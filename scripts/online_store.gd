extends Node
## Nora's online sweater store (Alex, 2026-11-16: "a computer ... as a high ticket purchase item. When
## computer is bought she can first person view the screen and scroll through 'orders' that she can
## fill. Orders request specific animal furs ... The orders are endless but order frequency increases
## by customer satisfaction (she has a star rating) ... how quickly she fills orders since request
## date. Longer time = lower rating out of 5. High star rating = more orders and potential for growth").
##
## The computer is a catalogue piece ("computer" in data/furniture.json; Catalog._computer is its
## stand-in until assets/props/computer.glb lands, and the view only needs a part named "screen").
## "Use the computer…" stands her in front of it in first person (main.fps.locked, as wardrobe_view.gd
## and barista.gd do) with the store's page drawn over the screen. Up and Down (or W and S, or the
## wheel) pick an order, Enter (or E, Space, or its Send button) sends the plainest sweater in her bag
## that will do, Esc leaves.
##
## Orders run on the game's clock in hours ((day - 1) * 24 + hour), so they keep through saves and
## sleep: while a computer stands in her house, a new one comes every interval_hours (shorter the better
## her rating) up to max_open at once, and each wants a sweater knitted with one wild fibre, sometimes
## with more stars than the fibre gives by itself. Which sweater was knitted with what is
## Game.sweater_fibres. Filling one scores it 5 if it's within the order's grace, falling to 1 at its
## expiry; an order left to expire scores expired_score. The rating is the average of the last
## `window` scores. Payment comes with the morning post: the coins arrive on the next Game.day_started.
## Every number is in data/store_orders.json. The state is Game.flags["store"]:
##   orders: [{id, fibre, tier, stars, pay, placed (game hour), who, note}], next_at (game hour),
##   scores: [float], pending: [{id, coins, who, fibre}], seq, filled, expired, earned, last_score.
## Every word on the page is a draft until Alex approves it.

const Sweaters = preload("res://scripts/sweaters.gd")
const Data = preload("res://scripts/data.gd")
const FirstPerson = preload("res://scripts/first_person.gd")
const Catalog = preload("res://scripts/catalog.gd")
const EmpireGoals = preload("res://scripts/empire_goals.gd")

const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const STAND := 0.28 # how far in front of the desk she stands
const STEP_BACK := 0.8 # where she stands when she leaves it: clear of the desk on the walking grid
const FOV := 50.0 # narrower than first person's own, so the screen fills most of the view
const SHOP_NAME := "Nora's Knits" # draft

var main: Node
var data: Dictionary = {}
var active := false
var selected := 0
var piece: Node3D
var on := true # the autotest turns the clock off while it sets things up itself
var _screen: Node3D
var _was_fps := false
var _flat := false # first person couldn't start: the page is shown on its own
var _cam := {}
var _fps_view := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _page: PanelContainer
var _rating: Label
var _sub: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _foot: Label
var _rows: Array = [] # the order rows, in the list's order
var _sig := ""


func _ready() -> void:
	data = Data.load_json("store_orders")
	Game.day_started.connect(_on_day_started)
	_build_page()


# --- the numbers ------------------------------------------------------------------------------

## The store's saved state, made on first use.
func state() -> Dictionary:
	var s: Variant = Game.flags.get("store", null)
	if not s is Dictionary:
		s = {}
		Game.flags["store"] = s
	return s


func started() -> bool:
	return state().has("next_at")


## Game hours since the first morning: what orders are stamped with.
static func now_h() -> float:
	return float(Game.day - 1) * 24.0 + Game.hour


## True while a computer stands among her furniture.
func owns() -> bool:
	if main == null:
		return false
	for f in main.furniture:
		if is_instance_valid(f) and str(f.item_id) == "computer":
			return true
	return false


func computer() -> Node3D:
	for f in main.furniture:
		if is_instance_valid(f) and str(f.item_id) == "computer":
			return f
	return null


func orders() -> Array:
	var o: Variant = state().get("orders", [])
	return o if o is Array else []


