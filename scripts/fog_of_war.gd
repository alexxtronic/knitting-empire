extends Node
## The fog over unexplored land (Alex, 2026-11-17: "a 'fog of war' or fog that persists until she
## explores an area both in real world and on the map. The fog is in a large circle around the
## starting town, it's not so dense you can't see through it just enough to indicate it's an
## unexplored area.")
##
## Everything outside a circle round the farm and Maple Grove (data/economy.json "fog": centre,
## radius, fade) lies under a light ground fog until she, or the dog while the player plays him,
## has come within "reveal" metres of it. Then it's gone for good, in the world and on the minimap.
##
## How it's drawn, cheaply (see "Frame rate" in AGENTS.md):
## - What she has explored is a coarse grid ("cell" metres a cell, over Regions.BOUNDS and a margin),
##   one bit a cell, kept in Game.flags["explored"] as base64 so it saves with the game.
## - An LA8 image holds the fog left on each cell (0 inside the circle or explored, up to 255 out
##   in the unknown); a few times a second, when she has reached new cells, those pixels change and
##   the texture is updated.
## - In the world, one full-screen quad (shaders/fog_of_war.gdshader) reads the depth buffer and
##   the texture: no fog volumes, no node per cell. It sits on its own render layer (LAYER), which
##   the minimap's camera leaves out; the minimap draws the same texture flat over its picture
##   instead (draw_on_map()).
## - It's hidden in the world editor and off in the autotest but for its own check (`enabled`).

const Data = preload("res://scripts/data.gd")
const Regions = preload("res://scripts/regions.gd")
const Town = preload("res://scripts/town.gd")
const SHADER := preload("res://shaders/fog_of_war.gdshader")

const LAYER := 1 << 19 # render layer 20: only the game's camera draws the fog quad
const MARGIN := 20.0 # metres past the map's bounds the grid reaches
const EVERY := 0.2 # s between looks at where she is
const DAY_COLOR := Color(0.84, 0.87, 0.91)
const NIGHT_COLOR := Color(0.17, 0.2, 0.27)

var main # main.gd
var enabled := true
var data := {}
var origin := Vector2.ZERO # world x, z of the grid's corner
var cells := Vector2i.ZERO
var cell := 2.0
var centre := Vector2.ZERO
var radius := 48.0
var fade := 10.0
var reveal_radius := 16.0
var tex: ImageTexture

var _bits := PackedByteArray() # explored, a bit a cell
var _outside := PackedByteArray() # how foggy each cell is when unexplored, 0..255
var _img: Image
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0
var _last := Vector2i(-99999, -99999)
var _saved := ""


func _ready() -> void:
	name = "FogOfWar"
	data = Data.load_json("economy").get("fog", {})
	cell = float(data.get("cell", 2.0))
	var c: Array = data.get("centre", [32.5, -2.5])
	centre = Vector2(float(c[0]), float(c[1]))
	radius = float(data.get("radius", 48.0))
	fade = float(data.get("fade", 10.0))
	reveal_radius = float(data.get("reveal", 16.0))
	var b: Rect2 = Regions.BOUNDS.grow(MARGIN)
	origin = b.position
	cells = Vector2i(ceili(b.size.x / cell), ceili(b.size.y / cell))
	_outside.resize(cells.x * cells.y)
	for y in cells.y:
		for x in cells.x:
			var d := (origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell).distance_to(centre)
			_outside[y * cells.x + x] = int(255.0 * smoothstep(radius, radius + fade, d))
	_img = Image.create_empty(cells.x, cells.y, false, Image.FORMAT_LA8)
	load_from_flags()
	_build_quad()


## The grid was 140 cells wide until the map grew east (2026-11-26: the dunes and the downs). The
## origin and the rows' count didn't change, so a save's narrower grid is copied in row by row.
const OLD_WIDTH := 140


