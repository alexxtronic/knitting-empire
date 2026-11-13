"""The gold coin (Alex's reference, ref/reference.png): a thick gold coin with a broad rounded rim, a
fine groove inside it, a recessed field and a chunky embossed dollar sign, the edge reeded. Built by
script, rendered in Cycles on a transparent background, and cut down to the game's coin picture,
assets/icons/coin.png (the coin chip in the HUD and the "+N" pop-up whenever she earns coins).

  Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/coin/build.py [-- --samples N --size PX]

Writes out/coin.blend, out/coin.glb (for kiln's review sheets), out/coin_render.png (the full render)
and assets/icons/coin.png (256 px). Then import (Godot writes the .import file).

Front is -Y (kiln), the coin's axis along Y, 1 unit = 1 m on a coin 2 m across: it is only ever a
picture, so it's built at a size the bevels are easy to reason about.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "out")
ICON = os.path.join(ROOT, "assets", "icons", "coin.png")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default):
    return type(default)(args[args.index(name) + 1]) if name in args else default


SAMPLES = opt("--samples", 96)
SIZE = opt("--size", 1024)
ICON_PX = opt("--icon", 256)

R = 1.0  # radius
H = 0.17  # half the thickness at the rim's crown
SEGS = 720  # round the coin
REEDS = 120  # ridges on the edge
REED_DEPTH = 0.014
FIELD_R = 0.80  # the recessed field, where the dollar sign stands
FIELD_Y = 0.132  # its depth from the middle (the rim's crown is at H)

# Palette, sampled from the reference (sRGB): field #e9a21e, lit rim #ffe07a, shade #b86f05
GOLD_FIELD = (0.93, 0.56, 0.06)
GOLD_RIM = (1.0, 0.66, 0.13)


def srgb_to_lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def arc(cx, cy, rad, a0, a1, n):
    """Points on a circle (r, y), angles in degrees."""
    return [(cx + rad * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + rad * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def front_profile():
    """(r, y) from the centre of the front face out to the middle of the edge; y negative = front.
    The field, a fine raised bead, a groove, the broad rounded rim, and the bevel onto the edge."""
    p = []
    for i in range(0, 17):  # field, flat
        p.append((FIELD_R * i / 16, -FIELD_Y))
    # a soft step up into a thin bead, then down into the groove
    p += arc(FIELD_R + 0.016, -FIELD_Y - 0.0, 0.016, 180, 90, 4)[1:]
    p += [(FIELD_R + 0.032, -FIELD_Y - 0.010)]
    p += arc(FIELD_R + 0.046, -FIELD_Y + 0.004, 0.014, 180, 360, 6)[1:]  # the groove
    # the rim rises from the groove in a broad rounded crown, then bevels onto the edge
    p += [(0.875, -0.150), (0.89, -0.161)]
    p += arc(0.925, -H + 0.035, 0.035, 225, 270, 4)
    p += [(0.95, -H)]
    p += arc(0.95, -H + 0.05, 0.05, 270, 360, 8)[1:]  # round over onto the edge at r = 1
    edge_top = -H + 0.05
    for i in range(1, 13):  # down the edge to the middle
        p.append((R, edge_top * (1 - i / 12)))
    return p


def build_coin():
    prof = front_profile()
    prof += [(r, -y) for r, y in reversed(prof[:-1])]  # the back mirrors the front
    bm = bmesh.new()
    verts = [bm.verts.new((r, y, 0.0)) for r, y in prof]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 1, 0), angle=math.tau, steps=SEGS,
                   use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    edge_y = H - 0.05 - 0.008
    for v in bm.verts:
        r = math.hypot(v.co.x, v.co.z)
        if r > R - 0.002 and abs(v.co.y) < edge_y:
            a = math.atan2(v.co.z, v.co.x)
            ridge = 0.5 + 0.5 * math.tanh(3.0 * math.cos(REEDS * a))  # square-ish ridges, rounded
            fade = min(1.0, (edge_y - abs(v.co.y)) / 0.02)
            s = (R - REED_DEPTH * (1 - ridge) * fade) / r
            v.co.x *= s
            v.co.z *= s
    me = bpy.data.meshes.new("SM_Coin")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("SM_Coin", me)
    bpy.context.collection.objects.link(ob)
    for f in me.polygons:
        f.use_smooth = True
    # the field (front and back) is satin, everything else polished
    sat = gold_material("M_Gold_Satin", GOLD_FIELD, 0.36)
    pol = gold_material("M_Gold_Polished", GOLD_RIM, 0.2)
    me.materials.append(pol)
    me.materials.append(sat)
    for f in me.polygons:
        c = f.center
        if math.hypot(c.x, c.z) < FIELD_R - 0.005:
            f.material_index = 1
    return ob


def build_dollar():
    cu = bpy.data.curves.new("Dollar", "FONT")
    cu.font = bpy.data.fonts.load(FONT)
    cu.body = "$"
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = 1.62
    cu.extrude = 0.03
    cu.bevel_depth = 0.028
    cu.bevel_resolution = 5
    cu.resolution_u = 24
    ob = bpy.data.objects.new("Dollar", cu)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    ob.name = "SM_Dollar"
    me = ob.data
    # centre it on its own bounds (the font's centre sits a little off the glyph's)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    off = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, 0))
    h = max(ys) - min(ys)
    me.transform(Matrix.Translation(-off))
    me.transform(Matrix.Scale(1.36 / h, 4))  # 0.68 of the diameter, as in the reference
    # face it to -Y and sink its back into the field
    me.transform(Matrix.Rotation(math.radians(90), 4, "X"))
    me.transform(Matrix.Translation((0, -FIELD_Y - 0.02, 0)))
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    me.materials.append(bpy.data.materials["M_Gold_Polished"])
    # the back gets one too, so the coin is whole from any side
    back = ob.copy()
    back.data = me.copy()
    back.data.transform(Matrix.Rotation(math.radians(180), 4, "Z"))
    back.name = "SM_Dollar_Back"
    bpy.context.collection.objects.link(back)
    return ob, back


def gold_material(name, srgb, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb_to_lin(srgb), 1.0)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    if "Specular Tint" in b.inputs and b.inputs["Specular Tint"].type == "RGBA":
        b.inputs["Specular Tint"].default_value = (*srgb_to_lin((1.0, 0.85, 0.5)), 1.0)
    return m


def scene_setup(coin_parts):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.device = "CPU"
    sc.render.film_transparent = True
    sc.render.resolution_x = SIZE
    sc.render.resolution_y = SIZE
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    # studio reflections: Blender's own studio HDRI, unseen by the camera
    w = bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    hdri = [p for p in [os.path.join(os.path.dirname(bpy.app.binary_path), "..", "Resources",
                                     "%d.%d" % bpy.app.version[:2], "datafiles", "studiolights", "world", "studio.exr")]
            if os.path.exists(p)]
    if hdri:
        env.image = bpy.data.images.load(hdri[0])
        nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.9
    # Alex chose this look (2026-11-13): deep mirror-polished gold reflecting the studio, over a
    # brighter, softer gold that read closer to the reference but flatter
    # a big soft key from the upper left, a warm fill from the right, a rim from behind
    for name, loc, energy, size, col in [
        ("Key", (-4.0, -5.0, 5.0), 900, 4.0, (1.0, 0.97, 0.9)),
        ("Fill", (5.0, -3.5, 0.5), 260, 5.0, (1.0, 0.9, 0.75)),
        ("Rim", (2.0, 4.0, 3.0), 400, 3.0, (1.0, 0.95, 0.85)),
    ]:
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        sc.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    # the coin turned so its right edge shows, the camera a touch above
    pivot = bpy.data.objects.new("Coin", None)
    sc.collection.objects.link(pivot)
    for o in coin_parts:
        o.parent = pivot
    pivot.rotation_euler = (math.radians(-4), 0, math.radians(-26))
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 120
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = (0, -8.3, 0.35)
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return pivot


def try_gpu():
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        if any(d.type == "METAL" for d in prefs.devices):
            for d in prefs.devices:
                d.use = True
            bpy.context.scene.cycles.device = "GPU"
            return "GPU"
    except Exception:
        pass
    return "CPU"


def crop_icon(src, dst, px):
    """Tight crop on the coin's alpha with a small margin, squared, resized to px."""
    img = bpy.data.images.load(src)
    w, h = img.size
    pix = list(img.pixels)
    xs, ys = [], []
    for y in range(0, h, 2):
        row = y * w * 4
        for x in range(0, w, 2):
            if pix[row + x * 4 + 3] > 0.02:
                xs.append(x)
                ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    side = int(max(x1 - x0, y1 - y0) * 1.06) + 4
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sx, sy = cx - side // 2, cy - side // 2
    out = [0.0] * (side * side * 4)
    for y in range(side):
        yy = sy + y
        if not 0 <= yy < h:
            continue
        for x in range(side):
            xx = sx + x
            if 0 <= xx < w:
                i = (yy * w + xx) * 4
                o = (y * side + x) * 4
                out[o:o + 4] = pix[i:i + 4]
    crop = bpy.data.images.new("icon", side, side, alpha=True)
    crop.pixels = out
    crop.scale(px, px)
    crop.filepath_raw = dst
    crop.file_format = "PNG"
    crop.save()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    os.makedirs(OUT, exist_ok=True)
    coin = build_coin()
    d1, d2 = build_dollar()
    parts = [coin, d1, d2]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts)
    print("SCENE", [o.name for o in bpy.context.scene.objects], "triangles", tris)
    allv = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    print("SIZE x %.3f y %.3f z %.3f" % tuple(max(v[i] for v in allv) - min(v[i] for v in allv) for i in range(3)))
    # the review GLB: the coin standing on its edge, upright, as made (no render turn)
    for o in bpy.context.scene.objects:
        o.select_set(o in parts)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "coin.glb"), use_selection=True,
                              export_draco_mesh_compression_enable=False, export_apply=False)
    scene_setup(parts)
    print("DEVICE", try_gpu() if "--cpu" not in args else "CPU")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "coin.blend"))
    render = os.path.join(OUT, "coin_render.png")
    bpy.context.scene.render.filepath = render
    bpy.ops.render.render(write_still=True)
    if "--no-icon" not in args:
        crop_icon(render, ICON, ICON_PX)
        print("ICON", ICON)
    print("DONE")


main()
