extends Node
## Build & Buy with the world editor's reach (Alex, 2026-11-24: "I essentially want the build mode to
## be near-identical to our 'god mode' but everything just has a coin price. A tulip would be one coin
## for example or repaving the ground would be a set amount of coin per square meter. The exception is
## the player can't edit the main town or suburban area (except for their house if they buy one
## there)." Then: "keep the current UX of build mode, I more mean I want the amount of purchaseable
## things to edit to be the same as our god mode").
##
## Build mode keeps its own look and flow (main.gd's ghost, _pay_for, selling back for half); this
## widens what it can do to match god mode (god_mode.gd):
##   - The catalogue holds everything god mode's Place list holds. register() reads that list once at
##     launch (after the layout, before the HUD and the save): a catalogue piece stays itself, and every
##     other option (each scenery kind, each other model in assets/props, a "(small)" option) becomes a
##     catalogue entry of its own, "w_<kind>", with "world": true, priced from data/economy.json
##     "build_prices" and put in the Garden & Nature or Farm tab. The shops' own fittings (no shop in
##     furniture.json) go in Shop & Town. These are ordinary Furniture once placed, kept in her save.
##     What's no use as a purchase ("build_prices" "exclude": buildings, the bus, the dog, crops, tools
##     and the lantern as props, signs, the stalls...) isn't listed, and a model in twice is listed once
##     ("prefer_scenery"; Alex, 2026-11-24: "take out things that don't make sense").
##   - The town pieces ("build_prices" "town": the buildings, the barn, the bus, the signs, the stalls,
##     the post box; Alex, 2026-11-24: "anything town related we can have unlock when they purchase a
##     plot of land") are entries too, kept out of the catalogue's lists (Catalog.TOWN) until
##     town_open(): Act 2 or later (Game.unlocked("town")) and a large plot of hers ("building" "plots"
##     "large"). Then they're listed, in the HUD's Town tab, with a toast the first time
##     (Game.flags["town_pieces_open"]); they go down only on her large plots (town_ok()), and are set
##     dressing for now (no walking in, no shop, no post).
##   - Undo (Ctrl/Cmd+Z, the Paint row's Undo): her last UNDO_MAX strokes, placements, moves and
##     removals, each put back exactly with its coins. In memory only: not saved.
##   - Painting the ground with god mode's road surfaces, paid per square metre that changes
##     (paint_begin/hover/end). It uses god mode's own brush (_dab) on its road map, but none of its
##     undo, layout or "unsaved" state: what she paints is a layer of her own (an RGBA image over the
##     map, Game.flags["ground_paint"]), laid over the layout's map after a load, and taken off again
##     while god mode is open (suspend/resume), so the layout file never gets it.
##   - Taking the world's own scenery up (trees, rocks, bushes, flowers, tufts, in her area): it's gone
##     for good (Game.flags["cleared"], which forage.apply() hides like a felled tree, never El.deleted),
##     and she holds a copy of it to set down elsewhere for nothing ("w" on the piece: worth nothing
##     when taken up again), or removes it (Delete) for nothing.
## Where: house_builder.gd can_edit_at() is the one rule, for all of it.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const Nature = preload("res://scripts/nature.gd")
const GodMode = preload("res://scripts/god_mode.gd")
const Forage = preload("res://scripts/forage.gd")

const BRUSH := 1.0 # metres: the ground brush's radius
const NATURE_TAB := "Garden & Nature"
const OUTDOOR_TAB := "Farm" # what isn't nature (the fence parts) goes in with the pen's fence
const SHOP_TAB := "Shop & Town"
const NATURAL := ["tree_", "rock_", "bush_", "tuft_", "flowers_", "clover", "leaf_", "maple_", "hedge", "arborvitae", "red_shrub"]
const FLAT := ["tuft_", "flowers_", "clover", "leaf_", "crop_"] # nothing walks round these

static var _econ := {}

