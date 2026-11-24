extends Node3D
## Real grass: a ground shader (shaders/ground.gdshader) for soil and grass colour, and tens of
## thousands of GPU-instanced blades (shaders/grass_blade.gdshader) that sway in the wind and
## bend away from Nora. Grass doesn't grow on paths, under buildings, in the vegetable beds or
## the pond: a low-res mask marks bare earth, shared by the ground colour and blade placement.
## main.gd builds it once, rebuilds it when the house grows, and feeds it weather and seasons.
##
## Blades grow over the whole map (Alex, 2026-11-24: "more realistic, beautiful grass across the
## entire map"): REGION (the farm and the town) is planted once, as before, from the mask the ground
## shader shares; everywhere else in OUTER (the four lands, the woods between, Bretton Oaks) is
## planted in CHUNK squares as the camera comes near, on worker threads, from a whole-map mask
## (full_img) and god mode's road map, and dropped again once the camera is far off. Each land's
## blades take its own colour, height and density (data/regions.json "grass").

const REGION := Rect2(-14.0, -28.0, 92.0, 48.0) # where blades are planted up front: the farm, the road and town
const OUTER := Rect2(-96.0, -100.0, 240.0, 162.0) # Regions.BOUNDS, the whole walkable map: blades stream in here
const ROAD_RECT := Rect2(-96.0, -100.0, 240.0, 162.0) # GodMode.ROAD_RECT, what god mode's road map covers
const ROAD_PX := 8.0 # GodMode.ROAD_PX
var plant_reach := VIEW_RANGE + CHUNK + 2.0 # outer squares whose nearest corner is this close to the camera are planted (the level's range and a square)
const DROP_REACH := 100.0 # ... and freed again past this
const MAX_TASKS := 3 # outer squares planted at once on worker threads
## Low and Medium draw the streamed squares leaner (main.gd GRASS_OUTER_FRAC, GRASS_OUTER_REACH): this
## share of their blades, each widened to match, out to this share of the range. A blade costs what it
## covers on screen, and these lands had none before (2026-11-24, --only=perf --perfprobe).
var outer_frac := 1.0
var outer_reach := 1.0
const PX_PER_M := 2.0
const CHUNK := 8.0
const DENSITY := 34.0 # blades per square metre on full grass
const VIEW_RANGE := 46.0 # chunks further than this from the camera aren't drawn
const PATCH_PX := 4.0 # the baked patch texture's pixels per metre (_bake_patches)

var ground_mat: ShaderMaterial
var blade_mat: ShaderMaterial
var mask_img: Image
var _ground: MeshInstance3D
var _chunks: Array[MultiMeshInstance3D] = []
var _chunk_at := {} # Vector2i(chunk x, chunk z) -> its MultiMeshInstance3D
var _blade_mesh: ArrayMesh
## Every blade planted, the streamed squares round the camera too (it finishes planting those first).
var blade_count: int:
	get:
		settle()
		_count_blades()
		return _blade_count
var _blade_count := 0
var _frac := 1.0 # share of blades drawn (graphics setting)
var _range := VIEW_RANGE
## Far grass is thinned: every blade out to thin_near metres from the camera, then fewer and a
## little wider toward the end of the range, down to THIN_KEEP of them, so the turf looks as full.
## A blade 30 m off is a pixel wide, and drawing tens of thousands of them was 6 to 10 ms a frame
## on a MacBook Air (--only=perf). The shader widens each blade to match (grass_blade.gdshader).
var thin_near := 16.0
var thin_keep := 0.4 # share of blades kept at the end of the range (1: no thinning)
var _cam := Vector3(INF, 0, INF) # where the camera was when the chunks were last thinned

# the streamed squares outside REGION
var full_img: Image # grass amount 0..1 over OUTER at PX_PER_M, roads left out (they're road_img)
var road_img: Image # a copy of god mode's painted road map over ROAD_RECT (any colour is a road), or null: the threads read it
var _road_src: Image # god mode's own map, which it paints into
var lands: Array = [] # Dictionary per land: ground Rect2, fade, idx, density, height
var land_pools: Array = [] # Vector3 (x, z, radius): the swamp's pools
var lawns: Array = [] # Vector3 (x, z, radius): kept plain farm lawn though inside a land (Bretton Oaks in the meadows)
var shore_z := INF # no blades past here (the sea)
var _outer_at := {} # Vector2i -> MultiMeshInstance3D
var _tasks := {} # Vector2i -> WorkerThreadPool task id
var _done := {} # Vector2i -> [gen, PackedFloat32Array, n], filled by the worker threads
var _mutex := Mutex.new()
var _gen := 0 # bumped by build(): a square planted from an older mask is thrown away
var _stream_cam := Vector3(INF, 0, INF)
var _empty := {} # Vector2i -> true: outer squares that came out with no blades


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
	blade_mat.set_shader_parameter("thin_near", thin_near)
	blade_mat.set_shader_parameter("thin_keep", thin_keep)
	_bake_patches()


