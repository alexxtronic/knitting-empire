"""A farm soil plot, after Alex's reference: a raised block of red-brown earth with a mossy
grass rim, three mounded furrows, a few stones and grass tufts round the edge.

1.0 x 1.0 m (the game's plot size, scripts/plot.gd). Furrows run along Y here (Z in Godot).
The soil surfaces use the material "Soil_plot"; plot.gd darkens it when the plot is watered.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/dirt_plot/build.py
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

NAME = "dirt_plot"
TEX = os.path.join(HERE, "tex")
K.reset(NAME)

S = 0.5           # half size
BASE = 0.07       # top of the block
RIM = 0.075       # width of the grass rim
IN = S - RIM      # half size of the tilled bed
ROWS = 3
RIDGE = 0.085     # furrow height above the bed
SOIL = np.array(K.hex_rgb("#8a4b2b"))
SOIL_DARK = np.array(K.hex_rgb("#5a2f1b"))
SOIL_LIGHT = np.array(K.hex_rgb("#a8653a"))
MOSS = np.array(K.hex_rgb("#86a63a"))
MOSS_LIGHT = np.array(K.hex_rgb("#b5cc4a"))


def ridge(u):
    """Furrow profile across the bed, u in 0..1: three rounded mounds."""
    w = (u * ROWS) % 1.0
    return max(0.0, math.sin(math.pi * w)) ** 0.7


def soil_maps(n=512):
    """Clods and crumbs; v runs across the rows so the valleys are darker."""
    clod = K.tile_noise(n, 1.45, 31)
    crumb = K.tile_noise(n, 0.85, 37)
    big = K.tile_noise(n, 1.9, 41)
    yy, xx = np.mgrid[0:n, 0:n]
    across = xx / n
    prof = np.vectorize(ridge)(across)
    rgb = SOIL * (0.8 + 0.35 * big[..., None])
    rgb = rgb * (1 - 0.4 * (1 - prof[..., None])) + SOIL_DARK * 0.4 * (1 - prof[..., None])
    lit = np.clip((clod - 0.55) * 4, 0, 1)[..., None]
    rgb = rgb * (1 - 0.35 * lit) + SOIL_LIGHT * 0.35 * lit
    pit = np.clip((0.35 - crumb) * 5, 0, 1)[..., None]
    rgb = rgb * (1 - 0.5 * pit) + SOIL_DARK * 0.5 * pit
    rgb *= (0.92 + 0.16 * crumb[..., None])
    hgt = 0.7 * clod + 0.5 * crumb + 0.4 * big
    return K.save_image("dirt_plot_soil", rgb, TEX), K.save_image("dirt_plot_soil_normal", K.normal_from_height(hgt, 1.8), TEX)


def side_maps(w=512, h=128):
    """The block's sides: packed earth cut into soft blocks, a little grass hanging over the top."""
    mott = K.tile_noise(w, 1.4, 51, m=h)
    speck = K.tile_noise(w, 0.5, 53, m=h)
    yy, xx = np.mgrid[0:h, 0:w]
    rgb = SOIL_LIGHT * 0.65 + SOIL * 0.35
    rgb = rgb * (0.82 + 0.3 * mott[..., None]) * (0.94 + 0.12 * speck[..., None])
    bw = w / 4
    d = np.minimum(xx % bw, bw - xx % bw)
    joint = np.clip(1 - d / 3.0, 0, 1)[..., None]
    rgb = rgb * (1 - 0.45 * joint) + SOIL_DARK * 0.45 * joint
    top = np.clip((0.25 - yy / h + 0.12 * (mott - 0.5)) * 8, 0, 1)[..., None]
    rgb = rgb * (1 - top) + MOSS * (0.85 + 0.3 * speck[..., None]) * top
    hgt = 0.6 * mott + 0.3 * speck - 1.5 * joint[..., 0]
    return K.save_image("dirt_plot_side", rgb, TEX), K.save_image("dirt_plot_side_normal", K.normal_from_height(hgt, 2.5), TEX)


def moss_maps(n=256):
    a = K.tile_noise(n, 1.1, 61)
    b = K.tile_noise(n, 0.5, 63)
    t = np.clip((a - 0.4) * 2.2, 0, 1)[..., None]
    rgb = MOSS * (1 - t) + MOSS_LIGHT * t
    rgb *= (0.88 + 0.24 * b[..., None])
    return K.save_image("dirt_plot_moss", rgb, TEX), K.save_image("dirt_plot_moss_normal", K.normal_from_height(0.6 * a + 0.6 * b, 3.0), TEX)


