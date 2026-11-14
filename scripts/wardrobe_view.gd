## The wardrobe from her eyes (Alex, 2026-11-14): "Choose a sweater…" on the wardrobe in her house
## opens its doors and hands the camera to first person (first_person.gd, locked: no walking, no
## mouse look) looking in. Every sweater in her wardrobe (Game.wardrobe) hangs face out on its own
## wooden hanger on the brass rail, in its own design; the one in front faces her and the rest fan
## out either side, turned toward the middle.
##
## Left and Right (or the mouse wheel) browse: her arm reaches in and pulls the next one along to the
## middle, and the hangers slide and swing on the rail. A click on a sweater, or Enter on the one in
## front, picks it: it comes off its hanger, she puts it on (Game.wear and Sweaters.wear) and the
## doors close. X puts her back in her city coat; Esc closes without changing. The camera she had
## before comes back either way. The sweater she's wearing has an empty hanger.
##
## The wardrobe model (art/world_assets/house_furniture/build.py, wardrobe()) has the doors as parts
## of their own, door_l and door_r, with their origins on the hinge pins, and the rail at RAIL_Y.
## The old list (wardrobe_panel.gd) is still Menu > Wardrobe, for changing away from the wardrobe.
extends Node

const Sweaters = preload("res://scripts/sweaters.gd")
const WardrobePanel = preload("res://scripts/wardrobe_panel.gd")
const FirstPerson = preload("res://scripts/first_person.gd")

# where things are in the model's own space (Godot axes; build.py's WR_* constants)
const RAIL_Y := 1.80
const RAIL_Z := -0.005
const RAIL_HALF := 0.50 # how far along the rail a hanger may go either side of the middle
const FRONT_Z := 0.30 # the front of the carcass
const STAND := 0.58 # where she stands, this far in front of it (her eyes come out about 0.62 m from the rail)
const DOOR_OPEN := 105.0 # degrees
const DOOR_TIME := 0.45
# the hangers' layout: the one in front has GAP either side; the rest bunch toward the walls
const GAP := 0.30
const STEP := 0.05
const TURN := 68.0 # degrees the sweaters either side turn toward the middle
const SQUASH := 0.55 # a hung sweater is flatter front to back than one on her
const FOV := 72.0
const PITCH := 0.0
const TIER := ["Common", "Rare", "Ultra rare", "Legendary"]

var main: Node
var active := false
var piece: Node3D # the wardrobe (a Furniture)
var focus := 0 # the hanger in front of her
var hangers: Array = [] # {node, swing, sweater, design, x, vx, yaw, yaw_v, roll, roll_v}
var picked := "" # the design picked this time ("" none yet)
var reach: ReachIK # her arm (null while closed)

var _model: Node3D # the model's root node, the hangers' parent
var _root: Node3D
var _doors: Array = [] # [node, sign]
var _door_t := 0.0
var _closing := false
var _was_fps := false
var _fps_view := Vector2.ZERO
var _cam := {}
var _stand := Vector3.ZERO # where she stands while it's open, held there every frame
var _stand_yaw := 0.0
var _light: OmniLight3D
var _push := {} # {i: hanger, side: 1 right hand / -1 left, t: seconds}
var _pick_t := -1.0
var _held_t := 0.0
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _hint: Label
static var _mesh: Mesh # Nora's fitted sweater in its rest pose (arms down): the hung sweater
static var _mesh_xf := Transform3D.IDENTITY


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 16
	_layer.visible = false
	add_child(_layer)
	_title = _label(26)
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = 22
	_layer.add_child(_title)
	_sub = _label(15)
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.offset_top = 60
	_layer.add_child(_sub)
	_hint = _label(14)
	_hint.text = "←  →  browse     Enter or click  put it on     X  city coat     Esc  close"
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -96
	_layer.add_child(_hint)


