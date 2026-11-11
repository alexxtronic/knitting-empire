"""
CH_Rowan phase 04: the outfit (sweater, jeans, belt, boots), each garment its own object.

  Blender --background --python build/04_outfit.py -- --master CH_Rowan_master.blend

Nothing here is joined to the body: the garments sit over the nude body from 02_body.py with
clearance, so an outfit can be swapped by replacing these objects.

Constants are metres measured on ref/front.png, ref/side.png and ref/back.png at
0.002347 m/px (hair top 1.80 m), or marked "inferred". Re-runnable: deletes what it owns.
Each cage is all quads with a loop at every joint; a level-1 Subdivision gives the game mesh.
"""
import bpy, sys, os, math, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from common import *
from spec import *

PHASE = "04_outfit"
OWNER = "phase:" + PHASE


def log(*a):
    print("[" + PHASE + "]", *a)


# ----------------------------------------------------------------------------- preview materials
# Flat colours sampled from the reference; phase 05 replaces them with the real materials.
def mats():
    return dict(
        sweater=material("CH_Rowan_Sweater", (0.150, 0.140, 0.135), 0.95),
        denim=material("CH_Rowan_Denim", (0.030, 0.038, 0.060), 0.85),
        cuff=material("CH_Rowan_DenimCuff", (0.330, 0.330, 0.340), 0.9),
        leather=material("CH_Rowan_BootLeather", (0.240, 0.095, 0.040), 0.6),
        sole=material("CH_Rowan_BootSole", (0.420, 0.270, 0.130), 0.8),
        lace=material("CH_Rowan_BootLace", (0.520, 0.360, 0.190), 0.85),
        belt=material("CH_Rowan_Belt", (0.130, 0.055, 0.025), 0.55),
        brass=material("CH_Rowan_Brass", (0.560, 0.400, 0.150), 0.45, 0.6),
    )


# ----------------------------------------------------------------------------- sweater
NT = 24            # torso columns; column 0 is front centre, 6 his left side, 12 back centre
# z, half width a, half depth front, half depth back, centre y, superellipse exponent
TORSO = [
    (1.018, 0.158, 0.132, 0.102, -0.027, 2.20),   # hem, turned under (hidden)
    (1.000, 0.176, 0.150, 0.118, -0.027, 2.20),   # hem bottom: front view 44% width 0.364
    (1.030, 0.181, 0.157, 0.122, -0.027, 2.20),
    (1.060, 0.178, 0.160, 0.125, -0.026, 2.20),   # top of the ribbed hem
    (1.100, 0.171, 0.160, 0.128, -0.024, 2.25),   # front view 40% width 0.336; side view front -0.173
    (1.150, 0.166, 0.156, 0.131, -0.020, 2.30),
    (1.195, 0.162, 0.150, 0.133, -0.016, 2.35),
    (1.228, 0.160, 0.146, 0.135, -0.013, 2.40),   # bottom of the armhole
    (1.280, 0.158, 0.140, 0.136, -0.009, 2.40),   # side view 28%: front -0.150, back +0.140
    (1.330, 0.157, 0.132, 0.136, -0.005, 2.40),
    (1.382, 0.155, 0.122, 0.133, -0.001, 2.40),   # side view 24%: front -0.120, back +0.133
    (1.432, 0.156, 0.108, 0.126, 0.004, 2.30),    # top of the armhole: front view 20% half width 0.153
    (1.458, 0.118, 0.098, 0.106, 0.000, 2.20),
    (1.476, 0.090, 0.086, 0.086, -0.010, 2.00),   # collar base: front view collar width 0.19
    (1.497, 0.081, 0.080, 0.078, -0.011, 2.00),   # collar, outer top
    (1.502, 0.071, 0.071, 0.070, -0.012, 2.00),   # collar, inner top: 1 cm clear of the neck
    (1.482, 0.067, 0.067, 0.066, -0.012, 2.00),   # collar, turned in (hidden)
]
AH_R0, AH_ROWS = 7, 4                 # armhole: rows 7..11, columns 4..8 (left) and 16..20 (right)
COLLAR_DIP = 0.012                    # collar front sits lower than the back (side view)

