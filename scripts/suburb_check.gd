extends RefCounted
## The Bretton Oaks check (--only=suburb, and part of the full run): the six houses round the
## cul-de-sac (scripts/suburb.gd) in their parts and colours, three of them mirrored, the house's
## textures through BuildingSkin, the sign's own board, the scenery cleared off the plot, every door
## reachable from the town, a villager going home to bed at night and coming out in the morning, and
## the windows lit after dark. Saves 66_suburb_house.png (the house close up beside Alex's photo),
## 66_suburb_above.png (the cul-de-sac from above) and 66_suburb_night.png.

const REF := "res://art/world_assets/suburb_house/ref/bretton_oaks_house.png"

var main: Node


func run(m: Node) -> void:
	main = m
	var sb = main.suburb
	main._check("Bretton Oaks is built", sb != null and sb.house_list.size() == 6)
	if sb == null or sb.house_list.is_empty():
		return
	# the parts, and the low walls hidden from outside
	var parts_ok := true
	var low_hidden := true
	var kinds := {}
	var bricks := {}
	var mirrored := 0
	for h in sb.house_list:
		var model := h["model"] as Node3D
		if model == null:
			parts_ok = false
			continue
		for part in ["base", "door", "roof", "wall_front", "wall_back", "wall_left", "wall_right"]:
			if model.find_child(part, true, false) == null:
				parts_ok = false
		for n in model.find_children("*_low", "", true, false):
			low_hidden = low_hidden and not (n as Node3D).visible
		var k := {}
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var mm := mi as MeshInstance3D
			for i in mm.mesh.get_surface_count():
				var o := mm.get_surface_override_material(i)
				if o and o.resource_name.begins_with("skin_"):
					k[o.resource_name.substr(5)] = true
				var base := mm.mesh.surface_get_material(i)
				if base and base.resource_name == "suburb_brick" and o:
					bricks[o.get_instance_id()] = true
		kinds[h["i"]] = ",".join(k.keys())
		parts_ok = parts_ok and k.has("brick") and k.has("shingles") and k.has("paintwood")
		if bool(h["mirror"]):
			mirrored += 1
	main._check("six houses round the cul-de-sac in their parts, the low walls hidden, brick, shingles and painted trim from the house's maps (%s)" % str(kinds), parts_ok and low_hidden)
	main._check("each house is its own: %d brick colours, %d of six mirrored" % [bricks.size(), mirrored], bricks.size() >= 5 and mirrored == 3)
	# every house the code places faces the circle; one Alex has moved or turned in the world
	# editor stands where data/world_layout.json puts it, and that's the map
	var facing := true
	var moved := 0
	for h in sb.house_list:
		var n := h["node"] as Node3D
		if n.position.distance_to(h["at"]) > 0.05 or absf(angle_difference(n.rotation.y, float(h["yaw"]))) > 0.01:
			moved += 1
			continue
		var front := n.global_transform.basis.z.normalized()
		var to_c: Vector3 = (sb.centre - n.global_position)
		to_c.y = 0.0
		facing = facing and front.dot(to_c.normalized()) > 0.95
	main._check("every house faces the turning circle, but for those the world layout moved (%d moved)" % moved, facing)
	# the sign
	var face_ok := false
	if sb.sign_node:
		for mi in sb.sign_node.find_children("*", "MeshInstance3D", true, false):
			var mm := mi as MeshInstance3D
			for i in mm.mesh.get_surface_count():
				var o := mm.get_surface_override_material(i) as BaseMaterial3D
				if o and o.resource_name == "sign_face_bretton_oaks" and o.albedo_texture and o.albedo_texture.resource_path.ends_with("bretton_oaks_face.png"):
					face_ok = true
	main._check("the town's sign stands at the road in, its board reading Bretton Oaks", face_ok)
	# the world editor has them
	var editable := 0
	for el in main.god.els:
		if el.kind == sb.KIND or el.kind == sb.SIGN_KIND:
			editable += 1
	main._check("the world editor can move each house and the sign (%d)" % editable, editable == 7)
	# nothing left growing on the plot
	var standing: Array = []
	for el in main.god.els:
		if el.scenery and not el.deleted and not el.cut and sb.clears(el.xf.origin):
			standing.append(el.kind)
	main._check("the plot is cleared of trees, rocks and bushes (%d still standing%s)" % [standing.size(), (": " + ", ".join(standing.slice(0, 6))) if standing.size() > 0 else ""], standing.is_empty())
	# the turning circle and the road in are open ground on the walking grid
	var shut: Array = []
	var r: float = float(sb.cfg.get("bulb", 8.5)) - 0.6
	var pts: Array = [sb.centre]
	for k in 12:
		pts.append(sb.centre + Vector3(cos(TAU * k / 12.0), 0, sin(TAU * k / 12.0)) * r)
	var rt: Array = sb.cfg.get("road_to", [86.5, 0.7])
	var end := Vector3(float(rt[0]), 0, float(rt[1]))
	for k in 6:
		pts.append(sb.centre.lerp(end, (k + 1) / 7.0))
	for p in pts:
		if not main._walkable(main._cell(p)):
			shut.append("%.1f,%.1f" % [p.x, p.z])
	main._check("the turning circle and the road in are open to walk on (%d blocked%s)" % [shut.size(), (": " + ", ".join(shut)) if shut.size() > 0 else ""], shut.is_empty())
	# every door can be walked to from the town square
	var reach := 0
	var from := Vector3(53.0, 0.0, -1.0)
	var cut: Array = []
	for h in sb.houses():
		var path: Array = main._find_path(from, h["door"])
		if not path.is_empty() and (path[-1] as Vector3).distance_to(h["door"]) < 1.0:
			reach += 1
		else:
			var d: Vector3 = h["door"]
			cut.append("house %d door %.1f,%.1f (%s)" % [h["i"], d.x, d.z, "open cell, no way to it" if main._walkable(main._cell(d)) else "its cell is blocked"])
	main._check("every front door can be walked to from the square (%d of 6%s)" % [reach, (": not " + "; ".join(cut)) if cut.size() > 0 else ""], reach == 6)
	# the API: who sleeps where
	main._check("home_for gives each named villager their house and anyone else the same one every time",
		sb.home_for("wren") == 0 and sb.home_for("rosa") == 2 and sb.home_for("someone_new") == sb.home_for("someone_new")
		and sb.home_for("someone_new") >= 0 and sb.door_for("rowan").distance_to(sb.houses()[3]["door"]) < 0.01)
	await _night(sb)
	await _pictures(sb)


