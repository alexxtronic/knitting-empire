extends Node
## Global game state (autoloaded as `Game`): money, inventory, needs, clock.

signal toast(text: String)
signal day_started(day: int)

const HOUR_SECONDS := 10.0 # real seconds per in-game hour
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const SELL_PRICES := {"wool": 8, "turnip": 35, "pumpkin": 95, "sweater": 140}
const EXPAND_COSTS := [800, 2000, 4500]
const MAX_HOUSE_LEVEL := 3
## Maplewood market: base prices that drift up and down every morning.
const MARKET_BASE := {"sweater": 150, "pumpkin": 105, "turnip": 38}
const WOOL_PACK_PRICE := 36
const SHEEP_PRICE := 400
const MAX_SHEEP := 6
const COTTAGE_PRICE := 2500
const MAX_HEARTS := 5

var save_path := "user://knitting_empire_save.json"

var coins: int = 250
var inv := {"wool": 3, "turnip": 2, "pumpkin": 0, "sweater": 0}
var energy: float = 100.0
var fullness: float = 80.0
var day: int = 1
var hour: float = 8.0
var house_level: int = 0
var time_running := true
var friends := {} # villager id -> {"pts", "talk" (last day talked), "gift" (last day gifted), "n" (chats)}
var owns_cottage := false
var sheep_count: int = 3


func reset() -> void:
	coins = 250
	inv = {"wool": 3, "turnip": 2, "pumpkin": 0, "sweater": 0}
	energy = 100.0
	fullness = 80.0
	day = 1
	hour = 8.0
	house_level = 0
	time_running = true
	friends = {}
	owns_cottage = false
	sheep_count = 3


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
		friends[id] = {"pts": 0, "talk": 0, "gift": 0, "n": 0}
	return friends[id]


## 0..5 hearts; every 20 friendship points is one heart.
func hearts(id: String) -> int:
	return mini(MAX_HEARTS, int(friend(id)["pts"]) / 20)


func add_friendship(id: String, pts: int) -> void:
	var f := friend(id)
	f["pts"] = mini(MAX_HEARTS * 20, int(f["pts"]) + pts)


# --- save data -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"coins": coins, "inv": inv, "energy": energy, "fullness": fullness,
		"day": day, "hour": hour, "house_level": house_level,
		"friends": friends, "owns_cottage": owns_cottage, "sheep_count": sheep_count,
	}


func from_dict(d: Dictionary) -> void:
	coins = int(d.get("coins", 250))
	var saved_inv: Dictionary = d.get("inv", {})
	for k in inv.keys():
		inv[k] = int(saved_inv.get(k, 0))
	energy = float(d.get("energy", 100.0))
	fullness = float(d.get("fullness", 80.0))
	day = int(d.get("day", 1))
	hour = float(d.get("hour", 8.0))
	house_level = int(d.get("house_level", 0))
	friends = {}
	var saved_friends: Dictionary = d.get("friends", {})
	for id in saved_friends:
		var e: Dictionary = saved_friends[id]
		friends[id] = {"pts": int(e.get("pts", 0)), "talk": int(e.get("talk", 0)), "gift": int(e.get("gift", 0)), "n": int(e.get("n", 0))}
	owns_cottage = bool(d.get("owns_cottage", false))
	sheep_count = clampi(int(d.get("sheep_count", 3)), 3, MAX_SHEEP)
