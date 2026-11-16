extends Node
## Building walls (Alex, 2026-11-15): in build mode (B) she lays walls one at a time on a 2 m grid,
## paying for each as it goes up. A run of walls that closes a room against her house joins it: the
## house wall between them opens in a doorway, and the room gets the house's plank floor and gable
## roof. On a plot bought from Gary at Willow Homes she can start a whole new house; its first wall
## pays for the foundations too. Prices and plots are in data/economy.json "building".
##
## What she built is Game.flags["built_walls"]: edge key -> "wall" or "door". An edge key is
## "x,z,h" for the wall from (x, z) to (x + 2, z), or "x,z,v" for (x, z) to (x, z + 2), x and z in
## metres on the even grid. The plots she owns are Game.flags["plots_owned"] (their ids). Rooms
## aren't saved: they're worked out from the walls (compute()), so a wall taken down opens its room.
##
## main.gd draws it all in _rebuild_house() through build_into(), so the walls, floors and roofs
## are the house's own (_wall, _plank_floor, _house_roof), cut down and lifted by the same rules.

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")

const STEP := 2 # metres between grid lines
const DOORWAY := 1.4 # metres across a doorway (her front door's is 1.4)

var main
var tool := "" # "" (furniture), "wall" or "door": what a click in build mode lays
var hover := "" # the edge under the pointer
var hover_ok := false
var hover_note := ""
var rooms: Array = [] # {"cells": Array of Vector2i, "rects": Array of Rect2, "joined": bool, "plot": String}
var room_cells := {} # Vector2i -> index in rooms
var open_house := {} # house edges a joined room opens (edge key -> true)
var wall_nodes: Array = [] # Node3D per built edge (meta "edge", "kind"), for the world editor
var wall_rects: Array = [] # the ground each built wall stands on
var _ghost: MeshInstance3D
var _mats := {}
var _plot_root: Node3D


# --- the data ----------------------------------------------------------------------------------

static func econ() -> Dictionary:
	return Data.economy().get("building", {})


static func price(kind: String) -> int:
	return int(econ().get("door" if kind == "door" else "wall", 80))


static func new_house_fee() -> int:
	return int(econ().get("new_house_fee", 600))


static func plots() -> Array:
	return econ().get("plots", [])


static func plot_rect(p: Dictionary) -> Rect2:
	var r: Array = p["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


static func plot_def(id: String) -> Dictionary:
	for p in plots():
		if str(p["id"]) == id:
			return p
	return {}


func owned() -> Array:
	return Game.flag("plots_owned", [])


func owns(id: String) -> bool:
	return owned().has(id)


func plot_price(p: Dictionary) -> int:
	return int(round(float(p["price"]) * (1.0 - 0.04 * Game.hearts("gary"))))


## Gary sells her a plot: it's cleared of trees and scrub (forage.gd hides them) and staked out.
func buy_plot(id: String) -> bool:
	var p := plot_def(id)
	if p.is_empty() or owns(id) or not Game.spend(plot_price(p)):
		return false
	var o: Array = owned().duplicate()
	o.append(id)
	Game.set_flag("plots_owned", o)
	refresh_world()
	return true


## The plot a ground point is on ("" for none of hers).
func plot_at(q: Vector2) -> String:
	for id in owned():
		var p := plot_def(str(id))
		if not p.is_empty() and plot_rect(p).has_point(q):
			return str(id)
	return ""


## Scenery standing on a plot she owns is cleared (forage.apply hides it, like a felled tree).
func clears(at: Vector3) -> bool:
	return plot_at(Vector2(at.x, at.z)) != ""


func edges() -> Dictionary:
	return Game.flag("built_walls", {})


func _set_edges(d: Dictionary) -> void:
	if d.is_empty():
		Game.flags.erase("built_walls")
	else:
		Game.set_flag("built_walls", d)


static func key(x: int, z: int, h: bool) -> String:
	return "%d,%d,%s" % [x, z, "h" if h else "v"]


## [Vector2 from, Vector2 to, bool horizontal]
static func ends(k: String) -> Array:
	var p := k.split(",")
	var x := float(p[0])
	var z := float(p[1])
	var h := p[2] == "h"
	return [Vector2(x, z), Vector2(x + STEP, z) if h else Vector2(x, z + STEP), h]


## The ground a wall on this edge stands on.
static func edge_rect(k: String, thick := 0.2) -> Rect2:
	var e := ends(k)
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	return Rect2(minf(a.x, b.x) - thick * 0.5, minf(a.y, b.y) - thick * 0.5, absf(b.x - a.x) + thick, absf(b.y - a.y) + thick)


## The two cells either side of an edge: [north or west, south or east].
static func sides(k: String) -> Array:
	var p := k.split(",")
	var cx := int(p[0]) / STEP
	var cz := int(p[1]) / STEP
	if p[2] == "h":
		return [Vector2i(cx, cz - 1), Vector2i(cx, cz)]
	return [Vector2i(cx - 1, cz), Vector2i(cx, cz)]


static func cell_of(q: Vector2) -> Vector2i:
	return Vector2i(floori(q.x / STEP), floori(q.y / STEP))


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * STEP, c.y * STEP, STEP, STEP)


