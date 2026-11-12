"""Ground cover and planting for the map: grass tufts, three flower patches plus poppies, clover, four
bushes and a hedge segment. Every surface is textured (painted blades, leaves and petals from make_tex.py,
with normal maps). Models stand on z = 0, centred, front toward -Y.

    uv run --no-project --with numpy --with pillow python art/world_assets/flora/make_tex.py
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/flora/build.py [-- name ...]
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils import noise as mnoise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import natlib as N  # noqa: E402

TEX = os.path.join(HERE, "tex")


def img(fn, srgb=True):
    im = bpy.data.images.load(os.path.join(TEX, fn))
    if not srgb:
        im.colorspace_settings.name = "Non-Color"
    im.pack()
    return im


def tmat(name, albedo, normal=None, rough=0.7, spec=0.25, ns=1.0):
    m = K.textured(name, img(albedo + ".png"), rough=rough, normal=img(normal + ".png", False) if normal else None, normal_strength=ns)
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = spec
    m.use_backface_culling = False
    return m


def mesh_from(name, verts, faces, uvs, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    ob = K._obj(name, me, mat)
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob


class Strips:
    """Collects ribbons (blades, petals, leaves) into one mesh."""

    def __init__(self):
        self.v, self.f, self.uv = [], [], []

    def ribbon(self, pts, widths, side, uv_u=(0.0, 1.0)):
        base = len(self.v)
        n = len(pts)
        for i, (p, w) in enumerate(zip(pts, widths)):
            p = Vector(p)
            self.v += [p + side * w, p - side * w]
            self.uv += [(uv_u[1], i / (n - 1)), (uv_u[0], i / (n - 1))]
        for i in range(n - 1):
            a = base + 2 * i
            self.f.append((a, a + 1, a + 3, a + 2))

    def blade(self, root, ang, lean, h, w, segs=4):
        d = Vector((math.cos(ang), math.sin(ang), 0))
        side = Vector((-d.y, d.x, 0))
        pts, ws = [], []
        for s in range(segs):
            f = s / (segs - 1)
            pts.append(Vector(root) + d * lean * h * f * f + Vector((0, 0, h * f * (1 - 0.1 * f))))
            ws.append(w * (math.sin(math.pi * min(f * 0.8 + 0.18, 1.0)) * 0.9 + 0.1) * (1 - 0.6 * f))
        self.ribbon(pts, ws, side)


def tuft(name, rng, blades, height, spread, wscale=1.0):
    S = Strips()
    for _ in range(blades):
        a = rng.uniform(0, 2 * math.pi)
        r0 = spread * math.sqrt(rng.random())
        S.blade((math.cos(a) * r0, math.sin(a) * r0, 0), a + rng.uniform(-0.5, 0.5), rng.uniform(0.15, 0.7), height * rng.uniform(0.6, 1.25), spread * 0.28 * wscale * rng.uniform(0.8, 1.3))
    return S


def grass_mat():
    return tmat("blade_mat", "blade", "blade_n", rough=0.55, spec=0.3)


def build_tufts():
    for name, blades, h, sp, seed in (("tuft_small", 8, 0.2, 0.08, 1), ("tuft_mid", 14, 0.32, 0.13, 2), ("tuft_tall", 20, 0.5, 0.18, 3)):
        K.reset(name)
        rng = np.random.default_rng(seed)
        S = tuft(name, rng, blades, h, sp)
        mesh_from(name, S.v, S.f, S.uv, grass_mat())
        K.finish(name, os.path.join(HERE, "out"), max_tris=1200)


def petal_head(S_by_mat, center, tilt_dir, facing, petals, length, width, cup, mat_key):
    """A flower head: petals radiating from the centre, each a tapered ribbon cupped upwards."""
    S = S_by_mat[mat_key]
    up = Vector(facing).normalized()
    t1 = up.cross(Vector((0, 0, 1)) if abs(up.z) < 0.95 else Vector((1, 0, 0))).normalized()
    t2 = up.cross(t1).normalized()
    for i in range(petals):
        a = 2 * math.pi * i / petals
        d = t1 * math.cos(a) + t2 * math.sin(a)
        side = up.cross(d).normalized()
        pts = [Vector(center) + d * length * f + up * cup * f * f * length for f in (0.08, 0.35, 0.7, 1.0)]
        widths = [width * 0.3, width * 0.5, width * 0.5, width * 0.12]
        S.ribbon(pts, widths, side)


def flower_patch(name, seed, kind, count=7, radius=0.42):
    K.reset(name)
    rng = np.random.default_rng(seed)
    petal = {"daisy": "petal_white", "buttercup": "petal_yellow", "wild": "petal_purple", "poppy": "petal_red"}[kind]
    petals_by = {"petal_white": Strips(), "petal_yellow": Strips(), "petal_purple": Strips(), "petal_pink": Strips(), "petal_red": Strips()}
    stems = Strips()
    blades = tuft(name, rng, 22, 0.28, radius * 0.9, wscale=0.3)
    centers = []
    for k in range(count):
        a = rng.uniform(0, 2 * math.pi)
        r0 = radius * math.sqrt(rng.random())
        x, y = math.cos(a) * r0, math.sin(a) * r0
        h = rng.uniform(0.26, 0.5)
        lean = rng.uniform(0.0, 0.12)
        top = Vector((x + math.cos(a) * lean, y + math.sin(a) * lean, h))
        # stem: a thin tube-like ribbon from two sides (crossed ribbons read as a round stem)
        for off in (0.0, math.pi / 2):
            d = Vector((math.cos(off), math.sin(off), 0))
            stems.ribbon([Vector((x, y, 0)), Vector((x, y, 0)) + (top - Vector((x, y, 0))) * 0.5, top], [0.005, 0.0045, 0.004], d)
        face = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1.0))
        key = petal
        if kind == "wild" and k % 3 == 0:
            key = "petal_pink"
        if kind == "daisy":
            petal_head(petals_by, top, None, face, 10, 0.085, 0.032, 0.25, key)
        elif kind == "buttercup":
            petal_head(petals_by, top, None, face, 5, 0.06, 0.05, 0.5, key)
        elif kind == "poppy":
            petal_head(petals_by, top, None, face, 5, 0.085, 0.075, 0.7, key)
        else:
            petal_head(petals_by, top, None, face, 12, 0.07, 0.024, 0.15, key)
        centers.append((top, face))
    mesh_from("blades", blades.v, blades.f, blades.uv, grass_mat())
    stem_mat = tmat("stem_mat", "blade", "blade_n", rough=0.6)
    mesh_from("stems", stems.v, stems.f, stems.uv, stem_mat)
    for key, S in petals_by.items():
        if S.v:
            mesh_from("petals_" + key, S.v, S.f, S.uv, tmat(key + "_mat", key, None, rough=0.55, spec=0.3))
    centre_col = {"daisy": "#f0b81c", "buttercup": "#c98a14", "wild": "#f2d24a", "poppy": "#2a1810"}[kind]
    cm = K.plain(name + "_centre", centre_col, 0.6)
    for top, face in centers:
        K.ball("centre", 0.016 if kind != "poppy" else 0.022, top + face.normalized() * 0.006, cm, u=8, v=5)
    K.finish(name, os.path.join(HERE, "out"), max_tris=1800)


def build_clover():
    name = "clover_patch"
    K.reset(name)
    rng = np.random.default_rng(9)
    cmat = tmat("clover_mat", "clover", "clover_n", rough=0.6)
    v, f, uv = [], [], []
    for k in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r0 = 0.45 * math.sqrt(rng.random())
        cx, cy = math.cos(a) * r0, math.sin(a) * r0
        h = rng.uniform(0.03, 0.07)
        spin = rng.uniform(0, 2 * math.pi)
        for leaflet in range(3):
            la = spin + leaflet * 2 * math.pi / 3
            R = rng.uniform(0.05, 0.075)
            ctr = Vector((cx + math.cos(la) * R * 0.9, cy + math.sin(la) * R * 0.9, h + 0.01))
            base = len(v)
            v.append(ctr + Vector((0, 0, 0.012)))
            uv.append((0.5, 0.5))
            for s in range(8):
                t = 2 * math.pi * s / 8
                p = ctr + Vector((math.cos(t) * R, math.sin(t) * R, -0.012))
                v.append(p)
                uv.append((0.5 + 0.5 * math.cos(t - la), 0.5 + 0.5 * math.sin(t - la)))
            for s in range(8):
                f.append((base, base + 1 + s, base + 1 + (s + 1) % 8))
    mesh_from(name, v, f, uv, cmat)
    wm = K.plain("clover_flower", "#f4efe4", 0.7)
    for k in range(4):
        a = rng.uniform(0, 2 * math.pi)
        r0 = 0.4 * math.sqrt(rng.random())
        K.ball("head", 0.03, (math.cos(a) * r0, math.sin(a) * r0, 0.11), wm, scale=(1, 1, 0.85), u=8, v=5)
    K.finish(name, os.path.join(HERE, "out"), max_tris=1500)


def box_uv(ob, tile):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        nx, ny, nz = abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)
        for l in f.loops:
            p = l.vert.co
            l[uv].uv = (p.x / tile, p.y / tile) if nz >= nx and nz >= ny else ((p.y / tile, p.z / tile) if nx >= ny else (p.x / tile, p.z / tile))
    bm.to_mesh(ob.data)
    bm.free()


def blob(name, radii, loc, mat, rng, noise=0.12, tile=0.9, u=12, v=8, flat=0.0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    ph = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    for vt in bm.verts:
        d = 1.0 + noise * mnoise.noise(vt.co * 2.0 + ph)
        z = vt.co.z * radii[2] * d
        if flat and z < -flat:
            z = -flat
        vt.co = Vector((vt.co.x * radii[0] * d, vt.co.y * radii[1] * d, z))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat)
    ob.location = loc
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    bpy.context.view_layer.update()
    # bake the location into the mesh for UVs, then project
    me.transform(ob.matrix_basis)
    ob.location = (0, 0, 0)
    box_uv(ob, tile)
    return ob


def amat(name, png):
    """A cut-out leaf-card material: the cluster picture's alpha is scissored, both sides drawn."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img(png)
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    clip = nt.nodes.new("ShaderNodeMath")  # an alpha cut-off: the glTF exporter turns this into alphaMode MASK
    clip.operation = "GREATER_THAN"
    clip.inputs[1].default_value = 0.5
    nt.links.new(t.outputs["Alpha"], clip.inputs[0])
    nt.links.new(clip.outputs[0], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.8
    b.inputs["Specular IOR Level"].default_value = 0.2
    m.surface_render_method = "DITHERED"
    m.use_backface_culling = False
    return m


def cards_on(blobs, mat, rng, per, size, lift=0.03, elev=(-0.1, 1.55), ydir=None):
    """Maple-leaf cards lying on the outside of each blob, like the leaf cards on the map trees."""
    from mathutils import Quaternion
    from mathutils.bvhtree import BVHTree
    for ob in blobs:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        tree = BVHTree.FromBMesh(bm)
        zs = [v.co.z for v in bm.verts]
        xs = [v.co.x for v in bm.verts]
        ys = [v.co.y for v in bm.verts]
        c = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))
        R = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        bm.free()
        made, tries = 0, 0
        while made < per and tries < per * 12:
            tries += 1
            th = rng.uniform(0, 2 * math.pi)
            el = rng.uniform(*elev)
            d = Vector((math.cos(th) * math.cos(el), math.sin(th) * math.cos(el), math.sin(el)))
            hit = tree.ray_cast(c + d * R * 2.0, -d)
            if hit[0] is None:
                continue
            p, n = hit[0], hit[1].normalized()
            n = (n + Vector((0, 0, 0.3))).normalized()
            s = size * rng.uniform(0.85, 1.2)
            v = [(-s / 2, -s / 2, 0), (s / 2, -s / 2, 0), (s / 2, s / 2, 0), (-s / 2, s / 2, 0)]
            me = bpy.data.meshes.new("card")
            me.from_pydata(v, [], [(0, 1, 2, 3)])
            uv = me.uv_layers.new(name="UVMap")
            for li, (u_, v_) in zip(me.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
                uv.data[li].uv = (u_, v_)
            co = K._obj("card", me, mat)
            co.rotation_mode = "QUATERNION"
            co.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(n) @ Quaternion((0, 0, 1), rng.uniform(0, 6.28))
            co.location = p + n * lift
            made += 1


def build_bush(name, tex, normal, blobs, seed, berries=0, tile=0.9, cluster="cluster_green", cards=36, size=0.5):
    K.reset(name)
    rng = np.random.default_rng(seed)
    mat = tmat(name + "_mat", tex, normal, rough=0.7, spec=0.25)
    made = []
    for (x, y, z, rx, ry, rz) in blobs:
        made.append(blob("blob", (rx, ry, rz), (x, y, z), mat, rng, tile=tile))
    cards_on(made, amat(name + "_leaves", cluster + ".png"), rng, cards, size)
    if berries:
        bm = K.plain(name + "_berry", "#85262e", 0.5)
        for _ in range(berries):
            a = rng.uniform(0, 2 * math.pi)
            el = rng.uniform(0.1, 1.2)
            b = blobs[int(rng.integers(0, len(blobs)))]
            p = Vector((b[0] + math.cos(a) * math.cos(el) * b[3] * 1.0, b[1] + math.sin(a) * math.cos(el) * b[4] * 1.0, b[2] + math.sin(el) * b[5]))
            K.ball("berry", 0.022, p, bm, u=6, v=4)
    K.finish(name, os.path.join(HERE, "out"), max_tris=4500)


def build_hedge():
    name = "hedge"
    K.reset(name)
    rng = np.random.default_rng(31)
    mat = tmat("hedge_mat", "hedge_leaf", "hedge_leaf_n", rough=0.75, spec=0.2)
    # a long, rounded, clipped hedge, 2 m x 0.8 m x 1.0 m: a chain of squashed blobs along X
    segs = []
    for i in range(7):
        x = -0.7 + i * 0.233
        segs.append(blob("seg", (0.4, 0.4, 0.52), (x, 0, 0.5), mat, rng, noise=0.07, tile=0.8, u=10, v=7, flat=0.5))
    for i in range(6):
        x = -0.62 + i * 0.25
        segs.append(blob("top", (0.26, 0.28, 0.2), (x, rng.uniform(-0.08, 0.08), 0.9), mat, rng, noise=0.1, tile=0.8, u=8, v=5))
    cards_on(segs, amat("hedge_leaves", "cluster_dark.png"), rng, 8, 0.42, elev=(0.05, 1.5))
    K.finish(name, os.path.join(HERE, "out"), max_tris=4500)


ALL = ["tuft", "daisy", "buttercup", "wild", "poppy", "clover", "bush_round", "bush_tall", "bush_berry", "bush_autumn", "hedge"]
which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ALL
for w in which:
    if w == "tuft":
        build_tufts()
    elif w in ("daisy", "buttercup", "wild", "poppy"):
        flower_patch("flowers_" + w, {"daisy": 4, "buttercup": 5, "wild": 6, "poppy": 7}[w], w)
    elif w == "clover":
        build_clover()
    elif w == "bush_round":
        build_bush("bush_round", "bush_leaf", "bush_leaf_n", [(0, 0, 0.36, 0.55, 0.5, 0.42), (0.38, 0.1, 0.3, 0.38, 0.36, 0.32), (-0.34, -0.1, 0.3, 0.36, 0.34, 0.3)], 11)
    elif w == "bush_tall":
        build_bush("bush_tall", "bush_leaf", "bush_leaf_n", [(0, 0, 0.45, 0.45, 0.42, 0.5), (0.05, 0, 0.95, 0.36, 0.34, 0.42), (-0.1, 0.05, 1.28, 0.2, 0.2, 0.22)], 12)
    elif w == "bush_berry":
        build_bush("bush_berry", "berry_leaf", "berry_leaf_n", [(0, 0, 0.34, 0.5, 0.46, 0.38), (0.32, 0.08, 0.28, 0.34, 0.32, 0.28), (-0.3, -0.06, 0.3, 0.34, 0.32, 0.3)], 13, berries=34)
    elif w == "bush_autumn":
        build_bush("bush_autumn", "autumn_leaf", "bush_leaf_n", [(0, 0, 0.36, 0.55, 0.5, 0.42), (0.38, 0.1, 0.3, 0.38, 0.36, 0.32), (-0.34, -0.1, 0.3, 0.36, 0.34, 0.3)], 14, cluster="cluster_autumn")
    elif w == "hedge":
        build_hedge()
