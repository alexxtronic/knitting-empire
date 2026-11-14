extends RefCounted
## The Coffee Shop is the town's hangout (Alex, 2026-11-14: "have npcs randomly come in here for a
## coffee and sit down with a book"). Every so often in the day one of the regulars (data/interiors.json
## "cafe" "visits") leaves their spot, walks in, stops at the counter for a coffee, takes a free
## reading seat (Interiors.ReadSpot) and sits reading a book for a while, then goes back where they
## were. main.gd calls update() with the town's other routines (_update_rounds), so the autotest's
## still town has none; a story scene starting sends everyone back first (end_all), so the scene
## finds them where it expects.

const Interiors = preload("res://scripts/interiors.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")

const BOOKS := ["plum", "forest", "wine", "navy", "mustard"]
const ARRIVED := 0.2 # how close counts as there

var main: Node
var visits := {} # vid -> {"v", "state", "seat", "home", "roam", "rest", "until", "book", "t"}
var next_at := -1.0 # the game hour (counted from day 1) the next regular may come in
var seen := {} # vid -> the day they last came in (once a day each)


func _cfg() -> Dictionary:
	return Interiors.shops["cafe"].info.get("visits", {}) if Interiors.shops.has("cafe") else {}


func _now() -> float:
	return float(Game.day) * 24.0 + Game.hour


## Twice a second (main._update_rounds): moves each visit on, and now and then starts one.
func update() -> void:
	for vid in visits.keys():
		_step(vid)
	var cfg := _cfg()
	if cfg.is_empty():
		return
	var hours: Array = cfg.get("hours", [8, 20])
	if Game.hour < float(hours[0]) or Game.hour >= float(hours[1]) or visits.size() >= int(cfg.get("max", 3)):
		return
	if next_at < 0.0:
		next_at = _now() + randf_range(0.2, 1.0)
	if _now() < next_at:
		return
	var every: Array = cfg.get("every", [0.6, 1.6])
	next_at = _now() + randf_range(float(every[0]), float(every[1]))
	var who: Array = []
	for vid in cfg.get("who", []):
		if can_visit(str(vid)):
			who.append(str(vid))
	if not who.is_empty():
		start(who[randi() % who.size()])


## Whether `vid` is free to drop in now: about, not busy with Nora, a scene, or their own round.
func can_visit(vid: String) -> bool:
	if visits.has(vid) or int(seen.get(vid, 0)) == Game.day or Game.flag("home_" + vid, null) != null:
		return false
	var v = main._villager(vid)
	if v == null or not v.visible or v.listening or v.anim_override != "" or main.story.is_playing():
		return false
	if vid == "barbara" and not main.post_round_done():
		return false
	return free_seats().size() > 0


## The café's reading seats nobody is in, Nora's included.
func free_seats() -> Array:
	return Interiors.read_spots("cafe").filter(func(r): return r.kind == "seat" and (r.occupant == null or not is_instance_valid(r.occupant)))


## Sends `vid` in for a coffee and a book now. Returns false if there's no seat or no such person.
func start(vid: String) -> bool:
	var v = main._villager(vid)
	var seats := free_seats()
	if v == null or seats.is_empty() or not Interiors.shops.has("cafe"):
		return false
	var seat = seats[randi() % seats.size()]
	seat.occupant = v
	var cfg := _cfg()
	var stay: Array = cfg.get("stay", [1.5, 3.0])
	visits[vid] = {"v": v, "state": "counter", "seat": seat, "home": v.home, "roam": v.roam, "rest": v.rest_yaw,
		"until": 0.0, "stay": randf_range(float(stay[0]), float(stay[1])), "book": null, "t": 0.0}
	seen[vid] = Game.day
	v.rest_yaw = null
	var at := counter_spot(visits[vid])
	v.walk_to(at, main._find_path(v.position, at))
	return true


