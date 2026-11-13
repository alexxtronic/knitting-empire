"""Bring a character rigged by Mixamo's auto-rigger into the game's pipeline.

Mixamo's skinning (and its finger bones) beats what tools/rig_sculpt.py gets from Blender's bone heat on
a Tripo sculpt: its arms bend at the elbow and stay round, where ours curved like hoses on thin arms
(Sabrina). The upload is made by preparing the Tripo GLB as a zipped OBJ (T-pose, Y up, metres, base
colour only) and auto-rigging it on mixamo.com (Standard Skeleton, 65 bones); download FBX Binary, With
Skin, T-pose.

  Blender -b --factory-startup -P tools/import_mixamo.py -- <project_dir> <mixamo.fbx> <out_id> [--like <old.blend>] [--rig-name Name]

It:
  1. imports the FBX and bakes Mixamo's centimetre scale and Y-up turn into the armature, so the rig sits at
     identity like every other character rig (tools/retarget_anims.py asserts that);
  2. renames the bones the game knows to its names (Hips, Spine, Chest, UpperChest, Neck, Head,
     LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, LeftToes, and
     the right side); the fingers keep Mixamo's names (LeftHandIndex1 ...) without the "mixamorig:" prefix;
  3. gives the mesh a plain material with its base colour packed in (the FBX carries it);
  4. makes the head rigid (tools/rigid_head.py);
  5. keeps the seated anchor of --like (the old rig's SitIdle hips, moved by how far Mixamo put the hip
     joint from the old one, so the body still lands on the chair: tools/retarget_anims.py reads
     rig["seat_SitIdle"]) and its armature's name (a new character has no --like: --rig-name names the
     armature, and tools/retarget_anims.py seats its loops on the origin);
  6. saves tools/character_build/<out_id>/<out_id>.blend and exports assets/<out_id>.glb (no loops yet:
     run tools/retarget_anims.py on the blend next).
"""
import bpy, os, sys
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, FBX, OUT_ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
LIKE = argv[argv.index("--like") + 1] if "--like" in argv else None
RIG_NAME = argv[argv.index("--rig-name") + 1] if "--rig-name" in argv else "Rig"

NAMES = {
    "Hips": "Hips", "Spine": "Spine", "Spine1": "Chest", "Spine2": "UpperChest", "Neck": "Neck", "Head": "Head",
    "LeftShoulder": "LeftShoulder", "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand",
    "RightShoulder": "RightShoulder", "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm", "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes",
    "RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToes",
}

# ---- what to keep from the old rig
rig_name, seat, old_hips, fps = RIG_NAME, None, None, 30
if LIKE:
    with bpy.data.libraries.load(LIKE) as (src, dst):
        dst.objects = list(src.objects)
        dst.actions = [a for a in src.actions if a == "SitIdle"]
    old = next(o for o in dst.objects if o and o.type == "ARMATURE")
    rig_name = old.name
    old_hips = old.data.bones["Hips"].head_local.copy()
    if dst.actions:
        sc_ = bpy.context.scene
        sc_.collection.objects.link(old)
        old.animation_data_create()
        old.animation_data.use_nla = False
        a = dst.actions[0]
        old.animation_data.action = a
        if a.slots:
            old.animation_data.action_slot = a.slots[0]
        f0, f1 = (int(x) for x in a.frame_range)
        acc = Vector()
        for f in range(f0, f1):
            sc_.frame_set(f)
            acc += old.pose.bones["Hips"].head
        seat = acc / (f1 - f0)
    print("LIKE", os.path.basename(LIKE), "armature", rig_name, "seat", seat and tuple(round(v, 3) for v in seat))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = fps

# ---- 1. import, bake the transform into the armature
bpy.ops.import_scene.fbx(filepath=FBX, automatic_bone_orientation=False, global_scale=100.0)  # Mixamo writes centimetres
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
body = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.parent == rig)
for o in list(bpy.context.scene.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)
rig.animation_data_clear()
# bake each one's world transform on its own (applying the parent's scale doesn't carry into the child's
# vertices), then parent the mesh back with nothing between them
mw = body.matrix_world.copy()
body.parent = None
body.matrix_world = mw
for o in (rig, body):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.parent = rig
body.matrix_parent_inverse = Matrix.Identity(4)
for pb in rig.pose.bones:
    pb.rotation_mode = "XYZ"                 # tools/retarget_anims.py keys Euler angles, as our other rigs use
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
top = max((body.matrix_world @ v.co).z for v in body.data.vertices)
print("IMPORTED", rig.name, len(rig.data.bones), "bones; mesh", len(body.data.polygons), "faces, height", round(top, 3))

# ---- 2. bone names (vertex groups follow a renamed bone)
for b in rig.data.bones:
    short = b.name.split(":")[-1]
    b.name = NAMES.get(short, short)
missing = [n for n in NAMES.values() if n not in rig.data.bones]
assert not missing, "bones not found: %s" % missing
rig.name = rig.data.name = rig_name
body.name = body.data.name = OUT_ID + "Mesh"
mod = next((m for m in body.modifiers if m.type == "ARMATURE"), None) or body.modifiers.new("Armature", "ARMATURE")
mod.object = rig

# ---- 3. material: the base colour, packed
img = next((i for i in bpy.data.images if i.size[0] > 0 and i.name not in ("Render Result", "Viewer Node")), None)
assert img is not None, "no texture in the FBX"
img.name = OUT_ID + "_albedo"
img.pack()
m = bpy.data.materials.new(OUT_ID.split("_")[0].capitalize())
m.use_nodes = True
nt = m.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
body.data.materials.clear()
body.data.materials.append(m)
for p in body.data.polygons:
    p.use_smooth = True

# ---- 4. rigid head
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rigid_head  # noqa: E402
rigid_head.make_rigid(body, rig)

# ---- 5. seat anchor for seated loops
if seat is not None:
    # the anchor is where the hip joint sits; Mixamo's is higher than ours (Sabrina's by 11 cm), and the
    # body hangs from it, so the joint has to sit that much higher too
    rig["seat_SitIdle"] = list(seat - old_hips + rig.data.bones["Hips"].head_local)
    print("SEAT", tuple(round(v, 3) for v in rig["seat_SitIdle"]), "hip joint moved by",
          tuple(round(v, 3) for v in rig.data.bones["Hips"].head_local - old_hips))
rig.animation_data_create()

# ---- 6. save, export
build = os.path.join(PROJECT, "tools", "character_build", OUT_ID)
os.makedirs(build, exist_ok=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, OUT_ID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(PROJECT, "assets", OUT_ID + ".glb"), export_format="GLB",
                          export_apply=True, export_yup=True, export_cameras=False, export_lights=False,
                          export_skins=True, export_animations=False)
print("SAVED", OUT_ID, "bones", len(rig.data.bones))
