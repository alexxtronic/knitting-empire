extends Node
## Knitted scarves for the dog (docs/DIRECTION.md, 2026-11-16: "Knitting rare scarves for the dog so
## he can run faster and stay more warm in cold areas and catch rarer animals").
##
## Once Act 1 is done the rocking chair (and armchair) has "Knit a scarf for the dog" rows: plain
## wool, or a little wool and a wild fibre. The knitting game decides its quality like a sweater's,
## lifted to her needles' floor and the fibre's own (main._finish_knit hands it to knitted()). A
## scarf isn't a sweater: it never goes in her bag, to a request or to Rosa.
##
## Her scarves are Game.flags["dog_scarves"] ([{"q": rarity, "fibre": id or "", "n": how many}]),
## the one he wears Game.flags["dog_scarf"] ({"q", "fibre"}, or none for his red one). Clicking the
## dog (once she has one) lists them to put on, and takes his off. update() keeps him dressed from
## the flags, so a loaded game, a new one or a check that sets the flags all dress him.
##
## What a scarf does is data/scarves.json "tiers" by quality: a faster trot and gallop, more fright
## in every bark (dog.bark_power(), wildlife.barked), and warmth kept for cold lands (dog.warmth()).
##
## The pack (kennel.gd, from Act 2): any of her scarves goes on any of her dogs, one dog for each
## copy she has knitted (`n`). A pack dog's scarf is the "scarf" of its row in Game.flags["dogs"];
## its menu lists her scarves as her first dog's does.

const Data = preload("res://scripts/data.gd")
const KnitGame = preload("res://scripts/knit_game.gd")

var main: Node # main.gd
var data := {}


func _ready() -> void:
	name = "Scarves"
	data = Data.load_json("scarves")


func wool() -> int:
	return int(data.get("wool", 2))


func fibre_wool() -> int:
	return int(data.get("fibre_wool", 1))


## The row of data/scarves.json "tiers" for a quality (1..5).
func tier(q: int) -> Dictionary:
	for t in data.get("tiers", []):
		if int(t.get("rarity", 0)) == q:
			return t
	return {}


func owned() -> Array:
	var v = Game.flag("dog_scarves", [])
	return v if v is Array else []


## The scarf he wears ({"q", "fibre"}), empty for his red one. `dog` a pack dog (kennel.gd), or
## null for her first.
func worn(dog: Node = null) -> Dictionary:
	var v: Variant = Game.flag("dog_scarf", {})
	if dog != null and int(dog.get("pack_index")) >= 0:
		var list: Array = main.kennel.bought() if main and main.kennel else []
		var i := int(dog.get("pack_index"))
		v = (list[i] as Dictionary).get("scarf", {}) if i < list.size() and list[i] is Dictionary else {}
	return v if v is Dictionary and int((v as Dictionary).get("q", 0)) > 0 else {}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("q", 0)) == int(b.get("q", 0)) and str(a.get("fibre", "")) == str(b.get("fibre", ""))


## How many of her dogs other than `dog` wear a scarf like `s`.
func _worn_by_others(s: Dictionary, dog: Node) -> int:
	var n := 0
	if main and main.kennel:
		for d in main.kennel.all_dogs():
			if d != dog and _same(worn(d), s):
				n += 1
	elif dog != null and int(dog.get("pack_index")) >= 0 and _same(worn(), s):
		n += 1
	return n


func name_of(s: Dictionary) -> String:
	var f := str(s.get("fibre", ""))
	var what: String = "wool" if f == "" or main == null else main.wildlife.item_name(f).to_lower()
	return "%s %s scarf" % [KnitGame.rarity_name(int(s.get("q", 1))), what]


## The chair's rows: a plain scarf, and one for each wild fibre in her bag. Not before Act 1 is
## done (Gran leaves just enough wool for the first sweater).
func knit_rows() -> Array:
	if Game.flag("act1_done") != true:
		return []
	var rows: Array = [main._act("knit_scarf", "Knit a scarf for the dog…  (%d wool)" % wool(), Game.has_item("wool", wool()))]
	for id in main.wildlife.fibres():
		if Game.count(id) <= 0:
			continue
		var fl: int = main.wildlife.knit_floor(id)
		rows.append(main._act("knit_scarf:" + id, "Knit the dog a %s scarf…  (%d wool + 1 · %s or better)" % [main.wildlife.item_name(id).to_lower(), fibre_wool(), KnitGame.rarity_name(fl)], Game.has_item("wool", fibre_wool())))
	return rows


## Whether she has what a scarf takes ("" plain wool, else that fibre and a little wool).
func can_knit(fibre: String) -> bool:
	if fibre == "":
		return Game.has_item("wool", wool())
	return Game.has_item("wool", fibre_wool()) and Game.has_item(fibre)