func pending() -> Array:
	var p: Variant = state().get("pending", [])
	return p if p is Array else []


func scores() -> Array:
	var sc: Variant = state().get("scores", null)
	return sc if sc is Array else [float(data.get("start_rating", 3.0))]


## Her star rating, out of 5: the average of the last `window` scores.
func rating() -> float:
	var sc := scores()
	if sc.is_empty():
		return float(data.get("start_rating", 3.0))
	var total := 0.0
	for x in sc:
		total += float(x)
	return clampf(total / float(sc.size()), 1.0, 5.0)


func reviews() -> int:
	return int(state().get("filled", 0)) + int(state().get("expired", 0))


func _add_score(x: float) -> void:
	var sc := scores().duplicate()
	sc.append(clampf(x, 0.0, 5.0))
	var w := int(data.get("window", 12))
	while sc.size() > w:
		sc.remove_at(0)
	state()["scores"] = sc


## 0 at a 1-star rating, 1 at 5 stars.
func _t() -> float:
	return clampf((rating() - 1.0) / 4.0, 0.0, 1.0)


func _between(key: String, a0: float, a1: float) -> float:
	var a: Array = data.get(key, [a0, a1])
	return lerpf(float(a[0]), float(a[1]), _t())


## Game hours between new orders at her rating now.
func interval() -> float:
	return maxf(0.5, _between("interval_hours", 14.0, 4.0))


func max_open() -> int:
	return maxi(1, int(round(_between("max_open", 3.0, 8.0))))


func expire_hours(o: Dictionary) -> float:
	return float((data.get("expire_hours", {}) as Dictionary).get(str(o.get("tier", "common")), 48.0))


func hours_left(o: Dictionary) -> float:
	return float(o.get("placed", 0.0)) + expire_hours(o) - now_h()


func age(o: Dictionary) -> float:
	return now_h() - float(o.get("placed", 0.0))


## The score filling `o` now would give: 5 within its grace, then down in a line to 1 at expiry.
func score_for(o: Dictionary) -> float:
	var exp_h := expire_hours(o)
	var g := exp_h * float(data.get("grace", 0.25))
	var a := age(o)
	if a <= g:
		return 5.0
	return 5.0 - 4.0 * clampf((a - g) / maxf(0.01, exp_h - g), 0.0, 1.0)


## The least rarity (1..5) a sweater needs for this order: the fibre's own floor, or what its stars ask.
func least_rarity(o: Dictionary) -> int:
	var by_stars: int = [1, 3, 4, 5][clampi(int(o.get("stars", 1)), 1, 4) - 1]
	return maxi(main.wildlife.knit_floor(str(o["fibre"])), by_stars)


## The plainest sweater in her bag that will do for `o` (its index in Game.sweaters), or -1.
func sweater_for(o: Dictionary) -> int:
	var best := -1
	var n := mini(Game.sweaters.size(), Game.sweater_fibres.size())
	for i in n:
		var q := int(Game.sweaters[i])
		if str(Game.sweater_fibres[i]) == str(o["fibre"]) and Sweaters.stars_for(q) >= int(o.get("stars", 1)):
			if best < 0 or q < int(Game.sweaters[best]):
				best = i
	return best


## What sending a sweater of `rarity` for `o` pays: its price, and a tenth more a grade above the least.
func pay_for(o: Dictionary, rarity: int) -> int:
	var extra := maxi(0, rarity - least_rarity(o))
	return int(round(float(o["pay"]) * (1.0 + float(data.get("bonus_per_grade", 0.1)) * extra)))


func coming() -> int:
	var n := 0
	for p in pending():
		n += int(p.get("coins", 0))
	return n


# --- the clock --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if main == null:
		return
	if on and not main.title_on:
		update()
	if active:
		if main.story.is_playing() or main.sleeping:
			close()
			return
		_steer()
		_refresh()


