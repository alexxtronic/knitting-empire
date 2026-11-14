"""The furniture of Nora's house, rebuilt from reference images in the style of Alex's prop references
(chunky, hand-painted, warm orange wood): rocking chair, fireplace, kitchen counter, sofa, armchair,
spinning wheel, dining table, bookshelf, wardrobe, floor lamp, potted fern and knitted rug. Each stands in for a
box model in scripts/catalog.gd, on the same footprint (data/furniture.json), facing the same way.

The references (ref/<id>.png) were made in ChatGPT, one per piece, on white. Wood, cloth and
straw-like textures are the small painterly maps of craftlib; iron, brass, glass and flames are flat colours.
The tartan's wool (fibre speckle and woven relief) comes from two Poly Haven fabric scans (CC0, in
../textures_web), and the sofa's throw is draped over it with Blender's cloth simulation.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/house_furniture/build.py [-- id ...]

Writes <id>/out/<id>.glb. Front faces -Y here (+Z in Godot); metres; sized to Nora (seats 0.42 m up).
Then copy the GLBs to assets/props/ and import (see AGENTS.md).
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import craftlib as CL  # noqa: E402
import kelib as K  # noqa: E402
sys.path.insert(0, HERE)
import knit  # noqa: E402

ITEM = ""
TEX = ""
M = {}
SEAT = 0.42   # the top of every seat cushion
WEB = os.path.join(os.path.dirname(HERE), "textures_web")
WOOL_SPECKLE = 3.0   # how strongly the wool scan's fibres show in the tartan's colour
WOOL_RELIEF = 1.2    # the strength of the tartan's woven normal map


# --- materials ---------------------------------------------------------------------------------------

def wood(key="wood", base="#d07a32", light="#eb9a4f", dark="#a2551e", seams=0, knots=1, seed=1, rough=0.7):
    if key not in M:
        i, n = CL.plank_maps(ITEM + "_" + key, TEX, base=base, light=light, dark=dark, seams=seams, knots=knots, seed=seed)
        M[key] = K.textured(ITEM + "_" + key, i, rough=rough, normal=n, normal_strength=0.9)
    return M[key]


def web_map(rel, n=512, data=False):
    """A downloaded fabric scan (../textures_web, Poly Haven, CC0) as a float array (n, n, 3),
    row 0 at the top, squeezed to a square that still tiles."""
    img = bpy.data.images.load(os.path.join(WEB, rel))
    if data:
        img.colorspace_settings.name = "Non-Color"
    img.scale(n, n)
    px = np.empty(n * n * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(n, n, 4)[::-1, :, :3].copy()


def plaid():
    """Red tartan as in the references: broad darker bands both ways, thin cream lines between them
    and a fine gold line down the middle of each band. Woven wool: the fibre speckle is a herringbone
    wool scan's and the relief a boucle wool's."""
    if "plaid" not in M:
        n = 512
        yy, xx = np.mgrid[0:n, 0:n]
        u, v = xx / n, yy / n

        def lines(t, centres, width):
            return sum(np.exp(-((((t - c) + 0.5) % 1.0 - 0.5) / width) ** 2) for c in centres)

        band = np.clip((lines(u, (0.25, 0.75), 0.075) + lines(v, (0.25, 0.75), 0.075)) * 0.6, 0, 1)
        cream = np.clip(lines(u, (0.0, 0.5), 0.014) + lines(v, (0.0, 0.5), 0.014), 0, 1)
        gold = np.clip(lines(u, (0.25, 0.75), 0.009) + lines(v, (0.25, 0.75), 0.009), 0, 1)
        fibre = web_map("poly_wool_herringbone/poly_wool_herringbone_diff_1k.jpg", n).mean(axis=2)
        fibre = np.clip(1.0 + (fibre / fibre.mean() - 1.0) * WOOL_SPECKLE, 0.72, 1.25)
        soft = K.tile_noise(n, 1.3, 5)
        rgb = CL.mix(CL.C("#cc4433"), CL.C("#8f2319"), band[..., None])
        rgb = CL.mix(rgb, CL.C("#f3dfae"), cream[..., None] * 0.9)
        rgb = CL.mix(rgb, CL.C("#e9a93c"), gold[..., None] * 0.6)
        rgb = rgb * fibre[..., None] * (0.95 + 0.1 * soft[..., None])
        i = K.save_image(ITEM + "_plaid", rgb, TEX)
        nm = K.save_image(ITEM + "_plaid_n", web_map("wool_boucle/wool_boucle_nor_gl_1k.jpg", n, data=True), TEX)
        M["plaid"] = K.textured(ITEM + "_plaid", i, rough=1.0, normal=nm, normal_strength=WOOL_RELIEF)
    return M["plaid"]


def cloth(key, hexcol):
    if key not in M:
        i, n = CL.cloth_maps(ITEM + "_" + key, TEX, hexcol)
        M[key] = K.textured(ITEM + "_" + key, i, rough=0.95, normal=n, normal_strength=0.8)
    return M[key]


def flat(key, hexcol, rough=0.8, emit=0.0):
    if key not in M:
        M[key] = K.plain(ITEM + "_" + key, hexcol, rough, emit=emit)
    return M[key]


def stone():
    if "stone" not in M:
        n = 256
        a, b = K.tile_noise(n, 1.5, 31), K.tile_noise(n, 0.7, 32)
        rgb = CL.mix(CL.C("#7d7f8c"), CL.C("#9c9dab"), np.clip(a * 1.6 - 0.2, 0, 1)[..., None])
        rgb = CL.mix(rgb, CL.C("#bdbdca"), np.clip(b * 2.2 - 1.25, 0, 1)[..., None])
        i = K.save_image(ITEM + "_stone", rgb, TEX)
        nm = K.save_image(ITEM + "_stone_n", K.normal_from_height(0.6 * a + 0.4 * b, 2.0), TEX)
        M["stone"] = K.textured(ITEM + "_stone", i, rough=0.9, normal=nm, normal_strength=1.0)
    return M["stone"]


# --- pieces ------------------------------------------------------------------------------------------

def lin(a, b, n):
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def bx(name, size, loc, mat, grain="z", bevel=0.02, seg=2, rot=(0, 0, 0), scale=1.5):
    ob = K.box(name, size, loc, mat, bevel=bevel, seg=seg, rot=rot)
    K.uv_box(ob, scale, grain=grain)
    return ob


def beam(name, pts, w, h, mat, square=0.4, sides=10):
    """A rounded bar along pts. For a level bar w is its width and h its height; for an upright
    one w is its size front to back and h side to side."""
    return CL.beam(name, [Vector(p) for p in pts], w, h, mat, sides=sides, v_scale=1.5, square=square)


def tube(name, pts, r, mat, sides=8):
    rr = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    return CL.tube(name, [Vector(p) for p in pts], rr, mat, sides=sides)


def pillow(name, size, loc, mat, rot=(0, 0, 0), boxy=0.45, scale=3.2):
    ob = K.ball(name, 1.0, loc, mat, scale=(size[0] / 2, size[1] / 2, size[2] / 2), u=14, v=8, boxy=boxy)
    ob.rotation_euler = [math.radians(a) for a in rot]
    bpy.context.view_layer.update()
    K.uv_box(ob, scale)
    return ob


def ball(name, r, loc, mat, scale=(1, 1, 1), u=10, v=7):
    return K.ball(name, r, loc, mat, scale=scale, u=u, v=v)


def cyl(name, r1, r2, depth, loc, mat, verts=12, rot=(0, 0, 0), bevel=0.0):
    ob = K.cyl(name, r1, r2, depth, loc, mat, verts=verts, rot=rot, bevel=bevel)
    K.uv_box(ob, 1.5)
    return ob


def lathe(name, prof, loc, mat, steps=12, sharp=50):
    return K.lathe(name, prof, mat, steps=steps, loc=loc, sharp=sharp)


def candle(x, y, z, h=0.16):
    """A cream candle in a small brass dish with a lit flame."""
    lathe("dish", [(0.0, 0.0), (0.06, 0.0), (0.075, 0.02), (0.06, 0.022), (0.03, 0.015)], (x, y, z), flat("brass", "#c98a2e", 0.45), steps=10)
    cyl("candle", 0.028, 0.03, h, (x, y, z + 0.015 + h / 2), flat("wax", "#f3e6c8", 0.7), verts=8)
    ball("flame", 0.02, (x, y, z + 0.04 + h), flat("flame", "#ffc24a", 0.4, emit=3.0), scale=(1, 1, 1.9), u=8, v=6)


def drape(name, size, centre, yaw, mat, cell=0.025, frames=90, tris=900, uv_scale=3.2, fringe=18, tassel=0.1, floor=None):
    """A blanket of size (x, y) dropped flat from `centre` (turned `yaw` degrees) onto everything
    built so far and left to settle by cloth simulation, then cut down to about `tris` triangles,
    given a turned-under hem and a fringe along its two short ends."""
    sc = bpy.context.scene
    nx, ny = round(size[0] / cell), round(size[1] / cell)
    rz = Matrix.Rotation(math.radians(yaw), 3, "Z")
    rng = random.Random(7)
    verts, uvs_v = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            lx, ly = (i / nx - 0.5) * size[0], (j / ny - 0.5) * size[1]
            verts.append(Vector(centre) + rz @ Vector((lx, ly, rng.uniform(-0.004, 0.004))))
            uvs_v.append((lx * uv_scale, ly * uv_scale))
    faces, uvs = [], []
    for j in range(ny):
        for i in range(nx):
            f = (i + j * (nx + 1), i + 1 + j * (nx + 1), i + 1 + (j + 1) * (nx + 1), i + (j + 1) * (nx + 1))
            faces.append(f)
            uvs.extend(uvs_v[k] for k in f)
    solids = [o for o in K.COLL.objects if o.type == "MESH"]
    for o in solids:
        o.modifiers.new("hit", "COLLISION")
        o.collision.thickness_outer = 0.012
        o.collision.cloth_friction = 60.0
        o.collision.damping = 0.9
    ob = CL._finish_mesh(name, verts, faces, uvs, mat, recalc=False)
    c = ob.modifiers.new("cloth", "CLOTH")
    st, cs = c.settings, c.collision_settings
    st.quality = 10
    st.mass = 0.25
    st.tension_stiffness = st.compression_stiffness = 12.0
    st.shear_stiffness = 4.0
    st.bending_stiffness = 0.25     # a soft wool blanket: it folds rather than tents
    st.tension_damping = st.compression_damping = st.shear_damping = 6.0
    st.bending_damping = 0.6
    st.air_damping = 2.0
    cs.collision_quality = 5
    cs.distance_min = 0.012
    cs.use_self_collision = True
    cs.self_distance_min = 0.008
    c.point_cache.frame_start, c.point_cache.frame_end = 1, frames
    sc.frame_start, sc.frame_end = 1, frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    K.apply_mods(ob)
    for o in solids:
        o.modifiers.remove(o.modifiers["hit"])
    sc.frame_set(1)
    me = ob.data
    rows = [[me.vertices[i + j * (nx + 1)].co.copy() for i in range(nx + 1)] for j in (0, 3, ny, ny - 3)]

    if os.environ.get("DRAPE_DEBUG"):
        for r in rows:
            print("[drape]", " ".join("(%.2f %.2f %.2f)" % tuple(r[i]) for i in range(0, nx + 1, 5)))
    d = ob.modifiers.new("lean", "DECIMATE")
    d.ratio = min(1.0, tris / (2.0 * nx * ny))
    K.apply_mods(ob)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    rim = [e for e in bm.edges if e.is_boundary]
    at = {v: v.link_loops[0][uv].uv.copy() for e in rim for v in e.verts}
    out = bmesh.ops.extrude_edge_only(bm, edges=rim)["geom"]
    bm.normal_update()
    for v in [g for g in out if isinstance(g, bmesh.types.BMVert)]:
        src = next(e.other_vert(v) for e in v.link_edges if e.other_vert(v) in at)
        at[v] = at[src]
        v.co = src.co - src.normal * 0.016
    for f in {f for g in out if isinstance(g, bmesh.types.BMEdge) for f in g.link_faces}:
        for lp in f.loops:
            lp[uv].uv = at[lp.vert]
        f.smooth = True
    bm.to_mesh(me)
    bm.free()

    # fringe: flat strands in the plane of the cloth (the material is two-sided), every other one
    # cream, taken from the tartan's cream crossing. They carry on the way the cloth runs, stand a
    # little proud of it, and stop short of `floor` (a seat they would otherwise sink into).
    tv, tf, tu = [], [], []
    pitch = size[0] / fringe
    for edge, inner, flip in ((rows[0], rows[1], -1.0), (rows[2], rows[3], 1.0)):
        for k in range(fringe):
            t = (k + 0.5) / fringe * nx
            i0 = min(int(t), nx - 1)
            p = edge[i0].lerp(edge[i0 + 1], t - i0)
            run = (p - inner[i0].lerp(inner[i0 + 1], t - i0)).normalized()
            across = (edge[i0 + 1] - edge[i0]).normalized()
            face = across.cross(run * flip).normalized()
            along = (run + across * rng.uniform(-0.16, 0.16) + face * 0.12).normalized()
            length = tassel * rng.uniform(0.85, 1.1)
            if floor is not None and along.z < -0.05:
                length = max(0.035, min(length, (p.z - floor) / -along.z))
            root = p + face * 0.008 - run * 0.012
            tint = (0.0, 0.0) if k % 2 else (0.118, 0.118)
            b0 = len(tv)
            tv.extend([root - across * pitch * 0.36, root + across * pitch * 0.36,
                       root + along * length + across * pitch * 0.3, root + along * length - across * pitch * 0.3])
            tf.append((b0, b0 + 1, b0 + 2, b0 + 3))
            tu.extend([tint] * 4)
    CL._finish_mesh(name + "_fringe", tv, tf, tu, mat, recalc=False, smooth=False)
    return ob


# --- rocking chair -------------------------------------------------------------------------------------

def rocking_chair():
    w, p = wood(), plaid()
    for s in (-1, 1):
        x = s * 0.31
        beam("rocker", [(x, y, 0.035 + 0.5 * y * y) for y in lin(-0.52, 0.56, 12)], 0.075, 0.075, w)
        beam("front_leg", [(x, -0.25, 0.08), (x, -0.25, 0.61)], 0.07, 0.07, w)
        beam("back_post", [(x, 0.24, 0.10), (x, 0.255, 0.5), (x, 0.305, 0.85), (x, 0.36, 1.13)], 0.07, 0.07, w)
        beam("arm", [(x * 1.04, 0.31, 0.60), (x * 1.06, 0.0, 0.635), (x * 1.06, -0.28, 0.63), (x * 1.06, -0.37, 0.595)], 0.11, 0.055, w)
        beam("side_rail", [(x, -0.25, 0.20), (x, 0.24, 0.20)], 0.05, 0.05, w)
        ball("post_knob", 0.05, (x, 0.365, 1.16), w)
    beam("front_rail", [(-0.31, -0.25, 0.22), (0.31, -0.25, 0.22)], 0.05, 0.055, w)
    bx("seat", (0.68, 0.60, 0.07), (0, 0.0, 0.30), w, grain="y", bevel=0.028)
    pillow("seat_pad", (0.60, 0.54, 0.15), (0, -0.01, SEAT - 0.06), p)
    beam("crest", [(-0.34, 0.36, 1.10), (-0.17, 0.365, 1.155), (0, 0.37, 1.17), (0.17, 0.365, 1.155), (0.34, 0.36, 1.10)], 0.055, 0.13, w)
    beam("back_rail", [(-0.31, 0.262, 0.52), (0.31, 0.262, 0.52)], 0.045, 0.07, w)
    for x in (-0.21, -0.07, 0.07, 0.21):
        beam("slat", [(x, 0.265, 0.52), (x, 0.36, 1.12)], 0.028, 0.075, w)
    pillow("back_pad", (0.46, 0.10, 0.44), (0, 0.262, 0.83), p, rot=(-9, 0, 0))
    for x in (-0.14, 0.14):
        bx("strap", (0.055, 0.035, 0.20), (x, 0.315, 1.06), p, bevel=0.012, rot=(-9, 0, 0), scale=3.2)
        ball("stud", 0.022, (x, 0.293, 1.115), flat("brass", "#c98a2e", 0.45))


# --- armchair and sofa ---------------------------------------------------------------------------------

def upholstered(seats, fab, fab_light):
    """The body of the armchair (one seat) or sofa (two): bun feet, a box base, loose seat cushions,
    rolled arms and a leaning back with its own cushions. Returns the seat cushions' centres (x)."""
    w = wood()
    width = 0.94 if seats == 1 else 1.92
    for sx in (-1, 1):
        for sy in (-1, 1):
            lathe("foot", [(0.0, 0.0), (0.045, 0.0), (0.07, 0.03), (0.066, 0.075), (0.04, 0.105)], (sx * (width / 2 - 0.11), sy * 0.32, 0.0), w, steps=10)
    bx("base", (width - 0.06, 0.80, 0.23), (0, 0.0, 0.205), fab, bevel=0.06, seg=3, scale=2.2)
    cw = (width - 0.44) / seats
    xs = [(-(seats - 1) / 2 + i) * cw for i in range(seats)]
    for cx in xs:
        bx("seat_cushion", (cw - 0.015, 0.64, 0.12), (cx, -0.075, SEAT - 0.06), fab_light, bevel=0.05, seg=3, scale=2.2)
        pillow("back_cushion", (cw - 0.03, 0.22, 0.44), (cx, 0.20, 0.66), fab_light, rot=(-12, 0, 0))
    for s in (-1, 1):
        bx("arm", (0.21, 0.84, 0.36), (s * (width / 2 - 0.105), 0.0, 0.36), fab, bevel=0.08, seg=3, scale=2.2)
        ob = K.cyl("arm_roll", 0.13, 0.13, 0.84, (s * (width / 2 - 0.11), 0.0, 0.555), fab, verts=14, rot=(90, 0, 0), bevel=0.035, seg=3)
        K.uv_box(ob, 2.2)
    bx("back", (width - 0.08, 0.24, 0.66), (0, 0.325, 0.57), fab, bevel=0.11, seg=3, rot=(-7, 0, 0), scale=2.2)
    return xs