## The knitting game is done: take the wool (and fibre) and keep the scarf. Returns its quality, or
## 0 if she no longer had what it takes.
func knitted(rarity: int, fibre: String) -> int:
	if fibre != "" and not can_knit(fibre):
		fibre = ""
	if not can_knit(fibre):
		main.hud.show_toast("You need %d wool for a scarf." % wool())
		return 0
	var q := clampi(rarity, 1, 5)
	if fibre != "":
		Game.take_item("wool", fibre_wool())
		Game.take_item(fibre)
		q = maxi(q, main.wildlife.knit_floor(fibre))
	else:
		Game.take_item("wool", wool())
	var list: Array = owned().duplicate(true)
	var found := false
	for s in list:
		if int(s.get("q", 0)) == q and str(s.get("fibre", "")) == fibre:
			s["n"] = int(s.get("n", 1)) + 1
			found = true
	if not found:
		list.append({"q": q, "fibre": fibre, "n": 1})
	list.sort_custom(func(a, b): return int(a["q"]) > int(b["q"]))
	Game.set_flag("dog_scarves", list)
	Game.add_need("happiness", 8.0)
	var s := {"q": q, "fibre": fibre}
	var better := q > int(worn().get("q", 0))
	if better:
		wear(s)
	main.hud.show_toast("A %s for the dog!%s" % [name_of(s), " She ties it on him: he's quicker on his paws, and his bark carries." if better else " Click him to change his scarf."])
	return q


## Puts a scarf she has on him (`dog` a pack dog, or null for her first); an empty one gives him
## his red scarf back.
func wear(s: Dictionary, dog: Node = null) -> void:
	var on := {} if s.is_empty() else {"q": int(s.get("q", 1)), "fibre": str(s.get("fibre", ""))}
	if dog != null and int(dog.get("pack_index")) >= 0 and main and main.kennel:
		var list: Array = main.kennel.bought().duplicate(true)
		var i := int(dog.get("pack_index"))
		if i < list.size() and list[i] is Dictionary:
			if on.is_empty():
				(list[i] as Dictionary).erase("scarf")
			else:
				list[i]["scarf"] = on
			Game.set_flag("dogs", list)
	elif on.is_empty():
		Game.flags.erase("dog_scarf")
	else:
		Game.set_flag("dog_scarf", on)
	update()


## A dog's menu: each scarf she has to put on (greyed when every copy is on another of her dogs),
## and his own red one back.
func dog_rows(dog: Node = null) -> Array:
	var list := owned()
	var on := worn(dog)
	if list.is_empty() and on.is_empty():
		return []
	var rows: Array = []
	for i in list.size():
		var s: Dictionary = list[i]
		var t := tier(int(s.get("q", 1)))
		var wearing: bool = _same(on, s)
		var free: bool = _worn_by_others(s, dog) < int(s.get("n", 1))
		var what := "Wearing the" if wearing else ("Put on the" if free else "On another dog: the")
		var row: Dictionary = main._act("scarf_on:%d" % i, "%s %s  (×%.2f gallop · ×%.2f bark)" % [what, name_of(s), float(t.get("run", 1.0)), float(t.get("bark", 1.0))], not wearing and free)
		rows.append(row)
	if not on.is_empty():
		var off: Dictionary = main._act("scarf_off", "Take his scarf off  (his red one back)")
		rows.append(off)
	return rows


func perform(id: String, dog: Node = null) -> void:
	var who: String = "The dog" if dog == null or int(dog.get("pack_index")) < 0 else str(dog.call("display_name"))
	if id == "scarf_off":
		wear({}, dog)
		main.hud.show_toast("%s has his red scarf back." % who)
	elif id.begins_with("scarf_on:"):
		var i := int(id.trim_prefix("scarf_on:"))
		var list := owned()
		if i >= 0 and i < list.size() and _worn_by_others(list[i], dog) < int(list[i].get("n", 1)):
			wear(list[i], dog)
			main.hud.show_toast("%s wears the %s now." % [who, name_of(list[i])])


## Dresses every dog from the flags whenever they change (a load, a new game, a check).
func update() -> void:
	if main == null:
		return
	var dogs: Array = main.kennel.all_dogs() if main.kennel else ([main.dog] if main.dog else [])
	for dog in dogs:
		if dog == null or not is_instance_valid(dog):
			continue
		var on := worn(dog if int(dog.pack_index) >= 0 else null)
		var key := "" if on.is_empty() else "%d|%s" % [int(on["q"]), str(on.get("fibre", ""))]
		if key == dog._dressed_key:
			continue
		dog._dressed_key = key
		dog.wear_scarf({} if on.is_empty() else tier(int(on["q"])), float(data.get("max_rate", 1.5)))