## New orders in, old ones out. Catches up after sleep: what came in overnight is waiting at dawn.
func update() -> void:
	if not owns():
		return
	var s := state()
	var now := now_h()
	if not s.has("next_at"):
		s["orders"] = []
		s["scores"] = [float(data.get("start_rating", 3.0))]
		s["pending"] = []
		s["seq"] = int(s.get("seq", 0))
		s["filled"] = 0
		s["expired"] = 0
		s["earned"] = 0
		for i in int(data.get("seed_orders", 2)):
			place_order(now)
		s["next_at"] = now + interval()
	_expire(now)
	# catch up a night at most: a computer sold and bought back days later mustn't come back to a
	# pile of orders dated days ago that all expire at once
	var earliest := now - float(data.get("catch_up_hours", 12.0))
	if float(s["next_at"]) < earliest:
		s["next_at"] = earliest
	var guard := 0
	while float(s["next_at"]) <= now and guard < 64:
		guard += 1
		var at := float(s["next_at"])
		if orders().size() < max_open():
			place_order(at)
		s["next_at"] = at + interval()
	if float(s["next_at"]) <= now:
		s["next_at"] = now + interval()
	_expire(now)


## A new order, placed at game hour `at` (now if not given). Returns it.
func place_order(at := -1.0, fibre := "", stars := 0) -> Dictionary:
	var s := state()
	if at < 0.0:
		at = now_h()
	var seq := int(s.get("seq", 0)) + 1
	s["seq"] = seq
	_rng.seed = hash("knitting-empire-store-%d" % seq)
	var fibres: Dictionary = main.wildlife.fibres()
	var tier := ""
	if fibre == "" or not fibres.has(fibre):
		tier = _pick_tier()
		var pool: Array = fibres.keys().filter(func(k): return str(fibres[k].get("tier", "")) == tier)
		if pool.is_empty():
			pool = fibres.keys()
		pool.sort()
		fibre = str(pool[_rng.randi() % pool.size()])
	tier = str(fibres[fibre].get("tier", "common"))
	var own := Sweaters.stars_for(main.wildlife.knit_floor(fibre))
	var roll := _rng.randf()
	if stars <= 0:
		stars = own + 1 if own < 4 and roll < float(data.get("stars_chance", 0.3)) else own
	stars = clampi(maxi(stars, own), 1, 4)
	var pay := float((data.get("pay", {}) as Dictionary).get(tier, 120))
	if stars > own:
		pay *= 1.0 + float(data.get("stars_extra_pay", 0.2))
	var names: Array = data.get("customers", ["A customer"])
	var notes: Array = data.get("notes", [""])
	var o := {"id": seq, "fibre": fibre, "tier": tier, "stars": stars, "pay": int(round(pay / 5.0) * 5.0),
		"placed": at, "who": str(names[_rng.randi() % names.size()]), "note": str(notes[_rng.randi() % notes.size()])}
	var list := orders().duplicate()
	list.append(o)
	s["orders"] = list
	return o


func _pick_tier() -> String:
	var w: Dictionary = data.get("tier_weights", {"common": [1.0, 1.0]})
	var total := 0.0
	var ws := {}
	for k in w:
		var a: Array = w[k]
		ws[k] = maxf(0.0, lerpf(float(a[0]), float(a[1]), _t()))
		total += float(ws[k])
	var r := _rng.randf() * total
	for k in ws:
		r -= float(ws[k])
		if r <= 0.0:
			return str(k)
	return "common"


func _expire(now: float) -> void:
	var s := state()
	var keep := []
	var gone := 0
	for o in orders():
		if float(o.get("placed", 0.0)) + expire_hours(o) <= now:
			gone += 1
			_add_score(float(data.get("expired_score", 1.0)))
		else:
			keep.append(o)
	if gone > 0:
		s["orders"] = keep
		s["expired"] = int(s.get("expired", 0)) + gone
		main.hud.show_toast("%s online order%s ran out before you sent %s. Your rating is %.1f." % ["An" if gone == 1 else str(gone), "" if gone == 1 else "s", "it" if gone == 1 else "them", rating()])


