## Cinematic mode: a free camera that leaves Nora behind and flies anywhere, from a few
## centimetres off a flower to 300 m above the farm, and takes pictures for the photo album.
##
## P (or Menu > Cinematic camera) goes in and out. While it's on the clock stops, Nora stays where
## she is, the HUD is hidden and every key and the mouse come here (main.gd hands them over):
## WASD flies, the mouse looks round (the arrow keys too), E / Space climb, Q / C sink, Shift is
## faster, Alt slower, the wheel sets the cruising speed, F or a click takes a photo, Esc or P
## goes back to Nora. Photos are PNGs in `dir` (user://photos), named by the real date and time
## and the day and hour in the game.
extends Node

const Keys = preload("res://scripts/keybinds.gd")
const MAX_HEIGHT := 300.0
const GROUND_CLEAR := 0.15 # how close to the ground it may go
const BOUNDS := Rect2(-90, -100, 260, 220) # x and z: the map (x -8..92, z -22..20) with plenty of sky round it
const SPEED := 5.0 # metres a second at speed x1
const FAST := 6.0 # Shift
const SLOW := 0.2 # Alt
const LOOK := 0.0025 # radians a pixel of mouse
const KEY_LOOK := 1.6 # radians a second for the arrow keys
const GLIDE := 3.5 # how quickly the camera takes up a new speed (higher is snappier)

## Where the photos go. The autotest points this at its own folder.
static var dir := "user://photos"

var main: Node
var active := false
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var yaw_goal := 0.0
var pitch_goal := 0.0
var speed_scale := 1.0 # the mouse wheel: x0.1 .. x10
var last_photo := "" # the path of the newest photo, for the autotest
var key_down := {} # Key -> true: what the autotest holds (the real keyboard is read through Input)

var _clock_was := true
var _cam0 := {} # the camera's settings before, put back on the way out
var _layer: CanvasLayer
var _hint: Label
var _readout: Label
var _toast: Label
var _flash: ColorRect
var _toast_t := 0.0
var _shooting := false


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	_layer.visible = false
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash)
	_hint = _text("WASD fly   Mouse look   E / Q up and down   Shift faster   Wheel speed   F photo   Esc back to Nora", 15)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -18
	_layer.add_child(_hint)
	_readout = _text("", 14)
	_readout.position = Vector2(18, 16)
	_layer.add_child(_readout)
	_toast = _text("", 18)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 22
	_toast.modulate.a = 0.0
	_layer.add_child(_toast)


func _text(s: String, size: int) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.93, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Whether it can start now: not in a story scene, asleep, knitting, on the title or in the world editor.
func can_enter() -> bool:
	return not active and not main.sleeping and not main.title_on and not main.knit.active \
		and not main.story.is_playing() and not main.god.active and not main.hud.is_chat_open()


func toggle() -> void:
	if active:
		leave()
	else:
		enter()


func enter() -> void:
	if not can_enter():
		return
	active = true
	var cam: Camera3D = main.cam
	_cam0 = {"near": cam.near, "far": cam.far, "fov": cam.fov, "dof": main.cam_attr.dof_blur_far_enabled,
		"shadow": main.sun.directional_shadow_max_distance}
	cam.near = 0.03 # right up to a flower
	cam.far = 2000.0 # and the whole valley from 300 m
	main.cam_attr.dof_blur_far_enabled = false
	pos = cam.global_position
	var fwd := -cam.global_transform.basis.z
	yaw = atan2(-fwd.x, -fwd.z)
	pitch = asin(clampf(fwd.y, -1.0, 1.0))
	yaw_goal = yaw
	pitch_goal = pitch
	vel = Vector3.ZERO
	key_down.clear()
	_clock_was = Game.time_running
	Game.time_running = false
	main.player.path.clear() # she stops where she is and waits
	main.hud.hide_menu()
	main.hud.game_menu.visible = false
	main.hud.visible = false
	_layer.visible = true
	_hint.visible = true
	if main._autotest_dir == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave() -> void:
	if not active:
		return
	active = false
	var cam: Camera3D = main.cam
	cam.near = float(_cam0.get("near", 0.5))
	cam.far = float(_cam0.get("far", 300.0))
	cam.fov = float(_cam0.get("fov", 32.0))
	main.cam_attr.dof_blur_far_enabled = bool(_cam0.get("dof", false))
	main.sun.directional_shadow_max_distance = float(_cam0.get("shadow", 70.0))
	Game.time_running = _clock_was
	main.hud.visible = true
	_layer.visible = false
	key_down.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main._update_camera(1.0) # straight back to Nora


