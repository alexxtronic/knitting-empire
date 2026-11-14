"""The candle, the cloth-bound books and the café's furniture (Alex, 2026-11-14: "a cozy little
cafe of dreams", from his three references: a pillar candle in a brass chamberstick, a chunky
purple book with gold corners and a red ribbon, and a candle-lit café mock-up).

    candle            a chunky cream pillar candle with soft drips, in a brass chamberstick with a
                      ring handle. The flame is live in the game (Catalog.lit_candle), at FLAME_Z.
    book_<colour>     a chunky cloth-bound book lying flat: gold corner caps, gold spine bands, a gold
                      leaf on the cover, a red ribbon. Colours: plum (the reference), forest, wine,
                      navy, mustard.
    book_stack        three of them in a pile
    cafe_counter      a green panelled counter with a wood top and a glass case of croissants,
                      cinnamon buns and muffins
    espresso_bar      the back bar: a red espresso machine, a grinder, jars of beans, shelves of
                      cups above, and a chalkboard with a coffee cup on it
    cafe_bookshelf    a tall shelf crammed with cloth-bound books, a plant trailing from the top
    cafe_table        a round café table with two spindle-back chairs and a jar of lavender
    cafe_coffee_table a low planked table with books, a jug of daisies and a cup
    pouf              a tufted tartan pouf
    pendant_lamp      a dark enamel dome lamp hung on a cord (the game adds its light)

Candles on the other pieces are the candle model itself, put there by the game
(data/furniture.json "candles"), so every candle in the world is the same one and is lit.

Front faces -Y here (+Z in Godot); the origin is on the floor under the middle.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/cafe_props/build.py -- <kind> ... | all

Writes <kind>/out/<kind>.{blend,glb} and copies the GLB to assets/props/.
"""
import math
import os
import shutil
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

PROPS = os.path.join(K.PROJECT, "assets", "props")
TEX = os.path.join(HERE, "tex")
M = {}
rng = np.random.default_rng(5)

# the cloth colours of the books (sampled from the reference for plum), each with its worn-edge tint
CLOTH = {
    "plum": ("#6a2352", "#a3486a"),
    "forest": ("#2e5236", "#5f8a55"),
    "wine": ("#7e2128", "#b0503a"),
    "navy": ("#253860", "#58709a"),
    "mustard": ("#b4842a", "#dcae52"),
}
GOLD = "#d9a03c"


def C(h):
    return np.array(K.hex_rgb(h))


# --- textures ------------------------------------------------------------------------------------

def cloth_cover(name, colour, n=512, frame=True):
    """Book cloth: a fine weave, soft mottling, rubbed lighter at the edges; with frame=True the
    front cover's gold inset frame (notched corners) and the little flourishes at top and bottom,
    painted on. UV 0..1 spans the cover."""
    base, worn = CLOTH[colour]
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 3.0) * np.sign(np.sin(2 * np.pi * yy / 6.0)) + 0.25 * np.sin(2 * np.pi * yy / 3.0)
    mott = K.tile_noise(n, 1.5, 11)
    rgb = C(base) * (0.84 + 0.22 * weave[..., None]) * (0.88 + 0.2 * mott[..., None])
    d = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    rub = np.clip(1 - d / 0.035, 0, 1) * (0.5 + 0.6 * K.tile_noise(n, 1.0, 12))
    rgb = rgb * (1 - 0.6 * rub[..., None]) + C(worn) * 0.6 * rub[..., None]
    hgt = 0.4 * weave
    gold = np.zeros((n, n))
    if frame:
        # an inset frame line with concave-cut corners, as on the reference
        m, w, r = 0.13, 0.012, 0.075
        cu, cv = np.abs(u - 0.5), np.abs(v - 0.5)
        hx, hy = 0.5 - m, 0.5 - m
        on_rect = (np.abs(np.maximum(cu - hx, cv - hy)) < w) & (cu <= hx + w) & (cv <= hy + w)
        corner_d = np.hypot(cu - hx, cv - hy)
        in_corner = (cu > hx - r) & (cv > hy - r)
        arc = in_corner & (np.abs(corner_d - r) < w)
        line = (on_rect & ~in_corner) | arc
        gold = np.maximum(gold, line.astype(float))
        # three-dot flourishes centred above and below the emblem
        for sv in (0.5 + hy - 0.07, 0.5 - hy + 0.07):
            for du, dv, rr in ((0.0, 0.0, 0.016), (-0.035, 0.012, 0.012), (0.035, 0.012, 0.012), (0.0, 0.03 * np.sign(sv - 0.5), 0.009)):
                gold = np.maximum(gold, (np.hypot(u - 0.5 - du, v - sv - dv * np.sign(sv - 0.5)) < rr).astype(float))
    gold = np.clip(gold, 0, 1)
    gmott = 0.85 + 0.25 * K.tile_noise(n, 1.2, 13)
    rgb = rgb * (1 - gold[..., None]) + (C(GOLD) * gmott[..., None]) * gold[..., None]
    hgt = hgt * (1 - gold) + 0.8 * gold
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.6), TEX)


