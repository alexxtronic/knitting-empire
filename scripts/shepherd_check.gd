extends RefCounted
## --only=shepherd (and part of the full run): Shepherd Rowan (scripts/shepherd.gd, Act 1's tutorial in
## data/scenes/act1.scene, his advice in data/scenes/rowan.scene). His name tag, the four tasks' story
## chain (sheared, knit_done and sweater_sold each start the next step only in its place), the four
## strays, his advice talks in order as the farm gets there, and hiring him to watch the pen at half the
## barn's rent (no row before Act 1 is done, one hire at a time). Rowan's cover against the wolves is in
## the wolves check (main._wolf_checks). Saves 68_shepherd_rowan.png and 68_shepherd_tip.png.
## Leaves the flags, the coins, the day and the camera as it found them.

const Story = preload("res://scripts/story.gd")
const Shepherd = preload("res://scripts/shepherd.gd")

var m: Node


func _ev(name: String) -> String:
	return Story.find_trigger("event", name)


func run(main: Node) -> void:
	m = main
	var keep := {"flags": Game.flags.duplicate(true), "day": Game.day, "hour": Game.hour, "coins": Game.coins, "clock": Game.time_running}
	Game.time_running = false
	m.hud.hide_dialogue()
	var rowan = m._villager("rowan")
	# his name tag
	m._check("Rowan's tag reads '%s'" % rowan.display_name(), rowan.display_name() == "Shepherd Rowan")
	m.cam_target = rowan.position
	m.cam_dist = 6.0
	await m._wait(0.6)
	await m._shot("68_shepherd_rowan.png")
	# Act 1: four strays, and his tasks' events each start the next step only in their place
	m._check("four strays come for Rowan's second task (economy 'story' strays = %d)" % m.homestead.econ("strays", 0), m.homestead.econ("strays", 0) == 4)
	for k in ["act1_flock_in", "act1_knit3", "act1_done", "seen_act1_sheared", "seen_act1_knit3", "seen_act1_rowan_done", "act1_yarn", "act1_note", "seen_act1_knit", "seen_act1_knit2"]:
		Game.flags.erase(k)
	Game.set_flag("seen_act1_knit")
	Game.set_flag("seen_act1_knit2")
	var before := [_ev("sheared"), _ev("knit_done"), _ev("sweater_sold")]
	Game.set_flag("act1_flock_in")
	var mid := [_ev("sheared"), _ev("knit_done"), _ev("sweater_sold")]
	Game.set_flag("seen_act1_sheared")
	Game.set_flag("seen_act1_knit3")
	Game.set_flag("act1_knit3")
	var last := _ev("sweater_sold")
	Game.set_flag("act1_done")
	Game.flags.erase("seen_act1_sheared")
	var done_ev := [_ev("sheared"), _ev("sweater_sold")]
	m._check("his tasks in order: nothing before the flock's in (%s), then shear (%s) and knit (%s) but no sale yet (%s), then the sale (%s); none once Act 1 is done (%s)" % [str(before), mid[0], mid[1], mid[2], last, str(done_ev)],
		before == ["", "", ""] and mid[0] == "act1_sheared" and mid[1] == "act1_knit3" and mid[2] == "" and last == "act1_rowan_done" and done_ev == ["", ""])
	# after Act 1: his advice, one talk a day, as the farm gets there
	for k in Game.flags.keys():
		if str(k).begins_with("rowan_tip") or str(k).begins_with("seen_rowan_tip") or str(k).begins_with("seen_rowan_topic"):
			Game.flags.erase(k)
	Game.flags.erase("daily_scene_day")
	Game.set_flag("met_rowan")
	Game.set_flag("seen_rowan_town_chat")
	Game.set_flag("story_farm")
	var t1 := Story.find_trigger("talk", "rowan")
	m.story.auto = true
	m.story.play(t1)
	await m._wait(0.5)
	await m._shot("68_shepherd_tip.png")
	await m._act1_until_done(30.0)
	var same_day := Story.find_trigger("talk", "rowan")
	Game.day += 1
	var t2 := Story.find_trigger("talk", "rowan")
	Game.set_flag("seen_" + t2)
	Game.day += 1
	var t_none := Story.find_trigger("talk", "rowan")
	Game.set_flag("rowan_tip_pen_due")
	var t3 := Story.find_trigger("talk", "rowan")
	Game.set_flag("seen_" + t3)
	Game.day += 1
	Game.set_flag("rowan_tip_wild_due")
	var t4 := Story.find_trigger("talk", "rowan")
	Game.set_flag("seen_" + t4)
	Game.day += 1
	Game.set_flag("rowan_tip_wolves_due")
	var t5 := Story.find_trigger("talk", "rowan")
	m.story.auto = false
	m._check("his advice: the watch first (%s, played: %s), one a day (same day: '%s'), then rare animals (%s); the pen talk waits for a full pen ('%s' before), then a bigger pen (%s), the wild one and a scarf (%s), the wolves (%s)" % [t1, Game.flag("seen_rowan_tip_watch") == true, same_day, t2, t_none, t3, t4, t5],
		t1 == "rowan_tip_watch" and Game.flag("seen_rowan_tip_watch") == true and not same_day.begins_with("rowan_tip") and t2 == "rowan_tip_rare"
		and not t_none.begins_with("rowan_tip") and t3 == "rowan_tip_pen" and t4 == "rowan_tip_scarf" and t5 == "rowan_tip_wolves")
	# the flags those wait for come from the farm (shepherd.update)
	for k in ["rowan_tip_pen_due", "rowan_tip_wild_due"]:
		Game.flags.erase(k)
	Game.set_flag("penned", [{"species": "rabbit", "key": "pen_rabbit_951"}])
	m.shepherd.update()
	m._check("a penned wild animal sets the scarf talk's flag (%s)" % Game.flag("rowan_tip_wild_due"), Game.flag("rowan_tip_wild_due") == true)
	# hiring him to watch the pen: half the barn's rent, paid ahead
	var fee: int = Shepherd.fee()
	var barn: int = m.homestead.econ("barn_rent", 120)
	Game.flags.erase("shepherd_until")
	Game.flags.erase("act1_done")
	var rows_early: Array = m.shepherd.rows_for(rowan)
	Game.set_flag("act1_done")
	Game.coins = fee + 7
	var rows: Array = m.shepherd.rows_for(rowan)
	var in_menu: bool = m._villager_actions(rowan).any(func(a): return str(a["id"]) == "shep_hire" and a["enabled"])
	var nobody: bool = m.shepherd.rows_for(m._villager("lars")).is_empty()
	m._villager_action(rowan, "shep_hire")
	var hired := Shepherd.paid_up()
	var rows_after: Array = m.shepherd.rows_for(rowan)
	var twice: bool = m.shepherd.hire(rowan)
	m.hud.hide_dialogue()
	m._check("hiring Rowan: no row during Act 1 (%d), then '%s' at %dc, half the barn's %dc (in his menu %s, not Lars's %s); hired (%s, coins %d left, until day %d), and '%s', no second hire (%s)" % [
		rows_early.size(), str(rows[0]["label"]) if not rows.is_empty() else "-", fee, barn, in_menu, not nobody, hired, Game.coins, int(Game.flag("shepherd_until", 0)), str(rows_after[0]["label"]) if not rows_after.is_empty() else "-", twice],
		rows_early.is_empty() and rows.size() == 1 and fee * 2 == barn and in_menu and nobody and hired and Game.coins == 7
		and int(Game.flag("shepherd_until", 0)) == Game.day + Shepherd.days() and not bool(rows_after[0]["enabled"]) and not twice)
	Game.day = int(Game.flag("shepherd_until", 0))
	m._check("his watch runs out after %d days (paid up %s on day %d), and the row comes back (%s)" % [Shepherd.days(), Shepherd.paid_up(), Game.day, str(m.shepherd.rows_for(rowan)[0]["id"])],
		not Shepherd.paid_up() and str(m.shepherd.rows_for(rowan)[0]["id"]) == "shep_hire")
	# put it all back
	Game.flags = keep["flags"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	Game.coins = keep["coins"]
	Game.time_running = keep["clock"]
	m.hud.hide_dialogue()
	m.cam_target = m.player.position
