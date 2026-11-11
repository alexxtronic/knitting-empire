"""
CH_Rowan phase 05: hair. One object, CH_Rowan_Hair, rigid to the head and separate from it,
so the hairstyle can be swapped.

  Blender --background --python build/05_hair.py -- --master CH_Rowan_master.blend

Built the way stylised game hair usually is: a cap that follows the scalp, and over it
chunky locks. Each lock is a tapered tube laid along a path that is combed over the scalp
away from the centre parting, pulled down by gravity, waved, and flicked out at the tip.
UVs run along each lock, so a strand texture follows the hair.

Reference: centre parting, wavy mid-length hair swept to the sides, covering the top of the
ears and ending at the nape (ref/front.png, side.png, back.png). Hair top 1.80, widest 0.256
at z 1.656, back of the hair at y +0.135.
"""
import bpy, sys, os, math, argparse, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from common import *
from spec import *

head = importlib.import_module("03_head")
PHASE = "05_hair"
OWNER = "phase:" + PHASE
C0 = np.array([0.0, -0.010, 1.685])          # centre of the cranium


def log(*a):
    print("[" + PHASE + "]", *a)


def scalp(u):
    """Point of the bare head along direction u from the cranium centre, and its normal."""
    u = np.atleast_2d(u)
    o = np.repeat(C0[None, :], len(u), axis=0)
    p = o + u * raycast(head.head_sdf, o, u, 0.3, steps=64, refine=10)[:, None]
    return p


def lock_path(u0, v0, length, lift, grav=0.10, wave=0.0, phase=0.0, period=7.0, flick=0.010, step=0.012,
              lift_root=0.004):
    """Comb a path over the scalp: start direction u0, heading v0. Returns points (n, 3) and normals."""
    n = max(4, int(round(length / step)))
    u = norm(np.asarray(u0, dtype=float))
    v = np.asarray(v0, dtype=float)
    v = norm(v - np.dot(v, u) * u)
    pts, nrms = [], []
    for k in range(n + 1):
        t = k / n
        s = scalp(u)[0]
        h = lift_root + lift * math.sin(PI * min(t / 0.85, 1.0)) ** 0.8
        if t > 0.72:
            h += flick * ((t - 0.72) / 0.28) ** 2
        pts.append(s + u * h)
        nrms.append(u.copy())
        # next direction
        r = np.linalg.norm(s - C0)
        g = np.array([0.0, 0.0, -1.0])
        g = g - np.dot(g, u) * u
        if np.linalg.norm(g) > 1e-6:
            gg = grav if t < 0.72 else -grav * 1.2          # the tip turns up: the flick
            v = norm(v * (1 - abs(gg)) + norm(g) * gg)
        a = wave * math.sin(phase + 2 * PI * k / period)
        v = norm(v * math.cos(a) + np.cross(u, v) * math.sin(a))
        u = norm(u + v * (step / r))
        v = norm(v - np.dot(v, u) * u)
    return np.array(pts), np.array(nrms)


def add_lock(mb, pts, nrms, w0, th0, uvx):
    """A tapered tube with a flat underside along the path."""
    n = len(pts)
    T = np.zeros_like(pts)
    T[1:-1] = pts[2:] - pts[:-2]
    T[0], T[-1] = pts[1] - pts[0], pts[-1] - pts[-2]
    T = norm(T)
    prof = [(-1.0, 0.10), (-0.60, 0.80), (0.0, 1.0), (0.60, 0.80), (1.0, 0.10), (0.55, -0.40), (0.0, -0.55), (-0.55, -0.40)]
    rows = []
    for k in range(n):
        t = k / (n - 1)
        wt = min(1.0, (t + 0.04) / 0.16) ** 0.6 * max(0.0, 1 - t ** 4.0) ** 0.55       # narrow root, full middle, blunt tip
        w = w0 * max(wt, 0.03)
        th = th0 * (0.55 + 0.45 * wt)
        N = nrms[k] - np.dot(nrms[k], T[k]) * T[k]
        N = norm(N)
        Bv = np.cross(T[k], N)
        rows.append([pts[k] + Bv * (b * w) + N * (h * th) for (b, h) in prof])
    idx = mb.grid(rows, closed=True, uv=(uvx, 0, 1, 1))
    mb.cap(idx[0], outward=-T[0])
    mb.cap(idx[-1], outward=T[-1])


def part_dir(gamma_deg, x=0.0):
    g = math.radians(gamma_deg)
    return norm(np.array([x, math.sin(g), math.cos(g)]))


