extends Node3D
## A sheep that wanders its pen and regrows wool after shearing.
##
## Two models from tripo.ai, brought into the Woolcore look by tools/import_asset.py: a woolly sheep
## (assets/props/sheep_woolly.glb) and a freshly shorn one (assets/props/sheep_sheared.glb). Her coat
## comes back once the wool is half grown and fills out as it finishes. Both are rigged by
## tools/rig_sheep.py with the same loops: Walk (a four-beat walk), Graze (head down, tugging and
## chewing) and Idle (breathing, shifting her weight, looking about). She grazes her way round the
## pen a step or two at a time, crosses it now and then, and eases in and out of every walk.
##
## Bedtime (main.gd's _update_flock): at dusk she is given a route to her stall in the barn and
## walks it at a purposeful pace without stopping to graze. She is `housed` when she gets there,
## and stands in her stall facing the aisle until she is given the route back to the pen.

const Catalog = preload("res://scripts/catalog.gd")
const REGROW_HOURS := 10.0
const WOOLLY_MODEL := "res://assets/props/sheep_woolly.glb"
const SHEARED_MODEL := "res://assets/props/sheep_sheared.glb"
const COAT_BACK := 0.5 # wool level at which the woolly model shows again
const WALK_SPEED := 0.38 # metres per second, an amble (each sheep's own pace is a little either side)
## Each model's Walk loop covers this much ground per second at speed 1 (rig_sheep.py prints it),
## so the loop is sped up or slowed to keep the hooves planted.
const STRIDE := {"woolly": 0.315, "sheared": 0.462}
const BLEND := 0.6 # seconds to cross-fade between loops (her head takes a moment to come up)
const GRAZE_CHANCE := 0.7 # at each stop: graze, or just stand and look about
const HOME_SPEED := 0.8 # metres per second on the way to the barn and back

var pen := Rect2()
## 0..1, shearable at 1. Setting it (shearing, loading a save, overnight growth) updates the look.
var wool := 1.0:
	set(v):
		wool = clampf(v, 0.0, 1.0)
		_update_look()
var hold_time := 0.0
var route: Array = [] # Vector3 points still to pass, in order
var housed := false # in her stall for the night
var heading_in := false # the route she is on ends in her stall
var stall_yaw := 0.0 # which way she faces once housed
var _target := Vector3.ZERO
var _wait := 0.0
var _grazing := false
var _speed := 0.0 # ground speed right now: she eases into a walk and out of it
var _pace := 1.0 # this sheep's own pace
var _nibbles := 0 # short steps left before her next proper wander
var _pivot: Node3D # carries both models
var _woolly: Node3D
var _sheared: Node3D


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_woolly = Catalog.model(WOOLLY_MODEL, _pivot)
	_sheared = Catalog.model(SHEARED_MODEL, _pivot)
	for m in [_woolly, _sheared]:
		var ap := _player_of(m)
		if ap:
			for n in ["Walk", "Graze", "Idle"]:
				if ap.has_animation(n):
					ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			ap.play("Idle")
			ap.seek(randf() * 6.0, true) # sheep don't breathe in step
	if _woolly == null:
		_woolly = Node3D.new()
		_pivot.add_child(_woolly)
		Catalog.ball(_woolly, 0.4, Vector3(0, 0.55, 0.3), Color(0.97, 0.96, 0.92), Vector3(0.8, 0.8, 1.2))
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 0.95, 1.05)
	cs.shape = bs
	cs.position.y = 0.48
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	_pace = randf_range(0.85, 1.15)
	_wait = randf_range(0.0, 4.0) # the flock doesn't set off together
	_grazing = randf() < GRAZE_CHANCE
	_pick_target()
	_update_look()


func display_name() -> String:
	return "Sheep"


func is_woolly() -> bool:
	return wool >= 1.0


## Which model shows right now: "woolly" or "sheared" (for the autotest).
func coat() -> String:
	return "sheared" if _sheared and _sheared.visible else "woolly"


func shear() -> void:
	wool = 0.0


func hold(seconds: float) -> void:
	hold_time = seconds


## Sends her along `points`: to her stall (she is housed at the end, facing `yaw`) or back to the pen.
func walk_route(points: Array, to_stall: bool, yaw := 0.0) -> void:
	route = points.duplicate()
	heading_in = to_stall
	housed = false
	stall_yaw = yaw
	_wait = 0.0


## Puts her straight in her stall, or straight back in the pen, without the walk (a save loaded
## at night, the autotest).
func place(at: Vector3, in_stall: bool, yaw := 0.0) -> void:
	position = at
	route = []
	heading_in = false
	housed = in_stall
	stall_yaw = yaw
	_speed = 0.0
	if in_stall:
		rotation.y = yaw
	else:
		_pick_target()


