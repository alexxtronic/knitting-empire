"""
Experiment: give a Tripo character real eyes (eyeballs that turn, lids that close) in place of
the eyes painted on its head, so the game can blink and show emotion.

  Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/add_eyes.py -- "$PWD" nora_tripo --probe
  Blender -b tools/character_build/nora_tripo/nora_tripo.blend -P tools/add_eyes.py -- "$PWD" nora_tripo

Writes tools/character_build/<id>_eyes/<id>_eyes.blend and assets/<id>_eyes.glb. The source
model is not changed. How it works:

1. Front map. Rays are cast at the face from the front, 0.25 mm apart; each hit reads the
   albedo, giving a picture of the painted eyes that is registered to the mesh in metres.
2. The picture is segmented: eye (white, iris, pupil, glints) and upper lashes.
3. A sphere is fitted to the face under each eye. Everything new sits on spheres about its centre.
4. The head is cut open along the eye and lash outlines.
5. New parts, one small mesh (<Name>Eyes) skinned to the Head and two eye bones:
   eyeball caps with a rebuilt iris texture, the lash line (the piece cut from the head, still
   using the painted texture), and upper and lower lid skins that unfold from behind the rim.
6. Shape keys on that mesh: blink, lid_angry, lid_sad, squint (lower lids up), per eye.
"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, CID = argv[0], argv[1]
PROBE = "--probe" in argv
OUT = os.path.join(PROJECT, "tools", "character_build", CID + "_eyes")
os.makedirs(OUT, exist_ok=True)

# where to look on the face (metres, the model faces -Y): set per character
REGION = {"nora_tripo": dict(x=(-0.115, 0.105), z=(1.435, 1.535))}[CID]
STEP = 0.00025


def log(*a):
    print("[add_eyes]", *a, flush=True)


def body_mesh():
    return next(o for o in bpy.data.objects if o.type == "MESH" and len(o.data.vertices) > 5000)


def albedo(ob):
    for n in ob.data.materials[0].node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
            w, h = img.size
            px = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            return img, px.reshape(h, w, 4)[..., :3]
    raise RuntimeError("no albedo image on " + ob.name)


def front_map(ob, tex):
    """Cast rays at the face from the front. Returns colour (H, W, 3, row 0 = lowest z),
    hit position (H, W, 3) and a hit mask."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active
    verts = [v.co.copy() for v in bm.verts]
    tris = [[v.index for v in f.verts] for f in bm.faces]
    uvs = [[l[uvl].uv.copy() for l in f.loops] for f in bm.faces]
    bvh = BVHTree.FromPolygons(verts, tris)
    xs = np.arange(REGION["x"][0], REGION["x"][1], STEP)
    zs = np.arange(REGION["z"][0], REGION["z"][1], STEP)
    H, W = len(zs), len(xs)
    col = np.zeros((H, W, 3), dtype=np.float32)
    pos = np.zeros((H, W, 3), dtype=np.float32)
    uvm = np.zeros((H, W, 2), dtype=np.float32)
    hit = np.zeros((H, W), dtype=bool)
    th, tw = tex.shape[:2]
    d = Vector((0, 1, 0))
    for j, z in enumerate(zs):
        for i, x in enumerate(xs):
            loc, nrm, fi, dist = bvh.ray_cast(Vector((x, -1.0, z)), d)
            if loc is None:
                continue
            a, b, c = (verts[k] for k in tris[fi])
            v0, v1, v2 = b - a, c - a, loc - a
            d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
            den = d00 * d11 - d01 * d01
            if abs(den) < 1e-20:
                continue
            bv = (d11 * d20 - d01 * d21) / den
            bw = (d00 * d21 - d01 * d20) / den
            uv = uvs[fi][0] * (1 - bv - bw) + uvs[fi][1] * bv + uvs[fi][2] * bw
            col[j, i] = tex[int(uv.y % 1.0 * th) % th, int(uv.x % 1.0 * tw) % tw]
            pos[j, i] = loc
            uvm[j, i] = uv
            hit[j, i] = True
    bm.free()
    return xs, zs, col, pos, hit, uvm, bvh


