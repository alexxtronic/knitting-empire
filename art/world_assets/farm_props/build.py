"""Farm props after Alex's reference art: chunky, hand-painted, soft-edged.

    fence_post     a square post with a swirl of end grain on top and silver bolts at the rails
    fence_rails    two gently wavy rails, 1 m long from x = 0 (the game stretches them post to post)
    fence_section  one free-standing section: two posts and two rails (the buyable fence)
    hay_bale       a golden bale of layered straw tufts tied with two twisted ropes
    scarecrow      straw hat with a sunflower, a stitched burlap smile, plaid shirt, patched
                   overalls, straw at the cuffs and hem, on a wooden post

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/farm_props/build.py -- all
"""
import math
import os
import shutil
import sys

import bpy
import numpy as np
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402

TEX = os.path.join(HERE, "tex")
PROPS = os.path.join(K.PROJECT, "assets", "props")
POST_W, POST_H = 0.15, 1.0
RAILS = (0.42, 0.74)  # rail heights
RAIL_H, RAIL_D = 0.13, 0.05


def wood(name="fence_wood", seams=0, seed=91):
    # browner and rougher than the first pass, which read as glossy orange plastic (kiln round 1)
    # no knots: on a post's side they read as glitches (kiln round 2)
    i, n = CL.plank_maps(name, TEX, base="#a65d2c", light="#c98145", dark="#6e3c1d", seams=seams, seed=seed, knots=0)
    return K.textured(name, i, rough=0.82, normal=n, normal_strength=1.1)


def endgrain():
    i, n = CL.endgrain_maps("fence_endgrain", TEX)
    return K.textured("fence_endgrain", i, rough=0.6, normal=n, normal_strength=0.6)


def bolt_mat():
    # steel, not white plastic (kiln round 3)
    m = K.plain("bolt_steel", "#aeb4bc", rough=0.32)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = 0.85
    return m


# --- fence -----------------------------------------------------------------------------------------

def post(x, y, w, ge, bolt, seed=0, h=POST_H):
    rng = np.random.default_rng(seed)
    pts = [Vector((x, y, 0.0)), Vector((x, y, h * 0.5)), Vector((x, y, h - 0.008))]
    ob = CL.beam("post", pts, POST_W, POST_W, w, sides=16, v_scale=2.0, square=0.3)
    # the sawn top: a fan over the post's own top ring, so it matches the outline exactly (kiln
    # round 3: a separately drawn lid sat turned and overhung)
    top_cap(ob, ge, rng.uniform(0, 6.28))
    for z in RAILS:
        for sy in (-1, 1):
            K.ball("bolt", 0.027, (x, y + sy * (POST_W / 2 + 0.002), z), bolt, scale=(1, 0.45, 1), u=12, v=6)


def top_cap(ob, mat, turn):
    co = [ob.matrix_world @ v.co for v in ob.data.vertices]
    zmax = max(c.z for c in co)
    ring = [c for c in co if c.z > zmax - 1e-4]
    cen = sum(ring, Vector()) / len(ring)
    # only the outline: the post's own cap has a centre vertex, which cut a wedge out (kiln round 4)
    rmax = max((c - cen).length for c in ring)
    ring = [c for c in ring if (c - cen).length > rmax * 0.5]
    cen = sum(ring, Vector()) / len(ring)
    ring.sort(key=lambda c: math.atan2(c.y - cen.y, c.x - cen.x))
    size = max(max(abs(c.x - cen.x), abs(c.y - cen.y)) for c in ring) * 2
    ct, st = math.cos(turn), math.sin(turn)
    def uv(c):
        dx, dy = c.x - cen.x, c.y - cen.y
        return (0.5 + (dx * ct - dy * st) / size, 0.5 + (dx * st + dy * ct) / size)
    lift = Vector((0, 0, 0.0012))
    V = [cen + lift] + [cen + (c - cen) * 0.997 + lift for c in ring]
    F, U = [], []
    n = len(ring)
    for j in range(n):
        k = (j + 1) % n
        F.append((0, 1 + j, 1 + k))
        U += [uv(V[0]), uv(V[1 + j]), uv(V[1 + k])]
    return CL._finish_mesh("endgrain", V, F, U, mat, recalc=False, smooth=False)


