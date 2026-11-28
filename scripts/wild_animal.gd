extends Node3D
## A wild animal: wanders its habitat a few steps at a time, bolts when Nora runs at it or the dog
## comes charging, and lets her comb a little fibre from its coat when she walks up quietly.
##
## Made and placed by scripts/wildlife.gd from data/wildlife.json. Its model is a rigged GLB with
## Idle, Walk and Run loops (art/world_assets/wildlife/build.py; the wild sheep borrow the pen's
## sheep_woolly.glb and its Graze). Each loop is played at the rate that keeps its paws planted:
## STRIDE in the data is the ground each covers per second at speed 1.
##
## Its coat is in Game.flags["wild"][key]: the day it was last combed. It grows back in the
## species' regrow_days. While it does, the animal shows its shorn model (`shorn_model` in the data,
## with its own `shorn_stride`; Alex, 2026-11-16: every shearable animal has a naked form), the
## furry one again once the coat is back.
##
## Catching (Alex, 2026-11-15: hunt for animals with the dog and round them up in the pen): the
## dog's bark frightens it (`fright`, 0..1, shown as a "Fright" meter over its head; the rarer the animal the
## more barks it takes, and it calms down again if he lets up). At full fright it is `caught`: it
## gives in and follows the dog along the walking grid, and wildlife.gd pens it when he brings it
## to a pen. `penned`, it wanders its pen, never bolts, and is combed there.

const Catalog = preload("res://scripts/catalog.gd")
const BLEND := 0.3
const MIN_RATE := 0.55 # a loop never plays slower than this: a first step is quick, not slow motion
const ACCEL := 5.0
const BRAKE := 6.0
const TURN := 7.0
const METER_W := 0.9 # the fright meter's width, metres
const METER_FULL := 1.4 # seconds the full meter stays up once it gives in
const METER_NEAR := 1.5 # the empty meter shows this many bark ranges from a dog the player is playing
const CALM_AFTER := 2.0 # seconds after a bark before its fright starts to fade
const CALM_RATE := 0.07 # fright lost a second after that
const FLEE_TIME := 2.6 # seconds it keeps running once something has scared it
const PROBE := 1.2 # metres ahead it checks the ground is walkable
const STEER := [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, 2.6, -2.6] # radians to try when the way ahead is blocked

var main: Node # main.gd
var wl: Node # scripts/wildlife.gd
var species := ""
var key := "" # species and number, in Game.flags["wild"]
var info: Dictionary = {}
var habitats: Array = [] # Rect2s (x, z) it wanders in
var speed := 0.0 # ground speed right now
var fleeing := 0.0 # seconds of bolting left
var walked := 0.0 # metres covered (for the autotest)
var fright := 0.0 # 0..1: how frightened the dog's barking has made it (1 = it gives in)
var caught := false # frightened into following the dog home
var penned := false # lives in one of her pens
var _calm_t := 0.0 # seconds since the last bark that reached it
var _meter: Node3D # the fright meter over its head: a back bar, its fill and the word over them
var _full_t := 0.0 # seconds the full meter still shows after it gave in
var _in_earshot := false # the dog being played is close enough to bark at it
var _path: Array = [] # caught: the way to the dog
var _repath := 0.0
var _flee_dir := Vector3.ZERO
var _target := Vector3.ZERO
var _going := false
var _wait := 0.0
var _hold := 0.0
var _graze := false
var _model: Node3D # the furry model
var _shorn: Node3D # the model it shows while its coat grows back, or null
var _anim: AnimationPlayer # the loops of whichever model shows
var _anim_fur: AnimationPlayer
var _anim_shorn: AnimationPlayer
var _coat_t := 0.0 # seconds before the coat is looked at again
var _loops := {"idle": "Idle", "walk": "Walk", "run": "Run"}


func setup(m: Node, manager: Node, id: String, n: int, data: Dictionary, rects: Array) -> void:
	main = m
	wl = manager
	species = id
	key = "%s_%d" % [id, n]
	info = data
	habitats = rects
	name = "Wild_" + key
	for k in (info.get("loops", {}) as Dictionary):
		_loops[k] = str(info["loops"][k])


