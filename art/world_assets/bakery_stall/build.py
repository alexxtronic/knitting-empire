"""The bakery's street stall, after Alex's reference art: a planked wooden counter under a
scalloped red-and-cream striped awning, a lantern hanging from an iron bracket, and on the
counter a basket of croissants, a glass cake dome with a croissant, a jug of lavender and a
folded tea towel. Beside it go an A-frame chalkboard and a crate of daisies and ivy, built as
their own models so they can be moved on their own in the world editor.

    bakery_stall      counter, posts, awning, lantern, and the things on the counter
    chalkboard_sign   an A-frame chalkboard: "Fresh Croissants" with a croissant drawn under it
    daisy_crate       a slatted wooden crate of daisies with ivy trailing over the front

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/bakery_stall/build.py -- all
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
CW, CD, CH = 1.7, 0.72, 0.95  # counter width, depth, height
PX, PY = 0.86, 0.38  # post positions (x, y half spacing)
AW = 1.0  # half width of the awning
STRIPE = 0.125  # awning stripe width, one scallop per stripe


def wood(name, seams=0, seed=91, base="#c56f2c", light="#e08f45", dark="#93501f", knots=1, rough=0.65, normal_strength=0.7):
    i, n = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=seams, seed=seed, knots=knots)
    return K.textured(name, i, rough=rough, normal=n, normal_strength=normal_strength)


def mesh(name, verts, faces, uvs, mat):
    return CL._finish_mesh(name, verts, faces, uvs, mat, recalc=False)


# --- croissants --------------------------------------------------------------------------------------

def croissant(centre, yaw, mat, size=1.0, tilt=0.0):
    """A crescent of rolled dough: fat in the middle, tapering to curled points, with the rolls
    showing as swellings along it."""
    c = Vector(centre)
    R = 0.06 * size
    pts, radii = [], []
    n = 15
    for i in range(n + 1):
        t = i / n
        a = math.radians(-95 + 190 * t)
        pts.append(Vector((R * math.sin(a), -R * math.cos(a) + R * 0.6, 0.0)))
        swell = 0.72 + 0.28 * abs(math.cos(t * math.pi * 5))
        radii.append(0.03 * size * max(0.12, math.sin(math.pi * t)) ** 0.7 * swell)
    ob = CL.tube("croissant", pts, radii, mat, sides=10, v_scale=6.0, flat=0.72)
    # the tube lies in its local XY plane, squashed along Z, so it already lies flat
    ob.rotation_euler = (math.radians(tilt), 0, math.radians(yaw))
    ob.location = c
    return ob


def croissant_maps(n=128):
    """Golden baked dough: darker caramel along the top of each roll, paler in the creases."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    top = 0.5 + 0.5 * np.cos(2 * np.pi * (u - 0.25))  # u runs round the tube
    rgb = CL.mix(CL.C("#eaa94e"), CL.C("#a8521a"), (top ** 1.2)[..., None])
    s = K.tile_noise(n, 1.4, 151)
    rgb = rgb * (0.92 + 0.14 * s[..., None])
    return K.save_image("croissant", rgb, TEX)


# --- the stall ---------------------------------------------------------------------------------------

def awning_maps():
    i, n = CL.stripes_maps("awning_stripes", TEX, a="#d4483e", b="#f6e6c8", stripes=8)
    return K.textured("awning_stripes", i, rough=0.85, normal=n, normal_strength=0.5)


def awning(mat):
    """A sloping striped canopy from the back posts down over the front, with a scalloped valance
    on the front and both sides."""
    y0, y1 = PY + 0.12, -PY - 0.3  # back, front
    z0, z1 = 2.32, 2.02
    nx, ny = 16, 6
    verts, faces, uvs = [], [], []
    for j in range(ny + 1):
        t = j / ny
        for i in range(nx + 1):
            x = -AW + 2 * AW * i / nx
            sag = 0.025 * math.sin(math.pi * t) + 0.012 * math.sin(math.pi * ((x + AW) / (2 * AW / 4) % 1.0))
            verts.append((x, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t - sag))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            b = a + nx + 1
            faces.append((a, a + 1, b + 1, b))  # faces up
            for (ii, jj) in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)):
                uvs.append(((-AW + 2 * AW * ii / nx + AW) / 1.0, jj / ny))
    mesh("awning", verts, faces, uvs, mat)
    # valances: a scallop per stripe, hanging from the edge
    drop, r = 0.12, STRIPE / 2

    def valance(name, start, along, count, u0, slope=0.0, flip=False):
        start, along = Vector(start), Vector(along).normalized()
        out = along.cross(Vector((0, 0, 1))) * (-1 if flip else 1)
        V, F, U = [], [], []
        for k in range(count):
            a = start + along * STRIPE * k
            poly = [a, a + along * STRIPE]
            for s in range(9):  # the round bottom, right to left
                ang = math.pi * s / 8
                poly.append(a + along * (r + r * math.cos(ang)) + Vector((0, 0, -drop - r * math.sin(ang))))
            # (the arc ends at the left edge, so no extra point: it made a zero-area triangle)
            # lean out a little at the bottom
            poly = [p + out * 0.06 * max(0.0, (a.z - p.z)) for p in poly]
            # follow a sloping edge: each point rises with how far along it is
            poly = [p + Vector((0, 0, slope * (p - start).dot(along))) for p in poly]
            base = len(V)
            V += poly
            # anticlockwise seen from outside
            idx = list(range(base, base + len(poly)))
            F.append(tuple(reversed(idx)) if along.cross(Vector((0, 0, -1))).dot(out) > 0 else tuple(idx))
            for p in poly:
                rise = slope * (p - start).dot(along)
                U.append((u0 + (k * STRIPE + (p - a).dot(along)) / 1.0, (p.z - rise - a.z + drop + r) / (drop + r)))
        mesh(name, V, F, U, mat)

    valance("valance_front", (-AW, y1, z1 + 0.005), (1, 0, 0), int(2 * AW / STRIPE), 0.0, flip=True)
    nside = int(round((y0 - y1) / STRIPE))
    for sx in (-1, 1):
        # the side edges slope up to the back: the valance follows them, no steps
        valance("valance_side", (sx * AW, y1, z1 + 0.005), (0, 1, 0), nside, 0.0, slope=(z0 - z1) / (y0 - y1), flip=sx < 0)
    # a rolled hem along the front edge
    CL.tube("hem", [Vector((x, y1 - 0.004, z1 + 0.005)) for x in np.linspace(-AW + 0.02, AW - 0.02, 9)], [0.014] * 9, mat, sides=8, v_scale=4.0)


