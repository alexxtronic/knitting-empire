extends Node
## Global game state (autoloaded as `Game`): money, inventory, needs, clock, story flags.
## Prices and limits come from res://data/economy.json (see scripts/data.gd).

const Data = preload("res://scripts/data.gd")

signal toast(text: String)
signal day_started(day: int)

const HOUR_SECONDS := 10.0 # real seconds per in-game hour
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const MAX_HOUSE_LEVEL := 3
## Save files carry a version; migrate() upgrades older ones step by step.
## v1: first prototype (no version field). v2: adds story flags.
## v3: friendship points become three relationship stats: familiarity, trust, romance.
## v4: adds the needs happiness, love, warmth and fitness, knitting skill and the sweater she wears.
## v5: adds typed chats with villagers (the last lines of each conversation).
const SAVE_VERSION := 5
## Relationship stats and their ranges. Familiarity drives hearts (20 per heart).
const STATS := {"familiarity": [0, 100], "trust": [-50, 100], "romance": [0, 100]}

# --- tuning, loaded from data/economy.json --------------------------------------
var SELL_PRICES := {}
var EXPAND_COSTS: Array = []
## Maplewood market: base prices that drift up and down every morning.
var MARKET_BASE := {}
var WOOL_PACK_PRICE := 0
var SHEEP_PRICE := 0
var START_SHEEP := 3
var MAX_SHEEP := 6
var COTTAGE_PRICE := 0
var MAX_HEARTS := 5
var START_COINS := 250
var START_INVENTORY := {}

var save_path := "user://knitting_empire_save.json"

var coins: int = 250
var inv := {}
## Where each carried thing sits: item ids, "" for an empty slot. The first nine are the hotbar,
## the rest the bag (hud.gd). Counts stay in `inv`; sync_slots() keeps the two in step.
const SLOTS := 36
var slots: Array = []
# --- needs, 0..100 (100 = fully met). Shown in the needs panel (hud.gd). ---------
var energy: float = 100.0
var fullness: float = 80.0 # shown as "Hunger"
var happiness: float = 70.0 # knitting, animals, reading, good food; sinks when other needs are low
var love: float = 50.0 # time with people: talking, gifts, story moments
var warmth: float = 70.0 # drifts toward warmth_target (main.gd: weather, night, indoors, her sweater)
var fitness: float = 45.0 # walking and farm work
var warmth_target: float = 70.0
## Knitting skill: sweaters knit so far. Quality (1..5 stars) grows with it.
var knit_xp: int = 0
## Quality of the warmest thing she owns to wear: 1 = the thin city coat she arrived in.
var worn_quality: int = 1
const NEEDS := ["energy", "fullness", "happiness", "love", "warmth", "fitness"]
var day: int = 1
var hour: float = 8.0
var clock_frozen := false # god mode (settings): the hour stands still, everything else carries on
var house_level: int = 0
var time_running := true
var friends := {} # villager id -> {"familiarity", "trust", "romance", "talk" (last day talked), "gift" (last day gifted), "n" (chats)}
var owns_cottage := false
var sheep_count: int = 3
## Story progress: named flags set by scenes and choices ("met_rowan", "act1_done", ...).
var flags := {}
## Typed chats (ai_chat.gd): villager id -> {"day": last day you chatted, "msgs": [{role, content}]}.
var chats := {}


func _init() -> void:
	load_tuning()
	reset()


func load_tuning() -> void:
	var e := Data.economy()
	SELL_PRICES = Data.int_dict(e.get("sell_prices", {}))
	MARKET_BASE = Data.int_dict(e.get("market_base", {}))
	EXPAND_COSTS = []
	for c in e.get("expand_costs", []):
		EXPAND_COSTS.append(int(c))
	WOOL_PACK_PRICE = int(e.get("wool_pack_price", 36))
	SHEEP_PRICE = int(e.get("sheep_price", 400))
	START_SHEEP = int(e.get("start_sheep", 3))
	MAX_SHEEP = int(e.get("max_sheep", 6))
	COTTAGE_PRICE = int(e.get("cottage_price", 2500))
	MAX_HEARTS = int(e.get("max_hearts", 5))
	START_COINS = int(e.get("start_coins", 250))
	START_INVENTORY = Data.int_dict(e.get("start_inventory", {}))


func reset() -> void:
	coins = START_COINS
	inv = START_INVENTORY.duplicate()
	slots = []
	energy = 100.0
	fullness = 80.0
	happiness = 70.0
	love = 50.0
	warmth = 70.0
	warmth_target = 70.0
	fitness = 45.0
	knit_xp = 0
	worn_quality = 1
	day = 1
	hour = 8.0
	house_level = 0
	time_running = true
	friends = {}
	owns_cottage = false
	sheep_count = START_SHEEP
	flags = {}
	chats = {}