def armchair():
    upholstered(1, cloth("fabric", "#8a9a4b"), cloth("fabric_light", "#94a454"))
    pillow("cushion", (0.38, 0.13, 0.38), (0.05, 0.06, 0.63), plaid(), rot=(-20, 0, 8))


def sofa():
    xs = upholstered(2, cloth("fabric", "#e6cc9b"), cloth("fabric_light", "#ecd6a8"))
    p = plaid()
    # a plaid throw dropped over the back and the arm at one end, and two cushions at the other
    drape("throw", (0.74, 1.04), (xs[0] - 0.13, 0.25, 1.0), 6.0, p, floor=SEAT + 0.012)
    pillow("cushion", (0.36, 0.13, 0.36), (xs[1] - 0.12, 0.05, 0.63), p, rot=(-20, 0, 6))
    pillow("cushion_green", (0.36, 0.13, 0.36), (xs[1] + 0.2, 0.10, 0.65), cloth("green", "#7f8f45"), rot=(-18, 0, -14))


# --- knitted rug ---------------------------------------------------------------------------------------

def rug_red():
    """The wool rug (3 x 2 m with its tassels), knitted: red stockinette with cream colourwork (a
    Nordic star, sprigs, daisies and diamonds; knit.py), a twisted cord round the edge and a row of
    cream tassels at each end. It lies flat: she walks over it, so nothing is draped or rumpled."""
    length, width, top = 2.5, 1.826, 0.034
    pat = knit.rug_pattern()
    fibre = web_map("knitted_fleece/knitted_fleece_diff_1k.jpg", 512).mean(axis=2)
    fibre = np.clip(1.0 + (fibre / fibre.mean() - 1.0) * 2.5, 0.8, 1.2)
    rgb, hgt = knit.stitch_maps(pat, (CL.C("#bf2a21"), CL.C("#f2e0b9")), px=12, fibre=fibre)
    img = K.save_image(ITEM + "_knit", rgb, TEX)
    nm = K.save_image(ITEM + "_knit_n", K.normal_from_height(hgt, 2.2), TEX)
    mat = K.textured(ITEM + "_knit", img, rough=1.0, normal=nm, normal_strength=1.0)

    # the knitted slab: a gently uneven top and a skirt down to the floor under the cord
    nx, ny = 10, 7
    rng = random.Random(4)
    verts, uv_v = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x, y = (i / nx - 0.5) * length, (j / ny - 0.5) * width
            edge = i in (0, nx) or j in (0, ny)
            verts.append((x, y, top + (0.0 if edge else rng.uniform(-0.003, 0.004))))
            uv_v.append((0.5 - y / width, 0.5 + x / length))
    faces = [(i + j * (nx + 1), i + 1 + j * (nx + 1), i + 1 + (j + 1) * (nx + 1), i + (j + 1) * (nx + 1))
             for j in range(ny) for i in range(nx)]
    ring = ([i for i in range(nx)] + [nx + j * (nx + 1) for j in range(ny)]
            + [ny * (nx + 1) + nx - i for i in range(nx)] + [(ny - j) * (nx + 1) for j in range(ny)])
    low = len(verts)
    for k in ring:
        x, y, _ = verts[k]
        verts.append((x + math.copysign(0.012, x) * (abs(x) > length / 2 - 1e-6), y + math.copysign(0.012, y) * (abs(y) > width / 2 - 1e-6), 0.002))
        uv_v.append(uv_v[k])
    for n, k in enumerate(ring):
        k2, n2 = ring[(n + 1) % len(ring)], (n + 1) % len(ring)
        faces.append((k2, k, low + n, low + n2))
    CL._finish_mesh("knit", verts, faces, [uv_v[k] for f in faces for k in f], mat, recalc=False)

    # the cord round the edge
    ci, cn = CL.yarn_maps(ITEM + "_cord", TEX, "#a82219", plies=3, twists=2)
    cord = K.textured(ITEM + "_cord", ci, rough=1.0, normal=cn, normal_strength=1.0)
    hx, hy, rc, r = length / 2, width / 2, 0.07, 0.03
    path = []
    for qx, qy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        for k in range(5):
            a = math.radians(a0 + 90 * k / 4)
            path.append((qx * (hx - rc) + rc * math.cos(a), qy * (hy - rc) + rc * math.sin(a), r))
    path.append(path[0])
    CL.tube("cord", path, [r] * len(path), cord, sides=8, v_scale=7.0, caps=False)

    # tassels: a wrapped head and a skirt of strands, lying on the floor, each a little askew
    ti, tn = CL.yarn_maps(ITEM + "_tassel", TEX, "#f0dcb2", plies=9, twists=0.5)
    yarn = K.textured(ITEM + "_tassel", ti, rough=1.0, normal=tn, normal_strength=1.0)
    count = 11
    for end in (-1, 1):
        for k in range(count):
            y = (k / (count - 1) - 0.5) * (width - 0.1)
            long = rng.uniform(0.2, 0.225)
            prof = [(0.0, 0.0), (0.034, 0.014), (0.038, 0.05), (0.022, 0.07), (0.042, 0.115), (0.058, long), (0.0, long)]
            t = K.lathe("tassel", prof, yarn, steps=8, loc=(end * (hx + 0.02), y, 0.036), sharp=60)
            t.rotation_euler = (0.0, math.radians(90) * end, math.radians(rng.uniform(-8, 8)))
            t.scale = (0.62, 1.0, 1.0)      # flattened where it lies (its own X is up once turned)


