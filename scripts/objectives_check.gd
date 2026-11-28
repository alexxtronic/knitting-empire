extends RefCounted
## --only=objectives: the Objectives tab and the blue way to the one she tracks (objectives.gd; Alex,
## 2026-11-28). The tab by the Menu button, O opening the panel with its main objectives and side
## quests and Esc shutting it; in Act 1 the story's goal line as the main objective pointing at the
## person it names (Steve, not the spot in the data) and the chair for a knit; a click tracking the
## main slot, the blue route on the ground from her along the walking grid with the blue badge over
## the target, the gold marker stepping aside, the minimap drawing both; the slot following the next
## step by itself; the route worked out again when she's moved; none in the cinematic camera; a click
## again stopping it and the gold marker back. After Act 1: the Next line and the act's Empire goals,
## each pointing somewhere (the pen goal at the farm), a local's request as a side quest pointing at
## them, a tracked side quest dropped once it's done. Saves 83_objectives_panel.png,
## 83_objectives_route.png, 83_objectives_badge.png, 83_objectives_close.png and 83_objectives_side.png. Leaves the game as
## it found it.

const Objectives = preload("res://scripts/objectives.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")
const FogOfWar = preload("res://scripts/fog_of_war.gd")


func run(m: Node) -> void:
	var keep := {"flags": Game.flags.duplicate(true), "on": Objectives.on, "goals_on": EmpireGoals.on, "clock": Game.time_running,
		"pos": m.player.position}
	Game.time_running = false
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	Objectives.on = true
	var ob = m.objectives
	ob.untrack()
	# --- the tab
	await m._wait(0.6)
	m._check("the Objectives tab is up beside the Menu button (\"%s\")" % ob.btn.text,
		ob.btn.visible and ob.btn.get_global_rect().position.x > m.hud.menu_btn.get_global_rect().end.x - 1.0 and absf(ob.btn.get_global_rect().position.y - m.hud.menu_btn.get_global_rect().position.y) < 4.0)
	# --- Act 1: the story's goal line
	Game.flags["story_farm"] = true
	Game.flags.erase("act1_done")
	m.set_goal("Buy turnip seeds from Steve at Builder's Delight", Vector2(47.7, -9.4))
	await m._key_tap(KEY_O)
	await m._wait(0.7)
	var steve = m._villager("steve")
	var first: Dictionary = ob.items[0] if not ob.items.is_empty() else {}
	m._check("O opens the panel, with main objectives and side quests (%d rows)" % ob.items.size(), ob.is_open() and _has_label(ob._list, "MAIN OBJECTIVES") and _has_label(ob._list, "SIDE QUESTS"))
	m._check("in Act 1 the story's goal line is the main objective, pointing at Steve himself (%s)" % str(first.get("text", "")),
		str(first.get("id", "")) == "story" and first.get("target") == steve and steve != null)
	await m._wait(0.3)
	m._check("the panel shows its rows (%.0f px tall)" % ob._scroll.size.y, ob._scroll.size.y > 30.0)
	await m._shot("83_objectives_panel.png")
	ob.pick("story")
	await m._wait(0.8)
	m._check("a click tracks the main slot", ob.tracked_id() == "main" and str(ob.tracked().get("id", "")) == "story")
	var at_steve: bool = ob.goal != null and Objectives._flat(ob.goal, steve.global_position) < 0.5
	m._check("the blue route lies on the ground from her to him (%d points, %.1f ms to work out) with the badge over him, and the gold marker steps aside" % [ob.route.size(), ob.path_us / 1000.0],
		ob.shown and not ob.route.is_empty() and ob._line.visible and ob.marker.visible and at_steve and not m.goal_marker.visible)
	var ends: bool = not ob.drawn.is_empty() and Objectives._flat(ob.drawn[0], m.player.position) < 1.0 and Objectives._flat(ob.drawn[ob.drawn.size() - 1], steve.global_position) < 5.0
	m._check("the ribbon starts at her feet and ends at him", ends)
	m._check("the ribbon and the badge are on the fog's layer, left out by the minimap's camera", ob._line.layers == FogOfWar.LAYER and (ob._icon.layers & FogOfWar.LAYER) != 0)
	ob.close()
	m.cam_glide = {"pos": m.player.position.lerp(steve.global_position, 0.3), "dist": 26.0, "pitch": 55.0}
	await m._wait(1.6)
	await m._shot("83_objectives_route.png")
	m.cam_glide = {"pos": steve.global_position, "dist": 14.0, "pitch": 40.0}
	await m._wait(1.6)
	await m._shot("83_objectives_badge.png")
	m.cam_glide = {"pos": m.player.position, "dist": 9.0, "pitch": 45.0}
	await m._wait(1.4)
	await m._shot("83_objectives_close.png")
	# the slot follows the next step
	m.set_goal("Knit your first sweater in Gran's rocking chair", Vector2(2.4, 3.6))
	await m._wait(0.8)
	var chair = ob._chair()
	m._check("the next step is tracked by itself: the rocking chair (%s)" % str(ob.tracked().get("text", "")),
		chair != null and ob.tracked().get("target") == chair and ob.goal != null and Objectives._flat(ob.goal, chair.global_position) < 0.5)
	# she moves: the route is worked out again from where she is
	var from0: Vector3 = ob._route_from
	m.player.position += Vector3(5.0, 0, 4.0)
	m.player.walk([])
	await m._wait(0.8)
	m._check("walked off it, the route starts again from her (%.1f m from where she stands)" % Objectives._flat(ob._route_from, m.player.position),
		Objectives._flat(ob._route_from, m.player.position) < 1.5 and Objectives._flat(from0, ob._route_from) > 3.0)
	m.cinema.enter()
	await m._wait(0.4)
	var hid: bool = not ob.shown and not ob._line.visible and not ob.marker.visible
	m.cinema.leave()
	await m._wait(0.5)
	m._check("none of it in the cinematic camera, back after", hid and ob.shown)
	ob.pick(str(ob.tracked().get("id", "")))
	await m._wait(0.5)
	m._check("a click again stops it, and the gold marker is back", ob.tracked_id() == "" and not ob.shown and not ob.marker.visible and m.goal_marker.visible)
	await m._key_tap(KEY_O)
	await m._wait(0.3)
	var opened: bool = ob.is_open()
	await m._key_tap(KEY_ESCAPE)
	await m._wait(0.3)
	m._check("Esc shuts the panel", opened and not ob.is_open() and not m.hud.game_menu.visible)
	# --- after Act 1
	m.set_goal("")
	Game.flags["act1_done"] = true
	EmpireGoals.on = true
	await m._wait(0.7)
	var ids: Array = ob.items.map(func(o): return str(o["id"]))
	var goal_ids := ids.filter(func(i): return str(i).begins_with("goal:"))
	m._check("after Act 1 the act's Empire goals are main objectives (%s)" % str(ids), goal_ids.size() >= 1 and not ids.has("story"))
	var pointed := 0
	for o in ob.items:
		if str(o["kind"]) == "main" and Objectives.point_of(o["target"]) != null:
			pointed += 1
	m._check("and %d of the %d main ones point somewhere" % [pointed, ob.items.filter(func(o): return str(o["kind"]) == "main").size()], pointed >= 1)
	var pen_goal := {"id": "pen2", "line": "Build a second pen", "check": "pens", "n": 2}
	var pp: Variant = ob.goal_target(pen_goal)
	m._check("a pen goal points at the farm (%s)" % str(pp), pp is Vector3 and Objectives._flat(pp, Vector3(10, 0, -4)) < 40.0)
	# how long a long route takes: the farm to the far dunes
	var t0 := Time.get_ticks_usec()
	var far: Array = m._find_path(Vector3(10, 0, 0), Vector3(230, 0, 20))
	print("OBJECTIVES ROUTE farm to dunes: %d points in %.1f ms" % [far.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	# a local's request as a side quest
	var who := "barbara"
	var v = m._villager(who)
	Game.flags["request"] = {"id": "check_req", "who": who, "pay": 120, "made": 0, "design": "", "rarity": 1}
	Game.add_sweater(1, "")
	await m._wait(0.7)
	var req: Dictionary = ob._item("request")
	m._check("a request is a side quest pointing at %s (%s)" % [who, str(req.get("text", ""))], str(req.get("kind", "")) == "side" and req.get("target") == v and "Barbara" in str(req.get("text", "")))
	ob.pick("request")
	ob.open()
	m.cam_glide = {"pos": m.player.position.lerp(v.global_position, 0.5), "dist": 34.0, "pitch": 60.0}
	await m._wait(1.6)
	m._check("tracked, the way goes to her", ob.shown and ob.goal != null and v != null and Objectives._flat(ob.goal, v.global_position) < 0.5)
	await m._shot("83_objectives_side.png")
	ob.close()
	Game.flags.erase("request")
	await m._wait(0.7)
	m._check("once it's done it's no longer tracked", ob.tracked_id() == "" and not ob.shown)
	# leave it as it was
	Game.remove_sweater(Game.sweaters.size() - 1)
	Game.flags = keep["flags"]
	Objectives.on = keep["on"]
	EmpireGoals.on = keep["goals_on"]
	Game.time_running = keep["clock"]
	m.player.position = keep["pos"]
	m._show_goal()
	ob.untrack()


static func _has_label(root: Node, text: String) -> bool:
	for c in root.get_children():
		if c is Label and (c as Label).text == text:
			return true
	return false
