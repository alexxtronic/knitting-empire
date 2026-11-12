extends Node
## Jobs: a steady wage beside knitting (data/economy.json "jobs"). Giorgio offers work at Heart
## Bakery after Act 1, Sabrina's Coffee Shop takes her on once Sabrina trusts her, and Barbara
## shares the post round. She holds one job at a time (Game.flags "job") and works at most one
## shift a day ("job_shift_day"). The offers are story scenes, "job_<id>" in data/scenes/jobs.scene.
##
## A shift: she clocks in by talking to the boss in the job's hours, then walks from task to task
## (the goal line and its marker show the next one) and works each for a few seconds. The clock
## moves on with each task, her needs drain, and the pay comes at the end. Click away and she picks
## the shift up again a moment later; walk off (LEAVE_DIST from the next task) or tell the boss
## you're done and she's paid for what she did. Added as a child of main.gd.

const Data = preload("res://scripts/data.gd")
const Story = preload("res://scripts/story.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")

const RESUME_AFTER := 2.0 # s idle away from the next task before she picks the shift up again
const LEAVE_DIST := 30.0 # m from the next task: past this, she has walked off the job

var main: Node
var nudge := true # after Act 1, a goal that sends her to Giorgio (off in the autotest)
var shift := {} # the shift she is working: {"id", "stops", "i", "hour0", "goal"}
var _idle_t := 0.0
var _job_seen: Variant = null # the job last time we looked, to say so when it changes


## Every job in data/economy.json, by id.
static func defs() -> Dictionary:
	var out := {}
	var all: Dictionary = Data.economy().get("jobs", {})
	for k in all:
		if not str(k).begins_with("_"):
			out[str(k)] = all[k]
	return out


static func def(id: String) -> Dictionary:
	return defs().get(id, {})


## The job she has ("" if none).
static func current() -> String:
	var j: Variant = Game.flag("job", "")
	return str(j) if j is String else ""


## The job `vid` gives out ("" if they don't).
static func job_of(vid: String) -> String:
	var all := defs()
	for id in all:
		if str(all[id].get("boss", "")) == vid:
			return id
	return ""


func working() -> bool:
	return not shift.is_empty()


## True once Act 1 is behind her (or on a farm that never had it).
static func story_ready() -> bool:
	return Game.flag("act1_done") == true or Game.flag("story_farm") != true


## True if the boss would offer job `id` now: the story is far enough on and they trust her enough.
static func offer_due(id: String) -> bool:
	var d := def(id)
	if d.is_empty() or not story_ready():
		return false
	return Game.stat(str(d["boss"]), "trust") >= int(d.get("trust", -1000))


## The offer scene to play when she talks to `vid`, the first time it's due ("" if none).
static func offer_scene(vid: String) -> String:
	var id := job_of(vid)
	if id == "" or current() == id or Game.flag("job_offer_" + id) == true:
		return ""
	var sc := "job_" + id
	if not Story.has_scene(sc) or Game.flag("seen_" + sc) == true or not offer_due(id):
		return ""
	return sc


## Why she can't start a shift of job `id` now ("" if she can).
func shift_problem(id: String) -> String:
	var d := def(id)
	var st: Array = d.get("start", [0, 24])
	if working():
		return "on shift"
	if int(Game.flag("job_shift_day", 0)) == Game.day:
		return "already worked today"
	if Game.hour < float(st[0]) or Game.hour >= float(st[1]):
		return "starts %s" % _hours(d)
	if Game.energy < float(d.get("drain", {}).get("energy", 0.0)):
		return "too tired"
	return ""


## The rows the boss's menu gets: take the job, work a shift, stop early, or leave the job.
func actions_for(vid: String) -> Array:
	var id := job_of(vid)
	if id == "":
		return []
	var d := def(id)
	var rows := []
	if working() and shift["id"] == id:
		var left: int = shift["stops"].size() - int(shift["i"])
		rows.append(_row("job_end", "Stop the shift early  (%d to go)" % left))
	elif current() == id:
		var why := shift_problem(id)
		rows.append(_row("job_shift", "Work a shift  (%dc)" % int(d["pay"]) if why == "" else "Work a shift  (%s)" % why, why == ""))
		rows.append(_row("job_quit", "Leave the job"))
	elif Game.flag("job_offer_" + id) == true:
		var cur := current()
		var label := "Take the job  (starts %s, %dc)" % [_hours(d), int(d["pay"])]
		if cur != "":
			label = "Take the job instead of %s" % str(def(cur).get("name", cur))
		rows.append(_row("job_take", label))
	return rows


func _row(id: String, label: String, enabled := true) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "group": "Work"}