func _label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.93, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Opens the wardrobe from her eyes. Falls back on the list (wardrobe_panel.gd) when first person
## can't start (a story scene, the world editor...) or the model has no doors.
func open(wardrobe: Node3D) -> void:
	if active:
		return
	var door_l := wardrobe.find_child("door_l", true, false) as Node3D
	var door_r := wardrobe.find_child("door_r", true, false) as Node3D
	_was_fps = main.fps.active
	if door_l == null or door_r == null or (not _was_fps and not main.fps.can_enter()):
		main.wardrobe_ui.open()
		return
	piece = wardrobe
	_model = door_l.get_parent() as Node3D
	_doors = [[door_l, -1.0], [door_r, 1.0]]
	_cam = {"yaw": main.cam_yaw, "goal": main.cam_yaw_goal, "target": main.cam_target, "dist": main.cam_dist}
	_fps_view = Vector2(main.fps.yaw, main.fps.pitch)
	# she stands square in front of it
	var p: Node3D = main.player
	p.cancel_activity() # first: ending one later puts her back where it began (player._return_pos)
	p.path.clear()
	p._on_arrive = Callable() # nor does a walk she was on finish (and send her off again)
	var spot: Vector3 = _model.to_global(Vector3(0, 0, FRONT_Z + STAND))
	p.position = Vector3(spot.x, p.position.y, spot.z)
	_stand = p.position
	# which way its doors face, from the model's own front (+z), not global_rotation: a piece placed
	# from the saved layout can carry a basis that rotation alone misreads
	var front: Vector3 = _model.global_transform.basis * Vector3.BACK
	front.y = 0.0
	var face: float = atan2(front.x, front.z) if front.length() > 0.001 else _model.global_rotation.y
	p.rotation.y = face + PI
	_stand_yaw = p.rotation.y
	if not _was_fps:
		main.fps.enter()
	main.fps.locked = true
	main.fps.yaw = face
	main.fps.pitch = deg_to_rad(PITCH)
	main.cam.fov = FOV
	main.hud.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	_closing = false
	picked = ""
	_pick_t = -1.0
	_push = {}
	_door_t = 0.0
	_build_hangers()
	_light = OmniLight3D.new() # the inside is in the doors' shade (the light bake has it shut)
	_light.light_color = Color(1.0, 0.86, 0.7)
	_light.light_energy = 0.9
	_light.omni_range = 1.6
	_light.shadow_enabled = false
	_model.add_child(_light)
	_light.position = Vector3(0, 1.55, 0.55)
	reach = ReachIK.new()
	reach.body = p
	p.body.skeleton.add_child(reach)
	_layer.visible = true
	_refresh_text()
	main.hud.click("ui_open")


## Shuts the doors and gives the camera back (Esc, or after she picks).
func close() -> void:
	if not active or _closing:
		return
	_closing = true
	_push = {}


func _finish() -> void:
	active = false
	_closing = false
	for d in _doors:
		if is_instance_valid(d[0]):
			(d[0] as Node3D).rotation.y = 0.0
	if is_instance_valid(_root):
		_root.queue_free()
	if is_instance_valid(_light):
		_light.queue_free()
	if is_instance_valid(reach):
		reach.queue_free()
	reach = null
	hangers.clear()
	_layer.visible = false
	main.fps.locked = false
	main.cam.fov = FirstPerson.FOV
	if not _was_fps:
		main.fps.leave()
		main.cam_yaw = float(_cam["yaw"])
		main.cam_yaw_goal = float(_cam["goal"])
		main.cam_target = _cam["target"]
		main.cam_dist = float(_cam["dist"])
		main._update_camera(1.0)
	else:
		main.fps.yaw = _fps_view.x
		main.fps.pitch = _fps_view.y
		if main._autotest_dir == "":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- the hangers ---------------------------------------------------------------------------------

## The designs on the rail, in the order of the list (best stars first).
static func designs() -> Array:
	return WardrobePanel.entries().map(func(d): return str(d["id"]))


