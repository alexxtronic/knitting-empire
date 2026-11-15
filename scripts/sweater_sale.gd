## Selling a sweater to anyone in town, face to face (Alex, 2026-11-15: sweaters are the economy).
## On anyone's menu, "Ask if they're looking for a sweater" (once a day each): some days they say no.
## When they say yes this panel opens: she picks one of her sweaters and sets a price, and a meter
## shows how likely they are to say yes to it. They may turn an offer down and come back with one
## of their own; after a few refusals they walk away for the day. The numbers are in
## data/economy.json "haggle" (its "_about_haggle" says what each does); every line is a draft.
extends PanelContainer

const Data = preload("res://scripts/data.gd")
const Sweaters = preload("res://scripts/sweaters.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const GROUP := "Sell a sweater"
const NO := ["Not today, thanks. I'm all set.", "Oh, I've got one on the go already. Another time?", "I'll pass today, love. Money's tight this week.", "Not just now. Ask me again some other day."]
const YES := ["Actually, I could use one. What have you got?", "Ooh, go on then. Let's see them.", "You know, I might. Show me."]
const DEAR := ["Oh, that's far too dear for me.", "For that much? No, I don't think so.", "That's more than I'd ever spend on a sweater."]
const COUNTER := ["Hm. That's a bit steep. Would you take %dc?", "I like it, but not at that. %dc?", "Tell you what: %dc and it's mine."]
const SOLD := ["Done! I'm putting it on right now.", "Lovely. Worth every coin.", "You made this? It's beautiful. Here you go."]
const WALK := ["I think I'll leave it, thanks. Maybe another day.", "No, I've talked myself out of it. Sorry, love."]

var hud: Node # hud.gd, for its labels, buttons and sounds
var main: Node # main.gd: the sale itself (sell_sweater_to) and the villagers' lines
var v: Node = null # who she's selling to
var choice := -1 # the sweater on the table: its index in Game.sweaters
var price := 0
var counter := 0 # their counter-offer (0: none on the table)
var force_roll := -1.0 # tests: the roll an offer is judged by (0..1); below 0, a random one
var rng := RandomNumberGenerator.new()

var _who: Label
var _said: Label
var _picks: HBoxContainer
var _price_label: Label
var _fair_label: Label
var _meter_fill: ColorRect
var _meter_label: Label
var _offer: Button
var _take: Button


# --- the rules -----------------------------------------------------------------------------------

static func cfg(key: String, default: float) -> float:
	return float(Data.economy().get("haggle", {}).get(key, default))


## What she has said to `vid` today: {"day", "yes", "tries"} ({} if she hasn't asked today).
static func asked(vid: String) -> Dictionary:
	var a: Variant = (Game.flag("sweater_asked", {}) as Dictionary).get(vid, {})
	return a if a is Dictionary and int(a.get("day", -1)) == Game.day else {}


static func _note(vid: String, d: Dictionary) -> void:
	var all: Dictionary = (Game.flag("sweater_asked", {}) as Dictionary).duplicate()
	d["day"] = Game.day
	all[vid] = d
	Game.set_flag("sweater_asked", all)


static func bought_today(vid: String) -> bool:
	return int((Game.flag("npc_sweater_day", {}) as Dictionary).get(vid, -99)) == Game.day


## The chance they're looking for one today: better the more they like her, small if they bought
## one only lately.
static func yes_chance(vid: String) -> float:
	var last := int((Game.flag("npc_sweater_day", {}) as Dictionary).get(vid, -99))
	if Game.day - last < int(cfg("rebuy_days", 3)):
		return cfg("rebuy_yes", 0.15)
	var p := cfg("yes_base", 0.35) + cfg("yes_per_heart", 0.1) * Game.hearts(vid) + cfg("yes_per_trust", 0.003) * Game.stat(vid, "trust")
	return clampf(p, 0.05, 0.95)


## A number in 0..1 that stays the same for this villager all day (so asking again changes nothing).
static func _day_roll(vid: String, what: String) -> float:
	return float(absi(("%d:%s:%s" % [Game.day, vid, what]).hash()) % 10000) / 10000.0


## Whether they're looking for a sweater today.
static func looking(vid: String) -> bool:
	return _day_roll(vid, "ask") < yes_chance(vid)


## The plain fair price of a sweater: Rosa's price for its rarity.
func fair(rarity: int) -> int:
	return int(main._wear_price(rarity))


## The most they'd happily pay today for a sweater of `rarity`: at it the chance is even.
func reserve(vid: String, rarity: int) -> int:
	var m := lerpf(cfg("res_min", 0.95), cfg("res_max", 1.35), _day_roll(vid, "reserve")) + cfg("res_per_heart", 0.04) * Game.hearts(vid)
	return int(round(fair(rarity) * m))


## How likely they are to say yes to `p` coins for a sweater of `rarity` (what the meter shows).
func chance(vid: String, rarity: int, p: int) -> float:
	var spread := maxf(1.0, cfg("spread", 0.12) * fair(rarity))
	return 1.0 / (1.0 + exp((float(p) - float(reserve(vid, rarity))) / spread))


## The villager's menu rows: ask, haggle again, or why not today.
func rows_for(villager) -> Array:
	if Game.count("sweater") == 0:
		return []
	var vid: String = villager.vid
	var row: Dictionary
	var a := asked(vid)
	if bought_today(vid):
		row = {"id": "noop", "label": "Bought a sweater from you today", "enabled": false}
	elif a.is_empty():
		row = {"id": "sale_ask", "label": "Ask if they're looking for a sweater", "enabled": true}
	elif not bool(a.get("yes", false)):
		row = {"id": "noop", "label": "Not looking for a sweater today", "enabled": false}
	elif int(a.get("tries", 0)) >= int(cfg("tries", 3)):
		row = {"id": "noop", "label": "Done haggling for today", "enabled": false}
	else:
		row = {"id": "sale_haggle", "label": "Show them a sweater", "enabled": true}
	row["group"] = GROUP
	return [row]


## She asks; they say yes or no, and on a yes the panel opens.
func ask(villager) -> bool:
	var vid: String = villager.vid
	if asked(vid).is_empty():
		var yes := looking(vid)
		_note(vid, {"yes": yes, "tries": 0})
		if not yes:
			main._say(villager, str(NO[(Game.day + vid.length()) % NO.size()]))
			return false
	elif not bool(asked(vid).get("yes", false)):
		return false
	open(villager)
	return true


## The sweaters she can show: one of each design and rarity, best first. [index, rarity, design]
static func choices() -> Array:
	Game.sync_sweaters()
	var seen := {}
	var out := []
	for i in Game.sweaters.size():
		var key := "%s/%d" % [str(Game.sweater_designs[i]), int(Game.sweaters[i])]
		if not seen.has(key):
			seen[key] = true
			out.append([i, int(Game.sweaters[i]), str(Game.sweater_designs[i])])
	out.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
	return out


## She offers the sweater on the table at `price`. "sold", "counter" (they name theirs), "no", or
## "gone" (they walk away for the day).
func offer() -> String:
	if v == null or choice < 0 or choice >= Game.sweaters.size():
		return "no"
	var vid: String = v.vid
	var rarity := int(Game.sweaters[choice])
	var roll := force_roll if force_roll >= 0.0 else rng.randf()
	if roll < chance(vid, rarity, price):
		_sell(price)
		return "sold"
	var a := asked(vid)
	a["tries"] = int(a.get("tries", 0)) + 1
	_note(vid, a)
	var res := reserve(vid, rarity)
	if int(a["tries"]) >= int(cfg("tries", 3)):
		_say(WALK[int(a["tries"]) % WALK.size()])
		counter = 0
		_refresh()
		close()
		return "gone"
	if price <= int(res * cfg("counter_within", 1.3)):
		var step := maxi(1, int(cfg("step", 5)))
		counter = mini(price - step, int(floor(res * 0.97 / step)) * step)
		if counter > 0:
			_say(COUNTER[int(a["tries"]) % COUNTER.size()] % counter)
			_refresh()
			return "counter"
	counter = 0
	_say(DEAR[int(a["tries"]) % DEAR.size()])
	_refresh()
	return "no"


## She takes their counter-offer.
func take_counter() -> bool:
	if counter <= 0:
		return false
	_sell(counter)
	return true


func _sell(p: int) -> void:
	var who = v
	var i := choice
	counter = 0
	close()
	if main.sell_sweater_to(who, i, p):
		main._say(who, str(SOLD[(Game.day + i) % SOLD.size()]))


func _say(text: String) -> void:
	if _said:
		_said.text = "%s: \"%s\"" % [v.title if v else "", text]


# --- the panel -----------------------------------------------------------------------------------

func setup(h: Node, m: Node) -> void:
	hud = h
	main = m
	rng.randomize()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_who = hud._label("", 22, GOLD)
	vb.add_child(_who)
	_said = hud._label("", 15, TEXT)
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_said.custom_minimum_size = Vector2(460, 0)
	vb.add_child(_said)
	_picks = HBoxContainer.new()
	_picks.add_theme_constant_override("separation", 6)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(460, 70)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(_picks)
	vb.add_child(sc)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	for d in [-20, -5]:
		pr.add_child(_step_button(d))
	_price_label = hud._label("", 26, GOLD)
	_price_label.custom_minimum_size = Vector2(110, 0)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(_price_label)
	for d in [5, 20]:
		pr.add_child(_step_button(d))
	vb.add_child(pr)
	_fair_label = hud._label("", 13, Color(TEXT, 0.7))
	_fair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_fair_label)
	# the meter: how likely they are to say yes at this price
	var bar := ColorRect.new()
	bar.color = Color(0.12, 0.1, 0.09, 0.85)
	bar.custom_minimum_size = Vector2(460, 22)
	_meter_fill = ColorRect.new()
	_meter_fill.position = Vector2(2, 2)
	_meter_fill.size = Vector2(0, 18)
	bar.add_child(_meter_fill)
	vb.add_child(bar)
	_meter_label = hud._label("", 14, TEXT)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_meter_label)
	var bb := HBoxContainer.new()
	bb.add_theme_constant_override("separation", 8)
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	_offer = hud._button("Offer", func(): offer())
	_offer.custom_minimum_size = Vector2(150, 38)
	bb.add_child(_offer)
	_take = hud._button("Take theirs", func(): take_counter())
	_take.custom_minimum_size = Vector2(150, 38)
	bb.add_child(_take)
	var walk: Button = hud._button("Walk away", close)
	walk.custom_minimum_size = Vector2(120, 38)
	bb.add_child(walk)
	vb.add_child(bb)
	add_child(vb)
	visible = false


