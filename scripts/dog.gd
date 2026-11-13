extends Node3D
## The farm dog: a golden retriever in a red scarf (assets/props/dog.glb, rigged by tools/rig_dog.py).
##
## Tab hands the player's clicks to him and back (main.gd's toggle_dog). While you play him, a
## click walks him there like it walks Nora, and holding Shift he gallops. The rest of the time he
## keeps Nora company: he trots after her when she gets away from him, gallops to catch up when she
## is far off, and stands at her side looking about when she stops.
##
## Four loops, each keyed so a planted paw stays exactly where it was put. STRIDE is the ground
## speed each covers at speed 1 (rig_dog.py prints it); the loop playing is chosen by his speed and
## sped up or slowed to match it, so his paws never slide.
##
## He herds: he is in homestead.herders, and strays shy from him further off than from Nora.
## For now he's with her from the start of every game (main.DOG_FROM_START); in Act 1 he only
## herds once the pen is built (the "pen_done" flag, main.dog_herds()).

const Catalog = preload("res://scripts/catalog.gd")
const MODEL := "res://assets/props/dog.glb"
const LOOPS := ["Idle", "Walk", "Trot", "Run"]
const STRIDE := {"Walk": 0.669, "Trot": 1.459, "Run": 3.424}
## Walk gives way to Trot above TROT_ABOVE m/s and comes back below WALK_BELOW (two thresholds so
## he doesn't flicker between them); Trot gives way to the gallop likewise.
const TROT_ABOVE := 0.85
const WALK_BELOW := 0.7
const RUN_ABOVE := 2.5
const TROT_BELOW := 2.2
const MIN_RATE := 0.6 # a loop never plays slower than this: a first step is quick, not slow motion
const BLEND := 0.25
const ACCEL := 7.0
const BRAKE := 8.0
const TURN := 9.0
const HEEL := 1.3 # how close to Nora he settles
const ROOM := 1.1 # in a story scene, anyone who comes this close moves him round to her other side
const SCARE_RADIUS := 3.4 # sheep move off when he is this close (Nora: homestead.HERD_RADIUS)

var main: Node # main.gd
var controlled := false # the player's clicks move him (Tab)
var running := false # Shift held, while he's the one you play
var walk_speed := 1.6 # a brisk trot when you send him somewhere
var run_speed := 4.2 # the gallop
var speed := 0.0 # ground speed right now
var path: Array = []
var _model: Node3D
var _anim: AnimationPlayer
var _repath := 0.0
var _look_t := 0.0
var _giving_way := false # walking round to Nora's far side to make room in a scene


func _ready() -> void:
	_model = Catalog.model(MODEL, self)
	if _model:
		var aps := _model.find_children("*", "AnimationPlayer", true, false)
		_anim = aps[0] if not aps.is_empty() else null
	if _anim:
		for n in LOOPS:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_anim.play("Idle")
	var body := StaticBody3D.new() # so a click on him can be told apart (and the autotest can find him)
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 0.6, 1.0)
	cs.shape = bs
	cs.position.y = 0.32
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)


func display_name() -> String:
	return "Dog"


func scare_radius() -> float:
	return SCARE_RADIUS


## Whether the model loaded with every loop (for the autotest).
func ok() -> bool:
	if _anim == null:
		return false
	for n in LOOPS:
		if not _anim.has_animation(n):
			return false
	return true


func current_loop() -> String:
	return _anim.current_animation if _anim else ""


func loop_rate() -> float:
	return _anim.speed_scale if _anim else 0.0


## Where floating text and the camera aim: over his back.
func head_point() -> Vector3:
	return global_position + Vector3(0, 0.75, 0)


## Sends him along a path (world points), as a click does.
func walk(p: Array) -> void:
	path = p


func _process(delta: float) -> void:
	if not controlled:
		_follow_nora(delta)
	var walking := not path.is_empty()
	if walking:
		var next: Vector3 = path[0]
		var to := next - position
		to.y = 0.0
		var d := to.length()
		var top := _top_speed()
		var off := absf(angle_difference(rotation.y, atan2(to.x, to.z))) if d > 0.01 else 0.0
		var want := top * clampf(1.15 - off / 1.6, 0.3, 1.0)
		want = minf(want, maxf(0.4, sqrt(2.0 * BRAKE * _path_left())))
		speed = move_toward(speed, want, (ACCEL if want > speed else BRAKE) * delta)
		var step := speed * delta
		if d <= step:
			position = Vector3(next.x, 0.0, next.z)
			path.remove_at(0)
			if path.is_empty():
				speed = 0.0
		else:
			position += to / d * step
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-delta * TURN))
	else:
		speed = move_toward(speed, 0.0, BRAKE * delta)
		_idle_look(delta)
	_play_gait()


