"""Review renders of the plank mock-up: the wall square on (as its reference), the floor from above
(as its reference), and both from the game camera's angle.

    Blender -b art/world_assets/planks/out/planks.blend --python art/world_assets/planks/review.py -- <out_dir>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 48
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 1.8
sun.data.angle = math.radians(20)
sun.rotation_euler = (math.radians(48), 0, math.radians(-32))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
VIEWS = {  # name: (camera, looks at, lens, size)
    "wall": ((0, -7.0, 1.3), (0, 0, 1.3), 60, (1200, 760)),
    "floor": ((0, -1.2, 7.0), (0, -1.2, 0), 60, (1200, 700)),
    "game": ((2.6, -5.2, 5.4), (0, -0.6, 0.7), 50, (1100, 800)),
}
for name, (at, to, lens, size) in VIEWS.items():
    cam.location = at
    cam.data.lens = lens
    cam.rotation_euler = (Vector(to) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
