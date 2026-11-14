extends Control
## The knitting game: a rhythm game played to a song. Balls of yarn roll down four lanes towards four
## knitting needles; press the lane's key (D F J K, or the arrow keys) as one reaches its needle, and
## hold the key down along a strand of yarn until it ends. Every stitch you make is knitted into a
## swatch beside the playfield, and how well you do decides how rare the sweater is.
##
## Rarity (Common, Uncommon, Rare, Epic, Legendary) comes from your accuracy, but each song can only
## give up to its own highest rarity: the easy song tops out at Rare, the harder ones go higher (CAPS).
## Songs are charts in data/songs/*.json made by tools/make_chart.py from the audio.
##
## main.gd opens it (open), and gets `finished` with the result. The tests play it by itself
## (opts "auto") and fast (opts "fast": the clock runs that many times quicker and there's no sound).

signal finished(result: Dictionary) # {"song", "difficulty", "accuracy", "rarity", "score", "max_combo", "counts", "cancelled"}
signal stitched(grade: int) # a stitch was made: 0 perfect, 1 great, 2 good

const Keys = preload("res://scripts/keybinds.gd")
const LANES := 4
const LANE_KEYS := [[KEY_D, KEY_LEFT], [KEY_F, KEY_DOWN], [KEY_J, KEY_UP], [KEY_K, KEY_RIGHT]]
const LANE_LETTERS := ["D", "F", "J", "K"]
const LANE_COLORS := [Color("a12b26"), Color("596b8c"), Color("9eae8f"), Color("e8b23a")] # plaid, denim, sage, sunflower
const CREAM := Color("edddbd")
const CHARCOAL := Color("2b2826")
const BRASS := Color("d9a84d")
const RARITIES := [
	{"id": "common", "name": "Common", "color": Color("c2b8a6")},
	{"id": "uncommon", "name": "Uncommon", "color": Color("8cc07a")},
	{"id": "rare", "name": "Rare", "color": Color("6f95d4")},
	{"id": "epic", "name": "Epic", "color": Color("b07ad8")},
	{"id": "legendary", "name": "Legendary", "color": Color("f2cc75")},
]
## How close to the beat counts: perfect, great, good (seconds either side).
const WINDOW := [0.05, 0.095, 0.14]
const CREDIT := [1.0, 0.7, 0.4] # how much of a full hit each grade is worth to the accuracy
const GRADE_NAMES := ["Perfect", "Great", "Good"]
## The highest rarity each difficulty can reach: harder songs have more to give.
const CAPS := {1: 3, 2: 4, 3: 5, 4: 5}
## The accuracy needed for Common, Uncommon, Rare, Epic, Legendary on each difficulty.
const THRESHOLDS := {
	1: [0.0, 0.60, 0.80, 0.90, 0.97],
	2: [0.0, 0.60, 0.78, 0.90, 0.96],
	3: [0.0, 0.58, 0.76, 0.88, 0.95],
	4: [0.0, 0.55, 0.72, 0.85, 0.93],
}
const LEAD_IN := 2.5
const FIELD_X := 150.0 # the playfield, in a 1280 x 720 design space
const LANE_W := 104.0
const HIT_Y := 590.0
const TOP_Y := 110.0
const SWATCH := Rect2(790, 170, 400, 360)

enum State { SELECT, PLAYING, PAUSED, RESULT }

var active := false
var state := State.SELECT
var songs: Array = []
var sel := 0
var best := {} # song id -> best rarity so far (set by main)
var auto := false # plays itself perfectly (the tests)
var fast := 1.0 # clock speed: the tests run it many times faster
var silent := false # no song plays (the tests)
var offset_ms := 0 # your timing offset, kept in settings.cfg

var song: Dictionary = {}
var notes: Array = []
var lane_notes: Array = [[], [], [], []] # note indices per lane, in time order
var ptr: Array = [0, 0, 0, 0] # the first note in each lane not yet hit or missed
var holding: Array = [-1, -1, -1, -1]
var down: Array = [false, false, false, false]
var glow: Array = [0.0, 0.0, 0.0, 0.0]
var now := 0.0 # song time in seconds; negative during the lead-in
var events := 0 # stitches to make in all: a tap is one, a hold is two (start and end)
var credit := 0.0
var score := 0
var combo := 0
var max_combo := 0
var counts: Array = [0, 0, 0, 0] # perfect, great, good, dropped
var stitches: Array = [] # {lane, grade} in the order made; grade -1 is a dropped stitch
var popups: Array = [] # {text, lane, t, color}
var result: Dictionary = {}
var _player: AudioStreamPlayer
var _started := false
var _clock := 0.0
var _result_t := 0.0
var _new_best := false
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = ThemeDB.fallback_font
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		offset_ms = int(cfg.get_value("knit", "offset_ms", 0))


