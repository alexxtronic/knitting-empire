"""The Mayor's Office: Maple Grove's town hall, from Alex's concept (ref/mayors_office_concept.png,
2026-11-12). See asset-brief.md for the measurements and what is inferred.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/mayors_office/build.py

Writes out/building_mayor.{blend,glb} and copies the GLB to assets/props/. One static mesh (not
walk-in). Front faces -Y (+Z in Godot); the origin is on the ground at the middle of the whole
footprint (stairs included), so town.gd's building() centres it on its lot rect. Measured off the
reference at 108 px a metre (X(px), Z(py)); depth is inferred.

It prints SIGN_MOUNT: where the Mayors Office hanging sign goes (the front face of the portico's
entablature, between the columns), in Godot's axes, for town.gd.
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

NAME = "building_mayor"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
PROPS = os.path.join(K.PROJECT, "assets", "props")

PPM = 108.0  # reference pixels per metre (the double door: 220 px = 2.05 m)
CX, GY = 610.0, 1095.0  # the front's centre line and the ground line, reference px


def X(px):
    return (px - CX) / PPM


def Z(py):
    return (GY - py) / PPM


# --- measured (front view of the reference) -----------------------------------------------------
W = 10.6  # pilaster to pilaster (x 35..1185)
D = 6.8  # the main block's depth  # inferred
PORTICO = 1.6  # columns in front of the wall  # inferred from the overlap of column and window
STAIR_RUN = 0.35  # each of 3 steps
DT = D + PORTICO + 0.45 + 3 * STAIR_RUN  # the whole footprint, front to back
BACK = DT / 2
FRONT = BACK - D  # the front wall's face (-Y is the front)
COL_Y = FRONT - PORTICO  # the columns' centres
PODIUM_Y = COL_Y - 0.45  # the podium's front edge, where the stairs start
PL = Z(990)  # plinth top 0.97
FLOOR = Z(1010)  # the podium and doorstep 0.79
BAND = Z(775)  # storey band 2.96
EAVE = Z(590)  # cornice bottom 4.68
CORNICE = Z(540)  # cornice top 5.14
RIDGE = Z(345)  # roof ridge 6.94
OVER = 0.45  # roof overhang
COL_X = 1.85  # column centres (x 402 and 782, made symmetric)
ENT0, ENT1 = Z(545), Z(500)  # the portico's entablature 4.63..5.05..
APEX = Z(315)  # the pediment's apex 7.22
PED_HALF = (880 - 275) / PPM / 2  # half the pediment's span 2.8
WIN_X = (3.2, 4.22)  # window centres, each side of the portico
WIN_LO = (Z(950), Z(815))  # lower windows' surround 1.34..2.59
WIN_HI = (Z(745), Z(615))  # upper 3.24..4.44
CHIM = ((-3.2, 0.95), (4.0, 0.85))  # chimney x and width
CUP_R = 2.82 / 2  # the cupola's drum, across its flats

# --- colours -------------------------------------------------------------------------------------
RED, CREAM, STONE_C, SHINGLE_C = "#a33a2e", "#efdcb8", "#bcab95", "#5d433b"
NAVY, GOLD, FLAG_RED, LEAF_C, BLOOM = "#3f4b6e", "#d4a24a", "#c0443a", "#5f8a3a", "#f5ecd6"


def rgb(h):
    return np.array(K.hex_rgb(h))


def block_maps(name, base, mortar, n=512, blocks=4, courses=6, joint=5, jitter=0.25, seed=1):
    """Dressed stone blocks with mortar joints; tileable (as in town_buildings/build.py)."""
    mott = K.tile_noise(n, 1.4, seed)
    speck = K.tile_noise(n, 0.4, seed + 3)
    yy, xx = np.mgrid[0:n, 0:n]
    ch, bw = n / courses, n / blocks
    row = (yy // ch).astype(int)
    xo = (xx + (row % 2) * bw / 2) % n
    ci = (xo // bw).astype(int)
    r = np.random.default_rng(seed)
    tint = (1 - jitter / 2 + jitter * r.random((courses, blocks)))[row, ci]
    c = rgb(base) * (0.88 + 0.2 * mott[..., None]) * (0.96 + 0.08 * speck[..., None]) * tint[..., None]
    d = np.minimum(np.minimum(xo % bw, bw - xo % bw), np.minimum(yy % ch, ch - yy % ch))
    j = np.clip(1 - d / joint, 0, 1)[..., None]
    c = c * (1 - j) + rgb(mortar) * j
    hgt = 0.3 * mott + 0.2 * speck + 2.0 * np.clip(d / (joint * 2.5), 0, 1)
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.4), TEX)


def shingle_maps(name, hexcol, n=512, rows=8, per=6):
    """Square wooden shingles in rows across the image; v runs down the roof."""
    yy, xx = np.mgrid[0:n, 0:n]
    rh, sw = n / rows, n / per
    row = (yy // rh).astype(int)
    xo = (xx + (row % 2) * sw / 2) % n
    ci = (xo // sw).astype(int)
    fx = (xo % sw) / sw - 0.5
    fy = (yy % rh) / rh
    r = np.random.default_rng(5)
    tint = (0.8 + 0.32 * r.random((rows, per)))[row, ci]
    mott = K.tile_noise(n, 1.3, 17)
    gap = np.abs(fx) > 0.47
    c = rgb(hexcol) * tint[..., None] * (0.9 + 0.16 * mott[..., None])
    c = c * (0.72 + 0.36 * fy[..., None]) * np.where(gap, 0.6, 1.0)[..., None]
    hgt = fy + 0.2 * mott - 0.5 * gap
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 2.5), TEX)


def materials():
    M = {}
    i, n = CL.plank_maps("mayor_boards", TEX, base=RED, light="#bd4a3a", dark="#7a2a22", knots=0, seams=4, seed=33)
    M["wall"] = K.textured("mayor_wall", i, 0.88, normal=n, normal_strength=0.9)
    i, n = block_maps("mayor_stone", STONE_C, "#d2c8bb", seed=7)
    M["stone"] = K.textured("mayor_stone", i, 0.92, normal=n)
    i, n = block_maps("mayor_paving", "#c9b8a6", "#8f8a6a", blocks=3, courses=3, joint=7, jitter=0.3, seed=11)
    M["paving"] = K.textured("mayor_paving", i, 0.95, normal=n)
    i, n = block_maps("mayor_brick", "#e8d3ad", "#c8b493", blocks=3, courses=7, joint=5, seed=19)
    M["brick"] = K.textured("mayor_brick", i, 0.85, normal=n)
    i, n = shingle_maps("mayor_roof", SHINGLE_C)
    M["roof"] = K.textured("mayor_roof", i, 0.85, normal=n, normal_strength=1.2)
    i, n = CL.plank_maps("mayor_door", TEX, base="#a5582c", light="#c47440", dark="#7a3d1c", knots=1, seams=3, seed=41)
    M["door"] = K.textured("mayor_door", i, 0.75, normal=n, normal_strength=0.8)
    M["trim"] = K.plain("mayor_trim", CREAM, 0.6)
    M["glass"] = K.plain("mayor_glow", "#e8913a", 0.3, emit=0.55)  # warm lamplight behind the panes
    M["frame"] = K.plain("mayor_frame", "#f2e2c2", 0.6)
    M["navy"] = K.plain("mayor_navy", NAVY, 0.8)
    M["gold"] = K.plain("mayor_gold", GOLD, 0.35)
    M["gold"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.7
    M["flag"] = K.plain("mayor_flag", FLAG_RED, 0.8)
    M["leaf"] = K.plain("mayor_leaf", LEAF_C, 0.85)
    M["bloom"] = K.plain("mayor_bloom", BLOOM, 0.8)
    M["iron"] = K.plain("mayor_iron", "#3a3230", 0.5)
    M["band"] = K.plain("mayor_redwood", "#8f3027", 0.85)  # the cupola's base and the tympanum
    return M


# --- shapes --------------------------------------------------------------------------------------

def place(ob, rot_z=0.0, loc=(0, 0, 0)):
    """Turn a part built facing -Y about Z (degrees) and move it."""
    from mathutils import Matrix
    r = Matrix.Rotation(math.radians(rot_z), 4, "Z")
    # a part may sit where it was made (its location) or carry it in its vertices: turn both
    ob.matrix_world = Matrix.Translation(Vector(loc)) @ r @ ob.matrix_world
    bpy.context.view_layer.update()
    return ob


def ccw(pts):
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


def arch(cx, z0, w, h, n=12):
    """An arch-topped opening: w wide, h tall to the crown (semicircular head), as XZ points."""
    r = w / 2
    zs = z0 + h - r
    pts = [(cx - r, z0), (cx + r, z0)]
    for a in np.linspace(0, math.pi, n):
        pts.append((cx + r * math.cos(a), zs + r * math.sin(a)))
    return pts


def flat(name, pts, y, depth, mat, bevel=0.01, uv=None):
    """A flat shape in XZ standing from the plane y out towards -Y by depth."""
    ob = K.extrude_xz(name, ccw([tuple(p) for p in pts]), y - depth, y, mat, bevel=bevel)
    if uv:
        K.uv_box(ob, uv)
    return ob


def maple(scale, cx=0.0, cz=0.0):
    """A stylised maple leaf (XZ points), about scale tall."""
    p = [(0, -0.5), (0.05, -0.22), (0.36, -0.3), (0.3, -0.12), (0.5, 0.06), (0.36, 0.08), (0.42, 0.27),
         (0.2, 0.17), (0.16, 0.33), (0.07, 0.2), (0, 0.5), (-0.07, 0.2), (-0.16, 0.33), (-0.2, 0.17),
         (-0.42, 0.27), (-0.36, 0.08), (-0.5, 0.06), (-0.3, -0.12), (-0.36, -0.3), (-0.05, -0.22)]
    return [(cx + x * scale, cz + z * scale) for x, z in p]


def window(name, M, cx, z0, z1, y, rot=0.0, loc=None, glow=True):
    """An arched window with a cream surround and keystone, a sill, glowing panes and a cross
    of glazing bars. Built on the plane y facing -Y (cx along the wall), turned by rot about Z."""
    h = z1 - z0
    w = h * 0.63
    parts = []
    parts.append(flat(name + "_surround", arch(cx, z0, w, h), y, 0.07, M["frame"], bevel=0.015))
    parts.append(flat(name + "_glass", arch(cx, z0 + 0.12, w - 0.2, h - 0.22), y - 0.07, 0.015, M["glass"] if glow else M["navy"], bevel=0.0))
    parts.append(K.box(name + "_sill", (w + 0.16, 0.14, 0.09), (cx, y - 0.06, z0 + 0.02), M["frame"], bevel=0.02))
    parts.append(K.box(name + "_key", (0.13, 0.1, 0.16), (cx, y - 0.08, z1 - 0.04), M["frame"], bevel=0.015))
    parts.append(K.box(name + "_bar_v", (0.07, 0.03, h - 0.3), (cx, y - 0.095, z0 + 0.12 + (h - 0.3) / 2), M["door"], bevel=0.01))
    parts.append(K.box(name + "_bar_h", (w - 0.22, 0.03, 0.07), (cx, y - 0.095, z0 + 0.12 + (h - 0.22) * 0.5), M["door"], bevel=0.01))
    parts.append(flat(name + "_frame", arch(cx, z0 + 0.1, w - 0.12, h - 0.18), y - 0.065, 0.006, M["door"], bevel=0.0))
    if rot or loc:
        for p in parts:
            place(p, rot, loc or (0, 0, 0))
    return parts


# --- the building --------------------------------------------------------------------------------

def main_block(M):
    hw = W / 2 - 0.3  # the boards between the pilasters
    # stone plinth, a little proud of the walls
    pl = K.box("plinth", (W + 0.12, D + 0.12, PL), (0, FRONT + D / 2, PL / 2), M["stone"], bevel=0.03)
    K.uv_box(pl, 0.75)
    # the red boards, vertical, wall to cornice
    wall = K.box("walls", (W - 0.2, D - 0.2, EAVE - PL + 0.02), (0, FRONT + D / 2, (PL + EAVE) / 2), M["wall"], bevel=0.0)
    K.uv_box(wall, 0.5, grain="z")
    # corner pilasters (cream), with caps and bases, and the same on the back corners
    for sx in (-1, 1):
        for y in (FRONT + 0.25, BACK - 0.25):
            K.box("pilaster", (0.56, 0.56, EAVE - PL), (sx * (W / 2 - 0.28), y, (PL + EAVE) / 2), M["trim"], bevel=0.03)
            K.box("pil_base", (0.66, 0.66, 0.18), (sx * (W / 2 - 0.28), y, PL + 0.09), M["trim"], bevel=0.03)
            K.box("pil_cap", (0.68, 0.68, 0.14), (sx * (W / 2 - 0.28), y, EAVE - 0.18), M["trim"], bevel=0.03)
    # storey band and the cornice, all round
    K.box("band", (W - 0.3, D + 0.04, 0.2), (0, FRONT + D / 2, BAND), M["trim"], bevel=0.03)
    K.box("frieze", (W + 0.2, D + 0.2, 0.22), (0, FRONT + D / 2, EAVE + 0.11), M["trim"], bevel=0.03)
    K.box("cornice", (W + 0.5, D + 0.5, CORNICE - EAVE - 0.22), (0, FRONT + D / 2, (EAVE + 0.22 + CORNICE) / 2), M["trim"], bevel=0.04)
    # the front's windows, both storeys, either side of the portico
    for sx in (-1, 1):
        for wx in WIN_X:
            for z0, z1 in (WIN_LO, WIN_HI):
                window("win", M, sx * wx, z0, z1, FRONT - 0.1)
    # the side walls: two windows a storey (the back has the same; inferred)
    for sx in (-1, 1):
        for a in (-1.5, 1.5):
            for z0, z1 in (WIN_LO, WIN_HI):
                window("swin", M, a, z0, z1, -(W / 2 - 0.1), rot=-90 * sx, loc=(0, FRONT + D / 2, 0))
    for a in (-3.2, -1.2, 1.2, 3.2):
        for z0, z1 in (WIN_LO, WIN_HI):
            window("bwin", M, a, z0, z1, -(D / 2 - 0.1), rot=180, loc=(0, FRONT + D / 2, 0))


def roof(M):
    """A hipped roof: the eave rectangle at the cornice's top, a ridge along x."""
    hw, hd = W / 2 + OVER, D / 2 + OVER
    rl = hw - hd  # half the ridge's length
    cy = FRONT + D / 2
    z0, z1 = CORNICE - 0.02, RIDGE
    v = [(-hw, cy - hd, z0), (hw, cy - hd, z0), (hw, cy + hd, z0), (-hw, cy + hd, z0), (-rl, cy, z1), (rl, cy, z1)]
    faces = [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4)]
    me = bpy.data.meshes.new("roof")
    me.from_pydata(v, [], faces)
    me.update()
    ob = K._obj("roof", me, M["roof"])
    # thickness, so the eaves show an edge
    s = ob.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.12
    s.offset = -1
    K.apply_mods(ob)
    # shingle rows level on every slope: u along the eave, v down the slope
    layer = ob.data.uv_layers.new(name="UVMap")
    for poly in ob.data.polygons:
        n = poly.normal
        h = Vector((n.x, n.y, 0))
        if h.length < 0.3:
            for li in poly.loop_indices:
                p = ob.data.vertices[ob.data.loops[li].vertex_index].co
                layer.data[li].uv = (p.x * 0.6, p.y * 0.6)
            continue
        h.normalize()
        along = Vector((-h.y, h.x, 0))
        for li in poly.loop_indices:
            p = ob.data.vertices[ob.data.loops[li].vertex_index].co
            down = (Vector((p.x, p.y - cy, 0)).dot(h)) / math.cos(math.atan2(z1 - z0, hd))
            layer.data[li].uv = (p.dot(along) * 0.6, down * 0.6)
    # ridge and hip caps
    K.box("ridge", (2 * rl + 0.2, 0.22, 0.14), (0, cy, z1 + 0.04), M["roof"], bevel=0.04)
    # chimneys at the roof's ends, cream brick, with caps
    for x, w in CHIM:
        top = Z(255)
        base = z0 + 0.4
        c = K.box("chimney", (w, 0.62, top - base), (x, cy + 0.9, (top + base) / 2), M["brick"], bevel=0.02)
        K.uv_box(c, 1.6)
        K.box("chim_cap", (w + 0.16, 0.78, 0.16), (x, cy + 0.9, top), M["brick"], bevel=0.03)
        K.box("chim_top", (w - 0.2, 0.42, 0.14), (x, cy + 0.9, top + 0.14), M["brick"], bevel=0.03)
    # dormers on the front slope, arched windows (x 262 and 970 of the reference)
    slope = (z1 - z0) / hd
    for x in (-3.25, 3.3):
        zb, zt = Z(505), Z(375)
        yf = cy - hd + (zb - z0) / slope + 0.1  # where the dormer's face meets the roof
        body = K.box("dormer", (1.25, 1.4, zt - zb), (x, yf + 0.7, (zb + zt) / 2), M["trim"], bevel=0.03)
        window("dwin", M, x, zb + 0.12, zt - 0.22, yf)
        K.ball("dormer_hood", 0.74, (x, yf + 0.6, zt - 0.02), M["roof"], scale=(1.0, 1.05, 0.36), u=18, v=10)
        K.box("dormer_sill", (1.4, 0.3, 0.1), (x, yf - 0.05, zb), M["trim"], bevel=0.03)


