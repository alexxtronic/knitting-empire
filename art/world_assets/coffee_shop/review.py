"""Review renders of the coffee shop, compared with Alex's concept.

    Blender -b art/world_assets/coffee_shop/out/building_cafe.blend --python art/world_assets/coffee_shop/review.py -- <round>

Writes review/<round>_*.png: the reference camera (about 8 degrees right of front, 10 up, a long
lens: the verticals in the concept stay parallel), the front, a three-quarter from the left, the
back, the game's overhead three-quarter, the same reference view in clay, and
<round>_compare.png with the reference on the left and the render on the right.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
rnd = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(HERE, "review")
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("SAMPLES", 32))
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.95, 0.94, 0.95, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.2
sun.data.angle = math.radians(20)
sun.rotation_euler = (math.radians(50), 0, math.radians(-25))
sc.collection.objects.link(sun)
ground = bpy.data.meshes.new("ground")
ground.from_pydata([(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [], [(0, 1, 2, 3)])
g = bpy.data.objects.new("ground", ground)
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.55, 0.28, 1)
ground.materials.append(gm)
sc.collection.objects.link(g)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "ground"]  # the walk-in parts
for o in parts:  # the game shows a wall's low version only while she's inside; seen from out here it's the full one
    o.hide_render = o.name.endswith("_low")


def shot(name, az, el, dist, look=(0, 0, 4.6), lens=50, res=(1254, 1254), ortho=None):
    sc.render.resolution_x, sc.render.resolution_y = res
    a, e = math.radians(az), math.radians(el)
    loc = Vector(look) + dist * Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam.data.ortho_scale = ortho
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(look) - loc).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (rnd, name))
    bpy.ops.render.render(write_still=True)


# the reference (1448 x 1086): its 5.9 m front wall is 805 px, seen about 12 degrees right and 12 up.
# Since the café was doubled (2026-11-14) that wall is the middle of an 11.8 m front, whose foot is
# y = FRONT = -3.0; the camera keeps the concept's angle with the whole front in frame.
RES = (1448, 1086)
LENS = 36 * 120 / (12.6 * 1448 / 805)
REF = dict(az=12, el=12, dist=120, look=(0, -3.0, 3.55), lens=LENS, res=RES)
shot("ref_cam", REF["az"], REF["el"], REF["dist"], look=REF["look"], lens=LENS, res=RES)
shot("q_left", -40, 18, 40, look=(0, 0, 2.8))
shot("back", 160, 15, 40, look=(0, 0, 2.8))
shot("game", 25, 48, 42, look=(0, 0, 2.5), res=(1280, 800))
clay = bpy.data.materials.new("clay")
clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.75, 0.75, 1)
for o in parts:
    for i in range(len(o.data.materials)):
        o.data.materials[i] = clay
shot("clay_ref_cam", REF["az"], REF["el"], REF["dist"], look=REF["look"], lens=LENS, res=RES)

try:
    import numpy as np
    ref = bpy.data.images.load(os.path.join(HERE, "ref", "coffee_shop_concept.png"))
    ren = bpy.data.images.load(os.path.join(OUT, "%s_ref_cam.png" % rnd))
    a = np.array(ref.pixels[:]).reshape(ref.size[1], ref.size[0], 4)
    b = np.array(ren.pixels[:]).reshape(ren.size[1], ren.size[0], 4)
    both = np.concatenate([a, b], 1)
    img = bpy.data.images.new("compare", both.shape[1], both.shape[0], alpha=True)
    img.pixels[:] = both.ravel()
    img.filepath_raw = os.path.join(OUT, "%s_compare.png" % rnd)
    img.file_format = "PNG"
    img.save()
except Exception as e:
    print("compare failed:", e)
print("REVIEW", OUT)
