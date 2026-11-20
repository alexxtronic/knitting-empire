"""The Bretton Oaks house: a 1960s/70s single-storey brick ranch, from Alex's reference
(ref/bretton_oaks_house.png, 2026-11-17). See asset-brief.md for the measurements and what is inferred.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/suburb_house/build.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/suburb_house/build.py -- plants

Writes out/building_suburb_house.{blend,glb} and copies the GLB to assets/props/ (with "plants": the
arborvitae and the red-leaf shrub, assets/props/arborvitae.glb and red_shrub.glb). Built like the
walk-in shops and the café (art/world_assets/coffee_shop), in parts, so its roof lifts and its walls
cut down like theirs and it can be walked into later:

    base                          the plank floor and the concrete stoop at the door
    wall_front|back|left|right    each side's walls at full height, hollow, plastered inside, the
                                  windows open through them; the gables and dressing go with them
    wall_*_low                    the same walls cut down to a stub
    door                          the front door, its origin on its hinge (left jamb), so it swings in
    roof                          the three gabled roofs, fascia, soffits, gutters, the cream centre
                                  block above the low roofs, and the ceiling

Three blocks, each a front-facing gable (its ridge front to back):
    L  the entry wing on the left: lower (eave 2.45 m), its front set back behind the right wing's
    R  the right wing: forward, eave 2.6 m; its front part is the garage, its door in the side by the porch; one window in a cream strip
    M  the cream upper wing over the right wing, just behind its gable and above both (eave 4 m,
       apex about 5.5 m); the right wing's roof shows as its front gable and a skirt round the sides
Front faces -Y (+Z in Godot); the origin is on the ground in the middle of the footprint.
The material names choose what scripts/building_skin.gd does with each surface: brick -> the house's
brick map, roof_shake -> its shingles (grey here), trim -> painted wood; vinyl, pane, door, floor,
lining and paving keep their own.
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

NAME = "building_suburb_house"
TEX = os.path.join(HERE, "tex")
OUT = os.path.join(HERE, "out")
PROPS = os.path.join(K.PROJECT, "assets", "props")

T = 0.2          # wall thickness: the walls are hollow
LOW = 0.62       # a cut-down wall's height
FLOOR = 0.04
RT = 0.12        # roof thickness
OV = 0.4         # the roof's overhang at the eaves
OVE = 0.3        # ... and past the gable ends
PORCH = 1.45     # the entry wing's gable reaches out over a covered porch (the photo's bench sits under it),
                 # just in front of the upper wing's front wall, so its right slope shows coming down to the right wing
# the blocks: (x0, x1, y0 (front), y1 (back), eave, pitch in degrees)
# the right wing runs out toward the street as a garage for a car (Alex, 2026-11-17: "the garage is
# just that existing bottom part extended out towards the street to fit a car"): its front gable, now
# with the garage door, stands GARAGE_D in front of where the rooms end (HOUSE_FRONT)
HOUSE_FRONT = -4.4
GARAGE_D = 5.6
# the right wing and the upper wing run on BACK past the entry wing (Alex, 2026-11-20: "not enough room
# on upper floor, expand internally a bit ... shouldn't be visible from the street"): BACK_EXT more
# toward the back yard, so the street front is as it was
BACK_EXT = 2.0
R = (-1.44, 6.54, HOUSE_FRONT - GARAGE_D, 4.2 + BACK_EXT, 2.6, 17.0)
# the upper wing (Alex, 2026-11-17: "the top floor needs more square footage ... extended a bit more
# into the air"): over the whole right wing, front to back, standing just behind its brick gable, so
# Marcus's bedroom floor (data/split_house.json) has full-height walls everywhere under it
M = (-1.44, 6.54, -4.3, 4.2 + BACK_EXT, 4.0, 20.0)
# the entry wing: its apex just left of the upper wing, under that wing's eave corner, the rake rising
# to meet it (Alex, 2026-11-17: "increase tilt of bottom roof to be flush with top wing"), then coming
# down again to the right wing's rake, the whole upside-down V of the photo (Alex, 2026-11-17: "put
# bottom angle line on leftmost roof to finish the upside-down V shape"); its right half runs on under
# the other two, clipped inside the upper wing
L_EAVE = 2.4
LA = (-2.1, 3.8)  # the entry wing's apex under its roof: x, height
L = (-6.6, 2 * LA[0] + 6.6, -3.0, 4.2, L_EAVE, math.degrees(math.atan((LA[1] - L_EAVE) / (LA[0] + 6.6))))
# the garage door is in the garage's left side, facing the porch and the driveway in front of it
# (Alex, 2026-11-17: "put garage door on the right hand side (by the door entrance) and put it back to
# how it was before in the front"): centre along y, width, height
GDOOR = (HOUSE_FRONT - GARAGE_D / 2, 2.8, 2.15)
GSIDE_DOOR = HOUSE_FRONT - 2.0   # the garage's side door, in the right wing's right wall (along y)
MB = 2.42        # the centre block's walls start here, at the ceiling, under the low roofs
CEIL = 2.42      # the flat ceiling over the rooms
DOOR = (-2.5, 1.0, 2.05)              # the front door: centre x, width, height (in the entry wing)
PICTURE = (-5.1, 1.5, 0.85, 2.05)     # the picture window in the entry wing: centre x, width, sill, head
RWIN = (2.55, 1.4, 0.95, 2.2)         # the right wing's window
STRIP = (1.75, 3.35)                    # the cream strip round it

BRICK, VINYL, ROOF, TRIM = "#8a4a36", "#d8ccac", "#5e5d5a", "#f1efe8"


def tan(p):
    return math.tan(math.radians(p))


def apex_wall(b):
    """The gable wall's apex height (under the roof)."""
    x0, x1, _, _, eave, p = b
    return eave + (x1 - x0) / 2 * tan(p)


