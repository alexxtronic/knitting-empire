"""Repair a Mixamo rig whose shoulder joints were set too low (Giorgio).

Mixamo's auto-rigger expects a T-pose. Giorgio went up with his arms hanging down, so it put each shoulder
joint out on his sleeve, 11 cm under the real one: the upper-arm bone came out 7 cm long, the collar bone
26 cm long and sloping down, the sleeve was skinned to the collar bone, and the arm swung from the sleeve as
one stiff piece. The elbow, wrist, hand, body and legs it got right.

  Blender -b tools/character_build/<id>/<id>.blend -P tools/fix_shoulders.py -- <project_dir> <id> [--drop m] [--inset m]

It:
  1. finds each real shoulder joint from the mesh: DROP under the top of the shoulder and INSET in from the
     shoulder's outer edge at that height, at the arm's own depth;
  2. moves the upper-arm bone's head, and the collar bone's tail with it, to that point; the elbow and
     everything below it stay where Mixamo put them;
  3. hands the collar bone's weights on the sleeve and the shoulder cap over to the upper arm: whole from the
     joint outward and from 8 cm under it down, blending back to the collar bone over the 9 cm toward the neck.
     Every other weight is left as Mixamo made it, so each vertex's weights still add up to what they did;
  4. saves the blend.

The loops no longer fit the moved bones: run tools/retarget_anims.py next (the library loops, then SitKnit
with --same-bones), then tools/add_eyes.py and tools/render_portraits.py, and refit the character's sweater.

A side whose upper-arm bone is already MIN_UPPER of the body's height or longer is left alone, so running it
twice changes nothing.
"""
import bpy, os, sys
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, OUT_ID = os.path.abspath(argv[0]), argv[1]
DROP = float(argv[argv.index("--drop") + 1]) if "--drop" in argv else 0.055     # the joint sits this far under the top of the shoulder
INSET = float(argv[argv.index("--inset") + 1]) if "--inset" in argv else 0.07   # and this far in from its outer edge
BLEND = 0.09        # the collar bone keeps what is this far inboard of the joint; between, the two share
UNDER = (0.02, 0.08)  # from this far under the joint the collar bone lets go, by this far it has let go whole
MIN_UPPER = 0.085   # an upper-arm bone shorter than this share of the height is one Mixamo set too low

rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
body = max((o for o in bpy.context.scene.objects if o.type == "MESH" and o.parent == rig), key=lambda o: len(o.data.vertices))
me = body.data
mw = np.array(rig.matrix_world.inverted() @ body.matrix_world)      # mesh -> armature space
co = np.empty(len(me.vertices) * 3)
me.vertices.foreach_get("co", co)
P = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
H = float(P[:, 2].max() - P[:, 2].min())
gi = {g.name: g.index for g in body.vertex_groups}


def weights(name):
    w = np.zeros(len(me.vertices))
    if name in gi:
        i = gi[name]
        for v in me.vertices:
            for g in v.groups:
                if g.group == i:
                    w[v.index] = g.weight
    return w


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


head = (weights("Head") + weights("Neck")) > 0.3
plan = []
for side, sx in (("Left", 1.0), ("Right", -1.0)):
    B = rig.data.bones
    s0 = np.array(B[side + "UpperArm"].head_local)
    el = np.array(B[side + "LowerArm"].head_local)
    upper = float(np.linalg.norm(el - s0))
    if upper >= MIN_UPPER * H:
        print("SHOULDER %s %s: upper arm %.3f m (%.3f of the height), left alone" % (OUT_ID, side, upper, upper / H))
        continue
    X = P[:, 0] * sx
    near = (X > 0.02) & ~head & (np.abs(P[:, 1] - s0[1]) < 0.14)

    def top_at(x):
        m = near & (np.abs(X - x) < 0.012)
        return float(P[m, 2].max())

    x = float(s0[0] * sx)
    for _ in range(4):      # the outer edge depends on the height and the height on the edge: a few rounds settle it
        z = top_at(x) - DROP
        slab = (X > 0.02) & ~head & (np.abs(P[:, 2] - z) < 0.012)
        outer = float(X[slab].max())
        x = outer - INSET
    z = top_at(x) - DROP
    arm = slab & (X > x - 0.03)
    y = float((P[arm, 1].min() + P[arm, 1].max()) / 2.0)
    s1 = np.array((x * sx, y, z))
    plan.append((side, sx, s0, s1, el))
    print("SHOULDER %s %s: joint %s -> %s (top of the shoulder %.3f, outer edge %.3f); upper arm %.3f -> %.3f m"
          % (OUT_ID, side, tuple(round(float(v), 3) for v in s0), tuple(round(float(v), 3) for v in s1), z + DROP, outer,
             upper, float(np.linalg.norm(el - s1))))

if plan:
    # ---- 2. the bones
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for side, sx, s0, s1, el in plan:
        eb[side + "UpperArm"].head = Vector(s1)
        eb[side + "Shoulder"].tail = Vector(s1)
    bpy.ops.object.mode_set(mode="OBJECT")

    # ---- 3. the sleeve and the shoulder cap go from the collar bone to the upper arm
    for side, sx, s0, s1, el in plan:
        w_c = weights(side + "Shoulder")
        X = P[:, 0] * sx
        gx = smooth((X - (s1[0] * sx - BLEND)) / BLEND)
        gz = smooth((s1[2] - UNDER[0] - P[:, 2]) / (UNDER[1] - UNDER[0]))
        g = np.maximum(gx, gz)
        g[X < 0.0] = 0.0
        moved = w_c * g
        idx = np.nonzero(moved > 1e-5)[0]
        vc, vu = body.vertex_groups[side + "Shoulder"], body.vertex_groups[side + "UpperArm"]
        w_u = weights(side + "UpperArm")
        for i in idx:
            i = int(i)
            keep = float(w_c[i] - moved[i])
            if keep > 1e-5:
                vc.add([i], keep, "REPLACE")
            else:
                vc.remove([i])
            vu.add([i], float(w_u[i] + moved[i]), "REPLACE")
        print("SLEEVE %s %s: %d vertices, %.1f of the collar bone's %.1f weight handed to the upper arm"
              % (OUT_ID, side, len(idx), float(moved.sum()), float(w_c.sum())))

    bpy.ops.wm.save_mainfile()
    print("SAVED", bpy.data.filepath)
else:
    print("NOTHING TO DO", OUT_ID)
