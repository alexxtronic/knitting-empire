extends Node
## Eyes for a character whose model has them (made by tools/add_eyes.py): blinking, where the
## eyes point, lid shapes for moods, and eyes shut for sleep. body.gd adds this when the model
## has a mesh named "...Eyes" with the lid blend shapes; models without one simply have no face node.
##
##   mood:        a story mood ("happy", "sad", ...): the lids ease into its shape (MOODS below)
##   closed:      true = both eyes shut and stay shut (asleep)
##   look_target: a world point the eyes turn toward, within a few degrees; the head (rig.gd)
##                does the rest. null = straight ahead, with small glances now and then.

## Lid shapes for each mood a story line can carry. Anything else is neutral.
const MOODS := {
	"neutral": {},
	"happy": {"squint": 0.75},
	"warm": {"squint": 0.4},
	"wry": {"squint": 0.3, "lid_half": 0.35},
	"sad": {"lid_sad": 0.85},
	"worried": {"lid_sad": 0.55},
	"surprised": {}, # eyes wide: just no blinking for a moment
	"angry": {"lid_angry": 0.9},
	"tired": {"lid_half": 0.6},
	"sleepy": {"lid_half": 0.9},
}
const UPPER := ["lid_half", "lid_angry", "lid_sad"] # shapes of the upper lid: they fade out as it shuts
## The eyeballs stay under the skin this far (tools/add_eyes.py keeps them clear to 12 and 8 degrees).
const MAX_YAW := deg_to_rad(10.0)
const MAX_PITCH := deg_to_rad(7.0)
const CLOSE_TIME := 0.07
const OPEN_TIME := 0.13

var mesh: MeshInstance3D
var skeleton: Skeleton3D
var body: Node3D
var mood := "neutral":
	set(v):
		mood = v if MOODS.has(v) else "neutral"
		if mood == "surprised":
			_next_blink = maxf(_next_blink, 2.5)
var closed := false
var look_target = null # Vector3 in world space, or null
var hold_gaze = null # a world point that wins over look_target while set (a story beat, the autotest)
var blinks := true # the autotest turns this off to hold a pose still

var _shape := {} # blend shape name -> index
var _w := {} # current weight of each mood shape
var _blink := 0.0 # 0 open .. 1 shut
var _phase := 0 # 0 open, 1 closing, 2 opening
var _next_blink := 2.0
var _again := false # a second blink straight after this one
var _eyes: Array[int] = []
var _head := -1
var _gaze := Vector2.ZERO # yaw (+ = her left), pitch (+ = down), radians
var _glance := Vector2.ZERO
var _glance_t := 1.0


## Returns false when the mesh has no lid shapes (then there is nothing to drive).
func setup(eyes_mesh: MeshInstance3D, sk: Skeleton3D, owner_body: Node3D) -> bool:
	mesh = eyes_mesh
	skeleton = sk
	body = owner_body
	var am := mesh.mesh as ArrayMesh
	if am == null:
		return false
	for i in am.get_blend_shape_count():
		_shape[str(am.get_blend_shape_name(i))] = i
	if not (_shape.has("blink_L") and _shape.has("blink_R")):
		return false
	for n in ["squint", "lid_half", "lid_angry", "lid_sad"]:
		_w[n] = 0.0
	_head = sk.find_bone("Head")
	for n in ["LeftEye", "RightEye"]:
		var b := sk.find_bone(n)
		if b >= 0:
			_eyes.append(b)
	_next_blink = randf_range(0.5, 4.0)
	return true


## One blink now (also used by the autotest).
func blink() -> void:
	if _phase == 0:
		_phase = 1


## How shut the eyes are right now, 0..1.
func shut() -> float:
	return _blink


## Where the eyes point right now: yaw (+ = her left) and pitch (+ = down), in radians.
func gaze() -> Vector2:
	return _gaze


