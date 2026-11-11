"""
CH_Rowan phase 02: the nude body, one continuous skin from the neck down
(torso, arms, hands, legs, feet). No clothing is part of it: garments are separate
objects built by 04_outfit.py, and the head (03_head.py) meets it on the neck ring.

  Blender --background --python build/02_body.py -- --master CH_Rowan_master.blend

The reference shows him clothed, so every body dimension here is inferred: the outfit
measured on the reference, minus cloth thickness and ease. The cage is all quads with a
loop at every joint; one level of subdivision is baked in to make the game mesh.
"""
import bpy, sys, os, math, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from common import *
from spec import *

PHASE = "02_body"
OWNER = "phase:" + PHASE


def log(*a):
    print("[" + PHASE + "]", *a)


# ----------------------------------------------------------------------------- torso
NT = 16            # torso columns: 0 front centre, 4 his left side, 8 back centre
# z, half width, half depth front, half depth back, centre y, superellipse exponent   (all inferred)
TORSO = [
    (0.775, 0.160, 0.092, 0.098, -0.036, 2.60),    # crotch row
    (0.815, 0.168, 0.104, 0.106, -0.035, 2.50),    # hips: 2 cm inside the jeans
    (0.865, 0.166, 0.112, 0.112, -0.033, 2.40),
    (0.920, 0.156, 0.113, 0.104, -0.031, 2.30),
    (0.980, 0.146, 0.113, 0.094, -0.029, 2.25),    # belt line
    (1.050, 0.141, 0.116, 0.088, -0.026, 2.20),    # waist, a soft belly
    (1.120, 0.142, 0.116, 0.090, -0.022, 2.20),
    (1.190, 0.145, 0.113, 0.096, -0.017, 2.25),
    (1.235, 0.147, 0.111, 0.101, -0.013, 2.30),
    (1.275, 0.148, 0.110, 0.105, -0.010, 2.30),    # bottom of the arm opening
    (1.325, 0.149, 0.108, 0.108, -0.006, 2.30),    # chest
    (1.375, 0.147, 0.100, 0.106, -0.002, 2.30),
    (1.420, 0.140, 0.088, 0.100, 0.002, 2.20),     # top of the arm opening, shoulder line
    (1.447, 0.100, 0.070, 0.086, 0.000, 2.10),
    (1.468, 0.072, 0.062, 0.072, -0.006, 2.00),    # base of the neck
    (1.485, 0.0625, 0.0615, 0.0615, -0.010, 2.00),
    (NECK_Z, NECK_R, NECK_R, NECK_R, NECK_Y, 2.00),  # neck ring shared with the head: ref neck width 0.121
]
AH_R0, AH_ROWS = 9, 3            # arm opening: rows 9..12, columns 3..5 (left) and 11..13 (right)
CROTCH_Z = 0.748

# Shoulder fan (his left): rings pivot on the armpit. outer/top point, inner/bottom point, y, half depth
ARM_FAN = [
    ((0.152, 1.420), (0.137, 1.281), 0.000, 0.052),
    ((0.183, 1.400), (0.139, 1.276), -0.001, 0.053),
    ((0.207, 1.366), (0.142, 1.268), -0.003, 0.052),
    ((0.228, 1.318), (0.146, 1.256), -0.006, 0.050),
]
ARM_UPPER = [(0.140, 0.046), (0.200, 0.045), (0.260, 0.041)]         # distance from the shoulder joint, radius
ARM_FORE = [(0.050, 0.043), (0.100, 0.041), (0.145, 0.035)]          # distance from the elbow, radius
NA = 10

# z, centre x, centre y, half width, half depth (his left leg)
LEG = [
    (0.720, 0.094, -0.037, 0.082, 0.092),
    (0.645, 0.103, -0.035, 0.078, 0.088),
    (0.570, 0.108, -0.028, 0.068, 0.078),
    (0.500, 0.113, -0.016, 0.056, 0.064),      # knee
    (0.430, 0.118, -0.002, 0.055, 0.066),
    (0.355, 0.123, 0.012, 0.058, 0.070),       # calf
    (0.280, 0.126, 0.018, 0.048, 0.056),
    (0.205, 0.129, 0.021, 0.039, 0.046),       # above the ankle
]
NL = 12


def torso_ring(z, a, bf, bb, cy, e):
    th = 2 * PI * np.arange(NT) / NT
    s, c = np.sin(th), np.cos(th)
    return np.stack([a * sgnpow(s, 2.0 / e), cy - np.where(c >= 0, bf, bb) * sgnpow(c, 2.0 / e),
                     np.full(NT, z)], axis=1)