# --- rarity ---------------------------------------------------------------------

## 1..5 (Common..Legendary) for an accuracy (0..1) on a difficulty: the highest rarity whose bar
## you cleared, but never above what that difficulty can give.
static func rarity_for(accuracy: float, difficulty: int) -> int:
	var th: Array = THRESHOLDS.get(difficulty, THRESHOLDS[1])
	var r := 1
	for i in th.size():
		if accuracy >= float(th[i]):
			r = i + 1
	return mini(r, max_rarity(difficulty))


static func max_rarity(difficulty: int) -> int:
	return int(CAPS.get(difficulty, 3))


static func rarity_name(r: int) -> String:
	return str(RARITIES[clampi(r, 1, 5) - 1]["name"])


static func rarity_color(r: int) -> Color:
	return RARITIES[clampi(r, 1, 5) - 1]["color"]


## Every song with a chart in data/songs, easiest first.
static func load_songs() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/songs"):
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/songs/" + f))
		if d is Dictionary and d.has("notes"):
			out.append(d)
	out.sort_custom(func(a, b): return int(a["difficulty"]) < int(b["difficulty"]) or (int(a["difficulty"]) == int(b["difficulty"]) and str(a["name"]) < str(b["name"])))
	return out


# --- opening and closing ----------------------------------------------------------

## Shows the song list (or starts opts.song at once). opts: best {song id: rarity}, auto, fast, song.
func open(opts: Dictionary = {}) -> void:
	songs = load_songs()
	best = opts.get("best", {})
	auto = bool(opts.get("auto", false))
	fast = float(opts.get("fast", 1.0))
	silent = bool(opts.get("silent", auto))
	active = true
	visible = true
	state = State.SELECT
	sel = 0
	if opts.has("song"):
		for i in songs.size():
			if songs[i]["id"] == opts["song"]:
				sel = i
	if songs.is_empty():
		_finish(true)
		return
	if opts.has("song"):
		_start(songs[sel])
	queue_redraw()


func _finish(cancelled: bool) -> void:
	active = false
	visible = false
	_player.stop()
	if cancelled:
		result = {"cancelled": true}
	finished.emit(result)


func _start(s: Dictionary) -> void:
	song = s
	notes = []
	lane_notes = [[], [], [], []]
	ptr = [0, 0, 0, 0]
	holding = [-1, -1, -1, -1]
	down = [false, false, false, false]
	events = 0
	for n in s["notes"]:
		var d := {"t": float(n[0]), "lane": int(n[1]), "hold": float(n[2]), "state": 0}
		lane_notes[d["lane"]].append(notes.size())
		notes.append(d)
		events += 2 if d["hold"] > 0.0 else 1
	credit = 0.0
	score = 0
	combo = 0
	max_combo = 0
	counts = [0, 0, 0, 0]
	stitches = []
	popups = []
	now = -LEAD_IN
	_started = false
	_clock = 0.0
	state = State.PLAYING
	var stream = load(str(s["audio"])) if (not silent and ResourceLoader.exists(str(s["audio"]))) else null
	_player.stream = stream as AudioStream
	queue_redraw()


