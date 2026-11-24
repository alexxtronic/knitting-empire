extends RefCounted
## --only=goals: Act 1's sense of progress (scripts/empire_goals.gd, data/goals.json, field_guide.gd,
## lookbook.gd). No goals during Act 1; the first after act1_done; a goal met pays, logs its day and
## play time, and the next comes on; the save keeps them; the last sets act_ready; the Field Guide
## marking seen (near her), caught and combed through the wildlife's own calls; the Lookbook's count;
## the ledger counting by channel and rolling over at a new day, its morning card, and the 1,000c day
## reading it. Saves 70_goals.png, 70_field_guide.png, 70_lookbook.png and 70_ledger.png.
## Leaves the flags, the coins, the day, her things and the wildlife as it found them.

const EmpireGoals = preload("res://scripts/empire_goals.gd")
const Lookbook = preload("res://scripts/lookbook.gd")

var m: Node


func _ids(w: Array) -> Array:
	return w.map(func(g): return str(g["id"]))


func run(main: Node) -> void:
	m = main
	var g: Node = m.goals
	var keep := {"flags": Game.flags.duplicate(true), "day": Game.day, "hour": Game.hour, "coins": Game.coins, "clock": Game.time_running,
		"wardrobe": Game.wardrobe.duplicate(), "inv": Game.inv.duplicate(true), "pos": m.player.position}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	EmpireGoals.on = true
	for k in ["empire_goals", "empire_stats", "guide", "ledger", "act_ready", "act1_done"]:
		Game.flags.erase(k)
	# --- no goals during Act 1
	await m._wait(1.0)
	m._check("no goals during Act 1 (live %s, panel %s, done %d)" % [str(g.live()), str(g._panel.visible), (g.state()["done"] as Dictionary).size()],
		not g.live() and not g._panel.visible and (g.state()["done"] as Dictionary).is_empty() and (g.state()["base"] as Dictionary).is_empty())
	# --- the first goal once Act 1's guided part is done
	Game.set_flag("act1_done")
	await m._wait(1.0)
	var w: Array = _ids(g.window())
	var first_row := ""
	if g._rows.get_child_count() > 1:
		first_row = (g._rows.get_child(1) as Label).text
	m._check("after act1_done the list shows %s, first '%s'" % [str(w), first_row],
		g.live() and g._panel.visible and w == ["catch", "pen", "comb"] and first_row.contains("Catch a wild animal") and g.defs.size() >= 12 and str(g.defs[-1]["id"]) == "ready")
	m._check("every goal has a line, a check and a reward of 0 to 150c", g.defs.all(func(d): return str(d.get("line", "")) != "" and str(d.get("check", "")) != "" and int(d.get("reward", -1)) >= 0 and int(d.get("reward", 0)) <= 150))
	# --- a goal met pays and the next comes on (a caught animal)
	m.wildlife.build()
	await m._wait(0.6)
	var c0 := Game.coins
	var secs0 := int(float(Game.flags.get("play_secs", 0.0)))
	var near: Node3D = null
	for a in m.wildlife.animals:
		if near == null or a.global_position.distance_to(m.player.global_position) < near.global_position.distance_to(m.player.global_position):
			near = a
	EmpireGoals.mark(near.species, "caught") # the call wildlife.frightened() makes (tested on its own below)
	await m._wait(1.0)
	var done: Dictionary = g.state()["done"]
	var entry: Dictionary = done.get("catch", {})
	w = _ids(g.window())
	m._check("catching a %s does the first goal: +%dc, logged day %s at %ss of play, and %s come on" % [near.species, Game.coins - c0, str(entry.get("day")), str(entry.get("secs")), str(w)],
		g.is_done("catch") and Game.coins - c0 == 20 and int(entry.get("day", 0)) == Game.day and int(entry.get("secs", -1)) >= secs0 and w == ["pen", "comb", "knit_fibre"])
	m.cam_target = m.player.position
	await m._wait(0.5)
	await m._shot("70_goals.png")
	# --- the save keeps them
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	Game.flags.erase("empire_goals")
	var lost: Array = _ids(g.window())
	Game.flags["empire_goals"] = (saved.get("flags", {}) as Dictionary).get("empire_goals", {})
	m._check("the save keeps the goals (cleared: %s; loaded: %s)" % [str(lost), str(_ids(g.window()))],
		lost[0] == "catch" and g.is_done("catch") and _ids(g.window()) == ["pen", "comb", "knit_fibre"])
	# --- the Field Guide: seen near her, caught and combed
	Game.flags.erase("guide")
	m.player.position = near.global_position + Vector3(6.0, 0.0, 0.0)
	m.player.walk([])
	await m._wait(1.2)
	var far := 0
	for a in m.wildlife.animals:
		if a.global_position.distance_to(m.player.position) > 40.0 and not EmpireGoals.guide_entry(a.species).has("seen"):
			far += 1
	m._check("a %s 6 m from her is seen (%s), animals far off aren't (%d)" % [near.species, str(EmpireGoals.guide_entry(near.species)), far],
		EmpireGoals.guide_entry(near.species).has("seen") and far > 0)
	var fur: bool = near.has_fur()
	m.wildlife.combed(near)
	m.wildlife.frightened(near)
	var e: Dictionary = EmpireGoals.guide_entry(near.species)
	m._check("combing (fur %s) and catching mark it combed %s and caught %s" % [str(fur), str(e.get("combed")), str(e.get("caught"))],
		(int(e.get("combed", 0)) >= 1 or not fur) and int(e.get("caught", 0)) >= 1)
	# a second species seen, caught and combed by the guide's own marks, a third only seen
	var others: Array = m.wildlife.data.get("animals", {}).keys().filter(func(id): return str(id) != near.species)
	EmpireGoals.mark(str(others[0]), "caught")
	EmpireGoals.mark(str(others[0]), "combed")
	EmpireGoals.mark(str(others[1]), "seen")
	m.hud.guide.call("open")
	var t := 0.0
	while (m.hud.guide.rendering or m.hud.guide.pics.is_empty()) and t < 20.0:
		await m._wait(0.2)
		t += 0.2
	await m._wait(0.3)
	var unseen := ""
	for id in m.wildlife.data.get("animals", {}):
		if not EmpireGoals.guide_entry(str(id)).has("seen"):
			unseen = str(id)
	var pic := m.hud.guide.find_child("Pic_" + unseen, true, false) as TextureRect
	var count_text: String = m.hud.guide._count.text
	m._check("the Field Guide lists every species (%d pictures), counts '%s', and a %s not yet seen is a silhouette" % [m.hud.guide.pics.size(), count_text, unseen],
		m.hud.guide.pics.size() == 10 and count_text.begins_with("Seen 3 of 10") and count_text.contains("Caught 2") and pic != null and pic.modulate.r < 0.01 and pic.texture != null)
	await m._shot("70_field_guide.png")
	m.hud.guide.call("close")
	# --- the Lookbook
	Game.wardrobe = {}
	var ds: Array = preload("res://scripts/sweaters.gd").designs()
	for i in 4:
		Game.wardrobe[str(ds[i * 7]["id"])] = 1
	m.hud.lookbook.call("open")
	await m._wait(0.6)
	var lb_text: String = m.hud.lookbook._count.text
	m._check("the Lookbook shows the %d designs and counts '%s'" % [ds.size(), lb_text], ds.size() == 50 and Lookbook.knitted() == 4 and lb_text == "Knitted 4 of 50 designs")
	await m._shot("70_lookbook.png")
	m.hud.lookbook.call("close")
	# --- the ledger: takings by channel, rolled over at a new day
	Game.flags.erase("ledger")
	var d0 := Game.day
	var c1 := Game.coins
	var rosa: Variant = m._villager("rosa")
	Game.add_sweater(1)
	m.sell_sweater_to(rosa, Game.sweaters.size() - 1, 120)
	EmpireGoals.took("rosa", 80)
	var today: Dictionary = EmpireGoals.ledger()["today"]
	m._check("a sale face to face and Rosa's count by channel (%s)" % str(today), int(today.get("face", 0)) == 120 and int(today.get("rosa", 0)) == 80 and Game.coins - c1 == 120)
	Game.day = d0 + 1
	var l1: Dictionary = EmpireGoals.ledger().duplicate(true) # a copy: the ledger is changed in place
	EmpireGoals.took("mail", 300)
	EmpireGoals.took("store", 50)
	Game.day = d0 + 2
	g._on_day_started(Game.day)
	await m._wait(1.6)
	var card: String = g._card_text.text
	var l2: Dictionary = EmpireGoals.ledger()
	m._check("the day rolls over: day one's 200c become yesterday (%s), then the day before (%s); yesterday %dc" % [str(l1["yesterday"]), str(l2["before"]), EmpireGoals.sum(l2["yesterday"])],
		EmpireGoals.sum(l1["yesterday"]) == 200 and (l1["today"] as Dictionary).is_empty() and EmpireGoals.sum(l2["before"]) == 200 and EmpireGoals.sum(l2["yesterday"]) == 350 and (l2["today"] as Dictionary).is_empty())
	m._check("the morning card shows yesterday by channel and the change ('%s')" % card.replace("\n", " | "),
		g._card.visible and card.contains("Mail orders   300c") and card.contains("Online store   50c") and card.contains("Total 350c") and card.contains("+150c"))
	await m._shot("70_ledger.png")
	Game.day = d0 + 5
	m._check("a gap of days leaves nothing to compare", EmpireGoals.ledger_text() == "" and EmpireGoals.sum(EmpireGoals.ledger()["yesterday"]) == 0)
	# --- the 1,000c day reads the ledger
	var day_goal: Dictionary = g.defs.filter(func(x): return str(x["id"]) == "day1000")[0]
	var before_k := int(g.metric(day_goal))
	EmpireGoals.took("face", 600)
	EmpireGoals.took("store", 450)
	m._check("'Earn 1,000c in one day' reads the ledger's best day (%d, then %d)" % [before_k, int(g.metric(day_goal))], before_k == 350 and g.met(day_goal))
	# --- the last goal opens the next chapter
	for x in g.defs:
		if str(x["id"]) != "ready":
			(g.state()["done"] as Dictionary)[str(x["id"])] = {"day": Game.day, "secs": 0}
	var c2 := Game.coins
	g.check_now()
	m._check("with every other goal done, 'Ready for the next chapter' sets act_ready (%s) and pays nothing (%d)" % [str(Game.flags.get("act_ready")), Game.coins - c2],
		int(Game.flags.get("act_ready", 0)) == 1 and g.is_done("ready") and g.window().is_empty() and Game.coins == c2)
	# put it all back
	m.wildlife.clear()
	g._card.visible = false
	g._card_t = 0.0
	EmpireGoals.on = false
	Game.flags = keep["flags"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	Game.coins = keep["coins"]
	Game.wardrobe = keep["wardrobe"]
	Game.inv = keep["inv"]
	Game.time_running = keep["clock"]
	m.player.position = keep["pos"]
	m.player.walk([])
	await m._wait(0.6)
	m._check("with the check done, the list is off again", not g._panel.visible)