## Where they stand to order: in front of one of the counters ("visits" "counter": [x, z] spots in
## the café's own space), the one nearest their seat.
func counter_spot(vis: Dictionary) -> Vector3:
	var s = Interiors.shops["cafe"]
	var xf: Transform3D = s.node.global_transform
	var best := Vector3.ZERO
	var bd := INF
	for c in _cfg().get("counter", [[2.2, -4.0]]):
		var p: Vector3 = xf * Vector3(float(c[0]), 0, float(c[1]))
		var d: float = p.distance_to((vis["seat"] as Node3D).global_position)
		if d < bd:
			bd = d
			best = Vector3(p.x, 0, p.z)
	return best


func _there(v, p: Vector3) -> bool:
	return Vector2(v.position.x - p.x, v.position.z - p.z).length() < ARRIVED


func _step(vid: String) -> void:
	var vis: Dictionary = visits[vid]
	var v = vis["v"]
	if not is_instance_valid(v):
		_free(vis)
		visits.erase(vid)
		return
	match str(vis["state"]):
		"counter": # walking up to order
			var at := counter_spot(vis)
			if _there(v, at):
				var s = Interiors.shops["cafe"]
				v.face_point(s.node.global_transform * Vector3(float(_cfg().get("counter", [[2.2, -4.0]])[0][0]), 1.0, -6.5), 3.5)
				v.talk(3.0)
				vis["state"] = "ordering"
				vis["t"] = 3.5
		"ordering": # a word with the counter for a coffee
			vis["t"] = float(vis["t"]) - 0.5
			if float(vis["t"]) <= 0.0:
				var at: Vector3 = vis["seat"].stand_point()
				v.walk_to(at, main._find_path(v.position, at))
				vis["state"] = "to_seat"
		"to_seat":
			if _there(v, vis["seat"].stand_point()):
				sit(vis)
		"reading":
			if v.anim_override != "SitIdle": # something else took them (a scene, a chat that sent them off)
				_free(vis)
				visits.erase(vid)
			elif _now() >= float(vis["until"]):
				leave(vid)
		"leaving":
			if _there(v, vis["home"]):
				v.roam = vis["roam"]
				v.rest_yaw = vis["rest"]
				visits.erase(vid)


## Down in the seat with a book on their lap.
func sit(vis: Dictionary) -> void:
	var v = vis["v"]
	var seat = vis["seat"]
	v.settle_at(seat.seat_point())
	v.rotation.y = seat.seat_yaw()
	v.anim_override = "SitIdle"
	var book := Node3D.new()
	book.name = "CafeBook"
	v.add_child(book)
	Catalog.model("res://assets/props/book_%s.glb" % BOOKS[randi() % BOOKS.size()], book)
	book.position = Vector3(0.0, 0.2, 0.3)
	book.rotation = Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	vis["book"] = book
	vis["state"] = "reading"
	vis["until"] = _now() + float(vis["stay"])


## Up, the book left behind, and back to where they were.
func leave(vid: String) -> void:
	var vis: Dictionary = visits[vid]
	var v = vis["v"]
	_free(vis)
	v.anim_override = ""
	v.position.y = 0.0
	v.walk_to(vis["home"], main._find_path(v.position, vis["home"]))
	vis["state"] = "leaving"


func _free(vis: Dictionary) -> void:
	if vis["seat"] != null and is_instance_valid(vis["seat"]) and vis["seat"].occupant == vis["v"]:
		vis["seat"].occupant = null
	if vis["book"] != null and is_instance_valid(vis["book"]):
		(vis["book"] as Node).queue_free()
	vis["book"] = null


## A story scene is starting (or the game is loading): everyone in for a coffee is back at their
## own spot at once, standing, before the scene places anyone.
func end_all() -> void:
	for vid in visits:
		var vis: Dictionary = visits[vid]
		var v = vis["v"]
		_free(vis)
		if not is_instance_valid(v):
			continue
		if v.anim_override == "SitIdle":
			v.anim_override = ""
		v.settle_at(vis["home"])
		v.roam = vis["roam"]
		v.rest_yaw = vis["rest"]
	visits.clear()


## Who's in the café reading right now (for the autotest and the HUD).
func reading() -> Array:
	return visits.keys().filter(func(vid): return str(visits[vid]["state"]) == "reading")
