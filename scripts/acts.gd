extends Node
## The four acts across one life (Alex, 2026-11-24; docs/DIRECTION.md "Four acts across one life" and
## its "Decided", docs/REVIEW_2026-11-24.md 3.1 and 5.4): Nora at 25, 50, 75 and 100. `Game.act` is
## the act and `Game.age()` her age; `Game.unlocked(name)` is the gate later steps use (data/economy.json
## "acts" "unlocks").
##
## The skip is hers to start. Finishing the act's last goal ("Ready for the next chapter",
## scripts/empire_goals.gd) sets Game.flags["act_ready"]; from then her bed's menu has "Begin the next
## chapter…" and so does the Esc menu, never during a story scene, the knitting game, sleep, a wolf raid
## or anything else that holds her (`why_not()`). Either plays the act's scene in data/scenes/acts.scene,
## whose first choice is the confirm ("Not yet" changes nothing). Its `@act next` makes the skip
## (`advance()`): the act, the calendar (`skip_days`, a season, so weekdays and weekly sums stay where
## they were, with every day still to come moved on with it: `_shift()`), act_ready cleared, the next
## act's goals, her model for her age (data/characters.json "nora" "nora_ages"), and in Act 2 Gran's
## passing (`gran_passed`: her rent stops, homestead.gd, and her last letter comes in the post, mail.json
## "gran_last"). `@act card` shows the montage card: twenty-five years later, her age, the act's name,
## what she has, and a line for her partner when Game.flags["partner"] exists (step 3 builds it).
## Everything she owns carries over. Game.flags["acts_log"] keeps the day and play time of each skip.
##
## Every line players see here and in acts.scene is a DRAFT until Alex approves it.

const Data = preload("res://scripts/data.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")

const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const SOFT := Color(0.86, 0.80, 0.70)

var main: Node # main.gd
var card: Control # the montage card (full screen; its panel in the middle)
var card_open := false
var hold_card := false # the check holds the card for its picture, then closes it as a click would
var card_button: Button
var _card_rows: VBoxContainer
var used_model := "" # the model path the act last asked for (the check reads it)


func _ready() -> void:
	name = "Acts"


static func econ() -> Dictionary:
	return Data.economy().get("acts", {})


## The act's title on the card ("The Long Row"), a draft.
static func act_name(n: int) -> String:
	return str((econ().get("names", {}) as Dictionary).get(str(n), ""))


## How far the calendar jumps at a skip, in days (28: a season).
static func skip_days() -> int:
	return int(econ().get("skip_days", 28))


# --- may she begin it? ----------------------------------------------------------------------------

## "" if she can begin the next chapter now, "none" if there's none to begin (the act isn't done, or
## it's Act 4), else why not, for the row and the toast.
func why_not() -> String:
	if Game.act >= Game.LAST_ACT or int(Game.flag("act_ready", 0)) <= 0:
		return "none"
	if main.story.is_playing():
		return "not in the middle of a scene"
	if main.sleeping:
		return "not while she's asleep"
	if main.knit != null and main.knit.active:
		return "not while she's knitting"
	if main.wolves != null and main.wolves.active():
		return "not while the wolves are at the pen"
	if main.fps != null and main.fps.active: # first person, the computer, the counter, the wardrobe
		return "not from first person"
	if main.fp_blocked(): # the title, the cinematic camera, the world editor, building, the dog
		return "not right now"
	return ""


## True while there's a chapter to begin (the rows show, greyed if she can't right now).
func offered() -> bool:
	return why_not() != "none"


## The row on her bed's menu.
func bed_rows() -> Array:
	var why := why_not()
	if why == "none":
		return []
	if why != "":
		return [{"id": "next_chapter", "label": "Begin the next chapter…  (%s)" % why, "enabled": false}]
	return [{"id": "next_chapter", "label": "Begin the next chapter…", "enabled": true}]


