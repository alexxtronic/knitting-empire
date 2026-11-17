extends RefCounted
## The town's buildings and the farm's barn wear the same hand-made textures as Nora's house
## (Alex, 2026-11-16: "all buildings in the game should have similar realistic textures to her
## main house"). When a building model loads (Catalog.model), each surface is matched by its
## material's name to one of the maps in assets/textures/house (art/world_assets/house_exterior):
## plaster, brick, board siding, oak beams, fieldstone, painted wood for frames and trim, and clay
## tiles or cedar shingles on the roofs (shaders/roof_tiles.gdshader). Each keeps the building's
## own colour: the map is tinted so that, on average, it comes out the colour the surface had.
## Doors, awnings, signs, floors, rooms and small props keep their own materials.

const DIR := "res://assets/textures/house/"
## The photo-scanned wood (Alex, 2026-11-17: "better wood textures realistic throughout cafe"):
## kinds named wood_* read assets/textures/wood/<name>.jpg and <name>_n.png, made from CC0 Poly Haven
## scans by art/world_assets/cafe_wood/build.py. Each tile is the scan's real size in metres.
const WOOD_DIR := "res://assets/textures/wood/"
const TILE := {"plaster": 2.0, "brick": 2.0, "boards": 2.0, "timber": 1.0, "stone": 2.0, "paintwood": 1.0, "tiles": 1.0, "shingles": 1.0,
	"wood_floor": 1.7, "wood_boards": 1.5, "wood_oak": 1.83, "wood_walnut": 1.5}
const ROUGH := {"plaster": 0.92, "brick": 0.9, "boards": 0.85, "timber": 0.8, "stone": 0.9, "paintwood": 0.7, "tiles": 0.82, "shingles": 0.88,
	"wood_floor": 0.62, "wood_boards": 0.78, "wood_oak": 0.55, "wood_walnut": 0.5}
## how strongly each map's relief shows: beams and painted trim are seen across their grain as
## often as along it here, so theirs is kept low
const RELIEF := {"plaster": 1.0, "brick": 1.0, "boards": 0.8, "timber": 0.45, "stone": 1.0, "paintwood": 0.3,
	"wood_floor": 0.7, "wood_boards": 0.8, "wood_oak": 0.35, "wood_walnut": 0.35}
const ROOF_SHADER := preload("res://shaders/roof_tiles.gdshader")

static var _avg := {} # texture path -> its average colour
static var _mats := {}


## Which map a building surface takes, from its material's name (and its own texture's name):
## "" leaves it as it is.
static func kind_for(mname: String, tex_name: String) -> String:
	var n := mname.to_lower()
	var t := tex_name.to_lower()
	# the Cappuccino Cafe's boards inside (walls, ceilings, the loft), its beams, stairs and rails
	if n == "cafe_lining":
		return "wood_boards"
	if n == "cafe_wood":
		return "wood_walnut"
	for skip in ["door", "awning", "floor", "interior", "lining", "paving", "cobble", "glass", "glow", "plaque", "chalk", "flag", "sign", "straw", "sack", "water", "gold", "brass", "iron", "bulb", "leaf", "bloom", "soil", "pot", "lavender", "plaid", "mat", "yarn", "wicker", "loaf", "pretzel", "paper", "postbox", "needle", "handle", "navy", "dark"]:
		if n.contains(skip):
			return ""
	if n.contains("shake"):
		return "shingles"
	if n.contains("roof"):
		return "tiles"
	if n.contains("brick") or t.contains("brick"):
		return "brick"
	if n.contains("stone"):
		return "stone"
	if n.contains("wall"):
		return "plaster"
	if n.contains("siding") or n.contains("boards") or n.contains("panel") or n.contains("stall") or n.contains("redwood"):
		return "boards"
	if n.contains("timber") or n.contains("beam") or n.contains("wood") or (n.contains("trim") and t != ""):
		return "timber"
	if n.contains("frame") or n.contains("trim") or n.contains("column") or n.contains("muntin"):
		return "paintwood"
	return ""


## Gives every surface of a building model (Catalog.model's instance) its textured material.
## Returns how many surfaces it changed.
static func dress(inst: Node3D) -> int:
	var changed := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			if m.get_surface_override_material(i) != null:
				continue # Catalog.model has already given it one (the window glass, wool)
			var old := m.mesh.surface_get_material(i) as BaseMaterial3D
			if old == null:
				continue
			var tex_name := old.albedo_texture.resource_path.get_file() if old.albedo_texture else ""
			var kind := kind_for(old.resource_name, tex_name)
			if kind == "":
				continue
			m.set_surface_override_material(i, material(kind, colour_of(old), old))
			changed += 1
	return changed


