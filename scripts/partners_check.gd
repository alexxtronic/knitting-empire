extends RefCounted
## --only=partners: her partner (scripts/partners.gd, data/scenes/partners.scene, lars.scene,
## gary.scene, the proposal and wedding in acts.scene, data/economy.json "partners"). Every scene
## reads; Gary is a candidate and Max never is, even at full romance; no "Ask him out" below the
## threshold; asking Rowan makes him her boyfriend, on his menu's heading; Lars climbing past him by
## the margin gets the row (and only the man with the most romance does); turning Lars down keeps
## Rowan; saying yes makes Lars her partner and Rowan sore, his romance down; the argument; a sharp
## line; the morning's roll pulling a prank; each prank applied (needles: a knit a grade lower; itch:
## that villager not buying today; a pastry gone; the front of the house garish; a sheep out of the
## pen) and undone or expiring; a save and load keeping it all; herding the sheep back; a gift ending
## his sulk and putting the pastry and paint right; two days of talk ending it; no pranks in Act 1's
## guided part or in a scene; titles by act; the proposal at the Act 2 skip and the wedding at the
## Act 3 one. Saves 73_partner_ask.png, 73_partner_prank.png and 73_partner_proposal.png.
## Leaves the flags, the day, the act, her coins and the friendships as it found them.