func _build_hangers() -> void:
	_root = Node3D.new()
	_root.name = "WardrobeHangers"
	_model.add_child(_root)
	hangers.clear()
	var ds := designs()
	focus = 1 if ds.size() > 1 and str(ds[0]) == Game.worn_design else 0 # the best one she isn't wearing
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.36, 0.18)
	wood.roughness = 0.55
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.6, 0.3)
	brass.metallic = 1.0
	brass.roughness = 0.35
	for i in ds.size():
		var node := Node3D.new()
		_root.add_child(node)
		var swing := Node3D.new()
		node.add_child(swing)
		_hanger(swing, wood, brass)
		var sw := MeshInstance3D.new()
		sw.name = "Sweater"
		sw.mesh = _sweater_mesh()
		sw.material_override = Sweaters.material(str(ds[i]))
		sw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		swing.add_child(sw)
		if sw.mesh != null:
			# the neck just over the hanger's shoulders, flattened front to back
			var box: AABB = _mesh_xf * sw.mesh.get_aabb()
			var c := box.get_center()
			sw.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, SQUASH)), Vector3(-c.x, -0.05 - box.end.y, -c.z * SQUASH)) * _mesh_xf
		sw.visible = str(ds[i]) != Game.worn_design # she has that one on
		var x := _target_x(i)
		node.position = Vector3(x, RAIL_Y, RAIL_Z)
		hangers.append({"node": node, "swing": swing, "sweater": sw, "design": str(ds[i]), "x": x, "vx": 0.0,
			"yaw": _target_yaw(i), "yaw_v": 0.0, "roll": 0.0, "roll_v": 0.0})


## A wooden hanger: a brass hook round the rail, a neck, two sloping shoulders and a bar.
func _hanger(parent: Node3D, wood: Material, brass: Material) -> void:
	var hook := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.013
	tm.outer_radius = 0.019
	tm.rings = 12
	tm.ring_segments = 6
	hook.mesh = tm
	hook.material_override = brass
	hook.rotation_degrees = Vector3(0, 0, 90)
	parent.add_child(hook)
	_rod(parent, Vector3(0, -0.016, 0), Vector3(0, -0.06, 0), 0.0035, brass)
	for s in [-1.0, 1.0]:
		_rod(parent, Vector3(0, -0.058, 0), Vector3(s * 0.2, -0.105, 0), 0.011, wood)
	_rod(parent, Vector3(-0.19, -0.12, 0), Vector3(0.19, -0.12, 0), 0.005, wood)


func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)


## Nora's fitted sweater (assets/sweaters/nora_sweater.glb) without its skeleton: in its rest pose
## her arms hang down, which is how a sweater hangs.
static func _sweater_mesh() -> Mesh:
	if _mesh == null:
		var packed := load(Sweaters.DIR + "nora_sweater.glb") as PackedScene
		if packed == null:
			return null
		var inst := packed.instantiate()
		var best: MeshInstance3D = null
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh != null and (best == null or m.mesh.get_faces().size() > best.mesh.get_faces().size()):
				best = m
		if best != null:
			_mesh = best.mesh
			var xf := Transform3D.IDENTITY
			var n2: Node = best
			while n2 != null and n2 != inst: # bake the nodes' own transforms in (not the bones' poses)
				if n2 is Node3D:
					xf = (n2 as Node3D).transform * xf
				n2 = n2.get_parent()
			_mesh_xf = xf
		inst.free()
	return _mesh


## Where hanger i goes along the rail: the one in front in the middle, the rest bunching toward the
## walls the further they are from it.
func _target_x(i: int) -> float:
	var k := i - focus
	if k == 0:
		return 0.0
	var room := RAIL_HALF - GAP
	var n := float(absi(k) - 1)
	return signf(k) * (GAP + room * (1.0 - exp(-n * STEP / room)))


func _target_yaw(i: int) -> float:
	var k := i - focus
	return 0.0 if k == 0 else deg_to_rad(TURN) * (-signf(k))


