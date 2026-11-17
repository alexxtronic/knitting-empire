"""The furnishings of Marcus's house in Bretton Oaks, a 1990s suburban back-split (2026-11-17),
copied from two ChatGPT lineup sheets in ref/ (lineup_1: kitchen, bath, rec room and garage;
lineup_2: the kids' toys and the garage shelf).

    kitchen_counter_90s  a 2.4 m run of honey-oak base cabinets (a bank of three drawers, two doors
                         under the sink, two more), white laminate top with a backsplash, a double
                         stainless sink and a gooseneck tap, and oak wall cabinets either side above
    kitchen_island_90s   an oak island with drawers and doors, a white top and a black electric
                         cooktop with four coil burners
    fridge_90s           an almond top-freezer fridge with brown bar handles and a toe grille
    toilet               a white close-coupled toilet, lid down, chrome lever
    bathroom_vanity      a white two-door vanity, cultured-marble top with an oval basin and a
                         two-handle tap, a white-framed mirror above
    bathtub              a white tub/shower alcove (back and end walls), shower head and valve on
                         the left end, a chrome rail and a rose-print curtain gathered to the right
    pinball_machine      a purple space-theme pinball table: chrome legs, side art, a lit backglass
                         with a rocket, bumpers under the glass, coin door and plunger at the front
    crt_tv               a charcoal 90s CRT on a black two-shelf stand with a VCR, tapes and books
    workbench            an orange-pine garage bench, pegboard back with hand tools, three
                         toolboxes on the shelf below
    garage_shelf         grey steel shelving, four shelves of cardboard boxes, paint cans, a gas can
    teddy_bear, toy_blocks, toy_truck, rocking_horse, toy_ball, toy_train
                         the kids' toys (the truck, horse and train run along X, nose to -X)

Front faces -Y here (+Z in Godot); the origin is on the floor under the middle of each piece's
bounding box (make() re-centres it). Textures are painted in numpy, like cafe_props.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/marcus_props/build.py -- <kind> ... | all

Writes out/<kind>/<kind>.{blend,glb} and stats.json, and copies the GLB to assets/props/.
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


def mix(a, b, t):
    return a * (1 - t) + b * t


# --- painted textures ----------------------------------------------------------------------------

def grid_uv(n, m=None):
    m = m or n
    yy, xx = np.mgrid[0:m, 0:n]
    return xx / n, 1 - yy / m


def star_mask(u, v, cx, cy, r, points=5, inner=0.45, turn=0.0, aspect=1.0):
    du, dv = (u - cx) * aspect, v - cy
    th = np.arctan2(dv, du) + turn
    rr = np.hypot(du, dv)
    k = np.abs(((th * points / (2 * np.pi)) % 1.0) - 0.5) * 2  # 1 at a point, 0 between
    edge = r * (inner + (1 - inner) * k ** 1.6)
    return rr < edge


def painted(name, rgb, hgt=None, strength=1.2):
    """Saves a painted map with a little brushy mottling, and its normal map if hgt is given."""
    n = rgb.shape[1]
    mott = K.tile_noise(n, 1.5, abs(hash(name)) % 997, m=rgb.shape[0]) if rgb.shape[0] == n else 0.5
    rgb = rgb * (0.94 + 0.1 * np.asarray(mott)[..., None] if np.ndim(mott) else 1.0)
    img = K.save_image(name, rgb, TEX)
    if hgt is None:
        return img, None
    return img, K.save_image(name + "_n", K.normal_from_height(hgt, strength), TEX)


def tex_side_art(n=512):
    """The pinball cabinet's side: deep purple, a yellow-orange starburst, gold stars, a magenta
    swoosh, like the reference."""
    u, v = grid_uv(n)
    rgb = mix(C("#3a1f78"), C("#6a2fa8"), (v * 0.8 + 0.2 * K.tile_noise(n, 1.6, 3))[..., None])
    sw = np.abs(v - (0.35 + 0.25 * np.sin(u * 3.0))) < 0.06
    rgb[sw] = mix(rgb[sw], C("#e2389a"), 0.85)
    burst = star_mask(u, v, 0.32, 0.45, 0.26, points=8, inner=0.35)
    core = star_mask(u, v, 0.32, 0.45, 0.14, points=8, inner=0.5)
    rgb[burst] = C("#f08a1c")
    rgb[core] = C("#ffd23a")
    rng = np.random.default_rng(4)
    for _ in range(14):
        cx, cy, r = rng.uniform(0.05, 0.95), rng.uniform(0.08, 0.95), rng.uniform(0.025, 0.05)
        rgb[star_mask(u, v, cx, cy, r, turn=rng.uniform(0, 1))] = C("#ffd84a")
    for cx, cy, r, c in ((0.78, 0.7, 0.09, "#38b6e8"), (0.72, 0.25, 0.06, "#7ad04a")):
        d = np.hypot(u - cx, v - cy)
        rgb[d < r] = mix(C(c), C("#ffffff"), np.clip(0.4 - d / r * 0.5, 0, 1)[d < r][..., None])
    return painted("pin_side", rgb)


def tex_backglass(n=512):
    """The backglass: a night sky with stars, a ringed planet and a red-and-white rocket climbing
    from a cloud, as on the reference."""
    u, v = grid_uv(n)
    rgb = mix(C("#1a1a5c"), C("#5a2a9c"), v[..., None])
    rng = np.random.default_rng(9)
    for _ in range(60):
        cx, cy = rng.uniform(0, 1, 2)
        rgb[np.hypot(u - cx, v - cy) < rng.uniform(0.003, 0.008)] = C("#fff6d8")
    for _ in range(8):
        cx, cy, r = rng.uniform(0.05, 0.95), rng.uniform(0.1, 0.95), rng.uniform(0.025, 0.045)
        rgb[star_mask(u, v, cx, cy, r, turn=rng.uniform(0, 1))] = C("#ffd23a")
    # the planet and its ring
    d = np.hypot(u - 0.78, v - 0.35)
    rgb[d < 0.11] = mix(C("#f0a040"), C("#c4602a"), np.clip((v[d < 0.11] - 0.25) * 4, 0, 1)[..., None])
    ring = np.abs(np.hypot((u - 0.78) / 1.0, (v - 0.35) / 0.28) - 0.17) < 0.012
    rgb[ring & ~((d < 0.11) & (v > 0.35))] = C("#ffe08a")
    # the cloud it launches from
    for cx, cy, r in ((0.15, 0.15, 0.1), (0.27, 0.12, 0.09), (0.36, 0.17, 0.07), (0.08, 0.22, 0.07)):
        rgb[np.hypot(u - cx, v - cy) < r] = C("#f4dfe8")
    # the rocket: a body along a diagonal, nose cone, fins, a window, a flame tail
    a = math.radians(35)
    ru, rv = (u - 0.52) * math.cos(a) + (v - 0.6) * math.sin(a), -(u - 0.52) * math.sin(a) + (v - 0.6) * math.cos(a)
    body = (np.abs(rv) < 0.06 * np.sqrt(np.clip(1 - (ru / 0.2) ** 2, 0, 1))) & (ru > -0.16)
    rgb[body] = C("#f4f0ea")
    rgb[body & (ru > 0.1)] = C("#d8302a")
    fin = (ru < -0.08) & (ru > -0.17) & (np.abs(rv) < 0.06 + (-0.08 - ru) * 0.9) & (np.abs(rv) > 0.04)
    rgb[fin] = C("#d8302a")
    rgb[np.hypot(ru - 0.03, rv) < 0.025] = C("#5ac8f0")
    flame = (ru < -0.16) & (ru > -0.32) & (np.abs(rv) < 0.04 * (ru + 0.32) / 0.16)
    rgb[flame] = mix(C("#ffd23a"), C("#ff6a1a"), np.clip((-0.16 - ru[flame]) / 0.16, 0, 1)[..., None])
    return painted("pin_backglass", rgb)


def tex_playfield(n=512):
    """The playfield under the glass: blue to purple, lit inserts in rows, white lane guides."""
    u, v = grid_uv(n)
    rgb = mix(C("#2a3aa8"), C("#7a2aa0"), v[..., None])
    rng = np.random.default_rng(12)
    for row in range(5):
        for k in range(4):
            cx, cy = 0.2 + 0.2 * k, 0.25 + 0.13 * row
            c = ["#ffd23a", "#ff5a3a", "#3ae0a0", "#ff7ad0"][(row + k) % 4]
            rgb[np.hypot(u - cx, (v - cy) * 1.4) < 0.035] = C(c)
    rgb[star_mask(u, v, 0.5, 0.12, 0.07)] = C("#ffd23a")
    for x0 in (0.12, 0.88):
        rgb[(np.abs(u - x0) < 0.008) & (v > 0.6)] = C("#f4f0ea")
    rgb[(np.abs(u - 0.5 - (v - 0.05) * 0.0) < 0.01) & (v < 0.05)] = C("#111111")
    return painted("pin_playfield", rgb)


def tex_screen(name, base, light, n=256):
    """A glass face (CRT screen or mirror): lighter in the middle, darker at the edges, with two
    soft diagonal highlights painted on like the references."""
    u, v = grid_uv(n)
    d = np.hypot((u - 0.5) * 1.1, v - 0.5)
    rgb = mix(C(light), C(base), np.clip(d * 1.6, 0, 1)[..., None])
    s = u + v
    for c0, w in ((1.25, 0.06), (1.42, 0.025)):
        band = np.clip(1 - np.abs(s - c0) / w, 0, 1) * np.clip((v - 0.35) * 3, 0, 1)
        rgb = mix(rgb, C("#ffffff"), (band * 0.55)[..., None])
    return painted(name, rgb)


def tex_pegboard(n=1024, m=512):
    """Brown hardboard pegboard: a hole every 25 mm across a 1.72 x 0.86 m board."""
    u, v = grid_uv(n, m)
    rgb = C("#b47a40") * (0.9 + 0.12 * K.tile_noise(n, 1.4, 21, m=m))[..., None]
    gu, gv = (u * 1.72 / 0.025) % 1.0, (v * 0.86 / 0.025) % 1.0
    hole = np.hypot((gu - 0.5) * 0.025, (gv - 0.5) * 0.025) < 0.0035
    rgb[hole] = C("#3a2210")
    return painted("peg_board", rgb, -hole.astype(float), 2.0)


def tex_curtain(n=512):
    """A 90s shower curtain: cream with pink roses and green leaves, teal and pink bands near the
    hem. u runs across the curtain, v up it."""
    u, v = grid_uv(n)
    rgb = C("#f6ecdc") * np.ones((n, n, 1))
    rng = np.random.default_rng(31)
    for _ in range(26):
        cx, cy = rng.uniform(0, 1), rng.uniform(0.25, 0.98)
        for lx, ly in ((-0.03, -0.012), (0.03, -0.012)):
            rgb[np.hypot((u - cx - lx) / 1.6, v - cy - ly) < 0.012] = C("#7fb08a")
        d = np.hypot(u - cx, v - cy)
        rgb[d < 0.022] = C("#e88ea2")
        rgb[(d < 0.012)] = C("#cc5f7c")
    for c0, w, c in ((0.08, 0.025, "#4fb3a6"), (0.13, 0.012, "#e88ea2"), (0.17, 0.008, "#4fb3a6")):
        rgb[np.abs(v - c0) < w] = C(c)
    return painted("curtain_roses", rgb)


def tex_dapple(n=256):
    """The rocking horse's cream paint with orange-brown spots, as on the reference."""
    u, v = grid_uv(n)
    rgb = C("#f6ecd6") * np.ones((n, n, 1))
    rng = np.random.default_rng(41)
    for _ in range(26):
        cx, cy, r = rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0.025, 0.045)
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                d = np.hypot(u - cx - ox, v - cy - oy)
                rgb = mix(rgb, C("#d9904a"), (np.clip((1 - d / r) * 3, 0, 1) * 0.85)[..., None])
    return painted("horse_dapple", rgb)


