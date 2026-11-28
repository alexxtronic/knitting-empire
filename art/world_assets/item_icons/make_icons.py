"""The bag's pictures for everything she can carry that isn't yarn or a tool (Alex, 2026-11-28:
"make anything we can hold in our bag have a corresponding icon"). Same studio as the yarn icons
(yarn/make_icons.py): Cycles, a transparent background, a key, fill and rim light, cropped square
to 256 px into assets/icons/<id>.png, which Hud.Slot.icon() picks up by item id.

Where the game has a model of the thing, the icon is that model or the builder that made it: the
turnip and pumpkin from crops/build.py, the croissant from bakery_stall/build.py, the needles from
yarn/build.py, and lantern.glb, hay_bale.glb and the three leaf GLBs. The rest (wood, the gate, Gran's
note, the seed packets, a sweater, the waders, the tent) are built here from kelib and craftlib.

  Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/item_icons/make_icons.py [-- --size PX --samples N --only wood,tent]

Textures and full-size renders go to out/ beside this script (not committed).
"""
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
WA = os.path.dirname(HERE)
sys.path.insert(0, WA)
import kelib as K  # noqa: E402
import craftlib as CL  # noqa: E402


def opt(name, default):
    a = sys.argv
    return type(default)(a[a.index(name) + 1]) if name in a else default


SIZE = opt("--size", 256)
SAMPLES = opt("--samples", 96)
ONLY = opt("--only", "").split(",") if "--only" in sys.argv else []
OUT = os.path.join(K.PROJECT, "assets", "icons")
PROPS = os.path.join(K.PROJECT, "assets", "props")
TEX = os.path.join(HERE, "out", "tex")
os.makedirs(TEX, exist_ok=True)


def borrow(rel, cut):
    """Another build script's functions, without its build-everything tail, its textures sent to TEX."""
    path = os.path.join(WA, rel)
    src = open(path).read().split(cut)[0]
    ns = {"__file__": path, "__name__": "borrowed"}
    exec(compile(src, rel, "exec"), ns)
    ns["TEX"] = TEX
    return ns


CROPS = borrow("crops/build.py", "def build(crop, stage):")
BAKERY = borrow("bakery_stall/build.py", "# --- the stall")
YARN = borrow("yarn/build.py", "def build(name):")

with open(os.path.join(K.PROJECT, "data", "explore.json"), encoding="utf-8") as f:
    NEEDLES = {k: v["color"] for k, v in json.load(f)["needles"].items()}


def glb(name, loc=(0, 0, 0), yaw=0.0, scale=1.0, tilt=(0.0, 0.0)):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new(name + "_root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    root.location = loc
    root.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw))
    root.scale = (scale, scale, scale)
    return root


def wood_mats(tag, base="#b77a44", light="#d69a5e", dark="#7d4c26"):
    i, n = CL.plank_maps(tag + "_wood", TEX, base=base, light=light, dark=dark, knots=1)
    side = K.textured(tag + "_wood", i, rough=0.75, normal=n, normal_strength=0.7)
    i, n = CL.endgrain_maps(tag + "_end", TEX)
    return side, K.textured(tag + "_end", i, rough=0.8, normal=n, normal_strength=0.6)


# --- the things ------------------------------------------------------------------------------------

def turnip():
    m = CROPS["materials"]()
    CROPS["turnip"](0.0, 0.0, 3, m, random.Random(3))


def pumpkin():
    m = CROPS["materials"]()
    CROPS["pumpkin_fruit"](0.0, 0.0, 0.15, 0.2, m["pumpkin"], m, random.Random(5), stem=1.1, hook_yaw=40)
    CL.palm_leaf("pleaf", (0.1, 0.12, 0.03), 0.1, m["pleaf"], yaw=40, pitch=25)


