extends RefCounted
## The frame-rate check (--only=perf): stands Nora at fixed spots (her farm by day and night, the
## town square by day and night, inside the Cappuccino Cafe by day and night, the swamp at dawn in
## the mist, the woods by day and in the morning mist), with the world as a player has it (the wild
## animals out, the town on its rounds, vsync off), and prints for each graphics level the median
## frame time, the slowest frames (95th percentile), the render thread's CPU time, and the draw
## calls, primitives and objects drawn. It saves a picture of each spot at the computer's default
## level, 63_perf_<spot>.png, and checks the default level's slowest frames hold 30 fps.
##
## Timing on a laptop swings with whatever else it's doing: each sample runs SAMPLE_SECS, counts the
## frames actually drawn (macOS skips drawing a covered window, and then frames cost nothing: a
## sample with frames missing is marked "covered" and not counted), and a calibration row (Low at
## the farm) at the start and the end shows how loaded the machine was. Compare runs only when the
## calibration rows agree.
##
## Options after --only=perf: --perflevels=low,medium,high (default: all three),
## --perfspots=farm_day,town_night,... (default: all), and --perfprobe, which at each spot times
## each effect and each of the frame-rate pass's changes by switching it off and on again in turn
## (back to back, so the machine's load hits both halves alike); --perftoggles=a,b keeps only those.
## Every line starts with PERF.

const Interiors = preload("res://scripts/interiors.gd")
const Lighting = preload("res://scripts/lighting.gd")
const Catalog = preload("res://scripts/catalog.gd")

const SAMPLE_SECS := 2.5
const SETTLE := 2.5 # seconds at a spot before measuring (streaming, shaders, the camera gliding in)

var main: Node
var vp_rid: RID


## [name, where she stands, hour]
func spots() -> Array:
	var cafe := Vector3.ZERO
	var s = Interiors.shops.get("cafe")
	if s != null:
		var xf: Transform3D = s.node.global_transform
		cafe = xf * Vector3(-0.6, 0.0, -1.0)
		cafe.y = 0.0
	return [
		["farm_day", Vector3(6.0, 0.0, 5.0), 11.0],
		["farm_night", Vector3(6.0, 0.0, 5.0), 22.5],
		["town_day", Vector3(53.0, 0.0, -1.0), 13.0],
		["town_night", Vector3(53.0, 0.0, -1.0), 21.5],
		["cafe_day", cafe, 15.0],
		["cafe_night", cafe, 20.5],
		["swamp_dawn", Vector3(-58.0, 0.0, -6.0), 6.4],
		["woods_day", Lighting.SHOT_TARGET, 12.0],
		["woods_mist", Lighting.SHOT_TARGET, 6.6],
	]