## The light and dark patches (grass_patches.gdshaderinc) cost each blade's vertices sixteen hashes;
## they depend only on where the blade stands, so draw them once over OUTER into a texture on the
## GPU (the CPU can't repeat the shader's sin hash exactly, and the blades must match the ground's
## patches, which keeps working them out itself). The blades read it once it has drawn.
var patch_vp: SubViewport

func _bake_patches() -> void:
	patch_vp = SubViewport.new()
	patch_vp.size = Vector2i(int(OUTER.size.x * PATCH_PX), int(OUTER.size.y * PATCH_PX))
	patch_vp.disable_3d = true
	patch_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(patch_vp.size)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/grass_patch_bake.gdshader")
	var r := Vector4(OUTER.position.x, OUTER.position.y, OUTER.size.x, OUTER.size.y)
	m.set_shader_parameter("rect", r)
	rect.material = m
	patch_vp.add_child(rect)
	add_child(patch_vp)
	blade_mat.set_shader_parameter("patch_tex", patch_vp.get_texture())
	blade_mat.set_shader_parameter("patch_rect", r)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	blade_mat.set_shader_parameter("patch_baked", true)


## Bare-earth areas: `dirt` rects (paths, beds: worn earth, wide soft edges), `clear` rects and
## `circles` (Vector3 x, z, radius) where nothing grows (buildings, the pond). `roads` is god
## mode's painted road map (an image covering REGION; any colour = a road, so no grass there).
## `full_roads` is the whole road map (god.road_img), for the squares outside REGION.
func build(dirt: Array, clear: Array, circles: Array, roads: Image = null, full_roads: Image = null) -> void:
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	_chunk_at.clear()
	_finish_tasks() # the threads read the masks: let them finish before they change
	_make_mask(dirt, clear, circles, roads)
	_make_full(dirt, clear, circles)
	_road_src = full_roads
	road_img = full_roads.duplicate() if full_roads != null else null
	_plant()
	_drop_outer()


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
		if r is PackedVector2Array:
			continue # Bretton Oaks' turned houses lie outside REGION
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


## Grass amount at a world point, 0..1.
func grass_at(x: float, z: float) -> float:
	var px := int((x - REGION.position.x) * PX_PER_M)
	var pz := int((z - REGION.position.y) * PX_PER_M)
	if px < 0 or pz < 0 or px >= mask_img.get_width() or pz >= mask_img.get_height():
		return _outer_amount(x, z).x
	return mask_img.get_pixel(px, pz).r


## The mask over the whole map, for the streamed squares: the same rects and circles as REGION's,
## the swamp's pools too, without the roads (those are read from road_img itself, blade by blade).
## All native image work, so a rebuild stays quick at this size.
func _make_full(dirt: Array, clear: Array, circles: Array) -> void:
	var w := int(OUTER.size.x * PX_PER_M)
	var h := int(OUTER.size.y * PX_PER_M)
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	for r in dirt + clear:
		if r is PackedVector2Array: # a turned rect (Bretton Oaks' houses)
			_fill_quad(img, r)
			continue
		var rr: Rect2 = r
		if rr.size.x > 4.0 and rr.size.y > 4.0 and absf(rr.size.x - rr.size.y) < 1.0 and not REGION.intersects(rr) and not r in dirt:
			continue # a big square out in the lands is a tree's crown on the walking grid: grass grows under it (pools come as circles)
		var px := Rect2i(Vector2i(((rr.position - OUTER.position) * PX_PER_M).floor()), Vector2i((rr.size * PX_PER_M).ceil()))
		img.fill_rect(px, Color(0, 0, 0))
	for c in circles + land_pools.map(func(p): return Vector3(p.x, p.y, p.z + 0.5)):
		var cv: Vector3 = c
		var cx := (cv.x - OUTER.position.x) * PX_PER_M
		var cz := (cv.y - OUTER.position.y) * PX_PER_M
		var rad := cv.z * PX_PER_M
		for y in range(maxi(int(cz - rad) - 1, 0), mini(int(cz + rad) + 2, h)):
			for x in range(maxi(int(cx - rad) - 1, 0), mini(int(cx + rad) + 2, w)):
				if Vector2(x + 0.5 - cx, y + 0.5 - cz).length() <= rad:
					img.set_pixel(x, y, Color(0, 0, 0))
	img.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_CUBIC)
	full_img = img


