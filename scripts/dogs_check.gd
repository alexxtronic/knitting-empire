extends RefCounted
## --only=dogs: more dogs (scripts/kennel.gd, data/economy.json "dogs", data/wildlife.json
## herd_per_dog). No "Buy a dog" on Lars's menu in Act 1; in Act 2 three dogs bought at the rising
## prices; the thirteenth refused; the herd limit with 1, 2 and 4 dogs; the pack following Nora,
## then the dog she plays; one bark from him adding the fright of each pack dog near enough (and
## none from one too far off), and a pack dog's bark taking a wolf's nerve; a pack dog never moving toward an animal by itself; a knitted scarf
## on a pack dog, one copy a dog; coats tinted apart; all of it through a save and load.
## Saves 74_dogs_pack.png and 74_dogs_coats.png. Leaves the act, the flags, her coins, the dogs
## and the wild animals as it found them.

const Wildlife = preload("res://scripts/wildlife.gd")

var m: Node


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _rows(lars) -> Array:
	return m._villager_actions(lars).filter(func(r): return str(r["label"]).begins_with("Buy a dog") or str(r["id"]) == "dog_buy" or str(r.get("group", "")) == "Dogs")


## The fright one bark adds at distance d (wildlife.barked's falloff).
func _gain(d: float) -> float:
	if d > Wildlife.BARK_RANGE:
		return 0.0
	return lerpf(1.0, Wildlife.BARK_FAR_GAIN, smoothstep(Wildlife.BARK_NEAR, Wildlife.BARK_RANGE, d))


func _walk_to(who: Node3D, to: Vector3, limit: float) -> void:
	who.walk(m._find_path(who.position, to))
	var t := 0.0
	while not who.path.is_empty() and t < limit:
		await m._wait(0.2)
		t += 0.2


## Waits (up to `limit` s) for the pack to stop moving.
func _settle(k: Node, limit: float) -> void:
	var t := 0.0
	await m._wait(1.0)
	while t < limit and k.pack.any(func(d): return d.speed > 0.05 or not d.path.is_empty()):
		await m._wait(0.2)
		t += 0.2


