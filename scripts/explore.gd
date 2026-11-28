extends Node
## Things to find out in the world (2026-11-26, docs/REVIEW_2026-11-26.md section 6; data/explore.json).
##
## - Treasure patches: lusher, darker turf with a faint glint, a few in every land. Dug with the
##   shovel (a click with it in hand, or the patch's own menu) they give a roll of their land's loot
##   table: coins, wool or a wild fibre, seeds, now and then a pair of found needles. Most are once
##   only; some fill in again after a while. The first, near the farm, is Gran's ("For a rainy day").
## - Huts with a chest each, opened once: a row of beach huts on Saltmeadow Beach, a stilt hut on the
##   Deep Mire's island, a sandstone ruin deep in the Sunscald Dunes and a stone bothy high in the
##   Larkspur Downs. They're Town.built, so the world editor can move them (the chest goes with its
##   hut), and what grows on their ground is cleared (clears(), asked by forage.apply()).
## - Found needles: items in her bag; the best pair she owns sets the least a sweater can be, like
##   Rosa's (empire.needle_floor() asks found_floor()).
## - Waders from Steve: the Deep Mire's moat is deep water on the walking grid (regions.mark_moat())
##   until she has them; then the grid is built again and the island, its patch, its hut and its
##   animals (the muskrat and the otter) are hers to reach. Walking up to the water without them
##   says so.
## - The tent from Steve: pitched from the ground ring anywhere open outside town, packed up again
##   from its menu. Sleeping in it with a bonfire of hers burning near fills every bar; without one
##   it's a fire's half a night's rest. Game.flags["tent"] = [x, z, yaw] while it's pitched.
##
## State: Game.flags["explore"] = {"dug": {patch id: day}, "opened": {hut id: day}}. Everything is a
## STAND-IN built from plain shapes until its model is made (docs/DIRECTION.md "Models still needed").

