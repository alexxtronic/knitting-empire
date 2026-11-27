## Selling a sweater to anyone in town, face to face (Alex, 2026-11-15: sweaters are the economy).
## On anyone's menu, "Ask if they're looking for a sweater" (once a day each): some days they say no.
## When they say yes this panel opens: she picks one of her sweaters and sets a price, and a meter
## shows how likely they are to say yes to it. They may turn an offer down and come back with one
## of their own; after a few refusals they walk away for the day. The numbers are in
## data/economy.json "haggle" (its "_about_haggle" says what each does); every line is a draft.
extends PanelContainer

const Data = preload("res://scripts/data.gd")
const Sweaters = preload("res://scripts/sweaters.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const GROUP := "Sell a sweater"
const NO := ["Not today, thanks. I'm all set.", "Oh, I've got one on the go already. Another time?", "I'll pass today, love. Money's tight this week.", "Not just now. Ask me again some other day."]
const YES := ["Actually, I could use one. What have you got?", "Ooh, go on then. Let's see them.", "You know, I might. Show me."]
const DEAR := ["Oh, that's far too dear for me.", "For that much? No, I don't think so.", "That's more than I'd ever spend on a sweater."]
const COUNTER := ["Hm. That's a bit steep. Would you take %dc?", "I like it, but not at that. %dc?", "Tell you what: %dc and it's mine."]
const SOLD := ["Done! I'm putting it on right now.", "Lovely. Worth every coin.", "You made this? It's beautiful. Here you go."]
## Act 1's first sale (Alex, 2026-11-16): Wren names her range, as a share of Rosa's price, takes
## any price inside it and counters above it at her top. She never walks away, so it can't stick.
const GUIDED_LOW := 0.9
const GUIDED_HIGH := 1.25
## Not looking for one today, but they'll look at what she has (and pay less): Alex, 2026-11-27.
const CASUAL := ["I wasn't looking for one, but go on, show me. I won't pay top coin, mind.", "Not on my list today. Let's see them anyway: if the price is right...", "I've no need of one, but I've a weakness for a bargain. What have you got?"]
const LATELY := ["I've only just bought one from you, love. Give it a few days.", "The one you sold me is still new! Ask me again next week."]
const WALK := ["I think I'll leave it, thanks. Maybe another day.", "No, I've talked myself out of it. Sorry, love."]

var hud: Node # hud.gd, for its labels, buttons and sounds
var main: Node # main.gd: the sale itself (sell_sweater_to) and the villagers' lines
var v: Node = null # who she's selling to
var choice := -1 # the sweater on the table: its index in Game.sweaters
var price := 0
var counter := 0 # their counter-offer (0: none on the table)
var guided := "" # the villager whose sale is Act 1's guided first sale ("" for an ordinary one)
var force_roll := -1.0 # tests: the roll an offer is judged by (0..1); below 0, a random one
var rng := RandomNumberGenerator.new()
## The fibre each buyer asks for (wanted_fibre()). Off in the autotest but for its own check, so the
## other checks' sales take any sweater as before.
static var fibre_on := true
## Tests: the fibre every buyer wants ("wool" for sheep's wool); "" leaves it to the day's roll.
static var force_fibre := ""
## The hamlets' keepers (hamlets.gd, data/hamlets.json): vid -> {"fibres": [...], "mult": x}. Each
## wants one of their own fibres (any of them buyers may ask for now and she has seen; sheep's
## wool when none is) and will pay up to `mult` times what anyone else would.
static var themed := {}
## The townsfolk's own "wants one today" (townsfolk.gd sets it): vid -> bool.
static var tf_looking := Callable()
const TIERS := ["plain", "common", "rare", "ultra_rare", "legendary", "mythic"]

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
	if itchy(vid):
		return false
	if themed.has(vid):
		return true # a hamlet's keeper always wants one of their own fibres
	if vid.begins_with("tf_") and tf_looking.is_valid():
		return bool(tf_looking.call(vid)) # the townsfolk roll their own day (townsfolk.gd, the red pin)
	return _day_roll(vid, "ask") < yes_chance(vid)


## Whether they bought one from her within the last `rebuy_days`: then, unless they're looking again
## already, they won't look at another yet (and say so).
static func bought_lately(vid: String) -> bool:
	var last := int((Game.flag("npc_sweater_day", {}) as Dictionary).get(vid, -99))
	return Game.day - last < int(cfg("rebuy_days", 3))


## Whether `vid` will look at her sweaters today at all. Nearly everyone will (Alex, 2026-11-27:
## "most will consider buying if the price is right. They just won't pay as much if they're not
## actively looking for a specific sweater"): not after a sore man's itch, nor days after buying one.
static func considers(vid: String) -> bool:
	if itchy(vid):
		return false
	return looking(vid) or not bought_lately(vid)


## Whether a sweater of `fibre` is the one `vid` is after today: they're looking, and for that fibre.
## Then they pay their full price; for anything else, `casual_mult` of it.
static func keen(vid: String, fibre: String = "wool") -> bool:
	if not looking(vid):
		return false
	var want := wanted_fibre(vid)
	return want == "" or want == ("wool" if fibre == "" else fibre)


## A sore man told `vid` her sweaters itch, today (scripts/partners.gd's "itch" prank, read straight
## from Game.flags["pranks"]): they won't buy one today.
static func itchy(vid: String) -> bool:
	var all: Variant = Game.flags.get("pranks", [])
	if not (all is Array):
		return false
	for p in all:
		if p is Dictionary and str(p.get("kind", "")) == "itch" and str(p.get("who", "")) == vid and int(p.get("day", -1)) == Game.day:
			return true
	return false


## The fair price of a sweater: Rosa's price for its rarity, times its fibre's tier "value" in
## data/economy.json "wants" ("wool", sheep's wool, is 1).
func fair(rarity: int, fibre: String = "wool") -> int:
	var f := float(main._wear_price(rarity))
	if fibre_on and fibre != "wool" and fibre != "":
		f *= float((_wants().get("value", {}) as Dictionary).get(fibre_tier(fibre), 1.0))
	return int(round(f))


# --- which fibre they want (Alex, 2026-11-24: specific fibres, nothing she can't get yet) ---------

static func _wants() -> Dictionary:
	return Data.economy().get("wants", {})


## The tier of a fibre ("plain" for sheep's wool).
static func fibre_tier(fibre: String) -> String:
	if fibre == "" or fibre == "wool":
		return "plain"
	return str(((Data.load_json("wildlife").get("fibres", {}) as Dictionary).get(fibre, {}) as Dictionary).get("tier", "plain"))


## The fibre her i-th sweater was knitted with ("wool" for sheep's wool).
static func fibre_of(i: int) -> String:
	if i < 0 or i >= Game.sweater_fibres.size():
		return "wool"
	var f := str(Game.sweater_fibres[i])
	return "wool" if f == "" else f


## What players read for a fibre: "sheep's wool", "angora fluff", "fox fluff"...
static func fibre_name(fibre: String) -> String:
	if fibre == "" or fibre == "wool":
		return "sheep's wool"
	return str(((Data.load_json("wildlife").get("fibres", {}) as Dictionary).get(fibre, {}) as Dictionary).get("name", fibre)).to_lower()


## The fibre tiers buyers may ask for now, plainest first: sheep's wool only until Act 1 is done,
## then up to the act's tier in "by_act", and one tier more once she has combed an animal of it.
static func open_tiers() -> Array:
	if Game.flag("act1_done") != true:
		return ["plain"]
	var cap := TIERS.find(str((_wants().get("by_act", {}) as Dictionary).get(str(clampi(Game.act, 1, 4)), "common")))
	cap = clampi(cap, 0, TIERS.size() - 1)
	if cap + 1 < TIERS.size():
		var animals: Dictionary = Data.load_json("wildlife").get("animals", {})
		var guide: Dictionary = Game.flags.get("guide", {})
		for sp in animals:
			if str((animals[sp] as Dictionary).get("tier", "")) == TIERS[cap + 1] and guide.get(sp, {}) is Dictionary and int((guide.get(sp, {}) as Dictionary).get("combed", 0)) > 0:
				cap += 1
				break
	return TIERS.slice(0, cap + 1)


## Whether a sweater of `fibre` is one buyers may ask for now.
static func fibre_open(fibre: String) -> bool:
	return fibre_tier(fibre) in open_tiers()


## The fibre `vid` wants a sweater of today ("wool" for sheep's wool; "" for any, while it's off).
## The same all day; each open tier's "weights" share is split between its fibres.
static func wanted_fibre(vid: String) -> String:
	if not fibre_on:
		return ""
	if force_fibre != "":
		return force_fibre
	if themed.has(vid): # a hamlet's keeper: one of their theme's fibres
		var own: Array = (themed[vid] as Dictionary).get("fibres", []).filter(func(f): return str(f) == "wool" or (fibre_open(str(f)) and EmpireGoals.fibre_open(str(f))))
		if own.is_empty():
			return "wool"
		return str(own[int(_day_roll(vid, "fibre") * own.size()) % own.size()])
	var w: Dictionary = _wants().get("weights", {})
	var fibres: Dictionary = Data.load_json("wildlife").get("fibres", {})
	var pool := [] # [fibre, weight]
	var total := 0.0
	for t in open_tiers():
		var of_tier := ["wool"] if t == "plain" else fibres.keys().filter(func(f): return str((fibres[f] as Dictionary).get("tier", "")) == t and EmpireGoals.fibre_open(str(f)))
		for f in of_tier:
			var wt := float(w.get(t, 1.0)) / of_tier.size()
			pool.append([str(f), wt])
			total += wt
	var r := _day_roll(vid, "fibre") * total
	for e in pool:
		r -= float(e[1])
		if r < 0.0:
			return str(e[0])
	return "wool"


## Whether her i-th sweater is one `vid` would buy today.
static func suits(vid: String, i: int) -> bool:
	var want := wanted_fibre(vid)
	return want == "" or fibre_of(i) == want


## Whether she has a sweater `vid` would buy today.
static func has_for(vid: String) -> bool:
	for i in Game.sweaters.size():
		if suits(vid, i):
			return true
	return false


## "a fox fluff sweater", "a sheep's wool sweater", or "a sweater" while it's off.
static func wanted_text(vid: String) -> String:
	var want := wanted_fibre(vid)
	return "a sweater" if want == "" else "a %s sweater" % fibre_name(want)


## The most they'd happily pay today for a sweater of `rarity`: at it the chance is even.
func reserve(vid: String, rarity: int, fibre: String = "wool") -> int:
	if guided != "" and vid == guided:
		return guided_range(rarity).y
	var m := lerpf(cfg("res_min", 0.95), cfg("res_max", 1.35), _day_roll(vid, "reserve")) + cfg("res_per_heart", 0.04) * Game.hearts(vid)
	if not keen(vid, fibre):
		m *= cfg("casual_mult", 0.82) # not what they're after today: they'll take it for less
	elif themed.has(vid): # a hamlet's keeper pays more for their own fibres (data/hamlets.json "mult")
		m *= float((themed[vid] as Dictionary).get("mult", 1.0))
	return int(round(fair(rarity, fibre) * m))


## How likely they are to say yes to `p` coins for a sweater of `rarity` (what the meter shows).
func chance(vid: String, rarity: int, p: int, fibre: String = "wool") -> float:
	if guided != "" and vid == guided: # inside her range she's all but certain; above it, less and less
		var r := guided_range(rarity)
		if p <= r.y:
			return lerpf(0.99, 0.9, clampf(inverse_lerp(float(r.x), float(r.y), float(p)), 0.0, 1.0))
		return 1.8 / (1.0 + exp((float(p) - float(r.y)) / maxf(1.0, 0.05 * fair(rarity))))
	var spread := maxf(1.0, cfg("spread", 0.12) * fair(rarity, fibre))
	return 1.0 / (1.0 + exp((float(p) - float(reserve(vid, rarity, fibre))) / spread))


## Wren's range for Act 1's first sale: [low, high] coins, in steps of 5.
## Never under the story's `first_sale_min` (data/economy.json "story"): this is her only money,
## and it has to cover Steve's seed and Rosa's yarn, the next two steps, with a little over.
func guided_range(rarity: int) -> Vector2i:
	var step := maxi(1, int(cfg("step", 5)))
	var least := int(main.homestead.econ("first_sale_min", 75)) if main and main.homestead else 75
	var lo := maxi(int(round(fair(rarity) * GUIDED_LOW / step)) * step, least)
	var hi := maxi(int(round(fair(rarity) * GUIDED_HIGH / step)) * step, lo + 3 * step)
	return Vector2i(lo, hi)


## Whether Act 1 is waiting on her first sale to `vid` (Wren, after the knock at the door).
static func guided_due(vid: String) -> bool:
	return vid == "wren" and Game.flag("act1_wren_asked") == true and Game.flag("act1_sold") != true and Game.count("sweater") > 0


## Opens the panel for Act 1's guided first sale: Wren says her range out loud.
func open_guided(villager) -> void:
	guided = str(villager.vid)
	open(villager)
	if visible and choice >= 0:
		var r := guided_range(int(Game.sweaters[choice]))
		price = r.x # start inside her range, so the price she's shown is always enough
		_refresh()
		_say("Anywhere from %dc to %dc and it's a deal. Go on, name your price." % [r.x, r.y])


## The villager's menu rows: ask, haggle again, or why not today.
func rows_for(villager) -> Array:
	if Game.count("sweater") == 0:
		return []
	var vid: String = villager.vid
	var row: Dictionary
	var a := asked(vid)
	if guided_due(vid):
		row = {"id": "sale_guided", "label": "Name your price for your sweater", "enabled": true}
	elif bought_today(vid):
		row = {"id": "noop", "label": "Bought a sweater from you today", "enabled": false}
	elif a.is_empty() and not itchy(vid) and not considers(vid):
		row = {"id": "noop", "label": "Bought a sweater from you lately", "enabled": false}
	elif a.is_empty():
		row = {"id": "sale_ask", "label": "Offer them a sweater", "enabled": true}
	elif not bool(a.get("yes", false)):
		row = {"id": "noop", "label": "Won't buy a sweater today", "enabled": false}
	elif int(a.get("tries", 0)) >= int(cfg("tries", 3)):
		row = {"id": "noop", "label": "Done haggling for today", "enabled": false}
	elif looking(vid) and not has_for(vid):
		row = {"id": "sale_haggle", "label": "Wants %s: show them another  (they'd pay less)" % wanted_text(vid), "enabled": true}
	else:
		row = {"id": "sale_haggle", "label": "Show them a sweater", "enabled": true}
	row["group"] = GROUP
	return [row]


## She asks; they say yes or no, and on a yes the panel opens.
func ask(villager) -> bool:
	var vid: String = villager.vid
	if asked(vid).is_empty():
		var yes := guided_due(vid) or considers(vid)
		_note(vid, {"yes": yes, "tries": 0})
		if not yes:
			var itch_no := str((Data.economy().get("partners", {}).get("lines", {}) as Dictionary).get("itch_no", ""))
			if itchy(vid):
				main._say(villager, itch_no if itch_no != "" else str(NO[(Game.day + vid.length()) % NO.size()]))
			else:
				main._say(villager, str(LATELY[(Game.day + vid.length()) % LATELY.size()]))
			return false
	elif not bool(asked(vid).get("yes", false)):
		return false
	open(villager)
	return true


## The sweaters she can show: one of each design, rarity and fibre, best first, only those of the
## fibre `want` ("" for any). [index, rarity, design, fibre]
static func choices(want: String = "") -> Array:
	Game.sync_sweaters()
	var seen := {}
	var out := []
	for i in Game.sweaters.size():
		var fib := fibre_of(i)
		if want != "" and fib != want:
			continue
		var key := "%s/%d/%s" % [str(Game.sweater_designs[i]), int(Game.sweaters[i]), fib]
		if not seen.has(key):
			seen[key] = true
			out.append([i, int(Game.sweaters[i]), str(Game.sweater_designs[i]), fib])
	out.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
	return out


## Every sweater she can show `vid`, the ones they're after today first (then best first).
static func choices_for(vid: String) -> Array:
	var all := choices("")
	var first := all.filter(func(e): return keen(vid, str(e[3])))
	return first + all.filter(func(e): return not keen(vid, str(e[3])))


## She offers the sweater on the table at `price`. "sold", "counter" (they name theirs), "no", or
## "gone" (they walk away for the day).
func offer() -> String:
	if v == null or choice < 0 or choice >= Game.sweaters.size():
		return "no"
	var vid: String = v.vid
	var rarity := int(Game.sweaters[choice])
	var fib := fibre_of(choice)
	if guided != "" and vid == guided: # Act 1: inside her range she buys; above it she offers her top
		var top := guided_range(rarity).y
		if price <= top:
			_sell(price)
			return "sold"
		counter = top
		_say("That's steep for a first sweater! %dc, and not a coin more." % top)
		_refresh()
		return "counter"
	var roll := force_roll if force_roll >= 0.0 else rng.randf()
	if roll < chance(vid, rarity, price, fib):
		_sell(price)
		return "sold"
	var a := asked(vid)
	a["tries"] = int(a.get("tries", 0)) + 1
	_note(vid, a)
	var res := reserve(vid, rarity, fib)
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
	var first := guided != "" and str(who.vid) == guided
	guided = ""
	close()
	if main.sell_sweater_to(who, i, p):
		if first: # Act 1 carries on with Wren's scene
			main._story_event_soon("first_sale")
		else:
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
	if guided != "" and str(villager.vid) != guided:
		guided = ""
	v = villager
	counter = 0
	var cs := _shown()
	if cs.is_empty():
		return
	choice = int(cs[0][0])
	price = _start_price(choice)
	_who.text = "Selling to %s" % v.title
	var want := _want()
	var vid := str(v.vid)
	if guided != "" and vid == guided:
		_say(str(YES[(Game.day + vid.length()) % YES.size()]))
	elif not looking(vid):
		_say(str(CASUAL[(Game.day + vid.length()) % CASUAL.size()]))
	elif want == "":
		_say(str(YES[(Game.day + vid.length()) % YES.size()]))
	elif keen(vid, str(cs[0][3])):
		_say("I'm after a %s sweater. What have you got?" % fibre_name(want))
	else:
		_say("I'm after a %s sweater, really. Show me what you have, though: I'd take another for less." % fibre_name(want))
	if hud.has_method("hide_dialogue"):
		hud.hide_dialogue()
	hud.click("ui_open")
	visible = true
	move_to_front()
	_refresh()


func close() -> void:
	visible = false


## The sweaters on the table: all of hers, the ones they're after first (Act 1's guided sale: any).
func _shown() -> Array:
	if v == null:
		return []
	if guided != "" and str(v.vid) == guided:
		return choices("")
	return choices_for(str(v.vid))


## Where the price starts for her i-th sweater: its fair price; a hamlet keeper's own fibre at their
## premium; a sweater they aren't after at the lower price they'd think about.
func _start_price(i: int) -> int:
	var f := fair(int(Game.sweaters[i]), fibre_of(i))
	if v == null or (guided != "" and str(v.vid) == guided):
		return f
	var vid := str(v.vid)
	var step := maxi(1, int(cfg("step", 5)))
	if not keen(vid, fibre_of(i)):
		return maxi(step, int(round(f * cfg("casual_start", 0.9) / step)) * step)
	if themed.has(vid):
		return int(round(f * float((themed[vid] as Dictionary).get("mult", 1.0))))
	return f


## The fibre the one she's selling to wants ("" for any; Act 1's guided sale takes any).
func _want() -> String:
	if v == null or (guided != "" and str(v.vid) == guided):
		return ""
	return wanted_fibre(str(v.vid))


func pick(i: int) -> void:
	if i < 0 or i >= Game.sweaters.size():
		return
	choice = i
	counter = 0
	price = _start_price(i)
	_refresh()


func set_price(p: int) -> void:
	if choice < 0 or choice >= Game.sweaters.size():
		return
	var f := fair(int(Game.sweaters[choice]), fibre_of(choice))
	price = clampi(p, maxi(5, f / 4), f * 4)
	_refresh()


func _refresh() -> void:
	if v == null or _picks == null:
		return
	for c in _picks.get_children():
		_picks.remove_child(c)
		c.queue_free()
	var is_guided := guided != "" and str(v.vid) == guided
	var after := _want() != "" and looking(str(v.vid))
	for e in _shown():
		var d := Sweaters.design(str(e[2]))
		var dname := str(d.get("name", "Sweater"))
		var wanted: bool = after and not is_guided and keen(str(v.vid), str(e[3]))
		var b: Button = hud._button("%s%s\n%s · %s" % ["★ " if wanted else "", dname, RARITY[clampi(int(e[1]), 1, 5) - 1], fibre_name(str(e[3]))], pick.bind(int(e[0])))
		b.custom_minimum_size = Vector2(118, 56)
		b.add_theme_font_size_override("font_size", 12)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if int(e[0]) == choice:
			b.modulate = Color(1.15, 1.05, 0.8)
		_picks.add_child(b)
	if choice < 0 or choice >= Game.sweaters.size():
		return
	var rarity := int(Game.sweaters[choice])
	var fib := fibre_of(choice)
	var p := chance(v.vid, rarity, price, fib)
	_price_label.text = "%dc" % price
	_fair_label.text = ("Rosa would give you %dc for it today." % fair(rarity)) if fibre_tier(fib) == "plain" or not fibre_on else ("A fair price for %s: about %dc." % [fibre_name(fib), fair(rarity, fib)])
	if not is_guided:
		# which kind of buyer this is today, so the price makes sense
		if keen(str(v.vid), fib):
			_fair_label.text += "\nJust what they're after today: they'll pay well for it."
		elif looking(str(v.vid)):
			_fair_label.text += "\nNot the %s they're after: they'd pay less for this one." % fibre_name(_want())
		else:
			_fair_label.text += "\nNot looking for one today: they'd pay less than someone who is."
	_meter_fill.size.x = 456.0 * p
	_meter_fill.color = Color(0.85, 0.3, 0.25).lerp(Color(0.95, 0.75, 0.3), clampf(p * 2.0, 0.0, 1.0)).lerp(Color(0.45, 0.8, 0.4), clampf(p * 2.0 - 1.0, 0.0, 1.0))
	_meter_label.text = "%s  ·  %d%% likely to say yes" % [("Happy to pay that" if p >= 0.75 else ("Thinking about it" if p >= 0.4 else ("A stretch" if p >= 0.15 else "Far too dear"))), int(round(p * 100.0))]
	_offer.text = "Offer %dc" % price
	_take.visible = counter > 0
	_take.text = "Take %dc" % counter
