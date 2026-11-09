extends SkeletonModifier3D
## Procedural motion layered on top of the animation loops, every frame, after the
## AnimationPlayer has posed the skeleton:
##   - look-at: the neck and head turn toward `look_target` (a world point) within natural limits,
##     easing in and out, so people glance at whoever is near and lead turns with their eyes
##   - lean: the spine leans into turns and lags when starting and stopping, on a damped spring
##     (a little overshoot reads as weight)
##   - breathing: a slow rise and fall of the chest and shoulders
##   - weight shift: a lazy sway through the spine while standing
## Added by body.gd under the character's Skeleton3D. body.gd feeds speed, turn rate and
## acceleration from how the character actually moved.

var body: Node3D # the node that turns and moves with the character (body.gd)
var look_target = null # Vector3 in world space, or null
var look_strength := 1.0 # 0..1, how far the head may turn toward the target
var speed := 0.0 # metres per second
var turn_rate := 0.0 # radians per second, + = turning left
var accel := 0.0 # forward acceleration, m/s²
var moving := false
var seed_t := 0.0 # so two characters don't breathe in step

var _t := 0.0
var _w := 0.0 # current look weight
var _target := Vector3.ZERO # smoothed look point
var _lean := Vector2.ZERO # x = roll (into turns), y = pitch (forward)
var _lean_v := Vector2.ZERO
var _bones := {}
var _fwd_rest := {} # each bone's forward axis in its own space at rest
var _ready_bones := false

const LOOK_BONES := [["Neck", 0.4], ["Head", 1.0]]
const MAX_YAW := deg_to_rad(70.0)
const MAX_PITCH_UP := deg_to_rad(25.0)
const MAX_PITCH_DOWN := deg_to_rad(35.0)


func _setup() -> void:
	var sk := get_skeleton()
	if sk == null or body == null:
		return
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder"]:
		_bones[n] = sk.find_bone(n)
		if _bones[n] < 0:
			return
	var fwd_sk := _body_fwd_in_skeleton(sk)
	for n in ["Neck", "Head"]:
		var rest := sk.get_bone_global_rest(_bones[n])
		_fwd_rest[n] = (rest.basis.inverse() * fwd_sk).normalized()
	_ready_bones = true


func _body_fwd_in_skeleton(sk: Skeleton3D) -> Vector3:
	return (sk.global_transform.basis.inverse() * body.global_transform.basis.z).normalized()


func _process_modification_with_delta(delta: float) -> void:
	if not _ready_bones:
		_setup()
		if not _ready_bones:
			return
	var sk := get_skeleton()
	_t += delta
	var fwd := _body_fwd_in_skeleton(sk)
	var up := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var right := up.cross(fwd).normalized()

	# --- lean: a damped spring chasing where the body "wants" to lean ----------------
	var want := Vector2.ZERO
	if moving:
		want.x = clampf(-turn_rate * speed * 0.045, -0.14, 0.14) # into the turn
		want.y = 0.035 + clampf(accel * 0.03, -0.08, 0.1) # a slight forward lean, more when speeding up
	else:
		want.x = sin((_t + seed_t) * 0.55) * 0.018 # idle weight shift
	var k := 70.0
	var c := 11.0
	_lean_v += ((want - _lean) * k - _lean_v * c) * delta
	_lean += _lean_v * delta
	var breath := sin((_t + seed_t) * TAU * 0.24)
	_add_rot(sk, "Spine", right, _lean.y * 0.5 - breath * 0.004)
	_add_rot(sk, "Spine", fwd, _lean.x * 0.55)
	_add_rot(sk, "Chest", right, _lean.y * 0.5 + breath * 0.016)
	_add_rot(sk, "Chest", fwd, _lean.x * 0.45)
	_add_rot(sk, "LeftShoulder", fwd, -breath * 0.012)
	_add_rot(sk, "RightShoulder", fwd, breath * 0.012)

	# --- look-at ---------------------------------------------------------------------
	var target_w := 0.0
	if look_target != null:
		var tl: Vector3 = sk.global_transform.affine_inverse() * (look_target as Vector3)
		_target = tl if _w < 0.01 else _target.lerp(tl, clampf(delta * 6.0, 0.0, 1.0))
		target_w = look_strength
	_w = move_toward(_w, target_w, delta * (2.2 if target_w > _w else 1.6))
	if _w <= 0.001:
		return
	for lb in LOOK_BONES:
		var n: String = lb[0]
		var share: float = lb[1]
		var bi: int = _bones[n]
		var gp := sk.get_bone_global_pose(bi)
		var cur: Vector3 = (gp.basis * (_fwd_rest[n] as Vector3)).normalized()
		var desired := _limit((_target - gp.origin).normalized(), fwd, up, right)
		var q := Quaternion(cur, desired)
		q = Quaternion.IDENTITY.slerp(q, share * _w)
		_set_global_basis(sk, bi, Basis(q) * gp.basis)


## Clamps a look direction to how far a neck can turn from the body's forward.
func _limit(d: Vector3, fwd: Vector3, up: Vector3, right: Vector3) -> Vector3:
	var x := d.dot(right)
	var y := d.dot(up)
	var z := d.dot(fwd)
	var yaw := clampf(atan2(x, z), -MAX_YAW, MAX_YAW)
	var pitch := clampf(atan2(y, Vector2(x, z).length()), -MAX_PITCH_DOWN, MAX_PITCH_UP)
	var h := cos(pitch)
	return (right * sin(yaw) * h + up * sin(pitch) + fwd * cos(yaw) * h).normalized()


## Rotates a bone by `angle` round an axis given in skeleton space, on top of its current pose.
func _add_rot(sk: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.00001:
		return
	var bi: int = _bones[bone]
	var gp := sk.get_bone_global_pose(bi)
	_set_global_basis(sk, bi, Basis(axis.normalized(), angle) * gp.basis)


func _set_global_basis(sk: Skeleton3D, bi: int, b: Basis) -> void:
	var parent := sk.get_bone_parent(bi)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bi, (pb.inverse() * b).orthonormalized().get_rotation_quaternion())