# --- input -------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if not active or not (e is InputEventKey) or auto:
		return
	var k := e as InputEventKey
	var kc := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	var lane := _lane_of(Keys.map(kc, ["knit"])) # the lanes' keys as the player bound them
	match state:
		State.SELECT:
			if not k.pressed:
				return
			match kc:
				KEY_UP, KEY_W:
					sel = (sel + songs.size() - 1) % songs.size()
				KEY_DOWN, KEY_S:
					sel = (sel + 1) % songs.size()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_start(songs[sel])
				KEY_ESCAPE:
					_finish(true)
				KEY_BRACKETLEFT, KEY_MINUS:
					_set_offset(offset_ms - 10)
				KEY_BRACKETRIGHT, KEY_EQUAL:
					_set_offset(offset_ms + 10)
				_:
					return
			get_viewport().set_input_as_handled()
			queue_redraw()
		State.PLAYING:
			if kc == KEY_ESCAPE and k.pressed and not k.echo:
				_pause(true)
			elif lane >= 0 and not k.echo:
				if k.pressed:
					press(lane)
				else:
					release(lane)
			get_viewport().set_input_as_handled()
		State.PAUSED:
			if k.pressed and not k.echo:
				if kc in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
					_pause(false)
				elif kc in [KEY_ESCAPE, KEY_Q]:
					_finish(true)
			get_viewport().set_input_as_handled()
		State.RESULT:
			if k.pressed and not k.echo and kc in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
				_finish(false)
			get_viewport().set_input_as_handled()


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if not active or auto or mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if state == State.SELECT:
		var p := _to_design(mb.position)
		for i in songs.size():
			if Rect2(240, 150 + i * 120, 800, 100).has_point(p):
				if sel == i:
					_start(songs[i])
				sel = i
		queue_redraw()
	elif state == State.RESULT:
		_finish(false)


func _lane_of(kc: int) -> int:
	for l in LANES:
		if kc in LANE_KEYS[l]:
			return l
	return -1


func _set_offset(v: int) -> void:
	offset_ms = clampi(v, -200, 200)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("knit", "offset_ms", offset_ms)
	cfg.save("user://settings.cfg")


func _pause(on: bool) -> void:
	state = State.PAUSED if on else State.PLAYING
	_player.stream_paused = on
	for l in LANES:
		down[l] = false
	queue_redraw()


# --- playing ---------------------------------------------------------------------------

## A key goes down in a lane: hit the nearest note that's close enough to its needle.
func press(lane: int) -> void:
	down[lane] = true
	glow[lane] = 1.0
	if state != State.PLAYING:
		return
	var i := _pending(lane)
	if i < 0:
		return
	var n: Dictionary = notes[i]
	var err := absf(float(n["t"]) - now)
	if err > WINDOW[2]:
		return # too early to count: it's still on its way
	var g := 0 if err <= WINDOW[0] else (1 if err <= WINDOW[1] else 2)
	ptr[lane] += 1
	_make_stitch(lane, g)
	if float(n["hold"]) > 0.0:
		n["state"] = 2
		holding[lane] = i
	else:
		n["state"] = 1


## A key comes up: it ends a hold.
func release(lane: int) -> void:
	down[lane] = false
	if state != State.PLAYING or holding[lane] < 0:
		return
	var n: Dictionary = notes[holding[lane]]
	var end := float(n["t"]) + float(n["hold"])
	var err := absf(end - now)
	holding[lane] = -1
	if now < end and err > WINDOW[2] * 1.2:
		n["state"] = 4 # let go too soon: the strand breaks
		_drop(lane)
	else:
		n["state"] = 1
		_make_stitch(lane, 0 if err <= WINDOW[0] else (1 if err <= WINDOW[1] else 2))


func _pending(lane: int) -> int:
	var list: Array = lane_notes[lane]
	return int(list[ptr[lane]]) if ptr[lane] < list.size() else -1


func _make_stitch(lane: int, grade: int) -> void:
	credit += CREDIT[grade]
	counts[grade] += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	score += int(round(300.0 * CREDIT[grade] * (1.0 + minf(combo, 40) * 0.025)))
	stitches.append({"lane": lane, "grade": grade})
	popups.append({"text": GRADE_NAMES[grade], "lane": lane, "t": _clock, "color": CREAM if grade == 0 else (Color("c9d8b0") if grade == 1 else Color("c2b8a6"))})
	stitched.emit(grade)


func _drop(lane: int) -> void:
	counts[3] += 1
	combo = 0
	stitches.append({"lane": lane, "grade": -1})
	popups.append({"text": "Dropped", "lane": lane, "t": _clock, "color": Color("d98a7a")})


