extends RefCounted
## Maplewood: the little town east of the farm. Layout constants and static scenery
## (road, plaza, fountain, market stall, shop fronts, signposts). Villagers, the
## cottage's walls and gameplay live in main.gd.

const Catalog = preload("res://scripts/catalog.gd")
const Landmark = preload("res://scripts/landmark.gd")

const ROAD := Rect2(26.0, 2.2, 11.0, 1.6) # farm gate → town, along z ≈ 3
const TOWN := Rect2(36.0, -16.0, 34.0, 30.0) # walkable town area: x 36..70, z -16..14
const PLAZA := Rect2(45.0, -6.0, 16.0, 10.0)
const FOUNTAIN := Vector3(53.0, 0, -1.0)
const FOUNTAIN_MODEL := "res://assets/props/plaza_fountain.glb"
const STALL_MODEL := "res://assets/props/market_stall.glb"
const STALL := Vector3(48.5, 0, -7.2)
const SHOP := Rect2(53.5, -14.0, 6.0, 5.0) # Woolly Goods, door on the south side
const OFFICE := Rect2(61.5, -13.5, 5.5, 5.0) # Land Office
const BAKERY := Rect2(39.0, -13.0, 5.5, 4.5)
const MODEL_DIR := "res://assets/props/"
const BUILDING_SIGN_Y := 3.02 # the modelled sign board's centre (SIGN_Z in the build script)
const COTTAGE_LOT := Rect2(56.0, 4.6, 12.0, 9.0) # x 56..68, z 4.6..13.6
const COTTAGE := Rect2(58.0, 7.0, 7.0, 5.0) # wall lines: x 58..65, z 7..12
const COTTAGE_DOOR := Vector2(60.8, 62.2) # gap in the north wall (x range)
const TOWN_ARRIVE := Vector3(41.0, 0, 3.0)
const FARM_ARRIVE := Vector3(23.5, 0, 3.0)
# Villager homes are in res://data/villagers.json.

const PATH := Color(0.62, 0.50, 0.34)
## The road from the farm and the town paths: bakery lane, shop door, office door, cottage walk.
const PATHS := [Rect2(16.8, 2.35, 28.4, 1.3), Rect2(41.2, -8.8, 1.1, 11.0), Rect2(55.95, -9.2, 1.1, 3.2),
	Rect2(63.7, -8.5, 1.1, 2.6), Rect2(60.85, 3.9, 1.3, 3.2)]
const COBBLE := Color(0.5, 0.47, 0.42) # real stone is darker than it looks; the sun does the rest
## Cobblestones (assets/textures/cobblestone.png, a seamless painted tile, with a bump map made
## from it) cover the plaza and the town lanes; the farm road stays worn earth.
const COBBLE_TILE := 2.2 # metres of ground one repeat of the texture covers (about 40 cm a stone)
const COBBLE_PATHS := [1, 2, 3, 4] # which of PATHS are cobbled: bakery lane, shop, office, cottage walk
static var _cobble_mat: StandardMaterial3D