def pages_image(name, n=256):
    """The page block's edges: cream, with fine page lines running along u, a little uneven."""
    yy, xx = np.mgrid[0:n, 0:n]
    lines = 0.5 + 0.5 * np.sin(2 * np.pi * yy / 2.6 + 3 * K.tile_noise(n, 2.0, 21))
    mott = K.tile_noise(n, 1.4, 22)
    rgb = C("#f2dfb2") * (0.86 + 0.1 * lines[..., None]) * (0.92 + 0.12 * mott[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(lines * 0.4, 1.2), TEX)


def hammered(name, hexcol, n=256, seed=31):
    """Gold or brass with a soft hammered, hand-cast surface."""
    mott = K.tile_noise(n, 1.1, seed)
    dent = K.tile_noise(n, 0.6, seed + 1)
    rgb = C(hexcol) * (0.82 + 0.3 * mott[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(dent * 0.5 + mott * 0.3, 1.4), TEX)


def wax_image(name, n=256):
    """Cream wax: soft mottling and faint vertical pour marks; v runs up the candle, lighter toward
    the top where the flame warms it."""
    yy, xx = np.mgrid[0:n, 0:n]
    v = 1 - yy / n
    mott = K.tile_noise(n, 1.6, 41)
    streak = K.grain_noise(n, 20.0, 1.2, 42)
    rgb = C("#ecc88a") * (0.93 + 0.08 * mott[..., None] + 0.04 * streak[..., None])
    rgb = rgb * (1 - v[..., None] * 0.0) + (C("#f6dfaa") - C("#ecc88a")) * (v ** 2)[..., None]
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(mott * 0.3 + streak * 0.15, 0.8), TEX)


def chalkboard_image(name, n=512):
    """A slate board in a wood frame (frame modelled): a steaming coffee cup in chalk between two
    laurel sprigs, as on the café mock-up's menu board."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    smear = K.tile_noise(n, 1.3, 51)
    rgb = C("#2a2f2b") * (0.85 + 0.3 * smear[..., None])
    chalk = np.zeros((n, n))

    def stroke(mask, a=1.0):
        nonlocal chalk
        chalk = np.maximum(chalk, mask.astype(float) * a)

    w = 0.011
    # the cup: a bowl (lower half ellipse), its rim, a handle, a saucer
    cx, cy, rx, ry = 0.5, 0.45, 0.17, 0.13
    e = np.hypot((u - cx) / rx, (v - cy) / ry)
    stroke((np.abs(e - 1) < w / ry * 1.2) & (v <= cy + 0.005))
    stroke((np.abs(v - cy) < w) & (np.abs(u - cx) < rx))
    h = np.hypot((u - (cx + rx + 0.02)) / 0.05, (v - (cy - 0.04)) / 0.045)
    stroke((np.abs(h - 1) < 0.25) & (u > cx + rx - 0.01))
    stroke((np.abs(np.hypot((u - cx) / 0.27, (v - (cy - ry - 0.01)) / 0.03) - 1) < 0.35) & (v < cy - ry + 0.01))
    # three wavy steam lines
    for dx in (-0.06, 0.0, 0.06):
        sx = cx + dx + 0.025 * np.sin((v - cy) * 28)
        stroke((np.abs(u - sx) < w * 0.9) & (v > cy + 0.05) & (v < cy + 0.25))
    # laurel sprigs either side: a curved stem and little leaves
    for s in (-1, 1):
        for t in np.linspace(0, 1, 9):
            ang = math.pi * (0.95 + 0.55 * t)
            px = cx + s * (0.32 * math.cos(ang) * -1)
            py = cy - 0.02 + 0.3 * math.sin(ang) * -1 * 0.9
            stroke(np.hypot(u - px, v - py) < 0.006)
            if 0.1 < t < 0.95:
                lx, ly = px + s * 0.03, py + 0.012
                stroke(np.hypot((u - lx) / 0.028, (v - ly) / 0.012) < 1.0, 0.85)
    chalk = np.clip(chalk, 0, 1) * (0.75 + 0.25 * K.tile_noise(n, 0.7, 52))
    rgb = rgb * (1 - chalk[..., None]) + C("#ece6d6") * chalk[..., None]
    return K.save_image(name, rgb, TEX)


def tartan_image(name, n=256):
    """Red and cream tartan, as on the café's cushions and pouf."""
    yy, xx = np.mgrid[0:n, 0:n]
    def band(t):
        t = t % 64
        return np.where(t < 28, 0, np.where(t < 32, 2, np.where(t < 56, 1, 3)))
    bu, bv = band(xx), band(yy)
    cols = [C("#9c2b25"), C("#6e1c1c"), C("#e9d8b6"), C("#3f4a2a")]
    a = np.zeros((n, n, 3))
    for i, c in enumerate(cols):
        a += (bu == i)[..., None] * c * 0.5 + (bv == i)[..., None] * c * 0.5
    weave = 0.5 + 0.5 * np.sin(2 * np.pi * (xx + yy) / 4)
    rgb = a * (0.88 + 0.14 * weave[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(weave * 0.3, 1.0), TEX)


# --- materials -----------------------------------------------------------------------------------

def metal(name, hexcol, rough=0.32, metallic=0.85, seed=31):
    i, n = hammered(name, hexcol, seed=seed)
    m = K.textured(name, i, rough, normal=n, normal_strength=0.5)
    m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = metallic
    return m


def materials():
    M.clear()
    M["gold"] = metal("book_gold", GOLD, 0.35, 0.8, 31)
    M["brass"] = metal("candle_brass", "#c8901e", 0.3, 0.85, 33)
    wi, wn = wax_image("candle_wax")
    M["wax"] = K.textured("candle_wax", wi, 0.55, normal=wn, normal_strength=0.4)
    M["wick"] = K.plain("candle_wick", "#3a2414", 0.9)
    pi, pn = pages_image("book_pages")
    M["pages"] = K.textured("book_pages", pi, 0.9, normal=pn, normal_strength=0.6)
    M["ribbon"] = K.textured("book_ribbon", CL.cloth_maps("book_ribbon", TEX, "#b3302a", weave_px=2)[0], 0.8)
    M["oak"] = wood("cafe_oak", "#b4672f", "#d48a48", "#86451d", 301)
    M["walnut"] = wood("cafe_walnut", "#7b3f1e", "#9c5a2e", "#55290f", 303)
    M["green"] = wood("cafe_green", "#3f5c45", "#4f7055", "#2c4231", 305, seams=0, knots=0)
    M["cream"] = K.plain("cafe_cream", "#f1e7d3", 0.35)
    M["red"] = K.plain("cafe_machine_red", "#a3262a", 0.25)
    M["chrome"] = K.plain("cafe_chrome", "#d6d6d2", 0.15)
    M["chrome"].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
    M["black"] = K.plain("cafe_black", "#1e1a18", 0.4)
    M["glass"] = K.plain("cafe_glass", "#eef6f7", 0.02, alpha=0.14)
    M["beans"] = K.plain("cafe_beans", "#3b2212", 0.55)
    M["kraft"] = K.plain("cafe_kraft", "#b98a52", 0.9)
    M["pastry"] = K.plain("cafe_pastry", "#d7923e", 0.6)
    M["pastry_dark"] = K.plain("cafe_pastry_dark", "#a8601f", 0.6)
    M["icing"] = K.plain("cafe_icing", "#f6ecd8", 0.5)
    M["berry"] = K.plain("cafe_berry", "#3b2a52", 0.5)
    M["paper"] = K.plain("cafe_paper", "#efe3c8", 0.9)
    M["leaf"] = K.plain("cafe_leaf", "#4f7f36", 0.8)
    M["leaf_dark"] = K.plain("cafe_leaf_dark", "#365f28", 0.8)
    M["lavender"] = K.plain("cafe_lavender", "#8e70b8", 0.8)
    M["daisy"] = K.plain("cafe_daisy", "#f7f1e2", 0.7)
    M["daisy_eye"] = K.plain("cafe_daisy_eye", "#e0a92a", 0.6)
    M["clay"] = K.plain("cafe_clay", "#c47838", 0.85)
    M["soil"] = K.plain("cafe_soil", "#3a2a1c", 0.95)
    M["enamel"] = K.plain("cafe_enamel", "#2e3530", 0.35)
    M["bulb"] = K.plain("cafe_bulb", "#ffd98a", 0.3, emit=3.0)
    ci = chalkboard_image("cafe_chalkboard")
    M["chalk"] = K.textured("cafe_chalkboard", ci, 0.9)
    ti, tn = tartan_image("cafe_tartan")
    M["tartan"] = K.textured("cafe_tartan", ti, 0.95, normal=tn, normal_strength=0.6)
    for c in CLOTH:
        si, sn = cloth_cover("book_spine_" + c, c, n=128, frame=False)
        M["spine_" + c] = K.textured("book_spine_" + c, si, 0.85, normal=sn, normal_strength=0.7)


def cover_mat(colour):
    key = "cover_" + colour
    if key not in M:
        i, n = cloth_cover("book_cover_" + colour, colour)
        M[key] = K.textured("book_cover_" + colour, i, 0.85, normal=n, normal_strength=0.8)
    return M[key]


def wood(name, base, light, dark, seed, seams=0, knots=1):
    i, n = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=seams, seed=seed, knots=knots)
    return K.textured(name, i, rough=0.7, normal=n, normal_strength=0.6)


def bx(name, size, loc, mat, bevel=0.01, rot=(0, 0, 0), grain="z", scale=1.0):
    return K.uv_box(K.box(name, size, loc, mat, bevel=bevel, seg=1, rot=rot), scale, grain=grain)


def cy(name, r1, r2, h, loc, mat, verts=16, rot=(0, 0, 0)):
    return K.uv_box(K.cyl(name, r1, r2, h, loc, mat, verts=verts, rot=rot), 2.0)


def bl(name, r, loc, mat, scale=(1, 1, 1), u=12, v=8, boxy=1.0):
    return K.uv_box(K.ball(name, r, loc, mat, scale=scale, u=u, v=v, boxy=boxy), 4.0)


def uv_top(ob, x0, x1, y0, y1):
    """UVs mapped once across a rectangle seen from above (the book's front cover)."""
    me = ob.data
    lay = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for li, loop in enumerate(me.loops):
        p = ob.matrix_world @ me.vertices[loop.vertex_index].co
        lay.data[li].uv = ((p.x - x0) / (x1 - x0), (p.y - y0) / (y1 - y0))
    return ob


# --- the candle ----------------------------------------------------------------------------------

CANDLE_R = 0.042  # the pillar's radius
CANDLE_H = 0.19  # its height above the dish
DISH_Z = 0.016  # where the pillar stands in the cup
FLAME_Z = DISH_Z + CANDLE_H + 0.012  # the wick's tip: the game's flame starts here


def pillar(mat, r=CANDLE_R, h=CANDLE_H, z0=DISH_Z, drips=5, seed=1):
    """A pillar of wax with a soft rounded top that slumps over its edge, a shallow melt pool
    round the wick, and drips running down from the lip. One mesh, built ring by ring."""
    rr = np.random.default_rng(seed)
    seg = 40
    lip = 1.0 + 0.04 * rr.random(seg)  # the top's wobble, so the edge isn't machined
    prof = [(0.0, 0.0), (r * 0.98, 0.0), (r, 0.004)]
    prof += [(r, h * t) for t in (0.3, 0.6, 0.85)]
    prof += [(r * 1.05, h - 0.016), (r * 1.1, h - 0.007), (r * 1.09, h + 0.002), (r * 0.97, h + 0.008),
             (r * 0.78, h + 0.004), (r * 0.6, h - 0.003), (r * 0.25, h - 0.006), (0.0, h - 0.006)]
    verts, faces, uvs = [], [], []
    n = len(prof)
    for i in range(seg + 1):
        a = 2 * math.pi * i / seg
        k = lip[i % seg]
        for j, (pr, pz) in enumerate(prof):
            s = k if j >= 6 else 1.0
            verts.append(Vector((pr * s * math.cos(a), pr * s * math.sin(a), z0 + pz)))
    for i in range(seg):
        for j in range(n - 1):
            a, b = i * n + j, (i + 1) * n + j
            faces.append((a, b, b + 1, a + 1))
            uvs += [(i / seg * 2, prof[j][1] / h), ((i + 1) / seg * 2, prof[j][1] / h),
                    ((i + 1) / seg * 2, prof[j + 1][1] / h), (i / seg * 2, prof[j + 1][1] / h)]
    before = set(K.COLL.objects)
    ob = CL._finish_mesh("wax", verts, faces, uvs, mat)
    # drips: a fat bead hanging from the lip, thinning as it runs down, a round drop at its end
    angs = np.sort(rr.uniform(0, math.tau, drips))
    for k, a in enumerate(angs):
        a = float(a)
        L = float(rr.uniform(0.03, 0.085))
        w = float(rr.uniform(0.015, 0.02))
        # a run of soft beads pressed into the side, narrowing as it goes, and a round drop at the end
        n_b = 12
        for t in map(float, np.linspace(0, 1, n_b)):
            rad = w * (1.0 - 0.3 * t)
            d = r + 0.45 * rad - 0.003 * t
            bl("drip", rad, (d * math.cos(a), d * math.sin(a), z0 + h - 0.014 - L * t), mat,
               scale=(0.75, 0.75, 1.5), u=10, v=7)
        d = r + 0.55 * w
        bl("drip_end", w * 0.95, (d * math.cos(a), d * math.sin(a), z0 + h - 0.006 - L - 0.004), mat, scale=(0.85, 0.85, 1.25), u=12, v=8)
    # fuse the pillar and its drips into one soft surface: voxel remesh, relax, thin out
    parts = [o for o in K.COLL.objects if o not in before]
    for o in bpy.context.view_layer.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.0018
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 4
    dc = ob.modifiers.new("dec", "DECIMATE")
    dc.ratio = 0.12
    bpy.context.view_layer.update()
    K.apply_mods(ob)
    ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
    # UVs: round the candle (u) and up it (v), so the wax texture's warm top sits at the top
    me = ob.data
    for l in list(me.uv_layers):
        me.uv_layers.remove(l)
    lay = me.uv_layers.new(name="UVMap")
    for li, loop in enumerate(me.loops):
        co = me.vertices[loop.vertex_index].co
        lay.data[li].uv = ((math.atan2(co.y, co.x) / math.tau + 0.5) * 2, (co.z - z0) / h)
    return ob


def build_candle():
    brass = M["brass"]
    # the chamberstick: a round dish with a rolled rim, a cup in the middle, a ring handle
    K.lathe("dish", [(0.0, 0.0), (0.074, 0.0), (0.082, 0.004), (0.086, 0.014), (0.084, 0.024), (0.078, 0.026),
                     (0.074, 0.018), (0.07, 0.012), (0.056, 0.009), (0.052, 0.01)], brass, steps=40, u_rep=2)
    K.lathe("cup", [(0.052, 0.009), (0.05, 0.016), (0.051, 0.03), (0.055, 0.034), (0.051, 0.036), (0.047, 0.03), (0.046, 0.016)],
            brass, steps=40, u_rep=2)
    K.uv_box(K.torus("handle", 0.025, 0.0085, (0.108, 0.0, 0.034), brass, rot=(90, 0, 0), major=24, minor=8), 3.0)
    bx("handle_tab", (0.026, 0.02, 0.008), (0.086, 0.0, 0.022), brass, bevel=0.003)
    pillar(M["wax"])
    pts = [Vector((0, 0, DISH_Z + CANDLE_H - 0.008)), Vector((0.0005, 0, DISH_Z + CANDLE_H + 0.004)), Vector((0.002, 0, FLAME_Z))]
    CL.tube("wick", pts, [0.0022, 0.002, 0.0016], M["wick"], sides=6)
    print("FLAME_AT %.4f" % FLAME_Z)


# --- the book ------------------------------------------------------------------------------------

BW, BL, BT = 0.165, 0.225, 0.066  # across (spine to fore-edge), long, thick


def book(colour, loc=(0, 0, 0), yaw=0.0, ribbon=True, emblem=True, s=1.0):
    """A chunky cloth-bound book lying on its back, spine on its left (-X), the ribbon out of the
    bottom (-Y) edge. Built at the origin, then turned and moved into place."""
    before = set(K.COLL.objects)
    w, L, t = BW * s, BL * s, BT * s
    ct = 0.0075 * s  # each board's thickness
    ov = 0.006 * s  # how far the boards stand out past the pages
    sp = 0.012 * s  # the spine's bulge
    cloth = cover_mat(colour)
    spine = M["spine_" + colour]
    x0 = -w / 2 + sp
    # the two boards
    for z, top in ((ct / 2, False), (t - ct / 2, True)):
        b = K.box("board", (w - sp, L, ct), (x0 + (w - sp) / 2, 0, z), cloth, bevel=0.0028 * s, seg=2)
        uv_top(b, x0, w / 2, -L / 2, L / 2)
    # the page block, a touch hollow at the fore-edge
    pb = K.box("pages", (w - sp - ov, L - 2 * ov, t - 2 * ct + 0.001), (x0 + (w - sp - ov) / 2, 0, t / 2), M["pages"], bevel=0.002 * s, seg=1)
    K.uv_box(pb, 12.0 / s, grain="x")
    # the rounded spine: a half-tube of cloth wrapping the page block's back
    sl = K.cyl("spine", t / 2, t / 2, L, (x0, 0, t / 2), spine, verts=20, rot=(90, 0, 0))
    sl.scale = (sp / (t / 2) * 1.25, 1, 1)
    K.apply_mods(sl)
    K.uv_box(sl, 6.0 / s)
    # gold bands round the spine, raised, as on the reference
    for yy in (-L * 0.33, 0.0, L * 0.33):
        band = K.cyl("band", t / 2 + 0.002 * s, t / 2 + 0.002 * s, 0.012 * s, (x0, yy, t / 2), M["gold"], verts=20, rot=(90, 0, 0))
        band.scale = (sp / (t / 2) * 1.25 + 0.04, 1, 1.03)
        K.apply_mods(band)
        K.uv_box(band, 8.0)
    # corner caps: an L of gold over each corner of the front board, folded over its edge, with a rivet
    cap = 0.046 * s
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx = (w / 2 - cap / 2 + 0.0015) if sx > 0 else (x0 + cap / 2 - 0.001)
            cyy = sy * (L / 2 - cap / 2 + 0.0015)
            for zc in (t - ct / 2,) + ((ct / 2,) if sx > 0 else ()):
                ob = K.extrude_xz("cap", [(-cap / 2, -cap / 2), (cap / 2, -cap / 2), (cap / 2, cap / 2), (cap / 2 - cap * 0.38, cap / 2),
                                          (-cap / 2 + cap * 0.1, -cap / 2 + cap * 0.62), (-cap / 2, -cap / 2 + cap * 0.62)],
                                  -ct / 2 - 0.0014 * s, ct / 2 + 0.0014 * s, M["gold"], bevel=0.0012 * s)
                # extrude_xz draws in XZ; turn it so the shape lies in XY, the corner pointing outward
                ob.rotation_euler = (math.radians(90), 0, 0)
                bpy.context.view_layer.update()
                K.apply_mods(ob)
                me = ob.data
                for v in me.vertices:
                    v.co = Vector((v.co.x * sx, -v.co.y * sy if False else v.co.y * -sy, v.co.z))
                me.update()
                ob.location = (cx, cyy, zc)
                bmf = bmesh.new()
                bmf.from_mesh(me)
                bmesh.ops.recalc_face_normals(bmf, faces=bmf.faces)
                bmf.to_mesh(me)
                bmf.free()
                K.uv_box(ob, 8.0)
                if zc > ct:
                    bl("rivet", 0.0048 * s, (cx + sx * cap * 0.18, cyy + sy * cap * 0.18, t + 0.0014 * s), M["gold"], scale=(1, 1, 0.55), u=8, v=5)
    # the leaf emblem: raised gold, a curving stem with five leaves
    if emblem:
        ex, ey, ez = x0 + (w - sp) / 2, 0.0, t + 0.0006 * s
        es = s * 1.3  # the leaf fills the frame, as on the reference
        stem = [Vector((ex - 0.022 * es, ey - 0.042 * es, ez)), Vector((ex - 0.008 * es, ey - 0.015 * es, ez)),
                Vector((ex + 0.002 * es, ey + 0.012 * es, ez)), Vector((ex + 0.004 * es, ey + 0.032 * es, ez))]
        CL.tube("stem", stem, [0.0028 * es, 0.0026 * es, 0.0022 * es, 0.0016 * s], M["gold"], sides=6, flat=0.45)
        for (px, py, ang, size) in ((0.004, 0.036, 85, 1.0), (-0.012, 0.02, 150, 0.95), (0.016, 0.018, 35, 0.95),
                                    (-0.016, -0.006, 160, 0.75), (0.012, -0.01, 20, 0.75)):
            lf = K.ball("leaf", 0.0125 * es * size, (ex + px * es, ey + py * es, ez + 0.0008 * es), M["gold"], scale=(1.75, 0.95, 0.22), u=12, v=6)
            lf.rotation_euler = (0, 0, math.radians(ang))
            bpy.context.view_layer.update()
            K.apply_mods(lf)
            K.uv_box(lf, 8.0)
    # the ribbon: out from between the pages at the bottom edge, near the spine, down to the table
    if ribbon:
        rx = x0 + 0.03 * s
        pts = [Vector((rx, -L / 2 + ov + 0.004, t * 0.55)), Vector((rx + 0.002, -L / 2 - 0.004 * s, t * 0.45)),
               Vector((rx + 0.004, -L / 2 - 0.009 * s, t * 0.2)), Vector((rx + 0.006, -L / 2 - 0.016 * s, 0.003)),
               Vector((rx + 0.01, -L / 2 - 0.05 * s, 0.0016))]
        CL.tube("ribbon", pts, [0.0075 * s] * len(pts), M["ribbon"], sides=4, flat=0.12, caps=True)
        # the notched end, lying on the table
        tip = pts[-1]
        for sx2 in (-1, 1):
            ob = K.box("ribbon_tail", (0.0075 * s, 0.012 * s, 0.0014), (tip.x + sx2 * 0.0038 * s, tip.y - 0.004 * s, 0.0016), M["ribbon"], bevel=0.0, seg=1,
                       rot=(0, 0, -sx2 * 18))
            K.uv_box(ob, 20.0)
    made = [o for o in K.COLL.objects if o not in before]
    from mathutils import Matrix
    T = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in made:
        o.matrix_world = T @ o.matrix_world
    bpy.context.view_layer.update()
    return made


def build_book(colour):
    book(colour)


def build_book_stack():
    book("navy", (0.0, 0.0, 0.0), 4, ribbon=False, emblem=False, s=1.08)
    book("forest", (0.008, -0.004, BT * 1.08), -9, ribbon=False, emblem=False, s=1.0)
    book("plum", (-0.004, 0.006, BT * 1.08 + BT), 6, ribbon=False, emblem=True, s=0.95)


# --- books standing on a shelf -------------------------------------------------------------------

SHELF_COLOURS = list(CLOTH) + ["tan", "olive", "brown"]


def shelf_mat(c):
    if c in CLOTH:
        return M["spine_" + c]
    key = "spine_" + c
    if key not in M:
        M[key] = K.plain("book_spine_" + c, {"tan": "#b8935e", "olive": "#6b6a32", "brown": "#5a3520"}[c], 0.85)
    return M[key]


def upright_book(x, y, z, w, h, d, c, lean=0.0):
    """A book stood on a shelf, spine to the room (-Y): cloth, cream page tops, two gold bands."""
    rot = (0, lean, 0)
    bx("ub", (w, d, h), (x, y, z + h / 2), shelf_mat(c), bevel=0.003, rot=rot, scale=6.0)
    if lean == 0.0:
        bx("ubp", (w * 0.86, d * 0.94, 0.004), (x, y + 0.002, z + h + 0.001), M["pages"], bevel=0.0, scale=12.0)
        for f in (0.18, 0.8):
            bx("ubg", (w * 1.02, 0.004, 0.008), (x, y - d / 2 - 0.001, z + h * f), M["gold"], bevel=0.0, scale=8.0)


def fill_shelf(x0, x1, y, z, hmax, seed):
    r = np.random.default_rng(seed)
    x = x0
    while x < x1 - 0.03:
        if r.random() < 0.07 and x < x1 - 0.25:  # a little stack lying flat
            for k in range(r.integers(2, 4)):
                c = SHELF_COLOURS[r.integers(0, len(SHELF_COLOURS))]
                bx("flat", (0.2, 0.15, 0.035), (x + 0.1 + r.uniform(-0.008, 0.008), y, z + 0.0175 + k * 0.036), shelf_mat(c), bevel=0.003, scale=6.0)
            x += 0.22
            continue
        w = r.uniform(0.028, 0.055)
        h = r.uniform(0.62, 0.95) * hmax
        c = SHELF_COLOURS[r.integers(0, len(SHELF_COLOURS))]
        if r.random() < 0.05 and x > x0 + 0.1:
            upright_book(x + 0.04, y, z, w, h * 0.9, 0.17, c, lean=-18.0)
            x += 0.09
            continue
        upright_book(x + w / 2, y, z, w, h, r.uniform(0.15, 0.19), c)
        x += w + r.uniform(0.0, 0.004)


# --- the café's furniture -----------------------------------------------------------------------

def croissant(x, y, z, yaw):
    pts = [Vector((math.cos(a) * 0.035, math.sin(a) * 0.035, 0)) for a in np.linspace(-1.1, 1.1 + math.pi, 9)]
    rad = [0.008, 0.013, 0.017, 0.02, 0.021, 0.02, 0.017, 0.013, 0.008]
    ob = CL.tube("croissant", pts, rad, M["pastry"], sides=10, flat=0.75)
    ob.rotation_euler = (0, 0, math.radians(yaw))
    ob.location = (x, y, z + 0.016)
    bpy.context.view_layer.update()


def bun(x, y, z):
    pts = [Vector((math.cos(a) * (0.006 + 0.0035 * a), math.sin(a) * (0.006 + 0.0035 * a), 0.0)) for a in np.linspace(0, 4 * math.pi, 28)]
    CL.tube("bun", pts, [0.009] * len(pts), M["pastry"], sides=6, flat=0.8)
    obs = [o for o in K.COLL.objects if o.name.startswith("bun")]
    obs[-1].location = (x, y, z + 0.012)
    bl("icing", 0.03, (x, y, z + 0.016), M["icing"], scale=(1, 1, 0.22), u=10, v=5)


def muffin(x, y, z):
    cy("muffin_cup", 0.022, 0.028, 0.03, (x, y, z + 0.015), M["paper"], verts=12)
    bl("muffin_top", 0.032, (x, y, z + 0.033), M["pastry_dark"], scale=(1, 1, 0.7), u=10, v=6)
    for k in range(4):
        a = k * 1.7
        bl("berry", 0.006, (x + 0.018 * math.cos(a), y + 0.018 * math.sin(a), z + 0.048), M["berry"], u=6, v=4)


def jar(x, y, z, r, h, fill):
    cy("jar", r, r, h, (x, y, z + h / 2), M["glass"], verts=16)
    cy("jar_fill", r * 0.9, r * 0.9, h * 0.75, (x, y, z + h * 0.39), fill, verts=12)
    cy("jar_lid", r * 1.02, r * 1.02, 0.02, (x, y, z + h + 0.01), M["brass"], verts=16)


def cup(x, y, z, s=1.0):
    cy("cup", 0.032 * s, 0.026 * s, 0.05 * s, (x, y, z + 0.025 * s), M["cream"], verts=14)
    K.uv_box(K.torus("cup_handle", 0.014 * s, 0.004 * s, (x + 0.036 * s, y, z + 0.027 * s), M["cream"], rot=(90, 0, 0), major=10, minor=4), 4.0)


def build_cafe_counter():
    W, D, H = 1.8, 0.62, 1.0
    bx("body", (W - 0.04, D - 0.06, H - 0.1), (0, 0.03, (H - 0.1) / 2 + 0.04), M["green"], scale=1.5)
    bx("kick", (W - 0.06, D - 0.05, 0.08), (0, 0.035, 0.04), M["walnut"], grain="x")
    bx("top", (W + 0.08, D + 0.06, 0.06), (0, -0.01, H - 0.03), M["oak"], bevel=0.015, grain="x")
    # raised panels, framed in a slightly darker green rail
    n, z0, z1 = 4, 0.16, H - 0.16
    pw = (W - 0.08 - 0.08 * (n + 1)) / n
    for i in range(n):
        x = -W / 2 + 0.04 + 0.08 + pw / 2 + i * (pw + 0.08)
        bx("panel", (pw, 0.03, z1 - z0), (x, -D / 2 + 0.02, (z0 + z1) / 2), M["green"], bevel=0.012, scale=1.5)
        bx("panel_in", (pw - 0.08, 0.02, z1 - z0 - 0.08), (x, -D / 2 + 0.0, (z0 + z1) / 2), M["green"], bevel=0.01, scale=1.5)
    bx("rail", (W - 0.04, 0.03, 0.05), (0, -D / 2 + 0.015, H - 0.11), M["walnut"], grain="x")
    # the glass case on the right: a wood base, glass on three sides and the top, two shelves of pastries
    cx, cw, cd, ch = 0.45, 0.78, 0.46, 0.34
    zt = H
    bx("case_base", (cw, cd, 0.05), (cx, 0.02, zt + 0.025), M["walnut"], grain="x")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx("case_post", (0.025, 0.025, ch), (cx + sx * (cw / 2 - 0.0125), 0.02 + sy * (cd / 2 - 0.0125), zt + 0.05 + ch / 2), M["walnut"], bevel=0.004)
    bx("case_top", (cw, cd, 0.025), (cx, 0.02, zt + 0.05 + ch + 0.0125), M["walnut"], grain="x")
    bx("case_glass", (cw - 0.04, cd - 0.04, ch), (cx, 0.02, zt + 0.05 + ch / 2), M["glass"], bevel=0.0)
    bx("case_shelf", (cw - 0.05, cd - 0.06, 0.01), (cx, 0.02, zt + 0.05 + ch * 0.5), M["glass"], bevel=0.0)
    for k in range(4):
        croissant(cx - 0.28 + k * 0.12, -0.05 + (k % 2) * 0.1, zt + 0.05, rng.uniform(-30, 30))
    for k in range(3):
        bun(cx - 0.24 + k * 0.16, 0.06, zt + 0.05 + ch * 0.5 + 0.005)
        muffin(cx - 0.18 + k * 0.17, -0.08, zt + 0.05 + ch * 0.5 + 0.005)
    # a cake under a glass dome on a stand, at the left
    cy("stand_foot", 0.06, 0.08, 0.02, (-0.55, 0.0, zt + 0.01), M["cream"], verts=18)
    cy("stand_stem", 0.02, 0.02, 0.08, (-0.55, 0.0, zt + 0.06), M["cream"], verts=12)
    cy("stand_plate", 0.15, 0.15, 0.012, (-0.55, 0.0, zt + 0.106), M["cream"], verts=24)
    cy("cake", 0.11, 0.11, 0.08, (-0.55, 0.0, zt + 0.152), M["pastry"], verts=20)
    cy("cake_icing", 0.112, 0.112, 0.02, (-0.55, 0.0, zt + 0.192), M["icing"], verts=20)
    K.uv_box(K.ball("dome", 0.14, (-0.55, 0.0, zt + 0.112), M["glass"], scale=(1, 1, 1.15), u=20, v=10), 2.0)
    bl("dome_knob", 0.015, (-0.55, 0.0, zt + 0.275), M["brass"], u=8, v=6)
    # a tip jar and a little coffee bag at the front
    jar(-0.2, -0.12, zt, 0.04, 0.1, M["beans"])
    bx("bag", (0.09, 0.06, 0.15), (-0.06, 0.0, zt + 0.075), M["kraft"], bevel=0.01)
    bx("bag_label", (0.05, 0.002, 0.05), (-0.06, -0.031, zt + 0.085), M["leaf"], bevel=0.0)


def build_espresso_bar():
    W, D, H = 1.6, 0.48, 0.92
    bx("cab", (W, D - 0.02, H - 0.08), (0, 0.01, (H - 0.08) / 2 + 0.04), M["green"], scale=1.5)
    bx("kick", (W - 0.02, D - 0.04, 0.08), (0, 0.02, 0.04), M["walnut"], grain="x")
    for s in (-1, 1):
        bx("door", (W / 2 - 0.08, 0.02, H - 0.24), (s * W / 4, -D / 2 + 0.0, H / 2), M["green"], bevel=0.012, scale=1.5)
        bl("knob", 0.014, (s * 0.07, -D / 2 - 0.02, H / 2 + 0.08), M["brass"], u=8, v=6)
    bx("top", (W + 0.04, D + 0.02, 0.05), (0, 0.0, H + 0.025), M["oak"], bevel=0.012, grain="x")
    zt = H + 0.05
    # the espresso machine: a red body with a rounded crown, two group heads, a steam wand, a gauge
    mx = -0.25
    bx("mach_base", (0.56, 0.36, 0.06), (mx, 0.02, zt + 0.03), M["chrome"], bevel=0.01)
    bx("mach_body", (0.52, 0.34, 0.3), (mx, 0.03, zt + 0.06 + 0.15), M["red"], bevel=0.03)
    K.uv_box(K.cyl("mach_crown", 0.17, 0.17, 0.52, (mx, 0.03, zt + 0.36), M["red"], verts=24, rot=(0, 90, 0)), 2.0)
    bpy.context.view_layer.update()
    crown = [o for o in K.COLL.objects if o.name.startswith("mach_crown")][-1]
    crown.scale = (1, 1, 0.38)
    K.apply_mods(crown)
    bx("cup_rail", (0.5, 0.3, 0.015), (mx, 0.03, zt + 0.43), M["chrome"], bevel=0.004)
    for k in range(5):
        cup(mx - 0.18 + k * 0.09, 0.03, zt + 0.44, 0.8)
    bx("drip_tray", (0.5, 0.14, 0.03), (mx, -0.2, zt + 0.075), M["chrome"], bevel=0.006)
    for s in (-1, 1):
        gx = mx + s * 0.12
        cy("group", 0.04, 0.04, 0.06, (gx, -0.16, zt + 0.2), M["chrome"], verts=16)
        cy("portafilter", 0.035, 0.035, 0.035, (gx, -0.17, zt + 0.155), M["chrome"], verts=14)
        bx("pf_handle", (0.025, 0.12, 0.025), (gx, -0.26, zt + 0.15), M["black"], bevel=0.008, rot=(-8, 0, 0))
        cup(gx, -0.2, zt + 0.09, 0.85)
    bx("wand", (0.012, 0.012, 0.16), (mx + 0.24, -0.16, zt + 0.16), M["chrome"], bevel=0.004, rot=(0, 10, 0))
    cy("gauge", 0.04, 0.04, 0.012, (mx, -0.14, zt + 0.29), M["chrome"], verts=18, rot=(90, 0, 0))
    cy("gauge_face", 0.032, 0.032, 0.004, (mx, -0.147, zt + 0.29), M["cream"], verts=18, rot=(90, 0, 0))
    # a grinder, three jars of beans, a bag of coffee
    gx = 0.32
    bx("grinder", (0.16, 0.18, 0.22), (gx, 0.05, zt + 0.11), M["black"], bevel=0.02)
    cy("hopper", 0.05, 0.08, 0.14, (gx, 0.05, zt + 0.29), M["glass"], verts=16)
    cy("hopper_beans", 0.045, 0.06, 0.08, (gx, 0.05, zt + 0.26), M["beans"], verts=12)
    for k, x in enumerate((0.52, 0.64)):
        jar(x, 0.08, zt, 0.05, 0.18 - 0.03 * k, M["beans"])
    bx("bag", (0.12, 0.08, 0.2), (0.6, -0.1, zt + 0.1), M["kraft"], bevel=0.012)
    bx("bag_label", (0.07, 0.002, 0.07), (0.6, -0.141, zt + 0.11), M["leaf"], bevel=0.0)
    # open shelves on the wall above, on brackets, with cups and jars
    for k, z in enumerate((1.42, 1.8)):
        bx("shelf", (W - 0.1, 0.24, 0.035), (0, D / 2 - 0.12, z), M["oak"], bevel=0.008, grain="x")
        for s in (-1, 1):
            bx("bracket", (0.03, 0.18, 0.12), (s * (W / 2 - 0.2), D / 2 - 0.1, z - 0.07), M["walnut"], bevel=0.006)
        if k == 0:
            for i in range(7):
                cup(-0.62 + i * 0.12, D / 2 - 0.12, z + 0.018, 1.0)
        else:
            for i in range(4):
                jar(-0.55 + i * 0.16, D / 2 - 0.12, z + 0.018, 0.045, 0.14, M["beans"] if i % 2 == 0 else M["kraft"])
            K.uv_box(K.ball("pot_plant", 0.09, (0.5, D / 2 - 0.12, z + 0.12), M["leaf"], scale=(1.3, 1, 0.9), u=10, v=7), 3.0)
            cy("pot", 0.06, 0.05, 0.1, (0.5, D / 2 - 0.12, z + 0.068), M["clay"], verts=12)
            for t in range(6):  # trailing ivy over the shelf's edge
                bl("ivy", 0.028, (0.43 + 0.03 * t, D / 2 - 0.26, z - 0.04 - 0.06 * t), M["leaf_dark"], scale=(1, 0.5, 1.4), u=8, v=5)
    # the chalkboard menu at the top, in a wood frame
    bw, bh, bz = 0.74, 0.5, 2.32
    bx("frame", (bw + 0.08, 0.035, bh + 0.08), (-0.35, D / 2 - 0.03, bz), M["walnut"], bevel=0.01)
    face = K.pane("board", (-0.35 - bw / 2, D / 2 - 0.05, bz - bh / 2), (-0.35 + bw / 2, D / 2 - 0.05, bz + bh / 2), M["chalk"], (0, -1, 0))
    return face


def build_cafe_bookshelf():
    W, D, H = 1.5, 0.4, 2.2
    T = 0.045
    for s in (-1, 1):
        bx("side", (T, D, H), (s * (W / 2 - T / 2), 0, H / 2), M["walnut"])
    bx("back", (W - 2 * T + 0.01, 0.02, H), (0, D / 2 - 0.01, H / 2), M["walnut"], bevel=0.0)
    bx("crown", (W + 0.1, D + 0.06, 0.07), (0, -0.01, H + 0.035), M["walnut"], bevel=0.015, grain="x")
    bx("plinth", (W + 0.04, D + 0.03, 0.1), (0, 0.0, 0.05), M["walnut"], grain="x")
    shelves = [0.1, 0.52, 0.94, 1.36, 1.78]
    for z in shelves[1:]:
        bx("shelf", (W - 2 * T, D - 0.02, 0.03), (0, 0.0, z), M["walnut"], grain="x")
    for k, z in enumerate(shelves):
        top = (shelves[k + 1] if k + 1 < len(shelves) else H) - z - 0.03
        fill_shelf(-W / 2 + T + 0.005, W / 2 - T - 0.005, 0.02, z + 0.015, min(0.36, top - 0.02), 61 + k)
    # a plant on the crown, trailing down the left side
    cy("pot", 0.1, 0.08, 0.15, (-0.5, 0.0, H + 0.07 + 0.075), M["clay"], verts=14)
    bl("leaves", 0.14, (-0.5, 0.0, H + 0.07 + 0.2), M["leaf"], scale=(1.3, 1.1, 0.8), u=12, v=8)
    for t in range(9):
        bl("ivy", 0.035, (-0.66 - 0.01 * (t % 2), -0.16, H + 0.05 - 0.09 * t), M["leaf_dark" if t % 2 else "leaf"], scale=(1, 0.55, 1.4), u=8, v=5)


def windsor_chair(x, y, face):
    """A spindle-back café chair at (x, y), its seat facing `face` (degrees about Z, 0 = toward -Y)."""
    before = set(K.COLL.objects)
    w = M["oak"]
    cy("seat", 0.21, 0.21, 0.045, (0, 0, 0.46), w, verts=24)
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        cy("leg", 0.016, 0.02, 0.47, (0.15 * math.cos(r), 0.15 * math.sin(r), 0.228), w, verts=8,
           rot=(7 * math.sin(r), -7 * math.cos(r), 0))
    bk = K.torus("back_rail", 0.2, 0.016, (0, 0.0, 0.86), w, rot=(0, 0, 0), major=24, minor=6)
    # keep only the back half of the hoop
    bm = bmesh.new()
    bm.from_mesh(bk.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < 0.02], context="VERTS")
    bm.to_mesh(bk.data)
    bm.free()
    K.uv_box(bk, 4.0)
    for k in range(5):
        a = math.radians(30 + 30 * k)
        cy("spindle", 0.008, 0.009, 0.4, (0.19 * math.cos(a), 0.19 * math.sin(a), 0.68), w, verts=6)
    made = [o for o in K.COLL.objects if o not in before]
    from mathutils import Matrix
    T = Matrix.Translation(Vector((x, y, 0))) @ Matrix.Rotation(math.radians(face), 4, "Z")
    for o in made:
        o.matrix_world = T @ o.matrix_world
    bpy.context.view_layer.update()