def arm_rows(side):
    rows = []
    for (q, pb, yc, ra) in ARM_FAN:
        q3 = np.array([q[0], yc, q[1]])
        p3 = np.array([pb[0], yc, pb[1]])
        rows.append(ring((q3 + p3) / 2, (0, -1, 0), norm(q3 - p3), ra, np.linalg.norm(q3 - p3) / 2, NA))
    A0 = np.array([0.0, -1.0, 0.0])
    for (s, r) in ARM_UPPER:
        A = norm(A0 - np.dot(A0, UPPER_DIR) * UPPER_DIR)
        rows.append(ring(SHOULDER + UPPER_DIR * s, A, np.cross(A, UPPER_DIR), r, r, NA))
    for (f, r) in ARM_FORE:
        A = norm(A0 - np.dot(A0, FORE_DIR) * FORE_DIR)
        rows.append(ring(ELBOW + FORE_DIR * f, A, np.cross(A, FORE_DIR), r * 1.06, r * 0.94, NA))
    rows = np.array(rows)
    return mirror_points(rows) if side < 0 else rows


def leg_ring(z, cx, cy, rx, ry, e=2.2):
    phi = np.radians(90 + (np.arange(NL) - 4.0) * 30.0)       # from the front toward the outside
    s, c = np.sin(phi), np.cos(phi)
    return np.stack([cx + rx * sgnpow(s, 2.0 / e), cy - ry * sgnpow(c, 2.0 / e), np.full(NL, z)], axis=1)


# ----------------------------------------------------------------------------- hands
FINGERS = [   # length, half width, spread (deg, + toward the thumb), curl (deg per joint)
    (0.066, 0.0118, 5.0, (12, 22, 18)),      # index
    (0.073, 0.0122, 1.0, (14, 24, 20)),      # middle
    (0.068, 0.0116, -3.5, (16, 26, 22)),     # ring
    (0.055, 0.0104, -9.0, (18, 28, 24)),     # little
]
KNUCKLE_L = [0.086, 0.092, 0.093, 0.089, 0.081]      # palm length at the five finger boundaries
KNUCKLE_T = [0.046, 0.023, 0.0, -0.023, -0.046]      # across the palm, + on the thumb side: ref hand width 0.089


def hand_into(mb, side):
    """Adds one hand to mb and returns its open wrist ring (10 vertices).
    Built in hand space: l toward the fingertips, t toward the thumb, n out of the palm."""
    h = MB()
    spec = [(-0.045, 0.70, 0.0245), (-0.012, 0.76, 0.0225), (0.016, 0.92, 0.0215), (0.040, 1.00, 0.0200),
            (0.068, 1.02, 0.0180), (1.0, 1.00, 0.0158)]
    rows = []
    for (l, ws, th) in spec:
        ring_pts = []
        for k in list(range(5)) + list(range(4, -1, -1)):
            ll = KNUCKLE_L[k] if l == 1.0 else l
            edge = 0.70 if k in (0, 4) else 1.0          # thinner at the two edges: an oval section
            ring_pts.append((ll, KNUCKLE_T[k] * ws, (-th if len(ring_pts) < 5 else th) * edge))
        rows.append(ring_pts)
    idx = h.grid(np.array(rows), closed=True, skip={(3, 9)}, uv=(0, 0, 1, 1))
    last = idx[-1]
    for k, (L, hw, spread, curl) in enumerate(FINGERS):
        base = [last[k], last[k + 1], last[8 - k], last[9 - k]]
        c = np.array([h.v[i] for i in base]).mean(axis=0)
        d = norm(np.array([1.0, math.tan(math.radians(spread)), 0.0]))
        tdir = norm(np.array([-d[1], d[0], 0.0]))
        frows, pos, ang = [], c.copy(), 0.0
        segs = [(0.011, 0.84, 0)] + [(L * f, w, j + 1) for j, (f, w) in enumerate(((0.40, 0.92), (0.31, 0.86), (0.24, 0.66)))]
        ht = hw * 0.95
        for (seg, wsc, jn) in segs:
            if jn > 0:
                ang += math.radians(curl[jn - 1]) * (0.5 if jn == 1 else 1.0)
            dd = d * math.cos(ang) + np.array([0, 0, 1.0]) * math.sin(ang)
            nn = np.cross(dd, tdir)
            nn = nn if nn[2] < 0 else -nn          # the back of the finger is -n
            pos = pos + dd * seg
            frows.append([pos + tdir * hw * wsc + nn * ht * wsc, pos - tdir * hw * wsc + nn * ht * wsc,
                          pos - tdir * hw * wsc - nn * ht * wsc, pos + tdir * hw * wsc - nn * ht * wsc])
        fidx = h.grid(frows, closed=True, uv=(0.3 + k * 0.1, 0.2, 1, 1))
        h.bridge(base, fidx[0])
        tipq = fidx[-1]
        P = np.array([h.v[i] for i in tipq])
        nrm = np.cross(P[1] - P[0], P[3] - P[0])
        h.face(tipq if np.dot(nrm, P.mean(axis=0) - c) > 0 else tipq[::-1])
    # thumb, out of the side face between palm rings 3 and 4
    base = [idx[3][0], idx[4][0], idx[4][9], idx[3][9]]
    c = np.array([h.v[i] for i in base]).mean(axis=0)
    d = norm(np.array([0.62, 0.72, 0.30]))
    tdir = norm(np.cross(d, np.array([0.0, 0.3, -1.0])))
    nn = np.cross(d, tdir)
    pos, frows = c.copy(), []
    for (seg, hw) in ((0.013, 0.0150), (0.027, 0.0146), (0.027, 0.0134), (0.021, 0.0100)):
        pos = pos + d * seg
        d = norm(d + np.array([0.10, -0.06, 0.05]))
        frows.append([pos + tdir * hw + nn * hw, pos - tdir * hw + nn * hw, pos - tdir * hw - nn * hw, pos + tdir * hw - nn * hw])
    fidx = h.grid(frows, closed=True, uv=(0.8, 0.2, 1, 1))
    h.bridge(base, fidx[0])
    tipq = fidx[-1]
    P = np.array([h.v[i] for i in tipq])
    nrm = np.cross(P[1] - P[0], P[3] - P[0])
    h.face(tipq if np.dot(nrm, P.mean(axis=0) - c) > 0 else tipq[::-1])
    # hand space -> world, then append to the body builder
    Lw = HAND_DIR
    Tw = np.array([0.0, -1.0, 0.0])
    Tw = norm(Tw - np.dot(Tw, Lw) * Lw)
    Nw = np.cross(Lw, Tw)                          # toward the thigh for his left hand
    V = np.array(h.v)
    Wd = WRIST[None, :] + V[:, 0:1] * Lw + V[:, 1:2] * Tw + V[:, 2:3] * Nw
    faces, uvs = h.f, h.uv
    if side < 0:
        Wd[:, 0] *= -1
        faces = [f[::-1] for f in faces]
        uvs = [u[::-1] if u else u for u in uvs]
    off = len(mb.v)
    mb.v += [tuple(p) for p in Wd]
    for f, u in zip(faces, uvs):
        mb.face([i + off for i in f], [(a + 3.0 + side * 0.5, b) for (a, b) in u] if u else None)
    return [i + off for i in idx[0]]


