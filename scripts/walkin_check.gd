extends RefCounted
## Marcus's house, the one you can walk into (--only=walkin, and part of the full run; split_house.gd,
## data/split_house.json): Nora walks in at the front door to the living room on the ground, up the
## half flight to the kids' room on the bedroom floor, down the long flight to the basement (the
## basement takes over the house's cells on the walking grid, the floors above are hidden and the
## ground over the house isn't drawn) and through to the rec room, then back up. Saves
## 67_walkin_living.png, 67_walkin_upstairs.png, 67_walkin_basement.png and 67_walkin_fps.png.

var main: Node
var wi = null


func run(m: Node) -> void:
	main = m
	wi = main.suburb.walk_in if main.suburb != null else null
	main._check("one Bretton Oaks house can be walked into", wi != null and wi.house != null)
	if wi == null:
		return
	var rooms := 0
	for k in ["main", "upper", "basement"]:
		for n in (wi.roots[k] as Node3D).get_children():
			if n is MeshInstance3D and str(n.name).begins_with("Floor_"):
				rooms += 1
	var pieces := 0
	for k in wi.roots:
		for n in (wi.roots[k] as Node3D).get_children():
			if n.has_meta("item_id") and n.get_child_count() > 0:
				pieces += 1
	var want: int = (wi.cfg["furniture"] as Array).size()
	main._check("its three floors are laid with their rooms' floors (%d) and furnished (%d of %d)" % [rooms, pieces, want], rooms >= 13 and pieces == want)
	var nora0: Vector3 = main.player.position
	var dog0: Vector3 = main.dog.position if main.dog else Vector3.ZERO
	var hour0: float = Game.hour
	Game.hour = 12.0
	main._set_cam_lock(false)
	# in at the front door to the living room
	main.player.position = wi.house.global_transform * Vector3(-2.5, 0, 4.8)
	if main.dog:
		main.dog.position = main.player.position + Vector3(1, 0, 0)
	await main._wait(0.3)
	var ok: bool = await _walk(Vector3(-2.0, 0, -1.0))
	main._check("in at the front door to the living room (inside %s, at %.2f m, the roof lifted %s)" % [wi.inside, main.player.position.y, not (wi.parts["roof"] as Node3D).visible],
		ok and wi.inside and absf(main.player.position.y) < 0.05 and not (wi.parts["roof"] as Node3D).visible)
	await _picture(Vector3(-2.4, 0, -0.6), 15.0, 58.0, "67_walkin_living.png")
	# up the half flight to the kids' room
	ok = await _walk(Vector3(5.0, 0, -2.1))
	main._check("up the half flight to the kids' room (at %.2f m)" % main.player.position.y, ok and absf(main.player.position.y - wi.upper_y) < 0.05)
	await _picture(Vector3(3.6, 0.85, -1.8), 14.0, 60.0, "67_walkin_upstairs.png")
	# first person upstairs: the roof off, the bedroom floor's ceiling on
	main.fps.enter()
	await main._wait(0.8)
	main._check("in first person upstairs the roof is off and the bedroom ceilings are on", main.fps.active and not (wi.parts["roof"] as Node3D).visible and (wi.ceilings[0] as Node3D).visible)
	await main._shot("67_walkin_fps.png")
	main.fps.leave()
	await main._wait(0.5)
	# down the long flight: halfway down, the basement takes over
	ok = await _walk(Vector3(3.2, 0, 3.5))
	main._check("down the stairs to the basement (level %d, at %.2f m)" % [wi.level, main.player.position.y], ok and wi.level == wi.BASEMENT and main.player.position.y < -2.0)
	ok = await _walk(Vector3(5.2, 0, -2.6))
	main._check("through the den to the rec room (at %.2f m), the floors above hidden and the ground over the house cut away" % main.player.position.y,
		ok and absf(main.player.position.y - wi.basement_y) < 0.05 and (wi.roots["basement"] as Node3D).visible and not (wi.roots["main"] as Node3D).visible and wi._hole_on)
	await _picture(Vector3(0.0, -2.4, -0.4), 17.0, 62.0, "67_walkin_basement.png")
	# and back up: to the top of the flight, then the living room
	ok = await _walk(Vector3(0.75, 0, 3.5))
	main._check("back up the stairs, the main floor shown again and the ground whole", ok and wi.level == wi.UPPER and (wi.roots["main"] as Node3D).visible and not wi._hole_on)
	ok = await _walk(Vector3(-2.0, 0, -1.0))
	main._check("and on into the living room", ok and absf(main.player.position.y) < 0.05)
	# out of the door again
	ok = await _walk(Vector3(-2.5, 0, 5.2))
	main._check("out of the front door, the roof back on", ok and not wi.inside and (wi.parts["roof"] as Node3D).visible)
	main.player.position = nora0
	if main.dog:
		main.dog.position = dog0
	Game.hour = hour0
	main.cam_glide = {}
	main._set_cam_lock(true)


## Walks her to `to` (the house's space) and waits; true if she got there.
func _walk(to: Vector3, limit := 40.0) -> bool:
	var w: Vector3 = wi.house.global_transform * Vector3(to.x, 0, to.z)
	var path: Array = main._find_path(main.player.position, w)
	if path.is_empty():
		print("WALKIN no path to ", to)
		return false
	main.player.walk(path)
	var t := 0.0
	while t < limit and not main.player.path.is_empty():
		await main._wait(0.25)
		t += 0.25
	var at: Vector3 = main.player.position
	var d := Vector2(at.x - w.x, at.z - w.z).length()
	if d > 0.8:
		print("WALKIN stopped %.2f m short of %s at %s" % [d, to, wi.local(at)])
	return d <= 0.8


func _picture(local_at: Vector3, dist: float, pitch: float, fname: String) -> void:
	var p: Vector3 = wi.house.global_transform * local_at
	main.cam_target = p
	main.cam_dist = dist
	main.cam_pitch = pitch
	main.cam_glide = {"pos": p, "dist": dist, "pitch": pitch}
	main.cam_yaw = wi.house.global_rotation.y + deg_to_rad(10.0)
	main.cam_yaw_goal = main.cam_yaw
	await main._wait(2.0)
	await main._shot(fname)
	main.cam_glide = {}
