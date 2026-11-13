extends Node3D
## God mode's world editor: the admin (whoever runs the game from the project with the Godot
## editor build; an exported game never shows it) can pick up anything in the world, drag it
## somewhere else, turn it, copy it or delete it, and paint dirt, gravel and cobblestone roads with
## a round brush. Settings > God mode > "Edit the world" switches it on.
##
## What you arrange is saved to res://data/world_layout.json, a data file like the others in
## data/. Every launch reads it after the world is built and applies it, so the layout is the map
## every player gets. The file holds:
##   "nodes"    changes to single things the code builds (shop fronts, fountain, stall, signposts,
##              barn, shipping bin, crop plots, lamp posts, benches): moved, turned or deleted,
##              each named by its kind and where the code first put it
##   "added"    extra lamp posts, benches and other decor copied in the editor
##   "scenery"  for each kind of scattered scenery you have edited (trees, rocks, bushes, hedges,
##              fences, tufts, flowers), the complete list of where each one stands. Once a kind
##              is in the file the list replaces what scripts/world.gd and scripts/nature.gd
##              scatter, so later changes to their random placement can't undo your arrangement
##   "roads"    the painted road map (a PNG, base64): red = dirt, green = gravel, blue = cobbles
## With no file, or a part missing from it, that part of the world is exactly what the code builds.
##
## The Place tool shows the chosen thing under the pointer with a green outline (R turns it left,
## T right), sets one down on a click and streams them out while the button is held. Its
## drop-down lists everything that can be set down: every kind of
## scenery, every model in assets/props (a kind that the code never scatters, such as the single
## maple leaves, becomes scenery of its own the first time one is placed) and every catalog piece.
##
##   "house"    Nora's furniture as a new game starts it: her house and the yard pieces, the
##              complete list, written once any of it has been arranged here. Her own game's
##              furniture (bought, moved and sold in Build mode) is in her save, as before
##
## Her furniture can be picked up, moved, turned, copied and deleted like anything else, and a
## catalog piece placed inside the house becomes part of it. Anything new built as a Furniture
## node is picked up by itself; the autotest's god checks fail if anything in the world can't be.
##
## Not editable here: the walls of Nora's house and Rosewood Cottage (the game's rules are tied
## to where they stand), the villagers and the sheep. The sheep pen moves as one piece and turns in quarter
## turns; the sheep and their field go with it.

const Catalog = preload("res://scripts/catalog.gd")
const World = preload("res://scripts/world.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Grass = preload("res://scripts/grass.gd")
const Nature = preload("res://scripts/nature.gd")
const Furniture = preload("res://scripts/furniture.gd")

const LAYOUT_FILE := "res://data/world_layout.json"
const TURN_STEP := 15.0 # degrees per press of R
const ROAD_PX := 8 # pixels of the painted road map per metre
const ROAD_COLOURS := {"dirt": Color(1, 0, 0), "gravel": Color(0, 1, 0), "cobble": Color(0, 0, 1)}
const TOOLS := [["select", "Select & move"], ["place", "Place"], ["dirt", "Dirt road"], ["gravel", "Gravel road"], ["cobble", "Cobblestones"], ["erase", "Erase road"]]
const BRUSH_MAX := 15.0 # metres (radius)
const SIZE_STEP := 1.1 # how much bigger one press of + makes a thing (and - smaller)
const SIZE_MIN := 0.2
const SIZE_MAX := 5.0
## Extra entries in the Place list: a model at a smaller size to begin with, [model, size, name].
const SMALL_OPTIONS := [["rock_cluster", 0.5, "Rock cluster (small)"], ["rock_single", 0.5, "Rock (small)"]]
## Scenery that is set down turned and sized a little at random, as the code scatters it.
const NATURAL := ["tree_", "rock_", "bush_", "tuft_", "flowers_", "clover", "leaf_", "maple_"]
## Scenery you walk through: it never blocks the way.
const SOFT := ["bush_", "tuft_", "flowers_", "clover", "leaf_", "crop_"]
## Models the Place list leaves out: paving (painted instead), rigged animals, the working crop plot.
const NOT_PLACED := ["cobble_", "sheep_", "dirt_plot"]
## Painted cobbles are the 4 x 2 m plaza tiles on a fixed grid (it lines up with the plaza the code
## builds), each drawn only where it was painted (shaders/cobble_painted.gdshader).
const TILE := Vector2(4.0, 2.0)
const TILE_ORIGIN := Vector2(1.0, 0.0)
const BEDS := Rect2(10.25, -1.75, 5.1, 3.9) # worn earth under the crop plots where the code puts them
const BEDS_NO_BUILD := Rect2(10.4, -1.6, 4.8, 3.6) # main.gd keeps furniture off the plots
const ROAM := Rect2(-104, -108, 256, 178) # how far the camera may go while editing: every land (Regions.BOUNDS) and a margin
const SMALL := ["tuft_small", "tuft_mid", "tuft_tall", "flowers_daisy", "flowers_buttercup", "flowers_wild", "flowers_poppy", "clover_patch"]
const TITLES := {
	"tree_maple_autumn": "Maple tree (autumn)", "tree_maple_green": "Maple tree (green)", "tree_spruce": "Spruce tree",
	"rock_boulder": "Boulder", "rock_cluster": "Rock cluster", "rock_single": "Rock", "hedge": "Hedge", "fence_picket": "Picket fence",
	"bush_round": "Round bush", "bush_tall": "Tall bush", "bush_berry": "Berry bush", "bush_autumn": "Autumn bush",
	"tuft_small": "Grass tuft (small)", "tuft_mid": "Grass tuft", "tuft_tall": "Grass tuft (tall)", "flowers_daisy": "Daisies",
	"flowers_buttercup": "Buttercups", "flowers_wild": "Wild flowers", "flowers_poppy": "Poppies", "clover_patch": "Clover",
	"barn": "Barn", "bin": "Shipping bin", "mailbox": "Mailbox", "plot": "Crop plot", "pen": "Sheep pen", "pond": "Pond",
	"leaf_yellow": "Maple leaf (gold)", "leaf_red": "Maple leaf (red)", "leaf_green": "Maple leaf (green)",
	"maplewood_bus": "Maplewood bus",
}


## One thing in the world that can be picked up.
class El:
	extends RefCounted
	var kind := ""
	var title := ""
	var scenery := false # one of many copies drawn together (a tree, a rock, a tuft); else its own node
	var key := "" # nodes: kind@x,z where the code first put it (its name in the layout file)
	var node: Node3D
	var mmi: MultiMeshInstance3D
	var idx := -1
	var base := Transform3D.IDENTITY # where the code (or the layout file) put it
	var xf := Transform3D.IDENTITY # where it is now
	var deleted := false
	var added := false # decor copied in the editor
	var home := false # Nora's furniture (main.furniture): saved as the "house" list, not as a node
	var tint := Color.WHITE
	var bounds := AABB() # in its own space
	var radius := 1.0
	var tri: TriangleMesh # its triangles, for exact clicking
	var block_local: Array = [] # nodes: obstacle rects relative to `base`
	var block_world: Array = [] # the obstacle rects it has in main.gd's lists now
	var leaves: Array = [] # trees: fallen leaves, each [Transform3D relative to the tree, Color, Color]
	var leaf0 := -1


var main # main.gd
var active := false
var layout_path := LAYOUT_FILE
var els: Array[El] = []
var by_key := {} # nodes
var scenery := {} # kind -> Array of El
var templates := {} # kind -> how its MultiMeshes are made
var baked := {} # scenery kinds whose full list goes in the layout file
var orphans := {} # saved node edits that match nothing the code builds now (kept in the file)
var unknown_scenery := {} # saved scenery lists for kinds the game no longer has (kept in the file)
var plots_edited := false
var home_edited := false # her furniture was arranged here: the layout gets the whole list again
var house_list: Array = [] # the layout's "house" list, as read ([] = the code's own furnishing)
var _home := {} # Furniture node -> El
var unsaved := false
var loaded := false # a layout file was read and applied at launch
var selected: El
var hover: El
var tool := "select"
var brush := 1.2 # metres (radius, or half the side of the square brush)
var brush_square := false
var place_id := "" # what the Place tool sets down: "scenery:<model>", "scenery:<model>:<size>" or "decor:<catalog id>"
var place_size := 1.0 # how big the Place tool sets things down (+ and - change it)
var _size_for := "" # the place_id that place_size was last reset for
var small_on := true
var roads_on := false # the layout has painted roads: the code's own paths and cobbles are replaced by the map
var road_img: Image
var road_tex: ImageTexture
var undo_stack: Array = []

var _tri_cache := {}
var _bed_blocks: Array = []
var _tiles := {} # Vector2i cell -> which of the 4 tile variants
var _tile_meshes: Array = []
var _tile_mmis: Array[MultiMeshInstance3D] = []
var _drag := {}
var _painting := false
var _stroke_rect := Rect2()
var _stroke_before := PackedByteArray()
var _last_dab := Vector3.ZERO
var _line_on := false # Shift held while painting: a straight line from _line_from
var _line_from := Vector3.ZERO
var _line_base := PackedByteArray() # the road map as it was when the line began
var _pen_at := Vector3.ZERO
var _pen_place := Rect2()
var _pond: El
var _place_pick: OptionButton
var _ghost: Node3D # the Place tool's preview: the thing itself under the pointer, outlined in green
var _ghost_yaw := 0.0
var _ghost_scale := 1.0
var _ghost_mat: StandardMaterial3D
var _stream := {} # click and hold with the Place tool: {"from", "last", "els", "changed"}
var _shape_btn: Button
var _mask_dirty := false
var _mask_t := 0.0
var _mouse := Vector2.ZERO
var _mouse_moved := false
var _time_was := true
var _hidden: Array = []
var _sel_box: MeshInstance3D
var _hover_box: MeshInstance3D
var _ring: MeshInstance3D
var _ui: PanelContainer
var _tool_btns := {}
var _status: Label
var _brush_label: Label
var _brush_slider: HSlider
var _small_check: CheckBox


## Only the admin edits the world: the game run from its project with the Godot editor build.
## A player's exported game is a different build, and can't write to res:// either.
static func is_admin() -> bool:
	return OS.has_feature("editor")


# --- finding everything -------------------------------------------------------------------

## Lists everything that can be edited. main.gd calls this once the world is built.
func collect() -> void:
	els.clear()
	by_key.clear()
	scenery.clear()
	templates.clear()
	for c in main.get_children():
		if c is MultiMeshInstance3D and str(c.name).begins_with("Trees_"):
			_collect_mmi(c, "tree_" + str(c.name).substr(6))
	for c in main.nature.get_children():
		if c is MultiMeshInstance3D:
			var parts := str(c.name).split("_")
			_collect_mmi(c, "_".join(parts.slice(0, parts.size() - 2)))
		elif c is Furniture:
			_collect_node(c, "decor_" + c.item_id, c.display_name(), [] if c.is_flat() else [c.footprint()])
	for b in Town.built:
		_collect_node(b[0], b[1], b[2], b[3])
	for f in main.decor:
		_collect_node(f, "decor_" + f.item_id, f.display_name(), [] if f.is_flat() else [f.footprint()])
	if World.barn != null and is_instance_valid(World.barn):
		var p: Vector3 = World.barn.position
		_collect_node(World.barn, "barn", "Barn", World.barn_blocks(p) if not World.barn_parts.is_empty() else [Rect2(p.x - 2.6, p.z - 2.1, 5.2, 4.2)])
	var bp: Vector3 = main.bin.position
	_collect_node(main.bin, "bin", "Shipping bin", [Rect2(bp.x - 0.5, bp.z - 0.35, 1.0, 0.7)])
	if main.mail and main.mail.box:
		var mp: Vector3 = main.mail.box.position
		_collect_node(main.mail.box, "mailbox", "Mailbox", [Rect2(mp.x - 0.2, mp.z - 0.25, 0.4, 0.5)])
	for p in main.plots:
		_collect_node(p, "plot", "Crop plot", [])
	if World.pen != null and is_instance_valid(World.pen):
		_collect_node(World.pen, "pen", "Sheep pen", World.pen_blocks)
		_pen_at = World.pen.position
		_pen_place = (main.PEN as Rect2).grow(0.3) # main.gd keeps furniture out of the pen
	_pond = null
	if World.pond != null and is_instance_valid(World.pond):
		_pond = _collect_node(World.pond, "pond", "Pond", [main.pond_rect])
	_home.clear()
	sync_home()


## Nora's furniture comes and goes as she buys, moves and sells things (and only exists once a
## game is loaded), so its list is brought up to date each time the editor opens.
func sync_home() -> void:
	for f in _home.keys():
		var el: El = _home[f]
		if not is_instance_valid(f) or (not el.deleted and not main.furniture.has(f)):
			els.erase(el)
			_home.erase(f)
	for f in main.furniture:
		if is_instance_valid(f) and not _home.has(f):
			var el := _collect_node(f, "home_" + str(f.item_id), f.display_name(), [])
			el.home = true
			_home[f] = el


func _collect_mmi(mmi: MultiMeshInstance3D, kind: String) -> void:
	var mm := mmi.multimesh
	var tree := kind.begins_with("tree_")
	if not templates.has(kind):
		templates[kind] = {"parent": mmi.get_parent(), "mesh": mm.mesh, "shadow": mmi.cast_shadow, "view": mmi.visibility_range_end,
			"margin": mmi.visibility_range_end_margin, "seasonal": not tree and main.nature._seasonal.has(mmi), "tree": tree, "mmis": []}
		scenery[kind] = []
	templates[kind]["mmis"].append(mmi)
	var bounds: AABB = mm.mesh.get_aabb()
	for i in mm.instance_count:
		var el := El.new()
		el.kind = kind
		el.title = TITLES.get(kind, kind.capitalize())
		el.scenery = true
		el.mmi = mmi
		el.idx = i
		el.base = mmi.transform * mm.get_instance_transform(i)
		el.xf = el.base
		el.bounds = bounds
		if tree:
			el.tint = mm.get_instance_color(i)
			_take_leaves(el, "%s:%d" % [kind.substr(5), i])
		else:
			var at := Vector2i(roundi(el.base.origin.x * 100.0), roundi(el.base.origin.z * 100.0))
			if main.nature.block_at.has(at):
				el.block_world = [main.nature.block_at[at]]
		_measure(el)
		els.append(el)
		scenery[kind].append(el)


func _collect_node(n: Node3D, kind: String, title: String, blocks: Array) -> El:
	var el := El.new()
	el.kind = kind
	el.title = title
	el.node = n
	el.base = n.global_transform
	el.xf = el.base
	var o := Vector2(el.base.origin.x, el.base.origin.z)
	for r in blocks:
		el.block_world.append(r)
		el.block_local.append(Rect2((r as Rect2).position - o, (r as Rect2).size))
	el.key = "%s@%.2f,%.2f" % [kind, o.x, o.y]
	var n_same := 2
	while by_key.has(el.key):
		el.key = "%s@%.2f,%.2f#%d" % [kind, o.x, o.y, n_same]
		n_same += 1
	by_key[el.key] = el
	# its size: every mesh under it, in its own space
	var inv := el.base.affine_inverse()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
		el.bounds = box if first else el.bounds.merge(box)
		first = false
	if first:
		el.bounds = AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.0, 0.6))
	_measure(el)
	els.append(el)
	return el