## `old` (a grid `w0` cells wide, as many rows as now) widened to this one; empty if it doesn't fit.
func _widened(old: PackedByteArray, w0: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((cells.x * cells.y + 7) / 8)
	if w0 <= 0 or w0 > cells.x or old.size() != (w0 * cells.y + 7) / 8:
		return out # none yet, or a grid we can't read: start again
	for y in cells.y:
		for x in w0:
			var i := y * w0 + x
			if old[i >> 3] & (1 << (i & 7)):
				var j := y * cells.x + x
				out[j >> 3] = out[j >> 3] | (1 << (j & 7))
	return out


## The explored cells from the save (or none), and the texture drawn from them.
func load_from_flags() -> void:
	var n := (cells.x * cells.y + 7) / 8
	_bits = PackedByteArray()
	var s: Variant = Game.flags.get("explored", "")
	if s is String and s != "":
		_bits = Marshalls.base64_to_raw(s)
	if _bits.size() != n: # none yet, or a grid of another size
		_bits = _widened(_bits, int(Game.flags.get("explored_w", OLD_WIDTH)))
	Game.flags["explored_w"] = cells.x
	_saved = str(s) if s is String else ""
	for i in cells.x * cells.y:
		_img.set_pixel(i % cells.x, i / cells.x, Color(1, 1, 1, _fog_byte(i) / 255.0))
	if tex == null:
		tex = ImageTexture.create_from_image(_img)
	else:
		tex.update(_img)
	_last = Vector2i(-99999, -99999)


func _fog_byte(i: int) -> int:
	if _bits[i >> 3] & (1 << (i & 7)):
		return 0
	return _outside[i]


func _build_quad() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = -120 # first of the see-through things: flames, sparks and meters draw over it
	_mat.set_shader_parameter("fog_tex", tex)
	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("size", Vector2(cells) * cell)
	_mat.set_shader_parameter("top", float(data.get("top", 6.0)))
	_mat.set_shader_parameter("density", float(data.get("density", 0.05)))
	_mat.set_shader_parameter("max_alpha", float(data.get("max_alpha", 0.62)))
	_quad = MeshInstance3D.new()
	_quad.name = "FogOfWarQuad"
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.layers = LAYER
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0 # its vertex shader puts it over the whole screen: never cull it
	_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_quad)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.z - origin.y) / cell))


## How much fog lies on the ground at `p` (0 clear .. 1 full).
func fog_at(p: Vector3) -> float:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= cells.x or c.y >= cells.y:
		return 1.0
	return _fog_byte(c.y * cells.x + c.x) / 255.0


func explored_at(p: Vector3) -> bool:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= cells.x or c.y >= cells.y:
		return false
	var i := c.y * cells.x + c.x
	return (_bits[i >> 3] & (1 << (i & 7))) != 0


## The share of the fogged land she has cleared, 0..1.
func explored_share() -> float:
	var all := 0
	var seen := 0
	for i in cells.x * cells.y:
		if _outside[i] > 0:
			all += 1
			if _bits[i >> 3] & (1 << (i & 7)):
				seen += 1
	return float(seen) / float(maxi(all, 1))


## Clears the fog within `r` metres of `p`. Returns how many cells were new.
func reveal(p: Vector3, r: float) -> int:
	var c0 := cell_of(p - Vector3(r, 0, r))
	var c1 := cell_of(p + Vector3(r, 0, r))
	var r2 := r * r
	var n := 0
	for y in range(maxi(c0.y, 0), mini(c1.y + 1, cells.y)):
		for x in range(maxi(c0.x, 0), mini(c1.x + 1, cells.x)):
			var w := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if w.distance_squared_to(Vector2(p.x, p.z)) > r2:
				continue
			var i := y * cells.x + x
			if _bits[i >> 3] & (1 << (i & 7)):
				continue
			_bits[i >> 3] = _bits[i >> 3] | (1 << (i & 7))
			if _outside[i] > 0:
				_img.set_pixel(x, y, Color(1, 1, 1, 0))
			n += 1
	if n > 0:
		tex.update(_img)
		_saved = Marshalls.raw_to_base64(_bits)
		Game.flags["explored"] = _saved
	return n


