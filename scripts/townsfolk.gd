extends Node
## Maple Grove's townsfolk (Alex, 2026-11-17: "generic NPCs ... with no real purpose for the plot or
## dialogue. They're more to make the city feel alive. They wander, sit on benches, read books in the
## cafe, and generally live their life peacefully"). Who they are and what they say is
## data/townsfolk.json; each one is a Townsperson (villager.gd with its own menu), never in
## main.villagers, so no story scene, gift, job or request ever reaches them.
##
## Each day every person keeps their own hours inside "hours": they turn up at a way into town
## (home_spot()), then over and over pick something to do: walk to a spot in town, sit at the free end
## of a bench (found in main.decor wherever the world editor has put it), or drop into the café for a
## coffee and a book (cafe_visits.gd, as the regulars do). At the end of their day they walk back out
## and are gone. At most "max_out" are about at once. Far from her and the camera they are hidden and
## stop thinking (CULL, like the wildlife), and a story scene sends them all out of shot until it ends.
## A jump of the clock (sleep, a load) puts everyone back where the new hour has them.
##
## Sweaters: some days one wants a sweater ("want_chance", the same all day). Whenever anyone in town
## wants one, a red pin bobs over their head (update_pins(), for the townsfolk and the named villagers
## alike: a villager who is looking for one today by sweater_sale.gd, or has a request for her by
## empire.gd). The pin sits above the gold star when both show.
##
## main.gd builds them outside the autotest (like the wildlife); --only=townsfolk and the frame-rate
## check build them for themselves.

