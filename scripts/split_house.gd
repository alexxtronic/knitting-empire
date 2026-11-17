extends Node3D
## Marcus's house: the one house round the Bretton Oaks cul-de-sac you can walk into (Alex,
## 2026-11-17). Outside it is the same brick ranch as its neighbours (art/world_assets/suburb_house,
## never changed for this). Inside it is a back-split, as Alex remembers living in it: the main floor
## (kitchen, dining, living room) is the left half at ground level; a half flight up from the living
## room is the bedroom floor over the right half; a long flight down is the basement under the whole
## house (a rec room in black tile, a den in green shag, a bathroom and the garage). The layout is
## data/split_house.json, in the house's own space, so the world editor can move or turn the house
## and everything goes with it.
##
## How three floors fit a game that walks on one flat grid (main.gd's AStarGrid2D):
## - The main floor and the bedroom floor don't overlap: they share the grid, and y_at() gives the
##   floor's height under anyone (player.gd, dog.gd, villager.gd lift themselves to it). The stairs
##   are ramps: the height climbs along them.
## - The basement does overlap: while she is down there (`level` BASEMENT, chosen by how far down the
##   basement stairs she is) the house's cells on the grid are its walls and furniture instead
##   (mark_grid()), only it is shown, and the ground over the house isn't drawn
##   (shaders/ground_hole.gdshaderinc) so the camera looks down into it.
## While she is inside, the roof lifts and the walls toward the camera drop to stubs, as in the
## walk-in shops (interiors.gd); in first person the roof is off and each floor has its own ceiling.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")

const UPPER := 0 # she is on the main floor or the bedroom floor (or outside)
const BASEMENT := 1 # she is in the basement
const WALL_T := 0.16 # a partition's thickness
const LOW := 0.5 # a cut-down partition's height above its floor
const GROW := 0.1 # how far walls and furniture block the walking grid past their faces
const SIDES := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}

static var current: Node3D = null # the house, for y_at()

var main: Node
var house: Node3D # the suburb house's node: the world editor moves this
var cfg: Dictionary = {}
var level := UPPER
var inside := false
var parts := {} # the shell's parts by name (base, roof, door, wall_front, wall_front_low ...)
var roots := {} # "main", "upper", "basement", "all" -> Node3D
var walls: Array = [] # {"full", "low", "level", "c" (Vector2, local x / z)}
var ceilings: Array = [] # MeshInstance3D, shown only in first person
var lights: Array = [] # OmniLight3D: the rooms' ceiling lights
var footprint: Array = [] # Rect2s in the house's space
var hole: Array = [] # the same, for the ground's hole
var open := 0.0 # the front door: 0 shut .. 1 swung in
var split_x := 0.5
var upper_y := 0.85
var basement_y := -2.4
var _floor_surfaces: Array = [] # [MeshInstance3D, surface index, its material]: the shell's plank floor
var _hidden: Array = [] # villagers hidden while she's in the basement (they're upstairs)
var _inv := Transform3D.IDENTITY # the house's world -> local, kept each frame
var _mats := {}


## Furnishes house `node` (a suburb house, its model loaded under its "Model" holder) for main `m`.
func build(m: Node, node: Node3D) -> void:
	main = m
	house = node
	cfg = Data.load_json("split_house")
	split_x = float(cfg.get("split_x", 0.5))
	upper_y = float(cfg.get("upper_y", 0.85))
	basement_y = float(cfg.get("basement_y", -2.4))
	for r in cfg.get("footprint", []):
		footprint.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	hole = footprint
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.name)] = mi
	if parts.has("base"):
		var b: MeshInstance3D = parts["base"]
		for i in b.mesh.get_surface_count():
			var mat: Material = b.get_active_material(i)
			if mat != null and "floor" in str(mat.resource_name).to_lower():
				_floor_surfaces.append([b, i, b.get_surface_override_material(i)])
	var interior := Node3D.new()
	interior.name = "Interior"
	house.add_child(interior)
	for k in ["main", "upper", "basement", "all"]:
		var r := Node3D.new()
		r.name = (k as String).capitalize()
		interior.add_child(r)
		roots[k] = r
	_floors()
	_walls()
	_stairs()
	_lights()
	_furniture()
	current = self
	house.set_meta("walk_in", "split_house")
	_inv = house.global_transform.affine_inverse()
	_show()


