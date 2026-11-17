extends Node
## Bonfires (Alex, 2026-11-17: "Costs 1/2 tree to start a bonfire that lasts through the night.
## This allows her to keep exploring through the night and catching animals.")
##
## From dusk she can start one on open ground: the ground ring's "Start a bonfire" row (main.gd's
## ground_actions()) walks her there and takes half a felled tree's wood (data/economy.json
## "bonfire" "wood": a tree gives "forage" "tree_wood" 8, so 4). It burns until the next dawn and
## then goes out by itself.
##
## What it does for her:
## - The night is hers. At midnight she would fall asleep where she stood; while a bonfire of hers
##   burns anywhere, the night goes on instead (Game.stay_up(): the day turns over without sleep,
##   none of sleep's rest) until she goes to bed or morning comes. That gives her the small hours,
##   the darkest and quietest of the 20-minute day, to round up animals with the dog.
## - It keeps her warm: within "warm_radius" her warmth heads for at least "warmth"
##   (main.warmth_target()), so she doesn't shiver her energy away out there, and its menu has
##   "Warm up by the fire".
## - It lights the ground round it (a warm light from Catalog.omni(), so it joins the light budget),
##   a place to come back to in the dark.
##
## Each fire is Game.flags["bonfires"]: [x, z, the game hour it goes out] (hours counted like
## OnlineStore.now_h(), (day - 1) * 24 + hour), so it keeps through a save. Fires are hers and last
## one night, like the walls she builds they live in the save, never in data/world_layout.json, so
## the world editor doesn't list them.
##
## The look reuses the fireplace's pieces (Catalog.fire_material(), flame_quad(), _sparks()):
## three sheets of shader flame, a bed of coals and rising sparks, on a ring of stones and a
## tepee of logs built here from plain shapes.

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")

const GAP := 3.0 # metres between two fires
const STAND := 1.2 # she builds it from this far off

var main # main.gd
var data := {}
var fires: Array = [] # the Fire nodes burning now
var _t := 0.0


func _ready() -> void:
	name = "Bonfires"
	data = Data.load_json("economy").get("bonfire", {})


func econ(key: String, fallback):
	return data.get(key, fallback)


func wood_cost() -> int:
	return int(econ("wood", 4))


## The game's clock in hours since day 1 began: it runs on across midnight and sleep.
static func now_h() -> float:
	return float(Game.day - 1) * 24.0 + Game.hour


## The first dawn (6:00) after the hour `h`.
static func dawn_after(h: float) -> float:
	var day0 := floorf(h / 24.0) * 24.0
	var dawn := day0 + Game.DAY_START
	return dawn if h < dawn else dawn + 24.0


## From dusk until dawn: when a fire can be lit.
func is_evening() -> bool:
	return Game.hour >= float(econ("from_hour", 18.0)) or Game.hour < Game.DAY_START


# --- lighting one ------------------------------------------------------------------------------

## Why she can't start a fire at `g` ("" when she can).
func problem_at(g: Vector3) -> String:
	var q := Vector2(g.x, g.z)
	if not is_evening():
		return "Save the wood for tonight: a bonfire only lasts till dawn."
	if Game.count("wood") < wood_cost():
		return "You need %d wood (half a tree). Fell one with the axe, or buy wood from Steve." % wood_cost()
	if Town.TOWN.has_point(q):
		return "Not in the middle of town."
	if main.building_at(g) or Interiors.inside_of(g) != "":
		return "Not indoors!"
	if not main._walkable(main._cell(g)):
		return "There's no room for a fire there."
	for f in fires:
		if Vector2(f.position.x, f.position.z).distance_to(q) < GAP:
			return "There's a fire burning there already."
	return ""


## The ground ring's row for a spot (main.ground_actions()): only from dusk.
func rows_for(g: Vector3) -> Array:
	if not is_evening():
		return []
	var why := problem_at(g)
	var row: Dictionary = main._act("bonfire", "Start a bonfire  (%d wood · burns till dawn)" % wood_cost(), why == "")
	if why != "":
		row["hint"] = why
	return [row]


