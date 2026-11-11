extends Node3D
## Dresses the map with the nature and street models made in art/world_assets: rocks (a few big
## boulders, clusters and single rocks), ground cover (grass tufts, flower patches, clover), bushes,
## hedges, picket fences, lamp posts and benches. main.gd builds it once after the trees, passes
## in the places that must stay clear, and adds the returned obstacles to its walking grid.
##
## Everything is placed with a fixed seed, so the map is the same every time. Small plants are
## GPU-instanced in 16 m cells that fade out in the distance; flowers and clover rest in winter.

const Catalog = preload("res://scripts/catalog.gd")
const Town = preload("res://scripts/town.gd")
const World = preload("res://scripts/world.gd")

const P := "res://assets/props/"
const CELL := 16.0
const COUNTRY := Rect2(-24, -36, 110, 66) # the same range the trees are scattered over
const MEADOW := Rect2(-14, -28, 92, 48) # where the grass shader grows blades
const WALK := Rect2(-6, -20, 80, 36) # the part of the map the walking grid covers

var rng := RandomNumberGenerator.new()
var avoid: Array[Rect2] = []
var taken: Array[Vector3] = [] # x, z, radius: trees and rocks already standing
var blockers: Array = []
## For god mode (scripts/god_mode.gd): the obstacle each rock, hedge and fence segment made, by
## where it stands (Vector2i of its x and z in centimetres).
var block_at := {}
var _meshes := {}
var _seasonal: Array[Node3D] = []
var _season_shown := ""
var _tick := 0.0


## root: the world node the trees were added to. keep: extra rectangles (x, z, w, d) to leave bare.
func build(root: Node3D, keep: Array) -> Array:
	rng.seed = 77
	for r in keep:
		avoid.append(r as Rect2)
	_note_trees(root)
	_rocks()
	_hedges_and_fences()
	_lamps_and_benches()
	_bushes()
	_ground_cover()
	return blockers


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var s: String = Game.season_name()
	if s == _season_shown:
		return
	_season_shown = s
	for n in _seasonal:
		n.visible = s != "Winter"


# --- helpers -----------------------------------------------------------------------

func _mesh(model: String) -> ArrayMesh:
	if _meshes.has(model):
		return _meshes[model]
	var path := P + model + ".glb"
	var mesh: ArrayMesh = null
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (mi as MeshInstance3D).mesh as ArrayMesh
			break
		inst.free()
	_meshes[model] = mesh
	return mesh