## Forget everything she explored (for the autotest).
func reset() -> void:
	Game.flags.erase("explored")
	load_from_flags()


## Who clears the fog: the dog while the player plays him, else Nora.
func _hero() -> Node3D:
	if main.dog != null and main.dog.controlled:
		return main.dog
	return main.player


func shown() -> bool:
	return enabled and not (main.god != null and main.god.active)


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var on := shown()
	_quad.visible = on
	if not on:
		return
	var dl: float = Game.daylight()
	_mat.set_shader_parameter("color", NIGHT_COLOR.lerp(DAY_COLOR, dl))
	_t -= delta
	if _t > 0.0:
		return
	_t = EVERY
	var h := _hero()
	if h == null or main.title_on:
		return
	var c := cell_of(h.global_position)
	if c == _last:
		return
	_last = c
	reveal(h.global_position, reveal_radius)


## The minimap (minimap.gd _draw): the same fog, flat over its picture. `centre` is the world
## point at the map's middle, `yaw` its turn, `span` the metres across, `px` its size in pixels.
func draw_on_map(ci: CanvasItem, map_centre: Vector3, yaw: float, span: float, px: float) -> void:
	if not shown() or tex == null:
		return
	var k := px / span
	var xc := Vector2(k * cos(yaw), k * sin(yaw)) # world x -> map pixels (as Minimap.to_map())
	var zc := Vector2(-k * sin(yaw), k * cos(yaw)) # world z -> map pixels
	var o := Vector2(px * 0.5, px * 0.5) - xc * map_centre.x - zc * map_centre.z
	ci.draw_set_transform_matrix(Transform2D(xc, zc, o))
	ci.draw_texture_rect(tex, Rect2(origin, Vector2(cells) * cell), false, Color(0.88, 0.9, 0.95, 0.62))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# --- the autotest's check (main.gd _fog_checks, --only=fog) ------------------------------------

