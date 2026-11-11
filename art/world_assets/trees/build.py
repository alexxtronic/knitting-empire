"""The three map trees, after Alex's reference pictures:

  maple_autumn  a round maple in red, orange and yellow, thick trunk with a root flare, two rocks
  maple_green   the same maple in summer yellow-green, a more open crown with its branches showing
  spruce        a tall fir of drooping, layered fronds

Stylised, low-poly and game-ready. Each crown is a few leafy clumps: an opaque core (so you can't
see through the tree) wrapped in alpha-cut cards painted with maple leaves (or spruce fronds).
The leaf materials are named Leaves_<kind> / LeafCore_<kind>; the game swaps them for its
wind-sway shader (shaders/tree_leaves.gdshader) and keeps the painted texture.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/trees/build.py -- maple_autumn
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kelib as K  # noqa: E402

KIND = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "maple_autumn"
NAME = "tree_" + KIND
OUT = os.path.join(HERE, KIND)
TEX = os.path.join(OUT, "tex")
K.reset(NAME)
rng = np.random.default_rng({"maple_autumn": 11, "maple_green": 23, "spruce": 37}[KIND])

PALETTES = {
    "maple_autumn": ["#a51d0e", "#c22f12", "#d9480f", "#e8740c", "#efa312", "#f2c21a", "#8a1a0c", "#cf3a10"],
    "maple_green": ["#7fae2c", "#98c034", "#b3cf3c", "#64962a", "#a8c832", "#cbd648"],
    "spruce": ["#23492c", "#2d5934", "#1e4026", "#3a6a3c"],
}
CORE = {"maple_autumn": "#6e1a0c", "maple_green": "#5f8a2a", "spruce": "#173020"}
BARK = {"maple_autumn": "#4f3d30", "maple_green": "#55443a", "spruce": "#4a3729"}


# --- textures --------------------------------------------------------------------------------

def save_rgba(name, rgba):
    """rgba: (H, W, 4) floats, sRGB, row 0 at the top. Saved as a PNG and packed."""
    os.makedirs(TEX, exist_ok=True)
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.clip(rgba[::-1], 0, 1).astype(np.float32).ravel())
    img.filepath_raw = os.path.join(TEX, name + ".png")
    img.file_format = "PNG"
    img.alpha_mode = "STRAIGHT"
    img.save()
    img.pack()
    return img


def _wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi


LOBES = ((0.0, 1.0), (0.95, 0.86), (-0.95, 0.86), (1.95, 0.55), (-1.95, 0.55))


def maple_leaf(s):
    """A five-lobed maple leaf on an s x s grid: (mask, shade). The tip points up."""
    yy, xx = np.mgrid[0:s, 0:s]
    x = (xx + 0.5) / s * 2 - 1
    y = 1 - (yy + 0.5) / s * 2
    y = y + 0.12  # the leaf's heart sits a little below the middle
    th = np.arctan2(x, y)
    d = np.hypot(x, y)
    r = 0.24 + 0.0 * th
    for ang, amp in LOBES:
        r = r + 0.62 * amp * np.exp(-(_wrap(th - ang) / 0.3) ** 2)
    r = r + 0.05 * np.abs(np.sin(th * 11))  # serrated edge
    leaf = d < r
    stem = (np.abs(x) < 0.035) & (y < 0.0) & (y > -0.8)
    vein = np.zeros_like(d)
    for ang, _ in LOBES:
        along = x * math.sin(ang) + y * math.cos(ang)
        perp = np.abs(x * math.cos(ang) - y * math.sin(ang))
        vein = np.maximum(vein, (perp < 0.025) * (along > 0) * (along < r * 0.8))
    shade = 0.92 + 0.16 * y - 0.18 * np.clip((d / np.maximum(r, 1e-3) - 0.8) * 4, 0, 1) - 0.18 * vein
    return leaf | stem, np.where(stem & ~leaf, 0.6, shade)


def stamp(canvas, mask, shade, cx, cy, col):
    h, w, _ = canvas.shape
    s = mask.shape[0]
    x0, y0 = int(cx - s / 2), int(cy - s / 2)
    xa, ya, xb, yb = max(x0, 0), max(y0, 0), min(x0 + s, w), min(y0 + s, h)
    if xa >= xb or ya >= yb:
        return
    m = mask[ya - y0:yb - y0, xa - x0:xb - x0]
    sh = shade[ya - y0:yb - y0, xa - x0:xb - x0]
    reg = canvas[ya:yb, xa:xb]
    reg[m, :3] = np.array(col)[None, :] * sh[m][:, None]
    reg[m, 3] = 1.0


def rotated_leaf(s, angle):
    """maple_leaf turned by angle (radians), by sampling."""
    big = maple_leaf(s)
    yy, xx = np.mgrid[0:s, 0:s]
    c = (s - 1) / 2
    xs = np.cos(angle) * (xx - c) - np.sin(angle) * (yy - c) + c
    ys = np.sin(angle) * (xx - c) + np.cos(angle) * (yy - c) + c
    ok = (xs >= 0) & (xs < s) & (ys >= 0) & (ys < s)
    xi, yi = np.clip(xs.astype(int), 0, s - 1), np.clip(ys.astype(int), 0, s - 1)
    return big[0][yi, xi] & ok, big[1][yi, xi]


def leaf_cards(n=512):
    """A clump of overlapping maple leaves, roughly round, on a clear background."""
    cols = [np.array(K.hex_rgb(c)) for c in PALETTES[KIND]]
    a = np.zeros((n, n, 4))
    for _ in range(70):
        ang = rng.uniform(0, 2 * np.pi)
        rad = n * 0.36 * math.sqrt(rng.random())
        s = int(n * rng.uniform(0.2, 0.3))
        m, sh = rotated_leaf(s, rng.uniform(-np.pi, np.pi))
        col = cols[rng.integers(len(cols))] * rng.uniform(0.85, 1.1)
        stamp(a, m, sh, n / 2 + rad * math.cos(ang), n / 2 + rad * math.sin(ang), col)
    return save_rgba("leaves_" + KIND, a)


def leaf_core(n=256):
    """The opaque inside of a clump: leaves packed edge to edge over a shadowed base."""
    cols = [np.array(K.hex_rgb(c)) for c in PALETTES[KIND]]
    base = np.array(K.hex_rgb(CORE[KIND]))
    a = np.ones((n, n, 4))
    a[..., :3] = base * (0.8 + 0.3 * K.tile_noise(n, 1.4, 5)[..., None])
    for _ in range(140):
        s = int(n * rng.uniform(0.18, 0.28))
        m, sh = rotated_leaf(s, rng.uniform(-np.pi, np.pi))
        col = cols[rng.integers(len(cols))] * rng.uniform(0.7, 0.95)
        stamp(a, m, sh, rng.uniform(0, n), rng.uniform(0, n), col)
    a[..., 3] = 1.0
    return save_rgba("leafcore_" + KIND, a)


def segment_dist(xx, yy, p, q):
    d = q - p
    t = np.clip(((xx - p[0]) * d[0] + (yy - p[1]) * d[1]) / max(d @ d, 1e-6), 0, 1)
    return np.hypot(xx - p[0] - t * d[0], yy - p[1] - t * d[1])


def line(canvas, p, q, width, col):
    h, w, _ = canvas.shape
    x0, x1 = int(max(min(p[0], q[0]) - width - 1, 0)), int(min(max(p[0], q[0]) + width + 2, w))
    y0, y1 = int(max(min(p[1], q[1]) - width - 1, 0)), int(min(max(p[1], q[1]) + width + 2, h))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    m = segment_dist(xx, yy, np.array(p, float), np.array(q, float)) < width
    reg = canvas[y0:y1, x0:x1]
    reg[m, :3] = col
    reg[m, 3] = 1.0


def frond_card(w=256, h=512):
    """A spruce frond seen from above: a stem up the middle (tip at the top) with needles
    sweeping forward on both sides, shorter towards the tip."""
    cols = [np.array(K.hex_rgb(c)) for c in PALETTES[KIND]]
    a = np.zeros((h, w, 4))
    cx = w / 2
    for i in range(170):
        t = i / 170
        y = h * (0.98 - t * 0.95)
        reach = w * 0.47 * (1 - t ** 1.6) * (0.75 + 0.25 * math.sin(t * 40)) + 6
        for side in (-1, 1):
            k = rng.uniform(0.8, 1.05)
            tip = (cx + side * reach * k, y - reach * 0.55 * k)
            col = cols[rng.integers(len(cols))] * (0.8 + 0.35 * t) * rng.uniform(0.85, 1.1)
            line(a, (cx, y), tip, 2.2, col)
    line(a, (cx, h * 0.99), (cx, h * 0.03), 3.0, np.array(K.hex_rgb("#3b4527")))
    return save_rgba("frond_" + KIND, a)


def bark_image(n=256):
    g = K.grain_noise(n, 14.0, 1.2, 3)
    m = K.tile_noise(n, 1.3, 4)
    base = np.array(K.hex_rgb(BARK[KIND]))
    rgb = base * (0.62 + 0.55 * g[..., None]) * (0.9 + 0.2 * m[..., None])
    crack = np.clip((0.3 - g) * 4, 0, 1)[..., None]
    rgb = rgb * (1 - 0.5 * crack)
    return K.save_image("bark_" + KIND, rgb, TEX), K.save_image("bark_%s_normal" % KIND, K.normal_from_height(g + 0.3 * m, 3.0), TEX)


def leaf_material(name, image, clip=True, rough=0.75):
    m, b = K._principled(name, rough)
    nt = m.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = image
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if clip:  # glTF alpha MASK: the exporter reads a Round node between alpha and the BSDF
        r = nt.nodes.new("ShaderNodeMath")
        r.operation = "ROUND"
        nt.links.new(t.outputs["Alpha"], r.inputs[0])
        nt.links.new(r.outputs[0], b.inputs["Alpha"])
        m.surface_render_method = "DITHERED"
    m.use_backface_culling = False
    return m


# --- meshes ----------------------------------------------------------------------------------

def mesh_obj(name, verts, faces, uvs, mat, normals=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", [c for uv in uvs for c in uv])
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if normals is not None:
        me.normals_split_custom_set([normals[v] for f in faces for v in f])
    return K._obj(name, me, mat)


def trunk(height, r0, flare, roots, mat, lean=(0.0, 0.0), sides=12):
    """A tapering trunk with buttress roots spreading at the base. UVs tile once a metre up."""
    zs = [0.0, 0.06, 0.15, 0.3, 0.5, 0.8] + list(np.linspace(1.2, height, max(2, int(height / 0.7))))
    phase = rng.uniform(0, 2 * np.pi)
    verts, faces, uvs = [], [], []
    for z in zs:
        f = z / height
        rad = r0 * (1 - 0.45 * f) + flare * math.exp(-z / 0.22)
        for i in range(sides + 1):
            a = 2 * math.pi * i / sides
            lobe = 1 + 0.55 * math.exp(-z / 0.35) * max(0.0, math.cos(roots * a + phase)) ** 3
            verts.append((rad * lobe * math.cos(a) + lean[0] * f * f, rad * lobe * math.sin(a) + lean[1] * f * f, z))
    n = sides + 1
    for j in range(len(zs) - 1):
        for i in range(sides):
            a = j * n + i
            faces.append((a, a + 1, a + n + 1, a + n))
            uvs += [(i / sides * 2, zs[j]), ((i + 1) / sides * 2, zs[j]), ((i + 1) / sides * 2, zs[j + 1]), (i / sides * 2, zs[j + 1])]
    return mesh_obj("trunk", verts, faces, uvs, mat)


def tube(p0, p1, r0, r1, mat, sides=7):
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0).normalized()
    t1 = ax.cross(Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))).normalized()
    t2 = ax.cross(t1)
    verts, faces, uvs = [], [], []
    L = (p1 - p0).length
    for k, (p, r) in enumerate(((p0, r0), (p1, r1))):
        for i in range(sides + 1):
            a = 2 * math.pi * i / sides
            verts.append(tuple(p + (t1 * math.cos(a) + t2 * math.sin(a)) * r))
    n = sides + 1
    for i in range(sides):
        faces.append((i, i + n, i + n + 1, i + 1))
        uvs += [(i / sides, 0), (i / sides, L), ((i + 1) / sides, L), ((i + 1) / sides, 0)]
    return mesh_obj("branch", verts, faces, uvs, mat)


def blob(c, r, squash, mat, centre):
    """A low-poly leafy core with normals bent out from the crown's centre (soft, round shading)."""
    u, v = 10, 7
    verts, faces, uvs, nrm = [], [], [], []
    for j in range(v + 1):
        ph = math.pi * j / v
        for i in range(u + 1):
            th = 2 * math.pi * i / u
            d = Vector((math.sin(ph) * math.cos(th), math.sin(ph) * math.sin(th), math.cos(ph)))
            wob = 1 + 0.12 * (rng.random() - 0.5)
            p = Vector(c) + Vector((d.x * r, d.y * r, d.z * r * squash)) * wob
            verts.append(tuple(p))
            nrm.append(((p - centre).normalized() + d).normalized())
    for j in range(v):
        for i in range(u):
            a = j * (u + 1) + i
            faces.append((a, a + u + 1, a + u + 2, a + 1))
            uvs += [(i / u * 2, j / v), (i / u * 2, (j + 1) / v), ((i + 1) / u * 2, (j + 1) / v), ((i + 1) / u * 2, j / v)]
    return mesh_obj("core", verts, faces, uvs, mat, nrm)