# Shoulder fan (his left): rings pivot on the armpit. outer/top point, inner/bottom point, y, half depth
SLEEVE_FAN = [
    ((0.166, 1.436), (0.157, 1.228), 0.006, 0.068),
    ((0.202, 1.416), (0.160, 1.222), 0.004, 0.071),
    ((0.237, 1.374), (0.163, 1.214), 0.001, 0.073),   # front view 24%: half width 0.235
    ((0.254, 1.302), (0.166, 1.203), -0.003, 0.074),  # 28%: 0.257
    ((0.272, 1.240), (0.170, 1.186), -0.007, 0.074),  # 32%: 0.280
]
# distance along the upper arm from the shoulder joint, outer radius, inner radius, front/back radius
SLEEVE_UPPER = [(0.215, 0.073, 0.056, 0.074), (0.260, 0.074, 0.068, 0.074)]
# distance along the forearm from the elbow, radius
SLEEVE_FORE = [(0.050, 0.076), (0.090, 0.077), (0.115, 0.072), (0.130, 0.057),   # bunched above the cuff
               (0.142, 0.050), (0.170, 0.048), (0.198, 0.047),                    # ribbed cuff: z 1.02 to 0.957
               (0.201, 0.040), (0.186, 0.036)]                                    # turned in (hidden)
NS = 16


def torso_ring(z, a, bf, bb, cy, e):
    th = 2 * PI * np.arange(NT) / NT
    s, c = np.sin(th), np.cos(th)
    x = a * sgnpow(s, 2.0 / e)
    y = cy - np.where(c >= 0, bf, bb) * sgnpow(c, 2.0 / e)
    w = float(smoothstep(1.43, 1.476, z))
    zz = z - COLLAR_DIP * c * w + 0.004 * w
    return np.stack([x, y, zz], axis=1)


def sleeve_rows(side):
    """Rings of the sleeve for his left arm (side=+1), mirrored for the right."""
    rows = []
    for (q, pb, yc, ra) in SLEEVE_FAN:
        q3 = np.array([q[0], yc, q[1]])
        p3 = np.array([pb[0], yc, pb[1]])
        cen = (q3 + p3) / 2
        Bv = norm(q3 - p3)
        r = np.linalg.norm(q3 - p3) / 2
        rows.append(ring(cen, (0, -1, 0), Bv, ra, r, NS))
    A0 = np.array([0.0, -1.0, 0.0])
    for (s, ro, ri, ra) in SLEEVE_UPPER:
        cen = SHOULDER + UPPER_DIR * s
        A = norm(A0 - np.dot(A0, UPPER_DIR) * UPPER_DIR)
        Bv = np.cross(A, UPPER_DIR)
        rows.append(ring(cen, A, Bv, ra, ro, NS, rb_neg=ri))
    for (f, r) in SLEEVE_FORE:
        cen = ELBOW + FORE_DIR * f
        A = norm(A0 - np.dot(A0, FORE_DIR) * FORE_DIR)
        Bv = np.cross(A, FORE_DIR)
        rows.append(ring(cen, A, Bv, r, r, NS))
    rows = np.array(rows)
    if side < 0:
        rows = mirror_points(rows)
    return rows


