extends Node3D
## Bretton Oaks (Alex, 2026-11-17): a suburb of six brick ranch houses round a cul-de-sac south-east
## of Maple Grove, where the town's people go home to sleep. One house model
## (art/world_assets/suburb_house, from Alex's photo) set round the turning circle with mild changes:
## every other one mirrored, its own brick, siding, trim and door colours, its own front garden.
## The road runs in from the end of the meadow trail; the town's sign stands at its mouth, its board
## reading "Bretton Oaks". All of it is data (data/suburb.json); every name is a draft.
##
## main.gd builds it after the town (build()), and the world editor picks up each house (garden
## included) and the sign through Town.built, and the street lamps as decor. What used to grow on
## the plot (trees, rocks, bushes) is cut while the suburb stands (clears(), asked by forage.apply()).
##
## At night: update() (from main._update_rounds(), so never in the autotest's still town) walks each
## resident home to their door at night_from, hides them inside, and at night_to lets them out again
## and walks them back to where they were. The API for anyone else's people (generic townsfolk):
##   houses()            [{"i", "door", "inside", "yaw", "node"}]: door is where to stand to go in
##   home_for(id) -> int the house a person sleeps in (data's residents, or a hash of the id)
##   door_for(id)        that house's door
##   go_home(v) / wake(v), asleep(id), bedtime(), add_sleeper(v)
## Each house's windows light up from dusk until lights (data), each a little later than the last.

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")
const BuildingSkin = preload("res://scripts/building_skin.gd")
const Town = preload("res://scripts/town.gd")
const SplitHouse = preload("res://scripts/split_house.gd")
const PAVING := preload("res://shaders/paving.gdshader")
const MODEL := "res://assets/props/building_suburb_house.glb"
const SIGN_MODEL := "res://assets/props/welcome_sign.glb"
const SIGN_FACE := "res://assets/textures/signs/bretton_oaks_face.png"
const SIGN_FACE_N := "res://assets/textures/signs/bretton_oaks_face_n.png"
const KIND := "suburb_house" # its Town.built kind (not building_*: those are the town's shops and their post round)
const SIGN_KIND := "bretton_oaks_sign"
const VINYL_BASE := Color("#d8ccac") # the siding's colour in its own texture (build.py VINYL)
## The house in its own space (x right, its front toward +z): the entry wing, the right wing, the
## porch post (art/world_assets/suburb_house/build.py, L and R, Blender y turned to Godot z).
const FOOTPRINT := [Rect2(-6.6, -4.2, 5.16, 7.2), Rect2(-1.44, -6.2, 7.98, 10.6), Rect2(-6.6, 3.85, 0.25, 0.25)]
const GARAGE := Rect2(-1.44, 4.4, 7.98, 5.6) # the right wing run out to the street as a garage (Alex, 2026-11-17), in front of Marcus's walk-in footprint
const DOOR_AT := Vector3(-2.5, 0, 4.6) # where to stand to go in: in front of the stoop
const INSIDE_AT := Vector3(-2.5, 0, 1.5) # where a sleeper is put, out of sight
const PORCH_LIGHT := Vector3(-2.5, 2.2, 3.7)
const DRIVE_X := Vector2(-6.4, -3.2) # the driveway, in front of the porch; the garage's door opens onto it from the side
const DRIVE_Z := 4.6 # ... from the porch's front
const PLANT_BLOCK := {"arborvitae": 0.45, "red_shrub": 0.8, "hydrangea": 0.6, "rose_bush": 0.6}
const Y_LAWN := 0.0112
const Y_ROAD := 0.015
const Y_DRIVE := 0.017
const LIGHTS_ON := 19.5 # windows light at dusk
const LATE := 1.5 # hours after night_to: a sleeper still indoors comes out straight to their spot
const WALK_LIMIT := 300.0 # seconds: a walker who hasn't reached the door by then is put to bed

