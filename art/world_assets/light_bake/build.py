"""Cycles light bake for the world props: soft sky light, contact shadows and bounce light, path traced
in Cycles and baked into one light atlas per prop, which the game reads as the prop's ambient occlusion.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/light_bake/build.py -- <id> [...]
    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/light_bake/build.py -- all

It works on the finished GLB in assets/props/ (whatever made it: a build.py here, Tripo, Codex) and
writes it back in place, so run it again after rebuilding a prop. Then import (see AGENTS.md).

What the bake holds, and why only this: the game's sun moves (the day/night cycle) and Alex moves
props around in the world editor, so the sun's own shadows and the light between props are drawn
live by Godot. What never changes is how much of the sky each spot on a prop can see once the prop
itself is in the way: the dark under a bench seat, the creases of a sofa, the foot of a wall, the
inside of a barrel, and the light that bounces back off the prop's own parts into those places.
That is the bake. It moves with the prop.

How: every surface is lit by a uniform white sky. A ray that leaves the baked spot and meets the
prop (or the ground under it) within REACH metres stops and bounces; anything further away lets the
ray through to the sky. So an open surface of any slope bakes to 1.0, and only what is close by
darkens it: contact shadows with the bounce light that fills them, not a blanket of black inside a
closed building (the shops and the barn open up when Nora walks in). Cycles bakes the light (the
diffuse pass, light only, no colour) onto a second UV map, LightUV, packed for the whole prop into
one atlas. The GLB's material gets the atlas as its glTF occlusion texture on that UV; Godot imports
it as the material's ambient occlusion on UV2 (scripts/lighting.gd checks it), so it darkens the
sky light and the bounce light SSIL adds, and the sun only slightly (Lighting.AO_SUN).

Running it twice is safe: a prop that already has LightUV keeps it and is baked again.
LIGHT_SAMPLES (default 256) and LIGHT_DENSITY (atlas pixels per metre, default 110) can be set.
"""
import json
import math
import os
import sys
import time

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PROPS_DIR = os.path.join(ROOT, "assets", "props")
OUT = os.path.join(HERE, "out")
REVIEW = os.path.join(HERE, "review")

SAMPLES = int(os.environ.get("LIGHT_SAMPLES", 256))
DENSITY = float(os.environ.get("LIGHT_DENSITY", 110))
BOUNCE_ALBEDO = 0.5  # how much light the prop's own surfaces send on (grey: the colour bounce is SSIL's, live)
GROUND_ALBEDO = 0.32  # grass and dirt

# id: (reach in metres, stands on the ground). Static world pieces only: the trees, bushes, grass,
# flowers and crops have their own foliage shaders, and the characters, the sheep and the tools move.
PROPS = {
    "armchair": (0.8, True),
    "bakery_counter": (0.8, True),
    "bakery_stall": (1.0, True),
    "barn": (1.6, True),
    "bench_park": (0.8, True),
    "bench_park_short": (0.8, True),
    "bookshelf": (0.7, True),
    "bread_rack": (0.7, True),
    "brick_oven": (0.8, True),
    "building_bakery": (1.4, True),
    "building_cafe": (1.4, True),
    "building_homegoods": (1.4, True),
    "building_mayor": (1.4, True),
    "building_office": (1.4, True),
    "building_shop": (1.4, True),
    "chalkboard_sign": (0.6, True),
    "coffee_table": (0.7, True),
    "daisy_crate": (0.6, True),
    "dining_table": (0.8, True),
    "fence_post": (0.6, True),
    "fence_rails": (0.6, True),
    "fence_section": (0.6, True),
    "filing_cabinet": (0.6, True),
    "fireplace": (0.8, True),
    "flour_sacks": (0.6, True),
    "gran_bed": (0.8, True),
    "hay_bale": (0.6, True),
    "kitchen": (0.8, True),
    "lamp": (0.5, True),
    "lamp_post": (0.6, True),
    "market_stall": (1.0, True),
    "milk_churn": (0.5, True),
    "office_desk": (0.8, True),
    "plaza_fountain": (1.0, True),
    "rocking_chair": (0.8, True),
    "rug_red": (0.4, True),
    "scarecrow": (0.6, True),
    "shop_counter": (0.8, True),
    "sofa": (0.8, True),
    "spinning_wheel": (0.6, True),
    "sweater_rack": (0.7, True),
    "trash_can": (0.6, True),
    "wardrobe": (0.7, True),
    "welcome_sign": (0.8, True),
    "yarn_shelf": (0.7, True),
}

