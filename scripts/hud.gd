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

# story scenes (driven by story_player.gd)
signal story_next
signal story_chosen(index: int)
var story_layer: Control # full screen; takes clicks while a scene plays
var story_box: PanelContainer
var story_portrait: TextureRect
var story_portrait_frame: PanelContainer
var story_name_tab: PanelContainer
var story_name: Label
var story_text: Label
var story_hint: Label
var story_choice_box: VBoxContainer
var story_prompt: Label
var story_fade_rect: ColorRect
var story_title_label: Label
var story_bars: Array[ColorRect] = []
var _story_typing: Tween
var goal_panel: PanelContainer # the current story goal, top centre
var goal_label: Label
var phone_panel: PanelContainer # "Incoming call" card during scenes
var phone_label: Label
var _phone_tween: Tween


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_vignette()
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
	_build_story()
	_build_goal()
	_build_phone()


# --- styling -------------------------------------------------------------------

## Woolcore UI: a bordered panel or button is a piece of felt with a running stitch sewn around
## it (see _stitched); a borderless one is a plain rounded shape.
func _sb(c: Color, radius: int, border := Color(0, 0, 0, 0), margin := 10.0) -> StyleBox:
	if border.a > 0.0 and radius >= 6:
		return _stitched(c, radius, border, margin)
	return _sb_flat(c, radius, border, margin)


static var _felt_cache := {}

## A felt patch with a running stitch, drawn into a small image and nine-sliced. The edges
## tile, so the stitches keep their size on any panel. Stitch period 8 px: 5 thread, 3 gap.
func _stitched(c: Color, radius: int, border: Color, margin: float) -> StyleBoxTexture:
	var key := "%s|%d|%s" % [c.to_html(), radius, border.to_html()]
	var m := maxi(radius + 6, 14) # corner size
	var n := m * 2 + 16 # a 16 px middle band that tiles
	var tex: ImageTexture = _felt_cache.get(key)
	if tex == null:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var thread := border.lerp(Color(1.0, 0.95, 0.82), 0.3)
		thread.a = 1.0
		var shade := Color(0, 0, 0, 0.35)
		var size := Vector2(n, n)
		var r := float(radius)
		var inset := 5.5
		var ri := maxf(r - inset, 1.5)
		for y in n:
			for x in n:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := _sd_rrect(p, size, 0.5, r)
				if d > 0.5:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				var col := c
				var grain := 1.0 + (rng.randf() - 0.5) * 0.07 + (0.03 if (x + y * 3) % 7 == 0 else 0.0)
				col = Color(col.r * grain, col.g * grain, col.b * grain, c.a)
				col = col.darkened(0.22 * clampf(1.0 + d / 2.5, 0.0, 1.0)) # a soft rolled edge
				# the stitch: distance to an inset rounded path, dashed along the edges
				var ds := absf(_sd_rrect(p, size, inset, ri))
				var dsh := absf(_sd_rrect(p - Vector2(0, 1.2), size, inset, ri)) # its shadow, a pixel lower
				var on := _stitch_on(p, size, inset, ri, m)
				if on and dsh < 1.2 and ds >= 1.0:
					col = col.lerp(shade, 0.5 * clampf(1.2 - dsh, 0.0, 1.0))
				if on and ds < 1.25:
					var k := clampf(1.25 - ds, 0.0, 1.0)
					var tc := thread.lightened(0.12) if ds < 0.4 else thread
					col = col.lerp(Color(tc.r, tc.g, tc.b, maxf(col.a, 0.95)), k)
				col.a *= clampf(0.5 - d, 0.0, 1.0)
				img.set_pixel(x, y, col)
		tex = ImageTexture.create_from_image(img)
		_felt_cache[key] = tex
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = margin + 5.0
	sb.content_margin_right = margin + 5.0
	sb.content_margin_top = margin * 0.6 + 2.0
	sb.content_margin_bottom = margin * 0.6 + 2.0
	return sb


## Signed distance from p to a rounded rectangle filling `size`, shrunk by `inset`, corner radius r.
static func _sd_rrect(p: Vector2, size: Vector2, inset: float, r: float) -> float:
	var c := size * 0.5
	var b := c - Vector2(inset + r, inset + r)
	var q := (p - c).abs() - b
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## Whether the running stitch shows at p: dashed along straight runs, one long stitch round a corner.
static func _stitch_on(p: Vector2, size: Vector2, inset: float, r: float, m: int) -> bool:
	var c := size * 0.5
	var b := c - Vector2(inset + r, inset + r)
	var q := (p - c).abs()
	if q.x > b.x and q.y > b.y:
		return true # the corner curve
	var along := p.x # along the top and bottom edges; down the sides
	if q.x > b.x:
		along = p.y
	elif q.y > b.y:
		along = p.x
	return absf(fposmod(along - m, 8.0) - 4.0) < 2.5


