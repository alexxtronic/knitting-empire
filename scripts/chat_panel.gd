extends PanelContainer
## The chat window for typing to a villager (scripts/ai_chat.gd does the talking).
## Name and hearts on top, the conversation, a "thinking" line, and a box to type in.
## When there's no API key it shows a box to paste one (saved to user://ai.cfg, never the repo).

signal sent(text: String)
signal closed
signal key_entered(key: String)

const AiChat = preload("res://scripts/ai_chat.gd")
const GOLD := Color(0.95, 0.80, 0.46)
const TEXT := Color(0.97, 0.93, 0.85)
const MOOD_FACE := {"neutral": "", "happy": "smiling", "warm": "warmly", "wry": "wryly", "sad": "quietly", "worried": "worried", "surprised": "surprised"}

var hud
var log_label: RichTextLabel
var input: LineEdit
var send_btn: Button
var name_label: Label
var mood_label: Label
var thinking: Label
var hearts_box: HBoxContainer
var key_row: HBoxContainer
var key_input: LineEdit
var note: Label
var speaker := ""
var _think_t := 0.0


func build(h) -> void:
	hud = h
	custom_minimum_size = Vector2(560, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	name_label = hud._label("", 19, GOLD)
	top.add_child(name_label)
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 3)
	hearts_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 5:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(16, 16)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(hud.make_icon("heart_empty"))
		hearts_box.add_child(holder)
	top.add_child(hearts_box)
	mood_label = hud._label("", 13, Color(0.8, 0.74, 0.62))
	mood_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(mood_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close: Button = hud._button("Close", func(): closed.emit())
	close.custom_minimum_size = Vector2(72, 30)
	top.add_child(close)
	vb.add_child(top)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(540, 210)
	log_label.add_theme_font_size_override("normal_font_size", 15)
	log_label.add_theme_font_size_override("italics_font_size", 15)
	log_label.add_theme_color_override("default_color", TEXT)
	log_label.selection_enabled = true
	vb.add_child(log_label)
	thinking = hud._label("", 13, Color(0.8, 0.74, 0.62))
	thinking.custom_minimum_size = Vector2(0, 18)
	vb.add_child(thinking)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	input = LineEdit.new()
	input.max_length = AiChat.MAX_INPUT
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 36)
	input.text_submitted.connect(func(_t): _send())
	row.add_child(input)
	send_btn = hud._button("Say it", _send)
	send_btn.custom_minimum_size = Vector2(84, 36)
	row.add_child(send_btn)
	vb.add_child(row)
	note = hud._label("", 12, Color(0.8, 0.74, 0.62))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(540, 0)
	vb.add_child(note)
	key_row = HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	key_input = LineEdit.new()
	key_input.secret = true
	key_input.placeholder_text = "Paste your Anthropic API key (sk-ant-...)"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.text_submitted.connect(func(_t): _save_key())
	key_row.add_child(key_input)
	var save: Button = hud._button("Save key", _save_key)
	save.custom_minimum_size = Vector2(96, 32)
	key_row.add_child(save)
	vb.add_child(key_row)
	visible = false


func open(who: String, hearts: int, history: Array, online: bool) -> void:
	speaker = who
	name_label.text = who
	set_hearts(hearts)
	mood_label.text = ""
	log_label.clear()
	for m in history:
		_append(str(m["role"]), str(m["content"]))
	input.placeholder_text = "Say something to %s..." % who
	input.text = ""
	set_thinking(false)
	set_online(online)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	input.grab_focus.call_deferred()


func set_online(online: bool) -> void:
	key_row.visible = not online
	note.text = "" if online else AiChat.error_note("offline")


func set_hearts(hearts: int) -> void:
	for i in hearts_box.get_child_count():
		var ic = hearts_box.get_child(i).get_child(0)
		ic.set_kind("heart" if i < hearts else "heart_empty", TEXT)


func set_thinking(on: bool) -> void:
	thinking.visible = on
	input.editable = not on
	send_btn.disabled = on
	_think_t = 0.0
	if not on:
		thinking.text = ""


func add_line(role: String, text: String, mood := "") -> void:
	_append(role, text)
	if role == "assistant" and mood != "":
		mood_label.text = str(MOOD_FACE.get(mood, ""))


func show_note(text: String) -> void:
	note.text = text


func _append(role: String, raw: String) -> void:
	if role == "user":
		log_label.append_text("[color=#a9c98f]Nora:[/color] %s\n" % AiChat.to_bbcode(raw))
	else:
		var text: String = AiChat.split_mood(raw)[1]
		log_label.append_text("[color=#f2cc75]%s:[/color] %s\n" % [speaker, AiChat.to_bbcode(text)])


func transcript() -> String:
	return log_label.get_parsed_text()


func _send() -> void:
	var t := input.text.strip_edges()
	if t == "" or not input.editable:
		return
	input.text = ""
	sent.emit(t)


func _save_key() -> void:
	var k := key_input.text.strip_edges()
	key_input.text = ""
	if k != "":
		key_entered.emit(k)


func _process(delta: float) -> void:
	if visible and thinking.visible:
		_think_t += delta
		thinking.text = "%s is thinking%s" % [speaker, ".".repeat(1 + int(_think_t * 3.0) % 3)]
