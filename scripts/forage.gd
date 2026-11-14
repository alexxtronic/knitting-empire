extends Node
## Her axe and shears out in the world (Alex, 2026-11-14). The axe fells a tree for wood, and the
## shears trim a bush, a tuft, a clover patch or a flower clump down to the ground for leaves. What
## she cut grows back after a while (data/economy.json "forage").
##
## The trees and plants are the world editor's scenery (god_mode.gd's El). A cut one is hidden
## with `El.cut`, never `deleted`, so it never ends up in data/world_layout.json. What she has cut
## is kept in Game.flags["cut"] (key "kind@x,z" -> the day she cut it), so it saves with the game.

const Town = preload("res://scripts/town.gd")
const Data = preload("res://scripts/data.gd")

## The scenery the shears take, by the start of its kind's name (the tree kinds are the axe's).
const PLANTS := ["bush_", "flowers_", "tuft_", "clover"]

var main # main.gd
var _econ := {}


func _ready() -> void:
	_econ = Data.load_json("economy").get("forage", {})


func econ(key: String, fallback):
	return _econ.get(key, fallback)


## Where a thing stood when she cut it: its name in Game.flags["cut"].
static func key_of(el) -> String:
	return "%s@%.1f,%.1f" % [el.kind, el.xf.origin.x, el.xf.origin.z]


## The plant under the mouse (the nearest the ray hits), or null.
func plant_at(mpos: Vector2):
	for prefix in PLANTS:
		var el = main.god.pick_kind(mpos, prefix)
		if el != null:
			return el
	return null


## Why she can't fell this tree ("" if she can).
func fell_problem(el) -> String:
	if Town.TOWN.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)):
		return "The town's trees aren't hers to fell."
	return ""


## She fells the tree: it's gone until it grows back, and she gets its wood. Returns the wood.
func fell(el) -> int:
	_record(el)
	_set_cut(el, true)
	main._rebuild_grid() # its trunk no longer stands in the way
	var wood := int(econ("tree_wood", 5))
	Game.add_item("wood", wood)
	return wood


## How many leaves trimming this plant gives.
func leaves_for(el) -> int:
	var by: Dictionary = econ("leaves", {})
	for prefix in by:
		if el.kind.begins_with(str(prefix)):
			return int(by[prefix])
	return 1


## She trims the plant to the ground: it's gone until it grows back. Returns the leaves.
func trim(el) -> int:
	_record(el)
	_set_cut(el, true)
	var n := leaves_for(el)
	Game.add_item("leaves", n)
	return n


## Hides what she has cut and brings back what has grown again. main.gd calls it once the world
## and the save are loaded, and every morning.
func apply() -> void:
	if main == null or main.god == null:
		return
	var cut: Dictionary = Game.flag("cut", {})
	var kept := {}
	for k in cut:
		var day := int(cut[k])
		var tree := str(k).begins_with("tree_")
		var regrow := int(econ("tree_regrow_days" if tree else "plant_regrow_days", 14 if tree else 2))
		if Game.day - day < regrow:
			kept[k] = day
	if kept.size() != cut.size():
		Game.set_flag("cut", kept)
	var grid := false
	for el in main.god.els:
		if not el.scenery:
			continue
		var on := kept.has(key_of(el))
		if el.cut != on:
			_set_cut(el, on)
			grid = grid or el.kind.begins_with("tree_")
	if grid:
		main._rebuild_grid()


func _record(el) -> void:
	var cut: Dictionary = Game.flag("cut", {}).duplicate()
	cut[key_of(el)] = Game.day
	Game.set_flag("cut", cut)


func _set_cut(el, on: bool) -> void:
	el.cut = on
	main.god._apply(el)
	main.god._reblock(el)
