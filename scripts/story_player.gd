extends Node
## Plays story scenes (see story.gd for the text format) in the world: lines in the dialogue
## box with mood portraits, choices, camera cues, fades, title cards, and actors who walk,
## turn and animate. Added as a child of main.gd.

const Story = preload("res://scripts/story.gd")
const Data = preload("res://scripts/data.gd")

signal scene_finished(id: String)

var main: Node
var playing := ""
var auto := false # autotest: lines advance by themselves and choices come from auto_choices
var auto_choices: Array = []
var shown: Array = [] # every line shown, "Name: text" (for the autotest)
var _held: Array = [] # actors put into an animation by @anim
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
	var sc: Dictionary = Story.scenes()[id]
	var hud = main.hud
	_cam0 = {"follow": main.cam_follow, "dist": main.cam_dist}
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
	for a in _held:
		if is_instance_valid(a):
			a.anim_override = ""
	_held.clear()
	main.cam_glide = {}
	await hud.story_end()
	for v in main.villagers:
		if v.tag:
			v.tag.visible = true
	main.cam_dist = _cam0["dist"]
	main.cam_follow = _cam0["follow"]
	if main.cam_follow:
		main.cam_target = main.player.position
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
		await get_tree().create_timer(0.08).timeout
	else:
		await main.hud.story_next


func _choose(op: Dictionary) -> int:
	var texts := []
	for o in op["options"]:
		texts.append(_fill(str(o["text"])))
	main.hud.story_choices(_fill(str(op["prompt"])), texts)
	var idx := 0
	if auto:
		await get_tree().create_timer(0.08).timeout
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


## Runs one command. Returns a jump target (op index), -1 to end the scene, or null.
func _cmd(op: Dictionary, sc: Dictionary) -> Variant:
	var a: Array = op["args"]
	match str(op["cmd"]):
		"camera":
			var dist := float(main.cam_glide.get("dist", 9.0))
			var pos = null
			if a.is_empty() or str(a[0]) in ["player", "off", "follow"]:
				pos = main.player.position + Vector3(0, 0.9, 0)
				if a.size() > 1:
					dist = float(a[1])
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
			if pos != null:
				main.cam_follow = false
				main.cam_glide = {"pos": pos, "dist": dist}
				if auto:
					main.cam_target = pos
					main.cam_dist = dist
		"fade":
			var secs := float(a[1]) if a.size() > 1 else 0.8
			await main.hud.story_fade(1.0 if str(a[0]) == "out" else 0.0, 0.01 if auto else secs)
		"title":
			await main.hud.story_title(_fill(str(op["rest"])), 0.2 if auto else 2.6)
		"wait":
			await get_tree().create_timer(0.02 if auto else float(a[0])).timeout
		"anim":
			var n := actor(str(a[0]))
			if n and "anim_override" in n:
				var loop := str(a[1]) if a.size() > 1 else "off"
				n.anim_override = "" if loop == "off" else loop
				if loop != "off" and not _held.has(n):
					_held.append(n)
		"face":
			var n := actor(str(a[0]))
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
					n.walk_to(dest)
				var t := 0.0
				while t < 25.0 and n.position.distance_to(dest) > 0.15:
					await get_tree().process_frame
					t += get_process_delta_time()
		"place":
			var n := actor(str(a[0]))
			if n and a.size() >= 3:
				var p := Vector3(float(a[1]), 0, float(a[2]))
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
				Game.add_item(str(a[0]), int(a[1]) if a.size() > 1 else 1)
		"take":
			if not a.is_empty():
				Game.take_item(str(a[0]), int(a[1]) if a.size() > 1 else 1)
		"toast":
			main.hud.show_toast(_fill(str(op["rest"])))
		"if":
			var parts := Story.split_if(str(op["rest"]))
			if Story.condition(parts[0]):
				return int(sc["labels"].get(parts[1], -1))
		"goto":
			return int(sc["labels"].get(str(op["rest"]), -1))
		"end":
			return -1
	return null