def save_png(path, rgb):
    """rgb (H, W, 3) linear 0..1, row 0 at the bottom."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.new("tmp_png", w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = rgb
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def hsv(rgb):
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    v = mx
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return s, v


if PROBE:
    ob = body_mesh()
    img, tex = albedo(ob)
    xs, zs, col, pos, hit, uvm, bvh = front_map(ob, tex)
    np.save(os.path.join(OUT, "_front_col.npy"), col)
    np.save(os.path.join(OUT, "_front_pos.npy"), pos)
    save_png(os.path.join(OUT, "_front_map.png"), col)
    s, v = hsv(col)
    log("front map", col.shape, "hit", hit.mean().round(3), "image colourspace", img.colorspace_settings.name)
    log("y range of the face in the region", float(pos[..., 1][hit].min()), float(pos[..., 1][hit].max()))


# ----------------------------------------------------------------------------- segmentation

def components(mask):
    """Connected pieces of a boolean picture (4-neighbours). Returns a label picture and the count."""
    H, W = mask.shape
    lab = np.zeros((H, W), dtype=np.int32)
    n = 0
    for j0, i0 in zip(*np.nonzero(mask)):
        if lab[j0, i0]:
            continue
        n += 1
        stack = [(j0, i0)]
        lab[j0, i0] = n
        while stack:
            j, i = stack.pop()
            for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, b = j + dj, i + di
                if 0 <= a < H and 0 <= b < W and mask[a, b] and not lab[a, b]:
                    lab[a, b] = n
                    stack.append((a, b))
    return lab, n


def smooth1d(v, k=9):
    pad = np.pad(v.astype(float), k // 2, mode="edge")
    return np.convolve(pad, np.ones(k) / k, mode="valid")


def hull(v, upper):
    """Upper (or lower) convex hull of the points (i, v[i]), sampled back at every i. It bridges the
    notches that dark paint (the top of the iris, lash shadow) leaves in an outline that is really an arc."""
    pts = [(i, float(y) if upper else -float(y)) for i, y in enumerate(v)]
    h = []
    for p in pts:
        while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0]) >= 0:
            h.pop()
        h.append(p)
    out = np.interp(np.arange(len(v)), [p[0] for p in h], [p[1] for p in h])
    return out if upper else -out


def segment(col):
    """Find both painted eyes. Returns a list of eyes (her right eye first, the one at -X), each a dict:
    E (eye opening mask), L (upper lash mask), c0, c1 (column range of E) and per-column rows
    ebot, etop (opening) and ltop (top of the lash band), smoothed; plus the colour classes."""
    R, G, B = col[..., 0], col[..., 1], col[..., 2]
    s, v = hsv(col)
    gr, br = G / np.maximum(R, 1e-6), B / np.maximum(R, 1e-6)
    sclera = (s < 0.45) & (R > 0.33)
    iris = (R > 0.33) & (s > 0.68) & (gr < 0.62) & (br < 0.30)
    pupil = (R < 0.22) & (s < 0.62)
    core = sclera | iris | pupil
    lab, n = components(core)
    score = [(int((sclera & (lab == k)).sum()), k) for k in range(1, n + 1)]
    best = sorted(score, reverse=True)[:2]
    eyes = []
    H, W = core.shape
    dark = (R < 0.33) & (s > 0.62)
    for _, k in best:
        E = lab == k
        cols = np.nonzero(E.any(axis=0))[0]
        c0, c1 = int(cols.min()), int(cols.max())
        for c in range(c0, c1 + 1):                       # fill each column between its lowest and highest eye pixel
            rows = np.nonzero(E[:, c])[0]
            if len(rows):
                E[rows.min():rows.max() + 1, c] = True
        for r in np.nonzero(E.any(axis=1))[0]:            # and each row
            cc = np.nonzero(E[r])[0]
            E[r, cc.min():cc.max() + 1] = True
        ebot = np.array([np.nonzero(E[:, c])[0].min() if E[:, c].any() else 0 for c in range(c0, c1 + 1)])
        etop = np.array([np.nonzero(E[:, c])[0].max() if E[:, c].any() else 0 for c in range(c0, c1 + 1)])
        etop = np.round(hull(etop, True)).astype(int)
        ebot = np.round(hull(ebot, False)).astype(int)
        E[:] = False
        for c in range(c0, c1 + 1):
            E[ebot[c - c0]:etop[c - c0] + 1, c] = True
        # lashes: dark brown pixels joined to the pixels just above the opening
        allow = np.zeros_like(E)
        r_lo = int(ebot.min())
        allow[r_lo:min(H, int(etop.max()) + 48), max(0, c0 - 64):min(W, c1 + 64)] = True
        for c in range(c0, c1 + 1):
            allow[:etop[c - c0] + 1, c] = False            # inside the opening's columns: only above the opening
        cand = dark & allow & ~E
        seed = np.zeros_like(E)
        for c in range(c0, c1 + 1):
            t = etop[c - c0]
            seed[t + 1:t + 4, c] = True
        llab, ln = components(cand)
        keep = set(np.unique(llab[seed & cand])) - {0}
        L = np.isin(llab, list(keep)) if keep else np.zeros_like(E)
        for _ in range(6):                                # a 1.5 mm margin of skin goes with them: the cut runs through skin, not paint
            L = L | np.roll(L, 1, 0) | np.roll(L, -1, 0) | np.roll(L, 1, 1) | np.roll(L, -1, 1)
        L &= ~E
        hole = E | L
        ltop = np.array([np.nonzero(hole[:, c])[0].max() if hole[:, c].any() else 0 for c in range(c0, c1 + 1)])
        skin = (R > 0.45) & (s > 0.30) & (s < 0.75) & ~E & ~L
        eyes.append(dict(E=E, L=L, c0=c0, c1=c1, ebot=smooth1d(ebot, 7), etop=smooth1d(etop, 7), ltop=smooth1d(np.maximum(ltop, etop), 15), skin=skin,
                         sclera=sclera & E, iris=iris & E, pupil=pupil & E))
    eyes.sort(key=lambda e: e["c0"])
    return eyes


def fit_sphere(P):
    """Least-squares sphere through points (N, 3): centre, radius."""
    A = np.hstack([2 * P, np.ones((len(P), 1))])
    b = (P ** 2).sum(axis=1)
    x = np.linalg.lstsq(A, b, rcond=None)[0]
    c = x[:3]
    return c, float(np.sqrt(x[3] + c @ c))


# ----------------------------------------------------------------------------- build
if not PROBE:
    ob = body_mesh()
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.data.pose_position = "REST"
    img, tex = albedo(ob)
    xs, zs, col, pos, hit, uvm, bvh = front_map(ob, tex)
    H, W = col.shape[:2]
    x0, z0 = REGION["x"][0], REGION["z"][0]
    eyes = segment(col)
    LAB = np.zeros((H, W), dtype=np.int8)                   # 1, 2 = openings; 3, 4 = lashes (right eye, left eye)
    for k, e in enumerate(eyes):
        LAB[e["E"]] = 1 + k
        LAB[e["L"] & ~e["E"]] = 3 + k
        log("eye", k, "columns", e["c0"], e["c1"], "opening %.1f x %.1f mm" % ((e["c1"] - e["c0"]) * STEP * 1000, (e["etop"] - e["ebot"]).max() * STEP * 1000),
            "lash pixels", int(e["L"].sum()))
    dbg = col.copy()
    for k, tint in ((1, (0, 1, 0)), (2, (0, 1, 0)), (3, (1, 0, 1)), (4, (1, 0, 1))):
        dbg[LAB == k] = dbg[LAB == k] * 0.45 + np.array(tint) * 0.55
    save_png(os.path.join(OUT, "_segments.png"), dbg)

    def pix(p):
        return int(round((p[0] - x0) / STEP)), int(round((p[2] - z0) / STEP))

    def label_at(p):
        i, j = pix(p)
        if not (0 <= i < W and 0 <= j < H) or abs(p[1] - pos[j, i, 1]) > 0.002:
            return 0
        return int(LAB[j, i])

    def surf(c, r):
        c, r = float(np.clip(c, 0, W - 1.001)), float(np.clip(r, 0, H - 1.001))
        i, j = int(c), int(r)
        a, b = c - i, r - j
        return (pos[j, i] * (1 - a) * (1 - b) + pos[j, i + 1] * a * (1 - b) + pos[j + 1, i] * (1 - a) * b + pos[j + 1, i + 1] * a * b).astype(float)

    def uv_at(c, r):
        return uvm[int(np.clip(round(r), 0, H - 1)), int(np.clip(round(c), 0, W - 1))].astype(float)

    # ---- cut the head: refine the triangles the outlines cross, then take the eye and lash faces out
    me = ob.data
    tris_before = len(me.polygons)
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    xr, zr = REGION["x"], REGION["z"]

    def near(f):
        c = f.calc_center_median()
        return xr[0] < c.x < xr[1] and zr[0] < c.z < zr[1] and c.y < -0.03

    for _ in range(3):
        edges = set()
        for f in bm.faces:
            if not near(f):
                continue
            ls = {label_at(v.co) for v in f.verts}
            ls.add(label_at(f.calc_center_median()))
            for e in f.edges:
                ls.add(label_at((e.verts[0].co + e.verts[1].co) / 2))
            if len(ls) > 1:
                edges.update(f.edges)
        bmesh.ops.subdivide_edges(bm, edges=list(edges), cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    lash_faces = {3: [], 4: []}
    kill = []
    for f in bm.faces:
        if not near(f):
            continue
        k = label_at(f.calc_center_median())
        if k in (1, 2):
            kill.append(f)
        elif k in (3, 4):
            lash_faces[k].append([(l.vert.co.copy(), l[uvl].uv.copy()) for l in f.loops])
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(me)
    bm.free()
    log("head: triangles", tris_before, "->", len(me.polygons), "lash faces", [len(v) for v in lash_faces.values()])

    # ---- the new parts
    V, F, UV, MAT, GRP = [], [], [], [], []          # vertices, faces, per-corner UVs, material, bone of each vertex
    KEYS = {}                                        # shape key name -> {vertex: delta}

    def vert(p, grp):
        V.append(tuple(float(t) for t in p))
        GRP.append(grp)
        return len(V) - 1

    def key(name, vi, delta):
        KEYS.setdefault(name, {})[vi] = np.asarray(delta, dtype=float)

    def quad_grid(P, uvs, mat, grp, center, shape=None):
        """P: (rows, cols, 3). uvs: (rows, cols, 2). Returns vertex indices (rows, cols)."""
        R_, C_ = P.shape[:2]
        idx = [[vert(P[r, c], grp) for c in range(C_)] for r in range(R_)]
        for r in range(R_ - 1):
            for c in range(C_ - 1):
                q = [(r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)]
                S_ = P if shape is None else shape           # a folded sheet takes its facing from its unfolded shape
                a, b, d = S_[q[0]], S_[q[1]], S_[q[3]]
                if np.dot(np.cross(b - a, d - a), (a + S_[q[2]]) / 2 - center) < 0:
                    q = q[::-1]
                F.append([idx[i][j] for (i, j) in q])
                UV.append([tuple(uvs[i, j]) for (i, j) in q])
                MAT.append(mat)
        return idx

    TEXN = 256
    STRIP = 32                                       # under the eyeballs: a strip of upper-lid and one of lower-lid skin colours
    TEXH = TEXN + 2 * STRIP
    eye_tex = np.zeros((TEXH, TEXN * 2, 3), dtype=np.float32)
    centers, bones = [], []
    for k, e in enumerate(eyes):
        side = "Right" if k == 0 else "Left"
        Emask = e["E"]
        Pe = pos[Emask].astype(float)
        C, Rfit = fit_sphere(pos[Emask | e["L"]].astype(float))
        if not (0.030 < Rfit < 0.090) or C[1] < Pe[:, 1].mean():      # flat or odd patch: use a sensible ball behind it
            n_ = np.array([0.0, -1.0, 0.0])
            Rfit = 0.055
            C = Pe.mean(axis=0) - n_ * Rfit
        f = (Pe.mean(axis=0) - C)
        f /= np.linalg.norm(f)
        Reye = 0.045                                                    # a smaller ball: its edge falls away behind the face
        ctr_px = (float(np.nonzero(Emask)[1].mean()), float(np.nonzero(Emask)[0].mean()))
        C = surf(*ctr_px) - f * (Reye + 0.0025)                         # its front is 2.5 mm behind the painted eye
        r = np.cross([0, 0, 1.0], f)
        r /= np.linalg.norm(r)
        u = np.cross(f, r)
        log(side, "eye: sphere centre", np.round(C, 4), "radius %.1f mm" % (Rfit * 1000), "fit error %.2f mm" %
            (np.abs(np.linalg.norm(Pe - C, axis=1) - Rfit).mean() * 1000))
        centers.append(C)
        bones.append((side + "Eye", C, f))

        def ab(P):
            d = P - C
            d = d / np.linalg.norm(d, axis=-1, keepdims=True)
            fw = d @ f
            return (d @ r) / fw, (d @ u) / fw

        # eyeball texture: plain white of the eye, and the iris made whole (its hidden top mirrored from the bottom)
        a_, b_ = ab(Pe)
        m = 0.016 / Reye                                             # margin round the opening, for looking about
        alo, ahi, blo, bhi = a_.min() - m, a_.max() + m, b_.min() - m, b_.max() + m
        Ce = col[Emask]
        ti = np.clip(((a_ - alo) / (ahi - alo) * TEXN).astype(int), 0, TEXN - 1)
        tj = np.clip(((b_ - blo) / (bhi - blo) * TEXN).astype(int), 0, TEXN - 1)
        orig = np.zeros((TEXN, TEXN, 3), dtype=np.float32)
        have = np.zeros((TEXN, TEXN), dtype=bool)
        orig[tj, ti] = Ce
        have[tj, ti] = True
        for _ in range(3):                                           # close the pinholes of the scatter
            sh = [(np.roll(orig, s_, ax), np.roll(have, s_, ax)) for s_ in (1, -1) for ax in (0, 1)]
            for o_, h_ in sh:
                fill = ~have & h_
                orig[fill] = o_[fill]
                have |= fill
        scl = Ce[e["sclera"][Emask] & (Ce[:, 0] > 0.6)]
        white = np.median(scl, axis=0) if len(scl) else np.array([0.8, 0.75, 0.7])
        pm = e["pupil"][Emask]
        ac, bc = a_[pm].mean(), b_[pm].mean()
        im = (e["iris"][Emask] | pm) & (b_ < bc)
        ri = np.percentile(np.hypot(a_[im] - ac, b_[im] - bc), 97)
        jj, ii = np.mgrid[0:TEXN, 0:TEXN]
        ta = alo + (ii + 0.5) / TEXN * (ahi - alo)
        tb = blo + (jj + 0.5) / TEXN * (bhi - blo)
        dist = np.hypot(ta - ac, tb - bc)
        t = np.repeat(white[None, None, :], TEXN, axis=0).repeat(TEXN, axis=1).astype(np.float32)
        t *= (1.0 - 0.10 * np.clip(dist / (4 * ri), 0, 1))[..., None]
        mirror_j = np.clip(((2 * bc - tb - blo) / (bhi - blo) * TEXN).astype(int), 0, TEXN - 1)
        use_orig = (tb <= bc + 0.10 * ri) & have
        src = np.where(use_orig[..., None], orig, orig[mirror_j, ii])
        ok = np.where(use_orig, True, have[mirror_j, ii])
        edge = np.clip((ri - dist) / (0.06 * ri), 0, 1)[..., None]
        inside = (dist < ri) & ok
        t = np.where(inside[..., None], src * edge + t * (1 - edge), t)
        s_o, v_o = hsv(orig)
        glint = have & (dist < 0.8 * ri) & (s_o < 0.25) & (orig[..., 0] > 0.75)
        t[glint] = orig[glint]
        eye_tex[2 * STRIP:, k * TEXN:(k + 1) * TEXN] = t
        log(side, "iris: radius %.1f mm" % (ri * Reye * 1000))

        # eyeball: a cap of the sphere, a little bigger than the opening, never through the face
        na = max(8, int(round((ahi - alo) * Reye / 0.0030)))
        nb = max(6, int(round((bhi - blo) * Reye / 0.0030)))
        P = np.zeros((nb + 1, na + 1, 3))
        U_ = np.zeros((nb + 1, na + 1, 2))
        for j in range(nb + 1):
            for i in range(na + 1):
                a = alo + (ahi - alo) * i / na
                b = blo + (bhi - blo) * j / nb
                d = f + a * r + b * u
                d /= np.linalg.norm(d)
                rho = Reye
                loc, nrm, fi, dd = bvh.ray_cast(Vector(C), Vector(d))
                if loc is not None:
                    # behind the opening it may sit 1.5 mm under the painted surface; under the skin round it,
                    # 6 mm, so the edge stays inside the cheek when the eye turns
                    outside = max(alo + m - a, a - (ahi - m), blo + m - b, b - (bhi - m), 0.0) * Reye
                    rho = min(rho, dd - (0.0015 + 0.0045 * min(1.0, outside / 0.004)))
                P[j, i] = C + d * rho
                U_[j, i] = ((k + i / na) / 2.0, (2 * STRIP + j / nb * TEXN) / TEXH)
        quad_grid(P, U_, 1, side + "Eye", C)

        # lash line: the faces cut from the head, as they were; they ride down with the lid
        c0, c1 = e["c0"], e["c1"]

        def col_arrays(c):
            t_ = float(np.clip(c - c0, 0, c1 - c0))
            i_ = int(t_)
            i2 = min(i_ + 1, c1 - c0)
            w_ = t_ - i_
            g = lambda arr: arr[i_] * (1 - w_) + arr[i2] * w_
            inside_ = c0 <= c <= c1
            eb, et, lt = g(e["ebot"]), g(e["etop"]), g(e["ltop"])
            hgt = max(0.0, et - eb) if inside_ else 0.0
            return eb, et, lt, hgt

        def amounts(c):
            """How far the upper lid closes at this column for each key (0..1)."""
            s_ = float(np.clip((c - c0) / max(1, c1 - c0), 0, 1))
            inner = s_ if k == 0 else 1 - s_                        # 1 at the corner next to the nose
            return {"blink_" + side[0]: 1.0, "lid_angry": 0.10 + 0.50 * inner, "lid_sad": 0.10 + 0.50 * (1 - inner),
                    "lid_half": 0.45}

        for tri in lash_faces[3 + k]:
            ids = []
            for (co, uv) in tri:
                vi = vert(co, "Head")
                ids.append(vi)
                ci, rj = (co.x - x0) / STEP, (co.z - z0) / STEP
                eb, et, lt, hgt = col_arrays(ci)
                nrm_ = (np.array(co) - C) / np.linalg.norm(np.array(co) - C)
                closed = surf(ci, rj - hgt) + nrm_ * 0.0004
                for name, am in amounts(ci).items():
                    key(name, vi, (closed - np.array(co)) * am)
            F.append(ids)
            UV.append([tuple(uv) for (co, uv) in tri])
            MAT.append(0)

        # lid skins: folded away behind the rim at rest, unfolded over the eye by the keys
        NC, NR = 28, 6
        cs = np.linspace(c0 - 5, c1 + 5, NC)
        Pu, Uu = np.zeros((NR + 1, NC, 3)), np.zeros((NR + 1, NC, 2))
        Pl, Ul = np.zeros((NR + 1, NC, 3)), np.zeros((NR + 1, NC, 2))
        closed_u, raised_l = np.zeros((NR + 1, NC, 3)), np.zeros((NR + 1, NC, 3))
        def skin_row(c, start, step):
            ci = int(round(c))
            r_ = int(round(start))
            for _ in range(40):
                if 0 <= r_ < H and e["skin"][r_, ci]:
                    return r_ + 3 * step
                r_ += step
            return int(round(start))
        up_rows = [skin_row(c, col_arrays(c)[2] + 6, 1) for c in cs]
        lo_rows = [skin_row(c, col_arrays(c)[0] - 8, -1) for c in cs]
        # the lids take their colour from the skin just above and just below the eye, painted into the strips
        lines = []
        for rows_ in (lo_rows, up_rows):
            cols_ = np.array([col[int(np.clip(r_, 0, H - 1)), int(np.clip(round(c), 0, W - 1))] for c, r_ in zip(cs, rows_)])
            cols_ = np.stack([smooth1d(cols_[:, ch], 7) for ch in range(3)], axis=1)
            xi = np.linspace(0, NC - 1, TEXN)
            lines.append(np.stack([np.interp(xi, np.arange(NC), cols_[:, ch]) for ch in range(3)], axis=1))
        for r_ in range(2 * STRIP):                                   # below-the-eye skin at the bottom, above-the-eye skin at the top
            w_ = r_ / (2 * STRIP - 1)
            eye_tex[r_, k * TEXN:(k + 1) * TEXN] = lines[0] * (1 - w_) + lines[1] * w_
        for i, c in enumerate(cs):
            eb, et, lt, hgt = col_arrays(c)
            s_ = i / (NC - 1)
            for j in range(NR + 1):
                tt = j / NR
                top = lt + 6
                p = surf(c, top + (et + 1.5 - top) * tt)
                n_ = (p - C) / np.linalg.norm(p - C)
                Pu[j, i] = p - n_ * 0.0014
                pc = surf(c, top + (eb - 5.0 - top) * tt)
                closed_u[j, i] = pc - (pc - C) / np.linalg.norm(pc - C) * 0.0005
                Uu[j, i] = ((k + (i + 0.5) / NC) / 2.0, ((1 - 0.85 * tt) * (2 * STRIP - 1) + 0.5) / TEXH)
                low = eb - 9
                p = surf(c, low + (eb - 1.0 - low) * tt)
                Pl[j, i] = p - (p - C) / np.linalg.norm(p - C) * 0.0014
                up_to = eb + 0.42 * hgt * (0.55 + 0.45 * math.sin(math.pi * s_))
                pr = surf(c, low + (up_to - low) * tt)
                raised_l[j, i] = pr - (pr - C) / np.linalg.norm(pr - C) * 0.0005
                Ul[j, i] = ((k + (i + 0.5) / NC) / 2.0, (0.35 * tt * (2 * STRIP - 1) + 0.5) / TEXH)
        iu = quad_grid(Pu, Uu, 1, "Head", C, shape=closed_u)
        il = quad_grid(Pl, Ul, 1, "Head", C, shape=raised_l)
        for i, c in enumerate(cs):
            for j in range(NR + 1):
                for name, am in amounts(c).items():
                    key(name, iu[j][i], (closed_u[j, i] - Pu[j, i]) * am)
                key("squint", il[j][i], raised_l[j, i] - Pl[j, i])

    # ---- mesh object, materials, bones
    save_png(os.path.join(OUT, CID + "_eyes_iris.png"), eye_tex)
    iris_img = bpy.data.images.load(os.path.join(OUT, CID + "_eyes_iris.png"))
    iris_img.pack()
    mat_eye = bpy.data.materials.new(CID.split("_")[0].capitalize() + "_eyes")
    if bpy.app.version < (5, 0, 0):
        mat_eye.use_nodes = True
    nt = mat_eye.node_tree
    bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    ti_ = nt.nodes.new("ShaderNodeTexImage")
    ti_.image = iris_img
    nt.links.new(ti_.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.4
    em = bpy.data.meshes.new(arm.name + "Eyes")
    em.from_pydata(V, [], F)
    uvl2 = em.uv_layers.new(name="UVMap")
    n = 0
    for fi, face in enumerate(F):
        for j in range(len(face)):
            uvl2.data[n].uv = UV[fi][j]
            n += 1
    em.materials.append(ob.data.materials[0])
    em.materials.append(mat_eye)
    em.polygons.foreach_set("material_index", MAT)
    em.polygons.foreach_set("use_smooth", [True] * len(F))
    em.update()
    eo = bpy.data.objects.new(arm.name + "Eyes", em)
    ob.users_collection[0].objects.link(eo)
    eo.parent = arm
    eo.modifiers.new("Armature", "ARMATURE").object = arm
    for g in sorted(set(GRP)):
        vg = eo.vertex_groups.new(name=g)
        vg.add([i for i, gg in enumerate(GRP) if gg == g], 1.0, "REPLACE")
    eo.shape_key_add(name="Basis", from_mix=False)
    for name in sorted(KEYS):
        sk = eo.shape_key_add(name=name, from_mix=False)      # from_mix would fold the earlier keys into this one
        sk.value = 0.0
        for vi, d in KEYS[name].items():
            sk.data[vi].co = Vector(V[vi]) + Vector(d)
    bpy.context.view_layer.objects.active = arm
    arm.data.pose_position = "POSE"
    bpy.ops.object.mode_set(mode="EDIT")
    for (name, C, f) in bones:
        b = arm.data.edit_bones.new(name)
        b.head, b.tail = Vector(C), Vector(C + f * 0.03)
        b.parent = arm.data.edit_bones["Head"]
        b.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    log("eyes mesh: verts", len(V), "tris", sum(len(f_) - 2 for f_ in F), "shape keys", sorted(KEYS))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, CID + "_eyes.blend"))
    if "--no-export" not in argv:
        bpy.ops.export_scene.gltf(filepath=os.path.join(PROJECT, "assets", CID + "_eyes.glb"), export_format="GLB", export_apply=False,
                                  export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                                  export_morph=True, export_animations=True, export_animation_mode="ACTIONS",
                                  export_force_sampling=True)
        log("exported", os.path.join("assets", CID + "_eyes.glb"))
