extends Node3D
## Real grass: a ground shader (shaders/ground.gdshader) for soil and grass colour, and tens of
## thousands of GPU-instanced blades (shaders/grass_blade.gdshader) that sway in the wind and
## bend away from Nora. Grass doesn't grow on paths, under buildings, in the vegetable beds or
## the pond: a low-res mask marks bare earth, shared by the ground colour and blade placement.
## main.gd builds it once, rebuilds it when the house grows, and feeds it weather and seasons.

const REGION := Rect2(-14.0, -28.0, 92.0, 48.0) # where blades grow: the farm, the road and town
const PX_PER_M := 2.0
const CHUNK := 8.0
const DENSITY := 34.0 # blades per square metre on full grass
const VIEW_RANGE := 46.0 # chunks further than this from the camera aren't drawn

var ground_mat: ShaderMaterial
var blade_mat: ShaderMaterial
var mask_img: Image
var _ground: MeshInstance3D
var _chunks: Array[MultiMeshInstance3D] = []
var _blade_mesh: ArrayMesh
var blade_count := 0
var _frac := 1.0 # share of blades drawn (graphics setting)
var _range := VIEW_RANGE


func _ready() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = preload("res://shaders/ground.gdshader")
	blade_mat = ShaderMaterial.new()
	blade_mat.shader = preload("res://shaders/grass_blade.gdshader")
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(180, 180)
	_ground.mesh = pm
	_ground.material_override = ground_mat
	_ground.position = Vector3(10, -0.01, -5)
	add_child(_ground)
	_blade_mesh = _make_blade()


## Bare-earth areas: `dirt` rects (paths, beds: worn earth, wide soft edges), `clear` rects and
## `circles` (Vector3 x, z, radius) where nothing grows (buildings, the pond).
func build(dirt: Array, clear: Array, circles: Array) -> void:
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	_make_mask(dirt, clear, circles)
	_plant()


func _make_mask(dirt: Array, clear: Array, circles: Array) -> void:
	var w := int(REGION.size.x * PX_PER_M)
	var h := int(REGION.size.y * PX_PER_M)
	mask_img = Image.create(w, h, false, Image.FORMAT_L8)
	mask_img.fill(Color(1, 1, 1))
	for r in dirt + clear:
		var rr: Rect2 = r
		var px := Rect2i(Vector2i(((rr.position - REGION.position) * PX_PER_M).floor()), Vector2i((rr.size * PX_PER_M).ceil()))
		mask_img.fill_rect(px, Color(0, 0, 0))
	for c in circles:
		var cv: Vector3 = c
		var cx := (cv.x - REGION.position.x) * PX_PER_M
		var cz := (cv.y - REGION.position.y) * PX_PER_M
		var rad := cv.z * PX_PER_M
		for y in range(int(cz - rad) - 1, int(cz + rad) + 2):
			for x in range(int(cx - rad) - 1, int(cx + rad) + 2):
				if x >= 0 and y >= 0 and x < w and y < h and Vector2(x + 0.5 - cx, y + 0.5 - cz).length() <= rad:
					mask_img.set_pixel(x, y, Color(0, 0, 0))
	# soften the edges: shrink and grow back
	var soft := mask_img.duplicate() as Image
	soft.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
	soft.resize(w, h, Image.INTERPOLATE_CUBIC)
	mask_img = soft
	ground_mat.set_shader_parameter("mask", ImageTexture.create_from_image(mask_img))
	ground_mat.set_shader_parameter("mask_rect", Vector4(REGION.position.x, REGION.position.y, REGION.size.x, REGION.size.y))


## Grass amount at a world point, 0..1 (1 outside the region).
func grass_at(x: float, z: float) -> float:
	var px := int((x - REGION.position.x) * PX_PER_M)
	var pz := int((z - REGION.position.y) * PX_PER_M)
	if px < 0 or pz < 0 or px >= mask_img.get_width() or pz >= mask_img.get_height():
		return 1.0
	return mask_img.get_pixel(px, pz).r