def cards(c, r, count, size, mat, centre, out_bias=0.8):
    """Leaf cards shingled over a clump, facing out, normals bent round the crown."""
    verts, faces, uvs, nrm = [], [], [], []
    c = Vector(c)
    out = (c - centre)
    out = out.normalized() if out.length > 1e-3 else Vector((0, 0, 1))
    for _ in range(count):
        d = Vector(rng.normal(size=3)).normalized() + out * out_bias + Vector((0, 0, 0.35))
        if d.z < -0.5:
            d.z = -0.5
        d.normalize()
        p = c + d * r * rng.uniform(0.7, 0.95)
        n = (d + Vector(rng.normal(size=3)) * 0.18).normalized()
        t1 = n.cross(Vector(rng.normal(size=3))).normalized()
        t2 = n.cross(t1)
        s = size * rng.uniform(0.85, 1.15) / 2
        base = len(verts)
        for (a, b), uv in zip(((-1, -1), (1, -1), (1, 1), (-1, 1)), ((0, 0), (1, 0), (1, 1), (0, 1))):
            q = p + t1 * a * s + t2 * b * s
            verts.append(tuple(q))
            nrm.append(((q - centre).normalized() * 0.6 + n * 0.4).normalized())
        faces.append((base, base + 1, base + 2, base + 3))
        uvs += [(0, 0), (1, 0), (1, 1), (0, 1)]
    return mesh_obj("cards", verts, faces, uvs, mat, nrm)