func _measure(el: El) -> void:
	var s: Vector3 = el.xf.basis.get_scale()
	el.radius = (el.bounds.size * 0.5).length() * maxf(s.x, maxf(s.y, s.z)) + 0.05


## The fallen leaves the code scattered under this tree, kept relative to it so they follow it.
func _take_leaves(el: El, range_key: String) -> void:
	if World.tree_litter == null or not World.tree_leaf_ranges.has(range_key):
		return
	var r: Vector2i = World.tree_leaf_ranges[range_key]
	var mm := World.tree_litter.multimesh
	var inv := _rigid(el.base).affine_inverse()
	el.leaf0 = r.x
	for j in range(r.x, r.x + r.y):
		el.leaves.append([inv * mm.get_instance_transform(j), mm.get_instance_color(j), mm.get_instance_custom_data(j)])


## Fallen leaves for a tree the code didn't scatter (one from the layout file, or a copy).
func _new_leaves(el: El) -> void:
	el.leaves.clear()
	var k := el.kind.substr(5)
	if not World.LEAVES_PER_TREE.has(k):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(el.xf.origin.x * 100.0), roundi(el.xf.origin.z * 100.0)))
	var cols: Array = World.LITTER[k]
	var s: float = el.xf.basis.get_scale().x
	var inv := _rigid(el.xf).affine_inverse()
	for i in int(World.LEAVES_PER_TREE[k]):
		var a := rng.randf() * TAU
		var d := 0.4 + 3.4 * s * sqrt(rng.randf())
		var p := Vector2(el.xf.origin.x + cos(a) * d, el.xf.origin.z + sin(a) * d)
		var c: Color = (cols[rng.randi() % cols.size()] as Color) * rng.randf_range(0.85, 1.08)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.7, 1.35))
		var leaf := Transform3D(b, Vector3(p.x, 0.03 + rng.randf() * 0.015, p.y))
		el.leaves.append([inv * leaf, c, Color(rng.randf(), 0, 0, 0)])


static func _yaw(t: Transform3D) -> float:
	return atan2(-t.basis.x.z, t.basis.x.x)


## The transform's position on the ground and its turn about the vertical, without scale.
static func _rigid(t: Transform3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw(t)), Vector3(t.origin.x, 0.0, t.origin.z))


# --- showing a change in the world --------------------------------------------------------

## Puts the thing where its `xf` says (or hides it, if deleted). Scenery standing on a walk-in
## shop's floor isn't drawn (it would grow through the boards), but stays in the layout.
func _apply(el: El) -> void:
	if el.scenery:
		var t := el.xf
		if el.deleted or Interiors.inside_of(el.xf.origin) != "":
			t = Transform3D(Basis.from_scale(Vector3.ZERO), el.xf.origin)
		el.mmi.multimesh.set_instance_transform(el.idx, el.mmi.transform.affine_inverse() * t)
		_apply_leaves(el)
		return
	var n := el.node
	n.global_transform = el.xf
	n.visible = not el.deleted
	for b in n.find_children("*", "StaticBody3D", true, false):
		var body := b as StaticBody3D
		if not body.has_meta("god_layer"):
			body.set_meta("god_layer", body.collision_layer)
		body.collision_layer = 0 if el.deleted else int(body.get_meta("god_layer"))
	if n is Furniture:
		n.set("rot", posmod(roundi(_yaw(el.xf) / (PI * 0.5)), 4)) # which way its footprint lies, for sitting and standing by it
	if el.home:
		# her furniture blocks the way through main.gd's own list of it, so that list is what changes
		home_edited = true
		if el.deleted:
			main.furniture.erase(n)
		elif not main.furniture.has(n):
			main.furniture.append(n)
	if n.has_meta("water"):
		(n.get_meta("water") as ShaderMaterial).set_shader_parameter("centre", el.xf.origin)
	if el.kind == "plot" and (el.deleted or not el.xf.is_equal_approx(el.base)):
		plots_edited = true
	if el.kind == "pond" and World.water_mat != null:
		World.water_mat.set_shader_parameter("centre", el.xf.origin)
		World.water_mat.set_shader_parameter("radius", 2.0 * _size_of(el))
	if el.kind == "pen":
		# the sheep and the field they wander go with the fence
		var d: Vector3 = el.xf.origin - _pen_at
		if d.length() > 0.0001:
			_pen_at = el.xf.origin
			main.pen_rect.position += Vector2(d.x, d.z)
			for s in main.sheep_list:
				s.pen.position += Vector2(d.x, d.z)
				s._target += d
				if not s.housed and s.route.is_empty(): # a sheep in the barn, or on her way, stays where she is
					s.position += d