s_img, s_nrm = soil_maps()
soil = K.textured("Soil_plot", s_img, rough=0.97, normal=s_nrm)
d_img, d_nrm = side_maps()
side = K.textured("Soil_side", d_img, rough=0.95, normal=d_nrm)
m_img, m_nrm = moss_maps()
moss = K.textured("Moss_plot", m_img, rough=0.95, normal=m_nrm)
blade = K.plain("Grass_tuft", "#9cbf3c", rough=0.8)
blade_dark = K.plain("Grass_tuft_dark", "#6f9a2e", rough=0.85)
pebble = K.textured("Stone_pebble", K.save_image("dirt_plot_pebble", (np.array(K.hex_rgb("#b5a08a")) * (0.85 + 0.25 * K.tile_noise(64, 1.2, 71)[..., None])), TEX), rough=0.85)

# --- the block: sides textured as cut earth (v runs bottom to top) --------------------------------
blk = K.box("block", (2 * S, 2 * S, BASE), (0, 0, BASE / 2), side, bevel=0.018, seg=2)
K.uv_box(blk, 2.0, v_from_z=(0.0, BASE))

# --- the grass rim: a mossy frame round the bed, slightly lumpy ------------------------------------
rng = np.random.default_rng(3)
for i, (sx, sy, cx, cy) in enumerate(((2 * S, RIM, 0, -S + RIM / 2), (2 * S, RIM, 0, S - RIM / 2),
                                      (RIM, 2 * S - 2 * RIM, -S + RIM / 2, 0), (RIM, 2 * S - 2 * RIM, S - RIM / 2, 0))):
    r = K.box("rim", (sx + 0.004, sy + 0.004, 0.03), (cx, cy, BASE + 0.008), moss, bevel=0.012, seg=2)
    K.uv_box(r, 3.0)
for _ in range(9):  # moss cushions breaking up the straight edge
    side_i = rng.integers(0, 4)
    t = rng.uniform(-S + 0.06, S - 0.06)
    x, y = [(t, -S + 0.04), (t, S - 0.04), (-S + 0.04, t), (S - 0.04, t)][side_i]
    K.uv_box(K.ball("moss_lump", 1.0, (x, y, BASE + 0.018), moss, scale=(0.045 + 0.025 * rng.random(), 0.045 + 0.025 * rng.random(), 0.02), u=8, v=5), 3.0)


# --- the tilled bed: one heightfield, three furrows with crumbly noise ---------------------------
def bed(nx=36, ny=30):
    noise = K.tile_noise(64, 1.1, 9)
    verts, faces, uvs = [], [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            x = -IN + 2 * IN * u
            y = -IN + 2 * IN * v
            edge = min(u, 1 - u, v, 1 - v)
            fall = min(1.0, edge * 9.0)  # mounds sink into the rim at the ends
            n = noise[int(v * 63), int(u * 63)] - 0.5
            z = BASE - 0.005 + (RIDGE * ridge(u) + 0.022 * n) * fall ** 0.6
            verts.append((x, y, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
            for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                uvs += [(i + di) / nx, (j + dj) / ny]
    me = bpy.data.meshes.new("bed")
    me.from_pydata(verts, [], faces)
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", uvs)
    ob = K._obj("bed", me, soil)
    K.smooth(ob, keep_sharp=False)


bed()

# --- stones and grass tufts ------------------------------------------------------------------------
for x, y, r in ((-0.38, -0.36, 0.045), (0.41, 0.3, 0.035), (0.12, -0.42, 0.022), (-0.3, 0.38, 0.02), (0.05, 0.1, 0.015)):
    st = K.ball("stone", 1.0, (x, y, BASE + r * 0.5), pebble, scale=(r * 1.3, r, r * 0.8), u=7, v=5)
    for vtx in st.data.vertices:  # chip it into a rough faceted pebble
        vtx.co *= 0.85 + 0.3 * rng.random()


def tuft(x, y, h, n=5):
    for k in range(n):
        a = k / n * math.tau + rng.random()
        tilt = 18 + rng.random() * 22
        b = K.cyl("blade", 0.024, 0.0, h * (0.7 + 0.5 * rng.random()), (0, 0, 0), blade if k % 2 else blade_dark, verts=3)
        b.scale = (2.0, 0.4, 1.0)
        b.location = (x + 0.012 * math.cos(a), y + 0.012 * math.sin(a), BASE + 0.01 + b.dimensions.z / 2 * 0.9)
        b.rotation_euler = (math.radians(tilt) * math.sin(a), -math.radians(tilt) * math.cos(a), a)


spots = [(-0.47, 0.15), (-0.46, -0.1), (0.47, -0.2), (0.46, 0.42), (0.2, 0.47), (-0.15, 0.47), (-0.2, -0.47),
         (0.3, -0.47), (0.47, 0.05), (-0.47, 0.42), (-0.44, -0.44)]
for x, y in spots:
    tuft(x, y, 0.09 + 0.06 * rng.random())

K.finish(NAME, os.path.join(HERE, "out"), max_tris=6000)