# ----------------------------------------------------------------------------- feet
NF = 12
FOOT_PATH = [(0.150, 0.047), (0.120, 0.048), (0.090, 0.050), (0.060, 0.054), (0.030, 0.064), (0.005, 0.082),
             (-0.012, 0.108), (-0.020, 0.140), (-0.022, 0.170)]


def foot_sdf(p):
    """Bare foot in boot space (x across, y toward the toes, z up); it stands on the boot sole.
    A simple shape: no separate toes (inferred, the reference only shows boots)."""
    foot = sd_ellipsoid(p, (0, 0.065, 0.052), (0.042, 0.120, 0.027))
    ball = sd_ellipsoid(p, (0, 0.128, 0.047), (0.046, 0.052, 0.021))
    heel = sd_ellipsoid(p, (0, -0.034, 0.060), (0.033, 0.037, 0.034))
    ankle = sd_capsule(p, (0, -0.021, 0.078), (0, -0.022, 0.230), 0.036, 0.042)
    instep = sd_capsule(p, (0, 0.050, 0.064), (0, -0.012, 0.112), 0.029, 0.036)
    d = smin(foot, ball, 0.02)
    d = smin(d, heel, 0.025)
    d = smin(d, instep, 0.025)
    d = smin(d, ankle, 0.03)
    return smax(d, SOLE_T + 0.003 - p[..., 2], 0.004)


