"""Review renders of the built bench: the reference's own camera angle, five more views, and the same
views in plain clay (how it is built, with the paint off). White studio, no ground detail.

    Blender -b art/world_assets/bench_park/out/bench_park.blend --python art/world_assets/bench_park/review.py -- <out_dir> [view ...]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
only = argv[1:]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("REVIEW_SAMPLES", 48))
sc.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
except Exception as e:  # CPU is fine
    print("cpu render:", e)
sc.view_settings.view_transform = "Standard"
sc.render.film_transparent = False
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
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, -0.002))
bpy.context.object.data.materials.append(gm)
clay = bpy.data.materials.new("clay")
clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.6, 0.58, 1)
clay.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.lens = 50
sc.collection.objects.link(cam)
sc.camera = cam

# name: (azimuth from the front towards +X, elevation, distance, look-at, size)
C = Vector((0, 0.03, 0.47))
VIEWS = {
    "ref": (38, 22, 3.7, Vector((0.0, 0.03, 0.47)), (1280, 720)),
    "front_left": (-40, 16, 4.6, C, (960, 640)),
    "front": (0, 6, 4.6, C, (960, 640)),
    "side": (90, 4, 3.0, C, (960, 640)),
    "back": (150, 18, 4.6, C, (960, 640)),
    "game": (20, 52, 6.0, C, (960, 640)),
    "close_arm": (48, 16, 1.6, Vector((0.86, -0.05, 0.50)), (960, 640)),
    "close_back": (-150, 20, 1.8, Vector((-0.84, 0.25, 0.7)), (960, 640)),
}
model = bpy.data.objects["model"]
for name, (az, el, dist, ctr, size) in VIEWS.items():
    if only and name not in only:
        continue
    a, e = math.radians(az), math.radians(el)
    cam.location = ctr + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = size
    cam.data.lens = 36 if name == "ref" else 50
    for tag, override in (("", None), ("_clay", clay)):
        bpy.context.view_layer.material_override = override
        sc.render.filepath = os.path.join(out, name + tag + ".png")
        bpy.ops.render.render(write_still=True)