# --- each frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		return
	if not main.fps.active or not is_instance_valid(piece):
		_finish()
		return
	delta = minf(delta, 0.05)
	# she stays put in front of it, whatever else wants to walk her somewhere
	var p: Node3D = main.player
	p.path.clear()
	p.position = Vector3(_stand.x, p.position.y, _stand.z)
	p.rotation.y = _stand_yaw
	# the doors
	_door_t = clampf(_door_t + (-delta if _closing else delta) / DOOR_TIME, 0.0, 1.0)
	var e := _door_t * _door_t * (3.0 - 2.0 * _door_t)
	for d in _doors:
		(d[0] as Node3D).rotation.y = deg_to_rad(DOOR_OPEN) * e * float(d[1])
	if _closing and _door_t <= 0.0:
		_finish()
		return
	# the hangers slide on the rail and swing
	for i in hangers.size():
		var h: Dictionary = hangers[i]
		var tx := _target_x(i)
		var ax := 70.0 * (tx - float(h["x"])) - 13.0 * float(h["vx"])
		h["vx"] = float(h["vx"]) + ax * delta
		h["x"] = float(h["x"]) + float(h["vx"]) * delta
		var ty := _target_yaw(i)
		var ay := 55.0 * (ty - float(h["yaw"])) - 11.0 * float(h["yaw_v"])
		h["yaw_v"] = float(h["yaw_v"]) + ay * delta
		h["yaw"] = float(h["yaw"]) + float(h["yaw_v"]) * delta
		# a pendulum on the hook: sliding along the rail swings it the other way
		var ar := -38.0 * float(h["roll"]) - 2.2 * float(h["roll_v"]) - 2.6 * ax
		h["roll_v"] = float(h["roll_v"]) + ar * delta
		h["roll"] = clampf(float(h["roll"]) + float(h["roll_v"]) * delta, -0.5, 0.5)
		(h["node"] as Node3D).position = Vector3(float(h["x"]), RAIL_Y, RAIL_Z)
		(h["swing"] as Node3D).rotation = Vector3(0.0, float(h["yaw"]), float(h["roll"]))
	_update_arm(delta)
	_update_pick(delta)
	# held arrow keys keep browsing (the real keyboard; main.gd passes no echoes)
	if main._autotest_dir == "" and _pick_t < 0.0 and not _closing:
		var dir := 0
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_RIGHT):
			dir = 1
		elif Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_LEFT):
			dir = -1
		if dir == 0:
			_held_t = 0.0
		else:
			_held_t += delta
			if _held_t > 0.45:
				_held_t -= 0.2
				browse(dir)


## Her arm: it reaches for the sweater she's pulling along and follows it to the middle, then drops.
func _update_arm(delta: float) -> void:
	if reach == null:
		return
	var want := 0.0
	if not _push.is_empty() and not _closing:
		_push["t"] = float(_push["t"]) + delta
		var t: float = _push["t"]
		var i: int = _push["i"]
		if t > 1.0 or i < 0 or i >= hangers.size():
			_push = {}
		else:
			want = 1.0 if t < 0.75 else 0.0
			reach.side = int(_push["side"])
			var h: Dictionary = hangers[i]
			# her fingers on the sweater's outer edge, a little below the shoulder
			reach.target = (h["swing"] as Node3D).to_global(Vector3(0.2 * float(_push["side"]), -0.3, 0.07))
	if _pick_t >= 0.0 and picked != "":
		var hi := hangers.map(func(h): return h["design"]).find(picked)
		if hi >= 0 and _pick_t < 0.3:
			want = 1.0
			reach.side = 1
			# her fingers on its near edge, as when she browses (not at its neck: that drew her arm up past her eyes)
			reach.target = (hangers[hi]["swing"] as Node3D).to_global(Vector3(0.2, -0.3, 0.07))
	reach.weight = move_toward(reach.weight, want, delta / (0.16 if want > reach.weight else 0.24))


## Browses one hanger right (+1) or left (-1).
func browse(dir: int) -> void:
	if not active or _closing or _pick_t >= 0.0 or hangers.is_empty():
		return
	var to := clampi(focus + dir, 0, hangers.size() - 1)
	if to == focus:
		return
	focus = to
	# the hand on her side of it pulls it in: the right hand for the ones on the right
	_push = {"i": to, "side": dir, "t": 0.0}
	main.hud.click()
	_refresh_text()