func _apply_leaves(el: El) -> void:
	if el.leaves.is_empty() or el.leaf0 < 0 or World.tree_litter == null:
		return
	var mm := World.tree_litter.multimesh
	var at := _rigid(el.xf)
	for j in el.leaves.size():
		var t: Transform3D = at * (el.leaves[j][0] as Transform3D)
		if el.deleted:
			t = Transform3D(Basis.from_scale(Vector3.ZERO), t.origin)
		mm.set_instance_transform(el.leaf0 + j, t)


## Lays every tree's fallen leaves out again (after trees were added or the list was replaced).
func _rebuild_litter() -> void:
	if World.tree_litter == null:
		return
	var trees: Array = []
	var total := 0
	for kind in scenery:
		if str(kind).begins_with("tree_"):
			for el in scenery[kind]:
				trees.append(el)
				total += (el as El).leaves.size()
	var mm := World.tree_litter.multimesh
	mm.instance_count = total
	var at := 0
	for e in trees:
		var el := e as El
		el.leaf0 = at
		for j in el.leaves.size():
			mm.set_instance_color(at + j, el.leaves[j][1])
			mm.set_instance_custom_data(at + j, el.leaves[j][2])
		at += el.leaves.size()
		_apply_leaves(el)


## Draws every piece of scenery again where it stands (after the layout has moved the buildings,
## so whatever is now on a shop's floor is hidden).
func reapply_scenery() -> void:
	for kind in scenery:
		for el in scenery[kind]:
			if (el as El).mmi != null:
				_apply(el)
	_road_holes()


## The painted cobbles leave the shops' floors alone (shaders/cobble_painted.gdshader).
func _road_holes() -> void:
	var holes := PackedVector4Array()
	for r in Interiors.floors().slice(0, 4):
		holes.append(Vector4((r as Rect2).position.x, (r as Rect2).position.y, (r as Rect2).size.x, (r as Rect2).size.y))
	for mesh in _tile_meshes:
		for i in (mesh as ArrayMesh).get_surface_count():
			var m := (mesh as ArrayMesh).surface_get_material(i) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("holes", holes)
				m.set_shader_parameter("hole_count", holes.size())


