extends Node
## Building walls (Alex, 2026-11-15): in build mode (B) she lays walls one at a time on a 2 m grid,
## paying for each as it goes up. A run of walls that closes a room against her house joins it: the
## house wall between them opens in a doorway, and the room gets the house's plank floor and gable
## roof. On a plot bought from Gary at Willow Homes she can start a whole new house; its first wall
## pays for the foundations too. Prices and plots are in data/economy.json "building".
##
## Openings (Alex, 2026-11-17: "all houses get build mode wall edits for a cost of wood or coin ...
## I want to be able to fully customize homes we build in the future also can place windows and
## doors"): the Doorway, Door, Sliding door and Window tools put one in any wall of hers, her house's
## own walls included (not the front door), or build a new wall with one in it. Each piece is paid in
## wood when she has enough for it, else coins (data/economy.json "building" "wall_wood" and
## "openings"), and what it was paid with is kept (Game.flags["built_paid"]: edge -> {"wall": [coins,
## wood], "open": [coins, wood]}), so taking it out gives half back in the same: wood paid back as
## wood, never as coins. Her house's own edges with an opening are Game.flags["house_openings"]
## (edge -> kind). Doors swing and sliding doors slide as she or the dog comes up (_process()).
##
## What she built is Game.flags["built_walls"]: edge key -> a kind in KINDS ("wall", "door" a doorway,
## "hdoor", "slide", "window"). An edge key is
## "x,z,h" for the wall from (x, z) to (x + 2, z), or "x,z,v" for (x, z) to (x, z + 2), x and z in
## metres on the even grid. The plots she owns are Game.flags["plots_owned"] (their ids). Rooms
## aren't saved: they're worked out from the walls (compute()), so a wall taken down opens its room.
##
## Floors (Alex, 2026-11-17, "fully customize homes"): the Floor tool lays the floor picked in its
## list (carpets, tiles, oak boards) over a whole room at a click: her house, or a room she built.
## Each 2 m cell is paid for ("building" "floors", in wood when she has enough, else coins) and kept
## in Game.flags["floors"] ("cx,cz" -> kind) with what paid in Game.flags["floors_paid"]; "planks",
## the floor the house was built with, takes it up again for half back. Drawn over the planks by
## _draw_floors(), only where the cell is still indoors.
##
## main.gd draws it all in _rebuild_house() through build_into(), so the walls, floors and roofs
## are the house's own (_wall, _plank_floor, _house_roof), cut down and lifted by the same rules.

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")

const STEP := 2 # metres between grid lines
const DOORWAY := 1.4 # metres across a doorway (her front door's is 1.4)
const KINDS := ["wall", "door", "hdoor", "slide", "window"]
const LABELS := {"wall": "Wall", "door": "Doorway", "hdoor": "Door", "slide": "Sliding door", "window": "Window"}
const GAPS := {"door": DOORWAY, "hdoor": 1.2, "slide": 1.6} # metres across each kind's gap, its jambs inside (over 1.1, or no cell of the walking grid is free in it: walls block 0.2 m past their faces)
const DOOR_GLB := "res://assets/props/door_interior.glb" # origin at the foot of its hinge edge, slab along +X
const SLIDE_GLB := "res://assets/props/sliding_door.glb" # "frame" and "slide", glass named glass
const DOOR_W := 0.85 # the door model's width
const SLIDE_W := 1.8 # the sliding door model's width
const SplitHouse = preload("res://scripts/split_house.gd") # its drawn tiles and boards
const FLOORS := ["planks", "carpet_grey", "carpet_blue", "carpet_cream", "tile_beige", "tile_white", "tile_black", "wood_oak"]
const FLOOR_LABELS := {"planks": "Plank boards (as built)", "carpet_grey": "Grey carpet", "carpet_blue": "Blue carpet", "carpet_cream": "Cream carpet",
	"tile_beige": "Beige tile", "tile_white": "White tile", "tile_black": "Black tile", "wood_oak": "Oak boards"}
const FLOOR_Y := 0.035 # the top of a laid floor, just over the planks (0.02)

