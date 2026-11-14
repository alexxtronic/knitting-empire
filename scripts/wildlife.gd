extends Node3D
## The wild animals and birds round the farm (data/wildlife.json).
##
## Animals come in five tiers, Common to Mythic. The commoner the animal, the more of them there
## are and the nearer the farm they live: wild sheep and rabbits in the fields by the house, foxes
## and raccoons in the woods and at the edge of town, beavers and mink in the swamp, coyotes in the
## low foothills, sables in the far east meadows, lynxes higher in the foothills, and one wild
## chinchilla up by the mountains. Walk up to one quietly and she can comb a little fibre from its
## coat (scripts/wild_animal.gd); run at it, or let the dog charge, and it bolts.
##
## A fibre's tier sets the least a sweater knitted with it can be: the chair's "Knit with ..." rows
## take two wool and one fibre (knit_floor in the data). Fibres ship from the bin.
##
## Birds peck about in small flocks and fly off when she or the dog comes near (scripts/bird.gd).
##
## Everything is placed with a fixed seed, so the world is the same every game. Animals and flocks
## beyond CULL metres of her and of the camera are hidden and stop thinking.

const Data = preload("res://scripts/data.gd")
const WildAnimal = preload("res://scripts/wild_animal.gd")
const Bird = preload("res://scripts/bird.gd")
const Hud = preload("res://scripts/hud.gd")
const KnitGame = preload("res://scripts/knit_game.gd")
const CULL := 60.0
const SEED := 20261114

var main: Node # main.gd
var data: Dictionary = {}
var animals: Array = [] # wild_animal.gd nodes
var flocks: Array = [] # bird.gd nodes
var built := false
var _cull_t := 0.0


func _ready() -> void:
	name = "Wildlife"
	data = Data.load_json("wildlife")
	for id in fibres():
		var f: Dictionary = fibres()[id]
		Hud.Slot.extra[id] = [str(f.get("name", id)), Color.html(str(f.get("color", "#a08060")))]


func fibres() -> Dictionary:
	return data.get("fibres", {})


func fibre_info(id: String) -> Dictionary:
	return fibres().get(id, {})


func is_fibre(id: String) -> bool:
	return fibres().has(id)


func item_name(id: String) -> String:
	return str(fibre_info(id).get("name", Hud.Slot.item_name(id)))


func tier_name(t: String) -> String:
	return str((data.get("tier_names", {}) as Dictionary).get(t, t.capitalize()))


func tier_rank(t: String) -> int:
	return (data.get("tiers", []) as Array).find(t)


func habitat(id: String) -> Rect2:
	var a: Array = (data.get("habitats", {}) as Dictionary).get(id, [0, 0, 1, 1])
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## Places every animal and flock. The same seed puts them in the same places every game.
func build() -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var species: Dictionary = data.get("animals", {})
	for id in species:
		var info: Dictionary = species[id]
		var rects: Array = []
		for h in info.get("habitats", []):
			rects.append(habitat(str(h)))
		var herd := maxi(1, int(info.get("herd", 1)))
		var centre := Vector3.ZERO
		for n in int(info.get("count", 1)):
			var p: Vector3
			if n % herd == 0 or herd == 1: # a new herd (or a loner) somewhere in its habitats
				centre = _open_spot(rng, rects[floori(float(n) / herd) % rects.size()] if not rects.is_empty() else Rect2(0, 0, 10, 10))
				p = centre
			else: # the rest of a herd graze close by
				p = _open_spot(rng, Rect2(centre.x - 3.0, centre.z - 3.0, 6.0, 6.0), centre)
			var a := WildAnimal.new()
			a.setup(main, self, str(id), n, info, rects)
			a.position = p
			add_child(a)
			animals.append(a)
	var birds: Dictionary = data.get("birds", {})
	for id in birds:
		var info: Dictionary = birds[id]
		var i := 0
		for f in info.get("flocks", []):
			var zone := habitat(str(f[0]))
			var b := Bird.new()
			b.setup(main, self, str(id), i, info, zone, int(f[1]), _open_spot(rng, zone))
			add_child(b)
			flocks.append(b)
			i += 1
	built = true
	_cull(true)


func clear() -> void:
	for n in animals + flocks:
		if is_instance_valid(n):
			n.queue_free()
	animals = []
	flocks = []
	built = false


