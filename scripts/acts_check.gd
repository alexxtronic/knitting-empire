extends RefCounted
## --only=acts: the four acts (scripts/acts.gd, data/scenes/acts.scene, data/economy.json "acts").
## A new game is Act 1 at 25 and the date chip says so; no chapter row on her bed or in the Esc menu
## before act_ready; the rows once the act's last goal sets it, greyed during a wolf raid; "Not yet"
## changing nothing; beginning it plays the scene and the montage card (closed by its Continue button,
## as a click would); Act 2 at 50 after it, the calendar a season on with the day of the season kept,
## act_ready cleared, her coins, animals and pens unchanged, the barn's rent day moved with it, Act 2's
## first goal showing; Gran's last letter in the post and her rent stopped; a save and load keeping it
## all; an old save without an act loading as Act 1; her model from nora_ages, swapped for real and
## back with her eyes, grip and sweater kept. Saves 72_acts_card.png and 72_acts_act2.png.
## Leaves the act, the flags, the day, her coins and her sweater as it found them.

const EmpireGoals = preload("res://scripts/empire_goals.gd")
const Acts = preload("res://scripts/acts.gd")
const Sweaters = preload("res://scripts/sweaters.gd")
const Furniture = preload("res://scripts/furniture.gd")

var m: Node


func _bed() -> Node:
	for f in m.furniture:
		if is_instance_valid(f) and f is Furniture and f.item_id == "bed":
			return f
	return null


func _row(bed: Node) -> Dictionary:
	for r in m._actions_for(bed):
		if str(r["id"]) == "next_chapter":
			return r
	return {}


func _esc_row() -> bool:
	m.hud.toggle_game_menu() # open: the row's shown or not
	var shown: bool = m.hud.chapter_btn.visible
	m.hud.toggle_game_menu()
	return shown


func _until_free(limit: float) -> float:
	var t := 0.0
	while m.story.is_playing() and t < limit:
		await m._wait(0.1)
		t += 0.1
	return t