var main
var tool := "" # "" (furniture), or a kind in KINDS: what a click in build mode lays
var doors: Array = [] # {"node", "part", "kind", "at": Vector2 (world), "rot0", "x0", "w", "open"}: _process() swings them
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
var floor_kind := "carpet_grey" # what the Floor tool lays
var hover_cells: Array = [] # the cells the Floor tool would lay (Vector2i)
var _floor_ghost: Node3D
var _floor_mats := {}
var _plot_root: Node3D


# --- the data ----------------------------------------------------------------------------------

static func econ() -> Dictionary:
	return Data.economy().get("building", {})


## Coins for a new wall of this kind (the wall and what's in it).
static func price(kind: String) -> int:
	return int(econ().get("wall", 80)) + int(opening_cost(kind)[0])


## [coins, wood] for the opening of a kind alone ([0, 0] for a plain wall).
static func opening_cost(kind: String) -> Array:
	var o: Dictionary = econ().get("openings", {}).get(kind, {})
	return [int(o.get("coins", 0)), int(o.get("wood", 0))]


## [coins, wood] for the wall alone.
static func wall_cost() -> Array:
	return [int(econ().get("wall", 80)), int(econ().get("wall_wood", 10))]


static func label(kind: String) -> String:
	return str(LABELS.get(kind, "Wall"))


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
	_draw_floors()
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
	# an outside wall of a room gets a window on every other grid step, like the house's
	var wins: Array = []
	if kind == "wall" and (in0 != in1) and posmod(int(a.x + a.y) / STEP, 2) == 0:
		wins.append(mid.x if h else mid.y)
	main._edge_piece(a, b, normal, kind, wins, divider, node)
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
	var out := {"ok": false, "why": "", "cost": price(kind), "plot": "", "fee": 0} # cost: in coins
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


## Puts a wall up on an edge, with an opening of `kind` in it unless it's a plain "wall", and takes
## its price: in wood if she has enough for it all, else coins. False if it can't go there.
func place(k: String, kind := "wall") -> bool:
	var c := check(k, kind)
	if not c["ok"]:
		main.hud.show_toast(str(c["why"]))
		return false
	var parts := _parts(kind)
	var paid := _pay(parts, int(c["fee"]))
	if paid.is_empty():
		return false
	var rooms_before := rooms.size()
	var d: Dictionary = edges().duplicate()
	d[k] = kind
	_set_edges(d)
	for part in paid:
		_set_paid(k, part, paid[part])
	refresh_world()
	var what := "wall" if kind == "wall" else "wall with a %s" % label(kind).to_lower()
	if rooms.size() > rooms_before:
		var joined: bool = _room_by(k).get("joined", false)
		main.hud.show_toast("The room's closed in! Floor and roof are on%s." % (", and a doorway joins it to the house" if joined else ""))
	elif int(c["fee"]) > 0:
		main.hud.show_toast("Foundations laid for a new house, and the first %s is up (%s)." % [what, _paid_text(paid, int(c["fee"]))])
	else:
		main.hud.show_toast("Built a %s (%s)." % [what, _paid_text(paid, 0)])
	return true


func _room_by(k: String) -> Dictionary:
	for s in sides(k):
		if room_cells.has(s):
			return rooms[int(room_cells[s])]
	return {}


## Takes a wall she built down again, with whatever is in it, for half of what it cost, given
## back in what it was paid with.
func remove(k: String) -> bool:
	var d: Dictionary = edges().duplicate()
	if not d.has(k):
		return false
	var kind := str(d[k])
	var back := [0, 0]
	for part in ["wall", "open"]:
		if part == "open" and kind == "wall":
			continue
		var b := _refund(_paid_part(k, part, kind))
		back = [back[0] + b[0], back[1] + b[1]]
	d.erase(k)
	_set_edges(d)
	_set_paid(k, "wall", null)
	_set_paid(k, "open", null)
	refresh_world()
	main.hud.show_toast("Took the wall down (%s back)." % _back_text(back))
	return true


# --- openings ------------------------------------------------------------------------------------

