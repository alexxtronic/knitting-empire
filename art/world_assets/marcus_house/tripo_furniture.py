"""Marcus's house furniture from Alex's two Tripo lineups: each export cut into one game model per piece.

    Blender --background --factory-startup --python-exit-code 1 --python art/world_assets/marcus_house/tripo_furniture.py -- <lineup.glb> household|wooden [--probe] [--render] [--only id,id]

Alex (2026-11-17) gave two Tripo exports for the walk-in house in Bretton Oaks: "household items 3d
model.glb" (a TV armoire, a sofa, a Christmas tree, a bunk bed with a blue duvet) and "wooden furniture
3d model.glb" (a double bed, a crib, a light table with white legs, a spindle chair, a coffee table). Tripo laid each out like the picture it came from: the pieces stand in rows up the export's
z axis, some one behind another. This script:
  1. imports the export and welds it (Tripo splits it along its UV seams);
  2. cuts it into pieces: the big connected clusters of a 1 cm voxel grid (loose crumbs join the
     piece whose box they sit in), ordered top row first, then left to right, named by SETS;
  3. stands each on the ground, origin under the middle of its footprint, front to -Y (+Z in
     Godot), scaled to its height in metres (SETS);
  4. thins a copy to its triangle budget, unwraps it and bakes Tripo's colour and its normal detail
     onto it at TEX px (a "tone" lifts the colour: the near-black sofa becomes Alex's grey couch);
  5. exports assets/props/<id>.glb (never Draco: Godot can't read it).
--probe only prints the clusters; --render saves review/<set>.png, the pieces side by side.
The source exports stay in Alex's Downloads, not the repo (each is about 17 MB).
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
SET = argv[1]
PROBE = "--probe" in argv
RENDER = "--render" in argv
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else []
OUT = os.path.join(HERE, "out")
TEX = 1024
# Tripo flattened some pieces front to back, as in its picture: their depth in metres
DEPTH = {"bed_double": 2.1}

# per set, in reading order (top row first, left to right): id, height in metres, triangles, colour
# tone (None, or (mean brightness, saturation): the near-black sofa toned to a mid grey)
SETS = {
    "household": [
        ("tv_armoire", 1.75, 14000, None),
        ("sofa_grey", 0.92, 16000, (0.21, 0.3)),
        ("christmas_tree", 1.95, 18000, None),
        ("bunk_bed", 1.9, 16000, None),
    ],
    "wooden": [
        ("bed_double", 1.3, 16000, None),
        ("crib", 0.92, 14000, None),
        ("table_light", 0.76, 8000, None),
        ("chair_spindle", 0.95, 6000, None),
        ("coffee_table_oak", 0.46, 6000, None),
    ],
}


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
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(ob.data)
    print("IMPORTED %s: %d faces" % (os.path.basename(SRC), len(bm.faces)))
    bm.free()
    return ob


def clusters(ob):
    """Face groups: connected pieces of the mesh, merged where their voxels touch (1 cm)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    # connected components by shared vertices
    comp = [-1] * len(bm.faces)
    n = 0
    for f0 in bm.faces:
        if comp[f0.index] >= 0:
            continue
        stack = [f0]
        comp[f0.index] = n
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if comp[g.index] < 0:
                        comp[g.index] = n
                        stack.append(g)
        n += 1
    # boxes per component
    lo = [Vector((1e9,) * 3) for _ in range(n)]
    hi = [Vector((-1e9,) * 3) for _ in range(n)]
    cnt = [0] * n
    for f in bm.faces:
        c = comp[f.index]
        cnt[c] += 1
        for v in f.verts:
            for i in range(3):
                lo[c][i] = min(lo[c][i], v.co[i])
                hi[c][i] = max(hi[c][i], v.co[i])
    # merge components that touch: each one's vertices on a 1 cm voxel grid, two components joined
    # where their voxels meet (a box test merged pieces standing one behind another in the picture)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    order = sorted(range(n), key=lambda c: -cnt[c])
    big = set(c for c in order if cnt[c] >= 200)
    vox = {}
    g = 0.01
    for f in bm.faces:
        c = comp[f.index]
        if c not in big:
            continue
        for v in f.verts:
            key = (int(v.co.x // g), int(v.co.y // g), int(v.co.z // g))
            o = vox.get(key)
            if o is None:
                vox[key] = c
            elif find(o) != find(c):
                parent[find(c)] = find(o)
    for key, c in list(vox.items()):
        for d in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
            o = vox.get((key[0] + d[0], key[1] + d[1], key[2] + d[2]))
            if o is not None and find(o) != find(c):
                parent[find(c)] = find(o)
    groups = {}
    for c in big:
        groups.setdefault(find(c), []).append(c)
    # crumbs join the group whose box holds their centre
    gbox = {}
    for r, cs in groups.items():
        glo = Vector((min(lo[c][k] for c in cs) for k in range(3)))
        ghi = Vector((max(hi[c][k] for c in cs) for k in range(3)))
        gbox[r] = (glo, ghi)
    for c in order:
        if cnt[c] >= 200:
            continue
        mid = (lo[c] + hi[c]) / 2
        best = None
        for r, (glo, ghi) in gbox.items():
            d = sum(max(glo[k] - mid[k], 0, mid[k] - ghi[k]) for k in range(3))
            if best is None or d < best[0]:
                best = (d, r)
        groups[best[1]].append(c)
    out = []
    for r, cs in groups.items():
        faces = sum(cnt[c] for c in cs)
        glo, ghi = gbox[r]
        out.append({"comps": set(cs), "lo": glo, "hi": ghi, "faces": faces})
    bm.free()
    out = [p for p in out if p["faces"] > 2000]
    return comp, out


def reading_order(pieces):
    """Top row first (by the top of each piece's box), then left to right."""
    pieces.sort(key=lambda p: -p["hi"].z)
    rows = []
    for p in pieces:
        for row in rows:
            r0 = row[0]
            # the same row if their vertical spans overlap by half the smaller one
            ov = min(p["hi"].z, r0["hi"].z) - max(p["lo"].z, r0["lo"].z)
            if ov > 0.5 * min(p["hi"].z - p["lo"].z, r0["hi"].z - r0["lo"].z):
                row.append(p)
                break
        else:
            rows.append([p])
    out = []
    for row in rows:
        out.extend(sorted(row, key=lambda p: p["lo"].x))
    return out


def split(ob, comp, pieces):
    parts = []
    for k, p in enumerate(pieces):
        dup = ob.copy()
        dup.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(dup)
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        bm.faces.ensure_lookup_table()
        gone = [f for f in bm.faces if comp[f.index] not in p["comps"]]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bm.to_mesh(dup.data)
        bm.free()
        parts.append(dup)
    bpy.data.objects.remove(ob)
    return parts


def stand(ob, pid, height):
    me = ob.data
    co = [v.co for v in me.vertices]
    z0 = min(c.z for c in co)
    z1 = max(c.z for c in co)
    cx = (min(c.x for c in co) + max(c.x for c in co)) / 2
    cy = (min(c.y for c in co) + max(c.y for c in co)) / 2
    s = height / (z1 - z0)
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -z0))))
    if pid in DEPTH:
        d = max(v.co.y for v in me.vertices) - min(v.co.y for v in me.vertices)
        me.transform(Matrix.Diagonal((1.0, DEPTH[pid] / d, 1.0, 1.0)))
    me.update()
    co = [v.co for v in me.vertices]
    size = (max(c.x for c in co) - min(c.x for c in co), max(c.y for c in co) - min(c.y for c in co), max(c.z for c in co))
    print("PIECE %s: %d faces, %.2f x %.2f x %.2f m" % ((pid, len(me.polygons)) + size))
    ob.name = ob.data.name = pid + "_src"
    return size


