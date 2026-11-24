extends RefCounted
## --only=buildplus: Build & Buy with the world editor's reach (scripts/build_plus.gd). The catalogue
## holds everything god mode's Place list holds; a flower clump for 1c placed, paid and saved; a tree
## out past the farm at its price; a few square metres of gravel paid by the metre, and refused when
## she can't pay; her piece moved for nothing and taken up for half back; the world's own scenery on
## her farm taken up for good; refusals in Maple Grove's square, in Bretton Oaks and in Marcus's house
## until she owns it; all of it through a save and a load; and data/world_layout.json untouched, god
## mode's own records too, through a real open and close of the editor. Saves 71_buildplus_catalog.png,
## 71_buildplus_garden.png, 71_buildplus_paint.png and 71_buildplus_refused.png. Leaves the coins, the
## flags, her furniture and the road map as it found them.

const Catalog = preload("res://scripts/catalog.gd")
const Town = preload("res://scripts/town.gd")
const Forage = preload("res://scripts/forage.gd")

const LAYOUT := "res://data/world_layout.json"

var m: Node


func _check(label: String, ok: bool) -> void:
	m._check("buildplus: " + label, ok)


## Looks at a spot from the game's camera and clicks it in build mode.
func _click(p: Vector3) -> void:
	var sp: Vector2 = m.cam.unproject_position(p)
	m._last_mouse = sp
	m._build_click(sp, false)


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
	var furn0: Array = m.furniture.duplicate()
	Game.hour = 11.0
	Game.take_item("wood", Game.count("wood")) # these count coins
	m.set_mode(m.Mode.LIVE)
	m.hud.hide_dialogue()
	m.player.position = Vector3(10.5, 0, 7.5)

	# the catalogue: every option on god mode's Place list, each in a tab with a card and a price
	var missing: Array = []
	var w_items: Array = []
	for o in god.place_options():
		var id := str(bp.options.get(str(o[0]), ""))
		if id == "" or not (id in Catalog.INDOOR or id in Catalog.OUTDOOR) or not m.hud.item_buttons.has(id) or int(Catalog.ITEMS[id].get("price", 0)) <= 0 \
				or not (Catalog.cat_of(id) in Catalog.CATS):
			missing.append(str(o[0]))
		if id.begins_with("w_"):
			w_items.append("%s %dc" % [id, int(Catalog.ITEMS[id]["price"])])
	print("BUILDPLUS PRICES ", ", ".join(w_items))
	var nature: Array = Catalog.in_cat("Garden & Nature")
	_check("the catalogue holds all %d of god mode's Place options, each with a card and a price (%d missing: %s; Garden & Nature %d, Outdoor %d, Shop & Town %d)" % [god.place_options().size(), missing.size(), str(missing.slice(0, 8)), nature.size(), Catalog.in_cat("Outdoor").size(), Catalog.in_cat("Shop & Town").size()],
		missing.is_empty() and nature.size() >= 10 and Catalog.in_cat("Outdoor").size() >= 4)
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

	# leave it all as it was
	for f in m.furniture.duplicate():
		if not furn0.has(f):
			m.furniture.erase(f)
			f.queue_free()
	Game.flags = flags0
	bp.apply_saved()
	m.forage.apply()
	m._rebuild_grid()
	m.set_mode(m.Mode.LIVE)
	Game.coins = coins0
	Game.hour = hour0
	var bytes1 := FileAccess.get_file_as_bytes(LAYOUT)
	_check("data/world_layout.json untouched (%d bytes, same %s), god mode's layout, undo and unsaved as before (%s, %d, %s)" % [bytes1.size(), bytes1 == bytes0, JSON.stringify(god.layout()) == lay0, god.undo_stack.size(), god.unsaved],
		bytes1 == bytes0 and JSON.stringify(god.layout()) == lay0 and god.undo_stack.size() == undo0 and god.unsaved == unsaved0)