def build_cafe_table():
    w = M["oak"]
    cy("top", 0.36, 0.36, 0.04, (0, 0, 0.74), w, verts=32)
    bx("apron", (0.5, 0.5, 0.05), (0, 0, 0.7), M["walnut"], bevel=0.01)
    cy("pedestal", 0.045, 0.06, 0.68, (0, 0, 0.36), M["walnut"], verts=14)
    for a in (0, 90):
        bx("foot", (0.56, 0.06, 0.05), (0, 0, 0.03), M["walnut"], bevel=0.015, rot=(0, 0, a))
    # a jar of lavender at one side (the game stands a candle at the other)
    jar_x, jar_y = -0.12, 0.08
    cy("vase", 0.035, 0.03, 0.1, (jar_x, jar_y, 0.81), M["glass"], verts=12)
    for k in range(9):
        a = k * 0.7
        h = 0.14 + 0.04 * math.sin(k * 1.3)
        tilt = (math.degrees(0.15 * math.cos(a)), math.degrees(0.15 * math.sin(a)), 0)
        cy("lav_stem", 0.003, 0.003, h, (jar_x + 0.01 * math.cos(a), jar_y + 0.01 * math.sin(a), 0.78 + h / 2), M["leaf"], verts=4, rot=tilt)
        bl("lav", 0.012, (jar_x + 0.01 * math.cos(a) + 0.15 * h * math.sin(math.radians(tilt[1])), jar_y + 0.01 * math.sin(a) - 0.15 * h * math.sin(math.radians(tilt[0])), 0.78 + h),
           M["lavender"], scale=(1, 1, 2.8), u=6, v=5)
    windsor_chair(-0.62, 0.0, 90)
    windsor_chair(0.62, 0.0, -90)


