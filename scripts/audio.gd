extends Node
## Music, ambience and sound effects. Every sound comes from tools/make_audio.py (no samples or
## licences); swap in real recordings later under the same names in res://assets/audio/.
##
## Three buses under Master: Music, Ambience and SFX. The Settings panel sets Music and Sound
## (Ambience + SFX), kept in user://settings.cfg with the graphics level. The autotest mutes it all.

const DIR := "res://assets/audio/"
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_DB := -9.0
const AMB_DB := -7.0

var main: Node
var music: AudioStreamPlayer
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


func setup(m: Node, mute := false) -> void:
	main = m
	muted = mute
	_make_buses()
	_load_settings()
	music = _player("Music", _loop("music_cast_on.ogg"))
	music.volume_db = MUSIC_DB
	for k in ["day", "night", "rain"]:
		amb[k] = _player("Ambience", _loop("amb_%s.ogg" % k))
		amb[k].volume_db = -80.0
		amb[k].play()
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
	for one in ["ui_click", "ui_open", "journal"]:
		if ResourceLoader.exists(DIR + one + ".wav"):
			_sfx[one] = [load(DIR + one + ".wav")]
	apply_volumes()


func _make_buses() -> void:
	for b in ["Music", "Ambience", "SFX"]:
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


func apply_volumes() -> void:
	AudioServer.set_bus_mute(0, muted)
	# a slider's 0..1 maps to a gentle curve, so the middle is still clearly audible
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume * music_volume, 0.0001)))
	for b in ["Ambience", "SFX"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b), linear_to_db(maxf(sound_volume * sound_volume, 0.0001)))


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
	_gain["music"] = lerpf(_gain["music"], 0.55 if memory else 1.0, k)
	music.volume_db = MUSIC_DB + linear_to_db(_gain["music"])


## For the autotest: the current loudness (0..1) of an ambience layer or the music.
func gain(key: String) -> float:
	return float(_gain.get(key, 0.0))