func house_openings() -> Dictionary:
	return Game.flag("house_openings", {})


## The parts a new wall of this kind is paid for: {"wall": [coins, wood], "open": [coins, wood]}.
static func _parts(kind: String) -> Dictionary:
	var out := {"wall": wall_cost()}
	if kind != "wall":
		out["open"] = opening_cost(kind)
	return out


## Whether an opening of `kind` can go in the standing wall on edge k (hers or the house's):
## {"ok", "why", "undo" (it's there already: a click takes it out), "house", "now" (what's in it)},
## or {} if no wall stands there.
func opening_check(k: String, kind: String) -> Dictionary:
	var out := {"ok": false, "why": "", "undo": false, "house": false, "now": "wall"}
	if edges().has(k):
		out["now"] = str(edges()[k])
	elif house_edges().has(k):
		out["house"] = true
		out["now"] = str(house_openings().get(k, "wall"))
		if k == FRONT_DOOR:
			out["why"] = "That's your front door."
			return out
		if open_house.has(k):
			out["why"] = "That wall's open to the room you built."
			return out
	else:
		return {}
	out["undo"] = str(out["now"]) == kind
	if not out["undo"] and GAPS.has(kind):
		var why := _furniture_in_doorway(k)
		if why != "":
			out["why"] = why
			return out
	out["ok"] = true
	return out


## A piece standing where a doorway on edge k would let her through, or "".
func _furniture_in_doorway(k: String) -> String:
	var e := ends(k)
	var mid: Vector2 = (e[0] + e[1]) * 0.5
	var r := Rect2(mid - Vector2(0.5, 0.5), Vector2(1.0, 1.0)).grow_individual(0, 0.5, 0, 0.5) if e[2] \
		else Rect2(mid - Vector2(0.5, 0.5), Vector2(1.0, 1.0)).grow_individual(0.5, 0, 0.5, 0)
	for f in main.furniture:
		if not f.is_flat() and f.footprint().intersects(r):
			return "Move the %s out of the way first." % f.display_name()
	return ""


## Puts an opening of `kind` in the wall on edge k, or takes it out if that's what's there. What
## was in it before comes out first, half paid back in what it was paid with.
func set_opening(k: String, kind: String) -> bool:
	var c := opening_check(k, kind)
	if c.is_empty():
		return false
	if not c["ok"]:
		main.hud.show_toast(str(c["why"]))
		return false
	var now := str(c["now"])
	var to := "wall" if bool(c["undo"]) else kind
	if to != "wall" and not _can_pay({"open": opening_cost(to)}, 0):
		main.hud.show_toast("Not enough: a %s costs %s." % [label(to).to_lower(), _cost_text({"open": opening_cost(to)}, 0)])
		return false
	var back := [0, 0]
	if now != "wall":
		back = _refund(_paid_part(k, "open", now))
		_set_paid(k, "open", null)
	var paid := {}
	if to != "wall":
		paid = _pay({"open": opening_cost(to)}, 0)
		_set_paid(k, "open", paid.get("open", null))
	if bool(c["house"]):
		var h: Dictionary = house_openings().duplicate()
		if to == "wall":
			h.erase(k)
		else:
			h[k] = to
		if h.is_empty():
			Game.flags.erase("house_openings")
		else:
			Game.set_flag("house_openings", h)
	else:
		var d: Dictionary = edges().duplicate()
		d[k] = to
		_set_edges(d)
	refresh_world()
	if to == "wall":
		main.hud.show_toast("Took the %s out (%s back)." % [label(now).to_lower(), _back_text(back)])
	elif now != "wall":
		main.hud.show_toast("Swapped the %s for a %s (%s, %s back)." % [label(now).to_lower(), label(to).to_lower(), _paid_text(paid, 0), _back_text(back)])
	else:
		main.hud.show_toast("Put a %s in (%s)." % [label(to).to_lower(), _paid_text(paid, 0)])
	return true


