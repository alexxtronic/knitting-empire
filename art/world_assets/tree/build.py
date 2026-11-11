"""The big green maple tree after Alex's reference: flared, lobed roots, a thick bark trunk, boughs, and a
canopy of tiered leafy clumps painted with overlapping maple leaves and studded with real maple-leaf cards
that break up the silhouette. About 5.3 m tall, 5 m across at scale 1. Textures come from make_tex.py.

    uv run --no-project --with numpy --with pillow python art/world_assets/tree/make_tex.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/tree/build.py
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, Quaternion
from mathutils import noise as mnoise
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import natlib as N  # noqa: E402

NAME = "tree"
TEX = os.path.join(HERE, "tex")
K.reset(NAME)
rng = np.random.default_rng(21)


def load(fn, srgb=True):
    im = bpy.data.images.load(os.path.join(TEX, fn))
    if not srgb:
        im.colorspace_settings.name = "Non-Color"
    im.pack()
    return im


canopy = K.textured("canopy_mat", load("canopy_albedo.png"), rough=0.7, normal=load("canopy_normal.png"), normal_strength=1.0)
bark = K.textured("bark_mat", load("bark_albedo.png"), rough=0.9, normal=load("bark_normal.png"), normal_strength=1.2)
for m in (canopy, bark):
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.25
# leaf cards use the green leaf's own painted maps
shape = N.Shape("leaf_green", 0.46)
la, ln = N.leaf_maps("tree_card", TEX, shape, seed=5, n=512, gamma=0.95, gain=1.3)
card_mat = K.textured("card_mat", la, rough=0.6, normal=ln, normal_strength=1.0)
card_mat.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.25


def box_uv(bm, tile):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        nx, ny, nz = abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)
        for l in f.loops:
            p = l.vert.co
            l[uv].uv = (p.x / tile, p.y / tile) if nz >= nx and nz >= ny else ((p.y / tile, p.z / tile) if nx >= ny else (p.x / tile, p.z / tile))


# --- trunk: lobed roots flaring out of a tapering, slightly leaning trunk -----------------------
ZS = [0.0, 0.06, 0.15, 0.28, 0.45, 0.7, 1.0, 1.4, 1.85, 2.4, 3.0, 3.5]
SIDES = 32
bm = bmesh.new()
rings = []
for zi, z in enumerate(ZS):
    r0 = 0.36 + 0.55 * math.exp(-z / 0.42) - 0.02 * z
    amp = 0.55 * math.exp(-z / 0.5)
    ring = []
    for s in range(SIDES):
        t = 2 * math.pi * s / SIDES
        lobe = max(0.0, math.cos(2.5 * (t - 0.4))) ** 1.4
        wob = 0.05 * mnoise.noise(Vector((math.cos(t) * 1.3, math.sin(t) * 1.3, z * 0.8)))
        r = r0 * (1 + amp * lobe + wob)
        ring.append(bm.verts.new((math.cos(t) * r + 0.06 * z * 0.3, math.sin(t) * r, z)))
    rings.append(ring)
for zi in range(len(ZS) - 1):
    for s in range(SIDES):
        s2 = (s + 1) % SIDES
        bm.faces.new((rings[zi][s], rings[zi][s2], rings[zi + 1][s2], rings[zi + 1][s]))
bm.faces.new(list(reversed(rings[-1])))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
uv = bm.loops.layers.uv.verify()
for f in bm.faces:
    for l in f.loops:
        ang = math.atan2(l.vert.co.y, l.vert.co.x)
        l[uv].uv = (ang / (2 * math.pi) * 4.0 % 4.0, l.vert.co.z / 1.3)
me = bpy.data.meshes.new("trunk")
bm.to_mesh(me)
bm.free()
ob = K._obj("trunk", me, bark)
me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
# seam fix: the u wrap makes one column of faces span 0..4; push those corners to 4
uvd = me.uv_layers[0].data
for poly in me.polygons:
    us = [uvd[li].uv[0] for li in poly.loop_indices]
    if max(us) - min(us) > 2:
        for li in poly.loop_indices:
            d = uvd[li]
            if d.uv[0] < 2:
                d.uv = (d.uv[0] + 4.0, d.uv[1])

# --- canopy: tiered pads of leaves (a wide skirt, a middle tier, a crown) on visible boughs -----------
pads = []  # x, y, z, radius
def ring(count, rad, z, r, off=0.0):
    for i in range(count):
        a = off + 2 * math.pi * i / count + rng.uniform(-0.12, 0.12)
        pads.append((math.cos(a) * rad * rng.uniform(0.9, 1.1), math.sin(a) * rad * rng.uniform(0.9, 1.1), z + rng.uniform(-0.12, 0.12), r * rng.uniform(0.9, 1.1)))
ring(7, 2.05, 3.55, 1.2)
ring(5, 1.25, 4.45, 1.1, 0.4)
ring(3, 0.55, 5.25, 1.0, 0.9)
pads.append((0.0, 0.0, 5.75, 0.95))

# boughs from the trunk top out under each lower pad
for (x, y, z, r) in pads[:12]:
    d = math.hypot(x, y)
    pts = [(0.05, 0, 3.0), (x * 0.35, y * 0.35, 3.15 + (z - 3.2) * 0.3), (x * 0.7, y * 0.7, z - 0.25), (x * 0.95, y * 0.95, z - 0.1)]
    N.tube("bough", pts, [0.2, 0.15, 0.1, 0.07], bark, sides=8)

blobs = []
for (x, y, z, r) in pads:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=7, radius=1.0)
    ph = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    for v in bm.verts:
        d = 1.0 + 0.1 * mnoise.noise(v.co * 2.0 + ph)
        v.co = Vector((v.co.x * r * d, v.co.y * r * d, v.co.z * r * 0.48 * d))
    bm.normal_update()
    box_uv(bm, 2.2)
    me = bpy.data.meshes.new("pad")
    bm.to_mesh(me)
    bm.free()
    o = K._obj("pad", me, canopy)
    o.location = (x, y, z)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    blobs.append((o, Vector((x, y, z)), r))
bpy.context.view_layer.update()


def card(pos, normal, spin, mat, scale):
    n = 12
    verts = [(0, 0.0, 0.03 * scale)]
    for i in range(n):
        th = 2 * math.pi * i / n
        R = float(shape.r(th)) * scale
        verts.append((math.sin(th) * R, math.cos(th) * R, 0.0))
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    me = bpy.data.meshes.new("card")
    me.from_pydata(verts, [], faces)
    uv = me.uv_layers.new(name="UVMap")
    half = shape.reach * 1.02 * scale
    for li, loop in enumerate(me.loops):
        x, y, _ = verts[loop.vertex_index]
        uv.data[li].uv = (0.5 + x / (2 * half), 0.5 + y / (2 * half))
    ob = K._obj("card", me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(normal) @ Quaternion((0, 0, 1), spin)
    ob.location = pos
    return ob


for (o, c, r) in blobs:
    bmx = bmesh.new()
    bmx.from_mesh(o.data)
    bmx.transform(o.matrix_world)
    tree = BVHTree.FromBMesh(bmx)
    bmx.free()
    made, tries = 0, 0
    want = 11
    while made < want and tries < 300:
        tries += 1
        th = rng.uniform(0, 2 * math.pi)
        el = rng.uniform(-0.15, 0.9) if made < 7 else rng.uniform(0.55, 1.4)  # most on the rim and top edge, some on top
        d = Vector((math.cos(th) * math.cos(el), math.sin(th) * math.cos(el), math.sin(el)))
        hit = tree.ray_cast(c + d * (r * 2.0), -d)
        if hit[0] is None:
            continue
        p, n = hit[0], hit[1].normalized()
        n = (n + Vector((0, 0, 0.25))).normalized()
        card(p + n * 0.04, n, rng.uniform(0, 6.28), card_mat, rng.uniform(0.95, 1.15))
        made += 1

K.finish(NAME, os.path.join(HERE, "out"), max_tris=9500)