func checks() -> void:
	var m = main
	var keep := {"explored": Game.flags.get("explored", null), "enabled": enabled, "pos": m.player.position,
		"hour": Game.hour, "running": Game.time_running, "zoom": m.minimap.zoom}
	Game.time_running = false
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	m.player.walk([])
	enabled = true
	reset()
	var home := Vector3(4.6, 0, 4.9)
	m.player.position = home
	await m._wait(0.5)
	var t: Rect2 = Town.TOWN
	var lot: Rect2 = (m.get_script() as Script).get_script_constant_map()["LOT"]
	var clear := [home, Vector3(t.position.x, 0, t.position.y), Vector3(t.end.x, 0, t.position.y), Vector3(t.end.x, 0, t.end.y),
		Vector3(t.position.x, 0, t.end.y), Vector3(lot.position.x, 0, lot.position.y), Vector3(lot.position.x, 0, lot.end.y), Vector3(lot.end.x, 0, lot.position.y)]
	var worst := 0.0
	for p in clear:
		worst = maxf(worst, fog_at(p))
	m._check("the farm and all of Maple Grove are clear of fog (worst corner %.2f)" % worst, worst < 0.01)
	var lands := {"swamp": Vector3(-60, 0, -6), "foothills": Vector3(30, 0, -75), "beach": Vector3(80, 0, 48), "meadows": Vector3(115, 0, -5)}
	var fogged := true
	var says := []
	for id in lands:
		says.append("%s %.2f" % [id, fog_at(lands[id])])
		fogged = fogged and fog_at(lands[id]) > 0.95
	m._check("the lands round them lie under fog (%s)" % ", ".join(says), fogged)
	m._check("one full-screen quad on its own render layer draws it, and the minimap's camera leaves that layer out (%d x %d cells of %.0f m)" % [cells.x, cells.y, cell],
		_quad.visible and _quad.layers == LAYER and (m.minimap._cam.cull_mask & LAYER) == 0 and cells.x * cells.y < 40000)
	# the edge of the known world from the farm's west side, by day
	Game.hour = 11.0
	m.player.position = Vector3(-6.0, 0, -2.0)
	m.cam_yaw_goal = deg_to_rad(90.0)
	m.cam_yaw = m.cam_yaw_goal
	m.cam_glide = {"pos": Vector3(-34.0, 0, -4.0), "dist": 42.0, "pitch": 34.0}
	await m._wait(3.0)
	await m._shot("65_fog_edge.png")
	# she walks into the swamp: the fog round her is gone, further on it isn't
	var swamp: Vector3 = lands["swamp"]
	m.player.position = swamp
	await m._wait(0.6)
	var on := fog_at(swamp)
	var ahead := fog_at(swamp + Vector3(-reveal_radius - 8.0, 0, 0))
	m._check("where she has been the fog is gone (%.2f), %.0f m on it's still there (%.2f)" % [on, reveal_radius + 8.0, ahead], on < 0.01 and explored_at(swamp) and ahead > 0.9)
	m.cam_glide = {"pos": swamp, "dist": 34.0, "pitch": 38.0}
	m.minimap.set_zoom(2)
	await m._wait(3.0)
	await m._shot("65_fog_cleared.png")
	# the minimap, close
	var img: Image = m.get_viewport().get_texture().get_image()
	var mr: Rect2 = m.minimap.get_global_rect()
	var sc: Vector2 = Vector2(img.get_size()) / m.get_viewport().get_visible_rect().size
	var crop := Rect2i(Vector2i(mr.position * sc), Vector2i(mr.size * sc))
	if crop.size.x > 0 and crop.size.y > 0 and Rect2i(Vector2i.ZERO, img.get_size()).encloses(crop):
		img.get_region(crop).save_png(m._autotest_dir.path_join("65_fog_minimap.png"))
		print("SHOT 65_fog_minimap.png")
	m._check("the minimap is drawing (zoom %d, %.0f m across)" % [m.minimap.zoom, m.minimap.span()], m.minimap.is_visible_in_tree())
	# the dog, played, clears it too
	if m.dog != null and m.dog.visible:
		var spot := Vector3(-75.0, 0, 12.0)
		m.toggle_dog(true)
		m.dog.position = spot
		await m._wait(0.6)
		m._check("playing the dog clears the fog where he goes (%.2f)" % fog_at(spot), fog_at(spot) < 0.01)
		m.toggle_dog(false)
		m.dog.position = m.player.position + Vector3(1.0, 0, 0)
	# the save keeps what she has explored
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	var s: String = str((saved.get("flags", {}) as Dictionary).get("explored", ""))
	Game.flags.erase("explored")
	load_from_flags()
	var lost := fog_at(swamp) > 0.9
	Game.flags["explored"] = s
	load_from_flags()
	m._check("the save keeps it (%d characters): cleared again after loading (%.2f, before loading %s), the rest still fogged" % [s.length(), fog_at(swamp), "fogged" if lost else "clear?"],
		lost and fog_at(swamp) < 0.01 and fog_at(lands["meadows"]) > 0.95 and s.length() < 6000 and explored_share() > 0.0)
	# at night it isn't a glowing sheet
	Game.hour = 22.5
	m.player.position = Vector3(-6.0, 0, -2.0)
	m.cam_glide = {"pos": Vector3(-34.0, 0, -4.0), "dist": 42.0, "pitch": 34.0}
	await m._wait(3.0)
	await m._shot("65_fog_night.png")
	var col: Color = _mat.get_shader_parameter("color")
	m._check("by night the fog takes the night's colour (%.2f)" % col.get_luminance(), col.get_luminance() < 0.25)
	# put it all back
	if keep["explored"] == null:
		Game.flags.erase("explored")
	else:
		Game.flags["explored"] = keep["explored"]
	load_from_flags()
	enabled = bool(keep["enabled"])
	Game.hour = float(keep["hour"])
	Game.time_running = bool(keep["running"])
	m.player.position = keep["pos"]
	m.minimap.zoom = int(keep["zoom"])
	m.cam_glide = {}
	m.cam_target = m.player.position
