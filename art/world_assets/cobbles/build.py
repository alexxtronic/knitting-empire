"""Cobblestones in 3D, after Alex's painted cobble texture (assets/textures/cobblestone.png): warm grey
pillow-shaped stones in rough rows, set in white cement that fills the joints.

Two tiles that repeat with no seams:

  plaza  4 x 2 m. Rows of stones in running bond across the whole tile. A stone that crosses the
         left or right edge is cut exactly at the edge, and the tile beside it carries the rest, so
         the grid joins invisibly. Rows fill the depth exactly, so the front and back edges join too.
  lane   1 x 1 m, for the town paths. The stones fit inside the 1 m width (the lane's sides are
         finished) and the rows repeat along its length.

The stones' tops sit 6-9 cm above the mortar; the mortar is 1 cm above the ground (so it never
lies flush with the grass). Front faces -Y here (+Z in Godot); the lane runs along Y here (Z in
Godot).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/cobbles/build.py -- plaza 0

Variants: plaza 0..3, lane 0..1.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["plaza", "0"]
KIND = ARGS[0]
VARIANT = int(ARGS[1]) if len(ARGS) > 1 else 0
NAME = "cobble_%s_%d" % (KIND, VARIANT)
OUT = os.path.join(HERE, KIND)
TEX = os.path.join(HERE, "tex")
K.reset(NAME)
rng = np.random.default_rng(1000 * VARIANT + {"plaza": 7, "lane": 19}[KIND])

# A professional sett pattern: rows of even depth, stones of one length laid in running bond
# (every other row shifted half a stone), with even joints. Each variant has the same layout and
# the same stones along its side edges, so all variants join each other; only the stones inside
# differ (shape, height, tone), and the game mixes variants so the plaza never visibly repeats.
SETT_L = 4.0 / 14  # stone length along a row
SETT_D = 0.2       # row depth
W, H = (4.0, 2.0) if KIND == "plaza" else (1.0, 0.8)
BASE = 0.01        # where the stones are set, above the ground
FILL = 0.035       # top of the cement between the stones: it fills the joints up their sides
GAP = 0.016        # spacing between stones
SPREAD = 1.06      # stone footprint scale, over the spacing
STONE = np.array(K.hex_rgb("#8f8078"))
STONE_WARM = np.array(K.hex_rgb("#a08a7c"))
STONE_COOL = np.array(K.hex_rgb("#7d7672"))
CEMENT = np.array(K.hex_rgb("#e6e1d7"))
CEMENT_DIRTY = np.array(K.hex_rgb("#b9b1a3"))


# --- textures (shared by both tiles; built once, reused if present) ---------------------------

def stone_maps(n=512):
    """Mottled stone. Its broad patches differ in tone, and each stone samples its own spot, so
    neighbours don't match."""
    big = K.tile_noise(n, 2.2, 101)
    mid = K.tile_noise(n, 1.5, 103)
    fine = K.tile_noise(n, 0.7, 107)
    t = np.clip((big[..., None] - 0.5) * 1.8 + 0.5, 0, 1)
    rgb = STONE_COOL * (1 - t) + STONE_WARM * t
    dark = np.clip((0.35 - K.tile_noise(n, 2.0, 109)) * 3, 0, 1)[..., None]  # some stones darker
    rgb = rgb * (1 - 0.3 * dark)
    rgb = rgb * (0.86 + 0.24 * mid[..., None]) * (0.94 + 0.1 * fine[..., None])
    speck = np.clip((fine - 0.78) * 6, 0, 1)[..., None]
    rgb = rgb * (1 - 0.3 * speck) + np.array(K.hex_rgb("#c9bdb2")) * 0.3 * speck
    hgt = 0.5 * mid + 0.6 * fine
    return K.save_image("cobble_stone", rgb, TEX), K.save_image("cobble_stone_normal", K.normal_from_height(hgt, 2.0), TEX)


def mortar_maps(n=512):
    """White cement: a warm off-white with soft cloudy patches, fine grit and a little grime.
    Tileable, and it repeats every metre on both tiles."""
    a = K.tile_noise(n, 1.7, 201)
    b = K.tile_noise(n, 0.5, 203)
    g = K.tile_noise(n, 2.2, 205)
    rgb = CEMENT * (0.9 + 0.12 * a[..., None]) * (0.96 + 0.06 * b[..., None])
    grime = np.clip((g - 0.6) * 2.5, 0, 1)[..., None] * 0.25
    rgb = rgb * (1 - grime) + CEMENT_DIRTY * grime
    grit = np.clip((b - 0.8) * 8, 0, 1)[..., None]
    rgb = rgb * (1 - 0.18 * grit)
    return K.save_image("cobble_cement", rgb, TEX), K.save_image("cobble_cement_normal", K.normal_from_height(0.4 * a + 0.8 * b, 1.2), TEX)


def get_or_make(make, names):
    paths = [os.path.join(TEX, nm + ".png") for nm in names]
    if all(os.path.exists(p) for p in paths):
        imgs = []
        for p in paths:
            img = bpy.data.images.load(p)
            img.pack()
            imgs.append(img)
        return imgs
    return make()


s_img, s_nrm = get_or_make(stone_maps, ["cobble_stone", "cobble_stone_normal"])
m_img, m_nrm = get_or_make(mortar_maps, ["cobble_cement", "cobble_cement_normal"])
stone_mat = K.textured("Cobble_stone", s_img, rough=0.86, normal=s_nrm, normal_strength=0.8)
mortar_mat = K.textured("Cobble_mortar", m_img, rough=0.95, normal=m_nrm, normal_strength=0.8)


