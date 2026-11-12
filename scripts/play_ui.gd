extends CanvasLayer
## The farm's own panels (scripts/homestead.gd): the pen builder's bar, the crafting bench (G) and
## Gran's note. Styled with the HUD's own boxes so they sit with the rest of it.

var home # the Homestead
var _bar: PanelContainer # bottom centre while the pen builder is on
var _bar_text: Label
var _fence_btn: Button
var _gate_btn: Button
var _craft: PanelContainer
var _craft_list: VBoxContainer
var _note: PanelContainer
var _note_text: RichTextLabel
var _hints: HBoxContainer # the builder and crafting buttons, bottom right


func _ready() -> void:
	layer = 11 # just over the HUD
	var hud = home.main.hud
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# the pen builder's bar
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", hud._sb(hud.BG, 12, hud.BORDER, 12.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bar.add_child(row)
	_bar_text = hud._label("", 15)
	row.add_child(_bar_text)
	_fence_btn = hud._button("Fence", func(): _pick("fence"))
	_gate_btn = hud._button("Gate", func(): _pick("gate"))
	row.add_child(_fence_btn)
	row.add_child(_gate_btn)
	row.add_child(hud._button("Done (F)", func(): home.set_builder(false)))
	root.add_child(_bar)
	hud._place(_bar, 0.5, 1.0, Vector2(0, 132))
	_bar.visible = false

	# the crafting bench
	_craft = PanelContainer.new()
	_craft.add_theme_stylebox_override("panel", hud._sb(hud.BG, 14, hud.BORDER, 16.0))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_craft.add_child(cv)
	cv.add_child(hud._label("Crafting", 20, hud.GOLD))
	_craft_list = VBoxContainer.new()
	_craft_list.add_theme_constant_override("separation", 8)
	cv.add_child(_craft_list)
	cv.add_child(hud._button("Close (G)", func(): _craft.visible = false))
	root.add_child(_craft)
	hud._place(_craft, 0.5, 0.5, Vector2.ZERO)
	_craft.custom_minimum_size = Vector2(360, 0)
	_craft.visible = false

	# Gran's note: cream paper, dark ink
	_note = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.96, 0.92, 0.82)
	paper.border_color = Color(0.72, 0.6, 0.42)
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(6)
	paper.set_content_margin_all(26)
	paper.shadow_color = Color(0, 0, 0, 0.35)
	paper.shadow_size = 12
	_note.add_theme_stylebox_override("panel", paper)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 14)
	_note.add_child(nv)
	_note_text = RichTextLabel.new()
	_note_text.fit_content = true
	_note_text.scroll_active = false
	_note_text.custom_minimum_size = Vector2(520, 0)
	_note_text.add_theme_color_override("default_color", Color(0.24, 0.17, 0.12))
	_note_text.add_theme_font_size_override("normal_font_size", 16)
	nv.add_child(_note_text)
	var close: Button = hud._button("Fold it away", func(): _note.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	nv.add_child(close)
	root.add_child(_note)
	hud._place(_note, 0.5, 0.5, Vector2.ZERO)
	_note.visible = false

	# reminders, bottom right, once there's something to build or craft
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 8)
	root.add_child(_hints)
	hud._place(_hints, 1.0, 1.0, Vector2(16, 132))
	refresh()


func _pick(kind: String) -> void:
	if kind == "gate" and Game.count("gate") == 0:
		home.main.hud.show_toast("No gate yet. Craft one (G): it takes 2 wood.")
		return
	home.tool = kind
	refresh()


func toggle_craft() -> void:
	_craft.visible = not _craft.visible
	if _craft.visible:
		refresh()


func show_note(text: String) -> void:
	_note_text.text = text
	_note.visible = true
	if home.main.audio:
		home.main.audio.play("journal", -8.0)


func is_open() -> bool:
	return _craft.visible or _note.visible


func close_all() -> void:
	_craft.visible = false
	_note.visible = false


func refresh() -> void:
	if _bar == null:
		return
	var hud = home.main.hud
	_bar.visible = home.building
	_bar_text.text = "Wood: %d   Gates: %d   (T switches)" % [Game.count("wood"), Game.count("gate")]
	_fence_btn.modulate = Color.WHITE if home.tool == "fence" else Color(1, 1, 1, 0.55)
	_gate_btn.modulate = Color.WHITE if home.tool == "gate" else Color(1, 1, 1, 0.55)
	for c in _craft_list.get_children():
		c.queue_free()
	for r in home.recipes():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var parts := []
		var needs: Dictionary = r.get("needs", {})
		for id in needs:
			parts.append("%d %s (have %d)" % [int(needs[id]), str(id), Game.count(str(id))])
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(str(r.get("name", r["id"])), 16, hud.TEXT))
		info.add_child(hud._label(", ".join(parts), 13, Color(hud.TEXT, 0.7)))
		line.add_child(info)
		var rid := str(r["id"])
		var b: Button = hud._button("Craft", func(): home.craft(rid))
		b.disabled = not home.can_craft(r)
		line.add_child(b)
		_craft_list.add_child(line)
	for c in _hints.get_children():
		c.queue_free()
	if home.story_farm() and not home.main.story.is_playing():
		if Game.flag("act1_wood") == true and not home.building:
			_hints.add_child(hud._button("Build pen (F)", func(): home.set_builder(true)))
		if Game.count("wood") > 0 or Game.count("gate") > 0:
			_hints.add_child(hud._button("Craft (G)", func(): toggle_craft()))
