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
const BuildingSkin = preload("res://scripts/building_skin.gd")

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
	var casters := [] # [GeometryInstance3D, its own cast_shadow]: the furnishings that cast shadows
	var all_lights := [] # every light in the building: its lamp, the candles, the pendants
	var casting := true
	var lit := true
	## the café's upstairs ("loft" in its data): see _build_loft()
	var loft := {}
	var loft_y := 0.0
	var loft_root: Node3D
	var loft_grid: AStarGrid2D
	var loft_light: OmniLight3D
	var up := false # Nora is upstairs (or on the top half of the stairs)
	var shown := -1 # which floor's hitboxes take clicks: 1 the loft's, 0 the room's (-1 not yet set)
	var down_bodies: Array = [] # [CollisionObject3D, its layer]: the room's furnishings'
	var up_bodies: Array = [] # the loft's

static var shops := {} # building id -> Shop
static var lofts: Array = [] # the shops with an upstairs (the café)
static var editing := false # the world editor is open: every roof is off, so the rooms can be furnished
## Graphics levels below Ultra (main.apply_graphics): while a shop's roof is on its furnishings cast
## no shadows (the sun can't reach them and nobody can see in from above). Low and Medium also turn
## its lights off while she's outside with its door shut. Ultra keeps both, as High always did.
static var no_casters := false
static var lights_off := false


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
	b.set_meta("walk_in", id)
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
	var fl := Planks.lay(b, "floor", Vector3(rm.position.x + T, 0.0315, rm.position.y + T), Vector3(1, 0, 0), Vector3(0, 0, 1), rm.size - Vector2(2 * T, 2 * T), Vector3.UP, [], hash(id), id)
	# "wood": the photo-scanned wood (BuildingSkin's wood_* kinds) on the floor and every wooden piece
	var wood: bool = s.info.get("wood", false) == true
	if wood:
		fl.material_override = BuildingSkin.material("wood_floor", Color(str(s.info.get("floor_colour", "#9a6a44"))))
	var room := Node3D.new()
	room.name = "Furnishings"
	b.add_child(room)
	for f in s.info.get("furniture", []):
		var block: Variant = _piece(s, room, f, wood)
		if block != null:
			rects.append(block)
	var lp: Vector3 = Data.vec3(s.info.get("light", [0.0, 2.5, 0.0]))
	s.light = Catalog.omni(b, lp, Color(1.0, 0.78, 0.5), 4.2, 0.0, 1.2)
	s.light.shadow_enabled = false
	s.light.set_meta("no_shadow", true)
	Catalog.soft_glint(s.light) # no glare off the panes and counters
	for g in room.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			s.casters.append([gi, gi.cast_shadow])
	if s.info.has("loft"):
		rects.append_array(_build_loft(s, wood))
	s.all_lights = b.find_children("*", "Light3D", true, false)
	return rects


