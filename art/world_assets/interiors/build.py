"""The furniture inside Maplewood's shops, so you can walk in and find the shopkeeper at work.
Simple, sturdy pieces (Alex asked for these to be quick rather than hero props), each its own
model so the game can arrange them per building (data/interiors.json) and the world editor can
place them anywhere.

    Woolly Goods     shop_counter     a panelled counter with a till and a basket of yarn
                     yarn_shelf       an open shelf unit stacked with balls of yarn
                     sweater_rack     an iron rail with three sweaters on hangers, more folded below
    bakery           bakery_counter   a counter with a glass display case of croissants, buns and tarts
                     bread_rack       slanted shelves of loaves, and baguettes standing in a basket
                     brick_oven       a domed brick bread oven, fire glowing in its mouth, logs below
                     flour_sacks      three burlap sacks, one tipped over, with a scoop
    land office      office_desk      a twin-pedestal desk with a ledger, banker's lamp, inkwell and bell
                     filing_cabinet   a four-drawer oak cabinet with brass pulls and labels

Front faces -Y (+Z in Godot), the origin is on the floor under the middle.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/interiors/build.py -- <kind>|all
"""
import math
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
M = {}


def wood(name, base, light, dark, seed, seams=0):
    i, n = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=seams, seed=seed, knots=1)
    return K.textured(name, i, rough=0.7, normal=n, normal_strength=0.6)


