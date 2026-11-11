"""Shared helpers for the nature assets (maple leaves, rocks, the maple tree): a parametric maple-leaf
outline and vein heightfield used by both the leaf mesh and its baked texture, grass tufts, and
moss cushions. Needs kelib.py (same folder)."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import kelib as K

# --- maple leaf shape ------------------------------------------------------------------------------
# The outline of each leaf is traced from Alex's reference render (leaf_shapes.json, made by tracing the
# silhouette radius from the vein hub every degree, angle measured from +Y towards +X).
import json
import os

_SHAPES = None


class Shape:
    def __init__(self, name, width_m=0.30):
        global _SHAPES
        if _SHAPES is None:
            with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "leaf_shapes.json")) as f:
                _SHAPES = json.load(f)
        d = _SHAPES[name]
        mpp = width_m / d["width_px"]
        self.reach = d["reach_px"] * mpp
        self.radii = np.array(d["radii"] + d["radii"][:1])
        self.tips = [(math.radians(a), r) for a, r in d["tips"]]
        self.colors = {k: tuple(v) for k, v in d["colors"].items()}
        self.vein_hub = 0.10 * self.reach  # the veins meet a little above the outline's hub
        a = np.radians(np.arange(0, 360, 2))
        rr = self.r(a)
        self.edge_pts = np.stack([np.sin(a) * rr, np.cos(a) * rr], 1)

    def edge_dist(self, x, y):
        """Distance (m) from each point to the leaf's outline (points are assumed inside it)."""
        dmin = np.full(np.shape(x), 9.0)
        for px, py in self.edge_pts:
            dmin = np.minimum(dmin, np.hypot(x - px, y - py))
        return dmin

    def r(self, theta):
        """Outline radius (m) at angle(s) theta, radians from +Y."""
        deg = np.degrees(np.asarray(theta)) % 360.0
        return np.interp(deg, np.arange(361), self.radii) * self.reach

    def height(self, x, y, thick=1.0):
        """Surface height (m) at points (x, y) metres from the outline hub: a soft thick dome with a rounded
        rim, and raised veins (a midrib, a primary vein to every lobe, side veins off each)."""
        e = np.clip(self.edge_dist(x, y) / 0.05, 0, 1)
        smooth = e * e * (3 - 2 * e)
        dome = 0.004 + 0.010 * np.sqrt(np.clip(1 - (1 - e) ** 2, 0, 1)) + 0.014 * smooth
        ridge = np.zeros_like(x)
        reach = self.reach

        def seg(ax, ay, bx, by, w, h):
            px, py = x - ax, y - ay
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy
            s = np.clip((px * vx + py * vy) / L2, 0, 1)
            d = np.hypot(px - s * vx, py - s * vy)
            fade = np.clip((np.hypot(x, y - hy) - 0.015) / 0.05, 0, 1)  # keep the hub itself smooth
            return h * (1.0 - 0.6 * s) * np.exp(-(d / w) ** 2) * fade

        hy = self.vein_hub
        for a, r in self.tips:
            tx, ty = math.sin(a) * r * reach * 0.86, math.cos(a) * r * reach * 0.86 + 0.0
            main = r > 0.95
            ridge = np.maximum(ridge, seg(0, hy, tx, ty, 0.0062 if main else 0.0048, 0.0060 if main else 0.0042))
            L = math.hypot(tx, ty - hy)
            ux, uy = tx / max(math.hypot(tx, ty - hy), 1e-6), (ty - hy) / max(math.hypot(tx, ty - hy), 1e-6)
            for f in (0.38, 0.62) if r > 0.7 else (0.5,):
                for sg in (-1, 1):
                    ang = math.radians(48) * sg
                    dx = ux * math.cos(ang) - uy * math.sin(ang)
                    dy = ux * math.sin(ang) + uy * math.cos(ang)
                    sx, sy = tx * f, hy + (ty - hy) * f
                    ln = L * (0.34 if r > 0.7 else 0.26)
                    ridge = np.maximum(ridge, seg(sx, sy, sx + dx * ln, sy + dy * ln, 0.0038, 0.0016))
        return dome + ridge * thick * (0.25 + 0.75 * smooth)  # veins fade out before the rim so the edge stays a clean rounded slab


