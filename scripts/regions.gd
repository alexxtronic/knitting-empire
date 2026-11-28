extends Node3D
## The lands round the farm and Maple Grove, one continuous world with no loading screens:
## Mirewood Swamp to the west, the Greyspine foothills and their mountain range to the north,
## Saltmeadow Beach and the sea to the south, and Eastfield Meadows past the town. Each is
## reached by a dirt trail from the farm or the town.
##
## What each land holds is data (data/regions.json): where you can walk, its ground colours and
## what grows there. This script draws the ground, the trails, the swamp's pools and mist, the
## sea and the mountains, and scatters the scenery as MultiMeshes under main.nature, one kind
## per land and model (swamp-rock_cluster, mountains-tree_spruce...), so the world editor can
## move them and saves them like the rest. The mountains, the sea and the ground are terrain and
## stay put.
##
## Why it stays fast: the far scenery is culled by distance (visibility ranges) and per 16 m
## cell, the grass blades only grow round the farm and the town, and the big terrain is a few
## plain meshes. Nothing here needs loading as you walk.

const Data = preload("res://scripts/data.gd")
const World = preload("res://scripts/world.gd")
const Nature = preload("res://scripts/nature.gd")

## The whole walkable world: main.gd's walking grid and the camera's reach cover this.
const BOUNDS := Rect2(-96.0, -100.0, 360.0, 162.0) # x -96..264, z -100..62 (east to 144 until 2026-11-26: the dunes and the downs)
const SEA_Y := -0.3
const SAND_FLAT_TO := 55.0 # the beach starts to slope into the sea here (z)
const SAND_SLOPE := 18.0 # ... and is this many metres further out at its lowest
const SAND_DEPTH := 1.8
const GROUND_Y := 0.004 # just over the farm's ground, which lies at -0.01
const TRAIL_Y := 0.012
const GRASS := Color(0.24, 0.38, 0.13) # ground.gdshader's lush grass, that the lands fade into
## How far away each sort of scenery is still drawn (metres from the camera).
const VIEW := {"tree": 150.0, "rock": 110.0, "bush": 90.0, "small": 50.0}