## Instances `model` at each transform, grouped into CELL-sized MultiMeshes so far cells are culled.
func _scatter(model: String, items: Array, shadows: bool, view: float, seasonal := false) -> void:
	var mesh := _mesh(model)
	if mesh == null or items.is_empty():
		return
	var cells := {}
	for t in items:
		var tf: Transform3D = t
		var key := Vector2i(floori(tf.origin.x / CELL), floori(tf.origin.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(tf)
	for key in cells:
		var list: Array = cells[key]
		var centre := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var tf: Transform3D = list[i]
			tf.origin -= centre
			mm.set_instance_transform(i, tf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [model, key.x, key.y]
		mmi.multimesh = mm
		mmi.position = centre
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if view > 0.0:
			mmi.visibility_range_end = view
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		add_child(mmi)
		if seasonal:
			_seasonal.append(mmi)


static func _xf(p: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), p)


func _note_trees(root: Node3D) -> void:
	for c in root.get_children():
		if c is MultiMeshInstance3D and str(c.name).begins_with("Trees_"):
			var mm := (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				taken.append(Vector3(o.x, o.z, 1.6))


## True if (x, z) is clear of every keep-out rectangle (grown by `margin`) and of anything standing
## within `gap` metres (trees and rocks count with their own radius).
func _clear(x: float, z: float, margin: float, gap: float) -> bool:
	var p := Vector2(x, z)
	for r in avoid:
		if r.grow(margin).has_point(p):
			return false
	for t in taken:
		if Vector2(t.x, t.y).distance_to(p) < t.z + gap:
			return false
	return true


func _reserve(x: float, z: float, r: float) -> void:
	taken.append(Vector3(x, z, r))


func _block(x: float, z: float, hx: float, hz: float) -> void:
	if WALK.has_point(Vector2(x, z)):
		var r := Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0)
		blockers.append(r)
		block_at[Vector2i(roundi(x * 100.0), roundi(z * 100.0))] = r


# --- rocks -------------------------------------------------------------------------
# kind: [model, how wide it stands (m), blocker half-width, blocker half-depth, scale range]
const ROCKS := {
	"boulder": ["rock_boulder", 2.3, 1.2, 1.0, [0.95, 1.25]],
	"cluster": ["rock_cluster", 1.8, 0.95, 0.7, [0.9, 1.35]],
	"single": ["rock_single", 1.0, 0.5, 0.45, [0.8, 1.5]],
}


func _rock(kind: String, x: float, z: float, s := -1.0) -> bool:
	var k: Array = ROCKS[kind]
	if s < 0.0:
		s = rng.randf_range(k[4][0], k[4][1])
	var r: float = float(k[1]) * 0.5 * s
	if not _clear(x, z, 0.3, r * 0.4):
		return false
	var yaw := rng.randf() * TAU
	_pending[k[0]].append(_xf(Vector3(x, -0.03 * s, z), yaw, s))
	_reserve(x, z, r + 0.4)
	_block(x, z, float(k[2]) * s, float(k[3]) * s)
	return true


var _pending := {"rock_boulder": [], "rock_cluster": [], "rock_single": []}


func _rocks() -> void:
	# a rock garden in the yard's north-west corner and one at the barn's back corner, then
	# singles along the road and by the pond, placed by hand
	for spec in [["boulder", -3.0, -14.6], ["cluster", -2.2, -8.6], ["single", -3.6, 0.8], ["single", -3.2, 8.6],
			["cluster", 25.0, -13.2], ["single", 6.9, -13.6], ["single", -1.6, -17.7], ["single", 23.8, 9.2],
			["single", 29.2, -0.6], ["cluster", 33.6, 8.2], ["single", 39.0, 6.4], ["single", 71.5, -2.0]]:
		_rock(spec[0], spec[1], spec[2])
	# a few big boulders out in the countryside, well apart from each other
	var placed := 0
	var tries := 0
	while placed < 5 and tries < 600:
		tries += 1
		var x := rng.randf_range(COUNTRY.position.x, COUNTRY.end.x)
		var z := rng.randf_range(COUNTRY.position.y, COUNTRY.end.y)
		if WALK.grow(2.0).has_point(Vector2(x, z)) or not _far_from_boulders(x, z, 22.0):
			continue
		if _rock("boulder", x, z):
			_boulders.append(Vector2(x, z))
			placed += 1
	# clusters and single rocks in loose groups: a cluster with a couple of singles around it
	placed = 0
	tries = 0
	while placed < 9 and tries < 900:
		tries += 1
		var x := rng.randf_range(COUNTRY.position.x, COUNTRY.end.x)
		var z := rng.randf_range(COUNTRY.position.y, COUNTRY.end.y)
		if WALK.has_point(Vector2(x, z)):
			continue
		if _rock("cluster", x, z):
			placed += 1
			for i in rng.randi_range(1, 3):
				var a := rng.randf() * TAU
				var d := rng.randf_range(2.6, 4.2)
				_rock("single", x + cos(a) * d, z + sin(a) * d)
	placed = 0
	tries = 0
	while placed < 14 and tries < 900:
		tries += 1
		var x := rng.randf_range(COUNTRY.position.x, COUNTRY.end.x)
		var z := rng.randf_range(COUNTRY.position.y, COUNTRY.end.y)
		if _rock("single", x, z):
			placed += 1
	for model in _pending:
		_scatter(model, _pending[model], true, 120.0)


var _boulders: Array[Vector2] = []


func _far_from_boulders(x: float, z: float, d: float) -> bool:
	for b in _boulders:
		if b.distance_to(Vector2(x, z)) < d:
			return false
	return true


# --- hedges and fences -------------------------------------------------------------

## A straight run of `model` segments (each `seg` m long) from a to b, with a blocker per segment.
func _run(model: String, a: Vector2, b: Vector2, seg: float, items: Array, thick: float, grow_blockers := true) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, int(round(length / seg)))
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x) # the model's long side runs along +x
	var s := length / (n * seg)
	for i in n:
		var c := a + dir * ((i + 0.5) * length / n)
		items.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, 1, 1)), Vector3(c.x, 0, c.y)))
		var hx := absf(dir.x) * seg * 0.5 * s + absf(dir.y) * thick
		var hz := absf(dir.y) * seg * 0.5 * s + absf(dir.x) * thick
		if grow_blockers:
			_block(c.x, c.y, hx, hz)


