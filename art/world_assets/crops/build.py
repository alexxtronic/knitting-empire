"""The crops in a farm plot, after Alex's reference art: stylised, chunky and painterly.

Pumpkins: deep-lobed glossy orange with hooked brown stems, five-lobed leaves and curly tendrils.
Turnips: cream bulbs with brushy magenta shoulders under an upright fan of wavy green leaves.

Four growth stages each (scripts/plot.gd, Plot.stage()): 0 seedlings, 1 young leaves, 2 growing,
3 ripe. One model per stage, sized to the 1 x 1 m plot (art/world_assets/dirt_plot): z = 0 is the
tilled bed (plot.gd lifts the crops by CROP_LIFT), three furrows run along Y at x = -0.283, 0, 0.283.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/crops/build.py -- all
    (or -- pumpkin 3, -- turnip 0 ...)
"""
import math
import os
import shutil
import sys

import bpy  # noqa: F401
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
ROWS = (-0.283, 0.0, 0.283)
MAX_TRIS = 9000


def ground(x):
    """Height of the plot's furrows (dirt_plot/build.py ridge()) at x, so plants sit on the soil."""
    u = (x + 0.425) / 0.85
    if u <= 0 or u >= 1:
        return 0.0
    w = (u * 3) % 1.0
    return 0.085 * max(0.0, math.sin(math.pi * w)) ** 0.7 - 0.005


def materials():
    m = {}
    i, n = CL.strap_leaf_maps("turnip_leaf", TEX)
    m["tleaf"] = K.textured("turnip_leaf", i, rough=0.55, normal=n, normal_strength=0.6)
    m["tstalk"] = K.plain("turnip_stalk", "#a8cf68", rough=0.55)
    i, n = CL.turnip_maps("turnip_bulb", TEX)
    m["bulb"] = K.textured("turnip_bulb", i, rough=0.42, normal=n, normal_strength=0.5)
    i, n = CL.pumpkin_maps("pumpkin_skin", TEX, ribs=10, base="#f25c00", light="#ff8a12", dark="#a83000", top="#c94600")
    m["pumpkin"] = K.textured("pumpkin_skin", i, rough=0.5, normal=n, normal_strength=0.6)
    i, n = CL.pumpkin_maps("pumpkin_small", TEX, ribs=8, base="#f56a00", light="#ff961f", dark="#b03a00", top="#cc5200")
    m["pumpkin_s"] = K.textured("pumpkin_small", i, rough=0.5, normal=n, normal_strength=0.6)
    i, n = CL.pumpkin_maps("pumpkin_green", TEX, ribs=8, green=True)
    m["pumpkin_g"] = K.textured("pumpkin_green", i, rough=0.4, normal=n, normal_strength=0.6)
    i, n = CL.stem_maps("pumpkin_stem", TEX)
    m["stem"] = K.textured("pumpkin_stem", i, rough=0.65, normal=n, normal_strength=0.8)
    m["stem_tip"] = K.plain("pumpkin_stem_tip", "#b07a45", rough=0.6)
    i, n = CL.palm_leaf_maps("pumpkin_leaf", TEX)
    m["pleaf"] = K.textured("pumpkin_leaf", i, rough=0.55, normal=n, normal_strength=0.6)
    m["vine"] = K.plain("pumpkin_vine", "#7aa63a", rough=0.55)
    m["tendril"] = K.plain("pumpkin_tendril", "#8cb845", rough=0.5)
    m["flower"] = K.plain("pumpkin_flower", "#f7b52c", rough=0.5)
    m["flower_in"] = K.plain("pumpkin_flower_in", "#e8891c", rough=0.5)
    return m


# --- turnips ---------------------------------------------------------------------------------------

