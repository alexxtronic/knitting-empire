## First person: the camera at Nora's eyes, so you play through them. She keeps her whole body:
## look down and there are her own arms, hands, legs and feet, walking, holding a tool, knitting.
##
## V (or Menu > First person) goes in and out, Esc comes out too. The mouse looks round (captured),
## WASD walks her the way she looks (Shift jogs), a click or E uses what's under the dot in the
## middle of the screen, with the same ring and actions as clicking it from above.
##
## Her head is hidden from this camera only: her body meshes go on drawing their shadow (head
## and all) but aren't drawn themselves, and a copy of each without the head's triangles (built
## once, sharing her skeleton and skin) is drawn instead. The model itself is never changed.
## Like cinematic.gd, main.gd hands over the camera (_update_camera returns early) and the
## keys and mouse while it's on, and it gives them back when a story scene, bed, the knitting
## game, a chat, the world editor or the cinematic camera starts.
extends Node

const World = preload("res://scripts/world.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Keys = preload("res://scripts/keybinds.gd")

const FOV := 72.0
const NEAR := 0.04
const FAR := 400.0
const FORWARD := 0.11 # metres in front of her eyes, so the camera is clear of her face
const LOOK := 0.0025 # radians a pixel of mouse
const KEY_LOOK := 1.8 # radians a second for the arrow keys
const PITCH_MIN := -82.0 # degrees: right down at her feet
const PITCH_MAX := 80.0
const BOB := 0.35 # how much of the walk's own head bob reaches the camera (0 none, 1 all)
const SHADOW := 45.0

var main: Node
var active := false
var yaw := 0.0 # where the view points: forward is (-sin yaw, 0, -cos yaw)
var pitch := 0.0
var key_down := {} # Key -> true: what the autotest holds (the real keyboard is read through Input)

var _cam0 := {}
var _walls_was := false
var _eye := Vector3.ZERO # her eyes in her own space, smoothed
var _have_eye := false
var _copies: Array = [] # [original MeshInstance3D, headless copy (or null), original cast_shadow]
var _menu_freed := false # the mouse was let go so the action ring can be clicked
var _layer: CanvasLayer
var _dot: Control
var _hint: Label
var _aim: Label
var _aim_t := 0.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 15
	_layer.visible = false
	add_child(_layer)
	_dot = _Dot.new()
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_dot)
	_aim = _text("", 16)
	_aim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim.set_anchors_preset(Control.PRESET_CENTER)
	_aim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_aim.offset_top = 16
	_layer.add_child(_aim)
	_hint = _text("WASD walk   Mouse look   Shift jog   Click or E use   V or Esc back", 14)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = 14
	_layer.add_child(_hint)


## The aiming dot in the middle of the screen.
class _Dot extends Control:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.45))
		draw_circle(Vector2.ZERO, 2.5, Color(1, 0.97, 0.9, 0.95))


func _text(s: String, size: int) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.93, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Whether it can start now (main.fp_blocked() lists what stops it).
func can_enter() -> bool:
	return not active and not main.fp_blocked() and main.player.detailed


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
	_cam0 = {"near": cam.near, "far": cam.far, "fov": cam.fov, "dof": main.cam_attr.dof_blur_far_enabled}
	cam.near = NEAR
	cam.far = FAR
	cam.fov = FOV
	main.cam_attr.dof_blur_far_enabled = false
	main.sun.directional_shadow_max_distance = SHADOW
	_walls_was = main.walls_up
	main.walls_up = true # no cut-away walls round her: she's inside the room
	var p: Node3D = main.player
	yaw = wrapf(p.rotation.y + PI, -PI, PI) # looking the way she faces
	pitch = deg_to_rad(-8.0)
	_have_eye = false
	key_down.clear()
	p.path.clear()
	main.hud.hide_menu()
	main.hud.game_menu.visible = false
	_hide_head(true)
	_layer.visible = true
	_hint.visible = true
	get_tree().create_timer(6.0).timeout.connect(func(): _hint.visible = false)
	if main._autotest_dir == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update(0.0)


