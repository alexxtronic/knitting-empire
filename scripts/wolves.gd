extends Node3D
## Wolves at night (Alex, 2026-11-16, docs/DIRECTION.md "The guided opening and how the player
## scales": "small chance a wolf can kill an animal each night, player is alerted if it happens and
## can scare the wolves off manually in a short time window"). The numbers are data/wolves.json.
##
## Once a night, at the data's `hour`, there's a small `chance` that wolves come for her pens: only
## once Act 1 is done, and only if some animal is at risk (at_risk()). Housed sheep (in their barn
## stalls at bedtime, main._update_flock) are safe, and while Lars's barn rent is paid up
## (wildlife.stalls_rented()) its `barn_stalls` shelter that many more: the penned wild animals
## first, then any sheep still out in the pen. Everything else is in an open pen.
##
## When they come: a howl, a toast, and one to three wolves of the three sizes walk in from the woods
## to stand at the pen. She has `window` real seconds to see them off herself: Nora running at a wolf,
## or the dog's bark while she plays him (main.dog_bark() calls barked()), takes one of its `nerve`
## (the bigger, the more), and a wolf with none left runs back into the woods. Miss the window and
## they take one animal at risk; the morning note says which. Asleep through the night (in bed before
## `hour`), the night is rolled in the morning instead, and a hit takes one while she slept.
##
## The state is Game.flags["wolves"]: {"night": the last day rolled, "raids", "seen_off", "lost",
## and while they're here "raid": {"left": seconds, "pack": the sizes still about}}, so a reload
## doesn't send them away; and Game.flags["wolf_note"], the morning's word about a loss.
##
## Taming (later, not built): Alex wants her to tame the wolves later and have them round up
## animals for her by themselves. The hook is tamed(): once Game.flags["wolves_tamed"] is true the
## wild ones stop coming (roll() returns at once). A tamed pack's behaviour belongs in its own
## script; it must follow the 2026-11-16 rule that herding is the player's, so think of it as a
## second animal the player plays, or a separate rule Alex approves, not the dog herding by himself.
##
## The models: each size's `model` (wolf_small/medium/large.glb, being made in another session)
## falls back to the coyote scaled up (`fallback_model`) until it's in the project.

const Data = preload("res://scripts/data.gd")
const Catalog = preload("res://scripts/catalog.gd")

static var on := true # main.gd turns them off for the autotest but its own check

var main: Node # main.gd
var data: Dictionary = {}
var pack: Array = [] # Wolf nodes here now
var raid_left := 0.0 # seconds of the window left (0: no raid)
var force_next := false # the next roll comes up wolves (the autotest)
var _rng := RandomNumberGenerator.new()
var _save_t := 0.0
var _resumed := false


func _ready() -> void:
	name = "Wolves"
	data = Data.load_json("wolves")
	_rng.randomize()


func state() -> Dictionary:
	var s: Variant = Game.flag("wolves", {})
	return (s as Dictionary).duplicate(true) if s is Dictionary else {}


func _set_state(s: Dictionary) -> void:
	Game.set_flag("wolves", s)


func num(k: String, fallback: float) -> float:
	return float(data.get(k, fallback))


## Later in the game she tames them (not built yet): then the wild ones stop coming.
func tamed() -> bool:
	return Game.flag("wolves_tamed") == true


func active() -> bool:
	return raid_left > 0.0


# --- who is at risk ---------------------------------------------------------------------------

## The animals the wolves could take tonight: [{"kind": "wild", "key", "species"} or
## {"kind": "sheep", "i": index in main.sheep_list}], wild ones first. Housed sheep are safe, and the
## rented barn stalls shelter the first `barn_stalls` of the rest.
func at_risk() -> Array:
	var out: Array = []
	var wl = main.wildlife
	if wl:
		for e in wl.penned_list():
			out.append({"kind": "wild", "key": str((e as Dictionary).get("key", "")), "species": str((e as Dictionary).get("species", ""))})
	for i in Game.sheep_count:
		var s = main.sheep_list[i] if i < main.sheep_list.size() else null
		if s != null and s.housed:
			continue
		out.append({"kind": "sheep", "i": i})
	if wl and wl.stalls_rented():
		var stalls := int(wl.data.get("barn_stalls", 4))
		out = out.slice(mini(stalls, out.size()))
	return out


