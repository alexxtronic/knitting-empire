extends RefCounted
## Story scenes, written as plain text in res://data/scenes/*.scene and played by story_player.gd.
##
##   == meet_rowan                  starts a scene (one file can hold many)
##   @trigger talk rowan            when it plays: "talk <villager>", "start" (a new game),
##                                   "area <name>" (walking into a place from data/areas.json;
##                                   area scenes must be @once), "event knit_done" (finishing a knit),
##                                   "gift rowan sweater" (giving someone a gift, after its usual effects)
##   @requires met_rowan            only if a flag is set; "!flag" = only if it isn't
##   @when hearts rowan >= 2        only if a condition holds (anything @if takes); one per line, all must hold
##   @once                          play it only once per save
##   @daily                         at most one @daily scene plays per day (spaces out talk topics)
##   # a comment
##   Rowan (wry): Your fence leans.  a line: speaker, optional mood (picks the portrait), text
##   > The rain doesn't let up.      narration (no speaker)
##   ? What do you say?              a choice; the options follow, one per line:
##   - I'll fix it. -> fixed | trust rowan +2; set fence_promise
##                                   option text, optional "-> label" to jump to, optional
##                                   "| effects" separated by ";" (any command below, minus the @)
##   @label fixed                    a place to jump to
##   @goto done / @end
##   @if met_rowan -> label          jump if a flag is set ("!flag" for not set), or
##   @if trust rowan >= 10 -> label  compare a relationship stat (familiarity, trust, romance)
##   @set flag [value] / @unset flag
##   @trust rowan +2                 also @familiarity, @romance
##   @camera rowan [distance]        point the camera at someone (or "@camera x z [distance]",
##                                   "@camera between rowan nora [distance]" to frame two people,
##                                   "@camera player" to follow the player again; add "low" at the
##                                   end for a low, close-to-eye-level angle)
##   @fade out [seconds] / @fade in [seconds]
##   @title Act 1: Cast On           a title card over the screen
##   @wait seconds
##   @anim rowan Work                hold someone in an animation loop ("@anim rowan off" to release)
##   @face nora rowan                turn someone toward someone (or toward x, z)
##   @eyes nora closed               shut someone's eyes ("open" to open them), or set the look of
##                                   their eyes without a line: happy, warm, wry, sad, worried, angry, sleepy
##   @walk rowan 30 4 [nowait]       walk someone to x, z and wait until they arrive (or don't)
##   @walk steve by building_homegoods 0 4  any x z can be "by <building> x z": a spot in front of
##                                   that building (its own space, front toward +z), wherever it stands;
##                                   "@camera ... yaw building_cafe" looks at that building's front
##   @place rowan 30 4 [yaw] [height]  put someone at x, z instantly (villagers stay there); a height
##                                   seats them up on something, e.g. 0.43 on a rock, for SitIdle
##   @give wool 3 / @take wool 1     change the inventory
##   @toast Some text                a small notice
##   @goal Walk to the farm | 24 3   the goal shown at the top of the screen, with a marker at x, z
##                                   (the "| x z" part is optional; "@goal" alone clears it)
##   @weather rain / @weather clear
##   @prop bus bus1 40 6 90          put a prop down: bus, suitcase, rail, letter, lantern, rock; name, x, z, yaw
##   @prop_move bus1 70 6 4          slide it to x, z over some seconds (doesn't wait)
##   @prop_remove bus1
##   @phone Max / @phone off      a phone ringing on screen
##   @shake 0.4                      shake the camera
##   @sheep out / @sheep home        three sheep get out by the south fence, or go back in
##   @home rowan 21 5                a villager stays at x, z (survives saves); "@home rowan off"
##   @memory on [seconds]            a memory thread: the screen fades to warm sepia ("@memory off")
##   @journal memory Title | text    write in her journal ("memory" or "note"); a toast says so
##   @time 21.5                      set the clock (hours, or 21:30)
##   @sleep                          she sleeps: next morning, a new day (crops grow, prices change)
##   @give coins 60 / @take coins 5  coins work like items
##   @if has sweater -> label        jump if she has an item ("has wool 3" for at least 3)
##   @if hearts rowan >= 3 -> label  friendship hearts (0-5); "@if hour < 17 -> label" checks the clock
## Text can use {player} for the heroine's name.

const SCENE_DIR := "res://data/scenes"
const COMMANDS := ["camera", "fade", "title", "wait", "anim", "face", "eyes", "walk", "place", "set", "unset",
	"familiarity", "trust", "romance", "if", "goto", "end", "give", "take", "toast",
	"goal", "weather", "prop", "prop_move", "prop_remove", "phone", "shake", "sheep", "home",
	"memory", "journal", "time", "sleep", "music", "farm"]
const HEADERS := ["label", "trigger", "requires", "when", "once", "daily"]
const STATS := ["familiarity", "trust", "romance"]

static var _scenes := {}
static var _loaded := false
static var errors: Array = []


