"""The hanging shop signs over Maplewood's storefronts, built from Alex's five references
(ref/sign_*.png, 2026-11-12): a carved board of reddish planks with a raised cream border, a hump
in the middle of the top edge and rounded notches at its four corners, hung by two iron straps and
wooden rings from a round log; the shop's name in big soft cream letters, an emblem over it
between two sprigs, and on three of them a flourish underneath.

    uv run --no-project --with numpy --with pillow python art/world_assets/shop_signs/make_faces.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/shop_signs/build.py -- <sign>|all

<sign> is one of willow_homes, builders_delight, yarn_barn, heart_bakery, mayors_office. Each
becomes assets/props/sign_<sign>.glb. Front faces -Y (+Z in Godot); the origin is on the wall the
sign hangs against (y = 0), centred on the board (x = 0, z = 0), so town.gd puts it at the old
sign board's centre. Measured off the references at PX metres a pixel (the board is 1,690 px wide
in every one of them).

The board's face is the reference itself, the way the Maple Grove welcome sign does it (Alex,
2026-11-12: get the lettering exactly like the reference): make_faces.py cuts each board out of its
reference into tex/<sign>_face.png with a normal map that raises the cream work, and traces the
board's outline (tex/<sign>_board.json). This script extrudes the board from that outline, lays
the face on its front, and models the rest: the plank sides and back, the log, straps and rings.
"""
import json
import os
import shutil
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
SIGNS = ["willow_homes", "builders_delight", "yarn_barn", "heart_bakery", "mayors_office"]

WIDTH = 2.0  # the board, end to end
PX = WIDTH / 1690.0  # metres per reference pixel
CXP, CZP = 995.0, 340.0  # the board's centre in reference pixels
BOARD_T = 0.055  # board thickness
ROD_R = 46 * PX  # its underside on the reference's, 91 px
WALL_GAP = 0.05  # from the wall to the back of the rod
ROD_Y = WALL_GAP + ROD_R  # the rod's axis, in front of the wall (as -y)
BOARD_BACK = -(ROD_Y + 0.01)  # the board hangs just in front of the rod's axis...
YF = BOARD_BACK - BOARD_T  # ...and this is its front face


def P(px, py):
    """A reference pixel as (x, z) on the board."""
    return ((px - CXP) * PX, (CZP - py) * PX)


def ccw(pts):
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    return pts if area > 0 else pts[::-1]


# --- materials -----------------------------------------------------------------------------------

def materials(key):
    M = {}
    i, n = CL.plank_maps("shopsign_board", TEX, base="#8c3a14", light="#a84e20", dark="#5e240c", knots=2, seams=2, seed=61)
    M["board"] = K.textured("shopsign_board", i, rough=0.72, normal=n, normal_strength=0.8)
    i, n = CL.plank_maps("shopsign_rod", TEX, base="#b0592e", light="#c8723f", dark="#7e3a1a", knots=1, seed=67)
    M["rod"] = K.textured("shopsign_rod", i, rough=0.7, normal=n, normal_strength=0.7)
    face = bpy.data.images.load(os.path.join(TEX, "%s_face.png" % key))
    face_n = bpy.data.images.load(os.path.join(TEX, "%s_face_n.png" % key))
    M["face"] = K.textured("shopsign_face_" + key, face, rough=0.68, normal=face_n, normal_strength=1.0)
    M["ring"] = K.plain("shopsign_ring", "#a5532c", rough=0.65)
    M["iron"] = K.plain("shopsign_iron", "#77706c", rough=0.5)
    bolt = K.plain("shopsign_bolt", "#a19d9a", rough=0.3)
    bolt.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.85
    M["bolt"] = bolt
    return M


# --- the board and its hanger --------------------------------------------------------------------

def build_board(M, key):
    """The board, extruded from the outline traced off the reference, with the reference's face
    on its front."""
    with open(os.path.join(TEX, "%s_board.json" % key)) as f:
        prof = json.load(f)
    xs, top, bot = prof["x"], prof["top"], prof["bot"]
    out = [P(x, t) for x, t in zip(xs, top)] + [P(x, b) for x, b in zip(xs[::-1], bot[::-1])]
    board = K.extrude_xz("board", ccw(out), YF, BOARD_BACK, M["board"], bevel=0.01)
    K.uv_box(board, 0.9, grain="x")  # the sides and back: planks running along the board
    fx0, fx1, fy0, fy1 = prof["crop"]
    me = board.data
    me.materials.append(M["face"])
    fi = len(me.materials) - 1
    uvl = me.uv_layers.active.data
    for poly in me.polygons:
        if poly.normal.y < -0.95:
            poly.material_index = fi
            for li in poly.loop_indices:
                co = board.matrix_world @ me.vertices[me.loops[li].vertex_index].co
                px, py = co.x / PX + CXP, CZP - co.z / PX
                uvl[li].uv = ((px - fx0) / (fx1 - fx0), 1 - (py - fy0) / (fy1 - fy0))


def build_hanger(M):
    """The round log the board hangs from, with two iron straps round it, each holding a wooden
    ring that's fixed into the board's top edge, and the two brackets that hold the log off the
    wall."""
    z_rod = P(0, 52)[1]  # its underside tucked behind the board's top edge
    x0, x1 = P(255, 0)[0], P(1745, 0)[0]
    rod = CL.beam("rod", [(x, -ROD_Y, z_rod) for x in np.linspace(x0, x1, 10)], 2 * ROD_R, 2 * ROD_R, M["rod"],
                  sides=18, v_scale=1.3, wave=0.004, seed=5, square=0.9)
    for xp in (455, 1535):
        x = P(xp, 0)[0]
        # the iron strap wrapped round the log, its bolt, and the loop hanging down to the ring
        K.cyl("strap", ROD_R + 0.007, ROD_R + 0.007, 0.045, (x, -ROD_Y, z_rod), M["iron"], verts=18, rot=(0, 90, 0), bevel=0.004)
        K.ball("strap_bolt", 0.017, (x, -ROD_Y - ROD_R - 0.006, z_rod + 0.006), M["bolt"], scale=(1, 0.6, 1))
        zr = P(0, 150)[1]
        K.box("strap_drop", (0.04, 0.016, z_rod - ROD_R - zr + 0.01), (x, -ROD_Y - 0.005, (z_rod - ROD_R + zr) / 2 + 0.01), M["iron"], bevel=0.006, seg=2)
        K.torus("ring", 0.034, 0.011, (x, BOARD_BACK - BOARD_T / 2, zr), M["ring"], rot=(90, 0, 0), major=18, minor=8)
        # the bracket back to the wall
        K.box("bracket", (0.035, ROD_Y, 0.035), (x, -ROD_Y / 2, z_rod), M["iron"], bevel=0.008, seg=2)
        K.box("plate", (0.08, 0.012, 0.16), (x, -0.006, z_rod), M["iron"], bevel=0.004, seg=1)


# --- build -------------------------------------------------------------------------------------

def build(key):
    name = "sign_" + key
    K.reset(name)
    M = materials(key)
    build_board(M, key)
    build_hanger(M)
    out = os.path.join(HERE, "out", key)
    K.finish(name, out, max_tris=60000)
    os.makedirs(PROPS, exist_ok=True)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", os.path.join(PROPS, name + ".glb"))


arg = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "all"
for k in (SIGNS if arg == "all" else [arg]):
    build(k)
