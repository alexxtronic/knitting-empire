extends Node3D
## Marcus's house: the one house round the Bretton Oaks cul-de-sac you can walk into (Alex,
## 2026-11-17). Outside it is the same brick ranch as its neighbours (art/world_assets/suburb_house,
## never changed for this). Inside it is a back-split, as Alex remembers living in it: the main floor
## (kitchen, dining, living room) is the left half at ground level; a half flight up from the living
## room is the bedroom floor over the right half; beside it a flight down is the basement under the
## bedroom half (`bfoot`: a den in green shag at the foot of the stairs, a rec room in black tile the
## same size behind it, and a bathroom), as in Alex's plans. The layout is
## data/split_house.json, in the house's own space, so the world editor can move or turn the house
## and everything goes with it.
##
## How three floors fit a game that walks on one flat grid (main.gd's AStarGrid2D):
## - The main floor and the bedroom floor don't overlap: they share the grid, and y_at() gives the
##   floor's height under anyone (player.gd, dog.gd, villager.gd lift themselves to it). The stairs
##   are ramps: the height climbs along them.
## - The basement does overlap: while she is down there (`level` BASEMENT, chosen by how far down the
##   basement stairs she is) the house's cells on the grid are its walls and furniture instead, and
##   the cells outside its footprint are solid (mark_grid()), only it is shown, and the ground over the house isn't drawn
##   (shaders/ground_hole.gdshaderinc) so the camera looks down into it.
## While she is inside, the roof lifts and the walls toward the camera drop to stubs, as in the
## walk-in shops (interiors.gd); in first person the roof is off and each floor has its own ceiling.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const FurnitureScript = preload("res://scripts/furniture.gd")

const UPPER := 0 # she is on the main floor or the bedroom floor (or outside)
const BASEMENT := 1 # she is in the basement
const WALL_T := 0.16 # a partition's thickness
const LOW := 0.5 # a cut-down partition's height above its floor
const BLOCK_T := 0.6 # how wide a partition blocks the walking grid: more than a 0.5 m cell turned 9 degrees
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
var hole: Array = [] # the basement's, for the ground's hole
var bfoot: Array = [] # the basement's footprint (Rect2s): "basement_footprint", else the whole house's
var open := 0.0 # the front door: 0 shut .. 1 swung in
var split_x := 0.5
var upper_y := 0.85
var basement_y := -2.4
var _floor_surfaces: Array = [] # [MeshInstance3D, surface index, its material]: the shell's plank floor
var _hidden: Array = [] # villagers hidden while she's in the basement (they're upstairs)
var _inv := Transform3D.IDENTITY # the house's world -> local, kept each frame
var _mats := {}
var _built: Array = [] # the walls, openings, floors and ceilings: rebuild() makes them again from cfg
var doors: Array = [] # the doors and sliding doors in the walls' openings: {"node", "part", "kind", "c", "lv", "rot0", "x0", "open"}
var selected_wall := -1 # the world editor's house tools: the wall picked (an index into cfg "walls"), drawn gold

const DOOR_GLB := "res://assets/props/door_interior.glb"
const SLIDE_GLB := "res://assets/props/sliding_door.glb"
const DOOR_W := 0.85 # the door model's width
const SLIDE_W := 1.8 # the sliding door model's width
const DOOR_HEAD := 2.06 # a door's head above its floor
const WINDOW_SILL := 0.9
const WINDOW_HEAD := 2.1


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
	for r in cfg.get("basement_footprint", cfg.get("footprint", [])):
		bfoot.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	hole = bfoot
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.name)] = mi
	if parts.has("base"):
		var b: MeshInstance3D = parts["base"]
		for i in b.mesh.get_surface_count():
			var mat: Material = b.get_active_material(i)
			if mat != null and "floor" in str(mat.resource_name).to_lower():
				_floor_surfaces.append([b, i, b.get_surface_override_material(i)])
	for od in cfg.get("outside_doors", []):
		for nm in ["wall_%s" % od["side"], "wall_%s_low" % od["side"]]:
			if parts.has(nm):
				_cut(parts[nm], float(od["at"]) - float(od["width"]) * 0.5 - 0.02, float(od["at"]) + float(od["width"]) * 0.5 + 0.02, DOOR_HEAD + 0.3)
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
	var patches := 0
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
			if bool(room.get("patch", false)):
				# a floor laid in the world editor: a thin layer over what's there, the later ones on top
				patches += 1
				_built.append(_slab(roots[lv], rect, y + 0.045, y + 0.047 + 0.002 * patches, mat, "Floor_%s" % room["id"]))
				continue
			_built.append(_slab(roots[lv], rect, y + 0.045 - thick, y + 0.045, mat, "Floor_%s" % room["id"]))
			var c := _slab(roots[lv], rect, _ceiling_y(lv), _ceiling_y(lv) + 0.04, cm, "Ceiling_%s" % room["id"])
			c.visible = false
			ceilings.append(c)
			_built.append(c)