def build_locks(mb):
    rng = np.random.RandomState(7)
    n = 0
    # A: from the centre parting out to both sides and back. gamma: -56 = over the forehead, 0 = top, +38 = crown.
    # The front ones are the "curtains": they lift off the forehead, sweep out past the temples and flick up.
    for i, gam in enumerate(np.linspace(-56, 38, 10)):
        f = i / 9.0
        for side in (1, -1):
            u0 = part_dir(gam, side * 0.035)
            v0 = np.array([side * 1.0, lerp(0.42, 0.85, f), 0.15])
            length = lerp(0.128, 0.165, f) * (1 + 0.07 * rng.randn())
            lift = lerp(0.034, 0.026, f) * (1 + 0.20 * rng.randn())
            pts, nr = lock_path(u0, v0, length, lift, grav=lerp(0.05, 0.09, f), wave=0.19, phase=rng.rand() * 6.28,
                                period=6.5 + rng.rand() * 2.0, flick=0.032)
            add_lock(mb, pts, nr, 0.022 * (1 + 0.15 * rng.randn()), 0.012, 0.1 * n)
            n += 1
    # B: the layer underneath, behind the ears and round the back, falling to the nape and curling out
    for ring_i, (el, length, lift) in enumerate(((50, 0.120, 0.026), (28, 0.104, 0.023))):
        for az in np.arange(76 + 9 * ring_i, 181, 17.5):
            for side in ((1, -1) if az < 179 else (1,)):
                a, e = math.radians(az), math.radians(el)
                u0 = np.array([side * math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)])
                v0 = np.array([side * math.sin(a) * 0.25, -math.cos(a) * 0.25 + 0.35, -1.0])
                ln = length * (1 + 0.08 * rng.randn())
                pts, nr = lock_path(u0, v0, ln, lift * (1 + 0.2 * rng.randn()), grav=0.14, wave=0.20,
                                    phase=rng.rand() * 6.28, period=6.0 + rng.rand() * 2.0, flick=0.028)
                add_lock(mb, pts, nr, 0.023 * (1 + 0.15 * rng.randn()), 0.0115, 0.1 * n)
                n += 1
    # C: from the crown down the back
    for az in (128, 146, 164, 180):
        for side in ((1, -1) if az < 179 else (1,)):
            u0 = part_dir(34, 0.0) + np.array([side * 0.10 * math.sin(math.radians(az)), 0.03, 0])
            a = math.radians(az)
            v0 = np.array([side * math.sin(a), -math.cos(a), -0.2])
            pts, nr = lock_path(u0, v0, 0.150 * (1 + 0.06 * rng.randn()), 0.028, grav=0.12, wave=0.18,
                                phase=rng.rand() * 6.28, period=7.0, flick=0.022)
            add_lock(mb, pts, nr, 0.024, 0.012, 0.1 * n)
            n += 1
    return n


def build_cap(mb):
    """A shell over the scalp under the locks, so no skin shows between them."""
    P, ELEV, THG = head.head_grid()
    R, M = P.shape[0], P.shape[1]
    m = head.hair_mask(P, THG)
    m[-1] = 1.0
    nrm = sdf_normal(head.head_sdf, P.reshape(-1, 3)).reshape(R, M, 3)
    off = lerp(-0.003, 0.014, smoothstep(0.45, 0.95, m))        # the cap starts inside the painted hairline
    Q = P + nrm * off[..., None]
    vid = {}
    for r in range(R - 1):
        for c in range(M):
            c2 = (c + 1) % M
            if max(m[r, c], m[r, c2], m[r + 1, c], m[r + 1, c2]) > 0.02:
                q = []
                for (rr, cc) in ((r, c), (r, c2), (r + 1, c2), (r + 1, c)):
                    if (rr, cc) not in vid:
                        vid[(rr, cc)] = mb.vert(Q[rr, cc])
                    q.append(vid[(rr, cc)])
                mb.face(q, [(0.9, 0.0), (0.91, 0.0), (0.91, 0.01), (0.9, 0.01)])
    top_ring = [vid[(R - 1, c)] for c in range(M)]
    top = C0 + np.array([0, 0, 1.0]) * (raycast(head.head_sdf, C0[None, :], np.array([[0, 0, 1.0]]), 0.3)[0] + 0.011)
    mb.cap(top_ring, center=top, outward=(0, 0, 1))


def build():
    hair = material("CH_Rowan_Hair", (0.130, 0.060, 0.028), 0.75)
    mb = MB()
    build_cap(mb)
    n = build_locks(mb)
    ob = mb.build("CH_Rowan_Hair", "LOW", OWNER, [hair], recalc=True)
    ob.vertex_groups.new(name="Head").add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    me = ob.data
    zs = [v.co.z for v in me.vertices]
    xs = [abs(v.co.x) for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    log(ob.name, "locks", n, "verts", len(me.vertices), "tris", sum(len(p.vertices) - 2 for p in me.polygons),
        "top %.3f half width %.3f back %.3f" % (max(zs), max(xs), max(ys)))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--master", required=True)
    a = p.parse_args(argv_after_dashes())
    open_master(a.master)
    clear_owned(OWNER)
    build()
    save_master(a.master)
    log("saved", a.master)
