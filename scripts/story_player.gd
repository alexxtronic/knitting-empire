extends Node
## Plays story scenes (see story.gd for the text format) in the world: lines in the dialogue
## box with mood portraits, choices, camera cues, fades, title cards, and actors who walk,
## turn and animate. Added as a child of main.gd.

const Story = preload("res://scripts/story.gd")
const Data = preload("res://scripts/data.gd")

signal scene_finished(id: String)
signal scene_started(id: String) # before its first line: main.gd sends the café's visitors home

var main: Node
var playing := ""
var auto := false # autotest: lines advance by themselves and choices come from auto_choices
var auto_choices: Array = []
var auto_line := 0.08 # seconds each line shows in auto mode
var cinematic := false # auto mode at a person's pace: real fades and glides, time to read each line
var pause_on := "" # auto mode: hold on the first line containing this (the autotest takes a picture)
var holding := false
var shown: Array = [] # every line shown, "Name: text" (for the autotest)
var _held: Array = [] # actors put into an animation by @anim
var _lifted: Array = [] # actors @place put up on a seat; set back on the ground when the scene ends
var _cam0 := {}


func is_playing() -> bool:
	return playing != ""


## Starts a scene. Returns false if one is already playing or the id is unknown.
func play(id: String) -> bool:
	if playing != "" or not Story.has_scene(id):
		return false
	_run(id)
	return true


## Plays the first scene with a matching @trigger, if any. Returns its id or "".
func trigger(kind: String, target := "") -> String:
	if playing != "":
		return ""
	var id := Story.find_trigger(kind, target)
	if id != "":
		play(id)
	return id


func _run(id: String) -> void:
	playing = id
	scene_started.emit(id)
	var sc: Dictionary = Story.scenes()[id]
	var hud = main.hud
	_cam0 = {"follow": main.cam_follow, "dist": main.cam_dist, "yaw": main.cam_yaw_goal}
	var clock_was: bool = Game.time_running
	Game.time_running = false # the day doesn't slip away while you read
	main.player.path = []
	for v in main.villagers:
		if v.tag:
			v.tag.visible = false # name tags are too big for close-up scene cameras
	hud.story_begin()
	var ops: Array = sc["ops"]
	var pc := 0
	var steps := 0
	while pc < ops.size() and steps < 10000:
		steps += 1
		var op: Dictionary = ops[pc]
		pc += 1
		match op["op"]:
			"say":
				await _say(op)
			"choice":
				var idx: int = await _choose(op)
				var opt: Dictionary = op["options"][idx]
				shown.append("> " + str(opt["text"]))
				for e in opt["effects"]:
					await _cmd(e, sc)
				if opt["label"] != "":
					pc = int(sc["labels"].get(opt["label"], ops.size()))
			"cmd":
				var jump = await _cmd(op, sc)
				if jump is int:
					pc = jump if jump >= 0 else ops.size()
	Game.set_flag("seen_" + id)
	if sc["daily"]:
		Game.set_flag("daily_scene_day", Game.day)
	for a in _held:
		if is_instance_valid(a):
			a.anim_override = ""
	_held.clear()
	for a in _lifted: # back down off the rock
		if is_instance_valid(a):
			a.position.y = 0.0
	_lifted.clear()
	main.cam_glide = {}
	hud.set_phone("")
	if hud.memory_on():
		await hud.set_memory(false, 0.6)
	await hud.story_end()
	for v in main.villagers:
		if v.tag:
			v.tag.visible = true
	Game.time_running = clock_was
	main.cam_dist = _cam0["dist"]
	main.cam_follow = _cam0["follow"]
	main.cam_yaw_goal = _cam0["yaw"] # a scene that turned the camera turns it back
	if main.cam_follow:
		main.cam_target = main.player.position
	for n in [main.player] + main.villagers: # faces go back to neutral, eyes open
		if n.get("body") != null and n.body:
			n.body.set_mood("neutral")
			n.body.set_eyes_closed(false)
	playing = ""
	scene_finished.emit(id)


# --- lines and choices ----------------------------------------------------------