def daisy(x, y, z):
    cy("d_stem", 0.003, 0.003, 0.12, (x, y, z - 0.06), M["leaf"], verts=4)
    for k in range(8):
        a = k * math.tau / 8
        bl("petal", 0.011, (x + 0.012 * math.cos(a), y + 0.012 * math.sin(a), z), M["daisy"], scale=(1.6, 0.6, 0.25), u=6, v=4)
    bl("eye", 0.007, (x, y, z + 0.003), M["daisy_eye"], scale=(1, 1, 0.6), u=6, v=4)


def build_cafe_coffee_table():
    W, D, H = 1.1, 0.6, 0.42
    w = M["oak"]
    for k in range(3):
        bx("plank", (W, D / 3 - 0.006, 0.055), (0, -D / 3 + k * D / 3, H - 0.0275), w, bevel=0.012, grain="x")
    bx("apron", (W - 0.14, D - 0.12, 0.08), (0, 0, H - 0.095), M["walnut"], bevel=0.01, grain="x")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx("leg", (0.08, 0.08, H - 0.055), (sx * (W / 2 - 0.09), sy * (D / 2 - 0.08), (H - 0.055) / 2), M["walnut"], bevel=0.015)
    bx("shelf", (W - 0.22, D - 0.16, 0.03), (0, 0, 0.09), M["walnut"], bevel=0.008, grain="x")
    # two books, a jug of daisies, a cup on a saucer (the game stands a candle in the middle)
    book("plum", (-0.33, 0.04, H), 8, ribbon=True, emblem=True, s=0.9)
    book("navy", (-0.32, 0.03, H + BT * 0.9), -6, ribbon=False, emblem=False, s=0.8)
    K.lathe("jug", [(0.04, 0.0), (0.06, 0.04), (0.062, 0.08), (0.045, 0.13), (0.05, 0.15), (0.044, 0.15), (0.04, 0.13)], M["cream"], steps=20, loc=(0.3, 0.08, H))
    K.uv_box(K.torus("jug_handle", 0.03, 0.007, (0.36, 0.08, H + 0.08), M["cream"], rot=(90, 0, 0), major=12, minor=4), 4.0)
    for k in range(6):
        a = k * 1.05
        daisy(0.3 + 0.035 * math.cos(a), 0.08 + 0.035 * math.sin(a), H + 0.2 + 0.03 * math.sin(k * 2.1))
    bl("daisy_leaves", 0.05, (0.3, 0.08, H + 0.15), M["leaf_dark"], scale=(1.2, 1.2, 0.6), u=8, v=5)
    cy("saucer", 0.06, 0.05, 0.01, (0.3, -0.16, H + 0.005), M["cream"], verts=18)
    cup(0.3, -0.16, H + 0.01, 1.0)
    cy("coffee", 0.028, 0.028, 0.003, (0.3, -0.16, H + 0.053), M["beans"], verts=12)


