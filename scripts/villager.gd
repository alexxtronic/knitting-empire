extends Node3D
## A Maplewood townsperson: idles near their post, turns to face you when you
## come over, and wears a name tag. Friendship lives in Game.friends.
## With look.model set (a character id from data/characters.json) they wear that skinned
## body and share the player's animations; otherwise they get a simple shape model.

const Catalog = preload("res://scripts/catalog.gd")
const Body = preload("res://scripts/body.gd")
const WALK_SPEED := 1.0

var vid := ""
var title := ""
var role := ""
var loves := "" # item id they love as a gift
var likes: Array = [] # item ids they like (a smaller boost)
var romance := false # gifts can grow romance with them
var home := Vector3.ZERO
var roam := Vector2(0.8, 0.4) # how far they wander from home in x / z
var hold_time := 0.0
var talk_spot = null # where you stand to talk to them (e.g. in front of a counter); null = beside them
var rest_yaw = null # the way they face while standing at their post (a shopkeeper faces the counter); null = any
var _via: Array = [] # the rest of the route they are walking (walk_to)
## A round of stops they walk all day (villagers.json "route": the postman's deliveries), pausing
## at each door. Empty for everyone who stays near their post. A story's walk_to/settle_at stops it.
var route: Array = []
var _route_i := 0
var _look = null
var _target := Vector3.ZERO
var _wait := 0.0
var _speed := 0.0 # ground speed right now (skinned villagers ease in and out of a walk)
var _t := 0.0
var _model: Node3D
var _arms: Array[MeshInstance3D] = []
var body: Body # set when this villager wears a skinned character model
var anim_override := "" # a story scene can hold them in a loop
var tag: Label3D
## Chatting with Nora (main.gd): they stay put facing her, and talk while `speak_time` runs.
var listening := false
var speak_time := 0.0


## look: {"skin", "hair", "top", "bottom", "extra"} where extra is apron / glasses / hat.
func setup(id: String, name_text: String, role_text: String, loved_item: String, pos: Vector3, look: Dictionary) -> void:
	vid = id
	title = name_text
	role = role_text
	loves = loved_item
	home = pos
	position = pos
	_target = pos
	_wait = randf_range(0.5, 3.0)
	_build(look)


## Story scenes: walk to a spot and stay there (no more wandering). `via`: a route to follow on
## the way (main._find_path), so a shopkeeper goes out through the door, not the wall.
func walk_to(p: Vector3, via: Array = []) -> void:
	route = []
	home = p
	roam = Vector2.ZERO
	_via = via.duplicate()
	if _via.is_empty() or (_via[-1] as Vector3).distance_to(p) > 0.05:
		_via.append(p)
	_target = _via.pop_front()
	_wait = 0.0
	hold_time = 0.0


## Story scenes: stand at a spot from now on.
func settle_at(p: Vector3) -> void:
	route = []
	home = Vector3(p.x, 0.0, p.z) # p may be up on a seat (a story's @place height); home is on the ground
	roam = Vector2.ZERO
	_via.clear()
	_target = home
	position = p
	_wait = randf_range(1.0, 3.0)


## On a round: off to the next stop after a short pause at this door (a letter in the box).
func _next_stop() -> void:
	if route.is_empty():
		return
	var p = route[_route_i % route.size()]
	_route_i += 1
	_target = Vector3(float(p[0]), 0.0, float(p[1])) if p is Array else p
	_wait = randf_range(1.2, 2.4)


## Gesture while talking in a scene.
func talk(seconds := 2.5) -> void:
	hold_time = maxf(hold_time, seconds)


func display_name() -> String:
	return "%s · %s" % [title, role]


func hold(seconds: float) -> void:
	hold_time = seconds


func face_point(p: Vector3, seconds := 8.0) -> void:
	hold_time = seconds
	_look = p
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func _build(look: Dictionary) -> void:
	_model = Node3D.new()
	add_child(_model)
	var tag_y := 2.05
	var model_id := str(look.get("model", ""))
	if model_id != "":
		body = Body.new()
		_model.add_child(body)
		if body.load_character(model_id):
			tag_y = body.label_height + 0.12
		else:
			body.queue_free()
			body = null
	if body == null:
		_build_shapes(look)
	_add_tag_and_collider(tag_y)


