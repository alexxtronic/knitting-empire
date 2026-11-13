"""The one sweater every character can wear, fitted to a character's body and then given any of the
knitted designs in patterns.py. From Alex's reference (ref_sweater.png): a crew-neck pullover, a little
oversized, dropped shoulders, roomy sleeves gathered into ribbed cuffs, a ribbed hem and collar.

How it is made, so the same mesh (and the same UVs, so the same designs) fits everyone:
  * the body and the sleeves are rings of a fixed number of points. Each ring is the convex outline of
    the character's body there (torso parts only for the body, arm parts only for a sleeve), so the
    knit bridges hollows the way real cloth does, plus some ease, more over the belly and above the
    cuffs where the reference blouses;
  * above the shoulders the rings turn into a dome from the chest's centre up to a crew collar round
    the base of the neck; the hem, collar and cuffs turn under, inside, so the openings have depth;
  * a short cloth simulation (Blender's, the body as the obstacle, ribs held) lets it settle and sag;
  * every point takes its bone weights from the nearest skin of the same part of the body, so it
    moves with her in the game; the body gets an `under_sweater` shape key that tucks the skin a
    little further in wherever the sweater covers it.
UVs are laid out flat by arc length on Nora, so every stitch is the same size, and each part has its
own rectangle in one 2048 x 1024 atlas (layout.json). The stitch normal map is the same for every
design; each design is one colour map.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/sweater/build.py -- [nora] [--render]

Writes out/<char>_sweater.blend, out/<char>_sweater.glb (skinned to the character's rig, no
animations), out/textures/sweater_n.png and out/textures/<design>.png, and with --render the review
pictures in review/. Blender: front is -Y.
"""
import json
import math
import os
import shutil
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
WEB = os.path.join(HERE, "..", "textures_web")
sys.path.insert(0, HERE)
import patterns as PT  # noqa: E402

CHARS = {
    "nora": dict(blend="tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend", rig="Nora", body="nora_tripoMesh"),
    "steve": dict(blend="tools/character_build/steve_tripo_eyes/steve_tripo_eyes.blend", rig="Rowan", body="steve_tripoMesh", neck=0.075),
    "barbara": dict(blend="tools/character_build/barbara_tripo_eyes/barbara_tripo_eyes.blend", rig="Nora", body="barbara_tripoMesh"),
}

NC = 64          # points round the body
NS = 32          # points round a sleeve
GAUGE = (0.009, 0.0075)   # one stitch, wide x tall (m): a chunky knit
PX = 4           # design map pixels per stitch (the stitches themselves come from the tiles)
ATLAS = (1024, 512)
TILE = 4         # the stitch tiles are 4 stitches by 4 rows
TILE_PX = 32     # tile pixels per stitch
HEM_RIB = 0.05
CUFF_RIB = 0.055
COLLAR_H = 0.02
LIP = 0.03       # how far the hem, cuffs and collar turn under inside
THICK = 0.007    # the knit's thickness at the turned edges
EASE = 1.0       # room over the body; Nora's own (sculpted) sweater is already roomy
ARM_REACH = 0.085  # arm skin further than this from the bone is not the arm
MARGIN = 0.012   # how far inside the knit the under_sweater key keeps the skin
TUCK = 0.02      # how far the under_sweater key pulls the covered skin in
ARM_TUCK = 0.035 # and the arms, further: a relaxed arm rests against the body's knit, and its skin
                 # (a sculpted sleeve) would show through there

TORSO_G = {"Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"}
SIDES = ("Left", "Right")


# --- the character ---------------------------------------------------------------------------------

def load_char(cid):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = CHARS[cid]
    with bpy.data.libraries.load(os.path.join(ROOT, c["blend"]), link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n != "KnitProps"]     # the body, its rig, its eyes
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
    rig, body = bpy.data.objects[c["rig"]], bpy.data.objects[c["body"]]
    rig.data.pose_position = "REST"
    if rig.animation_data:
        rig.animation_data.action = None
    if body.data.shape_keys:
        for k in body.data.shape_keys.key_blocks:
            k.value = 0.0
    bpy.context.view_layer.update()
    return rig, body


def bones(rig):
    mw = rig.matrix_world
    return {b.name: (mw @ b.head_local, mw @ b.tail_local) for b in rig.data.bones}


def body_points(body):
    """World positions of the body's vertices in the rest pose, the name of the bone each follows
    most, and every vertex's weights."""
    mw = body.matrix_world
    co = np.array([(mw @ v.co)[:] for v in body.data.vertices])
    names = [g.name for g in body.vertex_groups]
    dom, weights = [], []
    for v in body.data.vertices:
        w = {names[g.group]: g.weight for g in v.groups if g.weight > 0.0}
        weights.append(w)
        dom.append(max(w, key=w.get) if w else "")
    return co, np.array(dom), weights


# --- outlines ----------------------------------------------------------------------------------------

def hull2(pts):
    """Convex hull (counter-clockwise) of 2D points."""
    P = sorted(set(map(tuple, np.round(np.asarray(pts), 5))))
    if len(P) < 3:
        return np.array(P)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in P:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(P):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return np.array(lo[:-1] + up[:-1])


def reach(hull, c, d):
    """How far from c along direction d to the hull's edge (c inside), or None."""
    best = None
    n = len(hull)
    for i in range(n):
        p, q = hull[i], hull[(i + 1) % n]
        e = q - p
        det = -d[0] * e[1] + e[0] * d[1]
        if abs(det) < 1e-12:
            continue
        w = p - c
        t = (-w[0] * e[1] + e[0] * w[1]) / det
        s = (d[0] * w[1] - d[1] * w[0]) / det
        if -1e-9 <= s <= 1 + 1e-9 and t > 0:
            best = t if best is None else max(best, t)
    return best


def smooth_ring(r, passes=1):
    for _ in range(passes):
        r = 0.25 * np.roll(r, 1) + 0.5 * r + 0.25 * np.roll(r, -1)
    return r


# --- the shape ---------------------------------------------------------------------------------------

