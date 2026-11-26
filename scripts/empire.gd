extends Node
## The knitting empire's own systems (Alex, 2026-11-15, docs/DIRECTION.md): the things her money
## buys to make better knits and go further, and the locals' requests that send her out for rare
## animals.
##
## Needles (data/economy.json "gear", sold by Rosa): each better pair sets the least a sweater she
## knits can be (`floor`, 1 Common .. 5 Legendary on the knitting game's scale). Her pair is
## Game.flags["needles"]; she starts with Gran's bamboo ones.
##
## The lantern (sold by Steve): once she has one she carries it in her left hand whenever it's dark
## out, and it lights her way.
##
## Requests (data/requests.json): one local at a time wants a sweater knitted from a wild animal's
## fibre. Asked, they say what they want and a goal sends her to find the animal; the sweater she
## then knits with that fibre is put by for them, and handing it over pays far more than Rosa
## would. The state is Game.flags["request"] ({"i", "who", "fibre", "pay", "made", "design"}),
## "requests_done" (how many she has filled) and "request_day" (the day the next one may come).

const Data = preload("res://scripts/data.gd")
const KnitGame = preload("res://scripts/knit_game.gd")
const Sweaters = preload("res://scripts/sweaters.gd")
const Hud = preload("res://scripts/hud.gd")
const Catalog = preload("res://scripts/catalog.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")
const Explore = preload("res://scripts/explore.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const LANTERN_MODEL := "res://assets/props/lantern.glb" # art/world_assets/lantern/build.py; its origin is the ring's top
const GLOBE_DROP := 0.175 # metres from the ring's top down to the flame
const LIGHT_OUT := 0.14 # how far out from her side the light sits, so it doesn't burn a patch on her sweater

var main: Node # main.gd
var _gear := {}
var _req := {}
var _lamp: OmniLight3D
var _lantern: Node3D # the lantern model, hung from her left fist after dark
var _swing := Vector3.ZERO # where her hand was a moment ago: the lantern lags behind it


func _ready() -> void:
	name = "Empire"
	_gear = Data.load_json("economy").get("gear", {})
	_req = Data.load_json("requests")


# --- needles -----------------------------------------------------------------------------------

func needle_defs() -> Array:
	return _gear.get("needles", [])


func needle_def(id: String) -> Dictionary:
	for d in needle_defs():
		if str(d.get("id", "")) == id:
			return d
	return {}


## Her pair's place in the list (-1: Gran's bamboo ones).
func needle_rank() -> int:
	var mine := str(Game.flag("needles", ""))
	var defs := needle_defs()
	for i in defs.size():
		if str(defs[i].get("id", "")) == mine:
			return i
	return -1


func needle_name() -> String:
	var r := needle_rank()
	var bought := clampi(int(needle_defs()[r].get("floor", 1)), 1, 5) if r >= 0 else 1
	if Explore.found_floor() > bought:
		return Explore.found_name()
	return str(needle_defs()[r].get("name", "")) if r >= 0 else str(_gear.get("first_needles", "Gran's bamboo needles"))


## The least a sweater she knits can be (1..5) with the needles she has.
func needle_floor() -> int:
	var r := needle_rank()
	var bought := clampi(int(needle_defs()[r].get("floor", 1)), 1, 5) if r >= 0 else 1
	return clampi(maxi(bought, Explore.found_floor()), 1, 5) # or a pair she found out in the world (explore.gd)


## Rosa's rows: the next pair up, or what she already knits with.
func needle_rows() -> Array:
	var defs := needle_defs()
	var next := needle_rank() + 1
	if next >= defs.size():
		return [main._act("noop", "%s  (the best there are)" % needle_name(), false)]
	var d: Dictionary = defs[next]
	var price := int(d.get("price", 0))
	return [main._act("buy_needles", "Buy %s  (%dc · every knit %s or better)" % [str(d.get("name", "needles")).to_lower(), price, KnitGame.rarity_name(int(d.get("floor", 1)))], Game.coins >= price)]


func buy_needles(v) -> bool:
	var defs := needle_defs()
	var next := needle_rank() + 1
	if next >= defs.size():
		return false
	var d: Dictionary = defs[next]
	if not Game.spend(int(d.get("price", 0))):
		return false
	Game.set_flag("needles", str(d["id"]))
	main._say(v, str(d.get("line", "Good needles make good knitting, love.")))
	main.hud.show_toast("New needles: %s. Every sweater you knit is %s or better now." % [str(d["name"]), KnitGame.rarity_name(needle_floor())])
	return true


# --- the lantern -------------------------------------------------------------------------------

func lantern_price() -> int:
	return int(_gear.get("lantern", 45))


func has_lantern() -> bool:
	return Game.has_item("lantern")


func lantern_rows() -> Array:
	if has_lantern():
		return [main._act("noop", "Lantern  (you have one)", false)]
	return [main._act("buy_lantern", "Buy a lantern  (%dc · lights your way at night)" % lantern_price(), Game.coins >= lantern_price())]


func buy_lantern(v) -> bool:
	if has_lantern() or not Game.spend(lantern_price()):
		return false
	Game.add_item("lantern", 1)
	main._say(v, "Storm lantern. Burns all night. Don't leave it in the barn.")
	main.hud.show_toast("New: a lantern. It lights itself whenever it's dark out.")
	return true


## How brightly it burns now (0 = out): only when it's dark, and only if she has one.
func lantern_level() -> float:
	if not has_lantern() or main.sleeping or main.title_on:
		return 0.0
	return 1.0 - smoothstep(0.25, 0.6, Game.daylight())


func lantern_lit() -> bool:
	return _lamp != null and _lamp.visible


## True while the lantern hangs from her left hand (for the autotest).
func lantern_in_hand() -> bool:
	return _lantern != null and _lantern.visible


## Every frame from main._process: after dark the lantern hangs from her left fist, upright
## whatever her arm does, swinging a little as she walks, and its warm light goes with it. Put
## away by day, in a story scene, and while she sits or lies down.
func update(delta: float) -> void:
	var level := lantern_level()
	var pl = main.player
	var out: bool = level > 0.01 and int(main.mode) == 0 and not main.story.is_playing() and not pl.is_sitting() and not pl.is_lying()
	if pl.body:
		pl.body.hold_left = out
	if not out:
		if _lamp:
			_lamp.visible = false
		if _lantern:
			_lantern.visible = false
		return
	if _lamp == null:
		_lamp = OmniLight3D.new()
		_lamp.name = "LanternLight"
		_lamp.light_color = Color(1.0, 0.78, 0.48)
		_lamp.omni_range = 16.0
		_lamp.omni_attenuation = 0.9
		_lamp.shadow_enabled = false
		main.add_child(_lamp)
	if _lantern == null and ResourceLoader.exists(LANTERN_MODEL):
		_lantern = Node3D.new()
		_lantern.name = "Lantern"
		main.add_child(_lantern)
		Catalog.model(LANTERN_MODEL, _lantern)
	var at: Vector3 = pl.position + Vector3(0.0, 1.1, 0.0)
	var sk: Skeleton3D = pl.body.skeleton if pl.body else null
	if _lantern and sk and sk.find_bone("LeftHand") >= 0:
		# her left fist: as far beyond the wrist as the right one is (main.FIST_C, mirrored)
		var bone := sk.find_bone("LeftHand")
		var fist: Vector3 = sk.get_bone_global_rest(bone).affine_inverse() * Vector3(-main.FIST_C.x, main.FIST_C.y, main.FIST_C.z)
		var hand: Vector3 = sk.global_transform * (sk.get_bone_global_pose(bone) * fist)
		# it hangs straight down from the ring and lags a little behind her hand: a gentle swing
		_swing = _swing.lerp(hand, 1.0 - exp(-delta * 14.0)) if _lantern.visible else hand
		var lag := _swing - hand
		_lantern.visible = true
		_lantern.global_position = hand
		_lantern.global_rotation = Vector3(clampf(lag.z * 2.5, -0.35, 0.35), pl.rotation.y, clampf(-lag.x * 2.5, -0.35, 0.35))
		# the light sits at the flame, nudged out away from her side: right beside the sweater it
		# burned a white patch on the knit (60_lantern_hand.png, 2026-11-15)
		var out_dir := Vector3(hand.x - pl.position.x, 0.0, hand.z - pl.position.z)
		at = hand + Vector3(0.0, -GLOBE_DROP, 0.0) + (out_dir.normalized() * LIGHT_OUT if out_dir.length() > 0.01 else Vector3.ZERO)
	_lamp.visible = true
	_lamp.light_energy = 3.2 * level
	_lamp.position = at


# --- requests ----------------------------------------------------------------------------------

func request_defs() -> Array:
	return _req.get("requests", [])


## The request she has taken ({} if none).
func request() -> Dictionary:
	var r: Variant = Game.flag("request", {})
	return r if r is Dictionary else {}


func requests_done() -> int:
	return int(Game.flag("requests_done", 0))


## The ids of the requests she has filled. A save from before they had ids (and before they waited
## on hearts) kept only a count: the first that many fibre requests, in the list's order.
func filled() -> Array:
	var f: Variant = Game.flag("requests_filled", null)
	if f is Array:
		return f
	var out := []
	for d in request_defs():
		if out.size() >= requests_done():
			break
		if d.has("fibre"):
			out.append(str(d.get("id", "")))
	return out


const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]