var main: Node
var cfg := {}
var centre := Vector3.ZERO
var road_dir := Vector2.ZERO
var drive_angles: Array = [] # where each driveway meets the circle (radians round the centre), for the kerb's gaps
## The paving as shapes, for the world editor's road map (Alex, 2026-11-17: "can't delete original
## cul-de-sac pavement"): {"kind": "pavement"|"sidewalk", "circle": [Vector2, r]} or {"kind", "quad": [a, b, w]}.
## god_mode.gd paints them into its map once and hides the meshes (group "suburb_paving").
var paving: Array = []
var house_list: Array = [] # {"i", "node", "model", "door", "inside", "yaw", "mirror", "panes", "light"}
var sign_node: Node3D
var lamps: Array = [] # the street lamps (main.decor)
var sleepers := {} # id -> {"v", "state": walking|asleep|returning, "house", "home", "roam", "route", "route_i", "rest", "t"}
var extra := {} # id -> Villager: townsfolk who sleep here too (add_sleeper)
var lit := {} # house index -> its windows lit
var walk_in: Node3D = null # split_house.gd: the one house you can go into (Marcus's)
var on := true # bedtimes at all: main.gd turns it off in the autotest (its town keeps still) but for the suburb check
var _pane_night: StandardMaterial3D
var _mats := {}
var _lights_t := 0.0


## Builds the suburb. Returns its obstacles for the walking grid.
func build(m: Node) -> Array:
	main = m
	name = "Suburb"
	cfg = Data.load_json("suburb")
	var c: Array = cfg.get("centre", [99.0, 8.0])
	centre = Vector3(float(c[0]), 0, float(c[1]))
	var rt: Array = cfg.get("road_to", [86.5, 0.7])
	road_dir = (Vector2(float(rt[0]), float(rt[1])) - Vector2(centre.x, centre.z)).normalized()
	var blockers: Array = []
	_lawn()
	var defs: Array = cfg.get("houses", [])
	for i in defs.size():
		blockers.append_array(_house(i, defs[i]))
	_roads()
	blockers.append_array(_sign())
	_street_lamps()
	update_lights(true)
	return blockers


func _angle(i: int) -> float:
	var a0 := atan2(road_dir.y, road_dir.x)
	return a0 + deg_to_rad(float(cfg.get("start_deg", 45.0)) + float(cfg.get("step_deg", 54.0)) * i)


## A point in a house's own space, in the world.
static func _to_world(node: Node3D, p: Vector3) -> Vector3:
	return node.global_transform * p


## Turns a rect in a house's own space into world rects for the walking grid: cut into squares no
## bigger than 1.5 m first, so a house turned at 45 degrees doesn't block a box twice its size.
static func _blocks(r: Rect2, pos: Vector3, yaw: float) -> Array:
	var out: Array = []
	var nx := maxi(1, ceili(r.size.x / 1.5))
	var nz := maxi(1, ceili(r.size.y / 1.5))
	var s := r.size / Vector2(nx, nz)
	var c := cos(yaw)
	var sn := sin(yaw)
	for i in nx:
		for j in nz:
			var q := Rect2(r.position + s * Vector2(i, j), s)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in [q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)]:
				var w := Vector2(p.x * c + p.y * sn, -p.x * sn + p.y * c)
				lo = lo.min(w)
				hi = hi.max(w)
			out.append(Rect2(Vector2(pos.x, pos.z) + lo, hi - lo))
	return out


func _paving(col: Color, joint := 0.0) -> ShaderMaterial:
	var key := "%s/%s" % [col.to_html(false), joint]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = PAVING
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("joint", joint)
	_mats[key] = m
	return m


