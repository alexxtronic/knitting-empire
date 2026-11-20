extends RefCounted
## --only=marcushouse (and part of the full run): buying Marcus's house in Bretton Oaks
## (scripts/house_sale.gd). Builds the townsfolk for itself to find Marcus, and clears them after.
## Nothing on his menu before Act 1 is done; his favour, the red pin while he waits, a sweater handed
## over at its fair price, the 1,000c sale, nobody sleeping there after; then, inside it in Build &
## Buy, the owner's bar and a wall drawn and a floor laid with the house tools (paid for: refused with no
## coins, the wall by the metre and the floor by the square metre, half back for her own wall, nothing
## for Marcus's, undo giving it all back), kept in her save (not
## the layout file) and laid back over the house after a load, and undone. Saves
## 69_house_owned_bar.png and 69_house_owned_edit.png. Leaves the flags, coins, sweaters, the house,
## Nora and the camera as it found them.

const HouseSale = preload("res://scripts/house_sale.gd")
const Town = preload("res://scripts/town.gd")

var m: Node
var wi = null


func _screen(q: Vector3) -> Vector2:
	return m.cam.unproject_position(wi.house.global_transform * q)


func _drag(tool: String, a: Vector3, b: Vector3) -> void:
	var hs = m.house_sale
	hs.set_tool(tool)
	hs.handle(_press(_screen(a), true))
	for i in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = _screen(a.lerp(b, float(i + 1) / 5.0))
		hs.handle(mm)
		await m._wait(0.05)
	hs.handle(_press(_screen(b), false))
	await m._wait(0.2)


