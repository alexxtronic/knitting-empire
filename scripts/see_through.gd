extends Node
## Scenery between the camera and the people on screen fades to see-through (Alex's review,
## 2026-11-14: a fern hid most of Rowan's first scene, and the barn roof hid the pen builder).
##
## What counts as in the way: the segment from the camera to each person near what the camera looks
## at (her, anyone in the scene, the dog) and to the look-at point itself passes through the thing's
## box. Scattered scenery (god_mode.gd's scenery elements, copies in a MultiMesh) can't fade one
## copy at a time, so the copy is hidden in its MultiMesh and a stand-in MeshInstance3D fades in its
## place; once it's clear again the stand-in fades back and the copy returns. A building's or a
## prop's own meshes (the barn roof, a shop's wall) fade in place, mesh by mesh.
## main.gd calls update() every frame; it does nothing in first person, the cinematic camera, the
## world editor or on the title (restoring anything it faded).

const Furniture = preload("res://scripts/furniture.gd")

const CHECK := 0.12 # seconds between looks
const FADED := 0.7 # how see-through a building's part in the way gets
const SCENERY_FADED := 0.93 # a tree or bush nearly goes: its layered leaf shells would still hide her at less
const SPEED := 3.5 # fade per second
const LOW := 0.7 # things lower than this (tufts, flowers) never hide anyone
const NEAR := 7.0 # people within this of the camera's look-at point count

var main: Node
var _t := 0.0
var _ghosts := {} # god_mode El -> MeshInstance3D standing in for its copy
var _faded := {} # MeshInstance3D (a node's own mesh) -> true while it's fading or faded
var _meshes := {} # node El -> its MeshInstance3Ds
var _want := {} # what's in the way at the last look: El or MeshInstance3D -> true


func setup(m: Node) -> void:
	main = m


func update(delta: float) -> void:
	var off: bool = main.title_on or main.fps.active or main.cinema.active or main.god.active
	_t -= delta
	if _t <= 0.0:
		_t = CHECK
		_want = {} if off else _look()
	# the stand-ins for scenery copies
	for el in _ghosts.keys():
		var g: MeshInstance3D = _ghosts[el]
		var goal := SCENERY_FADED if _want.has(el) else 0.0
		var f := move_toward(float(g.get_meta("fade", 0.0)), goal, delta * SPEED)
		g.set_meta("fade", f)
		for gm in g.get_meta("mats"):
			(gm as StandardMaterial3D).albedo_color.a = 1.0 - 0.99 * f # 0.08 at full fade: a canopy has many layers
		if goal == 0.0 and f <= 0.0:
			_ghosts.erase(el)
			g.queue_free()
			main.god._apply(el) # the copy back where its element says (or still hidden, if cut)
	for el in _want:
		if el is MeshInstance3D or _ghosts.has(el):
			continue
		_ghosts[el] = _stand_in(el)
	# a node's own meshes
	for mi in _want:
		if mi is MeshInstance3D and not _faded.has(mi):
			_faded[mi] = true
	for mi in _faded.keys():
		if not is_instance_valid(mi):
			_faded.erase(mi)
			continue
		var goal := FADED if _want.has(mi) else 0.0
		(mi as MeshInstance3D).transparency = move_toward(mi.transparency, goal, delta * SPEED)
		if goal == 0.0 and mi.transparency <= 0.0:
			_faded.erase(mi)


## How see-through a scenery element or mesh is now (0 = solid), for the checks.
func fade_of(thing) -> float:
	if _ghosts.has(thing):
		return float(_ghosts[thing].get_meta("fade", 0.0))
	if thing is MeshInstance3D and _faded.has(thing):
		return thing.transparency
	return 0.0


func faded_count() -> int:
	return _ghosts.size() + _faded.size()