func _fill_quad(img: Image, quad: PackedVector2Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in quad:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(int((lo.y - OUTER.position.y) * PX_PER_M), 0), mini(int((hi.y - OUTER.position.y) * PX_PER_M) + 1, img.get_height())):
		for x in range(maxi(int((lo.x - OUTER.position.x) * PX_PER_M), 0), mini(int((hi.x - OUTER.position.x) * PX_PER_M) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(OUTER.position + Vector2(x + 0.5, y + 0.5) / PX_PER_M, quad):
				img.set_pixel(x, y, Color(0, 0, 0))


## The lands round the farm (regions.gd), from main.gd before build(): each land's ground rect and
## how its blades differ ("grass" in data/regions.json), its pools, and the shore.
func set_lands(defs: Dictionary, pools: Array, shore: float, lawn: Array = []) -> void:
	if not lands.is_empty():
		return # the lands don't change, and the threads read them
	lawns = lawn.duplicate()
	var tints: Array[Vector3] = [Vector3.ONE]
	var farm := Color(0.24, 0.38, 0.13).srgb_to_linear() # ground.gdshader's lush
	for id in defs:
		var d: Dictionary = defs[id]
		var g: Dictionary = d.get("grass", {})
		var a: Array = d["ground"]
		# the blades take the land's own ground colour: its colours' mean against the farm's grass
		var mean := Vector3.ZERO
		for c in d.get("colours", []):
			var lc := Color(str(c)).srgb_to_linear()
			mean += Vector3(lc.r, lc.g, lc.b)
		mean /= maxf(1.0, float(d.get("colours", []).size()))
		var t := Vector3(mean.x / farm.r, mean.y / farm.g, mean.z / farm.b)
		if g.has("tint"):
			var tc := Color(str(g["tint"]))
			t = Vector3(tc.r, tc.g, tc.b)
		t = Vector3.ONE.lerp(t.clamp(Vector3.ONE * 0.45, Vector3.ONE * 1.6), float(g.get("tint_share", 0.5)))
		tints.append(t)
		lands.append({"rect": Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])), "fade": 9.0, "idx": tints.size() - 1,
			"density": float(g.get("density", 1.0)), "height": float(g.get("height", 1.0)), "seeds": float(g.get("seed_heads", 0.0))})
	while tints.size() < 8:
		tints.append(Vector3.ONE)
	blade_mat.set_shader_parameter("land_tint", PackedVector3Array(tints))
	land_pools = pools.duplicate()
	shore_z = shore


## Grass outside REGION at a point: (amount 0..1, the land's index + how far into it 0..0.99,
## the land's height factor, its share of seed heads).
func _outer_amount(x: float, z: float) -> Vector4:
	if full_img == null or not OUTER.has_point(Vector2(x, z)) or z > shore_z - 1.5:
		return Vector4(0.0, 0.0, 1.0, 0.0)
	var g := full_img.get_pixel(clampi(int((x - OUTER.position.x) * PX_PER_M), 0, full_img.get_width() - 1),
		clampi(int((z - OUTER.position.y) * PX_PER_M), 0, full_img.get_height() - 1)).r
	if g < 0.5:
		return Vector4(g, 0.0, 1.0, 0.0)
	if road_img != null:
		var rx := int((x - ROAD_RECT.position.x) * ROAD_PX)
		var rz := int((z - ROAD_RECT.position.y) * ROAD_PX)
		if rx >= 0 and rz >= 0 and rx < road_img.get_width() and rz < road_img.get_height():
			var c := road_img.get_pixel(rx, rz)
			if maxf(c.r, maxf(c.g, c.b)) > 0.4:
				return Vector4(0.0, 0.0, 1.0, 0.0)
	var idx := 0.0
	var height := 1.0
	var seeds := 0.0
	for l in lands:
		var r: Rect2 = l["rect"]
		if not r.has_point(Vector2(x, z)):
			continue
		var e := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
		var k := smoothstep(0.0, float(l["fade"]), e)
		idx = float(l["idx"]) + k * 0.99 # the colour: the land's ground, lawns too
		for lw in lawns: # a lawn keeps the farm's short, even grass
			k *= smoothstep(lw.z - 6.0, lw.z, Vector2(x - lw.x, z - lw.y).length())
		g *= lerpf(1.0, float(l["density"]), k)
		height = lerpf(1.0, float(l["height"]), k)
		seeds = float(l["seeds"]) * k
		break
	return Vector4(g, idx, height, seeds)


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
	var x0 := REGION.position.x + cx * CHUNK
	var z0 := REGION.position.y + cz * CHUNK
	var res := _plant_buf(x0, z0, 2026 + cx * 7919 + cz * 104729, false)
	var mmi := _make_chunk(x0, z0, res[0], res[1])
	if mmi != null:
		_chunk_at[key] = mmi