func shape_value(shape_name: String) -> float:
	return mesh.get_blend_shape_value(_shape[shape_name]) if _shape.has(shape_name) else 0.0


func _process(delta: float) -> void:
	if mesh == null:
		return
	# lids: shut for sleep, otherwise a blink every few seconds
	if closed:
		_blink = move_toward(_blink, 1.0, delta / 0.25)
		_phase = 0
	else:
		if _phase == 0:
			if _blink > 0.0:
				_blink = move_toward(_blink, 0.0, delta / OPEN_TIME)
			_next_blink -= delta
			if _next_blink <= 0.0 and blinks:
				_phase = 1
				_again = randf() < 0.15
				_next_blink = randf_range(2.2, 5.5)
		elif _phase == 1:
			_blink = move_toward(_blink, 1.0, delta / CLOSE_TIME)
			if _blink >= 1.0:
				_phase = 2
		else:
			_blink = move_toward(_blink, 0.0, delta / OPEN_TIME)
			if _blink <= 0.0:
				_phase = 1 if _again else 0
				_again = false
	var eased := _blink * _blink * (3.0 - 2.0 * _blink)
	mesh.set_blend_shape_value(_shape["blink_L"], eased)
	mesh.set_blend_shape_value(_shape["blink_R"], eased)
	# mood: ease each lid shape toward the mood's value
	var want: Dictionary = MOODS[mood]
	for n in _w:
		_w[n] = move_toward(_w[n], float(want.get(n, 0.0)), delta * 4.0)
		if _shape.has(n):
			mesh.set_blend_shape_value(_shape[n], _w[n] * ((1.0 - eased) if n in UPPER else 1.0))
	_turn_eyes(delta)


func _turn_eyes(delta: float) -> void:
	if _eyes.is_empty() or _head < 0 or body == null:
		return
	var sk := skeleton
	# the character's own up, forward and left, in the Head bone's space
	var head_rest := sk.get_bone_global_rest(_head).basis.orthonormalized()
	var up_sk := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var fwd_sk := (sk.global_transform.basis.inverse() * body.global_transform.basis.z).normalized()
	var up_l := (head_rest.inverse() * up_sk).normalized()
	var fwd_l := (head_rest.inverse() * fwd_sk).normalized()
	var left_l := up_l.cross(fwd_l).normalized()
	var want := Vector2.ZERO
	var target = hold_gaze if hold_gaze != null else look_target
	if target != null:
		var head_now := sk.global_transform * sk.get_bone_global_pose(_head)
		var mid := Vector3.ZERO
		for b in _eyes:
			mid += sk.get_bone_rest(b).origin
		mid /= float(_eyes.size())
		var d: Vector3 = head_now.basis.orthonormalized().inverse() * ((target as Vector3) - head_now * mid)
		if d.length() > 0.05:
			var f := d.dot(fwd_l)
			want.x = atan2(d.dot(left_l), maxf(f, 0.001))
			want.y = -atan2(d.dot(up_l), Vector2(f, d.dot(left_l)).length())
	else:
		# nobody to look at: the eyes rest ahead and flick a little to one side now and then
		_glance_t -= delta
		if _glance_t <= 0.0:
			_glance = Vector2(randf_range(-0.07, 0.07), randf_range(-0.03, 0.03)) if _glance == Vector2.ZERO and randf() < 0.6 else Vector2.ZERO
			_glance_t = randf_range(0.6, 1.4) if _glance != Vector2.ZERO else randf_range(1.5, 4.0)
		want = _glance
	want.x = clampf(want.x, -MAX_YAW, MAX_YAW)
	want.y = clampf(want.y, -MAX_PITCH, MAX_PITCH)
	_gaze = _gaze.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
	var turn := Basis(up_l, _gaze.x) * Basis(left_l, _gaze.y)
	for b in _eyes:
		sk.set_bone_pose_rotation(b, (turn * sk.get_bone_rest(b).basis.orthonormalized()).get_rotation_quaternion())
