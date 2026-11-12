extends CanvasLayer
## All on-screen UI, built in code: resources, needs, clock, mode buttons,
## build catalog, action menu, toasts, help and the sleep fade.

signal mode_selected(build: bool)
signal expand_pressed
signal walls_pressed
signal save_pressed
signal new_game_pressed
signal graphics_pressed
signal title_continue
signal title_new_game
signal title_quit
signal volumes_changed(music: float, sound: float)
signal fullscreen_toggled(on: bool)
signal god_time(hour: float) # god mode (settings): jump the clock
signal god_weather(weather: String) # "clear" or "rain"
signal god_freeze(on: bool) # stop the clock
signal god_edit(on: bool) # the world editor (scripts/god_mode.gd), admin only
signal hud_option(option: String, on: bool) # "fps" or "camera_pad": shown or hidden (settings)
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
			"bolt":
				draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.25, -r * 1.25), c + Vector2(-r * 0.7, r * 0.15), c + Vector2(-r * 0.05, r * 0.15),
					c + Vector2(-r * 0.3, r * 1.25), c + Vector2(r * 0.7, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2)]), col)
			"bowl":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.1, -r * 0.05), c + Vector2(r * 1.1, -r * 0.05), c + Vector2(r * 0.6, r * 0.85), c + Vector2(-r * 0.6, r * 0.85)]), col)
				for i in 3:
					var x := (i - 1) * r * 0.5
					draw_arc(c + Vector2(x, -r * 0.6), r * 0.22, PI * 0.5, PI * 1.5, 8, col, 1.8, true)
			"smile":
				draw_arc(c, r * 1.1, 0.0, TAU, 28, col, 2.2, true)
				draw_circle(c + Vector2(-r * 0.4, -r * 0.3), r * 0.16, col)
				draw_circle(c + Vector2(r * 0.4, -r * 0.3), r * 0.16, col)
				draw_arc(c + Vector2(0, r * 0.05), r * 0.6, 0.35, PI - 0.35, 14, col, 2.2, true)
			"flame":
				var pts := PackedVector2Array()
				for i in 25:
					var a := float(i) / 24.0 * TAU
					var rr := r * (1.0 - 0.45 * pow(maxf(0.0, -sin(a)), 3.0)) * 1.05
					pts.append(c + Vector2(cos(a) * rr * 0.8, sin(a) * rr * 0.75 + r * 0.2) + Vector2(0, -pow(maxf(0.0, -sin(a)), 6.0) * r * 0.9))
				draw_colored_polygon(pts, col)
			"dumbbell":
				draw_line(c - Vector2(r * 0.8, 0), c + Vector2(r * 0.8, 0), col, 2.6)
				for sx in [-1.0, 1.0]:
					draw_rect(Rect2(c + Vector2(sx * r * 0.85 - r * 0.22, -r * 0.6), Vector2(r * 0.44, r * 1.2)), col)
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

## A rounded bar for needs and progress. Colour follows the value (green, amber, red) unless
## `fixed` is set. `trend` (-2..2) draws arrows at the end of the fill, pointing the way it's moving.
class Meter extends Control:
	var value := 1.0
	var trend := 0
	var fixed := Color(0, 0, 0, 0)
	var _track: StyleBoxFlat
	var _fill: StyleBoxFlat

	func _init(v := 1.0, sz := Vector2(150, 12), fixed_color := Color(0, 0, 0, 0)) -> void:
		value = clampf(v, 0.0, 1.0)
		fixed = fixed_color
		custom_minimum_size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_track = StyleBoxFlat.new()
		_track.bg_color = Color(0.05, 0.04, 0.03, 0.55)
		_track.set_corner_radius_all(int(sz.y * 0.5))
		_track.border_color = Color(0, 0, 0, 0.35)
		_track.set_border_width_all(1)
		_fill = StyleBoxFlat.new()
		_fill.set_corner_radius_all(int(sz.y * 0.5))

	func set_value(v: float, t := 0) -> void:
		v = clampf(v, 0.0, 1.0)
		if absf(v - value) > 0.001 or t != trend:
			value = v
			trend = t
			queue_redraw()

	static func color_for(v: float) -> Color:
		if v > 0.6:
			return Color(0.45, 0.8, 0.33)
		if v > 0.3:
			return Color(0.86, 0.7, 0.26)
		return Color(0.84, 0.33, 0.22)

	func _draw() -> void:
		var h := size.y
		draw_style_box(_track, Rect2(Vector2.ZERO, size))
		if value <= 0.005:
			return
		var w := maxf(h, size.x * value)
		var col := fixed if fixed.a > 0.0 else color_for(value)
		_fill.bg_color = col
		draw_style_box(_fill, Rect2(Vector2(1, 1), Vector2(w - 2, h - 2)))
		draw_line(Vector2(h * 0.5, h * 0.32), Vector2(maxf(h * 0.5, w - h * 0.5), h * 0.32), col.lightened(0.35), maxf(1.0, h * 0.18), true)
		var arrow := col.darkened(0.45)
		for i in absi(trend):
			var d := 1.0 if trend > 0 else -1.0
			var x := w - h * 0.6 - i * h * 0.75
			if x < h:
				break
			var cy := h * 0.5
			var s := h * 0.3
			draw_colored_polygon(PackedVector2Array([Vector2(x + s * d, cy), Vector2(x - s * d, cy - s), Vector2(x - s * d, cy + s)]), arrow)


const BG := Color(0.17, 0.13, 0.11, 0.9)
const BG_LIGHT := Color(0.27, 0.21, 0.17, 0.95)
const BORDER := Color(0.55, 0.42, 0.28, 0.85)
const GOLD := Color(0.95, 0.80, 0.46)
const TEXT := Color(0.97, 0.93, 0.85)