func _ready() -> void:
	_model = Catalog.model(str(info.get("model", "")), self)
	_anim_fur = _loops_of(_model)
	if info.has("shorn_model"):
		_shorn = Catalog.model(str(info["shorn_model"]), self)
		_anim_shorn = _loops_of(_shorn)
	_anim = _anim_fur
	# a stand-in made from another species' model (2026-11-26, until Tripo is back): resized and tinted
	for m in [_model, _shorn]:
		if m != null:
			restyle(m, info)
	if _anim == null: # no model: a soft ball in its colour, so it is still there to find
		_model = Node3D.new()
		add_child(_model)
		Catalog.ball(_model, 0.18, Vector3(0, 0.2, 0), Color.html(str(wl.fibre_info(fibre()).get("color", "#a08060"))), Vector3(1, 0.9, 1.4))
	var body := StaticBody3D.new() # a click on it opens its menu (layer 2, meta "target", as the sheep)
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var s := float(info.get("click", 0.5))
	bs.size = Vector3(s * 0.8, s, s * 1.4)
	cs.shape = bs
	cs.position.y = s * 0.5
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	rotation.y = randf() * TAU
	_wait = randf_range(0.5, 4.0)
	_show_coat()
	visibility_changed.connect(_show_coat) # coming back into view after the cull: the coat as it is now


