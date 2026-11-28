extends Node
## The Objectives tab (Alex, 2026-11-28: "a more clear way to play the game ... an 'objectives' tab at
## the top that's clickable telling them main objectives (build your first animal pen) and side quests
## (make a sweater for NAME). When user clicks on objective a small blue line will appear on the ground
## and on the minimap leading them to where they need to go with a blue icon over the objective area.
## Do this for all objectives for the entire game playthrough start to finish").
##
## Nothing here keeps a record of its own of what's done: twice a second the list is read again from
## the state the rest of the game keeps (`build_list()`):
##   Main: wolves at the pen; in Act 1's guided part the story's goal line (Game.flags["goal"]), or
##     whoever has a scene waiting (the gold star) between its steps; after it the "Next" line
##     (coach.gd) and the act's Empire goals (empire_goals.gd window()), then the chapter skip from
##     her bed once the act's goals are done.
##   Side: a local's request (empire.gd), Marcus's favour and his house (house_sale.gd), a date or any
##     other goal line a scene sets after Act 1, mail orders and post in the box (mail.gd), online
##     orders (online_store.gd), anyone with a scene waiting, asking a man out (partners.gd), and the
##     red-pin buyers who want a sweater today (sweater_sale.gd, townsfolk.gd).
## Each objective resolves to a live point (`target`: a Node3D, a Vector3 or null), read from the nodes
## themselves rather than coordinates, since Alex moves buildings, pens and the mailbox in the world
## editor. Where an objective has no place of its own (knit ten designs, earn 1,000c in a day) it points
## where its next action happens (the rocking chair, a buyer, Rosa for wool).
##
## Tracking: Game.flags["objective"] is the id she clicked, "main" for the first main objective (a slot,
## so Act 1 follows each step without a click per step), or absent. Tracked, a blue route lies on the
## ground from her (or the dog while he's played) along the walking grid (main._find_path), a blue
## icon stands over the target, and the minimap draws both (`draw_on_map()`). The ribbon and the marker
## are on FogOfWar.LAYER, which the minimap's camera leaves out, so the map draws its own flat copy.
## Hidden in a story scene, on the title, in the cinematic camera, the world editor and Build & Buy.
##
## Hidden hamlets are never pointed at directly: the route goes to the land they lie in (or a spot
## some way short of them in the woods), so finding one is still a find.
##
## Every line players see here is a DRAFT until Alex approves it.