func _say(op: Dictionary) -> void:
	var who := str(op["who"])
	var actor = actor(who)
	var name_text := str(op["name"])
	var char_id := who
	if actor == main.player:
		char_id = Data.player_character()
		name_text = str(Data.character(char_id).get("name", name_text))
	var text := _fill(str(op["text"]))
	if actor and actor.get("body") != null and actor.body:
		actor.body.set_mood(str(op["mood"])) # the speaker's eyes take the line's mood
	var tex: Texture2D = null
	if who != "":
		for p in ["res://assets/portraits/%s_%s.png" % [char_id, op["mood"]], "res://assets/portraits/%s_neutral.png" % char_id]:
			if ResourceLoader.exists(p):
				tex = load(p)
				break
	shown.append(("%s: %s" % [name_text, text]) if name_text != "" else text)
	if actor and actor.has_method("talk"):
		actor.talk(2.5)
	elif actor and actor.has_method("hold"):
		actor.hold(2.5)
	main.hud.story_say(name_text, text, tex)
	if auto:
		if pause_on != "" and pause_on in text:
			pause_on = ""
			holding = true
			while holding:
				await get_tree().process_frame
		await get_tree().create_timer(auto_line + (0.9 + text.length() * 0.035 if cinematic else 0.0)).timeout
	else:
		await main.hud.story_next


func _choose(op: Dictionary) -> int:
	var texts := []
	for o in op["options"]:
		texts.append(_fill(str(o["text"])))
	main.hud.story_choices(_fill(str(op["prompt"])), texts)
	var idx := 0
	if auto:
		await get_tree().create_timer(2.6 if cinematic else 0.08).timeout
		idx = int(auto_choices.pop_front()) if not auto_choices.is_empty() else 0
		main.hud.story_clear_choices()
	else:
		idx = await main.hud.story_chosen
	return clampi(idx, 0, texts.size() - 1)


func _fill(t: String) -> String:
	return t.format({"player": str(Data.character(Data.player_character()).get("name", "Nora"))})


# --- commands -------------------------------------------------------------------

## The node for a name in a scene: the heroine ("player", "you", "nora"...) or a villager id.
func actor(who: String) -> Node3D:
	var w := who.to_lower()
	if w == "" :
		return null
	if w in ["player", "you", "me", Data.player_character()]:
		return main.player
	return main._villager(w)


## "by <building> x z" in a command's arguments is a spot in that building's own space (its front
## toward +z; the kinds are Town.built's, such as building_office or market_stall), turned into
## world x z wherever the world editor has put the building now. A scene that walks round the
## town keeps working when Alex rearranges it.
func _by_buildings(args: Array) -> Array:
	var i := args.find("by")
	if i < 0 or i + 3 >= args.size():
		return args
	var at: Dictionary = main._spot_at({"building": str(args[i + 1]), "pos": [float(args[i + 2]), float(args[i + 3])]})
	if at.is_empty():
		push_warning("story: no %s in the world for 'by'" % args[i + 1])
		return args.slice(0, i) + [str(args[i + 2]), str(args[i + 3])] + args.slice(i + 4)
	var p: Vector3 = at["pos"]
	return args.slice(0, i) + [str(p.x), str(p.z)] + args.slice(i + 4)