## The plainest sweater in her bag at least `rarity` good (its index in Game.sweaters), or -1.
func sweater_for(rarity: int) -> int:
	var best := -1
	for i in Game.sweaters.size():
		var q := int(Game.sweaters[i])
		if q >= rarity and (best < 0 or q < int(Game.sweaters[best])):
			best = i
	return best


## How good the sweater she'd hand over is (0: none yet): the one put by for a fibre request, or
## the plainest in her bag that will do for a rarity one.
func _made(r: Dictionary) -> int:
	if r.has("rarity"):
		var i := sweater_for(int(r["rarity"]))
		return int(Game.sweaters[i]) if i >= 0 else 0
	return int(r.get("made", 0))


## True once the story lets locals ask: Act 1 is behind her (or the farm never had it).
func open() -> bool:
	return Game.flag("act1_done") == true or Game.flag("story_farm") != true


## The request waiting to be asked for ({} if none is due): the first in the list not yet filled
## whose villager likes her enough (its "hearts"), once the last one is filled and a day or two
## has passed (Alex, 2026-11-15: a good relationship brings requests, and a request pays a bonus).
func due() -> Dictionary:
	if not open() or not request().is_empty() or Game.day < int(Game.flag("request_day", 0)):
		return {}
	var done := filled()
	for d in request_defs():
		if not done.has(str(d.get("id", ""))) and Game.hearts(str(d["who"])) >= int(d.get("hearts", 0)):
			if SweaterSale.fibre_on and d.has("fibre") and not SweaterSale.fibre_open(str(d["fibre"])):
				continue # a fibre she can't get yet (sweater_sale.gd open_tiers()): it waits
			return d
	return {}