# --- kitchen counter -----------------------------------------------------------------------------------

def kitchen():
    cab = wood("cabinet", "#7b8a4d", "#93a161", "#556230", seams=4, knots=0, seed=4)
    w = wood()
    brass = flat("brass", "#c98a2e", 0.45)
    bx("body", (1.84, 0.72, 0.70), (0, 0.04, 0.47), cab, bevel=0.012, seg=1)
    for sx in (-1, 1):
        for y in (-0.33, 0.40):
            bx("post", (0.10, 0.10, 0.82), (sx * 0.90, y, 0.41), cab, bevel=0.02)
    bx("kick", (1.72, 0.05, 0.09), (0, -0.335, 0.165), cab, grain="x", bevel=0.015)
    for cx in (0.07, 0.59):   # two panelled doors
        bx("door", (0.50, 0.035, 0.56), (cx, -0.335, 0.50), cab, bevel=0.012)
        for sx in (-1, 1):
            bx("door_stile", (0.07, 0.025, 0.56), (cx + sx * 0.215, -0.36, 0.50), cab, bevel=0.012)
        for z in (0.255, 0.745):
            bx("door_rail", (0.38, 0.025, 0.07), (cx, -0.36, z), cab, grain="x", bevel=0.012)
    for x in (0.275, 0.385):
        ball("knob", 0.03, (x, -0.385, 0.55), brass)
    # worktop, left open over the sink
    bx("worktop", (1.27, 0.94, 0.08), (0.385, 0.02, 0.86), w, grain="x", bevel=0.03)
    bx("worktop_end", (0.16, 0.94, 0.08), (-0.94, 0.02, 0.86), w, grain="y", bevel=0.03)
    bx("worktop_back", (0.64, 0.42, 0.08), (-0.56, 0.28, 0.86), w, grain="x", bevel=0.03)
    # a deep cream sink whose apron front stands proud of the cabinet
    ce = flat("ceramic", "#efe6d2", 0.35)
    sx0, sy0 = -0.56, -0.19
    bx("sink_floor", (0.60, 0.50, 0.04), (sx0, sy0, 0.70), ce, bevel=0.01, seg=1)
    for d in (-1, 1):
        bx("sink_side", (0.06, 0.52, 0.27), (sx0 + d * 0.28, sy0, 0.775), ce, bevel=0.025, seg=3)
        bx("sink_wall", (0.62, 0.06, 0.27), (sx0, sy0 + d * 0.23, 0.775), ce, bevel=0.025, seg=3)
    # brass tap: a bar, two handles and a swan-neck spout
    bx("tap_bar", (0.26, 0.04, 0.035), (sx0, 0.13, 0.925), brass, bevel=0.012)
    for d in (-1, 1):
        cyl("tap_stem", 0.016, 0.016, 0.07, (sx0 + d * 0.11, 0.13, 0.97), brass, verts=8)
        bx("tap_handle", (0.07, 0.022, 0.022), (sx0 + d * 0.11, 0.13, 1.01), brass, bevel=0.008)
    tube("spout", [(sx0, 0.13, 0.93), (sx0, 0.13, 1.10), (sx0, 0.10, 1.17), (sx0, 0.02, 1.19), (sx0, -0.05, 1.15), (sx0, -0.07, 1.09)], 0.02, brass)
    # stove top with a red kettle
    iron = flat("iron", "#2e2a2b", 0.6)
    bx("hob", (0.50, 0.46, 0.035), (0.70, -0.02, 0.915), iron, bevel=0.012)
    for y in (-0.13, 0.10):
        K.torus("burner", 0.085, 0.014, (0.70 - 0.11, y, 0.94), iron, major=12, minor=5)
        K.torus("burner", 0.085, 0.014, (0.70 + 0.12, y, 0.94), iron, major=12, minor=5)
    red = flat("enamel", "#c5362b", 0.35)
    kx, ky = 0.82, -0.12
    lathe("kettle", [(0.0, 0.0), (0.105, 0.0), (0.125, 0.04), (0.12, 0.10), (0.085, 0.15), (0.05, 0.165), (0.0, 0.165)], (kx, ky, 0.945), red, steps=14)
    ball("kettle_knob", 0.022, (kx, ky, 1.125), wood())
    tube("kettle_spout", [(kx - 0.09, ky, 1.01), (kx - 0.15, ky, 1.05), (kx - 0.19, ky, 1.10)], [0.026, 0.02, 0.014], red)
    tube("kettle_handle", [(kx - 0.07, ky, 1.10), (kx - 0.05, ky, 1.19), (kx + 0.05, ky, 1.19), (kx + 0.07, ky, 1.10)], 0.013, wood())
    # a wooden bowl of apples and two cream jars
    lathe("bowl", [(0.0, 0.0), (0.07, 0.0), (0.15, 0.06), (0.17, 0.10), (0.155, 0.10), (0.13, 0.065), (0.0, 0.035)], (0.02, -0.08, 0.90), w, steps=14)
    apple = flat("apple", "#c9342c", 0.45)
    for (ax, ay, az) in ((-0.045, -0.10, 0.985), (0.065, -0.06, 0.985), (0.0, -0.03, 0.99), (0.02, -0.13, 0.99), (0.0, -0.08, 1.04)):
        ball("apple", 0.056, (ax, ay, az), apple, scale=(1, 1, 0.9))
    lid = flat("jar_lid", "#d9cdb1", 0.5)
    for (jx, jy, js) in ((0.26, 0.26, 1.0), (0.44, 0.22, 0.82)):
        lathe("jar", [(0.0, 0.0), (0.075 * js, 0.0), (0.085 * js, 0.02), (0.085 * js, 0.15 * js), (0.07 * js, 0.175 * js), (0.0, 0.175 * js)], (jx, jy, 0.90), ce, steps=12)
        lathe("jar_lid", [(0.078 * js, 0.0), (0.078 * js, 0.02), (0.03 * js, 0.04), (0.0, 0.04)], (jx, jy, 0.90 + 0.175 * js), lid, steps=12)
        ball("jar_knob", 0.02 * js, (jx, jy, 0.90 + 0.235 * js), lid)


