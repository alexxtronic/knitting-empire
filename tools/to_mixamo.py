"""Tripo GLB -> a light, cleanly textured OBJ for Mixamo's auto-rigger, zipped with its MTL and base colour.

Cut down as it comes, a 2M-face Tripo model creases along its texture seams (a fold down Max's
cheek), and the old UVs smear once the mesh is that light; Mixamo carries both into the game. So the light
copy is welded, lightly smoothed and cut down without the old UVs' constraints, unwrapped afresh, and its
colours baked across from the full-detail model.
  Blender -b --factory-startup -P tools/to_mixamo.py -- <tripo.glb> <out.zip> <height_m> [faces]

Upload the zip to mixamo.com's auto-rigger, download the rigged T-pose as FBX and bring it in with
tools/import_mixamo.py. Faces default to 30000; if the light copy shows a dark line across the face (a thin
sliver of a triangle that picked up a nostril's shadow in the bake, as Lars's did), try 40000."""
import bpy, bmesh, sys, os, shutil, tempfile, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
src, out, height = a[0], a[1], float(a[2])
FACES = int(a[3]) if len(a) > 3 else 30000
TEX = 2048
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
ms = [o for o in sc.objects if o.type == "MESH"]
for o in sc.objects: o.select_set(o in ms)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1: bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(sc.objects):
    if o != hi: bpy.data.objects.remove(o)
H = hi.dimensions.z
print("FACES before", len(hi.data.polygons), "height in file", round(H, 3))

# ---- the light copy: weld the seams, cut down, unwrap afresh
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = lo.data.name = "light"
sc.collection.objects.link(lo)
bm = bmesh.new(); bm.from_mesh(lo.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001 * H)
bm.to_mesh(lo.data); bm.free()
for o in sc.objects: o.select_set(o == lo)
bpy.context.view_layer.objects.active = lo
for nm_ in ("custom_normal", "sharp_edge", "sharp_face"):      # the import's split normals and sharp marks
    if nm_ in lo.data.attributes: lo.data.attributes.remove(lo.data.attributes[nm_])
for p in lo.data.polygons: p.use_smooth = True
# Tripo meshes carry tiny folds along their texture seams; cut down as they are, a fold grows into a crease
# down the face (the male model's cheek). A light smoothing first irons them out; the bake below still
# takes its colours from the full model
m = lo.modifiers.new("s", "SMOOTH"); m.factor = 0.5; m.iterations = 3
bpy.ops.object.modifier_apply(modifier="s")
m = lo.modifiers.new("d", "DECIMATE"); m.ratio = min(1.0, FACES / len(lo.data.polygons))
bpy.ops.object.modifier_apply(modifier="d")
while lo.data.uv_layers: lo.data.uv_layers.remove(lo.data.uv_layers[0])
lo.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004, area_weight=0.0, scale_to_bounds=False)
bpy.ops.object.mode_set(mode="OBJECT")
print("FACES after", len(lo.data.polygons))

# ---- bake the full model's base colour onto it
img = bpy.data.images.new("basecolor", TEX, TEX, alpha=False)
mat = bpy.data.materials.new("skin"); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]; bsdf.inputs["Roughness"].default_value = 0.85
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
lo.data.materials.clear(); lo.data.materials.append(mat)
nt.nodes.active = tex
sc.render.engine = "CYCLES"; sc.cycles.samples = 4; sc.cycles.device = "CPU"
bk = sc.render.bake
bk.use_selected_to_active = True; bk.use_cage = False
bk.cage_extrusion = 0.0025 * H; bk.max_ray_distance = 0.012 * H; bk.margin = 12   # short rays: a curl over the forehead mustn't shade it
for o in sc.objects: o.select_set(o in (hi, lo))
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
print("BAKED", img.name, tuple(img.size))

# ---- keep only the light model, scaled to height, standing on the ground, centred
bpy.data.objects.remove(hi)
for i in list(bpy.data.images):
    if i != img: bpy.data.images.remove(i)
for o in sc.objects: o.select_set(o == lo)
s = height / lo.dimensions.z
lo.scale = (s, s, s); bpy.ops.object.transform_apply(scale=True)
bb = [mathutils.Vector(c) for c in lo.bound_box]
lo.location = (-sum(v.x for v in bb) / 8, -sum(v.y for v in bb) / 8, -min(v.z for v in bb))
bpy.ops.object.transform_apply(location=True)
print("DIMS", tuple(round(d, 3) for d in lo.dimensions))

# ---- OBJ + MTL + texture, zipped (Mixamo can't read Blender's FBX without a skeleton)
d = tempfile.mkdtemp()
name = os.path.splitext(os.path.basename(out))[0]
img.name = name + "_basecolor"
img.filepath_raw = os.path.join(d, img.name + ".png"); img.file_format = "PNG"; img.save()
bpy.ops.wm.obj_export(filepath=os.path.join(d, name + ".obj"), export_materials=True, path_mode="STRIP",
                      forward_axis="NEGATIVE_Z", up_axis="Y", export_normals=True, export_uv=True)
if os.path.exists(out): os.remove(out)
shutil.make_archive(out[:-4], "zip", d)
print("FILES", sorted(os.listdir(d)))
print("WROTE", out, os.path.getsize(out))