## Builds everything static. Returns {"blockers": Array[Rect2], "board": Label3D,
## "sign_to_town": Landmark, "sign_to_farm": Landmark}.
static func build(root: Node3D) -> Dictionary:
	var blockers := []
	# the road from the farm is worn earth in the ground shader (PATHS); the plaza and the
	# lanes off it are cobbled, all with one world-mapped texture so the stones line up
	var paved: Array[Rect2] = [PLAZA]
	for i in COBBLE_PATHS:
		paved.append(PATHS[i])
	cobble_tiles(root, paved)
	# the cottage yard reads as a tidy lawn
	blockers.append(_fountain(root, FOUNTAIN))
	var stall := _stall(root, STALL)
	blockers.append_array(stall["blockers"])
	blockers.append(building(root, SHOP, Color(0.86, 0.78, 0.62), Color(0.36, 0.42, 0.5), "WOOLLY GOODS", 56.5, Color(0.55, 0.65, 0.8), "shop"))
	blockers.append(building(root, OFFICE, Color(0.74, 0.55, 0.42), Color(0.3, 0.26, 0.25), "LAND OFFICE", 64.25, Color(0.85, 0.75, 0.45), "office"))
	blockers.append(building(root, BAKERY, Color(0.95, 0.88, 0.75), Color(0.62, 0.25, 0.2), "BAKERY", 41.75, Color(0.95, 0.65, 0.4), "bakery"))
	var to_town := signpost(root, Vector3(25.6, 0, 1.75), "MAPLEWOOD  →", "travel_town", "Signpost: Maplewood")
	var to_farm := signpost(root, Vector3(38.2, 0, 1.75), "←  BIRCHFIELD FARM", "travel_farm", "Signpost: Birchfield Farm")
	blockers.append(Rect2(25.45, 1.6, 0.3, 0.3))
	blockers.append(Rect2(38.05, 1.6, 0.3, 0.3))
	return {"blockers": blockers, "board": stall["board"], "sign_to_town": to_town, "sign_to_farm": to_farm}


static func cobble_material() -> StandardMaterial3D:
	if _cobble_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = preload("res://assets/textures/cobblestone.png")
		m.albedo_color = Color(0.86, 0.84, 0.82)
		m.normal_enabled = true
		m.normal_texture = preload("res://assets/textures/cobblestone_normal.png")
		m.normal_scale = 0.9
		m.roughness = 0.92
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / COBBLE_TILE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cobble_mat = m
	return _cobble_mat


## 3D cobblestones (art/world_assets/cobbles): an even sett pattern in white cement, laid as a
## grid of seamless tiles over each rectangle. Wide areas get 4 x 2 m plaza tiles; narrow lanes
## get 1 x 0.8 m lane tiles in a row along their length (turned for an east-west lane), each row
## stretched a little to end exactly at the rect. Each tile kind comes in variants that join each
## other; every cell picks one at random, so the paving never visibly repeats. Falls back to the
## flat painted texture if the models are missing.
const COBBLE_TILES := {
	"plaza": ["res://assets/props/cobble_plaza_0.glb", "res://assets/props/cobble_plaza_1.glb",
		"res://assets/props/cobble_plaza_2.glb", "res://assets/props/cobble_plaza_3.glb"],
	"lane": ["res://assets/props/cobble_lane_0.glb", "res://assets/props/cobble_lane_1.glb"],
}
const COBBLE_PLAZA_TILE := Vector2(4.0, 2.0)
const COBBLE_LANE_TILE := Vector2(1.0, 0.8)


static func cobble_tiles(root: Node3D, rects: Array[Rect2]) -> void:
	var meshes := {} # "plaza_0" -> Mesh
	for kind in COBBLE_TILES:
		var paths: Array = COBBLE_TILES[kind]
		for v in paths.size():
			var path: String = paths[v]
			if not ResourceLoader.exists(path):
				for r in rects:
					cobble(root, r)
				return
			var inst := (load(path) as PackedScene).instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				meshes["%s_%d" % [kind, v]] = (mi as MeshInstance3D).mesh
				break
			inst.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var spots := {} # "plaza_0" -> [Transform3D, ...]
	for key in meshes:
		spots[key] = []
	for r in rects:
		if minf(r.size.x, r.size.y) >= 2.0:
			var t := COBBLE_PLAZA_TILE
			var nx := maxi(1, roundi(r.size.x / t.x))
			var nz := maxi(1, roundi(r.size.y / t.y))
			var sx := r.size.x / (nx * t.x)
			var sz := r.size.y / (nz * t.y)
			for i in nx:
				for j in nz:
					var c := Vector3(r.position.x + (i + 0.5) * t.x * sx, 0, r.position.y + (j + 0.5) * t.y * sz)
					spots["plaza_%d" % rng.randi_range(0, 3)].append(Transform3D(Basis.from_scale(Vector3(sx, 1, sz)), c))
		else:
			var along_z := r.size.y >= r.size.x
			var length := r.size.y if along_z else r.size.x
			var width := r.size.x if along_z else r.size.y
			var n := maxi(1, roundi(length / COBBLE_LANE_TILE.y))
			var step := length / n
			for k in n:
				var d := (k + 0.5) * step
				var c := Vector3(r.position.x + width * 0.5, 0, r.position.y + d) if along_z else Vector3(r.position.x + d, 0, r.position.y + width * 0.5)
				var b := Basis.from_scale(Vector3(width / COBBLE_LANE_TILE.x, 1, step / COBBLE_LANE_TILE.y))
				if not along_z:
					b = Basis(Vector3.UP, PI / 2) * b
				spots["lane_%d" % rng.randi_range(0, 1)].append(Transform3D(b, c))
	for key in spots:
		var list: Array = spots[key]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cobbles_" + key
		mmi.multimesh = mm
		root.add_child(mmi)


