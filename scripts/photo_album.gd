## The photo album (Menu > Photo album): every picture taken in cinematic mode (cinematic.gd) as
## a thumbnail; a click shows it full size, with the ones either side and a delete button.
extends PanelContainer

const Cinematic = preload("res://scripts/cinematic.gd")
const THUMB := Vector2(200, 125)
const COLS := 4
const GOLD := Color(0.95, 0.80, 0.46) # hud.gd's colours
const TEXT := Color(0.97, 0.93, 0.85)

var hud: Node # hud.gd, for its labels, buttons and sounds
var paths: Array[String] = [] # newest first
var current := -1 # the photo shown full size, or -1 for the thumbnails

var _count: Label
var _grid: GridContainer
var _empty: Label
var _scroll: ScrollContainer
var _viewer: VBoxContainer
var _big: TextureRect
var _caption: Label
var _delete_btn: Button


func setup(h: Node) -> void:
	hud = h
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_child(hud._label("Photo album", 24, GOLD))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_count = hud._label("", 14, Color(TEXT, 0.65))
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	vb.add_child(head)
	# the thumbnails
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(THUMB.x * COLS + 10 * (COLS - 1) + 14, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	vb.add_child(_scroll)
	_empty = hud._label("No photos yet. Press P to fly the camera, then F to take a picture.", 15, Color(TEXT, 0.7))
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_empty)
	# one photo, full size
	_viewer = VBoxContainer.new()
	_viewer.add_theme_constant_override("separation", 8)
	_big = TextureRect.new()
	_big.custom_minimum_size = _scroll.custom_minimum_size
	_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewer.add_child(_big)
	_caption = hud._label("", 13, Color(TEXT, 0.65))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_viewer.add_child(_caption)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(hud._button("< Newer", func(): show_photo(maxi(current - 1, 0))))
	row.add_child(hud._button("Older >", func(): show_photo(mini(current + 1, paths.size() - 1))))
	_delete_btn = hud._button("Delete", func(): pass)
	_delete_btn.pressed.connect(func(): hud._confirm_then(_delete_btn, "Click again to delete", delete_current))
	row.add_child(_delete_btn)
	row.add_child(hud._button("All photos", func(): show_photo(-1)))
	for b in row.get_children():
		(b as Button).custom_minimum_size = Vector2(150, 36)
	_viewer.add_child(row)
	_viewer.visible = false
	vb.add_child(_viewer)
	var close_btn: Button = hud._button("Close", close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(140, 36)
	vb.add_child(close_btn)
	add_child(vb)
	visible = false


func open() -> void:
	hud.click("ui_open")
	visible = true
	move_to_front()
	refresh()
	show_photo(-1)


func close() -> void:
	visible = false
	_big.texture = null
	for c in _grid.get_children():
		c.queue_free()


## Reads the folder again and lays out the thumbnails.
func refresh() -> void:
	paths = Cinematic.list_photos()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in paths.size():
		var b := TextureButton.new()
		b.custom_minimum_size = THUMB
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		b.texture_normal = _load(paths[i], THUMB * 2.0)
		b.tooltip_text = _title(paths[i])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): hud.click(); show_photo(i))
		_grid.add_child(b)
	_count.text = "%d photo%s" % [paths.size(), "" if paths.size() == 1 else "s"]
	_empty.visible = paths.is_empty()


## Shows photo i full size, or the thumbnails for -1 (or past either end).
func show_photo(i: int) -> void:
	if i < 0 or i >= paths.size():
		current = -1
		_big.texture = null
	else:
		current = i
		_big.texture = _load(paths[i], Vector2.ZERO)
		_caption.text = "%s   (%d of %d)" % [_title(paths[i]), i + 1, paths.size()]
	_viewer.visible = current >= 0
	_scroll.visible = current < 0
	_empty.visible = current < 0 and paths.is_empty()


func delete_current() -> void:
	if current < 0:
		return
	var i := current
	Cinematic.delete_photo(paths[i])
	refresh()
	show_photo(mini(i, paths.size() - 1))


## e.g. "12 Nov 2026, 2:05 PM  ·  Day 3, 7:30 AM" from the file's name.
func _title(path: String) -> String:
	var p := path.get_file().get_basename().split("_")
	if p.size() < 4:
		return path.get_file()
	var d := p[0].split("-")
	var t := p[1].split("-")
	if d.size() < 3 or t.size() < 2:
		return path.get_file()
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var h := int(t[0])
	var real := "%d %s %s, %d:%s %s" % [int(d[2]), months[clampi(int(d[1]) - 1, 0, 11)], d[0], 12 if h % 12 == 0 else h % 12, t[1], "AM" if h < 12 else "PM"]
	var game := "%s, %s" % ["Day " + p[2].trim_prefix("day"), p[3].replace("-", ":").to_upper().replace("AM", " AM").replace("PM", " PM")]
	return real + "  ·  " + game


static func _load(path: String, fit: Vector2) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if fit != Vector2.ZERO:
		var k := maxf(fit.x / img.get_width(), fit.y / img.get_height())
		if k < 1.0:
			img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)