func _walls() -> void:
	var wi := -1
	for w in cfg.get("walls", []):
		wi += 1
		var lv := str(w["level"])
		var seg: Array = w["wall"]
		var a := Vector2(float(seg[0]), float(seg[1]))
		var b := Vector2(float(seg[2]), float(seg[3]))
		var base_y := _level_y(lv) if lv != "all" else basement_y
		var y0 := float(w.get("from", base_y))
		var y1 := float(w.get("to", _ceiling_y(lv) if lv != "all" else upper_y))
		var col := _wall_colour(a.lerp(b, 0.5), lv)
		if wi == selected_wall:
			col = Color(1.0, 0.8, 0.3)
		for piece in _pieces(a, b, w.get("doors", [])):
			var p0: Vector2 = piece[0]
			var p1: Vector2 = piece[1]
			var full := _wall_box(roots[lv], p0, p1, y0, y1, col)
			var low := _wall_box(roots[lv], p0, p1, y0, maxf(y0 + 0.05, _level_y(lv) + LOW), col.darkened(0.08))
			low.visible = false
			_built.append_array([full, low])
			walls.append({"full": full, "low": low, "level": lv, "c": p0.lerp(p1, 0.5), "a": p0, "b": p1, "i": wi})
		for d in w.get("doors", []):
			_opening(lv, a, b, d, y0, y1, col, wi)
	_outside_doors()


## An outside door: the shell's wall `mi` (the house model's, this house's copy alone) loses every
## triangle between x0 and x1 (the house's x) below `top`, the window that was there and the brick
## under it.
func _cut(mi: MeshInstance3D, x0: float, x1: float, top: float) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var xf := house.global_transform.affine_inverse() * mi.global_transform
	var keep := []
	for i in mi.get_surface_override_material_count():
		keep.append(mi.get_surface_override_material(i))
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c: Vector3 = xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
			if c.x > x0 and c.x < x1 and c.y < top:
				continue
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if kept.is_empty():
			kept = PackedInt32Array([0, 0, 0]) # keep the surface (and its material's index)
		arr[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arr)
		out.surface_set_material(si, src.surface_get_material(si))
		out.surface_set_name(si, src.surface_get_name(si))
	mi.mesh = out
	for i in mini(keep.size(), out.get_surface_count()):
		mi.set_surface_override_material(i, keep[i])


## The outside doors' frames and doors (cfg "outside_doors"), in the holes _cut() made.
func _outside_doors() -> void:
	var trim := _flat_mat(Color("#f2efe8"))
	for od in cfg.get("outside_doors", []):
		var z := float(od["z"])
		var at := float(od["at"])
		var wd := float(od["width"])
		var a := Vector2(at - wd * 0.5 - 0.5, z)
		var b := Vector2(at + wd * 0.5 + 0.5, z)
		_opening("main", a, b, [at, wd, str(od.get("kind", "slide"))], 0.0, DOOR_HEAD + 0.06, Color.WHITE, -1)
		# the reveal: jambs and a head through the brick's thickness
		for x in [at - wd * 0.5 - 0.04, at + wd * 0.5 + 0.04]:
			_built.append(_box(roots["main"], Vector3(0.08, DOOR_HEAD + 0.3, 0.38), Vector3(x, (DOOR_HEAD + 0.3) * 0.5, z), trim))
		_built.append(_box(roots["main"], Vector3(wd + 0.16, 0.24, 0.38), Vector3(at, DOOR_HEAD + 0.18, z), trim))


