"""Join every mesh in a finished model into one, keeping its materials and textures exactly.

A model made of many separate parts costs one draw call per part in Godot (141 for the market
stall). Joined, it costs one per material instead. Nothing else changes: positions, UVs, normals,
material names (so `wool_*` still gets the Woolcore shader) and embedded images are kept.

Run headless:
  Blender -b --factory-startup -P tools/join_meshes.py -- <in.glb> <out.glb>
"""
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
before = len(meshes)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
joined = bpy.context.view_layer.objects.active
joined.name = joined.data.name = "model"
# drop the now-empty parents and helpers so the scene is just the one mesh
for o in list(bpy.context.scene.objects):
    if o != joined and o.type != "MESH":
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
joined.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
                          export_image_format="AUTO", export_yup=True)
print("JOINED %d meshes -> 1 mesh with %d materials -> %s" % (before, len(joined.data.materials), OUT))
