extends Node
## More dogs (step 4 of docs/REVIEW_2026-11-24.md; Alex, 2026-11-24: "purchasing additional dogs
## which you can use to hunt larger packs of animals at a time ... 2 dogs allows you to herd 4
## animals at once rather than the usual 2, 3 dogs allows for 6 etc all the way up to 12 dogs
## maximum. Dogs are an expensive investment").
##
## From Act 2 (Game.unlocked("dogs")) Lars's menu has "Buy a dog". Each costs more than the last
## (data/economy.json "dogs": price, price_mult, round), up to `max` dogs counting her first. The
## dogs she buys are Game.flags["dogs"]: [{"name", "coat", "scarf"?}], in the order bought; her
## first dog (main.dog) isn't in it and stays as he is. update() builds and dresses the pack from
## that list, so a load, a new game or a check that sets the flag needs nothing more.
##
## Each dog she owns lets two more animals follow (data/wildlife.json herd_per_dog, read by
## wildlife.max_herd() through count()).
##
## The pack: each extra dog is a dog.gd of its own with `pack_leader` set, in a loose formation
## behind whoever leads: Nora on foot, or the dog she plays while she plays him. Only the player
## herds (2026-11-16): pack dogs aren't herders, don't frighten anything by being near, and never go
## after an animal; they move only with their leader. When the dog she plays barks, every pack dog
## within `pack_bark_range` of him barks too, and each bark frightens the animals round that dog
## (wildlife.barked(at, power)) and takes nerve from wolves (wolves.barked()).
##
## Their look: dog.glb with the fur tinted to the coat's colour (shaders/dog_scarf.gdshader) until
## Alex's breeds land as a `model` per coat. Each wears a knitted scarf of its own (scarves.gd).
##
## The frame rate: past the `lod_after`th dog, or more than `lod_far` m from the camera, a dog
## animates and thinks `lod_hz` times a second instead of every frame (dog.set_lod()).

const Data = preload("res://scripts/data.gd")
const Dog = preload("res://scripts/dog.gd")

var main: Node # main.gd
var data := {}
var pack: Array = [] # dog.gd nodes, in Game.flags["dogs"] order
var _sig := "-" # the list the pack was last built from
var _sync_t := 0.0
var frozen := false # a check holds them where it put them (for a picture)


func _ready() -> void:
	name = "Kennel"
	data = Data.economy().get("dogs", {})


func bought() -> Array:
	var v: Variant = Game.flag("dogs", [])
	return v if v is Array else []


## How many dogs she owns, her first included.
func count() -> int:
	return 1 + bought().size()


func max_dogs() -> int:
	return maxi(1, int(data.get("max", 12)))


## What the dog after `n_bought` bought ones costs: `price`, then `price_mult` times the last.
func price_of(n_bought: int) -> int:
	var r := maxi(1, int(data.get("round", 50)))
	var p := float(data.get("price", 3000)) * pow(float(data.get("price_mult", 1.26)), n_bought)
	return int(roundf(p / r)) * r


func next_price() -> int:
	return price_of(bought().size())


func coat(id: String) -> Dictionary:
	return (data.get("coats", {}) as Dictionary).get(id, {})


## Lars's rows: nothing before Act 2, then a dog at its price, or the most she can keep.
func rows_for(v) -> Array:
	if v == null or str(v.vid) != "lars" or not Game.unlocked("dogs"):
		return []
	var row: Dictionary
	if count() >= max_dogs():
		row = main._act("noop", "You have %d dogs: as many as one farm can keep" % count(), false)
	else:
		var p := next_price()
		row = main._act("dog_buy", "Buy a dog  (%sc · you have %d)" % [main._thousands(p), count()], Game.coins >= p)
	row["group"] = "Dogs"
	return [row]


func action(_v, id: String) -> void:
	if id == "dog_buy":
		buy()


## Buys the next dog: true if she could. Refused before Act 2, at the most she can keep, or short of coins.
func buy() -> bool:
	if not Game.unlocked("dogs"):
		return false
	if count() >= max_dogs():
		main.hud.show_toast("You have %d dogs: as many as one farm can keep." % count())
		return false
	var p := next_price()
	if not Game.spend(p):
		main.hud.show_toast("A dog costs %sc." % main._thousands(p))
		return false
	var list: Array = bought().duplicate(true)
	var names: Array = data.get("names", ["Biscuit"])
	var order: Array = data.get("coat_order", ["cream"])
	var i := list.size()
	var dog := {"name": str(names[i % names.size()]), "coat": str(order[i % order.size()])}
	list.append(dog)
	Game.set_flag("dogs", list)
	sync()
	Game.add_need("happiness", 10.0)
	var herd: int = main.wildlife.max_herd() if main.wildlife else 0
	main.hud.show_toast("%s, a %s pup, joins the pack! Your dogs can herd %d animals at once now." % [dog["name"], str(coat(str(dog["coat"])).get("name", dog["coat"])), herd])
	return true