## Makes one furnishing of `f` (an entry of the shop's "furniture") under `parent`, `y0` above the
## building's floor. Returns the Rect2 it blocks on its floor (building x / z), or null.
static func _piece(s: Shop, parent: Node3D, f: Dictionary, wood: bool, y0 := 0.0) -> Variant:
	var fid := str(f["id"])
	var at: Vector2 = Data.vec2(f["at"])
	var turn := float(f.get("turn", 0.0))
	var n := Node3D.new()
	n.name = fid
	n.set_meta("item_id", fid)
	n.set_meta("furnishing", true) # the world editor moves each piece on its own (god_mode.gd)
	n.position = Vector3(at.x, y0 + float(f.get("y", 0.0)), at.y)
	n.rotation.y = deg_to_rad(turn)
	parent.add_child(n)
	Catalog.build(fid, n)
	if wood:
		BuildingSkin.dress_wood(n)
	for c in n.get_children():
		if c is OmniLight3D and c.has_meta("night_energy"):
			s.lights.append(c)
		elif c is MeshInstance3D and c.has_meta("flame"):
			s.flames.append(c)
	var item: Dictionary = Catalog.ITEMS.get(fid, {})
	var spots: Array = []
	if f.has("seats"): # a table with a chair each side: a reading seat per chair
		for sd in f["seats"]:
			spots.append(ReadSpot.make(n, f, item, sd))
	elif f.has("read"):
		spots.append(ReadSpot.make(n, f, item))
	for r in spots:
		(r as ReadSpot).upstairs = y0 > 0.0
	if f.has("work"):
		WorkSpot.make(n, f, item)
	if bool(item.get("flat", false)) or float(f.get("y", 0.0)) > 0.3:
		return null
	var fs: Vector2 = Data.vec2(item.get("size", [1.0, 1.0]))
	if absi(int(roundf(turn / 90.0))) % 2 == 1:
		fs = Vector2(fs.y, fs.x)
	n.set_meta("block", Rect2(at - fs * 0.5, fs))
	return Rect2(at - fs * 0.5, fs)


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
static func update(who: Vector3, cam_yaw: float, walls_up: bool, delta: float, movers: Array = [], roof_on := false) -> void:
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
		(s.parts["roof"] as Node3D).visible = (not s.inside or roof_on) and not editing # first person keeps it on
		if s.parts.has("loft"): # the café's upstairs goes with the roof while she's downstairs
			s.up = s.inside and who.y - s.node.global_position.y > s.loft_y * 0.5
			# in the world editor, the floor she's on: its pieces are edited from up there
			var show: bool = (s.up or not s.inside or roof_on) and (not editing or s.up)
			(s.parts["loft"] as Node3D).visible = show
			if s.loft_root != null:
				s.loft_root.visible = show
			# only the floor she's on takes clicks: no seat through the floor, none hidden overhead
			var want := 1 if s.up else 0
			if want != s.shown:
				s.shown = want
				for e in s.down_bodies:
					if is_instance_valid(e[0]):
						(e[0] as CollisionObject3D).collision_layer = 0 if s.up else int(e[1])
				for e in s.up_bodies:
					if is_instance_valid(e[0]):
						(e[0] as CollisionObject3D).collision_layer = int(e[1]) if s.up else 0
			if s.loft_light != null:
				s.loft_light.light_energy = (0.3 + 0.8 * night) if s.up or roof_on else 0.0
		_economise(s)
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


## `no_casters`: no furnishing shadows under a roof; `lights_off`: no lights in a shut shop she isn't
## in. Only touches the nodes when the state changes.
static func _economise(s: Shop) -> void:
	var cast := not (no_casters and (s.parts["roof"] as Node3D).visible)
	if cast != s.casting:
		s.casting = cast
		for e in s.casters:
			if is_instance_valid(e[0]):
				(e[0] as GeometryInstance3D).cast_shadow = e[1] if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var on := not (lights_off and not s.inside and s.open <= 0.0)
	if on != s.lit:
		s.lit = on
		for l in s.all_lights:
			if is_instance_valid(l):
				(l as Light3D).visible = on


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


## A counter she can work behind ("work": "barista" on the Coffee Shop's front counter): its hitbox
## has "Work behind the counter" at any hour, and main.barista takes it from there.
class WorkSpot extends Node3D:
	static var main: Node
	var job := "barista"
	var stand := Vector3(-0.45, 0, 0.85)

	static func make(piece: Node3D, f: Dictionary, item: Dictionary) -> WorkSpot:
		var w := WorkSpot.new()
		w.name = "WorkSpot"
		w.job = str(f["work"])
		piece.add_child(w)
		var sz: Vector2 = Data.vec2(item.get("size", [1.9, 0.7]))
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sz.x, 1.0, sz.y)
		cs.shape = bs
		cs.position.y = 0.5
		body.add_child(cs)
		body.set_meta("target", w)
		w.add_child(body)
		return w

	func display_name() -> String:
		return "Coffee counter"

	func ke_actions() -> Array:
		return [{"id": "work_counter", "label": "Work behind the counter", "enabled": true}]

	func ke_action(_id: String) -> void:
		if main != null:
			main.barista.open(self)

	func stand_point() -> Vector3:
		var p := to_global(stand)
		return Vector3(p.x, 0, p.z)


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
	var upstairs := false # in the café's loft: only Nora goes up there (cafe_visits.gd skips it)

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

	## Where she stands to use it, in the world (on the café's upstairs floor for a piece up there).
	func stand_point() -> Vector3:
		var p := to_global(stand)
		return Vector3(p.x, p.y if upstairs else 0.0, p.z)

	## Where she sits (her origin), in the world, and the way she faces.
	func seat_point() -> Vector3:
		return to_global(seat)

	func seat_yaw() -> float:
		return global_rotation.y + deg_to_rad(seat_turn)


