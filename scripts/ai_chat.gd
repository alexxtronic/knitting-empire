extends Node
## Free-typed chat with villagers, voiced by Claude (the Anthropic Messages API, over plain HTTPS).
## Each villager has a character bible in data/personas.json. Every request sends:
##   system[0]  the rules, the shared world and this villager's bible: the same every time, so
##              it's marked for prompt caching
##   system[1]  the moment: time, weather, how well they know Nora, what's happened in the story,
##              which of their own secrets they're ready to share. Changes every message.
##   messages   the conversation so far with this villager (kept in the save, last 20 lines)
##
## The API key is never in the game files or the repo. It's read, in order, from:
##   1. user://ai.cfg   [ai] api_key="sk-ant-..."   (the chat window can write this for you)
##   2. the ANTHROPIC_API_KEY environment variable
## or set [ai] proxy_url="https://..." to send requests to your own server, which adds the key
## (the way to ship it to players). [ai] model="..." picks another model; [ai] enabled=false turns
## AI chat off. Without any of these, villagers fall back to their hand-written lines.

signal replied(vid: String, result: Dictionary) # {"ok", "text", "mood", "error"}

const API_URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"
const DEFAULT_MODEL := "claude-haiku-5-5" # cheapest current model; strong at staying in character
const CFG_PATH := "user://ai.cfg"
const MAX_HISTORY := 20 # messages kept per villager (10 exchanges)
const MAX_INPUT := 280 # characters Nora can type in one go
const MOODS := ["neutral", "happy", "warm", "wry", "sad", "worried", "surprised"]

var personas := {}
var api_key := ""
var proxy_url := ""
var model := DEFAULT_MODEL
var enabled := true
var key_source := "" # "file", "env" or "" (for the setup hint; never the key itself)
## Tests set this to a Callable(body: Dictionary) -> Dictionary {"code", "body"} to skip the network.
var mock: Callable
var busy := false
var last_request := {} # the last request body (for tests and debugging; holds no key)

var _http: HTTPRequest
var _pending_vid := ""


func _ready() -> void:
	personas = _load_personas()
	load_config()
	_http = HTTPRequest.new()
	_http.timeout = 45.0
	_http.request_completed.connect(_on_completed)
	add_child(_http)


static func _load_personas() -> Dictionary:
	var f := FileAccess.open("res://data/personas.json", FileAccess.READ)
	if f == null:
		push_error("data/personas.json is missing")
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_config() -> void:
	api_key = ""
	proxy_url = ""
	model = DEFAULT_MODEL
	enabled = true
	key_source = ""
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		api_key = str(cfg.get_value("ai", "api_key", "")).strip_edges()
		proxy_url = str(cfg.get_value("ai", "proxy_url", "")).strip_edges()
		model = str(cfg.get_value("ai", "model", DEFAULT_MODEL)).strip_edges()
		enabled = bool(cfg.get_value("ai", "enabled", true))
		if api_key != "":
			key_source = "file"
	if api_key == "" and proxy_url == "":
		api_key = OS.get_environment("ANTHROPIC_API_KEY").strip_edges()
		if api_key != "":
			key_source = "env"
	if model == "":
		model = DEFAULT_MODEL