def leaf_mesh(name, shape, mat, n=96, rings=9):
    """Domed maple leaf whose outline is the traced one; origin at its outline hub."""
    reach = shape.reach
    verts, faces = [], []
    idx = {}
    for k in range(rings + 1):
        f = (k / rings) ** 0.75
        for i in range(n):
            th = 2 * math.pi * i / n
            R = float(shape.r(th))
            idx[(k, i)] = len(verts)
            verts.append([math.sin(th) * R * f, math.cos(th) * R * f, 0.0])
    base0 = len(verts)
    for i in range(n):
        v = verts[idx[(rings, i)]]
        verts.append([v[0] * 0.95, v[1] * 0.95, 0.0])
    xs = np.array([v[0] for v in verts])
    ys = np.array([v[1] for v in verts])
    z = shape.height(xs, ys)
    for j, v in enumerate(verts):
        v[2] = float(z[j])
    for i in range(n):
        verts[base0 + i][2] = 0.001
    for k in range(rings):
        for i in range(n):
            j = (i + 1) % n
            a, b, c, d = idx[(k, i)], idx[(k, j)], idx[(k + 1, j)], idx[(k + 1, i)]
            faces.append((a, d, c, b) if k else (a, d, c))
    for i in range(n):
        j = (i + 1) % n
        faces.append((idx[(rings, i)], base0 + i, base0 + j, idx[(rings, j)]))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new(name="UVMap")
    half = reach * 1.02
    for li, loop in enumerate(me.loops):
        x, y, _ = verts[loop.vertex_index]
        uv.data[li].uv = (0.5 + x / (2 * half), 0.5 + y / (2 * half))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob


def _sat(c, k):
    m = c.mean(axis=-1, keepdims=True)
    return m + (c - m) * k


def leaf_maps(name, folder, shape, seed=0, n=768, normal_strength=3.0, gamma=1.25, gain=0.82, sat=1.0):
    """Albedo + normal map for a leaf: colours sampled from the reference render, lighter veins, darker rim,
    a fine fuzzy speckle like the reference's clay surface."""
    half = shape.reach * 1.02
    xs = (np.arange(n) + 0.5) / n * 2 - 1
    X, Y = np.meshgrid(xs * half, xs * half)
    Y = Y[::-1]
    H = shape.height(X, Y)
    H0 = shape.height(X, Y, 0.0)
    th = np.arctan2(X, Y)
    t = np.clip(1.0 - shape.edge_dist(X, Y) / 0.05, 0, 1.3) * 0.0 + np.clip(np.hypot(X, Y) / np.maximum(shape.r(th), 1e-4), 0, 1.3)
    base, light, dark = (np.array(shape.colors[k]) for k in ("base", "light", "dark"))
    veinmask = np.clip((H - H0) / 0.0030, 0, 1)[..., None]
    rim = np.clip((t - 0.72) / 0.28, 0, 1)[..., None]
    noise = K.tile_noise(n, 1.1, seed + 1)
    mid = K.tile_noise(n, 0.8, seed + 3)
    fine = K.tile_noise(n, 0.35, seed + 2)
    col = base * (0.93 + 0.14 * noise[..., None]) + (light - base) * 0.35 * mid[..., None]
    col = col * (1 - 0.8 * rim) + dark * 0.8 * rim * (0.95 + 0.1 * fine[..., None])
    col = col * (1 - 0.6 * veinmask) + light * 0.6 * veinmask
    col = np.clip(_sat(((col * (0.96 + 0.08 * fine[..., None])) ** gamma) * gain, sat), 0, 1)
    albedo = K.save_image(name + "_albedo", col, folder)
    rimfade = np.clip((t - 0.86) / 0.12, 0, 1)
    bump = (H / H.max() + (fine - 0.5) * 0.02 + (noise - 0.5) * 0.012) * (1 - rimfade) + 0.25 * rimfade
    nrm = K.save_image(name + "_normal", K.normal_from_height(bump, normal_strength * 3.0), folder)
    return albedo, nrm


