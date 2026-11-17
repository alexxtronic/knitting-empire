extends RefCounted
## Marcus's house, the one you can walk into (--only=walkin, and part of the full run; split_house.gd,
## data/split_house.json): Nora walks in at the front door to the living room on the ground, up the
## half flight to the kids' room and each bedroom on the bedroom floor, down the flight beside it into
## the basement's green den (the basement takes over the house's cells on the walking grid, the
## floors above are hidden and the ground over the house isn't drawn), its bathroom and through to
## the rec room, then back up. Saves
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
	main._check("its three floors are laid with their rooms' floors (%d) and furnished (%d of %d)" % [rooms, pieces, want], rooms >= (wi.cfg["rooms"] as Array).size() and pieces == want)
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
	# up the half flight: every bedroom off the hall, as in Alex's plan
	ok = await _walk(Vector3(4.8, 0, -1.0))
	main._check("up the half flight to the kids' room (at %.2f m)" % main.player.position.y, ok and absf(main.player.position.y - wi.upper_y) < 0.05)
	await _picture(Vector3(3.4, 0.85, -0.6), 14.0, 62.0, "67_walkin_upstairs.png")
	var rooms_ok := true
	for r in [["baby", Vector3(1.9, 0, -2.7)], ["master", Vector3(4.6, 0, 0.8)], ["ensuite", Vector3(3.05, 0, 2.7)], ["kids", Vector3(4.8, 0, -1.0)]]:
		var got: bool = await _walk(r[1])
		if not got:
			for zi in range(0, 9):
				var line := ""
				for xi in range(0, 14):
					var q := Vector3(2.5 + xi * 0.2, 0, 1.5 + zi * 0.2)
					line += "." if main._walkable(main._cell(wi.house.global_transform * q)) else "#"
				print("WALKIN grid z %.2f %s" % [1.5 + zi * 0.2, line])
		if not got:
			print("WALKIN couldn't reach the ", r[0])
		rooms_ok = rooms_ok and got
	main._check("the baby's room and the master are each through their own door off the hall, and the ensuite (with its bathtub) through the master's", rooms_ok)
	# first person upstairs: the roof off, the bedroom floor's ceiling on
	main.fps.enter()
	await main._wait(0.8)
	main._check("in first person upstairs the roof is off and the bedroom ceilings are on", main.fps.active and not (wi.parts["roof"] as Node3D).visible and (wi.ceilings[0] as Node3D).visible)
	await main._shot("67_walkin_fps.png")
	main.fps.leave()
	await main._wait(0.5)
	# down the flight beside it: halfway down, the basement takes over; at the foot, the green den
	ok = await _walk(Vector3(1.5, 0, 2.7))
	main._check("down the stairs to the basement (level %d, at %.2f m)" % [wi.level, main.player.position.y], ok and wi.level == wi.BASEMENT and main.player.position.y < -1.2)
	ok = await _walk(Vector3(3.5, 0, 1.2))
	main._check("off the stairs straight into the green shag den (at %.2f m)" % main.player.position.y, ok and absf(main.player.position.y - wi.basement_y) < 0.05)
	var areas := {}
	for room in wi.cfg["rooms"]:
		var a := 0.0
		for r in room["rects"]:
			a += float(r[2]) * float(r[3])
		areas[str(room["id"])] = a
	main._check("the basement's green shag den is as big as its black-tile rec room (%.1f and %.1f m2)" % [areas.get("den", 0.0), areas.get("rec_room", 0.0)],
		areas.has("den") and absf(float(areas["den"]) - float(areas.get("rec_room", 0.0))) < 0.2)
	# the bathroom, to the right at the foot of the stairs: its door swings open as she comes up to it
	ok = await _walk(Vector3(2.9, 0, 2.8))
	await main._wait(0.8)
	var bdoor: Dictionary = {}
	for d in wi.doors:
		if (d["c"] as Vector2).distance_to(Vector2(2.9, 3.4)) < 0.2:
			bdoor = d
	main._check("up to the basement bathroom beside the stairs, whose door swings open for her (%.2f open)" % (float(bdoor.get("open", 0.0))),
		ok and not bdoor.is_empty() and float(bdoor["open"]) > 0.6)
	ok = await _walk(Vector3(3.4, 0, -2.5))
	main._check("through the den's door to the rec room (at %.2f m), the floors above hidden and the ground over the house cut away" % main.player.position.y,
		ok and absf(main.player.position.y - wi.basement_y) < 0.05 and (wi.roots["basement"] as Node3D).visible and not (wi.roots["main"] as Node3D).visible and wi._hole_on)
	await _picture(Vector3(3.4, -2.4, 0.0), 13.0, 64.0, "67_walkin_basement.png")
	# and back up: to the top of the flight, then the living room
	ok = await _walk(Vector3(0.75, 0, 2.7))
	main._check("back up the stairs, the main floor shown again and the ground whole", ok and wi.level == wi.UPPER and (wi.roots["main"] as Node3D).visible and not wi._hole_on)
	ok = await _walk(Vector3(-2.0, 0, -1.0))
	main._check("and on into the living room", ok and absf(main.player.position.y) < 0.05)
	# out through the sliding door at the back of the dining room, and in again
	ok = await _walk(Vector3(-2.8, 0, -5.4))
	var sdoor: Dictionary = {}
	for d in wi.doors:
		if str(d["kind"]) == "slide" and (d["c"] as Vector2).distance_to(Vector2(-2.8, -4.16)) < 0.2:
			sdoor = d
	main._check("out to the back garden through the dining room's sliding door, which slides open for her (%.2f open)" % float(sdoor.get("open", 0.0)),
		ok and not wi.inside and not sdoor.is_empty() and float(sdoor["open"]) > 0.6)
	await _picture(Vector3(-2.8, 0, -4.2), 9.0, 30.0, "67_walkin_back_door.png", 190.0)
	ok = await _walk(Vector3(-2.0, 0, -1.0))
	main._check("and back in to the living room", ok and wi.inside)
	# out of the door again
	ok = await _walk(Vector3(-2.5, 0, 5.2))
	main._check("out of the front door, the roof back on", ok and not wi.inside and (wi.parts["roof"] as Node3D).visible)
	await _editor_checks()
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


