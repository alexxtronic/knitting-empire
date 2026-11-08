extends Node3D
## The farmer: follows paths, sits, and runs timed activities (knitting, shearing...).
## Uses the Blender-made character in res://assets/farmer.glb (built by tools/build_farmer.py):
## a skinned humanoid with Idle, Walk, SitKnit, SitIdle, Work and Talk loops, cross-faded here.
## Falls back to a simple shape model if the file is missing.

const Catalog = preload("res://scripts/catalog.gd")
const MODEL_PATH := "res://assets/farmer.glb"
const ANIMS := ["Idle", "Walk", "SitKnit", "SitIdle", "Work", "Talk"]
const WALK_ANIM_SPEED := 3.0 # walking speed (m/s) the Walk loop's stride was keyed for
const BLEND := 0.22

var speed := 3.0
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
var _anim: AnimationPlayer
var _props: Node3D # needles + swatch, shown only while knitting
var _talk_t := 0.0
var _label: Label3D
var _ring: MeshInstance3D


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	if ResourceLoader.exists(MODEL_PATH):
		var packed := load(MODEL_PATH) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			_model.add_child(inst)
			var aps := inst.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				_anim = aps[0]
				detailed = true
				for n in ANIMS:
					if not _anim.has_animation(n):
						detailed = false
					else:
						_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			if detailed:
				_anim.play("Idle")
				_props = inst.find_child("KnitProps", true, false) as Node3D
				if _props:
					_props.visible = false
			else:
				push_warning("farmer.glb has no animations; using the simple model")
				inst.queue_free()
				_anim = null
	if not detailed:
		_build_simple_model()
	_ring = Catalog.glow(Catalog.ring(self, 0.4, 0.46, Vector3(0, 0.03, 0), Color(0.55, 0.95, 0.4)), Color(0.55, 0.95, 0.4), 0.8)
	_label = Label3D.new()
	_label.position = Vector3(0, 2.15 if detailed else 1.8, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 44
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.96, 0.85)
	_label.visible = false
	add_child(_label)


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
	_label.visible = true
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
	_label.visible = false
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


func _process(delta: float) -> void:
	_t += delta
	var walking := false
	if busy:
		_activity_t += delta
		var pct := clampf(_activity_t / _activity_total, 0.0, 1.0)
		_label.text = "%s… %d%%" % [_activity_text, int(pct * 100.0)]
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
		var step := speed * delta
		if d <= step:
			position = Vector3(next.x, 0.0, next.z)
			path.remove_at(0)
			if path.is_empty():
				_arrive()
		else:
			position += to / d * step
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.25)
	if detailed:
		_animate(delta, walking)
	else:
		_animate_simple(walking)


## Skinned character: pick the loop for the current state and cross-fade to it.
func _animate(delta: float, walking: bool) -> void:
	_talk_t = maxf(0.0, _talk_t - delta)
	var want := "Idle"
	if busy:
		if _sitting:
			want = "SitKnit" if _activity_text == "Knitting" else "SitIdle"
		elif _activity_text == "Reading":
			want = "Idle"
		else:
			want = "Work"
	elif walking:
		want = "Walk"
	elif _talk_t > 0.0:
		want = "Talk"
	if _anim.current_animation != want:
		_anim.play(want, BLEND)
	if _props:
		_props.visible = want == "SitKnit"
	_anim.speed_scale = speed / WALK_ANIM_SPEED if want == "Walk" else 1.0


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