def foot_into(mb, side):
    path = spline([(0, y, z) for (y, z) in FOOT_PATH], 1)
    T, A, Bv = frames(path, ref=(1, 0, 0))
    phi = 2 * PI * np.arange(NF) / NF + PI / NF
    rows = []
    for tdeg in (62, 30):
        t = math.radians(tdeg)
        d = (np.cos(phi)[:, None] * A[0] + np.sin(phi)[:, None] * Bv[0]) * math.cos(t) - T[0] * math.sin(t)
        o = np.repeat(path[0][None, :], NF, axis=0)
        rows.append(o + d * raycast(foot_sdf, o, d, 0.2)[:, None])
    for i in range(len(path)):
        d = np.cos(phi)[:, None] * A[i] + np.sin(phi)[:, None] * Bv[i]
        o = np.repeat(path[i][None, :], NF, axis=0)
        rows.append(o + d * raycast(foot_sdf, o, d, 0.2)[:, None])
    tip = path[0] - T[0] * raycast(foot_sdf, path[0][None, :], -T[0][None, :], 0.2)[0]
    idx = mb.grid(boot_world(np.array(rows), side), closed=True, uv=(4.0 + side * 0.5, 0, 1, 1))
    # close the toe with a quad cap: 12 -> a strip of 5 quads
    r0 = idx[0]
    n = len(r0)
    fwd = boot_world(tip + np.array([0, 1, 0]), side) - boot_world(tip, side)
    for k in range(n // 2 - 1):
        q = [r0[k], r0[k + 1], r0[n - 2 - k], r0[n - 1 - k]]
        P = np.array([mb.v[i] for i in q])
        nrm = np.cross(P[1] - P[0], P[3] - P[0])
        mb.face(q if np.dot(nrm, fwd) > 0 else q[::-1])
    return idx[-1]


# ----------------------------------------------------------------------------- build

def bake_subsurf(ob, levels):
    m = ob.modifiers.new("Subdivision", "SUBSURF")
    m.levels = levels
    m.uv_smooth = "PRESERVE_BOUNDARIES"
    m.boundary_smooth = "ALL"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    name = old.name
    ob.data = me
    ob.modifiers.clear()
    bpy.data.meshes.remove(old)
    me.name = name
    return ob


def build():
    skin = material("CH_Rowan_Skin", (0.800, 0.440, 0.300), 0.6)
    mb = MB()
    rows = [torso_ring(*r) for r in TORSO]
    rows[0][0, 2] -= 0.010           # front and back centre dip toward the crotch
    rows[0][8, 2] -= 0.006
    skip = {(r, c) for r in range(AH_R0, AH_R0 + AH_ROWS) for c in (3, 4, 11, 12)}
    idx = mb.grid(rows, closed=True, skip=skip, uv=(0, 0, 1, 1), flip=False)
    # arms and hands
    for side, c0 in ((1, 3), (-1, 11)):
        r0, r1 = AH_R0, AH_R0 + AH_ROWS
        loop = [idx[r0][c] for c in range(c0, c0 + 3)]
        loop += [idx[r][c0 + 2] for r in range(r0 + 1, r1)]
        loop += [idx[r1][c] for c in range(c0 + 2, c0 - 1, -1)]
        loop += [idx[r][c0] for r in range(r1 - 1, r0, -1)]
        aidx = mb.grid(arm_rows(side), closed=True, uv=(2.0 + side * 0.5, 0, 1, 1))
        mb.bridge(loop, aidx[0], outward_from=(side * 0.11, 0, 1.35))
        wrist = hand_into(mb, side)
        mb.bridge(aidx[-1], wrist)
    # legs and feet
    first = idx[0]
    cy = TORSO[0][4]
    c1 = mb.vert((0, cy - 0.055, CROTCH_Z + 0.006))      # three gusset points under the crotch
    c2 = mb.vert((0, cy, CROTCH_Z))
    c3 = mb.vert((0, cy + 0.055, CROTCH_Z + 0.006))
    F, Bk = first[0], first[8]
    for side in (1, -1):
        lrows = np.array([leg_ring(*r) for r in LEG])
        if side < 0:
            lrows = mirror_points(lrows)
        lidx = mb.grid(lrows, closed=True, uv=(5.5 + side * 0.5, 0, 1, 1), flip=side > 0)
        if side > 0:
            loop = [F] + [first[j] for j in range(1, 8)] + [Bk, c3, c2, c1]
        else:
            loop = [F] + [first[j] for j in range(15, 8, -1)] + [Bk, c3, c2, c1]
        ringi = lidx[0]
        cen = np.array([side * 0.10, cy, 0.74])
        for k in range(NL):
            k2 = (k + 1) % NL
            q = [loop[k], loop[k2], ringi[k2], ringi[k]]
            P = np.array([mb.v[i] for i in q])
            n = np.cross(P[1] - P[0], P[3] - P[0])
            mb.face(q if np.dot(n, P.mean(axis=0) - cen) > 0 else q[::-1], [(0, 0), (0.02, 0), (0.02, 0.02), (0, 0.02)])
        ankle = foot_into(mb, side)
        mb.bridge(lidx[-1], ankle)
    ob = mb.build("CH_Rowan_Body", "LOW", OWNER, [skin])
    cage = (len(ob.data.vertices), len(ob.data.polygons))
    bake_subsurf(ob, 1)
    me = ob.data
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    log(ob.name, "cage verts/faces", cage, "-> verts", len(me.vertices), "faces", len(me.polygons), "tris", tris)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True)
    a = p.parse_args(argv_after_dashes())
    open_master(a.master)
    clear_owned(OWNER)
    build()
    save_master(a.master)
    log("saved", a.master)
