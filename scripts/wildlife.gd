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
## take two wool and one fibre (knit_floor in the data). Fibres ship from the mailbox.
##
## Birds peck about in small flocks and fly off when she or the dog comes near (scripts/bird.gd).
##
## Catching (Alex, 2026-11-15: the game's core loop): play the dog (Tab) and bark (right click). A bark
## frightens every wild animal within BARK_RANGE: each has a fright meter, and the rarer it is the
## more barks fill it (`barks` in the data); it bolts, so he has to keep after it, and it calms
## down if he lets up. At full fright it gives in and follows the dog, up to `max_herd` (three) at
## a time. He brings them to a pen and they move in for good (Game.flags["penned"]). Only the player
## herds (Alex, 2026-11-16): the dog never rounds anything up by himself.
## A pen holds `pen_size` (four) animals, her sheep included, and she can build as many pens as
## she likes (homestead.gd's fences; every closed patch with a gate is one); Lars's barn adds
## `barn_stalls` while its rent is paid. A caught animal's place in the wild is empty for its
## tier's `respawn_days` (Game.flags["wild_gone"]), then another turns up there.
##
## Everything is placed with a fixed seed, so the world is the same every game. Animals and flocks
## beyond CULL metres of her and of the camera are hidden and stop thinking.

const Data = preload("res://scripts/data.gd")
const WildAnimal = preload("res://scripts/wild_animal.gd")
const Bird = preload("res://scripts/bird.gd")
const Hud = preload("res://scripts/hud.gd")
const KnitGame = preload("res://scripts/knit_game.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")
const CULL := 60.0
const SEED := 20261114
const BARK_RANGE := 8.0 # a bark frightens the wild animals this close
const BARK_NEAR := 3.5 # full effect inside this; it falls to BARK_FAR_GAIN of that at BARK_RANGE
const BARK_FAR_GAIN := 0.45

var main: Node # main.gd
var data: Dictionary = {}
var animals: Array = [] # wild_animal.gd nodes
var flocks: Array = [] # bird.gd nodes
var built := false
var _said_t := 0.0 # seconds before "he can only herd three" may be said again
var _cull_t := 0.0
var _spots := {} # wild animal key -> [species, n, where it was placed], to put another there later


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
			_spots["%s_%d" % [id, n]] = [str(id), n, p]
			if _gone("%s_%d" % [id, n]):
				continue # caught, and nothing has taken its place yet
			_spawn(str(id), n, p)
	for e in penned_list(): # the ones in her pens
		_spawn_penned(e)
	_assign_pens()
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


func _spawn(id: String, n: int, p: Vector3) -> Node3D:
	var info: Dictionary = data.get("animals", {}).get(id, {})
	var rects: Array = []
	for h in info.get("habitats", []):
		rects.append(habitat(str(h)))
	var a := WildAnimal.new()
	a.setup(main, self, id, n, info, rects)
	a.position = p
	add_child(a)
	animals.append(a)
	return a


func clear() -> void:
	for n in animals + flocks:
		if is_instance_valid(n):
			n.queue_free()
	animals = []
	flocks = []
	_spots = {}
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
	_said_t = maxf(0.0, _said_t - delta)
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.4
		_cull(false)
		_update_home()


