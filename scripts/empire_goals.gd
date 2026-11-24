extends Node
## Act 1's sense of progress (Alex approved 2026-11-18; docs/REVIEW_2026-11-24.md sections 2 and 7):
## the Empire goal list, the takings ledger and its morning card, and the Field Guide's state.
##
## Goals (data/goals.json): once Act 1's guided part is done (`act1_done`) the first three goals not
## yet done show top left, under the needs; any of them can be done, and each pays its reward. Counted
## checks (caught, penned...) count from the moment the goal first shows ("base"), so what she did in
## Act 1 doesn't tick them off. The last goal, "Ready for the next chapter", sets
## Game.flags["act_ready"] = 1 for the time skip, which another step builds. The state is
## Game.flags["empire_goals"]: {"done": {id: {"day", "secs"}}, "base": {id: n}}, so a play-test shows
## the pacing (the game day and Game.flags["play_secs"] at each goal).
##
## The ledger: every place a sweater is paid for calls `took(channel, coins)` (face to face, Rosa, the
## mailbox's shipping, mail orders, the online store, requests). Game.flags["ledger"] keeps today,
## yesterday and the day before, rolled over lazily by the day it was last touched (a bonfire's night,
## sleep, or a check moving Game.day), and the best day's total. On a new day a card shows yesterday's
## takings by channel and the change against the day before.
##
## The Field Guide (scripts/field_guide.gd): Game.flags["guide"] = {species: {"seen": day, "caught": n,
## "combed": n}}. Seen means it came within SEEN_RANGE of Nora or of the dog while the player plays him.
##
## Every line players see here is a DRAFT until Alex approves it.

const Data = preload("res://scripts/data.gd")
const FieldGuide = preload("res://scripts/field_guide.gd")
const Lookbook = preload("res://scripts/lookbook.gd")

const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const SHOWN := 3 # goals on screen at once
const SEEN_RANGE := 15.0
const CARD_SECS := 14.0
const CHANNELS := ["face", "rosa", "mailbox", "mail", "store", "request"]
const CHANNEL_NAMES := {"face": "Face to face", "rosa": "Rosa", "mailbox": "The mailbox", "mail": "Mail orders",
	"store": "Online store", "request": "Requests"} # drafts
## Stats the goals count, kept in Game.flags["empire_stats"].
const STATS := ["caught", "combed", "fibre_knits", "face_sales"]

## Off in the autotest but for its own check (like Wolves.on): no goals paid, no list, no morning card,
## so the other checks' coins and pictures are as they were. The ledger and the guide still count.
static var on := true

var main: Node # main.gd
## The goals of the act she's in (data/goals.json, each goal's "act", 1 when it has none; scripts/acts.gd).
var defs: Array = []
var all_defs: Array = [] # every act's
var _act := 0 # the act `defs` was taken for
var guide: FieldGuide
var lookbook: Lookbook
var _t := 0.0
var _panel: PanelContainer
var _rows: VBoxContainer
var _shown := "" # the ids on the panel, to rebuild it only when they change
var _card: PanelContainer
var _card_text: Label
var _card_t := 0.0


func _ready() -> void:
	name = "EmpireGoals"
	all_defs = Data.load_json("goals").get("goals", [])
	sync_act()
	Game.day_started.connect(_on_day_started)


## Builds the goal list, the morning card and the two panels into the HUD (main.gd, once it has one).
func setup() -> void:
	var hud: Node = main.hud
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", hud._sb(Color(0.16, 0.12, 0.09, 0.86), 10, GOLD, 10.0))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_rows)
	_panel.visible = false
	hud.root.add_child(_panel)
	hud._place(_panel, 0.0, 0.0, Vector2(16, 300))
	hud.chrome.append(_panel)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", hud._sb(Color(0.16, 0.12, 0.09, 0.92), 10, GOLD, 14.0))
	_card_text = hud._label("", 15)
	_card.add_child(_card_text)
	_card.visible = false
	hud.root.add_child(_card)
	hud._place(_card, 0.5, 0.0, Vector2(0, 150)) # under the goal line and the toasts
	hud.chrome.append(_card)
	guide = FieldGuide.new()
	guide.setup(hud, self)
	hud.root.add_child(guide)
	hud._place(guide, 0.5, 0.5, Vector2.ZERO)
	hud.guide = guide
	lookbook = Lookbook.new()
	lookbook.setup(hud)
	hud.root.add_child(lookbook)
	hud._place(lookbook, 0.5, 0.5, Vector2.ZERO)
	hud.lookbook = lookbook


