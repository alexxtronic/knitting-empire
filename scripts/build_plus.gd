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
##     "build_prices" and put in the Garden & Nature or Outdoor tab. The shops' own fittings (no shop in
##     furniture.json) go in Shop & Town. These are ordinary Furniture once placed, kept in her save.
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
const OUTDOOR_TAB := "Outdoor"
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

## Makes a catalogue entry for every option on god mode's Place list that isn't one already.
func register() -> void:
	var shop_prices: Dictionary = econ().get("shop_pieces", {})
	for o in main.god.place_options():
		var pid := str(o[0])
		var what := pid.get_slice(":", 1)
		if pid.begins_with("decor:"):
			if not Catalog.ITEMS.has(what):
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
		Catalog.OUTDOOR.append(id)
		options[pid] = id


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
	_before = null
	if changed.is_empty():
		return
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
				cl[Forage.key_of(el)] = Game.day
				Game.set_flag("cleared", cl)
				main.forage._set_cut(el, true)
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