def tex_ball(n=256):
    """The ball: three bands, red at the top, yellow round the middle, blue below (v runs up the
    lathe from the bottom pole), each band's edge waving a little as the ball is tipped."""
    u, v = grid_uv(n)
    t = v + 0.06 * np.sin(2 * np.pi * u)
    rgb = np.where((t > 0.62)[..., None], C("#e3342c"), np.where((t > 0.4)[..., None], C("#f8c826"), C("#2f6fd8")))
    return painted("ball_bands", rgb)


def tex_plush(n=256):
    """Teddy-bear plush: warm brown with soft fur streaks."""
    g = K.grain_noise(n, 6.0, 1.0, 51)
    f = K.tile_noise(n, 0.8, 52)
    rgb = mix(C("#8a5228"), C("#b87a40"), np.clip(g * 0.8 + f * 0.4 - 0.2, 0, 1)[..., None])
    return painted("bear_plush", rgb, f * 0.5 + g * 0.3, 1.5)


def tex_kraft(n=256):
    f = K.tile_noise(n, 1.2, 61)
    g = K.grain_noise(n, 10.0, 1.0, 62)
    rgb = C("#c69458") * (0.88 + 0.12 * f[..., None] + 0.06 * g[..., None])
    return painted("box_kraft", rgb)


def tex_grille(n=128):
    u, v = grid_uv(n)
    slot = ((v * 8) % 1.0) < 0.45
    rgb = np.where(slot[..., None], C("#2a241e"), C("#d9ccab"))
    return painted("fridge_grille", rgb)


def tex_speaker(n=128):
    u, v = grid_uv(n)
    dots = np.hypot((u * 24) % 1 - 0.5, (v * 12) % 1 - 0.5) < 0.28
    rgb = np.where(dots[..., None], C("#0e0e10"), C("#3a3a3e"))
    return painted("speaker_grille", rgb)


def tex_vcr(n=256, m=64):
    """The VCR's face: black, a cassette slot, a green clock reading 12:00, little buttons."""
    u, v = grid_uv(n, m)
    rgb = C("#1d1d20") * np.ones((m, n, 1))
    rgb[(np.abs(u - 0.38) < 0.2) & (np.abs(v - 0.55) < 0.12)] = C("#0a0a0a")
    rgb[(np.abs(u - 0.78) < 0.08) & (np.abs(v - 0.55) < 0.16)] = C("#0c1a10")
    for k, cx in enumerate((0.73, 0.76, 0.80, 0.83)):
        rgb[(np.abs(u - cx) < 0.01) & (np.abs(v - 0.55) < 0.09)] = C("#5aff8a")
    for cx in (0.65, 0.92):
        rgb[(np.abs(u - cx) < 0.02) & (np.abs(v - 0.3) < 0.08)] = C("#8a8a90")
    return painted("vcr_face", rgb)


def tex_label(name, colour, n=128):
    """A paint can's label: a colour band with a white strip and a swatch."""
    u, v = grid_uv(n)
    rgb = C("#f4f2ea") * np.ones((n, n, 1))
    rgb[(v > 0.15) & (v < 0.85)] = C(colour)
    rgb[(np.abs(v - 0.5) < 0.12)] = C("#f4f2ea")
    rgb[(np.abs(v - 0.5) < 0.08) & (np.abs(u - 0.25) < 0.08)] = C(colour) * 0.8
    return painted(name, rgb)


# --- materials -----------------------------------------------------------------------------------

def _metal(m, metallic):
    m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = metallic
    return m


def _wood(name, base, light, dark, seed, n=512, knots=1):
    i, nm = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=0, seed=seed, knots=knots, n=n)
    return K.textured(name, i, rough=0.55, normal=nm, normal_strength=0.5)


def _tex(fn, rough=0.8, emit=0.0, ns=0.6):
    def make(key):
        i, nm = fn()
        return K.textured(key, i, rough, emit=emit, normal=nm, normal_strength=ns)
    return make


MATS = {
    "oak": lambda k: _wood("m90_oak", "#c8822f", "#daa04a", "#a86a2a", 7, knots=0),
    "pine": lambda k: _wood("m90_pine", "#d98c38", "#f0b060", "#a86224", 11),
    "laminate": lambda k: K.plain("m90_laminate", "#eeeae0", 0.35),
    "marble": lambda k: K.plain("m90_cultured_marble", "#f1ece2", 0.2),
    "porcelain": lambda k: K.plain("m90_porcelain", "#f6f3ec", 0.14),
    "acrylic": lambda k: K.plain("m90_acrylic", "#f0ebe0", 0.22),
    "white_paint": lambda k: K.plain("m90_white_paint", "#f2eee4", 0.45),
    "stainless": lambda k: _metal(K.plain("m90_stainless", "#b8bcc0", 0.3), 0.85),
    "chrome": lambda k: _metal(K.plain("m90_chrome", "#d4d8dc", 0.14), 0.9),
    "brass": lambda k: _metal(K.plain("m90_brass", "#c99a34", 0.3), 0.8),
    "almond": lambda k: K.plain("m90_almond", "#ede1c4", 0.32),
    "almond_dark": lambda k: K.plain("m90_almond_trim", "#d5c6a4", 0.4),
    "handle_brown": lambda k: _metal(K.plain("m90_handle", "#7a6a58", 0.35), 0.4),
    "black": lambda k: K.plain("m90_black", "#1c1b1e", 0.5),
    "black_gloss": lambda k: K.plain("m90_black_gloss", "#151517", 0.15),
    "charcoal": lambda k: K.plain("m90_charcoal", "#3a383c", 0.45),
    "coil": lambda k: _metal(K.plain("m90_coil", "#2c2b2a", 0.45), 0.5),
    "rubber": lambda k: K.plain("m90_rubber", "#141414", 0.8),
    "steel_grey": lambda k: _metal(K.plain("m90_steel_grey", "#8d939a", 0.45), 0.5),
    "glass": lambda k: K.plain("m90_glass", "#eef6f8", 0.03, alpha=0.18),
    "door_glass": lambda k: K.plain("glass", "#e4f0f4", 0.03, alpha=0.2),  # the game swaps it by name
    "alu_white": lambda k: K.plain("m90_alu_white", "#f1efea", 0.3),
    "purple": lambda k: K.plain("m90_pin_purple", "#4a2a88", 0.4),
    "red": lambda k: K.plain("m90_toy_red", "#d8352c", 0.4),
    "yellow": lambda k: K.plain("m90_toy_yellow", "#f6c62a", 0.4),
    "blue": lambda k: K.plain("m90_toy_blue", "#2f74d6", 0.4),
    "green": lambda k: K.plain("m90_toy_green", "#45a845", 0.4),
    "orange": lambda k: K.plain("m90_toy_orange", "#f08a24", 0.4),
    "violet": lambda k: K.plain("m90_toy_violet", "#8a4ec4", 0.4),
    "cream": lambda k: K.plain("m90_cream", "#f6efdc", 0.5),
    "tan": lambda k: K.plain("m90_bear_tan", "#e2b47a", 0.85),
    "eye": lambda k: K.plain("m90_eye", "#121010", 0.15),
    "lit_red": lambda k: K.plain("m90_lit_red", "#ff3a2a", 0.3, emit=2.0),
    "lit_yellow": lambda k: K.plain("m90_lit_yellow", "#ffd23a", 0.3, emit=1.5),
    "bulb": lambda k: K.plain("m90_bulb", "#fff2cc", 0.2, emit=1.2),
    "rose_pink": lambda k: K.plain("m90_rose_pink", "#e88ea2", 0.6),
    "mane": lambda k: K.plain("m90_yarn_mane", "#d6aa5c", 0.95),
    "hose_orange": lambda k: K.plain("m90_cord_orange", "#f07a1c", 0.5),
    "side_art": _tex(tex_side_art, 0.4, ns=0),
    "backglass": _tex(tex_backglass, 0.3, emit=0.7, ns=0),
    "playfield": _tex(tex_playfield, 0.3, emit=0.25, ns=0),
    "crt": _tex(lambda: tex_screen("crt_screen", "#1e2a28", "#4e605a"), 0.08, ns=0),
    "mirror": _tex(lambda: tex_screen("mirror_glass", "#9fb6c2", "#dfeaf0"), 0.05, ns=0),
    "pegboard": _tex(tex_pegboard, 0.8, ns=0.5),
    "curtain": _tex(tex_curtain, 0.85, ns=0),
    "dapple": _tex(tex_dapple, 0.45, ns=0),
    "ball": _tex(tex_ball, 0.3, ns=0),
    "plush": _tex(tex_plush, 0.95, ns=0.8),
    "kraft": _tex(tex_kraft, 0.9, ns=0),
    "grille": _tex(tex_grille, 0.5, ns=0),
    "speaker": _tex(tex_speaker, 0.6, ns=0),
    "vcr": _tex(tex_vcr, 0.4, emit=0.0, ns=0),
}
for _c, _hex in (("can_blue", "#3a6ad0"), ("can_green", "#4aa050"), ("can_cream", "#efe0b8"), ("can_red", "#c83a30")):
    MATS["label_" + _c] = _tex(lambda c=_c, h=_hex: tex_label("label_" + c, h), 0.5, ns=0)


def mat(key):
    if key not in M:
        M[key] = MATS[key]("m90_" + key)
    return M[key]


# --- shapes --------------------------------------------------------------------------------------

def bx(name, size, loc, m, bevel=0.008, rot=(0, 0, 0), grain="z", scale=None):
    if scale is None:
        scale = 2.5 if m == "oak" else 1.5  # the oak's grain reads finer, like the references
    return K.uv_box(K.box(name, size, loc, mat(m), bevel=bevel, seg=1, rot=rot), scale, grain=grain)


def cy(name, r1, r2, h, loc, m, verts=12, rot=(0, 0, 0), scale=2.0):
    return K.uv_box(K.cyl(name, r1, r2, h, loc, mat(m), verts=verts, rot=rot), scale)


def bl(name, r, loc, m, scale=(1, 1, 1), u=10, v=7, boxy=1.0, uvs=4.0):
    return K.uv_box(K.ball(name, r, loc, mat(m), scale=scale, u=u, v=v, boxy=boxy), uvs)


def tube(name, pts, r, m, sides=6, caps=True):
    radii = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    return CL.tube(name, [Vector(p) for p in pts], radii, mat(m), sides=sides, caps=caps)


def pane(name, a, b, m, out=(0, -1, 0)):
    return K.pane(name, a, b, mat(m), out)


def quad(name, corners, m):
    """One flat quad through four corners (counter-clockwise seen from its front), the texture
    mapped across it once."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(c) for c in corners], [], [(0, 1, 2, 3)])
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", [0, 0, 1, 0, 1, 1, 0, 1])
    return K._obj(name, me, mat(m))


def poly_x(name, pts_yz, x, m, facing):
    """A flat polygon in the plane x = const (pts as (y, z)), facing +X (facing=1) or -X, the
    texture mapped once across its bounds: the pinball's side art."""
    ys = [p[0] for p in pts_yz]
    zs = [p[1] for p in pts_yz]
    verts = [(x, y, z) for y, z in pts_yz]
    idx = list(range(len(verts)))
    if facing < 0:
        idx.reverse()
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], [tuple(idx)])
    lay = me.uv_layers.new(name="UVMap")
    for li, loop in enumerate(me.loops):
        y, z = pts_yz[loop.vertex_index]
        u = (y - min(ys)) / (max(ys) - min(ys))
        lay.data[li].uv = ((1 - u) if facing > 0 else u, (z - min(zs)) / (max(zs) - min(zs)))
    ob = K._obj(name, me, mat(m))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


def cut(ob, cutter):
    """Subtracts cutter from ob (an exact boolean) and removes the cutter."""
    md = ob.modifiers.new("cut", "BOOLEAN")
    md.object = cutter
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    bpy.context.view_layer.update()
    K.apply_mods(ob)
    bpy.data.objects.remove(cutter)
    return ob


