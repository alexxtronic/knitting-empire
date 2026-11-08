extends Node3D
## A placed (or ghost) piece of furniture built from the catalog.

const Catalog = preload("res://scripts/catalog.gd")

var item_id := ""
var rot := 0
var body: StaticBody3D
var lights: Array[OmniLight3D] = []
var flames: Array[MeshInstance3D] = []
var is_ghost := false
var _t := 0.0


func setup(id: String, r: int) -> void:
	item_id = id
	Catalog.build(id, self)
	set_rot(r)
	for c in get_children():
		if c is OmniLight3D:
			lights.append(c)
		elif c is MeshInstance3D and c.has_meta("flame"):
			flames.append(c)
	body = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var s: Vector2 = info()["size"]
	var h: float = maxf(0.12, float(info().get("height", 1.0)))
	bs.size = Vector3(s.x, h, s.y)
	cs.shape = bs
	cs.position.y = h * 0.5
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	_t = randf() * 10.0


func info() -> Dictionary:
	return Catalog.ITEMS[item_id]


func display_name() -> String:
	return info()["name"]


func is_flat() -> bool:
	return bool(info().get("flat", false))


func set_rot(r: int) -> void:
	rot = posmod(r, 4)
	rotation.y = rot * PI * 0.5


func size_rotated() -> Vector2:
	var s: Vector2 = info()["size"]
	return Vector2(s.y, s.x) if rot % 2 == 1 else s


func footprint_at(p: Vector3) -> Rect2:
	var s := size_rotated()
	return Rect2(p.x - s.x * 0.5, p.z - s.y * 0.5, s.x, s.y)


func footprint() -> Rect2:
	return footprint_at(position)


func front() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


func set_ghost(on: bool) -> void:
	is_ghost = on
	for m in find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).transparency = 0.4 if on else 0.0
	if body:
		body.collision_layer = 0 if on else 2


func _process(delta: float) -> void:
	if lights.is_empty() and flames.is_empty():
		return
	_t += delta
	var dark := 1.0 - Game.daylight()
	for l in lights:
		var e := lerpf(float(l.get_meta("day_energy")), float(l.get_meta("night_energy")), dark)
		if l.has_meta("fire"):
			e *= 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 5.3 + 1.0)
		l.light_energy = e
	for i in flames.size():
		var s := 1.0 + 0.12 * sin(_t * (8.0 + i * 2.3) + i)
		flames[i].scale = Vector3(1.0, 1.5 * s, 0.6) if i == 0 else Vector3(s, s, s)