def rake(b, x):
    """The underside of a block's roof over x (the gable wall's top edge)."""
    x0, x1, _, _, eave, p = b
    cx = (x0 + x1) / 2
    return eave + ((x1 - x0) / 2 - abs(x - cx)) * tan(p)


# --- textures -----------------------------------------------------------------------------------

def rgb(h):
    return np.array(K.hex_rgb(h))


def lap_maps(name, hexcol, n=512, laps=6):
    """Horizontal vinyl lap siding: boards with a soft shadow under each lap, faint wood-grain
    embossing. One texture tile is 1.08 m (laps of 0.18 m); v runs up."""
    yy, xx = np.mgrid[0:n, 0:n]
    lh = n / laps
    f = (yy % lh) / lh  # 0 at a lap's top, 1 at its bottom edge
    grain = K.grain_noise(n, 30.0, 1.4, 11)
    mott = K.tile_noise(n, 1.6, 12)
    shade = 0.93 + 0.1 * f - 0.28 * np.clip((f - 0.9) / 0.1, 0, 1)
    c = rgb(hexcol) * shade[..., None] * (0.97 + 0.04 * grain[..., None]) * (0.96 + 0.06 * mott[..., None])
    hgt = f * 1.0 + 0.04 * grain - 1.2 * np.clip((f - 0.92) / 0.08, 0, 1)
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 3.0), TEX)


def materials():
    M_ = {}
    M_["brick"] = K.plain("suburb_brick", BRICK, 0.9)
    i, n = lap_maps("suburb_vinyl", VINYL)
    M_["vinyl"] = K.textured("suburb_vinyl", i, 0.6, normal=n, normal_strength=0.8)
    M_["roof"] = K.plain("suburb_roof_shake", ROOF, 0.9)
    M_["trim"] = K.plain("suburb_trim", TRIM, 0.55)
    M_["pane"] = K.plain("suburb_pane", "#2e3a40", 0.08)
    M_["curtain"] = K.plain("suburb_curtain_sheer", "#e8e1d0", 0.9)
    M_["door"] = K.plain("suburb_door", "#f4f2ec", 0.45)
    M_["floor"] = K.plain("suburb_floor", "#8a6a48", 0.75)
    M_["lining"] = K.plain("suburb_lining", "#e9e2d4", 0.9)
    # the right wing's ceiling: its own surface, so a walk-in house with an upper floor there can hide it
    M_["lining_r"] = K.plain("suburb_lining_upper", "#e9e2d4", 0.9)
    M_["paving"] = K.plain("suburb_paving", "#b9b4aa", 0.95)
    M_["lamp"] = K.plain("suburb_lamp_black", "#22201e", 0.5)
    M_["bulb"] = K.plain("suburb_bulb", "#ffd98a", 0.3, emit=2.0)
    M_["wreath"] = K.plain("suburb_leaf_wreath", "#3e5a2c", 0.9)
    M_["bow"] = K.plain("suburb_bow", "#a8282a", 0.7)
    M_["brass"] = K.plain("suburb_brass", "#c9933e", 0.35)
    return M_


# --- parts ------------------------------------------------------------------------------------------

PARTS = {}
HINGES = {}


class part:
    def __init__(self, name):
        self.name = name

    def __enter__(self):
        self.before = set(K.COLL.objects)

    def __exit__(self, *a):
        PARTS.setdefault(self.name, []).extend(o for o in K.COLL.objects if o not in self.before)


def ccw(pts):
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


def flat(name, pts, y0, y1, mat):
    """A shape drawn in XZ, from y0 to y1."""
    return K.extrude_xz(name, ccw([tuple(p) for p in pts]), y0, y1, mat, bevel=0.0)


def flat_side(name, pts, x0, x1, mat):
    """A shape drawn in YZ (y, z), from x0 to x1: drawn in XZ and turned a quarter."""
    ob = flat(name, [(-y, z) for y, z in pts], -x1, -x0, mat)
    ob.rotation_euler = (0, 0, math.radians(90))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return ob


# side -> (the axis the wall runs along, the inward direction along the other axis)
SIDES = {"front": ("x", 1), "back": ("x", -1), "left": ("y", 1), "right": ("y", -1)}


