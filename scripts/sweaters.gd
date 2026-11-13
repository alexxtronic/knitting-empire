extends RefCounted
## The knitted sweaters anyone can wear: fifty designs (data/sweaters.json, 1 Common .. 4 Legendary
## stars) on one core sweater fitted to each character (assets/sweaters/<id>_sweater.glb), all made by
## art/world_assets/sweater/build.py. A design is only a colour map; the wool itself (stitch tiles,
## rib, normals) is shaders/sweater.gdshader, shared by every design.
##
## Wearing one puts the character's own fitted sweater on their skeleton and turns on an
## `under_sweater` shape key on their body that tucks the skin it covers in under the knit. The game's
## character models don't carry that key, so the first time a body wears a sweater the key is added
## to a copy of its mesh from assets/sweaters/<id>_tuck.json (points of the body and how far each
## moves, matched by position).

const Data = preload("res://scripts/data.gd")
const DIR := "res://assets/sweaters/"
const TEX := "res://assets/sweaters/textures/"
const SHADER := preload("res://shaders/sweater.gdshader")
const NODE := "KnitSweater"
const KEY := "under_sweater"
## Positions are matched on a grid this fine (per metre): half a millimetre.
const GRID := 2000.0

static var _designs: Array = []
static var _mats := {} # design id -> ShaderMaterial
static var _tucked := {} # original mesh's instance id -> its copy with the under_sweater key
static var _tuck_points := {} # character id -> {Vector3i: Vector3}


## Every design: {id, name, stars, colours, about}.
static func designs() -> Array:
	if _designs.is_empty():
		var f := FileAccess.open("res://data/sweaters.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_designs = d.get("designs", [])
	return _designs


static func design(id: String) -> Dictionary:
	for d in designs():
		if str(d["id"]) == id:
			return d
	return {}


## The designs with this many stars.
static func of_stars(stars: int) -> Array:
	return designs().filter(func(d): return int(d["stars"]) == stars)


## The game's sweater rarity (1 Common .. 5 Legendary, Game.sweaters) as the designs' stars (1..4):
## Common and Uncommon are both one star.
static func stars_for(rarity: int) -> int:
	return [1, 1, 2, 3, 4][clampi(rarity, 1, 5) - 1]


## A design for a sweater of this rarity, picked by `pick` (any number; the same number gives the
## same design, so an old save gets the same one every time).
static func design_for(rarity: int, pick: int) -> String:
	var ds := of_stars(stars_for(rarity))
	if ds.is_empty():
		return ""
	return str(ds[posmod(pick, ds.size())]["id"])


## Whether this character has a sweater fitted to them.
static func fits(char_id: String) -> bool:
	return ResourceLoader.exists(DIR + char_id + "_sweater.glb")


static func material(id: String) -> ShaderMaterial:
	if not _mats.has(id):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("design", load(TEX + id + ".png"))
		m.set_shader_parameter("rib_mask", load(TEX + "sweater_rib_mask.png"))
		m.set_shader_parameter("stock", load(TEX + "knit_stockinette.png"))
		m.set_shader_parameter("stock_n", load(TEX + "knit_stockinette_n.png"))
		m.set_shader_parameter("rib", load(TEX + "knit_rib.png"))
		m.set_shader_parameter("rib_n", load(TEX + "knit_rib_n.png"))
		_mats[id] = m
	return _mats[id]


## The design this body is wearing, or "".
static func worn(body: Node3D) -> String:
	var mi := _sweater_node(body)
	return str(mi.get_meta("design", "")) if mi and mi.visible else ""


## Puts this design on the body (a body.gd), or takes the sweater off for "". Returns false if the
## character has no fitted sweater or the design doesn't exist.
static func wear(body: Node3D, id: String) -> bool:
	if body == null or body.skeleton == null:
		return false
	if id == "":
		take_off(body)
		return true
	if design(id).is_empty() or not fits(body.id):
		return false
	var mi := _sweater_node(body)
	if mi == null:
		mi = _fit(body)
		if mi == null:
			return false
	mi.material_override = material(id)
	mi.set_meta("design", id)
	mi.visible = true
	_set_tuck(body, 1.0)
	return true


static func take_off(body: Node3D) -> void:
	var mi := _sweater_node(body)
	if mi:
		mi.visible = false
		mi.set_meta("design", "")
	_set_tuck(body, 0.0)


## How many of the body's points the tuck moved the last time it was set up (for the checks).
static func tucked_points(body: Node3D) -> int:
	var n := 0
	for m in _body_meshes(body):
		n += int(m.get_meta("tucked_points", 0))
	return n


# --- fitting ---------------------------------------------------------------------------------------

static func _sweater_node(body: Node3D) -> MeshInstance3D:
	if body == null or body.skeleton == null:
		return null
	return body.skeleton.get_node_or_null(NODE) as MeshInstance3D


## The character's fitted sweater, moved onto their own skeleton (it was skinned to the same rig).
static func _fit(body: Node3D) -> MeshInstance3D:
	var packed := load(DIR + body.id + "_sweater.glb") as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		inst.free()
		return null
	var mi := found[0] as MeshInstance3D
	mi.get_parent().remove_child(mi)
	inst.free()
	mi.name = NODE
	mi.transform = Transform3D.IDENTITY
	# the rig the sweater was skinned to may have bones this model lacks (the eyes, on the models with
	# painted eyes). The sweater doesn't follow them, but its weights count binds by place, so keep
	# each in its place and point it at the head instead
	if mi.skin:
		var skin := mi.skin.duplicate() as Skin
		for b in skin.get_bind_count():
			if body.skeleton.find_bone(skin.get_bind_name(b)) < 0:
				skin.set_bind_name(b, "Head")
		mi.skin = skin
	body.skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	_add_tuck(body)
	return mi


## The body's skinned meshes (not the sweater).
static func _body_meshes(body: Node3D) -> Array:
	if body == null or body.skeleton == null:
		return []
	return body.find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return m.name != NODE and m.mesh is ArrayMesh and m.skin != null)