func _process(delta: float) -> void:
	if not time_running:
		return
	if not clock_frozen:
		hour += delta / HOUR_SECONDS
	fullness = maxf(0.0, fullness - delta * 0.22)
	if fullness <= 0.0:
		energy = maxf(0.0, energy - delta * 0.4)
	warmth = move_toward(warmth, warmth_target, delta * 1.2)
	if warmth < 25.0:
		energy = maxf(0.0, energy - delta * 0.08) # shivering is tiring
	# happiness slips slowly, faster when she's hungry, cold, exhausted or lonely
	var low := 0.0
	for v in [fullness, warmth, energy, love]:
		if v < 25.0:
			low += 0.07
	happiness = clampf(happiness - delta * (0.05 + low), 0.0, 100.0)
	love = maxf(0.0, love - delta * 0.035)
	fitness = maxf(0.0, fitness - delta * 0.02)


## Adds to a need (energy, fullness, happiness, love, warmth, fitness), kept within 0..100.
func add_need(need: String, amount: float) -> void:
	set(need, clampf(float(get(need)) + amount, 0.0, 100.0))


## Quality (1..5) of the next sweater she knits: better with every few she's made.
func knit_quality() -> int:
	return clampi(2 + knit_xp / 3, 2, 5)


## Records a finished sweater. Returns its quality. She wears the best one she's made.
func knit_sweater() -> int:
	var q := knit_quality()
	knit_xp += 1
	if q > worn_quality:
		worn_quality = q
	return q


static func stars(q: int) -> String:
	return "★".repeat(q) + "☆".repeat(maxi(0, 5 - q))


# --- clock -------------------------------------------------------------------

func season_name() -> String:
	return SEASONS[(2 + int((day - 1) / 28.0)) % 4]


func day_of_season() -> int:
	return ((day - 1) % 28) + 1


func clock_text() -> String:
	var h := int(hour) % 24
	var m := int((hour - floorf(hour)) * 6.0) * 10
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, ampm]


## 1.0 in full daylight, 0.0 at night, smooth at dawn and dusk.
func daylight() -> float:
	var h := hour
	if h < 5.5 or h >= 20.5:
		return 0.0
	if h < 7.5:
		return smoothstep(5.5, 7.5, h)
	if h < 18.0:
		return 1.0
	return 1.0 - smoothstep(18.0, 20.5, h)


func sleep() -> void:
	day += 1
	hour = 6.0
	energy = 100.0
	fullness = maxf(15.0, fullness - 25.0)
	happiness = clampf(happiness + 10.0, 0.0, 100.0) # a fresh morning
	warmth = maxf(warmth, 70.0) # under the quilt all night
	day_started.emit(day)


# --- money & items -------------------------------------------------------------

func spend(amount: int) -> bool:
	if coins < amount:
		toast.emit("Not enough coins (need %d)." % amount)
		return false
	coins -= amount
	return true


func add_item(id: String, n: int = 1) -> void:
	inv[id] = int(inv.get(id, 0)) + n


## Gives every carried thing a slot (the first empty one) and empties the slots of things used up.
func sync_slots() -> void:
	if slots.size() != SLOTS:
		slots.resize(SLOTS)
		for i in SLOTS:
			if slots[i] == null:
				slots[i] = ""
	for i in SLOTS:
		if slots[i] != "" and count(str(slots[i])) <= 0:
			slots[i] = ""
	for id in inv:
		if int(inv[id]) > 0 and not slots.has(id):
			var free := slots.find("")
			if free >= 0:
				slots[free] = id


func swap_slots(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t


func count(id: String) -> int:
	return int(inv.get(id, 0))


func has_item(id: String, n: int = 1) -> bool:
	return count(id) >= n


func take_item(id: String, n: int = 1) -> bool:
	if not has_item(id, n):
		return false
	inv[id] = count(id) - n
	return true


func use_energy(amount: float) -> bool:
	if energy < amount:
		toast.emit("You're too tired. Rest in a chair or sleep in your bed.")
		return false
	energy -= amount
	return true


# --- town: market & friendships ------------------------------------------------

## Today's Maplewood market price for an item: 80%..130% of base, new every morning.
func market_price(item: String) -> int:
	var h := absi(("%d:%s" % [day, item]).hash())
	var f := 0.8 + float(h % 1000) / 1000.0 * 0.5
	return int(round(float(MARKET_BASE[item]) * f))


func friend(id: String) -> Dictionary:
	if not friends.has(id):
		friends[id] = {"familiarity": 0, "trust": 0, "romance": 0, "talk": 0, "gift": 0, "n": 0}
	return friends[id]


## 0..5 hearts; every 20 familiarity is one heart.
func hearts(id: String) -> int:
	return mini(MAX_HEARTS, int(friend(id)["familiarity"]) / 20)


## How well you know someone (talking, gifts). Shown as hearts.
func add_friendship(id: String, pts: int) -> void:
	add_stat(id, "familiarity", pts)


func stat(id: String, stat_name: String) -> int:
	return int(friend(id).get(stat_name, 0))


## Changes familiarity, trust or romance, kept within its range. Returns the new value.
func add_stat(id: String, stat_name: String, amount: int) -> int:
	if not STATS.has(stat_name):
		push_error("Unknown relationship stat '%s'" % stat_name)
		return 0
	var f := friend(id)
	var lim: Array = STATS[stat_name]
	f[stat_name] = clampi(int(f.get(stat_name, 0)) + amount, int(lim[0]), int(lim[1]))
	return int(f[stat_name])


# --- story flags ---------------------------------------------------------------

## The saved conversation with a villager (created empty on first use).
func chat(id: String) -> Dictionary:
	if not chats.has(id):
		chats[id] = {"day": 0, "msgs": []}
	return chats[id]


func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value


func flag(flag_name: String, default: Variant = false) -> Variant:
	return flags.get(flag_name, default)


## Her journal: what the story has written down, oldest first. Kept in the flags, so it saves.
func journal() -> Array:
	return flags.get("journal", [])


func add_journal(kind: String, title: String, text: String) -> void:
	var j: Array = journal().duplicate()
	j.append({"kind": kind, "title": title, "text": text, "day": day})
	flags["journal"] = j


# --- save data -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "flags": flags, "chats": chats,
		"coins": coins, "inv": inv, "slots": slots, "energy": energy, "fullness": fullness,
		"happiness": happiness, "love": love, "warmth": warmth, "fitness": fitness,
		"knit_xp": knit_xp, "worn_quality": worn_quality,
		"day": day, "hour": hour, "house_level": house_level,
		"friends": friends, "owns_cottage": owns_cottage, "sheep_count": sheep_count,
	}


