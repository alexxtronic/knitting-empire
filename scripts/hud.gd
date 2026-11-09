extends CanvasLayer
## All on-screen UI, built in code: resources, needs, clock, mode buttons,
## build catalog, action menu, toasts, help and the sleep fade.

signal mode_selected(build: bool)
signal expand_pressed
signal walls_pressed
signal save_pressed
signal new_game_pressed
signal item_chosen(id: String)
signal rotate_pressed
signal sell_pressed
signal cancel_pressed
signal cam_lock_pressed
signal cam_rotate(dir: int)
signal cam_zoom(dir: int)

const Catalog = preload("res://scripts/catalog.gd")


## Small vector icons drawn in code, so they never depend on a font having the glyph.
class Icon extends Control:
	var kind := ""
	var col := Color(0.97, 0.93, 0.85)

	func _init(k: String) -> void:
		kind = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func set_kind(k: String, c: Color) -> void:
		kind = k
		col = c
		queue_redraw()

	func _tri(c: Vector2, d: Vector2, r: float) -> void:
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([c + d * r, c - d * r * 0.55 + n * r * 0.85, c - d * r * 0.55 - n * r * 0.85]), col)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.27
		match kind:
			"up": _tri(c, Vector2.UP, r)
			"down": _tri(c, Vector2.DOWN, r)
			"left": _tri(c, Vector2.LEFT, r)
			"right": _tri(c, Vector2.RIGHT, r)
			"plus":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 3.0)
				draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 3.0)
			"minus":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 3.0)
			"rot_l", "rot_r":
				var cw := kind == "rot_r"
				var a0 := deg_to_rad(135.0) if cw else deg_to_rad(45.0)
				var a1 := a0 + deg_to_rad(250.0) * (1.0 if cw else -1.0)
				draw_arc(c, r * 0.9, a0, a1, 28, col, 2.5, true)
				var p := c + Vector2(cos(a1), sin(a1)) * r * 0.9
				var t := Vector2(-sin(a1), cos(a1)) * (1.0 if cw else -1.0)
				_tri(p + t * r * 0.15, t, r * 0.45)
			"heart", "heart_empty":
				var hc := Color(0.92, 0.3, 0.38) if kind == "heart" else Color(0.42, 0.33, 0.28)
				var hr := minf(size.x, size.y) * 0.5
				draw_circle(c + Vector2(-hr * 0.45, -hr * 0.18), hr * 0.5, hc)
				draw_circle(c + Vector2(hr * 0.45, -hr * 0.18), hr * 0.5, hc)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-hr * 0.93, -hr * 0.02), c + Vector2(hr * 0.93, -hr * 0.02), c + Vector2(0, hr * 0.9)]), hc)
			"lock", "unlock":
				var body := Rect2(c.x - r * 0.8, c.y - r * 0.05, r * 1.6, r * 1.15)
				draw_rect(body, col)
				draw_circle(Vector2(c.x, body.position.y + body.size.y * 0.45), r * 0.16, Color(0.17, 0.13, 0.11))
				var sc := Vector2(c.x, body.position.y) if kind == "lock" else Vector2(c.x + r * 0.55, body.position.y - r * 0.35)
				var sr := r * 0.52
				draw_arc(sc, sr, PI, TAU, 18, col, 3.0, true)
				draw_line(sc + Vector2(sr, 0), Vector2(sc.x + sr, body.position.y), col, 3.0)
				if kind == "lock":
					draw_line(sc - Vector2(sr, 0), Vector2(sc.x - sr, body.position.y), col, 3.0)

const BG := Color(0.17, 0.13, 0.11, 0.9)
const BG_LIGHT := Color(0.27, 0.21, 0.17, 0.95)
const BORDER := Color(0.55, 0.42, 0.28, 0.85)
const GOLD := Color(0.95, 0.80, 0.46)
const TEXT := Color(0.97, 0.93, 0.85)