def build_sweater(M):
    mb = MB()
    rows = [torso_ring(*r) for r in TORSO]
    skip = set()
    for r in range(AH_R0, AH_R0 + AH_ROWS):
        for c in (4, 5, 6, 7, 16, 17, 18, 19):
            skip.add((r, c))
    idx = mb.grid(rows, closed=True, skip=skip, uv=(0, 0, 1, 1), flip=False)
    for side, c0 in ((1, 4), (-1, 16)):
        r0, r1 = AH_R0, AH_R0 + AH_ROWS
        loop = [idx[r0][c] for c in range(c0, c0 + 5)]
        loop += [idx[r][c0 + 4] for r in range(r0 + 1, r1)]
        loop += [idx[r1][c] for c in range(c0 + 4, c0 - 1, -1)]
        loop += [idx[r][c0] for r in range(r1 - 1, r0, -1)]
        srows = sleeve_rows(side)
        sidx = mb.grid(srows, closed=True, uv=(2.0 + side * 0.6, 0, 1, 1))
        mb.bridge(loop, sidx[0], outward_from=(side * 0.12, 0, 1.33), uv_ring=mb.last_uv)
    ob = mb.build("CH_Rowan_Sweater", "LOW", OWNER, [M["sweater"]])
    subsurf(ob, 1, 2)
    return ob


# ----------------------------------------------------------------------------- jeans
NP = 26            # pelvis columns: 0 front centre, 13 back centre
PELVIS = [
    (1.020, 0.150, 0.118, 0.098, -0.030, 2.3),   # waistband, turned in (hidden)
    (1.008, 0.158, 0.126, 0.106, -0.030, 2.3),
    (0.965, 0.165, 0.129, 0.112, -0.032, 2.3),   # front view 48%: width 0.343
    (0.915, 0.174, 0.130, 0.124, -0.033, 2.4),
    (0.860, 0.183, 0.128, 0.128, -0.035, 2.5),   # 52%: 0.366; side view front -0.161, back +0.094
    (0.805, 0.190, 0.120, 0.116, -0.038, 2.6),   # 56%: 0.383
    (0.755, 0.194, 0.114, 0.110, -0.040, 2.8),   # crotch row: 60% 0.392
]
CROTCH_Z = 0.722
# z, centre x, centre y, half width, half depth (his left leg)
LEG = [
    (0.700, 0.101, -0.040, 0.093, 0.108),
    (0.645, 0.110, -0.037, 0.090, 0.103),   # 64%: width 0.180, centre 0.110; side view depth 0.206
    (0.572, 0.113, -0.031, 0.0855, 0.1015),
    (0.500, 0.117, -0.014, 0.076, 0.100),   # knee, 72%: width 0.148
    (0.427, 0.122, 0.000, 0.083, 0.100),    # 76%: 0.167
    (0.354, 0.127, 0.012, 0.082, 0.092),    # 80%: 0.164
    (0.285, 0.128, 0.018, 0.078, 0.089),
    (0.232, 0.128, 0.022, 0.0765, 0.088),   # 88%: 0.155
]
CUFF = [(0.236, 0.008), (0.205, 0.0095), (0.174, 0.008), (0.170, 0.001), (0.195, -0.007)]   # z, offset from the leg
NL = 16


def pelvis_ring(z, a, bf, bb, cy, e):
    th = 2 * PI * np.arange(NP) / NP
    s, c = np.sin(th), np.cos(th)
    return np.stack([a * sgnpow(s, 2.0 / e), cy - np.where(c >= 0, bf, bb) * sgnpow(c, 2.0 / e),
                     np.full(NP, z)], axis=1)


def leg_ring(z, cx, cy, rx, ry, e=2.3):
    phi = np.radians(90 + (np.arange(NL) - 6.5) * 22.5)      # from the front toward the outside
    s, c = np.sin(phi), np.cos(phi)
    return np.stack([cx + rx * sgnpow(s, 2.0 / e), cy - ry * sgnpow(c, 2.0 / e), np.full(NL, z)], axis=1)


