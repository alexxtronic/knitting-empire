"""Put a sculpted body on a character's existing rig and animations.

Run headless:
  Blender -b tools/character_build/<id>/<id>.blend -P tools/rig_sculpt.py -- \
      <project_dir> <colored.ply> <out_id> [--faces 24000] [--tex 2048] [--render DIR]

Takes a vertex-coloured mesh (from image-to-sculpt plus tools/project_colors.py, in its frame: +Z up,
facing -Y, any scale) and the character .blend made by tools/build_character.py, then:

  1. scales the sculpt to the rig's height, feet on the ground, torso over the spine;
  2. decimates it to a game budget, unwraps it and bakes the vertex colours into one texture;
  3. aims a copy of the rig's arms along the sculpt's arms (generated turnarounds stand in a wider
     A-pose than the rig), binds the mesh to it with automatic weights, swings the arms back to
     the rig's rest pose and applies that, so the mesh now matches the real rig's rest pose;
  4. swaps the procedural body for the sculpt on the real rig (bones, animations and knitting
     props are untouched) and exports assets/<out_id>.glb, plus a turntable/pose check with --render.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, PLY, OUT_ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
FACES = int(argv[argv.index("--faces") + 1]) if "--faces" in argv else 24000
TEX = int(argv[argv.index("--tex") + 1]) if "--tex" in argv else 2048
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None

scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == "ARMATURE")
old_body = next(o for o in scene.objects if o.type == "MESH" and o.parent == rig and o.name != "KnitProps")
bones = rig.data.bones
head_top = max((old_body.matrix_world @ Vector(c)).z for c in old_body.bound_box)
print("RIG", rig.name, "body", old_body.name, "height", round(head_top, 3))


def select_only(*objs):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    for o in scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


# ----------------------------------------------------------------------------- 1. import and place
bpy.ops.wm.ply_import(filepath=PLY)
hi = bpy.context.selected_objects[0]
hi.name = OUT_ID + "_hi"
V = np.array([v.co[:] for v in hi.data.vertices])
z0, h = V[:, 2].min(), V[:, 2].max() - V[:, 2].min()
s = head_top / h
torso = V[(V[:, 2] - z0 > 0.59 * h) & (V[:, 2] - z0 < 0.73 * h)]
cx, cy = np.median(torso[:, 0]), np.median(torso[:, 1])
hi.data.transform(Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation((-cx, -cy, -z0)))
hi.data.update()
print("SCULPT scale", round(s, 4), "verts", len(hi.data.vertices))

# ----------------------------------------------------------------------------- 2. game mesh + texture
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = lo.data.name = OUT_ID + "Mesh"
scene.collection.objects.link(lo)
select_only(lo)
dec = lo.modifiers.new("dec", "DECIMATE")
dec.ratio = min(1.0, FACES / len(hi.data.polygons))
bpy.ops.object.modifier_apply(modifier="dec")
sm = lo.modifiers.new("smooth", "LAPLACIANSMOOTH")  # irons out the ripples a silhouette-only fit leaves
sm.iterations, sm.lambda_factor, sm.use_volume_preserve = 6, 0.6, True
bpy.ops.object.modifier_apply(modifier="smooth")
for p in lo.data.polygons:
    p.use_smooth = True
print("GAME MESH faces", len(lo.data.polygons))

bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

img = bpy.data.images.new(OUT_ID + "_albedo", TEX, TEX)
img.colorspace_settings.name = "sRGB"


def color_material(name, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    if image is None:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = hi.data.color_attributes[0].name
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(attr.outputs["Color"], em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    else:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


hi.data.materials.clear()
hi.data.materials.append(color_material("bake_src"))
lo.data.materials.clear()
skin = color_material(OUT_ID.capitalize(), img)
lo.data.materials.append(skin)
skin.node_tree.nodes.active = next(n for n in skin.node_tree.nodes if n.type == "TEX_IMAGE")

scene.render.engine = "CYCLES"
scene.cycles.samples = 1
scene.cycles.device = "CPU"
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.02
scene.render.bake.max_ray_distance = 0.05
scene.render.bake.margin = 6
select_only(lo, hi)
hi.select_set(True)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type="EMIT")
img.pack()  # embedded in the .glb; Godot extracts it on import as assets/<id>_<id>_albedo.png
print("BAKED", img.name, TEX)
bpy.data.objects.remove(hi)

# ----------------------------------------------------------------------------- 3. bind in the sculpt's pose
L = np.array([v.co[:] for v in lo.data.vertices])
temp = rig.copy()
temp.data = rig.data.copy()
temp.animation_data_clear()
scene.collection.objects.link(temp)
for pb in temp.pose.bones:  # the copy keeps whatever pose the rig was last evaluated in; start from rest
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
swing = {}
select_only(temp)
bpy.ops.object.mode_set(mode="EDIT")
eb = temp.data.edit_bones
for side, sx in (("Left", 1), ("Right", -1)):
    sh = eb[side + "UpperArm"].head.copy()
    tip = eb[side + "Hand"].tail.copy()
    # the arm's vertices: outboard of the torso, between hand and armpit height
    z_lo, z_hi = tip.z + 0.06, sh.z - 0.30
    torso_w = 0.115 * head_top  # hips and ribs stay inside this; the hanging arm is outside it
    arm = L[(L[:, 2] > z_lo) & (L[:, 2] < z_hi) & (L[:, 0] * sx > torso_w)]
    c = arm.mean(0)
    d = np.linalg.svd(arm - c)[2][0]
    d = d if d[2] < 0 else -d
    want = Vector((d[0], 0.0, d[2])).normalized()
    have = Vector((tip.x - sh.x, 0.0, tip.z - sh.z)).normalized()
    ang = math.atan2(have.cross(want).y, have.dot(want))
    R = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh)
    for b in ("UpperArm", "LowerArm", "Hand"):
        eb[side + b].transform(R)
    swing[side] = (sh, -ang)
    print("ARM", side, "verts", len(arm), "rig", round(math.degrees(math.atan2(abs(have.x), -have.z)), 1),
          "sculpt", round(math.degrees(math.atan2(abs(want.x), -want.z)), 1), "deg")
bpy.ops.object.mode_set(mode="OBJECT")

select_only(lo, temp)
lo.select_set(True)
bpy.context.view_layer.objects.active = temp
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("WEIGHTS groups", len(lo.vertex_groups))

# swing the arms back to the real rig's rest angle and bake that into the mesh
select_only(temp)
bpy.ops.object.mode_set(mode="POSE")
for side, (sh, ang) in swing.items():
    pb = temp.pose.bones[side + "UpperArm"]
    pb.matrix = Matrix.Translation(sh) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Translation(-sh) @ pb.bone.matrix_local
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")
select_only(lo)
mod = next(m for m in lo.modifiers if m.type == "ARMATURE")
bpy.ops.object.modifier_apply(modifier=mod.name)
lo.parent = None
lo.matrix_world = Matrix.Identity(4)
bpy.data.objects.remove(temp)

# ----------------------------------------------------------------------------- 4. onto the real rig, export
bpy.data.objects.remove(old_body)
lo.parent = rig
am = lo.modifiers.new("Armature", "ARMATURE")
am.object = rig
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()

assets = os.path.join(PROJECT, "assets")
build = os.path.join(PROJECT, "tools", "character_build", OUT_ID)
os.makedirs(build, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, OUT_ID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(assets, OUT_ID + ".glb"), export_format="GLB", export_apply=True,
                          export_yup=True, export_cameras=False, export_lights=False, export_skins=True,
                          export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True)
print("EXPORTED", os.path.join(assets, OUT_ID + ".glb"), "faces", len(lo.data.polygons))

# ----------------------------------------------------------------------------- check renders
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 480, 720
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam

    rig.animation_data.use_nla = False  # the stored NLA tracks would blend every loop together

    def shoot(path, yaw_deg, action=None, frame=0):
        rig.animation_data.action = bpy.data.actions[action] if action else None
        if action is None:
            for pb in rig.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
        scene.frame_set(frame)
        a = math.radians(yaw_deg)
        cam.location = (3.2 * math.sin(a), -3.2 * math.cos(a), 1.0)
        cam.rotation_euler = (math.radians(88), 0, a)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    for yaw in (0, 45, 90, 180, 270):
        shoot(os.path.join(RENDER, f"turn_{yaw:03d}.png"), yaw)
    for act in ("Idle", "Walk", "SitKnit", "Talk", "Work"):
        rng = bpy.data.actions[act].frame_range
        shoot(os.path.join(RENDER, f"pose_{act}.png"), 30, act, int((rng[0] + rng[1]) / 2))
    print("RENDERED", RENDER)
