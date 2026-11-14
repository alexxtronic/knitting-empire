"""
Real eyes for a Tripo character, in place of the eyes painted on its head: a clean almond-shaped opening cut in
the face, a plain eyeball behind it and two lids that close over it, so the game can blink, turn the eyes and
set the lids for a mood (scripts/face.gd).

  Blender -b tools/character_build/<id>/<id>.blend -P tools/add_eyes.py -- "$PWD" <id>             build
  Blender -b tools/character_build/<id>/<id>.blend -P tools/add_eyes.py -- "$PWD" <id> --probe     measure
  Blender -b tools/character_build/<id>/<id>.blend -P tools/add_eyes.py -- "$PWD" <id> --overlay   check

A new character: --probe writes _front_map.png in tools/character_build/<id>_eyes/ (the face seen from the
front, 0.25 mm a pixel, with a line every 5 mm; --region x0 x1 z0 z1 in metres looks elsewhere). Read the
painted eyes off it into EYES below, then --overlay draws that outline over the map to check it.

The build writes tools/character_build/<id>_eyes/<id>_eyes.blend and assets/<id>_eyes.glb; the source model is
not changed. How:

1. The painted eyes are painted out of the albedo: skin grown in over each eye, its lashes and lid lines.
2. Each eye's outline is an almond (EYES), the same shape on both sides. The eyeball is a sphere behind it,
   as round as the face is there; every new part sits on spheres round that centre.
3. The head is cut along the outline grown by the lid's width, and a new lid rim is built in the gap: from
   the face it rolls in to the eyeball, so the edge of the opening is the clean almond whatever the mesh was.
4. A new mesh (<Armature>Eyes) skinned to the Head and two eye bones: each eyeball a cap of its sphere with a
   drawn iris and pupil, and an upper and a lower lid, thin shells just over the eyeball that wait under the
   rim while the eye is open. The upper lid's edge is the lash line.
5. Its shape keys: blink_L and blink_R (the upper lid comes down to meet the lower, which rises a little),
   lid_half, lid_angry and lid_sad (the upper lids part way: evenly, inner corners first, outer corners
   first) and squint (the lower lids up). A blend shape moves each point in a straight line, which cuts
   inside a sphere, so the lids ride far enough out that a lid on its way down never dips into the eyeball.
"""
import bpy, bmesh, sys, os, math, json
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, CID = argv[0], argv[1]
PROBE, OVERLAY = "--probe" in argv, "--overlay" in argv
OUT = os.path.join(PROJECT, "tools", "character_build", CID + "_eyes")
os.makedirs(OUT, exist_ok=True)
MM = 0.001
STEP = 0.00025                      # the front map's pixel
LID_PAST = 0.006                    # the lids reach this far above and below the opening, under the skin

# Each character's eyes, in millimetres, as the front map shows them (the model faces -Y, X is to her left):
#   mid     the face's centre line (x)              dx      each eye's centre from that line
#   z       the height of the line between the corners, at the eye's middle
#   a       half the width, corner to corner      up, lo  how far the upper and lower arcs rise and dip from that line
#   tilt    how much higher the outer corner is than the inner
#   k_up, k_lo  where along the eye each arc peaks: -1 the inner corner, 0 the middle, 1 the outer
#   p       the arcs' shape: 1 an almond (pointed corners), 0.5 round
#   lash    the lash line's thickness at its thickest
#   iris    the iris's radius (default: half the two arcs' heights together)
#   rim     the lid rim's width round the opening
#   R       the eyeball's radius (default: from the face's own curve round the eye)
#   reach   paint touching the eye is painted out if it ends within this of the outline (default 16; Nora's
#           liner flicks out 17 mm)
#   loose   1 also paints out dark marks near the eye that don't touch it (a lash flick painted above the outer
#           corner, Lars), as long as they end within REACH; a brow or hair runs on past it and stays
EYES = {
    "gary_tripo": dict(mid=-0.1, dx=40.6, z=1617.75, a=21.0, up=7.6, lo=6.6, tilt=-3.5, k_up=-0.1, k_lo=0.1, p=0.85, lash=1.6),
    "giorgio_tripo": dict(mid=0.4, dx=52.1, z=1687.0, a=25.0, up=19.0, lo=10.5, k_up=-0.1, p=0.6, lash=1.8, rim=2.5),
    "steve_tripo": dict(mid=0.4, dx=49.85, z=1739.0, a=19.5, up=13.0, lo=7.0, k_up=-0.05, k_lo=-0.05, p=0.7, lash=1.5),
    "barbara_tripo": dict(mid=-0.5, dx=54.2, z=1568.5, a=25.5, up=20.5, lo=9.0, tilt=3.0, k_up=-0.03, p=0.7, lash=2.2, rim=2.5),
    "sabrina_tripo": dict(mid=-0.7, dx=38.6, z=1502.0, a=19.2, up=9.5, lo=9.5, tilt=4.5, k_up=0.1, k_lo=0.07, p=0.85, lash=2.0),
    "nora_tripo": dict(mid=-3.5, dx=52.2, z=1480.75, a=24.8, up=16.6, lo=13.5, tilt=9.0, k_up=-0.2, k_lo=0.1, p=0.75, lash=2.4, rim=2.5, reach=18.0),
    "rowan_tripo": dict(mid=-3.75, dx=43.15, z=1625.3, a=21.0, up=14.2, lo=10.6, tilt=3.1, k_up=-0.1, k_lo=-0.05, p=0.75, lash=2.0),
    "wren_tripo": dict(mid=-0.6, dx=45.6, z=1446.9, a=21.1, up=13.2, lo=8.8, tilt=6.0, k_up=0.2, k_lo=-0.03, p=0.7, lash=2.2),
    "rosa_tripo": dict(mid=-0.3, dx=44.3, z=1299.5, a=23.3, up=15.0, lo=9.0, tilt=-4.0, k_up=-0.1, p=0.75, lash=2.2, rim=2.5),
    "max_tripo": dict(mid=-0.25, dx=38.25, z=1622.75, a=17.75, up=10.0, lo=6.5, k_up=-0.1, k_lo=0.1, p=0.8, lash=1.6, iris=11.0),
    "lars_tripo": dict(mid=-0.4, dx=45.9, z=1665.5, a=18.0, up=10.0, lo=6.8, tilt=-1.5, k_up=-0.1, k_lo=0.1, p=0.8, lash=1.8, iris=11.0, loose=1),
}
DEFAULTS = dict(tilt=0.0, k_up=0.0, k_lo=0.0, p=0.85, lash=1.0, iris=0.0, rim=2.0, R=0.0, loose=0, reach=16.0)
SPEC = None
if CID in EYES:
    SPEC = dict(DEFAULTS)
    SPEC.update(EYES[CID])
    for k_ in ("mid", "dx", "z", "a", "up", "lo", "tilt", "lash", "iris", "rim", "R", "reach"):
        SPEC[k_] *= MM

RECESS = 0.6 * MM                   # the eyeball's front sits this far behind where the painted eye was
GAZE = (10.0, 7.0)                  # how far face.gd turns the eyes (MAX_YAW, MAX_PITCH, degrees)


def log(*a):
    print("[add_eyes]", *a, flush=True)


def _region():
    if "--region" in argv:                       # --region x0 x1 z0 z1 (metres), to find a new character's eyes
        i = argv.index("--region")
        return dict(x=(float(argv[i + 1]), float(argv[i + 2])), z=(float(argv[i + 3]), float(argv[i + 4])))
    if SPEC:
        h = max(SPEC["up"], SPEC["lo"]) + abs(SPEC["tilt"]) / 2 + 0.016
        w = SPEC["dx"] + SPEC["a"] + 0.016
        return dict(x=(SPEC["mid"] - w, SPEC["mid"] + w), z=(SPEC["z"] - h, SPEC["z"] + h))
    arm_ = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    hz = (arm_.matrix_world @ arm_.data.bones["Head"].head_local).z
    return dict(x=(-0.115, 0.115), z=(hz - 0.03, hz + 0.105))


REGION = _region()


def body_mesh():
    return next(o for o in bpy.data.objects if o.type == "MESH" and len(o.data.vertices) > 5000)


def albedo(ob):
    for n in ob.data.materials[0].node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
            w, h = img.size
            px = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            return img, px.reshape(h, w, 4)[..., :3].copy()
    raise RuntimeError("no albedo image on " + ob.name)


