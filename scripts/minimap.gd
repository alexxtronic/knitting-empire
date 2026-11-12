class_name Minimap
extends Control
## The little map in the top right corner, under the coins. A second camera looks straight down on
## the world round Nora (a few times a second, into a small SubViewport) and her, the dog and the
## villagers are drawn on top as dots. It turns with the game camera, so up on the map is the way
## the screen looks. Click it and she walks there (main.minimap_walk); the mouse wheel or the + and -
## buttons zoom it.

const SIZE := 200.0 # on screen, px
const RES := 256 # the render, px
const SPANS := [40.0, 70.0, 110.0, 160.0] # metres across, nearest to farthest
const HEIGHT := 150.0 # the map camera's height above the ground
const EVERY := 0.25 # s between renders while nothing turns

var main: Node # main.gd
var zoom := 1 # index into SPANS
var target = null # Vector3 she was sent to from the map (a ring until she's there), or null

var _sv: SubViewport
var _cam: Camera3D
var _t := 0.0
var _centre := Vector3.ZERO # where the map camera was for the picture on show
var _yaw := 0.0
var _span := 70.0
var _rendered := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click to walk there. Mouse wheel zooms."
	_sv = SubViewport.new()
	_sv.size = Vector2i(RES, RES)
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sv.msaa_3d = Viewport.MSAA_DISABLED
	_sv.positional_shadow_atlas_size = 0
	add_child(_sv)
	_sv.world_3d = get_viewport().world_3d # the game's world, seen from above
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 1.0
	_cam.far = HEIGHT + 60.0
	# its own plain light: no mist, no GI, no sky glow, so the map reads the same at any hour
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.5, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam.environment = env
	_sv.add_child(_cam)
	_cam.current = true
	for i in 2:
		var b := Button.new()
		b.text = "+" if i == 0 else "-"
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Zoom in" if i == 0 else "Zoom out"
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(28, 28)
		b.size = Vector2(28, 28)
		b.position = Vector2(6 + i * 32, SIZE - 34)
		b.pressed.connect(set_zoom.bind(-1 if i == 0 else 1))
		add_child(b)


func set_zoom(step: int) -> void:
	zoom = clampi(zoom + step, 0, SPANS.size() - 1)
	_t = 0.0 # render again now


func span() -> float:
	return SPANS[zoom]


## Who the map follows: the dog while the player steers him, else Nora.
func _hero() -> Node3D:
	if main.dog != null and main.dog.controlled:
		return main.dog
	return main.player


func _process(delta: float) -> void:
	if main == null or not is_visible_in_tree():
		return
	if target != null:
		var h := _hero()
		var left := Vector2(h.position.x - target.x, h.position.z - target.z).length()
		if left < 0.8 or h.path.is_empty():
			target = null
	var yaw: float = main.cam_yaw_goal
	_t -= delta
	if _t <= 0.0 or absf(angle_difference(yaw, _yaw)) > 0.001:
		_t = EVERY
		_render(yaw)
	queue_redraw()


func _render(yaw: float) -> void:
	_yaw = yaw
	_span = span()
	var h := _hero().position
	_centre = Vector3(h.x, 0, h.z)
	_cam.size = _span
	_cam.position = _centre + Vector3(0, HEIGHT, 0)
	_cam.rotation = Vector3(-PI * 0.5, yaw, 0) # straight down; screen up is the way the game camera looks
	_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	_rendered = true


## A point on the ground to the map's pixels (and back), for the picture on show.
func to_map(p: Vector3) -> Vector2:
	var rel := Vector2(p.x - _centre.x, p.z - _centre.z)
	var right := Vector2(cos(_yaw), -sin(_yaw))
	var up := Vector2(-sin(_yaw), -cos(_yaw))
	var k := SIZE / _span
	return Vector2(SIZE * 0.5 + rel.dot(right) * k, SIZE * 0.5 - rel.dot(up) * k)


func to_world(m: Vector2) -> Vector3:
	var k := _span / SIZE
	var a := (m.x - SIZE * 0.5) * k
	var b := (SIZE * 0.5 - m.y) * k
	var right := Vector2(cos(_yaw), -sin(_yaw))
	var up := Vector2(-sin(_yaw), -cos(_yaw))
	var w := right * a + up * b
	return Vector3(_centre.x + w.x, 0, _centre.z + w.y)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				click(mb.position)
			MOUSE_BUTTON_WHEEL_UP:
				set_zoom(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				set_zoom(1)
		accept_event()
	elif e is InputEventMagnifyGesture:
		var g := e as InputEventMagnifyGesture
		if absf(g.factor - 1.0) > 0.04:
			set_zoom(-1 if g.factor > 1.0 else 1)
		accept_event()


## A click at a point of the map: she walks there. True if she set off.
func click(m: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).has_point(m):
		return false
	var g := to_world(m)
	if main.minimap_walk(g):
		target = g
		return true
	return false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_rect(r, Color(0.22, 0.3, 0.2))
	if _rendered:
		draw_texture_rect(_sv.get_texture(), r, false)
	# villagers
	for v in main.villagers:
		var n := v as Node3D
		if n != null and is_instance_valid(n) and n.visible:
			_dot(to_map(n.global_position), 3.0, Color(0.4, 0.75, 1.0), Color(0.1, 0.15, 0.25))
	# the dog
	if main.dog != null and is_instance_valid(main.dog) and main.dog.visible and not main.dog.controlled:
		_dot(to_map(main.dog.global_position), 3.0, Color(0.85, 0.55, 0.25), Color(0.25, 0.14, 0.06))
	# where she's headed
	if target != null:
		var tp := to_map(target)
		draw_arc(tp, 5.0, 0, TAU, 20, Color(0.1, 0.1, 0.1, 0.6), 3.0)
		draw_arc(tp, 5.0, 0, TAU, 20, Color(0.6, 0.95, 0.5), 1.6)
	# her (or the dog while he's played): an arrow the way she faces
	var h := _hero()
	var hp := to_map(h.global_position)
	var f := h.global_transform.basis.z # facing, on the ground (they turn with rotation.y = atan2(x, z))
	var f2 := Vector2(f.x, f.z)
	if f2.length() < 0.01:
		f2 = Vector2(0, -1)
	var tip := to_map(h.global_position + Vector3(f2.normalized().x, 0, f2.normalized().y)) - hp
	var dir := tip.normalized() if tip.length() > 0.001 else Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([hp + dir * 10.0, hp - dir * 6.0 + side * 7.0, hp - dir * 2.5, hp - dir * 6.0 - side * 7.0])
	draw_colored_polygon(pts, Color(0.95, 0.78, 0.3))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.12, 0.05), 2.0, true)
	# frame
	draw_rect(r, Color(0.95, 0.78, 0.3, 0.9), false, 2.0)


func _dot(p: Vector2, rad: float, fill: Color, edge: Color) -> void:
	if not Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).grow(-2).has_point(p):
		return
	draw_circle(p, rad + 1.2, edge)
	draw_circle(p, rad, fill)
