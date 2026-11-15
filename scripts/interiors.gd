extends RefCounted
## Walk-in shops: the Yarn Barn, Heart Bakery, Willow Homes, Builder's Delight and the Coffee Shop. Their models
## (art/world_assets/town_buildings) come in parts, like the barn: `base` (the plank floor and the
## things standing outside), each wall at full height (`wall_front`...) and cut down to a stub
## (`wall_front_low`...), a `door` hinged on its left jamb, and the `roof`. While she is inside one
## its roof is hidden and the walls facing the camera drop to stubs (unless Walls Up is on); the
## door swings in as anyone comes up to it; a lamp inside comes up as the daylight goes.
## Each is furnished from data/interiors.json, and its shopkeeper (villagers.json "works_in")
## stands behind the counter. Everything is a child of the building's node, so the world editor
## moves it all together. A shop whose room doesn't fill its lot (the Coffee Shop has its terrace in
## front) gives its "room" rect; candles and lamps on its furnishings flicker and come up at dusk, and
## pieces marked "read" are reading seats and bookshelves (ReadSpot; main.gd begin_read()).

const Catalog = preload("res://scripts/catalog.gd")
const FurnitureScript = preload("res://scripts/furniture.gd")
const Data = preload("res://scripts/data.gd")
const Planks = preload("res://scripts/planks.gd")

const WALLS := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}
const T := 0.2 # wall thickness
const DOOR_HALF := 0.62 # half the gap the front wall's obstacles leave at the door

## One building you can walk into.
class Shop:
	var id := ""
	var node: Node3D
	var size := Vector2.ZERO # its lot (x, z)
	var room := Rect2() # the room inside the walls' outer faces, in the building's own x / z
	var parts := {} # MeshInstance3D by part name
	var inside := false
	var open := 0.0 # the door: 0 shut .. 1 swung in
	var light: OmniLight3D
	var info := {} # its entry in data/interiors.json
	var lights := [] # the furnishings' candles and lamps (Furniture.animate)
	var flames := []
	var t := 0.0

static var shops := {} # building id -> Shop


## Sets up building `b` (its model already loaded under it) as a walk-in shop, if its model has
## the parts: finds them, furnishes the room and hangs the lamp. Returns what blocks the way, as
## Rect2s in the building's own space (x, z) round its origin, or [] if it isn't a walk-in model.
static func furnish(b: Node3D, id: String, size: Vector2) -> Array:
	var parts := {}
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		parts[str(mi.name)] = mi
	for need in ["base", "roof", "door", "wall_front", "wall_front_low"]:
		if not parts.has(need):
			return []
	var s := Shop.new()
	s.id = id
	s.node = b
	s.size = size
	s.parts = parts
	s.info = Data.load_json("interiors").get(id, {})
	s.room = Rect2(-size * 0.5, size)
	if s.info.has("room"): # [centre x, centre z, width, depth]
		var rr: Array = s.info["room"]
		s.room = Rect2(float(rr[0]) - float(rr[2]) * 0.5, float(rr[1]) - float(rr[3]) * 0.5, float(rr[2]), float(rr[3]))
	s.t = randf() * 10.0
	shops[id] = s
	for side in WALLS:
		if parts.has("wall_%s_low" % side):
			(parts["wall_%s_low" % side] as Node3D).visible = false
	var rm := s.room
	var door_x := float(s.info.get("door_x", rm.get_center().x))
	# "wall_block": how deep the walls block the walking grid from their outer faces. A 0.2 m wall can
	# fall between the grid's 0.5 m cell centres (main.gd CELL), so a room can ask for a full cell.
	var wb := float(s.info.get("wall_block", T))
	var rects := [
		Rect2(rm.position.x, rm.position.y, rm.size.x, wb), Rect2(rm.position.x, rm.position.y, wb, rm.size.y), Rect2(rm.end.x - wb, rm.position.y, wb, rm.size.y), # back, left, right
		Rect2(rm.position.x, rm.end.y - wb, door_x - DOOR_HALF - rm.position.x, wb), Rect2(door_x + DOOR_HALF, rm.end.y - wb, rm.end.x - door_x - DOOR_HALF, wb), # the front, either side of the door
	]
	for o in s.info.get("outside", []):
		rects.append(Rect2(float(o[0]), float(o[1]), float(o[2]), float(o[3])))
	# the same plank floor as the houses, in this shop's own shade, over the model's boards
	Planks.lay(b, "floor", Vector3(rm.position.x + T, 0.0315, rm.position.y + T), Vector3(1, 0, 0), Vector3(0, 0, 1), rm.size - Vector2(2 * T, 2 * T), Vector3.UP, [], hash(id), id)
	var room := Node3D.new()
	room.name = "Furnishings"
	b.add_child(room)
	for f in s.info.get("furniture", []):
		var fid := str(f["id"])
		var at: Vector2 = Data.vec2(f["at"])
		var turn := float(f.get("turn", 0.0))
		var n := Node3D.new()
		n.name = fid
		n.position = Vector3(at.x, float(f.get("y", 0.0)), at.y)
		n.rotation.y = deg_to_rad(turn)
		room.add_child(n)
		Catalog.build(fid, n)
		for c in n.get_children():
			if c is OmniLight3D and c.has_meta("night_energy"):
				s.lights.append(c)
			elif c is MeshInstance3D and c.has_meta("flame"):
				s.flames.append(c)
		var item: Dictionary = Catalog.ITEMS.get(fid, {})
		if f.has("seats"): # a table with a chair each side: a reading seat per chair
			for sd in f["seats"]:
				ReadSpot.make(n, f, item, sd)
		elif f.has("read"):
			ReadSpot.make(n, f, item)
		if bool(item.get("flat", false)) or float(f.get("y", 0.0)) > 0.3:
			continue
		var fs: Vector2 = Data.vec2(item.get("size", [1.0, 1.0]))
		if absi(int(roundf(turn / 90.0))) % 2 == 1:
			fs = Vector2(fs.y, fs.x)
		rects.append(Rect2(at - fs * 0.5, fs))
	var lp: Vector3 = Data.vec3(s.info.get("light", [0.0, 2.5, 0.0]))
	s.light = Catalog.omni(b, lp, Color(1.0, 0.78, 0.5), 4.2, 0.0, 1.2)
	s.light.shadow_enabled = false
	return rects


