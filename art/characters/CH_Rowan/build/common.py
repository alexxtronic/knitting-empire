"""
Shared helpers for the CH_Rowan phase scripts (bpy, run inside Blender).

Convention: metres, Z up, the character faces -Y, his left is +X, origin on the ground
between the feet. Every phase script opens the master, deletes what it owns, rebuilds, saves.

File handling and the modifier helpers follow assets/build_template.py of the
blender-image-to-3d skill (MIT, Majid Manzarpour); the mesh builder, the lofts and the
signed-distance ray caster are ours.
"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector, Matrix

PI = math.pi


# ----------------------------------------------------------------------------- files

def argv_after_dashes():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def open_master(path):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(path))
    return bpy.context.scene


def save_master(path):
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path))


def col(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def clear_owned(tag):
    for ob in [o for o in bpy.data.objects if o.get("owner") == tag]:
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Armature):
                bpy.data.armatures.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)


# ----------------------------------------------------------------------------- maths

def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=float) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def table(rows, x):
    """Smooth (Catmull-Rom, non-uniform) interpolation of a table [(x, v1, v2, ...), ...] at x.
    Returns a numpy array of the values. Clamps outside the range."""
    xs = np.array([r[0] for r in rows], dtype=float)
    ys = np.array([r[1:] for r in rows], dtype=float)
    if xs[0] > xs[-1]:
        xs, ys = xs[::-1], ys[::-1]
    x = float(np.clip(x, xs[0], xs[-1]))
    i = int(np.clip(np.searchsorted(xs, x) - 1, 0, len(xs) - 2))
    x0, x1 = xs[i], xs[i + 1]
    h = x1 - x0
    t = (x - x0) / h
    def slope(k):
        if k == 0:
            return (ys[1] - ys[0]) / (xs[1] - xs[0])
        if k == len(xs) - 1:
            return (ys[-1] - ys[-2]) / (xs[-1] - xs[-2])
        return (ys[k + 1] - ys[k - 1]) / (xs[k + 1] - xs[k - 1])
    m0, m1 = slope(i) * h, slope(i + 1) * h
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * m0
            + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * m1)


def spline(points, per_seg=8):
    """Catmull-Rom through 3D control points; returns an (N, 3) array including both ends."""
    P = np.array(points, dtype=float)
    P = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(per_seg):
            t = k / per_seg
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return np.array(out)


def resample(path, n):
    """Resample a polyline to n points evenly spaced by arc length."""
    path = np.asarray(path, dtype=float)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    q = np.linspace(0, s[-1], n)
    return np.stack([np.interp(q, s, path[:, k]) for k in range(3)], axis=1)


def at_length(path, dist):
    """Points on a polyline at the given arc lengths (array)."""
    path = np.asarray(path, dtype=float)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    q = np.asarray(dist, dtype=float)
    return np.stack([np.interp(q, s, path[:, k]) for k in range(3)], axis=1)


def norm(v):
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def frames(path, ref=(0, -1, 0)):
    """Tangent, side A and side B for every point of a path. A is ref made perpendicular to the
    tangent (carried along the path, so it never flips), B = T x A."""
    path = np.asarray(path, dtype=float)
    T = np.zeros_like(path)
    T[1:-1] = path[2:] - path[:-2]
    T[0] = path[1] - path[0]
    T[-1] = path[-1] - path[-2]
    T = norm(T)
    A = np.zeros_like(path)
    a = np.asarray(ref, dtype=float)
    for i in range(len(path)):
        a = a - np.dot(a, T[i]) * T[i]
        a = a / max(np.linalg.norm(a), 1e-9)
        A[i] = a
    B = np.cross(T, A)
    return T, A, B


def sgnpow(v, p):
    return np.sign(v) * np.abs(v) ** p


def ring(center, A, B, ra, rb, n, e=2.0, phase=0.0, rb_neg=None):
    """Superellipse ring: center + ra*c(phi)*A + rb*s(phi)*B. phi=0 is +A.
    rb_neg gives a different radius on the -B side."""
    phi = phase + 2 * PI * np.arange(n) / n
    c, s = np.cos(phi), np.sin(phi)
    ca, sb = sgnpow(c, 2.0 / e), sgnpow(s, 2.0 / e)
    rbb = np.where(sb >= 0, rb, rb if rb_neg is None else rb_neg)
    return (np.asarray(center)[None, :] + ra * ca[:, None] * np.asarray(A)[None, :]
            + (rbb * sb)[:, None] * np.asarray(B)[None, :])


# ----------------------------------------------------------------------------- mesh builder

class MB:
    """Collects vertices, faces and per-corner UVs, then makes one mesh object."""

    def __init__(self):
        self.v, self.f, self.uv, self.mat = [], [], [], []
        self.tags = {}          # vertex index -> float, written to the point attribute "tag"
        self.attrs = {}         # name -> {vertex index: float}, written as point attributes

    def vert(self, co):
        self.v.append((float(co[0]), float(co[1]), float(co[2])))
        return len(self.v) - 1

    def face(self, idx, uvs=None, mat=0):
        self.f.append(tuple(int(i) for i in idx))
        self.uv.append(uvs)
        self.mat.append(mat)

    def grid(self, rows, closed=True, mat=0, skip=(), uv=None, flip=None, idx=None, vmap=None):
        """rows: R lists of C points, bottom to top or along a tube. Returns the index grid.
        uv = (u0, v0, su, sv): UVs are u0 + su * arc position, v0 + sv * length along (metres),
        so a tiling texture keeps one scale over the whole character. skip = cells (r, c) to leave open.
        idx = an existing index grid to face (rows are then ignored)."""
        if idx is None:
            idx = [[self.vert(p) for p in row] for row in rows]
        R, C = len(idx), len(idx[0])
        P = np.array([[self.v[i] for i in row] for row in idx])
        # arc positions
        nxt = np.roll(P, -1, axis=1) if closed else P
        du = np.linalg.norm(nxt - P, axis=2)
        if not closed:
            du = np.linalg.norm(P[:, 1:] - P[:, :-1], axis=2)
        um = du.mean(axis=0)
        U = np.concatenate([[0], np.cumsum(um)])
        dv = np.linalg.norm(P[1:] - P[:-1], axis=2).mean(axis=1)
        V = np.concatenate([[0], np.cumsum(dv)])
        u0, v0, su, sv = uv or (0, 0, 1, 1)
        if flip is None:
            cen = P[0].mean(axis=0) * 0.5 + P[1].mean(axis=0) * 0.5
            a, b, c, d = P[0][0], P[0][1], P[1][1], P[1][0]
            n = np.cross(b - a, d - a)
            flip = np.dot(n, (a + b + c + d) / 4 - cen) < 0
        self.last_uv = dict(row0=list(idx[0]), U=U, u0=u0, v0=v0, su=su, sv=sv, closed=closed)
        for r in range(R - 1):
            for c in range(C if closed else C - 1):
                if (r, c) in skip:
                    continue
                c2 = (c + 1) % C
                q = [idx[r][c], idx[r][c2], idx[r + 1][c2], idx[r + 1][c]]
                uvs = [(u0 + su * U[c], v0 + sv * V[r]), (u0 + su * U[c + 1], v0 + sv * V[r]),
                       (u0 + su * U[c + 1], v0 + sv * V[r + 1]), (u0 + su * U[c], v0 + sv * V[r + 1])]
                if vmap is not None:
                    uvs = [vmap(*t) for t in uvs]
                if flip:
                    q, uvs = q[::-1], uvs[::-1]
                self.face(q, uvs, mat)
        return idx

    def bridge(self, loop_a, loop_b, mat=0, outward_from=None, uv=None, uv_ring=None):
        """Quads between two closed index loops of equal length. Picks the rotation and direction
        of loop_b that makes the shortest connection."""
        n = len(loop_a)
        A = np.array([self.v[i] for i in loop_a])
        best = None
        for direction in (1, -1):
            lb = loop_b[::direction]
            Bp = np.array([self.v[i] for i in lb])
            for s in range(n):
                d = np.linalg.norm(A - np.roll(Bp, -s, axis=0), axis=1).sum()
                if best is None or d < best[0]:
                    best = (d, [lb[(k + s) % n] for k in range(n)])
        lb = best[1]
        cen = (A.mean(axis=0) + np.array([self.v[i] for i in lb]).mean(axis=0)) / 2
        if outward_from is not None:
            cen = np.asarray(outward_from, dtype=float)
        quads, score = [], 0.0
        for k in range(n):
            k2 = (k + 1) % n
            q = [loop_a[k], loop_a[k2], lb[k2], lb[k]]
            P = np.array([self.v[i] for i in q])
            score += np.dot(np.cross(P[1] - P[0], P[3] - P[0]), P.mean(axis=0) - cen)
            quads.append(q)
        for q in quads:                       # one winding for the whole strip, decided by the majority
            uvs = uv or [(0, 0), (0.01, 0), (0.01, 0.01), (0, 0.01)]
            if uv_ring is not None:           # carry on the UVs of the grid whose first row is loop_b
                col = {vi: c for c, vi in enumerate(uv_ring["row0"])}
                C, U = len(uv_ring["row0"]), uv_ring["U"]
                ca, cb = col[q[3]], col[q[2]]
                if (ca + 1) % C == cb:
                    ua, ub = U[ca], U[ca + 1]
                else:
                    ub, ua = U[cb], U[cb + 1]
                P = [np.array(self.v[i]) for i in q]
                da, db = np.linalg.norm(P[0] - P[3]), np.linalg.norm(P[1] - P[2])
                f = lambda u_, d_: (uv_ring["u0"] + uv_ring["su"] * u_, uv_ring["v0"] - uv_ring["sv"] * d_)
                uvs = [f(ua, da), f(ub, db), f(ub, 0.0), f(ua, 0.0)]
            if score < 0:
                q, uvs = q[::-1], uvs[::-1]
            self.face(q, uvs, mat)

    def cap(self, loop, center=None, mat=0, outward=None):
        """Fan cap over a closed loop."""
        P = np.array([self.v[i] for i in loop])
        c = P.mean(axis=0) if center is None else np.asarray(center, dtype=float)
        ci = self.vert(c)
        n = len(loop)
        for k in range(n):
            q = [loop[k], loop[(k + 1) % n], ci]
            Q = np.array([self.v[i] for i in q])
            nrm = np.cross(Q[1] - Q[0], Q[2] - Q[0])
            if outward is not None and np.dot(nrm, np.asarray(outward, dtype=float)) < 0:
                q = q[::-1]
            self.face(q, [(0, 0), (0.01, 0), (0.005, 0.01)], mat)
        return ci

    def build(self, name, collection, owner, materials=(), smooth=True, weld=0.0, recalc=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        uvl = me.uv_layers.new(name="UVMap")
        k = 0
        for fi, f in enumerate(self.f):
            uvs = self.uv[fi]
            for j in range(len(f)):
                uvl.data[k].uv = uvs[j] if uvs else (0, 0)
                k += 1
        for m in materials:
            me.materials.append(m)
        if materials:
            me.polygons.foreach_set("material_index", self.mat)
        me.polygons.foreach_set("use_smooth", [smooth] * len(self.f))
        me.update()
        if self.tags:
            at = me.attributes.new("tag", "FLOAT", "POINT")
            at.data.foreach_set("value", [float(self.tags.get(i, 0.0)) for i in range(len(self.v))])
        for nm, d in self.attrs.items():
            at = me.attributes.new(nm, "FLOAT", "POINT")
            at.data.foreach_set("value", [float(d.get(i, 0.0)) for i in range(len(self.v))])
        bm = bmesh.new()
        bm.from_mesh(me)
        loose = [v for v in bm.verts if not v.link_faces]      # e.g. the grid points inside a cut hole
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        if weld > 0:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
        if recalc:
            orient_islands(bm)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        col(collection).objects.link(ob)
        ob["owner"] = owner
        return ob


def orient_islands(bm):
    """Make every connected piece consistently wound, facing away from its own centre."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    seen = set()
    for f0 in bm.faces:
        if f0 in seen:
            continue
        stack, island = [f0], []
        seen.add(f0)
        while stack:
            f = stack.pop()
            island.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g)
                        stack.append(g)
        cen = Vector((0, 0, 0))
        for f in island:
            cen += f.calc_center_median()
        cen /= len(island)
        score = sum(f.normal.dot(f.calc_center_median() - cen) * f.calc_area() for f in island)
        if score < 0:
            bmesh.ops.reverse_faces(bm, faces=island)