# --- dining table --------------------------------------------------------------------------------------

def dining_table():
    w = wood(knots=2)
    for i, y in enumerate((-0.31, 0.0, 0.31)):
        bx("plank", (1.90, 0.305, 0.085), (0, y, 0.745 + 0.004 * (i % 2)), w, grain="x", bevel=0.028)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx("leg", (0.14, 0.14, 0.71), (sx * 0.80, sy * 0.34, 0.355), w, bevel=0.03)
            ball("peg", 0.018, (sx * 0.80, sy * 0.415, 0.64), flat("peg", "#7a4320", 0.7))
        bx("apron_end", (0.06, 0.60, 0.13), (sx * 0.80, 0, 0.635), w, grain="y", bevel=0.02)
    for sy in (-1, 1):
        bx("apron", (1.50, 0.06, 0.13), (0, sy * 0.34, 0.635), w, grain="x", bevel=0.02)
    p = plaid()
    bx("runner", (1.94, 0.36, 0.018), (0, 0, 0.798), p, grain="x", bevel=0.006, seg=1, scale=3.2)
    for sx in (-1, 1):
        bx("runner_drop", (0.018, 0.36, 0.16), (sx * 0.972, 0, 0.725), p, bevel=0.006, seg=1, scale=3.2)
    # a cream jug of yellow flowers, a candle each end
    ce = flat("ceramic", "#efe6d2", 0.4)
    lathe("jug", [(0.0, 0.0), (0.06, 0.0), (0.085, 0.05), (0.08, 0.12), (0.05, 0.17), (0.062, 0.20), (0.045, 0.20), (0.04, 0.17), (0.0, 0.17)], (0, 0, 0.807), ce, steps=14)
    K.torus("jug_band", 0.084, 0.008, (0, 0, 0.875), flat("band", "#6f93b5", 0.5), major=14, minor=4)
    tube("jug_handle", [(0.07, 0, 0.96), (0.125, 0, 0.94), (0.125, 0, 0.88), (0.08, 0, 0.855)], 0.012, ce)
    rng = random.Random(3)
    stem, petal, eye = flat("stem", "#5d8a35", 0.8), flat("petal", "#f2b01e", 0.6), flat("eye", "#6b3d1c", 0.8)
    for i in range(9):
        a = rng.uniform(0, 6.283)
        r = rng.uniform(0.02, 0.15)
        top = Vector((math.cos(a) * r, math.sin(a) * r, 1.07 + rng.uniform(0.0, 0.14) - r * 0.35))
        tube("stem", [(0, 0, 0.99), (top.x * 0.5, top.y * 0.5, 1.04), tuple(top)], 0.006, stem, sides=5)
        ob = ball("flower", 0.05, tuple(top), petal, scale=(1, 1, 0.3), u=10, v=5)
        ob.rotation_euler = (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0)
        ball("flower_eye", 0.02, (top.x, top.y, top.z + 0.012), eye, scale=(1, 1, 0.6), u=8, v=5)
    for sx in (-1, 1):
        candle(sx * 0.62, 0.0, 0.807, h=0.15)


# --- bookshelf -----------------------------------------------------------------------------------------

def bookshelf():
    w = wood(knots=2)
    for sx in (-1, 1):
        bx("side", (0.075, 0.42, 1.82), (sx * 0.70, 0.0, 0.93), w, bevel=0.025)
    bx("back", (1.36, 0.03, 1.74), (0, 0.19, 0.93), wood("back", "#b96a2b", "#d08440", "#8f4c1b", seams=5, seed=6), bevel=0.0)
    levels = (0.10, 0.52, 0.94, 1.36)
    for z in levels:
        bx("shelf", (1.36, 0.40, 0.05), (0, 0.0, z), w, grain="x", bevel=0.018)
    bx("top", (1.52, 0.47, 0.07), (0, 0.0, 1.855), w, grain="x", bevel=0.028)
    bx("plinth", (1.40, 0.05, 0.10), (0, -0.19, 0.05), w, grain="x", bevel=0.018)
    cols = [flat("book%d" % i, c, 0.75) for i, c in enumerate(("#a8342c", "#3f5c86", "#5e7a3c", "#d9a441", "#7a3f5e", "#e6dcc0"))]
    band = flat("gilt", "#e0b85a", 0.5)
    rng = random.Random(7)
    for li, z in enumerate(levels):
        x = -0.64
        z0 = z + 0.025
        while x < 0.60:
            if li == 1 and -0.2 < x < 0.0:   # a small pile lying flat
                for k in range(3):
                    bx("book_flat", (0.30, 0.24, 0.05), (x + 0.16, -0.02, z0 + 0.027 + k * 0.052), cols[(k * 2 + 1) % 6], bevel=0.008, seg=1, rot=(0, 0, rng.uniform(-6, 6)))
                x += 0.34
                continue
            bw, bh = rng.uniform(0.05, 0.085), rng.uniform(0.25, 0.34)
            lean = rng.uniform(-14, -9) if rng.random() < 0.1 and x < 0.4 else 0.0
            c = cols[rng.randrange(6)]
            cx = x + bw / 2 + (0.035 if lean else 0)
            bx("book", (bw * 0.92, 0.25, bh), (cx, -0.035, z0 + bh / 2), c, bevel=0.008, seg=1, rot=(0, lean, 0))
            if not lean:
                for dz in (0.22, 0.78):
                    bx("book_band", (bw * 0.94, 0.012, 0.012), (cx, -0.162, z0 + bh * dz), band, bevel=0.0)
            x += bw + (0.07 if lean else 0) + (0.10 if rng.random() < 0.07 else 0)
    # a trailing plant in a terracotta pot on top
    lathe("pot", [(0.0, 0.0), (0.075, 0.0), (0.105, 0.14), (0.118, 0.145), (0.118, 0.17), (0.095, 0.17), (0.09, 0.14), (0.0, 0.13)], (0.36, 0.0, 1.89), flat("terracotta", "#c5653a", 0.8), steps=12)
    leaf = flat("leaf", "#6ea33a", 0.7)
    leaf2 = flat("leaf2", "#8cbf4a", 0.7)
    for i in range(22):
        a = rng.uniform(0, 6.283)
        r = rng.uniform(0.02, 0.2)
        hang = max(0.0, r - 0.11) * 3.2 + (rng.uniform(0.0, 0.5) if math.cos(a) > 0.2 and r > 0.13 else 0.0)
        pos = (0.36 + math.cos(a) * r, math.sin(a) * r * 0.9, 2.10 - hang + rng.uniform(-0.03, 0.05))
        ob = ball("leaf", 0.055, pos, leaf if i % 3 else leaf2, scale=(1, 0.75, 0.22), u=8, v=5)
        ob.rotation_euler = (rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), a)


# --- wardrobe ------------------------------------------------------------------------------------------

