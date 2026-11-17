extends RefCounted
## The world editor's house tools (Alex, 2026-11-17: "a God mode where I can totally edit the house's
## walls, place windows, doors, and a sliding door ... so good that I can make the interior exactly in
## my image"), for Marcus's house in Bretton Oaks (split_house.gd). They change its walls and floors in
## the house's own space and rebuild them at once; god_mode.gd keeps the result in the layout file
## ("split_house": the whole walls and rooms lists, which replace data/split_house.json's).
##
##   Wall      drag on a floor to draw a wall (square to the house, snapped to 10 cm). Click a wall
##             to pick it (it turns gold) and drag to slide it; Delete removes it.
##   Door, Sliding door, Window, Opening
##             click a wall to put one there (a door 0.85 m, sliding doors 1.8 m, a window 1.2 m, a
##             plain opening 1 m wide); click one again with the same tool to take it out. Doors
##             swing and sliding doors slide as she comes up to them; windows still block the way.
##   Floor     drag a rectangle to lay the floor chosen in the list over what's there; click a floor
##             laid this way to take it up.
## The floors shown are the ones being edited: the main floor and the bedroom floor from above, the
## basement when she's down there as the editor opens. Every change can be undone.

const SNAP := 0.1
const WIDTHS := {"open": 1.0, "door": 0.85, "slide": 1.8, "window": 1.2} # the width each kind of opening starts at
const FLOORS := [["carpet_grey", "Grey carpet"], ["carpet_blue", "Blue carpet"], ["carpet_cream", "Cream carpet"], ["shag_green", "Green shag"],
	["tile_beige", "Beige tile"], ["tile_black", "Black tile"], ["tile_white", "White tile"], ["cement", "Cement"], ["wood_oak", "Oak boards"]]
const TOOLS := [["h_wall", "Wall"], ["h_door", "Door"], ["h_slide", "Sliding door"], ["h_window", "Window"], ["h_open", "Opening"], ["h_floor", "Floor"]]

var god # god_mode.gd
var main
var floor_kind := "carpet_grey"
var _drag := {}


func _init(g) -> void:
	god = g
	main = g.main


func house():
	if main.suburb == null:
		return null
	return main.suburb.walk_in


func hint(tool: String) -> String:
	match tool:
		"h_wall":
			return "House walls: drag on a floor to draw one. Click a wall to pick it, drag to slide it, Delete removes it."
		"h_door", "h_slide", "h_window", "h_open":
			return "Click a wall to put a %s in it; click it again to take it out." % {"h_door": "door", "h_slide": "sliding door", "h_window": "window", "h_open": "plain opening"}[tool]
		"h_floor":
			return "Drag a rectangle to lay the floor chosen in the list; click a laid floor to take it up."
	return ""


## The walls and rooms as they stand, for undo and the layout file.
func snapshot() -> Array:
	var h = house()
	return [(h.cfg.get("walls", []) as Array).duplicate(true), (h.cfg.get("rooms", []) as Array).duplicate(true)]


func restore(snap: Array) -> void:
	var h = house()
	if h == null:
		return
	h.selected_wall = -1
	h.set_layout((snap[0] as Array).duplicate(true), (snap[1] as Array).duplicate(true))


func _changed(before: Array) -> void:
	god.undo_stack.append(["house", before])
	if god.undo_stack.size() > 80:
		god.undo_stack.pop_front()
	god.house_split_edited = true
	god.unsaved = true
	god._show_status()


## The point under the pointer in the house's space ({"q": Vector3, "lv": level}), or {}.
func _at(mpos: Vector2) -> Dictionary:
	var h = house()
	if h == null:
		return {}
	var hit = h.editor_pick(main.cam.project_ray_origin(mpos), main.cam.project_ray_normal(mpos))
	if hit == null:
		return {}
	var q: Vector3 = h.local(hit)
	return {"q": q, "lv": h.level_name_at(q)}


static func _snap(v: Vector2) -> Vector2:
	return Vector2(snappedf(v.x, SNAP), snappedf(v.y, SNAP))


func press(tool: String, mpos: Vector2) -> void:
	_drag = {}
	var h = house()
	var at := _at(mpos)
	if h == null or at.is_empty():
		main.hud.show_toast("That's not inside Marcus's house.")
		return
	var q: Vector3 = at["q"]
	var q2 := Vector2(q.x, q.z)
	var lv: String = at["lv"]
	match tool:
		"h_wall":
			var i: int = h.wall_near(q2, lv, 0.25)
			if i >= 0:
				h.selected_wall = i
				h.rebuild()
				_drag = {"mode": "slide", "i": i, "from": q2, "seg": (h.cfg["walls"][i]["wall"] as Array).duplicate(), "before": snapshot(), "moved": false}
			else:
				var before := snapshot()
				var a := _snap(q2)
				var walls: Array = h.cfg["walls"]
				walls.append({"level": lv, "wall": [a.x, a.y, a.x, a.y], "doors": []})
				h.selected_wall = walls.size() - 1
				_drag = {"mode": "draw", "i": walls.size() - 1, "a": a, "before": before}
		"h_door", "h_slide", "h_window", "h_open":
			_opening(tool, q2, lv)
		"h_floor":
			var before := snapshot()
			var a := _snap(q2)
			var rooms: Array = h.cfg["rooms"]
			rooms.append({"id": "patch_%d" % rooms.size(), "level": lv, "floor": floor_kind, "patch": true, "rects": [[a.x, a.y, 0.0, 0.0]]})
			_drag = {"mode": "floor", "i": rooms.size() - 1, "a": a, "q": q2, "before": before}