var root: Control
var res_labels := {}
var needs_meters := {} # need -> Meter
var needs_cells := {} # need -> the cell (for tooltips)
var _need_prev := {}
var _need_rate := {}
var _need_t := 0.0
var now_row: HBoxContainer # the current action in the needs panel, with a Stop button
var now_label: Label
var now_meter: Meter
var act_bubble: PanelContainer # the action bar floating over her head
var act_label: Label
var act_meter: Meter
signal stop_activity_pressed
var clock_label: Label
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var toast_meter: Meter
var build_btn: Button # at the end of the hotbar
var menu_btn: Button
var game_menu: PanelContainer # Save, Settings, Journal, How to Play, New Game
var needs_panel: PanelContainer
var cam_pad: PanelContainer
var fps_check: CheckButton
var cam_pad_check: CheckButton
var hotbar: PanelContainer
var bag_panel: PanelContainer
var slot_btns: Array[Slot] = [] # Game.slots, in order: the first HOTBAR are the bar, the rest the bag
var hot_sel := 0 # the hotbar slot in her hand
var _picked := -1 # a slot clicked in the bag, waiting for the slot to swap it with
var expand_btn: Button
var graphics_btn: Button
var settings_panel: PanelContainer
var god_time_slider: HSlider
var god_time_label: Label
var god_weather_btns := {} # "clear" / "rain" -> Button
var god_freeze_check: CheckButton
var god_edit_check: CheckButton
var god_edit_note: Label
var fps_label: Label
var _fps_t := 0.0
var music_slider: HSlider
var sound_slider: HSlider
var fullscreen_check: CheckButton
var title_layer: Control
var tip_panel: PanelContainer
var tip_label: Label
var _tip_tween: Tween
var title_continue_btn: Button
var title_new_btn: Button
var _title_new_armed := false
var catalog_panel: PanelContainer
var item_buttons := {}
var thumbs # thumbs.gd
var holding_bar: HBoxContainer
var sell_btn: Button
var chrome: Array[Control] = [] # the everyday panels, faded out during story scenes
var pie # pie_menu.gd: the ring of actions round whatever you clicked
var chat # chat_panel.gd: typing to a villager
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
var memory_rect: ColorRect # the warm, faded look of a memory thread (story "@memory on")
var _memory_tween: Tween
var journal_panel: PanelContainer # the journal: memories and moments the story writes down
var journal_list: VBoxContainer
signal journal_opened


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_vignette()
	_build_memory()
	var first := root.get_child_count()
	_build_menu_button()
	_build_resources()
	_build_needs()
	_build_clock()
	_build_camera_pad()
	_build_hotbar()
	for i in range(first, root.get_child_count()):
		if root.get_child(i) != act_bubble:
			chrome.append(root.get_child(i))
	_build_catalog()
	_build_holding()
	_build_toast()
	_build_dialogue()
	_build_menu()
	_build_chat()
	_build_help()
	_build_journal()
	_build_game_menu()
	_build_bag()
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.06, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	_build_story()
	_build_goal()
	_build_phone()
	_build_tip()
	_build_settings()
	_build_title_screen()


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


func set_graphics_label(level: String) -> void:
	graphics_btn.text = "Graphics: " + level


var sfx := Callable() # main.gd's audio.play(name, db): a soft click for buttons


func click(sound := "ui_click") -> void:
	if sfx.is_valid():
		sfx.call(sound, -10.0)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): click())
	b.pressed.connect(cb)
	return b


# --- widgets -------------------------------------------------------------------

## The one button left of the old side menu: everything else is behind it (see _build_game_menu).
func _build_menu_button() -> void:
	menu_btn = _button("Menu", func(): toggle_game_menu())
	menu_btn.tooltip_text = "Save, settings, journal and help (Esc)"
	root.add_child(menu_btn)
	_place(menu_btn, 0.0, 0.0, Vector2(16, 16))


## Coins, top right. Everything else she carries is in the hotbar and the bag.
func _build_resources() -> void:
	var chip := PanelContainer.new()
	chip.tooltip_text = "Coins"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _sb(GOLD, 7, Color(0, 0, 0, 0), 0.0))
	row.add_child(dot)
	var l := _label("0", 16)
	row.add_child(l)
	chip.add_child(row)
	root.add_child(chip)
	res_labels["coins"] = l
	_place(chip, 1.0, 0.0, Vector2(16, 16))
	# frames per second, under the coins (updated twice a second); off unless switched on in settings
	fps_label = _label("-- FPS", 14, Color(1, 1, 1, 0.85))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = false
	root.add_child(fps_label)
	_place(fps_label, 1.0, 0.0, Vector2(20, 58))