def wall_box(side, plane, a0, a1, z0, z1, depth, mat, inset=0.0):
    """A slab of wall on a side: its outer face on `plane` (pushed in by inset), from a0 to a1 along
    the wall and z0 to z1 up, `depth` thick inwards."""
    if a1 - a0 < 0.005 or z1 - z0 < 0.005:
        return None
    along, inward = SIDES[side]
    c = plane + inward * (inset + depth / 2)
    am, zm = (a0 + a1) / 2, (z0 + z1) / 2
    if along == "x":
        ob = K.box("wall", (a1 - a0, depth, z1 - z0), (am, c, zm), mat, bevel=0.0)
    else:
        ob = K.box("wall", (depth, a1 - a0, z1 - z0), (c, am, zm), mat, bevel=0.0)
    return ob


def wall_run(side, plane, a0, a1, z0, z1, mat, openings=(), depth=T, inset=0.0):
    """A stretch of wall with openings [(centre, width, bottom, top)] left out of it."""
    obs = []
    ops = sorted([o for o in openings if a0 < o[0] < a1], key=lambda o: o[0])
    a = a0
    for c, w, zb, zt in ops:
        obs.append(wall_box(side, plane, a, c - w / 2, z0, z1, depth, mat, inset))
        obs.append(wall_box(side, plane, c - w / 2, c + w / 2, z0, min(zb, z1), depth, mat, inset))
        obs.append(wall_box(side, plane, c - w / 2, c + w / 2, max(zt, z0), z1, depth, mat, inset))
        a = c + w / 2
    obs.append(wall_box(side, plane, a, a1, z0, z1, depth, mat, inset))
    return [o for o in obs if o is not None]


def lined_wall(Mt, side, plane, a0, a1, top, openings, low, mat="brick"):
    """The wall itself and the plaster lining inside it."""
    z1 = LOW if low else top
    wall_run(side, plane, a0, a1, 0.0, z1, Mt[mat], openings)
    wall_run(side, plane, a0 + (T if side in ("front", "back") else 0), a1 - (T if side in ("front", "back") else 0),
             FLOOR, min(z1, CEIL), Mt["lining"], openings, depth=0.02, inset=T)


def window(Mt, side, plane, c, w, zb, zt, bars=1, out=0.03):
    """A window in a wall: white frame proud of the face, a sill, the pane (sheer curtain behind it)
    halfway into the wall, glazing bars."""
    along, inward = SIDES[side]
    h = zt - zb
    fy = plane - inward * out / 2  # the frame's centre, a little outside the face
    py = plane + inward * T * 0.4
    cy = plane + inward * T * 0.55

    def bx(name, a, d, z, sa, sd, sz, mat):
        if along == "x":
            return K.box(name, (sa, sd, sz), (a, d, z), mat, bevel=0.0)
        return K.box(name, (sd, sa, sz), (d, a, z), mat, bevel=0.0)

    fw = 0.09
    bx("frame", c, fy, zt + fw / 2, w + 2 * fw, out + 0.06, fw, Mt["trim"])
    bx("frame", c - w / 2 - fw / 2, fy, (zb + zt) / 2, fw, out + 0.06, h, Mt["trim"])
    bx("frame", c + w / 2 + fw / 2, fy, (zb + zt) / 2, fw, out + 0.06, h, Mt["trim"])
    bx("sill", c, plane - inward * 0.06, zb - 0.03, w + 0.3, 0.16, 0.06, Mt["trim"])
    bx("pane", c, py, (zb + zt) / 2, w, 0.02, h, Mt["pane"])
    bx("curtain", c, cy, (zb + zt) / 2, w, 0.01, h, Mt["curtain"])
    # the jambs' reveal through the wall
    for s in (-1, 1):
        bx("reveal", c + s * (w / 2 - 0.02), plane + inward * T / 2, (zb + zt) / 2, 0.04, T, h, Mt["trim"])
    bx("reveal", c, plane + inward * T / 2, zb + 0.01, w, T, 0.02, Mt["trim"])
    bx("reveal", c, plane + inward * T / 2, zt - 0.01, w, T, 0.02, Mt["trim"])
    for k in range(1, bars + 1):
        bx("bar", c - w / 2 + k * w / (bars + 1), plane + inward * T * 0.35, (zb + zt) / 2, 0.045, 0.03, h, Mt["trim"])
    bx("bar", c, plane + inward * T * 0.35, zb + h * 0.55, w, 0.03, 0.04, Mt["trim"])


# the side and back windows (inferred): (block, side, centre along the wall, width, sill, head)
SIDE_WINDOWS = [("L", "left", -1.0, 1.2, 1.0, 2.1), ("L", "left", 2.4, 1.2, 1.0, 2.1),
                ("R", "right", -2.4, 1.3, 1.0, 2.2), ("R", "right", 1.6, 1.3, 1.0, 2.2), ("R", "right", 4.9, 1.3, 1.0, 2.2),
                ("R", "right", HOUSE_FRONT - 3.9, 1.0, 1.2, 2.0),
                ("L", "back", -5.0, 1.4, 1.0, 2.1), ("L", "back", -2.8, 1.0, 1.2, 2.1),
                ("R", "back", 0.6, 1.4, 1.0, 2.2), ("R", "back", 4.8, 1.2, 1.0, 2.2)]
BACK_DOOR = 2.6  # in the right wing (inferred)