# --- the café's upstairs ----------------------------------------------------------------------
# Alex, 2026-11-17: "add an upstairs to the cafe with cozy circle windows looking out to the main
# square and more couches with books"; the stairs climb the right wall toward the back. The model's
# "loft" part is its floor (with the stairwell), and "base" carries the flight. Upstairs has its
# own walking grid (loft_grid, LOFT_CELL cells in the building's own x / z) under the roof's
# headroom; the flight joins it to main.gd's grid. Only Nora (and the dog with her) goes up: the
# regulars' seats are all downstairs (ReadSpot.upstairs, cafe_visits.gd).
# Data, all in the building's space ("loft" in data/interiors.json "cafe"):
#   y          the loft's floor
#   walk       [x, z, w, d] rects she can stand in (where the roof leaves her headroom, the bays of
#              the dormers and the gable)
#   blocks     [x, z, w, d] rects that are solid up there (the stairwell and its railing, the chimney)
#   stairs     {"x", "low_z", "high_z", "lane" [x, z, w, d], "foot" [x, z] (where she starts up, on
#              the floor below), "top" [x, z] (where she steps off, upstairs)}
#   under      [x, z, w, d]: the room under the flight, solid on the floor below
#   light      [x, y, z] its lamp; furniture: as the room's, stood on the loft's floor

const LOFT_CELL := 0.25
const LOFT_GROW := 0.22 # how far a piece upstairs keeps her off it


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


