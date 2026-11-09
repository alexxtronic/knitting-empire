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
const SAVE_VERSION := 3
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
var energy: float = 100.0
var fullness: float = 80.0
var day: int = 1
var hour: float = 8.0
var house_level: int = 0
var time_running := true
var friends := {} # villager id -> {"familiarity", "trust", "romance", "talk" (last day talked), "gift" (last day gifted), "n" (chats)}
var owns_cottage := false
var sheep_count: int = 3
## Story progress: named flags set by scenes and choices ("met_rowan", "act1_done", ...).
var flags := {}


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
	energy = 100.0
	fullness = 80.0
	day = 1
	hour = 8.0
	house_level = 0
	time_running = true
	friends = {}
	owns_cottage = false
	sheep_count = START_SHEEP
	flags = {}


func _process(delta: float) -> void:
	if not time_running:
		return
	hour += delta / HOUR_SECONDS
	fullness = maxf(0.0, fullness - delta * 0.22)
	if fullness <= 0.0:
		energy = maxf(0.0, energy - delta * 0.4)


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

func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value


func flag(flag_name: String, default: Variant = false) -> Variant:
	return flags.get(flag_name, default)


# --- save data -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION, "flags": flags,
		"coins": coins, "inv": inv, "energy": energy, "fullness": fullness,
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
	energy = float(d.get("energy", 100.0))
	fullness = float(d.get("fullness", 80.0))
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
