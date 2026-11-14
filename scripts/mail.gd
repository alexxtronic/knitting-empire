## The post (Alex, 2026-11-12: a core mechanic). Barbara's nine o'clock round (main.gd
## _update_post) calls at Nora's mailbox by the porch: she leaves what's due (data/mail.json) and
## takes any sweater Nora has put out for a customer. Nora takes the letters out and reads them in
## the letters panel (scripts/letters_panel.gd); coins or things enclosed are hers when she first
## reads one. Sweater orders: a customer writes, she posts a sweater of the stars they asked for
## from the mailbox, Barbara takes it, and the next morning's post brings the payment.
##
## Everything is kept in Game.flags["mail"], so it saves with the game:
##   "box"    letters waiting in the mailbox (each a whole letter Dictionary, see letter())
##   "got"    letters she has taken out, oldest first, each with "read"
##   "orders" order id -> {"state": "open" | "posted" | "sent" | "paid", "stars", "pay", "from",
##            "place", "thanks", "rarity" (the sweater posted), "sent" (the day Barbara took it)}
##   "sent"   letter id -> the day it was delivered (for "after")
##   "n_orders", "next_order"   how many orders have come, and the day the next one may
extends Node

const Catalog = preload("res://scripts/catalog.gd")
const Data = preload("res://scripts/data.gd")

const RARITY := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const STOP_AHEAD := 0.75 # m in front of the box: where Barbara stands to post
const MODEL := "res://assets/props/mailbox.glb"
const SIZE := Vector2(0.72, 0.58) # its footprint, width (x) by depth (z), over the feet

var main: Node
var box: Node3D # the mailbox by the porch (a MailBox); the world editor can move it
var _flag: Node3D # its red flag: up while there's post in it or a sweater going out
var _told_day := -1 # the day we last told her there's post waiting
var _defs := {}


func _ready() -> void:
	_defs = Data.load_json("mail")


## The mail's state in the save. Made on first use.
func state() -> Dictionary:
	var m: Dictionary = Game.flags.get("mail", {})
	if m.is_empty():
		m = {"box": [], "got": [], "orders": {}, "sent": {}, "n_orders": 0, "next_order": 0}
		Game.flags["mail"] = m
	return m


func letters_in_box() -> Array:
	return state()["box"]


func letters() -> Array:
	return state()["got"]


func unread() -> int:
	var n := 0
	for l in letters():
		if not bool(l.get("read", false)):
			n += 1
	return n


func orders() -> Dictionary:
	return state()["orders"]


## The orders she hasn't sent a sweater for yet, oldest first: [id, order].
func open_orders() -> Array:
	var out: Array = []
	for id in orders():
		var o: Dictionary = orders()[id]
		if str(o["state"]) == "open":
			out.append([id, o])
	return out


# --- the mailbox ------------------------------------------------------------------------

## Builds the mailbox at `pos`, its door toward `yaw` (radians; 0 faces +z): the blue post box
## (assets/props/mailbox.glb, art/world_assets/mailbox) with a red flag on its right side.
func build_box(root: Node3D, pos: Vector3, yaw: float) -> Node3D:
	box = MailBox.new()
	box.mail = self
	box.name = "Mailbox"
	box.position = pos
	box.rotation.y = yaw
	root.add_child(box)
	var packed := load(MODEL) as PackedScene
	if packed != null:
		box.add_child(packed.instantiate())
	else: # not imported yet: a plain blue box stands in, so the game still starts
		push_warning("mail: %s is missing; import the assets" % MODEL)
		Catalog.box(box, Vector3(0.46, 0.9, 0.44), Vector3(0, 0.7, 0), Color(0.23, 0.36, 0.6))
	# the flag pivots on the right-hand side between the ribs, lying along the box when down
	_flag = Node3D.new()
	_flag.position = Vector3(0.24, 0.70, -0.13)
	box.add_child(_flag)
	Catalog.box(_flag, Vector3(0.014, 0.025, 0.24), Vector3(0, 0, 0.12), Color(0.75, 0.13, 0.11))
	Catalog.box(_flag, Vector3(0.014, 0.09, 0.08), Vector3(0, 0.03, 0.22), Color(0.80, 0.15, 0.12))
	box.add_hitbox(Vector3(SIZE.x, 1.2, SIZE.y))
	update_flag()
	return box


## Up while there's post for her in the box or a sweater waiting for Barbara.
func flag_up() -> bool:
	return not letters_in_box().is_empty() or _has_posted()


func update_flag() -> void:
	if _flag:
		_flag.rotation.x = -PI * 0.5 if flag_up() else 0.0