class Surface:
    """The model's surface as it is now, for casting rays at."""

    def __init__(self, me):
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        uvl = bm.loops.layers.uv.active
        self.verts = [v.co.copy() for v in bm.verts]
        self.tris = [[v.index for v in f.verts] for f in bm.faces]
        self.uvs = [[l[uvl].uv.copy() for l in f.loops] for f in bm.faces]
        self.bvh = BVHTree.FromPolygons(self.verts, self.tris)
        bm.free()

    def uv(self, loc, fi):
        a, b, c = (self.verts[k] for k in self.tris[fi])
        v0, v1, v2 = b - a, c - a, loc - a
        d00, d01, d11, d20, d21 = v0.dot(v0), v0.dot(v1), v1.dot(v1), v2.dot(v0), v2.dot(v1)
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-24:
            return self.uvs[fi][0].copy()
        bv = (d11 * d20 - d01 * d21) / den
        bw = (d00 * d21 - d01 * d20) / den
        return self.uvs[fi][0] * (1 - bv - bw) + self.uvs[fi][1] * bv + self.uvs[fi][2] * bw

    def front(self, x, z):
        loc, nrm, fi, d = self.bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
        return loc, fi

    def near(self, x, z, C, Rf):
        """Of everything at (x, z) seen from the front, the point nearest the sphere (C, Rf): the skin, not a
        lock of hair or a spectacle frame in front of it, nor a layer under it."""
        o = Vector((x, -1.0, z))
        Cv = Vector(C)
        best = None
        for _ in range(6):
            loc, nrm, fi, d = self.bvh.ray_cast(o, Vector((0, 1, 0)))
            if loc is None:
                break
            e = abs((loc - Cv).length - Rf)
            if best is None or e < best[0]:
                best = (e, loc.copy(), fi)
            o = loc + Vector((0, 2e-5, 0))
        if best is None:
            raise RuntimeError("nothing at x %.4f z %.4f" % (x, z))
        return np.array(best[1]), best[2]


def front_map(surf, tex):
    """Cast rays at the face from the front. Returns colour (H, W, 3, row 0 = lowest z), hit position,
    hit mask and UV."""
    xs = np.arange(REGION["x"][0], REGION["x"][1], STEP)
    zs = np.arange(REGION["z"][0], REGION["z"][1], STEP)
    H, W = len(zs), len(xs)
    col = np.zeros((H, W, 3), dtype=np.float32)
    pos = np.zeros((H, W, 3), dtype=np.float32)
    uvm = np.zeros((H, W, 2), dtype=np.float32)
    hit = np.zeros((H, W), dtype=bool)
    th, tw = tex.shape[:2]
    for j, z in enumerate(zs):
        for i, x in enumerate(xs):
            loc, fi = surf.front(x, z)
            if loc is None:
                continue
            uv = surf.uv(loc, fi)
            col[j, i] = tex[int(uv.y % 1.0 * th) % th, int(uv.x % 1.0 * tw) % tw]
            pos[j, i] = loc
            uvm[j, i] = uv
            hit[j, i] = True
    return xs, zs, col, pos, hit, uvm


