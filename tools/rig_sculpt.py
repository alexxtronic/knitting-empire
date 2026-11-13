"""Put a sculpted body on a character's existing rig and animations.

Run headless:
  Blender -b tools/character_build/<id>/<id>.blend -P tools/rig_sculpt.py -- \
      <project_dir> <colored.ply> <out_id> [--faces 24000] [--tex 2048] [--height 1.9] [--render DIR]

Takes a body mesh, either a vertex-coloured .ply (image-to-sculpt plus tools/project_colors.py, or
tools/run_triposr.py; +Z up, facing -Y, any scale) or a textured .glb/.gltf (e.g. from tripo.ai: glTF's
+Y up and +Z front, which Blender turns into +Z up and facing -Y), and the character .blend made by
tools/build_character.py, then:

  1. scales the sculpt to the rig's height, feet on the ground, torso over the spine;
  2. decimates it to a game budget; a .ply is unwrapped and its vertex colours baked into one texture,
     a .glb keeps its own UVs and base-colour texture;
  3. aims a copy of the rig's arms along the sculpt's arms (found from the arm's outer outline;
     generated turnarounds stand in a wider A-pose than the rig), binds the mesh to it with automatic
     weights, then splits arm skin from body skin (by the gap between them seen from the front, else by
     distance along the surface) so a hand resting on a thigh doesn't move with the leg (or the arm sink
     into the body); an export with the arms held out (T-pose, best for clean armpits) needs no split;
     swings the arms back to the
     rig's rest pose and applies that, so the mesh now matches the real rig's rest pose; the head is made
     one rigid piece from the jaw line up (tools/rigid_head.py), so it doesn't bend when it turns;
  4. swaps the procedural body for the sculpt on the real rig (bones, animations and knitting
     props are untouched) and exports assets/<out_id>.glb, plus a turntable/pose check with --render.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, PLY, OUT_ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
FACES = int(argv[argv.index("--faces") + 1]) if "--faces" in argv else 24000
TEX = int(argv[argv.index("--tex") + 1]) if "--tex" in argv else 2048
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None
HEIGHT = float(argv[argv.index("--height") + 1]) if "--height" in argv else 0.0  # the sculpt's full height in metres when it is not the rig's: a tall hat or big hair puts the chin too low otherwise
COAT = float(argv[argv.index("--coat") + 1]) if "--coat" in argv else 0.0  # nearest-bone weights: jacket length below the hips
ARM_THICK = float(argv[argv.index("--arm-thick") + 1]) if "--arm-thick" in argv else 1.0  # fatten thin T-pose arms round their own line (a 'noodle' arm), shoulder to wrist; the hands keep their size
APRON = "--apron" in argv  # a long apron or skirt hangs free in front of the thighs: let its hem drape off the knees

scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == "ARMATURE")
old_body = next(o for o in scene.objects if o.type == "MESH" and o.parent == rig and o.name != "KnitProps")
bones = rig.data.bones
head_top = max((old_body.matrix_world @ Vector(c)).z for c in old_body.bound_box)
print("RIG", rig.name, "body", old_body.name, "height", round(head_top, 3))


def select_only(*objs):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    for o in scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


# ----------------------------------------------------------------------------- 1. import and place
TEXTURED = PLY.lower().endswith((".glb", ".gltf"))
if TEXTURED:
    bpy.ops.import_scene.gltf(filepath=PLY)
    parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in [o for o in bpy.context.selected_objects if o.type != "MESH"]:
        for c in o.children:
            c.matrix_parent_inverse = Matrix.Identity(4)
    select_only(*parts)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(parts) > 1:
        bpy.ops.object.join()
    hi = bpy.context.view_layer.objects.active
else:
    bpy.ops.wm.ply_import(filepath=PLY)
    hi = bpy.context.selected_objects[0]
hi.name = OUT_ID + "_hi"
V = np.array([v.co[:] for v in hi.data.vertices])
z0, h = V[:, 2].min(), V[:, 2].max() - V[:, 2].min()
s = (HEIGHT or head_top) / h
torso = V[(V[:, 2] - z0 > 0.59 * h) & (V[:, 2] - z0 < 0.73 * h)]
# x from the middle of the slice's outline, not the median vertex: dense detail on one side (a badge
# on the chest) would pull a median off the body's centre line
cx, cy = 0.5 * sum(np.percentile(torso[:, 0], (2, 98))), np.median(torso[:, 1])
hi.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-cx, -cy, -z0)))
hi.data.update()
print("SCULPT scale", round(s, 4), "verts", len(hi.data.vertices))

# ----------------------------------------------------------------------------- 2. game mesh + texture
def color_material(name, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    if image is None:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = hi.data.color_attributes[0].name
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(attr.outputs["Color"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.nodes.active = tex
    return m


def decimate(ob):
    select_only(ob)
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, FACES / len(ob.data.polygons))
    bpy.ops.object.modifier_apply(modifier="dec")


if TEXTURED:
    # a modelled mesh with its own UVs and texture: keep both. Weld the vertices glTF split along
    # every UV seam (UVs live on the face corners, so they survive), or the decimator can't collapse
    # across those seams and stops at several times the budget; then use the model's own base colour.
    lo = hi
    lo.name = lo.data.name = OUT_ID + "Mesh"
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    print("WELDED", n0, "->", len(bm.verts), "verts")
    bm.to_mesh(lo.data)
    bm.free()
    if lo.data.has_custom_normals:
        select_only(lo)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    decimate(lo)
    mats = list(lo.data.materials)
    lo.data.materials.clear()
    for i, m in enumerate(mats):
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        link = bsdf.inputs["Base Color"].links
        img = link[0].from_node.image if link and link[0].from_node.type == "TEX_IMAGE" else None
        if img is None:
            raise SystemExit("material %s has no base-colour texture" % m.name)
        img.name = OUT_ID + ("_albedo" if i == 0 else "_albedo%d" % i)
        if max(img.size) > TEX:
            img.scale(TEX, TEX)
        img.pack()  # embedded in the .glb; Godot extracts it on import as assets/<id>_<id>_albedo.png
        lo.data.materials.append(color_material(OUT_ID.capitalize() + ("" if i == 0 else str(i)), img))
        print("TEXTURE", img.name, tuple(img.size))
    for p in lo.data.polygons:
        p.use_smooth = True
    print("GAME MESH faces", len(lo.data.polygons))
else:
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = lo.data.name = OUT_ID + "Mesh"
    scene.collection.objects.link(lo)
    decimate(lo)
    # irons out the ripples a silhouette-only fit leaves
    sm = lo.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.use_volume_preserve = 6, 0.6, True
    bpy.ops.object.modifier_apply(modifier="smooth")
    for p in lo.data.polygons:
        p.use_smooth = True
    print("GAME MESH faces", len(lo.data.polygons))

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.new(OUT_ID + "_albedo", TEX, TEX)
    img.colorspace_settings.name = "sRGB"
    hi.data.materials.clear()
    hi.data.materials.append(color_material("bake_src"))
    lo.data.materials.clear()
    lo.data.materials.append(color_material(OUT_ID.capitalize(), img))

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.02
    scene.render.bake.max_ray_distance = 0.05
    scene.render.bake.margin = 6
    select_only(lo, hi)
    hi.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="EMIT")
    img.pack()  # embedded in the .glb; Godot extracts it on import as assets/<id>_<id>_albedo.png
    print("BAKED", img.name, TEX)
    bpy.data.objects.remove(hi)

# ----------------------------------------------------------------------------- 3. bind in the sculpt's pose
L = np.array([v.co[:] for v in lo.data.vertices])
temp = rig.copy()
temp.data = rig.data.copy()
temp.animation_data_clear()
scene.collection.objects.link(temp)
for pb in temp.pose.bones:  # the copy keeps whatever pose the rig was last evaluated in; start from rest
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
swing = {}
arm_r = {}  # side -> (radius, a point on the centre line, its direction) of a held-out arm
moved_joint = {}  # side -> how far the arm's joint was moved to the sculpt's shoulder (T-pose exports)
raised = {}  # side -> True when the sculpt's arm is held out (its angle found along the arm)
select_only(temp)
bpy.ops.object.mode_set(mode="EDIT")
eb = temp.data.edit_bones
seg = {}  # bone -> (head, tail) of the aimed copy, in the mesh's space


def fit_legs(ebs, fit):
    """Move a rig's leg bones to the sculpt's legs: fit is side -> (hip, knee, ankle) shifts."""
    for side, (dh, dk, da) in fit.items():
        ebs[side + "UpperLeg"].head += dh
        ebs[side + "UpperLeg"].tail += dk
        ebs[side + "LowerLeg"].head += dk
        ebs[side + "LowerLeg"].tail += da
        for b in ("Foot", "Toes"):
            ebs[side + b].transform(Matrix.Translation(da))


# the legs: the rig's stand where its own body's do, but a stocky sculpt's stand wider (Steve's shins
# are 10 cm further out) and every sculpt's stand behind the bones, since it is centred on its feet's
# box and the toes reach forward. A knee bending off its trouser leg shears it. Take each leg's line from
# its shin, where nothing hangs over it (an apron or a coat comes down to the knee), up to the knee; the
# hip joint goes half as far out, as a real stance splays from the pelvis.
leg_fit = {}
for side, sx in (("Left", 1), ("Right", -1)):
    ankle, knee, hip = (eb[side + b].head.copy() for b in ("Foot", "LowerLeg", "UpperLeg"))
    zs, cx, cy = [], [], []
    for z in np.arange(ankle.z + 0.06, ankle.z + 0.6 * (knee.z - ankle.z), 0.015):
        sl = L[(np.abs(L[:, 2] - z) < 0.006) & (L[:, 0] * sx > 0.015)]
        if len(sl) > 8:
            zs.append(z)
            cx.append((sl[:, 0].min() + sl[:, 0].max()) / 2)
            cy.append((sl[:, 1].min() + sl[:, 1].max()) / 2)
    if len(zs) < 4:
        continue
    fx, fy = np.polyfit(zs, cx, 1), np.polyfit(zs, cy, 1)
    at = lambda z: Vector((float(np.polyval(fx, z)), float(np.polyval(fy, z)), z))
    da = at(ankle.z) - ankle
    dk = at(knee.z) - knee
    da.z = dk.z = 0.0
    if max(da.length, dk.length) > 0.18:  # not a leg: leave the rig's
        print("LEGS", side, "fit out of range", tuple(round(v, 3) for v in dk))
        continue
    dh = Vector((dk.x * 0.5, dk.y, 0.0))
    leg_fit[side] = (dh, dk, da)
    print("LEGS", side, "knee moved by", tuple(round(v, 3) for v in dk), "ankle by", tuple(round(v, 3) for v in da))
fit_legs(eb, leg_fit)
for side, sx in (("Left", 1), ("Right", -1)):
    sh = eb[side + "UpperArm"].head.copy()
    tip = eb[side + "Hand"].tail.copy()
    # the arm's angle from its outer outline: in every slice between armpit and wrist the outermost
    # point on this side is the outside of the arm, whether the arm hangs wide (generated A-pose
    # turnarounds) or close against the body (tripo.ai). Fit a line through those points.
    pts = []
    for z in np.arange(sh.z - 0.12, tip.z + 0.12, -0.02):
        sl = L[(np.abs(L[:, 2] - z) < 0.008) & (L[:, 0] * sx > 0)]
        if len(sl):
            pts.append((z, (sl[:, 0] * sx).max()))
    pts = np.array(pts)
    slope = np.polyfit(pts[:, 0], pts[:, 1], 1)[0]  # outward x per metre of height
    want = Vector((-slope * sx, 0.0, -1.0)).normalized()
    # arms held out (a T-pose or wide A-pose export: the way to get clean armpits): horizontal slices
    # don't follow the arm, so take its line from the arm itself, everything well outside the shoulder
    # joint and within half a metre of its height, along its main direction
    far = L[(L[:, 0] * sx > sh.x * sx + 0.12) & (np.abs(L[:, 2] - sh.z) < 0.5)]
    if len(far) > 50 and (far[:, 0] * sx).max() > sh.x * sx + 0.35:
        # start from what is level with the shoulder (only the arm is out there), then take in the
        # points that lie along that line: a bag or an apron hanging below doesn't pull it down
        pick = far[np.abs(far[:, 2] - sh.z) < 0.15]
        for _ in range(3):
            c = pick.mean(axis=0)
            ax = np.linalg.svd(pick - c, full_matrices=False)[2][0]
            off = far - c
            pick = far[np.linalg.norm(off - np.outer(off @ ax, ax), axis=1) < 0.08]
        ax = ax if ax[0] * sx > 0 else -ax
        want = Vector((ax[0], 0.0, ax[2])).normalized()
        raised[side] = True
        # the shoulder joint: the rig's sits where its own body's shoulder is, and a slimmer sculpt's
        # arm then swings down from a point outside her shoulder and hangs away from the body with a
        # gap under it. Put the joint on the arm's line just inside the side of the torso under the arm.
        off = pick - c
        r = float(np.median(np.linalg.norm(off - np.outer(off @ ax, ax), axis=1)))
        arm_r[side] = (r, c.copy(), ax.copy())
        z_at = lambda x: c[2] + (x - c[0]) / ax[0] * ax[2]
        zp = z_at(sh.x) - r - 0.04
        under = L[(np.abs(L[:, 2] - zp) < 0.006) & (L[:, 0] * sx > 0) & (L[:, 0] * sx < sh.x * sx + 0.12)]
        if len(under) > 5:
            w = (under[:, 0] * sx).max()
            jx = (w - 0.02) * sx
            joint = Vector((jx, sh.y, z_at(jx)))
            shift = joint - sh
            # the whole collarbone moves with the joint: moving only its tail tips it steeply down
            # (Wren's joint is 13 cm under the rig's), and the loops' small shrugs then swing it up
            # into a hunch
            for b in ("Shoulder", "UpperArm", "LowerArm", "Hand"):
                eb[side + b].transform(Matrix.Translation(shift))
            # the rig's arm is Nora's length: stretch the chain about the joint to reach the sculpt's
            # fingertips, so the elbow bends where the sleeve's elbow is
            reach_ = (L - np.array(joint)) @ ax
            d_ = np.linalg.norm((L - c) - np.outer((L - c) @ ax, ax), axis=1)
            tips = reach_[(d_ < r + 0.08) & (reach_ > 0)]
            chain = (eb[side + "Hand"].tail - eb[side + "UpperArm"].head).length
            k_raw = float(np.percentile(tips, 99.5) / chain) if len(tips) else 1.0
            k = float(np.clip(k_raw, 0.7, 1.25))
            S_ = Matrix.Translation(joint) @ Matrix.Scale(k, 4) @ Matrix.Translation(-joint)
            for b in ("UpperArm", "LowerArm", "Hand"):
                eb[side + b].transform(S_)
            moved_joint[side] = (shift.copy(), k)
            print("SHOULDER", side, "arm radius", round(r, 3), "torso side", round(w, 3), "joint moved by",
                  tuple(round(v, 3) for v in shift), "arm length x", round(k, 3), "measured", round(k_raw, 3))
            if ARM_THICK != 1.0:
                # radial scale about the arm's line, eased in past the armpit and out before the wrist
                wrist = (eb[side + "LowerArm"].tail - eb[side + "UpperArm"].head).length
                along = (L - np.array(joint)) @ ax
                off = (L - c) - np.outer((L - c) @ ax, ax)
                d_ = np.linalg.norm(off, axis=1)
                f = (np.clip((along - 0.02) / 0.08, 0, 1) * np.clip((wrist + 0.01 - along) / 0.04, 0, 1)
                     * np.clip((r + 0.06 - d_) / 0.02, 0, 1) * (L[:, 0] * sx > joint.x * sx))
                f = f * f * (3 - 2 * f)
                L += off * ((ARM_THICK - 1.0) * f)[:, None]
                lo.data.vertices.foreach_set("co", L.astype(np.float32).ravel())
                lo.data.update()
                arm_r[side] = (r * ARM_THICK, c.copy(), ax.copy())
                print("ARM THICK", side, "x", ARM_THICK, "verts", int((f > 0).sum()))
            sh = joint
            tip = eb[side + "Hand"].tail.copy()
    have = Vector((tip.x - sh.x, 0.0, tip.z - sh.z)).normalized()
    ang = math.atan2(have.cross(want).y, have.dot(want))
    R = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh)
    for b in ("UpperArm", "LowerArm", "Hand"):
        eb[side + b].transform(R)
    swing[side] = (sh, -ang)
    print("ARM", side, "slices", len(pts), "rig", round(math.degrees(math.atan2(abs(have.x), -have.z)), 1),
          "sculpt", round(math.degrees(math.atan2(abs(want.x), -want.z)), 1), "deg")
for b in eb:
    seg[b.name] = (np.array((temp.matrix_world @ b.head)[:]), np.array((temp.matrix_world @ b.tail)[:]))
bpy.ops.object.mode_set(mode="OBJECT")

select_only(lo, temp)
lo.select_set(True)
bpy.context.view_layer.objects.active = temp
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("WEIGHTS groups", len(lo.vertex_groups))


def nearest_bone_weights():
    """Bone heat fails on meshes made of many loose shells (Tripo's Clean Topology: jacket, shirt and
    trousers as separate pieces), leaving skin bound to nothing and whole bones unbound. Then bind every
    vertex to its nearest bones instead: weight 1/d^5 to the bone segments, a left bone only on the left
    of the body and a right one only on the right, the three strongest kept, then smoothed along the mesh."""
    deform = [b.name for b in temp.data.bones if b.use_deform]
    D = np.stack([seg_dist(L, *seg[b]) for b in deform], axis=1)
    W = 1.0 / (D + 0.004) ** 5
    for k, b in enumerate(deform):
        if b.startswith("Left"):
            W[L[:, 0] < -0.01, k] = 0.0
        elif b.startswith("Right"):
            W[L[:, 0] > 0.01, k] = 0.0
    W[W < np.sort(W, axis=1)[:, -3][:, None]] = 0.0
    W /= W.sum(axis=1, keepdims=True)
    if COAT:  # a long jacket hangs from the hips: the thighs' pull fades out over COAT metres below the hip joint
        crotch = seg["LeftUpperLeg"][0][2]
        keep = np.clip((crotch - 0.02 - L[:, 2]) / COAT, 0.0, 1.0)
        hips = deform.index("Hips")
        for k, b in enumerate(deform):
            if b.endswith("UpperLeg"):
                W[:, hips] += W[:, k] * (1.0 - keep)
                W[:, k] *= keep
    E = np.array([e.vertices[:] for e in lo.data.edges])
    deg = np.bincount(E.ravel(), minlength=len(L)).astype(float)[:, None]
    for _ in range(4):  # smooth along the mesh, so joints bend rather than crease
        acc = np.zeros_like(W)
        np.add.at(acc, E[:, 0], W[E[:, 1]])
        np.add.at(acc, E[:, 1], W[E[:, 0]])
        W = np.where(deg > 0, 0.5 * W + 0.5 * acc / np.maximum(deg, 1), W)
    W[W < 0.01] = 0.0
    W /= W.sum(axis=1, keepdims=True)
    for b in deform:
        g = lo.vertex_groups.get(b) or lo.vertex_groups.new(name=b)
        g.remove(list(range(len(L))))
    for k, b in enumerate(deform):
        g = lo.vertex_groups[b]
        for i in np.where(W[:, k] > 1e-3)[0]:
            g.add([int(i)], float(W[i, k]), "REPLACE")


def heat_failed():
    names = {g.index: g.name for g in lo.vertex_groups}
    bare, used = 0, set()
    for v in lo.data.vertices:
        gs = [g for g in v.groups if g.weight > 1e-4]
        if not gs:
            bare += 1
        else:
            used.add(names[max(gs, key=lambda g: g.weight).group])
    limbs = [s + b for s in ("Left", "Right") for b in ("LowerLeg", "Foot", "LowerArm", "Hand")]
    missing = [b for b in limbs if b not in used]
    print("HEAT bare verts", bare, "of", len(L), "limb bones with no skin", missing)
    return bare > 0.005 * len(L) or bool(missing)



def seg_dist(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def geodesic(seeds, adj, n):
    import heapq
    d = np.full(n, np.inf)
    q = [(0.0, int(i)) for i in seeds]
    for _, i in q:
        d[i] = 0.0
    heapq.heapify(q)
    while q:
        di, i = heapq.heappop(q)
        if di > d[i]:
            continue
        for j, w in adj[i]:
            if di + w < d[j]:
                d[j] = di + w
                heapq.heappush(q, (di + w, j))
    return d


if "--nearest-weights" in argv or heat_failed():
    nearest_bone_weights()
    print("WEIGHTS nearest-bone fallback")

# Automatic weights go by straight-line distance, so where a hand rests against a thigh or a forearm
# against the sweater, skin of one is bound to the other's bones and the arm sinks into the body when
# it moves. Split arm skin from body skin by distance along the surface instead: grown out from the
# forearm on one side and from the thigh and waist on the other, the two only meet where they touch.
def gap_line(sx, sh_z, elbow, hand):
    """For every vertex: the x (times sx) that splits arm from body at its height, or nan.
    Found slice by slice from the surface itself: each triangle the slice plane crosses covers a stretch
    of x; walking in from the outermost point on this side, the first uncovered stretch wider than GAP,
    after at least 3 cm of arm, is the gap. Heights with no gap get the line from the heights around
    them; under the lowest gap (the fingertips) and above the armpit band, nan."""
    GAP = 0.006
    top = sh_z - 0.10
    bottom = hand[1][2] - 0.25    # a sculpt's hand often hangs below the rig's; below the fingers no gap is found
    lo.data.calc_loop_triangles()
    T = np.array([t.vertices[:] for t in lo.data.loop_triangles])
    U = L[:, 0] * sx
    tz = L[T, 2]
    zs, cs = [], []
    for z in np.arange(top, bottom, -0.01):
        cross = (tz.min(1) <= z) & (tz.max(1) >= z)
        iv = []
        for tri in T[cross]:
            pts = []
            for i, j in ((0, 1), (1, 2), (2, 0)):
                za, zb = L[tri[i], 2], L[tri[j], 2]
                if (za - z) * (zb - z) <= 0 and za != zb:
                    f = (z - za) / (zb - za)
                    pts.append(U[tri[i]] + f * (U[tri[j]] - U[tri[i]]))
            if pts and max(pts) > 0.0:
                iv.append((min(pts), max(pts)))
        if len(iv) < 6:
            continue
        iv.sort(key=lambda t: -t[1])
        o = iv[0][1]
        reach = iv[0][0]           # how far in the covered stretch from the outside goes so far
        found = None
        for a_, b_ in iv[1:]:
            if b_ < reach - GAP and reach < o - 0.03:
                found = (b_ + reach) / 2
                break
            reach = min(reach, a_)
        if found is not None and found > o - 0.30:
            zs.append(z)
            cs.append(found)
    cutv = np.full(len(L), np.nan)
    if len(zs) < 0.3 * (top - bottom) / 0.01:
        print("GAP", "few gaps", len(zs), "- falling back to the surface walk")
        return cutv
    zs, cs = np.array(zs[::-1]), np.array(cs[::-1])
    # a gap far off the trend is a fold in the clothes, not the arm's edge: drop it and refit
    for _ in range(2):
        fit = np.polyval(np.polyfit(zs, cs, 2), zs)
        keep = np.abs(cs - fit) < 0.03
        zs, cs = zs[keep], cs[keep]
    band = (L[:, 2] >= zs.min() - 0.03) & (L[:, 2] <= top + 0.02)
    cutv[band] = np.interp(L[band, 2], zs, cs)
    print("GAP", "slices", len(zs), "of", int((top - bottom) / 0.01), "cut x", np.round(np.percentile(cs, [5, 50, 95]), 3),
          "z", round(float(zs.min()), 2), "-", round(float(zs.max()), 2))
    return cutv


n = len(L)
adj = [[] for _ in range(n)]
for e in lo.data.edges:
    i, j = e.vertices
    w = float(np.linalg.norm(L[i] - L[j]))
    adj[i].append((j, w))
    adj[j].append((i, w))
gidx = {g.name: g.index for g in lo.vertex_groups}
for side, sx in (("Left", 1), ("Right", -1)):
    arm_bones = [side + b for b in ("Shoulder", "UpperArm", "LowerArm", "Hand")]
    if raised.get(side):
        # nothing touches an arm held out, so the automatic weights stand, except at the shoulder: skin
        # outside the shoulder joint (the sleeve's top, the deltoid) kept part body weight and stayed up
        # when the arm came down from the T-pose, flaring the sleeve. Out there it is all arm, blended
        # over 8 cm across the joint; the arm hangs level, so only skin near the shoulder's height counts.
        shj = seg[side + "UpperArm"][0]
        # near the arm: within its radius (plus 5 cm) of the arm's own centre line, as measured, out
        # from just inside the joint; the rig's bones are shorter and don't run down its middle
        r_, c_, ax_ = arm_r[side]
        off_ = L - c_
        d_arm = np.linalg.norm(off_ - np.outer(off_ @ ax_, ax_), axis=1)
        near = (d_arm < r_ + 0.05) & (L[:, 0] * sx > shj[0] * sx - 0.06)
        t = np.clip((L[:, 0] * sx - (shj[0] * sx - 0.03)) / 0.08, 0.0, 1.0)
        t[np.abs(L[:, 2] - shj[2]) > 0.22] = 0.0
        t[(L[:, 0] * sx < 0.0) | ~near] = 0.0
        gi_arm = {gidx[b] for b in arm_bones[1:] if b in gidx}
        # hair over the shoulder (or a collar, a bag strap) lies near the arm in the T-pose and took
        # some of its weight; above the joint and away from the arm, it belongs with the body
        # only round the shoulder itself: a level arm's hand and fingers are above the joint and off
        # the line too (the men's T-poses), and must stay on the arm
        along = (L - np.array(shj)) @ ax_
        loose = ~near & (L[:, 2] > shj[2] - 0.05) & (L[:, 0] * sx > 0.0) & (along < 0.10)
        # but a sleeve is the arm's own surface: a puffed shoulder (Giorgio) or a short sleeve's top
        # (Steve), the shirt over a broad shoulder, are all joined to the arm, while hair only lies on it
        # (its own shell, or joined only far round by the scalp). Keep whatever the surface reaches
        # within 30 cm of the upper arm.
        seeds_ = np.where((d_arm < r_ + 0.08) & (along > 0.10) & (along < 0.25))[0]
        if len(seeds_):
            sleeve = geodesic(seeds_, adj, n) < 0.30
            print("SPLIT", side, "sleeve kept on the arm", int((loose & sleeve).sum()))
            loose &= ~sleeve
            # and the sleeve's top swings with the arm like the skin under it
            t = np.clip((L[:, 0] * sx - (shj[0] * sx - 0.03)) / 0.08, 0.0, 1.0)
            t[np.abs(L[:, 2] - shj[2]) > 0.22] = 0.0
            t[(L[:, 0] * sx < 0.0) | ~(near | sleeve)] = 0.0
        freed = 0
        for i in np.where(loose)[0]:
            v = lo.data.vertices[i]
            drop = [g.group for g in v.groups if g.group in gi_arm and g.weight > 0.0]
            for gi in drop:
                lo.vertex_groups[gi].remove([int(i)])
            if drop:
                freed += 1
                if not any(g.weight > 1e-4 for g in v.groups):
                    b = min(["Neck", "UpperChest", side + "Shoulder"], key=lambda b: seg_dist(L[i:i + 1], *seg[b])[0])
                    lo.vertex_groups[gidx[b]].add([int(i)], 1.0, "REPLACE")
        print("SPLIT", side, "hair and collar off the arm", freed)
        changed = 0
        for i in np.where(t > 0.0)[0]:
            v = lo.data.vertices[i]
            ws = [(g.group, g.weight) for g in v.groups if g.weight > 0.0]
            wa = sum(w for gi, w in ws if gi in gi_arm)
            wb = sum(w for gi, w in ws if gi not in gi_arm)
            if wa + wb <= 0.0 or wa / (wa + wb) >= t[i]:
                continue
            if wa <= 0.0:   # no arm weight yet: the nearest arm bone gets the share
                b = min(arm_bones[1:], key=lambda b: seg_dist(L[i:i + 1], *seg[b])[0])
                lo.vertex_groups[gidx[b]].add([int(i)], 1e-6, "REPLACE")
                ws.append((gidx[b], 1e-6))
                wa = 1e-6
            tot = wa + wb
            for gi, w in ws:
                nw = w / wa * t[i] * tot if gi in gi_arm else w / wb * (1.0 - t[i]) * tot if wb > 0 else 0.0
                lo.vertex_groups[gi].add([int(i)], max(nw, 0.0), "REPLACE")
            changed += 1
        print("SPLIT", side, "arm held out: no split; shoulder skin moved to the arm", changed)
        continue

    sh_z = seg[side + "UpperArm"][0][2]
    wrist = seg[side + "Hand"][0]
    elbow = seg[side + "LowerArm"][0]
    d_fore = seg_dist(L, elbow, wrist)
    d_hand = seg_dist(L, *seg[side + "Hand"])
    d_thigh = seg_dist(L, *seg[side + "UpperLeg"])
    side_ok = L[:, 0] * sx > 0.02
    seeds_arm = np.where(side_ok & (d_fore < 0.05) & (L[:, 2] > wrist[2] + 0.06))[0]
    seeds_body = np.where(side_ok & (((d_thigh < 0.07) & (L[:, 2] < seg[side + "Hand"][1][2] - 0.03))
                                     | ((np.abs(L[:, 0]) < 0.05) & (np.abs(L[:, 2] - elbow[2]) < 0.1))))[0]
    # the upper arm: in tripo's pose it is often pressed against the body, its inner side merged with the
    # torso's, so the forearm alone can't claim the sleeve: half the sleeve went with the arm and half
    # stayed, and it tore when the arm lifted. Find the whole arm at each height between armpit and
    # elbow instead: its outer edge is the outermost point on this side, its thickness the front-to-back
    # depth there, and a round arm that thick fits inside that edge. That tube is arm; the torso inside it is body.
    upper = side_ok & (L[:, 2] < sh_z - 0.04) & (L[:, 2] > elbow[2] - 0.02)
    zs, oo, dd, yy = [], [], [], []
    for z in np.arange(elbow[2] - 0.02, sh_z - 0.03, 0.01):
        sl = side_ok & (np.abs(L[:, 2] - z) < 0.006)
        if sl.sum() < 8:
            continue
        o = (L[sl, 0] * sx).max()
        rim = sl & (L[:, 0] * sx > o - 0.012)
        y0, y1 = L[rim, 1].min(), L[rim, 1].max()
        zs.append(z); oo.append(o); dd.append(min(y1 - y0, 0.16)); yy.append((y0 + y1) / 2)
    if len(zs) > 3:
        o = np.interp(L[:, 2], zs, oo)
        dia = np.interp(L[:, 2], zs, dd)
        yc = np.interp(L[:, 2], zs, yy)
        cx = o - dia / 2
        tube = upper & ((L[:, 0] * sx - cx) ** 2 + (L[:, 1] - yc) ** 2 < (dia / 2 + 0.006) ** 2)
        seeds_arm = np.union1d(seeds_arm, np.where(tube)[0])
        seeds_body = np.union1d(seeds_body, np.where(upper & (L[:, 0] * sx < o - dia - 0.015))[0])
        print("UPPER ARM", side, "diameter", np.round(np.percentile(dd, [10, 50, 90]), 3), "tube verts", int(tube.sum()))
    if "--wide-body" in argv:
        # a stout body's apron or overalls are further than 7 cm from the thigh bone, so the thigh finds no
        # seeds on them and the arm's skin floods the hip: the body's core (inside the wrist line, knee to
        # armpit) is body too, and thick forearms need a wider reach to be found at all
        knee_z = seg[side + "LowerLeg"][0][2]
        core = side_ok & (np.abs(L[:, 0]) < 0.6 * abs(wrist[0])) & (L[:, 2] > knee_z) & (L[:, 2] < sh_z - 0.08)
        seeds_body = np.union1d(seeds_body, np.where(core)[0])
        seeds_arm = np.where(side_ok & (d_fore < 0.085) & (L[:, 2] > wrist[2] + 0.06) & (np.abs(L[:, 0]) > 0.75 * abs(elbow[0])))[0]
    if not len(seeds_arm) or not len(seeds_body):
        print("SPLIT", side, "skipped: no seeds")
        continue
    ga, gb = geodesic(seeds_arm, adj, n), geodesic(seeds_body, adj, n)
    zone = side_ok & (L[:, 2] < sh_z - 0.08)
    # Seen from the front there is daylight between the arm and the body at most heights: at each
    # height, everything outside the gap is arm. Where the hand or forearm touches the clothes there is
    # no gap; the cut line carries on from the heights above and below. The walk along the surface
    # (ga < gb) is only used where no gap was found anywhere.
    cut = gap_line(sx, sh_z, elbow, seg[side + "Hand"])
    arm_side = np.where(np.isnan(cut), ga < gb, L[:, 0] * sx > cut)
    is_arm = zone & arm_side
    # islands: a patch on the inside of the forearm that fell on the body's side of the line, with arm
    # all round it, would stay behind at the hip as a sliver. Body skin must join the body (the thigh
    # and waist seeds) through body skin, arm skin the forearm through arm skin; flip whatever doesn't.
    def reach(seeds, member):
        seen = np.zeros(n, bool)
        st = [int(i) for i in seeds if member[i]]
        seen[st] = True
        while st:
            i = st.pop()
            for j, _ in adj[i]:
                if member[j] and not seen[j]:
                    seen[j] = True
                    st.append(j)
        return seen
    body_ok = reach(seeds_body, zone & ~is_arm)
    stray_body = zone & ~is_arm & ~body_ok
    is_arm |= stray_body
    arm_ok = reach(np.where(is_arm & (d_fore < 0.12))[0], is_arm)
    stray_arm = is_arm & ~arm_ok
    is_arm &= ~stray_arm
    print("ISLANDS", side, "body->arm", int(stray_body.sum()), "arm->body", int(stray_arm.sum()))
    is_body = zone & ~is_arm
    moved = 0
    for i in np.where(zone)[0]:
        v = lo.data.vertices[i]
        keep_arm = bool(is_arm[i])
        # read the groups first: removing one while walking v.groups shifts the rest under the loop
        drop = [g.group for g in v.groups if (lo.vertex_groups[g.group].name in arm_bones) != keep_arm and g.weight > 0.0]
        for gi in drop:
            lo.vertex_groups[gi].remove([int(i)])
            moved += 1
        if not any(g.weight > 1e-4 for g in v.groups):  # stripped bare: give it the nearest allowed bone
            names = arm_bones[1:] if keep_arm else ["Hips", side + "UpperLeg", "Spine"]
            best = min(names, key=lambda b: seg_dist(L[i:i + 1], *seg[b])[0])
            lo.vertex_groups[gidx[best]].add([int(i)], 1.0, "REPLACE")
    print("SPLIT", side, "arm verts", int(is_arm.sum()), "body verts", int(is_body.sum()), "weights moved", moved,
          "hand verts", int((is_arm & (d_hand < 0.06)).sum()))

if APRON:
    # an apron in front of the thighs rode them up level when he sat and stuck out past his knees like
    # a tray. Cloth that stands off the front of the thigh hands its lower part to the shin, from the
    # middle of the thigh down to the knee (at most 70%), so the hem hangs down over the knees seated
    # and swings a little with the shins walking.
    freed = 0
    for side, sx in (("Left", 1), ("Right", -1)):
        hip, knee = (np.array(p) for p in seg[side + "UpperLeg"])
        th = knee - hip
        u = np.clip((L - hip) @ th / (th @ th), 0.0, 1.5)
        rad = np.linalg.norm(L - (hip + np.outer(u, th)), axis=1)
        gu, gl = gidx[side + "UpperLeg"], gidx[side + "LowerLeg"]
        wu = np.zeros(len(L))
        for i in np.where((u > 0.3) & (u < 1.3) & (L[:, 0] * sx > -0.03))[0]:
            for g in lo.data.vertices[i].groups:
                if g.group == gu:
                    wu[i] = g.weight
        legs = (wu > 0.5) & (u > 0.3) & (u < 1.0)
        if not legs.any():
            continue
        # the trouser's radius round the thigh, taken behind it where no apron hangs
        back = legs & ((L[:, 1] - (hip[1] + u * th[1])) > 0.0)
        leg_r = float(np.median(rad[back])) if back.sum() > 20 else float(np.percentile(rad[legs], 15))
        front = (L[:, 1] - (hip[1] + u * th[1])) < -0.6 * leg_r
        cloth = (wu > 0.0) & front & (rad > leg_r + 0.03)
        share = np.clip((u - 0.5) / 0.5, 0.0, 1.0) * 0.7
        share[~cloth] = 0.0
        # soften its edge over the surface, so the cloth beside it bends with it rather than tearing
        has = wu > 0.0
        for _ in range(4):
            nb = np.array([np.mean([share[j] for j, _ in adj[i]]) if adj[i] else share[i] for i in range(len(L))])
            share = np.where(has, np.maximum(share, 0.5 * share + 0.5 * nb), 0.0)
        for i in np.where(has & (share > 0.01))[0]:
            move = wu[i] * share[i]
            lo.vertex_groups[gu].add([int(i)], float(wu[i] - move), "REPLACE")
            lo.vertex_groups[gl].add([int(i)], float(move), "ADD")
            freed += 1
        print("APRON", side, "thigh radius", round(leg_r, 3), "cloth verts to the shin", int((cloth).sum()), "with the blend", int((has & (share > 0.01)).sum()))

# the seat: the automatic weights hang the buttocks (and a jacket's tail over them) on the thighs,
# so a knee raised in a run swung them out behind in a balloon. Behind the hip joint the pelvis carries
# them; the thigh's pull comes back over 20 cm below the joint, and fades in over 6 cm round the side.
hips_g = gidx["Hips"]
for side, sx in (("Left", 1), ("Right", -1)):
    hip = np.array(seg[side + "UpperLeg"][0])
    gu = gidx[side + "UpperLeg"]
    keep = np.clip((hip[2] - 0.04 - L[:, 2]) / 0.20, 0.15, 1.0)
    behind = np.clip((L[:, 1] - hip[1] + 0.02) / 0.06, 0.0, 1.0)
    m = 1.0 - behind * (1.0 - keep)
    zone = (m < 0.999) & (L[:, 0] * sx > -0.02) & (L[:, 2] > hip[2] - 0.30) & (L[:, 2] < hip[2] + 0.20)
    moved = 0
    for i in np.where(zone)[0]:
        w = next((g.weight for g in lo.data.vertices[i].groups if g.group == gu), 0.0)
        if w <= 0.0:
            continue
        lo.vertex_groups[gu].add([int(i)], float(w * m[i]), "REPLACE")
        lo.vertex_groups[hips_g].add([int(i)], float(w * (1.0 - m[i])), "ADD")
        moved += 1
    print("SEAT", side, "verts eased onto the pelvis", moved)

# elbows and wrists: bone heat spreads the upper arm and forearm over each other for 15 cm or more, so a bent
# arm curved like a hose from shoulder to hand (Sabrina working). A real arm is two straight segments with a
# joint between: each vertex's arm weight goes to one bone, blended only within a few centimetres of the
# elbow and the wrist. The arm's share against the shoulder and body is kept as it was.
def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


ELBOW_BAND, WRIST_BAND = 0.035, 0.02
for side, sx in (("Left", 1), ("Right", -1)):
    names = [side + b for b in ("UpperArm", "LowerArm", "Hand")]
    if any(n not in gidx for n in names):
        continue
    gis = [gidx[n] for n in names]
    sh_, el_ = (np.array(p) for p in seg[names[0]])
    wr_ = np.array(seg[names[2]][0])
    du = (el_ - sh_) / np.linalg.norm(el_ - sh_)
    dl = (wr_ - el_) / np.linalg.norm(wr_ - el_)
    de = du + dl
    de /= np.linalg.norm(de)
    W3 = np.zeros((len(L), 3))
    for i, v in enumerate(lo.data.vertices):
        for g in v.groups:
            if g.group in gis:
                W3[i, gis.index(g.group)] = g.weight
    a = W3.sum(axis=1)
    on = np.where(a > 1e-4)[0]
    t_el = smoothstep(((L[on] - el_) @ de + ELBOW_BAND) / (2 * ELBOW_BAND))
    t_wr = smoothstep(((L[on] - wr_) @ dl + WRIST_BAND) / (2 * WRIST_BAND))
    new = np.stack([1 - t_el, t_el * (1 - t_wr), t_el * t_wr], axis=1) * a[on, None]
    for n_, i in enumerate(on):
        for k_, gi in enumerate(gis):
            if new[n_, k_] > 1e-4:
                lo.vertex_groups[gi].add([int(i)], float(new[n_, k_]), "REPLACE")
            elif W3[i, k_] > 0.0:
                lo.vertex_groups[gi].remove([int(i)])
    print("JOINTS", side, "arm verts", len(on), "elbow band", ELBOW_BAND * 2, "m, wrist band", WRIST_BAND * 2, "m")

# the head: one rigid piece from the jaw line up, turning on a short band of neck (tools/rigid_head.py)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rigid_head  # noqa: E402
rigid_head.make_rigid(lo, temp)

# swing the arms back to the real rig's rest angle and bake that into the mesh
select_only(temp)
bpy.ops.object.mode_set(mode="POSE")
for side, (sh, ang) in swing.items():
    pb = temp.pose.bones[side + "UpperArm"]
    pb.matrix = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh) @ pb.bone.matrix_local
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")
select_only(lo)
mod = next(m for m in lo.modifiers if m.type == "ARMATURE")
bpy.ops.object.modifier_apply(modifier=mod.name)
lo.parent = None
lo.matrix_world = Matrix.Identity(4)
bpy.data.objects.remove(temp)

# ----------------------------------------------------------------------------- 4. onto the real rig, export
bpy.data.objects.remove(old_body)
if moved_joint:  # the real rig's arms move to the same shoulder joints the mesh now hangs from
    select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for side, (shift, k) in moved_joint.items():
        reb = rig.data.edit_bones
        for b in ("Shoulder", "UpperArm", "LowerArm", "Hand"):
            reb[side + b].transform(Matrix.Translation(shift))
        j_ = reb[side + "UpperArm"].head.copy()
        S_ = Matrix.Translation(j_) @ Matrix.Scale(k, 4) @ Matrix.Translation(-j_)
        for b in ("UpperArm", "LowerArm", "Hand"):
            reb[side + b].transform(S_)
    bpy.ops.object.mode_set(mode="OBJECT")
if leg_fit:  # the real rig's legs move to the same places
    select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    fit_legs(rig.data.edit_bones, leg_fit)
    bpy.ops.object.mode_set(mode="OBJECT")
lo.parent = rig
am = lo.modifiers.new("Armature", "ARMATURE")
am.object = rig
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

assets = os.path.join(PROJECT, "assets")
build = os.path.join(PROJECT, "tools", "character_build", OUT_ID)
os.makedirs(build, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, OUT_ID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(assets, OUT_ID + ".glb"), export_format="GLB", export_apply=True,
                          export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                          export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
print("EXPORTED", os.path.join(assets, OUT_ID + ".glb"), "faces", len(lo.data.polygons))

# ----------------------------------------------------------------------------- check renders
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 480, 720
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam

    rig.animation_data.use_nla = False  # the stored NLA tracks would blend every loop together

    def shoot(path, yaw_deg, action=None, frame=0):
        rig.animation_data.action = bpy.data.actions[action] if action else None
        if action is None:
            for pb in rig.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
        scene.frame_set(frame)
        a = math.radians(yaw_deg)
        cam.location = (3.2 * math.sin(a), -3.2 * math.cos(a), 1.0)
        cam.rotation_euler = (math.radians(88), 0, a)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    for yaw in (0, 45, 90, 180, 270):
        shoot(os.path.join(RENDER, f"turn_{yaw:03d}.png"), yaw)
    for act in ("Idle", "Walk", "SitKnit", "Talk", "Work"):
        rng = bpy.data.actions[act].frame_range
        shoot(os.path.join(RENDER, f"pose_{act}.png"), 30, act, int((rng[0] + rng[1]) / 2))
    print("RENDERED", RENDER)