## Builds the MultiMeshes of one kind of scenery again from its list (after the list changed).
func _rebuild_kind(kind: String) -> void:
	var t: Dictionary = templates[kind]
	var parent: Node3D = t["parent"]
	for m in t["mmis"]:
		if is_instance_valid(m):
			main.nature._seasonal.erase(m)
			parent.remove_child(m)
			m.queue_free()
	t["mmis"] = []
	var groups := {} # name -> [centre, [El, ...]]
	for e in scenery[kind]:
		var el := e as El
		var gname := "Trees_" + kind.substr(5)
		var centre := Vector3.ZERO
		if not t["tree"]:
			var cell := Vector2i(floori(el.xf.origin.x / Nature.CELL), floori(el.xf.origin.z / Nature.CELL))
			gname = "%s_%d_%d" % [kind, cell.x, cell.y]
			centre = Vector3((cell.x + 0.5) * Nature.CELL, 0.0, (cell.y + 0.5) * Nature.CELL)
		if not groups.has(gname):
			groups[gname] = [centre, []]
		groups[gname][1].append(el)
	for gname in groups:
		var list: Array = groups[gname][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = t["tree"]
		mm.mesh = t["mesh"]
		mm.instance_count = list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = gname
		mmi.multimesh = mm
		mmi.position = groups[gname][0]
		mmi.cast_shadow = t["shadow"]
		if float(t["view"]) > 0.0:
			mmi.visibility_range_end = t["view"]
			mmi.visibility_range_end_margin = t["margin"]
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		parent.add_child(mmi)
		if t["seasonal"]:
			main.nature._seasonal.append(mmi)
			mmi.visible = main.nature._season_shown != "Winter"
		t["mmis"].append(mmi)
		for i in list.size():
			var el := list[i] as El
			el.mmi = mmi
			el.idx = i
			if t["tree"]:
				mm.set_instance_color(i, el.tint)
			_apply(el)


## The obstacle rects a thing makes where it stands now.
func _block_rects(el: El) -> Array:
	var out: Array = []
	var o := Vector2(el.xf.origin.x, el.xf.origin.z)
	if el.scenery:
		if not Nature.WALK.has_point(o):
			return out
		var s: Vector3 = el.xf.basis.get_scale()
		if el.kind.begins_with("tree_"):
			out.append(Rect2(o.x - 0.35, o.y - 0.35, 0.7, 0.7))
		elif el.kind == "hedge":
			out.append(_turned(Rect2(-1.0 * s.x, -0.45, 2.0 * s.x, 0.9), _yaw(el.xf), o))
		elif el.kind == "fence_picket":
			out.append(_turned(Rect2(-0.5 * s.x, -0.12, 1.0 * s.x, 0.24), _yaw(el.xf), o))
		elif el.kind.begins_with("rock_"):
			for k in Nature.ROCKS.values():
				if k[0] == el.kind:
					out.append(Rect2(o.x - float(k[2]) * s.x, o.y - float(k[3]) * s.x, float(k[2]) * s.x * 2.0, float(k[3]) * s.x * 2.0))
		elif not _starts(el.kind, SOFT) and el.bounds.size.y * s.y > 0.5:
			# any other solid model: the box round its footprint
			var b := el.bounds
			out.append(_turned(Rect2(b.position.x * s.x, b.position.z * s.z, b.size.x * s.x, b.size.z * s.z), _yaw(el.xf), o))
		return out
	var turn := _yaw(el.xf) - _yaw(el.base)
	var f := _size_of(el)
	for r in el.block_local:
		out.append(_turned(Rect2((r as Rect2).position * f, (r as Rect2).size * f), turn, o))
	return out


## How big a thing is now: scenery against its model, anything else against how the code built it.
static func _size_of(el: El) -> float:
	var s: float = el.xf.basis.get_scale().x
	return s if el.scenery else s / maxf(el.base.basis.get_scale().x, 0.0001)


static func _starts(kind: String, prefixes: Array) -> bool:
	for p in prefixes:
		if kind.begins_with(p):
			return true
	return false


## A ground rect (x, z) turned about the origin by `yaw`, then moved to `o`: the box around it.
static func _turned(r: Rect2, yaw: float, o: Vector2) -> Rect2:
	var c := cos(yaw)
	var s := sin(yaw)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var q := Vector2(p.x * c + p.y * s, -p.x * s + p.y * c)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(o + lo, hi - lo)


## Swaps the thing's old obstacles in main.gd's lists for where it stands now. Returns every
## ground rect that changed (old and new), so the grass can be redone there.
func _reblock(el: El) -> Array:
	var changed: Array = []
	for r in el.block_world:
		main.grid_blockers.erase(r)
		main.place_blockers.erase(r)
		changed.append(r)
	el.block_world = []
	if not el.deleted:
		for r in _block_rects(el):
			el.block_world.append(r)
			main.grid_blockers.append(r)
			main.place_blockers.append(r)
			changed.append(r)
	if el.kind == "pen":
		main.place_blockers.erase(_pen_place)
		_pen_place = (main.pen_rect as Rect2).grow(0.3)
		if not el.deleted:
			main.place_blockers.append(_pen_place)
	if el.kind == "pond":
		main.pond_rect = el.block_world[0] if not el.block_world.is_empty() else Rect2()
	if el.kind == "plot" and plots_edited:
		changed.append_array(_bed_blocks)
		changed.append(BEDS)
		_sync_beds()
		changed.append_array(bed_rects())
	return changed


## Once a plot has been moved, furniture is kept off each plot rather than off the stock block.
func _sync_beds() -> void:
	main.place_blockers.erase(BEDS_NO_BUILD)
	for r in _bed_blocks:
		main.place_blockers.erase(r)
	_bed_blocks = []
	for el in els:
		if el.kind == "plot" and not el.deleted:
			var r := Rect2(el.xf.origin.x - 0.6, el.xf.origin.z - 0.6, 1.2, 1.2)
			_bed_blocks.append(r)
			main.place_blockers.append(r)


## Where no grass grows because of the pond: (x, z, radius). main.gd's grass mask asks for this.
func pond_circles() -> Array:
	if _pond == null:
		return [Vector3(2.5, -16.0, 2.55)]
	return [] if _pond.deleted else [Vector3(_pond.xf.origin.x, _pond.xf.origin.z, 2.55 * _size_of(_pond))]


## Worn earth under the crop plots (main.gd's grass mask asks for this).
func bed_rects() -> Array:
	if not plots_edited:
		return [BEDS]
	var out: Array = []
	for el in els:
		if el.kind == "plot" and not el.deleted:
			out.append(Rect2(el.xf.origin.x - 0.75, el.xf.origin.z - 0.75, 1.5, 1.5))
	return out


func _set_state(el: El, xf: Transform3D, deleted: bool) -> Array:
	el.xf = xf
	el.deleted = deleted
	_apply(el)
	return _reblock(el)


## After an edit in the running game: walking grid, grass under obstacles, the outline.
func _refresh(changed: Array) -> void:
	unsaved = true
	main._rebuild_grid()
	if not changed.is_empty():
		main._rebuild_grass(false)
		for r in changed:
			main.grass.replant((r as Rect2).grow(0.5))
	_draw_boxes()
	_show_status()


# --- the layout file ----------------------------------------------------------------------

## Reads the layout file and applies it. main.gd calls this after collect(), before it builds
## the house, the grass and the walking grid.
func load_layout() -> void:
	orphans.clear()
	unknown_scenery.clear()
	baked.clear()
	if not FileAccess.file_exists(layout_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if typeof(d) != TYPE_DICTIONARY:
		push_warning("world layout: %s isn't valid JSON, so the world is as the code builds it" % layout_path)
		return
	loaded = true
	var sc: Dictionary = d.get("scenery", {})
	var trees_changed := false
	for kind in sc:
		if not _ensure_kind(str(kind)):
			unknown_scenery[kind] = sc[kind]
			continue
		for old in scenery[kind]:
			for r in (old as El).block_world:
				main.grid_blockers.erase(r)
				main.place_blockers.erase(r)
		scenery[kind] = []
		baked[kind] = true
		for item in sc[kind]:
			var el := _scenery_from(str(kind), item)
			scenery[kind].append(el)
			if str(kind).begins_with("tree_"):
				_new_leaves(el)
				trees_changed = true
	if not baked.is_empty():
		els.assign(els.filter(func(e: El): return not (e.scenery and baked.has(e.kind))))
		for kind in baked:
			_rebuild_kind(kind)
			for el in scenery[kind]:
				els.append(el)
				_reblock(el)
	if trees_changed:
		_rebuild_litter()
	var nodes: Dictionary = d.get("nodes", {})
	for key in nodes:
		var el: El = by_key.get(key)
		var v: Dictionary = nodes[key]
		if el == null:
			orphans[key] = v
			continue
		if bool(v.get("del", false)):
			_set_state(el, el.base, true)
		else:
			var b := (Basis(Vector3.UP, deg_to_rad(float(v.get("r", 0.0)))) * el.base.basis).scaled(Vector3.ONE * float(v.get("s", 1.0)))
			_set_state(el, Transform3D(b, Vector3(float(v.get("x", el.base.origin.x)), el.base.origin.y, float(v.get("z", el.base.origin.z)))), false)
	for a in d.get("added", []):
		if Catalog.ITEMS.has(str(a.get("id", ""))):
			_add_decor(str(a["id"]), Vector3(float(a["x"]), 0, float(a["z"])), deg_to_rad(float(a.get("r", 0.0))), float(a.get("s", 1.0)))
	if not orphans.is_empty() or not unknown_scenery.is_empty():
		push_warning("world layout: %d saved changes match nothing in the world now (kept in the file): %s" % [orphans.size() + unknown_scenery.size(), ", ".join(orphans.keys() + unknown_scenery.keys())])
	if d.has("roads"):
		_load_roads(d["roads"])
	house_list = d.get("house", [])
	unsaved = false


## Her furniture as it stands now, for the layout's "house" list: what a new game starts with.
func home_now() -> Array:
	var out: Array = []
	for f in main.furniture:
		if is_instance_valid(f):
			out.append(main.furniture_entry(f))
	return out


func _scenery_from(kind: String, item: Array) -> El:
	var el := El.new()
	el.kind = kind
	el.title = TITLES.get(kind, kind.capitalize())
	el.scenery = true
	var b := Basis(Vector3.UP, deg_to_rad(float(item[3]))) * Basis.from_scale(Vector3(float(item[4]), float(item[5]), float(item[6])))
	el.base = Transform3D(b, Vector3(float(item[0]), float(item[1]), float(item[2])))
	el.xf = el.base
	if item.size() >= 10:
		el.tint = Color(float(item[7]), float(item[8]), float(item[9]))
	el.bounds = (templates[kind]["mesh"] as Mesh).get_aabb()
	_measure(el)
	return el


func _item_of(el: El) -> Array:
	var s: Vector3 = el.xf.basis.get_scale()
	var o := el.xf.origin
	var item: Array = [snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001), snappedf(rad_to_deg(_yaw(el.xf)), 0.01),
		snappedf(s.x, 0.001), snappedf(s.y, 0.001), snappedf(s.z, 0.001)]
	if el.kind.begins_with("tree_"):
		item.append_array([snappedf(el.tint.r, 0.001), snappedf(el.tint.g, 0.001), snappedf(el.tint.b, 0.001)])
	return item


## What the layout file would hold now.
func layout() -> Dictionary:
	var nodes := orphans.duplicate()
	var added: Array = []
	for el in els:
		if el.scenery or el.home:
			continue
		var o := el.xf.origin
		if el.added:
			if not el.deleted:
				var a := {"id": str(el.node.get("item_id")), "x": snappedf(o.x, 0.001), "z": snappedf(o.z, 0.001), "r": snappedf(rad_to_deg(_yaw(el.xf)), 0.01)}
				if absf(_size_of(el) - 1.0) > 0.0005:
					a["s"] = snappedf(_size_of(el), 0.001)
				added.append(a)
		elif el.deleted:
			nodes[el.key] = {"del": true}
		elif not el.xf.is_equal_approx(el.base):
			nodes[el.key] = {"x": snappedf(o.x, 0.001), "z": snappedf(o.z, 0.001), "r": snappedf(rad_to_deg(angle_difference(_yaw(el.base), _yaw(el.xf))), 0.01)}
			if absf(_size_of(el) - 1.0) > 0.0005:
				nodes[el.key]["s"] = snappedf(_size_of(el), 0.001) # its size, as a multiple of how the code builds it
	var sc := unknown_scenery.duplicate()
	for kind in baked:
		var list: Array = []
		for el in scenery[kind]:
			if not (el as El).deleted:
				list.append(_item_of(el))
		sc[kind] = list
	var d := {"version": 1, "nodes": nodes, "added": added, "scenery": sc}
	if home_edited:
		d["house"] = home_now()
	elif not house_list.is_empty():
		d["house"] = house_list
	if roads_on:
		var r := Grass.REGION
		d["roads"] = {"px": ROAD_PX, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "png": Marshalls.raw_to_base64(road_img.save_png_to_buffer())}
	return d


## Writes the layout file: one line per thing, so a change shows up as a small diff.
func save_layout() -> bool:
	var d := layout()
	var lines: Array[String] = ['\t"version": 1']
	for section in ["nodes", "scenery"]:
		var rows: Array[String] = []
		var keys: Array = (d[section] as Dictionary).keys()
		keys.sort()
		for k in keys:
			rows.append("\t\t%s: %s" % [JSON.stringify(k), JSON.stringify(d[section][k])])
		lines.append('\t"%s": {%s}' % [section, "" if rows.is_empty() else "\n" + ",\n".join(rows) + "\n\t"])
	var arows: Array[String] = []
	for a in d["added"]:
		arows.append("\t\t" + JSON.stringify(a))
	lines.append('\t"added": [%s]' % ("" if arows.is_empty() else "\n" + ",\n".join(arows) + "\n\t"))
	if d.has("house"):
		var hrows: Array[String] = []
		for h in d["house"]:
			hrows.append("\t\t" + JSON.stringify(h))
		lines.append('\t"house": [%s]' % ("" if hrows.is_empty() else "\n" + ",\n".join(hrows) + "\n\t"))
	if d.has("roads"):
		lines.append('\t"roads": ' + JSON.stringify(d["roads"]))
	var fa := FileAccess.open(layout_path, FileAccess.WRITE)
	if fa == null:
		push_warning("world layout: can't write %s" % layout_path)
		return false
	fa.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	fa.close()
	unsaved = false
	return true


## Throws the saved layout away and builds the world again as the code makes it.
func reset_world() -> void:
	if FileAccess.file_exists(layout_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(layout_path))
	unsaved = false
	set_active(false)
	main._save_game()
	Engine.set_meta("ke_skip_title", true)
	get_tree().reload_current_scene()


# --- editing ------------------------------------------------------------------------------

func set_active(on: bool) -> void:
	if on == active or (on and not is_admin()):
		return
	active = on
	if on:
		sync_home()
		if _ui == null:
			_build_ui()
		main.set_mode(main.Mode.LIVE)
		main.player.cancel_activity()
		main._set_cam_lock(false)
		main.hud.hide_menu()
		main.hud.settings_panel.visible = false
		_time_was = Game.time_running
		Game.time_running = false
		_hidden.clear()
		for c in main.hud.chrome:
			if c.visible:
				_hidden.append(c)
				c.visible = false
		_ui.visible = true
		_ui.move_to_front()
		set_tool("select")
		main.hud.show_toast("World editor: click anything to pick it up and drag it. R turns it, Delete removes it.")
	else:
		_end_stroke()
		_end_stream()
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		_drag = {}
		select(null)
		hover = null
		_draw_boxes()
		_ring.visible = false
		_ui.visible = false
		for c in _hidden:
			if is_instance_valid(c):
				c.visible = true
		_hidden.clear()
		Game.time_running = _time_was
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if unsaved and save_layout():
			main.hud.show_toast("World layout saved.")
	_show_status()


## Closing the window while editing keeps the work.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and active and unsaved:
		save_layout()


func cam_bounds() -> Rect2:
	return ROAM


func set_tool(t: String) -> void:
	_end_stroke()
	_end_stream()
	tool = t
	for k in _tool_btns:
		(_tool_btns[k] as Button).set_pressed_no_signal(k == t)
	if t == "place" and place_id == "":
		place_id = str(place_options()[0][0])
	if t != "select":
		select(null)
		hover = null
		_draw_boxes()
	if _ring != null:
		_ring.visible = t != "select" and t != "place" # the Place tool shows the thing itself instead
	_make_ghost()
	_draw_ring()
	_show_status()


func select(el: El) -> void:
	selected = el
	_draw_boxes()
	_show_status()


## What's under the pointer: the nearest thing whose own triangles the click hits, else whatever
## stands right by the spot on the ground (thin things like lamp posts are hard to hit exactly).
## The nearest thing under the mouse whose kind starts with `prefix` ("tree_" for the axe), or
## null. Unlike pick() it never falls back to whatever is near the ground point.
func pick_kind(mpos: Vector2, prefix: String) -> El:
	var from: Vector3 = main.cam.project_ray_origin(mpos)
	var dir: Vector3 = main.cam.project_ray_normal(mpos)
	var best: El = null
	var best_t := INF
	for el in els:
		if el.deleted or not el.kind.begins_with(prefix):
			continue
		var to_c: Vector3 = el.xf * el.bounds.get_center() - from
		var along := to_c.dot(dir)
		if along < 0.0 or (to_c - dir * along).length_squared() > el.radius * el.radius:
			continue
		var inv := el.xf.affine_inverse()
		var hit: Dictionary = _triangles(el).intersect_segment(inv * from, inv * (from + dir * 400.0))
		if hit.is_empty():
			continue
		var t := (el.xf * (hit["position"] as Vector3) - from).dot(dir)
		if t < best_t:
			best_t = t
			best = el
	return best


func pick(mpos: Vector2) -> El:
	var from: Vector3 = main.cam.project_ray_origin(mpos)
	var dir: Vector3 = main.cam.project_ray_normal(mpos)
	var best: El = null
	var best_t := INF
	for el in els:
		if el.deleted or (not small_on and SMALL.has(el.kind)):
			continue
		var to_c: Vector3 = el.xf * el.bounds.get_center() - from
		var along := to_c.dot(dir)
		if along < 0.0 or (to_c - dir * along).length_squared() > el.radius * el.radius:
			continue
		var inv := el.xf.affine_inverse()
		var hit: Dictionary = _triangles(el).intersect_segment(inv * from, inv * (from + dir * 400.0))
		if hit.is_empty():
			continue
		var t := (el.xf * (hit["position"] as Vector3) - from).dot(dir)
		if t < best_t:
			best_t = t
			best = el
	if best != null:
		return best
	var g = main._ground_point(mpos)
	if g == null:
		return null
	var best_d := INF
	for el in els:
		if el.deleted or (not small_on and SMALL.has(el.kind)):
			continue
		var d := Vector2(el.xf.origin.x - g.x, el.xf.origin.z - g.z).length()
		var s: Vector3 = el.xf.basis.get_scale()
		var reach := clampf(Vector2(el.bounds.size.x * s.x, el.bounds.size.z * s.z).length() * 0.18, 0.3, 0.9)
		if d < reach and d < best_d:
			best_d = d
			best = el
	return best


func _triangles(el: El) -> TriangleMesh:
	if el.scenery:
		var mesh: Mesh = el.mmi.multimesh.mesh
		if not _tri_cache.has(mesh):
			_tri_cache[mesh] = mesh.generate_triangle_mesh()
		return _tri_cache[mesh]
	if el.tri == null:
		var faces := PackedVector3Array()
		var inv: Transform3D = el.node.global_transform.affine_inverse()
		for mi in el.node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh != null and m.visible:
				faces.append_array((inv * m.global_transform) * m.mesh.get_faces())
		el.tri = TriangleMesh.new()
		if faces.size() >= 3:
			el.tri.create_from_faces(faces)
	return el.tri


## Mouse events from main.gd while the editor is on. True = the editor used it.
func handle_mouse(e: InputEvent) -> bool:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			press(mb.position)
		else:
			release()
		return true
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0 and (_painting or not _drag.is_empty() or not _stream.is_empty()):
			release() # the button came up over the toolbar, where the editor never saw it
		move(mm.position, mm.shift_pressed)
		return not main.drag_pan # a right-drag still pans the camera
	return false


func press(mpos: Vector2) -> void:
	_mouse = mpos
	_end_stroke()
	_end_stream()
	_drag = {}
	if tool == "place":
		var spot = main._ground_point(mpos)
		if spot != null:
			# one now; holding the button and moving streams more (move), letting go ends it (release)
			_stream = {"from": spot, "last": spot, "els": [], "changed": []}
			var first := _place_one(spot, _stream["changed"])
			if first != null:
				_stream["els"].append(first)
		return
	if tool != "select":
		_begin_stroke(mpos)
		return
	var el := pick(mpos)
	select(el)
	var g = main._ground_point(mpos)
	if el != null and g != null:
		_drag = {"el": el, "from": el.xf, "grab": Vector3(g.x - el.xf.origin.x, 0, g.z - el.xf.origin.z), "moved": false}


func move(mpos: Vector2, snap := false) -> void:
	_mouse = mpos
	_mouse_moved = true
	if tool == "place":
		var g = main._ground_point(mpos)
		if g != null:
			if _stream.is_empty():
				_move_ghost(g)
			else:
				_stream_to(g, snap)
	elif _painting:
		var g = main._ground_point(mpos)
		if g != null:
			_stroke_to(g, snap)
	elif not _drag.is_empty():
		var g = main._ground_point(mpos)
		if g == null:
			return
		var el: El = _drag["el"]
		var grab: Vector3 = _drag["grab"]
		var p := Vector3(g.x - grab.x, el.xf.origin.y, g.z - grab.z)
		if snap:
			p.x = snappedf(p.x, 0.25)
			p.z = snappedf(p.z, 0.25)
		el.xf.origin = p
		_drag["moved"] = true
		_apply(el)
		_draw_boxes()
	if tool != "select":
		_draw_ring()


func release() -> void:
	_end_stream()
	if _painting:
		_end_stroke()
	elif not _drag.is_empty():
		var el: El = _drag["el"]
		var from: Transform3D = _drag["from"]
		var moved: bool = _drag["moved"] and not el.xf.is_equal_approx(from)
		_drag = {}
		if moved:
			_edited(el, from, false)


## Records a change to a thing (for undo), then brings obstacles, grass and the grid up to date.
func _edited(el: El, from: Transform3D, was_deleted: bool) -> void:
	undo_stack.append(["state", el, from, was_deleted])
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	if el.scenery:
		baked[el.kind] = true
	_apply(el)
	_refresh(_reblock(el))


func rotate_selected(degrees: float) -> void:
	if selected == null or selected.deleted:
		return
	var from := selected.xf
	if selected.kind == "pen":
		degrees = signf(degrees) * 90.0 # the sheep's field is square to the map, so the pen turns in quarter turns
	selected.xf.basis = Basis(Vector3.UP, deg_to_rad(degrees)) * selected.xf.basis
	_edited(selected, from, false)


func delete_selected() -> void:
	if selected == null or selected.deleted:
		return
	var el := selected
	el.deleted = true
	select(null)
	_edited(el, el.xf, false)
	main.hud.show_toast("Deleted the %s. Undo brings it back." % el.title.to_lower())


## A copy of the selected thing, set down beside it and selected. Scenery, and the lamp posts,
## benches and other decor from the catalog, can be copied; one-off buildings can't.
func duplicate_selected() -> El:
	if selected == null or selected.deleted:
		return null
	var src := selected
	var right := Vector3(cos(main.cam_yaw), 0, -sin(main.cam_yaw))
	var at := src.xf.origin + right * clampf(src.radius * 0.8, 0.6, 3.0)
	var el: El
	if src.scenery:
		el = _add_scenery(src.kind, Transform3D(src.xf.basis, at), src.tint)
	elif src.home:
		el = _add_home(str(src.node.get("item_id")), at, _yaw(src.xf), src.xf.basis.get_scale().x)
	elif src.node is Furniture:
		el = _add_decor(str(src.node.get("item_id")), at, _yaw(src.xf), _size_of(src))
	else:
		main.hud.show_toast("The %s is one of a kind: it can be moved, turned or deleted, not copied." % src.title.to_lower())
		return null
	undo_stack.append(["add", [el]])
	_refresh(_reblock(el))
	select(el)
	return el


## One more of a kind of scenery, where `xf` says.
func _add_scenery(kind: String, xf: Transform3D, tint := Color.WHITE) -> El:
	var el := El.new()
	el.kind = kind
	el.title = TITLES.get(kind, kind.capitalize())
	el.scenery = true
	el.tint = tint
	el.bounds = (templates[kind]["mesh"] as Mesh).get_aabb()
	el.base = xf
	el.xf = xf
	_measure(el)
	els.append(el)
	scenery[kind].append(el)
	baked[kind] = true
	if kind.begins_with("tree_"):
		_new_leaves(el)
	_rebuild_kind(kind)
	if kind.begins_with("tree_"):
		_rebuild_litter()
	return el


## Makes sure a kind of scenery can be drawn: the ones the code scatters already can; any other
## model in assets/props gets its own MultiMeshes the first time it's needed.
func _ensure_kind(kind: String) -> bool:
	if templates.has(kind):
		return true
	var mesh: ArrayMesh = main.nature._mesh(kind)
	if mesh == null:
		return false
	templates[kind] = {"parent": main.nature, "mesh": mesh, "shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "view": 90.0,
		"margin": 6.0, "seasonal": false, "tree": false, "mmis": []}
	scenery[kind] = []
	return true


## Everything the Place tool can set down, as [id, name, group]: every kind of scenery and every
## model in assets/props ("scenery:<model>"), and every catalog piece ("decor:<id>").
func place_options() -> Array:
	var models := {}
	for kind in templates:
		models[kind] = true
	var in_catalog := {}
	for id in Catalog.ITEMS:
		in_catalog[str(Catalog.ITEMS[id].get("model", "")).get_file().get_basename()] = true
	for f in DirAccess.get_files_at(Nature.P):
		var m := f.get_basename()
		if f.ends_with(".glb") and not _starts(m, NOT_PLACED) and not in_catalog.has(m):
			models[m] = true
	var out: Array = []
	var names: Array = models.keys()
	names.sort()
	for group in [["Trees", ["tree_", "maple_"]], ["Rocks", ["rock_"]], ["Plants", ["bush_", "tuft_", "flowers_", "clover"]], ["Leaves", ["leaf_"]], ["Hedges and fences", ["hedge", "fence_"]]]:
		for m in names:
			if _starts(m, group[1]):
				out.append(["scenery:" + m, TITLES.get(m, str(m).capitalize()), group[0]])
				models.erase(m)
				for small in SMALL_OPTIONS:
					if small[0] == m:
						out.append(["scenery:%s:%s" % [m, str(small[1])], small[2], group[0]])
	var decor: Array = []
	for id in Catalog.ITEMS:
		if Catalog.has_builder(id):
			decor.append(["decor:" + str(id), str(Catalog.ITEMS[id]["name"]), "Furniture and decor"])
	decor.sort_custom(func(a, b): return str(a[1]) < str(b[1]))
	out.append_array(decor)
	for m in names:
		if models.has(m):
			out.append(["scenery:" + m, TITLES.get(m, str(m).capitalize()), "Other models"])
	return out


## Sets one of the chosen thing down at a spot on the ground (the Place tool), and selects it.
func place(at: Vector3) -> El:
	var changed: Array = []
	var el := _place_one(at, changed)
	if el != null:
		undo_stack.append(["add", [el]])
		_refresh(changed)
	return el


## Sets one down as the preview shows it (its turn and size). The ground rects that changed are
## added to `changed`; the caller brings the grid and the grass up to date and records the undo.
func _place_one(at: Vector3, changed: Array) -> El:
	if place_id == "":
		place_id = str(place_options()[0][0])
	if place_id != _size_for:
		_next_look() # a different thing than the preview was made for: start from its own size
	var what := place_id.get_slice(":", 1)
	var el: El
	if place_id.begins_with("decor:"):
		if not Catalog.ITEMS.has(what):
			return null
		if main.interior_rect().has_point(Vector2(at.x, at.z)):
			el = _add_home(what, Vector3(at.x, 0, at.z), _ghost_yaw, _ghost_scale) # into her house: it's hers
		else:
			el = _add_decor(what, Vector3(at.x, 0, at.z), _ghost_yaw, _ghost_scale)
	else:
		if not _ensure_kind(what):
			main.hud.show_toast("There's no model for that.")
			return null
		el = _add_scenery(what, _ghost_xf(at))
	changed.append_array(_reblock(el))
	_next_look()
	_move_ghost(at)
	return el


## Where the thing being placed would stand at a spot, with the preview's turn and size.
func _ghost_xf(at: Vector3) -> Transform3D:
	var y := -0.03 * _ghost_scale if place_id.begins_with("scenery:rock_") else 0.0
	return Transform3D(Basis(Vector3.UP, _ghost_yaw).scaled(Vector3.ONE * _ghost_scale), Vector3(at.x, y, at.z))


## Natural scenery (trees, rocks, plants, leaves) gets a new turn and size for each one set down,
## as the code scatters it; everything else keeps the turn it was given with R and T.
func _next_look() -> void:
	if place_id != _size_for:
		# a new choice starts at its own size: 1, or what a "(small)" entry names
		_size_for = place_id
		place_size = float(place_id.get_slice(":", 2)) if place_id.get_slice_count(":") > 2 else 1.0
	if place_id.begins_with("scenery:") and _starts(place_id.get_slice(":", 1), NATURAL):
		_ghost_yaw = randf() * TAU
		_ghost_scale = place_size * randf_range(0.9, 1.15)
	else:
		_ghost_scale = place_size


## Builds the Place tool's preview: the chosen thing itself, see-through with a green outline.
func _make_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if not active or tool != "place" or place_id == "":
		return
	var what := place_id.get_slice(":", 1)
	if place_id.begins_with("decor:"):
		if not Catalog.ITEMS.has(what):
			return
		var f := Furniture.new()
		add_child(f)
		f.setup(what, 0)
		f.set_ghost(true)
		_ghost = f
	else:
		if not _ensure_kind(what):
			return
		var mi := MeshInstance3D.new()
		mi.mesh = templates[what]["mesh"]
		mi.transparency = 0.25
		add_child(mi)
		_ghost = mi
	if _ghost_mat == null:
		# an outline: the model again, a little fatter, back faces only, plain green
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4)
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_ghost_mat.grow = true
		_ghost_mat.grow_amount = 0.03
	var meshes: Array = _ghost.find_children("*", "MeshInstance3D", true, false)
	if _ghost is MeshInstance3D:
		meshes.append(_ghost)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = _ghost_mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_yaw = 0.0
	_next_look()
	var g = main._ground_point(_mouse)
	_move_ghost(g if g != null else main.cam_target)