const Data = preload("res://scripts/data.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Hud = preload("res://scripts/hud.gd")
const KnitGame = preload("res://scripts/knit_game.gd")

const CLEAR_R := 4.5 # metres round a hut kept clear of scenery

var main # main.gd
var data := {}
var patches: Array = [] # Patch nodes
var huts: Array = [] # [node, cfg]
var chests: Array = [] # Chest nodes
var tent: Node3D = null # the pitched tent, if any
var _t := 0.0
var _hint_day := -1


func _ready() -> void:
	name = "Explore"


func econ(key: String, fallback):
	return data.get(key, fallback)


func state() -> Dictionary:
	if not Game.flags.has("explore") or not Game.flags["explore"] is Dictionary:
		Game.flags["explore"] = {"dug": {}, "opened": {}}
	var s: Dictionary = Game.flags["explore"]
	for k in ["dug", "opened"]:
		if not s.has(k) or not s[k] is Dictionary:
			s[k] = {}
	return s


# --- found needles ------------------------------------------------------------------------------

static func needle_defs() -> Dictionary:
	return Data.load_json("explore").get("needles", {})


## The least a sweater can be with the best found pair in her bag (0 with none).
static func found_floor() -> int:
	var best := 0
	var defs := needle_defs()
	for id in defs:
		if Game.has_item(str(id)):
			best = maxi(best, int((defs[id] as Dictionary).get("floor", 1)))
	return best


static func found_name() -> String:
	var best := 0
	var name := ""
	var defs := needle_defs()
	for id in defs:
		var f := int((defs[id] as Dictionary).get("floor", 1))
		if Game.has_item(str(id)) and f > best:
			best = f
			name = str((defs[id] as Dictionary).get("name", id))
	return name


## The items' names and colours for the bag (Hud.Slot.extra), once at launch.
static func register_items() -> void:
	var defs := needle_defs()
	for id in defs:
		var d: Dictionary = defs[id]
		Hud.Slot.extra[str(id)] = [str(d.get("name", id)), Color.html(str(d.get("color", "#a08060")))]
	Hud.Slot.extra["waders"] = ["Waders", Color.html("#3e5a3a")]
	Hud.Slot.extra["tent"] = ["Tent", Color.html("#c8a46a")]


# --- the world: huts (before the grid, so they block it) ----------------------------------------

## Builds the huts and their chests. Returns their blocks for the walking grid (main.grid_blockers).
func build() -> Array:
	data = Data.load_json("explore")
	register_items()
	var blocks := []
	for h in data.get("huts", []):
		var cfg: Dictionary = h
		var at: Array = cfg.get("at", [0, 0])
		var node := Node3D.new()
		node.name = "Hut_" + str(cfg.get("id", "hut"))
		node.position = Vector3(float(at[0]), 0.0, float(at[1]))
		node.rotation_degrees.y = float(cfg.get("yaw", 0.0))
		main.add_child(node)
		var size: Vector2 = _build_hut(node, cfg)
		var rect := _turned_rect(node, size)
		blocks.append(rect)
		if cfg.has("chest"):
			var c := Chest.new()
			c.home = self
			c.hut_id = str(cfg["id"])
			c.loot = cfg["chest"]
			c.position = _chest_spot(str(cfg.get("kind", "")), size)
			node.add_child(c)
			c.build()
			chests.append(c)
		huts.append([node, cfg])
		Town.built.append([node, str(cfg.get("kind", "hut")), _title(str(cfg.get("kind", ""))), [rect]])
	return blocks


func _title(kind: String) -> String:
	match kind:
		"beach_hut": return "Beach hut"
		"stilt_hut": return "Stilt hut"
		"ruin": return "Old ruin"
		"bothy": return "Stone bothy"
	return "Hut"


## The world rect a footprint of `size` covers, turned as `node` is.
func _turned_rect(node: Node3D, size: Vector2) -> Rect2:
	var r := Rect2()
	var first := true
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p: Vector3 = node.transform * Vector3(size.x * sx, 0, size.y * sz)
			var q := Rect2(p.x, p.z, 0, 0)
			r = q if first else r.merge(q)
			first = false
	return r


## Where a hut's chest stands, in its own space (its front is +Z).
func _chest_spot(kind: String, size: Vector2) -> Vector3:
	match kind:
		"beach_hut": return Vector3(0.6, 0.0, size.y * 0.5 + 0.9)
		"stilt_hut": return Vector3(1.0, 0.0, size.y * 0.5 + 1.1)
		"ruin": return Vector3(0.0, 0.0, size.y * 0.5 + 1.0)
		"bothy": return Vector3(1.4, 0.0, size.y * 0.5 + 0.9)
	return Vector3(0, 0, size.y * 0.5 + 1.0)


## True if scenery at `at` should go: it stands on a hut's ground (forage.apply()).
func clears(at: Vector3) -> bool:
	for h in huts:
		var n: Node3D = h[0]
		if is_instance_valid(n) and Vector2(at.x - n.global_position.x, at.z - n.global_position.z).length() < CLEAR_R:
			return true
	return false


static func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## A gable roof of two slabs over a w x d box whose walls stop at `eave`, ridge along Z.
static func _gable(parent: Node3D, w: float, d: float, eave: float, pitch_deg: float, mat: Material, over := 0.25) -> void:
	var half := w * 0.5 + over
	var slope := half / cos(deg_to_rad(pitch_deg))
	var rise := half * tan(deg_to_rad(pitch_deg))
	for s in [-1.0, 1.0]:
		_box(parent, Vector3(slope, 0.08, d + over * 2.0), Vector3(s * half * 0.5, eave + rise * 0.5, 0), mat, Vector3(0, 0, -s * pitch_deg))


## The stand-in models, from plain shapes. Returns the footprint (x, z) in its own space.
func _build_hut(node: Node3D, cfg: Dictionary) -> Vector2:
	var kind := str(cfg.get("kind", ""))
	match kind:
		"beach_hut":
			var col := Color.html(str(cfg.get("colour", "#e86a5a")))
			var white := _mat(Color(0.95, 0.93, 0.88))
			var paint := _mat(col)
			var post := _mat(Color(0.42, 0.33, 0.24))
			var w := 2.2
			var d := 2.4
			var base := 0.45
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_cyl(node, 0.07, base, Vector3(x * (w * 0.5 - 0.1), base * 0.5, z * (d * 0.5 - 0.1)), post)
			_box(node, Vector3(w + 0.1, 0.08, d + 1.1), Vector3(0, base, 0.5), _mat(Color(0.62, 0.52, 0.4))) # the floor and its deck
			# the walls in stripes of the hut's colour and white boards
			var n := 9
			for i in n:
				var m := paint if i % 2 == 0 else white
				var x0 := -w * 0.5 + w * (float(i) + 0.5) / n
				_box(node, Vector3(w / n, 1.9, 0.06), Vector3(x0, base + 0.99, d * 0.5), m)
				_box(node, Vector3(w / n, 1.9, 0.06), Vector3(x0, base + 0.99, -d * 0.5), m)
			_box(node, Vector3(0.06, 1.9, d), Vector3(-w * 0.5, base + 0.99, 0), paint)
			_box(node, Vector3(0.06, 1.9, d), Vector3(w * 0.5, base + 0.99, 0), paint)
			_box(node, Vector3(0.8, 1.55, 0.04), Vector3(-0.35, base + 0.8, d * 0.5 + 0.04), _mat(col.darkened(0.35))) # the door
			# the gable ends' triangles, as stepped boards
			for k in 4:
				var ww := w * (1.0 - float(k) / 4.0)
				_box(node, Vector3(ww, 0.18, 0.05), Vector3(0, base + 2.0 + 0.18 * k, d * 0.5), white)
				_box(node, Vector3(ww, 0.18, 0.05), Vector3(0, base + 2.0 + 0.18 * k, -d * 0.5), white)
			_gable(node, w, d, base + 1.95, 33.0, _mat(Color(0.32, 0.3, 0.3)))
			return Vector2(w + 0.2, d + 0.2)
		"stilt_hut":
			var board := _mat(Color(0.36, 0.3, 0.24))
			var dark := _mat(Color(0.22, 0.18, 0.15))
			var thatch := _mat(Color(0.48, 0.4, 0.26))
			var w := 3.0
			var d := 3.0
			var base := 1.1
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_cyl(node, 0.1, base + 0.3, Vector3(x * (w * 0.5 - 0.15), (base + 0.3) * 0.5 - 0.3, z * (d * 0.5 - 0.15)), dark)
			_box(node, Vector3(w + 0.3, 0.1, d + 1.0), Vector3(0, base, 0.4), board)
			_box(node, Vector3(w, 1.8, 0.08), Vector3(0, base + 0.9, -d * 0.5), board)
			_box(node, Vector3(0.08, 1.8, d), Vector3(-w * 0.5, base + 0.9, 0), board)
			_box(node, Vector3(0.08, 1.8, d), Vector3(w * 0.5, base + 0.9, 0), board)
			_box(node, Vector3(0.9, 1.8, 0.08), Vector3(-1.05, base + 0.9, d * 0.5), board)
			_box(node, Vector3(0.9, 1.8, 0.08), Vector3(1.05, base + 0.9, d * 0.5), board)
			_box(node, Vector3(1.2, 0.4, 0.08), Vector3(0, base + 1.6, d * 0.5), board)
			_gable(node, w, d, base + 1.75, 38.0, thatch, 0.45)
			# a ladder down to the mud
			for s in [-0.25, 0.25]:
				_box(node, Vector3(0.06, 1.5, 0.06), Vector3(s, 0.55, d * 0.5 + 1.0), dark, Vector3(-25, 0, 0))
			for k in 4:
				_box(node, Vector3(0.5, 0.04, 0.05), Vector3(0, 0.2 + 0.28 * k, d * 0.5 + 1.15 - 0.13 * k), dark)
			return Vector2(w + 0.4, d + 0.6)
		"ruin":
			var stone := _mat(Color(0.82, 0.66, 0.46))
			var worn := _mat(Color(0.7, 0.55, 0.38))
			var w := 5.0
			var d := 4.0
			var rng := RandomNumberGenerator.new()
			rng.seed = 3306
			# broken walls: blocks of sandstone, standing to different heights, a gap at the front
			for i in 9:
				var x := -w * 0.5 + w * (float(i) + 0.5) / 9.0
				var hb := rng.randf_range(0.5, 2.4)
				_box(node, Vector3(w / 9.0, hb, 0.5), Vector3(x, hb * 0.5, -d * 0.5), stone)
			for i in 7:
				var z := -d * 0.5 + d * (float(i) + 0.5) / 7.0
				for s in [-1.0, 1.0]:
					var hgt := rng.randf_range(0.4, 2.0)
					_box(node, Vector3(0.5, hgt, d / 7.0), Vector3(s * w * 0.5, hgt * 0.5, z), stone if i % 2 else worn)
			for s in [-1.0, 1.0]:
				_box(node, Vector3(1.3, 0.9, 0.5), Vector3(s * 1.85, 0.45, d * 0.5), worn)
			_cyl(node, 0.28, 2.6, Vector3(1.2, 0.28, d * 0.5 + 1.5), stone, Vector3(0, 30, 90)) # a fallen column
			_cyl(node, 0.3, 2.8, Vector3(-2.9, 1.4, d * 0.5 + 0.2), stone)
			return Vector2(w + 0.5, d + 0.5)
		"bothy":
			var stone := _mat(Color(0.52, 0.52, 0.5))
			var slate := _mat(Color(0.25, 0.27, 0.3))
			var w := 4.2
			var d := 3.2
			_box(node, Vector3(w, 2.0, d), Vector3(0, 1.0, 0), stone)
			_box(node, Vector3(0.9, 1.7, 0.06), Vector3(-0.6, 0.85, d * 0.5 + 0.03), _mat(Color(0.34, 0.22, 0.14)))
			_box(node, Vector3(0.6, 0.5, 0.06), Vector3(1.2, 1.3, d * 0.5 + 0.03), _mat(Color(0.12, 0.14, 0.16), 0.2))
			for k in 4: # the gable ends
				var ww := d * (1.0 - float(k) / 4.0)
				for s in [-1.0, 1.0]:
					_box(node, Vector3(0.3, 0.3, ww), Vector3(s * (w * 0.5 - 0.15), 2.15 + 0.3 * k, 0), stone)
			var roof := Node3D.new()
			roof.rotation_degrees.y = 90.0 # the ridge runs along the long side
			node.add_child(roof)
			_gable(roof, d, w, 2.0, 36.0, slate, 0.2)
			_box(node, Vector3(0.6, 1.2, 0.6), Vector3(w * 0.5 - 0.3, 3.2, 0), stone) # the chimney
			return Vector2(w + 0.3, d + 0.3)
	return Vector2(2, 2)


# --- after the grid: patches, the saved state, the tent -----------------------------------------

## Lays out the patches (each on the nearest open ground to its spot), and the tent if it's
## pitched. main.gd calls it once the walking grid is built, and again after a load.
func apply() -> void:
	for p in patches:
		if is_instance_valid(p):
			p.queue_free()
	patches.clear()
	for e in data.get("patches", []):
		var a: Array = e
		var p := Patch.new()
		p.home = self
		p.id = str(a[0])
		p.table = str(a[3])
		p.refill = int(a[4])
		p.position = _open_spot(Vector3(float(a[1]), 0, float(a[2])))
		p.position.y = main.regions.relief(p.position.x, p.position.z) if main.regions else 0.0 # on a hillside, on the hill
		main.add_child(p)
		p.build()
		patches.append(p)
	for c in chests:
		c.refresh()
	_apply_tent()
	refresh()


## The nearest walkable spot to `p` (in rings of half a metre), so a patch never sits in a tree.
func _open_spot(p: Vector3) -> Vector3:
	if main._walkable(main._cell(p)):
		return p
	for r in range(1, 24):
		for k in 12:
			var a := TAU * float(k) / 12.0
			var q := p + Vector3(cos(a), 0, sin(a)) * (0.5 * r)
			if main._walkable(main._cell(q)):
				return q
	return p


## Shows each patch as dug or not (a dug one-off stays a dirt mark; a refill one greens over again).
func refresh() -> void:
	for p in patches:
		p.show_state()


func dug_on(id: String) -> int:
	return int(state()["dug"].get(id, -1))


## Whether patch `p` can be dug now: never dug, or dug long enough ago that it has filled in again.
func can_dig(p) -> bool:
	var d := dug_on(p.id)
	if d < 0:
		return true
	return p.refill > 0 and Game.day >= d + p.refill


# --- rolling loot ---------------------------------------------------------------------------------

## One roll of a table. Returns [kind, a, b] (kind coins: a coins; item: a id, b count; needles: a id).
func roll(table: String, rng: RandomNumberGenerator) -> Array:
	var t: Array = (data.get("loot", {}) as Dictionary).get(table, [["coins", 20, 40, 1]])
	var total := 0.0
	for e in t:
		total += float(e[3])
	var r := rng.randf() * total
	for e in t:
		r -= float(e[3])
		if r <= 0.0:
			if str(e[0]) == "coins":
				return ["coins", rng.randi_range(int(e[1]), int(e[2])), 0]
			return [str(e[0]), str(e[1]), int(e[2])]
	return ["coins", 20, 0]


## Gives one find to her. Returns the toast's words for it. Needles she has already are coins.
func give(f: Array, coins_if_owned := 60) -> String:
	match str(f[0]):
		"coins":
			var n := int(f[1])
			Game.coins += n # found money: not a sweater's, so the ledger leaves it out (empire_goals.gd)
			return "+%dc" % n
		"item":
			Game.add_item(str(f[1]), int(f[2]))
			return "+%d %s" % [int(f[2]), Hud.Slot.item_name(str(f[1]))]
		"needles":
			var id := str(f[1])
			if Game.has_item(id):
				Game.coins += coins_if_owned
				return "+%dc" % coins_if_owned
			Game.add_item(id, 1)
			var d: Dictionary = needle_defs().get(id, {})
			return "a pair of %s! (every knit %s or better while they're the best you have)" % [str(d.get("name", id)).to_lower(), KnitGame.rarity_name(int(d.get("floor", 1)))]
	return ""


## Digs patch `p` up (the shovel's work is done): a roll, a toast, the patch marked dug today.
func dug(p) -> void:
	if not can_dig(p):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d" % [p.id, Game.day])
	var f := roll(p.table, rng)
	if p.id == "gran_first":
		f = ["coins", 40, 0]
	var got := give(f)
	state()["dug"][p.id] = Game.day
	p.show_state()
	Game.add_need("happiness", 4.0)
	var note := str((data.get("notes", {}) as Dictionary).get(p.id, ""))
	if note != "":
		main.hud.show_dialogue("A find", -1, "%s  %s" % [note, got])
	else:
		main.hud.show_toast("Something under the turf: %s" % got)


## She walks over and digs `p` with the shovel. True if she set off.
func dig(p) -> bool:
	if main.player.busy:
		return false
	if not Game.has_item("shovel"):
		main.hud.show_toast("Something's under this turf. A shovel would get it up (Steve sells them).")
		return true
	if not can_dig(p):
		main.hud.show_toast("You've dug here already.")
		return true
	var away: Vector3 = main.player.position - p.position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
	main._tool_walk(p.position, p.position + away * 0.9, 3.0, "Digging", 1.6, dug.bind(p))
	return true


func open_chest(c) -> void:
	if state()["opened"].has(c.hut_id):
		return
	var words := []
	for f in c.loot:
		var e: Array = f
		words.append(give([str(e[0]), e[1] if str(e[0]) != "coins" else int(e[1]), int(e[2]) if e.size() > 2 else 1], 120))
	state()["opened"][c.hut_id] = Game.day
	c.refresh()
	Game.add_need("happiness", 6.0)
	main.hud.show_toast("Inside the chest: %s" % ", ".join(words))


# --- Steve's rows: waders and the tent ------------------------------------------------------------

func steve_rows() -> Array:
	var story: bool = Game.flag("story_farm", false) == true
	var done: bool = Game.flag("act1_done", false) == true
	if story and not done: # Act 1's guided days keep Steve's menu to the tools and seeds
		return []
	var rows := []
	var wp := int((econ("waders", {}) as Dictionary).get("price", 350))
	if Game.has_item("waders"):
		rows.append(main._act("noop", "Waders  (you have a pair)", false))
	else:
		rows.append(main._act("ex_waders", "Buy waders  (%dc · wade into the Deep Mire)" % wp, Game.coins >= wp))
	var tp := int((econ("tent", {}) as Dictionary).get("price", 400))
	if Game.has_item("tent") or Game.flags.has("tent"):
		rows.append(main._act("noop", "Tent  (you have one)", false))
	else:
		rows.append(main._act("ex_tent", "Buy a tent  (%dc · sleep out anywhere)" % tp, Game.coins >= tp))
	return rows


func action(v, id: String) -> void:
	match id:
		"ex_waders":
			var price := int((econ("waders", {}) as Dictionary).get("price", 350))
			if Game.has_item("waders") or not Game.spend(price):
				return
			Game.add_item("waders", 1)
			main._say(v, str((econ("waders", {}) as Dictionary).get("line", "Waders.")))
			main.hud.show_toast("New: waders. The deep water round the Deep Mire, west in Mirewood Swamp, is yours to wade.")
			main._rebuild_grid()
		"ex_tent":
			var price := int((econ("tent", {}) as Dictionary).get("price", 400))
			if Game.has_item("tent") or Game.flags.has("tent") or not Game.spend(price):
				return
			Game.add_item("tent", 1)
			main._say(v, str((econ("tent", {}) as Dictionary).get("line", "A tent.")))
			main.hud.show_toast("New: a tent. Pitch it from the ground anywhere outside town (a right click), and sleep by a bonfire for a full night's rest.")


# --- the tent -------------------------------------------------------------------------------------

func tent_problem(g: Vector3) -> String:
	if not Game.has_item("tent"):
		return "You have no tent."
	if Town.TOWN.has_point(Vector2(g.x, g.z)):
		return "Not in the middle of town."
	if main.building_at(g) or Interiors.inside_of(g) != "":
		return "Not indoors!"
	if not main._walkable(main._cell(g)) or not main._walkable(main._cell(g + Vector3(0, 0, 1.2))):
		return "There's no room for a tent there."
	if main.bonfire != null:
		for f in main.bonfire.fires:
			if Vector2(f.position.x - g.x, f.position.z - g.z).length() < 2.2:
				return "Too close to the fire."
	return ""


## The ground ring's rows (main.ground_actions()).
func rows_for(g: Vector3) -> Array:
	if not Game.has_item("tent"):
		return []
	var why := tent_problem(g)
	var row: Dictionary = main._act("ex_pitch", "Pitch your tent here", why == "")
	if why != "":
		row["hint"] = why
	return [row]


func ground_action(id: String, g: Vector3) -> void:
	if id != "ex_pitch" or main.player.busy:
		return
	var why := tent_problem(g)
	if why != "":
		main.hud.show_toast(why)
		return
	var away: Vector3 = main.player.position - g
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
	var yaw := atan2(away.x, away.z) # its door toward where she came from
	main._tool_walk(g, g + away * 1.8, 2.0, "Pitching the tent", 2.5, pitch.bind(g, yaw))


func pitch(g: Vector3, yaw: float) -> void:
	if not Game.take_item("tent", 1):
		return
	Game.flags["tent"] = [snappedf(g.x, 0.01), snappedf(g.z, 0.01), snappedf(yaw, 0.001)]
	_apply_tent()
	main.hud.show_toast("Tent pitched. Light a bonfire beside it for a full night's rest.")


func pack_up() -> void:
	if tent == null:
		return
	Game.flags.erase("tent")
	Game.add_item("tent", 1)
	_apply_tent()
	main.hud.show_toast("Tent packed away.")


func _apply_tent() -> void:
	if tent != null and is_instance_valid(tent):
		tent.queue_free()
	tent = null
	var e = Game.flags.get("tent", null)
	if not e is Array or (e as Array).size() < 3:
		return
	var t := Tent.new()
	t.home = self
	t.position = Vector3(float(e[0]), main.regions.relief(float(e[0]), float(e[1])) if main.regions else 0.0, float(e[1]))
	t.rotation.y = float(e[2])
	main.add_child(t)
	t.build()
	tent = t


## True if a bonfire of hers burns near the tent.
func fire_by_tent() -> bool:
	if tent == null or main.bonfire == null:
		return false
	var r := float((econ("tent", {}) as Dictionary).get("fire_radius", 9.0))
	for f in main.bonfire.fires:
		if Vector2(f.position.x - tent.position.x, f.position.z - tent.position.z).length() < r:
			return true
	return false


func tent_rest() -> float:
	return float((econ("tent", {}) as Dictionary).get("rest", 50.0))


## Into the tent till morning: every bar full with a fire burning near, half a night's rest without.
func sleep_in_tent() -> void:
	if tent == null or main.sleeping:
		return
	var full := fire_by_tent()
	await main._go_to_sleep(false, 100.0 if full else tent_rest())
	if full: # by a good fire under canvas: she wakes with everything full
		Game.energy = 100.0
		Game.fullness = 100.0
		Game.happiness = 100.0
		Game.warmth = 100.0


# --- now and then ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or main == null or main.player == null:
		return
	_t = 0.5
	_mire_hint()


## Walking up to the Deep Mire's water without waders: once a day, a word about it.
func _mire_hint() -> void:
	if Game.has_item("waders") or _hint_day == Game.day or main.regions == null or main.regions.mire.is_empty():
		return
	var p: Vector3 = main.player.position
	if main.regions.mire_zone(p.x, p.z) != 2:
		return
	var c: Vector2 = main.regions.mire["centre"]
	var d := (c - Vector2(p.x, p.z))
	if d.length() < 0.1:
		return
	var q := Vector2(p.x, p.z) + d.normalized() * 2.5
	if main.regions.mire_zone(q.x, q.y) == 1:
		_hint_day = Game.day
		main.hud.show_toast("The water's too deep to wade here. Something lives on that island... Steve sells waders.")


# --- the nodes --------------------------------------------------------------------------------------

static func _hitbox(owner: Node3D, size: Vector3, centre: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = centre
	body.add_child(cs)
	body.set_meta("target", owner)
	owner.add_child(body)


## A patch of lusher turf with something under it. Click it (or click it with the shovel) to dig.
class Patch extends Node3D:
	var home # explore.gd
	var id := ""
	var table := "near"
	var refill := 0
	var green: MeshInstance3D
	var dirt: MeshInstance3D
	var glint: MeshInstance3D
	var _t := 0.0

	func display_name() -> String:
		return "Lush patch of grass" if home.can_dig(self) else "Dug-over ground"

	func ke_actions() -> Array:
		if not home.can_dig(self):
			return [{"id": "noop", "label": "You've dug here already" + (" (it'll green over again)" if refill > 0 else ""), "enabled": false}]
		var shovel := Game.has_item("shovel")
		return [{"id": "dig", "label": "Dig here" if shovel else "Dig here  (you need a shovel)", "enabled": shovel}]

	func ke_action(aid: String) -> void:
		if aid == "dig":
			home.dig(self)

	func build() -> void:
		name = "Treasure_" + id
		set_meta("treasure", true)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.2, 0.4, 0.12)
		gm.roughness = 1.0
		green = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 0.9
		cm.height = 0.04
		cm.radial_segments = 14
		green.mesh = cm
		green.material_override = gm
		green.position.y = 0.02
		add_child(green)
		for k in 7: # a few tall tufts, greener than the lawn round it
			var tuft := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.1, 0.24, 0.03)
			tuft.mesh = pm
			tuft.material_override = gm
			var a := TAU * float(k) / 7.0 + 0.4
			tuft.position = Vector3(cos(a) * 0.5, 0.17, sin(a) * 0.5)
			tuft.rotation.y = a
			add_child(tuft)
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.33, 0.24, 0.16)
		dm.roughness = 1.0
		dirt = MeshInstance3D.new()
		var dmm := CylinderMesh.new()
		dmm.top_radius = 0.55
		dmm.bottom_radius = 0.75
		dmm.height = 0.1
		dmm.radial_segments = 12
		dirt.mesh = dmm
		dirt.material_override = dm
		dirt.position.y = 0.03
		add_child(dirt)
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(1.0, 0.95, 0.7)
		em.emission_enabled = true
		em.emission = Color(1.0, 0.9, 0.55)
		em.emission_energy_multiplier = 2.5
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glint = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.08
		sm.radial_segments = 6
		sm.rings = 3
		glint.mesh = sm
		glint.material_override = em
		glint.position = Vector3(0.2, 0.12, -0.1)
		glint.visibility_range_end = 16.0
		add_child(glint)
		home._hitbox(self, Vector3(1.8, 0.4, 1.8), Vector3(0, 0.2, 0))
		show_state()

	func show_state() -> void:
		var r: bool = home.can_dig(self)
		green.visible = r
		glint.visible = r
		for c in get_children():
			if c is MeshInstance3D and c.mesh is PrismMesh:
				c.visible = r
		dirt.visible = not r and (refill == 0 or Game.day < home.dug_on(id) + 2)

	func _process(delta: float) -> void:
		if not glint.visible:
			return
		_t += delta
		var s := 0.6 + 0.6 * maxf(0.0, sin(_t * 2.6 + position.x)) # a slow glint, now and then
		glint.scale = Vector3.ONE * s


