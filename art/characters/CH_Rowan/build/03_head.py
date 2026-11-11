"""
CH_Rowan phase 03: head, face and everything in it.

  Blender --background --python build/03_head.py -- --master CH_Rowan_master.blend   (after 02_body.py)

Objects: Head (skin, with ears, eyelids and an opening mouth), Eye_L / Eye_R (origin at the
eyeball centre, so they turn), TeethUpper, TeethLower, Tongue, Mouth (the inside of the mouth),
Beard and Brows (separate, so facial hair can be changed).

The head is a signed-distance sculpt (smooth unions of measured ellipsoids and capsules) meshed
by casting rays from the head's axis, which gives an all-quad grid: columns run down the face,
rows run round it. The eyes are cut as holes with lid loops, the mouth is a slit along one row
with lip loops going inside. The bottom row is the body's neck ring, vertex for vertex.

Measurements: ref/front.png and ref/side.png at 0.002347 m/px. Vertex groups "Head" and "Jaw"
are written for the jaw hinge.
"""
import bpy, bmesh, sys, os, math, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from common import *
from spec import *

PHASE = "03_head"
OWNER = "phase:" + PHASE


def log(*a):
    print("[" + PHASE + "]", *a)


# ----------------------------------------------------------------------------- the sculpt

def head_sdf(p):
    ax = np.abs(p[..., 0])
    q = np.stack([ax, p[..., 1], p[..., 2]], axis=-1)            # mirrored: paired features
    d = sd_ellipsoid(p, (0, -0.010, 1.685), (0.086, 0.115, 0.092))                       # cranium: forehead -0.125, top 1.777
    d = smin(d, sd_ellipsoid(p, (0, -0.048, 1.603), (0.078, 0.084, 0.086)), 0.040)       # face and jaw: width 0.158 at the mouth
    d = smin(d, sd_ellipsoid(q, (0.055, -0.018, 1.588), (0.020, 0.038, 0.030)), 0.030)   # jaw corners
    d = smin(d, sd_ellipsoid(p, (0, -0.110, 1.547), (0.031, 0.030, 0.029)), 0.025)       # chin: front -0.138, bottom 1.518
    d = smin(d, sd_ellipsoid(q, (0.042, -0.096, 1.614), (0.025, 0.025, 0.023)), 0.038)   # smiling cheeks
    d = smin(d, sd_capsule(p, (0, 0.0, 1.38), (0, -0.022, 1.60), 0.059), 0.009)          # neck: width 0.121
    d = smin(d, sd_capsule(q, (0.016, -0.121, 1.689), (0.056, -0.100, 1.690), 0.008), 0.020)   # a soft brow ridge
    eye = np.array(EYE)
    d = smax(d, -sd_sphere(q, eye + np.array([0, -0.004, 0]), EYE_R + 0.0045), 0.012)    # eye socket
    d = smin(d, sd_sphere(q, eye, EYE_R + 0.0020), 0.006)                                # eyelids, 2 mm over the eyeball
    d = smin(d, sd_capsule(p, (0, -0.124, 1.660), (0, -0.150, 1.620), 0.0090, 0.0140), 0.014)  # a short nose bridge
    d = smin(d, sd_sphere(p, (0, -0.149, 1.613), 0.0190), 0.008)                         # round nose tip: side view -0.164
    d = smin(d, sd_sphere(q, (0.0175, -0.136, 1.608), 0.0115), 0.007)                    # nostril wings
    d = smin(d, sd_ellipsoid(p, (0, -0.134, 1.592), (0.026, 0.010, 0.0065)), 0.006)      # upper lip
    d = smin(d, sd_ellipsoid(p, (0, -0.1315, 1.5780), (0.026, 0.0110, 0.0080)), 0.007)   # lower lip
    return d


def front_project(x, z):
    """Points of the face surface with the given x and z (cast straight forward from inside)."""
    x, z = np.atleast_1d(np.asarray(x, dtype=float)), np.atleast_1d(np.asarray(z, dtype=float))
    o = np.stack([x, np.full_like(x, 0.03), z], axis=1)
    d = np.repeat(np.array([[0.0, -1.0, 0.0]]), len(x), axis=0)
    return o + d * raycast(head_sdf, o, d, 0.25)[:, None]