def turnip_bulb(x, y, cz, R, m, rng):
    prof = [(0.0, -1.42), (0.03, -1.28), (0.07, -1.08), (0.16, -0.95)]
    for k in range(10):
        ph = math.radians(-62 + 140 * k / 9)
        prof.append((math.cos(ph), 0.94 * math.sin(ph)))
    prof += [(0.3, 0.98), (0.14, 1.02), (0.0, 1.0)]
    ob = K.lathe("bulb", [(r * R, z * R) for r, z in prof], m["bulb"], steps=16, sharp=70)
    ob.rotation_euler = (math.radians(rng.uniform(-6, 6)), math.radians(rng.uniform(-6, 6)), rng.uniform(0, 6.28))
    ob.location = (x, y, cz)
    return ob


def turnip(x, y, stage, m, rng):
    z0 = ground(x)
    yaw0 = rng.uniform(0, 360)
    if stage == 0:
        top = Vector((x, y, z0 + 0.04))
        CL.tube("sprout", [Vector((x, y, z0 - 0.01)), Vector((x, y, z0 + 0.02)), top], [0.0045, 0.004, 0.0035], m["tstalk"], sides=5)
        for k in (0, 180):
            CL.strap_leaf("coty", top, yaw0 + k, 0.065, 0.036, m["tleaf"], petiole=0.18, lift=40, droop=5, fold=0.2,
                          ns=5, petiole_mat=m["tstalk"], petiole_r=0.0035)
        return
    L, W, n, R, rise = {1: (0.14, 0.05, 4, 0.0, 0.0), 2: (0.21, 0.07, 5, 0.05, 0.0), 3: (0.28, 0.09, 6, 0.085, 0.0)}[stage]
    crown = z0 + 0.012
    if R:
        cz = z0 + (0.2 if stage == 3 else -0.4) * R
        turnip_bulb(x, y, cz, R, m, rng)
        crown = cz + 0.96 * R
    for k in range(n):
        yaw = yaw0 + 360 * k / n + rng.uniform(-14, 14)
        sc = rng.uniform(0.82, 1.08)
        CL.strap_leaf("tleaf", (x, y, crown), yaw, L * sc, W * sc, m["tleaf"], petiole=0.34, lift=rng.uniform(62, 80),
                      droop=rng.uniform(15, 40), fold=0.3, wave=0.12, lobes=0.16, ns=8, petiole_mat=m["tstalk"],
                      petiole_r=W * 0.11, twist=rng.uniform(-25, 25))


def build_turnip(stage, m):
    rng = np.random.default_rng(100 + stage)
    for x in ROWS:
        for y in (-0.21, 0.21):
            turnip(x + rng.uniform(-0.015, 0.015), y + rng.uniform(-0.03, 0.03), stage, m, rng)


# --- pumpkins --------------------------------------------------------------------------------------

def petiole(base, top, m, r=0.007):
    base, top = Vector(base), Vector(top)
    mid = base.lerp(top, 0.5) + Vector((0, 0, (top.z - base.z) * 0.4))
    pts = CL.bezier(base, base + Vector((0, 0, (top.z - base.z) * 0.7)), mid, top, n=6)
    CL.tube("petiole", pts, [r * (1 - 0.3 * i / 6) for i in range(7)], m["vine"], sides=5, v_scale=6.0)


def vine(pts, m, r=0.011):
    pts = CL.bezier(*pts, n=14)
    CL.tube("vine", pts, [r * (1 - 0.45 * i / 14) for i in range(15)], m["vine"], sides=6, v_scale=6.0)
    return pts


def leaf_on(base, m, R, yaw, h, pitch=12.0, rng=None):
    """A leaf on its stalk: the stalk rises from base to a point h up and a little out."""
    yr = math.radians(yaw)
    top = Vector(base) + Vector((math.cos(yr) * R * 0.25, math.sin(yr) * R * 0.25, h))
    petiole(base, top, m)
    CL.palm_leaf("pleaf", top, R, m["pleaf"], yaw=yaw, pitch=pitch, roll=(rng.uniform(-10, 10) if rng is not None else 0))


