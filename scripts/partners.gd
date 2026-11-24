extends Node
## Her partner (Alex, 2026-11-24; docs/DIRECTION.md "Four acts across one life" and its "Decided",
## docs/REVIEW_2026-11-24.md section 4): one partner at a time, out of Rowan, Lars and Gary. Max is
## never one: he is her abusive ex (NEVER, whatever the data says). He is her boyfriend in Act 1, her
## fiancé in Act 2 and her husband in Acts 3 and 4 (title(), data/economy.json "partners" "titles").
##
## - Asking: once a candidate's romance reaches `ask_at`, his menu has "Ask him out" (rows_for()), which
##   plays partner_ask_<id> (data/scenes/partners.scene). With a partner already, only the candidate
##   with the most romance gets the row, and only once he leads the partner by `switch_margin`; his
##   scene then asks her to choose (its "@partner take <id>" or "@partner stay <id>"), so switching is
##   always her decision. Once a day per man.
## - Switching: the old partner is sore for `sore_days` (Game.flags["sore"] = {id: the day it ends})
##   and loses `sore_drop` romance. Turning the new man down costs him `stay_drop`.
## - While a man is sore (update(), polled, so the skip between acts and sleep in a scene are fine):
##   a sharp line now and then when she talks to him (talk_line()); one argument with her partner
##   (argument_for(), partner_argue_<id> in partners.scene, once a spell); and each morning a chance of
##   one mild, silly prank, at most one every `prank_every` days, never in Act 1's guided part
##   (act1_done unset) or in a story scene: the pen gate left open (one sheep out, herded back), her
##   needles hidden (knits one grade lower today, knit_penalty()), a villager told her sweaters itch
##   (won't buy today: SweaterSale.looking() reads Game.flags["pranks"] itself), a pastry eaten out of
##   her bag, the front of her house painted garish (Game.flags["wall_paint"]). Nothing is lost for
##   good: needles, itch and the pen end the next morning; the pastry comes back and the paint comes
##   off when he isn't sore any more. A gift, or talking to him on `mend_talk_days` days, ends it early.
##
## State in Game.flags: "partner" (his id), "partner_since" (the day), "sore", "sore_talks" ({id: [days
## she talked to him]}), "argued" ({id: the sore spell's end day it was used for}), "argue_due"
## ({"day", "id"}), "pranks" ([{"kind", "by", "day", "until" (-1: until he mends)}, and each kind's own
## keys]), "prank_last" (day), "prank_roll" (the last morning rolled), "partner_asked" ({id: day}).
## Numbers come back from a save as floats: read them with int().
##
## Every line and number is a DRAFT until Alex approves it.

const Data = preload("res://scripts/data.gd")
const HouseBuilder = preload("res://scripts/house_builder.gd")
const Story = preload("res://scripts/story.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")

const NEVER := ["max"] # Max is her abusive ex: never a partner, whatever the data says
const KINDS := ["pen", "needles", "itch", "pastry", "paint"]

static var on := true # off in the autotest but for --only=partners: no pranks, sharp lines or arguments

var main: Node # main.gd
var force_roll := -1.0 # the check: the roll every chance is judged by (0..1); below 0, the day's own
var force_prank := "" # the check: the next prank's kind
var _t := 0.0
var _argue_back := "" # the partner we stood beside the sore man for an argument: sent back after


func _ready() -> void:
	name = "Partners"


static func econ() -> Dictionary:
	return Data.economy().get("partners", {})


static func num(key: String, fallback: float) -> float:
	return float(econ().get(key, fallback))


static func line(key: String) -> String:
	return str((econ().get("lines", {}) as Dictionary).get(key, ""))


## The men who can be her partner: the data's list, minus Max, minus anyone not "romance" in villagers.json.
static func candidates() -> Array:
	var romantic := {}
	for v in Data.villagers():
		if bool(v.get("romance", false)):
			romantic[str(v.get("id", ""))] = true
	var out := []
	for id in econ().get("candidates", ["rowan", "lars", "gary"]):
		var s := str(id)
		if not s in NEVER and romantic.has(s):
			out.append(s)
	return out