def mirror_points(P):
    P = np.array(P, dtype=float)
    P[..., 0] *= -1
    return P


def subsurf(ob, levels=1, render=None):
    s = ob.modifiers.new("Subdivision", "SUBSURF")
    s.levels = levels
    s.render_levels = levels if render is None else render
    s.uv_smooth = "PRESERVE_BOUNDARIES"
    return s


def material(name, color=(0.5, 0.5, 0.5), roughness=0.8, metallic=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0) and not m.use_nodes:
        m.use_nodes = True
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    m.diffuse_color = (*color[:3], 1.0)
    return m


def set_origin(ob, world_point):
    p = Vector(world_point)
    local = ob.matrix_world.inverted() @ p
    ob.data.transform(Matrix.Translation(-local))
    ob.matrix_world = ob.matrix_world @ Matrix.Translation(local)
    return ob


# ----------------------------------------------------------------------------- signed distance fields

def sd_ellipsoid(p, c, r):
    """Approximate signed distance to an ellipsoid (exact on the surface, good near it)."""
    q = (p - np.asarray(c)) / np.asarray(r)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / np.asarray(r), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_sphere(p, c, r):
    return np.linalg.norm(p - np.asarray(c), axis=-1) - r


def sd_capsule(p, a, b, ra, rb=None):
    """Capsule from a to b; radius ra at a and rb at b (linear)."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    rb = ra if rb is None else rb
    pa, ba = p - a, b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - (ra + (rb - ra) * h)


def smin(a, b, k):
    """Smooth union."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    """Smooth intersection; smax(a, -b, k) subtracts b from a."""
    return -smin(-a, -b, k)


def raycast(sdf, origins, dirs, tmax=0.3, steps=96, refine=14):
    """Distance along each ray (origin inside the solid) to the outermost surface of sdf.
    Marches inward from tmax to find the last inside -> outside crossing, then bisects."""
    O = np.asarray(origins, dtype=float)
    D = np.asarray(dirs, dtype=float)
    ts = np.linspace(tmax, 0.0, steps)
    hi = np.full(len(O), tmax)
    lo = np.zeros(len(O))
    found = np.zeros(len(O), dtype=bool)
    prev_t = ts[0]
    for t in ts[1:]:
        inside = sdf(O + D * t) < 0
        new = inside & ~found
        hi[new] = prev_t
        lo[new] = t
        found |= inside
        prev_t = t
    for _ in range(refine):
        mid = (lo + hi) / 2
        inside = sdf(O + D * mid[:, None]) < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    return np.where(found, (lo + hi) / 2, 0.0)


def sdf_normal(sdf, P, eps=4e-4):
    P = np.asarray(P, dtype=float)
    n = np.zeros_like(P)
    for k in range(3):
        d = np.zeros(3)
        d[k] = eps
        n[:, k] = sdf(P + d) - sdf(P - d)
    return norm(n)