## The house grew and its back wall moved: openings in house walls that are gone come out, paid back.
func prune_house() -> void:
	var h: Dictionary = house_openings().duplicate()
	var he := house_edges()
	var back := [0, 0]
	for k in h.keys():
		if not he.has(k):
			var b := _refund(_paid_part(str(k), "open", str(h[k])))
			back = [back[0] + b[0], back[1] + b[1]]
			_set_paid(str(k), "open", null)
			h.erase(k)
	if h.is_empty():
		Game.flags.erase("house_openings")
	else:
		Game.set_flag("house_openings", h)


## The openings in the house's own wall line on `side` ("back", "front", "left", "right"):
## {metres along the line where the edge starts: kind}, for main._wall_line().
func line_edits(side: String) -> Dictionary:
	var out := {}
	var he := house_edges()
	var z0: int = int(main._zmin())
	var h := house_openings()
	for k in h:
		if not he.has(k) or str(k) == FRONT_DOOR or open_house.has(k):
			continue
		var e := ends(str(k))
		var a: Vector2 = e[0]
		var s := ("back" if roundi(a.y) == z0 else "front") if e[2] else ("left" if roundi(a.x) == 0 else "right")
		if s == side:
			out[roundi(a.x if e[2] else a.y)] = str(h[k])
	return out


# --- paying ----------------------------------------------------------------------------------------

func _can_pay(parts: Dictionary, fee: int) -> bool:
	var coins := fee
	var wood := 0
	for p in parts:
		coins += int(parts[p][0])
		wood += int(parts[p][1])
	return (wood > 0 and Game.count("wood") >= wood and Game.coins >= fee) or Game.coins >= coins


## Takes the parts' price, all in wood when she has enough for them all (the foundations' `fee` is
## coins either way), else all in coins. What each part was paid with ({part: [coins, wood]}), or
## {} if she can't pay.
func _pay(parts: Dictionary, fee: int) -> Dictionary:
	var coins := fee
	var wood := 0
	for p in parts:
		coins += int(parts[p][0])
		wood += int(parts[p][1])
	var out := {}
	if wood > 0 and Game.count("wood") >= wood and Game.coins >= fee:
		if fee > 0 and not Game.spend(fee):
			return {}
		Game.take_item("wood", wood)
		for p in parts:
			out[p] = [0, int(parts[p][1])]
		return out
	if not Game.spend(coins):
		return {}
	for p in parts:
		out[p] = [int(parts[p][0]), 0]
	return out


## What a part on edge k was paid with: from the record, or for walls built before it was kept,
## coins at today's price.
func _paid_part(k: String, part: String, kind: String) -> Array:
	var rec: Dictionary = (Game.flag("built_paid", {}) as Dictionary).get(k, {})
	if rec.has(part):
		return [int(rec[part][0]), int(rec[part][1])]
	return [int(wall_cost()[0]) if part == "wall" else int(opening_cost(kind)[0]), 0]


func _set_paid(k: String, part: String, v: Variant) -> void:
	var all: Dictionary = (Game.flag("built_paid", {}) as Dictionary).duplicate(true)
	var rec: Dictionary = all.get(k, {})
	if v == null:
		rec.erase(part)
	else:
		rec[part] = [int(v[0]), int(v[1])]
	if rec.is_empty():
		all.erase(k)
	else:
		all[k] = rec
	if all.is_empty():
		Game.flags.erase("built_paid")
	else:
		Game.set_flag("built_paid", all)


## Gives back the refund share of what was paid, in the same: [coins, wood] given.
func _refund(paid: Array) -> Array:
	var share := float(econ().get("refund", 0.5))
	var c := int(round(int(paid[0]) * share))
	var w := int(floor(int(paid[1]) * share))
	Game.coins += c
	if w > 0:
		Game.add_item("wood", w)
	return [c, w]


func _cost_text(parts: Dictionary, fee: int) -> String:
	var coins := fee
	var wood := 0
	for p in parts:
		coins += int(parts[p][0])
		wood += int(parts[p][1])
	if wood <= 0:
		return "%dc" % coins
	return "%dc or %d wood%s" % [coins, wood, " and %dc" % fee if fee > 0 else ""]


