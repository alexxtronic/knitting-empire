"""Small, cute furnishings for her house, each in colours she can pick in Build & Buy (Alex,
2026-11-28: "Small, cute things like different kinds of lamps, different kinds of lounging chairs,
things to help people customize their house and make it their own. Everything should be able to have
a different color if they choose it. Maybe like three or four color options.")

Thirty pieces, script-built and painted in numpy like cafe_props and marcus_props:

    lamps           mushroom_lamp, paper_lantern_lamp, tripod_lamp, arc_lamp, pleated_lamp, tulip_lamp
    lounging        chaise_longue, papasan_chair, wingback_chair, egg_chair, scallop_chair, floor_lounger
    soft things     knit_pouf, cushion_pile, bunny_stool, rug_scallop, rug_checker, rug_arch
    pots and plants floor_vase, cactus_trio, fiddle_fig, plant_stand
    on the walls    wall_clock, wall_shelf, rainbow_print (hung by data/furniture.json "hang")
    the rest        arch_mirror, basket_trio, candle_stand, mushroom_table, pedestal_table

The part she recolours is its own material, named <id>_<part> (data/furniture.json "colors"
"parts"); trim, wood, brass and glass are separate materials that keep their colour. The lamps'
lights and the candle stand's candles are the game's (furniture.json "light" and "candles").

Front faces -Y here (+Z in Godot); the origin is on the floor under the middle (a hung piece's
origin is at the bottom of its back, and "hang" lifts it up the wall).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/cozy_decor/build.py -- <kind> ... | all

Writes out/<kind>/<kind>.{blend,glb} (gitignored) and copies the GLB to assets/props/. Then the
light bake (art/world_assets/light_bake/build.py -- <kind>) and import.
"""
import json
import math
import os
import shutil
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

PROPS = os.path.join(K.PROJECT, "assets", "props")
OUT = os.path.join(HERE, "out")
TEX = os.path.join(OUT, "tex")
M = {}


def C(h):
    return np.array(K.hex_rgb(h))


# --- textures ------------------------------------------------------------------------------------