var main # main.gd
var options: Dictionary = {} # god mode's Place option id -> the catalogue id that buys it
var ground_kind := "gravel"
var layer: Image # her ground paint: RGBA8 over the road map, alpha 1 where she painted
var under: Image # the road map under her paint (the layout's, and god mode's edits)
var last_cost := 0 # what the last stroke cost (the check reads it)
var last_refusal := ""
var excluded: Dictionary = {} # god mode's Place option id -> the "exclude" pattern that keeps it out of Build & Buy
var hidden: Dictionary = {} # a catalogue id left out as a second copy of a model -> the one listed instead
var town: Dictionary = {} # god mode's Place option id -> the town piece's catalogue id (also in Catalog.TOWN)
var town_listed := false # whether the town pieces are in the catalogue's lists now (sync_town())
var _town_t := 0.0
var undo_stack: Array = [] # her last few strokes, placements, moves and removals in Build & Buy (undo())
const UNDO_MAX := 10
var _painting := false
var _before: Image
var _rect := Rect2()
var _last := Vector3.ZERO


static func econ() -> Dictionary:
	if _econ.is_empty():
		_econ = Data.economy().get("build_prices", {})
	return _econ


## Coins a square metre of ground painted with `kind` (one of GodMode.ROADS).
static func ground_price(kind: String) -> int:
	return int((econ().get("ground", {}) as Dictionary).get(kind, 2))


static func ground_label(kind: String) -> String:
	for r in GodMode.ROADS:
		if r[0] == kind:
			return "%s (%dc/m²)" % [r[1], ground_price(kind)]
	return kind


## The model a scenery kind draws ("swamp-rock_cluster" draws rock_cluster).
static func model_of(kind: String) -> String:
	return kind.get_slice("-", kind.get_slice_count("-") - 1)


static func price_for(model: String) -> int:
	for p in econ().get("prefixes", []):
		if model.begins_with(str(p[0])):
			return int(p[1])
	return int(econ().get("default", 25))


# --- the catalogue ----------------------------------------------------------------------------

## Whether a Build & Buy id (a "w_" option or a catalogue id) is one "build_prices" "exclude" leaves
## out of the catalogue: the pattern that matched, or "".
static func exclude_pattern(id: String) -> String:
	for p in econ().get("exclude", []):
		var pat := str(p)
		if (pat.ends_with("*") and id.begins_with(pat.trim_suffix("*"))) or id == pat:
			return pat
	return ""


## Whether a Build & Buy id is one of the town pieces ("build_prices" "town"): the pattern, or "".
static func town_pattern(id: String) -> String:
	for p in econ().get("town", []):
		var pat := str(p)
		if (pat.ends_with("*") and id.begins_with(pat.trim_suffix("*"))) or id == pat:
			return pat
	return ""


## Makes a catalogue entry for every option on god mode's Place list that isn't one already. Those
## "exclude" names stay out of the catalogue (an entry is still made, so a save that has one keeps it
## and the world's scenery of that kind can still be taken up), and a model listed twice is listed once.
func register() -> void:
	var shop_prices: Dictionary = econ().get("shop_pieces", {})
	for o in main.god.place_options():
		var pid := str(o[0])
		var what := pid.get_slice(":", 1)
		if pid.begins_with("decor:"):
			if not Catalog.ITEMS.has(what):
				continue
			if town_pattern(what) != "":
				var ti: Dictionary = Catalog.ITEMS[what]
				ti["cat"] = Catalog.TOWN_CAT
				ti["town"] = true
				if int(ti.get("price", 0)) <= 0: # the welcome sign has none of its own
					ti["price"] = int(shop_prices.get(what, econ().get("default", 25)))
				Catalog.INDOOR.erase(what)
				Catalog.OUTDOOR.erase(what)
				_add_town(pid, what)
				continue
			var pat := exclude_pattern(what)
			if pat != "":
				excluded[pid] = pat
				Catalog.INDOOR.erase(what)
				Catalog.OUTDOOR.erase(what)
				continue
			options[pid] = what
			if not (what in Catalog.INDOOR or what in Catalog.OUTDOOR):
				# a shop's or the café's own fitting: in the catalogue too, at a draft price if it had none
				var info: Dictionary = Catalog.ITEMS[what]
				info["cat"] = SHOP_TAB
				if int(info.get("price", 0)) <= 0:
					info["price"] = int(shop_prices.get(what, econ().get("default", 25)))
				(Catalog.INDOOR if str(info.get("where", "")) == "in" else Catalog.OUTDOOR).append(what)
			continue
		var model := model_of(what)
		var path: String = Nature.P + model + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var small := pid.get_slice_count(":") > 2
		var id := "w_" + what + ("_small" if small else "")
		var natural := GodMode._starts(model, NATURAL)
		var land := what.get_slice("-", 0) if what.contains("-") else ""
		var nm := str(o[1])
		if land != "":
			nm = "%s (%s)" % [GodMode.TITLES.get(model, model.capitalize()), land.capitalize()]
		var price := price_for(model)
		var e := {"id": id, "name": nm, "price": maxi(1, roundi(price * (float(econ().get("small", 0.5)) if small else 1.0))),
			"size": Vector2.ONE, "height": 1.0, "where": "out", "shop": "yard", "cat": NATURE_TAB if natural else OUTDOOR_TAB,
			"model": path, "world": true, "kind": what, "measure": true}
		if small:
			e["scale"] = float(pid.get_slice(":", 2))
		if GodMode._starts(model, FLAT):
			e["flat"] = true
		if model.begins_with("tree_") or model.begins_with("maple_"):
			e["trunk"] = true
		Catalog.ITEMS[id] = e
		if town_pattern(id) != "":
			if small: # a building at half size is no use to a town
				excluded[pid] = town_pattern(id)
				continue
			e["cat"] = Catalog.TOWN_CAT
			e["town"] = true
			if model.begins_with("building_") or model == "barn":
				e["shell"] = true # Catalog.build hides the walk-in models' low walls: set dressing, not walked into
			_add_town(pid, id)
			continue
		var pat := exclude_pattern(id)
		if pat != "":
			excluded[pid] = pat
			continue
		Catalog.OUTDOOR.append(id)
		options[pid] = id
	_dedupe()