func _move_ghost(at: Vector3) -> void:
	if _ghost != null:
		_ghost.global_transform = _ghost_xf(at)


## R turns left and T turns right: the preview while placing, otherwise the selected thing.
func turn(degrees: float) -> void:
	if tool == "place":
		_ghost_yaw += deg_to_rad(degrees)
		if _ghost != null:
			_move_ghost(_ghost.global_position)
	else:
		rotate_selected(degrees)


## + makes it bigger and - smaller: the preview (and all that follow) while placing, otherwise
## the selected thing.
func resize(factor: float) -> void:
	if tool == "place":
		var to := clampf(place_size * factor, SIZE_MIN, SIZE_MAX)
		_ghost_scale *= to / place_size
		place_size = to
		if _ghost != null:
			_move_ghost(_ghost.global_position)
		_show_status()
	else:
		resize_selected(factor)


func resize_selected(factor: float) -> void:
	if selected == null or selected.deleted:
		return
	if selected.kind == "pen":
		main.hud.show_toast("The sheep pen keeps its size: the sheep's field is tied to it.")
		return
	var now := _size_of(selected)
	var f := clampf(now * factor, SIZE_MIN, SIZE_MAX) / now
	if absf(f - 1.0) < 0.0001:
		return
	var from := selected.xf
	selected.xf.basis = selected.xf.basis.scaled(Vector3.ONE * f)
	if selected.kind.begins_with("rock_"):
		selected.xf.origin.y = -0.03 * _size_of(selected) # rocks sit a little into the ground
	_measure(selected)
	_edited(selected, from, false)