## She walks over and builds a fire at `g`. True if she set off.
func start(g: Vector3) -> bool:
	if main.player.busy:
		return false
	var why := problem_at(g)
	if why != "":
		main.hud.show_toast(why)
		return false
	g.y = 0.0
	var away: Vector3 = main.player.position - g
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
	main._tool_walk(g, g + away * STAND, 3.0, "Building a fire", 2.5, _finish.bind(g))
	return true


func _finish(g: Vector3) -> void:
	if problem_at(g) != "" or not Game.take_item("wood", wood_cost()):
		main.hud.show_toast(problem_at(g))
		return
	light(g)
	Game.add_need("happiness", 3.0)
	main.hud.show_toast("The bonfire catches. It'll burn till dawn, and the night is yours while it does.")


## A fire at `g` that burns until the next dawn. Returns its node.
func light(g: Vector3, until := -1.0) -> Node3D:
	if until < 0.0:
		until = dawn_after(now_h())
	var f := Fire.new()
	f.home = self
	f.until = until
	f.position = Vector3(g.x, 0.0, g.z)
	main.add_child(f)
	f.build(float(econ("light_range", 15.0)), float(econ("light_energy", 3.4)))
	fires.append(f)
	_save()
	return f


func put_out(f) -> void:
	fires.erase(f)
	if is_instance_valid(f):
		f.queue_free()
	_save()


func _save() -> void:
	var list := []
	for f in fires:
		list.append([snappedf(f.position.x, 0.01), snappedf(f.position.z, 0.01), snappedf(f.until, 0.001)])
	if list.is_empty():
		Game.flags.erase("bonfires")
	else:
		Game.set_flag("bonfires", list)


## The fires in the save, burning again (main.gd calls it once the save is loaded).
func apply() -> void:
	for f in fires:
		if is_instance_valid(f):
			f.queue_free()
	fires.clear()
	var keep := []
	for e in Game.flag("bonfires", []):
		if e is Array and (e as Array).size() >= 3:
			keep.append(e)
	for e in keep:
		if float(e[2]) > now_h():
			light(Vector3(float(e[0]), 0, float(e[1])), float(e[2]))
	_save()


# --- what it does ------------------------------------------------------------------------------

func burning() -> bool:
	return not fires.is_empty()


## At midnight: true if a fire of hers is still burning, so she stays up (main.gd).
func keeps_her_up() -> bool:
	for f in fires:
		if f.until > now_h():
			return true
	return false


## True if `p` is within a fire's warmth.
func warms(p: Vector3) -> bool:
	var r := float(econ("warm_radius", 7.0))
	for f in fires:
		if Vector2(f.position.x - p.x, f.position.z - p.z).length() < r:
			return true
	return false


func warmth() -> float:
	return float(econ("warmth", 78.0))


## Twice a second: a fire whose dawn has come goes out.
func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or fires.is_empty():
		return
	_t = 0.5
	update()


func update() -> void:
	var now := now_h()
	var out := 0
	for f in fires.duplicate():
		if f.until <= now:
			fires.erase(f)
			f.queue_free()
			out += 1
	if out > 0:
		_save()
		if main.hud and not main.sleeping:
			main.hud.show_toast("Dawn. The bonfire has burned down to ash.")


func warm_up(f) -> void:
	var w: Dictionary = econ("warm_up", {})
	main.player.face_point(f.global_position)
	main.player.start_activity("Warming up", float(w.get("secs", 3.0)), func():
		Game.add_need("warmth", float(w.get("warmth", 25.0)))
		Game.add_need("energy", float(w.get("energy", 6.0)))
		Game.add_need("happiness", 2.0))


## Half a night's rest (Alex, 2026-11-17): she curls up by the fire and sleeps till 6:00 like bed
## (main._go_to_sleep), but wakes with only `sleep_rest` energy more than she lay down with, so she
## can stay out herding without walking home to bed.
func sleep_rest() -> float:
	return float(econ("sleep_rest", 50.0))


