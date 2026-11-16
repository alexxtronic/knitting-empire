"""The garden's big flowers from Tripo: one lineup export cut into one game model per plant.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/flowers/build.py -- <lineup.glb> [--render]

Alex (2026-11-15) wanted the code-built sunflowers (blocky cylinders) replaced with ChatGPT picture >
Tripo models, and the same for other large flowers. To save credits the five plants share one picture
(ref/lineup_1.png: sunflowers, a rose bush, foxgloves (Tripo made them a pink mallow, and they are called that), hollyhocks, a hydrangea, left to right) and so
one Tripo generation (H3.1 Best Quality, 55 credits). This script:
  1. imports the export and welds it (Tripo splits it along its UV seams);
  2. cuts it into plants at the widest empty gaps along the row, left to right (IDS);
  3. stands each on the ground, origin under the middle of its base, scaled to HEIGHTS (metres);
  4. thins a copy to FACES triangles, unwraps it and bakes Tripo's colour and its normal detail onto it
     at TEX px;
  5. exports assets/props/<id>.glb (never Draco: Godot can't read it).
--render saves review/lineup.png, the five side by side as the game will have them.
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
OUT = os.path.join(HERE, "out")

IDS = ["sunflowers", "rose_bush", "mallow", "hollyhocks", "hydrangea"]
HEIGHTS = {"sunflowers": 1.65, "rose_bush": 0.85, "mallow": 1.15, "hollyhocks": 1.8, "hydrangea": 0.95}
FACES = 9000  # the yard can hold dozens of them: kept light
TEX = 1024


def activate(*obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def import_lineup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(obs) > 1:
        activate(*obs)
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active if len(obs) > 1 else obs[0]
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix()
    ob.parent = None
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    print("IMPORTED %s: %d faces, %d -> %d vertices after welding" % (os.path.basename(SRC), len(bm.faces), before, len(bm.verts)))
    bm.free()
    co = [v.co for v in ob.data.vertices]
    span = [max(c[i] for c in co) - min(c[i] for c in co) for i in range(3)]
    print("SPAN x %.3f y %.3f z %.3f" % tuple(span))
    # the row runs along the longer of x and y: turn it onto x
    if span[1] > span[0]:
        ob.data.transform(Matrix.Rotation(math.radians(-90), 4, "Z"))
    return ob


def cut_points(ob, n):
    """The n-1 x positions to cut at: the middles of the widest empty runs along the row."""
    xs = [v.co.x for v in ob.data.vertices]
    lo, hi = min(xs), max(xs)
    bins = 4000
    occ = [False] * bins
    for x in xs:
        occ[min(bins - 1, int((x - lo) / (hi - lo) * bins))] = True
    runs, start = [], None
    for i, o in enumerate(occ + [True]):
        if not o and start is None:
            start = i
        elif o and start is not None:
            runs.append((i - start, start, i))
            start = None
    runs.sort(reverse=True)
    assert len(runs) >= n - 1, "only %d gaps along the row for %d plants" % (len(runs), n)
    cuts = sorted(lo + (a + b) / 2.0 / bins * (hi - lo) for _w, a, b in runs[:n - 1])
    print("CUTS at x = %s" % ", ".join("%.3f" % c for c in cuts))
    return cuts


def split(ob):
    cuts = cut_points(ob, len(IDS))
    parts = []
    for k, pid in enumerate(IDS):
        lo = cuts[k - 1] if k > 0 else -1e9
        hi = cuts[k] if k < len(cuts) else 1e9
        dup = ob.copy()
        dup.data = ob.data.copy()
        dup.name = dup.data.name = pid + "_src"
        bpy.context.scene.collection.objects.link(dup)
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        gone = [f for f in bm.faces if not (lo <= f.calc_center_median().x < hi)]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bm.to_mesh(dup.data)
        bm.free()
        parts.append(dup)
    bpy.data.objects.remove(ob)
    return parts


def stand(ob, pid):
    me = ob.data
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    ground = [v.co for v in me.vertices if v.co.z < z0 + 0.06 * (z1 - z0)]
    cx = sum(c.x for c in ground) / len(ground)
    cy = sum(c.y for c in ground) / len(ground)
    s = HEIGHTS[pid] / (z1 - z0)
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -z0))))
    me.update()
    co = [v.co for v in me.vertices]
    print("PLANT %s: %d faces, %.2f x %.2f x %.2f m" % (pid, len(me.polygons), max(c.x for c in co) - min(c.x for c in co),
                                                        max(c.y for c in co) - min(c.y for c in co), max(c.z for c in co)))


def low_copy(src, pid):
    low = src.copy()
    low.data = src.data.copy()
    bpy.context.scene.collection.objects.link(low)
    low.name = low.data.name = pid
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
    print("THINNED %s: %d -> %d triangles" % (pid, len(src.data.polygons), len(low.data.polygons)))
    return low


def bake(src, low, pid):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    H = HEIGHTS[pid]
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
    col = bpy.data.images.new(pid + "_color", TEX, TEX, alpha=False)
    nor = bpy.data.images.new(pid + "_normal", TEX, TEX, alpha=False)
    nor.colorspace_settings.name = "Non-Color"
    m = bpy.data.materials.new(pid)
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
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.0
    os.makedirs(os.path.join(OUT, pid), exist_ok=True)
    for img in (col, nor):
        img.filepath_raw = os.path.join(OUT, pid, img.name + ".png")
        img.file_format = "PNG"
        img.save()
    print("BAKED %s colour and normal at %d px" % (pid, TEX))


def export(low, pid):
    path = os.path.join(PROJECT, "assets", "props", pid + ".glb")
    activate(low)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=92,
                              export_draco_mesh_compression_enable=False)
    print("EXPORTED %s: %d triangles -> %s" % (pid, len(low.data.polygons), os.path.relpath(path, PROJECT)))


def render(lows):
    sc = bpy.context.scene
    x = 0.0
    for low in lows:
        low.location = (x, 0, 0)
        x += 1.3
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = x + 0.4
    cam.location = (x / 2 - 0.65, -8, 1.4)
    cam.rotation_euler = (math.radians(86), 0, 0)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.render.resolution_x, sc.render.resolution_y = 1600, 520
    os.makedirs(os.path.join(HERE, "review"), exist_ok=True)
    sc.render.filepath = os.path.join(HERE, "review", "lineup.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED review/lineup.png")


def main():
    ob = import_lineup()
    srcs = split(ob)
    lows = []
    for src, pid in zip(srcs, IDS):
        stand(src, pid)
        low = low_copy(src, pid)
        bake(src, low, pid)
        export(low, pid)
        lows.append(low)
    for src in srcs:
        bpy.data.objects.remove(src)
    if RENDER:
        render(lows)


main()