static func is_candidate(id: String) -> bool:
	return id in candidates()


## Her partner's id, or "". (The acts check probes the flag with {"id", "title"}: read that too.)
static func partner() -> String:
	var p: Variant = Game.flags.get("partner", null)
	if p is Dictionary:
		return str((p as Dictionary).get("id", ""))
	return "" if p == null else str(p)


static func is_partner(id: String) -> bool:
	return id != "" and partner() == id


## What he is to her in act `n` (the current act by default): boyfriend, fiancé, husband.
static func title(n := -1) -> String:
	var a := Game.act if n < 1 else n
	var t: Dictionary = econ().get("titles", {})
	return str(t.get(str(clampi(a, 1, Game.LAST_ACT)), "boyfriend"))


static func display(id: String) -> String:
	for v in Data.villagers():
		if str(v.get("id", "")) == id:
			return str(v.get("name", id.capitalize()))
	return id.capitalize()


## {id: the day it ends} for every man still sore.
static func sore() -> Dictionary:
	var s: Variant = Game.flags.get("sore", {})
	return s if s is Dictionary else {}


static func is_sore(id: String) -> bool:
	return sore().has(id) and Game.day < int(sore()[id])


static func pranks() -> Array:
	var p: Variant = Game.flags.get("pranks", [])
	return p if p is Array else []


static func prank(kind: String) -> Dictionary:
	for p in pranks():
		if p is Dictionary and str(p.get("kind", "")) == kind:
			return p
	return {}


## Her needles are hidden today: her knits come out one grade lower (main._finish_knit).
func knit_penalty() -> int:
	return 1 if not prank("needles").is_empty() else 0


## The menu heading for him: "Shepherd Rowan  (your boyfriend)".
func heading(v) -> String:
	var base: String = v.display_name()
	return "%s  (your %s)" % [base, title()] if is_partner(str(v.vid)) else base


# --- asking him out --------------------------------------------------------------------------------

static func romance(id: String) -> int:
	return Game.stat(id, "romance")


## The candidate who may be asked now, or "": with no partner, any candidate at `ask_at`; with one,
## the candidate with the most romance, if he leads the partner by `switch_margin`.
static func can_ask(id: String) -> bool:
	if not is_candidate(id) or is_partner(id):
		return false
	if romance(id) < int(num("ask_at", 10)):
		return false
	var p := partner()
	if p == "":
		return true
	for c in candidates():
		if c != p and c != id and romance(c) > romance(id):
			return false
	return romance(id) >= romance(p) + int(num("switch_margin", 8))


func rows_for(v) -> Array:
	if v == null:
		return []
	var id := str(v.vid)
	if not can_ask(id):
		return []
	var asked: Dictionary = Game.flags.get("partner_asked", {})
	var label := "Ask %s out" % _obj(id)
	if int(asked.get(id, -99)) == Game.day:
		return [{"id": "noop", "label": label + "  (you asked today)", "enabled": false}]
	return [{"id": "partner_ask", "label": label, "enabled": true}]


## "him" (or the data's "pronoun_obj" for a candidate, should one ever be a woman).
static func _obj(id: String) -> String:
	for v in Data.villagers():
		if str(v.get("id", "")) == id:
			return str(v.get("pronoun_obj", "him"))
	return "him"


func action(v, id: String) -> void:
	if id != "partner_ask" or v == null or not can_ask(str(v.vid)):
		return
	var asked: Dictionary = (Game.flags.get("partner_asked", {}) as Dictionary).duplicate()
	asked[str(v.vid)] = Game.day
	Game.flags["partner_asked"] = asked
	var sid := "partner_ask_%s" % v.vid
	v.face_point(main.player.position, 3.0)
	main.player.face_point(v.position)
	main.story.play(sid)


## A scene's @partner command: "take <id>" makes him her partner (the old one sore), "stay <id>" is
## her turning him down to stay with the one she has.
func cmd(args: Array) -> void:
	if args.size() < 2:
		return
	var id := str(args[1])
	match str(args[0]):
		"take":
			take(id)
		"stay":
			if is_candidate(id):
				Game.add_stat(id, "romance", -int(num("stay_drop", 3)))


