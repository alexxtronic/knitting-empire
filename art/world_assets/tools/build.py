"""Nora's hand tools, after the reference sheet beside this file (reference_sheet.png): chunky,
toy-like, honey wood and dark iron, a strip of cloth or twine on each handle.

    axe           a short hatchet: curved handle with a rounded foot, a wedge head with a worn edge and a
                  rivet on each cheek, a striped cloth band tied with a twine bow
    hoe           a long straight handle, a riveted collar and a square blade hanging beside it
    shovel        a D grip at the foot, twine and a red wrap, a socket running on as a ridge down the blade
    scythe        a crooked snath with two side handles, a crescent blade swept out from its collar
    shears        hedge shears: two broad blades on a pivot bolt, red-wrapped grips, a spring and a loop
    watering_can  a squat iron can with a lid, a cloth-bound bail, a spout with a rose, a felt daisy

Each tool stands upright: the handle along +Z from the origin (the centre of its foot), the
working end at the top, the blade toward +X. The game holds each by its grip (TOOL_HOLD in scripts/main.gd): the can by the top of its bail.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/tools/build.py -- axe
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")


# --- materials ---------------------------------------------------------------------------------------

def wood():
    # round 1: the first wood read as flat orange plastic: more contrast in the grain, rougher
    i, n = CL.plank_maps("tool_wood", TEX, base="#c97d3c", light="#eeb06a", dark="#74401c", knots=4, seed=17)  # round 2: swirls, not ruled stripes
    return K.textured("tool_wood", i, rough=0.82, normal=n, normal_strength=1.0)  # round 4: less gloss


def endgrain():
    i, n = CL.endgrain_maps("tool_endgrain", TEX, base="#dc9450", light="#f2b878", dark="#a8622c")
    return K.textured("tool_endgrain", i, rough=0.6, normal=n, normal_strength=0.5)


def iron_maps(name, n=512, seed=5, wear=True):
    """Forged iron as the reference paints it: dark blue-grey with soft mottling and a few rusty
    blooms; toward u = 1 (the cutting edge) a pale worn band with a ragged, chipped boundary; a
    thin paler rim along v = 0 and v = 1 (the head's top and bottom edges)."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    base = CL.C("#646870")  # round 4: greyer still  # round 2: neutral blue-grey (the violet #6c6873 read purple)
    mott = K.tile_noise(n, 1.6, seed)
    fine = K.tile_noise(n, 0.9, seed + 1)
    speck = (np.random.default_rng(seed).random((n, n)) > 0.985).astype(float)
    rgb = base * (0.78 + 0.4 * mott[..., None]) * (0.9 + 0.2 * fine[..., None]) * (1.0 + 0.35 * speck[..., None])
    rust = np.clip((K.tile_noise(n, 2.2, seed + 2) - 0.62) * 5, 0, 1)
    rgb = CL.mix(rgb, CL.C("#77625a"), (rust * 0.4)[..., None])  # round 2: a hint of rust, not orange smears
    # the worn edge: where the band starts wanders with a noise, and chips bite into it
    ragged = 0.74 + 0.09 * (K.tile_noise(n, 1.2, seed + 3) - 0.5) * 2 + 0.05 * (fine - 0.5) * 2  # round 2: wider, more ragged
    edge = np.clip((u - ragged) / 0.035, 0, 1) if wear else np.zeros_like(u)
    rgb = CL.mix(rgb, CL.C("#cbbcab") * (0.9 + 0.2 * fine[..., None]), edge[..., None])
    rim = np.clip(1 - np.minimum(v, 1 - v) / 0.06, 0, 1) * np.clip((fine - 0.25) * 3, 0, 1) * (np.clip(u * 2.2, 0, 1) if wear else 1.0)
    rgb = CL.mix(rgb, CL.C("#b9ada2"), (rim * 0.85)[..., None])
    hgt = 0.5 * mott + 0.2 * fine - 0.6 * edge
    rough = np.clip(0.66 - 0.08 * edge + 0.15 * rust, 0, 1)  # round 4: the edge was chrome-bright
    return (K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.2), TEX),
            K.save_image(name + "_r", np.repeat(rough[..., None], 3, axis=2), TEX))


def iron(wear=True):
    """wear=False: the same iron with no worn cutting edge (collars, sockets, the can)."""
    nm = "tool_iron" if wear else "tool_iron_plain"
    if nm in bpy.data.materials:
        return bpy.data.materials[nm]
    i, n, r = iron_maps(nm, wear=wear)
    m = K.textured(nm, i, rough=0.6, normal=n, normal_strength=0.7)
    nt = m.node_tree
    b = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = 0.3
    r.colorspace_settings.name = "Non-Color"
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = r
    nt.links.new(t.outputs["Color"], b.inputs["Roughness"])
    return m


