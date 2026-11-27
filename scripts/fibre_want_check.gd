extends RefCounted
## --only=sale (after _sale_checks) and the full run: which fibre buyers want face to face
## (scripts/sweater_sale.gd wanted_fibre(), data/economy.json "wants"; Alex, 2026-11-24: "request
## specific fiber types but nothing unobtainable ... requests scale as the game develops"). Sheep's
## wool only before act1_done; in Act 1 nothing above Common over many rolls; a Rare fibre once she
## has combed a fox; Ultra Rare only in Act 3; the panel showing only the fibre wanted; a fox sweater
## worth more than a plain one; no panel and a line naming the fibre when she has none of it; a
## townsperson's row and Talk naming it; a local's lynx request waiting in Act 1.
## Leaves the flags, the act, the coins and her sweaters as it found them.

const SweaterSale = preload("res://scripts/sweater_sale.gd")

var m: Node


func _ids(n: int) -> Array:
	var out := []
	for i in n:
		out.append("fw_buyer_%d" % i)
	return out


## The tiers wanted by `n` made-up buyers today.
func _tiers_seen(n: int) -> Dictionary:
	var seen := {}
	for vid in _ids(n):
		seen[SweaterSale.fibre_tier(SweaterSale.wanted_fibre(vid))] = true
	return seen


