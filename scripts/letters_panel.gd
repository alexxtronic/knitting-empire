## The letters panel (from the mailbox, or Menu > Letters): every letter she has taken out of the
## mailbox (scripts/mail.gd), newest first, down the left; the one picked on cream paper on the
## right. Opening a letter the first time hands over anything enclosed.
extends PanelContainer

const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const INK := Color(0.24, 0.17, 0.12)

var hud: Node # hud.gd, for its labels, buttons and sounds
var mail: Node # mail.gd; main.gd hands it over
var current := -1 # index into mail.letters() of the letter shown, or -1

var _list: VBoxContainer
var _empty: Label
var _from: Label
var _meta: Label
var _body: RichTextLabel
var _note: Label # what was enclosed, or what an order wants


func setup(h: Node) -> void:
	hud = h
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(hud._label("Letters", 24, GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	# the list
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(250, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	row.add_child(sc)
	# the letter, on paper
	var paper_box := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.96, 0.92, 0.82)
	paper.border_color = Color(0.72, 0.6, 0.42)
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(6)
	paper.set_content_margin_all(22)
	paper_box.add_theme_stylebox_override("panel", paper)
	paper_box.custom_minimum_size = Vector2(520, 440)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	paper_box.add_child(pv)
	_from = hud._label("", 19, INK)
	pv.add_child(_from)
	_meta = hud._label("", 12, Color(INK, 0.6))
	pv.add_child(_meta)
	var bsc := ScrollContainer.new()
	bsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = RichTextLabel.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(470, 0)
	_body.add_theme_color_override("default_color", INK)
	_body.add_theme_font_size_override("normal_font_size", 15)
	bsc.add_child(_body)
	pv.add_child(bsc)
	_note = hud._label("", 14, Color(0.45, 0.18, 0.12))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(470, 0)
	pv.add_child(_note)
	_empty = hud._label("No letters yet. Barbara brings the post to your mailbox at nine.", 15, Color(INK, 0.7))
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(470, 0)
	pv.add_child(_empty)
	row.add_child(paper_box)
	var close_btn: Button = hud._button("Close", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


## Opens the panel on the letter with this id (or the newest unread one, else the newest).
func open(id := "") -> void:
	hud.click("ui_open")
	var ls: Array = mail.letters()
	var pick := -1
	for i in range(ls.size() - 1, -1, -1):
		if (id != "" and str(ls[i]["id"]) == id) or (id == "" and pick < 0 and not bool(ls[i].get("read", false))):
			pick = i
	if pick < 0:
		pick = ls.size() - 1
	visible = true
	move_to_front()
	show_letter(pick)


func close() -> void:
	visible = false


func show_letter(i: int) -> void:
	var ls: Array = mail.letters()
	current = i if i >= 0 and i < ls.size() else -1
	_empty.visible = current < 0
	_note.text = ""
	if current < 0:
		_from.text = ""
		_meta.text = ""
		_body.text = ""
	else:
		var l: Dictionary = ls[current]
		_from.text = "From %s" % l["from"]
		_meta.text = "%s%sDay %d" % [l["place"], "  ·  " if str(l["place"]) != "" else "", int(l["day"])]
		_body.text = str(l["body"])
		var enclosed: String = mail.read(l)
		if enclosed != "":
			_note.text = enclosed
			hud.show_toast(enclosed + ".")
		elif int(l.get("coins", 0)) > 0 or str(l.get("item", "")) != "":
			_note.text = "Enclosed: %s" % ("%dc" % int(l["coins"]) if int(l.get("coins", 0)) > 0 else "%d %s" % [int(l.get("item_n", 1)), l["item"]])
		if str(l.get("kind", "")) == "order":
			_note.text = _order_line(str(l["order"]))
	_fill_list()


func _order_line(oid: String) -> String:
	var o: Dictionary = mail.orders().get(oid, {})
	if o.is_empty():
		return ""
	var want: String = mail.RARITY[clampi(int(o["stars"]), 1, 5) - 1]
	match str(o["state"]):
		"open":
			return "Wants one sweater, %s or better, for %dc. Put it in your mailbox and Barbara takes it on her round." % [want, int(o["pay"])]
		"posted":
			return "The sweater is in your mailbox, flag up. Barbara takes it on her next round."
		"sent":
			return "Barbara took the sweater. Payment comes in the post."
	return "Sent and paid."


func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var ls: Array = mail.letters()
	for i in range(ls.size() - 1, -1, -1):
		var l: Dictionary = ls[i]
		var unread := not bool(l.get("read", false))
		var b: Button = hud._button("%s%s\n%s" % ["● " if unread else "", l["from"], l["subject"]], show_letter.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(236, 52)
		b.clip_text = true
		if i == current:
			b.modulate = Color(1.15, 1.05, 0.8)
		_list.add_child(b)