var root: Control
var res_labels := {}
var energy_bar: ProgressBar
var food_bar: ProgressBar
var clock_label: Label
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var live_btn: Button
var build_btn: Button
var expand_btn: Button
var catalog_panel: PanelContainer
var item_buttons := {}
var holding_bar: HBoxContainer
var sell_btn: Button
var menu_panel: PanelContainer
var menu_box: VBoxContainer
var help_panel: PanelContainer
var fade: ColorRect
var lock_btn: Button
var lock_icon: Icon
var cam_locked := true
## Held on-screen arrow buttons, read by main.gd every frame (x = right, y = toward the viewer).
var cam_pad_pan := Vector2.ZERO
var _pad_held := {}
var dlg_panel: PanelContainer
var dlg_name: Label
var dlg_text: Label
var dlg_hearts: Array = []
var dlg_tween: Tween


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_title()
	_build_resources()
	_build_left()
	_build_needs()
	_build_clock()
	_build_camera_pad()
	_build_catalog()
	_build_holding()
	_build_toast()
	_build_dialogue()
	_build_menu()
	_build_help()
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.06, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)


# --- styling -------------------------------------------------------------------

func _sb(c: Color, radius: int, border := Color(0, 0, 0, 0), margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.set_border_width_all(2)
		s.border_color = border
	s.content_margin_left = margin + 2.0
	s.content_margin_right = margin + 2.0
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", _sb(BG, 12, BORDER, 12.0))
	t.set_stylebox("normal", "Button", _sb(BG_LIGHT, 8, Color(0.5, 0.38, 0.25)))
	t.set_stylebox("hover", "Button", _sb(Color(0.4, 0.3, 0.2, 0.97), 8, GOLD))
	t.set_stylebox("pressed", "Button", _sb(Color(0.62, 0.45, 0.2, 1.0), 8, GOLD))
	t.set_stylebox("hover_pressed", "Button", _sb(Color(0.68, 0.5, 0.24, 1.0), 8, GOLD))
	t.set_stylebox("disabled", "Button", _sb(Color(0.2, 0.17, 0.15, 0.85), 8, Color(0.32, 0.26, 0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 0.98, 0.9))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.98, 0.9))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.45))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("background", "ProgressBar", _sb(Color(0, 0, 0, 0.45), 6, Color(0, 0, 0, 0), 0.0))
	return t


