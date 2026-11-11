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


## The ground itself is grass.gd; this adds the doormat and fallen leaves blown into the yard.
static func build_ground(root: Node3D, lot: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# doormat
	Catalog.box(root, Vector3(0.9, 0.02, 1.2), Vector3(8.6, 0.0, 3.0), Color(0.45, 0.33, 0.2))
	# fallen leaves: drifts of a dozen or so, and strays between them
	var pts := []
	var cols: Array = LITTER["maple_autumn"]
	for i in 22:
		var c := Vector2(rng.randf_range(lot.position.x, lot.end.x), rng.randf_range(lot.position.y, lot.end.y))
		for k in rng.randi_range(6, 16):
			_add_leaf(pts, c + Vector2(rng.randfn(0.0, 0.5), rng.randfn(0.0, 0.5)), cols, rng)
	for i in 90:
		_add_leaf(pts, Vector2(rng.randf_range(lot.position.x, lot.end.x), rng.randf_range(lot.position.y, lot.end.y)), cols, rng)
	_litter(root, pts, rng)


## Leaf colours on the ground under each kind of tree (and blown into the yard).
const LITTER := {
	"maple_autumn": [Color(0.78, 0.2, 0.08), Color(0.88, 0.38, 0.08), Color(0.93, 0.6, 0.12), Color(0.95, 0.76, 0.2), Color(0.6, 0.16, 0.07), Color(0.7, 0.45, 0.2)],
	"maple_green": [Color(0.62, 0.72, 0.22), Color(0.82, 0.78, 0.25), Color(0.7, 0.52, 0.22), Color(0.55, 0.62, 0.2)],
	"spruce": [Color(0.52, 0.38, 0.2), Color(0.45, 0.32, 0.18)],
}
## The map trees (art/world_assets/trees), with how often each one turns up.
const TREE_KINDS := [["maple_autumn", 0.45], ["maple_green", 0.25], ["spruce", 0.3]]
## How many leaves lie under each kind of tree.
const LEAVES_PER_TREE := {"maple_autumn": 60, "maple_green": 20, "spruce": 6}
## The leaf materials on every tree, and the fallen leaves, so main.gd can set wind and rain.
static var leaf_mats: Array[ShaderMaterial] = []
static var litter_mat: ShaderMaterial
## For god mode (scripts/god_mode.gd): the barn, the leaves lying under the trees, and which of
## those leaves belong to which tree ("kind:index in its MultiMesh" -> Vector2i(first leaf, count)).
static var barn: Node3D
static var pond: Node3D
static var pen: Node3D
static var pen_blocks: Array = [] # the obstacle rects build_pen() made
static var tree_litter: MultiMeshInstance3D
static var tree_leaf_ranges := {}


static func _add_leaf(pts: Array, p: Vector2, cols: Array, rng: RandomNumberGenerator) -> void:
	if p.x > -0.6 and p.x < 8.6 and p.y > -12.6 and p.y < 6.6:
		return # not inside the house footprint
	var c: Color = cols[rng.randi() % cols.size()]
	pts.append([Vector3(p.x, 0.03 + rng.randf() * 0.015, p.y), c * rng.randf_range(0.85, 1.08)])


## One MultiMesh of small flat leaf cards, each turned, tilted and tinted on its own.
static func _litter(root: Node3D, pts: Array, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	if pts.is_empty() or not ResourceLoader.exists("res://assets/props/leaf_litter.png"):
		return null
	if litter_mat == null:
		litter_mat = ShaderMaterial.new()
		litter_mat.shader = preload("res://shaders/leaf_litter.gdshader")
		litter_mat.set_shader_parameter("atlas", load("res://assets/props/leaf_litter.png"))
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.orientation = PlaneMesh.FACE_Y
	q.material = litter_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = pts.size()
	for i in pts.size():
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.7, 1.35))
		mm.set_instance_transform(i, Transform3D(b, pts[i][0]))
		mm.set_instance_color(i, pts[i][1])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FallenLeaves"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


## The tree model's mesh with its leaf surfaces switched to the wind-sway shader (the painted
## texture is kept). null if the model is missing.
static func _tree_mesh(kind: String) -> ArrayMesh:
	var path := "res://assets/props/tree_%s.glb" % kind
	if not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate()
	var mesh: ArrayMesh = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mesh = (mi as MeshInstance3D).mesh as ArrayMesh
		break
	inst.free()
	if mesh == null:
		return null
	mesh = mesh.duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i)
		var mname := sm.resource_name if sm else ""
		if (mname.begins_with("Leaves_") or mname.begins_with("LeafCore_")) and sm is BaseMaterial3D:
			var leaf := ShaderMaterial.new()
			leaf.shader = preload("res://shaders/tree_leaves.gdshader")
			leaf.set_shader_parameter("albedo_tex", (sm as BaseMaterial3D).albedo_texture)
			leaf_mats.append(leaf)
			mesh.surface_set_material(i, leaf)
	return mesh


