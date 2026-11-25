"""The inventory pictures of wool and the wild fibres: one ball of our own chunky yarn (the model
build.py makes for yarn_balls.glb) in each item's colour, rendered in Cycles on a transparent
background and cropped square. Writes assets/icons/<item>.png: `wool`, and one for every fibre in
data/wildlife.json ("fibres"), in its colour. Hud.Slot.icon() picks them up by item id.

  Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/yarn/make_icons.py [-- --size PX --samples N --only wool,fox_fibre]

The yarn's strand textures are written to a scratch folder (out/icons_tex), not the model's own tex/.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402


def opt(name, default):
    a = sys.argv
    return type(default)(a[a.index(name) + 1]) if name in a else default


SIZE = opt("--size", 256)
SAMPLES = opt("--samples", 96)
ONLY = opt("--only", "").split(",") if "--only" in sys.argv else []
OUT = os.path.join(K.PROJECT, "assets", "icons")
TEX = os.path.join(HERE, "out", "icons_tex")
os.makedirs(TEX, exist_ok=True)

# build.py's yarn_ball() and its helpers, without its build-everything tail
src = open(os.path.join(HERE, "build.py")).read().split("def build(name):")[0]
ns = {"__file__": os.path.join(HERE, "build.py"), "__name__": "yarn_build"}
exec(compile(src, "build.py", "exec"), ns)
yarn_ball = ns["yarn_ball"]

ITEMS = {"wool": "#f1e3c2"}  # the cream of the yarn_balls model
with open(os.path.join(K.PROJECT, "data", "wildlife.json"), encoding="utf-8") as f:
    for fid, fd in json.load(f)["fibres"].items():
        ITEMS[fid] = fd.get("color", "#a08060")


def render(item, hexcol):
    K.reset("icon_" + item)
    img, nrm = CL.yarn_maps("yarn_" + item, TEX, hexcol)
    mat = K.textured("yarn_" + item, img, rough=0.95, normal=nrm, normal_strength=0.9)
    R = 0.085
    yarn_ball((0, 0, R), R, mat, 4, tail=((0.35, -1, 0), 0.16))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE * 2
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.92, 1.0, 1.0)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    for name, loc, energy, size, col in [("Key", (-0.5, -0.7, 0.6), 7, 0.5, (1.0, 0.96, 0.88)),
                                         ("Fill", (0.6, -0.4, 0.2), 2, 0.6, (0.9, 0.93, 1.0)),
                                         ("Rim", (0.3, 0.6, 0.5), 3, 0.4, (1.0, 0.95, 0.9))]:
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.size, ld.color = energy, size, col
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        sc.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, 0, R)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 90
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = (0.0, -0.95, 0.52)
    cam.rotation_euler = (Vector((0.015, 0, 0.075)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    tmp = os.path.join(HERE, "out", "icon_%s_full.png" % item)
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    return tmp


def crop(src, dst):
    im = bpy.data.images.load(src)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.where(px[:, :, 3] > 0.03)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * 1.08) + 4
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sq = np.zeros((side, side, 4), dtype=np.float32)
    ox, oy = cx - side // 2, cy - side // 2
    for yy in range(side):
        sy = yy + oy
        if 0 <= sy < h:
            xa, xb = max(0, ox), min(w, ox + side)
            sq[yy, xa - ox:xb - ox] = px[sy, xa:xb]
    out = bpy.data.images.new("icon", side, side, alpha=True)
    out.pixels = sq.ravel().tolist()
    out.scale(SIZE, SIZE)
    out.filepath_raw = dst
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    bpy.data.images.remove(im)


for item, col in ITEMS.items():
    if ONLY and item not in ONLY:
        continue
    full = render(item, col)
    crop(full, os.path.join(OUT, item + ".png"))
    print("ICON", item, col)
