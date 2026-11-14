extends Node3D
## A small flock of birds pecking about on the ground (sparrows, robins, gulls on the beach).
##
## When Nora, or the dog, comes within the flock's flush distance, the birds take off one after
## another, climb and fly off together to another spot in their zone, away from her, and settle
## there. On the ground each one pecks (its Idle loop) and hops a few steps now and then.
##
## Made by scripts/wildlife.gd from data/wildlife.json "birds". The models are rigged GLBs with Idle
## and Fly loops (art/world_assets/wildlife/birds.py).

const Catalog = preload("res://scripts/catalog.gd")
const SPREAD := 1.6 # metres round the flock's spot that its birds peck over
const HOP := 0.35
const BLEND := 0.15

var main: Node
var wl: Node
var kind := ""
var info: Dictionary = {}
var zone := Rect2()
var flying := false
var flushes := 0 # times this flock has been put up (for the autotest)
var birds: Array = [] # one Dictionary per bird
var _calm := 0.0 # seconds after landing before they'll go up again


func setup(m: Node, manager: Node, id: String, n: int, data: Dictionary, z: Rect2, count: int, at: Vector3) -> void:
	main = m
	wl = manager
	kind = id
	info = data
	zone = z
	name = "Birds_%s_%d" % [id, n]
	position = at
	for i in count:
		birds.append({"spot": _spot()})


func _ready() -> void:
	for b in birds:
		var node := Node3D.new()
		add_child(node)
		var model := Catalog.model(str(info.get("model", "")), node)
		var anim: AnimationPlayer = null
		if model:
			var aps := model.find_children("*", "AnimationPlayer", true, false)
			anim = aps[0] if not aps.is_empty() else null
		else: # no model yet: a little round bird so the flock still shows
			Catalog.ball(node, 0.06, Vector3(0, 0.07, 0), Color(0.55, 0.42, 0.3), Vector3(1, 0.9, 1.3))
			Catalog.ball(node, 0.04, Vector3(0, 0.13, 0.05), Color(0.6, 0.48, 0.35))
		if anim:
			for n in ["Idle", "Fly"]:
				if anim.has_animation(n):
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			anim.play("Idle")
			anim.seek(randf() * 2.0, true)
			anim.speed_scale = randf_range(0.85, 1.15)
		node.position = b["spot"]
		node.rotation.y = randf() * TAU
		b["node"] = node
		b["anim"] = anim
		b["hop_t"] = randf_range(0.5, 3.0)
		b["air"] = false


func _spot() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * SPREAD
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _process(delta: float) -> void:
	if main == null:
		return
	if flying:
		_fly(delta)
		return
	_calm -= delta
	if _calm <= 0.0:
		var who = wl.flusher(global_position, float(info.get("flush", 4.5)))
		if who != null:
			take_off(who)
			return
	for b in birds:
		_peck(b, delta)


## On the ground: peck, and now and then hop a step or two somewhere else in the spot.
func _peck(b: Dictionary, delta: float) -> void:
	var node: Node3D = b["node"]
	if b.has("hop_to"):
		b["hop_k"] = float(b["hop_k"]) + delta / 0.28
		var k := minf(1.0, float(b["hop_k"]))
		var p: Vector3 = (b["hop_from"] as Vector3).lerp(b["hop_to"], k)
		p.y = sin(k * PI) * 0.08
		node.position = p
		if k >= 1.0:
			b.erase("hop_to")
			b["hop_t"] = randf_range(1.0, 4.0)
		return
	b["hop_t"] = float(b["hop_t"]) - delta
	if float(b["hop_t"]) <= 0.0:
		var to: Vector3 = node.position + Vector3(randf_range(-HOP, HOP), 0.0, randf_range(-HOP, HOP))
		if to.length() > SPREAD:
			to = to.normalized() * SPREAD * 0.8
		b["hop_from"] = node.position
		b["hop_to"] = to
		b["hop_k"] = 0.0
		var d := to - node.position
		if d.length() > 0.01:
			node.rotation.y = atan2(d.x, d.z)


## Up they go: a new spot in their zone, away from whatever came at them, and each bird's path to it.
func take_off(from: Vector3) -> void:
	var best := global_position
	var far := -1.0
	for i in 12:
		var p := Vector3(randf_range(zone.position.x, zone.end.x), 0.0, randf_range(zone.position.y, zone.end.y))
		var d := global_position.distance_to(p)
		if d < 10.0 or d > 40.0 or not main._walkable(main._cell(p)):
			continue
		var score := p.distance_to(from) + randf() * 4.0 # away from her, mostly
		if score > far:
			far = score
			best = p
	if far < 0.0: # nowhere else in the zone: a loop out and back
		best = global_position + (global_position - from).normalized() * 8.0
	var starts: Array = []
	for b in birds:
		starts.append((b["node"] as Node3D).global_position)
	position = best
	var speed := float(info.get("speed", 6.0))
	var up := randf_range(4.0, 8.0)
	for i in birds.size():
		var b: Dictionary = birds[i]
		var a: Vector3 = starts[i]
		var land: Vector3 = best + _spot()
		var away := a - from
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		b["p0"] = a
		b["p1"] = a + Vector3(0, up * 0.6, 0) + away * 2.5
		b["p2"] = land + Vector3(0, up, 0) + (a - land).normalized() * 3.0
		b["p3"] = land
		b["land"] = land - best
		b["t"] = -randf_range(0.0, 0.35) # they don't all go at once
		b["dur"] = maxf(2.0, a.distance_to(land) / speed + 1.0)
		b["air"] = true
		b.erase("hop_to")
		var anim: AnimationPlayer = b["anim"]
		if anim and anim.has_animation("Fly"):
			anim.play("Fly", BLEND)
	flying = true
	flushes += 1
	if main.audio and main.player: # a flutter of wings, quieter the further off she is
		var d: float = (main.player.global_position as Vector3).distance_to(starts[0] if not starts.is_empty() else global_position)
		if d < 25.0:
			main.audio.play("flutter", -4.0 - d * 0.6 - (0.0 if kind == "gull" else 2.0), 0.12)


func _fly(delta: float) -> void:
	var landed := 0
	for b in birds:
		var node: Node3D = b["node"]
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) < 0.0:
			continue
		var k := clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k) # ease out of the take-off and into the landing
		var p := _bez(b["p0"], b["p1"], b["p2"], b["p3"], e)
		var ahead := _bez(b["p0"], b["p1"], b["p2"], b["p3"], minf(1.0, e + 0.02))
		node.global_position = p
		var d := ahead - p
		if Vector2(d.x, d.z).length() > 0.002:
			node.global_rotation = Vector3(-atan2(d.y, Vector2(d.x, d.z).length()) * 0.5, atan2(d.x, d.z), 0.0)
		var anim: AnimationPlayer = b["anim"]
		if k > 0.93 and anim and anim.current_animation == "Fly":
			anim.play("Idle", 0.2)
		if k >= 1.0:
			node.position = b["land"]
			node.rotation = Vector3(0, node.rotation.y, 0)
			b["air"] = false
			landed += 1
	if landed == birds.size():
		flying = false
		_calm = 1.0


static func _bez(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## How many of its birds are in the air right now (for the autotest).
func in_air() -> int:
	var n := 0
	for b in birds:
		if bool(b.get("air", false)) and float(b.get("t", 0.0)) >= 0.0:
			n += 1
	return n