OPAQUE_NODE = "light_bake_opaque"


def log(msg):
    print("[light] " + msg, flush=True)


def gpu_on():
    """Bake on the Mac's GPU (Metal) when Cycles can see one."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("METAL", "OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = kind
            except TypeError:
                continue
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == kind]
            if devs:
                for d in prefs.devices:
                    d.use = d.type == kind
                bpy.context.scene.cycles.device = "GPU"
                return kind
    except Exception as e:  # noqa: BLE001
        log("no GPU (%s), baking on the CPU" % e)
    bpy.context.scene.cycles.device = "CPU"
    return "CPU"


def gltf_summary(path):
    """Nodes, meshes, materials and images of a GLB, read from its JSON chunk."""
    import struct
    with open(path, "rb") as f:
        b = f.read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    return {
        "nodes": sorted(x.get("name", "") for x in j.get("nodes", [])),
        "meshes": len(j.get("meshes", [])),
        "materials": sorted(x.get("name", "") for x in j.get("materials", [])),
        "images": sorted(x.get("name", "") for x in j.get("images", [])),
    }


def bake_material(reach):
    """White-sky bake shader: opaque grey for the baked spot itself and for anything a ray meets within
    `reach` on its first leg; past that (or once a ray has passed through anything) the ray goes on to the sky."""
    m = bpy.data.materials.new("light_bake")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    path = nt.nodes.new("ShaderNodeLightPath")
    near = nt.nodes.new("ShaderNodeMath")
    near.operation = "LESS_THAN"
    near.inputs[1].default_value = reach
    nt.links.new(path.outputs["Ray Length"], near.inputs[0])
    first = nt.nodes.new("ShaderNodeMath")
    first.operation = "LESS_THAN"
    first.inputs[1].default_value = 0.5
    nt.links.new(path.outputs["Transparent Depth"], first.inputs[0])
    both = nt.nodes.new("ShaderNodeMath")
    both.operation = "MULTIPLY"
    nt.links.new(near.outputs[0], both.inputs[0])
    nt.links.new(first.outputs[0], both.inputs[1])
    opaque = nt.nodes.new("ShaderNodeMath")
    opaque.name = OPAQUE_NODE
    opaque.operation = "MAXIMUM"
    nt.links.new(both.outputs[0], opaque.inputs[0])
    nt.links.new(path.outputs["Is Camera Ray"], opaque.inputs[1])
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (BOUNCE_ALBEDO, BOUNCE_ALBEDO, BOUNCE_ALBEDO, 1)
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(opaque.outputs[0], mix.inputs["Fac"])
    nt.links.new(clear.outputs[0], mix.inputs[1])
    nt.links.new(diff.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


def white_sky():
    w = bpy.data.worlds.new("white_sky")
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 1.0
    bpy.context.scene.world = w


def mesh_area(obs):
    a = 0.0
    for ob in obs:
        mw = ob.matrix_world
        s = abs(mw.to_scale().x * mw.to_scale().y * mw.to_scale().z) ** (2.0 / 3.0)
        a += sum(p.area for p in ob.data.polygons) * s
    return a


def light_uvs(obs):
    """Give every mesh a LightUV map (the second UV, Godot's UV2) packed with the rest into one atlas.
    Meshes that already have one (an earlier bake) keep it."""
    fresh = []
    for ob in obs:
        me = ob.data
        if len(me.uv_layers) == 0:
            me.uv_layers.new(name="UVMap")
        if "LightUV" not in me.uv_layers:
            me.uv_layers.new(name="LightUV")
            fresh.append(ob)
        me.uv_layers.active = me.uv_layers["LightUV"]
    if fresh:
        if len(fresh) != len(obs):
            log("  some meshes had LightUV and some not: unwrapping all of them again")
        bpy.ops.object.select_all(action="DESELECT")
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.reveal()
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0,
                                 correct_aspect=True, scale_to_bounds=False)
        bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, margin_method="FRACTION", margin=0.006)
        bpy.ops.object.mode_set(mode="OBJECT")
    for ob in obs:
        # the exporter writes UV maps in order: UVMap stays TEXCOORD_0, LightUV is TEXCOORD_1 (Godot's UV2)
        me = ob.data
        me.uv_layers.active = me.uv_layers[0]
        for i, uv in enumerate(me.uv_layers):
            uv.active_render = i == 0


def occlusion_socket(mat):
    """The Occlusion input of the material's glTF output group (made if missing)."""
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "GROUP" and n.node_tree and "Occlusion" in n.inputs:
            return n.inputs["Occlusion"]
    g = bpy.data.node_groups.get("glTF Material Output")
    if g is None:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        g.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    n = nt.nodes.new("ShaderNodeGroup")
    n.node_tree = g
    n.location = (300, -400)
    return n.inputs["Occlusion"]


def wire_occlusion(mat, img):
    nt = mat.node_tree
    sock = occlusion_socket(mat)
    for l in list(sock.links):
        nt.links.remove(l)
    for n in list(nt.nodes):  # an earlier bake's nodes
        if n.label == "light_bake":
            nt.nodes.remove(n)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.label = "light_bake"
    tex.image = img
    tex.location = (-300, -600)
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.label = "light_bake"
    uv.uv_map = "LightUV"
    uv.location = (-500, -600)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.label = "light_bake"
    sep.location = (0, -600)
    nt.links.new(uv.outputs[0], tex.inputs[0])
    nt.links.new(tex.outputs[0], sep.inputs[0])
    nt.links.new(sep.outputs[0], sock)


def soften(px, w, h):
    """A 3x3 blur of the baked light, to settle the last of the sampling noise."""
    a = px.reshape(h, w, 4)[:, :, 0]
    p = np.pad(a, 1, mode="edge")
    k = np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]], dtype=np.float32) / 16.0
    s = np.zeros_like(a)
    for dy in range(3):
        for dx in range(3):
            s += k[dy, dx] * p[dy:dy + h, dx:dx + w]
    return s


