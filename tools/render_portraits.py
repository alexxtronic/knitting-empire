"""Mood portraits for the dialogue box, rendered from the models the game plays with.

    Blender -b --factory-startup -P tools/render_portraits.py -- "$PWD" [character id ...]

For every character in data/characters.json (or the ids given) it loads the character's `model`,
stands it in its Idle pose, and renders a head-and-shoulders picture for each story mood to
assets/portraits/<id>_<mood>.png (384 px, transparent), the files scripts/story_player.gd shows
beside a line. A mood is a tilt of the head plus, on a model with real eyes (tools/add_eyes.py),
the lid shapes the game itself uses for that mood (MOODS in scripts/face.gd; keep LIDS in step).

Run it again whenever a character's model or face changes, then import.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ROOT = argv[0]
ONLY = argv[1:]
OUT = os.path.join(ROOT, "assets", "portraits")
SIZE = 384

# mood: Head bone (nod forward, turn, tilt) in degrees
HEAD = {
    "neutral": (0, 0, 0), "happy": (-4, 0, 6), "warm": (3, 0, 8), "sad": (12, 0, -4),
    "wry": (0, -6, -9), "surprised": (-9, 0, 0), "worried": (6, 0, 5), "angry": (7, 0, 0),
}
# the lid blend shapes of scripts/face.gd (MOODS) for the same moods
LIDS = {
    "neutral": {}, "happy": {"squint": 0.75}, "warm": {"squint": 0.4}, "wry": {"squint": 0.3, "lid_half": 0.35},
    "sad": {"lid_sad": 0.85}, "worried": {"lid_sad": 0.55}, "surprised": {}, "angry": {"lid_angry": 0.9},
}


def render_character(cid, model):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=model)
    sc = bpy.context.scene
    rig = next(o for o in sc.objects if o.type == "ARMATURE")
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in meshes:
        if o.name.startswith("KnitProps"):       # her needles and swatch: only out while she knits
            o.hide_render = True
    body = max((o for o in meshes if not o.hide_render), key=lambda o: len(o.data.vertices))
    eyes = [o for o in meshes if o.data.shape_keys and "squint" in o.data.shape_keys.key_blocks]

    # stand in the Idle loop's first frame (the rest pose has the arms out), then drop the action
    idle = next((a for a in bpy.data.actions if a.name.split(".")[0].endswith("Idle") and "Sit" not in a.name), None)
    if idle is not None:
        rig.animation_data_create()
        rig.animation_data.action = idle
        sc.frame_set(int(idle.frame_range[0]))
        bpy.context.view_layer.update()
        pose = {b.name: (b.location.copy(), b.rotation_quaternion.copy(), b.scale.copy()) for b in rig.pose.bones}
        rig.animation_data.action = None
        for b in rig.pose.bones:
            b.location, b.rotation_quaternion, b.scale = pose[b.name]
    head = rig.pose.bones["Head"]
    head_rest = head.rotation_quaternion.copy()
    rig.rotation_mode = "XYZ"
    rig.rotation_euler = (rig.rotation_euler.x, rig.rotation_euler.y, math.radians(16))   # three-quarter view
    bpy.context.view_layer.update()

    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    top = max((ev.matrix_world @ v.co).z for v in ev.data.vertices)
    neck = (rig.matrix_world @ head.head).z
    centre = Vector((0.0, 0.0, neck + 0.3 * (top - neck)))
    span = (top - neck) * 1.85      # the head fills a little over half the picture

    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.4, 0.38, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = world
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span
    cam.location = (centre.x + (rig.matrix_world @ head.head).x, -6.0, centre.z)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, energy, rot, col in (("key", 3.0, (55, -20, -35), (1.0, 0.95, 0.88)), ("fill", 1.0, (70, 25, 140), (0.86, 0.9, 1.0)),
                                   ("rim", 1.6, (80, 0, 180), (1.0, 0.86, 0.72))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.data.color = col
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        sc.collection.objects.link(light)

    for mood, (nod, turn, tilt) in HEAD.items():
        head.rotation_quaternion = head_rest @ Euler((math.radians(nod), math.radians(turn), math.radians(tilt)), "XYZ").to_quaternion()
        for o in eyes:
            for k in o.data.shape_keys.key_blocks[1:]:
                k.value = LIDS[mood].get(k.name, 0.0)
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (cid, mood))
        bpy.ops.render.render(write_still=True)
    print("[portraits] %s: %d moods from %s (%s)" % (cid, len(HEAD), os.path.basename(model), "eyes with lids" if eyes else "no lid shapes"))


with open(os.path.join(ROOT, "data", "characters.json"), encoding="utf-8") as f:
    data = json.load(f)
os.makedirs(OUT, exist_ok=True)
for ch in data.get("characters", []):
    cid = str(ch.get("id", ch.get("name", ""))).lower()
    path = str(ch.get("model", ""))
    if not path or (ONLY and cid not in ONLY):
        continue
    render_character(cid, os.path.join(ROOT, path.replace("res://", "")))