## Shows and wakes what is within CULL of her or of the camera; hides and stills the rest.
func _cull(force: bool) -> void:
	var eyes: Array = []
	if main.player:
		eyes.append(main.player.global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		eyes.append(cam.global_position)
	for n in animals + flocks:
		if not is_instance_valid(n):
			continue
		var near: bool = n.get("caught") == true or n.get("penned") == true # hers: never asleep
		if near and not force and (n as Node3D).visible:
			continue
		for e in eyes:
			var d := Vector2((n as Node3D).global_position.x - e.x, (n as Node3D).global_position.z - e.z).length()
			if near or d < CULL:
				near = true
				break
		if force or near != (n as Node3D).visible:
			(n as Node3D).visible = near
			n.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


# --- catching them for the pen ---------------------------------------------------------------

func _tier_value(a: Node3D, table: String, fallback: float) -> float:
	return float((data.get(table, {}) as Dictionary).get(a.tier(), fallback))


## Barks at close range that fill its fright meter: the rarer, the more.
func barks_for(a: Node3D) -> float:
	return maxf(1.0, _tier_value(a, "barks", 3.0))


func max_herd() -> int:
	return int(data.get("max_herd", 3))


func penned_list() -> Array:
	var l: Variant = Game.flag("penned", [])
	return l if l is Array else []


func penned() -> Array:
	return animals.filter(func(a): return is_instance_valid(a) and a.penned)


func following() -> Array:
	return animals.filter(func(a): return is_instance_valid(a) and a.caught)


## Who the caught ones follow: the dog, or Nora if he isn't about.
func leader() -> Node3D:
	return main.dog if main.dog and main.dog.visible else main.player


## Her pens, the biggest first: every closed, gated patch of fence on the farm (homestead.gd), or
## the old pen on a farm that never had Act 1. None on the story farm before she builds one.
func pens() -> Array:
	var hs = main.homestead
	if hs and not hs.pens.is_empty():
		return hs.pens
	if hs and hs.story_farm():
		return []
	return [main.pen_rect.grow(-0.6)]


## The first pen: where her sheep live.
func pen() -> Rect2:
	var all := pens()
	return all[0] if not all.is_empty() else Rect2()


func pen_size() -> int:
	return maxi(1, int(data.get("pen_size", 4)))


## How many animals she can keep, her sheep included: `pen_size` in every pen, and `barn_stalls`
## more in Lars's barn while its rent is paid up (homestead.gd).
func pen_capacity() -> int:
	var n := pens().size() * pen_size()
	if n > 0 and stalls_rented():
		n += int(data.get("barn_stalls", 4))
	return n


## True while she rents Lars's barn and owes him nothing.
func stalls_rented() -> bool:
	var hs = main.homestead
	return hs != null and hs.barn_rent_on() and hs.barn_rent_owed() <= 0


## Places left, counting the animals already on their way home.
func pen_room() -> int:
	return pen_capacity() - Game.sheep_count - penned_list().size() - following().size()


## Why this one can't be caught now ("" if it can).
func round_up_problem(a: Node3D) -> String:
	var d = main.dog
	if d == null or not d.visible:
		return "the dog isn't with you"
	if pens().is_empty():
		return "build a pen first"
	if pen_room() <= 0:
		return "the pens are full"
	if following().size() >= max_herd():
		return "he can only herd %d at a time" % max_herd()
	return ""


## The dog barked at `at` (main.dog_bark): every wild animal near enough takes fright and bolts,
## and one whose meter fills gives in and follows him. With three behind him already, or the pens
## full, they only bolt. Returns how many it reached.
func barked(at: Vector3) -> int:
	var reached := 0
	var blocked := ""
	for a in animals:
		if not is_instance_valid(a) or a.caught or a.penned or not a.visible:
			continue
		var d := _flat(at, a.global_position)
		if d > BARK_RANGE:
			continue
		reached += 1
		a.hold(0.0)
		a.scare(at)
		if pens().is_empty():
			blocked = "Build a pen first: there's nowhere to keep it."
		elif pen_room() <= 0:
			blocked = "Your pens are full. Build another pen to keep more animals."
		elif following().size() >= max_herd():
			blocked = "He can only herd %d at a time. Take these home first." % max_herd()
		else:
			var near := lerpf(1.0, BARK_FAR_GAIN, smoothstep(BARK_NEAR, BARK_RANGE, d))
			var power: float = main.dog.bark_power() if main and main.dog else 1.0 # his knitted scarf (scarves.gd)
			if a.frighten(near * power / barks_for(a) + 0.0001):
				frightened(a)
	if blocked != "" and _said_t <= 0.0 and not (main.wolves and main.wolves.active()): # not over the wolves' warning
		_said_t = 6.0
		main.hud.show_toast(blocked)
	return reached


## Its fright meter is full: it gives in and follows the dog home.
func frightened(a: Node3D) -> void:
	a.caught = true
	EmpireGoals.mark(a.species, "caught") # the Field Guide and the goal list
	a.fleeing = 0.0
	a.fright = 0.0
	a._show_meter()
	Game.add_need("happiness", 6.0)
	var n := following().size()
	main.hud.show_toast("The %s gives in and falls in behind the dog. Lead it home to a pen.  (%d of %d)" % [str(a.info.get("name", a.species)).to_lower(), n, max_herd()])


## Twice a second: an animal following the dog moves in once he has brought it to a pen, and the
## penned ones keep to their pens wherever those stand now.
func _update_home() -> void:
	_assign_pens()
	var all := pens()
	if all.is_empty():
		return
	var lead: Vector3 = leader().position
	for a in following():
		var at := Vector2(a.position.x, a.position.z)
		for r in all:
			if (r as Rect2).grow(2.0).has_point(at) or ((r as Rect2).grow(3.5).has_point(Vector2(lead.x, lead.z)) and _flat(a.position, lead) < 7.0):
				pen_it(a)
				break


## Which pen each of her animals lives in: the sheep fill the first pen, then the caught ones take
## the free places pen by pen in the order she caught them; any beyond the pens (Lars's stalls)
## stay in the first. One whose pen changed is put in its new one.
func _assign_pens() -> void:
	var all := pens()
	if all.is_empty():
		return
	var free: Array = []
	for i in all.size():
		free.append(pen_size() - (Game.sheep_count if i == 0 else 0))
	for a in penned():
		var k := 0
		for i in all.size():
			if int(free[i]) > 0:
				k = i
				break
		free[k] = int(free[k]) - 1
		var r: Rect2 = (all[k] as Rect2)
		if a.habitats.is_empty() or (a.habitats[0] as Rect2) != r:
			a.habitats = [r]
			if not r.grow(0.3).has_point(Vector2(a.position.x, a.position.z)):
				a.position = _pen_spot(r)


## It moves into a pen for good.
func pen_it(a: Node3D) -> void:
	var gone: Dictionary = (Game.flag("wild_gone", {}) as Dictionary).duplicate()
	gone[a.key] = Game.day
	Game.set_flag("wild_gone", gone)
	var n := int(Game.flag("pen_n", 0)) + 1
	Game.set_flag("pen_n", n)
	var entry := {"species": a.species, "key": "pen_%s_%d" % [a.species, n]}
	var list := penned_list().duplicate()
	list.append(entry)
	Game.set_flag("penned", list)
	a.make_penned(str(entry["key"]), Rect2())
	a.habitats = []
	_assign_pens() # puts it in the first pen with a free place
	Game.add_need("happiness", 12.0)
	var fname := item_name(a.fibre())
	main.hud.show_toast("%s is in your pen! Comb it for %s whenever its coat has grown back.  (%d of %d places taken)" % [
		str(a.info.get("name", a.species)), fname, pen_capacity() - pen_room(), pen_capacity()])
	main.story.trigger("event", "animal_penned")


func _pen_spot(r: Rect2) -> Vector3:
	for i in 30:
		var p := Vector3(randf_range(r.position.x, r.end.x), 0.0, randf_range(r.position.y, r.end.y))
		if main._walkable(main._cell(p)):
			return p
	return Vector3(r.get_center().x, 0.0, r.get_center().y)


func _spawn_penned(entry: Dictionary) -> Node3D:
	var id := str(entry.get("species", ""))
	if not (data.get("animals", {}) as Dictionary).has(id):
		return null
	var a := _spawn(id, 0, _pen_spot(pen()))
	a.make_penned(str(entry.get("key", "pen_" + id)), Rect2())
	a.habitats = []
	return a


## She opens the gate for it: it leaves the pen list and goes.
func set_free(a: Node3D) -> void:
	var list := penned_list().filter(func(e): return str((e as Dictionary).get("key", "")) != a.key)
	Game.set_flag("penned", list)
	animals.erase(a)
	a.queue_free()
	main.hud.show_toast("You let the %s go. It's off back to the wild." % str(a.info.get("name", a.species)).to_lower())


## True while a caught animal's place in the wild is still empty.
func _gone(key: String) -> bool:
	var gone: Dictionary = Game.flag("wild_gone", {})
	if not gone.has(key):
		return false
	var id: String = str(_spots[key][0]) if _spots.has(key) else key.get_slice("_", 0)
	var tier := str((data.get("animals", {}) as Dictionary).get(id, {}).get("tier", "common"))
	var days := int((data.get("respawn_days", {}) as Dictionary).get(tier, 3))
	return Game.day - int(gone[key]) < days


## Every morning: another animal turns up where one was caught, once its tier's days have passed.
func restock() -> void:
	if not built:
		return
	var here := {}
	for a in animals:
		if is_instance_valid(a) and not a.penned:
			here[a.key] = true
	for key in _spots:
		if here.has(key) or _gone(key):
			continue
		var sp: Array = _spots[key]
		_spawn(str(sp[0]), int(sp[1]), sp[2])
	_cull(true)


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
	EmpireGoals.mark(a.species, "combed") # the Field Guide and the goal list
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


func fibre_count() -> int:
	var n := 0
	for id in fibres():
		n += Game.count(id)
	return n

