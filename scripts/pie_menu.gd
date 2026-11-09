extends Control
## The action menu: a ring of choices around whatever you clicked. A felt puck sits at the click
## point with the thing's name above it, and the options fan out left and right in an arc.
##
## Each action is {"id", "label", "enabled"} plus, optionally:
##   "group": "Give a gift"   actions sharing a group fold into one "Give a gift…" option
##                            that opens its own ring (with a Back option)
##   "progress": 0.0..1.0     a small bar under the label (crop growth, wool regrowing...)
##   "hint": "10c · 6 hrs"    a second, smaller line. Labels written "Plant turnips  (10c · 6 hrs)"
##                            are split into label and hint automatically.
## Number keys pick options in order (see key()).

const GAP := 7.0
const INNER := 30.0 # how far the columns start from the puck
const BULGE := 30.0 # how far the middle of each column bows out

var hud # hud.gd, for the felt styles and labels
var _cb := Callable()
var _title := ""
var _center := Vector2.ZERO
var _items: Array = [] # what the current ring shows: {"id", "label", "enabled", ...}
var _pills: Array[Control] = []
var _stack: Array = [] # rings to go back to: [title, items]
var _hovered := -1
var _style := {}


## A felt puck that marks the click point, with a slowly turning running stitch.
class Puck extends Control:
	var t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(44, 44)

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c + Vector2(0, 2), 20.0, Color(0, 0, 0, 0.25))
		draw_circle(c, 20.0, Color(0.17, 0.13, 0.11, 0.94))
		draw_arc(c, 18.0, 0.0, TAU, 40, Color(0.55, 0.42, 0.28), 2.0, true)
		for i in 10:
			var a := t * 0.7 + i * TAU / 10.0
			draw_arc(c, 13.0, a, a + 0.32, 4, Color(1.0, 0.95, 0.82, 0.9), 1.8, true)
		draw_circle(c, 4.5 + sin(t * 4.0) * 0.8, Color(0.95, 0.8, 0.46))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_style = {
		"normal": hud._sb(Color(0.17, 0.13, 0.11, 0.94), 16, Color(0.55, 0.42, 0.28, 0.85), 9.0),
		"hover": hud._sb(Color(0.42, 0.31, 0.19, 0.98), 16, hud.GOLD, 9.0),
		"disabled": hud._sb(Color(0.15, 0.13, 0.12, 0.8), 16, Color(0.32, 0.26, 0.2), 9.0),
		"title": hud._sb(Color(0.3, 0.2, 0.14, 0.96), 12, hud.GOLD, 7.0),
	}


func is_open() -> bool:
	return visible


func open(screen_pos: Vector2, title: String, actions: Array, cb: Callable) -> void:
	_cb = cb
	_center = screen_pos
	_stack.clear()
	_show_ring(title, _fold(actions))


func close() -> void:
	visible = false
	_stack.clear()
	for c in get_children():
		c.queue_free()
	_pills.clear()


## Picks the n-th option (1-based) of the ring that is showing, as if clicked.
func key(n: int) -> void:
	if visible and n >= 1 and n <= _items.size():
		_pick(n - 1)


## The labels of the ring that is showing (for the autotest).
func labels() -> Array:
	return _items.map(func(a): return str(a["label"]))


# --- building a ring ------------------------------------------------------------------

## Folds grouped actions into one "Group…" option each, in the place of the group's first action.
func _fold(actions: Array) -> Array:
	var out := []
	var groups := {}
	for a in actions:
		var g := str(a.get("group", ""))
		if g == "":
			out.append(a)
			continue
		if not groups.has(g):
			groups[g] = {"id": "", "label": g + "…", "enabled": false, "children": []}
			out.append(groups[g])
		groups[g]["children"].append(a)
		groups[g]["enabled"] = groups[g]["enabled"] or bool(a.get("enabled", true))
	return out


func _show_ring(title: String, items: Array) -> void:
	for c in get_children():
		c.queue_free()
	_pills.clear()
	_title = title
	_items = items
	_hovered = -1
	visible = true
	var puck := Puck.new()
	add_child(puck)
	var title_pc := PanelContainer.new()
	title_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_pc.add_theme_stylebox_override("panel", _style["title"])
	title_pc.add_child(hud._label(title, 14, hud.GOLD))
	add_child(title_pc)
	for i in items.size():
		var p := _make_pill(items[i], i)
		add_child(p)
		_pills.append(p)
	_layout(puck, title_pc)


func _split(label: String) -> Array:
	var cut := label.find("  (")
	if cut > 0 and label.ends_with(")"):
		return [label.substr(0, cut), label.substr(cut + 3, label.length() - cut - 4)]
	return [label, ""]