## What's in the way now: {El or MeshInstance3D: true}.
func _look() -> Dictionary:
	var cam: Camera3D = main.cam
	var eye := cam.global_position
	var ends: Array[Vector3] = [main.cam_target + Vector3(0, 0.6, 0)]
	var who: Array = [main.player]
	who.append_array(main.villagers)
	if main.dog and main.dog.visible:
		who.append(main.dog)
	for n in who:
		if n.visible and n.position.distance_to(main.cam_target) < NEAR:
			ends.append(n.position + Vector3(0, 0.5, 0))
			ends.append(n.position + Vector3(0, 1.5, 0))
	# a box round all the segments, to skip most things with one cheap test
	var lo := eye
	var hi := eye
	for e in ends:
		lo = lo.min(e)
		hi = hi.max(e)
	var found := {}
	for el in main.god.els:
		var o: Vector3 = el.xf.origin
		var reach := 2.0 if el.scenery else 16.0
		if o.x < lo.x - reach or o.x > hi.x + reach or o.z < lo.z - reach or o.z > hi.z + reach:
			continue
		if el.scenery:
			if el.deleted or el.cut or el.home:
				continue
			var box: AABB = (el.xf * el.bounds).abs()
			if box.size.y < LOW or not _blocks(box, eye, ends):
				continue
			found[el] = true
		elif is_instance_valid(el.node) and not el.home and not el.deleted and not (el.node is Furniture):
			var meshes := _meshes_of(el)
			if meshes.any(func(m): return not is_instance_valid(m)):
				_meshes.erase(el) # rebuilt since: list its meshes afresh next time
				continue
			# someone inside the building (a shopkeeper at the counter) doesn't make it fade: the
			# walk-in shops and the barn open up for that themselves
			var whole := AABB()
			var first := true
			var boxes := []
			for mi in meshes:
				if not mi.is_visible_in_tree():
					boxes.append(null)
					continue
				var box: AABB = (mi.global_transform * mi.get_aabb()).abs()
				boxes.append(box)
				whole = box if first else whole.merge(box)
				first = false
			if first:
				continue
			var outside: Array[Vector3] = []
			for e in ends:
				if not whole.grow(0.3).has_point(e):
					outside.append(e)
			if outside.is_empty():
				continue
			for i in meshes.size():
				var box = boxes[i]
				if box != null and box.size.y >= LOW and _blocks(box, eye, outside):
					found[meshes[i]] = true
	return found


## True if the box lies across the way from the eye to any of the ends (and doesn't hold the eye:
## the camera inside a canopy sees out of it anyway).
func _blocks(box: AABB, eye: Vector3, ends: Array[Vector3]) -> bool:
	var core := box.abs()
	core = core.grow(-minf(0.12, minf(core.size.x, minf(core.size.y, core.size.z)) * 0.2))
	if core.has_point(eye):
		return false
	for e in ends:
		# stop a little short of the person, so what they stand next to doesn't count
		var to := eye + (e - eye) * maxf(0.0, 1.0 - 0.35 / maxf(eye.distance_to(e), 0.01))
		if core.intersects_segment(eye, to) != null:
			return true
	return false


func _meshes_of(el) -> Array:
	if not _meshes.has(el):
		var list := []
		for m in el.node.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).mesh != null:
				list.append(m)
		_meshes[el] = list
	return _meshes[el]


## Hides a scenery copy in its MultiMesh and puts a stand-in in its place that can fade.
func _stand_in(el) -> MeshInstance3D:
	var mmi: MultiMeshInstance3D = el.mmi
	var g := MeshInstance3D.new()
	g.mesh = mmi.multimesh.mesh
	# the leaves' own shader sets its alpha (cut-out leaves), so instance transparency can't fade it:
	# each surface gets a plain copy of its own picture, dithered by alpha hash (no blending, so a
	# canopy's inner shells don't darken it), whose alpha then falls
	var mats := []
	for i in g.mesh.get_surface_count():
		var src: Material = mmi.material_override if mmi.material_override else g.mesh.surface_get_material(i)
		var gm := StandardMaterial3D.new()
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.roughness = 0.85
		var tint := Color.WHITE
		if src is ShaderMaterial:
			var tex = (src as ShaderMaterial).get_shader_parameter("albedo_tex")
			if tex is Texture2D:
				gm.albedo_texture = tex
			var t = (src as ShaderMaterial).get_shader_parameter("tint")
			if t is Vector3:
				tint = Color(t.x, t.y, t.z)
			elif t is Color:
				tint = t
			if el.kind.begins_with("tree_"):
				tint *= el.tint # the instance colour, as the leaf shader uses it
		elif src is BaseMaterial3D:
			gm.albedo_texture = (src as BaseMaterial3D).albedo_texture
			tint = (src as BaseMaterial3D).albedo_color
		gm.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
		g.set_surface_override_material(i, gm)
		mats.append(gm)
	g.set_meta("mats", mats)
	g.cast_shadow = mmi.cast_shadow # its shadow stays on the ground while it's see-through
	main.add_child(g)
	g.global_transform = el.xf
	g.set_meta("fade", 0.0)
	mmi.multimesh.set_instance_transform(el.idx, mmi.transform.affine_inverse() * Transform3D(Basis.from_scale(Vector3.ZERO), el.xf.origin))
	return g
