extends RefCounted
## --only=voice: the characters' mumbles (audio.gd speak(), data/voices.json, assets/audio/voice/;
## Alex, 2026-11-28, "B · Mumbles"). The five syllables loaded on their own Voice bus, every named
## character and the townsfolk and keepers with a voice ("like" followed, anyone else the default),
## a villager's talk and a story line mumbling in the speaker's voice at their pitch, a longer line
## getting more syllables up to their most, the next line cutting the last one off, narration
## saying nothing, and the Voices slider setting the bus. Sound is muted in the autotest, so it
## reads what was played rather than listening. A few seconds; no pictures.


func run(m: Node) -> void:
	var a = m.audio
	m._check("five mumble syllables on the Voice bus (%d clips, %d players, bus %d)" % [a._voice_clips.size(), a._voice_players.size(), AudioServer.get_bus_index("Voice")],
		a._voice_clips.size() == 5 and a._voice_players.size() >= 2 and AudioServer.get_bus_index("Voice") >= 0
		and a._voice_players.all(func(p): return p.bus == "Voice"))
	var named := ["nora", "rosa", "wren", "sabrina", "barbara", "rebecca", "rowan", "giorgio", "gary", "lars", "steve", "max"]
	var vs: Dictionary = a._voices.get("voices", {})
	var missing := named.filter(func(id): return not vs.has(id))
	m._check("every named character has a voice of their own (missing %s)" % str(missing), missing.is_empty())
	var kid: Dictionary = a.voice_for("tf_lily")
	var old: Dictionary = a.voice_for("hm_bramwell")
	var nobody: Dictionary = a.voice_for("nobody_at_all")
	m._check("the townsfolk and keepers borrow one (Lily the kid's %.2f, Bramwell the old man's %.2f), anyone else the default (%.2f)" % [float(kid["pitch"]), float(old["pitch"]), float(nobody["pitch"])],
		kid == vs["kid"] and old == vs["old"] and nobody == a._voices["default"])
	m._check("the children are higher than the grown-ups, Steve lower than Rosa", float(vs["kid"]["pitch"]) > float(vs["man"]["pitch"]) and float(vs["steve"]["pitch"]) < float(vs["rosa"]["pitch"]))
	# a villager's talk
	var rosa = m._villager("rosa")
	var before := int(a.spoke.get("rosa", 0))
	m._say(rosa, "Morning! The wool came in this morning, lovely and soft.")
	await m._wait(0.05)
	var p0: AudioStreamPlayer = a._voice_players[0]
	var rp := float(vs["rosa"]["pitch"])
	m._check("talking to Rosa mumbles in her voice (%d syllables, pitch %.2f)" % [int(a.last_voice.get("n", 0)), p0.pitch_scale],
		int(a.spoke.get("rosa", 0)) == before + 1 and str(a.last_voice.get("id", "")) == "rosa" and p0.playing
		and p0.pitch_scale > rp * 0.9 and p0.pitch_scale < rp * 1.1)
	# a story line
	m.hud.story_say("Nora", "Hello.", null, "nora")
	await m._wait(0.05)
	var short_n := int(a.last_voice.get("n", 0))
	m._check("a story line is spoken in the speaker's voice (%s, %d syllables)" % [str(a.last_voice.get("id", "")), short_n],
		str(a.last_voice.get("id", "")) == "nora" and short_n == 3)
	m.hud.story_say("Nora", "I didn't think I'd ever come back here, but the farm looks just the way Gran left it, more or less.", null, "nora")
	await m._wait(0.05)
	m._check("a longer line gets more syllables, up to her most (%d of %d)" % [int(a.last_voice.get("n", 0)), int(vs["nora"]["max"])],
		int(a.last_voice.get("n", 0)) == int(vs["nora"]["max"]))
	# the next line cuts it off
	var seq: int = a._voice_seq
	a.speak("steve", "Wood's round the back. Help yourself, pay at the till.")
	await m._wait(0.05)
	var sp := float(vs["steve"]["pitch"])
	m._check("the next line cuts the last off and starts its own (Steve at %.2f)" % a._voice_players[0].pitch_scale,
		a._voice_seq > seq and a._voice_players[0].pitch_scale < sp * 1.1)
	m.hud.story_say("", "The bus pulls away.", null, "")
	await m._wait(0.05)
	m._check("narration says nothing and hushes the last line", a._voice_players.all(func(p): return not p.playing))
	await m._wait(0.6)
	m._check("and nothing comes after it", a._voice_players.all(func(p): return not p.playing))
	m.hud.story_box.visible = false
	m.hud.hide_dialogue()
	# the Voices slider
	var keep: float = a.voice_volume
	m.hud.voice_slider.value = 0.4
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice"))
	m._check("the Voices slider sets the Voice bus (%.1f dB)" % db, absf(db - linear_to_db(0.16)) < 0.2 and absf(a.voice_volume - 0.4) < 0.01)
	m.hud.voice_slider.value = keep
