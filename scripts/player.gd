extends Node3D
## The character you play: follows paths, sits, and runs timed activities (knitting, shearing...).
## Wears the skinned body named as "player" in data/characters.json (see scripts/body.gd),
## which shares its skeleton and animation loops with every other character.
## Falls back to a simple shape model if the model is missing.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const Body = preload("res://scripts/body.gd")
## Lying in a bed (assets/props/gran_bed.glb), measured in the bed's own space: her feet rest here,
## she lies along the bed's back-to-front axis with her head on the pillows (the head end rises by
## LIE_TILT degrees), and a quilt lies over her up to the chest.
const LIE_FEET := Vector3(0.0, 0.64, 0.66)
const LIE_TILT := 8.0
const LIE_COVER_LENGTH := 1.1 # metres of her, from the feet, that the quilt covers

var speed := 0.0 # ground speed right now: it eases toward walk_speed, or run_speed while she jogs
var walk_speed := 1.5 # m/s; main.gd raises both with fitness
var run_speed := 3.0
var running := false # Shift held (main.gd sets it every frame; the autotest can hold it too)
var path: Array = []
var busy := false
var detailed := false # true when the Blender character loaded
var _on_arrive := Callable()
var _activity_text := ""
var _activity_t := 0.0
var _activity_total := 1.0
var _activity_done := Callable()
var _return_pos = null
var _sitting := false
var _lying := false # in a bed, on her back under the covers (lie_in_bed)
var _lie_bed: Node3D
var _lie_shape_wait := 0 # frames to wait for her lying pose to take hold before the quilt is shaped over it
var _lie_age := 0.0 # seconds since she lay down; drives the quilt shader
var _t := 0.0
var _model: Node3D
var _arms: Array[MeshInstance3D] = []
var body: Body
var anim_override := "" # a story scene can hold her in a loop ("Work", "SitIdle"...)
var _talk_t := 0.0
var _ring: MeshInstance3D
## How she gathers and sheds speed (m/s²) and how quickly she comes round to a new heading (per
## second, eased): a person takes a moment over each, and without it the walk looks mechanical.
const ACCEL := 9.0
const BRAKE := 9.0
const TURN := 11.0
var walked := 0.0 # metres walked since main.gd last counted them (for fitness)
signal footstep # a foot lands (from the Walk loop's timing)
signal needle_click # a stitch while she knits
var _walk_phase := -1.0
var _needle_t := 0.4


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	body = Body.new()
	_model.add_child(body)
	detailed = body.load_character(Data.player_character())
	if not detailed:
		_build_simple_model()
	_ring = Catalog.glow(Catalog.ring(self, 0.4, 0.46, Vector3(0, 0.03, 0), Color(0.55, 0.95, 0.4)), Color(0.55, 0.95, 0.4), 0.8)


func _build_simple_model() -> void:
	var denim := Color(0.25, 0.3, 0.42)
	var sweater := Catalog.CREAM
	var skin := Color(0.93, 0.76, 0.62)
	var hair := Color(0.36, 0.22, 0.13)
	for x in [-0.1, 0.1]:
		Catalog.cyl(_model, 0.075, 0.07, 0.5, Vector3(x, 0.27, 0), denim)
		Catalog.box(_model, Vector3(0.13, 0.08, 0.22), Vector3(x, 0.04, 0.03), Color(0.3, 0.2, 0.12))
	Catalog.cyl(_model, 0.19, 0.23, 0.56, Vector3(0, 0.78, 0), sweater)
	Catalog.cyl(_model, 0.215, 0.225, 0.08, Vector3(0, 0.84, 0), Catalog.PLAID)
	for x in [-0.27, 0.27]:
		_arms.append(Catalog.cyl(_model, 0.06, 0.065, 0.5, Vector3(x, 0.78, 0), sweater, Vector3(0, 0, -x * 25)))
	Catalog.ball(_model, 0.17, Vector3(0, 1.22, 0), skin)
	Catalog.ball(_model, 0.18, Vector3(0, 1.31, -0.03), hair, Vector3(1.0, 0.75, 1.0))


func walk(p: Array, on_arrive := Callable()) -> void:
	cancel_activity()
	path = p
	_on_arrive = on_arrive
	if path.is_empty():
		_arrive()


func face_point(p: Vector3) -> void:
	var d := p - position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


## Gesture while chatting with a villager.
func talk(seconds := 4.0) -> void:
	_talk_t = seconds


func start_activity(text: String, duration: float, done: Callable, sit_pos = null, sit_rot = null) -> void:
	busy = true
	_activity_text = text
	_activity_t = 0.0
	_activity_total = duration
	_activity_done = done
	_ring.visible = false
	_sitting = sit_pos != null
	if sit_pos != null:
		_return_pos = position
		position = sit_pos
		if sit_rot != null:
			rotation.y = sit_rot


