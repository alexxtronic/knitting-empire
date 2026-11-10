"""Make a skinned character's head one rigid piece that swivels on a short band of neck.

Automatic weights share the face out between Head, Neck and the shoulders (the jaw and beard partly
follow the neck, the collar partly follows the head), so when the head turns to look at someone the
face shears. This rebinds the skin:

  - everything from the chin up follows the Head bone alone, so the face, hair and ears never bend;
  - over a band of neck under the chin the head's hold fades back to the weights it had before (neck,
    upper chest, shoulders), so the turn happens there, the way a neck twists;
  - below that band (the collar and shoulders) nothing changes.

The chin is found from the mesh: going up the neck, the first slice whose front juts out past the
throat. tools/rig_sculpt.py runs this on every body it rigs. To fix a character that's already rigged
(and re-export it, keeping its animations), run it on its .blend:

  Blender -b tools/character_build/<id>/<id>.blend -P tools/rigid_head.py -- <project_dir> <id>
"""
import os
import sys

import bpy
import numpy as np

BAND = 0.06  # metres of neck under the jaw line over which the head's hold fades out
TILT = 0.25  # the jaw line rises this much per metre back from the chin (about 5 cm by the nape)


def _smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def find_chin(P, neck_z, head_z):
    """Height (and front, in y) of the chin: the lowest slice, from below the neck bone up, whose front juts at least
    3.5 cm further forward than the throat just under it (the furthest-forward front of the slices
    0.5 to 2 cm below, so one sparse slice can't fake a jump). Falls back to the Head bone."""
    fronts = []  # (z, front) of each slice so far
    for z in np.arange(neck_z - 0.08, head_z + 0.12, 0.005):
        s = P[(np.abs(P[:, 2] - z) < 0.004) & (np.abs(P[:, 0]) < 0.06)]
        if not len(s):
            continue
        front = float(s[:, 1].min())  # characters face -Y
        below = [f for zz, f in fronts if z - 0.0205 < zz <= z - 0.0045]
        if len(below) >= 2 and front < min(below) - 0.035:
            return float(z), front
        fronts.append((z, front))
    return float(head_z), float(P[:, 1].min())


def make_rigid(me, rig):
    """Rebinds me's head (a mesh skinned to rig, in rest pose). Returns the chin height."""
    P = np.array([(me.matrix_world @ v.co)[:] for v in me.data.vertices])
    bones = rig.data.bones
    neck_z = (rig.matrix_world @ bones["Neck"].head_local).z
    head_z = (rig.matrix_world @ bones["Head"].head_local).z
    chin, chin_y = find_chin(P, neck_z, head_z)
    groups = {g.name: g for g in me.vertex_groups}
    head_g = groups.get("Head") or me.vertex_groups.new(name="Head")
    neck_g = groups.get("Neck") or me.vertex_groups.new(name="Neck")
    names = {g.index: g.name for g in me.vertex_groups}
    # the jaw line: at the chin in front, rising towards the nape, so a high collar at the back of
    # the neck stays below the band
    jaw = chin + TILT * np.maximum(P[:, 1] - chin_y, 0.0)
    lo = jaw - BAND
    s = _smooth((P[:, 2] - lo) / BAND)  # 0 at the bottom of the band, 1 at the jaw line and above
    rigid = band = 0
    for i, v in enumerate(me.data.vertices):
        if P[i, 2] <= lo[i]:
            continue  # below the band: the collar and shoulders keep their weights
        w = {names[g.group]: g.weight for g in v.groups if g.weight > 0.0}
        total = sum(w.values()) or 1.0
        h0 = w.pop("Head", 0.0) / total  # how much of this vertex followed the head before
        h = h0 + (1.0 - h0) * float(s[i])  # ...rising to all of it at the chin
        # take the group indices first: removing a vertex from a group reshuffles v.groups underneath a
        # loop over it, and the skipped groups would keep pulling the face toward the shoulders
        for gi in [g.group for g in v.groups]:
            me.vertex_groups[gi].remove([i])
        head_g.add([i], h, "REPLACE")
        if h >= 0.999 or not w:
            if h < 0.999:
                neck_g.add([i], 1.0 - h, "REPLACE")
            rigid += h >= 0.999
            continue
        rest = sum(w.values())
        for n, x in w.items():
            groups[n].add([i], (1.0 - h) * x / rest, "REPLACE")
        band += 1
    # check: above the jaw line every vertex follows the Head bone and nothing else
    stray = sum(1 for i, v in enumerate(me.data.vertices) if s[i] >= 0.999
                and any(g.weight > 0.0 and g.group != head_g.index for g in v.groups))
    if stray:
        raise RuntimeError(f"rigid_head: {stray} vertices above the jaw line still follow other bones")
    print(f"RIGID HEAD {me.name}: chin at {chin:.3f} m (Neck bone {neck_z:.3f}, Head bone {head_z:.3f}); "
          f"{rigid} verts rigid, {band} in the neck band")
    return chin


if __name__ == "__main__" and "--" in sys.argv:
    argv = sys.argv[sys.argv.index("--") + 1:]
    project, out_id = os.path.abspath(argv[0]), argv[1]
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = max((o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig and o.vertex_groups),
               key=lambda o: len(o.data.vertices))
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    make_rigid(body, rig)
    build = os.path.join(project, "tools", "character_build", out_id)
    os.makedirs(build, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, out_id + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(project, "assets", out_id + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True, export_cameras=False, export_lights=False,
                              export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True)
    print("EXPORTED", os.path.join(project, "assets", out_id + ".glb"))
