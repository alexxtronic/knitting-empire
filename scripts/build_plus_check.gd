extends RefCounted
## --only=buildplus: Build & Buy with the world editor's reach (scripts/build_plus.gd). The catalogue
## holds everything god mode's Place list holds that makes sense to buy, each model once ("build_prices"
## "exclude" and "prefer_scenery"); undo taking back two ground strokes in order, a placement and a
## sale, with their coins (71_buildplus_undo_before.png, 71_buildplus_undo_after.png); a flower clump for 1c placed, paid and saved; a tree
## out past the farm at its price; a few square metres of gravel paid by the metre, and refused when
## she can't pay; her piece moved for nothing and taken up for half back; the world's own scenery on
## her farm taken up for good; refusals in Maple Grove's square, in Bretton Oaks and in Marcus's house
## until she owns it; all of it through a save and a load; and data/world_layout.json untouched, god
## mode's own records too, through a real open and close of the editor. Saves 71_buildplus_catalog.png,
## 71_buildplus_garden.png, 71_buildplus_paint.png and 71_buildplus_refused.png. Leaves the coins, the
## flags, her furniture and the road map as it found them.
## The town pieces ("build_prices" "town"): absent in Act 1 (with a large plot or without) and in Act 2
## without one, the Town tab hidden; listed with a toast once she buys Eastfield Acres in Act 2; a
## building placed there and paid for, its low walls hidden, a post box there taking no post; both
## refused on her farm; the never list ("exclude") absent every time; all of it through a save and a
## load (an Act 1 game between hiding them again). Saves 71_buildplus_town.png. Leaves the act too.

const Catalog = preload("res://scripts/catalog.gd")
const Town = preload("res://scripts/town.gd")
const Forage = preload("res://scripts/forage.gd")
const GodMode = preload("res://scripts/god_mode.gd")

const LAYOUT := "res://data/world_layout.json"

var m: Node


func _check(label: String, ok: bool) -> void:
	m._check("buildplus: " + label, ok)


## Looks at a spot from the game's camera and clicks it in build mode.
func _click(p: Vector3) -> void:
	var sp: Vector2 = m.cam.unproject_position(p)
	m._last_mouse = sp
	m._build_click(sp, false)