## How far apart a stream sets things down along `dir`: the length of the thing's footprint that
## way, so fences and hedges dragged along their length join end to end.
func _stream_spacing(dir: Vector2) -> float:
	var size := Vector2(0.5, 0.5)
	var what := place_id.get_slice(":", 1)
	if place_id.begins_with("decor:"):
		size = (Catalog.ITEMS[what]["size"] as Vector2) * _ghost_scale
	elif templates.has(what):
		var b: AABB = (templates[what]["mesh"] as Mesh).get_aabb()
		size = Vector2(b.size.x, b.size.z) * _ghost_scale
	var along := Vector2(cos(_ghost_yaw), -sin(_ghost_yaw)) # the thing's own x axis on the ground
	var c := absf(dir.dot(along))
	var s := sqrt(maxf(0.0, 1.0 - c * c))
	return maxf(0.15, size.x * c + size.y * s)


## Click and hold with the Place tool: one more each time the pointer has gone a footprint
## further. Shift keeps the stream on a straight line (snapped to 45 degrees) from where it began.
func _stream_to(g: Vector3, straight: bool) -> void:
	var from: Vector3 = _stream["from"]
	if straight:
		var d := Vector2(g.x - from.x, g.z - from.z)
		if d.length() < 0.05:
			return
		var dir := Vector2.from_angle(snappedf(d.angle(), PI / 4.0))
		g = from + Vector3(dir.x, 0, dir.y) * maxf(d.dot(dir), 0.0)
	var natural := place_id.begins_with("scenery:") and _starts(place_id.get_slice(":", 1), NATURAL)
	for i in 200:
		var last: Vector3 = _stream["last"]
		var to := Vector3(g.x - last.x, 0, g.z - last.z)
		var dir2 := Vector2(to.x, to.z).normalized()
		var gap := _stream_spacing(dir2) * (0.9 if natural else 1.0)
		if to.length() < gap:
			break
		var next := last + Vector3(dir2.x, 0, dir2.y) * gap
		_stream["last"] = next
		var at := next
		if natural and not straight:
			at += Vector3(-dir2.y, 0, dir2.x) * randf_range(-0.3, 0.3) * gap # a loose line, not a ruled one
		var el := _place_one(at, _stream["changed"])
		if el == null:
			break
		_stream["els"].append(el)
	_move_ghost(g)


func _end_stream() -> void:
	if _stream.is_empty():
		return
	var s := _stream
	_stream = {}
	if not (s["els"] as Array).is_empty():
		undo_stack.append(["add", s["els"]])
		if undo_stack.size() > 80:
			undo_stack.pop_front()
		_refresh(s["changed"])


func _add_decor(id: String, at: Vector3, yaw: float, size := 1.0) -> El:
	main._decor(id, at, 0)
	var f: Furniture = main.decor[-1]
	var el := _collect_node(f, "decor_" + id, f.display_name(), [] if f.is_flat() else [f.footprint()])
	el.added = true
	_set_state(el, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at), false)
	_measure(el)
	return el


## One more piece of her furniture (a copy, or a catalog piece set down in the house).
func _add_home(id: String, at: Vector3, yaw: float, size := 1.0) -> El:
	var f: Furniture = main._spawn_furniture(id, at, posmod(roundi(yaw / (PI * 0.5)), 4))
	var el := _collect_node(f, "home_" + id, f.display_name(), [])
	el.home = true
	el.added = true
	_home[f] = el
	_set_state(el, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at), false)
	_measure(el)
	return el


func undo() -> void:
	_end_stroke()
	if undo_stack.is_empty():
		main.hud.show_toast("Nothing to undo.")
		return
	var u: Array = undo_stack.pop_back()
	match str(u[0]):
		"state":
			_refresh(_set_state(u[1], u[2], u[3]))
			select(null if u[3] else u[1])
		"add":
			# one thing, or everything a held click streamed out
			var changed: Array = []
			for e in u[1]:
				var el := e as El
				if selected == el:
					select(null)
				changed.append_array(_set_state(el, el.xf, true))
			_refresh(changed)
		"roads":
			road_img.set_data(road_img.get_width(), road_img.get_height(), false, Image.FORMAT_RGB8, u[1])
			for el in u[2]:
				(el as El).deleted = false
				_apply(el)
			_roads_changed(Grass.REGION)