## The four edges round a cell and the cell across each: [[edge, neighbour], ...].
static func around(c: Vector2i) -> Array:
	var x := c.x * STEP
	var z := c.y * STEP
	return [[key(x, z, true), c + Vector2i(0, -1)], [key(x, z + STEP, true), c + Vector2i(0, 1)],
		[key(x, z, false), c + Vector2i(-1, 0)], [key(x + STEP, z, false), c + Vector2i(1, 0)]]


# --- her house as edges ------------------------------------------------------------------------

## Nora's house's own walls on the grid: x 0..8, z from the back (main._zmin()) to the front (6).
## Her front door is the edge "8,2,v": it stays as it is.
func house_edges() -> Dictionary:
	var out := {}
	var z0: int = int(main._zmin())
	var w := int(main.HOUSE_W)
	var d := int(main.HOUSE_FRONT)
	for x in range(0, w, STEP):
		out[key(x, z0, true)] = "house"
		out[key(x, d, true)] = "house"
	for z in range(z0, d, STEP):
		out[key(0, z, false)] = "house"
		out[key(w, z, false)] = "house"
	return out


func house_cells() -> Dictionary:
	var out := {}
	for x in range(0, int(main.HOUSE_W) / STEP):
		for z in range(int(main._zmin()) / STEP, int(main.HOUSE_FRONT) / STEP):
			out[Vector2i(x, z)] = true
	return out


const FRONT_DOOR := "8,2,v"


## The stretches of each of the house's walls that a joined room shares, for main._rebuild_house:
## {"back": [[from, to], ...], "front": ..., "left": ..., "right": ...}, along x for back and front
## and along z for the sides. A doorway opens in the middle of each.
func house_spans() -> Dictionary:
	var out := {"back": [], "front": [], "left": [], "right": []}
	if open_house.is_empty():
		return out
	var z0: int = int(main._zmin())
	var lines := {"back": [], "front": [], "left": [], "right": []}
	for k in open_house:
		var p := str(k).split(",")
		var x := int(p[0])
		var z := int(p[1])
		if p[2] == "h":
			lines["back" if z == z0 else "front"].append(x)
		else:
			lines["left" if x == 0 else "right"].append(z)
	for side in lines:
		var ts: Array = lines[side]
		ts.sort()
		var run: Array = []
		for t in ts:
			if not run.is_empty() and int(run[1]) == int(t):
				run[1] = int(t) + STEP
			else:
				if not run.is_empty():
					out[side].append(run)
				run = [int(t), int(t) + STEP]
		if not run.is_empty():
			out[side].append(run)
	return out


# --- rooms --------------------------------------------------------------------------------------

