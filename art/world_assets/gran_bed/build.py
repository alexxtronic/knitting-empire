"""Gran's bed: a turned-post farmhouse bed with a patchwork quilt, for Nora's cottage.

Footprint 1.5 x 2.0 m (the game's "bed" entry), headboard at +Y here (the back, -Z in Godot).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/gran_bed/build.py
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

NAME = "gran_bed"
TEX = os.path.join(HERE, "tex")
K.reset(NAME)

# --- textures --------------------------------------------------------------------------------
wood = K.textured("WoodGrain_bed", K.wood_image("gran_bed_wood", TEX, seed=3))
WS = 1 / 0.6  # one wood tile per 0.6 m, so planks are 15 cm wide

PX, PY = 5, 7  # quilt patches across and along


def quilt_image(n=1024):
    rng = np.random.default_rng(11)
    ids = ["plaid", "cream", "denim", "rug_oat", "clay", "sage", "rug_wine", "sunflower"]
    cols = [np.array(K.pal_srgb(i)) for i in ids]
    cream = np.array(K.pal_srgb("milk"))
    rgb = np.zeros((n, n, 3))
    pw, ph = n / PX, n / PY
    yy, xx = np.mgrid[0:n, 0:n]
    cloth = K.tile_noise(n, 0.9, 5)
    grid = np.zeros((PY, PX), dtype=int)
    for j in range(PY):
        for i in range(PX):
            ban = {grid[j - 1, i] if j else -1, grid[j, i - 1] if i else -1}
            grid[j, i] = rng.choice([k for k in range(len(cols)) if k not in ban])
            x0, x1, y0, y1 = int(i * pw), int((i + 1) * pw), int(j * ph), int((j + 1) * ph)
            c = cols[grid[j, i]]
            lx, ly = xx[y0:y1, x0:x1] - x0, yy[y0:y1, x0:x1] - y0
            patch = np.broadcast_to(c, (y1 - y0, x1 - x0, 3)).copy()
            kind = rng.integers(0, 4)  # plain, stripes, checks, dots: printed cotton scraps
            other = cream if grid[j, i] != 1 else cols[0]
            if kind == 1:
                m = ((lx + ly) // 14) % 2 == 0
                patch[m] = patch[m] * 0.72 + other * 0.28
            elif kind == 2:
                m = ((lx // 20) % 2 == 0) ^ ((ly // 20) % 2 == 0)
                patch[m] = patch[m] * 0.8 + other * 0.2
            elif kind == 3:
                m = ((lx % 34 - 17) ** 2 + (ly % 34 - 17) ** 2) < 30
                patch[m] = other
            # a running stitch just inside the edge
            d = np.minimum(np.minimum(lx, (x1 - x0 - 1) - lx), np.minimum(ly, (y1 - y0 - 1) - ly))
            dash = ((lx + ly) // 9) % 2 == 0
            st = (np.abs(d - 9) < 1.6) & dash
            patch[st] = cream
            seam = np.clip(1 - d / 4.0, 0, 1)[..., None]
            patch = patch * (1 - 0.45 * seam)
            rgb[y0:y1, x0:x1] = patch
    rgb *= (0.9 + 0.2 * cloth)[..., None]
    return K.save_image("gran_bed_quilt", rgb, TEX)


quilt = K.textured("Quilt_patchwork", quilt_image(), rough=0.95)

# --- frame ---------------------------------------------------------------------------------------
HW, HL = 0.72, 0.97  # post centres


def post(x, y, h):
    prof = [(0.05, 0.0), (0.055, 0.03), (0.055, 0.34), (0.066, 0.38), (0.05, 0.43), (0.043, h - 0.22),
            (0.06, h - 0.18), (0.045, h - 0.14), (0.034, h - 0.115), (0.062, h - 0.07), (0.062, h - 0.04),
            (0.04, h - 0.005), (0.0, h)]
    K.lathe("post", prof, wood, steps=10, loc=(x, y, 0), u_rep=0.5, v_rep=h * WS)


for sx in (-1, 1):
    post(sx * HW, HL, 1.3)
    post(sx * HW, -HL, 0.82)
    K.uv_box(K.box("rail", (0.06, 1.9, 0.2), (sx * HW, 0, 0.3), wood, bevel=0.02), WS, grain="y")


def panel(y, z0, z1, rise, n=9):
    w = HW - 0.03
    pts = [(-w, z0), (w, z0)]
    for i in range(n + 1):
        x = w - 2 * w * i / n
        pts.append((x, z1 + rise * math.cos(math.pi * x / (2 * w))))
    ob = K.extrude_xz("panel", pts, y - 0.022, y + 0.022, wood)
    K.uv_box(ob, WS)


panel(HL, 0.3, 0.95, 0.22)   # headboard, arched
panel(-HL, 0.24, 0.6, 0.07)  # footboard
K.cyl("rosette", 0.1, 0.1, 0.03, (0, HL - 0.03, 0.98), K.wool("wood_light"), verts=16, rot=(90, 0, 0), bevel=0.01)
K.ball("rosette_knob", 0.035, (0, HL - 0.05, 0.98), K.wool("brass"), u=10, v=6)

# --- mattress and bedding ----------------------------------------------------------------------
K.box("mattress", (1.38, 1.88, 0.22), (0, 0, 0.45), K.wool("milk"), bevel=0.06, seg=3)
ZT = 0.575


def quilt_sheet():
    drape, rc = 0.26, 0.05
    hw = 0.70
    wt = 2 * (hw + drape)
    y0, ly = -0.935, 1.38
    nx, ny = PX * 4, PY * 4
    verts, faces, uvs = [], [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            s = (u - 0.5) * wt
            sg = 1 if s >= 0 else -1
            puff = 0.016 * abs(math.sin(math.pi * u * PX) * math.sin(math.pi * v * PY))
            d = abs(s) - hw
            if d <= 0:
                x, z = s, ZT + puff
            elif d < rc * math.pi / 2:
                t = d / rc
                x, z = sg * (hw + rc * math.sin(t) + puff * math.sin(t)), ZT - rc * (1 - math.cos(t)) + puff * math.cos(t)
            else:
                # the hanging sides swing out a little and ripple, like cloth
                hang = d - rc * math.pi / 2
                x = sg * (hw + rc + puff + 0.05 * hang + 0.012 * math.sin(v * math.pi * 9) * hang / drape)
                z = ZT - rc - hang
            verts.append((x, y0 + v * ly, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
            for (di, dj) in ((0, 0), (1, 0), (1, 1), (0, 1)):
                uvs += [(i + di) / nx, 1.0 - (j + dj) / ny]
    me = bpy.data.meshes.new("quilt")
    me.from_pydata(verts, [], faces)
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", uvs)
    ob = K._obj("quilt", me, quilt)
    K.smooth(ob, keep_sharp=False)


quilt_sheet()
# the sheet turned down over the top of the quilt, and the quilt's end tucked at the foot
K.box("sheet_fold", (1.5, 0.2, 0.05), (0, 0.5, ZT + 0.015), K.wool("cream"), bevel=0.022, seg=3)
for sx in (-1, 1):
    K.ball("pillow", 1.0, (sx * 0.34, 0.77, ZT + 0.09), K.wool("milk"), scale=(0.31, 0.2, 0.095), boxy=0.6, u=16, v=8).rotation_euler = (math.radians(-14), 0, math.radians(-sx * 4))
K.ball("cushion", 1.0, (0.05, 0.6, ZT + 0.085), K.wool("berry"), scale=(0.17, 0.085, 0.13), boxy=0.65, u=12, v=8).rotation_euler = (math.radians(-22), 0, math.radians(6))
K.ball("cushion_button", 0.022, (0.05, 0.545, ZT + 0.1), K.wool("gold"), u=8, v=5)

# a folded blanket across the foot, with Gran's knitting left on it
K.box("blanket", (1.26, 0.36, 0.07), (0, -0.66, ZT + 0.05), K.wool("plaid"), bevel=0.03, seg=3)
K.box("blanket_top", (1.26, 0.31, 0.06), (0, -0.675, ZT + 0.105), K.wool("plaid"), bevel=0.028, seg=3)
for x in (-0.38, 0.38):
    K.box("blanket_stripe", (0.08, 0.37, 0.145), (x, -0.665, ZT + 0.07), K.wool("plaid_dark"), bevel=0.03, seg=2)
K.ball("yarn", 0.075, (0.36, -0.67, ZT + 0.205), K.wool("sage"), u=12, v=8)
for a in (25, 100, 160):
    K.torus("yarn_wrap", 0.07, 0.012, (0.36, -0.67, ZT + 0.205), K.wool("leaf"), rot=(a, a * 0.7, 0), major=14, minor=4)
for a in (-18, 22):
    K.cyl("needle", 0.007, 0.007, 0.34, (0.36, -0.67, ZT + 0.215), K.wool("brass"), verts=6, rot=(72, 0, a))

K.finish(NAME, os.path.join(HERE, "out"), max_tris=9000)