def seed_packet(tag, paper, band, crop):
    """A paper seed packet standing up, its top folded over, the crop on its front and a few seeds
    spilt at its foot, so it reads apart from the crop itself."""
    W, H, T = 0.13, 0.17, 0.012
    tilt = (-8, 0, -12)
    pm = K.plain(tag + "_paper", paper, rough=0.8)
    bm = K.plain(tag + "_band", band, rough=0.75)
    K.box("packet", (W, T, H), (0, 0, H / 2), pm, bevel=0.004, rot=tilt)
    K.box("flap", (W * 1.01, T * 1.3, 0.028), (0, 0, H - 0.016), bm, bevel=0.004, rot=tilt)
    K.box("band", (W * 1.01, T * 1.15, 0.03), (0, 0, 0.03), bm, bevel=0.003, rot=tilt)
    rng = random.Random(7)
    m = CROPS["materials"]()
    if crop == "turnip":
        CROPS["turnip_bulb"](0.0, -0.035, 0.085, 0.032, m, rng)
        for k in range(4):
            CL.strap_leaf("tleaf", (0.0, -0.035, 0.115), 90 * k + 20, 0.07, 0.025, m["tleaf"], petiole=0.3, lift=70,
                          droop=20, ns=6, petiole_mat=m["tstalk"], petiole_r=0.003)
        seed = K.plain("turnip_seed", "#4a2e22", rough=0.5)
        for k in range(5):
            K.ball("seed", 0.006, (rng.uniform(-0.045, 0.045), rng.uniform(-0.05, -0.03), 0.006), seed, u=8, v=6)
    else:
        CROPS["pumpkin_fruit"](0.0, -0.035, 0.05, 0.065, m["pumpkin"], m, rng, stem=0.8, hook_yaw=60)
        for o in bpy.context.scene.objects:  # pumpkin_fruit sinks it into the furrow: lift it onto the packet
            if o.name.startswith(("pumpkin", "stem")) and o.location.z < 0.02:
                o.location.z += 0.05
        seed = K.plain("pumpkin_seed", "#f3e6c4", rough=0.45)
        for k in range(4):
            ob = K.ball("seed", 0.012, (rng.uniform(-0.05, 0.05), rng.uniform(-0.055, -0.035), 0.004), seed,
                        scale=(1.0, 0.62, 0.3), u=12, v=8)
            ob.rotation_euler = (0, 0, rng.uniform(0, 3.14))


def turnip_seeds():
    seed_packet("tseeds", "#efe2f4", "#9b6cc0", "turnip")


def pumpkin_seeds():
    seed_packet("pseeds", "#fbefd8", "#e0761e", "pumpkin")


def wood():
    """Three split logs stacked, bark round them and the end grain showing."""
    i, n = CL.wood_maps("bark", TEX, base="#6e4a2c", light="#8e6640", dark="#45301c")
    bark = K.textured("bark", i, rough=0.85, normal=n, normal_strength=1.0)
    _, end = wood_mats("logs")
    L, r = 0.26, 0.045
    for x, z in ((-0.047, r), (0.047, r), (0.0, r * 2.65)):
        K.cyl("log", r, r, L, (x, 0, z), bark, verts=14, rot=(90, 0, 0))
        for s in (-1, 1):
            K.cyl("end", r * 0.93, r * 0.93, 0.004, (x, s * L / 2, z), end, verts=14, rot=(90, 0, 0))
    pile = bpy.data.objects.new("pile", None)
    bpy.context.scene.collection.objects.link(pile)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.parent is None:
            o.parent = pile
    pile.rotation_euler = (0, 0, math.radians(55))


def hay():
    glb("hay_bale", yaw=30)


def leaves():
    glb("leaf_red", (-0.05, 0.0, 0.0), yaw=-30, tilt=(30, 0))
    glb("leaf_yellow", (0.05, 0.01, 0.0), yaw=25, tilt=(30, 0))
    glb("leaf_green", (0.0, -0.03, 0.02), yaw=0, tilt=(35, 0))


def gate():
    """A farm gate: two rails, a brace corner to corner, hinge straps and a latch."""
    side, end = wood_mats("gate", base="#a87448", light="#c99160", dark="#6f4628")
    iron = K.plain("gate_iron", "#3a3a3e", rough=0.5)
    W, H = 0.4, 0.26
    for x in (-W / 2, W / 2):
        K.box("stile", (0.03, 0.03, H), (x, 0, H / 2), side, bevel=0.004)
    for z in (0.04, H / 2, H - 0.03):
        K.box("rail", (W, 0.022, 0.03), (0, 0, z), side, bevel=0.004)
    ang = math.degrees(math.atan2(H - 0.07, W))
    K.box("brace", (math.hypot(W, H - 0.07), 0.02, 0.026), (0, -0.004, H / 2 + 0.005), side, bevel=0.003, rot=(0, -ang, 0))
    for z in (0.04, H - 0.03):
        K.box("hinge", (0.11, 0.026, 0.012), (-W / 2 + 0.045, -0.002, z), iron, bevel=0.002)
    K.box("latch", (0.05, 0.03, 0.014), (W / 2 - 0.01, -0.006, H / 2), iron, bevel=0.002)