## The shopkeeper's place in building `id`, wherever it stands now: {"pos", "talk" (world
## Vector3s), "yaw" (the way they face), "roam" (Vector2, in world x / z)}; {} if there is none.
static func keeper(id: String) -> Dictionary:
	var s: Shop = shops.get(id)
	if s == null or not is_instance_valid(s.node) or not s.node.visible or not s.info.has("keeper"):
		return {}
	var k: Dictionary = s.info["keeper"]
	var xf := s.node.global_transform
	var spot: Vector2 = Data.vec2(k["spot"])
	var talk: Vector2 = Data.vec2(k["talk"])
	var roam: Vector2 = Data.vec2(k.get("roam", [0.0, 0.0]))
	var face: Vector3 = xf.basis * Vector3(sin(deg_to_rad(float(k.get("face", 0.0)))), 0, cos(deg_to_rad(float(k.get("face", 0.0)))))
	if absf(face.x) > absf(face.z): # the building stands turned: so does the way they potter
		roam = Vector2(roam.y, roam.x)
	var pos: Vector3 = xf * Vector3(spot.x, 0, spot.y)
	var at: Vector3 = xf * Vector3(talk.x, 0, talk.y)
	return {"pos": Vector3(pos.x, 0, pos.z), "talk": Vector3(at.x, 0, at.z), "yaw": atan2(face.x, face.z), "roam": roam}


## The shop she is standing in ("" if none).
static func inside_of(who: Vector3) -> String:
	for s in shops.values():
		if _is_in(s, who):
			return s.id
	return ""


static func _is_in(s: Shop, who: Vector3) -> bool:
	if not is_instance_valid(s.node) or not s.node.visible:
		return false
	var p: Vector3 = s.node.global_transform.affine_inverse() * who
	return s.room.has_point(Vector2(p.x, p.z))


## The ground under each shop's floor, wherever it stands now, so no grass grows through it.
static func floors() -> Array:
	var out := []
	for s in shops.values():
		if not is_instance_valid(s.node) or not s.node.visible:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for sx in [s.room.position.x, s.room.end.x]:
			for sz in [s.room.position.y, s.room.end.y]:
				var p: Vector3 = s.node.global_transform * Vector3(sx, 0, sz)
				lo = lo.min(Vector2(p.x, p.z))
				hi = hi.max(Vector2(p.x, p.z))
		out.append(Rect2(lo, hi - lo))
	return out


## Every frame: each door swings in for her or a villager coming up to it (`movers`: positions),
## and shuts behind them; the shop she is in loses its roof and the walls toward the camera
## (unless Walls Up is on); the lamps come up as the daylight goes.
static func update(who: Vector3, cam_yaw: float, walls_up: bool, delta: float, movers: Array = []) -> void:
	var cdir := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var night := clampf(1.0 - Game.daylight(), 0.0, 1.0)
	for s in shops.values():
		if not is_instance_valid(s.node):
			continue
		var inv: Transform3D = s.node.global_transform.affine_inverse()
		s.inside = _is_in(s, who)
		var at_door := false
		var dx := float(s.info.get("door_x", s.room.get_center().x))
		for m in [who] + movers:
			var q: Vector3 = inv * (m as Vector3)
			if absf(q.x - dx) < 1.0 and q.z > s.room.end.y - 1.4 and q.z < s.room.end.y + 1.5:
				at_door = true
		s.open = move_toward(s.open, 1.0 if (s.inside or at_door) and s.node.visible else 0.0, delta * 2.5)
		(s.parts["door"] as Node3D).rotation.y = deg_to_rad(100.0) * smoothstep(0.0, 1.0, s.open)
		(s.parts["roof"] as Node3D).visible = not s.inside
		for side in WALLS:
			if not s.parts.has("wall_" + side) or not s.parts.has("wall_%s_low" % side):
				continue
			var n: Vector3 = (s.node.global_transform.basis * (WALLS[side] as Vector3)).normalized()
			var cut: bool = s.inside and not walls_up and n.dot(cdir) > 0.25
			(s.parts["wall_" + side] as Node3D).visible = not cut
			(s.parts["wall_%s_low" % side] as Node3D).visible = cut
		if s.light != null and is_instance_valid(s.light):
			s.light.light_energy = 0.35 + 1.0 * night
		if not s.lights.is_empty() or not s.flames.is_empty():
			s.t += delta
			FurnitureScript.animate(s.lights, s.flames, s.t, night)


