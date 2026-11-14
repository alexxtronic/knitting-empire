## Nora's wardrobe (from the wardrobe in her house, or Menu > Wardrobe): every design she has knit,
## kept to wear (Game.wardrobe), best stars first, and her city coat. Picking one puts it on at once,
## so she changes in the room behind the panel (main.gd's _update_sweater).
extends PanelContainer

const Sweaters = preload("res://scripts/sweaters.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const TIER := ["Common", "Rare", "Ultra rare", "Legendary"]
const TIER_COLOUR := [Color(0.85, 0.82, 0.76), Color(0.55, 0.78, 1.0), Color(0.82, 0.6, 1.0), Color(1.0, 0.8, 0.35)]

var hud: Node # hud.gd, for its labels, buttons and sounds
var _list: VBoxContainer
var _wearing: Label
var _empty: Label


func setup(h: Node) -> void:
	hud = h
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(hud._label("Wardrobe", 24, GOLD))
	_wearing = hud._label("", 15, TEXT)
	vb.add_child(_wearing)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	vb.add_child(sc)
	_empty = hud._label("Nothing knitted yet. Every sweater you knit, you knit one like it for yourself, and it hangs here.", 14, Color(TEXT, 0.75))
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(440, 0)
	vb.add_child(_empty)
	var close_btn: Button = hud._button("Close", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


func open() -> void:
	hud.click("ui_open")
	visible = true
	move_to_front()
	refresh()


func close() -> void:
	visible = false


## Her wardrobe's designs, best stars first, then by name.
static func entries() -> Array:
	var out := []
	for id in Game.wardrobe:
		var d := Sweaters.design(str(id))
		if not d.is_empty():
			out.append(d)
	out.sort_custom(func(a, b): return int(a["stars"]) > int(b["stars"]) or (int(a["stars"]) == int(b["stars"]) and str(a["name"]) < str(b["name"])))
	return out


func pick(design: String) -> void:
	if Game.wear(design):
		hud.click("ui_open")
		refresh()


func refresh() -> void:
	var worn := Sweaters.design(Game.worn_design)
	_wearing.text = "Wearing: %s" % ("her thin city coat" if worn.is_empty() else "%s  %s" % [worn["name"], "★".repeat(int(worn["stars"]))])
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var es := entries()
	_empty.visible = es.is_empty()
	_list.add_child(_row("City coat", "the thin coat she came in", Color(0.6, 0.6, 0.62), Game.worn_design == "", ""))
	for d in es:
		var s := clampi(int(d["stars"]), 1, 4)
		_list.add_child(_row(str(d["name"]), "%s  %s" % ["★".repeat(s), TIER[s - 1]], Color(str(d["colours"][0])), Game.worn_design == str(d["id"]), str(d["id"]), TIER_COLOUR[s - 1], d["colours"]))


func _row(title: String, sub: String, swatch: Color, on: bool, design: String, sub_colour := Color(TEXT, 0.7), colours: Array = []) -> Control:
	var b: Button = hud._button("", pick.bind(design))
	b.custom_minimum_size = Vector2(424, 54)
	b.set_meta("design", design)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -10
	# the design's yarns, side by side
	var sw := HBoxContainer.new()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_theme_constant_override("separation", 1)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cols: Array = colours if not colours.is_empty() else [swatch.to_html(false)]
	for c in cols.slice(0, 5):
		var r := ColorRect.new()
		r.color = Color(str(c))
		r.custom_minimum_size = Vector2(36.0 / mini(cols.size(), 5) if cols.size() > 1 else 36.0, 36)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(r)
	hb.add_child(sw)
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t: Label = hud._label(title, 16, TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(t)
	var st: Label = hud._label(sub, 12, sub_colour)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(st)
	hb.add_child(tv)
	if on:
		var w: Label = hud._label("wearing", 13, GOLD)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(w)
		b.modulate = Color(1.15, 1.05, 0.8)
	b.add_child(hb)
	return b