def cupola(M):
    cy = FRONT + D / 2
    zb = Z(360)  # its red base starts on the ridge
    K.cyl("cup_base", CUP_R * 1.02, CUP_R * 1.02, Z(320) - zb + 0.4, (0, cy, (zb - 0.4 + Z(320)) / 2), M["band"], verts=8, rot=(0, 0, 22.5))
    K.cyl("cup_sill", CUP_R * 1.1, CUP_R * 1.1, 0.14, (0, cy, Z(320)), M["trim"], verts=8, rot=(0, 0, 22.5), bevel=0.02)
    zd0, zd1 = Z(320), Z(235)
    K.cyl("cup_drum", CUP_R * 0.96, CUP_R * 0.96, zd1 - zd0, (0, cy, (zd0 + zd1) / 2), M["band"], verts=8, rot=(0, 0, 22.5))
    flat_r = CUP_R * 0.96 * math.cos(math.pi / 8)
    for k in range(8):
        a = 45 * k
        # a cream post on each corner, and an arched window on each face
        ca = math.radians(a + 22.5)
        K.box("cup_post", (0.16, 0.16, zd1 - zd0), (CUP_R * 0.97 * math.sin(ca), cy - CUP_R * 0.97 * math.cos(ca), (zd0 + zd1) / 2), M["trim"], bevel=0.02)
        window("cwin", M, 0, zd0 + 0.08, zd1 - 0.06, -flat_r, rot=a, loc=(0, cy, 0))
    K.cyl("cup_cornice", CUP_R * 1.12, CUP_R * 1.16, Z(205) - zd1, (0, cy, (zd1 + Z(205)) / 2), M["trim"], verts=8, rot=(0, 0, 22.5), bevel=0.02)
    # the dome: shingled, on an octagonal base, a gold ball and the flagpole
    zr = Z(205)
    prof = [(CUP_R * 1.0 * math.cos(t), zr + 0.85 * math.sin(t)) for t in np.linspace(0, math.pi / 2, 10)]
    prof[-1] = (0.0, prof[-1][1])
    K.lathe("dome", prof, M["roof"], steps=24, loc=(0, cy, 0), u_rep=8, v_rep=3)
    top = zr + 0.85
    K.ball("finial", 0.13, (0, cy, top + 0.12), M["gold"], u=14, v=9)
    K.cyl("finial_neck", 0.06, 0.09, 0.12, (0, cy, top + 0.02), M["gold"], verts=12)
    pole_top = Z(18)
    K.cyl("flagpole", 0.035, 0.035, pole_top - top, (0, cy, (top + pole_top) / 2), M["gold"], verts=10)
    K.ball("pole_ball", 0.07, (0, cy, pole_top + 0.05), M["gold"], u=10, v=7)
    # the flag: a red pennant with a gentle wave, a cream maple leaf on it
    fw, fh = 1.25, 0.72
    verts, faces = [], []
    nu, nv = 10, 3
    for i in range(nu + 1):
        for j in range(nv + 1):
            u, v = i / nu, j / nv
            verts.append((0.04 + u * fw, cy + 0.08 * math.sin(u * 5.0) * u, pole_top - 0.12 - fh + v * fh + 0.06 * math.sin(u * 3.2)))
    for i in range(nu):
        for j in range(nv):
            a = i * (nv + 1) + j
            faces.append((a, a + nv + 1, a + nv + 2, a + 1))
    me = bpy.data.meshes.new("flag")
    me.from_pydata(verts, [], faces)
    fl = K._obj("flag", me, M["flag"])
    s = fl.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.02
    K.apply_mods(fl)
    leaf = flat("flag_leaf", maple(0.38, 0.04 + fw * 0.52, pole_top - 0.12 - fh / 2 + 0.06 * math.sin(0.52 * 3.2)), cy + 0.08 * math.sin(2.6) * 0.52 - 0.012, 0.006, M["bloom"], bevel=0.0)