func run(m: Node) -> void:
	main = m
	vp_rid = main.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# the world as a player has it: the animals out, the town on its rounds, the real clock (stopped)
	if main.wildlife.get_child_count() == 0:
		main.wildlife.build()
	main.town_rounds = true
	Game.fast_clock = false
	Game.time_running = false
	main.hud.visible = true
	var levels: Array = [0, 1, 2]
	var probe := false
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perflevels="):
			levels = []
			for w in a.substr(13).split(","):
				var i: int = ["low", "medium", "high"].find(w.strip_edges().to_lower())
				if i >= 0:
					levels.append(i)
		if a == "--perfprobe":
			probe = true
		if a.begins_with("--perfspots="):
			only = a.substr(12).split(",")
	var start_gfx: int = main.gfx
	var d: int = main.default_graphics()
	print("PERF window %s, screen %s, %s, default level %s, 3D at %d%% (%s)" % [main.get_window().size, DisplayServer.screen_get_size(), RenderingServer.get_video_adapter_name(), main.GFX_NAMES[d], roundi(main.get_viewport().scaling_3d_scale * 100.0), ["bilinear", "FSR", "FSR2", "MetalFX spatial", "MetalFX temporal"][main.get_viewport().scaling_3d_mode]])
	await _calibrate("start")
	print("PERF %-11s %-6s %7s %6s %7s %6s %7s %7s %6s %s" % ["spot", "level", "med ms", "fps", "p95 ms", "cpu ms", "draws", "prims k", "objs", "frames"])
	var worst := {}
	for spot in spots():
		if not only.is_empty() and not (str(spot[0]) in only):
			continue
		_stand(spot)
		for lv in levels:
			_set_level(lv)
			await main._wait(1.2 if lv != levels[0] else SETTLE)
			var r := await measure()
			print("PERF %-11s %-6s %7.2f %6.1f %7.2f %6.2f %7d %7d %6d %d%s" % [spot[0], main.GFX_NAMES[lv], r.med, 1000.0 / r.med, r.p95, r.cpu, r.draws, r.prims / 1000, r.objs, r.frames, "" if r.ok else " covered"])
			if r.ok:
				worst[lv] = maxf(float(worst.get(lv, 0.0)), r.p95)
			if lv == d:
				await main._shot("63_perf_%s.png" % spot[0])
		if probe:
			_set_level(levels[-1])
			await main._wait(1.0)
			await _probe(spot)
	await _calibrate("end")
	for lv in levels:
		if worst.has(lv):
			print("PERF worst p95 on %s: %.2f ms (%.0f fps)" % [main.GFX_NAMES[lv], worst[lv], 1000.0 / worst[lv]])
	if worst.has(d):
		main._check("the default graphics level (%s) holds 30 fps or more at every spot: slowest frames %.1f ms" % [main.GFX_NAMES[d], worst[d]], worst[d] <= 1000.0 / 30.0)
	_set_level(start_gfx)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _set_level(lv: int) -> void:
	main.gfx = lv
	main.apply_graphics()


## Low graphics at the farm by day, and how busy the machine is: compare runs only when these agree.
func _calibrate(when: String) -> void:
	_stand(spots()[0])
	var keep: int = main.gfx
	_set_level(0)
	await main._wait(SETTLE)
	var r := await measure()
	var load := ""
	var out := []
	OS.execute("sysctl", ["-n", "vm.loadavg"], out)
	if not out.is_empty():
		load = str(out[0]).strip_edges()
	var others := []
	OS.execute("pgrep", ["-f", "Godot.app/Contents/MacOS/Godot"], others)
	var n_godot := str(others[0]).strip_edges().split("\n").size() if not others.is_empty() and str(others[0]).strip_edges() != "" else 0
	print("PERF calibration %s: Low at the farm %.2f ms median, %.2f p95%s; load average %s; Godot processes running: %d" % [when, r.med, r.p95, "" if r.ok else " (covered)", load, n_godot])
	_set_level(keep)


func _stand(spot: Array) -> void:
	var p: Vector3 = spot[1]
	main.player.walk([])
	main.player.position = p
	main._set_cam_lock(true)
	main.cam_target = p
	main.cam_dist = 23.0
	Game.hour = float(spot[2])
	main.rain = 0.0


## Frame times over SAMPLE_SECS: median and 95th percentile, the render thread's CPU time for the
## main viewport (Metal reports no GPU time), the render monitors averaged, and whether every frame
## was drawn (`ok`).
func measure(secs := SAMPLE_SECS) -> Dictionary:
	var drawn := [0]
	var count := func() -> void: drawn[0] += 1
	await main.get_tree().process_frame
	RenderingServer.frame_post_draw.connect(count)
	var times := PackedFloat64Array()
	var cpu := 0.0
	var draws := 0.0
	var prims := 0.0
	var objs := 0.0
	var t0 := Time.get_ticks_usec()
	var t_prev := t0
	while Time.get_ticks_usec() - t0 < int(secs * 1e6) or times.size() < 10:
		await main.get_tree().process_frame
		var t := Time.get_ticks_usec()
		times.append((t - t_prev) / 1000.0)
		t_prev = t
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	RenderingServer.frame_post_draw.disconnect(count)
	var sorted := times.duplicate()
	sorted.sort()
	var n := float(times.size())
	return {
		"med": sorted[int(n * 0.5)], "p95": sorted[mini(int(n * 0.95), times.size() - 1)], "cpu": cpu / n,
		"draws": int(draws / n), "prims": int(prims / n), "objs": int(objs / n),
		"frames": times.size(), "ok": drawn[0] >= times.size() - 2,
	}


