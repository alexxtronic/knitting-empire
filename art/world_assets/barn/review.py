"""Review renders of the barn: outside from the reference's angle and three more, and inside the way
the game shows it (roof off, doors open, the two walls nearest the camera cut down to stubs).

    Blender -b art/world_assets/barn/out/barn.blend --python art/world_assets/barn/review.py -- <out_dir> [view ...]
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
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.9, 0.9, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, -0.06))
bpy.context.object.data.materials.append(gm)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.lens = 50
sc.collection.objects.link(cam)
sc.camera = cam
ob = bpy.data.objects
WALLS = ("front", "back", "left", "right")


def show(roof=True, doors=0.0, cut=()):
    """roof on or off, doors swung open by `doors` degrees, and the walls in `cut` shown as stubs."""
    ob["roof"].hide_render = not roof
    ob["door_l"].rotation_euler.z = -math.radians(doors)
    ob["door_r"].rotation_euler.z = math.radians(doors)
    for s in WALLS:
        ob["wall_" + s].hide_render = s in cut
        ob["wall_" + s + "_low"].hide_render = s not in cut


OUTSIDE = dict(roof=True, doors=0.0, cut=())
INSIDE = dict(roof=False, doors=105.0, cut=("front", "right"))
# name: (azimuth from the front towards +X, elevation, distance, look-at, size, what is shown)
VIEWS = {
    "ref": (38, 17, 17.0, Vector((0, 0, 2.6)), (1100, 1100), OUTSIDE),
    "front": (0, 8, 17.0, Vector((0, 0, 2.6)), (960, 800), OUTSIDE),
    "back": (212, 18, 17.0, Vector((0, 0, 2.6)), (960, 800), OUTSIDE),
    "game": (25, 50, 19.0, Vector((0, 0, 1.6)), (960, 800), OUTSIDE),
    "doors_open": (20, 14, 15.0, Vector((0, 0, 2.2)), (960, 800), dict(roof=True, doors=105.0, cut=())),
    "inside_game": (25, 50, 14.0, Vector((0, 0.2, 0.8)), (1100, 900), INSIDE),
    "inside_low": (35, 28, 11.0, Vector((0, 0.4, 0.9)), (1100, 800), INSIDE),
    "inside_top": (0, 86, 13.0, Vector((0, 0, 0.5)), (960, 900), dict(roof=False, doors=105.0, cut=())),
    "inside_left": (-40, 34, 11.0, Vector((0, 0.4, 0.9)), (1100, 800), dict(roof=False, doors=105.0, cut=("front", "left"))),
}
for name, (az, el, dist, ctr, size, vis) in VIEWS.items():
    if only and name not in only:
        continue
    show(**vis)
    a, e = math.radians(az), math.radians(el)
    cam.location = ctr + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