## Picks hanger i: it comes off the rail toward her and she puts it on.
func pick(i: int) -> void:
	if not active or _closing or _pick_t >= 0.0 or i < 0 or i >= hangers.size():
		return
	var d: String = hangers[i]["design"]
	if d == Game.worn_design:
		close() # she has it on already
		return
	focus = i
	picked = d
	_pick_t = 0.0
	_push = {}
	_refresh_text()


## X: back into the city coat; her sweater goes back on its hanger.
func city_coat() -> void:
	if not active or _closing or _pick_t >= 0.0:
		return
	if Game.wear(""):
		Sweaters.wear(main.player.body, "")
		for h in hangers:
			(h["sweater"] as MeshInstance3D).visible = true
		main.hud.click("ui_open")
	close()


func _update_pick(delta: float) -> void:
	if _pick_t < 0.0:
		return
	_pick_t += delta
	var hi := hangers.map(func(h): return h["design"]).find(picked)
	if hi < 0:
		_pick_t = -1.0
		return
	var sw := hangers[hi]["sweater"] as MeshInstance3D
	if _pick_t < 0.45:
		# lifted off the rail and drawn a little toward her (not into her eyes)
		var k := _pick_t / 0.45
		sw.position.z = lerpf(sw.position.z, 0.16, k * 0.25)
		sw.position.y += delta * 0.3
		sw.scale = Vector3.ONE * lerpf(1.0, 0.85, k)
	elif sw.visible:
		sw.visible = false
		var was := Game.worn_design
		if Game.wear(picked):
			Sweaters.wear(main.player.body, picked)
		for h in hangers:
			if h["design"] == was:
				(h["sweater"] as MeshInstance3D).visible = true # her old one back on its hanger
		main.hud.click("ui_open")
		_refresh_text()
	elif _pick_t > 0.9:
		_pick_t = -1.0
		close()


func _refresh_text() -> void:
	if hangers.is_empty():
		_title.text = "Wardrobe"
		_sub.text = "Nothing knitted yet. Every sweater you knit, you knit one like it for yourself, and it hangs here."
		_hint.text = "Esc  close"
		return
	var d := Sweaters.design(str(hangers[focus]["design"]))
	var s := clampi(int(d.get("stars", 1)), 1, 4)
	_title.text = "%s  %s" % [str(d.get("name", "")), "★".repeat(s)]
	var wearing: bool = str(d.get("id", "")) == Game.worn_design
	_sub.text = "%s%s     %d of %d" % [TIER[s - 1], "  ·  you're wearing it" if wearing else "", focus + 1, hangers.size()]
	_hint.text = "←  →  browse     Enter or click  put it on     X  city coat     Esc  close"


# --- input (main.gd hands everything here while it's open) -----------------------------------------