func _paid_text(paid: Dictionary, fee: int) -> String:
	var coins := fee
	var wood := 0
	for p in paid:
		coins += int(paid[p][0])
		wood += int(paid[p][1])
	if wood > 0:
		return "%d wood%s" % [wood, ", %dc" % coins if coins > 0 else ""]
	return "%dc" % coins


func _back_text(back: Array) -> String:
	var out: Array = []
	if int(back[0]) > 0:
		out.append("+%dc" % int(back[0]))
	if int(back[1]) > 0:
		out.append("+%d wood" % int(back[1]))
	return ", ".join(out) if not out.is_empty() else "nothing"


## Rebuilds the house, its rooms and the walking grid after a change.
func refresh_world() -> void:
	compute()
	main._rebuild_house()
	main._rebuild_grid()
	if main.forage != null:
		main.forage.apply() # a plot she just bought is cleared
	if main.god != null:
		main.god.sync_built()


# --- doors -----------------------------------------------------------------------------------------

## A door or sliding doors in the gap from a to b (world, on the ground), hung under `tall` (the
## lintel's node, at the gap's middle) so they hide with the wall when it's cut down.
func hang_door(tall: Node3D, kind: String, a: Vector2, b: Vector2) -> void:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
	var clear := a.distance_to(b) - 0.16 # inside the jambs
	var pivot := Node3D.new()
	pivot.name = "Door" if kind == "hdoor" else "SlidingDoor"
	tall.add_child(pivot)
	pivot.rotation.y = 0.0 if horizontal else -PI * 0.5 # a model laid along +X turned to lie along the wall
	var holder := Node3D.new()
	pivot.add_child(holder)
	var part: Node3D = pivot
	if kind == "hdoor":
		pivot.position = -along * clear * 0.5 # hinged on the gap's low end
		holder.scale = Vector3(clear / DOOR_W, 1, 1)
		if ResourceLoader.exists(DOOR_GLB):
			holder.add_child((load(DOOR_GLB) as PackedScene).instantiate())
		else:
			Catalog.box(holder, Vector3(DOOR_W, 2.02, 0.04), Vector3(DOOR_W * 0.5, 1.01, 0), Catalog.WOOD)
	else:
		holder.scale = Vector3(clear / SLIDE_W, 1, 1)
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
			var g := Catalog.box(holder, Vector3(SLIDE_W, 2.0, 0.03), Vector3(0, 1.0, 0), Color(0.7, 0.85, 0.95))
			g.material_override = Catalog.window_glass()
	var mid := (a + b) * 0.5
	doors.append({"node": pivot, "part": part, "kind": kind, "at": mid, "rot0": pivot.rotation.y, "x0": part.position.x, "open": 0.0})


## Doors swing open and sliding doors slide as Nora or the dog comes up to one, and shut behind.
func _process(delta: float) -> void:
	if doors.is_empty() or main == null:
		return
	var who: Array = []
	if main.player != null:
		who.append((main.player as Node3D).position)
	if main.dog != null and is_instance_valid(main.dog):
		who.append((main.dog as Node3D).position)
	for d in doors:
		var node: Node3D = d["node"]
		if not is_instance_valid(node):
			continue
		var at: Vector2 = d["at"]
		var near := false
		for p in who:
			if Vector2((p as Vector3).x, (p as Vector3).z).distance_to(at) < 1.5:
				near = true
		d["open"] = move_toward(float(d["open"]), 1.0 if near else 0.0, delta * 2.2)
		var s := smoothstep(0.0, 1.0, float(d["open"]))
		if str(d["kind"]) == "hdoor":
			node.rotation.y = float(d["rot0"]) - deg_to_rad(95.0) * s
		elif is_instance_valid(d["part"]):
			(d["part"] as Node3D).position.x = float(d["x0"]) - SLIDE_W * 0.47 * s


# --- floors ----------------------------------------------------------------------------------------

func floors() -> Dictionary:
	return Game.flag("floors", {})


static func cell_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func floor_label(kind: String) -> String:
	return str(FLOOR_LABELS.get(kind, kind))


