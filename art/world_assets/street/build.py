"""Street furniture for the map, all textured: a painted picket fence segment (1 m) and a cast-iron lamp
post. Painted-wood and iron textures are generated here (numpy) with matching normal maps. Footprints and
facing match the game's old box versions: the fence's flat side faces -Z in Godot (+Y here); the lamp's arm
reaches +X. The park bench has its own folder now: art/world_assets/bench_park.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/street/build.py [-- name ...]
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import natlib as N  # noqa: E402

TEX = os.path.join(HERE, "tex")


def wood_mats(prefix, seed, planks=4, tint=(1.0, 1.0, 1.0)):
    alb = K.wood_image(prefix + "_wood", TEX, seed=seed, planks=planks)
    h = K.grain_noise(512, 30.0, 1.25, seed) * 0.7 + K.grain_noise(512, 90.0, 0.7, seed + 3) * 0.3
    nrm = K.save_image(prefix + "_wood_n", K.normal_from_height(h, 3.0), TEX)
    m = K.textured(prefix + "_wood_mat", alb, rough=0.78, normal=nrm, normal_strength=1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.2
    return m


def painted(prefix, base_hex, seed):
    """Brush-painted white wood: grain shows faintly through, with chipped paint showing bare wood at the edges."""
    n = 512
    g = K.grain_noise(n, 28.0, 1.2, seed)
    fine = K.grain_noise(n, 90.0, 0.7, seed + 2)
    chips = K.tile_noise(n, 0.9, seed + 5)
    base = np.array(K.hex_rgb(base_hex))
    wood = np.array(K.pal_srgb("wood_light"))
    col = base * (0.93 + 0.1 * g[..., None]) * (0.97 + 0.05 * fine[..., None])
    chip = np.clip((chips - 0.74) / 0.06, 0, 1)[..., None] * np.clip(fine[..., None] * 1.4, 0, 1)
    col = col * (1 - chip) + wood * 0.85 * chip
    alb = K.save_image(prefix + "_paint", np.clip(col, 0, 1), TEX)
    h = g * 0.6 + fine * 0.4 - chip[..., 0] * 0.3
    nrm = K.save_image(prefix + "_paint_n", K.normal_from_height(h, 3.0), TEX)
    m = K.textured(prefix + "_paint_mat", alb, rough=0.6, normal=nrm, normal_strength=1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.3
    return m


def iron(prefix, seed):
    n = 512
    a = K.tile_noise(n, 1.2, seed)
    b = K.tile_noise(n, 0.5, seed + 1)
    base = np.array(K.hex_rgb("#2d2b2a"))
    col = base * (0.85 + 0.35 * a[..., None]) * (0.92 + 0.16 * b[..., None])
    rust = np.clip((K.tile_noise(n, 1.0, seed + 4) - 0.78) / 0.08, 0, 1)[..., None]
    col = col * (1 - 0.5 * rust) + np.array([0.42, 0.22, 0.12]) * 0.5 * rust
    alb = K.save_image(prefix + "_iron", np.clip(col, 0, 1), TEX)
    nrm = K.save_image(prefix + "_iron_n", K.normal_from_height(b * 0.6 + a * 0.4, 2.5), TEX)
    m = K.textured(prefix + "_iron_mat", alb, rough=0.55, normal=nrm, normal_strength=0.8)
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.4
    return m


def uv_box_all():
    """Box-project UVs onto every object so planks and posts carry the texture at 1 tile per 0.6 m."""
    import bmesh
    for ob in list(K.COLL.objects):
        if ob.type != "MESH":
            continue
        K.apply_mods(ob)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        uv = bm.loops.layers.uv.verify()
        bm.normal_update()
        tile = 0.6
        for f in bm.faces:
            nx, ny, nz = abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)
            for l in f.loops:
                p = ob.matrix_world @ l.vert.co
                # wood grain runs along Z on uprights, along X on boards
                if nz >= nx and nz >= ny:
                    l[uv].uv = (p.x / tile, p.y / tile)
                elif nx >= ny:
                    l[uv].uv = (p.y / tile, p.z / tile)
                else:
                    l[uv].uv = (p.x / tile, p.z / tile)
        bm.to_mesh(ob.data)
        bm.free()


def build_fence():
    name = "fence_picket"
    K.reset(name)
    paint = painted("fence", "#ece6d6", 3)
    # posts with pyramid caps at the segment ends
    for x in (-0.46, 0.46):
        K.box("post", (0.09, 0.09, 0.95), (x, 0, 0.475), paint, bevel=0.012, seg=2)
        K.cyl("cap", 0.07, 0.0, 0.06, (x, 0, 0.98), paint, verts=4, rot=(0, 0, 45))
    # two rails behind the pickets
    for z in (0.3, 0.62):
        K.box("rail", (0.92, 0.04, 0.07), (0, 0.04, z), paint, bevel=0.01, seg=1)
    # pointed pickets, 5 per metre
    for i in range(5):
        x = -0.36 + i * 0.18
        top = 0.88 + 0.02 * ((i * 7) % 3)
        pts = [(x - 0.045, 0.0), (x + 0.045, 0.0), (x + 0.045, top - 0.06), (x, top), (x - 0.045, top - 0.06)]
        K.extrude_xz("picket", pts, -0.045, -0.015, paint, bevel=0.006)
    uv_box_all()
    K.finish(name, os.path.join(HERE, "out"), max_tris=1600)


def build_lamp():
    name = "lamp_post"
    K.reset(name)
    ir = iron("lamp", 9)
    glass = K.plain("lamp_glass", "#ffd48a", 0.35, emit=2.5)
    # fluted base, pole, collars
    base = [(0.13, 0.0), (0.13, 0.05), (0.09, 0.16), (0.07, 0.3), (0.075, 0.34), (0.05, 0.38), (0.042, 0.5)]
    K.lathe("base", base, ir, steps=12)
    K.cyl("pole", 0.038, 0.044, 1.1, (0, 0, 1.05), ir, verts=12)
    for z, r in ((0.7, 0.062), (1.2, 0.055), (1.58, 0.06)):
        K.cyl("collar", r, r, 0.035, (0, 0, z), ir, verts=12)
    K.ball("finial", 0.055, (0, 0, 1.64), ir, u=10, v=7)
    # curved arm to the lantern: a scroll that sweeps out and drops
    pts = [(0, 0, 1.52), (0.06, 0, 1.6), (0.15, 0, 1.62), (0.23, 0, 1.58), (0.25, 0, 1.52)]
    N.tube("arm", pts, [0.022, 0.02, 0.018, 0.016, 0.014], ir, sides=8)
    # the lantern: cap, glass, cup, hanging at x = 0.25
    # a closed, flared roof (lathe from the eaves up to a point) with a little finial on top
    roof = [(0.155, 0.0), (0.155, 0.015), (0.12, 0.045), (0.075, 0.095), (0.04, 0.135), (0.02, 0.15), (0.0, 0.16)]
    K.lathe("roof", roof, ir, steps=8, loc=(0.25, 0, 1.47))
    K.ball("roof_knob", 0.022, (0.25, 0, 1.64), ir, u=8, v=6)
    K.box("glass", (0.16, 0.16, 0.2), (0.25, 0, 1.38), glass, bevel=0.01, seg=1)
    for sx in (-1, 1):
        for sy in (-1, 1):
            K.box("frame", (0.016, 0.016, 0.22), (0.25 + sx * 0.08, sy * 0.08, 1.38), ir, bevel=0.004, seg=1)
    K.cyl("cup", 0.02, 0.1, 0.05, (0.25, 0, 1.26), ir, verts=8)
    K.finish(name, os.path.join(HERE, "out"), max_tris=2600)


ALL = ["fence", "lamp"]
which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ALL
for w in which:
    {"fence": build_fence, "lamp": build_lamp}[w]()