## A row from the boss's menu (main._villager_action passes the "job_..." ones here).
func action(v, act: String) -> void:
	var id := job_of(v.vid)
	if id == "":
		return
	var d := def(id)
	match act:
		"job_take":
			Game.set_flag("job", id)
			_announce()
		"job_quit":
			if current() == id:
				Game.set_flag("job", "")
				_job_seen = ""
				main.hud.show_toast("You left %s." % str(d["name"]))
		"job_shift":
			if current() == id and shift_problem(id) == "":
				main._say(v, _line(d, "start"))
				start(id)
		"job_end":
			if working() and shift["id"] == id:
				finish()


## Clocks in: works out the shift's stops and sends her to the first.
func start(id: String) -> bool:
	if current() != id or shift_problem(id) != "":
		return false
	var st := stops(id)
	if st.is_empty():
		return false
	var goal: Variant = Game.flag("goal", "")
	var gp: Variant = Game.flag("goal_pos", null)
	shift = {"id": id, "stops": st, "i": 0, "hour0": Game.hour, "goal": [goal, gp]}
	_idle_t = 0.0
	_next()
	return true


## The shift's stops in order: {"pos", "face" (world Vector3s), "text", "secs"}.
func stops(id: String) -> Array:
	var d := def(id)
	var tasks: Array = d.get("tasks", [])
	var out := []
	if bool(d.get("round", false)):
		var task: Dictionary = tasks[0] if not tasks.is_empty() else {}
		var boss = main._villager(str(d["boss"]))
		var from: Vector3 = boss.position if boss else main.player.position
		# Barbara's doors in town; her last two stops are Nora's farm and her own spot on the plaza
		for p in main.post_round_stops(from).slice(0, -2):
			out.append({"pos": p, "face": _nearest_building(p), "text": str(task.get("text", "Delivering")), "secs": float(task.get("secs", 1.5))})
		return out
	for r in int(d.get("rounds", 1)):
		for t in tasks:
			var k: Dictionary = main._spot_at({"building": str(d["building"]), "pos": t["at"], "talk": t.get("face", t["at"])})
			if k.is_empty():
				continue
			out.append({"pos": k["pos"], "face": k["talk"], "text": str(t["text"]), "secs": float(t.get("secs", 2.0))})
	return out


func _nearest_building(p: Vector3) -> Vector3:
	var best := p + Vector3(0, 0, -1)
	var bd := INF
	for b in Town.built:
		if not is_instance_valid(b[0]) or not (b[0] as Node3D).visible:
			continue
		var o: Vector3 = (b[0] as Node3D).global_position
		if o.distance_to(p) < bd:
			bd = o.distance_to(p)
			best = o
	return best


## Sends her to the next task, or ends the shift when there are none left.
func _next() -> void:
	if not working():
		return
	var i: int = shift["i"]
	var st: Array = shift["stops"]
	if i >= st.size():
		finish()
		return
	var s: Dictionary = st[i]
	var d := def(str(shift["id"]))
	var p: Vector3 = s["pos"]
	main.set_goal("Shift at %s: %s  (%d of %d)" % [str(d["name"]), str(s["text"]), i + 1, st.size()], Vector2(p.x, p.z))
	main.player.walk(main._find_path(main.player.position, p), _arrived.bind(i))


func _arrived(i: int) -> void:
	if not working() or int(shift["i"]) != i:
		return
	var s: Dictionary = shift["stops"][i]
	var d := def(str(shift["id"]))
	var n: float = float(shift["stops"].size())
	var drain: Dictionary = d.get("drain", {})
	var e := float(drain.get("energy", 0.0)) / n
	if Game.energy < e:
		main.hud.show_toast("You're too tired to carry on.")
		finish()
		return
	Game.energy -= e
	for need in drain:
		if str(need) != "energy":
			Game.add_need(str(need), -float(drain[need]) / n)
	main.player.face_point(s["face"])
	main.player.start_activity(str(s["text"]), float(s["secs"]), _task_done.bind(i))


func _task_done(i: int) -> void:
	if not working() or int(shift["i"]) != i:
		return
	shift["i"] = i + 1
	var d := def(str(shift["id"]))
	# the shift's hours go by over its tasks (and never backwards, if the clock ran ahead)
	var want: float = float(shift["hour0"]) + float(d.get("hours", 0.0)) * float(i + 1) / float(shift["stops"].size())
	Game.hour = maxf(Game.hour, want)
	_next()


