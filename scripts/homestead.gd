extends Node
## Act 1's farm work (Alex's design, 2026-11-12). A new game starts Nora at Gran's farm with no
## pen, no sheep and no money. Gran's note (on the table in the house) leaves her 100 coins and
## asks for a little rent in the tin each week. Two stray sheep graze past the pond; to keep them
## she buys wood from Steve at Builder's Delight, builds a pen panel by panel (the fence builder, F) and
## crafts a gate (G), then herds them in. Sheep shy away from whoever is herding them: Nora for
## now. Alex is making the dog in a separate chat; it herds by joining `herders`.
##
## Story events fired here (data/scenes/act1.scene): "yarn_bought" (her first yarn from Rosa),
## "wood_bought" (her first wood from Steve), "pen_built" (a closed pen with a gate; the dog's cue),
## "sheep_penned" (both strays inside).
##
## What survives a save lives in Game.flags: "story_farm", "fences" (edge key -> "fence"/"gate"),
## "strays" ([[x, z], ...] still loose), "rent_due" (the day rent is next added), "rent_owed".
## The autotest's sandbox farm (the old pen and three sheep) is put back by reset_sandbox().

const Catalog = preload("res://scripts/catalog.gd")
const World = preload("res://scripts/world.gd")
const Sheep = preload("res://scripts/sheep.gd")
const Data = preload("res://scripts/data.gd")
const PlayUi = preload("res://scripts/play_ui.gd")

const STRAYS_AT := Vector3(13.5, 0, -14.0) # where the two strays graze, east of the pond
const HERD_RADIUS := 2.6 # sheep move off when Nora is this close
const FLEE_SPEED := 1.7
const NOTE_ITEM := "gran_note"
## The note Gran left on the table. A DRAFT for Alex.
const NOTE_TEXT := """My darling Nora,

I have missed you every single day since you moved away. The kettle still boils for two out of habit, and I let it.

The house is yours now, if you'll have it: the third stair that creaks, the roses that sulk every June, the chair by the fire that still remembers the shape of me. Keep it warm for me.

Put a little in the tin each week, for the house. Not because it needs the money. Because a home you pay into is a home you stay in.

There's a hundred coins under the lid to start you off. Go and see Rosa at the Yarn Barn for some good yarn, and make something with your hands. It always helped me. It will help you.

Whatever happened out there, love, it stays out there. In here it's just you, and the kettle, and me in every cup.

All my love, always,
Gran"""

var main: Node
var ui: PlayUi
var fences := {} # "x,z,h" (from x,z to x+1,z) or "x,z,v" (to x,z+1) -> "fence" or "gate"
var pen_cells := {} # Vector2i -> true: the 1 m cells inside the pen ({} = no pen yet)
var pen_inner := Rect2() # the largest rectangle of the pen's cells: where penned sheep graze
var strays: Array = [] # the loose sheep, not yet penned
var herders: Array = [] # what the sheep move away from (Nora; the dog joins when it's in)
var building := false # the fence builder is on
var tool := "fence" # what a click puts down: "fence" or "gate"
var tin: Node3D # Gran's tin on the table: pay the rent
var note_prop: Node3D
var _fence_root: Node3D
var _blocks: Array = [] # Rect2s this file added to main.grid_blockers
var _ghost: Node3D
var _hover = null # the edge key under the mouse in the builder
var _hidden_pen := false
var _sandbox_pen := Rect2()
var _last_sel := ""
var _save_t := 0.0
var _settle_t := 0.0
var _econ := {}
var _ui_sig := ""


func _ready() -> void:
	_econ = Data.load_json("economy").get("story", {})
	_sandbox_pen = main.pen_rect
	_fence_root = Node3D.new()
	_fence_root.name = "Fences"
	main.add_child(_fence_root)
	herders = [main.player]
	ui = PlayUi.new()
	ui.home = self
	add_child(ui)
	_build_ghost()
	Game.day_started.connect(_on_day)
	# villagers with a round to walk (the postman)
	for d in Data.villagers():
		if d.has("route"):
			var v = main._villager(str(d["id"]))
			if v:
				v.route = d["route"]
				v._next_stop()


func econ(key: String, default: int) -> int:
	return int(_econ.get(key, default))