## One town piece: listed once per model (Catalog.TOWN), the first option that draws it.
func _add_town(pid: String, id: String) -> void:
	for t in Catalog.TOWN:
		if t != id and _draws(t) == _draws(id):
			hidden[id] = t
			town[pid] = t
			return
	town[pid] = id
	if not Catalog.TOWN.has(id):
		Catalog.TOWN.append(id)


# --- the town pieces --------------------------------------------------------------------------

## Whether the town pieces are hers to buy: Act 2 or later, and a large plot of hers.
func town_open() -> bool:
	return Game.unlocked("town") and main.builder != null and main.builder.owns_large()


## Lists the town pieces in the catalogue (and its Town tab) when town_open() says so, and takes them
## out again when it doesn't (a load of an earlier save). The first time they come, a toast says so.
func sync_town() -> void:
	var want := town_open()
	if want != town_listed:
		town_listed = want
		for id in Catalog.TOWN:
			var lst: Array = Catalog.INDOOR if str(Catalog.ITEMS[id].get("where", "")) == "in" else Catalog.OUTDOOR
			if want and not lst.has(id):
				lst.append(id)
			elif not want:
				lst.erase(id)
		if main.hud != null and main.hud.has_method("show_town_tab"):
			main.hud.show_town_tab(want)
	if want and Game.flag("town_pieces_open") != true:
		Game.set_flag("town_pieces_open")
		if main.hud != null:
			main.hud.show_toast("Town pieces are in Build & Buy now (B), in the Town tab: buildings, signs, stalls and a post box for your large plot.")


func _process(delta: float) -> void:
	_town_t -= delta
	if _town_t <= 0.0: # the act, her plots and a load all change it: a cheap look twice a second
		_town_t = 0.5
		sync_town()


## A town piece's footprint: all of it on a large plot of hers, and clear as any piece out there.
func town_ok(r: Rect2, flat: bool) -> bool:
	if not town_listed:
		return false
	var b = main.builder
	var on := false
	for id in b.owned():
		var p: Dictionary = b.plot_def(str(id))
		if p.get("large", false) == true and b.plot_rect(p).encloses(r):
			on = true
	return on and outdoor_ok(r, flat)


## Why a town piece can't go here ("" if it can, or it isn't one).
func town_why(f, at: Vector3) -> String:
	if f == null or f.info().get("town", false) != true:
		return ""
	if not town_listed:
		return "Town pieces come with a large plot of land, from Act 2."
	var why: String = main.builder.can_edit_at(at)
	if why != "":
		return why
	return "Town pieces go on a large plot of yours, all of them inside it." if main.builder.large_plot_at(Vector2(at.x, at.z)) == "" else "Not there: keep it clear of trees, walls and the edge of your plot."