def save_png(path, rgb):
    """rgb (H, W, 3) 0..1, row 0 at the bottom."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.new("tmp_png", w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def hsv(rgb):
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return s, mx


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


def grow(m, n):
    for _ in range(n):
        m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    return m


def fit_sphere(P):
    """Least-squares sphere through points (N, 3): centre, radius."""
    A = np.hstack([2 * P, np.ones((len(P), 1))])
    b = (P ** 2).sum(axis=1)
    x = np.linalg.lstsq(A, b, rcond=None)[0]
    c = x[:3]
    return c, float(np.sqrt(max(x[3] + c @ c, 0.0)))


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Almond:
    """One eye's outline in the front view (x, z in metres). Eye 0 is her right (at -X), eye 1 her left.
    Along the eye, s runs from -1 at the inner corner to 1 at the outer."""

    def __init__(self, k, n=361):
        S = SPEC
        self.k = k
        self.out = -1.0 if k == 0 else 1.0
        self.cx = S["mid"] + self.out * S["dx"]
        s = np.linspace(-1.0, 1.0, n)
        x, zu, zl = self.at_s(s)
        poly = np.concatenate([np.stack([x, zu], 1), np.stack([x[::-1], zl[::-1]], 1)[1:-1]])
        px, pz = poly[:, 0], poly[:, 1]
        px2, pz2 = np.roll(px, -1), np.roll(pz, -1)
        cr = px * pz2 - px2 * pz
        A = cr.sum() / 2
        self.c = np.array([((px + px2) * cr).sum() / (6 * A), ((pz + pz2) * cr).sum() / (6 * A)])
        th = np.arctan2(pz - self.c[1], px - self.c[0])
        o = np.argsort(th)
        self.th, self.rr = th[o], np.hypot(px - self.c[0], pz - self.c[1])[o]
        self.n = n

    @staticmethod
    def _g(s, kk):
        t = (s - kk) / (1 - kk * s)
        return np.clip(1 - t * t, 0, 1) ** SPEC["p"]

    def at_s(self, s):
        """x, upper z and lower z at s; past the corners (|s| > 1) the line carries on level with them."""
        S = SPEC
        s = np.asarray(s, dtype=float)
        sc = np.clip(s, -1, 1)
        x = self.cx + self.out * s * S["a"]
        zc = S["z"] + S["tilt"] * sc / 2
        return x, zc + S["up"] * self._g(sc, S["k_up"]), zc - S["lo"] * self._g(sc, S["k_lo"])

    def r(self, th):
        return np.interp(th, self.th, self.rr, period=2 * np.pi)

    def excess(self, x, z):
        """How far each point lies outside the outline, along the ray from its centre (negative: inside)."""
        th = np.arctan2(z - self.c[1], x - self.c[0])
        return np.hypot(x - self.c[0], z - self.c[1]) - self.r(th)

    def around(self, m):
        """About m points round the outline, evenly spaced along it: the upper arc from the inner corner to the
        outer, then the lower arc back (corners once each). Returns points (m, 2), their angle about the centre
        and whether each is on the upper arc, in order of increasing angle."""
        s = np.linspace(-1, 1, 801)
        x, zu, zl = self.at_s(s)
        lu = np.concatenate([[0], np.cumsum(np.hypot(np.diff(x), np.diff(zu)))])
        ll = np.concatenate([[0], np.cumsum(np.hypot(np.diff(x), np.diff(zl)))])
        mu = max(8, int(round(m * lu[-1] / (lu[-1] + ll[-1]))))
        ml = max(8, m - mu)
        su = np.interp(np.linspace(0, lu[-1], mu + 1), lu, s)
        sl = np.interp(np.linspace(0, ll[-1], ml + 1), ll, s)[::-1][1:-1]
        xu, zu_, _ = self.at_s(su)
        xl, _, zl_ = self.at_s(sl)
        P = np.concatenate([np.stack([xu, zu_], 1), np.stack([xl, zl_], 1)])
        up = np.concatenate([np.ones(len(su), bool), np.zeros(len(sl), bool)])
        th = np.arctan2(P[:, 1] - self.c[1], P[:, 0] - self.c[0])
        o = np.argsort(th)
        return P[o], th[o], up[o]


# ----------------------------------------------------------------------------- probe and overlay

def draw_map(col, almonds=(), grid=True):
    img = col.copy()
    H, W = img.shape[:2]
    if grid:
        for mm in range(int(math.ceil(REGION["x"][0] * 1000)), int(REGION["x"][1] * 1000) + 1):
            if mm % 5 == 0:
                i = int(round((mm / 1000 - REGION["x"][0]) / STEP))
                if 0 <= i < W:
                    img[:, i] = img[:, i] * 0.5 + (np.array((0.1, 0.4, 1.0)) if mm % 10 == 0 else np.array((0.4, 0.7, 1.0))) * 0.5
        for mm in range(int(math.ceil(REGION["z"][0] * 1000)), int(REGION["z"][1] * 1000) + 1):
            if mm % 5 == 0:
                j = int(round((mm / 1000 - REGION["z"][0]) / STEP))
                if 0 <= j < H:
                    img[j] = img[j] * 0.5 + (np.array((0.1, 0.4, 1.0)) if mm % 10 == 0 else np.array((0.4, 0.7, 1.0))) * 0.5

    def dot(x, z, c):
        i = int(round((x - REGION["x"][0]) / STEP))
        j = int(round((z - REGION["z"][0]) / STEP))
        if 0 <= i < W and 0 <= j < H:
            img[j, i] = c
    for al in almonds:
        s = np.linspace(-1, 1, 2000)
        x, zu, zl = al.at_s(s)
        for a_, b_, c_ in zip(x, zu, zl):
            dot(a_, b_, (1, 0, 0))
            dot(a_, c_, (0, 0.9, 0))
        P, th, up = al.around(400)
        for (px, pz), t in zip(P, th):
            d = np.array([math.cos(t), math.sin(t)]) * SPEC["rim"]
            dot(px + d[0], pz + d[1], (1, 1, 0))
        for d in range(-6, 7):
            dot(al.c[0] + d * STEP, al.c[1], (1, 0, 1))
            dot(al.c[0], al.c[1] + d * STEP, (1, 0, 1))
    return img


if PROBE or OVERLAY:
    ob = body_mesh()
    img, tex = albedo(ob)
    cache = os.path.join(OUT, "_front_col.npy")
    reg_file = os.path.join(OUT, "_front_region.json")
    if OVERLAY and os.path.exists(cache) and os.path.exists(reg_file) and json.load(open(reg_file)) == REGION:
        col = np.load(cache)
    else:
        surf = Surface(ob.data)
        xs, zs, col, pos, hit, uvm = front_map(surf, tex)
        np.save(cache, col)
        np.save(os.path.join(OUT, "_front_pos.npy"), pos)
        json.dump(REGION, open(reg_file, "w"))
        log("front map", col.shape, "hit", hit.mean().round(3), "region", REGION)
        log("y range of the face in the region", float(pos[..., 1][hit].min()), float(pos[..., 1][hit].max()))
    save_png(os.path.join(OUT, "_front_map.png"), draw_map(col))
    if OVERLAY and SPEC:
        save_png(os.path.join(OUT, "_overlay.png"), draw_map(col, [Almond(0), Almond(1)], grid=False))
        log("overlay written:", os.path.join(OUT, "_overlay.png"))
    sys.exit(0)

if SPEC is None:
    raise SystemExit("no EYES entry for %s: measure it with --probe first" % CID)


# ----------------------------------------------------------------------------- build
ob = body_mesh()
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
arm.data.pose_position = "REST"
bpy.context.view_layer.update()
img, tex = albedo(ob)
surf = Surface(ob.data)                                  # the head as it came, for colours, UVs and the skin's shape
xs, zs, col, pos, hit, uvm = front_map(surf, tex)
H, W = col.shape[:2]
X, Z = np.meshgrid(xs, zs)
als = [Almond(0), Almond(1)]
col0 = col.copy()
EX = np.min([al.excess(X, Z) for al in als], axis=0)     # each front pixel's distance outside the nearer outline

# ---- the colours to keep: skin round the eyes, the painted iris and lashes
s_, v_ = hsv(col0)
ring = hit & (EX > 0.004) & (EX < 0.010)
skin = np.median(col0[ring], axis=0)
diff = np.abs(col0 - skin).sum(-1)
skin_like = diff < 0.22
mean_h = (SPEC["up"] + SPEC["lo"]) / 2
deep = hit & (EX < -0.3 * mean_h)                        # well inside the eye
white = (v_ > 0.72) & (s_ < 0.28)
ir = deep & ~white & (v_ > 0.08) & ~skin_like
iris_col = np.median(col0[ir], axis=0) if ir.sum() > 30 else np.array([0.35, 0.22, 0.12])
if iris_col.max() < 0.32:                                # a near-black painted iris: lift it so the pupil shows
    iris_col = iris_col * (0.32 / max(iris_col.max(), 1e-3))
lash_px = hit & (EX > -0.001) & (EX < 0.003) & (v_ < 0.30)
lash_px &= np.stack([Z > al.c[1] for al in als]).any(0)
lash_col = np.median(col0[lash_px], axis=0) * 0.8 if lash_px.sum() > 30 else np.array([0.05, 0.03, 0.025])
log("skin", skin.round(3), "iris", iris_col.round(3), "lash", lash_col.round(3))

# ---- paint the old eyes out: the eye and a margin round it, and paint that is not skin close by (lashes, a lid
# line, a flick at the corner) unless it runs on far (a brow, hair, a spectacle frame)
# (dark paint and coloured paint are judged apart: a lid line that touches a coloured spectacle frame in the
# front view is still a lid line)
dark_ = hit & (col0.max(-1) < 0.62 * skin.max())
nonskin = hit & ((diff > 0.28) | dark_)
near_px = np.zeros_like(hit)
REACH = SPEC["reach"]                                   # paint touching the eye that ends within this is the eye's
for kind_ in (dark_, nonskin & ~dark_):
    lab, nlab = components(kind_ & (EX < 0.030))       # (looked at well past that, so a brow or a lock of hair shows
    reach = np.zeros(nlab + 1)                          # it runs on)
    np.maximum.at(reach, lab[lab > 0], EX[lab > 0])
    touch = np.zeros(nlab + 1, dtype=bool)
    touch[np.unique(lab[(lab > 0) & (EX < 0.004)])] = True
    loose_ = ~touch & (reach <= REACH) & bool(SPEC["loose"]) & (kind_ is dark_)
    loose_[0] = False
    near_lab = np.nonzero((touch | loose_) & (reach <= REACH))[0]
    near_px |= np.isin(lab, near_lab)
    if loose_.any():
        log("  loose dark marks near the eyes painted out: %d, %d px" % (int(loose_.sum()), int(np.isin(lab, np.nonzero(loose_)[0]).sum())))
    for k_ in np.nonzero(touch)[0]:
        n_ = int((lab == k_).sum())
        if n_ > 200:
            log("  %s paint at the eyes: %d px, reaching %.1f mm out%s" % ("dark" if kind_ is dark_ else "coloured", n_, reach[k_] * 1000, "" if reach[k_] <= REACH else " (left: it runs on)"))
# a painted mark's soft edge (a liner's blurred fringe) is neither dark nor far enough from skin to count as
# paint, and was left as a jagged brown line (Rowan): take the off-skin pixels right round a mark going too
for _ in range(2):
    near_px |= grow(near_px, 4) & hit & (diff > 0.12) & (EX < REACH)
M = hit & ((EX < SPEC["rim"] + 0.0006) | near_px)
solve = M | nonskin                                     # no paint (a lash, a brow, a frame) is a colour to grow skin from
fill = col0.copy()
known = ~solve
edge = known & grow(solve, 1)
fill[solve] = col0[edge].mean(axis=0) if edge.any() else skin
for _ in range(900):
    avg = (np.roll(fill, 1, 0) + np.roll(fill, -1, 0) + np.roll(fill, 1, 1) + np.roll(fill, -1, 1)) / 4
    fill[solve] = avg[solve]
col[M] = fill[M]
th_, tw_ = tex.shape[:2]
jj_, ii_ = np.nonzero(M)
ty = (uvm[jj_, ii_, 1] % 1.0 * th_).astype(int) % th_
tx = (uvm[jj_, ii_, 0] % 1.0 * tw_).astype(int) % tw_
for dy in (-1, 0, 1):
    for dx in (-1, 0, 1):
        tex[np.clip(ty + dy, 0, th_ - 1), np.clip(tx + dx, 0, tw_ - 1)] = fill[jj_, ii_]
# The front map sees the face where it turns away at a slant, so some texels between the splats kept their
# paint: close the painted patch in texture space and grow skin over what it missed round it.
if len(ty):
    T = np.zeros((th_, tw_), dtype=bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            T[np.clip(ty + dy, 0, th_ - 1), np.clip(tx + dx, 0, tw_ - 1)] = True
    y0_, y1_ = max(0, ty.min() - 24), min(th_, ty.max() + 25)
    x0_, x1_ = max(0, tx.min() - 24), min(tw_, tx.max() + 25)
    t_ = T[y0_:y1_, x0_:x1_]
    sub = tex[y0_:y1_, x0_:x1_].copy()
    closed_ = ~grow(~grow(t_, 6), 6)
    ts_, tv_ = hsv(sub)
    skin_t = np.median(sub[t_], axis=0)
    dark_t = tv_ < 0.62 * skin_t.max()
    near_dark = grow(t_, 8) & dark_t
    for _ in range(4):
        near_dark = grow(near_dark, 1) & dark_t | near_dark
    off = grow(t_, 8) & (np.abs(sub - skin_t).max(axis=-1) > 0.10) & ~dark_t
    for _ in range(4):
        off = grow(off, 1) & (np.abs(sub - skin_t).max(axis=-1) > 0.10) & ~dark_t | off
    gap = (closed_ | near_dark | off) & ~t_
    if gap.any():
        sub[gap] = skin_t
        for _ in range(200):
            avg = (np.roll(sub, 1, 0) + np.roll(sub, -1, 0) + np.roll(sub, 1, 1) + np.roll(sub, -1, 1)) / 4
            sub[gap] = avg[gap]
        tex[y0_:y1_, x0_:x1_] = sub
    log("texture gaps closed:", int(gap.sum()), "texels")
px_ = np.ones((th_, tw_, 4), dtype=np.float32)
px_[..., :3] = tex
img.pixels.foreach_set(px_.ravel())
alb = os.path.join(OUT, CID + "_albedo.jpg")                 # kept a JPEG, as it came: a PNG would be five times the size
img.filepath_raw = alb
img.file_format = "JPEG"
img.save(quality=92)
if img.packed_file:
    img.unpack(method="REMOVE")                          # drop the old packed file, or the exporter writes that one
img.filepath = alb
img.reload()
img.pack()
os.remove(alb)
save_png(os.path.join(OUT, "_front_map_clean.png"), draw_map(col, als, grid=False))
log("old eyes painted out:", int(M.sum()), "front pixels")

# ---- each eye: its sphere, and its lids' outline on it. Both eyeballs are one size: the face's curve round both.
FITS = []
for al in als:
    sel = hit & (al.excess(X, Z) < 0.006)
    P = pos[sel].astype(float)
    cen = P.mean(axis=0)
    nrm = np.linalg.svd(P - cen)[2][2]
    if nrm[1] > 0:
        nrm = -nrm
    FITS.append((nrm, fit_sphere(P)[1]))
R_fit = float(np.mean([f_[1] for f_ in FITS]))
Rf = SPEC["R"] + RECESS if SPEC["R"] else float(np.clip(R_fit, 1.3 * SPEC["a"], 2.6 * SPEC["a"]))
def onball(x, z, rad, C):
    """The point of the sphere (C, rad) seen at (x, z) from the front."""
    dx, dz = x - C[0], z - C[2]
    h = rad * rad - dx * dx - dz * dz
    if h < (0.3 * rad) ** 2:                             # nearly round the side of the ball: hold it short of the edge
        k = math.sqrt((1 - 0.09) * rad * rad / max(dx * dx + dz * dz, 1e-12))
        dx, dz, h = dx * k, dz * k, (0.3 * rad) ** 2
    return np.array([C[0] + dx, C[1] - math.sqrt(h), C[2] + dz])


EYE = []
for al, (nrm, _) in zip(als, FITS):
    side = "Right" if al.k == 0 else "Left"
    loc, fi = surf.front(*al.c)
    P0 = np.array(loc)
    pole = 2 * np.array([0.0, -1.0, 0.0]) + nrm               # mostly straight ahead: eyes on a curved face don't splay
    pole /= np.linalg.norm(pole)
    C = P0 - pole * Rf
    R = Rf - RECESS
    r = np.cross([0, 0, 1.0], pole)
    r /= np.linalg.norm(r)
    u = np.cross(pole, r)

    def ab(Pt, C=C, pole=pole, r=r, u=u):
        d = np.asarray(Pt) - C
        fw = d @ pole
        return (d @ r) / fw, (d @ u) / fw

    def dirab(a, b, pole=pole, r=r, u=u):
        d = pole + a * r + b * u
        return d / np.linalg.norm(d)
    def ab_s(s_, upper, al=al, ab=ab, C=C):
        """The outline at s on the eyeball, as the front view sees it: the opening is the outline exactly, however
        the face behind it slopes (carried through the face, a deep socket's walls bent it out of shape)."""
        x_, zu_, zl_ = al.at_s(s_)
        return ab(onball(float(x_), float(zu_ if upper else zl_), Rf, C))
    # the lids' columns: well past each corner, and (below) well above and below the opening. Hidden under the skin,
    # they keep a look at a slant, under the rim and into the head, from finding the eyeball where a socket turns away.
    NCOL = 56
    s_cols = np.linspace(-1.4, 1.4, NCOL)
    Au, Bu, Al, Bl = (np.zeros(NCOL) for _ in range(4))
    for j, sj in enumerate(s_cols):
        if abs(sj) <= 1:
            Au[j], Bu[j] = ab_s(sj, True)
            Al[j], Bl[j] = ab_s(sj, False)
        else:                                            # past the corner: on along the eye, level with the corner
            e1 = math.copysign(1.0, sj)
            a1, b1 = ab_s(e1, True)
            a0 = (ab_s(e1 * 0.95, True)[0] + ab_s(e1 * 0.95, False)[0]) / 2
            Au[j] = Al[j] = a1 + (a1 - a0) / 0.05 * (abs(sj) - 1)
            Bu[j] = Bl[j] = b1
    sc = np.clip(s_cols, -1, 1)
    hgt = np.maximum(Bu - Bl, 0.0)
    lash = SPEC["lash"] * (0.45 + 0.55 * (sc + 1) / 2) * smoothstep(np.minimum(1 + sc, 1 - sc) / 0.3)
    lash = np.where(np.abs(s_cols) > 1, 0.0, lash)
    E = dict(al=al, side=side, C=C, R=R, Rf=Rf, pole=pole, r=r, u=u, ab=ab, dirab=dirab, s=s_cols, sc=sc,
             Au=Au, Bu=Bu, Al=Al, Bl=Bl, h=hgt, lash=lash)
    # rows of the lids, in b (up the eye) per column; the travel decides how far out the lids must ride
    E["b_lead"] = Bu - lash / R
    E["b_meet_u"] = Bl + 0.25 * hgt
    # the lower lid rises behind the upper one's edge, and well past it, so no gap shows at the corners (where the
    # opening narrows to nothing) from any side
    E["b_meet_l"] = np.maximum(Bl + 0.30 * hgt, E["b_meet_u"] + 1.2 * MM / R)
    E["b_low"] = Bl + 0.2 * MM / R
    E["b_squint"] = Bl + 0.42 * hgt * (0.55 + 0.45 * np.sin(np.pi * (sc + 1) / 2))

    def travel(a_, b0, b1):
        return max(math.acos(float(np.clip(dirab(a_[j], b0[j]) @ dirab(a_[j], b1[j]), -1, 1))) for j in range(NCOL))
    du = travel(Au, E["b_lead"], E["b_meet_u"])
    dl_ = max(travel(Al, E["b_low"], E["b_squint"]), travel(Al, E["b_low"], E["b_meet_l"]))
    eu = max(1.0 * MM, (R + 0.35 * MM) / math.cos(du / 2) - R)
    el = max(0.6 * MM, (R + 0.3 * MM) / math.cos(dl_ / 2) - R)
    eu = max(eu, el + 0.3 * MM)
    E.update(eu=eu, el=el, g=eu + 0.5 * MM)
    log(side, "eye: face curve %.1f mm, eyeball %.1f mm, centre %s, lids %.2f / %.2f mm out (travel %.0f / %.0f deg), rim %.2f mm"
        % (R_fit * 1000, R * 1000, np.round(C, 4), eu * 1000, el * 1000, math.degrees(du), math.degrees(dl_), E["g"] * 1000))
    EYE.append(E)


# ---- one seamless patch of skin for everything new round the eyes (the rims and the lids), seen from the front.
# The head's own texture is cut into many pieces, and a rim or lid triangle whose corners fall on different pieces
# smears everything between them across the skin (dark zig-zags at the corners). The patch is sampled from the
# painted texture through the surface, so where it meets the head the colours are the same.
def bilinear(t, u, v):
    h_, w_ = t.shape[:2]
    x_, y_ = u % 1.0 * w_ - 0.5, v % 1.0 * h_ - 0.5
    x0_, y0_ = int(math.floor(x_)), int(math.floor(y_))
    fx, fy = x_ - x0_, y_ - y0_
    xa, xb, ya, yb = x0_ % w_, (x0_ + 1) % w_, y0_ % h_, (y0_ + 1) % h_
    return (t[ya, xa] * (1 - fx) + t[ya, xb] * fx) * (1 - fy) + (t[yb, xa] * (1 - fx) + t[yb, xb] * fx) * fy


PAD = max(SPEC["rim"], LID_PAST) + 0.4 * SPEC["a"] + 1.0 * MM   # past the rim, and past the lids under the skin
bx, bz = [], []
for E in EYE:
    P2_, _, _ = E["al"].around(90)
    d2_ = (P2_ - E["al"].c) / np.linalg.norm(P2_ - E["al"].c, axis=1)[:, None]
    Q_ = P2_ + d2_ * PAD
    bx += [Q_[:, 0].min(), Q_[:, 0].max()]
    bz += [Q_[:, 1].min(), Q_[:, 1].max()]
PX0, PZ0 = min(bx), min(bz)
PW, PH = int(math.ceil((max(bx) - PX0) / STEP)), int(math.ceil((max(bz) - PZ0) / STEP))
patch = np.zeros((PH, PW, 3), dtype=np.float32)
got = np.zeros((PH, PW), dtype=bool)
for j in range(PH):
    z = PZ0 + (j + 0.5) * STEP
    for i in range(PW):
        x = PX0 + (i + 0.5) * STEP
        fi_, fj_ = int(round((x - REGION["x"][0]) / STEP)), int(round((z - REGION["z"][0]) / STEP))
        if 0 <= fj_ < H and 0 <= fi_ < W and M[fj_, fi_]:    # painted: its colour as painted (where the face turns
            patch[j, i] = col[fj_, fi_]                      # at a slant, the texture keeps some old paint between)
            got[j, i] = True
            continue
        E = min(EYE, key=lambda E_: abs(x - E_["al"].c[0]))
        try:
            S_, f_ = surf.near(x, z, E["C"], E["Rf"])
        except RuntimeError:
            continue
        uv_ = surf.uv(Vector(S_), f_)
        patch[j, i] = bilinear(tex, uv_.x, uv_.y)
        got[j, i] = True
if not got.all():                                        # nothing there (past the face's edge): the nearest colour
    for _ in range(40):
        g_ = grow(got, 1) & ~got
        if not g_.any():
            break
        acc, cnt = np.zeros_like(patch), np.zeros(got.shape)
        for sh_ in ((1, 0), (-1, 0), (1, 1), (-1, 1)):
            acc += np.roll(patch * got[..., None], sh_[0], sh_[1])
            cnt += np.roll(got.astype(float), sh_[0], sh_[1])
        patch[g_] = acc[g_] / np.maximum(cnt[g_], 1)[:, None]
        got |= g_
skin_png = os.path.join(OUT, CID + "_eyes_skin.png")
save_png(skin_png, patch)
log("skin patch %d x %d texels (%.0f x %.0f mm)" % (PW, PH, PW * STEP * 1000, PH * STEP * 1000))


def patch_uv(x, z):
    return ((x - PX0) / (PW * STEP), (z - PZ0) / (PH * STEP))


skin_img = bpy.data.images.load(skin_png)
skin_img.pack()
mat_skin = ob.data.materials[0].copy()                   # the head's own material, with the patch for its colour
mat_skin.name = CID.split("_")[0].capitalize() + "_eye_skin"
next(n for n in mat_skin.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is not None).image = skin_img


# ---- the head: cut along each outline grown by the rim's width, and build the rim in the gap
me = ob.data
tris_before = len(me.polygons)
bm = bmesh.new()
bm.from_mesh(me)
uvl = bm.loops.layers.uv.active
dfl = bm.verts.layers.deform.active
Wr = SPEC["rim"]
SKIN_SLOT = len(me.materials)
me.materials.append(mat_skin)


SKIN = {}


def on_skin(co, E):
    """Is the point on the face's skin, rather than a spectacle frame or a lock of hair in front of it?"""
    k = (E["side"], round(co.x, 5), round(co.z, 5))
    if k not in SKIN:
        try:
            SKIN[k] = Vector(surf.near(co.x, co.z, E["C"], E["Rf"])[0])
        except RuntimeError:
            SKIN[k] = None
    return SKIN[k] is not None and (co - SKIN[k]).length < 0.004


def zone(co, extra, skin=True):
    """Is the point inside an eye's outline grown by the rim's width and extra? (On the face's front: heavy lids
    can stand well out from the eyeball's sphere.)"""
    for E in EYE:
        d = co - Vector(E["C"])
        if d.length < E["Rf"] + 0.03 and d.dot(Vector(E["pole"])) > 0 and E["al"].excess(co.x, co.z) < Wr + extra \
                and (not skin or on_skin(co, E)):
            return True
    return False


def face_groups(faces):
    """The faces in groups joined by their edges."""
    left, out = set(faces), []
    while left:
        f0 = left.pop()
        comp, todo = [f0], [f0]
        while todo:
            f = todo.pop()
            for e in f.edges:
                for g_ in e.link_faces:
                    if g_ in left:
                        left.remove(g_)
                        comp.append(g_)
                        todo.append(g_)
        out.append(comp)
    return out


def check(tag):
    nm = sum(1 for e in bm.edges if len(e.link_faces) > 2 and zone(e.verts[0].co, 0.008))
    wire = sum(1 for e in bm.edges if not e.link_faces and zone(e.verts[0].co, 0.008))
    odd = sum(1 for v in bm.verts if v.is_boundary and zone(v.co, 0.008) and sum(1 for e in v.link_edges if e.is_boundary) != 2)
    log("  check %s: edges with 3+ faces %d, loose edges %d, odd boundary points %d" % (tag, nm, wire, odd))


def refine(cut):
    """Split each edge in cut at its middle, every triangle on them in two (one edge cut) or in four (all three).
    Blender's own subdivide leaves ngons with points in a line, and triangulating those makes triangles of no area
    that fold the mesh: this makes none."""
    grow_ = True
    while grow_:                                         # a triangle with two edges to cut gets its third as well
        grow_ = False
        for f in {f for e in cut for f in e.link_faces}:
            if sum(1 for e in f.edges if e in cut) == 2:
                cut.update(f.edges)
                grow_ = True
    mid = {}
    for e in cut:
        a_, b_ = e.verts
        v = bm.verts.new((a_.co + b_.co) / 2)
        wa, wb = a_[dfl], b_[dfl]
        for gi in set(wa.keys()) | set(wb.keys()):
            v[dfl][gi] = (wa.get(gi, 0.0) + wb.get(gi, 0.0)) / 2
        mid[e] = v
    faces = list({f for e in cut for f in e.link_faces})
    made = []
    for f in faces:
        vs = [lp.vert for lp in f.loops]
        uv = [lp[uvl].uv.copy() for lp in f.loops]
        m = [mid.get(lp.edge) for lp in f.loops]         # loop i's edge runs from corner i to corner i + 1
        mu = [(uv[i] + uv[(i + 1) % 3]) / 2 for i in range(3)]
        if all(m):
            tris = [((vs[0], uv[0]), (m[0], mu[0]), (m[2], mu[2])), ((m[0], mu[0]), (vs[1], uv[1]), (m[1], mu[1])),
                    ((m[2], mu[2]), (m[1], mu[1]), (vs[2], uv[2])), ((m[0], mu[0]), (m[1], mu[1]), (m[2], mu[2]))]
        else:
            i = next(i for i in range(3) if m[i])
            a_, b_, c_ = i, (i + 1) % 3, (i + 2) % 3
            tris = [((vs[a_], uv[a_]), (m[i], mu[i]), (vs[c_], uv[c_])), ((m[i], mu[i]), (vs[b_], uv[b_]), (vs[c_], uv[c_]))]
        made.append((tris, f.material_index, f.smooth))
    for tris, mi, sm in made:                            # the new faces first, so no corner is ever left loose
        for t in tris:
            nf = bm.faces.new([p[0] for p in t])
            nf.material_index, nf.smooth = mi, sm
            for lp, p in zip(nf.loops, t):
                lp[uvl].uv = p[1]
    bmesh.ops.delete(bm, geom=faces, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=list(cut), context="EDGES")


check("start")
bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3 and any(zone(v.co, 0.03) for v in f.verts)])
def outside(co):
    """How far a point lies outside the nearer eye's outline (negative: inside); None away from both eyes."""
    ex = [float(E["al"].excess(co.x, co.z)) for E in EYE if (Vector(E["C"]) - co).length < E["Rf"] + 0.03]
    return min(ex) if ex else None