## The blades of the square at (x0, z0): [the MultiMesh buffer, how many]. `outer`: a streamed
## square, which leaves REGION's blades to REGION and reads the whole-map mask. Runs on worker
## threads for the outer squares, so it touches only images and plain data.
func _plant_buf(x0: float, z0: float, seed: int, outer: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed # the same blades in a square every time
	var buf := PackedFloat32Array()
	var n := 0
	var tries := int(CHUNK * CHUNK * DENSITY)
	buf.resize(tries * 16)
	# blades grow in loose tufts: about half crowd round a tuft's heart, the rest stand between
	var tuft := Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK)
	var tuft_h := 1.0
	for i in tries:
		if i % 9 == 0:
			tuft = Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK)
			tuft_h = rng.randf_range(0.8, 1.25)
		var x: float
		var z: float
		var in_tuft := rng.randf() < 0.5
		if in_tuft:
			x = clampf(tuft.x + rng.randfn(0.0, 0.28), x0, x0 + CHUNK - 0.001)
			z = clampf(tuft.y + rng.randfn(0.0, 0.28), z0, z0 + CHUNK - 0.001)
		else:
			x = x0 + rng.randf() * CHUNK
			z = z0 + rng.randf() * CHUNK
		var land := 0.0
		var hmul := 1.0
		var seeds := 0.0
		var g: float
		if outer:
			if REGION.has_point(Vector2(x, z)):
				continue
			var o := _outer_amount(x, z)
			g = o.x
			land = o.y
			hmul = o.z
			seeds = o.w
		else:
			if not REGION.has_point(Vector2(x, z)):
				continue # the last column of squares runs past REGION: the streamed squares grow there
			g = grass_at(x, z)
		if g < 0.55 or rng.randf() > (g - 0.45) * 1.8:
			continue
		# clumps: some patches grow taller
		var tall := 0.5 + 0.5 * sin(x * 0.7 + sin(z * 0.45) * 2.0) * cos(z * 0.6)
		var height := rng.randf_range(0.12, 0.24) + tall * 0.14
		height *= clampf((g - 0.5) * 2.5, 0.35, 1.0) # shorter at the edges of paths
		height *= (tuft_h if in_tuft else 1.0) * hmul
		# a seed head: a taller stem gone to seed (the meadows), its tip pale; it rides in the land's fraction
		var seed_head := rng.randf() < seeds
		if seed_head:
			height *= 1.5
		var yaw := rng.randf() * TAU
		var c := cos(yaw)
		var s := sin(yaw)
		var o16 := n * 16
		# Transform3D rows: basis x row, origin x; basis y row, origin y; basis z row, origin z
		buf[o16 + 0] = c; buf[o16 + 1] = 0.0; buf[o16 + 2] = s; buf[o16 + 3] = x
		buf[o16 + 4] = 0.0; buf[o16 + 5] = 1.0; buf[o16 + 6] = 0.0; buf[o16 + 7] = 0.0
		buf[o16 + 8] = -s; buf[o16 + 9] = 0.0; buf[o16 + 10] = c; buf[o16 + 11] = z
		# custom: height, a random 0..1, the land (index + how far into it), 1 for a seed head
		buf[o16 + 12] = height; buf[o16 + 13] = rng.randf(); buf[o16 + 14] = land; buf[o16 + 15] = 1.0 if seed_head else 0.0
		n += 1
	buf.resize(n * 16)
	return [buf, n]