## Works out the rooms from the walls: every patch of cells shut in by walls (her own and the
## house's), outside the house. A room that shares a wall with the house joins it.
func compute() -> void:
	rooms.clear()
	room_cells.clear()
	open_house.clear()
	var built := edges()
	if built.is_empty():
		return
	var walls := house_edges()
	walls.merge(built, true)
	var hc := house_cells()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for k in walls:
		for c in sides(k):
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	# flood in from the border: whatever it can't reach is shut in
	var seen := {}
	var todo: Array = []
	for x in range(lo.x, hi.x + 1):
		todo.append(Vector2i(x, lo.y))
		todo.append(Vector2i(x, hi.y))
	for z in range(lo.y, hi.y + 1):
		todo.append(Vector2i(lo.x, z))
		todo.append(Vector2i(hi.x, z))
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if seen.has(c) or c.x < lo.x or c.y < lo.y or c.x > hi.x or c.y > hi.y:
			continue
		seen[c] = true
		for a in around(c):
			if not walls.has(a[0]) and not seen.has(a[1]):
				todo.append(a[1])
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			if seen.has(c) or hc.has(c) or room_cells.has(c):
				continue
			# a room: the shut-in cells joined to this one, through anything but a wall or doorway
			var cells: Array = []
			var q: Array = [c]
			var idx := rooms.size()
			while not q.is_empty():
				var d: Vector2i = q.pop_back()
				if room_cells.has(d) or seen.has(d) or hc.has(d):
					continue
				room_cells[d] = idx
				cells.append(d)
				for a in around(d):
					if not walls.has(a[0]):
						q.append(a[1])
			var joined := false
			for d in cells:
				for a in around(d):
					if hc.has(a[1]) and str(a[0]) != FRONT_DOOR and str(walls.get(a[0], "")) == "house":
						open_house[a[0]] = true
						joined = true
			var centre := cell_rect(cells[0]).get_center()
			rooms.append({"cells": cells, "rects": _rects(cells), "joined": joined, "plot": plot_at(centre)})


## Cells as a few rectangles (in metres): rows of cells, then rows stacked where they match.
static func _rects(cells: Array) -> Array:
	var have := {}
	for c in cells:
		have[c] = true
	var used := {}
	var out: Array = []
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in sorted:
		if used.has(c):
			continue
		var w := 1
		while have.has(c + Vector2i(w, 0)) and not used.has(c + Vector2i(w, 0)):
			w += 1
		var h := 1
		while true:
			var ok := true
			for i in w:
				var n: Vector2i = c + Vector2i(i, h)
				if not have.has(n) or used.has(n):
					ok = false
					break
			if not ok:
				break
			h += 1
		for i in w:
			for j in h:
				used[c + Vector2i(i, j)] = true
		out.append(Rect2(c.x * STEP, c.y * STEP, w * STEP, h * STEP))
	return out


## Whether a ground point is inside one of the rooms she built.
func indoors(q: Vector2) -> bool:
	return room_cells.has(cell_of(q))


## Whether a footprint sits wholly inside one room she built, clear of its walls.
func encloses(r: Rect2) -> bool:
	if room_cells.is_empty():
		return false
	var room := -1
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var c := cell_of(p)
		if not room_cells.has(c) or (room >= 0 and int(room_cells[c]) != room):
			return false
		room = int(room_cells[c])
	for w in wall_rects:
		if (w as Rect2).intersects(r):
			return false
	return true


## Whether a footprint outdoors would run into what she built (a room or a wall).
func blocks(r: Rect2) -> bool:
	for w in wall_rects:
		if (w as Rect2).intersects(r):
			return true
	for room in rooms:
		for rr in room["rects"]:
			if (rr as Rect2).intersects(r):
				return true
	return false


# --- drawing -------------------------------------------------------------------------------------