def on_cut(e):
    """Does the edge cross the band where the cut will run (from 3 mm inside it to 2 mm outside)? Only there do
    the triangles need to be fine: the ones inside go, and the ones further out are left as they were."""
    ex = [x_ for x_ in (outside(p) for p in (e.verts[0].co, e.verts[1].co, (e.verts[0].co + e.verts[1].co) / 2)) if x_ is not None]
    return bool(ex) and min(ex) < Wr + 0.002 and max(ex) > Wr - 0.003


for it in range(8):                                      # fine triangles round the eyes, so the cut follows the outline closely
    edges = {e for e in bm.edges if e.calc_length() > 0.0015 and on_cut(e)}
    if not edges:
        break
    refine(edges)
check("subdivided")
# The cut: from the middle of each painted eye outward, through faces with a corner inside the outline grown by the
# rim, so it opens exactly one hole per eye (a fold of skin by a corner, or a spectacle frame, can't leave a scrap
# inside the hole or a pinhole beside it)
seed = [f for f in bm.faces if all(zone(v.co, -Wr - 0.002) for v in f.verts)]
kill, todo = set(seed), list(seed)
while todo:
    f = todo.pop()
    for e in f.edges:
        for g_ in e.link_faces:
            if g_ not in kill and any(zone(v.co, 0.0003, skin=False) for v in g_.verts):
                kill.add(g_)
                todo.append(g_)
