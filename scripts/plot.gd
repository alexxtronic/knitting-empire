extends Node3D
## One soil plot on the farm: plant → water → grow → harvest.

const Catalog = preload("res://scripts/catalog.gd")

const CROPS := {
	"turnip": {"name": "Turnips", "seed": 10, "hours": 6.0},
	"pumpkin": {"name": "Pumpkins", "seed": 30, "hours": 14.0},
}
const DRY := Color(0.52, 0.36, 0.22)
const WET := Color(0.30, 0.20, 0.13)

var crop := ""
var growth := 0.0 # in-game hours of growth
var watered := false
var soil: MeshInstance3D
var crop_root: Node3D
var _stage := -2
var _bob := 0.0


func _ready() -> void:
	soil = Catalog.box(self, Vector3(1.0, 0.1, 1.0), Vector3(0, 0.03, 0), DRY)
	for i in 3:
		Catalog.box(self, Vector3(0.9, 0.025, 0.08), Vector3(0, 0.085, -0.3 + i * 0.3), DRY.darkened(0.15))
	crop_root = Node3D.new()
	add_child(crop_root)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.5, 1.0)
	cs.shape = bs
	cs.position.y = 0.25
	body.add_child(cs)
	body.set_meta("target", self)
	add_child(body)
	refresh()


func display_name() -> String:
	if crop == "":
		return "Soil Plot"
	return CROPS[crop]["name"]


func hours_needed() -> float:
	return CROPS[crop]["hours"] if crop != "" else 1.0


func progress() -> float:
	return clampf(growth / hours_needed(), 0.0, 1.0) if crop != "" else 0.0


func is_ready() -> bool:
	return crop != "" and growth >= hours_needed()


func stage() -> int:
	if crop == "":
		return -1
	var p := progress()
	if p >= 1.0:
		return 3
	if p >= 0.66:
		return 2
	if p >= 0.33:
		return 1
	return 0


func plant(c: String) -> void:
	crop = c
	growth = 0.0
	refresh()


func water() -> void:
	watered = true
	refresh()


func clear_crop() -> void:
	crop = ""
	growth = 0.0
	refresh()


func on_new_day() -> void:
	if crop != "" and watered:
		growth += 8.0 # crops keep growing overnight if they were watered
	watered = false
	refresh()


func _process(delta: float) -> void:
	if crop != "" and watered and not is_ready() and Game.time_running:
		growth += delta / Game.HOUR_SECONDS
	if stage() != _stage:
		refresh()
	if is_ready():
		_bob += delta
		crop_root.position.y = 0.02 * sin(_bob * 3.0)


func refresh() -> void:
	_stage = stage()
	soil.material_override = Catalog.mat(WET if watered else DRY)
	for c in crop_root.get_children():
		c.queue_free()
	crop_root.position.y = 0
	var leaf := Catalog.LEAF
	match _stage:
		0:
			for o in [Vector3(-0.08, 0.12, 0), Vector3(0.08, 0.12, 0.02)]:
				Catalog.ball(crop_root, 0.05, o, leaf.lightened(0.15))
		1:
			for i in 4:
				var a := i * TAU / 4.0
				Catalog.ball(crop_root, 0.09, Vector3(cos(a) * 0.08, 0.17, sin(a) * 0.08), leaf, Vector3(1, 0.6, 1))
		2, 3:
			var ripe := _stage == 3
			if crop == "turnip":
				var bulb := Color(0.92, 0.88, 0.95) if ripe else Color(0.85, 0.85, 0.8)
				Catalog.ball(crop_root, 0.16 if ripe else 0.1, Vector3(0, 0.15, 0), bulb, Vector3(1, 0.9, 1))
				Catalog.ball(crop_root, 0.1 if ripe else 0.06, Vector3(0, 0.22, 0), Color(0.6, 0.25, 0.55), Vector3(1, 0.6, 1))
				for i in 5:
					var a := i * TAU / 5.0
					Catalog.box(crop_root, Vector3(0.06, 0.32, 0.02), Vector3(cos(a) * 0.06, 0.42, sin(a) * 0.06), leaf, Vector3(cos(a) * 25, -rad_to_deg(a), sin(a) * 25))
			else:
				var pc := Color(0.95, 0.52, 0.12) if ripe else Color(0.6, 0.7, 0.3)
				var s := 0.32 if ripe else 0.18
				Catalog.ball(crop_root, s, Vector3(0, s * 0.7, 0), pc, Vector3(1, 0.75, 1))
				Catalog.cyl(crop_root, 0.025, 0.035, 0.12, Vector3(0, s * 1.4 + 0.04, 0), Color(0.35, 0.3, 0.12))
				Catalog.ball(crop_root, 0.12, Vector3(0.3, 0.12, 0.2), leaf, Vector3(1.4, 0.4, 1.0))
				Catalog.ball(crop_root, 0.12, Vector3(-0.25, 0.1, -0.25), leaf, Vector3(1.2, 0.4, 1.3))
			if ripe:
				Catalog.glow(Catalog.ball(crop_root, 0.05, Vector3(0, 0.85, 0), Color(1.0, 0.9, 0.4)), Color(1.0, 0.9, 0.4), 3.0)


func to_dict() -> Dictionary:
	return {"crop": crop, "growth": growth, "watered": watered}


func from_dict(d: Dictionary) -> void:
	crop = str(d.get("crop", ""))
	growth = float(d.get("growth", 0.0))
	watered = bool(d.get("watered", false))
	refresh()
