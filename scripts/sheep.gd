extends Node3D
## A sheep that wanders its pen and regrows wool after shearing.
##
## Two models from tripo.ai, brought into the Woolcore look by tools/import_asset.py: a woolly sheep
## (assets/props/sheep_woolly.glb) and a freshly shorn one (assets/props/sheep_sheared.glb). Her coat
## comes back once the wool is half grown and fills out as it finishes. Both are rigged by
## tools/rig_sheep.py with the same loops: Walk (a four-beat walk), Graze (head down, chewing) and
## Idle (breathing, looking about). She wanders, and at each stop mostly grazes.

const Catalog = preload("res://scripts/catalog.gd")
const REGROW_HOURS := 10.0
const WOOLLY_MODEL := "res://assets/props/sheep_woolly.glb"
const SHEARED_MODEL := "res://assets/props/sheep_sheared.glb"
const COAT_BACK := 0.5 # wool level at which the woolly model shows again
const WALK_SPEED := 0.55 # metres per second
## Each model's Walk loop covers this much ground per second at speed 1 (rig_sheep.py prints it),
## so the loop is sped up or slowed to keep the hooves planted.
const STRIDE := {"woolly": 0.506, "sheared": 0.742}
const BLEND := 0.35 # seconds to cross-fade between loops
const GRAZE_CHANCE := 0.7 # at each stop: graze, or just stand and look about

var pen := Rect2()
## 0..1, shearable at 1. Setting it (shearing, loading a save, overnight growth) updates the look.
var wool := 1.0:
	set(v):
		wool = clampf(v, 0.0, 1.0)
		_update_look()
var hold_time := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var _grazing := false
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
			ap.seek(randf() * 3.0, true) # sheep don't breathe in step
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


func _pick_target() -> void:
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
		_play("Idle")
		return
	if _wait > 0.0:
		_wait -= delta
		_play("Graze" if _grazing else "Idle")
		return
	var to := _target - position
	to.y = 0
	if to.length() < 0.1:
		_wait = randf_range(3.0, 8.0)
		_grazing = randf() < GRAZE_CHANCE
		_pick_target()
		return
	position += to.normalized() * WALK_SPEED * delta
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 5.0))
	_play("Walk", WALK_SPEED)


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
		ap.speed_scale = ground_speed / float(STRIDE[key]) if ground_speed > 0.0 else 1.0
