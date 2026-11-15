"""Review renders of the lantern (out/lantern.glb, the file the game gets) in Cycles on the CPU.

    Blender -b --factory-startup --python-exit-code 1 --python art/world_assets/lantern/review.py -- <out dir> [clay] [night]

Writes into <out dir>:
- ref.png: the lantern from the reference's own camera (18 deg above, 18 deg round to its left, 2.5 m off);
- side_by_side.png: the reference beside that render, both cut to their outlines at the same height;
- overlay.png: the two outlines over each other (red: the reference only, cyan: the model only), and one
  FIDELITY line with the outlines' overlap (IoU) and the width difference in five height bands;
- front, q_left, q_right, side, back, top and low (close on the base and knob) .png, and sheet.png, the
  seven of them and the ref view on one picture; under.png, from below, on its own.
Name views after the folder (`top low`) to render only those and the ref view.
`clay` renders everything in plain clay instead (files end _clay; a face seen from behind shows red, so a
part built inside out is caught). `night` renders the colour views in the dark with only the lantern's
own emission (files end _night), to see what glows.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
a = sys.argv[sys.argv.index("--") + 1:]
out = a[0]
clay = "clay" in a[1:]
night = "night" in a[1:]
tag = "_clay" if clay else "_night" if night else ""
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "out", "lantern.glb"))
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 64
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
meshes = [o for o in sc.objects if o.type == "MESH"]
print("[review] objects:", [(o.name, [m.name for m in o.data.materials]) for o in meshes])
# Cycles draws both sides of every face; the game does not (the GLB's materials are single-sided, and the
# glass's far wall is a liner that faces inward). Make a face seen from behind invisible here too.
for m in bpy.data.materials:
    if m.use_nodes and m.use_backface_culling:
        nt = m.node_tree
        outn = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial")
        surf = outn.inputs["Surface"].links[0].from_socket
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mixs = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(geo.outputs["Backfacing"], mixs.inputs[0])
        nt.links.new(surf, mixs.inputs[1])
        nt.links.new(nt.nodes.new("ShaderNodeBsdfTransparent").outputs[0], mixs.inputs[2])
        nt.links.new(mixs.outputs[0], outn.inputs["Surface"])
if clay:
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.7
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    ins = {s.identifier: s for s in mix.inputs}
    ins["A_Color"].default_value = (0.6, 0.58, 0.55, 1)
    ins["B_Color"].default_value = (0.9, 0.02, 0.02, 1)
    nt.links.new(geo.outputs["Backfacing"], ins["Factor_Float"])
    nt.links.new([s for s in mix.outputs if s.identifier == "Result_Color"][0], b.inputs["Base Color"])
    for o in meshes:
        for i in range(len(o.material_slots)):
            o.material_slots[i].material = m
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.02, 0.025, 0.04, 1) if night else (0.82, 0.85, 0.9, 1)
bg.inputs[1].default_value = 0.3 if night else 0.5
if not night:
    for name, rot, energy in (("key", (52, 0, -40), 2.4), ("rim", (60, 0, 150), 1.2), ("fill", (70, 0, 60), 0.4)):
        s = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        sc.collection.objects.link(s)
        s.rotation_euler = [math.radians(v) for v in rot]
        s.data.energy = energy
        s.data.angle = math.radians(10)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam

# the model hangs below its origin: 0.285 m down to the base, 0.015 m up to the ring's top
MID = -0.135
VIEWS = {  # name: (azimuth, elevation, target z, distance, lens mm, width px, height px)
    "ref": (-108, 18, MID, 2.5, 165, 724, 724),
    "front": (-90, 8, MID, 2.5, 150, 520, 680),
    "q_left": (-55, 12, MID, 2.5, 150, 520, 680),
    "q_right": (-125, 12, MID, 2.5, 150, 520, 680),
    "side": (0, 8, MID, 2.5, 150, 520, 680),
    "back": (90, 10, MID, 2.5, 150, 520, 680),
    "top": (-100, 42, -0.07, 1.6, 150, 520, 680),
    "low": (-62, 14, -0.215, 1.3, 150, 520, 680),
    "under": (-90, -55, MID, 2.5, 150, 520, 680),
}
only = [v for v in a[1:] if v in VIEWS]
if only:                                   # a quick look at some views only: no sheet
    VIEWS = {n: VIEWS[n] for n in ["ref"] + [v for v in only if v != "ref"]}
for name, (az, el, tz, dist, lens, rx, ry) in VIEWS.items():
    t = Vector((0, 0, tz))
    d = Vector((math.cos(math.radians(az)) * math.cos(math.radians(el)), math.sin(math.radians(az)) * math.cos(math.radians(el)),
                math.sin(math.radians(el)))) * dist
    cam.location = t + d
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.sensor_fit = "VERTICAL"
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.render.filepath = os.path.join(out, name + tag + ".png")
    bpy.ops.render.render(write_still=True)


# --- pictures as arrays (top row first, sRGB values as stored) --------------------------------------

def load(path):
    im = bpy.data.images.load(path)
    wd, ht = im.size
    px = np.empty(wd * ht * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    bpy.data.images.remove(im)
    return px.reshape(ht, wd, 4)[::-1].copy()


def save(path, arr):
    ht, wd, _ = arr.shape
    im = bpy.data.images.new("out", wd, ht, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1], dtype=np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def on_white(arr):
    o = arr.copy()
    al = o[..., 3:4]
    o[..., :3] = o[..., :3] * al + (1.0 - al) if not night else o[..., :3] * al + 0.03 * (1.0 - al)
    o[..., 3] = 1.0
    return o


def resize(arr, ht, wd):
    ys = np.clip((np.arange(ht) + 0.5) * arr.shape[0] / ht, 0, arr.shape[0] - 1).astype(int)
    xs = np.clip((np.arange(wd) + 0.5) * arr.shape[1] / wd, 0, arr.shape[1] - 1).astype(int)
    return arr[ys][:, xs]


def crop_to(mask, arr):
    ys, xs = np.where(mask)
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# background seen through the lantern: inside the ring handle, and between each arm and the glass
HOLES = ((360, 90), (263, 335), (458, 335), (233, 482), (247, 500))


def reference_cutout():
    """The reference with its white background made transparent: what is near white and reaches the
    border is background; white enclosed by the lantern (the flame, highlights) stays."""
    ref = load(os.path.join(HERE, "ref", "lantern.png"))
    near = (1.0 - ref[..., :3].min(-1)) < 0.055
    bgm = np.zeros(near.shape, bool)
    bgm[0, :], bgm[-1, :], bgm[:, 0], bgm[:, -1] = near[0, :], near[-1, :], near[:, 0], near[:, -1]
    for x, y in HOLES:
        bgm[y, x] = near[y, x]
    while True:
        grow = bgm.copy()
        grow[1:, :] |= bgm[:-1, :]
        grow[:-1, :] |= bgm[1:, :]
        grow[:, 1:] |= bgm[:, :-1]
        grow[:, :-1] |= bgm[:, 1:]
        grow &= near
        if (grow == bgm).all():
            break
        bgm = grow
    ref[..., 3] = (~bgm).astype(np.float32)
    return ref


shots = {n: load(os.path.join(out, n + tag + ".png")) for n in VIEWS}
ref = reference_cutout()
rmask = ref[..., 3] > 0.5
mine = shots["ref"]
mmask = mine[..., 3] > 0.5
rc, rm = crop_to(rmask, ref), crop_to(rmask, rmask)
mc, mm = crop_to(mmask, mine), crop_to(mmask, mmask)
H = rc.shape[0]
scale = H / mc.shape[0]
mc = resize(mc, H, int(round(mc.shape[1] * scale)))
mm = resize(mm, H, mc.shape[1])
W = max(rc.shape[1], mc.shape[1]) + 40


def centred(arr, wd):
    """Pads to `wd`, keeping the picture's own middle column in the middle."""
    o = np.zeros((arr.shape[0], wd) + arr.shape[2:], arr.dtype)
    x0 = (wd - arr.shape[1]) // 2
    o[:, x0:x0 + arr.shape[1]] = arr
    return o


