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
var _chunk_at := {} # Vector2i(chunk x, chunk z) -> its MultiMeshInstance3D
var _blade_mesh: ArrayMesh
var blade_count := 0
var _frac := 1.0 # share of blades drawn (graphics setting)
var _range := VIEW_RANGE
## Far grass is thinned: every blade out to THIN_NEAR metres from the camera, then fewer and a
## little wider toward the end of the range, down to THIN_KEEP of them, so the turf looks as full.
## A blade 30 m off is a pixel wide, and drawing tens of thousands of them was 6 to 10 ms a frame
## on a MacBook Air (--only=perf). The shader widens each blade to match (grass_blade.gdshader).
const THIN_NEAR := 16.0
var thin_keep := 0.4 # share of blades kept at the end of the range (1: no thinning)
var _cam := Vector3(INF, 0, INF) # where the camera was when the chunks were last thinned


func _ready() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = preload("res://shaders/ground.gdshader")
	blade_mat = ShaderMaterial.new()
	blade_mat.shader = preload("res://shaders/grass_blade.gdshader")
	blade_mat.set_shader_parameter("fade_end", VIEW_RANGE)
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	# out past every land (scripts/regions.gd) to the horizon, and south only as far as the beach,
	# where the sand runs down under the sea
	pm.size = Vector2(720, 395)
	_ground.mesh = pm
	_ground.material_override = ground_mat
	_ground.position = Vector3(25, -0.01, 55.0 - 197.5)
	add_child(_ground)
	_blade_mesh = _make_blade()
	blade_mat.set_shader_parameter("thin_near", THIN_NEAR)
	blade_mat.set_shader_parameter("thin_keep", thin_keep)


## Bare-earth areas: `dirt` rects (paths, beds: worn earth, wide soft edges), `clear` rects and
## `circles` (Vector3 x, z, radius) where nothing grows (buildings, the pond). `roads` is god
## mode's painted road map (an image covering REGION; any colour = a road, so no grass there).
func build(dirt: Array, clear: Array, circles: Array, roads: Image = null) -> void:
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	_chunk_at.clear()
	_make_mask(dirt, clear, circles, roads)
	_plant()


## The same as build(), but only redraws the ground (the blades stay where they are). God mode
## calls this while a road is being painted, then replant() when the stroke ends.
func remask(dirt: Array, clear: Array, circles: Array, roads: Image = null) -> void:
	_make_mask(dirt, clear, circles, roads)


func _make_mask(dirt: Array, clear: Array, circles: Array, roads: Image = null) -> void:
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
	if roads != null:
		var small := roads.duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		for y in h:
			for x in w:
				var c := small.get_pixel(x, y)
				if maxf(c.r, maxf(c.g, c.b)) > 0.4:
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
	var nx := ceili(REGION.size.x / CHUNK)
	var nz := ceili(REGION.size.y / CHUNK)
	for cz in nz:
		for cx in nx:
			_plant_chunk(cx, cz)
	_count_blades()


## Plants the blades of one CHUNK-sized square again (after the mask changed under it).
func _plant_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if _chunk_at.has(key):
		var old: MultiMeshInstance3D = _chunk_at[key]
		_chunks.erase(old)
		_chunk_at.erase(key)
		old.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026 + cx * 7919 + cz * 104729 # the same blades in a square every time
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
		return
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
	mm.visible_instance_count = _visible(n, _keep_at(mmi_centre_dist(mm)))
	mmi.visibility_range_end = _range
	mmi.visibility_range_end_margin = 6.0
	add_child(mmi)
	_chunks.append(mmi)
	_chunk_at[key] = mmi


func _count_blades() -> void:
	blade_count = 0
	for c in _chunks:
		blade_count += c.multimesh.instance_count


## Plants the blades again in every square that touches `area` (x, z, width, depth in metres).
func replant(area: Rect2) -> void:
	var a := area.grow(1.5).intersection(REGION)
	if a.size.x <= 0.0 or a.size.y <= 0.0:
		return
	var c0 := Vector2i(((a.position - REGION.position) / CHUNK).floor())
	var c1 := Vector2i(((a.end - REGION.position) / CHUNK).floor())
	var nx := ceili(REGION.size.x / CHUNK)
	var nz := ceili(REGION.size.y / CHUNK)
	for cz in range(c0.y, mini(c1.y, nz - 1) + 1):
		for cx in range(c0.x, mini(c1.x, nx - 1) + 1):
			_plant_chunk(cx, cz)
	_count_blades()


## A blade 1 m tall (the shader scales it): a tapering, slightly curved strip, UV.y 0 → 1 root → tip.
func _make_blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[0.0, 0.023, 0.0], [0.35, 0.019, 0.03], [0.68, 0.012, 0.09], [1.0, 0.0, 0.18]]
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
func set_quality(frac: float, view_range: float, keep_far := 0.4) -> void:
	_frac = clampf(frac, 0.05, 1.0)
	_range = view_range
	thin_keep = clampf(keep_far, 0.05, 1.0)
	blade_mat.set_shader_parameter("fade_end", _range)
	blade_mat.set_shader_parameter("thin_keep", thin_keep)
	for c in _chunks:
		c.visibility_range_end = _range
	_thin()


## Every frame from main.gd: thins the chunks again once the camera has moved a metre.
func follow(cam_pos: Vector3) -> void:
	if cam_pos.distance_to(_cam) < 1.0:
		return
	_cam = cam_pos
	_thin()


func _thin() -> void:
	for c in _chunks:
		c.multimesh.visible_instance_count = _visible(c.multimesh.instance_count, _keep_at(mmi_centre_dist(c.multimesh)))


func mmi_centre_dist(mm: MultiMesh) -> float:
	if not is_finite(_cam.x):
		return 0.0
	return mm.custom_aabb.get_center().distance_to(_cam)


## The share of blades drawn at distance d from the camera (the shader's keep() is the same curve).
func _keep_at(d: float) -> float:
	# a chunk is 8 m across: count it by its nearest blades so the shader never widens a blade that
	# the chunk still draws at full density
	var near := maxf(d - CHUNK * 0.7, 0.0)
	return lerpf(1.0, thin_keep, smoothstep(THIN_NEAR, _range, near))


func drawn_blades() -> int:
	var n := 0
	for c in _chunks:
		n += c.multimesh.visible_instance_count if c.multimesh.visible_instance_count >= 0 else c.multimesh.instance_count
	return n


func _visible(n: int, keep := 1.0) -> int:
	var f := _frac * keep
	return -1 if f >= 0.999 else maxi(1, int(n * f))


func set_conditions(rain: float, season_dry: float) -> void:
	for m in [ground_mat, blade_mat]:
		m.set_shader_parameter("season_dry", season_dry)
		m.set_shader_parameter("wet", rain)
	blade_mat.set_shader_parameter("wind", 0.16 + rain * 0.2)


## Who the grass bends away from (Nora).
func set_pusher(p: Vector3) -> void:
	blade_mat.set_shader_parameter("pusher", p)