## Sends the plainest sweater that will do for the k-th order. The rating takes its score now; the
## coins come with the morning post. False if she has nothing that will do.
func fill(k: int) -> bool:
	var list := orders()
	if k < 0 or k >= list.size():
		return false
	var o: Dictionary = list[k]
	var i := sweater_for(o)
	if i < 0:
		return false
	var score := score_for(o)
	var sw := Game.remove_sweater(i)
	var coins := pay_for(o, int(sw.get("rarity", 1)))
	var s := state()
	_add_score(score)
	s["last_score"] = score
	s["filled"] = int(s.get("filled", 0)) + 1
	var pend := pending().duplicate()
	pend.append({"id": int(o["id"]), "coins": coins, "who": str(o["who"]), "fibre": str(o["fibre"])})
	s["pending"] = pend
	var keep := list.duplicate()
	keep.remove_at(k)
	s["orders"] = keep
	selected = clampi(selected, 0, maxi(0, keep.size() - 1))
	main.hud.click("ui_open")
	main.hud.show_toast("Packed for %s: a %s %s sweater. %dc comes with the morning post. (%s)" % [o["who"], RARITY[clampi(int(sw.get("rarity", 1)), 1, 5) - 1], main.wildlife.item_name(str(o["fibre"])).to_lower(), coins, _stars_text(score)])
	_sig = ""
	return true


## The morning post brings what yesterday's orders paid.
func _on_day_started(_day: int) -> void:
	var total := coming()
	if total <= 0:
		return
	var n := pending().size()
	var s := state()
	Game.coins += total
	EmpireGoals.took("store", total) # the morning it arrives
	s["earned"] = int(s.get("earned", 0)) + total
	s["pending"] = []
	if main != null:
		main.audio.play("coins", -4.0)
		main.hud.show_toast("The morning post: %dc from your online store for %d order%s." % [total, n, "" if n == 1 else "s"])


# --- the screen --------------------------------------------------------------------------------

## "Use the computer…": stands her at the desk in first person, looking at the screen, with the page on it.
func open(at: Node3D) -> void:
	if active or at == null:
		return
	piece = at
	update()
	_screen = at.find_child("screen", true, false) as Node3D
	_was_fps = main.fps.active
	_flat = _screen == null or (not _was_fps and not main.fps.can_enter())
	_cam = {"yaw": main.cam_yaw, "goal": main.cam_yaw_goal, "target": main.cam_target, "dist": main.cam_dist}
	_fps_view = Vector2(main.fps.yaw, main.fps.pitch)
	var p: Node3D = main.player
	p.cancel_activity()
	p.path.clear()
	p._on_arrive = Callable()
	main.hud.hide_menu()
	if not _flat:
		var size: Vector2 = Catalog.ITEMS.get("computer", {}).get("size", Vector2(1.3, 0.7)) # Data.furniture() makes it a Vector2
		var depth := size.y
		var spot: Vector3 = at.to_global(Vector3(0, 0, depth * 0.5 + STAND))
		p.position = Vector3(spot.x, p.position.y, spot.z)
		var front: Vector3 = at.global_transform.basis * Vector3.BACK
		front.y = 0.0
		var face: float = atan2(front.x, front.z) if front.length() > 0.001 else at.global_rotation.y
		p.rotation.y = face + PI
		if not _was_fps:
			main.fps.enter()
		main.fps.locked = true
		main.fps.yaw = face
		main.fps.pitch = deg_to_rad(-20.0)
		main.cam.fov = FOV
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	selected = clampi(selected, 0, maxi(0, orders().size() - 1))
	_sig = ""
	_layer.visible = true
	_refresh()
	main.hud.click("ui_open")


