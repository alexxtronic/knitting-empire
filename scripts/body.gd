extends Node3D
## A skinned humanoid made by tools/build_character.py (see data/characters.json).
## Every character shares one 22-bone skeleton and the same animation loops, so the
## player and NPCs all move with the same library. Callers pick a loop; this cross-fades.

const Data = preload("res://scripts/data.gd")
const Rig = preload("res://scripts/rig.gd")
const Face = preload("res://scripts/face.gd")
const ANIMS := ["Idle", "Walk", "SitKnit", "SitIdle", "Work", "Talk"]
## Run is a jog, for the player holding Shift; Brisk is the Walk with a longer stride, for walking
## faster than a stroll. Bodies without them walk instead.
const OPTIONAL := ["Run", "Brisk"]
## Walk gives way to Brisk above this many times the Walk loop's own speed, and comes back below
## the lower one (two thresholds, so she doesn't flicker between them while speeding up).
const BRISK_ABOVE := 1.3
const BRISK_BELOW := 1.12
const BLEND := 0.22
## While she's still gathering speed the stride plays no slower than this: a real first step is
## short and quick, not a full stride in slow motion.
const MIN_STRIDE_RATE := 0.55

var id := ""
var ok := false # true when the model loaded with every loop
var anim: AnimationPlayer
var skeleton: Skeleton3D
var props: Node3D # knitting needles and swatch, shown only while knitting
## Her meshes with the knitting fists (shape keys knit_R and knit_L, tools/add_grip.py), closed
## round the needles while she knits.
var _knit_meshes: Array = []
var walk_anim_speed := 3.0
var run_anim_speed := 3.0 # the ground speed the Run loop's stride matches
var brisk_anim_speed := 0.0 # and the Brisk loop's; 0 when the body has none
var label_height := 2.1
var rig: Rig # procedural look-at, lean and breathing on top of the loops (rig.gd)
var face: Face # blinking, eye direction and lid moods, when the model has real eyes (face.gd); else null
## Where this character is looking (a world point), or null. Set by main.gd each frame.
var look_target = null:
	set(v):
		look_target = v
		if rig:
			rig.look_target = v
		if face:
			face.look_target = v
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var _last_speed := 0.0
var _have_last := false


## Loads the character's model. Returns false (and adds nothing) if it's missing or incomplete.
func load_character(char_id: String) -> bool:
	id = char_id
	var info := Data.character(char_id)
	walk_anim_speed = float(info.get("walk_anim_speed", 3.0))
	run_anim_speed = float(info.get("run_anim_speed", 3.0))
	brisk_anim_speed = float(info.get("brisk_anim_speed", 0.0))
	label_height = float(info.get("label_height", 2.1))
	var path := str(info.get("model", "res://assets/%s.glb" % char_id))
	if not ResourceLoader.exists(path):
		push_warning("%s: model %s is missing" % [char_id, path])
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate() as Node3D
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		inst.free()
		push_warning("%s has no animations" % path)
		return false
	anim = aps[0]
	for n in ANIMS:
		if not anim.has_animation(n):
			inst.free()
			anim = null
			push_warning("%s is missing the %s loop" % [path, n])
			return false
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in OPTIONAL:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	add_child(inst)
	var sk := inst.find_children("*", "Skeleton3D", true, false)
	skeleton = sk[0] if not sk.is_empty() else null
	if skeleton:
		rig = Rig.new()
		rig.body = self
		rig.seed_t = randf() * 10.0
		skeleton.add_child(rig)
	if skeleton:
		for m in inst.find_children("*Eyes", "MeshInstance3D", true, false):
			var f := Face.new()
			if f.setup(m as MeshInstance3D, skeleton, self):
				face = f
				add_child(f)
				break
			f.free()
	props = inst.find_child("KnitProps", true, false) as Node3D
	if props:
		props.visible = false
	_knit_meshes = inst.find_children("*", "MeshInstance3D", true, false).filter(
		func(mi): return mi.mesh != null and mi.find_blend_shape_by_name("knit_R") >= 0)
	anim.play("Idle")
	anim.seek(randf() * anim.get_animation("Idle").length, true) # so no two people stand in step
	ok = true
	return true