var main: Node
var defs := {} # region id -> its entry in data/regions.json
var trails: Array = [] # Rect2: the dirt trails joining the lands to the farm and the town
var pools: Array = [] # Vector3 (x, z, radius): the swamp's pools
var shore_z := 0.0 # where the sea meets the sand
var grounds := {} # region id -> its ground MeshInstance3D
var sea: MeshInstance3D
var mountains: MeshInstance3D
var swamp_mist: FogVolume
var kinds: Array[String] = [] # the world-editor kinds this made
var blockers: Array = []
var ground_mats: Array[ShaderMaterial] = []
var pool_mats: Array[ShaderMaterial] = []
var sea_mat: ShaderMaterial
## The dunes' and the downs' mounds (data "relief"): [cx, cz, rx, rz, height, cos, sin, dune].
var mounds: Array = []
var mire := {} # the swamp's Deep Mire: centre (Vector2), half (Vector2, the island), moat (metres)
var moat: MeshInstance3D
var _relief_cells: Array = [] # walking-grid cells the mounds block (worked out once)
var _moat_cells: Array = [] # ... and the Deep Mire's moat, open only with waders


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## Builds every land. Returns the rects that block the walking grid (rocks, trunks, pools).
func build(m: Node) -> Array:
	main = m
	name = "Regions"
	var d := Data.load_json("regions")
	for t in d.get("trails", []):
		trails.append(_rect(t))
	defs = d.get("regions", {})
	shore_z = _find_shore()
	for id in defs:
		var dune: bool = defs[id].get("dunes", false) == true
		for md in defs[id].get("relief", []):
			var a := deg_to_rad(float(md[5]))
			mounds.append([float(md[0]), float(md[1]), float(md[2]), float(md[3]), float(md[4]), cos(a), sin(a), dune])
	if defs.has("swamp") and defs["swamp"].has("deep_mire"):
		var dm: Dictionary = defs["swamp"]["deep_mire"]
		mire = {"centre": Vector2(float(dm["centre"][0]), float(dm["centre"][1])),
			"half": Vector2(float(dm["size"][0]), float(dm["size"][1])) * 0.5, "moat": float(dm.get("moat", 4.0))}
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var k := 0
	for id in defs:
		# each land's patch a couple of millimetres over the last, so where they overlap they don't
		# sit flush and flicker (the trails still lie over all of them)
		_ground(id, defs[id], GROUND_Y + (0.002 * mini(k, 3) if k < 4 else 0.001)) # the lands added later lie under the first four where they meet
		k += 1
	for t in trails:
		_trail(t)
	if defs.has("swamp"):
		_swamp_pools(defs["swamp"], rng)
		_swamp_mist(defs["swamp"])
	if defs.has("beach"):
		_sea()
	if defs.has("mountains"):
		_mountains()
	for id in defs:
		_scatter_region(id, defs[id], rng)
	# added later: each kind from its own seed, so the scenery above never moves (2026-11-26)
	for id in defs:
		if defs[id].has("extra"):
			_scatter_region(id, {"walk": defs[id]["walk"], "ground": defs[id]["ground"], "scatter": defs[id]["extra"], "seeded": true}, rng)
	if not mire.is_empty():
		_build_moat()
		var island := Rect2(mire["centre"] - mire["half"], mire["half"] * 2.0)
		var dm: Dictionary = defs["swamp"]["deep_mire"]
		_scatter_region("mire", {"walk": [island.position.x, island.position.y, island.size.x, island.size.y],
			"ground": [island.position.x - 7.0, island.position.y - 7.0, island.size.x + 14.0, island.size.y + 14.0],
			"scatter": dm.get("scatter", []), "seeded": true}, rng)
	return blockers


## Where Nora may walk out here: every land and the trails to them.
func walk_areas() -> Array:
	var out: Array = trails.duplicate()
	for id in defs:
		out.append(_rect(defs[id]["walk"]))
	return out


## The land at a point, or "" (the farm, the town, the woods between).
func region_at(x: float, z: float) -> String:
	for id in defs:
		if _rect(defs[id]["walk"]).has_point(Vector2(x, z)):
			return id
	return ""


func display_name(id: String) -> String:
	return str(defs.get(id, {}).get("name", id.capitalize()))