func handle_key(kc: Key) -> bool:
	match kc:
		KEY_LEFT, KEY_A:
			browse(-1)
		KEY_RIGHT, KEY_D:
			browse(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			pick(focus)
		KEY_X:
			city_coat()
		KEY_ESCAPE, KEY_V:
			close()
	return true # nothing else while she's at the wardrobe


func handle_mouse(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not (e as InputEventMouseButton).pressed:
		return
	var mb := e as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			var i := hanger_at(mb.position)
			if i >= 0:
				pick(i)
		MOUSE_BUTTON_WHEEL_DOWN:
			browse(1)
		MOUSE_BUTTON_WHEEL_UP:
			browse(-1)
		MOUSE_BUTTON_RIGHT:
			close()


## The hanger whose sweater is under this point of the screen (the one in front first), or -1.
func hanger_at(pos: Vector2) -> int:
	var order: Array = range(hangers.size())
	order.sort_custom(func(a, b): return absi(a - focus) < absi(b - focus))
	for i in order:
		var r := screen_rect(i)
		if r.has_point(pos):
			return i
	return -1


## Where hanger i's sweater is on the screen (empty if it isn't shown).
func screen_rect(i: int) -> Rect2:
	var sw := hangers[i]["sweater"] as MeshInstance3D
	if not sw.visible or sw.mesh == null:
		return Rect2()
	var box := sw.get_aabb()
	var cam: Camera3D = main.cam
	var r := Rect2()
	var first := true
	for c in 8:
		var w: Vector3 = sw.global_transform * box.get_endpoint(c)
		if cam.is_position_behind(w):
			continue
		var p := cam.unproject_position(w)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	# the sweaters either side are turned: only their near strip shows past the one in front
	if i != focus and not first:
		var fr := screen_rect(focus) if focus >= 0 and focus < hangers.size() and focus != i else Rect2()
		if fr.has_area():
			if i < focus:
				r.end.x = minf(r.end.x, fr.position.x)
			else:
				r.position.x = maxf(r.position.x, fr.end.x)
	return r


# --- her arm ---------------------------------------------------------------------------------------

## Reaches one of her arms toward a point (two-bone IK on the upper and lower arm, the elbow down and
## out), on top of the loops and rig.gd. weight 0..1 blends from the loop's hand to the target.
class ReachIK extends SkeletonModifier3D:
	var body: Node3D # the player (her yaw gives the elbow its side)
	var side := 1 # 1 her right arm, -1 her left
	var target := Vector3.ZERO # world
	var weight := 0.0
	var hand_gap := 0.0 # how far the wrist ended up from where it was sent, for the checks

	func _process_modification_with_delta(_delta: float) -> void:
		if weight <= 0.001:
			return
		var sk := get_skeleton()
		var pre := "Right" if side > 0 else "Left"
		var u := sk.find_bone(pre + "UpperArm")
		var l := sk.find_bone(pre + "LowerArm")
		var h := sk.find_bone(pre + "Hand")
		if u < 0 or l < 0 or h < 0:
			return
		var s := sk.get_bone_global_pose(u).origin
		var e := sk.get_bone_global_pose(l).origin
		var w := sk.get_bone_global_pose(h).origin
		var a := s.distance_to(e)
		var b := e.distance_to(w)
		var inv := sk.global_transform.affine_inverse()
		# the palm, not the wrist, goes to the target: send the wrist a hand's breadth short
		var t: Vector3 = inv * target
		var goal := w.lerp(t - (t - s).normalized() * 0.09, weight)
		var d := clampf(s.distance_to(goal), 0.02, (a + b) * 0.995)
		var dir := (goal - s).normalized()
		# the elbow drops and goes out to her side
		var out_side: Vector3 = -body.global_transform.basis.x * float(side) # her right is -x
		var pole: Vector3 = (inv.basis * (Vector3.DOWN + out_side * 0.7)).normalized()
		var pp := pole - dir * pole.dot(dir)
		if pp.length() < 0.001:
			pp = (inv.basis * Vector3.DOWN).normalized()
		pp = pp.normalized()
		var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var elbow := s + dir * a * ca + pp * a * sqrt(1.0 - ca * ca)
		_aim(sk, u, e - s, elbow - s)
		var e2 := sk.get_bone_global_pose(l).origin
		var w2 := sk.get_bone_global_pose(h).origin
		var wrist := s + dir * d
		_aim(sk, l, w2 - e2, wrist - e2)
		hand_gap = (sk.global_transform * sk.get_bone_global_pose(h).origin).distance_to(sk.global_transform * goal)

	func _aim(sk: Skeleton3D, bi: int, from: Vector3, to: Vector3) -> void:
		if from.length() < 1e-5 or to.length() < 1e-5:
			return
		var q := Quaternion(from.normalized(), to.normalized())
		var g := sk.get_bone_global_pose(bi)
		var nb := Basis(q) * g.basis
		var parent := sk.get_bone_parent(bi)
		var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(bi, (pb.inverse() * nb).orthonormalized().get_rotation_quaternion())