def bowl(name, rx, ry, depth, loc, m, u=16, v=6):
    """The inside of a basin: the lower half of an ellipsoid, its faces turned inward."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v * 2, radius=1.0)
    bmesh.ops.delete(bm, geom=[vv for vv in bm.verts if vv.co.z > 1e-4], context="VERTS")
    for vv in bm.verts:
        vv.co = Vector((vv.co.x * rx, vv.co.y * ry, vv.co.z * depth))
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat(m))
    ob.location = loc
    return K.uv_box(K.smooth(ob, keep_sharp=False), 3.0)


def sink_box(name, w, d, h, loc, m):
    """An open-topped box seen from inside (a sink basin, a tub's well)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z > 0.5], context="FACES")
    for vv in bm.verts:
        vv.co = Vector((vv.co.x * w, vv.co.y * d, vv.co.z * h))
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat(m))
    ob.location = loc
    return K.uv_box(ob, 3.0)


def letter(name, ch, size, loc, rot, m, depth=0.002):
    """A raised letter (the built-in font) with a coarse curve resolution, centred on loc."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = ch
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth
    cu.resolution_u = 2
    ob = bpy.data.objects.new(name, cu)
    K._link(ob)
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mob = K._obj(name, me, mat(m))
    mob.matrix_world = ob.matrix_world.copy()
    bpy.data.objects.remove(ob)
    return mob


def knob(x, y, z, m="brass", r=0.014):
    return bl("knob", r, (x, y, z), m, u=8, v=5)


def door(name, x0, x1, z0, z1, yf, m="oak", knob_at=None, inset=0.055, arch=False):
    """A cabinet door or drawer front whose face is at y = yf: a slab with a raised centre panel."""
    w, h = x1 - x0, z1 - z0
    bx(name, (w - 0.006, 0.02, h - 0.006), ((x0 + x1) / 2, yf + 0.01, (z0 + z1) / 2), m, bevel=0.006)
    if min(w, h) > 0.16:
        bx(name + "_panel", (w - 2 * inset, 0.01, h - 2 * inset), ((x0 + x1) / 2, yf - 0.002, (z0 + z1) / 2), m, bevel=0.008)
    if knob_at is not None:
        knob(knob_at[0], yf - 0.012, knob_at[1])


def base_run(x0, x1, y0, y1, z_top, m="oak", kick=0.09):
    """A cabinet carcass from x0 to x1, back at y1, front at y0 (doors go on in front of it),
    with a recessed toe kick."""
    bx("carcass", (x1 - x0, y1 - y0, z_top - kick), ((x0 + x1) / 2, (y0 + y1) / 2, (z_top + kick) / 2), m, bevel=0.006)
    bx("toe_kick", (x1 - x0 - 0.02, y1 - y0 - 0.06, kick), ((x0 + x1) / 2, (y0 + y1) / 2 + 0.03, kick / 2), "black", bevel=0.0)


def spiral(name, cx, cy, z, r0, r1, turns, m="coil"):
    pts = []
    n = int(turns * 14)
    for i in range(n + 1):
        t = i / n
        a = 2 * math.pi * turns * t
        r = r0 + (r1 - r0) * t
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    return tube(name, pts, 0.0055, m, sides=5)


# --- kitchen -------------------------------------------------------------------------------------

def build_kitchen_counter_90s():
    W, D, H = 2.4, 0.62, 0.91
    x0, x1 = -W / 2 + 0.02, W / 2 - 0.02
    yb, yf = D / 2, -D / 2 + 0.05   # carcass back and front; doors stand proud of yf
    base_run(x0, x1, yf, yb, H - 0.04)
    df = yf - 0.02
    # a bank of three drawers on the left
    zt = H - 0.06
    for i in range(3):
        za, zb = 0.1 + i * (zt - 0.1) / 3, 0.1 + (i + 1) * (zt - 0.1) / 3
        door("drawer", x0 + 0.01, x0 + 0.6, za + 0.005, zb - 0.005, df, knob_at=(x0 + 0.305, (za + zb) / 2))
    # the sink base: a false drawer front and two doors
    sx0, sx1 = x0 + 0.62, x0 + 1.42
    door("false_front", sx0, sx1, zt - 0.15, zt, df)
    door("sink_door_l", sx0, (sx0 + sx1) / 2, 0.1, zt - 0.17, df, knob_at=((sx0 + sx1) / 2 - 0.05, zt - 0.25))
    door("sink_door_r", (sx0 + sx1) / 2, sx1, 0.1, zt - 0.17, df, knob_at=((sx0 + sx1) / 2 + 0.05, zt - 0.25))
    # the right: a drawer over two doors
    rx0 = sx1 + 0.02
    rm = (rx0 + x1) / 2
    door("drawer_r", rx0, x1 - 0.01, zt - 0.15, zt, df, knob_at=(rm, zt - 0.075))
    door("door_rl", rx0, rm, 0.1, zt - 0.17, df, knob_at=(rm - 0.05, zt - 0.25))
    door("door_rr", rm, x1 - 0.01, 0.1, zt - 0.17, df, knob_at=(rm + 0.05, zt - 0.25))
    # the laminate top with its rounded nosing and a backsplash, cut for the sink
    top = bx("top", (W, D, 0.04), (0, 0, H - 0.02), "laminate", bevel=0.012, scale=1.0)
    scx = (sx0 + sx1) / 2
    cutter = K.box("sink_hole", (0.76, 0.42, 0.2), (scx, -0.02, H), mat("laminate"), bevel=0.04, seg=2)
    cut(top, cutter)
    K.uv_box(top, 1.0)
    bx("backsplash", (W, 0.025, 0.1), (0, D / 2 - 0.0125, H + 0.05), "laminate", bevel=0.008)
    # the double sink: a rim, two basins and a divider
    rim = bx("sink_rim", (0.8, 0.46, 0.008), (scx, -0.02, H + 0.004), "stainless", bevel=0.004, scale=3)
    cut(rim, K.box("rim_hole", (0.74, 0.4, 0.1), (scx, -0.02, H), mat("stainless"), bevel=0.03, seg=2))
    for s in (-1, 1):
        sink_box("basin", 0.35, 0.39, 0.18, (scx + s * 0.185, -0.02, H - 0.08), "stainless")
    bx("divider", (0.02, 0.4, 0.012), (scx, -0.02, H + 0.002), "stainless", bevel=0.004)
    # a gooseneck tap and two handles
    tx, ty = scx, 0.21
    cy("tap_base", 0.03, 0.026, 0.03, (tx, ty, H + 0.015), "chrome", verts=10)
    tube("tap_neck", [(tx, ty, H + 0.02), (tx, ty, H + 0.2), (tx, ty - 0.04, H + 0.25), (tx, ty - 0.12, H + 0.22), (tx, ty - 0.15, H + 0.17)], 0.011, "chrome", sides=8)
    for s in (-1, 1):
        cy("tap_handle", 0.012, 0.01, 0.04, (tx + s * 0.09, ty, H + 0.02), "chrome", verts=8)
        bx("tap_lever", (0.05, 0.012, 0.01), (tx + s * 0.105, ty, H + 0.045), "chrome", bevel=0.003)
    # the wall cabinets: left over the drawers and the sink's edge, right over the right base
    for (ux0, ux1, ndoors) in ((-W / 2 + 0.02, -0.38, 2), (0.42, W / 2 - 0.02, 2)):
        uy0, uy1 = D / 2 - 0.32, D / 2
        z0, z1 = 1.42, 2.1
        bx("upper", (ux1 - ux0, uy1 - uy0, z1 - z0), ((ux0 + ux1) / 2, (uy0 + uy1) / 2, (z0 + z1) / 2), "oak", bevel=0.006)
        bx("crown", (ux1 - ux0 + 0.04, uy1 - uy0 + 0.03, 0.04), ((ux0 + ux1) / 2, (uy0 + uy1) / 2 - 0.015, z1 + 0.02), "oak", bevel=0.01)
        dw = (ux1 - ux0) / ndoors
        for i in range(ndoors):
            a, b = ux0 + i * dw, ux0 + (i + 1) * dw
            kx = b - 0.04 if i % 2 == 0 else a + 0.04
            door("upper_door", a, b, z0 + 0.01, z1 - 0.01, uy0 - 0.02, knob_at=(kx, z0 + 0.08))


def build_kitchen_island_90s():
    W, D, H = 1.6, 0.9, 0.91
    x0, x1, y0, y1 = -W / 2 + 0.05, W / 2 - 0.05, -D / 2 + 0.07, D / 2 - 0.07
    base_run(x0, x1, y0, y1, H - 0.04)
    zt = H - 0.06
    for side, yf in ((-1, y0 - 0.02), (1, y1)):
        mid = 0.0
        for a, b in ((x0 + 0.01, mid - 0.005), (mid + 0.005, x1 - 0.01)):
            # the back face gets plain panelled doors, no knobs
            if side < 0:
                door("drawer", a, b, zt - 0.15, zt, yf, knob_at=((a + b) / 2, zt - 0.075))
                door("door", a, b, 0.1, zt - 0.17, yf, knob_at=(b - 0.05 if a < 0 else a + 0.05, zt - 0.25))
            else:
                bx("back_door", (b - a - 0.006, 0.02, zt - 0.1 - 0.006), ((a + b) / 2, y1 + 0.01, (zt + 0.1) / 2), "oak", bevel=0.006)
                bx("back_panel", (b - a - 0.11, 0.01, zt - 0.21), ((a + b) / 2, y1 + 0.022, (zt + 0.1) / 2), "oak", bevel=0.008)
    # end panels with a raised panel each
    for s in (-1, 1):
        bx("end_panel", (0.01, y1 - y0 - 0.11, zt - 0.21), (s * (x1 + 0.002), 0, (zt + 0.1) / 2), "oak", bevel=0.008)
    bx("top", (W, D, 0.04), (0, 0, H - 0.02), "laminate", bevel=0.014, scale=1.0)
    cooktop(0.0, 0.02, H, knobs_on_top=True)


def cooktop(cx, cy_, H, knobs_on_top):
    """A black enamel cooktop on the counter at (cx, cy_), four coils over chrome drip pans (two
    big, two small, diagonally), its four knobs along its front edge or (knobs_on_top False) none,
    for the caller to put on the cabinet front."""
    bx("cooktop", (0.76, 0.52, 0.012), (cx, cy_, H + 0.006), "black_gloss", bevel=0.006)
    for (dx, dy, r) in ((-0.19, 0.11, 0.095), (0.19, 0.11, 0.075), (-0.19, -0.1, 0.075), (0.19, -0.1, 0.095)):
        d = K.disc("drip_pan", r + 0.02, H + 0.0125, mat("chrome"), steps=20)
        d.location = (cx + dx, cy_ + dy, 0)
        K.uv_box(d, 3)
        spiral("coil", cx + dx, cy_ + dy, H + 0.018, 0.018, r, 3.0)
    if knobs_on_top:
        for kx in (-0.27, -0.09, 0.09, 0.27):
            cy("knob", 0.016, 0.014, 0.018, (cx + kx, cy_ - 0.225, H + 0.021), "chrome", verts=10)


def build_fridge_90s():
    W, D, H = 0.8, 0.75, 1.75
    yb = D / 2
    yf = -D / 2 + 0.05  # the cabinet's face; the doors stand 0.05 proud of it
    bx("cabinet", (W, D - 0.05, H - 0.02), (0, (yf + yb) / 2, (H - 0.02) / 2 + 0.02), "almond", bevel=0.03, scale=1)
    # freezer door above, fresh-food door below, a dark seam between
    zg = 1.2
    bx("freezer_door", (W - 0.01, 0.05, H - zg - 0.03), (0, yf - 0.025, (zg + H) / 2 - 0.005), "almond", bevel=0.025, scale=1)
    bx("fresh_door", (W - 0.01, 0.05, zg - 0.13), (0, yf - 0.025, (zg + 0.11) / 2), "almond", bevel=0.025, scale=1)
    bx("seam", (W - 0.04, 0.03, 0.03), (0, yf - 0.012, zg - 0.008), "almond_dark", bevel=0.0)
    for ob in (bx("gasket", (W - 0.02, 0.006, H - 0.12), (0, yf - 0.001, (H + 0.1) / 2), "almond_dark", bevel=0.0),):
        pass
    # bar handles on the left of each door (hinges right), standing off on two feet
    hx = -W / 2 + 0.075
    for z0, z1 in ((zg + 0.1, zg + 0.38), (zg - 0.5, zg - 0.08)):
        bx("handle", (0.035, 0.03, z1 - z0), (hx, yf - 0.085, (z0 + z1) / 2), "handle_brown", bevel=0.012)
        for z in (z0 + 0.03, z1 - 0.03):
            bx("handle_foot", (0.03, 0.04, 0.03), (hx, yf - 0.06, z), "handle_brown", bevel=0.008)
    # hinges on the right
    for z in (H - 0.01, zg + 0.005, 0.1):
        bx("hinge", (0.06, 0.06, 0.018), (W / 2 - 0.05, yf - 0.03, z), "almond_dark", bevel=0.005)
    # the toe grille
    pane("grille", (-W / 2 + 0.05, yf - 0.002, 0.025), (W / 2 - 0.05, yf - 0.002, 0.095), "grille")
    # a kid's drawing and two magnets on the fresh-food door
    pane("drawing", (0.02, yf - 0.051, 0.72), (0.24, yf - 0.051, 0.95), "cream")
    bl("magnet", 0.014, (0.13, yf - 0.056, 0.94), "red", scale=(1, 0.5, 1), u=8, v=5)
    bl("magnet", 0.014, (-0.12, yf - 0.056, 1.05), "blue", scale=(1, 0.5, 1), u=8, v=5)
    for (a, b, c) in (((0.06, 0.78), (0.11, 0.86), "orange"), ((0.15, 0.76), (0.21, 0.82), "green")):
        pane("doodle", (a[0], yf - 0.052, a[1]), (b[0], yf - 0.052, b[1]), c)


# --- bathroom ------------------------------------------------------------------------------------

def build_toilet():
    # the bowl: an elongated pedestal and bowl, its open top under the seat
    prof = [(0.105, 0.0), (0.115, 0.02), (0.1, 0.1), (0.1, 0.2), (0.13, 0.28), (0.17, 0.34), (0.18, 0.38), (0.0, 0.381)]
    b = K.lathe("bowl", prof, mat("porcelain"), steps=20, loc=(0, -0.06, 0), sharp=50)
    b.scale = (1.0, 1.32, 1.0)
    K.uv_box(b, 3)
    K.torus("seat", 0.13, 0.03, (0, -0.07, 0.395), mat("porcelain"), major=20, minor=6).scale = (1.05, 1.32, 0.45)
    lid = bl("lid", 0.17, (0, -0.07, 0.41), "porcelain", scale=(0.98, 1.3, 0.11), u=18, v=8)
    bx("lid_hinge", (0.16, 0.04, 0.03), (0, 0.13, 0.405), "porcelain", bevel=0.012)
    # the tank and its lid, a chrome lever on the front left
    bx("neck", (0.2, 0.1, 0.06), (0, 0.18, 0.4), "porcelain", bevel=0.02)
    bx("tank", (0.48, 0.19, 0.36), (0, 0.255, 0.58), "porcelain", bevel=0.035, scale=2)
    bx("tank_lid", (0.5, 0.21, 0.04), (0, 0.255, 0.78), "porcelain", bevel=0.015, scale=2)
    cy("lever_boss", 0.018, 0.018, 0.015, (-0.17, 0.158, 0.7), "chrome", verts=10, rot=(90, 0, 0))
    bx("lever", (0.08, 0.012, 0.014), (-0.13, 0.15, 0.7), "chrome", bevel=0.005)
    # the supply valve on the left under the tank
    tube("supply", [(-0.15, 0.3, 0.4), (-0.15, 0.3, 0.2), (-0.15, 0.34, 0.16)], 0.006, "chrome")


def build_bathroom_vanity():
    W, D, H = 0.9, 0.55, 0.86
    yb, yf = D / 2, -D / 2 + 0.04
    base_run(-W / 2 + 0.02, W / 2 - 0.02, yf, yb - 0.01, H - 0.04, m="white_paint", kick=0.08)
    zt = H - 0.06
    for a, b, kx in ((-W / 2 + 0.035, -0.003, -0.06), (0.003, W / 2 - 0.035, 0.06)):
        door("door", a, b, 0.1, zt - 0.02, yf - 0.02, m="white_paint", knob_at=(kx, zt - 0.12))
        hx = a + 0.01 if a < 0 else b - 0.01
        for z in (0.17, zt - 0.1):
            bx("hinge", (0.012, 0.012, 0.05), (hx, yf - 0.045, z), "brass", bevel=0.003)
    # the cultured-marble top with its oval basin, backsplash and a two-handle tap
    top = bx("top", (W + 0.02, D, 0.04), (0, 0, H - 0.02), "marble", bevel=0.012, scale=1.0)
    cut(top, K.ball("basin_hole", 1.0, (0, -0.03, H), mat("marble"), scale=(0.2, 0.15, 0.1), u=24, v=8))
    K.uv_box(top, 1.0)
    bowl("basin", 0.2, 0.15, 0.13, (0, -0.03, H - 0.001), "marble", u=24, v=6)
    bx("backsplash", (W + 0.02, 0.025, 0.09), (0, D / 2 - 0.0125, H + 0.045), "marble", bevel=0.008)
    ty = 0.17
    bx("tap_plate", (0.2, 0.06, 0.02), (0, ty, H + 0.01), "chrome", bevel=0.008)
    tube("spout", [(0, ty, H + 0.02), (0, ty, H + 0.06), (0, ty - 0.08, H + 0.06)], 0.012, "chrome", sides=8)
    for s in (-1, 1):
        cy("tap_handle", 0.016, 0.012, 0.03, (s * 0.075, ty, H + 0.035), "chrome", verts=8)
    # the mirror on the wall above, in a white frame
    mz0, mz1, mw = 1.06, 1.56, 0.68
    my = D / 2 - 0.02
    bx("mirror_frame", (mw, 0.03, mz1 - mz0), (0, my, (mz0 + mz1) / 2), "white_paint", bevel=0.01)
    pane("mirror", (-mw / 2 + 0.035, my - 0.016, mz0 + 0.035), (mw / 2 - 0.035, my - 0.016, mz1 - 0.035), "mirror")


def build_bathtub():
    W, D = 1.5, 0.75
    TH, WH = 0.5, 1.9   # the tub's rim and the surround's top
    wall = 0.04
    tub = bx("tub", (W, D - wall, TH), (0, -wall / 2, TH / 2), "acrylic", bevel=0.02, scale=1)
    inner = K.box("well_cut", (W - 2 * wall - 0.14, D - wall - 0.17, 0.6), (0.02, -wall / 2 + 0.01, TH + 0.18), mat("acrylic"), bevel=0.08, seg=3)
    cut(tub, inner)
    K.uv_box(tub, 1.0)
    # the surround: back wall and two end walls with a moulded rim, a soap ledge on the back
    bx("back_wall", (W, wall, WH - TH + 0.02), (0, D / 2 - wall / 2, (WH + TH) / 2 - 0.01), "acrylic", bevel=0.01, scale=1)
    for s in (-1, 1):
        bx("end_wall", (wall, D, WH - TH + 0.02), (s * (W / 2 - wall / 2), 0, (WH + TH) / 2 - 0.01), "acrylic", bevel=0.01, scale=1)
        bx("end_lip", (wall + 0.03, 0.03, WH - TH), (s * (W / 2 - wall / 2), -D / 2 + 0.015, (WH + TH) / 2), "acrylic", bevel=0.012)
    bx("top_lip", (W, D + 0.0, 0.03), (0, 0, WH + 0.015), "acrylic", bevel=0.012, scale=1)
    bx("ledge", (0.5, 0.07, 0.03), (0.05, D / 2 - wall - 0.035, 1.05), "acrylic", bevel=0.01)
    bx("niche", (0.3, 0.02, 0.38), (0.05, D / 2 - wall - 0.01, 1.3), "acrylic", bevel=0.02)
    # shower head, valve and spout on the left end wall
    ex = -W / 2 + wall
    tube("shower_arm", [(ex, 0.0, 1.72), (ex + 0.1, 0.0, 1.72), (ex + 0.14, 0.0, 1.68)], 0.011, "chrome", sides=8)
    cy("shower_head", 0.022, 0.045, 0.05, (ex + 0.155, 0.0, 1.655), "chrome", verts=12, rot=(0, 35, 0))
    cy("valve_plate", 0.06, 0.06, 0.01, (ex + 0.005, 0.0, 1.15), "chrome", verts=14, rot=(0, 90, 0))
    cy("valve", 0.022, 0.018, 0.05, (ex + 0.03, 0.0, 1.15), "chrome", verts=10, rot=(0, 90, 0))
    tube("spout", [(ex, 0.0, 0.66), (ex + 0.09, 0.0, 0.66), (ex + 0.11, 0.0, 0.63)], 0.016, "chrome", sides=8)
    # the rail and the curtain, gathered to the right on its rings
    ry, rz = -D / 2 + 0.06, 1.84
    tube("rail", [(-W / 2 + wall, ry, rz), (W / 2 - wall, ry, rz)], 0.012, "chrome", sides=8, caps=False)
    cx0, cx1 = 0.28, W / 2 - wall - 0.01
    for i in range(6):
        x = cx0 + 0.01 + i * (cx1 - cx0 - 0.02) / 5
        K.torus("ring", 0.018, 0.0035, (x, ry, rz - 0.01), mat("chrome"), rot=(90, 0, 90), major=10, minor=4)
    nx, nz = 22, 6
    zt, zb = rz - 0.03, 0.55
    verts, faces, uvs = [], [], []
    for j in range(nz + 1):
        z = zb + (zt - zb) * j / nz
        for i in range(nx + 1):
            t = i / nx
            x = cx0 + (cx1 - cx0) * t
            y = ry + 0.035 * math.sin(t * nx * math.pi / 2) * (0.6 + 0.4 * (1 - j / nz))
            verts.append((x, y, z))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
            uvs += [(i / nx, j / nz), ((i + 1) / nx, j / nz), ((i + 1) / nx, (j + 1) / nz), (i / nx, (j + 1) / nz)]
    me = bpy.data.meshes.new("curtain")
    me.from_pydata(verts, [], faces)
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", [c for uv in uvs for c in uv])
    ob = K._obj("curtain", me, mat("curtain"))
    K.smooth(ob, keep_sharp=False)
    sol = ob.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.006
    K.apply_mods(ob)


# --- rec room ------------------------------------------------------------------------------------

def build_pinball_machine():
    W = 0.72
    hw = W / 2
    # the cabinet's side profile (y, z): lower at the player's end (-Y), rising to the back
    yf, yb, zbf, zbb, ztf, ztb = -0.64, 0.58, 0.6, 0.64, 0.9, 1.02
    prof = [(yf, zbf), (yb, zbb), (yb, ztb), (yf, ztf)]
    body = K.extrude_xz("cabinet", [(y, z) for y, z in prof], -hw, hw, mat("purple"), bevel=0.012)
    body.rotation_euler = (0, 0, math.radians(90))   # profile x -> world y; thickness -> world -x
    bpy.context.view_layer.update()
    K.uv_box(body, 1.5)
    for s in (-1, 1):
        inset = [(yf + 0.03, zbf + 0.03), (yb - 0.03, zbb + 0.03), (yb - 0.03, ztb - 0.04), (yf + 0.03, ztf - 0.04)]
        poly_x("side_art", inset, s * (hw + 0.002), "side_art", s)
    # the playfield under the glass, with chrome side rails and the lockdown bar
    slope = math.atan2(ztb - ztf, yb - yf)
    def zt(y):
        return ztf + (ztb - ztf) * (y - yf) / (yb - yf)
    py0, py1 = yf + 0.06, yb - 0.04
    quad("playfield", [(-hw + 0.03, py0, zt(py0) - 0.012), (hw - 0.03, py0, zt(py0) - 0.012), (hw - 0.03, py1, zt(py1) - 0.012), (-hw + 0.03, py1, zt(py1) - 0.012)], "playfield")
    quad("glass", [(-hw + 0.02, py0, zt(py0) + 0.004), (hw - 0.02, py0, zt(py0) + 0.004), (hw - 0.02, py1, zt(py1) + 0.004), (-hw + 0.02, py1, zt(py1) + 0.004)], "glass")
    L = math.hypot(yb - yf, ztb - ztf)
    for s in (-1, 1):
        bx("rail", (0.03, L, 0.02), (s * (hw - 0.012), (yf + yb) / 2, (ztf + ztb) / 2 + 0.008), "chrome", bevel=0.006, rot=(math.degrees(slope), 0, 0))
    bx("lockdown", (W + 0.01, 0.07, 0.03), (0, yf + 0.03, ztf + 0.01), "chrome", bevel=0.01)
    # pop bumpers, slingshots and flippers seen through the glass
    for (x, y, c) in ((-0.12, 0.18, "lit_red"), (0.12, 0.18, "lit_yellow"), (0.0, 0.3, "lit_red")):
        z = zt(y) - 0.012
        cy("bumper", 0.045, 0.045, 0.025, (x, y, z + 0.012), "white_paint", verts=12)
        cy("bumper_cap", 0.04, 0.03, 0.02, (x, y, z + 0.034), c, verts=12)
    for s in (-1, 1):
        y = yf + 0.2
        bx("flipper", (0.1, 0.022, 0.02), (s * 0.07, y, zt(y)), "white_paint", bevel=0.008, rot=(0, 0, s * -25))
        y2 = yf + 0.32
        bx("slingshot", (0.03, 0.14, 0.03), (s * 0.18, y2, zt(y2)), "lit_yellow", bevel=0.01, rot=(0, 0, s * 20))
    # the coin door, plunger and flipper buttons at the front
    fz = (zbf + ztf) / 2
    bx("coin_door", (0.3, 0.02, 0.2), (0, yf - 0.008, fz - 0.02), "charcoal", bevel=0.008)
    for s in (-1, 1):
        bx("coin_slot", (0.05, 0.012, 0.06), (s * 0.065, yf - 0.02, fz + 0.01), "lit_red", bevel=0.004)
    cy("plunger_boss", 0.025, 0.025, 0.02, (0.26, yf - 0.01, ztf - 0.07), "chrome", verts=10, rot=(90, 0, 0))
    cy("plunger", 0.01, 0.01, 0.08, (0.26, yf - 0.05, ztf - 0.07), "chrome", verts=8, rot=(90, 0, 0))
    cy("plunger_knob", 0.018, 0.018, 0.03, (0.26, yf - 0.09, ztf - 0.07), "red", verts=10, rot=(90, 0, 0))
    for s in (-1, 1):
        cy("flip_button", 0.014, 0.014, 0.02, (s * (hw + 0.008), yf + 0.1, ztf - 0.07), "red", verts=8, rot=(0, 90, 0))
    # chrome legs with black levellers
    for x in (-hw + 0.03, hw - 0.03):
        for y, ztop in ((yf + 0.06, zbf), (yb - 0.06, zbb)):
            bx("leg", (0.05, 0.05, ztop + 0.02), (x * 1.02, y, (ztop + 0.02) / 2 + 0.015), "chrome", bevel=0.01)
            cy("foot", 0.03, 0.025, 0.02, (x * 1.02, y, 0.01), "rubber", verts=10)
            bx("leg_bracket", (0.012, 0.09, 0.09), (x + math.copysign(0.004, x), y, ztop + 0.03), "chrome", bevel=0.004)
    # the backbox: a speaker panel and the lit backglass, purple sides with the art
    by0, by1, bz0, bz1 = yb - 0.22, yb + 0.07, ztb - 0.02, 1.9
    bx("backbox", (W, by1 - by0, bz1 - bz0), (0, (by0 + by1) / 2, (bz0 + bz1) / 2), "purple", bevel=0.015, scale=1)
    for s in (-1, 1):
        poly_x("backbox_art", [(by0 + 0.02, bz0 + 0.03), (by1 - 0.02, bz0 + 0.03), (by1 - 0.02, bz1 - 0.03), (by0 + 0.02, bz1 - 0.03)], s * (hw + 0.002), "side_art", s)
    pane("speaker", (-hw + 0.05, by0 - 0.002, bz0 + 0.04), (hw - 0.05, by0 - 0.002, bz0 + 0.17), "speaker")
    bx("glass_trim", (W - 0.02, 0.02, 0.66), (0, by0 - 0.005, bz1 - 0.37), "black", bevel=0.006)
    pane("backglass", (-hw + 0.04, by0 - 0.017, bz0 + 0.21), (hw - 0.04, by0 - 0.017, bz1 - 0.06), "backglass")


def build_crt_tv():
    W, D = 0.9, 0.5
    SH = 0.5  # the stand's height
    # the stand: a top, a bottom, sides, a back, one middle shelf, little round feet
    t = 0.025
    bx("stand_top", (W, D, t), (0, 0, SH - t / 2), "black", bevel=0.008, scale=1)
    bx("stand_base", (W, D, t), (0, 0, 0.06), "black", bevel=0.008, scale=1)
    for s in (-1, 1):
        bx("stand_side", (t, D, SH - 0.05), (s * (W / 2 - t / 2), 0, (SH + 0.05) / 2), "black", bevel=0.006, scale=1)
    bx("stand_back", (W - 2 * t, 0.012, SH - 0.08), (0, D / 2 - 0.006, (SH + 0.05) / 2), "black", bevel=0.0)
    bx("stand_shelf", (W - 2 * t, D - 0.03, 0.018), (0, -0.01, 0.29), "black", bevel=0.005)
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for y in (-D / 2 + 0.06, D / 2 - 0.06):
            bl("foot", 0.025, (x, y, 0.025), "black", u=8, v=5)
    # a VCR on the middle shelf, tapes and books below
    bx("vcr", (0.42, 0.3, 0.08), (0.05, 0.0, 0.299 + 0.04), "black", bevel=0.008)
    pane("vcr_face", (-0.16, -0.151, 0.305), (0.26, -0.151, 0.375), "vcr")
    x = -0.38
    for i, (w, h, c) in enumerate(((0.03, 0.2, "blue"), (0.025, 0.18, "red"), (0.03, 0.21, "yellow"), (0.028, 0.19, "violet"), (0.03, 0.2, "green"), (0.025, 0.17, "orange"))):
        bx("book", (w, 0.17, h), (x + w / 2, -0.05, 0.0725 + h / 2), c, bevel=0.004)
        x += w + 0.004
    for k in range(3):
        bx("tape", (0.19, 0.105, 0.025), (0.18, -0.06, 0.0725 + 0.0125 + k * 0.026), "black" if k != 1 else "charcoal", bevel=0.003)
    # the set: a deep tapered charcoal body, the bezel, a recessed screen, a control strip
    TW, TD, TH = 0.68, 0.48, 0.56
    z0 = SH
    yf = -D / 2 + 0.02
    bx("bezel", (TW, 0.12, TH), (0, yf + 0.06, z0 + TH / 2), "charcoal", bevel=0.03, scale=1)
    back = K.box("tv_back", (TW - 0.04, TD - 0.12, TH - 0.04), (0, yf + 0.12 + (TD - 0.12) / 2, z0 + TH / 2 - 0.01), mat("charcoal"), bevel=0.02, seg=1)
    for v_ in back.data.vertices:
        if v_.co.y > 0:  # the tube's funnel narrows to the back
            v_.co.x *= 0.62
            v_.co.z = v_.co.z * 0.7 + 0.02
    K.uv_box(back, 1.0)
    sw, sh_ = 0.5, 0.38
    sz = z0 + TH / 2 + 0.04
    bx("screen_recess", (sw + 0.04, 0.02, sh_ + 0.04), (0, yf - 0.002, sz), "black", bevel=0.015)
    pane("screen", (-sw / 2, yf - 0.014, sz - sh_ / 2), (sw / 2, yf - 0.014, sz + sh_ / 2), "crt")
    for i in range(5):
        bx("button", (0.025, 0.01, 0.012), (0.04 + i * 0.035, yf - 0.002, z0 + 0.05), "black", bevel=0.003)
    bl("power_led", 0.005, (-0.2, yf - 0.002, z0 + 0.05), "lit_red", u=6, v=4)
    pane("tv_speaker", (-0.26, yf - 0.002, z0 + 0.03), (-0.06, yf - 0.002, z0 + 0.07), "speaker")


# --- garage --------------------------------------------------------------------------------------

def build_workbench():
    W, D, H = 1.8, 0.66, 0.9
    yb = D / 2
    # the top: two thick planks with a front apron
    bx("top", (W, D, 0.06), (0, 0, H - 0.03), "pine", bevel=0.01, grain="x", scale=0.8)
    bx("apron", (W - 0.1, 0.03, 0.1), (0, -D / 2 + 0.06, H - 0.11), "pine", bevel=0.006, grain="x", scale=0.8)
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for y in (-D / 2 + 0.06, yb - 0.06):
            bx("leg", (0.08, 0.08, H - 0.06), (x, y, (H - 0.06) / 2), "pine", bevel=0.008, scale=0.8)
    # the shelf below on rails
    bx("shelf", (W - 0.06, D - 0.04, 0.03), (0, 0, 0.16), "pine", bevel=0.006, grain="x", scale=0.8)
    for y in (-D / 2 + 0.06, yb - 0.06):
        bx("rail", (W - 0.12, 0.04, 0.08), (0, y, 0.12), "pine", bevel=0.006, grain="x", scale=0.8)
    # bolt heads on the top's front edge
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for z in (H - 0.11, 0.12):
            bl("bolt", 0.009, (x, -D / 2 + 0.018, z), "steel_grey", scale=(1, 0.5, 1), u=6, v=4)
    # the pegboard on two uprights at the back, in a pine frame
    py = yb - 0.03
    pz0, pz1 = H + 0.06, 1.86
    for s in (-1, 1):
        bx("upright", (0.06, 0.05, pz1 - H + 0.02), (s * (W / 2 - 0.06), py, (pz1 + H) / 2), "pine", bevel=0.006, scale=0.8)
    bx("frame_top", (W - 0.06, 0.05, 0.06), (0, py, pz1 - 0.03), "pine", bevel=0.006, grain="x", scale=0.8)
    bx("frame_bot", (W - 0.06, 0.05, 0.06), (0, py, pz0 + 0.03), "pine", bevel=0.006, grain="x", scale=0.8)
    bx("board_back", (W - 0.18, 0.008, pz1 - pz0 - 0.1), (0, py + 0.004, (pz0 + pz1) / 2), "pine", bevel=0.0)
    pane("pegboard", (-W / 2 + 0.09, py - 0.005, pz0 + 0.06), (W / 2 - 0.09, py - 0.005, pz1 - 0.06), "pegboard")
    fy = py - 0.02
    # tools on the pegboard: hammer, pliers, wrench, three screwdrivers, a saw, a tape and a cord
    hz = 1.45
    bx("hammer_handle", (0.03, 0.02, 0.26), (-0.66, fy, hz - 0.05), "pine", bevel=0.008)
    bx("hammer_head", (0.13, 0.03, 0.035), (-0.66, fy, hz + 0.09), "steel_grey", bevel=0.008)
    for s in (-1, 1):
        bx("plier_grip", (0.022, 0.016, 0.13), (-0.42 + s * 0.025, fy, hz - 0.05), "red", bevel=0.007, rot=(0, s * 12, 0))
        bx("plier_jaw", (0.016, 0.014, 0.08), (-0.42 + s * 0.007, fy, hz + 0.07), "steel_grey", bevel=0.005, rot=(0, -s * 10, 0))
    bx("wrench", (0.026, 0.012, 0.26), (-0.2, fy, hz), "steel_grey", bevel=0.006)
    K.torus("wrench_ring", 0.03, 0.01, (-0.2, fy, hz + 0.14), mat("steel_grey"), rot=(90, 0, 0), major=12, minor=4)
    for i, x in enumerate((-0.02, 0.05, 0.12)):
        cy("driver_grip", 0.016, 0.016, 0.09, (x, fy, hz + 0.08), "yellow", verts=8)
        cy("driver_shaft", 0.004, 0.004, 0.13, (x, fy, hz - 0.03), "steel_grey", verts=6)
    saw = K.extrude_xz("saw_blade", [(0.3, 1.2), (0.36, 1.2), (0.56, 1.58), (0.5, 1.62)], fy - 0.002, fy + 0.002, mat("steel_grey"), bevel=0.0)
    K.uv_box(saw, 3)
    bx("saw_handle", (0.1, 0.025, 0.12), (0.56, fy, 1.64), "red", bevel=0.015, rot=(0, -28, 0))
    bx("tape", (0.07, 0.04, 0.07), (-0.1, fy, 1.18), "yellow", bevel=0.015)
    K.torus("cord", 0.08, 0.016, (0.3, fy - 0.01, 1.15), mat("hose_orange"), rot=(90, 0, 0), major=16, minor=5)
    for ox in (-0.66, -0.42, -0.2, 0.05, 0.43, 0.3):
        cy("peg", 0.004, 0.004, 0.03, (ox, fy + 0.005, hz + 0.17 if ox != 0.3 else 1.25), "steel_grey", verts=5, rot=(90, 0, 0))
    # three toolboxes on the shelf
    for x, c, w in ((-0.55, "red", 0.4), (-0.05, "green", 0.36), (0.42, "blue", 0.34)):
        bx("toolbox", (w, 0.24, 0.16), (x, -0.02, 0.175 + 0.08), c, bevel=0.012)
        bx("toolbox_lid", (w + 0.01, 0.25, 0.03), (x, -0.02, 0.175 + 0.17), c, bevel=0.01)
        bx("toolbox_handle", (w * 0.5, 0.02, 0.02), (x, -0.02, 0.175 + 0.2), "black", bevel=0.006)
        bx("toolbox_latch", (0.04, 0.01, 0.03), (x, -0.145, 0.175 + 0.15), "steel_grey", bevel=0.004)


def build_garage_shelf():
    W, D, H = 1.2, 0.45, 1.8
    post = 0.035
    for x in (-W / 2 + post / 2, W / 2 - post / 2):
        for y in (-D / 2 + post / 2, D / 2 - post / 2):
            # angle posts: two flanges
            bx("post_a", (post, 0.004, H), (x, y + math.copysign(post / 2 - 0.002, -y), H / 2), "steel_grey", bevel=0.0)
            bx("post_b", (0.004, post, H), (x + math.copysign(post / 2 - 0.002, -x), y, H / 2), "steel_grey", bevel=0.0)
            bx("foot", (post + 0.01, post + 0.01, 0.01), (x, y, 0.005), "rubber", bevel=0.002)
    levels = (0.12, 0.6, 1.08, 1.56)
    for z in levels:
        bx("shelf", (W - 0.01, D - 0.01, 0.012), (0, 0, z), "steel_grey", bevel=0.002, scale=2)
        for y in (-D / 2 + 0.01, D / 2 - 0.01):
            bx("shelf_lip", (W - 0.01, 0.012, 0.04), (0, y, z - 0.014), "steel_grey", bevel=0.002)
    rng = np.random.default_rng(3)
    # cardboard boxes, taped
    def carton(x, z, w, d, h, rot=0.0):
        bx("carton", (w, d, h), (x, 0.0, z + h / 2), "kraft", bevel=0.01, rot=(0, 0, rot), scale=2)
        bx("tape", (0.05, d + 0.004, 0.004), (x, 0.0, z + h + 0.001), "cream", bevel=0.0, rot=(0, 0, rot))
    carton(-0.32, levels[0] + 0.006, 0.42, 0.36, 0.34)
    carton(0.2, levels[0] + 0.006, 0.5, 0.38, 0.3, 4)
    carton(-0.3, levels[2] + 0.006, 0.36, 0.34, 0.28, -5)
    carton(-0.32, levels[3] + 0.006, 0.34, 0.32, 0.18, 3)
    # paint cans on the second shelf
    for i, c in enumerate(("can_blue", "can_green", "can_cream", "can_red", "can_blue")):
        x = -0.46 + i * 0.2 + rng.uniform(-0.02, 0.02)
        z = levels[1] + 0.006
        cy("can", 0.085, 0.085, 0.19, (x, -0.04, z + 0.095), "steel_grey", verts=14)
        cy("label", 0.087, 0.087, 0.12, (x, -0.04, z + 0.09), "label_" + c, verts=14)
        cy("lid", 0.08, 0.08, 0.008, (x, -0.04, z + 0.193), "chrome", verts=14)
        bx("bail", (0.17, 0.004, 0.004), (x, -0.04, z + 0.2), "steel_grey", bevel=0.0)
    # a red toolbox on the top shelf, a green bin on the third
    bx("toolbox", (0.3, 0.17, 0.13), (0.26, -0.02, levels[3] + 0.071), "red", bevel=0.012)
    bx("toolbox_lid", (0.31, 0.18, 0.025), (0.26, -0.02, levels[3] + 0.148), "red", bevel=0.008)
    bx("toolbox_handle", (0.14, 0.02, 0.025), (0.26, -0.02, levels[3] + 0.175), "steel_grey", bevel=0.006)
    bx("bin", (0.4, 0.32, 0.18), (0.24, -0.02, levels[2] + 0.096), "green", bevel=0.015)
    bx("bin_lip", (0.42, 0.34, 0.02), (0.24, -0.02, levels[2] + 0.18), "green", bevel=0.006)


# --- toys ----------------------------------------------------------------------------------------

def build_teddy_bear():
    bl("body", 0.095, (0, 0, 0.115), "plush", scale=(1.0, 0.88, 1.15), u=14, v=9)
    bl("head", 0.078, (0, -0.005, 0.255), "plush", scale=(1.05, 0.95, 0.95), u=14, v=9)
    bl("muzzle", 0.036, (0, -0.072, 0.238), "tan", scale=(1.15, 0.85, 0.8), u=10, v=7)
    bl("nose", 0.013, (0, -0.1, 0.25), "eye", scale=(1.3, 0.8, 0.9), u=8, v=5)
    for s in (-1, 1):
        bl("eye", 0.009, (s * 0.032, -0.068, 0.275), "eye", u=8, v=5)
        bl("ear", 0.03, (s * 0.06, 0.0, 0.32), "plush", scale=(1, 0.55, 1), u=10, v=6)
        bl("ear_in", 0.019, (s * 0.06, -0.014, 0.318), "tan", scale=(1, 0.4, 1), u=8, v=5)
        arm = bl("arm", 0.04, (s * 0.098, -0.035, 0.135), "plush", scale=(0.8, 0.8, 1.55), u=10, v=7)
        arm.rotation_euler = (math.radians(-25), math.radians(s * 22), 0)
        bl("leg", 0.045, (s * 0.058, -0.075, 0.042), "plush", scale=(0.85, 1.5, 0.85), u=10, v=7)
        pad = K.disc("foot_pad", 0.03, 0, mat("tan"), steps=12)
        pad.location = (s * 0.058, -0.14, 0.044)
        pad.rotation_euler = (math.radians(90), 0, 0)
        pad.scale = (0.95, 1.15, 1)
        K.uv_box(pad, 4)
    # the red bow at the neck
    for s in (-1, 1):
        bl("bow_loop", 0.026, (s * 0.03, -0.075, 0.19), "red", scale=(1.2, 0.5, 0.8), u=10, v=6)
        tube("bow_tail", [(s * 0.008, -0.08, 0.185), (s * 0.02, -0.088, 0.15)], 0.009, "red", sides=5)
    bl("bow_knot", 0.014, (0, -0.088, 0.19), "red", u=8, v=5)


def build_toy_blocks():
    """A pyramid of six as on the reference: D E F on the floor, B C on them, A on top. Each block
    is its colour with a cream face panel on every side and the letter raised in its colour."""
    s = 0.065
    cols = {"A": "red", "B": "blue", "C": "yellow", "D": "green", "E": "red", "F": "blue"}
    spots = {"D": (-0.068, 0.004, 0, -4), "E": (0.0, -0.004, 0, 3), "F": (0.068, 0.0, 0, -2),
             "B": (-0.034, 0.002, 1, 5), "C": (0.036, -0.003, 1, -6), "A": (0.0, 0.0, 2, 8)}
    for ch, (x, y, layer, yaw) in spots.items():
        c = cols[ch]
        parts = [bx("block", (s, s, s), (0, 0, 0), c, bevel=0.006, scale=8)]
        # cream panels on the four sides and the top (the base is hidden)
        for loc, size in (((0, -s / 2 - 0.001, 0), (s - 0.016, 0.002, s - 0.016)), ((0, s / 2 + 0.001, 0), (s - 0.016, 0.002, s - 0.016)),
                          ((s / 2 + 0.001, 0, 0), (0.002, s - 0.016, s - 0.016)), ((-s / 2 - 0.001, 0, 0), (0.002, s - 0.016, s - 0.016)),
                          ((0, 0, s / 2 + 0.001), (s - 0.016, s - 0.016, 0.002))):
            parts.append(bx("panel", size, loc, "cream", bevel=0.0))
        parts.append(letter("letter", ch, 0.042, (0, -s / 2 - 0.0035, 0), (90, 0, 0), c))
        other = "ABCDEF"[("ABCDEF".index(ch) + 3) % 6]
        parts.append(letter("letter", other, 0.042, (s / 2 + 0.0035, 0, 0), (90, 0, 90), c))
        mtx = Matrix.Translation((x, y, s / 2 + layer * (s + 0.001))) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for p in parts:
            p.matrix_world = mtx @ p.matrix_world


def build_toy_truck():
    L = 0.35
    # chassis, cab at -X, dump bed at +X, tipped up a little
    bx("chassis", (L - 0.02, 0.12, 0.03), (0, 0, 0.06), "black", bevel=0.006)
    bx("cab", (0.11, 0.15, 0.1), (-0.1, 0, 0.125), "red", bevel=0.02, scale=4)
    bx("cab_roof", (0.08, 0.15, 0.03), (-0.095, 0, 0.19), "red", bevel=0.012, scale=4)
    bx("hood", (0.06, 0.14, 0.06), (-0.15, 0, 0.1), "red", bevel=0.015, scale=4)
    for s in (-1, 1):
        pane("window", (-0.13, s * 0.0765, 0.14), (-0.07, s * 0.0765, 0.19), "crt", out=(0, s, 0))
    pane("windscreen", (-0.07, -0.07, 0.14), (-0.07, 0.07, 0.19), "crt", out=(1, 0, 0))
    bx("grille", (0.006, 0.1, 0.04), (-0.181, 0, 0.1), "chrome", bevel=0.002)
    for s in (-1, 1):
        bl("headlight", 0.012, (-0.18, s * 0.05, 0.11), "lit_yellow", u=8, v=5)
    bx("bumper", (0.02, 0.15, 0.025), (-0.18, 0, 0.065), "yellow", bevel=0.008)
    bed = []
    bx("bed_floor", (0.18, 0.16, 0.012), (0.075, 0, 0.09), "yellow", bevel=0.004)
    for s in (-1, 1):
        bx("bed_side", (0.18, 0.012, 0.08), (0.075, s * 0.074, 0.135), "yellow", bevel=0.004)
    bx("bed_front", (0.012, 0.16, 0.1), (-0.015, 0, 0.145), "yellow", bevel=0.004)
    bx("bed_tail", (0.012, 0.16, 0.07), (0.159, 0, 0.13), "yellow", bevel=0.004)
    for o in [o for o in K.COLL.objects if o.name.startswith("bed_")]:
        o.matrix_world = Matrix.Translation((-0.015, 0, 0.09)) @ Matrix.Rotation(math.radians(-8), 4, "Y") @ Matrix.Translation((0.015, 0, -0.09)) @ o.matrix_world
    bx("piston", (0.012, 0.012, 0.05), (0.0, 0, 0.09), "chrome", bevel=0.003)
    for x in (-0.12, 0.1):
        for s in (-1, 1):
            cy("tyre", 0.048, 0.048, 0.034, (x, s * 0.075, 0.048), "rubber", verts=14, rot=(90, 0, 0))
            cy("hub", 0.024, 0.024, 0.036, (x, s * 0.075, 0.048), "yellow", verts=10, rot=(90, 0, 0))


def build_rocking_horse():
    # the rockers: two shallow arcs joined by two slats
    for s in (-1, 1):
        pts = []
        for i in range(13):
            x = -0.42 + 0.84 * i / 12
            pts.append((x, s * 0.13, 0.024 + (1.0 - math.sqrt(1 - x * x))))
        tube("rocker", pts, 0.024, "oak", sides=6)
        for x in (-0.36, 0.0, 0.36):
            bl("rocker_dot", 0.01, (x, s * 0.152, 0.03 + (1.0 - math.sqrt(1 - x * x))), "yellow", u=8, v=5)
    for x in (-0.24, 0.24):
        z = 0.024 + (1.0 - math.sqrt(1 - x * x)) + 0.02
        bx("slat", (0.06, 0.3, 0.025), (x, 0, z), "oak", bevel=0.006)
    # legs from the body to the slats
    for x in (-0.18, 0.18):
        for s in (-1, 1):
            top = Vector((x * 0.85, s * 0.07, 0.37))
            bot = Vector((x * 1.25, s * 0.1, 0.07 + (1.0 - math.sqrt(1 - (x * 1.25) ** 2))))
            tube("leg", [bot, top], [0.032, 0.042], "dapple", sides=10)
            bl("hoof", 0.034, tuple(bot), "oak", scale=(1, 1, 0.6), u=8, v=5)
    # body, neck and head in dappled white
    bl("body", 0.13, (0.01, 0, 0.42), "dapple", scale=(1.55, 0.92, 0.88), u=16, v=10)
    tube("neck", [(-0.15, 0, 0.43), (-0.21, 0, 0.53), (-0.24, 0, 0.6)], [0.085, 0.072, 0.06], "dapple", sides=10)
    bl("head", 0.075, (-0.29, 0, 0.615), "dapple", scale=(1.3, 0.78, 0.8), u=12, v=8)
    bl("muzzle", 0.05, (-0.37, 0, 0.595), "dapple", scale=(1.0, 0.9, 0.9), u=10, v=7)
    for s in (-1, 1):
        bl("eye", 0.012, (-0.3, s * 0.056, 0.645), "eye", u=8, v=5)
        bl("nostril", 0.008, (-0.415, s * 0.022, 0.6), "eye", u=6, v=4)
        cy("ear", 0.018, 0.004, 0.05, (-0.25, s * 0.028, 0.685), "dapple", verts=8, rot=(s * -12, 0, 0))
        cy("handle_knob", 0.014, 0.014, 0.025, (-0.27, s * 0.085, 0.6), "red", verts=8, rot=(90, 0, 0))
    cy("handle", 0.008, 0.008, 0.16, (-0.27, 0, 0.6), "red", verts=8, rot=(90, 0, 0))
    K.torus("bridle_nose", 0.048, 0.006, (-0.37, 0, 0.595), mat("red"), rot=(0, 90, 0), major=14, minor=4).scale = (1, 0.95, 1.05)
    K.torus("bridle_cheek", 0.068, 0.006, (-0.3, 0, 0.62), mat("red"), rot=(0, 75, 0), major=14, minor=4).scale = (1, 0.8, 1.1)
    # the yarn mane along the crest, a yarn tail, the red saddle and its blanket
    # yarn strands falling from the crest down both sides of the neck, and a forelock
    for i in range(8):
        t = i / 7
        p = Vector((-0.27 + 0.14 * t, 0, 0.685 - 0.2 * t))
        for sd in (-1, 1):
            tube("mane", [p, p + Vector((0.02, sd * 0.045, -0.02)), p + Vector((0.03, sd * 0.06, -0.09))], [0.014, 0.012, 0.008], "mane", sides=5)
    tube("forelock", [(-0.28, 0, 0.69), (-0.32, 0, 0.68), (-0.34, 0, 0.65)], [0.014, 0.012, 0.008], "mane", sides=5)
    tube("tail", [(0.19, 0, 0.45), (0.24, 0, 0.42), (0.27, 0, 0.33), (0.26, 0, 0.27)], [0.03, 0.036, 0.028, 0.014], "mane", sides=8)
    bl("saddle", 0.1, (0.02, 0, 0.52), "red", scale=(1.0, 1.2, 0.3), u=14, v=7)
    K.torus("saddle_trim", 0.1, 0.007, (0.02, 0, 0.512), mat("yellow"), major=20, minor=4).scale = (1.0, 1.2, 1.0)
    for s in (-1, 1):
        bx("girth", (0.03, 0.006, 0.16), (0.02, s * 0.118, 0.43), "red", bevel=0.0)


def build_toy_ball():
    r = 0.125
    prof = [(r * math.sin(math.pi * i / 12), r - r * math.cos(math.pi * i / 12)) for i in range(13)]
    prof[0] = (0.0, 0.0)
    prof[-1] = (0.0, 2 * r)
    K.lathe("ball", prof, mat("ball"), steps=24, sharp=89)


def build_toy_train():
    """The engine at -X (red boiler, green cab with a yellow roof, blue chimney and cowcatcher),
    then a blue and a red open wagon, all on chunky yellow-hubbed wheels."""
    bx("eng_chassis", (0.19, 0.08, 0.03), (-0.155, 0, 0.05), "blue", bevel=0.006)
    cy("boiler", 0.04, 0.04, 0.12, (-0.185, 0, 0.1), "red", verts=14, rot=(0, 90, 0))
    cy("boiler_front", 0.03, 0.03, 0.012, (-0.248, 0, 0.1), "yellow", verts=12, rot=(0, 90, 0))
    bx("cab", (0.075, 0.09, 0.11), (-0.09, 0, 0.12), "green", bevel=0.008)
    bx("cab_roof", (0.095, 0.11, 0.018), (-0.09, 0, 0.183), "yellow", bevel=0.006)
    for s in (-1, 1):
        pane("cab_window", (-0.11, s * 0.0455, 0.125), (-0.07, s * 0.0455, 0.158), "crt", out=(0, s, 0))
    cy("chimney", 0.016, 0.022, 0.06, (-0.22, 0, 0.165), "blue", verts=10)
    cy("chimney_cap", 0.026, 0.026, 0.012, (-0.22, 0, 0.2), "blue", verts=10)
    bx("cowcatcher", (0.035, 0.09, 0.035), (-0.262, 0, 0.04), "blue", bevel=0.008, rot=(0, -25, 0))
    for x, c in ((0.03, "blue"), (0.18, "red")):
        bx("wagon_floor", (0.12, 0.08, 0.012), (x, 0, 0.056), c, bevel=0.004)
        for sy in (-1, 1):
            bx("wagon_side", (0.12, 0.01, 0.055), (x, sy * 0.035, 0.088), c, bevel=0.004)
        for sx in (-1, 1):
            bx("wagon_end", (0.01, 0.08, 0.055), (x + sx * 0.055, 0, 0.088), c, bevel=0.004)
    for x in (-0.05, 0.105):
        cy("coupling", 0.007, 0.007, 0.04, (x, 0, 0.055), "black", verts=6, rot=(0, 90, 0))
    for x in (-0.2, -0.12, -0.005, 0.065, 0.145, 0.215):
        for s in (-1, 1):
            cy("wheel", 0.026, 0.026, 0.014, (x, s * 0.046, 0.026), "orange", verts=12, rot=(90, 0, 0))
            cy("wheel_hub", 0.011, 0.011, 0.016, (x, s * 0.046, 0.026), "yellow", verts=8, rot=(90, 0, 0))


# --- the counter modules, the doors (from ref/lineup_3) -----------------------------------------

def pull(x, y, z):
    """A brass bar pull on two posts, across a door or drawer at height z."""
    bx("pull", (0.09, 0.012, 0.014), (x, y - 0.024, z), "brass", bevel=0.005)
    for dx in (-0.035, 0.035):
        bx("pull_post", (0.01, 0.024, 0.01), (x + dx, y - 0.012, z), "brass", bevel=0.002)


def counter_module(top_cut=None):
    """The base-cabinet run of lineup_3, kitchen_counter_90s's size without its wall cabinets: a
    drawer over a door at each end, a wide false front over two doors in the middle, brass bar
    pulls and hinges, a white laminate top with a backsplash. Returns the top, the middle bay's
    centre x and its false front's height, for the sink or cooktop that goes into it."""
    W, D, H = 2.4, 0.62, 0.91
    x0, x1 = -W / 2 + 0.03, W / 2 - 0.03
    yb, yf = D / 2, -D / 2 + 0.05
    base_run(x0, x1, yf, yb, H - 0.04)
    df = yf - 0.02
    zt = H - 0.06
    cols = ((x0, x0 + 0.62), (x0 + 0.64, x1 - 0.64), (x1 - 0.62, x1))
    for i, (a, b) in enumerate(cols):
        mid = (a + b) / 2
        door("drawer", a + 0.005, b - 0.005, zt - 0.15, zt, df)
        if i != 1:
            pull(mid, df, zt - 0.075)
        doors = [(a + 0.005, b - 0.005)] if i != 1 else [(a + 0.005, mid - 0.003), (mid + 0.003, b - 0.005)]
        for j, (da, db) in enumerate(doors):
            door("door", da, db, 0.1, zt - 0.17, df)
            hinge_left = (i == 0) or (i == 1 and j == 0)
            hx = da + 0.012 if hinge_left else db - 0.012
            px = db - 0.05 if hinge_left else da + 0.05
            bx("pull_v", (0.014, 0.012, 0.09), (px, df - 0.024, zt - 0.28), "brass", bevel=0.005)
            for dz in (-0.035, 0.035):
                bx("pull_post", (0.01, 0.024, 0.01), (px, df - 0.012, zt - 0.28 + dz), "brass", bevel=0.002)
            for z in (0.17, zt - 0.24):
                bx("hinge", (0.012, 0.012, 0.05), (hx, df - 0.003, z), "brass", bevel=0.003)
    top = bx("top", (W, D, 0.04), (0, 0, H - 0.02), "laminate", bevel=0.012, scale=1.0)
    bx("backsplash", (W, 0.025, 0.1), (0, D / 2 - 0.0125, H + 0.05), "laminate", bevel=0.008)
    return top, (cols[1][0] + cols[1][1]) / 2, zt - 0.075, df, H