## Runs one command. Returns a jump target (op index), -1 to end the scene, or null.
func _cmd(op: Dictionary, sc: Dictionary) -> Variant:
	var a: Array = op["args"]
	if str(op["cmd"]) in ["walk", "place", "face", "camera", "home", "prop", "prop_move"]:
		a = _by_buildings(a)
	match str(op["cmd"]):
		"camera":
			var dist := float(main.cam_glide.get("dist", 9.0))
			var pos = null
			var yaw = null # "yaw 200": which side the camera looks from, in degrees (45 is the usual)
			var yi := a.find("yaw")
			if yi >= 0 and yi + 1 < a.size():
				var yv := str(a[yi + 1])
				if yv.is_valid_float():
					yaw = deg_to_rad(float(yv))
				else: # "yaw building_cafe": a three-quarter view of that building's front
					var front: Dictionary = main._spot_at({"building": yv, "pos": [0.0, 0.0]})
					if not front.is_empty():
						yaw = float(front["yaw"]) + deg_to_rad(25.0)
				a = a.slice(0, yi) + a.slice(yi + 2)
			var low := not a.is_empty() and str(a[-1]) == "low"
			if low:
				a = a.slice(0, a.size() - 1)
			if a.is_empty() or str(a[0]) in ["player", "off", "follow"]:
				pos = main.player.position + Vector3(0, 0.9, 0)
				if a.size() > 1:
					dist = float(a[1])
			elif str(a[0]) == "between" and a.size() >= 3:
				var n1 := actor(str(a[1]))
				var n2 := actor(str(a[2]))
				if n1 and n2:
					pos = (n1.position + n2.position) * 0.5 + Vector3(0, 0.9, 0)
				if a.size() > 3:
					dist = float(a[3])
			elif str(a[0]).is_valid_float():
				pos = Vector3(float(a[0]), 0.9, float(a[1]) if a.size() > 1 else 0.0)
				if a.size() > 2:
					dist = float(a[2])
			else:
				var n := actor(str(a[0]))
				if n:
					pos = n.position + Vector3(0, 0.9, 0)
				if a.size() > 1:
					dist = float(a[1])
			if yaw != null:
				main.cam_yaw_goal = yaw
			if pos != null:
				main.cam_follow = false
				main.cam_glide = {"pos": pos, "dist": dist}
				if low:
					# aim at seated head height, so they sit above the dialogue box rather than behind it
					pos.y -= 0.7
					main.cam_glide["pos"] = pos
					main.cam_glide["pitch"] = main.CAM_PITCH_LOW
				if auto and not cinematic:
					main.cam_target = pos
					main.cam_dist = dist
					main.cam_pitch = float(main.cam_glide.get("pitch", main.CAM_PITCH))
		"fade":
			var secs := float(a[1]) if a.size() > 1 else 0.8
			await main.hud.story_fade(1.0 if str(a[0]) == "out" else 0.0, 0.01 if auto and not cinematic else secs)
		"title":
			await main.hud.story_title(_fill(str(op["rest"])), 0.2 if auto and not cinematic else 2.6)
		"wait":
			await get_tree().create_timer(0.02 if auto and not cinematic else float(a[0])).timeout
		"anim":
			var n := actor(str(a[0]))
			if n and "anim_override" in n:
				var loop := str(a[1]) if a.size() > 1 else "off"
				n.anim_override = "" if loop == "off" else loop
				if loop != "off" and not _held.has(n):
					_held.append(n)
		"eyes":
			var who := actor(str(a[0]))
			if who and who.get("body") != null and who.body and a.size() > 1:
				var how := str(a[1]).to_lower()
				if how in ["closed", "open"]:
					who.body.set_eyes_closed(how == "closed")
				else:
					who.body.set_mood(how)
		"face":
			var n := actor(str(a[0]))
			if n and a.size() > 2 and str(a[1]).is_valid_float():
				n.face_point(Vector3(float(a[1]), 0, float(a[2])))
			else:
				var t := actor(str(a[1])) if a.size() > 1 else null
				if n and t:
					n.face_point(t.position)
		"walk":
			var n := actor(str(a[0]))
			if n and a.size() >= 3:
				var dest := Vector3(float(a[1]), 0, float(a[2]))
				if n == main.player:
					main.player.walk(main._find_path(main.player.position, dest))
				else:
					n.walk_to(dest, main._find_path(n.position, dest)) # round walls, out through doors
				var t := 0.0 if a.size() < 4 or str(a[3]) != "nowait" else 99.0
				while t < 25.0 and (not main.player.path.is_empty() if n == main.player else n.position.distance_to(dest) > 0.15):
					await get_tree().process_frame
					t += get_process_delta_time()
		"place":
			var n := actor(str(a[0]))
			if n and a.size() >= 3:
				# an optional height after the yaw seats them up on something (the seated loops put
				# the seat at the character's origin)
				var p := Vector3(float(a[1]), float(a[4]) if a.size() > 4 else 0.0, float(a[2]))
				if p.y != 0.0 and not _lifted.has(n):
					_lifted.append(n)
				if n == main.player:
					main.player.walk([])
				n.position = p
				if a.size() > 3:
					n.rotation.y = deg_to_rad(float(a[3]))
				if n != main.player:
					n.settle_at(p)
		"set":
			if not a.is_empty():
				var v: Variant = true
				if a.size() > 1:
					var s := str(a[1])
					v = int(s) if s.is_valid_int() else (float(s) if s.is_valid_float() else (s == "true" if s in ["true", "false"] else s))
				Game.set_flag(str(a[0]), v)
		"unset":
			if not a.is_empty():
				Game.flags.erase(str(a[0]))
		"familiarity", "trust", "romance":
			if a.size() >= 2:
				var who := str(a[0])
				var n := int(str(a[1]).trim_prefix("+"))
				Game.add_stat(who, str(op["cmd"]), n)
				var nm := str(Data.character(who).get("name", who.capitalize()))
				var v = main._villager(who)
				if v:
					nm = v.title
				if op["cmd"] == "trust":
					main.hud.show_toast("%s will remember that." % nm)
				elif op["cmd"] == "romance" and n > 0:
					main.hud.show_toast("Something shifted between you and %s." % nm)
		"give":
			if not a.is_empty():
				var n := int(a[1]) if a.size() > 1 else 1
				if str(a[0]) == "coins":
					Game.coins += n
				else:
					Game.add_item(str(a[0]), n)
		"take":
			if not a.is_empty():
				var n := int(a[1]) if a.size() > 1 else 1
				if str(a[0]) == "coins":
					Game.coins = maxi(0, Game.coins - n)
				else:
					Game.take_item(str(a[0]), n)
		"memory":
			var on := a.is_empty() or str(a[0]) != "off"
			var secs := float(a[1]) if a.size() > 1 else 1.4
			await main.hud.set_memory(on, 0.01 if auto and not cinematic else secs)
		"journal":
			var rest := _fill(str(op["rest"]))
			var kind := "note"
			if rest.begins_with("memory ") or rest.begins_with("note "):
				kind = rest.get_slice(" ", 0)
				rest = rest.substr(kind.length() + 1)
			var bar := rest.find("|")
			var title := rest.substr(0, bar).strip_edges() if bar >= 0 else rest.strip_edges()
			var text := rest.substr(bar + 1).strip_edges() if bar >= 0 else ""
			Game.add_journal(kind, title, text)
			if main.audio:
				main.audio.play("journal", -8.0)
			main.hud.show_toast(("A memory, written down: " if kind == "memory" else "Journal: ") + title)
		"time":
			if not a.is_empty():
				var t := str(a[0])
				Game.hour = float(t.get_slice(":", 0)) + float(t.get_slice(":", 1)) / 60.0 if ":" in t else float(t)
		"sleep":
			Game.sleep()
		"toast":
			main.hud.show_toast(_fill(str(op["rest"])))
		"goal":
			var rest := _fill(str(op["rest"]))
			var bar := rest.find("|")
			var pos = null
			if bar >= 0:
				var xz := rest.substr(bar + 1).strip_edges().split(" ", false)
				if xz.size() >= 2:
					pos = Vector2(float(xz[0]), float(xz[1]))
				rest = rest.substr(0, bar).strip_edges()
			main.set_goal(rest, pos)
		"weather":
			main.set_weather(str(a[0]) if not a.is_empty() else "clear")
		"prop":
			if a.size() >= 4:
				main.spawn_prop(str(a[0]), str(a[1]), Vector3(float(a[2]), 0, float(a[3])), float(a[4]) if a.size() > 4 else 0.0)
		"prop_move":
			if a.size() >= 4:
				main.move_prop(str(a[0]), Vector3(float(a[1]), 0, float(a[2])), 0.05 if auto and not cinematic else float(a[3]))
		"prop_remove":
			if not a.is_empty():
				main.remove_prop(str(a[0]))
		"phone":
			var caller := "" if a.is_empty() or str(a[0]) == "off" else str(op["rest"])
			main.hud.set_phone(caller)
		"shake":
			main.shake(float(a[0]) if not a.is_empty() else 0.4)
		"sheep":
			main.sheep_out(not a.is_empty() and str(a[0]) == "out")
		"music":
			if main.audio:
				main.audio.play_tune(str(a[0]) if not a.is_empty() else "off", 0.1 if auto and not cinematic else 2.5)
		"farm":
			# Act 1's farm (scripts/homestead.gd): @farm note (Gran's note, her 100 coins, rent starts),
			# @farm strays (two stray sheep graze past the pond)
			var home = main.homestead
			match str(a[0]) if not a.is_empty() else "":
				"note":
					Game.add_item(home.NOTE_ITEM)
					Game.coins += home.econ("gran_coins", 100)
					Game.set_flag("rent_on")
					home.start_rent()
					home.take_note()
				"strays":
					home.spawn_strays()
		"home":
			if a.size() >= 2:
				if str(a[1]) == "off":
					main.set_home(str(a[0]))
				elif a.size() >= 3:
					main.set_home(str(a[0]), Vector3(float(a[1]), 0, float(a[2])))
		"if":
			var parts := Story.split_if(str(op["rest"]))
			if Story.condition(parts[0]):
				return int(sc["labels"].get(parts[1], -1))
		"goto":
			return int(sc["labels"].get(str(op["rest"]), -1))
		"end":
			return -1
	return null