func run(main: Node) -> void:
	m = main
	var k: Node = m.kennel
	var lars = m._villager("lars")
	var keep := {"flags": Game.flags.duplicate(true), "coins": Game.coins, "act": Game.act, "sheep": Game.sheep_count, "pos": m.player.position, "cd": m.cam_dist, "clock": Game.time_running, "hour": Game.hour}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	if k == null or lars == null:
		m._check("the dogs check has the kennel and Lars", false)
		return
	m.toggle_dog(false)
	Game.flags.erase("dogs")
	Game.flags.erase("dog_scarf")
	Game.flags.erase("dog_scarves")
	k.sync()
	# Act 1: no dogs for sale
	Game.act = 1
	var rows1: Array = _rows(lars)
	# Act 2: three dogs at the rising prices
	Game.act = 2
	Game.coins = 1000000
	var rows2: Array = _rows(lars)
	var paid: Array = []
	for i in 3:
		var c0 := Game.coins
		m._villager_action(lars, "dog_buy")
		m.hud.hide_dialogue()
		paid.append(c0 - Game.coins)
	var want: Array = [k.price_of(0), k.price_of(1), k.price_of(2)]
	m._check("Lars sells no dog in Act 1 (%d rows); in Act 2 he has '%s', and three dogs cost %s (the data's %s, each dearer), so she owns %d" % [rows1.size(), str(rows2[0]["label"]) if not rows2.is_empty() else "none", str(paid), str(want), k.count()],
		rows1.is_empty() and rows2.size() == 1 and rows2[0]["enabled"] and paid == want and int(want[1]) > int(want[0]) and int(want[2]) > int(want[1]) and k.count() == 4)
	await m._wait(0.4)
	# the thirteenth: refused
	var many: Array = []
	for i in k.max_dogs() - 1:
		many.append({"name": "Dog%d" % i, "coat": "cream"})
	Game.set_flag("dogs", many)
	var c1 := Game.coins
	var row12: Array = _rows(lars)
	var ok13: bool = k.buy()
	m.hud.toast_panel.visible = false
	m._check("with %d dogs a thirteenth is refused (row '%s' greyed %s, bought %s, coins %d -> %d, still %d)" % [k.max_dogs(), str(row12[0]["label"]) if not row12.is_empty() else "none", not row12.is_empty() and not row12[0]["enabled"], ok13, c1, Game.coins, k.count()],
		k.max_dogs() == 12 and not row12.is_empty() and not row12[0]["enabled"] and not ok13 and Game.coins == c1 and k.count() == 12)
	# the herd: two animals a dog
	var per := int(m.wildlife.data.get("herd_per_dog", 2))
	var herds := {}
	for n in [1, 2, 4]:
		var l: Array = []
		for i in n - 1:
			l.append({"name": "Dog%d" % i, "coat": "cream"})
		Game.set_flag("dogs", l)
		herds[n] = m.wildlife.max_herd()
	m._check("each dog herds %d: 1 dog %d, 2 dogs %d, 4 dogs %d" % [per, herds[1], herds[2], herds[4]],
		per == 2 and herds[1] == 2 and herds[2] == 4 and herds[4] == 8)
	# the pack follows Nora, then the dog she plays
	var five: Array = []
	var coats: Array = k.data.get("coat_order", [])
	for i in 5:
		five.append({"name": str(k.data["names"][i]), "coat": str(coats[i % coats.size()])})
	Game.set_flag("dogs", five)
	k.sync()
	var start: Vector3 = m._open_near(Vector3(9.0, 0, 8.0), 0.5)
	m.player.walk([])
	m.player.position = start
	m.dog.position = start + Vector3(1.2, 0, 0.8)
	m.dog.path = []
	for d in k.pack:
		d.position = start + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-3.0, -1.0))
	m.cam_target = start
	m._set_cam_lock(true)
	await m._wait(0.5)
	var goal_n: Vector3 = m._open_near(start + Vector3(14.0, 0, 0), 1.0)
	await _walk_to(m.player, goal_n, 15.0)
	await m._wait(2.5)
	var near_nora: Array = k.pack.map(func(d): return snappedf(_flat(d.position, m.player.position), 0.1))
	var behind := 0
	for d in k.pack:
		var rel: Vector3 = d.position - m.player.position
		if rel.dot(m.player.global_transform.basis.z) < 0.3:
			behind += 1
	m._check("the pack follows Nora on foot (%d dogs, %s m from her after a %.0f m walk, %d of them behind her)" % [k.pack.size(), str(near_nora), _flat(start, goal_n), behind],
		k.pack.size() == 5 and near_nora.all(func(x): return x < 6.5) and behind >= 4)
	m.toggle_dog(true)
	m.hud.toast_panel.visible = false
	var goal_d: Vector3 = m._open_near(m.dog.position + Vector3(-14.0, 0, 6.0), 1.0)
	m.dog.walk(m._find_path(m.dog.position, goal_d))
	var tw := 0.0
	var shot := false
	while not m.dog.path.is_empty() and tw < 15.0:
		await m._wait(0.2)
		tw += 0.2
		var mid := Vector3.ZERO
		for d in k.pack:
			mid += d.position / k.pack.size()
		m.cam_target = m.dog.position.lerp(mid, 0.45)
		if not shot and tw > 5.0:
			shot = true
			m.cam_dist = 11.0
			await m._shot("74_dogs_pack.png")
	await _settle(k, 6.0)
	for d in k.pack: # what each one is doing, should the check below fail
		print("DOGS pack %s at %s, place %s (open %s), path %d, speed %.2f, lod %.0f" % [d.pack_name, str(d.position.snapped(Vector3.ONE * 0.1)), str(d._slot_point().snapped(Vector3.ONE * 0.1)), m._walkable(m._cell(d._slot_point())), d.path.size(), d.speed, d.lod_hz])
	var near_dog: Array = k.pack.map(func(d): return snappedf(_flat(d.position, m.dog.position), 0.1))
	var closer: int = k.pack.filter(func(d): return _flat(d.position, m.dog.position) < _flat(d.position, m.player.position)).size()
	m._check("playing the dog, the pack follows him (%s m from him, %d of 5 nearer him than Nora, %.1f m off)" % [str(near_dog), closer, _flat(m.dog.position, m.player.position)],
		near_dog.all(func(x): return x < 6.5) and closer == 5 and _flat(m.dog.position, m.player.position) > 8.0)
	# one bark: each pack dog near enough adds its own fright
	Game.sheep_count = 0 # room in the pen
	Game.flags.erase("penned")
	Game.flags.erase("wild_gone")
	m.wildlife.build()
	await m._wait(0.4)
	var hard: Array = m.wildlife.animals.filter(func(a): return not a.penned and m.wildlife.barks_for(a) >= 5.0)
	if hard.size() < 3:
		m._check("there are three wild animals that take five barks or more (%d)" % hard.size(), false)
	else:
		Game.set_flag("dogs", five.slice(0, 2))
		k.sync()
		await m._wait(0.3)
		var a_dog = k.pack[0]
		var b_dog = k.pack[1]
		await m._wait(m.dog.BARK_EVERY + 0.1)
		var p: Vector3 = m.dog.position
		var x = hard[0] # by pack dog A, out of the played dog's reach
		var w = hard[1] # between him and A: both reach it
		var y = hard[2] # by pack dog B, who is too far off to bark
		a_dog.position = p + Vector3(6.0, 0, 0)
		b_dog.position = p + Vector3(-20.0, 0, 0)
		x.position = p + Vector3(9.5, 0, 0)
		w.position = p + Vector3(2.5, 0, 0)
		y.position = p + Vector3(-22.0, 0, 0)
		for a in [x, w, y]:
			a.fright = 0.0
			a.caught = false
			a.fleeing = 0.0
			a.visible = true
		var ab0: int = a_dog.barks
		var bb0: int = b_dog.barks
		var barked: bool = m.dog_bark()
		var pw: float = a_dog.bark_power()
		var want_x: float = _gain(3.5) * pw / m.wildlife.barks_for(x)
		var want_w: float = (_gain(2.5) * m.dog.bark_power() + _gain(3.5) * pw) / m.wildlife.barks_for(w)
		m._check("one bark from the dog she plays (%s): pack dog A 6 m off barks too (%d), B 20 m off doesn't (%d); A's bark frightens the animal by it (%.3f, want %.3f) that his can't reach, the one between them takes both (%.3f, want %.3f), and the one by B none (%.3f)" % [barked, a_dog.barks - ab0, b_dog.barks - bb0, x.fright, want_x, w.fright, want_w, y.fright],
			barked and a_dog.barks - ab0 == 1 and b_dog.barks - bb0 == 0 and absf(x.fright - want_x) < 0.01 and absf(w.fright - want_w) < 0.01 and y.fright == 0.0 and x.fright > 0.0)
		# wolves: a pack dog's bark takes their nerve too
		m.wolves.start_raid(3)
		m.hud.toast_panel.visible = false
		await m._wait(0.1)
		var bigs: Array = m.wolves.pack.filter(func(wf): return wf.size_id == "large")
		if bigs.is_empty():
			m._check("a forced wolf night has the large wolf", false)
		else:
			var big = bigs[0]
			var wr := float(m.wolves.num("bark_range", 10.0))
			await m._wait(m.dog.BARK_EVERY + 0.1)
			var q: Vector3 = m.dog.position
			for wf in m.wolves.pack:
				wf.position = q + Vector3(0, 0, 40.0) # the others well away
				wf._path = []
			big.position = q + Vector3(wr + 2.0, 0, 0) # beyond his bark
			big._path = []
			a_dog.position = big.position + Vector3(-2.0, 0, 0) # beside it, and near him
			var nerve0: int = big.nerve
			m.dog_bark()
			var nerve1: int = big.nerve
			await m._wait(m.dog.BARK_EVERY + 0.1)
			a_dog.position = q + Vector3(-30.0, 0, 0)
			big.position = q + Vector3(wr + 2.0, 0, 0)
			m.dog_bark()
			var nerve2: int = big.nerve
			m._check("a pack dog's bark takes a wolf's nerve: the large one %.0f m from the dog she plays, %d -> %d with pack dog A beside it, and %d -> %d with A away" % [wr + 2.0, nerve0, nerve1, nerve1, nerve2],
				nerve0 >= 2 and nerve1 == nerve0 - 1 and nerve2 == nerve1)
		m.wolves.clear()
		# a pack dog never goes after an animal by itself
		m.toggle_dog(false)
		m.hud.toast_panel.visible = false
		m.player.walk([])
		m.dog.path = []
		await _settle(k, 8.0)
		var a0: Vector3 = a_dog.position
		x.position = a0 + Vector3(2.5, 0, 0.5)
		x.fright = 0.0
		x.fleeing = 0.0
		x.hold(10.0)
		var d0 := _flat(a0, x.position)
		await m._wait(3.0)
		var moved := _flat(a_dog.position, a0)
		var d1 := _flat(a_dog.position, x.position)
		var herder: bool = m.homestead.herders.has(a_dog)
		m._check("a pack dog never goes after an animal by himself: with one %.1f m off he stays at his place (moved %.2f m, %.1f m from it after), frightens nothing (fright %.2f, threat %s) and herds nothing (%s)" % [d0, moved, d1, x.fright, str(m.wildlife.threat_to(x)), herder],
			moved < 0.4 and d1 >= d0 - 0.4 and x.fright <= 0.0 and m.wildlife.threat_to(x) == null and not herder)
	m.wildlife.clear()
	# a scarf of her own for a pack dog: one copy a dog
	Game.set_flag("dogs", five)
	k.sync()
	await m._wait(0.3)
	Game.set_flag("dog_scarves", [{"q": 3, "fibre": "", "n": 1}])
	var pd = k.pack[0]
	var rows_pd: Array = m._actions_for(pd)
	m._perform(pd, "scarf_on:0")
	await m._wait(0.2)
	var rows_main: Array = m._actions_for(m.dog).filter(func(r): return str(r["id"]) == "scarf_on:0")
	var rows_pd2: Array = m._actions_for(k.pack[1]).filter(func(r): return str(r["id"]) == "scarf_on:0")
	m._check("a pack dog's menu puts her scarf on him ('%s'): he wears it (scarf %d, bark ×%.2f), and with one copy it's greyed for her first dog (%s) and the next (%s)" % [str(rows_pd[0]["label"]) if not rows_pd.is_empty() else "none", pd.scarf_q, pd.bark_power(), str(rows_main.map(func(r): return r["enabled"])), str(rows_pd2.map(func(r): return r["enabled"]))],
		not rows_pd.is_empty() and pd.scarf_q == 3 and pd.bark_power() > 1.0 and m.dog.scarf_q == 0 and rows_main.size() == 1 and not rows_main[0]["enabled"] and rows_pd2.size() == 1 and not rows_pd2[0]["enabled"])
	# their coats: each a colour of its own
	m.player.walk([])
	m.player.position = start
	m.dog.position = start + Vector3(-1.5, 0, 0)
	m.dog.path = []
	for i in k.pack.size():
		var d = k.pack[i]
		d.pack_leader = null
		d.path = []
		d.position = start + Vector3(-3.4 + i * 1.15, 0, 0.6 - i * 0.25)
		d.rotation.y = 0.35
	m.dog.position = start + Vector3(-1.2, 0, -0.8)
	m.cam_dist = 9.5
	k.frozen = true # they stand for the picture
	await m._wait(2.5) # the camera glides over and settles
	m.hud.toast_panel.visible = false
	await m._shot("74_dogs_coats.png")
	k.frozen = false
	var tints: Array = []
	for d in k.pack:
		tints.append(d.coat_key())
	var distinct := {}
	for t in tints:
		distinct[t] = true
	m._check("their coats are tinted apart (%s: %d colours for %d dogs)" % [str(tints), distinct.size(), k.pack.size()],
		distinct.size() == 5 and not tints.has(""))
	# a save and load keeps them
	var herd_was: int = m.wildlife.max_herd()
	var d := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	Game.flags.erase("dogs")
	await m._wait(0.4)
	var gone: int = k.pack.size()
	Game.from_dict(d)
	await m._wait(0.5)
	var back = k.by_name(str(five[0]["name"]))
	m._check("a save keeps the pack (%d with the flag gone, %d back, %s in his %s coat wearing scarf %d, herd %d of %d)" % [gone, k.pack.size(), str(five[0]["name"]), str(five[0]["coat"]), back.scarf_q if back != null else -1, m.wildlife.max_herd(), herd_was],
		gone == 0 and k.pack.size() == 5 and back != null and back.coat_id == str(five[0]["coat"]) and back.scarf_q == 3 and m.wildlife.max_herd() == herd_was and herd_was == 12)
	# as it was
	m.toggle_dog(false)
	m._set_cam_lock(true)
	Game.flags = keep["flags"]
	Game.coins = keep["coins"]
	Game.act = keep["act"]
	Game.sheep_count = keep["sheep"]
	Game.time_running = keep["clock"]
	Game.hour = keep["hour"]
	m.player.position = keep["pos"]
	m.cam_dist = keep["cd"]
	k.sync()
	m.scarves.update()
	await m._wait(0.3)