def gable(Mt, b, y, mat, inward, upto=None):
    """The gable end's triangle above the eave, in the wall's plane (cut off at x = upto, where the
    right wing stands in front of the entry wing's)."""
    x0, x1, _, _, eave, _ = b
    cx = (x0 + x1) / 2
    tri = [(x0, eave), (x1, eave), (cx, apex_wall(b))]
    if upto is not None and upto < x1:
        tri = [(x0, eave), (upto, eave), (upto, rake(b, upto)), (cx, apex_wall(b))] if upto > cx else \
              [(x0, eave), (upto, eave), (upto, rake(b, upto))]
    y0, y1 = (y, y + T) if inward > 0 else (y - T, y)
    return flat("gable", tri, y0, y1, Mt[mat])


def valley_x():
    """Where the entry wing's rake comes down to the right wing's."""
    xs = np.linspace(R[0], 1.0, 200)
    return float(next((x for x in xs if rake(L, x) <= rake(R, x)), 1.0))


def valley_fill(Mt, y, inward):
    """Where the entry wing's roof runs on over the right wing's eave: the wedge of wall between the
    right wing's rake and the entry wing's, out to where the two roofs meet."""
    meet = valley_x()
    pts = [(R[0], R[4]), (meet, rake(R, meet)), (R[0], rake(L, R[0]))]
    y0, y1 = (y, y + T) if inward > 0 else (y - T, y)
    return flat("valley", pts, y0, y1, Mt["brick"])


def wall_front(Mt, low):
    x0, x1, yL = L[0], R[0], L[2]
    door_op = (DOOR[0], DOOR[1], -0.1, DOOR[2])
    pic_op = (PICTURE[0], PICTURE[1], PICTURE[2], PICTURE[3])
    lined_wall(Mt, "front", yL, x0, x1, L[4], [door_op, pic_op], low)
    rx0, rx1, yR = R[0], R[1], R[2]
    rwin = (RWIN[0], RWIN[1], RWIN[2], RWIN[3])
    wall_run("front", yR, rx0, rx1, 0.0, LOW if low else R[4], Mt["brick"], [rwin])
    # where the rooms end, the garage's back wall: the rooms' old front, plain brick, plastered inside
    lined_wall(Mt, "front", HOUSE_FRONT, rx0 + T, rx1 - T, R[4], [], low)
    # the right wing's left side, from its front back to the entry wing's front, with the garage door
    wall_run("left", rx0, yR + T, yL, 0.0, LOW if low else R[4], Mt["brick"], [(GDOOR[0], GDOOR[1], -0.1, GDOOR[2])])
    wall_run("left", rx0, HOUSE_FRONT + T, yL, FLOOR, LOW if low else CEIL, Mt["lining"], depth=0.02, inset=T)
    if not low:
        garage_door(Mt, rx0)
    if low:
        return
    gable(Mt, L, yL, "brick", 1, upto=R[0])
    gable(Mt, R, yR, "brick", 1)
    # the cream strip round the right window, from the ground up under the rake
    s0, s1 = STRIP
    flat("vinyl_strip", [(s0, 0.12), (s1, 0.12), (s1, rake(R, s1) - 0.02), (RWIN[0], rake(R, RWIN[0]) - 0.02),
                         (s0, rake(R, s0) - 0.02)], yR - 0.025, yR + 0.001, Mt["vinyl"])
    window(Mt, "front", yR - 0.025, RWIN[0], RWIN[1], RWIN[2], RWIN[3], bars=1)
    # the picture window: a shallow white bay, three lights
    pc, pw, pb, pt = PICTURE
    K.box("bay", (pw + 0.36, 0.3, 0.14), (pc, yL - 0.15, pb - 0.1), Mt["trim"], bevel=0.0)
    K.box("bay_head", (pw + 0.36, 0.3, 0.12), (pc, yL - 0.15, pt + 0.12), Mt["trim"], bevel=0.0)
    window(Mt, "front", yL - 0.02, pc, pw, pb, pt, bars=2, out=0.08)
    # the door: a white casing and the cream panel above it, up to the rake
    dc, dw, dh = DOOR
    for s in (-1, 1):
        K.box("casing", (0.1, 0.06, dh + 0.06), (dc + s * (dw / 2 + 0.05), yL - 0.03, dh / 2 + 0.03), Mt["trim"], bevel=0.0)
        K.box("reveal", (0.04, T, dh), (dc + s * (dw / 2 - 0.02), yL + T / 2, dh / 2), Mt["trim"], bevel=0.0)
    K.box("casing", (dw + 0.3, 0.07, 0.1), (dc, yL - 0.035, dh + 0.1), Mt["trim"], bevel=0.0)
    K.box("reveal", (dw, T, 0.03), (dc, yL + T / 2, dh - 0.015), Mt["trim"], bevel=0.0)
    p0, p1 = dc - dw / 2 - 0.15, dc + dw / 2 + 0.15
    flat("vinyl_door", [(p0, dh + 0.15), (p1, dh + 0.15), (p1, rake(L, p1) - 0.02), (p0, rake(L, p0) - 0.02)],
         yL - 0.02, yL + 0.001, Mt["vinyl"])
    # the house number and the porch lamps either side of the door
    K.box("number_plate", (0.14, 0.03, 0.4), (dc - dw / 2 - 0.45, yL - 0.015, 1.55), Mt["trim"], bevel=0.0)
    for s in (-1, 1):
        lx = dc + s * (dw / 2 + 0.38)
        K.box("lamp", (0.16, 0.12, 0.3), (lx, yL - 0.1, 1.85), Mt["lamp"], bevel=0.01)
        K.box("lamp_glass", (0.12, 0.1, 0.2), (lx, yL - 0.105, 1.85), Mt["bulb"], bevel=0.0)
    # a slim white post at the porch's outer corner, up to the roof
    px, py = L[0] + 0.12, yL - PORCH + 0.15
    K.box("porch_post", (0.12, 0.12, rake(L, px) - 0.08), (px, py, (rake(L, px) - 0.08) / 2), Mt["trim"], bevel=0.0)
    K.box("porch_slab", (R[0] - L[0] - 0.1, PORCH - 0.1, 0.08), ((L[0] + R[0]) / 2, yL - PORCH / 2, 0.04), Mt["paving"], bevel=0.01)
    # white downspouts at the front corners
    for x, y in ((rx0 - 0.08, yL - 0.08), (rx1 - 0.08, yR - 0.08)):
        K.box("downspout", (0.07, 0.07, L[4] if x < rx0 else R[4]), (x, y, (L[4] if x < rx0 else R[4]) / 2), Mt["trim"], bevel=0.0)
    # under the entry wing's slope coming down to the right wing, in front of the upper wing's wall:
    # the wedge of brick between the two rakes, as in the photo
    valley_fill(Mt, M[2] - 0.13, 1)


