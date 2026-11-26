extends Node3D
## A few shore crabs on Saltmeadow Beach (2026-11-26): they sit on the sand, scuttle sideways a little
## now and then, and when Nora or the dog comes within `flush` metres they dash off sideways and dig
## themselves into the sand, coming up again a little way off once it's quiet.
##
## Made by scripts/wildlife.gd from data/wildlife.json "crabs" ([zone, how many] per group) and culled
## with the birds. A STAND-IN from plain shapes (a shell, two claws, eight legs) until a model is made
## (docs/DIRECTION.md "Models still needed").

const SPREAD := 2.5 # metres round the group's spot
const HIDE_SECS := 9.0 # under the sand before coming up again

var main: Node
var wl: Node
var zone := Rect2()
var flush := 3.0
var crabs: Array = [] # one Dictionary per crab: node, legs, target, burrowed, t
var burrows := 0 # times one has dug in (for the autotest)


func setup(m: Node, manager: Node, n: int, z: Rect2, count: int, at: Vector3, flush_m: float) -> void:
	main = m
	wl = manager
	zone = z
	flush = flush_m
	name = "Crabs_%d" % n
	position = at
	for i in count:
		crabs.append({"spot": _spot()})


func _ready() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.82, 0.32, 0.18)
	shell.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.55, 0.2, 0.12)
	for c in crabs:
		var node := Node3D.new()
		add_child(node)
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.1
		sm.radial_segments = 10
		sm.rings = 5
		body.mesh = sm
		body.material_override = shell
		body.scale = Vector3(1.4, 0.55, 1.0)
		body.position.y = 0.05
		node.add_child(body)
		for s in [-1.0, 1.0]: # the claws, out in front
			var claw := MeshInstance3D.new()
			var cm := SphereMesh.new()
			cm.radius = 0.035
			cm.height = 0.05
			cm.radial_segments = 8
			cm.rings = 4
			claw.mesh = cm
			claw.material_override = shell
			claw.position = Vector3(s * 0.09, 0.05, 0.09)
			node.add_child(claw)
		var legs := []
		for s in [-1.0, 1.0]:
			for k in 4:
				var leg := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.09, 0.012, 0.012)
				leg.mesh = bm
				leg.material_override = dark
				leg.position = Vector3(s * 0.12, 0.03, -0.04 + 0.03 * k)
				leg.rotation_degrees = Vector3(0, s * (-20.0 + 12.0 * k), s * -25.0)
				node.add_child(leg)
				legs.append(leg)
		node.position = c["spot"]
		node.rotation.y = randf() * TAU
		c["node"] = node
		c["legs"] = legs
		c["target"] = c["spot"]
		c["t"] = randf_range(1.0, 5.0)
		c["burrowed"] = 0.0
		c["fast"] = false


func _spot() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * SPREAD
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## Somewhere open in the zone near the group's spot, in the group's own space.
func _open_near(local: Vector3) -> Vector3:
	for i in 10:
		var q := local + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		var w := global_position + q
		if zone.has_point(Vector2(w.x, w.z)) and main._walkable(main._cell(w)):
			return q
	return local


func _process(delta: float) -> void:
	if main == null:
		return
	var who = wl.flusher(global_position, flush + SPREAD)
	for c in crabs:
		var node: Node3D = c["node"]
		if float(c["burrowed"]) > 0.0: # under the sand
			c["burrowed"] = float(c["burrowed"]) - delta
			if float(c["burrowed"]) <= 0.0 and wl.flusher(global_position + node.position, flush) == null:
				node.position = _open_near(node.position)
				c["target"] = node.position
				node.visible = true
				node.position.y = -0.08
			else:
				c["burrowed"] = maxf(float(c["burrowed"]), 0.01)
			continue
		if node.position.y < 0.0: # coming up out of the sand
			node.position.y = minf(0.0, node.position.y + delta * 0.2)
		var me := global_position + node.position
		if who != null and Vector2(me.x - who.x, me.z - who.z).length() < flush and not c["fast"]:
			var away := Vector3(me.x - who.x, 0, me.z - who.z).normalized()
			c["target"] = node.position + away * 1.6
			c["fast"] = true
		c["t"] = float(c["t"]) - delta
		if float(c["t"]) <= 0.0 and not c["fast"]:
			c["t"] = randf_range(2.0, 6.0)
			c["target"] = _open_near(node.position)
		var to: Vector3 = (c["target"] as Vector3) - node.position
		to.y = 0.0
		var speed := 1.8 if c["fast"] else 0.35
		if to.length() > 0.03:
			var step := minf(to.length(), speed * delta)
			node.position += to.normalized() * step
			# crabs go sideways: the body's side to the way it goes
			var want := atan2(to.x, to.z) + PI * 0.5
			node.rotation.y = lerp_angle(node.rotation.y, want, minf(1.0, delta * 6.0))
			var ph := Time.get_ticks_msec() * 0.03 * speed
			var legs: Array = c["legs"]
			for i in legs.size():
				(legs[i] as Node3D).position.y = 0.03 + 0.012 * sin(ph + i * 1.7)
		elif c["fast"]: # there: dig in
			c["fast"] = false
			c["burrowed"] = HIDE_SECS
			node.visible = false
			burrows += 1