## He's her partner now. The one before is sore.
func take(id: String) -> bool:
	if not is_candidate(id) or is_partner(id):
		return false
	var old := partner()
	Game.flags["partner"] = id
	Game.flags["partner_since"] = Game.day
	if is_sore(id): # she came back to him: no hard feelings
		mend(id, false)
	if old != "":
		make_sore(old)
	main.hud.show_toast("%s is your %s now." % [display(id), title()])
	return true


func make_sore(id: String) -> void:
	var s := sore().duplicate()
	s[id] = Game.day + int(num("sore_days", 7))
	Game.flags["sore"] = s
	var t: Dictionary = (Game.flags.get("sore_talks", {}) as Dictionary).duplicate()
	t.erase(id)
	Game.flags["sore_talks"] = t
	Game.add_stat(id, "romance", -int(num("sore_drop", 10)))
	if line("sore") != "":
		main.hud.show_toast(line("sore") % display(id))


## His soreness ends: by a gift, two days of talk, or its time running out. His pranks are put right.
func mend(id: String, toast := true) -> void:
	if not sore().has(id):
		return
	var s := sore().duplicate()
	s.erase(id)
	if s.is_empty():
		Game.flags.erase("sore")
	else:
		Game.flags["sore"] = s
	var t: Dictionary = (Game.flags.get("sore_talks", {}) as Dictionary).duplicate()
	t.erase(id)
	Game.flags["sore_talks"] = t
	for p in pranks().duplicate():
		if p is Dictionary and str(p.get("by", "")) == id:
			undo(p)
	var due: Variant = Game.flags.get("argue_due", null)
	if due is Dictionary and str((due as Dictionary).get("id", "")) == id:
		Game.flags.erase("argue_due")
	if toast and line("mended") != "":
		main.hud.show_toast(line("mended") % display(id))


# --- talking to him, gifts ------------------------------------------------------------------------

## Called when she talks to him: counts the day toward mending; returns a sharp line instead of his
## usual one now and then, or "".
func talk_line(v) -> String:
	var id := str(v.vid)
	if not is_sore(id):
		return ""
	var t: Dictionary = (Game.flags.get("sore_talks", {}) as Dictionary).duplicate()
	var days: Array = (t.get(id, []) as Array).duplicate()
	if not days.any(func(d): return int(d) == Game.day):
		days.append(Game.day)
	t[id] = days
	Game.flags["sore_talks"] = t
	var sharp := ""
	if on and _roll("sharp:%s" % id) < num("sharp_chance", 0.6):
		var lines: Array = (econ().get("sharp", {}) as Dictionary).get(id, [])
		if not lines.is_empty():
			var p := partner()
			sharp = str(lines[(Game.day + days.size()) % lines.size()]).replace("{partner}", title() if p != "" else "friends")
	if days.size() >= int(num("mend_talk_days", 2)):
		mend(id)
	return sharp


## A gift ends his soreness (after the gift's usual effects).
func on_gift(v) -> void:
	if is_sore(str(v.vid)):
		mend(str(v.vid))


## The argument scene to play when she talks to `v` today, or "": the sore man or her partner, on the
## day the morning rolled it, once a spell.
func argument_for(v) -> String:
	if not on or main.story.is_playing():
		return ""
	var due: Variant = Game.flags.get("argue_due", null)
	if not (due is Dictionary) or int((due as Dictionary).get("day", -1)) != Game.day:
		return ""
	var who := str((due as Dictionary).get("id", ""))
	var p := partner()
	if not is_sore(who) or p == "" or not (str(v.vid) == who or str(v.vid) == p):
		return ""
	var sid := "partner_argue_%s" % who
	if not Story.has_scene(sid):
		return ""
	return sid


