"""Re-weight a long skirt or dress on a rigged character so it swings as one bell instead of two trouser legs.

Mixamo's auto-rigging skins a long skirt like trousers: the left half follows the left leg and the right half
the right, split sharply down the middle, and the hem follows the feet. On a walk the skirt then tears open at
the front and back seams and folds round the back leg every time a heel lifts. This keeps every skirt vertex's
hip and spine weights as they are and shares out its leg and foot weight again:

  * left against right goes by how far the vertex is from the middle (x), blended over --band metres each side
    of it, so the front and back of the skirt (and an apron) move with both legs;
  * none of it follows a foot; above the knee it follows the thighs as before, and below the knee it slides
    toward the shins, at most --shin of it at the hem, so the hem still covers the boots as they step;
  * the boots and anything near a shin (within --keep metres of the shin bone's line) keep their weights, with
    a 4 cm blend so nothing tears where the skirt's underside meets a boot.

Run it on the character's .blend after tools/import_mixamo.py and before tools/retarget_anims.py (which
exports the GLB) and tools/add_eyes.py:
  Blender -b tools/character_build/<id>/<id>.blend -P tools/skirt_weights.py -- <project_dir> <id> \
      [--hem Z] [--band 0.12] [--shin 0.35] [--keep 0.09]

--hem is the height of the skirt's lower edge at rest (default: where the body suddenly widens above the
boots). It saves the .blend in place.
"""
import bpy, os, sys
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, ID = os.path.abspath(argv[0]), argv[1]


def opt(name, default):
    return float(argv[argv.index(name) + 1]) if name in argv else default


BAND, SHIN, KEEP = opt("--band", 0.12), opt("--shin", 0.35), opt("--keep", 0.09)

rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = max((o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig), key=lambda o: len(o.data.vertices))
B = rig.data.bones
mw = np.array(body.matrix_world)
co = np.array([v.co[:] for v in body.data.vertices]) @ mw[:3, :3].T + mw[:3, 3]
names = [g.name for g in body.vertex_groups]
gi = {n: i for i, n in enumerate(names)}
for side in ("Left", "Right"):
    for b in ("UpperLeg", "LowerLeg"):
        if side + b not in gi:
            body.vertex_groups.new(name=side + b)
            gi[side + b] = len(names)
            names.append(side + b)
W = np.zeros((len(co), len(names)))
for v in body.data.vertices:
    for g in v.groups:
        W[v.index, g.group] = g.weight


def cols(*parts):
    return [i for n, i in gi.items() if any(p in n for p in parts)]


LEG, ARM = cols("UpperLeg", "LowerLeg", "Foot", "Toes"), cols("Shoulder", "Arm", "Hand")
hips_z = B["Hips"].head_local.z
knee_z = (B["LeftLowerLeg"].head_local.z + B["RightLowerLeg"].head_local.z) / 2
if "--hem" in argv:
    hem_z = opt("--hem", 0.0)
else:   # the skirt's edge: the lowest 1 cm slice at least 1.3 times as wide as the slice under it
    hem_z = None
    for z in np.arange(0.02, knee_z, 0.01):
        lo = co[(co[:, 2] >= z - 0.02) & (co[:, 2] < z - 0.01), 0]
        hi = co[(co[:, 2] >= z) & (co[:, 2] < z + 0.01), 0]
        if len(lo) and len(hi) and np.ptp(hi) > 1.3 * np.ptp(lo):
            hem_z = z
            break
    assert hem_z is not None, "no skirt edge found above the boots: pass --hem"


def to_line(p, a, b):
    """Distance from each point to the segment a..b."""
    d = b - a
    t = np.clip((p - a) @ d / (d @ d), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * d), axis=1)


shin = np.minimum(*(to_line(co, np.array(B[s + "LowerLeg"].head_local), np.array(B[s + "Foot"].tail_local))
                    for s in ("Left", "Right")))
leg_w = W[:, LEG].sum(1)
skirt = (co[:, 2] > hem_z - 0.01) & (co[:, 2] < hips_z + 0.05) & (leg_w > 1e-4) & (W[:, ARM].sum(1) < 0.05)
mix = np.clip((shin - KEEP) / 0.04, 0, 1) * skirt     # 0 keeps the old weights, 1 takes the new
left = np.clip((co[:, 0] / BAND + 1) / 2, 0, 1)
left = left * left * (3 - 2 * left)                    # smoothstep across the middle
upper_old = W[:, [gi["LeftUpperLeg"], gi["RightUpperLeg"]]].sum(1)
lower_frac = np.where(leg_w > 0, 1 - upper_old / np.maximum(leg_w, 1e-9), 0)
# above the knee keep the old thigh/shin split; below it, toward the shins, SHIN of it at the hem
below = np.clip((knee_z - co[:, 2]) / max(knee_z - hem_z, 1e-3), 0, 1)
lower_frac = np.where(co[:, 2] < knee_z, SHIN * below, np.minimum(lower_frac, 0.5))
new = W.copy()
new[:, LEG] = 0
for side, share in (("Left", left), ("Right", 1 - left)):
    new[:, gi[side + "UpperLeg"]] = leg_w * share * (1 - lower_frac)
    new[:, gi[side + "LowerLeg"]] = leg_w * share * lower_frac
W2 = W * (1 - mix[:, None]) + new * mix[:, None]

changed = np.nonzero(mix > 0)[0]
groups = body.vertex_groups
for c in LEG:
    g = groups[names[c]]
    for i in changed:
        w = float(W2[i, c])
        if w > 1e-4:
            g.add([int(i)], w, "REPLACE")
        else:
            g.remove([int(i)])
foot_before = W[changed][:, cols("Foot", "Toes")].sum(1).mean() if len(changed) else 0
print(f"SKIRT {ID}: hem {hem_z:.2f} m, knee {knee_z:.2f}, hips {hips_z:.2f}; {len(changed)} vertices re-weighted "
      f"({int((mix == 1).sum())} fully), their foot weight {foot_before:.2f} -> 0")
bpy.ops.wm.save_mainfile()
print("SAVED", bpy.data.filepath)