func _flat(mesh: Mesh, mat: Material, y: float, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## The mown lawns: a patch of the lands' ground shader in lawn greens, fading into the meadow.
func _lawn() -> void:
	var half := float(cfg.get("ring", 21.0)) + 6.0
	var rect := Rect2(centre.x - half, centre.z - half, half * 2.0, half * 2.0)
	var pm := PlaneMesh.new()
	pm.size = rect.size
	var mat: Material
	if main.regions != null:
		mat = main.regions._ground_material(cfg.get("lawn", ["#56802e", "#4c7629", "#5f8a33"]), rect, 6.0, -100.0)
	else:
		mat = _paving(Color("#56802e"))
	var mi := _flat(pm, mat, Y_LAWN, "Lawn")
	mi.position.x = centre.x
	mi.position.z = centre.z


## The turning circle, the road in and its curbs.
func _roads() -> void:
	var r := float(cfg.get("bulb", 8.5))
	var w := float(cfg.get("road_width", 6.0))
	var asphalt := _paving(Color(0.25, 0.25, 0.25))
	var concrete := _paving(Color(0.68, 0.66, 0.62), 1.6)
	# the circle
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * r, 0, sin(a0) * r)) # clockwise from above: Godot's front face
		st.add_vertex(Vector3(cos(a1) * r, 0, sin(a1) * r))
	var bulb := _flat(st.commit(), asphalt, Y_ROAD, "TurningCircle")
	bulb.position = Vector3(centre.x, Y_ROAD, centre.z)
	bulb.add_to_group("suburb_paving")
	paving.append({"kind": "pavement", "circle": [Vector2(centre.x, centre.z), r]})
	# the road in, from inside the circle to the trail
	var rt: Array = cfg.get("road_to", [86.5, 0.7])
	var a := Vector2(centre.x, centre.z) + road_dir * (r - 1.0)
	var b := Vector2(float(rt[0]), float(rt[1]))
	var road := _quad(a, b, w, asphalt, Y_ROAD, "RoadIn")
	road.name = "RoadIn"
	road.add_to_group("suburb_paving")
	paving.append({"kind": "pavement", "quad": [a, b, w]})
	# curbs: a low concrete kerb round the circle, open where the road comes in, and along the road
	var open := asin(clampf(w * 0.5 / r, 0.0, 1.0)) + 0.04
	var a_road := atan2(road_dir.y, road_dir.x)
	var segs := 40
	for i in segs:
		var t0 := a_road + open + (TAU - 2.0 * open) * i / segs
		var t1 := a_road + open + (TAU - 2.0 * open) * (i + 1) / segs
		var cut := false
		for da in drive_angles:
			cut = cut or absf(wrapf((t0 + t1) * 0.5 - float(da[0]), -PI, PI)) < float(da[1])
		if cut:
			continue # a dropped kerb where a driveway comes in
		var p0 := Vector2(centre.x, centre.z) + Vector2(cos(t0), sin(t0)) * (r + 0.12)
		var p1 := Vector2(centre.x, centre.z) + Vector2(cos(t1), sin(t1)) * (r + 0.12)
		_kerb(p0, p1, concrete)
	var side := Vector2(-road_dir.y, road_dir.x)
	for s in [-1.0, 1.0]:
		var off: Vector2 = side * s * (w * 0.5 + 0.12)
		var from := Vector2(centre.x, centre.z) + road_dir * sqrt(maxf(r * r - w * w * 0.25, 0.0)) + off
		_kerb(from, b + off - road_dir * 0.5, concrete)


func _quad(a: Vector2, b: Vector2, w: float, mat: Material, y: float, nm: String) -> MeshInstance3D:
	var d := (b - a).normalized()
	var s := Vector2(-d.y, d.x) * w * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := [a - s, a + s, b + s, b - s]
	var v: Array[Vector3] = []
	for q in p:
		v.append(Vector3(q.x, 0, q.y))
	for k in [[0, 1, 2], [0, 2, 3]]:
		var e1: Vector3 = v[k[1]] - v[k[0]]
		var e2: Vector3 = v[k[2]] - v[k[0]]
		var order: Array = k if e1.cross(e2).y < 0.0 else [k[0], k[2], k[1]] # clockwise from above
		for idx in order:
			st.set_normal(Vector3.UP)
			st.add_vertex(v[idx])
	return _flat(st.commit(), mat, y, nm)