def portico(M):
    # the podium under the portico, level with the doorstep
    pod = K.box("podium", (2 * COL_X + 1.3, FRONT - PODIUM_Y, FLOOR), (0, (FRONT + PODIUM_Y) / 2, FLOOR / 2), M["stone"], bevel=0.02)
    K.uv_box(pod, 0.75)
    # three steps down to the ground, and the cheek blocks either side with urns
    for i in range(3):
        top = FLOOR * (3 - i) / 3 - FLOOR / 3 * 0
        zt = FLOOR * (2 - i) / 3 + FLOOR / 3
        y0 = PODIUM_Y - i * STAIR_RUN
        st = K.box("step", (2 * COL_X - 0.4 + i * 0.35, STAIR_RUN + 0.02, zt), (0, y0 - STAIR_RUN / 2, zt / 2), M["stone"], bevel=0.02)
        K.uv_box(st, 0.75)
    sy = PODIUM_Y - 1.5 * STAIR_RUN
    for sx in (-1, 1):
        x = sx * (COL_X + 0.15)
        ch = K.box("cheek", (0.95, 3 * STAIR_RUN + 0.5, FLOOR + 0.25), (x, sy + 0.2, (FLOOR + 0.25) / 2), M["stone"], bevel=0.03)
        K.uv_box(ch, 0.75)
        K.box("cheek_cap", (1.05, 0.9, 0.12), (x, sy - 0.15, FLOOR + 0.31), M["trim"], bevel=0.03)
        urn(M, (x, sy - 0.15, FLOOR + 0.37))
    # the columns: square base on the podium, a tapering shaft, a cushion capital and abacus
    for sx in (-1, 1):
        x = sx * COL_X
        K.box("col_plinth", (1.05, 1.05, 0.32), (x, COL_Y, FLOOR + 0.16), M["trim"], bevel=0.03)
        prof = [(0.52, FLOOR + 0.32), (0.52, FLOOR + 0.42), (0.46, FLOOR + 0.48), (0.42, FLOOR + 0.55),
                (0.38, ENT0 - 0.55), (0.42, ENT0 - 0.45), (0.5, ENT0 - 0.3), (0.52, ENT0 - 0.24)]
        K.lathe("column", prof, M["trim"], steps=24, loc=(x, COL_Y, 0))
        K.box("col_abacus", (1.2, 1.2, 0.24), (x, COL_Y, ENT0 - 0.12), M["trim"], bevel=0.03)
        # flutes: shallow darker grooves would shimmer at game size; the shaft stays smooth
    # entablature over the columns, back to the wall
    ent_front = COL_Y - 0.62
    K.box("entablature", (2 * PED_HALF, FRONT - ent_front, ENT1 - ENT0), (0, (FRONT + ent_front) / 2, (ENT0 + ENT1) / 2), M["trim"], bevel=0.04)
    K.box("ent_soffit", (2 * PED_HALF - 0.1, FRONT - ent_front, 0.06), (0, (FRONT + ent_front) / 2, ENT0 + 0.02), M["frame"], bevel=0.0)
    # the pediment: a red tympanum inside cream raking cornices, a little roof behind it
    zb = ENT1
    tri = [(-PED_HALF + 0.35, zb + 0.05), (PED_HALF - 0.35, zb + 0.05), (0, APEX - 0.32)]
    flat("tympanum", tri, ent_front + 0.2, 0.06, M["band"], bevel=0.0, uv=None)
    K.box("ped_base", (2 * PED_HALF + 0.3, 0.75, 0.2), (0, ent_front + 0.33, zb + 0.06), M["trim"], bevel=0.04)
    ang = math.degrees(math.atan2(APEX - zb, PED_HALF))
    run = math.hypot(PED_HALF, APEX - zb)
    for sx in (-1, 1):
        K.box("rake", (run + 0.35, 0.8, 0.26), (sx * PED_HALF / 2, ent_front + 0.33, (zb + APEX) / 2 - 0.02), M["trim"], bevel=0.04, rot=(0, sx * ang, 0))
    K.box("ped_key", (0.5, 0.82, 0.42), (0, ent_front + 0.33, APEX - 0.1), M["trim"], bevel=0.05, rot=(0, 45, 0))
    # the pediment's roof, back to the main roof
    hw = PED_HALF + 0.15
    yb = FRONT + 0.4
    v = [(-hw, ent_front + 0.05, zb + 0.1), (0, ent_front + 0.05, APEX), (hw, ent_front + 0.05, zb + 0.1),
         (-hw, yb + 1.6, zb + 0.1), (0, yb + 1.6, APEX), (hw, yb + 1.6, zb + 0.1)]
    me = bpy.data.meshes.new("ped_roof")
    me.from_pydata(v, [], [(0, 3, 4, 1), (1, 4, 5, 2)])
    pr = K._obj("ped_roof", me, M["roof"])
    s = pr.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.1
    K.apply_mods(pr)
    K.uv_box(pr, 0.6, grain="y")
    # the crest: a navy shield with a gold rim, a cream maple leaf, between laurel sprigs
    sz = (zb + APEX) / 2 - 0.12
    shield = [(-0.34, sz + 0.36), (0, sz + 0.3), (0.34, sz + 0.36), (0.33, sz - 0.02), (0.2, sz - 0.24), (0, sz - 0.38), (-0.2, sz - 0.24), (-0.33, sz - 0.02)]
    yt = ent_front + 0.14
    flat("shield_rim", shield, yt, 0.05, M["gold"], bevel=0.012)
    inner = [(x * 0.82, sz + (z - sz) * 0.82) for x, z in shield]
    flat("shield", inner, yt - 0.05, 0.02, M["navy"], bevel=0.005)
    flat("shield_leaf", maple(0.4, 0, sz - 0.02), yt - 0.07, 0.015, M["bloom"], bevel=0.0)
    for sx in (-1, 1):
        laurel(M, sx, (sx * 0.75, yt, sz - 0.12))
    # the lantern hanging from the portico's ceiling over the door
    lx, ly = 0, FRONT - 0.55
    K.cyl("lantern_chain", 0.012, 0.012, 0.3, (lx, ly, ENT0 - 0.15), M["iron"], verts=6)
    K.cyl("lantern_cap", 0.05, 0.2, 0.14, (lx, ly, ENT0 - 0.36), M["iron"], verts=8)
    K.box("lantern_glass", (0.26, 0.26, 0.34), (lx, ly, ENT0 - 0.62), M["glass"], bevel=0.02)
    for a, b in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        K.box("lantern_bar", (0.035, 0.035, 0.38), (lx + a * 0.13, ly + b * 0.13, ENT0 - 0.62), M["iron"], bevel=0.005)
    K.cyl("lantern_foot", 0.15, 0.06, 0.1, (lx, ly, ENT0 - 0.84), M["iron"], verts=8)
    return ent_front