## What used to be the left-hand column, opened by the Menu button or Esc.
func _build_game_menu() -> void:
	game_menu = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var title := _label("Knitting Empire", 24, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var shut := func(): game_menu.visible = false
	vb.add_child(_button("Back to the farm", shut))
	vb.add_child(_button("Save Game", func(): shut.call(); save_pressed.emit()))
	vb.add_child(_button("Settings", func(): shut.call(); open_settings()))
	vb.add_child(_button("Journal", func(): shut.call(); open_journal()))
	vb.add_child(_button("How to Play", func(): shut.call(); help_panel.visible = true))
	var new_btn := _button("New Game", func(): pass)
	new_btn.pressed.connect(_confirm_then.bind(new_btn, "Click again: lose this farm", func(): shut.call(); new_game_pressed.emit()))
	vb.add_child(new_btn)
	for c in vb.get_children():
		if c is Button:
			(c as Button).custom_minimum_size = Vector2(240, 38)
	game_menu.add_child(vb)
	game_menu.visible = false
	root.add_child(game_menu)
	_place(game_menu, 0.5, 0.5, Vector2.ZERO)


func toggle_game_menu() -> void:
	game_menu.visible = not game_menu.visible
	if game_menu.visible:
		click("ui_open")
		game_menu.move_to_front()


# --- hotbar and bag ------------------------------------------------------------

const HOTBAR := 9


## One square of the hotbar or the bag: a token for the thing in it, how many, and (on the bar)
## the number key that picks it.
class Slot extends Button:
	## What each thing she can carry is called, and the colour of its token until it has a picture.
	const ITEM_INFO := {
		"wool": ["Wool", Color(0.97, 0.97, 0.94)],
		"turnip": ["Turnip", Color(0.82, 0.62, 0.9)],
		"pumpkin": ["Pumpkin", Color(0.98, 0.55, 0.15)],
		"sweater": ["Sweater", Color(0.85, 0.25, 0.2)],
		"wood": ["Wood", Color(0.72, 0.47, 0.25)],
		"hay": ["Hay", Color(0.94, 0.72, 0.2)],
		"gate": ["Pen gate", Color(0.6, 0.45, 0.3)],
		"gran_note": ["Gran's note", Color(0.96, 0.92, 0.82)],
		# tools: a third entry says what a click does with it in her hand
		"hoe": ["Hoe", Color(0.6, 0.45, 0.3), "right-click open ground on the farm and pick Dig bed"],
		"watering_can": ["Watering can", Color(0.45, 0.5, 0.6), "click a growing crop to water it"],
		"shears": ["Shears", Color(0.8, 0.3, 0.25), "click a woolly sheep to shear it"],
		"shovel": ["Shovel", Color(0.5, 0.45, 0.45), "click a bed you dug to clear it away"],
		"axe": ["Axe", Color(0.55, 0.4, 0.3), "click a tree to chop some wood"],
		"scythe": ["Scythe", Color(0.5, 0.55, 0.5), "click long grass to cut hay"],
	}
	static var _icons := {}

	static func holds_tool(item: String) -> bool:
		return ITEM_INFO.has(item) and (ITEM_INFO[item] as Array).size() > 2

	## What the tool does, for the toast when she takes it in hand ("" for anything else).
	static func tool_hint(item: String) -> String:
		return str(ITEM_INFO[item][2]) if holds_tool(item) else ""

	## The item's picture (assets/icons/<id>.png), or null: it is then drawn as a coloured token.
	static func icon(item: String) -> Texture2D:
		if not _icons.has(item):
			var path := "res://assets/icons/%s.png" % item
			_icons[item] = load(path) if ResourceLoader.exists(path) else null
		return _icons[item]

	static func item_name(item: String) -> String:
		return str(ITEM_INFO[item][0]) if ITEM_INFO.has(item) else item.capitalize()

	var id := ""
	var n := 0
	var key := 0 # 1..9 on the hotbar, 0 in the bag
	var chosen := false # in her hand
	var picked := false # clicked in the bag, about to be swapped

	func show_item(item: String, count: int, in_hand: bool, is_picked: bool) -> void:
		if item == id and count == n and in_hand == chosen and is_picked == picked:
			return
		id = item
		n = count
		chosen = in_hand
		picked = is_picked
		if id == "":
			tooltip_text = ""
		elif holds_tool(id):
			tooltip_text = "%s: %s" % [item_name(id), tool_hint(id)]
		else:
			tooltip_text = "%s × %d" % [item_name(id), n]
		queue_redraw()

	func _draw() -> void:
		var f := get_theme_default_font()
		if chosen or picked:
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.95, 0.80, 0.46) if chosen else Color(0.6, 0.85, 1.0), false, 3.0)
		if id != "":
			var col: Color = ITEM_INFO[id][1] if ITEM_INFO.has(id) else Color.from_hsv(float(id.hash() % 360) / 360.0, 0.45, 0.85)
			var pic := icon(id)
			if pic != null:
				draw_texture_rect(pic, Rect2(Vector2(4, 4), size - Vector2(8, 8)), false)
			else:
				draw_circle(size * 0.5 + Vector2(0, 1.5), size.x * 0.27, Color(0, 0, 0, 0.35))
				draw_circle(size * 0.5, size.x * 0.27, col)
			var t := "" if holds_tool(id) else str(n)
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string_outline(f, Vector2(size.x - w - 5, size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(size.x - w - 5, size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
		if key > 0:
			draw_string(f, Vector2(5, 14), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))


func _slot(i: int) -> Slot:
	var b := Slot.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 48)
	b.key = i + 1 if i < HOTBAR else 0
	b.pressed.connect(func(): click(); _slot_clicked(i))
	slot_btns.append(b)
	return b


## The bar along the bottom: nine slots (keys 1 to 9), then the bag and Build & Buy.
func _build_hotbar() -> void:
	hotbar = PanelContainer.new()
	hotbar.add_theme_stylebox_override("panel", _sb(BG, 12, BORDER, 6.0))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	for i in HOTBAR:
		hb.add_child(_slot(i))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	hb.add_child(gap)
	var bag := _button("Bag", func(): toggle_bag())
	bag.tooltip_text = "Everything she carries (I)"
	hb.add_child(bag)
	build_btn = _button("Build", func(): mode_selected.emit(build_btn.button_pressed))
	build_btn.toggle_mode = true
	build_btn.tooltip_text = "Build & Buy (B)"
	hb.add_child(build_btn)
	for b in [bag, build_btn]:
		b.custom_minimum_size = Vector2(0, 48)
	hotbar.add_child(hb)
	root.add_child(hotbar)
	_place(hotbar, 0.5, 1.0, Vector2(0, 14))


## The bag: the other 27 slots. With it open, click one slot and then another to swap them
## (the hotbar's slots too).
func _build_bag() -> void:
	bag_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(_label("Bag", 20, GOLD))
	var grid := GridContainer.new()
	grid.columns = HOTBAR
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for i in range(HOTBAR, Game.SLOTS):
		grid.add_child(_slot(i))
	vb.add_child(grid)
	vb.add_child(_label("Click a slot, then another, to swap them · I or Esc closes", 11, Color(0.85, 0.8, 0.7)))
	bag_panel.add_child(vb)
	bag_panel.visible = false
	root.add_child(bag_panel)
	_place(bag_panel, 0.5, 1.0, Vector2(0, 96))


func toggle_bag() -> void:
	bag_panel.visible = not bag_panel.visible
	_picked = -1
	if bag_panel.visible:
		click("ui_open")
		bag_panel.move_to_front()


func _slot_clicked(i: int) -> void:
	if not bag_panel.visible:
		hot_sel = i # only the hotbar can be clicked with the bag shut
		_announce_tool()
		return
	if _picked < 0:
		if Game.slots[i] != "":
			_picked = i
	else:
		Game.swap_slots(_picked, i)
		_picked = -1


## Number keys 1 to 9 (main.gd): puts that hotbar slot in her hand.
func hotbar_key(n: int) -> void:
	hot_sel = clampi(n - 1, 0, HOTBAR - 1)
	click()
	_announce_tool()


## Says what the tool she just took in hand is for.
func _announce_tool() -> void:
	var id := selected_item()
	if Slot.holds_tool(id):
		show_toast("%s: %s." % [Slot.item_name(id), Slot.tool_hint(id)])


## The id of the thing in her hand ("" for an empty slot).
func selected_item() -> String:
	return str(Game.slots[hot_sel]) if hot_sel < Game.slots.size() else "" # empty until the first sync


func _update_slots() -> void:
	Game.sync_slots()
	for i in slot_btns.size():
		var id := str(Game.slots[i])
		slot_btns[i].show_item(id, Game.count(id) if id != "" else 0, i == hot_sel, i == _picked)


## Settings switches for the parts of the HUD that are off by default ("fps", "camera_pad").
func set_option(option: String, on: bool) -> void:
	match option:
		"fps":
			fps_label.visible = on
			fps_check.set_pressed_no_signal(on)
		"camera_pad":
			cam_pad.visible = on
			cam_pad_check.set_pressed_no_signal(on)


## A small bar for progress (crop growth, wool, an action), Sims-green unless given a colour.
func meter(v: float, sz := Vector2(150, 10), col := Color(0.5, 0.84, 0.36)) -> Meter:
	return Meter.new(v, sz, col)


const NEED_INFO := {
	"energy": ["Energy", "bolt", Color(0.95, 0.75, 0.25)],
	"fullness": ["Hunger", "bowl", Color(0.55, 0.78, 0.4)],
	"happiness": ["Happiness", "smile", Color(0.98, 0.62, 0.3)],
	"love": ["Love", "heart", Color(0.92, 0.36, 0.46)],
	"warmth": ["Warmth", "flame", Color(0.95, 0.5, 0.22)],
	"fitness": ["Fitness", "dumbbell", Color(0.45, 0.68, 0.9)],
}


## The needs panel, top left under the Menu button: six needs in one column, each an icon badge,
## a name and a bar whose arrows show which way it's heading. Above them, while she's busy, what
## she's doing and a Stop button.
func _build_needs() -> void:
	var pc := PanelContainer.new()
	needs_panel = pc
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	now_row = HBoxContainer.new()
	now_row.add_theme_constant_override("separation", 8)
	now_label = _label("", 14, GOLD)
	now_label.custom_minimum_size = Vector2(90, 0)
	now_row.add_child(now_label)
	now_meter = meter(0.0, Vector2(150, 12))
	now_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	now_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now_row.add_child(now_meter)
	var stop := _button("Stop", func(): stop_activity_pressed.emit())
	stop.add_theme_font_size_override("font_size", 12)
	now_row.add_child(stop)
	now_row.visible = false
	vb.add_child(now_row)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 8)
	for need in Game.NEEDS:
		var info: Array = NEED_INFO[need]
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 7)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var badge := Panel.new()
		badge.custom_minimum_size = Vector2(28, 28)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", _sb_flat(info[2].darkened(0.45), 14, info[2], 0.0))
		var ic := Icon.new(info[1])
		ic.col = Color(1.0, 0.96, 0.88)
		badge.add_child(ic)
		cell.add_child(badge)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(_label(info[0], 12, Color(0.9, 0.85, 0.76)))
		var m := Meter.new(1.0, Vector2(118, 12))
		col.add_child(m)
		cell.add_child(col)
		grid.add_child(cell)
		needs_meters[need] = m
		needs_cells[need] = cell
		_need_prev[need] = float(Game.get(need))
		_need_rate[need] = 0.0
	vb.add_child(grid)
	pc.add_child(vb)
	root.add_child(pc)
	_place(pc, 0.0, 0.0, Vector2(16, 62))
	# the action bar over her head
	act_bubble = PanelContainer.new()
	act_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act_bubble.add_theme_stylebox_override("panel", _sb(Color(0.17, 0.13, 0.11, 0.9), 10, BORDER, 6.0))
	var ab := VBoxContainer.new()
	ab.add_theme_constant_override("separation", 3)
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act_label = _label("", 13)
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ab.add_child(act_label)
	act_meter = meter(0.0, Vector2(120, 10))
	ab.add_child(act_meter)
	act_bubble.add_child(ab)
	act_bubble.visible = false
	root.add_child(act_bubble)