def build_kitchen_counter_sink():
    top, cx, fz, df, H = counter_module()
    cut(top, K.box("sink_hole", (0.76, 0.42, 0.2), (cx, -0.02, H), mat("laminate"), bevel=0.04, seg=2))
    K.uv_box(top, 1.0)
    pull(cx, df, fz)
    rim = bx("sink_rim", (0.8, 0.46, 0.008), (cx, -0.02, H + 0.004), "stainless", bevel=0.004, scale=3)
    cut(rim, K.box("rim_hole", (0.74, 0.4, 0.1), (cx, -0.02, H), mat("stainless"), bevel=0.03, seg=2))
    for s in (-1, 1):
        sink_box("basin", 0.35, 0.39, 0.18, (cx + s * 0.185, -0.02, H - 0.08), "stainless")
    bx("divider", (0.02, 0.4, 0.012), (cx, -0.02, H + 0.002), "stainless", bevel=0.004)
    ty = 0.235
    bx("tap_deck", (0.26, 0.06, 0.02), (cx, ty, H + 0.01), "chrome", bevel=0.008)
    tube("tap_neck", [(cx, ty, H + 0.02), (cx, ty, H + 0.2), (cx, ty - 0.04, H + 0.25), (cx, ty - 0.12, H + 0.22), (cx, ty - 0.15, H + 0.17)], 0.011, "chrome", sides=8)
    for s in (-1, 1):
        cy("tap_handle", 0.018, 0.014, 0.04, (cx + s * 0.09, ty, H + 0.04), "chrome", verts=8)