## What fills an opening in a wall: nothing for a plain gap; a header and a door, or sliding glass
## doors, that open as she comes up; or a window (sill, glass in a white frame, head) that still
## blocks the way.
func _opening(lv: String, a: Vector2, b: Vector2, d: Array, y0: float, y1: float, col: Color, wi: int) -> void:
	var kind := str(d[2]) if d.size() > 2 else "open"
	if kind == "open":
		return
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var at := float(d[0])
	var wd := float(d[1])
	var p0 := Vector2(at - wd * 0.5, a.y) if along_x else Vector2(a.x, at - wd * 0.5)
	var p1 := Vector2(at + wd * 0.5, a.y) if along_x else Vector2(a.x, at + wd * 0.5)
	var c := p0.lerp(p1, 0.5)
	var fl := _level_y(lv) if lv != "all" else basement_y
	# a window may give its own sill and head over the floor ([at, width, "window", sill, head]), to
	# line up with the house model's own windows
	var w_sill := float(d[3]) if d.size() > 3 else WINDOW_SILL
	var w_head := float(d[4]) if d.size() > 4 else WINDOW_HEAD
	var head := fl + (w_head if kind == "window" else DOOR_HEAD + (0.06 if kind == "slide" else 0.0))
	if y1 > head + 0.01:
		var hb := _short_box(roots[lv], p0, p1, head, y1, col)
		_built.append(hb)
		walls.append({"full": hb, "low": null, "level": lv, "c": c, "a": p0, "b": p1, "i": wi, "block": false})
	var rot := 0.0 if along_x else -PI * 0.5 # a model laid along +X turned to lie along the wall
	if kind == "window":
		var sill := _short_box(roots[lv], p0, p1, y0, fl + w_sill, col)
		var low := _short_box(roots[lv], p0, p1, y0, maxf(y0 + 0.05, fl + LOW), col.darkened(0.08))
		low.visible = false
		_built.append_array([sill, low])
		walls.append({"full": sill, "low": low, "level": lv, "c": c, "a": p0, "b": p1, "i": wi})
		var win := Node3D.new()
		win.position = Vector3(c.x, fl + w_sill, c.y)
		win.rotation.y = rot
		roots[lv].add_child(win)
		_built.append(win)
		var h := w_head - w_sill
		var glass := _box(win, Vector3(wd, h, 0.02), Vector3(0, h * 0.5, 0), Catalog.window_glass())
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var frame := _flat_mat(Color("#f4f1ea"))
		for fr in [[Vector3(wd, 0.06, WALL_T + 0.02), Vector3(0, 0.03, 0)], [Vector3(wd, 0.06, WALL_T + 0.02), Vector3(0, h - 0.03, 0)],
				[Vector3(0.06, h, WALL_T + 0.02), Vector3(-wd * 0.5 + 0.03, h * 0.5, 0)], [Vector3(0.06, h, WALL_T + 0.02), Vector3(wd * 0.5 - 0.03, h * 0.5, 0)],
				[Vector3(0.04, h, 0.05), Vector3(0, h * 0.5, 0)]]:
			_box(win, fr[0], fr[1], frame)
		walls.append({"full": win, "low": null, "level": lv, "c": c, "a": p0, "b": p1, "i": wi, "block": false})
		return
	var pivot := Node3D.new()
	roots[lv].add_child(pivot)
	_built.append(pivot)
	var part: Node3D = pivot
	if kind == "door":
		# hinged on the gap's low end, the slab along the wall
		pivot.position = Vector3(p0.x, fl + 0.045, p0.y)
		pivot.rotation.y = rot
		var holder := Node3D.new()
		holder.scale = Vector3(wd / DOOR_W, 1, 1)
		pivot.add_child(holder)
		if ResourceLoader.exists(DOOR_GLB):
			holder.add_child((load(DOOR_GLB) as PackedScene).instantiate())
		else:
			_box(holder, Vector3(DOOR_W, 2.02, 0.04), Vector3(DOOR_W * 0.5, 1.01, 0), _flat_mat(Color("#f4f1ea")))
			_box(holder, Vector3(0.06, 0.06, 0.12), Vector3(DOOR_W - 0.08, 0.95, 0), _flat_mat(Color("#c9a24a")))
	else:
		pivot.position = Vector3(c.x, fl + 0.045, c.y)
		pivot.rotation.y = rot
		var holder := Node3D.new()
		holder.scale = Vector3(wd / SLIDE_W, 1, 1)
		pivot.add_child(holder)
		if ResourceLoader.exists(SLIDE_GLB):
			var m: Node3D = (load(SLIDE_GLB) as PackedScene).instantiate()
			holder.add_child(m)
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for si in mesh.get_surface_count():
					var mat := mesh.surface_get_material(si)
					if mat != null and "glass" in str(mat.resource_name).to_lower():
						(mi as MeshInstance3D).set_surface_override_material(si, Catalog.window_glass())
			var sl := m.find_child("slide", true, false)
			part = sl if sl is Node3D else holder
		else:
			var fm := _flat_mat(Color("#ecebe6"))
			for fr in [[Vector3(SLIDE_W, 0.06, 0.1), Vector3(0, 0.03, 0)], [Vector3(SLIDE_W, 0.06, 0.1), Vector3(0, 2.05, 0)],
					[Vector3(0.06, 2.08, 0.1), Vector3(-SLIDE_W * 0.5 + 0.03, 1.04, 0)], [Vector3(0.06, 2.08, 0.1), Vector3(SLIDE_W * 0.5 - 0.03, 1.04, 0)]]:
				_box(holder, fr[0], fr[1], fm)
			_box(holder, Vector3(SLIDE_W * 0.5, 1.98, 0.02), Vector3(-SLIDE_W * 0.25, 1.04, -0.025), Catalog.window_glass())
			var sl := Node3D.new()
			sl.name = "slide"
			holder.add_child(sl)
			_box(sl, Vector3(SLIDE_W * 0.5, 1.98, 0.02), Vector3(SLIDE_W * 0.25, 1.04, 0.025), Catalog.window_glass())
			_box(sl, Vector3(0.05, 1.98, 0.05), Vector3(0.05, 1.04, 0.025), fm)
			part = sl
	doors.append({"node": pivot, "part": part, "kind": kind, "c": c, "lv": lv, "rot0": pivot.rotation.y, "x0": part.position.x, "open": 0.0})