## [coins, wood] for one 2 m cell of a floor kind ([0, 0] for the planks).
static func floor_cost(kind: String) -> Array:
	var f: Dictionary = econ().get("floors", {}).get(kind, {})
	return [int(f.get("coins", 0)), int(f.get("wood", 0))]


## The room the cell under q belongs to: a room she built, or her house. [] outside.
func floor_cells_at(q: Vector2) -> Array:
	var c := cell_of(q)
	if room_cells.has(c):
		return (rooms[int(room_cells[c])]["cells"] as Array).duplicate()
	var hc := house_cells()
	if hc.has(c):
		return hc.keys()
	return []


func _floor_now(c: Vector2i) -> String:
	return str(floors().get(cell_key(c), "planks"))


## Whether `kind` can go down over these cells: {"ok", "why", "n" (cells it changes), "parts"
## (what they cost), "back" ([coins, wood] the floors taken up give back)}.
func floor_check(cells: Array, kind: String) -> Dictionary:
	var out := {"ok": false, "why": "", "n": 0, "parts": {}, "back": [0, 0]}
	if cells.is_empty():
		out["why"] = "Floors go down inside your house or a room you've built."
		return out
	var n := 0
	var back := [0, 0]
	var share := float(econ().get("refund", 0.5))
	var paid: Dictionary = Game.flag("floors_paid", {})
	for c in cells:
		var now := _floor_now(c)
		if now == kind:
			continue
		n += 1
		if now != "planks":
			var p: Array = paid.get(cell_key(c), floor_cost(now))
			back = [back[0] + int(round(int(p[0]) * share)), back[1] + int(floor(int(p[1]) * share))]
	out["n"] = n
	out["back"] = back
	if n == 0:
		out["why"] = "This room's floor is %s already." % floor_label(kind).to_lower()
		return out
	var one := floor_cost(kind)
	out["parts"] = {"floor": [int(one[0]) * n, int(one[1]) * n]}
	if kind != "planks" and not _can_pay(out["parts"], 0):
		out["why"] = "You need %s for %d m² of %s." % [_cost_text(out["parts"], 0), n * STEP * STEP, floor_label(kind).to_lower()]
		return out
	out["ok"] = true
	return out


## Lays `kind` over the cells (a room), paying for each cell it changes; what it covers comes up
## for half back in what paid for it. "planks" just takes them up.
func lay_floor(cells: Array, kind: String) -> bool:
	var chk := floor_check(cells, kind)
	if not bool(chk["ok"]):
		main.hud.show_toast(str(chk["why"]))
		return false
	var each := [0, 0]
	if kind != "planks":
		var got := _pay(chk["parts"], 0)
		if got.is_empty():
			main.hud.show_toast(str(chk["why"]) if str(chk["why"]) != "" else "You can't afford that.")
			return false
		var one := floor_cost(kind)
		each = [int(one[0]), 0] if int(got["floor"][0]) > 0 else [0, int(one[1])]
	var fl: Dictionary = floors().duplicate()
	var paid: Dictionary = (Game.flag("floors_paid", {}) as Dictionary).duplicate()
	var back := [0, 0]
	for c in cells:
		var k := cell_key(c)
		var now := _floor_now(c)
		if now == kind:
			continue
		if now != "planks":
			var b := _refund(paid.get(k, floor_cost(now)))
			back = [back[0] + b[0], back[1] + b[1]]
		if kind == "planks":
			fl.erase(k)
			paid.erase(k)
		else:
			fl[k] = kind
			paid[k] = each
	for pair in [["floors", fl], ["floors_paid", paid]]:
		if (pair[1] as Dictionary).is_empty():
			Game.flags.erase(pair[0])
		else:
			Game.set_flag(pair[0], pair[1])
	main._rebuild_house()
	var got_back := "" if back == [0, 0] else " (%s for the old floor)" % _back_text(back)
	if kind == "planks":
		main.hud.show_toast("The floor's up: plank boards again%s." % got_back)
	else:
		main.hud.show_toast("%s laid: %d m²%s." % [floor_label(kind), int(chk["n"]) * STEP * STEP, got_back])
	return true