## The reading seats and bookshelves in shop `id`, wherever it stands now ([] if none).
static func read_spots(id: String) -> Array:
	var s: Shop = shops.get(id)
	if s == null or not is_instance_valid(s.node):
		return []
	var out := []
	for n in s.node.find_children("*", "Node3D", true, false):
		if n is ReadSpot:
			out.append(n)
	return out


## A piece in a shop you can read at: a seat ("read": "seat") she sits in with a book, or a bookshelf
## ("read": "shelf") she picks one from. Its hitbox lists its own actions (main.gd _actions_for);
## main.gd begin_read() does the rest. Its "seat" ([x, y, z, turn] in the piece's own space) and
## "stand" ([x, z], where she walks up to) come from data/interiors.json, or from the piece's size.
## A piece with "seats" (a café table's two chairs) gets one per entry, each with a hitbox round its
## own chair. Whoever sits in one (Nora, or a villager in for a coffee: scripts/cafe_visits.gd) is
## its `occupant` until they get up, so nobody else is sent to it.
class ReadSpot extends Node3D:
	static var main: Node # main.gd sets it: what ke_action() hands over to
	var kind := "seat"
	var label := ""
	var seat := Vector3(0, 0.42, 0.05)
	var seat_turn := 0.0
	var stand := Vector3.ZERO
	var occupant: Node = null # who's sitting here (Nora or a villager); null when it's free

	## `sd`: one of the piece's "seats" ({"seat", "stand"}), or {} for the piece's own "seat".
	static func make(piece: Node3D, f: Dictionary, item: Dictionary, sd: Dictionary = {}) -> ReadSpot:
		var r := ReadSpot.new()
		r.name = "ReadSpot%d" % piece.get_child_count()
		r.kind = str(f.get("read", "seat"))
		r.label = str(item.get("name", f["id"]))
		var sz: Vector2 = Data.vec2(item.get("size", [1.0, 1.0]))
		var src: Dictionary = sd if not sd.is_empty() else f
		if src.has("seat"):
			var a: Array = src["seat"]
			r.seat = Vector3(float(a[0]), float(a[1]), float(a[2]))
			r.seat_turn = float(a[3]) if a.size() > 3 else 0.0
		r.stand = Vector3(r.seat.x, 0, sz.y * 0.5 + 0.45)
		if src.has("stand"):
			var st: Vector2 = Data.vec2(src["stand"])
			r.stand = Vector3(st.x, 0, st.y)
		piece.add_child(r)
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var h := maxf(0.4, float(item.get("height", 1.0)))
		bs.size = Vector3(sz.x, h, sz.y)
		if not sd.is_empty(): # just this chair, so the table's two seats are two clicks
			bs.size = Vector3(0.6, h, sz.y)
			cs.position.x = r.seat.x
		cs.shape = bs
		cs.position.y = h * 0.5
		body.add_child(cs)
		body.set_meta("target", r)
		r.add_child(body)
		return r

	func display_name() -> String:
		return label

	func ke_actions() -> Array:
		if kind == "shelf":
			return [{"id": "read_pick", "label": "Choose a book from the shelf…", "enabled": true}]
		if taken():
			var who := str(occupant.get("title")) if occupant.get("title") != null else "Someone"
			return [{"id": "read_book", "label": "%s is reading here" % who, "enabled": false}]
		return [{"id": "read_book", "label": "Sit and read a book…", "enabled": true}]

	## Someone else is in it (not Nora: she's the one asking).
	func taken() -> bool:
		return occupant != null and is_instance_valid(occupant) and (main == null or occupant != main.get("player"))

	func ke_action(id: String) -> void:
		if main != null:
			main.begin_read(self, id)

	## Where she stands to use it, in the world.
	func stand_point() -> Vector3:
		var p := to_global(stand)
		return Vector3(p.x, 0, p.z)

	## Where she sits (her origin), in the world, and the way she faces.
	func seat_point() -> Vector3:
		return to_global(seat)

	func seat_yaw() -> float:
		return global_rotation.y + deg_to_rad(seat_turn)