def torso_rows(co, dom, B, neck_r=0.06):
    """The body of the sweater as rows of NC points, top (collar's turned-in edge) to bottom (hem's
    turned-in edge). Returns (rows: list of (NC, 3) arrays, tags: one per row)."""
    hips = B["Hips"][0].z
    hem0 = hips - 0.04
    zc = B["UpperChest"][0].z + 0.035          # where the rings turn into the shoulders' dome
    sel = np.isin(dom, list(TORSO_G))
    # the tops of the shoulders, so the dome reaches out over them (the dropped shoulder)
    sel |= np.isin(dom, [s + "UpperArm" for s in SIDES]) & (co[:, 2] > zc - 0.005)
    sel |= np.isin(dom, [s + "UpperLeg" for s in SIDES]) & (co[:, 2] > hem0 - 0.03) & (co[:, 2] < hips) & (np.abs(co[:, 0]) < 0.16)
    T = co[sel]
    chest_lo, chest_hi = B["Chest"][0].z, B["UpperChest"][0].z
    band = T[(T[:, 2] > chest_lo) & (T[:, 2] < chest_hi)]
    yc = 0.5 * (band[:, 1].min() + band[:, 1].max())
    c2 = np.array([0.0, yc])

    # columns spaced evenly by arc length round the chest, starting at the back's centre
    chest = hull2(band[np.abs(band[:, 2] - (chest_lo + chest_hi) / 2) < 0.03][:, :2])
    fine = np.linspace(math.pi, 3 * math.pi, 721)
    pts = np.array([c2 + reach(chest, c2, (math.sin(a), -math.cos(a))) * np.array((math.sin(a), -math.cos(a))) for a in fine])
    arc = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    thetas = np.interp(np.arange(NC) * arc[-1] / NC, arc, fine)
    dirs = np.stack([np.sin(thetas), -np.cos(thetas)], axis=1)
    front = np.clip(-dirs[:, 1], 0, 1)          # 1 at the front's centre, 0 at the sides and back
    side = np.abs(dirs[:, 0])                   # 1 under the arms

    # the collar's base: round the bottom of the neck, dipping at the front. Its height comes from the
    # shape, not the neck bone (which sits low on some rigs): the top of the shoulders just beside
    # the neck, at the back and sides
    size = B["Hips"][0].z / 0.821
    skin = co[~np.isin(dom, ["Head", "LeftHand", "RightHand"] + [s + p for s in SIDES for p in ("LowerArm", "UpperLeg", "LowerLeg")])]
    beside = skin[(np.abs(skin[:, 0]) > 0.08 * size) & (np.abs(skin[:, 0]) < 0.12 * size)
                  & (np.abs(skin[:, 1] - yc) < 0.07 * size) & (skin[:, 2] > zc)]
    neck_z = B["Neck"][0].z - 0.016
    if len(beside) > 10:
        neck_z = max(neck_z, float(np.percentile(beside[:, 2], 90)) - 0.01)
    sel_t = co[:, 2] < neck_z + 0.012
    # a round crew collar of NECK_R (or the character's own `neck`) round the neck's middle: the
    # torso's, unless the neck sits clear of it (Steve's sits back), then the neck skin's own
    slab = np.abs(co[:, 2] - neck_z) < 0.012
    nc = c2
    nk = co[~np.isin(dom, ["Head", "LeftHand", "RightHand", "LeftUpperArm", "RightUpperArm"]) & slab]
    nk = nk[np.hypot(nk[:, 0], nk[:, 1] - yc) < 0.13 * size]
    if len(nk) > 8:
        nh = hull2(nk[:, :2])
        mid = 0.5 * (nh.min(axis=0) + nh.max(axis=0))
        print("[torso] neck middle %.3f from the torso's" % np.linalg.norm(mid - c2)) if os.environ.get("SW_DEBUG") else None
        if np.linalg.norm(mid - c2) > 0.05:
            nc = mid
    r_neck = np.full(NC, neck_r)
    col_r = np.einsum("ij,ij->i", nc - c2 + dirs * (r_neck + 0.012 + 0.016 * front ** 2)[:, None], dirs)
    col_z = neck_z - 0.006 - 0.04 * front ** 2

    # slices of the torso, 1 cm apart: each one's outline, how far out it reaches in each column
    T = T[T[:, 2] < neck_z + 0.012]
    zs = np.arange(hem0, neck_z + 0.02, 0.01)
    prof = [[] for _ in range(NC)]
    for z in zs:
        s = T[np.abs(T[:, 2] - z) < 0.008]
        if len(s) < 12:
            continue
        h = hull2(s[:, :2])
        for k in range(NC):
            r = reach(h, c2, dirs[k])
            if r:
                prof[k].append((r, z))
    # below the chest, no wider than the chest (and a little): a bag or a flared jacket at the hips
    # stays under the knit (the under_sweater key tucks it in) rather than tenting it
    for k in range(NC):
        top = [r for r, z in prof[k] if chest_lo <= z <= chest_hi + 0.05]
        if top:
            cap = max(top) * 1.15
            prof[k] = [(min(r, cap) if z < chest_lo else r, z) for r, z in prof[k]]

    def ease_at(z):
        # hem rib -> blouse above it -> belly -> chest -> shoulders
        return EASE * float(np.interp(z, [hem0, hem0 + HEM_RIB, hem0 + HEM_RIB + 0.02, hips + 0.12, zc - 0.08, zc],
                                      [0.016, 0.018, 0.026, 0.02, 0.015, 0.012]))

    # rows: hem rib, body (straight down), dome (rays from the chest's centre), collar
    body_z = list(np.linspace(hem0 + HEM_RIB, zc, 19))
    rib_z = list(np.linspace(hem0, hem0 + HEM_RIB, 4))[:-1]
    n_dome = 8
    grid = {}       # name -> list of rows
    out_rows = []
    tags = []
    per_col = []
    for k in range(NC):
        P = np.array(prof[k] + [(col_r[k] - 0.012, col_z[k]), (-0.05, hem0 - 0.01), (-0.05, col_z[k] + 0.02)])
        h = hull2(P)
        col = []
        for z in rib_z + body_z:
            r = reach(h, np.array([0.0, z]), (1.0, 0.0)) or 0.1
            e = ease_at(z) * (1.0 - 0.6 * side[k] ** 4 * (z < zc - 0.06))   # closer under the arms
            # the knit blouses over the hem rib in soft folds
            above = (z - (hem0 + HEM_RIB)) / 0.07
            if 0.0 <= above <= 1.0:
                e += 0.007 * math.sin(math.pi * (1 - above)) ** 1.5 * math.cos(16 * thetas[k] + 0.7)
            col.append((r + e, z))
        phi_top = math.atan2(col_z[k] - zc, col_r[k] - 0.012)
        for j in range(1, n_dome + 1):
            phi = phi_top * j / n_dome
            d = (math.cos(phi), math.sin(phi))
            r = reach(h, np.array([0.0, zc]), d) or 0.1
            e = 0.02 + (0.0 - 0.02) * j / n_dome
            col.append(((r + e) * d[0] + 0.0, zc + (r + e) * d[1]))
        col[-1] = (col_r[k], col_z[k])
        per_col.append(col)
    nrow = len(per_col[0])
    # rows bottom-up so far; the hem's ribbed rows are flat-ish: pull them in to the rib's radius
    rows = []
    for i in range(nrow):
        r = np.array([per_col[k][i][0] for k in range(NC)])
        z = np.array([per_col[k][i][1] for k in range(NC)])
        if i >= len(rib_z) + len(body_z):
            r = smooth_ring(r, 1)
        rows.append((r, z))
    # the hem rib: as wide as the bottom body row, drawn in a little
    rb = rows[len(rib_z)][0]
    for i in range(len(rib_z)):
        rows[i] = (rb - 0.006 + 0.003 * i / max(1, len(rib_z) - 1), rows[i][1])

    def ring(r, z):
        return np.stack([c2[0] + r * dirs[:, 0], c2[1] + r * dirs[:, 1], z], axis=1)

    if os.environ.get("SW_DEBUG"):
        print("[torso] yc %.3f zc %.3f neck_z %.3f col_r %.3f..%.3f col_z %.3f..%.3f" % (yc, zc, neck_z, col_r.min(), col_r.max(), col_z.min(), col_z.max()))
        for i, (r, z) in enumerate(rows):
            print("[torso] row %d z %.3f..%.3f r %.3f..%.3f" % (i, z.min(), z.max(), r.min(), r.max()))

    pts = []
    # top first: collar lip (inside), collar top, collar, then the dome and body down, the hem, hem lip
    cr, cz = rows[-1]
    collar = [ring(cr - THICK, cz + 0.006), ring(cr - THICK * 0.6, cz + COLLAR_H + 0.002),
              ring(cr - 0.002, cz + COLLAR_H), ring(cr, cz + COLLAR_H * 0.5)]
    for p in collar:
        pts.append(p)
        tags.append("collar")
    for i in range(nrow - 1, -1, -1):
        r, z = rows[i]
        pts.append(ring(r, z))
        tags.append("torso" if i >= len(rib_z) else "hem")
    tags[len(collar)] = "torso"     # the collar's base row belongs to both; the band above is collar
    br, bz = rows[0]
    for p in (ring(br - THICK * 0.6, bz - 0.003), ring(br - THICK, bz + LIP * 0.5), ring(br - THICK, bz + LIP)):
        pts.append(p)
        tags.append("hem")
    marks = {"zc": zc, "yc": yc, "neck_z": neck_z, "n_dome": n_dome, "collar_rows": len(collar)}
    return pts, tags, marks