def lantern(at, iron, glow, glass):
    """A small iron lantern: a peaked cap with a ring, four corner bars round a warm glass box."""
    at = Vector(at)
    s = 0.075
    K.cyl("lantern_base", s * 0.9, s * 0.8, 0.025, tuple(at + Vector((0, 0, -0.1))), iron, verts=4, rot=(0, 0, 45))
    K.box("lantern_glow", (s * 1.05, s * 1.05, 0.15), tuple(at), glow, bevel=0.004, seg=1)
    for gx in (-1, 1):
        for gy in (-1, 1):
            K.box("lantern_bar", (0.012, 0.012, 0.18), tuple(at + Vector((gx * s * 0.56, gy * s * 0.56, 0))), iron, bevel=0.002, seg=1)
    K.cyl("lantern_cap", s * 0.95, s * 0.2, 0.07, tuple(at + Vector((0, 0, 0.115))), iron, verts=4, rot=(0, 0, 45))
    K.torus("lantern_ring", 0.022, 0.006, tuple(at + Vector((0, 0, 0.17))), iron, rot=(90, 0, 0), major=12, minor=5)


def basket(at, wick, rx=0.21, ry=0.15, h=0.09):
    prof = [(0.0, 0.0), (0.82, 0.0), (0.9, 0.12), (1.0, 0.85), (1.02, 1.0), (0.95, 1.0), (0.93, 0.85), (0.83, 0.2), (0.0, 0.2)]
    ob = K.lathe("basket", [(r, z * h) for r, z in prof], wick, steps=28, u_rep=8.0, v_rep=1.5, sharp=60)
    for v in ob.data.vertices:
        v.co.x *= rx
        v.co.y *= ry
    ob.location = at
    rim = K.torus("basket_rim", 1.0, 0.06, tuple(Vector(at) + Vector((0, 0, h))), wick, major=28, minor=6)
    for v in rim.data.vertices:
        v.co.x *= rx
        v.co.y *= ry
        v.co.z *= 0.2
    K.uv_box(rim, 8.0)
    return ob


def jug(at, ceramic, blue):
    at = Vector(at)
    prof = [(0.0, 0.0), (0.05, 0.0), (0.062, 0.01), (0.075, 0.05), (0.072, 0.1), (0.052, 0.15), (0.046, 0.17),
            (0.05, 0.19), (0.054, 0.2), (0.048, 0.2), (0.042, 0.18), (0.0, 0.18)]
    K.lathe("jug", prof, ceramic, steps=22, loc=tuple(at), sharp=70)
    K.torus("jug_band", 0.0745, 0.006, tuple(at + Vector((0, 0, 0.075))), blue, major=22, minor=5)
    hp = CL.bezier(at + Vector((0.05, 0.0, 0.165)), at + Vector((0.11, 0.0, 0.17)), at + Vector((0.115, 0.0, 0.08)), at + Vector((0.068, 0.0, 0.06)), n=8)
    CL.tube("jug_handle", hp, [0.011] * len(hp), ceramic, sides=8, flat=0.6)


def lavender(at, stem, bud, rng):
    at = Vector(at)
    for k in range(13):
        a = 2 * math.pi * k / 13 + rng.uniform(-0.2, 0.2)
        spread = rng.uniform(0.25, 0.55)
        top = at + Vector((math.cos(a) * spread * 0.16, math.sin(a) * spread * 0.16, rng.uniform(0.22, 0.3)))
        base = at + Vector((math.cos(a) * 0.012, math.sin(a) * 0.012, 0.12))
        mid = base.lerp(top, 0.5) + Vector((0, 0, 0.01))
        CL.tube("lav_stem", [base, mid, top], [0.0035] * 3, stem, sides=4, caps=False)
        d = (top - mid).normalized()
        for b in range(5):  # a spike of buds
            p = top + d * (b * 0.012)
            K.ball("lav_bud", 0.008 * (1 - b * 0.12), tuple(p), bud, scale=(1, 1, 1.3), u=6, v=4)


def towel_maps(n=128):
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    rgb = np.ones((n, n, 3)) * CL.C("#f3ece0")
    band = ((np.abs(v - 0.1) < 0.025) | (np.abs(v - 0.17) < 0.012) | (np.abs(v - 0.9) < 0.025) | (np.abs(v - 0.83) < 0.012))
    rgb = np.where(band[..., None], CL.C("#5f86b8"), rgb)
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 3) + 0.25 * np.sin(2 * np.pi * yy / 3)
    rgb = rgb * (0.95 + 0.06 * weave[..., None])
    return K.save_image("tea_towel", rgb, TEX)