func close() -> void:
	if not active:
		return
	active = false
	_layer.visible = false
	if _flat:
		return
	if is_instance_valid(piece): # a step back from the desk, where she can walk again
		var size: Vector2 = Catalog.ITEMS.get("computer", {}).get("size", Vector2(1.3, 0.7))
		var out: Vector3 = piece.to_global(Vector3(0, 0, size.y * 0.5 + STEP_BACK))
		main.player.position = Vector3(out.x, main.player.position.y, out.z)
	main.fps.locked = false
	main.cam.fov = FirstPerson.FOV
	if not _was_fps:
		main.fps.leave()
		main.cam_yaw = float(_cam["yaw"])
		main.cam_yaw_goal = float(_cam["goal"])
		main.cam_target = _cam["target"]
		main.cam_dist = float(_cam["dist"])
		main._update_camera(1.0)
	else:
		main.fps.yaw = _fps_view.x
		main.fps.pitch = _fps_view.y
		if main._autotest_dir == "":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Keeps her eyes on the middle of the screen (the camera is at her eyes; the view is ours while locked).
func _steer() -> void:
	if _flat or not is_instance_valid(_screen) or not main.fps.active:
		return
	var eye: Vector3 = main.cam.global_position
	var to: Vector3 = screen_centre() - eye
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	main.fps.yaw = atan2(-to.x, -to.z)
	main.fps.pitch = atan2(to.y, flat)


## The middle of the screen's glass in the world: its mesh's bounds, since a model's "screen" node
## may have its origin anywhere (the Tripo computer's sits at the model's foot).
func screen_centre() -> Vector3:
	var mi := _screen_mesh()
	if mi == null:
		return _screen.global_position
	return mi.global_transform * mi.get_aabb().get_center()


func _screen_mesh() -> MeshInstance3D:
	if not is_instance_valid(_screen):
		return null
	if _screen is MeshInstance3D:
		return _screen as MeshInstance3D
	return _screen.find_child("*", true, false) as MeshInstance3D


## Where the screen is in the view, or a centred page if it isn't (or is too small to read).
func screen_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	# the HUD's free middle: clear of the need bars, the minimap, the toasts and the hotbar
	var free := Rect2(vp * Vector2(0.135, 0.14), vp * Vector2(0.72, 0.775)) # fractions: the window may be scaled
	var fallback := free
	var mi: MeshInstance3D = null if _flat else _screen_mesh()
	if mi == null:
		return fallback
	var box := mi.get_aabb()
	var r := Rect2()
	var first := true
	for i in 8:
		var w: Vector3 = mi.global_transform * box.get_endpoint(i)
		if main.cam.is_position_behind(w):
			return fallback
		var sp: Vector2 = main.cam.unproject_position(w)
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	r = r.intersection(free)
	if r.size.x < 480.0 or r.size.y < 300.0:
		return fallback
	return r.grow(-6.0)


func handle_key(kc: Key) -> bool:
	if not active:
		return false
	match kc:
		KEY_ESCAPE:
			close()
		KEY_UP, KEY_W:
			select(selected - 1)
		KEY_DOWN, KEY_S:
			select(selected + 1)
		KEY_PAGEUP:
			select(selected - 3)
		KEY_PAGEDOWN:
			select(selected + 3)
		KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE:
			send_selected()
		_:
			return kc in [KEY_A, KEY_D, KEY_V, KEY_P, KEY_TAB, KEY_B, KEY_I]
	return true


