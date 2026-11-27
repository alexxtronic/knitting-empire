extends RefCounted
## --only=hamlets: the hidden hamlets of 2026-11-27 (scripts/hamlets.gd, data/hamlets.json).
## Every hamlet stands with its buildings solid on the walking grid, in the world editor, its keeper
## on open ground that can be walked to from the farm; Rimefall's snowfield has no grass; walking
## into each finds it (the flag, the toast) and the goal list counts them; a keeper's menu, his
## greeting, the sweater he wants (sheep's wool in Act 1, one of his own fibres once it's open),
## his premium in the haggle panel and the sale, the red pin and its going, his hat; the windmill's
## sails turning; a hamlet moved in the world editor taking its keeper along; the save.
## Saves 79_hamlet_<id>.png (by day), 79_hamlet_<id>_night.png, 79_hamlet_keeper_<id>.png and
## 79_hamlet_sale.png. Leaves the flags, her things, the coins and where she stood as it found them.

const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Hamlets = preload("res://scripts/hamlets.gd")
const Town = preload("res://scripts/town.gd")

var m: Node


func _look(at: Vector3, dist: float, pitch: float, secs := 2.0) -> void:
	m.player.position = m._open_near(at, 3.0) if not m._walkable(m._cell(at)) else at
	m.cam_glide = {"pos": at, "dist": dist, "pitch": pitch}
	await m._wait(secs)


func _reaches(a: Vector3, b: Vector3) -> bool:
	var path: Array = m._find_path(a, b)
	return not path.is_empty() and Vector2((path[path.size() - 1] as Vector3).x - b.x, (path[path.size() - 1] as Vector3).z - b.z).length() < 1.2