## The model (and size) a catalogue piece draws, so two entries for one thing can be told apart.
static func _draws(id: String) -> String:
	var info: Dictionary = Catalog.ITEMS.get(id, {})
	return "%s@%.2f" % [str(info.get("model", id)).get_file().get_basename(), float(info.get("scale", 1.0))]


## One model listed twice (a catalogue piece and the world editor's option, or a land's own copy of a
## kind): "prefer_scenery" models keep the world editor's own option (the plain kind, not a land's),
## anything else keeps the catalogue piece. The other is left out of the catalogue's lists, its entry
## kept (taking a land's rock up still hands her a copy of it).
func _dedupe() -> void:
	var groups := {}
	for id in Catalog.INDOOR + Catalog.OUTDOOR:
		var k := _draws(str(id))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(str(id))
	for k in groups:
		var ids: Array = groups[k]
		if ids.size() < 2:
			continue
		var scenery := GodMode._starts(str(k).get_slice("@", 0), econ().get("prefer_scenery", []))
		var rank := func(id: String) -> int:
			var world: bool = Catalog.ITEMS[id].get("world", false) == true
			var land: bool = world and str(Catalog.ITEMS[id].get("kind", "")).contains("-")
			if scenery:
				return 0 if world and not land else (1 if not world else 2)
			return 0 if not world else (1 if not land else 2)
		ids.sort_custom(func(a, b): return rank.call(a) < rank.call(b) or (rank.call(a) == rank.call(b) and a < b))
		var keep: String = ids[0]
		for i in range(1, ids.size()):
			var id: String = ids[i]
			hidden[id] = keep
			Catalog.INDOOR.erase(id)
			Catalog.OUTDOOR.erase(id)
	for pid in options.keys():
		if hidden.has(options[pid]):
			options[pid] = hidden[options[pid]]


## The catalogue piece a piece of the world's scenery is a copy of ("" if none).
func item_for(kind: String) -> String:
	var id := "w_" + kind
	return id if Catalog.ITEMS.has(id) else ""


## What taking a piece of hers back up gives: half its price, or nothing for a copy of the world's own.
func sell_value(f) -> int:
	if f.has_meta("w"):
		return 0
	return int(Catalog.ITEMS[f.item_id]["price"]) / 2