func _held(keys: Array) -> bool:
	for k in keys:
		var b := Keys.key_for(k, ["cine", "move"]) # the player's key bindings
		if key_down.get(k, false) or Input.is_key_pressed(b) or Input.is_physical_key_pressed(b):
			return true
	return false


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
	if not active:
		return
	if main.sleeping or main.story.is_playing():
		leave()
		return
	# look: the arrow keys turn it too, for a trackpad without a captured mouse
	var turn := Vector2.ZERO
	if _held([KEY_LEFT]):
		turn.x += 1
	if _held([KEY_RIGHT]):
		turn.x -= 1
	if _held([KEY_UP]):
		turn.y += 1
	if _held([KEY_DOWN]):
		turn.y -= 1
	yaw_goal += turn.x * KEY_LOOK * delta
	pitch_goal = clampf(pitch_goal + turn.y * KEY_LOOK * delta, deg_to_rad(-89.0), deg_to_rad(89.0))
	var k := 1.0 - exp(-14.0 * delta)
	yaw = lerp_angle(yaw, yaw_goal, k)
	pitch = lerpf(pitch, pitch_goal, k)
	# move: forward is where it looks, up is straight up
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var want := Vector3.ZERO
	if _held([KEY_W]):
		want -= basis.z
	if _held([KEY_S]):
		want += basis.z
	if _held([KEY_D]):
		want += basis.x
	if _held([KEY_A]):
		want -= basis.x
	if _held([KEY_E, KEY_SPACE]):
		want += Vector3.UP
	if _held([KEY_Q, KEY_C]):
		want -= Vector3.UP
	var speed := SPEED * speed_scale
	if _held([KEY_SHIFT]):
		speed *= FAST
	if _held([KEY_ALT]):
		speed *= SLOW
	if want != Vector3.ZERO:
		want = want.normalized() * speed
	vel = vel.lerp(want, 1.0 - exp(-GLIDE * delta)) # a smooth glide in and out of every move
	pos = clamp_pos(pos + vel * delta)
	var cam: Camera3D = main.cam
	cam.global_transform = Transform3D(basis, pos)
	# high up, the haze that suits the ground (main.gd and lighting.gd set it each frame, before
	# this) would grey out the whole valley: thin it out on the way up
	var up := smoothstep(30.0, 250.0, pos.y)
	main.env.fog_density *= lerpf(1.0, 0.3, up)
	main.env.fog_height_density *= 1.0 - up
	# shadows reach far enough for what's on screen, and no further
	main.sun.directional_shadow_max_distance = clampf(30.0 + pos.y * 1.5, 30.0, 200.0)
	_readout.text = "Height %d m   Speed x%.1f" % [roundi(pos.y), speed_scale]


## Inside the map's sky: no lower than the ground, no higher than MAX_HEIGHT.
func clamp_pos(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, BOUNDS.position.x, BOUNDS.end.x),
		clampf(p.y, GROUND_CLEAR, MAX_HEIGHT),
		clampf(p.z, BOUNDS.position.y, BOUNDS.end.y))


## Keys while the mode is on (main.gd's _input hands them all here). Returns true if used.
func handle_key(kc: Key) -> bool:
	match Keys.map(kc, ["cine", "move"]): # the player's key bindings, as the default keys below
		KEY_ESCAPE, KEY_P:
			leave()
		KEY_F, KEY_ENTER, KEY_KP_ENTER:
			take_photo()
		KEY_H:
			_hint.visible = not _hint.visible
		_:
			return false
	return true


## The mouse while the mode is on (main.gd's _unhandled_input hands it here).
func handle_mouse(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			yaw_goal -= mm.relative.x * LOOK
			pitch_goal = clampf(pitch_goal - mm.relative.y * LOOK, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # a click after Cmd-Tab takes the mouse back
				else:
					take_photo()
			MOUSE_BUTTON_WHEEL_UP:
				speed_scale = clampf(speed_scale * 1.25, 0.1, 10.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				speed_scale = clampf(speed_scale / 1.25, 0.1, 10.0)
	elif e is InputEventPanGesture: # two fingers on a Mac trackpad look round
		var g := e as InputEventPanGesture
		yaw_goal -= g.delta.x * 0.02
		pitch_goal = clampf(pitch_goal - g.delta.y * 0.02, deg_to_rad(-89.0), deg_to_rad(89.0))


## Hides the hint for a frame, saves what the camera sees and flashes. Returns the file's path
## ("" if it couldn't be saved).
func take_photo() -> String:
	if not active or _shooting:
		return ""
	_shooting = true
	var hint_was := _hint.visible
	_hint.visible = false
	_readout.visible = false
	_toast.visible = false
	# two frames: the one already being drawn may still have the hint on it. A covered window
	# never draws, so go on after a few seconds rather than wait forever.
	for i in 2:
		var drawn := [false]
		RenderingServer.frame_post_draw.connect(func(): drawn[0] = true, CONNECT_ONE_SHOT)
		var waited := 0.0
		while not drawn[0] and waited < 3.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
	var img := get_viewport().get_texture().get_image()
	_hint.visible = hint_was
	_readout.visible = true
	_toast.visible = true
	var path := ""
	DirAccess.make_dir_recursive_absolute(dir)
	if img != null and not img.is_empty():
		path = dir.path_join(photo_name())
		if img.save_png(path) != OK:
			path = ""
	_shooting = false
	if path == "":
		_say("The photo couldn't be saved")
		return ""
	last_photo = path
	main.audio.play("ui_click", -4.0)
	_flash.color.a = 0.7
	create_tween().tween_property(_flash, "color:a", 0.0, 0.35)
	_say("Photo saved to your album")
	return path


func _say(s: String) -> void:
	_toast.text = s
	_toast_t = 2.2


## e.g. 2026-11-12_14-05-33_day3_7-30am.png: the real date and time, then the day and hour in the game.
func photo_name() -> String:
	var t := Time.get_datetime_dict_from_system()
	var h := int(Game.hour) % 24
	var m := int((Game.hour - floorf(Game.hour)) * 60.0) % 60
	var base := "%04d-%02d-%02d_%02d-%02d-%02d_day%d_%d-%02d%s" % [t.year, t.month, t.day, t.hour, t.minute, t.second,
		Game.day, 12 if h % 12 == 0 else h % 12, m, "am" if h < 12 else "pm"]
	var fname := base + ".png"
	var n := 2
	while FileAccess.file_exists(dir.path_join(fname)):
		fname = "%s_%d.png" % [base, n]
		n += 1
	return fname


## Every photo in the album, newest first (the names start with the date and time).
static func list_photos() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == "png":
			out.append(dir.path_join(f))
	out.sort()
	out.reverse()
	return out


static func delete_photo(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK
