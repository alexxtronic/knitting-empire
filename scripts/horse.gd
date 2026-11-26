extends Node3D
## Her horse (2026-11-26; data/horse.json). Alex: "a horse that she can ride ... so she can travel
## places faster; a placeholder for now until we get Tripo assets again."
##
## - Lars sells it once Act 1 is done (his menu, rows_for()). It stands where she left it, and it's
##   kept in the save there: Game.flags["horse"] = [x, z, yaw].
## - G (the "ride" key) gets her on when it's within mount_reach, and off again; from further away
##   G whistles and it trots over to her. A click on it does the same from its menu.
## - Riding, she walks and runs `speed` times faster (player.ride_mult), sat in the saddle (her
##   SitIdle loop, her body lifted by `saddle`), and the horse walks, trots or gallops under her.
## - She gets off by herself for anything that isn't travelling: a story scene, sleep, knitting,
##   first person, the cinematic camera, the world editor, build mode, playing the dog, starting an
##   activity, or going indoors. It never herds and never counts as a herder (only she and the dog
##   do: Alex, 2026-11-16).
##
## The model is the dog's (dog.glb) scaled up and tinted: a STAND-IN until a horse model is made
## (docs/DIRECTION.md "Models still needed"). Its loops' strides are the dog's (dog.gd STRIDE)
## times the scale.

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Interiors = preload("res://scripts/interiors.gd")
const DOG_STRIDE := {"Walk": 0.669, "Trot": 1.459, "Run": 3.424} # dog.gd STRIDE

var main # main.gd
var data := {}
var riding := false
var owned := false
var _model: Node3D
var _anim: AnimationPlayer
var _loop := ""
var _coming: Array = [] # its path while it trots over to her
var _t := 0.0


func _ready() -> void:
	name = "Horse"
	data = Data.load_json("horse")
	visible = false


func econ(key: String, fallback):
	return data.get(key, fallback)


## From the save: hers, and where she left it.
func apply() -> void:
	riding = false
	_coming = []
	if main != null and main.player != null: # on foot, whatever the last game had her doing
		main.player.riding = false
		main.player.ride_mult = 1.0
		if main.player.body:
			main.player.body.position.y = 0.0
	var e = Game.flags.get("horse", null)
	owned = e is Array and (e as Array).size() >= 3
	visible = owned
	if not owned:
		return
	_ensure_model()
	position = Vector3(float(e[0]), 0, float(e[1]))
	rotation.y = float(e[2])


func _save() -> void:
	if owned:
		Game.flags["horse"] = [snappedf(position.x, 0.01), snappedf(position.z, 0.01), snappedf(rotation.y, 0.001)]


func _ensure_model() -> void:
	if _model != null:
		return
	_model = Catalog.model(str(econ("model", "res://assets/props/dog.glb")), self)
	if _model == null:
		return
	_model.scale *= float(econ("scale", 2.35))
	var tint := Color.html(str(econ("tint", "#9a5a34")))
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var mat := inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var own := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				own.albedo_color = own.albedo_color * tint
				inst.set_surface_override_material(i, own)
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = aps[0] if not aps.is_empty() else null
	if _anim:
		for n in ["Idle", "Walk", "Trot", "Run"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_play("Idle", 0.0)
	# its hitbox: click it for its menu
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 1.6, 2.0)
	cs.shape = bs
	cs.position.y = 0.8
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)


func _play(loop: String, ground_speed: float) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(loop):
		loop = "Walk" if loop != "Idle" and _anim.has_animation("Walk") else "Idle"
	if loop != _loop:
		_anim.play(loop, 0.2)
		_loop = loop
	var stride := float(DOG_STRIDE.get(loop, 1.0)) * float(econ("scale", 2.35))
	_anim.speed_scale = 1.0 if loop == "Idle" else clampf(ground_speed / maxf(stride, 0.01), 0.3, 2.5)


# --- buying it from Lars ------------------------------------------------------------------------

func rows_for(v) -> Array:
	var story: bool = Game.flag("story_farm", false) == true
	var done: bool = Game.flag("act1_done", false) == true
	if story and not done:
		return []
	if owned:
		return [main._act("noop", "%s is yours. G to ride her" % str(econ("name", "Your horse")), false)]
	var price := int(econ("price", 1200))
	return [main._act("horse_buy", "Buy a horse  (%sc · ride to get places faster)" % main._thousands(price), Game.coins >= price)]


