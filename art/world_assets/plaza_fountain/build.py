"""The Maplewood plaza fountain, after Alex's reference picture: an eight-sided basin of dressed
stone blocks under wide coping slabs, and in the middle a baluster carrying a shallow bowl whose
water jets up and spills over the rim.

Fits the game's fountain spot (town.gd: a 3.5 m square blocker).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/plaza_fountain/build.py
"""
import math
import os
import sys

import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

NAME = "plaza_fountain"
TEX = os.path.join(HERE, "tex")
K.reset(NAME)

# warm sandstone: the palette's stone pulled towards oat, as in the evening light of the reference
STONE = (np.array(K.pal_srgb("stone")) * 0.6 + np.array(K.pal_srgb("path")) * 0.4) * 0.95
DARK = np.array(K.pal_srgb("stone_dark")) * 0.8 + np.array(K.pal_srgb("wood_dark")) * 0.2
MOSS = np.array(K.pal_srgb("moss"))


def stone_maps(name, w, h, blocks=0, courses=0, joint_px=6, moss=0.0, seed=3):
    """Colour and normal map for hewn stone. blocks/courses > 0 cuts it into bonded blocks."""
    mott = K.tile_noise(w, 1.5, seed, m=h)
    speck = K.tile_noise(w, 0.45, seed + 6, m=h)
    pit = K.tile_noise(w, 0.9, seed + 11, m=h)
    yy, xx = np.mgrid[0:h, 0:w]
    rgb = STONE * (0.8 + 0.34 * mott[..., None]) * (0.94 + 0.12 * speck[..., None])
    hgt = 0.25 * mott + 0.35 * pit
    if blocks:
        ch, bw = h / courses, w / blocks
        row = (yy // ch).astype(int)
        xo = (xx + (row % 2) * bw / 2) % w
        col = (xo // bw).astype(int)
        rng = np.random.default_rng(seed)
        tint = (0.8 + 0.36 * rng.random((courses, blocks)))[row, col]
        warm = (rng.random((courses, blocks)) - 0.5)[row, col][..., None] * np.array([0.05, 0.0, -0.05])
        rgb = rgb * tint[..., None] + warm
        d = np.minimum(np.minimum(xo % bw, bw - xo % bw), np.minimum(yy % ch, ch - yy % ch))
        joint = np.clip(1 - d / joint_px, 0, 1)
        rgb = rgb * (1 - joint[..., None]) + DARK * 0.7 * joint[..., None]
        chamfer = np.clip(d / (joint_px * 2.5), 0, 1)
        hgt = hgt * 0.6 + 2.2 * chamfer
        rgb = rgb + 0.04 * np.clip(1 - np.abs(d - joint_px * 1.8) / 4.0, 0, 1)[..., None]
    if moss > 0:
        up = yy / h  # 0 at the top of the image, 1 at the bottom
        m = np.clip((up - (1 - moss) + 0.5 * (mott - 0.5)) * 4.0, 0, 1)[..., None] * 0.65
        rgb = rgb * (1 - m) + MOSS * (0.8 + 0.4 * speck[..., None]) * m
    col_img = K.save_image(name, rgb, TEX)
    nrm_img = K.save_image(name + "_normal", K.normal_from_height(hgt, 1.6), TEX)
    return col_img, nrm_img


def water_maps(n=512, splashes=8, splash_r=0.6):
    """Still green-grey water with rings spreading from the middle and from where each fall lands."""
    yy, xx = np.mgrid[0:n, 0:n]
    x, y = xx / n - 0.5, 0.5 - yy / n
    hgt = np.zeros((n, n))

    def rings(cx, cy, freq, reach, amp):
        d = np.hypot(x - cx, y - cy)
        return amp * np.sin(d * freq) * np.exp(-d / reach)

    hgt += rings(0, 0, 75.0, 0.45, 0.45)
    for i in range(splashes):
        a = math.pi / splashes + i * math.tau / splashes
        hgt += rings(splash_r * 0.5 * math.cos(a), splash_r * 0.5 * math.sin(a), 120.0, 0.08, 0.8)
    hgt += 0.5 * (K.tile_noise(n, 1.2, 21) - 0.5)
    deep, shallow, sky = np.array(K.hex_rgb("#3f5f5c")), np.array(K.hex_rgb("#6f8f86")), np.array(K.hex_rgb("#cfe0d6"))
    r = np.hypot(x, y)[..., None] * 2
    rgb = deep * (1 - r * 0.5) + shallow * r * 0.5
    crest = np.clip(hgt, 0, 1)[..., None]
    rgb = rgb * (1 - 0.45 * crest) + sky * 0.45 * crest
    return K.save_image("plaza_fountain_water", rgb, TEX), K.save_image("plaza_fountain_water_normal", K.normal_from_height(hgt, 3.0), TEX)


b_img, b_nrm = stone_maps("plaza_fountain_blocks", 1024, 512, blocks=4, courses=2, moss=0.2)
blocks = K.textured("Stone_blocks", b_img, rough=0.92, normal=b_nrm)
c_img, c_nrm = stone_maps("plaza_fountain_coping", 512, 256, blocks=2, courses=1, joint_px=4, seed=8)
coping = K.textured("Stone_coping", c_img, rough=0.88, normal=c_nrm)
p_img, p_nrm = stone_maps("plaza_fountain_plain", 512, 512, seed=14)
hewn = K.textured("Stone_hewn", p_img, rough=0.9, normal=p_nrm, normal_strength=0.7)
w_img, w_nrm = water_maps()
water = K.textured("Water_fountain", w_img, rough=0.06, normal=w_nrm, normal_strength=0.8)
fall = K.plain("Water_fall", "#e6f3f2", rough=0.2, alpha=0.42)
foam = K.plain("Water_foam", "#eef7f5", rough=0.35, alpha=0.7)
iron = K.wool("iron")

TURN = math.radians(22.5)  # flats face the plaza's four sides


def octa(name, profile, mat, u_rep, v_rep=1.0):
    ob = K.lathe(name, profile, mat, steps=8, u_rep=u_rep, v_rep=v_rep, sharp=30)
    ob.rotation_euler = (0, 0, TURN)
    return ob


# --- the basin: plinth course, two courses of blocks, coping slabs, dark inside ------------------
R = 1.72
octa("plinth", [(R + 0.06, 0.0), (R + 0.06, 0.13), (R + 0.02, 0.17), (R, 0.17)], coping, 8, 0.5)
octa("wall", [(R, 0.17), (R, 0.6)], blocks, 6)
octa("coping", [(R, 0.6), (R + 0.09, 0.62), (R + 0.09, 0.71), (R + 0.06, 0.74), (R - 0.33, 0.74), (R - 0.36, 0.71), (R - 0.36, 0.6)],
     coping, 8, 1.6)
octa("inside", [(R - 0.36, 0.62), (R - 0.36, 0.25), (0.4, 0.25)], hewn, 4, 2.0)
K.disc("water_low", R - 0.36, 0.62, water, steps=8, turn=TURN)

# --- the middle: eight-sided foot, round baluster, shallow moulded bowl ---------------------------
octa("foot", [(0.56, 0.25), (0.56, 0.7), (0.5, 0.76), (0.3, 0.78)], hewn, 2, 1.0)
K.lathe("baluster", [(0.34, 0.78), (0.36, 0.82), (0.3, 0.86), (0.33, 0.92), (0.36, 1.02), (0.34, 1.12), (0.26, 1.24), (0.2, 1.32), (0.2, 1.37), (0.27, 1.41), (0.24, 1.45)],
        hewn, 20, u_rep=2, v_rep=1.0, sharp=35)
K.lathe("bowl", [(0.24, 1.45), (0.44, 1.5), (0.64, 1.6), (0.72, 1.69), (0.77, 1.71), (0.78, 1.78), (0.75, 1.82), (0.68, 1.82),
                 (0.65, 1.78), (0.45, 1.71), (0.06, 1.69)], hewn, 28, u_rep=3, v_rep=1.5, sharp=45)
BOWL_R, BOWL_Z = 0.655, 1.79
K.disc("water_high", BOWL_R, BOWL_Z, water, steps=28)
K.cyl("nozzle", 0.035, 0.03, 0.12, (0, 0, BOWL_Z + 0.04), iron, verts=8)

# --- water: the jet, the spills over the rim, splashes -------------------------------------------
# a narrow plume that rises, mushrooms and falls back in thin arcs
K.lathe("jet", [(0.022, BOWL_Z + 0.08), (0.03, BOWL_Z + 0.3), (0.05, BOWL_Z + 0.42), (0.06, BOWL_Z + 0.47), (0.04, BOWL_Z + 0.51), (0.0, BOWL_Z + 0.52)],
        foam, 8, sharp=80)
for i in range(7):
    a = i * math.tau / 7 + 0.3
    c, s_ = math.cos(a), math.sin(a)
    pts = [(0.04 + 0.16 * t, BOWL_Z + 0.46 + 0.1 * t - 0.56 * t * t) for t in (0.0, 0.35, 0.7, 1.0)]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        p0, p1 = Vector((r0 * c, r0 * s_, z0)), Vector((r1 * c, r1 * s_, z1))
        seg = K.cyl("jet_arc", 0.009, 0.011, (p1 - p0).length + 0.01, (p0 + p1) / 2, fall, verts=5)
        seg.rotation_mode = "QUATERNION"
        seg.rotation_quaternion = (p0 - p1).to_track_quat("Z", "Y")
K.torus("jet_ring", 0.21, 0.008, (0, 0, BOWL_Z + 0.004), foam, major=18, minor=4)
K.torus("jet_ring2", 0.36, 0.005, (0, 0, BOWL_Z + 0.004), foam, major=22, minor=4)
rng = np.random.default_rng(5)
SPILLS = 8
for i in range(SPILLS):
    a = math.pi / SPILLS + i * math.tau / SPILLS
    c, s = math.cos(a), math.sin(a)
    # each spill leaves the rim, thins as it falls and lands in the basin
    pts = [(0.775 + 0.11 * t, 1.8 - 1.18 * t * t) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
    wide = 0.034
    for k, ((r0, z0), (r1, z1)) in enumerate(zip(pts, pts[1:])):
        p0, p1 = Vector((r0 * c, r0 * s, z0)), Vector((r1 * c, r1 * s, z1))
        seg = K.cyl("spill", 0.011 - 0.0015 * k, 0.013 - 0.0015 * k, (p1 - p0).length + 0.015, (p0 + p1) / 2, fall, verts=5)
        seg.rotation_mode = "QUATERNION"
        seg.rotation_quaternion = (p0 - p1).to_track_quat("Z", "Y")
        seg.scale = (wide / 0.012, 1, 1)  # a flat ribbon of water, not a rod
        wide *= 0.8
    land = Vector((pts[-1][0] * c, pts[-1][0] * s, 0.624))
    K.torus("splash_ring", 0.1, 0.009, land, foam, major=16, minor=4)
    K.torus("splash_ring2", 0.2, 0.005, land, foam, major=18, minor=4)
    for _ in range(4):
        off = Vector((rng.normal(0, 0.06), rng.normal(0, 0.06), 0.03 + abs(rng.normal(0, 0.05))))
        K.ball("drop", 0.014 + 0.01 * rng.random(), land + off, foam, u=6, v=4)

# --- fallen maple leaves on the water and at the foot -----------------------------------------
leafcols = [K.wool("sunflower"), K.wool("gold"), K.wool("terracotta")]
for i in range(9):
    a, r = rng.random() * math.tau, 0.75 + rng.random() * 0.5
    K.star("leaf", 0.06 + 0.02 * rng.random(), (r * math.cos(a), r * math.sin(a), 0.626), leafcols[i % 2], turn=rng.random() * 3)
for i in range(5):
    a = rng.random() * math.tau
    r = R + 0.02 + rng.random() * 0.03
    K.star("leaf_ground", 0.07, (r * math.cos(a) * 0.97, r * math.sin(a) * 0.97, 0.012), leafcols[i % 3], turn=rng.random() * 3)

K.finish(NAME, os.path.join(HERE, "out"), max_tris=9000)
