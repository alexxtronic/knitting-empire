"""Review pictures of a built sweater's fit: the character in out/<id>_sweater.blend with the
`under_sweater` key on, from the front, three-quarter and side, and from above at about the game
camera's angle, in EEVEE so a check takes seconds. Any of the outfit showing through the knit shows
here. Then a sheet of them all: review/fit_sheet.png.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/sweater/fit_review.py -- giorgio rosa ...

With `--pose` the rig plays its Idle loop's first frame (the arms in against the body, as in the game),
then a Walk frame and a seated one (SitKnit, or SitIdle).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "review", "fit")
VIEWS = (("front", 0, 6), ("threeq", -40, 8), ("side", 90, 6), ("game", -25, 38), ("back", 180, 6))
WALK_VIEWS = (("walk_threeq", -40, 8), ("walk_game", 150, 38), ("walk_side", -90, 6))
SIT_VIEWS = (("sit_threeq", -40, 20),)


def shoot(cid, pose):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", cid + "_sweater.blend"))
    sc = bpy.context.scene
    body = next(o for o in sc.objects if o.type == "MESH" and o.data.shape_keys and "under_sweater" in o.data.shape_keys.key_blocks)
    body.data.shape_keys.key_blocks["under_sweater"].value = 1.0
    rig = next(o for o in sc.objects if o.type == "ARMATURE")
    def play(name, at):
        act = next((a for a in bpy.data.actions if a.name.lower().startswith(name)), None)
        if act:
            rig.data.pose_position = "POSE"
            rig.animation_data_create()
            rig.animation_data.action = act
            f0, f1 = act.frame_range
            sc.frame_set(int(f0 + (f1 - f0) * at))
    if pose:
        play("idle", 0.0)
    for o in sc.objects:
        if o.type == "CAMERA" or o.type == "LIGHT":
            bpy.data.objects.remove(o)
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 520, 680
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.82, 0.86, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    ld = bpy.data.lights.new("key", "SUN")
    ld.energy = 3.0
    lo = bpy.data.objects.new("key", ld)
    sc.collection.objects.link(lo)
    lo.rotation_euler = (0.7, 0.1, -0.6)
    cd = bpy.data.cameras.new("cam")
    cd.lens = 70
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    hips = rig.matrix_world @ rig.data.bones["Hips"].head_local
    head = rig.matrix_world @ rig.data.bones["Head"].head_local
    t = Vector((0, 0, 0.5 * (hips.z + head.z) - 0.05))
    dist = 2.4 * (head.z - hips.z + 0.35) / 0.95
    os.makedirs(OUT, exist_ok=True)
    out = []
    for name, yaw, elev in VIEWS:
        a, e = math.radians(yaw), math.radians(elev)
        cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(OUT, "%s_%s.png" % (cid, name))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        out.append(p)
    if pose:
        play("walk", 0.3)
        for name, yaw, elev in WALK_VIEWS:
            a, e = math.radians(yaw), math.radians(elev)
            cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
            cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
            p = os.path.join(OUT, "%s_%s.png" % (cid, name))
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            out.append(p)
        play("sitknit" if any(a.name.lower().startswith("sitknit") for a in bpy.data.actions) else "sitidle", 0.3)
        for name, yaw, elev in SIT_VIEWS:
            a, e = math.radians(yaw), math.radians(elev)
            cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist - Vector((0, 0, 0.35))
            cam.rotation_euler = (t - Vector((0, 0, 0.35)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            p = os.path.join(OUT, "%s_%s.png" % (cid, name))
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            out.append(p)
    return out


def sheet(rows):
    import numpy as np
    imgs = []
    for row in rows:
        line = []
        for p in row:
            im = bpy.data.images.load(p)
            w, h = im.size
            a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
            line.append(a)
            bpy.data.images.remove(im)
        imgs.append(np.concatenate(line, axis=1))
    a = np.concatenate(imgs[::-1], axis=0)
    h, w = a.shape[:2]
    im = bpy.data.images.new("sheet", w, h)
    im.pixels = a.ravel()
    im.filepath_raw = os.path.join(OUT, "fit_sheet.png")
    im.file_format = "PNG"
    im.save()


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    who = [a for a in argv if not a.startswith("--")]
    rows = [shoot(c, "--pose" in argv) for c in who]
    sheet(rows)