func _make_pill(a: Dictionary, i: int) -> PanelContainer:
	var enabled := bool(a.get("enabled", true))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style["normal" if enabled else "disabled"])
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := _split(str(a["label"]))
	var hint := str(a.get("hint", parts[1]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if i < 9:
		var num: Label = hud._label(str(i + 1), 11, Color(0.75, 0.62, 0.42) if enabled else Color(0.45, 0.4, 0.35))
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(num)
	row.add_child(hud._label(parts[0], 15, hud.TEXT if enabled else Color(0.58, 0.53, 0.48)))
	vb.add_child(row)
	if hint != "":
		vb.add_child(hud._label(hint, 11, Color(0.88, 0.77, 0.54) if enabled else Color(0.5, 0.45, 0.4)))
	if a.has("progress"):
		vb.add_child(hud.meter(float(a["progress"]), Vector2(150, 8)))
	pc.add_child(vb)
	pc.mouse_entered.connect(_hover.bind(i, true))
	pc.mouse_exited.connect(_hover.bind(i, false))
	pc.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pc.accept_event()
			_pick(i))
	return pc


## Two columns, right then left, bowed out in the middle like an arc round the puck.
func _layout(puck: Control, title_pc: Control) -> void:
	var n := _pills.size()
	var right_n := n if n <= 1 else ceili(n / 2.0)
	var targets: Array[Vector2] = []
	targets.resize(n)
	var top := -24.0
	var bottom := 24.0
	var left := -24.0
	var right := 24.0
	for side in 2:
		var idx := range(0, right_n) if side == 0 else range(right_n, n)
		var total := -GAP
		for i in idx:
			_pills[i].size = _pills[i].get_combined_minimum_size()
			total += _pills[i].size.y + GAP
		var y := -total * 0.5
		var half := maxf(total * 0.5 + 18.0, 1.0)
		for i in idx:
			var s: Vector2 = _pills[i].size
			var cy := y + s.y * 0.5
			var k := cy / half
			var x := INNER + BULGE * (1.0 - k * k)
			targets[i] = Vector2(x, y) if side == 0 else Vector2(-x - s.x, y)
			top = minf(top, y)
			bottom = maxf(bottom, y + s.y)
			left = minf(left, targets[i].x)
			right = maxf(right, targets[i].x + s.x)
			y += s.y + GAP
	title_pc.size = title_pc.get_combined_minimum_size()
	var title_off := Vector2(-title_pc.size.x * 0.5, minf(top, -26.0) - title_pc.size.y - 8.0)
	top = title_off.y
	left = minf(left, title_off.x)
	right = maxf(right, title_off.x + title_pc.size.x)
	# keep the whole ring on screen
	var vs := get_viewport_rect().size
	var c := _center
	c.x = clampf(c.x, 10.0 - left, vs.x - 10.0 - right)
	c.y = clampf(c.y, 10.0 - top, vs.y - 10.0 - bottom)
	puck.position = c - puck.size * 0.5
	title_pc.position = c + title_off
	title_pc.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_pc, "modulate:a", 1.0, 0.18)
	for i in n:
		var p := _pills[i]
		p.pivot_offset = p.size * 0.5
		p.position = c + (Vector2(0, -p.size.y * 0.5) if targets[i].x > 0.0 else Vector2(-p.size.x, -p.size.y * 0.5))
		p.scale = Vector2(0.6, 0.6)
		p.modulate.a = 0.0
		var d := 0.025 * i
		tw.tween_property(p, "position", c + targets[i], 0.2).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 1.0, 0.12).set_delay(d)


func _hover(i: int, on: bool) -> void:
	if i >= _pills.size() or not bool(_items[i].get("enabled", true)):
		return
	var p := _pills[i]
	p.add_theme_stylebox_override("panel", _style["hover" if on else "normal"])
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2(1.06, 1.06) if on else Vector2.ONE, 0.09)
	_hovered = i if on else -1


func _pick(i: int) -> void:
	var a: Dictionary = _items[i]
	if not bool(a.get("enabled", true)):
		return
	if a.has("children"):
		_stack.append([_title, _items])
		_show_ring(str(a["label"]).trim_suffix("…"), a["children"] + [{"id": "__back", "label": "Back", "enabled": true}])
		return
	if str(a["id"]) == "__back":
		var prev: Array = _stack.pop_back()
		_show_ring(prev[0], prev[1])
		return
	var cb := _cb
	close()
	if cb.is_valid():
		cb.call(str(a["id"]))