func _update_needs(delta: float) -> void:
	_need_t += delta
	var sample := _need_t >= 0.5
	for need in needs_meters:
		var v := float(Game.get(need))
		if sample:
			var inst: float = (v - float(_need_prev[need])) / _need_t
			_need_rate[need] = lerpf(float(_need_rate[need]), inst, 0.35)
			_need_prev[need] = v
		var r: float = _need_rate[need]
		var t := 0
		if r > 1.5:
			t = 2
		elif r > 0.04:
			t = 1
		elif r < -1.5:
			t = -2
		elif r < -0.04:
			t = -1
		needs_meters[need].set_value(v / 100.0, t)
	if sample:
		_need_t = 0.0
		needs_cells["warmth"].tooltip_text = "Warmth: weather, time of day, being indoors, and her sweater.\nWearing: %s" % ("her thin city coat" if Game.worn_quality <= 1 else "a %s sweater she knit" % Game.stars(Game.worn_quality))
		needs_cells["fitness"].tooltip_text = "Fitness: walking and farm work. Fitter means faster walking and less tiring work."
		needs_cells["happiness"].tooltip_text = "Happiness: knitting, animals, books and good food. Low needs drag it down."
		needs_cells["love"].tooltip_text = "Love: time with people. Talk, give gifts, keep your promises."


