extends Node3D
## Tiny hidden hamlets out in the lands (2026-11-27, data/hamlets.json). Alex: "little towns
## scattered throughout that you can also discover ... extremely small and maybe have different
## themes like witchy theme or ice theme".
##
## - Four for now: Hexwood Hollow (witchy, in the dark woods between the swamp and the foothills),
##   Rimefall (ice, at the foot of the mountains, a snowfield and snow falling), Sunwell (an oasis in
##   the deep dunes) and Larkhill (a windmill on the downs). Each is a few buildings, a landmark and
##   one keeper. Names, lines and numbers are drafts.
## - Finding one: Nora, or the dog while played, comes within `discover` metres of its centre.
##   Game.flags["hamlets"][id] = the day; a toast and the journal chime. EmpireGoals' "hamlets"
##   check counts them.
## - The keeper is a new market: they buy a sweater a day, of one of their theme's fibres (any of
##   those buyers may ask for now and she has seen, else sheep's wool), and pay up to `mult` times
##   what anyone else would (SweaterSale.themed, read by wanted_fibre() and reserve()). They wear
##   the red pin while they want one.
## - Each hamlet is one node in the world editor (Town.built, kind "hamlet"): moved there, its
##   keeper, discovery and cleared ground go with it. Its buildings block the walking grid.
## - Everything is a STAND-IN from plain shapes dressed in the house's own maps (house_skin.gd),
##   and the keepers borrow Maple Grove's townsfolk bodies with a hat of the theme
##   (docs/DIRECTION.md "Models still needed").
## - `on` (keepers, discovery, pins) is off in the autotest but for --only=hamlets; the buildings
##   are always there.