# Measured from ref/wardrobe.png (1024 x 1536). Its camera, from the converging lines: level, eye
# 1.07 m up (the cornice slopes down to the right, the plinth up), 24 degrees round to the left, a
# focal length of 3760 px (59 mm on a 24 mm frame) and 5.9 m from the front left corner. Heights read
# down the middle of the front are 1.625 mm a pixel (the top of the cornice 2.145 m up); the front's
# width and the side's depth are solved through that camera (wardrobe/wardrobe_log.md).
WR_KX = 1.625e-3 / math.cos(math.radians(24))   # metres a pixel across the front, near the middle
WR_W = 1.15          # carcass, side to side (front: 243..884 px)
WR_D = 0.60          # carcass, front to back (side face: 121..243 px solves to 0.62)
WR_Z0 = 0.245        # top of the plinth (1330 px)
WR_ZT = 1.97         # top of the carcass, under the cornice (268 px)
WR_ZC = 2.145        # top of the cornice (160 px)
WR_POST = 0.084      # the corner posts either side of the doors (243..290 px)
WR_DOOR = (0.276, 1.942)   # bottom and top of the doors (1310 and 285 px)
WR_DOOR_X = 0.491    # the doors' outer edges, either side of the middle (290 and 848 px)
WR_HINGE_Y = -WR_D / 2 - 0.004   # the hinges' pins, just in front of the face frame
WR_RAIL_Z = 1.80     # the hanging rail inside (inferred: hidden by the doors in the reference)
WR_RAIL_Y = 0.005
WR_STILE = 0.088     # the doors' stiles (297..345 px)
WR_UV = 3.2          # texture repeats a metre: the reference's grain is fine and busy