def gran_note():
    """Gran's note: a folded card of cream paper, written on in blue ink, a red heart at the end."""
    paper = K.plain("note_paper", "#f4ead2", rough=0.85)
    ink = K.plain("note_ink", "#2f4a86", rough=0.6)
    heart = K.plain("note_heart", "#c8323a", rough=0.5)
    W, H = 0.2, 0.15
    K.box("page", (W, 0.003, H), (0, 0, 0), paper, bevel=0.001)
    rng = random.Random(11)
    z = H / 2 - 0.03
    for k in range(5):
        ln = W * (0.76 if k < 4 else 0.42) * rng.uniform(0.9, 1.0)
        K.box("line", (ln, 0.002, 0.0055), (-W / 2 + 0.02 + ln / 2, -0.003, z), ink, bevel=0.0)
        z -= 0.022
    K.text("heart", "♥", 0.03, (W * 0.22, -0.003, z + 0.022), (90, 0, 0), heart, depth=0.001)
    root = bpy.data.objects.new("note", None)
    bpy.context.scene.collection.objects.link(root)
    for o in list(bpy.context.scene.objects):
        if o.type in ("MESH", "FONT") and o.parent is None:
            o.parent = root
    root.rotation_euler = (math.radians(-30), 0, math.radians(-8))
    root.location = (0, 0, H / 2)


def lantern():
    glb("lantern", yaw=20)


def pastry():
    i = BAKERY["croissant_maps"]()
    mat = K.textured("croissant", i, rough=0.42)
    BAKERY["croissant"]((0, 0, 0.03), 180, mat, size=2.0, tilt=-50)


def sweater():
    """A sweater laid out flat and tipped toward us: red knit, cream yoke stripe, ribbed cuffs and hem."""
    i, n = CL.yarn_maps("sweater_red", TEX, "#c8392c")
    knit = K.textured("sweater_red", i, rough=0.95, normal=n, normal_strength=0.9)
    i, n = CL.yarn_maps("sweater_cream", TEX, "#f1e3c2")
    cream = K.textured("sweater_cream", i, rough=0.95, normal=n, normal_strength=0.9)
    rib = K.plain("sweater_rib", "#9e2a20", rough=0.95)
    body = [(-0.1, -0.12), (0.1, -0.12), (0.1, 0.05), (0.2, -0.04), (0.235, 0.0), (0.12, 0.12), (0.045, 0.13),
            (0.0, 0.11), (-0.045, 0.13), (-0.12, 0.12), (-0.235, 0.0), (-0.2, -0.04), (-0.1, 0.05)]
    K.extrude_xz("body", body, -0.02, 0.02, knit, bevel=0.012)
    K.box("yoke", (0.2, 0.046, 0.026), (0, 0, 0.068), cream, bevel=0.008)
    K.box("hem", (0.206, 0.046, 0.026), (0, 0, -0.11), rib, bevel=0.008)
    K.box("collar", (0.1, 0.046, 0.018), (0, 0, 0.118), rib, bevel=0.007)
    for s in (-1, 1):
        K.box("cuff", (0.05, 0.046, 0.024), (s * 0.214, 0, -0.022), rib, bevel=0.008, rot=(0, s * 40, 0))
    root = bpy.data.objects.new("sweater", None)
    bpy.context.scene.collection.objects.link(root)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.parent is None:
            o.parent = root
    root.rotation_euler = (math.radians(-25), 0, 0)
    root.location = (0, 0, 0.13)


def waders():
    """Chest waders: olive rubber bib and legs, black boots, braces over the top."""
    rub = K.plain("waders_rubber", "#5d6a3a", rough=0.45)
    boot = K.plain("waders_boot", "#24231f", rough=0.4)
    strap = K.plain("waders_strap", "#2c3a5a", rough=0.7)
    buckle = K.plain("waders_buckle", "#b9b4a6", rough=0.3)
    K.box("bib", (0.15, 0.07, 0.13), (0, 0, 0.36), rub, bevel=0.03)
    K.box("seat", (0.16, 0.08, 0.06), (0, 0, 0.29), rub, bevel=0.03)
    for s in (-1, 1):
        K.cyl("leg", 0.034, 0.042, 0.2, (s * 0.042, 0, 0.17), rub, verts=16, rot=(0, s * -3, 0))
        K.cyl("boot", 0.036, 0.034, 0.075, (s * 0.046, 0, 0.04), boot, verts=16)
        K.ball("toe", 0.036, (s * 0.046, -0.032, 0.02), boot, scale=(1.0, 1.4, 0.6), u=14, v=8)
        K.box("brace", (0.018, 0.012, 0.12), (s * 0.05, -0.034, 0.47), strap, bevel=0.003, rot=(0, s * -12, 0))
        K.box("buckle", (0.026, 0.016, 0.02), (s * 0.05, -0.04, 0.42), buckle, bevel=0.003)