func _process(delta: float) -> void:
	if not active:
		return
	for l in LANES:
		glow[l] = maxf(0.0, glow[l] - delta * 4.0)
	if state == State.PLAYING:
		var left := delta * fast
		_clock += left
		while state == State.PLAYING: # in small steps, so a fast clock still judges every note on time
			var step := minf(left, 0.016)
			_advance(step)
			_judge_missed()
			if auto:
				_autoplay()
			if now > float(song["length"]) + 0.8 or (now > _last_time() + 1.6):
				_end_song()
			left -= step
			if left <= 0.0:
				break
	elif state == State.RESULT:
		_result_t += delta
		if auto and _result_t > 0.2:
			_finish(false)
	queue_redraw()


func _last_time() -> float:
	var t := 0.0
	for n in notes:
		t = maxf(t, float(n["t"]) + float(n["hold"]))
	return t


func _advance(step: float) -> void:
	if not _started and now + step >= 0.0:
		_started = true
		if _player.stream != null and not silent and fast <= 1.0:
			_player.play()
	if _started and _player.playing:
		# follow the sound itself, so the notes line up with what you hear
		var ap := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - offset_ms / 1000.0
		now = lerpf(now + step, ap, 0.3)
	else:
		now += step


func _judge_missed() -> void:
	for lane in LANES:
		var list: Array = lane_notes[lane]
		while ptr[lane] < list.size():
			var n: Dictionary = notes[list[ptr[lane]]]
			if float(n["t"]) + WINDOW[2] >= now:
				break
			ptr[lane] += 1
			n["state"] = 4
			_drop(lane)
			if float(n["hold"]) > 0.0:
				_drop(lane) # a hold is two stitches: start and end
		var h: int = holding[lane]
		if h >= 0:
			var hn: Dictionary = notes[h]
			var end := float(hn["t"]) + float(hn["hold"])
			if now >= end + 0.1 or (auto and now >= end):
				holding[lane] = -1
				hn["state"] = 1
				_make_stitch(lane, 0)
			elif not down[lane] and now < end - WINDOW[2]:
				holding[lane] = -1 # the key is up before the end
				hn["state"] = 4
				_drop(lane)


func _autoplay() -> void:
	for lane in LANES:
		var i := _pending(lane)
		if i >= 0 and float(notes[i]["t"]) <= now:
			press(lane)
		if holding[lane] >= 0:
			down[lane] = true


func _end_song() -> void:
	var accuracy := credit / float(maxi(events, 1))
	var diff := int(song["difficulty"])
	var r := rarity_for(accuracy, diff)
	_new_best = r > int(best.get(str(song["id"]), 0))
	result = {
		"song": song["id"], "name": song["name"], "difficulty": diff, "accuracy": accuracy, "rarity": r, "score": score,
		"max_combo": max_combo, "counts": counts.duplicate(), "cancelled": false, "new_best": _new_best,
	}
	_player.stop()
	state = State.RESULT
	_result_t = 0.0


## The rarity you're on course for right now (from your accuracy so far).
func rarity_now() -> int:
	var played := 0
	for n in notes:
		if n["state"] != 0:
			played += 2 if float(n["hold"]) > 0.0 else 1
	if played == 0:
		return max_rarity(int(song.get("difficulty", 1)))
	return rarity_for(credit / float(played), int(song["difficulty"]))


# --- drawing -----------------------------------------------------------------------------

func _scale() -> float:
	return minf(size.x / 1280.0, size.y / 720.0)


func _to_design(p: Vector2) -> Vector2:
	var s := _scale()
	return (p - (size - Vector2(1280, 720) * s) * 0.5) / s