## Gets into a bed and lies down: on her back, head on the pillows, the quilt over her. The bed's
## cushion and folded blanket (its "tidy" mesh) are hidden meanwhile. Ends like any activity.
func lie_in_bed(bed: Node3D, text: String, duration: float, done: Callable) -> void:
	start_activity(text, duration, done, bed.to_global(LIE_FEET), bed.rotation.y)
	_lying = true
	_lie_bed = bed
	var tidy := bed.find_child("tidy", true, false) as Node3D
	if tidy:
		tidy.visible = false
	_lie_cover(bed).visible = false # shown once her pose has settled and the quilt has her shape
	_lie_shape_wait = 3
	_lie_age = 0.0
	_set_cloth(bed, 0.0)
	if detailed:
		_model.rotation_degrees.x = -(90.0 - LIE_TILT)


## Passes the time since she lay down to the quilt shader (the drop, the ripples, the breathing).
func _set_cloth(bed: Node3D, age: float) -> void:
	var cover := bed.get_node_or_null("LieCover") as Node3D
	if cover == null or not cover.has_meta("cloth"):
		return
	for m in cover.get_meta("cloth"):
		(m as ShaderMaterial).set_shader_parameter("age", age)
		(m as ShaderMaterial).set_shader_parameter("breath", clampf((age - 1.0) / 1.5, 0.0, 1.0))


func is_lying() -> bool:
	return busy and _lying


## The quilt over a sleeper. It is shaped from her own body: her bones, padded out to the width of
## her limbs, hold the cloth up, and it hangs from them to the mattress as real cloth would, so the
## bulge is her: two legs, hips, chest, arms. Built on the bed's own node, in the bed's space, once
## per bed; _shape_cover gives it its shape each time she lies down.
func _lie_cover(bed: Node3D) -> Node3D:
	var c := bed.get_node_or_null("LieCover") as Node3D
	if c:
		return c
	c = Node3D.new()
	c.name = "LieCover"
	c.visible = false
	bed.add_child(c)
	var shader := preload("res://shaders/quilt_cloth.gdshader")
	var quilt := ShaderMaterial.new()
	quilt.shader = shader
	quilt.set_shader_parameter("albedo_tex", load("res://assets/props/gran_bed_gran_bed_quilt.png"))
	var sheet := ShaderMaterial.new()
	sheet.shader = shader
	sheet.set_shader_parameter("textured", false)
	sheet.set_shader_parameter("puff", 0.0)
	c.set_meta("cloth", [quilt, sheet])
	var mi := MeshInstance3D.new()
	mi.name = "Cloth"
	c.add_child(mi)
	return c


const LIE_SLOPE := 1.3 # how steeply the cloth hangs from her body down to the mattress, metres per metre