## Whether `vid` has something to say about a request: they want to ask, or she has their sweater.
func wants(vid: String) -> bool:
	var r := request()
	if not r.is_empty():
		return str(r.get("who", "")) == vid and _made(r) > 0
	return str(due().get("who", "")) == vid


func _fibre_name(id: String) -> String:
	return str(main.wildlife.item_name(id))


func _animal_of(fibre: String) -> String:
	var species: Dictionary = main.wildlife.data.get("animals", {})
	for id in species:
		if str(species[id].get("fibre", "")) == fibre:
			return str(species[id].get("name", id)).to_lower()
	return "animal"


## The villager's menu rows: ask what they want, or hand over their sweater.
func rows_for(v) -> Array:
	var r := request()
	var rows := []
	if r.is_empty():
		var d := due()
		if str(d.get("who", "")) == v.vid:
			rows.append(_row("request_ask", "Ask what %s wanted" % v.title))
	elif str(r.get("who", "")) == v.vid:
		if _made(r) > 0:
			rows.append(_row("request_give", "Give %s the sweater  (+%dc)" % [v.title, payout()]))
		elif r.has("rarity"):
			rows.append(_row("noop", "A %s sweater or better  (+%dc)" % [RARITY[clampi(int(r["rarity"]), 1, 5) - 1], int(r["pay"])], false))
		else:
			rows.append(_row("noop", "A sweater of %s  (find a %s, comb it, knit with its fibre)" % [_fibre_name(str(r["fibre"])).to_lower(), _animal_of(str(r["fibre"]))], false))
	return rows


func _row(id: String, label: String, enabled := true) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "group": "Request"}