func _make_chunk(x0: float, z0: float, buf: PackedFloat32Array, n: int, outer := false) -> MultiMeshInstance3D:
	if n == 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _blade_mesh
	mm.instance_count = n
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(x0 - 0.5, -0.1, z0 - 0.5), Vector3(CHUNK + 1.0, 1.0, CHUNK + 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = blade_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if outer:
		mmi.set_meta("outer", true)
	mmi.visibility_range_end_margin = 6.0
	_thin_one(mmi)
	add_child(mmi)
	_chunks.append(mmi)
	return mmi


func _count_blades() -> void:
	_blade_count = 0
	for c in _chunks:
		_blade_count += c.multimesh.instance_count


## Plants the blades again in every square that touches `area` (x, z, width, depth in metres).
func replant(area: Rect2) -> void:
	_finish_tasks()
	if _road_src != null and not REGION.encloses(area): # god mode painted out here: the threads' copy of its map
		road_img = _road_src.duplicate()
	_replant_outer(area.grow(1.5))
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
	st.index() # 7 shared points rather than 15: the vertex shader runs once per point
	return st.commit()


func _outer_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - OUTER.position.x) / CHUNK), floori((z - OUTER.position.y) / CHUNK))


func _outer_rect(k: Vector2i) -> Rect2:
	return Rect2(OUTER.position.x + k.x * CHUNK, OUTER.position.y + k.y * CHUNK, CHUNK, CHUNK)


## The outer squares that should be planted round the camera, nearest first.
func _wanted(cam: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_finite(cam.x) or full_img == null:
		return out
	var c := Vector2(cam.x, cam.z)
	var k0 := _outer_key(c.x - plant_reach, c.y - plant_reach)
	var k1 := _outer_key(c.x + plant_reach, c.y + plant_reach)
	var nx := ceili(OUTER.size.x / CHUNK)
	var nz := ceili(OUTER.size.y / CHUNK)
	for kz in range(maxi(k0.y, 0), mini(k1.y, nz - 1) + 1):
		for kx in range(maxi(k0.x, 0), mini(k1.x, nx - 1) + 1):
			var r := _outer_rect(Vector2i(kx, kz))
			if REGION.encloses(r):
				continue
			var near := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
			if near.distance_to(c) <= plant_reach:
				out.append(Vector2i(kx, kz))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _outer_rect(a).get_center().distance_squared_to(c) < _outer_rect(b).get_center().distance_squared_to(c))
	return out


func _task(key: Vector2i, gen: int) -> void:
	var r := _outer_rect(key)
	var res := _plant_buf(r.position.x, r.position.y, 7331 + key.x * 7919 + key.y * 104729, true)
	_mutex.lock()
	_done[key] = [gen, res[0], res[1]]
	_mutex.unlock()


## Starts the squares the camera needs, takes in the ones the threads have finished and frees the far
## ones. `block`: plant everything the camera needs now (tests and settle()).
func _stream(block := false) -> void:
	# take in what the threads have planted
	for key in _tasks.keys():
		if block or WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	_mutex.lock()
	var done := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for key in done:
		var d: Array = done[key]
		if int(d[0]) != _gen:
			continue
		if _outer_at.has(key):
			_free_outer(key)
		var r := _outer_rect(key)
		var mmi := _make_chunk(r.position.x, r.position.y, d[1], int(d[2]), true)
		if mmi == null:
			_empty[key] = true
		else:
			_outer_at[key] = mmi
	var c := Vector2(_stream_cam.x, _stream_cam.z)
	if is_finite(c.x):
		for key in _outer_at.keys():
			if _outer_rect(key).get_center().distance_to(c) > DROP_REACH:
				_free_outer(key)
		for key in _empty.keys():
			if _outer_rect(key).get_center().distance_to(c) > DROP_REACH:
				_empty.erase(key)
	for key in _wanted(_stream_cam):
		if _outer_at.has(key) or _tasks.has(key) or _empty.has(key):
			continue
		if block:
			_task(key, _gen)
		elif _tasks.size() < MAX_TASKS:
			_tasks[key] = WorkerThreadPool.add_task(_task.bind(key, _gen), false, "grass")
		else:
			break
	if block and not _done.is_empty():
		_stream(false)


func _free_outer(key: Vector2i) -> void:
	var mmi: MultiMeshInstance3D = _outer_at[key]
	_outer_at.erase(key)
	_chunks.erase(mmi)
	mmi.queue_free()


## After build(): every streamed square is planted again from the new mask.
func _drop_outer() -> void:
	_gen += 1
	for key in _outer_at.keys():
		_free_outer(key)
	_empty.clear()
	_mutex.lock()
	_done.clear()
	_mutex.unlock()