# --- a stone ---------------------------------------------------------------------------------

def stone(cx, cy, w, d, h, rng=rng):
    """A cobble: a rounded, slightly lopsided pillow w x d, its top h above the ground. Only the
    part above the mortar is modelled. UVs are a top-down projection from a random spot in the
    stone texture, so each stone has its own colouring."""
    U, V = 12, 3
    # a little oversize: the bases tuck under their neighbours below the cement, so only thin
    # joints show between the domes
    a, b = w / 2 * SPREAD, d / 2 * SPREAD
    ph = rng.uniform(0, 2 * np.pi, 3)
    amp = rng.uniform(0.008, 0.025, 3)
    tilt = rng.normal(0, 0.006, 2)
    du, dv = rng.uniform(0, 1, 2)
    p = rng.uniform(0.28, 0.42)  # squareness of the footprint (1 = oval): setts are near square
    verts, faces, uvs = [], [], []
    for j in range(V + 1):
        phi = (math.pi / 2) * j / V
        rr = math.cos(phi) ** 0.55 if j < V else 0.0
        z = h * math.sin(phi) ** 0.7
        for i in range(U):
            th = 2 * math.pi * i / U
            c, s = math.cos(th), math.sin(th)
            wob = 1 + amp[0] * math.sin(2 * th + ph[0]) + amp[1] * math.sin(3 * th + ph[1]) + amp[2] * math.sin(5 * th + ph[2])
            x = a * rr * wob * math.copysign(abs(c) ** p, c)
            y = b * rr * wob * math.copysign(abs(s) ** p, s)
            verts.append((cx + x, cy + y, BASE - 0.012 + z + tilt[0] * x * 10 + tilt[1] * y * 10))
            if j == V:
                break
    top = len(verts) - 1
    for j in range(V - 1):
        for i in range(U):
            a0, a1 = j * U + i, j * U + (i + 1) % U
            faces.append((a0, a1, a1 + U, a0 + U))
    for i in range(U):
        faces.append(((V - 1) * U + i, (V - 1) * U + (i + 1) % U, top))
    me = bpy.data.meshes.new("stone")
    me.from_pydata(verts, [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = verts[me.loops[li].vertex_index]
            uvl.data[li].uv = ((co[0] - cx) / 0.9 + du, (co[1] - cy) / 0.9 + dv)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return K._obj("stone", me, stone_mat)


def cut(ob, x0, x1):
    """Trims a stone to x0..x1 (the tile's side edges), leaving the cut open: the neighbouring tile
    holds the other part, so nothing shows through."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for co, no in (((x1, 0, 0), (1, 0, 0)), ((x0, 0, 0), (-1, 0, 0))):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(ob.data)
    bm.free()
    if not ob.data.vertices:
        bpy.data.objects.remove(ob)


# --- the tile --------------------------------------------------------------------------------

def lay(cx, cy, length, row, edge=False):
    """One sett. Edge stones draw from a generator fixed by their row, so every variant has the
    very same stone there and the variants join."""
    r = np.random.default_rng(5000 + row) if edge else rng
    size = 1 + r.normal(0, 0.015)
    return stone(cx, cy, (length - GAP) * size, (SETT_D - GAP) * size, r.uniform(0.055, 0.072), r)


rows = int(round(H / SETT_D))
for row in range(rows):
    cy = -H / 2 + (row + 0.5) * SETT_D
    if KIND == "plaza":
        # odd rows shift half a stone; their first stone straddles the side edge, so it is laid
        # twice (here and one tile over) and both copies are trimmed at the edges
        shift = SETT_L / 2 if row % 2 else 0.0
        n = int(round(W / SETT_L))
        for k in range(n):
            cx = -W / 2 + shift + (k + 0.5) * SETT_L
            edge = cx + SETT_L / 2 > W / 2 + 1e-6
            st = lay(cx, cy, SETT_L, row, edge)
            if edge:
                twin = st.copy()
                twin.data = st.data.copy()
                twin.location.x -= W
                K._link(twin)
                bpy.context.view_layer.update()
                twin.data.transform(twin.matrix_basis)
                twin.matrix_basis.identity()
                cut(twin, -W / 2, W / 2)
                cut(st, -W / 2, W / 2)
    else:
        # across the 1 m lane: three whole setts and a half, the half at alternate ends
        lengths = [SETT_L] * 3 + [W - 3 * SETT_L]
        if row % 2:
            lengths.reverse()
        x = -W / 2
        for ln in lengths:
            lay(x + ln / 2, cy, ln, row)
            x += ln

# the cement: one quad a few cm up the stones' sides, its texture repeating every metre so it joins across tiles
me = bpy.data.meshes.new("bed")
me.from_pydata([(-W / 2, -H / 2, FILL), (W / 2, -H / 2, FILL), (W / 2, H / 2, FILL), (-W / 2, H / 2, FILL)], [], [(0, 1, 2, 3)])
me.uv_layers.new(name="UVMap").data.foreach_set("uv", [0, 0, W, 0, W, H, 0, H])
K._obj("bed", me, mortar_mat)

K.finish(NAME, os.path.join(OUT, "out_%d" % VARIANT), max_tris=12000)