## A hut's old chest: opened once.
class Chest extends Node3D:
	var home # explore.gd
	var hut_id := ""
	var loot: Array = []
	var lid: Node3D

	func display_name() -> String:
		return "Old chest"

	func is_open() -> bool:
		return home.state()["opened"].has(hut_id)

	func ke_actions() -> Array:
		if is_open():
			return [{"id": "noop", "label": "Empty. You've had what was in it", "enabled": false}]
		return [{"id": "open", "label": "Open the chest", "enabled": true}]

	func ke_action(aid: String) -> void:
		if aid == "open":
			var p: Vector3 = global_position + global_transform.basis.z * 0.9
			home.main._tool_walk(global_position, p, 0.5, "Opening the chest", 1.0, func(): home.open_chest(self))

	func build() -> void:
		name = "Chest"
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.28, 0.15)
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.25, 0.24, 0.22)
		iron.metallic = 0.6
		iron.roughness = 0.5
		home._box(self, Vector3(0.8, 0.42, 0.5), Vector3(0, 0.21, 0), wood)
		home._box(self, Vector3(0.82, 0.06, 0.52), Vector3(0, 0.06, 0), iron)
		lid = Node3D.new()
		lid.position = Vector3(0, 0.42, -0.25)
		add_child(lid)
		home._box(lid, Vector3(0.8, 0.14, 0.5), Vector3(0, 0.07, 0.25), wood)
		home._box(lid, Vector3(0.1, 0.12, 0.04), Vector3(0, 0.0, 0.51), iron)
		home._hitbox(self, Vector3(1.0, 0.8, 0.8), Vector3(0, 0.4, 0))
		refresh()

	func refresh() -> void:
		if lid:
			lid.rotation_degrees.x = -70.0 if is_open() else 0.0


