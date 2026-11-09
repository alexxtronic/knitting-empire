"""Character generator: builds humanoid characters in Blender from a spec.

Run headless:
  Blender -b -P tools/build_character.py -- <project_dir> [--character rowan|nora|all]
                                            [--render <out_dir> [--poses]]

Every character is one skinned mesh on the same 22-bone humanoid skeleton, with bone names
that follow Godot's SkeletonProfileHumanoid (Hips, Spine, Chest, UpperChest, Neck, Head,
Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes). The body is
shaped by the numbers in SPECS (height, shoulders, waist, hips, bust, limbs, head) and dressed
by its palette and style switches (hair, beard, cuffs). The animation set (Idle, Walk, SitKnit,
SitIdle, Work, Talk) is written once below and keyed onto every character, so they all move
the same way. Characters face -Y in Blender, which becomes +Z (forward) in Godot.

Writes <project_dir>/assets/<id>.glb, plus tools/character_build/<id>/ (.blend, textures).
With --render: a turntable strip and portrait (and with --poses, a pose sheet and knitting
close-ups) in <out_dir>/<id>/. With --character all, also <out_dir>/lineup.png.
"""
import bpy, bmesh, math, os, subprocess, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PROJECT = os.path.abspath(argv[0]) if argv else os.getcwd()
WHO = argv[argv.index("--character") + 1] if "--character" in argv else "all"
RENDER_ROOT = argv[argv.index("--render") + 1] if "--render" in argv else None

# ----------------------------------------------------------------------------- character specs
# Body numbers are multipliers on the base (male) build, so 1.0 everywhere is Rowan.
SPECS = {
    "rowan": dict(
        name="Rowan", height=1.0, shoulder=1.0, chest=1.0, waist=1.0, hip=1.0, neck=1.0, bust=0.0,
        arm=1.0, hand=1.0, thigh=1.0, calf=1.0, foot=1.0, head=1.09, jaw=1.0, arm_tilt=7,
        eye=1.0, nose=1.0, lips=(0.019, 0.0065, 0.0055), brow=(0.019, 0.005, 0.0048, -8),
        skin=(0.90, 0.69, 0.56), lip_color=(0.78, 0.50, 0.44), blush=0.15, iris=(0.26, 0.16, 0.09),
        hair=(0.31, 0.19, 0.11), hair_hi=(0.42, 0.27, 0.16), brow_color=(0.36, 0.24, 0.15),
        hair_style="curls", beard=(0.36, 0.24, 0.15), lashes=False, earrings=False,
        knit=((0.80, 0.74, 0.65), (0.39, 0.25, 0.16), (0.74, 0.68, 0.59)),  # base, motif, rib
        body_bands=[(37, "line"), (39, "diamonds"), (45, "star"), (59, "diamonds")],
        sleeve_bands=[(42, "line"), (44, "star"), (58, "dots")],
        swatch=((0.80, 0.74, 0.65), (0.39, 0.25, 0.16), (0.74, 0.68, 0.59)),
        denim=(0.29, 0.30, 0.34), cuffs=(0.64, 0.63, 0.60),
        leather=(0.52, 0.32, 0.18), leather_dk=(0.36, 0.22, 0.13), sole=(0.22, 0.16, 0.12),
    ),
    # The heroine, v1 (working name Nora): auburn hair up in a bun with soft bangs, a dusty-rose
    # hand-knit sweater with a cream Fair Isle yoke, dark jeans tucked into ankle boots.
    "nora": dict(
        name="Nora", height=0.955, shoulder=0.87, chest=0.93, waist=0.87, hip=1.06, neck=0.88, bust=1.0,
        arm=0.86, hand=0.86, thigh=0.95, calf=0.88, foot=0.88, head=1.08, jaw=0.93, arm_tilt=10,
        eye=1.1, nose=0.82, lips=(0.0195, 0.0075, 0.0068), brow=(0.019, 0.0038, 0.0032, -13),
        skin=(0.94, 0.76, 0.65), lip_color=(0.80, 0.43, 0.43), blush=0.24, iris=(0.27, 0.38, 0.24),
        hair=(0.42, 0.19, 0.10), hair_hi=(0.58, 0.29, 0.14), brow_color=(0.34, 0.17, 0.09),
        hair_style="bun", beard=None, lashes=True, earrings=True,
        knit=((0.77, 0.53, 0.53), (0.95, 0.90, 0.81), (0.70, 0.47, 0.47)),
        body_bands=[(33, "dots"), (35, "line"), (37, "diamonds"), (43, "star"), (57, "line"), (59, "dots")],
        sleeve_bands=[(44, "diamonds"), (50, "line"), (52, "dots")],
        swatch=((0.62, 0.68, 0.56), (0.95, 0.90, 0.81), (0.56, 0.62, 0.50)),  # sage, for the piece she knits
        denim=(0.20, 0.23, 0.31), cuffs=None,
        leather=(0.47, 0.29, 0.17), leather_dk=(0.33, 0.20, 0.12), sole=(0.20, 0.15, 0.12),
    ),
}

if WHO == "all":
    # Build each character in its own clean Blender process, then render a side-by-side lineup.
    for cid in SPECS:
        cmd = [bpy.app.binary_path, "-b", "-P", os.path.abspath(__file__), "--", PROJECT, "--character", cid]
        if RENDER_ROOT:
            cmd += ["--render", RENDER_ROOT] + (["--poses"] if "--poses" in argv else [])
        print("CHARACTER building", cid, flush=True)
        subprocess.run(cmd, check=True)
    if RENDER_ROOT:
        imgs = []
        for cid in SPECS:
            p = os.path.join(RENDER_ROOT, cid, "turn_000.png")
            if os.path.exists(p):
                im = bpy.data.images.load(p)
                imgs.append(np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4))
        if imgs:
            strip = np.concatenate(imgs, axis=1)
            out = bpy.data.images.new("lineup", strip.shape[1], strip.shape[0], alpha=True)
            out.pixels.foreach_set(strip.ravel())
            out.filepath_raw = os.path.join(RENDER_ROOT, "lineup.png")
            out.file_format = "PNG"
            out.save()
            print("CHARACTER lineup", out.filepath_raw)
    sys.exit(0)