## Builds the loft's furniture, floor, lamp and walking grid. Returns what blocks the floor below.
static func _build_loft(s: Shop, wood: bool) -> Array:
	s.loft = s.info["loft"]
	s.loft_y = float(s.loft.get("y", 3.57))
	s.loft_root = Node3D.new()
	s.loft_root.name = "LoftFurnishings"
	s.node.add_child(s.loft_root)
	# its floor: the same photo oak as downstairs (or planks), with the stairwell left open
	var walk: Array = s.loft.get("walk", [])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in walk:
		var r := _rect(w)
		lo = lo.min(r.position)
		hi = hi.max(r.end)
	var room := s.room.grow(-T)
	var holes: Array = []
	if s.loft.has("stairwell"):
		var h := _rect(s.loft["stairwell"])
		holes.append(Rect2(h.position - room.position, h.size))
	var fl := Planks.lay(s.loft_root, "floor", Vector3(room.position.x, s.loft_y + 0.012, room.position.y), Vector3(1, 0, 0), Vector3(0, 0, 1), room.size, Vector3.UP, holes, hash(s.id) + 7, s.id)
	fl.remove_from_group("planks_floor") # the café's own second storey, not another building's floor
	if wood:
		fl.material_override = BuildingSkin.material("wood_floor", Color(str(s.info.get("floor_colour", "#9a6a44"))))
	var blocks: Array = []
	for b in s.loft.get("blocks", []):
		blocks.append(_rect(b))
	for f in s.loft.get("furniture", []):
		var block: Variant = _piece(s, s.loft_root, f, wood, s.loft_y)
		if block != null:
			blocks.append(block)
	for n in s.loft_root.get_children():
		n.remove_meta("block") # not the floor below's: the world editor mustn't hand it to main's grid
	var lp: Vector3 = Data.vec3(s.loft.get("light", [0.0, s.loft_y + 1.9, -2.0]))
	s.loft_light = Catalog.omni(s.loft_root, lp, Color(1.0, 0.78, 0.5), 3.2, 0.0, 1.0)
	s.loft_light.shadow_enabled = false
	s.loft_light.set_meta("no_shadow", true)
	# the grid
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, int(ceil(s.room.size.x / LOFT_CELL)), int(ceil(s.room.size.y / LOFT_CELL)))
	g.cell_size = Vector2.ONE
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	g.fill_solid_region(g.region, true)
	for x in g.region.size.x:
		for z in g.region.size.y:
			var c := _loft_center(s, Vector2i(x, z))
			var ok := false
			for w in walk:
				if _rect(w).has_point(c):
					ok = true
					break
			if ok:
				for b in blocks:
					if (b as Rect2).grow(LOFT_GROW).has_point(c):
						ok = false
						break
			g.set_point_solid(Vector2i(x, z), not ok)
	s.loft_grid = g
	var furn: Node = s.node.find_child("Furnishings", false, false)
	for pair in [[furn, s.down_bodies], [s.loft_root, s.up_bodies]]:
		if pair[0] == null:
			continue
		for c in (pair[0] as Node).find_children("*", "CollisionObject3D", true, false):
			(pair[1] as Array).append([c, (c as CollisionObject3D).collision_layer])
	StairSpot.make(s)
	lofts = lofts.filter(func(o: Shop) -> bool: return o.id != s.id and is_instance_valid(o.node))
	lofts.append(s)
	var under: Array = []
	if s.loft.has("under"):
		under.append(_rect(s.loft["under"]))
	return under


static func _loft_center(s: Shop, c: Vector2i) -> Vector2:
	return s.room.position + (Vector2(c) + Vector2(0.5, 0.5)) * LOFT_CELL


static func _loft_cell(s: Shop, q: Vector2) -> Vector2i:
	var c := (q - s.room.position) / LOFT_CELL
	return Vector2i(int(floorf(c.x)), int(floorf(c.y)))


static func _loft_ok(s: Shop, c: Vector2i) -> bool:
	return s.loft_grid != null and s.loft_grid.is_in_boundsv(c) and not s.loft_grid.is_point_solid(c)


## The shop with a loft whose room `p` (world) is in, or null.
static func loft_shop(p: Vector3) -> Shop:
	for s in lofts:
		if is_instance_valid(s.node) and _is_in(s, p):
			return s
	return null


## Whether `p` (world) stands upstairs in a loft (or high on its stairs).
static func upstairs(p: Vector3) -> bool:
	var s := loft_shop(p)
	return s != null and p.y - s.node.global_position.y > s.loft_y * 0.5


static func _stair_y(s: Shop, z: float) -> float:
	var st: Dictionary = s.loft["stairs"]
	var lz := float(st["low_z"])
	var hz := float(st["high_z"])
	return s.loft_y * clampf((z - lz) / (hz - lz), 0.0, 1.0)


## The floor under `p` (world) for whoever stands there, `prev` being the floor they stood on last
## frame: the flight's slope on the stairs, the loft for anyone already up, else the ground floor.
## null outside any loft's room (SplitHouse.follow then leaves them be).
static func floor_for(p: Vector3, prev: float) -> Variant:
	var s := loft_shop(p)
	if s == null:
		return null
	var by := s.node.global_position.y
	var q: Vector3 = s.node.global_transform.affine_inverse() * p
	var st: Dictionary = s.loft["stairs"]
	if _rect(st["lane"]).has_point(Vector2(q.x, q.z)):
		var sy := by + _stair_y(s, q.z)
		if absf(sy - prev) < 0.7:
			return sy
	return by + s.loft_y if prev - by > s.loft_y * 0.5 else by