static func scenes() -> Dictionary:
	if not _loaded:
		load_all()
	return _scenes


static func has_scene(id: String) -> bool:
	return scenes().has(id)


static func load_all() -> void:
	_scenes = {}
	errors = []
	_loaded = true
	var dir := DirAccess.open(SCENE_DIR)
	if dir == null:
		return
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		if str(f).ends_with(".scene"):
			parse_into(FileAccess.get_file_as_string(SCENE_DIR + "/" + f), str(f))


## Parses scene text and adds its scenes. Problems go to `errors` with file:line.
static func parse_into(text: String, src := "text") -> void:
	var cur = null
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		var where := "%s:%d" % [src, i + 1]
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("=="):
			var id := line.substr(2).strip_edges()
			if _scenes.has(id):
				errors.append("%s: scene '%s' is defined twice" % [where, id])
			cur = {"id": id, "ops": [], "labels": {}, "trigger": [], "requires": [], "when": [], "once": false, "daily": false, "where": where}
			_scenes[id] = cur
			continue
		if cur == null:
			errors.append("%s: text before the first '== scene_name' line" % where)
			continue
		var ops: Array = cur["ops"]
		if line.begins_with("- "):
			if ops.is_empty() or ops[-1]["op"] != "choice":
				errors.append("%s: an option needs a '?' choice line above it" % where)
				continue
			ops[-1]["options"].append(_parse_option(line.substr(2), where))
			continue
		if line.begins_with("?"):
			ops.append({"op": "choice", "prompt": line.substr(1).strip_edges(), "options": [], "where": where})
			continue
		if line.begins_with(">"):
			ops.append({"op": "say", "who": "", "name": "", "mood": "", "text": line.substr(1).strip_edges(), "where": where})
			continue
		if line.begins_with("@"):
			var c := parse_command(line.substr(1), where)
			match c["cmd"]:
				"label":
					if c["args"].is_empty():
						errors.append("%s: @label needs a name" % where)
					else:
						cur["labels"][c["args"][0]] = ops.size()
				"trigger":
					cur["trigger"] = c["args"]
				"requires":
					cur["requires"].append_array(c["args"])
				"when":
					cur["when"].append(c["args"])
				"once":
					cur["once"] = true
				"daily":
					cur["daily"] = true
				_:
					ops.append(c)
			continue
		var colon := line.find(":")
		if colon > 0:
			var head := line.substr(0, colon).strip_edges()
			var mood := "neutral"
			var p0 := head.find("(")
			if p0 >= 0 and head.ends_with(")"):
				mood = head.substr(p0 + 1, head.length() - p0 - 2).strip_edges().to_lower()
				head = head.substr(0, p0).strip_edges()
			ops.append({"op": "say", "who": head.to_lower().replace(" ", "_"), "name": head, "mood": mood,
				"text": line.substr(colon + 1).strip_edges(), "where": where})
			continue
		errors.append("%s: can't read this line: %s" % [where, line])


## "trust rowan +2" -> {"op": "cmd", "cmd": "trust", "args": ["rowan", "+2"], "rest": "rowan +2"}
static func parse_command(text: String, where := "") -> Dictionary:
	var t := text.strip_edges()
	var sp := t.find(" ")
	var cmd := (t if sp < 0 else t.substr(0, sp)).to_lower()
	var rest := "" if sp < 0 else t.substr(sp + 1).strip_edges()
	if not (cmd in COMMANDS or cmd in HEADERS):
		errors.append("%s: unknown command '@%s'" % [where, cmd])
	return {"op": "cmd", "cmd": cmd, "args": Array(rest.split(" ", false)), "rest": rest, "where": where}


static func _parse_option(body: String, where: String) -> Dictionary:
	var effects := []
	var bar := body.find("|")
	if bar >= 0:
		for e in body.substr(bar + 1).split(";", false):
			if e.strip_edges() != "":
				effects.append(parse_command(e, where))
		body = body.substr(0, bar)
	var label := ""
	var arrow := body.find("->")
	if arrow >= 0:
		label = body.substr(arrow + 2).strip_edges()
		body = body.substr(0, arrow)
	return {"text": body.strip_edges(), "label": label, "effects": effects, "where": where}


## The jump target inside an @if, e.g. "met_rowan -> done" -> ["met_rowan"], "done".
static func split_if(rest: String) -> Array:
	var a := rest.find("->")
	if a < 0:
		return [[], ""]
	return [Array(rest.substr(0, a).strip_edges().split(" ", false)), rest.substr(a + 2).strip_edges()]


## True if every requirement ("flag" or "!flag") holds.
static func requirements_met(reqs: Array) -> bool:
	for r in reqs:
		var s := str(r)
		var want := not s.begins_with("!")
		if bool(Game.flag(s.trim_prefix("!"))) != want:
			return false
	return true