func move(mpos: Vector2) -> void:
	if _drag.is_empty():
		return
	var h = house()
	var at := _at(mpos)
	if h == null or at.is_empty():
		return
	var q: Vector3 = at["q"]
	var q2 := _snap(Vector2(q.x, q.z))
	match str(_drag["mode"]):
		"draw":
			var a: Vector2 = _drag["a"]
			var b := Vector2(q2.x, a.y) if absf(q2.x - a.x) >= absf(q2.y - a.y) else Vector2(a.x, q2.y) # square to the house
			h.cfg["walls"][_drag["i"]]["wall"] = [a.x, a.y, b.x, b.y]
			h.rebuild()
		"slide":
			var seg: Array = _drag["seg"]
			var from: Vector2 = _drag["from"]
			var along_x := absf(float(seg[2]) - float(seg[0])) > absf(float(seg[3]) - float(seg[1]))
			var d := snappedf((q2.y - from.y) if along_x else (q2.x - from.x), SNAP)
			var w: Dictionary = h.cfg["walls"][_drag["i"]]
			if along_x:
				w["wall"] = [seg[0], float(seg[1]) + d, seg[2], float(seg[3]) + d]
			else:
				w["wall"] = [float(seg[0]) + d, seg[1], float(seg[2]) + d, seg[3]]
			_drag["moved"] = absf(d) > 0.001
			h.rebuild()
		"floor":
			var a: Vector2 = _drag["a"]
			var lo := a.min(q2)
			var hi := a.max(q2)
			h.cfg["rooms"][_drag["i"]]["rects"] = [[lo.x, lo.y, hi.x - lo.x, hi.y - lo.y]]
			h.rebuild()


func release() -> void:
	if _drag.is_empty():
		return
	var d := _drag
	_drag = {}
	var h = house()
	match str(d["mode"]):
		"draw":
			var seg: Array = h.cfg["walls"][d["i"]]["wall"]
			if Vector2(float(seg[0]), float(seg[1])).distance_to(Vector2(float(seg[2]), float(seg[3]))) < 0.3:
				(h.cfg["walls"] as Array).remove_at(d["i"]) # a click, not a wall
				h.selected_wall = -1
				h.rebuild()
				return
			_changed(d["before"])
		"slide":
			if d["moved"]:
				_changed(d["before"])
		"floor":
			var r: Array = h.cfg["rooms"][d["i"]]["rects"][0]
			if float(r[2]) < 0.2 or float(r[3]) < 0.2:
				# a click: take up the floor laid here last, if any
				(h.cfg["rooms"] as Array).remove_at(d["i"])
				var q: Vector2 = d["q"]
				var rooms: Array = h.cfg["rooms"]
				for i in range(rooms.size() - 1, -1, -1):
					var room: Dictionary = rooms[i]
					if bool(room.get("patch", false)) and str(room["level"]) == h.level_name_at(Vector3(q.x, 0, q.y)):
						var rr: Array = room["rects"][0]
						if Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3])).has_point(q):
							rooms.remove_at(i)
							h.rebuild()
							_changed(d["before"])
							return
				h.rebuild()
				return
			_changed(d["before"])


## A door, sliding doors, window or plain opening in the wall under the pointer, or that one taken out.
func _opening(tool: String, q: Vector2, lv: String) -> void:
	var h = house()
	var i: int = h.wall_near(q, lv, 0.4)
	if i < 0:
		main.hud.show_toast("Click on a wall.")
		return
	var kind := {"h_door": "door", "h_slide": "slide", "h_window": "window", "h_open": "open"}[tool] as String
	var before := snapshot()
	var w: Dictionary = h.cfg["walls"][i]
	var seg: Array = w["wall"]
	var along_x := absf(float(seg[2]) - float(seg[0])) > absf(float(seg[3]) - float(seg[1]))
	var lo := minf(float(seg[0]), float(seg[2])) if along_x else minf(float(seg[1]), float(seg[3]))
	var hi := maxf(float(seg[0]), float(seg[2])) if along_x else maxf(float(seg[1]), float(seg[3]))
	var t := q.x if along_x else q.y
	var ops: Array = w.get("doors", [])
	for j in ops.size():
		var o: Array = ops[j]
		var ok := str(o[2]) if o.size() > 2 else "open"
		if absf(float(o[0]) - t) <= float(o[1]) * 0.5 + 0.05:
			ops.remove_at(j)
			if ok != kind: # a different kind there: swap it for this one, the same width
				ops.append([o[0], o[1], kind])
			w["doors"] = ops
			h.rebuild()
			_changed(before)
			return
	var wd: float = float(WIDTHS[kind])
	if hi - lo < wd + 0.1:
		main.hud.show_toast("That wall is too short for it.")
		return
	t = clampf(snappedf(t, SNAP * 0.5), lo + wd * 0.5 + 0.05, hi - wd * 0.5 - 0.05)
	for o in ops:
		if absf(float(o[0]) - t) < (float(o[1]) + wd) * 0.5:
			main.hud.show_toast("There's already an opening there.")
			return
	ops.append([t, wd, kind])
	w["doors"] = ops
	h.rebuild()
	_changed(before)


## Delete with the Wall tool: the picked wall goes.
func delete_selected() -> bool:
	var h = house()
	if h == null or h.selected_wall < 0 or h.selected_wall >= (h.cfg["walls"] as Array).size():
		return false
	var before := snapshot()
	(h.cfg["walls"] as Array).remove_at(h.selected_wall)
	h.selected_wall = -1
	h.rebuild()
	_changed(before)
	return true


func deselect() -> void:
	var h = house()
	if h != null and h.selected_wall >= 0:
		h.selected_wall = -1
		h.rebuild()

