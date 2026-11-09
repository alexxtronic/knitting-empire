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
const STALL := Vector3(48.5, 0, -7.2)
const SHOP := Rect2(53.5, -14.0, 6.0, 5.0) # Woolly Goods, door on the south side
const OFFICE := Rect2(61.5, -13.5, 5.5, 5.0) # Land Office
const BAKERY := Rect2(39.0, -13.0, 5.5, 4.5)
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
const COBBLE := Color(0.66, 0.62, 0.55)


## Builds everything static. Returns {"blockers": Array[Rect2], "board": Label3D,
## "sign_to_town": Landmark, "sign_to_farm": Landmark}.
static func build(root: Node3D) -> Dictionary:
	var blockers := []
	# the road from the farm and the town paths are worn earth in the ground shader (PATHS)
	# cobbled plaza with a checker of slightly different stones
	Catalog.box(root, Vector3(PLAZA.size.x, 0.012, PLAZA.size.y), Vector3(PLAZA.get_center().x, -0.001, PLAZA.get_center().y), COBBLE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 70:
		var p := Vector3(rng.randf_range(PLAZA.position.x + 0.4, PLAZA.end.x - 0.4), 0.004, rng.randf_range(PLAZA.position.y + 0.4, PLAZA.end.y - 0.4))
		Catalog.box(root, Vector3(0.5, 0.01, 0.5), p, COBBLE.darkened(rng.randf_range(0.04, 0.12)), Vector3(0, rng.randf() * 90.0, 0))
	# the cottage yard reads as a tidy lawn
	blockers.append(_fountain(root, FOUNTAIN))
	var stall := _stall(root, STALL)
	blockers.append_array(stall["blockers"])
	blockers.append(building(root, SHOP, Color(0.86, 0.78, 0.62), Color(0.36, 0.42, 0.5), "WOOLLY GOODS", 56.5, Color(0.55, 0.65, 0.8)))
	blockers.append(building(root, OFFICE, Color(0.74, 0.55, 0.42), Color(0.3, 0.26, 0.25), "LAND OFFICE", 64.25, Color(0.85, 0.75, 0.45)))
	blockers.append(building(root, BAKERY, Color(0.95, 0.88, 0.75), Color(0.62, 0.25, 0.2), "BAKERY", 41.75, Color(0.95, 0.65, 0.4)))
	var to_town := signpost(root, Vector3(25.6, 0, 1.75), "MAPLEWOOD  →", "travel_town", "Signpost: Maplewood")
	var to_farm := signpost(root, Vector3(38.2, 0, 1.75), "←  BIRCHFIELD FARM", "travel_farm", "Signpost: Birchfield Farm")
	blockers.append(Rect2(25.45, 1.6, 0.3, 0.3))
	blockers.append(Rect2(38.05, 1.6, 0.3, 0.3))
	return {"blockers": blockers, "board": stall["board"], "sign_to_town": to_town, "sign_to_farm": to_farm}


static func _fountain(root: Node3D, c: Vector3) -> Rect2:
	Catalog.cyl(root, 1.55, 1.65, 0.5, c + Vector3(0, 0.25, 0), Catalog.STONE, Vector3.ZERO, 28)
	var water := Catalog.cyl(root, 1.38, 1.38, 0.06, c + Vector3(0, 0.47, 0), Color(0.36, 0.58, 0.7), Vector3.ZERO, 28)
	water.material_override = Catalog.mat(Color(0.36, 0.58, 0.7), 0.05)
	Catalog.cyl(root, 0.18, 0.24, 1.3, c + Vector3(0, 0.95, 0), Catalog.STONE_DARK)
	Catalog.cyl(root, 0.62, 0.32, 0.22, c + Vector3(0, 1.6, 0), Catalog.STONE, Vector3.ZERO, 20)
	var top := Catalog.cyl(root, 0.52, 0.52, 0.04, c + Vector3(0, 1.69, 0), Color(0.45, 0.68, 0.8), Vector3.ZERO, 20)
	Catalog.glow(top, Color(0.45, 0.68, 0.8), 0.3)
	Catalog.ball(root, 0.14, c + Vector3(0, 1.85, 0), Color(0.6, 0.8, 0.9))
	return Rect2(c.x - 1.75, c.z - 1.75, 3.5, 3.5)


## Rosa's market stall: counter, striped awning, goods and a daily price board.
static func _stall(root: Node3D, pos: Vector3) -> Dictionary:
	var s := Node3D.new()
	s.position = pos
	root.add_child(s)
	Catalog.box(s, Vector3(3.0, 0.88, 0.8), Vector3(0, 0.44, 0), Catalog.WOOD)
	Catalog.box(s, Vector3(3.1, 0.06, 0.9), Vector3(0, 0.91, 0), Catalog.WOOD_LIGHT)
	for x in [-1.45, 1.45]:
		Catalog.box(s, Vector3(0.1, 2.45, 0.1), Vector3(x, 1.22, 0.3), Catalog.WOOD_DARK)
		Catalog.box(s, Vector3(0.1, 2.75, 0.1), Vector3(x, 1.37, -1.55), Catalog.WOOD_DARK)
	for i in 6:
		var c := Catalog.PLAID if i % 2 == 0 else Catalog.CREAM
		Catalog.box(s, Vector3(0.52, 0.05, 2.2), Vector3(-1.3 + i * 0.52, 2.62, -0.62), c, Vector3(-11, 0, 0))
	# folded sweaters and a crate of pumpkins on the counter
	var cols := [Color(0.75, 0.2, 0.18), Catalog.CREAM, Color(0.35, 0.5, 0.35), Color(0.3, 0.4, 0.6)]
	for i in 4:
		for k in 2:
			Catalog.box(s, Vector3(0.42, 0.09, 0.32), Vector3(-1.0 + i * 0.48, 0.99 + k * 0.095, 0.05), cols[(i + k) % 4], Vector3(0, (i * 13 + k * 7) % 9 - 4, 0))
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
	var r := Rect2(pos.x - 1.55, pos.z - 0.45, 3.1, 0.9)
	return {"board": board, "blockers": [r, Rect2(pos.x - 1.5, pos.z - 1.6, 0.2, 0.2), Rect2(pos.x + 1.3, pos.z - 1.6, 0.2, 0.2), Rect2(pos.x - 2.25, pos.z + 0.25, 0.2, 0.2), Rect2(pos.x + 1.5, pos.z - 0.05, 0.8, 0.7)]}


## A shop front: walls, gable roof, door, windows and a sign. Door on the south (+z) side at door_x.
static func building(root: Node3D, r: Rect2, wall: Color, roof: Color, sign_text: String, door_x: float, trim: Color) -> Rect2:
	var b := Node3D.new()
	var c := r.get_center()
	b.position = Vector3(c.x, 0, c.y)
	root.add_child(b)
	var w := r.size.x
	var d := r.size.y
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
	var l := Label3D.new()
	l.text = sign_text
	l.font_size = 60
	l.pixel_size = 0.005
	l.outline_size = 0
	l.modulate = Color(0.3, 0.18, 0.1)
	l.position = Vector3(0, h - 0.4, front + 0.085)
	b.add_child(l)
	return Rect2(r.position.x - 0.2, r.position.y - 0.2, w + 0.4, d + 0.4)


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
