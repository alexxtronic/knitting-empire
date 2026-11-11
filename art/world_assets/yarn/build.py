"""Yarn and needles, after Alex's reference art: chunky plied yarn wound into soft balls in sage,
mustard, dusty rose, cream and cornflower blue, each with a loose tail; and glossy turned-wood
knitting needles with a ringed collar and a mushroom knob.

    yarn_balls        five balls in a heap (rose, cream and blue in front, sage and mustard behind)
    knitting_needles  a pair of needles lying crossed
    yarn_basket       a round wicker basket of yarn with the needles pushed through a ball

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/yarn/build.py -- all
"""
import math
import os
import shutil
import sys

import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
FLOOR = 0.02  # the house floorboards stand 2 cm proud of the ground (main.gd), so floor props sit on them
COLOURS = {"sage": "#86a865", "mustard": "#e3a92a", "rose": "#cf6a6a", "cream": "#f1e3c2", "blue": "#6e97c8"}


def yarn_mat(c):
    i, n = CL.yarn_maps("yarn_" + c, TEX, COLOURS[c])
    return K.textured("yarn_" + c, i, rough=0.95, normal=n, normal_strength=0.9)


def wood_mat():
    i, n = CL.wood_maps("needle_wood", TEX)
    return K.textured("needle_wood", i, rough=0.32, normal=n, normal_strength=0.3)


def yarn_ball(centre, R, mat, seed, tail=None, sides=6, segs=26):
    """A ball of chunky yarn: a soft core under bands of two or three strands wound round it at
    different angles, outer bands riding over the inner ones. tail: (direction, length) on the floor."""
    rng = np.random.default_rng(seed)
    c = Vector(centre)
    rs = R * 0.14
    K.ball("core", R * 0.86, tuple(c), mat, u=12, v=8)
    groups = 5
    for g in range(groups):
        ax = Vector(rng.standard_normal(3)).normalized()
        e1 = ax.orthogonal().normalized()
        e2 = ax.cross(e1).normalized()
        layer = R * (0.84 + 0.035 * g)
        n_str = 2 + (g % 2)
        for k in range(n_str):
            # neighbouring strands in a band: the same circle tipped a little about e1
            tip = math.radians((k - (n_str - 1) / 2) * 15.0)
            rot = Matrix.Rotation(tip, 3, e1)
            a1, a2 = rot @ e1, rot @ e2
            pts = []
            for i in range(segs + 1):
                t = 2 * math.pi * i / segs
                pts.append(c + (a1 * math.cos(t) + a2 * math.sin(t)) * (layer + rs * 0.4))
            CL.tube("strand", pts, [rs] * len(pts), mat, sides=sides, v_scale=1 / (rs * 9), caps=False)
    if tail:
        d, length = Vector(tail[0]).normalized(), tail[1]
        side = Vector((-d.y, d.x, 0))
        start = c + d * R * 0.8 + Vector((0, 0, -R * 0.45))
        floor = c.z - R + rs
        p1 = c + d * (R * 1.05) + Vector((0, 0, -R * 0.85))
        p2 = Vector((start.x, start.y, floor)) + d * length * 0.5 + side * length * 0.3
        p3 = Vector((start.x, start.y, floor)) + d * length * 0.85 - side * length * 0.15
        pts = CL.bezier(start, p1, p2, p3, n=14)
        pts = [Vector((p.x, p.y, max(p.z, floor))) for p in pts]
        # the cut end curls up a little
        end = pts[-1]
        pts += [end + d * rs * 1.4 + Vector((0, 0, rs * 0.8)), end + d * rs * 2.0 + Vector((0, 0, rs * 2.0))]
        radii = [rs] * (len(pts) - 1) + [rs * 0.8]
        CL.tube("tail", pts, radii, mat, sides=sides, v_scale=1 / (rs * 9))
        K.ball("tailend", rs * 0.85, tuple(pts[-1]), mat, u=8, v=5)


