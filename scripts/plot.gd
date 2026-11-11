extends Node3D
## One soil plot on the farm: plant → water → grow → harvest.

const Catalog = preload("res://scripts/catalog.gd")

const Data = preload("res://scripts/data.gd")
## Crops come from res://data/crops.json.
static var CROPS: Dictionary = Data.crops()
const DRY := Color(0.52, 0.36, 0.22)
const WET := Color(0.30, 0.20, 0.13)
## The plot model (art/world_assets/dirt_plot): a raised soil block with three furrows and a grass
## rim. Its tilled soil uses the material "Soil_plot", which gets darker while the plot is watered.
const MODEL := "res://assets/props/dirt_plot.glb"
const CROP_LIFT := 0.07 # crops stand on the furrows, which are higher than the old flat soil

var crop := ""
var growth := 0.0 # in-game hours of growth
var watered := false
var soil: MeshInstance3D
var crop_root: Node3D
var _stage := -2
var _bob := 0.0
## The model's soil surfaces, [MeshInstance3D, surface index], and their wet material.
var _soil_slots: Array = []
var _soil_wet: Material


func _ready() -> void:
	var inst := Catalog.model(MODEL, self)
	if inst:
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(i)
				if sm and sm.resource_name == "Soil_plot":
					_soil_slots.append([m, i])
					if sm is BaseMaterial3D and _soil_wet == null:
						var wet := sm.duplicate() as BaseMaterial3D
						wet.albedo_color = Color(0.55, 0.5, 0.48) # damp earth
						wet.roughness = 0.6
						_soil_wet = wet
	if _soil_slots.is_empty():
		soil = Catalog.box(self, Vector3(1.0, 0.1, 1.0), Vector3(0, 0.03, 0), DRY)
		for i in 3:
			Catalog.box(self, Vector3(0.9, 0.025, 0.08), Vector3(0, 0.085, -0.3 + i * 0.3), DRY.darkened(0.15))
	var lift := Node3D.new()
	lift.position.y = CROP_LIFT if soil == null else 0.0
	add_child(lift)
	crop_root = Node3D.new()
	lift.add_child(crop_root)
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
	if soil:
		soil.material_override = Catalog.mat(WET if watered else DRY)
	for slot in _soil_slots:
		(slot[0] as MeshInstance3D).set_surface_override_material(int(slot[1]), _soil_wet if watered else null)
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