# --- building ---------------------------------------------------------------------------------

func _level_y(lv: String) -> float:
	return upper_y if lv == "upper" else (basement_y if lv == "basement" else 0.0)


func _ceiling_y(lv: String) -> float:
	match lv:
		"upper":
			return float(cfg.get("upper_ceiling", 3.25))
		"basement":
			return float(cfg.get("basement_ceiling", -0.12))
	return float(cfg.get("main_ceiling", 2.42))


func _floors() -> void:
	for room in cfg.get("rooms", []):
		var lv := str(room["level"])
		var y := _level_y(lv)
		var mat := _floor_mat(str(room.get("floor", "carpet_grey")))
		var cm := _flat_mat(Color(str(room.get("wall", "#e4ddd0"))).lightened(0.15))
		for r in room["rects"]:
			var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			# a slab: the main floor sits on the shell's planks; the upper floor and the basement
			# floor are thick enough to show an edge at the stairs
			var thick := 0.03 if lv == "main" else 0.2
			_slab(roots[lv], rect, y + 0.045 - thick, y + 0.045, mat, "Floor_%s" % room["id"])
			var c := _slab(roots[lv], rect, _ceiling_y(lv), _ceiling_y(lv) + 0.04, cm, "Ceiling_%s" % room["id"])
			c.visible = false
			ceilings.append(c)


func _walls() -> void:
	for w in cfg.get("walls", []):
		var lv := str(w["level"])
		var seg: Array = w["wall"]
		var a := Vector2(float(seg[0]), float(seg[1]))
		var b := Vector2(float(seg[2]), float(seg[3]))
		var base_y := _level_y(lv) if lv != "all" else basement_y
		var y0 := float(w.get("from", base_y))
		var y1 := float(w.get("to", _ceiling_y(lv) if lv != "all" else upper_y))
		var col := _wall_colour(a.lerp(b, 0.5), lv)
		for piece in _pieces(a, b, w.get("doors", [])):
			var p0: Vector2 = piece[0]
			var p1: Vector2 = piece[1]
			var full := _wall_box(roots[lv], p0, p1, y0, y1, col)
			var low := _wall_box(roots[lv], p0, p1, y0, maxf(y0 + 0.05, _level_y(lv) + LOW), col.darkened(0.08))
			low.visible = false
			walls.append({"full": full, "low": low, "level": lv, "c": p0.lerp(p1, 0.5), "a": p0, "b": p1})


## A wall's centre line cut at its doors: [[from, to], ...].
func _pieces(a: Vector2, b: Vector2, doors: Array) -> Array:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var cuts := []
	for d in doors:
		cuts.append([float(d[0]) - float(d[1]) * 0.5, float(d[0]) + float(d[1]) * 0.5])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var out := []
	var t := lo
	for c in cuts:
		if c[0] > t:
			out.append([t, c[0]])
		t = maxf(t, c[1])
	if hi > t:
		out.append([t, hi])
	var res := []
	for s in out:
		if along_x:
			res.append([Vector2(s[0], a.y), Vector2(s[1], a.y)])
		else:
			res.append([Vector2(a.x, s[0]), Vector2(a.x, s[1])])
	return res


func _wall_box(parent: Node3D, a: Vector2, b: Vector2, y0: float, y1: float, col: Color) -> MeshInstance3D:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var length := (absf(b.x - a.x) if along_x else absf(b.y - a.y)) + WALL_T
	var size := Vector3(length, y1 - y0, WALL_T) if along_x else Vector3(WALL_T, y1 - y0, length)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _flat_mat(col)
	var c := a.lerp(b, 0.5)
	mi.position = Vector3(c.x, (y0 + y1) * 0.5, c.y)
	parent.add_child(mi)
	return mi


## A wall's paint: the colour of the room beside it on that floor (the first one it touches).
func _wall_colour(at: Vector2, lv: String) -> Color:
	for room in cfg.get("rooms", []):
		if lv != "all" and str(room["level"]) != lv:
			continue
		for r in room["rects"]:
			if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).grow(0.3).has_point(at):
				return Color(str(room.get("wall", "#e4ddd0")))
	return Color("#e4ddd0")