## Ctrl/Cmd+Z as the keyboard sends it, through main._input.
func _cmd_z() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.physical_keycode = KEY_Z
	ev.ctrl_pressed = true
	ev.meta_pressed = true
	ev.pressed = true
	ev.set_meta("ke_test", true)
	Input.parse_input_event(ev)
	await m._wait(0.1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	up.set_meta("ke_test", true)
	Input.parse_input_event(up)
	await m._wait(0.5)


func _look(p: Vector3, dist := 14.0) -> void:
	m._set_cam_lock(false)
	m.cam_target = p
	m.cam_dist = dist
	await m._wait(0.7)


func _piece_at(id: String, p: Vector3):
	for f in m.furniture:
		if is_instance_valid(f) and f.item_id == id and Vector2(f.position.x - p.x, f.position.z - p.z).length() < 0.6:
			return f
	return null


## Holds a catalogue piece over a spot: whether it could go down there.
func _valid_at(id: String, p: Vector3) -> bool:
	m._begin_place(id)
	if m.ghost == null:
		return false
	m.ghost.position = Vector3(p.x, 0, p.z)
	var ok: bool = m._placement_valid(m.ghost, m.ghost.position)
	m._cancel_ghost()
	return ok


func run(main_node: Node) -> void:
	m = main_node
	var bp = m.buildplus
	var god = m.god
	var bytes0 := FileAccess.get_file_as_bytes(LAYOUT)
	var lay0 := JSON.stringify(god.layout())
	var unsaved0: bool = god.unsaved
	var undo0: int = god.undo_stack.size()
	var coins0: int = Game.coins
	var hour0: float = Game.hour
	var flags0: Dictionary = Game.flags.duplicate(true)
	var act0: int = Game.act
	Game.act = 1
	bp.sync_town()
	var furn0: Array = m.furniture.duplicate()
	Game.hour = 11.0
	Game.take_item("wood", Game.count("wood")) # these count coins
	m.set_mode(m.Mode.LIVE)
	m.hud.hide_dialogue()
	m.player.position = Vector3(10.5, 0, 7.5)

	# the catalogue: every option on god mode's Place list that makes sense to buy, each in a tab with a
	# card and a price; the rest left out by "build_prices" "exclude", and a model in twice listed once
	var missing: Array = []
	var w_items: Array = []
	var listed: Array = Catalog.INDOOR + Catalog.OUTDOOR
	for o in god.place_options():
		if bp.excluded.has(str(o[0])) or bp.town.has(str(o[0])): # (the town pieces are checked below)
			continue
		var id := str(bp.options.get(str(o[0]), ""))
		if id == "" or not (id in listed) or not m.hud.item_buttons.has(id) or int(Catalog.ITEMS[id].get("price", 0)) <= 0 \
				or not (Catalog.cat_of(id) in Catalog.CATS):
			missing.append(str(o[0]))
		if id.begins_with("w_") and not w_items.has("%s %dc" % [id, int(Catalog.ITEMS[id]["price"])]):
			w_items.append("%s %dc" % [id, int(Catalog.ITEMS[id]["price"])])
	print("BUILDPLUS PRICES ", ", ".join(w_items))
	print("BUILDPLUS EXCLUDED ", ", ".join(bp.excluded.keys()))
	print("BUILDPLUS HIDDEN ", ", ".join(bp.hidden.keys().map(func(k): return "%s (for %s)" % [k, bp.hidden[k]])))
	var nature: Array = Catalog.in_cat("Garden & Nature")
	_check("the catalogue holds every one of god mode's %d Place options that isn't excluded (%d excluded, %d missing: %s; Garden & Nature %d, Shop & Town %d)" % [god.place_options().size(), bp.excluded.size(), missing.size(), str(missing.slice(0, 8)), nature.size(), Catalog.in_cat("Shop & Town").size()],
		missing.is_empty() and nature.size() >= 10 and not bp.excluded.is_empty())
	# nothing that's no use as a purchase is for sale, though god mode still places it all
	var odd: Array = []
	for id in listed:
		if bp.exclude_pattern(str(id)) != "":
			odd.append(str(id))
	for id in ["w_building_cafe", "w_building_shop", "w_building_suburb_house", "w_barn", "w_maplewood_bus", "w_dog", "w_crop_turnip_0", "w_crop_pumpkin_3",
			"w_axe", "w_hoe", "w_shears", "w_shovel", "w_scythe", "w_watering_can", "w_lantern", "w_sign_yarn_barn", "welcome_sign", "bakery_stall", "mailbox", "w_door_interior", "w_sliding_door"]:
		if id in listed or m.hud.item_buttons.has(id):
			odd.append(id)
	var god_ids: Array = god.place_options().map(func(o): return str(o[0]))
	var god_keeps: bool = god_ids.has("scenery:building_cafe") and god_ids.has("scenery:maplewood_bus") and god_ids.has("scenery:axe") and god_ids.has("decor:welcome_sign")
	var kept: bool = "lantern" in listed and "fountain" in listed and "fence" in listed and "bench" in listed and "trash_can" in listed and "hay_bale" in listed \
		and "scarecrow" in listed and "w_tree_spruce" in listed and "w_rock_boulder" in listed and "w_bush_round" in listed and "w_tuft_tall" in listed and "w_fence_post" in listed and "cafe_table" in listed
	_check("in Act 1 no building, bus, dog, crop, tool, lantern prop, sign, stall or mailbox is for sale (%d found: %s), god mode still places them (%s), and the lamp post, fountain, fence, benches, trees, rocks, bushes and tufts are (%s)" % [odd.size(), str(odd.slice(0, 8)), god_keeps, kept],
		odd.is_empty() and god_keeps and kept)
	# one model, one card: the daisies at their scenery price, not the 35c flower bed too; the fountain as the catalogue's piece
	var seen := {}
	var twice: Array = []
	for id in listed:
		var k := "%s@%.2f" % [str(Catalog.ITEMS[id].get("model", id)).get_file().get_basename(), float(Catalog.ITEMS[id].get("scale", 1.0))]
		if seen.has(k):
			twice.append("%s/%s" % [seen[k], id])
		seen[k] = id
	_check("no model is in the catalogue twice (%s), the daisies are the 1c clump (%s, flower bed listed %s), the fountain the catalogue's (%s listed %s), a land's spruce not listed apart (%s)" % [str(twice.slice(0, 6)), "w_flowers_daisy" in listed, "bed_daisy" in listed, "fountain" in listed, "w_plaza_fountain" in listed, "w_mountains-tree_spruce" in listed],
		twice.is_empty() and "w_flowers_daisy" in listed and not "bed_daisy" in listed and "fountain" in listed and not "w_plaza_fountain" in listed \
		and not "w_mountains-tree_spruce" in listed and Catalog.ITEMS.has("w_mountains-tree_spruce") and bp.item_for("swamp-rock_cluster") != "")
	var after := JSON.stringify(god.layout())
	_check("registering them leaves god mode's Place list and layout as they were (%d options)" % god.place_options().size(), after == lay0)
	m.set_mode(m.Mode.BUILD)
	if m.hud.cat_tabs.has("Garden & Nature"):
		(m.hud.cat_tabs["Garden & Nature"] as Button).pressed.emit()
		(m.hud.cat_tabs["Garden & Nature"] as Button).button_pressed = true
	var tw := 0.0
	while tw < 12.0 and nature.any(func(i): return m.hud.item_buttons[i].icon == null):
		await m._wait(0.3)
		tw += 0.3
	await _look(Vector3(14, 0, 2))
	await m._shot("71_buildplus_catalog.png")

	# a flower clump (there's no tulip model: the poppies stand in) for 1c on her farm
	Game.coins = 1000
	var flower := "w_flowers_poppy"
	var spot := Vector3(20.5, 0, 6.5)
	await _look(spot, 10.0)
	var c0: int = Game.coins
	m._begin_place(flower)
	_click(spot)
	m._cancel_ghost()
	var fl = _piece_at(flower, spot)
	_check("a flower clump costs %dc and goes down on her farm (price %d, placed %s)" % [c0 - Game.coins, int(Catalog.ITEMS.get(flower, {}).get("price", -1)), fl != null],
		Catalog.ITEMS.has(flower) and int(Catalog.ITEMS[flower]["price"]) == 1 and c0 - Game.coins == 1 and fl != null)

	# a tree out past the farm, on the open land, at its price
	var tree := "w_tree_spruce"
	var tspot := Vector3.ZERO
	var found := false
	for r in 40:
		for k in 16:
			var a := k * TAU / 16.0
			var q := Vector3(30.0, 0, -2.0) + Vector3(cos(a), 0, sin(a)) * (4.0 + r * 1.5)
			if not m.LOT.grow(2.0).has_point(Vector2(q.x, q.z)) and m.builder.can_edit_at(q) == "" and _valid_at(tree, q):
				tspot = q
				found = true
				break
		if found:
			break
	await _look(tspot, 22.0)
	c0 = Game.coins
	m._begin_place(tree)
	_click(tspot)
	m._cancel_ghost()
	var tr = _piece_at(tree, tspot)
	if tr == null and m.ghost == null and found: # the click's snap moved it a little
		for f in m.furniture:
			if f.item_id == tree and Vector2(f.position.x - tspot.x, f.position.z - tspot.z).length() < 1.0:
				tr = f
	_check("a spruce goes down out past the farm (%.1f, %.1f) for its %dc (paid %d, placed %s)" % [tspot.x, tspot.z, int(Catalog.ITEMS[tree]["price"]), c0 - Game.coins, tr != null],
		found and tr != null and c0 - Game.coins == int(Catalog.ITEMS[tree]["price"]))
	await m._shot("71_buildplus_garden.png")

	# moving her piece is free; taking it up gives half back
	if tr != null:
		c0 = Game.coins
		_click(tr.position + Vector3(0, 0.6, 0))
		var held: bool = m.ghost == tr
		var to := Vector3.ZERO
		var moved := false
		if held:
			for d in [Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0, -2), Vector3(3, 0, 3)]:
				if m._placement_valid(tr, tr.position + d):
					to = tr.position + d
					break
			_click(to)
			moved = m.ghost == null and _piece_at(tree, to) != null
		var note := "to %s, at %s, valid %s" % [str(to), str(tr.position), m.ghost_valid]
		m._cancel_ghost()
		_check("moving her spruce costs nothing (held %s, moved %s, %dc; %s)" % [held, moved, c0 - Game.coins, note], held and moved and Game.coins == c0)
		await _look(tr.position, 14.0)
		_click(tr.position + Vector3(0, 0.6, 0))
		var value: int = bp.sell_value(tr)
		var held2: bool = m.ghost == tr
		var what: String = str(m.ghost.item_id) if m.ghost != null else "nothing"
		m._sell_ghost()
		if not held2:
			m._cancel_ghost()
		_check("taking it up gives half back (+%dc of %dc; held %s)" % [Game.coins - c0, int(Catalog.ITEMS[tree]["price"]), what], Game.coins - c0 == int(Catalog.ITEMS[tree]["price"]) / 2 and value == Game.coins - c0 and not m.furniture.has(tr))

	# the world's own scenery on her farm: taken up for nothing, gone for good
	var wel = null
	for el in god.els:
		if el.scenery and not el.cut and not el.deleted and bp.item_for(el.kind) != "" and m.LOT.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)) \
				and (el.kind.begins_with("bush_") or el.kind.begins_with("rock_") or el.kind.begins_with("tree_")):
			await _look(el.xf.origin, 10.0)
			if bp.world_at(m.cam.unproject_position(el.xf * el.bounds.get_center())) == el: # the one the pointer finds there
				wel = el
				break
	var wkey := Forage.key_of(wel) if wel != null else ""
	if wel != null:
		c0 = Game.coins
		var aim: Vector3 = wel.xf * wel.bounds.get_center()
		var under = bp.world_at(m.cam.unproject_position(aim))
		_click(aim)
		var took: bool = m.ghost != null and wel.cut and (m.ghost_from as Dictionary).get("world", "") == wkey
		m._cancel_ghost()
		var back: bool = not wel.cut
		_click(wel.xf * wel.bounds.get_center())
		m._sell_ghost()
		Game.day += 1
		m.forage.apply() # the morning: felled trees grow back, but this stays gone
		_check("her farm's own %s: picked up (%s), put back by Esc (%s), removed for nothing (%dc) and still gone the next morning (%s; under the pointer %s, can edit '%s')" % [wel.kind, took, back, c0 - Game.coins, wel.cut, under.kind if under != null else "nothing", m.builder.can_edit_at(wel.xf.origin)],
			took and back and Game.coins == c0 and wel.cut and (Game.flag("cleared", {}) as Dictionary).has(wkey))
		Game.day -= 1
	else:
		_check("found the world's own scenery on her farm", false)

	# a few square metres of gravel, paid by the metre that changes
	var pspot := spot + Vector3(-6, 0, -2)
	await _look(pspot, 12.0)
	m.builder.set_tool("ground")
	bp.ground_kind = "gravel"
	var img: Image = god.road_img
	var before := img.duplicate() as Image
	c0 = Game.coins
	m.builder.click(pspot)
	m.builder.hover_at(pspot + Vector3(2.5, 0, 0))
	bp.paint_end()
	var n := 0
	var px: Rect2i = god._px_in(Rect2(pspot.x - 2, pspot.z - 2, 7, 4))
	for y in range(px.position.y, px.end.y):
		for x in range(px.position.x, px.end.x):
			if img.get_pixel(x, y) != before.get_pixel(x, y):
				n += 1
	var m2 := n / 64.0
	var want := ceili(m2 * 2.0 - 0.0001)
	_check("painting %.1f m² of gravel costs %dc at 2c a square metre (charged %d, ground now '%s')" % [m2, want, c0 - Game.coins, god.road_at(pspot.x, pspot.z)],
		m2 > 3.0 and c0 - Game.coins == want and bp.last_cost == want and god.road_at(pspot.x, pspot.z) == "gravel")
	await m._shot("71_buildplus_paint.png")
	var poor := pspot + Vector3(0, 0, 4)
	var was: String = god.road_at(poor.x, poor.z)
	Game.coins = 1
	bp.ground_kind = "cobble"
	m.builder.click(poor)
	m.builder.hover_at(poor + Vector3(3, 0, 0))
	bp.paint_end()
	_check("with 1c she can't pay for a stroke of cobbles: refused, nothing taken, nothing laid ('%s', %dc)" % [bp.last_refusal, Game.coins],
		Game.coins == 1 and god.road_at(poor.x, poor.z) == was and bp.last_refusal.begins_with("Not enough"))
	Game.coins = 1000

	# undo: two overlapping strokes of different surfaces on lawn with tufts, taken back in order, each
	# putting the map, her layer, the cleared tufts, the grass and the coins back as they were
	var u := Vector3.INF
	var best_tufts := -1
	for i in 12:
		for j in 8:
			var q := Vector3(16.0 + i * 1.5, 0, 9.0 + j * 1.5)
			if Vector2(q.x - pspot.x, q.z - pspot.z).length() < 7.0 or Vector2(q.x - poor.x, q.z - poor.z).length() < 7.0:
				continue
			var ok := true
			for d in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(1.5, 0, -1.5), Vector3(1.5, 0, 1.5)]:
				var w: Vector3 = q + d
				if bp._why_not(w) != "" or god.road_at(w.x, w.z) != "" or m.grass.grass_at(w.x, w.z) < 0.5:
					ok = false
			if not ok:
				continue
			var tufts: int = god.els.filter(func(e): return e.scenery and not e.cut and not e.deleted and GodMode.SMALL.has(e.kind) and Vector2(e.xf.origin.x - q.x - 1.5, e.xf.origin.z - q.z).length() < 2.0).size()
			if tufts > best_tufts:
				best_tufts = tufts
				u = q
	var found_u := u != Vector3.INF
	if not found_u:
		u = pspot + Vector3(8, 0, 6)
	await _look(u + Vector3(1.5, 0, 0), 12.0)
	var snap := func() -> Dictionary:
		var img_now: Image = god.road_img
		return {"road": img_now.get_region(god._px_in(Rect2(u.x - 3, u.z - 4, 9, 8))).get_data(), "paint": JSON.stringify(Game.flag("ground_paint", {})),
			"cleared": JSON.stringify(Game.flag("cleared", {})), "grass": snappedf(m.grass.grass_at(u.x + 1.5, u.z), 0.01), "coins": Game.coins,
			"tufts": god.els.filter(func(e): return e.scenery and e.cut and GodMode.SMALL.has(e.kind)).size()}
	var s0: Dictionary = snap.call()
	bp.undo_stack.clear()
	m.builder.set_tool("ground")
	bp.ground_kind = "dirt"
	m.builder.click(u)
	m.builder.hover_at(u + Vector3(3, 0, 0))
	bp.paint_end()
	var cost_a: int = bp.last_cost
	var s1: Dictionary = snap.call()
	var dirt_on: String = god.road_at(u.x + 1.5, u.z)
	bp.ground_kind = "cobble"
	m.builder.click(u + Vector3(1.5, 0, -1.5))
	m.builder.hover_at(u + Vector3(1.5, 0, 1.5))
	bp.paint_end()
	var cost_b: int = bp.last_cost
	var cobble_on: String = god.road_at(u.x + 1.5, u.z)
	await m._wait(0.3)
	await m._shot("71_buildplus_undo_before.png")
	await _cmd_z() # Ctrl/Cmd+Z through main._input: the cobbles come off, the dirt under them is back
	var s2: Dictionary = snap.call()
	var after_one: String = god.road_at(u.x + 1.5, u.z)
	_check("undo takes back the last stroke: cobbles (%dc) over dirt (%dc) come off to the dirt ('%s' -> '%s'), the map, her layer, the tufts and the coins as after the dirt (map %s, layer %s, cleared %s, coins %d/%d, %d left in the stack)" % [cost_b, cost_a, cobble_on, after_one, s2["road"] == s1["road"], s2["paint"] == s1["paint"], s2["cleared"] == s1["cleared"], s2["coins"], s1["coins"], bp.undo_stack.size()],
		found_u and dirt_on == "dirt" and cobble_on == "cobble" and cost_a > 0 and cost_b > 0 and after_one == "dirt" and s2["road"] == s1["road"] and s2["paint"] == s1["paint"] and s2["cleared"] == s1["cleared"] and s2["coins"] == s1["coins"])
	m.hud.build_undo_btn.pressed.emit() # the Paint row's Undo: the dirt goes too
	await m._wait(0.6)
	var s3: Dictionary = snap.call()
	_check("a second undo (the Undo button) takes the dirt back too: map, layer, cleared tufts (%d were cleared, %d now), grass (%.2f, was %.2f, %.2f painted) and every coin as before (%d/%d)" % [s1["tufts"], s3["tufts"], s3["grass"], s0["grass"], s1["grass"], s3["coins"], s0["coins"]],
		s3["road"] == s0["road"] and s3["paint"] == s0["paint"] and s3["cleared"] == s0["cleared"] and s3["tufts"] == s0["tufts"] and s3["coins"] == s0["coins"] and absf(float(s3["grass"]) - float(s0["grass"])) < 0.02 and float(s1["grass"]) < float(s0["grass"]) - 0.3 and god.road_at(u.x + 1.5, u.z) == "")
	await m._shot("71_buildplus_undo_after.png")
	m.builder.set_tool("")
	# a flower clump placed, then undone: gone, its coin back; one taken up and sold, then undone: back, its coins returned
	c0 = Game.coins
	var fspot := u + Vector3(1.5, 0, 0)
	for k in 24: # somewhere both a flower clump and a bush can go down
		var q := spot + Vector3(cos(k * 0.9), 0, sin(k * 0.9)) * (2.0 + k * 0.4)
		if _valid_at("w_bush_round", q) and _valid_at(flower, q) and _piece_at(flower, q) == null:
			fspot = q
			break
	await _look(fspot, 10.0)
	m._begin_place(flower)
	_click(fspot)
	m._cancel_ghost()
	var placed = null
	if not m.furniture.is_empty() and str(m.furniture.back().item_id) == flower and Game.coins == c0 - 1:
		placed = m.furniture.back()
	var had_flower: bool = placed != null
	await _cmd_z()
	var place_undone: bool = had_flower and not m.furniture.has(placed) and Game.coins == c0 # (a freed piece compares equal to null)
	m._begin_place("w_bush_round")
	_click(fspot)
	m._cancel_ghost()
	var bush = null
	if not m.furniture.is_empty() and str(m.furniture.back().item_id) == "w_bush_round":
		bush = m.furniture.back()
	var c1 := Game.coins
	var bush_id: int = bush.get_instance_id() if bush != null else 0
	var sold := false
	if bush != null:
		await m._wait(0.3) # its hitbox is in the physics world by the next frames
		var bsp: Vector2 = m.cam.unproject_position(bush.global_position + Vector3(0, 0.3, 0))
		m._last_mouse = bsp
		m._build_click(bsp, false)
		var value: int = bp.sell_value(bush)
		m._sell_ghost()
		sold = not m.furniture.has(bush) and Game.coins == c1 + value
	await _cmd_z()
	var back_bush = null
	if not m.furniture.is_empty() and str(m.furniture.back().item_id) == "w_bush_round" and m.furniture.back().get_instance_id() != bush_id:
		back_bush = m.furniture.back()
	_check("undo takes back a placement (flower %s, coins %s) and a sale (sold %s, back %s, coins %d after, %d before the sale)" % [had_flower, place_undone, sold, back_bush != null, Game.coins, c1],
		place_undone and sold and back_bush != null and Game.coins == c1)
	if back_bush != null:
		m.furniture.erase(back_bush)
		back_bush.queue_free()
	Game.coins = 1000
	bp.ground_kind = "gravel"
	m.builder.set_tool("")

	# refusals: Maple Grove's square, Bretton Oaks, Marcus's house until she owns it
	var square := Vector3(Town.TOWN.get_center().x, 0, Town.TOWN.get_center().y)
	var t_why: String = m.builder.can_edit_at(square)
	var t_place := _valid_at(flower, square)
	m.builder.set_tool("ground")
	c0 = Game.coins
	m.builder.click(square)
	bp.paint_end()
	var t_paint: bool = Game.coins == c0 and bp.last_refusal != ""
	m.builder.set_tool("")
	var sb = m.suburb
	var s_at: Vector3 = sb.centre if sb != null else Vector3(99, 0, 8)
	var s_why: String = m.builder.can_edit_at(s_at)
	var s_place := _valid_at(flower, s_at + Vector3(4, 0, 0))
	_check("Maple Grove's square is refused ('%s', placing %s, painting refused %s) and Bretton Oaks too ('%s', placing %s)" % [t_why, t_place, t_paint, s_why, s_place],
		t_why != "" and not t_place and t_paint and s_why != "" and not s_place)
	var open_sq := square + Vector3(-5.0, 0, 4.5) # clear of the fountain, so the red ghost shows
	await _look(open_sq, 9.0)
	m._begin_place("w_bush_round")
	var ssp: Vector2 = m.cam.unproject_position(open_sq)
	m._last_mouse = ssp
	m._update_ghost(ssp)
	m._build_click(ssp, false) # refused: the toast says why
	var red: bool = m.ghost_marker.material_override == m._mark_bad
	await m._wait(0.2)
	await m._shot("71_buildplus_refused.png")
	m._cancel_ghost()
	_check("the ghost goes red over the square (%s)" % red, red)
	var owned0 = Game.flag("marcus_house_owned")
	var wi = sb.walk_in if sb != null else null
	if wi != null:
		var inside: Vector3 = wi.house.global_transform * Vector3(-4.0, 0, 0)
		Game.flags.erase("marcus_house_owned")
		var no: String = m.builder.can_edit_at(inside)
		Game.set_flag("marcus_house_owned")
		var yes: String = m.builder.can_edit_at(inside)
		_check("inside Marcus's house: refused before she owns it ('%s'), hers after ('%s')" % [no, yes], no != "" and yes == "" and wi.in_footprint(wi.local(inside)))
		if owned0 == null:
			Game.flags.erase("marcus_house_owned")
		else:
			Game.set_flag("marcus_house_owned", owned0)
	else:
		_check("Marcus's house is there", false)

	# god mode: opened and closed for real, it sees the map without her paint and saves none of her edits
	var gm_ok := true
	if god.is_admin():
		god.set_active(true)
		await m._wait(0.3)
		var during := JSON.stringify(god.layout())
		var base_there: String = god.road_at(pspot.x, pspot.z)
		god.set_active(false)
		await m._wait(0.3)
		gm_ok = during == lay0 and base_there != "gravel" and god.road_at(pspot.x, pspot.z) == "gravel"
		_check("god mode open: the layout it would save is as before her edits (%s), her gravel off ('%s') and back after ('%s')" % [during == lay0, base_there, god.road_at(pspot.x, pspot.z)], gm_ok)

	# a save and a load: her pieces (through the furniture list the save keeps), her paint, the cleared scenery
	var flower_e: Dictionary = m.furniture_entry(fl) if fl != null else {}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	var entries: Array = JSON.parse_string(JSON.stringify(m.furniture.map(func(f): return m.furniture_entry(f))))
	for f in m.furniture.duplicate():
		if not furn0.has(f):
			m.furniture.erase(f)
			f.queue_free()
	Game.flags.erase("ground_paint")
	Game.flags.erase("cleared")
	bp.apply_saved()
	m.forage.apply()
	var gone: bool = god.road_at(pspot.x, pspot.z) != "gravel" and (wel == null or not wel.cut) and _piece_at(flower, spot) == null
	Game.from_dict(saved)
	for e in entries:
		var found_e := false
		for f in m.furniture:
			if m.furniture_entry(f).hash() == (e as Dictionary).hash():
				found_e = true
		if not found_e:
			m._spawn_entry(e)
	bp.apply_saved()
	m.forage.apply()
	m._rebuild_grid()
	var fl2 = _piece_at(flower, spot)
	_check("a save and a load bring back the flowers (%s), the gravel ('%s') and the cleared %s (%s), and nothing of them before (%s)" % [fl2 != null, god.road_at(pspot.x, pspot.z), wel.kind if wel else "-", wel.cut if wel else false, gone],
		gone and fl2 != null and god.road_at(pspot.x, pspot.z) == "gravel" and (wel == null or wel.cut) and not flower_e.is_empty())

	# a piece of the world's own, moved somewhere else: hers, kept with "w", worth nothing
	var wel2 = null
	for el in god.els:
		if el.scenery and not el.cut and not el.deleted and el.kind.begins_with("rock_") and bp.item_for(el.kind) != "" and m.builder.can_edit_at(el.xf.origin) == "" \
				and m.LOT.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)):
			wel2 = el
			break
	if wel2 != null:
		await _look(wel2.xf.origin, 10.0)
		c0 = Game.coins
		_click(wel2.xf * wel2.bounds.get_center())
		var g = m.ghost
		var put := false
		if g != null:
			for d in [Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0, -2), Vector3(3, 0, -3)]:
				if m._placement_valid(g, wel2.xf.origin + d):
					_click(wel2.xf.origin + d)
					put = m.ghost == null
					break
		var e2: Dictionary = m.furniture_entry(g) if put else {}
		_check("the world's own %s moved for nothing (%dc): hers now, kept as the world's (%s), worth nothing taken up (%d)" % [wel2.kind, c0 - Game.coins, str(e2.get("w", "")), bp.sell_value(g) if g != null else -1],
			put and Game.coins == c0 and int(e2.get("w", 0)) == 1 and bp.sell_value(g) == 0 and wel2.cut)
	else:
		_check("found a rock on her farm", false)

	await _town_checks(furn0)

	# leave it all as it was
	for f in m.furniture.duplicate():
		if not furn0.has(f):
			m.furniture.erase(f)
			f.queue_free()
	Game.flags = flags0
	bp.apply_saved()
	m.forage.apply()
	m._rebuild_grid()
	Game.act = act0
	m.builder.refresh_world() # her plots as they were: Eastfield's stakes gone, its scenery back
	bp.sync_town()
	m.set_mode(m.Mode.LIVE)
	Game.coins = coins0
	Game.hour = hour0
	var bytes1 := FileAccess.get_file_as_bytes(LAYOUT)
	_check("data/world_layout.json untouched (%d bytes, same %s), god mode's layout, undo and unsaved as before (%s, %d, %s)" % [bytes1.size(), bytes1 == bytes0, JSON.stringify(god.layout()) == lay0, god.undo_stack.size(), god.unsaved],
		bytes1 == bytes0 and JSON.stringify(god.layout()) == lay0 and god.undo_stack.size() == undo0 and god.unsaved == unsaved0)