## Shows what she's doing as a bar over her head and in the needs panel. Called every frame by main.gd.
func update_activity(text: String, progress: float, screen_pos: Vector2, show: bool, can_stop := true) -> void:
	act_bubble.visible = show
	now_row.visible = show
	if not show:
		return
	act_label.text = text
	act_meter.set_value(progress)
	now_label.text = text
	now_meter.set_value(progress)
	now_row.get_child(2).visible = can_stop
	act_bubble.reset_size()
	var vs := root.get_viewport_rect().size
	var p := screen_pos - Vector2(act_bubble.size.x * 0.5, act_bubble.size.y)
	p.x = clampf(p.x, 8.0, vs.x - act_bubble.size.x - 8.0)
	p.y = clampf(p.y, 64.0, vs.y - act_bubble.size.y - 8.0)
	act_bubble.position = p.round()


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
	cam_pad = pc
	pc.visible = false # off unless switched on in settings: the keys and the trackpad do it all
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
	_place(pc, 1.0, 1.0, Vector2(16, 66)) # bottom right, above the clock
	set_cam_locked(true)


## Shows the lock as closed (camera follows your character) or open (free camera).
func set_cam_locked(on: bool) -> void:
	cam_locked = on
	lock_btn.set_pressed_no_signal(on)
	lock_icon.set_kind("lock" if on else "unlock", Color(1.0, 0.92, 0.7) if on else TEXT)
	lock_btn.tooltip_text = "Camera locked to your character. Click to unlock (Space)" if on else "Free camera. Click to lock onto your character (Space)"