func _picture(local_at: Vector3, dist: float, pitch: float, fname: String, yaw := 10.0) -> void:
	var p: Vector3 = wi.house.global_transform * local_at
	main.cam_target = p
	main.cam_dist = dist
	main.cam_pitch = pitch
	main.cam_glide = {"pos": p, "dist": dist, "pitch": pitch}
	main.cam_yaw = wi.house.global_rotation.y + deg_to_rad(yaw)
	main.cam_yaw_goal = main.cam_yaw
	await main._wait(2.0)
	await main._shot(fname)
	main.cam_glide = {}


## The world editor's house tools (house_edit.gd) on the main floor: a wall drawn across the kitchen
## and living room, a door, a window and sliding doors put in it, an oak floor laid in the dining room,
## the wall picked and deleted; then everything undone. The layout goes to a test file of its own.
func _editor_checks() -> void:
	var god = main.god
	if not god.is_admin():
		return
	var path0: String = god.layout_path
	god.layout_path = "user://autotest_walkin_layout.json"
	var walls0: int = (wi.cfg["walls"] as Array).size()
	var rooms0: int = (wi.cfg["rooms"] as Array).size()
	var undo0: int = god.undo_stack.size()
	god.set_active(true)
	await main._wait(0.3)
	await main._god_look(wi.house.global_transform * Vector3(-3.5, 0, -1.0), 14.0)
	await main._wait(0.8)
	var ht = god.house_tools
	god.set_tool("h_wall")
	await _drag_at("h_wall", Vector3(-6.3, 0, -0.5), Vector3(-1.5, 0, -0.5))
	var drew: bool = (wi.cfg["walls"] as Array).size() == walls0 + 1
	var mid: Vector2i = main._cell(wi.house.global_transform * Vector3(-3.6, 0, -0.5))
	main._check("house editor: a wall drawn across the main floor (%s) blocks the way there (%s)" % [drew, not main._walkable(mid)], drew and not main._walkable(mid))
	for t in [["h_door", -5.8], ["h_window", -4.6], ["h_slide", -2.6]]:
		god.set_tool(str(t[0]))
		ht.press(str(t[0]), _screen(Vector3(float(t[1]), 0, -0.5)))
		ht.release()
	var ops: Array = wi.cfg["walls"][walls0]["doors"] if drew else []
	var kinds := ops.map(func(o): return str(o[2]))
	var door_cell: Vector2i = main._cell(wi.house.global_transform * Vector3(-5.8, 0, -0.5))
	var win_cell: Vector2i = main._cell(wi.house.global_transform * Vector3(-4.6, 0, -0.5))
	main._check("house editor: a door, a window and sliding doors in it (%s; %d doors built), the door's way open (%s) and the window's shut (%s)" % [kinds, wi.doors.size(), main._walkable(door_cell), not main._walkable(win_cell)],
		kinds == ["door", "window", "slide"] and main._walkable(door_cell) and not main._walkable(win_cell) and wi.doors.size() >= 5)
	god.set_tool("h_floor")
	ht.floor_kind = "wood_oak"
	await _drag_at("h_floor", Vector3(-6.0, 0, -3.8), Vector3(-4.0, 0, -2.0))
	var patch: Dictionary = wi.cfg["rooms"][-1]
	main._check("house editor: an oak floor laid over the dining room's tiles (%s)" % str(patch.get("floor", "")),
		(wi.cfg["rooms"] as Array).size() == rooms0 + 1 and bool(patch.get("patch", false)) and str(patch["floor"]) == "wood_oak")
	await main._wait(0.4)
	await main._shot("67_walkin_editor.png")
	var saved: Dictionary = god.layout()
	var in_file: bool = saved.has("split_house") and (saved["split_house"]["walls"] as Array).size() == walls0 + 1
	god.set_tool("h_wall")
	# picked by a click on its top, as it's seen from above (Alex, 2026-11-17: clicks there used to
	# land on the floor behind it and start a new wall instead)
	var top := _wall_top(walls0)
	ht.press("h_wall", main.cam.unproject_position(top))
	ht.release()
	var picked: bool = wi.selected_wall == walls0 and (wi.cfg["walls"] as Array).size() == walls0 + 1
	var deleted: bool = ht.delete_selected() and (wi.cfg["walls"] as Array).size() == walls0
	while god.undo_stack.size() > undo0:
		god.undo()
	main._check("house editor: the layout keeps the house's walls and floors (%s); the wall picked (%s) and deleted (%s); undo puts the house back as it was (%d walls, %d rooms)" % [in_file, picked, deleted, (wi.cfg["walls"] as Array).size(), (wi.cfg["rooms"] as Array).size()],
		in_file and picked and deleted and (wi.cfg["walls"] as Array).size() == walls0 and (wi.cfg["rooms"] as Array).size() == rooms0)
	god.set_tool("select")
	god.house_split_edited = false
	god.unsaved = false
	god.set_active(false)
	god.layout_path = path0
	await main._wait(0.3)


## The top middle of wall `i` as it stands shown (full height, or cut down low toward the camera).
func _wall_top(i: int) -> Vector3:
	for w in wi.walls:
		if int(w.get("i", -1)) != i:
			continue
		for part in ["full", "low"]:
			var mi = w.get(part)
			if mi is MeshInstance3D and is_instance_valid(mi) and (mi as MeshInstance3D).is_visible_in_tree():
				var b: AABB = (mi as MeshInstance3D).get_aabb()
				return (mi as MeshInstance3D).global_transform * (b.get_center() + Vector3(0, b.size.y * 0.5 - 0.02, 0))
	return wi.house.global_transform * Vector3(-3.3, 2.0, -0.5)


func _screen(local_at: Vector3) -> Vector2:
	return main.cam.unproject_position(wi.house.global_transform * local_at)


func _drag_at(tool: String, a: Vector3, b: Vector3) -> void:
	var ht = main.god.house_tools
	ht.press(tool, _screen(a))
	for i in 5:
		ht.move(_screen(a.lerp(b, float(i + 1) / 5.0)))
		await main._wait(0.05)
	ht.release()
	await main._wait(0.2)