def build_kitchen_counter_stove():
    top, cx, fz, df, H = counter_module()
    cut(top, K.box("hob_hole", (0.72, 0.48, 0.2), (cx, -0.0, H), mat("laminate"), bevel=0.0, seg=1))
    K.uv_box(top, 1.0)
    cooktop(cx, 0.0, H - 0.004, knobs_on_top=False)
    # the four knobs on the false front below the cooktop
    for kx in (-0.15, -0.05, 0.05, 0.15):
        cy("knob", 0.022, 0.02, 0.025, (cx + kx * 1.2, df - 0.012, fz), "black_gloss", verts=12, rot=(90, 0, 0))
        bx("knob_mark", (0.004, 0.004, 0.016), (cx + kx * 1.2, df - 0.026, fz + 0.006), "chrome", bevel=0.0)


def build_door_interior():
    """A white six-panel slab, 0.85 x 2.03 x 0.04, its origin at the foot of the hinge edge and the
    slab running along +X, so a turn about the vertical axis swings it. Panels on both faces, a
    brass knob each side, three brass hinge leaves on the hinge edge."""
    W, H, T = 0.85, 2.03, 0.04
    bx("slab", (W, T, H), (W / 2, 0, H / 2), "white_paint", bevel=0.004, scale=1.0)
    st, mul = 0.12, 0.1
    pw = (W - 2 * st - mul) / 2
    rows = ((0.2, 0.82), (0.91, 1.51), (1.6, 1.91))
    for side in (-1, 1):
        for z0, z1 in rows:
            for k in range(2):
                x = st + pw / 2 + k * (pw + mul)
                bx("panel", (pw, 0.008, z1 - z0), (x, side * (T / 2 + 0.002), (z0 + z1) / 2), "white_paint", bevel=0.012, scale=1.0)
        kx, kz = W - 0.065, 0.92
        cy("rose", 0.03, 0.03, 0.008, (kx, side * (T / 2 + 0.004), kz), "brass", verts=14, rot=(90, 0, 0))
        cy("stem", 0.01, 0.01, 0.04, (kx, side * (T / 2 + 0.025), kz), "brass", verts=8, rot=(90, 0, 0))
        bl("knob", 0.028, (kx, side * (T / 2 + 0.055), kz), "brass", scale=(1, 0.75, 1), u=12, v=7)
    for z in (0.25, 1.0, 1.78):
        bx("hinge", (0.006, 0.03, 0.09), (-0.001, 0, z), "brass", bevel=0.001)
        cy("hinge_knuckle", 0.006, 0.006, 0.09, (-0.004, 0, z), "brass", verts=6)