func run(main: Node) -> void:
	m = main
	var keep := {"flags": Game.flags.duplicate(true), "act": Game.act, "coins": Game.coins, "sw": Game.sweaters.duplicate(),
		"sd": Game.sweater_designs.duplicate(), "sf": Game.sweater_fibres.duplicate()}
	var on0 := SweaterSale.fibre_on
	SweaterSale.fibre_on = true
	SweaterSale.force_fibre = ""
	m.hud.hide_dialogue()

	# before act1_done: sheep's wool, always
	Game.flags.erase("act1_done")
	Game.flags.erase("guide")
	Game.act = 1
	var pre := _tiers_seen(200)
	m._check("fibre wants: before Act 1 is done every buyer wants sheep's wool (%s)" % str(pre.keys()), pre.keys() == ["plain"])

	# Act 1 after act1_done: wool and angora, nothing rarer
	Game.flags["act1_done"] = true
	var a1 := _tiers_seen(400)
	m._check("fibre wants: in Act 1 only sheep's wool and angora are wanted over 400 buyers (%s)" % str(a1.keys()),
		a1.has("plain") and a1.has("common") and a1.size() == 2)
	# a fox combed opens Rare (one tier above the act's), not Ultra Rare
	Game.flags["guide"] = {"fox": {"seen": Game.day, "combed": 1}}
	var a1f := _tiers_seen(400)
	m._check("fibre wants: in Act 1 a combed fox opens Rare and nothing above (%s)" % str(a1f.keys()),
		a1f.has("rare") and not a1f.has("ultra_rare") and not a1f.has("legendary") and not a1f.has("mythic"))
	Game.flags.erase("guide")
	Game.act = 2
	var a2 := _tiers_seen(400)
	m._check("fibre wants: Act 2 brings Rare, still no Ultra Rare (%s)" % str(a2.keys()), a2.has("rare") and not a2.has("ultra_rare"))
	Game.act = 3
	var a3 := _tiers_seen(400)
	m._check("fibre wants: Act 3 brings Ultra Rare, not Legendary (%s)" % str(a3.keys()), a3.has("ultra_rare") and not a3.has("legendary"))
	Game.act = 4
	var a4 := _tiers_seen(600)
	m._check("fibre wants: Act 4 opens them all, sheep's wool still the commonest (%s)" % str(a4.keys()),
		a4.has("legendary") and a4.has("mythic") and a4.has("plain"))
	var same := SweaterSale.wanted_fibre("fw_buyer_3") == SweaterSale.wanted_fibre("fw_buyer_3")
	m._check("fibre wants: a buyer wants the same fibre all day", same)

	# the sale itself: Wren wants fox fluff today
	Game.act = 2
	var wren: Node = m._villager("wren")
	SweaterSale.force_fibre = "fox_fibre"
	while Game.sweaters.size() > 0:
		Game.remove_sweater(0)
	Game.add_sweater(3, "")
	Game.sync_sweaters()
	var flags_ask: Dictionary = (Game.flag("sweater_asked", {}) as Dictionary).duplicate()
	flags_ask["wren"] = {"day": Game.day, "yes": true, "tries": 0}
	Game.set_flag("sweater_asked", flags_ask)
	var rows: Array = m.sale.rows_for(wren)
	var row_label := str(rows[0]["label"]) if rows.size() > 0 else ""
	m._check("fibre wants: with only a wool sweater, Wren's row names fox fluff and offers to show her another for less (\"%s\")" % row_label,
		rows.size() == 1 and bool(rows[0]["enabled"]) and "fox fluff" in row_label and "pay less" in row_label)
	m.hud.hide_dialogue()
	var opened: bool = m.sale.ask(wren)
	await m._wait(0.3)
	var said := str(m.sale._said.text)
	var wool_res: int = m.sale.reserve("wren", 3, "wool")
	var fox_res: int = m.sale.reserve("wren", 3, "fox_fibre")
	m._check("fibre wants: shown a wool one, she says she's after fox fluff and would take it for less (\"%s\"; her top for it %dc, %dc if it were what she wanted)" % [said, wool_res, int(round(wool_res / SweaterSale.cfg("casual_mult", 0.82)))],
		opened and m.sale.visible and "fox fluff" in said and not SweaterSale.keen("wren", "wool") and SweaterSale.keen("wren", "fox_fibre") and fox_res > wool_res)
	m.sale.close()
	m.hud.hide_dialogue()
	Game.add_sweater(3, "")
	Game.sync_sweaters()
	Game.sweater_fibres[Game.sweaters.size() - 1] = "fox_fibre"
	var fox_i := Game.sweaters.size() - 1
	rows = m.sale.rows_for(wren)
	m._check("fibre wants: with a fox sweater, Show them a sweater is open", rows.size() == 1 and bool(rows[0]["enabled"]) and str(rows[0]["id"]) == "sale_haggle")
	opened = m.sale.ask(wren)
	await m._wait(0.3)
	var shown: Array = SweaterSale.choices(SweaterSale.wanted_fibre("wren"))
	m._check("fibre wants: the panel opens on the fox sweater alone (%d shown, on #%d)" % [shown.size(), m.sale.choice],
		opened and m.sale.visible and shown.size() == 1 and m.sale.choice == fox_i)
	var plain: int = m.sale.fair(3)
	var fox: int = m.sale.fair(3, "fox_fibre")
	m._check("fibre wants: a fox sweater's fair price is above a wool one of the same grade (%dc against %dc)" % [fox, plain], fox > plain)
	await m._shot("61_sale_fibre.png")
	var coins0 := Game.coins
	m.sale.force_roll = 0.0
	m.sale.set_price(fox)
	var res: String = m.sale.offer()
	m.sale.force_roll = -1.0
	m._check("fibre wants: she sells the fox sweater at its price and keeps the wool one (%s, +%dc, left %s)" % [res, Game.coins - coins0, str(Game.sweater_fibres)],
		res == "sold" and Game.coins - coins0 == fox and Game.sweater_fibres.size() == 1 and str(Game.sweater_fibres[0]) == "")
	m.hud.hide_dialogue()
	m.sale.close()

	# a townsperson's row and Talk name the fibre
	var tf: Node = m.townsfolk
	if tf != null and tf.people.size() > 0:
		var p: Node = tf.people[0]
		Game.flags["tf_want_" + p.vid] = Game.day
		var srow: Array = tf.actions(p).filter(func(a): return str(a["id"]) == "sale")
		m._check("fibre wants: a townsperson's sweater row names fox fluff and is greyed with only wool (%s)" % str(srow.map(func(a): return a["label"])),
			srow.size() == 1 and not bool(srow[0]["enabled"]) and "fox fluff" in str(srow[0]["label"]))
		var talk: String = tf.want_talk(p)
		m._check("fibre wants: their Talk names fox fluff (\"%s\")" % talk, "fox fluff" in talk)
	else:
		m._check("fibre wants: the townsfolk aren't built here, row skipped", true)

	# a local's request for a fibre above the open tiers waits
	SweaterSale.force_fibre = ""
	Game.act = 1
	Game.flags.erase("guide")
	var lynx_open := SweaterSale.fibre_open("lynx_fibre")
	var fox_open := SweaterSale.fibre_open("fox_fibre")
	var due: Dictionary = m.empire.due()
	m._check("fibre wants: in Act 1 lynx and fox are closed, and no request due asks for one (%s)" % str(due.get("id", "none")),
		not lynx_open and not fox_open and not (due.has("fibre") and not SweaterSale.fibre_open(str(due["fibre"]))))

	# put it all back
	SweaterSale.force_fibre = ""
	SweaterSale.fibre_on = on0
	Game.flags = keep["flags"]
	Game.act = keep["act"]
	Game.coins = keep["coins"]
	Game.sweaters = keep["sw"]
	Game.sweater_designs = keep["sd"]
	Game.sweater_fibres = keep["sf"]
	Game.inv["sweater"] = Game.sweaters.size()
	m.hud.hide_dialogue()