func _hedges_and_fences() -> void:
	var hedges := []
	var fences := []
	# the yard's south edge, open at the gate; lines of hedge down both sides of the road
	_run("hedge", Vector2(-4.2, 11.5), Vector2(20.2, 11.5), 2.0, hedges, 0.45)
	_run("hedge", Vector2(28.0, 0.7), Vector2(36.0, 0.7), 2.0, hedges, 0.45)
	_run("hedge", Vector2(28.0, 5.3), Vector2(36.0, 5.3), 2.0, hedges, 0.45)
	# the cottage garden: hedge on its south and east sides
	_run("hedge", Vector2(56.2, 13.4), Vector2(68.0, 13.4), 2.0, hedges, 0.45)
	_run("hedge", Vector2(67.9, 5.6), Vector2(67.9, 13.4), 2.0, hedges, 0.45)
	# white picket fences along the east side of the yard, with a gap for the gate
	_run("fence_picket", Vector2(26.6, -18.4), Vector2(26.6, 0.2), 1.0, fences, 0.12)
	_run("fence_picket", Vector2(26.6, 5.8), Vector2(26.6, 11.4), 1.0, fences, 0.12)
	_scatter("hedge", hedges, true, 110.0)
	_scatter("fence_picket", fences, true, 110.0)
	for t in hedges:
		_reserve((t as Transform3D).origin.x, (t as Transform3D).origin.z, 1.2)


# --- lamp posts and benches ---------------------------------------------------------

func _furniture(id: String, x: float, z: float, r: int) -> void:
	var f = load("res://scripts/furniture.gd").new()
	add_child(f)
	f.setup(id, r)
	f.position = Vector3(x, 0, z)
	if not f.is_flat():
		blockers.append(f.footprint())
	_reserve(x, z, 1.3 if id == "bench" else 0.9)


func _lamps_and_benches() -> void:
	# along the road to town and the farm path, by the pond and the barn
	for p in [Vector2(29.5, 1.8), Vector2(33.4, 4.7), Vector2(12.6, 4.0), Vector2(19.6, 4.6),
			Vector2(6.8, -13.4), Vector2(19.0, -6.6), Vector2(-1.8, 8.4)]:
		_furniture("lantern", p.x, p.y, 0)
	# somewhere to sit: facing the pond, looking over the beds, and on the cottage lawn
	for b in [[2.5, -12.5, 2], [14.6, 5.0, 2], [63.5, 5.9, 0]]:
		_furniture(Catalog.world_bench(b[0], b[1]), b[0], b[1], b[2]) # one bench in five is the short one


# --- bushes ------------------------------------------------------------------------

func _bushes() -> void:
	var items := {"bush_round": [], "bush_tall": [], "bush_berry": [], "bush_autumn": []}
	var pick := func(roll: float) -> String:
		if roll < 0.34: return "bush_round"
		if roll < 0.52: return "bush_tall"
		if roll < 0.78: return "bush_berry"
		return "bush_autumn"
	# placed by hand: round the pond, by the barn, at the gate, and in the cottage garden
	var hand := [
		Vector2(0.4, -19.0), Vector2(5.2, -19.0), Vector2(-1.3, -15.2), Vector2(6.6, -16.8), Vector2(2.5, -12.0),
		Vector2(18.4, -12.2), Vector2(24.8, -12.2), Vector2(24.8, -6.8), Vector2(26.0, 3.0), Vector2(26.0, -0.8),
		Vector2(56.6, 12.4), Vector2(67.0, 6.4), Vector2(66.8, 12.4), Vector2(57.0, 7.6), Vector2(59.0, 13.0),
		Vector2(-4.2, 4.6), Vector2(-4.2, -3.6), Vector2(21.0, 10.6), Vector2(11.0, 10.6),
	]
	for p in hand:
		if _clear(p.x, p.y, 0.2, 0.3):
			var m: String = pick.call(rng.randf())
			items[m].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.85, 1.25)))
			_reserve(p.x, p.y, 0.8)
	# loose thickets across the countryside, and along tree lines
	var groups := 0
	var tries := 0
	while groups < 22 and tries < 900:
		tries += 1
		var x := rng.randf_range(MEADOW.position.x, MEADOW.end.x)
		var z := rng.randf_range(MEADOW.position.y, MEADOW.end.y)
		if not _clear(x, z, 1.2, 1.6):
			continue
		groups += 1
		var kind: String = pick.call(rng.randf())
		for i in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.0, 1.8)
			var bx := x + cos(a) * d
			var bz := z + sin(a) * d
			if _clear(bx, bz, 0.8, 0.5):
				var m: String = kind if rng.randf() < 0.7 else pick.call(rng.randf())
				items[m].append(_xf(Vector3(bx, 0, bz), rng.randf() * TAU, rng.randf_range(0.8, 1.3)))
				_reserve(bx, bz, 0.9)
	for m in items:
		_scatter(m, items[m], true, 90.0)


