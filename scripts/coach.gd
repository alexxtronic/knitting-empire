extends RefCounted
## What to do next, in one line, from what she has right now (Alex, 2026-11-27: "Make more prompts
## for what to do next, make it clear they should build a pen to store the animals in it. Chapter
## one is all about setting up the foundations, getting the pen built, getting animals in the pen
## and selling sweaters."). The loop read backwards from the money: a sweater in her bag is sold
## first, then wool enough is knitted, then a coat that's ready is shorn or combed, then an animal
## is caught for a pen with room, and before any of that a pen is built.
## Shown as the first line of the Empire goal list (empire_goals.gd), once Act 1's guided part is
## done (the story's own goal line leads until then). Every line is a draft.

const Keys = preload("res://scripts/keybinds.gd")


## [id, text]: the id is what the checks read; "" when there's nothing to say.
static func next_step(main: Node) -> Array:
	if main == null or Game.flag("act1_done") != true:
		return ["", ""]
	var wl = main.wildlife
	var dog_key: String = Keys.key_name(Keys.bound("dog"))
	if Game.count("sweater") > 0:
		return ["sell", "Sell your sweater. Offer it to anyone in town: a red pin over someone's head means they want one today and will pay well, everyone else pays a little less."]
	if Game.has_item("wool", 3):
		return ["knit", "Knit a sweater: click the rocking chair. (Wild fibre knits a rarer one.)"]
	var ready := 0
	for s in main.sheep_list:
		if is_instance_valid(s) and s.has_method("is_woolly") and s.is_woolly():
			ready += 1
	if wl:
		for a in wl.penned():
			if a.has_method("has_fur") and a.has_fur():
				ready += 1
	if ready > 0:
		return ["shear", "%d of your animals %s a coat ready: click one in the pen to shear or comb it." % [ready, "has" if ready == 1 else "have"]]
	if wl == null:
		return ["", ""]
	if wl.pens().is_empty():
		return ["pen", "Build a pen to keep animals in: get wood (Steve sells it, or fell a tree), press F and click to lay fence round a patch of your farm, then set a gate in it (G)."]
	if wl.pen_room() > 0:
		if not wl.following().is_empty():
			return ["lead", "Lead it home: walk the dog back to your pen and in through the gate."]
		return ["catch", "Catch an animal for your pen: click the dog and choose Play as the dog (or press %s), go up to a wild animal, and bark (right-click) until its Fright bar fills. Then lead it home." % dog_key]
	return ["full", "Your pens are full and the coats are growing back. Build another pen (F) for more animals, or buy wool from Rosa while you wait."]