## Plays it, with her partner stood beside the sore man (sent back to his own spot after).
func play_argument(v, sid: String) -> bool:
	var due: Dictionary = Game.flags.get("argue_due", {})
	var who := str(due.get("id", ""))
	var p := partner()
	var sorev = main._villager(who)
	var pv = main._villager(p)
	if sorev == null or pv == null or Game.flags.has("home_" + p) or Game.flags.has("home_" + who):
		return false
	var argued: Dictionary = (Game.flags.get("argued", {}) as Dictionary).duplicate()
	argued[who] = int(sore()[who])
	Game.flags["argued"] = argued
	Game.flags.erase("argue_due")
	var other = pv if v == sorev else sorev # the one she didn't click comes over
	var here = v
	var side: Vector3 = (main.player.position - here.position)
	side.y = 0.0
	side = side.normalized().rotated(Vector3.UP, PI * 0.5) if side.length() > 0.01 else Vector3.RIGHT
	other.position = here.position + side * 1.3
	other.settle_at(other.position)
	other.face_point(here.position, 30.0)
	here.face_point(other.position, 30.0)
	_argue_back = str(other.vid)
	main.story.scene_finished.connect(_after_argument, CONNECT_ONE_SHOT)
	return main.story.play(sid)


func _after_argument(_id: String) -> void:
	if _argue_back != "":
		main.set_home(_argue_back) # back to his own spot
	_argue_back = ""


# --- the day --------------------------------------------------------------------------------------

## A number in 0..1, the same for the same day and key (so a reload can't reroll it).
func _roll(key: String) -> float:
	if force_roll >= 0.0:
		return force_roll
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("partners:%d:%s" % [Game.day, key])
	return rng.randf()


static func _pranks_ok() -> bool:
	return Game.flag("act1_done") == true


func _free() -> bool:
	return not main.story.is_playing() and not main.sleeping and not (main.knit != null and main.knit.active)


func _process(delta: float) -> void:
	if main == null:
		return
	_herd()
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	update()


## Soreness running out, pranks ending, and (once a day, when she's free) the morning's roll.
func update() -> void:
	for id in sore().keys():
		if Game.day >= int(sore()[id]):
			mend(str(id))
	for p in pranks().duplicate():
		if p is Dictionary and int(p.get("until", -1)) >= 0 and Game.day >= int(p.get("until", -1)):
			undo(p)
	if not on or not _pranks_ok() or not _free():
		return
	if int(Game.flag("prank_roll", -1)) >= Game.day:
		return
	Game.flags["prank_roll"] = Game.day
	morning()


## The day's roll for each sore man: an argument due today, and maybe a prank.
func morning() -> void:
	var ids: Array = sore().keys()
	ids.sort()
	for id in ids:
		var who := str(id)
		if not is_sore(who):
			continue
		var argued: Dictionary = Game.flags.get("argued", {})
		if partner() != "" and int(argued.get(who, -1)) != int(sore()[who]) and _roll("argue:" + who) < num("argue_chance", 0.35):
			Game.flags["argue_due"] = {"day": Game.day, "id": who}
		var last := int(Game.flag("prank_last", -999))
		if Game.day - last >= int(num("prank_every", 3)) and (force_prank != "" or _roll("prank:" + who) < num("prank_chance", 0.4)):
			do_prank(who, force_prank)
			force_prank = ""


## The kinds he could pull now, in the data's order.
func available() -> Array:
	var out := []
	for k in econ().get("pranks", KINDS):
		var kind := str(k)
		if not prank(kind).is_empty():
			continue
		match kind:
			"pen":
				if _sheep_to_let_out() != null:
					out.append(kind)
			"pastry":
				if Game.count("pastry") > 0:
					out.append(kind)
			"itch":
				if _itch_target() != "":
					out.append(kind)
			"needles", "paint":
				out.append(kind)
	return out