## A resident (Wren, if she's free) goes home at night_from, is put to bed when she reaches her door, and comes out at night_to.
func _night(sb) -> void:
	var v = null
	var who := ""
	for id in sb.cfg.get("residents", {}):
		var c = main._villager(str(id))
		if c != null and sb._free_to_go(str(id), c):
			v = c
			who = str(id)
			break
	if v == null:
		main._check("someone who lives in Bretton Oaks is free to go home", false)
		return
	print("SUBURB night check with ", who)
	var on0: bool = sb.on
	sb.on = true
	var home0: Vector3 = v.home
	var spot0: Vector3 = v.position
	var hour0: float = Game.hour
	Game.hour = 21.5
	main._check("bedtime at half past nine, not at noon", sb.bedtime() and not sb.bedtime(12.0))
	sb.update()
	var walking: bool = sb.sleepers.has(who) and str(sb.sleepers[who]["state"]) == "walking"
	var door: Vector3 = sb.door_for(who)
	main._check("at night %s sets off" % who + " for their front door", walking and v.home.distance_to(door) < 0.01)
	v.position = door + Vector3(0.1, 0, 0.1) # most of the walk, skipped
	sb.update()
	main._check("at the door they go in: hidden, her click box off", sb.asleep(who) and not v.visible and v.process_mode == Node.PROCESS_MODE_DISABLED)
	Game.hour = 6.2
	sb.update()
	main._check("at six they come out of the door and heads back", v.visible and str(sb.sleepers[who]["state"]) == "returning" and v.position.distance_to(door) < 0.5)
	v.position = home0
	sb.update()
	main._check("back at their spot they're themselves again (home, roam, route kept)", not sb.sleepers.has(who) and v.home.distance_to(home0) < 0.01)
	# a scene starting wakes everyone at once
	Game.hour = 22.0
	sb.update()
	if sb.sleepers.has(who):
		sb._hide(v, sb.sleepers[who])
	sb.wake_all()
	main._check("a story scene starting brings everyone straight back to their spot", v.visible and sb.sleepers.is_empty() and v.position.distance_to(home0) < 0.01)
	v.position = spot0
	Game.hour = hour0
	sb.on = on0