## A piece outside her farm's lot: in her area, clear of the town's buildings, trees and pools.
func outdoor_ok(r: Rect2, flat: bool) -> bool:
	var b = main.builder
	for p in [r.get_center(), r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
		if b.can_edit_at(Vector3(p.x, 0, p.y)) != "":
			return false
	if b.blocks(r.grow(0.25)):
		return false
	var c := r.get_center()
	if not main._walkable(main._cell(Vector3(c.x, 0, c.y))):
		return false
	if not flat:
		for p in [r.position, r.end]:
			if not main._walkable(main._cell(Vector3(p.x, 0, p.y))):
				return false
	return true


# --- the world's own scenery ------------------------------------------------------------------

## The world's scenery under the pointer that she could take up (or null): trees, rocks, plants.
func world_at(mpos: Vector2):
	var god = main.god
	var from: Vector3 = main.cam.project_ray_origin(mpos)
	var dir: Vector3 = main.cam.project_ray_normal(mpos)
	var best = null
	var best_t := INF
	for el in god.els:
		if not el.scenery or el.deleted or el.cut or item_for(el.kind) == "":
			continue
		var to_c: Vector3 = el.xf * el.bounds.get_center() - from
		var along := to_c.dot(dir)
		if along < 0.0 or (to_c - dir * along).length_squared() > el.radius * el.radius:
			continue
		var inv: Transform3D = el.xf.affine_inverse()
		var hit: Dictionary = god._triangles(el).intersect_segment(inv * from, inv * (from + dir * 400.0))
		if hit.is_empty():
			continue
		var t: float = (el.xf * (hit["position"] as Vector3) - from).dot(dir)
		if t < best_t:
			best_t = t
			best = el
	return best


## Takes a piece of the world's scenery up for good (until she puts it back with unclear()).
func clear(el) -> void:
	var c: Dictionary = (Game.flag("cleared", {}) as Dictionary).duplicate()
	c[Forage.key_of(el)] = Game.day
	Game.set_flag("cleared", c)
	main.forage._set_cut(el, true)
	main._rebuild_grid()


func unclear(key: String) -> void:
	var c: Dictionary = (Game.flag("cleared", {}) as Dictionary).duplicate()
	c.erase(key)
	Game.set_flag("cleared", c)
	main.forage.apply()
	main._rebuild_grid()


# --- painting the ground ----------------------------------------------------------------------

func paint_off() -> void:
	paint_end()
	main.ghost_marker.visible = false


func _why_not(p: Vector3) -> String:
	for off in [Vector3.ZERO, Vector3(BRUSH, 0, 0), Vector3(-BRUSH, 0, 0), Vector3(0, 0, BRUSH), Vector3(0, 0, -BRUSH)]:
		var why: String = main.builder.can_edit_at(p + off)
		if why != "":
			return why
	return ""


func paint_hover(g: Variant) -> void:
	if g == null:
		return
	var p := g as Vector3
	var why := _why_not(p)
	main.ghost_marker.visible = true
	main.ghost_marker.position = p + Vector3(0, 0.05, 0)
	main.ghost_marker.scale = Vector3(BRUSH * 2.0, 1, BRUSH * 2.0)
	main.ghost_marker.material_override = main._mark_ok if why == "" else main._mark_bad
	main.hud.set_wall_note(why if why != "" else "Drag to paint %s. %dc a square metre, only where it changes." % [ground_label(ground_kind).get_slice(" (", 0).to_lower(), ground_price(ground_kind)])
	if _painting:
		_stroke_to(p)


func paint_begin(g: Variant) -> void:
	if g == null:
		return
	var p := g as Vector3
	last_refusal = _why_not(p)
	if last_refusal != "":
		main.hud.show_toast(last_refusal)
		return
	if Game.coins < ground_price(ground_kind):
		last_refusal = "Not enough coins: %s." % ground_label(ground_kind)
		main.hud.show_toast(last_refusal)
		return
	var god = main.god
	if not god.roads_on:
		god._enable_roads(true)
	_ensure_layer()
	_painting = true
	_before = god.road_img.duplicate() as Image
	_rect = Rect2()
	_last = p
	_dab(p)


func _ensure_layer() -> void:
	var img: Image = main.god.road_img
	if layer == null:
		layer = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	if under == null:
		under = img.duplicate() as Image


## One dab of god mode's own brush, on the road map, with its state put back after.
func _dab(p: Vector3) -> void:
	var why := _why_not(p)
	if why != "":
		last_refusal = why
		return
	var god = main.god
	var was := [god.tool, god.brush, god.brush_square, god._stroke_rect]
	god.tool = ground_kind
	god.brush = BRUSH
	god.brush_square = false
	god._stroke_rect = Rect2()
	god._dab(p)
	var t: Rect2 = god._stroke_rect
	god.tool = was[0]
	god.brush = was[1]
	god.brush_square = was[2]
	god._stroke_rect = was[3]
	_rect = t if _rect.size == Vector2.ZERO else _rect.merge(t)
	god.road_tex.update(god.road_img)


func _stroke_to(p: Vector3) -> void:
	var step := BRUSH * 0.35
	var dist := _last.distance_to(p)
	if dist < step:
		return
	var n := ceili(dist / step)
	var from := _last
	for i in range(1, n + 1):
		_dab(from.lerp(p, float(i) / n))
	_last = p


## The stroke is done: what changed is paid for (or it all comes off again if she can't pay), and
## goes into her layer.
func paint_end() -> void:
	if not _painting:
		return
	_painting = false
	var god = main.god
	last_cost = 0
	if _rect.size == Vector2.ZERO:
		_before = null
		return
	var px: Rect2i = god._px_in(_rect.grow(0.2))
	var img: Image = god.road_img
	var changed: Array[Vector2i] = []
	for y in range(px.position.y, px.end.y):
		for x in range(px.position.x, px.end.x):
			if img.get_pixel(x, y) != _before.get_pixel(x, y):
				changed.append(Vector2i(x, y))
	var per := float(GodMode.ROAD_PX * GodMode.ROAD_PX)
	var cost := ceili(changed.size() / per * ground_price(ground_kind) - 0.0001) if not changed.is_empty() else 0
	if cost > Game.coins:
		img.blit_rect(_before, px, px.position)
		god.road_tex.update(img)
		_before = null
		last_refusal = "Not enough coins: that's %dc of %s." % [cost, ground_label(ground_kind).get_slice(" (", 0).to_lower()]
		main.hud.show_toast(last_refusal)
		return
	if changed.is_empty():
		_before = null
		return
	# for undo: the map and her layer as they were where the stroke reached, and what it cost
	var rec := {"px": px, "road": _before.get_region(px), "layer": layer.get_region(px), "cost": cost, "area": _rect.grow(0.2), "cleared": []}
	_before = null
	Game.coins -= cost
	last_cost = cost
	for q in changed:
		var c := img.get_pixelv(q)
		layer.set_pixelv(q, Color(c.r, c.g, c.b, 1.0))
	_save_layer()
	_show(_rect)
	if ground_kind != "grass": # a path laid over the lawn takes the tufts and flowers there, as god mode's does
		for el in god.els:
			if el.scenery and not el.cut and not el.deleted and GodMode.SMALL.has(el.kind) and _rect.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)) \
					and god.road_at(el.xf.origin.x, el.xf.origin.z) != "":
				var cl: Dictionary = (Game.flag("cleared", {}) as Dictionary).duplicate()
				if not cl.has(Forage.key_of(el)):
					(rec["cleared"] as Array).append(Forage.key_of(el))
				cl[Forage.key_of(el)] = Game.day
				Game.set_flag("cleared", cl)
				main.forage._set_cut(el, true)
	push_undo("paint", rec)
	main.hud.show_toast("Painted %.1f m² of %s for %dc." % [changed.size() / per, ground_label(ground_kind).get_slice(" (", 0).to_lower(), cost])


