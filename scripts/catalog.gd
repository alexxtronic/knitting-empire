extends RefCounted
## Furniture catalog plus the tiny primitive-mesh helpers every model is built from.
## Placeholder art: swap any builder for an imported Tripo/Blender .glb later.
## Every model faces +Z and sits centered on its footprint at floor level.

const Data = preload("res://scripts/data.gd")

const WOOD := Color(0.47, 0.30, 0.18)
const WOOD_DARK := Color(0.30, 0.19, 0.11)
const WOOD_LIGHT := Color(0.72, 0.54, 0.34)
const PLAID := Color(0.63, 0.17, 0.15)
const PLAID_DARK := Color(0.36, 0.09, 0.09)
const CREAM := Color(0.93, 0.87, 0.74)
const STONE := Color(0.57, 0.55, 0.51)
const STONE_DARK := Color(0.42, 0.40, 0.37)
const LEAF := Color(0.33, 0.52, 0.25)
const TERRACOTTA := Color(0.72, 0.40, 0.26)
const BRASS := Color(0.85, 0.66, 0.30)
const FIRE := Color(1.0, 0.48, 0.10)

## The Build-mode catalog comes from res://data/furniture.json; the meshes are built below.
static var ITEMS: Dictionary = Data.furniture()
static var INDOOR: Array = Data.furniture_ids("indoors")
static var OUTDOOR: Array = Data.furniture_ids("yard")
## Ids that have a builder in build(). A furniture.json entry without one shows a magenta box.
const BUILDERS := ["rocking_chair", "armchair", "sofa", "bed", "kitchen", "coffee_table", "dining_table",
	"bookshelf", "wardrobe", "fireplace", "spinning_wheel", "lamp", "yarn_basket", "rug_red", "rug_round",
	"plant", "flower_pot", "sunflowers", "fence", "bench", "scarecrow", "lantern", "hay_bale"]

static var _mats := {}


# --- primitive helpers ---------------------------------------------------------

## Woolcore (shaders/woolcore.gdshader): solid surfaces are felt, and the colours below are knitted,
## with this stitch width in metres. Glass, water and glowing things stay plain.
static var woolcore := true
const WOOL_SHADER := preload("res://shaders/woolcore.gdshader")
const KNIT := [
	[Color(0.43, 0.58, 0.28), 0.24], # grass (world.gd GRASS)
	[Color(0.92, 0.86, 0.74), 0.15], # house plaster (main.gd PLASTER)
	[PLAID, 0.07], [PLAID_DARK, 0.07], [CREAM, 0.08],
	[Color(0.45, 0.12, 0.11), 0.08], [Color(0.88, 0.80, 0.62), 0.08], [Color(0.62, 0.17, 0.14), 0.08], # red rug
	[Color(0.35, 0.42, 0.55), 0.08], [Color(0.62, 0.35, 0.25), 0.08], # round rug
]