## A walkable spot in the rect (or `fallback` if none turns up).
func _open_spot(rng: RandomNumberGenerator, r: Rect2, fallback := Vector3.INF) -> Vector3:
	for i in 40:
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0.0, rng.randf_range(r.position.y, r.end.y))
		if main._walkable(main._cell(p)):
			return p
	return fallback if fallback != Vector3.INF else Vector3(r.get_center().x, 0.0, r.get_center().y)


func _process(delta: float) -> void:
	if not built:
		return
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.4
		_cull(false)


## Shows and wakes what is within CULL of her or of the camera; hides and stills the rest.
func _cull(force: bool) -> void:
	var eyes: Array = []
	if main.player:
		eyes.append(main.player.global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		eyes.append(cam.global_position)
	for n in animals + flocks:
		var near := false
		for e in eyes:
			var d := Vector2((n as Node3D).global_position.x - e.x, (n as Node3D).global_position.z - e.z).length()
			if d < CULL:
				near = true
				break
		if force or near != (n as Node3D).visible:
			(n as Node3D).visible = near
			n.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


# --- what scares them -------------------------------------------------------------------------

## Where the thing scaring this animal is, or null: Nora running at it inside its shy distance, or
## the dog charging (galloping, or sent by the player) inside it. Walking up, she can come close.
func threat_to(a: Node3D) -> Variant:
	var shy := float(a.info.get("shy", 5.0))
	var p = main.player
	if p and p.running and p.speed > p.walk_speed + 0.3 and _flat(p.global_position, a.global_position) < shy:
		return p.global_position
	var d = main.dog
	if d and d.visible and (d.controlled or d.speed > 2.2) and _flat(d.global_position, a.global_position) < shy:
		return d.global_position
	return null


## Whether something is close enough to put the birds up: Nora at any pace, or the dog.
func flusher(at: Vector3, radius: float) -> Variant:
	var p = main.player
	if p and _flat(p.global_position, at) < radius:
		return p.global_position
	var d = main.dog
	if d and d.visible and _flat(d.global_position, at) < radius * (1.3 if d.speed > 2.2 else 1.0):
		return d.global_position
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- combing, knitting, shipping ----------------------------------------------------------------

## The comb is done: a fibre for her bag, and its coat starts growing back.
func combed(a: Node3D) -> void:
	if not a.has_fur():
		return
	a.comb()
	a.hold(1.5)
	var f: String = a.fibre()
	Game.add_item(f, 1)
	Game.add_need("happiness", 4.0)
	Game.add_need("fitness", 1.0)
	var t := tier_name(a.tier())
	main.hud.show_toast("+1 %s  (%s)" % [item_name(f), t])


func watch_line(a: Node3D) -> String:
	match str(a.species):
		"sheep": return "A wild ewe, shaggy from the hills. She chews and watches you right back."
		"rabbit": return "Its nose never stops twitching."
		"fox": return "It sits with its tail round its feet, watching you sideways."
		"raccoon": return "It turns something over in its little hands, very seriously."
		"beaver": return "It slaps the mud with its tail and goes on chewing."
		"mink": return "Sleek and quick. It's gone the moment you blink, then back again."
		"coyote": return "It tilts its head at you, ears high."
		"sable": return "A rare sable. Its coat shines gold where the light catches it."
		"lynx": return "The lynx looks at you for a long moment, then yawns."
		"chinchilla": return "A wild chinchilla. People say you see one once in a lifetime."
	return "You watch it for a while."


## The chair's extra rows: knit with two wool and one wild fibre, a sweater of at least that fibre's
## floor. Only fibres she has show.
func knit_rows() -> Array:
	var rows: Array = []
	for id in fibres():
		if Game.count(id) <= 0:
			continue
		var fl := knit_floor(id)
		rows.append(main._act("knit_fibre:" + id, "Knit with %s…  (2 wool + 1 · %s or better)" % [item_name(id), KnitGame.rarity_name(fl)], Game.has_item("wool", 2)))
	return rows


func knit_floor(id: String) -> int:
	return clampi(int(fibre_info(id).get("knit_floor", 1)), 1, 5)


func fibre_worth() -> int:
	var total := 0
	for id in fibres():
		total += Game.count(id) * int(fibre_info(id).get("price", 10))
	return total


func fibre_count() -> int:
	var n := 0
	for id in fibres():
		n += Game.count(id)
	return n


## Ships every wild fibre in her bag; returns the coins.
func ship_fibres() -> int:
	var earned := fibre_worth()
	for id in fibres():
		Game.take_item(id, Game.count(id))
	return earned

