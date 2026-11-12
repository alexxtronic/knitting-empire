"""Review renders of one shop sign, compared with its reference.

    Blender -b art/world_assets/shop_signs/out/<sign>/sign_<sign>.blend --python art/world_assets/shop_signs/review.py -- <sign> <round>

Writes review/<sign>/<round>_*.png: the front framed like the reference (2000 x 667 px, the
board's ends on the reference's), two three-quarter views, the side, the back, the same front in
clay (no colour, to judge the relief), and compare.png with the reference above the render.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
key, rnd = sys.argv[sys.argv.index("--") + 1:][:2]
OUT = os.path.join(HERE, "review", key)
os.makedirs(OUT, exist_ok=True)
PX = 2.0 / 1690.0
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = int(os.environ.get("SAMPLES", 48))
sc.cycles.use_denoising = True
sc.view_settings.view_transform = "Standard"  # the face is the reference's own colours: no tone curve, like the game
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.97, 0.97, 0.97, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.data.angle = math.radians(25)
sun.rotation_euler = (math.radians(55), 0, math.radians(-20))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
model = bpy.data.objects["model"]


def shot(name, loc, look, ortho=None, res=(1200, 800)):
    sc.render.resolution_x, sc.render.resolution_y = res
    cam.data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam.data.ortho_scale = ortho
    else:
        cam.data.lens = 50
    cam.location = loc
    cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (rnd, name))
    bpy.ops.render.render(write_still=True)


# the reference's frame: 2000 px across, the board's centre at (995, 340) of 667
cx = (1000 - 995) * PX
cz = (340 - 333.5) * PX
shot("front", (cx, -6, cz), (cx, 0, cz), ortho=2000 * PX, res=(2000, 667))
shot("q_left", (-2.2, -2.6, 0.5), (0, 0, 0.0))
shot("q_right", (2.2, -2.6, -0.3), (0, 0, 0.0))
shot("side", (4, -0.1, 0.1), (0, -0.1, 0.05), ortho=1.2, res=(800, 800))
shot("back", (0.8, 4, 0.3), (0, 0, 0))
clay = bpy.data.materials.new("clay")
clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.75, 0.75, 1)
for i in range(len(model.data.materials)):
    model.data.materials[i] = clay
shot("clay_front", (cx, -6, cz), (cx, 0, cz), ortho=2000 * PX, res=(2000, 667))

try:
    import numpy as np
    ref = bpy.data.images.load(os.path.join(HERE, "ref", "sign_%s.png" % key))
    ren = bpy.data.images.load(os.path.join(OUT, "%s_front.png" % rnd))
    a = np.array(ref.pixels[:]).reshape(ref.size[1], ref.size[0], 4)
    b = np.array(ren.pixels[:]).reshape(ren.size[1], ren.size[0], 4)
    both = np.concatenate([b, a], 0)  # Blender images are bottom-up: the reference ends up on top
    img = bpy.data.images.new("compare", both.shape[1], both.shape[0], alpha=True)
    img.pixels[:] = both.ravel()
    img.filepath_raw = os.path.join(OUT, "%s_compare.png" % rnd)
    img.file_format = "PNG"
    img.save()
except Exception as e:  # the comparison is a convenience; the renders matter
    print("compare failed:", e)
print("REVIEW", OUT)