## Whether `p` (world) is somewhere she can step to by the keys (first person) in a loft's room:
## null if `p` isn't in one, so main's own grid decides. `from` is where she is now.
static func steer_ok(from: Vector3, p: Vector3) -> Variant:
	var s := loft_shop(from)
	if s == null:
		return null
	var q: Vector3 = s.node.global_transform.affine_inverse() * p
	var q2 := Vector2(q.x, q.z)
	var st: Dictionary = s.loft["stairs"]
	var lane := _rect(st["lane"])
	if lane.grow(-0.08).has_point(q2):
		return true
	var by := s.node.global_position.y
	if from.y - by > s.loft_y * 0.5:
		return _loft_ok(s, _loft_cell(s, q2)) or (q.z < float(st["high_z"]) and lane.grow(0.4).has_point(q2))
	if q.z > float(st["low_z"]) - 0.1 and lane.grow(0.35).has_point(q2):
		return true # stepping on at the foot
	return null


## A path (world points) for a walk that starts or ends upstairs in a loft, joining main's grid
## (`ground`: main._find_path_ground) to the loft's by the flight; null when neither end is upstairs.
static func loft_route(from: Vector3, to: Vector3, ground: Callable) -> Variant:
	var s := loft_shop(from)
	if s == null or not upstairs(from):
		var s2 := loft_shop(to)
		if s2 == null or not upstairs(to):
			if s == null or not _on_stairs(s, from):
				return null
			s2 = s
		s = s2
	var xf := s.node.global_transform
	var inv := xf.affine_inverse()
	var st: Dictionary = s.loft["stairs"]
	var sx := float(st["x"])
	var foot: Vector2 = Data.vec2(st["foot"])
	var top: Vector2 = Data.vec2(st["top"])
	var up_from := upstairs(from) and _is_in(s, from)
	var up_to := upstairs(to) and _is_in(s, to)
	var qf: Vector3 = inv * from
	var qt: Vector3 = inv * to
	var w := func(v: Vector2) -> Vector3:
		var g: Vector3 = xf * Vector3(v.x, 0, v.y)
		return Vector3(g.x, 0, g.z)
	var climb := [Vector2(sx, float(st["low_z"]) + 0.25), Vector2(sx, float(st["high_z"])), top]
	var out: Array = []
	var on_stairs := _on_stairs(s, from)
	if up_from and up_to and not on_stairs:
		for v in _loft_path(s, Vector2(qf.x, qf.z), Vector2(qt.x, qt.z)):
			out.append(w.call(v))
		return out
	if up_to: # going up: to the foot, up the flight (from where she is on it), on upstairs
		if on_stairs:
			climb = climb.slice(1)
		else:
			out.append_array(ground.call(from, w.call(foot)))
		for v in climb:
			out.append(w.call(v))
		for v in _loft_path(s, top, Vector2(qt.x, qt.z)):
			out.append(w.call(v))
		return out
	# going down: to the top, down the flight, on from its foot
	var down := [Vector2(sx, float(st["high_z"])), Vector2(sx, float(st["low_z"]) + 0.25), foot]
	if on_stairs:
		down = down.slice(1)
	else:
		for v in _loft_path(s, Vector2(qf.x, qf.z), top):
			out.append(w.call(v))
		out.append(w.call(top))
	for v in down:
		out.append(w.call(v))
	out.append_array(ground.call(w.call(foot), Vector3(to.x, 0, to.z)))
	return out


static func _on_stairs(s: Shop, p: Vector3) -> bool:
	var q: Vector3 = s.node.global_transform.affine_inverse() * p
	return _rect(s.loft["stairs"]["lane"]).has_point(Vector2(q.x, q.z)) and p.y - s.node.global_position.y > 0.12


