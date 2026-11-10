extends Node3D
## A skinned humanoid made by tools/build_character.py (see data/characters.json).
## Every character shares one 22-bone skeleton and the same animation loops, so the
## player and NPCs all move with the same library. Callers pick a loop; this cross-fades.

const Data = preload("res://scripts/data.gd")
const Rig = preload("res://scripts/rig.gd")
const ANIMS := ["Idle", "Walk", "SitKnit", "SitIdle", "Work", "Talk"]
const OPTIONAL := ["Run"] # a jog, for the player holding Shift; bodies without it walk instead
const BLEND := 0.22

var id := ""
var ok := false # true when the model loaded with every loop
var anim: AnimationPlayer
var skeleton: Skeleton3D
var props: Node3D # knitting needles and swatch, shown only while knitting
var walk_anim_speed := 3.0
var run_anim_speed := 3.0 # the ground speed the Run loop's stride matches
var label_height := 2.1
var rig: Rig # procedural look-at, lean and breathing on top of the loops (rig.gd)
## Where this character is looking (a world point), or null. Set by main.gd each frame.
var look_target = null:
	set(v):
		look_target = v
		if rig:
			rig.look_target = v
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
	props = inst.find_child("KnitProps", true, false) as Node3D
	if props:
		props.visible = false
	anim.play("Idle")
	ok = true
	return true


## Cross-fades to a loop. For "Walk" and "Run", pass the ground speed so the stride matches it.
func play(loop_name: String, ground_speed := 0.0) -> void:
	if not ok:
		return
	if loop_name == "Run" and not anim.has_animation("Run"):
		loop_name = "Walk"
	if anim.current_animation != loop_name:
		anim.play(loop_name, BLEND)
	anim.speed_scale = 1.0
	if ground_speed > 0.0 and loop_name == "Walk":
		anim.speed_scale = ground_speed / walk_anim_speed
	elif ground_speed > 0.0 and loop_name == "Run":
		anim.speed_scale = ground_speed / run_anim_speed
	if props:
		props.visible = loop_name == "SitKnit"


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
	_last_pos = p
	_last_yaw = yaw
	_have_last = true


## World point just in front of the eyes, for others to look at.
func eye_point() -> Vector3:
	return global_position + Vector3(0, label_height - 0.55, 0)


func current() -> String:
	return anim.current_animation if ok else ""


func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	if skeleton:
		for i in skeleton.get_bone_count():
			out.append(skeleton.get_bone_name(i))
	return out