def build_jeans(M):
    mb = MB()
    prow = [pelvis_ring(*r) for r in PELVIS]
    prow[-1][0, 2] -= 0.012          # front and back centre dip toward the crotch
    prow[-1][13, 2] -= 0.008
    idx = mb.grid(prow, closed=True, uv=(0, 0, 1, 1), flip=True)     # rows run downward
    last = idx[-1]
    cy = PELVIS[-1][4]
    c1 = mb.vert((0, cy - 0.050, CROTCH_Z))
    c2 = mb.vert((0, cy + 0.045, CROTCH_Z))
    F, Bk = last[0], last[13]
    for side in (1, -1):
        rows = [leg_ring(*r) for r in LEG]
        zc = LEG[-1]
        for (z, off) in CUFF:
            rows.append(leg_ring(z, zc[1], zc[2], zc[3] + off, zc[4] + off))
        rows = np.array(rows)
        if side < 0:
            rows = mirror_points(rows)
        nleg = len(LEG)
        lidx = mb.grid(rows[:nleg], closed=True, uv=(1.5 + side * 0.4, 0, 1, 1), flip=side > 0)
        cidx = [lidx[-1]] + [[mb.vert(p) for p in r] for r in rows[nleg:]]
        mb.grid(None, closed=True, idx=cidx, mat=1, uv=(1.5 + side * 0.4, -0.3, 1, 1), flip=side > 0)
        if side > 0:
            loop = [F] + [last[j] for j in range(1, 13)] + [Bk, c2, c1]
        else:
            loop = [F] + [last[j] for j in range(25, 13, -1)] + [Bk, c2, c1]
        # explicit pairing: ring vertex k sits under loop vertex k
        ringi = lidx[0]
        for k in range(NL):
            k2 = (k + 1) % NL
            q = [loop[k], loop[k2], ringi[k2], ringi[k]]
            P = np.array([mb.v[i] for i in q])
            n = np.cross(P[1] - P[0], P[3] - P[0])
            cen = np.array([side * 0.10, cy, 0.72])
            uvs = [(0, 0), (0.02, 0), (0.02, 0.02), (0, 0.02)]
            if np.dot(n, P.mean(axis=0) - cen) < 0:
                q, uvs = q[::-1], uvs[::-1]
            mb.face(q, uvs, 0)
    ob = mb.build("CH_Rowan_Jeans", "LOW", OWNER, [M["denim"], M["cuff"]])
    subsurf(ob, 1, 2)
    return ob


# ----------------------------------------------------------------------------- belt
BELT_Z, BELT_H, BELT_T = 0.985, 0.032, 0.006      # front view: belt 0.970 to 1.002


