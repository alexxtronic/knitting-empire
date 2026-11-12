"""Nora's hand tools, after the reference sheet beside this file (reference_sheet.png): chunky,
toy-like, honey wood and dark iron, a strip of cloth or twine on each handle.

    axe    a short hatchet: curved handle with a rounded foot, a wedge head with a worn edge and a
           rivet on each cheek, a striped cloth band tied with a twine bow

Each tool stands upright: the handle along +Z from the origin (the centre of its foot), the
working end at the top, the blade toward +X. The game holds it by the grip, GRIP metres up.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/tools/build.py -- axe
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Vector

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


def iron_maps(name, n=512, seed=5):
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
    edge = np.clip((u - ragged) / 0.035, 0, 1)
    rgb = CL.mix(rgb, CL.C("#cbbcab") * (0.9 + 0.2 * fine[..., None]), edge[..., None])
    rim = np.clip(1 - np.minimum(v, 1 - v) / 0.06, 0, 1) * np.clip((fine - 0.25) * 3, 0, 1) * np.clip(u * 2.2, 0, 1)
    rgb = CL.mix(rgb, CL.C("#b9ada2"), (rim * 0.85)[..., None])
    hgt = 0.5 * mott + 0.2 * fine - 0.6 * edge
    rough = np.clip(0.66 - 0.08 * edge + 0.15 * rust, 0, 1)  # round 4: the edge was chrome-bright
    return (K.save_image(name, rgb, TEX), K.save_image(name + "_n", K.normal_from_height(hgt, 1.2), TEX),
            K.save_image(name + "_r", np.repeat(rough[..., None], 3, axis=2), TEX))


def iron():
    i, n, r = iron_maps("tool_iron")
    m = K.textured("tool_iron", i, rough=0.6, normal=n, normal_strength=0.7)
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


KINDS = {"axe": (build_axe, 9000)}


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