## Builds the walls, and each room's floor and roof, under main.house_root (called from
## main._rebuild_house after the house's own walls).
func build_into() -> void:
	wall_nodes.clear()
	wall_rects.clear()
	var built := edges()
	for k in built:
		_build_wall(str(k), str(built[k]))
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		var group := "house" if room["joined"] else "room%d" % i
		for r in room["rects"]:
			var rr := r as Rect2
			Catalog.box(main.house_root, Vector3(rr.size.x + 0.3, 0.1, rr.size.y + 0.3), Vector3(rr.get_center().x, -0.04, rr.get_center().y), Catalog.STONE)
			main._plank_floor(rr, 11 + i * 7 + int(rr.position.x * 3.0 + rr.position.y), "house")
			main._house_roof(rr, rr.size.y >= rr.size.x, group)
	_draw_plots()


func _build_wall(k: String, kind: String) -> void:
	var e := ends(k)
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var h: bool = e[2]
	var s := sides(k)
	var in0 := room_cells.has(s[0])
	var in1 := room_cells.has(s[1])
	var across := Vector3(0, 0, 1) if h else Vector3(1, 0, 0)
	var normal := -across if (in1 and not in0) else across # out of the room
	var divider := in0 and in1
	var mid := (a + b) * 0.5
	var node := Node3D.new()
	node.name = "BuiltWall"
	node.position = Vector3(mid.x, 0, mid.y)
	node.set_meta("edge", k)
	node.set_meta("kind", kind)
	main.house_root.add_child(node)
	wall_nodes.append(node)
	var along := (b - a).normalized()
	if kind == "door":
		var side := (STEP - DOORWAY) * 0.5
		main._wall(a, a + along * side, normal, [], main.WALL_H, true, divider, node)
		main._wall(b - along * side, b, normal, [], main.WALL_H, true, divider, node)
		main._lintel(a + along * side, b - along * side, normal, node)
	else:
		# an outside wall of a room gets a window on every other grid step, like the house's
		var wins: Array = []
		if (in0 != in1) and posmod(int(a.x + a.y) / STEP, 2) == 0:
			wins.append(mid.x if h else mid.y)
		main._wall(a, b, normal, wins, main.WALL_H, true, divider, node)
	wall_rects.append(edge_rect(k))


## Each plot she owns is staked out at its corners, with a little board.
func _draw_plots() -> void:
	if _plot_root != null and is_instance_valid(_plot_root):
		_plot_root.free()
	_plot_root = Node3D.new()
	_plot_root.name = "Plots"
	main.house_root.add_child(_plot_root)
	for id in owned():
		var p := plot_def(str(id))
		if p.is_empty():
			continue
		var r := plot_rect(p)
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			Catalog.cyl(_plot_root, 0.05, 0.06, 0.7, Vector3(c.x, 0.35, c.y), Catalog.WOOD)
			Catalog.box(_plot_root, Vector3(0.14, 0.08, 0.14), Vector3(c.x, 0.72, c.y), Color(0.85, 0.25, 0.2))


# --- laying walls ------------------------------------------------------------------------------

## The edge nearest a ground point.
static func edge_at(g: Vector3) -> String:
	var hz := roundf(g.z / STEP) * STEP
	var vx := roundf(g.x / STEP) * STEP
	var hx := floorf(g.x / STEP) * STEP
	var vz := floorf(g.z / STEP) * STEP
	if absf(g.z - hz) <= absf(g.x - vx):
		return key(int(hx), int(hz), true)
	return key(int(vx), int(vz), false)


## The grid points walls already reach on her farm or on a plot: where a new wall may start.
func _anchors(on_plot: String) -> Dictionary:
	var out := {}
	var built := edges()
	var src: Dictionary = built.duplicate()
	if on_plot == "":
		src.merge(house_edges())
	for k in src:
		var e := ends(k)
		var a: Vector2 = e[0]
		if plot_at(a + (e[1] - a) * 0.5) != on_plot:
			continue
		out[Vector2i(roundi(a.x), roundi(a.y))] = true
		var b: Vector2 = e[1]
		out[Vector2i(roundi(b.x), roundi(b.y))] = true
	return out


