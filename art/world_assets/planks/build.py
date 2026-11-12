"""The house's wall boards and floor planks: five boards of each, with their own grain, as two
atlases (colour and normal) the game lays walls and floors from (scripts/planks.gd), plus a mock-up
of a boarded wall on a planked floor, laid the way the game lays them, to check against the
references (ref/wall_planks.png, ref/floor_planks.png).

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/planks/build.py

Writes tex/<kind>_planks.png and _n.png, copies them to assets/textures/planks/, and saves
out/planks.blend. The grain itself is grain.py (numpy). Then import (see AGENTS.md).
"""
import os
import random
import shutil
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402
import grain  # noqa: E402

TEX = os.path.join(HERE, "tex")
GAME = os.path.join(ROOT, "assets", "textures", "planks")


def lay(name, mat, origin, across, along, n_boards, length, piece, rng, normal_up=True):
    """Boards side by side from `origin`: each `grain.BOARD_W` wide along `across` and `length` long
    along `along`, in pieces of `piece` metres (a floor's boards) or whole (piece >= length). Every
    piece takes one of the five grains at random, some of them turned end for end or mirrored."""
    verts, faces, uvs = [], [], []
    for b in range(n_boards):
        pos = -rng.uniform(0.0, piece) if piece < length else 0.0
        while pos < length:
            a0, a1 = max(pos, 0.0), min(pos + piece, length)
            var, flip_u, flip_v = rng.randrange(grain.VARIANTS), rng.random() < 0.5, rng.random() < 0.5
            quad = []
            for u, a in ((0, a0), (1, a0), (1, a1), (0, a1)):
                p = origin + across * ((b + u) * grain.BOARD_W) + along * a
                uu = (var + ((1 - u) if flip_u else u)) / grain.VARIANTS
                vv = (a - pos) / piece
                quad.append((p, (uu, vv if flip_v else 1.0 - vv)))
            if not normal_up:
                quad.reverse()
            faces.append(tuple(range(len(verts), len(verts) + 4)))
            verts.extend(q[0] for q in quad)
            uvs.extend(q[1] for q in quad)
            pos += piece
    return CL._finish_mesh(name, verts, faces, uvs, mat, recalc=False, smooth=False)


def main():
    from mathutils import Vector

    K.reset("planks")
    os.makedirs(GAME, exist_ok=True)
    mats = {}
    for kind in grain.KINDS:
        rgb, nrm = grain.atlas(kind)
        img = K.save_image(kind + "_planks", rgb, TEX)
        nm = K.save_image(kind + "_planks_n", nrm, TEX)
        mats[kind] = K.textured(kind + "_planks", img, rough=0.75, normal=nm, normal_strength=1.0)
        for f in (kind + "_planks.png", kind + "_planks_n.png"):
            shutil.copyfile(os.path.join(TEX, f), os.path.join(GAME, f))
    rng = random.Random(3)
    # a wall 4.2 m long and 2.6 m high on a floor 4.2 x 2.4 m, with the rails the house puts on it
    lay("wall", mats["wall"], Vector((-2.1, 0, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)), 14, grain.KINDS["wall"]["length"], 99.0, rng)
    lay("floor", mats["floor"], Vector((-2.1, 0, 0)), Vector((0, -1, 0)), Vector((1, 0, 0)), 8, 4.2, grain.KINDS["floor"]["length"], rng)
    trim = K.plain("trim", "#cfae84", 0.75)
    K.box("rail", (4.2, 0.05, 0.16), (0, -0.025, 2.52), trim, bevel=0.012)
    K.box("skirting", (4.2, 0.04, 0.14), (0, -0.02, 0.07), trim, bevel=0.012)
    bpy.context.view_layer.update()
    bpy.ops.file.pack_all()
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "out", "planks.blend"))


main()
