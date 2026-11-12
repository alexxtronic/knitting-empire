extends RefCounted
## Wall boards and floor planks, laid board by board from two atlases of five boards each
## (assets/textures/planks, made by art/world_assets/planks/build.py). Every board takes one of the
## five grains at random, and half of them are mirrored or turned end for end, so no two stretches
## of wall or floor look the same. One mesh and one draw call per wall or floor.

const BOARD_W := 0.3
const VARIANTS := 5
const LENGTH := {"wall": 2.6, "floor": 2.4} # what one board in the atlas covers, in metres
const TRIM := Color(0.74, 0.61, 0.45) # rails and skirting over the wall boards
## Every building has its own shade of floor: the same five oak boards, stained. "house" is Alex's
## reference a little darker, as he asked (the game's warm sunlight lifts the oak well above its
## texture, so even that one is tinted down).
const SHADES := {
	"house": Color(0.87, 0.79, 0.8), # golden oak
	"cottage": Color(1.0, 0.93, 0.86), # pale honey
	"shop": Color(0.6, 0.5, 0.48), # walnut
	"bakery": Color(0.78, 0.56, 0.5), # cherry
	"office": Color(0.66, 0.66, 0.7), # grey driftwood
	"homegoods": Color(0.76, 0.7, 0.52), # smoked ash
	"barn": Color(0.68, 0.6, 0.55), # weathered brown
}

static var _mats := {}


static func material(kind: String, shade := "") -> StandardMaterial3D:
	var key := kind + "/" + shade
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/planks/%s_planks.png" % kind)
		m.albedo_color = SHADES.get(shade, Color.WHITE)
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/planks/%s_planks_n.png" % kind)
		m.normal_scale = 0.8
		m.roughness = 0.78
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mats[key] = m
	return _mats[key]


## Lays boards over a flat rectangle and returns the mesh, added under `parent`.
## The rectangle starts at `origin`; `across` is the way the boards are counted (one every BOARD_W)
## and `along` the way they run; `size` is its extent (across, along); `normal` is the side it
## faces. Wall boards are whole, from `along` = 0; floor boards are LENGTH long with their ends
## staggered from row to row. `holes` (Rect2 in across/along metres) are left open, for windows.
## `shade` is the building's stain (SHADES); none leaves the boards as they are.
static func lay(parent: Node3D, kind: String, origin: Vector3, across: Vector3, along: Vector3, size: Vector2, normal: Vector3, holes: Array = [], rng_seed := 1, shade := "") -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var piece: float = LENGTH[kind]
	var staggered := kind == "floor"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(size.x / BOARD_W - 0.001))
	var first := (size.x - n * BOARD_W) * 0.5 # the same sliver of a board at both ends
	var flip_winding := across.cross(along).dot(normal) > 0.0
	var boards := 0
	for b in n:
		var a0 := first + b * BOARD_W
		var pos := -rng.randf_range(0.0, piece) if staggered else 0.0
		while pos < size.y:
			var variant := rng.randi_range(0, VARIANTS - 1)
			var flip_u := rng.randf() < 0.5
			var flip_v := staggered and rng.randf() < 0.5
			var rects: Array = [Rect2(maxf(a0, 0.0), maxf(pos, 0.0), minf(a0 + BOARD_W, size.x) - maxf(a0, 0.0), minf(pos + piece, size.y) - maxf(pos, 0.0))]
			for h in holes:
				rects = _cut(rects, h)
			for r in rects:
				var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
				var order := [0, 2, 1, 0, 3, 2] if flip_winding else [0, 1, 2, 0, 2, 3]
				for i in order:
					var c: Vector2 = corners[i]
					var fu := (c.x - a0) / BOARD_W
					var fv := (c.y - pos) / piece
					st.set_normal(normal)
					st.set_uv(Vector2((variant + (1.0 - fu if flip_u else fu)) / VARIANTS, fv if flip_v else 1.0 - fv))
					st.add_vertex(origin + across * c.x + along * c.y)
			boards += 1
			pos += piece
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "planks_" + kind
	mi.mesh = st.commit()
	mi.material_override = material(kind, shade)
	mi.set_meta("shade", shade)
	mi.set_meta("boards", boards)
	mi.add_to_group("planks_" + kind)
	parent.add_child(mi)
	return mi


## The parts of `rects` that `hole` leaves.
static func _cut(rects: Array, hole: Rect2) -> Array:
	var out: Array = []
	for r in rects:
		if not r.intersects(hole):
			out.append(r)
			continue
		var x0 := maxf(r.position.x, hole.position.x)
		var x1 := minf(r.end.x, hole.end.x)
		if hole.position.x > r.position.x:
			out.append(Rect2(r.position.x, r.position.y, hole.position.x - r.position.x, r.size.y))
		if hole.end.x < r.end.x:
			out.append(Rect2(hole.end.x, r.position.y, r.end.x - hole.end.x, r.size.y))
		if hole.position.y > r.position.y:
			out.append(Rect2(x0, r.position.y, x1 - x0, hole.position.y - r.position.y))
		if hole.end.y < r.end.y:
			out.append(Rect2(x0, hole.end.y, x1 - x0, r.end.y - hole.end.y))
	return out