func _story_ok() -> bool:
	return Game.flag("act1_done") == true or Game.flag("story_farm") != true


# --- the nightly roll -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null:
		return
	if not _resumed:
		_resumed = true
		_resume()
	if active():
		_update_raid(delta)
		return
	if not on or main.title_on or main.sleeping or main.story.is_playing():
		return
	if Game.hour >= num("hour", 21.0) and Game.hour < 24.0 and int(state().get("night", -1)) != Game.day:
		roll(Game.day, false)


## Rolls the night `night`: wolves come (true) or not. Awake, they walk in and she has her window;
## asleep, they take one at once (the morning note says which).
func roll(night: int, asleep: bool) -> bool:
	var s := state()
	s["night"] = night
	_set_state(s)
	if tamed() or not _story_ok():
		return false
	var risk := at_risk()
	if risk.is_empty():
		force_next = false
		return false
	var hit := force_next or _rng.randf() < num("asleep_chance" if asleep else "chance", 0.125)
	force_next = false
	if not hit:
		return false
	s["raids"] = int(s.get("raids", 0)) + 1
	_set_state(s)
	# Rowan, while she pays him to watch the pen (shepherd.gd), stops about half the raids on the
	# animals the barn doesn't shelter: they never reach the pen.
	if main.get("shepherd") != null and main.shepherd.stops(night):
		s["rowan_stopped"] = int(s.get("rowan_stopped", 0)) + 1
		_set_state(s)
		var line := "Rowan was walking your fence %s: he heard the wolves in the woods and drove them off before they reached the pen." % ("in the night" if asleep else "tonight")
		if asleep:
			Game.set_flag("wolf_note", line)
		else:
			main.hud.show_toast(line)
		return true
	if asleep:
		_take_one("While you slept, wolves came out of the woods and took %s.")
		return true
	var n := _rng.randi_range(int(num("min_pack", 1)), int(num("max_pack", 3)))
	start_raid(n)
	return true


## The wolves come: the howl, the warning, and `n` of them walking in from the woods.
func start_raid(n: int, left := -1.0) -> void:
	var order: Array = data.get("pack_order", ["medium", "small", "large"])
	var sizes: Array = []
	for i in clampi(n, 1, order.size()):
		sizes.append(str(order[i]))
	_begin(sizes, num("window", 45.0) if left < 0.0 else left, false)
	main.audio.play("howl", -2.0)
	var who := "A wolf is" if sizes.size() == 1 else "%d wolves are" % sizes.size()
	main.hud.show_toast("A howl from the woods! %s coming for your animals. Run at them, or play the dog (Tab) and bark, to see them off.  (%d s)" % [who, int(raid_left)])


func _begin(sizes: Array, left: float, at_pen: bool) -> void:
	clear()
	raid_left = maxf(left, 0.5)
	var home := pen_centre()
	var from := _spawn_point(home)
	for i in sizes.size():
		var w := Wolf.new()
		w.setup(self, str(sizes[i]), (data.get("sizes", {}) as Dictionary).get(str(sizes[i]), {}))
		var off := Vector3((i - (sizes.size() - 1) * 0.5) * 1.6, 0, float(i % 2) * 1.2)
		w.den = from + off
		w.goal = _stand_spot(home, from, i, sizes.size())
		w.position = w.goal if at_pen else w.den
		add_child(w)
		pack.append(w)
		w.go_to(w.goal)
	_note_raid()


