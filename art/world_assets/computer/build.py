"""The computer from Tripo: a cosy wooden desk with a cream monitor, tower, keyboard and mouse.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/computer/build.py -- "<computer desk 3d model.glb>" [--yaw DEG] [--orient] [--render]

Alex (2026-11-16, docs/DIRECTION.md): a computer is a big, expensive purchase that opens an online
store (like Etsy) she uses in first person. Picture first (ChatGPT, ref/computer.png, asked for in the
game's Woolcore look from docs/woolcore/style_02_hearth.png), then one Tripo generation (H3.1 Best
Quality, 4K textures, 300k triangles). This script:
  1. imports the export and welds it (Tripo splits it along its UV seams);
  2. turns it to face -Y (+Z in Godot): `--yaw` degrees about Z, read off review/orient.png, which
     it renders from above with the axes marked (`--orient` stops there);
  3. scales it so the desk top stands DESK_TOP metres high (the desk top is the biggest flat,
     upward-facing area in the model) and sets it on the floor, origin under the middle of the desk;
  4. thins a copy to FACES triangles, unwraps it and bakes Tripo's colour and its normal detail onto it
     at TEX px;
  5. finds the screen (dark, facing the front, above the desk top) on the bake and lays a flat quad
     over it, in the plane of those faces (tilted back with the monitor): its own object and material, both named `screen`, with UVs 0..1 (u left to right as you
     face it, v bottom to top), so the game can draw a store's page on it;
  6. exports assets/props/computer.glb (never Draco: Godot can't read it).
Then run the light bake (`art/world_assets/light_bake/build.py -- computer`) and import.
--render saves review/front.png and review/threeq.png.
The source export stays in Alex's Downloads, not the repo.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:]
SRC = os.path.abspath(argv[0])
RENDER = "--render" in argv
YAW = float(argv[argv.index("--yaw") + 1]) if "--yaw" in argv else 0.0
OUT = os.path.join(HERE, "out")
REVIEW = os.path.join(HERE, "review")
PID = "computer"
DESK_TOP = 0.76  # metres: a writing desk (the kitchen counter is 0.9)
FACES = 12000  # she sits at it in first person: more than a yard prop
TEX = 2048
SCREEN_DARK = 0.16  # the screen's baked colour is darker than this (luminance)


def activate(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def import_src():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in obs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix()
        o.parent = None
    if len(obs) > 1:
        activate(*obs)
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active if len(obs) > 1 else obs[0]
    for o in list(bpy.context.scene.objects):
        if o is not ob:
            bpy.data.objects.remove(o)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    print("IMPORTED %s: %d faces, %d -> %d vertices after welding" % (os.path.basename(SRC), len(bm.faces), before, len(bm.verts)))
    bm.free()
    ob.name = ob.data.name = PID + "_src"
    return ob


def desk_top_z(me):
    """The height of the biggest flat upward-facing area: a histogram of upward faces' area by z."""
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    bins = 200
    area = [0.0] * bins
    for p in me.polygons:
        if p.normal.z > 0.92:
            k = min(bins - 1, int((p.center.z - z0) / (z1 - z0) * bins))
            area[k] += p.area
    # ignore the floor-level bins (the feet's soles)
    k = max(range(bins // 10, bins), key=lambda i: area[i])
    return z0 + (k + 0.5) / bins * (z1 - z0), z0, z1


def stand(ob):
    me = ob.data
    me.transform(Matrix.Rotation(math.radians(YAW), 4, "Z"))
    top, z0, z1 = desk_top_z(me)
    s = DESK_TOP / (top - z0)
    # the middle of the desk: the extent of what stands below the desk top
    below = [v.co for v in me.vertices if v.co.z < top - 0.02 * (z1 - z0)]
    cx = (min(c.x for c in below) + max(c.x for c in below)) / 2.0
    cy = (min(c.y for c in below) + max(c.y for c in below)) / 2.0
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -z0))))
    me.update()
    co = [v.co for v in me.vertices]
    size = Vector((max(c.x for c in co) - min(c.x for c in co), max(c.y for c in co) - min(c.y for c in co), max(c.z for c in co)))
    print("STOOD %s: yaw %.0f deg, desk top at %.3f of %.3f -> scaled x%.4f; %.3f x %.3f x %.3f m" % (
        PID, YAW, top - z0, z1 - z0, s, size.x, size.y, size.z))
    return size