func _draw() -> void:
	if not active:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.08, 0.075, 0.97))
	var s := _scale()
	draw_set_transform((size - Vector2(1280, 720) * s) * 0.5, 0.0, Vector2(s, s))
	match state:
		State.SELECT:
			_draw_select()
		State.RESULT:
			_draw_play()
			_draw_result()
		_:
			_draw_play()
			if state == State.PAUSED:
				draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.55))
				_text("Paused", Vector2(640, 330), 52, CREAM, 1)
				_text("Enter to carry on · Esc to put it down", Vector2(640, 390), 22, Color(0.85, 0.8, 0.7), 1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text(t: String, pos: Vector2, fs: int, c: Color, align := 0) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos - Vector2(w * (0.5 if align == 1 else (1.0 if align == 2 else 0.0)), 0)
	draw_string(_font, p + Vector2(2, 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _felt(r: Rect2, c: Color, border: Color) -> void:
	draw_rect(r, c)
	draw_rect(r, border, false, 3.0)
	var x := r.position.x + 8.0
	while x < r.end.x - 8.0: # a running stitch just inside the edge
		draw_line(Vector2(x, r.position.y + 7), Vector2(x + 7, r.position.y + 7), border.lightened(0.2), 1.5)
		draw_line(Vector2(x, r.end.y - 7), Vector2(x + 7, r.end.y - 7), border.lightened(0.2), 1.5)
		x += 14.0


func _yarn_ball(c: Vector2, r: float, col: Color, a := 1.0) -> void:
	var base := Color(col.r, col.g, col.b, a)
	draw_circle(c, r, base)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, Color(1, 1, 1, 0.16 * a))
	var dark := Color(col.darkened(0.35).r, col.darkened(0.35).g, col.darkened(0.35).b, a)
	for k in 3: # the strands wound round it
		draw_arc(c, r * (0.78 - k * 0.2), 0.35 + k * 1.1, 2.6 + k * 1.1, 14, dark, 2.2)
	draw_arc(c, r, 0.0, TAU, 24, dark, 2.5)


func _draw_play() -> void:
	var diff := int(song.get("difficulty", 1))
	_text(str(song.get("name", "")), Vector2(FIELD_X, 62), 34, CREAM)
	_text("%d BPM · difficulty %s" % [int(song.get("bpm", 0)), "●".repeat(diff) + "○".repeat(4 - diff)], Vector2(FIELD_X, 92), 16, Color(0.85, 0.8, 0.7))
	var field := Rect2(FIELD_X - 20, TOP_Y - 10, LANE_W * LANES + 40, HIT_Y - TOP_Y + 90)
	_felt(field, Color(0.2, 0.16, 0.14), Color("5c1717"))
	var approach := float(song.get("approach", 1.6))
	for l in LANES:
		var cx := FIELD_X + LANE_W * (l + 0.5)
		var lane_col: Color = LANE_COLORS[l]
		draw_rect(Rect2(cx - LANE_W * 0.5 + 4, TOP_Y, LANE_W - 8, HIT_Y - TOP_Y + 20), Color(lane_col.r, lane_col.g, lane_col.b, 0.07 + 0.2 * glow[l]))
		var y := TOP_Y # a dashed stitch line down the middle of the lane
		while y < HIT_Y:
			draw_line(Vector2(cx, y), Vector2(cx, minf(y + 8, HIT_Y)), Color(CREAM.r, CREAM.g, CREAM.b, 0.16), 2.0)
			y += 18.0
	# the notes
	for n in notes:
		var t := float(n["t"])
		if t - now > approach + 0.3 or t + float(n["hold"]) < now - 0.4:
			continue
		var lane := int(n["lane"])
		var cx := FIELD_X + LANE_W * (lane + 0.5)
		var col: Color = LANE_COLORS[lane]
		var st := int(n["state"])
		var a := 0.3 if st == 4 else 1.0
		var y_of := func(tt: float) -> float: return HIT_Y - (tt - now) / approach * (HIT_Y - TOP_Y)
		var y_head: float = y_of.call(t)
		if float(n["hold"]) > 0.0:
			var y_tail: float = maxf(TOP_Y, y_of.call(t + float(n["hold"])))
			var y_low: float = minf(y_head, HIT_Y) if st != 2 else HIT_Y
			if y_low > y_tail:
				draw_rect(Rect2(cx - 13, y_tail, 26, y_low - y_tail), Color(col.r, col.g, col.b, 0.8 * a))
				var yy := y_tail + 4
				while yy < y_low - 4:
					draw_line(Vector2(cx - 9, yy), Vector2(cx + 9, yy + 5), Color(1, 1, 1, 0.22 * a), 2.0)
					yy += 11.0
		if st == 1:
			continue # a tap that's been knitted is gone
		var py := y_head if st != 2 else HIT_Y
		if py > TOP_Y - 30 and py < HIT_Y + 60:
			_yarn_ball(Vector2(cx, py), 27.0, col, a)
	# the needles
	for l in LANES:
		var cx := FIELD_X + LANE_W * (l + 0.5)
		var c: Color = LANE_COLORS[l].lightened(0.35) if down[l] else BRASS
		draw_rect(Rect2(cx - 46, HIT_Y + 22, 92, 12), c)
		draw_circle(Vector2(cx - 46, HIT_Y + 28), 8.0, c.lightened(0.15))
		draw_circle(Vector2(cx + 46, HIT_Y + 28), 8.0, c.lightened(0.15))
		draw_arc(Vector2(cx, HIT_Y), 34.0, 0.0, TAU, 28, Color(CREAM.r, CREAM.g, CREAM.b, 0.35 + 0.5 * glow[l]), 3.0)
		_text(Keys.key_name(Keys.bound("lane_%d" % (l + 1))), Vector2(cx, HIT_Y + 78), 24, LANE_COLORS[l].lightened(0.3), 1)
	# what you've just done, over each needle
	for p in popups:
		var age: float = (_clock - float(p["t"])) / fast_div()
		if age < 0.0 or age > 0.7:
			continue
		var cx := FIELD_X + LANE_W * (int(p["lane"]) + 0.5)
		var col: Color = p["color"]
		_text(str(p["text"]), Vector2(cx, HIT_Y - 44 - age * 40), 18, Color(col.r, col.g, col.b, 1.0 - age / 0.7), 1)
	while popups.size() > 12:
		popups.pop_front()
	if state == State.PLAYING and now < 0.0:
		_text(str(ceili(-now)), Vector2(FIELD_X + LANE_W * 2, 340), 96, Color(CREAM.r, CREAM.g, CREAM.b, 0.9), 1)
	# the readout and the swatch
	var acc := credit / float(maxi(1, _played_events()))
	_text("%d" % score, Vector2(1190, 62), 40, CREAM, 2)
	_text("%.1f%% accuracy" % (acc * 100.0 if _played_events() > 0 else 100.0), Vector2(1190, 92), 18, Color(0.85, 0.8, 0.7), 2)
	if combo >= 3:
		_text("%d in a row" % combo, Vector2(FIELD_X + LANE_W * 2, 200), 30, Color(CREAM.r, CREAM.g, CREAM.b, 0.85), 1)
	var prog := clampf(now / maxf(float(song.get("length", 1.0)), 1.0), 0.0, 1.0)
	draw_rect(Rect2(790, 112, 400, 14), Color(0.22, 0.18, 0.15))
	draw_rect(Rect2(790, 112, 400 * prog, 14), BRASS)
	var rn := rarity_now()
	# one line between the progress bar and the swatch, so nothing sits on the knitting
	_text("Heading for", Vector2(790, 150), 16, Color(0.85, 0.8, 0.7))
	_text(rarity_name(rn), Vector2(790 + _font.get_string_size("Heading for", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 10.0, 150), 22, rarity_color(rn))
	_text("this pattern: up to %s" % rarity_name(max_rarity(diff)), Vector2(1190, 150), 14, Color(0.7, 0.66, 0.58), 2)
	_draw_swatch()


func fast_div() -> float:
	return maxf(fast, 1.0)


func _played_events() -> int:
	return counts[0] + counts[1] + counts[2] + counts[3]


## The knit: a stitch for each one you make, row on row, in the lane's colour; a dropped one leaves a hole.
func _draw_swatch() -> void:
	_felt(SWATCH.grow(10), Color(0.93, 0.87, 0.74, 0.1), Color("5c1717"))
	var cols := 14
	var rows := maxi(ceili(float(maxi(events, 1)) / cols), 1)
	var cell := minf(SWATCH.size.x / cols, SWATCH.size.y / rows)
	var origin := SWATCH.position + Vector2((SWATCH.size.x - cell * cols) * 0.5, 0)
	for i in stitches.size():
		var s: Dictionary = stitches[i]
		var c := origin + Vector2((i % cols + 0.5) * cell, (i / cols + 0.5) * cell)
		if int(s["grade"]) < 0:
			draw_circle(c, cell * 0.14, Color(0.05, 0.04, 0.04, 0.8))
			continue
		var col: Color = LANE_COLORS[int(s["lane"])]
		if int(s["grade"]) == 0:
			col = col.lightened(0.18)
		var w := cell * 0.3
		draw_line(c + Vector2(-w * 0.9, -cell * 0.3), c + Vector2(0, cell * 0.32), col, cell * 0.26)
		draw_line(c + Vector2(w * 0.9, -cell * 0.3), c + Vector2(0, cell * 0.32), col, cell * 0.26)
		draw_line(c + Vector2(-w * 0.9, -cell * 0.3), c + Vector2(0, cell * 0.32), Color(1, 1, 1, 0.18), cell * 0.07)


func _draw_select() -> void:
	_text("Choose a pattern", Vector2(640, 90), 46, CREAM, 1)
	_text("Harder patterns can knit rarer sweaters", Vector2(640, 124), 18, Color(0.85, 0.8, 0.7), 1)
	for i in songs.size():
		var s: Dictionary = songs[i]
		var r := Rect2(240, 150 + i * 120, 800, 100)
		var diff := int(s["difficulty"])
		_felt(r, Color(0.24, 0.19, 0.16) if i != sel else Color(0.33, 0.24, 0.18), BRASS if i == sel else Color("5c1717"))
		_text(str(s["name"]), Vector2(r.position.x + 30, r.position.y + 46), 32, CREAM)
		_text("%d BPM · %d stitches" % [int(s["bpm"]), s["notes"].size()], Vector2(r.position.x + 30, r.position.y + 78), 16, Color(0.8, 0.75, 0.66))
		for k in 4:
			_yarn_ball(Vector2(r.position.x + 360 + k * 34, r.position.y + 36), 12.0, LANE_COLORS[k] if k < diff else Color(0.35, 0.3, 0.27), 1.0 if k < diff else 0.5)
		var cap := max_rarity(diff)
		_text("Up to %s" % rarity_name(cap), Vector2(r.end.x - 30, r.position.y + 42), 26, rarity_color(cap), 2)
		var b := int(best.get(str(s["id"]), 0))
		_text("Your best: %s" % (rarity_name(b) if b > 0 else "not yet"), Vector2(r.end.x - 30, r.position.y + 78), 16, rarity_color(b) if b > 0 else Color(0.7, 0.66, 0.58), 2)
	_text("↑ ↓ choose · Enter to knit · Esc to go back", Vector2(640, 650), 18, Color(0.85, 0.8, 0.7), 1)
	_text("Keys D F J K, or the arrow keys · timing %+d ms ( [ ] to change )" % offset_ms, Vector2(640, 678), 15, Color(0.7, 0.66, 0.58), 1)


func _draw_result() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.6))
	var r := Rect2(310, 130, 660, 470)
	_felt(r, Color(0.24, 0.19, 0.16), BRASS)
	var rar := int(result.get("rarity", 1))
	var col := rarity_color(rar)
	_text("%s sweater" % rarity_name(rar), Vector2(640, 215), 58, col, 1)
	if rar == 5:
		for k in 9: # a little shine for a Legendary
			var a := TAU * k / 9.0 + _result_t
			draw_circle(Vector2(640, 190) + Vector2(cos(a), sin(a)) * (250.0 + 12.0 * sin(_result_t * 3 + k)), 5.0, Color(col.r, col.g, col.b, 0.7))
	_text("%s · difficulty %d" % [result.get("name", ""), int(result.get("difficulty", 1))], Vector2(640, 252), 20, Color(0.85, 0.8, 0.7), 1)
	_text("%.1f%% accuracy" % (float(result.get("accuracy", 0.0)) * 100.0), Vector2(640, 320), 40, CREAM, 1)
	var c: Array = result.get("counts", [0, 0, 0, 0])
	_text("Perfect %d   Great %d   Good %d   Dropped %d" % [c[0], c[1], c[2], c[3]], Vector2(640, 368), 22, Color(0.9, 0.85, 0.76), 1)
	_text("Score %d   ·   Longest run %d" % [int(result.get("score", 0)), int(result.get("max_combo", 0))], Vector2(640, 408), 22, Color(0.9, 0.85, 0.76), 1)
	var cap := max_rarity(int(result.get("difficulty", 1)))
	if rar >= cap and cap < 5:
		_text("That's the most this pattern can give. Try a harder one!", Vector2(640, 462), 18, col, 1)
	elif bool(result.get("new_best", false)):
		_text("A new best on this pattern", Vector2(640, 462), 18, col, 1)
	_text("Press Enter", Vector2(640, 560), 24, BRASS, 1)
