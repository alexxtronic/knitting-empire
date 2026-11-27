extends RefCounted
## --only=houselook: pictures of Marcus's house from her eyes, room by room (not a check): the
## ceilings and the two flights of stairs. Saves 81_house_<name>.png.

var main: Node
var wi


## Stands her at `at` (the house's own space; y the floor's height) looking along `yaw_deg` (0 is +z,
## toward the street; 90 is +x) and `pitch_deg` up, and takes the picture.
func _eyes(at: Vector3, yaw_deg: float, pitch_deg: float, fname: String) -> void:
	main.player.position = wi.house.global_transform * at
	main.player.path = []
	await main._wait(0.4)
	if not main.fps.active:
		main.fps.enter()
	var dir: Vector3 = wi.house.global_transform.basis * Vector3(sin(deg_to_rad(yaw_deg)), 0, cos(deg_to_rad(yaw_deg)))
	main.fps.yaw = atan2(-dir.x, -dir.z)
	main.fps.pitch = deg_to_rad(pitch_deg)
	await main._wait(1.0)
	print("HOUSELOOK %s level %d local %s eye y %.2f fov %.0f" % [fname, wi.level, wi.local(main.player.position), wi.local(main.cam.global_position).y, main.cam.fov])
	await main._shot(fname)


func run(m: Node) -> void:
	main = m
	wi = main.suburb.walk_in
	Game.time_running = false
	Game.hour = 14.0
	main.hud.tip_panel.visible = false
	var uy: float = wi.upper_y
	var by: float = wi.basement_y
	await _eyes(Vector3(-2.2, 0, 1.6), -90, 10, "81_house_01_living_west.png")
	await _eyes(Vector3(-2.2, 0, 0.6), 90, 10, "81_house_02_living_east.png")
	await _eyes(Vector3(-3.0, 0, -2.8), -90, 10, "81_house_03_dining.png")
	await _eyes(Vector3(-5.0, 0, 1.6), 180, 12, "81_house_04_kitchen.png")
	await _eyes(Vector3(-2.2, 0, 0.6), 0, 40, "81_house_05_main_ceiling.png")
	await _eyes(Vector3(-0.4, 0, 1.3), 90, 5, "81_house_06_up_from_foot.png")
	await _eyes(Vector3(-0.2, 0, 2.7), 90, -28, "81_house_07_down_from_top.png")
	await _eyes(Vector3(1.0, -0.75, 2.7), 90, -30, "81_house_08_down_on.png")
	await _eyes(Vector3(1.9, by + 0.3, 2.7), 90, 0, "81_house_09_down_low.png") # halfway: the basement takes over
	await _eyes(Vector3(3.2, by, 2.7), -90, 18, "81_house_10_down_from_foot.png")
	await _eyes(Vector3(4.6, by, 1.0), -90, 8, "81_house_11_den.png")
	await _eyes(Vector3(4.6, by, 1.0), 0, 30, "81_house_12_den_ceiling.png")
	await _eyes(Vector3(3.5, by, -1.6), 180, 8, "81_house_13_rec.png")
	main.player.position = wi.house.global_transform * Vector3(1.0, -0.75, 2.7) # back up the flight
	await main._wait(0.3)
	await _eyes(Vector3(-0.2, 0, 2.7), 90, 0, "81_house_14_back_up.png")
	main.player.position = wi.house.global_transform * Vector3(-0.4, 0, 1.3) # the foot of the half flight
	await main._wait(0.3)
	await _eyes(Vector3(2.6, uy, 0.4), 0, 10, "81_house_15_upper_hall.png")
	await _eyes(Vector3(4.8, uy, 1.6), 0, 12, "81_house_16_master.png")
	await _eyes(Vector3(4.8, uy, -2.4), 180, 12, "81_house_17_kids.png")
	await _eyes(Vector3(4.8, uy, 1.6), 90, 40, "81_house_18_upper_ceiling.png")
	main.fps.leave()