def orient_view(ob, size):
    """From above, +X red bar, -Y (the front) green bar: to read --yaw off."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 900
    world = bpy.data.worlds.new("w")
    world.color = (1, 1, 1)
    sc.world = world
    marks = []
    for name, loc, scale, col in (("x", (0.6 * max(size), 0, 0), (0.3 * max(size), 0.01, 0.01), (1, 0, 0, 1)),
                                  ("front", (0, -0.6 * max(size), 0), (0.01, 0.3 * max(size), 0.01), (0, 0.7, 0, 1))):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=2.0)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        m = bpy.data.materials.new(name)
        m.diffuse_color = col
        me.materials.append(m)
        o.location, o.scale = loc, scale
        sc.collection.objects.link(o)
        marks.append(o)
    sc.display.shading.color_type = "MATERIAL"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.0 * max(size)
    os.makedirs(REVIEW, exist_ok=True)
    for name, loc, rot in (("orient", (0, 0, 5), (0, 0, 0)), ("orient_front", (0, -5, size.z / 2), (90, 0, 0))):
        cam.location = loc
        cam.rotation_euler = [math.radians(a) for a in rot]
        sc.display.shading.color_type = "TEXTURE"
        for o in marks:
            o.hide_render = name != "orient"
        sc.render.filepath = os.path.join(REVIEW, name + ".png")
        bpy.ops.render.render(write_still=True)
    for o in marks + [cam]:
        bpy.data.objects.remove(o)
    print("ORIENT review/orient.png (from above: red +X, green the front -Y), review/orient_front.png")


def low_copy(src):
    low = src.copy()
    low.data = src.data.copy()
    bpy.context.scene.collection.objects.link(low)
    low.name = low.data.name = PID
    mod = low.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, FACES / max(1, len(src.data.polygons)))
    activate(low)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = bmesh.new()
    bm.from_mesh(low.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(low.data)
    bm.free()
    for p in low.data.polygons:
        p.use_smooth = True
    print("THINNED %s: %d -> %d triangles" % (PID, len(src.data.polygons), len(low.data.polygons)))
    return low


def bake(src, low, H):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    for m in src.data.materials:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            for l in list(bsdf.inputs["Metallic"].links):
                m.node_tree.links.remove(l)
            bsdf.inputs["Metallic"].default_value = 0.0
    activate(low)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    col = bpy.data.images.new(PID + "_color", TEX, TEX, alpha=False)
    nor = bpy.data.images.new(PID + "_normal", TEX, TEX, alpha=False)
    nor.colorspace_settings.name = "Non-Color"
    m = bpy.data.materials.new(PID)
    m.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(m)
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    ntex = nt.nodes.new("ShaderNodeTexImage")
    ntex.image = nor
    for img, kind, extra in ((col, "DIFFUSE", {"pass_filter": {"COLOR"}}), (nor, "NORMAL", {"normal_space": "TANGENT"})):
        tex.image = img
        nt.nodes.active = tex
        activate(low, src)
        bpy.context.view_layer.objects.active = low
        bpy.ops.object.bake(type=kind, use_selected_to_active=True, cage_extrusion=0.01 * H,
                            max_ray_distance=0.03 * H, margin=8, **extra)
    tex.image = col
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ntex.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.85  # felt-matte (docs/STYLE_GUIDE.md)
    bsdf.inputs["Metallic"].default_value = 0.0
    os.makedirs(OUT, exist_ok=True)
    for img in (col, nor):
        img.filepath_raw = os.path.join(OUT, img.name + ".png")
        img.file_format = "PNG"
        img.save()
    print("BAKED %s colour and normal at %d px" % (PID, TEX))
    return col


def screen_quad(low, col):
    """A flat quad over the monitor's dark screen, its own object and material named `screen`."""
    me = low.data
    uv = me.uv_layers.active.data
    px = col.pixels[:]
    W = col.size[0]
    top = DESK_TOP + 0.05
    dark = []
    for p in me.polygons:
        if p.normal.y > -0.8 or p.center.z < top:
            continue
        u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
        x, y = min(W - 1, max(0, int(u * W))), min(W - 1, max(0, int(v * W)))
        k = 4 * (y * W + x)
        lum = 0.2126 * px[k] + 0.7152 * px[k + 1] + 0.0722 * px[k + 2]
        if lum < SCREEN_DARK:
            dark.append(p)
    assert dark, "found no screen: no dark front-facing faces above the desk top"
    area = sum(p.area for p in dark)
    # the screen's plane: the dark faces' area-weighted normal (Tripo may tilt the monitor back)
    n = Vector()
    for p in dark:
        n += p.normal * p.area
    n.normalize()
    right = (Vector((1, 0, 0)) - n * n.x).normalized()
    up = n.cross(right)  # for n = -Y: +Z
    pts = [me.vertices[i].co for p in dark for i in p.vertices]
    us = sorted(c.dot(right) for c in pts)
    vs = sorted(c.dot(up) for c in pts)

    def pct(a, q):  # trims stray dark bits (a knob, a vent)
        return a[int(q * (len(a) - 1))]
    u0, u1, v0, v1 = pct(us, 0.02), pct(us, 0.98), pct(vs, 0.02), pct(vs, 0.98)
    inner = [p for p in dark if u0 <= p.center.dot(right) <= u1 and v0 <= p.center.dot(up) <= v1]
    d = max(me.vertices[i].co.dot(n) for p in inner for i in p.vertices) + 0.002  # just in front
    inset = 0.012 * (u1 - u0)
    u0, u1, v0, v1 = u0 + inset, u1 - inset, v0 + inset, v1 - inset

    def P(u, v):
        return tuple(right * u + up * v + n * d)
    sm = bpy.data.meshes.new("screen")
    sm.from_pydata([P(u0, v0), P(u1, v0), P(u1, v1), P(u0, v1)], [], [(0, 1, 2, 3)])
    sm.update()
    uvl = sm.uv_layers.new(name="UVMap")
    for li, (a, b) in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        uvl.data[li].uv = (a, b)
    # wound along right then up, so it faces n (the front); seen from there u runs left to right
    assert sm.polygons[0].normal.dot(n) > 0.99
    tilt = math.degrees(math.acos(max(-1.0, min(1.0, -n.y))))
    m = bpy.data.materials.new("screen")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.03, 0.028, 0.026, 1)  # charcoal, switched off
    b.inputs["Roughness"].default_value = 0.4
    sm.materials.append(m)
    so = bpy.data.objects.new("screen", sm)
    bpy.context.scene.collection.objects.link(so)
    so.parent = low
    c = Vector(P((u0 + u1) / 2, (v0 + v1) / 2))
    print("SCREEN %d dark faces (%.3f m2); quad %.3f x %.3f m (aspect %.3f), centre (%.3f, %.3f, %.3f), normal %s, tilted %.1f deg off vertical" % (
        len(dark), area, u1 - u0, v1 - v0, (u1 - u0) / (v1 - v0), c.x, c.y, c.z, tuple(round(x, 3) for x in n), tilt))
    return so


def export(low, screen):
    path = os.path.join(PROJECT, "assets", "props", PID + ".glb")
    activate(low, screen)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=92,
                              export_draco_mesh_compression_enable=False)
    print("EXPORTED %s: %d triangles + screen -> %s" % (PID, len(low.data.polygons), os.path.relpath(path, PROJECT)))


def render(low):
    sc = bpy.context.scene
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("w2")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 32
    sc.render.resolution_x, sc.render.resolution_y = 900, 900
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    h = low.dimensions.z
    for name, loc in (("front", (0, -4.2, h * 0.6)), ("threeq", (2.6, -3.0, h * 1.6))):
        cam.location = loc
        d = Vector((0, 0, h * 0.5)) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(REVIEW, name + ".png")
        bpy.ops.render.render(write_still=True)
    print("RENDERED review/front.png, review/threeq.png")


def main():
    src = import_src()
    size = stand(src)
    orient_view(src, size)
    if "--orient" in argv:
        return
    low = low_copy(src)
    col = bake(src, low, size.z)
    screen = screen_quad(low, col)
    bpy.data.objects.remove(src)
    export(low, screen)
    if RENDER:
        render(low)


main()