def tent():
    """A little canvas ridge tent: pitched sides, a door flap tied back, a pole at each end, pegs and guys."""
    i, n = CL.cloth_maps("tent_canvas", TEX, "#c7a66c")
    canvas = K.textured("tent_canvas", i, rough=0.9, normal=n, normal_strength=0.6)
    dark = K.plain("tent_door", "#4a3a26", rough=0.9)
    pole = K.plain("tent_pole", "#7a5634", rough=0.7)
    rope = K.plain("tent_rope", "#e6dcc4", rough=0.8)
    W, H, D = 0.34, 0.24, 0.34
    K.extrude_xz("canvas", [(-W / 2, 0), (W / 2, 0), (0, H)], -D / 2, D / 2, canvas, bevel=0.006)
    K.extrude_xz("door", [(-W * 0.22, 0), (W * 0.22, 0), (0, H * 0.78)], -D / 2 - 0.004, -D / 2 + 0.001, dark, bevel=0.0)
    for y in (-D / 2 - 0.006, D / 2 + 0.006):
        K.cyl("pole", 0.006, 0.006, H + 0.05, (0, y, (H + 0.05) / 2), pole, verts=8)
    for x, y in ((-W / 2 - 0.08, -D / 2 + 0.03), (W / 2 + 0.08, -D / 2 + 0.03)):
        top = Vector((0, -D / 2 - 0.006, H + 0.02))
        CL.tube("guy", [top, Vector((x, y, 0.005))], [0.0025, 0.0025], rope, sides=5)
        K.cyl("peg", 0.004, 0.002, 0.03, (x, y, 0.01), pole, verts=6)


def needles_for(item):
    def build():
        mat = K.plain(item, NEEDLES[item], rough=0.4 if item != "bone_needles" else 0.55)
        YARN["needle"](Vector((-0.11, -0.08, 0.012)), (1, 0.62, 0.0), mat, L=0.26)
        YARN["needle"](Vector((0.11, -0.08, 0.012)), (-1, 0.62, 0.045), mat, L=0.26)
    return build


ITEMS = {
    "turnip": turnip, "pumpkin": pumpkin, "turnip_seeds": turnip_seeds, "pumpkin_seeds": pumpkin_seeds,
    "wood": wood, "hay": hay, "leaves": leaves, "gate": gate, "gran_note": gran_note, "lantern": lantern,
    "pastry": pastry, "sweater": sweater, "waders": waders, "tent": tent,
}
for nid in NEEDLES:
    ITEMS[nid] = needles_for(nid)


# --- the studio ------------------------------------------------------------------------------------

def bounds():
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o.type not in ("MESH", "FONT"):
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return (lo + hi) / 2, (hi - lo).length / 2


def render(item):
    K.reset("icon_" + item)
    ITEMS[item]()
    c, r = bounds()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = SIZE * 2
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.9, 0.92, 1.0, 1.0)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    k = r / 0.1  # the yarn studio was set for a ball 0.1 m across
    for name, loc, energy, size, col in [("Key", (-0.5, -0.7, 0.6), 7, 0.5, (1.0, 0.96, 0.88)),
                                         ("Fill", (0.6, -0.4, 0.2), 2, 0.6, (0.9, 0.93, 1.0)),
                                         ("Rim", (0.3, 0.6, 0.5), 3, 0.4, (1.0, 0.95, 0.9))]:
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.size, ld.color = energy * k * k, size * k, col
        lo = bpy.data.objects.new(name, ld)
        lo.location = c + Vector(loc) * k
        sc.collection.objects.link(lo)
        lo.rotation_euler = (c - lo.location).to_track_quat("-Z", "Y").to_euler()
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 90
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    fov = 2 * math.atan(18 / cd.lens)
    cam.location = c + Vector((0.0, -0.95, 0.52)).normalized() * (r / math.sin(fov / 2) * 1.05)
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.clip_start, cd.clip_end = 0.01, 100
    sc.camera = cam
    tmp = os.path.join(HERE, "out", "icon_%s_full.png" % item)
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    return tmp


def crop(src, dst):
    im = bpy.data.images.load(src)
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.where(px[:, :, 3] > 0.03)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = int(max(x1 - x0, y1 - y0) * 1.08) + 4
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sq = np.zeros((side, side, 4), dtype=np.float32)
    ox, oy = cx - side // 2, cy - side // 2
    for yy in range(side):
        sy = yy + oy
        if 0 <= sy < h:
            xa, xb = max(0, ox), min(w, ox + side)
            sq[yy, xa - ox:xb - ox] = px[sy, xa:xb]
    out = bpy.data.images.new("icon", side, side, alpha=True)
    out.pixels = sq.ravel().tolist()
    out.scale(SIZE, SIZE)
    out.filepath_raw = dst
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    bpy.data.images.remove(im)


for item in ITEMS:
    if ONLY and item not in ONLY:
        continue
    full = render(item)
    crop(full, os.path.join(OUT, item + ".png"))
    print("ICON", item)