func _sb_flat(c: Color, radius: int, border := Color(0, 0, 0, 0), margin := 10.0) -> StyleBoxFlat:
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


# --- story scenes ----------------------------------------------------------------

const STORY_W := 860.0


func _build_story() -> void:
	story_layer = Control.new()
	story_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	story_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	story_layer.visible = false
	story_layer.gui_input.connect(_on_story_input)
	root.add_child(story_layer)
	# cinematic bars
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.02, 0.03, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		story_layer.add_child(bar)
		story_bars.append(bar)
	# the dialogue box: portrait on the left, name tab, text, choices
	story_box = PanelContainer.new()
	story_box.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.11, 0.09, 0.94), 14, BORDER, 16.0))
	story_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_portrait_frame = PanelContainer.new()
	story_portrait_frame.add_theme_stylebox_override("panel", _sb(Color(0.33, 0.25, 0.19, 1.0), 10, GOLD, 3.0))
	story_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	story_portrait = TextureRect.new()
	story_portrait.custom_minimum_size = Vector2(150, 150)
	story_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	story_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_portrait_frame.add_child(story_portrait)
	hb.add_child(story_portrait_frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_name_tab = PanelContainer.new()
	story_name_tab.add_theme_stylebox_override("panel", _sb(Color(0.55, 0.36, 0.22, 1.0), 8, Color(0, 0, 0, 0), 8.0))
	story_name_tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	story_name_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_name = _label("", 19, Color(1.0, 0.95, 0.84))
	story_name_tab.add_child(story_name)
	vb.add_child(story_name_tab)
	story_text = _label("", 19)
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.custom_minimum_size = Vector2(STORY_W - 230, 64)
	vb.add_child(story_text)
	story_prompt = _label("", 15, GOLD)
	story_prompt.visible = false
	vb.add_child(story_prompt)
	story_choice_box = VBoxContainer.new()
	story_choice_box.add_theme_constant_override("separation", 6)
	vb.add_child(story_choice_box)
	story_hint = _label("click or press Space  ▸", 12, Color(0.78, 0.72, 0.62))
	story_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(story_hint)
	hb.add_child(vb)
	story_box.add_child(hb)
	for c in [story_name, story_text, story_prompt, story_hint]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_box.custom_minimum_size = Vector2(STORY_W, 0)
	story_box.visible = false
	story_layer.add_child(story_box)
	_place(story_box, 0.5, 1.0, Vector2(0, 70))
	# fade and title card sit on top of everything
	story_fade_rect = ColorRect.new()
	story_fade_rect.color = Color(0.03, 0.025, 0.03, 0.0)
	story_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	story_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(story_fade_rect)
	story_title_label = _label("", 44, GOLD)
	story_title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	story_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	story_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_title_label.modulate.a = 0.0
	root.add_child(story_title_label)


func story_begin() -> void:
	hide_menu()
	hide_dialogue()
	story_layer.visible = true
	story_box.visible = false
	goal_panel.visible = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(story_bars[0], "offset_bottom", 54.0, 0.45)
	tw.tween_property(story_bars[1], "offset_top", -54.0, 0.45)


func story_end() -> void:
	story_box.visible = false
	story_clear_choices()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(story_bars[0], "offset_bottom", 0.0, 0.35)
	tw.tween_property(story_bars[1], "offset_top", 0.0, 0.35)
	if story_fade_rect.color.a > 0.0:
		tw.tween_property(story_fade_rect, "color:a", 0.0, 0.5)
	await tw.finished
	story_layer.visible = false
	goal_panel.visible = goal_label.text != ""


## Shows a line. name_text "" = narration (no tab, no portrait); tex null = no portrait.
func story_say(name_text: String, text: String, tex: Texture2D) -> void:
	story_clear_choices()
	story_box.visible = true
	story_name_tab.visible = name_text != ""
	story_name.text = name_text
	story_portrait_frame.visible = tex != null
	story_portrait.texture = tex
	story_text.text = text
	story_text.add_theme_color_override("font_color", TEXT if name_text != "" else Color(0.88, 0.84, 0.76))
	story_hint.visible = true
	story_text.visible_ratio = 0.0
	if _story_typing:
		_story_typing.kill()
	_story_typing = create_tween()
	_story_typing.tween_property(story_text, "visible_ratio", 1.0, clampf(text.length() * 0.022, 0.25, 2.2))


func story_choices(prompt: String, texts: Array) -> void:
	story_clear_choices()
	story_box.visible = true
	story_hint.visible = false
	story_prompt.text = prompt
	story_prompt.visible = prompt != ""
	if _story_typing:
		_story_typing.kill()
	story_text.visible_ratio = 1.0
	for i in texts.size():
		var b := _button("  %d.  %s" % [i + 1, texts[i]], func(): _choose(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 17)
		story_choice_box.add_child(b)


func story_clear_choices() -> void:
	for c in story_choice_box.get_children():
		c.queue_free()
	story_prompt.visible = false


func story_has_choices() -> bool:
	return story_choice_box.get_child_count() > 0 and story_choice_box.get_child(0).is_queued_for_deletion() == false


func _choose(i: int) -> void:
	story_clear_choices()
	story_chosen.emit(i)


## Click or key while a scene plays: finish the typing, then go to the next line.
func story_click() -> void:
	if not story_layer.visible or story_has_choices():
		return
	if _story_typing and _story_typing.is_running():
		_story_typing.kill()
		story_text.visible_ratio = 1.0
		return
	story_next.emit()


## Picks choice n (1-based) from the keyboard.
func story_key_choice(n: int) -> void:
	if story_has_choices() and n >= 1 and n <= story_choice_box.get_child_count():
		_choose(n - 1)


func _on_story_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		story_click()


func story_fade(alpha: float, secs: float) -> void:
	if alpha > 0.0:
		story_box.visible = false
	var tw := create_tween()
	tw.tween_property(story_fade_rect, "color:a", alpha, secs)
	await tw.finished


## A title card: fades in over a dark screen, holds, fades out.
func story_title(text: String, secs: float) -> void:
	story_box.visible = false
	story_title_label.text = text
	var tw := create_tween()
	if story_fade_rect.color.a < 0.9:
		tw.tween_property(story_fade_rect, "color:a", 1.0, secs * 0.2)
	tw.tween_property(story_title_label, "modulate:a", 1.0, secs * 0.25)
	tw.tween_interval(secs * 0.5)
	tw.tween_property(story_title_label, "modulate:a", 0.0, secs * 0.25)
	await tw.finished


# --- story goal and phone card ----------------------------------------------------

func _build_goal() -> void:
	goal_panel = PanelContainer.new()
	goal_panel.add_theme_stylebox_override("panel", _sb(Color(0.16, 0.12, 0.09, 0.9), 10, GOLD, 10.0))
	goal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.add_child(_label("▸", 16, GOLD))
	goal_label = _label("", 16)
	hb.add_child(goal_label)
	goal_panel.add_child(hb)
	goal_panel.visible = false
	root.add_child(goal_panel)
	_place(goal_panel, 0.5, 0.0, Vector2(0, 16))


## Shows the current goal ("" hides it).
func set_goal(text: String) -> void:
	goal_label.text = text
	goal_panel.visible = text != "" and not story_layer.visible
	if goal_panel.visible:
		goal_panel.modulate.a = 0.0
		create_tween().tween_property(goal_panel, "modulate:a", 1.0, 0.5)


func _build_phone() -> void:
	phone_panel = PanelContainer.new()
	phone_panel.add_theme_stylebox_override("panel", _sb_flat(Color(0.08, 0.09, 0.12, 0.95), 18, Color(0.45, 0.5, 0.6), 14.0))
	phone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.add_child(_label("Incoming call", 13, Color(0.7, 0.75, 0.82)))
	phone_label = _label("", 24, Color(0.96, 0.96, 0.98))
	vb.add_child(phone_label)
	vb.add_child(_label("mobile", 12, Color(0.55, 0.6, 0.68)))
	phone_panel.add_child(vb)
	phone_panel.visible = false
	root.add_child(phone_panel)
	_place(phone_panel, 1.0, 0.0, Vector2(28, 76))


## A phone ringing with a caller's name ("" puts it away).
func set_phone(caller: String) -> void:
	if _phone_tween:
		_phone_tween.kill()
	phone_panel.visible = caller != ""
	phone_label.text = caller
	phone_panel.rotation = 0.0
	if caller != "":
		phone_panel.pivot_offset = Vector2(90, 40)
		_phone_tween = create_tween().set_loops()
		for r in [0.05, -0.05, 0.04, -0.04, 0.0]:
			_phone_tween.tween_property(phone_panel, "rotation", r, 0.06)
		_phone_tween.tween_interval(0.7)


## Woolcore: the screen's edges darken a little, like the frame of an embroidery hoop.
func _build_vignette() -> void:
	var v := ColorRect.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.42;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.82);
	float v = smoothstep(0.32, 0.8, length(d));
	COLOR = vec4(0.13, 0.06, 0.09, v * strength);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	v.material = m
	root.add_child(v)