## Build & Buy: tabs for indoors and the yard, and a grid of cards with a rendered picture of
## each item (see thumbs.gd), its name and price. Cards you can't afford dim out.
func _build_catalog() -> void:
	catalog_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	var title := _label("Build & Buy", 20, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	expand_btn = _button("Expand House", func(): expand_pressed.emit())
	head.add_child(expand_btn)
	vb.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	var group := ButtonGroup.new()
	var pages: Array[Control] = []
	var sections := [["Indoors", Catalog.INDOOR], ["Yard & Garden", Catalog.OUTDOOR]]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(408, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for si in sections.size():
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for id in sections[si][1]:
			var info: Dictionary = Catalog.ITEMS[id]
			var item_id: String = id
			var b := _button("%s\n%dc" % [info["name"], info["price"]], func(): item_chosen.emit(item_id))
			b.custom_minimum_size = Vector2(128, 138)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 112)
			b.add_theme_font_size_override("font_size", 12)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.tooltip_text = "%s · %dc" % [info["name"], info["price"]]
			grid.add_child(b)
			item_buttons[id] = b
		grid.visible = si == 0
		stack.add_child(grid)
		pages.append(grid)
		var tab := _button(sections[si][0], func():
			for k in pages.size():
				pages[k].visible = k == si)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = si == 0
		tabs.add_child(tab)
	vb.add_child(scroll)
	vb.add_child(_label("R rotates · right-click cancels · click a placed item to move or sell it", 11, Color(0.85, 0.8, 0.7)))
	catalog_panel.add_child(vb)
	catalog_panel.visible = false
	root.add_child(catalog_panel)
	_place(catalog_panel, 1.0, 0.5, Vector2(16, 0))
	var th = preload("res://scripts/thumbs.gd").new()
	add_child(th)
	th.thumb_ready.connect(func(id: String, tex: Texture2D):
		if item_buttons.has(id):
			item_buttons[id].icon = tex)
	thumbs = th


## Starts rendering the catalog pictures (main.gd calls this once the world is up).
func render_thumbnails() -> void:
	thumbs.render(Catalog.INDOOR + Catalog.OUTDOOR)


func _build_holding() -> void:
	holding_bar = HBoxContainer.new()
	holding_bar.add_theme_constant_override("separation", 8)
	holding_bar.add_child(_button("Rotate  (R)", func(): rotate_pressed.emit()))
	sell_btn = _button("Sell", func(): sell_pressed.emit())
	holding_bar.add_child(sell_btn)
	holding_bar.add_child(_button("Cancel  (Esc)", func(): cancel_pressed.emit()))
	holding_bar.visible = false
	root.add_child(holding_bar)
	_place(holding_bar, 0.5, 1.0, Vector2(0, 96)) # above the hotbar


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	toast_label = _label("", 17)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(toast_label)
	toast_meter = meter(0.0, Vector2(220, 12))
	toast_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast_meter.visible = false
	vb.add_child(toast_meter)
	toast_panel.add_child(vb)
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
	_place(dlg_panel, 0.5, 1.0, Vector2(0, 96))


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


func make_icon(kind: String) -> Control:
	return Icon.new(kind)


func _build_chat() -> void:
	chat = preload("res://scripts/chat_panel.gd").new()
	chat.build(self)
	root.add_child(chat)
	_place(chat, 0.5, 1.0, Vector2(0, 96))


func is_chat_open() -> bool:
	return chat != null and chat.visible


func _build_menu() -> void:
	pie = preload("res://scripts/pie_menu.gd").new()
	pie.hud = self
	root.add_child(pie)


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

[b]Live mode:[/b] click the ground to walk; hold [b]Shift[/b] to jog. Click things (chair, bed, kitchen, soil plots, sheep, shipping bin) for a menu of actions.
[b]Farming:[/b] plant seeds in the soil plots, water them every day, harvest when they glow. Eat crops at the kitchen or ship them.
[b]Build & Buy[/b] ([b]B[/b], or Build on the bar): pick furniture from the catalog and click to place it. [b]R[/b] rotates, right-click cancels. Click placed furniture to move it or sell it back.
[b]Carrying things:[/b] what she carries is in the bar along the bottom. [b]1[/b] to [b]9[/b] pick a slot, [b]I[/b] opens the bag.
[b]Tools:[/b] with a tool in her hand, a click uses it. To dig a new bed, right-click open ground on her farm and pick Dig bed (never indoors). The watering can waters, the shears shear, the shovel clears a bed you dug, the axe chops wood from a tree and the scythe cuts hay from long grass. Her needs are the bars top left.
[b]Camera:[/b] WASD / arrow keys, or two-finger swipe on the trackpad to pan · pinch or scroll to zoom · [b]Q[/b]/[b]E[/b] rotate · [b]Space[/b] locks the camera onto your character · [b]C[/b] toggles walls. Settings can show on-screen camera buttons.
[b]Maple Grove:[/b] follow the road east (or click the signpost) to town. Sell sweaters to Rosa at the market for today's price, buy wool and sheep from Theo, and buy Rosewood Cottage from Mabel. Furnish it and it earns rent every morning. Talk to villagers and bring gifts to earn hearts: more hearts, better deals.
[b]Sheep pen:[/b] in the story, buy wood from Gus at Builder's Delight. [b]F[/b] builds the pen: click to lay a panel (1 wood), right-click to take one up, [b]T[/b] switches to the gate. [b]G[/b] crafts a gate from 2 wood. Walk up behind sheep and they move away from you.
[b]People:[/b] talk to villagers every day and bring gifts. Each has a favourite, and things they like. Rowan, up on the hill, opens up slowly, one conversation at a time.
[b]Journal:[/b] memories that come back while she knits, and the days that matter, are written in the [b]Journal[/b] (Menu, or [b]Esc[/b]).
[b]Days:[/b] sleep in your bed to start a new day. Watered crops grow overnight. The game saves when you sleep and when you quit. Sound, music, picture quality and full screen are in [b]Settings[/b]."""
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
	if not on:
		set_holding(false)


func set_holding(on: bool, sell_value := 0) -> void:
	holding_bar.visible = on
	sell_btn.visible = sell_value > 0
	sell_btn.text = "Sell for %dc  (Del)" % sell_value


func set_expand_text(text: String, enabled: bool) -> void:
	expand_btn.text = text
	expand_btn.disabled = not enabled


## A short notice at the top. With a progress (0..1) it also shows a bar.
func show_toast(text: String, progress := -1.0) -> void:
	toast_label.text = text
	toast_meter.visible = progress >= 0.0
	if progress >= 0.0:
		toast_meter.set_value(progress)
	toast_panel.reset_size()
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.6)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.6)


## Opens the action ring at a screen point. actions: Array of {"id", "label", "enabled"} and
## optional "group", "progress", "hint" (see pie_menu.gd); cb receives the chosen id.
func show_menu(screen_pos: Vector2, title: String, actions: Array, cb: Callable) -> void:
	pie.open(screen_pos, title, actions, cb)


func hide_menu() -> void:
	pie.close()


func is_menu_open() -> bool:
	return pie.is_open()


func fade_sleep() -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.tween_interval(0.9)
	tw.tween_property(fade, "color:a", 0.0, 0.8)


func _process(_delta: float) -> void:
	_fps_t -= _delta
	if _fps_t <= 0.0 and fps_label.visible:
		_fps_t = 0.5
		var fps := Engine.get_frames_per_second()
		fps_label.text = "%d FPS" % fps
		fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if fps >= 50 else (Color(1.0, 0.85, 0.4) if fps >= 30 else Color(1.0, 0.5, 0.45)))
	res_labels["coins"].text = "%d" % Game.coins
	_update_slots()
	_update_needs(_delta)
	clock_label.text = "%s, Day %d   ·   %s" % [Game.season_name(), Game.day_of_season(), Game.clock_text()]
	if catalog_panel.visible:
		for id in item_buttons:
			item_buttons[id].disabled = Game.coins < int(Catalog.ITEMS[id]["price"])


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
	for c in chrome:
		tw.tween_property(c, "modulate:a", 0.0, 0.35)
	tw.tween_property(story_bars[0], "offset_bottom", 54.0, 0.45)
	tw.tween_property(story_bars[1], "offset_top", -54.0, 0.45)


func story_end() -> void:
	story_box.visible = false
	story_clear_choices()
	var tw := create_tween().set_parallel(true)
	for c in chrome:
		tw.tween_property(c, "modulate:a", 1.0, 0.4)
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


# --- memory threads and the journal --------------------------------------------------

## A memory thread plays in the past: the world fades to warm sepia, softer at the edges, with a
## slow drift of grain, like an old photo. The story box stays sharp on top.
func _build_memory() -> void:
	memory_rect = ColorRect.new()
	memory_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	memory_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.8);
	float edge = smoothstep(0.18, 0.75, length(d));
	vec3 c = textureLod(screen_tex, SCREEN_UV, edge * 2.5 * amount).rgb;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 sepia = vec3(l * 1.08 + 0.06, l * 0.92 + 0.04, l * 0.72 + 0.03);
	float grain = fract(sin(dot(floor(SCREEN_UV * 420.0) + floor(TIME * 8.0), vec2(12.9898, 78.233))) * 43758.55);
	sepia += (grain - 0.5) * 0.035;
	sepia = mix(sepia, vec3(0.98, 0.9, 0.78), edge * 0.55);
	COLOR = vec4(mix(c, sepia, amount), 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("amount", 0.0)
	memory_rect.material = m
	memory_rect.visible = false
	root.add_child(memory_rect)


## Fades the memory look in or out over `secs`. Awaitable.
func set_memory(on: bool, secs := 1.2) -> void:
	if _memory_tween:
		_memory_tween.kill()
	var m := memory_rect.material as ShaderMaterial
	memory_rect.visible = true
	var from := _memory_amount()
	_memory_tween = create_tween()
	_memory_tween.tween_method(func(v): m.set_shader_parameter("amount", v), from, 1.0 if on else 0.0, maxf(secs, 0.01))
	await _memory_tween.finished
	memory_rect.visible = on


func memory_on() -> bool:
	return memory_rect.visible and _memory_amount() > 0.5


## The shader parameter reads back null until something sets it, so default to 0.
func _memory_amount() -> float:
	var v = (memory_rect.material as ShaderMaterial).get_shader_parameter("amount")
	return float(v) if v != null else 0.0


func _build_journal() -> void:
	journal_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("Journal", 24, GOLD))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	journal_list = VBoxContainer.new()
	journal_list.add_theme_constant_override("separation", 14)
	journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(journal_list)
	vb.add_child(sc)
	var close := _button("Close", func(): journal_panel.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close)
	journal_panel.add_child(vb)
	journal_panel.visible = false
	root.add_child(journal_panel)
	_place(journal_panel, 0.5, 0.5, Vector2.ZERO)


## Shows the journal: Game.journal() entries, newest first. Memories are marked with a thread.
func open_journal() -> void:
	click("ui_open")
	for c in journal_list.get_children():
		c.queue_free()
	var entries: Array = Game.journal()
	if entries.is_empty():
		journal_list.add_child(_label("Nothing written yet. Some days are like that.", 15, Color(TEXT, 0.7)))
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var head := _label(("~ " if e.get("kind", "") == "memory" else "") + str(e.get("title", "")), 18, GOLD)
		var when := _label("Day %d%s" % [int(e.get("day", 1)), "  ·  a memory" if e.get("kind", "") == "memory" else ""], 12, Color(TEXT, 0.6))
		var body := _label(str(e.get("text", "")), 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(520, 0)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		for c in [head, when, body]:
			box.add_child(c)
		journal_list.add_child(box)
	journal_panel.visible = true
	journal_opened.emit()



# --- settings and the title screen --------------------------------------------------------------

## A button that needs a second click within 3 seconds (for anything you can't undo).
func _confirm_then(b: Button, ask: String, cb: Callable) -> void:
	if b.has_meta("armed") and b.get_meta("armed"):
		b.set_meta("armed", false)
		b.text = str(b.get_meta("label"))
		cb.call()
		return
	b.set_meta("label", b.text)
	b.set_meta("armed", true)
	b.text = ask
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(b) and b.get_meta("armed", false):
			b.set_meta("armed", false)
			b.text = str(b.get_meta("label")))


func _slider_row(vb: VBoxContainer, text: String, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := _label(text, 16)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	vb.add_child(row)
	return s


func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.add_child(_label("Settings", 24, GOLD))
	graphics_btn = _button("Graphics: High", func(): graphics_pressed.emit())
	graphics_btn.tooltip_text = "High: every effect. Medium: no light bounce or reflections, less grass. Low: for slower computers."
	graphics_btn.custom_minimum_size = Vector2(200, 36)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var gl := _label("Picture", 16)
	gl.custom_minimum_size = Vector2(120, 0)
	row.add_child(gl)
	row.add_child(graphics_btn)
	vb.add_child(row)
	music_slider = _slider_row(vb, "Music", 0.7)
	sound_slider = _slider_row(vb, "Sound", 0.8)
	for s in [music_slider, sound_slider]:
		s.value_changed.connect(func(_v): volumes_changed.emit(music_slider.value, sound_slider.value))
	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Full screen"
	fullscreen_check.focus_mode = Control.FOCUS_NONE
	fullscreen_check.toggled.connect(func(on): click(); fullscreen_toggled.emit(on))
	vb.add_child(fullscreen_check)
	fps_check = CheckButton.new()
	fps_check.text = "Show frames per second"
	cam_pad_check = CheckButton.new()
	cam_pad_check.text = "On-screen camera buttons"
	for pair in [[fps_check, "fps"], [cam_pad_check, "camera_pad"]]:
		var cb: CheckButton = pair[0]
		var option: String = pair[1]
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on): click(); set_option(option, on); hud_option.emit(option, on))
		vb.add_child(cb)
	vb.add_child(_label("Music and sounds are placeholders made in code (tools/make_audio.py).", 12, Color(TEXT, 0.55)))
	_build_god_mode(vb)
	var close := _button("Close", func(): settings_panel.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close)
	settings_panel.add_child(vb)
	settings_panel.visible = false
	root.add_child(settings_panel)
	_place(settings_panel, 0.5, 0.5, Vector2.ZERO)


## God mode: set the time of day and the weather by hand, and stop the clock.
func _build_god_mode(vb: VBoxContainer) -> void:
	vb.add_child(HSeparator.new())
	vb.add_child(_label("God mode", 18, GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := _label("Time", 16)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	god_time_slider = HSlider.new()
	god_time_slider.min_value = 6.0
	god_time_slider.max_value = 23.75 # midnight is bedtime: past it she passes out
	god_time_slider.step = 0.25
	god_time_slider.custom_minimum_size = Vector2(170, 24)
	god_time_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	god_time_slider.focus_mode = Control.FOCUS_NONE
	row.add_child(god_time_slider)
	god_time_label = _label("8:00 AM", 16)
	god_time_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(god_time_label)
	god_time_slider.value_changed.connect(func(v: float):
		god_time_label.text = clock_text(v)
		god_time.emit(v))
	vb.add_child(row)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	var wl := _label("Weather", 16)
	wl.custom_minimum_size = Vector2(120, 0)
	wrow.add_child(wl)
	for w in ["clear", "rain"]:
		var b := _button("Clear" if w == "clear" else "Rain", func():
			click()
			god_weather.emit(w)
			show_god_weather(w))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(100, 34)
		god_weather_btns[w] = b
		wrow.add_child(b)
	vb.add_child(wrow)
	god_freeze_check = CheckButton.new()
	god_freeze_check.text = "Stop the clock"
	god_freeze_check.focus_mode = Control.FOCUS_NONE
	god_freeze_check.toggled.connect(func(on): click(); god_freeze.emit(on))
	vb.add_child(god_freeze_check)
	# the world editor: only the admin sees this (main.gd shows it; see scripts/god_mode.gd)
	god_edit_check = CheckButton.new()
	god_edit_check.text = "Edit the world"
	god_edit_check.focus_mode = Control.FOCUS_NONE
	god_edit_check.toggled.connect(func(on): click(); god_edit.emit(on))
	god_edit_check.visible = false
	vb.add_child(god_edit_check)
	god_edit_note = _label("Admin only. Move, turn, copy or delete anything and paint roads.\nSaved to data/world_layout.json: the map every player gets.", 12, Color(TEXT, 0.55))
	god_edit_note.visible = false
	vb.add_child(god_edit_note)


## Shows the god mode controls at the game's current time and weather (main.gd, when settings open).
func show_god_state(hour: float, weather: String, frozen: bool) -> void:
	god_time_slider.set_value_no_signal(clampf(hour, god_time_slider.min_value, god_time_slider.max_value))
	god_time_label.text = clock_text(hour)
	show_god_weather(weather)
	god_freeze_check.set_pressed_no_signal(frozen)


## The world editor's switch: shown only to the admin, set to whether the editor is on.
func show_god_edit(admin: bool, on: bool) -> void:
	god_edit_check.visible = admin
	god_edit_note.visible = admin
	god_edit_check.set_pressed_no_signal(on)


func show_god_weather(weather: String) -> void:
	for k in god_weather_btns:
		(god_weather_btns[k] as Button).set_pressed_no_signal(k == weather)


static func clock_text(hour: float) -> String:
	var h := int(hour) % 24
	var m := int(round((hour - floorf(hour)) * 60.0)) % 60
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, m, "AM" if h < 12 else "PM"]


func open_settings(music_v := -1.0, sound_v := -1.0, fullscreen := false) -> void:
	click("ui_open")
	if music_v >= 0.0:
		music_slider.set_value_no_signal(music_v)
	if sound_v >= 0.0:
		sound_slider.set_value_no_signal(sound_v)
	fullscreen_check.set_pressed_no_signal(fullscreen or DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN)
	settings_panel.visible = true
	settings_panel.move_to_front()


func _build_title_screen() -> void:
	title_layer = Control.new()
	title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	# a warm dark wash from the left, so the words sit on something calm and the farm shows through
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.06, 0.05, 0.88))
	g.set_color(1, Color(0.09, 0.06, 0.05, 0.0))
	g.add_point(0.45, Color(0.09, 0.06, 0.05, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(wash)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var name_l := _label("Knitting Empire", 64, GOLD)
	name_l.add_theme_constant_override("outline_size", 10)
	name_l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.06, 0.9))
	vb.add_child(name_l)
	vb.add_child(_label("Cast on a new life.", 22, Color(TEXT, 0.88)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	vb.add_child(gap)
	title_continue_btn = _button("Continue", func(): title_continue.emit())
	title_new_btn = _button("New Game", func():
		if title_continue_btn.visible:
			_confirm_then(title_new_btn, "Start over? Click again", func(): title_new_game.emit())
		else:
			title_new_game.emit())
	var settings_btn := _button("Settings", func(): open_settings())
	var quit_btn := _button("Quit", func(): title_quit.emit())
	for b in [title_continue_btn, title_new_btn, settings_btn, quit_btn]:
		b.custom_minimum_size = Vector2(260, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 19)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		vb.add_child(b)
	title_layer.add_child(vb)
	_place(vb, 0.0, 0.5, Vector2(96, 0))
	vb.offset_top = -190
	var foot := _label("Prototype · Nov 2026", 12, Color(TEXT, 0.5))
	title_layer.add_child(foot)
	_place(foot, 0.0, 1.0, Vector2(24, 18))
	title_layer.visible = false
	root.add_child(title_layer)


func show_title(has_save: bool) -> void:
	title_continue_btn.visible = has_save
	title_new_btn.text = "New Game"
	title_new_btn.set_meta("armed", false)
	title_layer.visible = true
	title_layer.modulate.a = 1.0
	goal_panel.visible = false
	for c in chrome:
		c.modulate.a = 0.0
	settings_panel.move_to_front()


func title_visible() -> bool:
	return title_layer.visible


func hide_title() -> void:
	settings_panel.visible = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_layer, "modulate:a", 0.0, 0.5)
	for c in chrome:
		tw.tween_property(c, "modulate:a", 1.0, 0.6)
	await tw.finished
	title_layer.visible = false
	goal_panel.visible = goal_label.text != ""


# --- tips: a one-time nudge the first time something becomes possible (main.gd _update_tips) ----

func _build_tip() -> void:
	tip_panel = PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var head := _label("Tip", 15, GOLD)
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(head)
	tip_label = _label("", 15)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(480, 0)
	hb.add_child(tip_label)
	tip_panel.add_child(hb)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tip_panel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			tip_panel.visible = false)
	tip_panel.visible = false
	root.add_child(tip_panel)
	_place(tip_panel, 0.5, 1.0, Vector2(0, 98))


func show_tip(text: String, secs := 11.0) -> void:
	tip_label.text = text
	tip_panel.reset_size()
	tip_panel.visible = true
	tip_panel.modulate.a = 0.0
	click("ui_open")
	if _tip_tween:
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(tip_panel, "modulate:a", 1.0, 0.4)
	_tip_tween.tween_interval(secs)
	_tip_tween.tween_property(tip_panel, "modulate:a", 0.0, 0.8)
	_tip_tween.tween_callback(func(): tip_panel.visible = false)