def steel():
    m = K.plain("tool_rivet", "#cbbfae", rough=0.4)  # round 1: at metallic 0.85 it rendered black
    b = next(x for x in m.node_tree.nodes if x.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = 0.35
    return m


def band_maps(name, n=256, seed=31):
    """The cloth band: cream weave with two red stripes across v (v runs along the handle)."""
    yy, xx = np.mgrid[0:n, 0:n]
    v = 1 - yy / n
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 6) + 0.25 * np.sin(2 * np.pi * yy / 6)
    mott = K.tile_noise(n, 1.4, seed)
    rgb = CL.C("#ecdcbc") * (0.9 + 0.16 * weave[..., None]) * (0.94 + 0.1 * mott[..., None])
    red = np.zeros_like(v)
    for c in (0.36, 0.64):
        red = np.maximum(red, np.clip(1 - np.abs(v - c) / 0.085, 0, 1) ** 0.35)
    red = (red > 0.5).astype(float)
    rgb = CL.mix(rgb, CL.C("#c9544a") * (0.9 + 0.16 * weave[..., None]), red[..., None])
    return K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(weave * 0.6, 1.6), TEX)


def band():
    i, n = band_maps("tool_band")
    return K.textured("tool_band", i, rough=0.9, normal=n, normal_strength=0.8)


def knot_cloth():
    i, n = CL.cloth_maps("tool_knot", TEX, "#ecdcbc", seed=33)
    return K.textured("tool_knot", i, rough=0.92, normal=n, normal_strength=1.0)


# --- shapes ------------------------------------------------------------------------------------------

def spline(keys, n):
    """Catmull-Rom through (z, value...) keys, sampled at n points evenly in z."""
    keys = np.array(keys, dtype=float)
    zs = np.linspace(keys[0, 0], keys[-1, 0], n)
    out = []
    for z in zs:
        i = int(np.clip(np.searchsorted(keys[:, 0], z) - 1, 0, len(keys) - 2))
        p0, p1, p2, p3 = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]
        t = (z - p1[0]) / (p2[0] - p1[0])
        v = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
        v[0] = z
        out.append(v)
    return np.array(out)


def wedge(name, stations, mat, ring=20, square=0.45, curve=0.0):
    """A forged head lofted through stations along its length. Each station is (x, z_mid,
    half_height, half_thickness): a rounded-rectangle section in the YZ plane at x. `curve` bows
    each section toward -x at its top and bottom, more toward the last station, so the far end is
    a convex cutting edge. UVs: u along the stations (0..1), v up the section (0..1)."""
    st = np.array(stations, dtype=float)
    ns = len(st)
    verts, faces, uvs = [], [], []
    sec = []
    for j in range(ring):
        a = 2 * math.pi * j / ring
        c, s = math.cos(a), math.sin(a)
        # superellipse: boxy with soft corners
        sec.append((math.copysign(abs(c) ** square, c), math.copysign(abs(s) ** square, s)))
    for i, (x, zm, hh, ht) in enumerate(st):
        f = i / (ns - 1)
        for (cy, cz) in sec:
            bow = curve * f * f * cz * cz
            verts.append(Vector((x - bow, cy * ht, zm + cz * hh)))
    for i in range(ns - 1):
        for j in range(ring):
            j1 = (j + 1) % ring
            a0, a1, b0, b1 = i * ring + j, i * ring + j1, (i + 1) * ring + j, (i + 1) * ring + j1
            faces.append((a0, b0, b1, a1))
            for k in (a0, b0, b1, a1):
                ii, jj = divmod(k, ring)
                uvs.append((ii / (ns - 1), 0.5 + 0.5 * sec[jj][1]))
    for end, i in ((0, 0), (1, ns - 1)):
        c = len(verts)
        x, zm, hh, ht = st[i]
        verts.append(Vector((x - (curve * 0.0 if end == 0 else 0.0), 0.0, zm)))
        for j in range(ring):
            j1 = (j + 1) % ring
            tri = (c, i * ring + j1, i * ring + j) if end == 0 else (c, i * ring + j, i * ring + j1)
            faces.append(tri)
            for k in tri:
                if k == c:
                    uvs.append((float(end), 0.5))
                else:
                    uvs.append((float(end) + (0.004 if end == 0 else -0.004) * (1 + sec[k % ring][0]), 0.5 + 0.5 * sec[k % ring][1]))
    return CL._finish_mesh(name, verts, faces, uvs, mat, recalc=True)


def cloth_knot(name, at, mat, out=Vector((0, -1, 0)), side=Vector((1, 0, 0)), size=0.03):
    """The band's tie as the reference shows it: a flat cloth knot with two short, wide tails
    that lie on the wood below it (round 4: a ball on two thin legs read as a little figure)."""
    up = Vector((0, 0, 1))
    K.ball(name, size * 0.6, at + out * size * 0.12, mat, scale=(1.3, 0.42, 0.9), u=14, v=10, boxy=0.75)
    for sgn, drop in ((-1, 1.5), (1, 1.2)):
        p0 = at + out * size * 0.1 - up * size * 0.2
        tail = [p0 + side * sgn * size * (0.15 + 0.8 * t) - up * size * drop * t + out * size * (0.1 - 0.12 * t) for t in np.linspace(0, 1, 7)]
        r = size * 0.42
        # the tube's flat axis for a tail hanging down is `side`: so squash the radii and widen along side
        CL.tube(name + "_tail", tail, [r * 0.3 * k for k in (0.8, 1, 1, 1, 1, 1.05, 0.9)], mat, sides=10, v_scale=14.0, caps=True, flat=1.0 / 0.3)