def build_belt(M):
    mb = MB()
    n = 48
    th = 2 * PI * np.arange(n) / n
    a, bf, bb, cy, e = table([r[:6] for r in PELVIS], BELT_Z)
    s, c = np.sin(th), np.cos(th)
    base = np.stack([a * sgnpow(s, 2 / e), cy - np.where(c >= 0, bf, bb) * sgnpow(c, 2 / e), np.zeros(n)], axis=1)
    nrm = norm(np.stack([base[:, 0] / a ** 2, (base[:, 1] - cy) / (bf ** 2), np.zeros(n)], axis=1))
    prof = [(0.001, -0.5), (0.001 + BELT_T * 0.8, -0.5), (0.001 + BELT_T, -0.36), (0.001 + BELT_T, 0.36),
            (0.001 + BELT_T * 0.8, 0.5), (0.001, 0.5)]
    rows = [base + nrm * o + np.array([0, 0, BELT_Z + h * BELT_H]) for (o, h) in prof]
    mb.grid(rows, closed=True, uv=(0, 0, 1, 1), flip=False)
    # belt loops (denim): five flat tabs over the belt
    for ang in (28, 105, 180, 255, 332):
        k = int(round(ang / 360 * n)) % n
        p, nn = base[k], nrm[k]
        tng = np.array([-nn[1], nn[0], 0])
        w, o = 0.007, 0.001 + BELT_T + 0.0015
        z0, z1 = BELT_Z - BELT_H * 0.5 - 0.006, BELT_Z + BELT_H * 0.5 + 0.006
        ring_pts = []
        for (zz, oo) in ((z0, 0.0), (z0, o), (z1, o), (z1, 0.0)):
            ring_pts.append([p + nn * oo + tng * w + np.array([0, 0, zz]), p + nn * oo - tng * w + np.array([0, 0, zz]),
                             p + nn * (oo + 0.0025) - tng * w + np.array([0, 0, zz]),
                             p + nn * (oo + 0.0025) + tng * w + np.array([0, 0, zz])])
        mb.grid(ring_pts, closed=True, mat=2)
    # buckle: a brass frame in front of the belt and a prong
    fy = base[0][1] - 0.001 - BELT_T - 0.0035
    bw, bh, br, pr = 0.027, 0.0215, 0.006, 0.0032
    path = []
    for (sx, sz, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        for k in range(4):
            ang = math.radians(a0 + k * 30)
            path.append(((bw - br) * sx + br * math.cos(ang), (bh - br) * sz + br * math.sin(ang)))
    path = np.array(path)
    rows = []
    for k in range(5):
        ang = 2 * PI * (k % 4) / 4 - PI / 4
        d = path / np.linalg.norm(path, axis=1, keepdims=True)
        rr = pr * math.cos(ang)
        rows.append(np.stack([path[:, 0] + d[:, 0] * rr, np.full(len(path), fy - pr * math.sin(ang)),
                              BELT_Z + path[:, 1] + d[:, 1] * rr], axis=1))
    mb.grid(rows, closed=True, mat=1)
    prong = [[(-bw - 0.002, fy - 0.004 + dy, BELT_Z + dz) for (dy, dz) in ((-0.002, -0.0025), (0.002, -0.0025), (0.002, 0.0025), (-0.002, 0.0025))],
             [(0.006, fy - 0.004 + dy, BELT_Z + dz) for (dy, dz) in ((-0.002, -0.0025), (0.002, -0.0025), (0.002, 0.0025), (-0.002, 0.0025))]]
    pi_ = mb.grid(prong, closed=True, mat=1)
    mb.face(pi_[0][::-1], mat=1)
    mb.face(pi_[1], mat=1)
    ob = mb.build("CH_Rowan_Belt", "LOW", OWNER, [M["belt"], M["brass"], M["denim"]], weld=1e-5)
    return ob


# ----------------------------------------------------------------------------- boots

def boot_sdf(p):
    """Boot upper in boot space: x across, y toward the toe, z up. Toe at y = 0.227, heel at y = -0.090."""
    foot = sd_ellipsoid(p, (0, 0.075, 0.060), (0.056, 0.150, 0.047))
    toe = sd_ellipsoid(p, (0, 0.163, 0.064), (0.059, 0.064, 0.048))       # round, tall toe box
    heel = sd_ellipsoid(p, (0, -0.040, 0.066), (0.052, 0.050, 0.056))
    q = p * np.array([1.0 / 0.90, 1.0, 1.0])
    shaft = sd_capsule(q, (0, -0.030, 0.090), (0, -0.033, 0.270), 0.054)      # stays inside the jeans cuff
    instep = sd_capsule(p, (0, 0.075, 0.082), (0, -0.008, 0.150), 0.044, 0.050)
    d = smin(foot, toe, 0.02)
    d = smin(d, heel, 0.03)
    d = smin(d, instep, 0.03)
    d = smin(d, shaft, 0.035)
    return smax(d, SOLE_T - 0.004 - p[..., 2], 0.004)


BOOT_PATH = [(0.198, 0.060), (0.170, 0.059), (0.135, 0.060), (0.100, 0.063), (0.065, 0.069), (0.030, 0.082),
             (0.000, 0.104), (-0.019, 0.134), (-0.028, 0.168), (-0.032, 0.200), (-0.033, 0.228), (-0.033, 0.250)]
NB = 20


def build_boot(M, side):
    mb = MB()
    path = spline([(0, y, z) for (y, z) in BOOT_PATH], 3)
    T, A, Bv = frames(path, ref=(1, 0, 0))
    phi = 2 * PI * np.arange(NB) / NB
    rows = []
    # toe cap: rays from the first path point, tilted forward
    cap_tilts = [75, 55, 35, 17]
    for tdeg in cap_tilts:
        t = math.radians(tdeg)
        d = (np.cos(phi)[:, None] * A[0] + np.sin(phi)[:, None] * Bv[0]) * math.cos(t) - T[0] * math.sin(t)
        o = np.repeat(path[0][None, :], NB, axis=0)
        rows.append(o + d * raycast(boot_sdf, o, d, 0.25)[:, None])
    for i in range(len(path)):
        d = np.cos(phi)[:, None] * A[i] + np.sin(phi)[:, None] * Bv[i]
        o = np.repeat(path[i][None, :], NB, axis=0)
        rows.append(o + d * raycast(boot_sdf, o, d, 0.25)[:, None])
    rows = np.array(rows)
    tip = path[0] - T[0] * raycast(boot_sdf, path[0][None, :], -T[0][None, :], 0.25)[0]
    idx = mb.grid(boot_world(rows, side), closed=True, uv=(0, 0, 1, 1))
    mb.cap(idx[0], center=boot_world(tip, side), outward=boot_world(tip + np.array([0, 1, 0]), side) - boot_world(tip, side))
    # sole: outline of the upper at the sole line, grown by a welt
    ny = 40
    ys = np.concatenate([np.linspace(-0.094, 0.231, ny)])
    half = []
    for y in ys:
        o = np.array([[0.0, y, SOLE_T + 0.006]])
        if boot_sdf(o)[0] > 0:
            half.append(0.0)
        else:
            half.append(raycast(boot_sdf, o, np.array([[1.0, 0, 0]]), 0.12)[0])
    half = np.array(half)
    left = np.stack([half, ys], axis=1)
    outline = np.concatenate([left, np.stack([-half[::-1][1:-1], ys[::-1][1:-1]], axis=1)])
    cen = outline.mean(axis=0)
    dirs = norm(outline - cen)
    def lay(z, grow):
        return np.stack([outline[:, 0] + dirs[:, 0] * grow, outline[:, 1] + dirs[:, 1] * grow,
                         np.full(len(outline), z)], axis=1)
    srows = [lay(0.0, 0.002), lay(0.004, 0.006), lay(SOLE_T - 0.004, 0.007), lay(SOLE_T, 0.005), lay(SOLE_T + 0.001, -0.004)]
    sidx = mb.grid(boot_world(np.array(srows), side), closed=True, mat=1)
    mb.cap(sidx[0], mat=1, outward=(0, 0, -1))
    # laces: six bars across the front of the instep and shaft, r = 2.5 mm
    for s in np.linspace(0.34, 0.86, 6):
        i = int(round(s * (len(path) - 1)))
        up = Bv[i]                       # toward the front of the boot
        pts = []
        for a in np.linspace(-32, 32, 7):
            d = math.cos(math.radians(a)) * up + math.sin(math.radians(a)) * A[i]
            t = raycast(boot_sdf, path[i][None, :], d[None, :], 0.2)[0]
            pts.append(path[i] + d * (t + 0.0015))
        pts = boot_world(np.array(pts), side)
        Tl, Al, Bl = frames(pts, ref=(0, 0, 1))
        lrows = [ring(pts[k], Al[k], Bl[k], 0.0026, 0.0026, 6) for k in range(len(pts))]
        li = mb.grid(lrows, closed=True, mat=2)
        mb.cap(li[0], mat=2, outward=-Tl[0])
        mb.cap(li[-1], mat=2, outward=Tl[-1])
    name = "CH_Rowan_Boot_L" if side > 0 else "CH_Rowan_Boot_R"
    ob = mb.build(name, "LOW", OWNER, [M["leather"], M["sole"], M["lace"]], weld=1e-5)
    return ob


# ----------------------------------------------------------------------------- build

def build():
    M = mats()
    obs = [build_sweater(M), build_jeans(M), build_belt(M)]
    for side in (1, -1):
        obs.append(build_boot(M, side))
    for ob in obs:
        log(ob.name, "verts", len(ob.data.vertices), "faces", len(ob.data.polygons))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True)
    a = p.parse_args(argv_after_dashes())
    open_master(a.master)
    clear_owned(OWNER)
    build()
    save_master(a.master)
    log("saved", a.master)
