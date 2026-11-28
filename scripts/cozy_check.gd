extends RefCounted
## --only=cozy: the thirty small furnishings of 2026-11-28 (art/world_assets/cozy_decor; Alex: "Small,
## cute things like different kinds of lamps, different kinds of lounging chairs ... Everything should
## be able to have a different color if they choose it. Maybe like three or four color options").
## Each is its model with a catalogue picture; every material its "colors" names is on the model; it
## comes in 3 or 4 colours and set_color() tints exactly those parts (and puts them back); the lamps
## carry their light and the candelabra its three candles. Then, with the house cleared, Build mode
## finds each a spot in groups, and each group is pictured as built, recoloured, and the lamps at night.
## Saves 84_cozy_<n>.png, 84_cozy_<n>_recolor.png, 84_cozy_lamps_night.png and 84_cozy_catalog.png.

const Catalog = preload("res://scripts/catalog.gd")
const Furniture = preload("res://scripts/furniture.gd")

const IDS := ["mushroom_lamp", "paper_lantern_lamp", "tripod_lamp", "arc_lamp", "pleated_lamp", "tulip_lamp",
	"chaise_longue", "papasan_chair", "wingback_chair", "egg_chair", "scallop_chair", "floor_lounger",
	"knit_pouf", "cushion_pile", "bunny_stool", "rug_scallop", "rug_checker", "rug_arch",
	"floor_vase", "cactus_trio", "fiddle_fig", "plant_stand", "wall_clock", "wall_shelf", "rainbow_print",
	"arch_mirror", "basket_trio", "candle_stand", "mushroom_table", "pedestal_table"]
const GROUP := 8


## The surfaces of f whose material is one of its "colors" parts: [[MeshInstance3D, surface, name]].
static func part_surfaces(f: Node) -> Array:
	var parts: Array = Catalog.ITEMS.get(f.item_id, {}).get("colors", {}).get("parts", [])
	var out := []
	for m in f.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i)
			if base != null and parts.has(base.resource_name):
				out.append([mi, i, base.resource_name])
	return out


