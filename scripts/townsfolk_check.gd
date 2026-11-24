extends RefCounted
## --only=townsfolk (and part of the full run): the townsfolk (scripts/townsfolk.gd,
## data/townsfolk.json). Builds them for itself (the autotest's town has none) and clears them after.
## Saves 64_townsfolk_crowd.png, 64_townsfolk_bench.png, 64_townsfolk_cafe.png, 64_townsfolk_pin.png
## 64_townsfolk_star_pin.png and 64_townsfolk_villager_pin.png.

const Data = preload("res://scripts/data.gd")
const Town = preload("res://scripts/town.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")

var m: Node


func _look(at: Vector3, dist: float) -> void:
	m.cam_target = at
	m.cam_dist = dist


## Back to eleven in the morning (the autotest's clock runs ten seconds an hour), seen as no jump.
func _morning() -> void:
	Game.hour = 11.0
	m.townsfolk._last_now = m.townsfolk.now_h()


## Everyone but `busy` stands where they are for a while, so they don't take the seats the check wants.
func _park(busy: Array) -> void:
	for p in m.townsfolk.people:
		if not p in busy and p.state != "away":
			m.townsfolk._end_activity(p)
			p.walk_to(p.position, [])
			p.state = "idle"
			p.until = m.townsfolk.now_h() + 50.0


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await m._wait(0.25)
		t += 0.25
	return cond.call()