def garage_door(Mt, xf):
    """The white sectional garage door in the garage's left side (its outer face on x = xf), four rows
    of panels, its casing, a lamp either side."""
    gc, gw, gh = GDOOR
    x = xf + 0.12
    K.box("garage_door", (0.05, gw, gh), (x, gc, gh / 2), Mt["trim"], bevel=0.0)
    rows, cols = 4, 4
    for k in range(rows):
        for j in range(cols):
            K.box("garage_panel", (0.02, gw / cols - 0.08, gh / rows - 0.12),
                  (x - 0.035, gc - gw / 2 + (j + 0.5) * gw / cols, (k + 0.5) * gh / rows), Mt["trim"], bevel=0.008)
    for s in (-1, 1):
        K.box("casing", (0.07, 0.12, gh + 0.06), (xf - 0.035, gc + s * (gw / 2 + 0.06), gh / 2 + 0.03), Mt["trim"], bevel=0.0)
        K.box("reveal", (0.12, 0.04, gh), (xf + 0.06, gc + s * (gw / 2 - 0.02), gh / 2), Mt["trim"], bevel=0.0)
        K.box("lamp", (0.12, 0.16, 0.3), (xf - 0.08, gc + s * (gw / 2 + 0.45), 1.95), Mt["lamp"], bevel=0.01)
        K.box("lamp_glass", (0.1, 0.12, 0.2), (xf - 0.085, gc + s * (gw / 2 + 0.45), 1.95), Mt["bulb"], bevel=0.0)
    K.box("casing", (0.07, gw + 0.36, 0.12), (xf - 0.035, gc, gh + 0.06), Mt["trim"], bevel=0.0)


def wall_back(Mt, low):
    ops = {"L": [], "R": []}
    for blk, side, c, w, zb, zt in SIDE_WINDOWS:
        if side == "back":
            ops[blk].append((c, w, zb, zt))
    lined_wall(Mt, "back", L[3], L[0], R[0], L[4], ops["L"], low)
    lined_wall(Mt, "back", R[3], R[0], R[1], R[4], ops["R"], low)
    # the right wing's left wall where it runs on past the entry wing's back
    lined_wall(Mt, "left", R[0], L[3], R[3] - T, R[4], [], low)
    if low:
        return
    gable(Mt, L, L[3], "brick", -1, upto=R[0])
    # (the right wing's back gable is inside the upper wing's back wall)
    for blk, side, c, w, zb, zt in SIDE_WINDOWS:
        if side == "back":
            window(Mt, "back", L[3] if blk == "L" else R[3], c, w, zb, zt)
    # the back door (inferred) in the right wing: a white leaf, shut
    K.box("back_door", (0.95, 0.06, 2.05), (BACK_DOOR, R[3] + 0.02, 1.03), Mt["door"], bevel=0.0)
    K.box("casing", (1.15, 0.06, 0.1), (BACK_DOOR, R[3] + 0.04, 2.1), Mt["trim"], bevel=0.0)