## A model's AnimationPlayer with its loops set to loop and the idle playing, or null.
func _loops_of(m: Node3D) -> AnimationPlayer:
	if m == null:
		return null
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return null
	var ap := aps[0] as AnimationPlayer
	for n in ["Idle", "Walk", "Run", "Graze"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if ap.has_animation(_loops["idle"]):
		ap.play(_loops["idle"])
		ap.seek(randf() * 3.0, true) # they don't breathe in step
	return ap


func display_name() -> String:
	return "%s  · %s" % [str(info.get("name", species.capitalize())), wl.tier_name(tier())]


func tier() -> String:
	return str(info.get("tier", "common"))


func fibre() -> String:
	return str(info.get("fibre", "wool"))


## Whether the model loaded with its loops (for the autotest).
func ok() -> bool:
	return _has_loops(_anim_fur)


## Whether its shorn model loaded with its loops (for the autotest).
func shorn_ok() -> bool:
	return _shorn != null and _has_loops(_anim_shorn)


func _has_loops(ap: AnimationPlayer) -> bool:
	if ap == null:
		return false
	for k in ["idle", "walk"]:
		if not ap.has_animation(_loops[k]):
			return false
	return true


## Which model shows right now: "furry" or "shorn" (for the autotest).
func coat() -> String:
	return "shorn" if _shorn != null and _shorn.visible else "furry"


func current_loop() -> String:
	return _anim.current_animation if _anim else ""


func loop_rate() -> float:
	return _anim.speed_scale if _anim else 0.0


## Stands still for a while (she is coming over to it, or combing it).
func hold(seconds: float) -> void:
	_hold = seconds
	_going = false


func scare(from: Vector3) -> void:
	if caught or penned:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.05:
		away = -global_transform.basis.z
	_flee_dir = away.normalized()
	fleeing = FLEE_TIME
	_hold = 0.0
	_going = false


# --- its coat --------------------------------------------------------------------------------

func has_fur() -> bool:
	return regrow() >= 1.0


## 0..1: how far its coat has grown back since the last comb.
func regrow() -> float:
	var wild: Dictionary = Game.flag("wild", {})
	if not wild.has(key):
		return 1.0
	var days := maxf(1.0, float(info.get("regrow_days", 1)))
	return clampf(float(Game.day - int(wild[key])) / days, 0.0, 1.0)


func comb() -> void:
	var wild: Dictionary = (Game.flag("wild", {}) as Dictionary).duplicate()
	wild[key] = Game.day
	Game.set_flag("wild", wild)
	_show_coat()


## The shorn model while its coat grows back, the furry one once it's back. It follows the coat's
## state (looked at every couple of seconds, on coming into view and when it's combed or penned),
## so a loaded save, a restock and a new morning all come out right. The hidden model's loops stop.
func _show_coat() -> void:
	if _shorn == null or _model == null:
		return
	var bare := not has_fur()
	_model.visible = not bare
	_shorn.visible = bare
	_model.process_mode = Node.PROCESS_MODE_DISABLED if bare else Node.PROCESS_MODE_INHERIT
	_shorn.process_mode = Node.PROCESS_MODE_INHERIT if bare else Node.PROCESS_MODE_DISABLED
	var was := _anim
	_anim = _anim_shorn if bare else _anim_fur
	if _anim and was and was != _anim and _anim.has_animation(was.current_animation):
		_anim.play(was.current_animation) # it carries on with what it was doing
		_anim.speed_scale = was.speed_scale


## The ground each loop of the model showing covers a second at speed 1 (times `model_scale`: a
## model drawn twice as big covers twice the ground).
func stride() -> Dictionary:
	var st: Dictionary = info.get("stride", {})
	if _anim != null and _anim == _anim_shorn:
		st = info.get("shorn_stride", st)
	var k := float(info.get("model_scale", 1.0))
	if is_equal_approx(k, 1.0):
		return st
	var out := {}
	for n in st:
		out[n] = float(st[n]) * k
	return out


## A stand-in's look (data/wildlife.json): `model_scale` resizes the model and `tint` multiplies its
## colours (each surface's material is copied, so the species it was borrowed from keeps its own).
## Static, so the Field Guide's pictures can match.
static func restyle(m: Node3D, info: Dictionary) -> void:
	var k := float(info.get("model_scale", 1.0))
	if not is_equal_approx(k, 1.0):
		m.scale *= k
	if not info.has("tint"):
		return
	var tint := Color.html(str(info["tint"]))
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var mat := inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var own := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				own.albedo_color = own.albedo_color * tint
				inst.set_surface_override_material(i, own)


## Its menu: comb it (or wait for its coat), or just watch it. Opening the menu holds it still.
func ke_actions() -> Array:
	if caught:
		return [main._act("noop", "It's following the dog home to the pen", false)]
	hold(12.0)
	var fname: String = wl.item_name(fibre())
	var verb := "Shear  (+1 %s)" % fname if species == "sheep" else "Comb its coat  (+1 %s)" % fname
	var a: Dictionary = main._act("comb", verb, has_fur())
	if not has_fur():
		a["label"] = "Shear" if species == "sheep" else "Comb its coat"
		a["hint"] = "coat growing back"
		a["progress"] = regrow()
	var rows := [a]
	if penned:
		rows.append(main._act("free", "Let it go"))
	rows.append(main._act("watch", "Watch it a while"))
	return rows


func ke_action(id: String) -> void:
	match id:
		"comb":
			if not has_fur():
				main.hud.show_toast("Its coat hasn't grown back yet.")
				return
			if Game.use_energy(3.0):
				hold(4.0)
				main.player.start_activity("Shearing" if species == "sheep" else "Combing", 2.0, Callable(wl, "combed").bind(self))
		"free":
			wl.set_free(self)
		"watch":
			hold(5.0)
			Game.add_need("happiness", 3.0)
			main.hud.show_toast(wl.watch_line(self))


# --- moving ------------------------------------------------------------------------------------

var _grounded := false # stood on the ground's height once (the hills, regions.relief)

func _process(delta: float) -> void:
	if main == null:
		return
	if not _grounded and main.regions: # where it was put down (a hillside, perhaps), before its first step
		_grounded = true
		position.y = main.regions.relief(position.x, position.z)
	_coat_t -= delta
	if _coat_t <= 0.0 and _shorn != null:
		_coat_t = randf_range(1.5, 2.5)
		_show_coat()
	var threat = null if (caught or penned) else wl.threat_to(self)
	if threat != null and fleeing < FLEE_TIME * 0.6:
		scare(threat)
	if not caught and not penned and fright > 0.0:
		_calm(delta)
	var hear: bool = not caught and not penned and main.dog != null and main.dog.controlled and main.dog.visible \
		and Vector2(main.dog.position.x - position.x, main.dog.position.z - position.z).length() < wl.BARK_RANGE * METER_NEAR
	if hear != _in_earshot or _full_t > 0.0:
		_in_earshot = hear
		_full_t = maxf(0.0, _full_t - delta)
		_show_meter()
	var want := 0.0
	var dir := Vector3.ZERO
	if caught:
		var step_to = _follow(delta)
		if step_to != null:
			dir = (step_to as Vector3)
			want = _follow_speed()
	elif fleeing > 0.0:
		fleeing -= delta
		dir = _clear_way(_flee_dir, false)
		_flee_dir = dir if dir != Vector3.ZERO else _flee_dir
		want = float(info.get("run", 2.5)) if dir != Vector3.ZERO else 0.0
	elif _hold > 0.0:
		_hold -= delta
		_face_nora(delta)
	elif _going:
		var to := _target - position
		to.y = 0.0
		if to.length() < 0.25:
			_going = false
			_wait = randf_range(2.0, 7.0)
			_graze = randf() < 0.6
		else:
			dir = _clear_way(to.normalized(), true)
			if dir == Vector3.ZERO:
				_going = false
				_wait = randf_range(1.0, 3.0)
			want = minf(float(info.get("walk", 0.5)), maxf(0.15, sqrt(2.0 * BRAKE * to.length())))
	else:
		_wait -= delta
		if _wait <= 0.0:
			_pick_target()
	speed = move_toward(speed, want, (ACCEL if want > speed else BRAKE) * delta)
	if dir != Vector3.ZERO and speed > 0.01:
		var step := dir * speed * delta
		position += step
		position.y = main.regions.relief(position.x, position.z) if main.regions else 0.0 # up over the hills and dunes
		walked += step.length()
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-delta * TURN))
	_play_gait()


