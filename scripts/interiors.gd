extends RefCounted
## Walk-in shops: Woolly Goods, the bakery and the land office. Their models
## (art/world_assets/town_buildings) come in parts, like the barn: `base` (the plank floor and the
## things standing outside), each wall at full height (`wall_front`...) and cut down to a stub
## (`wall_front_low`...), a `door` hinged on its left jamb, and the `roof`. While she is inside one
## its roof is hidden and the walls facing the camera drop to stubs (unless Walls Up is on); the
## door swings in as anyone comes up to it; a lamp inside comes up as the daylight goes.
## Each is furnished from data/interiors.json, and its shopkeeper (villagers.json "works_in")
## stands behind the counter. Everything is a child of the building's node, so the world editor
## moves it all together.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const Planks = preload("res://scripts/planks.gd")

const WALLS := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}
const T := 0.2 # wall thickness
const DOOR_HALF := 0.62 # half the gap the front wall's obstacles leave at the door

## One building you can walk into.
class Shop:
	var id := ""
	var node: Node3D
	var size := Vector2.ZERO # over the walls (x, z)
	var parts := {} # MeshInstance3D by part name
	var inside := false
	var open := 0.0 # the door: 0 shut .. 1 swung in
	var light: OmniLight3D
	var info := {} # its entry in data/interiors.json

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
	shops[id] = s
	for side in WALLS:
		if parts.has("wall_%s_low" % side):
			(parts["wall_%s_low" % side] as Node3D).visible = false
	var w := size.x * 0.5
	var d := size.y * 0.5
	var rects := [
		Rect2(-w, -d, size.x, T), Rect2(-w, -d, T, size.y), Rect2(w - T, -d, T, size.y), # back, left, right
		Rect2(-w, d - T, w - DOOR_HALF, T), Rect2(DOOR_HALF, d - T, w - DOOR_HALF, T), # the front, either side of the door
	]
	for o in s.info.get("outside", []):
		rects.append(Rect2(float(o[0]), float(o[1]), float(o[2]), float(o[3])))
	# the same plank floor as the houses, in this shop's own shade, over the model's boards
	Planks.lay(b, "floor", Vector3(-w + T, 0.0315, -d + T), Vector3(1, 0, 0), Vector3(0, 0, 1), size - Vector2(2 * T, 2 * T), Vector3.UP, [], hash(id), id)
	var room := Node3D.new()
	room.name = "Furnishings"
	b.add_child(room)
	for f in s.info.get("furniture", []):
		var fid := str(f["id"])
		var at: Vector2 = Data.vec2(f["at"])
		var turn := float(f.get("turn", 0.0))
		var n := Node3D.new()
		n.name = fid
		n.position = Vector3(at.x, 0, at.y)
		n.rotation.y = deg_to_rad(turn)
		room.add_child(n)
		Catalog.build(fid, n)
		var item: Dictionary = Catalog.ITEMS.get(fid, {})
		if bool(item.get("flat", false)):
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
	return absf(p.x) < s.size.x * 0.5 and absf(p.z) < s.size.y * 0.5


## The ground under each shop's floor, wherever it stands now, so no grass grows through it.
static func floors() -> Array:
	var out := []
	for s in shops.values():
		if not is_instance_valid(s.node) or not s.node.visible:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for sx in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				var p: Vector3 = s.node.global_transform * Vector3(sx * s.size.x, 0, sz * s.size.y)
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
		for m in [who] + movers:
			var q: Vector3 = inv * (m as Vector3)
			if absf(q.x) < 1.0 and q.z > s.size.y * 0.5 - 1.4 and q.z < s.size.y * 0.5 + 1.5:
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
