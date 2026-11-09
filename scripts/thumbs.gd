extends Node
## Renders a small picture of each catalog item for the Build & Buy cards, from the same
## furniture models the game places (Catalog.build), in an offscreen viewport of its own.
## One item per frame or two at startup; the cards fill in as the pictures arrive.

const Catalog = preload("res://scripts/catalog.gd")
const SIZE := Vector2i(200, 150)

signal thumb_ready(id: String, tex: Texture2D)
signal all_done

var done := {} # id -> Texture2D


func render(ids: Array) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.8)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 28.0
	vp.add_child(cam)
	for id in ids:
		var holder := Node3D.new()
		vp.add_child(holder)
		Catalog.build(str(id), holder)
		var box := _aabb(holder)
		var c := box.get_center()
		var radius := maxf(box.size.length() * 0.5, 0.2)
		var dir := Vector3(1.0, 0.8, 1.35).normalized()
		var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.02
		cam.near = maxf(0.02, dist - radius * 2.0)
		cam.far = dist + radius * 3.0
		cam.look_at_from_position(c + dir * dist, c)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
		done[str(id)] = tex
		thumb_ready.emit(str(id), tex)
		holder.queue_free()
	vp.queue_free()
	all_done.emit()


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		if v is Light3D:
			continue
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
