"""Review renders of the mailbox in Cycles on the CPU (the kiln sheet's views: front, both
three-quarters, side, back, and a close-up of the door), laid out beside the reference. Used when
EEVEE stalls because another Blender holds the GPU.

    Blender -b --factory-startup --python-exit-code 1 --python art/world_assets/mailbox/review.py -- <out dir> [clay]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
a = sys.argv[sys.argv.index("--") + 1:]
out = a[0]
clay = "clay" in a[1:]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "out", "mailbox.glb"))
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 48
sc.render.resolution_x, sc.render.resolution_y = 600, 700
sc.view_settings.view_transform = "Standard"
if clay:
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.58, 0.55, 1)
    for o in sc.objects:
        if o.type == "MESH":
            for i in range(len(o.material_slots)):
                o.material_slots[i].material = m
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.82, 0.85, 0.9, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.55
for name, rot, energy in (("key", (50, 0, -35), 3.2), ("rim", (60, 0, 150), 1.5)):
    s = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    sc.collection.objects.link(s)
    s.rotation_euler = [math.radians(v) for v in rot]
    s.data.energy = energy
    s.data.angle = math.radians(8)
bpy.ops.mesh.primitive_plane_add(size=20)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 70
views = {"front": (-90, 8, 0.58, 3.4), "q_left": (-65, 10, 0.58, 3.4), "q_right": (-115, 10, 0.58, 3.4),
         "side": (0, 8, 0.58, 3.4), "back": (90, 10, 0.58, 3.4), "close": (-70, 12, 0.62, 1.5)}
tag = "_clay" if clay else ""
for name, (az, el, tz, dist) in views.items():
    t = Vector((0, 0, tz))
    d = Vector((math.cos(math.radians(az)) * math.cos(math.radians(el)), math.sin(math.radians(az)) * math.cos(math.radians(el)),
                math.sin(math.radians(el)))) * dist
    cam.location = t + d
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + tag + ".png")
    bpy.ops.render.render(write_still=True)
