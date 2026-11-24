## The Field Guide (Menu > Field Guide; Alex approved 2026-11-18): every wild animal in
## data/wildlife.json, grouped by tier in the tier's colour, each marked seen, caught and combed, with
## a count at the top. One not yet seen is a black silhouette with "???". The pictures are rendered
## once, the first time the guide opens, from the species' own models in an offscreen viewport (like
## thumbs.gd). The state is Game.flags["guide"], kept by empire_goals.gd. Every line is a DRAFT.
extends PanelContainer

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const DIM := Color(0.55, 0.5, 0.45)
const PIC := Vector2i(160, 110)

var hud: Node
var goals: Node # empire_goals.gd
var pics := {} # species -> Texture2D, once rendered
var rendering := false
var _count: Label
var _body: VBoxContainer


func setup(h: Node, g: Node) -> void:
	hud = h
	goals = g
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(hud._label("Field Guide", 24, GOLD))
	_count = hud._label("", 15)
	vb.add_child(_count)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(860, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	vb.add_child(sc)
	var close_btn: Button = hud._button("Close", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


func species() -> Dictionary:
	return Data.load_json("wildlife").get("animals", {})


func open() -> void:
	hud.click("ui_open")
	visible = true
	move_to_front()
	refresh()
	if pics.is_empty() and not rendering:
		_render()


func close() -> void:
	visible = false


func refresh() -> void:
	var data := Data.load_json("wildlife")
	var all := species()
	var n := all.size()
	_count.text = "Seen %d of %d   ·   Caught %d   ·   Combed %d" % [goals.guide_count("seen"), n, goals.guide_count("caught"), goals.guide_count("combed")]
	for c in _body.get_children():
		c.queue_free()
	var names: Dictionary = data.get("tier_names", {})
	var colours: Dictionary = data.get("tier_colors", {})
	for tier in data.get("tiers", []):
		var ids: Array = all.keys().filter(func(id): return str(all[id].get("tier", "")) == str(tier))
		if ids.is_empty():
			continue
		var col := Color.html(str(colours.get(tier, "#ffffff")))
		_body.add_child(hud._label(str(names.get(tier, tier)), 17, col))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		for id in ids:
			row.add_child(_card(str(id), all[id], col))
		_body.add_child(row)


func _card(id: String, info: Dictionary, col: Color) -> Control:
	var e: Dictionary = goals.guide_entry(id)
	var seen := e.has("seen")
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", hud._sb_flat(Color(0.12, 0.09, 0.07, 0.9), 8, col if seen else Color(col, 0.35), 8.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(PIC)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = pics.get(id)
	pic.modulate = Color.WHITE if seen else Color(0.0, 0.0, 0.0, 0.9) # a silhouette until she's seen one
	pic.name = "Pic_" + id
	vb.add_child(pic)
	var name_l: Label = hud._label(str(info.get("name", id)) if seen else "???", 15, TEXT if seen else DIM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_l)
	var marks := HBoxContainer.new()
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("separation", 8)
	for m in [["Seen", seen], ["Caught", int(e.get("caught", 0)) > 0], ["Combed", int(e.get("combed", 0)) > 0]]:
		marks.add_child(hud._label(str(m[0]), 12, GOLD if m[1] else Color(DIM, 0.6)))
	vb.add_child(marks)
	pc.add_child(vb)
	return pc


## Renders each species once, side on, in its idle pose; the cards fill in as each arrives.
func _render() -> void:
	rendering = true
	var vp := SubViewport.new()
	vp.size = PIC * 2
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.8)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	var all := species()
	for id in all:
		var holder := Node3D.new()
		vp.add_child(holder)
		var m := Catalog.model(str(all[id].get("model", "")), holder)
		if m != null:
			var ap := m.find_children("*", "AnimationPlayer", true, false)
			if not ap.is_empty():
				var p := ap[0] as AnimationPlayer
				for a in p.get_animation_list():
					if str(a).to_lower().contains("idle"):
						p.play(a)
						p.seek(0.0, true)
						p.pause()
						break
			await get_tree().process_frame
			var box := _aabb(holder)
			var c := box.get_center()
			var radius := maxf(box.size.length() * 0.5, 0.1)
			var dir := Vector3(1.0, 0.3, 0.45).normalized() # side on, a little from the front
			var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.95
			cam.near = maxf(0.01, dist - radius * 2.0)
			cam.far = dist + radius * 3.0
			cam.look_at_from_position(c + dir * dist, c)
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			pics[str(id)] = ImageTexture.create_from_image(vp.get_texture().get_image())
			var pic := find_child("Pic_" + str(id), true, false) as TextureRect
			if pic:
				pic.texture = pics[str(id)]
		holder.queue_free()
	vp.queue_free()
	rendering = false
	if visible:
		refresh()


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		if v is Light3D:
			continue
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