func _top_speed() -> float:
	if controlled:
		return run_speed if running else walk_speed
	# keeping up with Nora: a walk beside her, a trot when she's drawn ahead, a gallop to catch up
	var d := _to_nora().length()
	if d > 7.0:
		return run_speed
	if d > 3.0:
		return walk_speed
	return maxf(0.6, main.player.speed if main else 0.6)


func _to_nora() -> Vector3:
	if main == null or main.player == null:
		return Vector3.ZERO
	var v: Vector3 = main.player.position - position
	v.y = 0.0
	return v


## Off the lead he stays near her: when she's more than a few steps off he heads for a spot at her
## side, and picks it again every so often as she moves.
func _follow_nora(delta: float) -> void:
	if main == null or main.player == null:
		return
	_repath -= delta
	var d := _to_nora().length()
	if d > 25.0: # left far behind (she went through a door, a scene moved her): he catches up out of sight
		position = main.player.position - main.player.global_transform.basis.z * 1.5 + main.player.global_transform.basis.x * 0.8
		path = []
		return
	var crowd := _crowding()
	if crowd != null: # in a scene, someone has walked up to her where he sits: he goes round to her far side
		var away: Vector3 = main.player.position - crowd.global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = main.player.global_transform.basis.z
		var clear: Vector3 = main.player.position + away.normalized() * HEEL
		if path.is_empty() or (path[-1] as Vector3).distance_to(clear) > 0.5:
			path = main._find_path(position, clear) if main.has_method("_find_path") else [clear]
		_giving_way = true
		return
	if _giving_way and not path.is_empty(): # he goes all the way round, not just out of the way
		return
	_giving_way = false
	if d < HEEL + 0.6 and main.player.path.is_empty():
		if not path.is_empty() and d < HEEL:
			path = []
		return
	if _repath > 0.0 and not path.is_empty():
		return
	_repath = 0.6
	var nora: Vector3 = main.player.position
	var side: Vector3 = main.player.global_transform.basis.x * 0.9 - main.player.global_transform.basis.z * 0.5
	var spot := nora + side
	path = main._find_path(position, spot) if main.has_method("_find_path") else [spot]


## While a story scene plays, the person within ROOM of where he is (they came to talk to her), so
## he can make way; null when nobody is, or no scene is on.
func _crowding() -> Node3D:
	if main.story == null or not main.story.is_playing():
		return null
	for v in main.villagers + main.visitors.values(): # the town's cast, and anyone visiting for a scene (Max)
		if is_instance_valid(v) and v.visible and (v as Node3D).global_position.distance_to(position) < ROOM:
			return v
	return null


## Standing: now and then he turns to look at Nora, or somewhere else.
func _idle_look(delta: float) -> void:
	_look_t -= delta
	if _look_t > 0.0 or main == null or controlled:
		return
	_look_t = randf_range(3.0, 7.0)
	var to := _to_nora()
	if to.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.6)


## Picks the loop for his speed and plays it at the rate that keeps his paws planted.
func _play_gait() -> void:
	if _anim == null:
		return
	var cur := _anim.current_animation
	var want := "Idle"
	if speed > 0.05:
		if cur == "Run":
			want = "Run" if speed > TROT_BELOW else ("Trot" if speed > WALK_BELOW else "Walk")
		elif cur == "Trot":
			want = "Run" if speed > RUN_ABOVE else ("Trot" if speed > WALK_BELOW else "Walk")
		else:
			want = "Run" if speed > RUN_ABOVE else ("Trot" if speed > TROT_ABOVE else "Walk")
	if cur != want:
		_anim.play(want, BLEND)
	_anim.speed_scale = maxf(speed / float(STRIDE[want]), MIN_RATE) if want != "Idle" else 1.0


func _path_left() -> float:
	var total := 0.0
	var from := position
	for p in path:
		total += Vector2(p.x - from.x, p.z - from.z).length()
		from = p
	return total