# ----------------------------------------------------------------------------- the grid
M = 64                                    # columns: 0 front centre, 16 his left, 32 back
YAX = -0.010                              # the vertical axis the rays leave from
ZJ, DZ, NMID = 1.537, 0.006, 26           # middle rows: horizontal rays, 6 mm apart, 1.537 .. 1.687
ZC = ZJ + DZ * (NMID - 1)
LOW_E = [-27, -22, -16, -10, -5]          # rows under the jaw: rays tilted down from (0, YAX, ZJ)
TOP_E = [8, 16, 24, 32, 41, 50, 60, 70, 80]   # rows over the cranium: rays tilted up from (0, YAX, ZC)
RL = len(LOW_E)
SMILE = 0.0080                            # how far the mouth corners rise (ref: a wide closed smile)
MOUTH_I, MOUTH_C = 8, 7                   # mouth: middle row 8 (z 1.585), corners at columns +-7 (width 0.088)
EYE_C0, EYE_C1, EYE_I0, EYE_I1 = 3, 11, 17, 23     # eye hole: 8 x 6 quads -> a 28-vertex lid loop
EYE_ZC, EYE_HW, EYE_HU, EYE_HL, EYE_TILT = 1.6565, 0.0240, 0.0185, 0.0155, 0.0010   # opening 43 x 25 mm: the lids just touch the iris


def col_theta():
    u = np.arange(M) / M
    warped = 2 * PI * (u - 0.5 * np.sin(2 * PI * u) / (2 * PI))       # columns twice as dense on the face
    return warped, 2 * PI * u


def eye_outline(s, upper):
    f = (1 - abs(s) ** 2.4) ** 0.62          # round, open eyes
    return EYE[0] + EYE_HW * s, EYE_ZC + (EYE_HU if upper else -EYE_HL) * f + EYE_TILT * s


def eye_loop():
    """The grid points round the eye hole (middle row, column) with their targets (x, z):
    inner corner, along the lower lid, outer corner, back along the upper lid."""
    mid = (EYE_I0 + EYE_I1) // 2
    lower = [(i, EYE_C0) for i in range(mid - 1, EYE_I0 - 1, -1)] + [(EYE_I0, c) for c in range(EYE_C0 + 1, EYE_C1)] \
        + [(i, EYE_C1) for i in range(EYE_I0, mid)]
    upper = [(i, EYE_C1) for i in range(mid + 1, EYE_I1 + 1)] + [(EYE_I1, c) for c in range(EYE_C1 - 1, EYE_C0, -1)] \
        + [(i, EYE_C0) for i in range(EYE_I1, mid, -1)]
    out = [((mid, EYE_C0), eye_outline(-1, False))]
    for m, rc in enumerate(lower, start=1):
        out.append((rc, eye_outline(-1 + 2 * m / (len(lower) + 1), False)))
    out.append(((mid, EYE_C1), eye_outline(1, False)))
    for m, rc in enumerate(upper, start=1):
        out.append((rc, eye_outline(1 - 2 * m / (len(upper) + 1), True)))
    return out