## Whether a wall can go on this edge now, and what it would cost: {"ok", "why", "cost", "plot", "fee"}.
func check(k: String, kind := "wall") -> Dictionary:
	var out := {"ok": false, "why": "", "cost": price(kind), "plot": "", "fee": 0}
	var e := ends(k)
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var mid := (a + b) * 0.5
	if edges().has(k):
		out["why"] = "There's a wall there already."
		return out
	if house_edges().has(k) or (house_cells().has(sides(k)[0]) and house_cells().has(sides(k)[1])):
		out["why"] = "That's your house."
		return out
	var plot := plot_at(mid)
	out["plot"] = plot
	var r := edge_rect(k)
	if plot == "":
		if not main.LOT.encloses(r):
			out["why"] = "That's not your land. Gary at Willow Homes sells building plots."
			return out
	elif not plot_rect(plot_def(plot)).grow(0.11).encloses(r):
		out["why"] = "Keep inside your plot."
		return out
	var anchors := _anchors(plot)
	var touches := anchors.has(Vector2i(roundi(a.x), roundi(a.y))) or anchors.has(Vector2i(roundi(b.x), roundi(b.y)))
	if plot != "" and anchors.is_empty():
		out["fee"] = new_house_fee() # the first wall of a new house lays its foundations
	elif not touches:
		out["why"] = "Walls go up against your house, or against a wall you've built." if plot == "" else "Build on from the walls you've started."
		return out
	out["cost"] = int(out["cost"]) + int(out["fee"])
	var why := _blocked(r)
	if why != "":
		out["why"] = why
		return out
	out["ok"] = true
	return out


## What's in the way of a wall on this ground, or "".
func _blocked(r: Rect2) -> String:
	var rr := r.grow(-0.02)
	for f in main.furniture:
		if not f.is_flat() and f.footprint().intersects(rr):
			return "Move the %s out of the way first." % f.display_name()
	for p in main.plots:
		if Rect2(p.position.x - 0.75, p.position.z - 0.75, 1.5, 1.5).intersects(rr):
			return "There's a crop bed in the way."
	if (main.pen_rect as Rect2).grow(0.3).intersects(rr):
		return "The pen's in the way."
	for g in main.grid_blockers + main.place_blockers:
		if (g as Rect2).intersects(rr):
			return "Something's in the way."
	if r.grow(0.3).has_point(Vector2(main.player.position.x, main.player.position.z)):
		return "Nora's standing there."
	return ""


## Puts a wall (or doorway) up on an edge and takes its price. False if it can't go there.
func place(k: String, kind := "wall") -> bool:
	var c := check(k, kind)
	if not c["ok"]:
		main.hud.show_toast(str(c["why"]))
		return false
	if not Game.spend(int(c["cost"])):
		return false
	var rooms_before := rooms.size()
	var d: Dictionary = edges().duplicate()
	d[k] = kind
	_set_edges(d)
	refresh_world()
	var what := "doorway" if kind == "door" else "wall"
	if rooms.size() > rooms_before:
		var joined: bool = _room_by(k).get("joined", false)
		main.hud.show_toast("The room's closed in! Floor and roof are on%s." % (", and a doorway joins it to the house" if joined else ""))
	elif int(c["fee"]) > 0:
		main.hud.show_toast("Foundations laid for a new house, and the first %s is up (%dc)." % [what, int(c["cost"])])
	else:
		main.hud.show_toast("Built a %s (%dc)." % [what, int(c["cost"])])
	return true


func _room_by(k: String) -> Dictionary:
	for s in sides(k):
		if room_cells.has(s):
			return rooms[int(room_cells[s])]
	return {}


## Takes a wall she built down again, for part of what it cost.
func remove(k: String) -> bool:
	var d: Dictionary = edges().duplicate()
	if not d.has(k):
		return false
	var back := int(round(price(str(d[k])) * float(econ().get("refund", 0.5))))
	d.erase(k)
	_set_edges(d)
	Game.coins += back
	refresh_world()
	main.hud.show_toast("Took the wall down (+%dc)." % back)
	return true