def towel(x, mat):
    """A tea towel folded over the front edge of the counter: lying flat, then hanging down."""
    w = 0.2
    path = [(-0.05, CH + 0.052), (-0.2, CH + 0.052), (-CD / 2 - 0.06, CH + 0.05), (-CD / 2 - 0.08, CH + 0.02),
            (-CD / 2 - 0.08, CH - 0.06), (-CD / 2 - 0.078, CH - 0.22)]
    V, F, U = [], [], []
    run = [0.0]
    for a, b in zip(path, path[1:]):
        run.append(run[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    for i, (y, z) in enumerate(path):
        for s in (-1, 1):
            ripple = 0.004 * math.sin(i * 1.7 + s)
            V.append(Vector((x + s * w / 2, y + ripple, z)))
    for i in range(len(path) - 1):
        a = 2 * i
        F.append((a, a + 2, a + 3, a + 1))
        U += [(0, run[i] / run[-1]), (0, run[i + 1] / run[-1]), (1, run[i + 1] / run[-1]), (1, run[i] / run[-1])]
    ob = CL._finish_mesh("tea_towel", V, F, U, mat, recalc=True)
    sol = ob.modifiers.new("thick", "SOLIDIFY")  # cloth has a thickness (kiln round 1: a flat card)
    sol.thickness = 0.006
    sol.offset = 1.0
    K.apply_mods(ob)
    # the rim faces solidify adds have no UV area: map them by their position instead
    uv = ob.data.uv_layers.active.data
    for poly in ob.data.polygons:
        pts = [uv[li].uv.copy() for li in poly.loop_indices]
        area = abs(sum(pts[i].x * pts[i - 1].y - pts[i - 1].x * pts[i].y for i in range(len(pts))))
        if area < 1e-7:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                co = ob.data.vertices[vi].co
                uv[li].uv = (co.x * 8.0 + co.y * 8.0, co.z * 8.0 + co.y * 4.0)


def build_stall():
    rng = np.random.default_rng(23)
    body = wood("stall_planks", seams=4, seed=97, knots=0)  # kiln round 1: the knots repeated as bullseyes
    trim = wood("stall_trim", seed=98, base="#a65a26", light="#c4733a", dark="#7a3f18")
    top_w = wood("stall_top", seed=99, base="#d68a44", light="#eba664", dark="#a8622c")
    iron = K.plain("lantern_iron", "#2f2c2b", rough=0.5)
    glow = K.plain("lantern_glow", "#ffd27a", rough=0.3, emit=3.0)
    glass = K.plain("cake_glass", "#e6f4f6", rough=0.05, alpha=0.22)
    wick_i, wick_n = CL.wicker_maps("stall_wicker", TEX)
    wick = K.textured("stall_wicker", wick_i, rough=0.8, normal=wick_n, normal_strength=0.8)
    pastry = K.textured("croissant", croissant_maps(), rough=0.42)
    ceramic = K.plain("jug_ceramic", "#f1ebdf", rough=0.3)
    blue = K.plain("jug_blue", "#5f86b8", rough=0.35)
    stem = K.plain("lavender_stem", "#7f9a5a", rough=0.7)
    bud = K.plain("lavender_bud", "#8b6cc7", rough=0.7)
    cloth = K.textured("tea_towel", towel_maps(), rough=0.9)
    board = wood("cake_board", seed=100, base="#d9a066", light="#ecbd88", dark="#b07a44")

    # counter: a planked body on a darker plinth, a top board with an overhang, trim along the front
    b = K.box("counter", (CW, CD, CH - 0.1), (0, 0, 0.05 + (CH - 0.1) / 2), body, bevel=0.012, seg=2)
    K.uv_box(b, 1.2)
    K.uv_box(K.box("plinth", (CW + 0.04, CD + 0.04, 0.07), (0, 0, 0.035), trim, bevel=0.01, seg=1), 1.5, grain="x")
    K.uv_box(K.box("counter_top", (CW + 0.12, CD + 0.1, 0.05), (0, 0, CH - 0.025), top_w, bevel=0.012, seg=2), 1.2, grain="x")
    for z in (0.16, CH - 0.11):
        K.uv_box(K.box("front_rail", (CW + 0.01, 0.03, 0.06), (0, -CD / 2 - 0.012, z), trim, bevel=0.01, seg=1), 1.5, grain="x")
    # posts at the corners, the back pair taller for the slope, a cross bar at the top front
    for sx in (-1, 1):
        for sy, h in ((-1, 2.04), (1, 2.25)):  # both stop under the canopy (kiln round 1)
            CL.beam("post", [Vector((sx * PX, sy * PY, 0)), Vector((sx * PX, sy * PY, h / 2)), Vector((sx * PX, sy * PY, h))], 0.08, 0.08, trim, sides=12, v_scale=1.0, square=0.3)
        CL.beam("side_bar", [Vector((sx * PX, -PY, 1.98)), Vector((sx * PX, 0, 2.08)), Vector((sx * PX, PY, 2.2))], 0.05, 0.06, trim, sides=10, square=0.3)
    CL.beam("front_bar", [Vector((-PX - 0.05, -PY, 1.98)), Vector((0, -PY, 1.98)), Vector((PX + 0.05, -PY, 1.98))], 0.06, 0.07, trim, sides=10, square=0.3)
    awning(awning_maps())
    # the lantern on an iron bracket off the right front post
    bp = [Vector((PX + 0.04, -PY, 1.78)), Vector((PX + 0.2, -PY, 1.78)), Vector((PX + 0.3, -PY, 1.78))]
    CL.tube("bracket", bp, [0.011] * 3, iron, sides=6)
    CL.tube("bracket_brace", CL.bezier(Vector((PX + 0.04, -PY, 1.6)), Vector((PX + 0.1, -PY, 1.62)), Vector((PX + 0.2, -PY, 1.7)), Vector((PX + 0.24, -PY, 1.775)), n=7), [0.008] * 8, iron, sides=6)
    CL.tube("bracket_curl", [Vector((PX + 0.3, -PY, 1.78)) + Vector((0.025 * math.sin(a), 0, -0.025 + 0.025 * math.cos(a))) for a in np.linspace(0, 1.6 * math.pi, 9)], [0.008] * 9, iron, sides=6)
    CL.tube("lantern_hook", [Vector((PX + 0.24, -PY, 1.78)), Vector((PX + 0.24, -PY, 1.72))], [0.005] * 2, iron, sides=5)
    lantern((PX + 0.24, -PY, 1.55), iron, glow, glass)

    top = CH
    # a basket heaped with croissants
    basket((-0.48, -0.08, top), wick)
    for k, (x, y, z, yaw, tilt) in enumerate([(-0.57, -0.13, 0.065, 20, 8), (-0.4, -0.14, 0.065, -15, -8), (-0.5, -0.01, 0.07, 160, 6),
                                              (-0.37, -0.03, 0.07, 200, -8), (-0.48, -0.08, 0.11, 80, 10), (-0.61, -0.04, 0.08, 120, -12)]):
        croissant((x, y, top + z), yaw, pastry, size=1.15, tilt=tilt)
    # a glass cake dome on a wooden board, a croissant inside
    K.uv_box(K.cyl("cake_board", 0.16, 0.16, 0.025, (0.12, -0.02, top + 0.0125), board, verts=24, bevel=0.006), 2.0, grain="x")
    croissant((0.12, -0.03, top + 0.05), -20, pastry, size=1.5)
    prof = [(0.145, 0.0), (0.148, 0.012), (0.146, 0.1), (0.13, 0.17), (0.09, 0.215), (0.04, 0.232), (0.0, 0.235)]
    K.lathe("cake_dome", prof, glass, steps=24, loc=(0.12, -0.02, top + 0.026), sharp=80)
    K.ball("dome_knob", 0.022, (0.12, -0.02, top + 0.275), glass, scale=(1, 1, 0.8), u=10, v=6)
    # a jug of lavender at the back corner
    jug((0.55, 0.14, top), ceramic, blue)
    lavender((0.55, 0.14, top), stem, bud, rng)
    # a tea towel folded over the front edge
    towel(0.5, cloth)


# --- the chalkboard ----------------------------------------------------------------------------------

def slate_maps(n=256):
    yy, xx = np.mgrid[0:n, 0:n]
    s = K.tile_noise(n, 1.1, 161)
    smear = K.grain_noise(n, 6.0, 1.4, 162)
    rgb = CL.C("#2e3a36") * (0.85 + 0.2 * s[..., None]) + CL.C("#ffffff") * 0.035 * np.clip(smear - 0.5, 0, 1)[..., None]
    # chalk dust left from wiping the board (kiln round 1: the slate was too clean): soft cloudy
    # patches and a few broad sideways swipes
    rng = np.random.default_rng(163)
    cloud = K.tile_noise(n, 2.2, 164)
    dust = np.clip((cloud - 0.55) * 2.2, 0, 1) * 0.16
    for k in range(5):
        cy, h = rng.uniform(0.1, 0.9) * n, rng.uniform(0.04, 0.09) * n
        x0, x1 = sorted(rng.uniform(0, n, 2))
        band = np.exp(-((yy - cy - 6 * np.sin(xx / n * 6.28 + k)) / h) ** 2) * ((xx > x0) & (xx < x1 + n * 0.25))
        dust += band * rng.uniform(0.05, 0.1) * (0.6 + 0.4 * smear)
    rgb = rgb + (CL.C("#d8dcd4") - rgb) * np.clip(dust, 0, 0.35)[..., None]
    return K.save_image("chalk_slate", np.clip(rgb, 0, 1), TEX)


def chalk_fill_maps(n=256):
    """Chalk rubbed in lightly with the side of the stick: the slate shows through most of it."""
    g = K.grain_noise(n, 3.0, 1.0, 167)
    f = K.tile_noise(n, 0.8, 168)
    cover = np.clip(0.3 + 0.5 * (g - 0.5) + 0.4 * (f - 0.5), 0, 1)
    rgb = CL.C("#33403b") + (CL.C("#e9e2cf") - CL.C("#33403b")) * (0.45 * cover)[..., None]
    return K.save_image("chalk_fill", np.clip(rgb, 0, 1), TEX)


def chalk_maps(n=256):
    """Chalk strokes: white broken up by the slate showing through, in fine streaks."""
    g = K.grain_noise(n, 10.0, 1.0, 165)
    f = K.tile_noise(n, 0.6, 166)
    cover = np.clip(0.55 + 0.9 * (g - 0.5) + 0.6 * (f - 0.5), 0, 1)
    rgb = CL.C("#38443f") + (CL.C("#f1efe6") - CL.C("#38443f")) * (0.35 + 0.65 * cover)[..., None]
    return K.save_image("chalk_strokes", np.clip(rgb, 0, 1), TEX)


def build_chalkboard():
    # browner, rougher wood in square stock (kiln round 1: it read as orange plastic dowels)
    frame = wood("chalk_frame", seed=101, base="#8c5a33", light="#ad7a4c", dark="#5f3a1f", knots=0, rough=0.88, normal_strength=1.2)
    slate = K.textured("chalk_slate", slate_maps(), rough=0.95)
    chalk = K.textured("chalk", chalk_maps(), rough=0.97)
    chalk_fill = K.textured("chalk_fill", chalk_fill_maps(), rough=0.97)
    W, Hb, foot = 0.52, 0.86, 0.24
    th = math.atan2(foot, Hb)
    up = Vector((0, math.sin(th), math.cos(th)))  # along the front board, bottom to top
    for side in (-1, 1):
        # boards lean together at the top; side -1 is the front (lettered) one
        f_up = Vector((0, -side * math.sin(th), math.cos(th)))
        base = Vector((0, side * foot, 0))
        nrm = Vector((0, side * math.cos(th), side * math.sin(th)))  # pointing away from the middle
        for sx in (-1, 1):
            CL.beam("frame_leg", [base + Vector((sx * W / 2, 0, 0)), base + Vector((sx * W / 2, 0, 0)) + f_up * (Hb / 2), base + Vector((sx * W / 2, 0, 0)) + f_up * (Hb - 0.01)],
                    0.06, 0.038, frame, sides=16, square=0.15, v_scale=2.0)
        for t in (0.12, 0.97):
            p = base + f_up * (Hb * t)
            CL.beam("frame_rail", [p + Vector((-W / 2, 0, 0)), p, p + Vector((W / 2, 0, 0))], 0.05, 0.034, frame, sides=16, square=0.15, v_scale=2.0)
        a = base + f_up * (Hb * 0.14) + Vector((-W / 2 + 0.032, 0, 0)) + nrm * 0.004
        b = base + f_up * (Hb * 0.95) + Vector((W / 2 - 0.032, 0, 0)) + nrm * 0.004
        # the slate panel, as a quad laid along the board
        quad = [a, a + Vector((W - 0.064, 0, 0)), b, b - Vector((W - 0.064, 0, 0))]
        if side > 0:
            quad.reverse()
        mesh("slate", [tuple(q) for q in quad], [(0, 1, 2, 3)], [(0, 0), (1, 0), (1, 1), (0, 1)] if side < 0 else [(0, 1), (1, 1), (1, 0), (0, 0)], slate)
    # lettering and a croissant drawn in chalk on the front board
    rng = np.random.default_rng(41)
    base = Vector((0, -foot, 0))
    f_up = Vector((0, math.sin(th), math.cos(th)))
    out = Vector((0, -math.cos(th), math.sin(th)))
    # each letter placed by hand: a little tilt, size and baseline wobble (kiln round 2: one clean
    # line of type read as vinyl lettering)
    chalk_word("Fresh", 0.105, base + f_up * 0.73 + out * 0.0045, f_up, out, chalk, rng)
    chalk_word("Croissants", 0.078, base + f_up * 0.61 + out * 0.0045, f_up, out, chalk, rng)
    croissant_doodle(base + f_up * 0.38 + out * 0.0046, Vector((1, 0, 0)), f_up, chalk, 1.25, fill=chalk_fill)
    # the back board gets a doodle too: a croissant and a few stars (no words)
    b_base = Vector((0, foot, 0))
    b_up = Vector((0, -math.sin(th), math.cos(th)))
    b_out = Vector((0, math.cos(th), math.sin(th)))
    croissant_doodle(b_base + b_up * 0.45 + b_out * 0.0046, Vector((-1, 0, 0)), b_up, chalk, 1.35, fill=chalk_fill)
    for (sx_, sy_, r) in ((-0.15, 0.72, 0.03), (0.14, 0.68, 0.024), (0.02, 0.2, 0.026)):
        c = b_base + b_up * sy_ + Vector((sx_, 0, 0)) + b_out * 0.0048
        pts = []
        # a plain outline star: no crossing lines (kiln round 8: drawn as a pentagram it read occult)
        for k in range(11):
            a = math.pi / 2 + k * math.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append(c + Vector((rr * math.cos(a), 0, 0)) + b_up * (rr * math.sin(a)))
        flat_stroke("chalk_star", pts, 0.007, b_out, chalk)
    # small iron hinges where the stiles meet at the top (kiln round 2: a black rod lay across it)
    hinge = K.plain("hinge_iron", "#3d3936", rough=0.7)
    top_z = (Hb - 0.01) * math.cos(th)
    for sx in (-1, 1):
        K.box("hinge", (0.03, 0.07, 0.02), (sx * W / 2, 0, top_z - 0.03), hinge, bevel=0.004, seg=1)
        K.cyl("hinge_pin", 0.008, 0.008, 0.034, (sx * W / 2, 0, top_z - 0.02), hinge, verts=10, rot=(0, 90, 0))
    # a cord holds the legs apart on each side
    cord = K.plain("chalk_cord", "#a88a62", rough=0.9)
    zc = 0.3
    yc = foot - zc * math.tan(th)
    for sx in (-1, 1):
        pts = [Vector((sx * W / 2, -yc + 2 * yc * t, zc - 0.03 * math.sin(math.pi * t))) for t in np.linspace(0, 1, 9)]
        CL.tube("cord", pts, [0.005] * 9, cord, sides=6, v_scale=10.0)


def chalk_word(word, size, centre, f_up, out, mat, rng):
    """A word in chalk on a board: one letter at a time, each slightly turned, sized and lifted."""
    letters = []
    for ch in word:
        ob = K.text("chalk_" + ch, ch, size * rng.uniform(0.93, 1.07), (0, 0, 0), (0, 0, 0), mat, depth=0.0)
        # flat on the board, its outline a little shaky like a hand-drawn stroke
        ph = rng.uniform(0, 6.28, 2)
        for v in ob.data.vertices:
            v.co.x += 0.0012 * math.sin(v.co.y * 140 + ph[0])
            v.co.y += 0.0012 * math.sin(v.co.x * 150 + ph[1])
        xs = [v.co.x for v in ob.data.vertices]
        letters.append((ob, max(xs) - min(xs), (max(xs) + min(xs)) / 2))
    gap = size * 0.07
    total = sum(w for _, w, _ in letters) + gap * (len(letters) - 1)
    x_axis = f_up.cross(out).normalized()  # the board's right, seen from the front
    basis = Matrix((x_axis, f_up, out)).transposed()
    cursor = -total / 2
    for ob, w, cx in letters:
        turn = math.radians(rng.uniform(-6, 6))
        rz = Matrix.Rotation(turn, 3, "Z")
        pos = centre + x_axis * (cursor + w / 2) + f_up * rng.uniform(-0.004, 0.004)
        m = (basis @ rz).to_4x4()
        m.translation = pos - (basis @ rz) @ Vector((cx, 0, 0))
        ob.matrix_world = m
        bpy.context.view_layer.update()
        K.uv_box(ob, 10.0)
        cursor += w + gap


def flat_stroke(name, pts, width, normal, mat, taper=False):
    """A chalk line drawn flat on a board: a ribbon in the board's plane (kiln round 3: raised tubes
    read as bent wire and poked through the board)."""
    V, F, U = [], [], []
    run = 0.0
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = t.cross(normal).normalized() * width / 2
        if taper:  # narrows to a point at the last sample
            side *= max(0.05, 1 - i / (len(pts) - 1))
        if i:
            run += (p - pts[i - 1]).length
        V += [p - side, p + side]
        if i:
            b = 2 * i
            F.append((b - 2, b - 1, b + 1, b))
            U += [((run - (p - pts[i - 1]).length) * 10, 0), ((run - (p - pts[i - 1]).length) * 10, width * 10), (run * 10, width * 10), (run * 10, 0)]
    ob = CL._finish_mesh(name, V, F, U, mat, recalc=False, smooth=False)
    # face out of the board
    for poly in ob.data.polygons:
        if poly.normal.dot(normal) < 0:
            poly.flip()
    return ob


def croissant_doodle(centre, x_axis, up, mat, scale, fill=None):
    """A croissant drawn in chalk the way a baker draws one: a fat crescent arching up, its two
    pointed ends hooking down, split into rolled segments by curved ridge lines, lightly rubbed in
    (kiln round 5: five separate rolls read as a crown or balloons; round 6: a smooth dome read as a frown)."""
    normal = x_axis.cross(up).normalized()
    # a true crescent: the band inside circle A and outside circle B, which sits lower, so the body is
    # fattest on top and tapers to two horns pointing down (kiln round 7: a dome on a flat base line
    # read as a cloud, a loaf or a shell)
    RA, cB, RB = 0.1, -0.05, 0.085
    def at(x, y, lift=0.0):  # squashed: a croissant lies wider than tall, not a horseshoe
        return centre + x_axis * (x * scale * 1.1) + up * ((y + 0.02) * scale * 0.72) + normal * lift
    horn = math.atan2(-0.05275, 0.0849)  # where the circles cross
    th0, th1 = math.pi - horn, horn       # left horn, over the top, to the right horn
    folds = [math.radians(90 + d) for d in (50, 18, -18, -50)]
    bounds = [th0] + folds + [th1]
    def outer_r(th):
        for a, b in zip(bounds, bounds[1:]):
            if b <= th <= a:
                return RA * (1 + 0.07 * max(0.0, math.sin(math.pi * (a - th) / (a - b))) ** 0.6)
        return RA
    def inner_r(th):
        uc = math.sin(th) * cB
        return uc + math.sqrt(max(0.0, uc * uc - cB * cB + RB * RB))
    def pt(th, r, lift=0.0):
        return at(r * math.cos(th), r * math.sin(th), lift)
    ths = sorted(set(list(np.linspace(th1, th0, 49)) + folds), reverse=True)
    if fill is not None:
        V, F, U = [], [], []
        for i, th in enumerate(ths):
            V += [pt(th, inner_r(th), -0.0001), pt(th, max(outer_r(th), inner_r(th) + 1e-4), -0.0001)]
            if i:
                b = 2 * i
                F.append((b - 2, b, b + 1, b - 1))
        for f in F:
            for v in f:
                q = V[v] - centre
                U.append((q.dot(x_axis) * 6, q.dot(up) * 6))
        ob = CL._finish_mesh("chalk_fill", V, F, U, fill, recalc=False, smooth=False)
        for poly in ob.data.polygons:
            if poly.normal.dot(normal) < 0:
                poly.flip()
    outline = [pt(th, outer_r(th)) for th in ths] + [pt(th, inner_r(th)) for th in reversed(ths)]
    outline.append(outline[0])
    flat_stroke("chalk_drawing", outline, 0.009 * scale, normal, mat)
    # pointed horn tips: each carries on round circle A, down and in, narrowing to a point
    # (kiln round 8: the horns stopped bluntly)
    for th_tip, d in ((th0, 1), (th1, -1)):
        tip = [pt(th_tip + d * a, RA) for a in np.linspace(-0.04, 0.3, 6)]
        flat_stroke("chalk_drawing", tip, 0.011 * scale, normal, mat, taper=True)
    # the folds between the rolls, each bowed toward the middle
    for th in folds:
        r0, r1 = inner_r(th), outer_r(th)
        side = 1 if th < math.pi / 2 else -1
        pts = [pt(th + side * 0.12 * math.sin(math.pi * t), r0 + (r1 - r0) * t, 0.0002) for t in np.linspace(0.08, 0.92, 7)]
        flat_stroke("chalk_drawing", pts, 0.0075 * scale, normal, mat)


# --- the crate of daisies ----------------------------------------------------------------------------

def build_crate():
    rng = np.random.default_rng(31)
    slat = wood("crate_slats", seed=103, base="#c48a52", light="#e6b77e", dark="#8a5a30", knots=0, rough=0.8, normal_strength=1.2, seams=0)
    soil = K.plain("crate_soil", "#4a3324", rough=0.95)
    leaf_dark = K.plain("ivy_dark", "#3f7a2e", rough=0.6)
    leaf_mid = K.plain("ivy_mid", "#5f9a38", rough=0.6)
    leaf_light = K.plain("ivy_light", "#86b84a", rough=0.6)
    petal = K.plain("daisy_petal", "#fbf7ee", rough=0.6, emit=0.35)  # stays white in shade (kiln round 4)
    eye = K.plain("daisy_eye", "#f2b51c", rough=0.6)
    stem = K.plain("daisy_stem", "#5f9a38", rough=0.6)
    L, D, H = 0.56, 0.36, 0.26
    # four slats a side with gaps, corner blocks, a floor
    for sy in (-1, 1):
        for k in range(3):
            K.uv_box(K.box("slat", (L, 0.018, 0.07), (0, sy * (D / 2 - 0.009), 0.045 + k * 0.085), slat, bevel=0.006, seg=1), 2.0, grain="x")
    for sx in (-1, 1):
        for k in range(3):
            K.uv_box(K.box("slat", (0.018, D - 0.036, 0.07), (sx * (L / 2 - 0.009), 0, 0.045 + k * 0.085), slat, bevel=0.006, seg=1), 2.0, grain="y")
        for sy in (-1, 1):
            K.uv_box(K.box("corner", (0.04, 0.04, H - 0.01), (sx * (L / 2 - 0.02), sy * (D / 2 - 0.02), (H - 0.01) / 2), slat, bevel=0.006, seg=1), 2.0)
    # the soil fills the crate, so it does not look hollow through the gaps (kiln round 2)
    K.uv_box(K.box("soil", (L - 0.04, D - 0.04, H - 0.05), (0, 0, 0.01 + (H - 0.05) / 2), soil, bevel=0.005, seg=1), 2.0)
    # ivy in clumps inside the rim, and a few strands trailing over the front and the side
    mats = [leaf_dark, leaf_mid, leaf_light]
    clumps = [(-0.17, -0.06), (-0.05, 0.08), (0.08, -0.07), (0.19, 0.06), (-0.19, 0.08), (0.02, 0.0), (0.2, -0.08), (-0.08, -0.08), (0.1, 0.09), (-0.2, 0.0), (0.21, 0.0)]
    for cx, cy in clumps:
        for k in range(14):  # dense enough that the soil barely shows
            a, r = rng.uniform(0, 6.28), 0.075 * math.sqrt(rng.uniform(0, 1))
            R = rng.uniform(0.026, 0.036)
            x = float(np.clip(cx + r * math.cos(a), -L / 2 + 0.03 + R * 0.7, L / 2 - 0.03 - R * 0.7))
            y = float(np.clip(cy + r * math.sin(a), -D / 2 + 0.03 + R * 0.7, D / 2 - 0.03 - R * 0.7))
            z = H - 0.025 + 0.05 * (1 - r / 0.075) + 0.04 * (1 - (x / (L / 2)) ** 2) * (1 - (y / (D / 2)) ** 2) + rng.uniform(0, 0.015)
            ivy_leaf((x, y, z), R, mats[rng.integers(3)], yaw=rng.uniform(0, 6.28), pitch=rng.uniform(-25, 25), roll=rng.uniform(-20, 20))
    trails = [  # start x, which edge, length, sway
        (-0.2, "front", 0.24, 0.05), (-0.04, "front", 0.13, -0.03), (0.14, "front", 0.19, 0.04), (0.06, "side", 0.16, -0.04), (0.1, "back", 0.15, 0.03)]
    for k, (x0, edge, length, sway) in enumerate(trails):
        if edge == "front":
            start, out = Vector((x0, -D / 2 + 0.01, H - 0.01)), Vector((0, -1, 0))
        elif edge == "back":
            start, out = Vector((x0, D / 2 - 0.01, H - 0.01)), Vector((0, 1, 0))
        else:
            start, out = Vector((L / 2 - 0.01, x0, H - 0.01)), Vector((1, 0, 0))
        side = out.cross(Vector((0, 0, 1)))
        # from the soil inside, up over the rim, then down the slats in a loose S, close to the wood
        # (kiln round 3: straight rods started from a leaf on the rim)
        inner = start - out * 0.05 + Vector((0, 0, -0.02))
        pts = [inner.lerp(start + Vector((0, 0, 0.02)), t) + Vector((0, 0, 0.015 * math.sin(math.pi * t))) for t in np.linspace(0, 1, 4)]
        lip = start + out * 0.025 + Vector((0, 0, 0.012))
        pts.append(lip)
        for t in np.linspace(0.12, 1.0, 9):
            pts.append(start + out * (0.018 + 0.006 * math.sin(t * 5 + k)) + side * (sway * t + 0.012 * math.sin(t * 9 + k)) + Vector((0, 0, -length * t)))
        CL.tube("ivy_vine", pts, [0.0035] * len(pts), stem, sides=5, caps=False, v_scale=10.0)
        for i, p in enumerate(pts[3:]):
            d = (-1) ** (i + k)
            R = 0.028 - i * 0.0012 + rng.uniform(-0.003, 0.003)
            # hanging: the face turned out from the crate, the tip down
            yaw = math.atan2(out.y, out.x) + math.radians(d * rng.uniform(10, 35))
            ivy_leaf(tuple(p + side * d * 0.012 + out * 0.005), R, mats[(i + k) % 3], yaw=yaw, pitch=rng.uniform(60, 82), roll=rng.uniform(-15, 15))
    # daisies standing up out of the leaves on curving stems
    for k in range(17):
        x = rng.uniform(-L / 2 + 0.06, L / 2 - 0.06)
        y = rng.uniform(-D / 2 + 0.05, D / 2 - 0.05)
        h = H + rng.uniform(0.03, 0.09)  # tucked into the leaves
        bend = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))
        root = Vector((x, y, H - 0.03))
        c = root + bend + Vector((0, 0, h - root.z))
        sp = CL.bezier(root, root + Vector((0, 0, 0.05)), c - bend * 0.3 - Vector((0, 0, 0.05)), c - Vector((0, 0, 0.006)), n=6)
        CL.tube("daisy_stem", sp, [0.005, 0.0048, 0.0045, 0.0042, 0.004, 0.004, 0.0038], stem, sides=6, caps=False, v_scale=10.0)
        tilt = (Vector((0, 0, 1)) + bend * 4 + Vector((0, -0.15, 0))).normalized()
        q = tilt.to_track_quat("Z", "Y")
        K.ball("daisy_eye", 0.0105, tuple(c + tilt * 0.004), eye, scale=(1, 1, 0.6), u=8, v=5).rotation_euler = q.to_euler()
        V, F, U = [], [], []
        n_p = 12
        for i in range(n_p):
            a = 2 * math.pi * (i + rng.uniform(-0.15, 0.15)) / n_p
            d, w = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
            plen = 0.03 * rng.uniform(0.9, 1.1)
            base = len(V)
            V.append(d * 0.009)
            for j in range(7):
                t = j / 6
                # rounded petals, widest past the middle (kiln round 4: spiky petals read as fluff)
                V.append(d * (0.009 + plen * t) + w * 0.0105 * math.sin(math.pi * min(1.0, t * 0.85 + 0.0)) ** 0.6 * (1.0 if t < 1 else 0.0) + Vector((0, 0, 0.004 * t - 0.007 * t * t)))
            for j in range(6):
                F.append((base, base + 1 + j, base + 2 + j))
                for vi in (base, base + 1 + j, base + 2 + j):
                    U.append((0.5 + V[vi].x / 0.09, 0.5 + V[vi].y / 0.09))
        m, nf = len(V), len(F)
        V += [v - Vector((0, 0, 0.0008)) for v in V[:m]]
        F += [(m + f[0], m + f[2], m + f[1]) for f in F[:nf]]
        U += [U[3 * i + j] for i in range(nf) for j in (0, 2, 1)]
        fl = CL._finish_mesh("daisy_petals", V, F, U, petal, recalc=False)
        foliage_normals(fl)
        fl.rotation_mode = "QUATERNION"
        fl.rotation_quaternion = q
        fl.location = c