def needle(base, tip_dir, mat, L=0.4):
    """A turned needle: point, long shaft, ringed collar and a mushroom knob. base = the point."""
    r = 0.011
    prof = [(0.0, 0.0), (0.0035, 0.008), (0.0075, 0.03), (r * 0.95, 0.075), (r, 0.2), (r * 1.08, L - 0.06),
            (r * 1.5, L - 0.057), (r * 1.62, L - 0.05), (r * 1.62, L - 0.04), (r * 1.4, L - 0.034),
            (r * 1.25, L - 0.032), (r * 2.0, L - 0.028), (r * 2.4, L - 0.018), (r * 2.4, L - 0.008),
            (r * 1.9, L + 0.001), (r * 1.0, L + 0.006), (0.0, L + 0.007)]
    ob = K.lathe("needle", prof, mat, steps=14, sharp=50, v_rep=3.0)
    z = Vector((0, 0, 1))
    d = Vector(tip_dir).normalized()
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = z.rotation_difference(d)
    ob.location = base
    return ob


def build_balls():
    R = 0.085
    m = {c: yarn_mat(c) for c in COLOURS}
    z = R * 0.98 + FLOOR
    yarn_ball((-0.085, 0.07, z + 0.02), R, m["sage"], 1)
    yarn_ball((0.09, 0.075, z + 0.02), R, m["mustard"], 2)
    yarn_ball((-0.16, -0.06, z), R, m["rose"], 3, tail=((-0.6, -1, 0), 0.16))
    yarn_ball((0.0, -0.1, z), R, m["cream"], 4, tail=((0.3, -1, 0), 0.17))
    yarn_ball((0.165, -0.05, z), R, m["blue"], 5, tail=((1, -0.5, 0), 0.13))


def build_needles():
    w = wood_mat()
    # two needles lying crossed: one flat on the floor, the other resting across it
    needle(Vector((-0.17, -0.12, 0.012 + FLOOR)), (1, 0.62, 0.0), w)
    needle(Vector((0.17, -0.12, 0.012 + FLOOR)), (-1, 0.62, 0.045), w)


def build_basket():
    i, n = CL.wicker_maps("wicker", TEX)
    wick = K.textured("wicker", i, rough=0.8, normal=n, normal_strength=0.8)
    prof = [(0.0, 0.0), (0.17, 0.0), (0.185, 0.012), (0.2, 0.08), (0.225, 0.2), (0.23, 0.22),
            (0.215, 0.22), (0.205, 0.19), (0.18, 0.07), (0.16, 0.04), (0.0, 0.04)]
    K.lathe("basket", prof, wick, steps=32, u_rep=12.0, v_rep=4.0, sharp=60)
    rim = K.torus("rim", 0.224, 0.016, (0, 0, 0.222), wick, major=32, minor=6)
    K.uv_box(rim, 6.0)
    m = {c: yarn_mat(c) for c in COLOURS}
    R = 0.08
    yarn_ball((-0.075, 0.06, 0.19), R, m["sage"], 11)
    yarn_ball((0.085, 0.055, 0.2), R, m["mustard"], 12)
    yarn_ball((-0.05, -0.08, 0.2), R, m["rose"], 13, tail=None)
    yarn_ball((0.07, -0.075, 0.24), R, m["cream"], 14)
    yarn_ball((0.0, 0.0, 0.29), R * 0.95, m["blue"], 15)
    w = wood_mat()
    # the needles pushed through the top ball, knobs up and out
    needle(Vector((-0.03, 0.05, 0.22)), (0.75, -0.55, 0.6), w, L=0.34)
    needle(Vector((0.04, 0.06, 0.22)), (0.35, -0.85, 0.55), w, L=0.34)


KINDS = {"yarn_balls": (build_balls, 24000), "knitting_needles": (build_needles, 2000), "yarn_basket": (build_basket, 26000)}


def build(name):
    K.reset(name)
    fn, budget = KINDS[name]
    fn()
    out = os.path.join(HERE, "out", name)
    K.finish(name, out, max_tris=budget)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for a in (KINDS if args[0] == "all" else args):
    build(a)