def wall_side(Mt, side, low):
    b = L if side == "left" else R
    plane = b[0] if side == "left" else b[1]
    ops = [(c, w, zb, zt) for blk, s, c, w, zb, zt in SIDE_WINDOWS if s == side and blk == ("L" if side == "left" else "R")]
    if side == "left":
        lined_wall(Mt, side, plane, b[2] + T, b[3] - T, b[4], ops, low)
    else:
        # the garage's stretch (bare brick, its side door) and the rooms' (plastered inside)
        wall_run(side, plane, b[2] + T, HOUSE_FRONT + T, 0.0, LOW if low else b[4], Mt["brick"],
                 [o for o in ops if o[0] < HOUSE_FRONT] + [(GSIDE_DOOR, 0.9, -0.1, 2.05)])
        lined_wall(Mt, side, plane, HOUSE_FRONT + T, b[3] - T, b[4], [o for o in ops if o[0] > HOUSE_FRONT], low)
    if low:
        return
    for c, w, zb, zt in ops:
        window(Mt, side, plane, c, w, zb, zt)
    if side == "right":  # the garage's side door, shut
        K.box("side_door", (0.06, 0.88, 2.04), (plane - 0.08, GSIDE_DOOR, 1.02), Mt["door"], bevel=0.0)
        K.box("casing", (0.06, 1.1, 0.1), (plane + 0.03, GSIDE_DOOR, 2.1), Mt["trim"], bevel=0.0)
        for s in (-1, 1):
            K.box("casing", (0.06, 0.1, 2.1), (plane + 0.03, GSIDE_DOOR + s * 0.5, 1.05), Mt["trim"], bevel=0.0)

def slab(Mt, b, ends=(True, True), clip=None, front=OVE, back=OVE, meet=None, under=None):
    """A block's roof: two slopes, the ridge, white fascia and gutters along the eaves, rake boards
    and soffits. clip: the right slope stops at this x, inside the upper wing, untrimmed; meet: in
    front of the upper wing's wall (y < M's front) it runs on to this x, where it comes down onto the
    right wing's roof, its rake board with it. under: past this y (inside the upper wing) only the
    eaves run on, out from the walls, so no roof hangs through the rooms of a floor up there."""
    x0, x1, y0, y1, eave, p = b
    cx, hw = (x0 + x1) / 2, (x1 - x0) / 2
    t = tan(p)
    c = math.cos(math.radians(p))
    ya, yb = y0 - front, y1 + back
    ze = eave - OV * t  # the underside at the eave's edge
    top = RT / c
    for s in (-1, 1):
        xe = cx + s * (hw + OV)
        if s > 0 and clip is not None:
            zc = eave + hw * t - (clip - cx) * t
            flat("roof", [(clip, zc), (cx, eave + hw * t), (cx, eave + hw * t + top), (clip, zc + top)], ya, yb, Mt["roof"])
            ends_at = {ya: clip, yb: clip}
            if meet is not None and meet > clip:
                zm = eave + hw * t - (meet - cx) * t
                flat("roof", [(meet, zm), (clip - 0.3, zc + 0.3 * t), (clip - 0.3, zc + 0.3 * t + top), (meet, zm + top)],
                     ya, M[2] - 0.01, Mt["roof"])
                ends_at[ya] = meet
            for ye, xr in ends_at.items():
                zr = eave + hw * t - (xr - cx) * t
                band = [(xr, zr + top + 0.03), (cx, eave + hw * t + top + 0.03), (cx, eave + hw * t - 0.16), (xr, zr - 0.16)]
                flat("rake", band, ye - 0.035, ye + 0.015, Mt["trim"])
            continue
        pts = [(xe, ze), (cx, eave + hw * t), (cx, eave + hw * t + top), (xe, ze + top)]
        if under is None:
            flat("roof", pts, ya, yb, Mt["roof"])
        else:
            flat("roof", pts, ya, under, Mt["roof"])
            xw = cx + s * (hw - T / 2)  # into the hollow wall, so the joint can't be seen
            zw = eave + T / 2 * t
            flat("roof", [(xe, ze), (xw, zw), (xw, zw + top), (xe, ze + top)], under - 0.01, yb, Mt["roof"])
        # fascia and gutter along the eave, the soffit under the overhang
        K.box("fascia", (0.04, yb - ya, 0.24), (xe + s * 0.02, (ya + yb) / 2, ze + top - 0.1), Mt["trim"], bevel=0.0)
        K.box("gutter", (0.12, yb - ya, 0.11), (xe + s * 0.08, (ya + yb) / 2, ze + top - 0.12), Mt["trim"], bevel=0.0)
        K.box("soffit", (OV, yb - ya - 0.02, 0.02), (cx + s * (hw + OV / 2), (ya + yb) / 2, ze - 0.01), Mt["trim"], bevel=0.0)
        # rake boards up the gable ends
        for ye, on in ((ya, ends[0]), (yb, ends[1])):
            if not on:
                continue
            band = [(xe, ze + top + 0.03), (cx, eave + hw * t + top + 0.03), (cx, eave + hw * t - 0.16), (xe, ze - 0.16)]
            flat("rake", band, ye - 0.035, ye + 0.015, Mt["trim"])
            # the rake's soffit: under the roof past the gable wall
            und = [(xe, ze - 0.005), (cx, eave + hw * t - 0.005), (cx, eave + hw * t - 0.02), (xe, ze - 0.02)]
            flat("rake_soffit", und, min(ye, y0 if ye == ya else y1), max(ye, y0 if ye == ya else y1), Mt["trim"])
    yr = yb if under is None else under
    K.box("ridge", (0.26, yr - ya, 0.07), (cx, (ya + yr) / 2, eave + hw * t + top + 0.01), Mt["roof"], bevel=0.0)


