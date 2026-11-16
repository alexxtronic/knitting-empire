extends Node
## Working behind the Coffee Shop's counter (Alex, 2026-11-15: "I want to be behind the counter in
## first person, someone comes and asks for a coffee and I go over and grind the coffee, put it in a
## filter and press the button, wait 10 seconds then when coffee's done pour it and hand it to them,
## they hand me 5 coin. A pot pours 4 cups ... I can do this any time"). The café counter's "Work
## behind the counter" (Interiors.WorkSpot) opens it at any hour; Esc stops.
##
## She stands behind the counter in first person, the view locked (main.fps.locked) and turned for
## her to whatever the next step needs: the grinder and the drip brewer on the back bar, the cup on
## the counter, the customer. E, Space, Enter or a click does that step; her arm reaches for it
## (WardrobeView.ReachIK). Grind, put the grounds in the filter, press the button, wait BREW_SECS
## while the pot fills, then pour a cup for whoever is waiting and hand it over for PAY coins, all
## hers. A pot holds CUPS cups. Customers are the town's people: one at a time walks up, asks, pays,
## and takes a free reading seat with the coffee (cafe_visits.adopt) or goes home.

const WardrobeView = preload("res://scripts/wardrobe_view.gd")
const FirstPerson = preload("res://scripts/first_person.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Interiors = preload("res://scripts/interiors.gd")

const PAY := 5 # coins a cup (Alex)
const CUPS := 4 # cups a pot pours (Alex)
const BREW_SECS := 10.0 # real seconds the brewer takes (Alex)
const MOTION := {"grind": 1.6, "filter": 0.8, "brew": 0.5, "pour": 1.1, "hand": 0.8}
# in the café's own space (data/interiors.json "cafe": the front counter at (2.2, -4.9), the back bar
# at (2.2, -6.25); the gap between them is where she works)
const AT_COUNTER := Vector3(1.75, 0, -5.62)
const AT_BAR := Vector3(2.65, 0, -5.36) # her back to the front counter: the gap is narrow
const GRINDER := Vector3(2.5, 0.97, -6.14)
const BREWER := Vector3(2.88, 0.97, -6.16)
const CUP_AT := Vector3(1.72, 1.0, -4.78) # on the counter's edge, in reach of both of them
const CUSTOMER := Vector3(1.72, 0, -3.98)
const EYE := 1.55
const REACH := 0.5 # how far her arm reaches in (fully, it crossed the camera)
const PAUSE := 15.0 # seconds between customers, once the last one has sat down or gone (Alex)

var main: Node
var active := false
var ground := false # beans ground, waiting for the filter
var filtered := false # grounds in the filter, waiting for the button
var brewing := false
var brew_t := 0.0 # seconds left
var pot := 0 # cups in the pot
var poured := false # a cup stands poured on the counter
var busy := "" # the motion under way ("grind", "pour"...), "" when her hands are free
var busy_t := 0.0
var customer := {} # {"vid", "v", "home", "roam", "rest", "state": "coming" | "waiting"}
var next_customer_t := 2.0
var _last := "" # the customer just served, until they sit down with it or are out of the door
var earned := 0 # this shift
var served := 0
var steps_done: Array = [] # every step she has done, in order (for the autotest)
var line := "" # what the customer said

var _shop = null
var _kit: Node3D # the grinder, brewer, pot and cup on the back bar (stay after she stops)
var _grinder: Node3D
var _grinder_rest := Vector3.ZERO
var _grounds: MeshInstance3D # in the filter basket
var _button: MeshInstance3D
var _button_mat: StandardMaterial3D
var _coffee: MeshInstance3D # in the pot
var _pivot: Node3D # its foot on the pot's floor: scaling it fills the pot from the bottom up
var _steam: GPUParticles3D
var _cup: Node3D
var _reach: WardrobeView.ReachIK
var _was_fps := false
var _cam := {}
var _layer: CanvasLayer
var _title: Label
var _say: Label
var _step: Label
var _bar: ProgressBar
var _status: Label


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	_layer.visible = false
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = -230
	panel.offset_bottom = -96
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.09, 0.86)
	sb.border_color = Color(0.86, 0.68, 0.42)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	_title = _label(col, 15, Color(0.98, 0.84, 0.6))
	_title.text = "Behind the counter"
	_say = _label(col, 15, Color(1, 1, 1))
	_step = _label(col, 19, Color(1.0, 0.95, 0.85))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	col.add_child(_bar)
	_status = _label(col, 13, Color(0.9, 0.82, 0.7))