def dome(name, centre, rx, ry, h, mat, up=1.0, rings=5, sides=28):
    """A shallow rounded cap over an oval (a handle's sawn end), with planar UVs so end-grain
    rings read as rings (round 4: a UV sphere showed its grid)."""
    c = Vector(centre)
    verts, faces, uvs = [], [], []
    for k in range(rings):
        a = (math.pi / 2) * k / rings
        for j in range(sides):
            t = 2 * math.pi * j / sides
            verts.append(c + Vector((rx * math.cos(a) * math.cos(t), ry * math.cos(a) * math.sin(t), up * h * math.sin(a))))
    top = len(verts)
    verts.append(c + Vector((0, 0, up * h)))

    def uv(i):
        v = verts[i] - c
        return (0.5 + 0.48 * v.x / rx, 0.5 + 0.48 * v.y / rx)
    for k in range(rings - 1):
        for j in range(sides):
            q = (k * sides + j, k * sides + (j + 1) % sides, (k + 1) * sides + (j + 1) % sides, (k + 1) * sides + j)
            faces.append(q)
            uvs += [uv(i) for i in q]
    for j in range(sides):
        q = ((rings - 1) * sides + j, (rings - 1) * sides + (j + 1) % sides, top)
        faces.append(q)
        uvs += [uv(i) for i in q]
    return CL._finish_mesh(name, verts, faces, uvs, mat, recalc=True)


# --- the axe -----------------------------------------------------------------------------------------

AXE_H = 0.59
OVAL = 0.82  # the handle's thickness across the blade, against its width along it


def build_axe():
    w, eg, ir, st, bd, kc = wood(), endgrain(), iron(), steel(), band(), knot_cloth()
    # handle: (z, x offset, radius). A gentle S, thickest at the rounded foot, a waist above it.
    # round 1: a third thicker (the reference's handle is a third of the head's length across), a
    # fuller foot, and both ends rounded off in the tube itself (the cap discs stood out as lips)
    # round 5: slim under the head, swelling steadily into a fat club with a clear sweep (the
    # reference's signature shape); still one curve, no kink
    keys = [(0.0, 0.046, 0.058), (0.05, 0.040, 0.064), (0.12, 0.028, 0.060), (0.20, 0.016, 0.052), (0.29, 0.007, 0.045),
            (0.38, 0.002, 0.040), (0.47, 0.0, 0.037), (AXE_H, 0.0, 0.036)]
    sp = spline(keys, 48)
    pts = [Vector((p[1], 0.0, p[0])) for p in sp]
    rad = [float(p[2]) for p in sp]
    # an oval handle, long axis toward the blade (x). CL.tube squashes along its binormal, which
    # for an upright tube is x, so the radii carry the squash and `flat` undoes it along x.
    h = CL.tube("handle", pts, [r * OVAL for r in rad], w, sides=28, v_scale=1.2, u_rep=1.0, caps=True, flat=1.0 / OVAL)
    dome("handle_top", (pts[-1].x, 0.0, AXE_H), rad[-1], rad[-1] * OVAL, rad[-1] * 0.5, eg, up=1.0, rings=7)
    dome("handle_foot", (pts[0].x, 0.0, 0.0), rad[0], rad[0] * OVAL, rad[0] * 0.7, eg, up=-1.0, rings=8)  # round 5: a rounded, bulbous foot
    # the caps (foot and top) show end grain
    h.data.materials.append(eg)
    zs = [v.co.z for v in h.data.vertices]
    lo, hi = min(zs), max(zs)
    for p in h.data.polygons:
        if len(p.vertices) == 3 and all(abs(h.data.vertices[i].co.z - lo) < 0.004 or abs(h.data.vertices[i].co.z - hi) < 0.004 for i in p.vertices):
            p.material_index = 1
    # head: stations (x, z mid, half height, half thickness) from the poll to the cutting edge
    zc = 0.505
    # round 5: a bigger head whose lower corner drops further (a bearded blade), no slot on the poll
    stations = [
        (-0.100, zc + 0.000, 0.040, 0.028), (-0.093, zc + 0.000, 0.058, 0.041), (-0.066, zc + 0.000, 0.064, 0.047),
        (-0.016, zc + 0.000, 0.064, 0.048), (0.036, zc - 0.002, 0.063, 0.046), (0.072, zc - 0.010, 0.068, 0.038),
        (0.106, zc - 0.022, 0.084, 0.028), (0.138, zc - 0.034, 0.103, 0.019), (0.166, zc - 0.043, 0.118, 0.012),
        (0.186, zc - 0.048, 0.125, 0.0085), (0.200, zc - 0.050, 0.124, 0.0055), (0.206, zc - 0.051, 0.120, 0.0035),
    ]
    wedge("head", stations, ir, ring=72, square=0.5, curve=0.05)  # round 2: 72 round, so the edge is one curve
    # a rivet on each cheek, and a collar where the handle goes through
    for sgn in (-1, 1):
        K.ball("rivet", 0.022, (-0.018, sgn * 0.0475, zc + 0.008), st, scale=(1.0, 0.5, 1.0), u=16, v=8)

    # the cloth band: a sleeve round the handle, v from 0 to 1 over its height
    z0, z1 = 0.19, 0.30
    bsp = [p for p in sp if z0 - 0.004 <= p[0] <= z1 + 0.004]
    bpts = [Vector((p[1], 0.0, p[0])) for p in bsp]
    # round 2: a thick wrap that bulges, not a decal: fattest in the middle, tucked in at its edges
    brad = [float(p[2]) + 0.0015 + 0.0035 * math.sin(math.pi * k / (len(bsp) - 1)) ** 0.5 for k, p in enumerate(bsp)]  # round 4: thin wrapped cloth, not a cuff
    length = sum((b - a).length for a, b in zip(bpts, bpts[1:]))
    CL.tube("band", bpts, [r * OVAL for r in brad], bd, sides=28, v_scale=1.0 / length, u_rep=3.0, caps=True, flat=1.0 / OVAL)
    # the tie: a fat cloth knot with two stubby tails on the band's lower edge, at the front
    pt = min(sp, key=lambda p: abs(p[0] - (z0 + 0.012)))
    cloth_knot("knot", Vector((pt[1] + 0.012, -OVAL * (float(pt[2]) + 0.004), z0 + 0.012)), kc, size=0.04)