## Where the points of her skinned body are right now, in the bed's space: every vertex of her mesh
## moved by her current bones. The quilt is draped over these, so it takes her exact shape.
func _body_points(bed: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sk: Skeleton3D = body.skeleton
	var to_bed := bed.global_transform.affine_inverse() * sk.global_transform
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var skin: Skin = mi.skin
		var xf: Array[Transform3D] = []
		if skin != null:
			for b in skin.get_bind_count():
				var bone := skin.get_bind_bone(b)
				if bone < 0:
					bone = sk.find_bone(skin.get_bind_name(b))
				xf.append(to_bed * sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
		else: # no skin of its own: the skeleton's rest pose is the bind pose
			for bone in sk.get_bone_count():
				xf.append(to_bed * sk.get_bone_global_pose(bone) * sk.get_bone_global_rest(bone).affine_inverse())
		for surf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.size() < verts.size():
				continue
			var per := bones.size() / verts.size()
			for v in verts.size():
				var pos := Vector3.ZERO
				for k in per:
					var w := weights[v * per + k]
					if w > 0.0:
						pos += (xf[bones[v * per + k]] * verts[v]) * w
				out.append(pos)
	return out


## Builds the quilt's mesh over her body as she lies now: a height field over the bed, from just below
## her shoulders to past her feet. Her body's highest point in each small cell holds the cloth up, and
## from there it hangs at LIE_SLOPE down to the mattress, so the bulge is her own shape. The first rows,
## at her chest, are the sheet turned back over it.
func _shape_cover(bed: Node3D) -> void:
	var cover := _lie_cover(bed)
	var sk: Skeleton3D = body.skeleton
	var edge := 0.615 # the top of the quilt that's already on the bed
	var chest: Vector3 = bed.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("UpperChest")).origin)
	var z_head := chest.z + 0.04
	var z_foot := minf(0.93, LIE_FEET.z + 0.27)
	var half := 0.68
	var nx := 46
	var nz := 64
	var fold_rows := 4
	var dx := 2.0 * half / nx
	var dz := (z_foot - z_head) / nz
	var w1 := nx + 1
	var h := PackedFloat32Array()
	h.resize(w1 * (nz + 1))
	h.fill(edge)
	for p in _body_points(bed):
		if p.y <= edge + 0.01 or p.z < z_head - 0.02 or p.z > z_foot:
			continue
		var ix := roundi((p.x + half) / dx)
		var iz := roundi((p.z - z_head) / dz)
		if ix < 0 or ix > nx or iz < 0 or iz > nz:
			continue
		h[iz * w1 + ix] = maxf(h[iz * w1 + ix], p.y)
	# the cloth bridges the gaps between her surface points
	var g := h.duplicate()
	for iz in range(1, nz):
		for ix in range(1, nx):
			var m := h[iz * w1 + ix]
			for o in [-w1 - 1, -w1, -w1 + 1, -1, 1, w1 - 1, w1, w1 + 1]:
				m = maxf(m, g[iz * w1 + ix + o])
			h[iz * w1 + ix] = m
	# and hangs from her down to the mattress: two sweeps of a distance transform with a slope
	var sx := LIE_SLOPE * dx
	var sz := LIE_SLOPE * dz
	var sd := LIE_SLOPE * sqrt(dx * dx + dz * dz)
	for iz in range(1, nz + 1):
		for ix in range(1, nx):
			var k := iz * w1 + ix
			h[k] = maxf(h[k], maxf(maxf(h[k - 1] - sx, h[k - w1] - sz), maxf(h[k - w1 - 1] - sd, h[k - w1 + 1] - sd)))
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, 0, -1):
			var k := iz * w1 + ix
			h[k] = maxf(h[k], maxf(maxf(h[k + 1] - sx, h[k + w1] - sz), maxf(h[k + w1 + 1] - sd, h[k + w1 - 1] - sd)))
	for iz in nz + 1:
		var z := lerpf(z_head, z_foot, float(iz) / nz)
		var tuck := clampf((z_foot - z) / 0.12, 0.0, 1.0) # tucked in at the foot
		for ix in nx + 1:
			var k := iz * w1 + ix
			h[k] = edge + (maxf(h[k] + 0.022, edge) - edge) * tuck
	g = h.duplicate() # cloth holds no crease: soften it once
	for iz in range(1, nz):
		for ix in range(1, nx):
			var k := iz * w1 + ix
			h[k] = (g[k] * 4.0 + g[k - 1] + g[k + 1] + g[k - w1] + g[k + w1]) / 8.0
	var mesh := ArrayMesh.new()
	for part in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for jz in nz:
			if (jz < fold_rows) != (part == 0):
				continue
			for ix in nx:
				for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
					var cx: int = ix + corner[0]
					var cz: int = jz + corner[1]
					var u: float = float(cx) / nx
					var v: float = float(cz) / nz
					var y: float = h[cz * w1 + cx]
					st.set_uv(Vector2(u, v))
					st.set_color(Color(clampf((y - edge) / 0.12, 0.0, 1.0), 0.0, 0.0)) # free to move where it's off the mattress
					st.add_vertex(Vector3((u - 0.5) * 2.0 * half, y + (0.012 if part == 0 else 0.0), lerpf(z_head, z_foot, v)))
		st.index()
		st.generate_normals()
		st.generate_tangents() # the shader's weave and padding are normal-mapped
		st.commit(mesh)
	var cloth: Array = cover.get_meta("cloth")
	mesh.surface_set_material(0, cloth[1])
	mesh.surface_set_material(1, cloth[0])
	(cover.get_node("Cloth") as MeshInstance3D).mesh = mesh
	cover.visible = true


func cancel_activity() -> void:
	if not busy:
		return
	_end_activity()


func _end_activity() -> void:
	busy = false
	_sitting = false
	if _lying:
		_lying = false
		_model.rotation_degrees.x = 0.0
		if is_instance_valid(_lie_bed):
			var tidy := _lie_bed.find_child("tidy", true, false) as Node3D
			if tidy:
				tidy.visible = true
			var cover := _lie_bed.get_node_or_null("LieCover") as Node3D
			if cover:
				cover.visible = false
		_lie_bed = null
	_ring.visible = true
	if not detailed:
		_model.position.y = 0.0
		for a in _arms:
			a.rotation_degrees.x = 0.0
	if _return_pos != null:
		position = _return_pos
		_return_pos = null


## Metres of path still ahead of her.
func _path_left() -> float:
	var total := 0.0
	var from := position
	for p in path:
		total += Vector2(p.x - from.x, p.z - from.z).length()
		from = p
	return total