## Her tent: a canvas ridge tent, its door at +Z. Click it to sleep in it or pack it up.
class Tent extends Node3D:
	var home # explore.gd

	func display_name() -> String:
		return "Your tent"

	func door_point() -> Vector3:
		return global_position + global_transform.basis.z * 1.6

	func ke_actions() -> Array:
		var full: bool = home.fire_by_tent()
		var label := "Sleep in the tent  (by the fire: wake with every bar full)" if full else "Sleep in the tent  (+%d energy; light a bonfire near it for a full night's rest)" % int(home.tent_rest())
		return [
			{"id": "tent_sleep", "label": label, "enabled": not home.main.sleeping},
			{"id": "tent_pack", "label": "Pack up the tent", "enabled": true},
		]

	func ke_action(aid: String) -> void:
		match aid:
			"tent_sleep":
				home.main._tool_walk(global_position, door_point(), 0.0, "Into the tent", 0.8, home.sleep_in_tent)
			"tent_pack":
				home.pack_up()

	func build() -> void:
		name = "Tent"
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.78, 0.64, 0.42)
		canvas.roughness = 1.0
		canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
		var pole := StandardMaterial3D.new()
		pole.albedo_color = Color(0.35, 0.25, 0.16)
		var w := 1.8
		var d := 2.2
		var h := 1.35
		var side := sqrt(w * w * 0.25 + h * h)
		var tilt := rad_to_deg(atan2(h, w * 0.5))
		for s in [-1.0, 1.0]:
			home._box(self, Vector3(side, 0.03, d), Vector3(s * w * 0.25, h * 0.5, 0), canvas, Vector3(0, 0, -s * tilt))
		var back := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(w, h, 0.03)
		back.mesh = pm
		back.material_override = canvas
		back.position = Vector3(0, h * 0.5, -d * 0.5)
		add_child(back)
		var front := MeshInstance3D.new() # the front, its canvas tied back round a dark doorway
		var fm := PrismMesh.new()
		fm.size = Vector3(w, h, 0.03)
		front.mesh = fm
		front.material_override = canvas
		front.position = Vector3(0, h * 0.5, d * 0.5)
		add_child(front)
		var shade := StandardMaterial3D.new()
		shade.albedo_color = Color(0.12, 0.09, 0.07)
		var door := MeshInstance3D.new()
		var dm := PrismMesh.new()
		dm.size = Vector3(w * 0.55, h * 0.75, 0.03)
		door.mesh = dm
		door.material_override = shade
		door.position = Vector3(0, h * 0.375, d * 0.5 + 0.02)
		add_child(door)
		for z in [-d * 0.5, d * 0.5]:
			home._cyl(self, 0.03, h + 0.15, Vector3(0, (h + 0.15) * 0.5, z), pole)
		home._hitbox(self, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