## A reload in the middle of a raid: they're still at the pen with the time that was left.
func _resume() -> void:
	var s := state()
	if not on or not s.has("raid"):
		return
	var r: Dictionary = s["raid"]
	var sizes: Array = r.get("pack", [])
	if sizes.is_empty() or at_risk().is_empty():
		s.erase("raid")
		_set_state(s)
		return
	_begin(sizes, float(r.get("left", num("window", 45.0))), true)


func _note_raid() -> void:
	var s := state()
	s["raid"] = {"left": raid_left, "pack": pack.filter(func(w): return not w.fleeing).map(func(w): return w.size_id)}
	_set_state(s)


func pen_rect() -> Rect2:
	var r: Rect2 = main.wildlife.pen() if main.wildlife else Rect2()
	return r if r.has_area() else main.pen_rect


func pen_centre() -> Vector3:
	var c := pen_rect().get_center()
	return Vector3(c.x, 0, c.y)


## Where they come out of the woods: `spawn_dist` off, somewhere walkable with a way to the pen.
func _spawn_point(home: Vector3) -> Vector3:
	var d := num("spawn_dist", 30.0)
	var a0 := _rng.randf() * TAU
	for k in 24:
		var a := a0 + k * TAU / 24.0
		var p := home + Vector3(cos(a), 0, sin(a)) * d
		if main._walkable(main._cell(p)) and not main._find_path(p, home).is_empty():
			return p
	return home + Vector3(0, 0, -d)


## Each one's place just outside the pen, on the side they came from, a little apart.
func _stand_spot(home: Vector3, from: Vector3, i: int, n: int) -> Vector3:
	var r := pen_rect()
	var dir := (from - home)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0, dir.x)
	var reach := maxf(r.size.x, r.size.y) * 0.5 + 2.2
	var p := home + dir * reach + side * ((i - (n - 1) * 0.5) * 2.0)
	var c = main._nearest_walkable(main._cell(p), p)
	return main._cell_center(c) if c != null else p


# --- the window -------------------------------------------------------------------------------

func _update_raid(delta: float) -> void:
	var paused: bool = main.title_on or main.story.is_playing() or main.cinema.active
	if main.sleeping: # she went to bed with them at the pen
		_lose("The wolves didn't wait for morning: they took %s in the night.")
		return
	if not paused:
		raid_left -= delta
	pack = pack.filter(func(w): return is_instance_valid(w))
	var here: Array = pack.filter(func(w): return not w.fleeing)
	if here.is_empty():
		_seen_off()
		return
	_check_nora(here)
	if raid_left <= 0.0:
		_lose("The wolves got into the pen and took %s before you could stop them.")
		return
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 1.0
		_note_raid()


## Nora running at a wolf inside `shy` metres takes some of its nerve.
func _check_nora(here: Array) -> void:
	var p = main.player
	if p == null or not (p.running and p.speed > p.walk_speed + 0.3):
		return
	for w in here:
		if _flat(p.global_position, w.global_position) < num("shy", 7.0):
			w.hit(p.global_position)


## The dog barked at `at` (main.dog_bark): every wolf near enough loses some nerve. Only while she
## plays him: by her side he does nothing by himself. Returns how many it reached.
func barked(at: Vector3) -> int:
	if not active() or main.dog == null or not main.dog.controlled:
		return 0
	var n := 0
	for w in pack:
		if is_instance_valid(w) and not w.fleeing and _flat(at, w.global_position) < num("bark_range", 10.0):
			w.hit(at, true)
			n += 1
	return n


func _seen_off() -> void:
	var s := state()
	s["seen_off"] = int(s.get("seen_off", 0)) + 1
	s.erase("raid")
	_set_state(s)
	raid_left = 0.0
	Game.add_need("happiness", 10.0)
	main.hud.show_toast("You saw the wolves off! Your animals are safe tonight.")


func _lose(fmt: String) -> void:
	raid_left = 0.0
	for w in pack:
		if is_instance_valid(w) and not w.fleeing:
			w.flee(pen_centre())
	var s := state()
	s.erase("raid")
	_set_state(s)
	_take_one(fmt)


