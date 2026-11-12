"""The coffee shop near Nora's farmhouse, from Alex's concept (ref/coffee_shop_concept.png,
2026-11-12). See asset-brief.md for the measurements and what is inferred.

    uv run --no-project --with pillow --with numpy python art/world_assets/coffee_shop/make_faces.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/coffee_shop/build.py

Writes out/building_cafe.{blend,glb} and copies the GLB to assets/props/. One static mesh, terrace
included. Front faces -Y (+Z in Godot); the origin is on the ground at the middle of the whole
footprint, so town.gd's building() centres it on its lot. Measured off the reference at 136 px a
metre (X(px), Z(py)). The plaque's and the chalkboard's faces are the reference itself
(make_faces.py), like the shop signs.
"""
import json
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

NAME = "building_cafe"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
PROPS = os.path.join(K.PROJECT, "assets", "props")

PPM = 136.0  # reference px a metre (the door: 285 px = 2.1 m)
CX, GY = 695.0, 985.0  # the front wall's centre line and its foot


def X(px):
    return (px - CX) / PPM


def Z(py):
    return (GY - py) / PPM


W = 5.9  # the front wall (x 300..1105)
D = 5.0  # its depth  # inferred
TERRACE = 2.8  # cobbles in front of the wall
DT = D + TERRACE
BACK = DT / 2
FRONT = BACK - D  # the front wall's face; -Y is the front
FOOT = 0.2  # the stone footing
EAVE = Z(505)  # 3.53
RIDGE = Z(95)  # 6.54
OVER = 0.4  # the roof's overhang at the eaves
GABLE_OVER = 0.4  # and past the gable ends
G_HALF = (910 - 455) / PPM / 2  # the front gable's half width 1.67
G_CX = X(682)  # its centre line
G_APEX = Z(55)  # 6.84
DOOR_X, DOOR_W = X(677), 0.99
DOOR_TOP = Z(655)  # its arched top 2.43
STEP = 0.33  # the doorstep's height (two steps)
WIN_C = (X(402), X(932))  # the shop windows' centres
WIN_W, WIN_Z = 1.5, (Z(800), Z(670))  # 1.36..2.32
AWN_TOP, AWN_EDGE, AWN_OUT = Z(535), Z(640), 1.0  # the awning, 3.31 down to 2.54, 1 m out
AWN_X = (X(232), X(1092))
STRIPE = (X(1092) - X(232)) / 14  # the awning's fourteen stripes
ROOF_EDGE = Z(480)  # the front slope's lower edge, just over the fascia
SLOPE = (RIDGE - ROOF_EDGE) / (D / 2 + 0.4)
ROOF_WALL = ROOF_EDGE + 0.4 * SLOPE  # where the slope passes over the wall

GREEN, CREAM, TILE, STONE_C = "#4f6a3c", "#f0dfc0", "#b0562e", "#b9ab98"
WOOD, GLOW, AWN_G = "#a8612e", "#f0a548", "#55703f"


def rgb(h):
    return np.array(K.hex_rgb(h))


# --- textures -----------------------------------------------------------------------------------

def tile_maps(name, hexcol, n=512, rows=6, per=5):
    """Big rounded clay tiles in rows across the image, round-bottomed; v runs down the roof."""
    yy, xx = np.mgrid[0:n, 0:n]
    rh, sw = n / rows, n / per
    row = (yy // rh).astype(int)
    xo = (xx + (row % 2) * sw / 2) % n
    ci = (xo // sw).astype(int)
    fx = (xo % sw) / sw - 0.5
    fy = (yy % rh) / rh
    edge = 0.62 + 0.38 * np.sqrt(np.clip(1 - (2 * fx) ** 2, 0, 1))
    inside = fy < edge
    r = np.random.default_rng(4)
    tint = (0.82 + 0.3 * r.random((rows, per)))[row, ci]
    mott = K.tile_noise(n, 1.3, 23)
    c = rgb(hexcol) * tint[..., None] * (0.9 + 0.15 * mott[..., None])
    thick = np.where(inside, fy / np.maximum(edge, 1e-3), 0.0)
    c = c * (0.7 + 0.4 * thick[..., None]) * np.where(inside, 1.0, 0.5)[..., None]
    c = c * (0.85 + 0.2 * np.cos(fx * math.pi)[..., None])
    hgt = thick + 0.2 * mott
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 2.8), TEX)


def block_maps(name, base, mortar, n=512, blocks=4, courses=5, joint=6, jitter=0.25, seed=1):
    mott = K.tile_noise(n, 1.4, seed)
    yy, xx = np.mgrid[0:n, 0:n]
    ch, bw = n / courses, n / blocks
    row = (yy // ch).astype(int)
    xo = (xx + (row % 2) * bw / 2) % n
    ci = (xo // bw).astype(int)
    r = np.random.default_rng(seed)
    tint = (1 - jitter / 2 + jitter * r.random((courses, blocks)))[row, ci]
    c = rgb(base) * (0.88 + 0.2 * mott[..., None]) * tint[..., None]
    d = np.minimum(np.minimum(xo % bw, bw - xo % bw), np.minimum(yy % ch, ch - yy % ch))
    j = np.clip(1 - d / joint, 0, 1)[..., None]
    c = c * (1 - j) + rgb(mortar) * j
    hgt = 0.3 * mott + 2.0 * np.clip(d / (joint * 2.5), 0, 1)
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.5), TEX)