func story_farm() -> bool:
	return Game.flag("story_farm") == true


func has_pen() -> bool:
	return not pen_cells.is_empty()


# --- the story farm --------------------------------------------------------------------

## A new game's Act 1: Gran's farm as Nora finds it. Called before the opening scene plays.
func start_story() -> void:
	Game.set_flag("story_farm")
	Game.coins = 0
	for id in ["wool", "turnip", "pumpkin", "sweater"]:
		Game.inv.erase(id)
	Game.sheep_count = 0
	Game.flags.erase("fences")
	Game.flags.erase("strays")
	apply()


## Puts the story farm in place: after start_story, or after loading a game that has it.
func apply() -> void:
	if not story_farm():
		return
	if not _hidden_pen and World.pen and is_instance_valid(World.pen):
		World.pen.visible = false
		for r in World.pen_blocks:
			main.grid_blockers.erase(r)
			main.place_blockers.erase(r)
		_hidden_pen = true
	while main.sheep_list.size() > Game.sheep_count:
		var s = main.sheep_list.pop_back()
		s.queue_free()
	fences = {}
	var saved = Game.flag("fences", {})
	if saved is Dictionary:
		for k in saved:
			fences[str(k)] = str(saved[k])
	_rebuild_fences()
	for s in main.sheep_list:
		_put_in_pen(s)
	for s in strays:
		if is_instance_valid(s):
			s.queue_free()
	strays.clear()
	var loose = Game.flag("strays", [])
	if loose is Array:
		for p in loose:
			_add_stray(Vector3(float(p[0]), 0, float(p[1])))
	_place_note_and_tin()
	ui.refresh()


## The autotest's sandbox farm again: the old pen, three sheep, no fences or strays.
func reset_sandbox() -> void:
	Game.flags.erase("story_farm")
	Game.flags.erase("fences")
	Game.flags.erase("strays")
	set_builder(false)
	fences = {}
	_rebuild_fences()
	for s in strays:
		if is_instance_valid(s):
			s.queue_free()
	strays.clear()
	if _hidden_pen and World.pen and is_instance_valid(World.pen):
		World.pen.visible = true
		for r in World.pen_blocks:
			main.grid_blockers.append(r)
			main.place_blockers.append(r)
		_hidden_pen = false
	main.pen_rect = _sandbox_pen
	Game.sheep_count = maxi(Game.sheep_count, Game.START_SHEEP)
	for s in main.sheep_list:
		s.pen = Rect2(main.pen_rect.position + Vector2(0.7, 0.7), main.pen_rect.size - Vector2(1.4, 1.4))
		s.place(Vector3(main.pen_rect.get_center().x, 0, main.pen_rect.get_center().y), false)
	while main.sheep_list.size() < Game.sheep_count:
		main._add_sheep()
	for n in [note_prop, tin]:
		if n and is_instance_valid(n):
			n.queue_free()
	note_prop = null
	tin = null
	main._rebuild_grid()
	ui.refresh()


# --- fences ----------------------------------------------------------------------------

static func edge_key(x: int, z: int, horizontal: bool) -> String:
	return "%d,%d,%s" % [x, z, "h" if horizontal else "v"]


static func edge_ends(key: String) -> Array:
	var p := key.split(",")
	var a := Vector2(float(p[0]), float(p[1]))
	return [a, a + (Vector2(1, 0) if p[2] == "h" else Vector2(0, 1))]


## The grid edge nearest a point on the ground.
static func nearest_edge(g: Vector3) -> String:
	var dh := absf(g.z - roundf(g.z)) # to the nearest east-west line
	var dv := absf(g.x - roundf(g.x))
	if dh <= dv:
		return edge_key(floori(g.x), roundi(g.z), true)
	return edge_key(roundi(g.x), floori(g.z), false)


## Why a panel can't go on this edge ("" if it can).
func edge_problem(key: String) -> String:
	var ends := edge_ends(key)
	var mid: Vector2 = (ends[0] + ends[1]) * 0.5
	if not main.LOT.grow(-1.0).has_point(mid):
		return "That's off the farm."
	if main.house_rect().grow(0.6).has_point(mid):
		return "Too close to the house."
	for r in main.grid_blockers:
		if _blocks.has(r):
			continue
		if (r as Rect2).grow(0.15).has_point(mid):
			return "Something's in the way."
	for f in main.furniture:
		if not f.is_flat() and (f.footprint() as Rect2).grow(0.1).has_point(mid):
			return "Something's in the way."
	for p in main.plots:
		if Rect2(p.position.x - 0.6, p.position.z - 0.6, 1.2, 1.2).has_point(mid):
			return "That's a vegetable bed."
	return ""