## Pulls one prank (`kind`, or one picked by the day's roll), with a toast. Returns its kind or "".
func do_prank(who: String, kind := "") -> String:
	var can := available()
	if can.is_empty():
		return ""
	if kind == "" or not kind in can:
		kind = str(can[int(_roll("kind:" + who) * can.size()) % can.size()])
	var p := {"kind": kind, "by": who, "day": Game.day, "until": Game.day + 1}
	var text := ""
	match kind:
		"pen":
			var s = _sheep_to_let_out()
			var at := _outside_spot(s)
			p["sheep"] = main.sheep_list.find(s)
			p["at"] = [snappedf(at.x, 0.01), snappedf(at.z, 0.01)]
			_let_out(s, at, true)
			text = line("pen") % display(who)
		"needles":
			text = line("needles") % display(who)
		"itch":
			var vid := _itch_target()
			p["who"] = vid
			text = line("itch") % [display(who), display(vid)]
		"pastry":
			if not Game.take_item("pastry"):
				return ""
			p["until"] = -1
			text = line("pastry") % display(who)
		"paint":
			var before := {}
			var pp: Dictionary = (Game.flag("wall_paint", {}) as Dictionary).duplicate()
			var garish := str(econ().get("garish", "garish"))
			for f in _front_faces():
				before[f] = str(pp.get(f, ""))
				pp[f] = garish
			Game.set_flag("wall_paint", pp)
			p["before"] = before
			p["until"] = -1
			main._rebuild_house()
			text = line("paint") % display(who)
	var all := pranks().duplicate()
	all.append(p)
	Game.flags["pranks"] = all
	Game.flags["prank_last"] = Game.day
	if text != "":
		main.hud.show_toast(text)
	return kind


## Puts a prank right and drops it from the list.
func undo(p: Dictionary) -> void:
	var all := pranks().duplicate()
	var i := -1
	for j in all.size():
		if all[j] is Dictionary and str(all[j].get("kind", "")) == str(p.get("kind", "")):
			i = j
	if i >= 0:
		all.remove_at(i)
	if all.is_empty():
		Game.flags.erase("pranks")
	else:
		Game.flags["pranks"] = all
	var who := display(str(p.get("by", "")))
	match str(p.get("kind", "")):
		"pen":
			var s = _loose()
			if s != null:
				_bring_home(s, false)
		"pastry":
			Game.add_item("pastry")
			if line("undo_pastry") != "":
				main.hud.show_toast(line("undo_pastry") % who)
		"paint":
			var pp: Dictionary = (Game.flag("wall_paint", {}) as Dictionary).duplicate()
			var garish := str(econ().get("garish", "garish"))
			var before: Dictionary = p.get("before", {})
			for f in before:
				if str(pp.get(f, "")) == garish: # she may have painted over it herself
					if str(before[f]) == "":
						pp.erase(f)
					else:
						pp[f] = str(before[f])
			if pp.is_empty():
				Game.flags.erase("wall_paint")
			else:
				Game.set_flag("wall_paint", pp)
			main._rebuild_house()
			if line("undo_paint") != "":
				main.hud.show_toast(line("undo_paint") % who)


## The outside of the house's porch wall, the one with her front door (x = HOUSE_W, facing +x).
func _front_faces() -> Array:
	var out := []
	var w := int(main.HOUSE_W)
	for z in range(int(main._zmin()), int(main.HOUSE_FRONT), HouseBuilder.STEP):
		out.append(HouseBuilder.key(w, z, false) + ":p")
	return out


## Who he tells her sweaters itch: someone in town who isn't one of the men, looking for one today if
## anyone is.
func _itch_target() -> String:
	var others := []
	for v in Data.villagers():
		var id := str(v.get("id", ""))
		if id != "" and not id in candidates() and not id in NEVER and id != "rosa": # Rosa buys at her counter, not by asking
			others.append(id)
	others.sort()
	if others.is_empty():
		return ""
	for id in others:
		if SweaterSale.looking(id):
			return str(id)
	return str(others[int(_roll("itch") * others.size()) % others.size()])


## True if `vid` was told her sweaters itch, today (SweaterSale.looking reads the flag the same way).
static func itchy(vid: String) -> bool:
	return SweaterSale.itchy(vid)


# --- the sheep out of the pen ---------------------------------------------------------------------

func _sheep_to_let_out():
	if main.pen_rect.get_area() <= 0.0:
		return null
	for s in main.sheep_list:
		if is_instance_valid(s) and not s.housed and not s.heading_in and s.route.is_empty() \
				and main.pen_rect.has_point(Vector2(s.position.x, s.position.z)):
			return s
	return null


func _loose():
	var p := prank("pen")
	if p.is_empty():
		return null
	var i := int(p.get("sheep", -1))
	if i < 0 or i >= main.sheep_list.size() or not is_instance_valid(main.sheep_list[i]):
		return null
	return main.sheep_list[i]