S = SPECS[WHO]
CID = WHO
H = S["height"]
RENDER_DIR = os.path.join(RENDER_ROOT, CID) if RENDER_ROOT else None
ASSETS = os.path.join(PROJECT, "assets")
BUILD = os.path.join(PROJECT, "tools", "character_build", CID)  # source files kept out of Godot's import
TEXDIR = os.path.join(BUILD, "textures")
os.makedirs(TEXDIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
rng = np.random.default_rng(7)

# ----------------------------------------------------------------------------- palette (sRGB)
SKIN = S["skin"]
LIPS = S["lip_color"]
HAIR = S["hair"]
HAIR_HI = S["hair_hi"]
BROW = S["brow_color"]
DENIM = S["denim"]
LEATHER = S["leather"]
LEATHER_DK = S["leather_dk"]
SOLE = S["sole"]
EYE_W = (0.95, 0.94, 0.91)
IRIS = S["iris"]


def lerp_keys(keys, x):
    """Piecewise-linear lookup in [(x, value), ...] sorted by x."""
    if x <= keys[0][0]:
        return keys[0][1]
    for (x0, v0), (x1, v1) in zip(keys, keys[1:]):
        if x <= x1:
            return v0 + (v1 - v0) * (x - x0) / (x1 - x0)
    return keys[-1][1]


def width_f(z):
    """How much wider (>1) or narrower than the base build the body is at height z."""
    return lerp_keys([(0.80, S["hip"]), (0.96, S["hip"]), (1.10, S["waist"]), (1.24, S["chest"]),
                      (1.33, S["shoulder"]), (1.40, S["shoulder"]), (1.50, S["neck"])], z)


def shape_profile(prof, depth=0.6, bust=False, densify=False):
    """Apply the spec's body shape to a lathe profile: widths follow width_f(z), depth follows
    it more gently, and a bust adds depth to the front of the chest."""
    rows = [tuple(p) + (0.0,) * (5 - len(p)) for p in prof]
    if densify and S["bust"] > 0:
        dense = []
        for a, b in zip(rows, rows[1:]):
            dense.append(a)
            if b[0] - a[0] > 0.05 and 1.10 < (a[0] + b[0]) / 2 < 1.36:
                for t in (1 / 3, 2 / 3):
                    dense.append(tuple(a[i] + (b[i] - a[i]) * t for i in range(5)))
        rows = dense + [rows[-1]]
    out = []
    for z, rx, ry, cx, cy in rows:
        f = width_f(z)
        rx *= f
        ry *= 1 + (f - 1) * depth
        if bust:
            b = S["bust"] * 0.021 * math.exp(-((z - 1.235) / 0.055) ** 2)
            ry += b
            cy -= b
        out.append((z, rx, ry, cx, cy))
    return out


def lin(c):
    return tuple(max(0.0, x) ** 2.2 for x in c)


# ----------------------------------------------------------------------------- textures
def save_image(name, arr):
    """arr: H x W x 3 sRGB floats, row 0 = bottom of the image (Blender convention)."""
    h, w, _ = arr.shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :3] = np.clip(arr, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = os.path.join(TEXDIR, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


# one knit stitch ("V") as an 8x8 brightness tile, row 0 = top of the tile
def _stitch_tile():
    t = np.zeros((8, 8), np.float32)
    for py in range(8):
        for px in range(8):
            lx = 0.6 + py * 0.42
            rx = 7.4 - (0.6 + py * 0.42)
            d = min(abs(px + 0.5 - lx - 0.5), abs(px + 0.5 - rx + 0.5))
            t[py, px] = math.exp(-(d * d) / 2.2)
    return 0.70 + 0.30 * t


STITCH = _stitch_tile()


def star_motif():
    """13x13 Nordic star / snowflake, True = brown."""
    m = np.zeros((13, 13), bool)
    for y in range(13):
        for x in range(13):
            dx, dy = x - 6, y - 6
            ax, ay = abs(dx), abs(dy)
            r = max(ax, ay)
            if (dx == 0 or dy == 0) and 2 <= r <= 5:
                m[y, x] = True  # spokes
            if ax == ay and 1 <= r <= 3:
                m[y, x] = True  # diagonals
            if ax + ay == 2:
                m[y, x] = True  # ring around the centre
            if (ax == 1 and ay == 4) or (ax == 4 and ay == 1):
                m[y, x] = True  # arrow heads near the spoke tips
            if (dx == 0 or dy == 0) and r == 6:
                m[y, x] = False
    return m


STAR = star_motif()


def knit_texture(name, cols, rows, bands, rib_rows=(), seed=1, pal=None):
    """Stitch-grid texture. bands: list of (row0, kind) placing motif rows (row 0 = bottom)."""
    grid = np.zeros((rows, cols), np.int8)  # 0 base, 1 motif, 2 rib-knit, 3 rib-purl
    for r0, r1 in rib_rows:
        for r in range(r0, r1):
            for c in range(cols):
                grid[r, c] = 2 if (c % 4) < 2 else 3
    for r0, kind in bands:
        if kind == "star":
            period = 16
            for c0 in range(0, cols, period):
                for y in range(13):
                    for x in range(13):
                        if STAR[y, x]:
                            rr, cc = r0 + y, (c0 + x + 1) % cols
                            if 0 <= rr < rows:
                                grid[rr, cc] = 1
            # little dots between the stars
            for c0 in range(0, cols, period):
                for (y, x) in [(6, 15), (3, 15), (9, 15)]:
                    rr, cc = r0 + y, (c0 + x) % cols
                    if 0 <= rr < rows:
                        grid[rr, cc] = 1
        elif kind == "diamonds":  # 5-row band of small diamonds
            for c in range(cols):
                for y in range(5):
                    if abs((c % 6) - 2) + abs(y - 2) <= 2 and abs((c % 6) - 2) + abs(y - 2) != 1 and 0 <= r0 + y < rows:
                        grid[r0 + y, c] = 1
        elif kind == "line":
            for c in range(cols):
                grid[r0, c] = 1
        elif kind == "dots":
            for c in range(0, cols, 2):
                grid[r0, c] = 1
    noise = np.random.default_rng(seed).normal(0, 0.025, (rows, cols))
    tex = np.zeros((rows * 8, cols * 8, 3), np.float32)
    base_c, motif_c, rib_c = pal or S["knit"]
    base = {0: base_c, 1: motif_c, 2: rib_c, 3: rib_c}
    for r in range(rows):
        for c in range(cols):
            k = int(grid[r, c])
            col = np.array(base[k]) * (1.0 + noise[r, c])
            shade = STITCH if k != 3 else (0.62 + 0.25 * STITCH)
            tile = shade[::-1, :, None] * col[None, None, :]
            tex[r * 8:(r + 1) * 8, c * 8:(c + 1) * 8] = tile
    return save_image(name, tex)


def denim_texture():
    h = w = 256
    y, x = np.mgrid[0:h, 0:w]
    twill = 0.5 + 0.5 * np.sin((x + y) * 1.6)
    n = np.random.default_rng(3).normal(0, 1, (h, w))
    v = 0.86 + 0.08 * twill + 0.05 * n
    arr = np.array(DENIM)[None, None, :] * v[..., None]
    arr += np.array([0.02, 0.02, 0.03]) * (np.random.default_rng(4).random((h, w))[..., None] > 0.97)
    return save_image("denim", arr)


def cuff_texture():
    h, w = 64, 256
    y, x = np.mgrid[0:h, 0:w]
    n = np.random.default_rng(5).normal(0, 1, (h, w))
    arr = np.array(S["cuffs"])[None, None, :] * (0.95 + 0.04 * n)[..., None]
    arr[h - 6:, :] = np.array((0.80, 0.79, 0.76))  # pale fold at the top edge
    arr[:6, :] *= 0.85
    return save_image("cuff", arr)


def leather_texture():
    h = w = 128
    n = np.random.default_rng(6).normal(0, 1, (h, w))
    arr = np.array(LEATHER)[None, None, :] * (0.93 + 0.06 * n)[..., None]
    return save_image("leather", arr)


Z_CHIN, Z_TOP = 1.475, 1.742


def head_texture():
    """Head UVs: u around (0 = back, 0.5 = face), v by height. Paints skin, beard, blush."""
    h, w = 512, 512
    v, u = np.mgrid[0:h, 0:w]
    u = (u + 0.5) / w
    z = Z_CHIN + (v + 0.5) / h * (Z_TOP - Z_CHIN)
    du = np.abs(u - 0.5)
    arr = np.ones((h, w, 3), np.float32) * np.array(SKIN)
    # warm cheeks and nose
    blush = np.exp(-(((du - 0.12) / 0.05) ** 2 + ((z - 1.575) / 0.02) ** 2))
    k = S["blush"]
    arr = arr * (1 - k * blush[..., None]) + np.array((0.86, 0.52, 0.45)) * k * blush[..., None]
    if not S["beard"]:
        return save_image("head", arr)
    # short, trimmed beard: jaw, chin, mustache, sideburns
    top = np.where(du < 0.06, 1.551, 1.551 + (du - 0.06) * 0.30)
    stache = (du < 0.06) & (z > 1.535) & (z < 1.551)
    beard = (z < top) & (du < 0.245)
    side = (du > 0.185) & (du < 0.245) & (z < 1.632)
    mouth = (du < 0.032) & (z > 1.520) & (z < 1.531)
    mask = (beard | side) & ~mouth
    edge = np.clip((top - z) / 0.022, 0, 1) * np.clip((0.245 - du) / 0.03, 0, 1)
    edge = np.where(side, np.clip((1.635 - z) / 0.01, 0, 1), edge)
    stub = np.random.default_rng(8).random((h, w))
    dens = np.where(mask, np.clip(edge, 0, 1) * (0.42 + 0.30 * (stub > 0.45)), 0.0)
    arr = arr * (1 - dens[..., None]) + np.array(S["beard"]) * dens[..., None]
    return save_image("head", arr)


def hair_texture():
    """Fine strands running up the head (lathe UVs: u around, v up), for sleek styles."""
    h, w = 256, 512
    r = np.random.default_rng(11)
    u_noise = np.repeat(r.normal(0, 1, (1, w)), h, axis=0)
    u_noise = 0.6 * u_noise + 0.4 * np.roll(u_noise, 1, axis=1)
    v_drift = np.linspace(0, 1, h)[:, None]
    t = np.clip(0.5 + 0.28 * u_noise + 0.08 * np.sin(v_drift * 9 + np.arange(w)[None, :] * 0.05), 0, 1)
    arr = np.array(HAIR)[None, None, :] * (1 - t[..., None]) + np.array(HAIR_HI)[None, None, :] * t[..., None]
    return save_image("hair", arr)


# ----------------------------------------------------------------------------- materials
def material(name, color=None, image=None, rough=0.75, sheen=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if out is None:
        out = nt.nodes.new("ShaderNodeOutputMaterial")
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    if image is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = image
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*lin(color), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    m.diffuse_color = (*lin(color if color else (0.8, 0.8, 0.8)), 1.0)
    return m


# ----------------------------------------------------------------------------- mesh helpers
def link(obj):
    scene.collection.objects.link(obj)
    return obj


def finish(bm, name, mat, smooth=True, subsurf=1):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    if mat:
        me.materials.append(mat)
    obj = link(bpy.data.objects.new(name, me))
    if subsurf:
        m = obj.modifiers.new("ss", "SUBSURF")
        m.levels = subsurf
        m.render_levels = subsurf
    return obj


def lathe(name, prof, mat, segs=32, v_of_z=None, u_rep=1.0, subsurf=1, caps=(True, True)):
    """Surface of revolution. prof rows: (z, rx, ry[, cx, cy]) bottom -> top.
    Ring vertex 0 is at the back (+Y), so u = 0.5 is the front of the character."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rings = []
    for p in prof:
        z, rx, ry = p[0], p[1], p[2]
        cx = p[3] if len(p) > 3 else 0.0
        cy = p[4] if len(p) > 4 else 0.0
        rings.append([bm.verts.new((cx + rx * math.sin(2 * math.pi * i / segs), cy + ry * math.cos(2 * math.pi * i / segs), z)) for i in range(segs)])
    zs = [p[0] for p in prof]
    z0, z1 = min(zs), max(zs)
    vz = v_of_z or (lambda z: (z - z0) / max(1e-6, z1 - z0))
    for r in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i]))
            for loop, uu in zip(f.loops, [i / segs, (i + 1) / segs, (i + 1) / segs, i / segs]):
                loop[uvl].uv = (uu * u_rep, vz(loop.vert.co.z))
    for idx, want in ((0, caps[0]), (len(rings) - 1, caps[1])):
        if not want:
            continue
        ring = rings[idx]
        c = Vector((0, 0, 0))
        for v in ring:
            c += v.co
        c /= len(ring)
        cv = bm.verts.new(c)
        for i in range(segs):
            f = bm.faces.new((cv, ring[i], ring[(i + 1) % segs]))
            for loop in f.loops:
                loop[uvl].uv = (0.5 * u_rep, vz(loop.vert.co.z))
    return finish(bm, name, mat, subsurf=subsurf)


def ellipsoid(name, center, radii, mat, segs=16, rings=10, rot=(0, 0, 0), subsurf=0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    uvl = bm.loops.layers.uv.new("UVMap")
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (0.5 + math.atan2(co.x, co.y) / (2 * math.pi), 0.5 + co.z / (2 * radii[2]))
    obj = finish(bm, name, mat, subsurf=subsurf)
    obj.location = center
    obj.rotation_euler = rot
    return obj


def rbox(name, center, size, mat, cuts=2, subsurf=2, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    uvl = bm.loops.layers.uv.new("UVMap")
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uvl].uv = (co.x / size[0] + co.y / size[1] + 0.5, co.z / size[2] + 0.5)
    obj = finish(bm, name, mat, subsurf=subsurf)
    obj.location = center
    obj.rotation_euler = rot
    return obj


def bake_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.clear()
    obj.data = me


def join(objs, name):
    """Merge several objects (world space) into one mesh, keeping materials."""
    bpy.context.view_layer.update()
    bm = bmesh.new()
    mats = []
    for o in objs:
        bake_modifiers(o)
        me = o.data.copy()
        me.transform(o.matrix_world)
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        for p in me.polygons:
            p.material_index = remap[p.material_index] if remap else 0
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        bpy.data.objects.remove(o)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    for m in mats:
        out.materials.append(m)
    return link(bpy.data.objects.new(name, out))


def empty(name, loc, parent=None, rot=(0, 0, 0)):
    e = link(bpy.data.objects.new(name, None))
    e.empty_display_size = 0.05
    e.location = loc
    e.rotation_euler = rot
    if parent is not None:
        bpy.context.view_layer.update()
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e


def attach(child, parent):
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()
    child.matrix_world = mw


# ----------------------------------------------------------------------------- materials & textures
OAT, OAT_RIB = S["knit"][0], S["knit"][2]
tex_body = knit_texture("sweater_body", 128, 64, bands=S["body_bands"], rib_rows=[(0, 7), (62, 64)], seed=1)
tex_sleeve = knit_texture("sweater_sleeve", 48, 64, bands=S["sleeve_bands"], rib_rows=[(0, 6)], seed=2)
m_sweater = material("Sweater", OAT, tex_body, rough=0.95)
m_sleeve = material("SweaterSleeve", OAT, tex_sleeve, rough=0.95)
m_collar = material("SweaterRib", OAT_RIB, rough=0.95)
m_denim = material("Denim", DENIM, denim_texture(), rough=0.9)
m_cuff = material("JeansCuff", S["cuffs"], cuff_texture(), rough=0.9) if S["cuffs"] else None
m_skin = material("Skin", SKIN, rough=0.55)
m_head = material("Face", SKIN, head_texture(), rough=0.55)
m_lips = material("Lips", LIPS, rough=0.5)
m_hair = material("Hair", HAIR, rough=0.6)
m_hair_hi = material("HairLight", HAIR_HI, rough=0.6)
m_brow = material("Brows", BROW, rough=0.8)
m_lash = material("Lashes", (0.10, 0.07, 0.06), rough=0.8)
m_gold = material("Gold", (0.85, 0.68, 0.38), rough=0.3)
m_eye = material("EyeWhite", EYE_W, rough=0.25)
m_iris = material("Iris", IRIS, rough=0.2)
m_leather = material("Leather", LEATHER, leather_texture(), rough=0.55)
m_leather_dk = material("LeatherDark", LEATHER_DK, rough=0.6)
m_sole = material("Sole", SOLE, rough=0.8)

# ----------------------------------------------------------------------------- body (torso, hips, neck)
TORSO_Z0, TORSO_Z1 = 0.90, 1.462
torso_v = lambda z: (z - TORSO_Z0) / (TORSO_Z1 - TORSO_Z0)
torso = lathe("torso", shape_profile([
    (0.900, 0.172, 0.118), (0.955, 0.173, 0.119), (0.966, 0.181, 0.125), (1.05, 0.183, 0.126),
    (1.15, 0.185, 0.128), (1.25, 0.190, 0.131), (1.32, 0.192, 0.128), (1.37, 0.180, 0.118),
    (1.405, 0.150, 0.102), (1.438, 0.105, 0.084), (1.462, 0.076, 0.070),
], bust=True, densify=True), m_sweater, segs=40, v_of_z=torso_v, caps=(True, False))
collar = lathe("collar", shape_profile([(1.430, 0.080, 0.074), (1.452, 0.078, 0.073), (1.470, 0.071, 0.067), (1.476, 0.062, 0.060)]),
               m_collar, segs=32, caps=(False, False))
hips = lathe("hips", shape_profile([(0.80, 0.150, 0.102), (0.86, 0.162, 0.110), (0.96, 0.163, 0.112)], depth=0.8), m_denim, segs=32)
NK = S["neck"]
neck = lathe("neck", [(1.40, 0.054 * NK, 0.052 * NK), (1.47, 0.050 * NK, 0.050 * NK, 0, 0.006), (1.53, 0.048 * NK, 0.048 * NK, 0, 0.012)], m_skin, segs=24)

# ----------------------------------------------------------------------------- head & face
HEAD_C = Vector((0.0, 0.006, 1.607))
head_v = lambda z: (z - Z_CHIN) / (Z_TOP - Z_CHIN)
JAW = lambda z: 1.0 + (S["jaw"] - 1.0) * min(1.0, max(0.0, (1.60 - z) / 0.09))  # narrower jaw and chin
head = lathe("head", [(z, rx * JAW(z), ry, cx, cy) for z, rx, ry, cx, cy in [
    (Z_CHIN, 0.032, 0.026, 0, -0.050), (1.488, 0.062, 0.058, 0, -0.034), (1.515, 0.080, 0.083, 0, -0.016),
    (1.555, 0.087, 0.097, 0, -0.005), (1.600, 0.090, 0.105, 0, 0.0), (1.640, 0.091, 0.108, 0, 0.005),
    (1.680, 0.087, 0.105, 0, 0.008), (1.712, 0.073, 0.091, 0, 0.010), (1.732, 0.047, 0.062, 0, 0.010), (Z_TOP, 0.012, 0.016, 0, 0.010),
]], m_head, segs=40, v_of_z=head_v)
face = [head]
E, N = S["eye"], S["nose"]
bw, bt, bh, broll = S["brow"]
for sx in (-1, 1):
    face.append(ellipsoid("eye", (sx * 0.035, -0.087, 1.613), (0.0165 * E, 0.0165, 0.0165 * E), m_eye))
    face.append(ellipsoid("iris", (sx * 0.035, -0.1015, 1.612), (0.0098 * E, 0.004, 0.0105 * E), m_iris, segs=12, rings=8))
    face.append(ellipsoid("lid", (sx * 0.035, -0.090, 1.623 + 0.0015 * (E - 1) * 10), (0.019 * E, 0.0165, 0.009), m_skin, rot=(math.radians(-12), 0, 0)))
    face.append(ellipsoid("brow", (sx * 0.037, -0.0985, 1.642 + 0.002 * (E - 1) * 10), (bw, bt, bh), m_brow, segs=10, rings=6, rot=(0, math.radians(sx * broll), 0)))
    face.append(ellipsoid("ear", (sx * 0.091 * S["jaw"] ** 0.5, 0.012, 1.598), (0.011, 0.021, 0.032), m_skin, rot=(0, 0, math.radians(sx * -12))))
    if S["lashes"]:
        face.append(ellipsoid("lash", (sx * 0.0362, -0.1032, 1.6205), (0.0175 * E, 0.0022, 0.0016), m_lash, segs=12, rings=6,
                              rot=(math.radians(-8), math.radians(sx * -6), 0)))
        face.append(ellipsoid("lashtip", (sx * 0.0535, -0.0975, 1.6225), (0.0042, 0.0018, 0.0016), m_lash, segs=8, rings=5,
                              rot=(0, math.radians(sx * -28), 0)))
    if S["earrings"]:
        face.append(ellipsoid("earring", (sx * 0.0955 * S["jaw"] ** 0.5, 0.004, 1.566), (0.0048, 0.0048, 0.0048), m_gold, segs=10, rings=6))
face.append(ellipsoid("nose", (0, -0.1035 + 0.006 * (1 - N), 1.588), (0.0095 * N, 0.013 * N, 0.027 * N), m_skin, rot=(math.radians(-14), 0, 0)))
face.append(ellipsoid("nosetip", (0, -0.1125 + 0.010 * (1 - N), 1.569 + 0.004 * (1 - N)), (0.0118 * N, 0.0105 * N, 0.0098 * N), m_skin))
for sx in (-1, 1):
    face.append(ellipsoid("nostril", (sx * 0.0092 * N, -0.1065 + 0.008 * (1 - N), 1.566 + 0.004 * (1 - N)), (0.0062 * N, 0.0072 * N, 0.0062 * N), m_skin))
face.append(ellipsoid("lips", (0, -0.0975, 1.526), S["lips"], m_lips))

# hair: a cap over the scalp plus clumps of curls
HR = Vector((0.093, 0.109, 0.134))


def hair_ok(d, margin=0.0):
    """d: unit direction from head centre. Front of face is -Y."""
    front = -d.y
    thr = -0.12 + 0.55 * front
    if front < -0.2:
        thr = -0.12 + 1.9 * (front + 0.2) * 0.55 - 0.08  # lower at the back (nape)
    if abs(d.x) > 0.75 and front > -0.2:
        thr = max(thr, 0.02)  # above the ears
    return d.z > thr + margin


def hair_cap(margin, subsurf, mat=None, front_lift=0.0, feather=False):
    prof = [
        (1.45, 0.066, 0.080, 0, 0.012), (1.52, 0.085, 0.100, 0, 0.012), (1.58, 0.094, 0.111, 0, 0.008),
        (1.63, 0.096, 0.113, 0, 0.007), (1.68, 0.092, 0.110, 0, 0.008), (1.715, 0.079, 0.097, 0, 0.010),
        (1.742, 0.052, 0.068, 0, 0.010), (1.756, 0.01, 0.012, 0, 0.010),
    ]
    segs = 36
    if feather:
        # finer rings and segments so the hairline can follow a curve instead of a ring
        fine = []
        for a, b in zip(prof, prof[1:]):
            for t in (0, 0.25, 0.5, 0.75):
                fine.append(tuple(a[i] + (b[i] - a[i]) * t for i in range(5)))
        prof = fine + [prof[-1]]
        segs = 72
    cap = lathe("haircap", prof, mat or m_hair, segs=segs, subsurf=0)
    bm = bmesh.new()
    bm.from_mesh(cap.data)

    def keep(f):
        d = (f.calc_center_median() - HEAD_C).normalized()
        return hair_ok(d, margin + front_lift * max(0.0, -d.y) ** 2)  # front_lift arches the hairline up over the forehead
    kill = [f for f in bm.faces if not keep(f)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    if feather:
        # feather the hairline: pull the open edge (and the ring inside it) down onto the scalp
        edge = {v for v in bm.verts if v.is_boundary}
        inner = {o for v in edge for e in v.link_edges for o in e.verts} - edge
        for vs, k in ((edge, 0.952), (inner, 0.985)):
            for v in vs:
                v.co = HEAD_C + (v.co - HEAD_C) * k
    bm.to_mesh(cap.data)
    bm.free()
    m = cap.modifiers.new("ss", "SUBSURF")
    m.levels = subsurf
    return cap


def oriented(name, p, d, t, sc, mat):
    """Ellipsoid at p whose thin axis is the surface normal d and long axis is t."""
    t = (t - d * t.dot(d)).normalized()
    xl = d.cross(t).normalized()
    basis = Matrix((xl, d, t)).transposed()
    return ellipsoid(name, p, sc, mat, segs=12, rings=8, rot=tuple(basis.to_euler()), subsurf=0)


def hair_curls():
    """Short curly hair (Rowan): a cap over the scalp plus clumps of curls."""
    cap = hair_cap(0.04, 1)
    hair = [cap]
    n = 700
    for k in range(n):
        zz = 1 - 2 * (k + 0.5) / n
        rr = math.sqrt(max(0.0, 1 - zz * zz))
        ph = k * math.pi * (3 - math.sqrt(5))
        d = Vector((rr * math.cos(ph), rr * math.sin(ph), zz))
        if not hair_ok(d):
            continue
        if rng.random() < 0.18:
            continue
        r = rng.uniform(0.020, 0.027)
        lift = 0.004 + 0.008 * max(0.0, d.z) ** 1.5
        p = HEAD_C + Vector((HR.x * d.x, HR.y * d.y, HR.z * d.z)) + d * (lift - 0.004)
        # flow direction: down the sides/back, swept forward and outward on top
        down = Vector((0, 0, -1)) - d * (-d.z)
        out = Vector((d.x * 0.6, 1.0, 0.25))
        w = min(1.0, max(0.0, (d.z - 0.35) / 0.4 + max(0.0, -d.y) * 0.8))
        t = (down.normalized() * (1 - w) + (out.normalized() if out.length > 1e-3 else Vector((0, -1, 0))) * w)
        t = (t - d * t.dot(d)).normalized()
        t = (t + Vector((rng.normal(0, 0.25), rng.normal(0, 0.25), rng.normal(0, 0.15)))).normalized()
        t = (t - d * t.dot(d)).normalized()
        xl = d.cross(t).normalized()
        basis = __import__("mathutils").Matrix((xl, d, t)).transposed()
        rot = tuple(basis.to_euler())
        sc = (r * rng.uniform(1.0, 1.3), r * rng.uniform(0.5, 0.65), r * rng.uniform(1.9, 2.6))
        hair.append(ellipsoid("curl", p, sc, m_hair_hi if rng.random() < 0.3 else m_hair, segs=12, rings=8, rot=rot, subsurf=0))
    # a few loose curls falling over the forehead and over the ears
    for p, r in [((0.088, -0.02, 1.640), 0.019), ((-0.090, -0.02, 1.642), 0.019),
                 ((0.066, 0.068, 1.548), 0.021), ((-0.066, 0.068, 1.548), 0.021), ((0.0, 0.094, 1.543), 0.022)]:
        hair.append(ellipsoid("curl", p, (r, r * 0.8, r * 1.4), m_hair, segs=12, rings=8, rot=(rng.uniform(-0.5, 0.5), 0.3, rng.uniform(0, 3)), subsurf=0))
    return hair


def hair_bun():
    """Hair up in a bun with soft curved bangs (Nora), and loose strands framing the face."""
    m_sleek = material("HairSleek", HAIR, hair_texture(), rough=0.5)
    cap = hair_cap(0.03, 2, m_sleek, front_lift=0.09)  # soft curved bangs
    hair = [cap]
    # the bun: a round knot with a few rolled loops around it
    bun_c = HEAD_C + Vector((0.0, 0.108, 0.104))
    hair.append(ellipsoid("bun", bun_c, (0.043, 0.036, 0.040), m_sleek, segs=20, rings=12, rot=(math.radians(35), 0, 0), subsurf=1))
    for i in range(6):
        a = i * math.tau / 6 + 0.4
        off = Vector((math.cos(a) * 0.030, 0.006, math.sin(a) * 0.028))
        hair.append(ellipsoid("bunloop", bun_c + off, (0.022, 0.018, 0.016), m_hair_hi if i % 2 else m_hair, segs=14, rings=9,
                              rot=(math.radians(35), 0, a), subsurf=1))
    # loose strands framing the face, from the temples down to the jaw, hugging the cheek
    for sx in (-1, 1):
        pts = [Vector((sx * 0.082, -0.058, 1.705)), Vector((sx * 0.086, -0.060, 1.660)), Vector((sx * 0.085, -0.056, 1.618)),
               Vector((sx * 0.081, -0.050, 1.588))]
        for a, b in zip(pts, pts[1:]):
            mid = (a + b) * 0.5
            out = Vector((sx, -0.35, 0)).normalized()
            hair.append(oriented("wisp", mid, out, b - a, (0.0062, 0.0028, (b - a).length * 0.8), m_hair))
    # a few short wisps at the nape
    for x in (-0.03, 0.0, 0.032):
        hair.append(oriented("nape", Vector((x, 0.084, 1.515)), Vector((0, 1, -0.2)).normalized(), Vector((0, 0.2, -1)),
                             (0.008, 0.0035, 0.020), m_hair))
    return hair


hair = hair_curls() if S["hair_style"] == "curls" else hair_bun()

# ----------------------------------------------------------------------------- arms
SHOULDER_Z = 1.372
sleeve_v = lambda z: (z - 0.862) / (1.425 - 0.862)
arm_parts = {}
A, HD = S["arm"], S["hand"]
SHOULDER_X = 0.186 * S["shoulder"]
for side, sx in (("L", 1), ("R", -1)):
    x = sx * SHOULDER_X
    parts = [lathe("sleeve", [
        (0.862, 0.044 * A, 0.044 * A, x, 0), (0.905, 0.046 * A, 0.046 * A, x, 0), (0.916, 0.051 * A, 0.051 * A, x, 0),
        (1.02, 0.054 * A, 0.053 * A, x, 0.003), (1.10, 0.057 * A, 0.055 * A, x, 0.004), (1.22, 0.062 * A, 0.060 * A, x, 0.002),
        (1.31, 0.066 * A, 0.065 * A, x, 0), (1.365, 0.058 * A, 0.060 * A, x - sx * 0.008 * A, 0), (1.392, 0.030 * A, 0.036 * A, x - sx * 0.02 * A, 0),
    ], m_sleeve, segs=24, v_of_z=sleeve_v)]
    # hand hanging relaxed, palm facing the leg (sized about the wrist at z 0.85)
    hx = x + sx * 0.002
    WZ = 0.85
    parts.append(lathe("wrist", [(0.85, 0.032 * HD, 0.036 * HD, hx, 0), (0.885, 0.034 * HD, 0.038 * HD, hx, 0)], m_skin, segs=16, caps=(False, True)))
    parts.append(rbox("palm", (hx, -0.004 * HD, WZ - 0.045 * HD), (0.034 * HD, 0.078 * HD, 0.092 * HD), m_skin, cuts=2, subsurf=2))
    parts.append(rbox("fingers", (hx - sx * 0.002, -0.006 * HD, WZ - 0.115 * HD), (0.03 * HD, 0.072 * HD, 0.072 * HD), m_skin, cuts=2, subsurf=2, rot=(0, math.radians(sx * 4), 0)))
    parts.append(ellipsoid("thumb", (hx - sx * 0.008 * HD, -0.044 * HD, WZ - 0.06 * HD), (0.014 * HD, 0.016 * HD, 0.036 * HD), m_skin, rot=(math.radians(-18), math.radians(sx * 10), 0)))
    arm_parts[side] = parts

# ----------------------------------------------------------------------------- legs & boots
HIP_Z, KNEE_Z = 0.86, 0.48
leg_parts, shin_parts = {}, {}
TH, CF, FT = S["thigh"], S["calf"], S["foot"]
LEG_X = 0.087 * S["hip"]
for side, sx in (("L", 1), ("R", -1)):
    x = sx * LEG_X
    leg_parts[side] = [lathe("thigh", [
        (0.455, 0.062 * CF, 0.064 * CF, x, 0), (0.60, 0.069 * TH, 0.071 * TH, x, 0), (0.75, 0.078 * TH, 0.080 * TH, x, 0.002),
        (0.90, 0.086 * TH, 0.088 * TH, x * 0.92, 0.004),
    ], m_denim, segs=24)]
    # rolled cuffs over the boots, or jeans tucked into the boot shaft
    shin_z0 = 0.235 if S["cuffs"] else 0.15
    sp = [lathe("shin", [
        (shin_z0, 0.058 * CF if not S["cuffs"] else 0.060, 0.060 * CF if not S["cuffs"] else 0.062, x, 0),
        (0.33, 0.060 * CF, 0.062 * CF, x, 0), (0.44, 0.063 * CF, 0.065 * CF, x, 0), (0.52, 0.066 * CF, 0.068 * CF, x, 0),
    ], m_denim, segs=24)]
    if S["cuffs"]:
        sp.append(lathe("cuff", [(0.165, 0.071, 0.073, x, 0), (0.200, 0.073, 0.075, x, 0), (0.250, 0.073, 0.075, x, 0), (0.258, 0.066, 0.068, x, 0)],
                        m_cuff, segs=24, caps=(False, False)))
    sp.append(lathe("bootshaft", [(0.03, 0.057 * FT, 0.064 * FT, x, -0.004), (0.10, 0.055 * FT, 0.060 * FT, x, 0.0),
                                  (0.165, 0.058 * FT, 0.061 * FT, x, 0.0), (0.18, 0.063 * FT, 0.066 * FT, x, 0.0)],
                    m_leather, segs=24))
    sp.append(rbox("bootfoot", (x, -0.045 * FT, 0.048), (0.102 * FT, 0.245 * FT, 0.09), m_leather, cuts=3, subsurf=2))
    sp.append(rbox("toecap", (x, -0.125 * FT, 0.045), (0.096 * FT, 0.08 * FT, 0.075), m_leather_dk, cuts=2, subsurf=2))
    sp.append(rbox("sole", (x, -0.04 * FT, 0.012), (0.112 * FT, 0.265 * FT, 0.026), m_sole, cuts=2, subsurf=1))
    sp.append(rbox("heel", (x, 0.055 * FT, 0.018), (0.1 * FT, 0.075 * FT, 0.034), m_sole, cuts=1, subsurf=1))
    sp.append(rbox("tongue", (x, -0.058 * FT, 0.115), (0.04 * FT, 0.012, 0.09), m_leather_dk, cuts=1, subsurf=1, rot=(math.radians(-12), 0, 0)))
    for i, zl in enumerate([0.085, 0.11, 0.135, 0.16]):
        sp.append(rbox("lace", (x, (-0.064 + i * 0.002) * FT, zl), (0.05 * FT, 0.008, 0.007), m_sole, cuts=0, subsurf=0))
    shin_parts[side] = sp

# ----------------------------------------------------------------------------- skeleton, skin weights
SIDES = (("L", 1), ("R", -1))
SIDE_NAME = {"L": "Left", "R": "Right"}
ARM_TILT = math.radians(S["arm_tilt"])  # rest pose: arms hang slightly away from the hips
UPPER_ARM, FORE_ARM, HAND_LEN = 0.272, 0.233, 0.17
ANKLE_Z = 0.10
SH = {s: Vector((sx * SHOULDER_X, 0, SHOULDER_Z)) for s, sx in SIDES}


def arm_dir(sx):
    return Vector((sx * math.sin(ARM_TILT), 0, -math.cos(ARM_TILT)))


def smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def chain(x, bones, joints, widths):
    """Weights along a bone chain: blend from bone i to i+1 around each joint."""
    w = {bones[0]: 1.0}
    for i, (j, h) in enumerate(zip(joints, widths)):
        t = smooth(j - h, j + h, x)
        for k in list(w):
            w[k] *= 1 - t
        w[bones[i + 1]] = w.get(bones[i + 1], 0.0) + t
    return w


def weigh(obj, fn):
    groups = {}
    for v in obj.data.vertices:
        w = {b: x for b, x in fn(v.co).items() if x > 1e-3}
        tot = sum(w.values())
        for b, x in w.items():
            if b not in groups:
                groups[b] = obj.vertex_groups.new(name=b)
            groups[b].add([v.index], x / tot, "REPLACE")


def body_w(co):
    w = chain(co.z, ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"],
              [0.98, 1.12, 1.28, 1.42, 1.50], [0.05, 0.06, 0.06, 0.03, 0.02])
    sh = smooth(0.11, 0.18, abs(co.x)) * smooth(1.27, 1.36, co.z) * 0.6
    if sh > 0:
        for k in w:
            w[k] *= 1 - sh
        w[("Left" if co.x > 0 else "Right") + "Shoulder"] = sh
    return w


def arm_w(s, sx):
    n = SIDE_NAME[s]
    sp, d = SH[s], arm_dir(sx)
    return lambda co: chain((co - sp).dot(d), [n + "UpperArm", n + "LowerArm", n + "Hand"],
                            [UPPER_ARM, UPPER_ARM + FORE_ARM], [0.05, 0.02])


def leg_w(s):
    n = SIDE_NAME[s]

    def f(co):
        w = chain(HIP_Z - co.z, [n + "UpperLeg", n + "LowerLeg"], [HIP_Z - KNEE_Z], [0.05])
        foot = smooth(0.15, 0.085, co.z) * smooth(0.02, -0.04, co.y)
        if foot > 0:
            toe = smooth(-0.08 * FT, -0.125 * FT, co.y)
            for k in w:
                w[k] *= 1 - foot
            w[n + "Foot"] = foot * (1 - toe)
            w[n + "Toes"] = foot * toe
        return w
    return f


bpy.context.view_layer.update()
parts = []
body = join([torso, collar, hips, neck], "body_part")
weigh(body, body_w)
parts.append(body)
headm = join(face + hair, "head_part")
# stylised proportions: a slightly larger head, scaled about the neck
headm.data.transform(Matrix.Translation((0, 0, 1.47)) @ Matrix.Scale(S["head"], 4) @ Matrix.Translation((0, 0, -1.47)))
weigh(headm, lambda co: {"Head": 1.0})
parts.append(headm)
for s, sx in SIDES:
    a = join(arm_parts[s], "arm_part")
    a.data.transform(Matrix.Translation(SH[s]) @ Matrix.Rotation(-sx * ARM_TILT, 4, "Y") @ Matrix.Translation(-SH[s]))
    weigh(a, arm_w(s, sx))
    lg = join(leg_parts[s] + shin_parts[s], "leg_part")
    weigh(lg, leg_w(s))
    parts += [a, lg]

for o in scene.objects:
    if o is not None:
        o.select_set(False)
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
mesh = body
mesh.name = S["name"] + "Mesh"
mesh.data.name = S["name"] + "Mesh"
mesh.data.transform(Matrix.Scale(H, 4))  # overall height; the skeleton below is scaled to match

rig = bpy.data.armatures.new(S["name"] + "Rig")
root = link(bpy.data.objects.new(S["name"], rig))
for o in scene.objects:
    if o is not None:
        o.select_set(False)
root.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.object.mode_set(mode="EDIT")
FWD, UP = Vector((0, -1, 0)), Vector((0, 0, 1))


def bone(name, head, tail, parent=None, roll_to=FWD):
    b = rig.edit_bones.new(name)
    b.head, b.tail = Vector(head) * H, Vector(tail) * H
    b.align_roll(roll_to)
    if parent:
        b.parent = rig.edit_bones[parent]
    return b


bone("Hips", (0, 0, HIP_Z), (0, 0, 0.98))
bone("Spine", (0, 0, 0.98), (0, 0, 1.12), "Hips")
bone("Chest", (0, 0, 1.12), (0, 0, 1.28), "Spine")
bone("UpperChest", (0, 0, 1.28), (0, 0, 1.42), "Chest")
bone("Neck", (0, 0, 1.42), (0, 0, 1.50), "UpperChest")
bone("Head", (0, 0, 1.50), (0, 0, 1.78), "Neck")
for s, sx in SIDES:
    n = SIDE_NAME[s]
    sp, d = SH[s], arm_dir(sx)
    bone(n + "Shoulder", (sx * 0.03, 0, 1.385), (sx * 0.15 * S["shoulder"], 0, 1.385), "UpperChest")
    bone(n + "UpperArm", sp, sp + d * UPPER_ARM, n + "Shoulder")
    bone(n + "LowerArm", sp + d * UPPER_ARM, sp + d * (UPPER_ARM + FORE_ARM), n + "UpperArm")
    bone(n + "Hand", sp + d * (UPPER_ARM + FORE_ARM), sp + d * (UPPER_ARM + FORE_ARM + HAND_LEN), n + "LowerArm")
    x = sx * LEG_X
    bone(n + "UpperLeg", (x, 0, HIP_Z), (x, 0, KNEE_Z), "Hips")
    bone(n + "LowerLeg", (x, 0, KNEE_Z), (x, 0, ANKLE_Z), n + "UpperLeg")
    bone(n + "Foot", (x, 0, ANKLE_Z), (x, -0.10 * FT, 0.035), n + "LowerLeg", roll_to=UP)
    bone(n + "Toes", (x, -0.10 * FT, 0.035), (x, -0.165 * FT, 0.035), n + "Foot", roll_to=UP)
bpy.ops.object.mode_set(mode="OBJECT")

mesh.parent = root
mod = mesh.modifiers.new("Armature", "ARMATURE")
mod.object = root
for pb in root.pose.bones:
    pb.rotation_mode = "XYZ"

# ----------------------------------------------------------------------------- animations
# Bone-local rotations in degrees. With this rig, +X swings a limb FORWARD for arms and legs
# (and bends the spine/head forward); a knee bends back with -X on the LowerLeg; an elbow
# bends with +X on the LowerArm. Arms: +Y on Left / -Y on Right rotates the arm inward.
FPS = 30
scene.render.fps = FPS


def mirror(d, n_from, n_to):
    """Copy Left* values to Right* with Y/Z flipped (and vice versa)."""
    for k, (x, y, z) in list(d.items()):
        if k.startswith(n_from):
            d[n_to + k[len(n_from):]] = (x, -y, -z)
    return d


def P(**kw):
    return {k: v for k, v in kw.items()}


SIT_DROP = -(HIP_Z * H - 0.08)  # hips rest on a seat whose top is at the character origin + 0.08


def a_idle(p):
    b = math.sin(2 * math.pi * p)
    d = P(Chest=(1.2 * b, 0, 0), Neck=(-0.8 * b, 0, 0), Head=(1.0, 3 * math.sin(2 * math.pi * p + 1), 0),
          LeftUpperArm=(1.5 * b, 0, 0), LeftLowerArm=(6, 0, 0))
    mirror(d, "Left", "Right")
    d["hips_loc"] = 0.003 * b
    return d


def a_walk(p):
    s, c = math.sin(2 * math.pi * p), math.cos(2 * math.pi * p)
    d = {}
    for n, sg in (("Left", 1), ("Right", -1)):
        thigh = 28 * sg * s + 4
        knee = -6 - 52 * max(0.0, sg * c) ** 2
        d[n + "UpperLeg"] = (thigh, 0, 0)
        d[n + "LowerLeg"] = (knee, 0, 0)
        d[n + "Foot"] = (-(thigh + knee) * 0.75 - 4, 0, 0)
        d[n + "UpperArm"] = (-20 * sg * s, 0, 0)
        d[n + "LowerArm"] = (14 + 12 * max(0.0, -sg * s), 0, 0)
    d["Spine"] = (3, 5 * s, 0)
    d["Chest"] = (2, -3 * s, 0)
    d["Head"] = (-2, -2 * s, 0)
    d["hips_loc"] = 0.022 * (c * c - 0.5)
    return d


def sit_base():
    d = P(Spine=(8, 0, 0), Chest=(4, 0, 0))
    for n in ("Left", "Right"):
        d[n + "UpperLeg"] = (86, 0, 0)
        d[n + "LowerLeg"] = (-84, 0, 0)
        d[n + "Foot"] = (-2, 0, 0)
    d["hips_loc"] = SIT_DROP
    return d


def a_sit_knit(p):
    k = math.sin(2 * math.pi * p * 2)
    d = sit_base()
    d.update(Neck=(10, 0, 0), Head=(16, 0, 0),
             LeftUpperArm=(18 + 3 * k, 14, 0), LeftLowerArm=(92 + 6 * k, 0, 0), LeftHand=(-10, 0, 8 * k),
             RightUpperArm=(18 - 3 * k, -14, 0), RightLowerArm=(92 - 6 * k, 0, 0), RightHand=(-10, 0, 8 * k))
    return d


def a_sit_idle(p):
    b = math.sin(2 * math.pi * p)
    d = sit_base()
    d.update(Chest=(4 + 1.2 * b, 0, 0), Head=(4, 6 * math.sin(2 * math.pi * p + 0.6), 0),
             LeftUpperArm=(30, 12, 0), LeftLowerArm=(42, 0, 0), RightUpperArm=(30, -12, 0), RightLowerArm=(42, 0, 0))
    return d


def a_work(p):
    k = math.sin(2 * math.pi * p * 2)
    d = P(Hips=(4, 0, 0), Spine=(18, 0, 0), Chest=(12, 0, 0), Neck=(8, 0, 0), Head=(10, 0, 0),
          LeftUpperLeg=(14, 0, 0), LeftLowerLeg=(-26, 0, 0), LeftFoot=(10, 0, 0),
          LeftUpperArm=(52 + 10 * k, 14, 0), LeftLowerArm=(30 - 8 * k, 0, 0),
          RightUpperArm=(52 - 10 * k, -14, 0), RightLowerArm=(30 + 8 * k, 0, 0))
    d["RightUpperLeg"], d["RightLowerLeg"], d["RightFoot"] = (14, 0, 0), (-26, 0, 0), (10, 0, 0)
    d["hips_loc"] = -0.035
    return d


def a_talk(p):
    k = math.sin(2 * math.pi * p * 2)
    d = P(Chest=(0, 3 * math.sin(2 * math.pi * p), 0), Head=(3 + 3 * k, 5 * math.sin(2 * math.pi * p), 0),
          RightUpperArm=(22, -10, -4), RightLowerArm=(68 + 12 * k, 0, 0), RightHand=(-8 * k, 0, 0),
          LeftUpperArm=(4, 0, 0), LeftLowerArm=(10, 0, 0))
    return d


ANIMS = [("Idle", 60, a_idle), ("Walk", 18, a_walk), ("SitKnit", 40, a_sit_knit),
         ("SitIdle", 90, a_sit_idle), ("Work", 30, a_work), ("Talk", 60, a_talk)]
root.animation_data_create()
actions = {}
for name, frames, fn in ANIMS:
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    root.animation_data.action = act
    for f in range(frames + 1):
        vals = fn((f % frames) / frames)
        for pb in root.pose.bones:
            pb.rotation_euler = [math.radians(a) for a in vals.get(pb.name, (0, 0, 0))]
            pb.keyframe_insert("rotation_euler", frame=f)
        hb = root.pose.bones["Hips"]
        hb.location = (0, vals.get("hips_loc", 0.0), 0)
        hb.keyframe_insert("location", frame=f)
    track = root.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    actions[name] = act
    root.animation_data.action = None
for pb in root.pose.bones:
    pb.rotation_euler = (0, 0, 0)
    pb.location = (0, 0, 0)

# ----------------------------------------------------------------------------- knitting props
# Two needles and a small Fair Isle swatch, modelled where the hands are in the SitKnit pose and
# then moved back into the rest pose so they ride on the hand bones. Exported as a separate
# mesh ("KnitProps") that the game only shows while knitting.
m_needle = material("Needle", (0.86, 0.70, 0.47), rough=0.35)
m_needle_cap = material("NeedleCap", (0.45, 0.24, 0.16), rough=0.4)
m_swatch = material("Swatch", S["swatch"][0], knit_texture("swatch", 24, 18, bands=[(5, "line"), (7, "diamonds"), (13, "line")],
                                                             rib_rows=[(0, 3)], seed=4, pal=S["swatch"]), rough=0.95)

root.animation_data.action = actions["SitKnit"]
scene.frame_set(0)
bpy.context.view_layer.update()


def hand_frame(n):
    pb = root.pose.bones[n + "Hand"]
    h, t = pb.head.copy(), pb.tail.copy()
    deform = pb.matrix @ pb.bone.matrix_local.inverted()  # rest -> posed (armature space)
    return h + (t - h) * 0.42, (t - h).normalized(), deform


gL, dirL, defL = hand_frame("Left")
gR, dirR, defR = hand_frame("Right")
UPV = Vector((0, 0, 1))
mid = (gL + gR) * 0.5 + UPV * 0.035 + Vector((0, -0.03, 0))  # needle tips cross a little above and ahead
print(CID.upper(), "knit grips L", tuple(round(x, 3) for x in gL), "R", tuple(round(x, 3) for x in gR), "gap", round((gL - gR).length, 3))


def stick(a, b, r, cap_at_a=True):
    """A needle from a to b (tapered at b), as its own object in posed space."""
    L = (b - a).length
    o = lathe("needle", [(0.0, r, r), (L - 0.035, r, r), (L - 0.012, r * 0.55, r * 0.55), (L, r * 0.12, r * 0.12)],
              m_needle, segs=10, subsurf=0)
    q = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    o.data.transform(Matrix.Translation(a) @ q.to_matrix().to_4x4())
    objs = [o]
    if cap_at_a:
        c = ellipsoid("needlecap", a - (b - a).normalized() * 0.004, (0.0085, 0.0085, 0.0085), m_needle_cap, segs=10, rings=6)
        objs.append(c)
    return objs


def swatch(top_a, top_b, depth, toward):
    """Knitted piece hanging from the segment top_a..top_b, bowing slightly toward `toward`."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    nu, nv = 8, 6
    across = top_b - top_a
    grid = []
    for j in range(nv + 1):
        v = j / nv
        row = []
        for i in range(nu + 1):
            u = i / nu
            p = top_a + across * u - UPV * depth * v + toward * (0.025 * math.sin(math.pi * v) + 0.03 * v)
            p += toward * 0.006 * math.sin(math.pi * u)
            row.append(bm.verts.new(p))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop, (uu, vv) in zip(f.loops, [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]):
                loop[uvl].uv = (uu / nu, 1.0 - vv / nv)
    o = finish(bm, "swatch", m_swatch, subsurf=0)
    sol = o.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.006
    return o


toward_body = Vector((0, 1, 0))
pieces = {"Right": [], "Left": []}
# right needle: from behind the right hand, through the grip, to just past the middle
pieces["Right"] += stick(gR + (gR - mid).normalized() * 0.07, mid + (mid - gR).normalized() * 0.06, 0.0042)
# left needle carries the work
pieces["Left"] += stick(gL + (gL - mid).normalized() * 0.07, mid + (mid - gL).normalized() * 0.05 + UPV * 0.012, 0.0042)
pieces["Left"].append(swatch(gL + (mid - gL) * 0.18 + UPV * 0.004, gL + (mid - gL) * 0.92 + UPV * 0.009, 0.085, toward_body))

prop_objs = []
for n, objs in pieces.items():
    inv = (defL if n == "Left" else defR).inverted()
    for o in objs:
        bake_modifiers(o)
        o.data.transform(o.matrix_world)  # ellipsoids carry their own location
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(inv)
        weigh(o, lambda co, b=n + "Hand": {b: 1.0})
        prop_objs.append(o)
for o in scene.objects:
    if o is not None:
        o.select_set(False)
for o in prop_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = prop_objs[0]
bpy.ops.object.join()
props = prop_objs[0]
props.name = "KnitProps"
props.data.name = "KnitProps"
props.parent = root
pm = props.modifiers.new("Armature", "ARMATURE")
pm.object = root
root.animation_data.action = None

bpy.context.view_layer.update()
print(CID.upper(), "faces:", len(mesh.data.polygons), "bones:", len(rig.bones), "groups:", len(mesh.vertex_groups))

os.makedirs(ASSETS, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BUILD, CID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(ASSETS, CID + ".glb"), export_format="GLB", export_apply=True,
                          export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                          export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
print(CID.upper(), "exported", os.path.join(ASSETS, CID + ".glb"))
for t in root.animation_data.nla_tracks:
    t.mute = True
for pb in root.pose.bones:  # back to the rest pose for the turntable
    pb.rotation_euler = (0, 0, 0)
    pb.location = (0, 0, 0)
bpy.context.view_layer.update()

# ----------------------------------------------------------------------------- turntable render
if RENDER_DIR:
    os.makedirs(RENDER_DIR, exist_ok=True)
    props.hide_render = True  # the turntable shows the rest pose; props only make sense while knitting
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except Exception:
            continue
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*lin((0.36, 0.36, 0.36)), 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    floor = link(bpy.data.objects.new("floor", bpy.data.meshes.new("floor")))
    fbm = bmesh.new()
    bmesh.ops.create_grid(fbm, x_segments=1, y_segments=1, size=4)
    fbm.to_mesh(floor.data)
    fbm.free()
    floor.data.materials.append(material("floor", (0.33, 0.33, 0.33), rough=0.9))
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.95
    cam.location = (0, -6, 0.9)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    key = link(bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN")))
    key.data.energy = 3.2
    key.rotation_euler = (math.radians(50), math.radians(-25), math.radians(-30))
    fill = link(bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")))
    fill.data.energy = 1.0
    fill.rotation_euler = (math.radians(65), math.radians(30), math.radians(150))
    scene.render.resolution_x = 360
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    frames = []
    for ang in range(0, 360, 50):
        root.rotation_euler = (0, 0, math.radians(ang))
        p = os.path.join(RENDER_DIR, "turn_%03d.png" % ang)
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        frames.append(p)
    root.rotation_euler = (0, 0, math.radians(20))
    cam.data.ortho_scale = 0.42
    cam.location = (0, -6, 1.63 * H)
    scene.render.resolution_x = 600
    scene.render.resolution_y = 600
    scene.render.filepath = os.path.join(RENDER_DIR, "portrait.png")
    bpy.ops.render.render(write_still=True)
    strips = []
    for p in frames:
        im = bpy.data.images.load(p)
        a = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)
        strips.append(a)
    strip = np.concatenate(strips, axis=1)
    out = bpy.data.images.new("strip", strip.shape[1], strip.shape[0], alpha=True)
    out.pixels.foreach_set(strip.ravel())
    out.filepath_raw = os.path.join(RENDER_DIR, "turntable.png")
    out.file_format = "PNG"
    out.save()
    print(CID.upper(), "turntable", out.filepath_raw)

    # pose sheet: each animation at two moments, seen from the front-left and the side
    if "--poses" in argv:
        cam.data.ortho_scale = 2.1
        scene.render.resolution_x = 300
        scene.render.resolution_y = 600
        shots = []
        for name, frames, fn in ANIMS:
            for fr in sorted({0, frames // 4}):
                root.animation_data.action = actions[name]
                scene.frame_set(fr)
                root.location.z = 0.40 if name.startswith("Sit") else 0.0
                for view, ang in (("front", 35), ("side", 90)):
                    root.rotation_euler = (0, 0, math.radians(ang))
                    cam.location = (0, -6, 1.0)
                    p = os.path.join(RENDER_DIR, "pose_%s_%02d_%s.png" % (name, fr, view))
                    scene.render.filepath = p
                    bpy.ops.render.render(write_still=True)
                    shots.append(p)
        root.animation_data.action = actions["SitKnit"]
        root.location.z = 0.40
        props.hide_render = False
        cam.data.ortho_scale = 0.8
        cam.location = (0, -6, 0.98)
        scene.render.resolution_x = 600
        scene.render.resolution_y = 600
        for view, ang in (("front", 25), ("side", 90), ("top3q", 15)):
            scene.frame_set(0)
            root.rotation_euler = (math.radians(30) if view == "top3q" else 0, 0, math.radians(ang))
            scene.render.filepath = os.path.join(RENDER_DIR, "knit_%s.png" % view)
            bpy.ops.render.render(write_still=True)
        root.rotation_euler = (0, 0, 0)
        scene.render.resolution_x = 300
        scene.render.resolution_y = 600
        rows = []
        for i in range(0, len(shots), 8):
            row = []
            for p in shots[i:i + 8]:
                im = bpy.data.images.load(p)
                row.append(np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4))
            while len(row) < 8:
                row.append(np.zeros_like(row[0]))
            rows.append(np.concatenate(row, axis=1))
        sheet = np.concatenate(rows[::-1], axis=0)
        out = bpy.data.images.new("poses", sheet.shape[1], sheet.shape[0], alpha=True)
        out.pixels.foreach_set(sheet.ravel())
        out.filepath_raw = os.path.join(RENDER_DIR, "poses.png")
        out.file_format = "PNG"
        out.save()
        print(CID.upper(), "poses", out.filepath_raw)