def low_copy(src, pid, faces):
    low = src.copy()
    low.data = src.data.copy()
    bpy.context.scene.collection.objects.link(low)
    low.name = low.data.name = pid
    mod = low.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, faces / max(1, len(src.data.polygons)))
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


def bake(src, low, pid, size, tone):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    H = max(size)
    for m in src.data.materials:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            for link in list(bsdf.inputs["Metallic"].links):
                m.node_tree.links.remove(link)
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
    if tone:
        # scale the colour so its average brightness is `target` (linear), keeping its texture;
        # `sat` keeps that much of its colour
        target, sat = tone
        px = list(col.pixels)
        lum = [0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2] for i in range(0, len(px), 4)]
        mean = sum(lum) / len(lum)
        k = target / max(mean, 1e-4)
        for j, i in enumerate(range(0, len(px), 4)):
            y = lum[j]
            for c in range(3):
                px[i + c] = min(1.0, max(0.0, (y + (px[i + c] - y) * sat) * k))
        col.pixels = px
        print("TONED %s: mean %.3f -> %.3f" % (pid, mean, target))
    tex.image = col
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(ntex.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.8
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
        w = low.dimensions.x
        low.location = (x + w / 2, 0, 0)
        x += w + 0.3
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = x + 0.4
    cam.location = (x / 2, -9, 2.2)
    cam.rotation_euler = (math.radians(78), 0, 0)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.render.resolution_x, sc.render.resolution_y = 1600, 560
    os.makedirs(os.path.join(HERE, "review"), exist_ok=True)
    sc.render.filepath = os.path.join(HERE, "review", SET + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED review/%s.png" % SET)


def main():
    ob = import_lineup()
    comp, pieces = clusters(ob)
    pieces = reading_order(pieces)
    spec = SETS[SET]
    for k, p in enumerate(pieces):
        lo, hi = p["lo"], p["hi"]
        name = spec[k][0] if k < len(spec) else "?"
        print("CLUSTER %d %-16s faces %6d  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (k, name, p["faces"], lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
    assert len(pieces) == len(spec), "found %d pieces for %d ids" % (len(pieces), len(spec))
    if PROBE:
        return
    srcs = split(ob, comp, pieces)
    lows = []
    for src, (pid, height, faces, tone) in zip(srcs, spec):
        if ONLY and pid not in ONLY:
            bpy.data.objects.remove(src)
            continue
        size = stand(src, pid, height)
        low = low_copy(src, pid, faces)
        bake(src, low, pid, size, tone)
        export(low, pid)
        lows.append(low)
        bpy.data.objects.remove(src)
    if RENDER:
        render(lows)


main()