# --- shared parts for the other five -----------------------------------------------------------------

def once(name, make):
    return bpy.data.materials[name] if name in bpy.data.materials else make()


def felt(name, hexcol):
    return once("tool_felt_" + name, lambda: K.textured("tool_felt_" + name, *CL.cloth_maps("tool_felt_" + name, TEX, hexcol, seed=hash(name) % 97, weave_px=2, rough=0.06)[:1], rough=0.95))


def red_cloth():
    def make():
        i, n = CL.cloth_maps("tool_redcloth", TEX, "#c4503f", seed=41)
        return K.textured("tool_redcloth", i, rough=0.9, normal=n, normal_strength=1.0)
    return once("tool_redcloth", make)


def mats():
    return dict(w=once("tool_wood", wood), eg=once("tool_endgrain", endgrain), ir=iron(), ip=iron(False),
                st=once("tool_rivet", steel), bd=once("tool_band", band), kc=once("tool_knot", knot_cloth))


def set_uv(ob, fn):
    """UVs from each corner's position: fn(co) -> (u, v)."""
    me = ob.data
    layer = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        for li in p.loop_indices:
            layer.data[li].uv = fn(me.vertices[me.loops[li].vertex_index].co)
    return ob


def seg_dist(p, a, b):
    ab = (b[0] - a[0], b[1] - a[1])
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / max(1e-12, ab[0] ** 2 + ab[1] ** 2)))
    return math.hypot(p[0] - a[0] - t * ab[0], p[1] - a[1] - t * ab[1])


def plate(name, outline, thick, mat, cut, depth=0.05, y=0.0, taper=0.45, dish=0.0, dish_axis=(0.0, 0.0), bevel=0.0035):
    """A forged iron plate drawn in XZ: thick at its back, thinner toward the cutting edge (the
    outline's segments listed in `cut`, by their first point's index), where the iron map's worn
    band falls: u runs from 0.1 well inside the plate to 1 at the cutting edge."""
    n = len(outline)
    edges = [(outline[i], outline[(i + 1) % n]) for i in cut]
    ob = K.extrude_xz(name, outline, y - thick / 2, y + thick / 2, mat, bevel=bevel)
    # round 1: the faces had vertices only on the outline, so the worn colour spread over them all
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    flat = [f for f in bm.faces if abs(f.normal.y) > 0.9]
    bmesh.ops.triangulate(bm, faces=flat, quad_method="BEAUTY", ngon_method="BEAUTY")
    for _ in range(1):
        flat = [f for f in bm.faces if abs(f.normal.y) > 0.9]
        es = list({e for f in flat for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=es, cuts=3, use_grid_fill=True)
        flat = [f for f in bm.faces if abs(f.normal.y) > 0.9 and len(f.verts) > 3]
        bmesh.ops.triangulate(bm, faces=flat)
    bm.to_mesh(ob.data)
    bm.free()
    xs = [q[0] for q in outline]
    x0, x1 = min(xs), max(xs)
    for v in ob.data.vertices:
        d = min(seg_dist((v.co.x, v.co.z), a, b) for a, b in edges)
        k = taper + (1 - taper) * min(1.0, d / depth)
        v.co.y = y + (v.co.y - y) * k + dish * ((v.co.x - dish_axis[0]) ** 2)

    def uv(co):
        d = min(seg_dist((co.x, co.z), a, b) for a, b in edges)
        return (1.0 - 0.9 * min(1.0, d / depth), 0.15 + 0.7 * (co.x - x0) / max(1e-6, x1 - x0))
    return set_uv(ob, uv)


def dome_axis(name, centre, axis, r, h, mat, rings=6, sides=24):
    """A shallow rounded wooden end cap facing along axis, with end-grain UVs."""
    ob = dome(name, (0, 0, 0), r, r, h, mat, up=1.0, rings=rings, sides=sides)
    q = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized())
    ob.matrix_world = Matrix.Translation(Vector(centre)) @ q.to_matrix().to_4x4()
    return ob