const Coach = preload("res://scripts/coach.gd")
const Keys = preload("res://scripts/keybinds.gd")
const SHADER = preload("res://shaders/objective_path.gdshader")
const Story = preload("res://scripts/story.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const HouseSale = preload("res://scripts/house_sale.gd")
const OnlineStore = preload("res://scripts/online_store.gd")
const FogOfWar = preload("res://scripts/fog_of_war.gd")

const BLUE := Color(0.30, 0.66, 1.0)
const BLUE_DARK := Color(0.06, 0.15, 0.30)
const GOLD := Color(0.95, 0.80, 0.46)
const TEXT := Color(0.97, 0.93, 0.85)
const DIM := Color(0.80, 0.76, 0.68)
const LIST_EVERY := 0.5
const DRAW_EVERY := 0.1
const MAX_TALKS := 4
const MAX_BUYERS := 3
const ARRIVED := 3.0 # m: closer than this the route goes; the icon stays
const WIDTH := 0.34 # the route's width, m
const LIFT := 0.12 # over the ground, m
const STEP := 0.6 # m between the route's points on the ground
const ICON_PX := 96
const STORY_PEN := Vector3(13.5, 0, -14) # where Act 1 asks for the pen (act1.scene)
const PANEL_W := 430.0

## Off in the autotest but for its own check (like EmpireGoals.on): no tab, nothing tracked.
static var on := true

var main: Node
var items: Array = [] # {"id", "kind": "main" | "side", "text", "detail", "target": Node3D | Vector3 | null}
var btn: Button
var panel: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _sig := ""
var _t := 0.0
var _line: MeshInstance3D
var _mesh: ImmediateMesh
var _mat: ShaderMaterial
var marker: Node3D
var _icon: Sprite3D
var _beam: GeometryInstance3D
var route: Array = [] # Vector3: the walking grid's path from where it was worked out to the target
var _route_from := Vector3.INF
var _route_to := Vector3.INF
var _route_stamp := -1
var _route_age := 0.0
var _draw_t := 0.0
var goal: Variant = null # the tracked objective's point now (Vector3), or null
var shown := false # the route and the marker are up
var drawn: Array = [] # Vector3: the ribbon as drawn last, from the hero on (the minimap draws it)
var path_us := 0 # how long the last route took to work out (the check prints it)
var _hid_gold := false # the story's gold marker, hidden while its goal is tracked


func _ready() -> void:
	name = "Objectives"


## The tab, its panel, the ribbon and the marker (main.gd, once it has a HUD).
func setup() -> void:
	var hud: Node = main.hud
	btn = hud._button("Objectives", func(): toggle())
	btn.tooltip_text = "Main objectives and side quests (%s). Click one to show the way." % Keys.key_name(Keys.bound("objectives"))
	hud.root.add_child(btn)
	hud._place(btn, 0.0, 0.0, Vector2(16, 16))
	hud.chrome.append(btn)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", hud._sb(Color(0.13, 0.10, 0.08, 0.95), 10, GOLD, 12.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title: Label = hud._label("Objectives", 20, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var shut: Button = hud._button("×", func(): close())
	shut.tooltip_text = "Close (Esc)"
	head.add_child(shut)
	vb.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(PANEL_W, 0)
	_scroll = scroll
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	vb.add_child(scroll)
	var foot: Label = hud._label("Click one to show the way with a blue line. Click it again to stop.", 12, DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(PANEL_W, 0)
	vb.add_child(foot)
	panel.add_child(vb)
	panel.visible = false
	hud.root.add_child(panel)
	hud._place(panel, 0.0, 0.0, Vector2(16, 62))
	_build_world()
	_place_tab()


## The tab sits just right of the Menu button.
func _place_tab() -> void:
	var mb: Button = main.hud.menu_btn
	if mb == null:
		return
	var x: float = 16.0 + mb.get_combined_minimum_size().x + 8.0
	btn.offset_left = x
	btn.offset_right = x


func is_open() -> bool:
	return panel != null and panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if panel == null or not on:
		return
	items = build_list()
	_sig = ""
	_rebuild_rows()
	panel.visible = true
	panel.move_to_front()
	main.hud.click("ui_open")


func close() -> void:
	if panel:
		panel.visible = false


# --- tracking -----------------------------------------------------------------------------------

func tracked_id() -> String:
	return str(Game.flags.get("objective", ""))


## Shows the way to objective `id` ("main" follows the first main objective, whatever it is).
func track(id: String) -> void:
	if id == "":
		untrack()
		return
	Game.flags["objective"] = id
	_route_to = Vector3.INF # work the route out again now
	_sig = ""
	_refresh()


func untrack() -> void:
	Game.flags.erase("objective")
	_sig = ""
	_refresh()


## The objective being tracked ({} if none).
func tracked() -> Dictionary:
	var id := tracked_id()
	if id == "":
		return {}
	for o in items:
		if id == "main" and str(o["kind"]) == "main":
			return o
		if str(o["id"]) == id:
			return o
	return {}


## A row was clicked: track it, or stop if it already is.
func pick(id: String) -> void:
	var first_main := ""
	for o in items:
		if str(o["kind"]) == "main":
			first_main = str(o["id"])
			break
	var as_id := "main" if id == first_main else id
	var cur := tracked()
	if not cur.is_empty() and str(cur["id"]) == id:
		untrack()
	else:
		track(as_id)
		var o := _item(id)
		if not o.is_empty() and o.get("target") == null:
			main.hud.show_toast("No one place for this one: %s" % str(o.get("detail", "")) if str(o.get("detail", "")) != "" else "This one has no single place to go to.")
	main.hud.click()


func _item(id: String) -> Dictionary:
	for o in items:
		if str(o["id"]) == id:
			return o
	return {}


# --- the list -----------------------------------------------------------------------------------

func _o(id: String, kind: String, text: String, target: Variant, detail := "") -> Dictionary:
	if target is Node3D and not is_instance_valid(target):
		target = null
	return {"id": id, "kind": kind, "text": text, "target": target, "detail": detail}


## Every objective she has now, main ones first.
func build_list() -> Array:
	var out: Array = []
	if main == null:
		return out
	var act1_done: bool = Game.flag("act1_done") == true
	var guided: bool = not act1_done and Game.flag("story_farm") == true
	var goal_text := str(Game.flag("goal", ""))
	if goal_text == "false":
		goal_text = ""
	var used := {} # villagers already given an objective, so nobody is listed twice
	# --- main
	if main.wolves != null and main.wolves.active():
		out.append(_o("wolves", "main", "Wolves at your pen! Run at them, or play the dog and bark, before they take an animal", _pen_point()))
	if guided:
		if goal_text != "":
			out.append(_o("story", "main", goal_text, story_target(goal_text)))
		else:
			var v = _talkers(used, 1)
			if not v.is_empty():
				out.append(_o("story", "main", "Talk to %s: they have something to tell you" % v[0].display_name(), v[0]))
	else:
		var ns: Array = Coach.next_step(main)
		if str(ns[0]) != "":
			out.append(_o("next", "main", "Next: " + str(ns[1]), coach_target(str(ns[0]))))
		if main.goals != null:
			var w: Array = main.goals.window()
			for g in w:
				out.append(_goal_item(g))
			if w.is_empty() and not main.goals.defs.is_empty() and Game.act < 4:
				out.append(_o("chapter", "main", "Begin the next chapter: sleep in your bed and choose \"Begin the next chapter…\"", _bed()))
			elif main.goals.defs.is_empty() and Game.act >= 4:
				out.append(_o("act4", "main", "The last chapter: grow your empire as you like. (Its goals are still to come.)", null, "nothing to find yet"))
	# --- side
	if act1_done or not guided:
		_request_items(out, used)
		_marcus_items(out, used)
		if goal_text != "" and main.empire != null and main.empire.request().is_empty():
			out.append(_o("story", "side", goal_text, story_target(goal_text))) # a date, or a scene's own errand
		_post_items(out)
		_store_items(out)
		_partner_items(out, used)
	for v in _talkers(used, MAX_TALKS if act1_done else 2):
		out.append(_o("talk:" + str(v.vid), "side", "Talk to %s: they have something to tell you" % v.display_name(), v))
		used[str(v.vid)] = true
	if act1_done or not guided:
		for v in _buyers(used):
			var want := ""
			if SweaterSale.fibre_on:
				var f := SweaterSale.wanted_fibre(str(v.vid))
				if f != "" and f != "wool" and main.wildlife != null:
					want = " (a %s one)" % str(main.wildlife.item_name(f)).to_lower()
			out.append(_o("buyer:" + str(v.vid), "side", "%s wants a sweater today%s: offer them one" % [v.display_name(), want], v))
	return out


func _goal_item(g: Dictionary) -> Dictionary:
	var text: String = main.goals.label(g)
	var check := str(g.get("check", ""))
	var t: Variant = goal_target(g)
	var detail := ""
	if check == "hamlets":
		detail = "a hidden hamlet lies somewhere out this way"
	elif check == "ready":
		text = str(g.get("line", "Ready for the next chapter"))
	return _o("goal:" + str(g["id"]), "main", text, t, detail)


func _request_items(out: Array, used: Dictionary) -> void:
	var e = main.empire
	if e == null:
		return
	var r: Dictionary = e.request()
	if not r.is_empty():
		var v = main._villager(str(r.get("who", "")))
		var who: String = v.display_name() if v else str(r.get("who", "")).capitalize()
		var what: String = e._what(r)
		var made: int = e._made(r)
		var text := ""
		var t: Variant = null
		if made > 0:
			text = "Take %s %s  (+%dc)" % [who, what.replace(" or better", ""), e.payout()]
			t = v
		elif r.has("rarity"):
			text = "Knit %s for %s  (+%dc)" % [what, who, int(r.get("pay", 0))]
			t = sweater_target()
		else:
			var fibre := str(r.get("fibre", ""))
			text = "Make %s for %s: find a %s, comb it and knit with its fibre  (+%dc)" % [what, who, e._animal_of(fibre), int(r.get("pay", 0))]
			t = fibre_target(fibre)
		out.append(_o("request", "side", text, t))
		if v:
			used[str(v.vid)] = true
		return
	var d: Dictionary = e.due()
	if not d.is_empty():
		var v = main._villager(str(d.get("who", "")))
		if v:
			out.append(_o("request", "side", "%s has a request for you: ask what they'd like" % v.display_name(), v))
			used[str(v.vid)] = true


func _marcus_items(out: Array, used: Dictionary) -> void:
	var hs = main.house_sale
	if hs == null or not hs._ready_for_task() or HouseSale.owned():
		return
	var p = main._villager(HouseSale.MARCUS) if main.townsfolk != null else null
	var where: Variant = p if p != null and (p as Node3D).visible else _marcus_house()
	var task := HouseSale.task()
	match task:
		"":
			out.append(_o("marcus", "side", "Marcus has a favour to ask: find him round town", where, "he's about town by day"))
		"asked":
			if Game.sweaters.is_empty():
				out.append(_o("marcus", "side", "Knit a sweater for Marcus (any will do)", sweater_target()))
			else:
				out.append(_o("marcus", "side", "Give Marcus a sweater: his favour", where, "he's about town by day"))
		"done":
			out.append(_o("marcus", "side", "Buy Marcus's house in Bretton Oaks  (%dc)" % HouseSale.price(), where, "he's about town by day"))
	used[HouseSale.MARCUS] = true


func _marcus_house() -> Variant:
	var sb = main.suburb
	if sb == null or not sb.has_method("houses"):
		return null
	for h in sb.houses():
		if int(h.get("i", -1)) == 1:
			return h.get("door", null)
	return null


func _post_items(out: Array) -> void:
	var m = main.mail
	if m == null or m.box == null:
		return
	var box: Variant = m.stop_point()
	if not m.letters_in_box().is_empty():
		out.append(_o("post", "side", "Post in your mailbox: take it out and read it", box))
	for pair in m.open_orders():
		var o: Dictionary = pair[1]
		var stars := int(o.get("stars", 1))
		var who := str(o.get("from", "a customer"))
		var have: bool = m.sweater_for(o) >= 0
		out.append(_o("mail:" + str(pair[0]), "side", "Mail order: post a %s sweater to %s  (%dc)" % ["★".repeat(stars), who, int(o.get("pay", 0))],
			box if have else sweater_target(stars)))


func _store_items(out: Array) -> void:
	var s = main.store
	if s == null or not s.owns():
		return
	var pc: Variant = s.computer()
	var n := 0
	for o in s.orders():
		var fibre := str(o.get("fibre", ""))
		var have: bool = s.sweater_for(o) >= 0
		var name_f: String = str(main.wildlife.item_name(fibre)).to_lower() if main.wildlife else fibre
		out.append(_o("store:" + str(o.get("id", n)), "side", "Online order: a %s sweater for %s  (%s left)" % [name_f, str(o.get("who", "")), OnlineStore._hours_text(maxf(0.0, s.hours_left(o)))],
			pc if have else fibre_target(fibre)))
		n += 1
		if n >= 4:
			break


func _partner_items(out: Array, used: Dictionary) -> void:
	var pt = main.partners
	if pt == null or not pt.has_method("can_ask"):
		return
	var asked: Dictionary = Game.flags.get("partner_asked", {})
	for v in main.villagers:
		var id := str(v.vid)
		if used.has(id) or not pt.can_ask(id) or int(asked.get(id, -99)) == Game.day:
			continue
		out.append(_o("partner:" + id, "side", "Ask %s out" % v.display_name(), v))
		used[id] = true


## Villagers with a scene waiting (the gold star over their head), nearest first.
func _talkers(used: Dictionary, most: int) -> Array:
	var out: Array = []
	for v in main.villagers:
		if used.has(str(v.vid)) or not is_instance_valid(v):
			continue
		if Story.find_trigger("talk", str(v.vid)) != "":
			out.append(v)
	return _nearest(out, most)


## Whoever wears the red pin today (wants a sweater), nearest first.
func _buyers(used: Dictionary) -> Array:
	var out: Array = []
	var all: Array = main.villagers.duplicate()
	if main.townsfolk != null:
		all.append_array(main.townsfolk.people)
	for v in all:
		if not is_instance_valid(v) or used.has(str(v.vid)):
			continue
		var pin := (v as Node).get_node_or_null("SweaterPin") as Node3D
		if pin and pin.visible:
			out.append(v)
	return _nearest(out, MAX_BUYERS)


func _nearest(nodes: Array, most: int) -> Array:
	var h := _hero_pos()
	nodes.sort_custom(func(a, b): return _flat(a.global_position, h) < _flat(b.global_position, h))
	return nodes.slice(0, most)


# --- where each one is ---------------------------------------------------------------------------

## A story goal line to a live point: the person named in it, the chair, a stray, else its own spot.
func story_target(text: String) -> Variant:
	var low := text.to_lower()
	var dot := low.find(". ")
	if low.begins_with("rowan ") and dot > 0 and dot < 14: # "Rowan 2/4. Herd ...": the task is what follows
		low = low.substr(dot + 2)
	var gp: Variant = Game.flag("goal_pos", null)
	var pos: Variant = Vector3(float(gp[0]), 0, float(gp[1])) if gp is Array and (gp as Array).size() >= 2 else null
	for start in ["meet ", "head home", "go to", "find where", "plant"]:
		if low.begins_with(start) and pos != null:
			return pos # a place: the rock, the fountain, Gran's house
	if low.begins_with("knit") or "rocking chair" in low:
		var c := _chair()
		if c:
			return c
	if low.begins_with("herd") or ("strays" in low and not low.begins_with("build")):
		var s := _stray()
		if s:
			return s
	if low.begins_with("shear"):
		var w := _woolly()
		if w:
			return w
	if low.begins_with("build a pen"):
		return pos if pos != null else _pen_point()
	if low.begins_with("sell") and not "rosa" in low:
		var b := _buyers({})
		if not b.is_empty():
			return b[0]
		return pos
	if low.begins_with("take ") or low.begins_with("find a ") or low.begins_with("knit "):
		pass
	# whoever it names first
	var best: Node3D = null
	var at := 1 << 30
	for v in main.villagers:
		var nm := str(v.title).to_lower()
		var i := low.find(nm)
		if nm != "" and i >= 0 and i < at:
			best = v
			at = i
	if best:
		return best
	return pos


## The coach's "Next" step to where it's done.
func coach_target(id: String) -> Variant:
	match id:
		"sell":
			return _buyer_or_rosa()
		"knit":
			return _chair()
		"shear":
			return _furry_penned()
		"pen", "full":
			return _new_pen_point()
		"lead":
			return _pen_point()
		"catch":
			return _wild(func(_a): return true)
	return null


## An Empire goal to where its next action happens.
func goal_target(g: Dictionary) -> Variant:
	var wl = main.wildlife
	match str(g.get("check", "")):
		"caught", "penned":
			if wl and not wl.following().is_empty():
				return _pen_point()
			return _wild(func(_a): return true)
		"combed": # a wild one: one of hers in a pen with its coat back, else one out in the wild
			var mine: Array = wl.penned().filter(func(a): return a.has_method("has_fur") and a.has_fur()) if wl else []
			if not mine.is_empty():
				return _nearest(mine, 1)[0]
			return _wild(func(a): return a.has_method("has_fur") and a.has_fur())
		"fibre_knits":
			return fibre_target("")
		"face_sales", "best_day", "designs":
			return sweater_target()
		"needles":
			return main._villager("rosa")
		"guide_seen":
			var g0: Dictionary = Game.flags.get("guide", {})
			return _wild(func(a): return not (g0.has(a.species) and (g0[a.species] as Dictionary).has("seen")))
		"requests":
			var r: Dictionary = main.empire.request() if main.empire else {}
			if not r.is_empty():
				return main._villager(str(r.get("who", "")))
			var d: Dictionary = main.empire.due() if main.empire else {}
			if not d.is_empty():
				return main._villager(str(d.get("who", "")))
			return _nearest(main.villagers.duplicate(), 1)[0] if not main.villagers.is_empty() else null
		"pens":
			return _new_pen_point()
		"barn":
			return main._villager("lars")
		"large_plot":
			return main._villager("gary")
		"hamlets":
			return hamlet_hint()
		"ready":
			return _bed()
	return null


## What making a sweater needs next: sell the one she has, knit the wool she has, shear a coat
## that's ready, or buy wool from Rosa.
func sweater_target(stars := 0) -> Variant:
	var have := false
	for q in Game.sweaters:
		if int(q) >= stars:
			have = true
	if have:
		return _buyer_or_rosa()
	if Game.has_item("wool", 3):
		return _chair()
	var f := _furry_penned()
	if f:
		return f
	return main._villager("rosa")


## Knitting with a wild fibre ("" any): knit if she has it and the wool, buy wool, or find the animal.
func fibre_target(fibre: String) -> Variant:
	var wl = main.wildlife
	var has_fibre := false
	if wl:
		for sp in wl.data.get("animals", {}):
			var f := str(wl.data["animals"][sp].get("fibre", ""))
			if f != "" and f != "wool" and (fibre == "" or f == fibre) and Game.has_item(f, 1):
				has_fibre = true
	if has_fibre:
		return _chair() if Game.has_item("wool", 2) else main._villager("rosa")
	return _wild(func(a): return a.has_method("has_fur") and a.has_fur() and (fibre == "" and str(a.info.get("fibre", "wool")) != "wool" or str(a.info.get("fibre", "")) == fibre))


## Toward a hidden hamlet she hasn't found, without giving it away: the land it lies in, or a spot
## short of it on the way from the farm.
func hamlet_hint() -> Variant:
	var hm = main.hamlets
	if hm == null:
		return null
	var best: Variant = null
	var bd := INF
	var h := _hero_pos()
	for x in hm.hamlets:
		var cfg: Dictionary = x.get("cfg", {})
		var id := str(cfg.get("id", ""))
		var n: Node3D = x.get("node")
		if hm.is_found(id) or n == null or not is_instance_valid(n):
			continue
		var c := n.global_position
		var d := _flat(c, h)
		if d < bd:
			bd = d
			best = c
	if best == null:
		return null
	var c3: Vector3 = best
	if main.regions != null:
		for k in main.regions.defs:
			var w: Array = main.regions.defs[k].get("walk", [])
			if w.size() == 4:
				var r := Rect2(float(w[0]), float(w[1]), float(w[2]), float(w[3]))
				if r.has_point(Vector2(c3.x, c3.z)):
					return Vector3(r.get_center().x, 0, r.get_center().y)
	var home := Vector3(10, 0, 0)
	return c3 + (home - c3).normalized() * 30.0


func _buyer_or_rosa() -> Variant:
	var b := _buyers({})
	return b[0] if not b.is_empty() else main._villager("rosa")


func _chair() -> Node3D:
	return _furn(["rocking_chair", "armchair"])


func _bed() -> Node3D:
	return _furn(["bed", "single_bed", "double_bed"])


func _furn(ids: Array) -> Node3D:
	var best: Node3D = null
	var bd := INF
	var h := _hero_pos()
	for f in main.furniture:
		if is_instance_valid(f) and str(f.item_id) in ids:
			var d := _flat(f.global_position, h)
			if d < bd:
				bd = d
				best = f
	return best


func _stray() -> Node3D:
	var best: Node3D = null
	var bd := INF
	var h := _hero_pos()
	for s in main.sheep_list:
		if not is_instance_valid(s):
			continue
		var p := Vector2(s.global_position.x, s.global_position.z)
		if s.pen.size.x > 0.0 and s.pen.grow(0.3).has_point(p):
			continue
		var d := _flat(s.global_position, h)
		if d < bd:
			bd = d
			best = s
	return best


func _woolly() -> Node3D:
	for s in _nearest(main.sheep_list.filter(func(x): return is_instance_valid(x) and x.is_woolly()), 1):
		return s
	return null


## The nearest of her own animals with a coat ready (a sheep or a penned wild one).
func _furry_penned() -> Node3D:
	var all: Array = main.sheep_list.filter(func(x): return is_instance_valid(x) and x.is_woolly())
	if main.wildlife:
		all.append_array(main.wildlife.penned().filter(func(a): return a.has_method("has_fur") and a.has_fur()))
	var n := _nearest(all, 1)
	return n[0] if not n.is_empty() else null


## The nearest wild animal still out in the wild that `ok` accepts.
func _wild(ok: Callable) -> Node3D:
	var wl = main.wildlife
	if wl == null:
		return null
	var best: Node3D = null
	var bd := INF
	var h := _hero_pos()
	for a in wl.animals:
		if not is_instance_valid(a) or a.caught or a.penned or not ok.call(a):
			continue
		var d := _flat(a.global_position, h)
		if d < bd:
			bd = d
			best = a
	return best


func _pen_point() -> Vector3:
	var pens: Array = main.wildlife.pens() if main.wildlife else []
	if not pens.is_empty():
		var r: Rect2 = pens[0]
		return Vector3(r.get_center().x, 0, r.get_center().y)
	if Game.flag("story_farm") == true:
		return STORY_PEN
	return Vector3(main.pen_rect.get_center().x, 0, main.pen_rect.get_center().y)


## Where a new pen could go: beside the last one, or Act 1's spot before there is any.
func _new_pen_point() -> Vector3:
	var pens: Array = main.wildlife.pens() if main.wildlife else []
	if pens.is_empty():
		return STORY_PEN if Game.flag("story_farm") == true else _pen_point()
	var r: Rect2 = pens[pens.size() - 1]
	return Vector3(r.end.x + 4.0, 0, r.get_center().y)


func _hero() -> Node3D:
	return main._walker()


func _hero_pos() -> Vector3:
	var h := _hero()
	return h.global_position if h else Vector3.ZERO


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The point an objective's target stands at now (Vector3, y 0), or null.
static func point_of(t: Variant) -> Variant:
	if t is Node3D:
		if not is_instance_valid(t):
			return null
		var p: Vector3 = (t as Node3D).global_position
		return Vector3(p.x, 0, p.z)
	if t is Vector3:
		return Vector3((t as Vector3).x, 0, (t as Vector3).z)
	if t is Vector2:
		return Vector3((t as Vector2).x, 0, (t as Vector2).y)
	return null


# --- every frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.hud == null or panel == null:
		return
	btn.visible = on and not main.hud.title_visible()
	if is_open() and (main.story.is_playing() or main.hud.title_visible()):
		close()
	if not on:
		panel.visible = false
		_show(false)
		return
	_t -= delta
	if _t <= 0.0:
		_t = LIST_EVERY
		_refresh()
	if is_open(): # the list as tall as its rows, up to most of the screen, then it scrolls
		var room: float = main.get_viewport().get_visible_rect().size.y - 200.0
		_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 40.0, maxf(120.0, room))
	_update_route(delta)


func _refresh() -> void:
	if main == null:
		return
	items = build_list()
	var id := tracked_id()
	if id != "" and id != "main" and tracked().is_empty():
		var was_main := id.begins_with("goal:") or id in ["story", "next", "wolves", "chapter"]
		if was_main:
			Game.flags["objective"] = "main" # that step is done: follow the next main one
		else:
			Game.flags.erase("objective")
	btn.text = ("Objectives  %d" % items.size()) if not items.is_empty() else "Objectives"
	btn.add_theme_color_override("font_color", BLUE.lightened(0.35) if tracked_id() != "" else TEXT)
	if is_open():
		_rebuild_rows()


func _rebuild_rows() -> void:
	var cur := tracked()
	var sig := str(cur.get("id", "")) + "#"
	for o in items:
		sig += "%s|%s|%s;" % [o["id"], o["text"], o["kind"]]
	if sig == _sig:
		_update_distances()
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	var hud: Node = main.hud
	for kind in ["main", "side"]:
		var these := items.filter(func(o): return str(o["kind"]) == kind)
		_list.add_child(hud._label("MAIN OBJECTIVES" if kind == "main" else "SIDE QUESTS", 13, GOLD))
		if these.is_empty():
			var none: Label = hud._label("Nothing just now." if kind == "main" else "None just now: make friends in town and they'll come.", 13, DIM)
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			none.custom_minimum_size = Vector2(PANEL_W - 10, 0)
			_list.add_child(none)
		for o in these:
			_list.add_child(_row(o, not cur.is_empty() and str(cur["id"]) == str(o["id"])))
	_update_distances()


func _row(o: Dictionary, on_it: bool) -> Button:
	var hud: Node = main.hud
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(PANEL_W - 10, 0)
	b.add_theme_font_size_override("font_size", 14)
	b.text = ("◆  " if on_it else "◇  ") + str(o["text"])
	b.set_meta("objective", str(o["id"]))
	b.set_meta("base", b.text)
	var fill := Color(0.12, 0.24, 0.42, 0.95) if on_it else Color(0.22, 0.17, 0.13, 0.9)
	var edge := BLUE if on_it else Color(0.45, 0.36, 0.26)
	b.add_theme_stylebox_override("normal", hud._sb_flat(fill, 8, edge, 8.0))
	b.add_theme_stylebox_override("hover", hud._sb_flat(fill.lightened(0.12), 8, BLUE.lightened(0.2), 8.0))
	b.add_theme_stylebox_override("pressed", hud._sb_flat(fill.darkened(0.1), 8, BLUE, 8.0))
	b.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0) if on_it else TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.9, 0.96, 1.0))
	b.tooltip_text = "Click to stop showing the way" if on_it else "Click to show the way"
	var id := str(o["id"])
	b.pressed.connect(func(): pick(id))
	return b