func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	blade_count = 0
	var nx := ceili(REGION.size.x / CHUNK)
	var nz := ceili(REGION.size.y / CHUNK)
	for cz in nz:
		for cx in nx:
			var x0 := REGION.position.x + cx * CHUNK
			var z0 := REGION.position.y + cz * CHUNK
			var buf := PackedFloat32Array()
			var n := 0
			var tries := int(CHUNK * CHUNK * DENSITY)
			buf.resize(tries * 16)
			for i in tries:
				var x := x0 + rng.randf() * CHUNK
				var z := z0 + rng.randf() * CHUNK
				var g := grass_at(x, z)
				if g < 0.55 or rng.randf() > (g - 0.45) * 1.8:
					continue
				# clumps: some patches grow taller
				var tall := 0.5 + 0.5 * sin(x * 0.7 + sin(z * 0.45) * 2.0) * cos(z * 0.6)
				var height := rng.randf_range(0.12, 0.24) + tall * 0.14
				height *= clampf((g - 0.5) * 2.5, 0.35, 1.0) # shorter at the edges of paths
				var yaw := rng.randf() * TAU
				var c := cos(yaw)
				var s := sin(yaw)
				var o := n * 16
				# Transform3D rows: basis x row, origin x; basis y row, origin y; basis z row, origin z
				buf[o + 0] = c; buf[o + 1] = 0.0; buf[o + 2] = s; buf[o + 3] = x
				buf[o + 4] = 0.0; buf[o + 5] = 1.0; buf[o + 6] = 0.0; buf[o + 7] = 0.0
				buf[o + 8] = -s; buf[o + 9] = 0.0; buf[o + 10] = c; buf[o + 11] = z
				buf[o + 12] = height; buf[o + 13] = rng.randf(); buf[o + 14] = 0.0; buf[o + 15] = 0.0
				n += 1
			if n == 0:
				continue
			buf.resize(n * 16)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _blade_mesh
			mm.instance_count = n
			mm.buffer = buf
			mm.custom_aabb = AABB(Vector3(x0 - 0.5, -0.1, z0 - 0.5), Vector3(CHUNK + 1.0, 0.8, CHUNK + 1.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = blade_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mm.visible_instance_count = _visible(n)
			mmi.visibility_range_end = _range
			mmi.visibility_range_end_margin = 6.0
			add_child(mmi)
			_chunks.append(mmi)
			blade_count += n


## A blade 1 m tall (the shader scales it): a tapering, slightly curved strip, UV.y 0 → 1 root → tip.
func _make_blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[0.0, 0.019, 0.0], [0.35, 0.016, 0.03], [0.68, 0.011, 0.09], [1.0, 0.0, 0.18]]
	var verts := []
	for r in rows:
		var y: float = r[0]
		var w: float = r[1]
		var lean: float = r[2]
		verts.append([Vector3(-w, y, lean), Vector2(0.0, y)])
		verts.append([Vector3(w, y, lean), Vector2(1.0, y)])
	var tri := func(a: int, b: int, c: int):
		for i in [a, b, c]:
			st.set_normal(Vector3(0, 0.3, -1).normalized())
			st.set_uv(verts[i][1])
			st.add_vertex(verts[i][0])
	for i in 3:
		var a := i * 2
		tri.call(a, a + 1, a + 2)
		if i < 2:
			tri.call(a + 1, a + 3, a + 2)
	return st.commit()


## Weather and season, from main.gd: rain (0..1), how dry the season is (0 spring .. 1 winter).
## Graphics setting: draw this share of the blades (they're planted in random order, so the
## first N are an even thinning) out to this distance from the camera.
func set_quality(frac: float, view_range: float) -> void:
	_frac = clampf(frac, 0.05, 1.0)
	_range = view_range
	for c in _chunks:
		c.multimesh.visible_instance_count = _visible(c.multimesh.instance_count)
		c.visibility_range_end = _range


func drawn_blades() -> int:
	var n := 0
	for c in _chunks:
		n += c.multimesh.visible_instance_count if c.multimesh.visible_instance_count >= 0 else c.multimesh.instance_count
	return n


func _visible(n: int) -> int:
	return -1 if _frac >= 0.999 else maxi(1, int(n * _frac))


func set_conditions(rain: float, season_dry: float) -> void:
	for m in [ground_mat, blade_mat]:
		m.set_shader_parameter("season_dry", season_dry)
		m.set_shader_parameter("wet", rain)
	blade_mat.set_shader_parameter("wind", 0.16 + rain * 0.2)


## Who the grass bends away from (Nora).
func set_pusher(p: Vector3) -> void:
	blade_mat.set_shader_parameter("pusher", p)