func leave() -> void:
	if not active:
		return
	active = false
	var cam: Camera3D = main.cam
	cam.near = float(_cam0.get("near", 0.5))
	cam.far = float(_cam0.get("far", 300.0))
	cam.fov = float(_cam0.get("fov", 32.0))
	main.cam_attr.dof_blur_far_enabled = bool(_cam0.get("dof", false))
	main.walls_up = _walls_was
	main.player.steer = Vector3.ZERO
	main.player._ring.visible = not main.player.busy
	_hide_head(false)
	_layer.visible = false
	key_down.clear()
	_menu_freed = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# the overhead camera picks up behind her, looking the way she was looking
	main.cam_yaw_goal = yaw
	main.cam_yaw = yaw
	main.cam_target = main.player.position
	main._update_camera(1.0)


## Which way the view looks.
func forward() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


## Where her head should turn to (main._gaze_for): straight ahead along the view.
func look_point() -> Vector3:
	return main.cam.global_position + forward() * 8.0


# --- her head, hidden from this camera -------------------------------------------------

## The Head bone and every bone under it (the eyes, the jaw).
func _head_bones(sk: Skeleton3D) -> Dictionary:
	var out := {}
	var head := sk.find_bone("Head")
	if head < 0:
		return out
	var stack: Array = [head]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out[b] = true
		stack.append_array(sk.get_bone_children(b))
	return out


## A copy of a skinned mesh without the triangles that follow her head (more than half their
## weight on the head's bones), or null if nothing is left (the eyes).
func _headless(mi: MeshInstance3D, sk: Skeleton3D, head: Dictionary) -> MeshInstance3D:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return null
	var skin: Skin = mi.skin
	# the skin's bind index -> the skeleton's bone
	var bind_bone := PackedInt32Array()
	if skin != null:
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = sk.find_bone(skin.get_bind_name(b))
			bind_bone.append(bone)
	var out := ArrayMesh.new()
	out.blend_shape_mode = src.blend_shape_mode
	for k in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(k))
	var kept := 0
	var mats: Array = []
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or bones.size() < verts.size():
			continue
		var per := bones.size() / verts.size()
		var on_head := PackedByteArray()
		on_head.resize(verts.size())
		for v in verts.size():
			var w := 0.0
			for j in per:
				var bi := bones[v * per + j]
				var bone: int = bind_bone[bi] if bi < bind_bone.size() else bi
				if head.has(bone):
					w += weights[v * per + j]
			on_head[v] = 1 if w > 0.5 else 0
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for v in verts.size():
				idx[v] = v
		var keep := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			if on_head[idx[t]] == 0 and on_head[idx[t + 1]] == 0 and on_head[idx[t + 2]] == 0:
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		if keep.is_empty():
			continue
		arr[Mesh.ARRAY_INDEX] = keep
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, src.surface_get_blend_shape_arrays(s), {}, flags)
		mats.append(mi.get_active_material(s))
		kept += 1
	if kept == 0:
		return null
	for s in mats.size():
		out.surface_set_material(s, mats[s])
	var copy := MeshInstance3D.new()
	copy.name = mi.name + "_FirstPerson"
	copy.mesh = out
	copy.skin = skin
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.visible = false
	mi.get_parent().add_child(copy)
	copy.transform = mi.transform
	copy.skeleton = copy.get_path_to(mi.get_node(mi.skeleton)) if not mi.skeleton.is_empty() else NodePath("")
	return copy


## On: her body meshes only cast their shadow, and the headless copies are drawn instead.
func _hide_head(on: bool) -> void:
	var body = main.player.body
	if body == null or not body.ok:
		return
	if _copies.is_empty() and on:
		var sk: Skeleton3D = body.skeleton
		var head := _head_bones(sk)
		for node in body.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or mi.skin == null and mi.skeleton.is_empty() or mi.name.ends_with("_FirstPerson"):
				continue
			if mi.get_parent() == body.props or (body.props != null and body.props.is_ancestor_of(mi)):
				continue # the knitting needles stay as they are
			_copies.append([mi, _headless(mi, sk, head), mi.cast_shadow])
	for c in _copies:
		var mi := c[0] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else c[2]
		if c[1] != null:
			(c[1] as MeshInstance3D).visible = on and mi.visible