func _slab(parent: Node3D, r: Rect2, y0: float, y1: float, mat: Material, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, y1 - y0, r.size.y)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(r.get_center().x, (y0 + y1) * 0.5, r.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if y1 - y0 < 0.05 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## The two flights: treads of oak carpeted grey. The half flight up is the main floor's; the long
## flight down belongs to both (you look down it from the living room).
func _stairs() -> void:
	var tread := _floor_mat("carpet_grey")
	var riser := _flat_mat(Color("#d9cfc0"))
	for k in ["up", "down"]:
		var rp: Dictionary = cfg.get("ramps", {}).get(k, {})
		if rp.is_empty():
			continue
		var r: Array = rp["rect"]
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		var y_from := float(rp["from"])
		var y_to := float(rp["to"])
		var n := int(rp.get("steps", 6))
		var parent: Node3D = roots["main"] if k == "up" else roots["all"]
		var run := rect.size.x / n
		for i in n:
			# step i's top: the height a little past its front edge
			var top := y_from + (y_to - y_from) * float(i + 1) / float(n)
			var x0 := rect.position.x + run * i
			var bottom := minf(y_to, y_from) - 0.05
			var st := Rect2(x0, rect.position.y, run, rect.size.y)
			_slab(parent, st, bottom, top + 0.045, tread, "Step_%s_%d" % [k, i])
		if k == "down":
			# the stairwell's front side below the ground, so you can't see out under the house
			_wall_box(parent, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), y_to, 0.0, riser.albedo_color)


func _lights() -> void:
	for l in cfg.get("lights", []):
		var lv := str(l["level"])
		var at: Array = l["at"]
		var o := Catalog.omni(roots[lv], Vector3(float(at[0]), float(at[1]), float(at[2])), Color(1.0, 0.86, 0.66), 5.5, 0.5, 1.1)
		o.shadow_enabled = false
		o.set_meta("no_shadow", true)
		o.remove_from_group("lamp_shadow")
		lights.append(o)


func _furniture() -> void:
	for f in cfg.get("furniture", []):
		var lv := str(f["level"])
		var at: Vector2 = Data.vec2(f["at"])
		var n := Node3D.new()
		n.name = str(f["id"])
		n.set_meta("item_id", str(f["id"]))
		n.set_meta("furnishing", true) # the world editor moves each piece on its own (god_mode.gd)
		n.position = Vector3(at.x, _level_y(lv) + 0.045 + float(f.get("y", 0.0)), at.y)
		n.rotation.y = deg_to_rad(float(f.get("turn", 0.0)))
		roots[lv].add_child(n)
		Catalog.build(str(f["id"]), n)


# --- materials -------------------------------------------------------------------------------

func _flat_mat(c: Color) -> StandardMaterial3D:
	var key := "flat_" + c.to_html(false)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


## The floors, drawn here: tiles with grout, carpet and shag from noise, plain cement.
func _floor_mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	var img: Image
	match kind:
		"tile_beige":
			img = _tiles(Color("#d8c7a4"), Color("#b9a988"), 4)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 1.2
			m.roughness = 0.45
		"tile_black":
			img = _tiles(Color("#1d1d20"), Color("#47474a"), 4)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 1.2
			m.roughness = 0.3
		"tile_white":
			img = _tiles(Color("#eceae4"), Color("#c3c0b8"), 8)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 1.2
			m.roughness = 0.35
		"shag_green":
			img = _noise(Color("#4f6b2a"), 0.28, 9)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.8
		"carpet_blue":
			img = _noise(Color("#5d7fa8"), 0.12, 3)
		"carpet_cream":
			img = _noise(Color("#e3d8c0"), 0.08, 3)
		"cement":
			img = _noise(Color("#8f8b84"), 0.1, 17)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 2.0
			m.roughness = 0.8
		_: # carpet_grey
			img = _noise(Color("#8b8b88"), 0.1, 5)
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	if m.roughness == 1.0:
		m.roughness = 0.95
	_mats[kind] = m
	return m