const Data = preload("res://scripts/data.gd")
const Explore = preload("res://scripts/explore.gd")
const HouseSkin = preload("res://scripts/house_skin.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Town = preload("res://scripts/town.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Townsfolk = preload("res://scripts/townsfolk.gd")

static var on := true

var main
var data := {}
var hamlets: Array = [] # {"cfg", "node", "keeper", "sails"}
var keepers: Array = []
var _t := 0.0
var _pin_tex: Texture2D
var _found_toast := ""


func _ready() -> void:
	name = "Hamlets"


func cfg_of(id: String) -> Dictionary:
	for h in hamlets:
		if str(h["cfg"].get("id", "")) == id:
			return h["cfg"]
	return {}


func node_of(id: String) -> Node3D:
	for h in hamlets:
		if str(h["cfg"].get("id", "")) == id:
			return h["node"]
	return null


static func found() -> Dictionary:
	var f = Game.flags.get("hamlets", {})
	return f if f is Dictionary else {}


static func found_count() -> int:
	return found().size()


func is_found(id: String) -> bool:
	return found().has(id)


# --- building -------------------------------------------------------------------------------------

## Builds every hamlet (before the walking grid). Returns their buildings' blocks.
func build() -> Array:
	data = Data.load_json("hamlets")
	var blocks := []
	for c in data.get("hamlets", []):
		var cfg: Dictionary = c
		var at: Array = cfg.get("at", [0, 0])
		var node := Node3D.new()
		node.name = "Hamlet_" + str(cfg.get("id", ""))
		node.position = Vector3(float(at[0]), 0.0, float(at[1]))
		node.rotation_degrees.y = float(cfg.get("yaw", 0.0))
		main.add_child(node)
		var rects := []
		var h := {"cfg": cfg, "node": node, "keeper": null, "sails": []}
		for b in cfg.get("buildings", []):
			var bn := Node3D.new()
			bn.position = Vector3(float(b[1]), 0.0, float(b[2]))
			bn.rotation_degrees.y = float(b[3])
			node.add_child(bn)
			var size := _building(bn, str(b[0]), float(b[4]), float(b[5]), float(b[6]), cfg, h)
			rects.append(_rect_of(bn, size))
		for p in cfg.get("props", []):
			var pn := Node3D.new()
			pn.position = Vector3(float(p[1]), 0.0, float(p[2]))
			pn.rotation_degrees.y = float(p[3])
			node.add_child(pn)
			var size := _prop(pn, str(p[0]), cfg)
			if size != Vector2.ZERO:
				rects.append(_rect_of(pn, size))
		if cfg.has("snow"):
			_snow(node, float(cfg["snow"]))
		h["lights"] = node.find_children("*", "OmniLight3D", true, false)
		hamlets.append(h)
		Town.built.append([node, "hamlet", str(cfg.get("name", "Hamlet")), rects])
		blocks.append_array(rects)
	return blocks


## The world rect a footprint of `size` covers round node `n`, as it's turned.
func _rect_of(n: Node3D, size: Vector2) -> Rect2:
	var r := Rect2()
	var first := true
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p: Vector3 = n.global_transform * Vector3(size.x * sx, 0, size.y * sz)
			var q := Rect2(p.x, p.z, 0, 0)
			r = q if first else r.merge(q)
			first = false
	return r


## True if the world's scenery at `at` stands on a hamlet's ground (forage.apply() cuts it).
func clears(at: Vector3) -> bool:
	for h in hamlets:
		var n: Node3D = h["node"]
		if is_instance_valid(n) and Vector2(at.x - n.global_position.x, at.z - n.global_position.z).length() < float(h["cfg"].get("clear", 14.0)):
			return true
	return false


## Where no grass grows: the snowfields (main._rebuild_grass). Vector3(x, z, radius).
func grass_holes() -> Array:
	var out := []
	for h in hamlets:
		if h["cfg"].has("snow"):
			var n: Node3D = h["node"]
			out.append(Vector3(n.global_position.x, n.global_position.z, float(h["cfg"]["snow"]) * 0.9))
	return out


static func _m(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _glow(c: Color, energy := 1.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


static func _skin(kind: String, tint: String) -> StandardMaterial3D:
	return HouseSkin.material(kind, Color(tint))


static func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return Explore._box(p, size, pos, mat, rot)


static func _cone(p: Node3D, r_bottom: float, r_top: float, h: float, pos: Vector3, mat: Material, seg := 12, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi


static func _ball(p: Node3D, r: float, pos: Vector3, mat: Material, squash := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = Vector3(1, squash, 1)
	p.add_child(mi)
	return mi


## A solid prism: a triangle `w` wide and `h` tall (in x, y), `d` deep (z). Its base is at `pos`.
static func _prism(p: Node3D, w: float, h: float, d: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w, h, d)
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0)
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi


## One building of the hamlet. Returns its footprint (x, z) in its own space.
func _building(n: Node3D, kind: String, w: float, d: float, h: float, cfg: Dictionary, ham: Dictionary) -> Vector2:
	var st: Dictionary = cfg.get("style", {})
	match kind:
		"cottage":
			_cottage(n, w, d, h, st)
			return Vector2(w + 0.3, d + 0.3)
		"tower":
			_tower(n, w, h, st)
			return Vector2(w + 0.2, w + 0.2)
		"adobe":
			_adobe(n, w, d, h, st)
			return Vector2(w + 0.4, d + 0.4)
		"tent":
			_tent(n, w, d, h)
			return Vector2(w, d)
		"windmill":
			ham["sails"].append(_windmill(n, w, h, st))
			return Vector2(w, w)
	return Vector2(w, d)


## Windows: a glowing pane with a dark frame, on the face that looks +Z of `n` at `pos`.
func _window(n: Node3D, pos: Vector3, size: Vector2, st: Dictionary, rot := Vector3.ZERO) -> void:
	var frame := _skin("timber_h", str(st.get("frame", "#4a3a2a")))
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = rot
	n.add_child(holder)
	# each part's back is sunk into the wall (holder z -0.03) by its own amount, so no two faces share a plane
	_box(holder, Vector3(size.x + 0.14, size.y + 0.14, 0.06), Vector3(0, 0, 0.01), frame) # [-0.02, 0.04]
	_box(holder, Vector3(size.x, size.y, 0.09), Vector3(0, 0, 0.005), _glow(Color(str(st.get("window", "#ffd28a"))), 0.9)) # [-0.04, 0.05]
	_box(holder, Vector3(0.05, size.y - 0.02, 0.105), Vector3(0, 0, 0.0175), frame) # the glazing bar [-0.035, 0.07]
	_box(holder, Vector3(size.x + 0.24, 0.07, 0.16), Vector3(0, -size.y * 0.5 - 0.06, 0.045), frame) # the sill [-0.035, 0.125]


## A cottage: walls of the style's map on a stone footing, a timber frame at the corners, a door
## and windows, an attic gable and a roof with its ridge across the front (snow on it in Rimefall).
func _cottage(n: Node3D, w: float, d: float, h: float, st: Dictionary) -> void:
	var wall := _skin(str(st.get("wall", "plaster")), str(st.get("wall_tint", "#ffffff")))
	var frame := _skin("timber", str(st.get("frame", "#4a3a2a")))
	var stone := HouseSkin.material("stone")
	_box(n, Vector3(w + 0.12, 0.32, d + 0.12), Vector3(0, 0.16, 0), stone)
	_box(n, Vector3(w, h - 0.3, d), Vector3(0, 0.3 + (h - 0.3) * 0.5, 0), wall)
	if str(st.get("wall", "")) == "plaster":
		for sx in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				_box(n, Vector3(0.16, h - 0.3, 0.16), Vector3(sx * w, 0.3 + (h - 0.3) * 0.5, sz * d), frame)
		_box(n, Vector3(w + 0.04, 0.14, d + 0.04), Vector3(0, h - 0.05, 0), _skin("timber_h", str(st.get("frame", "#4a3a2a"))))
	# the door and its frame, the windows
	_box(n, Vector3(0.96, 1.82, 0.1), Vector3(-w * 0.18, 0.3 + 0.91, d * 0.5 + 0.03), _skin("timber", str(st.get("frame", "#4a3a2a"))))
	_box(n, Vector3(0.82, 1.7, 0.12), Vector3(-w * 0.18, 0.3 + 0.86, d * 0.5 + 0.05), _skin("paintwood", "#6b4a3a"))
	_window(n, Vector3(w * 0.25, 0.3 + h * 0.5, d * 0.5 + 0.03), Vector2(0.6, 0.55), st)
	_window(n, Vector3(w * 0.5 + 0.03, 0.3 + h * 0.5, 0), Vector2(0.5, 0.5), st, Vector3(0, 90, 0))
	_window(n, Vector3(-w * 0.5 - 0.03, 0.3 + h * 0.5, 0.2), Vector2(0.5, 0.5), st, Vector3(0, -90, 0))
	# the roof: a leaning top (Hexwood's lean) over an attic prism, ridge along x
	var top := Node3D.new()
	top.position.y = h
	top.rotation_degrees.z = float(st.get("lean", 0.0))
	n.add_child(top)
	var pitch := deg_to_rad(float(st.get("pitch", 40.0)))
	var half := d * 0.5
	var rise := half * tan(pitch)
	_prism(top, d, rise, w, Vector3.ZERO, wall, Vector3(0, 90, 0))
	var over := 0.35
	var slope := (half + over) / cos(pitch)
	var roof_tint := str(st.get("roof_tint", "#ffffff"))
	for s in [-1.0, 1.0]:
		# from the ridge (z 0, y rise) down past the eave by `over`, laid on the attic
		var mid := Vector3(0, rise - (half + over) * 0.5 * tan(pitch) + 0.06, s * (half + over) * 0.5)
		var slab := _box(top, Vector3(w + over * 2.0, 0.1, slope), mid, _skin("shingles" if s > 0 else "shingles_r", roof_tint), Vector3(s * rad_to_deg(pitch), 0, 0))
		if st.get("snowcap", false) == true:
			var cap := _box(top, Vector3(w + over * 2.0 - 0.1, 0.12, slope * 0.85), slab.position + Vector3(0, 0.1, 0) - Vector3(0, 0, s * 0.05), _m(Color(0.96, 0.97, 1.0), 0.85), slab.rotation_degrees)
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			# icicles under the eave
			var eave: Vector3 = slab.position + Vector3(0, -sin(pitch) * slope * 0.5, s * cos(pitch) * slope * 0.5)
			for k in int(w * 3.0):
				var ix := -w * 0.5 - over + 0.2 + (w + over * 2.0 - 0.4) * float(k) / maxf(1.0, w * 3.0 - 1.0)
				var ln := 0.12 + 0.22 * absf(sin(float(k) * 2.3))
				_cone(top, 0.035, 0.0, ln, eave + Vector3(ix, -ln * 0.5 - 0.02, 0), _m(Color(0.85, 0.93, 1.0), 0.05), 5, Vector3(180, 0, 0))
	_box(top, Vector3(w + over * 2.0, 0.12, 0.16), Vector3(0, rise + 0.08, 0), _skin("timber_h", str(st.get("frame", "#4a3a2a")))) # the ridge board
	# a chimney through the roof, smoking-hot stone
	var chim := _box(top, Vector3(0.6, rise + 1.0, 0.6), Vector3(w * 0.3, (rise + 1.0) * 0.5, -half * 0.35), stone)
	chim.rotation_degrees.z = -float(st.get("lean", 0.0)) * 1.6
	if st.get("snowcap", false) == true:
		_box(top, Vector3(0.66, 0.1, 0.66), Vector3(w * 0.3, rise + 1.05, -half * 0.35), _m(Color(0.96, 0.97, 1.0), 0.85))


## Hexwood's round tower: a leaning cone roof over a tall round wall, a door and a high window.
func _tower(n: Node3D, w: float, h: float, st: Dictionary) -> void:
	var r := w * 0.5
	var wall := _skin(str(st.get("wall", "plaster")), str(st.get("wall_tint", "#ffffff")))
	_cone(n, r + 0.08, r + 0.08, 0.35, Vector3(0, 0.175, 0), HouseSkin.material("stone"), 14)
	_cone(n, r, r * 0.92, h, Vector3(0, h * 0.5, 0), wall, 14)
	_box(n, Vector3(0.9, 1.8, 0.14), Vector3(0, 1.2, r - 0.02), _skin("paintwood", "#3d2b3a"))
	_window(n, Vector3(0, h * 0.72, r * 0.94), Vector2(0.45, 0.6), st)
	_window(n, Vector3(r * 0.92, h * 0.5, 0), Vector2(0.4, 0.5), st, Vector3(0, 90, 0))
	var roof := Node3D.new()
	roof.position.y = h
	roof.rotation_degrees = Vector3(float(st.get("lean", 0.0)) * 1.8, 0, -float(st.get("lean", 0.0)) * 1.4)
	n.add_child(roof)
	_cone(roof, r + 0.45, 0.0, 2.8, Vector3(0, 1.4, 0), _skin("shingles", str(st.get("roof_tint", "#ffffff"))), 14)
	_cone(roof, 0.04, 0.0, 0.5, Vector3(0.0, 3.0, 0.0), _m(Color(0.15, 0.12, 0.1)), 6) # the finial


## Sunwell's adobe: a sand-plaster box with a flat roof behind a low parapet, roof beams poking out.
func _adobe(n: Node3D, w: float, d: float, h: float, st: Dictionary) -> void:
	var wall := _skin("plaster", str(st.get("wall_tint", "#e8c08a")))
	var beam := _skin("timber_h", str(st.get("frame", "#6b4a2c")))
	_box(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), wall)
	_box(n, Vector3(w + 0.1, 0.35, 0.18), Vector3(0, h + 0.17, d * 0.5 - 0.04), wall)
	_box(n, Vector3(w + 0.1, 0.35, 0.18), Vector3(0, h + 0.17, -d * 0.5 + 0.04), wall)
	_box(n, Vector3(0.18, 0.35, d), Vector3(w * 0.5 - 0.04, h + 0.17, 0), wall)
	_box(n, Vector3(0.18, 0.35, d), Vector3(-w * 0.5 + 0.04, h + 0.17, 0), wall)
	for k in 5: # the vigas
		var x := -w * 0.4 + w * 0.8 * float(k) / 4.0
		Explore._cyl(n, 0.08, 0.7, Vector3(x, h - 0.2, d * 0.5 + 0.1), beam, Vector3(90, 0, 0))
	_box(n, Vector3(0.9, 1.75, 0.08), Vector3(w * 0.15, 0.88, d * 0.5 + 0.03), _skin("paintwood", "#2f6d8a"))
	_box(n, Vector3(1.1, 0.12, 0.3), Vector3(w * 0.15, 1.82, d * 0.5 + 0.1), beam)
	_window(n, Vector3(-w * 0.25, h * 0.55, d * 0.5 + 0.03), Vector2(0.5, 0.5), st)
	_window(n, Vector3(w * 0.5 + 0.03, h * 0.55, 0), Vector2(0.45, 0.45), st, Vector3(0, 90, 0))
	# a ladder to the roof
	for s in [-0.22, 0.22]:
		_box(n, Vector3(0.06, h + 0.6, 0.06), Vector3(-w * 0.5 - 0.35 + s, (h + 0.6) * 0.5, -0.4), beam, Vector3(0, 0, -8))
	for k in 5:
		_box(n, Vector3(0.5, 0.04, 0.05), Vector3(-w * 0.5 - 0.35 + 0.05 * float(k) * 0.3, 0.4 + 0.5 * k, -0.4), beam)


## A caravan's tent: striped canvas, the doorway at the front.
func _tent(n: Node3D, w: float, d: float, h: float) -> void:
	var canvas := _m(Color(0.93, 0.87, 0.74), 0.95)
	var stripe := _m(Color(0.72, 0.3, 0.2), 0.95)
	_prism(n, w, h, d, Vector3.ZERO, canvas)
	for k in 3: # stripes laid on the slopes
		var z := -d * 0.33 + d * 0.33 * k
		_prism(n, w + 0.02, h + 0.01, 0.22, Vector3(0, 0, z), stripe)
	_prism(n, w * 0.42, h * 0.62, 0.04, Vector3(0, 0, d * 0.5 + 0.01), _m(Color(0.12, 0.08, 0.06)))
	Explore._cyl(n, 0.04, h + 0.4, Vector3(0, (h + 0.4) * 0.5, d * 0.5 + 0.05), _m(Color(0.4, 0.3, 0.2)))
	var rug := _box(n, Vector3(w * 0.6, 0.02, 1.2), Vector3(0, 0.01, d * 0.5 + 0.7), _m(Color(0.6, 0.18, 0.14), 1.0))
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Larkhill's windmill: a white tower, a dark cap and four lattice sails that turn. Returns the sails.
func _windmill(n: Node3D, w: float, h: float, st: Dictionary) -> Node3D:
	var r := w * 0.5
	var wall := _skin("plaster", "#f2ede2")
	_cone(n, r + 0.1, r + 0.1, 0.5, Vector3(0, 0.25, 0), HouseSkin.material("stone"), 16)
	_cone(n, r, r * 0.68, h, Vector3(0, h * 0.5, 0), wall, 16)
	_cone(n, r * 0.75, 0.0, 2.0, Vector3(0, h + 1.0, 0), _skin("shingles", "#3c3a38"), 16)
	_box(n, Vector3(1.0, 1.9, 0.14), Vector3(0, 1.2, r - 0.04), _skin("paintwood", "#3f5a3a"))
	_window(n, Vector3(0, h * 0.62, r * 0.82 + 0.02), Vector2(0.45, 0.6), st, Vector3(-6, 0, 0))
	var hub := Node3D.new()
	hub.name = "Sails"
	hub.position = Vector3(0, h - 0.3, r * 0.68 + 0.5)
	n.add_child(hub)
	var wood := _skin("timber", "#5a4630")
	var cloth := _m(Color(0.92, 0.89, 0.8), 0.95)
	Explore._cyl(hub, 0.2, 0.5, Vector3(0, 0, -0.2), wood, Vector3(90, 0, 0))
	for i in 4:
		var arm := Node3D.new()
		arm.rotation_degrees.z = 90.0 * i
		hub.add_child(arm)
		_box(arm, Vector3(0.16, 4.2, 0.12), Vector3(0, 2.1, 0), wood)
		_box(arm, Vector3(0.95, 3.3, 0.04), Vector3(0.55, 2.4, 0.04), cloth)
		for k in 5:
			_box(arm, Vector3(1.0, 0.05, 0.06), Vector3(0.55, 0.9 + 0.75 * k, 0.07), wood)
	return hub


# --- props ---------------------------------------------------------------------------------------

## One prop. Returns its footprint on the walking grid, or Vector2.ZERO to walk through it.
func _prop(n: Node3D, kind: String, cfg: Dictionary) -> Vector2:
	var light := Color(str(cfg.get("light", "#ffd08a")))
	match kind:
		"cauldron":
			var iron := _m(Color(0.09, 0.09, 0.1), 0.45, 0.6)
			for k in 3:
				var a := TAU * k / 3.0
				_box(n, Vector3(0.08, 0.5, 0.08), Vector3(cos(a) * 0.38, 0.25, sin(a) * 0.38), iron)
			_cone(n, 0.42, 0.56, 0.62, Vector3(0, 0.62, 0), iron, 16)
			_ball(n, 0.5, Vector3(0, 0.45, 0), iron, 0.6)
			var brew := _cone(n, 0.52, 0.52, 0.03, Vector3(0, 0.9, 0), _glow(Color(0.45, 1.0, 0.35), 2.2), 16)
			brew.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var fm := (Catalog.fire_material(0.9, 1.3) as ShaderMaterial).duplicate() as ShaderMaterial
			fm.set_shader_parameter("col_core", Color(0.85, 1.0, 0.75))
			fm.set_shader_parameter("col_body", Color(0.3, 0.95, 0.25))
			fm.set_shader_parameter("col_tip", Color(0.1, 0.35, 0.08))
			Catalog.flame_quad(n, Vector2(0.8, 0.55), Vector3(0, 0.02, 0.05), fm)
			Catalog.flame_quad(n, Vector2(0.7, 0.5), Vector3(0.1, 0.02, -0.05), fm)
			for k in 7: # logs under it
				var a := TAU * k / 7.0
				Explore._cyl(n, 0.05, 0.7, Vector3(cos(a) * 0.25, 0.05, sin(a) * 0.25), _m(Color(0.25, 0.17, 0.11)), Vector3(90, rad_to_deg(a), 0))
			var l := Catalog.omni(n, Vector3(0, 1.2, 0), Color(0.5, 1.0, 0.45), 8.0, 0.6, 2.4)
			l.set_meta("no_shadow", true)
			l.shadow_enabled = false
			Catalog.fire_sound(n, Vector3(0, 0.3, 0), 10.0, -10.0)
			return Vector2(1.4, 1.4)
		"toadstools":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7171
			var stem := _m(Color(0.92, 0.88, 0.8))
			for k in 11:
				var a := TAU * k / 11.0 + rng.randf_range(-0.15, 0.15)
				var rr := 1.3 + rng.randf_range(-0.15, 0.15)
				var hh := rng.randf_range(0.12, 0.3)
				var p := Vector3(cos(a) * rr, 0, sin(a) * rr)
				Explore._cyl(n, 0.035 + hh * 0.08, hh, p + Vector3(0, hh * 0.5, 0), stem)
				var cap := Color(0.78, 0.12, 0.1) if k % 3 != 0 else Color(0.5, 0.25, 0.65)
				_ball(n, 0.08 + hh * 0.3, p + Vector3(0, hh, 0), _m(cap, 0.5), 0.55)
			return Vector2.ZERO
		"lantern":
			var post := _m(Color(0.12, 0.1, 0.09), 0.6, 0.3)
			Explore._cyl(n, 0.05, 2.1, Vector3(0, 1.05, 0), post)
			_box(n, Vector3(0.05, 0.05, 0.5), Vector3(0, 2.05, 0.22), post)
			var lm := Catalog.model("res://assets/props/lantern.glb", n)
			if lm:
				lm.position = Vector3(0, 2.0, 0.42)
			var g := _ball(n, 0.07, Vector3(0, 1.82, 0.42), _glow(light, 3.0))
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Catalog.omni(n, Vector3(0, 1.8, 0.42), light, 7.0, 0.0, 1.6)
			return Vector2(0.4, 0.4)
		"snowman":
			var snow := _m(Color(0.96, 0.97, 1.0), 0.85)
			_ball(n, 0.5, Vector3(0, 0.45, 0), snow)
			_ball(n, 0.36, Vector3(0, 1.1, 0), snow)
			_ball(n, 0.25, Vector3(0, 1.58, 0), snow)
			_cone(n, 0.05, 0.0, 0.3, Vector3(0, 1.6, 0.36), _m(Color(0.95, 0.45, 0.1), 0.6), 8, Vector3(90, 0, 0))
			for s in [-1.0, 1.0]:
				_ball(n, 0.03, Vector3(s * 0.09, 1.66, 0.22), _m(Color(0.05, 0.05, 0.05)))
				_box(n, Vector3(0.6, 0.03, 0.03), Vector3(s * 0.55, 1.15, 0), _m(Color(0.3, 0.2, 0.12)), Vector3(0, 0, s * 25.0))
			_cone(n, 0.2, 0.2, 0.22, Vector3(0, 1.88, 0), _m(Color(0.1, 0.1, 0.12)), 12) # his hat
			_cone(n, 0.3, 0.3, 0.03, Vector3(0, 1.77, 0), _m(Color(0.1, 0.1, 0.12)), 12)
			return Vector2(1.0, 1.0)
		"ice_pond":
			var ice := _m(Color(0.72, 0.86, 0.95), 0.06, 0.1)
			var p := _cone(n, 2.8, 2.8, 0.04, Vector3(0, 0.03, 0), ice, 28)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return Vector2.ZERO
		"firepit":
			var rock := _m(Color(0.45, 0.44, 0.42))
			for k in 9:
				var a := TAU * k / 9.0
				_ball(n, 0.16, Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), rock, 0.7)
			for k in 4:
				Explore._cyl(n, 0.06, 0.8, Vector3(0, 0.12, 0), _m(Color(0.28, 0.19, 0.12)), Vector3(70, 45.0 * k, 0))
			Catalog.flame_quad(n, Vector2(0.9, 1.0), Vector3(0, 0.05, 0), Catalog.fire_material(0.9, 1.0))
			Catalog.flame_quad(n, Vector2(0.8, 0.85), Vector3(0.1, 0.05, 0.05), Catalog.fire_material(0.8, 1.1))
			Catalog.omni(n, Vector3(0, 0.8, 0), Color(1.0, 0.62, 0.3), 9.0, 0.8, 2.6)
			Catalog.fire_sound(n, Vector3(0, 0.3, 0), 14.0, -4.0)
			return Vector2(1.4, 1.4)
		"pool":
			var water := _m(Color(0.16, 0.45, 0.5), 0.04, 0.1)
			var wt := _cone(n, 3.0, 3.0, 0.04, Vector3(0, 0.03, 0), water, 32)
			wt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rim := _m(Color(0.72, 0.6, 0.44))
			for k in 22:
				var a := TAU * k / 22.0
				_box(n, Vector3(0.55, 0.22, 0.32), Vector3(cos(a) * 3.15, 0.1, sin(a) * 3.15), rim, Vector3(0, -rad_to_deg(a), 0))
			var reed := _m(Color(0.35, 0.5, 0.22))
			for k in 26:
				var a := TAU * k / 26.0 + 0.1 * sin(k * 3.1)
				var hh := 0.5 + 0.4 * absf(sin(k * 1.7))
				Explore._cyl(n, 0.02, hh, Vector3(cos(a) * 2.7, hh * 0.5, sin(a) * 2.7), reed, Vector3(6.0 * sin(k * 2.0), 0, 6.0 * cos(k * 1.3)))
			return Vector2(6.4, 6.4)
		"palm":
			var bark := _m(Color(0.5, 0.38, 0.26))
			var leaf := _m(Color(0.3, 0.52, 0.2), 0.8)
			leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
			var p := Vector3.ZERO
			var lean := 0.0
			for k in 7:
				lean += 4.0
				var seg := Explore._cyl(n, 0.17 - k * 0.012, 0.78, p + Vector3(0, 0.39, 0), bark, Vector3(0, 0, -lean))
				p += Vector3(sin(deg_to_rad(lean)) * 0.78, cos(deg_to_rad(lean)) * 0.78, 0)
				seg.position = p - Vector3(sin(deg_to_rad(lean)) * 0.39, cos(deg_to_rad(lean)) * 0.39, 0)
			for k in 8:
				var f := Node3D.new()
				f.position = p
				f.rotation_degrees = Vector3(0, 45.0 * k + 10.0 * sin(k), 0)
				n.add_child(f)
				var fr := _box(f, Vector3(0.42, 0.02, 2.0), Vector3(0, -0.35, 0.9), leaf, Vector3(-28.0 - 8.0 * (k % 2), 0, 0))
				fr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for k in 3:
				_ball(n, 0.1, p + Vector3(0.12 * cos(k * 2.1), -0.15, 0.12 * sin(k * 2.1)), _m(Color(0.35, 0.24, 0.12)))
			return Vector2(0.6, 0.6)
		"hay":
			var m := Catalog.model("res://assets/props/hay_bale.glb", n)
			return Vector2(1.2, 0.8) if m else Vector2.ZERO
		"fence":
			var m := Catalog.model("res://assets/props/fence_section.glb", n)
			return Vector2(2.0, 0.3) if m else Vector2.ZERO
	return Vector2.ZERO


## Rimefall's snowfield (a soft-edged white disc, no grass on it) and the snow falling over it.
func _snow(n: Node3D, r: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.72, Color(1, 1, 1, 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.albedo_color = Color(0.95, 0.97, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.roughness = 0.85
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.2, r * 2.2)
	q.mesh = pm
	q.material_override = m
	q.position.y = 0.025
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.name = "Snowfield"
	n.add_child(q)
	# the snow falling
	var parts := GPUParticles3D.new()
	parts.name = "Snowfall"
	parts.amount = 600
	parts.lifetime = 7.0
	parts.preprocess = 7.0
	parts.visibility_aabb = AABB(Vector3(-r - 4, -2, -r - 4), Vector3(r * 2 + 8, 16, r * 2 + 8))
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(r + 3.0, 0.5, r + 3.0)
	pp.direction = Vector3(0.2, -1, 0.1)
	pp.spread = 12.0
	pp.initial_velocity_min = 0.6
	pp.initial_velocity_max = 1.2
	pp.gravity = Vector3(0, -0.5, 0)
	pp.turbulence_enabled = true
	pp.turbulence_noise_strength = 0.6
	pp.turbulence_noise_scale = 3.0
	parts.process_material = pp
	var flake := QuadMesh.new()
	flake.size = Vector2(0.05, 0.05)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1, 1, 1, 0.9)
	fm.albedo_texture = gt # round and soft, not a square
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA # a flake right at the camera fades rather than filling the view
	fm.distance_fade_min_distance = 0.6
	fm.distance_fade_max_distance = 2.5
	flake.material = fm
	parts.draw_pass_1 = flake
	parts.position.y = 9.0
	parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(parts)


# --- after the grid: the keepers ----------------------------------------------------------------

## Builds the keepers (only while `on`) and tells the sale who pays more. main.gd calls it once
## the grid is built; a load reloads the scene.
func apply() -> void:
	for k in keepers:
		if is_instance_valid(k):
			k.queue_free()
	keepers.clear()
	SweaterSale.themed.clear()
	if not on:
		return
	for h in hamlets:
		var kc: Dictionary = h["cfg"].get("keeper", {})
		if kc.is_empty():
			continue
		var k := Keeper.new()
		k.hamlets = self
		k.hamlet_id = str(h["cfg"]["id"])
		k.job = str(kc.get("job", ""))
		k.setup(str(kc["id"]), str(kc.get("name", "Keeper")), "", "", _keeper_spot(h), {"model": str(kc.get("model", "tf_theo"))})
		k.roam = Vector2(0.4, 0.3)
		k.rest_yaw = deg_to_rad(float(kc.get("yaw", 180.0)) + (h["node"] as Node3D).rotation_degrees.y)
		k.rotation.y = float(k.rest_yaw)
		main.add_child(k)
		if k.tag:
			k.tag.text = k.display_name()
		_hat(k, str(kc.get("hat", "")))
		h["keeper"] = k
		keepers.append(k)
		SweaterSale.themed[k.vid] = {"fibres": kc.get("wants", ["wool"]), "mult": float(kc.get("mult", 1.0))}


func _keeper_spot(h: Dictionary) -> Vector3:
	var s: Array = h["cfg"].get("keeper", {}).get("spot", [0, 2])
	var p: Vector3 = (h["node"] as Node3D).global_transform * Vector3(float(s[0]), 0, float(s[1]))
	return Vector3(p.x, 0, p.z)


## A hat of the theme on the keeper's head bone (they borrow the townsfolk's bodies, so this is
## what tells them apart): a witch's hat, a trapper's fur hat, a head wrap or a miller's cap.
func _hat(k, kind: String) -> void:
	if kind == "" or k.body == null or k.body.skeleton == null:
		return
	var sk: Skeleton3D = k.body.skeleton
	var bi := sk.find_bone("Head")
	if bi < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var hat := Node3D.new()
	hat.name = "Hat"
	att.add_child(hat)
	hat.visible = false # until it's seated on the crown (_seat_hat, once the pose has been worked out)
	_seat_hat.call_deferred(k, att, hat, bi)
	match kind:
		"witch":
			var felt := _m(Color(0.16, 0.1, 0.2), 0.9)
			_cone(hat, 0.27, 0.27, 0.02, Vector3(0, 0.0, 0), felt, 20)
			var tip := _cone(hat, 0.15, 0.015, 0.46, Vector3(0, 0.23, -0.02), felt, 14, Vector3(-10, 0, 6))
			tip.name = "Crown"
			_cone(hat, 0.155, 0.15, 0.06, Vector3(0, 0.04, 0), _m(Color(0.45, 0.85, 0.35), 0.6), 14)
		"fur":
			var fur := _m(Color(0.42, 0.3, 0.2), 1.0)
			_cone(hat, 0.15, 0.14, 0.2, Vector3(0, 0.05, 0), fur, 16)
			_cone(hat, 0.165, 0.165, 0.07, Vector3(0, -0.04, 0), _m(Color(0.86, 0.82, 0.74), 1.0), 16)
			for s in [-1.0, 1.0]:
				_box(hat, Vector3(0.04, 0.13, 0.11), Vector3(s * 0.15, -0.09, 0.0), fur)
		"wrap":
			var cloth := _m(Color(0.88, 0.82, 0.68), 1.0)
			_cone(hat, 0.15, 0.13, 0.15, Vector3(0, 0.03, 0), cloth, 16)
			var band := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.12
			tm.outer_radius = 0.17
			band.mesh = tm
			band.material_override = _m(Color(0.7, 0.36, 0.2), 1.0)
			band.position.y = -0.01
			hat.add_child(band)
			_box(hat, Vector3(0.12, 0.3, 0.03), Vector3(0.02, -0.18, -0.15), cloth, Vector3(10, 0, 0))
		"cap":
			var tweed := _m(Color(0.35, 0.32, 0.26), 1.0)
			_cone(hat, 0.15, 0.13, 0.07, Vector3(0, 0.0, -0.01), tweed, 16)
			_box(hat, Vector3(0.24, 0.02, 0.12), Vector3(0, -0.02, 0.14), tweed, Vector3(-12, 0, 0))



## Puts the hat on the crown of the keeper's head: the top of their body's meshes (hair included),
## straight up the head bone from where it starts, upright with the head and facing the way they do.
## Worked out in the world once the body is posed, so the rig's own scale and turns don't matter.
func _seat_hat(k, att: BoneAttachment3D, hat: Node3D, bi: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(k) or not is_instance_valid(hat):
		return
	var sk: Skeleton3D = k.body.skeleton
	var head: Transform3D = sk.global_transform * sk.get_bone_global_pose(bi)
	var top := -INF
	for mi in k.body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null or hat.is_ancestor_of(m3) or not m3.is_visible_in_tree():
			continue
		var box: AABB = m3.global_transform * m3.get_aabb()
		top = maxf(top, box.end.y)
	if top == -INF:
		top = head.origin.y + 0.2
	var up := head.basis.y.normalized()
	if up.y < 0.5:
		up = Vector3.UP
	var crown := head.origin + up * ((top - 0.05 - head.origin.y) / up.y)
	var fwd: Vector3 = (k as Node3D).global_transform.basis.z
	var z := (fwd - up * fwd.dot(up)).normalized()
	var want := Transform3D(Basis(up.cross(z), up, z), crown)
	hat.transform = att.global_transform.affine_inverse() * want
	hat.visible = true


# --- each frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	for h in hamlets: # the sails turn (only where you can see them)
		var n: Node3D = h["node"]
		if n.visible:
			for s in h["sails"]:
				(s as Node3D).rotation.z += delta * 0.6
	_bob_pins()
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var eye: Vector3 = main.cam.global_position if main.cam else main.player.position
	var cull := float(data.get("cull", 150.0))
	var dark := clampf(1.0 - Game.daylight(), 0.0, 1.0)
	for h in hamlets:
		var n: Node3D = h["node"]
		for l in h.get("lights", []): # lanterns and fires: brighter as the light goes
			if is_instance_valid(l):
				(l as OmniLight3D).light_energy = lerpf(float(l.get_meta("day_energy", 0.0)), float(l.get_meta("night_energy", 1.0)), dark)
		var near_me := Vector2(n.global_position.x - main.player.position.x, n.global_position.z - main.player.position.z).length()
		var near_eye := Vector2(n.global_position.x - eye.x, n.global_position.z - eye.z).length()
		n.visible = minf(near_me, near_eye) < cull or main.god.active
		var k = h["keeper"]
		if k != null and is_instance_valid(k):
			k.visible = n.visible and not main.story.is_playing()
			k.process_mode = Node.PROCESS_MODE_INHERIT if k.visible else Node.PROCESS_MODE_DISABLED
			var spot := _keeper_spot(h)
			if k.home.distance_to(spot) > 0.5: # the hamlet was moved in the world editor
				k.home = spot
				k.position = spot
		if on and not is_found(str(h["cfg"]["id"])) and not main.title_on:
			var r := float(h["cfg"].get("discover", 18.0))
			var dog_near: bool = main.dog != null and main.dog.controlled and Vector2(n.global_position.x - main.dog.position.x, n.global_position.z - main.dog.position.z).length() < r
			if near_me < r or dog_near:
				discover(str(h["cfg"]["id"]))


## She has found hamlet `id`.
func discover(id: String) -> void:
	if is_found(id):
		return
	var f := found().duplicate()
	f[id] = Game.day
	Game.flags["hamlets"] = f
	var c := cfg_of(id)
	_found_toast = "Discovered %s: %s." % [str(c.get("name", id)), str(c.get("blurb", "a hidden hamlet"))]
	main.hud.show_toast(_found_toast)
	main.hud.click("journal")


# --- the keepers' menus and pins ---------------------------------------------------------------

## Whether keeper `k` wants a sweater now: not bought one today, not given up haggling.
func wants(k) -> bool:
	if not on:
		return false
	var a := SweaterSale.asked(k.vid)
	var haggling := a.is_empty() or (bool(a.get("yes", false)) and int(a.get("tries", 0)) < int(SweaterSale.cfg("tries", 3)))
	return not SweaterSale.bought_today(k.vid) and haggling


func actions(k) -> Array:
	var acts := [{"id": "talk", "label": "Talk", "enabled": true}]
	if wants(k):
		var ok := SweaterSale.has_for(k.vid)
		var row := {"id": "sale", "label": ("Show them a sweater  (pays up to x%.1f)" % float(SweaterSale.themed.get(k.vid, {}).get("mult", 1.0))) if ok else "Wants %s: show them another  (they'd pay less)" % SweaterSale.wanted_text(k.vid), "enabled": Game.count("sweater") > 0}
		row["group"] = SweaterSale.GROUP
		acts.append(row)
	elif SweaterSale.bought_today(k.vid):
		acts.append({"id": "noop", "label": "Bought one today: come back tomorrow", "enabled": false})
	return acts


func action(k, id: String) -> void:
	k.face_point(main.player.position, 6.0)
	discover(k.hamlet_id)
	match id:
		"talk":
			var kc: Dictionary = cfg_of(k.hamlet_id).get("keeper", {})
			var key: String = "hamlet_greeted_" + k.hamlet_id
			var text := ""
			if Game.flag(key) != true:
				Game.set_flag(key, true)
				text = str(kc.get("greet", "Welcome."))
			else:
				var lines: Array = kc.get("lines", ["..."])
				k.talks += 1
				text = str(lines[(Game.day + k.talks) % maxi(1, lines.size())])
				if wants(k):
					text += "  Today I'm after %s." % SweaterSale.wanted_text(k.vid)
			main.hud.show_dialogue(k.title, -1, text, k.vid)
		"sale":
			if Game.count("sweater") == 0:
				return
			if SweaterSale.asked(k.vid).is_empty():
				SweaterSale._note(k.vid, {"yes": true, "tries": 0}) # they want one: no need to ask
			main.sale.open(k)


func _bob_pins() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for k in keepers:
		if not is_instance_valid(k):
			continue
		var g := k.get_node_or_null("SweaterPin") as Sprite3D
		var want: bool = k.visible and not main.title_on and not main.story.is_playing() and wants(k)
		if want and g == null:
			g = _make_pin(k)
		if g == null:
			continue
		g.visible = want
		if want:
			g.position.y = float(g.get_meta("y")) + 0.07 * absf(sin(t * 3.2 + k.position.x))


func _make_pin(k) -> Sprite3D:
	if _pin_tex == null:
		_pin_tex = ImageTexture.create_from_image(Townsfolk.pin_image())
	var g := Sprite3D.new()
	g.name = "SweaterPin"
	g.texture = _pin_tex
	g.pixel_size = 0.4 / Townsfolk.PIN_PX
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false
	g.no_depth_test = true
	g.transparent = true
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base: float = (k.tag.position.y if k.tag else 2.0) + 0.55
	g.set_meta("y", base)
	g.position.y = base
	k.add_child(g)
	return g


## A hamlet's keeper: a villager body with its own menu (main._actions_for asks ke_actions first).
class Keeper extends "res://scripts/villager.gd":
	var hamlets # hamlets.gd
	var hamlet_id := ""
	var talks := 0

	func ke_actions() -> Array:
		return hamlets.actions(self)

	func ke_action(id: String) -> void:
		hamlets.action(self, id)
