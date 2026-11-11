"""Three fallen maple leaves after Alex's reference renders: a chunky, domed, clay-soft leaf with raised
veins, serrated lobes and a short curved stalk. leaf_red, leaf_yellow, leaf_green; each ~0.30 m across.
Colour and vein relief are baked into a 512 px albedo + normal map; the stalk is plain colour.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/leaves/build.py -- leaf_red
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import natlib as N  # noqa: E402

TEX = os.path.join(HERE, "tex")
SIZE = 0.30


SHAPES = ("leaf_red", "leaf_yellow", "leaf_green")


def build(name):
    shape = N.Shape(name, 0.30)
    K.reset(name)
    alb, nrm = N.leaf_maps(name, TEX, shape, seed=SHAPES.index(name) * 3, gamma=1.1, gain=0.74, sat=1.3)
    mat = K.textured(name + "_mat", alb, rough=0.5, normal=nrm, normal_strength=1.0)
    mat.node_tree.nodes['Principled BSDF'].inputs['Specular IOR Level'].default_value = 0.18
    N.leaf_mesh(name, shape, mat, n=144, rings=13)
    # curved stalk, thickening towards its end like the reference
    sc = shape.colors["stem"]
    sc = tuple(min(1.0, max(0.0, 0.5 + (c - 0.5) * 1.0)) * 0.78 for c in sc)  # deeper brown so it keeps its colour in the harness light
    sm = K.plain(name + "_stalk", "#%02x%02x%02x" % tuple(round(c * 255) for c in sc), 0.5)
    pts = [(0.0, 0.02, 0.014), (0.0, 0.0, 0.014), (-0.004, -0.02, 0.014), (-0.012, -0.04, 0.016), (-0.026, -0.058, 0.015), (-0.042, -0.072, 0.0145)]
    N.tube("stalk", pts, [0.0055, 0.0058, 0.0066, 0.0078, 0.0092, 0.0105], sm, sides=14)
    K.finish(name, os.path.join(HERE, "out"), max_tris=5500)


which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(SHAPES)
for n_ in which:
    build(n_)