def centre_block(Mt):
    """The cream centre gable: its walls stand from inside the rooms up through the low roofs to
    their own eave, with a gable front and back."""
    x0, x1, y0, y1, eave, p = M
    wall_run("front", y0, x0, x1, MB, eave, Mt["vinyl"])
    wall_run("back", y1, x0, x1, MB, eave, Mt["vinyl"])
    wall_run("left", x0, y0 + T, y1 - T, MB, eave, Mt["vinyl"])
    wall_run("right", x1, y0 + T, y1 - T, MB, eave, Mt["vinyl"])
    for y, inward in ((y0, 1), (y1, -1)):
        g = gable(Mt, M, y, "vinyl", inward)


def roof(Mt):
    slab(Mt, L, clip=M[0] + 0.1, front=PORCH, meet=valley_x() + 0.05)  # its right slope ends inside the upper wing
    slab(Mt, R, ends=(True, False), back=-T - 0.02, under=M[2])  # under the upper wing only its eaves run on
    slab(Mt, M)
    centre_block(Mt)
    # the ceiling over the rooms (the entry wing's only as far as the right wing)
    for x0, x1, y0, y1, mat in ((L[0] + T, R[0], L[2] + T, L[3] - T, "lining"), (R[0] + T, R[1] - T, HOUSE_FRONT + T, R[3] - T, "lining_r")):
        K.box("ceiling", (x1 - x0, y1 - y0, 0.03), ((x0 + x1) / 2, (y0 + y1) / 2, CEIL + 0.015), Mt[mat], bevel=0.0)


def base(Mt):
    for x0, x1, y0, y1 in ((L[0] + 0.05, R[0], L[2] + 0.05, L[3] - 0.05), (R[0], R[1] - 0.05, HOUSE_FRONT + 0.05, R[3] - 0.05)):
        K.box("floor", (x1 - x0, y1 - y0, FLOOR), ((x0 + x1) / 2, (y0 + y1) / 2, FLOOR / 2), Mt["floor"], bevel=0.0)
    dc = DOOR[0]
    K.box("stoop", (1.9, 1.1, 0.12), (dc, L[2] - 0.55, 0.06), Mt["paving"], bevel=0.01)
    K.box("back_step", (1.5, 0.9, 0.1), (BACK_DOOR, R[3] + 0.45, 0.05), Mt["paving"], bevel=0.01)
    # the garage's concrete floor and the apron in front of its door
    K.box("garage_floor", (R[1] - R[0] - 0.4, GARAGE_D - 0.2, 0.05), ((R[0] + R[1]) / 2, R[2] + GARAGE_D / 2, 0.025), Mt["paving"], bevel=0.0)
    # (out to the driveway in front of the porch, suburb.gd DRIVE_X)
    K.box("garage_apron", (1.9, GDOOR[1] + 0.4, 0.06), (R[0] - 0.95, GDOOR[0], 0.03), Mt["paving"], bevel=0.01)


def door(Mt):
    """The front door, shut, its origin on the hinge (the left jamb seen from outside)."""
    dc, dw, dh = DOOR
    y = L[2] + 0.06
    K.box("door_leaf", (dw - 0.02, 0.05, dh - 0.02), (dc, y, dh / 2), Mt["door"], bevel=0.008)
    for zc in (0.55, 1.45):  # raised panels
        for s in (-1, 1):
            K.box("door_panel", (dw * 0.32, 0.02, 0.62), (dc + s * dw * 0.21, y - 0.03, zc), Mt["door"], bevel=0.01)
    K.cyl("knob", 0.03, 0.03, 0.06, (dc + dw / 2 - 0.1, y - 0.06, 1.0), Mt["brass"], verts=10, rot=(90, 0, 0))
    # the wreath, with a red bow
    K.torus("wreath", 0.2, 0.06, (dc, y - 0.09, 1.55), Mt["wreath"], rot=(90, 0, 0), major=18, minor=6)
    K.box("bow", (0.16, 0.03, 0.08), (dc, y - 0.15, 1.36), Mt["bow"], bevel=0.02)
    HINGES["door"] = (dc - dw / 2, y, 0.0)


def join_part(name, obs, origin=None):
    for o in obs:
        K.apply_mods(o)
        if "UVMap" not in o.data.uv_layers:
            if o.data.uv_layers:
                o.data.uv_layers[0].name = "UVMap"
            else:
                o.data.uv_layers.new(name="UVMap")
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = NAME + "_" + name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    if origin is not None:
        for v in ob.data.vertices:
            v.co -= Vector(origin)
        ob.location = origin
    return ob


def uv_all():
    """World-metre UVs on every surface: the brick, trim and shingles are mapped by the game in
    world space anyway, the siding's laps need v up the wall (1.08 m a tile)."""
    for o in K.COLL.objects:
        if o.type != "MESH":
            continue
        K.uv_box(o, 1.0 / 1.08)