## Evaluates @if conditions: ["flag"], ["!flag"], or ["trust", "rowan", ">=", "10"].
static func condition(cond: Array) -> bool:
	if cond.size() == 1:
		return requirements_met(cond)
	if str(cond[0]) == "has" and cond.size() in [2, 3]:
		return Game.has_item(str(cond[1]), int(cond[2]) if cond.size() == 3 else 1)
	if cond.size() == 4 and (str(cond[0]) in STATS or str(cond[0]) == "hearts"):
		var v := float(Game.hearts(str(cond[1])) if str(cond[0]) == "hearts" else Game.stat(str(cond[1]), str(cond[0])))
		return _compare(v, str(cond[2]), float(cond[3]))
	if cond.size() == 3 and str(cond[0]) == "hour":
		var t := str(cond[2])
		var h := float(t) if not ":" in t else float(t.get_slice(":", 0)) + float(t.get_slice(":", 1)) / 60.0
		return _compare(Game.hour, str(cond[1]), h)
	return false


static func _compare(v: float, op: String, n: float) -> bool:
	match op:
		">=": return v >= n
		">": return v > n
		"<=": return v <= n
		"<": return v < n
		"==", "=": return is_equal_approx(v, n)
		"!=": return not is_equal_approx(v, n)
	return false


## A condition @if and @when can read: a flag, "has item [n]", "<stat|hearts> name op n", "hour op h".
static func well_formed(c: Array) -> bool:
	var ops := [">=", ">", "<=", "<", "==", "=", "!="]
	if c.size() == 1:
		return true
	if str(c[0]) == "has":
		return c.size() in [2, 3]
	if c.size() == 4 and (str(c[0]) in STATS or str(c[0]) == "hearts"):
		return str(c[2]) in ops
	if c.size() == 3 and str(c[0]) == "hour":
		return str(c[1]) in ops
	return false


## True if a scene's @requires and @when all hold, and @once/@daily don't rule it out today.
static func can_play(id: String) -> bool:
	var sc: Dictionary = scenes()[id]
	if sc["once"] and Game.flag("seen_" + id):
		return false
	if sc["daily"] and int(Game.flag("daily_scene_day", -1)) == Game.day:
		return false
	if not requirements_met(sc["requires"]):
		return false
	for c in sc["when"]:
		if not condition(c):
			return false
	return true


## The first scene whose @trigger matches (e.g. "talk", "rowan") and can play now. `extra` is the
## third word for triggers that have one ("gift rowan sweater"); a trigger without it matches any.
static func find_trigger(kind: String, target := "", extra := "") -> String:
	for id in scenes():
		var sc: Dictionary = _scenes[id]
		var trig: Array = sc["trigger"]
		if trig.is_empty() or str(trig[0]) != kind:
			continue
		if target != "" and (trig.size() < 2 or str(trig[1]) != target):
			continue
		if extra != "" and trig.size() >= 3 and str(trig[2]) != extra:
			continue
		if can_play(id):
			return id
	return ""


## Checks every scene: jumps go to labels that exist, choices have options, commands have arguments.
static func validate() -> Array:
	scenes()
	var errs := errors.duplicate()
	for id in _scenes:
		var sc: Dictionary = _scenes[id]
		var labels: Dictionary = sc["labels"]
		if not sc["trigger"].is_empty() and str(sc["trigger"][0]) == "area" and not sc["once"]:
			errs.append("%s: an area scene must be @once (it would replay while you stand there)" % sc["where"])
		for c in sc["when"]:
			if not well_formed(c):
				errs.append("%s: can't read '@when %s' (see @if at the top of story.gd)" % [sc["where"], " ".join(c)])
		for op in sc["ops"]:
			if op["op"] == "choice":
				if op["options"].is_empty():
					errs.append("%s: a choice with no options" % op["where"])
				for o in op["options"]:
					if o["label"] != "" and not labels.has(o["label"]):
						errs.append("%s: no '@label %s' in scene %s" % [o["where"], o["label"], id])
			elif op["op"] == "cmd":
				var target := ""
				if op["cmd"] == "goto":
					target = op["rest"]
				elif op["cmd"] == "if":
					var parts := split_if(op["rest"])
					target = parts[1]
					if target == "":
						errs.append("%s: @if needs '-> label'" % op["where"])
					elif not well_formed(parts[0]):
						errs.append("%s: can't read the condition in '@if %s'" % [op["where"], op["rest"]])
				if target != "" and not labels.has(target):
					errs.append("%s: no '@label %s' in scene %s" % [op["where"], target, id])
				var need := {"prop": 4, "prop_move": 4, "prop_remove": 1, "weather": 1, "phone": 1, "sheep": 1, "home": 2, "walk": 3, "place": 3}
				if need.has(op["cmd"]) and op["args"].size() < int(need[op["cmd"]]):
					errs.append("%s: @%s needs more (see the list at the top of story.gd)" % [op["where"], op["cmd"]])
				if op["cmd"] in STATS and op["args"].size() < 2:
					errs.append("%s: @%s needs a name and an amount, like '@%s rowan +2'" % [op["where"], op["cmd"], op["cmd"]])
	return errs
