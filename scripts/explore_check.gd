extends RefCounted
## --only=explore: the bigger world of 2026-11-26 (scripts/explore.gd, horse.gd, crabs.gd,
## data/explore.json, data/horse.json, the new lands in data/regions.json and their animals in
## data/wildlife.json). The huts and their chests, the treasure patches on open ground, digging one
## with the shovel (Gran's first, a refill one greening over again, a one-off staying dug), a chest's
## found needles lifting the needle floor, the Deep Mire out of reach until Steve's waders, the tent
## (pitched, a short night without a fire, every bar full with one, packed up), the horse (bought from
## Lars, G on and off, faster in the saddle, whistled over), the crabs digging in, the far lands'
## animals and their fibres only wanted once seen, and the save keeping it all.
## Saves 75_explore_*.png. Leaves the flags, her things, the coins and where she stood as it found them.

const EmpireGoals = preload("res://scripts/empire_goals.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Town = preload("res://scripts/town.gd")

var m: Node


func _look(at: Vector3, dist: float, pitch: float, secs := 2.0) -> void:
	m.player.position = m._open_near(at, 3.0) if not m._walkable(m._cell(at)) else at
	m.cam_glide = {"pos": at, "dist": dist, "pitch": pitch}
	await m._wait(secs)


## Whether a walk from `a` gets all the way to `b` (_find_path gives a partial path to an unreachable goal).
func _reaches(a: Vector3, b: Vector3) -> bool:
	var path: Array = m._find_path(a, b)
	return not path.is_empty() and Vector2((path[path.size() - 1] as Vector3).x - b.x, (path[path.size() - 1] as Vector3).z - b.z).length() < 1.2


func run(main: Node) -> void:
	m = main
	var ex = m.explore
	var keep := {"flags": Game.flags.duplicate(true), "inv": Game.inv.duplicate(true), "coins": Game.coins, "day": Game.day,
		"hour": Game.hour, "energy": Game.energy, "fullness": Game.fullness, "happiness": Game.happiness, "warmth": Game.warmth,
		"clock": Game.time_running, "pos": m.player.position}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	Game.flags.erase("explore")
	Game.flags.erase("tent")
	Game.flags.erase("horse")
	Game.inv.erase("waders")
	Game.inv.erase("tent")
	for id in ex.needle_defs():
		Game.inv.erase(str(id))
	m._rebuild_grid()
	ex.apply()
	# --- the huts and their chests
	var kinds := {}
	for h in ex.huts:
		kinds[str(h[1].get("kind", ""))] = int(kinds.get(str(h[1].get("kind", "")), 0)) + 1
	var listed: int = Town.built.filter(func(b): return ex.huts.any(func(h): return h[0] == b[0])).size()
	var solid: bool = ex.huts.all(func(h): return not m._walkable(m._cell((h[0] as Node3D).global_position)))
	m._check("the huts stand (%s), each in the world editor (%d) and solid on the walking grid (%s), with %d chests" % [str(kinds), listed, str(solid), ex.chests.size()],
		int(kinds.get("beach_hut", 0)) == 5 and kinds.has("stilt_hut") and kinds.has("ruin") and kinds.has("bothy") and listed == ex.huts.size() and solid and ex.chests.size() == 4)
	var open_chests: bool = ex.chests.all(func(c): return m._walkable(m._cell(c.global_position + c.global_transform.basis.z * 0.9)))
	m._check("every chest can be walked up to", open_chests)
	# --- the patches
	var on_open: bool = ex.patches.all(func(p): return m._walkable(m._cell(p.position)))
	m._check("%d treasure patches, each on open ground" % ex.patches.size(), ex.patches.size() == (ex.data.get("patches", []) as Array).size() and on_open)
	var mire_p = ex.patches.filter(func(p): return p.id == "deep_mire")
	var mire_hut = ex.huts.filter(func(h): return str(h[1].get("id", "")) == "mire_hut")
	var farm := Vector3(10, 0, -3)
	var no_way: bool = not mire_p.is_empty() and not _reaches(farm, mire_p[0].position)
	m._check("without waders the Deep Mire's island can't be reached (its patch: %s)" % ("no path" if no_way else "a path!"), no_way and m.regions.mire_zone(mire_p[0].position.x, mire_p[0].position.z) == 0)
	# --- digging: Gran's first, with the shovel
	Game.add_item("shovel", 1)
	var gran = ex.patches.filter(func(p): return p.id == "gran_first")[0]
	await _look(gran.position + Vector3(0, 0, 2.5), 6.0, 40.0)
	await m._shot("75_explore_patch.png")
	var acts: Array = m._actions_for(gran)
	var c0 := Game.coins
	var used: bool = m._tool_click("shovel", gran, Vector2.ZERO)
	var waited := 0.0
	while ex.can_dig(gran) and waited < 10.0:
		await m._wait(0.25)
		waited += 0.25
	m._check("a click with the shovel digs Gran's first patch (menu '%s'; %.1f s): +%dc, her note, and it's dug" % [str(acts[0]["label"]) if not acts.is_empty() else "?", waited, Game.coins - c0],
		used and not acts.is_empty() and acts[0]["id"] == "dig" and Game.coins - c0 == 40 and not ex.can_dig(gran) and m.hud.dlg_panel.visible)
	m.hud.hide_dialogue()
	# a refill patch and a one-off
	var refill = ex.patches.filter(func(p): return p.refill > 0)[0]
	var once = ex.patches.filter(func(p): return p.refill == 0 and p.id != "gran_first" and p.id != "deep_mire")[0]
	var before := Game.inv.duplicate(true)
	var c1 := Game.coins
	ex.dug(refill)
	ex.dug(once)
	var got: bool = Game.coins > c1 or Game.inv.hash() != before.hash()
	var day0 := Game.day
	Game.day = day0 + refill.refill
	ex.refresh()
	m._check("digging gives something (%s); after %d days %s greens over again, %s stays dug" % [str(got), refill.refill, refill.id, once.id],
		got and ex.can_dig(refill) and not ex.can_dig(once) and refill.green.visible and not once.green.visible)
	Game.day = day0
	ex.refresh()
	# --- a chest's found needles
	var floor0: int = m.empire.needle_floor()
	var beach_chest = ex.chests.filter(func(c): return c.hut_id == "beach_hut_5")[0]
	await _look(beach_chest.global_position + Vector3(0, 0, -3.0), 16.0, 30.0)
	await m._shot("75_explore_beach_huts.png")
	ex.open_chest(beach_chest)
	m._check("the beach hut's chest holds driftwood needles: the floor goes %d -> %d (%s), and it stays empty" % [floor0, m.empire.needle_floor(), m.empire.needle_name()],
		Game.has_item("driftwood_needles") and m.empire.needle_floor() == maxi(floor0, 2) and beach_chest.is_open() and m._actions_for(beach_chest)[0]["id"] == "noop")
	# --- Steve's waders open the Deep Mire
	var steve = m._villager("steve")
	var rows: Array = m._villager_actions(steve).map(func(a): return str(a["id"]))
	m._check("Steve sells waders and a tent (%s)" % str(rows.filter(func(r): return r.begins_with("ex_"))), rows.has("ex_waders") and rows.has("ex_tent"))
	Game.coins = 5000
	m._villager_action(steve, "ex_waders")
	await m._wait(0.3)
	var way: bool = _reaches(farm, mire_p[0].position)
	m._check("with waders the island is reachable: its patch, its hut's chest", Game.has_item("waders") and way
		and _reaches(farm, m._open_near(ex.chests.filter(func(c): return c.hut_id == "mire_hut")[0].global_position, 1.0)))
	await _look((mire_hut[0][0] as Node3D).global_position + Vector3(0, 0, -4.0), 12.0, 32.0)
	await m._shot("75_explore_mire_hut.png")
	# the far huts
	for h in ex.huts:
		var kind := str(h[1].get("kind", ""))
		if kind == "ruin" or kind == "bothy":
			await _look((h[0] as Node3D).global_position + (h[0] as Node3D).global_transform.basis.z * 4.0, 12.0, 30.0, 2.5)
			await m._shot("75_explore_%s.png" % kind)
	# --- the tent
	m._villager_action(steve, "ex_tent")
	var spot: Vector3 = m._open_near(Vector3(-9.0, 0, 6.0), 2.0)
	var trows: Array = m.ground_actions(spot).map(func(a): return str(a["label"]))
	ex.pitch(spot, 0.0)
	await m._wait(0.3)
	var tacts: Array = m._actions_for(ex.tent).map(func(a): return str(a["label"])) if ex.tent else []
	m._check("bought, the tent pitches from the ground ring (%s) and has its menu (%s)" % [str(trows.filter(func(l): return l.begins_with("Pitch"))), str(tacts)],
		trows.has("Pitch your tent here") and ex.tent != null and Game.flags.has("tent") and not Game.has_item("tent") and tacts.size() == 2)
	Game.energy = 20.0
	Game.hour = 22.0
	await ex.sleep_in_tent()
	var short := Game.energy
	Game.hour = 22.0
	var f = m.bonfire.light(ex.tent.position + Vector3(2.6, 0, 1.0))
	Game.energy = 20.0
	Game.fullness = 30.0
	Game.happiness = 30.0
	Game.warmth = 30.0
	var full: bool = ex.fire_by_tent()
	await _look(ex.tent.position + Vector3(0, 0, 3.0), 7.0, 28.0, 2.5)
	await m._shot("75_explore_tent.png")
	await ex.sleep_in_tent()
	m._check("in the tent without a fire: %.0f energy (20 + %.0f); with a bonfire by it (%s) every bar is full (%.0f %.0f %.0f %.0f)" % [short, ex.tent_rest(), str(full), Game.energy, Game.fullness, Game.happiness, Game.warmth],
		is_equal_approx(short, 20.0 + ex.tent_rest()) and full and Game.energy >= 99.9 and Game.fullness >= 99.9 and Game.happiness >= 99.9 and Game.warmth >= 99.9)
	m.bonfire.put_out(f)
	ex.pack_up()
	m._check("packed up, the tent is back in her bag", Game.has_item("tent") and ex.tent == null and not Game.flags.has("tent"))
	# --- the horse
	var hz = m.horse
	var lars = m._villager("lars")
	var lrows: Array = m._villager_actions(lars).map(func(a): return str(a["id"]))
	Game.hour = 11.0
	m.player.position = m._open_near(Vector3(14.0, 0, 4.0), 1.0)
	m._villager_action(lars, "horse_buy")
	await m._wait(0.3)
	m._check("Lars sells a horse (%s): bought, she stands by Nora" % str(lrows.filter(func(r): return r.begins_with("horse"))),
		lrows.has("horse_buy") and hz.owned and hz.visible and Game.flags.has("horse") and hz.position.distance_to(m.player.position) < 4.5)
	hz.key()
	m._check("G beside her: Nora rides (x%.1f speed, sat in the saddle)" % m.player.ride_mult, hz.riding and m.player.riding and m.player.ride_mult > 2.0)
	var start: Vector3 = m.player.position
	var dest: Vector3 = m._open_near(start + Vector3(-24.0, 0, 0), 1.0)
	m.player.walk(m._find_path(start, dest))
	var t0 := Time.get_ticks_msec()
	waited = 0.0
	while not m.player.path.is_empty() and waited < 20.0:
		await m._wait(0.2)
		waited += 0.2
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var ride_speed: float = start.distance_to(m.player.position) / maxf(secs, 0.01)
	await _look(m.player.position, 6.0, 22.0, 0.8)
	await m._shot("75_explore_horse.png")
	m._check("riding she covers ground at %.1f m/s (her walk is %.1f), the horse under her" % [ride_speed, m.player.walk_speed],
		ride_speed > m.player.walk_speed * 1.6 and hz.position.distance_to(m.player.position) < 0.1)
	hz.key()
	m._check("G again: she's off, standing beside her", not hz.riding and not m.player.riding and is_equal_approx(m.player.ride_mult, 1.0))
	m.player.position = m._open_near(hz.position + Vector3(20.0, 0, 0), 1.0)
	hz.key()
	waited = 0.0
	while not hz._coming.is_empty() and waited < 15.0:
		await m._wait(0.25)
		waited += 0.25
	m._check("from 20 m off, G whistles her over (%.1f s, %.1f m off now)" % [waited, hz.position.distance_to(m.player.position)], hz._coming.is_empty() and hz.position.distance_to(m.player.position) < 4.0)
	# a game without a horse, loaded while she rides: on foot, at her own speed, no horse about
	hz.key()
	var horse_flag = Game.flags.get("horse")
	var mounted: bool = hz.riding and m.player.riding
	Game.flags.erase("horse")
	hz.apply()
	await m._wait(1.2)
	m._check("a horseless game loaded while she rides: on foot at her own speed, no horse (was riding: %s)" % str(mounted),
		mounted and not hz.owned and not hz.visible and not m.player.riding and is_equal_approx(m.player.ride_mult, 1.0) and not Game.flags.has("horse"))
	Game.flags["horse"] = horse_flag
	hz.apply()
	# --- the far lands' animals, the crabs, and who wants their fibre
	m.wildlife.build()
	await m._wait(0.6)
	var lands := {}
	for a in m.wildlife.animals:
		var land := str(a.info.get("land", ""))
		if land != "":
			lands[land] = int(lands.get(land, 0)) + 1
	m._check("the far lands have their own animals (%s)" % str(lands), lands.has("dunes") and lands.has("downs") and lands.has("swamp") and lands.has("beach"))
	Game.flags.erase("guide")
	var closed: bool = not EmpireGoals.fibre_open("vicuna_fibre") and EmpireGoals.fibre_open("fox_fibre")
	EmpireGoals.mark("vicuna", "seen")
	m._check("nobody asks for vicuna before she has seen one (%s), and they may once she has" % str(closed), closed and EmpireGoals.fibre_open("vicuna_fibre"))
	Game.flags.erase("guide")
	var crabs: Array = m.wildlife.crabs
	if not crabs.is_empty():
		var g: Node3D = crabs[0]
		await _look(g.global_position + Vector3(0, 0, -6.0), 7.0, 30.0, 1.5)
		await m._shot("75_explore_crabs.png")
		var b0: int = g.burrows
		m.player.position = g.global_position + Vector3(0.3, 0, 0.2)
		await m._wait(3.0)
		m._check("crabs on the beach (%d groups) dig in when she walks among them (%d)" % [crabs.size(), g.burrows - b0], g.burrows > b0)
	else:
		m._check("crabs on the beach", false)
	for spot2 in [[Vector3(200, 0, 20), "75_explore_dunes.png"], [Vector3(200, 0, -55), "75_explore_downs.png"]]:
		var w: Vector3 = spot2[0]
		await _look(w, 34.0, 34.0, 2.5)
		await m._shot(spot2[1])
	# --- the save keeps it
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	var sf: Dictionary = saved.get("flags", {})
	m._check("the save keeps what she dug and opened, and her horse (%s)" % str((sf.get("explore", {}) as Dictionary).get("dug", {}).keys()),
		(sf.get("explore", {}) as Dictionary).get("dug", {}).has("gran_first") and (sf.get("explore", {}) as Dictionary).get("opened", {}).has("beach_hut_5") and sf.has("horse"))
	# --- put it all back
	m.wildlife.clear()
	Game.flags = keep["flags"]
	Game.inv = keep["inv"]
	Game.coins = int(keep["coins"])
	Game.day = int(keep["day"])
	Game.hour = float(keep["hour"])
	for k in ["energy", "fullness", "happiness", "warmth"]:
		Game.set(k, float(keep[k]))
	Game.time_running = bool(keep["clock"])
	hz.apply()
	ex.apply()
	m._rebuild_grid()
	m.player.position = keep["pos"]
	m.cam_glide = {}
	m.cam_target = m.player.position
	m.hud.hide_dialogue()