func run(m: Node) -> void:
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	var bad_model := []
	var bad_parts := []
	var bad_palette := []
	var bad_tint := []
	var bad_light := []
	for id in IDS:
		if not Catalog.ITEMS.has(id):
			bad_model.append(id + " (not in the catalogue)")
			continue
		var f = Furniture.new()
		m.add_child(f)
		f.setup(id, 0)
		if f.find_children("model", "MeshInstance3D", true, false).size() != 1:
			bad_model.append(id)
		var parts: Array = Catalog.ITEMS[id].get("colors", {}).get("parts", [])
		var found := {}
		for s in part_surfaces(f):
			found[s[2]] = true
		if parts.is_empty() or found.size() != parts.size():
			bad_parts.append("%s %s of %s" % [id, str(found.keys()), str(parts)])
		var opts: Array = f.colors()
		if opts.size() < 3 or opts.size() > 4:
			bad_palette.append("%s (%d)" % [id, opts.size()])
		if not opts.is_empty():
			var c: Dictionary = opts[0]
			f.set_color(str(c["id"]))
			var tint := Color.html(str(c["color"]))
			var tinted := true
			for s in part_surfaces(f):
				var o = (s[0] as MeshInstance3D).get_surface_override_material(s[1])
				tinted = tinted and o is BaseMaterial3D and (o as BaseMaterial3D).albedo_color.is_equal_approx(tint)
			f.set_color("")
			for s in part_surfaces(f):
				tinted = tinted and (s[0] as MeshInstance3D).get_surface_override_material(s[1]) == null
			if not tinted or f.color != "":
				bad_tint.append(id)
		var want_lights := 1 if Catalog.ITEMS[id].has("light") else 0
		var own: Array = f.lights.filter(func(l): return not l.has_meta("candle"))
		var candles: int = f.lights.size() - own.size()
		if own.size() != want_lights or candles != Catalog.ITEMS[id].get("candles", []).size():
			bad_light.append("%s (%d lights, %d candles)" % [id, own.size(), candles])
		f.queue_free()
	m._check("the cozy furnishings are their models (%d of %d; wrong: %s)" % [IDS.size() - bad_model.size(), IDS.size(), str(bad_model)], bad_model.is_empty())
	m._check("each names the parts it recolours and the model has them (wrong: %s)" % str(bad_parts), bad_parts.is_empty())
	m._check("each comes in 3 or 4 colours (wrong: %s)" % str(bad_palette), bad_palette.is_empty())
	m._check("a colour tints exactly those parts and her own colour puts them back (wrong: %s)" % str(bad_tint), bad_tint.is_empty())
	m._check("the lamps carry their light and the candelabra its candles (wrong: %s)" % str(bad_light), bad_light.is_empty())
	# --- the catalogue pictures
	var t := 0.0
	while IDS.any(func(id): return not m.hud.thumbs.done.has(id)) and t < 90.0:
		await m._wait(0.5)
		t += 0.5
	var missing: Array = IDS.filter(func(id): return not m.hud.thumbs.done.has(id))
	m._check("each has its catalogue picture (missing: %s)" % str(missing), missing.is_empty())
	m.set_mode(m.Mode.BUILD)
	await m._wait(0.6)
	for tab in m.hud.catalog_panel.find_children("*", "Button", true, false):
		if (tab as Button).text == "Living":
			(tab as Button).button_pressed = true
			(tab as Button).pressed.emit()
	var card = m.hud.item_buttons.get("mushroom_lamp")
	var sc = card.get_parent() if card != null else null
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(card)
	await m._wait(0.6)
	await m._shot("84_cozy_catalog.png")
	m.set_mode(m.Mode.LIVE)
	# --- set out in her house a group at a time, as built and recoloured
	var ir: Rect2 = m.interior_rect()
	m.player.position = Vector3(ir.end.x - 0.4, 0, ir.end.y - 0.4)
	Game.hour = 11.0
	m._set_cam_lock(false)
	var placed_all := []
	var groups := []
	for g in range(0, IDS.size(), GROUP):
		groups.append(IDS.slice(g, g + GROUP))
	for gi in groups.size():
		for f in m.furniture.duplicate():
			if ir.grow(0.3).has_point(Vector2(f.position.x, f.position.z)):
				m.furniture.erase(f)
				f.queue_free()
		await m._wait(0.2)
		var placed := []
		for id in groups[gi]:
			var probe = Furniture.new()
			m.add_child(probe)
			probe.setup(id, 0)
			var spot = null
			var z := ir.position.y
			while spot == null and z < ir.end.y:
				var x := ir.position.x
				while x < ir.end.x:
					var p := Vector3(x + probe.size_rotated().x * 0.5, 0, z + probe.size_rotated().y * 0.5)
					if m._placement_valid(probe, p):
						spot = p
						break
					x += 0.25
				z += 0.25
			probe.queue_free()
			if spot != null:
				placed.append(m._spawn_furniture(id, spot, 0))
		placed_all += placed.map(func(f): return f.item_id)
		m._rebuild_grid()
		m.cam_target = Vector3(ir.get_center().x, 0.6, ir.position.y + 1.6) # the back wall, where they stand
		m.cam_dist = 8.5
		await m._wait(1.6)
		await m._shot("84_cozy_%d.png" % gi)
		for f in placed:
			var opts: Array = f.colors()
			if opts.size() > 1: # the palette's last colour: never the one it's built in
				f.set_color(str(opts[-1]["id"]))
		await m._wait(0.8)
		await m._shot("84_cozy_%d_recolor.png" % gi)
		if gi == 0: # the lamps after dark
			Game.hour = 22.0
			await m._wait(2.0)
			await m._shot("84_cozy_lamps_night.png")
			Game.hour = 11.0
	m._check("Build mode finds a spot in her house for each, %d at a time (%d of %d; missing %s)" % [GROUP, placed_all.size(), IDS.size(), str(IDS.filter(func(id): return not placed_all.has(id)))],
		placed_all.size() == IDS.size())
	m._set_cam_lock(true)