func run(main: Node) -> void:
	m = main
	var g: Node = m.goals
	var af: Node = m.act_frame
	var keep := {"flags": Game.flags.duplicate(true), "day": Game.day, "hour": Game.hour, "coins": Game.coins, "clock": Game.time_running,
		"act": Game.act, "sheep": Game.sheep_count, "pos": m.player.position, "worn": Game.worn_design, "wardrobe": Game.wardrobe.duplicate()}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	EmpireGoals.on = true
	# --- a new game is Act 1, aged 25
	var fresh: Node = load("res://scripts/game_state.gd").new() # what reset(), a new game, makes
	var fresh_ok: bool = fresh.act == 1 and fresh.age() == 25
	fresh.free()
	await m._wait(0.3)
	var chip: String = m.hud.clock_label.text
	m._check("a new game is Act 1, aged 25 (fresh %s, this game Act %d at %d), and the date chip says so ('%s')" % [str(fresh_ok), Game.act, Game.age(), chip],
		fresh_ok and Game.act == 1 and Game.age() == 25 and chip.contains("Act 1, 25"))
	m._check("the acts' unlocks: dogs not in Act 1, an unknown name never", not Game.unlocked("dogs") and not Game.unlocked("no_such_thing"))
	# --- no chapter before act_ready
	for k in ["act_ready", "empire_goals", "empire_stats", "gran_passed", "acts_log"]:
		Game.flags.erase(k)
	Game.set_flag("act1_done")
	Game.flags["rent_on"] = true # Gran's rent running, to see it stop
	Game.flags["rent_due"] = Game.day + 3
	Game.flags["rent_owed"] = 0
	var bed := _bed()
	m._check("no 'Begin the next chapter' before act_ready (bed %s, row %s, Esc menu %s, offered %s)" % [str(bed != null), str(_row(bed)), str(_esc_row()), str(af.offered())],
		bed != null and _row(bed).is_empty() and not _esc_row() and not af.offered())
	# --- the act's last goal sets act_ready, and the rows come
	var done: Dictionary = g.state()["done"]
	for x in g.defs:
		if str(x["id"]) != "ready":
			done[str(x["id"])] = {"day": Game.day, "secs": 0}
	g.check_now()
	var row := _row(bed)
	m._check("the last goal sets act_ready (%s): the bed's row '%s' (enabled %s) and the Esc menu's (%s)" % [str(Game.flags.get("act_ready")), str(row.get("label", "")), str(row.get("enabled", false)), str(_esc_row())],
		int(Game.flag("act_ready", 0)) == 1 and str(row.get("label", "")) == "Begin the next chapter…" and bool(row.get("enabled", false)) and _esc_row())
	m.wolves.raid_left = 30.0 # the wolves at the pen: greyed, and begin() refuses
	var raid_row := _row(bed)
	var raid_begin: bool = af.begin()
	m.wolves.raid_left = 0.0
	m._check("during a raid the row is greyed ('%s') and it won't begin (%s)" % [str(raid_row.get("label", "")), str(raid_begin)],
		not bool(raid_row.get("enabled", true)) and not raid_begin and not m.story.is_playing())
	# --- what she has before
	var c0 := Game.coins
	var sheep0 := Game.sheep_count
	var pens0: int = m.wildlife.pens().size()
	var wild0: int = m.wildlife.penned_list().size()
	var d0 := Game.day
	var season_day0 := Game.day_of_season()
	Game.flags["barn_rent_due"] = Game.day + 10
	# --- "Not yet" changes nothing
	m.story.auto = true
	m.story.auto_choices = [1]
	var began: bool = af.begin()
	await _until_free(10.0)
	m._check("'Not yet' (scene %s) leaves Act %d, day %d and act_ready %s" % [str(began), Game.act, Game.day, str(Game.flags.get("act_ready"))],
		began and Game.act == 1 and Game.day == d0 and int(Game.flag("act_ready", 0)) == 1)
	# --- beginning it: the scene and the card
	m.story.auto_choices = [0]
	af.hold_card = true
	began = af.begin()
	var t := 0.0
	while not af.card_open and t < 15.0:
		await m._wait(0.1)
		t += 0.1
	await m._wait(0.4)
	var lines: Array = af.card_lines()
	var joined := " | ".join(lines)
	await m._shot("72_acts_card.png")
	m._check("beginning it plays %s and the card (%s): %s" % [m.story.playing, str(af.card_open), joined],
		began and m.story.playing == "act2_begin" and af.card_open and af.card.visible and str(lines[0]) == "Twenty-five years later"
		and joined.contains("Act 2: The Long Row") and joined.contains("Nora is 50.") and joined.contains("Coins   %dc" % c0)
		and joined.contains("Pens   %d" % pens0) and joined.contains("Field Guide") and joined.contains("Gran passed peacefully"))
	m._check("no partner yet, so no partner line; one shows once Game.flags[\"partner\"] exists ('%s')" % _partner_probe(),
		Acts.partner_line() == "" and _partner_probe().begins_with("Rowan"))
	af.card_button.pressed.emit() # Continue, as a click would
	af.hold_card = false
	await _until_free(15.0)
	m._check("the card closes and the scene ends (%s, card %s)" % [m.story.playing, str(af.card_open)], not m.story.is_playing() and not af.card_open and not af.card.visible)
	# --- Act 2
	await m._wait(0.6)
	chip = m.hud.clock_label.text
	m._check("Act 2, aged 50, and the chip says so ('%s')" % chip, Game.act == 2 and Game.age() == 50 and chip.contains("Act 2, 50") and Game.unlocked("dogs") and not Game.unlocked("mayor"))
	m._check("the calendar moved a season (day %d to %d, day of the season %d to %d), act_ready cleared, the barn's rent day moved with it (%d)" % [d0, Game.day, season_day0, Game.day_of_season(), int(Game.flag("barn_rent_due", 0))],
		Game.day == d0 + Acts.skip_days() and Game.day_of_season() == season_day0 and Game.flag("act_ready", null) == null and int(Game.flag("barn_rent_due", 0)) == d0 + 10 + Acts.skip_days())
	m._check("everything she owns carried over: coins %d (%d), sheep %d (%d), pens %d (%d), wild %d (%d)" % [Game.coins, c0, Game.sheep_count, sheep0, m.wildlife.pens().size(), pens0, m.wildlife.penned_list().size(), wild0],
		Game.coins == c0 and Game.sheep_count == sheep0 and m.wildlife.pens().size() == pens0 and m.wildlife.penned_list().size() == wild0)
	var w: Array = g.window().map(func(x): return str(x["id"]))
	var first_row := ""
	if g._rows.get_child_count() > 1:
		first_row = (g._rows.get_child(1) as Label).text
	m._check("Act 2's goals show (%s, first '%s', panel %s), none of them done, and no chapter row now" % [str(w), first_row, str(g._panel.visible)],
		not w.is_empty() and str(w[0]) == "a2_catch3" and first_row.contains("Catch three wild animals") and g._panel.visible and not g.is_done("a2_catch3") and _row(bed).is_empty())
	m._check("her model is the act's from nora_ages ('%s', body %s)" % [af.used_model, m.player.body.model_path],
		af.used_model != "" and af.used_model == Acts.model_for(2) and m.player.body.model_path == af.used_model and m.player.body.ok)
	m.cam_target = m.player.position
	await m._wait(0.5)
	await m._shot("72_acts_act2.png")
	# --- Gran: her last letter, and no more rent
	m.mail.post_call()
	var box: Array = m.mail.letters_in_box().map(func(l): return str(l["id"]))
	m._check("Gran's last letter comes in the post (%s), and no more letters from Florida" % str(box),
		box.has("gran_last") and not box.has("gran_florida_1") and not box.has("gran_florida_2"))
	m.homestead._on_day(Game.day + 7)
	var tin_rows: Array = m.homestead.tin.ke_actions().map(func(r): return str(r["id"])) if m.homestead.tin else []
	m._check("Gran's rent has stopped (owed %d, rent_on %s, the tin's rows %s)" % [m.homestead.rent_owed(), str(Game.flag("rent_on")), str(tin_rows)],
		m.homestead.rent_owed() == 0 and Game.flag("rent_on") != true and not tin_rows.has("pay_rent") and not tin_rows.has("noop"))
	# --- a save and load
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	Game.act = 1
	Game.flags.erase("gran_passed")
	Game.from_dict(saved.duplicate(true))
	var kept_box: Array = m.mail.letters_in_box().map(func(l): return str(l["id"]))
	m._check("a save keeps it all (version %d, Act %d at %d, Gran %s, letter %s, goal %s)" % [int(saved.get("version", 0)), Game.act, Game.age(), str(Game.flag("gran_passed")), str(kept_box.has("gran_last")), str(g.window()[0]["id"]) if not g.window().is_empty() else "-"],
		int(saved.get("version", 0)) == Game.SAVE_VERSION and Game.act == 2 and Game.age() == 50 and Game.flag("gran_passed") == true and kept_box.has("gran_last")
		and not g.window().is_empty() and str(g.window()[0]["id"]) == "a2_catch3" and Game.coins == c0)
	var old: Dictionary = saved.duplicate(true)
	old.erase("act")
	old["version"] = 8
	Game.from_dict(old)
	var old_act := Game.act
	Game.from_dict(saved.duplicate(true))
	m._check("an old save without an act loads as Act 1 (%d), and this one back as Act %d" % [old_act, Game.act], old_act == 1 and Game.act == 2)
	# --- her model swapped for real, and back: eyes, grip and sweater kept
	var ds: Array = Sweaters.designs()
	var design := str(ds[0]["id"])
	Game.wardrobe[design] = 1
	Game.wear(design)
	await m._wait(0.3)
	var body0: Node = m.player.body
	var other: bool = m.player.set_model("res://assets/nora_tripo.glb") # her painted-eyes model, a stand-in for another age
	var swapped: bool = other and m.player.body != body0 and m.player.body.model_path == "res://assets/nora_tripo.glb"
	await m._wait(0.3)
	var back: bool = af.apply_model()
	await m._wait(0.4)
	var b: Node = m.player.body
	var grip := false
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).find_blend_shape_by_name("grip_R") >= 0:
			grip = true
	m._check("a model swap and back (%s, %s): her eyes %s, grip %s, sweater '%s' (wants '%s'), the old body freed %s" % [str(swapped), str(back), str(b.face != null), str(grip), Sweaters.worn(b), design, str(not is_instance_valid(body0))],
		swapped and back and b.model_path == Acts.model_for(2) and b.ok and b.face != null and grip and Sweaters.worn(b) == design and not is_instance_valid(body0))
	# put it all back
	m.story.auto = false
	EmpireGoals.on = false
	Game.flags = keep["flags"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	Game.coins = keep["coins"]
	Game.act = keep["act"]
	Game.sheep_count = keep["sheep"]
	Game.wardrobe = keep["wardrobe"]
	Game.wear(str(keep["worn"]))
	Game.time_running = keep["clock"]
	g.sync_act()
	af.apply_model()
	m.player.position = keep["pos"]
	m.player.walk([])
	await m._wait(0.6)
	m._check("with the check done, Act %d again and the list off" % Game.act, Game.act == 1 and not g._panel.visible)


## The partner line with a partner set for a moment (step 3 builds the real one).
func _partner_probe() -> String:
	var had: Variant = Game.flags.get("partner", null)
	Game.flags["partner"] = {"id": "rowan", "title": "fiancé"}
	var line := Acts.partner_line()
	if had == null:
		Game.flags.erase("partner")
	else:
		Game.flags["partner"] = had
	return line