func _kerb(a: Vector2, b: Vector2, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(a.distance_to(b) + 0.02, 0.1, 0.22)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, 0.05, mid.y)
	mi.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	mi.name = "Kerb"
	mi.add_to_group("suburb_paving")
	add_child(mi)
	paving.append({"kind": "sidewalk", "quad": [a, b, 0.3]}) # on the map the kerb is a strip of concrete


## One house round the circle: the model in its colours, its garden, its driveway, its porch light.
func _house(i: int, d: Dictionary) -> Array:
	var ring := float(cfg.get("ring", 21.0))
	var a := _angle(i)
	var out := Vector2(cos(a), sin(a))
	var node := Node3D.new()
	node.name = "BrettonOaksHouse%d" % i
	node.position = centre + Vector3(out.x, 0, out.y) * ring
	node.rotation.y = atan2(-out.x, -out.y) # its front toward the circle
	add_child(node)
	var mirror := bool(d.get("mirror", false))
	var holder := Node3D.new()
	holder.name = "Model"
	holder.scale.x = -1.0 if mirror else 1.0
	node.add_child(holder)
	var model := Catalog.model(MODEL, holder)
	var panes: Array = []
	if model:
		for n in model.find_children("*_low", "", true, false):
			(n as Node3D).visible = false # seen from outside it's the full walls (interiors.gd's rule)
		panes = _dress(model, d)
		_no_bake(model)
	var mx := -1.0 if mirror else 1.0
	# the garden: the photo's arborvitae and the red-leaf shrub, or some of the catalogue's flowers
	var local_blocks: Array = []
	var walks_in := i == int(Data.load_json("split_house").get("house", -1))
	for r in FOOTPRINT:
		if walks_in and (r as Rect2).size.x > 1.0:
			continue # its walls block the grid instead (split_house.gd mark_grid())
		local_blocks.append(_mirrored(r, mirror))
	local_blocks.append(_mirrored(GARAGE, mirror))
	for p in d.get("plants", []):
		var id := str(p[0])
		var g := Node3D.new()
		g.name = "Plant_" + id
		g.position = Vector3(float(p[1]) * mx, 0, float(p[2]))
		var sc := float(p[3]) if p.size() > 3 else 1.0
		g.scale = Vector3.ONE * sc
		g.rotation.y = float(i * 37 + int(p[1] * 10.0)) * 0.1
		node.add_child(g)
		Catalog.model("res://assets/props/%s.glb" % id, g)
		var hb := float(PLANT_BLOCK.get(id, 0.5)) * sc
		local_blocks.append(Rect2(g.position.x - hb, g.position.z - hb, hb * 2.0, hb * 2.0))
	# the driveway, from the porch to the circle
	var bulb := float(cfg.get("bulb", 8.5))
	var dx := DRIVE_X * mx
	var x0 := minf(dx.x, dx.y)
	var x1 := maxf(dx.x, dx.y)
	var xc := (x0 + x1) * 0.5
	var p0 := _to_world(node, Vector3(xc, 0, DRIVE_Z))
	var p1 := centre + (p0 - centre).normalized() * (bulb - 0.5) # straight at the circle, so neighbours' don't cross
	_quad(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), x1 - x0, _paving(Color(0.7, 0.68, 0.64), 2.4), Y_DRIVE, "Driveway%d" % i).add_to_group("suburb_paving")
	paving.append({"kind": "sidewalk", "quad": [Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), x1 - x0]})
	drive_angles.append([atan2(p1.z - centre.z, p1.x - centre.x), (x1 - x0) * 0.5 / bulb + 0.06])
	# the porch light, on while the windows are lit
	var light := OmniLight3D.new()
	light.name = "PorchLight"
	light.position = Vector3(PORCH_LIGHT.x * mx, PORCH_LIGHT.y, PORCH_LIGHT.z)
	light.light_color = Color(1.0, 0.8, 0.55)
	light.omni_range = 5.0
	light.light_energy = 0.9
	light.shadow_enabled = false
	light.set_meta("no_shadow", true)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 10.0
	light.visible = false
	node.add_child(light)
	var blocks: Array = []
	for r in local_blocks:
		blocks.append_array(_blocks(r, node.position, node.rotation.y))
	var h := {"i": i, "node": node, "model": model, "mirror": mirror, "panes": panes, "light": light, "yaw": node.rotation.y, "at": node.position, # where the code put it, before the world layout
		"door": _to_world(node, Vector3(DOOR_AT.x * mx, 0, DOOR_AT.z)), "inside": _to_world(node, Vector3(INSIDE_AT.x * mx, 0, INSIDE_AT.z))}
	house_list.append(h)
	if walks_in and not mirror:
		walk_in = SplitHouse.new()
		walk_in.name = "WalkIn"
		add_child(walk_in)
		walk_in.build(main, node)
		# you look out of its windows from inside: real glass, day and night (the room's own lights
		# show through after dark), never the other houses' cream panes or their lit night ones
		h["glass"] = true
		for p in panes:
			(p[0] as MeshInstance3D).set_surface_override_material(int(p[1]), Catalog.window_glass())
		# and its sheer curtains down: drawn across every window, they made the panes read as cream
		# boards from inside (Alex, 2026-11-17)
		var gone := StandardMaterial3D.new()
		gone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gone.albedo_color = Color(0, 0, 0, 0)
		gone.cull_mode = BaseMaterial3D.CULL_DISABLED
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var cm := mi as MeshInstance3D
			for si in cm.mesh.get_surface_count():
				var sm := cm.mesh.surface_get_material(si)
				if sm != null and sm.resource_name == "suburb_curtain_sheer":
					cm.set_surface_override_material(si, gone)
	Town.built.append([node, KIND, "House, %s" % str(cfg.get("name", "Bretton Oaks")), blocks])
	return blocks


