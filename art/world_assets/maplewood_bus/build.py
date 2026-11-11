"""The Maplewood bus from the opening scene, after Alex's reference picture: a dark green
single-decker with a cream stripe, warm-lit windows, two double doors and a roof unit.

6.4 m long, the same as the game's stand-in. Front faces +X (the way @prop_move drives it); the
doors are on the -Y side here (+Z in Godot, the side Nora steps off towards the camera).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/maplewood_bus/build.py
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

NAME = "maplewood_bus"
TEX = os.path.join(HERE, "tex")
K.reset(NAME)

GREEN = "#203b29"
G = np.array(K.hex_rgb(GREEN))


def rect(a, x0, y0, x1, y1, col, alpha=1.0):
    a[int(y0):int(y1), int(x0):int(x1)] = a[int(y0):int(y1), int(x0):int(x1)] * (1 - alpha) + np.array(col) * alpha


def paint_image(w=1024, h=512):
    """Body paint: panel seams, a little brushed variation, road dust along the bottom."""
    streak = K.grain_noise(w, 20.0, 1.2, 2)[:h]
    mott = K.tile_noise(w, 1.6, 6, m=h)
    rgb = G * (0.9 + 0.2 * streak[..., None]) * (0.94 + 0.12 * mott[..., None])
    yy, xx = np.mgrid[0:h, 0:w]
    seam = np.minimum(xx % 256, 256 - xx % 256)
    rgb *= (1 - 0.35 * np.clip(1 - seam / 2.0, 0, 1))[..., None]
    rgb += 0.035 * np.clip(1 - np.abs(seam - 4) / 2.0, 0, 1)[..., None]
    up = 1 - yy / h
    dust = np.clip((0.3 - up + 0.25 * (mott - 0.5)) * 5.0, 0, 1)[..., None] * 0.6
    rgb = rgb * (1 - dust) + np.array(K.hex_rgb("#6f6650")) * dust
    return K.save_image("bus_paint", rgb, TEX)


def interior(w, h, seed):
    """The lit inside of the bus seen through glass: warm wall, seat backs, a yellow grab rail."""
    a = np.zeros((h, w, 3))
    yy = np.mgrid[0:h, 0:w][0] / h
    a[:] = np.array(K.hex_rgb("#d9b47c")) * (1.05 - 0.35 * yy[..., None])
    rect(a, 0, 0, w, h * 0.12, K.hex_rgb("#f0d9a6"))  # ceiling light strip
    rect(a, 0, h * 0.2, w, h * 0.235, K.hex_rgb("#e3b62f"))  # grab rail
    return a


def window_image(seats=2, w=256, h=224, seed=0):
    a = interior(w, h, seed)
    sw = w / seats
    for i in range(seats):
        x0 = i * sw + sw * 0.16
        rect(a, x0, h * 0.42, x0 + sw * 0.68, h, K.hex_rgb("#a07850"))
        rect(a, x0 + sw * 0.06, h * 0.47, x0 + sw * 0.62, h * 0.8, K.hex_rgb("#c39a68"))
        rect(a, x0 + sw * 0.2, h * 0.34, x0 + sw * 0.48, h * 0.44, K.hex_rgb("#a07850"))  # headrest
    glass_finish(a)
    return a


def glass_finish(a, frame=9):
    h, w, _ = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    streak = np.clip(1 - np.abs((xx - yy * 0.6) % (w * 0.9) - w * 0.25) / 26.0, 0, 1)[..., None]
    a += 0.1 * streak  # a soft reflection across the glass
    a *= 0.92
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    a[d < frame] = K.hex_rgb("#1d1f1e")
    return a


def door_image(w=256, h=448):
    a = np.zeros((h, w, 3))
    a[:] = K.hex_rgb("#1d1f1e")
    for i in range(2):
        x0, x1 = i * w / 2 + 10, (i + 1) * w / 2 - 10
        pane_ = interior(int(x1 - x0), int(h * 0.78), 3)
        ph, pw, _ = pane_.shape
        yy, xx = np.mgrid[0:ph, 0:pw]
        # the diagonal yellow handrail behind each leaf
        t = xx / pw if i == 0 else 1 - xx / pw
        rail = np.abs(yy - (ph * 0.82 - t * ph * 0.3)) < 4
        pane_[rail] = K.hex_rgb("#e3b62f")
        post = np.abs(xx - (pw * 0.85 if i == 0 else pw * 0.15)) < 3
        pane_[post & (yy > ph * 0.25)] = K.hex_rgb("#e3b62f")
        pane_ += 0.08 * np.clip(1 - np.abs(xx - yy * 0.5 - pw * 0.1) / 16.0, 0, 1)[..., None]
        a[int(h * 0.05):int(h * 0.05) + ph, int(x0):int(x0) + pw] = pane_ * 0.92
    rect(a, 0, h * 0.955, w, h, K.hex_rgb("#8d8f8c"))  # the step plate
    return a


def windscreen_image(w=512, h=224):
    a = np.zeros((h, w, 3))
    yy, xx = np.mgrid[0:h, 0:w]
    a[:] = np.array(K.hex_rgb("#33414a")) * (0.75 + 0.5 * (yy / h))[..., None]
    a += np.array(K.hex_rgb("#d9b47c")) * 0.35 * np.clip((yy / h - 0.45) * 2, 0, 1)[..., None]  # dash glow
    a += 0.12 * np.clip(1 - np.abs(xx - yy * 0.7 - w * 0.2) / 40.0, 0, 1)[..., None]
    rect(a, w * 0.495, 0, w * 0.505, h, K.hex_rgb("#1d1f1e"))
    glass_finish(a, frame=8)
    return a


paint = K.textured("BusPaint", paint_image())
win = [K.textured("BusWindow_%d" % i, K.save_image("bus_window_%d" % i, window_image(2 if i else 1, seed=i), TEX), rough=0.3, emit=0.55) for i in range(2)]
door = K.textured("BusDoor", K.save_image("bus_door", door_image(), TEX), rough=0.3, emit=0.5)
screen = K.textured("BusWindscreen", K.save_image("bus_windscreen", windscreen_image(), TEX), rough=0.25, emit=0.25)
green = K.plain("BusGreen", GREEN, rough=0.6)
green_dark = K.plain("BusGreenDark", "#1a3022", rough=0.65)
black, tyre = K.plain("BusBlack", "#18191a", rough=0.45), K.plain("BusTyre", "#1b1b1c", rough=0.95)
amber = K.plain("BusAmber", "#f5a623", rough=0.4, emit=2.5)
lamp = K.plain("BusHeadlamp", "#fff0c2", rough=0.3, emit=3.0)
red = K.plain("BusTailRed", "#c8332c", rough=0.4, emit=1.2)
stripe = K.wool("rug_oat")
hub = K.wool("stone")

L, W = 6.3, 2.26
HWID = W / 2

# --- body --------------------------------------------------------------------------------------
K.box("under", (5.9, 2.0, 0.22), (0, 0, 0.34), black, bevel=0.03)
K.uv_box(K.box("lower", (L, W, 0.98), (0, 0, 0.79), paint, bevel=0.13, seg=3), 1 / 2.56, v_from_z=(0.3, 1.28))
K.box("band", (L - 0.04, W - 0.03, 0.9), (0, 0, 1.68), black, bevel=0.1, seg=3)
K.box("upper", (L, W, 0.52), (0, 0, 2.31), green, bevel=0.17, seg=4)
K.box("stripe", (L + 0.012, W + 0.012, 0.085), (0, 0, 1.1), stripe, bevel=0.012, seg=1)

# --- glass: flat panes a centimetre proud of the black band, each with its own lit interior ------
YS = HWID - 0.015 + 0.012
Z0, Z1 = 1.36, 2.02


def side_pane(x, w, side, mat, z0=Z0, z1=Z1):
    y = side * YS
    a, b = ((x - w / 2, y, z0), (x + w / 2, y, z1)) if side < 0 else ((x + w / 2, y, z0), (x - w / 2, y, z1))
    K.pane("pane", a, b, mat, (0, side, 0))


DOORS = (2.28, -0.42)
for x, w, m in ((-2.72, 0.42, 0), (-2.05, 0.8, 1), (-1.2, 0.8, 1), (0.5, 0.78, 1), (1.33, 0.78, 1)):
    side_pane(x, w, -1, win[m])
for x in DOORS:  # double doors run from the step to the top of the glass, set into the body
    # the doors sit proud of the paint and the cream stripe, in a black frame
    K.box("door_frame", (1.0, 0.03, 1.72), (x, -HWID - 0.002, 1.2), black, bevel=0.012, seg=1)
    K.pane("door", (x - 0.46, -HWID - 0.02, 0.38), (x + 0.46, -HWID - 0.02, 2.02), door, (0, -1, 0))
for i in range(7):
    side_pane(-2.61 + i * 0.87, 0.78, 1, win[1])
XF = L / 2 - 0.02 + 0.012
K.pane("windscreen", (XF, -0.98, 1.3), (XF, 0.98, 2.03), screen, (1, 0, 0))
K.pane("rear_window", (-XF, 0.8, 1.45), (-XF, -0.8, 2.0), screen, (-1, 0, 0))

# --- front and back ------------------------------------------------------------------------------
FX = L / 2
K.box("sign", (0.05, 1.36, 0.25), (FX - 0.005, 0, 2.28), black, bevel=0.02, seg=1)
K.text("sign_text", "MAPLEWOOD", 0.15, (FX + 0.022, 0, 2.275), (90, 0, 90), amber)
for sy in (-1, 1):
    K.box("headlamp", (0.05, 0.4, 0.15), (FX, sy * 0.72, 0.74), lamp, bevel=0.03)
    K.box("indicator", (0.05, 0.14, 0.12), (FX - 0.01, sy * 1.0, 0.74), amber, bevel=0.03)
    K.box("tail", (0.05, 0.16, 0.3), (-FX, sy * 0.9, 0.86), red, bevel=0.03)
    K.box("tail_amber", (0.05, 0.16, 0.12), (-FX, sy * 0.9, 1.1), amber, bevel=0.03)
    K.box("top_marker", (0.06, 0.1, 0.07), (-FX + 0.03, sy * 0.86, 2.42), amber, bevel=0.02)
    # mirrors on black arms, hanging forward of the screen as in the reference
    K.box("mirror_arm", (0.3, 0.045, 0.045), (FX + 0.1, sy * 1.08, 2.12), black, bevel=0.015, seg=1)
    K.box("mirror", (0.07, 0.15, 0.36), (FX + 0.24, sy * 1.1, 1.93), black, bevel=0.03)
for i in range(3):
    K.box("grille", (0.03, 0.7, 0.03), (FX + 0.005, 0, 0.66 + i * 0.07), black, bevel=0.0)
for sx in (-1, 1):
    K.box("bumper", (0.14, W - 0.06, 0.2), (sx * (FX - 0.01), 0, 0.4), black, bevel=0.05)

# small amber markers low on both sides
for sy in (-1, 1):
    for x in (-2.75, 1.0, 2.95):
        K.box("marker", (0.12, 0.03, 0.06), (x, sy * (HWID + 0.002), 0.5), amber, bevel=0.01, seg=1)

# --- roof: two hatches and the slatted unit -----------------------------------------------------
for x in (-1.95, 1.75):
    K.box("hatch", (0.62, 0.62, 0.06), (x, 0, 2.585), green_dark, bevel=0.03)
K.box("roof_unit", (1.6, 1.25, 0.16), (-0.25, 0, 2.63), green_dark, bevel=0.06, seg=3)
for r in range(4):
    for c in range(3):
        K.box("slat", (0.36, 0.07, 0.02), (-0.72 + c * 0.47, -0.36 + r * 0.24, 2.712), black, bevel=0.0)

# --- wheels ------------------------------------------------------------------------------------
for x in (1.42, -2.0):
    # a dark wheel well flush with the paint, the tyre standing a little proud of it
    K.cyl("arch", 0.52, 0.52, W + 0.004, (x, 0, 0.5), black, verts=28, rot=(90, 0, 0))
    for sy in (-1, 1):
        K.cyl("tyre", 0.44, 0.44, 0.3, (x, sy * (HWID - 0.11), 0.44), tyre, verts=28, rot=(90, 0, 0), bevel=0.07, seg=3)
        K.cyl("hub", 0.25, 0.25, 0.3, (x, sy * (HWID - 0.09), 0.44), hub, verts=20, rot=(90, 0, 0), bevel=0.03)
        K.cyl("hub_cap", 0.09, 0.09, 0.3, (x, sy * (HWID - 0.075), 0.44), K.wool("stone_dark"), verts=12, rot=(90, 0, 0), bevel=0.02)

K.finish(NAME, os.path.join(HERE, "out"), max_tris=14000)
