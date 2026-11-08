extends Node3D
## A fluffy sheep that wanders its pen and regrows wool after shearing.

const Catalog = preload("res://scripts/catalog.gd")
const REGROW_HOURS := 10.0

var pen := Rect2()
var wool := 1.0 # 0..1, shearable at 1
var hold_time := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var _walk := 0.0
var _fluff: Node3D
var _legs: Array[MeshInstance3D] = []
var _head: Node3D


func _ready() -> void:
	var skin := Color(0.82, 0.74, 0.66)
	Catalog.ball(self, 0.3, Vector3(0, 0.5, 0), skin, Vector3(1, 0.85, 1.3))
	_fluff = Node3D.new()
	_fluff.position.y = 0.52
	add_child(_fluff)
	var white := Color(0.97, 0.96, 0.92)
	for o in [Vector3(0, 0.05, 0), Vector3(0.18, 0.0, 0.18), Vector3(-0.18, 0.0, 0.18), Vector3(0.18, 0.0, -0.2),
			Vector3(-0.18, 0.0, -0.2), Vector3(0, 0.15, -0.1), Vector3(0, 0.12, 0.15)]:
		Catalog.ball(_fluff, 0.24, o, white)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.62, 0.45)
	add_child(_head)
	var face := Color(0.18, 0.15, 0.14)
	Catalog.ball(_head, 0.14, Vector3.ZERO, face, Vector3(0.9, 1.0, 1.15))
	Catalog.ball(_head, 0.11, Vector3(0, 0.1, -0.04), white)
	for x in [-0.14, 0.14]:
		Catalog.box(_head, Vector3(0.12, 0.04, 0.06), Vector3(x, 0.03, -0.02), face, Vector3(0, 0, x * 120))
		Catalog.ball(_head, 0.022, Vector3(x * 0.45, 0.03, 0.13), Color(0.95, 0.95, 0.9))
	for p in [Vector3(-0.15, 0.15, 0.22), Vector3(0.15, 0.15, 0.22), Vector3(-0.15, 0.15, -0.22), Vector3(0.15, 0.15, -0.22)]:
		_legs.append(Catalog.cyl(self, 0.045, 0.04, 0.32, p, face))
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 0.9, 1.2)
	cs.shape = bs
	cs.position.y = 0.45
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	_pick_target()
	_update_fluff()


func display_name() -> String:
	return "Sheep"


func is_woolly() -> bool:
	return wool >= 1.0


func shear() -> void:
	wool = 0.0
	_update_fluff()


func hold(seconds: float) -> void:
	hold_time = seconds


func _pick_target() -> void:
	_target = Vector3(randf_range(pen.position.x, pen.end.x), 0, randf_range(pen.position.y, pen.end.y))


func _update_fluff() -> void:
	var s := 0.55 + 0.45 * wool
	_fluff.scale = Vector3(s, s, s)


func _process(delta: float) -> void:
	if wool < 1.0:
		wool = minf(1.0, wool + delta / (Game.HOUR_SECONDS * REGROW_HOURS))
		_update_fluff()
	if hold_time > 0.0:
		hold_time -= delta
		return
	if _wait > 0.0:
		_wait -= delta
		_head.position.y = 0.5 + 0.05 * sin(_wait * 2.0) # grazing
		return
	_head.position.y = 0.62
	var to := _target - position
	to.y = 0
	if to.length() < 0.1:
		_wait = randf_range(2.0, 6.0)
		_pick_target()
		return
	position += to.normalized() * 0.55 * delta
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.1)
	_walk += delta * 10.0
	for i in _legs.size():
		_legs[i].position.y = 0.15 + 0.03 * maxf(0.0, sin(_walk + (PI if i % 3 == 0 else 0.0)))
