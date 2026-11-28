extends Node
## Music, ambience and sound effects. The theme song, Sunset Lullaby (assets/audio/sunset_lullaby.mp3),
## is Alex's own track and loops in the background all game; every other sound comes from
## tools/make_audio.py (no samples or licences).
##
## Four buses under Master: Music, Ambience, SFX and Voice. The Settings panel sets Music, Sound
## (Ambience + SFX) and Voices, kept in user://settings.cfg with the graphics level. The autotest mutes it all.
##
## Voices (Alex, 2026-11-28): no recorded lines, a cartoon mumble as each line comes up. speak() strings
## a few CC0 syllables (assets/audio/voice/, dodrio on Freesound, tools/make_voice.py) pitched and paced
## per character from data/voices.json; the next line cuts the last one off.

const Data = preload("res://scripts/data.gd")
const DIR := "res://assets/audio/"
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_DB := -9.0
const AMB_DB := -7.0
const THEME := "sunset_lullaby.mp3" # Alex's own track (2026-11-15), looped under everything
const MUSIC_ON := true # the theme plays; the Settings panel's Music slider sets its loudness

var main: Node
var music: AudioStreamPlayer
var tune: AudioStreamPlayer # a story's one-off music cue (@music arrival), on the Music bus
var tune_name := "" # what it's playing ("" for nothing)
var amb := {} # "day" / "night" / "rain" -> AudioStreamPlayer
var music_volume := 0.7 # 0..1, from the Settings panel
var sound_volume := 0.8
var muted := false
var _gain := {"day": 0.0, "night": 0.0, "rain": 0.0, "music": 1.0}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _sfx := {} # "step_grass" -> [AudioStream, ...]
var _memory_fx := -1 # index of the low-pass on the Music bus, on during memory flashbacks
var played := {} # sound name -> times played (the autotest reads it)
var voice_volume := 0.8
var spoke := {} # voice id -> lines mumbled (the autotest reads it)
var last_voice := {} # the last line's id, pitch, gap and syllables (the autotest reads it)
var _voice_clips: Array[AudioStream] = []
var _voice_players: Array[AudioStreamPlayer] = []
var _voice_seq := 0
var _voices := {}


func setup(m: Node, mute := false) -> void:
	main = m
	muted = mute
	_make_buses()
	_load_settings()
	music = _player("Music", _loop(THEME))
	music.volume_db = MUSIC_DB
	tune = AudioStreamPlayer.new()
	tune.bus = "Music"
	add_child(tune)
	for k in ["day", "night", "rain"]:
		amb[k] = _player("Ambience", _loop("amb_%s.ogg" % k))
		amb[k].volume_db = -80.0
		amb[k].play()
	if MUSIC_ON:
		music.play()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for group in ["step_grass", "step_wood", "needle"]:
		_sfx[group] = []
		for i in range(1, 5):
			var path := DIR + "%s_%d.wav" % [group, i]
			if ResourceLoader.exists(path):
				_sfx[group].append(load(path))
	for one in ["ui_click", "ui_open", "journal", "coins", "flutter", "bark", "howl"]:
		if ResourceLoader.exists(DIR + one + ".wav"):
			_sfx[one] = [load(DIR + one + ".wav")]
	for i in range(1, 9):
		var vp := DIR + "voice/mumble_%d.wav" % i
		if ResourceLoader.exists(vp):
			_voice_clips.append(load(vp))
	for i in 3: # syllables overlap a little at the slow, low voices
		var p := AudioStreamPlayer.new()
		p.bus = "Voice"
		add_child(p)
		_voice_players.append(p)
	_voices = Data.load_json("voices")
	apply_volumes()


func _make_buses() -> void:
	for b in ["Music", "Ambience", "SFX", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 900.0
	AudioServer.add_bus_effect(mi, lp)
	_memory_fx = AudioServer.get_bus_effect_count(mi) - 1
	AudioServer.set_bus_effect_enabled(mi, _memory_fx, false)


func _loop(file: String) -> AudioStream:
	if not ResourceLoader.exists(DIR + file):
		push_warning("missing sound " + file)
		return null
	var s = load(DIR + file)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	return s


func _player(bus: String, stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	add_child(p)
	return p


# --- settings -----------------------------------------------------------------------------------

func _load_settings() -> void:
	if muted:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
		sound_volume = clampf(float(cfg.get_value("audio", "sound", sound_volume)), 0.0, 1.0)
		voice_volume = clampf(float(cfg.get_value("audio", "voice", voice_volume)), 0.0, 1.0)


func set_volumes(music_v: float, sound_v: float) -> void:
	music_volume = clampf(music_v, 0.0, 1.0)
	sound_volume = clampf(sound_v, 0.0, 1.0)
	apply_volumes()
	if muted:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sound", sound_volume)
	cfg.save(SETTINGS_PATH)


func set_voice_volume(v: float) -> void:
	voice_volume = clampf(v, 0.0, 1.0)
	apply_volumes()
	if muted:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.save(SETTINGS_PATH)


func apply_volumes() -> void:
	AudioServer.set_bus_mute(0, muted)
	# a slider's 0..1 maps to a gentle curve, so the middle is still clearly audible
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume * music_volume, 0.0001)))
	for b in ["Ambience", "SFX"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b), linear_to_db(maxf(sound_volume * sound_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(voice_volume * voice_volume, 0.0001)))


# --- effects ------------------------------------------------------------------------------------

