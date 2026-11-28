extends RefCounted
## --only=coach: finding the dog and knowing what to do next (Alex, 2026-11-27). A click on her dog
## offers "Play as the dog" and choosing it makes the player him; the Dog button on the bar does the
## same and brings Nora back; the banner with his keys is up for as long as she's him; the "Next"
## line at the top of the Empire goal list follows what she holds: sell a sweater, knit when there's
## wool, shear a coat that's ready, build a pen when there's none, catch an animal when a pen has
## room, build another when they're full; none during Act 1's guided part. Saves 82_coach_dog_menu.png,
## 82_coach_dog_banner.png and 82_coach_next.png. Leaves the game as it found it.

const Coach = preload("res://scripts/coach.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")


func run(m: Node) -> void:
	var keep := {"flags": Game.flags.duplicate(true), "inv": Game.inv.duplicate(true), "sweaters": Game.sweaters.size(), "goals_on": EmpireGoals.on,
		"wool": [], "clock": Game.time_running}
	Game.time_running = false
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	for s in m.sheep_list:
		keep["wool"].append(s.wool)
	# --- the dog
	var dog = m.dog
	m.toggle_dog(false)
	await m._wait(0.3)
	var rows: Array = dog.ke_actions()
	var ids: Array = rows.map(func(r): return str(r["id"]))
	m.cam_glide = {"pos": dog.position, "dist": 7.0, "pitch": 40.0}
	await m._wait(1.0)
	m.hud.pie.open(m.get_viewport().get_visible_rect().size * 0.5, "Your dog", rows, func(_id): pass)
	await m._wait(0.4)
	await m._shot("82_coach_dog_menu.png")
	m.hud.pie.close()
	m._check("a click on her dog offers Play as the dog (%s: \"%s\")" % [str(ids), str(rows[0]["label"]) if not rows.is_empty() else ""], ids.has("play_dog") and "Play as the dog" in str(rows[0]["label"]))
	dog.ke_action("play_dog")
	await m._wait(0.5)
	var banner_on: bool = m.hud.dog_banner.visible
	var banner: String = m.hud._dog_banner_label.text
	m._check("choosing it makes the player the dog, with his keys on a banner the whole time (\"%s\")" % banner, dog.controlled and banner_on and "bark" in banner and "back to Nora" in banner and m.hud.dog_btn.visible and m.hud.dog_btn.text == "Nora")
	await m._shot("82_coach_dog_banner.png")
	m.hud.dog_pressed.emit()
	await m._wait(0.5)
	m._check("the button on the bar brings Nora back (it reads \"%s\" again), and the banner goes" % m.hud.dog_btn.text, not dog.controlled and not m.hud.dog_banner.visible and m.hud.dog_btn.text == "Dog")
	m.hud.dog_pressed.emit()
	await m._wait(0.4)
	var by_button: bool = dog.controlled
	m.toggle_dog(false)
	await m._wait(0.3)
	m._check("and pressed again it plays the dog", by_button and not dog.controlled)
	m._check("playing him, a click on him offers no second Play row", true if dog.ke_actions().filter(func(r): return str(r["id"]) == "play_dog").size() == 1 else false)
	# --- what to do next
	Game.flags.erase("act1_done")
	m._check("no Next line during Act 1's guided part", str(Coach.next_step(m)[0]) == "")
	Game.flags["act1_done"] = true
	while Game.sweaters.size() > 0:
		Game.remove_sweater(0)
	Game.inv.erase("wool")
	for s in m.sheep_list:
		s.wool = 0.0
	var steps := []
	steps.append(str(Coach.next_step(m)[0])) # pens with room (or full), nothing to shear
	for s in m.sheep_list:
		s.wool = 1.0
	steps.append(str(Coach.next_step(m)[0])) # a coat is ready
	Game.add_item("wool", 3)
	steps.append(str(Coach.next_step(m)[0])) # wool enough to knit
	Game.add_sweater(1, "")
	steps.append(str(Coach.next_step(m)[0])) # a sweater to sell
	var room: int = m.wildlife.pen_room()
	m._check("the Next line follows what she holds: %s (pen room %d)" % [str(steps), room],
		steps[0] == ("catch" if room > 0 else "full") and steps[1] == "shear" and steps[2] == "knit" and steps[3] == "sell")
	# no pen at all: build one
	var pens0: Array = m.homestead.pens.duplicate()
	var story0: Variant = Game.flags.get("story_farm")
	Game.remove_sweater(Game.sweaters.size() - 1)
	Game.inv.erase("wool")
	for s in m.sheep_list:
		s.wool = 0.0
	m.homestead.pens = []
	Game.flags["story_farm"] = true
	var no_pen: Array = Coach.next_step(m)
	m.homestead.pens = pens0
	if story0 == null:
		Game.flags.erase("story_farm")
	else:
		Game.flags["story_farm"] = story0
	m._check("with no pen it says to build one, and how (\"%s\")" % str(no_pen[1]), str(no_pen[0]) == "pen" and "Build a pen" in str(no_pen[1]) and "gate" in str(no_pen[1]))
	# on the goal list
	EmpireGoals.on = true
	Game.add_sweater(1, "")
	m.goals._shown = ""
	m.goals.sync_act()
	m.goals.check_now()
	m.goals._refresh()
	await m._wait(1.2)
	var line: Label = m.goals._rows.get_node_or_null("CoachLine")
	m._check("the Empire goal list opens with it (\"%s\")" % (line.text if line else ""), line != null and line.text.begins_with("Sell your sweater") and m.goals._panel.visible)
	m.cam_glide = {}
	await m._shot("82_coach_next.png")
	# --- put it back
	while Game.sweaters.size() > int(keep["sweaters"]):
		Game.remove_sweater(Game.sweaters.size() - 1)
	Game.flags = keep["flags"]
	Game.inv = keep["inv"]
	EmpireGoals.on = bool(keep["goals_on"])
	for i in m.sheep_list.size():
		m.sheep_list[i].wool = float(keep["wool"][i])
	Game.time_running = bool(keep["clock"])
	m.goals._shown = ""
