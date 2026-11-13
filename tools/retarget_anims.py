"""Put motion-captured loops from a humanoid animation library onto a character's rig.

Run headless on a character .blend (one made by build_character.py or rig_sculpt.py):
  Blender -b tools/character_build/<id>/<id>.blend -P tools/retarget_anims.py -- \
      <project_dir> <library.glb> <out_id> [--map Idle=Idle_Loop,Walk=Walk_Loop,...] [--arm-spread DEG] [--render DIR]

Made for Quaternius's Universal Animation Library (CC0, Unreal-style bone names, T-pose, 24 fps,
the in-place file without root motion), but any library on that skeleton works. For each of our
loops named in --map it:

  1. poses the library skeleton so every bone points the way ours does at rest (our arms hang in an
     A-pose, theirs stand out in a T-pose), and takes that as the reference pose;
  2. samples the clip at our frame rate and gives each of our bones the same world-space turn away
     from the reference pose as the library bone has, so the motion survives different rest poses,
     bone rolls and proportions;
  3. moves the hips by the library's hip motion scaled to our leg length, removes any drift so the
     loop closes, and sets standing loops' feet on the ground; seated loops keep the old loop's
     hip position so the character still lands on the chair;
  4. writes the keys into our existing action of that name (so the NLA tracks and every other loop
     are untouched), deletes the library, saves tools/character_build/<out_id>/<out_id>.blend and
     exports assets/<out_id>.glb.

--same-bones takes the loops from one of our own rigs instead (its bones carry our names), such as the
character's previous rig: its clips are renamed "lib_<name>" so they don't clash with ours. A rig made by
tools/import_mixamo.py has no SitKnit (the library has no knitting), so it borrows the old rig's:
  ... -P tools/retarget_anims.py -- "$PWD" <old_rig.glb> <out_id> --same-bones --map SitKnit=lib_SitKnit

Loops not named in --map keep their old keys (SitKnit's knitting hands, for instance); a name the
rig doesn't have yet (Run) gets a new action set up like the others.

A --map entry is Loop=Clip, with two optional extras: "Clip:a-b" loops only frames a..b and blends
the seam ("Fixing_Kneeling:30-118" stays kneeling), and "Clip*s" scales the stride (the library's
walk is a slow stroll and its jog a fast one: "Walk_Loop*1.3" and "Jog_Fwd_Loop*0.7" suit a 1.3 m/s
walk and a 3 m/s jog). Brisk is the same walk with a longer stride, for the player's 2 m/s walk: the
stroll played fast enough to cover that ground has her legs scurrying. For Walk, Brisk and Run it
prints the stride speed, the ground speed the planted foot implies; put those in
data/characters.json as walk_anim_speed, brisk_anim_speed and run_anim_speed.
"""
import bpy, math, os, sys
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
PROJECT, LIB, OUT_ID = os.path.abspath(argv[0]), os.path.abspath(argv[1]), argv[2]
DEFAULT_MAP = ("Idle=Idle_Loop,Walk=Walk_Loop*1.3,Brisk=Walk_Loop*1.4,Run=Jog_Fwd_Loop*0.7,Talk=Idle_Talking_Loop,"
               "SitIdle=Sitting_Idle_Loop,Work=Fixing_Kneeling:30-118")
MAP = dict(kv.split("=") for kv in (argv[argv.index("--map") + 1] if "--map" in argv else DEFAULT_MAP).split(","))
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None
# degrees each arm is held further out from the body in every standing loop: the library's arms hang
# close to a slim body, and on a wide one (an apron, a flared jacket) the hands sink into the hips
SPREAD = math.radians(float(argv[argv.index("--arm-spread") + 1])) if "--arm-spread" in argv else 0.0
SEATED = {"SitIdle", "SitKnit"}

# our bone <- library bone (Unreal mannequin names, as Quaternius uses)
BONES = {
    "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
    "Neck": "neck_01", "Head": "Head",
    "LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
    "RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
    "LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
    "RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
}
SAME = "--same-bones" in argv
if SAME:
    BONES = {n: n for n in BONES}

scene = bpy.context.scene
FPS = scene.render.fps
rig = next(o for o in scene.objects if o.type == "ARMATURE")
assert rig.matrix_world.to_3x3().is_identity or (rig.matrix_world.to_3x3() - Matrix.Identity(3)).median_scale < 1e-4
T = rig.data.bones
# parents before children; only the bones the library drives (a Mixamo rig's fingers and end bones stay at rest)
order = [b for b in sorted(T, key=lambda b: len(b.parent_recursive)) if b.name in BONES]
our_actions = {a.name for a in bpy.data.actions}
rig.animation_data.action = None
use_nla = rig.animation_data.use_nla
rig.animation_data.use_nla = False  # the stored NLA tracks would blend every loop together


