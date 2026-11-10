extends Node3D
## The character you play: follows paths, sits, and runs timed activities (knitting, shearing...).
## Wears the skinned body named as "player" in data/characters.json (see scripts/body.gd),
## which shares its skeleton and animation loops with every other character.
## Falls back to a simple shape model if the model is missing.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const Body = preload("res://scripts/body.gd")

var speed := 1.5 # ground speed right now: walk_speed, or run_speed while she jogs
var walk_speed := 1.5 # m/s; main.gd raises both with fitness
var run_speed := 3.0
var running := false # Shift held (main.gd sets it every frame; the autotest can hold it too)
var path: Array = []
var busy := false
var detailed := false # true when the Blender character loaded
var _on_arrive := Callable()
var _activity_text := ""
var _activity_t := 0.0
var _activity_total := 1.0
var _activity_done := Callable()
var _return_pos = null
var _sitting := false
var _t := 0.0
var _model: Node3D
var _arms: Array[MeshInstance3D] = []
var body: Body
var anim_override := "" # a story scene can hold her in a loop ("Work", "SitIdle"...)
var _talk_t := 0.0
var _ring: MeshInstance3D
var walked := 0.0 # metres walked since main.gd last counted them (for fitness)
signal footstep # a foot lands (from the Walk loop's timing)
signal needle_click # a stitch while she knits
var _walk_phase := -1.0
var _needle_t := 0.4


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	body = Body.new()
	_model.add_child(body)
	detailed = body.load_character(Data.player_character())
	if not detailed:
		_build_simple_model()
	_ring = Catalog.glow(Catalog.ring(self, 0.4, 0.46, Vector3(0, 0.03, 0), Color(0.55, 0.95, 0.4)), Color(0.55, 0.95, 0.4), 0.8)


func _build_simple_model() -> void:
	var denim := Color(0.25, 0.3, 0.42)
	var sweater := Catalog.CREAM
	var skin := Color(0.93, 0.76, 0.62)
	var hair := Color(0.36, 0.22, 0.13)
	for x in [-0.1, 0.1]:
		Catalog.cyl(_model, 0.075, 0.07, 0.5, Vector3(x, 0.27, 0), denim)
		Catalog.box(_model, Vector3(0.13, 0.08, 0.22), Vector3(x, 0.04, 0.03), Color(0.3, 0.2, 0.12))
	Catalog.cyl(_model, 0.19, 0.23, 0.56, Vector3(0, 0.78, 0), sweater)
	Catalog.cyl(_model, 0.215, 0.225, 0.08, Vector3(0, 0.84, 0), Catalog.PLAID)
	for x in [-0.27, 0.27]:
		_arms.append(Catalog.cyl(_model, 0.06, 0.065, 0.5, Vector3(x, 0.78, 0), sweater, Vector3(0, 0, -x * 25)))
	Catalog.ball(_model, 0.17, Vector3(0, 1.22, 0), skin)
	Catalog.ball(_model, 0.18, Vector3(0, 1.31, -0.03), hair, Vector3(1.0, 0.75, 1.0))


func walk(p: Array, on_arrive := Callable()) -> void:
	cancel_activity()
	path = p
	_on_arrive = on_arrive
	if path.is_empty():
		_arrive()


func face_point(p: Vector3) -> void:
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


## Gesture while chatting with a villager.
func talk(seconds := 4.0) -> void:
	_talk_t = seconds


func start_activity(text: String, duration: float, done: Callable, sit_pos = null, sit_rot = null) -> void:
	busy = true
	_activity_text = text
	_activity_t = 0.0
	_activity_total = duration
	_activity_done = done
	_ring.visible = false
	_sitting = sit_pos != null
	if sit_pos != null:
		_return_pos = position
		position = sit_pos
		if sit_rot != null:
			rotation.y = sit_rot


func cancel_activity() -> void:
	if not busy:
		return
	_end_activity()


func _end_activity() -> void:
	busy = false
	_sitting = false
	_ring.visible = true
	if not detailed:
		_model.position.y = 0.0
		for a in _arms:
			a.rotation_degrees.x = 0.0
	if _return_pos != null:
		position = _return_pos
		_return_pos = null


func _arrive() -> void:
	var cb := _on_arrive
	_on_arrive = Callable()
	if cb.is_valid():
		cb.call()


## What she's doing ("Knitting"), or "" when she isn't busy.
func activity_text() -> String:
	return _activity_text if busy else ""


## How far through the current activity she is, 0..1.
func activity_progress() -> float:
	return clampf(_activity_t / maxf(_activity_total, 0.001), 0.0, 1.0)


## Where the action bar floats: just over her head.
func head_point() -> Vector3:
	return global_position + Vector3(0, (body.label_height if detailed else 1.8) + 0.05, 0)


func _process(delta: float) -> void:
	_t += delta
	var walking := false
	if busy:
		_activity_t += delta
		if _activity_t >= _activity_total:
			var cb := _activity_done
			_activity_done = Callable()
			_end_activity()
			if cb.is_valid():
				cb.call()
	elif not path.is_empty():
		walking = true
		var next: Vector3 = path[0]
		var to := next - position
		to.y = 0.0
		var d := to.length()
		speed = run_speed if running else walk_speed
		var step := speed * delta
		if d <= step:
			walked += d
			position = Vector3(next.x, 0.0, next.z)
			path.remove_at(0)
			if path.is_empty():
				_arrive()
		else:
			position += to / d * step
			walked += step
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.25)
	if detailed:
		_animate(delta, walking)
	else:
		_animate_simple(walking)


## Skinned character: pick the loop for the current state; the body cross-fades to it.
func _animate(delta: float, walking: bool) -> void:
	_talk_t = maxf(0.0, _talk_t - delta)
	var want := "Idle"
	if anim_override != "" and not walking:
		want = anim_override
	elif busy:
		if _sitting:
			want = "SitKnit" if _activity_text == "Knitting" else "SitIdle"
		elif _activity_text == "Reading":
			want = "Idle"
		else:
			want = "Work"
	elif walking:
		want = "Run" if running else "Walk"
	elif _talk_t > 0.0:
		want = "Talk"
	body.play(want, speed)
	_sound_cues(delta)


## Footsteps land twice per Walk loop, when each leg is furthest forward (a quarter and three
## quarters through it, see a_walk in tools/build_character.py); needles click while she knits.
func _sound_cues(delta: float) -> void:
	var cur := body.current()
	if cur in ["Walk", "Run"] and body.anim.current_animation_length > 0.0:
		var ph := fmod(body.anim.current_animation_position / body.anim.current_animation_length + 0.75, 1.0)
		if _walk_phase >= 0.0 and (ph < _walk_phase or (_walk_phase < 0.5 and ph >= 0.5)):
			footstep.emit()
		_walk_phase = ph
	else:
		_walk_phase = -1.0
	if cur == "SitKnit":
		_needle_t -= delta
		if _needle_t <= 0.0:
			needle_click.emit()
			_needle_t = randf_range(0.28, 0.65)


func _animate_simple(walking: bool) -> void:
	if busy:
		for i in _arms.size():
			_arms[i].rotation_degrees.x = -50.0 + 12.0 * sin(_t * 12.0 + i * PI)
	elif walking:
		_model.position.y = absf(sin(_t * 11.0)) * 0.06
		for i in _arms.size():
			_arms[i].rotation_degrees.x = 25.0 * sin(_t * 11.0 + i * PI)
	else:
		_model.position.y = lerpf(_model.position.y, 0.0, 0.2)
		for a in _arms:
			a.rotation_degrees.x = lerpf(a.rotation_degrees.x, 0.0, 0.2)
