"""A Cycles render of each built piece against white, from the front right like the references.

    Blender -b --factory-startup --python art/world_assets/cafe_props/review.py -- <kind> [...]

Env: REVIEW_AZ (degrees, default 30), REVIEW_EL (default 22), REVIEW_SAMPLES (32).
Writes art/world_assets/cafe_props/review/<kind>.png.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(HERE, "review")
os.makedirs(out, exist_ok=True)
for kind in sys.argv[sys.argv.index("--") + 1:]:
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, kind, "out", kind + ".blend"))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("REVIEW_SAMPLES", 32))
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 2.4
    sun.data.angle = math.radians(14)
    sun.rotation_euler = (math.radians(40), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    gm = bpy.data.materials.new("floor")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.92, 0.92, 0.92, 1)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.001))
    bpy.context.object.data.materials.append(gm)
    ob = bpy.data.objects["model"]
    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    ctr = (lo + hi) / 2
    size = max((hi - lo).x, (hi - lo).z, (hi - lo).y)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 60
    cam.data.clip_start = 0.01
    sc.collection.objects.link(cam)
    sc.camera = cam
    a, e = math.radians(float(os.environ.get("REVIEW_AZ", 30))), math.radians(float(os.environ.get("REVIEW_EL", 22)))
    cam.location = ctr + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * size * 3.2
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x = sc.render.resolution_y = int(os.environ.get("REVIEW_PX", 600))
    sc.render.filepath = os.path.join(out, kind + os.environ.get("REVIEW_SUFFIX", "") + ".png")
    bpy.ops.render.render(write_still=True)