def stripes(name, a, b, n=256, k=8):
    x = np.arange(n)
    s = ((x // (n // k)) % 2)[None, :, None]
    weave = K.tile_noise(n, 0.5, 3)[..., None]
    c = (rgb(a) * s + rgb(b) * (1 - s)) * (0.93 + 0.1 * weave)
    return K.save_image(name, np.broadcast_to(c, (n, n, 3)).copy(), TEX)


def plaid(name, n=256):
    yy, xx = np.mgrid[0:n, 0:n]
    a = ((xx // 32) % 2) ^ ((yy // 32) % 2)
    line = ((xx % 32) < 4) | ((yy % 32) < 4)
    c = np.where(a[..., None], rgb("#a8312a"), rgb("#7e2420"))
    c = np.where(line[..., None], rgb("#efe0c6"), c)
    return K.save_image(name, c.astype(float), TEX)


def materials():
    M = {}
    i, n = CL.plank_maps("cafe_boards", TEX, base=GREEN, light="#62804b", dark="#38502b", knots=0, seams=4, seed=52)
    M["wall"] = K.textured("cafe_wall", i, 0.88, normal=n, normal_strength=0.9)
    i, n = tile_maps("cafe_tiles", TILE)
    M["roof"] = K.textured("cafe_roof", i, 0.8, normal=n, normal_strength=1.3)
    i, n = block_maps("cafe_stone", STONE_C, "#d8cebf", seed=5)
    M["stone"] = K.textured("cafe_stone", i, 0.92, normal=n)
    i, n = block_maps("cafe_cobble", "#cdb8a6", "#8e8a66", blocks=5, courses=6, joint=7, jitter=0.35, seed=8)
    M["cobble"] = K.textured("cafe_cobble", i, 0.95, normal=n)
    i, n = CL.plank_maps("cafe_wood", TEX, base=WOOD, light="#c47a40", dark="#7a4320", knots=1, seed=61)
    M["wood"] = K.textured("cafe_wood", i, 0.7, normal=n, normal_strength=0.6)
    i, n = CL.plank_maps("cafe_door", TEX, base="#4c693b", light="#5f7e4b", dark="#344a28", knots=0, seams=3, seed=63)
    M["door"] = K.textured("cafe_door", i, 0.75, normal=n, normal_strength=0.7)
    M["awning"] = K.textured("cafe_awning", stripes("cafe_awning", AWN_G, "#f2e6cf"), 0.9)
    M["plaid"] = K.textured("cafe_plaid", plaid("cafe_plaid"), 0.95)
    M["plaque"] = K.textured("cafe_plaque", bpy.data.images.load(os.path.join(TEX, "face_plaque.png")), 0.7)
    M["chalk"] = K.textured("cafe_chalk", bpy.data.images.load(os.path.join(TEX, "face_chalkboard.png")), 0.85)
    M["trim"] = K.plain("cafe_trim", CREAM, 0.6)
    M["glass"] = K.plain("cafe_glow", GLOW, 0.3, emit=0.6)
    M["bulb"] = K.plain("cafe_bulb", "#ffd98a", 0.3, emit=2.0)
    M["iron"] = K.plain("cafe_iron", "#5a3a26", 0.5)
    M["brass"] = K.plain("cafe_brass", "#c9933e", 0.35)
    M["brass"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.7
    M["leaf"] = K.plain("cafe_leaf", "#5f8a3a", 0.85)
    M["leaf_y"] = K.plain("cafe_leaf_y", "#b8b23c", 0.85)
    M["leaf_o"] = K.plain("cafe_leaf_o", "#d0632a", 0.85)
    M["bloom"] = K.plain("cafe_bloom", "#f3ead2", 0.8)
    M["lavender"] = K.plain("cafe_lavender", "#8d6fb5", 0.85)
    M["pot"] = K.plain("cafe_pot", "#c47838", 0.85)
    M["mat"] = K.plain("cafe_mat", "#c98a3e", 0.95)
    M["chalkframe"] = K.plain("cafe_chalkframe", "#c98a3e", 0.7)
    return M


# --- shapes ---------------------------------------------------------------------------------------

def place(ob, rot_z=0.0, loc=(0, 0, 0)):
    r = Matrix.Rotation(math.radians(rot_z), 4, "Z")
    ob.matrix_world = Matrix.Translation(Vector(loc)) @ r @ ob.matrix_world
    bpy.context.view_layer.update()
    return ob


def ccw(pts):
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


def arch(cx, z0, w, h, n=12):
    r = w / 2
    zs = z0 + h - r
    pts = [(cx - r, z0), (cx + r, z0)]
    for a in np.linspace(0, math.pi, n):
        pts.append((cx + r * math.cos(a), zs + r * math.sin(a)))
    return pts


def flat(name, pts, y, depth, mat, bevel=0.01, uv=None):
    ob = K.extrude_xz(name, ccw([tuple(p) for p in pts]), y - depth, y, mat, bevel=bevel)
    if uv:
        K.uv_box(ob, uv)
    return ob


def arched_window(name, M, cx, z0, z1, y, w=None, rot=0.0, loc=None):
    """A glowing arched window: a cream surround, wooden glazing bars, a sill."""
    h = z1 - z0
    w = w or h * 0.7
    parts = [flat(name + "_surround", arch(cx, z0, w + 0.16, h + 0.08), y, 0.06, M["trim"], bevel=0.012),
             flat(name + "_glass", arch(cx, z0 + 0.06, w - 0.06, h - 0.06), y - 0.06, 0.012, M["glass"], bevel=0.0),
             K.box(name + "_sill", (w + 0.26, 0.12, 0.07), (cx, y - 0.05, z0 - 0.02), M["trim"], bevel=0.015),
             K.box(name + "_bar", (0.05, 0.03, h - 0.12), (cx, y - 0.085, z0 + h / 2), M["wood"], bevel=0.008),
             K.box(name + "_bar", (w - 0.08, 0.03, 0.05), (cx, y - 0.085, z0 + (h - w / 2) * 0.62), M["wood"], bevel=0.008)]
    if rot or loc:
        for p in parts:
            place(p, rot, loc or (0, 0, 0))
    return parts


def blooms(M, c, r, n, seed, mat=None, lean=-1):
    """Round cream flower heads (hydrangea-like) on a leafy mound."""
    rng = np.random.default_rng(seed)
    x, y, z = c
    for i in range(max(4, n // 2)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, r * 0.6)
        K.ball("foliage", r * rng.uniform(0.4, 0.6), (x + d * math.cos(a), y + d * math.sin(a), z), M["leaf"], u=10, v=7, scale=(1, 1, 0.8))
    for i in range(n):
        a = rng.uniform(-math.pi * 0.95, -math.pi * 0.05) if lean < 0 else rng.uniform(0, math.tau)
        e = rng.uniform(0.2, 1.0)
        p = Vector((x, y, z + r * 0.2)) + Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))) * r * 0.85
        K.ball("bloom", r * 0.32, tuple(p), mat or M["bloom"], u=9, v=6, boxy=0.8)


def leaf_spray(M, pts, seed, size=0.16, density=3):
    """Autumn ivy: flat five-point leaves in greens, yellows and oranges along a path."""
    rng = np.random.default_rng(seed)
    mats = [M["leaf"], M["leaf"], M["leaf_y"], M["leaf_o"]]
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i]), Vector(pts[i + 1])
        for k in range(density):
            p = a.lerp(b, rng.random()) + Vector((rng.normal(0, 0.12), -rng.uniform(0.02, 0.1), rng.normal(0, 0.1)))
            lf = K.star("ivy", size * rng.uniform(0.7, 1.2), tuple(p), mats[rng.integers(0, 4)], points=5, inner=0.55, turn=rng.uniform(0, 6))
            lf.rotation_euler = (math.radians(90 + rng.normal(0, 20)), math.radians(rng.normal(0, 20)), 0)
            s = lf.modifiers.new("solid", "SOLIDIFY")
            s.thickness = 0.01
            K.apply_mods(lf)


# --- the building --------------------------------------------------------------------------------

def walls(M):
    cy = FRONT + D / 2
    K.uv_box(K.box("footing", (W + 0.14, D + 0.14, FOOT), (0, cy, FOOT / 2), M["stone"], bevel=0.02), 1.4)
    wall = K.box("walls", (W - 0.1, D - 0.1, EAVE + 0.5 - FOOT), (0, cy, (EAVE + 0.5 + FOOT) / 2), M["wall"], bevel=0.0)
    K.uv_box(wall, 0.55, grain="z")
    # the gable ends (left and right): triangles of boards up to the ridge
    for sx in (-1, 1):
        tri = [(-D / 2 + 0.05, EAVE - 0.02), (D / 2 - 0.05, EAVE - 0.02), (0, RIDGE - 0.15)]
        g = flat("gable_end", tri, 0, 0.1, M["wall"], bevel=0.0)
        place(g, -90 * sx, (sx * (W / 2 - 0.1), cy, 0))
        K.uv_box(g, 0.55, grain="z")
    # cream corner posts and the fascia under the eaves
    for sx in (-1, 1):
        for y in (FRONT + 0.06, BACK - 0.06):
            K.box("corner", (0.2, 0.2, EAVE - FOOT), (sx * (W / 2 - 0.02), y, (EAVE + FOOT) / 2), M["trim"], bevel=0.02)
    K.box("fascia", (W + 0.2, D + 0.2, 0.24), (0, cy, EAVE + 0.06), M["trim"], bevel=0.02)


def roof(M):
    cy = FRONT + D / 2
    hd = D / 2 + OVER
    hw = W / 2 + GABLE_OVER
    z0 = ROOF_EDGE  # the roof's front edge, just over the fascia (y 480)
    # two slopes, front and back, thick enough to show an edge
    for sy in (-1, 1):
        v = [(-hw, cy + sy * hd, z0), (hw, cy + sy * hd, z0), (hw, cy, RIDGE), (-hw, cy, RIDGE)]
        me = bpy.data.meshes.new("roof")
        me.from_pydata(v, [], [(0, 1, 2, 3) if sy < 0 else (3, 2, 1, 0)])
        ob = K._obj("roof", me, M["roof"])
        s = ob.modifiers.new("solid", "SOLIDIFY")
        s.thickness = 0.16
        K.apply_mods(ob)
        uv_slope(ob, cy, sy)
    K.cyl("ridge", 0.13, 0.13, 2 * hw + 0.1, (0, cy, RIDGE + 0.06), M["roof"], verts=12, rot=(0, 90, 0))
    # the front cross-gable: its wall flush with the front, a roof back to the main ridge
    yf = FRONT
    tri = [(G_CX - G_HALF + 0.12, EAVE - 0.1), (G_CX + G_HALF - 0.12, EAVE - 0.1), (G_CX, G_APEX - 0.25)]
    g = flat("front_gable", tri, yf + 0.02, 0.08, M["wall"], bevel=0.0)
    K.uv_box(g, 0.55, grain="z")
    ga = math.atan2(G_APEX - ROOF_EDGE, G_HALF + 0.15)
    for sx in (-1, 1):
        # the cross-gable's roof slopes, over its wall and back into the main roof
        e = G_CX + sx * (G_HALF + 0.15)  # its eaves end level with the main roof's edge
        ez = ROOF_EDGE
        v = [(e, yf - 0.35, ez), (G_CX, yf - 0.35, G_APEX), (G_CX, cy + 0.2, G_APEX), (e, cy + 0.2, ez)]
        me = bpy.data.meshes.new("groof")
        me.from_pydata(v, [], [(0, 1, 2, 3) if sx > 0 else (3, 2, 1, 0)])
        ob = K._obj("groof", me, M["roof"])
        s = ob.modifiers.new("solid", "SOLIDIFY")
        s.thickness = 0.16
        K.apply_mods(ob)
        uv_gable(ob, sx)
        # the cream bargeboard along its edge
        run = math.hypot(G_HALF + 0.15, G_APEX - ez)
        K.box("barge", (run + 0.1, 0.12, 0.2), (G_CX + sx * (G_HALF + 0.15) / 2, yf - 0.38, (G_APEX + ez) / 2 - 0.08), M["trim"], bevel=0.02, rot=(0, sx * math.degrees(ga), 0))
    K.cyl("gable_ridge", 0.13, 0.13, cy + 0.2 - yf + 0.45, (G_CX, (yf - 0.4 + cy + 0.2) / 2, G_APEX + 0.05), M["roof"], verts=12, rot=(90, 0, 0))
    K.ball("gable_finial", 0.17, (G_CX, yf - 0.42, G_APEX + 0.05), M["roof"], u=12, v=8)
    # the little truss in the gable's peak (y 120..170)
    tz = Z(165)
    K.box("truss_tie", (0.95, 0.08, 0.1), (G_CX, yf - 0.06, tz), M["trim"], bevel=0.01)
    K.box("truss_post", (0.1, 0.08, G_APEX - 0.35 - tz), (G_CX, yf - 0.06, (tz + G_APEX - 0.35) / 2), M["trim"], bevel=0.01)
    for sx in (-1, 1):
        K.box("truss_brace", (0.5, 0.07, 0.08), (G_CX + sx * 0.22, yf - 0.06, tz + 0.18), M["trim"], bevel=0.01, rot=(0, sx * 40, 0))
    # the gable's big arched window and its flower box (x 595..770, y 210..330)
    arched_window("gwin", M, G_CX, Z(330), Z(210), yf - 0.06, w=1.25)
    box_z = Z(345)
    K.box("gbox", (1.75, 0.34, 0.28), (G_CX, yf - 0.24, box_z - 0.12), M["wood"], bevel=0.02)
    blooms(M, (G_CX - 0.45, yf - 0.3, box_z + 0.05), 0.22, 7, 11)
    blooms(M, (G_CX + 0.45, yf - 0.3, box_z + 0.05), 0.22, 7, 12)
    for sx in (-1, 1):
        K.box("gbox_brace", (0.06, 0.25, 0.25), (G_CX + sx * 0.7, yf - 0.12, box_z - 0.35), M["wood"], bevel=0.01, rot=(45, 0, 0))
    # dormers (x 350 and 1045), on the front slope
    slope = SLOPE
    for x in (X(350), X(1045)):
        zb, zt = Z(410), Z(232)
        yd = FRONT + (zb - ROOF_WALL) / slope + 0.05
        K.box("dormer", (1.15, 1.4, zt - zb), (x, yd + 0.65, (zb + zt) / 2 - 0.08), M["trim"], bevel=0.03)
        arched_window("dwin", M, x, zb + 0.08, zt - 0.32, yd, w=0.62)
        hood = K.cyl("dormer_hood", 0.68, 0.68, 1.5, (x, yd + 0.6, zt - 0.3), M["roof"], verts=20, rot=(90, 0, 0))
        hood.scale = (1, 0.55, 1)
        K.uv_box(hood, 0.6)
        K.ball("dormer_finial", 0.1, (x, yd - 0.12, zt + 0.08), M["roof"], u=10, v=7)
    # the chimney (x 985..1135), stone with a cream brick top
    cx_, top = X(1060), Z(18)
    base = RIDGE - 1.2
    K.uv_box(K.box("chimney", (0.95, 0.75, top - 0.45 - base), (cx_, cy + 0.4, (top - 0.45 + base) / 2), M["stone"], bevel=0.03), 1.2)
    K.box("chim_top", (1.08, 0.88, 0.32), (cx_, cy + 0.4, top - 0.29), M["trim"], bevel=0.03)
    K.box("chim_cap", (0.82, 0.62, 0.14), (cx_, cy + 0.4, top - 0.06), M["wood"], bevel=0.03)


def uv_slope(ob, cy, sy):
    layer = ob.data.uv_layers.new(name="UVMap")
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            p = ob.data.vertices[ob.data.loops[li].vertex_index].co
            down = math.hypot(p.y - cy, p.z - RIDGE)
            layer.data[li].uv = (p.x * 0.75, down * 0.75)


def uv_gable(ob, sx):
    layer = ob.data.uv_layers.new(name="UVMap")
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            p = ob.data.vertices[ob.data.loops[li].vertex_index].co
            down = math.hypot(p.x - G_CX, p.z - G_APEX)
            layer.data[li].uv = (p.y * 0.75, down * 0.75)


def front(M):
    yf = FRONT
    # the door: green, an arched glass top, in a cream frame, with two steps and a mat
    out = arch(DOOR_X, STEP, DOOR_W + 0.3, DOOR_TOP - STEP + 0.15, n=14)
    flat("door_frame", out, yf - 0.02, 0.07, M["trim"], bevel=0.015)
    leaf = arch(DOOR_X, STEP, DOOR_W, DOOR_TOP - STEP, n=14)
    d = flat("door", leaf, yf - 0.09, 0.05, M["door"], bevel=0.01)
    K.uv_box(d, 0.9, grain="z")
    flat("door_glass", arch(DOOR_X, STEP + 1.15, DOOR_W - 0.3, DOOR_TOP - STEP - 1.3, n=12), yf - 0.14, 0.01, M["glass"], bevel=0.0)
    K.box("door_bar", (0.05, 0.02, DOOR_TOP - STEP - 1.3), (DOOR_X, yf - 0.155, (STEP + 1.15 + DOOR_TOP - 0.15) / 2), M["door"], bevel=0.0)
    K.box("door_bar", (DOOR_W - 0.3, 0.02, 0.05), (DOOR_X, yf - 0.155, STEP + 1.5), M["door"], bevel=0.0)
    for zz in (STEP + 0.3, STEP + 0.8):
        K.box("door_panel", (DOOR_W - 0.32, 0.025, 0.38), (DOOR_X, yf - 0.15, zz), M["door"], bevel=0.015)
    K.ball("door_knob", 0.05, (DOOR_X + DOOR_W / 2 - 0.13, yf - 0.18, STEP + 1.0), M["brass"], u=10, v=7)
    for i, (w, dpt) in enumerate(((2.2, 0.75), (1.75, 0.4))):
        h = STEP * (2 - i) / 2
        K.uv_box(K.box("step", (w, dpt, h), (DOOR_X + 0.05, yf - dpt / 2, h / 2), M["stone"], bevel=0.02), 1.4)
    K.box("doormat", (0.95, 0.38, 0.025), (DOOR_X, yf - 0.22, STEP + 0.012), M["mat"], bevel=0.008)
    # the shop windows: glowing, wooden bars (three across, two up), flower boxes under
    z0, z1 = WIN_Z
    for c in WIN_C:
        K.box("win_frame", (WIN_W + 0.16, 0.1, z1 - z0 + 0.16), (c, yf - 0.04, (z0 + z1) / 2), M["trim"], bevel=0.015)
        K.box("win_glass", (WIN_W - 0.06, 0.02, z1 - z0 - 0.06), (c, yf - 0.1, (z0 + z1) / 2), M["glass"], bevel=0.0)
        for k in (-1, 1):
            K.box("win_bar", (0.05, 0.03, z1 - z0 - 0.06), (c + k * WIN_W / 6, yf - 0.115, (z0 + z1) / 2), M["wood"], bevel=0.006)
        K.box("win_bar", (WIN_W - 0.06, 0.03, 0.05), (c, yf - 0.115, z0 + (z1 - z0) * 0.55), M["wood"], bevel=0.006)
        K.box("win_box", (WIN_W + 0.2, 0.32, 0.26), (c, yf - 0.2, z0 - 0.2), M["wood"], bevel=0.02)
        for k, sx in enumerate((-0.5, 0.0, 0.5)):
            blooms(M, (c + sx, yf - 0.24, z0 - 0.04), 0.2, 5, 20 + k + int(abs(c) * 10))
        # trailing greenery over the box's front
        for k in range(7):
            K.ball("trail", 0.06, (c - WIN_W / 2 + 0.1 + k * WIN_W / 6.5, yf - 0.38, z0 - 0.3 - 0.05 * (k % 3)), M["leaf"], u=8, v=6, scale=(0.8, 0.6, 1.4))
    # the striped awning: a sloping canvas, a scalloped valance
    x0, x1 = AWN_X
    v = [(x0, yf, AWN_TOP), (x1, yf, AWN_TOP), (x1, yf - AWN_OUT, AWN_EDGE + 0.15), (x0, yf - AWN_OUT, AWN_EDGE + 0.15)]
    me = bpy.data.meshes.new("awning")
    me.from_pydata(v, [], [(3, 2, 1, 0)])
    aw = K._obj("awning", me, M["awning"])
    s = aw.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.04
    K.apply_mods(aw)
    layer = aw.data.uv_layers.new(name="UVMap")
    for poly in aw.data.polygons:
        for li in poly.loop_indices:
            p = aw.data.vertices[aw.data.loops[li].vertex_index].co
            layer.data[li].uv = ((p.x - x0) / (STRIPE * 8), p.z)  # eight stripes a tile
    nsc = int(round((x1 - x0) / STRIPE))
    for k in range(nsc):
        cx_ = x0 + (k + 0.5) * (x1 - x0) / nsc
        hw_ = (x1 - x0) / nsc / 2
        pts = [(cx_ - hw_, AWN_EDGE + 0.17), (cx_ + hw_, AWN_EDGE + 0.17)]
        for a in np.linspace(0, math.pi, 10):
            pts.append((cx_ + hw_ * math.cos(a), AWN_EDGE + 0.17 - 0.16 * math.sin(a)))
        sc = flat("scallop", pts, yf - AWN_OUT + 0.02, 0.03, M["awning"], bevel=0.0)
        lay = (sc.data.uv_layers.active or sc.data.uv_layers.new(name="UVMap")).data
        for poly in sc.data.polygons:
            for li in poly.loop_indices:
                lay[li].uv = ((k + 0.5) / 8, 0.5)
    # string lights under the awning's edge, in two sagging runs (y 665..690)
    for a, b in ((X(258), X(500)), (X(855), X(1045))):
        pts = []
        for t in np.linspace(0, 1, 12):
            pts.append(Vector((a + (b - a) * t, yf - AWN_OUT + 0.08, AWN_EDGE + 0.05 - 0.14 * math.sin(math.pi * t))))
        CL.tube("light_wire", pts, [0.008] * len(pts), M["iron"], sides=4)
        for p in pts[1:-1:2]:
            K.ball("light_bulb", 0.05, (p.x, p.y, p.z - 0.07), M["bulb"], u=8, v=6, scale=(1, 1, 1.2))
    # two lanterns on the wall either side of the door (x 555, 790)
    for x in (X(555), X(795)):
        z = Z(712)
        K.box("lantern_arm", (0.05, 0.3, 0.05), (x, yf - 0.15, z + 0.38), M["iron"], bevel=0.0)
        K.cyl("lantern_cap", 0.05, 0.16, 0.12, (x, yf - 0.3, z + 0.3), M["iron"], verts=8)
        K.box("lantern_glass", (0.22, 0.22, 0.34), (x, yf - 0.3, z + 0.05), M["bulb"], bevel=0.02)
        for a, b in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
            K.box("lantern_bar", (0.03, 0.03, 0.36), (x + a * 0.11, yf - 0.3 + b * 0.11, z + 0.05), M["iron"], bevel=0.0)
        K.cyl("lantern_foot", 0.13, 0.05, 0.1, (x, yf - 0.3, z - 0.16), M["iron"], verts=8)
    plaque(M)


def plaque(M):
    """The coffee-cup plaque over the awning: its face is the reference (make_faces.py)."""
    with open(os.path.join(TEX, "plaque_outline.json")) as f:
        prof = json.load(f)
    x0, y0, x1, y1 = prof["crop"]
    bot = prof["bottom"]
    pts = [(X(x), Z(t)) for x, t in zip(prof["x"], prof["top"])]
    pts += [(X(prof["x"][-1]), Z(bot)), (X(prof["x"][0]), Z(bot))]
    yp = FRONT - 0.5
    ob = K.extrude_xz("plaque", ccw(pts), yp - 0.08, yp, M["trim"], bevel=0.015)
    me = ob.data
    me.materials.append(M["plaque"])
    fi = len(me.materials) - 1
    uvl = (me.uv_layers.active or me.uv_layers.new(name="UVMap")).data
    for poly in me.polygons:
        if poly.normal.y < -0.95:
            poly.material_index = fi
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            px, py = co.x * PPM + CX, GY - co.z * PPM
            uvl[li].uv = ((px - x0) / (x1 - x0), 1 - (py - y0) / (y1 - y0))
    # two brackets back to the wall
    for sx in (-1, 1):
        K.box("plaque_bracket", (0.05, 0.5, 0.05), (X(685) + sx * 0.8, FRONT - 0.25, Z(500)), M["iron"], bevel=0.0)


def right_side(M):
    """The right gable wall: an arched window up high, a small one below, a hanging basket."""
    cy = FRONT + D / 2
    xs = W / 2 + 0.01
    arched_window("rwin", M, -0.7, Z(445), Z(320), -xs, w=0.5, rot=90, loc=(0, cy, 0))
    arched_window("rwin", M, 0.9, EAVE + 0.7, EAVE + 1.6, -xs, w=0.55, rot=90, loc=(0, cy, 0))
    for p in arched_window("rwin_lo", M, -1.4, Z(800), Z(700), -xs, w=0.5, rot=90, loc=(0, cy, 0)):
        pass
    # the left gable's windows match (inferred)
    arched_window("lwin", M, 0.9, EAVE + 0.7, EAVE + 1.6, -xs, w=0.55, rot=-90, loc=(0, cy, 0))
    arched_window("lwin", M, 0.0, Z(800), Z(680), -xs, w=0.55, rot=-90, loc=(0, cy, 0))
    # the hanging basket on its scrolled bracket (x 1125..1265, y 555..730)
    by = FRONT + 0.9
    K.box("basket_arm", (0.62, 0.05, 0.05), (W / 2 + 0.31, by, Z(570)), M["iron"], bevel=0.0)
    K.box("basket_brace", (0.05, 0.05, 0.45), (W / 2 + 0.06, by, Z(570) - 0.2), M["iron"], bevel=0.0)
    K.torus("basket_scroll", 0.1, 0.018, (W / 2 + 0.2, by, Z(570) - 0.12), M["iron"], rot=(90, 0, 0), major=12, minor=5)
    bx, bz = W / 2 + 0.52, Z(660)
    for k in range(3):
        a = math.radians(120 * k)
        K.cyl("basket_chain", 0.006, 0.006, 0.42, (bx + 0.12 * math.cos(a) * 0.5, by + 0.12 * math.sin(a) * 0.5, Z(570) - 0.24), M["iron"], verts=4)
    K.lathe("basket", [(0.05, bz - 0.1), (0.2, bz), (0.24, bz + 0.12)], M["wood"], steps=16, loc=(bx, by, 0))
    blooms(M, (bx, by, bz + 0.16), 0.24, 9, 31, lean=1)
    for k in range(8):
        a = math.tau * k / 8
        K.ball("trail", 0.06, (bx + 0.22 * math.cos(a), by + 0.22 * math.sin(a), bz - 0.15 - 0.1 * (k % 3)), M["leaf"], u=8, v=6, scale=(0.7, 0.7, 1.8))


def ivy(M):
    """Autumn ivy up the left front corner and along the gable's left edge."""
    x = -W / 2 - 0.02
    pts = [(x + 0.1, FRONT - 0.1, 0.4), (x, FRONT - 0.15, 1.2), (x - 0.1, FRONT - 0.12, 2.0), (x + 0.05, FRONT - 0.15, 2.8),
           (x + 0.2, FRONT - 0.2, 3.4), (x + 0.6, FRONT - 0.45, 4.0)]
    leaf_spray(M, pts, 3, size=0.13, density=18)
    ga = math.atan2(G_APEX - EAVE, G_HALF)
    g0 = Vector((G_CX - G_HALF - 0.2, FRONT - 0.45, EAVE + 0.05))
    g1 = Vector((G_CX - 0.15, FRONT - 0.45, G_APEX - 0.15))
    leaf_spray(M, [tuple(g0.lerp(g1, t)) for t in np.linspace(0, 1, 6)], 4, size=0.12, density=10)


def bistro(M, cx, cy, seed, throw_side):
    """A round table with a lantern and a vase, two bentwood chairs, a plaid throw on one."""
    K.cyl("table_top", 0.4, 0.4, 0.05, (cx, cy, 0.76), M["wood"], verts=24, bevel=0.015)
    K.cyl("table_leg", 0.04, 0.04, 0.72, (cx, cy, 0.38), M["iron"], verts=8)
    K.cyl("table_foot", 0.24, 0.24, 0.04, (cx, cy, 0.02), M["iron"], verts=12)
    # a candle lantern and a little vase of flowers
    K.box("tlantern", (0.12, 0.12, 0.18), (cx + 0.12, cy, 0.9), M["bulb"], bevel=0.01)
    K.cyl("tlantern_cap", 0.03, 0.09, 0.05, (cx + 0.12, cy, 1.01), M["brass"], verts=6)
    K.cyl("vase", 0.05, 0.06, 0.13, (cx - 0.14, cy + 0.05, 0.85), M["trim"], verts=10)
    blooms(M, (cx - 0.14, cy + 0.05, 0.96), 0.08, 4, seed, lean=1)
    for sx in (-1, 1):
        x = cx + sx * 0.62
        K.cyl("chair_seat", 0.22, 0.22, 0.05, (x, cy, 0.46), M["wood"], verts=16, bevel=0.01)
        for a in (45, 135, 225, 315):
            r = math.radians(a)
            K.cyl("chair_leg", 0.018, 0.022, 0.46, (x + 0.15 * math.cos(r), cy + 0.15 * math.sin(r), 0.23), M["wood"], verts=6)
        # the bentwood back: a hoop on the far side from the table, with two spindles
        back = K.torus("chair_back", 0.2, 0.022, (x + sx * 0.2, cy, 0.78), M["wood"], rot=(0, 90, 0), major=16, minor=5)
        back.scale = (1, 1, 1.25)
        for k in (-1, 1):
            K.cyl("chair_spindle", 0.014, 0.014, 0.36, (x + sx * 0.2, cy + k * 0.08, 0.66), M["wood"], verts=5)
        if sx == throw_side:
            K.box("throw", (0.08, 0.42, 0.62), (x + sx * 0.24, cy, 0.62), M["plaid"], bevel=0.03, rot=(0, sx * 12, 0))
            K.box("throw_seat", (0.32, 0.42, 0.05), (x + sx * 0.08, cy, 0.5), M["plaid"], bevel=0.02)


def terrace(M):
    """Cobbles in front, the bistro tables, pots, the barrel, the chalkboard, fallen leaves."""
    yf = FRONT
    # the cobbled terrace: half an oval out from the wall, 10 m across
    pts = [(5.0 * math.cos(a), yf - (TERRACE - 0.05) * math.sin(a)) for a in np.linspace(0, math.pi, 28)]
    verts = [(x, y, 0.035) for x, y in pts] + [(x, y, 0.0) for x, y in pts]
    n = len(pts)
    faces = [tuple(range(n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    me = bpy.data.meshes.new("terrace")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = K._obj("terrace", me, M["cobble"])
    K.uv_box(ob, 0.55)
    bistro(M, X(400), yf - 1.4, 41, 1)
    bistro(M, X(945), yf - 1.4, 42, 1)
    # a barrel of hydrangeas at the left (x 100..230)
    bx, by = X(165), yf - 0.9
    K.lathe("barrel", [(0.3, 0.0), (0.36, 0.25), (0.37, 0.4), (0.36, 0.55), (0.3, 0.8)], M["wood"], steps=20, loc=(bx, by, 0), u_rep=6)
    for z in (0.12, 0.68):
        K.torus("barrel_hoop", 0.345, 0.018, (bx, by, z), M["iron"], major=20, minor=4)
    blooms(M, (bx, by, 0.85), 0.42, 9, 51)
    # lavender in clay pots (x 230 and 800), a pot of hydrangeas at the right (x 1285)
    for i, x in enumerate((X(232), X(800))):
        K.lathe("pot", [(0.13, 0.0), (0.2, 0.32), (0.22, 0.36)], M["pot"], steps=14, loc=(x, yf - 0.55, 0))
        rng = np.random.default_rng(60 + i)
        for k in range(9):
            a = rng.uniform(0, math.tau)
            px, py = x + 0.09 * math.cos(a), yf - 0.55 + 0.09 * math.sin(a)
            h = rng.uniform(0.35, 0.55)
            K.cyl("lav_stem", 0.008, 0.008, h, (px, py, 0.32 + h / 2), M["leaf"], verts=4, rot=(rng.normal(0, 8), rng.normal(0, 8), 0))
            K.ball("lav_spike", 0.035, (px, py, 0.32 + h), M["lavender"], u=6, v=5, scale=(1, 1, 3.0))
    K.lathe("pot", [(0.22, 0.0), (0.3, 0.38), (0.33, 0.44)], M["pot"], steps=16, loc=(X(1285), yf - 0.8, 0))
    blooms(M, (X(1285), yf - 0.8, 0.5), 0.36, 8, 55)
    # the A-frame chalkboard (x 1075..1240), its face from the reference
    cx_, cy_ = X(1158), yf - 1.15
    fw, fh = 0.62, 0.82
    for sy, tilt in ((-1, 12), (1, -12)):
        leg_y = cy_ + sy * 0.14
        for sx in (-1, 1):
            K.box("chalk_leg", (0.05, 0.05, 1.1), (cx_ + sx * (fw / 2 + 0.03), leg_y, 0.55), M["chalkframe"], bevel=0.01, rot=(tilt, 0, 0))
        K.box("chalk_rail", (fw + 0.1, 0.05, 0.06), (cx_, leg_y + sy * 0.08, 1.02), M["chalkframe"], bevel=0.01, rot=(tilt, 0, 0))
    face = K.box("chalk_face", (fw, 0.03, fh), (cx_, cy_ - 0.14, 0.58), M["chalk"], bevel=0.0, rot=(12, 0, 0))
    lay = (face.data.uv_layers.active or face.data.uv_layers.new(name="UVMap")).data
    for poly in face.data.polygons:
        for li in poly.loop_indices:
            co = face.data.vertices[face.data.loops[li].vertex_index].co
            lay[li].uv = (co.x / fw + 0.5, co.z / fh + 0.5)
    # fallen maple leaves on the cobbles
    rng = np.random.default_rng(71)
    for k in range(16):
        a = rng.uniform(0.1, math.pi - 0.1)
        r = rng.uniform(1.0, 4.6)
        p = (r * math.cos(a), yf - min(TERRACE - 0.2, 0.4 + r * 0.5 * math.sin(a)), 0.045)
        K.star("fallen_leaf", 0.08, p, [M["leaf_o"], M["leaf_y"], M["leaf_o"]][k % 3], points=5, inner=0.5, turn=rng.uniform(0, 6))


def build():
    K.reset(NAME)
    M = materials()
    walls(M)
    roof(M)
    front(M)
    right_side(M)
    ivy(M)
    terrace(M)
    bpy.context.view_layer.update()
    for o in K.COLL.objects:
        if o.type == "MESH" and o.data.vertices:
            lo = min((o.matrix_world @ v.co).z for v in o.data.vertices)
            if lo < -0.05:
                print("BELOW GROUND", o.name, round(lo, 3))
    K.finish(NAME, OUT, max_tris=60000)
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(OUT, NAME + ".glb"), os.path.join(PROPS, NAME + ".glb"))
    print("COPIED", os.path.join(PROPS, NAME + ".glb"))
    print("FOOTPRINT %.2f x %.2f m (terrace included)" % (10.0, DT))


build()