## Each row's distance, kept fresh without rebuilding the rows.
func _update_distances() -> void:
	var h := _hero_pos()
	for c in _list.get_children():
		if not c is Button or not (c as Button).has_meta("objective"):
			continue
		var o := _item(str(c.get_meta("objective")))
		var p: Variant = point_of(o.get("target"))
		var extra := ""
		if p != null:
			extra = "   · %d m" % roundi(_flat(p, h))
		elif str(o.get("detail", "")) != "":
			extra = "   · " + str(o["detail"])
		(c as Button).text = str(c.get_meta("base")) + extra


# --- the route, the marker and the map -------------------------------------------------------------

func _build_world() -> void:
	_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.name = "ObjectiveRoute"
	_line.mesh = _mesh
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = 40 # after the fog of war's quad (fog_of_war.gd draws first)
	_line.material_override = _mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.layers = FogOfWar.LAYER # the minimap's camera leaves it out and draws its own
	_line.custom_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 200, 2000))
	_line.visible = false
	main.add_child(_line)
	marker = Node3D.new()
	marker.name = "ObjectiveMarker"
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(BLUE.r, BLUE.g, BLUE.b, 0.85)
	ring_mat.no_depth_test = true
	ring_mat.render_priority = 41
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.74
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.scale = Vector3(1, 0.12, 1)
	ring.position.y = 0.1
	ring.name = "Ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	var bg := Gradient.new()
	bg.set_color(0, Color(0.35, 0.7, 1.0, 0.0))
	bg.set_color(1, Color(0.35, 0.7, 1.0, 0.55))
	var btex := GradientTexture2D.new()
	btex.gradient = bg
	btex.fill_from = Vector2(0, 0)
	btex.fill_to = Vector2(0, 1)
	btex.width = 4
	btex.height = 64
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_texture = btex
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.2
	bm.bottom_radius = 0.4
	bm.height = 9.0
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 4.5
	beam.name = "Beam"
	_beam = beam
	marker.add_child(beam)
	_icon = Sprite3D.new()
	_icon.name = "Icon"
	_icon.texture = ImageTexture.create_from_image(icon_image())
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.shaded = false
	_icon.fixed_size = true # the same size on screen near or far, so it can be found from across the map
	_icon.pixel_size = 0.0007
	_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_icon.transparent = true
	_icon.render_priority = 42
	_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_icon.position.y = 3.0
	marker.add_child(_icon)
	for c in marker.get_children():
		(c as VisualInstance3D).layers = FogOfWar.LAYER
	marker.visible = false
	main.add_child(marker)