def sleeve_rows(co, dom, B, side):
    """One sleeve as rings of NS points along the arm from inside the shoulder to the cuff's
    turned-in edge. Returns (rows, tags)."""
    sa, el = B[side + "UpperArm"][0], B[side + "LowerArm"][0]
    wr, ht = B[side + "Hand"][0], B[side + "Hand"][1]
    end = wr + (ht - wr).normalized() * 0.012
    path = [sa + (el - sa).normalized() * 0.01, el, wr, end]
    seg = [(path[i + 1] - path[i]).length for i in range(3)]
    L = sum(seg)

    def at(s):
        s = min(max(s, 0.0), L)
        for i in range(3):
            if s <= seg[i] or i == 2:
                t = s / seg[i]
                return path[i].lerp(path[i + 1], min(t, 1.0))
            s -= seg[i]

    def axis(s):
        a = (at(min(L, s + 0.03)) - at(max(0.0, s - 0.03)))
        return a.normalized()

    arm = co[np.isin(dom, [side + "UpperArm", side + "LowerArm", side + "Hand"])]
    sign = 1.0 if side == "Left" else -1.0
    cuff0 = L - CUFF_RIB

    def ease_at(s):
        return EASE * float(np.interp(s, [0, 0.06, 0.25, cuff0 - 0.08, cuff0 - 0.02, cuff0, L],
                                      [0.008, 0.012, 0.016, 0.03, 0.026, 0.004, 0.004]))

    stations = list(np.linspace(0.0, cuff0, 22)) + list(np.linspace(cuff0, L, 4))[1:]
    psi = math.pi + 2 * math.pi * np.arange(NS) / NS        # from the inner side (the seam) round

    # each station's slice of the arm (arm skin within REACH of the bone) in the ring's own plane
    frames, slices = [], []
    for s in stations:
        c, a = at(s), axis(s)
        out = Vector((sign, 0, 0))
        out = (out - a * out.dot(a)).normalized()
        fwd = a.cross(out) * sign
        rel = arm - np.array(c[:])
        along = rel @ np.array(a[:])
        sl = rel[np.abs(along) < 0.02]
        if len(sl):
            sl = sl[np.linalg.norm(sl - np.outer(sl @ np.array(a[:]), a[:]), axis=1) < ARM_REACH]
        P2 = np.stack([sl @ np.array(out[:]), sl @ np.array(fwd[:])], axis=1) if len(sl) >= 6 else None
        frames.append((c, a, out, fwd))
        slices.append(P2)
    # the ring's centre: the middle of the slice's outline, smoothed along the arm
    cen = np.array([0.5 * (P.min(axis=0) + P.max(axis=0)) if P is not None else (np.nan, np.nan) for P in slices])
    for j in range(2):
        ok = ~np.isnan(cen[:, j])
        cen[:, j] = np.interp(np.arange(len(cen)), np.nonzero(ok)[0], cen[ok, j])
    for _ in range(2):
        cen[1:-1] = 0.25 * cen[:-2] + 0.5 * cen[1:-1] + 0.25 * cen[2:]
    cen[:, 0] += 0.006      # a little out from the body, so the sleeve stands as its own tube
    elbow = seg[0]

    rows, tags = [], []
    prev = None
    for n_st, s in enumerate(stations):
        c, a, out, fwd = frames[n_st]
        P2 = slices[n_st]
        h = hull2(P2 - cen[n_st]) if P2 is not None else None
        rr = []
        for p in psi:
            d = np.array((math.cos(p), math.sin(p)))
            r = reach(h, np.zeros(2), d) if h is not None and len(h) >= 3 else None
            rr.append(r if r else (np.mean(prev) if prev is not None else 0.05))
        rr = smooth_ring(np.array(rr), 2)
        inner = np.cos(psi) < -0.5             # the side against the body: no wider than the rest
        rr[inner] = np.minimum(rr[inner], np.median(rr))
        if prev is not None:
            rr = np.maximum(rr, 0.0) * 0.6 + 0.4 * np.maximum(rr, prev - 0.012)
        if s >= cuff0:     # the cuff: round, snug
            rr = np.full(NS, rr.mean())
        prev = rr
        rr = rr + ease_at(s)
        # gathers into the cuff, and soft creases in the crook of the elbow
        g = np.clip(1.0 - (cuff0 - s) / 0.1, 0, 1) * (s < cuff0)
        rr = rr + 0.007 * g ** 1.5 * np.cos(7 * psi + 0.4 * n_st)
        crook = math.exp(-((s - elbow) / 0.06) ** 2) * (1 if n_st % 2 else -1)
        rr = rr + 0.004 * crook * np.clip(-np.sin(psi) * 0.5 - np.cos(psi) * 0.8, 0, 1)
        cc = c + out * cen[n_st][0] + fwd * cen[n_st][1]
        if os.environ.get("SW_DEBUG"):
            print("[sl] %s s=%.3f c=(%.3f %.3f %.3f) n=%d r=%.3f..%.3f" % (side, s, cc.x, cc.y, cc.z, 0 if P2 is None else len(P2), rr.min(), rr.max()))
        ring = np.array([(cc + (out * math.cos(p) + fwd * math.sin(p)) * r)[:] for p, r in zip(psi, rr)])
        rows.append(ring)
        tags.append("sleeve" if s < cuff0 else "cuff")
    tags[len(stations) - 4] = "sleeve"
    # turn the cuff under, inside
    last = rows[-1]
    c = last.mean(axis=0)
    a = np.array(frames[-1][1][:])
    for back, shrink in ((0.003, THICK * 0.6), (LIP * 0.5, THICK), (LIP, THICK)):
        rows.append(np.array([c - a * back + (p - c) * (1 - shrink / max(0.02, np.linalg.norm(p - c))) for p in last]))
        tags.append("cuff")
    return rows, tags, dict(path=[p[:] for p in path], L=L, sign=sign)