## Scatters the three tree models over the countryside (outside keep_out), one MultiMesh per
## kind, each tree turned, sized and tinted at random, with its fallen leaves around it.
static func build_trees(root: Node3D, keep_out: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	leaf_mats.clear()
	tree_leaf_ranges.clear()
	tree_litter = null
	var spots := {} # kind -> [[Transform3D, Color], ...]
	var placed: Array[Vector2] = []
	var leaves := []
	var tries := 0
	while placed.size() < 115 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-24, 86)
		var z := rng.randf_range(-36, 30)
		var at := Vector2(x, z)
		var blocked := false
		for r in keep_out:
			if (r as Rect2).grow(2.2).has_point(at):
				blocked = true
				break
		for q in placed:
			if q.distance_to(at) < 3.2:
				blocked = true
				break
		if blocked:
			continue
		placed.append(at)
		var roll := rng.randf()
		var kind: String = TREE_KINDS[-1][0]
		for k in TREE_KINDS:
			roll -= float(k[1])
			if roll < 0.0:
				kind = k[0]
				break
		var s := rng.randf_range(0.85, 1.3) if kind == "spruce" else rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var tint := Color.WHITE
		match kind:
			"maple_autumn":
				tint = Color(1.0, rng.randf_range(0.82, 1.08), rng.randf_range(0.8, 1.0))
			"maple_green":
				tint = Color(rng.randf_range(0.88, 1.05), 1.0, rng.randf_range(0.85, 1.0))
			_:
				var v := rng.randf_range(0.85, 1.05)
				tint = Color(v, v, v)
		if not spots.has(kind):
			spots[kind] = []
		spots[kind].append([Transform3D(basis, Vector3(x, 0, z)), tint])
		var n: int = LEAVES_PER_TREE[kind]
		var first_leaf := leaves.size()
		for i in n:
			var a := rng.randf() * TAU
			var d := 0.4 + 3.4 * s * sqrt(rng.randf())
			_add_leaf(leaves, at + Vector2(cos(a), sin(a)) * d, LITTER[kind], rng)
		tree_leaf_ranges["%s:%d" % [kind, spots[kind].size() - 1]] = Vector2i(first_leaf, leaves.size() - first_leaf)
	for kind in spots:
		var list: Array = spots[kind]
		var mesh := _tree_mesh(kind)
		if mesh == null:
			for e in list:
				var tf: Transform3D = e[0]
				_tree(root, tf.origin, rng)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + kind
		mmi.multimesh = mm
		root.add_child(mmi)
	tree_litter = _litter(root, leaves, rng)


## The old procedural tree, used only if a tree model is missing.
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
	barn = b
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


## The pond is one node (water, rim, lily pads, reeds), so god mode can pick it up.
static func build_pond(world: Node3D, pos: Vector3, r: float) -> Rect2:
	var root := Node3D.new()
	root.name = "Pond"
	root.position = pos
	world.add_child(root)
	pond = root
	pos = Vector3.ZERO # everything below is placed relative to the pond's node
	Catalog.cyl(root, r + 0.35, r + 0.45, 0.06, pos + Vector3(0, 0.0, 0), Color(0.55, 0.52, 0.46), Vector3.ZERO, 32)
	var w := Catalog.cyl(root, r, r, 0.07, pos + Vector3(0, 0.01, 0), Color(0.32, 0.52, 0.62), Vector3.ZERO, 32)
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("centre", root.position)
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
	var at := root.position
	return Rect2(at.x - r - 0.45, at.z - r - 0.45, 2 * r + 0.9, 2 * r + 0.9)


## Fence around `rect` with a gap on the left (west) side between gate.x and gate.y.
## Returns thin rects for each fence run (used as walking obstacles). The pen is one node at the
## middle of `rect` (fence, trough), so god mode can pick it up.
static func build_pen(world: Node3D, rect: Rect2, gate: Vector2) -> Array:
	var root := Node3D.new()
	root.name = "SheepPen"
	var mid := rect.get_center()
	root.position = Vector3(mid.x, 0, mid.y)
	world.add_child(root)
	pen = root
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
			Catalog.box(root, Vector3(0.12, 0.9, 0.12), Vector3(p.x - mid.x, 0.45, p.y - mid.y), wood.darkened(0.2))
		var half := (a + b) * 0.5
		var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
		for y in [0.35, 0.7]:
			var size := Vector3(length, 0.07, 0.05) if horizontal else Vector3(0.05, 0.07, length)
			Catalog.box(root, size, Vector3(half.x - mid.x, y, half.y - mid.y), wood)
		rects.append(Rect2(minf(a.x, b.x) - 0.08, minf(a.y, b.y) - 0.08, absf(b.x - a.x) + 0.16, absf(b.y - a.y) + 0.16))
	# water trough + hay inside the pen
	var tp := Vector2(rect.end.x - 0.7, rect.position.y + 0.8)
	Catalog.box(root, Vector3(0.6, 0.35, 1.2), Vector3(tp.x - mid.x, 0.175, tp.y - mid.y), Catalog.WOOD)
	Catalog.box(root, Vector3(0.5, 0.02, 1.1), Vector3(tp.x - mid.x, 0.34, tp.y - mid.y), Color(0.35, 0.55, 0.65))
	rects.append(Rect2(tp.x - 0.35, tp.y - 0.65, 0.7, 1.3))
	pen_blocks = rects
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
