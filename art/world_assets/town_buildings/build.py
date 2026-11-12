"""Maplewood's shop fronts: Woolly Goods, the bakery and the land office.

One parametric builder for all three, sized to the rects in scripts/town.gd (SHOP, BAKERY, OFFICE):
a stone plinth, walls (half-timbered plaster, or brick with stone quoins for the office), a gable
facing the street with a small window in it, a shingle roof with real overhangs and a chimney,
recessed mullioned windows lit warm from inside with shutters and flower boxes, a plank door up a
stone step, and each shop's own extras (striped awnings and a yarn basket, a bread crate and a
chalkboard, a porch and a notice board).

The sign board sits where town.gd puts its lettering (a Label3D, so the names stay editable text).
The shops with a hanging sign (art/world_assets/shop_signs, HANGING_SIGN) have no board: town.gd
hangs the sign there instead.

You can walk in, so the model is exported in parts, like the barn (scripts/interiors.gd opens it up):

    base                      plank floor, threshold, and the things standing outside: always shown
    wall_front|back|left|right    each wall at full height, hollow, with its windows, timbers and trim
                              (the gables go with front and back, the sign with the front)
    wall_*_low                the same wall cut down to a stub, shown instead when it faces the camera
    door                      the door leaf, its origin on the hinge line (left jamb) so it can swing in
    roof                      roof, barge boards, ridge and chimney: hidden while she is inside

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/town_buildings/build.py -- shop|bakery|office

Writes art/world_assets/town_buildings/<kind>/out/building_<kind>.glb and copies it to assets/props.
Front (the door) faces -Y here (+Z in Godot).
"""
import json
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

KIND = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "shop"
NAME = "building_" + KIND
TEX = os.path.join(HERE, KIND, "tex")
OUT = os.path.join(HERE, KIND, "out")
K.reset(NAME)

SPECS = {
    "shop": dict(w=6.0, d=5.0, walls="#e9d9b8", timber="#4d301c", roof="#5d6876", shingle="scale",
                 trim="#8fb3c7", awning=("#8fb3c7", "#f1e8d6"), interior="yarn", chimney=1, extras="yarn"),
    "bakery": dict(w=5.5, d=4.5, walls="#f3e6cb", timber="#5a3920", roof="#b8663f", shingle="tile",
                   trim="#e3a66d", awning=("#9a2a44", "#f1e8d6"), interior="bread", chimney=-1, extras="bread"),
    "office": dict(w=5.5, d=5.0, walls="brick", timber="#3e2a1d", roof="#4d4946", shingle="slate",
                   trim="#d9c58c", awning=None, interior="office", chimney=1, extras="office"),
    # the home goods store (2026-11-12: wood for the sheep pen, and the odds and ends a house needs),
    # narrower, in the gap between Heart Bakery and the Yarn Barn
    "homegoods": dict(w=5.0, d=4.4, walls="#d9e2cc", timber="#4a3322", roof="#5f7d5b", shingle="tile",
                      trim="#e3bf78", awning=("#4f7a54", "#f1e8d6"), interior="tools", chimney=-1, extras="tools"),
}
S = SPECS[KIND]
W, D = S["w"], S["d"]
H = 3.4  # eaves
BAND = 2.74  # the timber band over the door, below the sign
SIGN_Z = H - 0.38  # the sign board's centre (town.gd puts the name there)
HANGING_SIGN = ("shop", "bakery", "office", "homegoods")  # town.gd hangs a carved sign (shop_signs) here, no board
G = 1.6  # gable rise
PL = 0.35  # plinth height
FRONT = -D / 2
rng = np.random.default_rng({"shop": 3, "bakery": 7, "office": 11, "homegoods": 17}[KIND])


def rgb(h):
    return np.array(K.hex_rgb(h))


# --- textures ------------------------------------------------------------------------------------

def plaster_maps(hexcol, n=512):
    mott = K.tile_noise(n, 1.7, 5)
    fine = K.tile_noise(n, 0.6, 9)
    trowel = K.grain_noise(n, 6.0, 1.1, 13)
    col = rgb(hexcol) * (0.9 + 0.12 * mott[..., None]) * (0.97 + 0.05 * fine[..., None])
    col = col * (0.98 + 0.04 * trowel[..., None])
    hgt = 0.6 * mott + 0.5 * fine + 0.3 * trowel
    return K.save_image("plaster_" + KIND, col, TEX), K.save_image("plaster_%s_n" % KIND, K.normal_from_height(hgt, 1.2), TEX)