const Partners = preload("res://scripts/partners.gd")
const Story = preload("res://scripts/story.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Acts = preload("res://scripts/acts.gd")
const HouseSkin = preload("res://scripts/house_skin.gd")
const HouseBuilder = preload("res://scripts/house_builder.gd")

var m: Node
var pt: Node


func _set_romance(id: String, n: int) -> void:
	Game.friend(id)["romance"] = n


func _row_ids(v) -> Array:
	return m._villager_actions(v).map(func(r): return str(r.get("id", "")))


func _until_free(limit: float) -> float:
	var t := 0.0
	while m.story.is_playing() and t < limit:
		await m._wait(0.1)
		t += 0.1
	return t


## Plays the menu's ask on `v` with these choices and waits for the scene to end.
func _ask(v, choices: Array) -> String:
	Game.flags.erase("partner_asked")
	m.story.auto_choices = choices.duplicate()
	m._villager_action(v, "partner_ask")
	var sid: String = m.story.playing
	await _until_free(15.0)
	return sid


func _next_day() -> void:
	Game.day += 1
	Game.flags["prank_roll"] = Game.day # no morning roll unless the check asks for one
	pt.update()


func run(main: Node) -> void:
	m = main
	pt = m.partners
	var keep := {"flags": Game.flags.duplicate(true), "day": Game.day, "hour": Game.hour, "coins": Game.coins, "clock": Game.time_running,
		"act": Game.act, "friends": Game.friends.duplicate(true), "pos": m.player.position, "sheep": Game.sheep_count,
		"sweaters": Game.sweaters.duplicate(), "designs": Game.sweater_designs.duplicate(), "fibres": Game.sweater_fibres.duplicate(),
		"wool": Game.count("wool"), "pastry": Game.count("pastry"), "pumpkin": Game.count("pumpkin"),
		"wardrobe": Game.wardrobe.duplicate(), "worn": Game.worn_design, "xp": Game.knit_xp}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	Partners.on = true
	for k in ["partner", "partner_since", "sore", "sore_talks", "argued", "argue_due", "pranks", "prank_last", "prank_roll", "partner_asked", "wall_paint", "proposed", "married"]:
		Game.flags.erase(k)
	Game.set_flag("act1_done")
	Game.flags["prank_roll"] = Game.day
	for id in ["rowan", "lars", "gary"]:
		_set_romance(id, 0)
	m.story.auto = true
	var rowan = m._villager("rowan")
	var lars = m._villager("lars")
	var gary = m._villager("gary")
	var ask_at := int(Partners.num("ask_at", 10))
	var margin := int(Partners.num("switch_margin", 8))
	# --- the scenes read, and every one this step needs is there
	var errs: Array = Story.validate()
	var need := ["lars_topic_radio", "lars_topic_dad", "lars_topic_loft", "lars_date_invite", "lars_date1", "gary_topic_blazer", "gary_topic_starter",
		"gary_topic_caravan", "gary_date_invite", "gary_date1", "partner_ask_rowan", "partner_ask_lars", "partner_ask_gary",
		"partner_argue_rowan", "partner_argue_lars", "partner_argue_gary"]
	var missing := need.filter(func(s): return not Story.has_scene(str(s)))
	m._check("the scenes read (%d problems%s) and all %d of the partners' are there (missing %s)" % [errs.size(), (": " + str(errs[0])) if not errs.is_empty() else "", need.size(), str(missing)],
		errs.is_empty() and missing.is_empty())
	# --- the candidates: Gary is one, Max never
	_set_romance("max", 100)
	var cands: Array = Partners.candidates()
	m._check("the candidates are Rowan, Lars and Gary (%s); Max is never one, even at romance 100 (can ask %s)" % [str(cands), str(Partners.can_ask("max"))],
		cands == ["rowan", "lars", "gary"] and not Partners.can_ask("max") and not Partners.is_candidate("max") and lars.romance and gary.romance)
	Game.friends.erase("max")
	# --- no "Ask him out" below the threshold
	_set_romance("rowan", ask_at - 1)
	var below := _row_ids(rowan)
	_set_romance("rowan", ask_at)
	var at := _row_ids(rowan)
	m._check("no 'Ask him out' below romance %d (%s), and the row at it (%s)" % [ask_at, str(below.has("partner_ask")), str(at.has("partner_ask"))],
		not below.has("partner_ask") and at.has("partner_ask") and not _row_ids(lars).has("partner_ask") and not _row_ids(m._villager("wren")).has("partner_ask"))
	# --- asking Rowan: he's her boyfriend
	m.player.position = rowan.position + Vector3(1.2, 0, 1.2)
	m.cam_target = rowan.position
	m.story.pause_on = "Officially."
	Game.flags.erase("partner_asked")
	m.story.auto_choices = []
	m._villager_action(rowan, "partner_ask")
	var t := 0.0
	while not m.story.holding and t < 8.0:
		await m._wait(0.1)
		t += 0.1
	await m._wait(0.5)
	await m._shot("73_partner_ask.png")
	m.story.holding = false
	await _until_free(10.0)
	var head: String = m._name_of(rowan)
	m._check("asking Rowan out: partner '%s' since day %s, his title '%s', his menu reads '%s', no row now" % [Partners.partner(), str(Game.flags.get("partner_since")), Partners.title(), head],
		Partners.partner() == "rowan" and int(Game.flag("partner_since", -1)) == Game.day and Partners.title() == "boyfriend"
		and head == rowan.display_name() + "  (your boyfriend)" and rowan.tag.text == rowan.display_name() and not _row_ids(rowan).has("partner_ask"))
	# --- Lars climbing past him by the margin
	_set_romance("lars", ask_at + margin - 1)
	var short := _row_ids(lars).has("partner_ask")
	_set_romance("lars", ask_at + margin)
	var past := _row_ids(lars).has("partner_ask")
	_set_romance("gary", ask_at + margin + 1) # Gary higher still: only the man with the most romance is offered
	var lars_when_gary := _row_ids(lars).has("partner_ask")
	var gary_row := _row_ids(gary).has("partner_ask")
	_set_romance("gary", 0)
	m._check("Lars a point short of the margin gets no row (%s), at it he does (%s); with Gary higher still only Gary does (Lars %s, Gary %s)" % [str(short), str(past), str(lars_when_gary), str(gary_row)],
		not short and past and not lars_when_gary and gary_row)
	# --- turning him down keeps Rowan
	var lr0: int = Game.stat("lars", "romance")
	var sid := await _ask(lars, [1])
	m._check("'No. I'm staying with Rowan.' (%s): Rowan's still the one, Lars loses %d romance, nobody sore" % [sid, lr0 - Game.stat("lars", "romance")],
		sid == "partner_ask_lars" and Partners.partner() == "rowan" and lr0 - Game.stat("lars", "romance") == int(Partners.num("stay_drop", 3)) and Partners.sore().is_empty())
	# --- switching: Lars is her partner, Rowan sore
	_set_romance("lars", ask_at + margin + 4)
	var rr0: int = Game.stat("rowan", "romance")
	sid = await _ask(lars, [0])
	m._check("switching to Lars (%s): partner '%s', Rowan sore until day %d (today %d), his romance %d to %d, Lars's menu '%s'" % [sid, Partners.partner(), int(Partners.sore().get("rowan", -1)), Game.day, rr0, Game.stat("rowan", "romance"), m._name_of(lars)],
		Partners.partner() == "lars" and Partners.is_sore("rowan") and int(Partners.sore()["rowan"]) == Game.day + int(Partners.num("sore_days", 7))
		and rr0 - Game.stat("rowan", "romance") == int(Partners.num("sore_drop", 10)) and m._name_of(lars).ends_with("(your boyfriend)") and m._name_of(rowan) == rowan.display_name())
	# --- the argument: talking to her partner brings Rowan over
	Game.flags["argue_due"] = {"day": Game.day, "id": "rowan"}
	m.story.shown.clear()
	m._villager_action(lars, "talk")
	sid = m.story.playing
	await _until_free(10.0)
	var shown := " | ".join(m.story.shown)
	m._check("the argument (%s): '%s...', once a spell (argued %s, due %s)" % [sid, shown.left(70), str(Game.flags.get("argued")), str(Game.flags.get("argue_due"))],
		sid == "partner_argue_rowan" and shown.contains("radio") and int((Game.flag("argued", {}) as Dictionary).get("rowan", -1)) == int(Partners.sore()["rowan"])
		and Game.flags.get("argue_due", null) == null)
	await m._wait(0.3)
	# --- a sharp line from Rowan
	pt.force_roll = 0.0
	m.hud.hide_dialogue()
	m._villager_action(rowan, "talk")
	await m._wait(0.2)
	var said: String = m.hud.dlg_text.text
	var sharps: Array = (Partners.econ()["sharp"] as Dictionary)["rowan"]
	var is_sharp := sharps.any(func(x): return str(x).replace("{partner}", "boyfriend") == said)
	m._check("talking to sore Rowan: something sharp ('%s'), no scene (%s), still sore after one day's talk" % [said, m.story.playing],
		is_sharp and not m.story.is_playing() and Partners.is_sore("rowan"))
	m.hud.hide_dialogue()
	# --- the morning's roll: a prank (needles, forced) and nothing in a scene or Act 1's guided part
	Game.day += 1
	Game.flags["prank_roll"] = Game.day - 1
	pt.force_prank = "needles"
	Game.flags.erase("act1_done")
	pt.update()
	var guided: bool = Partners.pranks().is_empty() and int(Game.flag("prank_roll", -1)) == Game.day - 1
	Game.set_flag("act1_done")
	m.story.playing = "check_fake"
	pt.update()
	var in_scene: bool = Partners.pranks().is_empty()
	m.story.playing = ""
	m._check("no prank during Act 1's guided part (%s) or a story scene (%s)" % [str(guided), str(in_scene)], guided and in_scene)
	pt.update()
	var n_prank: Dictionary = Partners.prank("needles")
	m._check("the morning's roll: Rowan hides her needles (%s, until day %d), no second argument this spell (%s)" % [str(n_prank), int(n_prank.get("until", -1)), str(Game.flags.get("argue_due"))],
		str(n_prank.get("by", "")) == "rowan" and int(n_prank.get("until", -1)) == Game.day + 1 and pt.knit_penalty() == 1 and Game.flags.get("argue_due", null) == null
		and int(Game.flag("prank_last", -1)) == Game.day)
	# needles: the knit comes out a grade lower
	Game.add_item("wool", 3 - mini(3, Game.count("wool")))
	var sw0: int = Game.sweaters.size()
	m._finish_knit(3)
	var knit_q: int = int(Game.sweaters[-1]) if Game.sweaters.size() > sw0 else -1
	await m._wait(1.0)
	await _until_free(5.0)
	m._check("with her needles hidden a Fine knit comes out a grade lower (rated 3, got %d)" % knit_q, Game.sweaters.size() == sw0 + 1 and knit_q == 2)
	if Game.sweaters.size() > sw0:
		Game.remove_sweater(Game.sweaters.size() - 1)
	# itch
	var itch_kind: String = pt.do_prank("rowan", "itch")
	var ip: Dictionary = Partners.prank("itch")
	var who := str(ip.get("who", ""))
	var wv = m._villager(who)
	var looked: bool = SweaterSale.looking(who)
	if wv != null:
		var asked: Dictionary = (Game.flag("sweater_asked", {}) as Dictionary).duplicate()
		asked.erase(who)
		Game.flags["sweater_asked"] = asked
		m.sale.ask(wv)
	var no_line: String = m.hud.dlg_text.text
	m._check("itch (%s): Rowan told %s her sweaters itch; not looking today (%s), and says so ('%s')" % [itch_kind, who, str(looked), no_line],
		itch_kind == "itch" and who != "" and not Partners.is_candidate(who) and not looked and Partners.itchy(who) and no_line == Partners.line("itch_no"))
	m.hud.hide_dialogue()
	# pastry
	Game.add_item("pastry")
	var p0: int = Game.count("pastry")
	var pk: String = pt.do_prank("rowan", "pastry")
	m._check("pastry (%s): one gone from her bag (%d to %d), kept till he mends (until %d)" % [pk, p0, Game.count("pastry"), int(Partners.prank("pastry").get("until", 0))],
		pk == "pastry" and Game.count("pastry") == p0 - 1 and int(Partners.prank("pastry").get("until", 0)) == -1)
	# paint
	var garish := str(Partners.econ().get("garish", "garish"))
	var gk: String = pt.do_prank("rowan", "paint")
	var faces: Array = pt._front_faces()
	var painted: bool = faces.all(func(f): return str((Game.flag("wall_paint", {}) as Dictionary).get(f, "")) == garish)
	var meshes: int = m._count_mat(m.house_root, HouseSkin.material("plaster", HouseBuilder.PAINT_COLOURS[garish]))
	m._check("paint (%s): the porch wall's outside garish (%d faces, all %s, %d plaster pieces), not in the paint picker (%s)" % [gk, faces.size(), str(painted), meshes, str(HouseBuilder.PAINTS.has(garish))],
		gk == "paint" and not faces.is_empty() and painted and meshes > 0 and not HouseBuilder.PAINTS.has(garish))
	# the pen
	var pen_kind: String = pt.do_prank("rowan", "pen")
	var s = pt._loose()
	t = 0.0
	while s != null and not s.route.is_empty() and t < 10.0:
		await m._wait(0.2)
		t += 0.2
	var out_at: Vector3 = s.position if s != null else Vector3.ZERO
	var outside: bool = s != null and not m.pen_rect.has_point(Vector2(out_at.x, out_at.z))
	m._check("pen (%s): Rowan left the gate open and a sheep walked out (at %.1f, %.1f, outside the pen %s, loose %s)" % [pen_kind, out_at.x, out_at.z, str(outside), str(pt.loose_out())],
		pen_kind == "pen" and outside and pt.loose_out())
	# the picture: the garish house, the loose sheep
	m.player.position = Vector3(m.HOUSE_W + 5.0, 0, 3.0)
	m.cam_target = Vector3(m.HOUSE_W + 2.0, 0, 0.0)
	m.cam_yaw = deg_to_rad(80.0)
	m.cam_dist = 16.0
	await m._wait(0.8)
	await m._shot("73_partner_prank.png")
	# --- a save and load keeps it all
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	for k in ["partner", "sore", "pranks", "argued", "wall_paint"]:
		Game.flags.erase(k)
	Game.from_dict(saved.duplicate(true))
	pt.apply()
	var kinds: Array = Partners.pranks().map(func(x): return str(x.get("kind", "")))
	kinds.sort()
	m._check("a save keeps it (partner %s, sore %s, pranks %s, itch %s, penalty %d, loose %s, paint %s)" % [Partners.partner(), str(Partners.sore()), str(kinds), str(Partners.itchy(who)), pt.knit_penalty(), str(pt.loose_out()), str(Game.flags.has("wall_paint"))],
		Partners.partner() == "lars" and Partners.is_sore("rowan") and kinds == ["itch", "needles", "paint", "pastry", "pen"] and Partners.itchy(who)
		and pt.knit_penalty() == 1 and pt.loose_out() and Game.flags.has("wall_paint") and Partners.title() == "boyfriend")
	# --- herding her back: Nora walks round behind her toward the pen
	s = pt._loose()
	var herded := false
	t = 0.0
	while s != null and pt.loose_out() and t < 14.0:
		var to_pen: Vector3 = Vector3(m.pen_rect.get_center().x, 0, m.pen_rect.get_center().y) - s.position
		to_pen.y = 0.0
		m.player.walk([])
		m.player.position = s.position - to_pen.normalized() * 1.4
		await m._wait(0.15)
		t += 0.15
	herded = not pt.loose_out()
	if not herded and s != null: # the old sandbox pen's fence may be in her way: in by hand
		s.position = Vector3(m.pen_rect.get_center().x, 0, m.pen_rect.get_center().y)
		await m._wait(0.2)
	m._check("herding her back (by walking her in %s, %.1f s): in the pen, the prank over (%s)" % [str(herded), t, str(Partners.prank("pen"))],
		not pt.loose_out() and Partners.prank("pen").is_empty() and s != null and m.pen_rect.has_point(Vector2(s.position.x, s.position.z)))
	# --- the next morning: needles and itch are over; pastry and paint wait for him to mend
	_next_day()
	kinds = Partners.pranks().map(func(x): return str(x.get("kind", "")))
	kinds.sort()
	m._check("the next morning the needles and the itch are over (penalty %d, itchy %s), pastry and paint still on (%s)" % [pt.knit_penalty(), str(Partners.itchy(who)), str(kinds)],
		pt.knit_penalty() == 0 and not Partners.itchy(who) and kinds == ["paint", "pastry"])
	# --- a gift ends it: the pastry comes back, the paint comes off
	Game.add_item("pumpkin")
	var p1: int = Game.count("pastry")
	Game.friend("rowan")["gift"] = 0
	m._villager_action(rowan, "gift_pumpkin")
	await m._wait(0.2)
	await _until_free(8.0)
	var unpainted: bool = faces.all(func(f): return not (Game.flag("wall_paint", {}) as Dictionary).has(f))
	m._check("a gift ends Rowan's sulk (sore %s): the pastry back (%d to %d), the paint off (%s), no pranks left (%s)" % [str(Partners.is_sore("rowan")), p1, Game.count("pastry"), str(unpainted), str(Partners.pranks())],
		not Partners.is_sore("rowan") and Game.count("pastry") == p1 + 1 and unpainted and Partners.pranks().is_empty()
		and m._count_mat(m.house_root, HouseSkin.material("plaster", HouseBuilder.PAINT_COLOURS[garish])) == 0)
	# --- two days of talk end it too
	pt.make_sore("rowan")
	pt.force_roll = 1.0 # no sharp line
	pt.talk_line(rowan)
	var after_one := Partners.is_sore("rowan")
	_next_day()
	pt.talk_line(rowan)
	m._check("talking to him on two days ends it (sore after one %s, after two %s)" % [str(after_one), str(Partners.is_sore("rowan"))],
		after_one and not Partners.is_sore("rowan"))
	# --- and soreness, and the pen, run out on their own
	pt.make_sore("rowan")
	pt.do_prank("rowan", "pen")
	var s2 = pt._loose()
	await m._wait(0.3)
	_next_day()
	await m._wait(0.2)
	var pen_back: bool = not pt.loose_out() and s2 != null and m.pen_rect.has_point(Vector2(s2.position.x, s2.position.z))
	Game.day = int(Partners.sore()["rowan"])
	pt.update()
	m._check("the pen prank ends the next morning, the sheep back in (%s); his soreness runs out on its day (%s)" % [str(pen_back), str(Partners.is_sore("rowan"))],
		pen_back and not Partners.is_sore("rowan") and not Partners.sore().has("rowan"))
	pt.force_roll = -1.0
	# --- titles by act
	var titles := []
	for a in [1, 2, 3, 4]:
		Game.act = a
		titles.append(Partners.title())
	Game.act = 2
	var head2: String = m._name_of(lars)
	Game.act = 1
	m._check("titles by act %s; in Act 2 his menu reads '%s'" % [str(titles), head2],
		titles == ["boyfriend", "fiancé", "husband", "husband"] and head2.ends_with("(your fiancé)"))
	# --- the proposal at the Act 2 skip
	var af: Node = m.act_frame
	Game.flags["act_ready"] = 1
	m.story.shown.clear()
	m.story.auto_choices = [0, 0] # begin it; "yes"
	m.story.pause_on = "Marry me?"
	var began: bool = af.begin()
	t = 0.0
	while not m.story.holding and m.story.is_playing() and t < 20.0:
		await m._wait(0.1)
		t += 0.1
	await m._wait(0.6)
	m.hud.toast_panel.visible = false # the check's own toasts from a moment ago
	await m._shot("73_partner_proposal.png")
	var card: String = Acts.partner_line()
	m.story.holding = false
	await _until_free(15.0)
	shown = " | ".join(m.story.shown)
	m._check("the Act 2 skip (%s) plays Lars's proposal ('%s'), she says yes (proposed %s), and the card names him: '%s'" % [str(began), "Marry me" if shown.contains("Marry me") else shown.right(60), str(Game.flag("proposed")), card],
		began and Game.act == 2 and shown.contains("Marry me?") and Game.flag("proposed") == true and card == "Lars, your fiancé, is still by your side.")
	# --- the wedding at the Act 3 skip
	Game.flags["act_ready"] = 1
	m.story.shown.clear()
	m.story.auto_choices = [0]
	began = af.begin()
	await _until_free(20.0)
	shown = " | ".join(m.story.shown)
	m._check("the Act 3 skip (%s) marries them in the square (married %s, '%s'), his title '%s'" % [str(began), str(Game.flag("married")), "you're married" if shown.contains("you're married") else shown.right(60), Partners.title()],
		began and Game.act == 3 and Game.flag("married") == true and shown.contains("you're married") and Partners.title() == "husband")
	# --- without a partner, no proposal
	Game.flags.erase("partner")
	Game.flags["act_ready"] = 1
	m.story.shown.clear()
	m.story.auto_choices = [0]
	began = af.begin()
	await _until_free(20.0)
	shown = " | ".join(m.story.shown)
	m._check("without a partner the Act 4 skip has no partner scene (%s, %d lines)" % [str(began), m.story.shown.size()],
		began and Game.act == 4 and not shown.contains("Marry") and not shown.contains("married") and Acts.partner_line() == "")
	# put it all back
	m.story.auto = false
	m.story.pause_on = ""
	m.story.auto_choices = []
	Partners.on = false
	Game.flags = keep["flags"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	Game.coins = keep["coins"]
	Game.act = keep["act"]
	Game.friends = keep["friends"]
	Game.sheep_count = keep["sheep"]
	Game.sweaters = keep["sweaters"]
	Game.sweater_designs = keep["designs"]
	Game.sweater_fibres = keep["fibres"]
	for it in ["wool", "pastry", "pumpkin"]:
		var d: int = int(keep[it]) - Game.count(it)
		if d > 0:
			Game.add_item(it, d)
		elif d < 0:
			Game.take_item(it, -d)
	Game.wardrobe = keep["wardrobe"]
	Game.wear(str(keep["worn"]))
	Game.knit_xp = keep["xp"]
	Game.time_running = keep["clock"]
	m.goals.sync_act()
	af.apply_model()
	m._rebuild_house()
	m.player.position = keep["pos"]
	m.player.walk([])
	for id in ["rowan", "lars", "gary", "wren", "rosa", "giorgio"]:
		m.set_home(id)
	await m._wait(0.6)
	m._check("with the check done, Act %d again, no partner (%s), nobody sore" % [Game.act, Partners.partner()], Game.act == keep["act"] and Partners.sore().is_empty())
