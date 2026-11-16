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

const Data = preload("res://scripts/data.gd")
const KnitGame = preload("res://scripts/knit_game.gd")

var main: Node # main.gd
var data := {}
var _dressed := "-" # the scarf the dog was last dressed in ("" his red one)


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


## The scarf he wears ({"q", "fibre"}), empty for his red one.
func worn() -> Dictionary:
	var v = Game.flag("dog_scarf", {})
	return v if v is Dictionary and int((v as Dictionary).get("q", 0)) > 0 else {}


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


## Puts a scarf she has on him; an empty one gives him his red scarf back.
func wear(s: Dictionary) -> void:
	if s.is_empty():
		Game.flags.erase("dog_scarf")
	else:
		Game.set_flag("dog_scarf", {"q": int(s.get("q", 1)), "fibre": str(s.get("fibre", ""))})
	update()


## The dog's menu: each scarf she has to put on, and his own red one back.
func dog_rows() -> Array:
	var list := owned()
	var on := worn()
	if list.is_empty() and on.is_empty():
		return []
	var rows: Array = []
	for i in list.size():
		var s: Dictionary = list[i]
		var t := tier(int(s.get("q", 1)))
		var wearing: bool = int(on.get("q", 0)) == int(s.get("q", 0)) and str(on.get("fibre", "")) == str(s.get("fibre", ""))
		var row: Dictionary = main._act("scarf_on:%d" % i, "%s %s  (×%.2f gallop · ×%.2f bark)" % ["Wearing the" if wearing else "Put on the", name_of(s), float(t.get("run", 1.0)), float(t.get("bark", 1.0))], not wearing)
		rows.append(row)
	if not on.is_empty():
		var off: Dictionary = main._act("scarf_off", "Take his scarf off  (his red one back)")
		rows.append(off)
	return rows


func perform(id: String) -> void:
	if id == "scarf_off":
		wear({})
		main.hud.show_toast("He has his red scarf back.")
	elif id.begins_with("scarf_on:"):
		var i := int(id.trim_prefix("scarf_on:"))
		var list := owned()
		if i >= 0 and i < list.size():
			wear(list[i])
			main.hud.show_toast("The dog wears the %s now." % name_of(list[i]))


## Dresses the dog from the flags whenever they change (a load, a new game, a check).
func update() -> void:
	var dog = main.dog if main else null
	if dog == null:
		return
	var on := worn()
	var key := "" if on.is_empty() else "%d|%s" % [int(on["q"]), str(on.get("fibre", ""))]
	if key == _dressed:
		return
	_dressed = key
	dog.wear_scarf({} if on.is_empty() else tier(int(on["q"])), float(data.get("max_rate", 1.5)))
