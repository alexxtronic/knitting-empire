extends RefCounted
## Static scenery: ground, paths, trees, barn, pond, sheep pen, shipping bin.

const Catalog = preload("res://scripts/catalog.gd")

const GRASS := Color(0.43, 0.58, 0.28)
const PATH := Color(0.62, 0.50, 0.34)

## Shared by every canopy (colour per tree is an instance uniform) and the pond, so main.gd can
## turn up the wind and the rain on all of them at once.
static var foliage_mat: ShaderMaterial
static var water_mat: ShaderMaterial


static func _foliage(m: MeshInstance3D, c: Color) -> void:
	if foliage_mat == null:
		foliage_mat = ShaderMaterial.new()
		foliage_mat.shader = preload("res://shaders/foliage.gdshader")
	m.material_override = foliage_mat
	m.set_instance_shader_parameter("tint", c)


## Worn-earth paths on the farm: door → along the farm → sheep pen gate. Drawn by the
## ground shader (grass.gd), not as boxes.
const PATHS := [Rect2(8.1, 2.55, 9.0, 0.9), Rect2(16.15, -0.95, 0.9, 4.4), Rect2(16.5, -1.45, 1.0, 0.9)]


## The ground itself is grass.gd; this adds the doormat and fallen leaves.
static func build_ground(root: Node3D, lot: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# doormat
	Catalog.box(root, Vector3(0.9, 0.02, 1.2), Vector3(8.6, 0.0, 3.0), Color(0.45, 0.33, 0.2))
	# fallen autumn leaves
	var leaf_cols := [Color(0.88, 0.5, 0.15), Color(0.8, 0.3, 0.12), Color(0.92, 0.7, 0.2)]
	for i in 140:
		var p := Vector3(rng.randf_range(lot.position.x, lot.end.x), 0.004, rng.randf_range(lot.position.y, lot.end.y))
		if p.x > -0.6 and p.x < 8.6 and p.z > -12.6 and p.z < 6.6:
			continue # not inside the house footprint
		Catalog.box(root, Vector3(0.12, 0.005, 0.08), p, leaf_cols[rng.randi() % 3], Vector3(0, rng.randf() * 360.0, 0))


static func build_trees(root: Node3D, keep_out: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var placed := 0
	var tries := 0
	while placed < 115 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-24, 86)
		var z := rng.randf_range(-36, 30)
		var blocked := false
		for r in keep_out:
			if (r as Rect2).grow(1.0).has_point(Vector2(x, z)):
				blocked = true
				break
		if blocked:
			continue
		_tree(root, Vector3(x, 0, z), rng)
		placed += 1


static func _tree(root: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = rng.randf() * TAU
	var s := rng.randf_range(0.8, 1.4)
	t.scale = Vector3(s, s, s)
	root.add_child(t)
	Catalog.cyl(t, 0.15, 0.22, 2.0, Vector3(0, 1, 0), Catalog.WOOD_DARK)
	if rng.randf() < 0.3:
		var pine := Color(0.2, 0.36, 0.22)
		_foliage(Catalog.cyl(t, 0.0, 1.3, 2.2, Vector3(0, 2.4, 0), pine), pine)
		_foliage(Catalog.cyl(t, 0.0, 1.0, 1.8, Vector3(0, 3.4, 0), pine.lightened(0.05)), pine.lightened(0.05))
		_foliage(Catalog.cyl(t, 0.0, 0.7, 1.4, Vector3(0, 4.2, 0), pine.lightened(0.1)), pine.lightened(0.1))
	else:
		var palette := [Color(0.85, 0.45, 0.15), Color(0.9, 0.65, 0.2), Color(0.72, 0.3, 0.12),
			Color(0.42, 0.56, 0.25), Color(0.8, 0.56, 0.18)]
		var c: Color = palette[rng.randi() % palette.size()]
		_foliage(Catalog.ball(t, 1.25, Vector3(0, 2.8, 0), c), c)
		_foliage(Catalog.ball(t, 0.95, Vector3(0.65, 2.4, 0.3), c.darkened(0.1)), c.darkened(0.1))
		_foliage(Catalog.ball(t, 0.85, Vector3(-0.5, 3.4, -0.2), c.lightened(0.08)), c.lightened(0.08))


static func build_barn(root: Node3D, pos: Vector3) -> Rect2:
	var b := Node3D.new()
	b.position = pos
	root.add_child(b)
	var red := Color(0.62, 0.17, 0.14)
	var white := Color(0.95, 0.93, 0.88)
	Catalog.box(b, Vector3(5, 3.2, 4), Vector3(0, 1.6, 0), red)
	var gable := PrismMesh.new()
	gable.size = Vector3(5.0, 1.6, 4.0)
	var g := MeshInstance3D.new()
	g.mesh = gable
	g.material_override = Catalog.mat(red)
	g.position = Vector3(0, 4.0, 0)
	b.add_child(g)
	var roof := Color(0.32, 0.26, 0.25)
	Catalog.box(b, Vector3(3.2, 0.12, 4.4), Vector3(-1.3, 4.05, 0), roof, Vector3(0, 0, 32.6))
	Catalog.box(b, Vector3(3.2, 0.12, 4.4), Vector3(1.3, 4.05, 0), roof, Vector3(0, 0, -32.6))
	Catalog.box(b, Vector3(1.8, 2.2, 0.05), Vector3(0, 1.1, 2.01), red.darkened(0.2))
	Catalog.box(b, Vector3(1.95, 0.1, 0.07), Vector3(0, 2.22, 2.03), white)
	for x in [-0.95, 0.95]:
		Catalog.box(b, Vector3(0.1, 2.2, 0.07), Vector3(x, 1.1, 2.03), white)
	for a in [40, -40]:
		Catalog.box(b, Vector3(0.09, 2.6, 0.06), Vector3(0, 1.1, 2.04), white, Vector3(0, 0, a))
	Catalog.box(b, Vector3(0.8, 0.8, 0.05), Vector3(0, 3.6, 2.02), Color(0.15, 0.1, 0.08))
	Catalog.box(b, Vector3(0.95, 0.08, 0.06), Vector3(0, 4.03, 2.04), white)
	Catalog.box(b, Vector3(0.95, 0.08, 0.06), Vector3(0, 3.17, 2.04), white)
	return Rect2(pos.x - 2.6, pos.z - 2.1, 5.2, 4.2)


static func build_pond(root: Node3D, pos: Vector3, r: float) -> Rect2:
	Catalog.cyl(root, r + 0.35, r + 0.45, 0.06, pos + Vector3(0, 0.0, 0), Color(0.55, 0.52, 0.46), Vector3.ZERO, 32)
	var w := Catalog.cyl(root, r, r, 0.07, pos + Vector3(0, 0.01, 0), Color(0.32, 0.52, 0.62), Vector3.ZERO, 32)
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("centre", pos)
	water_mat.set_shader_parameter("radius", r)
	w.material_override = water_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 5:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, r - 0.3)
		Catalog.cyl(root, 0.22, 0.22, 0.01, pos + Vector3(cos(a) * d, 0.05, sin(a) * d), Color(0.35, 0.55, 0.25))
	for i in 9:
		var a := rng.randf() * TAU
		var p := pos + Vector3(cos(a) * (r + 0.3), 0.4, sin(a) * (r + 0.3))
		Catalog.cyl(root, 0.015, 0.02, 0.8, p, Color(0.45, 0.5, 0.25))
	return Rect2(pos.x - r - 0.45, pos.z - r - 0.45, 2 * r + 0.9, 2 * r + 0.9)


## Fence around `rect` with a gap on the left (west) side between gate.x and gate.y.
## Returns thin rects for each fence run (used as walking obstacles).
static func build_pen(root: Node3D, rect: Rect2, gate: Vector2) -> Array:
	var runs := [
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y)],
		[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y)],
		[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y)],
		[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, gate.x)],
		[Vector2(rect.position.x, gate.y), Vector2(rect.position.x, rect.end.y)],
	]
	var wood := Color(0.62, 0.48, 0.32)
	var rects := []
	for run in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var length := a.distance_to(b)
		var n := maxi(1, int(round(length)))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			Catalog.box(root, Vector3(0.12, 0.9, 0.12), Vector3(p.x, 0.45, p.y), wood.darkened(0.2))
		var mid := (a + b) * 0.5
		var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
		for y in [0.35, 0.7]:
			var size := Vector3(length, 0.07, 0.05) if horizontal else Vector3(0.05, 0.07, length)
			Catalog.box(root, size, Vector3(mid.x, y, mid.y), wood)
		rects.append(Rect2(minf(a.x, b.x) - 0.08, minf(a.y, b.y) - 0.08, absf(b.x - a.x) + 0.16, absf(b.y - a.y) + 0.16))
	# water trough + hay inside the pen
	var tp := Vector2(rect.end.x - 0.7, rect.position.y + 0.8)
	Catalog.box(root, Vector3(0.6, 0.35, 1.2), Vector3(tp.x, 0.175, tp.y), Catalog.WOOD)
	Catalog.box(root, Vector3(0.5, 0.02, 1.1), Vector3(tp.x, 0.34, tp.y), Color(0.35, 0.55, 0.65))
	rects.append(Rect2(tp.x - 0.35, tp.y - 0.65, 0.7, 1.3))
	return rects