const Data = preload("res://scripts/data.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Townsperson = preload("res://scripts/townsperson.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Furniture = preload("res://scripts/furniture.gd")
const CULL := 50.0
const TICK := 0.5
const PIN_PX := 96
const BENCH_IDS := ["bench", "bench_short"]
const BENCH_END := 0.45 # how far along a long bench from its middle they sit, so the middle stays hers

var main: Node
var data: Dictionary = {}
var people: Array = [] # Townsperson nodes
var built := false
var paused := false # a story scene is on: everyone is out of shot
var _tick := 0.0
var _last_now := -1.0
var _pin_tex: Texture2D
var _benches := {} # "bench instance id:end" -> the person sitting there


func _cfg(key: String, default: Variant) -> Variant:
	return data.get(key, default)


static func now_h() -> float:
	return float(Game.day - 1) * 24.0 + Game.hour


## A number in 0..1 fixed for this person, day and question (so asking twice changes nothing).
static func roll(id: String, what: String, day := -1) -> float:
	return float(absi(("%d:%s:%s" % [Game.day if day < 0 else day, id, what]).hash()) % 10000) / 10000.0


func build() -> void:
	clear()
	data = Data.load_json("townsfolk")
	for d in data.get("people", []):
		var p = Townsperson.new()
		p.town = self
		p.tags = d.get("tags", [])
		p.walk_speed = float(d.get("walk_speed", p.WALK_SPEED))
		p.setup(str(d["id"]), str(d["name"]), "", "", Vector3(Town.TOWN_ARRIVE), {"model": str(d["id"]), "scale": float(d.get("scale", 1.0))})
		p.roam = Vector2.ZERO
		if p.tag:
			p.tag.visible = false # no name tags over the townsfolk: strangers, mostly
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
		main.add_child(p)
		people.append(p)
	built = true
	_last_now = -1.0
	if not main.story.scene_started.is_connected(_on_scene_started):
		main.story.scene_started.connect(_on_scene_started)
		main.story.scene_finished.connect(_on_scene_finished)


func clear() -> void:
	for p in people:
		if is_instance_valid(p):
			_end_activity(p)
			_free_bench(p)
			p.queue_free()
	people.clear()
	_benches.clear()
	for v in main.villagers: # the named villagers' pins too: nothing keeps them up to date now
		var g: Node = v.get_node_or_null("SweaterPin")
		if g:
			g.queue_free()
	_pin_want.clear()
	built = false


func find(id: String):
	for p in people:
		if p.vid == id:
			return p
	return null


# --- the day -----------------------------------------------------------------------------------

## The hours [from, to] this person is about today, inside "hours".
func day_hours(p) -> Vector2:
	var h: Array = _cfg("hours", [7.0, 20.0])
	var a := float(h[0]) + roll(p.vid, "up") * 2.5
	var b := float(h[1]) - roll(p.vid, "down") * 3.0
	return Vector2(a, b)


## Who is out right now: those whose hours it is, the first "max_out" of them in today's order.
func should_be_out(p) -> bool:
	if Game.flag("tf_off") == true:
		return false
	var hrs := day_hours(p)
	if Game.hour < hrs.x or Game.hour >= hrs.y:
		return false
	var order := people.duplicate()
	order.sort_custom(func(x, y): return roll(x.vid, "order") < roll(y.vid, "order"))
	return order.find(p) < int(_cfg("max_out", 6))


## Where they go at the end of their day. For now a way out of town ("exits"), each person always the
## same one; once Bretton Oaks gives them houses, this is their front door.
func home_spot(p) -> Vector3:
	var ex: Array = _cfg("exits", [[30.0, 3.0]])
	var e: Array = ex[int(roll(p.vid, "exit", 0) * ex.size()) % ex.size()]
	return Vector3(float(e[0]), 0, float(e[1]))


## A spot somewhere in town she could walk to, outdoors.
func town_spot() -> Vector3:
	var r: Rect2 = Town.TOWN
	for _i in 30:
		var q := Vector3(randf_range(r.position.x, r.end.x), 0, randf_range(r.position.y, r.end.y))
		if main._walkable(main._cell(q)) and not _indoors(q):
			return q
	return Vector3(Town.TOWN_ARRIVE)


func _indoors(q: Vector3) -> bool:
	for id in Interiors.shops:
		var s = Interiors.shops[id]
		if s.node and is_instance_valid(s.node):
			var local: Vector3 = (s.node as Node3D).global_transform.affine_inverse() * q
			var half: Vector2 = s.size * 0.5
			if absf(local.x) < half.x and absf(local.z) < half.y:
				return true
	return false


func _process(delta: float) -> void:
	if not built:
		return
	update_pins(delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	if main.title_on or paused:
		return
	var now := now_h()
	var jumped := _last_now >= 0.0 and absf(now - _last_now) > 1.0
	_last_now = now
	if jumped:
		place_all()
	for p in people:
		_step(p)
		_bench_walk(p)
	_cull()


## The clock jumped (a night's sleep, a loaded save): everyone is where the new hour has them, at once.
func place_all() -> void:
	for p in people:
		_end_activity(p)
		if should_be_out(p):
			p.settle_at(town_spot())
			p.state = "idle"
			p.until = now_h() + randf_range(0.02, 0.1)
			p.visible = true
		else:
			p.state = "away"
			p.visible = false


func _step(p) -> void:
	var out := should_be_out(p)
	match p.state:
		"away":
			if out:
				var at := home_spot(p)
				p.settle_at(at)
				p.visible = true
				_go(p, town_spot())
		"walking":
			if not out:
				_leave(p)
			elif _arrived(p) or now_h() > p.until:
				p.state = "idle"
				p.until = now_h() + randf_range(0.03, 0.12) # a minute or few of game time
		"idle":
			if not out:
				_leave(p)
			elif now_h() >= p.until:
				_next(p)
		"bench":
			var b = p.bench
			if not out or now_h() >= p.until or b == null or not is_instance_valid(b):
				_stand_up(p)
				if out:
					_go(p, town_spot())
				else:
					_leave(p)
		"to_bench":
			if not out:
				_free_bench(p)
				_leave(p)
		"cafe":
			if not out:
				_leave(p)
			elif not main.cafe_visits.visits.has(p.vid):
				p.state = "idle"
				p.until = now_h() + 0.05
			elif not main.town_rounds:
				main.cafe_visits._step(p.vid) # the autotest's still town doesn't step the café's visits itself
		"leaving":
			if out:
				_go(p, town_spot())
			elif _arrived(p) and p.position.distance_to(main.player.position) > 12.0:
				p.state = "away" # out of town (or, later, home to bed)
				p.visible = false


## Something new to do: a bench, the café, or a walk.
func _next(p) -> void:
	var r := randf()
	if r < float(_cfg("cafe_chance", 0.2)) and cafe_open() and main.cafe_visits.free_seats().size() > 0 \
			and main.cafe_visits.visits.size() < 3 and not main.barista.active:
		p.home = p.position
		if main.cafe_visits.start(p.vid):
			p.state = "cafe"
			return
	if r < float(_cfg("cafe_chance", 0.2)) + float(_cfg("bench_chance", 0.3)) and sit_on_bench(p):
		return
	_go(p, town_spot())


func cafe_open() -> bool:
	var cfg: Dictionary = Interiors.shops["cafe"].info.get("visits", {}) if Interiors.shops.has("cafe") else {}
	var hrs: Array = cfg.get("hours", [8, 20])
	return not cfg.is_empty() and Game.hour >= float(hrs[0]) and Game.hour < float(hrs[1])


func _go(p, to: Vector3) -> void:
	p.anim_override = ""
	p.position.y = 0.0
	p.goal = to
	p.walk_to(to, main._find_path(p.position, to))
	p.state = "walking"
	p.until = now_h() + 1.5 # given up on after a game hour and a half (a path that never ends)


func _leave(p) -> void:
	_end_activity(p)
	if not p.visible:
		p.state = "away"
		return
	p.goal = home_spot(p)
	p.walk_to(p.goal, main._find_path(p.position, p.goal))
	p.state = "leaving"


func _arrived(p) -> bool:
	return Vector2(p.position.x - p.goal.x, p.position.z - p.goal.z).length() < 0.4 or (p._via.is_empty() and p._wait > 0.0)


func _end_activity(p) -> void:
	if p.state == "bench":
		_stand_up(p)
	_free_bench(p) # on the way to one too
	if p.state == "cafe" and main.cafe_visits.visits.has(p.vid):
		var vis: Dictionary = main.cafe_visits.visits[p.vid]
		var seated: bool = str(vis["state"]) == "reading" and vis["seat"] != null and is_instance_valid(vis["seat"])
		var up: Vector3 = vis["seat"].stand_point() if seated else p.position
		main.cafe_visits._free(vis)
		main.cafe_visits.visits.erase(p.vid)
		p.anim_override = ""
		p.position = Vector3(up.x, 0.0, up.z) # out of the seat onto the floor, where a path can start


# --- benches -----------------------------------------------------------------------------------

## The town's benches as they stand now (the world editor can move or delete any of them).
var _bench_list: Array = []
var _bench_at := -1000.0 # looked for again every 30 s (the world editor can move them)


func benches() -> Array:
	var now := Time.get_ticks_msec() * 0.001
	if now - _bench_at > 30.0 or _bench_list.any(func(f): return not is_instance_valid(f)):
		_bench_at = now
		_bench_list.clear()
		var area: Rect2 = Town.TOWN.grow(6.0)
		for f in main.find_children("*", "Node3D", true, false): # copies the world editor made too
			if f is Furniture and not f.is_ghost and str(f.item_id) in BENCH_IDS and f.is_visible_in_tree():
				var g: Vector3 = f.global_position
				if area.has_point(Vector2(g.x, g.z)):
					_bench_list.append(f)
	return _bench_list


## The places on bench `f` a townsperson may take: one at each end of a long bench, the middle of a short one.
func bench_ends(f) -> Array:
	if str(f.item_id) == "bench_short":
		return [0.0]
	return [-BENCH_END, BENCH_END]


func _bench_key(f, end: float) -> String:
	return "%d:%.2f" % [f.get_instance_id(), end]


## Where they sit on bench `f` at `end` (their origin) and where they stand to sit down.
func bench_seat(f, end: float) -> Vector3:
	var side: Vector3 = f.front().cross(Vector3.UP).normalized()
	return main._seat_point(f) + side * end


func bench_stand(f, end: float) -> Vector3:
	var s: Vector3 = bench_seat(f, end) + f.front() * 0.55
	return Vector3(s.x, 0, s.z)


## Sends `p` to the nearest free bench end, if there is one nobody (Nora included) is on.
func sit_on_bench(p) -> bool:
	var best = null
	var best_end := 0.0
	var bd := INF
	for f in benches():
		for end in bench_ends(f):
			var key := _bench_key(f, end)
			var who = _benches.get(key)
			if who != null and is_instance_valid(who):
				continue
			var seat := bench_seat(f, end)
			if main.player.position.distance_to(seat) < 1.0:
				continue
			var d: float = p.position.distance_to(seat)
			if d < bd:
				bd = d
				best = f
				best_end = end
	if best == null:
		return false
	_benches[_bench_key(best, best_end)] = p
	p.bench = best
	p.bench_end = best_end
	var at := bench_stand(best, best_end)
	p.goal = at
	p.walk_to(at, main._find_path(p.position, at))
	p.state = "to_bench"
	p.until = now_h() + 1.0
	return true


## Down on the bench, for a while.
func sit(p) -> void:
	var f = p.bench
	p.settle_at(bench_seat(f, p.bench_end))
	var fr: Vector3 = f.front()
	p.rotation.y = atan2(fr.x, fr.z)
	p.anim_override = "SitIdle"
	p.state = "bench"
	var h: Array = _cfg("bench_hours", [0.6, 1.6])
	p.until = now_h() + randf_range(float(h[0]), float(h[1]))


func _stand_up(p) -> void:
	if p.anim_override == "SitIdle":
		p.anim_override = ""
	p.position.y = 0.0
	if p.bench != null and is_instance_valid(p.bench):
		p.position = bench_stand(p.bench, p.bench_end)
	_free_bench(p)


func _free_bench(p) -> void:
	for k in _benches.keys():
		if _benches[k] == p:
			_benches.erase(k)
	p.bench = null


## Twice a second: on the way to a bench, sit down once there.
func _bench_walk(p) -> void:
	if p.state != "to_bench":
		return
	if p.bench == null or not is_instance_valid(p.bench) or now_h() > p.until:
		_free_bench(p)
		p.state = "idle"
		p.until = now_h()
	elif Vector2(p.position.x - p.goal.x, p.position.z - p.goal.z).length() < 0.3:
		sit(p)


# --- far away, and story scenes ----------------------------------------------------------------

func _cull() -> void:
	var eyes: Array = [main.player.global_position]
	var cam := get_viewport().get_camera_3d()
	if cam:
		eyes.append(cam.global_position)
	for p in people:
		var near := false
		if p.state != "away":
			for e in eyes:
				if Vector2(p.position.x - e.x, p.position.z - e.z).length() < CULL:
					near = true
					break
		p.visible = near
		p.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
		if not near and p.state in ["walking", "leaving", "to_bench"]:
			p.settle_at(p.goal) # far off nobody sees them walk: they are simply there


func _on_scene_started(_id: String) -> void:
	paused = true
	for p in people:
		_end_activity(p)
		p.state = "away"
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED


func _on_scene_finished(_id: String) -> void:
	paused = false
	place_all()


# --- talking and selling -----------------------------------------------------------------------

## A short line for `p`: one of the lines anyone may say or that fits who they are, a new one each talk.
func line_for(p) -> String:
	var ok := []
	for l in _cfg("lines", []):
		var who: Array = l.get("who", [])
		if who.all(func(t): return t in p.tags):
			ok.append(str(l["text"]))
	if ok.is_empty():
		return "..."
	p.talks += 1
	return ok[(int(roll(p.vid, "line") * ok.size()) + p.talks) % ok.size()]


## What `v` (a townsperson or a named villager) says when talked to while their red pin is up,
## or "" when it isn't (Alex, 2026-11-24: someone with the pin should say what they're after, not
## the usual banter). A named villager with a request speaks of it; "want_lines" in the data.
func want_talk(v) -> String:
	var named: bool = not (v in people)
	var key := ""
	var r: Dictionary = main.empire.request() if main.empire != null else {}
	var fill := {}
	if named and str(r.get("who", "")) == str(v.vid):
		key = "request_ready" if main.empire._made(r) > 0 else "request_waiting"
		fill = {"what": main.empire._what(r), "pay": str(main.empire.payout() if key == "request_ready" else int(r.get("pay", 0)))}
	elif named and not villager_wants(v):
		return ""
	elif not named and not (wants(v) or (main.house_sale != null and main.house_sale.wants_sweater(v))):
		return ""
	else:
		key = "has" if Game.count("sweater") > 0 else "none"
	var tags: Array = v.tags if not named else ["adult"] # the town's cast are all grown-ups
	var ok := []
	var src: Variant = _cfg("want_lines", {})
	for l in ((src as Dictionary).get(key, []) if src is Dictionary else []):
		var who: Array = l.get("who", [])
		if who.all(func(t): return t in tags):
			ok.append(str(l["text"]).format(fill))
	if ok.is_empty():
		return ""
	return ok[(int(roll(v.vid, "want_line") * ok.size()) + Game.day) % ok.size()]


## Whether `p` wants a sweater today (and hasn't bought one or given up haggling).
func wants(p) -> bool:
	if int(Game.flags.get("tf_want_" + p.vid, -1)) == Game.day: # the autotest: wants one today, whatever the roll
		return not SweaterSale.bought_today(p.vid) and _haggling(p.vid)
	return roll(p.vid, "want") < float(_cfg("want_chance", 0.3)) and not SweaterSale.bought_today(p.vid) and _haggling(p.vid)


func _haggling(vid: String) -> bool:
	var a := SweaterSale.asked(vid)
	return a.is_empty() or (bool(a.get("yes", false)) and int(a.get("tries", 0)) < int(SweaterSale.cfg("tries", 3)))


func actions(p) -> Array:
	var acts := [{"id": "talk", "label": "Talk", "enabled": true}]
	if wants(p):
		var n := Game.count("sweater")
		var row := {"id": "sale", "label": "Show them a sweater" if n > 0 else "Wants a sweater  (you have none)", "enabled": n > 0}
		row["group"] = SweaterSale.GROUP
		acts.append(row)
	if main.house_sale != null:
		acts.append_array(main.house_sale.rows_for(p)) # Marcus's task and his house (house_sale.gd)
	return acts


func action(p, id: String) -> void:
	p.face_point(main.player.position, 6.0)
	if main.house_sale != null and main.house_sale.action(p, id):
		return
	match id:
		"talk":
			var want := want_talk(p) # the red pin: what they're after, not the usual line
			main.hud.show_dialogue(p.title, -1, want if want != "" else line_for(p))
		"sale":
			if not SweaterSale.asked(p.vid).is_empty() or Game.count("sweater") == 0:
				if Game.count("sweater") > 0:
					main.sale.open(p)
				return
			SweaterSale._note(p.vid, {"yes": true, "tries": 0}) # they want one: no need to ask
			main.sale.open(p)


# --- the red pin -------------------------------------------------------------------------------

var _pin_t := 0.0
var _pin_want := {} # node -> wants a sweater (checked twice a second)


## Whether named villager `v` wants a sweater: looking for one today and not done with it, or a
## request of theirs waiting for her.
func villager_wants(v) -> bool:
	if main.empire.wants(v.vid):
		return true
	if main.homestead.story_farm() and Game.flag("act1_done") != true:
		return false
	return SweaterSale.looking(v.vid) and not SweaterSale.bought_today(v.vid) and _haggling(v.vid) \
		and (SweaterSale.asked(v.vid).is_empty() or bool(SweaterSale.asked(v.vid).get("yes", false)))


## Every frame: each pin bobs, and twice a second who has one is looked at again.
func update_pins(delta: float) -> void:
	_pin_t -= delta
	var check := _pin_t <= 0.0
	if check:
		_pin_t = 0.5
	var hide_all: bool = main.title_on or main.story.is_playing()
	var t := Time.get_ticks_msec() * 0.001
	for v in main.villagers + people:
		if check:
			var w: bool = not hide_all and v.visible and ((wants(v) or (main.house_sale != null and main.house_sale.wants_sweater(v))) if v in people else villager_wants(v))
			_pin_want[v] = w
		var g: Node = v.get_node_or_null("SweaterPin") as Sprite3D
		var want: bool = _pin_want.get(v, false) and v.visible and not hide_all
		if want and g == null:
			g = _make_pin(v)
		if g == null:
			continue
		g.visible = want
		if want:
			var y: float = float(g.get_meta("y"))
			if v.tag and v.tag.visible:
				y += 0.38 * v.tag.modulate.a # up clear of the name tag while it shows, like the star
			var star := v.get_node_or_null("NewTalk") as Node3D
			if star and star.visible:
				y += 0.42 # above the gold star when both show
			g.position.y = y + 0.07 * absf(sin(t * 3.2 + v.position.x)) # a gentle bounce


func _make_pin(v) -> Sprite3D:
	if _pin_tex == null:
		_pin_tex = ImageTexture.create_from_image(pin_image())
	var g := Sprite3D.new()
	g.name = "SweaterPin"
	g.texture = _pin_tex
	g.pixel_size = 0.4 / PIN_PX # 40 cm tall with its rim
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false
	g.no_depth_test = true
	g.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	g.transparent = true
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base: float = v.tag.position.y if v.tag else 2.0
	g.set_meta("y", base + 0.18)
	g.position.y = base + 0.18
	v.add_child(g)
	return g


## The pin's picture, drawn once: a red map pin (a round head drawn down to a point), lighter at the
## top left, a darker red rim, a white dot in its head, and a soft shadow-free halo.
static func pin_image() -> Image:
	var n := float(PIN_PX)
	var c := Vector2(0.5 * n, 0.36 * n) # the head's centre
	var r := 0.27 * n
	var tip := Vector2(0.5 * n, 0.95 * n)
	var img := Image.create(PIN_PX, PIN_PX, true, Image.FORMAT_RGBA8)
	# the outline: the head's circle and the two tangents down to the tip
	var dt := c.distance_to(tip)
	var ang := asin(r / dt)
	var down := (tip - c).normalized()
	for y in PIN_PX:
		for x in PIN_PX:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c) - r # signed distance to the head
			# the cone: points between the head and the tip inside the two tangent lines
			var along := (p - c).dot(down)
			if along > 0.0:
				var rr := r * (1.0 - along / dt) / cos(ang) # the cone's half-width here
				var off := absf((p - c).cross(down))
				d = minf(d, (off - rr) * cos(ang))
			var body := clampf(0.5 - d, 0.0, 1.0)
			var col := Color(0.96, 0.22, 0.2).lerp(Color(0.7, 0.06, 0.08), clampf((p.y - (c.y - r)) / (0.9 * n), 0.0, 1.0))
			col = col.lerp(Color(1.0, 0.75, 0.72), 0.55 * exp(-p.distance_squared_to(c + Vector2(-0.33, -0.38) * r) / (0.004 * n * n)))
			col = col.lerp(Color(0.45, 0.02, 0.04), clampf(1.0 + (d + 0.5) / (0.03 * n), 0.0, 1.0)) # rim
			var dot := clampf(0.5 - (p.distance_to(c) - 0.36 * r), 0.0, 1.0)
			col = col.lerp(Color(1, 0.97, 0.95), dot)
			var halo := 0.35 * exp(-maxf(d, 0.0) / (0.05 * n))
			var a := body + halo * (1.0 - body)
			if p.x < 1.0 or p.y < 1.0 or p.x > n - 1.0 or p.y > n - 1.0:
				a = 0.0
			if a > 0.001:
				col = (col * body + Color(1.0, 0.45, 0.4) * halo * (1.0 - body)) / a
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.generate_mipmaps()
	return img
