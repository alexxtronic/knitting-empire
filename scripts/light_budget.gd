extends RefCounted
## Which lamps cast real shadows. Every street lantern, fireplace and table lamp is made with a
## shadow (Catalog.omni puts it in the GROUP), but a shadowed omni light draws everything round it
## twice more each frame: with 38 of them in sight in town that was half the frame on a MacBook Air
## (--only=perf, 2026-11-16). So only the few nearest the camera's focus that are lit up enough to
## throw a shadow you'd see keep theirs; the rest light the scene without. A light already casting
## counts as a little nearer, so two lamps at the same distance don't swap their shadows back and
## forth as she walks between them.

const GROUP := "lamp_shadow"
const MIN_ENERGY := 0.5 # by day a street lantern glows at 0.15: no shadow you could see
const RANGE := 40.0 # Catalog.omni fades lamp shadows out by 40 m anyway (distance_fade_shadow)
const STICKY := 0.8 # a light casting now counts as this much of its distance
const EVERY := 0.2 # seconds between choices

var max_shadows := 6
var fade := 40.0 # metres from the camera a lamp's shadow fades out by (distance_fade_shadow; Catalog.omni's 40 on Ultra)
var enabled := true # false: every lamp casts, as before (the frame-rate probe's comparison)
var _t := 0.0


func update(tree: SceneTree, centre: Vector3, delta: float, now := false) -> void:
	_t -= delta
	if _t > 0.0 and not now:
		return
	_t = EVERY
	var picks: Array = []
	var main_vp := tree.root
	for n in tree.get_nodes_in_group(GROUP):
		var l := n as OmniLight3D
		if l == null or l.get_viewport() != main_vp: # the catalogue's thumbnails light their own pieces
			continue
		if l.distance_fade_shadow != fade:
			l.distance_fade_shadow = fade
		if not enabled:
			l.shadow_enabled = max_shadows > 0 and not l.has_meta("no_shadow")
			continue
		if l.has_meta("no_shadow") or max_shadows <= 0 or not l.is_visible_in_tree() or l.light_energy < MIN_ENERGY:
			l.shadow_enabled = false
			continue
		var d := l.global_position.distance_to(centre) * (STICKY if l.shadow_enabled else 1.0)
		if d > RANGE:
			l.shadow_enabled = false
			continue
		picks.append([d, l])
	picks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in picks.size():
		(picks[i][1] as OmniLight3D).shadow_enabled = i < max_shadows


## How many lamps cast a shadow now (for the checks).
func casting(tree: SceneTree) -> int:
	var n := 0
	for l in tree.get_nodes_in_group(GROUP):
		if (l as OmniLight3D).shadow_enabled:
			n += 1
	return n