## What's never for sale ("build_prices" "exclude"): the crops, tools, lantern and needles as props,
## the dog and sheep, the suitcase, the plaza's cobbles and the house editor's doors.
const NEVER := ["w_crop_turnip_0", "w_crop_pumpkin_3", "w_axe", "w_hoe", "w_shears", "w_shovel", "w_scythe", "w_watering_can",
	"w_lantern", "w_knitting_needles", "w_dog", "w_sheep_woolly", "w_door_interior", "w_sliding_door", "w_cobble_plaza_0"]


## The town pieces and the never list as Build & Buy has them now: {"town": how many listed, "tab": shown,
## "never": any never-for-sale id listed}.
func _town_state() -> Dictionary:
	var bp = m.buildplus
	bp.sync_town()
	var lst: Array = Catalog.INDOOR + Catalog.OUTDOOR
	var town_n := 0
	for id in Catalog.TOWN:
		if id in lst or m.hud.item_buttons.has(id):
			town_n += 1
	var never: Array = []
	for id in lst:
		if bp.exclude_pattern(str(id)) != "":
			never.append(str(id))
	for id in NEVER:
		if id in lst or m.hud.item_buttons.has(id):
			never.append(id)
	return {"town": town_n, "tab": m.hud.town_tab != null and m.hud.town_tab.visible, "never": never}