## A flat patch of cobblestones over a ground rectangle (x, z): the old painted texture, used
## only if the cobble models are missing.
static func cobble(root: Node3D, r: Rect2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = r.size
	mi.mesh = pm
	mi.position = Vector3(r.get_center().x, 0.006, r.get_center().y)
	mi.material_override = cobble_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## The plaza fountain (assets/props/plaza_fountain.glb: an eight-sided block basin, a bowl on a
## baluster, a jet and eight spills). The model's water is still; here its two water surfaces get
## the moving-ring shader and droplets fly from the jet and fall from the bowl's rim.
static func _fountain(root: Node3D, c: Vector3) -> Rect2:
	var f := Node3D.new()
	f.name = "fountain"
	f.position = c
	root.add_child(f)
	var inst := Catalog.model(FOUNTAIN_MODEL, f)
	if inst == null:
		Catalog.cyl(f, 1.55, 1.65, 0.5, Vector3(0, 0.25, 0), Catalog.STONE, Vector3.ZERO, 28)
		Catalog.cyl(f, 0.18, 0.24, 1.3, Vector3(0, 0.95, 0), Catalog.STONE_DARK)
		return Rect2(c.x - 1.75, c.z - 1.75, 3.5, 3.5)
	var water := ShaderMaterial.new()
	water.shader = preload("res://shaders/fountain_water.gdshader")
	water.set_shader_parameter("centre", c)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm and sm.resource_name == "Water_fountain":
				m.set_surface_override_material(i, water)
	# the jet: droplets thrown up from the nozzle that fall back into the bowl
	var jet := _droplets(f, Vector3(0, 1.95, 0), 70, 0.75)
	jet.direction = Vector3.UP
	jet.spread = 9.0
	jet.initial_velocity_min = 2.6
	jet.initial_velocity_max = 3.1
	# the spills: droplets leaving the bowl's rim all the way round and dropping into the basin
	var spill := _droplets(f, Vector3(0, 1.8, 0), 90, 0.5)
	spill.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	spill.emission_ring_axis = Vector3.UP
	spill.emission_ring_radius = 0.8
	spill.emission_ring_inner_radius = 0.77
	spill.emission_ring_height = 0.02
	spill.direction = Vector3.DOWN
	spill.spread = 6.0
	spill.initial_velocity_min = 0.1
	spill.initial_velocity_max = 0.4
	return Rect2(c.x - 1.75, c.z - 1.75, 3.5, 3.5)


static func _droplets(parent: Node3D, pos: Vector3, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var drop := SphereMesh.new()
	drop.radius = 0.014
	drop.height = 0.04
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.93, 0.98, 0.97, 0.75)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	p.mesh = drop
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Rosa's market stall: counter, striped awning, goods and a daily price board.
static func _stall(root: Node3D, pos: Vector3) -> Dictionary:
	var s := Node3D.new()
	s.position = pos
	root.add_child(s)
	# Rosa's stall: counter, striped canopy, folded sweaters and the "Sweaters 4 Sale" plaque
	# (assets/props/market_stall.glb, about 3.1 x 1.5 m and 2.6 m tall, front towards the plaza)
	if Catalog.model(STALL_MODEL, s) == null:
		Catalog.box(s, Vector3(3.0, 0.88, 0.8), Vector3(0, 0.44, 0), Catalog.WOOD)
	# a crate of pumpkins beside it
	Catalog.box(s, Vector3(0.7, 0.35, 0.55), Vector3(1.9, 0.18, 0.4), Catalog.WOOD_LIGHT)
	for i in 3:
		Catalog.ball(s, 0.16, Vector3(1.72 + i * 0.18, 0.42, 0.4 + (i % 2) * 0.08), Color(0.95, 0.5, 0.12), Vector3(1, 0.8, 1))
	# price board on a post beside the stall
	Catalog.box(s, Vector3(0.08, 1.5, 0.08), Vector3(-2.15, 0.75, 0.35), Catalog.WOOD_DARK)
	Catalog.box(s, Vector3(0.95, 0.75, 0.05), Vector3(-2.15, 1.55, 0.4), Color(0.2, 0.24, 0.2))
	Catalog.box(s, Vector3(1.03, 0.83, 0.04), Vector3(-2.15, 1.55, 0.37), Catalog.WOOD)
	var board := Label3D.new()
	board.font_size = 30
	board.pixel_size = 0.0042
	board.outline_size = 0
	board.modulate = Color(0.96, 0.94, 0.86)
	board.position = Vector3(-2.15, 1.55, 0.43)
	s.add_child(board)
	var r := Rect2(pos.x - 1.56, pos.z - 0.76, 3.12, 1.5) # the stall's whole footprint, posts included
	return {"board": board, "blockers": [r, Rect2(pos.x - 2.25, pos.z + 0.25, 0.2, 0.2), Rect2(pos.x + 1.5, pos.z - 0.05, 0.8, 0.7)]}


## A shop front: walls, gable roof, door, windows and a sign. Door on the south (+z) side at door_x.
## A shop front on rect r, door facing +Z (south). With a model id it uses the modelled building
## assets/props/building_<id>.glb (made by art/world_assets/town_buildings/build.py, sized to the
## rect, door centred) and writes the name on its sign board; without one it builds simple boxes.
static func building(root: Node3D, r: Rect2, wall: Color, roof: Color, sign_text: String, door_x: float, trim: Color, model_id := "") -> Rect2:
	var b := Node3D.new()
	var c := r.get_center()
	b.position = Vector3(c.x, 0, c.y)
	root.add_child(b)
	var w := r.size.x
	var d := r.size.y
	var path := MODEL_DIR + "building_%s.glb" % model_id
	if model_id != "" and ResourceLoader.exists(path) and Catalog.model(path, b) != null:
		b.name = "Building_" + model_id
		b.set_meta("building_model", model_id)
		b.add_child(_sign_label(sign_text, Vector3(0, BUILDING_SIGN_Y, d * 0.5 + 0.095)))
		# the steps and porch stand a little proud of the front wall
		return Rect2(r.position.x - 0.2, r.position.y - 0.2, w + 0.4, d + 0.75)
	var h := 3.0
	var gable := 1.6
	Catalog.box(b, Vector3(w, h, d), Vector3(0, h * 0.5, 0), wall)
	Catalog.box(b, Vector3(w + 0.3, 0.25, d + 0.3), Vector3(0, 0.12, 0), Catalog.STONE)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Catalog.box(b, Vector3(0.18, h, 0.18), Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), Catalog.WOOD_DARK)
	Catalog.box(b, Vector3(w + 0.1, 0.16, d + 0.1), Vector3(0, h, 0), Catalog.WOOD_DARK)
	var pm := PrismMesh.new()
	pm.size = Vector3(w, gable, d)
	var g := MeshInstance3D.new()
	g.mesh = pm
	g.material_override = Catalog.mat(wall)
	g.position = Vector3(0, h + gable * 0.5, 0)
	b.add_child(g)
	var half := w * 0.5 + 0.3
	var ang := rad_to_deg(atan2(gable, half))
	var slope := sqrt(half * half + gable * gable)
	for sx in [-1, 1]:
		Catalog.box(b, Vector3(slope + 0.1, 0.14, d + 0.5), Vector3(sx * half * 0.5, h + gable * 0.5 + 0.06, 0), roof, Vector3(0, 0, -sx * ang))
	Catalog.box(b, Vector3(0.5, 1.2, 0.5), Vector3(w * 0.25, h + gable * 0.9, -d * 0.2), Catalog.STONE_DARK)
	var front := d * 0.5
	var dx := door_x - c.x
	Catalog.box(b, Vector3(1.1, 2.15, 0.08), Vector3(dx, 1.08, front + 0.03), Catalog.WOOD)
	Catalog.box(b, Vector3(1.3, 0.12, 0.12), Vector3(dx, 2.2, front + 0.05), Catalog.WOOD_DARK)
	Catalog.ball(b, 0.04, Vector3(dx + 0.38, 1.05, front + 0.09), Catalog.BRASS)
	for wx in [-w * 0.3, w * 0.3]:
		if absf(wx - dx) < 1.2:
			continue
		var glass := Catalog.box(b, Vector3(1.0, 0.95, 0.06), Vector3(wx, 1.5, front + 0.02), Color(0.7, 0.85, 0.95))
		glass.material_override = Catalog.mat(Color(0.75, 0.85, 0.9), 0.1, 0.0)
		Catalog.box(b, Vector3(1.16, 0.08, 0.1), Vector3(wx, 1.0, front + 0.04), Catalog.WOOD_DARK)
		Catalog.box(b, Vector3(1.16, 0.08, 0.1), Vector3(wx, 2.0, front + 0.04), Catalog.WOOD_DARK)
		Catalog.box(b, Vector3(0.06, 0.95, 0.09), Vector3(wx, 1.5, front + 0.04), Catalog.WOOD_DARK)
		Catalog.box(b, Vector3(1.2, 0.18, 0.3), Vector3(wx, 0.92, front + 0.15), trim) # flower box
	Catalog.box(b, Vector3(minf(w - 0.6, 3.4), 0.5, 0.06), Vector3(0, h - 0.4, front + 0.05), Catalog.CREAM)
	Catalog.box(b, Vector3(minf(w - 0.6, 3.4) + 0.1, 0.6, 0.04), Vector3(0, h - 0.4, front + 0.03), Catalog.WOOD_DARK)
	b.add_child(_sign_label(sign_text, Vector3(0, h - 0.4, front + 0.085)))
	return Rect2(r.position.x - 0.2, r.position.y - 0.2, w + 0.4, d + 0.4)


static func _sign_label(text: String, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 60
	l.pixel_size = 0.005
	l.outline_size = 0
	l.modulate = Color(0.3, 0.18, 0.1)
	l.position = pos
	return l


static func signpost(root: Node3D, pos: Vector3, text: String, kind: String, title: String) -> Landmark:
	var s := Landmark.new()
	s.kind = kind
	s.title = title
	s.position = pos
	root.add_child(s)
	Catalog.box(s, Vector3(0.12, 1.7, 0.12), Vector3(0, 0.85, 0), Catalog.WOOD_DARK)
	Catalog.box(s, Vector3(1.9, 0.38, 0.06), Vector3(0, 1.45, 0.07), Catalog.WOOD_LIGHT)
	var l := Label3D.new()
	l.text = text
	l.font_size = 34
	l.pixel_size = 0.0045
	l.outline_size = 0
	l.modulate = Color(0.28, 0.16, 0.08)
	l.position = Vector3(0, 1.45, 0.105)
	s.add_child(l)
	pickable(s, Vector3(2.0, 1.9, 0.5), Vector3(0, 0.95, 0))
	return s


static func pickable(n: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	body.add_child(cs)
	body.set_meta("target", n)
	n.add_child(body)
