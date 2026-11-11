"""Three mossy rocks after Alex's references: rock_boulder (a big faceted boulder, moss on its crown and
ledges, grass and pebbles round its foot), rock_cluster (three rocks leaning together) and rock_single
(one medium rock). Faceted hull shapes bevelled into soft ridges; painted stone + moss textures, grass
tufts and pebbles.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/rocks/build.py -- rock_boulder
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import natlib as N  # noqa: E402

TEX = os.path.join(HERE, "tex")


def setup(name, seed):
    K.reset(name)
    a, n = N.rock_maps(name + "_stone", TEX, K.hex_rgb("#70665d"), seed=seed)
    stone = K.textured(name + "_stone_mat", a, rough=0.82, normal=n, normal_strength=0.9)
    stone.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.3
    ma, mn = N.moss_maps(name + "_moss", TEX, seed=seed)
    moss = K.textured(name + "_moss_mat", ma, rough=0.95, normal=mn, normal_strength=1.0)
    blade = K.plain(name + "_grass", "#3d8a22", 0.6)
    blade2 = K.plain(name + "_grass2", "#5aa32a", 0.6)
    pebble = K.plain(name + "_pebble", "#6a5d52", 0.8)
    return stone, moss, blade, blade2, pebble


def decorate(rock, pebble, moss, blades, rng, tufts, pebbles, moss_n=6, scale=1.0, moss_thick=0.02):
    N.moss_patches("moss", rock, moss, rng, moss_n, 0.07 * scale, 0.2 * scale, thickness=moss_thick * scale, near=(0, 0, 0.35 * scale))
    for (x, y, z, a) in N.foot_points(rock, tufts, rng, outward=(-0.04 * scale, 0.1 * scale)):
        N.tuft("tuft", (x, y, z), blades[rng.integers(0, 2)], rng, blades=int(rng.integers(5, 9)), height=0.2 * scale * rng.uniform(0.7, 1.3), spread=0.07 * scale)
    for (x, y, z, a) in N.foot_points(rock, pebbles, rng, outward=(0.08 * scale, 0.3 * scale)):
        r = 0.05 * scale * rng.uniform(0.8, 1.6)
        N.rock_shell("pebble", rng, (r, r * 0.9, r * 0.65), pebble, n_pts=10, bevel=r * 0.1, segs=2, loc=(x, y, 0), yaw=a, tile=0.4, dissolve=10.0, rough=0.0)


def boulder():
    name = "rock_boulder"
    rng = np.random.default_rng(14)
    stone, moss, g1, g2, peb = setup(name, 4)
    r = N.rock_shell("boulder", rng, (1.15, 1.0, 0.78), stone, n_pts=17, lean=0.2, bevel=0.11, segs=3, flat=0.5, dissolve=24.0, jit=(0.7, 1.12))
    decorate(r, peb, moss, (g1, g2), rng, tufts=28, pebbles=9, moss_n=7, scale=1.7, moss_thick=0.02)
    K.finish(name, os.path.join(HERE, "out"), max_tris=9000)


def cluster():
    name = "rock_cluster"
    rng = np.random.default_rng(25)
    stone, moss, g1, g2, peb = setup(name, 11)
    parts = []
    for nm, rad, lean, loc, yaw, cov in (("big", (0.6, 0.52, 0.5), 0.2, (0.34, 0.14, 0), 0.4, 0.5), ("medium", (0.5, 0.45, 0.34), -0.1, (-0.4, -0.06, 0), 1.2, 0.55), ("small", (0.34, 0.3, 0.2), 0.0, (0.03, -0.4, 0), 2.1, 0.45)):
        r = N.rock_shell(nm, rng, rad, stone, n_pts=16, lean=lean, bevel=0.045, segs=3, flat=0.5, loc=loc, yaw=yaw, dissolve=24.0, jit=(0.72, 1.12))
        parts.append((r, cov))
    for i, (r, cov) in enumerate(parts):
        decorate(r, peb, moss, (g1, g2), rng, tufts=12, pebbles=4, moss_n=int(4 + 4 * cov), scale=0.9, moss_thick=0.016)
    K.finish(name, os.path.join(HERE, "out"), max_tris=12000)


def single():
    name = "rock_single"
    rng = np.random.default_rng(37)
    stone, moss, g1, g2, peb = setup(name, 6)
    r = N.rock_shell("single", rng, (0.5, 0.44, 0.27), stone, n_pts=16, lean=0.08, bevel=0.05, segs=3, flat=0.5, dissolve=24.0, jit=(0.74, 1.12))
    decorate(r, peb, moss, (g1, g2), rng, tufts=10, pebbles=4, moss_n=3, scale=0.5, moss_thick=0.012)
    K.finish(name, os.path.join(HERE, "out"), max_tris=7000)


which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["rock_boulder", "rock_cluster", "rock_single"]
for w in which:
    {"rock_boulder": boulder, "rock_cluster": cluster, "rock_single": single}[w]()
