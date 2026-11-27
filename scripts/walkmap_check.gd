extends RefCounted
## --only=walkmap: a picture of the walking grid (not a check; it prints no PASS or FAIL). Saves
## 80_walkmap.png in the autotest folder: 2 px a cell (0.5 m), the whole map, north up. Open ground
## is green-grey; what blocks is coloured by why: red a hill or dune too steep to walk (regions.gd
## relief), blue water (the swamp's pools, the Deep Mire's moat, the sea), black the map's edge,
## orange everything else (trees, rocks, buildings, fences, furniture). White outlines are the
## lands' walk rects, the farm and the town. It also prints how much of each land is blocked.

const Regions = preload("res://scripts/regions.gd")
const Town = preload("res://scripts/town.gd")


func run(m: Node, dir: String) -> void:
	var size: Vector2i = m.GRID_SIZE
	var img := Image.create(size.x * 2, size.y * 2, false, Image.FORMAT_RGB8)
	var whole: Rect2 = m.whole_map()
	var counts := {}
	for y in size.y:
		for x in size.x:
			var id := Vector2i(x, y)
			var cc: Vector3 = m._cell_center(id)
			var col := Color(0.42, 0.52, 0.38)
			var why := ""
			if not m._walkable(id):
				if not whole.has_point(Vector2(cc.x, cc.z)):
					why = "edge"
					col = Color(0.05, 0.05, 0.07)
				elif m.regions.relief(cc.x, cc.z) > Regions.RELIEF_BLOCK:
					why = "hill"
					col = Color(0.85, 0.2, 0.2)
				elif m.regions.mire_zone(cc.x, cc.z) == 1 or m.regions.pools.any(func(p): return Vector2(cc.x - p.x, cc.z - p.y).length() < p.z + 0.4):
					why = "water"
					col = Color(0.2, 0.4, 0.9)
				else:
					why = "thing"
					col = Color(0.95, 0.6, 0.15)
			var land: String = m.regions.region_at(cc.x, cc.z)
			if land == "":
				land = "(between)"
			if not counts.has(land):
				counts[land] = {"n": 0, "edge": 0, "hill": 0, "water": 0, "thing": 0}
			counts[land]["n"] += 1
			if why != "":
				counts[land][why] += 1
			for dx in 2:
				for dy in 2:
					img.set_pixel(x * 2 + dx, y * 2 + dy, col)
	var rects: Array = [m.LOT, Town.TOWN]
	for id in m.regions.defs:
		rects.append(m.regions._rect(m.regions.defs[id]["walk"]))
	for r in rects:
		var a: Vector2i = m._cell(Vector3((r as Rect2).position.x, 0, (r as Rect2).position.y)) * 2
		var b: Vector2i = m._cell(Vector3((r as Rect2).end.x, 0, (r as Rect2).end.y)) * 2
		for x in range(maxi(a.x, 0), mini(b.x, size.x * 2)):
			for yy in [a.y, b.y - 1]:
				if yy >= 0 and yy < size.y * 2:
					img.set_pixel(x, yy, Color.WHITE)
		for y in range(maxi(a.y, 0), mini(b.y, size.y * 2)):
			for xx in [a.x, b.x - 1]:
				if xx >= 0 and xx < size.x * 2:
					img.set_pixel(xx, y, Color.WHITE)
	# the biggest blocked patches that aren't hills or water, and what stands in each
	var seen := {}
	var patches := []
	for y in size.y:
		for x in size.x:
			var id := Vector2i(x, y)
			if seen.has(id) or m._walkable(id):
				continue
			var cc0: Vector3 = m._cell_center(id)
			if not whole.has_point(Vector2(cc0.x, cc0.z)) or m.regions.relief(cc0.x, cc0.z) > Regions.RELIEF_BLOCK or m.regions.mire_zone(cc0.x, cc0.z) == 1:
				continue
			var stack := [id]
			seen[id] = true
			var lo := id
			var hi := id
			var n := 0
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				n += 1
				lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
				hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = c + d
					if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or seen.has(q) or m._walkable(q):
						continue
					seen[q] = true
					stack.append(q)
			if n * 0.25 > 16.0:
				var a3: Vector3 = m._cell_center(lo)
				var b3: Vector3 = m._cell_center(hi)
				patches.append([n * 0.25, Rect2(a3.x, a3.z, b3.x - a3.x, b3.z - a3.z)])
	patches.sort_custom(func(a, b): return a[0] > b[0])
	for pt in patches.slice(0, 70):
		var r: Rect2 = pt[1]
		var inside := {}
		for el in m.god.els:
			if el.deleted or el.cut:
				continue
			if r.grow(0.5).has_point(Vector2(el.xf.origin.x, el.xf.origin.z)) and not m.god._block_rects(el).is_empty():
				inside[el.kind] = int(inside.get(el.kind, 0)) + 1
		print("WALKMAP PATCH %5.0f m2 at (%.0f, %.0f) %.0f x %.0f m: %s" % [pt[0], r.get_center().x, r.get_center().y, r.size.x, r.size.y, str(inside)])
	img.save_png(dir.path_join("80_walkmap.png"))
	for land in counts:
		var c: Dictionary = counts[land]
		print("WALKMAP %-12s blocked %4.1f%%: hills %4.1f%%, water %4.1f%%, things %4.1f%%, edge %4.1f%%" % [land,
			100.0 * (c["edge"] + c["hill"] + c["water"] + c["thing"]) / c["n"], 100.0 * c["hill"] / c["n"], 100.0 * c["water"] / c["n"],
			100.0 * c["thing"] / c["n"], 100.0 * c["edge"] / c["n"]])