## The blue icon: a round blue badge with a white rim and a white diamond.
static func icon_image() -> Image:
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	var c := Vector2(ICON_PX, ICON_PX) * 0.5
	var r := ICON_PX * 0.44
	for y in ICON_PX:
		for x in ICON_PX:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d < r + 3.0: # a soft dark halo so it reads over sky and snow
				col = Color(0.02, 0.06, 0.14, 0.45 * clampf((r + 3.0 - d) / 3.0, 0.0, 1.0))
			if d < r:
				var rim := clampf((r - d) / 1.5, 0.0, 1.0)
				col = Color(1, 1, 1, rim)
				if d < r - 5.0:
					var shade := 0.85 + 0.15 * (1.0 - (p.y / ICON_PX))
					col = Color(BLUE.r * shade, BLUE.g * shade, BLUE.b * shade, 1.0)
					var q := (p - c) / (r * 0.5)
					if absf(q.x) + absf(q.y) < 1.0: # the diamond
						col = Color(1, 1, 1, 1)
			img.set_pixel(x, y, col)
	return img


## Whether the way may show now.
func _may_show() -> bool:
	if main.title_on or main.story.is_playing() or main.cinema.active or main.god.active or int(main.mode) != 0:
		return false
	return tracked_id() != ""


func _show(on_it: bool) -> void:
	shown = on_it
	if _line:
		_line.visible = on_it and not drawn.is_empty()
	if marker:
		marker.visible = on_it and goal != null
	# the story's own gold marker stands on the same spot: one marker is enough
	var hide_gold: bool = on_it and goal != null and str(tracked().get("id", "")) == "story"
	if main.goal_marker == null:
		return
	if hide_gold and main.goal_marker.visible:
		main.goal_marker.visible = false
		_hid_gold = true
	elif not hide_gold and _hid_gold:
		_hid_gold = false
		var gp = Game.flag("goal_pos", null)
		var text := str(Game.flag("goal", ""))
		main.goal_marker.visible = text != "" and text != "false" and gp is Array