func _press(at: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	return e


func run(main: Node) -> void:
	m = main
	wi = m.suburb.walk_in if m.suburb != null else null
	var hs = m.house_sale
	var keep := {"flags": Game.flags.duplicate(true), "coins": Game.coins, "hour": Game.hour, "clock": Game.time_running, "pos": m.player.position,
		"sw": Game.sweaters.duplicate(), "sd": Game.sweater_designs.duplicate(), "sf": Game.sweater_fibres.duplicate(), "items": Game.count("sweater")}
	var layout_file := FileAccess.get_file_as_string("res://data/world_layout.json")
	var walls0: Array = (wi.cfg["walls"] as Array).duplicate(true) if wi else []
	var rooms0: Array = (wi.cfg["rooms"] as Array).duplicate(true) if wi else []
	Game.time_running = false
	Game.hour = 12.0
	for k in ["marcus_task", "marcus_house_owned", "marcus_house_layout", "marcus_house_day"]:
		Game.flags.erase(k)
	m.townsfolk.build()
	await m._wait(0.3)
	var marcus = m._villager(HouseSale.MARCUS)
	m._check("Marcus is about to ask (found %s, a walk-in house %s)" % [marcus != null, wi != null], marcus != null and wi != null)
	if marcus == null or wi == null:
		m.townsfolk.clear()
		return
	var ids := func() -> Array: return m.townsfolk.actions(marcus).map(func(a): return str(a["id"]))
	# nothing before Act 1 is done
	Game.set_flag("story_farm")
	Game.flags.erase("act1_done")
	var early: Array = ids.call()
	Game.set_flag("act1_done")
	var ask_row: Array = ids.call()
	m.townsfolk.action(marcus, "mh_ask")
	var pin: bool = hs.wants_sweater(marcus)
	while Game.count("sweater") > 0:
		Game.remove_sweater(0)
	var no_sw: Array = m.townsfolk.actions(marcus).filter(func(a): return str(a["id"]) == "mh_give")
	Game.add_sweater(3, "")
	Game.add_sweater(1, "")
	var fair: int = m.sale.fair(1)
	Game.coins = 0
	m.townsfolk.action(marcus, "mh_give")
	m.hud.hide_dialogue()
	var paid := Game.coins
	m._check("Marcus's favour: nothing before Act 1 (%s), then '%s'; asked, he wears the red pin (%s) and his row waits for a sweater (enabled with none: %s); handed the plainest (left: %s), paid its fair %dc (%dc), the task done ('%s')" % [
		str(early.filter(func(i): return str(i).begins_with("mh_"))), str(ask_row), pin, str(no_sw[0]["enabled"]) if not no_sw.is_empty() else "-", str(Game.sweaters), fair, paid, HouseSale.task()],
		not early.has("mh_ask") and ask_row.has("mh_ask") and pin and not no_sw.is_empty() and not bool(no_sw[0]["enabled"]) and Game.sweaters == [3] and paid == fair and HouseSale.task() == "done" and not hs.wants_sweater(marcus))
	# the sale
	var buy_rows: Array = m.townsfolk.actions(marcus).filter(func(a): return str(a["id"]) == "mh_buy")
	var poor: bool = not buy_rows.is_empty() and not bool(buy_rows[0]["enabled"])
	Game.coins = HouseSale.price() + 5
	m.townsfolk.action(marcus, "mh_buy")
	m.hud.hide_dialogue()
	var idx: int = int(preload("res://scripts/data.gd").load_json("split_house").get("house", 1))
	var sleepers_there := []
	for who in ["wren", "rowan", "rosa", "barbara", "giorgio", "steve", "gary", "sabrina", "rebecca", "tf_theo", "tf_lily", HouseSale.MARCUS, "tf_jake", "tf_pip", "tf_dev", "tf_hank", "lars", "x1", "x2", "x3", "x4", "x5", "x6", "x7"]:
		if m.suburb.home_for(who) == idx:
			sleepers_there.append(who)
	m._check("the sale: '%s' greyed while she's short (%s); bought for %sc (owned %s, %dc left), and nobody sleeps there now (%s)" % [str(buy_rows[0]["label"]) if not buy_rows.is_empty() else "-", poor, HouseSale._thousands(HouseSale.price()), HouseSale.owned(), Game.coins, str(sleepers_there)],
		HouseSale.price() == 1000 and poor and HouseSale.owned() and Game.coins == 5 and sleepers_there.is_empty())
	# making it hers: inside, Build & Buy, the house tools
	m._set_cam_lock(false)
	m.player.walk([])
	m.player.position = wi.house.global_transform * Vector3(-2.0, 0, -1.0)
	m.cam_target = wi.house.global_transform * Vector3(-3.5, 0, -1.0)
	m.cam_dist = 14.0
	await m._wait(0.6)
	m.set_mode(m.Mode.BUILD)
	await m._wait(0.4)
	var bar_on: bool = hs.bar != null and hs.bar.visible
	await m._shot("69_house_owned_bar.png")
	var n_walls: int = (wi.cfg["walls"] as Array).size()
	var n_rooms: int = (wi.cfg["rooms"] as Array).size()
	# a wall across the main floor, from a spot on clear floor (not a wall's top, as the camera sees it)
	var wa := Vector3(-5.6, 0, -0.5)
	var found := false
	for z in [-1.5, -0.5, -2.0, -1.0, -2.5, -3.0]:
		for x in [-5.6, -5.2, -4.8, -4.4, -4.0]:
			var q := Vector3(x, 0, z)
			if hs.tools._wall_under(_screen(q)).is_empty() and not hs.tools._at(_screen(q)).is_empty() \
					and wi.wall_near(Vector2(q.x, q.z), "main", 0.5) < 0 and wi.wall_near(Vector2(q.x + 3.0, q.z), "main", 0.5) < 0:
				wa = q
				found = true
				break
		if found:
			break
	# what it costs: nothing she can't pay for goes in; a 3 m wall and a 2 x 1.8 m oak floor, in coins
	var wood0: int = Game.count("wood")
	if wood0 > 0:
		Game.take_item("wood", wood0)
	Game.coins = 0
	await _drag("h_wall", wa, wa + Vector3(3.0, 0, 0))
	var refused: bool = (wi.cfg["walls"] as Array).size() == n_walls and hs.undo_stack.is_empty()
	Game.coins = 1000
	await _drag("h_wall", wa, wa + Vector3(3.0, 0, 0))
	var wall_c: int = 1000 - Game.coins
	hs.tools.floor_kind = "wood_oak"
	await _drag("h_floor", Vector3(-6.0, 0, -3.8), Vector3(-4.0, 0, -2.0))
	var floor_c: int = 1000 - wall_c - Game.coins
	var wr: Array = HouseSale.wall_rate()
	var fr: Array = HouseSale.floor_rate("wood_oak")
	m._check("her changes cost: refused with no coins (%s); a 3 m wall %dc (%d a metre), a 3.6 m² oak floor %dc (%.1f a m²), recorded in her save (%d)" % [refused, wall_c, int(wr[0]), floor_c, float(fr[0]), (Game.flag("marcus_house_paid", {}) as Dictionary).size()],
		refused and wall_c == ceili(3.0 * float(wr[0]) - 0.001) and floor_c == ceili(3.6 * float(fr[0]) - 0.001) and (Game.flag("marcus_house_paid", {}) as Dictionary).size() == 2)
	# taking her wall down gives half back; taking down one of Marcus's gives nothing; undo puts each back
	var c0 := Game.coins
	wi.selected_wall = n_walls
	hs.tools.delete_selected()
	var half: int = Game.coins - c0
	hs.undo()
	var after_undo: int = Game.coins
	wi.selected_wall = 0
	hs.tools.delete_selected()
	var base_back: int = Game.coins - c0
	var base_gone: bool = (wi.cfg["walls"] as Array).size() == n_walls # hers is back, his first is gone
	hs.undo()
	m._check("her wall taken down gives half back (+%dc of %dc), undone (%dc); one of Marcus's own gives nothing (+%dc, gone %s), undone (walls %d)" % [half, wall_c, after_undo - c0, base_back, base_gone, (wi.cfg["walls"] as Array).size()],
		half == roundi(wall_c * 0.5) and after_undo == c0 and base_back == 0 and base_gone and (wi.cfg["walls"] as Array).size() == n_walls + 1)
	var saved: Variant = Game.flag("marcus_house_layout", null)
	var drew: bool = (wi.cfg["walls"] as Array).size() == n_walls + 1 and (wi.cfg["rooms"] as Array).size() == n_rooms + 1
	var in_save: bool = saved is Dictionary and ((saved as Dictionary)["walls"] as Array).size() == n_walls + 1 and ((saved as Dictionary)["rooms"] as Array).size() == n_rooms + 1
	await m._wait(0.3)
	await m._shot("69_house_owned_edit.png")
	# a load: the data file's house, then her changes laid back over it
	wi.set_layout(walls0.duplicate(true), rooms0.duplicate(true))
	hs.apply()
	var reloaded: bool = (wi.cfg["walls"] as Array).size() == n_walls + 1 and (wi.cfg["rooms"] as Array).size() == n_rooms + 1
	var untouched: bool = FileAccess.get_file_as_string("res://data/world_layout.json") == layout_file
	hs.undo()
	hs.undo()
	var undone: bool = (wi.cfg["walls"] as Array).size() == n_walls and (wi.cfg["rooms"] as Array).size() == n_rooms and Game.coins == 1000
	hs.set_tool("")
	m.set_mode(m.Mode.LIVE)
	await m._wait(0.2)
	var bar_off: bool = hs.bar == null or not hs.bar.visible
	m._check("hers to change: inside in Build & Buy the owner's bar shows (%s, gone after %s); a wall drawn and an oak floor laid (%s), kept in her save (%s) and laid back after a load (%s), the layout file untouched (%s); undo puts it back (%s)" % [bar_on, bar_off, drew, in_save, reloaded, untouched, undone],
		bar_on and bar_off and drew and in_save and reloaded and untouched and undone)
	# put it all back
	wi.set_layout(walls0.duplicate(true), rooms0.duplicate(true))
	m._rebuild_grid()
	m.townsfolk.clear()
	Game.flags = keep["flags"]
	Game.coins = keep["coins"]
	if Game.count("wood") < wood0:
		Game.add_item("wood", wood0 - Game.count("wood"))
	Game.hour = keep["hour"]
	Game.time_running = keep["clock"]
	Game.sweaters = keep["sw"]
	Game.sweater_designs = keep["sd"]
	Game.sweater_fibres = keep["sf"]
	m.player.position = keep["pos"]
	m.player.walk([])
	m.cam_target = m.player.position
	m.hud.hide_dialogue()