## Puts a fence panel (1 wood) or a gate (a crafted gate) on an edge. Returns what went wrong, or "".
func place(key: String, kind: String) -> String:
	if fences.has(key):
		return "There's already a %s there." % fences[key]
	var why := edge_problem(key)
	if why != "":
		return why
	if kind == "gate":
		if not Game.take_item("gate"):
			return "You need a gate. Craft one (G): it takes 2 wood."
	elif not Game.take_item("wood", econ("fence_wood", 1)):
		return "You need wood. Steve at Builder's Delight sells it."
	fences[key] = kind
	_changed()
	return ""


## Takes a panel or gate back up, and gives back what it cost.
func remove(key: String) -> bool:
	if not fences.has(key):
		return false
	Game.add_item("gate" if fences[key] == "gate" else "wood", 1 if fences[key] == "gate" else econ("fence_wood", 1))
	fences.erase(key)
	_changed()
	return true


func _changed() -> void:
	Game.set_flag("fences", fences.duplicate())
	_rebuild_fences()
	ui.refresh()
	if has_pen() and Game.flag("act1_wood") == true and Game.flag("pen_done") != true and not main.story.is_playing():
		Game.set_flag("pen_done")
		main.hud.show_toast("The pen is closed, with a gate. That'll hold them.")
		set_builder(false)
		main.story.trigger("event", "pen_built")


func _rebuild_fences() -> void:
	for c in _fence_root.get_children():
		c.queue_free()
	for r in _blocks:
		main.grid_blockers.erase(r)
		main.place_blockers.erase(r)
	_blocks.clear()
	var posts := {}
	for key in fences:
		var ends := edge_ends(key)
		var a: Vector2 = ends[0]
		var b: Vector2 = ends[1]
		var yaw := atan2(-(b.y - a.y), b.x - a.x)
		for p in [a, b]:
			var pk := Vector2i(roundi(p.x), roundi(p.y))
			if not posts.has(pk):
				posts[pk] = true
				var post := Catalog.model(World.PEN_POST, _fence_root)
				if post:
					post.position = Vector3(p.x, 0, p.y)
					post.rotation.y = yaw
				else:
					Catalog.box(_fence_root, Vector3(0.12, 0.9, 0.12), Vector3(p.x, 0.45, p.y), Color(0.5, 0.38, 0.25))
		if fences[key] == "gate":
			_fence_root.add_child(_gate(a, yaw))
			continue
		var rails := Catalog.model(World.PEN_RAILS, _fence_root)
		if rails:
			rails.position = Vector3(a.x, 0, a.y)
			rails.rotation.y = yaw
		else:
			var mid := (a + b) * 0.5
			for y in [0.35, 0.7]:
				Catalog.box(_fence_root, Vector3(1.0, 0.07, 0.05), Vector3(mid.x, y, mid.y), Color(0.62, 0.48, 0.32), Vector3(0, rad_to_deg(yaw), 0))
		# a thin box along the panel, short of the posts: the path grid grows it by 0.2 m, which closes
		# the gap to the next panel but leaves a gate's metre open to walk through
		var along := (b - a).abs()
		var r := Rect2(minf(a.x, b.x) + along.x * 0.25 - 0.08 * along.y, minf(a.y, b.y) + along.y * 0.25 - 0.08 * along.x,
			along.x * 0.5 + 0.16 * along.y, along.y * 0.5 + 0.16 * along.x)
		_blocks.append(r)
		main.grid_blockers.append(r)
		main.place_blockers.append(r)
	main._rebuild_grid()
	_find_pen()