## Keys from main.gd while the editor is on. True = the editor used it.
func handle_key(kc: Key, k: InputEventKey) -> bool:
	var cmd := k.is_command_or_control_pressed()
	match kc:
		KEY_R:
			turn(TURN_STEP) # left
		KEY_T:
			turn(-TURN_STEP) # right
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			if cmd:
				return false
			resize(SIZE_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			if cmd:
				return false
			resize(1.0 / SIZE_STEP)
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			delete_selected()
		KEY_Z:
			if cmd:
				undo()
		KEY_D:
			if not cmd:
				return false # D pans the camera
			duplicate_selected()
		KEY_S:
			if not cmd:
				return false
			if save_layout():
				main.hud.show_toast("World layout saved.")
		KEY_BRACKETLEFT:
			set_brush(brush - maxf(0.2, brush * 0.15))
		KEY_BRACKETRIGHT:
			set_brush(brush + maxf(0.2, brush * 0.15))
		KEY_ESCAPE:
			if tool != "select":
				set_tool("select")
			else:
				select(null)
		KEY_B, KEY_SPACE, KEY_C:
			pass # no build mode, camera lock or wall toggle while editing
		_:
			return false
	return true


func set_brush(r: float) -> void:
	brush = clampf(r, 0.3, BRUSH_MAX)
	if _brush_slider != null:
		_brush_slider.set_value_no_signal(brush)
		_brush_label.text = "%.1f m" % (brush * 2.0)
	_draw_ring()


func set_brush_square(on: bool) -> void:
	brush_square = on
	if _shape_btn != null:
		_shape_btn.text = "Square brush" if on else "Round brush"
	_draw_ring()


func _process(delta: float) -> void:
	if not active:
		return
	if _mask_dirty:
		_mask_t -= delta
		if _mask_t <= 0.0:
			_mask_t = 0.12
			_mask_dirty = false
			main._rebuild_grass(false)
	if _mouse_moved and _drag.is_empty() and not _painting and tool == "select":
		_mouse_moved = false
		var h := pick(_mouse)
		if h != hover:
			hover = h
			_draw_boxes()
			Input.set_default_cursor_shape(Input.CURSOR_DRAG if h != null else Input.CURSOR_ARROW)


# --- roads --------------------------------------------------------------------------------

## Switches the world's paths and paving over to the painted map. With `seed`, the map starts
## as the paths and cobbles the code builds, so they can be added to or rubbed out.
func _enable_roads(seed: bool) -> void:
	if roads_on:
		return
	roads_on = true
	var size := Vector2i(Grass.REGION.size * ROAD_PX)
	road_img = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	if seed:
		for r in World.PATHS:
			road_img.fill_rect(_px_rect(r), ROAD_COLOURS["dirt"])
		for i in Town.PATHS.size():
			if not Town.COBBLE_PATHS.has(i):
				road_img.fill_rect(_px_rect(Town.PATHS[i]), ROAD_COLOURS["dirt"])
		for i in Town.COBBLE_PATHS:
			road_img.fill_rect(_px_rect(Town.PATHS[i]), ROAD_COLOURS["cobble"])
		road_img.fill_rect(_px_rect(Town.PLAZA), ROAD_COLOURS["cobble"])
	_show_roads()


func _show_roads() -> void:
	road_tex = ImageTexture.create_from_image(road_img)
	var r := Grass.REGION
	var rect := Vector4(r.position.x, r.position.y, r.size.x, r.size.y)
	main.grass.ground_mat.set_shader_parameter("roads", road_tex)
	main.grass.ground_mat.set_shader_parameter("roads_rect", rect)
	# the cobbles the code laid give way to tiles that follow the painted map
	for c in main.get_children():
		if str(c.name).begins_with("Cobbles_"):
			main.remove_child(c)
			c.queue_free()
	if _tile_meshes.is_empty():
		for path in Town.COBBLE_TILES["plaza"]:
			if not ResourceLoader.exists(path):
				continue
			var inst := (load(path) as PackedScene).instantiate()
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var mesh := ((mi as MeshInstance3D).mesh as ArrayMesh).duplicate() as ArrayMesh
				for i in mesh.get_surface_count():
					var sm := mesh.surface_get_material(i) as BaseMaterial3D
					if sm == null or sm.albedo_texture == null:
						continue
					var m := ShaderMaterial.new()
					m.shader = preload("res://shaders/cobble_painted.gdshader")
					m.set_shader_parameter("albedo_tex", sm.albedo_texture)
					m.set_shader_parameter("use_normal", 1.0 if sm.normal_texture != null else 0.0)
					if sm.normal_texture != null:
						m.set_shader_parameter("normal_tex", sm.normal_texture)
						m.set_shader_parameter("normal_depth", sm.normal_scale)
					m.set_shader_parameter("roughness", sm.roughness)
					mesh.surface_set_material(i, m)
				_tile_meshes.append(mesh)
				break
			inst.free()
	for mesh in _tile_meshes:
		for i in (mesh as ArrayMesh).get_surface_count():
			var m := (mesh as ArrayMesh).surface_get_material(i) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("roads", road_tex)
				m.set_shader_parameter("roads_rect", rect)
	_tiles.clear()
	_retile(Grass.REGION)


func _load_roads(d: Dictionary) -> void:
	var img := Image.new()
	var size := Vector2i(Grass.REGION.size * ROAD_PX)
	if img.load_png_from_buffer(Marshalls.base64_to_raw(str(d.get("png", "")))) != OK or img.get_size() != size:
		push_warning("world layout: the saved roads don't fit this map, so the code's own paths are used")
		return
	img.convert(Image.FORMAT_RGB8)
	_enable_roads(false)
	road_img = img
	_show_roads()


func _px_rect(r: Rect2) -> Rect2i:
	return Rect2i(Vector2i(((r.position - Grass.REGION.position) * ROAD_PX).round()), Vector2i((r.size * ROAD_PX).round()))


## What's painted at a spot: "dirt", "gravel", "cobble" or "".
func road_at(x: float, z: float) -> String:
	if not roads_on:
		return ""
	var p := Vector2i(((Vector2(x, z) - Grass.REGION.position) * ROAD_PX).floor())
	if p.x < 0 or p.y < 0 or p.x >= road_img.get_width() or p.y >= road_img.get_height():
		return ""
	var c := road_img.get_pixelv(p)
	return "cobble" if c.b > 0.5 else ("gravel" if c.g > 0.5 else ("dirt" if c.r > 0.5 else ""))


## One round dab of the brush at a spot on the ground.
func _dab(p: Vector3) -> void:
	var c := (Vector2(p.x, p.z) - Grass.REGION.position) * ROAD_PX
	var r := brush * ROAD_PX
	var col: Color = ROAD_COLOURS.get(tool, Color(0, 0, 0))
	var w := road_img.get_width()
	var h := road_img.get_height()
	if brush_square:
		var px := Rect2i(roundi(c.x - r), roundi(c.y - r), roundi(r * 2.0), roundi(r * 2.0)).intersection(Rect2i(0, 0, w, h))
		if px.size.x > 0 and px.size.y > 0:
			road_img.fill_rect(px, col)
	else:
		for y in range(maxi(0, floori(c.y - r)), mini(h, ceili(c.y + r))):
			var dy := y + 0.5 - c.y
			if absf(dy) > r:
				continue
			var half := sqrt(r * r - dy * dy)
			var x0 := maxi(0, roundi(c.x - half))
			var x1 := mini(w, roundi(c.x + half))
			if x1 > x0:
				road_img.fill_rect(Rect2i(x0, y, x1 - x0, 1), col)
	var touched := Rect2(p.x - brush, p.z - brush, brush * 2.0, brush * 2.0)
	_stroke_rect = touched if _stroke_rect.size == Vector2.ZERO else _stroke_rect.merge(touched)


func _begin_stroke(mpos: Vector2) -> void:
	var g = main._ground_point(mpos)
	if g == null:
		return
	_enable_roads(true)
	_painting = true
	_line_on = false
	_stroke_before = road_img.get_data()
	_stroke_rect = Rect2()
	_last_dab = g
	_dab(g)
	_stroke_shown(Rect2(g.x - brush, g.z - brush, brush * 2.0, brush * 2.0))


## Carries the stroke on to `g`. With `straight` (Shift held) the stroke is one straight line
## from where Shift went down, along the nearest of the eight compass directions: each move
## takes the line back off the map and draws it again to the new end.
func _stroke_to(g: Vector3, straight := false) -> void:
	var step := maxf(brush * 0.35, 0.08)
	if straight:
		if not _line_on:
			_line_on = true
			_line_from = _last_dab
			_line_base = road_img.get_data()
		var d := Vector2(g.x - _line_from.x, g.z - _line_from.z)
		var end := _line_from
		if d.length() > 0.05:
			var dir := Vector2.from_angle(snappedf(d.angle(), PI / 4.0))
			end = _line_from + Vector3(dir.x, 0, dir.y) * maxf(d.dot(dir), 0.0)
		road_img.set_data(road_img.get_width(), road_img.get_height(), false, Image.FORMAT_RGB8, _line_base)
		var count := maxi(1, ceili(_line_from.distance_to(end) / step))
		for i in range(0, count + 1):
			_dab(_line_from.lerp(end, float(i) / count))
		_last_dab = end
		_stroke_shown(_stroke_rect)
		return
	_line_on = false
	var dist := _last_dab.distance_to(g)
	if dist < step:
		return
	var n := ceili(dist / step)
	var from := _last_dab
	for i in range(1, n + 1):
		_dab(from.lerp(g, float(i) / n))
	_last_dab = g
	_stroke_shown(Rect2(minf(from.x, g.x) - brush, minf(from.z, g.z) - brush, absf(g.x - from.x) + brush * 2.0, absf(g.z - from.z) + brush * 2.0))


## Shows the paint so far: the map on the ground and the tiles now; the grass mask a moment later.
func _stroke_shown(area: Rect2) -> void:
	road_tex.update(road_img)
	_retile(area)
	_mask_dirty = true


func _end_stroke() -> void:
	if not _painting:
		return
	_painting = false
	_line_on = false
	_line_base = PackedByteArray()
	# a new road clears the grass tufts, flowers and clover it was painted over
	var cleared: Array = []
	if tool != "erase":
		for el in els:
			if not el.deleted and SMALL.has(el.kind) and _stroke_rect.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)) and road_at(el.xf.origin.x, el.xf.origin.z) != "":
				el.deleted = true
				baked[el.kind] = true
				_apply(el)
				cleared.append(el)
	undo_stack.append(["roads", _stroke_before, cleared])
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	_stroke_before = PackedByteArray()
	_roads_changed(_stroke_rect)


