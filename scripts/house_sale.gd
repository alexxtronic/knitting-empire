extends Node
## Buying Marcus's house in Bretton Oaks (Alex, 2026-11-20: "we'll be able to purchase Marcus's house
## from him after running his first task for 1,000 coin. This will be our first new house purchase
## (assuming player accepts and doesn't make their own). Player can fully customize the house after
## purchasing." Asked whose first task: Marcus's own).
##
## - His task. Once Act 1 is done, Marcus (tf_marcus, a townsperson: townsfolk.gd hands his menu rows
##   to rows_for()) has a favour to ask: the family is moving to a bigger house across the circle and
##   he'd like a hand-knit sweater for the move. Asked, he wears the red sweater pin (wants_sweater())
##   until she hands him one (the plainest in her bag; he pays its fair price). Game.flags
##   "marcus_task": "asked", then "done".
## - The sale. With the task done his menu offers the house for `price` (data/economy.json
##   "marcus_house"); she can take it or leave it. Bought, Game.flags["marcus_house_owned"] is true:
##   nobody sleeps there any more (suburb.home_for() skips it) and Marcus has moved across the circle.
## - Making it hers. In Build & Buy (B) while she stands inside it, a "Your Bretton Oaks house" bar
##   offers the world editor's house tools (house_edit.gd: Wall, Door, Sliding door, Window, Opening,
##   Floor and its list), with this node standing in for the world editor (the duck-typed host:
##   undo_stack, house_split_edited, unsaved, _show_status()). Her changes go in her save
##   (Game.flags["marcus_house_layout"]: {"walls", "rooms"}), never in data/world_layout.json, and
##   apply() lays them over the house after a load. Ctrl/Cmd+Z undoes, Delete removes a picked wall,
##   right click or Esc puts the tool down. Edits are free for now (a draft: Alex to say).
##   Not yet: placing catalogue furniture in it, moving Marcus's own furniture, and paint (build mode's
##   paint is for her farm house's walls only).
##
## Every line and number is a draft until Alex approves it.

const HouseEdit = preload("res://scripts/house_edit.gd")
const Data = preload("res://scripts/data.gd")

const MARCUS := "tf_marcus"

var main: Node # main.gd

# the host house_edit.gd expects (god_mode.gd's names)
var undo_stack: Array = []
var house_split_edited := false
var unsaved := false

var tools # house_edit.gd
var tool := "" # one of HouseEdit.TOOLS' ids, or ""
var bar: PanelContainer
var _btns := {}
var _drag := false


func _ready() -> void:
	name = "HouseSale"
	tools = HouseEdit.new(self)
	call_deferred("apply")


static func cfg(key: String, fallback: float) -> float:
	return float(Data.economy().get("marcus_house", {}).get(key, fallback))


static func price() -> int:
	return int(cfg("price", 1000))


static func owned() -> bool:
	return Game.flag("marcus_house_owned") == true


static func task() -> String:
	return str(Game.flag("marcus_task", ""))


func house():
	return main.suburb.walk_in if main and main.suburb else null


## Her own changes to the house, laid over it (after a load, and once bought).
func apply() -> void:
	var h = house()
	var lay: Variant = Game.flag("marcus_house_layout", null)
	if h == null or not owned() or not (lay is Dictionary):
		return
	h.set_layout(((lay as Dictionary).get("walls", []) as Array).duplicate(true), ((lay as Dictionary).get("rooms", []) as Array).duplicate(true))
	if main.has_method("_rebuild_grid"):
		main._rebuild_grid()


# --- Marcus's menu ------------------------------------------------------------------------------------

func _ready_for_task() -> bool:
	return Game.flag("act1_done") == true or Game.flag("story_farm") != true


## True while Marcus is waiting on a sweater for his task (townsfolk.gd shows the red pin).
func wants_sweater(p) -> bool:
	return p != null and str(p.vid) == MARCUS and task() == "asked"


func rows_for(p) -> Array:
	if p == null or str(p.vid) != MARCUS or not _ready_for_task():
		return []
	var row: Dictionary
	if owned():
		row = {"id": "noop", "label": "Settled in across the circle. The old house is yours", "enabled": false}
	elif task() == "":
		row = {"id": "mh_ask", "label": "Marcus has a favour to ask", "enabled": true}
	elif task() == "asked":
		var n := Game.count("sweater")
		row = {"id": "mh_give", "label": "Give Marcus a sweater" if n > 0 else "Marcus wants a sweater  (you have none)", "enabled": n > 0}
	else:
		row = {"id": "mh_buy", "label": "Buy Marcus's house  (%sc)" % _thousands(price()), "enabled": Game.coins >= price()}
	row["group"] = "Marcus's house"
	return [row]


## His rows' actions; true if it was one of them.
func action(p, id: String) -> bool:
	match id:
		"mh_ask":
			ask(p)
		"mh_give":
			give(p)
		"mh_buy":
			buy(p)
		_:
			return false
	return true


func _say(p, text: String) -> void:
	if main and p:
		main.hud.show_dialogue(p.title, -1, text)