## A plank gate on its hinge post: three boards and a brace. (Boxes until the farm props have a gate model.)
func _gate(a: Vector2, yaw: float) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = "Gate"
	hinge.position = Vector3(a.x, 0, a.y)
	hinge.rotation.y = yaw
	var wood := Color(0.6, 0.45, 0.3)
	for y in [0.25, 0.5, 0.75]:
		Catalog.box(hinge, Vector3(0.88, 0.09, 0.04), Vector3(0.5, y, 0), wood)
	for x in [0.1, 0.9]:
		Catalog.box(hinge, Vector3(0.07, 0.72, 0.05), Vector3(x, 0.5, 0), wood.darkened(0.15))
	Catalog.box(hinge, Vector3(0.95, 0.07, 0.035), Vector3(0.5, 0.5, 0.03), wood.darkened(0.1), Vector3(0, 0, 32))
	return hinge


## Which cells the fences close in. The pen is the biggest closed-in patch of at least four cells
## with a gate in its fence.
func _find_pen() -> void:
	pen_cells = {}
	pen_inner = Rect2()
	if fences.is_empty():
		_after_pen_change()
		return
	var lot: Rect2 = main.LOT
	var x0 := floori(lot.position.x)
	var z0 := floori(lot.position.y)
	var w := ceili(lot.size.x)
	var h := ceili(lot.size.y)
	var outside := {}
	var todo: Array = []
	for i in w:
		for j in h:
			if i == 0 or j == 0 or i == w - 1 or j == h - 1:
				outside[Vector2i(i, j)] = true
				todo.append(Vector2i(i, j))
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for n in _open_neighbours(c, x0, z0, w, h):
			if not outside.has(n):
				outside[n] = true
				todo.append(n)
	var seen := {}
	var best := {}
	for i in w:
		for j in h:
			var c := Vector2i(i, j)
			if outside.has(c) or seen.has(c):
				continue
			var comp := {}
			var stack := [c]
			seen[c] = true
			var gated := false
			while not stack.is_empty():
				var q: Vector2i = stack.pop_back()
				comp[Vector2i(q.x + x0, q.y + z0)] = true
				for n in _open_neighbours(q, x0, z0, w, h):
					if not seen.has(n) and not outside.has(n):
						seen[n] = true
						stack.append(n)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if fences.get(_edge_between(q, q + d, x0, z0), "") == "gate":
						gated = true
			if gated and comp.size() >= 4 and comp.size() > best.size():
				best = comp
	pen_cells = best
	pen_inner = _largest_rect(best)
	_after_pen_change()


func _after_pen_change() -> void:
	if has_pen():
		main.pen_rect = pen_inner.grow(0.6)
		for s in main.sheep_list:
			s.pen = pen_inner
	elif story_farm():
		main.pen_rect = Rect2(-100, -100, 1, 1)


## The edge between two neighbouring cells (in lot cell coordinates).
static func _edge_between(a: Vector2i, b: Vector2i, x0: int, z0: int) -> String:
	if a.y == b.y:
		return edge_key(maxi(a.x, b.x) + x0, a.y + z0, false)
	return edge_key(a.x + x0, maxi(a.y, b.y) + z0, true)


func _open_neighbours(c: Vector2i, x0: int, z0: int, w: int, h: int) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
			continue
		if fences.has(_edge_between(c, n, x0, z0)):
			continue # fences and gates both close a pen in
		out.append(n)
	return out


## The biggest rectangle made only of the pen's cells, inset from the fences.
static func _largest_rect(cells: Dictionary) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var best := Rect2i()
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			for x1 in range(x, hi.x + 1):
				for z1 in range(z, hi.y + 1):
					var area := (x1 - x + 1) * (z1 - z + 1)
					if area <= best.get_area():
						continue
					var full := true
					for i in range(x, x1 + 1):
						for j in range(z, z1 + 1):
							if not cells.has(Vector2i(i, j)):
								full = false
								break
						if not full:
							break
					if full:
						best = Rect2i(x, z, x1 - x + 1, z1 - z + 1)
	return Rect2(Vector2(best.position) + Vector2(0.45, 0.45), Vector2(best.size) - Vector2(0.9, 0.9))


func in_pen(p: Vector3) -> bool:
	return pen_cells.has(Vector2i(floori(p.x), floori(p.z)))


func _put_in_pen(s) -> void:
	if not has_pen():
		return
	s.pen = pen_inner
	if not pen_inner.grow(0.3).has_point(Vector2(s.position.x, s.position.z)):
		s.place(Vector3(randf_range(pen_inner.position.x, pen_inner.end.x), 0, randf_range(pen_inner.position.y, pen_inner.end.y)), false)