kill = list(kill)
bmesh.ops.delete(bm, geom=kill, context="FACES")
# and any loose piece left lying wholly inside an opening
scraps = [c_ for c_ in face_groups(list(bm.faces)) if len(c_) < 2000 and
          all(zone(v.co, 0.001, skin=False) for f in c_ for v in f.verts)]
if scraps:
    log("head: %d loose scraps inside the openings removed (%d faces)" % (len(scraps), sum(len(c_) for c_ in scraps)))
    bmesh.ops.delete(bm, geom=[f for c_ in scraps for f in c_], context="FACES")
check("cut")
# tidy the cut's edge: a corner where two stretches of edge touch (a pinch) or a triangle hanging on by its
# corners would break the loop round the eye
for it in range(12):
    bad = set()
    for v in bm.verts:
        if v.is_boundary and zone(v.co, 0.004):
            if sum(1 for e in v.link_edges if e.is_boundary) > 2:
                bad.update(v.link_faces)
    for f in bm.faces:
        if zone(f.calc_center_median(), 0.0015) and sum(1 for e in f.edges if e.is_boundary) >= 2:
            bad.add(f)
    if not bad:
        break
    bmesh.ops.delete(bm, geom=list(bad), context="FACES")
    kill += list(bad)
check("tidied")
log("head: %d faces cut away" % len(kill))