## Is a sheep of hers out of the pen right now (the gate stands open while one is: homestead.gd)?
func loose_out() -> bool:
	return _loose() != null


## A walkable spot a few metres out from the pen, on the side nearest her house.
func _outside_spot(s) -> Vector3:
	var r: Rect2 = main.pen_rect
	var c := r.get_center()
	var reach := maxf(r.size.x, r.size.y) * 0.5 + 3.5
	var toward := (Vector2(main.HOUSE_W, 2.0) - c).normalized()
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8, PI]:
		var d := toward.rotated(turn)
		var p := c + d * reach
		var v := Vector3(p.x, 0, p.y)
		if not r.grow(1.0).has_point(p) and main._walkable(main._cell(v)):
			return v
	return Vector3(r.end.x + 3.0, 0, c.y) if s != null else Vector3.ZERO


func _let_out(s, at: Vector3, walk: bool) -> void:
	s.set_meta("loose", true) # homestead.gd leaves her be till she's herded back
	s.pen = Rect2(at.x - 1.0, at.z - 1.0, 2.0, 2.0)
	if walk:
		var path: Array = main._find_path(s.position, at)
		if path.size() >= 2:
			s.walk_route(path, false)
			return
	s.place(at, false)


func _bring_home(s, toast: bool) -> void:
	s.remove_meta("loose")
	s.flee = Vector3.ZERO
	var r: Rect2 = main.pen_rect
	s.pen = Rect2(r.position + Vector2(0.7, 0.7), r.size - Vector2(1.4, 1.4))
	if not s.route.is_empty() or not r.has_point(Vector2(s.position.x, s.position.z)): # still walking out, or out
		s.place(Vector3(r.get_center().x, 0, r.get_center().y), false)
	if toast and line("pen_home") != "":
		main.hud.show_toast(line("pen_home"))


## Herding her back: she shies from Nora (and the dog while the player plays him), and once she's
## back inside the pen the prank's over.
func _herd() -> void:
	var s = _loose()
	if s == null:
		return
	if s.housed or s.heading_in: # flock bedtime took her in with the others
		var p := prank("pen")
		var all := pranks().duplicate()
		all.erase(p)
		Game.flags["pranks"] = all
		s.remove_meta("loose")
		return
	if not s.route.is_empty():
		return
	var r: Rect2 = main.pen_rect
	if r.grow(-0.3).has_point(Vector2(s.position.x, s.position.z)):
		var p := prank("pen")
		var all := pranks().duplicate()
		all.erase(p)
		if all.is_empty():
			Game.flags.erase("pranks")
		else:
			Game.flags["pranks"] = all
		_bring_home(s, true)
		return
	var herders := [main.player]
	if main.dog != null and main.dog.controlled:
		herders.append(main.dog)
	var push := Vector3.ZERO
	for h in herders:
		if h == null or not is_instance_valid(h):
			continue
		var rad: float = h.scare_radius() if h.has_method("scare_radius") else 2.6
		var away: Vector3 = s.position - h.position
		away.y = 0.0
		var d := away.length()
		if d < rad and d > 0.01:
			push += away / d * (1.0 - d / rad + 0.35)
	if push == Vector3.ZERO:
		return
	var dir: Vector3 = push.normalized()
	if main.homestead != null:
		dir = main.homestead._free_dir(s.position, dir)
	if dir != Vector3.ZERO:
		s.flee = dir * 1.7 * clampf(push.length(), 0.5, 1.0)
		s.pen = Rect2(s.position.x - 0.7, s.position.z - 0.7, 1.4, 1.4)


# --- a save loaded ----------------------------------------------------------------------------------

## After a load: a sheep that was out is out again where she stood.
func apply() -> void:
	var p := prank("pen")
	if p.is_empty():
		return
	var s = _loose()
	if s == null:
		var all := pranks().duplicate()
		all.erase(p)
		Game.flags["pranks"] = all
		return
	var at: Array = p.get("at", [s.position.x, s.position.z])
	_let_out(s, Vector3(float(at[0]), 0, float(at[1])), false)