## A bark reached it: `gain` more fright, and the meter shows. True if that was enough to make
## it give in.
func frighten(gain: float) -> bool:
	fright = clampf(fright + gain, 0.0, 1.0)
	_calm_t = 0.0
	if fright >= 1.0:
		_full_t = METER_FULL # the full meter stays up a moment: this is when it starts to follow
	_show_meter()
	return fright >= 1.0


## Left alone for a couple of seconds it starts to calm down again.
func _calm(delta: float) -> void:
	_calm_t += delta
	if _calm_t > CALM_AFTER:
		fright = maxf(0.0, fright - delta * CALM_RATE)
	_show_meter()


## The fright meter: the word "Fright" and a bar over its head that fills from yellow to red.
## It shows, empty, as soon as a dog the player is playing comes within earshot, so there is
## something to fill; full, it turns green and says "Following!" for a moment, which is when the
## animal falls in behind the dog. Hidden when it's calm with no dog about, caught or penned.
func _show_meter() -> void:
	var full := _full_t > 0.0
	var show := full or ((fright > 0.001 or _in_earshot) and not caught and not penned)
	if _meter == null:
		if not show:
			return
		_meter = Node3D.new()
		_meter.name = "Fright"
		_meter.position.y = float(info.get("click", 0.5)) + 0.5
		add_child(_meter)
		var word := Label3D.new()
		word.name = "Word"
		word.font_size = 44
		word.pixel_size = 0.0042
		word.outline_size = 12
		word.no_depth_test = true
		word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		word.position.y = 0.2
		_meter.add_child(word)
		for i in 2: # the dark back, then the fill on top of it
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(METER_W + 0.07, 0.18) if i == 0 else Vector2(METER_W, 0.11)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m.no_depth_test = true
			m.render_priority = i
			m.albedo_color = Color(0.14, 0.1, 0.08, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			q.material = m
			mi.mesh = q
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_meter.add_child(mi)
	_meter.visible = show
	if show:
		var fill := 1.0 if full else fright
		var q: QuadMesh = (_meter.get_child(2) as MeshInstance3D).mesh
		q.size.x = METER_W * fill
		q.center_offset.x = -METER_W * 0.5 * (1.0 - fill)
		(q.material as StandardMaterial3D).albedo_color = Color(0.45, 0.9, 0.4) if full else Color(1.0, 0.86, 0.3).lerp(Color(1.0, 0.25, 0.18), fright)
		var word := _meter.get_child(0) as Label3D
		word.text = "Following!" if full else "Fright"
		word.modulate = Color(0.75, 1.0, 0.7) if full else Color(1.0, 0.95, 0.82)


## Caught: the next direction along the way to the dog (to Nora if he isn't about), or null when
## it's close enough (or they are too far off to follow, and it waits).
func _follow(delta: float) -> Variant:
	var lead: Node3D = wl.leader()
	var gap := Vector2(lead.position.x - position.x, lead.position.z - position.z).length()
	if gap < 2.0 or gap > wl.CULL:
		_path = []
		return null
	_repath -= delta
	if _repath <= 0.0 or _path.is_empty():
		_repath = 0.6
		_path = main._find_path(position, lead.position)
	while not _path.is_empty():
		var to: Vector3 = (_path[0] as Vector3) - position
		to.y = 0.0
		if to.length() < 0.3:
			_path.remove_at(0)
			continue
		return to.normalized()
	return null


## It keeps up with him whatever its legs: a little faster than he is going, never slower than
## its own walk.
func _follow_speed() -> float:
	return clampf(float(wl.leader().speed) + 0.6, float(info.get("walk", 0.5)), 4.6)


## Moves into her pen for good: a new key for its coat, the pen for a habitat.
func make_penned(pen_key: String, pen: Rect2) -> void:
	key = pen_key
	name = "Penned_" + pen_key
	_show_coat() # a new key: its coat in the pen
	caught = false
	penned = true
	fleeing = 0.0
	fright = 0.0
	_show_meter()
	_path = []
	_going = false
	habitats = [pen]
	_wait = randf_range(0.5, 2.0)


## The way to go: straight on if the ground ahead is open, else the nearest turn that is. While it
## wanders it keeps to its habitat; bolting, it goes anywhere it can walk.
func _clear_way(dir: Vector3, keep_home: bool) -> Vector3:
	var base := atan2(dir.x, dir.z)
	for off in STEER:
		var a := base + float(off)
		var d := Vector3(sin(a), 0.0, cos(a))
		var p := position + d * PROBE
		if not main._walkable(main._cell(p)):
			continue
		if keep_home and not _at_home(p) and _at_home(position):
			continue
		return d
	return Vector3.ZERO


func _at_home(p: Vector3) -> bool:
	for r in habitats:
		if (r as Rect2).grow(0.5).has_point(Vector2(p.x, p.z)):
			return true
	return false


## The next spot to amble to: a few metres off, inside its habitat, on open ground. Out of its
## habitat (it bolted out), it heads back to the nearest one.
func _pick_target() -> void:
	var home: Rect2 = habitats[0] if not habitats.is_empty() else Rect2(position.x - 5, position.z - 5, 10, 10)
	var best := INF
	for r in habitats:
		var c := (r as Rect2).get_center()
		var d := Vector2(position.x, position.z).distance_to(c)
		if (r as Rect2).has_point(Vector2(position.x, position.z)):
			d = 0.0
		if d < best:
			best = d
			home = r
	for i in 10:
		var p := position + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
		if best > 0.0: # coming home: somewhere inside it
			p = Vector3(randf_range(home.position.x, home.end.x), 0.0, randf_range(home.position.y, home.end.y))
		if not home.has_point(Vector2(p.x, p.z)) or not main._walkable(main._cell(p)):
			continue
		_target = p
		_going = true
		return
	_wait = randf_range(1.0, 3.0)


func _face_nora(delta: float) -> void:
	if main.player == null:
		return
	var to: Vector3 = main.player.position - position
	to.y = 0.0
	if to.length() > 0.3 and to.length() < 4.0:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 3.0))


## Picks the loop for its speed and plays it at the rate that keeps its paws planted.
func _play_gait() -> void:
	if _anim == null:
		return
	var walk := float(info.get("walk", 0.5))
	var run := float(info.get("run", 2.5))
	var k := "idle"
	if speed > 0.05:
		k = "run" if speed > (walk + run) * 0.5 and _anim.has_animation(_loops["run"]) else "walk"
	var want: String = _loops[k]
	if k == "idle" and _graze and _loops.has("graze") and _anim.has_animation(_loops["graze"]):
		want = _loops["graze"]
	if _anim.current_animation != want and _anim.has_animation(want):
		_anim.play(want, BLEND)
	var strides := stride()
	if k != "idle" and strides.has(want):
		_anim.speed_scale = maxf(speed / float(strides[want]), MIN_RATE)
	else:
		_anim.speed_scale = 1.0