def rails(x0, x1, y, w, seed=0):
    for k, z in enumerate(RAILS):
        pts = [Vector((x0 + (x1 - x0) * t, y, z)) for t in np.linspace(0, 1, 13)]
        CL.beam("rail", pts, RAIL_D, RAIL_H, w, sides=12, v_scale=2.0, wave=0.009, seed=seed + k, square=0.3)


def build_fence_post():
    post(0, 0, wood(), endgrain(), bolt_mat())


def build_fence_rails():
    rails(0.0, 1.0, 0.0, wood("fence_rail_wood", seed=93))


def build_fence_section():
    w, ge, b = wood(), endgrain(), bolt_mat()
    post(-0.5, 0, w, ge, b, seed=1)
    post(0.5, 0, w, ge, b, seed=2)
    rails(-0.5 + POST_W * 0.2, 0.5 - POST_W * 0.2, 0.0, wood("fence_rail_wood", seed=93), seed=5)  # the ends stay inside the posts


# --- hay bale --------------------------------------------------------------------------------------

def rounded_rect(rx, ry, rc, step):
    """Points round a rounded rectangle (half sizes rx, ry, corner radius rc), about `step` apart,
    with outward normals and the running length."""
    pts, nrm = [], []
    segs = [((rx - rc, -ry + rc), -90, 0), ((rx - rc, ry - rc), 0, 90), ((-rx + rc, ry - rc), 90, 180), ((-rx + rc, -ry + rc), 180, 270)]
    for (cx, cy), a0, a1 in segs:
        for k in range(4):  # the corner arc
            a = math.radians(a0 + (a1 - a0) * k / 4)
            pts.append(Vector((cx + rc * math.cos(a), cy + rc * math.sin(a), 0)))
            nrm.append(Vector((math.cos(a), math.sin(a), 0)))
        a = math.radians(a1)
        p0 = Vector((cx + rc * math.cos(a), cy + rc * math.sin(a), 0))
        nxt = segs[(segs.index(((cx, cy), a0, a1)) + 1) % 4]
        b = math.radians(nxt[1])
        p1 = Vector((nxt[0][0] + rc * math.cos(b), nxt[0][1] + rc * math.sin(b), 0))
        m = max(1, round((p1 - p0).length / step))
        for k in range(m):
            pts.append(p0.lerp(p1, k / m))
            nrm.append(Vector((math.cos(a), math.sin(a), 0)))
    pts.append(pts[0].copy())
    nrm.append(nrm[0].copy())
    run = [0.0]
    for p, q in zip(pts, pts[1:]):
        run.append(run[-1] + (q - p).length)
    return pts, nrm, run


def fringe(V, F, U, roots, outs, downs, lengths, flare, lift, u_at, rng, floor=0.004):
    """A strip of straw hanging from a line of roots: each column bends out (flare) and down, the
    tips alternating long and short so the lower edge is ragged like a pulled-apart flake."""
    cols = []
    for r, o, d, L in zip(roots, outs, downs, lengths):
        t = o.cross(d).normalized() * rng.uniform(-0.012, 0.012)
        mid = r + d * L * 0.5 + o * (lift + flare * L * 0.35) + t * 0.5
        tip = r + d * L + o * (lift * 0.6 + flare * L) + t
        mid.z, tip.z = max(mid.z, floor), max(tip.z, floor)
        cols.append((r, mid, tip))
    base = len(V)
    for c in cols:
        V += list(c)
    for i in range(len(cols) - 1):
        a, b = base + 3 * i, base + 3 * (i + 1)
        for j in range(2):
            F.append((a + j, b + j, b + j + 1, a + j + 1))
            U += [(u_at[i], j / 2), (u_at[i + 1], j / 2), (u_at[i + 1], (j + 1) / 2), (u_at[i], (j + 1) / 2)]


