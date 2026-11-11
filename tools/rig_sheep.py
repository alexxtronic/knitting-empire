"""Turn a Tripo sheep export into a rigged, animated game sheep.

Run headless (Blender 5):
  Blender -b --factory-startup -P tools/rig_sheep.py -- <project_dir> <tripo.glb> <id>
          [--height 0.95] [--yaw 90] [--faces 40000] [--tex 2048] [--render DIR]

What it does:
  1. imports the export, joins it, turns it --yaw degrees (head to -Y here, +Z in Godot), scales it
     to --height metres and stands it on the floor, centred;
  2. decimates it to --faces (the old 5,000-face import melted the wool curls into lumps);
  3. finds the anatomy from the mesh itself: the four leg columns, where the legs meet the body, the
     head (everything above the body line in front of the forelegs) and the rump;
  4. builds a quadruped skeleton (Hips, Spine, Neck, Head, Tail, and an upper and lower bone per leg)
     and skins the mesh to it by region, with the head bound rigidly to the Head bone so the face
     never shears;
  5. keyframes three loops: Idle (breathing, a slow look about, a tail flick), Walk (a sheep's
     four-beat walk: left hind, left fore, right hind, right fore) and Graze (head down in the
     grass, chewing);
  6. shrinks the colour and normal textures to --tex and exports assets/props/<id>.glb.

It prints the Walk loop's ground speed (STRIDE), which scripts/sheep.gd uses so the hooves don't slide.
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, SRC, ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


HEIGHT = float(opt("--height", 0.95))
YAW = float(opt("--yaw", 90))
FACES = int(opt("--faces", 40000))
TEX = int(opt("--tex", 2048))
RENDER = opt("--render")
FPS = 24

# --- 1. import, join, orient, size -------------------------------------------------------------
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
ob.data.transform(ob.matrix_world)
ob.matrix_world = Matrix.Identity(4)
ob.data.transform(Matrix.Rotation(math.radians(YAW), 4, "Z"))
pts = [v.co for v in ob.data.vertices]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
ob.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
ob.data.transform(Matrix.Scale(HEIGHT / (hi.z - lo.z), 4))
ob.data.update()

# --- 2. decimate --------------------------------------------------------------------------------
if before > FACES:
    mod = ob.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = FACES / before
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
for p in ob.data.polygons:
    p.use_smooth = True
V = [v.co.copy() for v in ob.data.vertices]

# --- 3. anatomy ---------------------------------------------------------------------------------
y_min = min(p.y for p in V)
y_max = max(p.y for p in V)
feet = [p for p in V if p.z < 0.06]
cx = sum(p.x for p in feet) / len(feet)
cy = sum(p.y for p in feet) / len(feet)
cols = {}
for key, sx, sy in (("FL", -1, -1), ("FR", 1, -1), ("HL", -1, 1), ("HR", 1, 1)):
    q = [p for p in feet if (p.x - cx) * sx > 0 and (p.y - cy) * sy > 0]
    cols[key] = Vector((sum(p.x for p in q) / len(q), sum(p.y for p in q) / len(q), 0.0))
LX = (abs(cols["FL"].x) + abs(cols["FR"].x) + abs(cols["HL"].x) + abs(cols["HR"].x)) / 4
FY = (cols["FL"].y + cols["FR"].y) / 2
BY = (cols["HL"].y + cols["HR"].y) / 2
LEG_R = 0.075


def in_leg(p):
    return min((Vector((p.x, p.y, 0)) - c).length for c in cols.values()) < LEG_R


# the body's underside: the lowest height where something sits between the fore and hind legs
# (measured on the centre line, between the left and right legs, so no leg is counted)
mid_band = sorted(p.z for p in V if (FY + 0.05) < p.y < (BY - 0.05) and abs(p.x) < 0.04)
ZB = mid_band[len(mid_band) // 50]
# the back line, over the rump half; anything higher in front of the forelegs is the head
ZTOP = max(p.z for p in V if p.y > (FY + BY) / 2)
head_pts = [p for p in V if p.y < FY + 0.2 and p.z > ZTOP + 0.03]
ZH = ZTOP - 0.03  # where the head starts
HEAD_TOP = max(p.z for p in head_pts)
HEAD_Y = sum(p.y for p in head_pts) / len(head_pts)
ZBODY = (ZB + ZTOP) / 2
HEAD_BACK = max(p.y for p in head_pts)  # how far back the head (and its wool) reaches
print("ANATOMY legs x ±%.2f, fore y %.2f, hind y %.2f, belly %.2f, back %.2f, head from %.2f (top %.2f, y %.2f)" % (
    LX, FY, BY, ZB, ZTOP, ZH, HEAD_TOP, HEAD_Y))

# --- 4. skeleton --------------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("sheep_rig")
rig = bpy.data.objects.new("rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones


def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head, b.tail = Vector(head), Vector(tail)
    b.align_roll(Vector((0, 0, 1)) if abs(b.vector.normalized().z) < 0.9 else Vector((0, -1, 0)))
    if parent:
        b.parent = eb[parent]
    return b


neck_base = (0, FY, ZBODY + 0.04)
# the head pivots where the back of its wool cap meets the shoulders, so a nod barely moves the join
jaw = (0, HEAD_BACK - 0.04, ZH)
bone("Hips", (0, BY + 0.03, ZBODY), (0, (BY + FY) / 2, ZBODY))
bone("Spine", (0, (BY + FY) / 2, ZBODY), (0, FY, ZBODY + 0.02), "Hips")
bone("Neck", neck_base, jaw, "Spine")
bone("Head", jaw, (0, y_min + 0.04, (ZH + HEAD_TOP) / 2), "Neck")
bone("Tail", (0, y_max - 0.06, ZTOP - 0.06), (0, y_max + 0.03, ZTOP - 0.16), "Hips")
KNEE = ZB * 0.5
for key, c in cols.items():
    par = "Spine" if key[0] == "F" else "Hips"
    bone("Leg%s_upper" % key, (c.x, c.y, ZB + 0.06), (c.x, c.y, KNEE), par)
    bone("Leg%s_lower" % key, (c.x, c.y, KNEE), (c.x, c.y, 0.02), "Leg%s_upper" % key)
bpy.ops.object.mode_set(mode="OBJECT")


# --- 4b. skin weights by region -----------------------------------------------------------------
def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


groups = {b.name: ob.vertex_groups.new(name=b.name) for b in arm_data.bones}


def nearest_leg(p):
    return min(cols, key=lambda k: (Vector((p.x, p.y, 0)) - cols[k]).length)


for i, p in enumerate(V):
    w = {}
    # body: hips to spine along the back, the neck in front of the forelegs, the head above the body line
    t_sp = smooth(BY, FY, p.y)
    body = {"Hips": 1 - t_sp, "Spine": t_sp}
    nb = max(FY, HEAD_BACK - 0.04)  # the neck runs back as far as the head does
    if p.y < nb + 0.04 and p.z > ZBODY:
        t_n = smooth(nb + 0.04, nb - 0.08, p.y) * smooth(ZBODY, ZBODY + 0.1, p.z)
        body = {k: v * (1 - t_n) for k, v in body.items()}
        body["Neck"] = t_n
    if p.y < HEAD_BACK + 0.02:
        # rigid above the jaw line, fading over 5 cm. Above the back line it is all head (the wool
        # cap reaches back over the shoulders); level with the back it fades out toward the rump.
        above = smooth(ZTOP, ZTOP + 0.04, p.z)
        back_fade = smooth(HEAD_BACK - 0.06, HEAD_BACK + 0.02, p.y) * (1 - above)
        t_h = smooth(ZH - 0.04, ZH + 0.01, p.z) * (1 - back_fade)
        if t_h > 0:
            body = {k: v * (1 - t_h) for k, v in body.items()}
            body["Head"] = body.get("Head", 0) + t_h
    if p.y > y_max - 0.1 and p.z > ZTOP - 0.2:
        t_t = smooth(y_max - 0.1, y_max - 0.03, p.y)
        body = {k: v * (1 - t_t) for k, v in body.items()}
        body["Tail"] = t_t
    # legs: below the belly, near a leg column; fading into the body over the top of the leg
    t_leg = 0.0
    if in_leg(p) or p.z < ZB - 0.02:
        t_leg = 1 - smooth(ZB - 0.03, ZB + 0.06, p.z)
    if t_leg > 0:
        k = nearest_leg(p)
        t_lo = 1 - smooth(KNEE - 0.03, KNEE + 0.03, p.z)
        leg = {"Leg%s_upper" % k: 1 - t_lo, "Leg%s_lower" % k: t_lo}
        w = {kk: v * (1 - t_leg) for kk, v in body.items()}
        for kk, v in leg.items():
            w[kk] = w.get(kk, 0) + v * t_leg
    else:
        w = body
    for name, v in w.items():
        if v > 0.001:
            groups[name].add([i], v, "REPLACE")

ob.parent = rig
md = ob.modifiers.new("rig", "ARMATURE")
md.object = rig

# --- 5. animation loops -------------------------------------------------------------------------
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "QUATERNION"
rest = {b.name: b.bone.matrix_local.to_3x3() for b in pb}


def rq(name, axis, deg):
    """A rotation about a world axis (in the bone's rest frame), as the bone's local quaternion."""
    r = Matrix.Rotation(math.radians(deg), 3, Vector(axis))
    m = rest[name].inverted() @ r @ rest[name]
    return m.to_quaternion()


def compose(*qs):
    out = Quaternion()
    for q in qs:
        out = out @ q
    return out


X, Z, Y = (1, 0, 0), (0, 0, 1), (0, 1, 0)


def make_action(name, frames, pose_at):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in range(frames + 1):
        t = f / frames
        poses = pose_at(t)
        for b in pb:
            b.rotation_quaternion = poses.get(b.name, Quaternion())
            b.location = poses.get(b.name + ":loc", Vector())
            b.keyframe_insert("rotation_quaternion", frame=f + 1)
            b.keyframe_insert("location", frame=f + 1)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    rig.animation_data.action = None
    return act


TAU = math.tau
WALK_T = 0.9  # seconds per stride
SWING = 26.0  # degrees fore and aft at the shoulder and hip
PHASE = {"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}  # a sheep's lateral-sequence walk


def walk(t):
    p = {}
    for k, ph in PHASE.items():
        a = TAU * (t + ph)
        # +X rotation swings a hanging leg back, so forward is negative
        swing = -SWING * math.sin(a)
        lift = max(0.0, math.cos(a))  # the leg is coming forward: fold the lower leg up
        fold = (38.0 if k[0] == "F" else 30.0) * lift
        p["Leg%s_upper" % k] = rq("Leg%s_upper" % k, X, swing - fold * 0.35)
        p["Leg%s_lower" % k] = rq("Leg%s_lower" % k, X, fold)
    bob = math.sin(TAU * t * 2)
    p["Hips"] = compose(rq("Hips", Y, 2.0 * math.sin(TAU * t)), rq("Hips", X, 0.6 * bob))
    p["Hips:loc"] = Vector((0, 0.008 * bob, 0))
    p["Spine"] = rq("Spine", Y, -1.5 * math.sin(TAU * t))
    p["Neck"] = rq("Neck", X, 3.0 * math.sin(TAU * t * 2 + 0.6))
    p["Head"] = rq("Head", X, -2.0 * math.sin(TAU * t * 2 + 0.6))
    p["Tail"] = rq("Tail", Z, 8.0 * math.sin(TAU * t))
    return p


def idle(t):
    p = {}
    br = math.sin(TAU * t * 2)  # two breaths a loop
    p["Spine"] = rq("Spine", X, 0.8 * br)
    look = math.sin(TAU * t)
    p["Neck"] = compose(rq("Neck", Z, 9.0 * look), rq("Neck", X, 2.0 * br))
    p["Head"] = compose(rq("Head", Z, 6.0 * look), rq("Head", Y, 3.0 * math.sin(TAU * t + 1.0)))
    flick = max(0.0, math.sin(TAU * t * 3)) ** 6
    p["Tail"] = rq("Tail", Z, 25.0 * flick * math.sin(TAU * t * 9))
    return p


GRAZE_NECK = 18.0  # the neck tips down this far...
GRAZE_HEAD = 48.0  # ...and the head the rest of the way to the grass


def graze(t):
    p = {}
    chew = math.sin(TAU * t * 4)
    step = math.sin(TAU * t)
    p["Neck"] = compose(rq("Neck", X, GRAZE_NECK + 2.0 * math.sin(TAU * t * 2)), rq("Neck", Z, 6.0 * step))
    p["Head"] = compose(rq("Head", X, GRAZE_HEAD + 4.0 * chew), rq("Head", Z, 5.0 * step))
    p["Spine"] = rq("Spine", X, 6.0)
    # the forelegs splay a touch to reach down
    for k in ("FL", "FR"):
        p["Leg%s_upper" % k] = rq("Leg%s_upper" % k, X, -6.0)
    p["Tail"] = rq("Tail", Z, 6.0 * math.sin(TAU * t * 2))
    return p


make_action("Idle", int(4.0 * FPS), idle)
make_action("Walk", int(WALK_T * FPS), walk)
make_action("Graze", int(3.0 * FPS), graze)
bpy.context.scene.render.fps = FPS

# hoof travel per stride, measured: how far a planted hoof slides back while it's down
leg_len = ZB + 0.06 - 0.02
STRIDE = 2.0 * leg_len * math.sin(math.radians(SWING)) * 2.0 / WALK_T
print("STRIDE %.3f m/s (Walk loop at speed 1)" % STRIDE)

# --- 6. textures and export ---------------------------------------------------------------------
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
            if not to_norm and "Base Color" not in used:
                for l in [l for l in nt.links if l.from_node == n]:
                    nt.links.remove(l)
                continue
            img = n.image
            if max(img.size) > TEX:
                img.scale(TEX, TEX)
            img.name = "%s_%s" % (ID, "normal" if to_norm else "color")
    if bsdf:
        bsdf.inputs["Roughness"].default_value = 0.95
        bsdf.inputs["Metallic"].default_value = 0.0

ob.name = ob.data.name = "model"
out = os.path.join(PROJECT, "assets", "props", ID + ".glb")
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=90, export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True)
print("RIGGED %s: %d -> %d faces, %d bones, textures %d px -> %s" % (
    ID, before, len(ob.data.polygons), len(arm_data.bones), TEX, out))

# --- optional: contact sheet of the loops -------------------------------------------------------
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    sc.world = w
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 420, 420
    c = Vector((0, 0, HEIGHT * 0.45))
    views = {"side": Vector((2.2, 0.0, 0.5)), "front": Vector((1.2, -1.9, 0.6))}
    for act_name, fracs in (("Walk", (0.0, 0.25, 0.5, 0.75)), ("Graze", (0.0, 0.5)), ("Idle", (0.0,))):
        act = bpy.data.actions[act_name]
        rig.animation_data.action = act
        for tr in rig.animation_data.nla_tracks:
            tr.mute = True
        n = int(act.frame_range[1] - act.frame_range[0])
        for fr in fracs:
            sc.frame_set(int(1 + fr * n))
            for vn, off in views.items():
                cam.location = c + off
                cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
                sc.render.filepath = os.path.join(RENDER, "%s_%s_%02d_%s.png" % (ID, act_name, int(fr * 100), vn))
                bpy.ops.render.render(write_still=True)
    print("RENDERED", RENDER)