func _update_route(delta: float) -> void:
	var o := tracked()
	goal = point_of(o.get("target")) if not o.is_empty() else null
	if o.is_empty() or not _may_show():
		_show(false)
		return
	var hero := _hero()
	var hp := hero.global_position
	if goal == null:
		route = []
		drawn = []
		_show(true)
		return
	var g: Vector3 = goal
	# the marker
	var t: Variant = o.get("target")
	var tall := 2.6
	if t is Node3D and (t as Node3D).has_method("display_name"):
		tall = 3.0 # over a person's head and their star
	marker.global_position = Vector3(g.x, _ground_y(g.x, g.z), g.z)
	var ms := Time.get_ticks_msec() * 0.001
	_icon.position.y = tall + 0.12 * sin(ms * 2.6)
	var near := clampf((_flat(g, hp) - 2.5) / 8.0, 0.0, 1.0)
	_beam.transparency = 1.0 - near * (0.7 + 0.3 * sin(ms * 2.0))
	_beam.visible = near > 0.01
	# the route: worked out again when she has wandered off it, the target has moved or the grid changed
	_route_age += delta
	var off := _off_route(hp)
	# a long route costs tens of ms (the farm to the dunes about 80): a far target that moves a little
	# doesn't need a new one until she's nearer
	var moved := maxf(2.5, _flat(g, hp) * 0.15)
	if _route_to == Vector3.INF or _flat(g, _route_to) > moved or off > 3.0 or _route_stamp != int(main.grid_stamp) or _route_age > 30.0:
		var t0 := Time.get_ticks_usec()
		route = main._find_path(Vector3(hp.x, 0, hp.z), g)
		path_us = Time.get_ticks_usec() - t0
		_route_from = hp
		_route_to = g
		_route_stamp = int(main.grid_stamp)
		_route_age = 0.0
	_draw_t -= delta
	if _draw_t <= 0.0:
		_draw_t = DRAW_EVERY
		_draw_route(hp, g)
	_show(true)