## The laid floors, a tile over the planks per cell that's still indoors (a room opened up keeps
## its floor in the save and gets it back when it's closed again).
func _draw_floors() -> void:
	var hc := house_cells()
	var fl := floors()
	for k in fl:
		var p := str(k).split(",")
		var c := Vector2i(int(p[0]), int(p[1]))
		if not (hc.has(c) or room_cells.has(c)):
			continue
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(STEP, 0.012, STEP)
		mi.mesh = m
		mi.position = Vector3(c.x * STEP + STEP * 0.5, FLOOR_Y - 0.006, c.y * STEP + STEP * 0.5)
		mi.material_override = floor_mat(str(fl[k]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LaidFloor"
		mi.set_meta("floor", str(fl[k]))
		main.house_root.add_child(mi)


## The floor's material: Marcus's house's tiles, boards and carpets (split_house.gd), laid in world
## space so neighbouring cells meet without a seam.
func floor_mat(kind: String) -> StandardMaterial3D:
	if _floor_mats.has(kind):
		return _floor_mats[kind]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.roughness = 0.95
	var img: Image = null
	var carpet := {"carpet_grey": Color("#9a9a97"), "carpet_blue": Color("#6a8cb6"), "carpet_cream": Color("#f0e6cf")}
	match kind:
		"tile_beige":
			img = SplitHouse._tiles(Color("#d8c7a4"), Color("#b9a988"), 4)
			m.uv1_scale = Vector3.ONE / 1.2
			m.roughness = 0.45
		"tile_black":
			img = SplitHouse._tiles(Color("#1d1d20"), Color("#47474a"), 4)
			m.uv1_scale = Vector3.ONE / 1.2
			m.roughness = 0.3
		"tile_white":
			img = SplitHouse._tiles(Color("#eceae4"), Color("#c3c0b8"), 8)
			m.uv1_scale = Vector3.ONE / 1.2
			m.roughness = 0.35
		"wood_oak":
			img = SplitHouse._boards(Color("#b98a55"), 6)
			m.roughness = 0.55
		_:
			var tint: Color = carpet.get(kind, Color("#9a9a97"))
			var base := "res://assets/textures/carpet/carpet_pile"
			if ResourceLoader.exists(base + ".png"):
				m.albedo_texture = load(base + ".png")
				m.albedo_color = tint
				if ResourceLoader.exists(base + "_n.png"):
					m.normal_enabled = true
					m.normal_texture = load(base + "_n.png")
					m.normal_scale = 0.8
				m.uv1_scale = Vector3.ONE / 0.6
				m.roughness = 0.97
			else:
				img = SplitHouse._noise(tint, 0.1, 5)
	if img != null:
		img.generate_mipmaps()
		m.albedo_texture = ImageTexture.create_from_image(img)
	_floor_mats[kind] = m
	return m


func _show_floor_ghost(cells: Array, mat: String) -> void:
	if _floor_ghost == null:
		_floor_ghost = Node3D.new()
		main.add_child(_floor_ghost)
	for ch in _floor_ghost.get_children():
		ch.queue_free()
	for c in cells:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(STEP - 0.06, 0.03, STEP - 0.06)
		mi.mesh = m
		mi.position = Vector3(c.x * STEP + STEP * 0.5, FLOOR_Y + 0.02, c.y * STEP + STEP * 0.5)
		mi.material_override = _mats[mat]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_floor_ghost.add_child(mi)
	_floor_ghost.visible = not cells.is_empty()


func set_floor_kind(kind: String) -> void:
	floor_kind = kind
	hover_cells = []
	if main.hud.floor_pick != null and main.hud.floor_pick.selected != FLOORS.find(kind):
		main.hud.floor_pick.select(FLOORS.find(kind))


func _hover_floor(g: Variant) -> void:
	_ghost.visible = false
	hover = ""
	if g == null:
		if _floor_ghost != null:
			_floor_ghost.visible = false
		return
	var q := Vector2((g as Vector3).x, (g as Vector3).z)
	var cells := floor_cells_at(q)
	var chk := floor_check(cells, floor_kind)
	hover_ok = bool(chk["ok"])
	var mat := "bad"
	if not hover_ok:
		hover_note = str(chk["why"])
	elif floor_kind == "planks":
		hover_note = "Click to take this room's floor up (%s back)." % _back_text(chk["back"])
		mat = "down"
	else:
		hover_note = "%s here: %d m², %s%s" % [floor_label(floor_kind), int(chk["n"]) * STEP * STEP, _cost_text(chk["parts"], 0),
			" (the old floor comes up, %s)" % _back_text(chk["back"]) if chk["back"] != [0, 0] else ""]
		mat = "ok"
	if cells != hover_cells or _floor_ghost == null or not _floor_ghost.visible:
		hover_cells = cells
		_show_floor_ghost(cells, mat)
	elif _floor_ghost.get_child_count() > 0:
		for ch in _floor_ghost.get_children():
			(ch as MeshInstance3D).material_override = _mats[mat]
	main.hud.set_wall_note(hover_note)


# --- the tool in build mode -------------------------------------------------------------------

func set_tool(t: String) -> void:
	tool = t
	hover = ""
	hover_cells = []
	if _ghost != null:
		_ghost.visible = false
	if _floor_ghost != null:
		_floor_ghost.visible = false
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
	if tool == "floor":
		_hover_floor(g)
		return
	if _floor_ghost != null:
		_floor_ghost.visible = false
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
	var mat := "bad"
	if tool == "wall" and edges().has(hover):
		var kind := str(edges()[hover])
		var back := [0, 0]
		for part in ["wall", "open"]:
			if part == "open" and kind == "wall":
				continue
			var p := _paid_part(hover, part, kind)
			var share := float(econ().get("refund", 0.5))
			back = [back[0] + int(round(int(p[0]) * share)), back[1] + int(floor(int(p[1]) * share))]
		hover_ok = false
		hover_note = "Click to take this wall down (%s back)." % _back_text(back)
		mat = "down"
	elif tool != "wall" and (edges().has(hover) or house_edges().has(hover)):
		var c := opening_check(hover, tool)
		hover_ok = bool(c["ok"])
		if not hover_ok:
			hover_note = str(c["why"])
		elif bool(c["undo"]):
			var p := _paid_part(hover, "open", tool)
			var share := float(econ().get("refund", 0.5))
			hover_note = "Click to take the %s out (%s back)." % [label(tool).to_lower(), _back_text([int(round(int(p[0]) * share)), int(floor(int(p[1]) * share))])]
			mat = "down"
		else:
			hover_note = "%s here: %s%s" % [label(tool), _cost_text({"open": opening_cost(tool)}, 0), " (the %s comes out, half back)" % label(str(c["now"])).to_lower() if str(c["now"]) != "wall" else ""]
			mat = "ok"
	else:
		var c := check(hover, tool)
		hover_ok = c["ok"]
		var what := "Wall" if tool == "wall" else "Wall with a %s" % label(tool).to_lower()
		hover_note = ("%s here: %s%s" % [what, _cost_text(_parts(tool), int(c["fee"])), " (with %dc for the foundations)" % int(c["fee"]) if int(c["fee"]) > 0 else ""]) if hover_ok else str(c["why"])
		mat = "ok" if hover_ok else "bad"
	_ghost.material_override = _mats[mat]
	main.hud.set_wall_note(hover_note)


## A click in build mode with a wall tool: the Wall tool builds on the edge or takes one of her walls
## down; the others put their opening in a standing wall (hers or the house's), take it out again,
## or build a new wall with it in.
func click(g: Variant) -> void:
	if g == null:
		return
	hover_at(g)
	if tool == "floor":
		lay_floor(floor_cells_at(Vector2((g as Vector3).x, (g as Vector3).z)), floor_kind)
		hover_cells = []
	elif tool == "wall" and edges().has(hover):
		remove(hover)
	elif tool != "wall" and (edges().has(hover) or house_edges().has(hover)):
		set_opening(hover, tool)
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