def laurel(M, side, at):
    """A curving sprig of leaves, carved in cream, lying on the tympanum."""
    x0, y, z0 = at
    pts = []
    for k in range(7):
        t = k / 6
        a = math.radians(-60 + 150 * t)  # sweeping up and in towards the shield
        pts.append(Vector((x0 + side * 0.45 * math.cos(a) * 0.9, y - 0.03, z0 + 0.5 * (math.sin(a) + 0.87) * 0.55)))
    CL.tube("laurel_stem", pts, [0.018] * len(pts), M["frame"], sides=6)
    for i, p in enumerate(pts[1:], 1):
        d = (pts[i] - pts[i - 1]).normalized()
        n = Vector((-d.z, 0, d.x))
        for s in (-1, 1):
            c = p + n * s * 0.07 - d * 0.02
            ang = math.degrees(math.atan2(d.z + s * n.z * 0.8, d.x + s * n.x * 0.8))
            lf = K.ball("laurel", 0.085, tuple(c), M["frame"], scale=(1.0, 0.3, 0.42), u=10, v=6)
            lf.rotation_euler = (0, -math.radians(ang), 0)


def urn(M, base):
    x, y, z = base
    prof = [(0.12, z), (0.16, z + 0.05), (0.08, z + 0.12), (0.12, z + 0.2), (0.27, z + 0.38), (0.3, z + 0.44), (0.27, z + 0.48)]
    K.lathe("urn", prof, M["trim"], steps=18, loc=(x, y, 0))
    bush(M, (x, y, z + 0.5), 0.36, n=7, seed=int(abs(x) * 10))