func _label(parent: Node, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## The café's building node (it may stand turned or moved by the world editor).
func _xf() -> Transform3D:
	return (_shop.node as Node3D).global_transform


func _w(p: Vector3) -> Vector3:
	return _xf() * p


## Behind the counter, from its "Work behind the counter" row.
func open(_spot = null) -> void:
	if active or not Interiors.shops.has("cafe"):
		return
	if main.story.is_playing() or main.sleeping:
		return
	_shop = Interiors.shops["cafe"]
	_ensure_kit()
	var p: Node3D = main.player
	p.cancel_activity()
	p.path.clear()
	p._on_arrive = Callable()
	main.hud.hide_menu()
	_was_fps = main.fps.active
	_cam = {"yaw": main.cam_yaw, "goal": main.cam_yaw_goal, "target": main.cam_target, "dist": main.cam_dist}
	var at := _w(AT_COUNTER)
	p.position = Vector3(at.x, p.position.y, at.z)
	_face(_w(CUSTOMER) + Vector3(0, 1.3, 0), true)
	if not _was_fps:
		main.fps.enter()
	if not main.fps.active:
		return # first person can't start now (main.fp_blocked())
	main.fps.locked = true
	_face(_w(CUSTOMER) + Vector3(0, 1.3, 0), true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reach = WardrobeView.ReachIK.new()
	_reach.body = p
	p.body.skeleton.add_child(_reach)
	active = true
	busy = ""
	earned = 0
	served = 0
	line = ""
	steps_done.clear()
	next_customer_t = 2.0
	_last = ""
	main.cafe_visits.hold_orders()
	_layer.visible = true
	main.hud.click("ui_open")
	_refresh()


## Esc: she steps out from behind the counter; whoever was coming or waiting goes back.
func close() -> void:
	if not active:
		return
	active = false
	_layer.visible = false
	if not customer.is_empty():
		_send_home(customer)
		customer = {}
	if is_instance_valid(_reach):
		_reach.queue_free()
	_reach = null
	main.fps.locked = false
	if not _was_fps:
		main.fps.leave()
		main.cam_yaw = float(_cam.get("yaw", main.cam_yaw))
		main.cam_yaw_goal = float(_cam.get("goal", main.cam_yaw_goal))
		main.cam_target = main.player.position
		main.cam_dist = float(_cam.get("dist", main.cam_dist))
		main._update_camera(1.0)
	# out in front of the counter again, where she can walk
	var out := _w(Vector3(AT_COUNTER.x, 0, CUSTOMER.z - 0.1))
	main.player.position = Vector3(out.x, main.player.position.y, out.z)
	if earned > 0:
		main.hud.show_toast("A good shift: %d cups, %d coins." % [served, earned])


func handle_key(kc: Key) -> bool:
	if not active:
		return false
	match kc:
		KEY_ESCAPE:
			close()
		KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			act()
		_:
			return kc in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_V, KEY_P, KEY_TAB, KEY_B]
	return true


func handle_mouse(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		act()


## The next thing to do: {"id", "label", "at" (world point she looks at), "ok" (can do it now)}.
func next_step() -> Dictionary:
	var waiting: bool = not customer.is_empty() and str(customer["state"]) == "waiting"
	var who := str(customer["v"].title) if not customer.is_empty() else ""
	var face := _w(CUSTOMER) + Vector3(0, 1.45, 0)
	if poured:
		if waiting:
			return {"id": "hand", "label": "Hand %s the coffee" % who, "at": _w(CUP_AT), "ok": true}
		return {"id": "", "label": "A cup's poured. Waiting for a customer…", "at": face, "ok": false}
	if brewing:
		return {"id": "", "label": "Brewing… %d s" % ceili(brew_t), "at": _w(BREWER + Vector3(0, 0.12, 0.06)), "ok": false}
	if pot > 0:
		if waiting:
			return {"id": "pour", "label": "Pour %s a cup" % who, "at": _w(BREWER + Vector3(0, 0.1, 0.07)), "ok": true}
		return {"id": "", "label": "The pot's ready. Waiting for a customer…", "at": face, "ok": false}
	if not ground:
		return {"id": "grind", "label": "Grind the beans", "at": _w(GRINDER + Vector3(0, 0.15, 0)), "ok": true}
	if not filtered:
		return {"id": "filter", "label": "Put the grounds in the filter", "at": _w(BREWER + Vector3(0, 0.33, 0)), "ok": true}
	return {"id": "brew", "label": "Press the button", "at": _w(BREWER + Vector3(0.07, 0.2, 0.08)), "ok": true}


## E, Space, Enter or a click: does the next step, if her hands are free and it can be done.
func act() -> void:
	if not active or busy != "":
		return
	var st := next_step()
	if not bool(st["ok"]):
		return
	busy = str(st["id"])
	busy_t = float(MOTION.get(busy, 0.6))
	if _reach:
		_reach.target = st["at"]
		_reach.side = 1
	main.hud.click("ui_click")


## A motion done: what it changes.
func _finish(what: String) -> void:
	steps_done.append(what)
	match what:
		"grind":
			ground = true
		"filter":
			filtered = true
			_grounds.visible = true
		"brew":
			brewing = true
			brew_t = BREW_SECS
			ground = false
			filtered = false
		"pour":
			pot -= 1
			poured = true
			_cup.visible = true
			_cup.position = CUP_AT
		"hand":
			_serve()


## The customer takes the cup and pays; the cup goes with them to a seat (or home).
func _serve() -> void:
	poured = false
	Game.coins += PAY
	earned += PAY
	served += 1
	main.audio.play("coins", -4.0)
	var v = customer["v"]
	var cup := Node3D.new()
	cup.name = "CafeCup"
	v.add_child(cup)
	_mug(cup, Vector3.ZERO)
	cup.position = Vector3(0.16, 1.02, 0.24)
	_cup.visible = false
	line = "%s: Thank you, Nora!" % v.title # draft
	v.talk(1.5)
	main.cafe_visits.adopt(str(customer["vid"]), v, customer["home"], customer["roam"], customer["rest"], cup)
	_last = str(customer["vid"])
	customer = {}
	next_customer_t = PAUSE


func _process(delta: float) -> void:
	if not active:
		return
	if main.story.is_playing() or main.sleeping:
		close()
		return
	var p: Node3D = main.player
	# her hands: the motion under way, and what it does to the things on the bar
	if busy != "":
		busy_t -= delta
		if busy == "grind" and is_instance_valid(_grinder):
			_grinder.position = _grinder_rest + Vector3(randf_range(-0.004, 0.004), 0, randf_range(-0.004, 0.004))
		if busy_t <= 0.0:
			if is_instance_valid(_grinder):
				_grinder.position = _grinder_rest
			var what := busy
			busy = ""
			_finish(what)
	if _reach:
		_reach.weight = move_toward(_reach.weight, REACH if busy != "" else 0.0, delta * 3.0)
	if brewing:
		brew_t -= delta
		if brew_t <= 0.0:
			brewing = false
			pot = CUPS
			main.hud.click("ui_open")
	_steam.emitting = brewing
	_button_mat.emission_energy_multiplier = 2.5 if brewing else 0.2
	var fill: float = (1.0 - brew_t / BREW_SECS) if brewing else float(pot) / CUPS
	_pivot.visible = fill > 0.01
	_pivot.scale = Vector3(1, maxf(fill, 0.01), 1)
	# her place: at the bar for the machines, at the counter for the cup and the customer
	var st := next_step()
	var here: String = busy if busy != "" else str(st["id"])
	var spot := AT_BAR if here in ["grind", "filter", "brew", "pour"] or (here == "" and brewing) else AT_COUNTER
	var to := _w(spot)
	p.position = p.position.lerp(Vector3(to.x, p.position.y, to.z), 1.0 - exp(-5.0 * delta))
	_face(st["at"] if busy == "" else (_reach.target if _reach else st["at"]), false, delta)
	_update_customer(delta)
	main.cafe_visits.step_all(delta)
	_refresh()


## Turns her view (and her body) to look at world point `at`.
func _face(at: Vector3, snap: bool, delta := 0.0) -> void:
	var p: Node3D = main.player
	var eye: Vector3 = p.global_position + Vector3(0, EYE, 0)
	var d := at - eye
	if d.length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	var pitch := clampf(asin(clampf(d.normalized().y, -1.0, 1.0)), deg_to_rad(-60.0), deg_to_rad(40.0))
	var k := 1.0 if snap else 1.0 - exp(-6.0 * delta)
	main.fps.yaw = lerp_angle(main.fps.yaw, yaw, k)
	main.fps.pitch = lerpf(main.fps.pitch, pitch, k)
	p.rotation.y = lerp_angle(p.rotation.y, atan2(d.x, d.z), k)


func _update_customer(delta: float) -> void:
	if customer.is_empty():
		if _last != "": # the pause starts once they're sitting with it, or out of the café
			var lv = main._villager(_last)
			var st := str(main.cafe_visits.visits.get(_last, {}).get("state", ""))
			if lv == null or st == "reading" or Interiors.inside_of(lv.position) != "cafe":
				_last = ""
			return
		next_customer_t -= delta
		if next_customer_t <= 0.0:
			if not call_customer():
				next_customer_t = 4.0 # nobody free: look again in a bit
		return
	var v = customer["v"]
	if not is_instance_valid(v):
		customer = {}
		return
	if str(customer["state"]) == "coming":
		var at := _w(CUSTOMER)
		if Vector2(v.position.x - at.x, v.position.z - at.z).length() < 0.25:
			customer["state"] = "waiting"
			v.face_point(main.player.global_position + Vector3(0, 1.4, 0), 600.0)
			v.talk(2.5)
			line = "%s: A coffee, please!" % v.title # draft
			main.hud.click("ui_click")


## Someone from town comes up to the counter for a coffee: `vid`, or whoever's free and nearest.
func call_customer(vid := "") -> bool:
	if not customer.is_empty():
		return false
	var v = null
	if vid != "":
		v = main._villager(vid)
	else:
		var free: Array = main.villagers.filter(func(x): return is_instance_valid(x) and x.visible and x.anim_override == "" \
			and not main.cafe_visits.visits.has(str(x.vid)) and Game.flag("home_" + str(x.vid), null) == null)
		var door := _w(Vector3(0, 0, 4.0))
		free.sort_custom(func(a, b): return a.position.distance_to(door) < b.position.distance_to(door))
		free = free.slice(0, 4)
		if not free.is_empty():
			v = free[randi() % free.size()]
	if v == null:
		return false
	customer = {"vid": str(v.vid), "v": v, "home": v.home, "roam": v.roam, "rest": v.rest_yaw, "state": "coming"}
	v.rest_yaw = null
	v.roam = Vector2.ZERO
	var at := _w(CUSTOMER)
	v.walk_to(at, main._find_path(v.position, at))
	line = ""
	return true


func _send_home(c: Dictionary) -> void:
	var v = c["v"]
	if not is_instance_valid(v):
		return
	v.roam = c["roam"]
	v.rest_yaw = c["rest"]
	v.walk_to(c["home"], main._find_path(v.position, c["home"]))


func _refresh() -> void:
	var st := next_step()
	var key := "[E]  " if bool(st["ok"]) and busy == "" else ""
	var doing := {"grind": "Grinding the beans…", "filter": "Filling the filter…", "brew": "Pressing the button…", "pour": "Pouring…", "hand": "Handing it over…"}
	_step.text = str(doing.get(busy, "")) if busy != "" else key + str(st["label"])
	if busy != "":
		_bar.value = 1.0 - busy_t / float(MOTION.get(busy, 1.0))
	elif brewing:
		_bar.value = 1.0 - brew_t / BREW_SECS
	else:
		_bar.value = 0.0
	_say.text = line
	_say.visible = line != ""
	var cups := ""
	for i in CUPS:
		cups += "●" if i < pot else "○"
	_status.text = "Pot %s   ·   Earned %d coins   ·   Esc to stop" % [cups, earned]


# --- the kit on the back bar -----------------------------------------------------------------------

func _ensure_kit() -> void:
	if is_instance_valid(_kit) and _kit.get_parent() == _shop.node:
		return
	_kit = Node3D.new()
	_kit.name = "BaristaKit"
	(_shop.node as Node3D).add_child(_kit)
	# the grinder: a black body with a glass hopper of beans and a steel spout
	_grinder = Node3D.new()
	_kit.add_child(_grinder)
	_grinder.position = GRINDER
	_grinder_rest = GRINDER
	Catalog.box(_grinder, Vector3(0.12, 0.16, 0.14), Vector3(0, 0.08, 0), Color(0.12, 0.11, 0.1))
	Catalog.cyl(_grinder, 0.035, 0.035, 0.03, Vector3(0, 0.03, 0.08), Color(0.7, 0.7, 0.72), Vector3(90, 0, 0), 10)
	var hopper := Catalog.cyl(_grinder, 0.055, 0.03, 0.1, Vector3(0, 0.21, 0), Color(0.85, 0.9, 0.92))
	hopper.material_override = Catalog.lamp_glass()
	Catalog.cyl(_grinder, 0.045, 0.026, 0.06, Vector3(0, 0.19, 0), Color(0.24, 0.13, 0.07)) # the beans
	# the drip brewer: a cream body, the filter basket on top, the red button, the glass pot below
	var b := Node3D.new()
	_kit.add_child(b)
	b.position = BREWER
	var cream := Color(0.9, 0.84, 0.72)
	Catalog.box(b, Vector3(0.2, 0.04, 0.2), Vector3(0, 0.02, 0), Color(0.15, 0.13, 0.12)) # the hot plate
	Catalog.box(b, Vector3(0.2, 0.34, 0.07), Vector3(0, 0.17, -0.065), cream) # the column
	Catalog.box(b, Vector3(0.22, 0.07, 0.2), Vector3(0, 0.36, 0), cream) # the head
	Catalog.cyl(b, 0.07, 0.04, 0.06, Vector3(0, 0.3, 0.02), Color(0.3, 0.26, 0.22)) # the basket
	_grounds = Catalog.cyl(b, 0.055, 0.035, 0.02, Vector3(0, 0.33, 0.02), Color(0.2, 0.11, 0.06))
	_grounds.visible = false
	_button = Catalog.cyl(b, 0.012, 0.012, 0.012, Vector3(0.07, 0.2, -0.026), Color(0.8, 0.1, 0.08), Vector3(90, 0, 0), 10)
	_button_mat = StandardMaterial3D.new()
	_button_mat.albedo_color = Color(0.8, 0.1, 0.08)
	_button_mat.emission_enabled = true
	_button_mat.emission = Color(1.0, 0.2, 0.1)
	_button_mat.emission_energy_multiplier = 0.2
	_button.material_override = _button_mat
	var glass := Catalog.cyl(b, 0.06, 0.06, 0.13, Vector3(0, 0.105, 0.03), Color(0.85, 0.9, 0.92))
	glass.material_override = Catalog.lamp_glass()
	var lid := Catalog.cyl(b, 0.062, 0.062, 0.015, Vector3(0, 0.175, 0.03), Color(0.12, 0.11, 0.1))
	lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var handle := Catalog.box(b, Vector3(0.015, 0.09, 0.02), Vector3(0, 0.11, 0.1), Color(0.12, 0.11, 0.1))
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cm := CylinderMesh.new() # the coffee: its foot on the pot's floor, so scaling y fills it
	cm.top_radius = 0.056
	cm.bottom_radius = 0.056
	cm.height = 0.11
	_coffee = MeshInstance3D.new()
	_coffee.mesh = cm
	cm.surface_set_material(0, Catalog.mat(Color(0.16, 0.08, 0.03), 0.3))
	var cpivot := Node3D.new()
	b.add_child(cpivot)
	cpivot.position = Vector3(0, 0.045, 0.03)
	cpivot.add_child(_coffee)
	_coffee.position = Vector3(0, 0.055, 0)
	_pivot = cpivot
	_pivot.visible = false
	_steam = _make_steam()
	b.add_child(_steam)
	_steam.position = Vector3(0, 0.42, 0.0)
	# the cup she pours into, on the counter's edge
	_cup = Node3D.new()
	_kit.add_child(_cup)
	_mug(_cup, Vector3.ZERO)
	_cup.position = CUP_AT
	_cup.visible = false


## A white mug of coffee standing at `at` in r's space.
static func _mug(r: Node3D, at: Vector3) -> void:
	Catalog.cyl(r, 0.04, 0.035, 0.09, at + Vector3(0, 0.045, 0), Color(0.95, 0.94, 0.9))
	Catalog.cyl(r, 0.034, 0.034, 0.005, at + Vector3(0, 0.083, 0), Color(0.3, 0.16, 0.07))
	Catalog.ring(r, 0.018, 0.026, at + Vector3(0.045, 0.048, 0), Color(0.95, 0.94, 0.9), Vector3(90, 0, 0))


func _make_steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0, 0.03, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Catalog._halo()
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
