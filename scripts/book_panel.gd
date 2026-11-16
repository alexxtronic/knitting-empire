## The books (data/books.json): a shelf of them down the left, and the one she has open on the right,
## two cream pages at a time. ◀ ▶ (or the arrow keys) turn the pages; each book keeps its place
## (Game.flags["books"]: id -> {"page", "done"}). From a bookshelf it opens to choose one (`pick`):
## the right side shows the book's cover and blurb, and taking it says so through `picked`.
## main.gd sits her down with it (begin_read) and gets `closed` when she puts it down.
extends PanelContainer

signal closed
signal picked(id: String)

const Data = preload("res://scripts/data.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const INK := Color(0.22, 0.16, 0.11)
const PAPER := Color(0.97, 0.93, 0.83)
const GENRE := {"horror": "Horror", "thriller": "Thriller", "romance": "Romance"}
const GENRE_COLOUR := {"horror": Color(0.72, 0.62, 0.95), "thriller": Color(0.55, 0.78, 1.0), "romance": Color(1.0, 0.62, 0.68)}
const COVER := {"plum": Color(0.42, 0.22, 0.42), "forest": Color(0.20, 0.36, 0.25), "wine": Color(0.50, 0.15, 0.17), "navy": Color(0.17, 0.22, 0.40), "mustard": Color(0.72, 0.55, 0.18)}

var hud: Node # hud.gd, for its labels, buttons and sounds
var current := "" # the id of the book open (or picked out), "" for none
var spread := 0 # the left page's index, always even
var pick_mode := false
var pages_read := 0 # pages she has turned to since the panel opened (main.gd rewards them)
var finished := [] # ids of books she finished since it opened

var _books: Array = []
var _title: Label
var _list: VBoxContainer
var _head: Label
var _byline: Label
var _pages: Array[RichTextLabel] = []
var _nums: Array[Label] = []
var _spread_box: HBoxContainer
var _cover_box: PanelContainer
var _cover_title: Label
var _cover_blurb: Label
var _prev: Button
var _next: Button
var _where: Label
var _take: Button


func setup(h: Node) -> void:
	hud = h
	_books = Data.load_json("books").get("books", [])
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_title = hud._label("Books", 24, GOLD)
	vb.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	# the shelf
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(260, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	row.add_child(sc)
	# the book
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	_head = hud._label("", 20, GOLD)
	right.add_child(_head)
	_byline = hud._label("", 13, Color(TEXT, 0.75))
	right.add_child(_byline)
	_spread_box = HBoxContainer.new()
	_spread_box.add_theme_constant_override("separation", 4)
	for side in 2:
		var page := PanelContainer.new()
		var paper := StyleBoxFlat.new()
		paper.bg_color = PAPER
		paper.border_color = Color(0.70, 0.58, 0.40)
		paper.set_border_width_all(2)
		paper.set_corner_radius_all(3)
		paper.corner_radius_top_left = 10 if side == 0 else 2
		paper.corner_radius_bottom_left = 10 if side == 0 else 2
		paper.corner_radius_top_right = 2 if side == 0 else 10
		paper.corner_radius_bottom_right = 2 if side == 0 else 10
		paper.set_content_margin_all(20)
		page.add_theme_stylebox_override("panel", paper)
		page.custom_minimum_size = Vector2(330, 400)
		var pv := VBoxContainer.new()
		var text := RichTextLabel.new()
		text.bbcode_enabled = false
		text.fit_content = false
		text.scroll_active = false
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(290, 330)
		text.add_theme_color_override("default_color", INK)
		text.add_theme_font_size_override("normal_font_size", 15)
		text.add_theme_constant_override("line_separation", 3)
		pv.add_child(text)
		var num: Label = hud._label("", 12, Color(INK, 0.55))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		pv.add_child(num)
		page.add_child(pv)
		_spread_box.add_child(page)
		_pages.append(text)
		_nums.append(num)
	right.add_child(_spread_box)
	# a book seen from the shelf: its cover and blurb
	_cover_box = PanelContainer.new()
	_cover_box.custom_minimum_size = Vector2(664, 400)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 14)
	_cover_title = hud._label("", 26, Color(1.0, 0.86, 0.5))
	_cover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cover_title.custom_minimum_size = Vector2(560, 0)
	cv.add_child(_cover_title)
	_cover_blurb = hud._label("", 16, Color(1.0, 0.95, 0.85))
	_cover_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cover_blurb.custom_minimum_size = Vector2(520, 0)
	cv.add_child(_cover_blurb)
	_take = hud._button("Sit down with it", _take_it)
	_take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_take.custom_minimum_size = Vector2(220, 40)
	cv.add_child(_take)
	_cover_box.add_child(cv)
	right.add_child(_cover_box)
	var turn := HBoxContainer.new()
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	turn.add_theme_constant_override("separation", 16)
	_prev = hud._button("◀", turn_page.bind(-1))
	_prev.custom_minimum_size = Vector2(70, 34)
	turn.add_child(_prev)
	_where = hud._label("", 14, TEXT)
	_where.custom_minimum_size = Vector2(170, 0)
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn.add_child(_where)
	_next = hud._button("▶", turn_page.bind(1))
	_next.custom_minimum_size = Vector2(70, 34)
	turn.add_child(_next)
	right.add_child(turn)
	row.add_child(right)
	var close_btn: Button = hud._button("Put the book down", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(200, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


func books() -> Array:
	return _books


func book(id: String) -> Dictionary:
	for b in _books:
		if str(b["id"]) == id:
			return b
	return {}


## Opens on book `id` (or the one she last read, else the first). `pick`: from a bookshelf, to
## choose one to sit down with, so the right shows the cover rather than the pages.
func open(id := "", pick := false) -> void:
	hud.click("ui_open")
	pick_mode = pick
	pages_read = 0
	finished = []
	_title.text = "Choose a book" if pick else "Books"
	if id == "" or book(id).is_empty():
		id = str(Game.flag("book_last", ""))
	if book(id).is_empty() and not _books.is_empty():
		id = str(_books[0]["id"])
	visible = true
	move_to_front()
	show_book(id)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Opens book `id` where she left off (or at the start, if she finished it).
func show_book(id: String) -> void:
	current = id
	var b := book(id)
	if b.is_empty():
		_fill_list()
		return
	var mark := _mark(id)
	spread = int(mark.get("page", 0))
	if bool(mark.get("done", false)) and spread >= (b["pages"] as Array).size() - 2:
		spread = 0
	spread -= spread % 2
	if not pick_mode:
		Game.set_flag("book_last", id)
	_show()


## Turns the page forward (dir 1) or back (-1), a spread at a time.
func turn_page(dir: int) -> void:
	var b := book(current)
	if b.is_empty() or pick_mode:
		return
	var n: int = (b["pages"] as Array).size()
	var to := clampi(spread + 2 * dir, 0, maxi(0, (n - 1) - (n - 1) % 2))
	if to == spread:
		return
	hud.click("ui_click")
	spread = to
	if dir > 0:
		pages_read += 2
	_show()


## The arrow keys turn the pages while it's open (main.gd _input asks first).
func handle_key(kc: int) -> bool:
	if not visible:
		return false
	match kc:
		KEY_RIGHT, KEY_PAGEDOWN, KEY_SPACE:
			turn_page(1)
			return true
		KEY_LEFT, KEY_PAGEUP:
			turn_page(-1)
			return true
	return false


## How far she has got in each book: id -> {"page": the left page she was on, "done": finished}.
func _mark(id: String) -> Dictionary:
	var all: Dictionary = Game.flag("books", {})
	return all.get(id, {})


func _save_mark(id: String, page: int, done: bool) -> void:
	var all: Dictionary = (Game.flag("books", {}) as Dictionary).duplicate(true)
	var m: Dictionary = all.get(id, {})
	m["page"] = page
	m["done"] = done or bool(m.get("done", false))
	all[id] = m
	Game.set_flag("books", all)


func _show() -> void:
	var b := book(current)
	var pages: Array = b["pages"]
	var n := pages.size()
	_head.text = str(b["title"])
	_byline.text = "%s  ·  %s" % [b["author"], GENRE.get(str(b["genre"]), str(b["genre"]))]
	_spread_box.visible = not pick_mode
	_cover_box.visible = pick_mode
	_prev.visible = not pick_mode
	_next.visible = not pick_mode
	if pick_mode:
		var cs := StyleBoxFlat.new()
		cs.bg_color = COVER.get(str(b.get("cover", "plum")), COVER["plum"])
		cs.border_color = Color(0.85, 0.66, 0.3)
		cs.set_border_width_all(4)
		cs.set_corner_radius_all(8)
		cs.set_content_margin_all(30)
		_cover_box.add_theme_stylebox_override("panel", cs)
		_cover_title.text = "%s\n%s" % [b["title"], b["author"]]
		_cover_blurb.text = str(b.get("blurb", ""))
		var m := _mark(current)
		_where.text = "%d pages%s" % [n, "  ·  read ✓" if bool(m.get("done", false)) else ("  ·  on page %d" % (int(m["page"]) + 1) if int(m.get("page", 0)) > 0 else "")]
	else:
		for side in 2:
			var i := spread + side
			_pages[side].text = str(pages[i]) if i < n else ""
			_nums[side].text = str(i + 1) if i < n else ""
		var last := mini(spread + 2, n)
		_where.text = "Pages %d–%d of %d" % [spread + 1, last, n] if last > spread + 1 else "Page %d of %d" % [spread + 1, n]
		_prev.disabled = spread == 0
		_next.disabled = spread + 2 >= n
		var done := last >= n
		if done and not bool(_mark(current).get("done", false)):
			finished.append(current)
		_save_mark(current, spread, done)
		if done:
			_where.text += "  ·  The End"
	_fill_list()


func _take_it() -> void:
	if current != "":
		picked.emit(current)


func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for b in _books:
		var id := str(b["id"])
		var m := _mark(id)
		var state := "  ✓" if bool(m.get("done", false)) else ("  · p.%d" % (int(m["page"]) + 1) if int(m.get("page", 0)) > 0 else "")
		var btn: Button = hud._button("%s\n%s%s" % [b["title"], GENRE.get(str(b["genre"]), ""), state], show_book.bind(id))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(246, 50)
		btn.clip_text = true
		btn.add_theme_color_override("font_color", GENRE_COLOUR.get(str(b["genre"]), TEXT) if id != current else Color(1, 0.9, 0.6))
		if id == current:
			btn.modulate = Color(1.15, 1.05, 0.8)
		_list.add_child(btn)