def brick_maps(n=256, courses=8, blocks=4, joint=3.0, seed=21):
    mott = K.tile_noise(n, 1.4, seed)
    yy, xx = np.mgrid[0:n, 0:n]
    ch, bw = n / courses, n / blocks
    row = (yy // ch).astype(int)
    xo = (xx + (row % 2) * bw / 2) % n
    ci = (xo // bw).astype(int)
    r = np.random.default_rng(seed)
    tint = (0.82 + 0.3 * r.random((courses, blocks)))[row, ci]
    c = CL.C("#a8583a") * tint[..., None] * (0.88 + 0.2 * mott[..., None])
    d = np.minimum(np.minimum(xo % bw, bw - xo % bw), np.minimum(yy % ch, ch - yy % ch))
    j = np.clip(1 - d / joint, 0, 1)[..., None]
    c = c * (1 - j) + CL.C("#d8ccb4") * j
    hgt = 0.3 * mott + np.clip(d / (joint * 2), 0, 1)
    return K.save_image("int_brick", c, TEX), K.save_image("int_brick_n", K.normal_from_height(hgt, 1.6), TEX)


def materials():
    M.clear()
    M["oak"] = wood("int_oak", "#b07a45", "#cf9a60", "#86562c", 201)
    M["walnut"] = wood("int_walnut", "#6e4528", "#8c5c36", "#4c2e19", 203)
    M["pine"] = wood("int_pine", "#d2a46a", "#e8c088", "#a87842", 205)
    bi, bn = brick_maps()
    M["brick"] = K.textured("int_brick", bi, rough=0.9, normal=bn, normal_strength=1.0)
    si, sn = CL.cloth_maps("int_burlap", TEX, "#c9a874", weave_px=5, rough=0.07)
    M["burlap"] = K.textured("int_burlap", si, rough=0.95, normal=sn, normal_strength=0.8)
    wi = CL.wicker_maps("int_wicker", TEX)
    M["wicker"] = K.textured("int_wicker", wi[0] if isinstance(wi, tuple) else wi, rough=0.9)
    M["iron"] = K.plain("int_iron", "#2b2826", 0.55)
    M["brass"] = K.plain("int_brass", "#c9a24a", 0.35)
    M["glass"] = K.plain("int_glass", "#eef6f7", 0.02, alpha=0.12)
    M["cream"] = K.plain("int_cream", "#efe6d2", 0.8)
    M["paper"] = K.plain("int_paper", "#f1e8d6", 0.9)
    M["ink"] = K.plain("int_ink", "#1d2230", 0.3)
    M["leather"] = K.plain("int_leather", "#7a2e22", 0.6)
    M["green"] = K.plain("int_lampshade", "#2f6b48", 0.3, emit=0.15)
    M["soot"] = K.plain("int_soot", "#1c1714", 0.95)
    M["fire"] = K.plain("int_fire", "#ff7a00", 0.6, emit=0.9)
    M["ember"] = K.plain("int_ember", "#e0520a", 0.7, emit=0.7)
    M["baguette"] = K.plain("int_baguette", "#c98a3e", 0.75)
    M["crust"] = K.plain("int_crust", "#9c4f22", 0.75)
    M["crust_dark"] = K.plain("int_crust_dark", "#8a4f20", 0.75)
    M["dough"] = K.plain("int_dough", "#e7b46a", 0.75)
    M["jam"] = K.plain("int_jam", "#a3202e", 0.35)
    M["crust_bag"] = K.plain("int_paper_bag", "#dcc08f", 0.95)
    M["flour"] = K.plain("int_flour", "#f4efe4", 0.95)
    M["stone"] = K.plain("int_stone", "#918c82", 0.9)


def bx(name, size, loc, mat, bevel=0.01, rot=(0, 0, 0), grain="z", scale=1.0):
    """A box with box-projected UVs (every prop part gets real UVs, so none are collapsed)."""
    ob = K.box(name, size, loc, mat, bevel=bevel, seg=1, rot=rot)
    return K.uv_box(ob, scale, grain=grain)


def cy(name, r1, r2, h, loc, mat, verts=16, rot=(0, 0, 0)):
    return K.uv_box(K.cyl(name, r1, r2, h, loc, mat, verts=verts, rot=rot), 2.0)


def bl(name, r, loc, mat, scale=(1, 1, 1), u=12, v=8, boxy=1.0):
    return K.uv_box(K.ball(name, r, loc, mat, scale=scale, u=u, v=v, boxy=boxy), 2.0)


YARNS = ["plaid", "denim", "cream", "clay", "rug_oat", "rug_wine", "sage", "berry", "sky", "sunflower"]


def yarn_ball(loc, r, i):
    """A ball of yarn: a felt-coloured ball with a band of wraps round it the other way."""
    mat = K.wool(YARNS[i % len(YARNS)])
    bl("yarn", r, loc, mat, u=10, v=7)
    for rx, ry in ((90, 20 * (i % 3)), (90, 20 * (i % 3) + 75)):
        K.uv_box(K.torus("wrap", r * 0.9, r * 0.15, loc, mat, rot=(rx, ry, 0), major=12, minor=4), 2.0)


def panelled_front(w, y, z0, z1, n, mat_frame, mat_panel):
    """Raised panels across a cabinet front at y (facing -Y)."""
    pw = (w - 0.08 * (n + 1)) / n
    for i in range(n):
        x = -w / 2 + 0.08 + pw / 2 + i * (pw + 0.08)
        bx("panel", (pw, 0.02, z1 - z0), (x, y - 0.01, (z0 + z1) / 2), mat_panel, bevel=0.008)


# --- Woolly Goods ---------------------------------------------------------------------------------

def build_shop_counter():
    W, D, H = 1.6, 0.6, 0.95
    bx("body", (W, D, H - 0.12), (0, 0.02, (H - 0.12) / 2 + 0.06), M["walnut"])
    bx("kick", (W - 0.04, D - 0.02, 0.07), (0, 0.03, 0.035), M["walnut"], grain="x")
    bx("top", (W + 0.1, D + 0.08, 0.06), (0, 0, H - 0.03), M["oak"], bevel=0.015, grain="x")
    panelled_front(W - 0.08, -D / 2 + 0.02, 0.16, H - 0.14, 3, M["walnut"], M["oak"])
    # a brass till on the right
    bx("till", (0.34, 0.28, 0.16), (0.48, 0.04, H + 0.08), M["brass"], bevel=0.02)
    bx("till_keys", (0.3, 0.14, 0.05), (0.48, -0.08, H + 0.17), M["walnut"], bevel=0.01, rot=(-20, 0, 0))
    for i in range(3):
        for j in range(2):
            cy("key", 0.016, 0.016, 0.02, (0.39 + i * 0.09, -0.06 - j * 0.05, H + 0.2 - j * 0.02), M["cream"], verts=8)
    bx("till_top", (0.2, 0.06, 0.1), (0.48, 0.13, H + 0.21), M["brass"], bevel=0.015)
    # a wicker basket of yarn on the left, and a ball rolled loose
    cy("basket", 0.17, 0.2, 0.15, (-0.45, 0.0, H + 0.075), M["wicker"], verts=18)
    for i in range(5):
        a = i / 5 * math.tau
        yarn_ball((-0.45 + 0.09 * math.cos(a), 0.09 * math.sin(a), H + 0.17), 0.065, i)
    yarn_ball((-0.45, 0.0, H + 0.22), 0.065, 6)
    yarn_ball((0.0, -0.12, H + 0.055), 0.055, 3)
    # a pair of needles stuck in the loose ball
    cy("needle", 0.006, 0.006, 0.3, (0.03, -0.12, H + 0.1), M["oak"], verts=6, rot=(0, 35, 10))
    cy("needle", 0.006, 0.006, 0.3, (-0.02, -0.11, H + 0.1), M["oak"], verts=6, rot=(0, -30, -5))


def build_yarn_shelf():
    W, D, H = 1.4, 0.4, 1.9
    T = 0.04
    for s in (-1, 1):
        bx("side", (T, D, H), (s * (W / 2 - T / 2), 0, H / 2), M["oak"])
    bx("back", (W - 2 * T + 0.01, 0.02, H), (0, D / 2 - 0.01, H / 2), M["pine"], bevel=0.0)
    bx("crown", (W + 0.08, D + 0.06, 0.06), (0, -0.01, H + 0.03), M["oak"], bevel=0.015, grain="x")
    bx("plinth", (W - 2 * T, 0.03, 0.1), (0, -D / 2 + 0.03, 0.05), M["oak"], grain="x")
    shelves = [0.1, 0.52, 0.94, 1.36]
    for z in shelves:
        bx("shelf", (W - 2 * T, D - 0.02, 0.03), (0, 0.0, z), M["oak"], grain="x")
    rng = np.random.default_rng(31)
    k = 0
    for z in shelves:
        x = -W / 2 + T + 0.09
        while x < W / 2 - T - 0.08:
            r = rng.uniform(0.07, 0.085)
            yarn_ball((x, rng.uniform(-0.04, 0.06), z + 0.015 + r), r, k)
            k += 3
            x += 2 * r + rng.uniform(0.005, 0.02)
        # a second ball stacked on top here and there
        for x2 in rng.uniform(-W / 2 + 0.2, W / 2 - 0.2, 2):
            yarn_ball((x2, 0.02, z + 0.015 + 0.21), 0.065, k)
            k += 1


def sweater(x, y, z, colour, trim):
    """A sweater on a hanger, facing front: a sweater-shaped outline (V neck, sloping shoulders, sleeves
    hanging at its sides), ribbed hem and cuffs, a band across the chest."""
    body = K.wool(colour)
    rib = K.wool(trim)
    top = z - 0.07
    pts = [(-0.06, 0.0), (-0.16, -0.035), (-0.215, -0.07), (-0.245, -0.42), (-0.17, -0.43), (-0.165, -0.15),
           (-0.16, -0.5), (0.16, -0.5), (0.165, -0.15), (0.17, -0.43), (0.245, -0.42), (0.215, -0.07),
           (0.16, -0.035), (0.06, 0.0), (0.0, -0.07)]
    ob = K.extrude_xz("sw_body", [(x + px, top + pz) for px, pz in pts], y - 0.025, y + 0.025, body, bevel=0.012)
    K.uv_box(ob, 2.0)
    for s in (-1, 1):
        bx("sw_cuff", (0.085, 0.056, 0.05), (x + s * 0.208, y, top - 0.43), rib, bevel=0.012, rot=(0, s * 4, 0))
    bx("sw_hem", (0.33, 0.056, 0.06), (x, y, top - 0.49), rib, bevel=0.015)
    bx("sw_band", (0.325, 0.054, 0.04), (x, y, top - 0.2), rib, bevel=0.008)
    for s in (-1, 1):  # the ribbed V of the neckline
        bx("sw_collar", (0.08, 0.056, 0.022), (x + s * 0.032, y, top - 0.032), rib, bevel=0.008, rot=(0, -s * 48, 0))
    # the hanger: a bar across the shoulders, a stem up, and a hook looped over the rail
    bx("hanger", (0.34, 0.015, 0.015), (x, y, top - 0.02), M["oak"], bevel=0.005, grain="x")
    cy("hanger_stem", 0.004, 0.004, 0.05, (x, y, z - 0.045), M["iron"], verts=6)
    K.uv_box(K.torus("hook", 0.022, 0.004, (x, y, z), M["iron"], rot=(90, 0, 90), major=10, minor=4), 2.0)


def build_sweater_rack():
    W, H = 1.2, 1.5
    for s in (-1, 1):
        cy("upright", 0.016, 0.016, H, (s * W / 2, 0, H / 2), M["iron"], verts=8)
        cy("foot", 0.016, 0.016, 0.42, (s * W / 2, 0, 0.03), M["iron"], verts=8, rot=(90, 0, 0))
        bl("foot_cap", 0.03, (s * W / 2, 0.21, 0.03), M["iron"], u=8, v=6)
        bl("foot_cap", 0.03, (s * W / 2, -0.21, 0.03), M["iron"], u=8, v=6)
        bl("finial", 0.03, (s * W / 2, 0, H + 0.02), M["brass"], u=8, v=6)
    cy("rail", 0.014, 0.014, W, (0, 0, H - 0.06), M["iron"], verts=8, rot=(0, 90, 0))
    for i, (c, t) in enumerate((("plaid", "cream"), ("denim", "cream"), ("cream", "clay"))):
        sweater((i - 1) * 0.39, 0.0, H - 0.06, c, t)
    # a low shelf with folded sweaters
    bx("shelf", (W - 0.04, 0.4, 0.03), (0, 0, 0.32), M["oak"], grain="x")
    for i, c in enumerate(("rug_oat", "plaid", "denim")):
        for j in range(3 - (i % 2)):
            bx("folded", (0.3, 0.26, 0.06), ((i - 1) * 0.36, 0.0, 0.365 + j * 0.065), K.wool((c, "clay", "cream")[j % 3] if j else c), bevel=0.02)


# --- the bakery -----------------------------------------------------------------------------------

def croissant(loc, yaw, size=1.0):
    R = 0.05 * size
    pts, radii = [], []
    n = 12
    for i in range(n + 1):
        t = i / n
        a = math.radians(-95 + 190 * t)
        pts.append(K.Vector((R * math.sin(a), -R * math.cos(a) + R * 0.6, 0.0)))
        swell = 0.72 + 0.28 * abs(math.cos(t * math.pi * 5))
        radii.append(0.026 * size * max(0.12, math.sin(math.pi * t)) ** 0.7 * swell)
    ob = CL.tube("croissant", pts, radii, M["dough"], sides=8, v_scale=4.0, flat=0.72)
    ob.rotation_euler = (0, 0, math.radians(yaw))
    ob.location = loc
    return ob


def bun(loc, r=0.045):
    bl("bun", r, loc, M["crust"], scale=(1, 1, 0.62), u=12, v=7)


def tart(loc, r=0.05):
    """A jam tart: a pastry case with a raised rim and a dome of jam in it."""
    cy("tart", r, r * 0.9, 0.03, loc, M["dough"], verts=14)
    K.uv_box(K.torus("tart_rim", r * 0.85, r * 0.17, (loc[0], loc[1], loc[2] + 0.016), M["crust"], major=14, minor=5), 2.0)
    bl("jam", r * 0.72, (loc[0], loc[1], loc[2] + 0.016), M["jam"], scale=(1, 1, 0.45), u=12, v=6)


def build_bakery_counter():
    W, D, H = 1.8, 0.65, 0.9
    bx("body", (W, D, H - 0.1), (0, 0.02, (H - 0.1) / 2 + 0.05), M["oak"])
    bx("kick", (W - 0.04, D - 0.02, 0.06), (0, 0.03, 0.03), M["walnut"], grain="x")
    bx("top", (W + 0.08, D + 0.06, 0.05), (0, 0, H - 0.025), M["walnut"], bevel=0.015, grain="x")
    panelled_front(W - 0.08, -D / 2 + 0.02, 0.14, H - 0.12, 4, M["oak"], M["pine"])
    # the display case: a wooden frame with glass all round, a sloped front, two trays
    CW, CD, CH = W - 0.2, D - 0.12, 0.34
    z0 = H
    for s in (-1, 1):
        bx("case_end", (0.03, CD, CH), (s * (CW / 2 - 0.015), 0, z0 + CH / 2), M["walnut"])
    bx("case_top", (CW, CD * 0.6, 0.025), (0, CD * 0.2, z0 + CH), M["walnut"], grain="x")
    bx("case_back", (CW - 0.06, 0.02, CH), (0, CD / 2 - 0.01, z0 + CH / 2), M["walnut"], bevel=0.0)
    slope = math.hypot(CD * 0.4, CH)
    ang = math.degrees(math.atan2(CD * 0.4, CH))
    bx("case_glass", (CW - 0.06, 0.008, slope), (0, -CD / 2 + CD * 0.2, z0 + CH / 2), M["glass"], bevel=0.0, rot=(-ang, 0, 0))
    bx("case_rail", (CW, 0.03, 0.03), (0, -CD / 2, z0 + 0.015), M["brass"], bevel=0.008, grain="x")
    # top tray: croissants and buns; bottom (the counter top itself): tarts
    bx("tray", (CW - 0.1, CD * 0.45, 0.012), (0, CD * 0.12, z0 + 0.17), M["cream"], bevel=0.0)
    for i in range(4):
        croissant((-CW / 2 + 0.17 + i * 0.2, CD * 0.12, z0 + 0.2), 10 + 25 * (i % 3), 2.3)
    for i in range(3):
        bun((CW / 2 - 0.5 + i * 0.17, CD * 0.13, z0 + 0.225), 0.085)
    for i in range(6):
        tart((-CW / 2 + 0.17 + i * 0.255, -CD * 0.08 + 0.04 * (i % 2), z0 + 0.02), 0.08)
    # a little brass bell and a stack of paper bags at the end
    cy("bell", 0.05, 0.015, 0.05, (-W / 2 + 0.06, -0.15, H + 0.03), M["brass"], verts=14)
    bl("bell_knob", 0.012, (-W / 2 + 0.06, -0.15, H + 0.065), M["brass"], u=8, v=6)
    # two paper bags standing at the end of the counter, beside the case, tops folded over
    for j, (bx_, by_) in enumerate(((W / 2 - 0.06, -0.22), (W / 2 - 0.06, 0.12))):
        bx("bag", (0.09, 0.13, 0.19), (bx_, by_, H + 0.095), M["crust_bag"], bevel=0.004, rot=(0, 0, 10 * j))
        for k in range(3):  # the top rolled down in uneven folds
            bx("bag_fold", (0.095, 0.135, 0.022), (bx_ + 0.004 * (k - 1), by_, H + 0.2 + 0.016 * k), M["crust_bag"], bevel=0.004,
               rot=(0, (-9, 6, -14)[k], 10 * j + (3, -4, 5)[k]))


def loaf(loc, yaw, long=0.22, r=0.06):
    bl("loaf", r, loc, M["crust"], scale=(long / (2 * r), 1, 0.7), u=14, v=8)
    for k in (-1, 0, 1):
        bl("score", r * 0.42, (loc[0] + k * long * 0.22, loc[1], loc[2] + r * 0.5), M["dough"], scale=(0.22, 1.0, 0.45), u=8, v=5)


def build_bread_rack():
    W, D, H = 1.4, 0.45, 1.7
    T = 0.04
    for s in (-1, 1):
        bx("side", (T, D, H), (s * (W / 2 - T / 2), 0, H / 2), M["pine"])
    bx("back", (W - 2 * T, 0.02, H - 0.1), (0, D / 2 - 0.01, H / 2 + 0.05), M["pine"], bevel=0.0)
    bx("crown", (W + 0.06, D + 0.04, 0.05), (0, 0, H + 0.025), M["oak"], grain="x")
    for i, z in enumerate((0.25, 0.7, 1.15)):
        # slanted shelves with a lip, so the bread faces the shop
        bx("shelf", (W - 2 * T, D - 0.04, 0.04), (0, 0.0, z + 0.06), M["oak"], rot=(-16, 0, 0), grain="x")
        bx("lip", (W - 2 * T, 0.02, 0.06), (0, -D / 2 + 0.03, z + 0.06), M["oak"], grain="x")
        for k in range(4 if i != 1 else 5):
            n = 4 if i != 1 else 5
            x = -W / 2 + T + (k + 0.5) * (W - 2 * T) / n
            if i == 1:
                bun((x, -0.07, z + 0.1), 0.075)
                bun((x + 0.03, 0.08, z + 0.12), 0.075)
            else:
                loaf((x, -0.01, z + 0.14), 0, long=0.3, r=0.085)
    # top shelf: two baskets of rolls
    for s in (-1, 1):
        cy("basket", 0.16, 0.19, 0.14, (s * 0.32, 0.0, H + 0.05 + 0.07), M["wicker"], verts=16)
        for k in range(5):
            a = k / 5 * math.tau
            bun((s * 0.32 + 0.09 * math.cos(a), 0.09 * math.sin(a), H + 0.05 + 0.15), 0.06)
        bun((s * 0.32, 0.0, H + 0.05 + 0.19), 0.06)
    # baguettes standing in a tall basket beside it
    cy("tall_basket", 0.13, 0.15, 0.4, (W / 2 + 0.18, -0.05, 0.2), M["wicker"], verts=16)
    for k in range(5):
        a = k / 5 * math.tau
        bg = bl("baguette", 0.036, (0, 0, 0), M["baguette"], scale=(1, 1, 9.0), u=10, v=10, boxy=0.8)
        bg.rotation_euler = (math.radians(8 * math.sin(a)), math.radians(8 * math.cos(a)), 0)
        bg.location = (W / 2 + 0.18 + 0.05 * math.cos(a), -0.05 + 0.05 * math.sin(a), 0.52)


def build_brick_oven():
    W, D = 1.3, 1.0
    base_h = 0.8
    bx("base", (W, D, base_h), (0, 0, base_h / 2), M["brick"], bevel=0.02, scale=1.6)
    bx("hearth", (W + 0.06, D + 0.06, 0.07), (0, -0.01, base_h + 0.035), M["stone"], bevel=0.02)
    # wood store in an arch under the hearth
    bx("niche", (0.8, 0.04, 0.42), (0, -D / 2 + 0.01, 0.3), M["soot"], bevel=0.0)
    for k, (x, z) in enumerate(((-0.24, 0.15), (0.0, 0.15), (0.24, 0.15), (-0.12, 0.3), (0.12, 0.3), (0.0, 0.43))):
        cy("log", 0.065, 0.065, 0.5, (x, -D / 2 + 0.2, z), M["walnut"], verts=10, rot=(90, 0, 0))
        cy("log_end", 0.055, 0.055, 0.01, (x, -D / 2 - 0.05, z), M["pine"], verts=10, rot=(90, 0, 0))
    # the dome
    dome = bl("dome", 0.6, (0, 0.04, base_h + 0.07), M["brick"], scale=(1.0, 0.75, 0.78), u=20, v=12)
    K.uv_box(dome, 1.6)
    # the mouth: a stone arch round a dark opening with the fire glowing inside
    mz = base_h + 0.07
    bx("mouth", (0.44, 0.06, 0.26), (0, -0.4, mz + 0.13), M["soot"], bevel=0.0)
    K.uv_box(K.torus("arch", 0.25, 0.04, (0, -0.44, mz + 0.13), M["stone"], rot=(90, 0, 0), major=20, minor=6), 2.0)
    bx("arch_sill", (0.6, 0.12, 0.05), (0, -0.45, mz + 0.01), M["stone"], bevel=0.01)
    bl("fire", 0.11, (0, -0.445, mz + 0.07), M["fire"], scale=(1.5, 0.25, 0.75), u=10, v=6)
    for k in range(4):
        bl("ember", 0.035, (-0.12 + k * 0.08, -0.46, mz + 0.035), M["ember"], scale=(1, 0.6, 0.8), u=8, v=5)
    # the flue up out of the back of the dome
    bx("flue", (0.26, 0.26, 0.8), (0, 0.28, base_h + 0.3 + 0.4), M["brick"], bevel=0.015, scale=1.6)
    bx("flue_cap", (0.32, 0.32, 0.05), (0, 0.28, base_h + 1.1 + 0.03), M["stone"], bevel=0.01)
    # a baker's peel leaning on the side
    bx("peel_blade", (0.03, 0.26, 0.3), (W / 2 + 0.04, -0.15, 0.2), M["pine"], bevel=0.01, rot=(0, 8, 0))
    cy("peel_handle", 0.018, 0.018, 1.1, (W / 2 + 0.07, -0.15, 0.88), M["pine"], verts=8, rot=(0, 8, 0))


def sack(loc, h=0.5, r=0.2, tilt=(0, 0, 0)):
    ob = bl("sack", r, (0, 0, 0), M["burlap"], scale=(1.0, 0.85, h / (2 * r)), u=14, v=10, boxy=0.85)
    for v in ob.data.vertices:  # slumped: wider low down, narrower at the shoulders
        t = (v.co.z / (h / 2) + 1) / 2
        v.co.x *= 1.08 - 0.22 * t
        v.co.y *= 1.08 - 0.22 * t
    ob.rotation_euler = [math.radians(a) for a in tilt]
    ob.location = loc
    return ob


def gathered_neck(x, y, z, r):
    """The neck of a sack: a tie round it and the cloth bunched up above in a ruffle."""
    K.uv_box(K.torus("tie", r, r * 0.22, (x, y, z), M["leather"], major=12, minor=5), 2.0)
    cy("neck", r * 1.05, r * 0.85, r * 0.9, (x, y, z + r * 0.4), M["burlap"], verts=10)
    for k in range(7):
        a = k / 7 * math.tau
        bl("ruffle", r * 0.55, (x + r * 0.9 * math.cos(a), y + r * 0.9 * math.sin(a), z + r * 1.1), M["burlap"],
           scale=(1.0, 1.0, 1.3), u=8, v=6)


def build_flour_sacks():
    sack((-0.18, 0.05, 0.25), 0.5, 0.19)
    gathered_neck(-0.18, 0.05, 0.5, 0.06)
    sack((0.2, 0.1, 0.22), 0.44, 0.18)
    gathered_neck(0.2, 0.1, 0.44, 0.055)
    # one tipped over in front, its open mouth spilling flour onto the floor
    sack((0.0, -0.2, 0.14), 0.46, 0.15, tilt=(0, 90, 20))
    mx, my = 0.21, -0.12
    # its mouth: one flared, floppy lip of cloth opening toward the spill, flour inside it
    d = K.Vector((math.cos(math.radians(20)), math.sin(math.radians(20)), 0))
    lip = cy("mouth", 0.085, 0.11, 0.08, (mx, my, 0.13), M["burlap"], verts=14, rot=(0, 90, 20))
    for v in lip.data.vertices:  # flop: the top of the lip sags
        if v.co.z > 0.13:
            v.co.z -= 0.025 * (v.co.z - 0.13) / 0.11
    bl("mouth_flour", 0.075, (mx + 0.03, my + 0.01, 0.12), M["flour"], scale=(0.5, 1, 0.8), u=10, v=6)
    rng = np.random.default_rng(5)
    for k in range(6):
        bl("spill", rng.uniform(0.06, 0.1), (mx + 0.06 + k * 0.035 + rng.uniform(-0.02, 0.02), my - 0.02 + rng.uniform(-0.07, 0.07), 0.01),
           M["flour"], scale=(1.3, 1.0, 0.35), u=10, v=6)
    # a wooden scoop in the spill
    # a wooden scoop lying in the spill: an open bowl full of flour and a short handle
    sc = K.lathe("scoop", [(0.0, 0.0), (0.045, 0.004), (0.055, 0.03), (0.05, 0.032), (0.0, 0.01)], M["pine"], steps=14,
                 loc=(0.38, -0.24, 0.005))
    K.uv_box(sc, 2.0)
    bl("scoop_flour", 0.042, (0.38, -0.24, 0.03), M["flour"], scale=(1, 1, 0.3), u=10, v=6)
    cy("scoop_handle", 0.011, 0.011, 0.08, (0.465, -0.24, 0.022), M["oak"], verts=6, rot=(0, 90, 0))


# --- the land office ------------------------------------------------------------------------------

def build_office_desk():
    W, D, H = 1.4, 0.7, 0.78
    bx("top", (W, D, 0.04), (0, 0, H - 0.02), M["walnut"], bevel=0.012, grain="x")
    bx("blotter", (0.6, 0.38, 0.006), (0, 0.04, H + 0.003), M["leather"], bevel=0.0)
    for s in (-1, 1):
        px = s * (W / 2 - 0.21)
        bx("pedestal", (0.4, D - 0.06, H - 0.04), (px, 0.0, (H - 0.04) / 2), M["walnut"])
        # drawers on the back (the clerk's side, +Y); the front shows panels
        for k, z in enumerate((0.2, 0.42, 0.62)):
            bx("drawer", (0.34, 0.02, 0.18 if k else 0.24), (px, (D - 0.06) / 2 + 0.008, z), M["oak"], bevel=0.008)
            bl("pull", 0.015, (px, (D - 0.06) / 2 + 0.025, z), M["brass"], u=8, v=6)
        bx("panel", (0.32, 0.02, H - 0.2), (px, -(D - 0.06) / 2 - 0.008, H / 2 - 0.03), M["oak"], bevel=0.008)
    bx("modesty", (W - 0.8, 0.02, H - 0.3), (0, -D / 2 + 0.06, H - 0.04 - (H - 0.3) / 2), M["walnut"], bevel=0.0)
    # an open ledger
    for s in (-1, 1):
        bx("ledger", (0.2, 0.28, 0.012), (s * 0.105, 0.04, H + 0.012), M["paper"], bevel=0.002, rot=(0, s * 4, 0))
    bx("ledger_cover", (0.43, 0.3, 0.01), (0, 0.04, H + 0.007), M["leather"], bevel=0.0)
    for k in range(5):
        bx("line", (0.15, 0.004, 0.002), (-0.105, -0.06 + k * 0.04, H + 0.02), M["ink"], bevel=0.0)
    # banker's lamp on the left
    lx, ly = -0.48, 0.12
    cy("lamp_base", 0.08, 0.09, 0.03, (lx, ly, H + 0.015), M["brass"], verts=14)
    cy("lamp_stem", 0.012, 0.012, 0.3, (lx, ly, H + 0.18), M["brass"], verts=8)
    shade = cy("lamp_shade", 0.08, 0.08, 0.3, (lx, ly - 0.04, H + 0.34), M["green"], verts=16, rot=(0, 90, 0))
    K.uv_box(shade, 2.0)
    # inkwell and quill, a stamp, a bell, a stack of deeds
    cy("inkwell", 0.035, 0.03, 0.05, (0.38, 0.2, H + 0.025), M["ink"], verts=12)
    cy("quill", 0.004, 0.002, 0.28, (0.4, 0.2, H + 0.16), M["cream"], verts=6, rot=(20, 15, 0))
    vane = cy("quill_vane", 0.004, 0.024, 0.15, (0.422, 0.169, H + 0.232), M["cream"], verts=8, rot=(20, 15, 0))
    vane.scale = (0.35, 1.0, 1.0)
    cy("stamp", 0.025, 0.025, 0.05, (0.28, -0.12, H + 0.025), M["walnut"], verts=10)
    bl("stamp_knob", 0.025, (0.28, -0.12, H + 0.07), M["walnut"], u=8, v=6)
    cy("bell", 0.045, 0.012, 0.045, (0.55, -0.2, H + 0.022), M["brass"], verts=14)
    bl("bell_knob", 0.01, (0.55, -0.2, H + 0.05), M["brass"], u=8, v=6)
    for j in range(5):
        bx("deed", (0.22, 0.28, 0.008), (0.5, 0.15, H + 0.004 + j * 0.009), M["paper"], bevel=0.0, rot=(0, 0, (j * 37) % 11 - 5))
    bx("ribbon", (0.03, 0.29, 0.05), (0.5, 0.15, H + 0.025), M["leather"], bevel=0.0)


def build_filing_cabinet():
    W, D, H = 0.55, 0.5, 1.3
    bx("body", (W, D, H - 0.06), (0, 0, (H - 0.06) / 2 + 0.06), M["oak"])
    bx("top", (W + 0.04, D + 0.04, 0.03), (0, 0, H + 0.015), M["walnut"], bevel=0.01)
    bx("plinth", (W - 0.02, D - 0.02, 0.06), (0, 0.0, 0.03), M["walnut"])
    dh = (H - 0.12) / 4
    for k in range(4):
        z = 0.08 + dh * (k + 0.5)
        bx("drawer", (W - 0.06, 0.02, dh - 0.03), (0, -D / 2 - 0.005, z), M["oak"], bevel=0.008)
        bx("label", (0.11, 0.008, 0.05), (0, -D / 2 - 0.02, z + 0.07), M["brass"], bevel=0.002)
        bx("label_card", (0.09, 0.006, 0.035), (0, -D / 2 - 0.024, z + 0.07), M["paper"], bevel=0.0)
        bx("pull", (0.14, 0.03, 0.025), (0, -D / 2 - 0.025, z - 0.02), M["brass"], bevel=0.008)
    # a potted fern and a stack of boxes on top
    bx("box", (0.3, 0.22, 0.12), (-0.05, 0.03, H + 0.09), M["cream"], bevel=0.01)
    bx("box", (0.26, 0.2, 0.1), (-0.04, 0.02, H + 0.2), M["paper"], bevel=0.01, rot=(0, 0, 8))


KINDS = {
    "shop_counter": (build_shop_counter, 9000),
    "yarn_shelf": (build_yarn_shelf, 16000),
    "sweater_rack": (build_sweater_rack, 6000),
    "bakery_counter": (build_bakery_counter, 9000),
    "bread_rack": (build_bread_rack, 12000),
    "brick_oven": (build_brick_oven, 8000),
    "flour_sacks": (build_flour_sacks, 4000),
    "office_desk": (build_office_desk, 6000),
    "filing_cabinet": (build_filing_cabinet, 3000),
}


def build(name):
    K.reset(name)
    materials()
    fn, budget = KINDS[name]
    fn()
    out = os.path.join(HERE, "out", name)
    K.finish(name, out, max_tris=budget)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for a in (KINDS if args[0] == "all" else args):
    build(a)