def export(obs, name, budget):
    stats = {"name": name, "parts": {}, "triangles": 0}
    for o in obs:
        t = K.tri_count(o)
        stats["parts"][o.name] = {"triangles": t, "materials": [m.name if m else None for m in o.data.materials]}
        stats["triangles"] += t
    os.makedirs(OUT, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, name + ".blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    stats["glb_bytes"] = os.path.getsize(os.path.join(OUT, name + ".glb"))
    print("[ke] " + json.dumps(stats))
    if stats["triangles"] > budget:
        raise SystemExit("over the triangle budget")
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(OUT, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", os.path.join(PROPS, name + ".glb"))
    return stats


def build():
    K.reset(NAME)
    Mt = materials()
    with part("base"):
        base(Mt)
    for low in (False, True):
        sfx = "_low" if low else ""
        with part("wall_front" + sfx):
            wall_front(Mt, low)
        with part("wall_back" + sfx):
            wall_back(Mt, low)
        for side in ("left", "right"):
            with part("wall_" + side + sfx):
                wall_side(Mt, side, low)
    with part("door"):
        door(Mt)
    with part("roof"):
        roof(Mt)
    uv_all()
    obs = [join_part(n, [o for o in o_ if o.name in bpy.data.objects], HINGES.get(n)) for n, o_ in PARTS.items() if o_]
    stats = export(obs, NAME, 40000)
    with open(os.path.join(OUT, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    print("FOOTPRINT x %.2f..%.2f, Godot z %.2f..%.2f (the rooms to %.2f, the garage in front); door hinge %s"
          % (L[0], R[1], -R[3], -R[2], -HOUSE_FRONT, HINGES["door"]))


# --- the plants in front of it ---------------------------------------------------------------------

def foliage_maps(name, base, light, dark, n=256, seed=1):
    """Dense small-leaved foliage: clumps of light and dark."""
    a = K.tile_noise(n, 0.9, seed)
    b = K.tile_noise(n, 1.8, seed + 1)
    t = np.clip(a * 0.7 + b * 0.5 - 0.1, 0, 1)
    c = rgb(dark) * (1 - t[..., None]) + rgb(base) * t[..., None]
    c = np.where((a > 0.78)[..., None], rgb(light), c)
    hgt = a + 0.5 * b
    return K.save_image(name, c, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 4.0), TEX)


def lumpy(name, r, loc, mat, scale, seed, amp=0.18, subdiv=3):
    """A noisy blob: an icosphere pushed in and out by noise, so foliage reads as clumps."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    K.COLL.objects.link(ob)
    tex = bpy.data.textures.new(name + "_n", "CLOUDS")
    tex.noise_scale = 0.35
    tex.noise_depth = 2
    d = ob.modifiers.new("disp", "DISPLACE")
    d.texture = tex
    d.strength = amp
    d.mid_level = 0.5
    d.texture_coords = "GLOBAL"
    ob.data.materials.append(mat)
    bpy.context.view_layer.update()
    K.apply_mods(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    K.smooth(ob, keep_sharp=False)
    return ob


def plants():
    # the arborvitae: a tall narrow column (3.4 m, about 1 m across), rounded at the foot, pointed at the top
    K.reset("arborvitae")
    i, n = foliage_maps("arborvitae_leaf", "#4a7a2c", "#7ea543", "#24401a", seed=21)
    leaf = K.textured("arborvitae_leaf", i, 0.85, normal=n, normal_strength=1.2)
    trunk = K.plain("arborvitae_trunk", "#4a3424", 0.9)
    K.cyl("trunk", 0.06, 0.05, 0.3, (0, 0, 0.15), trunk, verts=8)
    # one smooth, dense column (the photo's are clipped smooth), a little fuller below the middle
    rng = np.random.default_rng(3)
    for k in range(13):
        z = 0.45 + k * 0.22
        f = 1.0 - (k / 13.0) ** 3.0
        r = 0.44 * f + 0.1
        lumpy("leaves", r, (rng.normal(0, 0.02), rng.normal(0, 0.02), z), leaf, (1.0, 1.0, 1.35), k, amp=0.05 * f + 0.03, subdiv=2)
    lumpy("tip", 0.2, (0, 0, 3.3), leaf, (1, 1, 1.4), 99, amp=0.04, subdiv=2)
    for o in K.COLL.objects:
        K.uv_box(o, 1.6)
    ob = join_part("arborvitae", list(K.COLL.objects))
    ob.data.name = "arborvitae"
    export([ob], "arborvitae", 12000)
    # the red-leaf shrub at the corner: a loose mound of wine-red leaves, about 2.2 m across, 1.8 m tall
    K.reset("red_shrub")
    i, n = foliage_maps("red_shrub_leaf", "#5c1f29", "#8a3a42", "#2c0c12", seed=31)
    leaf = K.textured("red_shrub_leaf", i, 0.85, normal=n, normal_strength=1.2)
    rng = np.random.default_rng(7)
    for k in range(14):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.65)
        z = rng.uniform(0.6, 1.45)
        lumpy("leaves", rng.uniform(0.42, 0.6), (d * math.cos(a), d * math.sin(a), z), leaf, (1, 1, 0.9), k + 40, amp=0.16, subdiv=2)
    for o in K.COLL.objects:
        K.uv_box(o, 1.6)
    ob = join_part("red_shrub", list(K.COLL.objects))
    ob.data.name = "red_shrub"
    export([ob], "red_shrub", 12000)


if "plants" in sys.argv:
    plants()
else:
    build()
