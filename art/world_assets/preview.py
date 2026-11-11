"""Quick preview renders of a built asset: hero, side and top views on a pale ground.

    Blender -b <asset>.blend --python art/world_assets/preview.py -- <out_dir> [cx,cy,cz] [distance]
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
ctr = Vector([float(v) for v in argv[1].split(",")]) if len(argv) > 1 else Vector((0, 0, 1))
dist = float(argv[2]) if len(argv) > 2 else 9.0
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 40
sc.cycles.use_denoising = True
sc.render.resolution_x = sc.render.resolution_y = 800
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.88, 0.85, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 4.0
sun.data.angle = math.radians(8)
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
sc.collection.objects.link(sun)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.5, 0.58, 0.35, 1)
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.01))
bpy.context.object.data.materials.append(gm)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
for name, az, el in [("hero", -35, 18), ("side", 50, 6), ("top", -35, 55)]:
    a, e = math.radians(az), math.radians(el)
    cam.location = ctr + Vector((math.sin(-a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{out}/{name}.png"
    bpy.ops.render.render(write_still=True)