func _replant_outer(area: Rect2) -> void:
	for key in _outer_at.keys() + _empty.keys():
		if _outer_rect(key).intersects(area):
			_empty.erase(key)
			if _outer_at.has(key):
				var r := _outer_rect(key)
				var res := _plant_buf(r.position.x, r.position.y, 7331 + key.x * 7919 + key.y * 104729, true)
				_free_outer(key)
				var mmi := _make_chunk(r.position.x, r.position.y, res[0], res[1], true)
				if mmi == null:
					_empty[key] = true
				else:
					_outer_at[key] = mmi


## Shows or hides the streamed squares (--only=perf's grass_outer probe).
func show_outer(on: bool) -> void:
	for key in _outer_at:
		(_outer_at[key] as Node3D).visible = on


## Plants every streamed square the camera needs right now (counts and checks want them all).
func settle() -> void:
	_stream(true)


func _finish_tasks() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


func _exit_tree() -> void:
	_finish_tasks()


## Blades planted within r metres of (x, z), planting the squares round it first (the checks).
func blades_near(x: float, z: float, r: float) -> int:
	_stream_cam = Vector3(x, 0.0, z)
	settle()
	var n := 0
	var p := Vector3(x, 0.1, z)
	for c in _chunks:
		var mm := c.multimesh
		if not mm.custom_aabb.grow(r).has_point(p):
			continue
		var buf := mm.buffer
		for i in mm.instance_count:
			if Vector2(buf[i * 16 + 3] - x, buf[i * 16 + 11] - z).length() <= r:
				n += 1
	return n


## Weather and season, from main.gd: rain (0..1), how dry the season is (0 spring .. 1 winter).
## Graphics setting: draw this share of the blades (they're planted in random order, so the
## first N are an even thinning) out to this distance from the camera.
func set_quality(frac: float, view_range: float, keep_far := 0.4, near := -1.0, o_frac := -1.0, o_reach := -1.0) -> void:
	if o_frac > 0.0: # else as it was
		outer_frac = clampf(o_frac, 0.05, 1.0)
	if o_reach > 0.0:
		outer_reach = clampf(o_reach, 0.3, 1.0)
	if near > 0.0: # else as it was
		thin_near = near
	blade_mat.set_shader_parameter("thin_near", thin_near)
	_frac = clampf(frac, 0.05, 1.0)
	blade_mat.set_shader_parameter("frac_widen", 1.0 / sqrt(_frac)) # fewer blades, each wider: the lawn as full
	_range = view_range
	plant_reach = _range + CHUNK + 2.0
	thin_keep = clampf(keep_far, 0.05, 1.0)
	blade_mat.set_shader_parameter("fade_end", _range)
	blade_mat.set_shader_parameter("thin_keep", thin_keep)
	_thin()


## Every frame from main.gd: thins the chunks again once the camera has moved a metre.
func follow(cam_pos: Vector3) -> void:
	if cam_pos.distance_to(_stream_cam) > 2.0 or not _tasks.is_empty() or not _done.is_empty():
		if cam_pos.distance_to(_stream_cam) > 2.0:
			_stream_cam = cam_pos
		_stream()
	if cam_pos.distance_to(_cam) < 1.0:
		return
	_cam = cam_pos
	_thin()


func _thin() -> void:
	for c in _chunks:
		_thin_one(c)


func _thin_one(c: MultiMeshInstance3D) -> void:
	var mm := c.multimesh
	var d := mmi_centre_dist(mm)
	if c.has_meta("outer"):
		var reach := _range * outer_reach
		mm.visible_instance_count = _visible(mm.instance_count, _keep_at(d, reach) * outer_frac)
		c.visibility_range_end = reach
		c.set_instance_shader_parameter("lean", Vector2(1.0 / sqrt(outer_frac), outer_reach))
	else:
		mm.visible_instance_count = _visible(mm.instance_count, _keep_at(d))
		c.visibility_range_end = _range


func mmi_centre_dist(mm: MultiMesh) -> float:
	if not is_finite(_cam.x):
		return 0.0
	return mm.custom_aabb.get_center().distance_to(_cam)


## The share of blades drawn at distance d from the camera (the shader's keep() is the same curve).
func _keep_at(d: float, reach := -1.0) -> float:
	if reach < 0.0:
		reach = _range
	# a chunk is 8 m across: count it by its nearest blades so the shader never widens a blade that
	# the chunk still draws at full density
	var near := maxf(d - CHUNK * 0.7, 0.0)
	return lerpf(1.0, thin_keep, smoothstep(thin_near, reach, near))


func drawn_blades() -> int:
	settle()
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