## The mood on her face: a story mood such as "happy" or "sad" (face.gd MOODS). Bodies without
## real eyes ignore it.
func set_mood(mood: String) -> void:
	if face:
		face.mood = mood


## Shuts the eyes and keeps them shut (asleep), or opens them again.
func set_eyes_closed(shut: bool) -> void:
	if face:
		face.closed = shut


## Cross-fades to a loop. For "Walk" and "Run", pass the ground speed so the stride matches it.
func play(loop_name: String, ground_speed := 0.0) -> void:
	if not ok:
		return
	if loop_name == "Run" and not anim.has_animation("Run"):
		loop_name = "Walk"
	if loop_name == "Walk" and brisk_anim_speed > 0.0 and anim.has_animation("Brisk"):
		var was_brisk := anim.current_animation == "Brisk"
		if ground_speed > walk_anim_speed * (BRISK_BELOW if was_brisk else BRISK_ABOVE):
			loop_name = "Brisk"
	if anim.current_animation != loop_name:
		# Walk and Brisk are the same steps at two stride lengths: change over mid-step, in step
		var in_step := anim.current_animation in ["Walk", "Brisk"] and loop_name in ["Walk", "Brisk"]
		var through := anim.current_animation_position / maxf(anim.current_animation_length, 0.001) if in_step else 0.0
		anim.play(loop_name, BLEND)
		if in_step:
			anim.seek(through * anim.current_animation_length)
	anim.speed_scale = 1.0
	if ground_speed > 0.0 and loop_name == "Walk":
		anim.speed_scale = maxf(ground_speed / walk_anim_speed, MIN_STRIDE_RATE)
	elif ground_speed > 0.0 and loop_name == "Brisk":
		anim.speed_scale = maxf(ground_speed / brisk_anim_speed, MIN_STRIDE_RATE)
	elif ground_speed > 0.0 and loop_name == "Run":
		anim.speed_scale = maxf(ground_speed / run_anim_speed, MIN_STRIDE_RATE)
	if props:
		props.visible = loop_name == "SitKnit"
	for mi in _knit_meshes:
		for key in ["knit_R", "knit_L"]:
			var k: int = mi.find_blend_shape_by_name(key)
			if k >= 0:
				mi.set_blend_shape_value(k, 1.0 if loop_name == "SitKnit" else 0.0)


## How far her fingers are closed round both knitting needles: 0 open, 1 closed (no keys: 0).
func knit_grip() -> float:
	if _knit_meshes.is_empty():
		return 0.0
	var mi: MeshInstance3D = _knit_meshes[0]
	return minf(mi.get_blend_shape_value(mi.find_blend_shape_by_name("knit_R")), mi.get_blend_shape_value(mi.find_blend_shape_by_name("knit_L")))


## Tells the rig how the character really moved this frame (speed, turning, speeding up).
func _process(delta: float) -> void:
	if rig == null or delta <= 0.0:
		return
	var p := global_position
	var yaw := global_rotation.y
	if _have_last:
		var v := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / delta
		var spd := lerpf(rig.speed, v, clampf(delta * 10.0, 0.0, 1.0))
		rig.accel = lerpf(rig.accel, (spd - _last_speed) / delta, clampf(delta * 6.0, 0.0, 1.0))
		_last_speed = spd
		rig.speed = spd
		rig.turn_rate = lerpf(rig.turn_rate, angle_difference(_last_yaw, yaw) / delta, clampf(delta * 8.0, 0.0, 1.0))
		rig.moving = spd > 0.4
		# seated or working: the loops own the spine; keep the head free
		rig.look_strength = 0.6 if current() in ["SitKnit", "Work"] else 1.0
		rig.glances = current() == "Idle" and global_transform.basis.y.y > 0.9 # not asleep in bed
	_last_pos = p
	_last_yaw = yaw
	_have_last = true


## World point just in front of the eyes, for others to look at.
func eye_point() -> Vector3:
	return global_position + Vector3(0, label_height - 0.55, 0)


func current() -> String:
	return anim.current_animation if ok else ""


## Whether she's taking steps right now (strolling, walking briskly or jogging).
func striding() -> bool:
	return current() in ["Walk", "Brisk", "Run"]


func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	if skeleton:
		for i in skeleton.get_bone_count():
			out.append(skeleton.get_bone_name(i))
	return out