## Builds the pack again if the list has changed (a purchase, a load, a check).
func sync() -> void:
	var list := bought()
	var sig := ""
	for d in list:
		if d is Dictionary:
			sig += "%s|%s;" % [str(d.get("name", "")), str(d.get("coat", ""))]
	if sig == _sig and pack.size() == list.size():
		return
	_sig = sig
	for d in pack:
		if is_instance_valid(d):
			d.queue_free()
	pack = []
	var lead: Node3D = _leader()
	for i in list.size():
		var e: Dictionary = list[i] if list[i] is Dictionary else {}
		var d := Dog.new()
		d.main = main
		d.pack_index = i
		d.pack_name = str(e.get("name", "Dog"))
		var c := coat(str(e.get("coat", "")))
		if c.has("model") and ResourceLoader.exists(str(c["model"])):
			d.model_path = str(c["model"])
		d.name = "PackDog%d" % i
		main.add_child(d)
		d.coat_id = str(e.get("coat", ""))
		d.set_coat(Color.html(str(c["tint"])) if c.has("tint") else null)
		if lead != null:
			d.position = _slot_point(lead, i)
		pack.append(d)
	if main.scarves:
		main.scarves.update()


## Whom the pack follows: the dog she plays while she plays him, else Nora.
func _leader() -> Node3D:
	if main.dog != null and main.dog.controlled and main.dog.visible:
		return main.dog
	return main.player


## A loose formation behind the leader, three abreast, each row a little further back. In the
## leader's own frame (x across, z ahead; they all face +Z), so `slot()` turns with him.
func slot(i: int) -> Vector3:
	var row := int(i / 3.0)
	var col := i % 3
	var x: float = [0.0, -1.3, 1.3][col] + (0.35 if row % 2 == 1 else 0.0)
	return Vector3(x, 0.0, -(1.9 + row * 1.5))


func _slot_point(lead: Node3D, i: int) -> Vector3:
	var b: Basis = lead.global_transform.basis
	var s := slot(i)
	var p: Vector3 = lead.global_position + b.x.normalized() * s.x + b.z.normalized() * s.z
	p.y = 0.0
	return p


## Every frame, from main._update_dog(): the leader and formation, who's drawn cheaply, and the scarves.
func update(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.25
		sync()
	if pack.is_empty():
		return
	var lead := _leader()
	var here: bool = main.dog == null or main.dog.visible
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	var far := float(data.get("lod_far", 30.0))
	var after := int(data.get("lod_after", 5))
	var hz := float(data.get("lod_hz", 10.0))
	for i in pack.size():
		var d = pack[i]
		if not is_instance_valid(d):
			continue
		if d.visible != here:
			d.visible = here
			d.process_mode = Node.PROCESS_MODE_INHERIT if here else Node.PROCESS_MODE_DISABLED
		d.pack_leader = null if frozen else lead
		d.pack_slot = slot(i)
		var cheap := i >= after or (cam != null and cam.global_position.distance_to(d.global_position) > far)
		d.set_lod(hz if cheap else 0.0)


## The dog she plays barked at `at`: every pack dog near enough barks too, and its bark reaches
## the animals and wolves round it. Returns how many pack dogs barked.
func barked(at: Vector3) -> int:
	var n := 0
	var r := float(data.get("pack_bark_range", 12.0))
	for d in pack:
		if not is_instance_valid(d) or not d.visible:
			continue
		var p: Vector3 = d.global_position
		if Vector2(p.x - at.x, p.z - at.z).length() > r:
			continue
		if not d.bark():
			continue
		n += 1
		if main.wildlife:
			main.wildlife.barked(p, d.bark_power())
		if main.wolves:
			main.wolves.barked(p)
	return n


## The pack dog named in a save or a check, or null.
func by_name(dog_name: String) -> Node3D:
	for d in pack:
		if is_instance_valid(d) and d.pack_name == dog_name:
			return d
	return null


## Every dog she owns as nodes: her first, then the pack.
func all_dogs() -> Array:
	var out: Array = []
	if main.dog != null:
		out.append(main.dog)
	for d in pack:
		if is_instance_valid(d):
			out.append(d)
	return out