## Where Barbara stands to put the post in: just in front of the box's door.
func stop_point() -> Vector3:
	if box == null or not is_instance_valid(box):
		return Vector3(10.6, 0, 3.0)
	var p: Vector3 = box.global_transform * Vector3(0, 0, STOP_AHEAD)
	return Vector3(p.x, 0, p.z)


# --- what Barbara brings ----------------------------------------------------------------

## Barbara at the mailbox on her round: she leaves what's due and takes what's going out.
## Returns how many letters she left.
func post_call() -> int:
	var m := state()
	for id in orders():
		var o: Dictionary = orders()[id]
		if str(o["state"]) == "posted":
			o["state"] = "sent"
			o["sent"] = Game.day
	var due := due_letters()
	for l in due:
		m["box"].append(l)
		m["sent"][str(l["id"])] = Game.day
		if l.has("order"):
			var oid := str(l["order"])
			if str(l.get("kind", "")) == "order":
				orders()[oid] = {"state": "open", "stars": int(l["stars"]), "pay": int(l["pay"]), "from": l["from"],
					"place": l["place"], "thanks": l.get("thanks", ""), "rarity": 0, "sent": 0}
			elif orders().has(oid):
				orders()[oid]["state"] = "paid"
	update_flag()
	return due.size()


## The letters the post brings today: one-off letters whose day has come, payments for the
## sweaters Barbara took before today, and a new order if one is due.
func due_letters() -> Array:
	var m := state()
	var out: Array = []
	for d in _defs.get("letters", []):
		var id := str(d["id"])
		if m["sent"].has(id) or not _ready_today(d):
			continue
		out.append(letter(d))
	for oid in orders():
		var o: Dictionary = orders()[oid]
		if str(o["state"]) == "sent" and int(o["sent"]) < Game.day:
			out.append(_payment(oid, o))
	var od: Dictionary = _defs.get("orders", {})
	var customers: Array = od.get("customers", [])
	if not customers.is_empty() and Game.day >= int(od.get("start_day", 1)) and Game.day >= int(m["next_order"]) \
			and _needs_met(str(od.get("needs", ""))) and open_orders().size() < int(od.get("max_open", 2)):
		var n := int(m["n_orders"])
		var c: Dictionary = customers[n % customers.size()]
		m["n_orders"] = n + 1
		m["next_order"] = Game.day + int(od.get("every", 3))
		var l := letter(c)
		l["id"] = "order_%d" % (n + 1)
		l["kind"] = "order"
		l["order"] = l["id"]
		l["stars"] = int(c.get("stars", 1))
		l["pay"] = int(c.get("pay", 150))
		l["thanks"] = str(c.get("thanks", ""))
		l["body"] = str(l["body"]).replace("{pay}", str(l["pay"]))
		out.append(l)
	return out


func _ready_today(d: Dictionary) -> bool:
	if Game.day < int(d.get("day", 1)) or not _needs_met(str(d.get("needs", ""))):
		return false
	if d.has("after"):
		var sent: Dictionary = state()["sent"]
		var a := str(d["after"])
		return sent.has(a) and Game.day >= int(sent[a]) + int(d.get("days", 1))
	return true


## A story flag a letter waits for. Act 1's flags count as set on a farm that skipped Act 1
## (old saves and the sandbox), or nothing would ever come there.
func _needs_met(f: String) -> bool:
	if f == "" or Game.flag(f) == true:
		return true
	return f.begins_with("act1") and not (main and main.homestead and main.homestead.story_farm())


## A letter as it's kept in the save: everything it says, so later edits to data/mail.json
## don't change letters she already has.
func letter(d: Dictionary) -> Dictionary:
	return {"id": str(d.get("id", "")), "from": str(d.get("from", "")), "place": str(d.get("place", "")),
		"subject": str(d.get("subject", "")), "body": str(d.get("body", "")).replace("{name}", "Nora"),
		"coins": int(d.get("coins", 0)), "item": str(d.get("item", "")), "item_n": int(d.get("item_n", 1)),
		"day": Game.day, "read": false}


func _payment(oid: String, o: Dictionary) -> Dictionary:
	var tip: int = int(_defs.get("orders", {}).get("tip_per_star", 0))
	var extra := maxi(0, int(o["rarity"]) - int(o["stars"])) * tip
	var l := letter({"id": "paid_" + oid, "from": o["from"], "place": o["place"], "subject": "Payment enclosed",
		"body": o["thanks"], "coins": int(o["pay"]) + extra})
	l["kind"] = "payment"
	l["order"] = oid
	return l


# --- Nora at the mailbox ------------------------------------------------------------------

## She takes the post out of the box. Returns the letters taken, oldest first.
func take_post() -> Array:
	var m := state()
	var taken: Array = m["box"].duplicate()
	m["got"].append_array(taken)
	m["box"] = []
	update_flag()
	return taken