static func _tiles(face: Color, grout: Color, n: int) -> Image:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cell := s / n
	var shade := []
	for i in n * n:
		shade.append(rng.randf_range(-0.05, 0.05))
	for y in s:
		for x in s:
			var gx := x % cell
			var gy := y % cell
			if gx < 2 or gy < 2:
				img.set_pixel(x, y, grout)
			else:
				var k: float = shade[(y / cell) * n + x / cell] + rng.randf_range(-0.015, 0.015)
				img.set_pixel(x, y, Color(face.r + k, face.g + k, face.b + k))
	return img


static func _noise(c: Color, amount: float, seed: int) -> Image:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for y in s:
		for x in s:
			var k := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(c.r * (1.0 + k), c.g * (1.0 + k), c.b * (1.0 + k)))
	return img


# --- where things are -----------------------------------------------------------------------

func local(p: Vector3) -> Vector3:
	return _inv * p


func in_footprint(q: Vector3) -> bool:
	for r in footprint:
		if (r as Rect2).has_point(Vector2(q.x, q.z)):
			return true
	return false


func _ramp(k: String) -> Dictionary:
	return cfg.get("ramps", {}).get(k, {})


func _ramp_y(k: String, q: Vector3) -> Variant:
	var rp := _ramp(k)
	if rp.is_empty():
		return null
	var r: Array = rp["rect"]
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	if not rect.has_point(Vector2(q.x, q.z)):
		return null
	var t := clampf((q.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	return lerpf(float(rp["from"]), float(rp["to"]), t)


## The floor's height under a point in the house's space, on the floors shown now.
func floor_local(q: Vector3, lv: int) -> float:
	if not in_footprint(q):
		return 0.0
	var d: Variant = _ramp_y("down", q)
	if d != null:
		return d
	if lv == BASEMENT:
		return basement_y
	var u: Variant = _ramp_y("up", q)
	if u != null:
		return u
	return upper_y if q.x > split_x else 0.0


## The floor's height under `p` (world), for whoever stands there: 0 anywhere outside the house.
static func y_at(p: Vector3) -> float:
	if current == null or not is_instance_valid(current):
		return 0.0
	var h: Node3D = current
	return h.floor_local(h.local(p), h.level)


## Where a click lands: the ray from the camera meets the floor she can see under it.
func pick(from: Vector3, dir: Vector3) -> Variant:
	var h := (main.player as Node3D).position.y
	var hit: Variant = null
	for _i in 4:
		hit = Plane(Vector3.UP, h).intersects_ray(from, dir)
		if hit == null:
			return null
		var h2 := floor_local(local(hit), level)
		if absf(h2 - h) < 0.02:
			break
		h = h2
	return hit


# --- the walking grid ------------------------------------------------------------------------

## The house's cells on main.gd's grid: open under the footprint, then its walls and furniture on
## the floors she can reach now. Called at the end of main._rebuild_grid() and when she goes up or
## down the basement stairs.
func mark_grid() -> void:
	if house == null or not is_instance_valid(house) or not house.visible:
		return
	var xf := house.global_transform
	_inv = xf.affine_inverse()
	for c in _cells(footprint, 0.0):
		main.astar.set_point_solid(c, false)
	# the shell's walls: always
	for w in cfg.get("shell", []):
		var seg: Array = w["wall"] if w is Dictionary else w
		var doors: Array = w.get("doors", []) if w is Dictionary else []
		for piece in _pieces(Vector2(float(seg[0]), float(seg[1])), Vector2(float(seg[2]), float(seg[3])), doors):
			_block(_seg_rect(piece[0], piece[1], 0.22))
	for w in walls:
		if _reachable(str(w["level"])):
			_block(_seg_rect(w["a"], w["b"], WALL_T))
	for n in _furniture_nodes():
		if not n.visible: # deleted in the world editor
			continue
		var item: Dictionary = Catalog.ITEMS.get(str(n.get_meta("item_id", "")), {})
		if item.is_empty() or bool(item.get("flat", false)):
			continue
		var fs: Vector2 = Data.vec2(item.get("size", [1.0, 1.0]))
		if absi(int(roundf(rad_to_deg(n.rotation.y) / 90.0))) % 2 == 1:
			fs = Vector2(fs.y, fs.x)
		_block(Rect2(Vector2(n.position.x, n.position.z) - fs * 0.5, fs))


## Where a catalogue piece set down at `p` (world) in the world editor goes: [the level's node, the
## floor's height in the world], or [] if `p` isn't inside the house. The basement while she's down
## there, else the bedroom floor over the right half and the main floor over the left.
func root_at(p: Vector3) -> Array:
	if house == null or not is_instance_valid(house):
		return []
	var q := local(p)
	if not in_footprint(q):
		return []
	var lv := "basement" if inside and level == BASEMENT else ("upper" if q.x > split_x else "main")
	return [roots[lv], house.global_position.y + _level_y(lv) + 0.045]


func _reachable(lv: String) -> bool:
	if lv == "all":
		return true
	return lv == "basement" if level == BASEMENT else lv != "basement"


func _furniture_nodes() -> Array:
	var out := []
	for k in roots:
		if _reachable(k):
			for n in (roots[k] as Node3D).get_children():
				if n is Node3D and n.has_meta("item_id"):
					out.append(n)
	return out


func _seg_rect(a: Vector2, b: Vector2, t: float) -> Rect2:
	var lo := a.min(b) - Vector2(t, t) * 0.5
	var hi := a.max(b) + Vector2(t, t) * 0.5
	return Rect2(lo, hi - lo)


## Grid cells whose centres fall inside any of `rects` (house space), grown by `grow`.
func _cells(rects: Array, grow: float) -> Array:
	var xf := house.global_transform
	var out := []
	for r0 in rects:
		var r := (r0 as Rect2).grow(grow)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var w: Vector3 = xf * Vector3(p.x, 0, p.y)
			lo = lo.min(Vector2(w.x, w.z))
			hi = hi.max(Vector2(w.x, w.z))
		var c0: Vector2i = main._cell(Vector3(lo.x, 0, lo.y))
		var c1: Vector2i = main._cell(Vector3(hi.x, 0, hi.y))
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var id := Vector2i(x, y)
				if not main.astar.is_in_boundsv(id):
					continue
				var q: Vector3 = _inv * (main._cell_center(id) as Vector3)
				if r.has_point(Vector2(q.x, q.z)):
					out.append(id)
	return out


func _block(r: Rect2) -> void:
	for c in _cells([r], GROW):
		main.astar.set_point_solid(c, true)


# --- every frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if house == null or not is_instance_valid(house) or main == null or main.player == null:
		return
	_inv = house.global_transform.affine_inverse()
	var q := local((main.player as Node3D).position)
	var was_inside := inside
	inside = house.visible and in_footprint(q)
	# up or down the basement stairs: halfway down, the basement takes over
	var want := level
	var d: Variant = _ramp_y("down", q)
	if d != null:
		want = BASEMENT if float(d) < float(cfg.get("switch_y", -1.2)) else UPPER
	elif not inside:
		want = UPPER
	if want != level:
		level = want
		mark_grid()
	# the front door swings in for anyone at it
	var door: Vector2 = Data.vec2(cfg.get("door", [-2.5, 2.9]))
	var at_door := false
	var movers: Array = [(main.player as Node3D).position]
	for v in main.villagers:
		movers.append((v as Node3D).position)
	for m in movers:
		var mq: Vector3 = _inv * (m as Vector3)
		if absf(mq.x - door.x) < 1.0 and absf(mq.z - door.y) < 1.6:
			at_door = true
	open = move_toward(open, 1.0 if (inside or at_door) else 0.0, delta * 2.5)
	if parts.has("door"):
		(parts["door"] as Node3D).rotation.y = deg_to_rad(100.0) * smoothstep(0.0, 1.0, open)
	_show()
	if inside != was_inside and not inside:
		_restore_hidden()


## What's shown: the floors she can see, the roof and the walls toward the camera, the ground's hole.
func _show() -> void:
	if main == null or main.player == null or not is_instance_valid(house):
		return
	var fp: bool = main.fps != null and main.fps.active
	if main.god != null and main.god.active:
		# the world editor: the roof off and the floors she's on shown, so every room can be furnished
		(roots["main"] as Node3D).visible = level == UPPER
		(roots["upper"] as Node3D).visible = level == UPPER
		(roots["basement"] as Node3D).visible = inside and level == BASEMENT
		(roots["all"] as Node3D).visible = true
		for c in ceilings:
			(c as Node3D).visible = false
		if parts.has("roof"):
			(parts["roof"] as Node3D).visible = false
		return
	var near := inside or (main.player as Node3D).position.distance_to(house.global_position) < 24.0
	(roots["main"] as Node3D).visible = near and level == UPPER
	(roots["upper"] as Node3D).visible = inside and level == UPPER
	(roots["basement"] as Node3D).visible = inside and level == BASEMENT
	(roots["all"] as Node3D).visible = near
	for c in ceilings:
		(c as Node3D).visible = inside and fp
	if parts.has("roof"):
		(parts["roof"] as Node3D).visible = not inside
	for fs in _floor_surfaces:
		(fs[0] as MeshInstance3D).set_surface_override_material(fs[1], _invisible() if level == BASEMENT and inside else fs[2])
	# the walls toward the camera, the shell's and the house's own, drop to stubs while she's in
	var cut_on: bool = inside and not fp and not main.walls_up
	var cdir := Vector3(sin(main.cam_yaw), 0, cos(main.cam_yaw))
	for side in SIDES:
		if not parts.has("wall_" + side) or not parts.has("wall_%s_low" % side):
			continue
		var n: Vector3 = (house.global_transform.basis * (SIDES[side] as Vector3)).normalized()
		# in the basement all four are stubs: the walls above ground would throw the sun's shadow
		# down into it, and from up here they'd hide it
		var cut: bool = cut_on and (n.dot(cdir) > 0.25 or level == BASEMENT)
		(parts["wall_" + side] as Node3D).visible = not cut
		(parts["wall_%s_low" % side] as Node3D).visible = cut
	var her := local((main.player as Node3D).position)
	var cl: Vector3 = _inv.basis * cdir
	for w in walls:
		var c: Vector2 = w["c"]
		var cut: bool = cut_on and Vector2(c.x - her.x, c.y - her.z).dot(Vector2(cl.x, cl.z)) > 0.6
		(w["full"] as Node3D).visible = not cut
		(w["low"] as Node3D).visible = cut
	var night := clampf(1.0 - Game.daylight(), 0.0, 1.0)
	for l in lights:
		(l as OmniLight3D).light_energy = 0.55 + 0.75 * night
	_ground_hole(inside and level == BASEMENT)
	_hide_upstairs(inside and level == BASEMENT)


func _invisible() -> Material:
	if not _mats.has("invisible"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0, 0, 0, 0)
		_mats["invisible"] = m
	return _mats["invisible"]


var _hole_on := false

func _ground_hole(on: bool) -> void:
	if on == _hole_on and not on:
		return
	_hole_on = on
	var a := Vector4(0, 0, 1, 0)
	var b := Vector4.ZERO
	var c := Vector4.ZERO
	if on:
		var xf := house.global_transform
		var yaw := xf.basis.get_euler().y
		a = Vector4(xf.origin.x, xf.origin.z, cos(yaw), sin(yaw))
		var r0: Rect2 = hole[0]
		b = Vector4(r0.position.x, r0.position.y, r0.end.x, r0.end.y)
		if hole.size() > 1:
			var r1: Rect2 = hole[1]
			c = Vector4(r1.position.x, r1.position.y, r1.end.x, r1.end.y)
	RenderingServer.global_shader_parameter_set("ground_hole_a", a)
	RenderingServer.global_shader_parameter_set("ground_hole_b", b)
	RenderingServer.global_shader_parameter_set("ground_hole_c", c)


## Villagers standing on the floors above are hidden while she's in the basement (they'd hang in
## the air over it), and come back when she's up again.
func _hide_upstairs(on: bool) -> void:
	if not on:
		_restore_hidden()
		return
	for v in main.villagers:
		var vn := v as Node3D
		if vn.visible and in_footprint(local(vn.position)) and not _hidden.has(vn):
			vn.visible = false
			_hidden.append(vn)


func _restore_hidden() -> void:
	for vn in _hidden:
		if is_instance_valid(vn):
			(vn as Node3D).visible = true
	_hidden.clear()