func _build_shapes(look: Dictionary) -> void:
	var skin: Color = look.get("skin", Color(0.93, 0.76, 0.62))
	var hair: Color = look.get("hair", Color(0.3, 0.2, 0.12))
	var top: Color = look.get("top", Catalog.CREAM)
	var bottom: Color = look.get("bottom", Color(0.3, 0.3, 0.35))
	var extra: String = look.get("extra", "")
	for x in [-0.1, 0.1]:
		Catalog.cyl(_model, 0.075, 0.07, 0.5, Vector3(x, 0.27, 0), bottom)
		Catalog.box(_model, Vector3(0.13, 0.08, 0.22), Vector3(x, 0.04, 0.03), Color(0.25, 0.17, 0.1))
	Catalog.cyl(_model, 0.19, 0.24, 0.58, Vector3(0, 0.79, 0), top)
	for x in [-0.27, 0.27]:
		_arms.append(Catalog.cyl(_model, 0.06, 0.065, 0.5, Vector3(x, 0.78, 0), top, Vector3(0, 0, -x * 25)))
	Catalog.ball(_model, 0.17, Vector3(0, 1.23, 0), skin)
	Catalog.ball(_model, 0.18, Vector3(0, 1.32, -0.03), hair, Vector3(1.0, 0.75, 1.0))
	for x in [-0.06, 0.06]:
		Catalog.ball(_model, 0.022, Vector3(x, 1.25, 0.155), Color(0.12, 0.09, 0.08))
	match extra:
		"apron":
			Catalog.box(_model, Vector3(0.36, 0.5, 0.04), Vector3(0, 0.72, 0.22), Catalog.CREAM, Vector3(-6, 0, 0))
			Catalog.ball(_model, 0.11, Vector3(0, 1.38, -0.16), hair) # bun
		"glasses":
			for x in [-0.065, 0.065]:
				Catalog.ring(_model, 0.035, 0.05, Vector3(x, 1.25, 0.165), Color(0.15, 0.12, 0.1), Vector3(90, 0, 0))
			Catalog.cyl(_model, 0.2, 0.2, 0.09, Vector3(0, 1.0, 0), Catalog.PLAID, Vector3.ZERO, 14) # scarf
		"hat":
			Catalog.cyl(_model, 0.3, 0.3, 0.03, Vector3(0, 1.42, 0), Color(0.25, 0.2, 0.32))
			Catalog.cyl(_model, 0.15, 0.17, 0.2, Vector3(0, 1.52, 0), Color(0.25, 0.2, 0.32))
			Catalog.cyl(_model, 0.172, 0.172, 0.05, Vector3(0, 1.46, 0), Catalog.BRASS)


func _add_tag_and_collider(tag_y: float) -> void:
	tag = Label3D.new()
	tag.text = "%s\n%s" % [title, role]
	tag.font_size = 56
	tag.pixel_size = 0.0055
	tag.outline_size = 14
	tag.no_depth_test = true
	tag.modulate = Color(1.0, 0.95, 0.82)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, tag_y, 0)
	add_child(tag)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 1.7, 0.7)
	cs.shape = bs
	cs.position.y = 0.85
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)


func _process(delta: float) -> void:
	_t += delta
	speak_time = maxf(0.0, speak_time - delta)
	if listening:
		hold_time = maxf(hold_time, 1.0)
	if body:
		_process_body(delta)
		return
	if hold_time > 0.0:
		hold_time -= delta
		_model.position.y = lerpf(_model.position.y, 0.0, 0.2)
		for i in _arms.size():
			_arms[i].rotation_degrees.x = 6.0 * sin(_t * 2.0 + i)
		return
	if _wait > 0.0:
		_wait -= delta
		_turn_to_rest(delta)
		_model.position.y = lerpf(_model.position.y, 0.0, 0.2)
		for a in _arms:
			a.rotation_degrees.x = lerpf(a.rotation_degrees.x, 0.0, 0.2)
		return
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	var step := 1.0 * delta
	if d <= step and not _via.is_empty():
		position = Vector3(_target.x, 0.0, _target.z)
		_target = _via.pop_front()
		return
	if d <= step:
		position = Vector3(_target.x, 0.0, _target.z)
		_wait = randf_range(2.0, 6.0)
		_target = home + Vector3(randf_range(-roam.x, roam.x), 0, randf_range(-roam.y, roam.y))
		_next_stop()
		return
	position += to / d * step
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.2)
	_model.position.y = absf(sin(_t * 9.0)) * 0.04
	for i in _arms.size():
		_arms[i].rotation_degrees.x = 18.0 * sin(_t * 9.0 + i * PI)


## Skinned villagers: talk while held in a conversation, idle while waiting, walk between spots.
func _process_body(delta: float) -> void:
	if anim_override != "" or listening or hold_time > 0.0 or _wait > 0.0:
		_speed = 0.0
	# on the spot (ignoring height: a scene may have seated them up on a rock)
	if anim_override != "" and Vector2(position.x - _target.x, position.z - _target.z).length() < 0.05:
		hold_time = maxf(0.0, hold_time - delta)
		body.play(anim_override)
		return
	if listening:
		body.play("Talk" if speak_time > 0.0 else "Idle")
		return
	if hold_time > 0.0:
		hold_time -= delta
		body.play("Talk")
		return
	if _wait > 0.0:
		_wait -= delta
		_turn_to_rest(delta)
		body.play("Idle")
		return
	var to := _target - position
	to.y = 0.0
	var d := to.length()
	# ease up to a stroll and slow into the last step, turning toward the way they're going first
	var off := absf(angle_difference(rotation.y, atan2(to.x, to.z))) if d > 0.01 else 0.0
	var want := minf(WALK_SPEED * clampf(1.15 - off / 1.4, 0.3, 1.0), maxf(0.35, sqrt(2.0 * 2.5 * d)))
	_speed = move_toward(_speed, want, 2.5 * delta)
	var step := _speed * delta
	if d <= step and not _via.is_empty():
		position = Vector3(_target.x, 0.0, _target.z)
		_target = _via.pop_front()
		return
	if d <= step:
		position = Vector3(_target.x, 0.0, _target.z)
		_speed = 0.0
		_wait = randf_range(2.0, 6.0)
		_target = home + Vector3(randf_range(-roam.x, roam.x), 0, randf_range(-roam.y, roam.y))
		_next_stop()
		return
	position += to / d * step
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 7.0))
	body.play("Walk", _speed)


## Standing at their post, they turn back to face their way (rest_yaw) once nobody holds their eye.
func _turn_to_rest(delta: float) -> void:
	if rest_yaw != null and _via.is_empty() and Vector2(position.x - home.x, position.z - home.z).length() < maxf(roam.length(), 0.1) + 0.3:
		rotation.y = lerp_angle(rotation.y, float(rest_yaw), 1.0 - exp(-delta * 3.0))