## Which photo wood a furnishing's surface takes, from its material's name: "" leaves it.
static func wood_for(mname: String) -> String:
	var n := mname.to_lower()
	if n.contains("walnut"):
		return "wood_walnut"
	if n.contains("oak") or n.ends_with("_wood"):
		return "wood_oak"
	return ""


## Gives a piece of furniture's wooden surfaces the photo wood, each keeping its own colour.
## Returns how many surfaces it changed.
static func dress_wood(inst: Node3D) -> int:
	var changed := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			if m.get_surface_override_material(i) != null:
				continue
			var old := m.mesh.surface_get_material(i) as BaseMaterial3D
			if old == null:
				continue
			var kind := wood_for(old.resource_name)
			if kind == "":
				continue
			m.set_surface_override_material(i, material(kind, colour_of(old), old))
			changed += 1
	return changed


## The colour a surface comes out on average: its albedo colour times its texture's average.
static func colour_of(m: BaseMaterial3D) -> Color:
	var c := m.albedo_color
	if m.albedo_texture:
		var a := average(m.albedo_texture)
		c = Color(c.r * a.r, c.g * a.g, c.b * a.b)
	return c


static func average(tex: Texture2D) -> Color:
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if not _avg.has(key):
		var img := tex.get_image()
		if img == null:
			_avg[key] = Color(0.7, 0.7, 0.7)
		else:
			if img.is_compressed():
				img.decompress()
			img.resize(16, 16, Image.INTERPOLATE_BILINEAR) # after its mipmaps, so this is a true mean
			var sum := Vector3.ZERO
			for y in 16:
				for x in 16:
					var p := img.get_pixel(x, y)
					sum += Vector3(p.r, p.g, p.b)
			sum /= 256.0
			_avg[key] = Color(sum.x, sum.y, sum.z)
	return _avg[key]


## The textured material for a kind, tinted so it averages `colour`; `old` lends its light bake.
static func material(kind: String, colour: Color, old: BaseMaterial3D = null) -> Material:
	var ao: Texture2D = old.ao_texture if old and old.ao_enabled else null
	## an arched dormer roof (kelib.arch_hood) carries its own UVs in metres, laid along the barrel
	var arched: bool = old != null and old.resource_name.to_lower().contains("arch")
	var key := "%s/%s/%s/%s" % [kind, colour.to_html(false), ao.resource_path if ao else "", arched]
	if _mats.has(key):
		return _mats[key]
	var wood := kind.begins_with("wood_")
	var base := WOOD_DIR + kind.substr(5) if wood else DIR + kind
	var albedo: Texture2D = load(base + (".jpg" if wood else ".png"))
	var a := average(albedo)
	var tint := Color(clampf(colour.r / maxf(a.r, 0.02), 0.15, 1.7), clampf(colour.g / maxf(a.g, 0.02), 0.15, 1.7), clampf(colour.b / maxf(a.b, 0.02), 0.15, 1.7))
	var out: Material
	if (kind == "tiles" or kind == "shingles") and not arched:
		var sm := ShaderMaterial.new()
		sm.shader = ROOF_SHADER
		sm.set_shader_parameter("tex", albedo)
		sm.set_shader_parameter("nrm", load(base + "_n.png"))
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("tile", TILE[kind])
		sm.set_shader_parameter("courses_down_u", kind == "shingles")
		sm.set_shader_parameter("rough", ROUGH[kind])
		if ao:
			sm.set_shader_parameter("ao_tex", ao)
			sm.set_shader_parameter("ao_amount", 1.0)
		out = sm
	else:
		var m := StandardMaterial3D.new()
		m.albedo_texture = albedo
		m.albedo_color = tint
		m.normal_enabled = true
		m.normal_texture = load(base + "_n.png")
		m.normal_scale = RELIEF.get(kind, 1.0)
		m.roughness = ROUGH[kind]
		m.uv1_scale = Vector3.ONE / float(TILE[kind])
		if not arched:
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_triplanar_sharpness = 4.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if ao:
			m.ao_enabled = true
			m.ao_texture = ao
			m.ao_on_uv2 = true
		out = m
	out.resource_name = "skin_" + kind
	_mats[key] = out
	return out