# --- the ledger ----------------------------------------------------------------------------------

## Game.flags["ledger"], rolled over to today: {"day", "today", "yesterday", "before", "best", "total"},
## each of today, yesterday, before and total {channel: coins}.
static func ledger() -> Dictionary:
	var l: Variant = Game.flags.get("ledger", null)
	if not l is Dictionary or not (l as Dictionary).has("day"):
		l = {"day": Game.day, "today": {}, "yesterday": {}, "before": {}, "best": 0, "total": {}}
		Game.flags["ledger"] = l
	var d: Dictionary = l
	var gap: int = Game.day - int(d.get("day", Game.day))
	if gap != 0:
		var today: Dictionary = d.get("today", {})
		var yesterday: Dictionary = d.get("yesterday", {})
		if gap == 1:
			d["before"] = yesterday
			d["yesterday"] = today
		elif gap == 2:
			d["before"] = today
			d["yesterday"] = {}
		else: # a longer gap, or a save from a later day: nothing to compare
			d["before"] = {}
			d["yesterday"] = {}
		d["today"] = {}
		d["day"] = Game.day
	return d


## Coins a sweater brought in, by channel (one of CHANNELS).
static func took(channel: String, coins: int) -> void:
	if coins <= 0:
		return
	var d := ledger()
	for part in ["today", "total"]:
		var m: Dictionary = d.get(part, {})
		m[channel] = int(m.get(channel, 0)) + coins
		d[part] = m
	d["best"] = maxi(int(d.get("best", 0)), sum(d["today"]))
	if channel == "face":
		note("face_sales")


static func sum(m: Dictionary) -> int:
	var n := 0
	for k in m:
		n += int(m[k])
	return n


## The morning card's text ("" if there's nothing to say): yesterday's takings by channel, its total
## and the change against the day before.
static func ledger_text() -> String:
	var d := ledger()
	var y: Dictionary = d.get("yesterday", {})
	var b: Dictionary = d.get("before", {})
	var ty := sum(y)
	var tb := sum(b)
	if ty <= 0 and tb <= 0:
		return ""
	var lines := ["Yesterday's takings (day %d)" % (Game.day - 1)]
	for ch in CHANNELS:
		if int(y.get(ch, 0)) > 0:
			lines.append("   %s   %dc" % [CHANNEL_NAMES[ch], int(y[ch])])
	if ty <= 0:
		lines.append("   No sweaters sold")
	var diff := ty - tb
	lines.append("Total %dc   (%s%dc on the day before)" % [ty, "+" if diff >= 0 else "-", absi(diff)])
	return "\n".join(lines)


func _on_day_started(_day: int) -> void:
	ledger() # roll over first, whatever else the morning pays
	if not on or main == null:
		return
	await get_tree().create_timer(1.2).timeout # after the sleep fade
	show_ledger()


## Shows the morning card for CARD_SECS (false if there was nothing to show).
func show_ledger() -> bool:
	var t := ledger_text()
	if t == "" or _card == null:
		return false
	_card_text.text = t
	_card.visible = true
	_card.modulate.a = 1.0
	_card.move_to_front()
	_card_t = CARD_SECS
	return true


# --- stats and the guide -------------------------------------------------------------------------

static func stat(what: String) -> int:
	return int((Game.flags.get("empire_stats", {}) as Dictionary).get(what, 0))


static func note(what: String, n := 1) -> void:
	var s: Dictionary = (Game.flags.get("empire_stats", {}) as Dictionary).duplicate()
	s[what] = int(s.get(what, 0)) + n
	Game.flags["empire_stats"] = s


static func guide_entry(species: String) -> Dictionary:
	return ((Game.flags.get("guide", {}) as Dictionary).get(species, {}) as Dictionary)


## Marks a species seen, caught or combed (caught and combed count; both also mean seen).
static func mark(species: String, what: String) -> void:
	var g: Dictionary = (Game.flags.get("guide", {}) as Dictionary).duplicate()
	var e: Dictionary = (g.get(species, {}) as Dictionary).duplicate()
	if not e.has("seen"):
		e["seen"] = Game.day
	if what != "seen":
		e[what] = int(e.get(what, 0)) + 1
	g[species] = e
	Game.flags["guide"] = g
	if what in STATS:
		note(what)


static func guide_count(what: String) -> int:
	var n := 0
	var g: Dictionary = Game.flags.get("guide", {})
	for k in g:
		if (g[k] as Dictionary).has(what) and (what == "seen" or int(g[k][what]) > 0):
			n += 1
	return n


## Every wild animal within SEEN_RANGE of her, or of the dog while the player plays him, is seen.
func _mark_seen() -> void:
	var wl = main.wildlife
	if wl == null or not wl.built:
		return
	var eyes: Array = [main.player.global_position]
	if main.dog and main.dog.visible and main.dog.controlled:
		eyes.append(main.dog.global_position)
	var g: Dictionary = Game.flags.get("guide", {})
	for a in wl.animals:
		if not is_instance_valid(a) or not (a as Node3D).visible or (g.has(a.species) and (g[a.species] as Dictionary).has("seen")):
			continue
		for e in eyes:
			if Vector2(a.global_position.x - e.x, a.global_position.z - e.z).length() < SEEN_RANGE:
				mark(a.species, "seen")
				main.hud.show_toast("New in your Field Guide: the %s." % str(a.info.get("name", a.species)).to_lower())
				break


# --- the goals -----------------------------------------------------------------------------------

## Takes the current act's goals into `defs` when the act has changed (the skip, a load).
func sync_act() -> void:
	if _act == Game.act:
		return
	_act = Game.act
	defs = all_defs.filter(func(g): return int(g.get("act", 1)) == Game.act)
	_shown = ""


func state() -> Dictionary:
	var s: Variant = Game.flags.get("empire_goals", null)
	if not s is Dictionary:
		s = {"done": {}, "base": {}}
		Game.flags["empire_goals"] = s
	var d: Dictionary = s
	if not d.get("done") is Dictionary:
		d["done"] = {}
	if not d.get("base") is Dictionary:
		d["base"] = {}
	return d


func is_done(id: String) -> bool:
	return (state()["done"] as Dictionary).has(id)


## True once the list runs: Act 1's guided part is done (and the autotest has it on).
func live() -> bool:
	return on and Game.flag("act1_done") == true


## The goals on screen: the first SHOWN not yet done; the last ("ready") only once it's all that's left.
func window() -> Array:
	sync_act()
	var out := []
	var left := defs.filter(func(g): return not is_done(str(g["id"])))
	for g in left:
		if str(g.get("check", "")) == "ready" and left.size() > 1:
			continue
		out.append(g)
		if out.size() >= SHOWN:
			break
	return out


## The number the goal's check reads now.
func metric(g: Dictionary) -> int:
	match str(g.get("check", "")):
		"caught", "combed", "fibre_knits", "face_sales":
			return stat(str(g["check"]))
		"penned":
			return int(Game.flag("pen_n", 0))
		"requests":
			return int(main.empire.requests_done()) if main and main.empire else 0
		"needles":
			var want := 0
			var defs_n: Array = main.empire.needle_defs()
			for i in defs_n.size():
				if str(defs_n[i].get("id", "")) == str(g.get("needles", "")):
					want = i
			return 1 if int(main.empire.needle_rank()) >= want else 0
		"pens":
			return main.wildlife.pens().size() if main and main.wildlife else 0
		"barn":
			return 1 if main and main.wildlife and main.wildlife.stalls_rented() else 0
		"guide_seen":
			return guide_count("seen")
		"designs":
			return Game.wardrobe.size()
		"best_day":
			return maxi(int(ledger().get("best", 0)), sum(ledger()["today"]))
		"ready":
			return 1
	return 0


## Counted checks count from when the goal first showed.
func _counted(g: Dictionary) -> bool:
	return str(g.get("check", "")) in ["caught", "penned", "combed", "fibre_knits", "face_sales", "requests"]


func met(g: Dictionary) -> bool:
	var base: int = int((state()["base"] as Dictionary).get(str(g["id"]), 0)) if _counted(g) else 0
	return metric(g) - base >= int(g.get("n", 1))


## The goal's line with its progress and reward, as the list shows it.
func label(g: Dictionary) -> String:
	var n := int(g.get("n", 1))
	var prog := ""
	if n > 1 and str(g["check"]) != "best_day":
		var base: int = int((state()["base"] as Dictionary).get(str(g["id"]), 0)) if _counted(g) else 0
		prog = "  %d/%d" % [mini(n, metric(g) - base), n]
	elif str(g["check"]) == "best_day":
		prog = "  (best %dc)" % metric(g)
	var r := int(g.get("reward", 0))
	return "%s%s%s" % [str(g["line"]), prog, "  +%dc" % r if r > 0 else ""]


func complete(g: Dictionary) -> void:
	var id := str(g["id"])
	var done: Dictionary = state()["done"]
	done[id] = {"day": Game.day, "secs": int(float(Game.flags.get("play_secs", 0.0)))}
	var r := int(g.get("reward", 0))
	if r > 0:
		Game.coins += r # a reward, not takings: the ledger leaves it out
	if str(g.get("check", "")) == "ready":
		Game.flags["act_ready"] = 1
		main.hud.show_toast("Ready for the next chapter. Begin it from your bed, or the menu (Esc), whenever you like.")
	else:
		main.hud.show_toast("Goal done: %s%s" % [str(g["line"]), "  (+%dc)" % r if r > 0 else ""])
	if main.audio:
		main.audio.play("coins", -6.0)


## Sets a base for any goal newly on screen, pays any that are met, and redraws the list.
func check_now() -> void:
	if not live():
		return
	var base: Dictionary = state()["base"]
	for _pass in defs.size(): # one met goal can bring on another that is met already
		var any := false
		for g in window():
			var id := str(g["id"])
			if _counted(g) and not base.has(id):
				base[id] = metric(g)
			if met(g):
				complete(g)
				any = true
		if not any:
			break
	_refresh()


func _refresh() -> void:
	if _panel == null:
		return
	var w := window()
	var key := ",".join(w.map(func(g): return label(g)))
	if key == _shown:
		return
	_shown = key
	for c in _rows.get_children():
		c.queue_free()
	var title: Label = main.hud._label("Empire goals", 13, GOLD)
	_rows.add_child(title)
	for g in w:
		var done := is_done(str(g["id"]))
		var l: Label = main.hud._label(("- " if not done else "Done: ") + label(g), 14, TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
		_rows.add_child(l)
	if w.is_empty(): # every goal is done, "ready" included: the skip is hers to start (scripts/acts.gd)
		_rows.add_child(main.hud._label("Ready for the next chapter", 14, GOLD))
		var how: Label = main.hud._label("Begin it from your bed, or the menu (Esc)", 13, TEXT)
		_rows.add_child(how)


func _process(delta: float) -> void:
	if main == null or main.hud == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_mark_seen()
		check_now()
	if _card_t > 0.0:
		_card_t -= delta
		if _card_t <= 0.0:
			_card.visible = false
	if _panel:
		sync_act()
		var show: bool = live() and not defs.is_empty() and int(main.mode) == 0 and not main.hud.title_visible() # Act 4 has none
		_panel.visible = show
		if show and main.hud.needs_panel: # just under the needs, wherever they end
			var y: float = main.hud.needs_panel.get_global_rect().end.y + 10.0
			_panel.offset_top = y
			_panel.offset_bottom = y
