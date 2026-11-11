extends Node3D
## A placed (or ghost) piece of furniture built from the catalog.

const Catalog = preload("res://scripts/catalog.gd")

var item_id := ""
var rot := 0
var body: StaticBody3D
var lights: Array[OmniLight3D] = []
var flames: Array[MeshInstance3D] = []
var is_ghost := false
## 0..1, how gloomy the weather is (main.gd sets it from the rain). Lamps come on in a daytime
## downpour as they would at dusk.
static var gloom := 0.0
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
	var dark := maxf(1.0 - Game.daylight(), gloom * 0.8)
	var candle := candle_flicker(_t)
	for l in lights:
		var e := lerpf(float(l.get_meta("day_energy")), float(l.get_meta("night_energy")), dark)
		if l.has_meta("fire"):
			e *= 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 5.3 + 1.0)
		elif l.has_meta("candle"):
			e *= candle
		l.light_energy = e
	for i in flames.size():
		var f := flames[i]
		if f.has_meta("candle"):
			# the flame stretches and shrinks with its light and leans a little in the draught
			if not f.has_meta("base_scale"):
				f.set_meta("base_scale", f.scale)
			var b: Vector3 = f.get_meta("base_scale")
			f.scale = Vector3(b.x * (0.9 + 0.1 * candle), b.y * (0.55 + 0.5 * candle), b.z * (0.9 + 0.1 * candle))
			f.rotation = Vector3(0.08 * sin(_t * 2.1 + 0.7), 0, 0.1 * sin(_t * 1.7) * sin(_t * 4.3 + 2.0))
			continue
		var s := 1.0 + 0.12 * sin(_t * (8.0 + i * 2.3) + i)
		f.scale = Vector3(1.0, 1.5 * s, 0.6) if i == 0 else Vector3(s, s, s)


## A candle's brightness (about 0.6 to 1.05): a soft quick waver, a faster shimmer, and now and
## then a gutter when a draught gets into the lantern. Each lamp starts at a random _t, so a
## street of lamps never flickers in step.
static func candle_flicker(t: float) -> float:
	var waver := 0.09 * sin(t * 6.3) * sin(t * 2.9 + 2.0)
	var shimmer := 0.05 * sin(t * 17.0 + 1.3) * sin(t * 11.7)
	var gutter := 0.3 * pow(maxf(0.0, sin(t * 0.61 + 1.1) * sin(t * 0.23)), 6.0)
	return 0.95 + waver + shimmer - gutter