# --- ground cover ------------------------------------------------------------------

func _ground_cover() -> void:
	var tufts := {"tuft_small": [], "tuft_mid": [], "tuft_tall": []}
	var flowers := {"flowers_daisy": [], "flowers_buttercup": [], "flowers_wild": [], "flowers_poppy": []}
	var clover := []
	var kinds := flowers.keys()
	# meadows: a centre with tufts all round it, flower patches of one or two kinds, and clover
	var centres: Array[Vector2] = []
	var tries := 0
	while centres.size() < 78 and tries < 3000:
		tries += 1
		var c := Vector2(rng.randf_range(MEADOW.position.x, MEADOW.end.x), rng.randf_range(MEADOW.position.y, MEADOW.end.y))
		if not _clear(c.x, c.y, 0.6, 0.3):
			continue
		centres.append(c)
	for c in centres:
		var favourite: String = kinds[rng.randi() % kinds.size()]
		var other: String = kinds[rng.randi() % kinds.size()]
		for i in rng.randi_range(9, 20):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * (sqrt(rng.randf()) * 2.2)
			if _clear(p.x, p.y, 0.15, 0.0):
				var roll := rng.randf()
				var m := "tuft_small" if roll < 0.5 else ("tuft_mid" if roll < 0.85 else "tuft_tall")
				tufts[m].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.35)))
		for i in rng.randi_range(1, 3):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * (sqrt(rng.randf()) * 1.8)
			if _clear(p.x, p.y, 0.15, 0.0):
				var m := favourite if rng.randf() < 0.7 else other
				flowers[m].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.3)))
		for i in rng.randi_range(0, 2):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * (sqrt(rng.randf()) * 2.4)
			if _clear(p.x, p.y, 0.15, 0.0):
				clover.append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.9, 1.5)))
	# beside the hedges, fences and rocks, and ringing the pond: a tuft or flower every metre or two
	var edge_lines := [[Vector2(-4.2, 10.6), Vector2(20.2, 10.6)], [Vector2(28.0, 1.4), Vector2(36.0, 1.4)],
		[Vector2(28.0, 4.6), Vector2(36.0, 4.6)], [Vector2(56.2, 12.6), Vector2(68.0, 12.6)],
		[Vector2(27.3, -18.0), Vector2(27.3, 0.0)], [Vector2(27.3, 6.0), Vector2(27.3, 11.0)]]
	for l in edge_lines:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var n := int(a.distance_to(b) / 1.6)
		for i in n:
			var p := a.lerp(b, (i + rng.randf()) / n) + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
			if _clear(p.x, p.y, 0.1, 0.0):
				if rng.randf() < 0.45:
					var m: String = kinds[rng.randi() % kinds.size()]
					flowers[m].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.2)))
				else:
					tufts["tuft_mid"].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.9, 1.3)))
	for i in 26:
		var a := TAU * i / 26.0 + rng.randf_range(-0.1, 0.1)
		var d := rng.randf_range(3.2, 4.4)
		var p := Vector2(2.5, -16.0) + Vector2.from_angle(a) * d
		if _clear(p.x, p.y, 0.1, 0.0):
			if i % 3 == 0:
				flowers["flowers_daisy" if i % 2 == 0 else "flowers_buttercup"].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, 1.0))
			else:
				tufts["tuft_tall"].append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.9, 1.3)))
	for m in tufts:
		_scatter(m, tufts[m], false, 48.0)
	for m in flowers:
		_scatter(m, flowers[m], false, 52.0, true)
	_scatter("clover_patch", clover, false, 40.0, true)