ROWS = [(-0.03, "bottom"), (0.0, "round"), (0.08, "top"), (0.25, "blend"), (0.5, "blend"), (0.75, "blend"), (1.0, "face")]
for E in EYE:
    al, C, R, Rf, g, eu = E["al"], E["C"], E["R"], E["Rf"], E["g"], E["eu"]
    Cv = Vector(C)
    # the cut's edge round this eye
    # (the boundary edges near the eye, and then the whole of each boundary they belong to: the cut's edge can
    # stray a few millimetres further out where tidying took a big triangle)
    seed = {v for e in bm.edges if e.is_boundary for v in e.verts
            if (v.co - Cv).length < Rf + 0.03 and al.excess(v.co.x, v.co.z) < Wr + 0.006}
    bed, todo, reached = set(), list(seed), set(seed)
    while todo:
        v = todo.pop()
        for e in v.link_edges:
            if e.is_boundary:
                bed.add(e)
                w = e.other_vert(v)
                if w not in reached:
                    reached.add(w)
                    todo.append(w)
    adj = {}
    for e in bed:
        a_, b_ = e.verts
        adj.setdefault(a_, []).append(b_)
        adj.setdefault(b_, []).append(a_)
    loops, seen = [], set()
    for v0 in adj:
        if v0 in seen:
            continue
        lp, prev, cur = [v0], None, v0
        seen.add(v0)
        while True:
            nxt = [w for w in adj[cur] if w is not prev and (w is v0 or w not in seen)]
            if not nxt or nxt[0] is v0:
                break
            prev, cur = cur, nxt[0]
            lp.append(cur)
            seen.add(cur)
        loops.append(lp)
    # the loop round this eye: the one with most points on the cut's line (a spectacle frame's edge can be near)
    loop = max(loops, key=lambda lp: sum(1 for v in lp if abs(al.excess(v.co.x, v.co.z) - Wr) < 0.0015))
    if bm.edges.get((loop[-1], loop[0])) is None:
        deg = [len(adj[v]) for v in adj]
        for lp in sorted(loops, key=len, reverse=True)[:6]:
            P_ = np.array([v.co[:] for v in lp]) * 1000
            log("  piece", len(lp), "x %.1f..%.1f z %.1f..%.1f" % (P_[:, 0].min(), P_[:, 0].max(), P_[:, 2].min(), P_[:, 2].max()),
                "ends", [tuple(np.round(np.array(v.co[:]) * 1000, 1)) for v in (lp[0], lp[-1])],
                "end degrees", len(adj[lp[0]]), len(adj[lp[-1]]))
        log("  degrees", {d_: deg.count(d_) for d_ in set(deg)})
        raise RuntimeError("%s eye: the cut's edge is not one closed loop" % E["side"])
    # The cut runs along the head's own triangles, so its edge is a saw: from 0.3 to 1.5 mm past the rim, its
    # teeth doubling back on themselves. Slide the points that stand furthest out in along their ray from the
    # eye's centre to SNAP past the rim, onto the skin there, so the edge runs smooth and the stitch to it can't
    # fold (dark notches under Rowan's lids). Sliding in only moves a point away from the head's faces round it.
    SNAP, n_snap = 0.4 * MM, 0

    def front_area(f, v=None, co=None):
        P = [((co if u is v else u.co).x, (co if u is v else u.co).z) for u in f.verts]
        return sum(P[k][0] * P[(k + 1) % len(P)][1] - P[(k + 1) % len(P)][0] * P[k][1] for k in range(len(P)))

    def slide(v, co):
        """Move v toward co, only as far as none of the head's faces round it turns over (seen from the front)."""
        before = [(f, front_area(f)) for f in v.link_faces]
        for t_ in (1.0, 0.5, 0.25):
            c_ = v.co.lerp(co, t_)
            if all(a_ * front_area(f, v, c_) > 0 and abs(front_area(f, v, c_)) > 0.05 * abs(a_) for f, a_ in before):
                v.co = c_
                return True
        return False

    def on_line(x_, z_, y_):
        try:
            return Vector(surf.near(x_, z_, C, Rf)[0])
        except RuntimeError:
            return Vector((x_, y_, z_))
    for v in loop:
        dx_, dz_ = v.co.x - al.c[0], v.co.z - al.c[1]
        rho = math.hypot(dx_, dz_)
        ex_ = float(al.excess(v.co.x, v.co.z))
        if ex_ > Wr + SNAP and rho > 1e-6:
            k_ = (rho - (ex_ - Wr - SNAP)) / rho
            n_snap += slide(v, on_line(al.c[0] + dx_ * k_, al.c[1] + dz_ * k_, v.co.y))
    # and where a tooth of the saw doubles back round the eye, ease each point to halfway round between its
    # neighbours (on the same line past the rim), again only as far as the head's faces allow
    ang = lambda u: math.atan2(u.co.z - al.c[1], u.co.x - al.c[0])
    sgn = 1.0 if sum(((ang(loop[(i + 1) % len(loop)]) - ang(loop[i]) + math.pi) % (2 * math.pi) - math.pi)
                     for i in range(len(loop))) > 0 else -1.0
    n_ease = 0
    for it in range(6):
        moved = 0
        for i, v in enumerate(loop):
            pa, na = ang(loop[i - 1]), ang(loop[(i + 1) % len(loop)])
            a0 = ang(v)
            back = sgn * (((a0 - pa + math.pi) % (2 * math.pi)) - math.pi) <= 0 or \
                sgn * (((na - a0 + math.pi) % (2 * math.pi)) - math.pi) <= 0
            if not back:
                continue
            mid_ = pa + (((na - pa + math.pi) % (2 * math.pi)) - math.pi) / 2
            r_ = float(al.r(mid_)) + Wr + SNAP
            if slide(v, on_line(al.c[0] + r_ * math.cos(mid_), al.c[1] + r_ * math.sin(mid_), v.co.y)):
                moved += 1
        n_ease += moved
        if not moved:
            break
    # a short stretch that still runs back round the eye: weld its two ends into one (the stitch over it would lie
    # face down and shade dark), where that turns none of the head's faces over
    n_weld = 0
    for it in range(80):
        welded = False
        for i in range(len(loop)):
            a_, b_ = loop[i], loop[(i + 1) % len(loop)]
            d_ = sgn * ((((ang(b_) - ang(a_)) + math.pi) % (2 * math.pi)) - math.pi)
            if d_ > 0 or (a_.co - b_.co).length > 0.6 * MM:
                continue
            for keep, gone in ((a_, b_), (b_, a_)):
                faces_ = [f for f in gone.link_faces if keep not in f.verts]
                if all(front_area(f) * front_area(f, gone, keep.co) > 0 for f in faces_):
                    bmesh.ops.weld_verts(bm, targetmap={gone: keep})
                    n_weld += 1
                    welded = True
                    break
            if welded:
                break
        loop = [v for v in loop if v.is_valid]
        if not welded:
            break
    tb = np.array([math.atan2(v.co.z - al.c[1], v.co.x - al.c[0]) for v in loop])
    if np.sum(np.diff(np.unwrap(tb))) < 0:
        loop, tb = loop[::-1], tb[::-1]
    st = int(np.argmin(tb))
    loop, tb = loop[st:] + loop[:st], np.concatenate([tb[st:], tb[:st]])
    tb = np.maximum.accumulate(np.unwrap(tb))
    exl = np.array([al.excess(v.co.x, v.co.z) for v in loop]) - Wr
    log(E["side"], "eye: cut edge of %d points, %d other loops, %.1f..%.1f mm past the rim (%d slid in, %d eased round, %d welded)" % (
        len(loop), len(loops) - 1, exl.min() * 1000, exl.max() * 1000, n_snap, n_ease, n_weld))
    # the rim: rows from just inside the outline out to the face, at even steps round it
    Mc = 160
    P2, th, upf = al.around(Mc)
    Mc = len(P2)
    dir2 = (P2 - al.c) / np.linalg.norm(P2 - al.c, axis=1)[:, None]
    grid, uvs = [], {}
    # Every row lies where the front view puts it (the band from the outline out by the rim's width), and only its
    # depth changes: on the lip it is on spheres just over the lids, and from there it eases forward (or back) to
    # the face.
    SW = [surf.near(*(P2[j] + dir2[j] * Wr), C, Rf)[0] for j in range(Mc)]   # where the rim meets the face
    YW = np.array([p_[1] for p_ in SW])
    # the face's depth round the eye, smoothed: a faceted face would make every row of the rim wave with it. Only
    # the rim's outer edge keeps the true depth, to meet the head.
    YWs = np.convolve(np.concatenate([YW[-4:], YW, YW[:4]]), np.ones(9) / 9, mode="valid")
    for j in range(Mc):
        Sw = SW[j]
        uv0 = patch_uv(*P2[j])                           # the rim's lip, inside the outline, is the colour at the outline
        colv = []
        for frac, kind in ROWS:
            q = P2[j] + dir2[j] * frac * Wr
            if kind == "face":
                p, uvv = Sw, patch_uv(Sw[0], Sw[2])
            else:
                if kind == "bottom":
                    p = onball(q[0], q[1], R + eu + 0.12 * MM, C)
                elif kind == "round":
                    p = onball(q[0], q[1], R + g - 0.45 * (g - eu), C)
                elif kind == "top":
                    p = onball(q[0], q[1], R + g, C)
                else:
                    y0_ = onball(q[0], q[1], R + g, C)[1]
                    y_t = YWs[j] + (YW[j] - YWs[j]) * frac ** 3
                    p = np.array([q[0], y0_ + (y_t - y0_) * float(smoothstep((frac - 0.08) / 0.92)), q[1]])
                uvv = uv0 if kind in ("bottom", "round") else patch_uv(q[0], q[1])
            v = bm.verts.new(Vector(p))
            uvs[v] = Vector(uvv)
            colv.append(v)
        grid.append(colv)
    # weights: each column as the nearest point of the cut's edge
    for j in range(Mc):
        src = loop[int(np.argmin(np.abs((tb - th[j] + np.pi) % (2 * np.pi) - np.pi)))]
        for v in grid[j]:
            for gi, w in src[dfl].items():
                v[dfl][gi] = w
    for v in loop:
        uvs[v] = Vector(patch_uv(v.co.x, v.co.z))
    new_faces = []
    for j in range(Mc):
        j2 = (j + 1) % Mc
        for i in range(len(ROWS) - 1):
            new_faces.append(bm.faces.new((grid[j][i], grid[j2][i], grid[j2][i + 1], grid[j][i + 1])))
    # do the rim's faces face out? judge by the ones lying on the face
    test = new_faces[len(ROWS) - 2::len(ROWS) - 1]
    for f in test:
        f.normal_update()
    out_ = sum(1 if f.normal.dot(f.calc_center_median() - Cv) > 0 else -1 for f in test)
    if out_ < 0:
        for f in new_faces:
            f.normal_flip()
    # stitch the rim's outer row to the cut's edge, walking both round the eye by angle together: each step goes on
    # along whichever loop's next point comes first, so no strip folds over itself. (Blender's bridge paired the
    # two loops by count, and where the cut's points crowd, under the eye, the pairs slid apart and the strip folded:
    # dark notches under Rowan's lids.)
    nb = len(loop)
    ta = (th - th[0]) % (2 * np.pi)
    ta = np.maximum.accumulate(ta)
    tb_ = (tb - th[0]) % (2 * np.pi)
    sb = int(np.argmin(tb_))
    order_b = [(sb + i) % nb for i in range(nb)]
    tbs = np.maximum.accumulate(np.unwrap(tb_[order_b]))
    A = [grid[j][-1] for j in range(Mc)] + [grid[0][-1]]
    ta = np.concatenate([ta, [2 * np.pi]])
    B = [loop[k] for k in order_b] + [loop[order_b[0]]]
    tbs = np.concatenate([tbs, [tbs[0] + 2 * np.pi]])
    # (seen from the front, a triangle laid this way runs clockwise; one that doesn't lies face down)

    def cw(tri):
        P = [(v_.co.x, v_.co.z) for v_ in tri]
        return sum(P[k][0] * P[(k + 1) % 3][1] - P[(k + 1) % 3][0] * P[k][1] for k in range(3)) < 0
    st_faces, ja, ib, n_fold = [], 0, 0, 0
    while ja < Mc or ib < nb:
        t1 = (A[ja], A[ja + 1], B[ib]) if ja < Mc else None
        t2 = (A[ja], B[ib + 1], B[ib]) if ib < nb else None
        tri = t1 if t2 is None or (t1 is not None and ta[ja + 1] <= tbs[ib + 1]) else t2
        other = t2 if tri is t1 else t1
        if not cw(tri) and other is not None and cw(other):  # where the edge still turns back: the other step
            tri = other
        n_fold += 0 if cw(tri) else 1
        if tri is t1:
            ja += 1
        else:
            ib += 1
        st_faces.append(bm.faces.new(tri))

    def start_of(face, edge):
        return next(l_.vert for l_ in face.loops if l_.edge is edge)

    def agreement(faces, others):
        # (edges wound like their neighbour across them, edges wound against it)
        ok = bad = 0
        for f in faces:
            for e in f.edges:
                for g_ in e.link_faces:
                    if g_ in others:
                        if start_of(f, e) is start_of(g_, e):
                            bad += 1
                        else:
                            ok += 1
        return ok, bad
    rim_set = set(new_faces)
    ok, bad = agreement(st_faces, rim_set)
    if bad > ok:                                         # wind the stitch like the rim
        for f in st_faces:
            f.normal_flip()
    st_set = set(st_faces)
    head_ok, head_bad = agreement(st_faces, {g_ for f in st_faces for e in f.edges for g_ in e.link_faces
                                             if g_ not in st_set and g_ not in rim_set})
    if head_bad > head_ok:                               # the head's winding is the one that faces out
        for f in st_faces + new_faces:
            f.normal_flip()
        head_ok, head_bad = head_bad, head_ok
    log(E["side"], "eye: stitch of %d triangles (%d still lying face down from the front), wound like the head on %d of %d edges" % (
        len(st_faces), n_fold, head_ok, head_ok + head_bad))
    br = {"faces": st_faces}
    n_st = 0
    for f in br["faces"]:
        f.normal_update()
        new_faces.append(f)
        n_st += 1
    for f in new_faces:                                  # the rim and its stitch wear the skin patch
        f.smooth = True
        f.material_index = SKIN_SLOT
        for l in f.loops:
            l[uvl].uv = uvs[l.vert]
    log(E["side"], "eye: rim of %d faces, %d stitched to the head" % (len(new_faces) - n_st, n_st))