def frond(root, direction, length, z_drop, width, mat, centre):
    """A drooping spruce frond: a V-shaped strip that arcs down from the trunk."""
    d = Vector((direction[0], direction[1], 0)).normalized()
    side = Vector((-d.y, d.x, 0))
    verts, faces, uvs, nrm = [], [], [], []
    steps = 3
    for k in range(steps + 1):
        s = k / steps
        spine = Vector(root) + d * (s * length) + Vector((0, 0, 0.18 * length * s - z_drop * s * s))
        w = width * (0.75 + 0.25 * math.sin(math.pi * min(1.0, s * 1.3)))
        for j, (off, lift) in enumerate(((-1, 0), (0, 0.1), (1, 0))):
            q = spine + side * off * w / 2 + Vector((0, 0, lift * w))
            verts.append(tuple(q))
            nrm.append(((q - centre).normalized() * 0.5 + Vector((0, 0, 0.8))).normalized())
    for k in range(steps):
        for j in range(2):
            a = k * 3 + j
            faces.append((a, a + 3, a + 4, a + 1))  # wound to face up, like its normals
            uvs += [(j / 2, k / steps), (j / 2, (k + 1) / steps), ((j + 1) / 2, (k + 1) / steps), ((j + 1) / 2, k / steps)]
    return mesh_obj("frond", verts, faces, uvs, mat, nrm)