def straw_card(V, F, U, root, d, o, length, width, flare, u0, tex_w, floor=0.004, root_w=1.0):
    """One bundle of straw: a narrow card from root along d, bending out along o, tapering to a
    point. Many of them, overlapping, make a soft ragged fringe (kiln round 1: regular shared
    triangles read as icicles)."""
    side = d.cross(o).normalized()
    pts = []
    for t, wf in ((0.0, root_w), (0.45, 0.95), (0.8, 0.55)):
        c = root + d * length * t + o * flare * length * t * t
        c.z = max(c.z, floor)
        pts += [c - side * width * wf / 2, c + side * width * wf / 2]
    tip = root + d * length + o * flare * length
    tip.z = max(tip.z, floor)
    b = len(V)
    V += pts + [tip]
    uw = width / tex_w
    for j in range(2):
        F.append((b + 2 * j, b + 2 * j + 1, b + 2 * j + 3, b + 2 * j + 2))
        v0, v1 = (0.0, 0.45, 0.8)[j], (0.0, 0.45, 0.8)[j + 1]
        U += [(u0, v0), (u0 + uw, v0), (u0 + uw, v1), (u0, v1)]
    F.append((b + 4, b + 5, b + 6))
    U += [(u0, 0.8), (u0 + uw, 0.8), (u0 + uw / 2, 1.0)]


def build_hay_bale():
    L, D, H = 0.95, 0.48, 0.4  # a small square bale: about 2.4 times as long as it is high
    i, n = CL.straw_maps("hay_bale_straw", TEX, base="#f0a51a", light="#ffd34d", dark="#b06a08")
    straw = K.textured("hay_bale_straw", i, rough=0.75, normal=n, normal_strength=0.7)
    i, n = CL.straw_maps("hay_core", TEX, base="#c98a1c", light="#e8b443", dark="#8a5a0c", seed=103)
    core = K.textured("hay_core", i, rough=0.85, normal=n, normal_strength=0.7)
    hx, hy, top = L / 2 - 0.03, D / 2 - 0.03, H - 0.025
    box = K.box("core", (2 * hx, 2 * hy, top), (0, 0, top / 2), core, bevel=0.05, seg=3)
    K.uv_box(box, 4.0)
    rng = np.random.default_rng(7)
    V, F, U = [], [], []
    tex_w = 0.2  # metres of straw per texture width
    dn = Vector((0, 0, -1))
    # layered flakes round the four sides, from the top down to the ground: overlapping bundles
    # of straw at random lengths and slants, the top one curling a little over the edge
    rows = 7
    for k in range(rows):
        z = top + 0.008 - k * (top - 0.02) / (rows - 1) * 0.97
        pts, nrm, run = rounded_rect(hx + 0.003, hy + 0.003, 0.05, 0.013)
        for j in range(len(pts) - 1):
            o = nrm[j]
            slant = o.cross(dn).normalized() * rng.uniform(-0.3, 0.3)
            d = (dn + slant).normalized()
            Lc = (0.09 if k < rows - 1 else 0.07) * rng.uniform(0.55, 1.15)
            pinch = 1.0 if min(abs(pts[j].x - 0.22), abs(pts[j].x + 0.22)) < 0.035 else 0.0  # the rope bites in
            root = pts[j] + o * (rng.uniform(0.0, 0.006) - 0.008 * pinch) + Vector((0, 0, z + (rng.uniform(0.0, 0.014) if k == 0 else rng.uniform(-0.01, 0.01))))
            straw_card(V, F, U, root, d, o, Lc, rng.uniform(0.018, 0.028), 0.2 if k == 0 else 0.12, run[j] / tex_w, tex_w)
    # the top: flakes lying flat, from the middle out to each end, overlapping like shingles
    up = Vector((0, 0, 1))
    for half in (-1, 1):
        for k in range(6):
            x0 = half * (-0.04 + k * 0.08)
            for j in range(40):
                y = -hy - 0.01 + (2 * hy + 0.02) * (j + rng.uniform(0, 1)) / 40
                d = Vector((half, rng.uniform(-0.25, 0.25), 0)).normalized()
                # shingled from the middle out, each band's root under the band inside it, lying
                # flat with a tapered root (kiln round 3: square cut chips stood up like confetti)
                root = Vector((x0 + rng.uniform(-0.02, 0.02), y, top + 0.004 + 0.002 * (5 - k)))
                straw_card(V, F, U, root, d, up, 0.12 * rng.uniform(0.7, 1.2), rng.uniform(0.018, 0.028), 0.03, (y + hy) / tex_w, tex_w, root_w=0.35)
    # tips past the ends droop down over the edge
    for p in V:
        if abs(p.x) > hx - 0.01 and p.z > top - 0.005:
            p.z -= (abs(p.x) - (hx - 0.01)) * 0.9
    CL._finish_mesh("straw", V, F, U, straw, recalc=False)
    # loose stalks poking out here and there
    blades = []
    for k in range(40):
        side = rng.integers(1, 3)  # the sides only (kiln round 2: stalks on top read as black slivers)
        if False:
            pass
        else:
            sy = 1 if side == 1 else -1
            p = Vector((rng.uniform(-hx, hx), sy * (hy + 0.03), rng.uniform(0.08, top)))
            o = Vector((0, sy, 0))
            d = Vector((rng.uniform(-0.3, 0.3), sy * 0.2, -1)).normalized()
        blades.append(CL.tuft("stalk", p, d, o, rng.uniform(0.04, 0.07), rng.uniform(0.008, 0.013), straw, curl=0.2, segs=2))
    CL.tufts_mesh("stalks", blades, straw)
    # two twisted ropes round the middle, sitting in the straw
    ri, rn = CL.yarn_maps("hay_rope", TEX, "#a3622a", plies=2, twists=3)
    rope = K.textured("hay_rope", ri, rough=0.8, normal=rn, normal_strength=1.0)
    for x in (-0.22, 0.22):
        ry, rz = hy + 0.014, (top + 0.02)  # sunk into the straw (kiln round 3)
        pts = []
        for k in range(49):
            a = 2 * math.pi * k / 48
            c, s_ = math.cos(a), math.sin(a)
            yy = math.copysign(abs(c) ** 0.15, c) * ry
            zz = top / 2 + math.copysign(abs(s_) ** 0.15, s_) * (rz / 2 + 0.004)
            pts.append(Vector((x, yy, max(0.02, zz))))
        CL.tube("rope", pts, [0.024] * len(pts), rope, sides=8, v_scale=8.0, caps=False)