## How far she is from the route she was given (m).
func _off_route(hp: Vector3) -> float:
	if route.is_empty():
		return 0.0 if _flat(hp, _route_from) < 3.0 else INF
	var best := _seg_dist(Vector2(hp.x, hp.z), Vector2(_route_from.x, _route_from.z), Vector2(route[0].x, route[0].z))
	for i in range(1, route.size()):
		best = minf(best, _seg_dist(Vector2(hp.x, hp.z), Vector2(route[i - 1].x, route[i - 1].z), Vector2(route[i].x, route[i].z)))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l := ab.length_squared()
	var k := 0.0 if l < 0.0001 else clampf((p - a).dot(ab) / l, 0.0, 1.0)
	return p.distance_to(a + ab * k)


## The ribbon from where she stands now along the rest of the route.
func _draw_route(hp: Vector3, g: Vector3) -> void:
	_mesh.clear_surfaces()
	drawn = []
	if _flat(hp, g) < ARRIVED:
		_line.visible = false
		return
	var pts: Array = [Vector3(hp.x, 0, hp.z)]
	if route.is_empty():
		_line.visible = false
		return
	# skip the corners she has already passed: start from the segment nearest her
	var all: Array = [Vector3(_route_from.x, 0, _route_from.z)]
	all.append_array(route)
	var k := 0
	var best := INF
	for i in range(1, all.size()):
		var d := _seg_dist(Vector2(hp.x, hp.z), Vector2(all[i - 1].x, all[i - 1].z), Vector2(all[i].x, all[i].z))
		if d < best:
			best = d
			k = i
	for i in range(k, all.size()):
		pts.append(all[i])
	# out to the point on the ground, then every STEP metres, standing on the ground
	var line: Array = []
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var n := maxi(1, ceili(_flat(a, b) / STEP))
		for j in n:
			line.append(a.lerp(b, float(j) / n))
	line.append(pts[pts.size() - 1])
	if line.size() < 2:
		_line.visible = false
		return
	var total := 0.0
	var dist: Array = [0.0]
	for i in range(1, line.size()):
		total += _flat(line[i - 1], line[i])
		dist.append(total)
	_mat.set_shader_parameter("total", total)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in line.size():
		var p: Vector3 = line[i]
		var dir: Vector3 = (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)])
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3.FORWARD
		var side := Vector3(-dir.z, 0, dir.x).normalized() * WIDTH * 0.5
		var y := _ground_y(p.x, p.z) + LIFT
		var at := Vector3(p.x, y, p.z)
		_mesh.surface_set_uv(Vector2(float(dist[i]), 0.0))
		_mesh.surface_add_vertex(at - side)
		_mesh.surface_set_uv(Vector2(float(dist[i]), 1.0))
		_mesh.surface_add_vertex(at + side)
		drawn.append(at)
	_mesh.surface_end()
	_line.visible = true