def block_maps(name, base, mortar, n=512, blocks=4, courses=8, joint=5, jitter=0.3, chamfer=2.5, seed=1):
    """Bonded blocks (bricks or dressed stone) with mortar joints; tileable."""
    mott = K.tile_noise(n, 1.4, seed)
    speck = K.tile_noise(n, 0.4, seed + 3)
    yy, xx = np.mgrid[0:n, 0:n]
    ch, bw = n / courses, n / blocks
    row = (yy // ch).astype(int)
    xo = (xx + (row % 2) * bw / 2) % n
    col_i = (xo // bw).astype(int)
    r = np.random.default_rng(seed)
    tint = (1 - jitter / 2 + jitter * r.random((courses, blocks)))[row, col_i]
    warm = (r.random((courses, blocks)) - 0.5)[row, col_i][..., None] * np.array([0.06, 0.01, -0.04])
    c = rgb(base) * (0.86 + 0.24 * mott[..., None]) * (0.95 + 0.1 * speck[..., None]) * tint[..., None] + warm
    d = np.minimum(np.minimum(xo % bw, bw - xo % bw), np.minimum(yy % ch, ch - yy % ch))
    j = np.clip(1 - d / joint, 0, 1)[..., None]
    c = c * (1 - j) + rgb(mortar) * (0.9 + 0.15 * speck[..., None]) * j
    hgt = 0.3 * mott + 0.2 * speck + 2.0 * np.clip(d / (joint * chamfer), 0, 1)
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.4), TEX)