def rod(name, pts, radii, mt, ends=(True, True), sides=24):
    """A wooden rod along pts with domed end-grain ends."""
    pts = [Vector(p) for p in pts]
    length = sum((b - a).length for a, b in zip(pts, pts[1:]))
    ob = CL.tube(name, pts, radii, mt["w"], sides=sides, v_scale=1.2, u_rep=1.0, caps=True)
    if ends[0]:
        dome_axis(name + "_end0", pts[0], pts[0] - pts[1], radii[0], radii[0] * 0.45, mt["eg"])
    if ends[1]:
        dome_axis(name + "_end1", pts[-1], pts[-1] - pts[-2], radii[-1], radii[-1] * 0.45, mt["eg"])
    return ob, length


def handle(keys, n, mt, top=True, foot=True):
    """A handle like the axe's: (z, x, radius) keys, domed end-grain ends. Returns the samples."""
    sp = spline(keys, n)
    pts = [Vector((p[1], 0.0, p[0])) for p in sp]
    rad = [float(p[2]) for p in sp]
    CL.tube("handle", pts, rad, mt["w"], sides=24, v_scale=1.2, u_rep=1.0, caps=True)
    if top:
        dome("handle_top", (pts[-1].x, 0.0, pts[-1].z), rad[-1], rad[-1], rad[-1] * 0.45, mt["eg"], up=1.0, rings=6)
    if foot:
        dome("handle_foot", (pts[0].x, 0.0, 0.0), rad[0], rad[0], rad[0] * 0.6, mt["eg"], up=-1.0, rings=7)
    return sp


def at(sp, z):
    p = min(sp, key=lambda q: abs(q[0] - z))
    return float(p[1]), float(p[2])


def band_on(name, sp, z0, z1, mat, puff=0.004, knot=None, u_rep=3.0):
    """A cloth band wrapped round a handle between z0 and z1 (a knot with tails at its foot if
    knot is a cloth material)."""
    bsp = [p for p in sp if z0 - 0.004 <= p[0] <= z1 + 0.004]
    bpts = [Vector((p[1], 0.0, p[0])) for p in bsp]
    brad = [float(p[2]) + 0.0015 + puff * math.sin(math.pi * k / (len(bsp) - 1)) ** 0.5 for k, p in enumerate(bsp)]
    length = sum((b - a).length for a, b in zip(bpts, bpts[1:]))
    CL.tube(name, bpts, brad, mat, sides=24, v_scale=1.0 / length, u_rep=u_rep, caps=True)
    if knot is not None:
        x, r = at(sp, z0 + 0.012)
        cloth_knot(name + "_knot", Vector((x + 0.012, -(r + 0.004), z0 + 0.012)), knot, size=0.036)


def twine(name, sp, z0, z1, mat, turns=5, r_cord=0.0065):
    """Cord wound round a handle: a tight helix of fat turns."""
    pts, rad = [], []
    steps = turns * 18
    for k in range(steps + 1):
        t = k / steps
        z = z0 + (z1 - z0) * t
        x, r = at(sp, z)
        a = 2 * math.pi * turns * t
        R = r + r_cord * 0.7
        pts.append(Vector((x + R * math.cos(a), R * math.sin(a), z)))
        rad.append(r_cord * (0.6 + 0.4 * min(1.0, min(t, 1 - t) * 30)))
    CL.tube(name, pts, rad, mat, sides=10, v_scale=30.0, caps=True)


def collar(name, sp, z0, z1, mt, extra=0.007, rivet=True, square=0.5):
    """An iron socket round the handle with a rivet on its front."""
    x, r = at(sp, (z0 + z1) / 2)
    w = 2 * (r + extra)
    CL.beam(name, [Vector((x, 0, z0)), Vector((x, 0, (z0 + z1) / 2)), Vector((x, 0, z1))], w, w, mt["ip"], sides=24, v_scale=2.0, square=square)
    if rivet:
        K.ball(name + "_rivet", 0.011, (x, -(r + extra) - 0.001, (z0 + z1) / 2), mt["st"], scale=(1.0, 0.55, 1.0), u=14, v=8)


# --- the hoe -----------------------------------------------------------------------------------------

HOE_H = 0.78


def build_hoe():
    mt = mats()
    keys = [(0.0, 0.0, 0.040), (0.06, 0.0, 0.038), (0.25, 0.0, 0.034), (0.5, 0.0, 0.031), (HOE_H, 0.0, 0.030)]
    sp = handle(keys, 40, mt)
    zc0, zc1 = HOE_H - 0.12, HOE_H - 0.035
    collar("collar", sp, zc0, zc1, mt)
    # the blade hangs beside the collar: a square top, a big rounded far corner, a straight cutting edge
    top, bot = HOE_H - 0.055, HOE_H - 0.25  # round 1: bigger, the reference's blade is as long as the collar is wide x3
    blade = [(0.025, top), (0.115, top), (0.16, top - 0.014), (0.186, top - 0.05), (0.195, top - 0.105),
             (0.193, bot), (0.042, bot + 0.004), (0.036, bot + 0.06), (0.025, top - 0.06)]
    plate("blade", blade, 0.016, mt["ir"], cut=[4, 5], depth=0.07, taper=0.4)
    band_on("band", sp, 0.09, 0.19, mt["bd"], knot=mt["kc"])