bm.normal_update()
bm.to_mesh(me)
bm.free()
me.validate()
me.update()
log("head: triangles", tris_before, "->", len(me.polygons))
cut = Surface(me)                                        # the head with its new rims, for the eyeballs' clearance

# ---- the new parts: eyeballs and lids
V, F, UV, MAT, GRP = [], [], [], [], []
KEYS = {}
TW = TH = 512
EV = 0.875                                               # the eyeball's map fills v 0..EV; the lash colour sits above it


LIDS = []                                                # (vertex, eye centre, eyeball radius) of every lid point


def vert(p, grp):
    V.append(tuple(float(t) for t in p))
    GRP.append(grp)
    return len(V) - 1


def face(idx, uvs, mat, C, flip_test=True):
    if flip_test:
        a, b, c = (np.array(V[i]) for i in idx[:3])
        if np.dot(np.cross(b - a, c - a), (a + b + c) / 3 - C) < 0:
            idx, uvs = idx[::-1], uvs[::-1]
    F.append(list(idx))
    UV.append([tuple(t) for t in uvs])
    MAT.append(mat)


def key(name, vi, delta):
    KEYS.setdefault(name, {})[vi] = np.asarray(delta, dtype=float)


LASH_UV = (0.5, (EV + 1) / 2)
bones = []
phis = []
for E in EYE:
    C, R, pole, r, u, dirab, side = E["C"], E["R"], E["pole"], E["r"], E["u"], E["dirab"], E["side"]
    Rf = E["Rf"]
    eu, el = E["eu"], E["el"]
    NCOL = len(E["s"])

    def skin_uv(p):
        return patch_uv(p[0], p[2])
    # upper lid: the lash band, then skin up to a top row that stays put
    NRU = 12
    b_top = E["Bu"] + LID_PAST / R
    rest = np.zeros((NRU + 2, NCOL))
    shut = np.zeros((NRU + 2, NCOL))
    rest[0], shut[0] = E["b_lead"], E["b_meet_u"]
    rest[1] = E["b_lead"] + (E["lash"] + 0.7 * MM) / R
    shut[1] = E["b_meet_u"] + (0.6 * E["lash"] + 0.3 * MM) / R
    for i in range(2, NRU + 2):
        t = (i - 1) / NRU
        rest[i] = rest[1] + (b_top - rest[1]) * t
        shut[i] = shut[1] + (b_top - shut[1]) * t
    idx = np.zeros(rest.shape, dtype=int)
    Pr = np.zeros(rest.shape + (3,))
    Ps = np.zeros(rest.shape + (3,))
    for i in range(rest.shape[0]):
        for j in range(NCOL):
            Pr[i, j] = C + dirab(E["Au"][j], rest[i, j]) * (R + eu)
            Ps[i, j] = C + dirab(E["Au"][j], shut[i, j]) * (R + eu)
            idx[i, j] = vert(Pr[i, j], "Head")
            LIDS.append((idx[i, j], C, R))
    for i in range(rest.shape[0] - 1):
        for j in range(NCOL - 1):
            q = [idx[i, j], idx[i, j + 1], idx[i + 1, j + 1], idx[i + 1, j]]
            if i == 0:
                face(q, [LASH_UV] * 4, 1, C)
            else:
                face(q, [skin_uv(Ps[i, j]), skin_uv(Ps[i, j + 1]), skin_uv(Ps[i + 1, j + 1]), skin_uv(Ps[i + 1, j])], 0, C)
    inner = (1 - E["sc"]) / 2                                   # 1 at the corner by the nose
    for i in range(rest.shape[0]):
        for j in range(NCOL):
            d = Ps[i, j] - Pr[i, j]
            key("blink_" + side[0], idx[i, j], d)
            key("lid_half", idx[i, j], 0.45 * d)
            key("lid_angry", idx[i, j], (0.10 + 0.50 * inner[j]) * d)
            key("lid_sad", idx[i, j], (0.10 + 0.50 * (1 - inner[j])) * d)
    # lower lid: skin from its edge down to a bottom row that stays put
    NRL = 8
    b_bot = E["Bl"] - LID_PAST / R
    lrest = np.zeros((NRL + 1, NCOL))
    lsq = np.zeros((NRL + 1, NCOL))
    lbl = np.zeros((NRL + 1, NCOL))
    for i in range(NRL + 1):
        t = i / NRL
        lrest[i] = E["b_low"] + (b_bot - E["b_low"]) * t
        lsq[i] = E["b_squint"] + (b_bot - E["b_squint"]) * t
        lbl[i] = E["b_meet_l"] + (b_bot - E["b_meet_l"]) * t
    lidx = np.zeros(lrest.shape, dtype=int)
    Lr, Lq, Lb = (np.zeros(lrest.shape + (3,)) for _ in range(3))
    for i in range(lrest.shape[0]):
        for j in range(NCOL):
            Lr[i, j] = C + dirab(E["Al"][j], lrest[i, j]) * (R + el)
            Lq[i, j] = C + dirab(E["Al"][j], lsq[i, j]) * (R + el)
            Lb[i, j] = C + dirab(E["Al"][j], lbl[i, j]) * (R + el)
            lidx[i, j] = vert(Lr[i, j], "Head")
            LIDS.append((lidx[i, j], C, R))
    for i in range(lrest.shape[0] - 1):
        for j in range(NCOL - 1):
            q = [lidx[i, j], lidx[i, j + 1], lidx[i + 1, j + 1], lidx[i + 1, j]]
            face(q, [skin_uv(Lq[i, j]), skin_uv(Lq[i, j + 1]), skin_uv(Lq[i + 1, j + 1]), skin_uv(Lq[i + 1, j])], 0, C)
    for i in range(lrest.shape[0]):
        for j in range(NCOL):
            key("squint", lidx[i, j], Lq[i, j] - Lr[i, j])
            key("blink_" + side[0], lidx[i, j], Lb[i, j] - Lr[i, j])
    # eyeball: a cap of the sphere, past the opening by as far as the eye turns and a little more
    op = np.abs(E["s"]) <= 1                             # the opening's own columns, not the lids' reach past it
    far = max(math.acos(float(np.clip(dirab(a_, b_) @ pole, -1, 1)))
              for a_, b_ in zip(np.concatenate([E["Au"][op], E["Al"][op]]), np.concatenate([E["Bu"][op], E["Bl"][op]])))
    phi_max = far + math.radians(max(GAZE) + 6)
    phis.append(phi_max)
    NK, NS = 30, 56
    rots = [(0, 0), (GAZE[0] / 2, 0), (-GAZE[0] / 2, 0), (GAZE[0], 0), (-GAZE[0], 0), (0, GAZE[1]), (0, -GAZE[1]),
            (GAZE[0], GAZE[1]), (-GAZE[0], GAZE[1]), (GAZE[0], -GAZE[1]), (-GAZE[0], -GAZE[1])]
    pulled = 0

    def ball(phi, psi):
        global pulled
        d = math.cos(phi) * pole + math.sin(phi) * (math.cos(psi) * r + math.sin(psi) * u)
        rho = R
        for ya, pa in rots:                               # stay under the skin wherever the eye may turn
            ya, pa = math.radians(ya), math.radians(pa)
            d2 = d * math.cos(ya) + np.cross(u, d) * math.sin(ya)
            d2 = d2 * math.cos(pa) + np.cross(r, d2) * math.sin(pa)
            loc, nrm_, fi_, dd = cut.bvh.ray_cast(Vector(C), Vector(d2 / np.linalg.norm(d2)))
            if loc is not None and dd - 0.8 * MM < rho:
                rho = dd - 0.8 * MM
        if rho < R:
            pulled += 1
        return C + d * max(rho, 0.5 * R)
    pole_i = vert(C + pole * R, side + "Eye")
    ringi = []
    for k in range(1, NK + 1):
        phi = phi_max * k / NK
        ringi.append([vert(ball(phi, 2 * math.pi * m / NS), side + "Eye") for m in range(NS)])
    for m in range(NS):
        m2 = (m + 1) % NS
        face([pole_i, ringi[0][m], ringi[0][m2]], [((m + 0.5) / NS, 0.0), (m / NS, EV / NK), ((m + 1) / NS, EV / NK)], 1, C)
        for k in range(NK - 1):
            face([ringi[k][m], ringi[k + 1][m], ringi[k + 1][m2], ringi[k][m2]],
                 [(m / NS, EV * (k + 1) / NK), (m / NS, EV * (k + 2) / NK), ((m + 1) / NS, EV * (k + 2) / NK), ((m + 1) / NS, EV * (k + 1) / NK)], 1, C)
    log(side, "eye: cap to %.0f deg, %d points kept under the skin" % (math.degrees(phi_max), pulled))
    bones.append((side + "Eye", C, pole))