def bush(M, c, r, n=9, seed=1):
    rng = np.random.default_rng(seed)
    x, y, z = c
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, r * 0.7)
        K.ball("bush", r * rng.uniform(0.45, 0.65), (x + d * math.cos(a), y + d * math.sin(a), z + rng.uniform(0, r * 0.5)), M["leaf"], u=10, v=7, scale=(1, 1, 0.85))
    for i in range(n + 3):
        # on the bush's skin, mostly on the front and top, where they show
        a = rng.uniform(-math.pi * 0.95, -math.pi * 0.05)
        e = rng.uniform(0.15, 1.0)
        dirv = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        p = Vector((x, y, z + r * 0.15)) + dirv * r * 0.98
        K.ball("bloom", 0.075 * (r / 0.75) ** 0.5 + 0.02, tuple(p), M["bloom"], u=8, v=5, scale=(1, 1, 0.7))


def front_wall(M):
    """The door in its arched surround with the fanlight, and the two banners."""
    yf = FRONT - 0.1
    # arched surround (x 460..735, top y 645)
    outer = arch(0, FLOOR, 2.55, Z(645) - FLOOR, n=16)
    flat("door_surround", outer, yf, 0.12, M["frame"], bevel=0.02)
    inner = arch(0, FLOOR, 1.7, Z(690) - FLOOR, n=16)
    flat("door_recess", inner, yf - 0.12, 0.02, M["band"], bevel=0.0)
    # the fanlight: glowing, with radiating glazing bars
    zs = Z(790)
    fan = [(0.85 * math.cos(a), zs + (Z(690) - zs) * math.sin(a)) for a in np.linspace(0, math.pi, 14)]
    flat("fanlight", fan, yf - 0.14, 0.02, M["glass"], bevel=0.0)
    for a in (30, 60, 90, 120, 150):
        r = math.radians(a)
        K.box("fan_bar", (0.04, 0.03, 0.8), (0.42 * math.cos(r), yf - 0.17, zs + 0.42 * math.sin(r)), M["door"], bevel=0.0, rot=(0, 90 - a, 0))
    K.box("fan_bar", (1.75, 0.05, 0.08), (0, yf - 0.17, zs), M["door"], bevel=0.01)
    # double doors and their ring handles
    for sx in (-1, 1):
        d = K.box("door", (0.83, 0.08, zs - FLOOR), (sx * 0.43, yf - 0.14, (FLOOR + zs) / 2), M["door"], bevel=0.02)
        K.uv_box(d, 0.9, grain="z")
        for zz in (FLOOR + 0.55, FLOOR + 1.45):
            K.box("door_panel", (0.56, 0.03, 0.62), (sx * 0.43, yf - 0.19, zz), M["door"], bevel=0.02)
        K.torus("door_ring", 0.09, 0.016, (sx * 0.12, yf - 0.22, FLOOR + 1.05), M["gold"], rot=(90, 0, 0), major=14, minor=6)
    # banners on rods (x 280..345 and 850..920)
    for sx in (-1, 1):
        x = sx * 2.65
        top = Z(640)
        K.cyl("banner_rod", 0.025, 0.025, 0.95, (x, yf - 0.32, top), M["gold"], verts=8, rot=(0, 90, 0))
        K.ball("banner_knob", 0.05, (x + 0.48, yf - 0.32, top), M["gold"], u=8, v=6)
        K.ball("banner_knob", 0.05, (x - 0.48, yf - 0.32, top), M["gold"], u=8, v=6)
        K.box("banner_arm", (0.04, 0.32, 0.04), (x - sx * 0.4, yf - 0.16, top), M["gold"], bevel=0.0)
        bw, bh = 0.62, Z(640) - Z(830)
        b = [(x - bw / 2, top - bh), (x, top - bh + 0.24), (x + bw / 2, top - bh), (x + bw / 2, top - 0.04), (x - bw / 2, top - 0.04)]
        flat("banner_trim", b, yf - 0.28, 0.02, M["gold"], bevel=0.0)
        bi = [(x - bw / 2 + 0.05, top - bh + 0.08), (x, top - bh + 0.3), (x + bw / 2 - 0.05, top - bh + 0.08), (x + bw / 2 - 0.05, top - 0.1), (x - bw / 2 + 0.05, top - 0.1)]
        flat("banner", bi, yf - 0.3, 0.012, M["navy"], bevel=0.0)
        flat("banner_leaf", maple(0.3, x, top - bh * 0.42), yf - 0.312, 0.008, M["bloom"], bevel=0.0)