## Plays a one-shot ("ui_click", "journal") or a random take from a group ("step_grass").
func play(sound: String, db := 0.0, pitch_jitter := 0.0) -> void:
	var takes: Array = _sfx.get(sound, [])
	if takes.is_empty():
		return
	played[sound] = int(played.get(sound, 0)) + 1
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = takes[randi() % takes.size()]
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# --- voices -------------------------------------------------------------------------------------

## A character's voice from data/voices.json: {"pitch", "gap", "max"}, following "like" to another's.
func voice_for(id: String) -> Dictionary:
	var vs: Dictionary = _voices.get("voices", {})
	var like: Dictionary = _voices.get("like", {})
	var key := id
	for i in 3:
		if vs.has(key):
			return vs[key]
		if not like.has(key):
			break
		key = str(like[key])
	return _voices.get("default", {"pitch": 1.0, "gap": 0.13, "max": 7})


## Mumbles a line in a character's voice (their id: "nora", "rosa", "tf_lily", "hm_wyn"...), cutting
## off whatever line was still being mumbled. "" (a narrator, a sign) says nothing.
func speak(id: String, text: String) -> void:
	hush()
	if id == "" or _voice_clips.is_empty() or text.strip_edges() == "":
		return
	var v := voice_for(id)
	var pitch := float(v.get("pitch", 1.0))
	var gap := float(v.get("gap", 0.13))
	var n := clampi(ceili(text.length() / 9.0), 3, maxi(3, int(v.get("max", 7))))
	spoke[id] = int(spoke.get(id, 0)) + 1
	last_voice = {"id": id, "pitch": pitch, "gap": gap, "n": n}
	var seq := _voice_seq
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + text) # the same line sounds the same each time
	var prev := -1
	for i in n:
		if seq != _voice_seq or not is_inside_tree():
			return
		var c := rng.randi() % _voice_clips.size()
		if c == prev and _voice_clips.size() > 1: # never the same syllable twice running
			c = (c + 1) % _voice_clips.size()
		prev = c
		var p := _voice_players[i % _voice_players.size()]
		p.stream = _voice_clips[c]
		p.pitch_scale = pitch * rng.randf_range(0.95, 1.06) * (0.96 if i == n - 1 else 1.0) # a lift, and a fall at the end
		p.volume_db = -4.0
		p.play()
		if i < n - 1:
			var wait := gap * rng.randf_range(0.85, 1.2) + (gap * 1.6 if rng.randf() < 0.12 else 0.0) # little pauses, like words
			await get_tree().create_timer(wait).timeout


## Stops the line being mumbled.
func hush() -> void:
	_voice_seq += 1
	for p in _voice_players:
		p.stop()


func footstep(pos: Vector3) -> void:
	if main.has_method("surface_at") and main.surface_at(pos) == "wood":
		play("step_wood", -11.0, 0.08)
	else:
		play("step_grass", -13.0, 0.12)


func needle() -> void:
	play("needle", -16.0, 0.1)


# --- music and ambience mix ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if music == null:
		return
	var night := 1.0 - clampf(Game.daylight() * 1.6, 0.0, 1.0)
	var wet := clampf(float(main.get("rain")), 0.0, 1.0)
	var inside: bool = main.has_method("player_indoors") and main.player_indoors()
	var room := 0.3 if inside else 1.0 # walls muffle the outdoors
	var want := {
		"day": (1.0 - night) * (1.0 - 0.7 * wet) * room,
		"night": night * (1.0 - 0.5 * wet) * room,
		"rain": wet * (0.45 if inside else 1.0),
	}
	var k := 1.0 - exp(-delta / 1.2) # about a second to cross-fade
	for key in want:
		_gain[key] = lerpf(_gain[key], want[key], k)
		amb[key].volume_db = AMB_DB + linear_to_db(maxf(_gain[key], 0.0001))
	# a memory flashback: the music sounds far away, as if through a wall
	var memory: bool = main.hud != null and main.hud.memory_on()
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), _memory_fx, memory)
	# a story's own music cue plays over the theme, which steps back for it
	var cue: bool = tune != null and tune.playing
	_gain["music"] = lerpf(_gain["music"], 0.15 if cue else (0.55 if memory else 1.0), k)
	music.volume_db = MUSIC_DB + linear_to_db(_gain["music"])


## A story music cue (assets/audio/music_<name>.ogg), faded in over a second or two; "off" fades
## whatever is playing out. Plays once over the theme (a separate player), which steps back while it plays.
func play_tune(cue: String, secs := 1.5) -> void:
	if cue == "off" or cue == "":
		tune_name = ""
		if tune.playing:
			var tw := create_tween()
			tw.tween_property(tune, "volume_db", -60.0, maxf(secs, 0.05))
			tw.tween_callback(tune.stop)
		return
	var path := DIR + "music_%s.ogg" % cue
	if not ResourceLoader.exists(path):
		push_warning("audio: no music cue " + path)
		return
	tune_name = cue
	tune.stream = load(path)
	tune.volume_db = -40.0
	tune.play()
	create_tween().tween_property(tune, "volume_db", MUSIC_DB + 3.0, maxf(secs, 0.05)).set_trans(Tween.TRANS_SINE)
	tune.finished.connect(func(): tune_name = "", CONNECT_ONE_SHOT)


## For the autotest: the current loudness (0..1) of an ambience layer or the music.
func gain(key: String) -> float:
	return float(_gain.get(key, 0.0))