## They say what they want, and it becomes her goal.
func ask(v) -> void:
	var d := due()
	if str(d.get("who", "")) != v.vid:
		return
	var r := {"id": str(d.get("id", "")), "who": v.vid, "pay": int(d.get("pay", 200)), "made": 0, "design": ""}
	if d.has("rarity"):
		r["rarity"] = clampi(int(d["rarity"]), 1, 5)
	else:
		r["fibre"] = str(d["fibre"])
	Game.set_flag("request", r)
	main._say(v, str(d.get("ask", "Could you knit me something special?")))
	_show_goal()
	main.hud.show_toast("New request: %s for %s.  (%dc)" % [_what(r), v.title, int(d.get("pay", 200))])


## What a request asks for, in words: "a fox fluff sweater", "a Rare sweater or better".
func _what(r: Dictionary) -> String:
	if r.has("rarity"):
		return "a %s sweater or better" % RARITY[clampi(int(r["rarity"]), 1, 5) - 1]
	return "a %s sweater" % _fibre_name(str(r["fibre"])).to_lower()


## What handing it over pays: the price agreed, and a tenth more for each grade above what the
## fibre alone gives.
func payout() -> int:
	var r := request()
	if r.is_empty():
		return 0
	var least := int(r["rarity"]) if r.has("rarity") else int(main.wildlife.knit_floor(str(r["fibre"])))
	var extra := maxi(0, _made(r) - least)
	return int(round(int(r["pay"]) * (1.0 + 0.1 * extra)))


## Called when a sweater is knitted with `fibre`: if that's the one asked for, it is taken out of
## her bag and put by for them. True if it was.
func knitted(fibre: String, rarity: int) -> bool:
	var r := request()
	if r.is_empty() or r.has("rarity") or str(r.get("fibre", "")) != fibre or int(r.get("made", 0)) > 0 or Game.sweaters.is_empty():
		return false
	var sw: Dictionary = Game.remove_sweater(Game.sweaters.size() - 1)
	r = r.duplicate()
	r["made"] = clampi(rarity, 1, 5)
	r["design"] = str(sw.get("design", ""))
	Game.set_flag("request", r)
	_show_goal()
	return true


## She hands it over: the coins, their thanks, and they put it on.
func give(v) -> bool:
	var r := request()
	if r.is_empty() or str(r.get("who", "")) != v.vid or _made(r) <= 0:
		return false
	var coins := payout()
	var design := str(r.get("design", ""))
	if r.has("rarity"): # the plainest sweater in her bag that will do
		design = str(Game.remove_sweater(sweater_for(int(r["rarity"]))).get("design", ""))
	Game.coins += coins
	EmpireGoals.took("request", coins)
	if Sweaters.fits(v.vid) and not Sweaters.design(design).is_empty():
		var worn: Dictionary = (Game.flag("npc_sweaters", {}) as Dictionary).duplicate()
		worn[v.vid] = design
		Game.set_flag("npc_sweaters", worn)
	Game.add_friendship(v.vid, 20)
	Game.add_need("happiness", 12.0)
	var d: Dictionary = {}
	for e in request_defs():
		if str(e.get("id", "")) == str(r.get("id", "")):
			d = e
		elif not r.has("id") and str(e.get("who", "")) == str(r.get("who", "")) and str(e.get("fibre", "")) == str(r.get("fibre", "-")):
			d = e # taken before requests had ids
	var done := filled().duplicate()
	done.append(str(d.get("id", r.get("id", ""))))
	Game.set_flag("requests_filled", done)
	Game.flags.erase("request")
	Game.set_flag("requests_done", requests_done() + 1)
	Game.set_flag("request_day", Game.day + int(_req.get("every_days", 2)))
	main.set_goal("")
	main._say(v, str(d.get("thanks", "It's perfect. Thank you!")))
	main.hud.show_toast("%s paid %dc for %s." % [v.title, coins, _what(r).replace(" or better", "")])
	main.story.trigger("event", "request_done")
	return true


## The goal line for the request she has: find the animal, or take them the sweater.
func _show_goal() -> void:
	var r := request()
	if r.is_empty():
		return
	var v = main._villager(str(r["who"]))
	var who: String = v.title if v else str(r["who"]).capitalize()
	if _made(r) > 0:
		main.set_goal("Take %s %s" % [who, _what(r).replace(" or better", "")], Vector2(v.position.x, v.position.z) if v else null)
	elif r.has("rarity"):
		main.set_goal("Knit %s %s" % [who, _what(r)])
	else:
		main.set_goal("Find a %s and knit %s a sweater with its %s" % [_animal_of(str(r["fibre"])), who, _fibre_name(str(r["fibre"])).to_lower()])