func handle_mouse(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(selected - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(selected + 1)


func select(i: int) -> void:
	var n := orders().size()
	selected = clampi(i, 0, maxi(0, n - 1))
	_sig = ""
	_refresh()


func send_selected() -> bool:
	if fill(selected):
		_refresh()
		return true
	main.hud.click("ui_click")
	return false


# --- the page ----------------------------------------------------------------------------------

const PAPER := Color(0.99, 0.97, 0.93)
const INK := Color(0.2, 0.15, 0.12)
const SOFT := Color(0.45, 0.38, 0.33)
const ACCENT := Color(0.89, 0.45, 0.2)
const GOOD := Color(0.24, 0.55, 0.3)


func _build_page() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	_layer.visible = false
	add_child(_layer)
	_page = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color(0.25, 0.22, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 8
	_page.add_theme_stylebox_override("panel", sb)
	_layer.add_child(_page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_page.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(head, 22, ACCENT)
	title.text = SHOP_NAME
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rating = _label(head, 17, INK)
	_rating.autowrap_mode = TextServer.AUTOWRAP_OFF
	_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sub = _label(col, 13, SOFT)
	var line := ColorRect.new()
	line.color = Color(0.89, 0.45, 0.2, 0.5)
	line.custom_minimum_size = Vector2(0, 2)
	col.add_child(line)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_foot = _label(col, 12, SOFT)
	_foot.text = "↑ ↓ choose an order   ·   Enter send   ·   Esc leave the computer" # draft


func _label(parent: Node, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func _stars_text(r: float) -> String:
	var n := clampi(int(round(r)), 0, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


static func _hours_text(h: float) -> String:
	if h < 1.0:
		return "just now" if h >= 0.0 else "now"
	if h < 24.0:
		return "%d h" % int(h)
	return "%d d %d h" % [int(h / 24.0), int(fmod(h, 24.0))]


func _refresh() -> void:
	var r := screen_rect()
	_page.position = r.position
	_page.size = r.size
	var list := orders()
	var sig := "%s|%d|%d|%d" % [str(list.map(func(o): return o["id"])), selected, int(now_h() * 4.0), Game.sweaters.size()]
	if sig == _sig:
		return
	_sig = sig
	_rating.text = "%s  %.1f  (%d review%s)" % [_stars_text(rating()), rating(), reviews(), "" if reviews() == 1 else "s"]
	var next_in := float(state().get("next_at", now_h())) - now_h()
	var sub := "Open orders: %d of %d  ·  next order in about %s" % [list.size(), max_open(), _hours_text(maxf(0.0, next_in))]
	if coming() > 0:
		sub += "  ·  coming in the morning post: %dc" % coming()
	_sub.text = sub
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	if list.is_empty():
		var l := _label(_list, 15, SOFT)
		l.text = "No orders right now. New ones come in about every %s; a better rating brings them sooner." % _hours_text(interval())
	for k in list.size():
		_rows.append(_row(k, list[k]))
	if selected < _rows.size():
		_scroll.ensure_control_visible.call_deferred(_rows[selected])


func _row(k: int, o: Dictionary) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var on_it := k == selected
	sb.bg_color = Color(1.0, 0.92, 0.82) if on_it else Color(0.96, 0.93, 0.88)
	sb.border_color = ACCENT if on_it else Color(0.85, 0.8, 0.74)
	sb.set_border_width_all(2 if on_it else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	_list.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 0)
	swatch.color = Color.html(str(main.wildlife.fibre_info(str(o["fibre"])).get("color", "#a08060")))
	h.add_child(swatch)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	h.add_child(col)
	var fname: String = main.wildlife.item_name(str(o["fibre"]))
	var head := _label(col, 16, INK)
	head.text = "A sweater of %s  ·  %s or better" % [fname.to_lower(), "★".repeat(int(o["stars"]))]
	var left := hours_left(o)
	var meta := _label(col, 12, SOFT if left > expire_hours(o) * 0.25 else Color(0.75, 0.25, 0.18))
	meta.text = "%s  ·  ordered %s ago  ·  %s left  ·  \"%s\"" % [o["who"], _hours_text(age(o)), _hours_text(maxf(0.0, left)), o["note"]]
	var i := sweater_for(o)
	var have := _label(col, 13, GOOD if i >= 0 else SOFT)
	if i >= 0:
		have.text = "In your bag: a %s %s sweater  ·  sending it now scores %s" % [RARITY[clampi(int(Game.sweaters[i]), 1, 5) - 1], fname.to_lower(), _stars_text(score_for(o))]
	else:
		have.text = "Knit one with %s first (%s or better)." % [fname.to_lower(), RARITY[least_rarity(o) - 1]]
	var right := VBoxContainer.new()
	h.add_child(right)
	var price := _label(right, 18, ACCENT)
	price.text = "%dc" % (pay_for(o, int(Game.sweaters[i])) if i >= 0 else int(o["pay"]))
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var b := Button.new()
	b.text = "Send"
	b.disabled = i < 0
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		selected = k
		send_selected())
	right.add_child(b)
	return box