# ---- the lids stay under the skin, open, shut and in every mood: only the opening may show them
def under(p, C, R):
    d = p - C
    L = float(np.linalg.norm(d))
    loc, n_, f_, dd = cut.bvh.ray_cast(Vector(C), Vector(d / L))
    if loc is not None and dd - 0.3 * MM < L:
        return C + d / L * max(dd - 0.3 * MM, R + 0.25 * MM)
    return p


moved = 0
for vi, C, R in LIDS:
    p0 = np.array(V[vi])
    p1 = under(p0, C, R)
    if np.linalg.norm(p1 - p0) > 1e-6:
        moved += 1
        V[vi] = tuple(p1)
    for name in KEYS:
        if vi in KEYS[name]:
            t = under(p0 + KEYS[name][vi], C, R)
            KEYS[name][vi] = t - p1
log("lid points kept under the skin: %d at rest" % moved)

# ---- the eyeball's look: white, an iris and a pupil, drawn by angle from the front of the ball
phi_max = max(phis)
iris_r = SPEC["iris"] or 0.5 * (SPEC["up"] + SPEC["lo"])
phi_i = iris_r / EYE[0]["R"]
phi_p = 0.45 * phi_i
SS = 2
vv = (np.arange(TH * SS) + 0.5) / (TH * SS)
uu = (np.arange(TW * SS) + 0.5) / (TW * SS)
U_, V_ = np.meshgrid(uu, vv)
PHI = V_ / EV * phi_max
PSI = U_ * 2 * np.pi
sclera = np.array([0.93, 0.91, 0.88])
t_i = np.clip((PHI - phi_p) / (phi_i - phi_p), 0, 1)
fib = 1 + 0.07 * np.sin(PSI * 37 + 2.5 * np.sin(PSI * 11)) + 0.05 * np.sin(PSI * 83 + 1.7)
irisc = iris_col[None, None, :] * ((1.18 - 0.38 * t_i) * fib)[..., None]
irisc *= (1 - 0.55 * smoothstep((t_i - 0.78) / 0.22))[..., None]          # the dark ring at its edge
irisc *= (1 - 0.35 * smoothstep(1 - t_i / 0.12))[..., None]                # and a soft dark edge round the pupil
aa = 0.004
w_pupil = smoothstep((phi_p + aa - PHI) / (2 * aa))[..., None]
w_iris = smoothstep((phi_i + aa - PHI) / (2 * aa))[..., None]
white_c = sclera[None, None, :] * (1 - 0.10 * np.clip((PHI - phi_i) / (phi_max - phi_i), 0, 1))[..., None]
eye_px = white_c * (1 - w_iris) + irisc * w_iris
eye_px = eye_px * (1 - w_pupil) + np.array([0.015, 0.012, 0.012]) * w_pupil
eye_px[V_ > EV] = lash_col
eye_tex = eye_px.reshape(TH, SS, TW, SS, 3).mean(axis=(1, 3))
save_png(os.path.join(OUT, CID + "_eyes_iris.png"), eye_tex)
log("iris %.1f mm, pupil %.1f mm" % (iris_r * 1000, phi_p * EYE[0]["R"] * 1000))

# ---- mesh object, materials, bones
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
bs.inputs["Roughness"].default_value = 0.3
em = bpy.data.meshes.new(arm.name + "Eyes")
em.from_pydata(V, [], F)
uvl2 = em.uv_layers.new(name="UVMap")
n = 0
for fi, fc in enumerate(F):
    for j in range(len(fc)):
        uvl2.data[n].uv = UV[fi][j]
        n += 1
em.materials.append(mat_skin)
em.materials.append(mat_eye)
em.polygons.foreach_set("material_index", MAT)
em.polygons.foreach_set("use_smooth", [True] * len(F))
em.update()
eo = bpy.data.objects.new(arm.name + "Eyes", em)
ob.users_collection[0].objects.link(eo)
eo.parent = arm
eo.modifiers.new("Armature", "ARMATURE").object = arm
for gname in sorted(set(GRP)):
    vg = eo.vertex_groups.new(name=gname)
    vg.add([i for i, gg in enumerate(GRP) if gg == gname], 1.0, "REPLACE")
eo.shape_key_add(name="Basis", from_mix=False)
for name in sorted(KEYS):
    sk = eo.shape_key_add(name=name, from_mix=False)
    sk.value = 0.0
    for vi, d in KEYS[name].items():
        sk.data[vi].co = Vector(V[vi]) + Vector(d)
bpy.context.view_layer.objects.active = arm
arm.data.pose_position = "POSE"
bpy.ops.object.mode_set(mode="EDIT")
for (name, C, f) in bones:
    b = arm.data.edit_bones.get(name) or arm.data.edit_bones.new(name)      # a Mixamo rig has eye bones already
    b.head, b.tail = Vector(C), Vector(C + f * 0.03)
    b.roll = 0.0
    b.parent = arm.data.edit_bones["Head"]
    b.use_connect = False
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