# --- the shovel --------------------------------------------------------------------------------------

def build_shovel():
    mt = mats()
    # the D grip at the foot: a crossbar held by two arms that meet in the shaft
    rod("crossbar", [(-0.072, 0, 0.026), (0.0, 0, 0.026), (0.072, 0, 0.026)], [0.024, 0.024, 0.024], mt)
    arm = [Vector(p) for p in ((-0.058, 0, 0.026), (-0.055, 0, 0.07), (-0.035, 0, 0.115), (0.0, 0, 0.135), (0.035, 0, 0.115), (0.055, 0, 0.07), (0.058, 0, 0.026))]
    CL.tube("arms", arm, [0.017] * len(arm), mt["w"], sides=20, v_scale=1.2, caps=True, flat=1.5)
    K.ball("grip_rivet", 0.01, (0.0, -0.028, 0.026), mt["st"], scale=(1, 0.55, 1), u=12, v=8)
    keys = [(0.11, 0.0, 0.026), (0.2, 0.0, 0.029), (0.4, 0.0, 0.030), (0.52, 0.0, 0.031)]
    sp = handle(keys, 30, mt, top=False, foot=False)
    # the socket: a tapering iron sleeve that runs on as a ridge down the middle of the blade
    # round 1: the ridge stood off the blade as a dark spike: flatter, lower, lying on the blade
    sock = [(0.0, 0.47, 0.036), (0.0, 0.52, 0.036), (0.0, 0.565, 0.03), (0.0, 0.63, 0.018), (0.0, 0.70, 0.007)]
    spts = [Vector((0, [0.0, 0.0, -0.002, -0.004, -0.002][i], z)) for i, (_x, z, _r) in enumerate(sock)]
    CL.tube("socket", spts, [r for (_x, _z, r) in sock], mt["ip"], sides=24, v_scale=2.0, caps=True, flat=0.45)
    K.ball("socket_rivet", 0.011, (0.0, -0.041, 0.505), mt["st"], scale=(1, 0.55, 1), u=14, v=8)
    blade = [(-0.092, 0.545), (0.092, 0.545), (0.098, 0.66), (0.085, 0.72), (0.05, 0.775), (0.0, 0.805),
             (-0.05, 0.775), (-0.085, 0.72), (-0.098, 0.66)]
    plate("blade", blade, 0.014, mt["ir"], cut=[1, 2, 3, 4, 5, 6, 7, 8], depth=0.05,  # round 2: the worn band was a third of the blade
          taper=0.5, dish=1.2, y=0.004)
    band_on("band", sp, 0.25, 0.30, red_cloth(), puff=0.003, u_rep=4.0)
    twine("twine", sp, 0.20, 0.25, mt["kc"], turns=4, r_cord=0.007)
    x, r = at(sp, 0.225)
    cloth_knot("twine_knot", Vector((x + r * 0.7, -(r * 0.75), 0.215)), mt["kc"], size=0.034)


# --- the scythe --------------------------------------------------------------------------------------

SCY_H = 0.84


def build_scythe():
    mt = mats()
    keys = [(0.0, 0.025, 0.034), (0.18, 0.012, 0.031), (0.42, -0.004, 0.029), (0.64, -0.006, 0.028), (SCY_H, 0.0, 0.028)]
    sp = handle(keys, 44, mt)
    for z, L in ((0.22, 0.12), (0.52, 0.11)):
        x, r = at(sp, z)
        rod("nib", [(x + r * 0.5, 0, z), (x + r + L * 0.5, 0, z + 0.004), (x + r + L, 0, z + 0.008)], [0.024, 0.024, 0.025], mt, ends=(False, True))
    twine("twine", sp, 0.05, 0.11, mt["kc"], turns=5, r_cord=0.007)
    band_on("wrap", sp, 0.60, 0.65, red_cloth(), puff=0.004, u_rep=4.0)
    zc0, zc1 = SCY_H - 0.09, SCY_H - 0.02
    collar("collar", sp, zc0, zc1, mt)
    # a long crescent swept out to the right: the back edge on top, the cutting edge underneath
    back = [(0.02, SCY_H - 0.02), (0.13, SCY_H - 0.008), (0.25, SCY_H - 0.025), (0.35, SCY_H - 0.07), (0.425, SCY_H - 0.14),
            (0.465, SCY_H - 0.23), (0.478, SCY_H - 0.30)]
    # round 1: a sliver; the reference's blade is as broad as the collar is tall, tapering to the tip
    edge = [(0.45, SCY_H - 0.215), (0.40, SCY_H - 0.16), (0.33, SCY_H - 0.13), (0.23, SCY_H - 0.118), (0.12, SCY_H - 0.118), (0.02, SCY_H - 0.11)]
    blade = back + edge
    plate("blade", blade, 0.012, mt["ir"], cut=list(range(len(back) - 1, len(blade) - 1)), depth=0.045, taper=0.35)


# --- the shears --------------------------------------------------------------------------------------

