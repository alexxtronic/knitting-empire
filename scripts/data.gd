extends RefCounted
## Game content lives in res://data/*.json so it can be tuned and written without touching code:
##   furniture.json  Build-mode catalog        crops.json      seeds and growth times
##   economy.json    prices, costs, limits     villagers.json  who lives in Maplewood
##   dialogue.json   what villagers say
## Each file is read once and cached. validate() cross-checks the files (run by the autotest).
## When exporting the game, add "data/*.json" to the export preset's non-resource include filter.

static var _cache := {}


static func load_json(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := "res://data/%s.json" % name
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Could not read %s (missing file or invalid JSON)" % path)
		parsed = {}
	_cache[name] = parsed
	return parsed


static func vec2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func vec3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func color(s) -> Color:
	return Color.html(str(s))


## id -> {name, price, size: Vector2, where, height, flat?, shop}
static func furniture() -> Dictionary:
	var out := {}
	for e in load_json("furniture").get("items", []):
		var info: Dictionary = (e as Dictionary).duplicate()
		info["price"] = int(info.get("price", 0))
		info["size"] = vec2(info.get("size", [1, 1]))
		info["height"] = float(info.get("height", 1.0))
		out[str(info["id"])] = info
	return out


## Furniture ids for one Build-menu section ("indoors" or "yard"), in file order.
static func furniture_ids(shop: String) -> Array:
	var out := []
	for e in load_json("furniture").get("items", []):
		if str(e.get("shop", "")) == shop:
			out.append(str(e["id"]))
	return out


## id -> {name, seed: int, hours: float}
static func crops() -> Dictionary:
	var out := {}
	for e in load_json("crops").get("crops", []):
		out[str(e["id"])] = {"name": str(e["name"]), "seed": int(e["seed"]), "hours": float(e["hours"])}
	return out


static func economy() -> Dictionary:
	return load_json("economy")


static func int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = int(d[k])
	return out


## Villager definitions with positions as vectors and look colors as Colors.
static func villagers() -> Array:
	var out := []
	for e in load_json("villagers").get("villagers", []):
		var v: Dictionary = (e as Dictionary).duplicate(true)
		v["pos"] = vec3(v["pos"])
		v["roam"] = vec2(v.get("roam", [1.0, 0.4]))
		if v.has("talk_spot"):
			v["talk_spot"] = vec3(v["talk_spot"])
		var look: Dictionary = v.get("look", {})
		for k in ["skin", "hair", "top", "bottom"]:
			if look.has(k):
				look[k] = color(look[k])
		v["look"] = look
		out.append(v)
	return out


static func dialogue() -> Dictionary:
	return load_json("dialogue")


## Cross-checks the content files. Returns a list of problems (empty = all good).
static func validate(has_builder: Callable) -> Array:
	var errs := []
	var econ := economy()
	var items := {}
	for k in econ.get("sell_prices", {}):
		items[k] = true
	for k in ["start_coins", "start_inventory", "start_sheep", "sell_prices", "market_base", "expand_costs", "wool_pack_price", "sheep_price", "max_sheep", "cottage_price", "max_hearts"]:
		if not econ.has(k):
			errs.append("economy.json is missing '%s'" % k)
	for id in furniture():
		if not has_builder.call(id):
			errs.append("furniture '%s' has no builder in catalog.gd" % id)
	for id in crops():
		if not items.has(id):
			errs.append("crop '%s' has no sell price in economy.json" % id)
	var dlg := dialogue()
	for v in villagers():
		var id := str(v["id"])
		if not items.has(str(v.get("loves", ""))):
			errs.append("villager '%s' loves unknown item '%s'" % [id, v.get("loves", "")])
		if not dlg.get("intro", {}).has(id):
			errs.append("villager '%s' has no intro line" % id)
		if dlg.get("lines", {}).get(id, []).size() != 3:
			errs.append("villager '%s' needs 3 tiers of lines" % id)
		if not dlg.get("gift_loved", {}).has(id):
			errs.append("villager '%s' has no loved-gift line" % id)
	return errs