def rock(loc, r, mat):
    st = K.ball("rock", 1.0, loc, mat, scale=(r * 1.3, r, r * 0.7), u=8, v=5)
    for vtx in st.data.vertices:
        vtx.co *= 0.82 + 0.3 * rng.random()
    return st


# --- build -----------------------------------------------------------------------------------

b_img, b_nrm = bark_image()
bark = K.textured("Bark_" + KIND, b_img, rough=0.92, normal=b_nrm)

if KIND == "spruce":
    needles = leaf_material("Leaves_" + KIND, frond_card())
    core_img = np.ones((128, 128, 3)) * np.array(K.hex_rgb(CORE[KIND]))[None, None, :]
    core_img *= (0.75 + 0.4 * K.tile_noise(128, 1.0, 9))[..., None]
    core = K.textured("LeafCore_" + KIND, K.save_image("leafcore_" + KIND, core_img, TEX), rough=0.9)
    H = 7.2
    trunk(H * 0.92, 0.2, 0.2, 5, bark)
    centre = Vector((0, 0, 3.2))
    tiers = 10
    for t in range(tiers):
        f = t / (tiers - 1)
        z = 0.9 + f * (H - 1.6)
        R = 2.15 * (1 - f) ** 0.95 + 0.35
        n = int(round(10 - 4 * f))
        turn = rng.uniform(0, 2 * np.pi)
        for k in range(n):
            a = turn + 2 * math.pi * k / n + rng.uniform(-0.2, 0.2)
            L = R * rng.uniform(0.9, 1.1)
            frond((0.08 * math.cos(a), 0.08 * math.sin(a), z), (math.cos(a), math.sin(a)), L, 0.45 * L, 0.8 * L + 0.3, needles, centre)
            # a shorter frond between each pair, a little higher, to close the gaps
            a2 = a + math.pi / n
            L2 = L * 0.72
            frond((0.08 * math.cos(a2), 0.08 * math.sin(a2), z + 0.28), (math.cos(a2), math.sin(a2)), L2, 0.4 * L2, 0.8 * L2 + 0.25, needles, centre)
    # a dark, tiered core so the tree is solid from every side
    prof = []
    for t in range(tiers):
        f = t / (tiers - 1)
        z = 0.9 + f * (H - 1.6)
        R = (2.15 * (1 - f) ** 0.95 + 0.35) * 0.55
        prof += [(R, z - 0.45), (R * 0.55, z + 0.05)]
    prof.append((0.0, H + 0.1))
    K.lathe("core", prof, core, steps=10, u_rep=3, v_rep=4, sharp=80)
    K.cyl("tip", 0.12, 0.0, 0.9, (0, 0, H + 0.25), core, verts=6)