# --- the fence builder -----------------------------------------------------------------

func set_builder(on: bool) -> void:
	if on and (main.story.is_playing() or not story_farm()):
		return
	building = on
	_ghost.visible = false
	_hover = null
	if on:
		main.hud.show_toast("Pen builder: click to put a panel down (1 wood), right-click to take one up. F or Esc when you're done.")
		if tool == "gate" and Game.count("gate") == 0:
			tool = "fence"
	ui.refresh()


func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.visible = false
	main.add_child(_ghost)
	var bar := Catalog.box(_ghost, Vector3(1.0, 0.75, 0.08), Vector3(0.5, 0.42, 0), Color(0.6, 0.95, 0.5))
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.95, 0.5, 0.45)
	bar.material_override = m
	_ghost.set_meta("bar", bar)


func _update_ghost(mpos: Vector2) -> void:
	var g = main._ground_point(mpos)
	if g == null:
		_ghost.visible = false
		_hover = null
		return
	_hover = nearest_edge(g)
	var ends := edge_ends(_hover)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	_ghost.position = Vector3(a.x, 0, a.y)
	_ghost.rotation.y = atan2(-(b.y - a.y), b.x - a.x)
	_ghost.visible = true
	var ok: bool = fences.has(_hover) or edge_problem(_hover) == ""
	var col := Color(0.6, 0.95, 0.5, 0.45) if ok else Color(0.95, 0.4, 0.35, 0.45)
	if fences.has(_hover):
		col = Color(0.95, 0.8, 0.4, 0.45) # right-click takes this one up
	((_ghost.get_meta("bar") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = col


func _unhandled_input(e: InputEvent) -> void:
	if main.story.is_playing() or main.sleeping or main.title_on:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var kc: Key = e.keycode if e.keycode != KEY_NONE else e.physical_keycode
		if main._autotest_dir != "" and not e.has_meta("ke_test"):
			return
		match kc:
			KEY_F:
				if story_farm() and Game.flag("act1_wood") == true:
					set_builder(not building)
					get_viewport().set_input_as_handled()
			KEY_G:
				if story_farm():
					ui.toggle_craft()
					get_viewport().set_input_as_handled()
			KEY_T:
				if building:
					tool = "gate" if tool == "fence" else "fence"
					ui.refresh()
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if building:
					set_builder(false)
					get_viewport().set_input_as_handled()
				elif ui.is_open():
					ui.close_all()
					get_viewport().set_input_as_handled()
		return
	if not building:
		return
	if main._autotest_dir != "" and e is InputEventMouse:
		return
	if e is InputEventMouseMotion:
		_update_ghost((e as InputEventMouseMotion).position)
		if (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and _hover != null and not fences.has(_hover):
			place(_hover, tool) # drag to lay a run of panels
	elif e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_update_ghost(mb.position)
			if _hover != null:
				var why := place(_hover, tool)
				if why != "" and not fences.has(_hover):
					main.hud.show_toast(why)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_update_ghost(mb.position)
			if _hover != null:
				remove(_hover)
			get_viewport().set_input_as_handled()


# --- crafting --------------------------------------------------------------------------

func recipes() -> Array:
	return Data.load_json("recipes").get("recipes", [])


func can_craft(r: Dictionary) -> bool:
	var needs: Dictionary = r.get("needs", {})
	for id in needs:
		if Game.count(str(id)) < int(needs[id]):
			return false
	return true


func craft(id: String) -> bool:
	for r in recipes():
		if str(r["id"]) == id and can_craft(r):
			var needs: Dictionary = r["needs"]
			for item in needs:
				Game.take_item(str(item), int(needs[item]))
			Game.add_item(id)
			main.hud.show_toast("Made: %s" % str(r["name"]))
			if main.audio:
				main.audio.play("journal", -10.0)
			ui.refresh()
			return true
	return false


# --- the strays and herding ------------------------------------------------------------

## Two strays come to graze east of the pond (@sheep strays in the story).
func spawn_strays(n := 2) -> void:
	for i in n:
		_add_stray(STRAYS_AT + Vector3(i * 1.6 - 0.8, 0, (i % 2) * 1.1))
	_save_strays()


func _add_stray(p: Vector3) -> void:
	var s = Sheep.new()
	s.position = p
	s.pen = Rect2(p.x - 1.5, p.z - 1.5, 3.0, 3.0)
	s.set_meta("stray", true)
	main.add_child(s)
	strays.append(s)


func _save_strays() -> void:
	var out := []
	for s in strays:
		if is_instance_valid(s):
			out.append([snappedf(s.position.x, 0.01), snappedf(s.position.z, 0.01)])
	Game.set_flag("strays", out)


func _process(delta: float) -> void:
	if not story_farm():
		return
	_herd(delta)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 2.0
		if not strays.is_empty():
			_save_strays()
	_settle_t -= delta
	if _settle_t <= 0.0:
		_settle_t = 1.0
		var sig := "%s|%s|%s|%s" % [building, Game.flag("act1_wood") == true, Game.count("wood") + Game.count("gate") > 0, main.story.is_playing()]
		if sig != _ui_sig: # the reminder buttons come and go with the story and her bag
			_ui_sig = sig
			ui.refresh()
		for s in main.sheep_list: # a sheep Rosa sold her stands in the pen, wherever it is
			if not s.housed and not s.heading_in and s.route.is_empty():
				_put_in_pen(s)
	# the note in her hand: open it to read
	var sel: String = main.hud.selected_item()
	if sel != _last_sel:
		_last_sel = sel
		if sel == NOTE_ITEM:
			ui.show_note(NOTE_TEXT)
	# the gate stands open while there are strays to bring in
	for g in _fence_root.get_children():
		if g.name.begins_with("Gate"):
			var want := -1.35 if not strays.is_empty() and has_pen() else 0.0
			var base: float = g.get_meta("yaw", g.rotation.y)
			g.set_meta("yaw", base)
			g.rotation.y = lerp_angle(g.rotation.y, base + want, 1.0 - exp(-delta * 3.0))


## Strays shy away from whoever is herding them; one that ends up inside the pen is home.
func _herd(_delta: float) -> void:
	for s in strays.duplicate():
		if not is_instance_valid(s):
			strays.erase(s)
			continue
		var push := Vector3.ZERO
		for h in herders:
			if h == null or not is_instance_valid(h):
				continue
			var r: float = h.scare_radius() if h.has_method("scare_radius") else HERD_RADIUS
			var away: Vector3 = s.position - h.position
			away.y = 0.0
			var d := away.length()
			if d < r and d > 0.01:
				push += away / d * (1.0 - d / r + 0.35)
		if push != Vector3.ZERO:
			var dir := _free_dir(s.position, push.normalized())
			if dir != Vector3.ZERO:
				s.flee = dir * FLEE_SPEED * clampf(push.length(), 0.5, 1.0)
				s.pen = Rect2(s.position.x - 0.7, s.position.z - 0.7, 1.4, 1.4) # she grazes where she's driven to
		if has_pen() and in_pen(s.position) and pen_inner.grow(0.4).has_point(Vector2(s.position.x, s.position.z)):
			_pen_stray(s)


## The way she can go: straight away, or turned a little either side if a fence, a wall or the
## edge of the farm is in the way. Gates are open while she's loose.
func _free_dir(from: Vector3, dir: Vector3) -> Vector3:
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var d := dir.rotated(Vector3.UP, turn)
		var to := from + d * 0.7
		if not main.LOT.grow(-0.5).has_point(Vector2(to.x, to.z)):
			continue
		if not main._walkable(main._cell(to)):
			continue
		if _crosses_fence(from, from + d * 0.35):
			continue
		return d
	return Vector3.ZERO


func _crosses_fence(a: Vector3, b: Vector3) -> bool:
	for key in fences:
		if fences[key] == "gate":
			continue
		var ends := edge_ends(key)
		if Geometry2D.segment_intersects_segment(Vector2(a.x, a.z), Vector2(b.x, b.z), ends[0], ends[1]) != null:
			return true
	return false


func _pen_stray(s) -> void:
	strays.erase(s)
	s.remove_meta("stray")
	s.flee = Vector3.ZERO
	s.pen = pen_inner
	main.sheep_list.append(s)
	Game.sheep_count += 1
	_save_strays()
	main.hud.show_toast("One's in! (%d in the pen)" % main.sheep_list.size())
	if strays.is_empty():
		Game.set_flag("act1_flock")
		main.story.trigger("event", "sheep_penned")


# --- rent and Gran's tin ---------------------------------------------------------------

## Rent starts once she's read Gran's note (@set rent_on in the story).
func start_rent() -> void:
	if Game.flag("rent_due", null) == null:
		Game.set_flag("rent_due", Game.day + econ("rent_days", 7))
		Game.set_flag("rent_owed", 0)
	ui.refresh()


func rent_owed() -> int:
	return int(Game.flag("rent_owed", 0))


func _on_day(day: int) -> void:
	if Game.flag("rent_on") != true:
		return
	var due := int(Game.flag("rent_due", day + econ("rent_days", 7)))
	if day >= due:
		Game.set_flag("rent_owed", rent_owed() + econ("rent", 20))
		Game.set_flag("rent_due", due + econ("rent_days", 7))
		main.hud.show_toast("Rent for Gran's house is due: %dc in her tin." % rent_owed())
	ui.refresh()


func pay_rent() -> bool:
	var owed := rent_owed()
	if owed <= 0 or not Game.spend(owed):
		return false
	Game.set_flag("rent_owed", 0)
	main.hud.show_toast("Paid %dc into Gran's tin." % owed)
	ui.refresh()
	return true


## The note and Gran's tin on the coffee table (wherever it stands now).
func _place_note_and_tin() -> void:
	var top := Vector3(4.0, 0.6, 3.0)
	for f in main.furniture:
		if f.item_id == "coffee_table":
			top = f.position + Vector3(0, 0.6, 0)
			break
	if tin == null or not is_instance_valid(tin):
		tin = _Pickable.new()
		tin.home = self
		tin.kind = "tin"
		main.add_child(tin)
		Catalog.cyl(tin, 0.09, 0.09, 0.13, Vector3(0, 0.065, 0), Color(0.36, 0.48, 0.55))
		Catalog.cyl(tin, 0.095, 0.095, 0.025, Vector3(0, 0.14, 0), Color(0.75, 0.62, 0.35))
		tin.add_hitbox(Vector3(0.5, 0.5, 0.5))
	tin.position = top + Vector3(0.28, 0.0, -0.18)
	var read: bool = Game.has_item(NOTE_ITEM) or Game.flag("read_gran_note") == true
	if read:
		if note_prop and is_instance_valid(note_prop):
			note_prop.queue_free()
		note_prop = null
	elif note_prop == null or not is_instance_valid(note_prop):
		note_prop = Node3D.new()
		main.add_child(note_prop)
		Catalog.box(note_prop, Vector3(0.22, 0.008, 0.16), Vector3(0, 0.005, 0), Color(0.97, 0.94, 0.86), Vector3(0, 12, 0))
		note_prop.position = top + Vector3(-0.1, 0.0, 0.05)


## The story has handed her the note: it leaves the table.
func take_note() -> void:
	Game.set_flag("read_gran_note")
	_place_note_and_tin()


## Something small in the world you can click (Gran's tin). main.gd asks it for its actions.
class _Pickable extends Node3D:
	var home
	var kind := ""

	func add_hitbox(size: Vector3) -> void:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position.y = size.y * 0.5
		body.add_child(cs)
		body.set_meta("target", self)
		add_child(body)

	func display_name() -> String:
		return "Gran's tin"

	func ke_actions() -> Array:
		var acts := []
		var owed: int = home.rent_owed()
		if Game.flag("rent_on") == true:
			if owed > 0:
				acts.append({"id": "pay_rent", "label": "Pay rent  (%dc)" % owed, "enabled": Game.coins >= owed})
			else:
				acts.append({"id": "noop", "label": "Rent's paid. Next %dc on day %d" % [home.econ("rent", 20), int(Game.flag("rent_due", 0))], "enabled": false})
		if Game.has_item(home.NOTE_ITEM):
			acts.append({"id": "read_note", "label": "Read Gran's note", "enabled": true})
		return acts

	func ke_action(id: String) -> void:
		match id:
			"pay_rent":
				home.pay_rent()
			"read_note":
				home.ui.show_note(home.NOTE_TEXT)