# --- scarecrow -------------------------------------------------------------------------------------

def head_maps(n=512):
    """Burlap with a seam down one side, closed happy eyes and a stitched smile, facing -Y (u = 0.75)."""
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = 1 - yy / n
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 3) + 0.25 * np.sin(2 * np.pi * yy / 3)
    mott = K.tile_noise(n, 0.9, 131)
    rgb = CL.C("#e3c48e") * (0.93 + 0.08 * weave[..., None]) * (0.95 + 0.07 * mott[..., None])
    ink = np.zeros_like(u)
    sx = 2.4  # u is squashed round the head: stretch it so the features are round

    def arc(cu, cv, rad, top, width=0.006, span=1.0):
        du = (u - cu) * sx
        dv = v - cv
        r = np.hypot(du, dv)
        ang = np.arctan2(dv, du)
        keep = (dv > 0) if top else (dv < 0)
        return np.exp(-((r - rad) / width) ** 2) * keep * (np.abs(np.cos(ang)) < span)

    for eu in (0.75 - 0.045, 0.75 + 0.045):
        ink = np.maximum(ink, arc(eu, 0.44, 0.055, True, 0.018, 0.95))
    smile = arc(0.75, 0.4, 0.1, False, 0.018, 0.9)
    ink = np.maximum(ink, smile)
    for k in range(-2, 3):  # stitches across the smile
        a = -math.pi / 2 + k * 0.42
        cu, cv = 0.75 + 0.1 * math.cos(a) / sx, 0.4 + 0.1 * math.sin(a)
        d = np.hypot((u - cu) * sx * math.sin(a) - (v - cv) * math.cos(a) * 0, (v - cv))
        tick = np.exp(-(((u - cu) * sx) / 0.006) ** 2) * (np.abs(v - cv) < 0.018) * 0.85
        ink = np.maximum(ink, tick)
    # the seam: a stitched line down the left of the face
    seam_u = 0.75 - 0.11
    seam = np.exp(-(((u - seam_u) * sx) / 0.004) ** 2) * (v > 0.22) * (v < 0.9)
    ink = np.maximum(ink, seam * 0.8)
    for k in range(12):
        cv = 0.26 + k * 0.055
        st = np.exp(-((v - cv) / 0.004) ** 2) * (np.abs((u - seam_u) * sx) < 0.02)
        ink = np.maximum(ink, st)
    rgb = CL.mix(rgb, CL.C("#5a3418"), np.clip(ink, 0, 1)[..., None])
    cheek = np.exp(-(((u - 0.75) * sx - 0.0) ** 2 + 0) / 0.01)  # noqa: F841 (kept simple: no blush)
    return K.save_image("scarecrow_face", rgb, TEX), K.save_image("scarecrow_face_n", K.normal_from_height(weave * 0.5 - ink * 0.6, 2.0), TEX)