static func _set_tuck(body: Node3D, w: float) -> void:
	for m in _body_meshes(body):
		var k: int = m.find_blend_shape_by_name(KEY)
		if k >= 0:
			m.set_blend_shape_value(k, w)


static func _points(char_id: String) -> Dictionary:
	if not _tuck_points.has(char_id):
		var grid := {}
		var f := FileAccess.open(DIR + char_id + "_tuck.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			var p: Array = d.get("points", []) if d is Dictionary else []
			for i in range(0, p.size() - 5, 6):
				grid[_key(Vector3(p[i], p[i + 1], p[i + 2]))] = Vector3(p[i + 3], p[i + 4], p[i + 5])
		_tuck_points[char_id] = grid
	return _tuck_points[char_id]


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * GRID), roundi(v.y * GRID), roundi(v.z * GRID))


## Swaps each body mesh for a copy with the under_sweater key (once per mesh; every NPC with the
## same model shares the copy). Meshes none of whose points are in the tuck list are left alone.
static func _add_tuck(body: Node3D) -> void:
	var grid := _points(body.id)
	if grid.is_empty():
		return
	for m in _body_meshes(body):
		var src := m.mesh as ArrayMesh
		if src.get_meta("sweater_tuck", false) or m.find_blend_shape_by_name(KEY) >= 0:
			continue
		var key := src.get_instance_id()
		if not _tucked.has(key):
			_tucked[key] = _with_tuck(src, grid)
		var made: ArrayMesh = _tucked[key]
		if made == null:
			continue
		var weights := {}
		for b in src.get_blend_shape_count():
			weights[src.get_blend_shape_name(b)] = m.get_blend_shape_value(b)
		m.mesh = made
		m.set_meta("tucked_points", int(made.get_meta("tucked_points", 0)))
		for b in weights:
			m.set_blend_shape_value(m.find_blend_shape_by_name(b), weights[b])


static func _with_tuck(src: ArrayMesh, grid: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.blend_shape_mode = src.blend_shape_mode
	for b in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(b))
	out.add_blend_shape(KEY)
	var matched := 0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var shapes := src.surface_get_blend_shape_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tucked := verts.duplicate()
		for i in verts.size():
			var k := _key(verts[i])
			if grid.has(k):
				tucked[i] = verts[i] + grid[k]
				matched += 1
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = tucked
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(shape)
		var flags := src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, shapes, {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	if matched == 0:
		return null
	out.set_meta("sweater_tuck", true)
	out.set_meta("tucked_points", matched)
	return out