func _pictures(sb) -> void:
	main._set_cam_lock(false)
	var yaw0: float = main.cam_yaw
	var pitch0: float = main.cam_pitch
	var dist0: float = main.cam_dist
	var hour0: float = Game.hour
	var target0: Vector3 = main.cam_target
	var nora0: Vector3 = main.player.position
	var dog0: Vector3 = main.dog.position if main.dog else Vector3.ZERO
	var h0: Dictionary = sb.houses()[0]
	var n := h0["node"] as Node3D
	main.player.position = n.global_transform * Vector3(0, 0, -7.0) # behind the house, out of the pictures
	# the house close up, from the street like Alex's photo, beside it
	Game.hour = 11.0
	sb.update_lights(true)
	main.cam_target = n.global_transform * Vector3(0.0, 1.8, 0.0)
	main.cam_dist = 24.0
	main.cam_pitch = 14.0
	main.cam_glide = {"pos": main.cam_target, "dist": 24.0, "pitch": 14.0} # held there: the pitch eases back otherwise
	main.cam_yaw = n.global_rotation.y + deg_to_rad(8.0)
	main.cam_yaw_goal = main.cam_yaw
	await main._wait(2.5)
	await main._shot("66_suburb_house_game.png")
	_beside_ref("66_suburb_house_game.png", "66_suburb_house.png")
	# every house from the street, the same way, at Ultra and High: Marcus's (the walk-in one) must
	# look like its neighbours from outside, its cream upper wing and gable lit, not a black hollow
	# (Alex, 2026-11-20: "walls black on one of the houses, ultra settings high graphics")
	var gfx0: int = main.gfx
	for g in [main.GFX_ULTRA, main.GFX_HIGH]:
		main.gfx = g
		main.apply_graphics()
		var lums: Array = []
		for h in sb.house_list:
			var hn := h["node"] as Node3D
			var holder := (h["model"] as Node3D).get_parent() as Node3D
			main.cam_target = hn.global_transform * Vector3(0.0, 2.6, 0.0)
			main.cam_glide = {"pos": main.cam_target, "dist": 22.0, "pitch": 12.0}
			main.cam_dist = 22.0
			main.cam_pitch = 12.0
			main.cam_yaw = hn.global_rotation.y
			main.cam_yaw_goal = main.cam_yaw
			await main._wait(1.5)
			var img := main.get_viewport().get_texture().get_image()
			var cam := main.get_viewport().get_camera_3d()
			# the upper wing's front gable (cream siding) and its wall under the eave
			var lum := 0.0
			for p in [Vector3(2.55, 4.6, 4.36), Vector3(1.0, 4.15, 4.36), Vector3(4.1, 4.15, 4.36)]:
				var sp := cam.unproject_position(holder.global_transform * p)
				lum += _patch_lum(img, Vector2i(sp))
			await main._shot("66_street_%s_%d.png" % ["ultra" if g == main.GFX_ULTRA else "high", int(h["i"])])
			# close up and low, Nora on the lawn by the garage's front corner (within the walk-in
			# house's 24 m, as Alex was), the garage's gable and its cream strip over the window
			var mx := -1.0 if bool(h["mirror"]) else 1.0
			main.player.position = hn.global_transform * Vector3(8.5 * mx, 0, 12.5)
			main.cam_target = hn.global_transform * Vector3(2.55 * mx, 2.6, 9.0)
			main.cam_glide = {"pos": main.cam_target, "dist": 9.0, "pitch": 6.0}
			main.cam_dist = 9.0
			main.cam_pitch = 6.0
			main.cam_yaw = hn.global_rotation.y + deg_to_rad(35.0) * mx
			main.cam_yaw_goal = main.cam_yaw
			await main._wait(1.5)
			img = main.get_viewport().get_texture().get_image()
			cam = main.get_viewport().get_camera_3d()
			for p in [Vector3(2.55, 2.9, 10.03), Vector3(2.55, 1.5, 10.03), Vector3(2.55, 4.6, 4.36)]:
				var sp := cam.unproject_position(holder.global_transform * p)
				lum += _patch_lum(img, Vector2i(sp))
			lums.append(lum / 6.0)
			await main._shot("66_close_%s_%d.png" % ["ultra" if g == main.GFX_ULTRA else "high", int(h["i"])])
			# and from her eyes there, as Alex saw it
			if g == main.GFX_ULTRA and main.fps != null:
				var look: Vector3 = hn.global_transform * Vector3(2.55 * mx, 0, 9.5) - main.player.position
				main.player.rotation.y = atan2(look.x, look.z)
				main.fps.enter()
				await main._wait(1.0)
				await main._shot("66_fps_%d.png" % int(h["i"]))
				main.fps.leave()
			main.player.position = n.global_transform * Vector3(0, 0, -7.0)
		var others: Array = []
		var walk := -1
		for k in sb.house_list.size():
			if sb.house_list[k].has("walk_in") or (sb.house_list[k]["node"] as Node3D).has_meta("walk_in") \
					or (sb.house_list[k]["model"] as Node3D).get_parent().get_parent().has_meta("walk_in"):
				walk = k
			else:
				others.append(lums[k])
		others.sort()
		var med: float = others[int(others.size() / 2.0)] if not others.is_empty() else 0.0
		print("SUBURB street cream lum %s: %s (walk-in %d)" % ["ultra" if g == main.GFX_ULTRA else "high", str(lums), walk])
		var ok := med > 0.15
		if walk >= 0:
			ok = ok and float(lums[walk]) > med * 0.75
		main._check("From the street Marcus's house's cream upper wing is lit like its neighbours' at %s" % ("Ultra" if g == main.GFX_ULTRA else "High"), ok)
	main.gfx = gfx0
	main.apply_graphics()
	# the cul-de-sac from above
	Game.hour = 13.0
	main.cam_target = sb.centre
	main.cam_dist = 70.0
	main.cam_pitch = 62.0
	main.cam_glide = {"pos": sb.centre, "dist": 70.0, "pitch": 62.0}
	main.cam_yaw = deg_to_rad(20.0)
	main.cam_yaw_goal = main.cam_yaw
	await main._wait(2.5)
	await main._shot("66_suburb_above.png")
	# at night, the windows and the porch lights on
	Game.hour = 21.0
	sb.update_lights(true)
	var lit := 0
	for h in sb.house_list:
		if (h["light"] as OmniLight3D).visible and not (h["panes"] as Array).is_empty():
			var p: Array = h["panes"][0]
			if (p[0] as MeshInstance3D).get_surface_override_material(int(p[1])) != null:
				lit += 1
	main._check("after dark every house's windows and porch light are on (%d of 6)" % lit, lit == 6)
	main.cam_target = sb.centre
	main.cam_dist = 34.0
	main.cam_pitch = 30.0
	main.cam_glide = {"pos": sb.centre, "dist": 34.0, "pitch": 30.0}
	main.cam_yaw = deg_to_rad(200.0)
	main.cam_yaw_goal = main.cam_yaw
	await main._wait(2.5)
	await main._shot("66_suburb_night.png")
	Game.hour = 12.0
	sb.update_lights(true)
	var off := 0
	for h in sb.house_list:
		if not (h["light"] as OmniLight3D).visible:
			off += 1
	main._check("by day the lights are off (%d of 6)" % off, off == 6)
	Game.hour = hour0
	sb.update_lights(true)
	main.cam_yaw = yaw0
	main.cam_yaw_goal = yaw0
	main.cam_pitch = pitch0
	main.cam_dist = dist0
	main.cam_glide = {}
	main.cam_target = target0
	main.player.position = nora0
	if main.dog:
		main.dog.position = dog0 # he followed her out to the houses: back beside her (the dog checks come next)
	main._set_cam_lock(true)


## The game's picture with Alex's photo beside it, at the same height.
func _beside_ref(game_png: String, out_png: String) -> void:
	var dir: String = main._autotest_dir
	var shot := Image.load_from_file(dir.path_join(game_png))
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REF))
	if shot == null or ref == null:
		return
	ref.convert(shot.get_format())
	var h := shot.get_height()
	ref.resize(int(ref.get_width() * float(h) / ref.get_height()), h, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(ref.get_width() + shot.get_width(), h, false, shot.get_format())
	out.blit_rect(ref, Rect2i(Vector2i.ZERO, ref.get_size()), Vector2i.ZERO)
	out.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(ref.get_width(), 0))
	out.resize(out.get_width() / 2, out.get_height() / 2, Image.INTERPOLATE_LANCZOS) # kept small
	out.save_png(dir.path_join(out_png))
	DirAccess.remove_absolute(dir.path_join(game_png))
	print("SHOT ", out_png)


## The mean brightness of a 9 x 9 patch of `img` round `c` (0 off the picture).
static func _patch_lum(img: Image, c: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var col := img.get_pixel(x, y)
			s += col.r * 0.3 + col.g * 0.59 + col.b * 0.11
			n += 1
	return s / n if n > 0 else 0.0