def build_sliding_door():
    """A white aluminium frame 1.8 x 2.05 along X, 0.11 deep, two glass panels: the left fixed in
    the back track, the right ("slide") in the front track, sliding along -X to open, its pull on
    its right stile. The glass material is called "glass" for the game to swap."""
    W, H, D = 1.8, 2.05, 0.11
    f = 0.05
    bx("head", (W, D, f), (0, 0, H - f / 2), "alu_white", bevel=0.006)
    bx("sill", (W, D + 0.02, f * 0.6), (0, 0, f * 0.3), "alu_white", bevel=0.006)
    for s in (-1, 1):
        bx("jamb", (f, D, H), (s * (W / 2 - f / 2), 0, H / 2), "alu_white", bevel=0.006)
        bx("track", (W - 2 * f, 0.006, 0.02), (0, s * 0.02, f * 0.6 + 0.01), "alu_white", bevel=0.0)
    pw = (W - 2 * f) / 2 + 0.03  # each panel, overlapping at the meeting stiles
    z0, z1 = f * 0.6 + 0.01, H - f - 0.005
    for name, xc, y in (("fixed", -(W / 2 - f) + pw / 2, 0.02), ("slide", (W / 2 - f) - pw / 2, -0.02)):
        st = 0.055
        bx(name + "_stile_l", (st, 0.035, z1 - z0), (xc - pw / 2 + st / 2, y, (z0 + z1) / 2), "alu_white", bevel=0.005)
        bx(name + "_stile_r", (st, 0.035, z1 - z0), (xc + pw / 2 - st / 2, y, (z0 + z1) / 2), "alu_white", bevel=0.005)
        bx(name + "_rail_b", (pw - 2 * st, 0.035, 0.08), (xc, y, z0 + 0.04), "alu_white", bevel=0.005)
        bx(name + "_rail_t", (pw - 2 * st, 0.035, 0.055), (xc, y, z1 - 0.0275), "alu_white", bevel=0.005)
        g = K.box(name + "_glass", (pw - 2 * st + 0.01, 0.008, z1 - z0 - 0.13), (xc, y, (z0 + 0.08 + z1 - 0.055) / 2), mat("door_glass"), bevel=0.0)
        K.uv_box(g, 1.0)
    px = (W / 2 - f) - 0.09
    bx("slide_pull", (0.025, 0.02, 0.22), (px, -0.02 - 0.03, 1.0), "charcoal", bevel=0.006)
    bx("slide_pull_plate", (0.04, 0.008, 0.26), (px, -0.02 - 0.019, 1.0), "alu_white", bevel=0.003)
    bx("slide_pull_in", (0.025, 0.012, 0.18), (px, -0.02 + 0.023, 1.0), "charcoal", bevel=0.004)