def build_pouf():
    R, H = 0.28, 0.4
    K.lathe("pouf", [(0.0, 0.0), (R * 0.92, 0.0), (R, 0.04), (R * 1.04, H * 0.5), (R, H - 0.04), (R * 0.9, H - 0.005),
                     (R * 0.4, H + 0.01), (0.03, H - 0.02), (0.0, H - 0.02)], M["tartan"], steps=36, u_rep=4, v_rep=2)
    for z in (0.03, H - 0.035):
        K.uv_box(K.torus("piping", R * (0.98 if z < 0.1 else 0.96), 0.012, (0, 0, z), M["tartan"], major=36, minor=6), 6.0)
    bl("button", 0.022, (0, 0, H - 0.01), M["walnut"], scale=(1, 1, 0.5), u=10, v=6)


PENDANT_TOP, PENDANT_BULB = 3.48, 2.4   # the café ceiling is 3.51 up


def build_pendant_lamp():
    cy("canopy", 0.06, 0.05, 0.03, (0, 0, PENDANT_TOP - 0.015), M["enamel"], verts=14)
    cy("cord", 0.006, 0.006, PENDANT_TOP - PENDANT_BULB - 0.2, (0, 0, (PENDANT_TOP + PENDANT_BULB + 0.2) / 2), M["black"], verts=6)
    K.lathe("shade", [(0.02, PENDANT_BULB + 0.2), (0.05, PENDANT_BULB + 0.19), (0.12, PENDANT_BULB + 0.12), (0.17, PENDANT_BULB + 0.03),
                      (0.19, PENDANT_BULB - 0.04), (0.185, PENDANT_BULB - 0.045), (0.163, PENDANT_BULB + 0.025),
                      (0.115, PENDANT_BULB + 0.11), (0.045, PENDANT_BULB + 0.175), (0.018, PENDANT_BULB + 0.185)],
            M["enamel"], steps=32, sharp=60)
    cy("shade_rim", 0.192, 0.192, 0.012, (0, 0, PENDANT_BULB - 0.043), M["brass"], verts=32)
    bl("bulb", 0.05, (0, 0, PENDANT_BULB), M["bulb"], scale=(1, 1, 1.1), u=12, v=8)
    print("PENDANT_BULB %.3f" % PENDANT_BULB)


KINDS = {
    "candle": build_candle,
    "book_stack": build_book_stack,
    "cafe_counter": build_cafe_counter,
    "espresso_bar": build_espresso_bar,
    "cafe_bookshelf": build_cafe_bookshelf,
    "cafe_table": build_cafe_table,
    "cafe_coffee_table": build_cafe_coffee_table,
    "pouf": build_pouf,
    "pendant_lamp": build_pendant_lamp,
}
for _c in CLOTH:
    KINDS["book_" + _c] = (lambda c=_c: build_book(c))

BUDGET = {"cafe_bookshelf": 30000, "espresso_bar": 30000, "cafe_counter": 30000, "cafe_table": 20000}


def make(kind):
    K.reset(kind)
    materials()
    KINDS[kind]()
    out = os.path.join(HERE, kind, "out")
    K.finish(kind, out, max_tris=BUDGET.get(kind, 15000))
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(out, kind + ".glb"), os.path.join(PROPS, kind + ".glb"))
    print("COPIED", kind)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for k in (list(KINDS) if args == ["all"] else args):
    make(k)