## After the map changed in `area`: ground, tiles and grass.
func _roads_changed(area: Rect2) -> void:
	unsaved = true
	_mask_dirty = false
	road_tex.update(road_img)
	_retile(area)
	main._rebuild_grass(false)
	main.grass.replant(area)


## Lays a cobble tile on every 4 x 2 m square of `area` that has cobbles painted in it.
func _retile(area: Rect2) -> void:
	var a := area.intersection(Grass.REGION)
	if a.size.x <= 0.0 or a.size.y <= 0.0:
		return
	var c0 := Vector2i(((a.position - TILE_ORIGIN) / TILE).floor())
	var c1 := Vector2i(((a.end - TILE_ORIGIN) / TILE).floor())
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var cell := Vector2i(i, j)
			if _cell_cobbled(cell):
				if not _tiles.has(cell):
					_tiles[cell] = posmod(i * 73856093 ^ j * 19349663, 4)
			else:
				_tiles.erase(cell)
	if _tile_meshes.is_empty():
		return
	for m in _tile_mmis:
		main.remove_child(m)
		m.queue_free()
	_tile_mmis.clear()
	var lists: Array = []
	for v in _tile_meshes.size():
		lists.append([])
	for cell in _tiles:
		var centre := TILE_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE
		lists[int(_tiles[cell]) % _tile_meshes.size()].append(Transform3D(Basis.IDENTITY, Vector3(centre.x, 0, centre.y)))
	for v in lists.size():
		var list: Array = lists[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tile_meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PaintedCobbles_%d" % v
		mmi.multimesh = mm
		main.add_child(mmi)
		_tile_mmis.append(mmi)


func _cell_cobbled(cell: Vector2i) -> bool:
	var px := _px_rect(Rect2(TILE_ORIGIN + Vector2(cell) * TILE, TILE)).intersection(Rect2i(Vector2i.ZERO, road_img.get_size()))
	for y in range(px.position.y, px.end.y, 2):
		for x in range(px.position.x, px.end.x, 2):
			if road_img.get_pixel(x, y).b > 0.5:
				return true
	return false


func painted_tiles() -> int:
	return _tiles.size()


# --- outlines, brush ring and the toolbar -------------------------------------------------

func _line_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 10
	return m


func _draw_boxes() -> void:
	if _sel_box == null:
		return
	_draw_box(_sel_box, selected)
	_draw_box(_hover_box, hover if hover != selected else null)


func _draw_box(mi: MeshInstance3D, el: El) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if el == null or el.deleted:
		return
	var b := el.bounds.grow(0.03)
	var c: Array[Vector3] = []
	for i in 8:
		c.append(el.xf * b.get_endpoint(i))
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# AABB endpoints: bit 2 = x, bit 1 = y, bit 0 = z
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(c[pair[0]])
		im.surface_add_vertex(c[pair[1]])
	im.surface_end()


func _draw_ring() -> void:
	if _ring == null or not _ring.visible:
		return
	var g = main._ground_point(_mouse)
	if g == null:
		return
	if _painting and _line_on:
		g = _last_dab # a straight line: the brush is at the line's end, not under the pointer
	var im := _ring.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	if tool != "place" and brush_square:
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
			im.surface_add_vertex(Vector3(g.x + c.x * brush, 0.08, g.z + c.y * brush))
	else:
		var r := 0.35 if tool == "place" else brush
		for i in 49:
			var a := TAU * i / 48.0
			im.surface_add_vertex(Vector3(g.x + cos(a) * r, 0.08, g.z + sin(a) * r))
	im.surface_end()


func _show_status() -> void:
	if _status == null:
		return
	var s := ""
	if tool == "select":
		if selected != null:
			s = "%s selected. Drag to move (Shift snaps to 25 cm). R / T turn it, + / - resize it (now %d%%). Delete removes it, Ctrl/Cmd+D copies it." % [selected.title, roundi(_size_of(selected) * 100.0)]
		else:
			s = "Click anything to select it, then drag it. Right-drag or WASD moves the camera, the wheel zooms."
	elif tool == "place":
		s = "Click to set one down; hold and drag for a stream (Shift keeps it straight). R / T turn the preview, + / - resize it (now %d%%). Ctrl/Cmd+Z undoes." % roundi(place_size * 100.0)
	elif tool == "erase":
		s = "Drag over a road or the paving to rub it out. Hold Shift for a straight line. [ and ] change the brush size."
	else:
		s = "Drag to paint; one click leaves a single patch. Hold Shift for a straight line (it snaps to 45 degrees). [ and ] change the brush size."
	if unsaved:
		s += "   (unsaved changes)"
	_status.text = s


func _build_ui() -> void:
	_sel_box = MeshInstance3D.new()
	_sel_box.mesh = ImmediateMesh.new()
	_sel_box.material_override = _line_mat(Color(1.0, 0.85, 0.3))
	_sel_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sel_box)
	_hover_box = MeshInstance3D.new()
	_hover_box.mesh = ImmediateMesh.new()
	_hover_box.material_override = _line_mat(Color(1, 1, 1, 0.8))
	_hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hover_box)
	_ring = MeshInstance3D.new()
	_ring.mesh = ImmediateMesh.new()
	_ring.material_override = _line_mat(Color(1.0, 0.85, 0.3))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	var hud = main.hud
	_ui = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(hud._label("World editor", 18, hud.GOLD))
	for t in TOOLS:
		var id: String = t[0]
		var b: Button = hud._button(t[1], func(): set_tool(id))
		b.toggle_mode = true
		_tool_btns[id] = b
		row.add_child(b)
		if id == "place":
			# what the Place tool sets down: everything in the world, grouped
			_place_pick = OptionButton.new()
			_place_pick.focus_mode = Control.FOCUS_NONE
			_place_pick.custom_minimum_size = Vector2(190, 0)
			_place_pick.fit_to_longest_item = false
			_place_pick.clip_text = true
			var group := ""
			for o in place_options():
				if str(o[2]) != group:
					group = str(o[2])
					_place_pick.add_separator(group)
				_place_pick.add_item(str(o[1]))
				_place_pick.set_item_metadata(_place_pick.item_count - 1, str(o[0]))
			_place_pick.get_popup().max_size = Vector2i(320, 520)
			_place_pick.item_selected.connect(func(i: int):
				place_id = str(_place_pick.get_item_metadata(i))
				set_tool("place"))
			row.add_child(_place_pick)
	vb.add_child(row)
	var brush_row := HBoxContainer.new()
	brush_row.add_theme_constant_override("separation", 8)
	brush_row.add_child(hud._label("Brush", 14))
	_brush_slider = HSlider.new()
	_brush_slider.min_value = 0.3
	_brush_slider.max_value = BRUSH_MAX
	_brush_slider.step = 0.1
	_brush_slider.value = brush
	_brush_slider.custom_minimum_size = Vector2(220, 24)
	_brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_brush_slider.focus_mode = Control.FOCUS_NONE
	_brush_slider.value_changed.connect(func(v: float): set_brush(v))
	brush_row.add_child(_brush_slider)
	_brush_label = hud._label("%.1f m" % (brush * 2.0), 14)
	_brush_label.custom_minimum_size = Vector2(56, 0)
	brush_row.add_child(_brush_label)
	_shape_btn = hud._button("Round brush", func(): set_brush_square(not brush_square))
	_shape_btn.tooltip_text = "Switch between a round and a square brush."
	_shape_btn.custom_minimum_size = Vector2(120, 0)
	brush_row.add_child(_shape_btn)
	brush_row.add_child(VSeparator.new())
	var row2 := brush_row
	row2.add_child(hud._button("Turn left (R)", func(): turn(TURN_STEP)))
	row2.add_child(hud._button("Turn right (T)", func(): turn(-TURN_STEP)))
	row2.add_child(hud._button("Copy", func(): duplicate_selected()))
	row2.add_child(hud._button("Smaller (-)", func(): resize(1.0 / SIZE_STEP)))
	row2.add_child(hud._button("Bigger (+)", func(): resize(SIZE_STEP)))
	row2.add_child(hud._button("Delete", func(): delete_selected()))
	vb.add_child(row2)
	row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_small_check = CheckBox.new()
	_small_check.text = "Pick small plants"
	_small_check.button_pressed = small_on
	_small_check.focus_mode = Control.FOCUS_NONE
	_small_check.tooltip_text = "Off: clicks pass over grass tufts, flowers and clover, so bigger things are easier to grab."
	_small_check.toggled.connect(func(on: bool): small_on = on)
	row2.add_child(_small_check)
	row2.add_child(VSeparator.new())
	row2.add_child(hud._button("Undo", func(): undo()))
	row2.add_child(hud._button("Save", func():
		if save_layout():
			hud.show_toast("World layout saved.")
		_show_status()))
	var reset: Button = hud._button("Reset world", func(): pass)
	reset.tooltip_text = "Throw away the saved layout and rebuild the world as the code makes it."
	reset.pressed.connect(func(): hud._confirm_then(reset, "Really reset?", reset_world))
	row2.add_child(reset)
	row2.add_child(hud._button("Done", func(): set_active(false)))
	vb.add_child(row2)
	_status = hud._label("", 13, Color(hud.TEXT, 0.8))
	vb.add_child(_status)
	_ui.add_child(vb)
	_ui.visible = false
	hud.root.add_child(_ui)
	hud._place(_ui, 0.5, 0.0, Vector2(0, 10))