## One animal at risk is gone: a penned wild one before a sheep. The note goes in the morning's
## greeting (morning_note) and shows now if she's awake.
func _take_one(fmt: String) -> String:
	var risk := at_risk()
	if risk.is_empty():
		return ""
	var e: Dictionary = risk[_rng.randi() % risk.size()]
	var what := ""
	if str(e["kind"]) == "wild":
		var key := str(e["key"])
		var sp := str(e["species"])
		var info: Dictionary = (main.wildlife.data.get("animals", {}) as Dictionary).get(sp, {})
		what = "your %s" % str(info.get("name", sp)).to_lower()
		Game.set_flag("penned", main.wildlife.penned_list().filter(func(x): return str((x as Dictionary).get("key", "")) != key))
		for a in main.wildlife.animals.duplicate():
			if is_instance_valid(a) and a.penned and a.key == key:
				main.wildlife.animals.erase(a)
				a.queue_free()
	else:
		var i := int(e["i"])
		what = "one of your sheep"
		Game.sheep_count = maxi(0, Game.sheep_count - 1)
		if i < main.sheep_list.size():
			var sh = main.sheep_list[i]
			main.sheep_list.remove_at(i)
			sh.queue_free()
	var s := state()
	s["lost"] = int(s.get("lost", 0)) + 1
	var taken: Array = s.get("taken", [])
	taken.append({"day": Game.day, "what": what})
	s["taken"] = taken.slice(-10)
	_set_state(s)
	var line := fmt % what
	Game.set_flag("wolf_note", line)
	Game.add_need("happiness", -15.0)
	if not main.sleeping:
		main.hud.show_toast(line + " Stalls in Lars's barn keep them safe at night, or pay Rowan to watch the pen for half as much.")
	return what


## For the morning's greeting (main._on_day_started): rolls a night she slept through, then any
## word of a loss, once.
func morning_note(day: int) -> String:
	if active():
		_lose("The wolves didn't wait for morning: they took %s in the night.")
	if on and int(state().get("night", -1)) < day - 1 and Game.hour < num("hour", 21.0):
		roll(day - 1, true)
	var note: String = str(Game.flag("wolf_note", ""))
	Game.flags.erase("wolf_note")
	return "  " + note if note != "" else ""


func clear() -> void:
	for w in pack:
		if is_instance_valid(w):
			w.queue_free()
	pack = []
	raid_left = 0.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- one wolf ---------------------------------------------------------------------------------