def head_grid():
    """Positions (R, M, 3) of the head grid, plus the parameters the beard needs."""
    warped, uniform = col_theta()
    TH = np.repeat(warped[None, :], NMID, axis=0)
    ZZ = np.repeat((ZJ + DZ * np.arange(NMID))[:, None], M, axis=1)
    # a gentle smile: the mouth row rises toward the corners
    for i, w in ((6, 0.35), (7, 0.7), (8, 1.0), (9, 0.7), (10, 0.35)):
        for c in range(-11, 12):
            s = min(abs(c) / MOUTH_C, 1.0)
            fade = 1.0 if abs(c) <= MOUTH_C else max(0.0, (11 - abs(c)) / 4.0)
            ZZ[i, c % M] += (SMILE * s * s - 0.0010) * w * fade
    # eye hole: pin its rim to the lid outline, relax the grid round it
    loop = eye_loop()
    targets = front_project([t[0] for (_, t) in loop], [t[1] for (_, t) in loop])
    pinned = {}
    for (rc, _), p in zip(loop, targets):
        TH[rc] = math.atan2(p[0], -(p[1] - YAX))
        ZZ[rc] = p[2]
        pinned[rc] = p
    free = [(i, c) for i in range(15, 25) for c in range(2, 14)
            if (i, c) not in pinned and not (EYE_I0 < i < EYE_I1 and EYE_C0 < c < EYE_C1)]
    for _ in range(120):
        for (i, c) in free:
            TH[i, c] = (TH[i - 1, c] + TH[i + 1, c] + TH[i, c - 1] + TH[i, c + 1]) / 4
            ZZ[i, c] = (ZZ[i - 1, c] + ZZ[i + 1, c] + ZZ[i, c - 1] + ZZ[i, c + 1]) / 4
    for c in range(1, M // 2):                       # mirror his left half onto the right
        TH[:, M - c] = -TH[:, c]
        ZZ[:, M - c] = ZZ[:, c]
    R = RL + NMID + len(TOP_E)
    O = np.zeros((R, M, 3))
    D = np.zeros((R, M, 3))
    ELEV = np.zeros(R)
    THG = np.zeros((R, M))
    for k, e in enumerate(LOW_E):
        th = lerp(uniform, warped, k / RL)             # the lowest row is evenly spaced, like the body's neck ring
        er = math.radians(e)
        O[k] = (0, YAX, ZJ)
        D[k] = np.stack([np.sin(th) * math.cos(er), -np.cos(th) * math.cos(er), np.full(M, math.sin(er))], axis=1)
        ELEV[k], THG[k] = e, th
    for i in range(NMID):
        O[RL + i] = np.stack([np.zeros(M), np.full(M, YAX), ZZ[i]], axis=1)
        D[RL + i] = np.stack([np.sin(TH[i]), -np.cos(TH[i]), np.zeros(M)], axis=1)
        THG[RL + i] = TH[i]
    for k, e in enumerate(TOP_E):
        er = math.radians(e)
        r = RL + NMID + k
        O[r] = (0, YAX, ZC)
        D[r] = np.stack([np.sin(warped) * math.cos(er), -np.cos(warped) * math.cos(er), np.full(M, math.sin(er))], axis=1)
        ELEV[r], THG[r] = e, warped
    t = raycast(head_sdf, O.reshape(-1, 3), D.reshape(-1, 3), 0.3)
    P = (O.reshape(-1, 3) + D.reshape(-1, 3) * t[:, None]).reshape(R, M, 3)
    # take the lumps out: two light smoothing passes, leaving the nose, the lips and the lid rims alone
    keep = smoothstep(0.045, 0.020, np.linalg.norm(P - np.array([0, -0.150, 1.613]), axis=2))
    for i in (7, 8, 9):
        for c in range(-9, 10):
            keep[RL + i, c % M] = max(keep[RL + i, c % M], 0.7)
    for (i, c) in pinned:
        keep[RL + i, c] = keep[RL + i, M - c] = 1.0
    for _ in range(2):
        avg = (np.roll(P, 1, axis=1) + np.roll(P, -1, axis=1)) / 2
        avg[1:-1] = (avg[1:-1] * 2 + P[:-2] + P[2:]) / 4
        P[1:-1] += 0.5 * ((avg - P) * (1 - keep)[..., None])[1:-1]
    P[:, 0, 0] = 0.0
    P[:, M // 2, 0] = 0.0
    for (i, c), p in pinned.items():
        P[RL + i, c] = p
        P[RL + i, M - c] = p * np.array([-1, 1, 1])
    return P, ELEV, THG


def body_neck_ring():
    """The open neck loop of the body mesh, starting at the front and going toward his left."""
    ob = bpy.data.objects.get("CH_Rowan_Body")
    if ob is None:
        raise RuntimeError("run 02_body.py first: the head joins the body's neck ring")
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    pts = {}
    for e in bm.edges:
        if e.is_boundary:
            for v in e.verts:
                if v.co.z > 1.45:
                    pts[v.index] = np.array(v.co)
    bm.free()
    out = sorted(pts.values(), key=lambda c: (math.atan2(c[0], -(c[1] - NECK_Y)) + 2 * PI + 0.02) % (2 * PI))
    return np.array(out)


def jaw_weight(P):
    """How much a skin point follows the jaw bone (0..1), from its rest position."""
    P = np.asarray(P, dtype=float)
    x, y, z = np.abs(P[:, 0]), P[:, 1], P[:, 2]
    ang = np.degrees(np.arctan2(JAW_PIVOT[2] - z, JAW_PIVOT[1] - y))      # 0 = straight forward, + = down
    mouth = 16.2                                                          # the lip line seen from the hinge
    band = 1.3 + 9.0 * smoothstep(0.035, 0.075, x)                        # sharp at the lips, soft on the cheeks
    w = smoothstep(mouth - band, mouth + band, ang)
    w = w * smoothstep(0.030, -0.020, y)                                  # nothing behind the jaw corner
    w = w * smoothstep(1.490, 1.512, z)                                   # the neck stays with the head
    return w


def write_jaw_groups(ob):
    me = ob.data
    n = len(me.vertices)
    co = np.zeros(n * 3)
    me.vertices.foreach_get("co", co)
    w = jaw_weight(co.reshape(n, 3))
    at = me.attributes.get("tag")
    if at is not None:
        tag = np.zeros(n)
        at.data.foreach_get("value", tag)
        w = np.where(tag > 1.5, 1.0, np.where(tag > 0.5, 0.0, w))
        w = np.where(tag > 2.5, tag - 3.0, w)            # tag 3 + w: an explicit weight
    gh = ob.vertex_groups.new(name="Head")
    gj = ob.vertex_groups.new(name="Jaw")
    for i in range(n):
        gj.add([i], float(w[i]), "REPLACE")
        gh.add([i], float(1.0 - w[i]), "REPLACE")
    if at is not None:
        me.attributes.remove(at)


# ----------------------------------------------------------------------------- head mesh

def ear_points(side):
    """One ear as a grid (rows from the outer face to the inner face) in world space."""
    C = np.array([0.087, 0.012, 1.632])                        # front view: ear out to x 0.10; side view ear centre
    yaw = math.radians(32)                                     # ears stand out from the head
    a = np.array([math.sin(yaw), math.cos(yaw), 0.0])          # along the ear, front to back
    b = norm(np.array([0.0, 0.12, 1.0]))                       # up the ear, tipped back a little
    n = norm(np.cross(b, a) * -1.0)
    n = n if n[0] > 0 else -n                                  # the outer face
    b = norm(np.cross(n, a))
    b = b if b[2] > 0 else -b

    def sdf(q):
        body = sd_ellipsoid(q, (0, 0, 0), (0.019, 0.034, 0.0072))
        dent = sd_ellipsoid(q, (-0.0015, 0.003, 0.0073), (0.011, 0.022, 0.0055))     # the bowl of the ear
        return smax(body, -dent, 0.004)

    rows = []
    n_col = 16
    phi = 2 * PI * np.arange(n_col) / n_col
    for lat in (72, 50, 30, 14, 2, -12, -32, -58):
        la = math.radians(lat)
        d = np.stack([np.cos(phi) * math.cos(la), np.sin(phi) * math.cos(la), np.full(n_col, math.sin(la))], axis=1)
        o = np.zeros((n_col, 3))
        q = d * raycast(sdf, o, d, 0.06, steps=64)[:, None]
        rows.append(C[None, :] + q[:, 0:1] * a + q[:, 1:2] * b + q[:, 2:3] * n)
    poles = []
    for sgn in (1, -1):
        d = np.array([[0.0, 0.0, float(sgn)]])
        q = d * raycast(sdf, np.zeros((1, 3)), d, 0.06, steps=64)[0]
        poles.append(C + q[0, 2] * n)
    rows = np.array(rows)
    poles = np.array(poles)
    if side < 0:
        rows, poles = mirror_points(rows), mirror_points(poles)
    return rows, poles


LASH = []          # upper-lid rim points of both eyes, for the lash line


def build_head(M_):
    mb = MB()
    P, ELEV, THG = head_grid()
    R = P.shape[0]
    idx = [[mb.vert(P[r, c]) for c in range(M)] for r in range(R)]
    rm = RL + MOUTH_I
    # mouth slit: the lower lip gets its own copies of the mouth-row vertices between the corners
    mbeard = beard_mask(P, np.repeat(ELEV[:, None], M, axis=1), THG)
    mhair = hair_mask(P, THG)
    mhair[-1] = 1.0
    mb.attrs["beard"] = {idx[r][c]: mbeard[r, c] for r in range(R) for c in range(M)}
    mb.attrs["hair"] = {idx[r][c]: mhair[r, c] for r in range(R) for c in range(M)}
    low_row = list(idx[rm])
    for c in range(-MOUTH_C + 1, MOUTH_C):
        low_row[c % M] = mb.vert(P[rm, c % M])
        mb.attrs["beard"][low_row[c % M]] = mbeard[rm, c % M]
        mb.tags[low_row[c % M]] = 2.0          # lower lip: all jaw
        mb.tags[idx[rm][c % M]] = 1.0          # upper lip: all head
    skip = set()
    for i in range(EYE_I0, EYE_I1):
        for c in range(EYE_C0, EYE_C1):
            skip.add((RL + i, c))
            skip.add((RL + i, M - c - 1))
    lower_idx = idx[:rm] + [low_row]
    mb.grid(None, idx=lower_idx, closed=True, uv=(0, 0, 1, 1), flip=False)
    upper_idx = idx[rm:]
    mb.grid(None, idx=upper_idx, closed=True, uv=(0, 0.3, 1, 1), flip=False,
            skip={(r - rm, c) for (r, c) in skip})
    # crown
    top = np.array([0.0, YAX, ZC]) + np.array([0, 0, 1.0]) * raycast(head_sdf, np.array([[0.0, YAX, ZC]]), np.array([[0, 0, 1.0]]), 0.3)[0]
    ci = mb.cap(idx[-1], center=top, outward=(0, 0, 1))
    mb.attrs["hair"][ci] = 1.0
    # neck: join the body's ring (32) to the lowest row (64), two head quads per body edge
    neck = body_neck_ring()
    K = len(neck)
    if K * 2 != M:
        raise RuntimeError("neck ring has %d vertices, expected %d" % (K, M // 2))
    S = [mb.vert(p) for p in neck]
    for i in range(K):
        mb.face([S[i], S[(i + 1) % K], idx[0][(2 * i + 2) % M], idx[0][2 * i + 1], idx[0][2 * i]])
    # eyelids: two loops going in round each eyeball
    loop = eye_loop()
    for side in (1, -1):
        E = np.array(EYE) * np.array([side, 1, 1])
        rim = [idx[RL + i][c if side > 0 else M - c] for ((i, c), _) in loop]
        Pr = np.array([mb.v[i] for i in rim])
        dirn = norm(Pr - E)
        axis = norm(Pr.mean(axis=0) - E)
        perp = norm(dirn - (dirn @ axis)[:, None] * axis[None, :])
        A = E + norm(dirn - 0.05 * perp) * (EYE_R + 0.0004)             # the lid's edge, touching the eyeball
        Bq = E + norm(dirn + 0.30 * perp) * (EYE_R + 0.0004)            # under the lid
        ia = [mb.vert(p) for p in A]
        ib = [mb.vert(p) for p in Bq]
        oc = len(loop) // 2                                # outer corner, along the upper lid, inner corner
        up = [oc] + list(range(oc + 1, len(loop))) + [0]
        LASH.append((Pr[up], dirn[up], perp[up], E))
        mb.grid(None, idx=[rim, ia, ib], closed=True, uv=(0.2, 0.9, 1, 1))
    # lips: three loops going into the mouth, sealed at the corners
    cols = list(range(-MOUTH_C, MOUTH_C + 1))
    up0 = [idx[rm][c % M] for c in cols]
    lo0 = [low_row[c % M] for c in cols]
    base = np.array([P[rm, c % M] for c in cols])
    ws = 1.0 - (np.abs(np.array(cols)) / MOUTH_C) ** 2
    rows_u, rows_l = [up0], [lo0]
    for (dy, dz) in ((0.0045, 0.0008), (0.0105, 0.0035)):
        pu = base + np.stack([np.zeros(len(cols)), np.full(len(cols), dy), dz * ws], axis=1)
        pl = base + np.stack([np.zeros(len(cols)), np.full(len(cols), dy), -dz * ws], axis=1)
        iu = [mb.vert(p) for p in pu]
        il = [mb.vert(p) for p in pl]
        il[0], il[-1] = iu[0], iu[-1]                 # shared at the corners
        for k in range(1, len(cols) - 1):
            mb.tags[iu[k]] = 1.0
            mb.tags[il[k]] = 2.0
        rows_u.append(iu)
        rows_l.append(il)
    mb.grid(None, idx=rows_u, closed=False, uv=(0.4, 0.9, 1, 1), flip=False)
    mb.grid(None, idx=rows_l, closed=False, uv=(0.4, 0.95, 1, 1), flip=False)
    # ears
    for side in (1, -1):
        rows, poles = ear_points(side)
        eidx = mb.grid(rows, closed=True, uv=(0.6 + 0.1 * side, 0.9, 1, 1))
        mb.cap(eidx[0], center=poles[0])
        mb.cap(eidx[-1], center=poles[1])
    ob = mb.build("CH_Rowan_Head", "LOW", OWNER, [M_["skin"]], recalc=True)
    write_jaw_groups(ob)
    return ob, P, ELEV, THG, idx, low_row


# ----------------------------------------------------------------------------- eyes

def build_eye(M_, side):
    mb = MB()
    n = 24
    phi = 2 * PI * np.arange(n) / n
    alphas = [5, 14.8, 21, 27, 33.3, 36.5, 44, 55, 66, 84, 104, 126, 150, 170]      # from the pupil pole
    rows = []
    for a in alphas:
        ar = math.radians(a)
        r = EYE_R + 0.0010 * float(smoothstep(36.5, 19, a))                          # the cornea bulges a little
        rows.append(np.stack([r * math.sin(ar) * np.cos(phi), np.full(n, -r * math.cos(ar)), r * math.sin(ar) * np.sin(phi)], axis=1))
    idx = [[mb.vert(p) for p in row] for row in rows]
    mb.grid(None, idx=idx[0:2], closed=True, mat=2, uv=(0, 0, 1, 1))              # pupil: radius 4.6 mm
    mb.grid(None, idx=idx[1:5], closed=True, mat=1, uv=(0, 0.1, 1, 1))            # iris: radius 12 mm
    mb.grid(None, idx=idx[4:], closed=True, mat=0, uv=(0, 0.3, 1, 1))
    mb.cap(idx[0], center=(0, -(EYE_R + 0.0010), 0), mat=2)
    mb.cap(idx[-1], center=(0, EYE_R, 0), mat=0)
    name = "CH_Rowan_Eye_L" if side > 0 else "CH_Rowan_Eye_R"
    ob = mb.build(name, "LOW", OWNER, [M_["sclera"], M_["iris"], M_["pupil"]], recalc=True)
    ob.location = (EYE[0] * side, EYE[1], EYE[2])
    return ob


# ----------------------------------------------------------------------------- inside the mouth
MOUTH_Z = 1.5855


def build_teeth(M_, upper):
    mb = MB()
    n_teeth, per = 12, 4
    n = n_teeth * per + 1
    u = np.linspace(0, 1, n)
    t = np.radians(-78 + 156 * u)
    a, b = (0.0285, 0.0310) if upper else (0.0270, 0.0290)
    y0 = -0.127 + 0.0310
    cx, cy = a * np.sin(t), y0 - b * np.cos(t)
    nx, ny = np.sin(t) / a, -np.cos(t) / b
    ln = np.sqrt(nx * nx + ny * ny)
    nx, ny = nx / ln, ny / ln
    g = (1 - np.abs(np.sin(PI * n_teeth * u))) ** 3            # 1 on the gaps between teeth
    prof = [(0.0030, 1.6080, 0), (0.0032, 1.5995, 0), (0.0030, 1.5988, 1), (0.0034, 1.5925, 1),
            (0.0028, 1.5868, 1), (-0.0020, 1.5868, 1), (-0.0034, 1.5935, 1), (-0.0036, 1.6080, 1)]
    rows = []
    for (o, z, tooth) in prof:
        oo = o - 0.0007 * g * tooth * (1 if o > 0 else 0)
        zz = np.full(n, z) + (0.0009 * g if abs(z - 1.5868) < 1e-6 else 0.0)
        if not upper:
            zz = 2 * MOUTH_Z - zz - 0.0012
        rows.append(np.stack([cx + nx * oo, cy + ny * oo, zz], axis=1))
    idx = [[mb.vert(p) for p in row] for row in rows]
    mb.grid(None, idx=idx[0:2], closed=False, mat=1, uv=(0, 0, 1, 1))             # gum
    mb.grid(None, idx=idx[1:], closed=False, mat=0, uv=(0, 0.1, 1, 1))
    name = "CH_Rowan_TeethUpper" if upper else "CH_Rowan_TeethLower"
    ob = mb.build(name, "LOW", OWNER, [M_["teeth"], M_["gum"]], recalc=True)
    g_ = ob.vertex_groups.new(name="Head" if upper else "Jaw")
    g_.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    return ob


def build_tongue(M_):
    mb = MB()
    z0 = 1.5665
    st = [(-0.060, 0.0160, 0.0060), (-0.078, 0.0185, 0.0095), (-0.095, 0.0185, 0.0105),
          (-0.107, 0.0165, 0.0095), (-0.114, 0.0120, 0.0072), (-0.118, 0.0055, 0.0045)]
    n = 10
    phi = 2 * PI * np.arange(n) / n + PI / 2            # index 0 is the top centre
    rows = []
    for (y, w, h) in st:
        x = w * sgnpow(np.cos(phi), 0.8)
        z = z0 + h / 2 + (h / 2) * sgnpow(np.sin(phi), 0.8)
        z[0] -= 0.0014                                   # the groove down the middle
        rows.append(np.stack([x, np.full(n, y), z], axis=1))
    idx = mb.grid(rows, closed=True, uv=(0, 0, 1, 1))
    mb.cap(idx[0], outward=(0, 1, 0))
    mb.cap(idx[-1], center=(0, -0.1195, z0 + 0.002), outward=(0, -1, 0))
    ob = mb.build("CH_Rowan_Tongue", "LOW", OWNER, [M_["tongue"]], recalc=True)
    ob.vertex_groups.new(name="Jaw").add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    return ob


def build_mouth_bag(M_):
    """The inside of the mouth: a pocket behind the lips. Its lower half follows the jaw."""
    mb = MB()
    n = 12
    phi = 2 * PI * np.arange(n) / n
    st = [(-0.127, 0.040, 0.0045, 0.0045), (-0.118, 0.041, 0.022, 0.021), (-0.100, 0.040, 0.025, 0.023),
          (-0.078, 0.034, 0.024, 0.022), (-0.058, 0.024, 0.016, 0.016)]
    rows = []
    for (y, rx, up, dn) in st:
        x = rx * np.cos(phi)
        s = np.sin(phi)
        z = MOUTH_Z + np.where(s >= 0, up, dn) * s
        rows.append(np.stack([x, y + 0.016 * (x / 0.044) ** 2, z], axis=1))     # wraps round with the face
    idx = mb.grid(rows, closed=True, uv=(0, 0, 1, 1))
    mb.cap(idx[-1], center=(0, -0.050, MOUTH_Z))
    for i, v in enumerate(mb.v):
        mb.tags[i] = 3.0 + float(smoothstep(MOUTH_Z + 0.003, MOUTH_Z - 0.003, v[2]))
    ob = mb.build("CH_Rowan_Mouth", "LOW", OWNER, [M_["mouth"]], recalc=True)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)          # seen from inside
    bm.to_mesh(ob.data)
    bm.free()
    write_jaw_groups(ob)
    return ob


# ----------------------------------------------------------------------------- beard and brows

def beard_mask(P, elev, th):
    """1 where the beard grows, falling to 0 at its edge (front view: cheek line, moustache, lips left bare)."""
    x, y, z = np.abs(P[..., 0]), P[..., 1], P[..., 2]
    thd = np.abs((np.degrees(th) + 180.0) % 360.0 - 180.0)          # 0 at the front, 180 at the back
    top_tab = [(0, 1.6065), (8, 1.6050), (16, 1.6000), (24, 1.5975), (32, 1.5960), (45, 1.6030),
               (60, 1.6190), (75, 1.6430), (84, 1.6650), (120, 1.6680)]
    ztop = np.interp(thd, [t[0] for t in top_tab], [t[1] for t in top_tab])
    # wide ramps: the shell crosses the skin half way down each ramp, so its edge is a smooth line
    m = smoothstep(ztop + 0.010, ztop - 0.014, z)
    m = np.minimum(m, smoothstep(96, 72, thd))                                   # stops in front of the ear
    bot_tab = [(0, 1.440), (32, 1.440), (46, 1.508), (60, 1.530), (75, 1.553), (90, 1.580), (180, 1.580)]
    zbot = np.interp(thd, [t[0] for t in bot_tab], [t[1] for t in bot_tab])
    m = np.minimum(m, smoothstep(zbot - 0.012, zbot + 0.010, z))                 # follows the jaw line at the sides
    under = smoothstep(-30, -8, elev) * smoothstep(62, 40, thd)
    m = np.minimum(m, np.where(elev < 0, under, 1.0))                            # under the chin only, fading out
    nose = smoothstep(-0.150, -0.138, y)
    m = np.minimum(m, np.where(z > 1.598, nose, 1.0))                            # not on the nose
    dzs = z - (1.5840 + SMILE * (x / 0.040) ** 2)              # height above the line of the mouth
    lips = smoothstep(-0.0088, -0.0052, dzs) * smoothstep(0.0030, 0.0010, dzs) * smoothstep(0.045, 0.037, x)
    m = np.minimum(m, 1.0 - lips)                                                # the lower lip and the mouth line stay bare
    return m


def hair_mask(P, th):
    """1 on the scalp where hair grows: the hairline from the forehead round to the nape."""
    thd = np.abs((np.degrees(th) + 180.0) % 360.0 - 180.0)
    tab = [(0, 1.750), (20, 1.752), (40, 1.742), (55, 1.716), (68, 1.678), (80, 1.657), (95, 1.642),
           (110, 1.612), (130, 1.592), (180, 1.582)]
    zl = np.interp(thd, [t[0] for t in tab], [t[1] for t in tab])
    return smoothstep(zl - 0.010, zl + 0.012, P[..., 2])


def build_beard(M_, P, ELEV, THG, low_row_src):
    R = P.shape[0]
    rm = RL + MOUTH_I
    E2 = np.repeat(ELEV[:, None], M, axis=1)
    m = beard_mask(P, E2, THG)
    nrm = sdf_normal(head_sdf, P.reshape(-1, 3)).reshape(R, M, 3)
    chin = smoothstep(1.568, 1.535, P[..., 2]) * smoothstep(40, 18, np.abs((np.degrees(THG) + 180.0) % 360.0 - 180.0))
    thick = 0.0034 + 0.0055 * chin                       # ref: beard 5 mm on the cheeks, 13 mm under the chin
    off = lerp(-0.0030, thick, smoothstep(0.45, 1.0, m) ** 1.5)       # the shell starts inside the painted stubble
    Q = P + nrm * off[..., None]
    mb = MB()
    wj = jaw_weight(P.reshape(-1, 3)).reshape(R, M)
    use = np.zeros((R, M), dtype=bool)
    cells = []
    for r in range(R - 1):
        for c in range(M):
            c2 = (c + 1) % M
            if max(m[r, c], m[r, c2], m[r + 1, c], m[r + 1, c2]) > 0.02:
                cells.append((r, c))
                use[r, c] = use[r, c2] = use[r + 1, c] = use[r + 1, c2] = True
    vid, vid_low = {}, {}
    for r in range(R):
        for c in range(M):
            if use[r, c]:
                vid[(r, c)] = mb.vert(Q[r, c])
                mb.tags[vid[(r, c)]] = 3.0 + float(wj[r, c])
    slit = {c % M for c in range(-MOUTH_C + 1, MOUTH_C)}
    for c in slit:
        if (rm, c) in vid:
            vid_low[c] = mb.vert(Q[rm, c])
            mb.tags[vid_low[c]] = 3.0 + 1.0
            mb.tags[vid[(rm, c)]] = 3.0 + 0.0
    for (r, c) in cells:
        c2 = (c + 1) % M
        def v(rr, cc):
            if rr == rm and r + 1 == rm and cc in vid_low:      # the cell below the mouth line
                return vid_low[cc]
            return vid[(rr, cc)]
        q = [v(r, c), v(r, c2), v(r + 1, c2), v(r + 1, c)]
        uv = [(THG[r, c], P[r, c, 2]), (THG[r, c2] if c2 else 2 * PI, P[r, c2, 2]),
              (THG[r + 1, c2] if c2 else 2 * PI, P[r + 1, c2, 2]), (THG[r + 1, c], P[r + 1, c, 2])]
        mb.face(q, [(a * 0.08, b) for (a, b) in uv])
    ob = mb.build("CH_Rowan_Beard", "LOW", OWNER, [M_["beard"]], recalc=True)
    write_jaw_groups(ob)
    return ob


def build_brows(M_):
    mb = MB()
    ctrl = [(0.0120, 1.6900), (0.0270, 1.6965), (0.0430, 1.6990), (0.0580, 1.6965), (0.0720, 1.6895)]   # front view
    path = resample(spline([(x, 0, z) for (x, z) in ctrl], 6), 13)
    n = len(path)
    s = np.linspace(0, 1, n)
    half = np.interp(s, [0, 0.12, 0.5, 0.85, 1.0], [0.0050, 0.0080, 0.0072, 0.0048, 0.0012])   # ref: 14 mm thick
    lift_end = np.interp(s, [0, 0.1, 0.9, 1.0], [0.3, 1.0, 1.0, 0.2])
    across = np.linspace(-1, 1, 5)
    for side in (1, -1):
        rows = []
        for w in across:
            x = path[:, 0]
            z = path[:, 2] + half * w
            p = front_project(x, z)
            nr = sdf_normal(head_sdf, p)
            lift = (-0.0008 + 0.0042 * (1 - w ** 4)) * lift_end
            rows.append(p + nr * lift[:, None])
        rows = np.array(rows)
        if side < 0:
            rows = mirror_points(rows)
        mb.grid(rows, closed=False, uv=(0.5 + side * 0.3, 0, 1, 1), flip=side < 0)
    # lash line: a dark ribbon along each upper lid (ref: a heavy upper lid line)
    for (Pr, dirn, perp, EC) in LASH:
        k = len(Pr)
        t = np.linspace(0, 1, k)
        wdt = 0.0012 + 0.0026 * np.sin(PI * t) ** 0.7
        Aq = Pr - dirn * (np.linalg.norm(Pr - EC, axis=1) - (EYE_R + 0.0006))[:, None]        # the lid's edge on the eyeball
        span = Pr - Aq
        ln = np.maximum(np.linalg.norm(span, axis=1), 1e-6)[:, None]
        lift = dirn * 0.0004 - perp * 0.0005                 # just proud of the lid margin
        inner = Aq + lift
        outer = Aq + span / ln * np.minimum(ln, wdt[:, None]) + lift
        mb.grid([inner, outer], closed=False, uv=(0.9, 0.5, 1, 1))
    ob = mb.build("CH_Rowan_Brows", "LOW", OWNER, [M_["brow"]], recalc=True)
    ob.vertex_groups.new(name="Head").add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    return ob


# ----------------------------------------------------------------------------- build

def mats():
    return dict(
        skin=material("CH_Rowan_Skin", (0.800, 0.440, 0.300), 0.6),
        sclera=material("CH_Rowan_EyeWhite", (0.90, 0.90, 0.88), 0.25),
        iris=material("CH_Rowan_Iris", (0.10, 0.30, 0.55), 0.2),
        pupil=material("CH_Rowan_Pupil", (0.01, 0.01, 0.012), 0.15),
        teeth=material("CH_Rowan_Teeth", (0.86, 0.84, 0.78), 0.35),
        gum=material("CH_Rowan_Gum", (0.62, 0.25, 0.24), 0.45),
        tongue=material("CH_Rowan_Tongue", (0.66, 0.26, 0.26), 0.45),
        mouth=material("CH_Rowan_MouthInside", (0.16, 0.035, 0.035), 0.6),
        beard=material("CH_Rowan_Beard", (0.085, 0.040, 0.020), 0.9),
        brow=material("CH_Rowan_Brow", (0.075, 0.035, 0.018), 0.9),
    )


def build():
    M_ = mats()
    head, P, ELEV, THG, idx, low_row = build_head(M_)
    obs = [head, build_eye(M_, 1), build_eye(M_, -1), build_teeth(M_, True), build_teeth(M_, False),
           build_tongue(M_), build_mouth_bag(M_), build_beard(M_, P, ELEV, THG, low_row), build_brows(M_)]
    for ob in obs:
        me = ob.data
        log(ob.name, "verts", len(me.vertices), "tris", sum(len(p.vertices) - 2 for p in me.polygons))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True)
    a = p.parse_args(argv_after_dashes())
    open_master(a.master)
    clear_owned(OWNER)
    build()
    save_master(a.master)
    log("saved", a.master)