## Saves a key typed into the chat window to user://ai.cfg (outside the game folder and the repo).
func save_key(key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("ai", "api_key", key.strip_edges())
	cfg.save(CFG_PATH)
	load_config()


func available() -> bool:
	return enabled and (api_key != "" or proxy_url != "")


func has_persona(vid: String) -> bool:
	return (personas.get("villagers", {}) as Dictionary).has(vid)


func persona(vid: String) -> Dictionary:
	return (personas.get("villagers", {}) as Dictionary).get(vid, {})


func offline_line(vid: String) -> String:
	return str(persona(vid).get("offline", "They smile and nod."))


# --- building the request --------------------------------------------------------

## The stable part of the prompt: rules, world, who this villager is. Cached by the API.
func bible_text(vid: String) -> String:
	var p := persona(vid)
	return "%s\n\n# The world\n%s\n\n# You are %s\n%s\n\n# What you know\n%s\n\nYou love being given %s." % [
		personas.get("rules", ""), personas.get("world", ""), p.get("name", vid), p.get("bible", ""), p.get("knows", ""), p.get("loves", "small kindnesses")]


## Builds the request body. `situation` is the volatile text from main.gd (situation_text).
func build_request(vid: String, history: Array, situation: String) -> Dictionary:
	var body := {
		"model": model,
		"max_tokens": 2048,
		"system": [
			{"type": "text", "text": bible_text(vid), "cache_control": {"type": "ephemeral"}},
			{"type": "text", "text": situation},
		],
		"messages": history.duplicate(true),
	}
	if proxy_url == "" and supports_fallback():
		body["fallbacks"] = "default" # if this model is overloaded, the API answers with a fallback
	if supports_effort():
		body["output_config"] = {"effort": "low"} # small talk: fast and cheap
	return body


## Server-side fallback exists for Opus, Sonnet and Fable; Haiku 5.5 rejects the field.
func supports_fallback() -> bool:
	return model.contains("opus") or model.contains("sonnet") or model.contains("fable")


## `effort` is on every current model except the older Haiku 4.5 and the Claude 3 family.
func supports_effort() -> bool:
	return not (model.contains("haiku-4") or model.begins_with("claude-3"))


## The text for system[1]: what's true right now. `ctx` comes from main.gd.
func situation_text(vid: String, ctx: Dictionary) -> String:
	var p := persona(vid)
	var lines := PackedStringArray()
	lines.append("# Right now")
	lines.append("Day %d of %s, %s. Weather: %s. You're at %s." % [ctx.get("day_of_season", 1), ctx.get("season", "Autumn"), ctx.get("clock", "morning"), ctx.get("weather", "clear"), ctx.get("place", "your usual spot")])
	var fam := int(ctx.get("familiarity", 0))
	var trust := int(ctx.get("trust", 0))
	var romance := int(ctx.get("romance", 0))
	lines.append("How you feel about Nora: familiarity %d/100 (%d hearts), trust %d (-50..100), romance %d/100. %s" % [fam, fam / 20, trust, romance, _closeness(fam, trust)])
	var unlocked := PackedStringArray()
	var opens: Dictionary = p.get("opens_up", {})
	for k in opens:
		if trust >= int(k) or fam >= int(k) * 2:
			unlocked.append("- " + str(opens[k]))
	if unlocked.size() > 0:
		lines.append("Things you'd now share with Nora if the conversation goes there (don't force them):\n" + "\n".join(unlocked))
	else:
		lines.append("You don't know Nora well enough yet to share anything personal.")
	for fact in ctx.get("facts", []):
		lines.append("- " + str(fact))
	if ctx.has("nora"):
		lines.append("How Nora seems: %s" % ctx["nora"])
	if int(ctx.get("last_day", 0)) > 0 and int(ctx.get("last_day", 0)) < int(ctx.get("day", 1)):
		lines.append("The earlier messages are from a previous day (day %d)." % int(ctx["last_day"]))
	return "\n".join(lines)


static func _closeness(fam: int, trust: int) -> String:
	if trust < -10:
		return "You're wary of her."
	if fam < 10:
		return "You've only just met."
	if fam < 40:
		return "You're getting to know each other."
	if fam < 70:
		return "You're friends."
	return "You're close friends."


# --- sending ---------------------------------------------------------------------

## Sends the conversation; `replied` fires with the result. Returns false if it couldn't start.
func send(vid: String, history: Array, situation: String) -> bool:
	if busy or not has_persona(vid):
		return false
	if not available() and not mock.is_valid():
		replied.emit.call_deferred(vid, {"ok": false, "error": "offline", "text": offline_line(vid), "mood": "neutral"})
		return true
	var body := build_request(vid, history, situation)
	last_request = body
	busy = true
	_pending_vid = vid
	if mock.is_valid():
		var r: Dictionary = mock.call(body)
		_finish.call_deferred(int(r.get("code", 200)), str(r.get("body", "")))
		return true
	var url := proxy_url if proxy_url != "" else API_URL
	var headers := PackedStringArray(["content-type: application/json", "anthropic-version: " + API_VERSION])
	if proxy_url == "":
		headers.append("x-api-key: " + api_key)
		if supports_fallback():
			headers.append("anthropic-beta: server-side-fallback-2026-07-01")
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		busy = false
		replied.emit.call_deferred(vid, {"ok": false, "error": "network", "text": offline_line(vid), "mood": "neutral"})
	return true


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		busy = false
		replied.emit(_pending_vid, {"ok": false, "error": "network", "text": offline_line(_pending_vid), "mood": "neutral"})
		return
	_finish(code, body.get_string_from_utf8())


func _finish(code: int, text: String) -> void:
	busy = false
	var r := parse_response(code, text)
	if not r["ok"]:
		r["text"] = offline_line(_pending_vid)
	replied.emit(_pending_vid, r)


## Reads an API response: {"ok", "text", "mood", "error"}. error is "" when ok, else one of
## "refusal", "key", "busy", "bad_request", "server", "empty".
static func parse_response(code: int, text: String) -> Dictionary:
	var d = JSON.parse_string(text) if text != "" else null
	if code == 401 or code == 403:
		return {"ok": false, "error": "key", "text": "", "mood": "neutral"}
	if code == 429 or code == 529 or code == 503:
		return {"ok": false, "error": "busy", "text": "", "mood": "neutral"}
	if code >= 400 and code < 500:
		var msg := ""
		if d is Dictionary and d.get("error") is Dictionary:
			msg = str(d["error"].get("message", ""))
		push_warning("AI chat request rejected (%d): %s" % [code, msg])
		return {"ok": false, "error": "bad_request", "text": "", "mood": "neutral"}
	if code >= 500 or not (d is Dictionary):
		return {"ok": false, "error": "server", "text": "", "mood": "neutral"}
	if str(d.get("stop_reason", "")) == "refusal":
		return {"ok": false, "error": "refusal", "text": "", "mood": "neutral"}
	var out := ""
	for block in d.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			out += str(block.get("text", ""))
	out = out.strip_edges()
	if out == "":
		return {"ok": false, "error": "empty", "text": "", "mood": "neutral"}
	var split := split_mood(out)
	return {"ok": true, "error": "", "text": split[1], "mood": split[0], "raw": out}


## "[warm] *smiles* Hello." -> ["warm", "*smiles* Hello."]
static func split_mood(s: String) -> Array:
	s = s.strip_edges()
	if s.begins_with("["):
		var end := s.find("]")
		if end > 0 and end < 16:
			var m := s.substr(1, end - 1).strip_edges().to_lower()
			return [m if m in MOODS else "neutral", s.substr(end + 1).strip_edges()]
	return ["neutral", s]


## Safe BBCode for the chat log: escapes brackets, turns *actions* into italics.
static func to_bbcode(s: String) -> String:
	s = s.replace("[", "[lb]")
	var out := ""
	var parts := s.split("*")
	for i in parts.size():
		out += ("[i][color=#d9c9a8]%s[/color][/i]" % parts[i]) if i % 2 == 1 and i < parts.size() - 1 else parts[i]
	return out


## Appends a message and trims to MAX_HISTORY, keeping the first message from Nora (the API
## needs the conversation to start with the user).
static func push_history(history: Array, role: String, text: String) -> void:
	history.append({"role": role, "content": text})
	while history.size() > MAX_HISTORY or (history.size() > 0 and history[0]["role"] != "user"):
		history.pop_front()


## What the chat window says when a reply didn't come back.
static func error_note(error: String) -> String:
	match error:
		"offline": return "AI chat is off: add an API key below to talk freely. (Talk still works.)"
		"key": return "The API key was rejected. Check it in the box below."
		"busy": return "Claude is busy right now. Try again in a moment."
		"refusal": return "They'd rather not talk about that."
		"network": return "Couldn't reach the server. Are you online?"
	return "Something went wrong with that reply. Try again."