def update():
    bpy.context.view_layer.update()


def hips_head(action, frames):
    """Mean armature-space position of the Hips over a loop, for seated anchoring."""
    rig.animation_data.action = action
    acc = Vector()
    for f in frames:
        scene.frame_set(f)
        acc += rig.pose.bones["Hips"].head
    rig.animation_data.action = None
    return acc / len(frames)


def lowest_foot(action, frames):
    rig.animation_data.action = action
    lows = []
    for f in frames:
        scene.frame_set(f)
        lows.append(min(rig.pose.bones[n].tail.z for n in ("LeftToes", "RightToes", "LeftFoot", "RightFoot")))
    rig.animation_data.action = None
    return lows


# --------------------------------------------------------------------------- old seated anchors
anchors = {}
for name in MAP:
    if name in SEATED and name in bpy.data.actions:
        a = bpy.data.actions[name]
        f0, f1 = (int(x) for x in a.frame_range)
        anchors[name] = hips_head(a, range(f0, f1))
    elif name in SEATED and "seat_" + name in rig:      # a new rig (tools/import_mixamo.py) keeps the old one's seat
        anchors[name] = Vector(rig["seat_" + name])
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
update()
rest_low = min(rig.pose.bones[n].tail.z for n in ("LeftToes", "RightToes", "LeftFoot", "RightFoot"))

# --------------------------------------------------------------------------- 1. the library
before = set(scene.objects)
bpy.ops.import_scene.gltf(filepath=LIB)
new = [o for o in scene.objects if o not in before]
src = next(o for o in new if o.type == "ARMATURE")
for o in new:
    if o.type == "MESH":
        bpy.data.objects.remove(o)
SW = src.matrix_world.copy()
assert (SW.to_3x3() - Matrix.Identity(3)).median_scale < 1e-4, "library armature is rotated or scaled"
lib_actions = [a for a in bpy.data.actions if a.name not in our_actions]
if SAME:
    for a in lib_actions:
        a.name = "lib_" + a.name.split(".")[0]
print("LIB CLIPS", sorted(a.name for a in lib_actions))
src.animation_data_create()
src.animation_data.action = None
for t in list(src.animation_data.nla_tracks):
    src.animation_data.nla_tracks.remove(t)
for pb in src.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
update()

# reference pose: each mapped library bone turned to point the way ours does at rest
for b in order:
    sb = src.pose.bones[BONES[b.name]]
    have = (sb.tail - sb.head).normalized()
    want = (b.tail_local - b.head_local).normalized()
    q = have.rotation_difference(want)
    sb.matrix = Matrix.Translation(sb.head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-sb.head) @ sb.matrix
    update()
ref = {b.name: src.pose.bones[BONES[b.name]].matrix.to_3x3().normalized() for b in order}
ref_inv = {k: v.inverted() for k, v in ref.items()}
rest_rot = {b.name: b.matrix_local.to_3x3().normalized() for b in order}
src_pelvis0 = src.pose.bones[BONES["Hips"]].head.copy()
# the hips move as far as the library's, scaled to our legs; the same body on another rig moves them as far
k_leg = 1.0 if SAME else T["LeftUpperLeg"].head_local.z / src.data.bones[BONES["LeftUpperLeg"]].head_local.z
print("HIPS AT REST: ours", tuple(round(v, 3) for v in T["Hips"].head_local), "library's", tuple(round(v, 3) for v in src_pelvis0))
print("LIB", os.path.basename(LIB), "clips", len(lib_actions), "leg scale", round(k_leg, 3))


def channelbag(action):
    slot = action.slots[0]
    strip = action.layers[0].strips[0]
    return strip.channelbag(slot, ensure=True)


def write(action, keys, hips_loc):
    """keys: {bone: [Euler per frame]}, hips_loc: [Vector per frame] -> replaces the action's curves."""
    cb = channelbag(action)
    cb.fcurves.clear()
    n = len(hips_loc)
    for bone, eul in keys.items():
        for i in range(3):
            fc = cb.fcurves.new(f'pose.bones["{bone}"].rotation_euler', index=i)
            fc.keyframe_points.add(n)
            fc.keyframe_points.foreach_set("co", [v for f in range(n) for v in (f, eul[f][i])])
            fc.update()
    for i in range(3):
        fc = cb.fcurves.new('pose.bones["Hips"].location', index=i)
        fc.keyframe_points.add(n)
        fc.keyframe_points.foreach_set("co", [v for f in range(n) for v in (f, hips_loc[f][i])])
        fc.update()
    action.use_frame_range = True
    action.frame_range = (0, n - 1)