static func mat(c: Color, rough: float = 0.85, glow: float = 0.0) -> Material:
	var key := "%s_%s_%s" % [c.to_html(true), rough, glow]
	if _mats.has(key):
		return _mats[key]
	if woolcore and glow <= 0.0 and rough >= 0.3 and c.a >= 0.99:
		var stitch := 0.0
		for k in KNIT:
			if (k[0] as Color).is_equal_approx(c):
				stitch = k[1]
		var sm := ShaderMaterial.new()
		sm.shader = WOOL_SHADER
		sm.set_shader_parameter("albedo", c)
		sm.set_shader_parameter("roughness", clampf(rough + 0.1, 0.0, 1.0))
		sm.set_shader_parameter("pattern", 1 if stitch > 0.0 else 0)
		sm.set_shader_parameter("stitch", maxf(stitch, 0.05))
		sm.set_shader_parameter("contrast", 0.86 if stitch > 0.2 else 0.72) # big ground stitches stay gentle
		_mats[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


static func _add(p: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi


static func box(p: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(p, m, pos, c, rot)


static func cyl(p: Node3D, top_r: float, bot_r: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return _add(p, m, pos, c, rot)


static func ball(p: Node3D, r: float, pos: Vector3, c: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	var mi := _add(p, m, pos, c, Vector3.ZERO)
	mi.scale = scl
	return mi


static func ring(p: Node3D, inner: float, outer: float, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 8
	return _add(p, m, pos, c, rot)


static func glow(mi: MeshInstance3D, c: Color, strength: float) -> MeshInstance3D:
	mi.material_override = mat(c, 0.6, strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # a flame or bulb never blocks its own light
	return mi


static func omni(p: Node3D, pos: Vector3, c: Color, rng: float, day_e: float, night_e: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.omni_range = rng
	l.light_energy = day_e
	# real shadows from the fire and lamps (furniture, people), cheap two-sided maps that fade
	# out with distance so a whole street of lamps doesn't cost much
	l.shadow_enabled = true
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.shadow_blur = 1.5
	l.light_size = 0.12
	# far-off lamps (the whole town from the farm) drop their shadows first, then their light
	l.distance_fade_enabled = true
	l.distance_fade_begin = 70.0
	l.distance_fade_shadow = 40.0
	l.distance_fade_length = 10.0
	l.set_meta("day_energy", day_e)
	l.set_meta("night_energy", night_e)
	p.add_child(l)
	return l


# --- model builders --------------------------------------------------------------

static func has_builder(id: String) -> bool:
	return id in BUILDERS


static func build(id: String, r: Node3D) -> void:
	match id:
		"rocking_chair": _rocking_chair(r)
		"armchair": _armchair(r)
		"sofa": _sofa(r)
		"bed": _bed(r)
		"kitchen": _kitchen(r)
		"coffee_table": _coffee_table(r)
		"dining_table": _dining_table(r)
		"bookshelf": _bookshelf(r)
		"wardrobe": _wardrobe(r)
		"fireplace": _fireplace(r)
		"spinning_wheel": _spinning_wheel(r)
		"lamp": _lamp(r)
		"yarn_basket": _yarn_basket(r)
		"rug_red": _rug_red(r)
		"rug_round": _rug_round(r)
		"plant": _plant(r)
		"flower_pot": _flower_pot(r)
		"sunflowers": _sunflowers(r)
		"fence": _fence(r)
		"bench": _bench(r)
		"scarecrow": _scarecrow(r)
		"lantern": _lantern(r)
		"hay_bale": _hay_bale(r)
		_: box(r, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), Color.MAGENTA)


static func _rocking_chair(r: Node3D) -> void:
	for x in [-0.3, 0.3]:
		box(r, Vector3(0.06, 0.06, 0.95), Vector3(x, 0.05, 0), WOOD_DARK)
		for z in [-0.25, 0.25]:
			box(r, Vector3(0.06, 0.4, 0.06), Vector3(x, 0.26, z), WOOD)
		box(r, Vector3(0.06, 0.05, 0.62), Vector3(x, 0.7, 0.02), WOOD)
		box(r, Vector3(0.05, 0.22, 0.05), Vector3(x, 0.58, 0.26), WOOD)
	box(r, Vector3(0.66, 0.07, 0.62), Vector3(0, 0.47, 0), WOOD)
	box(r, Vector3(0.58, 0.07, 0.54), Vector3(0, 0.53, 0.02), PLAID)
	box(r, Vector3(0.68, 0.08, 0.06), Vector3(0, 1.18, -0.28), WOOD)
	for x in [-0.3, -0.1, 0.1, 0.3]:
		box(r, Vector3(0.05, 0.68, 0.04), Vector3(x, 0.83, -0.29), WOOD)
	box(r, Vector3(0.5, 0.56, 0.03), Vector3(0.02, 0.86, -0.25), PLAID, Vector3(-6, 0, 0))
	for y in [0.72, 0.98]:
		box(r, Vector3(0.51, 0.05, 0.035), Vector3(0.02, y, -0.245), PLAID_DARK, Vector3(-6, 0, 0))


static func _armchair(r: Node3D) -> void:
	var f := Color(0.50, 0.58, 0.42)
	for x in [-0.38, 0.38]:
		for z in [-0.35, 0.35]:
			box(r, Vector3(0.07, 0.1, 0.07), Vector3(x, 0.05, z), WOOD_DARK)
	box(r, Vector3(0.9, 0.36, 0.85), Vector3(0, 0.27, 0), f)
	box(r, Vector3(0.64, 0.12, 0.66), Vector3(0, 0.51, 0.08), f.lightened(0.1))
	box(r, Vector3(0.9, 0.62, 0.2), Vector3(0, 0.75, -0.33), f)
	for x in [-0.38, 0.38]:
		box(r, Vector3(0.14, 0.26, 0.85), Vector3(x, 0.56, 0), f.darkened(0.08))
	box(r, Vector3(0.34, 0.3, 0.08), Vector3(0.1, 0.72, -0.2), PLAID, Vector3(-10, 0, 8))


static func _sofa(r: Node3D) -> void:
	var f := Color(0.86, 0.79, 0.66)
	for x in [-0.88, 0.88]:
		for z in [-0.35, 0.35]:
			box(r, Vector3(0.07, 0.1, 0.07), Vector3(x, 0.05, z), WOOD_DARK)
	box(r, Vector3(1.9, 0.36, 0.85), Vector3(0, 0.27, 0), f)
	for x in [-0.44, 0.44]:
		box(r, Vector3(0.84, 0.12, 0.66), Vector3(x, 0.51, 0.08), f.lightened(0.05))
	box(r, Vector3(1.9, 0.6, 0.2), Vector3(0, 0.75, -0.33), f)
	for x in [-0.87, 0.87]:
		box(r, Vector3(0.16, 0.3, 0.85), Vector3(x, 0.58, 0), f.darkened(0.06))
	box(r, Vector3(0.55, 0.5, 0.03), Vector3(0.55, 0.8, -0.21), PLAID, Vector3(-8, 0, 0))
	box(r, Vector3(0.3, 0.3, 0.1), Vector3(-0.62, 0.7, -0.17), PLAID, Vector3(-15, 0, 10))
	box(r, Vector3(0.3, 0.3, 0.1), Vector3(-0.25, 0.7, -0.18), Color(0.5, 0.58, 0.42), Vector3(-15, 0, -6))


static func _bed(r: Node3D) -> void:
	box(r, Vector3(1.5, 0.28, 2.0), Vector3(0, 0.18, 0), WOOD)
	box(r, Vector3(1.4, 0.16, 1.9), Vector3(0, 0.4, 0), Color(0.95, 0.94, 0.9))
	box(r, Vector3(1.46, 0.08, 1.25), Vector3(0, 0.5, 0.33), PLAID)
	for z in [0.1, 0.5]:
		box(r, Vector3(1.47, 0.085, 0.07), Vector3(0, 0.501, z), PLAID_DARK)
	for x in [-0.4, 0.4]:
		box(r, Vector3(0.07, 0.085, 1.26), Vector3(x, 0.502, 0.33), PLAID_DARK)
	box(r, Vector3(1.46, 0.1, 0.3), Vector3(0, 0.55, 0.8), CREAM)
	for x in [-0.33, 0.33]:
		box(r, Vector3(0.55, 0.12, 0.35), Vector3(x, 0.54, -0.7), Color(0.97, 0.96, 0.93))
	box(r, Vector3(1.5, 1.0, 0.08), Vector3(0, 0.5, -0.98), WOOD_DARK)
	box(r, Vector3(1.5, 0.5, 0.06), Vector3(0, 0.3, 0.98), WOOD_DARK)


static func _kitchen(r: Node3D) -> void:
	var cab := Color(0.40, 0.50, 0.42)
	box(r, Vector3(2.0, 0.84, 0.9), Vector3(0, 0.42, -0.05), cab)
	box(r, Vector3(2.04, 0.06, 0.96), Vector3(0, 0.87, -0.05), WOOD_LIGHT)
	for x in [-0.5, 0.5]:
		box(r, Vector3(0.9, 0.62, 0.02), Vector3(x, 0.42, 0.41), cab.darkened(0.12))
		ball(r, 0.025, Vector3(x + 0.35, 0.6, 0.43), BRASS)
	box(r, Vector3(0.55, 0.03, 0.45), Vector3(-0.45, 0.905, -0.05), Color(0.72, 0.74, 0.76))
	cyl(r, 0.02, 0.02, 0.25, Vector3(-0.45, 1.0, -0.35), Color(0.7, 0.7, 0.72))
	box(r, Vector3(0.04, 0.03, 0.15), Vector3(-0.45, 1.11, -0.29), Color(0.7, 0.7, 0.72))
	for p in [Vector2(0.35, -0.2), Vector2(0.72, -0.2), Vector2(0.35, 0.15), Vector2(0.72, 0.15)]:
		cyl(r, 0.1, 0.1, 0.02, Vector3(p.x, 0.91, p.y), Color(0.12, 0.12, 0.12))
	ball(r, 0.1, Vector3(0.72, 1.0, 0.15), Color(0.75, 0.2, 0.15), Vector3(1, 0.85, 1))
	cyl(r, 0.15, 0.1, 0.08, Vector3(0.0, 0.94, 0.1), WOOD_LIGHT)
	for o in [Vector3(-0.05, 1.0, 0.08), Vector3(0.06, 1.0, 0.12), Vector3(0.0, 1.0, 0.0)]:
		ball(r, 0.05, o, Color(0.8, 0.15, 0.12))
	for x in [-0.9, -0.78]:
		cyl(r, 0.05, 0.05, 0.18, Vector3(x, 0.99, -0.35), Color(0.9, 0.85, 0.7))


static func _coffee_table(r: Node3D) -> void:
	cyl(r, 0.45, 0.45, 0.06, Vector3(0, 0.44, 0), WOOD, Vector3.ZERO, 28)
	cyl(r, 0.06, 0.06, 0.4, Vector3(0, 0.22, 0), WOOD_DARK)
	cyl(r, 0.25, 0.28, 0.04, Vector3(0, 0.02, 0), WOOD_DARK)
	box(r, Vector3(0.3, 0.05, 0.22), Vector3(0.1, 0.495, 0.05), Color(0.3, 0.35, 0.55))
	box(r, Vector3(0.26, 0.05, 0.2), Vector3(0.1, 0.545, 0.05), Color(0.62, 0.5, 0.3), Vector3(0, 15, 0))
	cyl(r, 0.045, 0.04, 0.09, Vector3(-0.2, 0.515, -0.1), CREAM)
	cyl(r, 0.05, 0.04, 0.15, Vector3(-0.15, 0.545, 0.18), Color(0.6, 0.65, 0.75))
	for o in [Vector3(-0.15, 0.66, 0.18), Vector3(-0.12, 0.7, 0.2), Vector3(-0.18, 0.69, 0.16)]:
		ball(r, 0.035, o, Color(0.6, 0.45, 0.8))


static func _dining_table(r: Node3D) -> void:
	box(r, Vector3(1.9, 0.07, 0.95), Vector3(0, 0.76, 0), WOOD_LIGHT)
	for x in [-0.85, 0.85]:
		for z in [-0.4, 0.4]:
			box(r, Vector3(0.08, 0.72, 0.08), Vector3(x, 0.36, z), WOOD)
	box(r, Vector3(1.6, 0.01, 0.3), Vector3(0, 0.8, 0), PLAID)
	cyl(r, 0.07, 0.06, 0.2, Vector3(0, 0.9, 0), CREAM)
	for o in [Vector3(0, 1.04, 0), Vector3(0.06, 1.02, 0.03), Vector3(-0.05, 1.03, -0.03)]:
		ball(r, 0.05, o, Color(0.95, 0.75, 0.2))
	for x in [-0.55, 0.55]:
		cyl(r, 0.025, 0.025, 0.15, Vector3(x, 0.88, 0), CREAM)
		glow(ball(r, 0.025, Vector3(x, 0.98, 0), Color(1.0, 0.8, 0.4)), Color(1.0, 0.8, 0.4), 3.0)


static func _bookshelf(r: Node3D) -> void:
	for x in [-0.72, 0.72]:
		box(r, Vector3(0.05, 1.9, 0.45), Vector3(x, 0.95, 0), WOOD_DARK)
	box(r, Vector3(1.5, 1.9, 0.03), Vector3(0, 0.95, -0.21), WOOD_DARK)
	for y in [0.03, 0.48, 0.93, 1.38, 1.87]:
		box(r, Vector3(1.44, 0.04, 0.42), Vector3(0, y, 0), WOOD_DARK)
	var cols: Array[Color] = [Color(0.6, 0.18, 0.15), Color(0.25, 0.35, 0.5), Color(0.3, 0.45, 0.3),
		Color(0.85, 0.7, 0.4), Color(0.45, 0.3, 0.45), Color(0.9, 0.86, 0.75)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for shelf in [0.05, 0.5, 0.95, 1.4]:
		var x := -0.68
		while x < 0.58:
			var w := rng.randf_range(0.05, 0.1)
			var h := rng.randf_range(0.26, 0.38)
			box(r, Vector3(w * 0.9, h, 0.3), Vector3(x + w * 0.5, shelf + h * 0.5, 0.0), cols[rng.randi() % cols.size()])
			x += w
			if rng.randf() < 0.12:
				x += 0.12
	cyl(r, 0.1, 0.08, 0.15, Vector3(0.4, 1.97, 0), TERRACOTTA)
	ball(r, 0.14, Vector3(0.4, 2.1, 0), LEAF)


static func _wardrobe(r: Node3D) -> void:
	box(r, Vector3(1.5, 1.95, 0.5), Vector3(0, 0.975, 0), WOOD)
	box(r, Vector3(1.58, 0.08, 0.56), Vector3(0, 1.99, 0), WOOD_DARK)
	box(r, Vector3(1.58, 0.08, 0.56), Vector3(0, 0.04, 0), WOOD_DARK)
	box(r, Vector3(0.02, 1.7, 0.02), Vector3(0, 1.0, 0.255), WOOD_DARK)
	for x in [-0.37, 0.37]:
		box(r, Vector3(0.6, 1.5, 0.02), Vector3(x, 1.05, 0.255), WOOD.lightened(0.08))
	for x in [-0.07, 0.07]:
		ball(r, 0.03, Vector3(x, 1.0, 0.27), BRASS)
	cyl(r, 0.2, 0.2, 0.2, Vector3(0.3, 2.13, 0), Color(0.6, 0.3, 0.3))


static func _fireplace(r: Node3D) -> void:
	box(r, Vector3(1.9, 1.25, 0.85), Vector3(0, 0.625, -0.05), STONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		var x := rng.randf_range(-0.85, 0.85)
		var y := rng.randf_range(0.1, 1.15)
		if absf(x) < 0.6 and y < 0.95:
			continue
		var c := STONE_DARK if rng.randf() < 0.5 else STONE.lightened(0.1)
		box(r, Vector3(rng.randf_range(0.22, 0.38), rng.randf_range(0.14, 0.22), 0.04), Vector3(x, y, 0.38), c)
	box(r, Vector3(2.1, 0.1, 1.0), Vector3(0, 0.05, 0.05), STONE_DARK)
	box(r, Vector3(1.0, 0.8, 0.3), Vector3(0, 0.5, 0.25), Color(0.07, 0.05, 0.04))
	box(r, Vector3(2.15, 0.12, 1.0), Vector3(0, 1.31, 0), WOOD_DARK)
	box(r, Vector3(1.25, 1.3, 0.6), Vector3(0, 2.0, -0.15), STONE)
	cyl(r, 0.07, 0.07, 0.7, Vector3(0, 0.18, 0.25), WOOD_DARK, Vector3(0, 0, 90))
	cyl(r, 0.06, 0.06, 0.6, Vector3(0.05, 0.28, 0.22), WOOD, Vector3(0, 25, 90))
	var f1 := glow(ball(r, 0.18, Vector3(0, 0.38, 0.25), FIRE, Vector3(1, 1.5, 0.6)), FIRE, 4.0)
	var f2 := glow(ball(r, 0.1, Vector3(0.1, 0.42, 0.28), Color(1.0, 0.8, 0.3)), Color(1.0, 0.8, 0.3), 5.0)
	var f3 := glow(ball(r, 0.12, Vector3(-0.12, 0.34, 0.27), Color(1.0, 0.35, 0.1)), Color(1.0, 0.35, 0.1), 4.0)
	for f in [f1, f2, f3]:
		f.set_meta("flame", true)
	for x in [-0.8, -0.66, 0.78]:
		var h := 0.12 + absf(x) * 0.08
		cyl(r, 0.03, 0.03, h, Vector3(x, 1.37 + h * 0.5, 0.2), CREAM)
		glow(ball(r, 0.025, Vector3(x, 1.4 + h, 0.2), Color(1.0, 0.8, 0.4)), Color(1.0, 0.8, 0.4), 4.0)
	var l := omni(r, Vector3(0, 0.6, 0.9), Color(1.0, 0.55, 0.25), 7.0, 1.2, 2.6)
	l.set_meta("fire", true)


static func _spinning_wheel(r: Node3D) -> void:
	box(r, Vector3(0.85, 0.07, 0.28), Vector3(0, 0.42, 0), WOOD)
	for p in [Vector3(-0.35, 0.2, -0.1), Vector3(-0.35, 0.2, 0.1), Vector3(0.35, 0.2, 0)]:
		cyl(r, 0.03, 0.03, 0.42, p, WOOD_DARK)
	for z in [-0.08, 0.08]:
		box(r, Vector3(0.05, 0.6, 0.05), Vector3(0.15, 0.72, z), WOOD)
	ring(r, 0.3, 0.35, Vector3(0.15, 0.95, 0), WOOD_DARK, Vector3(90, 0, 0))
	for i in 6:
		box(r, Vector3(0.02, 0.6, 0.02), Vector3(0.15, 0.95, 0), WOOD, Vector3(0, 0, i * 30))
	ball(r, 0.05, Vector3(0.15, 0.95, 0), WOOD_DARK)
	cyl(r, 0.015, 0.015, 0.5, Vector3(-0.3, 0.7, 0), WOOD, Vector3(0, 0, 15))
	ball(r, 0.1, Vector3(-0.36, 0.95, 0), CREAM, Vector3(1, 1.4, 1))
	box(r, Vector3(0.3, 0.03, 0.2), Vector3(0.1, 0.06, 0.15), WOOD)


static func _lamp(r: Node3D) -> void:
	cyl(r, 0.16, 0.18, 0.04, Vector3(0, 0.02, 0), WOOD_DARK)
	cyl(r, 0.02, 0.02, 1.35, Vector3(0, 0.7, 0), BRASS)
	glow(cyl(r, 0.14, 0.24, 0.3, Vector3(0, 1.45, 0), CREAM), Color(1.0, 0.86, 0.6), 0.6)
	omni(r, Vector3(0, 1.3, 0), Color(1.0, 0.78, 0.5), 5.0, 0.3, 1.6)


static func _yarn_basket(r: Node3D) -> void:
	cyl(r, 0.23, 0.18, 0.24, Vector3(0, 0.12, 0), Color(0.72, 0.56, 0.34))
	ring(r, 0.2, 0.25, Vector3(0, 0.24, 0), Color(0.6, 0.45, 0.27))
	ball(r, 0.09, Vector3(-0.07, 0.27, 0.05), PLAID)
	ball(r, 0.09, Vector3(0.08, 0.28, -0.03), CREAM)
	ball(r, 0.09, Vector3(0.0, 0.3, -0.09), Color(0.85, 0.65, 0.25))
	ball(r, 0.08, Vector3(0.06, 0.26, 0.1), Color(0.45, 0.55, 0.4))
	cyl(r, 0.008, 0.008, 0.35, Vector3(0.02, 0.38, 0), BRASS, Vector3(20, 0, 25))


static func _rug_red(r: Node3D) -> void:
	box(r, Vector3(3.0, 0.02, 2.0), Vector3(0, 0.03, 0), Color(0.45, 0.12, 0.11))
	box(r, Vector3(2.7, 0.022, 1.7), Vector3(0, 0.031, 0), Color(0.88, 0.80, 0.62))
	box(r, Vector3(2.5, 0.024, 1.5), Vector3(0, 0.032, 0), Color(0.62, 0.17, 0.14))
	box(r, Vector3(0.7, 0.026, 0.7), Vector3(0, 0.033, 0), Color(0.88, 0.80, 0.62), Vector3(0, 45, 0))
	box(r, Vector3(0.4, 0.028, 0.4), Vector3(0, 0.034, 0), PLAID_DARK, Vector3(0, 45, 0))
	for x in [-0.85, 0.85]:
		box(r, Vector3(0.3, 0.026, 0.3), Vector3(x, 0.033, 0), Color(0.88, 0.80, 0.62), Vector3(0, 45, 0))


static func _rug_round(r: Node3D) -> void:
	var cols := [Color(0.35, 0.42, 0.55), CREAM, Color(0.62, 0.35, 0.25), CREAM, Color(0.35, 0.42, 0.55)]
	var radii := [0.98, 0.85, 0.7, 0.5, 0.3]
	for i in 5:
		cyl(r, radii[i], radii[i], 0.02 + i * 0.002, Vector3(0, 0.03 + i * 0.001, 0), cols[i], Vector3.ZERO, 32)


static func _plant(r: Node3D) -> void:
	cyl(r, 0.17, 0.13, 0.3, Vector3(0, 0.15, 0), TERRACOTTA)
	cyl(r, 0.15, 0.15, 0.02, Vector3(0, 0.29, 0), Color(0.3, 0.2, 0.12))
	ball(r, 0.18, Vector3(0, 0.5, 0), LEAF, Vector3(1, 1.2, 1))
	ball(r, 0.13, Vector3(0.1, 0.62, 0.05), LEAF.lightened(0.1))
	ball(r, 0.12, Vector3(-0.08, 0.65, -0.06), LEAF.darkened(0.1))
	ball(r, 0.1, Vector3(0.0, 0.76, 0.02), LEAF.lightened(0.05))


static func _flower_pot(r: Node3D) -> void:
	cyl(r, 0.18, 0.14, 0.26, Vector3(0, 0.13, 0), TERRACOTTA)
	var cols := [Color(0.9, 0.3, 0.35), Color(0.98, 0.8, 0.2), Color(0.95, 0.55, 0.7), Color(0.9, 0.3, 0.35)]
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var p := Vector3(cos(a) * 0.08, 0, sin(a) * 0.08)
		cyl(r, 0.01, 0.01, 0.25, p + Vector3(0, 0.37, 0), LEAF.darkened(0.2))
		ball(r, 0.06, p + Vector3(0, 0.5, 0), cols[i])
	ball(r, 0.1, Vector3(0, 0.3, 0), LEAF, Vector3(1.4, 0.6, 1.4))


static func _sunflowers(r: Node3D) -> void:
	for i in 3:
		var x := -0.32 + i * 0.32
		var h := 1.2 + (i % 2) * 0.25
		cyl(r, 0.025, 0.03, h, Vector3(x, h * 0.5, 0), LEAF.darkened(0.2))
		box(r, Vector3(0.18, 0.02, 0.08), Vector3(x + 0.08, h * 0.5, 0), LEAF, Vector3(0, 0, -25))
		box(r, Vector3(0.18, 0.02, 0.08), Vector3(x - 0.08, h * 0.65, 0), LEAF, Vector3(0, 0, 25))
		cyl(r, 0.16, 0.16, 0.04, Vector3(x, h, 0.05), Color(0.98, 0.78, 0.15), Vector3(70, 0, 0), 20)
		cyl(r, 0.08, 0.08, 0.05, Vector3(x, h, 0.07), Color(0.35, 0.2, 0.08), Vector3(70, 0, 0))


static func _fence(r: Node3D) -> void:
	var c := Color(0.9, 0.88, 0.82)
	for x in [-0.45, 0.45]:
		box(r, Vector3(0.08, 0.85, 0.08), Vector3(x, 0.425, 0), c)
	for i in 5:
		box(r, Vector3(0.1, 0.75, 0.03), Vector3(-0.36 + i * 0.18, 0.375, 0.05), c)
	for y in [0.25, 0.6]:
		box(r, Vector3(1.0, 0.06, 0.03), Vector3(0, y, 0.0), c.darkened(0.1))


static func _bench(r: Node3D) -> void:
	for z in [-0.12, 0.0, 0.12]:
		box(r, Vector3(1.4, 0.04, 0.1), Vector3(0, 0.45, z), WOOD_LIGHT)
	for x in [-0.6, 0.6]:
		box(r, Vector3(0.06, 0.45, 0.36), Vector3(x, 0.225, 0), WOOD_DARK)
		box(r, Vector3(0.05, 0.5, 0.04), Vector3(x, 0.68, -0.18), WOOD_DARK)
	for y in [0.7, 0.85]:
		box(r, Vector3(1.4, 0.1, 0.03), Vector3(0, y, -0.19), WOOD_LIGHT)


static func _scarecrow(r: Node3D) -> void:
	cyl(r, 0.04, 0.05, 1.8, Vector3(0, 0.9, 0), WOOD_DARK)
	box(r, Vector3(1.0, 0.06, 0.06), Vector3(0, 1.35, 0), WOOD_DARK)
	box(r, Vector3(0.45, 0.5, 0.25), Vector3(0, 1.2, 0), PLAID)
	box(r, Vector3(0.9, 0.16, 0.18), Vector3(0, 1.35, 0), PLAID)
	for x in [-0.48, 0.48]:
		ball(r, 0.07, Vector3(x, 1.33, 0), Color(0.9, 0.78, 0.4))
	ball(r, 0.17, Vector3(0, 1.62, 0), Color(0.85, 0.72, 0.5))
	cyl(r, 0.28, 0.28, 0.03, Vector3(0, 1.75, 0), Color(0.55, 0.4, 0.2))
	cyl(r, 0.1, 0.14, 0.2, Vector3(0, 1.86, 0), Color(0.55, 0.4, 0.2))
	for x in [-0.06, 0.06]:
		ball(r, 0.025, Vector3(x, 1.65, 0.15), Color(0.1, 0.08, 0.06))


static func _lantern(r: Node3D) -> void:
	var dark := Color(0.15, 0.15, 0.15)
	cyl(r, 0.04, 0.05, 1.6, Vector3(0, 0.8, 0), dark)
	box(r, Vector3(0.3, 0.03, 0.03), Vector3(0.12, 1.55, 0), dark)
	glow(box(r, Vector3(0.16, 0.22, 0.16), Vector3(0.25, 1.4, 0), Color(1.0, 0.8, 0.5)), Color(1.0, 0.78, 0.45), 2.0)
	cyl(r, 0.02, 0.12, 0.06, Vector3(0.25, 1.54, 0), dark)
	omni(r, Vector3(0.25, 1.35, 0), Color(1.0, 0.7, 0.4), 5.0, 0.0, 1.5)


static func _hay_bale(r: Node3D) -> void:
	box(r, Vector3(0.95, 0.45, 0.5), Vector3(0, 0.225, 0), Color(0.88, 0.74, 0.38))
	for x in [-0.25, 0.25]:
		box(r, Vector3(0.04, 0.47, 0.52), Vector3(x, 0.225, 0), Color(0.6, 0.45, 0.2))