## A box between two points of a wall's centre line, `y0` to `y1`, no longer than the gap.
func _short_box(parent: Node3D, a: Vector2, b: Vector2, y0: float, y1: float, col: Color) -> MeshInstance3D:
	var mi := _wall_box(parent, a, b, y0, y1, col)
	var bm := mi.mesh as BoxMesh
	if absf(b.x - a.x) > absf(b.y - a.y):
		bm.size.x -= WALL_T
	else:
		bm.size.z -= WALL_T
	return mi


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## The walls, openings, floors and ceilings built again from cfg (the world editor changed them).
func rebuild() -> void:
	for n in _built:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_built.clear()
	walls.clear()
	ceilings.clear()
	doors.clear()
	_floors()
	_walls()
	_show()
	mark_grid()


## The world editor's house tools change these and rebuild (god_mode.gd, house_edit.gd).
func set_layout(new_walls: Array, new_rooms: Array) -> void:
	cfg["walls"] = new_walls
	cfg["rooms"] = new_rooms
	rebuild()


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


## A piece's fabric or paint in another colour (its pattern kept, as Furniture.set_color() does).
func _tint(n: Node3D, c: Color, parts: Array) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base != null and parts.has(base.resource_name):
				mi.set_surface_override_material(i, FurnitureScript.recolored(base, c))


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
		if f.has("tint"):
			_tint(n, Color.html(str(f["tint"])), f.get("tint_parts", Catalog.ITEMS.get(str(f["id"]), {}).get("colors", {}).get("parts", [])))


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
			if _carpet(m, "carpet_shag", Color("#5a7a30"), 0.5, 1.4):
				_mats[kind] = m
				return m
			img = _noise(Color("#4f6b2a"), 0.28, 9)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 0.8
		"carpet_blue":
			if _carpet(m, "carpet_pile", Color("#6a8cb6"), 0.6, 0.8):
				_mats[kind] = m
				return m
			img = _noise(Color("#5d7fa8"), 0.12, 3)
		"carpet_cream":
			if _carpet(m, "carpet_pile", Color("#f0e6cf"), 0.6, 0.8):
				_mats[kind] = m
				return m
			img = _noise(Color("#e3d8c0"), 0.08, 3)
		"cement":
			img = _noise(Color("#8f8b84"), 0.1, 17)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 2.0
			m.roughness = 0.8
		"wood_oak":
			img = _boards(Color("#b98a55"), 6)
			m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 1.0
			m.roughness = 0.55
		_: # carpet_grey
			if _carpet(m, "carpet_pile", Color("#9a9a97"), 0.6, 0.8):
				_mats[kind] = m
				return m
			img = _noise(Color("#8b8b88"), 0.1, 5)
	img.generate_mipmaps()
	m.albedo_texture = ImageTexture.create_from_image(img)
	if m.roughness == 1.0:
		m.roughness = 0.95
	_mats[kind] = m
	return m


