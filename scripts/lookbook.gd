## The Lookbook (Menu > Lookbook; Alex approved 2026-11-18): the fifty sweater designs in
## data/sweaters.json, by stars, each with a crop of its own colour map (assets/sweaters/textures/),
## knitted or not. A design she has knitted is one in Game.wardrobe; one she hasn't is dimmed and
## nameless. The count is at the top. Every line is a DRAFT until Alex approves it.
extends PanelContainer

const Sweaters = preload("res://scripts/sweaters.gd")
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)
const DIM := Color(0.55, 0.5, 0.45)
const STAR_NAMES := ["", "Common", "Rare", "Ultra rare", "Legendary"] # the designs' stars (sweaters.json)
const CROP := Rect2(40, 40, 220, 220) # a square of the front panel of the colour map (1024 x 512)

var hud: Node
var _count: Label
var _body: VBoxContainer
var _tex := {} # design -> AtlasTexture, loaded the first time the book opens


func setup(h: Node) -> void:
	hud = h
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(hud._label("Lookbook", 24, GOLD))
	_count = hud._label("", 15)
	vb.add_child(_count)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(860, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	vb.add_child(sc)
	var close_btn: Button = hud._button("Close", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


## How many designs she has knitted, and how many there are.
static func knitted() -> int:
	var n := 0
	for d in Sweaters.designs():
		if Game.wardrobe.has(str(d["id"])):
			n += 1
	return n


func open() -> void:
	hud.click("ui_open")
	visible = true
	move_to_front()
	refresh()


func close() -> void:
	visible = false


func _thumb(id: String) -> Texture2D:
	if not _tex.has(id):
		var path := Sweaters.TEX + id + ".png"
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t == null:
			_tex[id] = null
		else:
			var a := AtlasTexture.new()
			a.atlas = t
			a.region = CROP
			_tex[id] = a
	return _tex[id]


func refresh() -> void:
	var all: Array = Sweaters.designs()
	_count.text = "Knitted %d of %d designs" % [knitted(), all.size()]
	for c in _body.get_children():
		c.queue_free()
	for stars in range(1, 5):
		var ds := all.filter(func(d): return int(d["stars"]) == stars)
		if ds.is_empty():
			continue
		_body.add_child(hud._label("%s  (%s)" % [STAR_NAMES[stars], "*".repeat(stars)], 17, GOLD))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		for d in ds:
			row.add_child(_card(d))
		_body.add_child(row)


func _card(d: Dictionary) -> Control:
	var id := str(d["id"])
	var have := Game.wardrobe.has(id)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.custom_minimum_size = Vector2(96, 0)
	var t := _thumb(id)
	if t != null:
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(88, 88)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = t
		pic.modulate = Color.WHITE if have else Color(0.3, 0.28, 0.27, 0.8)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(pic)
	else: # no colour map: a swatch of its colours
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(88, 88)
		var cs: Array = d.get("colours", ["#888888"])
		sw.color = Color.html(str(cs[0])) if have else Color(0.25, 0.23, 0.22)
		vb.add_child(sw)
	var l: Label = hud._label(str(d.get("name", id)) if have else "???", 11, TEXT if have else DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(96, 0)
	vb.add_child(l)
	vb.tooltip_text = str(d.get("about", "")) if have else ""
	return vb