func action(v, id: String) -> void:
	if id != "horse_buy" or owned:
		return
	var price := int(econ("price", 1200))
	if not Game.spend(price):
		return
	owned = true
	_ensure_model()
	var p: Vector3 = main._open_near(main.player.position, 2.5)
	position = Vector3(p.x, 0, p.z)
	rotation.y = main.player.rotation.y
	visible = true
	_save()
	main._say(v, str(econ("line", "She's yours.")))
	main.hud.show_toast("New: a horse. Press G beside her to ride (G again to get off; from further off, G whistles her over).")


# --- riding ----------------------------------------------------------------------------------------

func display_name() -> String:
	return str(econ("name", "Your horse"))


func ke_actions() -> Array:
	if riding:
		return [{"id": "dismount", "label": "Get off", "enabled": true}]
	return [{"id": "mount", "label": "Ride her  (G)", "enabled": why_not() == ""}]


func ke_action(id: String) -> void:
	match id:
		"mount":
			main.player.walk(main._find_path(main.player.position, position + global_transform.basis.x * 1.1), func(): mount())
		"dismount":
			dismount()


## Why she can't ride now ("" when she can).
func why_not() -> String:
	if not owned:
		return "You have no horse."
	if main.fp_blocked() or main.fps.active:
		return "Not now."
	if main.player.busy:
		return "Finish what you're doing first."
	if _indoors(main.player.position):
		return "Not indoors!"
	return ""


func _indoors(p: Vector3) -> bool:
	return main.building_at(p) or Interiors.inside_of(p) != ""


## The G key (main.gd): on, off, or whistle her over.
func key() -> void:
	if not owned:
		return
	if riding:
		dismount()
		return
	var d := Vector2(position.x - main.player.position.x, position.z - main.player.position.z).length()
	if d <= float(econ("mount_reach", 4.0)):
		mount()
	elif d <= float(econ("call_reach", 90.0)):
		call_over()
	else:
		main.hud.show_toast("She's too far off to hear you whistle.")


func mount() -> bool:
	var why := why_not()
	if why != "":
		main.hud.show_toast(why)
		return false
	_coming = []
	riding = true
	main.player.walk([])
	position = main.player.position
	rotation.y = main.player.rotation.y
	main.player.ride_mult = float(econ("speed", 2.5))
	main.player.riding = true
	return true


func dismount() -> void:
	if not riding:
		return
	riding = false
	main.player.ride_mult = 1.0
	main.player.riding = false
	if main.player.body:
		main.player.body.position.y = 0.0
	# she steps down beside it
	var side: Vector3 = main.player.global_transform.basis.x * 1.0
	for q in [main.player.position + side, main.player.position - side]:
		if main._walkable(main._cell(q)):
			main.player.position = Vector3(q.x, 0, q.z)
			break
	_save()


## A whistle: she trots over on the walking grid to stand beside her.
func call_over() -> void:
	var to: Vector3 = main._open_near(main.player.position, 1.6)
	_coming = main._find_path(position, to)
	if _coming.is_empty():
		main.hud.show_toast("She can't find a way to you from there.")
	else:
		main.hud.show_toast("You whistle. %s comes trotting." % display_name())


func _process(delta: float) -> void:
	if not owned or main == null or main.player == null:
		return
	if riding:
		if _must_get_off():
			dismount()
			return
		position = main.player.position
		rotation.y = main.player.rotation.y
		if main.player.body:
			main.player.body.position.y = float(econ("saddle", 0.95))
		var v: float = main.player.speed
		_play("Idle" if v < 0.1 else ("Walk" if v < 2.4 else ("Trot" if v < 5.0 else "Run")), v)
		_t -= delta
		if _t <= 0.0:
			_t = 1.0
			_save()
		return
	if not _coming.is_empty():
		var next: Vector3 = _coming[0]
		var to := next - position
		to.y = 0.0
		var spd := 4.0
		if to.length() <= spd * delta:
			position = Vector3(next.x, 0, next.z)
			_coming.remove_at(0)
			if _coming.is_empty():
				_save()
		else:
			position += to.normalized() * spd * delta
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
		_play("Trot", spd)
		return
	_play("Idle", 0.0)


func _must_get_off() -> bool:
	return main.fp_blocked() or main.fps.active or main.player.busy or _indoors(main.player.position)