func ask(p = null) -> void:
	if task() != "":
		return
	Game.set_flag("marcus_task", "asked")
	_say(p, "Favour to ask. Four kids, three bedrooms: we're moving to the bigger place across the circle. My wife wants something hand-knit for the new house. Any sweater. You'd be saving my marriage.")
	if main:
		main.hud.show_toast("Marcus's task: bring him a sweater. Any one will do.")


## Hands him the plainest sweater in her bag; he pays its fair price, and offers her the old house.
func give(p = null) -> bool:
	if task() != "asked" or Game.sweaters.is_empty():
		return false
	var best := 0
	for i in Game.sweaters.size():
		if int(Game.sweaters[i]) < int(Game.sweaters[best]):
			best = i
	var pay: int = main.sale.fair(int(Game.sweaters[best])) if main and main.sale else 90
	if p != null and main:
		main.sell_sweater_to(p, best, pay)
	else:
		Game.remove_sweater(best)
		Game.coins += pay
	Game.set_flag("marcus_task", "done")
	_say(p, "She'll love it. Here.\nListen: the old house goes up for sale when we move. Split level, basement, the lot. %s coins and it's yours, before Gary gets his hands on it. Think about it." % _thousands(price()))
	return true


func buy(p = null) -> bool:
	if owned() or task() != "done" or not Game.spend(price()):
		return false
	Game.set_flag("marcus_house_owned")
	Game.set_flag("marcus_house_day", Game.day)
	_say(p, "Keys. Front door sticks in the wet. Do what you like with the place: knock walls down, put windows in. It's yours.")
	if main:
		main.hud.show_toast("Marcus's house in Bretton Oaks is yours. Stand inside it and open Build & Buy (B) to change its walls, doors, windows and floors.")
	apply()
	return true


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# --- making it hers: the house tools in Build & Buy ----------------------------------------------------

## True while she can edit it now: hers, Build & Buy open, and her standing inside it.
func can_edit() -> bool:
	var h = house()
	return owned() and h != null and main.mode == main.Mode.BUILD and h.inside and not main.god.active


func set_tool(t: String) -> void:
	if tool == "h_wall" and t != "h_wall":
		tools.deselect()
	tool = t
	_drag = false
	if t != "":
		if main.builder.tool != "":
			main.builder.set_tool("")
		if main.ghost:
			main._cancel_ghost()
		main.hud.show_toast(tools.hint(t) + " Ctrl/Cmd+Z undoes. Right click puts the tool down.")
	for k in _btns:
		(_btns[k] as Button).set_pressed_no_signal(k == t)


## house_edit.gd's host call after every change: keep it in her save.
func _show_status() -> void:
	var snap: Array = tools.snapshot()
	Game.set_flag("marcus_house_layout", {"walls": snap[0], "rooms": snap[1]})
	if main.has_method("_rebuild_grid"):
		main._rebuild_grid()


func undo() -> bool:
	if undo_stack.is_empty():
		return false
	var u: Array = undo_stack.pop_back()
	tools.restore(u[1])
	_show_status()
	return true


func _process(_delta: float) -> void:
	if main == null or main.hud == null:
		return
	var on := can_edit()
	if on and bar == null:
		_build_bar()
	if bar:
		bar.visible = on
	if not on and tool != "":
		set_tool("")
	elif tool != "" and main.builder.tool != "":
		set_tool("") # she picked up the farm's wall tool


func _build_bar() -> void:
	var hud = main.hud
	bar = PanelContainer.new()
	bar.name = "OwnedHouseBar"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(hud._label("Your Bretton Oaks house", 15, hud.GOLD))
	for t in HouseEdit.TOOLS:
		var id: String = t[0]
		var b: Button = hud._button(t[1], func(): set_tool(id if _btns[id].button_pressed else ""))
		b.toggle_mode = true
		_btns[id] = b
		row.add_child(b)
	var fp := OptionButton.new()
	fp.focus_mode = Control.FOCUS_NONE
	for f in HouseEdit.FLOORS:
		fp.add_item(str(f[1]))
		fp.set_item_metadata(fp.item_count - 1, str(f[0]))
	fp.item_selected.connect(func(i: int):
		tools.floor_kind = str(fp.get_item_metadata(i))
		set_tool("h_floor"))
	row.add_child(fp)
	bar.add_child(row)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_top = 8
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(bar)


## The tools take the mouse and their keys while one is in hand (children see input before main.gd).
func _unhandled_input(e: InputEvent) -> void:
	if tool == "" or not can_edit():
		return
	if main._autotest_dir != "" and e is InputEventMouse:
		return
	if handle(e):
		get_viewport().set_input_as_handled()


func handle(e: InputEvent) -> bool:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			set_tool("")
			return true
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			tools.press(tool, mb.position)
			_drag = true
		else:
			tools.release()
			_drag = false
		return true
	if e is InputEventMouseMotion and _drag:
		tools.move((e as InputEventMouseMotion).position)
		return true
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var k := e as InputEventKey
		if k.keycode == KEY_ESCAPE:
			set_tool("")
			return true
		if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			if tool == "h_wall" and tools.delete_selected():
				return true
		if k.keycode == KEY_Z and (k.ctrl_pressed or k.meta_pressed):
			undo()
			return true
	return false