## Clocks out: pays for what she did (all of it, and the perk, for a full shift).
func finish() -> int:
	if not working():
		return 0
	var id := str(shift["id"])
	var d := def(id)
	var done: int = shift["i"]
	var total: int = shift["stops"].size()
	var full := done >= total
	var pay := int(round(float(d["pay"]) * float(done) / float(total)))
	var old_goal: Array = shift["goal"]
	shift = {}
	Game.coins += pay
	if done > 0:
		Game.set_flag("job_shift_day", Game.day)
		Game.set_flag("job_shifts_" + id, int(Game.flag("job_shifts_" + id, 0)) + 1)
	var boss := str(d["boss"])
	var text := "Shift over: +%dc" % pay
	if full:
		Game.add_friendship(boss, 6)
		Game.add_stat(boss, "trust", 1)
		var perk: Dictionary = d.get("perk", {})
		for need in perk:
			Game.add_need(str(need), float(perk[need]))
		text = "Shift done at %s: +%dc. %s" % [str(d["name"]), pay, str(d.get("perk_text", ""))]
		var v = main._villager(boss)
		if v and v.position.distance_to(main.player.position) < 6.0:
			main._say(v, _line(d, "done"))
	elif done > 0:
		text = "You stopped early: +%dc for %d of %d." % [pay, done, total]
	else:
		text = "You left before doing anything. No pay today."
	main.player.cancel_activity()
	var g: Variant = old_goal[0]
	var gp: Variant = old_goal[1]
	if g is String and g != "" and gp is Array:
		main.set_goal(g, Vector2(float(gp[0]), float(gp[1])))
	else:
		main.set_goal(g if g is String else "")
	main.hud.show_toast(text)
	if full:
		main._story_event_soon("shift_" + id) # a hook for scenes: "@trigger event shift_bakery"
	return pay


## Twice a second from main._process: picks an interrupted shift up again, ends one she walked
## away from, says so when the job changes, and points her to Giorgio once Act 1 is done.
func update(delta: float) -> void:
	if main.title_on or _job_seen == null: # a game just loaded: nothing has changed yet
		_job_seen = current()
		return
	if current() != str(_job_seen):
		_announce()
	if main.story.is_playing() or main.sleeping or main.title_on:
		return
	if not working():
		_update_nudge()
		return
	var pl = main.player
	if pl.busy or not pl.path.is_empty() or main.knit.active or main.hud.is_chat_open():
		_idle_t = 0.0
		return
	var s: Dictionary = shift["stops"][int(shift["i"])]
	var p: Vector3 = s["pos"]
	if Vector2(pl.position.x - p.x, pl.position.z - p.z).length() > LEAVE_DIST:
		main.hud.show_toast("You walked off the job.")
		finish()
		return
	_idle_t += delta
	if _idle_t > RESUME_AFTER:
		_idle_t = 0.0
		_next()


## A toast when she takes a job (from a scene or the boss's menu): its hours and pay.
func _announce() -> void:
	var id := current()
	var was := str(_job_seen) if _job_seen != null else ""
	_job_seen = id
	if id == "" or main.title_on:
		return
	var d := def(id)
	var boss = main._villager(str(d["boss"]))
	var who: String = boss.title if boss else str(d["boss"])
	var text := "You work at %s now: talk to %s from %s to start a shift (%dc)." % [str(d["name"]), who, _hours(d), int(d["pay"])]
	if was != "" and was != id:
		text = "You left %s. " % str(def(was).get("name", was)) + text
	main.hud.show_toast(text)


func _update_nudge() -> void:
	if not nudge or Game.flag("job_nudged") == true or Game.flag("story_farm") != true or Game.flag("act1_done") != true:
		return
	if current() != "" or Game.flag("seen_job_bakery") == true or str(Game.flag("goal", "")) not in ["", "false"]:
		return
	var k: Dictionary = Interiors.keeper("bakery")
	if k.is_empty():
		return
	Game.set_flag("job_nudged")
	var t: Vector3 = k["talk"]
	main.set_goal("Giorgio asked to see you at Heart Bakery", Vector2(t.x, t.z))


func _line(d: Dictionary, kind: String) -> String:
	var lines: Array = d.get("lines", {}).get(kind, [])
	if lines.is_empty():
		return ""
	return str(lines[Game.day % lines.size()])


static func _hours(d: Dictionary) -> String:
	var st: Array = d.get("start", [0, 24])
	return "%s to %s" % [_clock(float(st[0])), _clock(float(st[1]))]


static func _clock(h: float) -> String:
	var hh := int(h) % 24
	var suffix := "am" if hh < 12 else "pm"
	var h12 := hh % 12
	if h12 == 0:
		h12 = 12
	var m := int(round((h - floor(h)) * 60.0))
	return ("%d%s" % [h12, suffix]) if m == 0 else ("%d:%02d%s" % [h12, m, suffix])