def foliage_normals(ob):
    """Both faces of a leaf shade as its top, lit from above (kiln round 3: undersides seen from
    the side rendered near-black)."""
    me = ob.data
    me.normals_split_custom_set_from_vertices([(0.0, 0.0, 1.0)] * len(me.vertices))


def ivy_leaf(centre, R, mat, yaw=0.0, pitch=0.0, roll=0.0):
    """An ivy leaf: five pointed lobes, a notch where the stalk joins, cupped a little along the
    midrib. It lies flat facing up, tip along +x before it is turned (yaw, radians; pitch and roll
    in degrees)."""
    V, F, U = [Vector((0, 0, 0))], [], [(0.5, 0.5)]
    n = 20
    for i in range(n):
        a = 2 * math.pi * i / n
        # pointed lobes, the tip lobe longest (kiln round 2: rounder lobes read as clover)
        r = R * (0.6 + 0.4 * abs(math.cos(2.5 * a)) ** 2) * (1 + 0.28 * math.cos(a))  # shallow lobes
        r *= 1 - 0.45 * math.exp(-((a - math.pi) / 0.28) ** 2)
        x, y = r * math.cos(a), r * math.sin(a)
        V.append(Vector((x, y, 0.25 * abs(y) * (1 - abs(x) / (R * 1.2)) - 0.08 * (x / R) ** 2 * R)))
        U.append((0.5 + x / (2.4 * R), 0.5 + y / (2.4 * R)))
    for i in range(n):
        F.append((0, 1 + i, 1 + (i + 1) % n))
    # two-sided: a back copy just under the face (kiln round 2: back faces rendered black)
    m = len(V)
    V += [v - Vector((0, 0, 0.0008)) for v in V[:m]]
    U += U[:m]
    F += [(m + f[0], m + f[2], m + f[1]) for f in F[:n]]
    ob = CL._finish_mesh("ivy_leaf", V, F, [U[v] for f in F for v in f], mat, recalc=False)
    foliage_normals(ob)
    ob.location = centre
    ob.rotation_euler = (math.radians(roll), math.radians(pitch), yaw)
    return ob


KINDS = {"bakery_stall": (build_stall, 34000), "chalkboard_sign": (build_chalkboard, 9000), "daisy_crate": (build_crate, 17000)}


def build(name):
    K.reset(name)
    fn, budget = KINDS[name]
    fn()
    if name == "daisy_crate":
        # leaves and petals are built two-sided (a back copy under each face), so each side must hide
        # from behind, or the two copies fight and petals turn black (kiln round 5)
        for m in bpy.data.materials:
            m.use_backface_culling = True
    out = os.path.join(HERE, "out", name)
    K.finish(name, out, max_tris=budget)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for a in (KINDS if args[0] == "all" else args):
    build(a)