func _step_button(d: int) -> Button:
	var b: Button = hud._button(("+%d" % d) if d > 0 else str(d), func(): set_price(price + d))
	b.custom_minimum_size = Vector2(52, 38)
	return b


func open(villager) -> void:
	v = villager
	counter = 0
	var cs := choices()
	if cs.is_empty():
		return
	choice = int(cs[0][0])
	price = fair(int(cs[0][1]))
	_who.text = "Selling to %s" % v.title
	_say(str(YES[(Game.day + str(v.vid).length()) % YES.size()]))
	if hud.has_method("hide_dialogue"):
		hud.hide_dialogue()
	hud.click("ui_open")
	visible = true
	move_to_front()
	_refresh()


func close() -> void:
	visible = false


func pick(i: int) -> void:
	if i < 0 or i >= Game.sweaters.size():
		return
	choice = i
	counter = 0
	price = fair(int(Game.sweaters[i]))
	_refresh()


func set_price(p: int) -> void:
	if choice < 0 or choice >= Game.sweaters.size():
		return
	var f := fair(int(Game.sweaters[choice]))
	price = clampi(p, maxi(5, f / 4), f * 4)
	_refresh()


func _refresh() -> void:
	if v == null or _picks == null:
		return
	for c in _picks.get_children():
		_picks.remove_child(c)
		c.queue_free()
	for e in choices():
		var d := Sweaters.design(str(e[2]))
		var dname := str(d.get("name", "Sweater"))
		var b: Button = hud._button("%s\n%s" % [dname, RARITY[clampi(int(e[1]), 1, 5) - 1]], pick.bind(int(e[0])))
		b.custom_minimum_size = Vector2(118, 56)
		b.add_theme_font_size_override("font_size", 12)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if int(e[0]) == choice:
			b.modulate = Color(1.15, 1.05, 0.8)
		_picks.add_child(b)
	if choice < 0 or choice >= Game.sweaters.size():
		return
	var rarity := int(Game.sweaters[choice])
	var p := chance(v.vid, rarity, price)
	_price_label.text = "%dc" % price
	_fair_label.text = "Rosa would give you %dc for it today." % fair(rarity)
	_meter_fill.size.x = 456.0 * p
	_meter_fill.color = Color(0.85, 0.3, 0.25).lerp(Color(0.95, 0.75, 0.3), clampf(p * 2.0, 0.0, 1.0)).lerp(Color(0.45, 0.8, 0.4), clampf(p * 2.0 - 1.0, 0.0, 1.0))
	_meter_label.text = "%s  ·  %d%% likely to say yes" % [("Happy to pay that" if p >= 0.75 else ("Thinking about it" if p >= 0.4 else ("A stretch" if p >= 0.15 else "Far too dear"))), int(round(p * 100.0))]
	_offer.text = "Offer %dc" % price
	_take.visible = counter > 0
	_take.text = "Take %dc" % counter