rm_p, mm_p = centred(rm, W), centred(mm, W)
iou = float((rm_p & mm_p).sum() / max(1, (rm_p | mm_p).sum()))
bands = []
for k in range(5):
    y0, y1 = H * k // 5, H * (k + 1) // 5
    wr, wm = rm_p[y0:y1].sum(1).mean(), mm_p[y0:y1].sum(1).mean()
    bands.append(round(float((wm - wr) / max(wr, 1.0)) * 100, 1))
fid = {"view": "ref", "silhouette_iou": round(iou, 4), "width_diff_pct_top_to_bottom": bands,
       "model_px_wide": int(mc.shape[1]), "reference_px_wide": int(rc.shape[1]), "px_tall": int(H)}
print("FIDELITY " + json.dumps(fid))
if not clay and not night:
    with open(os.path.join(out, "fidelity.json"), "w", encoding="utf-8") as f:
        json.dump(fid, f, indent=2)
ov = np.ones((H, W, 4), np.float32)
ov[rm_p & mm_p, :3] = 0.82
ov[rm_p & ~mm_p, :3] = (0.9, 0.15, 0.15)
ov[~rm_p & mm_p, :3] = (0.1, 0.75, 0.85)
save(os.path.join(out, "overlay" + tag + ".png"), ov)
gap = np.ones((H, 24, 4), np.float32)
save(os.path.join(out, "side_by_side" + tag + ".png"),
     np.concatenate([on_white(centred(rc, W)), gap, on_white(centred(mc, W))], axis=1))

order = [n for n in ["ref", "front", "q_left", "q_right", "side", "back", "top", "low"] if n in VIEWS]
th, tw = 680, 520
tiles = []
for n in order:
    s = shots[n]
    s = resize(s, th, int(round(s.shape[1] * th / s.shape[0])))
    if s.shape[1] > tw:
        x0 = (s.shape[1] - tw) // 2
        s = s[:, x0:x0 + tw]
    tiles.append(on_white(centred(s, tw)))
rows = [np.concatenate(tiles[i:i + 4], axis=1) for i in range(0, len(tiles), 4) if len(tiles[i:i + 4]) == min(4, len(tiles))]
save(os.path.join(out, "sheet" + tag + ".png"), np.concatenate(rows, axis=0))
print("[review] wrote", out, "sheet%s.png: %s" % (tag, ", ".join(order)))
