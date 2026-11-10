extends Node3D
## A sheep that wanders its pen and regrows wool after shearing.
##
## Two models from tripo.ai, brought into the Woolcore look by tools/import_asset.py: a woolly sheep
## (assets/props/sheep_woolly.glb) and a freshly shorn one (assets/props/sheep_sheared.glb). Her coat
## comes back once the wool is half grown and fills out as it finishes. The models have no rig, so
## walking is a little waddle of the whole body and grazing a slow nod.

const Catalog = preload("res://scripts/catalog.gd")
const REGROW_HOURS := 10.0
const WOOLLY_MODEL := "res://assets/props/sheep_woolly.glb"
const SHEARED_MODEL := "res://assets/props/sheep_sheared.glb"
const COAT_BACK := 0.5 # wool level at which the woolly model shows again

var pen := Rect2()
## 0..1, shearable at 1. Setting it (shearing, loading a save, overnight growth) updates the look.
var wool := 1.0:
	set(v):
		wool = clampf(v, 0.0, 1.0)
		_update_look()
var hold_time := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var _walk := 0.0
var _pivot: Node3D # carries both models; tilts for grazing and sways for walking
var _woolly: Node3D
var _sheared: Node3D


func _ready() -> void:
	# pivot on the hind feet, so grazing dips the head and the back legs stay planted
	_pivot = Node3D.new()
	_pivot.position.z = -0.3
	add_child(_pivot)
	_woolly = Catalog.model(WOOLLY_MODEL, _pivot)
	_sheared = Catalog.model(SHEARED_MODEL, _pivot)
	for m in [_woolly, _sheared]:
		if m:
			m.position.z = 0.3
	if _woolly == null:
		_woolly = Node3D.new()
		_pivot.add_child(_woolly)
		Catalog.ball(_woolly, 0.4, Vector3(0, 0.55, 0.3), Color(0.97, 0.96, 0.92), Vector3(0.8, 0.8, 1.2))
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 0.95, 1.05)
	cs.shape = bs
	cs.position.y = 0.48
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	_pick_target()
	_update_look()


func display_name() -> String:
	return "Sheep"


func is_woolly() -> bool:
	return wool >= 1.0


## Which model shows right now: "woolly" or "sheared" (for the autotest).
func coat() -> String:
	return "sheared" if _sheared and _sheared.visible else "woolly"


func shear() -> void:
	wool = 0.0


func hold(seconds: float) -> void:
	hold_time = seconds


func _pick_target() -> void:
	_target = Vector3(randf_range(pen.position.x, pen.end.x), 0, randf_range(pen.position.y, pen.end.y))


func _update_look() -> void:
	if _woolly == null:
		return
	var coated := wool >= COAT_BACK or _sheared == null
	_woolly.visible = coated
	if _sheared:
		_sheared.visible = not coated
	if coated:
		var s := lerpf(0.88, 1.0, clampf((wool - COAT_BACK) / (1.0 - COAT_BACK), 0.0, 1.0))
		_woolly.scale = Vector3(s, s, s)


func _process(delta: float) -> void:
	if wool < 1.0:
		wool = wool + delta / (Game.HOUR_SECONDS * REGROW_HOURS)
	if hold_time > 0.0:
		hold_time -= delta
		_settle(delta)
		return
	if _wait > 0.0:
		_wait -= delta
		# grazing: head down, with a slow chewing nod
		_pivot.rotation.x = lerpf(_pivot.rotation.x, deg_to_rad(5.0 + 1.5 * sin(_wait * 2.5)), 1.0 - exp(-delta * 4.0))
		_pivot.rotation.z = lerpf(_pivot.rotation.z, 0.0, 1.0 - exp(-delta * 6.0))
		_pivot.position.y = 0.0
		return
	var to := _target - position
	to.y = 0
	if to.length() < 0.1:
		_wait = randf_range(2.0, 6.0)
		_pick_target()
		return
	position += to.normalized() * 0.55 * delta
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 0.1)
	# walking: a small side-to-side waddle and a bob with each step
	_walk += delta * 9.0
	_pivot.rotation.x = lerpf(_pivot.rotation.x, 0.0, 1.0 - exp(-delta * 6.0))
	_pivot.rotation.z = deg_to_rad(2.5) * sin(_walk)
	_pivot.position.y = 0.015 * absf(sin(_walk))


## Standing still (being sheared or petted): ease back to level.
func _settle(delta: float) -> void:
	var k := 1.0 - exp(-delta * 6.0)
	_pivot.rotation.x = lerpf(_pivot.rotation.x, 0.0, k)
	_pivot.rotation.z = lerpf(_pivot.rotation.z, 0.0, k)
	_pivot.position.y = lerpf(_pivot.position.y, 0.0, k)