# --------------------------------------------------------------------------- 2-4. each loop
def sample(t):
    """The library pose at time t: each of our bones' wanted armature-space rotation, and the hips."""
    scene.frame_set(int(t), subframe=t - int(t))
    want = {b.name: (src.pose.bones[BONES[b.name]].matrix.to_3x3().normalized() @ ref_inv[b.name]
                     @ rest_rot[b.name]).to_quaternion() for b in order}
    head = T["Hips"].head_local + (src.pose.bones[BONES["Hips"]].head - src_pelvis0) * k_leg
    return want, head


SEAM = 12  # frames blended into the start when a loop is cut from the middle of a clip

STRIDE_BONES = ("UpperLeg", "LowerLeg", "Foot", "Toes", "UpperArm", "LowerArm", "Hand")


def mean_quat(qs):
    acc = Quaternion((0, 0, 0, 0))
    for q in qs:
        acc += q if acc.dot(q) >= 0 else -q
    return acc.normalized()


def stride_speed(action, n):
    """Ground speed the loop's feet imply: how fast the planted (lowest) foot slides back, m/s."""
    rig.animation_data.action = action
    prev, dist, count = None, 0.0, 0
    for f in range(n + 1):
        scene.frame_set(f)
        feet = {s: rig.pose.bones[s + "Foot"].tail.copy() for s in ("Left", "Right")}
        low = min(feet, key=lambda s: feet[s].z)
        if prev and prev[0] == low and feet[low].z < rest_low + 0.03:  # planted, not mid-air
            dist += abs(feet[low].y - prev[1].y)
            count += 1
        prev = (low, feet[low])
    rig.animation_data.action = None
    return dist / count * FPS if count else 0.0


def ensure_action(name):
    """Our action of that name, or a new one set up like build_character.py's (slot, NLA track)."""
    if name in bpy.data.actions:
        return bpy.data.actions[name]
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = act.slots.new(id_type="OBJECT", name=rig.name)
    act.layers.new("Layer").strips.new(type="KEYFRAME").channelbag(slot, ensure=True)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    return act