func _set_plots(ids: Array) -> void:
	Game.set_flag("plots_owned", ids.duplicate())
	m.builder.refresh_world()


## A point of a plot: its centre plus `k` (each -0.5..0.5) of its size, pulled in half a metre.
func _corner(p: Dictionary, k: Vector2) -> Vector3:
	var r: Rect2 = m.builder.plot_rect(p).grow(-0.5)
	var c := r.get_center() + r.size * k
	return Vector3(c.x, 0, c.y)


## A spot on the large plot where a piece can go down, 9 m clear of `avoid` (Vector3.INF if none).
func _plot_spot(id: String, p: Dictionary, avoid: Array) -> Vector3:
	var r: Rect2 = m.builder.plot_rect(p)
	for j in range(3, int(r.size.y) - 2, 2):
		for i in range(3, int(r.size.x) - 2, 2):
			var q := Vector3(r.position.x + i, 0, r.position.y + j)
			var near := false
			for a in avoid:
				if Vector2(a.x - q.x, a.z - q.z).length() < 9.0:
					near = true
			if not near and _valid_at(id, q):
				return q
	return Vector3.INF


func _town_checks(furn0: Array) -> void:
	var b = m.builder
	var large: Dictionary = {}
	for p in b.plots():
		if p.get("large", false) == true:
			large = p
	if large.is_empty():
		_check("a large plot is for sale", false)
		return
	var lr: Rect2 = b.plot_rect(large)
	var edit_ok := true
	for k in [Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(-0.5, -0.5), Vector2.ZERO]:
		if b.can_edit_at(_corner(large, k)) != "":
			edit_ok = false
	_check("a large plot is for sale (%s, %s, %dc), out past her farm and the town, clear of Bretton Oaks (every corner hers to edit: %s)" % [str(large.get("name", "-")), str(large.get("rect", [])), int(large.get("price", 0)), edit_ok],
		edit_ok and not lr.intersects(m.LOT) and not lr.intersects(Town.TOWN))
	var lid := str(large["id"])
	var plots0: Array = (Game.flag("plots_owned", []) as Array).duplicate()
	Game.flags.erase("town_pieces_open")
	var n_town: int = Catalog.TOWN.size()
	var want_ids := ["w_building_shop", "w_building_cafe", "w_barn", "w_maplewood_bus", "w_sign_yarn_barn", "welcome_sign", "bakery_stall", "mailbox"]
	var missing: Array = want_ids.filter(func(i): return not i in Catalog.TOWN)
	print("BUILDPLUS TOWN ", ", ".join(Catalog.TOWN.map(func(i): return "%s %dc" % [i, int(Catalog.ITEMS[i].get("price", 0))])))
	# Act 1, with a large plot or without: none of it, no Town tab, and no picking one up
	Game.act = 1
	_set_plots([])
	var a1: Dictionary = _town_state()
	_set_plots([lid])
	var a1p: Dictionary = _town_state()
	m._begin_place("w_building_shop")
	var no_ghost: bool = m.ghost == null
	m._cancel_ghost()
	_check("Act 1: no town piece for sale and no Town tab, without a large plot (%d, tab %s) or with one (%d, tab %s); none picked up (%s); never list absent (%s)" % [a1["town"], a1["tab"], a1p["town"], a1p["tab"], no_ghost, str(a1["never"] + a1p["never"])],
		a1["town"] == 0 and not a1["tab"] and a1p["town"] == 0 and not a1p["tab"] and no_ghost and (a1["never"] as Array).is_empty() and (a1p["never"] as Array).is_empty())
	# Act 2 without a large plot: still none
	Game.act = 2
	_set_plots(plots0.filter(func(x): return str(x) != lid))
	var a2: Dictionary = _town_state()
	var met0: int = m.goals.metric({"check": "large_plot"})
	_check("Act 2 without a large plot: no town piece (%d), no Town tab (%s), the goal not met (%d), never list absent (%s)" % [a2["town"], a2["tab"], met0, str(a2["never"])],
		a2["town"] == 0 and not a2["tab"] and (a2["never"] as Array).is_empty() and met0 == 0)
	# buying Eastfield Acres: the town pieces come, in their own tab, with a toast
	Game.coins = 40000
	var c0 := Game.coins
	var price: int = b.plot_price(large)
	var bought: bool = b.buy_plot(lid)
	var a3: Dictionary = _town_state()
	var toast: String = m.hud.toast_label.text
	var met1: int = m.goals.metric({"check": "large_plot"})
	_check("bought %s for %dc (paid %d): all %d town pieces listed (%d; missing %s), the Town tab shows (%s), the toast ('%s'), the goal met (%d), never list absent (%s)" % [lid, price, c0 - Game.coins, n_town, a3["town"], str(missing), a3["tab"], toast, met1, str(a3["never"])],
		bought and c0 - Game.coins == price and missing.is_empty() and a3["town"] == n_town and a3["tab"] and toast.contains("Town") and Game.flag("town_pieces_open") == true
		and met1 == 1 and (a3["never"] as Array).is_empty() and Catalog.cat_of("w_building_shop") == Catalog.TOWN_CAT
		and int(Catalog.ITEMS["welcome_sign"]["price"]) > 0 and int(Catalog.ITEMS["bakery_stall"]["price"]) > 0)
	m.set_mode(m.Mode.BUILD)
	if m.hud.town_tab != null:
		m.hud.town_tab.pressed.emit()
		m.hud.town_tab.button_pressed = true
	# a building on the large plot, paid for; a post box beside it that takes no post
	Game.coins = 40000
	var bid := "w_building_shop"
	var spot := _plot_spot(bid, large, [])
	var placed = null
	c0 = Game.coins
	if spot != Vector3.INF:
		await _look(spot, 30.0)
		m._begin_place(bid)
		_click(spot)
		m._cancel_ghost()
		for f in m.furniture:
			if is_instance_valid(f) and f.item_id == bid and Vector2(f.position.x - spot.x, f.position.z - spot.z).length() < 1.5:
				placed = f
	var lows := 0
	if placed != null:
		for n in placed.find_children("*_low", "", true, false):
			if (n as Node3D).visible:
				lows += 1
	_check("a shop building goes down on %s at %s for its %dc (paid %d, placed %s, low walls showing %d)" % [lid, str(spot), int(Catalog.ITEMS[bid]["price"]), c0 - Game.coins, placed != null, lows],
		placed != null and c0 - Game.coins == int(Catalog.ITEMS[bid]["price"]) and lows == 0)
	var mspot := _plot_spot("mailbox", large, [spot] if placed != null else [])
	var box = null
	c0 = Game.coins
	if mspot != Vector3.INF:
		await _look(mspot, 14.0)
		m._begin_place("mailbox")
		_click(mspot)
		m._cancel_ghost()
		box = _piece_at("mailbox", mspot)
	var rows: Array = []
	if box != null:
		for a in m._actions_for(box):
			rows.append(str(a.get("label", a.get("id", ""))))
	var post := false
	for r in rows:
		if r.to_lower().contains("post") or r.to_lower().contains("ship") or r.to_lower().contains("letter"):
			post = true
	_check("a post box on the plot for %dc (paid %d), set dressing: no post or shipping on its menu (%s)" % [int(Catalog.ITEMS["mailbox"]["price"]), c0 - Game.coins, str(rows)],
		box != null and c0 - Game.coins == int(Catalog.ITEMS["mailbox"]["price"]) and not post)
	await _look(spot if placed != null else _corner(large, Vector2.ZERO), 26.0)
	await m._wait(0.4)
	await m._shot("71_buildplus_town.png")
	# refused on her farm, with the reason
	var farm := Vector3(20.5, 0, 6.5)
	var f_ok := _valid_at(bid, farm)
	var f_box := _valid_at("mailbox", farm)
	await _look(farm, 30.0)
	c0 = Game.coins
	var n0: int = m.furniture.size()
	m._begin_place(bid)
	_click(farm)
	var why: String = m.hud.toast_label.text
	var still: bool = m.ghost != null
	m._cancel_ghost()
	_check("refused on her farm: the building (%s) and the post box (%s), nothing paid (%d), nothing placed (%s), '%s'" % [f_ok, f_box, c0 - Game.coins, m.furniture.size() == n0, why],
		not f_ok and not f_box and still and Game.coins == c0 and m.furniture.size() == n0 and why.contains("large plot"))
	# a save and a load: an Act 1 game between takes them out again; the save brings it all back
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	var entries: Array = JSON.parse_string(JSON.stringify(m.furniture.map(func(f): return m.furniture_entry(f))))
	for f in m.furniture.duplicate():
		if not furn0.has(f):
			m.furniture.erase(f)
			f.queue_free()
	Game.act = 1
	_set_plots([])
	var a4: Dictionary = _town_state()
	Game.from_dict(saved)
	for e in entries:
		var found_e := false
		for f in m.furniture:
			if m.furniture_entry(f).hash() == (e as Dictionary).hash():
				found_e = true
		if not found_e:
			m._spawn_entry(e)
	m.builder.refresh_world()
	var a5: Dictionary = _town_state()
	var back = null
	for f in m.furniture:
		if is_instance_valid(f) and f.item_id == bid and Vector2(f.position.x - spot.x, f.position.z - spot.z).length() < 1.5:
			back = f
	var box_back = _piece_at("mailbox", mspot) if mspot != Vector3.INF else null
	_check("an Act 1 game hides them again (%d, tab %s); the save brings back Act %d, %s, the town pieces (%d, tab %s), the building (%s) and the post box (%s); never list absent (%s)" % [a4["town"], a4["tab"], Game.act, str(Game.flag("plots_owned", [])), a5["town"], a5["tab"], back != null, box_back != null, str(a4["never"] + a5["never"])],
		a4["town"] == 0 and not a4["tab"] and Game.act == 2 and b.owns(lid) and a5["town"] == n_town and a5["tab"] and back != null and box_back != null
		and (a4["never"] as Array).is_empty() and (a5["never"] as Array).is_empty())
	m.set_mode(m.Mode.LIVE)
