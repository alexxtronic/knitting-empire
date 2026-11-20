extends Node
## Rowan the shepherd (Alex, 2026-11-20: "give Rowan Shepard (new name Shepherd Rowan) the task of
## helping introduce and manage animals in the pen"). Three things live here:
##
## - His watch over the pen. Once Act 1 is done his menu has "Hire Rowan to watch your pen": `fee_share`
##   of Lars's barn rent (data/economy.json "shepherd", "story" barn_rent) paid in advance for `days`
##   days (Game.flags["shepherd_until"], the first day he's no longer paid for). Alex: "50% cheaper than
##   barn ... but he's 50% less effective than barns, aka he'll only protect the animals from 50% of
##   attacks". So while he's paid up, a night the wolves come (wolves.roll(), after the barn's stalls
##   have taken their animals off the list) is stopped with a chance of `cover`, rolled from the night
##   itself (stops(night)), so a reload can't reroll it. The barn's stalls still stop every raid on the
##   animals they hold; he covers the rest, half the time.
## - The flags his advice talks wait for (rowan.scene, rowan_tip_*): update() sets them as the farm
##   gets there (a full pen, a wild animal penned, a wolf raid seen).
## - Act 1's tutorial is his too, but it's story: data/scenes/act1.scene (act1_strays to
##   act1_rowan_done), driven by the "sheared" and "sweater_sold" events from main.gd.
##
## Every line and number is a draft until Alex approves it.

const Data = preload("res://scripts/data.gd")

var main: Node # main.gd
var force_roll := -1.0 # tests: the roll a night's cover is judged by (0..1); below 0, the night's own
var _t := 0.0


func _ready() -> void:
	name = "Shepherd"


static func cfg(key: String, fallback: float) -> float:
	return float(Data.economy().get("shepherd", {}).get(key, fallback))


## What a stretch of his watch costs: a share of Lars's barn rent.
static func fee() -> int:
	var rent := float(Data.economy().get("story", {}).get("barn_rent", 120))
	return maxi(1, int(round(rent * cfg("fee_share", 0.5))))


static func days() -> int:
	return maxi(1, int(cfg("days", 28)))


## True while he's paid to watch her pen.
static func paid_up() -> bool:
	return Game.day < int(Game.flag("shepherd_until", 0))


static func _story_ok() -> bool:
	return Game.flag("act1_done") == true or Game.flag("story_farm") != true


## A roll in 0..1 that's the same for the same night every time.
func night_roll(night: int) -> float:
	if force_roll >= 0.0:
		return force_roll
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rowan_watch:%d" % night)
	return rng.randf()


## Does Rowan stop tonight's raid? Only while he's paid up, and only `cover` of the time.
func stops(night: int) -> bool:
	return paid_up() and night_roll(night) < cfg("cover", 0.5)


# --- his menu ------------------------------------------------------------------------------------

func rows_for(v) -> Array:
	if v == null or str(v.vid) != "rowan" or not _story_ok():
		return []
	var row: Dictionary
	if paid_up():
		row = {"id": "noop", "label": "Rowan's watching your pen until day %d" % int(Game.flag("shepherd_until", 0)), "enabled": false}
	else:
		var f := fee()
		row = {"id": "shep_hire", "label": "Hire Rowan to watch your pen: %d days  (%dc)" % [days(), f], "enabled": Game.coins >= f}
	row["group"] = "Watching the pen"
	return [row]


func action(v, id: String) -> void:
	if id == "shep_hire":
		hire(v)


func hire(v = null) -> bool:
	if paid_up() or not Game.spend(fee()):
		return false
	Game.set_flag("shepherd_until", Game.day + days())
	Game.add_friendship("rowan", 4)
	if v != null and main:
		main._say(v, "Deal. I'll walk your fence at night with the dogs. I can't promise I'll hear every wolf, mind. The barn's walls don't sleep. I do.")
	if main:
		main.hud.show_toast("Rowan's watching your pen until day %d. He stops about half the wolf raids; Lars's barn stops them all." % int(Game.flag("shepherd_until", 0)))
	return true


# --- the flags his advice waits for ------------------------------------------------------------------

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or main == null:
		return
	_t = 2.0
	update()


func update() -> void:
	if Game.flag("act1_done") != true:
		return
	var wl = main.wildlife
	if wl == null:
		return
	if Game.flag("rowan_tip_pen_due") != true and wl.pens().size() > 0 and wl.pen_room() <= 0:
		Game.set_flag("rowan_tip_pen_due")
	if Game.flag("rowan_tip_wild_due") != true and not wl.penned_list().is_empty():
		Game.set_flag("rowan_tip_wild_due")
	var w = main.wolves
	if w and Game.flag("rowan_tip_wolves_due") != true and int(w.state().get("raids", 0)) > 0:
		Game.set_flag("rowan_tip_wolves_due")
