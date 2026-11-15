extends Node3D
## A placed (or ghost) piece of furniture built from the catalog.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")

var item_id := ""
var rot := 0
var body: StaticBody3D
var lights: Array[OmniLight3D] = []
var flames: Array[MeshInstance3D] = []
var is_ghost := false
var color := "" # a colour she bought for it (furniture.json "colors" and "palettes"), "" for its own
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


## The colours this piece comes in (furniture.json: its "colors" names the parts to recolour and a
## palette from "palettes"): [{"id", "name", "color"}]. Empty for a piece that comes in one colour.
func colors() -> Array:
	return colors_of(item_id)


static func colors_of(id: String) -> Array:
	var spec: Dictionary = Catalog.ITEMS.get(id, {}).get("colors", {})
	if spec.is_empty():
		return []
	return (Data.load_json("furniture").get("palettes", {}) as Dictionary).get(str(spec.get("palette", "")), [])


## Recolours the parts the data names ("" puts its own colours back). The model isn't changed: each
## part's material is copied with its texture turned grey and tinted, so a plaid or a knit keeps its
## pattern in the new colour.
func set_color(cid: String) -> void:
	var tint: Variant = null
	for o in colors():
		if str(o["id"]) == cid:
			tint = Color.html(str(o["color"]))
	color = cid if tint != null else ""
	var parts: Array = info().get("colors", {}).get("parts", [])
	for m in find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base == null or not parts.has(base.resource_name):
				continue
			mi.set_surface_override_material(i, null if tint == null else recolored(base, tint))


static var _recolored := {}
static var _greys := {}


static func recolored(base: Material, tint: Color) -> Material:
	var k := "%d|%s" % [base.get_instance_id(), tint.to_html()]
	if _recolored.has(k):
		return _recolored[k]
	if not base is BaseMaterial3D:
		return base
	var m := base.duplicate() as BaseMaterial3D
	if m.albedo_texture != null:
		m.albedo_texture = _grey(m.albedo_texture)
	m.albedo_color = tint
	_recolored[k] = m
	return m


## A texture in greys, brightened so its average is a light grey (the tint then sets the colour).
static func _grey(t: Texture2D) -> Texture2D:
	var id := t.get_instance_id()
	if _greys.has(id):
		return _greys[id]
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(1.0, 1.0, 0.0)
	var small := img.duplicate() as Image
	small.resize(4, 4, Image.INTERPOLATE_BILINEAR)
	var avg := 0.0
	for x in 4:
		for y in 4:
			avg += small.get_pixel(x, y).r / 16.0
	img.adjust_bcs(clampf(0.8 / maxf(avg, 0.05), 0.6, 3.0), 1.0, 0.0)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_greys[id] = out
	return out


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