func _follow_route(delta: float) -> void:
	var to: Vector3 = (route[0] as Vector3) - position
	to.y = 0
	var d := to.length()
	if d < 0.18:
		route.pop_front()
		if route.is_empty():
			housed = heading_in
			heading_in = false
			if not housed:
				_wait = randf_range(1.0, 3.0)
				_pick_target()
		return
	var off := absf(angle_difference(rotation.y, atan2(to.x, to.z)))
	var want := HOME_SPEED * _pace * clampf(1.2 - off / 1.2, 0.25, 1.0)
	if route.size() == 1: # slowing into her stall, or into the pen
		want = minf(want, maxf(0.15, sqrt(2.0 * 0.6 * d)))
	_speed = move_toward(_speed, want, 1.2 * delta)
	position += Vector3(sin(rotation.y), 0, cos(rotation.y)).lerp(to / d, 0.6).normalized() * _speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 4.0))
	_play("Walk", _speed)


## Where she heads next. Grazing sheep mostly shuffle a step or two to fresh grass, and only now
## and then cross the pen.
func _pick_target() -> void:
	if _nibbles > 0:
		_nibbles -= 1
		var a := rotation.y + randf_range(-0.9, 0.9)
		var p := position + Vector3(sin(a), 0, cos(a)) * randf_range(0.45, 1.1)
		_target = Vector3(clampf(p.x, pen.position.x, pen.end.x), 0, clampf(p.z, pen.position.y, pen.end.y))
		return
	_nibbles = randi_range(1, 4)
	_target = Vector3(randf_range(pen.position.x, pen.end.x), 0, randf_range(pen.position.y, pen.end.y))


func _update_look() -> void:
	if _woolly == null:
		return
	var coated := wool >= COAT_BACK or _sheared == null
	_woolly.visible = coated
	if _sheared:
		_sheared.visible = not coated
	if coated:
		var s := lerpf(0.88, 1.0, clampf((wool - COAT_BACK) / (1.0 - COAT_BACK), 0.0, 1.0))
		_woolly.scale = Vector3(s, s, s)


func _process(delta: float) -> void:
	if wool < 1.0:
		wool = wool + delta / (Game.HOUR_SECONDS * REGROW_HOURS)
	if hold_time > 0.0:
		hold_time -= delta
		_speed = 0.0
		_play("Idle")
		return
	if housed:
		_speed = 0.0
		rotation.y = lerp_angle(rotation.y, stall_yaw, 1.0 - exp(-delta * 2.0))
		_play("Idle")
		return
	if not route.is_empty():
		_follow_route(delta)
		return
	if _wait > 0.0:
		_wait -= delta
		_speed = 0.0
		_play("Graze" if _grazing else "Idle")
		return
	var to := _target - position
	to.y = 0
	var d := to.length()
	if d < 0.08:
		_speed = 0.0
		_grazing = randf() < GRAZE_CHANCE
		_wait = randf_range(4.0, 11.0) if _grazing else randf_range(2.0, 5.0)
		_pick_target()
		return
	# she turns toward where she's going as she sets off, gathers pace over a few steps and slows
	# into her stop: a sheep that snaps to full speed in a straight line looks like a toy on rails
	var off := absf(angle_difference(rotation.y, atan2(to.x, to.z)))
	var top := WALK_SPEED * _pace
	var want := minf(top * clampf(1.2 - off / 1.2, 0.25, 1.0), maxf(0.12, sqrt(2.0 * 0.5 * d)))
	_speed = move_toward(_speed, want, 0.7 * delta)
	position += Vector3(sin(rotation.y), 0, cos(rotation.y)).lerp(to / d, 0.5).normalized() * _speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 2.6))
	_play("Walk", _speed)


## Whether a loop is playing right now on the coat that's showing (for the autotest).
func current_loop() -> String:
	var ap := _player_of(_sheared if coat() == "sheared" else _woolly)
	return ap.current_animation if ap else ""


func _player_of(m: Node) -> AnimationPlayer:
	if m == null:
		return null
	var found := m.find_children("*", "AnimationPlayer", true, false)
	return found[0] if found.size() > 0 else null


## Plays a loop on both coats (the hidden one stays in step for when the wool grows back). With a
## ground speed, Walk runs at the pace that keeps that coat's hooves from sliding.
func _play(loop_name: String, ground_speed := 0.0) -> void:
	for key in ["woolly", "sheared"]:
		var ap := _player_of(_woolly if key == "woolly" else _sheared)
		if ap == null or not ap.has_animation(loop_name):
			continue
		if ap.current_animation != loop_name:
			ap.play(loop_name, BLEND)
		ap.speed_scale = maxf(ground_speed / float(STRIDE[key]), 0.5) if loop_name == "Walk" else 1.0