def shingle_maps(hexcol, style, n=512):
    """Roof shingles in rows running across the image; v runs down the roof (row 0 = ridge side).
    style: 'scale' (round-bottomed fish scales), 'tile' (clay tiles), 'slate' (square slates)."""
    rows, per = (10, 8) if style != "tile" else (9, 6)
    yy, xx = np.mgrid[0:n, 0:n]
    rh, sw = n / rows, n / per
    row = (yy // rh).astype(int)
    xo = (xx + (row % 2) * sw / 2) % n
    ci = (xo // sw).astype(int)
    fx = (xo % sw) / sw - 0.5  # -0.5..0.5 across a shingle
    fy = (yy % rh) / rh  # 0 at its top, 1 at its bottom edge
    if style == "scale":
        edge = 0.55 + 0.45 * np.sqrt(np.clip(1 - (2 * fx) ** 2, 0, 1))  # round bottom
    elif style == "tile":
        edge = np.ones_like(fx)
    else:
        edge = np.ones_like(fx) - 0.05 * (np.abs(fx) > 0.46)
    inside = fy < edge
    r = np.random.default_rng(5)
    tint = (0.82 + 0.3 * r.random((rows, per)))[row, ci]
    mott = K.tile_noise(n, 1.3, 17)
    c = rgb(hexcol) * tint[..., None] * (0.9 + 0.16 * mott[..., None])
    thick = np.where(inside, fy / np.maximum(edge, 1e-3), 0.0)  # thicker toward the bottom edge
    if style == "tile":
        thick = thick * (0.6 + 0.4 * np.cos(fx * math.tau) ** 2)  # rolled clay
        c = c * (0.85 + 0.25 * np.cos(fx * math.pi)[..., None])
    shade = np.where(inside, 1.0, 0.55)  # under the next shingle's edge
    c = c * (0.75 + 0.3 * thick[..., None]) * shade[..., None]
    hgt = thick * 1.0 + 0.2 * mott
    return (K.save_image("roof_" + KIND, c, TEX), K.save_image("roof_%s_n" % KIND, K.normal_from_height(hgt, 2.5), TEX))


def timber_image(hexcol, n=256):
    g = K.grain_noise(n, 30.0, 1.2, 4)
    c = rgb(hexcol) * (0.85 + 0.3 * g[..., None])
    return K.save_image("timber_" + KIND, c, TEX)


def stripes_image(a, b, n=256, k=8):
    x = np.arange(n)
    s = ((x // (n // k)) % 2)[None, :, None]
    weave = K.tile_noise(n, 0.5, 3)[..., None]
    c = (rgb(a) * s + rgb(b) * (1 - s)) * (0.92 + 0.12 * weave)
    return K.save_image("awning_" + KIND, np.broadcast_to(c, (n, n, 3)).copy(), TEX)


def uv_roof(ob, side, ridge_z, ang, scale=0.9):
    """Roof UVs: u along the ridge, v down the slope from the ridge, so shingle rows run level."""
    me = ob.data
    layer = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    down = Vector((side * math.cos(ang), 0, -math.sin(ang)))
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = ob.matrix_world @ me.vertices[me.loops[li].vertex_index].co
            layer.data[li].uv = (p.y * scale, -(p - Vector((0, 0, ridge_z))).dot(down) * scale)


# --- materials -----------------------------------------------------------------------------------

if S["walls"] == "brick":
    bc, bn = block_maps("brick_" + KIND, "#a8684a", "#d6c9b0", blocks=4, courses=10, joint=4, jitter=0.35, seed=21)
    WALL = K.textured("walls_" + KIND, bc, 0.9, normal=bn)
else:
    pc, pn = plaster_maps(S["walls"])
    WALL = K.textured("walls_" + KIND, pc, 0.92, normal=pn)
sc_, sn = block_maps("stone_" + KIND, "#9a958a", "#6b665e", blocks=3, courses=4, joint=6, jitter=0.3, seed=4)
STONE = K.textured("stone_" + KIND, sc_, 0.9, normal=sn)
rc, rn = shingle_maps(S["roof"], S["shingle"])
ROOF = K.textured("roof_" + KIND, rc, 0.85, normal=rn, normal_strength=1.2)
TIMBER = K.textured("timber_" + KIND, timber_image(S["timber"]), 0.85)
DOOR = K.textured("door_" + KIND, K.wood_image("door_" + KIND, TEX, seed=8, planks=5), 0.8)
TRIM = K.plain("trim_" + KIND, S["trim"], 0.7)
FRAME = K.plain("frame_" + KIND, "#efe6d2", 0.7)
GLASS = K.plain("glass_" + KIND, "#cfe0e4", 0.05, alpha=0.3)
FLOOR = K.textured("floor_" + KIND, K.wood_image("floor_" + KIND, TEX, seed=12, planks=8), 0.75)
BRASS = K.plain("brass", "#c9a24a", 0.35)
IRON = K.plain("iron", "#2b2826", 0.6)
SIGN = K.plain("sign_" + KIND, "#efe2c4", 0.8)
LEAF = K.plain("leaf", "#5f7d45", 0.85)
SOIL = K.plain("soil", "#4a3324", 0.95)
AWN = K.textured("awning_" + KIND, stripes_image(*S["awning"]), 0.9) if S["awning"] else None


# --- wall frames: each wall seen from outside ------------------------------------------------------

WALLS = {
    "front": (Vector((1, 0, 0)), Vector((0, -1, 0)), Vector((0, -D / 2, 0)), W),
    "back": (Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, D / 2, 0)), W),
    "right": (Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((W / 2, 0, 0)), D),
    "left": (Vector((0, -1, 0)), Vector((-1, 0, 0)), Vector((-W / 2, 0, 0)), D),
}


def wbox(name, wall, a, out, z, sa, so, sz, mat, bevel=0.012):
    """A box placed on a wall: a along it, out from its face, z up; sizes along/out/up. In a cut-down
    wall (CAP set) it is clipped to the stub's height, or left out if it starts above it."""
    if CAP is not None:
        z0 = z - sz / 2
        if z0 >= CAP - 0.01:
            return None
        if z + sz / 2 > CAP:
            sz = CAP - z0
            z = z0 + sz / 2
    al, ou, c, _ = WALLS[wall]
    pos = c + al * a + ou * out + Vector((0, 0, z))
    size = (abs(al.x) * sa + abs(ou.x) * so, abs(al.y) * sa + abs(ou.y) * so, sz)
    ob = K.box(name, size, tuple(pos), mat, bevel=bevel, seg=1)
    return ob


def wpane(name, wall, a, out, z0, z1, width, mat):
    al, ou, c, _ = WALLS[wall]
    base = c + ou * out
    p0 = base + al * (a - width / 2) + Vector((0, 0, z0))
    p1 = base + al * (a + width / 2) + Vector((0, 0, z1))
    return K.pane(name, tuple(p0), tuple(p1), mat, tuple(ou))


CUTTERS = []
CAP = None  # the height of the wall being built, when it is the cut-down stub
T = 0.2  # wall thickness: the walls are hollow, so she can walk in


def cut(wall, a, z0, z1, width):
    """An opening right through the wall (and its plinth and gable)."""
    al, ou, c, _ = WALLS[wall]
    pos = c + al * a + Vector((0, 0, (z0 + z1) / 2))
    size = (abs(al.x) * width + abs(ou.x) * 1.0, abs(al.y) * width + abs(ou.y) * 1.0, z1 - z0)
    ob = K.box("cut", size, tuple(pos), WALL, bevel=0)
    CUTTERS.append(ob)


REVEAL = 0.16  # how deep windows and the door sit in the wall


def window(wall, a, z0, z1, width, flowers=True, shutters=True, awning=False):
    if CAP is not None and z0 - 0.3 >= CAP:
        return  # all of it is above the stub
    cut(wall, a, z0, z1, width)
    wpane("glass", wall, a, -REVEAL + 0.005, z0, z1, width, GLASS)
    t = 0.06
    # frame and mullions (a cross)
    for zz in (z0 + t / 2, z1 - t / 2):
        wbox("wf", wall, a, -REVEAL + 0.03, zz, width, 0.05, t, FRAME)
    for aa in (a - width / 2 + t / 2, a + width / 2 - t / 2, a):
        wbox("wf", wall, aa, -REVEAL + 0.03, (z0 + z1) / 2, t * (0.7 if aa == a else 1), 0.05, z1 - z0, FRAME)
    wbox("wf", wall, a, -REVEAL + 0.03, (z0 + z1) / 2, width, 0.04, t * 0.7, FRAME)
    # stone sill
    wbox("sill", wall, a, 0.04, z0 - 0.05, width + 0.24, 0.2, 0.08, STONE)
    if shutters:
        for s in (-1, 1):
            sh = wbox("shutter", wall, a + s * (width / 2 + 0.2), 0.03, (z0 + z1) / 2, 0.36, 0.04, z1 - z0 + 0.06, TRIM)
            for zz in np.linspace(z0 + 0.12, z1 - 0.12, 4):
                wbox("slat", wall, a + s * (width / 2 + 0.2), 0.055, zz, 0.3, 0.015, 0.03, TRIM)
    if flowers:
        wbox("flowerbox", wall, a, 0.16, z0 - 0.2, width + 0.1, 0.22, 0.2, TRIM)
        wbox("soil", wall, a, 0.16, z0 - 0.095, width, 0.17, 0.02, SOIL, bevel=0)
        al, ou, c, _ = WALLS[wall]
        cols = [K.plain("bloom_a", "#9a2a44", 0.8), K.plain("bloom_b", "#f1e8d6", 0.8), K.plain("bloom_c", "#e3a66d", 0.8)]
        for i, f in enumerate(np.linspace(-width / 2 + 0.06, width / 2 - 0.06, 9)):
            pos = c + al * (a + f) + ou * (0.16 + rng.uniform(-0.05, 0.05)) + Vector((0, 0, z0 - 0.07))
            K.ball("leaves", 0.075, tuple(pos), LEAF, scale=(1.2, 1.0, 0.8), u=6, v=4)
            K.ball("bloom", 0.04, tuple(pos + Vector((rng.uniform(-0.03, 0.03), 0, 0.07))), cols[i % 3], u=6, v=4)
    if awning and AWN:
        awning_over(wall, a, z1 + 0.25, width + 0.5)


def awning_over(wall, a, z, width, reach=0.75, drop=0.4):
    al, ou, c, _ = WALLS[wall]
    ang = math.degrees(math.atan2(drop, reach))
    slope = math.hypot(reach, drop)
    pos = c + al * a + ou * (reach / 2) + Vector((0, 0, z - drop / 2))
    rot = (ang if wall == "front" else -ang, 0, 0) if abs(ou.y) > 0.5 else (0, ang, 0)
    ob = K.box("awning", (width, slope, 0.03) if abs(ou.y) > 0.5 else (slope, width, 0.03), tuple(pos), AWN, bevel=0.01, seg=1, rot=rot)
    K.uv_box(ob, 1.0)
    # scalloped valance along the front edge
    n = int(width / 0.22)
    for i in range(n):
        f = -width / 2 + (i + 0.5) * width / n
        p = c + al * (a + f) + ou * (reach + 0.01) + Vector((0, 0, z - drop - 0.07))
        K.ball("scallop", width / n / 2, tuple(p), AWN, scale=(1, 0.15, 1.0), u=8, v=4)
    wbox("valance", wall, a, reach + 0.01, z - drop - 0.02, width, 0.02, 0.1, AWN, bevel=0)
    for s in (-1, 1):
        p0 = c + al * (a + s * (width / 2 - 0.05)) + ou * (reach / 2) + Vector((0, 0, z - drop / 2 - 0.05))
        K.cyl("rod", 0.012, 0.012, slope, tuple(p0), IRON, verts=6, rot=(90 - ang if wall == "front" else -(90 - ang), 0, 0))


# --- parts ---------------------------------------------------------------------------------------

PARTS = {}
HINGES = {}  # part name -> where its origin goes, so the game can swing it


class part:
    """Everything built inside `with part("name"):` is joined into one exported object of that name."""

    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.before = set(K.COLL.objects)

    def __exit__(self, *a):
        PARTS.setdefault(self.name, []).extend(o for o in K.COLL.objects if o not in self.before)


LOW = 0.62  # height of a cut-down wall
DOOR_W, DOOR_H = 1.1, 2.15
DOOR_TOP = PL + DOOR_H  # the doorway runs from the floor: she walks in on the level
front_win = (W / 2 - 0.5) * (0.68 if KIND == "homegoods" else 0.62)  # the narrow shop: windows clear of the door
gw = 0.62  # the little window up in the front gable
TOP_Z = 0.03  # the floor boards' top


# --- walls ---------------------------------------------------------------------------------------

def shell(side):
    """The wall itself (hollow, T thick, outer face where the old solid block's was), its share of
    the stone plinth band, and for the front and back the gable above it. Returns what openings
    are cut out of."""
    al, ou, c, span = WALLS[side]
    top = H if CAP is None else CAP
    length = span if side in ("front", "back") else span - 2 * T  # front and back own the corners
    pos = c - ou * (T / 2) + Vector((0, 0, top / 2))
    size = (abs(al.x) * length + abs(ou.x) * T, abs(al.y) * length + abs(ou.y) * T, top)
    targets = [K.box("wall", size, tuple(pos), WALL, bevel=0)]
    plen = span + 0.3 if side in ("front", "back") else span
    ppos = c + ou * 0.075 + Vector((0, 0, PL / 2))
    psize = (abs(al.x) * plen + abs(ou.x) * 0.15, abs(al.y) * plen + abs(ou.y) * 0.15, PL)
    targets.append(K.box("plinth", psize, tuple(ppos), STONE, bevel=0))
    if CAP is None and side in ("front", "back"):
        y0, y1 = (-D / 2, -D / 2 + T) if side == "front" else (D / 2 - T, D / 2)
        targets.append(K.extrude_xz("gable", [(-W / 2, H), (W / 2, H), (0, H + G)], y0, y1, WALL, bevel=0))
    return targets


def apply_cuts(targets):
    for target in targets:
        for cobj in CUTTERS:
            m = target.modifiers.new("cut", "BOOLEAN")
            m.operation = "DIFFERENCE"
            m.solver = "EXACT"
            m.object = cobj
        K.apply_mods(target)
    for cobj in CUTTERS:
        bpy.data.objects.remove(cobj)
    CUTTERS.clear()
    for target in targets:
        K.uv_box(target, 1.0 if target.name.startswith("plinth") else (0.5 if S["walls"] != "brick" else 0.7))


def timbers(side):
    al, ou, c, span = WALLS[side]
    if S["walls"] != "brick":
        tt = 0.16
        for a in (-span / 2 + tt / 2, span / 2 - tt / 2):
            wbox("post", side, a, 0.025, (PL + H) / 2, tt, 0.06, H - PL, TIMBER)
        wbox("sillbeam", side, 0, 0.03, PL + 0.07, span, 0.07, 0.14, TIMBER)
        wbox("eavebeam", side, 0, 0.03, H - 0.08, span + 0.02, 0.08, 0.16, TIMBER)
        wbox("band", side, 0, 0.025, BAND, span, 0.06, 0.12, TIMBER)
        if side in ("left", "right"):
            for a in (-span / 4, span / 4):
                wbox("post", side, a, 0.025, (BAND + H) / 2, tt * 0.8, 0.05, H - BAND, TIMBER)
        if CAP is None and side in ("front", "back"):
            # gable timbers: braces up to a short king post over the gable window
            side_y = FRONT - 0.03 if side == "front" else D / 2 + 0.03
            for s in (-1, 1):
                x0, z0, x1, z1 = s * (W / 2 - 0.35), H + 0.05, s * 0.55, H + G * 0.62
                L = math.hypot(x1 - x0, z1 - z0)
                ang = math.degrees(math.atan2(z1 - z0, x1 - x0))
                K.box("brace", (L, 0.07, 0.14), ((x0 + x1) / 2, side_y, (z0 + z1) / 2), TIMBER, bevel=0.01, seg=1, rot=(0, -ang, 0))
            K.box("kingpost", (0.14, 0.07, G * 0.3), (0, side_y, H + G * 0.82), TIMBER, bevel=0.01, seg=1)
            K.box("collar", (W * 0.5, 0.07, 0.12), (0, side_y, H + 0.12), TIMBER, bevel=0.01, seg=1)
    else:
        # dressed stone quoins up the corners, a cornice under the eaves, a stone band
        for a in (-span / 2 + 0.17, span / 2 - 0.17):
            for i, zz in enumerate(np.arange(PL + 0.15, H - 0.1, 0.3)):
                wbox("quoin", side, a + (0.06 if i % 2 else -0.0) * np.sign(a), 0.02, zz, 0.42 if i % 2 else 0.3, 0.05, 0.26, STONE)
        wbox("cornice", side, 0, 0.05, H - 0.06, span + 0.1, 0.12, 0.14, STONE)
        wbox("band", side, 0, 0.03, BAND, span, 0.06, 0.1, STONE)
        if CAP is None and side in ("front", "back"):
            K.box("gablecap", (0.3, 0.08, 0.2), (0, FRONT - 0.04 if side == "front" else D / 2 + 0.04, H + G - 0.1), STONE, bevel=0.01, seg=1)


def build_wall(side, low):
    global CAP
    CAP = LOW if low else None
    targets = shell(side)
    if side == "front":
        cut("front", 0, -0.1, DOOR_TOP, DOOR_W)
        for s in (-1, 1):
            window("front", s * front_win, 0.95, 2.05, {"shop": 1.35, "homegoods": 0.86}.get(KIND, 1.15), awning=bool(S["awning"]))
        if CAP is None:
            cut("front", 0, H + 0.35, H + 0.35 + gw, gw)
            # the gable window: a little four-pane window
            wpane("glass", "front", 0, -REVEAL + 0.005, H + 0.35, H + 0.35 + gw, gw, GLASS)
            for zz in (H + 0.35 + 0.03, H + 0.35 + gw - 0.03, H + 0.35 + gw / 2):
                wbox("wf", "front", 0, -REVEAL + 0.03, zz, gw, 0.05, 0.05, FRAME)
            for aa in (-gw / 2 + 0.03, gw / 2 - 0.03, 0):
                wbox("wf", "front", aa, -REVEAL + 0.03, H + 0.35 + gw / 2, 0.05, 0.05, gw, FRAME)
        # door case: jambs either side of the opening, a lintel over it
        for s in (-1, 1):
            wbox("doorcase", "front", s * (DOOR_W / 2 + 0.06), 0.03, DOOR_TOP / 2, 0.14, 0.08, DOOR_TOP + 0.06, TIMBER if S["walls"] != "brick" else STONE)
        wbox("lintel", "front", 0, 0.035, DOOR_TOP + 0.08, DOOR_W + 0.4, 0.09, 0.16, TIMBER if S["walls"] != "brick" else STONE)
    else:
        window(side, 0, 1.0, 2.0, 0.95, flowers=(side != "back"), shutters=True)
    apply_cuts(targets)
    timbers(side)
    if side == "front" and CAP is None:
        if KIND not in HANGING_SIGN:
            sign_board()
        front_extras()
    CAP = None


def sign_board():
    sw = min(W - 0.6, 3.4)
    K.box("signframe", (sw + 0.12, 0.04, 0.56), (0, FRONT - 0.05, SIGN_Z), TIMBER, bevel=0.01, seg=1)
    K.box("signboard", (sw, 0.06, 0.46), (0, FRONT - 0.06, SIGN_Z), SIGN, bevel=0.01, seg=1)


def front_extras():
    """What hangs off the front wall: the bracket signs, the office's porch canopy."""
    ex = S["extras"]
    if ex in ("yarn", "bread", "tools"):
        bx, bz = W / 2 - 0.08, 3.12  # off the corner post, above the awnings
        K.box("bracket", (0.05, 0.7, 0.05), (bx, FRONT - 0.35, bz), IRON, bevel=0.01, seg=1)
    if ex == "yarn":
        yarns = ["#a12b26", "#596b8c"]
        K.cyl("chain", 0.008, 0.008, 0.16, (bx, FRONT - 0.6, bz - 0.09), IRON, verts=5)
        K.ball("yarnsign", 0.17, (bx, FRONT - 0.6, bz - 0.34), K.plain("yarn1", yarns[1], 0.95), u=14, v=9)
        K.cyl("needle", 0.012, 0.012, 0.5, (bx, FRONT - 0.6, bz - 0.32), K.plain("needle", "#b88a57", 0.6), verts=6, rot=(0, 55, 0))
    elif ex == "bread":
        K.cyl("chain", 0.008, 0.008, 0.12, (bx, FRONT - 0.6, bz - 0.07), IRON, verts=5)
        pz = bz - 0.34
        pm = K.plain("pretzel", "#b06e35", 0.75)
        K.torus("pretzel", 0.14, 0.035, (bx, FRONT - 0.6, pz), pm, rot=(90, 0, 0))
        K.torus("pretzel", 0.08, 0.03, (bx - 0.08, FRONT - 0.6, pz + 0.07), pm, rot=(90, 0, 0))
        K.torus("pretzel", 0.08, 0.03, (bx + 0.08, FRONT - 0.6, pz + 0.07), pm, rot=(90, 0, 0))
    elif ex == "tools":
        # a hammer hanging off the bracket, the old sign for a hardware shop
        K.cyl("chain", 0.008, 0.008, 0.12, (bx, FRONT - 0.6, bz - 0.07), IRON, verts=5)
        hz = bz - 0.36
        K.cyl("handle", 0.022, 0.026, 0.44, (bx, FRONT - 0.6, hz - 0.06), K.plain("handle", "#b88a57", 0.6), verts=8)
        K.box("hammerhead", (0.3, 0.075, 0.09), (bx, FRONT - 0.6, hz + 0.17), IRON, bevel=0.012, seg=1)
    elif ex == "office":
        # a little porch: two columns carrying a flat stone canopy over the door, kept below the sign
        for s in (-1, 1):
            K.cyl("column", 0.09, 0.08, 2.5, (s * 0.85, FRONT - 0.55, 0.06 + 1.25), K.plain("column", "#e8dfcc", 0.8), verts=14)
        K.box("porchroof", (2.2, 0.85, 0.12), (0, FRONT - 0.4, PL + 2.3), STONE, bevel=0.02)
        K.box("porchcornice", (2.34, 0.95, 0.06), (0, FRONT - 0.43, PL + 2.39), STONE, bevel=0.015)


# --- door ----------------------------------------------------------------------------------------

def build_door():
    """One plank leaf with a glazed top, hung on the left jamb, opening inward."""
    leaf_h = DOOR_TOP - TOP_Z - 0.02
    dz = TOP_Z + 0.01 + leaf_h / 2
    door = wbox("door", "front", 0, -REVEAL + 0.04, dz, DOOR_W - 0.06, 0.06, leaf_h, DOOR)
    K.uv_box(door, 1.0)
    g0, g1 = DOOR_TOP - 1.15, DOOR_TOP - 0.55
    wbox("doorglass", "front", 0, -REVEAL + 0.04, (g0 + g1) / 2, 0.6, 0.07, g1 - g0, GLASS)
    for side_out in (-REVEAL + 0.085, -REVEAL - 0.005):  # glazing bars and panels on both faces
        for zz in (g0, g1, (g0 + g1) / 2):
            wbox("df", "front", 0, side_out, zz, 0.62, 0.02, 0.04, TIMBER)
        wbox("df", "front", 0, side_out, (g0 + g1) / 2, 0.04, 0.02, 0.6, TIMBER)
        for zz in (TOP_Z + 0.4, TOP_Z + 1.0):
            wbox("panel", "front", 0, side_out - 0.003 * (1 if side_out > -REVEAL else -1), zz, 0.7, 0.015, 0.42, DOOR)
    for y in (FRONT + REVEAL - 0.1, FRONT + REVEAL + 0.02):
        K.ball("knob", 0.035, (DOOR_W / 2 - 0.19, y, TOP_Z + 1.0), BRASS)
    HINGES["door"] = (-DOOR_W / 2 + 0.03, FRONT + REVEAL - 0.04, 0.0)


# --- base: floor, threshold, and what stands outside ---------------------------------------------

def build_base():
    fl = K.box("floor", (W - 2 * T + 0.02, D - 2 * T + 0.02, 0.05), (0, 0, TOP_Z - 0.025), FLOOR, bevel=0)
    K.uv_box(fl, 0.6, grain="y")
    th = K.box("threshold", (DOOR_W + 0.1, T + 0.02, 0.05), (0, FRONT + T / 2, TOP_Z - 0.02), STONE, bevel=0.01)
    K.uv_box(th, 1.0)
    step = K.box("step", (1.6, 0.5, 0.05), (0, FRONT - 0.25, 0.015), STONE, bevel=0.015)
    K.uv_box(step, 1.0)
    ex = S["extras"]
    if ex == "yarn":
        bx = -(DOOR_W / 2 + 0.55)
        K.cyl("basket", 0.26, 0.3, 0.3, (bx, FRONT - 0.45, 0.15), K.textured("wicker", K.wood_image("wicker", TEX, seed=3, planks=12), 0.9), verts=16)
        yarns = ["#a12b26", "#596b8c", "#9eae8f", "#edddbd", "#9a2a44", "#b88a57", "#e3a66d"]
        for i in range(7):
            a = i / 7 * math.tau
            p = (bx + 0.13 * math.cos(a), FRONT - 0.45 + 0.13 * math.sin(a), 0.33 + 0.04 * (i % 2))
            K.ball("yarn", 0.1, p, K.plain("yarn%d" % i, yarns[i], 0.95), u=10, v=7)
        K.ball("yarn", 0.1, (bx, FRONT - 0.45, 0.42), K.plain("yarn0", yarns[0], 0.95), u=10, v=7)
    elif ex == "bread":
        bx = DOOR_W / 2 + 0.6
        crate = K.box("crate", (0.6, 0.45, 0.35), (bx, FRONT - 0.42, 0.18), DOOR, bevel=0.02)
        K.uv_box(crate, 1.5)
        loaf = K.plain("loaf", "#c98b4a", 0.8)
        for i in range(5):
            K.ball("loaf", 0.09, (bx - 0.2 + i * 0.1, FRONT - 0.42 + rng.uniform(-0.08, 0.08), 0.39), loaf, scale=(1.4, 0.8, 0.7), u=10, v=6)
        cbx = -(DOOR_W / 2 + 0.7)
        for s in (-1, 1):
            K.box("aframe", (0.5, 0.04, 0.8), (cbx, FRONT - 0.55 + s * 0.12, 0.4), DOOR, bevel=0.01, seg=1, rot=(s * 12, 0, 0))
        K.box("chalk", (0.42, 0.01, 0.6), (cbx, FRONT - 0.55 - 0.145, 0.42), K.plain("chalk", "#2f3530", 0.9), bevel=0, rot=(-12, 0, 0))
    elif ex == "office":
        for s in (-1, 1):
            K.box("plinthblock", (0.26, 0.26, 0.12), (s * 0.85, FRONT - 0.55, 0.06), STONE, bevel=0.02)
        K.box("porchfloor", (2.2, 0.9, 0.05), (0, FRONT - 0.45, 0.015), STONE, bevel=0.015)
        nbx, nby, nbz = W / 2 - 0.35, FRONT - 1.0, 1.25
        for s_ in (-1, 1):
            K.box("noticepost", (0.07, 0.07, nbz + 0.38), (nbx + s_ * 0.45, nby, (nbz + 0.38) / 2), DOOR, bevel=0.01, seg=1)
        nb = K.box("notice", (0.8, 0.05, 0.6), (nbx, nby, nbz), DOOR, bevel=0.01, seg=1)
        K.uv_box(nb, 1.5)
        K.box("noticecap", (1.02, 0.16, 0.05), (nbx, nby, nbz + 0.4), DOOR, bevel=0.01, seg=1)
        paper = K.plain("paper", "#f1e8d6", 0.9)
        for i, (px, pz) in enumerate(((-0.2, 0.08), (0.12, 0.12), (-0.05, -0.15), (0.22, -0.12))):
            K.box("paper", (0.18, 0.006, 0.22), (nbx + px, nby - 0.03, nbz + pz), paper, bevel=0, rot=(0, rng.uniform(-6, 6), 0))
        K.cyl("postbox", 0.16, 0.16, 0.9, (-(DOOR_W / 2 + 1.45), FRONT - 0.45, 0.45), K.plain("postbox", "#9a2a44", 0.6), verts=14)
        K.ball("postboxtop", 0.16, (-(DOOR_W / 2 + 1.45), FRONT - 0.45, 0.9), K.plain("postbox", "#9a2a44", 0.6), scale=(1, 1, 0.5), u=14, v=6)


# --- roof ----------------------------------------------------------------------------------------

def build_roof():
    OVER_E, OVER_G, THK = 0.4, 0.3, 0.12
    half = W / 2 + OVER_E
    rise = G * half / (W / 2)
    ang = math.atan2(G, W / 2)
    slope = math.hypot(half, rise)
    ridge_z = H + G + 0.06
    for s in (-1, 1):
        cx = s * half / 2
        cz = ridge_z - rise / 2
        ob = K.box("roof", (slope + 0.06, D + 2 * OVER_G, THK), (cx, 0, cz), ROOF, bevel=0.02, seg=1,
                   rot=(0, math.degrees(ang) * s, 0))
        uv_roof(ob, s, ridge_z, ang)
        for yy in (-(D / 2 + OVER_G), D / 2 + OVER_G):
            K.box("barge", (slope, 0.05, 0.2), (cx, yy, cz - 0.06), TIMBER, bevel=0.01, seg=1, rot=(0, math.degrees(ang) * s, 0))
        K.box("fascia", (0.05, D + 2 * OVER_G + 0.04, 0.2), (s * (half + 0.03), 0, ridge_z - rise - 0.04), TIMBER, bevel=0.01, seg=1)
    K.cyl("ridge", 0.09, 0.09, D + 2 * OVER_G + 0.04, (0, 0, ridge_z + 0.02), ROOF, verts=10, rot=(90, 0, 0))
    # chimney through the roof, on one slope toward the back
    cxs = S["chimney"] * W * 0.24
    roof_z_at = ridge_z - abs(cxs) * math.tan(ang)
    ch_h = roof_z_at + 0.9 - H
    ch = K.box("chimney", (0.6, 0.6, ch_h), (cxs, D * 0.2, H + ch_h / 2), STONE, bevel=0.02)
    K.uv_box(ch, 1.2)
    K.box("chimneycap", (0.75, 0.75, 0.1), (cxs, D * 0.2, H + ch_h + 0.05), STONE, bevel=0.02)
    for s in (-1, 1):
        K.cyl("pot", 0.08, 0.07, 0.25, (cxs + s * 0.14, D * 0.2, H + ch_h + 0.22), K.plain("pot", "#b8663f", 0.85), verts=10)


# --- export --------------------------------------------------------------------------------------

def join_part(name, obs, origin=None):
    for o in obs:
        K.apply_mods(o)
        if "UVMap" not in o.data.uv_layers:
            if o.data.uv_layers:
                o.data.uv_layers[0].name = "UVMap"
            else:
                o.data.uv_layers.new(name="UVMap")
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = NAME + "_" + name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if origin is not None:  # the door: put the object's origin on its hinge line
        for v in ob.data.vertices:
            v.co -= Vector(origin)
        ob.location = origin
    return ob


def main():
    with part("base"):
        build_base()
    for side in ("front", "back", "left", "right"):
        with part("wall_" + side):
            build_wall(side, False)
        with part("wall_" + side + "_low"):
            build_wall(side, True)
    with part("door"):
        build_door()
    with part("roof"):
        build_roof()
    bpy.context.view_layer.update()
    obs = [join_part(n, [o for o in o_ if o.name in bpy.data.objects], HINGES.get(n)) for n, o_ in PARTS.items() if o_]
    stats = {"name": NAME, "parts": {}, "triangles": 0}
    for o in obs:
        t = K.tri_count(o)
        stats["parts"][o.name] = {"triangles": t, "materials": [m.name for m in o.data.materials]}
        stats["triangles"] += t
    os.makedirs(OUT, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, NAME + ".blend"))
    for o in bpy.context.view_layer.objects:
        o.select_set(o in obs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, NAME + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    stats["glb_bytes"] = os.path.getsize(os.path.join(OUT, NAME + ".glb"))
    with open(os.path.join(OUT, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    print("[ke] " + json.dumps(stats))
    os.makedirs(os.path.join(K.PROJECT, "assets", "props"), exist_ok=True)
    shutil.copy(os.path.join(OUT, NAME + ".glb"), os.path.join(K.PROJECT, "assets", "props", NAME + ".glb"))
    print("COPIED", NAME)


main()