func _ground_y(x: float, z: float) -> float:
	var y := 0.0
	if main.regions != null and main.regions.has_method("relief"):
		y = maxf(0.0, float(main.regions.relief(x, z)))
	var h := _hero()
	if h and absf(h.global_position.y - y) > 0.08 and _flat(h.global_position, Vector3(x, 0, z)) < 8.0:
		y = h.global_position.y # on a floor above the ground (a house's, the café's loft)
	return y


## The minimap's copy (minimap.gd _draw): the route as a blue line and the target as the blue badge,
## pinned to the map's edge as an arrow when it's out of the map's span.
func draw_on_map(m) -> void:
	if not shown or goal == null:
		return
	var size: float = Minimap.SIZE
	if drawn.size() >= 2:
		var poly := PackedVector2Array()
		for p in drawn:
			poly.append(m.to_map(p))
		m.draw_polyline(poly, Color(BLUE_DARK, 0.8), 5.0, true)
		m.draw_polyline(poly, BLUE, 3.0, true)
	var tp: Vector2 = m.to_map(goal)
	var inner := Rect2(Vector2.ZERO, Vector2(size, size)).grow(-12.0)
	if inner.has_point(tp):
		m.draw_circle(tp, 8.5, Color(BLUE_DARK, 0.9))
		m.draw_circle(tp, 7.0, Color.WHITE)
		m.draw_circle(tp, 5.5, BLUE)
		var dia := PackedVector2Array([tp + Vector2(0, -3.2), tp + Vector2(3.2, 0), tp + Vector2(0, 3.2), tp + Vector2(-3.2, 0)])
		m.draw_colored_polygon(dia, Color.WHITE)
	else:
		var c := Vector2(size, size) * 0.5
		var d := (tp - c).normalized()
		var k := (size * 0.5 - 12.0) / maxf(absf(d.x), absf(d.y))
		var at := c + d * k
		var side := Vector2(-d.y, d.x)
		var tri := PackedVector2Array([at + d * 9.0, at - d * 5.0 + side * 7.0, at - d * 5.0 - side * 7.0])
		m.draw_colored_polygon(tri, BLUE)
		tri.append(tri[0])
		m.draw_polyline(tri, Color.WHITE, 1.5, true)