for name, spec in MAP.items():
    # "Clip" loops the whole clip; "Clip:a-b" loops frames a..b of it (our frame rate: the importer
    # already retimed the clip) and blends the last SEAM frames into the frames before a, so the cut
    # doesn't show (Fixing_Kneeling:30-118 keeps her kneeling instead of getting up every loop).
    # "Clip*s" scales the stride: legs and arm swing turn s times as far from their average pose,
    # and the hips bob s times as much (Jog_Fwd_Loop*0.7 is a lighter jog that covers less ground).
    spec, _, stride = spec.partition("*")
    stride = float(stride) if stride else 1.0
    clip, _, cut = spec.partition(":")
    act = bpy.data.actions[clip]
    s0, s1 = act.frame_range
    if cut:
        a, b = (float(x) for x in cut.split("-"))
        seam = int(min(SEAM, a - s0))
        s0, s1 = a, b
    else:
        seam = 0
    span = s1 - s0
    n = max(2, round(span))  # frame n repeats frame 0
    src.animation_data.action = act
    if act.slots:
        src.animation_data.action_slot = act.slots[0]
    poses, hips = [], []
    for i in range(n + 1):
        t = s0 + span * (i % n) / n
        want, head = sample(t)
        if seam and n - seam <= i < n:
            w = (i - (n - seam)) / seam
            want2, head2 = sample(t - span)
            want = {k: q.slerp(want2[k], w) for k, q in want.items()}
            head = head.lerp(head2, w)
        poses.append(want)
        hips.append(head)
    if stride != 1.0:
        # scale each limb bone's swing relative to its parent (world swings would drag children
        # along twice), then rebuild the limbs parents-first from the scaled swings
        scaled = [s + p for s in ("Left", "Right") for p in STRIDE_BONES]
        rel = {bn: [p[T[bn].parent.name].inverted() @ p[bn] for p in poses] for bn in scaled}
        mean = {bn: mean_quat(r[:-1]) for bn, r in rel.items()}
        for f, p in enumerate(poses):
            for b in order:
                if b.name in scaled:
                    m, r = mean[b.name], rel[b.name][f]
                    d = m.inverted() @ (r if m.dot(r) >= 0 else -r)  # swing away from the average
                    p[b.name] = p[b.parent.name] @ m @ Quaternion(d.axis, d.angle * stride)
        mid = sum((h.z for h in hips[:-1]), 0.0) / n
        hips = [Vector((h.x, h.y, mid + (h.z - mid) * stride)) for h in hips]
    if SPREAD and name not in SEATED:
        # turn the whole arm out about the chest's own front-to-back axis, so it stays a sideways
        # spread however the body leans; forearm and hand turn with it and keep their bend
        for p in poses:
            for side, sx in (("Left", 1), ("Right", -1)):
                ua = side + "UpperArm"
                par = T[ua].parent.name
                axis = (p[par] @ rest_rot[par].to_quaternion().inverted()) @ Vector((0, 1, 0))
                r = Quaternion(axis, -SPREAD * sx)
                for b in ("UpperArm", "LowerArm", "Hand"):
                    p[side + b] = r @ p[side + b]
    rot_keys = {b.name: [] for b in order}
    for want in poses:
        want = {k: q.to_matrix() for k, q in want.items()}
        for b in order:
            if b.parent is None:
                local = rest_rot[b.name].inverted() @ want[b.name]
            else:
                local = (rest_rot[b.name].inverted() @ rest_rot[b.parent.name]
                         @ want[b.parent.name].inverted() @ want[b.name])
            prev = rot_keys[b.name][-1] if rot_keys[b.name] else None
            rot_keys[b.name].append(local.to_euler("XYZ", prev) if prev else local.to_euler("XYZ"))
    # close the loop: take out any drift so the last frame lands on the first
    drift = hips[-1] - hips[0]
    hips = [h - drift * (i / n) for i, h in enumerate(hips)]
    if name in anchors:
        mean = sum(hips[:-1], Vector()) / n
        hips = [h + (anchors[name] - mean) for h in hips]
    loc = [rest_rot["Hips"].inverted() @ (h - T["Hips"].head_local) for h in hips]
    rig_act = ensure_action(name)
    write(rig_act, rot_keys, loc)
    note = ""
    if name not in SEATED:
        lows = lowest_foot(rig_act, range(0, n))
        lows = sorted(lows)[:max(1, len(lows) // 4)]  # the planted moments (a jog has a flight phase)
        dz = rest_low - sum(lows) / len(lows)
        loc = [l + rest_rot["Hips"].inverted() @ Vector((0, 0, dz)) for l in loc]
        write(rig_act, rot_keys, loc)
        note = f"feet {dz:+.3f} m"
    if name in ("Walk", "Brisk", "Run"):
        note += f" stride speed {stride_speed(rig_act, n):.2f} m/s"
    print("LOOP", name, "<-", spec, "x", stride, "frames", n, "seam", seam, "drift", round(drift.length, 3), note)

# --------------------------------------------------------------------------- clean up, save, export
src.animation_data.action = None
bpy.data.objects.remove(src)
for a in lib_actions:
    bpy.data.actions.remove(a)
for a in list(bpy.data.armatures):
    if a.users == 0:
        bpy.data.armatures.remove(a)
rig.animation_data.action = None
rig.animation_data.use_nla = use_nla
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
scene.frame_set(0)
build = os.path.join(PROJECT, "tools", "character_build", OUT_ID)
os.makedirs(build, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(build, OUT_ID + ".blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(PROJECT, "assets", OUT_ID + ".glb"), export_format="GLB",
                          export_apply=True, export_yup=True, export_cameras=False, export_lights=False,
                          export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True)
print("EXPORTED", OUT_ID, sorted(a.name for a in bpy.data.actions))

# --------------------------------------------------------------------------- check renders
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x, scene.render.resolution_y = 300, 450
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.0
    rig.animation_data.use_nla = False
    for name in MAP:
        a = bpy.data.actions[name]
        rig.animation_data.action = a
        last = int(a.frame_range[1])
        for k, frac in enumerate((0.0, 0.25, 0.5, 0.75)):
            scene.frame_set(int(last * frac))
            for yaw in (0, 90):
                y = math.radians(yaw)
                cam.location = (5 * math.sin(y), -5 * math.cos(y), 0.9)
                cam.rotation_euler = (math.radians(90), 0, y)
                scene.render.filepath = os.path.join(RENDER, f"{name}_{k}_{yaw:03d}.png")
                bpy.ops.render.render(write_still=True)
    print("RENDERED", RENDER)