def sweep3(name, prof, hx, yf, yb, mat, grain="x", scale=WR_UV):
    """A moulding swept round the two sides and the front of a carcass whose outer faces are at
    x = +-hx and y = yf (front) back to yb, with mitred front corners. prof is [(out, z)], how far
    out from the carcass face each point stands, bottom to top. The back ends are closed."""
    path = [(-1, yb, 0), (-1, yf, 1), (1, yf, 1), (1, yb, 0)]
    rings = []
    for sx, y, corner in path:
        ring = []
        for out, z in prof:
            x = sx * (hx + out)
            yy = y - out if corner else y
            ring.append((x, yy, z))
        rings.append(ring)
    n = len(prof)
    verts = [v for r in rings for v in r]
    faces = []
    for a in range(3):
        for i in range(n - 1):
            faces.append((a * n + i, (a + 1) * n + i, (a + 1) * n + i + 1, a * n + i + 1))
    faces.append(tuple(range(n)))                    # the back ends
    faces.append(tuple(range(3 * n + n - 1, 3 * n - 1, -1)))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = K._obj(name, me, mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    K.smooth(ob)
    K.uv_box(ob, scale, grain=grain)
    return ob


def raised(name, outline, y_back, y_face, inset, mat, scale=WR_UV):
    """A raised panel field: outline(i) gives the panel's outline in XZ shrunk by i (counter-clockwise
    from -Y, the same number of points for any i). The outer edge lies on y_back, the bevel rises
    `inset` inwards to the flat field at y_face (y_face < y_back: toward the front)."""
    o, f = outline(0.0), outline(inset)
    n = len(o)
    verts = [(x, y_back, z) for x, z in o] + [(x, y_face, z) for x, z in f]
    faces = [tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = K._obj(name, me, mat)
    bm = bmesh.new()
    bm.from_mesh(me)
    for fc in bm.faces:   # every face looks toward the front
        fc.normal_update()
        if fc.normal.y > 0:
            fc.normal_flip()
    bm.to_mesh(me)
    bm.free()
    K.uv_box(ob, scale)   # flat shaded: the bevel round the field has to catch the light (ref)
    return ob


def arch_pts(cx, hw, z0, zs, zp, n=13):
    """A door panel's outline: square bottom corners, a cathedral arch on top that rises from zs at
    the sides to zp in the middle (ref: the upper panels, 365 px at the sides, 325 px at the crown)."""
    pts = [(cx - hw, z0), (cx + hw, z0)]
    for k in range(n):
        u = 1.0 - 2.0 * k / (n - 1)
        pts.append((cx + u * hw, zs + (zp - zs) * (1.0 - abs(u) ** 2.4)))
    return pts


def leather(key, base, dark):
    """Red leather for the hat box: mottled, with a faint tooled scroll pattern pressed in (ref)."""
    if key not in M:
        n = 512
        a, b = K.tile_noise(n, 1.4, 41), K.tile_noise(n, 0.6, 42)
        yy, xx = np.mgrid[0:n, 0:n] / n
        scroll = np.clip(np.sin(xx * 2 * np.pi * 6 + np.sin(yy * 2 * np.pi * 3) * 2.2) * np.sin(yy * 2 * np.pi * 4), -1, 1)
        press = np.clip(np.abs(scroll) - 0.82, 0, 1) * 5
        rgb = CL.mix(CL.C(base), CL.C(dark), np.clip(a * 1.5 - 0.35 + press * 0.5, 0, 1)[..., None])
        rgb = rgb * (0.94 + 0.12 * b[..., None])
        i = K.save_image(ITEM + "_" + key, rgb, TEX)
        nm = K.save_image(ITEM + "_" + key + "_n", K.normal_from_height(0.5 * a - press * 0.6, 2.0), TEX)
        M[key] = K.textured(ITEM + "_" + key, i, rough=0.6, normal=nm, normal_strength=0.8)
    return M[key]


def wbx(*a, **k):
    """bx with the wardrobe's finer grain (the reference's wood has many thin grain lines)."""
    return bx(*a, scale=WR_UV, **k)


def fine_wood(key, base, light, dark, seed=1, n=512, lines=8.0):
    """The reference's wood: many thin dark grain lines that wander along the board, soft lighter
    streaks between them and no knots (the textures repeat a few times on each door)."""
    if key not in M:
        yy, xx = np.mgrid[0:n, 0:n]
        u = xx / n
        g = K.grain_noise(n, 14.0, 2.0, seed)
        g2 = K.grain_noise(n, 30.0, 1.4, seed + 7)
        g3 = K.grain_noise(n, 8.0, 2.4, seed + 11)
        phase = lines * u + 5.5 * g + 2.0 * np.sin(2 * np.pi * (2 * u + 3.0 * g3))
        line = 0.5 + 0.5 * np.cos(2 * np.pi * phase)
        streak = np.clip((g2 - 0.5) * 2.2 + 0.5, 0, 1)
        rgb = CL.mix(CL.C(base), CL.C(light), (streak * 0.75)[..., None])
        thin = np.clip((line - 0.9) / 0.1, 0, 1) ** 1.5 * np.clip(g3 * 1.6, 0.25, 1.0)
        rgb = CL.mix(rgb, CL.C(dark), (thin * 0.75)[..., None])
        rgb = rgb * (0.96 + 0.08 * K.tile_noise(n, 1.2, seed + 3)[..., None])
        hgt = 0.35 * streak - 0.6 * thin
        i = K.save_image(ITEM + "_" + key, rgb, TEX)
        nm = K.save_image(ITEM + "_" + key + "_n", K.normal_from_height(hgt, 1.6), TEX)
        M[key] = K.textured(ITEM + "_" + key, i, rough=0.55, normal=nm, normal_strength=0.3)
    return M[key]


def wardrobe():
    """The oak wardrobe of ref/wardrobe.png: a framed carcass with panelled sides, two arched panel
    doors on brass hinges, a stepped cornice and a plinth on bracket feet, a red leather hat box on
    top. It opens: the doors are parts of their own (door_l, door_r, their origins on the hinge pins)
    and inside there is a brass hanging rail, where scripts/wardrobe_view.gd hangs her sweaters."""
    # sampled from the reference's lit front (#e67d28 middle, #f0892f light, grain #ba5911) and the
    # shaded side (#a6551e); the inside is the same wood a little darker (inferred)
    w = fine_wood("wood", "#d0650a", "#ef8618", "#8a3a04", seed=1)
    panel = fine_wood("panel", "#d66b0c", "#f38c1c", "#8f3d06", seed=9)
    inner = fine_wood("inner", "#a9540f", "#c26818", "#6f3006", seed=13)
    brass = flat("brass", "#b98434", 0.35)   # antique brass (ref knob #a76c25 .. #f2bc67)
    brass.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
    hx, yf, yb = WR_W / 2, -WR_D / 2, WR_D / 2
    z0, zt, zc = WR_Z0, WR_ZT, WR_ZC
    # --- the carcass: corner posts, side frames and panels, back, floor, ceiling, face frame
    for sx in (-1, 1):
        wbx("post", (WR_POST, 0.06, zt - z0), (sx * (hx - WR_POST / 2), yf + 0.03, (z0 + zt) / 2), w, bevel=0.012)
        wbx("side_panel", (0.014, WR_D - 0.06, zt - z0), (sx * (hx - 0.013), 0.03, (z0 + zt) / 2), w, bevel=0.004, seg=1)
        wbx("side_inner", (0.004, WR_D - 0.08, zt - z0), (sx * (hx - 0.022), 0.02, (z0 + zt) / 2), inner, bevel=0.0)
        wbx("side_back_stile", (0.016, 0.06, zt - z0), (sx * (hx - 0.004), yb - 0.03, (z0 + zt) / 2), w, bevel=0.006)
        # the side's rails, at the doors' heights (ref: the side panels end where the door panels do)
        for (a, b) in ((z0, z0 + 0.125), (WR_DOOR[0] + 0.593, WR_DOOR[0] + 0.70), (zt - 0.105, zt)):
            wbx("side_rail", (0.016, WR_D - 0.12, b - a), (sx * (hx - 0.004), 0.0, (a + b) / 2), w, grain="y", bevel=0.006)
    wbx("back", (WR_W - 0.02, 0.015, zt - z0), (0, yb - 0.0075, (z0 + zt) / 2), inner, bevel=0.0)
    wbx("floor", (WR_W - 0.04, WR_D - 0.04, WR_DOOR[0] - z0), (0, 0.0, (z0 + WR_DOOR[0]) / 2), inner, grain="x", bevel=0.0)
    wbx("ceiling", (WR_W - 0.04, WR_D - 0.04, zt - WR_DOOR[1]), (0, 0.0, (zt + WR_DOOR[1]) / 2), inner, grain="x", bevel=0.0)
    wbx("frame_top", (2 * WR_DOOR_X + 0.01, 0.03, zt - WR_DOOR[1]), (0, yf + 0.015, (zt + WR_DOOR[1]) / 2), w, grain="x", bevel=0.006)
    wbx("frame_bottom", (2 * WR_DOOR_X + 0.01, 0.03, WR_DOOR[0] - z0), (0, yf + 0.015, (z0 + WR_DOOR[0]) / 2), w, grain="x", bevel=0.006)
    # the hanging rail on two round flanges
    cyl("rail", 0.011, 0.011, WR_W - 0.05, (0, WR_RAIL_Y, WR_RAIL_Z), brass, verts=12, rot=(0, 90, 0))
    for sx in (-1, 1):
        cyl("rail_flange", 0.024, 0.024, 0.01, (sx * (hx - 0.029), WR_RAIL_Y, WR_RAIL_Z), brass, verts=14, rot=(0, 90, 0))
    # --- the cornice: a bead, a cove, a half-round and a bullnosed top (ref: 160..268 px)
    prof = [(0.0, zt), (0.012, zt + 0.002), (0.016, zt + 0.008), (0.012, zt + 0.015)]
    for k in range(1, 7):   # a small cove (ref: the band at 2.03 m is upright and lit, so the cove is low)
        t = math.pi - (math.pi / 2) * k / 6
        prof.append((0.040 + 0.028 * math.cos(t), zt + 0.015 + 0.03 * math.sin(t)))
    prof.append((0.044, zt + 0.047))
    for k in range(1, 9):   # the broad rounded band
        p = math.pi * k / 8
        prof.append((0.044 + 0.018 * math.sin(p), zt + 0.0835 - 0.0365 * math.cos(p)))
    prof.append((0.05, zt + 0.124))
    for k in range(1, 9):   # the top slab's bullnose, 0.078 m out at its fullest (ref: 56 px past the post)
        p = math.pi * k / 8
        prof.append((0.05 + 0.028 * math.sin(p), zt + 0.1495 - 0.0255 * math.cos(p)))
    prof += [(0.03, zc), (-0.04, zc)]
    sweep3("cornice", prof, hx, yf, yb, w)
    wbx("cornice_top", (WR_W - 0.06, WR_D - 0.04, 0.03), (0, 0.0, zc - 0.015), w, grain="x", bevel=0.0)
    # --- the plinth: boards on bracket feet, a bullnosed lip on top (ref: 1330..1480 px)
    ph, po, zl = hx + 0.03, 0.03, z0 - 0.035   # ref: the plinth stands 0.037 m proud, its top edge rounded
    feet = [(-ph, 0.0), (-ph + 0.16, 0.0)]   # ref: the feet's coves rise 0.07 m over 0.09 m
    for k in range(1, 8):
        t = (math.pi / 2) * k / 7
        feet.append((-ph + 0.16 + 0.09 * (1 - math.cos(t)), 0.07 * math.sin(t)))
    feet += [(-x, z) for (x, z) in reversed(feet)]
    feet += [(ph, zl), (-ph, zl)]
    ob = K.extrude_xz("plinth_front", feet, yf - po, yf, w, bevel=0.012)
    K.uv_box(ob, WR_UV, grain="x")
    side = [(yf - po, 0.0), (yf - po + 0.13, 0.0)]
    a, c = (yb - 0.12 - (yf - po + 0.13)) / 2, (yb - 0.12 + (yf - po + 0.13)) / 2
    for k in range(1, 10):
        t = math.pi - math.pi * k / 10
        side.append((c + a * math.cos(t), 0.075 * math.sin(t)))
    side += [(yb - 0.12, 0.0), (yb, 0.0), (yb, zl), (yf - po, zl)]
    for sx in (-1, 1):
        ob = K.extrude_xz("plinth_side", side, -hx - po if sx > 0 else hx, -hx if sx > 0 else hx + po, w, bevel=0.012)
        ob.rotation_euler = (0, 0, math.pi / 2)
        bpy.context.view_layer.update()
        K.uv_box(ob, WR_UV, grain="y")
    wbx("plinth_core", (WR_W, WR_D, zl - 0.09), (0, 0.0, zl / 2 + 0.045), inner, bevel=0.0)
    lip = [(po, zl - 0.002)]
    for k in range(0, 8):   # a quarter round over the plinth's top front edge (ref: 1310..1355 px)
        t = (math.pi / 2) * k / 7
        lip.append((po - 0.03 + 0.03 * math.cos(t), zl + 0.035 * math.sin(t)))
    lip += [(0.0, z0), (-0.02, z0)]
    sweep3("plinth_lip", lip, hx, yf, yb, w)
    # --- the doors (ref: arched raised panels above, square ones below, a broad middle rail)
    d0, d1 = WR_DOOR
    dh = d1 - d0
    for sx, tag in ((-1, "doorL_"), (1, "doorR_")):
        xo, xi = sx * WR_DOOR_X, sx * 0.002
        cx, hw = (xo + xi) / 2, abs(xo - xi) / 2
        yd0, yd1 = WR_HINGE_Y + 0.002, WR_HINGE_Y + 0.028   # front and back of the door's frame
        wbx(tag + "board", (2 * hw - 0.02, 0.012, dh - 0.02), (cx, yd1 - 0.008, (d0 + d1) / 2), panel, bevel=0.0)
        for e in (xo, xi):
            wbx(tag + "stile", (0.08, yd1 - yd0, dh), (e - sx * 0.04 if e == xo else e + sx * 0.04, (yd0 + yd1) / 2, (d0 + d1) / 2), w, bevel=0.01)
        phw = hw - 0.08   # the panels' half width, between the stiles
        wbx(tag + "rail_bottom", (2 * phw, yd1 - yd0 - 0.004, 0.098), (cx, (yd0 + yd1) / 2, d0 + 0.049), w, grain="x", bevel=0.008)
        wbx(tag + "rail_mid", (2 * phw, yd1 - yd0 - 0.004, 0.107), (cx, (yd0 + yd1) / 2, d0 + 0.6465), w, grain="x", bevel=0.008)
        zs, zp = d0 + dh - 0.13, d0 + dh - 0.065
        top = [p for p in arch_pts(cx, phw, 0.0, zs, zp)[2:]][::-1] + [(cx + phw, d1), (cx - phw, d1)]
        ob = K.extrude_xz(tag + "rail_top", top, yd0 + 0.002, yd1 - 0.002, w, bevel=0.008)
        K.uv_box(ob, WR_UV, grain="x")
        raised(tag + "field_top", lambda i, cx=cx, phw=phw, zs=zs, zp=zp: arch_pts(cx, phw - i, d0 + 0.70 + i, zs - i, zp - i),
               yd1 - 0.007, yd0 + 0.006, 0.05, panel)
        raised(tag + "field_bottom", lambda i, cx=cx, phw=phw: [(cx - phw + i, d0 + 0.098 + i), (cx + phw - i, d0 + 0.098 + i),
                                                                (cx + phw - i, d0 + 0.593 - i), (cx - phw + i, d0 + 0.593 - i)],
               yd1 - 0.007, yd0 + 0.006, 0.05, panel)
        # the knob on the meeting stile (ref: 1.14 m up, 0.068 m across)
        kx = sx * 31 * WR_KX   # ref: 568 and 630 px, either side of the meeting stiles at 588
        cyl(tag + "knob_stem", 0.012, 0.016, 0.02, (kx, yd0 - 0.008, 1.137), brass, verts=10, rot=(90, 0, 0))
        ball(tag + "knob", 0.033, (kx, yd0 - 0.034, 1.137), brass, scale=(1, 0.8, 1), u=14, v=9)
        # the hinge leaves on the door; the knuckles stay on the frame
        for z in (0.495, 1.785):
            wbx(tag + "hinge_leaf", (0.016, 0.003, 0.14), (xo - sx * 0.01, yd0 - 0.0015, z), brass, bevel=0.0015, seg=1)
    for sx in (-1, 1):
        for z in (0.495, 1.785):
            cyl("hinge_knuckle", 0.008, 0.008, 0.15, (sx * (WR_DOOR_X + 0.003), WR_HINGE_Y, z), brass, verts=8)
            for dz in (-0.08, 0.08):
                ball("hinge_tip", 0.0075, (sx * (WR_DOOR_X + 0.003), WR_HINGE_Y, z + dz), brass, u=8, v=5)
    # --- the hat box (ref: 0.48 m across, a cream piped lid, a leather strap and brass buckle)
    red, lid_red = leather("hatbox", "#962b1e", "#6a1a12"), leather("hatbox_lid", "#a13023", "#731d14")
    hb = Vector((0.24, 0.06, zc))   # ref: right of the middle and set back
    hh, lh = 0.25, 0.095            # ref: the box 0.25 m tall, the lid a little over a third of it
    cyl("hatbox", 0.25, 0.25, hh, (hb.x, hb.y, zc + hh / 2), red, verts=32, bevel=0.01)
    cyl("hatbox_lid", 0.263, 0.263, lh, (hb.x, hb.y, zc + hh + 0.002 - lh / 2), lid_red, verts=32, bevel=0.014)
    cream = flat("piping", "#e7c792", 0.6)
    K.torus("hatbox_piping", 0.264, 0.007, (hb.x, hb.y, zc + hh - lh + 0.004), cream, major=32, minor=6)
    K.torus("hatbox_piping", 0.257, 0.006, (hb.x, hb.y, zc + hh), cream, major=32, minor=6)
    strap_mat = leather("strap", "#8d4a22", "#5e2c12")
    a = math.radians(14)   # the strap sits a little right of the front (ref: 640..675 px against 620)
    out = Vector((math.sin(a), -math.cos(a), 0))
    rot_z = math.degrees(a)
    p = hb + out * 0.266
    wbx("strap", (0.044, 0.007, 0.14), (p.x, p.y, zc + hh - 0.06), strap_mat, bevel=0.002, seg=1, rot=(0, 0, rot_z))
    p2 = hb + out * 0.14
    wbx("strap_top", (0.044, 0.2, 0.007), (p2.x, p2.y, zc + hh + 0.003), strap_mat, bevel=0.002, seg=1, rot=(0, 0, rot_z))
    p3 = hb + out * 0.273
    for (ox, oz, sx_, sz_) in ((-0.026, 0.0, 0.008, 0.06), (0.026, 0.0, 0.008, 0.06), (0.0, 0.026, 0.06, 0.008), (0.0, -0.026, 0.06, 0.008)):
        side_v = Vector((math.cos(a), math.sin(a), 0)) * ox
        wbx("buckle", (sx_, 0.008, sz_), (p3.x + side_v.x, p3.y + side_v.y, zc + hh - 0.035 + oz), brass, bevel=0.003, seg=1, rot=(0, 0, rot_z))
    wbx("buckle_pin", (0.006, 0.01, 0.05), (p3.x, p3.y, zc + hh - 0.035), brass, bevel=0.002, seg=1, rot=(0, 0, rot_z))


# --- fireplace -----------------------------------------------------------------------------------------

def fireplace():
    st, w = stone(), wood(knots=2)
    rng = random.Random(5)
    dark = flat("soot", "#1d1513", 0.95)
    front = -0.26      # the face of the stonework
    # hearth slab: big flat stones in front
    for (x, y, sx, sy) in ((-0.62, -0.12, 0.72, 0.74), (0.02, -0.14, 0.60, 0.70), (0.64, -0.12, 0.70, 0.74)):
        bx("hearth", (sx - 0.02, sy, 0.10 + rng.uniform(-0.01, 0.015)), (x, y, 0.05), st, bevel=0.035)
    # the core behind the stones, and a sooty firebox
    for sx in (-1, 1):
        bx("pier", (0.46, 0.60, 1.20), (sx * 0.62, 0.14, 0.70), st, bevel=0.02, seg=1)
    bx("lintel", (0.80, 0.60, 0.42), (0, 0.14, 1.09), st, bevel=0.02, seg=1)
    bx("firebox_back", (0.84, 0.04, 0.82), (0, 0.30, 0.50), dark, bevel=0.0)
    bx("firebox_floor", (0.84, 0.50, 0.03), (0, 0.05, 0.115), dark, bevel=0.0)
    for sx in (-1, 1):
        bx("firebox_side", (0.03, 0.50, 0.82), (sx * 0.40, 0.05, 0.50), dark, bevel=0.0)
    # face stones in courses, leaving the arched opening
    z = 0.10
    while z < 1.26:
        h = rng.uniform(0.17, 0.23)
        x = -0.92
        while x < 0.90:
            ln = min(rng.uniform(0.24, 0.40), 0.92 - x)
            cx, cz = x + ln / 2, z + h / 2
            arch_top = 0.50 + 0.40 * math.sqrt(max(0.0, 1 - (cx / 0.44) ** 2)) if abs(cx) < 0.44 else 0.0
            if not (abs(cx) < 0.46 and cz < arch_top + 0.06) and ln > 0.1:
                bx("stone", (ln - 0.015, 0.16, h - 0.015), (cx, front + rng.uniform(-0.01, 0.02), cz), st, bevel=0.04, rot=(0, rng.uniform(-2, 2), 0))
            x += ln
        for sx in (-1, 1):   # the returns down each side
            bx("stone_side", (0.14, 0.52, h - 0.015), (sx * 0.86, 0.10, z + h / 2), st, bevel=0.04)
        z += h
    for i in range(9):   # arch stones round the opening
        t = math.pi * (i + 0.5) / 9
        bx("arch_stone", (0.17, 0.17, 0.19), (0.50 * math.cos(t), front - 0.01, 0.50 + 0.47 * math.sin(t)), st, bevel=0.04, rot=(0, 90 - math.degrees(t), 0))
    # the mantel: a thick beam on two corbels, three candles
    bx("mantel", (2.06, 0.50, 0.15), (0, -0.14, 1.375), w, grain="x", bevel=0.04)
    for sx in (-1, 1):
        bx("corbel", (0.13, 0.26, 0.20), (sx * 0.72, front - 0.10, 1.21), w, bevel=0.035)
    for (x, h) in ((-0.17, 0.13), (0.0, 0.20), (0.17, 0.11)):
        candle(x, -0.20, 1.45, h=h)
    # the chimney breast, tapering up to a cap
    z = 1.45
    row = 0
    while z < 2.42:
        h = rng.uniform(0.19, 0.24)
        half = 0.80 - 0.26 * (z - 1.45)
        bx("breast_core", (half * 2 - 0.2, 0.42, h + 0.02), (0, 0.16, z + h / 2), st, bevel=0.0)
        n = 3 if half > 0.62 else 2
        edges = lin(-half, half, n + 1)
        for k in range(n):
            a, b = edges[k], edges[k + 1]
            if 0 < k:
                a += rng.uniform(-0.08, 0.08) * (1 if row % 2 else -1)
            bx("breast_stone", (b - a - 0.015, 0.20, h - 0.015), ((a + b) / 2, -0.02 + rng.uniform(-0.01, 0.02), z + h / 2), st, bevel=0.045)
        for sx in (-1, 1):
            bx("breast_side", (0.14, 0.44, h - 0.015), (sx * (half - 0.04), 0.17, z + h / 2), st, bevel=0.04)
        z += h
        row += 1
    bx("cap", (1.24, 0.66, 0.13), (0, 0.10, z + 0.065), st, bevel=0.045)
    # logs on an iron grate (the game adds the flickering flames and the firelight)
    iron = flat("iron", "#2e2a2b", 0.6)
    for sx in (-1, 1):
        bx("grate_foot", (0.03, 0.30, 0.10), (sx * 0.24, -0.02, 0.17), iron, bevel=0.008)
    for y in (-0.14, 0.08):
        bx("grate_bar", (0.56, 0.03, 0.03), (0, y, 0.225), iron, bevel=0.008)
    bark = wood("log", "#8a5a34", "#a8744a", "#5a3a20", seed=12)
    for (x, y, zz, yaw, ln) in ((-0.03, -0.06, 0.29, 8, 0.56), (0.04, 0.07, 0.30, -14, 0.50), (0.0, 0.0, 0.385, 20, 0.44)):
        cyl("log", 0.062, 0.058, ln, (x, y, zz), bark, verts=10, rot=(0, 90, yaw), bevel=0.012)


# --- spinning wheel ------------------------------------------------------------------------------------

def spinning_wheel():
    w = wood()
    wd = wood("dark", "#b5642a", "#cf7f3f", "#8a4718", seed=3)
    # the sloping bench on three turned, splayed legs
    beam("bench", [(-0.40, 0, 0.45), (0.34, 0, 0.56)], 0.20, 0.065, w)
    for (x, y, z, fx, fy) in ((-0.33, -0.07, 0.44, -0.44, -0.20), (-0.33, 0.07, 0.44, -0.44, 0.20), (0.26, 0.0, 0.53, 0.40, 0.0)):
        pts = [Vector((x, y, z)).lerp(Vector((fx, fy, 0.0)), t) for t in lin(0, 1, 6)]
        tube("leg", pts, [0.032, 0.045, 0.03, 0.042, 0.03, 0.036], w, sides=10)
    # the wheel between two uprights
    wx, wz, R = 0.14, 0.86, 0.33
    for y in (-0.075, 0.075):
        beam("upright", [(wx + 0.03, y, 0.52), (wx, y, wz + 0.07)], 0.05, 0.055, w)
    K.torus("rim", R, 0.036, (wx, 0, wz), wd, rot=(90, 0, 0), major=24, minor=8)
    cyl("hub", 0.065, 0.065, 0.12, (wx, 0, wz), wd, verts=12, rot=(90, 0, 0), bevel=0.012)
    cyl("axle", 0.016, 0.016, 0.24, (wx, 0, wz), flat("iron", "#2e2a2b", 0.6), verts=8, rot=(90, 0, 0))
    for i in range(8):
        a = math.pi * 2 * i / 8 + 0.2
        tube("spoke", [(wx + 0.05 * math.cos(a), 0, wz + 0.05 * math.sin(a)), (wx + 0.17 * math.cos(a), 0, wz + 0.17 * math.sin(a)),
                       (wx + (R - 0.02) * math.cos(a), 0, wz + (R - 0.02) * math.sin(a))], [0.02, 0.026, 0.017], w, sides=8)
    # treadle and the footman that turns the wheel
    bx("treadle", (0.46, 0.16, 0.03), (0.02, -0.12, 0.07), w, grain="x", bevel=0.012, rot=(0, -6, 0))
    tube("treadle_bar", [(-0.36, -0.17, 0.035), (-0.36, 0.17, 0.035)], 0.018, w, sides=8)
    tube("footman", [(0.2, -0.105, 0.09), (wx + 0.07, -0.105, wz - 0.05)], 0.012, wd, sides=6)
    # the mother-of-all: two maidens holding the flyer and a full bobbin, with a drive band from the wheel
    for x in (-0.36, -0.20):
        tube("maiden", [(x, 0, 0.47 + (x + 0.4) * 0.15), (x, 0, 0.60), (x, 0, 0.70), (x, 0, 0.76)], [0.024, 0.03, 0.02, 0.026], w, sides=8)
    cyl("bobbin", 0.05, 0.05, 0.13, (-0.28, 0, 0.70), flat("yarn", "#efe2c4", 0.95), verts=12, rot=(0, 90, 0), bevel=0.012)
    for x in (-0.345, -0.215):
        cyl("bobbin_end", 0.062, 0.062, 0.016, (x, 0, 0.70), wd, verts=12, rot=(0, 90, 0))
    tube("flyer", [(-0.33, 0, 0.775), (-0.33, 0, 0.80), (-0.28, 0, 0.815), (-0.23, 0, 0.80), (-0.23, 0, 0.775)], 0.011, wd, sides=6)
    band = flat("band", "#e8d9b0", 0.9)
    tube("drive_band", [(-0.215, 0.012, 0.75), (wx - 0.02, 0.012, wz + R + 0.02)], 0.005, band, sides=5)
    tube("drive_band", [(-0.215, 0.012, 0.65), (wx - 0.2, 0.012, wz - R + 0.08)], 0.005, band, sides=5)
    # the distaff with a tuft of wool
    tube("distaff", [(-0.40, 0.04, 0.46), (-0.42, 0.05, 0.80), (-0.43, 0.06, 1.10)], [0.022, 0.016, 0.014], w, sides=8)
    wool = flat("wool", "#f2e8cf", 0.98)
    for (dz, r, dx) in ((1.13, 0.085, 0.0), (1.03, 0.075, 0.015), (0.94, 0.06, -0.01), (1.22, 0.06, -0.01)):
        ball("wool", r, (-0.43 + dx, 0.06, dz), wool, scale=(1, 1, 1.25))


# --- floor lamp ----------------------------------------------------------------------------------------

def lamp():
    w = wood()
    brass = flat("brass", "#c98a2e", 0.45)
    lathe("base", [(0.0, 0.0), (0.17, 0.0), (0.18, 0.025), (0.15, 0.05), (0.075, 0.07), (0.05, 0.10), (0.0, 0.10)], (0, 0, 0), w, steps=16)
    tube("pole", [(0, 0, 0.09), (0, 0, 0.14), (0, 0, 0.19), (0, 0, 0.24), (0, 0, 0.70), (0, 0, 0.75), (0, 0, 0.80), (0, 0, 1.24)],
         [0.03, 0.04, 0.022, 0.018, 0.018, 0.03, 0.018, 0.016], brass, sides=10)
    shade = flat("shade", "#f6d58a", 0.6, emit=0.9)
    lathe("shade", [(0.215, 1.22), (0.155, 1.52), (0.148, 1.52), (0.205, 1.22)], (0, 0, 0), shade, steps=18, sharp=80)
    K.torus("shade_rim", 0.213, 0.012, (0, 0, 1.222), flat("trim", "#d8a54e", 0.5), major=18, minor=5)
    K.torus("shade_rim", 0.153, 0.011, (0, 0, 1.52), flat("trim", "#d8a54e", 0.5), major=18, minor=5)
    ball("bulb", 0.05, (0, 0, 1.33), flat("bulb", "#fff0c0", 0.4, emit=3.0), scale=(1, 1, 1.3))
    tube("harp", [(0, 0, 1.22), (0, 0, 1.56)], 0.008, brass, sides=6)
    ball("finial", 0.025, (0, 0, 1.585), brass)


# --- potted fern ---------------------------------------------------------------------------------------

def frond(name, yaw, length, lift, mats, rng):
    """One fern frond: an arching rib with pointed leaflets down both sides, built as flat blades
    (two-sided)."""
    n = 11
    verts, faces = [], []
    rib = []
    for i in range(n + 1):
        t = i / n
        r = length * t
        z = math.sin(math.radians(lift)) * r - 0.32 * length * t * t
        rib.append(Vector((math.cos(math.radians(lift)) * r, 0.0, z)))
    for i in range(1, n + 1):
        t = i / n
        size = length * 0.27 * math.sin(math.pi * min(1.0, t * 1.12)) ** 0.7 * (1.0 - 0.35 * t) + 0.012
        fwd = (rib[i] - rib[i - 1]).normalized()
        for s in (-1, 1):
            out = Vector((0, s, 0))
            tip = rib[i] + out * size + fwd * size * 0.45 + Vector((0, 0, -size * 0.25))
            a, b = rib[i] - fwd * size * 0.22, rib[i] + fwd * size * 0.22
            mid = (rib[i] + tip) / 2 + Vector((0, 0, size * 0.10))
            k = len(verts)
            verts += [a, mid + fwd * size * 0.16, tip, mid - fwd * size * 0.16, b]
            faces += [(k, k + 3, k + 2, k + 1), (k, k + 1, k + 4), (k + 1, k + 2, k + 3, k)[::-1], (k + 4, k + 1, k)]
    rot = Matrix.Rotation(yaw, 4, "Z")
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(rot @ v) for v in verts], [], faces)
    ob = K._obj(name, me, mats[rng.randrange(len(mats))])
    tube(name + "_rib", [tuple(rot @ p) for p in rib[::2]], [0.008, 0.007, 0.006, 0.005, 0.004, 0.003][:len(rib[::2])], mats[0], sides=5)
    return ob