func run(main: Node) -> void:
	m = main
	var tf = m.townsfolk
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	var hour0: float = Game.hour
	var day0: int = Game.day
	var flags0: Dictionary = Game.flags.duplicate(true)
	var friends0: Dictionary = Game.friends.duplicate(true)
	var sw0: Array = Game.sweaters.duplicate()
	var sd0: Array = Game.sweater_designs.duplicate()
	var sf0: Array = Game.sweater_fibres.duplicate()
	var coins0: int = Game.coins
	var pos0: Vector3 = m.player.position
	m._set_cam_lock(false)

	# the data: Alex's four lines and ten more, the people in the file
	var data := Data.load_json("townsfolk")
	var lines: Array = data.get("lines", []).map(func(l): return str(l["text"]))
	var alex := ["I hope my wife forgives me", "Don't you have a job?", "do I know you?", "STRANGER DANGER!"]
	m._check("townsfolk: %d lines, Alex's four among them (%s)" % [lines.size(), str(alex.map(func(a): return lines.any(func(l): return l.contains(a))))],
		lines.size() == 14 and alex.all(func(a): return lines.any(func(l): return l.contains(a))))

	Game.hour = 11.0
	m.player.position = Vector3(Town.TOWN_ARRIVE)
	_look(m.player.position, 16.0)
	tf.build()
	await m._wait(0.6)
	var people: Array = tf.people
	var faces: Array = people.filter(func(p): return p.body != null and p.body.face != null)
	m._check("townsfolk: %d people, %d in their own models with real eyes" % [people.size(), faces.size()],
		people.size() == data.get("people", []).size() and people.size() >= 7 and faces.size() == people.size()) # 7 once Marcus moves into Bretton Oaks as a villager
	m._check("townsfolk: not in the town's cast (no scenes, gifts or jobs), but _villager() finds them",
		people.all(func(p): return not p in m.villagers) and m._villager("tf_theo") == tf.find("tf_theo") and tf.find("tf_theo") != null)
	var kid = tf.find("tf_lily")
	var man = tf.find("tf_theo")
	m._check("townsfolk: the children are child-sized (Lily %.2f, Theo %.2f)" % [kid._model.scale.x if kid else 0.0, man._model.scale.x if man else 0.0],
		kid != null and man != null and kid._model.scale.x < 0.7 and man._model.scale.x > 0.95)

	# eleven in the morning: the most allowed are out, on open ground in town
	tf.place_all()
	var out: Array = people.filter(func(p): return p.state != "away")
	var max_out := int(data.get("max_out", 6))
	m._check("townsfolk: at eleven %d of %d are about (at most %d), all on open ground in town" % [out.size(), people.size(), max_out],
		out.size() == mini(max_out, people.size()) and out.all(func(p): return m._walkable(m._cell(p.position)) and Town.TOWN.grow(1.0).has_point(Vector2(p.position.x, p.position.z))))
	var start := {}
	for p in out:
		start[p] = p.position
	await m._wait(8.0)
	var moved: Array = out.filter(func(p): return p.position.distance_to(start[p]) > 1.0)
	m._check("townsfolk: they get on with their day (%d of %d moved in 8 s)" % [moved.size(), out.size()], moved.size() >= 2)
	_look(Vector3(Town.TOWN.get_center().x, 0, Town.TOWN.get_center().y), 20.0)
	await m._wait(1.5)
	await m._shot("64_townsfolk_crowd.png")

	# a bench: the nearest free end, sitting, Nora's middle left free
	_morning()
	var sitter = out[0]
	var second = out[1]
	_park([sitter, second])
	tf._end_activity(sitter)
	var ok: bool = tf.sit_on_bench(sitter)
	if ok:
		sitter.settle_at(sitter.goal + Vector3(0.8, 0, 0.8)) # a step away: the walk is not what's checked here
		sitter.walk_to(sitter.goal, m._find_path(sitter.position, sitter.goal))
	var sat: bool = ok and await _wait_for(func(): return sitter.state == "bench", 40.0)
	var b = sitter.bench
	var off := -1.0
	if b != null:
		off = Vector2(sitter.position.x, sitter.position.z).distance_to(Vector2(m._seat_point(b).x, m._seat_point(b).z))
	m._check("townsfolk: %s sits on a %s, at %.2f m from its middle, with SitIdle (%s)" % [sitter.title, str(b.item_id) if b else "bench?", off, str(sitter.anim_override)],
		sat and sitter.anim_override == "SitIdle" and b != null and (absf(off - tf.BENCH_END) < 0.08 if str(b.item_id) == "bench" else off < 0.08))
	tf._end_activity(second)
	tf.sit_on_bench(second)
	var whos: Array = tf._benches.values()
	var uniq := {}
	for w in whos:
		uniq[w] = true
	m._check("townsfolk: two never take the same end of a bench (%d ends taken by %d people)" % [whos.size(), uniq.size()],
		whos.size() >= 2 and uniq.size() == whos.size() and second in whos)
	if b != null:
		m.player.position = b.global_position + b.front() * 2.2 + Vector3(1.5, 0, 0)
		_look(b.global_position, 6.5)
		await m._wait(1.6)
		await m._shot("64_townsfolk_bench.png")

	# the café: in for a coffee and a book, like the regulars
	_morning()
	var reader = out[2]
	_park([sitter, second, reader])
	tf._end_activity(reader)
	reader.home = reader.position
	var cv = m.cafe_visits
	var went: bool = tf.cafe_open() and cv.start(reader.vid)
	if went:
		reader.state = "cafe"
		reader.settle_at(cv.counter_spot(cv.visits[reader.vid]))
	var reading: bool = went and await _wait_for(func(): return cv.visits.has(reader.vid) and str(cv.visits[reader.vid]["state"]) == "reading", 40.0)
	m._check("townsfolk: %s drops into the café, orders, and sits down with a book (%s, %s)" % [reader.title, str(cv.visits.get(reader.vid, {}).get("state", "-")), str(reader.anim_override)],
		reading and reader.anim_override == "SitIdle")
	if reading:
		m.player.position = cv.counter_spot(cv.visits[reader.vid])
		_look(reader.position, 6.0)
		await m._wait(1.6)
		await m._shot("64_townsfolk_cafe.png")

	# talking: one short line, fitting who they are
	var kid_lines := {}
	var adult_lines := {}
	for i in 20:
		kid_lines[tf.line_for(kid)] = true
		adult_lines[tf.line_for(man)] = true
	m._check("townsfolk: a child never says the wife line and a grown-up never shouts STRANGER DANGER (%d and %d lines heard)" % [kid_lines.size(), adult_lines.size()],
		kid_lines.size() >= 3 and adult_lines.size() >= 3 and not kid_lines.keys().any(func(l): return l.contains("wife"))
		and not adult_lines.keys().any(func(l): return l.contains("STRANGER")))
	var acts: Array = m._actions_for(man).map(func(a): return str(a["id"]))
	man.visible = true
	m._perform(man, "talk") # as a click on them does
	await m._wait(0.3)
	var hit: bool = man.find_children("*", "StaticBody3D", false, false).any(func(c): return c.get_meta("target", null) == man)
	m._check("townsfolk: their menu is Talk, and a sweater row only when they want one (%s); a click on them finds them (%s)" % [str(acts), str(hit)],
		(acts == ["talk"] or acts == ["talk", "sale"]) and hit)
	m._check("townsfolk: Talk shows one of their lines (%s: \"%s\")" % [str(m.hud.dlg_name.text), str(m.hud.dlg_text.text)],
		m.hud.dlg_panel.visible and (str(m.hud.dlg_text.text) in lines or (tf.wants(man) and (_want_lines(tf, "none") + _want_lines(tf, "has")).has(str(m.hud.dlg_text.text)))))
	m.hud.hide_dialogue()

	# wanting a sweater: the red pin, the sale row, the haggle panel, and the pin gone once sold
	_morning()
	var buyer = out[3]
	tf._end_activity(buyer)
	buyer.state = "idle"
	buyer.until = tf.now_h() + 5.0 # stands still for the picture
	Game.set_flag("tf_want_" + buyer.vid, Game.day)
	await m._wait(0.8)
	var pin := buyer.get_node_or_null("SweaterPin") as Sprite3D
	# the bob is abs(sin(t * 3.2)), about a second round: two samples can straddle a peak or a trough
	# and read the same, so watch a whole bob and take its lowest and highest
	var y0: float = pin.position.y if pin else 0.0
	var y1: float = y0
	for i in 8:
		await m._wait(0.13)
		var y: float = pin.position.y if pin else 0.0
		y0 = minf(y0, y)
		y1 = maxf(y1, y)
	m._check("townsfolk: %s wants a sweater, and a red pin floats over their head and bobs (%.2f -> %.2f m)" % [buyer.title, y0, y1],
		pin != null and pin.visible and y0 > 1.0 and absf(y1 - y0) > 0.001)
	var others_pinned: Array = people.filter(func(p): return p != buyer and p.get_node_or_null("SweaterPin") != null and p.get_node("SweaterPin").visible and not tf.wants(p))
	m._check("townsfolk: nobody who doesn't want one has a pin (%d)" % others_pinned.size(), others_pinned.is_empty())
	m.player.position = buyer.position + Vector3(1.6, 0, 1.6)
	_look(buyer.position + Vector3(0, 1.0, 0), 5.0)
	await m._wait(1.4)
	await m._shot("64_townsfolk_pin.png")
	# Talk says what they're after while the pin is up (Alex, 2026-11-24), not the usual banter
	var held: Array = []
	while Game.count("sweater") > 0: # none on her first: they ask her to come back with one
		held.append(Game.remove_sweater(0))
	m._perform(buyer, "talk")
	await m._wait(0.3)
	var said_none := str(m.hud.dlg_text.text)
	m.hud.hide_dialogue()
	Game.add_sweater(1, "")
	m._perform(buyer, "talk")
	await m._wait(0.3)
	var said_has := str(m.hud.dlg_text.text)
	m.hud.hide_dialogue()
	m._check("townsfolk: with the pin up, Talk says they want a sweater (none on her: \"%s\"; one on her: \"%s\")" % [said_none, said_has],
		_want_lines(tf, "none").has(said_none) and _want_lines(tf, "has").has(said_has) and not (said_none in lines))
	var rows: Array = m._actions_for(buyer)
	var sale_row: Array = rows.filter(func(a): return str(a["id"]) == "sale")
	m._check("townsfolk: their menu has Talk and a sweater row (%s)" % str(rows.map(func(a): return a["label"])),
		rows.size() == 2 and sale_row.size() == 1 and bool(sale_row[0]["enabled"]))
	m._perform(buyer, "sale")
	await m._wait(0.3)
	var panel: bool = m.sale.visible
	m.sale.force_roll = 0.0
	var res: String = m.sale.offer()
	m.sale.force_roll = -1.0
	await m._wait(0.8)
	m._check("townsfolk: the haggle panel opens (%s) and they buy it (%s); the pin is gone" % [str(panel), res],
		panel and res == "sold" and not pin.visible and not tf.wants(buyer))
	m.sale.close()
	m.hud.hide_dialogue()
	for h in held: # hers back, as she had them
		Game.add_sweater(int(h["rarity"]), str(h["design"]))
		Game.sweater_fibres[Game.sweater_fibres.size() - 1] = str(h["fibre"])

	# a local with a request for her wears the gold star and the pin, the pin above
	Game.set_flag("act1_done", true)
	var defs: Array = m.empire.request_defs()
	var asker = m._villager(str(defs[0]["who"])) if not defs.is_empty() else null
	if asker:
		Game.friend(asker.vid)["familiarity"] = 20 * int(defs[0].get("hearts", 0)) + 20
	await m._wait(1.2)
	var apin := asker.get_node_or_null("SweaterPin") as Sprite3D if asker else null
	var astar := asker.get_node_or_null("NewTalk") as Sprite3D if asker else null
	m._check("townsfolk: %s, with a request for her, has the gold star and the red pin above it (pin %.2f m, star %.2f m)" % [asker.title if asker else "?", apin.position.y if apin else -1.0, astar.position.y if astar else -1.0],
		apin != null and astar != null and apin.visible and astar.visible and apin.position.y > astar.position.y + 0.3)
	if asker:
		m.player.position = asker.global_position + Vector3(0.9, 0, 0.9) # beside them, inside their shop, so its walls come down
		_look(asker.global_position + Vector3(0, 1.4, 0), 6.0)
		await m._wait(1.4)
		await m._shot("64_townsfolk_star_pin.png")
	Game.friends = friends0.duplicate(true)

	# a named villager looking for a sweater today wears the pin too
	_morning()
	var wren = m._villager("wren")
	var yes_day := -1
	for d in range(day0, day0 + 60):
		Game.day = d
		if SweaterSale.looking("wren") and not SweaterSale.bought_today("wren"):
			yes_day = d
			break
	Game.day = yes_day if yes_day > 0 else day0
	await m._wait(0.8)
	var wpin := wren.get_node_or_null("SweaterPin") as Sprite3D
	var star := wren.get_node_or_null("NewTalk") as Node3D
	var clear := wpin != null and (star == null or not star.visible or wpin.position.y > star.position.y + 0.3)
	m._check("townsfolk: Wren, looking for a sweater today (day %d), has the red pin too (pin %.2f m, star %s)" % [yes_day, wpin.position.y if wpin else -1.0, ("%.2f m" % star.position.y) if star and star.visible else "off"],
		yes_day > 0 and wpin != null and wpin.visible and clear)
	m.player.position = wren.global_position + Vector3(0.9, 0, 0.9)
	_look(wren.global_position + Vector3(0, 1.4, 0), 6.0)
	await m._wait(1.4)
	await m._shot("64_townsfolk_villager_pin.png")
	if m.Story.find_trigger("talk", "wren") == "" and m.Jobs.offer_scene("wren") == "":
		m._perform(wren, "talk")
		await m._wait(0.3)
		var wsaid := str(m.hud.dlg_text.text)
		m.hud.hide_dialogue()
		m._check("townsfolk: Wren, with the pin up, says she's after a sweater when talked to (\"%s\")" % wsaid,
			(_want_lines(tf, "none") + _want_lines(tf, "has")).has(wsaid))
	Game.day = day0
	await m._wait(0.6)
	m._check("townsfolk: on a day she isn't looking, no pin over Wren", wpin == null or not wpin.visible or SweaterSale.looking("wren"))

	# a story scene sends everyone out of shot, and its end brings them back
	_morning()
	tf._on_scene_started("test")
	var gone: bool = people.all(func(p): return not p.visible and p.state == "away")
	tf._on_scene_finished("test")
	var back: int = people.filter(func(p): return p.state != "away").size()
	m._check("townsfolk: a story scene clears them out of shot (%s) and they're back after it (%d about)" % [str(gone), back],
		gone and back == mini(max_out, people.size()))

	# far from her and the camera: hidden and still
	_morning()
	m.player.position = Vector3(-30, 0, 2.5) # west of the farm, well past CULL from every corner of town
	_look(m.player.position, 16.0)
	await m._wait(3.0)
	var shown: Array = people.filter(func(p): return p.visible or p.process_mode != Node.PROCESS_MODE_DISABLED)
	m._check("townsfolk: out past the farm, the town's people are hidden and stop thinking (%d still on)" % shown.size(), shown.is_empty())

	# dusk: they walk out of town, and the next morning they're back
	m.player.position = Vector3(Town.TOWN_ARRIVE)
	_look(m.player.position, 16.0)
	_morning()
	await m._wait(1.5)
	Game.hour = 20.2
	tf._last_now = tf.now_h() # not a jump of the clock: they see the hour come
	await m._wait(1.2)
	var states: Array = people.map(func(p): return str(p.state))
	m._check("townsfolk: at dusk everyone heads out of town (%s)" % str(states),
		states.all(func(s): return s in ["leaving", "away"]) and states.has("leaving") and tf._benches.is_empty()
		and not people.any(func(p): return cv.visits.has(p.vid)))
	Game.hour = 23.0 # a jump: everyone where the hour has them
	await m._wait(1.0)
	m._check("townsfolk: late at night nobody is about", people.all(func(p): return p.state == "away" and not p.visible))
	Game.day = day0 + 1
	Game.hour = 11.0
	await m._wait(1.0)
	m._check("townsfolk: the next morning they're back in town (%d about)" % people.filter(func(p): return p.state != "away").size(),
		people.filter(func(p): return p.state != "away").size() == mini(max_out, people.size()))
	Game.set_flag("tf_off", true)
	await m._wait(1.0)
	m._check("townsfolk: switched off (tf_off), nobody comes out", people.all(func(p): return p.state in ["leaving", "away"]))

	# clean up
	tf.clear()
	var left_pins: Array = m.villagers.filter(func(v): return v.get_node_or_null("SweaterPin") != null and not v.get_node("SweaterPin").is_queued_for_deletion())
	m._check("townsfolk: cleared, no pin is left over anyone (%d)" % left_pins.size(), left_pins.is_empty())
	await m._wait(0.3)
	Game.day = day0
	Game.hour = hour0
	Game.flags = flags0
	Game.friends = friends0
	Game.sweaters = sw0
	Game.sweater_designs = sd0
	Game.sweater_fibres = sf0
	Game.coins = coins0
	m.player.position = pos0
	m.hud.hide_dialogue()
	m._set_cam_lock(true)


## Every line of `key` in the data's "want_lines" (any speaker), as the dialogue box shows it.
func _want_lines(tf, key: String) -> Array:
	var out: Array = []
	var src: Variant = tf._cfg("want_lines", {})
	var names: Array = ["sheep's wool"] # {fibre}: whichever fibre they want today
	for f in (Data.load_json("wildlife").get("fibres", {}) as Dictionary):
		names.append(SweaterSale.fibre_name(str(f)))
	for l in ((src as Dictionary).get(key, []) if src is Dictionary else []):
		for n in names:
			out.append(str(l["text"]).format({"fibre": n}))
	return out
