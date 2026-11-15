extends RefCounted
## Key bindings: which key does what, chosen by the player in Settings > Key bindings and kept in
## user://settings.cfg ("keys" section, action id -> keycode).
##
## The game's code still names each action by its default key (`KEY_I` opens the bag). Every
## handler passes the key it got through `Keys.map(kc, groups)`, which turns the key the player
## bound to an action into that action's default key, and swallows a default key whose action has
## been moved to another key. Held keys go through `Keys.key_for(default, groups)`. Each place in
## the game reads its own groups, so the same key can mean different things in different modes
## (E turns the camera from above and uses things in first person), and binding one doesn't move
## the other.
##
## Groups: "move" (walking, shared by Nora, first person and the free camera), "world" (from above),
## "fps" (first person), "cine" (the cinematic camera), "knit" (the knitting game). An action can
## belong to several (V enters first person from above and leaves it from inside).
## Fixed keys, never rebound: Esc, Enter, the number keys, the arrow keys (they always also move).

const SETTINGS_PATH := "user://settings.cfg"

## id, label shown in Settings, groups, default key. The order is the order on the page.
const ACTIONS := [
	["move_up", "Walk forward / up", ["move"], KEY_W],
	["move_down", "Walk back / down", ["move"], KEY_S],
	["move_left", "Walk left", ["move"], KEY_A],
	["move_right", "Walk right", ["move"], KEY_D],
	["run", "Run (hold)", ["move", "cine"], KEY_SHIFT],
	["bag", "Open the bag", ["world"], KEY_I],
	["turn_left", "Turn the camera left", ["world"], KEY_Q],
	["turn_right", "Turn the camera right", ["world"], KEY_E],
	["follow", "Camera follows / stays", ["world"], KEY_SPACE],
	["walls", "Walls up / down", ["world"], KEY_C],
	["build", "Build & Buy", ["world"], KEY_B],
	["rotate", "Turn a piece while placing", ["world"], KEY_R],
	["sell", "Sell the piece in hand", ["world"], KEY_X],
	["dog", "Play the dog / Nora", ["world"], KEY_TAB],
	["first_person", "First person on / off", ["world", "fps"], KEY_V],
	["use", "Use (first person)", ["fps"], KEY_E],
	["cinematic", "Cinematic camera on / off", ["world", "cine"], KEY_P],
	["photo", "Take a photo (cinematic)", ["cine"], KEY_F],
	["fly_up", "Fly up (cinematic)", ["cine"], KEY_E],
	["fly_down", "Fly down (cinematic)", ["cine"], KEY_Q],
	["slow", "Fly slowly (cinematic, hold)", ["cine"], KEY_ALT],
	["hint", "Hide the controls hint", ["fps", "cine"], KEY_H],
	["lane_1", "Knitting: lane 1", ["knit"], KEY_D],
	["lane_2", "Knitting: lane 2", ["knit"], KEY_F],
	["lane_3", "Knitting: lane 3", ["knit"], KEY_J],
	["lane_4", "Knitting: lane 4", ["knit"], KEY_K],
]

## Keys the player can't bind (the menus and the hotbar need them).
const FIXED := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
	KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

static var binds := {} # action id -> Key, only those moved off their default
static var persist := true # false in the autotest: the player's settings are never written
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK or not cfg.has_section("keys"):
		return
	for a in ACTIONS:
		if cfg.has_section_key("keys", a[0]):
			var k := int(cfg.get_value("keys", a[0]))
			if k != int(a[3]):
				binds[a[0]] = k


static func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for id in binds:
		cfg.set_value("keys", id, int(binds[id]))
	cfg.save(SETTINGS_PATH)


static func _action(id: String) -> Array:
	for a in ACTIONS:
		if a[0] == id:
			return a
	return []


## The key an action is on now.
static func bound(id: String) -> Key:
	_ensure()
	var a := _action(id)
	if a.is_empty():
		return KEY_NONE
	return binds.get(id, a[3]) as Key


static func default_key(id: String) -> Key:
	var a := _action(id)
	return (a[3] as Key) if not a.is_empty() else KEY_NONE


## Whether two actions can be live at once: the same group, or walking ("move") with any of the
## modes it walks in.
static func _shares_group(a: Array, b: Array) -> bool:
	var ga := _live_with(a[2])
	for g in b[2]:
		if g in ga:
			return true
	return false


static func _live_with(groups: Array) -> Array:
	var out := groups.duplicate()
	if "move" in groups:
		out.append_array(["world", "fps", "cine"])
	for g in ["world", "fps", "cine"]:
		if g in groups:
			out.append("move")
	return out


## Puts an action on a key. An action that shares a group with it and was on that key takes the
## key this one leaves (a swap), so no two actions in one place ever share a key. Returns the id
## of the action that moved, or "".
static func bind(id: String, key: Key) -> String:
	_ensure()
	var a := _action(id)
	if a.is_empty() or key in FIXED or key == KEY_NONE:
		return ""
	var old := bound(id)
	var moved := ""
	for b in ACTIONS:
		if b[0] != id and bound(b[0]) == key and _shares_group(a, b):
			_put(b[0], old)
			moved = b[0]
	_put(id, key)
	_save()
	return moved


static func _put(id: String, key: Key) -> void:
	if key == default_key(id):
		binds.erase(id)
	else:
		binds[id] = key


static func reset() -> void:
	_ensure()
	binds.clear()
	_save()


## The key pressed, as the game's code knows it in these groups: the default key of the action it
## is bound to, KEY_NONE for a default key whose action has moved elsewhere, or the key unchanged.
static func map(kc: Key, groups: Array) -> Key:
	_ensure()
	if binds.is_empty() or kc in FIXED:
		return kc
	for g in groups:
		for a in ACTIONS:
			if g in a[2] and bound(a[0]) == kc:
				return a[3]
		for a in ACTIONS:
			if g in a[2] and a[3] == kc:
				return KEY_NONE # its action is on another key now
	return kc


## The key to read for a held action named by its default key (Shift for running, W to walk).
static func key_for(default: Key, groups: Array) -> Key:
	_ensure()
	if binds.is_empty():
		return default
	for g in groups:
		for a in ACTIONS:
			if g in a[2] and a[3] == default:
				return bound(a[0])
	return default


## A key's name for the page ("Shift", "Tab", "W").
static func key_name(k: Key) -> String:
	var s := OS.get_keycode_string(k)
	return s if s != "" else "?"