def review(id_, obs, img):
    """A small picture of the prop lit by its bake alone (the atlas shown as plain grey light)."""
    os.makedirs(REVIEW, exist_ok=True)
    m = bpy.data.materials.new("light_review")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "LightUV"
    nt.links.new(uv.outputs[0], tex.inputs[0])
    nt.links.new(tex.outputs[0], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    keep = {}
    for ob in obs:
        keep[ob.name] = list(ob.data.materials)
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = m
    lo = np.array([min((ob.matrix_world @ v.co)[i] for ob in obs for v in ob.data.vertices) for i in range(3)])
    hi = np.array([max((ob.matrix_world @ v.co)[i] for ob in obs for v in ob.data.vertices) for i in range(3)])
    c = (lo + hi) / 2
    r = float(np.linalg.norm(hi - lo)) / 2
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    d = r / math.tan(cam_d.angle / 2) * 1.05
    a, e = math.radians(-35), math.radians(22)
    from mathutils import Vector
    cam.location = Vector(c) + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * d
    cam.rotation_euler = (Vector(c) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.22, 0.25, 1)
    sc.cycles.samples = 16
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.filepath = os.path.join(REVIEW, id_ + ".png")
    sc.view_settings.view_transform = "Standard"
    bpy.ops.render.render(write_still=True)
    for ob in obs:
        for i, mm in enumerate(keep[ob.name]):
            ob.data.materials[i] = mm


def bake(id_):
    reach, ground = PROPS.get(id_, (0.8, True))
    path = os.path.join(PROPS_DIR, id_ + ".glb")
    if not os.path.exists(path):
        raise SystemExit("no %s" % path)
    t0 = time.time()
    before = gltf_summary(path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    dev = gpu_on()
    bpy.ops.import_scene.gltf(filepath=path)
    if any(o.type == "ARMATURE" for o in sc.objects):
        raise SystemExit("%s is rigged: it moves, so it isn't baked" % id_)
    obs = [o for o in sc.objects if o.type == "MESH"]
    # linked duplicates would bake on top of each other in the shared atlas
    seen = set()
    for ob in obs:
        if ob.data.name in seen:
            ob.data = ob.data.copy()
        seen.add(ob.data.name)
    light_uvs(obs)
    area = mesh_area(obs)
    size = int(min(2048, max(256, 2 ** math.ceil(math.log2(max(1.0, math.sqrt(area) * DENSITY))))))
    log("%s: %d meshes, %.1f m2, atlas %d px, reach %.1f m, %s" % (id_, len(obs), area, size, reach, dev))

    img = bpy.data.images.new("light", size, size, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    # swap every material for the bake shader (kept to put back)
    bm = bake_material(reach)
    tex = bm.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uvn = bm.node_tree.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "LightUV"
    bm.node_tree.links.new(uvn.outputs[0], tex.inputs[0])
    bm.node_tree.nodes.active = tex
    originals = {}
    for ob in obs:
        # swapped slot by slot, so each face keeps its material index
        originals[ob.name] = list(ob.data.materials)
        if not ob.data.materials:
            ob.data.materials.append(bm)
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = bm
    if ground:
        lo_z = min((ob.matrix_world @ v.co).z for ob in obs for v in ob.data.vertices)
        bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, lo_z))
        gp = bpy.context.object
        gm = bake_material(reach)
        gm.node_tree.nodes["Diffuse BSDF"].inputs["Color"].default_value = (GROUND_ALBEDO,) * 3 + (1,)
        gp.data.materials.append(gm)
    white_sky()
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 0
    sc.cycles.transparent_max_bounces = 16
    sc.render.bake.margin = 6
    sc.render.bake.margin_type = "EXTEND"
    sc.render.bake.use_pass_direct = True
    sc.render.bake.use_pass_indirect = True
    sc.render.bake.use_pass_color = False
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    for ob in obs:  # Cycles bakes onto each mesh's active UV map
        ob.data.uv_layers.active = ob.data.uv_layers["LightUV"]
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, use_clear=True, margin=6)
    for ob in obs:
        ob.data.uv_layers.active = ob.data.uv_layers[0]
    px = np.array(img.pixels[:], dtype=np.float32)
    lum = np.clip(soften(px, size, size), 0.0, 1.0)
    stats = {"id": id_, "atlas": size, "reach": reach, "samples": SAMPLES, "device": dev,
             "light_mean": round(float(lum.mean()), 3), "light_p05": round(float(np.percentile(lum, 5)), 3)}

    # the atlas as an 8-bit grey PNG, packed into the GLB
    os.makedirs(os.path.join(OUT, id_), exist_ok=True)
    out_img = bpy.data.images.new("light", size, size, alpha=False)
    out_img.colorspace_settings.name = "Non-Color"
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = lum
    out_img.pixels.foreach_set(rgba.ravel())
    png = os.path.join(OUT, id_, "light.png")  # the GLB names the image after the file: Godot extracts <id>_light.png
    out_img.filepath_raw = png
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(img)
    out_img.name = "light"

    if ground:
        bpy.data.objects.remove(gp)
    for ob in obs:
        if not originals[ob.name]:
            ob.data.materials.clear()
        for i, m in enumerate(originals[ob.name]):
            ob.data.materials[i] = m
    for m in {m for ms in originals.values() for m in ms if m is not None}:
        wire_occlusion(m, out_img)
    # a mesh with no material still needs the atlas: give it a plain one
    for ob in obs:
        if not ob.data.materials:
            m = bpy.data.materials.new(id_)
            m.use_nodes = True
            ob.data.materials.append(m)
            wire_occlusion(m, out_img)

    review(id_, obs, out_img)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in sc.objects:
        if ob.type == "CAMERA":
            bpy.data.objects.remove(ob)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_image_format="AUTO", export_draco_mesh_compression_enable=False,
                              export_animations=False, export_lights=False, export_cameras=False)
    after = gltf_summary(path)
    stats["seconds"] = round(time.time() - t0, 1)
    stats["glb_bytes"] = os.path.getsize(path)
    stats["lost_nodes"] = sorted(set(before["nodes"]) - set(after["nodes"]))
    stats["lost_materials"] = sorted(set(before["materials"]) - set(after["materials"]))
    stats["lost_images"] = sorted(set(before["images"]) - set(after["images"]))
    with open(os.path.join(OUT, id_, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
    log(json.dumps(stats))
    if stats["lost_nodes"] or stats["lost_materials"]:
        raise SystemExit("%s lost parts on the way through Blender: %s" % (id_, stats))
    return stats


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("name the props to bake (or all): " + " ".join(PROPS))
    ids = list(PROPS) if args == ["all"] else args
    for id_ in ids:
        bake(id_)


main()