KINDS = {
    "kitchen_counter_90s": build_kitchen_counter_90s,
    "kitchen_island_90s": build_kitchen_island_90s,
    "fridge_90s": build_fridge_90s,
    "toilet": build_toilet,
    "bathroom_vanity": build_bathroom_vanity,
    "bathtub": build_bathtub,
    "pinball_machine": build_pinball_machine,
    "crt_tv": build_crt_tv,
    "workbench": build_workbench,
    "garage_shelf": build_garage_shelf,
    "teddy_bear": build_teddy_bear,
    "toy_blocks": build_toy_blocks,
    "toy_truck": build_toy_truck,
    "rocking_horse": build_rocking_horse,
    "toy_ball": build_toy_ball,
    "toy_train": build_toy_train,
    "kitchen_counter_sink": build_kitchen_counter_sink,
    "kitchen_counter_stove": build_kitchen_counter_stove,
    "door_interior": build_door_interior,
    "sliding_door": build_sliding_door,
}

# the size each should come out (width x depth x height, metres): make() fails if one is more
# than 12% off, so a slip in a constant can't reach the game unnoticed
TARGET = {
    "kitchen_counter_90s": (2.4, 0.62, 2.14),
    "kitchen_island_90s": (1.6, 0.9, 0.93),
    "fridge_90s": (0.8, 0.75, 1.75),
    "toilet": (0.5, 0.7, 0.8),
    "bathroom_vanity": (0.92, 0.55, 1.56),
    "bathtub": (1.5, 0.75, 1.93),
    "pinball_machine": (0.75, 1.4, 1.9),
    "crt_tv": (0.9, 0.5, 1.06),
    "workbench": (1.8, 0.66, 1.86),
    "garage_shelf": (1.2, 0.45, 1.8),
    "teddy_bear": (0.3, 0.25, 0.35),
    "toy_blocks": (0.21, 0.08, 0.2),
    "toy_truck": (0.36, 0.17, 0.2),
    "rocking_horse": (0.85, 0.32, 0.71),
    "toy_ball": (0.25, 0.25, 0.25),
    "toy_train": (0.52, 0.11, 0.21),
    "kitchen_counter_sink": (2.4, 0.62, 1.18),
    "kitchen_counter_stove": (2.4, 0.62, 1.01),
    "door_interior": (0.86, 0.19, 2.03),
    "sliding_door": (1.8, 0.13, 2.05),
}
# pieces exported as named nodes about their own origin instead of one centred "model":
# {kind: {node: name prefixes}}; the first node's origin is the model's origin
NODES = {
    "door_interior": {"door": ("",)},
    "sliding_door": {"frame": ("head", "sill", "jamb", "track", "fixed_"), "slide": ("slide_",)},
}
PIVOT = {"slide": None}  # None: the node's origin goes to its own bottom centre
BUDGET = {"kitchen_counter_90s": 12000, "kitchen_island_90s": 12000, "pinball_machine": 12000}