## The ground, the grass and the tiles over `area`, without touching god mode's own records.
func _show(area: Rect2) -> void:
	var god = main.god
	var was: bool = god.unsaved
	god._roads_changed(area)
	god.unsaved = was


func _save_layer() -> void:
	var used := layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		Game.flags.erase("ground_paint")
		return
	Game.set_flag("ground_paint", {"px": GodMode.ROAD_PX, "at": [used.position.x, used.position.y],
		"png": Marshalls.raw_to_base64(layer.get_region(used).save_png_to_buffer())})


func _world_rect(px: Rect2i) -> Rect2:
	var o := GodMode.ROAD_RECT.position
	return Rect2(o + Vector2(px.position) / GodMode.ROAD_PX, Vector2(px.size) / GodMode.ROAD_PX)


## Lays her layer over the road map within `px`.
func _composite(px: Rect2i) -> void:
	var img: Image = main.god.road_img
	var reg := img.get_region(px)
	reg.convert(Image.FORMAT_RGBA8)
	reg.blend_rect(layer, px, Vector2i.ZERO)
	reg.convert(img.get_format())
	img.blit_rect(reg, Rect2i(Vector2i.ZERO, px.size), px.position)


## After a load (or a new game): the road map as the layout made it, then her saved layer over it.
func apply_saved() -> void:
	undo_stack.clear() # a load or a new game: nothing of before to take back (and no refunds for it)
	var god = main.god
	if under != null and god.roads_on and layer != null:
		var old := layer.get_used_rect()
		if old.size.x > 0:
			god.road_img.blit_rect(under, old, old.position)
			_show(_world_rect(old))
	layer = null
	under = null
	var d: Dictionary = Game.flag("ground_paint", {})
	if d.is_empty() or int(d.get("px", 0)) != GodMode.ROAD_PX:
		return
	var img := Image.new()
	if img.load_png_from_buffer(Marshalls.base64_to_raw(str(d.get("png", "")))) != OK:
		return
	img.convert(Image.FORMAT_RGBA8)
	if not god.roads_on:
		god._enable_roads(true)
	_ensure_layer()
	var at: Array = d.get("at", [0, 0])
	layer.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(int(at[0]), int(at[1])))
	var used := layer.get_used_rect()
	_composite(used)
	_show(_world_rect(used))


## God mode opens: the road map goes back to the layout's own, so its file never gets her paint.
func suspend() -> void:
	paint_end()
	undo_stack.clear() # god mode may change the map under her strokes: their snapshots would be stale
	if layer == null or under == null:
		return
	var used := layer.get_used_rect()
	if used.size.x > 0:
		main.god.road_img.blit_rect(under, used, used.position)
		_show(_world_rect(used))