static func build_bin(root: Node3D, pos: Vector3) -> Node3D:
	var b := Node3D.new()
	b.position = pos
	root.add_child(b)
	Catalog.box(b, Vector3(1.0, 0.6, 0.7), Vector3(0, 0.3, 0), Catalog.WOOD)
	for y in [0.15, 0.3, 0.45]:
		Catalog.box(b, Vector3(1.02, 0.02, 0.72), Vector3(0, y, 0), Catalog.WOOD_DARK)
	Catalog.box(b, Vector3(1.06, 0.06, 0.76), Vector3(0, 0.66, -0.05), Catalog.WOOD_DARK, Vector3(-12, 0, 0))
	Catalog.box(b, Vector3(0.6, 0.2, 0.02), Vector3(0, 0.36, 0.36), Catalog.CREAM)
	var l := Label3D.new()
	l.text = "SHIPPING"
	l.font_size = 40
	l.pixel_size = 0.0035
	l.modulate = Color(0.3, 0.18, 0.1)
	l.outline_size = 0
	l.position = Vector3(0, 0.36, 0.375)
	b.add_child(l)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.8, 0.7)
	cs.shape = bs
	cs.position.y = 0.4
	body.add_child(cs)
	body.set_meta("target", b)
	b.add_child(body)
	return b