## The trunks of the woods' trees that stand on a trail (the woods' trees aren't in the walking
## grid otherwise, since nobody walked there before). Read when the grid is built, after the
## world layout has put the trees where Alex wants them.
func trunk_blocks() -> Array:
	var out: Array = []
	for c in main.get_children():
		if not (c is MultiMeshInstance3D and str(c.name).begins_with("Trees_")):
			continue
		var mm := (c as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var o: Vector3 = (c as MultiMeshInstance3D).transform * mm.get_instance_transform(i).origin
			for t in trails:
				if (t as Rect2).grow(0.6).has_point(Vector2(o.x, o.z)):
					out.append(Rect2(o.x - 0.4, o.z - 0.4, 0.8, 0.8))
					break
	return out


## Ground height out here: flat, but the beach runs down into the sea.
func height(_x: float, z: float) -> float:
	if defs.has("beach") and z > SAND_FLAT_TO and _rect(defs["beach"]["ground"]).has_point(Vector2(_x, z)):
		return -SAND_DEPTH * smoothstep(SAND_FLAT_TO, SAND_FLAT_TO + SAND_SLOPE, z)
	return relief(_x, z)


## The dunes and hills (data "relief"): the highest mound over a point, 0 off them. Each is a smooth
## bump, (1 - d²)² of its height, d the distance in its own turned, stretched frame; a dune is
## steeper on its east (lee) side.
func relief(x: float, z: float) -> float:
	var best := 0.0
	for m in mounds:
		var dx := x - float(m[0])
		var dz := z - float(m[1])
		var c: float = m[5]
		var sn: float = m[6]
		var lx := dx * c + dz * sn
		var lz := -dx * sn + dz * c
		if m[7] and lx > 0.0:
			lx *= 1.7
		var d2 := (lx / float(m[2])) * (lx / float(m[2])) + (lz / float(m[3])) * (lz / float(m[3]))
		if d2 < 1.0:
			best = maxf(best, float(m[4]) * (1.0 - d2) * (1.0 - d2))
	return best


## She walks over the hills and dunes now (Alex, 2026-11-27: "I still can't walk freely in the outer
## parts of the map, kept feeling like I was hitting an invisible wall": every mound over 12 cm was
## solid, 38% of the downs and 27% of the dunes). Walkers are lifted to the ground's height
## (SplitHouse.follow() asks `relief`, as do the wild animals, the birds and the horse), and only a
## face too steep to climb still blocks the grid: steeper than RELIEF_STEEP (rise over run; 1.1 is
## about 48 degrees, a dune's slip face), which reads as a wall. RELIEF_BLOCK is the height from
## which the ground counts as a hill at all (walkmap_check.gd, Build & Buy).
const RELIEF_BLOCK := 0.12
const RELIEF_STEEP := 1.1


## How steep the ground is at a point: rise over run, the steepest way.
func slope(x: float, z: float) -> float:
	var e := 0.2
	var gx := (relief(x + e, z) - relief(x - e, z)) / (2.0 * e)
	var gz := (relief(x, z + e) - relief(x, z - e)) / (2.0 * e)
	return sqrt(gx * gx + gz * gz)

func mark_relief() -> void:
	if _relief_cells.is_empty() and not mounds.is_empty():
		var seen := {}
		for m in mounds:
			var r := maxf(float(m[2]), float(m[3]))
			var c0: Vector2i = main._cell(Vector3(float(m[0]) - r, 0, float(m[1]) - r))
			var c1: Vector2i = main._cell(Vector3(float(m[0]) + r, 0, float(m[1]) + r))
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					var id := Vector2i(x, y)
					if seen.has(id) or not main.astar.is_in_boundsv(id):
						continue
					var cc: Vector3 = main._cell_center(id)
					if relief(cc.x, cc.z) > RELIEF_BLOCK and slope(cc.x, cc.z) > RELIEF_STEEP:
						seen[id] = true
		_relief_cells = seen.keys()
	for id in _relief_cells:
		main.astar.set_point_solid(id, true)


# --- the Deep Mire: an island in the swamp behind deep water (waders from Steve, explore.gd) ----

## How far out the moat's edge is at angle `a` (1 = the island's own ellipse), a little wobbly.
static func _wobble(a: float) -> float:
	return 1.0 + 0.07 * sin(a * 3.0 + 0.7) + 0.05 * sin(a * 5.0 + 2.1)


## 0 on the island, 1 out in the moat, 2 beyond it (the rest of the swamp).
func mire_zone(x: float, z: float) -> int:
	if mire.is_empty():
		return 2
	var d: Vector2 = Vector2(x, z) - mire["centre"]
	var h: Vector2 = mire["half"]
	var a := atan2(d.y / h.y, d.x / h.x)
	var w := _wobble(a)
	var e := sqrt((d.x / h.x) * (d.x / h.x) + (d.y / h.y) * (d.y / h.y)) / w
	if e <= 1.0:
		return 0
	var mo: float = mire["moat"]
	var out := sqrt((d.x / (h.x + mo)) * (d.x / (h.x + mo)) + (d.y / (h.y + mo)) * (d.y / (h.y + mo))) / w
	return 1 if out <= 1.0 else 2


## The island's rect, for the habitat and the hut's chest.
func mire_rect() -> Rect2:
	if mire.is_empty():
		return Rect2()
	return Rect2(mire["centre"] - mire["half"], mire["half"] * 2.0)


func mark_moat() -> void:
	if mire.is_empty():
		return
	if _moat_cells.is_empty():
		var h: Vector2 = mire["half"] + Vector2.ONE * (float(mire["moat"]) * 1.2 + 1.0)
		var c0: Vector2i = main._cell(Vector3(mire["centre"].x - h.x, 0, mire["centre"].y - h.y))
		var c1: Vector2i = main._cell(Vector3(mire["centre"].x + h.x, 0, mire["centre"].y + h.y))
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cc: Vector3 = main._cell_center(Vector2i(x, y))
				if mire_zone(cc.x, cc.z) == 1:
					_moat_cells.append(Vector2i(x, y))
	for id in _moat_cells:
		main.astar.set_point_solid(id, true)


## The moat's water: a ring between the island's wobbly edge and the moat's, dark and still.
func _build_moat() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var c: Vector2 = mire["centre"]
	var h: Vector2 = mire["half"]
	var mo: float = mire["moat"]
	var n := 72
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var w := _wobble(a)
		inner.append(Vector3(cos(a) * h.x * w * 0.97, 0.0, sin(a) * h.y * w * 0.97))
		outer.append(Vector3(cos(a) * (h.x + mo) * w * 1.02, 0.0, sin(a) * (h.y + mo) * w * 1.02))
	for i in n:
		st.add_vertex(inner[i])
		st.add_vertex(outer[i + 1])
		st.add_vertex(outer[i])
		st.add_vertex(inner[i])
		st.add_vertex(inner[i + 1])
		st.add_vertex(outer[i + 1])
	moat = MeshInstance3D.new()
	moat.name = "DeepMireMoat"
	moat.mesh = st.commit()
	moat.position = Vector3(c.x, 0.035, c.y)
	moat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://shaders/water.gdshader")
	wm.set_shader_parameter("centre", Vector3(c.x, 0, c.y))
	wm.set_shader_parameter("radius", maxf(h.x, h.y) + mo)
	wm.set_shader_parameter("shallow", Color(0.09, 0.11, 0.07))
	wm.set_shader_parameter("deep", Color(0.03, 0.045, 0.03))
	moat.material_override = wm
	pool_mats.append(wm)
	add_child(moat)


func _find_shore() -> float:
	var z := SAND_FLAT_TO
	while z < SAND_FLAT_TO + SAND_SLOPE and -SAND_DEPTH * smoothstep(SAND_FLAT_TO, SAND_FLAT_TO + SAND_SLOPE, z) > SEA_Y:
		z += 0.1
	return z


func _set_rain(rain: float) -> void:
	for gm in ground_mats:
		gm.set_shader_parameter("wet", rain)
	for pm in pool_mats:
		pm.set_shader_parameter("rain", rain)
	if sea_mat:
		sea_mat.set_shader_parameter("rain", rain)


func _process(_delta: float) -> void:
	_set_rain(main.rain)
	# the swamp's mist is volumetric fog: keep that switched on while the camera is near it
	if swamp_mist and main.lighting:
		var c: Vector3 = main.cam_target
		var near := _rect(defs["swamp"]["walk"]).grow(30.0).has_point(Vector2(c.x, c.z))
		main.lighting.local_fog = near
		swamp_mist.visible = near


# --- terrain -------------------------------------------------------------------------------

func _ground_material(cols: Array, rect: Rect2, fade: float, wet_below: float) -> ShaderMaterial:
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://shaders/region_ground.gdshader")
	gm.set_shader_parameter("col_a", Color(str(cols[0])))
	gm.set_shader_parameter("col_b", Color(str(cols[1])))
	gm.set_shader_parameter("col_c", Color(str(cols[2])))
	gm.set_shader_parameter("edge_col", GRASS)
	gm.set_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	gm.set_shader_parameter("fade", fade)
	gm.set_shader_parameter("wet_below", wet_below)
	ground_mats.append(gm)
	return gm


## A grid of 2 m squares over the land's ground rect, following height().
func _ground(id: String, r: Dictionary, lift: float) -> void:
	var rect := _rect(r["ground"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.5 if r.has("relief") else 2.0
	var nx := ceili(rect.size.x / step)
	var nz := ceili(rect.size.y / step)
	for j in nz + 1:
		for i in nx + 1:
			var x := rect.position.x + minf(i * step, rect.size.x)
			var z := rect.position.y + minf(j * step, rect.size.y)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, height(x, z) + lift, z))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + 1)
			st.add_index(a + nx + 2)
			st.add_index(a + nx + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Ground_" + id
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _ground_material(r["colours"], rect, 9.0, SEA_Y if id == "beach" else -100.0)
	add_child(mi)
	grounds[id] = mi


## A worn dirt trail: the same ground shader in earth colours, with a soft ragged edge. It's drawn
## only up to where a land's own ground begins (its edge blends into grass, not into sand).
func _trail(t: Rect2) -> void:
	var g := t.grow(0.5)
	for id in defs:
		var land := _rect(defs[id]["ground"]).grow(-4.0)
		if not land.intersects(g):
			continue
		if g.size.y > g.size.x: # runs north-south
			if land.get_center().y > g.get_center().y:
				g.size.y = land.position.y - g.position.y
			else:
				g.size.y = g.end.y - land.end.y
				g.position.y = land.end.y
		else:
			if land.get_center().x > g.get_center().x:
				g.size.x = land.position.x - g.position.x
			else:
				g.size.x = g.end.x - land.end.x
				g.position.x = land.end.x
	var mi := MeshInstance3D.new()
	mi.name = "Trail"
	var pm := PlaneMesh.new()
	pm.size = g.size
	mi.mesh = pm
	mi.position = Vector3(g.get_center().x, TRAIL_Y, g.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _ground_material(["#6b5236", "#5c4630", "#7a6044"], g, 1.0, -100.0)
	add_child(mi)


func _swamp_pools(r: Dictionary, rng: RandomNumberGenerator) -> void:
	var area := _rect(r["walk"]).grow(-5.0)
	var tries := 0
	while pools.size() < int(r.get("pools", 8)) and tries < 400:
		tries += 1
		var rad := rng.randf_range(2.2, 5.5)
		var x := rng.randf_range(area.position.x + rad, area.end.x - rad)
		var z := rng.randf_range(area.position.y + rad, area.end.y - rad)
		var ok := true
		for p in pools:
			if Vector2(p.x, p.y).distance_to(Vector2(x, z)) < p.z + rad + 3.0:
				ok = false
				break
		for t in trails:
			if (t as Rect2).grow(rad + 2.0).has_point(Vector2(x, z)):
				ok = false
		if not ok:
			continue
		pools.append(Vector3(x, z, rad))
		var mi := MeshInstance3D.new()
		mi.name = "SwampPool"
		mi.mesh = _blob(rad, rng)
		mi.position = Vector3(x, 0.03, z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wm := ShaderMaterial.new()
		wm.shader = preload("res://shaders/water.gdshader")
		wm.set_shader_parameter("centre", Vector3(x, 0, z))
		wm.set_shader_parameter("radius", rad)
		wm.set_shader_parameter("shallow", Color(0.27, 0.32, 0.18))
		wm.set_shader_parameter("deep", Color(0.07, 0.1, 0.06))
		mi.material_override = wm
		pool_mats.append(wm)
		add_child(mi)
		# five strips that follow the water's round edge (one square stood its corners out on dry
		# ground, an invisible wall beside the pool)
		var pr := rad * 0.82
		for k in 5:
			var zc := (-0.8 + 0.4 * k) * pr
			var hw := sqrt(maxf(0.0, pr * pr - zc * zc))
			blockers.append(Rect2(x - hw, z + zc - 0.2 * pr, hw * 2.0, 0.4 * pr))


## A flat, lumpy disc of radius about r (a pool's water).
static func _blob(r: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var k := [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)]
	var rim: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var rr := r * (0.85 + 0.12 * sin(a * 2.0 + k[0]) + 0.08 * sin(a * 3.0 + k[1]))
		rim.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
	st.set_normal(Vector3.UP)
	for i in n:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(rim[(i + 1) % n])
		st.add_vertex(rim[i])
	return st.commit()


func _swamp_mist(r: Dictionary) -> void:
	var walk := _rect(r["walk"])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/mist.gdshader")
	mat.set_shader_parameter("density", 0.045)
	mat.set_shader_parameter("falloff", 0.9)
	mat.set_shader_parameter("albedo", Color(0.78, 0.82, 0.7))
	var tex := NoiseTexture3D.new()
	tex.width = 48
	tex.height = 24
	tex.depth = 48
	tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.07
	tex.noise = fn
	mat.set_shader_parameter("noise", tex)
	swamp_mist = FogVolume.new()
	swamp_mist.name = "SwampMist"
	swamp_mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	swamp_mist.size = Vector3(walk.size.x + 12.0, 6.0, walk.size.y + 12.0)
	swamp_mist.position = Vector3(walk.get_center().x, 2.0, walk.get_center().y)
	swamp_mist.material = mat
	swamp_mist.visible = false
	add_child(swamp_mist)


func _sea() -> void:
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(900.0, 420.0)
	sea.mesh = pm
	sea.position = Vector3(30.0, SEA_Y, shore_z - 4.0 + 210.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = preload("res://shaders/sea.gdshader")
	sea_mat.set_shader_parameter("shore_z", shore_z)
	sea.material_override = sea_mat
	add_child(sea)


## The Greyspine range: a ridge of peaks along the north edge, rising from the foothills,
## grass at their feet, grey rock above, snow on the tops. Too steep to walk.
func _mountains() -> void:
	var foot := _rect(defs["mountains"]["walk"]).position.y - 4.0 # z where the slopes begin
	var x0 := -240.0
	var x1 := 300.0
	var z1 := foot - 150.0
	var step := 4.0
	var nx := int((x1 - x0) / step)
	var nz := int((foot - z1) / step)
	var ridge := FastNoiseLite.new()
	ridge.seed = 41
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.frequency = 0.012
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	var bumps := FastNoiseLite.new()
	bumps.seed = 7
	bumps.frequency = 0.05
	var hgt := PackedFloat32Array()
	hgt.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := x0 + i * step
			var z := foot - j * step
			var t := clampf((foot - z) / 55.0, 0.0, 1.0)
			var rise := t * t * (3.0 - 2.0 * t)
			var r := ridge.get_noise_2d(x, z) * 0.5 + 0.5
			var h := rise * (14.0 + 62.0 * r * r + 6.0 * bumps.get_noise_2d(x, z))
			if j == 0:
				h = -0.2 # tucked just under the foothills' ground
			hgt[j * (nx + 1) + i] = h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz + 1:
		for i in nx + 1:
			var h: float = hgt[j * (nx + 1) + i]
			var hl: float = hgt[j * (nx + 1) + maxi(i - 1, 0)]
			var hr: float = hgt[j * (nx + 1) + mini(i + 1, nx)]
			var hd: float = hgt[maxi(j - 1, 0) * (nx + 1) + i]
			var hu: float = hgt[mini(j + 1, nz) * (nx + 1) + i]
			var nrm := Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			var up := nrm.y # 1 = flat
			var n: float = bumps.get_noise_2d(i * 7.0, j * 7.0)
			var col := Color(0.33, 0.43, 0.22).lerp(Color(0.28, 0.36, 0.2), n * 0.5 + 0.5)
			var rock := Color(0.47, 0.44, 0.41).lerp(Color(0.38, 0.36, 0.35), n * 0.5 + 0.5)
			col = col.lerp(rock, clampf((h - 6.0 - 6.0 * n) / 10.0, 0.0, 1.0) * 0.6 + (1.0 - smoothstep(0.55, 0.8, up)) * 0.4)
			var snow := clampf((h - 40.0 - 8.0 * n) / 6.0, 0.0, 1.0) * smoothstep(0.45, 0.7, up)
			col = col.lerp(Color(0.93, 0.95, 0.98), snow)
			st.set_color(col)
			st.set_normal(nrm) # from the slope itself (generate_normals took the winding as facing down: flat, unlit hills)
			st.add_vertex(Vector3(x0 + i * step, h, foot - j * step))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			st.add_index(a)
			st.add_index(a + nx + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx + 2)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # (seen from the foothills and from above in the editor)
	mountains = MeshInstance3D.new()
	mountains.name = "Mountains"
	mountains.mesh = st.commit()
	mountains.material_override = mat
	add_child(mountains)


# --- scenery -------------------------------------------------------------------------------

func _view_for(model: String) -> float:
	if model.begins_with("tree"):
		return VIEW["tree"]
	if model.begins_with("rock"):
		return VIEW["rock"]
	if model.begins_with("bush"):
		return VIEW["bush"]
	return VIEW["small"]


func _scatter_region(id: String, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var walk := _rect(r["walk"])
	var area := _rect(r["ground"]).grow(-7.0)
	if id == "beach":
		area.size.y = minf(area.size.y, SAND_FLAT_TO - 1.5 - area.position.y) # dry sand only
	var taken: Array[Vector3] = [] # x, z, radius
	for entry in r.get("scatter", []):
		var model := str(entry[0])
		var count := int(entry[1])
		var smin := float(entry[2])
		var smax := float(entry[3])
		var gap := float(entry[4])
		var block := float(entry[5])
		var tint := Color(str(entry[6])) if entry.size() > 6 else Color.WHITE
		if r.get("seeded", false) == true: # its own random numbers: nothing else moves when it changes
			rng = RandomNumberGenerator.new()
			rng.seed = hash(id + "/" + model)
		var mesh: Mesh = null
		var kind := id + "-" + model
		if model.begins_with("tree:"):
			mesh = World._tree_mesh(model.substr(5))
			kind = id + "-tree_" + model.substr(5)
			if mesh and r.has("tree_tint"):
				mesh = _tinted(mesh as ArrayMesh, Color(str(r["tree_tint"])))
		else:
			mesh = main.nature._mesh(model)
		if mesh == null:
			if not r.get("seeded", false): # a seeded land's models may still be on their way
				push_warning("regions: no model for %s" % model)
			continue
		if tint != Color.WHITE:
			mesh = _tint_all(mesh as ArrayMesh, tint)
		var items: Array = []
		var tries := 0
		while items.size() < count and tries < count * 30:
			tries += 1
			var x := rng.randf_range(area.position.x, area.end.x)
			var z := rng.randf_range(area.position.y, area.end.y)
			if model == "lily_pads": # out on the pools' water
				if pools.is_empty():
					break
				var lp: Vector3 = pools[rng.randi() % pools.size()]
				var la := rng.randf() * TAU
				var ld := lp.z * sqrt(rng.randf()) * 0.7
				x = lp.x + cos(la) * ld
				z = lp.y + sin(la) * ld
			# reeds crowd round the swamp's pools
			if id == "swamp" and model == "tuft_tall" and not pools.is_empty() and rng.randf() < 0.65:
				var p: Vector3 = pools[rng.randi() % pools.size()]
				var a := rng.randf() * TAU
				var d := p.z * rng.randf_range(0.85, 1.25)
				x = p.x + cos(a) * d
				z = p.y + sin(a) * d
			if model != "lily_pads" and not _clear_at(x, z, gap, taken):
				continue
			var s := rng.randf_range(smin, smax)
			var y := 0.04 if model == "lily_pads" else height(x, z)
			if id != "mire" and model != "lily_pads" and mire_zone(x, z) == 1: # nothing grows in the Deep Mire's moat
				continue
			items.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y, z)))
			if gap > 0.0:
				taken.append(Vector3(x, z, gap * 0.5))
			if block > 0.0 and walk.grow(1.0).has_point(Vector2(x, z)):
				var b := Rect2(x - block * s, z - block * s, block * s * 2.0, block * s * 2.0)
				blockers.append(b)
				main.nature.block_at[Vector2i(roundi(x * 100.0), roundi(z * 100.0))] = b
		_add_kind(kind, mesh, items, gap > 0.0, _view_for(model))


## A copy of a model with every surface's colour multiplied by `tint` (the dunes' bleached rocks).
static func _tint_all(mesh: ArrayMesh, tint: Color) -> ArrayMesh:
	var m := mesh.duplicate() as ArrayMesh
	for i in m.get_surface_count():
		var sm := m.surface_get_material(i)
		if sm is StandardMaterial3D:
			var own := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
			own.albedo_color = own.albedo_color * tint
			m.surface_set_material(i, own)
		elif sm is ShaderMaterial and (sm as ShaderMaterial).shader != null:
			var own2 := (sm as ShaderMaterial).duplicate() as ShaderMaterial
			for u in (own2.shader as Shader).get_shader_uniform_list():
				if str(u["name"]) in ["tint", "albedo", "albedo_color", "colour", "color"] and int(u["type"]) == TYPE_COLOR:
					var c0: Variant = own2.get_shader_parameter(u["name"])
					own2.set_shader_parameter(u["name"], (c0 as Color) * tint if c0 is Color else tint)
			m.surface_set_material(i, own2)
	return m


## A copy of a tree with its leaves tinted (they still sway and wet in the rain with the rest).
static func _tinted(mesh: ArrayMesh, tint: Color) -> ArrayMesh:
	var m := mesh.duplicate() as ArrayMesh
	for i in m.get_surface_count():
		var sm := m.surface_get_material(i)
		if sm is ShaderMaterial and World.leaf_mats.has(sm):
			var own := (sm as ShaderMaterial).duplicate() as ShaderMaterial
			own.set_shader_parameter("tint", tint)
			World.leaf_mats.append(own)
			m.surface_set_material(i, own)
	return m


func _clear_at(x: float, z: float, gap: float, taken: Array[Vector3]) -> bool:
	for p in pools:
		if Vector2(p.x, p.y).distance_to(Vector2(x, z)) < p.z * 0.8:
			return false
	for t in trails:
		if (t as Rect2).grow(1.2).has_point(Vector2(x, z)):
			return false
	if gap <= 0.0:
		return true
	for q in taken:
		if Vector2(q.x, q.y).distance_to(Vector2(x, z)) < q.z + gap * 0.5:
			return false
	return true


## One kind's MultiMeshes, a 16 m cell each (the world editor's grouping), under main.nature.
func _add_kind(kind: String, mesh: Mesh, items: Array, shadows: bool, view: float) -> void:
	if items.is_empty():
		return
	kinds.append(kind)
	var cells := {}
	for t in items:
		var tf: Transform3D = t
		var key := Vector2i(floori(tf.origin.x / Nature.CELL), floori(tf.origin.z / Nature.CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(tf)
	for key in cells:
		var list: Array = cells[key]
		var centre := Vector3((key.x + 0.5) * Nature.CELL, 0.0, (key.y + 0.5) * Nature.CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var tf: Transform3D = list[i]
			tf.origin -= centre
			mm.set_instance_transform(i, tf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [kind, key.x, key.y]
		mmi.multimesh = mm
		mmi.position = centre
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = view
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		main.nature.add_child(mmi)