## She opens a letter: anything enclosed is hers, the first time. Returns what was enclosed, for
## the panel to show ("" if nothing).
func read(l: Dictionary) -> String:
	if bool(l.get("read", false)):
		return ""
	l["read"] = true
	var got: Array = []
	if int(l.get("coins", 0)) > 0:
		Game.coins += int(l["coins"])
		got.append("%dc" % int(l["coins"]))
	if str(l.get("item", "")) != "":
		Game.add_item(str(l["item"]), int(l.get("item_n", 1)))
		got.append("%d %s" % [int(l.get("item_n", 1)), str(l["item"])])
	if got.is_empty():
		return ""
	if main and main.audio and int(l.get("coins", 0)) <= 0: # coins enclosed: the HUD's pop-up rings them in
		main.audio.play("journal", -6.0)
	return "Enclosed: " + " and ".join(got)


## The sweater she'd send for an order: the plainest she carries that has the stars asked for
## (index into Game.sweaters), or -1.
func sweater_for(o: Dictionary) -> int:
	var best := -1
	for i in Game.sweaters.size():
		var r := int(Game.sweaters[i])
		if r >= int(o["stars"]) and (best < 0 or r < int(Game.sweaters[best])):
			best = i
	return best


## She puts a sweater in the mailbox for this order; Barbara takes it on her next round.
func post_sweater(oid: String) -> bool:
	var o: Dictionary = orders().get(oid, {})
	if o.is_empty() or str(o["state"]) != "open":
		return false
	var i := sweater_for(o)
	if i < 0:
		return false
	o["rarity"] = int(Game.remove_sweater(i).get("rarity", 0))
	o["state"] = "posted"
	update_flag()
	return true


func _has_posted() -> bool:
	for id in orders():
		if str(orders()[id]["state"]) == "posted":
			return true
	return false


## What the mailbox offers when she clicks it.
func actions() -> Array:
	var acts: Array = []
	var n := letters_in_box().size()
	if n > 0:
		acts.append({"id": "take", "label": "Take the post  (%d %s)" % [n, "letter" if n == 1 else "letters"], "enabled": true})
	for e in open_orders():
		var o: Dictionary = e[1]
		var a := {"id": "post:" + str(e[0]), "label": "Post a sweater to %s  (%s or better, %dc)" % [o["from"], RARITY[clampi(int(o["stars"]), 1, 5) - 1], int(o["pay"])],
			"enabled": sweater_for(o) >= 0}
		if not a["enabled"]:
			a["hint"] = "%s or better, %dc: none in your bag" % [RARITY[clampi(int(o["stars"]), 1, 5) - 1], int(o["pay"])]
		acts.append(a)
	for id in orders():
		if str(orders()[id]["state"]) == "posted":
			acts.append({"id": "noop", "label": "%s's sweater waits for Barbara" % orders()[id]["from"], "enabled": false})
	if not letters().is_empty():
		acts.append({"id": "letters", "label": "Read your letters", "enabled": true})
	if acts.is_empty():
		acts.append({"id": "noop", "label": "Empty. Barbara comes at nine.", "enabled": false})
	return acts


func do_action(id: String) -> void:
	if id == "take":
		var taken := take_post()
		if main and main.audio:
			main.audio.play("journal", -8.0)
		if not taken.is_empty():
			main.hud.letters.open(str(taken[0]["id"]))
	elif id == "letters":
		main.hud.letters.open()
	elif id.begins_with("post:"):
		var oid := id.substr(5)
		if post_sweater(oid):
			main.hud.show_toast("The sweater's in the box, flag up. Barbara takes it on her round.")


## Barbara told her herself (she was near): no need to say it again today.
func told_today() -> void:
	_told_day = Game.day


## Twice a second: once a day, if there's post waiting when she's home on the farm, say so.
func update() -> void:
	if letters_in_box().is_empty() or _told_day == Game.day or main == null:
		return
	if not main.LOT.has_point(Vector2(main.player.position.x, main.player.position.z)) or main.story.is_playing():
		return
	_told_day = Game.day
	main.hud.show_toast("There's post in your mailbox.")


## The mailbox itself: it lists its own actions (main.gd _actions_for asks things for theirs).
class MailBox extends Node3D:
	var mail

	func add_hitbox(size: Vector3) -> void:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position.y = size.y * 0.5
		body.add_child(cs)
		body.set_meta("target", self)
		add_child(body)

	func display_name() -> String:
		return "Mailbox"

	func ke_actions() -> Array:
		return mail.actions()

	func ke_action(id: String) -> void:
		mail.do_action(id)