def plant():
    terracotta = flat("terracotta", "#c5653a", 0.8)
    lathe("pot", [(0.0, 0.0), (0.105, 0.0), (0.155, 0.22), (0.172, 0.225), (0.172, 0.27), (0.145, 0.27), (0.138, 0.23), (0.0, 0.21)], (0, 0, 0), terracotta, steps=16)
    cyl("soil", 0.14, 0.14, 0.02, (0, 0, 0.225), flat("soil", "#5a3a22", 0.95), verts=14)
    greens = [flat("leaf", "#7fbf3a", 0.7), flat("leaf2", "#9bd24f", 0.7), flat("leaf3", "#69a832", 0.7)]
    rng = random.Random(8)
    obs = []
    for i in range(20):
        yaw = math.pi * 2 * i / 20 + rng.uniform(-0.2, 0.2)
        inner = i % 3 == 0
        ob = frond("frond", yaw, rng.uniform(0.40, 0.52) if not inner else rng.uniform(0.30, 0.38), rng.uniform(52, 70) if not inner else rng.uniform(78, 86), greens, rng)
        ob.location = (0, 0, 0.24)
        obs.append(ob)
    for ob in [o for o in K.COLL.objects if o.name.startswith("frond_rib")]:
        ob.location.z += 0.24


BUILDERS = {"rocking_chair": rocking_chair, "fireplace": fireplace, "kitchen": kitchen, "sofa": sofa, "armchair": armchair,
            "spinning_wheel": spinning_wheel, "dining_table": dining_table, "bookshelf": bookshelf, "wardrobe": wardrobe,
            "lamp": lamp, "plant": plant, "rug_red": rug_red}


# Parts the game moves, joined into meshes of their own with their origin on the pivot.
PARTS = {"wardrobe": {"door_l": ("doorL_", (-WR_DOOR_X - 0.003, WR_HINGE_Y, 0.0)),
                      "door_r": ("doorR_", (WR_DOOR_X + 0.003, WR_HINGE_Y, 0.0))}}


def main(item):
    global ITEM, TEX
    ITEM = item
    TEX = os.path.join(HERE, item, "tex")
    M.clear()
    K.reset(item)
    BUILDERS[item]()
    bpy.context.view_layer.update()
    bpy.context.preferences.filepaths.save_version = 0
    K.finish(item, os.path.join(HERE, item, "out"), parts=PARTS.get(item))


names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDERS)
for n in names:
    main(n)