## Each effect, and each of the frame-rate pass's changes, switched off on its own at this spot:
## what it costs, measured back to back with it on.
func _probe(spot: Array) -> void:
	var env: Environment = main.env
	var lamps: Array = main.find_children("*", "OmniLight3D", true, false)
	var vp: Viewport = main.get_viewport()
	var toggles := {
		# the frame-rate pass of 2026-11-16: "off" is the game as it was before it
		"light_budget": func(on: bool) -> void:
			main.light_budget.enabled = on
			main.light_budget.update(main.get_tree(), main.cam_target, 0.0, true),
		# the effects themselves
		"sdfgi": func(on: bool) -> void: env.sdfgi_enabled = on,
		"vol_fog": func(on: bool) -> void: env.volumetric_fog_enabled = on,
		"ssao": func(on: bool) -> void: env.ssao_enabled = on,
		"ssil": func(on: bool) -> void: env.ssil_enabled = on,
		"ssr": func(on: bool) -> void: env.ssr_enabled = on,
		"glow": func(on: bool) -> void: env.glow_enabled = on,
		"sun_shadow": func(on: bool) -> void: main.sun.shadow_enabled = on,
		"sun_soft_q4v3": func(on: bool) -> void: RenderingServer.directional_soft_shadow_filter_set_quality(4 if on else 3),
		"lamp_lights": func(on: bool) -> void:
			for l in lamps:
				if is_instance_valid(l):
					(l as Light3D).visible = on,
		"grass": func(on: bool) -> void: main.grass.visible = on,
		"nature": func(on: bool) -> void: main.nature.visible = on,
		"wildlife": func(on: bool) -> void: main.wildlife.visible = on,
		"villagers": func(on: bool) -> void:
			for v in main.villagers:
				v.visible = on,
		"hud": func(on: bool) -> void: main.hud.visible = on,
		"scripts": func(on: bool) -> void: main.get_tree().paused = not on,
		"sun_penumbra": func(on: bool) -> void: main.sun.light_angular_distance = 0.55 if on else 0.0,
		"sun_blend_splits": func(on: bool) -> void: main.sun.directional_shadow_blend_splits = on,
		"sun_4_splits": func(on: bool) -> void:
			main.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if on else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"lamp_shadows_4v2": func(on: bool) -> void:
			main.light_budget.max_shadows = 4 if on else 2
			main.light_budget.update(main.get_tree(), main.cam_target, 0.0, true),
		"plain_lights": func(on: bool) -> void:
			for l in lamps:
				if is_instance_valid(l) and not (l as Light3D).shadow_enabled:
					(l as Light3D).visible = on,
		"3d_res_x0.7": func(on: bool) -> void:
			main.render_scale = 1.0 if on else 0.7
			main._fit_3d_resolution(),
	}
	var casting: int = main.light_budget.casting(main.get_tree())
	print("PERF probe %-11s %d omni lights, %d casting shadows" % [spot[0], lamps.size(), casting])
	var pick: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perftoggles="):
			pick = a.substr(14).split(",")
	for k in toggles:
		if not pick.is_empty() and not (str(k) in pick):
			continue
		var with := await measure()
		toggles[k].call(false)
		await main._wait(0.6)
		var off := await measure()
		toggles[k].call(true)
		await main._wait(0.5)
		print("PERF probe %-11s without %-16s %6.2f ms, with %6.2f (saves %6.2f); draws %d / %d, prims %dk / %dk%s" % [spot[0], k, off.med, with.med, with.med - off.med, off.draws, with.draws, off.prims / 1000, with.prims / 1000, "" if off.ok and with.ok else " (covered: ignore)"])
	main.apply_graphics()