## Rebuilds the house, its rooms and the walking grid after a change.
func refresh_world() -> void:
	compute()
	main._rebuild_house()
	main._rebuild_grid()
	if main.forage != null:
		main.forage.apply() # a plot she just bought is cleared
	if main.god != null:
		main.god.sync_built()


# --- the tool in build mode -------------------------------------------------------------------

func set_tool(t: String) -> void:
	tool = t
	hover = ""
	if _ghost != null:
		_ghost.visible = false
	main.hud.set_wall_tool(t)


func _ensure_ghost() -> void:
	if _ghost != null:
		return
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	_ghost.visible = false
	main.add_child(_ghost)
	for n in ["ok", "bad", "down"]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = {"ok": Color(0.35, 0.95, 0.45, 0.45), "bad": Color(1.0, 0.3, 0.25, 0.45), "down": Color(1.0, 0.7, 0.2, 0.45)}[n]
		_mats[n] = m


## The pointer moved over the ground at g: show the edge under it.
func hover_at(g: Variant) -> void:
	_ensure_ghost()
	if tool == "" or g == null:
		_ghost.visible = false
		hover = ""
		return
	hover = edge_at(g)
	var e := ends(hover)
	var a: Vector2 = e[0]
	var b: Vector2 = e[1]
	var mid := (a + b) * 0.5
	var h: bool = e[2]
	(_ghost.mesh as BoxMesh).size = Vector3(STEP, main.WALL_H, 0.24) if h else Vector3(0.24, main.WALL_H, STEP)
	_ghost.position = Vector3(mid.x, main.WALL_H * 0.5, mid.y)
	_ghost.visible = true
	if edges().has(hover):
		hover_ok = false
		var back := int(round(price(str(edges()[hover])) * float(econ().get("refund", 0.5))))
		hover_note = "Click to take this wall down (+%dc back)." % back
		_ghost.material_override = _mats["down"]
	else:
		var c := check(hover, tool)
		hover_ok = c["ok"]
		hover_note = ("%s here: %dc%s" % ["Doorway" if tool == "door" else "Wall", int(c["cost"]), " (with %dc for the foundations)" % int(c["fee"]) if int(c["fee"]) > 0 else ""]) if hover_ok else str(c["why"])
		_ghost.material_override = _mats["ok" if hover_ok else "bad"]
	main.hud.set_wall_note(hover_note)


## A click in build mode with the wall tool: build on the edge, or take her own wall down.
func click(g: Variant) -> void:
	if g == null:
		return
	hover_at(g)
	if edges().has(hover):
		remove(hover)
	else:
		place(hover, tool)
	hover_at(g)


# --- the world editor --------------------------------------------------------------------------

## The world editor moved or deleted some of her walls: each goes back on the grid edge nearest
## where it was left (turned a quarter turn, it lies the other way), and deleted ones come down.
## els: [{"edge": key it was, "kind": ..., "pos": Vector3, "yaw": float, "deleted": bool}]
func from_editor(els: Array) -> void:
	var d := {}
	for el in els:
		if el["deleted"]:
			continue
		var h0: bool = str(el["edge"]).ends_with("h")
		var turned := posmod(roundi(float(el["yaw"]) / (PI * 0.5)), 2) == 1
		var h := h0 != turned
		var p: Vector3 = el["pos"]
		var k := key(int(roundf((p.x - STEP * 0.5) / STEP) * STEP), int(roundf(p.z / STEP) * STEP), true) if h \
			else key(int(roundf(p.x / STEP) * STEP), int(roundf((p.z - STEP * 0.5) / STEP) * STEP), false)
		d[k] = el["kind"]
	if d == edges():
		return
	_set_edges(d)
	compute()
	main._rebuild_house()
	main._rebuild_grid()