func run(main: Node) -> void:
	m = main
	var hm = m.hamlets
	var keep := {"flags": Game.flags.duplicate(true), "inv": Game.inv.duplicate(true), "coins": Game.coins, "day": Game.day,
		"hour": Game.hour, "clock": Game.time_running, "pos": m.player.position, "fibre_on": SweaterSale.fibre_on,
		"sweaters": Game.sweaters.size()}
	Game.time_running = false
	Game.hour = 11.0
	m.hud.hide_dialogue()
	m.hud.tip_panel.visible = false
	Game.flags.erase("hamlets")
	for h in hm.hamlets:
		Game.flags.erase("hamlet_greeted_" + str(h["cfg"]["id"]))
	Hamlets.on = true
	hm.apply()
	# --- they stand
	var ids: Array = hm.hamlets.map(func(h): return str(h["cfg"]["id"]))
	var listed: int = Town.built.filter(func(b): return str(b[1]) == "hamlet").size()
	var solid := true
	var keepers_ok := true
	var farm := Vector3(10, 0, -3)
	var unreachable := []
	for h in hm.hamlets:
		var n: Node3D = h["node"]
		var k = h["keeper"]
		if k == null or not m._walkable(m._cell(k.position)):
			keepers_ok = false
			unreachable.append(str(h["cfg"]["id"]) + " (blocked)")
		if k == null or not _reaches(farm, k.position):
			unreachable.append(str(h["cfg"]["id"]))
		for bc in h["cfg"].get("buildings", []):
			var c: Vector3 = n.global_transform * Vector3(float(bc[1]), 0, float(bc[2]))
			solid = solid and not m._walkable(m._cell(c))
	m._check("the hidden hamlets stand (%s), each in the world editor (%d), every building solid on the grid (%s)" % [str(ids), listed, str(solid)],
		ids.size() == 4 and listed == 4 and solid and ids.has("hexwood") and ids.has("rimefall") and ids.has("sunwell") and ids.has("larkhill"))
	m._check("each has its keeper on open ground, every one walkable to from the farm (not: %s)" % str(unreachable), keepers_ok and unreachable.is_empty() and hm.keepers.size() == 4)
	# --- Rimefall's snow
	var rime: Node3D = hm.node_of("rimefall")
	var hex: Node3D = hm.node_of("hexwood")
	var snow_blades: int = m.grass.blades_near(rime.global_position.x - 6.0, rime.global_position.z + 6.0, 2.5)
	var hex_blades: int = m.grass.blades_near(hex.global_position.x + 3.0, hex.global_position.z + 9.0, 3.0)
	m._check("no grass on Rimefall's snowfield (%d blades), grass in Hexwood Hollow (%d)" % [snow_blades, hex_blades], snow_blades == 0 and hex_blades > 0 and rime.get_node_or_null("Snowfall") != null)
	# --- finding them, and a picture of each by day
	var toasts := []
	for h in hm.hamlets:
		var n: Node3D = h["node"]
		var id := str(h["cfg"]["id"])
		await _look(n.global_position + Vector3(0, 0, 9.0), 17.0, 32.0, 2.2)
		toasts.append(hm._found_toast)
		await m._shot("79_hamlet_%s.png" % id)
	var f: Dictionary = Hamlets.found()
	m._check("walking into each finds it (%s; last toast: %s)" % [str(f.keys()), hm._found_toast], f.size() == 4 and hm._found_toast.begins_with("Discovered"))
	m._check("the goal list counts them (%d of the Act 3 goal's 4)" % m.goals.metric({"check": "hamlets"}), m.goals.metric({"check": "hamlets"}) == 4)
	# --- the sails turn
	var lark: Dictionary = hm.hamlets.filter(func(h): return str(h["cfg"]["id"]) == "larkhill")[0]
	await _look(lark["node"].global_position + Vector3(0, 0, 6.0), 14.0, 25.0, 0.5)
	var s0: float = (lark["sails"][0] as Node3D).rotation.z
	await m._wait(1.0)
	m._check("Larkhill's windmill turns its sails", absf((lark["sails"][0] as Node3D).rotation.z - s0) > 0.2)
	# --- at night
	for id in ["hexwood", "rimefall"]:
		var n: Node3D = hm.node_of(id)
		Game.hour = 22.5
		await _look(n.global_position + Vector3(0, 0, 9.0), 16.0, 30.0, 2.0)
		await m._shot("79_hamlet_%s_night.png" % id)
	Game.hour = 11.0
	# --- a keeper: Thistle in Hexwood Hollow
	var th = hm.keepers.filter(func(k): return k.hamlet_id == "hexwood")[0]
	SweaterSale.fibre_on = true
	SweaterSale.force_fibre = ""
	Game.flags.erase("act1_done")
	Game.add_sweater(1, "")
	await _look(th.position + Vector3(0, 0, 2.6), 4.5, 12.0, 1.0)
	var rows: Array = th.ke_actions().map(func(r): return str(r["id"]))
	th.ke_action("talk")
	m._check("Thistle's menu: Talk and a sweater (%s); her first word is a greeting" % str(rows), rows.has("talk") and rows.has("sale") and Game.flag("hamlet_greeted_hexwood") == true)
	m.hud.hide_dialogue()
	m._check("in Act 1 she wants sheep's wool (%s)" % SweaterSale.wanted_fibre(th.vid), SweaterSale.wanted_fibre(th.vid) == "wool")
	var pin: Node = th.get_node_or_null("SweaterPin")
	m._check("she wears the red pin", pin != null and pin.visible)
	var mult := float(SweaterSale.themed[th.vid]["mult"])
	var with_premium: int = m.sale.reserve(th.vid, 1, "wool")
	var saved = SweaterSale.themed[th.vid]
	SweaterSale.themed.erase(th.vid)
	var without: int = m.sale.reserve(th.vid, 1, "wool")
	SweaterSale.themed[th.vid] = saved
	m._check("she'd pay x%.1f what anyone else would (%dc against %dc)" % [mult, with_premium, without], absf(float(with_premium) / maxf(1.0, float(without)) - mult) < 0.05)
	th.ke_action("sale")
	await m._wait(0.6)
	var start_price: int = m.sale.price
	await m._shot("79_hamlet_sale.png")
	var fair: int = m.sale.fair(int(Game.sweaters[m.sale.choice]), SweaterSale.fibre_of(m.sale.choice))
	var c0 := Game.coins
	m.sale._sell(start_price)
	await m._wait(0.6)
	m._check("the haggle panel opens at her price (%dc, the town's %dc) and the sale pays it (+%dc)" % [start_price, fair, Game.coins - c0],
		start_price == int(round(fair * mult)) and Game.coins - c0 == start_price and Game.sweaters.size() == keep["sweaters"])
	await m._wait(0.7)
	pin = th.get_node_or_null("SweaterPin")
	var rows2: Array = th.ke_actions().map(func(r): return str(r["id"]))
	m._check("one a day: the pin goes and her menu says to come back (%s)" % str(rows2), (pin == null or not pin.visible) and not rows2.has("sale"))
	# Act 1 done and a raccoon combed: she wants one of her own dark fibres
	Game.flags["act1_done"] = true
	var guide: Dictionary = Game.flags.get("guide", {}).duplicate(true)
	guide["raccoon"] = {"seen": 1, "caught": 1, "combed": 1}
	Game.flags["guide"] = guide
	var want := SweaterSale.wanted_fibre(th.vid)
	var own: Array = hm.cfg_of("hexwood")["keeper"]["wants"]
	m._check("after Act 1 she wants one of her own fibres (%s), never one she can't get" % want, want in own and SweaterSale.fibre_open(want))
	# --- the hats, close up
	var hats := 0
	for k in hm.keepers:
		if k.body and k.body.skeleton and not k.body.skeleton.find_children("Hat", "Node3D", true, false).is_empty():
			hats += 1
		await _look(k.position + Vector3(0, 0, 2.4), 3.2, 8.0, 1.2)
		m.cam_glide = {"pos": k.position + Vector3(0, 1.4, 0), "dist": 2.6, "pitch": 6.0}
		m.hud.hide_dialogue()
		await m._wait(1.0)
		await m._shot("79_hamlet_keeper_%s.png" % k.hamlet_id)
	m._check("every keeper wears a hat of the theme (%d)" % hats, hats == 4)
	# --- moved in the world editor, the keeper goes with it
	var p0: Vector3 = hex.position
	hex.position += Vector3(3.0, 0, 0)
	await m._wait(0.8)
	var followed: bool = Vector2(th.home.x - (p0.x + 3.0 + 1.8), th.home.z - (p0.z + 3.4)).length() < 0.6
	hex.position = p0
	await m._wait(0.8)
	m._check("a hamlet moved in the world editor takes its keeper along", followed)
	# --- the save
	var saved_d: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	m._check("the save keeps the hamlets she found", ((saved_d.get("flags", {}) as Dictionary).get("hamlets", {}) as Dictionary).size() == 4)
	# --- put it all back
	while Game.sweaters.size() > int(keep["sweaters"]):
		Game.remove_sweater(Game.sweaters.size() - 1)
	Game.flags = keep["flags"]
	Game.inv = keep["inv"]
	Game.coins = int(keep["coins"])
	Game.day = int(keep["day"])
	Game.hour = float(keep["hour"])
	Game.time_running = bool(keep["clock"])
	SweaterSale.fibre_on = bool(keep["fibre_on"])
	Hamlets.on = false
	hm.apply()
	m.player.position = keep["pos"]
	m.cam_glide = {}