def build_shears():
    mt = mats()
    piv = Vector((0, 0, 0.25))  # round 1: longer handles, shorter broader blades
    open_ = math.radians(11)
    # each blade: (along, across) from the pivot, the cutting edge on its inner side (across < 0)
    shape = [(-0.03, -0.008), (-0.03, 0.03), (0.025, 0.04), (0.08, 0.036), (0.13, 0.02), (0.165, 0.0),
             (0.14, -0.005), (0.07, -0.008), (0.015, -0.01)]
    for side, y in ((-1, -0.0065), (1, 0.0065)):
        ang = side * open_
        d = Vector((math.sin(ang), 0, math.cos(ang)))
        a = Vector((math.cos(ang), 0, -math.sin(ang))) * side  # across, pointing away from the other blade
        out = [(piv + d * t + a * s) for t, s in shape]
        pts = [(p.x, p.z) for p in out]
        if side < 0:
            pts = pts[::-1]
        n = len(pts)
        cut = [n - 4, n - 3, n - 2] if side > 0 else [0, 1, 2]
        plate("blade", pts, 0.009, mt["ir"], cut=cut, depth=0.03, taper=0.45, y=y, bevel=0.0025)
        # the shank and handle on the other side of the pivot: iron, then a wooden grip in a red wrap
        hx = -side
        sh = [piv, piv + Vector((hx * 0.012, 0, -0.035)), piv + Vector((hx * 0.026, 0, -0.06))]
        CL.tube("shank", [p + Vector((0, y, 0)) for p in sh], [0.011, 0.012, 0.013], mt["ip"], sides=16, v_scale=2.0, caps=True, flat=0.7)
        g0 = piv + Vector((hx * 0.026, y, -0.06))
        g1 = Vector((hx * 0.062, y, 0.03))
        gpts = [g0.lerp(g1, t) for t in np.linspace(0, 1, 12)]
        grad = [0.017 + 0.003 * math.sin(math.pi * t) for t in np.linspace(0, 1, 12)]
        rod("grip", gpts, grad, mt, ends=(False, True), sides=20)
        K.ball("ferrule_rivet", 0.007, tuple(g0 + Vector((0, -0.017 + y * 0.0, 0.0))), mt["st"], scale=(1, 0.55, 1), u=10, v=6)
        wpts = [g0.lerp(g1, t) for t in np.linspace(0.18, 0.78, 10)]
        CL.tube("wrap", wpts, [0.021 + 0.002 * math.sin(math.pi * k / 9) ** 0.5 for k in range(10)], red_cloth(), sides=20, v_scale=12.0, u_rep=3.0, caps=True)
        # a running stitch down the front of the wrap
        for t in np.linspace(0.24, 0.72, 5):
            p = g0.lerp(g1, t)
            K.ball("stitch", 0.006, (p.x, p.y - 0.022, p.z), mt["kc"], scale=(0.45, 0.4, 1.0), u=8, v=6)
    # the pivot bolt, and the spring and ring between the handles
    K.cyl("pivot", 0.019, 0.017, 0.03, tuple(piv), mt["st"], verts=20, rot=(90, 0, 0), bevel=0.004)
    K.ball("pivot_cap", 0.013, (piv.x, -0.016, piv.z), mt["st"], scale=(1, 0.4, 1), u=14, v=8)
    coil = []
    for k in range(121):
        t = k / 120
        a = 2 * math.pi * 6 * t
        coil.append(Vector((-0.05 + 0.1 * t, 0.009 * math.cos(a), 0.1 + 0.009 * math.sin(a))))
    CL.tube("spring", coil, [0.0028] * len(coil), mt["ip"], sides=8, v_scale=20.0, caps=True)
    ring = [Vector((0.062 * math.cos(a), 0.0, 0.03 - 0.026 * math.sin(a))) for a in np.linspace(0.0, math.pi, 24)]
    CL.tube("ring", ring, [0.0065] * len(ring), mt["ip"], sides=12, v_scale=8.0, caps=True)


# --- the watering can --------------------------------------------------------------------------------