def surf_hit(objs, origin, direction):
    """The nearest hit of a ray on any of objs (balls and tubes: no rotation), as (point, normal)."""
    bpy.context.view_layer.update()
    best = None
    origin, direction = Vector(origin), Vector(direction).normalized()
    for ob in objs:
        ok, loc, nrm, _ = ob.ray_cast(origin - ob.location, direction)
        if ok:
            p = loc + ob.location
            d = (p - origin).length
            if best is None or d < best[0]:
                best = (d, p, nrm.normalized())
    assert best is not None, ("no hit", tuple(origin), tuple(direction))
    return best[1], best[2]


def surface_sheet(name, objs, ray, nu, nv, off, thick, mat, uv_scale=(1.0, 1.0)):
    """A cloth panel laid on the surface of objs (the bib, straps, pocket, patches): ray(u, v) gives
    the ray for each grid point, u and v running 0..1. The panel stands off by off and is thick."""
    grid = [[surf_hit(objs, *ray(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
    V, F, U = [], [], []
    W = nv + 1
    def idx(layer, i, j):
        return layer * (nu + 1) * W + i * W + j
    for layer, o in ((0, off), (1, off - thick)):
        for i in range(nu + 1):
            for j in range(nv + 1):
                p, n = grid[i][j]
                V.append(p + n * o)
    def quad(a, b, c, d, uva):
        F.append((a, b, c, d))
        U.extend(uva)
    for layer in (0, 1):
        for i in range(nu):
            for j in range(nv):
                q = [idx(layer, i, j), idx(layer, i + 1, j), idx(layer, i + 1, j + 1), idx(layer, i, j + 1)]
                uv = [(i / nu * uv_scale[0], j / nv * uv_scale[1]), ((i + 1) / nu * uv_scale[0], j / nv * uv_scale[1]),
                      ((i + 1) / nu * uv_scale[0], (j + 1) / nv * uv_scale[1]), (i / nu * uv_scale[0], (j + 1) / nv * uv_scale[1])]
                quad(*(q if layer == 0 else q[::-1]), uv if layer == 0 else uv[::-1])
    edge = [(i, 0) for i in range(nu)] + [(nu, j) for j in range(nv)] + [(i, nv) for i in range(nu, 0, -1)] + [(0, j) for j in range(nv, 0, -1)]
    for k, (i, j) in enumerate(edge):
        i2, j2 = edge[(k + 1) % len(edge)]
        t = thick * 4
        quad(idx(0, i, j), idx(0, i2, j2), idx(1, i2, j2), idx(1, i, j), [(k * t, 0), ((k + 1) * t, 0), ((k + 1) * t, t), (k * t, t)])
    return CL._finish_mesh(name, V, F, U, mat)


def on_surface(objs, origin, direction, lift):
    """A point lift above the surface and the rotation (degrees) that turns local +Z out of it."""
    p, n = surf_hit(objs, origin, direction)
    e = n.to_track_quat("Z", "Y").to_euler()
    return p + n * lift, n, tuple(math.degrees(a) for a in e)


def straw_ring(blades, centre, radius, z, out_tilt, length, width, mat, n, rng, down=True, axis="z", droop=0.0):
    """A fringe of straw round a circle (cuffs, collar, hem, hair)."""
    c = Vector(centre)
    for k in range(n):
        a = 2 * math.pi * (k + rng.uniform(-0.3, 0.3)) / n
        if axis == "z":
            radial = Vector((math.cos(a), math.sin(a), 0))
            root = c + radial * radius + Vector((0, 0, z))
            d = (radial * out_tilt * rng.uniform(0.5, 1.5) + Vector((0, 0, -1 if down else 1))).normalized()
        else:  # round the x axis (a sleeve cuff), pointing outward along x
            sgn = 1 if axis == "+x" else -1
            radial = Vector((0, math.cos(a), math.sin(a)))
            root = c + radial * radius
            d = (Vector((sgn, 0, -droop * rng.uniform(0.6, 1.3))) + radial * out_tilt).normalized()
        blades.append(CL.tuft("s", root, d, radial, length * rng.uniform(0.6, 1.4), width * rng.uniform(0.7, 1.3), mat, curl=rng.uniform(0.05, 0.3)))


def build_scarecrow():
    rng = np.random.default_rng(17)
    i, n = CL.plank_maps("scarecrow_wood", TEX, base="#8f6240", light="#b0835a", dark="#5e3f26", seed=95)
    w = K.textured("scarecrow_wood", i, rough=0.85, normal=n, normal_strength=1.1)
    ge = endgrain()
    i, n = CL.straw_maps("hay_straw", TEX)
    straw = K.textured("hay_straw", i, rough=0.75, normal=n, normal_strength=0.6)
    i, n = CL.plaid_maps("scarecrow_plaid", TEX)
    plaid = K.textured("scarecrow_plaid", i, rough=0.85, normal=n, normal_strength=0.4)
    i, n = CL.cloth_maps("scarecrow_denim", TEX, "#5f6f9a", seed=141, weave_px=2, rough=0.05)
    denim = K.textured("scarecrow_denim", i, rough=0.9, normal=n, normal_strength=0.35)
    i, n = CL.cloth_maps("scarecrow_burlap", TEX, "#dcc08c", seed=143, weave_px=2, rough=0.07)
    burlap = K.textured("scarecrow_burlap", i, rough=0.9, normal=n, normal_strength=0.8)
    i, n = head_maps()
    face = K.textured("scarecrow_face", i, rough=0.9, normal=n, normal_strength=0.4)
    i, n = CL.straw_maps("scarecrow_hat", TEX, base="#e2ad4c", light="#f6d283", dark="#a8741f", strands=90, seed=147)
    hat = K.textured("scarecrow_hat", i, rough=0.8, normal=n, normal_strength=1.0)
    band = K.plain("scarecrow_band", "#c2402c", rough=0.8)
    pocket = K.plain("scarecrow_pocket", "#c79a62", rough=0.85)
    patch_g = K.plain("scarecrow_patch_green", "#7d9a3a", rough=0.85)
    patch_o = K.plain("scarecrow_patch_orange", "#d9622c", rough=0.85)
    button = K.plain("scarecrow_button", "#e2a43a", rough=0.5)
    thread = K.plain("scarecrow_thread", "#6b4426", rough=0.8)
    petal = K.plain("sunflower_petal", "#f7c21c", rough=0.6)
    disc = K.plain("sunflower_disc", "#6b3d17", rough=0.8)
    leaf = K.plain("sunflower_leaf", "#5c9a34", rough=0.6)
    rope_i, rope_n = CL.yarn_maps("hay_rope", TEX, "#c8a46a", plies=2, twists=3)
    rope = K.textured("scarecrow_rope", rope_i, rough=0.8, normal=rope_n)
    blades = []

    # the post and the arm pole
    # the post stops inside the head; the arm pole runs down the middle of the sleeves (kiln round 1:
    # it showed through their backs)
    CL.beam("post", [Vector((0, 0.0, 0)), Vector((0, 0.0, 0.7)), Vector((0, 0.0, 1.36))], 0.1, 0.1, w, sides=16, v_scale=2.5, square=0.5)
    CL.beam("pole", [Vector((-0.65, 0.0, 1.17)), Vector((0, 0.0, 1.17)), Vector((0.65, 0.0, 1.17))], 0.065, 0.065, w, sides=12, v_scale=2.5, square=0.8)
    for sx in (-1, 1):
        K.ball("poleend", 1.0, (sx * 0.652, 0.0, 1.17), ge, scale=(0.004, 0.033, 0.033), u=12, v=6)
    # shirt: body and sleeves
    shirt = K.ball("shirt", 1.0, (0, 0, 1.06), plaid, scale=(0.2, 0.13, 0.2), u=20, v=12, boxy=0.75)
    K.uv_box(shirt, 3.0)
    for sx in (-1, 1):
        pts = [Vector((sx * 0.12, 0.0, 1.15)), Vector((sx * 0.3, 0.0, 1.165)), Vector((sx * 0.5, 0.0, 1.17))]
        CL.tube("sleeve", pts, [0.085, 0.08, 0.075], plaid, sides=12, v_scale=3.0)
        CL.tube("cuff", [Vector((sx * 0.49, 0, 1.17)), Vector((sx * 0.56, 0, 1.17))], [0.085, 0.085], burlap, sides=14, v_scale=4.0)
        straw_ring(blades, (sx * 0.56, 0, 1.17), 0.06, 0, 0.12, 0.1, 0.028, straw, 22, rng, axis="+x" if sx > 0 else "-x", droop=0.6)
    # collar, a rope tie
    straw_ring(blades, (0, 0, 0), 0.1, 1.24, 1.2, 0.09, 0.03, straw, 26, rng)
    CL.tube("tie", [Vector((-0.11, -0.05, 1.255)), Vector((0, -0.11, 1.245)), Vector((0.11, -0.05, 1.255))], [0.012] * 3, rope, sides=6, v_scale=10)
    K.ball("knot", 0.024, (0, -0.115, 1.24), rope, u=8, v=6)
    for sx in (-1, 1):
        CL.tube("tieend", CL.bezier((0, -0.115, 1.235), (sx * 0.02, -0.13, 1.2), (sx * 0.04, -0.14, 1.16), (sx * 0.05, -0.135, 1.13), n=6), [0.01] * 7, rope, sides=6, v_scale=10)
    # overalls: seat and shorts, a bib, straps, buttons, a pocket and two patches
    overalls = K.ball("overalls", 1.0, (0, 0, 0.82), denim, scale=(0.2, 0.135, 0.17), u=20, v=12, boxy=0.7)
    K.uv_box(overalls, 3.0)
    legs = []
    for sx in (-1, 1):
        legs.append(CL.tube("leg", [Vector((sx * 0.09, 0, 0.76)), Vector((sx * 0.1, -0.005, 0.66))], [0.1, 0.105], denim, sides=14, v_scale=3.0))
        CL.tube("legcuff", [Vector((sx * 0.1, -0.005, 0.67)), Vector((sx * 0.1, -0.005, 0.635))], [0.112, 0.112], denim, sides=14, v_scale=3.0)
        straw_ring(blades, (sx * 0.1, -0.005, 0), 0.07, 0.64, 0.25, 0.13, 0.03, straw, 20, rng)
    # the bib, straps, pocket and patches are laid on the cloth underneath (kiln round 1: the bib
    # floated in front of the shirt and the straps stopped short of the shoulders)
    body = [shirt, overalls]
    def front(x0, x1, z0, z1, taper=0.0, tilt=0.0):
        def ray(u, v):
            half = (x1 - x0) / 2 * (1 - taper * v)
            x = (x0 + x1) / 2 + (u * 2 - 1) * half
            z = z0 + (z1 - z0) * v + math.sin(math.radians(tilt)) * (u - 0.5) * (x1 - x0)
            return (x, -1.0, z), (0, 1, 0)
        return ray
    BIB_OFF, BIB_T = 0.005, 0.012
    surface_sheet("bib", body, front(-0.125, 0.125, 0.9, 1.15, taper=0.12), 8, 8, BIB_OFF, BIB_T, denim, (2.0, 2.0))
    surface_sheet("pocket", body, front(-0.055, 0.055, 0.95, 1.045), 4, 4, BIB_OFF + 0.007, 0.008, pocket, (1.0, 1.0))
    for sx in (-1, 1):
        x = sx * 0.095
        def strap(u, v, x=x):
            th = math.radians(28 + v * 195) # from the bib top, over the shoulder, down the back
            r = Vector((0, -math.cos(th), math.sin(th)))
            return Vector((x + (u - 0.5) * 0.045, 0, 1.06)) + r * 1.0, -r
        surface_sheet("strap", body, strap, 1, 16, BIB_OFF + 0.002, 0.009, denim, (0.5, 4.0))
        p, n, rot = on_surface(body, (x, -1, 1.12), (0, 1, 0), BIB_OFF + 0.01)
        K.cyl("button", 0.022, 0.022, 0.01, tuple(p), button, verts=14, rot=rot)
        q = n.to_track_quat("Z", "Y")
        for d in (45, -45):
            e = (q @ Quaternion((0, 0, 1), math.radians(d))).to_euler()
            K.box("x", (0.028, 0.005, 0.004), tuple(p + n * 0.006), thread, bevel=0, rot=tuple(math.degrees(a) for a in e))
    # the patches sit on the shorts' fronts
    surface_sheet("patch", legs + [overalls], front(-0.135, -0.06, 0.685, 0.755, tilt=8), 3, 3, 0.002, 0.006, patch_g, (1.0, 1.0))
    surface_sheet("patch", legs + [overalls], front(0.075, 0.135, 0.68, 0.745, tilt=-10), 3, 3, 0.002, 0.006, patch_o, (1.0, 1.0))
    # a patch on the seat at the back, so the back isn't plain (kiln round 2)
    def back(x0, x1, z0, z1):
        def ray(u, v):
            return ((x0 + (x1 - x0) * u, 1.0, z0 + (z1 - z0) * v), (0, -1, 0))
        return ray
    surface_sheet("patch", [overalls], back(0.02, 0.1, 0.8, 0.88), 3, 3, 0.002, 0.006, patch_o, (1.0, 1.0))
    # head: burlap with the face, straw hair under the brim
    prof = [(0.0, -0.16)]
    for k in range(1, 12):
        ph = -math.pi / 2 + math.pi * k / 12
        prof.append((0.165 * math.cos(ph), 0.16 * math.sin(ph)))
    prof.append((0.0, 0.16))
    K.lathe("head", prof, face, steps=28, loc=(0, 0, 1.42), sharp=80)
    straw_ring(blades, (0, 0.03, 0), 0.14, 1.54, 1.1, 0.075, 0.03, straw, 34, rng)
    # hat: a floppy scalloped brim, a crown, a red band and a sunflower
    brim = K.lathe("brim", [(0.0, 0.0), (0.12, 0.004), (0.24, -0.012), (0.31, -0.04), (0.3, -0.05), (0.23, -0.025), (0.12, -0.012), (0.0, -0.01)], hat, steps=72, loc=(0, 0, 1.56), u_rep=4.0, sharp=89)
    for vv in brim.data.vertices:
        a = math.atan2(vv.co.y, vv.co.x)
        r = math.hypot(vv.co.x, vv.co.y)
        if r > 0.2:
            vv.co.z += 0.012 * math.sin(a * 6) * (r - 0.2) / 0.1 + 0.02 * math.sin(a * 2 + 1)
    K.lathe("crown", [(0.0, 0.0), (0.15, 0.0), (0.149, 0.07), (0.142, 0.11), (0.125, 0.13), (0.07, 0.137), (0.0, 0.128)], hat, steps=28, loc=(0, 0, 1.55), u_rep=3.0, sharp=60)
    # the band: a short ring hugging the crown (kiln round 2: a closed tube left a spike at its seam)
    K.cyl("band", 0.1535, 0.152, 0.03, (0, 0, 1.587), band, verts=40, bevel=0.004, seg=2)
    fc = Vector((-0.1, -0.13, 1.6))
    K.cyl("disc", 0.03, 0.03, 0.015, tuple(fc + Vector((0, -0.01, 0))), disc, verts=16, rot=(80, 0, 20))
    for k in range(12):
        a = 2 * math.pi * k / 12
        p = fc + Vector((math.cos(a) * 0.048, -0.004, math.sin(a) * 0.048))
        K.ball("petal", 1.0, tuple(p), petal, scale=(0.026, 0.008, 0.012), u=8, v=5).rotation_euler = (math.radians(-10), math.radians(-math.degrees(a)), 0)
    for d in (-1, 1):
        K.ball("hatleaf", 1.0, tuple(fc + Vector((d * 0.07, 0.01, -0.03))), leaf, scale=(0.05, 0.008, 0.022), u=8, v=5).rotation_euler = (0, math.radians(d * 25), math.radians(d * 15))
    CL.tufts_mesh("straw", blades, straw)


KINDS = {"fence_post": (build_fence_post, 2500), "fence_rails": (build_fence_rails, 2500), "fence_section": (build_fence_section, 5000),
         "hay_bale": (build_hay_bale, 16000), "scarecrow": (build_scarecrow, 16000)}


def build(name):
    K.reset(name)
    fn, budget = KINDS[name]
    fn()
    out = os.path.join(HERE, "out", name)
    K.finish(name, out, max_tris=budget)
    shutil.copy(os.path.join(out, name + ".glb"), os.path.join(PROPS, name + ".glb"))
    print("COPIED", name)


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
for a in (KINDS if args[0] == "all" else args):
    build(a)