## Plays the act's skip scene (its first choice is the confirm). False, with a toast, if she can't now.
func begin() -> bool:
	var why := why_not()
	if why != "":
		if why != "none":
			main.hud.show_toast("You can begin the next chapter later: %s." % why)
		return false
	main.hud.game_menu.visible = false
	return main.story.play("act%d_begin" % (Game.act + 1))


## A scene's @act command (story_player.gd): "next" makes the skip, "card" shows what she has.
func cmd(what: String) -> void:
	match what:
		"next":
			advance()
		"card":
			await show_card()


# --- the skip -------------------------------------------------------------------------------------

## Twenty-five years later: the next act, the calendar, Gran, her goals and her model. Everything she
## owns stays as it is.
func advance() -> void:
	if Game.act >= Game.LAST_ACT:
		return
	var from := Game.act
	var n := skip_days()
	Game.act = from + 1
	Game.day += n
	_shift(n)
	Game.hour = 8.0 # a new chapter begins in the morning, before the post
	Game.flags.erase("stayed_up")
	Game.flags.erase("act_ready")
	var history: Dictionary = (Game.flags.get("acts_log", {}) as Dictionary).duplicate()
	history[str(Game.act)] = {"day": Game.day, "secs": int(float(Game.flags.get("play_secs", 0.0)))}
	Game.flags["acts_log"] = history
	if from == 1: # Gran (review 5.4): she has passed in Florida, and the farm is Nora's now
		Game.flags["gran_passed"] = true
		Game.flags["gran_passed_day"] = Game.day
		for k in ["rent_on", "rent_owed", "rent_due"]:
			Game.flags.erase(k)
		if main.homestead and main.homestead.ui:
			main.homestead.ui.refresh()
	if main.goals:
		main.goals.sync_act()
		main.goals.check_now() # the new act's counted goals count from now
	apply_model()


## Moves every day and hour still to come on by the jump, so nothing falls due because of it: the
## barn's rent, Rowan's watch, the next request, the next mail order, the online store's orders and
## its next one, and the night the wolves last rolled (or the morning would roll the missed nights).
## Days already past (when a coat was combed, a tree felled) stay, so all of that has grown back.
func _shift(n: int) -> void:
	for k in ["barn_rent_due", "shepherd_until", "request_day"]:
		if Game.flags.has(k):
			Game.flags[k] = int(Game.flags[k]) + n
	var m: Variant = Game.flags.get("mail", null)
	if m is Dictionary and (m as Dictionary).has("next_order"):
		m["next_order"] = int(m["next_order"]) + n
	var s: Variant = Game.flags.get("store", null)
	if s is Dictionary:
		if (s as Dictionary).has("next_at"):
			s["next_at"] = float(s["next_at"]) + n * 24.0
		for o in (s as Dictionary).get("orders", []):
			if o is Dictionary and (o as Dictionary).has("placed"):
				o["placed"] = float(o["placed"]) + n * 24.0
	var w: Variant = Game.flags.get("wolves", null)
	if w is Dictionary and int((w as Dictionary).get("night", -1)) >= 0:
		w["night"] = int(w["night"]) + n


# --- her model by age -----------------------------------------------------------------------------

## Her model in act `n` (data/characters.json "nora" "nora_ages"; "" if it has none).
static func model_for(n: int) -> String:
	var ages: Dictionary = Data.character(Data.player_character()).get("nora_ages", {})
	return str(ages.get(str(n), ""))


## Puts her in the act's model (at load and on the skip). False if there's none or it won't load.
func apply_model() -> bool:
	var path := model_for(Game.act)
	used_model = path
	if path == "" or main.player == null:
		return false
	return main.player.set_model(path)


# --- the montage card -----------------------------------------------------------------------------