func sleep_by(f) -> void:
	var p: Vector3 = f.stand_point()
	var yaw := atan2(f.global_position.x - p.x, f.global_position.z - p.z)
	main.player.start_activity("Zzz", 1.8, func(): pass, p, yaw)
	main._go_to_sleep(false, sleep_rest())


## One bonfire: a ring of stones, a tepee of logs, the fireplace's shader flames scaled up, coals,
## sparks and a warm flickering light. Click it for its menu.
class Fire extends Node3D:
	var home # bonfire.gd
	var until := 0.0 # the game hour it goes out (bonfire.now_h())
	var light: OmniLight3D
	var _t := 0.0
	var _base := 3.4

	func display_name() -> String:
		return "Bonfire"

	func ke_actions() -> Array:
		var left := maxf(0.0, until - home.now_h())
		return [
			{"id": "warm_up", "label": "Warm up by the fire", "enabled": true},
			{"id": "sleep_fire", "label": "Sleep by the fire  (+%d energy, till morning)" % int(home.sleep_rest()), "enabled": true},
			{"id": "noop", "label": "Burns till dawn  (%d hr%s left)" % [ceili(left), "" if ceili(left) == 1 else "s"], "enabled": false},
			{"id": "put_out", "label": "Put it out", "enabled": true},
		]

	func ke_action(id: String) -> void:
		match id:
			"warm_up":
				home.warm_up(self)
			"sleep_fire":
				home.sleep_by(self)
			"put_out":
				home.put_out(self)

	func stand_point() -> Vector3:
		var away: Vector3 = home.main.player.position - position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
		return position + away * 1.4

	func build(rng: float, energy: float) -> void:
		name = "Bonfire"
		_base = energy
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.46, 0.44, 0.41)
		stone.roughness = 0.95
		var sooty := StandardMaterial3D.new()
		sooty.albedo_color = Color(0.2, 0.18, 0.16)
		sooty.roughness = 1.0
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color(0.36, 0.24, 0.15)
		bark.roughness = 0.9
		var char_end := StandardMaterial3D.new()
		char_end.albedo_color = Color(0.09, 0.07, 0.06)
		char_end.emission_enabled = true
		char_end.emission = Color(1.0, 0.35, 0.08)
		char_end.emission_energy_multiplier = 0.6
		var rng_stones := RandomNumberGenerator.new()
		rng_stones.seed = hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0)))
		# a ring of eleven fieldstones
		for i in 11:
			var a := TAU * float(i) / 11.0 + rng_stones.randf_range(-0.12, 0.12)
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 10
			sm.rings = 6
			s.mesh = sm
			s.material_override = stone if i % 3 else sooty
			var r := rng_stones.randf_range(0.66, 0.74)
			s.position = Vector3(cos(a) * r, 0.05, sin(a) * r)
			s.scale = Vector3(rng_stones.randf_range(0.22, 0.3), rng_stones.randf_range(0.14, 0.2), rng_stones.randf_range(0.18, 0.24))
			s.rotation.y = -a + rng_stones.randf_range(-0.3, 0.3)
			add_child(s)
		# the ash under it
		var ash := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.62
		cm.bottom_radius = 0.64
		cm.height = 0.02
		cm.radial_segments = 16
		ash.mesh = cm
		ash.material_override = sooty
		ash.position.y = 0.01
		add_child(ash)
		# five logs leaning together in a tepee
		for i in 5:
			var a := TAU * float(i) / 5.0 + 0.3
			var lg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.055
			lm.bottom_radius = 0.075
			lm.height = 0.95
			lm.radial_segments = 8
			lg.mesh = lm
			lg.material_override = bark if i % 2 else char_end
			var foot := Vector3(cos(a) * 0.42, 0.06, sin(a) * 0.42)
			var tip := Vector3(cos(a) * 0.04, 0.72, sin(a) * 0.04)
			var up := (tip - foot).normalized() # a cylinder stands along its Y: lean that from foot to tip
			var side := up.cross(Vector3.UP).normalized()
			lg.transform = Transform3D(Basis(side, up, side.cross(up)), (foot + tip) * 0.5)
			add_child(lg)
		# the fireplace's flames, larger: three sheets, coals, sparks
		var sheets := [
			[Vector2(1.25, 1.55), Vector3(0.0, 0.0, 0.0), 1.0, 1.0],
			[Vector2(0.95, 1.15), Vector3(-0.22, 0.02, 0.1), 0.95, 1.2],
			[Vector2(0.9, 1.22), Vector3(0.24, 0.0, -0.08), 0.9, 0.85],
		]
		for sh in sheets:
			var q: MeshInstance3D = Catalog.flame_quad(self, sh[0], (sh[1] as Vector3) + Vector3(0, 0.05, 0), Catalog.fire_material(float(sh[2]), float(sh[3])))
			q.set_meta("flame", true)
			q.set_meta("self_lit", true)
		var coals: MeshInstance3D = Catalog.flame_quad(self, Vector2(1.0, 1.0), Vector3(0, 0.03, 0), Catalog.fire_material(1.0, 1.0, true))
		coals.mesh.set("center_offset", Vector3.ZERO)
		coals.rotation_degrees = Vector3(-90, 0, 0)
		Catalog._sparks(self, Vector3(0, 0.3, 0))
		var sp := find_child("Sparks", false, false) as GPUParticles3D
		if sp:
			sp.amount = 18
			sp.lifetime = 1.3
			sp.visibility_aabb = AABB(Vector3(-1.5, -0.3, -1.5), Vector3(3.0, 4.0, 3.0))
		light = Catalog.omni(self, Vector3(0, 0.9, 0), Color(1.0, 0.58, 0.28), rng, energy, energy)
		light.set_meta("fire", true)
		light.omni_attenuation = 1.1
		# its hitbox: click it for its menu
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.75
		cyl.height = 1.2
		cs.shape = cyl
		cs.position.y = 0.6
		body.add_child(cs)
		body.set_meta("target", self)
		add_child(body)

	func _process(delta: float) -> void:
		_t += delta
		if light:
			# a fire breathes: two slow swells and a quick flutter
			var f := 0.86 + 0.08 * sin(_t * 2.3) + 0.05 * sin(_t * 5.9 + 1.3) + 0.04 * sin(_t * 13.7)
			light.light_energy = _base * f
			light.position = Vector3(0.05 * sin(_t * 3.1), 0.9 + 0.04 * sin(_t * 4.3), 0.05 * cos(_t * 2.7))