## Upgrades a save dictionary from any older version to SAVE_VERSION, one step at a time.
## Add a new `if v < N` step whenever the save format changes; never edit old steps.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		d["flags"] = {} # v1 saves predate the story system
		v = 2
	if v < 3:
		# friendship points become familiarity; trust and romance start at zero
		var fr: Dictionary = d.get("friends", {})
		for id in fr:
			var e: Dictionary = fr[id]
			e["familiarity"] = int(e.get("pts", e.get("familiarity", 0)))
			e.erase("pts")
			e["trust"] = int(e.get("trust", 0))
			e["romance"] = int(e.get("romance", 0))
		v = 3
	if v < 4:
		# new needs start at comfortable values; skill counts sweaters already made by guessing none
		d["happiness"] = 70.0
		d["love"] = 50.0
		d["warmth"] = 70.0
		d["fitness"] = 45.0
		d["knit_xp"] = 0
		d["worn_quality"] = 1
		v = 4
	if v < 5:
		d["chats"] = {}
		v = 5
	d["version"] = v
	return d


func from_dict(d: Dictionary) -> void:
	d = migrate(d)
	coins = int(d.get("coins", START_COINS))
	inv = START_INVENTORY.duplicate()
	for k in inv.keys():
		inv[k] = 0
	var saved_inv: Dictionary = d.get("inv", {})
	for k in saved_inv:
		inv[str(k)] = int(saved_inv[k])
	slots = []
	var seen := {}
	for id in d.get("slots", []):
		var sid := str(id)
		slots.append(sid if not seen.has(sid) else "") # an id sits in one slot only
		if sid != "":
			seen[sid] = true
	sync_slots()
	energy = float(d.get("energy", 100.0))
	fullness = float(d.get("fullness", 80.0))
	happiness = float(d.get("happiness", 70.0))
	love = float(d.get("love", 50.0))
	warmth = float(d.get("warmth", 70.0))
	warmth_target = warmth
	fitness = float(d.get("fitness", 45.0))
	knit_xp = int(d.get("knit_xp", 0))
	worn_quality = clampi(int(d.get("worn_quality", 1)), 1, 5)
	day = int(d.get("day", 1))
	hour = float(d.get("hour", 8.0))
	house_level = int(d.get("house_level", 0))
	friends = {}
	var saved_friends: Dictionary = d.get("friends", {})
	for id in saved_friends:
		var e: Dictionary = saved_friends[id]
		friends[id] = {"familiarity": int(e.get("familiarity", 0)), "trust": int(e.get("trust", 0)), "romance": int(e.get("romance", 0)),
			"talk": int(e.get("talk", 0)), "gift": int(e.get("gift", 0)), "n": int(e.get("n", 0))}
	owns_cottage = bool(d.get("owns_cottage", false))
	sheep_count = clampi(int(d.get("sheep_count", START_SHEEP)), START_SHEEP, MAX_SHEEP)
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	chats = {}
	var saved_chats: Dictionary = d.get("chats", {})
	for id in saved_chats:
		var c = saved_chats[id]
		if c is Dictionary:
			var msgs: Array = []
			for m in c.get("msgs", []):
				if m is Dictionary and str(m.get("role", "")) in ["user", "assistant"]:
					msgs.append({"role": str(m["role"]), "content": str(m.get("content", ""))})
			chats[str(id)] = {"day": int(c.get("day", 0)), "msgs": msgs}