func _arrive() -> void:
	var cb := _on_arrive
	_on_arrive = Callable()
	if cb.is_valid():
		cb.call()


## What she's doing ("Knitting"), or "" when she isn't busy.
func activity_text() -> String:
	return _activity_text if busy else ""


## How far through the current activity she is, 0..1.
func activity_progress() -> float:
	return clampf(_activity_t / maxf(_activity_total, 0.001), 0.0, 1.0)


## Where the action bar floats: just over her head.
func head_point() -> Vector3:
	if _lying: # the bar floats over her head on the pillow, not over her feet
		return global_position + global_transform.basis * Vector3(0, 0.5, -1.55)
	return global_position + Vector3(0, (body.label_height if detailed else 1.8) + 0.05, 0)


func _process(delta: float) -> void:
	_t += delta
	if _lying and is_instance_valid(_lie_bed):
		if _lie_shape_wait > 0:
			_lie_shape_wait -= 1
			if _lie_shape_wait == 0 and detailed:
				_shape_cover(_lie_bed)
		_lie_age += delta
		_set_cloth(_lie_bed, _lie_age)
	var walking := false
	if busy:
		_activity_t += delta
		if _activity_t >= _activity_total:
			var cb := _activity_done
			_activity_done = Callable()
			_end_activity()
			if cb.is_valid():
				cb.call()
	elif not path.is_empty():
		walking = true
		var next: Vector3 = path[0]
		var to := next - position
		to.y = 0.0
		var d := to.length()
		# She eases up to speed and slows into her last step, and takes a corner at the pace her
		# turning allows, so she never snaps to full speed or pivots on the spot mid-stride.
		var top := run_speed if running else walk_speed
		var off := absf(angle_difference(rotation.y, atan2(to.x, to.z))) if d > 0.01 else 0.0
		var want := top * clampf(1.15 - off / 1.6, 0.35, 1.0)
		want = minf(want, maxf(0.5, sqrt(2.0 * BRAKE * _path_left())))
		speed = move_toward(speed, want, (ACCEL if want > speed else BRAKE) * delta)
		var step := speed * delta
		if d <= step:
			walked += d
			position = Vector3(next.x, 0.0, next.z)
			path.remove_at(0)
			if path.is_empty():
				speed = 0.0
				_arrive()
		else:
			position += to / d * step
			walked += step
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * TURN))
	else:
		speed = 0.0
	if detailed:
		_animate(delta, walking)
	else:
		_animate_simple(walking)


## Skinned character: pick the loop for the current state; the body cross-fades to it.
func _animate(delta: float, walking: bool) -> void:
	_talk_t = maxf(0.0, _talk_t - delta)
	var want := "Idle"
	if anim_override != "" and not walking:
		want = anim_override
	elif busy:
		if _lying:
			want = "Idle"
		elif _sitting:
			want = "SitKnit" if _activity_text == "Knitting" else "SitIdle"
		elif _activity_text == "Reading":
			want = "Idle"
		else:
			want = "Work"
	elif walking:
		want = "Run" if running else "Walk"
	elif _talk_t > 0.0:
		want = "Talk"
	body.play(want, speed)
	_sound_cues(delta)


## Footsteps land twice per Walk loop, when each leg is furthest forward (a quarter and three
## quarters through it, see a_walk in tools/build_character.py); needles click while she knits.
func _sound_cues(delta: float) -> void:
	var cur := body.current()
	if body.striding() and body.anim.current_animation_length > 0.0:
		var ph := fmod(body.anim.current_animation_position / body.anim.current_animation_length + 0.75, 1.0)
		if _walk_phase >= 0.0 and (ph < _walk_phase or (_walk_phase < 0.5 and ph >= 0.5)):
			footstep.emit()
		_walk_phase = ph
	else:
		_walk_phase = -1.0
	if cur == "SitKnit":
		_needle_t -= delta
		if _needle_t <= 0.0:
			needle_click.emit()
			_needle_t = randf_range(0.28, 0.65)


func _animate_simple(walking: bool) -> void:
	if busy:
		for i in _arms.size():
			_arms[i].rotation_degrees.x = -50.0 + 12.0 * sin(_t * 12.0 + i * PI)
	elif walking:
		_model.position.y = absf(sin(_t * 11.0)) * 0.06
		for i in _arms.size():
			_arms[i].rotation_degrees.x = 25.0 * sin(_t * 11.0 + i * PI)
	else:
		_model.position.y = lerpf(_model.position.y, 0.0, 0.2)
		for a in _arms:
			a.rotation_degrees.x = lerpf(a.rotation_degrees.x, 0.0, 0.2)