else:
    leaves = leaf_material("Leaves_" + KIND, leaf_cards())
    core = leaf_material("LeafCore_" + KIND, leaf_core(), clip=False, rough=0.85)
    green = KIND == "maple_green"
    lean = (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25))
    trunk_h = 3.0 if green else 2.5
    trunk(trunk_h, 0.36, 0.34, 5, bark, lean=lean)
    top = Vector((lean[0], lean[1], trunk_h))
    lift = 0.5 if green else 0.0
    centre = Vector((lean[0], lean[1], 3.4 + lift))
    clumps = [((0, 0, 4.35 + lift), 1.35)]
    ring = 6 if not green else 5
    for i in range(ring):
        a = 2 * math.pi * i / ring + rng.uniform(-0.2, 0.2)
        rr = 1.4 if not green else 1.55
        clumps.append(((rr * math.cos(a), rr * math.sin(a), 3.5 + lift + rng.uniform(-0.2, 0.25)), rng.uniform(1.05, 1.25)))
    for i in range(4):
        a = 2 * math.pi * (i + 0.5) / 4 + rng.uniform(-0.3, 0.3)
        rr = 1.95 if not green else 2.05
        clumps.append(((rr * math.cos(a), rr * math.sin(a), 2.7 + lift + rng.uniform(-0.15, 0.2)), rng.uniform(0.85, 1.0)))
    for (cx, cy, cz), r in clumps:
        c = Vector((cx + lean[0], cy + lean[1], cz))
        # a branch from the top of the trunk out into each clump (they show in the open crown)
        tube(top - Vector((0, 0, 0.5)), c - (c - top).normalized() * r * 0.3, 0.13, 0.04, bark)
        blob(c, r * (0.72 if green else 0.82), 0.82, core, centre)
        cards(c, r, 15 if not green else 13, r * 1.25, leaves, centre)
    if not green:
        stone = K.textured("Rock_tree", K.save_image("rock_tree", np.array(K.hex_rgb("#77736c")) * (0.8 + 0.35 * K.tile_noise(64, 1.2, 3)[..., None]), TEX), rough=0.85)
        rock((0.75, -0.55, 0.08), 0.22, stone)
        rock((-0.6, 0.7, 0.06), 0.15, stone)

if KIND == "maple_autumn":
    # the fallen-leaf atlas for the ground scatter (scripts/world.gd): four pale maple leaves in a
    # 2 x 2 grid, tinted per leaf in the game
    lit = np.zeros((256, 256, 4))
    for cell in range(4):
        m, sh = rotated_leaf(118, rng.uniform(-np.pi, np.pi))
        stamp(lit, m, sh * (0.9 + 0.1 * cell / 3), 64 + 128 * (cell % 2), 64 + 128 * (cell // 2), np.ones(3))
    save_rgba("leaf_litter", lit)

K.finish(NAME, os.path.join(OUT, "out"), max_tris=6000)
