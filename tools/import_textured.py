"""Bring a textured model (a Tripo export, say) into the game looking like the original.

Unlike tools/import_asset.py, which repaints a model in flat Woolcore palette colours, this keeps the
model's own UVs, colour texture and normal map, so painted detail (eyes, cheeks, a nose) survives.
It only makes the model game-sized and game-light.

Run headless:
  Blender -b --factory-startup -P tools/import_textured.py -- <project_dir> <model.glb> <id>
          [--height 0.95] [--yaw 0] [--faces 20000] [--tex 1024] [--render out.png]

What it does:
  1. imports the file, keeps only meshes, joins them and applies their transforms;
  2. turns it --yaw degrees, scales it to --height metres, centres it on its footprint and puts its
     base on the floor (models face +Z in Godot, -Y here);
  3. decimates it to a --faces budget, keeping UVs;
  4. shrinks the colour and normal textures to --tex pixels (the roughness map is dropped: the
     material is matte), names the material <id> (not wool_*, so Catalog.model leaves it alone) and
     exports assets/props/<id>.glb with the textures inside.
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, SRC, ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


HEIGHT = float(opt("--height", 1.0))
YAW = float(opt("--yaw", 0))
FACES = int(opt("--faces", 20000))
TEX = int(opt("--tex", 1024))
RENDER = opt("--render")

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(bpy.context.scene.objects):
    if o != ob:
        bpy.data.objects.remove(o)
ob.parent = None
before = len(ob.data.polygons)

# 2. orientation, size and placement (bake everything into the mesh)
ob.data.transform(ob.matrix_world)
ob.matrix_world = Matrix.Identity(4)
ob.data.transform(Matrix.Rotation(math.radians(YAW), 4, "Z"))
pts = [v.co for v in ob.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
s = HEIGHT / (hi.z - lo.z)
ob.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
ob.data.transform(Matrix.Scale(s, 4))
ob.data.update()

# 3. decimate, keeping UVs
if before > FACES:
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = FACES / before
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
for p in ob.data.polygons:
    p.use_smooth = True

# 4. textures: shrink colour and normal, drop roughness/metal, name the material
for i, mat in enumerate(ob.data.materials):
    if mat is None:
        continue
    mat.name = ID if i == 0 else "%s_%d" % (ID, i)
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    for n in nt.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            used = [l.to_socket.name for l in nt.links if l.from_node == n]
            to_norm = any(l.to_node.type == "NORMAL_MAP" for l in nt.links if l.from_node == n)
            if not to_norm and not any(u == "Base Color" for u in used):
                for l in [l for l in nt.links if l.from_node == n]:
                    nt.links.remove(l)
                continue
            img = n.image
            if max(img.size) > TEX:
                img.scale(TEX, TEX)
            img.name = "%s_%s" % (ID, "normal" if to_norm else "color")
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 0.9
        bsdf.inputs["Metallic"].default_value = 0.0

out = os.path.join(PROJECT, "assets", "props", ID + ".glb")
ob.name = ob.data.name = "model"
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                          export_image_format="JPEG", export_jpeg_quality=88, export_yup=True)
dims = ob.dimensions
print("IMPORTED %s: %d -> %d faces, %.2f wide x %.2f deep x %.2f tall (m), textures %d px -> %s" % (
    ID, before, len(ob.data.polygons), dims.x, dims.y, dims.z, TEX, out))

if RENDER:
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    c = Vector((0, 0, dims.z * 0.5))
    cam.location = c + Vector((dims.z * 1.3, -dims.z * 2.2, dims.z * 0.9))
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.color = (0.35, 0.35, 0.35)
    scene.world = w
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    scene.render.filepath = os.path.abspath(RENDER)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", RENDER)