## God mode closes (after it saved): what it left is the new map under her paint.
func resume() -> void:
	if layer == null:
		return
	under = main.god.road_img.duplicate() as Image
	var used := layer.get_used_rect()
	if used.size.x > 0:
		_composite(used)
		_show(_world_rect(used))


# --- undo -------------------------------------------------------------------------------------

## Remembers one of her changes in Build & Buy for undo(): "paint" (a ground stroke), "place" (a piece
## bought or a copy of the world's own set down), "move", "sell" (a piece taken up and sold back) or
## "remove_world" (the world's own scenery taken up and removed). Kept in memory only, the last
## UNDO_MAX of them: not in her save, and gone after a load or once god mode opens.
func push_undo(kind: String, d: Dictionary) -> void:
	d["kind"] = kind
	undo_stack.append(d)
	while undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()


## Takes back her last change in Build & Buy (Ctrl/Cmd+Z, or the Undo button in the Paint row): exactly
## what it changed, and every coin it cost (or the coins a sale gave, if she still has them).
func undo() -> void:
	paint_end()
	if main.ghost != null:
		main._cancel_ghost() # the piece in her hands goes back first
		return
	if undo_stack.is_empty():
		main.hud.show_toast("Nothing to undo.")
		return
	var u: Dictionary = undo_stack.pop_back()
	match str(u["kind"]):
		"paint":
			var god = main.god
			var px: Rect2i = u["px"]
			var road: Image = u["road"]
			god.road_img.blit_rect(road, Rect2i(Vector2i.ZERO, road.get_size()), px.position)
			if layer != null:
				var lr: Image = u["layer"]
				layer.blit_rect(lr, Rect2i(Vector2i.ZERO, lr.get_size()), px.position)
				_save_layer()
			Game.coins += int(u["cost"])
			if not (u["cleared"] as Array).is_empty():
				var cl: Dictionary = (Game.flag("cleared", {}) as Dictionary).duplicate()
				for key in u["cleared"]:
					cl.erase(key)
				Game.set_flag("cleared", cl)
				main.forage.apply()
			_show(u["area"])
			main.hud.show_toast("Undid the paint (+%dc)." % int(u["cost"]))
		"place":
			var f = _live(u)
			if f == null:
				main.hud.show_toast("That piece isn't there any more.")
				return
			main.furniture.erase(f)
			f.queue_free()
			Game.coins += int(u.get("coins", 0))
			if int(u.get("wood", 0)) > 0:
				Game.add_item("wood", int(u["wood"]))
			if u.get("given", false) == true:
				var g: Dictionary = (Game.flag("given", {}) as Dictionary).duplicate()
				g[u["id"]] = int(g.get(u["id"], 0)) + 1
				Game.set_flag("given", g)
			if str(u.get("world", "")) != "":
				unclear(str(u["world"])) # the world's own goes back where it stood
			main._rebuild_grid()
			main.hud.show_toast("Undid placing the %s." % str(Catalog.ITEMS.get(u["id"], {}).get("name", "piece")).to_lower())
		"move":
			var f = _live(u)
			if f == null:
				main.hud.show_toast("That piece isn't there any more.")
				return
			f.position = u["pos"]
			f.set_rot(int(u["rot"]))
			main._rebuild_grid()
			main.hud.show_toast("Moved the %s back." % f.display_name().to_lower())
		"sell":
			var value := int(u.get("value", 0))
			if Game.coins < value:
				undo_stack.append(u)
				main.hud.show_toast("You'd need the %dc back to undo that sale." % value)
				return
			Game.coins -= value
			main._spawn_entry(u["entry"])
			var f = main.furniture.back()
			for e in undo_stack: # earlier records of that piece now mean the new one
				if int(e.get("node_id", 0)) == int(u["node_id"]):
					e["node"] = f
					e["node_id"] = f.get_instance_id()
			main._rebuild_grid()
			main.hud.show_toast("Put the %s back." % f.display_name().to_lower())
		"remove_world":
			unclear(str(u["world"]))
			main.hud.show_toast("Put it back.")


## The piece an undo record is about, if it's still hers.
func _live(u: Dictionary):
	var f = u.get("node")
	if f == null or not is_instance_valid(f) or not main.furniture.has(f):
		return null
	return f