## A carpet from art/world_assets/carpet's maps (greyscale pile, tinted here, and its normal map),
## one tile every `tile` metres. False if the maps aren't there, so the drawn noise stands in.
func _carpet(m: StandardMaterial3D, map: String, tint: Color, tile: float, bump: float) -> bool:
	var base := "res://assets/textures/carpet/%s" % map
	if not ResourceLoader.exists(base + ".png"):
		return false
	m.albedo_texture = load(base + ".png")
	m.albedo_color = tint
	if ResourceLoader.exists(base + "_n.png"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_n.png")
		m.normal_scale = bump
	m.uv1_scale = Vector3(1.0, 1.0, 1.0) / tile
	m.roughness = 0.97
	return true


## Oak boards: `n` across the tile, each its own shade, with fine grain along it and dark seams.
static func _boards(wood: Color, n: int) -> Image:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var w := s / n
	var shade := []
	for i in n:
		shade.append(rng.randf_range(-0.08, 0.08))
	var grain := FastNoiseLite.new()
	grain.seed = 3
	grain.frequency = 0.08
	for y in s:
		for x in s:
			var b := mini(x / w, n - 1)
			var c: Color = wood.lightened(shade[b]) if shade[b] > 0.0 else wood.darkened(-shade[b])
			c = c.darkened(0.06 * (grain.get_noise_2d(x * 4.0, y * 0.25) + 1.0))
			if x % w == 0 or (y + b * 37) % s == 0:
				c = c.darkened(0.45)
			img.set_pixel(x, y, c)
	return img


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


static func _in(rects: Array, q: Vector3) -> bool:
	for r in rects:
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


## Every frame, for Nora, the dog and the villagers: keeps `n` on the house's floor under it. `prev`
## is the floor it stood on last frame (each keeps its own), and the new one is returned. Only the
## floor's change is applied, so anyone sitting or lying above it (a bench, the rock, a bed: their
## own code sets that height) keeps it; outside the house nothing changes.
static func follow(n: Node3D, prev: float) -> float:
	var f := y_at(n.position)
	if f == 0.0 and prev == 0.0:
		return 0.0
	# what's above the floor: the walk puts her back on the ground (0) each step, so a floor below the
	# ground (the basement stairs) counts from 0, not from it
	n.position.y = f + maxf(0.0, n.position.y - maxf(prev, 0.0))
	return f


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
		# in the basement, only the cells over it are floor
		main.astar.set_point_solid(c, level == BASEMENT and not _in(bfoot, _inv * (main._cell_center(c) as Vector3)))
	# the shell's walls: always
	for w in cfg.get("shell", []):
		var seg: Array = w["wall"] if w is Dictionary else w
		var doors: Array = w.get("doors", []) if w is Dictionary else []
		for piece in _pieces(Vector2(float(seg[0]), float(seg[1])), Vector2(float(seg[2]), float(seg[3])), doors):
			_block(_seg_rect(piece[0], piece[1], 0.22))
	for w in walls:
		if _reachable(str(w["level"])) and bool(w.get("block", true)):
			# a cell wide, so no cell centre slips through between its faces; its ends only reach
			# the wall's own, so a doorway beside it stays open
			for c in _cells([_wall_strip(w["a"], w["b"])], 0.0):
				main.astar.set_point_solid(c, true)
	if level != BASEMENT:
		# the foot of the basement stairs belongs to the basement: from up here it's a wall, so no path
		# runs down the flight and out beside a room on the floor above
		var rp := _ramp("down")
		if not rp.is_empty():
			var r: Array = rp["rect"]
			for c in _cells([Rect2(float(r[0]) + float(r[2]) - 0.5, float(r[1]), 0.5, float(r[3]))], 0.0):
				main.astar.set_point_solid(c, true)
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


## The ground a partition blocks: `BLOCK_T` across, its own length (and half its thickness) along.
func _wall_strip(a: Vector2, b: Vector2) -> Rect2:
	var lo := a.min(b)
	var hi := a.max(b)
	if absf(b.x - a.x) > absf(b.y - a.y):
		return Rect2(lo.x - WALL_T * 0.5, a.y - BLOCK_T * 0.5, hi.x - lo.x + WALL_T, BLOCK_T)
	return Rect2(a.x - BLOCK_T * 0.5, lo.y - WALL_T * 0.5, BLOCK_T, hi.y - lo.y + WALL_T)


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
	_swing_doors(q, delta)
	_show()
	if inside != was_inside and not inside:
		_restore_hidden()


## The doors and sliding doors inside open as she comes up to one on its floor, and close behind her.
func _swing_doors(q: Vector3, delta: float) -> void:
	for d in doors:
		var c: Vector2 = d["c"]
		var lv := str(d["lv"])
		var fl := _level_y(lv) if lv != "all" else basement_y
		var near: bool = (inside or lv == "main") and Vector2(q.x - c.x, q.z - c.y).length() < 1.5 and absf(main.player.position.y - house.global_position.y - fl) < 1.0
		d["open"] = move_toward(float(d["open"]), 1.0 if near else 0.0, delta * 2.2)
		var s := smoothstep(0.0, 1.0, float(d["open"]))
		if str(d["kind"]) == "door":
			(d["node"] as Node3D).rotation.y = float(d["rot0"]) - deg_to_rad(95.0) * s
		else:
			(d["part"] as Node3D).position.x = float(d["x0"]) - SLIDE_W * 0.47 * s


## The world editor: the level a point in the house's space is drawn on (the basement while she's
## down there, else the bedroom floor over the right half and the main floor over the left).
func level_name_at(q: Vector3) -> String:
	if level == BASEMENT:
		return "basement"
	return "upper" if q.x > split_x else "main"


## Where the world editor's pointer meets the floors shown now (world), or null off the house.
func editor_pick(from: Vector3, dir: Vector3) -> Variant:
	var hs: Array = [basement_y] if level == BASEMENT else [upper_y, 0.0]
	for h in hs:
		var hit: Variant = Plane(Vector3.UP, house.global_position.y + float(h)).intersects_ray(from, dir)
		if hit == null:
			continue
		var q := local(hit)
		if in_footprint(q) and absf(floor_local(q, level) - float(h)) < 0.02:
			return hit
	return null


## The wall in cfg "walls" nearest `q` (the house's x / z) on level `lv`, within `reach`; -1 if none.
func wall_near(q: Vector2, lv: String, reach := 0.3) -> int:
	var best := -1
	var best_d := reach
	var i := -1
	for w in cfg.get("walls", []):
		i += 1
		var wl := str(w["level"])
		if wl != lv and not (lv == "main" and wl == "upper" and q.x <= split_x + 0.2) and not (lv == "upper" and wl == "main" and q.x >= split_x - 0.2):
			continue
		var seg: Array = w["wall"]
		var a := Vector2(float(seg[0]), float(seg[1]))
		var b := Vector2(float(seg[2]), float(seg[3]))
		var dd := Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q)
		if dd < best_d:
			best_d = dd
			best = i
	return best


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
		if w["low"] != null:
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
