"""
Review sheet for a model made by tools/add_eyes.py: the eyes at rest, blinking, looking about
and in each lid shape, flat-lit with the painted texture (what the face colours really are).

  Blender -b tools/character_build/nora_tripo_eyes/nora_tripo_eyes.blend -P tools/add_eyes_review.py -- <out dir>

Writes one PNG per state; tools/character_build/<id>_eyes/sheet.py (or any image tool) lays them out.
"""
import bpy, sys, os, math
from mathutils import Vector, Matrix

out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
eyes = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("Eyes"))
arm.data.pose_position = "POSE"
for o in bpy.data.objects:
    if o.name == "KnitProps":
        o.hide_render = True
arm.animation_data_clear()
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.color_type, sh.show_cavity, sh.show_shadows = "FLAT", "TEXTURE", False, False
# the game draws these materials two-sided unless Blender's backface culling is on for them: do the same here
sh.show_backface_culling = all(m.use_backface_culling for o in (eyes,) for m in o.data.materials)
print("CULL", [(m.name, m.use_backface_culling) for m in eyes.data.materials])
sc.display.render_aa = "8"
sc.view_settings.view_transform = "Standard"
sh.background_type, sh.background_color = "VIEWPORT", (1, 1, 1)
if hasattr(sc.render.image_settings, "media_type"):
    sc.render.image_settings.media_type = "IMAGE"
sc.render.image_settings.file_format = "PNG"
sc.render.film_transparent = False
cd = bpy.data.cameras.new("C")
cd.type = "ORTHO"
cam = bpy.data.objects.new("C", cd)
sc.collection.objects.link(cam)
sc.camera = cam
head_z = (arm.matrix_world @ arm.data.bones["LeftEye"].head_local).z


def look(yaw, pitch):
    """Turn both eyes: yaw to her left (+), pitch up (+), in degrees."""
    for n in ("LeftEye", "RightEye"):
        pb = arm.pose.bones[n]
        rest = pb.bone.matrix_local
        c = rest.to_translation()
        rot = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "X")
        pb.matrix_basis = rest.inverted() @ Matrix.Translation(c) @ rot @ Matrix.Translation(-c) @ rest     # the Head is at rest
    bpy.context.view_layer.update()


def shot(name, az, keys=None, yaw=0.0, pitch=0.0, wide=0.27, tall=0.15, res=1040, zc=None, xc=0.0):
    for kb in eyes.data.shape_keys.key_blocks[1:]:
        kb.value = (keys or {}).get(kb.name, 0.0)
    look(yaw, pitch)
    sc.render.resolution_x, sc.render.resolution_y = res, int(res * tall / wide)
    cd.ortho_scale = wide
    t = Vector((xc, -0.08, head_z + 0.004 if zc is None else zc))
    a = math.radians(az)
    cam.location = t + Vector((math.sin(a), -math.cos(a), 0)) * 4
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)


B = {"blink_L": 1.0, "blink_R": 1.0}
if "--debug" in sys.argv:          # one eye, very close, closed: with and without back faces hidden
    ex = (arm.matrix_world @ arm.data.bones["RightEye"].head_local).x
    shot("d1_closed_culled", 0, B, wide=0.075, tall=0.05, res=1200, xc=ex)
    sh.show_backface_culling = False
    shot("d2_closed_all", 0, B, wide=0.075, tall=0.05, res=1200, xc=ex)
    shot("d3_half_all", 0, {"blink_R": 0.5}, wide=0.075, tall=0.05, res=1200, xc=ex)
    sys.exit(0)
shot("01_rest", 0)
shot("02_blink_half", 0, {"blink_L": 0.5, "blink_R": 0.5})
shot("03_blink_closed", 0, B)
shot("04_wink", 0, {"blink_L": 1.0})
shot("05_look_left", 0, yaw=11)
shot("06_look_right", 0, yaw=-11)
shot("07_look_up", 0, pitch=-8)
shot("08_look_down", 0, pitch=8)
shot("09_happy", 0, {"squint": 1.0})
shot("10_sleepy", 0, {"lid_half": 1.0})
shot("11_angry", 0, {"lid_angry": 1.0})
shot("12_sad", 0, {"lid_sad": 1.0})
shot("13_rest_three_quarter", 35)
shot("14_closed_three_quarter", 35, B)
shot("15_rest_side", 80)
shot("16_face_rest", 0, wide=0.36, tall=0.36, res=800, zc=head_z - 0.03)
shot("17_face_closed", 0, B, wide=0.36, tall=0.36, res=800, zc=head_z - 0.03)
shot("18_face_happy", 0, {"squint": 1.0}, wide=0.36, tall=0.36, res=800, zc=head_z - 0.03)
print("REVIEW", out)