def grounds(M):
    """Bushes either side of the stairs and paving in front (x 60..260, 905..1130)."""
    for sx in (-1, 1):
        bush(M, (sx * (COL_X + 1.75), FRONT - 0.65, 0.3), 0.75, n=18, seed=3 + sx)
    rng = np.random.default_rng(9)
    y0 = PODIUM_Y - 3 * STAIR_RUN
    for row in range(2):
        x = -3.0 + rng.uniform(0, 0.3)
        while x < 3.0:
            w = rng.uniform(0.55, 0.85)
            p = K.box("paver", (w - 0.06, 0.38, 0.05), (x + w / 2, y0 - 0.22 - row * 0.42, 0.02), M["paving"], bevel=0.02)
            K.uv_box(p, 1.2)
            x += w


def build():
    K.reset(NAME)
    M = materials()
    main_block(M)
    roof(M)
    cupola(M)
    ent_front = portico(M)
    front_wall(M)
    grounds(M)
    bpy.context.view_layer.update()
    for o in K.COLL.objects:
        if o.type == "MESH":
            lo = min((o.matrix_world @ v.co).z for v in o.data.vertices)
            if lo < -0.03:
                print("BELOW GROUND", o.name, round(lo, 3))
    K.finish(NAME, OUT, max_tris=60000)
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(OUT, NAME + ".glb"), os.path.join(PROPS, NAME + ".glb"))
    print("COPIED", os.path.join(PROPS, NAME + ".glb"))
    # glTF: Blender -Y is Godot +Z
    print("SIGN_MOUNT godot (0, %.3f, %.3f) under the entablature (bottom %.3f), columns %.2f apart"
          % (ENT0 - 0.4, -ent_front, ENT0, 2 * COL_X))
    print("FOOTPRINT %.2f x %.2f m" % (W + 0.5, DT))


build()