## Pins a control to a screen corner/edge (ax, ay in {0, 0.5, 1}) with a margin.
func _place(c: Control, ax: float, ay: float, m: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0.0 else (Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_BOTH)
	c.grow_vertical = Control.GROW_DIRECTION_END if ay == 0.0 else (Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_BOTH)
	var ox := m.x if ax == 0.0 else (-m.x if ax == 1.0 else 0.0)
	var oy := m.y if ay == 0.0 else (-m.y if ay == 1.0 else 0.0)
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy


func _label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


# --- widgets -------------------------------------------------------------------

func _build_title() -> void:
	var pc := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.add_child(_label("Knitting Empire", 26, GOLD))
	vb.add_child(_label("Birchfield Farm", 14, Color(0.85, 0.8, 0.7)))
	pc.add_child(vb)
	root.add_child(pc)
	_place(pc, 0.0, 0.0, Vector2(16, 16))


func _build_resources() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var specs := [["coins", "Coins", GOLD], ["wool", "Wool", Color(0.97, 0.97, 0.94)],
		["turnip", "Turnips", Color(0.82, 0.62, 0.9)], ["pumpkin", "Pumpkins", Color(0.98, 0.55, 0.15)],
		["sweater", "Sweaters", Color(0.85, 0.25, 0.2)]]
	for spec in specs:
		var chip := PanelContainer.new()
		chip.tooltip_text = spec[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", _sb(spec[2], 7, Color(0, 0, 0, 0), 0.0))
		row.add_child(dot)
		var l := _label("0", 16)
		row.add_child(l)
		chip.add_child(row)
		hb.add_child(chip)
		res_labels[spec[0]] = l
	root.add_child(hb)
	_place(hb, 1.0, 0.0, Vector2(16, 16))


func _build_left() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	live_btn = _button("Live", func(): mode_selected.emit(false))
	build_btn = _button("Build & Buy", func(): mode_selected.emit(true))
	for b in [live_btn, build_btn]:
		b.toggle_mode = true
		b.button_group = group
		vb.add_child(b)
	live_btn.button_pressed = true
	expand_btn = _button("Expand House", func(): expand_pressed.emit())
	vb.add_child(expand_btn)
	vb.add_child(_button("Walls Up / Down", func(): walls_pressed.emit()))
	vb.add_child(_button("Save Game", func(): save_pressed.emit()))
	vb.add_child(_button("How to Play", func(): help_panel.visible = true))
	vb.add_child(_button("New Game", func(): new_game_pressed.emit()))
	for c in vb.get_children():
		(c as Button).custom_minimum_size = Vector2(170, 0)
		(c as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(vb)
	_place(vb, 0.0, 0.0, Vector2(16, 104))


func _bar(color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(190, 14)
	p.show_percentage = false
	p.max_value = 100
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("fill", _sb(color, 6, Color(0, 0, 0, 0), 0.0))
	return p


func _build_needs() -> void:
	var pc := PanelContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(_label("Energy", 14))
	energy_bar = _bar(Color(0.95, 0.75, 0.25))
	grid.add_child(energy_bar)
	grid.add_child(_label("Food", 14))
	food_bar = _bar(Color(0.45, 0.78, 0.35))
	grid.add_child(food_bar)
	pc.add_child(grid)
	root.add_child(pc)
	_place(pc, 0.0, 1.0, Vector2(16, 16))


func _build_clock() -> void:
	var pc := PanelContainer.new()
	clock_label = _label("", 17)
	pc.add_child(clock_label)
	root.add_child(pc)
	_place(pc, 1.0, 1.0, Vector2(16, 16))


func _pad_button(kind: String, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(42, 42)
	b.tooltip_text = tip
	var ic := Icon.new(kind)
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b


func _pad_hold(b: Button, dir: Vector2) -> void:
	b.button_down.connect(func():
		_pad_held[b] = dir
		_sum_pad())
	b.button_up.connect(func():
		_pad_held.erase(b)
		_sum_pad())


func _sum_pad() -> void:
	cam_pad_pan = Vector2.ZERO
	for k in _pad_held:
		cam_pad_pan += _pad_held[k]


func _build_camera_pad() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(BG, 12, BORDER, 6.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var title := _label("Camera", 12, Color(0.85, 0.8, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var rl := _pad_button("rot_l", "Rotate left (Q)")
	rl.pressed.connect(func(): cam_rotate.emit(-1))
	var up := _pad_button("up", "Pan (W / ↑)")
	_pad_hold(up, Vector2(0, -1))
	var rr := _pad_button("rot_r", "Rotate right (E)")
	rr.pressed.connect(func(): cam_rotate.emit(1))
	var lf := _pad_button("left", "Pan (A / ←)")
	_pad_hold(lf, Vector2(-1, 0))
	lock_btn = _pad_button("lock", "")
	lock_btn.toggle_mode = true
	lock_icon = lock_btn.get_meta("icon")
	lock_btn.toggled.connect(func(_on): cam_lock_pressed.emit())
	var rt := _pad_button("right", "Pan (D / →)")
	_pad_hold(rt, Vector2(1, 0))
	var zo := _pad_button("minus", "Zoom out (scroll / pinch)")
	zo.pressed.connect(func(): cam_zoom.emit(1))
	var dn := _pad_button("down", "Pan (S / ↓)")
	_pad_hold(dn, Vector2(0, 1))
	var zi := _pad_button("plus", "Zoom in (scroll / pinch)")
	zi.pressed.connect(func(): cam_zoom.emit(-1))
	for b in [rl, up, rr, lf, lock_btn, rt, zo, dn, zi]:
		grid.add_child(b)
	vb.add_child(grid)
	pc.add_child(vb)
	root.add_child(pc)
	_place(pc, 0.0, 1.0, Vector2(16, 96))
	set_cam_locked(true)


## Shows the lock as closed (camera follows your character) or open (free camera).
func set_cam_locked(on: bool) -> void:
	cam_locked = on
	lock_btn.set_pressed_no_signal(on)
	lock_icon.set_kind("lock" if on else "unlock", Color(1.0, 0.92, 0.7) if on else TEXT)
	lock_btn.tooltip_text = "Camera locked to your character. Click to unlock (Space)" if on else "Free camera. Click to lock onto your character (Space)"


func _build_catalog() -> void:
	catalog_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(_label("Build & Buy", 20, GOLD))
	var hint := _label("Pick an item, click to place it.\nR rotate · Right-click cancel\nClick placed items to move or sell them.", 12, Color(0.85, 0.8, 0.7))
	vb.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(270, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	for section in [["INDOORS", Catalog.INDOOR], ["YARD & GARDEN", Catalog.OUTDOOR]]:
		list.add_child(_label(section[0], 12, GOLD))
		for id in section[1]:
			var info: Dictionary = Catalog.ITEMS[id]
			var item_id: String = id
			var b := _button("%s   ·   %dc" % [info["name"], info["price"]], func(): item_chosen.emit(item_id))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.add_child(b)
			item_buttons[id] = b
	scroll.add_child(list)
	vb.add_child(scroll)
	catalog_panel.add_child(vb)
	catalog_panel.visible = false
	root.add_child(catalog_panel)
	_place(catalog_panel, 1.0, 0.5, Vector2(16, 0))


func _build_holding() -> void:
	holding_bar = HBoxContainer.new()
	holding_bar.add_theme_constant_override("separation", 8)
	holding_bar.add_child(_button("Rotate  (R)", func(): rotate_pressed.emit()))
	sell_btn = _button("Sell", func(): sell_pressed.emit())
	holding_bar.add_child(sell_btn)
	holding_bar.add_child(_button("Cancel  (Esc)", func(): cancel_pressed.emit()))
	holding_bar.visible = false
	root.add_child(holding_bar)
	_place(holding_bar, 0.5, 1.0, Vector2(0, 24))


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_label = _label("", 17)
	toast_panel.add_child(toast_label)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	root.add_child(toast_panel)
	_place(toast_panel, 0.5, 0.0, Vector2(0, 84))


func _build_dialogue() -> void:
	dlg_panel = PanelContainer.new()
	dlg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	dlg_name = _label("", 19, GOLD)
	top.add_child(dlg_name)
	var hearts := HBoxContainer.new()
	hearts.add_theme_constant_override("separation", 3)
	hearts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 5:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(18, 18)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icon.new("heart_empty")
		holder.add_child(ic)
		hearts.add_child(holder)
		dlg_hearts.append(ic)
	top.add_child(hearts)
	vb.add_child(top)
	dlg_text = _label("", 16)
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_text.custom_minimum_size = Vector2(620, 0)
	vb.add_child(dlg_text)
	var hint := _label("click anywhere to close", 11, Color(0.75, 0.7, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	dlg_panel.add_child(vb)
	for c in [vb, top, hearts, hint, dlg_text, dlg_name]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_panel.visible = false
	root.add_child(dlg_panel)
	_place(dlg_panel, 0.5, 1.0, Vector2(0, 24))


## A villager speaks: name, 0..5 friendship hearts and their line.
func show_dialogue(speaker: String, hearts: int, text: String) -> void:
	dlg_name.text = speaker
	dlg_text.text = text
	for i in dlg_hearts.size():
		(dlg_hearts[i] as Icon).set_kind("heart" if i < hearts else "heart_empty", TEXT)
		(dlg_hearts[i] as Icon).get_parent().visible = hearts >= 0
	dlg_panel.visible = true
	dlg_panel.modulate.a = 1.0
	dlg_panel.reset_size()
	if dlg_tween:
		dlg_tween.kill()
	dlg_tween = create_tween()
	dlg_tween.tween_interval(12.0)
	dlg_tween.tween_property(dlg_panel, "modulate:a", 0.0, 0.5)
	dlg_tween.tween_callback(func(): dlg_panel.visible = false)


func hide_dialogue() -> void:
	if dlg_tween:
		dlg_tween.kill()
	dlg_panel.visible = false


func _build_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.1, 0.09, 0.82), 10, Color(0, 0, 0, 0), 8.0))
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 5)
	menu_panel.add_child(menu_box)
	menu_panel.visible = false
	root.add_child(menu_panel)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("Welcome to Birchfield Farm", 24, GOLD))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(600, 0)
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 15)
	rt.text = """[b]The loop:[/b] shear your sheep → knit sweaters in the rocking chair → ship them in the shipping bin → spend coins on furniture and house expansions.

[b]Live mode:[/b] click the ground to walk. Click things (chair, bed, kitchen, soil plots, sheep, shipping bin) for a menu of actions.
[b]Farming:[/b] plant seeds in the soil plots, water them every day, harvest when they glow. Eat crops at the kitchen or ship them.
[b]Build & Buy:[/b] pick furniture from the catalog and click to place it. [b]R[/b] rotates, right-click cancels. Click placed furniture to move it or sell it back.
[b]Camera:[/b] use the camera pad (bottom left), WASD / arrow keys, or two-finger swipe on the trackpad to pan · pinch or scroll to zoom · [b]Q[/b]/[b]E[/b] rotate · the [b]lock[/b] button (or [b]Space[/b]) locks the camera onto your character · [b]C[/b] toggles walls.
[b]Maplewood:[/b] follow the road east (or click the signpost) to town. Sell sweaters to Rosa at the market for today's price, buy wool and sheep from Theo, and buy Rosewood Cottage from Mabel. Furnish it and it earns rent every morning. Talk to villagers and bring gifts to earn hearts: more hearts, better deals.
[b]Days:[/b] sleep in your bed to start a new day. Watered crops grow overnight. The game saves when you sleep and when you quit."""
	vb.add_child(rt)
	var go := _button("Let's knit!", func(): help_panel.visible = false)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size = Vector2(160, 40)
	vb.add_child(go)
	help_panel.add_child(vb)
	help_panel.visible = false
	root.add_child(help_panel)
	_place(help_panel, 0.5, 0.5, Vector2.ZERO)


# --- public API ----------------------------------------------------------------

func set_build_mode(on: bool) -> void:
	catalog_panel.visible = on
	build_btn.set_pressed_no_signal(on)
	live_btn.set_pressed_no_signal(not on)
	if not on:
		set_holding(false)


func set_holding(on: bool, sell_value := 0) -> void:
	holding_bar.visible = on
	sell_btn.visible = sell_value > 0
	sell_btn.text = "Sell for %dc  (Del)" % sell_value


func set_expand_text(text: String, enabled: bool) -> void:
	expand_btn.text = text
	expand_btn.disabled = not enabled


func show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.6)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.6)


## actions: Array of {"id", "label", "enabled"}; cb receives the chosen id.
func show_menu(screen_pos: Vector2, title: String, actions: Array, cb: Callable) -> void:
	for c in menu_box.get_children():
		c.queue_free()
	menu_box.add_child(_label(title, 14, GOLD))
	for a in actions:
		var id: String = a["id"]
		var b := _button(a["label"], func():
			hide_menu()
			cb.call(id))
		b.disabled = not a["enabled"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(230, 34)
		menu_box.add_child(b)
	menu_panel.visible = true
	menu_panel.reset_size()
	menu_panel.position = screen_pos + Vector2(22, -14)
	await get_tree().process_frame
	var vs := root.get_viewport_rect().size
	menu_panel.position.x = minf(menu_panel.position.x, vs.x - menu_panel.size.x - 8.0)
	menu_panel.position.y = clampf(menu_panel.position.y, 8.0, vs.y - menu_panel.size.y - 8.0)


func hide_menu() -> void:
	menu_panel.visible = false


func is_menu_open() -> bool:
	return menu_panel.visible


func fade_sleep() -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.tween_interval(0.9)
	tw.tween_property(fade, "color:a", 0.0, 0.8)


func _process(_delta: float) -> void:
	res_labels["coins"].text = "%d" % Game.coins
	for k in ["wool", "turnip", "pumpkin", "sweater"]:
		res_labels[k].text = "%d %s" % [Game.count(k), _pretty(k, Game.count(k))]
	energy_bar.value = Game.energy
	food_bar.value = Game.fullness
	clock_label.text = "%s, Day %d   ·   %s" % [Game.season_name(), Game.day_of_season(), Game.clock_text()]
	if catalog_panel.visible:
		for id in item_buttons:
			item_buttons[id].disabled = Game.coins < int(Catalog.ITEMS[id]["price"])


func _pretty(k: String, n: int) -> String:
	match k:
		"wool": return "wool"
		"turnip": return "turnip" if n == 1 else "turnips"
		"pumpkin": return "pumpkin" if n == 1 else "pumpkins"
		"sweater": return "sweater" if n == 1 else "sweaters"
	return k