## A path on the loft's grid, in the building's x / z, smoothed; [] if there's none.
static func _loft_path(s: Shop, a: Vector2, b: Vector2) -> Array:
	var ca: Variant = _loft_near(s, _loft_cell(s, a))
	var cb: Variant = _loft_near(s, _loft_cell(s, b))
	if ca == null or cb == null:
		return []
	var ids := s.loft_grid.get_id_path(ca, cb, true)
	var pts: Array = []
	for i in range(1, ids.size()):
		pts.append(_loft_center(s, ids[i]))
	var reached: bool = not ids.is_empty() and ids[ids.size() - 1] == cb
	if reached and _loft_ok(s, _loft_cell(s, b)):
		if pts.is_empty():
			pts.append(b)
		else:
			pts[pts.size() - 1] = b
	# smoothed: straight on to the furthest point in clear sight
	var out: Array = []
	var cur := a
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not _loft_clear(s, cur, pts[j]):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out


static func _loft_clear(s: Shop, a: Vector2, b: Vector2) -> bool:
	var steps := int(ceilf(a.distance_to(b) / 0.1))
	for k in range(1, steps + 1):
		if not _loft_ok(s, _loft_cell(s, a.lerp(b, float(k) / steps))):
			return false
	return true


static func _loft_near(s: Shop, c: Vector2i) -> Variant:
	if _loft_ok(s, c):
		return c
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) == radius and _loft_ok(s, c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return null


## Where a click lands while she's upstairs in a loft: on its floor. null when she isn't up there.
static func loft_pick(who: Vector3, from: Vector3, dir: Vector3) -> Variant:
	if not upstairs(who):
		return null
	var s := loft_shop(who)
	var hit: Variant = Plane(Vector3.UP, s.node.global_position.y + s.loft_y).intersects_ray(from, dir)
	if hit == null:
		return null
	var q: Vector3 = s.node.global_transform.affine_inverse() * (hit as Vector3)
	if not s.room.has_point(Vector2(q.x, q.z)) or (s.loft.has("stairwell") and _rect(s.loft["stairwell"]).has_point(Vector2(q.x, q.z))):
		return null # off the loft's floor: the ground beyond (or the stairs' own hitbox)
	return hit


## The flight up to the loft, as something to click: "Go upstairs" from below, "Go downstairs" from
## above (it walks her to the top or the foot; main._find_path does the rest).
class StairSpot extends Node3D:
	static var main: Node
	var shop: Shop

	static func make(s: Shop) -> StairSpot:
		var st: Dictionary = s.loft["stairs"]
		var la: Array = st["lane"]
		var lane := Rect2(float(la[0]), float(la[1]), float(la[2]), float(la[3]))
		var sp := StairSpot.new()
		sp.name = "StairSpot"
		sp.shop = s
		s.node.add_child(sp)
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(lane.size.x, s.loft_y + 1.0, lane.size.y)
		cs.shape = bs
		cs.position = Vector3(lane.get_center().x, (s.loft_y + 1.0) * 0.5, lane.get_center().y)
		body.add_child(cs)
		body.set_meta("target", sp)
		sp.add_child(body)
		return sp

	func display_name() -> String:
		return "Stairs"

	func ke_actions() -> Array:
		if main == null:
			return []
		if _up():
			return [{"id": "stairs_down", "label": "Go downstairs", "enabled": true}]
		return [{"id": "stairs_up", "label": "Go upstairs", "enabled": true}]

	func _up() -> bool:
		return main != null and main.player.position.y - shop.node.global_position.y > shop.loft_y * 0.5

	func ke_action(_id: String) -> void:
		pass # main walked her there already (stand_point)

	## Where "Go upstairs" (or down) takes her, in the world: a step off the top, or the foot.
	func target(going_up: bool) -> Vector3:
		var st: Dictionary = shop.loft["stairs"]
		var v: Vector2 = Data.vec2(st["top"] if going_up else st["foot"])
		var p := shop.node.global_transform * Vector3(v.x, shop.loft_y if going_up else 0.0, v.y + (-0.35 if going_up else 0.0))
		return p

	## Where she walks to for it (main.gd _stand_point): straight to its target.
	func stand_point() -> Vector3:
		return target(not _up())