def pumpkin_fruit(cx, cy, R, H, mat, m, rng, stem=1.0, ribs=10, hook_yaw=None):
    z0 = ground(cx) - 0.012
    ob = CL.ribbed("pumpkin", R, H, mat, ribs=ribs, depth=0.13, dimple=0.17)
    ob.rotation_euler = (math.radians(rng.uniform(-4, 4)), math.radians(rng.uniform(-4, 4)), rng.uniform(0, 6.28))
    ob.location = (cx, cy, z0)
    if stem <= 0:
        return
    top = Vector((cx, cy, z0 + H * (1 - 0.17) - 0.01))
    sh = (0.05 + 0.32 * R) * stem
    hy = math.radians(hook_yaw if hook_yaw is not None else rng.uniform(0, 360))
    d = Vector((math.cos(hy), math.sin(hy), 0))
    pts = CL.bezier(top, top + Vector((0, 0, sh * 0.75)), top + d * sh * 0.15 + Vector((0, 0, sh * 1.1)),
                    top + d * sh * 0.55 + Vector((0, 0, sh * 0.85)), n=12)
    r = 0.01 + 0.085 * R
    radii = [r * (1.7 - 0.7 * min(1, i / 3)) * (1 - 0.3 * i / 12) for i in range(13)]
    CL.tube("stem", pts, radii, m["stem"], sides=8, v_scale=3.0)
    K.ball("stemtip", radii[-1] * 1.05, tuple(pts[-1]), m["stem_tip"], u=8, v=6)
    return top


def flower(pos, m, s=0.05, yaw=0.0):
    prof = [(0.0, 0.0), (s * 0.18, 0.0), (s * 0.22, s * 0.5), (s * 0.55, s * 0.95), (s * 0.85, s * 1.15), (s * 0.7, s * 1.1),
            (s * 0.3, s * 0.85), (0.0, s * 0.7)]
    ob = K.lathe("flower", prof, m["flower"], steps=10, sharp=50)
    for v in ob.data.vertices:  # five soft petal points round the rim
        a = math.atan2(v.co.y, v.co.x)
        if v.co.z > s * 0.9:
            f = 1 + 0.25 * math.cos(5 * a)
            v.co.x *= f
            v.co.y *= f
    ob.rotation_euler = (math.radians(35), 0, math.radians(yaw))
    ob.location = pos
    K.ball("flower_in", s * 0.16, (pos[0], pos[1], pos[2] + s * 0.6), m["flower_in"], u=6, v=4)


def seedling_pumpkin(x, y, m, rng):
    z0 = ground(x)
    top = Vector((x, y, z0 + 0.05))
    CL.tube("sprout", [Vector((x, y, z0 - 0.01)), Vector((x, y, z0 + 0.025)), top], [0.007, 0.006, 0.0055], m["vine"], sides=6)
    yaw0 = rng.uniform(0, 360)
    for k in (0, 180):
        CL.strap_leaf("coty", top, yaw0 + k, 0.075, 0.05, m["pleaf"], petiole=0.1, lift=22, droop=4, fold=0.12, ns=5,
                      petiole_mat=m["vine"], petiole_r=0.005)
    CL.palm_leaf("first", top + Vector((0, 0, 0.012)), 0.04, m["pleaf"], yaw=yaw0 + 90, pitch=40, cup=0.25, droop=0.1)


