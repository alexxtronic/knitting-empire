"""The farm barn, copied from Alex's reference render: red board walls on a stone footing, cream timber
frame (corner posts, a tie beam and knee braces over the doors), double doors with cross braces, iron
strap hinges and ring handles, lit four-pane windows, a brown shake roof with thick tan barge boards, and
a cupola with a rooster weathervane. Inside it is a working barn: a plank floor with straw, four stalls
with gates and bedding, a feed trough, hay bales and a loose pile, sacks, a barrel, a ladder, a pitchfork
and a lantern. The barn only: no path, plants or props outside.

The game shows a building's inside by hiding what is in the way, so the model is exported in parts:

    base                      floor, stone footing, threshold: always shown
    wall_front|back|left|right    each wall at full height (the gables go with front and back)
    wall_*_low                the same wall cut down to a 0.62 m stub, shown instead when it faces the camera
    door_l, door_r            the two door leaves, each with its origin on its hinge line, so they can swing
    gate_l0|l1|r0|r1          the four stall gates (left or right of the aisle, 0 nearest the doors), hinged
                              at the end nearer the doors, so they can swing into their stalls
    roof                      shakes, barge boards, ridge, cupola and weathervane: hidden when she is inside
    interior                  stalls, hay, tools

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/barn/build.py

Front (the doors) faces -Y here (+Z in Godot). 5.6 x 5.0 m over the walls, eaves at 2.7 m, ridge at 5.3 m.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

NAME = "barn"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")

# --- measures (metres) ----------------------------------------------------------------------------
W, D = 5.6, 5.0            # over the walls
SKIN = 0.07                # each wall is two skins of boards: red outside, bare wood inside
H = 2.7                    # eaves
PITCH = math.radians(43)
RIDGE = H + W / 2 * math.tan(PITCH)
EAVE, RAKE = 0.40, 0.36    # how far the roof overhangs the side walls and the gables
BASE = 0.34                # stone footing
POST = 0.26                # corner posts
DOOR_W, DOOR_H = 2.0, 2.2
LOW = 0.62                 # height of a cut-down wall
RNG = random.Random(4)
M = {}
PARTS = {}
CLAIMED = set()   # objects already given to a part of their own (the stall gates, built inside `interior`)
HINGES = {}       # part name -> where its origin goes, so the game can swing it


class part:
    """Everything built inside `with part("name"):` is joined into one exported object of that name."""

    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.before = set(K.COLL.objects)

    def __exit__(self, *a):
        PARTS.setdefault(self.name, []).extend(o for o in K.COLL.objects if o not in self.before and o not in CLAIMED)


# --- materials ---------------------------------------------------------------------------------------

def wood(name, base, light, dark, seams=0, knots=1, seed=1, rough=0.8, n=256):
    i, nm = CL.plank_maps(name, TEX, base=base, light=light, dark=dark, seams=seams, knots=knots, seed=seed, n=n)
    return K.textured(name, i, rough=rough, normal=nm, normal_strength=1.0)


def stone_maps(name, n=256, seed=31):
    """Soft grey fieldstone: broad mottling, a few pale flecks. Each footing block is its own mesh, so the
    texture carries no joints."""
    import numpy as np
    a = K.tile_noise(n, 1.5, seed)
    b = K.tile_noise(n, 0.7, seed + 1)
    base, light, dark = CL.C("#aaa39c"), CL.C("#c6bfb7"), CL.C("#857f79")
    rgb = CL.mix(dark, base, np.clip(a * 1.6 - 0.2, 0, 1)[..., None])
    rgb = CL.mix(rgb, light, np.clip(b * 2.2 - 1.2, 0, 1)[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(0.6 * a + 0.4 * b, 2.0), TEX)


def materials():
    M["red"] = wood("barn_siding", "#b9362a", "#cf4a37", "#861f17", seams=4, seed=3, n=512)
    M["cream"] = wood("barn_trim", "#f0dcb2", "#fbecca", "#cbad80", knots=0, seed=5)
    M["tan"] = wood("barn_beam", "#d98a3c", "#eea85c", "#a55e1e", seed=7)
    M["shake"] = wood("barn_shake", "#6c493f", "#7f5a4b", "#4d342d", knots=0, seed=9, rough=0.85)
    M["boards"] = wood("barn_boards", "#bd8c54", "#d2a468", "#93653a", seams=4, knots=0, seed=11, n=512)
    M["floor"] = wood("barn_floor", "#a37646", "#bd9160", "#6f4c2a", seams=3, seed=13, n=512)
    M["stall"] = wood("barn_stall", "#c08c50", "#dcae72", "#8c5c2e", seed=15)
    i, nm = stone_maps("barn_stone")
    M["stone"] = K.textured("barn_stone", i, rough=0.9, normal=nm, normal_strength=1.0)
    i, nm = CL.straw_maps("barn_straw", TEX, base="#f0a51a", light="#ffd34d", dark="#b06a08")
    M["straw"] = K.textured("barn_straw", i, rough=0.8, normal=nm, normal_strength=0.7)
    M["iron"] = K.plain("barn_iron", "#3b3435", 0.6)
    M["glow"] = K.plain("barn_glow", "#ffd884", 0.4, emit=1.8)
    M["muntin"] = K.plain("barn_muntin", "#9a643a", 0.8)
    M["gold"] = K.plain("barn_gold", "#e6a63c", 0.55)
    M["dark"] = K.plain("barn_dark", "#3a2a22", 0.9)
    M["sack"] = K.plain("barn_sack", "#c9b58a", 0.95)
    M["water"] = K.plain("barn_water", "#6fa7b8", 0.15)


# --- pieces ------------------------------------------------------------------------------------------

def bx(name, size, loc, mat, grain="z", bevel=0.015, seg=1, rot=(0, 0, 0), scale=1.0):
    """A rounded box with its texture laid on in world metres; grain is the axis the wood runs along."""
    ob = K.box(name, size, loc, mat, bevel=bevel, seg=seg, rot=rot)
    K.uv_box(ob, scale, grain=grain)
    return ob


class Wall:
    """One side of the barn. Pieces are placed in the wall's own terms: `a` along it (0 at its middle),
    `o` out from its outer face (negative is into the wall), z up. cap cuts the wall down to a stub."""

    def __init__(self, yaw, half, length, cap=None):
        self.yaw, self.half, self.length, self.cap = yaw, half, length, cap
        self.rot = Matrix.Rotation(yaw, 3, "Z")
        self.along = "x" if abs(math.sin(yaw)) < 0.5 else "y"

    def at(self, a, o, z):
        return self.rot @ Vector((a, -(self.half + o), z))

    def box(self, name, a, o, z, sa, so, sz, mat, grain="z", bevel=0.012, seg=1):
        """Centre (a, o, z); sa along the wall, so through it, sz tall. grain "a" runs along the wall."""
        if self.cap is not None:
            lo, hi = z - sz / 2, z + sz / 2
            if lo >= self.cap - 0.02:
                return None
            hi = min(hi, self.cap)
            z, sz = (lo + hi) / 2, hi - lo
        return bx(name, (sa, so, sz), self.at(a, o, z), mat, grain=self.along if grain == "a" else grain,
                  bevel=bevel, seg=seg, rot=(0, 0, math.degrees(self.yaw)))


def skins(wall, a0, a1, z0, z1):
    """The two layers of boards between a0 and a1: red outside, bare inside."""
    if a1 - a0 < 0.02:
        return
    wall.box("siding", (a0 + a1) / 2, -SKIN / 2, (z0 + z1) / 2, a1 - a0, SKIN, z1 - z0, M["red"], bevel=0.006)
    wall.box("boards", (a0 + a1) / 2, -SKIN * 1.5, (z0 + z1) / 2, a1 - a0, SKIN, z1 - z0, M["boards"], bevel=0.006)


def window(wall, a, z, w=0.86, h=0.86):
    """A lit four-pane window in a thick cream frame with a deeper sill, the same from inside."""
    for o, face in ((0.0, 1), (-2 * SKIN, -1)):
        d = 0.05 * face
        wall.box("pane", a, o + d * 0.4, z, w - 0.12, 0.03, h - 0.12, M["glow"], bevel=0.0)
        wall.box("muntin", a, o + d * 0.8, z, 0.045, 0.03, h - 0.12, M["muntin"], bevel=0.006)
        wall.box("muntin", a, o + d * 0.8, z, w - 0.12, 0.03, 0.045, M["muntin"], grain="a", bevel=0.006)
        for s in (-1, 1):
            wall.box("jamb", a + s * (w / 2 - 0.02), o + d, z, 0.13, 0.09, h + 0.04, M["cream"], bevel=0.02, seg=2)
        wall.box("head", a, o + d, z + h / 2 + 0.03, w + 0.26, 0.11, 0.15, M["cream"], grain="a", bevel=0.025, seg=2)
        wall.box("sill", a, o + d * 1.3, z - h / 2 - 0.03, w + 0.30, 0.15, 0.15, M["cream"], grain="a", bevel=0.025, seg=2)


def gable(y, face):
    """The triangle of wall under the roof at one end, two skins, with a window in the front one."""
    for k, mat in ((0, M["red"]), (1, M["boards"])):
        y0 = y - face * SKIN * k
        y1 = y - face * SKIN * (k + 1)
        pts = [(-W / 2, H), (W / 2, H), (0.0, RIDGE)]
        ob = K.extrude_xz("gable", pts, min(y0, y1), max(y0, y1), mat, bevel=0.0)
        K.uv_box(ob, 1.0, grain="z")


def build_wall(side, low):
    cap = LOW if low else None
    if side in ("front", "back"):
        wall = Wall(0.0 if side == "front" else math.pi, D / 2, W, cap)
        inner = W / 2 - POST / 2     # the side walls own the corner posts
        if side == "front":
            for s in (-1, 1):
                skins(wall, min(s * DOOR_W / 2, s * inner), max(s * DOOR_W / 2, s * inner), BASE, H)
                wall.box("door_jamb", s * (DOOR_W / 2 + 0.07), 0.035, (BASE + DOOR_H) / 2 + 0.1, 0.16, 0.12,
                         DOOR_H - BASE + 0.2, M["cream"], bevel=0.025, seg=2)
            skins(wall, -DOOR_W / 2, DOOR_W / 2, DOOR_H, H)
            wall.box("door_head", 0, 0.04, DOOR_H + 0.09, DOOR_W + 0.32, 0.13, 0.18, M["cream"], grain="a", bevel=0.03, seg=2)
            # the tie beam across the front, and a knee brace bowing down to each post
            wall.box("tie_beam", 0, 0.06, H - 0.10, W + 0.06, 0.20, 0.30, M["cream"], grain="a", bevel=0.04, seg=2)
            if not low:
                for s in (-1, 1):
                    x0 = s * (W / 2 - POST - 0.02)
                    pts = [wall.at(x0 + s * 0.04, 0.075, H - 1.05), wall.at(x0 - s * 0.02, 0.075, H - 0.60),
                           wall.at(x0 - s * 0.32, 0.075, H - 0.30), wall.at(x0 - s * 0.86, 0.075, H - 0.24)]
                    pts = [Vector(p) for p in CL.bezier(*pts, n=10)]
                    CL.beam("brace", pts, 0.13, 0.17, M["cream"], sides=10, square=0.3)
                gable(-D / 2, -1)
                window(wall, 0.0, H + 0.82, 0.84, 0.84)
        else:
            skins(wall, -inner, inner, BASE, H)
            if not low:
                gable(D / 2, 1)
                window(wall, 0.0, H + 0.82, 0.84, 0.84)   # up in the gable, clear of the ladder and tools inside
                wall.box("tie_beam", 0, 0.03, H - 0.10, W + 0.04, 0.14, 0.26, M["cream"], grain="a", bevel=0.035, seg=2)
    else:
        wall = Wall(math.pi / 2 if side == "right" else -math.pi / 2, W / 2, D, cap)
        skins(wall, -D / 2 + POST / 2, D / 2 - POST / 2, BASE, H)
        for s in (-1, 1):   # the corner posts, standing a little proud of both walls
            wall.box("post", s * (D / 2 - POST / 2 + 0.02), -POST / 2 + 0.04, (BASE + H) / 2, POST, POST, H - BASE,
                     M["cream"], bevel=0.035, seg=2)
        wall.box("plate", 0, -SKIN, H - 0.07, D - POST, 0.20, 0.14, M["cream"], grain="a", bevel=0.03, seg=2)
        window(wall, 0.35 if side == "right" else -0.35, 1.55)


def mound(name, x, y, r, h, sy=1.0, grain="y", seed=0):
    """A heap of straw or hay with a ragged outline, not a neat oval."""
    ob = K.ball(name, r, (x, y, 0.0), M["straw"], scale=(1.0, sy, h / r), u=14, v=7)
    K.apply_mods(ob)
    rg = random.Random(seed * 7 + 3)
    ph = [rg.uniform(0, 6.28) for _ in range(3)]
    for v in ob.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = 1.0 + 0.16 * math.sin(3 * a + ph[0]) + 0.10 * math.sin(5 * a + ph[1]) + 0.06 * math.sin(9 * a + ph[2])
        v.co.x *= k
        v.co.y *= k
        v.co.z = max(v.co.z, 0.0) * (1.0 + 0.25 * math.sin(4 * a + ph[1]))
    K.uv_box(ob, 1.6, grain=grain)
    return ob


def build_base():
    """Floor, straw, the stone footing all the way round and the threshold slab."""
    bx("floor", (W - 0.2, D - 0.2, 0.08), (0, 0, -0.01), M["floor"], grain="y", bevel=0.0)
    for (x, y, r, sy) in ((-1.9, 0.3, 0.75, 0.9), (1.85, 1.5, 0.8, 0.8), (1.9, -0.1, 0.7, 0.85), (-1.9, 1.6, 0.8, 0.8),
                          (0.1, 0.9, 0.9, 1.6), (-1.7, -1.6, 0.9, 0.7)):
        mound("straw", x, y, r, 0.05, sy, seed=int(x * 10 + y * 3))
    for side, yaw, half, length in (("front", 0.0, D / 2, W), ("back", math.pi, D / 2, W),
                                    ("right", math.pi / 2, W / 2, D), ("left", -math.pi / 2, W / 2, D)):
        wall = Wall(yaw, half, length)
        a = -length / 2 - 0.06
        while a < length / 2 + 0.05:
            ln = min(RNG.uniform(0.5, 0.82), length / 2 + 0.06 - a)
            if ln < 0.2:
                break
            mid = a + ln / 2
            in_door = side == "front" and abs(mid) < DOOR_W / 2 + 0.02
            if not in_door:
                h = BASE + RNG.uniform(-0.03, 0.035)
                wall.box("stone", mid, -0.06 + RNG.uniform(-0.012, 0.02), h / 2, ln - 0.02, 0.26, h, M["stone"],
                         grain="a", bevel=0.045, seg=1)
            a += ln
    wall = Wall(0.0, D / 2, W)
    wall.box("threshold", 0, -0.02, 0.035, DOOR_W + 0.1, 0.42, 0.09, M["stone"], grain="a", bevel=0.03, seg=2)


def build_door(s):
    """One door leaf (s = -1 left, +1 right): boards, a cream frame with a cross brace, two strap hinges on
    the outer edge and a ring handle by the meeting edge."""
    w = DOOR_W / 2 - 0.012
    cx = s * (w / 2 + 0.006)
    y = -D / 2 - 0.035
    z0, z1 = 0.07, DOOR_H - 0.02
    zc, h = (z0 + z1) / 2, z1 - z0
    bx("door_boards", (w, 0.05, h), (cx, y, zc), M["red"], bevel=0.008)
    f = y - 0.04
    for sx in (-1, 1):
        bx("stile", (0.12, 0.045, h), (cx + sx * (w / 2 - 0.06), f, zc), M["cream"], bevel=0.015, seg=2)
    for z in (z0 + 0.07, z1 - 0.07):
        bx("rail", (w - 0.2, 0.045, 0.14), (cx, f, z), M["cream"], grain="x", bevel=0.015, seg=2)
    span_x, span_z = w - 0.26, h - 0.30
    ang = math.degrees(math.atan2(span_z, span_x))
    for d in (-1, 1):
        bx("brace", (math.hypot(span_x, span_z), 0.035, 0.095), (cx, f + 0.004 * d, zc), M["cream"], grain="x",
           bevel=0.012, rot=(0, -d * ang, 0))
    for z in (z0 + 0.32, z1 - 0.32):   # strap hinges
        bx("hinge", (0.34, 0.03, 0.13), (s * (DOOR_W / 2 - 0.12), f - 0.03, z), M["iron"], bevel=0.012, seg=2)
        for k in (0.05, 0.19):
            ob = K.ball("hinge_pin", 0.018, (s * (DOOR_W / 2 - 0.26 + k), f - 0.045, z), M["iron"], u=8, v=5)
            K.apply_mods(ob)
    hx = s * 0.17
    ob = K.cyl("handle_boss", 0.05, 0.05, 0.04, (hx, f - 0.03, 1.12), M["iron"], verts=12, rot=(90, 0, 0), bevel=0.008)
    ob = K.torus("handle_ring", 0.11, 0.024, (hx, f - 0.06, 1.01), M["iron"], rot=(90, 0, 0), major=16, minor=6)
    K.apply_mods(ob)


def build_roof():
    run = W / 2 + EAVE
    slope = run / math.cos(PITCH)
    depth = D + 2 * RAKE
    for s in (-1, 1):
        # the deck: bare boards seen from under the eaves
        mid = Vector((s * run / 2, 0, RIDGE - run / 2 * math.tan(PITCH)))
        nrm = Vector((s * math.sin(PITCH), 0, math.cos(PITCH)))
        bx("deck", (slope, depth - 0.08, 0.06), mid + nrm * 0.05, M["boards"], grain="x", bevel=0.0,
           rot=(0, s * math.degrees(PITCH), 0))
        # shakes: five rows of thick boards, each row lapping the one below, joints staggered
        rows, per = 4, 6
        expose = (slope + 0.06) / rows
        tilt = math.atan2(0.085, expose)
        down = Vector((s * math.cos(PITCH), 0, -math.sin(PITCH)))
        wid = depth / per
        for r in range(rows):
            n = per + (r % 2)
            for k in range(n):
                wk = wid
                yk = -depth / 2 + wid * (k + 0.5) - (wid / 2 if r % 2 else 0)
                if r % 2 and k in (0, n - 1):   # the half boards that finish a staggered row
                    wk = wid / 2
                    yk = -depth / 2 + wk / 2 if k == 0 else depth / 2 - wk / 2
                ln = expose * 1.22 + RNG.uniform(-0.03, 0.05)
                u = expose * (r + 0.5) + 0.02
                c = Vector((0, 0, RIDGE)) + down * u + nrm * (0.14 + RNG.uniform(0, 0.014)) + Vector((0, yk, 0))
                bx("shake", (ln, wk - 0.016, 0.095), c, M["shake"], grain="x", bevel=0.028, seg=1,
                   rot=(RNG.uniform(-1.2, 1.2), s * math.degrees(PITCH - tilt), RNG.uniform(-1.0, 1.0)), scale=0.8)
        # barge boards along both gables: thick tan boards from the eaves to the peak
        for y in (-depth / 2 + 0.02, depth / 2 - 0.02):
            ln = slope + 0.2
            c = Vector((0, y, RIDGE)) + down * (ln / 2 - 0.08) + nrm * 0.10
            bx("barge", (ln, 0.22, 0.38), c, M["tan"], grain="x", bevel=0.07, seg=2, rot=(0, s * math.degrees(PITCH), 0))
    # the ridge board, and the round end of the ridge beam showing at each peak
    bx("ridge", (0.26, depth - 0.1, 0.14), (0, 0, RIDGE + 0.22), M["tan"], grain="y", bevel=0.04, seg=2)
    for y in (-depth / 2 - 0.03, depth / 2 + 0.03):
        ob = K.cyl("ridge_end", 0.27, 0.27, 0.30, (0, y, RIDGE + 0.12), M["tan"], verts=14, rot=(90, 0, 0), bevel=0.04)
        K.uv_box(ob, 2.0, grain="y")
    build_cupola(0.0, 1.0)


ROOSTER = [(-0.02, 0.0), (0.02, 0.0), (0.03, 0.05), (0.09, 0.06), (0.13, 0.10), (0.15, 0.17), (0.20, 0.20), (0.23, 0.27),
           (0.21, 0.33), (0.17, 0.30), (0.13, 0.33), (0.10, 0.27), (0.05, 0.19), (-0.02, 0.17), (-0.07, 0.21), (-0.10, 0.30),
           (-0.12, 0.33), (-0.13, 0.37), (-0.16, 0.36), (-0.165, 0.33), (-0.20, 0.31), (-0.165, 0.29), (-0.17, 0.22),
           (-0.15, 0.13), (-0.10, 0.07), (-0.03, 0.05)]


def build_cupola(x, y):
    z = RIDGE - 0.12
    size, h = 1.05, 1.05
    top = z + h
    bx("cupola", (size, size, h), (x, y, z + h / 2), M["red"], bevel=0.008)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx("cupola_post", (0.12, 0.12, h + 0.02), (x + sx * (size / 2 - 0.03), y + sy * (size / 2 - 0.03), z + h / 2),
               M["cream"], bevel=0.02, seg=2)
    bx("cupola_sill", (size + 0.14, size + 0.14, 0.09), (x, y, top - 0.56), M["cream"], grain="x", bevel=0.02, seg=2)
    for yaw in (0, 90, 180, 270):   # a louvred vent in each face
        r = Matrix.Rotation(math.radians(yaw), 3, "Z")
        at = lambda a, o, zz: Vector((x, y, 0)) + r @ Vector((a, -(size / 2 + o), zz))
        zc = top - 0.28
        bx("vent_back", (0.40, 0.02, 0.32), at(0, 0.004, zc), M["dark"], bevel=0.0, rot=(0, 0, yaw))
        for k in range(4):
            bx("slat", (0.40, 0.035, 0.045), at(0, 0.02, zc - 0.115 + k * 0.077), M["cream"], grain="x", bevel=0.008,
               rot=(-28, 0, yaw))
        for s in (-1, 1):
            bx("vent_side", (0.06, 0.05, 0.40), at(s * 0.215, 0.022, zc), M["cream"], bevel=0.012, rot=(0, 0, yaw))
            bx("vent_rail", (0.49, 0.05, 0.06), at(0, 0.022, zc + s * 0.185), M["cream"], grain="x", bevel=0.012, rot=(0, 0, yaw))
    bx("cupola_plate", (size + 0.2, size + 0.2, 0.08), (x, y, top + 0.02), M["cream"], grain="x", bevel=0.02, seg=2)
    ob = K.cyl("cupola_roof", 1.06, 0.07, 0.62, (x, y, top + 0.36), M["shake"], verts=4, rot=(0, 0, 45), bevel=0.02)
    K.uv_box(ob, 0.8, grain="z")
    ob = K.ball("finial", 0.085, (x, y, top + 0.72), M["iron"], u=10, v=7)
    K.apply_mods(ob)
    K.cyl("vane_rod", 0.018, 0.018, 0.36, (x, y, top + 0.94), M["iron"], verts=6)
    # the vane: an arrow, and a rooster standing on it
    zv = top + 1.02
    bx("arrow", (0.78, 0.028, 0.04), (x, y, zv), M["gold"], bevel=0.01)
    K.cyl("arrow_head", 0.08, 0.0, 0.17, (x + 0.46, y, zv), M["gold"], verts=4, rot=(0, 90, 0))
    for d in (-1, 1):
        bx("arrow_tail", (0.15, 0.026, 0.09), (x - 0.38, y, zv + d * 0.04), M["gold"], bevel=0.008, rot=(0, d * 28, 0))
    ob = K.extrude_xz("rooster", [(px * 1.45 + x, pz * 1.45 + zv + 0.015) for px, pz in ROOSTER], y - 0.02, y + 0.02, M["gold"], bevel=0.01)


def bale(x, y, z, yaw=0.0, size=(0.92, 0.46, 0.40)):
    bx("bale", size, (x, y, z + size[2] / 2), M["straw"], grain="x", bevel=0.05, seg=2, rot=(0, 0, yaw), scale=1.4)
    r = Matrix.Rotation(math.radians(yaw), 3, "Z")
    for k in (-0.25, 0.25):
        p = Vector((x, y, z + size[2] / 2)) + r @ Vector((k * size[0], 0, 0))
        bx("bale_twine", (0.03, size[1] + 0.012, size[2] + 0.012), p, M["dark"], bevel=0.004, rot=(0, 0, yaw))


def gate(x0, x1, y, z1=1.05):
    """A stall front between two posts: three rails, a cross brace and a latch."""
    w = x1 - x0
    for z in (0.22, 0.60, z1 - 0.07):
        bx("gate_rail", (w, 0.045, 0.12), ((x0 + x1) / 2, y, z), M["stall"], grain="x", bevel=0.018, seg=2)
    for x in (x0 + 0.06, x1 - 0.06):
        bx("gate_stile", (0.10, 0.055, z1 - 0.08), (x, y - 0.01, z1 / 2 + 0.02), M["stall"], bevel=0.018, seg=2)
    ang = math.degrees(math.atan2(z1 - 0.3, w - 0.2))
    bx("gate_brace", (math.hypot(w - 0.2, z1 - 0.3), 0.035, 0.085), ((x0 + x1) / 2, y - 0.012, z1 / 2 + 0.03), M["stall"],
       grain="x", bevel=0.012, rot=(0, -ang, 0))
    bx("latch", (0.16, 0.03, 0.05), (x1 - 0.1, y - 0.045, 0.78), M["iron"], bevel=0.008)


def build_interior():
    ix, iy = W / 2 - 2 * SKIN, D / 2 - 2 * SKIN      # the inner faces of the walls
    aisle = 0.95
    # four stalls, two each side of the aisle, over the back two thirds of the barn
    ys = (-0.55, 0.92, iy)
    for s in (-1, 1):
        for k in range(2):
            y0, y1 = ys[k], ys[k + 1]
            # the partition toward the front of the barn: boards between two posts, with a top rail
            bx("partition", (ix - aisle - 0.1, 0.06, 1.0), (s * (ix + aisle) / 2, y0, 0.56), M["stall"], grain="x", bevel=0.012)
            bx("partition_cap", (ix - aisle, 0.11, 0.09), (s * (ix + aisle) / 2, y0, 1.10), M["stall"], grain="x", bevel=0.025, seg=2)
            bx("stall_post", (0.15, 0.15, 1.42), (s * aisle, y0, 0.71), M["stall"], bevel=0.03, seg=2)
            # the gate on the aisle, and bedding, a water bucket and a hay net's worth of feed inside
            a0, a1 = (y0 + 0.10, y1 - 0.10) if k == 0 else (y0 + 0.10, y1 - 0.06)
            g = Matrix.Rotation(math.pi / 2, 3, "Z")
            before = set(K.COLL.objects)
            gate(a0, a1, 0.0)
            leaf = [o for o in K.COLL.objects if o not in before]
            for ob in leaf:
                ob.matrix_world = Matrix.Translation((s * aisle, 0, 0)) @ g.to_4x4() @ ob.matrix_world
            name = "gate_%s%d" % ("r" if s > 0 else "l", k)
            PARTS[name] = leaf
            CLAIMED.update(leaf)
            HINGES[name] = (s * aisle, a0 - 0.02, 0.0)
            mound("bedding", s * (ix + aisle) / 2 + s * 0.1, (y0 + y1) / 2, 0.66, 0.13, 0.85, grain="x", seed=k + 5 * s)
            bucket(s * (aisle + 0.33), y1 - 0.34)
        bx("stall_post", (0.15, 0.15, 1.42), (s * aisle, iy - 0.075, 0.71), M["stall"], bevel=0.03, seg=2)
    # front left: hay, baled and loose
    bale(-1.95, -1.95, 0.0, 8)
    bale(-1.9, -1.42, 0.0, -5)
    bale(-1.93, -1.72, 0.40, 3)
    mound("hay_pile", -1.25, -1.05, 0.6, 0.42, 0.85, grain="z", seed=9)
    # front right: a feed trough on legs, sacks, a barrel
    trough(1.92, -1.3)
    for (x, y, yaw, lean) in ((1.2, -2.05, 20, 0), (1.62, -2.1, -15, 0), (1.42, -2.02, 5, 1)):
        ob = K.ball("sack", 0.24, (x, y, 0.20 + 0.36 * lean), M["sack"], scale=(1.0, 0.72, 0.85 if not lean else 0.6), u=10, v=7, boxy=0.7)
        ob.rotation_euler = (0, 0, math.radians(yaw))
        K.apply_mods(ob)
    barrel(2.2, -2.0)
    # the back of the aisle: a ladder against the wall, a pitchfork, and a lantern on a bracket
    ladder(-0.35, iy - 0.16)
    pitchfork(0.45, iy - 0.07)
    lantern(0.0, iy - 0.05, 2.05)


def bucket(x, y):
    prof = [(0.11, 0.0), (0.145, 0.24), (0.15, 0.25), (0.135, 0.25), (0.105, 0.03), (0.0, 0.03)]
    K.lathe("bucket", prof, M["stall"], steps=12, loc=(x, y, 0.0))
    ob = K.cyl("bucket_water", 0.128, 0.128, 0.01, (x, y, 0.20), M["water"], verts=12)
    K.torus("bucket_band", 0.137, 0.012, (x, y, 0.18), M["iron"], major=12, minor=4)


def trough(x, y):
    """A long feed box on four legs, full of hay."""
    ln, wd = 1.5, 0.46
    for sx in (-1, 1):
        bx("trough_side", (0.05, ln, 0.26), (x + sx * (wd / 2 - 0.025), y, 0.50), M["stall"], grain="y", bevel=0.012)
        for sy in (-1, 1):
            bx("trough_leg", (0.08, 0.08, 0.62), (x + sx * (wd / 2 - 0.06), y + sy * (ln / 2 - 0.09), 0.31), M["stall"], bevel=0.015)
    for sy in (-1, 1):
        bx("trough_end", (wd, 0.05, 0.26), (x, y + sy * (ln / 2 - 0.025), 0.50), M["stall"], grain="x", bevel=0.012)
    bx("trough_floor", (wd - 0.06, ln - 0.06, 0.04), (x, y, 0.40), M["stall"], grain="y", bevel=0.0)
    ob = K.ball("trough_hay", 0.3, (x, y, 0.56), M["straw"], scale=(0.62, 2.3, 0.36), u=10, v=6)
    K.apply_mods(ob)
    K.uv_box(ob, 1.6, grain="y")


def barrel(x, y):
    prof = [(0.21, 0.0), (0.25, 0.14), (0.27, 0.34), (0.25, 0.54), (0.21, 0.68), (0.19, 0.68), (0.19, 0.64), (0.0, 0.64)]
    ob = K.lathe("barrel", prof, M["stall"], steps=14, loc=(x, y, 0.0), u_rep=3.0)
    for z, r in ((0.13, 0.252), (0.55, 0.252)):
        K.torus("barrel_band", r, 0.016, (x, y, z), M["iron"], major=14, minor=4)


def ladder(x, y):
    """Leaning back against the end wall."""
    lean = math.radians(12)
    for sx in (-1, 1):
        bx("ladder_rail", (0.06, 0.05, 2.5), (x + sx * 0.23, y - 0.26, 1.22), M["stall"], bevel=0.012, rot=(-math.degrees(lean), 0, 0))
    for k in range(7):
        z = 0.3 + k * 0.32
        bx("rung", (0.46, 0.04, 0.045), (x, y - 0.52 + z * math.tan(lean), z), M["stall"], grain="x", bevel=0.012)


def pitchfork(x, y):
    K.cyl("fork_handle", 0.018, 0.018, 1.5, (x, y - 0.12, 0.80), M["stall"], verts=8, rot=(-6, 0, 0))
    bx("fork_head", (0.22, 0.025, 0.03), (x, y - 0.045, 1.56), M["iron"], bevel=0.006)
    for k in (-0.09, -0.03, 0.03, 0.09):
        K.cyl("fork_tine", 0.008, 0.004, 0.26, (x + k, y - 0.035, 1.70), M["iron"], verts=5)


def lantern(x, y, z):
    bx("lantern_arm", (0.05, 0.34, 0.05), (x, y - 0.15, z + 0.28), M["iron"], bevel=0.01)
    K.cyl("lantern_cap", 0.10, 0.03, 0.08, (x, y - 0.28, z + 0.17), M["iron"], verts=8)
    K.cyl("lantern_glass", 0.075, 0.075, 0.17, (x, y - 0.28, z + 0.05), M["glow"], verts=8)
    K.cyl("lantern_base", 0.09, 0.07, 0.04, (x, y - 0.28, z - 0.055), M["iron"], verts=8)


# --- export ------------------------------------------------------------------------------------------

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
    if origin is not None:   # a door: put the object's origin on its hinge line
        for v in ob.data.vertices:
            v.co -= Vector(origin)
        ob.location = origin
    return ob


def main():
    K.reset(NAME)
    materials()
    with part("base"):
        build_base()
    for side in ("front", "back", "left", "right"):
        with part("wall_" + side):
            build_wall(side, False)
        with part("wall_" + side + "_low"):
            build_wall(side, True)
    for s, n in ((-1, "door_l"), (1, "door_r")):
        with part(n):
            build_door(s)
    with part("roof"):
        build_roof()
    with part("interior"):
        build_interior()
    bpy.context.view_layer.update()
    HINGES.update({"door_l": (-DOOR_W / 2, -D / 2 - 0.035, 0.0), "door_r": (DOOR_W / 2, -D / 2 - 0.035, 0.0)})
    obs = [join_part(n, o, HINGES.get(n)) for n, o in PARTS.items() if o]
    stats = {"name": NAME, "parts": {}, "triangles": 0}
    for o in obs:
        t = K.tri_count(o)
        stats["parts"][o.name] = {"triangles": t, "materials": [m.name for m in o.data.materials]}
        stats["triangles"] += t
    stats["images"] = sorted(i.name for i in bpy.data.images if i.users and i.type == "IMAGE")
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


main()