static func _mirrored(r: Rect2, mirror: bool) -> Rect2:
	return Rect2(-r.end.x, r.position.y, r.size.x, r.size.y) if mirror else r


## The house's colours (data's brick, vinyl, trim and door) on its own surfaces, after BuildingSkin
## has dressed it. Returns its window panes [MeshInstance3D, surface] for the night lights.
func _dress(model: Node3D, d: Dictionary) -> Array:
	var panes: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(s) as BaseMaterial3D
			if sm == null:
				continue
			match sm.resource_name:
				"suburb_brick":
					m.set_surface_override_material(s, BuildingSkin.material("brick", Color(str(d.get("brick", "#8a4a36"))), sm))
				"suburb_trim":
					m.set_surface_override_material(s, BuildingSkin.material("paintwood", Color(str(d.get("trim", "#f1efe8"))), sm))
				"suburb_vinyl":
					var col := Color(str(d.get("vinyl", "#d8ccac")))
					m.set_surface_override_material(s, _tinted(sm, Color(col.r / VINYL_BASE.r, col.g / VINYL_BASE.g, col.b / VINYL_BASE.b)))
				"suburb_door":
					m.set_surface_override_material(s, _tinted(sm, Color(str(d.get("door", "#f4f2ec")))))
				"suburb_pane":
					panes.append([m, s])
	return panes