def velvet_maps(name, hexcol, n=256, seed=1):
    """Velvet: a soft sheen that drifts across the pile and a very fine weave."""
    yy, xx = np.mgrid[0:n, 0:n]
    sheen = K.tile_noise(n, 2.2, seed)
    fine = 0.5 + 0.5 * np.sin(2 * np.pi * (xx + yy) / 3.0)
    rgb = C(hexcol) * (0.84 + 0.28 * sheen[..., None]) * (0.97 + 0.04 * fine[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(0.2 * fine + 0.3 * sheen, 0.8), TEX)


def knit_maps(name, hexcol, n=256, cols=8, rows=10):
    """Chunky stockinette: columns of V stitches, each stitch a pair of slanted plump loops."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = (xx / n * cols) % 1.0, (yy / n * rows) % 1.0
    left = u < 0.5
    du = np.where(left, u * 2, (1 - u) * 2)  # 0 at the stitch's edge, 1 at its middle
    slant = (v - 0.5 * du) % 1.0
    loop = np.sin(np.pi * np.clip(du, 0, 1)) ** 0.6 * np.sin(np.pi * slant) ** 0.8
    rgb = C(hexcol) * (0.55 + 0.55 * loop[..., None]) * (0.95 + 0.08 * K.tile_noise(n, 1.4, 7)[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(loop, 3.0), TEX)


def tuft_maps(name, hexcol, n=256, seed=3):
    """A tufted wool rug: soft speckled pile."""
    pile = K.tile_noise(n, 0.6, seed)
    mott = K.tile_noise(n, 1.6, seed + 1)
    rgb = C(hexcol) * (0.86 + 0.16 * pile[..., None]) * (0.92 + 0.12 * mott[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(pile, 2.0), TEX)


def checker_maps(name, a, b, n=512, checks=6, seed=5):
    """A wavy checkerboard rug in two colours, tufted."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    wu = u + 0.012 * np.sin(2 * np.pi * v * checks)
    wv = v + 0.012 * np.sin(2 * np.pi * u * checks)
    sq = (np.floor(wu * checks) + np.floor(wv * checks)) % 2
    pile = K.tile_noise(n, 0.6, seed)
    rgb = np.where(sq[..., None] == 0, C(a), C(b)) * (0.88 + 0.14 * pile[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(pile, 2.0), TEX)


def arch_maps(name, n=512):
    """A half-round rug of rainbow bands, tonal so a tint keeps them apart: u across, v up from the
    flat edge. Bands step from deep to light."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    r = np.hypot((u - 0.5) * 2, v)
    band = np.clip(np.floor(r * 5), 0, 4)
    tones = np.array([0.58, 1.0, 0.72, 0.9, 0.66])
    pile = K.tile_noise(n, 0.6, 9)
    rgb = C("#d98c6c") * tones[band.astype(int)][..., None] * (0.9 + 0.12 * pile[..., None])
    edge = np.abs((r * 5) % 1.0 - 0.5)
    hgt = pile * 0.6 + np.clip(edge * 4 - 1.6, 0, 1)
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 2.0), TEX)


def clock_face(name, n=512):
    """A cream clock face: twelve chunky dots and a little heart at twelve."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n - 0.5, 0.5 - yy / n
    rgb = np.ones((n, n, 3)) * C("#f4ead6") * (0.95 + 0.06 * K.tile_noise(n, 1.5, 11))[..., None]
    ink = np.zeros((n, n))
    for k in range(12):
        a = math.pi / 2 - k * math.tau / 12
        cx, cy = 0.38 * math.cos(a), 0.38 * math.sin(a)
        r = 0.032 if k % 3 == 0 else 0.018
        if k == 0:
            hx, hy = u - cx, v - cy + 0.012  # a heart: two lobes and a point
            heart = ((hx * hx + (hy - 0.6 * np.sqrt(np.abs(hx))) ** 2) < 0.0016)
            ink = np.maximum(ink, heart.astype(float))
        else:
            ink = np.maximum(ink, (np.hypot(u - cx, v - cy) < r).astype(float))
    rgb = rgb * (1 - ink[..., None]) + C("#c8615a") * ink[..., None]
    return K.save_image(name, rgb, TEX)


def print_art(name, n=512):
    """The framed print: a rainbow of five arches and a little sun, on a transparent-feeling mat
    (the mat itself is its own material, so it can take her colour)."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    rgb = np.ones((n, n, 3)) * C("#f3e8d4")
    r = np.hypot((u - 0.5) * 1.6, (v - 0.18) * 1.2)
    cols = ["#c8615a", "#e39a5a", "#e8c66a", "#9cb58a", "#7f9fbf"]
    for k, c in enumerate(cols):
        ring = (r > 0.62 - k * 0.1) & (r < 0.7 - k * 0.1) & (v > 0.18)
        rgb[ring] = C(c)
    sun = np.hypot(u - 0.78, v - 0.82) < 0.07
    rgb[sun] = C("#e8b04a")
    rgb = rgb * (0.95 + 0.06 * K.tile_noise(n, 1.4, 13))[..., None]
    return K.save_image(name, rgb, TEX)


def spots_maps(name, base, spot, n=512, seed=17, count=14):
    """A toadstool cap: a red (or any) glaze with soft cream spots, u round and v up the cap."""
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx / n, 1 - yy / n
    rng = np.random.default_rng(seed)
    m = np.zeros((n, n))
    for _ in range(count):
        cu, cv, r = rng.random(), rng.uniform(0.15, 0.85), rng.uniform(0.035, 0.07)
        for off in (-1, 0, 1):
            d = np.hypot((u - cu - off) * 1.6, v - cv)
            m = np.maximum(m, np.clip((r - d) / 0.01, 0, 1))
    rgb = C(base) * (0.92 + 0.1 * K.tile_noise(n, 1.4, seed)[..., None])
    rgb = rgb * (1 - m[..., None]) + C(spot) * m[..., None]
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(m * 0.5, 1.5), TEX)


def paper_maps(name, hexcol, n=256):
    """Rice paper: fibres and a faint mottle."""
    fib = K.grain_noise(n, 6.0, 1.0, 21)
    rgb = C(hexcol) * (0.93 + 0.06 * fib[..., None] + 0.04 * K.tile_noise(n, 1.6, 22)[..., None])
    return K.save_image(name, rgb, TEX)


# --- materials -----------------------------------------------------------------------------------

def _metallic(m, v):
    m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = v
    return m


def fabric(name, hexcol, rough=0.9):
    i, n = CL.cloth_maps(name, TEX, hexcol, weave_px=2)
    return K.textured(name, i, rough, normal=n, normal_strength=0.6)


def velvet(name, hexcol):
    i, n = velvet_maps(name, hexcol)
    return K.textured(name, i, 0.75, normal=n, normal_strength=0.4)


def knit(name, hexcol):
    i, n = knit_maps(name, hexcol)
    return K.textured(name, i, 0.95, normal=n, normal_strength=1.0)


def tuft(name, hexcol):
    i, n = tuft_maps(name, hexcol)
    return K.textured(name, i, 0.95, normal=n, normal_strength=0.8)


def wood(name, base, light, dark, seed):
    i, n = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=0, seed=seed, knots=0)
    return K.textured(name, i, rough=0.65, normal=n, normal_strength=0.5)


def rattan(name):
    i, n = CL.wicker_maps(name, TEX)
    return K.textured(name, i, 0.8, normal=n, normal_strength=0.9)


def glow(name, hexcol, emit=0.6):
    """A lamp's shade or paper: lit from inside (the game's furniture.gd tints the glow with it)."""
    i = paper_maps(name, hexcol)
    return K.textured(name, i, 0.8, emit=emit)


def glaze(name, hexcol, rough=0.22):
    return K.plain(name, hexcol, rough)


def shared():
    M.clear()
    M["oak"] = wood("cozy_oak", "#c08a52", "#d9a76c", "#8e5d32", 41)
    M["walnut"] = wood("cozy_walnut", "#7a4a2a", "#9a6640", "#52301a", 43)
    M["brass"] = _metallic(K.plain("cozy_brass", "#c9a04a", 0.28), 0.9)
    M["iron"] = _metallic(K.plain("cozy_iron", "#2b2a2a", 0.45), 0.6)
    M["cream"] = K.plain("cozy_cream", "#f1e8d6", 0.5)
    M["bulb"] = K.plain("cozy_bulb", "#ffe2a8", 0.3, emit=3.0)
    M["leaf"] = K.plain("cozy_leaf", "#4f8a3a", 0.7)
    M["leaf_dark"] = K.plain("cozy_leaf_dark", "#36672a", 0.7)
    M["soil"] = K.plain("cozy_soil", "#3a2a1c", 0.95)
    M["terracotta"] = K.plain("cozy_terracotta", "#c47040", 0.85)
    M["marble"] = K.plain("cozy_marble", "#e9e5de", 0.25)
    M["mirror"] = _metallic(K.plain("cozy_mirror", "#dfe6ea", 0.04), 1.0)
    M["cactus"] = K.plain("cozy_cactus", "#5f9a58", 0.7)
    M["blush"] = K.plain("cozy_blush", "#eaa3a0", 0.6)
    M["pampas"] = fabric("cozy_pampas", "#e3d3b4")
    M["rattan"] = rattan("cozy_rattan")


# --- shape helpers -------------------------------------------------------------------------------

def bx(name, size, loc, mat, bevel=0.01, rot=(0, 0, 0), grain="z", scale=2.0):
    return K.uv_box(K.box(name, size, loc, mat, bevel=bevel, seg=2, rot=rot), scale, grain=grain)


def cy(name, r1, r2, h, loc, mat, verts=20, rot=(0, 0, 0), bevel=0.0):
    return K.uv_box(K.cyl(name, r1, r2, h, loc, mat, verts=verts, rot=rot, bevel=bevel), 3.0)


def bl(name, r, loc, mat, scale=(1, 1, 1), u=16, v=10, boxy=1.0, rot=(0, 0, 0)):
    ob = K.ball(name, r, loc, mat, scale=scale, u=u, v=v, boxy=boxy)
    ob.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.view_layer.update()
    return K.uv_box(ob, 2.5)


def pipe(name, pts, r, mat, sides=10):
    return CL.tube(name, [Vector(p) for p in pts], [r] * len(pts), mat, sides=sides)


def leg(x, y, h, mat, r=0.022, splay=(0, 0), top=None):
    """A tapered leg from the floor at (x, y) up to height h, leaning out by splay (dx, dy) at the foot."""
    foot = Vector((x + splay[0], y + splay[1], 0.0))
    head = Vector((x, y, h)) if top is None else Vector(top)
    d = head - foot
    ob = cy("leg", r * 0.7, r, d.length, (foot + head) / 2, mat, verts=10)
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    bpy.context.view_layer.update()
    return ob


def pleated(name, r0, r1, z0, z1, mat, pleats=24, depth=0.06, rings=6):
    """A pleated lampshade: a cone from radius r0 at z0 to r1 at z1, folded in and out, open at both
    ends, two-sided (an inner wall) so it reads from below."""
    seg = pleats * 2
    verts, faces, uvs = [], [], []
    for side, k in ((0, 1.0), (1, 0.985)):
        base = len(verts)
        for j in range(rings + 1):
            t = j / rings
            z = z0 + (z1 - z0) * t
            r = (r0 + (r1 - r0) * t) * k
            for i in range(seg):
                a = math.tau * i / seg
                rr = r * (1 + depth * (1 if i % 2 == 0 else -1))
                verts.append(Vector((rr * math.cos(a), rr * math.sin(a), z)))
        for j in range(rings):
            for i in range(seg):
                a, b = base + j * seg + i, base + j * seg + (i + 1) % seg
                c, d = b + seg, a + seg
                f = (a, b, c, d) if side == 0 else (a, d, c, b)
                faces.append(f)
                uvs += [(i / seg * 4, j / rings), ((i + 1) / seg * 4, j / rings), ((i + 1) / seg * 4, (j + 1) / rings), (i / seg * 4, (j + 1) / rings)]
        if side == 1:
            uvs[-rings * seg * 4:] = [uvs[q] for q in range(len(uvs) - rings * seg * 4, len(uvs))]
    ob = CL._finish_mesh(name, verts, faces, uvs, mat, recalc=False, smooth=False)
    return ob


def shell(name, profile, mat, steps=32, u_rep=2.0, v_rep=1.0, inner=0.012):
    """A lathe with a thin wall: the profile out, then back in `inner` metres, so open shades and
    bowls have an inside."""
    back = [(max(0.0, r - inner), z) for r, z in reversed(profile)]
    return K.lathe(name, list(profile) + back, mat, steps=steps, u_rep=u_rep, v_rep=v_rep)


def potted(x, y, z, r, h, mat, plant=None):
    """A pot of radius r and height h standing at (x, y, z), its soil, and what grows in it."""
    K.lathe("pot", [(r * 0.72, 0), (r * 0.8, h * 0.05), (r, h * 0.9), (r * 1.06, h * 0.92), (r * 1.06, h), (r * 0.93, h), (r * 0.9, h * 0.8)],
            mat, steps=24, loc=(x, y, z))
    K.disc("soil", r * 0.9, z + h * 0.82, M["soil"], steps=18).location.x += x
    bpy.context.view_layer.objects[-1].location.y += y if False else 0
    return z + h * 0.82


def disc_at(name, r, x, y, z, mat, steps=20):
    ob = K.disc(name, r, z, mat, steps=steps)
    ob.location = (x, y, 0)
    return ob


# --- lamps ---------------------------------------------------------------------------------------

def build_mushroom_lamp():
    """A toadstool floor lamp: a cream stem flaring at the foot and a spotted cap that glows."""
    cap = spots_maps("mushroom_lamp_cap", "#d4554a", "#f6ecd8")
    M["cap"] = K.textured("mushroom_lamp_cap", cap[0], 0.45, emit=0.35, normal=cap[1], normal_strength=0.6)
    K.lathe("stem", [(0.16, 0.0), (0.17, 0.02), (0.12, 0.06), (0.085, 0.16), (0.075, 0.35), (0.08, 0.5), (0.0, 0.5)], M["cream"], steps=28)
    K.lathe("cap", [(0.0, 0.46), (0.3, 0.46), (0.33, 0.48), (0.32, 0.53), (0.27, 0.62), (0.18, 0.7), (0.08, 0.74), (0.0, 0.75)], M["cap"], steps=40)
    K.lathe("gills", [(0.29, 0.462), (0.08, 0.5), (0.0, 0.5)], M["cream"], steps=40)


def build_paper_lantern_lamp():
    """A round paper lantern on a three-legged oak stand."""
    M["paper"] = glow("paper_lantern_lamp_paper", "#f3e6cc", 0.7)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        leg(0.04 * math.cos(a), 0.04 * math.sin(a), 0.95, M["oak"], r=0.016, splay=(0.26 * math.cos(a), 0.26 * math.sin(a)))
    cy("collar", 0.05, 0.05, 0.04, (0, 0, 0.96), M["oak"], verts=14)
    R, zc = 0.24, 1.22
    prof = []
    for i in range(17):
        ph = -math.pi / 2 + math.pi * i / 16
        prof.append((max(0.0, R * math.cos(ph)), zc + R * 0.95 * math.sin(ph)))
    ob = K.lathe("lantern", prof, M["paper"], steps=36, u_rep=3)
    for v in ob.data.vertices:  # the wire ribs pull the paper in, ring by ring
        c = v.co
        f = 1 - 0.035 * (0.5 + 0.5 * math.cos((c.z - zc) / R * math.pi * 6))
        v.co = Vector((c.x * f, c.y * f, c.z))
    for z in (zc - R * 0.95, zc + R * 0.95):
        cy("ring", 0.06, 0.06, 0.012, (0, 0, z), M["iron"], verts=14)


def build_tripod_lamp():
    """A tall tripod lamp in oak with a drum shade."""
    M["shade"] = glow("tripod_lamp_shade", "#efe3cc", 0.5)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        leg(0.03 * math.cos(a), 0.03 * math.sin(a), 1.3, M["oak"], r=0.018, splay=(0.3 * math.cos(a), 0.3 * math.sin(a)))
    cy("hub", 0.035, 0.035, 0.06, (0, 0, 1.3), M["brass"], verts=12)
    cy("socket", 0.02, 0.02, 0.08, (0, 0, 1.37), M["brass"], verts=10)
    bl("bulb", 0.04, (0, 0, 1.44), M["bulb"], u=10, v=8)
    shell("shade", [(0.23, 1.3), (0.23, 1.58)], M["shade"], steps=40, inner=0.006)
    K.uv_box(K.torus("rim", 0.23, 0.006, (0, 0, 1.3), M["brass"], major=40, minor=4), 3)
    K.uv_box(K.torus("rim", 0.23, 0.006, (0, 0, 1.58), M["brass"], major=40, minor=4), 3)


def build_arc_lamp():
    """A brass arc lamp on a round marble foot, its dome shade hanging out over a chair."""
    M["dome"] = glaze("arc_lamp_dome", "#ece8df", 0.3)
    cy("foot", 0.2, 0.2, 0.06, (0, 0.0, 0.03), M["marble"], verts=32, bevel=0.012)
    pts = [Vector(p) for p in CL.bezier(Vector((0, 0, 0.05)), Vector((0, 0, 1.7)), Vector((0, -0.6, 2.05)), Vector((0, -0.95, 1.6)), n=28)]
    pipe("arc", pts, 0.014, M["brass"])
    top = pts[-1]
    shell("dome", [(0.24, top.z - 0.17), (0.22, top.z - 0.1), (0.16, top.z - 0.03), (0.05, top.z + 0.01), (0.02, top.z + 0.02)], M["dome"], steps=36)
    for o in [o for o in K.COLL.objects if o.name.startswith("dome")]:
        o.location.y = top.y
    bl("bulb", 0.045, (0, top.y, top.z - 0.1), M["bulb"], u=10, v=8)


def build_pleated_lamp():
    """A slim brass floor lamp with a pleated shade."""
    M["shade"] = glow("pleated_lamp_shade", "#e9b9b2", 0.5)
    cy("foot", 0.15, 0.16, 0.025, (0, 0, 0.0125), M["brass"], verts=28)
    cy("post", 0.012, 0.012, 1.3, (0, 0, 0.67), M["brass"], verts=10)
    bl("knob", 0.02, (0, 0, 0.7), M["brass"], u=10, v=6)
    bl("bulb", 0.04, (0, 0, 1.34), M["bulb"], u=10, v=8)
    pleated("shade", 0.22, 0.12, 1.22, 1.5, M["shade"])


def build_tulip_lamp():
    """A brass lamp of three glass bells hanging from curving stems, like a sprig of lily of the
    valley, on a round foot."""
    M["tulip"] = glaze("tulip_lamp_glass", "#f1c9b8", 0.2)
    bsdf = M["tulip"].node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = bsdf.inputs["Base Color"].default_value
    bsdf.inputs["Emission Strength"].default_value = 0.6
    cy("foot", 0.17, 0.18, 0.03, (0, 0, 0.015), M["brass"], verts=28)
    pipe("stem", CL.bezier(Vector((0, 0, 0.03)), Vector((0, 0, 0.6)), Vector((0.02, 0, 1.0)), Vector((0, 0, 1.3)), n=16), 0.011, M["brass"])
    for k, (a, h, out) in enumerate(((20, 1.25, 0.26), (160, 1.05, 0.24), (270, 0.85, 0.22))):
        ar = math.radians(a)
        d = Vector((math.cos(ar), math.sin(ar), 0))
        root = Vector((0, 0, h))
        tip = d * out + Vector((0, 0, h - 0.06))
        pipe("twig", CL.bezier(root, root + Vector((0, 0, 0.12)), d * out + Vector((0, 0, h + 0.1)), tip, n=12), 0.007, M["brass"], sides=8)
        z = tip.z
        bell = shell("bell", [(0.085, z - 0.17), (0.07, z - 0.14), (0.065, z - 0.08), (0.05, z - 0.03), (0.02, z), (0.0, z + 0.004)], M["tulip"], steps=24, inner=0.004)
        for v in bell.data.vertices:  # the rim scallops into five petals
            phi = math.atan2(v.co.y, v.co.x)
            low = max(0.0, (z - 0.12 - v.co.z) / 0.05)
            v.co.z -= 0.02 * low * abs(math.cos(2.5 * phi))
        bell.location = (tip.x, tip.y, 0)
        bl("bulb", 0.028, (tip.x, tip.y, z - 0.09), M["bulb"], u=8, v=6)


# --- lounging ------------------------------------------------------------------------------------

def build_chaise_longue():
    """A velvet chaise longue: a long buttoned seat on turned oak legs, a curled back at the head
    and a bolster."""
    M["v"] = velvet("chaise_longue_velvet", "#2f6e6a")
    L, W = 1.6, 0.62
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.lathe("leg", [(0.028, 0), (0.02, 0.06), (0.03, 0.12), (0.025, 0.18), (0.0, 0.18)], M["walnut"], steps=12,
                    loc=(sx * (L / 2 - 0.08), sy * (W / 2 - 0.07), 0))
    bx("base", (L, W, 0.14), (0, 0, 0.24), M["v"], bevel=0.04)
    bx("seat", (L - 0.06, W - 0.04, 0.1), (0, 0, 0.35), M["v"], bevel=0.045)
    for k in range(5):
        bl("button", 0.012, (-0.55 + k * 0.26, 0, 0.4), M["v"], scale=(1, 1, 0.6), u=8, v=6)
    # the back rises at the head (x < 0), curling over at its top
    pts = CL.bezier(Vector((-L / 2 + 0.06, 0, 0.3)), Vector((-L / 2 - 0.02, 0, 0.6)), Vector((-L / 2 + 0.05, 0, 0.82)), Vector((-L / 2 - 0.08, 0, 0.86)), n=12)
    for k, p in enumerate(pts):
        bx("back", (0.14, W, 0.08), tuple(p), M["v"], bevel=0.035)
    cy("bolster", 0.09, 0.09, W - 0.06, (-L / 2 + 0.2, 0, 0.48), M["v"], verts=20, rot=(90, 0, 0), bevel=0.03)
    for sy in (-1, 1):
        bl("bolster_end", 0.03, (-L / 2 + 0.2, sy * (W / 2 - 0.02), 0.48), M["walnut"], scale=(1, 0.5, 1), u=10, v=6)


def build_papasan_chair():
    """A papasan: a deep rattan bowl on a rattan drum, a round plump cushion in it."""
    M["cushion"] = velvet("papasan_chair_cushion", "#c99a2e")
    K.lathe("drum", [(0.3, 0.0), (0.32, 0.02), (0.26, 0.2), (0.3, 0.32), (0.0, 0.32)], M["rattan"], steps=32, u_rep=6, v_rep=2)
    before = set(K.COLL.objects)
    # the bowl, its rim and the cushion, built round the drum's top and then tipped back toward her
    shell("bowl", [(0.0, 0.0), (0.34, 0.03), (0.55, 0.12), (0.66, 0.26), (0.68, 0.38)], M["rattan"], steps=40, u_rep=8, v_rep=2, inner=0.03)
    K.uv_box(K.torus("rim", 0.67, 0.032, (0, 0, 0.38), M["rattan"], major=40, minor=8), 4)
    bl("cushion", 0.56, (0, 0, 0.17), M["cushion"], scale=(1, 1, 0.24), u=28, v=12, boxy=0.8)
    for k in range(6):
        a = k * math.tau / 6
        bl("tuft", 0.018, (0.26 * math.cos(a), 0.26 * math.sin(a), 0.29), M["cushion"], scale=(1, 1, 0.5), u=8, v=6)
    bl("tuft", 0.02, (0, 0, 0.305), M["cushion"], scale=(1, 1, 0.5), u=8, v=6)
    T = Matrix.Translation(Vector((0, 0.04, 0.3))) @ Matrix.Rotation(math.radians(18), 4, "X")
    for o in [o for o in K.COLL.objects if o not in before]:
        o.matrix_world = T @ o.matrix_world
    bpy.context.view_layer.update()


def build_wingback_chair():
    """A wingback armchair: a tall back with wings, rolled arms, a box cushion and short walnut legs."""
    M["v"] = velvet("wingback_chair_velvet", "#b5562f")
    W, D = 0.82, 0.8
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.lathe("leg", [(0.03, 0), (0.024, 0.08), (0.03, 0.14), (0.0, 0.14)], M["walnut"], steps=12, loc=(sx * (W / 2 - 0.07), sy * (D / 2 - 0.07), 0))
    bx("base", (W, D, 0.2), (0, 0, 0.24), M["v"], bevel=0.03)
    bx("cushion", (W - 0.2, D - 0.12, 0.12), (0, -0.04, 0.4), M["v"], bevel=0.05)
    # the back, rounded over the top
    bx("back", (W - 0.04, 0.16, 0.8), (0, D / 2 - 0.08, 0.66), M["v"], bevel=0.05)
    cy("back_top", 0.08, 0.08, W - 0.06, (0, D / 2 - 0.08, 1.06), M["v"], verts=18, rot=(0, 90, 0))
    for sx in (-1, 1):
        # wings: a panel that flares out and forward from the back, and the rolled arm below it
        bx("wing", (0.1, 0.36, 0.42), (sx * (W / 2 - 0.05), D / 2 - 0.26, 0.86), M["v"], bevel=0.04, rot=(0, 0, sx * 12))
        bx("arm", (0.12, D - 0.1, 0.24), (sx * (W / 2 - 0.06), -0.02, 0.44), M["v"], bevel=0.04)
        cy("roll", 0.075, 0.075, D - 0.12, (sx * (W / 2 - 0.04), -0.04, 0.58), M["v"], verts=18, rot=(90, 0, 0))
        disc_at("roll_end", 0.07, sx * (W / 2 - 0.04), 0, 0, M["v"]).rotation_euler = (math.radians(90), 0, 0)
    for o in [o for o in K.COLL.objects if o.name.startswith("roll_end")]:
        o.location = (o.location.x, -0.04 - (D - 0.12) / 2 - 0.001, 0.58)


def build_egg_chair():
    """A hanging rattan egg on a black arched stand, a fat cushion inside."""
    M["cushion"] = velvet("egg_chair_cushion", "#e9e0cf")
    cy("base", 0.32, 0.34, 0.05, (0, 0.05, 0.025), M["iron"], verts=32, bevel=0.015)
    pts = CL.bezier(Vector((0, 0.3, 0.05)), Vector((0, 0.42, 1.2)), Vector((0, 0.25, 2.0)), Vector((0, -0.02, 1.95)), n=24)
    pipe("stand", pts, 0.025, M["iron"])
    pipe("chain", [(0, -0.02, 1.95), (0, -0.02, 1.68)], 0.008, M["iron"], sides=6)
    zc, R = 1.05, 0.42
    prof = []
    for i in range(21):
        ph = -math.pi / 2 + math.pi * i / 20
        r = R * math.cos(ph) * (1 + 0.1 * math.sin(ph))
        prof.append((max(0.0, r), zc + 0.62 * math.sin(ph)))
    egg = shell("egg", prof, M["rattan"], steps=40, u_rep=8, v_rep=4, inner=0.03)
    # cut the opening: faces in front (-y) between the seat and the brow
    bm = bmesh.new()
    bm.from_mesh(egg.data)
    gone = [f for f in bm.faces if f.calc_center_median().y < -0.05 and 0.78 < f.calc_center_median().z < 1.55]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(egg.data)
    bm.free()
    egg.location.y = -0.02
    K.uv_box(K.torus("lip", 0.36, 0.025, (0, -0.24, 1.15), M["rattan"], rot=(68, 0, 0), major=36, minor=8), 4)
    bl("cushion", 0.32, (0, 0.0, 0.84), M["cushion"], scale=(1, 0.95, 0.35), u=24, v=10, boxy=0.8)
    bl("back_cushion", 0.28, (0, 0.2, 1.1), M["cushion"], scale=(1, 0.35, 1.0), u=24, v=10, boxy=0.8)


def build_scallop_chair():
    """A shell chair: a scalloped back of five plump velvet channels on a seat, on brass legs."""
    M["v"] = velvet("scallop_chair_velvet", "#6d4a6e")
    for sx in (-1, 1):
        for sy in (-1, 1):
            leg(sx * 0.24, sy * 0.22, 0.2, M["brass"], r=0.014, splay=(sx * 0.03, sy * 0.03))
    bl("seat", 0.36, (0, -0.02, 0.3), M["v"], scale=(1, 0.95, 0.3), u=28, v=10, boxy=0.75)
    for k in range(5):
        a = math.radians(-60 + 30 * k)
        x, y = 0.3 * math.sin(a), 0.22 - 0.1 * (1 - math.cos(a))
        bl("channel", 0.12, (x, y + 0.04, 0.62), M["v"], scale=(0.85, 0.6, 2.6), u=16, v=12, rot=(-10, 0, -math.degrees(a)))
    K.uv_box(K.torus("trim", 0.36, 0.006, (0, -0.02, 0.21), M["brass"], major=36, minor=4), 3)


def build_floor_lounger():
    """A folding floor chair: a thick tufted seat pad on the floor and a tufted backrest leaning
    back from it, with a strap down each side."""
    M["c"] = fabric("floor_lounger_cover", "#a9be98")
    bl("pad", 0.4, (0, -0.12, 0.1), M["c"], scale=(1.2, 1.15, 0.24), u=28, v=12, boxy=0.55)
    bl("back", 0.4, (0, 0.33, 0.38), M["c"], scale=(1.2, 0.24, 1.05), u=28, v=12, boxy=0.55, rot=(-28, 0, 0))
    bl("roll", 0.09, (0, 0.47, 0.74), M["c"], scale=(5.0, 1, 1), u=20, v=10, rot=(-28, 0, 0))
    for x in (-0.16, 0.16):
        for y, z in ((-0.26, 0.2), (0.02, 0.2)):
            bl("tuft", 0.018, (x, y, z), M["c"], scale=(1, 1, 0.5), u=8, v=6)
        for z in (0.3, 0.55):
            bl("tuft", 0.018, (x, 0.33 - 0.09 * (z - 0.38) / 0.4 - 0.1, z), M["c"], scale=(1, 0.5, 1), u=8, v=6)
    for sx in (-1, 1):
        bx("strap", (0.02, 0.05, 0.5), (sx * 0.49, 0.26, 0.3), M["walnut"], bevel=0.005, rot=(-28, 0, 0))


# --- soft things ---------------------------------------------------------------------------------

def build_knit_pouf():
    """A chunky hand-knit pouf, round and squashy."""
    M["k"] = knit("knit_pouf_knit", "#d8cdb8")
    R, H = 0.3, 0.36
    K.lathe("pouf", [(0.0, 0.0), (R * 0.9, 0.0), (R, 0.05), (R * 1.05, H * 0.5), (R, H - 0.05), (R * 0.88, H - 0.005),
                     (R * 0.4, H + 0.01), (0.0, H)], M["k"], steps=40, u_rep=6, v_rep=2)


def build_cushion_pile():
    """Three floor cushions stacked a little askew, a striped one in the middle."""
    M["c"] = fabric("cushion_pile_cover", "#e8a9a6")
    s = CL.stripes_maps("cushion_pile_stripe", TEX, a="#c8b89a", b="#f2e8d4", stripes=10)
    M["s"] = K.textured("cushion_pile_stripe", s[0], 0.9, normal=s[1], normal_strength=0.5)
    for k, (z, turn, mat) in enumerate(((0.07, 0, "c"), (0.2, 14, "s"), (0.32, -9, "c"))):
        bl("cushion", 0.32, (0.02 * k, -0.01 * k, z), M[mat], scale=(1, 1, 0.2), u=20, v=10, boxy=0.55, rot=(0, 0, turn))
        for c in range(4):
            a = math.radians(turn + 45 + 90 * c)
            bl("corner", 0.03, (0.02 * k + 0.4 * math.cos(a), -0.01 * k + 0.4 * math.sin(a), z), M[mat], scale=(1, 1, 0.6), u=8, v=6)
    bl("button", 0.02, (0.04, -0.02, 0.385), M["cream"], scale=(1, 1, 0.5), u=8, v=6)


def build_bunny_stool():
    """A little round stool with a plush seat that has two bunny ears at the back."""
    M["c"] = fabric("bunny_stool_plush", "#f2ead8")
    for k in range(3):
        a = math.radians(90 + 120 * k)
        leg(0.13 * math.cos(a), 0.13 * math.sin(a), 0.28, M["oak"], r=0.018, splay=(0.04 * math.cos(a), 0.04 * math.sin(a)))
    cy("seat_base", 0.2, 0.2, 0.04, (0, 0, 0.29), M["oak"], verts=28, bevel=0.01)
    bl("seat", 0.21, (0, 0, 0.35), M["c"], scale=(1, 1, 0.38), u=24, v=10)
    for sx in (-1, 1):
        bl("ear", 0.06, (sx * 0.07, 0.12, 0.55), M["c"], scale=(0.6, 0.35, 2.2), u=12, v=10, rot=(-12, sx * 12, 0))
        bl("ear_in", 0.04, (sx * 0.07, 0.1, 0.56), M["blush"], scale=(0.55, 0.2, 2.1), u=10, v=8, rot=(-12, sx * 12, 0))
    bl("tail", 0.05, (0, 0.2, 0.34), M["c"], u=10, v=8)


def flat_shape(name, outline, z, mat, uv_rect):
    """A flat rug: the outline (xy points, anticlockwise) filled, a thin edge round it, UVs over uv_rect."""
    n = len(outline)
    verts = [Vector((x, y, z)) for x, y in outline] + [Vector((x, y, 0.0)) for x, y in outline]
    cx = sum(p[0] for p in outline) / n
    cyy = sum(p[1] for p in outline) / n
    verts.append(Vector((cx, cyy, z)))
    faces, uvs = [], []
    x0, y0, x1, y1 = uv_rect
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * n, i, j))
        for q in (verts[2 * n], verts[i], verts[j]):
            uvs.append(((q.x - x0) / (x1 - x0), (q.y - y0) / (y1 - y0)))
        faces.append((i, i + n, j + n, j))
        uvs += [(i / n * 8, 1), (i / n * 8, 0.98), ((i + 1) / n * 8, 0.98), ((i + 1) / n * 8, 1)]
    return CL._finish_mesh(name, verts, faces, uvs, mat)


def build_rug_scallop():
    """A round tufted rug with a scalloped edge."""
    M["t"] = tuft("rug_scallop_wool", "#a9c4e0")
    R = 0.8
    pts = []
    for i in range(144):
        a = math.tau * i / 144
        r = R * (1 + 0.045 * abs(math.cos(a * 9))) - 0.045 * R
        pts.append((r * math.cos(a), r * math.sin(a)))
    flat_shape("rug", pts, 0.015, M["t"], (-R, -R, R, R))
    inner = [(0.78 * x, 0.78 * y) for x, y in pts]
    M["edge"] = tuft("rug_scallop_border", "#f2ead8")
    ob = flat_shape("rug_border", inner, 0.017, M["edge"], (-R, -R, R, R))
    ob.scale = (1, 1, 1)
    flat_shape("rug_inner", [(0.72 * x, 0.72 * y) for x, y in pts], 0.019, M["t"], (-R, -R, R, R))


def build_rug_checker():
    """A wavy checkerboard rug with tassels at both ends."""
    i, n = checker_maps("rug_checker_wool", "#f2ead8", "#c99a2e")
    M["t"] = K.textured("rug_checker_wool", i, 0.95, normal=n, normal_strength=0.8)
    W, D = 1.6, 1.1
    flat_shape("rug", [(-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)], 0.015, M["t"], (-W / 2, -D / 2, W / 2, D / 2))
    for sx in (-1, 1):
        for k in range(14):
            y = -D / 2 + 0.05 + k * (D - 0.1) / 13
            cy("tassel", 0.006, 0.006, 0.07, (sx * (W / 2 + 0.03), y, 0.006), M["cream"], verts=5, rot=(0, 90, 0))


def build_rug_arch():
    """A half-round rainbow rug: bands of one colour from deep to light."""
    i, n = arch_maps("rug_arch_wool")
    M["t"] = K.textured("rug_arch_wool", i, 0.95, normal=n, normal_strength=0.8)
    R = 0.85
    pts = [(R * math.cos(math.pi * i / 64), R * math.sin(math.pi * i / 64) - R / 2) for i in range(65)]
    flat_shape("rug", pts, 0.015, M["t"], (-R, -R / 2, R, R * 1.5))


# --- pots and plants -----------------------------------------------------------------------------

def build_floor_vase():
    """A tall glazed floor vase with a few stems of pampas grass."""
    M["g"] = glaze("floor_vase_glaze", "#c46a43")
    K.lathe("vase", [(0.08, 0.0), (0.12, 0.03), (0.17, 0.18), (0.16, 0.36), (0.07, 0.56), (0.06, 0.66), (0.085, 0.7), (0.07, 0.7), (0.05, 0.6)],
            M["g"], steps=32)
    for k in range(5):
        a = k * 1.3
        lean = Vector((0.18 * math.cos(a), 0.18 * math.sin(a), 0))
        top = Vector((0, 0, 1.25 + 0.12 * math.sin(k * 2.3))) + lean
        pts = CL.bezier(Vector((0, 0, 0.5)), Vector((0, 0, 0.9)), top * 0.8 + Vector((0, 0, 0.15)), top, n=10)
        pipe("stem", pts, 0.005, M["pampas"], sides=5)
        d = (pts[-1] - pts[-3]).normalized()
        plume = bl("plume", 0.06, tuple(top + d * 0.12), M["pampas"], scale=(0.6, 0.6, 2.6), u=10, v=10)
        plume.rotation_euler = d.to_track_quat("Z", "Y").to_euler()


def build_cactus_trio():
    """Three glazed pots, a tall cactus with arms, a round one and a little bunny-ear one."""
    M["g"] = glaze("cactus_trio_glaze", "#9cc0a6")
    for k, (x, y, r, h) in enumerate(((-0.17, 0.04, 0.1, 0.18), (0.08, -0.06, 0.08, 0.14), (0.24, 0.08, 0.065, 0.12))):
        K.lathe("pot", [(r * 0.75, 0), (r * 0.82, 0.01), (r, h), (r * 1.08, h), (r * 1.08, h + 0.02), (r * 0.92, h + 0.02), (r * 0.9, h * 0.85)],
                M["g"], steps=24, loc=(x, y, 0))
        disc_at("soil", r * 0.9, x, y, h * 0.85 + 0.005, M["soil"])
        z = h * 0.85
        if k == 0:
            CL.ribbed("cactus", 0.06, 0.42, M["cactus"], ribs=8, depth=0.12, dimple=0.02, loc=(x, y, z))
            for sx, hz in ((-1, 0.2), (1, 0.28)):
                pipe("arm", [(x, y, z + hz), (x + sx * 0.08, y, z + hz), (x + sx * 0.09, y, z + hz + 0.1)], 0.028, M["cactus"])
                bl("arm_tip", 0.028, (x + sx * 0.09, y, z + hz + 0.1), M["cactus"], u=10, v=6)
            bl("flower", 0.022, (x, y, z + 0.42), M["blush"], scale=(1, 1, 0.6), u=10, v=6)
        elif k == 1:
            CL.ribbed("cactus", 0.07, 0.12, M["cactus"], ribs=10, depth=0.14, dimple=0.08, loc=(x, y, z))
        else:
            bl("pad", 0.05, (x, y, z + 0.06), M["cactus"], scale=(1, 0.35, 1.2), u=12, v=8)
            for sx in (-1, 1):
                bl("ear", 0.035, (x + sx * 0.04, y, z + 0.14), M["cactus"], scale=(1, 0.35, 1.3), u=10, v=8, rot=(0, sx * 25, 0))


def build_fiddle_fig():
    """A fiddle-leaf fig in a glazed pot: a slim trunk and big wavy leaves."""
    M["g"] = glaze("fiddle_fig_pot", "#ece3cf")
    K.lathe("pot", [(0.15, 0), (0.17, 0.02), (0.2, 0.32), (0.21, 0.34), (0.19, 0.34), (0.18, 0.28)], M["g"], steps=32)
    disc_at("soil", 0.18, 0, 0, 0.3, M["soil"])
    trunk = CL.bezier(Vector((0, 0, 0.3)), Vector((0.02, 0, 0.8)), Vector((-0.03, 0.02, 1.2)), Vector((0, 0, 1.55)), n=14)
    pipe("trunk", trunk, 0.018, M["walnut"], sides=8)
    rng = np.random.default_rng(3)
    for k in range(17):
        t = 0.35 + 0.65 * k / 16
        p = trunk[min(len(trunk) - 1, int(t * (len(trunk) - 1)))]
        yaw = k * 137.5
        out = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0))
        s = 0.9 + 0.3 * rng.random()
        c = p + out * 0.12 * s + Vector((0, 0, 0.04))
        lf = bl("leaf", 0.1 * s, tuple(c), M["leaf"] if k % 3 else M["leaf_dark"], scale=(1.0, 0.12, 1.35), u=12, v=10)
        lf.rotation_euler = (math.radians(rng.uniform(25, 50)), 0, math.radians(yaw + 90))
        for v in lf.data.vertices:  # fiddle shape: a waist below the middle
            w = 1 - 0.25 * math.exp(-((v.co.z / (0.1 * s * 1.35) + 0.25) ** 2) * 6)
            v.co.x *= w


def build_plant_stand():
    """A painted three-step plant stand with three pots on it."""
    M["p"] = glaze("plant_stand_paint", "#ece8df", 0.5)
    for sx in (-1, 1):
        leg(sx * 0.36, 0.12, 0.9, M["p"], r=0.02, splay=(0, 0.06))
        leg(sx * 0.36, -0.12, 0.3, M["p"], r=0.02, splay=(0, -0.15), top=(sx * 0.36, 0.08, 0.95))
    for k, (y, z) in enumerate(((-0.17, 0.3), (-0.02, 0.6), (0.12, 0.9))):
        bx("step", (0.78, 0.18, 0.025), (0, y, z), M["p"], bevel=0.006, grain="x")
    potted(-0.18, -0.17, 0.3125, 0.07, 0.11, M["terracotta"])
    bl("fern", 0.11, (-0.18, -0.17, 0.46), M["leaf"], scale=(1.2, 1.2, 0.6), u=12, v=8)
    potted(0.16, -0.02, 0.6125, 0.065, 0.1, M["terracotta"])
    bl("succulent", 0.06, (0.16, -0.02, 0.72), M["cactus"], scale=(1, 1, 0.6), u=12, v=8)
    potted(-0.05, 0.12, 0.9125, 0.06, 0.09, M["terracotta"])
    for k in range(5):  # a trailing pothos: a few strands spilling over the edge
        a = k * 1.25
        pts = [Vector((-0.05 + 0.04 * math.cos(a), 0.12 + 0.04 * math.sin(a), 1.0)),
               Vector((-0.05 + 0.1 * math.cos(a), 0.12 - 0.08, 0.95)), Vector((-0.05 + 0.14 * math.cos(a), 0.0, 0.8 - 0.05 * k))]
        pipe("vine", pts, 0.004, M["leaf_dark"], sides=4)
        for p in pts[1:]:
            bl("vine_leaf", 0.022, tuple(p), M["leaf"], scale=(1, 0.3, 1.2), u=8, v=6)


# --- on the walls (origin at the bottom of the back; "hang" lifts them) --------------------------

def build_wall_clock():
    """A round wall clock: a painted wooden case, a cream face with dots and a heart, brass hands."""
    M["case"] = glaze("wall_clock_case", "#a8d4c0", 0.45)
    M["face"] = K.textured("wall_clock_face", clock_face("wall_clock_face"), 0.6)
    R, D = 0.2, 0.06
    cy("case", R, R, D, (0, -D / 2, R), M["case"], verts=40, rot=(90, 0, 0), bevel=0.012)
    face = K.disc("face", R * 0.86, 0, M["face"], steps=40)
    face.rotation_euler = (math.radians(90), 0, 0)
    face.location = (0, -D - 0.001, R)
    bx("hour", (0.012, 0.004, 0.1), (0.03, -D - 0.006, R + 0.035), M["brass"], bevel=0.002, rot=(0, -45, 0))
    bx("minute", (0.009, 0.004, 0.15), (-0.04, -D - 0.009, R + 0.055), M["brass"], bevel=0.002, rot=(0, 35, 0))
    cy("pin", 0.012, 0.012, 0.012, (0, -D - 0.008, R), M["brass"], verts=12, rot=(90, 0, 0))


def build_wall_shelf():
    """A painted floating shelf with brackets, two little pots and a few books."""
    M["p"] = glaze("wall_shelf_paint", "#e98a76", 0.5)
    bx("shelf", (0.7, 0.18, 0.03), (0, -0.09, 0.12), M["p"], bevel=0.006, grain="x")
    for sx in (-1, 1):
        bx("bracket", (0.02, 0.15, 0.1), (sx * 0.26, -0.075, 0.055), M["p"], bevel=0.004)
    potted(-0.2, -0.09, 0.135, 0.045, 0.07, M["terracotta"])
    bl("succulent", 0.04, (-0.2, -0.09, 0.22), M["cactus"], scale=(1, 1, 0.7), u=10, v=8)
    potted(0.22, -0.09, 0.135, 0.04, 0.08, M["cream"])
    bl("sprig", 0.035, (0.22, -0.09, 0.25), M["leaf"], scale=(0.8, 0.8, 1.4), u=10, v=8)
    for k, (c, h) in enumerate((("#6d4a6e", 0.17), ("#3f5f9e", 0.15), ("#c99a2e", 0.16))):
        bx("book", (0.035, 0.13, h), (-0.03 + k * 0.04, -0.09, 0.135 + h / 2), K.plain("wall_shelf_book_%d" % k, c, 0.8), bevel=0.004)


def build_rainbow_print():
    """A framed rainbow print on a coloured mat."""
    M["mat"] = glaze("rainbow_print_mat", "#e8a9a6", 0.8)
    M["art"] = K.textured("rainbow_print_art", print_art("rainbow_print_art"), 0.8)
    W, H, D = 0.5, 0.62, 0.03
    for (sx, sz, x, z) in ((W, 0.03, 0, 0.015), (W, 0.03, 0, H - 0.015), (0.03, H, -W / 2 + 0.015, H / 2), (0.03, H, W / 2 - 0.015, H / 2)):
        bx("frame", (sx, D, sz), (x, -D / 2, z), M["oak"], bevel=0.004)
    bx("mount", (W - 0.06, 0.008, H - 0.06), (0, -D * 0.6, H / 2), M["mat"], bevel=0.0)
    art = K.disc("art", 1.0, 0, M["art"], steps=4, turn=math.pi / 4)
    art.scale = ((W - 0.16) / math.sqrt(2), (H - 0.2) / math.sqrt(2), 1)
    art.rotation_euler = (math.radians(90), 0, 0)
    art.location = (0, -D * 0.6 - 0.005, H / 2)


# --- the rest ------------------------------------------------------------------------------------

def build_arch_mirror():
    """A tall arched floor mirror in a painted frame, leaning back a little."""
    M["f"] = glaze("arch_mirror_frame", "#2c2a28", 0.45)
    W, H, T = 0.62, 1.7, 0.05
    outer = [(-W / 2, 0)] + [((W / 2) * math.cos(math.pi - math.pi * i / 24), H - W / 2 + (W / 2) * math.sin(math.pi - math.pi * i / 24)) for i in range(25)] + [(W / 2, 0)]
    # the frame: a swept tube round the arch and along the foot
    path = [Vector((x, 0, z)) for x, z in outer] + [Vector((-W / 2, 0, 0))]
    CL.tube("frame", path, [T] * len(path), M["f"], sides=8, caps=False, flat=0.6)
    g = [(x * 0.92, z * 0.97 + 0.02) for x, z in outer]
    verts = [Vector((x, 0.0, z)) for x, z in g]
    me = bpy.data.meshes.new("glass")
    me.from_pydata(verts, [], [list(range(len(verts)))[::-1]])
    ob = K._obj("glass", me, M["mirror"])
    K.uv_box(ob, 1.0)
    for o in K.COLL.objects:
        o.rotation_euler = (math.radians(-6), 0, 0)
    bx("foot", (W + 0.06, 0.14, 0.03), (0, 0.03, 0.015), M["f"], bevel=0.008, grain="x")


def build_basket_trio():
    """Three woven baskets of different sizes with rope handles, a knitted throw in the biggest."""
    M["b"] = K.textured("basket_trio_weave", CL.wicker_maps("basket_trio_weave", TEX)[0], 0.8)
    M["throw"] = knit("basket_trio_throw", "#e8a9a6")
    for k, (x, y, r, h) in enumerate(((-0.2, 0.05, 0.22, 0.38), (0.22, 0.1, 0.17, 0.3), (0.12, -0.2, 0.12, 0.18))):
        shell("basket", [(r * 0.85, 0.0), (r, h * 0.2), (r * 1.04, h)], M["b"], steps=32, u_rep=6, v_rep=2, inner=0.012).location = (x, y, 0)
        disc_at("floor", r * 0.85, x, y, 0.005, M["b"])
        K.uv_box(K.torus("rim", r * 1.03, 0.014, (x, y, h), M["b"], major=32, minor=6), 4)
        for sx in (-1, 1):
            K.uv_box(K.torus("handle", 0.035, 0.008, (x + sx * r * 1.04, y, h - 0.06), M["cream"], rot=(90, 0, 90), major=12, minor=5), 4)
    bl("throw", 0.2, (-0.2, 0.05, 0.36), M["throw"], scale=(1, 1, 0.45), u=20, v=10, boxy=0.8)
    bl("throw_fold", 0.12, (-0.08, -0.08, 0.3), M["throw"], scale=(1.2, 0.5, 1.3), u=14, v=10, rot=(0, 0, -30))


CANDLE_STAND_CUPS = []


def build_candle_stand():
    """A painted iron floor candelabra: a twisted stem and three arms with cups for candles
    (the game stands its own lit candle in each: furniture.json "candles")."""
    M["p"] = _metallic(glaze("candle_stand_paint", "#2c2a28", 0.4), 0.3)
    cy("foot", 0.15, 0.17, 0.03, (0, 0, 0.015), M["p"], verts=24, bevel=0.01)
    stem = [Vector((0.008 * math.cos(t * 1.4), 0.008 * math.sin(t * 1.4), 0.03 + t * 0.02)) for t in range(56)]
    pipe("stem", stem, 0.014, M["p"])
    CANDLE_STAND_CUPS.clear()
    for k, (dx, z) in enumerate(((-0.2, 1.05), (0.0, 1.2), (0.2, 1.05))):
        if dx:
            pipe("arm", CL.bezier(Vector((0, 0, 0.95)), Vector((dx * 0.4, 0, 0.88)), Vector((dx, 0, 0.9)), Vector((dx, 0, z - 0.05)), n=10), 0.01, M["p"])
        K.lathe("cup", [(0.012, z - 0.06), (0.03, z - 0.04), (0.05, z - 0.02), (0.055, z), (0.045, z), (0.02, z - 0.01)], M["p"], steps=18, loc=(dx, 0, 0))
        CANDLE_STAND_CUPS.append((dx, z - 0.015, 0))


def build_mushroom_table():
    """A toadstool side table: a cream stem and a broad spotted cap with a flat top."""
    cap = spots_maps("mushroom_table_cap", "#c8615a", "#f6ecd8", seed=23, count=10)
    M["cap"] = K.textured("mushroom_table_cap", cap[0], 0.4, normal=cap[1], normal_strength=0.6)
    K.lathe("stem", [(0.2, 0.0), (0.21, 0.02), (0.15, 0.08), (0.12, 0.3), (0.13, 0.5), (0.0, 0.5)], M["cream"], steps=32)
    K.lathe("cap", [(0.0, 0.48), (0.34, 0.48), (0.36, 0.51), (0.35, 0.55), (0.3, 0.6), (0.0, 0.62)], M["cap"], steps=40)


def build_pedestal_table():
    """A round side table on a tulip pedestal, painted."""
    M["p"] = glaze("pedestal_table_paint", "#ece8df", 0.35)
    K.lathe("base", [(0.22, 0.0), (0.22, 0.015), (0.18, 0.04), (0.08, 0.1), (0.04, 0.3), (0.05, 0.5), (0.0, 0.5)], M["p"], steps=36)
    cy("top", 0.27, 0.27, 0.03, (0, 0, 0.53), M["p"], verts=40, bevel=0.01)
    K.uv_box(K.torus("top_edge", 0.27, 0.012, (0, 0, 0.53), M["brass"], major=48, minor=6), 3)


KINDS = {
    "mushroom_lamp": build_mushroom_lamp, "paper_lantern_lamp": build_paper_lantern_lamp, "tripod_lamp": build_tripod_lamp,
    "arc_lamp": build_arc_lamp, "pleated_lamp": build_pleated_lamp, "tulip_lamp": build_tulip_lamp,
    "chaise_longue": build_chaise_longue, "papasan_chair": build_papasan_chair, "wingback_chair": build_wingback_chair,
    "egg_chair": build_egg_chair, "scallop_chair": build_scallop_chair, "floor_lounger": build_floor_lounger,
    "knit_pouf": build_knit_pouf, "cushion_pile": build_cushion_pile, "bunny_stool": build_bunny_stool,
    "rug_scallop": build_rug_scallop, "rug_checker": build_rug_checker, "rug_arch": build_rug_arch,
    "floor_vase": build_floor_vase, "cactus_trio": build_cactus_trio, "fiddle_fig": build_fiddle_fig, "plant_stand": build_plant_stand,
    "wall_clock": build_wall_clock, "wall_shelf": build_wall_shelf, "rainbow_print": build_rainbow_print,
    "arch_mirror": build_arch_mirror, "basket_trio": build_basket_trio, "candle_stand": build_candle_stand,
    "mushroom_table": build_mushroom_table, "pedestal_table": build_pedestal_table,
}
WALL = ("wall_clock", "wall_shelf", "rainbow_print")  # hung: the origin stays at the back, not centred in depth
BUDGET = {"fiddle_fig": 20000, "egg_chair": 20000, "plant_stand": 20000}


def recentre(kind):
    """Origin on the floor under the middle (a hung piece: under the middle of its back)."""
    bpy.context.view_layer.update()
    obs = [o for o in K.COLL.objects if o.type == "MESH"]
    co = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    y = -hi.y if kind in WALL else -(lo.y + hi.y) / 2
    shift = Vector((-(lo.x + hi.x) / 2, y, -lo.z))
    for o in obs:
        if o.parent is None:
            o.matrix_world = Matrix.Translation(shift) @ o.matrix_world
    return shift


def make(kind):
    K.reset(kind)
    shared()
    KINDS[kind]()
    shift = recentre(kind)
    out = os.path.join(OUT, kind)
    K.finish(kind, out, max_tris=BUDGET.get(kind, 15000))
    if kind == "candle_stand":  # where the game's candles stand, in Godot's axes (x, up, -y)
        print("CANDLES", json.dumps([[round(x + shift.x, 3), round(z + shift.z, 3), round(-(y + shift.y), 3)] for x, z, y in CANDLE_STAND_CUPS]))
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(out, kind + ".glb"), os.path.join(PROPS, kind + ".glb"))
    print("COPIED", kind)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for k in (list(KINDS) if args == ["all"] else args):
    make(k)
