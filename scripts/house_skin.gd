extends RefCounted
## The outside of Nora's house and Rosewood Cottage: lime plaster, the oak of the timber frame
## (its grain up the posts, `timber`, or along the rails and lintels, `timber_h`), fieldstone
## for the footing and the flags round it, and cedar shingles on the roof (`shingles`, and its
## mirror `shingles_r` for the slope that runs down the other way). The maps come from art/world_assets/house_exterior
## (assets/textures/house) and are projected onto each box from three sides in its own space, so
## a box of any size keeps the same scale and the house can be moved without them swimming.

## metres one tile of each map covers (SIZES in the build script)
const TILE := {"plaster": 2.0, "timber": 1.0, "timber_h": 1.0, "stone": 2.0, "shingles": 1.0, "shingles_r": 1.0}
## a tint over the map, so the walls keep the colour the house always had
const TINT := {"plaster": Color(1.0, 1.0, 1.0), "timber": Color(0.95, 0.95, 0.95), "timber_h": Color(0.95, 0.95, 0.95), "stone": Color(1.0, 1.0, 1.0), "shingles": Color.WHITE, "shingles_r": Color.WHITE}
const ROUGH := {"plaster": 0.92, "timber": 0.8, "timber_h": 0.8, "stone": 0.9, "shingles": 0.88, "shingles_r": 0.88}
## a lighter oak for the door leaf and the window sills (Catalog.WOOD rather than WOOD_DARK)
const LIGHT_OAK := Color(1.35, 1.3, 1.25)
## weathered dark oak for the roof's ridge cap and fascia boards
const DARK_OAK := Color(0.72, 0.6, 0.56)

static var _mats := {}


static func material(kind: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := kind + tint.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		var file := kind
		m.albedo_texture = load("res://assets/textures/house/%s.png" % file)
		m.albedo_color = TINT[kind] * tint
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/house/%s_n.png" % file)
		m.normal_scale = 1.0
		m.roughness = ROUGH[kind]
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE / float(TILE[kind])
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mats[key] = m
	return _mats[key]


## Dresses a box (from Catalog.box) in one of the maps and hands it back.
static func on(mi: MeshInstance3D, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	mi.material_override = material(kind, tint)
	mi.add_to_group("house_skin")
	return mi


## The oak for a box: its grain runs along the box's longest side.
static func oak(mi: MeshInstance3D, tint := Color.WHITE) -> MeshInstance3D:
	var s := (mi.mesh as BoxMesh).size if mi.mesh is BoxMesh else Vector3.ONE
	return on(mi, "timber" if s.y >= maxf(s.x, s.z) else "timber_h", tint)