def tube(name, pts, radii, mat, sides=10):
    """A smooth tube along the polyline pts with a radius per point, closed with rounded ends."""
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        a = d.cross(up).normalized()
        b = d.cross(a).normalized()
        for s in range(sides):
            t = 2 * math.pi * s / sides
            verts.append(p + (a * math.cos(t) + b * math.sin(t)) * radii[i])
    for i in range(len(pts) - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            faces.append((i * sides + s, i * sides + s2, (i + 1) * sides + s2, (i + 1) * sides + s))
    c0, c1 = len(verts), len(verts) + 1
    d0 = (pts[0] - pts[1]).normalized()
    d1 = (pts[-1] - pts[-2]).normalized()
    verts += [pts[0] + d0 * radii[0] * 0.8, pts[-1] + d1 * radii[-1] * 0.8]
    for s in range(sides):
        s2 = (s + 1) % sides
        faces.append((c0, s2, s))
        last = (len(pts) - 1) * sides
        faces.append((c1, last + s, last + s2))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob


# --- surface helpers ---------------------------------------------------------------------------------

def bvh_of(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(ob.matrix_world)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def tuft(name, base, mat, rng, blades=7, height=0.2, spread=0.09):
    """A little clump of curved tapered grass blades standing at `base`."""
    verts, faces = [], []
    for _ in range(blades):
        a = rng.uniform(0, 2 * math.pi)
        lean = rng.uniform(0.15, 0.55)
        h = height * rng.uniform(0.6, 1.2)
        w = spread * 0.5 * rng.uniform(0.8, 1.2)
        ox, oy = math.cos(a) * rng.uniform(0, spread), math.sin(a) * rng.uniform(0, spread)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        prev = None
        for s in range(4):
            f = s / 3.0
            cx = ox + dx * lean * h * f * f
            cy = oy + dy * lean * h * f * f
            cz = h * f
            ww = w * math.sin(math.pi * min(f * 0.85 + 0.12, 1.0)) * (1 - 0.5 * f) + 0.0008
            p1 = (cx + px * ww, cy + py * ww, cz)
            p2 = (cx - px * ww, cy - py * ww, cz)
            i = len(verts)
            verts += [p1, p2]
            if prev is not None:
                faces.append((prev, prev + 1, i + 1, i))
            prev = i
    me = bpy.data.meshes.new(name)
    me.from_pydata([(v[0] + base[0], v[1] + base[1], v[2] + base[2]) for v in verts], [], faces)
    ob = K._obj(name, me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob


# --- rocks -----------------------------------------------------------------------------------------
from mathutils import noise as mnoise


def cell_noise(n, seeds=28, seed=0):
    """Tileable cellular (Worley) noise: returns (F1, F2-F1) for an n x n image; F1 is the distance to the
    nearest seed point and F2-F1 is small along cell borders, which makes chiselled facets and cracks."""
    rng = np.random.default_rng(seed)
    pts = rng.random((seeds, 2))
    ys, xs = (np.arange(n) + 0.5) / n, (np.arange(n) + 0.5) / n
    X, Y = np.meshgrid(xs, ys)
    best1 = np.full((n, n), 9.0)
    best2 = np.full((n, n), 9.0)
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for px, py in pts:
                d = np.hypot(X - (px + ox), Y - (py + oy))
                new2 = np.minimum(best2, np.maximum(best1, d))
                best1 = np.minimum(best1, d)
                best2 = new2
    return best1 / best1.max(), (best2 - best1) / max((best2 - best1).max(), 1e-6)


def rock_maps(name, folder, base, seed=0, n=1024):
    """Tileable granite-like stone: warm grey-tan with broad tonal patches, a fine speckled grain, faint
    hairline cracks, and a grain-driven normal map (no paving-style cells)."""
    f1, edge = cell_noise(n, 14, seed)
    low = K.tile_noise(n, 1.7, seed + 1)
    mid = K.tile_noise(n, 1.1, seed + 2)
    grain = K.tile_noise(n, 0.35, seed + 3)
    speck = K.tile_noise(n, 0.15, seed + 4)
    base = np.array(base)
    warm = np.array([1.04, 0.98, 0.92])
    cool = np.array([0.92, 0.96, 1.03])
    tone = (low[..., None] * warm + (1 - low[..., None]) * cool)
    col = base * tone * (0.88 + 0.24 * mid[..., None]) * (0.9 + 0.2 * grain[..., None]) * (0.95 + 0.1 * speck[..., None])
    crack = np.clip(1 - edge / 0.025, 0, 1)
    col = col * (1 - 0.22 * crack[..., None])
    albedo = K.save_image(name + "_albedo", np.clip(col, 0, 1), folder)
    height = 0.45 * grain + 0.25 * speck + 0.3 * mid + 0.12 * edge
    nrm = K.save_image(name + "_normal", K.normal_from_height(height, 5.0), folder)
    return albedo, nrm


def moss_maps(name, folder, seed=0, n=512):
    a = K.tile_noise(n, 1.0, seed + 1)
    b = K.tile_noise(n, 0.5, seed + 2)
    dark = np.array(K.hex_rgb("#4a5a1a"))
    light = np.array(K.hex_rgb("#7c8a2a"))
    t = np.clip(a * 1.3 + (b - 0.5) * 0.9 - 0.15, 0, 1)[..., None]
    col = dark * (1 - t) + light * t
    col = col * (0.88 + 0.24 * b[..., None])
    albedo = K.save_image(name + "_albedo", col, folder)
    fuzz = K.tile_noise(n, 0.25, seed + 3) * 0.7 + K.tile_noise(n, 0.7, seed + 4) * 0.3
    nrm = K.save_image(name + "_normal", K.normal_from_height(fuzz, 14.0), folder)
    return albedo, nrm


def rock_shell(name, rng, radii, mat, n_pts=30, lean=0.0, bevel=0.1, segs=3, flat=0.55, loc=(0, 0, 0), yaw=0.0,
               tile=1.2, rough=0.012, dissolve=18.0, jit=(0.78, 1.12)):
    """A chunky faceted rock: the convex hull of jittered points on an ellipsoid with near-flat faces merged,
    bevelled into soft ridges, with a bit of surface noise and box-projected UVs. Returns (object, bmesh data)."""
    golden = math.pi * (3 - math.sqrt(5))
    bm = bmesh.new()
    for i in range(n_pts):
        z = 1 - 2 * (i + 0.5) / n_pts
        r = math.sqrt(max(0, 1 - z * z))
        th = i * golden + rng.uniform(-0.3, 0.3)
        v = Vector((r * math.cos(th), r * math.sin(th), z)) * rng.uniform(*jit)
        bm.verts.new(Vector((v.x * radii[0] + lean * v.z * radii[2], v.y * radii[1], max(v.z, -flat) * radii[2])))
    for i in range(7):  # a broad flat foot so the rock sits heavily on the ground
        a = 2 * math.pi * i / 7 + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.8, 0.98)
        bm.verts.new(Vector((math.cos(a) * radii[0] * rr, math.sin(a) * radii[1] * rr, -flat * radii[2])))
    bmesh.ops.convex_hull(bm, input=list(bm.verts))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve), verts=bm.verts, edges=bm.edges)
    bm.normal_update()
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET", segments=segs, profile=0.55, affect="EDGES")
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.normal_update()
    # a bit of lumpiness
    for v in bm.verts:
        d = mnoise.noise(v.co * 2.2 + Vector((seedv(rng), 0, 0))) * rough * max(radii)
        v.co += v.normal * d
    bm.normal_update()
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= zmin
        x, y = v.co.x * math.cos(yaw) - v.co.y * math.sin(yaw), v.co.x * math.sin(yaw) + v.co.y * math.cos(yaw)
        v.co.x, v.co.y = x + loc[0], y + loc[1]
        v.co.z += loc[2]
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        nx, ny, nz = abs(f.normal.x), abs(f.normal.y), abs(f.normal.z)
        for l in f.loops:
            p = l.vert.co
            if nz >= nx and nz >= ny:
                l[uv].uv = (p.x / tile, p.y / tile)
            elif nx >= ny:
                l[uv].uv = (p.y / tile, p.z / tile)
            else:
                l[uv].uv = (p.x / tile, p.z / tile)
    bm.to_mesh(me)
    ob = K._obj(name, me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    bm.free()
    return ob


def seedv(rng):
    return float(rng.random()) * 100.0


def moss_cap(name, rock, mat, rng, thickness=0.018, coverage=0.5, scale=1.6, up=0.25, seed=0):
    """Moss cushions: the rock's own up-facing faces (chosen by noise) copied and pushed out along the surface
    normal, so the patches follow the stone and have ragged edges."""
    me = rock.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    off = Vector((seed * 7.3, seed * 3.1, seed * 5.9))
    keep = []
    for f in bm.faces:
        c = f.calc_center_median()
        s = mnoise.fractal(c * scale + off, 0.5, 2.0, 3) + 0.5 * (f.normal.z - 0.4)
        if f.normal.z > up and s > 0.42 - coverage * 0.5:
            keep.append(f)
    nb = bmesh.new()
    vmap = {}
    uvl = nb.loops.layers.uv.new("UVMap")
    for f in keep:
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                s = 0.6 + 0.8 * (mnoise.noise(v.co * 5.0 + off) * 0.5 + 0.5)
                vmap[v.index] = nb.verts.new(v.co + v.normal * thickness * s)
            vs.append(vmap[v.index])
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue
        for l, vv in zip(nf.loops, f.verts):
            l[uvl].uv = (vv.co.x * 1.5 + vv.co.y * 0.3, vv.co.y * 1.5 + vv.co.z * 0.3)
    nb.normal_update()
    nme = bpy.data.meshes.new(name)
    nb.to_mesh(nme)
    nb.free()
    bm.free()
    ob = K._obj(name, nme, mat)
    nme.polygons.foreach_set("use_smooth", [True] * len(nme.polygons))
    return ob


def foot_points(rock, count, rng, outward=(0.0, 0.1), zlift=0.12):
    """Points around a rock's foot (where its sides meet the ground), found by casting rays inwards."""
    tree = bvh_of(rock)
    c = Vector((sum(v.co.x for v in rock.data.vertices) / len(rock.data.vertices),
                sum(v.co.y for v in rock.data.vertices) / len(rock.data.vertices), 0.0))
    out = []
    for _ in range(count * 6):
        a = rng.uniform(0, 2 * math.pi)
        d = Vector((math.cos(a), math.sin(a), 0))
        o = c + d * 6.0 + Vector((0, 0, zlift))
        hit = tree.ray_cast(o, -d)
        if hit[0] is not None:
            p = hit[0] + d * rng.uniform(*outward)
            out.append((p.x, p.y, 0.0, a))
        if len(out) >= count:
            break
    return out


def moss_patches(name, rock, mat, rng, count, rmin, rmax, thickness=0.03, min_up=0.3, spokes=18, rings=5, near=None):
    """Soft moss cushions: round-ish patches with ragged outlines laid on the rock's up-facing surface, each
    a small polar grid projected onto the stone and raised into a pillow. near=(x, y, r) biases patches to
    that spot (used for the crown)."""
    tree = bvh_of(rock)
    xs = [v.co.x for v in rock.data.vertices]
    ys = [v.co.y for v in rock.data.vertices]
    zs = [v.co.z for v in rock.data.vertices]
    x0, x1, y0, y1, zt = min(xs), max(xs), min(ys), max(ys), max(zs)
    verts, faces, uvs = [], [], []
    made, tries = 0, 0
    while made < count and tries < count * 80:
        tries += 1
        if near is not None and made < count // 2:
            x, y = near[0] + rng.uniform(-near[2], near[2]), near[1] + rng.uniform(-near[2], near[2])
        else:
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        hit = tree.ray_cast(Vector((x, y, zt + 1.0)), Vector((0, 0, -1)))
        if hit[0] is None or hit[1].z < min_up:
            continue
        p, n = hit[0], hit[1].normalized()
        R = rng.uniform(rmin, rmax)
        t1 = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized()
        t2 = n.cross(t1).normalized()
        ph = rng.uniform(0, 100)
        base = len(verts)
        for k in range(rings + 1):
            f = k / rings
            for s in range(spokes):
                th = 2 * math.pi * s / spokes
                rag = 1.0 + 0.45 * mnoise.noise(Vector((math.cos(th) * 2.4 + ph, math.sin(th) * 2.4, 0.5)))
                q = p + (t1 * math.cos(th) + t2 * math.sin(th)) * R * rag * f + n * 0.3
                loc, nrm, _, _ = tree.find_nearest(q)
                lump = 0.75 + 0.5 * (mnoise.noise(Vector((q.x * 7 + ph, q.y * 7, q.z * 7)) ) * 0.5 + 0.5)
                h = thickness * (1 - f ** 1.6) ** 0.8 * lump + 0.002
                verts.append(loc + nrm * h)
                uvs.append((q.x * 1.6, q.y * 1.6 + q.z * 0.4))
        for k in range(rings):
            for s in range(spokes):
                s2 = (s + 1) % spokes
                a, b, c, d = base + k * spokes + s, base + k * spokes + s2, base + (k + 1) * spokes + s2, base + (k + 1) * spokes + s
                faces.append((a, d, c, b) if k else (a, d, c, b))
        made += 1
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = K._obj(name, me, mat)
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return ob