def build_pumpkin(stage, m):
    rng = np.random.default_rng(200 + stage)
    if stage == 0:
        for y in (-0.22, 0.22):
            seedling_pumpkin(rng.uniform(-0.02, 0.02), y, m, rng)
        return
    if stage == 1:
        for y in (-0.2, 0.2):
            x = rng.uniform(-0.02, 0.02)
            base = Vector((x, y, ground(x)))
            yaw0 = rng.uniform(0, 360)
            for k in range(3):
                leaf_on(base, m, rng.uniform(0.08, 0.1), yaw0 + 120 * k + rng.uniform(-15, 15), rng.uniform(0.09, 0.16), pitch=rng.uniform(15, 30), rng=rng)
            CL.tendril("tendril", base + Vector((0, 0, 0.05)), (math.cos(math.radians(yaw0 + 60)), math.sin(math.radians(yaw0 + 60)), 0.6),
                       m["tendril"], length=0.08, seed=stage + int(abs(y) * 10) + (1 if y > 0 else 0))
        return
    # stages 2 and 3: one plant whose vines run out over the plot
    base = Vector((0.0, 0.0, ground(0.0)))
    ends = [(0.36, -0.3), (-0.34, -0.26), (-0.3, 0.34), (0.34, 0.3)]
    leaf_spots = []
    vines = []
    for i, (ex, ey) in enumerate(ends):
        e = Vector((ex, ey, ground(ex) + 0.012))
        mid1 = Vector((ex * 0.35 + rng.uniform(-0.06, 0.06), ey * 0.35 + rng.uniform(-0.06, 0.06), 0.03))
        mid2 = Vector((ex * 0.7 + rng.uniform(-0.06, 0.06), ey * 0.7 + rng.uniform(-0.06, 0.06), 0.04))
        pts = vine([base + Vector((0, 0, 0.02)), mid1, mid2, e], m)
        vines.append(pts)
        leaf_spots += [pts[5], pts[10], pts[14]]
    rs = (0.15, 0.19) if stage == 2 else (0.16, 0.2)
    # room for the pumpkins: no leaf stands where a fruit will sit
    fruit = [(Vector((0.06, -0.08, 0)), 0.3), (Vector((-0.25, 0.25, 0)), 0.2)] if stage == 3 else [(Vector((vines[0][9].x, vines[0][9].y, 0)), 0.12)]
    for i, p in enumerate(leaf_spots):
        if any((Vector((p.x, p.y, 0)) - c).length < rad for c, rad in fruit):
            continue
        yaw = math.degrees(math.atan2(p.y, p.x)) + rng.uniform(-50, 50)
        leaf_on(p, m, rng.uniform(*rs), yaw, rng.uniform(0.07, 0.17), pitch=rng.uniform(5, 22), rng=rng)
    leaf_on(base, m, 0.15, rng.uniform(0, 360), 0.2, pitch=20, rng=rng)
    for k, i in enumerate((0, 2, 3)):
        p = vines[i][8]
        d = (vines[i][9] - vines[i][7]).normalized()
        side = Vector((-d.y, d.x, 0.5)).normalized() * (1 if k % 2 else -1)
        CL.tendril("tendril", p + Vector((0, 0, 0.01)), side + Vector((0, 0, 0.5)), m["tendril"], length=0.11, seed=10 + k)
    if stage == 2:
        flower(tuple(vines[1][7] + Vector((0, 0, 0.03))), m, s=0.055, yaw=30)
        flower(tuple(vines[3][11] + Vector((0, 0, 0.03))), m, s=0.05, yaw=-60)
        p = vines[0][9]
        pumpkin_fruit(p.x, p.y, 0.085, 0.11, m["pumpkin_g"], m, rng, stem=0.6, ribs=8)
        return
    # ripe: one big pumpkin with a smaller one beside it, a leaf curled over the big one's crown
    top = pumpkin_fruit(0.06, -0.08, 0.215, 0.32, m["pumpkin"], m, rng, stem=1.0, ribs=10, hook_yaw=200)
    CL.palm_leaf("crownleaf", top + Vector((0.02, 0.03, 0.02)), 0.1, m["pleaf"], yaw=40, pitch=-18, cup=0.1, droop=0.5)
    CL.tendril("tendril", top + Vector((-0.03, 0.02, 0.06)), (-0.6, 0.4, 0.8), m["tendril"], length=0.12, seed=31)
    pumpkin_fruit(-0.25, 0.25, 0.12, 0.17, m["pumpkin_s"], m, rng, stem=0.9, ribs=8, hook_yaw=330)


def build(crop, stage):
    name = "crop_%s_%d" % (crop, stage)
    K.reset(name)
    m = materials()
    (build_turnip if crop == "turnip" else build_pumpkin)(stage, m)
    out = os.path.join(HERE, "out", name)
    K.finish(name, out, max_tris=MAX_TRIS)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
if args[0] == "all":
    for c in ("turnip", "pumpkin"):
        for s in range(4):
            build(c, s)
else:
    stages = [int(a) for a in args[1:]] or range(4)
    for s in stages:
        build(args[0], s)
