extends Node3D
## A skinned humanoid made by tools/build_character.py (see data/characters.json).
## Every character shares one 22-bone skeleton and the same animation loops, so the
## player and NPCs all move with the same library. Callers pick a loop; this cross-fades.

const Data = preload("res://scripts/data.gd")
const ANIMS := ["Idle", "Walk", "SitKnit", "SitIdle", "Work", "Talk"]
const BLEND := 0.22

var id := ""
var ok := false # true when the model loaded with every loop
var anim: AnimationPlayer
var skeleton: Skeleton3D
var props: Node3D # knitting needles and swatch, shown only while knitting
var walk_anim_speed := 3.0
var label_height := 2.1


## Loads the character's model. Returns false (and adds nothing) if it's missing or incomplete.
func load_character(char_id: String) -> bool:
	id = char_id
	var info := Data.character(char_id)
	walk_anim_speed = float(info.get("walk_anim_speed", 3.0))
	label_height = float(info.get("label_height", 2.1))
	var path := str(info.get("model", "res://assets/%s.glb" % char_id))
	if not ResourceLoader.exists(path):
		push_warning("%s: model %s is missing" % [char_id, path])
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate() as Node3D
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		inst.free()
		push_warning("%s has no animations" % path)
		return false
	anim = aps[0]
	for n in ANIMS:
		if not anim.has_animation(n):
			inst.free()
			anim = null
			push_warning("%s is missing the %s loop" % [path, n])
			return false
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	add_child(inst)
	var sk := inst.find_children("*", "Skeleton3D", true, false)
	skeleton = sk[0] if not sk.is_empty() else null
	props = inst.find_child("KnitProps", true, false) as Node3D
	if props:
		props.visible = false
	anim.play("Idle")
	ok = true
	return true


## Cross-fades to a loop. For "Walk", pass the ground speed so the stride matches it.
func play(loop_name: String, ground_speed := 0.0) -> void:
	if not ok:
		return
	if anim.current_animation != loop_name:
		anim.play(loop_name, BLEND)
	anim.speed_scale = ground_speed / walk_anim_speed if loop_name == "Walk" and ground_speed > 0.0 else 1.0
	if props:
		props.visible = loop_name == "SitKnit"


func current() -> String:
	return anim.current_animation if ok else ""


func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	if skeleton:
		for i in skeleton.get_bone_count():
			out.append(skeleton.get_bone_name(i))
	return out