def recentre():
    """Puts the origin on the floor under the middle of the piece's bounding box."""
    bpy.context.view_layer.update()
    obs = [o for o in K.COLL.objects if o.type == "MESH"]
    co = [o.matrix_world @ v.co for o in obs for v in o.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    for o in obs:
        if o.parent is None:
            o.matrix_world = Matrix.Translation(shift) @ o.matrix_world


def finish_nodes(kind, out, nodes):
    """Like kelib.finish, but joins the pieces into the named nodes the game drives (a door slab
    called "door", a sliding panel called "slide"), each with its own origin, and exports them."""
    bpy.context.view_layer.update()
    obs = [o for o in K.COLL.objects if o.type == "MESH"]
    for o in obs:
        K.apply_mods(o)
        if "UVMap" not in o.data.uv_layers:
            if o.data.uv_layers:
                o.data.uv_layers[0].name = "UVMap"
            else:
                o.data.uv_layers.new(name="UVMap")
    names = [o.name for o in obs]
    taken, joined = set(), []
    # the most specific prefixes first, so "slide_" isn't swallowed by a shorter one
    for node, prefixes in sorted(nodes.items(), key=lambda kv: -max(len(p) for p in kv[1])):
        pick = [n for n in names if n not in taken and any(n.startswith(p) for p in prefixes)]
        taken.update(pick)
        parts = [bpy.data.objects[n] for n in pick]
        for o in bpy.context.view_layer.objects:
            o.select_set(o in parts)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        j.name, j.data.name = node, kind + "_" + node
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if node in PIVOT:
            co = [v.co for v in j.data.vertices]
            bpy.context.scene.cursor.location = ((min(c.x for c in co) + max(c.x for c in co)) / 2, (min(c.y for c in co) + max(c.y for c in co)) / 2, min(c.z for c in co))
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
            bpy.context.scene.cursor.location = (0, 0, 0)
        joined.append(j)
    left = [n for n in names if n not in taken]
    assert not left, "%s: pieces in no node: %s" % (kind, left)
    for o in K.COLL.objects:
        o.select_set(o in joined)
    os.makedirs(out, exist_ok=True)
    co = [o.matrix_world @ v.co for o in joined for v in o.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    st = {"name": kind, "triangles": sum(K.tri_count(o) for o in joined), "nodes": [o.name for o in joined],
          "materials": sorted({m.name for o in joined for m in o.data.materials}),
          "size_m": [round(a, 3) for a in hi - lo], "min_m": [round(a, 3) for a in lo], "max_m": [round(a, 3) for a in hi]}
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, kind + ".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, kind + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    st["glb_bytes"] = os.path.getsize(os.path.join(out, kind + ".glb"))
    with open(os.path.join(out, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(st, f, indent=2)
    print("[ke] " + json.dumps(st))
    if st["triangles"] > BUDGET.get(kind, 6000):
        raise SystemExit("%s has %d triangles" % (kind, st["triangles"]))


def make(kind):
    K.reset(kind)
    M.clear()
    KINDS[kind]()
    if kind != "door_interior":   # the door's origin stays on its hinge edge
        recentre()
    out = os.path.join(OUT, kind)
    if kind in NODES:
        finish_nodes(kind, out, NODES[kind])
    else:
        K.finish(kind, out, max_tris=BUDGET.get(kind, 6000))
    with open(os.path.join(out, "stats.json"), encoding="utf-8") as f:
        st = json.load(f)
    lo, hi = st["min_m"], st["max_m"]
    assert abs(lo[2]) < 0.002, "%s: base at z %.3f" % (kind, lo[2])
    if kind == "door_interior":
        assert abs(lo[0]) < 0.012 and abs(lo[1] + hi[1]) < 0.01, "%s: hinge edge not at the origin %s %s" % (kind, lo, hi)
    else:
        assert abs(lo[0] + hi[0]) < 0.01 and abs(lo[1] + hi[1]) < 0.01, "%s: not centred %s %s" % (kind, lo, hi)
    for axis, got, want in zip("xyz", st["size_m"], TARGET[kind]):
        assert abs(got - want) / want < 0.12, "%s: %s is %.3f m, wanted %.3f" % (kind, axis, got, want)
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(out, kind + ".glb"), os.path.join(PROPS, kind + ".glb"))
    print("COPIED", kind, st["size_m"], st["triangles"])


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for k in (list(KINDS) if args == ["all"] else args):
    make(k)