# --- the autotest's check (main.gd _bonfire_checks, --only=bonfire) ----------------------------

## Open ground for a test fire near `p`, or `p`.
func _test_spot(p: Vector3) -> Vector3:
	for r in range(0, 12):
		for k in 8:
			var a := TAU * float(k) / 8.0
			var q := p + Vector3(cos(a), 0, sin(a)) * float(r)
			if problem_at(q) == "" and main._walkable(main._cell(q + Vector3(STAND, 0, 0))):
				return q
	return p


func checks() -> void:
	var m = main
	var keep := {"day": Game.day, "hour": Game.hour, "inv": Game.inv.duplicate(), "energy": Game.energy,
		"fullness": Game.fullness, "happiness": Game.happiness, "warmth": Game.warmth,
		"fires": Game.flags.get("bonfires", null), "stayed": Game.flags.get("stayed_up", null),
		"running": Game.time_running, "pos": m.player.position}
	Game.time_running = false
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	m.player.walk([])
	m.player.cancel_activity()
	for f in fires.duplicate():
		put_out(f)
	Game.energy = 100.0
	var tree_wood := int(m.forage.econ("tree_wood", 8))
	m._check("a bonfire costs half a felled tree's wood (%d of a tree's %d)" % [wood_cost(), tree_wood], wood_cost() * 2 == tree_wood)
	Game.hour = 21.0
	Game.add_item("wood", wood_cost() + 1)
	var spot := _test_spot(Vector3(-9.0, 0, 2.0))
	Game.hour = 12.0
	m._check("by day the ground ring has no bonfire row ('%s')" % problem_at(spot), rows_for(spot).is_empty() and problem_at(spot) != "")
	Game.hour = 21.0
	Game.inv.erase("wood")
	var rows := rows_for(spot)
	m._check("after dark without wood the row is there but greyed ('%s')" % str(rows[0].get("hint", "")) if not rows.is_empty() else "after dark without wood: no row!",
		rows.size() == 1 and not bool(rows[0]["enabled"]))
	Game.add_item("wood", wood_cost() + 1)
	var hc: Vector2 = m.house_rect().get_center()
	var labels: Array = m.ground_actions(spot).map(func(a): return a["label"])
	m._check("with wood, the ground ring offers it (%s); not indoors ('%s') nor in the town square ('%s')" % [str(labels), problem_at(Vector3(hc.x, 0, hc.y)), problem_at(Vector3(53, 0, -1))],
		labels.any(func(l): return str(l).begins_with("Start a bonfire")) and problem_at(Vector3(hc.x, 0, hc.y)) != "" and problem_at(Vector3(53, 0, -1)) != "")
	# she lights one through the ground ring
	m.player.position = spot + Vector3(3.0, 0, 0)
	m._ground_action("bonfire", spot, spot)
	var waited := 0.0
	while fires.is_empty() and waited < 12.0:
		await m._wait(0.25)
		waited += 0.25
	var f = fires[0] if not fires.is_empty() else null
	var flames := 0
	if f != null:
		for c in f.get_children():
			if c is MeshInstance3D and c.has_meta("flame"):
				flames += 1
	m._check("she walks over and builds it (%.1f s): %d wood left, three sheets of flame (%d), coals, sparks and a warm light in the light budget, saved in the game" % [waited, Game.count("wood"), flames],
		f != null and Game.count("wood") == 1 and flames == 3 and f.find_child("Sparks", false, false) != null
		and f.light != null and f.light.is_in_group("lamp_shadow") and f.light.omni_range >= 12.0
		and (Game.flag("bonfires", []) as Array).size() == 1)
	if f == null:
		_restore(keep)
		return
	var dawn := dawn_after(float(keep["day"] - 1) * 24.0 + 21.0)
	m._check("it burns till dawn (out at hour %.1f, day %d 6:00)" % [f.until, int(f.until / 24.0) + 1], is_equal_approx(f.until, float(Game.day) * 24.0 + 6.0) or is_equal_approx(f.until, dawn))
	var acts: Array = m._actions_for(f).map(func(a): return a["label"])
	m._check("its menu: %s" % str(acts), acts.size() == 4 and str(acts[0]).begins_with("Warm up") and str(acts[1]).begins_with("Sleep by the fire") and str(acts[3]) == "Put it out")
	# pictures at night
	m.cam_glide = {"pos": f.position, "dist": 8.0, "pitch": 26.0}
	Game.hour = 22.5
	await m._wait(2.5)
	await m._shot("64_bonfire_night.png")
	m.cam_glide = {"pos": f.position, "dist": 22.0, "pitch": 40.0}
	await m._wait(2.5)
	await m._shot("64_bonfire_wide.png")
	# warm by it, cold away from it
	var near: float = m.warmth_target()
	m.player.position = f.position + Vector3(25.0, 0, 0)
	var far: float = m.warmth_target()
	m._check("by the fire her warmth heads for %.0f, %.0f away from it" % [near, far], near >= warmth() and far < near and warms(f.position + Vector3(2, 0, 0)) and not warms(f.position + Vector3(25, 0, 0)))
	m.player.position = spot + Vector3(3.0, 0, 0)
	Game.warmth = 30.0
	m._do_action(f, "warm_up")
	await m._wait(6.0)
	m._check("'Warm up by the fire' warms her (warmth %.0f)" % Game.warmth, Game.warmth >= 50.0)
	# midnight: she stays up
	var day0 := Game.day
	Game.hour = 23.97
	Game.time_running = true
	await m._wait(1.2)
	Game.time_running = false
	m._check("at midnight with the fire burning she stays up: day %d -> %d, %.2fh, not asleep" % [day0, Game.day, Game.hour],
		Game.day == day0 + 1 and Game.hour < 1.0 and not m.sleeping and int(Game.flags.get("stayed_up", 0)) == Game.day and fires.size() == 1)
	m.cam_glide = {"pos": f.position, "dist": 10.0, "pitch": 30.0}
	await m._wait(1.5)
	await m._shot("64_bonfire_midnight.png")
	# the save keeps it
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	var where: Vector3 = f.position
	for g in fires.duplicate():
		fires.erase(g)
		g.queue_free()
	Game.flags["bonfires"] = (saved.get("flags", {}) as Dictionary).get("bonfires", [])
	apply()
	m._check("the save keeps it burning where it was (%s)" % str(Game.flags.get("bonfires")),
		fires.size() == 1 and Vector2(fires[0].position.x, fires[0].position.z).distance_to(Vector2(where.x, where.z)) < 0.05)
	# to bed in the small hours: no second new day; morning puts it out
	var day1 := Game.day
	Game.sleep()
	update()
	m._check("bed in the small hours: still day %d (was %d), 6:00, and the fire is out at dawn" % [Game.day, day1],
		Game.day == day1 and is_equal_approx(Game.hour, 6.0) and fires.is_empty() and not Game.flags.has("bonfires") and not Game.flags.has("stayed_up"))
	m._check("with no fire burning, midnight still means bed", not keeps_her_up())
	# sleeping by a fire: till morning, half a night's rest, no walk home
	Game.hour = 1.5
	Game.flags["stayed_up"] = Game.day # up past midnight by it, as above
	var g = light(spot)
	var gp: Vector3 = g.position
	Game.energy = 20.0
	var day2 := Game.day
	var bed_dist: float = m.player.position.distance_to(Vector3(hc.x, 0, hc.y))
	m._do_action(g, "sleep_fire")
	waited = 0.0
	await m._wait(0.3)
	while m.sleeping and waited < 8.0:
		await m._wait(0.25)
		waited += 0.25
	m._check("'Sleep by the fire' sleeps her there till 6:00 (day %d, %.1fh) with half a night's rest (energy 20 -> %.0f), not walking home (%.0f m from the house)" % [Game.day, Game.hour, Game.energy, bed_dist],
		not m.sleeping and Game.day == day2 and is_equal_approx(Game.hour, 6.0) and is_equal_approx(Game.energy, 20.0 + sleep_rest())
		and m.player.position.distance_to(gp) < 3.0)
	m.player.cancel_activity()
	_restore(keep)


func _restore(keep: Dictionary) -> void:
	var m = main
	for f in fires.duplicate():
		put_out(f)
	Game.day = int(keep["day"])
	Game.hour = float(keep["hour"])
	Game.inv = keep["inv"]
	Game.energy = float(keep["energy"])
	Game.fullness = float(keep["fullness"])
	Game.happiness = float(keep["happiness"])
	Game.warmth = float(keep["warmth"])
	for k in [["fires", "bonfires"], ["stayed", "stayed_up"]]:
		if keep[k[0]] == null:
			Game.flags.erase(k[1])
		else:
			Game.flags[k[1]] = keep[k[0]]
	Game.time_running = bool(keep["running"])
	m.player.cancel_activity()
	m.player.position = keep["pos"]
	m.cam_glide = {}
	m.cam_target = m.player.position
	m.hud.hide_dialogue()
