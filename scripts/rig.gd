extends SkeletonModifier3D
## Procedural motion layered on top of the animation loops, every frame, after the
## AnimationPlayer has posed the skeleton:
##   - look-at: the neck and head turn toward `look_target` (a world point) within natural limits,
##     easing in and out, so people glance at whoever is near and lead turns with their eyes
##   - lean: the spine leans into turns and lags when starting and stopping, on a damped spring
##     (a little overshoot reads as weight)
##   - breathing: a slow rise and fall of the chest and shoulders
##   - weight shift: a lazy, never-repeating sway and twist through the spine while standing
##   - glances: with nobody to look at, a standing character now and then looks off to one side for
##     a moment, at their own pace, so a crowd never stands like statues playing the same loop
## Added by body.gd under the character's Skeleton3D. body.gd feeds speed, turn rate and
## acceleration from how the character actually moved.

var body: Node3D # the node that turns and moves with the character (body.gd)
var look_target = null # Vector3 in world space, or null
var look_strength := 1.0 # 0..1, how far the head may turn toward the target
var glances := true # may look about when idle (body.gd: only standing upright in the Idle loop)
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
var _glance := Vector3.ZERO # where an idle glance points, in skeleton space
var _glance_on := false
var _glance_t := 0.0 # seconds until the glance starts or ends
var _bones := {}
var _fwd_rest := {} # each bone's forward axis in its own space at rest
var _ready_bones := false

## How far each bone turns toward the target, down the chain: the upper chest takes a little, the neck
## more, the head the rest. Spread out like this no one joint twists far.
const LOOK_BONES := [["UpperChest", 0.25], ["Neck", 0.45], ["Head", 1.0]]
const MAX_YAW := deg_to_rad(70.0)
const MAX_PITCH_UP := deg_to_rad(25.0)
const MAX_PITCH_DOWN := deg_to_rad(35.0)
const SPRING_STEP := 1.0 / 120.0
const MAX_LEAN := 0.25 # radians, about 14 degrees


func _setup() -> void:
	var sk := get_skeleton()
	if sk == null or body == null:
		return
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder"]:
		_bones[n] = sk.find_bone(n)
		if _bones[n] < 0:
			return
	var fwd_sk := _body_fwd_in_skeleton(sk)
	for lb in LOOK_BONES:
		var n: String = lb[0]
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
		# idle weight shift: two slow waves that never line up, so it doesn't read as a loop
		var ti := _t + seed_t
		want.x = sin(ti * 0.55) * 0.02 + sin(ti * 0.23 + 1.3) * 0.016
		want.y = sin(ti * 0.31 + 0.7) * 0.008
	# stepped in small fixed slices: one big step on a slow frame would overshoot further each
	# frame until the spine spun round (the arms-flying glitch at low frame rates)
	var k := 70.0
	var c := 11.0
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, SPRING_STEP)
		_lean_v += ((want - _lean) * k - _lean_v * c) * h
		_lean += _lean_v * h
		left -= h
	if not (_lean.is_finite() and _lean_v.is_finite()):
		_lean = Vector2.ZERO
		_lean_v = Vector2.ZERO
	_lean = _lean.clamp(Vector2(-MAX_LEAN, -MAX_LEAN), Vector2(MAX_LEAN, MAX_LEAN))
	var breath := sin((_t + seed_t) * TAU * 0.24)
	_add_rot(sk, "Spine", right, _lean.y * 0.5 - breath * 0.004)
	_add_rot(sk, "Spine", fwd, _lean.x * 0.55)
	_add_rot(sk, "Chest", right, _lean.y * 0.5 + breath * 0.016)
	_add_rot(sk, "Chest", fwd, _lean.x * 0.45)
	if not moving:
		_add_rot(sk, "Chest", up, sin((_t + seed_t) * 0.19 + 2.1) * 0.03) # a slow twist at the waist
	_add_rot(sk, "LeftShoulder", fwd, -breath * 0.012)
	_add_rot(sk, "RightShoulder", fwd, breath * 0.012)

	# --- look-at ---------------------------------------------------------------------
	var target_w := 0.0
	if look_target != null:
		var tl: Vector3 = sk.global_transform.affine_inverse() * (look_target as Vector3)
		if not tl.is_finite():
			tl = _target
		_target = tl if _w < 0.01 else _target.lerp(tl, clampf(delta * 6.0, 0.0, 1.0))
		target_w = look_strength
	elif _idle_glance(delta, sk, fwd, up, right):
		_target = _glance if _w < 0.01 else _target.lerp(_glance, clampf(delta * 3.0, 0.0, 1.0))
		target_w = 0.8
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
		if cur.is_zero_approx() or not desired.is_finite() or cur.dot(desired) < -0.99:
			continue # pointing straight back: no stable rotation, leave the animated pose
		var q := _aim(cur, desired, up)
		q = Quaternion.IDENTITY.slerp(q, share * _w)
		_set_global_basis(sk, bi, Basis(q) * gp.basis)


## Standing with nobody to look at: every few seconds, look off to one side for a moment. Returns
## true while a glance is on (`_glance` is then the point to look at, in skeleton space).
func _idle_glance(delta: float, sk: Skeleton3D, fwd: Vector3, up: Vector3, right: Vector3) -> bool:
	if moving or not glances:
		_glance_on = false
		_glance_t = randf_range(2.0, 5.0)
		return false
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_on = not _glance_on
		_glance_t = randf_range(1.2, 3.0) if _glance_on else randf_range(3.5, 9.0)
		if _glance_on:
			var yaw := randf_range(0.3, 0.75) * (1.0 if randf() < 0.5 else -1.0)
			var head := sk.get_bone_global_pose(_bones["Head"]).origin
			_glance = head + (fwd * cos(yaw) + right * sin(yaw) + up * randf_range(-0.25, 0.1)) * 3.0
	return _glance_on


## The rotation that turns `cur` to `desired` as a person turns their head: a turn about the vertical,
## then a nod. The shortest-arc rotation would also roll the head sideways when it starts off bowed
## (seated, or mid-step), which reads as the face twisting.
func _aim(cur: Vector3, desired: Vector3, up: Vector3) -> Quaternion:
	var ch := cur - up * cur.dot(up)
	var dh := desired - up * desired.dot(up)
	if ch.length() < 0.05 or dh.length() < 0.05:
		return Quaternion(cur, desired)
	ch = ch.normalized()
	dh = dh.normalized()
	var turn := Quaternion(up, atan2(ch.cross(dh).dot(up), ch.dot(dh)))
	var c2 := (turn * cur).normalized()
	if c2.dot(desired) > 0.99999:
		return turn
	return Quaternion(c2, desired) * turn


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