def build_watering_can():
    mt = mats()
    s = 1.15
    prof = [(0.0005, 0.0), (0.104, 0.0), (0.111, 0.006), (0.113, 0.02), (0.108, 0.034), (0.102, 0.04), (0.099, 0.06),
            (0.092, 0.17), (0.088, 0.186), (0.074, 0.2), (0.058, 0.206)]
    K.lathe("body", [(r * s, z * s) for r, z in prof], mt["ip"], steps=48, u_rep=2.0, sharp=50)
    lid = [(0.062, 0.204), (0.06, 0.214), (0.048, 0.226), (0.028, 0.234), (0.014, 0.236), (0.012, 0.242), (0.0005, 0.243)]
    K.lathe("lid", [(r * s, z * s) for r, z in lid], mt["ip"], steps=40, u_rep=1.0, sharp=50)
    K.ball("knob", 0.019 * s, (0, 0, 0.257 * s), mt["ip"], scale=(1, 1, 0.8), u=18, v=10)
    # the bail: an iron strap over the top from lug to lug, its middle bound in striped cloth
    lug = 0.088 * s
    bail = [Vector((lug * math.cos(a), 0, 0.15 * s + 0.17 * s * math.sin(a))) for a in np.linspace(0, math.pi, 40)]
    CL.tube("bail", bail, [0.0055] * len(bail), mt["ip"], sides=14, v_scale=4.0, caps=True, flat=2.4)
    for sgn in (-1, 1):
        K.ball("lug", 0.014 * s, (sgn * (lug + 0.006), 0, 0.15 * s), mt["st"], scale=(0.55, 1, 1), u=14, v=8)
    sleeve = [p for p in bail if abs(p.x) < 0.045 * s]
    sl = sum((b - a).length for a, b in zip(sleeve, sleeve[1:]))
    CL.tube("sleeve", sleeve, [0.0125] * len(sleeve), mt["bd"], sides=20, v_scale=1.0 / sl, u_rep=2.0, caps=True, flat=1.3)
    # the spout from low on the right, up and out, and its rose
    sp0, sp1 = Vector((0.07 * s, 0, 0.06 * s)), Vector((0.215 * s, 0, 0.2 * s))
    spts = [sp0.lerp(sp1, t) for t in np.linspace(0, 1, 16)]
    CL.tube("spout", spts, [float((0.03 - 0.013 * t) * s) for t in np.linspace(0, 1, 16)], mt["ip"], sides=24, v_scale=3.0, caps=True)
    axis = (sp1 - sp0).normalized()
    rose = K.lathe("rose", [(0.016, 0.0), (0.02, 0.012), (0.036, 0.034), (0.044, 0.042), (0.045, 0.048), (0.04, 0.052), (0.0005, 0.054)],
                   mt["ip"], steps=36, sharp=50)
    q = Vector((0, 0, 1)).rotation_difference(axis)
    base = sp1 - axis * 0.012
    rose.matrix_world = Matrix.Translation(base) @ q.to_matrix().to_4x4()
    face = base + axis * 0.054
    dark = once("tool_hole", lambda: K.plain("tool_hole", "#2a2626", rough=0.8))
    rq = q.to_matrix()
    for hx, hy in [(0, 0)] + [(0.024 * math.cos(a), 0.024 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 7)[:-1]]:
        h = K.cyl("hole", 0.0045, 0.0045, 0.004, (0, 0, 0), dark, verts=10)
        h.matrix_world = Matrix.Translation(face + rq @ Vector((hx, hy, 0.0))) @ q.to_matrix().to_4x4()
    # the felt flower and two leaves on the front, and a running stitch round the foot
    zf = 0.112 * s

    def on_body(x, z, out=0.0):
        r = (0.099 + (0.092 - 0.099) * (z / s - 0.06) / 0.11) * s
        return Vector((x, -math.sqrt(max(r * r - x * x, 0.0)) - out, z))
    white, yellow, green = felt("petal", "#f7f0e2"), felt("centre", "#f2b33a"), felt("leaf", "#86a043")
    for k in range(5):
        a = math.pi / 2 + 2 * math.pi * k / 5
        p = on_body(-0.012 + 0.02 * math.cos(a), zf + 0.02 * math.sin(a), 0.002)
        b = K.ball("petal", 0.0155, (0, 0, 0), white, scale=(1.0, 0.32, 0.78), u=16, v=8, boxy=0.9)
        b.matrix_world = Matrix.Translation(p) @ Matrix.Rotation(math.atan2(p.x, -p.y), 4, "Z") @ Matrix.Rotation(-a, 4, "Y")
    c = on_body(-0.012, zf, 0.005)
    K.ball("centre", 0.009, tuple(c), yellow, scale=(1, 0.5, 1), u=14, v=8)
    for sgn in (-1, 1):
        p = on_body(-0.012 + sgn * 0.03, zf - 0.04, 0.002)
        lf = K.ball("leaf", 0.017, (0, 0, 0), green, scale=(1.3, 0.3, 0.55), u=16, v=8, boxy=0.85)
        lf.matrix_world = Matrix.Translation(p) @ Matrix.Rotation(math.atan2(p.x, -p.y), 4, "Z") @ Matrix.Rotation(sgn * math.radians(-25), 4, "Y")
    for k in range(30):
        a = 2 * math.pi * k / 30
        r = 0.1035 * s
        st = K.ball("stitch", 0.0085, (0, 0, 0), mt["kc"], scale=(1.0, 0.3, 0.3), u=8, v=6)
        st.matrix_world = Matrix.Translation(Vector((r * math.cos(a), r * math.sin(a), 0.05 * s))) @ Matrix.Rotation(a + math.pi / 2, 4, "Z")


KINDS = {"axe": (build_axe, 9000), "hoe": (build_hoe, 9000), "shovel": (build_shovel, 12000), "scythe": (build_scythe, 10000),
         "shears": (build_shears, 14000), "watering_can": (build_watering_can, 16000)}


def build(name):
    K.reset(name)
    fn, budget = KINDS[name]
    fn()
    out = os.path.join(HERE, "out", name)
    ob = K.finish(name, out, max_tris=budget)
    print("SCENE", [o.name for o in bpy.context.scene.objects], "size", [round(d, 3) for d in ob.dimensions])
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for a in (KINDS if args[0] == "all" else args):
    build(a)
