"""Park trash can, copied from Alex's reference render (ref/reference.png): a tapered barrel of fourteen
staves with two riveted iron bands and a dark iron liner, slung between two cast-iron posts on plinth
feet. The can only, no ground. It stands beside the park benches, so it is built at their size in the
game (0.74 m tall, the bench's back is 0.86 m) and painted with the bench's own wood and iron shaders
(art/world_assets/bench_park/build.py), baked to a colour and a normal map per material.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/trash_can/build.py

BIN_TEX (default 512) sets the texture size. The posts stand at +X and -X; 0.94 m wide over the feet,
0.60 m deep. Then copy out/trash_can.glb to assets/props/ and import (see AGENTS.md).
"""
import importlib.util
import math
import os
import random
import sys

from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

_spec = importlib.util.spec_from_file_location("bench_build", os.path.join(os.path.dirname(HERE), "bench_park", "build.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)

NAME = "trash_can"
RES = int(os.environ.get("BIN_TEX", 512))

# --- measures (metres, the size in the game) ----------------------------------------------------
STAVES = 14
Z0, Z1 = 0.12, 0.74          # the staves' bottom and top
R0, R1 = 0.232, 0.284        # the barrel's outer radius at the bottom and at the top
STAVE_T = 0.042
BANDS = ((0.190, 0.265), (0.550, 0.640))   # each iron band, from z to z


def radius(z):
    """The barrel's outer radius (to the middle of a stave's face) at height z."""
    return R0 + (R1 - R0) * (z - Z0) / (Z1 - Z0)


def stave(i, wood, rng):
    """One board of the barrel: wider at the top, leaning out with the taper, its outer face rounded."""
    phi = -math.pi / 2 + i * 2 * math.pi / STAVES
    alpha = math.atan2(R1 - R0, Z1 - Z0)
    width = lambda z: 2 * (radius(z) - STAVE_T * 0.3) * math.tan(math.pi / STAVES) - 0.003
    length = math.hypot(Z1 - Z0, R1 - R0) + rng.uniform(-0.007, 0.007)
    ob = B.plank("stave", length, width(Z0), STAVE_T, wood, rng, radii=(0.010, 0.005, 0.005, 0.010), stations=3,
                 taper=width(Z1) / width(Z0))
    rad = Vector((math.cos(phi), math.sin(phi), 0.0))
    along = (rad * math.sin(alpha) + Vector((0, 0, math.cos(alpha)))).normalized()   # the board's length
    out = (rad * math.cos(alpha) - Vector((0, 0, math.sin(alpha)))).normalized()     # its outer face
    side = out.cross(along)
    zm = (Z0 + Z1) / 2
    at = rad * (radius(zm) - STAVE_T / 2) + Vector((0, 0, zm))
    m = Matrix((along, side, out)).transposed().to_4x4()
    m.translation = at
    ob.matrix_world = m
    return ob


def band(z0, z1, metal):
    """An iron hoop that follows the taper, standing proud of the staves' corners, its edges eased."""
    corner = 1.0 / math.cos(math.pi / STAVES)
    ro = lambda z: radius(z) * corner + 0.012
    c = 0.006
    prof = [(radius(z0) - 0.004, z0), (ro(z0) - c, z0), (ro(z0 + c), z0 + c), (ro(z1 - c), z1 - c), (ro(z1) - c, z1),
            (radius(z1) - 0.004, z1)]
    return K.lathe("band", prof, metal, steps=28, sharp=35), ro((z0 + z1) / 2)


def build_geometry(wood, metal):
    rng = random.Random(5)
    parts_wood, parts_metal, steel = [], [], []
    for i in range(STAVES):
        parts_wood.append(stave(i, wood, rng))

    # bands, a dome rivet on every other stave (the two bands a stave apart), none behind the posts
    for k, (z0, z1) in enumerate(BANDS):
        b, r = band(z0, z1, metal)
        parts_metal.append(b)
        for i in range(k == 0, STAVES, 2):
            phi = -math.pi / 2 + i * 2 * math.pi / STAVES
            if k == 1 and abs(math.cos(phi)) > 0.94:
                continue
            rv = B.bolt("rivet", 0.021, 0.012, (r * math.cos(phi), r * math.sin(phi), (z0 + z1) / 2), metal,
                        rot=(0, 90, math.degrees(phi)), steps=9)
            parts_metal.append(rv)
            steel.append(rv)

    # the liner: a dark iron bucket whose rim sits a little under the staves' tops
    rim = Z1 - 0.038
    ri = radius(rim) - STAVE_T
    liner = [(ri + 0.010, rim - 0.02), (ri + 0.010, rim - 0.006), (ri + 0.004, rim), (ri - 0.018, rim),
             (ri - 0.024, rim - 0.006), (ri - 0.040, 0.30), (0.0, 0.30)]
    parts_metal.append(K.lathe("liner", liner, metal, steps=28, sharp=35))
    parts_metal.append(K.cyl("bottom", R0 - 0.022, R0 - 0.018, 0.03, (0, 0, Z0 + 0.035), metal, verts=STAVES))

    # two posts: big plinth feet and a flat bar, its broad face to the front, that narrows at the waist
    # and widens again to hug the upper band; a rivet through the top, front and back
    for side in (-1, 1):
        path = B.catmull([(0.372, 0.06, 0.130, 0.086), (0.366, 0.15, 0.100, 0.078), (0.358, 0.30, 0.078, 0.074),
                          (0.350, 0.45, 0.074, 0.074), (0.343, 0.575, 0.090, 0.076), (0.338, 0.675, 0.110, 0.078)], 3)
        path.append((0.336, 0.702, 0.080, 0.056))   # the top eased over
        post = B.sweep("post", path, 0.0, metal)
        post.rotation_euler = (0, 0, -math.pi / 2 * side)      # the path was drawn in YZ: turn it to +X or -X
        parts_metal.append(post)
        parts_metal.append(B.foot(side * 0.372, 0.0, metal, hx=0.098, hy=0.076, h=0.068, top=0.112, inset=(0.028, 0.024)))
        for face in (-1, 1):
            rv = B.bolt("rivet", 0.024, 0.012, (side * 0.338, face * 0.037, 0.612), metal, rot=(-90 * face, 0, 0), steps=9)
            parts_metal.append(rv)
            steel.append(rv)
    return parts_wood, parts_metal, steel


def main():
    K.reset(NAME)
    mats = B.bake_materials()
    pw, pm, steel = build_geometry(mats[0], mats[1])
    B.paint_and_export(NAME, pw, pm, steel, mats, os.path.join(HERE, "out"), os.path.join(HERE, "tex"), RES, RES,
                       grain="z", staves=STAVES, prefix="bin", centre_depth=False)


if __name__ == "__main__":
    main()