## Whether any of her drawn meshes still has the head in it (for the autotest).
func head_drawn() -> bool:
	for c in _copies:
		var mi := c[0] as MeshInstance3D
		if mi.visible and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			return true
	return _copies.is_empty()


## The headless copies drawn now (for the autotest).
func body_copies() -> Array:
	return _copies.filter(func(c): return c[1] != null).map(func(c): return c[1])


# --- each frame ----------------------------------------------------------------------

func _held(keys: Array) -> bool:
	if main.hud.is_menu_open():
		return false
	for k in keys:
		var b := Keys.key_for(k, ["fps", "move"]) # the player's key bindings
		if key_down.get(k, false) or Input.is_key_pressed(b) or Input.is_physical_key_pressed(b):
			return true
	return false


func _process(delta: float) -> void:
	if not active:
		return
	if main.fp_blocked():
		leave()
		return
	_update(delta)


func _update(delta: float) -> void:
	var p: Node3D = main.player
	# the arrow keys look round too, for a trackpad
	var turn := Vector2.ZERO
	if _held([KEY_LEFT]):
		turn.x += 1
	if _held([KEY_RIGHT]):
		turn.x -= 1
	if _held([KEY_UP]):
		turn.y += 1
	if _held([KEY_DOWN]):
		turn.y -= 1
	yaw = wrapf(yaw + turn.x * KEY_LOOK * delta, -PI, PI)
	pitch = clampf(pitch + turn.y * KEY_LOOK * delta, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	# walk: forward is where she looks, flat on the ground
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var want := Vector3.ZERO
	if _held([KEY_W]):
		want += fwd
	if _held([KEY_S]):
		want -= fwd
	if _held([KEY_D]):
		want += right
	if _held([KEY_A]):
		want -= right
	var steering: bool = want != Vector3.ZERO and not p.busy
	if steering:
		p.path.clear() # the keys take over from a click's walk
	p.steer = want.normalized() if steering else Vector3.ZERO
	p.steer_back = steering and want.dot(fwd) < -0.1
	# her body turns with the view (sitting or busy, the seat decides)
	if not p.busy:
		if p.path.is_empty():
			p.rotation.y = lerp_angle(p.rotation.y, yaw + PI, 1.0 - exp(-16.0 * delta)) if delta > 0.0 else yaw + PI
	# the camera: at her eyes, a little forward, the walk's bob mostly smoothed away
	var eye := _eye_local()
	if not _have_eye or delta <= 0.0:
		_eye = eye
		_have_eye = true
	else:
		var k := 1.0 - exp(-20.0 * delta)
		var ky := 1.0 - exp(-lerpf(3.0, 20.0, BOB) * delta)
		_eye = Vector3(lerpf(_eye.x, eye.x, k), lerpf(_eye.y, eye.y, ky), lerpf(_eye.z, eye.z, k))
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pos: Vector3 = p.global_transform * _eye + Vector3(-sin(yaw), 0, -cos(yaw)) * FORWARD
	main.cam.global_transform = Transform3D(basis, pos)
	main.sun.directional_shadow_max_distance = SHADOW
	p._ring.visible = false # the green ring round her feet is for the overhead camera
	# no roofs lifted off round her: from her eyes she's under them
	if World.barn != null and World.barn_parts.has("roof"):
		(World.barn_parts["roof"] as Node3D).visible = true
	for s in Interiors.shops.values():
		if is_instance_valid(s.node) and s.parts.has("roof"):
			(s.parts["roof"] as Node3D).visible = true
	# the headless copies follow her meshes: shown with them, and the same hand and face shapes
	for c in _copies:
		var mi := c[0] as MeshInstance3D
		var copy = c[1]
		if copy == null or not is_instance_valid(mi):
			continue
		(copy as MeshInstance3D).visible = mi.visible
		for k in (copy as MeshInstance3D).get_blend_shape_count():
			(copy as MeshInstance3D).set_blend_shape_value(k, mi.get_blend_shape_value(k))
	# the action ring wants the mouse; it comes back once the ring is gone
	if _menu_freed and not main.hud.is_menu_open():
		_menu_freed = false
		if main._autotest_dir == "":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_aim_t -= delta
	if _aim_t <= 0.0:
		_aim_t = 0.15
		var t = main._ray_target(_centre())
		var acts: Array = main._actions_for(t) if t != null else []
		_aim.text = main._name_of(t) if not acts.is_empty() else ""
	_dot.visible = not main.hud.is_menu_open()


## Her eyes, in her own space: between the eye bones (or a little above and before the Head bone).
func _eye_local() -> Vector3:
	var p: Node3D = main.player
	var sk: Skeleton3D = p.body.skeleton
	var w := Vector3.ZERO
	var l := sk.find_bone("LeftEye")
	var r := sk.find_bone("RightEye")
	if l >= 0 and r >= 0:
		w = sk.global_transform * ((sk.get_bone_global_pose(l).origin + sk.get_bone_global_pose(r).origin) * 0.5)
	else:
		var h := sk.find_bone("Head")
		var hx := sk.global_transform * sk.get_bone_global_pose(h)
		w = hx.origin + p.global_transform.basis * Vector3(0, 0.1, 0.08)
	return p.global_transform.affine_inverse() * w


func _centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


## A click or E: whatever is under the dot, as a click on it from above would (a tool on the
## ground, or the ring of actions). Returns true if something was used.
func use() -> bool:
	if main.hud.is_menu_open():
		main.hud.hide_menu()
		return false
	var c := _centre()
	var t = main._ray_target(c)
	if main._tool_click(main.hud.selected_item(), t, c):
		return true
	if t == null:
		return false
	var acts: Array = main._actions_for(t)
	if acts.is_empty():
		return false
	main.hud.show_menu(c, main._name_of(t), acts, func(id): main._do_action(t, id))
	if main._autotest_dir == "":
		_menu_freed = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(c)
	return true


## Keys while it's on (main.gd's _input asks first). Returns true if used; the rest (the hotbar,
## the bag, Esc with a panel open...) go on to main.gd.
func handle_key(kc: Key) -> bool:
	kc = Keys.map(kc, ["fps", "move"]) # the player's key bindings, as the default keys below
	if kc == KEY_NONE:
		return true # a default key whose action the player moved: it does nothing here
	match kc:
		KEY_V:
			leave()
		KEY_ESCAPE:
			if main.hud.is_menu_open():
				main.hud.hide_menu()
			else:
				leave()
		KEY_E:
			use()
		KEY_P, KEY_TAB, KEY_B:
			leave() # the cinematic camera, the dog and building mode work from above
			return false
		KEY_Q, KEY_SPACE, KEY_C:
			pass # the overhead camera's keys do nothing here
		KEY_H:
			_hint.visible = not _hint.visible
		_:
			return false
	return true


## The mouse while it's on (main.gd's _unhandled_input hands it here).
func handle_mouse(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			look((e as InputEventMouseMotion).relative)
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if main.hud.is_menu_open():
				main.hud.hide_menu() # a click outside the ring closes it
			elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and main._autotest_dir == "":
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # a click after Cmd-Tab takes the mouse back
			else:
				use()
	elif e is InputEventPanGesture: # two fingers on a Mac trackpad look round
		look((e as InputEventPanGesture).delta * 8.0)


## Turns the view by a mouse movement in pixels.
func look(rel: Vector2) -> void:
	yaw = wrapf(yaw - rel.x * LOOK, -PI, PI)
	pitch = clampf(pitch - rel.y * LOOK, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