## A line for her partner: "" until Game.flags["partner"] exists (step 3). It may be a villager id, or
## {"id", "name", "title"}.
static func partner_line() -> String:
	var p: Variant = Game.flags.get("partner", null)
	if p == null:
		return ""
	var id := ""
	var who := ""
	var title := ""
	if p is Dictionary:
		id = str((p as Dictionary).get("id", ""))
		who = str((p as Dictionary).get("name", ""))
		title = str((p as Dictionary).get("title", ""))
	else:
		id = str(p)
	if who == "" and id != "":
		for v in Data.villagers():
			if str(v.get("id", "")) == id:
				who = str(v.get("name", id))
		if who == "":
			who = id.capitalize()
	if who == "":
		return ""
	return "%s, your %s, is still by your side." % [who, title] if title != "" else "%s is still by your side." % who


## What she has, for the card: [label, value] rows.
func holdings() -> Array:
	var wild: int = main.wildlife.penned_list().size() if main.wildlife else 0
	var pens: int = main.wildlife.pens().size() if main.wildlife else 0
	var species: int = (main.wildlife.data.get("animals", {}) as Dictionary).size() if main.wildlife else 0
	var animals := "%d  (%d sheep, %d wild)" % [Game.sheep_count + wild, Game.sheep_count, wild]
	return [["Coins", "%dc" % Game.coins], ["Animals", animals], ["Pens", str(pens)],
		["Sweaters knitted", str(Game.knit_xp)], ["Field Guide", "%d of %d found" % [EmpireGoals.guide_count("seen"), species]]]


## The card's lines as they read now (the check reads them too).
func card_lines() -> Array:
	var out := ["Twenty-five years later", "Act %d: %s" % [Game.act, act_name(Game.act)], "Nora is %d." % Game.age()]
	for r in holdings():
		out.append("%s   %s" % [r[0], r[1]])
	var pl := partner_line()
	if pl != "":
		out.append(pl)
	if Game.act == 2 and Game.flag("gran_passed") == true:
		out.append("Gran passed peacefully in Florida. The farm is yours now.")
	return out


func _build_card() -> void:
	var hud: Node = main.hud
	card = Control.new()
	card.name = "ActCard"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP # a click anywhere closes it, as on a story line
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close_card())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", hud._sb(Color(0.16, 0.12, 0.09, 0.95), 14, GOLD, 28.0))
	panel.custom_minimum_size = Vector2(520, 0)
	_card_rows = VBoxContainer.new()
	_card_rows.add_theme_constant_override("separation", 6)
	panel.add_child(_card_rows)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(panel)
	card.add_child(centre)
	card.visible = false
	hud.root.add_child(card)


## Shows the card over the faded screen until she clicks it, or presses Enter, Space or Esc (in the
## story's auto mode, a moment, unless the check holds it).
func show_card() -> void:
	if card == null:
		_build_card()
	for c in _card_rows.get_children():
		c.queue_free()
	var hud: Node = main.hud
	var lines := card_lines()
	for i in lines.size():
		var fsize := 30 if i == 0 else (20 if i == 1 else 16)
		var col := GOLD if i == 0 else (TEXT if i <= 2 else SOFT)
		var l: Label = hud._label(str(lines[i]), fsize, col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(460, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_rows.add_child(l)
		if i == 2: # a little room between who she is and what she has
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			_card_rows.add_child(gap)
	card_button = hud._button("Continue", close_card)
	card_button.custom_minimum_size = Vector2(160, 36)
	card_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	_card_rows.add_child(gap2)
	_card_rows.add_child(card_button)
	card.visible = true
	card.move_to_front() # over the story's fade and its title
	card_open = true
	var t := 0.0
	while card_open:
		await get_tree().process_frame
		t += get_process_delta_time()
		if main.story.auto and not hold_card and t > (2.0 if main.story.cinematic else 0.3):
			close_card()
	card.visible = false


func close_card() -> void:
	card_open = false


func _input(e: InputEvent) -> void:
	if not card_open:
		return
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo \
			and (e as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		close_card()
		get_viewport().set_input_as_handled()
