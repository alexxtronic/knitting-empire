extends Node3D
## Fireflies: small glowing orbs that drift around things near the player after dusk (the crop
## plots, benches and lamps, the barn and pen, bushes and flowers). Each one hovers round an anchor
## for half a minute or so, blinking softly, then fades and turns up by something else. They fade
## in as the light goes, and stay away in the rain. One MultiMesh of glowing billboards draws them
## all; a few carry a tiny light so they tint what they pass.

const World = preload("res://scripts/world.gd")
const COUNT := 52
const LIGHTS := 6
const RANGE := 18.0 # anchors are picked within this distance of the player
const NATURE_KINDS := ["bush", "flowers", "hedge", "clover"]

var main # main.gd
var mmi: MultiMeshInstance3D
var lights: Array[OmniLight3D] = []
var anchors: Array[Vector3] = []
var night := 0.0 # 0 by day .. 1 on a clear night
var _t := 0.0
var _anchor_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _home: Array[Vector3] = [] # each fly's anchor
var _wander: Array[Vector3] = [] # how far it strays from the anchor (x, height, z)
var _phase: Array[Vector4] = []
var _age: Array[float] = []
var _life: Array[float] = []
var _glow: Array[float] = [] # brightness last frame, 0..1


func setup(m) -> void:
	main = m
	name = "Fireflies"
	_rng.seed = 4021
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1.0, 0.95, 0.6, 0.9), Color(0.85, 0.95, 0.35, 0.25), Color(0.6, 0.9, 0.2, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = COUNT
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1000, -10, -1000), Vector3(2000, 40, 2000))
	add_child(mmi)
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(0.85, 1.0, 0.45)
		l.omni_range = 1.3
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
	for i in COUNT:
		_home.append(Vector3.ZERO)
		_wander.append(Vector3.ZERO)
		_phase.append(Vector4.ZERO)
		_age.append(0.0)
		_life.append(0.0)
		_glow.append(0.0)
	_gather_anchors()
	for i in COUNT:
		_reset(i)
		_age[i] = _rng.randf() * _life[i] # start part-way through their lives, so they don't all fade at once


## How many are glowing visibly right now (for the autotest).
func lit_count() -> int:
	var n := 0
	if not mmi.visible:
		return 0
	for g in _glow:
		if g > 0.15:
			n += 1
	return n


func _gather_anchors() -> void:
	anchors.clear()
	var me: Vector3 = main.player.global_position
	var near := func(p: Vector3) -> bool:
		return Vector2(p.x - me.x, p.z - me.z).length() < RANGE
	var things: Array = []
	things.append_array(main.plots)
	things.append_array(main.decor)
	for n in [World.barn, World.pen, World.pond]:
		if n != null and is_instance_valid(n):
			things.append(n)
	for n in things:
		if is_instance_valid(n) and (n as Node3D).visible and near.call((n as Node3D).global_position):
			anchors.append((n as Node3D).global_position)
	if main.nature:
		for c in main.nature.get_children():
			if not (c is MultiMeshInstance3D) or not (c as Node3D).visible:
				continue
			var kind := str(c.name)
			if not NATURE_KINDS.any(func(k: String) -> bool: return kind.contains(k)):
				continue
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			var xf: Transform3D = (c as Node3D).global_transform
			var step := maxi(1, mm.instance_count / 12) # a sample is plenty
			for i in range(0, mm.instance_count, step):
				var p: Vector3 = xf * mm.get_instance_transform(i).origin
				if near.call(p):
					anchors.append(p)
	if anchors.size() < 8: # open grass: hover round the player's surroundings instead
		for i in 12:
			var a := _rng.randf() * TAU
			anchors.append(me + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, RANGE * 0.7))


func _reset(i: int) -> void:
	var a: Vector3 = anchors[_rng.randi() % anchors.size()] if not anchors.is_empty() else main.player.global_position
	var off := Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2))
	_home[i] = Vector3(a.x, 0, a.z) + off
	_wander[i] = Vector3(_rng.randf_range(0.4, 1.1), _rng.randf_range(0.35, 1.5), _rng.randf_range(0.4, 1.1))
	_phase[i] = Vector4(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf_range(0.15, 0.4), _rng.randf_range(0.6, 1.6))
	_age[i] = 0.0
	_life[i] = _rng.randf_range(14.0, 34.0)


func _process(delta: float) -> void:
	var rain: float = float(main.get("rain"))
	var target := (1.0 - smoothstep(0.0, 0.35, Game.daylight())) * (1.0 - clampf(rain, 0.0, 1.0))
	night = move_toward(night, target, delta * 0.5)
	mmi.visible = night > 0.01
	if not mmi.visible:
		for l in lights:
			l.visible = false
		for i in COUNT:
			_glow[i] = 0.0
		return
	_t += delta
	_anchor_timer -= delta
	if _anchor_timer <= 0.0:
		_anchor_timer = 6.0
		_gather_anchors()
	var me: Vector3 = main.player.global_position
	var mm := mmi.multimesh
	for i in COUNT:
		_age[i] += delta
		var far := Vector2(_home[i].x - me.x, _home[i].z - me.z).length() > RANGE + 4.0
		if _age[i] > _life[i] or (far and _glow[i] < 0.05):
			_reset(i)
		var ph := _phase[i]
		var s := ph.z
		var w := _wander[i]
		var p := _home[i] + Vector3(
			sin(_t * s + ph.x) * w.x + 0.25 * sin(_t * s * 2.7 + ph.y),
			w.y + 0.3 * sin(_t * s * 1.9 + ph.y) + 0.08 * sin(_t * 3.1 + ph.x),
			cos(_t * s * 0.83 + ph.y) * w.z + 0.25 * cos(_t * s * 2.3 + ph.x))
		var env := smoothstep(0.0, 2.5, _age[i]) * (1.0 - smoothstep(_life[i] - 2.5, _life[i], _age[i]))
		var blink := 0.3 + 0.7 * pow(0.5 + 0.5 * sin(_t * ph.w + ph.x), 3.0)
		var g := night * env * blink
		_glow[i] = g
		var size := 0.55 + 0.45 * g
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)), p))
		mm.set_instance_color(i, Color(1.0, 1.0, 0.85, g))
		if i < LIGHTS:
			var l := lights[i]
			l.visible = g > 0.02
			l.position = p
			l.light_energy = 0.35 * g