class Wolf extends Node3D:
	const BLEND := 0.3
	const MIN_RATE := 0.55
	const FLEE_SECS := 7.0 # it's gone into the woods after this
	var wolves: Node # wolves.gd
	var size_id := ""
	var info: Dictionary = {}
	var nerve := 1
	var fleeing := false
	var den := Vector3.ZERO # where it came out of the woods, and runs back to
	var goal := Vector3.ZERO # its place at the pen
	var speed := 0.0
	var _path: Array = []
	var _hit_t := 0.0
	var _flee_t := 0.0
	var _model: Node3D
	var _anim: AnimationPlayer
	var _tag: Label3D
	var _stride: Dictionary = {}
	var _scale := 1.0

	func setup(w: Node, id: String, d: Dictionary) -> void:
		wolves = w
		size_id = id
		info = d
		nerve = maxi(1, int(d.get("nerve", 1)))
		name = "Wolf_" + id

	func _ready() -> void:
		var path := str(info.get("model", ""))
		_scale = float(info.get("scale", 1.0))
		_stride = info.get("stride", {})
		if not ResourceLoader.exists(path): # the wolf models aren't in yet: the coyote, bigger
			path = str(wolves.data.get("fallback_model", ""))
			_stride = wolves.data.get("fallback_stride", {})
		else:
			_scale = float(info.get("model_scale", 1.0))
		_model = Catalog.model(path, self)
		if _model:
			_model.scale = Vector3.ONE * _scale
			var aps := _model.find_children("*", "AnimationPlayer", true, false)
			_anim = aps[0] if not aps.is_empty() else null
		if _anim:
			for n in ["Idle", "Walk", "Run"]:
				if _anim.has_animation(n):
					_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			if _anim.has_animation("Idle"):
				_anim.play("Idle")
		var body := StaticBody3D.new() # clickable like the wild animals (layer 2): she can walk at it
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var s := float(info.get("click", 0.9))
		bs.size = Vector3(s * 0.7, s, s * 1.5)
		cs.shape = bs
		cs.position.y = s * 0.5
		body.add_child(cs)
		add_child(body)
		_tag = Label3D.new() # its nerve left, as dots over its head
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.fixed_size = true
		_tag.pixel_size = 0.0016
		_tag.font_size = 30
		_tag.outline_size = 8
		_tag.modulate = Color(1.0, 0.55, 0.45)
		_tag.position.y = float(info.get("click", 0.9)) + 0.45
		add_child(_tag)
		_show_nerve()

	func _show_nerve() -> void:
		var full := maxi(1, int(info.get("nerve", 1)))
		_tag.text = "●".repeat(nerve) + "○".repeat(full - nerve)
		_tag.visible = not fleeing

	func go_to(p: Vector3) -> void:
		_path = wolves.main._find_path(position, p)
		if _path.is_empty() and position.distance_to(p) > 0.3:
			_path = [p]

	## Something rushed or barked at it from `from`: it loses nerve, and with none left it runs.
	## Nora's rush counts once every `hit_every` seconds; every bark counts (the dog has his own
	## breath to wait for).
	func hit(from: Vector3, bark := false) -> void:
		if fleeing or (_hit_t > 0.0 and not bark):
			return
		if not bark:
			_hit_t = float(wolves.num("hit_every", 0.9))
		nerve -= 1
		_show_nerve()
		if nerve <= 0:
			flee(from)
		else: # it shies back a step or two, snarling, and comes on again
			var away := position - from
			away.y = 0.0
			if away.length() > 0.05:
				_path = [position + away.normalized() * 2.0, goal]

	func flee(_from: Vector3) -> void:
		fleeing = true
		_flee_t = FLEE_SECS
		_show_nerve()
		go_to(den)

	func _process(delta: float) -> void:
		_hit_t = maxf(0.0, _hit_t - delta)
		var want := float(info.get("run" if fleeing else "walk", 1.5))
		if fleeing:
			_flee_t -= delta
			if _flee_t <= 0.0:
				queue_free()
				return
		var moving := not _path.is_empty()
		speed = move_toward(speed, want if moving else 0.0, delta * 6.0)
		if moving:
			var to: Vector3 = _path[0] - position
			to.y = 0.0
			var step := speed * delta
			if to.length() <= maxf(step, 0.05):
				position = Vector3(_path[0].x, 0, _path[0].z)
				_path.pop_front()
			else:
				position += to.normalized() * step
				rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * 7.0))
		else: # at the pen: it faces in, waiting
			var at: Vector3 = wolves.pen_centre() - position
			if at.length() > 0.3:
				rotation.y = lerp_angle(rotation.y, atan2(at.x, at.z), 1.0 - exp(-delta * 3.0))
		_play_gait()

	func current_loop() -> String:
		return _anim.current_animation if _anim else ""

	func _play_gait() -> void:
		if _anim == null:
			return
		var k := "Idle"
		if speed > 0.05:
			k = "Run" if fleeing and _anim.has_animation("Run") else "Walk"
		if _anim.current_animation != k and _anim.has_animation(k):
			_anim.play(k, BLEND)
		if k != "Idle" and _stride.has(k):
			_anim.speed_scale = maxf(speed / (float(_stride[k]) * _scale), MIN_RATE)
		else:
			_anim.speed_scale = 1.0