## Every surface without the model's light bake (Alex, 2026-11-17: dark blocky squares over the brick
## and siding, inside and out). The house's bake atlas came out nearly all black (its islands are
## brick-sized and mostly shut in by the shell), and on UV2 it printed those squares on every wall.
## Until it's baked again properly, the house is lit by the scene alone.
var _unbaked := {}
func _no_bake(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat == null:
				continue
			var k := mat.get_instance_id()
			if not _unbaked.has(k):
				var out: Material = mat
				if mat is BaseMaterial3D and (mat as BaseMaterial3D).ao_enabled:
					out = mat.duplicate()
					(out as BaseMaterial3D).ao_enabled = false
				elif mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("ao_tex") != null:
					out = mat.duplicate()
					(out as ShaderMaterial).set_shader_parameter("ao_amount", 0.0)
				_unbaked[k] = out
			if _unbaked[k] != mat:
				m.set_surface_override_material(s, _unbaked[k])


func _tinted(sm: BaseMaterial3D, c: Color) -> Material:
	var key := "%s/%s" % [sm.resource_name, c.to_html(false)]
	if not _mats.has(key):
		var m := sm.duplicate() as BaseMaterial3D
		m.albedo_color = c
		_mats[key] = m
	return _mats[key]


## The town's welcome sign at the road's mouth, its board reading "Bretton Oaks", facing the trail.
func _sign() -> Array:
	var rt: Array = cfg.get("road_to", [86.5, 0.7])
	var w := float(cfg.get("road_width", 6.0))
	var side := Vector2(-road_dir.y, road_dir.x)
	if side.x > 0.0:
		side = -side # on the town's side of the road
	var at := Vector2(float(rt[0]), float(rt[1])) - road_dir * 0.5 + side * (w * 0.5 + 1.4) # at the trail's end, clear of the driveways
	sign_node = Node3D.new()
	sign_node.name = "BrettonOaksSign"
	sign_node.position = Vector3(at.x, 0, at.y)
	var face := Vector2(-1.0, -0.15).normalized() # toward the town, west along the trail
	sign_node.rotation.y = atan2(face.x, face.y)
	add_child(sign_node)
	var inst := Catalog.model(SIGN_MODEL, sign_node)
	if inst and ResourceLoader.exists(SIGN_FACE):
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(s) as BaseMaterial3D
				if sm and sm.resource_name == "sign_face":
					var f := sm.duplicate() as BaseMaterial3D
					f.albedo_texture = load(SIGN_FACE)
					if ResourceLoader.exists(SIGN_FACE_N):
						f.normal_texture = load(SIGN_FACE_N)
					f.resource_name = "sign_face_bretton_oaks"
					m.set_surface_override_material(s, f)
	var blocks := _blocks(Rect2(-1.3, -0.3, 2.6, 0.6), sign_node.position, sign_node.rotation.y)
	Town.built.append([sign_node, SIGN_KIND, "Sign: %s" % str(cfg.get("name", "Bretton Oaks")), blocks])
	return blocks


## Three of the town's street lamps round the circle, between the houses, as decor the editor moves.
func _street_lamps() -> void:
	if main.decor_root == null:
		return
	var r := float(cfg.get("bulb", 8.5)) + 0.9
	for k in [0, 2, 4]:
		var a := (_angle(k) + _angle(k + 1)) * 0.5
		for _try in 4:
			var clash := false
			for da in drive_angles:
				clash = clash or absf(wrapf(a - float(da[0]), -PI, PI)) < float(da[1]) + 0.12
			if not clash:
				break
			a += 0.2 # off the driveway, onto the grass beside it
		var p := centre + Vector3(cos(a), 0, sin(a)) * r
		var n0: int = main.decor.size()
		main._decor("lantern", p, 0)
		if main.decor.size() > n0:
			lamps.append(main.decor[-1])


## Whether something at `at` stands on the suburb's ground (forage.apply() cuts the scenery there).
func clears(at: Vector3) -> bool:
	var reach := float(cfg.get("ring", 21.0)) + 6.0
	var p := Vector2(at.x, at.z)
	var c := Vector2(centre.x, centre.z)
	if p.distance_to(c) < reach:
		return true
	var rt: Array = cfg.get("road_to", [86.5, 0.7])
	var b := Vector2(float(rt[0]), float(rt[1]))
	var t := clampf((p - c).dot(road_dir) / maxf(c.distance_to(b), 0.01), 0.0, 1.0)
	var on_road := c + road_dir * c.distance_to(b) * t
	if p.distance_to(on_road) < float(cfg.get("road_width", 6.0)) * 0.5 + 3.5:
		return true
	return sign_node != null and p.distance_to(Vector2(sign_node.global_position.x, sign_node.global_position.z)) < 2.5


# --- the night ---------------------------------------------------------------------------------------

func houses() -> Array:
	var out: Array = []
	for h in house_list:
		var n := h["node"] as Node3D
		var mx := -1.0 if bool(h["mirror"]) else 1.0
		# from the node, so a house moved in the world editor gives its new door
		out.append({"i": h["i"], "node": n, "yaw": n.global_rotation.y,
			"door": n.global_transform * Vector3(DOOR_AT.x * mx, 0, DOOR_AT.z),
			"inside": n.global_transform * Vector3(INSIDE_AT.x * mx, 0, INSIDE_AT.z)})
	return out


## The house `id` sleeps in: a named villager's from the data, anyone else's from their id.
func home_for(id: String) -> int:
	var n := house_list.size()
	if n == 0:
		return -1
	var res: Dictionary = cfg.get("residents", {})
	var i := clampi(int(res[id]), 0, n - 1) if res.has(id) else absi(hash(id)) % n
	# once she's bought Marcus's house (house_sale.gd) nobody else sleeps there
	if n > 1 and Game.flag("marcus_house_owned") == true and i == int(Data.load_json("split_house").get("house", -1)):
		i = (i + 1) % n
	return i


func door_for(id: String) -> Vector3:
	var i := home_for(id)
	return houses()[i]["door"] if i >= 0 else Vector3.ZERO


func bedtime(h: float = -1.0) -> bool:
	var hr := Game.hour if h < 0.0 else h
	return hr >= float(cfg.get("night_from", 21.0)) or hr < float(cfg.get("night_to", 6.0))


func asleep(id: String) -> bool:
	return sleepers.has(id) and str(sleepers[id]["state"]) == "asleep"


## Someone else's people (townsfolk) who sleep here too: update() takes them home with the rest.
func add_sleeper(v: Node3D) -> void:
	extra[str(v.get("vid"))] = v


func _residents() -> Dictionary:
	var out := {}
	for id in cfg.get("residents", {}):
		var v = main._villager(str(id))
		if v != null:
			out[str(id)] = v
	for id in extra:
		if is_instance_valid(extra[id]):
			out[id] = extra[id]
	return out


## Twice a second from main._update_rounds(): to bed at night_from, out again at night_to.
func update() -> void:
	if not on:
		return
	var night := bedtime()
	var res := _residents()
	for id in res:
		var v = res[id]
		var st: Dictionary = sleepers.get(id, {})
		if night:
			if st.is_empty():
				if _free_to_go(id, v):
					go_home(v)
			elif str(st["state"]) != "asleep" and v.home.distance_to(st["target"]) > 0.05:
				sleepers.erase(id) # another routine (a story, the post round) has sent them elsewhere: theirs now
			elif str(st["state"]) == "walking":
				st["t"] = float(st["t"]) + 0.5
				if Vector2(v.position.x - st["door"].x, v.position.z - st["door"].z).length() < 0.6 or float(st["t"]) > WALK_LIMIT:
					_hide(v, st)
			elif str(st["state"]) == "returning":
				go_home(v) # turned round on the way back out
		elif not st.is_empty():
			match str(st["state"]):
				"walking", "asleep":
					wake(v)
				"returning":
					if v.home.distance_to(st["target"]) > 0.05:
						sleepers.erase(id) # taken over on the way back (Rosa's stall morning, the post): theirs now
					elif Vector2(v.position.x - st["home"].x, v.position.z - st["home"].z).length() < 0.4:
						_restore(v, st)
						sleepers.erase(id)


func _free_to_go(id: String, v) -> bool:
	if not v.visible or v.anim_override != "" or main.story.is_playing():
		return false
	if Game.flag("home_" + id, null) != null or main.visitors.has(id):
		return false
	if main.cafe_visits and main.cafe_visits.visits.has(id):
		return false
	if main.barista and main.barista.active:
		return false
	return true


## Walks `v` to their door; update() puts them inside when they get there.
func go_home(v) -> void:
	var id := str(v.vid)
	var st: Dictionary = sleepers.get(id, {})
	if st.is_empty():
		st = {"v": v, "home": v.home, "roam": v.roam, "route": v.route.duplicate(), "route_i": v._route_i, "rest": v.rest_yaw}
		sleepers[id] = st
	var i := home_for(id)
	var hs := houses()
	if i < 0:
		return
	st["house"] = i
	st["door"] = hs[i]["door"]
	st["inside"] = hs[i]["inside"]
	st["state"] = "walking"
	st["t"] = 0.0
	st["target"] = st["door"]
	v.rest_yaw = null
	var path: Array = main._find_path(v.position, st["door"])
	if path.is_empty() and v.position.distance_to(st["door"]) > 1.0:
		_hide(v, st) # no way there on the grid (a terrace inside a blocker): in bed without the walk
		return
	v.walk_to(st["door"], path)


func _hide(v, st: Dictionary) -> void:
	v.position = st["inside"]
	v.visible = false
	v.process_mode = Node.PROCESS_MODE_DISABLED # its click box goes with it
	st["state"] = "asleep"


## Out of the door and back to where they were (straight there if it's well past morning, or `now`).
func wake(v, now := false) -> void:
	var id := str(v.vid)
	var st: Dictionary = sleepers.get(id, {})
	if st.is_empty():
		return
	v.visible = true
	v.process_mode = Node.PROCESS_MODE_INHERIT
	var late := Game.hour >= float(cfg.get("night_to", 6.0)) + LATE and Game.hour < float(cfg.get("night_from", 21.0))
	var path: Array = [] if (now or late) else main._find_path(st["door"] if str(st["state"]) == "asleep" else v.position, st["home"])
	if now or late or path.is_empty():
		v.settle_at(st["home"]) # there at once, its walk target and path with it
		_restore(v, st)
		sleepers.erase(id)
		return
	if str(st["state"]) == "asleep":
		v.position = st["door"]
	st["state"] = "returning"
	st["target"] = st["home"]
	v.walk_to(st["home"], path)


func _restore(v, st: Dictionary) -> void:
	v.home = st["home"]
	v.roam = st["roam"]
	v.route = st["route"]
	v._route_i = int(st["route_i"])
	v.rest_yaw = st["rest"]


## Everyone up and back at their spot at once: a story scene is starting, or the game is loading.
func wake_all() -> void:
	for id in sleepers.keys():
		var v = sleepers[id]["v"]
		if is_instance_valid(v):
			wake(v, true)
	sleepers.clear()


# --- the lights ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_lights_t -= delta
	if _lights_t <= 0.0:
		_lights_t = 1.0
		update_lights()


## Windows lit from dusk until a little after `lights` (each house a quarter hour later than the
## last), and again before dawn; the porch light with them.
func lights_on(i: int, h: float = -1.0) -> bool:
	var hr := Game.hour if h < 0.0 else h
	var off := float(cfg.get("lights", 23.0)) + 0.25 * i
	var morning := float(cfg.get("lights_morning", 5.5))
	return (hr >= LIGHTS_ON and hr < off) or (hr >= morning and hr < 6.5)


func update_lights(force := false) -> void:
	if _pane_night == null:
		_pane_night = StandardMaterial3D.new()
		_pane_night.resource_name = "suburb_pane_lit"
		_pane_night.albedo_color = Color(1.0, 0.82, 0.55)
		_pane_night.emission_enabled = true
		_pane_night.emission = Color(1.0, 0.72, 0.42)
		_pane_night.emission_energy_multiplier = 1.8
		_pane_night.roughness = 0.4
	for h in house_list:
		var i := int(h["i"])
		var on := lights_on(i)
		if not force and bool(lit.get(i, false)) == on:
			continue
		lit[i] = on
		if not bool(h.get("glass", false)):
			for p in h["panes"]:
				(p[0] as MeshInstance3D).set_surface_override_material(int(p[1]), _pane_night if on else null)
		(h["light"] as OmniLight3D).visible = on
