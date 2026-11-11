"""One hero render of each piece (from the front right, as the references are), for a contact sheet.

    Blender -b --factory-startup --python art/world_assets/house_furniture/review.py -- <out_dir> [id ...]
    uv run --no-project --with pillow python art/world_assets/house_furniture/sheet.py <out_dir>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
items = argv[1:] or sorted(d for d in os.listdir(HERE) if os.path.exists(os.path.join(HERE, d, "out", d + ".blend")))
os.makedirs(out, exist_ok=True)
for item in items:
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, item, "out", item + ".blend"))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("REVIEW_SAMPLES", 32))
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.1
    sun.data.angle = math.radians(14)
    sun.rotation_euler = (math.radians(42), 0, math.radians(-28))
    sc.collection.objects.link(sun)
    gm = bpy.data.materials.new("floor")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.9, 0.9, 1)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.002))
    bpy.context.object.data.materials.append(gm)
    ob = bpy.data.objects["model"]
    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    ctr = (lo + hi) / 2
    size = max((hi - lo).x, (hi - lo).z, (hi - lo).y)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    sc.collection.objects.link(cam)
    sc.camera = cam
    a, e = math.radians(float(os.environ.get("REVIEW_AZ", 32))), math.radians(20)
    cam.location = ctr + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * size * 2.9
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x = sc.render.resolution_y = 520
    sc.render.filepath = os.path.join(out, item + ".png")
    bpy.ops.render.render(write_still=True)