# --- the mesh and its UVs ----------------------------------------------------------------------------

def layout(pieces):
    """Rectangles in the atlas (pixels, row 0 at the top) for each part, sized from its stitches."""
    reg = {}
    for name, (W, H) in pieces.items():
        reg[name] = dict(w=W, h=H)
    order = [("torso", 8, 8), ("sleeve", None, 8), ("hem", 8, None), ("collar", None, None), ("cuff", None, None)]
    x_tor = 8 + reg["torso"]["w"] * PX + 12
    reg["torso"].update(x=8, y=8)
    reg["sleeve"].update(x=x_tor, y=8)
    reg["hem"].update(x=8, y=8 + reg["torso"]["h"] * PX + 12)
    reg["collar"].update(x=x_tor, y=8 + reg["sleeve"]["h"] * PX + 12)
    reg["cuff"].update(x=x_tor + reg["collar"]["w"] * PX + 12, y=reg["collar"]["y"])
    for k, r in reg.items():
        if not os.environ.get("SW_LOOSE"): assert r["x"] + r["w"] * PX <= ATLAS[0] and r["y"] + r["h"] * PX <= ATLAS[1], (k, reg)
    del order
    return reg


def flat_uv(rows, seam_front, region_of_row):
    """Arc-length coordinates of every point of a tube: (u_st, d) per row and column, u_st in
    stitches from the tube's centre line (the side away from the seam), d in metres down the
    column from the top of its part. Columns 0..n (n repeats 0 at the end of the arc)."""
    n = len(rows[0])
    R = [np.vstack([r, r[:1]]) for r in rows]
    U = []
    for r in R:
        seg = np.linalg.norm(np.diff(r, axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        U.append((s - s[n // 2]) / GAUGE[0])        # column n/2 is the centre (front / outer side)
    D = np.zeros((len(R), n + 1))
    for i in range(1, len(R)):
        D[i] = D[i - 1] + np.linalg.norm(R[i] - R[i - 1], axis=1)
    return np.array(U), D


def build_piece(name, rows, tags, kinds, mat):
    """A tube from rows of points; faces get the part of the row above them (or below, for the last
    row of a part). Returns the object and per-part stitch extents."""
    n = len(rows[0])
    U, D = flat_uv(rows, None, None)
    verts = [tuple(p) for r in rows for p in r]
    faces, parts = [], []
    for i in range(len(rows) - 1):
        part = tags[i + 1] if tags[i] != tags[i + 1] and tags[i] in ("torso", "sleeve") else tags[i]
        if tags[i] == "collar" and tags[i + 1] == "torso":
            part = "collar"
        for k in range(n):
            faces.append((i * n + k, (i + 1) * n + k, (i + 1) * n + (k + 1) % n, i * n + (k + 1) % n))
            parts.append((part, i, k))
    # every face out: compare each face's normal with the way out from its ring's centre
    vs = np.array(verts)
    out = 0.0
    for f in faces[n * (len(rows) // 2): n * (len(rows) // 2 + 1)]:
        a, b, c = vs[f[0]], vs[f[1]], vs[f[2]]
        cen = vs[(f[0] // n) * n:(f[0] // n + 1) * n].mean(axis=0)
        out += float(np.dot(np.cross(b - a, c - b), a - cen))
    if out < 0:
        faces = [tuple(reversed(f)) for f in faces]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    # each part's top row (its d = 0) and its extent in stitches
    ext = {}
    tops = {}
    for p, i, k in parts:
        tops.setdefault(p, i)
    for p, top in tops.items():
        rws = [i for q, i, k in parts if q == p]
        lo, hi = min(rws), max(rws) + 1
        width = max(U[i][-1] - U[i][0] for i in range(lo, hi + 1))
        depth = max((D[hi] - D[lo]))
        ext[p] = (int(math.ceil(width)) + 2, int(math.ceil(depth / GAUGE[1])) + 2, lo)
    return ob, U, D, parts, ext


def assign_uvs(ob, U, D, parts, ext, reg):
    me = ob.data
    uv = me.uv_layers.new(name="UVMap")
    st = me.uv_layers.new(name="Stitches")      # in tiles of TILE stitches: where the knit tiles go
    n = U.shape[1] - 1
    li = 0
    for poly, (p, i, k) in zip(me.polygons, parts):
        r = reg[p]
        top = ext[p][2]
        sx = (r["w"] - 2.0) / max(1.0, ext[p][0] - 2.0)      # this character's stitches, fitted to the
        sy = (r["h"] - 2.0) / max(1.0, ext[p][1] - 2.0)      # shared layout (1 on Nora)
        quad = ((i, k), (i + 1, k), (i + 1, k + 1), (i, k + 1))
        if poly.vertices[0] != i * n + k or poly.vertices[1] != (i + 1) * n + k:
            quad = tuple(reversed(quad))
        for corner, (ii, kk) in zip(poly.loop_indices, quad):
            us = U[ii][kk] * sx + r["w"] / 2.0
            ds = (D[ii][kk] - D[top][kk]) / GAUGE[1] * sy + 1.0
            px = r["x"] + us * PX
            py = r["y"] + ds * PX
            uv.data[corner].uv = (px / ATLAS[0], 1.0 - py / ATLAS[1])
            st.data[corner].uv = ((us - 1.0) / TILE, -(ds - 1.0) / TILE)
        li += 1


# --- simulation, weights, the body's key ------------------------------------------------------------

def settle(ob, body, frames=24):
    """A short cloth simulation: the sweater settles onto the body (an obstacle) under its own weight,
    held by its ribs (the vertex group "pin")."""
    sc = bpy.context.scene
    col = body.modifiers.new("hit", "COLLISION")
    body.collision.thickness_outer = 0.004
    body.collision.cloth_friction = 20.0
    c = ob.modifiers.new("cloth", "CLOTH")
    st, cs = c.settings, c.collision_settings
    st.quality = 8
    st.mass = 0.35
    st.tension_stiffness = st.compression_stiffness = 25.0
    st.shear_stiffness = 8.0
    st.bending_stiffness = 0.6
    st.tension_damping = st.compression_damping = st.shear_damping = 8.0
    st.air_damping = 3.0
    st.vertex_group_mass = "pin"
    st.pin_stiffness = 1.0
    cs.collision_quality = 4
    cs.distance_min = 0.006
    cs.use_self_collision = False
    c.point_cache.frame_start, c.point_cache.frame_end = 1, frames
    sc.frame_start, sc.frame_end = 1, frames
    for f in range(1, frames + 1):
        sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = new
    bpy.data.meshes.remove(old)
    body.modifiers.remove(col)
    sc.frame_set(1)


def skin(ob, rig, co, dom, weights, piece_of):
    """Bone weights for every point of the sweater from the nearest skin of the same part of the body
    (the torso's for the body and collar, that arm's for a sleeve), eight nearest, by distance."""
    sets = {"torso": np.isin(dom, list(TORSO_G) + ["Neck", "LeftUpperLeg", "RightUpperLeg"])}
    for s in SIDES:
        sets[s] = np.isin(dom, [s + "Shoulder", s + "UpperArm", s + "LowerArm", s + "Hand"])
    trees = {}
    for k, m in sets.items():
        idx = np.nonzero(m)[0]
        t = KDTree(len(idx))
        for j, i in enumerate(idx):
            t.insert(co[i], int(i))
        t.balance()
        trees[k] = t
    groups = {}
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        acc = {}
        for (_, i, dist) in trees[piece_of[v.index]].find_n(p, 8):
            f = 1.0 / max(dist, 0.004) ** 2
            for g, w in weights[i].items():
                acc[g] = acc.get(g, 0.0) + w * f
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(w for _, w in top)
        for g, w in top:
            if g not in groups:
                groups[g] = ob.vertex_groups.new(name=g)
            groups[g].add([v.index], w / tot, "REPLACE")
    ob.parent = rig
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig


def tuck_key(body, sweater, co, dom, marks, lip):
    """The body's `under_sweater` key, for the game to turn on with the sweater: the skin it covers
    goes in by TUCK along its normal, and anything that would still reach the knit (a satchel, a
    jacket's collar, braces) is pulled in to MARGIN inside it. Not the head, hands or legs below the
    hem."""
    from mathutils.bvhtree import BVHTree
    if not body.data.shape_keys:
        body.shape_key_add(name="Basis")
    key = body.shape_key_add(name="under_sweater", from_mix=False)
    me = sweater.data
    mw = sweater.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons if not any(i in lip for i in p.vertices)]
    tree = BVHTree.FromPolygons(verts, polys)
    skip = np.isin(dom, ["Head", "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftToes", "RightToes"])
    bw = body.matrix_world
    bwi = bw.inverted()
    moved = 0
    for v in body.data.vertices:
        i = v.index
        if skip[i] or not (marks["hem_z"] - 0.06 < co[i, 2] < marks["collar_z"]):
            continue
        p = bw @ v.co
        hit = tree.find_nearest(p, 0.25)
        if hit[0] is None:
            continue
        loc, n = hit[0], hit[1]
        if (p - loc).dot(n) < -0.08:          # well inside already, or under some other part
            continue
        q = p - (bw.to_3x3() @ v.normal).normalized() * (ARM_TUCK if "Arm" in str(dom[i]) else TUCK)
        if (q - loc).dot(n) > -MARGIN:
            q = q - n * ((q - loc).dot(n) + MARGIN)
            moved += 1
        key.data[i].co = bwi @ q
    print("[sweater] under_sweater: %d points pulled in under the knit" % moved)
    return key


# --- textures and materials ---------------------------------------------------------------------------

def fibre_map(n=TILE * TILE_PX):
    """The fleece scan's speckle, squeezed to the tile's size (the scan tiles, so this does too)."""
    p = os.path.join(WEB, "knitted_fleece", "knitted_fleece_diff_1k.jpg")
    img = bpy.data.images.load(p)
    img.scale(n, n)
    px = np.empty(n * n * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    f = px.reshape(n, n, 4)[::-1, :, :3].mean(axis=2)
    return np.clip(1.0 + (f / f.mean() - 1.0) * 2.0, 0.85, 1.15)


def design_map(sw, reg, marks):
    """One design's colour map: each stitch's colour (PX pixels a side), a touch lighter or darker
    stitch by stitch, as hand-spun yarn is. The stitches' shapes come from the tiles."""
    pal = np.array(PT.palette(sw))
    parts = {k: (r["h"], r["w"]) for k, r in reg.items()}
    grids = sw["draw"](parts, marks)
    rgb = np.zeros((ATLAS[1], ATLAS[0], 3))
    rgb[:] = pal[0]
    rng = np.random.default_rng(3)
    for k, r in reg.items():
        g = grids[k]
        c = pal[g] * rng.uniform(0.95, 1.04, size=g.shape)[..., None]
        c = np.repeat(np.repeat(c, PX, axis=0), PX, axis=1)
        rgb[r["y"]:r["y"] + c.shape[0], r["x"]:r["x"] + c.shape[1]] = c
    return np.clip(rgb, 0, 1)


def rib_mask(reg):
    """Shared by every design: 1 where the knit is rib (hem, collar, cuffs), 0 where it's stockinette."""
    m = np.zeros((ATLAS[1], ATLAS[0], 3))
    for k, r in reg.items():
        if k in ("hem", "collar", "cuff"):
            m[r["y"] - 2:r["y"] + r["h"] * PX + 2, r["x"] - 2:r["x"] + r["w"] * PX + 2] = 1.0
    return m


def stitch_tiles(fibre):
    """The two knit tiles every design shares: stockinette and rib, TILE stitches by TILE rows, as a
    grey shade (the colour map is multiplied by it) and a normal map."""
    out = {}
    for kind, f in (("stockinette", PT.stitch_maps), ("rib", PT.rib_maps)):
        grid = np.zeros((TILE + 2, TILE), dtype=int)          # a row more each end, then cut: it tiles
        rgb, h = f(grid, [(1.0, 1.0, 1.0)], px=TILE_PX, fibre=None)
        rgb, h = rgb[TILE_PX:-TILE_PX], h[TILE_PX:-TILE_PX]
        if fibre is not None:
            n = rgb.shape[0]
            rgb = rgb * fibre[:n, :n][..., None]
        rgb = 0.8 + 0.2 * rgb       # the shade only darkens the gaps a little: the relief does the rest
        out[kind] = (np.clip(rgb, 0, 1), normal_from_height(h, 14.0))
    return out


def save_png(name, rgb, folder, data=False):
    os.makedirs(folder, exist_ok=True)
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb[::-1], 0.0, 1.0)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(folder, name + ".png")
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    img = bpy.data.images.load(os.path.join(folder, name + ".png"))     # read back as a file (Cycles)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def normal_from_height(hgt, strength=2.0):
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * strength
    dy = (np.roll(hgt, 1, axis=0) - np.roll(hgt, -1, axis=0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def wool_material(design, mask, tiles):
    """For the review renders (the game builds its own, the same way): the design's colour times the
    knit tile's shade, rib or stockinette by the mask; the tile's normal map, on the Stitches UVs."""
    m = bpy.data.materials.new("Sweater")
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    b = N["Principled BSDF"]
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Sheen Weight"].default_value = 0.15      # wool's soft fuzz at the edges (renders only)
    b.inputs["Sheen Roughness"].default_value = 0.6
    uv2 = N.new("ShaderNodeUVMap")
    uv2.uv_map = "Stitches"

    def tex(img, name, on_uv2=False, data=False, closest=False):
        t = N.new("ShaderNodeTexImage")
        t.name = name
        t.image = img
        if data:
            img.colorspace_settings.name = "Non-Color"
        if closest:
            t.interpolation = "Closest"
        if on_uv2:
            L.new(uv2.outputs["UV"], t.inputs["Vector"])
        return t
    col = tex(design, "colour")
    msk = tex(mask, "mask", data=True, closest=True)
    sc, sn = tex(tiles["stockinette"][0], "stock", True), tex(tiles["stockinette"][1], "stock_n", True, True)
    rc, rn = tex(tiles["rib"][0], "rib", True), tex(tiles["rib"][1], "rib_n", True, True)
    shade = N.new("ShaderNodeMix")
    shade.data_type = "RGBA"
    L.new(msk.outputs["Color"], shade.inputs["Factor"])
    L.new(sc.outputs["Color"], shade.inputs["A"])
    L.new(rc.outputs["Color"], shade.inputs["B"])
    mul = N.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    L.new(col.outputs["Color"], mul.inputs["A"])
    L.new(shade.outputs["Result"], mul.inputs["B"])
    L.new(mul.outputs["Result"], b.inputs["Base Color"])
    L.new(mul.outputs["Result"], b.inputs["Sheen Tint"])
    nmix = N.new("ShaderNodeMix")
    nmix.data_type = "RGBA"
    L.new(msk.outputs["Color"], nmix.inputs["Factor"])
    L.new(sn.outputs["Color"], nmix.inputs["A"])
    L.new(rn.outputs["Color"], nmix.inputs["B"])
    nm = N.new("ShaderNodeNormalMap")
    nm.uv_map = "Stitches"
    nm.inputs["Strength"].default_value = 1.0
    L.new(nmix.outputs["Result"], nm.inputs["Color"])
    L.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


# --- review renders ----------------------------------------------------------------------------------

def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    try:
        bpy.context.preferences.addons["cycles"].preferences.compute_device_type = "METAL"
        bpy.context.preferences.addons["cycles"].preferences.get_devices()
        for d in bpy.context.preferences.addons["cycles"].preferences.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 700, 900
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.82, 0.82, 0.84, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    for nm, en, rot in (("key", 2.6, (0.75, 0.1, -0.6)), ("rim", 1.2, (1.1, 0.0, 2.6))):
        ld = bpy.data.lights.new(nm, "SUN")
        ld.energy = en
        ld.angle = 0.2
        lo = bpy.data.objects.new(nm, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = rot
    cd = bpy.data.cameras.new("cam")
    cd.lens = 85
    co = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


CAM_Z = [1.08]


def shoot(cam, path, yaw, target=None, dist=3.2, elev=6.0):
    """A render from `yaw` degrees round from the front, aimed at the middle of the sweater (set per
    character in main)."""
    target = target or (0, 0, CAM_Z[0])
    a, e = math.radians(yaw), math.radians(elev)
    t = Vector(target)
    cam.location = t + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --- main ----------------------------------------------------------------------------------------------

GAME = os.path.join(ROOT, "assets", "sweaters")


def game_export(cid, sw_ob, rig, body, tex):
    """What the game loads (scripts/sweaters.gd builds the wool material itself):
    assets/sweaters/<cid>_sweater.glb, the sweater skinned to the rig with a plain material;
    <cid>_tuck.json, the body's under_sweater key as points (the body's own coordinates, Y up) and how
    far each moves, since the game's character models don't carry the key; and the textures."""
    os.makedirs(os.path.join(GAME, "textures"), exist_ok=True)
    wool = sw_ob.data.materials[0]
    plain = bpy.data.materials.new("Wool")
    sw_ob.data.materials[0] = plain
    for o in bpy.context.view_layer.objects:
        o.select_set(o in (sw_ob, rig))
    bpy.ops.export_scene.gltf(filepath=os.path.join(GAME, cid + "_sweater.glb"), export_format="GLB",
                              use_selection=True, export_animations=False, export_skins=True,
                              export_morph=False, export_yup=True, export_materials="PLACEHOLDER")
    sw_ob.data.materials[0] = wool
    kb = body.data.shape_keys.key_blocks
    base, key = kb[0].data, kb["under_sweater"].data
    pts = []
    for i, v in enumerate(body.data.vertices):
        p, q = base[i].co, key[i].co
        d = q - p
        if d.length > 1e-5:
            pts += [round(p.x, 5), round(p.z, 5), round(-p.y, 5), round(d.x, 5), round(d.z, 5), round(-d.y, 5)]
    with open(os.path.join(GAME, cid + "_tuck.json"), "w", encoding="utf-8") as f:
        json.dump({"about": "under_sweater for %s: x, y, z, dx, dy, dz per point (art/world_assets/sweater/build.py)" % cid,
                   "points": pts}, f, separators=(",", ":"))
    for name in os.listdir(tex):
        if name.endswith(".png"):
            shutil.copyfile(os.path.join(tex, name), os.path.join(GAME, "textures", name))
    write_catalogue()
    print("[sweater] game: %s_sweater.glb, %d tucked points" % (cid, len(pts) // 6))


def write_catalogue():
    """data/sweaters.json: the fifty designs as the game sees them (patterns.py is the source)."""
    designs = [{"id": sw["id"], "name": sw["name"], "stars": sw["stars"], "colours": sw["colours"],
                "about": " ".join((sw["draw"].__doc__ or "").split())} for sw in PT.SWEATERS]
    with open(os.path.join(ROOT, "data", "sweaters.json"), "w", encoding="utf-8") as f:
        json.dump({"_about": "The sweater designs, written by art/world_assets/sweater/build.py from patterns.py: "
                             "don't edit by hand. stars: 1 Common, 2 Rare, 3 Ultra rare, 4 Legendary. Each design's "
                             "colour map is assets/sweaters/textures/<id>.png; scripts/sweaters.gd puts it on a "
                             "character. Names and stars are drafts until Alex approves them.",
                   "designs": designs}, f, indent=1, ensure_ascii=False)
        f.write("\n")


def main(cid, render):
    rig, body = load_char(cid)
    B = bones(rig)
    co, dom, weights = body_points(body)
    out = os.path.join(HERE, "out")
    tex = os.path.join(out, "textures")
    os.makedirs(tex, exist_ok=True)

    trows, ttags, marks = torso_rows(co, dom, B, CHARS[cid].get("neck", 0.06))
    mat = bpy.data.materials.new("tmp")
    tor, tU, tD, tparts, text_ = build_piece("Body", trows, ttags, None, mat)
    sleeves = {}
    for s in SIDES:
        srows, stags, sm = sleeve_rows(co, dom, B, s)
        if s == "Left":     # mirror the winding so both sleeves face out
            srows = [r[::-1] for r in srows]
            srows = [np.vstack([r[-1:], r[:-1]]) for r in srows]
        sleeves[s] = (build_piece(s + "Sleeve", srows, stags, None, mat), srows, stags)

    # one atlas for everything: the parts' sizes in stitches come from Nora
    ext = dict(text_)
    sx = sleeves["Right"][0][4]
    for k in ("sleeve", "cuff"):
        ext[k] = (max(sx[k][0], sleeves["Left"][0][4][k][0]), max(sx[k][1], sleeves["Left"][0][4][k][1]), sx[k][2])
    lay_path = os.path.join(HERE, "layout.json")
    if cid == "nora" or not os.path.exists(lay_path):
        reg = layout({k: (v[0], v[1]) for k, v in ext.items()})
        torso_top = text_["torso"][2]
        kf = NC // 2
        target = B["UpperChest"][0].z - 0.05
        ri = min(range(torso_top, len(trows)), key=lambda i: abs(trows[i][kf][2] - target))
        mk = {"yoke_top": 0, "chest": int(round((tD[ri][kf] - tD[torso_top][kf]) / GAUGE[1]))}
        with open(lay_path, "w", encoding="utf-8") as f:
            json.dump({"atlas": ATLAS, "px": PX, "gauge": GAUGE, "regions": reg, "marks": mk}, f, indent=1)
        del torso_top
    with open(lay_path, encoding="utf-8") as f:
        L = json.load(f)
    reg, mk = L["regions"], L["marks"]

    assign_uvs(tor, tU, tD, tparts, text_, reg)
    for s in SIDES:
        (ob, U, D, parts, e), _, _ = sleeves[s]
        assign_uvs(ob, U, D, parts, ext if False else e, reg)

    # textures: one normal map, one colour map per design
    imgs = {sw["id"]: save_png(sw["id"], design_map(sw, reg, mk), tex) for sw in PT.SWEATERS}
    mask = save_png("sweater_rib_mask", rib_mask(reg), tex, data=True)
    tl = {}
    for kind, (c, n) in stitch_tiles(fibre_map()).items():
        tl[kind] = (save_png("knit_" + kind, c, tex), save_png("knit_" + kind + "_n", n, tex, data=True))
    wool = wool_material(imgs[PT.SWEATERS[0]["id"]], mask, tl)

    # join into one object, which piece each point came from, then settle, smooth and skin
    obs = [tor, sleeves["Right"][0][0], sleeves["Left"][0][0]]
    for o, p, (rws, tg) in zip(obs, ("torso", "Right", "Left"),
                               ((trows, ttags), (sleeves["Right"][1], sleeves["Right"][2]), (sleeves["Left"][1], sleeves["Left"][2]))):
        o.data.materials.clear()
        o.data.materials.append(wool)
        o.vertex_groups.new(name="piece_" + p).add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        n = len(rws[0])
        pins = []
        for i, t in enumerate(tg):
            if t in ("collar", "hem", "cuff") or (o is not tor and i <= 1):
                pins += [i * n + k for k in range(n)]
        o.vertex_groups.new(name="pin").add(pins, 1.0, "REPLACE")
        lips = [0] + [len(rws) - 2, len(rws) - 1] if o is tor else [len(rws) - 2, len(rws) - 1]
        o.vertex_groups.new(name="lip").add([i * n + k for i in lips for k in range(n)], 1.0, "REPLACE")
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = tor
    bpy.ops.object.join()
    sw_ob = bpy.context.view_layer.objects.active
    sw_ob.name = "Sweater"
    sw_ob.data.name = cid + "_sweater"
    sw_ob.data.polygons.foreach_set("use_smooth", [True] * len(sw_ob.data.polygons))
    gi = {g.index: g.name[6:] for g in sw_ob.vertex_groups if g.name.startswith("piece_")}
    li = sw_ob.vertex_groups["lip"].index
    lip = {v.index for v in sw_ob.data.vertices if any(g.group == li for g in v.groups)}
    piece_of = [next(gi[g.group] for g in v.groups if g.group in gi) for v in sw_ob.data.vertices]
    if "--sim" in sys.argv:
        settle(sw_ob, body)
    for g in list(sw_ob.vertex_groups):
        sw_ob.vertex_groups.remove(g)
    skin(sw_ob, rig, co, dom, weights, piece_of)
    marks["collar_z"] = marks["neck_z"] + 0.01
    marks["hem_z"] = B["Hips"][0].z - 0.05
    tuck_key(body, sw_ob, co, dom, marks, lip)

    tris = sum(len(p.vertices) - 2 for p in sw_ob.data.polygons)
    print("[sweater] %s: %d points, %d triangles, regions %s" % (cid, len(sw_ob.data.vertices), tris,
                                                                 {k: (r["w"], r["h"]) for k, r in reg.items()}))
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, cid + "_sweater.blend"))
    for o in bpy.context.view_layer.objects:
        o.select_set(o in (sw_ob, rig))
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, cid + "_sweater.glb"), export_format="GLB",
                              use_selection=True, export_animations=False, export_skins=True,
                              export_morph=False, export_yup=True)
    game_export(cid, sw_ob, rig, body, tex)

    if render:
        rv = os.path.join(HERE, "review")
        os.makedirs(rv, exist_ok=True)
        body.data.shape_keys.key_blocks["under_sweater"].value = 1.0
        CAM_Z[0] = B["Hips"][0].z + 0.26
        cam = setup_render()
        node = wool.node_tree.nodes["colour"]
        want = os.environ.get("SW_DESIGNS", "").split(",") if os.environ.get("SW_DESIGNS") else None
        for sw in PT.SWEATERS[:1] if os.environ.get("SW_ONE") else [w for w in PT.SWEATERS if not want or w["id"] in want]:
            node.image = imgs[sw["id"]]
            views = os.environ.get("SW_VIEWS", "front,back,close").split(",")   # SW_VIEWS=front for a quick catalogue
            if "front" in views:
                shoot(cam, os.path.join(rv, "%s_%s_front.png" % (cid, sw["id"])), -22)
            if "back" in views and not os.environ.get("SW_ONE"):
                shoot(cam, os.path.join(rv, "%s_%s_back.png" % (cid, sw["id"])), 158)
            if "close" in views:
                shoot(cam, os.path.join(rv, "%s_%s_close.png" % (cid, sw["id"])), -15, target=(0.0, 0.0, B["UpperChest"][0].z - 0.1), dist=1.25 * B["UpperChest"][0].z / 1.222)
        node.image = imgs["cranberry"]
        others = [o for o in bpy.context.scene.objects if o.type == "MESH" and o is not sw_ob]
        for o in others:
            o.hide_render = True
        pre = "" if cid == "nora" else cid + "_"
        shoot(cam, os.path.join(rv, pre + "alone_front.png"), 0, elev=4)
        shoot(cam, os.path.join(rv, pre + "alone_side.png"), 90, elev=4)
        for o in others:
            o.hide_render = False


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    who = [a for a in argv if not a.startswith("--")] or ["nora"]
    for c in who:
        main(c, "--render" in argv)
