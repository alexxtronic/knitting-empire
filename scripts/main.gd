extends Node3D
## Knitting Empire prototype: world setup, camera, input, pathfinding,
## actions, build mode, house expansion and saving.

const Catalog = preload("res://scripts/catalog.gd")
const World = preload("res://scripts/world.gd")
const Furniture = preload("res://scripts/furniture.gd")
const Plot = preload("res://scripts/plot.gd")
const Sheep = preload("res://scripts/sheep.gd")
const Player = preload("res://scripts/player.gd")
const Data = preload("res://scripts/data.gd")
const Hud = preload("res://scripts/hud.gd")
const Town = preload("res://scripts/town.gd")
const Grass = preload("res://scripts/grass.gd")
const Villager = preload("res://scripts/villager.gd")
const Story = preload("res://scripts/story.gd")
const StoryPlayer = preload("res://scripts/story_player.gd")
const Landmark = preload("res://scripts/landmark.gd")
const Dialogue = preload("res://scripts/dialogue.gd")
const AiChat = preload("res://scripts/ai_chat.gd")
const GameAudio = preload("res://scripts/audio.gd")
const Nature = preload("res://scripts/nature.gd")
const GodMode = preload("res://scripts/god_mode.gd")

const CELL := 0.5
const GRID_ORIGIN := Vector2(-8.0, -22.0)
const GRID_SIZE := Vector2i(160, 76) # covers x -8..72, z -22..16 (farm, road and Maplewood)
const HOUSE_W := 8.0
const HOUSE_FRONT := 6.0
const WALL_H := 2.6
const WALL_T := 0.2
const DOOR_Z0 := 2.3
const DOOR_Z1 := 3.7
const LOT := Rect2(-5, -19, 32, 31) # walkable / buildable yard: x -5..27, z -19..12
const PEN := Rect2(17, -4, 6, 6)
const PEN_GATE := Vector2(-1.6, -0.4)
const BIN_POS := Vector3(10.2, 0, 4.6)
const CAM_PITCH := 48.0
const CAM_PITCH_LOW := 20.0 # story close-ups ("@camera ... low")
const CAM_BOUNDS := Rect2(-5, -19, 75, 33) # farm + town
const PLASTER := Color(0.92, 0.86, 0.74)

enum Mode { LIVE, BUILD }

var mode := Mode.LIVE
var autotest_jog := false # the autotest jogs her everywhere (as if Shift were held), so its timings hold
var cam: Camera3D
var cam_target := Vector3(6, 0, 2.5)
var cam_yaw := deg_to_rad(45.0)
var cam_yaw_goal := deg_to_rad(45.0)
var cam_dist := 23.0
var cam_pitch := CAM_PITCH
var cam_follow := true
var cam_glide := {} # story camera cue: {"pos": Vector3, "dist": float}; the camera eases toward it
var drag_pan := false
var walls_up := false

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial # shaders/sky.gdshader: gradient, sun, drifting clouds, stars
var cam_attr: CameraAttributesPractical
var _cloud_drift := Vector2.ZERO

var house_root: Node3D
var furniture_root: Node3D
var walls: Array = [] # {tall, short, normal, cut}
var wall_rects: Array = []
var divider_rects: Array = []
var furniture: Array = []
var plots: Array = []
var sheep_list: Array = []
var grass # grass.gd: the ground and the blades
var nature # nature.gd: rocks, plants, hedges, fences, lamp posts and benches
var god: GodMode # god_mode.gd: the admin's world editor, and the saved layout it applies at launch
var pond_rect := Rect2()
var pen_rect := PEN # where the sheep pen stands now (god mode can move it)
var bin: Node3D
var grid_blockers: Array = [] # static outdoor obstacles (Rect2)
var place_blockers: Array = [] # areas furniture can't go (Rect2)
var astar := AStarGrid2D.new()
var player: Player
var hud: Hud
var audio: GameAudio
var story: StoryPlayer
var villagers: Array = []
var ai: AiChat # typed chat with villagers, voiced by Claude
var chat_v = null # the villager you're chatting with
var _chat_clock_was := true
var decor: Array = [] # town lanterns/benches: furniture you can use but not pick up
var decor_root: Node3D
var sign_to_town: Landmark
var sign_to_farm: Landmark
var price_board: Label3D
var _morning_note := ""
# story staging (Act 1 and later): see the @goal, @weather, @prop, @shake, @sheep, @home commands
var areas := {} # name -> Rect2, from data/areas.json
var _area_t := 0.0
var goal_marker: Node3D
var props := {} # name -> Node3D placed by @prop
var rain_fx: CPUParticles3D
var rain := 0.0 # 0 clear .. 1 raining (eases toward the weather flag)
var _shake_t := 0.0
var _shake_len := 0.0

var ghost: Furniture = null
var ghost_rot := 0
var ghost_from = null # {pos, rot} when moving an existing piece
var ghost_valid := false
var ghost_marker: MeshInstance3D
var _mark_ok: StandardMaterial3D
var _mark_bad: StandardMaterial3D
var _last_mouse := Vector2.ZERO

var sleeping := false
var _autosave_t := 0.0
var _autotest_dir := ""
var _style_frames := false # --styleframes=DIR: take the Woolcore style frames and quit
var _capture := false # --capture: play the opening at a person's pace (record it with --write-movie)
var _fps_probe := false # --fpsprobe: measure frame cost in town with each effect switched off in turn
var _asset_frames := false # --assetframes=DIR: picture the world props (plots, trees, bus) and quit
var _photo_frames := false # --photoframes=DIR: night photos by lamplight with strong bokeh, no HUD
var _god_only := false # --godcheck=DIR: run only the world editor's checks (about a minute)
var _photo_dof := {} # photo mode's depth of field: {"focus": m, "near": m, "far": m, "amount": x}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--capture":
			_capture = true
			a = "--autotest=" + OS.get_user_data_dir()
		if a == "--fpsprobe":
			_fps_probe = true
			a = "--autotest=" + OS.get_user_data_dir()
		if a.begins_with("--assetframes="):
			_asset_frames = true
			a = "--autotest=" + a.substr(14)
		if a.begins_with("--photoframes="):
			_photo_frames = true
			a = "--autotest=" + a.substr(14)
		if a.begins_with("--godcheck="):
			_god_only = true
			a = "--autotest=" + a.substr(11)
		if a.begins_with("--styleframes="):
			_style_frames = true
			a = "--autotest=" + a.substr(14)
		if a.begins_with("--autotest="):
			_autotest_dir = a.substr(11)
			Game.save_path = "user://autotest_save.json"
			if FileAccess.file_exists(Game.save_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
			Game.reset()
	if _autotest_dir != "":
		# the test window opens over whatever you're doing: let your mouse pass through it, so a
		# stray click or hover can't send Nora somewhere else or move a piece being placed
		get_window().mouse_passthrough = true
	_setup_environment()
	_fit_3d_resolution()
	get_viewport().size_changed.connect(_fit_3d_resolution)
	cam = Camera3D.new()
	cam.fov = 32.0
	# the camera never comes closer than about 6 m; a near plane at 0.5 m instead of 0.05 gives the
	# depth buffer ten times the precision, so surfaces a few millimetres apart stay apart at 40 m
	cam.near = 0.5
	cam.far = 300.0
	cam.attributes = cam_attr
	add_child(cam)
	grass = Grass.new()
	add_child(grass)
	World.build_ground(self, LOT)
	World.build_trees(self, [LOT, Town.ROAD.grow(0.8), Town.TOWN])
	nature = Nature.new()
	add_child(nature)
	grid_blockers.append_array(nature.build(self, _nature_keep()))
	var town := Town.build(self)
	grid_blockers.append_array(town["blockers"])
	price_board = town["board"]
	sign_to_town = town["sign_to_town"]
	sign_to_farm = town["sign_to_farm"]
	decor_root = Node3D.new()
	add_child(decor_root)
	_build_town_decor()
	grid_blockers.append(World.build_barn(self, Vector3(21.5, 0, -9.5)))
	pond_rect = World.build_pond(self, Vector3(2.5, 0, -16.0), 2.0)
	grid_blockers.append(pond_rect)
	grid_blockers.append_array(World.build_pen(self, PEN, PEN_GATE))
	bin = World.build_bin(self, BIN_POS)
	grid_blockers.append(Rect2(BIN_POS.x - 0.5, BIN_POS.z - 0.35, 1.0, 0.7))
	house_root = Node3D.new()
	add_child(house_root)
	furniture_root = Node3D.new()
	add_child(furniture_root)
	for j in 3:
		for i in 4:
			var p = Plot.new()
			p.position = Vector3(11.0 + i * 1.2, 0, -1.0 + j * 1.2)
			add_child(p)
			plots.append(p)
	for i in int(Game.START_SHEEP):
		_add_sheep()
	for v in _villager_defs():
		var vg = Villager.new()
		vg.setup(v["id"], v["name"], v["role"], v["loves"], v["pos"], v["look"])
		vg.roam = v["roam"]
		vg.likes = v.get("likes", [])
		vg.romance = bool(v.get("romance", false))
		if v.has("talk_spot"):
			vg.talk_spot = v["talk_spot"]
		add_child(vg)
		villagers.append(vg)
	place_blockers.append_array(grid_blockers)
	place_blockers.append(Rect2(10.4, -1.6, 4.8, 3.6)) # farm plots
	place_blockers.append(PEN.grow(0.3))
	place_blockers.append(Rect2(HOUSE_W - 1.0, DOOR_Z0 - 0.1, 2.4, DOOR_Z1 - DOOR_Z0 + 0.2)) # doorway, both sides
	place_blockers.append(Rect2(Town.COTTAGE_DOOR.x - 0.2, Town.COTTAGE.position.y - 1.2, Town.COTTAGE_DOOR.y - Town.COTTAGE_DOOR.x + 0.4, 2.5)) # cottage doorway
	place_blockers.append(Rect2(56.6, 5.1, 1.4, 0.5)) # cottage sign
	# the world as arranged in god mode (data/world_layout.json) goes on top of what was just built
	god = GodMode.new()
	god.main = self
	add_child(god)
	god.collect()
	if Engine.has_meta("ke_god_reload"):
		god.layout_path = GOD_TEST_LAYOUT # the autotest's last step: the world again, from the layout it saved
	if not OS.get_cmdline_user_args().has("--nolayout") and not Engine.has_meta("ke_god_stock"):
		god.load_layout()
	if _autotest_dir != "":
		god.layout_path = GOD_TEST_LAYOUT # the test saves here, never over the real layout
	player = Player.new()
	player.position = Vector3(4.6, 0, 4.9)
	add_child(player)
	hud = Hud.new()
	add_child(hud)
	audio = GameAudio.new()
	add_child(audio)
	audio.setup(self, _autotest_dir != "")
	hud.sfx = audio.play
	player.footstep.connect(func(): audio.footstep(player.position))
	player.needle_click.connect(audio.needle)
	story = StoryPlayer.new()
	story.main = self
	add_child(story)
	_setup_story_staging()
	_connect_hud()
	Game.toast.connect(hud.show_toast)
	Game.day_started.connect(_on_day_started)
	_setup_ghost_marker()
	astar.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var loaded := _load_game()
	if not loaded:
		_new_world()
	_rebuild_house()
	_rebuild_grid()
	_update_expand_button()
	_update_price_board()
	cam_target = player.position
	_restore_story_state()
	_load_graphics()
	hud.render_thumbnails()
	_load_display()
	tips_enabled = _autotest_dir == "" # the autotest turns them on for its own check
	# the title screen greets a normal launch; "New Game" from it reloads the scene and skips it
	var skip_title := bool(Engine.get_meta("ke_skip_title", false))
	Engine.set_meta("ke_skip_title", false)
	if _autotest_dir == "" and not skip_title:
		show_title(loaded)
	elif not loaded and _autotest_dir == "":
		_begin_new_story()
	if _capture:
		_capture_opening()
	elif _fps_probe:
		_run_fps_probe()
	elif _style_frames:
		_take_style_frames()
	elif _asset_frames:
		_take_asset_frames()
	elif _photo_frames:
		_take_photo_frames()
	elif Engine.has_meta("ke_god_reload"):
		_god_reload_checks()
	elif Engine.has_meta("ke_god_stock"):
		Engine.remove_meta("ke_god_stock")
		_god_checks()
	elif _god_only:
		_god_checks()
	elif _autotest_dir != "":
		_autotest()
	else:
		DisplayServer.window_move_to_foreground()


func _connect_hud() -> void:
	hud.mode_selected.connect(func(b): set_mode(Mode.BUILD if b else Mode.LIVE))
	hud.expand_pressed.connect(_expand_house)
	hud.walls_pressed.connect(func(): walls_up = not walls_up)
	hud.graphics_pressed.connect(_cycle_graphics)
	hud.save_pressed.connect(func():
		_save_game()
		hud.show_toast("Game saved."))
	hud.new_game_pressed.connect(_new_game)
	hud.title_continue.connect(_title_continue)
	hud.title_new_game.connect(_title_new_game)
	hud.title_quit.connect(func(): get_tree().quit())
	hud.volumes_changed.connect(audio.set_volumes)
	hud.music_slider.get_parent().visible = GameAudio.MUSIC_ON
	hud.fullscreen_toggled.connect(set_fullscreen)
	hud.settings_panel.visibility_changed.connect(func():
		if hud.settings_panel.visible:
			hud.music_slider.set_value_no_signal(audio.music_volume)
			hud.sound_slider.set_value_no_signal(audio.sound_volume)
			hud.show_god_state(Game.hour, str(Game.flag("weather", "clear")), Game.clock_frozen)
			hud.show_god_edit(GodMode.is_admin(), god.active))
	hud.god_edit.connect(func(on: bool):
		if on and title_on:
			hud.show_god_edit(true, false)
			hud.show_toast("Continue or start a game first, then edit the world.")
		else:
			god.set_active(on))
	hud.god_time.connect(func(h: float): Game.hour = h)
	hud.god_weather.connect(func(w: String): Game.set_flag("weather", w))
	hud.god_freeze.connect(func(on: bool): Game.clock_frozen = on)
	hud.item_chosen.connect(_begin_place)
	hud.rotate_pressed.connect(_rotate_ghost)
	hud.sell_pressed.connect(_sell_ghost)
	hud.cancel_pressed.connect(_cancel_ghost)
	hud.stop_activity_pressed.connect(func():
		if player.activity_text() != "Zzz":
			player.cancel_activity())
	hud.cam_lock_pressed.connect(func(): _set_cam_lock(not cam_follow, true))
	hud.cam_rotate.connect(func(d): cam_yaw_goal += d * PI * 0.5)
	hud.cam_zoom.connect(func(d): cam_dist = clampf(cam_dist + d * 3.0, 8.0, 45.0))
	ai = AiChat.new()
	add_child(ai)
	ai.replied.connect(_on_chat_reply)
	hud.chat.sent.connect(_chat_send)
	hud.chat.closed.connect(close_chat)
	hud.chat.key_entered.connect(func(k: String):
		ai.save_key(k)
		hud.chat.set_online(ai.available())
		hud.chat.show_note("Key saved on this computer (not in the game files). Say hello!" if ai.available() else "That key didn't take."))


func _set_cam_lock(on: bool, announce := false) -> void:
	if on == cam_follow:
		return
	cam_follow = on
	hud.set_cam_locked(on)
	if announce:
		hud.show_toast("Camera locked onto you." if on else "Camera unlocked: pan anywhere.")


# --- environment & lighting ------------------------------------------------------

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0 # bright sun on cream walls rolls off softly instead of clipping
	# contact darkening where things meet the ground, and it shows in sunlight too
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.15
	# the pond (and puddly ground in the rain) reflects what's around it
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.0
	# light bouncing off the ground and walls tints what's near it (green under trees, warm indoors)
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1 # only real highlights glow (lamps, the sun on water), not the whole frame
	# Woolcore grade: plum-tinted shadows, warm cream highlights, a touch more contrast
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	var grade := Gradient.new()
	grade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grade.colors = PackedColorArray([Color(0.025, 0.012, 0.035), Color(0.52, 0.49, 0.455), Color(1.0, 0.97, 0.9)])
	var lut := GradientTexture1D.new()
	lut.gradient = grade
	lut.width = 256
	env.adjustment_color_correction = lut
	env.fog_enabled = true
	env.fog_density = 0.0015
	# a thin volumetric haze: sunbeams through the trees at dawn and dusk, mist in the rain
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.002
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.04
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0 # _update_camera tightens this when zoomed in
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	# Godot's standard offsets: lower ones made flat tops (wall caps, sills) shade themselves in a
	# pattern that jumped every frame as the camera followed Nora (measured 3-5x more flicker)
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 1.0
	# the real sun is about half a degree across: crisp where a thing touches the ground,
	# softer the further the shadow falls from it
	sun.light_angular_distance = 0.55
	sun.light_volumetric_fog_energy = 1.3
	add_child(sun)
	# depth of field for close-ups (_update_camera turns it on when the camera's near)
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_amount = 0.05


## The 3D scene is drawn at about 1.6 million pixels whatever the window size, then upscaled
## (MetalFX on Macs, FSR elsewhere); the menus stay at full resolution. A full-screen Retina
## window is 4 to 7 million pixels, which a laptop GPU can't fill at 60 fps with these effects.
## Per graphics level (Low, Medium, High): 3D pixels to aim for and the lowest scale allowed.
const TARGET_3D_PIXELS := [0.7e6, 1.1e6, 1.6e6]
const MIN_3D_SCALE := [0.25, 0.3, 0.35]
const METALFX_MIN_SCALE := 0.34 # MetalFX temporal upscales at most 3x

# --- graphics setting ----------------------------------------------------------------
## Low / Medium / High, cycled from the left-hand menu and kept in user://settings.cfg (not the
## save file: it belongs to the computer, not the farm). The autotest always runs on High.
const GFX_NAMES := ["Low", "Medium", "High"]
const SETTINGS_PATH := "user://settings.cfg"
var gfx := 2


func _load_graphics() -> void:
	if _autotest_dir == "":
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			gfx = clampi(int(cfg.get_value("graphics", "quality", 2)), 0, 2)
	apply_graphics()


func _cycle_graphics() -> void:
	gfx = (gfx + 2) % 3 # High → Medium → Low → High
	apply_graphics()
	if _autotest_dir == "":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("graphics", "quality", gfx)
		cfg.save(SETTINGS_PATH)
	hud.show_toast("Graphics: %s" % GFX_NAMES[gfx])


func apply_graphics() -> void:
	var med := gfx >= 1
	var hi := gfx == 2
	env.ssao_enabled = med # contact shading
	env.ssil_enabled = hi # light bouncing off nearby surfaces
	env.ssr_enabled = hi # reflections in the pond and wet ground
	# the sun's soft shadows use the high filter at every setting: the shadow filter jitters its
	# samples each frame for the upscaler to average out, and with fewer samples the soft edges
	# (the long end of a shadow most of all) visibly vibrate. Rendering at a third of the screen
	# keeps the extra samples cheap.
	RenderingServer.directional_soft_shadow_filter_set_quality([4, 4, 5][gfx])
	RenderingServer.positional_soft_shadow_filter_set_quality([1, 2, 3][gfx])
	Catalog.lamp_shadows = med
	for l in find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).shadow_enabled = med
	grass.set_quality([0.45, 0.75, 1.0][gfx], [30.0, 40.0, 46.0][gfx])
	_fit_3d_resolution()
	hud.set_graphics_label(GFX_NAMES[gfx])


func _fit_3d_resolution() -> void:
	var vp := get_viewport()
	var px := Vector2(get_window().size)
	# the window renders at the screen's real pixels (project.godot: allow_hidpi off). A "2x scaled"
	# 1440p monitor would otherwise hand the game a 5120x2880 frame that macOS then shrinks back to
	# 2560x1440: four times the upscaling, post-processing and HUD work for nothing on screen.
	# Below about a third of the width, fine detail and thin edges break up when upscaled.
	var scale := clampf(sqrt(float(TARGET_3D_PIXELS[gfx]) / maxf(px.x * px.y, 1.0)), float(MIN_3D_SCALE[gfx]), 1.0)
	if scale > 0.95:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X if gfx == 0 else Viewport.MSAA_4X
		return
	if OS.get_name() == "macOS":
		# MetalFX temporal builds each frame from the last few, so the thousands of hair-thin grass
		# blades stay put as the camera follows Nora. Spatial upscalers (FSR 1, MetalFX spatial)
		# see one frame at a time: blades a pixel or two wide popped in and out every frame, the
		# flicker on every graphics level (measured 3x less frame-to-frame change). It brings its
		# own anti-aliasing, so MSAA is off.
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
		vp.scaling_3d_scale = maxf(scale, METALFX_MIN_SCALE)
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.msaa_3d = Viewport.MSAA_2X if gfx == 0 else Viewport.MSAA_4X
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.8 # 0 is sharpest; a softer setting keeps thin edges from ringing


func _update_lighting() -> void:
	var dl := Game.daylight()
	var t := clampf((Game.hour - 6.0) / 13.0, 0.0, 1.0)
	var arc := sin(t * PI)
	var elev := lerpf(38.0, 12.0 + 48.0 * arc, dl)
	var yaw := lerpf(-30.0, lerpf(35.0, -85.0, t), dl)
	sun.rotation_degrees = Vector3(-elev, yaw, 0)
	var warm := 1.0 - arc
	var day_col := Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.62, 0.36), warm * 0.85)
	sun.light_color = Color(0.55, 0.65, 1.0).lerp(day_col, dl)
	sun.light_energy = lerpf(0.3, 1.85, dl)
	var horizon := Color(0.14, 0.15, 0.28).lerp(Color(0.97, 0.82, 0.62).lerp(Color(1.0, 0.62, 0.4), warm * 0.6), dl)
	var top := Color(0.06, 0.08, 0.2).lerp(Color(0.38, 0.6, 0.86), dl)
	var sky_h := horizon
	env.ambient_light_energy = lerpf(0.38, 0.5, dl)
	env.fog_light_color = horizon
	if rain > 0.001: # overcast: a dimmer, greyer, mistier day
		var grey := Color(0.52, 0.55, 0.6).lerp(Color(0.12, 0.13, 0.18), 1.0 - dl)
		sun.light_energy *= 1.0 - 0.6 * rain
		sun.light_color = sun.light_color.lerp(Color(0.75, 0.8, 0.9), rain * 0.7)
		top = top.lerp(grey.darkened(0.15), rain * 0.85)
		sky_h = horizon.lerp(grey, rain * 0.85)
		env.fog_light_color = sky_h
		env.ambient_light_energy *= 1.0 - 0.25 * rain
	sky_mat.set_shader_parameter("sky_top_color", top)
	sky_mat.set_shader_parameter("sky_horizon_color", sky_h)
	sky_mat.set_shader_parameter("ground_horizon_color", sky_h)
	sky_mat.set_shader_parameter("ground_bottom_color", Color(0.08, 0.08, 0.1).lerp(Color(0.35, 0.3, 0.25), dl))
	sky_mat.set_shader_parameter("cloud_cover", 0.3 + 0.62 * rain)
	sky_mat.set_shader_parameter("night", 1.0 - dl)
	sky_mat.set_shader_parameter("cloud_light", Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.72, 0.5), warm * 0.7 * dl).lerp(Color(0.7, 0.72, 0.76), rain * 0.8))
	sky_mat.set_shader_parameter("cloud_shade", Color(0.62, 0.6, 0.7).lerp(Color(0.4, 0.42, 0.48), rain))
	_cloud_drift += Vector2(0.82, 0.57) * get_process_delta_time() * (0.012 + 0.02 * rain)
	sky_mat.set_shader_parameter("cloud_offset", _cloud_drift)
	env.fog_density = 0.0012 + 0.0068 * rain
	# haze only when it earns its keep: rain, and low sun at dawn and dusk (sunbeams)
	env.volumetric_fog_density = 0.01 * rain + 0.004 * warm * warm * dl
	env.volumetric_fog_enabled = gfx >= 1 and env.volumetric_fog_density > 0.0006
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.95).lerp(horizon, 0.3)
	env.adjustment_saturation = 1.1 - 0.3 * rain
	if World.foliage_mat:
		World.foliage_mat.set_shader_parameter("wind", 0.18 + rain * 0.3)
		World.foliage_mat.set_shader_parameter("wet", rain)
	for m in World.leaf_mats:
		m.set_shader_parameter("wind", 0.18 + rain * 0.3)
		m.set_shader_parameter("wet", rain)
	if World.litter_mat:
		World.litter_mat.set_shader_parameter("wet", rain)
	if World.water_mat:
		World.water_mat.set_shader_parameter("rain", rain)
	var dryness := {"Spring": 0.05, "Summer": 0.25, "Autumn": 0.5, "Winter": 0.8}
	grass.set_conditions(rain, float(dryness.get(Game.season_name(), 0.4)))


# --- house -------------------------------------------------------------------------

func _zmin() -> float:
	return -4.0 * Game.house_level


## What's underfoot at a spot, for footsteps: "wood" indoors (home or Rosewood Cottage), else "grass".
func surface_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	return "wood" if interior_rect().has_point(q) or Town.COTTAGE.has_point(q) else "grass"


func player_indoors() -> bool:
	return surface_at(player.position) == "wood"


func interior_rect() -> Rect2:
	var z0 := _zmin()
	return Rect2(0.1, z0 + 0.1, HOUSE_W - 0.2, HOUSE_FRONT - z0 - 0.2)


func house_rect() -> Rect2:
	var z0 := _zmin()
	return Rect2(-WALL_T * 0.5, z0 - WALL_T * 0.5, HOUSE_W + WALL_T, HOUSE_FRONT - z0 + WALL_T)


## Rock, plant and fence placement (scripts/nature.gd) keeps clear of these: the house and its
## doorway, the beds, the pen, the pond, the barn, every path and building in town, the story's
## named places.
func _nature_keep() -> Array:
	var keep: Array = [Rect2(-0.8, -13.0, 10.0, 20.0), Rect2(10.0, -2.4, 6.0, 5.0), PEN.grow(0.6), Rect2(0.0, -18.5, 5.0, 5.0),
		Rect2(18.9, -11.6, 5.2, 4.2), Rect2(9.7, 4.2, 1.2, 0.9), Town.ROAD, Town.PLAZA, Town.SHOP, Town.OFFICE, Town.BAKERY,
		Town.COTTAGE.grow(0.6), Rect2(56.0, 4.4, 2.0, 1.4)]
	keep.append_array(World.PATHS)
	keep.append_array(Town.PATHS)
	var d := Data.load_json("areas")
	for k in d.get("areas", {}):
		var a: Array = d["areas"][k]
		if k != "cottage_inside":
			keep.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
	return keep


## Where grass grows: not on paths, in the beds, under buildings and the house, or in the pond.
## Once roads have been painted in god mode, the painted map stands in for the paths and the plaza.
## replant = false only redraws the ground (god mode, while a road is being painted).
func _rebuild_grass(replant := true) -> void:
	var painted: bool = god != null and god.roads_on
	var dirt: Array = []
	if not painted:
		dirt.append_array(World.PATHS)
		dirt.append_array(Town.PATHS)
	dirt.append_array(god.bed_rects() if god != null else [GodMode.BEDS])
	var clear: Array = grid_blockers.filter(func(r): return r != pond_rect)
	clear.append(Rect2(-0.35, _zmin() - 0.35, HOUSE_W + 0.7, HOUSE_FRONT - _zmin() + 0.7))
	if not painted:
		clear.append(Town.PLAZA)
	clear.append(Town.COTTAGE.grow(0.3))
	clear.append(Rect2(8.1, 2.35, 1.0, 1.3)) # doormat
	var roads: Image = god.road_img if painted else null
	var pond: Array = god.pond_circles() if god != null else [Vector3(2.5, -16.0, 2.55)]
	if replant:
		grass.build(dirt, clear, pond, roads)
	else:
		grass.remask(dirt, clear, pond, roads)


func _rebuild_house() -> void:
	for c in house_root.get_children():
		c.free()
	walls.clear()
	_rebuild_grass()
	wall_rects.clear()
	divider_rects.clear()
	var z0 := _zmin()
	var W := HOUSE_W
	var D := HOUSE_FRONT
	var depth := D - z0
	Catalog.box(house_root, Vector3(W + 0.7, 0.1, depth + 0.7), Vector3(W * 0.5, -0.04, z0 + depth * 0.5), Catalog.STONE)
	var plank_cols := [Color(0.55, 0.36, 0.22), Color(0.6, 0.4, 0.25), Color(0.5, 0.33, 0.2), Color(0.57, 0.38, 0.23)]
	var n := int(W / 0.4)
	for i in n:
		Catalog.box(house_root, Vector3(0.385, 0.04, depth), Vector3(0.2 + i * 0.4, 0.0, z0 + depth * 0.5), plank_cols[(i * 7) % 4])
	var lvl := Game.house_level
	var left_windows := [4.8]
	var right_windows := [0.9]
	for k in range(1, lvl + 1):
		left_windows.append(-4.0 * k + 2.0)
		right_windows.append(-4.0 * k + 2.0)
	var back := _wall(Vector2(0, z0), Vector2(W, z0), Vector3(0, 0, -1), [2.0, 6.0])
	_wall(Vector2(0, D), Vector2(W, D), Vector3(0, 0, 1), [2.0, 6.0])
	_wall(Vector2(0, z0), Vector2(0, D), Vector3(-1, 0, 0), left_windows)
	_wall(Vector2(W, z0), Vector2(W, DOOR_Z0), Vector3(1, 0, 0), right_windows)
	_wall(Vector2(W, DOOR_Z1), Vector2(W, D), Vector3(1, 0, 0), [4.9])
	_door_lintel()
	for k in range(1, lvl + 1):
		var z := -4.0 * (k - 1)
		_wall(Vector2(0, z), Vector2(2.6, z), Vector3(0, 0, 1), [], 1.1, false, true)
		_wall(Vector2(5.4, z), Vector2(W, z), Vector3(0, 0, 1), [], 1.1, false, true)
	# the empire banner hangs on the back wall, above the bed corner
	var tall: Node3D = back["tall"]
	var bx := 6.9 - W * 0.5
	Catalog.cyl(tall, 0.02, 0.02, 0.9, Vector3(bx, 2.28, 0.14), Catalog.WOOD_DARK, Vector3(0, 0, 90))
	Catalog.box(tall, Vector3(0.7, 1.0, 0.03), Vector3(bx, 1.75, 0.13), Catalog.PLAID_DARK)
	Catalog.box(tall, Vector3(0.6, 0.04, 0.035), Vector3(bx, 2.15, 0.135), Catalog.BRASS)
	Catalog.ball(tall, 0.15, Vector3(bx, 1.8, 0.15), Color(0.78, 0.25, 0.3), Vector3(1, 1, 0.3))
	Catalog.ring(tall, 0.17, 0.2, Vector3(bx, 1.8, 0.15), Catalog.BRASS, Vector3(90, 0, 0))
	_build_cottage()
	_update_walls()


func _wall(a: Vector2, b: Vector2, normal: Vector3, windows: Array, height := WALL_H, cut := true, divider := false) -> Dictionary:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var node := Node3D.new()
	node.position = Vector3(mid.x, 0, mid.y)
	house_root.add_child(node)
	var tall := Node3D.new()
	node.add_child(tall)
	var short := Node3D.new()
	node.add_child(short)
	Catalog.box(tall, _sz(horizontal, length, height, WALL_T), _at(horizontal, 0, height * 0.5), PLASTER)
	Catalog.box(tall, _sz(horizontal, length + 0.02, 0.16, WALL_T + 0.06), _at(horizontal, 0, height - 0.08), Catalog.WOOD_DARK)
	Catalog.box(tall, _sz(horizontal, length, 0.14, WALL_T + 0.04), _at(horizontal, 0, 0.07), Catalog.WOOD_DARK)
	var posts := maxi(1, int(round(length / 2.0)))
	for i in posts + 1:
		var o := -length * 0.5 + length * i / posts
		Catalog.box(tall, _sz(horizontal, 0.16, height, WALL_T + 0.05), _at(horizontal, o, height * 0.5), Catalog.WOOD_DARK)
	for wpos in windows:
		_window(tall, float(wpos) - (mid.x if horizontal else mid.y), horizontal)
	Catalog.box(short, _sz(horizontal, length, 0.32, WALL_T), _at(horizontal, 0, 0.16), PLASTER)
	Catalog.box(short, _sz(horizontal, length + 0.02, 0.06, WALL_T + 0.06), _at(horizontal, 0, 0.33), Catalog.WOOD_DARK)
	short.visible = false
	var w := {"tall": tall, "short": short, "normal": normal, "cut": cut}
	walls.append(w)
	var r := Rect2(minf(a.x, b.x) - WALL_T * 0.5, minf(a.y, b.y) - WALL_T * 0.5, absf(b.x - a.x) + WALL_T, absf(b.y - a.y) + WALL_T)
	wall_rects.append(r)
	if divider:
		divider_rects.append(r)
	return w


func _sz(horizontal: bool, along: float, h: float, thick: float) -> Vector3:
	return Vector3(along, h, thick) if horizontal else Vector3(thick, h, along)


func _at(horizontal: bool, along: float, y: float, out := 0.0) -> Vector3:
	return Vector3(along, y, out) if horizontal else Vector3(out, y, along)


func _window(parent: Node3D, o: float, horizontal: bool) -> void:
	var glass := Catalog.box(parent, _sz(horizontal, 1.0, 1.0, WALL_T + 0.02), _at(horizontal, o, 1.55), Color(0.7, 0.85, 0.95))
	glass.material_override = Catalog.mat(Color(0.7, 0.85, 0.95), 0.1)
	var t := WALL_T + 0.08
	for y in [1.03, 2.07]:
		Catalog.box(parent, _sz(horizontal, 1.16, 0.08, t), _at(horizontal, o, y), Catalog.WOOD_DARK)
	for d in [-0.54, 0.54]:
		Catalog.box(parent, _sz(horizontal, 0.08, 1.12, t), _at(horizontal, o + d, 1.55), Catalog.WOOD_DARK)
	Catalog.box(parent, _sz(horizontal, 0.04, 1.0, t - 0.02), _at(horizontal, o, 1.55), Catalog.WOOD_DARK)
	Catalog.box(parent, _sz(horizontal, 1.0, 0.04, t - 0.02), _at(horizontal, o, 1.55), Catalog.WOOD_DARK)
	Catalog.box(parent, _sz(horizontal, 1.25, 0.06, WALL_T + 0.24), _at(horizontal, o, 0.98), Catalog.WOOD)


func _door_lintel() -> void:
	var node := Node3D.new()
	node.position = Vector3(HOUSE_W, 0, (DOOR_Z0 + DOOR_Z1) * 0.5)
	house_root.add_child(node)
	var tall := Node3D.new()
	node.add_child(tall)
	var short := Node3D.new()
	node.add_child(short)
	var gap := DOOR_Z1 - DOOR_Z0
	var h := WALL_H - 2.15
	Catalog.box(tall, Vector3(WALL_T, h, gap), Vector3(0, 2.15 + h * 0.5, 0), PLASTER)
	Catalog.box(tall, Vector3(WALL_T + 0.06, 0.16, gap + 0.02), Vector3(0, WALL_H - 0.08, 0), Catalog.WOOD_DARK)
	Catalog.box(tall, Vector3(WALL_T + 0.08, 0.1, gap + 0.1), Vector3(0, 2.15, 0), Catalog.WOOD_DARK)
	# open door leaf, swung outward
	Catalog.box(tall, Vector3(1.2, 2.05, 0.06), Vector3(0.62, 1.03, -gap * 0.5 + 0.05), Catalog.WOOD)
	Catalog.ball(tall, 0.035, Vector3(1.1, 1.0, -gap * 0.5 + 0.1), Catalog.BRASS)
	walls.append({"tall": tall, "short": short, "normal": Vector3(1, 0, 0), "cut": true})


func _update_walls() -> void:
	var cdir := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	for w in walls:
		var hide_it: bool = w["cut"] and not walls_up and (w["normal"] as Vector3).dot(cdir) > 0.25
		w["tall"].visible = not hide_it
		w["short"].visible = hide_it


func _update_expand_button() -> void:
	if Game.house_level >= Game.MAX_HOUSE_LEVEL:
		hud.set_expand_text("House fully expanded", false)
	else:
		hud.set_expand_text("Expand House · %dc" % Game.EXPAND_COSTS[Game.house_level], true)


func _expand_house() -> void:
	if Game.house_level >= Game.MAX_HOUSE_LEVEL:
		return
	var new_area := Rect2(-0.6, _zmin() - 4.6, HOUSE_W + 1.2, 4.6)
	for f in furniture:
		if f.footprint().intersects(new_area):
			hud.show_toast("Move the %s out of the way first — the new room goes there." % f.display_name())
			return
	if not Game.spend(Game.EXPAND_COSTS[Game.house_level]):
		return
	Game.house_level += 1
	_rebuild_house()
	_rebuild_grid()
	_update_expand_button()
	_set_cam_lock(false)
	cam_target = Vector3(HOUSE_W * 0.5, 0, _zmin() + 2.0)
	hud.show_toast("Your house grew! A new room is ready to decorate.")


# --- pathfinding ---------------------------------------------------------------------

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floorf((p.x - GRID_ORIGIN.x) / CELL)), int(floorf((p.z - GRID_ORIGIN.y) / CELL)))


func _cell_center(c: Vector2i) -> Vector3:
	return Vector3(GRID_ORIGIN.x + (c.x + 0.5) * CELL, 0, GRID_ORIGIN.y + (c.y + 0.5) * CELL)


func _walkable(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


func _rebuild_grid() -> void:
	astar.fill_solid_region(astar.region, false)
	for x in GRID_SIZE.x:
		for y in GRID_SIZE.y:
			var c := _cell_center(Vector2i(x, y))
			var p2 := Vector2(c.x, c.z)
			if not (LOT.has_point(p2) or Town.ROAD.has_point(p2) or Town.TOWN.has_point(p2)):
				astar.set_point_solid(Vector2i(x, y), true)
	var rects := []
	rects.append_array(wall_rects)
	rects.append_array(grid_blockers)
	for f in furniture:
		if not f.is_flat():
			rects.append(f.footprint())
	for r in rects:
		_mark_rect((r as Rect2).grow(0.2))


func _mark_rect(r: Rect2) -> void:
	var c0 := _cell(Vector3(r.position.x, 0, r.position.y))
	var c1 := _cell(Vector3(r.end.x, 0, r.end.y))
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var id := Vector2i(x, y)
			if not astar.is_in_boundsv(id):
				continue
			var cc := _cell_center(id)
			if r.has_point(Vector2(cc.x, cc.z)):
				astar.set_point_solid(id, true)


func _nearest_walkable(c: Vector2i, target: Vector3) -> Variant:
	if _walkable(c):
		return c
	for radius in range(1, 10):
		var best = null
		var best_d := INF
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if _walkable(n):
					var d := _cell_center(n).distance_to(target)
					if d < best_d:
						best_d = d
						best = n
		if best != null:
			return best
	return null


func _find_path(from: Vector3, to: Vector3) -> Array:
	var a = _nearest_walkable(_cell(from), from)
	var b = _nearest_walkable(_cell(to), to)
	if a == null or b == null:
		return []
	var ids := astar.get_id_path(a, b, true)
	# allow_partial_path: if the goal is unreachable (e.g. a locked door) we stop at the
	# closest reachable cell, and must not then step straight to the goal.
	var reached: bool = not ids.is_empty() and ids[ids.size() - 1] == b
	var pts := []
	for i in range(1, ids.size()):
		pts.append(_cell_center(ids[i]))
	if reached and _walkable(_cell(to)) and b == _cell(to):
		if pts.is_empty():
			pts.append(Vector3(to.x, 0, to.z))
		else:
			pts[pts.size() - 1] = Vector3(to.x, 0, to.z)
	return _smooth(pts, from)


func _smooth(points: Array, start: Vector3) -> Array:
	var out := []
	var cur := start
	var i := 0
	while i < points.size():
		var j := points.size() - 1
		while j > i and not _line_clear(cur, points[j]):
			j -= 1
		out.append(points[j])
		cur = points[j]
		i = j + 1
	return out


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var steps := int(ceilf(a.distance_to(b) / 0.2))
	for k in range(1, steps + 1):
		if not _walkable(_cell(a.lerp(b, float(k) / steps))):
			return false
	return true


# --- camera & per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if title_on:
		cam_yaw_goal += delta * 0.035 # a slow drift round the farm behind the title
	_update_camera(delta)
	_update_walls()
	_update_lighting()
	_update_story_staging(delta)
	_update_needs(delta)
	_update_gaze()
	_update_chat()
	_update_tips(delta)
	if Game.hour >= 24.0 and not sleeping:
		hud.show_toast("You stayed up too late and fell asleep where you stood!")
		_go_to_sleep(true)
	_autosave_t += delta
	if _autosave_t > 60.0 and _autotest_dir == "":
		_autosave_t = 0.0
		_save_game()


var hide_activity_bar := false # the style frames keep the screen clean


## Needs that depend on the world: warmth (weather, night, indoors, her sweater) and fitness
## (walking). Also her walking speed, and the action bar over her head.
func _update_needs(delta: float) -> void:
	Game.warmth_target = warmth_target()
	grass.set_pusher(player.global_position)
	if player.walked > 0.0:
		if Game.time_running:
			Game.add_need("fitness", player.walked * 0.06)
		player.walked = 0.0
	player.walk_speed = 1.47 + 0.21 * Game.fitness / 100.0 # a brisk walk; the Walk loop speeds up to match
	player.run_speed = 2.75 + 0.6 * Game.fitness / 100.0
	player.running = autotest_jog or _held(KEY_SHIFT)
	var head := player.head_point()
	var show := player.busy and not story.is_playing() and not sleeping and not hide_activity_bar and not cam.is_position_behind(head)
	hud.update_activity(player.activity_text(), player.activity_progress(), cam.unproject_position(head), show, player.activity_text() != "Zzz")


## Where each skinned character looks (rig.gd turns their head): Nora looks ahead along her
## path while walking, so her eyes lead each turn; everyone else glances at the nearest person in
## front of them within a few metres.
func _update_gaze() -> void:
	var people: Array = [player]
	for v in villagers:
		if v.visible:
			people.append(v)
	for a in people:
		if a.body and a.body.rig:
			a.body.look_target = _gaze_for(a, people)


func _gaze_for(a, people: Array) -> Variant:
	var me: Vector3 = a.global_position
	if a == player:
		if player.busy:
			return null
		if not player.path.is_empty():
			var ahead: Vector3 = player.path[mini(1, player.path.size() - 1)]
			if Vector2(ahead.x - me.x, ahead.z - me.z).length() > 0.8:
				return ahead + Vector3(0, 1.25, 0)
	var fwd: Vector3 = a.global_transform.basis.z
	var best = null
	var best_d := 4.5
	for o in people:
		if o == a:
			continue
		var to: Vector3 = o.global_position - me
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.2 and fwd.dot(to / d) > -0.15:
			best = o
			best_d = d
	if best == null:
		return null
	if best.body and best.body.ok:
		return best.body.eye_point()
	return best.global_position + Vector3(0, 1.45, 0)


## How warm she'd get staying where she is: 0 (freezing) .. 100 (toasty).
func warmth_target() -> float:
	if area_at(player.position) == "cottage_inside" or interior_rect().has_point(Vector2(player.position.x, player.position.z)):
		return 82.0
	var season := {"Spring": 0.0, "Summer": 14.0, "Autumn": -6.0, "Winter": -26.0}
	var t := 58.0 + float(season.get(Game.season_name(), 0.0))
	t -= 22.0 * (1.0 - Game.daylight())
	t -= 24.0 * rain
	t += 8.0 * (Game.worn_quality - 1) # a good hand-knit sweater beats the city coat
	return clampf(t, 0.0, 100.0)


func _update_camera(delta: float) -> void:
	if not _photo_dof.is_empty():
		_apply_photo_dof()
	# close-ups get a soft background
	var near := cam_dist < 9.0 and _photo_dof.is_empty()
	if _photo_dof.is_empty():
		cam_attr.dof_blur_far_enabled = near
	# spend the shadow map on what's on screen: sharper shadows the closer the camera is
	sun.directional_shadow_max_distance = clampf(cam_dist * 2.4 + 8.0, 20.0, [40.0, 55.0, 70.0][gfx])
	if near and _photo_dof.is_empty():
		cam_attr.dof_blur_far_distance = cam_dist + 2.5
		cam_attr.dof_blur_far_transition = 6.0
	var pan := hud.cam_pad_pan if not story.is_playing() else Vector2.ZERO
	if not sleeping and not story.is_playing() and not hud.is_chat_open():
		if _held(KEY_W) or _held(KEY_UP):
			pan.y -= 1
		if _held(KEY_S) or _held(KEY_DOWN):
			pan.y += 1
		if _held(KEY_A) or _held(KEY_LEFT):
			pan.x -= 1
		if _held(KEY_D) or _held(KEY_RIGHT):
			pan.x += 1
	if pan != Vector2.ZERO:
		_set_cam_lock(false)
		_pan_camera(pan.normalized() * 14.0 * delta * cam_dist / 23.0)
	if not cam_glide.is_empty():
		var k := 1.0 - exp(-2.6 * delta)
		cam_target = cam_target.lerp(cam_glide["pos"], k)
		cam_dist = lerpf(cam_dist, float(cam_glide["dist"]), k)
	elif cam_follow and mode == Mode.LIVE:
		cam_target = cam_target.lerp(player.position, 1.0 - exp(-4.0 * delta))
	cam_yaw = lerp_angle(cam_yaw, cam_yaw_goal, 1.0 - exp(-8.0 * delta))
	cam_pitch = lerpf(cam_pitch, float(cam_glide.get("pitch", CAM_PITCH)), 1.0 - exp(-2.6 * delta))
	var pitch := deg_to_rad(cam_pitch)
	var off := Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * cos(pitch) * cam_dist
	off.y = sin(pitch) * cam_dist
	cam.position = cam_target + off
	cam.look_at(cam_target + Vector3(0, 0.6, 0), Vector3.UP)
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := 0.22 * clampf(_shake_t / maxf(_shake_len, 0.01), 0.0, 1.0)
		cam.position += Vector3(randf_range(-k, k), randf_range(-k, k), randf_range(-k, k))


## Layout-proof key check: matches the key by its label or by its physical position.
func _held(k: Key) -> bool:
	return Input.is_key_pressed(k) or Input.is_physical_key_pressed(k)


func _pan_camera(v: Vector2) -> void:
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	cam_target += right * v.x - fwd * v.y
	var bounds: Rect2 = god.cam_bounds() if god.active else CAM_BOUNDS # the world editor reaches the far trees
	cam_target.x = clampf(cam_target.x, bounds.position.x, bounds.end.x)
	cam_target.z = clampf(cam_target.z, bounds.position.y, bounds.end.y)


# --- input ------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if sleeping or story.is_playing() or title_on:
		return
	if _autotest_dir != "" and e is InputEventMouse:
		return # the autotest calls _live_click and friends itself; a real mouse would only disturb it
	if god.active and god.handle_mouse(e):
		return # the world editor: clicks pick things up and paint roads instead of walking Nora
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				cam_dist = clampf(cam_dist - 1.5, 8.0, 45.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist = clampf(cam_dist + 1.5, 8.0, 45.0)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed and ghost and mb.button_index == MOUSE_BUTTON_RIGHT:
					_cancel_ghost()
				else:
					drag_pan = mb.pressed
					hud.hide_menu()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if hud.is_menu_open() and mode == Mode.LIVE:
						hud.hide_menu() # a click outside the ring just closes it
						return
					if hud.is_chat_open():
						close_chat() # clicking away ends the chat (it's saved)
						return
					hud.hide_dialogue()
					if mode == Mode.BUILD:
						_build_click(mb.position, mb.shift_pressed)
					else:
						_live_click(mb.position)
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		_last_mouse = mm.position
		if drag_pan:
			_set_cam_lock(false)
			_pan_camera(Vector2(-mm.relative.x, -mm.relative.y) * 0.03 * cam_dist / 23.0)
		if ghost:
			_update_ghost(mm.position)
		else:
			_update_hover(mm.position)
	elif e is InputEventGesture and _is_repeat_gesture(e as InputEventGesture):
		return # Godot can deliver the same trackpad gesture twice in one frame
	elif e is InputEventPanGesture:
		# two-finger swipe on a Mac trackpad
		_set_cam_lock(false)
		_pan_camera((e as InputEventPanGesture).delta * 0.6 * cam_dist / 23.0)
	elif e is InputEventMagnifyGesture:
		# pinch on a Mac trackpad
		cam_dist = clampf(cam_dist / (e as InputEventMagnifyGesture).factor, 8.0, 45.0)


var _last_gesture := ""


func _is_repeat_gesture(g: InputEventGesture) -> bool:
	var sig := "%d|%s" % [Engine.get_process_frames(), g.as_text()]
	if sig == _last_gesture:
		return true
	_last_gesture = sig
	return false


## Keys are read here, before the on-screen UI gets a chance to swallow them.
func _input(e: InputEvent) -> void:
	if sleeping or title_on or not (e is InputEventKey):
		return
	if _autotest_dir != "" and not e.has_meta("ke_test"):
		get_viewport().set_input_as_handled()
		return # the autotest presses its own keys (_key_tap); a real keyboard would only disturb it
	var k := e as InputEventKey
	if not k.pressed or k.echo:
		return
	var kc := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if story.is_playing():
		# during a scene, keys only advance it or pick a choice
		match kc:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				hud.story_click()
			KEY_1, KEY_2, KEY_3, KEY_4:
				hud.story_key_choice(kc - KEY_0)
		get_viewport().set_input_as_handled()
		return
	if hud.is_chat_open():
		# typing goes to the chat box; only Escape is ours
		if kc == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	if hud.is_menu_open() and kc >= KEY_1 and kc <= KEY_9:
		hud.pie.key(kc - KEY_0)
		get_viewport().set_input_as_handled()
		return
	if god.active and god.handle_key(kc, k):
		get_viewport().set_input_as_handled()
		return
	var handled := true
	match kc:
		KEY_Q:
			cam_yaw_goal -= PI * 0.5
		KEY_E:
			cam_yaw_goal += PI * 0.5
		KEY_R:
			_rotate_ghost()
		KEY_C:
			walls_up = not walls_up
		KEY_SPACE:
			_set_cam_lock(not cam_follow, true)
		KEY_B:
			set_mode(Mode.LIVE if mode == Mode.BUILD else Mode.BUILD)
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			_sell_ghost()
		KEY_ESCAPE:
			if ghost:
				_cancel_ghost()
			elif hud.is_menu_open():
				hud.hide_menu()
			elif hud.help_panel.visible:
				hud.help_panel.visible = false
			elif mode == Mode.BUILD:
				set_mode(Mode.LIVE)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _ray_target(mpos: Vector2) -> Variant:
	var from := cam.project_ray_origin(mpos)
	var to := from + cam.project_ray_normal(mpos) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return null
	var col: Object = res["collider"]
	if col and col.has_meta("target"):
		return col.get_meta("target")
	return null


func _ground_point(mpos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(mpos), cam.project_ray_normal(mpos))


func _update_hover(mpos: Vector2) -> void:
	var t = _ray_target(mpos)
	var clickable := false
	if t != null:
		clickable = (mode == Mode.BUILD and t is Furniture and furniture.has(t)) or (mode == Mode.LIVE and not _actions_for(t).is_empty())
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if clickable else Input.CURSOR_ARROW)


func _live_click(mpos: Vector2) -> void:
	var t = _ray_target(mpos)
	if t != null:
		var acts := _actions_for(t)
		if not acts.is_empty():
			hud.show_menu(mpos, _name_of(t), acts, func(id): _do_action(t, id))
			return
	var g = _ground_point(mpos)
	if g != null:
		player.walk(_find_path(player.position, g))
		_click_marker(g)


func _click_marker(p: Vector3) -> void:
	var m := Catalog.glow(Catalog.ring(self, 0.16, 0.22, p + Vector3(0, 0.04, 0), Color(0.6, 0.95, 0.5)), Color(0.6, 0.95, 0.5), 1.0)
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(1.8, 1, 1.8), 0.4)
	tw.parallel().tween_property(m, "transparency", 1.0, 0.4)
	tw.tween_callback(m.queue_free)


# --- actions --------------------------------------------------------------------------

func _name_of(t) -> String:
	if t == bin:
		return "Shipping Bin"
	return t.display_name()


func _act(id: String, label: String, enabled := true) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled}


func _actions_for(t) -> Array:
	if t == bin:
		var sw := Game.count("sweater")
		var crops: int = Game.count("turnip") * Game.SELL_PRICES["turnip"] + Game.count("pumpkin") * Game.SELL_PRICES["pumpkin"]
		var wool := Game.count("wool")
		return [
			_act("ship_sweater", "Ship sweaters (%d × %dc)" % [sw, Game.SELL_PRICES["sweater"]], sw > 0),
			_act("ship_crops", "Ship crops (%dc)" % crops, crops > 0),
			_act("ship_wool", "Ship raw wool (%d × %dc)" % [wool, Game.SELL_PRICES["wool"]], wool > 0),
		]
	if t is Furniture:
		match t.item_id:
			"rocking_chair", "armchair":
				return [_act("knit", "Knit Sweater…  (3 wool)", Game.has_item("wool", 3)), _act("rest", "Rest  (+energy)")]
			"sofa", "bench", "bench_short":
				return [_act("rest", "Rest  (+energy)"), _act("nap", "Take a nap  (1 hour)")]
			"bed":
				return [_act("sleep", "Sleep until morning"), _act("nap", "Take a nap  (1 hour)")]
			"kitchen":
				return [
					_act("cook_turnip", "Cook turnip stew  (1 turnip)", Game.has_item("turnip")),
					_act("cook_pumpkin", "Bake pumpkin pie  (1 pumpkin)", Game.has_item("pumpkin")),
					_act("snack", "Grab a snack  (5c)", Game.coins >= 5),
				]
			"spinning_wheel":
				return [_act("spin", "Spin wool  (just for fun)", Game.has_item("wool"))]
			"bookshelf":
				return [_act("read", "Read a knitting book")]
		return []
	if t is Plot:
		if t.crop == "":
			return [
				_act("plant_turnip", "Plant turnips  (10c · 6 hrs)", Game.coins >= 10),
				_act("plant_pumpkin", "Plant pumpkins  (30c · 14 hrs)", Game.coins >= 30),
			]
		if t.is_ready():
			return [_act("harvest", "Harvest %s" % t.display_name())]
		var acts := []
		if t.watered:
			acts.append(_act("noop", "Watered today ✓", false))
		else:
			acts.append(_act("water", "Water"))
		var g := _act("check", "Growing", true)
		g["progress"] = t.progress()
		g["hint"] = "watered today" if t.watered else "needs water today"
		acts.append(g)
		return acts
	if t is Villager:
		return _villager_actions(t)
	if t is Landmark:
		match t.kind:
			"travel_town":
				return [_act("travel", "Walk to Maplewood")]
			"travel_farm":
				return [_act("travel", "Walk home to Birchfield Farm")]
			"for_sale":
				return [] if Game.owns_cottage else [_act("info", "About this cottage")]
		return []
	if t is Sheep:
		var shear := _act("shear", "Shear  (+2 wool)", t.is_woolly())
		if not t.is_woolly():
			shear["label"] = "Shear"
			shear["hint"] = "wool regrowing"
			shear["progress"] = t.wool
		return [shear, _act("pet", "Pet")]
	return []


func _stand_point(t) -> Vector3:
	if t is Villager and t.talk_spot != null:
		return t.talk_spot
	var p: Vector3 = t.global_position
	if t is Furniture:
		var depth: float = t.size_rotated().y if t.rot % 2 == 0 else t.size_rotated().x
		return p + t.front() * (depth * 0.5 + 0.45)
	var dir := player.position - p
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	if t is Plot:
		return p + dir * 0.75
	return p + dir * 0.95


func _seat_point(f) -> Vector3:
	var y := 0.3
	var fwd := 0.05
	match f.item_id:
		"bed":
			y = 0.6 # on top of the quilt of assets/props/gran_bed.glb
		"rocking_chair":
			y = 0.32
		"bench", "bench_short":
			y = 0.25 # the boards of assets/props/bench_park.glb are 0.44 up; the seat sits forward of the back slats
			fwd = 0.12
	return f.global_position + Vector3(0, y, 0) + f.front() * fwd


func _do_action(t, id: String) -> void:
	if t is Landmark:
		match id:
			"travel":
				var dest: Vector3 = Town.TOWN_ARRIVE if t.kind == "travel_town" else Town.FARM_ARRIVE
				player.walk(_find_path(player.position, dest))
				_click_marker(dest)
			"info":
				hud.show_dialogue("Rosewood Cottage", -1, "A cozy cottage with a garden lot, just off the plaza. For sale: %dc. Mabel at the Land Office handles the sale. Furnish it and renters pay you every morning." % _cottage_price())
		return
	if t is Villager:
		t.hold(15.0)
	if id == "check":
		hud.show_toast("%s growing%s" % [t.display_name(), "" if t.watered else ". Needs water today!"], t.progress())
		return
	if t is Sheep:
		t.hold(10.0)
	player.walk(_find_path(player.position, _stand_point(t)), _perform.bind(t, id))


func _perform(t, id: String) -> void:
	player.face_point(t.global_position)
	if t is Villager:
		t.face_point(player.position, 10.0)
		player.talk(4.0)
		_villager_action(t, id)
		return
	match id:
		"knit":
			if not Game.has_item("wool", 3):
				hud.show_toast("You need 3 wool to knit a sweater. Shear a sheep!")
				return
			if Game.use_energy(10.0):
				player.start_activity("Knitting", 5.0, _finish_knit, _seat_point(t), t.rotation.y)
		"rest":
			var seat = _seat_point(t) if t is Furniture else null
			player.start_activity("Resting", 4.0, _finish_rest, seat, t.rotation.y)
		"nap":
			if t is Furniture and t.item_id == "bed":
				player.lie_in_bed(t, "Napping", 5.0, _finish_nap)
			else:
				player.start_activity("Napping", 5.0, _finish_nap, _seat_point(t), t.rotation.y)
		"sleep":
			if t is Furniture and t.item_id == "bed":
				player.lie_in_bed(t, "Zzz", 1.8, func(): pass)
			else:
				player.start_activity("Zzz", 1.8, func(): pass, _seat_point(t), t.rotation.y)
			_go_to_sleep(false)
		"cook_turnip", "cook_pumpkin", "snack":
			if id == "snack" and not Game.spend(5):
				return
			player.start_activity("Cooking", 3.0, _finish_cook.bind(id))
		"spin":
			player.start_activity("Spinning", 3.0, func():
				Game.add_need("happiness", 4.0)
				hud.show_toast("The wheel hums. Your wool is nice and even now."))
		"read":
			player.start_activity("Reading", 3.0, func():
				Game.energy = minf(100.0, Game.energy + 8.0)
				Game.add_need("happiness", 6.0)
				hud.show_toast("You learned a new cable stitch. (+8 energy)"))
		"plant_turnip", "plant_pumpkin":
			var crop := id.substr(6)
			if t.crop != "":
				return
			if Game.use_energy(2.0) and Game.spend(int(Plot.CROPS[crop]["seed"])):
				player.start_activity("Planting", 1.2, _finish_plant.bind(t, crop))
		"water":
			if Game.use_energy(2.0):
				player.start_activity("Watering", 1.0, _finish_water.bind(t))
		"harvest":
			if Game.use_energy(2.0):
				player.start_activity("Harvesting", 1.0, _finish_harvest.bind(t))
		"shear":
			if t.is_woolly() and Game.use_energy(5.0):
				player.start_activity("Shearing", 2.5, _finish_shear.bind(t))
		"pet":
			player.start_activity("Petting", 1.2, _finish_pet.bind(t))
		"ship_sweater", "ship_crops", "ship_wool":
			_ship(id)


func _finish_knit() -> void:
	if Game.take_item("wool", 3):
		Game.add_item("sweater")
		var worn0 := Game.worn_quality
		var q := Game.knit_sweater()
		Game.add_need("happiness", 14.0)
		if q > worn0:
			hud.show_toast("A %s sweater! Warmer than anything she owns. She'll wear one like it." % Game.stars(q))
		else:
			hud.show_toast("You knitted a %s sweater! Ship it for %dc." % [Game.stars(q), Game.SELL_PRICES["sweater"]])
		get_tree().create_timer(0.8).timeout.connect(func(): story.trigger("event", "knit_done"))


func _finish_rest() -> void:
	Game.energy = minf(100.0, Game.energy + 25.0)
	Game.add_need("happiness", 3.0)
	hud.show_toast("Ahh, that's better. (+25 energy)")


func _finish_nap() -> void:
	Game.energy = minf(100.0, Game.energy + 45.0)
	Game.hour += 1.0
	hud.show_toast("A cozy nap. (+45 energy)")


func _finish_cook(kind: String) -> void:
	match kind:
		"cook_turnip":
			if Game.take_item("turnip"):
				Game.fullness = minf(100.0, Game.fullness + 35.0)
				Game.energy = minf(100.0, Game.energy + 5.0)
				Game.add_need("warmth", 10.0)
				Game.add_need("happiness", 5.0)
				hud.show_toast("Warm turnip stew. Delicious!")
		"cook_pumpkin":
			if Game.take_item("pumpkin"):
				Game.fullness = minf(100.0, Game.fullness + 60.0)
				Game.energy = minf(100.0, Game.energy + 10.0)
				Game.add_need("happiness", 10.0)
				hud.show_toast("Fresh pumpkin pie. The whole house smells amazing.")
		"snack":
			Game.fullness = minf(100.0, Game.fullness + 20.0)
			hud.show_toast("A quick snack. (+20 food)")


func _finish_plant(p, crop: String) -> void:
	p.plant(crop)
	Game.add_need("fitness", 1.5)
	hud.show_toast("Planted %s. Don't forget to water them!" % Plot.CROPS[crop]["name"].to_lower())


func _finish_water(p) -> void:
	p.water()
	Game.add_need("fitness", 1.0)


func _finish_harvest(p) -> void:
	if not p.is_ready():
		return
	var crop: String = p.crop
	var n := 2 if crop == "turnip" else 1
	Game.add_item(crop, n)
	p.clear_crop()
	Game.add_need("fitness", 1.5)
	Game.add_need("happiness", 3.0)
	hud.show_toast("Harvested %d %s!" % [n, crop + ("s" if n > 1 else "")])


func _finish_shear(s) -> void:
	if not s.is_woolly():
		return
	s.shear()
	s.hold(0.0)
	Game.add_item("wool", 2)
	Game.add_need("fitness", 3.0)
	hud.show_toast("Snip snip! +2 wool.")


func _finish_pet(s) -> void:
	s.hold(0.0)
	for i in 3:
		var h := Catalog.glow(Catalog.ball(self, 0.07, s.global_position + Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2)), Color(1.0, 0.35, 0.45)), Color(1.0, 0.35, 0.45), 1.5)
		var tw := create_tween()
		tw.tween_property(h, "position:y", h.position.y + 0.9, 1.0).set_delay(i * 0.15)
		tw.parallel().tween_property(h, "transparency", 1.0, 1.0).set_delay(i * 0.15)
		tw.tween_callback(h.queue_free)
	Game.add_need("happiness", 6.0)
	Game.add_need("love", 2.0)
	hud.show_toast("Baa! Your sheep looks happy.")


func _ship(kind: String) -> void:
	var earned := 0
	var items: Array = []
	match kind:
		"ship_sweater":
			items = ["sweater"]
		"ship_crops":
			items = ["turnip", "pumpkin"]
		"ship_wool":
			items = ["wool"]
	for k in items:
		var n := Game.count(k)
		earned += n * int(Game.SELL_PRICES[k])
		Game.take_item(k, n)
	if earned > 0:
		Game.coins += earned
		hud.show_toast("Shipped! +%dc" % earned)


func _go_to_sleep(passed_out: bool) -> void:
	if sleeping:
		return
	sleeping = true
	hud.hide_menu()
	hud.fade_sleep()
	await get_tree().create_timer(0.9).timeout
	Game.sleep()
	if passed_out:
		Game.energy = 60.0
	if _autotest_dir == "":
		_save_game()
	await get_tree().create_timer(0.9).timeout
	sleeping = false
	hud.show_toast("%s, Day %d. Good morning!%s" % [Game.season_name(), Game.day_of_season(), _morning_note])


func _on_day_started(_day: int) -> void:
	_morning_note = ""
	var rent := _cottage_rent()
	if rent > 0:
		Game.coins += rent
		_morning_note = "  Rent from Rosewood Cottage: +%dc." % rent
	_update_price_board()
	for p in plots:
		p.on_new_day()
	for s in sheep_list:
		s.wool = minf(1.0, s.wool + 0.6)


# --- build mode ---------------------------------------------------------------------------

func set_mode(m: Mode) -> void:
	if ghost:
		_cancel_ghost()
	mode = m
	hud.set_build_mode(m == Mode.BUILD)
	hud.hide_menu()
	if m != Mode.LIVE:
		player.cancel_activity()
		hud.show_toast("Build mode: pick something from the catalog.")


func _setup_ghost_marker() -> void:
	_mark_ok = StandardMaterial3D.new()
	_mark_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_ok.albedo_color = Color(0.35, 0.95, 0.45, 0.45)
	_mark_bad = _mark_ok.duplicate()
	_mark_bad.albedo_color = Color(1.0, 0.3, 0.25, 0.5)
	ghost_marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 0.02, 1)
	ghost_marker.mesh = bm
	ghost_marker.visible = false
	add_child(ghost_marker)


func _begin_place(id: String) -> void:
	if mode != Mode.BUILD:
		set_mode(Mode.BUILD)
	if ghost:
		_cancel_ghost()
	if Game.coins < int(Catalog.ITEMS[id]["price"]):
		hud.show_toast("Not enough coins for that yet.")
		return
	ghost = Furniture.new()
	furniture_root.add_child(ghost)
	ghost.setup(id, ghost_rot)
	ghost.set_ghost(true)
	ghost_from = null
	ghost_marker.visible = true
	hud.set_holding(true, 0)
	_update_ghost(_last_mouse)


func _snap(v: float, size: float) -> float:
	return roundf((v - size * 0.5) / 0.5) * 0.5 + size * 0.5


func _update_ghost(mpos: Vector2) -> void:
	if not ghost:
		return
	var g = _ground_point(mpos)
	if g == null:
		return
	var s: Vector2 = ghost.size_rotated()
	ghost.position = Vector3(_snap(g.x, s.x), 0, _snap(g.z, s.y))
	ghost_valid = _placement_valid(ghost, ghost.position)
	ghost_marker.position = ghost.position + Vector3(0, 0.05, 0)
	ghost_marker.scale = Vector3(s.x, 1, s.y)
	ghost_marker.material_override = _mark_ok if ghost_valid else _mark_bad


func _placement_valid(f, pos: Vector3) -> bool:
	var r: Rect2 = f.footprint_at(pos)
	var in_cottage := Game.owns_cottage and cottage_interior().encloses(r)
	var inside := interior_rect().encloses(r) or in_cottage
	var in_yard := Game.owns_cottage and Town.COTTAGE_LOT.encloses(r) and not cottage_house_rect().grow(0.25).intersects(r)
	var outside := (LOT.encloses(r) and not house_rect().grow(0.25).intersects(r)) or in_yard
	match str(f.info()["where"]):
		"in":
			if not inside:
				return false
		"out":
			if not outside:
				return false
		_:
			if not (inside or outside):
				return false
	for b in divider_rects + place_blockers:
		if (b as Rect2).intersects(r):
			return false
	var flat: bool = f.is_flat()
	for o in furniture:
		if o == f or o.is_flat() != flat:
			continue # rugs may sit under furniture
		if o.footprint().intersects(r):
			return false
	if not flat and r.grow(0.15).has_point(Vector2(player.position.x, player.position.z)):
		return false
	return true


func _build_click(mpos: Vector2, keep_placing: bool) -> void:
	if ghost:
		_update_ghost(mpos)
		if not ghost_valid:
			hud.show_toast("Can't place that there.")
			return
		var id: String = ghost.item_id
		var bought := ghost_from == null
		if bought and not Game.spend(int(Catalog.ITEMS[id]["price"])):
			return
		ghost.set_ghost(false)
		furniture.append(ghost)
		ghost = null
		ghost_from = null
		ghost_marker.visible = false
		hud.set_holding(false)
		_rebuild_grid()
		if bought and keep_placing:
			_begin_place(id)
		return
	var t = _ray_target(mpos)
	if t != null and t is Furniture and furniture.has(t):
		furniture.erase(t)
		ghost = t
		ghost_from = {"pos": t.position, "rot": t.rot}
		ghost_rot = t.rot
		ghost.set_ghost(true)
		ghost_marker.visible = true
		hud.set_holding(true, int(Catalog.ITEMS[t.item_id]["price"]) / 2)
		_update_ghost(mpos)


func _rotate_ghost() -> void:
	if not ghost:
		return
	ghost_rot = (ghost.rot + 1) % 4
	ghost.set_rot(ghost_rot)
	_update_ghost(_last_mouse)


func _cancel_ghost() -> void:
	if not ghost:
		return
	if ghost_from != null:
		ghost.position = ghost_from["pos"]
		ghost.set_rot(ghost_from["rot"])
		ghost.set_ghost(false)
		furniture.append(ghost)
	else:
		ghost.queue_free()
	ghost = null
	ghost_from = null
	ghost_marker.visible = false
	hud.set_holding(false)
	_rebuild_grid()


func _sell_ghost() -> void:
	if not ghost or ghost_from == null:
		return
	var value := int(Catalog.ITEMS[ghost.item_id]["price"]) / 2
	Game.coins += value
	hud.show_toast("Sold the %s for %dc." % [ghost.display_name(), value])
	ghost.queue_free()
	ghost = null
	ghost_from = null
	ghost_marker.visible = false
	hud.set_holding(false)
	_rebuild_grid()


func _spawn_furniture(id: String, pos: Vector3, r: int) -> Furniture:
	var f: Furniture = Furniture.new()
	furniture_root.add_child(f)
	f.setup(id, r)
	f.position = pos
	furniture.append(f)
	return f


# --- new game / save / load ---------------------------------------------------------------

func _new_world() -> void:
	_spawn_furniture("fireplace", Vector3(0.6, 0, 2.5), 1)
	_spawn_furniture("rug_red", Vector3(3.5, 0, 3.0), 0)
	_spawn_furniture("rocking_chair", Vector3(2.4, 0, 3.6), 3)
	_spawn_furniture("coffee_table", Vector3(3.6, 0, 3.0), 0)
	_spawn_furniture("yarn_basket", Vector3(2.25, 0, 2.25), 0)
	_spawn_furniture("yarn_balls", Vector3(2.0, 0, 4.4), 0)
	_spawn_furniture("knitting_needles", Vector3(2.85, 0, 1.55), 0)
	_spawn_furniture("lamp", Vector3(1.45, 0, 4.55), 0)
	_spawn_furniture("bed", Vector3(6.85, 0, 1.1), 0)
	_spawn_furniture("kitchen", Vector3(1.2, 0, 0.6), 0)
	_spawn_furniture("bookshelf", Vector3(3.75, 0, 0.35), 0)
	_spawn_furniture("plant", Vector3(5.05, 0, 0.4), 0)
	_spawn_furniture("plant", Vector3(7.6, 0, 5.6), 0)
	_spawn_furniture("sunflowers", Vector3(9.0, 0, 0.5), 0)
	_spawn_furniture("scarecrow", Vector3(13.0, 0, -2.6), 0)
	_spawn_furniture("flower_pot", Vector3(9.0, 0, 5.0), 0)
	_spawn_furniture("hay_bale", Vector3(15.5, 0, -3.0), 0)
	_spawn_furniture("lantern", Vector3(9.4, 0, 1.6), 0)
	plots[0].plant("turnip")
	plots[0].growth = 5.0
	plots[0].water()
	plots[1].plant("pumpkin")
	plots[1].growth = 4.0


func _save_game() -> void:
	var d := Game.to_dict()
	var fl := []
	for f in furniture:
		fl.append({"id": f.item_id, "x": f.position.x, "z": f.position.z, "rot": f.rot})
	d["furniture"] = fl
	d["plots"] = plots.map(func(p): return p.to_dict())
	d["sheep"] = sheep_list.map(func(s): return s.wool)
	d["player"] = [player.position.x, player.position.z]
	var fa := FileAccess.open(Game.save_path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(d))


func _load_game() -> bool:
	if not FileAccess.file_exists(Game.save_path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	Game.from_dict(d)
	while sheep_list.size() < Game.sheep_count:
		_add_sheep()
	for e in d.get("furniture", []):
		if Catalog.ITEMS.has(str(e["id"])):
			_spawn_furniture(str(e["id"]), Vector3(float(e["x"]), 0, float(e["z"])), int(e["rot"]))
	var pl: Array = d.get("plots", [])
	for i in mini(pl.size(), plots.size()):
		plots[i].from_dict(pl[i])
	var sh: Array = d.get("sheep", [])
	for i in mini(sh.size(), sheep_list.size()):
		sheep_list[i].wool = float(sh[i])
	var pp: Array = d.get("player", [4.6, 4.9])
	player.position = Vector3(float(pp[0]), 0, float(pp[1]))
	return true


# --- tips ------------------------------------------------------------------------------------------

## One-time tips, the first time each becomes useful: [id, when, text]. Each shows once per save
## (flag tip_<id>), only in open play (no scene, title or sleep), and at most one every 20 seconds.
## Act 1 teaches the basics itself, so most wait until it's over.
var tips_enabled := true
var _tip_t := 3.0


func _tips() -> Array:
	var after_act1: bool = Game.flag("act1_done") == true
	return [
		["click", after_act1, "Click anything (sheep, the rocking chair, soil, people) to see what you can do with it."],
		["shear", after_act1 and Game.count("wool") < 3, "Sheep grow wool every day. Click a woolly one to shear it: three wool knit one sweater."],
		["knit", after_act1 and Game.has_item("wool", 3), "Enough wool for a sweater. Click the rocking chair and choose Knit Sweater."],
		["sell", after_act1 and Game.count("sweater") > 0, "Sell sweaters to Rosa at the Maplewood market (her price changes daily), ship them in the bin, or give one as a gift."],
		["night", after_act1 and Game.hour >= 21.0, "It's getting late. Click the bed to sleep: crops grow, prices change, and the game saves."],
		["rowan", after_act1 and Game.hearts("rowan") >= 1, "Rowan has more to say than he lets on. Talk to him once a day and a little more comes out."],
		["build", mode == Mode.BUILD, "Pick a piece from the catalog and click to place it. R rotates, right-click cancels. Click a placed piece to move or sell it."],
	]


func _update_tips(delta: float) -> void:
	_tip_t -= delta
	if _tip_t > 0.0 or not tips_enabled or title_on or story.is_playing() or sleeping:
		return
	_tip_t = 1.0
	for t in _tips():
		if t[1] and not Game.flag("tip_" + str(t[0])):
			Game.set_flag("tip_" + str(t[0]))
			hud.show_tip(str(t[2]))
			_tip_t = 20.0
			return


# --- title screen and display ----------------------------------------------------------------------

var title_on := false
var _title_clock := true


func show_title(has_save: bool) -> void:
	title_on = true
	_title_clock = Game.time_running
	Game.time_running = false
	cam_follow = false
	cam_glide = {"pos": Vector3(9.0, 0.0, -2.0), "dist": 24.0}
	hud.show_title(has_save)


func _leave_title() -> void:
	title_on = false
	cam_glide = {}
	cam_follow = true
	Game.time_running = _title_clock
	hud.hide_title()


func _title_continue() -> void:
	_leave_title()


func _title_new_game() -> void:
	if FileAccess.file_exists(Game.save_path) and _autotest_dir == "":
		Engine.set_meta("ke_skip_title", true)
		_new_game()
		return
	_leave_title()
	_begin_new_story()


func _load_display() -> void:
	if _autotest_dir != "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("display", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if _autotest_dir == "":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("display", "fullscreen", on)
		cfg.save(SETTINGS_PATH)


func _new_game() -> void:
	if FileAccess.file_exists(Game.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.reset()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _autotest_dir == "":
		_save_game()


# --- automated smoke test (run with: -- --autotest=/abs/dir) -------------------------------

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The graphics setting turns the expensive effects off and back on, and the autotest never
## writes the player's settings file.
func _graphics_checks() -> void:
	var blades_hi: int = grass.drawn_blades()
	var scale_hi := get_viewport().scaling_3d_scale
	var had_cfg := FileAccess.file_exists(SETTINGS_PATH)
	_cycle_graphics() # Medium
	_cycle_graphics() # Low
	await _wait(0.3)
	var lamps: Array = find_children("*", "OmniLight3D", true, false)
	_check("Low graphics: no light bounce, reflections, haze or lamp shadows; %d of %d grass blades; 3D at %d%% (High %d%%)" % [grass.drawn_blades(), blades_hi, roundi(get_viewport().scaling_3d_scale * 100), roundi(scale_hi * 100)],
		gfx == 0 and not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled
		and lamps.all(func(l): return not is_instance_valid(l) or not l.shadow_enabled) and grass.drawn_blades() < blades_hi * 0.5
		and get_viewport().scaling_3d_scale <= scale_hi and hud.graphics_btn.text == "Graphics: Low")
	_cycle_graphics() # High
	await _wait(0.3)
	var flush := coplanar_faces()
	for f in flush:
		print("      flush: ", f)
	_check("no two surfaces sit flush in the same plane (they'd flicker in stripes): %d" % flush.size(), flush.is_empty())
	_check("back on High: every effect and all the grass return; settings file untouched",
		gfx == 2 and env.ssao_enabled and env.ssil_enabled and env.ssr_enabled and lamps.all(func(l): return not is_instance_valid(l) or l.shadow_enabled)
		and grass.drawn_blades() == blades_hi and FileAccess.file_exists(SETTINGS_PATH) == had_cfg)


func _shot(fname: String) -> void:
	# macOS doesn't draw a window that is completely covered, and the frame never comes: after a
	# few seconds go on without the picture rather than wait forever
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func(): drawn[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not drawn[0] and waited < 6.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	if not drawn[0]:
		print("SHOT skipped (the window is covered, so nothing was drawn): ", fname)
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_autotest_dir.path_join(fname))
	print("SHOT ", fname)


## Content files and save format: everything the game reads from data/ is consistent,
## story flags survive a save, and an old (v1) save still loads.
func _data_checks() -> void:
	var errs := Data.validate(Callable(Catalog, "has_builder"))
	for e in errs:
		print("      data: ", e)
	_check("data files are consistent (%d furniture, %d crops, %d villagers)" % [Data.furniture().size(), Data.crops().size(), Data.villagers().size()], errs.is_empty())
	_check("prices come from economy.json (sweater sells for %d)" % Game.SELL_PRICES.get("sweater", 0), Game.SELL_PRICES.get("sweater", 0) == int(Data.economy()["sell_prices"]["sweater"]))
	Game.set_flag("met_rowan")
	Game.set_flag("chapter", 2)
	var d := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	Game.flags = {}
	Game.from_dict(d)
	_check("story flags survive a save (version %d, met_rowan=%s, chapter=%s)" % [int(d.get("version", 0)), Game.flag("met_rowan"), Game.flag("chapter")], int(d.get("version", 0)) == Game.SAVE_VERSION and Game.flag("met_rowan") == true and int(Game.flag("chapter")) == 2 and Game.flag("unset_flag") == false)
	var old_save := d.duplicate(true)
	old_save.erase("version")
	old_save.erase("flags")
	var coins := Game.coins
	Game.from_dict(old_save)
	_check("a v1 save without flags still loads (coins %d, flags %d)" % [Game.coins, Game.flags.size()], Game.coins == coins and Game.flags.is_empty())


## Story engine: scene files parse, a real scene plays through clicks and keys, and a scene
## written as plain text right here plays with fades, a title card, jumps and stats.
func _story_checks() -> void:
	var errs := Story.validate()
	for e in errs:
		print("      story: ", e)
	_check("story scenes parse (%d scenes, %d problems)" % [Story.scenes().size(), errs.size()], errs.is_empty() and Story.has_scene("rowan_town_chat"))
	Game.set_flag("met_rowan") # his town chat comes after Act 1
	var rowan := _villager("rowan")
	var fam0 := Game.stat("rowan", "familiarity")
	_villager_action(rowan, "talk")
	await _wait(1.4)
	_check("talking to Rowan starts his scene (%s, name box '%s', portrait %s)" % [story.playing, hud.story_name.text, hud.story_portrait.texture != null],
		story.playing == "rowan_town_chat" and hud.story_name.text == "Rowan" and hud.story_portrait_frame.visible and hud.story_portrait.texture != null)
	await _shot("12_story_line.png")
	var saw_choice := false
	var t := 0.0
	while story.is_playing() and t < 40.0:
		if hud.story_has_choices():
			if not saw_choice:
				saw_choice = true
				await _shot("13_story_choice.png")
			hud.story_key_choice(1)
		else:
			hud.story_click()
		await _wait(0.12)
		t += 0.12
	_check("played through with clicks and the 1 key (choice shown=%s, %d lines)" % [saw_choice, story.shown.size()], saw_choice and not story.is_playing() and story.shown.size() >= 6)
	_check("the choice changed trust and familiarity (trust %d, familiarity %d→%d)" % [Game.stat("rowan", "trust"), fam0, Game.stat("rowan", "familiarity")],
		Game.stat("rowan", "trust") == 2 and Game.stat("rowan", "familiarity") >= fam0 + 4 and Game.flag("met_rowan") == true)
	_check("a once-only scene doesn't repeat", Story.find_trigger("talk", "rowan") == "")
	# a scene written as plain text, parsed and played on the spot
	Story.parse_into("""
== autotest_scene
@fade out 0.2
@title Testing, testing
@fade in 0.2
@camera rowan 5
@if trust rowan >= 2 -> trusted
Rowan (sad): You shouldn't see this line.
@goto finish
@label trusted
Rowan (happy): You're alright, {player}.
@romance rowan +1
@label finish
@set autotest_scene_done 3
""", "autotest")
	story.shown.clear()
	story.auto = true
	story.play("autotest_scene")
	t = 0.0
	while story.is_playing() and t < 20.0:
		await _wait(0.1)
		t += 0.1
	story.auto = false
	var last := str(story.shown[-1]) if not story.shown.is_empty() else ""
	_check("a plain-text scene plays: jumps on trust, fills {player} (%s)" % last, last == "Rowan: You're alright, Nora." and story.shown.size() == 1)
	_check("scene commands ran (romance %d, flag %s, screen faded back in)" % [Game.stat("rowan", "romance"), Game.flag("autotest_scene_done")],
		Game.stat("rowan", "romance") == 1 and int(Game.flag("autotest_scene_done")) == 3 and hud.story_fade_rect.color.a < 0.05)
	# a v2 save (friendship points) upgrades to v3 (familiarity, trust, romance)
	var v2 := Game.to_dict()
	v2["version"] = 2
	v2["friends"] = {"rosa": {"pts": 37, "talk": 1, "gift": 0, "n": 2}}
	Game.from_dict(JSON.parse_string(JSON.stringify(v2)))
	_check("a v2 save upgrades: points become familiarity (rosa %d, trust %d)" % [Game.stat("rosa", "familiarity"), Game.stat("rosa", "trust")],
		Game.stat("rosa", "familiarity") == 37 and Game.stat("rosa", "trust") == 0 and Game.hearts("rosa") == 1)


## Act 1 from a fresh story: the rain bus, Mabel at the gate, Gran's basket, knitting and the
## first memory thread, Rowan at the broken fence, market day in Maplewood, and the porch at
## night. The heroine walks between the triggers for real.
func _act1_checks() -> void:
	Game.flags = {}
	Game.hour = 9.0
	Game.energy = 100.0
	for vid in ["rowan", "mabel"]:
		set_home(vid)
	mode = Mode.LIVE
	story.shown.clear()
	story.auto = true
	story.auto_line = 0.3
	story.auto_choices = [0, 0, 0, 1, 0, 1, 0]
	var wool0 := Game.count("wool")
	var trust0 := Game.stat("rowan", "trust")
	var journal0: int = Game.journal().size()
	var day0 := Game.day
	var walk_secs := 0.0
	_check("a new game opens on Act 1 (%s)" % Story.find_trigger("start"), Story.find_trigger("start") == "act1_arrival")
	var hour0 := Game.hour
	var hour_end := [-1.0] # read the moment the scene ends, before the clock starts again
	story.scene_finished.connect(func(_id): hour_end[0] = Game.hour, CONNECT_ONE_SHOT)
	story.trigger("start")
	await _act1_shot("Last stop", "20_act1_rain_bus.png")
	await _act1_shot("Daniel.", "21_act1_phone.png")
	await _act1_until_done(40.0)
	_check("the clock stands still during a scene (%.2f → %.2f)" % [hour0, hour_end[0]], absf(hour_end[0] - hour0) < 0.001 and Game.time_running)
	_check("the arrival ends at the bus stop in the rain with a goal (%s, '%s', rain %.1f)" % [str(Game.flag("act1_arrived")), hud.goal_label.text, rain],
		Game.flag("act1_arrived") == true and player.position.distance_to(Vector3(40.2, 0, 3.4)) < 0.5 and hud.goal_panel.visible and goal_marker.visible and rain > 0.5 and str(Game.flag("weather")) == "rain")
	await _wait(0.8)
	await _shot("22_act1_goal.png")
	var t0 := Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(25.2, 0, 3.0)))
	var t := 0.0
	while story.playing != "act1_cottage" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("walking to the farm gate starts Mabel's scene (%s after %.1fs)" % [story.playing, t], story.playing == "act1_cottage")
	await _act1_shot("Here. Keys.", "23_act1_mabel_keys.png")
	await _act1_until_done(40.0)
	_check("Mabel handed over the keys (goal '%s')" % hud.goal_label.text, Game.flag("act1_keys") == true and hud.goal_label.text.begins_with("Go inside"))
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(5.6, 0, 3.0)))
	t = 0.0
	while story.playing != "act1_basket" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("stepping inside starts Gran's basket scene (%s)" % story.playing, story.playing == "act1_basket")
	await _act1_shot("For when you come home", "24_act1_letter.png")
	await _act1_until_done(40.0)
	_check("read Gran's letter and got her yarn (wool %d→%d)" % [wool0, Game.count("wool")],
		Game.flag("read_gran_letter") == true and Game.count("wool") == wool0 + 3 and Game.flag("act1_basket") == true)
	var mabel := _villager("mabel")
	_check("Mabel went back to the Land Office (%.1f away)" % mabel.position.distance_to(Vector3(64.2, 0, -7.2)), mabel.position.distance_to(Vector3(64.2, 0, -7.2)) < 1.5)
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	t0 = Time.get_ticks_msec()
	_do_action(chair, "knit")
	t = 0.0
	while story.playing != "act1_fence" and t < 30.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("finishing a knit starts the fence scene (%s)" % story.playing, story.playing == "act1_fence")
	await _act1_shot("Babe.", "27_act1_memory.png")
	_check("the first knit opens memory thread #1 in the faded memory look", hud.memory_on())
	await _act1_shot("pay rent", "")
	_check("the memory ends before the sheep (look off: %s) and is in her journal (%s)" % [str(not hud.memory_on()), str(Game.journal().map(func(e): return e["title"]))],
		not hud.memory_on() and Game.journal().size() == journal0 + 1 and Game.journal()[-1]["kind"] == "memory")
	var loose := 0
	for i in 3:
		if not pen_rect.has_point(Vector2(sheep_list[i].position.x, sheep_list[i].position.z)):
			loose += 1
	_check("three sheep are out of the pen (%d)" % loose, loose == 3)
	await _act1_shot("You alright?", "25_act1_rowan_fence.png")
	await _act1_shot("fell over once", "26_act1_after.png")
	await _act1_until_done(60.0)
	var in_pen := 0
	for s in sheep_list:
		if pen_rect.has_point(Vector2(s.position.x, s.position.z)):
			in_pen += 1
	var rowan := _villager("rowan")
	_check("the fence: met Rowan, opened up (trust %d→%d), sheep home (%d/%d), Rowan back in town, sky clear, off to market ('%s')" % [trust0, Game.stat("rowan", "trust"), in_pen, sheep_list.size(), hud.goal_label.text],
		Game.flag("act1_fence_done") == true and Game.flag("met_rowan") == true and Game.flag("nora_opened") == true and Game.stat("rowan", "trust") == trust0 + 3
		and in_pen == sheep_list.size() and rowan.position.distance_to(Vector3(44.2, 0, 2.4)) < 1.0 and str(Game.flag("weather")) == "clear"
		and hud.goal_panel.visible and hud.goal_label.text.contains("market") and not Game.flag("act1_done"))
	# market day: walk into Maplewood to Rosa's stall
	var coins0 := Game.coins
	var sweaters0 := Game.count("sweater")
	var wool1 := Game.count("wool")
	var theo0 := Game.stat("theo", "trust")
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(48.5, 0, -5.6)))
	t = 0.0
	while story.playing != "act1_market" and t < 45.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("walking to Rosa's stall starts market day (%s after %.1fs)" % [story.playing, t], story.playing == "act1_market")
	await _act1_shot("Hold ON", "28_act1_market_rosa.png")
	await _act1_shot("two heads", "29_act1_market_theo.png")
	await _act1_until_done(60.0)
	_check("Rosa bought the sweater (coins %d→%d, sweaters %d→%d), Theo's wool on credit (wool %d→%d, trust %d→%d), home by dusk ('%s')" % [coins0, Game.coins, sweaters0, Game.count("sweater"), wool1, Game.count("wool"), theo0, Game.stat("theo", "trust"), hud.goal_label.text],
		Game.coins == coins0 + 60 and Game.count("sweater") == sweaters0 - 1 and Game.count("wool") == wool1 + 5 and Game.flag("theo_credit") == true
		and Game.stat("theo", "trust") == theo0 + 2 and Game.flag("act1_market") == true and hud.goal_label.text.begins_with("Head home") and Game.hour > 18.0)
	# the porch at night
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(9.8, 0, 3.0)))
	t = 0.0
	while story.playing != "act1_porch" and t < 50.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("walking home to the porch starts the night scene (%s after %.1fs)" % [story.playing, t], story.playing == "act1_porch")
	await _act1_shot("Hi Nora, it's Claire", "30_act1_voicemail.png")
	_check("it's night on the porch and the lawyer's voicemail is on her phone (%.1fh, '%s')" % [Game.hour, hud.phone_label.text],
		Game.hour > 21.0 and hud.phone_panel.visible and hud.phone_label.text.begins_with("Voicemail"))
	await _act1_shot("You okay?", "31_act1_porch_rowan.png")
	await _act1_shot("Morning.", "32_act1_morning.png")
	await _act1_until_done(60.0)
	_check("Act 1 done: she opened up on the porch (trust %d→%d, romance %d), three journal entries, the next morning (day %d→%d, %.1fh), no goal" % [trust0, Game.stat("rowan", "trust"), Game.stat("rowan", "romance"), day0, Game.day, Game.hour],
		Game.flag("act1_done") == true and Game.flag("nora_opened_porch") == true and Game.stat("rowan", "trust") == trust0 + 6
		and Game.stat("rowan", "romance") >= 1 and Game.journal().size() == journal0 + 3 and Game.day == day0 + 1 and absf(Game.hour - 7.5) < 0.3
		and not hud.goal_panel.visible)
	hud.open_journal()
	await _wait(0.4)
	await _shot("33_act1_journal.png")
	_check("the journal lists all three, newest first (%d rows)" % hud.journal_list.get_child_count(), hud.journal_panel.visible and hud.journal_list.get_child_count() == journal0 + 3)
	hud.journal_panel.visible = false
	# how long it takes a person: reading time for every line shown, choices, walks and the knit
	var read := 0.0
	var choices := 0
	for l in story.shown:
		var line := str(l)
		if line.begins_with("> "):
			choices += 1
		read += 0.7 + line.length() / 17.0
	var titles := 3 * 2.6
	var total := read + choices * 3.0 + walk_secs + titles
	_check("Act 1 plays in about 10 minutes (%d lines, %d choices: %.0fs reading + %.0fs walking/knitting = %.1f min)" % [story.shown.size(), choices, read + choices * 3.0 + titles, walk_secs, total / 60.0],
		total > 480.0 and total < 840.0)
	var d := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	Game.flags = {}
	Game.from_dict(d)
	_check("Act 1 progress survives a save (journal %d)" % Game.journal().size(),
		Game.flag("act1_done") == true and Game.flag("seen_act1_porch") == true and Game.journal().size() == journal0 + 3)
	story.auto = false
	story.auto_line = 0.08


## Romance v1 with Rowan, after Act 1: one talk topic a day as he warms up (with memory thread #2),
## gift reactions, the first-sweater scene, the invitation and the sunset date in the back field,
## and what he tells her after. Stats are nudged directly so it doesn't take a week of play.
func _romance_checks() -> void:
	var rowan := _villager("rowan")
	story.auto = true
	story.auto_line = 0.25
	story.auto_choices = [] # first option every time
	var f := Game.friend("rowan")
	player.walk([])
	player.position = rowan.position + Vector3(1.3, 0, 0.6) # beside him, as she would be to talk
	player.face_point(rowan.position)
	var talk := func() -> String:
		_villager_action(rowan, "talk")
		var id := story.playing
		await _act1_until_done(40.0)
		return id
	f["familiarity"] = 20
	f["trust"] = 6
	f["romance"] = 1
	var first: String = await talk.call()
	var second: String = await talk.call()
	_check("talking to Rowan after Act 1: his town chat, then the first topic (%s, %s), then no more topics today ('%s')" % [first, second, Story.find_trigger("talk", "rowan")],
		first == "rowan_town_chat" and second == "rowan_topic_flock" and Story.find_trigger("talk", "rowan") == "" and Game.flag("rowan_sheep_named") == true)
	Game.day += 1
	var j0: int = Game.journal().size()
	_villager_action(rowan, "talk")
	var gran := story.playing
	await _act1_shot("on flavour", "34_rowan_gran_memory.png")
	var mem := hud.memory_on()
	await _act1_until_done(40.0)
	_check("next day he talks about Gran, with memory thread #2 (%s, sepia %s, journal '%s')" % [gran, mem, Game.journal()[-1]["title"] if Game.journal().size() > j0 else ""],
		gran == "rowan_topic_ellie" and mem and not hud.memory_on() and Game.journal().size() == j0 + 1 and Game.journal()[-1]["kind"] == "memory")
	# gifts: a pumpkin he likes, then the first sweater, which has its own scene
	f["familiarity"] = 40
	var fam0 := Game.stat("rowan", "familiarity")
	var tr0 := Game.stat("rowan", "trust")
	var ro0 := Game.stat("rowan", "romance")
	Game.add_item("pumpkin", 1)
	_villager_action(rowan, "gift_pumpkin")
	_check("a pumpkin is a gift he likes (familiarity +%d, trust +%d, romance +%d): '%s'" % [Game.stat("rowan", "familiarity") - fam0, Game.stat("rowan", "trust") - tr0, Game.stat("rowan", "romance") - ro0, hud.dlg_text.text],
		Game.stat("rowan", "familiarity") == fam0 + 16 and Game.stat("rowan", "trust") == tr0 + 1 and Game.stat("rowan", "romance") == ro0 + 1 and hud.dlg_text.text.begins_with("Soup"))
	hud.hide_dialogue()
	Game.day += 1
	ro0 = Game.stat("rowan", "romance")
	Game.add_item("sweater", 1)
	_villager_action(rowan, "gift_sweater")
	var gift_scene := story.playing
	await _act1_until_done(40.0)
	_check("his first sweater plays its own scene (%s, romance +%d)" % [gift_scene, Game.stat("rowan", "romance") - ro0],
		gift_scene == "rowan_first_sweater" and Game.stat("rowan", "romance") == ro0 + 3 and Game.flag("rowan_has_sweater") == true)
	f["trust"] = maxi(int(f["trust"]), 9)
	var evenings: String = await talk.call()
	_check("one topic a day: the gift day still has room for one (%s)" % evenings, evenings == "rowan_topic_evenings" and Game.flag("rowan_tea_offer") == true)
	# three hearts and some romance: he asks her up to the back field
	Game.day += 1
	f["familiarity"] = 60
	var invite: String = await talk.call()
	await _wait(0.5)
	var home: Array = Game.flag("home_rowan", [])
	_check("at three hearts he asks her to watch the sunset (%s): goal '%s', Rowan waits at the rock %s" % [invite, hud.goal_label.text, home],
		invite == "rowan_date_invite" and Game.flag("date1_invited") == true and hud.goal_panel.visible and hud.goal_label.text.contains("back field")
		and home.size() == 2 and Vector2(float(home[0]), float(home[1])).distance_to(Vector2(24.4, -16.0)) < 0.1)
	Game.hour = 15.0
	j0 = Game.journal().size()
	ro0 = Game.stat("rowan", "romance")
	player.walk(_find_path(player.position, Vector3(23.4, 0, -16.4)))
	var t := 0.0
	while story.playing != "rowan_date1" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	_check("walking into the back field starts the date (%s after %.1fs)" % [story.playing, t], story.playing == "rowan_date1")
	await _act1_shot("Best rock", "35_rowan_date_rock.png")
	var rowan_v = _villager("rowan")
	var seat_r: float = rowan_v.position.y if rowan_v else 0.0
	var pose_r: String = rowan_v.body.current() if rowan_v and rowan_v.body else ""
	var pose_n: String = player.body.current() if player.body else ""
	_check("on the rock they sit up on it, not sunk into it (%s %.2f m up, Rowan %s %.2f m up)" % [pose_n, player.position.y, pose_r, seat_r],
		player.position.y > 0.35 and seat_r > 0.35 and pose_n == "SitIdle" and pose_r == "SitIdle")
	var sunset := Game.hour
	await _act1_shot("four minutes", "36_rowan_date_darning.png")
	var knit := player.body.current() if player.body else ""
	await _act1_until_done(60.0)
	await _wait(0.5)
	_check("the date: sunset (%.1fh), she darns his hat (%s), leans on his shoulder (romance +%d), journal '%s', rock gone, he heads home" % [sunset, knit, Game.stat("rowan", "romance") - ro0, Game.journal()[-1]["title"] if Game.journal().size() > j0 else ""],
		sunset >= 17.5 and sunset < 19.0 and knit == "SitKnit" and Game.flag("date1_done") == true and Game.flag("rowan_close") == true
		and Game.stat("rowan", "romance") >= ro0 + 4 and Game.journal().size() == j0 + 1 and not props.has("date_rock")
		and not Game.flag("home_rowan", false) and not hud.goal_panel.visible and player.anim_override == ""
		and is_zero_approx(player.position.y))
	Game.day += 1
	f["trust"] = maxi(int(f["trust"]), 14)
	var anna: String = await talk.call()
	_check("after the date, with enough trust, he tells her about Anna (%s)" % anna, anna == "rowan_topic_anna" and Game.journal()[-1]["title"] == "Anna")
	var d := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	Game.flags = {}
	Game.from_dict(d)
	_check("the romance survives a save (date %s, romance %d)" % [Game.flag("date1_done"), Game.stat("rowan", "romance")], Game.flag("date1_done") == true and Game.stat("rowan", "romance") >= 9)
	story.auto = false
	story.auto_line = 0.08


## Plays Act 1 from a new game at reading pace, walking between scenes, then quits. Record it:
##   Godot --path . --resolution 1280x800 --write-movie opening.avi --fixed-fps 30 -- --capture
func _capture_opening() -> void:
	story.auto = true
	story.cinematic = true
	story.auto_line = 0.6
	story.auto_choices = [0, 0, 0, 1, 0, 1, 0]
	await _wait(0.5)
	_begin_new_story()
	await _act1_until_done(300.0)
	await _wait(1.5)
	for step in [[Vector3(25.2, 0, 3.0), "act1_cottage"], [Vector3(5.6, 0, 3.0), "act1_basket"]]:
		player.walk(_find_path(player.position, step[0]))
		var t := 0.0
		while story.playing != step[1] and t < 40.0:
			await _wait(0.1)
			t += 0.1
		await _act1_until_done(300.0)
		await _wait(1.2)
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	_do_action(chair, "knit")
	var t2 := 0.0
	while story.playing != "act1_fence" and t2 < 30.0:
		await _wait(0.1)
		t2 += 0.1
	await _act1_until_done(400.0)
	await _wait(1.5)
	for step in [[Vector3(48.5, 0, -5.6), "act1_market"], [Vector3(9.8, 0, 3.0), "act1_porch"]]:
		player.walk(_find_path(player.position, step[0]))
		var t3 := 0.0
		while story.playing != step[1] and t3 < 60.0:
			await _wait(0.1)
			t3 += 0.1
		await _act1_until_done(400.0)
		await _wait(1.5)
	await _wait(1.5)
	print("CAPTURE DONE")
	get_tree().quit()


## Frame-cost probe (run with --disable-vsync -- --fpsprobe): the town at midday and the farm at night, vsync
## off, timing each graphics effect by switching it off on its own. Prints milliseconds per frame.
## Pairs of surfaces in different colours that face the same way in the same plane and overlap
## by more than `min_area` m²: the GPU can't tell which is in front, so they flicker in stripes
## as the camera moves (z-fighting). Checks the axis-aligned faces of every unrotated or
## quarter-turned mesh in the world, except undersides (they rest on something) and spheres.
func coplanar_faces(min_area := 0.02) -> Array:
	var buckets := {}
	var out := []
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.mesh is SphereMesh or not m.is_visible_in_tree() or m.skin != null or hud.is_ancestor_of(m):
			continue
		var b := m.global_transform.basis
		var aligned := true
		for c in 3:
			var v := b[c].normalized().abs()
			if maxf(v.x, maxf(v.y, v.z)) < 0.999:
				aligned = false
		if not aligned:
			continue
		var box := m.global_transform * m.get_aabb()
		var col := _mesh_colour(m)
		for ax in 3:
			for side in 2:
				if ax == 1 and side == 0:
					continue
				var coord := box.end[ax] if side == 1 else box.position[ax]
				var key := "%d_%d_%d" % [ax, side, roundi(coord / 0.003)]
				if not buckets.has(key):
					buckets[key] = []
				for other in buckets[key]:
					var ob: AABB = other[1]
					if other[2] == col or absf((ob.end[ax] if side == 1 else ob.position[ax]) - coord) > 0.0003:
						continue
					var area := 1.0
					for k in 3:
						if k != ax:
							area *= maxf(0.0, minf(box.end[k], ob.end[k]) - maxf(box.position[k], ob.position[k]))
					if area > min_area:
						out.append("%s%s at %.3f, %.2f m²: %s %s / %s %s" % ["xyz"[ax], "+" if side == 1 else "-", coord, area, col, box.get_center().snappedf(0.01), other[2], ob.get_center().snappedf(0.01)])
				buckets[key].append([m, box, col])
	return out


func _mesh_colour(m: MeshInstance3D) -> String:
	var mat = m.material_override if m.material_override else m.mesh.surface_get_material(0)
	if mat is ShaderMaterial and mat.get_shader_parameter("albedo") != null:
		return (mat.get_shader_parameter("albedo") as Color).to_html(false)
	if mat is StandardMaterial3D:
		return mat.albedo_color.to_html(false)
	return str(mat)


func _run_fps_probe() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Game.time_running = false
	_set_cam_lock(false)
	var lamps: Array = []
	for n in find_children("*", "OmniLight3D", true, false):
		lamps.append(n)
	var toggles := {
		"ssr": func(on): env.ssr_enabled = on,
		"ssao": func(on): env.ssao_enabled = on,
		"ssil": func(on): env.ssil_enabled = on,
		"vol_fog": func(on): env.volumetric_fog_enabled = on,
		"glow": func(on): env.glow_enabled = on,
		"sun_shadow": func(on): sun.shadow_enabled = on,
		"sun_soft": func(on): RenderingServer.directional_soft_shadow_filter_set_quality(4 if on else 2),
		"lamp_shadows": func(on):
			for l in lamps:
				l.shadow_enabled = on,
		"grass": func(on): grass.visible = on,
		"hud": func(on): hud.visible = on,
	}
	var vp := get_viewport()
	var before_today := func(on):
		# on = today's settings; off = what the game shipped with before the shadow pass
		env.ssr_enabled = on
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if on else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		RenderingServer.directional_soft_shadow_filter_set_quality(3 if on else 2)
		for l in lamps:
			l.shadow_enabled = on
	toggles["shadow-pass changes"] = before_today
	toggles["upscaling (vs full res)"] = func(on):
		if on:
			_fit_3d_resolution()
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
	for view in [["town noon", Vector3(53, 0, -3), 30.0, 10.8], ["farm night", Vector3(8, 0, -2), 23.0, 21.5]]:
		cam_target = view[1]
		cam_dist = view[2]
		Game.hour = view[3]
		await _wait(3.0)
		await _frame_ms()
		var base := await _frame_ms()
		print("PROBE %s  window %s px, 3D at %d%%  all on: %.2f ms (%.0f fps)" % [view[0], get_window().size, roundi(vp.scaling_3d_scale * 100.0), base, 1000.0 / base])
		for k in toggles:
			toggles[k].call(false)
			await _wait(0.6)
			var ms := await _frame_ms()
			toggles[k].call(true)
			await _wait(0.3)
			var again := await _frame_ms()
			print("PROBE %s  without %-26s %.2f ms (saves %.2f; all on again %.2f)" % [view[0], k, ms, again - ms, again])
	print("PROBE DONE")
	get_tree().quit()


## Average wall-clock time per frame over 90 frames (run with --disable-vsync to see past the
## display's refresh rate; Metal doesn't report GPU timings).
func _frame_ms() -> float:
	var t0 := Time.get_ticks_usec()
	for i in 150:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t0) / 150000.0


## Asset frames (run with -- --assetframes=/abs/dir): the world props from art/world_assets as
## they look in the game, for reviewing a new model. Late morning light.
func _take_asset_frames() -> void:
	Game.time_running = false
	_set_cam_lock(false)
	Game.hour = 10.5
	await _wait(1.0)
	var views := [
		["asset_plots.png", Vector3(12.8, 0, 0.2), 6.5, 30.0],
		["asset_trees_north.png", Vector3(8.0, 0, -26.0), 24.0, 20.0],
		["asset_trees_west.png", Vector3(-14.0, 0, -6.0), 16.0, 60.0],
		["asset_trees_south.png", Vector3(12.0, 0, 20.0), 20.0, 200.0],
		["asset_bus.png", Vector3(31.0, 0, 3.0), 11.0, 35.0],
		["asset_plaza.png", Vector3(49.0, 0, 1.0), 9.0, 30.0],
		["asset_plaza_wide.png", Vector3(53.0, 0, -1.0), 20.0, 10.0],
		["asset_lane.png", Vector3(41.7, 0, -5.0), 6.0, 70.0],
		# lamp posts at night: one close up (the candle behind clear glass), then the road to town
		["asset_lamp_close.png", Vector3(12.85, 1.2, 4.0), 2.6, 25.0, 22.0],
		["asset_lamps_night.png", Vector3(16.0, 0, 4.0), 11.0, 15.0, 22.0],
		# the sheep in their pen, close: rigged, walking and grazing (tools/rig_sheep.py)
		["asset_sheep.png", Vector3(20.0, 0, -2.0), 5.0, 30.0],
		["asset_sheep_low.png", Vector3(20.0, 0.3, -1.0), 3.2, 160.0],
		# the town buildings (art/world_assets/town_buildings): the row from the plaza, each front,
		# and the shop at dusk with its windows lit. The 6th element is the camera pitch.
		["asset_town_row.png", Vector3(52.5, 1.5, -10.0), 25.0, 0.0, 10.5, 20.0],
		["asset_shop.png", Vector3(56.5, 2.0, -11.5), 11.0, 18.0, 10.5, 16.0],
		["asset_bakery.png", Vector3(41.75, 2.0, -10.75), 10.5, 22.0, 10.5, 16.0],
		["asset_office.png", Vector3(64.25, 2.0, -11.0), 10.5, -20.0, 10.5, 16.0],
		["asset_shop_dusk.png", Vector3(56.5, 2.0, -11.5), 11.0, -12.0, 19.6, 16.0],
		# the crops (art/world_assets/crops): pumpkins growing along the back row, turnips the next,
		# then the ripe ones close up; and the yarn and needles by the rocking chair (art/world_assets/yarn)
		["asset_crops.png", Vector3(12.8, 0.2, -0.4), 6.0, 15.0, 10.5, 34.0],
		["asset_crops_low.png", Vector3(13.4, 0.25, -0.4), 3.6, 25.0, 10.5, 18.0],
		["asset_crops_ripe.png", Vector3(14.6, 0.25, -0.5), 2.4, 20.0, 10.5, 24.0],
		# (the camera looks 0.6 m above its target, so floor-level things get a target below the floor)
		["asset_yarn_basket.png", Vector3(2.55, -0.4, 1.95), 2.0, 35.0, 10.5, 36.0],
		["asset_yarn_balls.png", Vector3(2.0, -0.45, 4.35), 1.6, 80.0, 10.5, 32.0],
		["asset_needles.png", Vector3(2.85, -0.45, 1.55), 1.3, 20.0, 10.5, 55.0],
	]
	# pumpkins at each stage on the back row, turnips on the next (Plot.stage(): 0, 1/3, 2/3, ripe)
	for k in 4:
		for row in 2:
			var pl = plots[row * 4 + k]
			pl.plant("pumpkin" if row == 0 else "turnip")
			pl.growth = pl.hours_needed() * [0.0, 0.4, 0.75, 1.0][k]
			pl.water()
	spawn_prop("bus", "asset_bus", Vector3(31.0, 0, 3.0))
	for v in views:
		player.position = v[1] + Vector3(1.5, 0, 2.0)
		cam_yaw = deg_to_rad(v[3])
		cam_yaw_goal = cam_yaw
		cam_target = v[1]
		cam_dist = v[2]
		Game.hour = float(v[4]) if v.size() > 4 else 10.5
		if v.size() > 5:
			player.position = v[1] + Vector3(4.0, 0, 6.0) # out of the way
			cam_pitch = float(v[5])
			cam_glide = {"pos": v[1], "dist": v[2], "pitch": v[5]}
		await _wait(1.2)
		await _shot(v[0])
		cam_glide = {}
	print("ASSET FRAMES DONE")
	get_tree().quit()


## Photo frames (run with -- --photoframes=/abs/dir): night shots by lamplight to show the game
## off, with the HUD hidden, a low camera and strong round bokeh. Each view is
## [file, camera target, distance, yaw, pitch, hour, focus distance, blur amount, Nora's spot].
func _take_photo_frames() -> void:
	Game.time_running = false
	_set_cam_lock(false)
	hud.visible = false
	cam_follow = false
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	await _wait(1.0)
	for l in find_children("*", "Label3D", true, false):
		(l as Label3D).visible = false # no name tags in the photos
	var views := [
		# the lantern close up from its open side, the farmhouse and lamps melting into bokeh
		["photo_lantern.png", Vector3(12.85, 0.8, 4.0), 1.6, 70.0, 6.0, 21.5, 1.6, 0.3, Vector3(30, 0, 30)],
		# Nora under the lamp by the bench, lamps and plots soft behind her
		["photo_nora_lamp.png", Vector3(13.6, 0.55, 4.6), 3.2, -60.0, 8.0, 21.0, 3.2, 0.25, Vector3(13.6, 0, 4.6)],
		# down the farm path at dusk: a lamp in focus, the next ones glowing beyond
		["photo_path_dusk.png", Vector3(19.85, 0.8, 4.6), 2.2, 70.0, 8.0, 19.4, 2.2, 0.3, Vector3(30, 0, 30)],
		# the bench from low in the grass, its lamp a glow behind it
		["photo_bench.png", Vector3(14.6, 0.35, 5.0), 2.6, 63.0, 6.0, 21.8, 2.6, 0.3, Vector3(30, 0, 30)],
		# the pond lamp at night
		["photo_pond_lamp.png", Vector3(7.05, 0.8, -13.4), 1.8, 60.0, 6.0, 22.0, 1.8, 0.3, Vector3(30, 0, 30)],
		# the road lamp, the town's lamps a blur beyond
		["photo_road.png", Vector3(29.75, 0.8, 1.8), 1.8, -130.0, 5.0, 21.2, 1.8, 0.3, Vector3(30, 0, 30)],
		# Nora walking home past the lamps, close and low
		["photo_nora_walk.png", Vector3(16.5, 0.7, 4.3), 2.4, 30.0, 6.0, 20.6, 2.4, 0.28, Vector3(16.5, 0, 4.3)],
	]
	for v in views:
		player.position = v[8]
		player.face_point(v[1] + Vector3(sin(deg_to_rad(v[3])), 0, cos(deg_to_rad(v[3]))) * 5.0)
		Game.hour = float(v[5])
		cam_yaw = deg_to_rad(v[3])
		cam_yaw_goal = cam_yaw
		cam_target = v[1]
		cam_dist = v[2]
		cam_pitch = v[4]
		cam_glide = {"pos": v[1], "dist": v[2], "pitch": v[4]}
		_photo_dof = {"focus": v[6], "amount": v[7]}
		await _wait(2.0)
		await _shot(v[0])
	print("PHOTO FRAMES DONE")
	get_tree().quit()


func _apply_photo_dof() -> void:
	var f: float = _photo_dof["focus"]
	cam_attr.dof_blur_amount = float(_photo_dof["amount"])
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = f + 0.35
	cam_attr.dof_blur_far_transition = maxf(1.0, f * 0.8)
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = maxf(0.3, f - 0.9)
	cam_attr.dof_blur_near_transition = 0.8


## Woolcore style frames (run with -- --styleframes=/abs/dir): the farm at golden hour, the
## hearth at night, and Maplewood with the embroidered dialogue box.
func _take_style_frames() -> void:
	Game.time_running = false
	_set_cam_lock(false)
	await _wait(1.0)
	# 1. the farm, late afternoon
	Game.hour = 16.4
	player.position = Vector3(10.6, 0, 3.4)
	player.face_point(Vector3(18, 0, -1))
	cam_yaw = deg_to_rad(38.0)
	cam_yaw_goal = cam_yaw
	cam_target = Vector3(12.5, 0, -0.5)
	cam_dist = 17.0
	await _wait(1.5)
	await _shot("style_01_farm.png")
	# 2. the hearth: knitting by the fire after dark, Gran's words on screen
	Game.hour = 20.2
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	player.position = Vector3(3.4, 0, 4.4)
	_do_action(chair, "knit")
	var t := 0.0
	while not player.busy and t < 10.0:
		await _wait(0.1)
		t += 0.1
	await _wait(1.2)
	cam_yaw = deg_to_rad(52.0)
	cam_yaw_goal = cam_yaw
	cam_target = chair.position + Vector3(-0.3, 0.6, -0.4)
	cam_dist = 6.2
	hide_activity_bar = true
	hud.story_begin()
	hud.story_say("", "\"Knit something. It helps. It always helped.\"", null)
	hud.story_click()
	await _wait(1.0)
	await _shot("style_02_hearth.png")
	await hud.story_end()
	# 3. Maplewood: Rowan, his portrait, and a choice
	player.walk([])
	Game.hour = 10.2
	var rowan := _villager("rowan")
	rowan.settle_at(Vector3(46.4, 0, 1.2))
	player.position = Vector3(45.0, 0, 2.6)
	rowan.face_point(player.position, 30.0)
	player.face_point(rowan.position)
	rowan.talk(30.0)
	cam_yaw = deg_to_rad(45.0)
	cam_yaw_goal = cam_yaw
	cam_target = (rowan.position + player.position) * 0.5 + Vector3(0, 0.9, 0)
	cam_dist = 7.5
	for v in villagers:
		if v.tag:
			v.tag.visible = false
	hud.story_begin()
	hud.story_say("Rowan", "Come find me on the hill if they give you trouble. They usually do.", load("res://assets/portraits/rowan_warm.png"))
	hud.story_click()
	hud.story_choices("What do you say?", ["I might take you up on that.", "I'll manage. I always do.", "Are you always this friendly?"])
	await _wait(1.4)
	await _shot("style_03_maplewood.png")
	print("STYLE FRAMES DONE")
	get_tree().quit()


## Auto-play holds on the first line containing `sub`; finish its typing, picture it, go on.
func _act1_shot(sub: String, fname: String) -> void:
	story.pause_on = sub
	var t := 0.0
	while not story.holding and story.is_playing() and t < 40.0:
		await _wait(0.05)
		t += 0.05
	if story.holding:
		hud.story_click()
		await _wait(0.9)
		if fname != "":
			await _shot(fname)
	else:
		print("      (never saw a line with '%s')" % sub)
	story.pause_on = ""
	story.holding = false


func _act1_until_done(timeout: float) -> void:
	var t := 0.0
	while story.is_playing() and t < timeout:
		await _wait(0.1)
		t += 0.1


## Day 5 polish: sound (muted in the test, but every play is counted), the title screen,
## the settings panel and first-time tips.
func _polish_checks() -> void:
	story.auto = false
	hud.hide_dialogue()
	# lamp posts: clear glass with a lit candle inside, and the candle's light flickers
	var candle_lights: Array = find_children("*", "OmniLight3D", true, false).filter(func(l): return l.has_meta("candle"))
	var flick: Array[float] = []
	for k in 8:
		flick.append(Furniture.candle_flicker(k * 0.37))
	var clear_glass := Catalog.lamp_glass().transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and Catalog.lamp_glass().albedo_color.a < 0.5
	_check("lamp posts: clear glass and a flickering candle in each (%d candles, brightness %.2f to %.2f)" % [candle_lights.size(), flick.min(), flick.max()],
		candle_lights.size() >= 1 and clear_glass and flick.max() - flick.min() > 0.08 and flick.min() > 0.4)
	# the town's shop fronts are the modelled buildings (art/world_assets/town_buildings), each with its name
	var built: Array[String] = []
	for b in find_children("Building_*", "Node3D", true, false):
		var meshes := b.find_children("*", "MeshInstance3D", true, false).size()
		var named := false
		for l in b.find_children("*", "Label3D", false, false):
			named = named or (l as Label3D).text != ""
		if meshes > 0 and named:
			built.append(str(b.get_meta("building_model", "")))
	built.sort()
	var want: Array[String] = ["bakery", "office", "shop"]
	_check("town buildings are the modelled shop, bakery and land office, each with its sign (%s)" % ", ".join(built),
		built == want)
	# crops show their modelled growth stages (art/world_assets/crops); the yarn set is modelled too
	var pl = plots[plots.size() - 1]
	var saved: Dictionary = pl.to_dict()
	var staged: Array[String] = []
	for c in ["turnip", "pumpkin"]:
		for k in 4:
			pl.plant(c)
			pl.growth = pl.hours_needed() * [0.0, 0.4, 0.75, 1.0][k]
			pl.refresh()
			for n in pl.crop_root.get_children():
				if not n.is_queued_for_deletion() and str(n.name).begins_with("CropModel"):
					staged.append("%s %d" % [c, k])
	pl.from_dict(saved)
	var yarn_models := 0
	for id in ["yarn_basket", "yarn_balls", "knitting_needles"]:
		var path := str(Catalog.ITEMS.get(id, {}).get("model", ""))
		if path != "" and ResourceLoader.exists(path):
			yarn_models += 1
	_check("crops grow through four modelled stages and the yarn basket, yarn balls and needles are models (%d of 8 stages, %d of 3 yarn models)" % [staged.size(), yarn_models],
		staged.size() == 8 and yarn_models == 3)
	var steps_g := int(audio.played.get("step_grass", 0))
	var steps_w := int(audio.played.get("step_wood", 0))
	var needles := int(audio.played.get("needle", 0))
	_check("footsteps sound on grass and wood, needles click while knitting (grass %d, wood %d, needle %d)" % [steps_g, steps_w, needles],
		steps_g > 10 and steps_w > 3 and needles > 3)
	_check("what's underfoot: wood in the living room, grass in the yard (%s, %s)" % [surface_at(Vector3(3, 0, 2)), surface_at(Vector3(20, 0, 8))],
		surface_at(Vector3(3, 0, 2)) == "wood" and surface_at(Vector3(20, 0, 8)) == "grass")
	# ambience follows the time of day and the weather
	var p0 := player.position
	var w0 = Game.flag("weather", "clear")
	var h0 := Game.hour
	player.walk([])
	player.position = Vector3(20, 0, 8)
	Game.hour = 13.0
	Game.set_flag("weather", "clear")
	await _wait(5.0)
	var day_g := [audio.gain("day"), audio.gain("night"), audio.gain("rain")]
	var lamp_dry := _candle_energy()
	Game.set_flag("weather", "rain")
	await _wait(4.0)
	var lamp_wet := _candle_energy()
	_check("lamps come on in a daytime downpour (1 PM: dry %.2f, raining %.2f)" % [lamp_dry, lamp_wet], lamp_wet > 0.8 and lamp_dry < 0.4)
	# god mode in settings: set the time and weather, stop the clock
	hud.open_settings()
	hud.god_time_slider.value = 17.5
	(hud.god_weather_btns["clear"] as Button).pressed.emit()
	hud.god_freeze_check.button_pressed = true
	var clock0 := Game.time_running
	Game.time_running = true
	await _wait(1.5)
	_check("god mode: the settings set the clock to %s, clear skies, and stop the clock (hour %.2f, %s)" % [hud.god_time_label.text, Game.hour, str(Game.flag("weather"))],
		absf(Game.hour - 17.5) < 0.001 and str(Game.flag("weather")) == "clear" and hud.god_time_label.text == "5:30 PM")
	hud.god_freeze_check.button_pressed = false
	Game.time_running = clock0
	hud.settings_panel.visible = false
	Game.hour = 23.0
	Game.set_flag("weather", "rain") # rain eases in over two seconds
	await _wait(5.0)
	var night_g := [audio.gain("day"), audio.gain("night"), audio.gain("rain")]
	_check("ambience: birds by day, crickets and rain at a wet midnight (day %s, night %s)" % [str(day_g), str(night_g)],
		day_g[0] > 0.6 and day_g[1] < 0.2 and day_g[2] < 0.1 and night_g[1] > 0.3 and night_g[2] > 0.6 and night_g[0] < 0.1)
	Game.set_flag("weather", w0)
	Game.hour = h0
	player.position = p0
	# memories muffle the music
	hud.set_memory(true, 0.2)
	await _wait(3.0)
	var mg := audio.gain("music")
	var lp := AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Music"), audio._memory_fx)
	hud.set_memory(false, 0.2)
	await _wait(3.0)
	_check("a memory flashback muffles and quietens the music (gain %.2f, low-pass %s, after %.2f)" % [mg, lp, audio.gain("music")],
		mg < 0.7 and lp and audio.gain("music") > 0.9)
	# settings
	audio.set_volumes(0.3, 0.5)
	hud.open_settings(0.3, 0.5, false)
	var mdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	await _wait(0.4)
	await _shot("40_settings.png")
	_check("settings: music and sound sliders set the buses (%.1f dB, %.1f dB; panel %s, slider %.1f)" % [mdb, sdb, hud.settings_panel.visible, hud.music_slider.value],
		hud.settings_panel.visible and absf(mdb - linear_to_db(0.09)) < 0.1 and absf(sdb - linear_to_db(0.25)) < 0.1 and is_equal_approx(hud.music_slider.value, 0.3))
	audio.set_volumes(0.7, 0.8)
	hud.settings_panel.visible = false
	# title screen
	show_title(true)
	await _wait(1.2)
	await _shot("41_title.png")
	var faded := hud.chrome.all(func(c): return c.modulate.a < 0.05)
	_check("title screen: shown over the farm, clock paused, chrome hidden (visible %s, continue %s, chrome hidden %s)" % [hud.title_visible(), hud.title_continue_btn.visible, faded],
		hud.title_visible() and hud.title_continue_btn.visible and not Game.time_running and faded)
	_title_continue()
	await _wait(1.0)
	_check("Continue leaves the title and starts the clock again (title %s, clock %s)" % [hud.title_visible(), Game.time_running],
		not hud.title_visible() and Game.time_running and not title_on)
	# tips
	tips_enabled = true
	_tip_t = 0.0
	await _wait(1.6)
	await _shot("42_tip.png")
	_check("a first-time tip appears after Act 1 and is remembered ('%s')" % hud.tip_label.text.left(40),
		hud.tip_panel.visible and Game.flag("tip_click") == true)
	tips_enabled = false


## The brightest lamp candle's light right now (lamp posts and lanterns), without its flicker.
func _candle_energy() -> float:
	var e := 0.0
	for l in find_children("*", "OmniLight3D", true, false):
		if l.has_meta("candle"):
			var f: Node = l.get_parent()
			var flick: float = Furniture.candle_flicker(f.get("_t")) if f.get("_t") != null else 1.0
			e = maxf(e, l.light_energy / maxf(flick, 0.01))
	return e


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)


func _autotest() -> void:
	autotest_jog = true
	await _wait(1.5)
	await _shot("01_live.png")
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	_live_click(cam.unproject_position(chair.global_position + Vector3(0, 0.6, 0)))
	await _wait(0.4)
	_check("action menu opens on rocking chair as a ring (%s)" % str(hud.pie.labels()), hud.is_menu_open() and hud.pie.labels().size() == 2)
	await _shot("02_menu.png")
	hud.hide_menu()
	_check("the needs panel shows six needs", hud.needs_meters.size() == 6)
	var happy0 := Game.happiness

	await _graphics_checks()
	await _character_checks()
	await _bed_checks()
	_do_action(chair, "knit")
	await _wait(3.6)
	_check("heroine sits to knit (%s, needles shown=%s)" % [player.body.current(), player.body.props != null and player.body.props.visible], player.busy and player.position.distance_to(chair.position) < 1.2 and player.body.current() == "SitKnit" and player.body.props != null and player.body.props.visible)
	var cd0 := cam_dist
	cam_target = player.position
	cam_dist = 5.5
	await _wait(1.6)
	await _shot("02c_knit_closeup.png")
	cam_dist = cd0
	await _wait(4.8)
	_check("knit a sweater (sweaters=%d, wool=%d)" % [Game.count("sweater"), Game.count("wool")], Game.count("sweater") == 1 and Game.count("wool") == 0)
	_check("knitting made her happier and she wears a better sweater (happiness %.0f→%.0f, wearing %s)" % [happy0, Game.happiness, Game.stars(Game.worn_quality)],
		Game.happiness > happy0 + 8.0 and Game.worn_quality == 2)

	_do_action(sheep_list[0], "shear")
	await _wait(15.0)
	_check("sheared sheep (wool=%d)" % Game.count("wool"), Game.count("wool") == 2)
	var shorn: String = sheep_list[0].coat()
	var woolly_other: String = sheep_list[1].coat()
	var wool_keep: float = sheep_list[0].wool
	sheep_list[0].wool = 0.7 # half grown: the woolly model is back, a little smaller
	var regrown: String = sheep_list[0].coat()
	sheep_list[0].wool = wool_keep
	_check("a shorn sheep shows the shorn model and gets her coat back as it regrows (%s, others %s, at 70%% %s)" % [shorn, woolly_other, regrown],
		shorn == "sheared" and woolly_other == "woolly" and regrown == "woolly" and sheep_list[0].coat() == "sheared")
	var table = furniture.filter(func(f): return f.item_id == "coffee_table")
	_check("the coffee table in her living room is the Woolcore model (%d meshes)" % (table[0].find_children("*", "MeshInstance3D", true, false).size() if table.size() > 0 else 0),
		table.size() == 1 and table[0].find_children("model", "MeshInstance3D", true, false).size() == 1)
	_live_click(cam.unproject_position(sheep_list[0].global_position + Vector3(0, 0.5, 0)))
	await _wait(0.5)
	var shear_pill: Dictionary = hud.pie._items[0] if hud.is_menu_open() else {}
	var loops: Array = sheep_list.map(func(sh): return sh.current_loop())
	_check("sheep are rigged and play their loops: walking, grazing or looking about (%s)" % str(loops),
		loops.all(func(l): return l in ["Walk", "Graze", "Idle"]))
	_check("a sheared sheep's menu shows wool regrowing as a bar (%s)" % str(hud.pie.labels()), shear_pill.has("progress") and not bool(shear_pill.get("enabled", true)))
	await _shot("02d_menu_sheep.png")
	hud.hide_menu()
	var w_in := 0.0
	var p0 := player.position
	player.position = Vector3(3.0, 0, 2.0)
	w_in = warmth_target()
	player.position = Vector3(20.0, 0, 8.0)
	var r0 := rain
	rain = 1.0
	var w_rain := warmth_target()
	rain = r0
	player.position = p0
	_check("indoors is warmer than out in the rain (%.0f vs %.0f)" % [w_in, w_rain], w_in > w_rain + 20.0)

	var coins0 := Game.coins
	_do_action(plots[3], "plant_pumpkin")
	await _wait(6.0)
	_check("planted pumpkin (crop=%s, coins %d→%d)" % [plots[3].crop, coins0, Game.coins], plots[3].crop == "pumpkin" and Game.coins == coins0 - 30)
	_do_action(plots[3], "water")
	await _wait(3.0)
	_check("watered plot", plots[3].watered)
	await _wait(2.0)
	_do_action(plots[0], "harvest")
	var th := 0.0 # she walks there first; on a slow machine that takes longer than 4 s
	while (Game.count("turnip") < 4 or player.busy) and th < 12.0:
		await _wait(0.2)
		th += 0.2
	_check("harvested turnips (turnips=%d)" % Game.count("turnip"), Game.count("turnip") == 4)
	await _shot("03_farm.png")

	var coins1 := Game.coins
	_do_action(bin, "ship_sweater")
	await _wait(5.0)
	_check("shipped sweater (+%d)" % (Game.coins - coins1), Game.coins == coins1 + 140)

	set_mode(Mode.BUILD)
	cam_target = Vector3(4, 0, 3)
	await _wait(0.6)
	var nthumb := (Catalog.INDOOR + Catalog.OUTDOOR).size()
	var tw8 := 0.0
	while hud.thumbs.done.size() < nthumb and tw8 < 20.0:
		await _wait(0.2)
		tw8 += 0.2
	var with_icon := hud.item_buttons.values().filter(func(b): return b.icon != null).size()
	_check("every catalog card has a rendered picture (%d of %d)" % [with_icon, nthumb], with_icon == nthumb)
	await _shot("04a_catalog.png")
	_begin_place("armchair")
	var sp := cam.unproject_position(Vector3(5.5, 0, 4.9))
	_last_mouse = sp
	_update_ghost(sp)
	await _wait(0.3)
	await _shot("04_build.png")
	var n0 := furniture.size()
	var coins2 := Game.coins
	_build_click(sp, false)
	_check("placed armchair (valid=%s, coins %d→%d)" % [ghost_valid, coins2, Game.coins], furniture.size() == n0 + 1 and Game.coins == coins2 - 220)
	_begin_place("flower_pot")
	var bad := cam.unproject_position(Vector3(12.2, 0, 0.2))
	_update_ghost(bad)
	_check("flower pot can't go on the farm plots (ghost=%s)" % [ghost != null], ghost != null and not ghost_valid)
	var good := cam.unproject_position(Vector3(10.5, 0, 6.5))
	_update_ghost(good)
	_check("flower pot can go in the yard", ghost_valid)
	_cancel_ghost()

	Game.coins += 1000
	_expand_house()
	_check("expanded house (level=%d)" % Game.house_level, Game.house_level == 1)
	set_mode(Mode.LIVE)
	_set_cam_lock(false)
	cam_target = Vector3(5, 0, 0)
	cam_dist = 27.0
	await _wait(1.0)
	await _shot("05_expanded.png")

	await _camera_checks()

	var path := _find_path(Vector3(2, 0, 5), Vector3(20, 0, -2))
	_check("path from living room to sheep pen (%d waypoints)" % path.size(), path.size() > 1 and path[-1].distance_to(Vector3(20, 0, -2)) < 0.8)

	Game.hour = 21.5
	await _wait(0.8)
	await _shot("06_night.png")

	var day0 := Game.day
	var g0: float = plots[3].growth
	_go_to_sleep(false)
	await _wait(2.5)
	_check("slept to next day (day %d→%d, pumpkin growth %.1f→%.1f)" % [day0, Game.day, g0, plots[3].growth], Game.day == day0 + 1 and plots[3].growth > g0)

	_save_game()
	_check("save file written", FileAccess.file_exists(Game.save_path))
	await _town_checks()
	_data_checks()
	await _chat_checks()
	await _story_checks()
	await _act1_checks()
	await _romance_checks()
	await _polish_checks()
	await _bench_checks()
	await _god_checks() # ends by building the world again from the layout it saved, then "AUTOTEST DONE"


## The park benches (art/world_assets/bench_park): the long bench and the short single seat are
## both models, about one bench in five out in the world is the short one, and she sits on the
## boards of each.
func _bench_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var benches: Array = []
	for n in find_children("*", "Node3D", true, false):
		if n is Furniture and not n.is_ghost and n.item_id in Catalog.BENCH_IDS:
			benches.append(n)
	var short: Array = benches.filter(func(f): return f.item_id == "bench_short")
	var modelled: bool = benches.all(func(f): return f.find_children("model", "MeshInstance3D", true, false).size() == 1)
	_check("the benches around the map are the park bench models, mostly long with a short one among them (%d benches, %d short)" % [benches.size(), short.size()],
		benches.size() >= 3 and modelled and short.size() >= 1 and short.size() * 3 <= benches.size())
	var picked := 0
	for i in 5000:
		if Catalog.world_bench(float(i % 100) * 0.7, float(i / 100) * 0.7) == "bench_short":
			picked += 1
	_check("one bench place in five gets the short bench (%.1f%% of 5000 places)" % (picked / 50.0), picked > 850 and picked < 1150)
	_set_cam_lock(false)
	for id in Catalog.BENCH_IDS:
		var of_kind: Array = benches.filter(func(f): return f.item_id == id)
		if of_kind.is_empty():
			_check("there is a %s to sit on" % id, false)
			continue
		var b: Furniture = of_kind[0]
		player.position = b.global_position + b.front() * 1.4
		_perform(b, "rest")
		cam_target = b.global_position
		cam_dist = 6.5
		await _wait(1.6)
		var seat: Vector3 = _seat_point(b)
		_check("she rests on the %s, on its boards (%s, %.2f m from the seat)" % [id, player.body.current(), player.position.distance_to(seat)],
			player.busy and player.body.current() == "SitIdle" and player.position.distance_to(seat) < 0.05)
		await _shot("43_%s.png" % id)
		await _wait(3.2)
	_set_cam_lock(true)


const GOD_TEST_LAYOUT := "user://autotest_layout.json"


## Points the camera at a spot for the world editor's checks.
func _god_look(p: Vector3, dist := 16.0) -> void:
	cam_target = Vector3(p.x, 0, p.z)
	cam_dist = dist
	await _wait(0.5)


## God mode's world editor (scripts/god_mode.gd), driven the way a mouse would: pick things up by
## clicking them, drag, turn, delete, copy and undo, paint and rub out roads, then save. The last
## step loads the whole scene again from the saved layout (_god_reload_checks).
func _god_checks() -> void:
	if god.loaded:
		# the checks edit a known world: build it again as the code makes it, without the saved layout
		# (the rest of the autotest has just played the game with the layout on, as players get it)
		await get_tree().process_frame # not from inside _ready (--godcheck starts here)
		Engine.set_meta("ke_god_stock", true)
		get_tree().reload_current_scene()
		return
	autotest_jog = true
	if FileAccess.file_exists(GOD_TEST_LAYOUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GOD_TEST_LAYOUT))
	await _wait(0.5)
	var kinds := {}
	for el in god.els:
		var group := "trees" if el.kind.begins_with("tree_") else ("buildings" if el.kind.begins_with("building_") else ("lamps" if el.kind == "decor_lantern" else "other"))
		kinds[group] = int(kinds.get(group, 0)) + 1
	_check("god mode: the world editor can pick up everything in the world (%d things: %s)" % [god.els.size(), str(kinds)],
		god.els.size() > 400 and int(kinds.get("trees", 0)) > 50 and int(kinds.get("buildings", 0)) == 3 and int(kinds.get("lamps", 0)) >= 10)
	hud.open_settings()
	await _wait(0.3)
	_check("god mode: 'Edit the world' is in the settings for the admin only (shown %s, admin %s)" % [hud.god_edit_check.visible, GodMode.is_admin()],
		hud.god_edit_check.visible == GodMode.is_admin() and GodMode.is_admin())
	var blades0: int = grass.blade_count
	hud.god_edit_check.button_pressed = true
	await _wait(0.4)
	_check("god mode: switching it on opens the editor's toolbar, closes the settings and stops the clock",
		god.active and god._ui.visible and not hud.settings_panel.visible and not Game.time_running)

	# a lamp post on the plaza: click it, drag it, turn it with R
	var lamp: GodMode.El = god.by_key.get("decor_lantern@46.00,-5.40")
	var lamp_from: Vector3 = lamp.xf.origin
	await _god_look(lamp_from, 14.0)
	god.press(cam.unproject_position(lamp_from + Vector3(0, 0.2, 0)))
	var picked_lamp: bool = god.selected == lamp
	var lamp_to := lamp_from + Vector3(2.0, 0, 1.5)
	god.move(cam.unproject_position(lamp_to + Vector3(0, 0.2, 0)))
	god.release()
	await _wait(0.2)
	_check("god mode: a click picks up the lamp post and a drag moves it, obstacle and all (%.2f m from where it was dropped; old spot free %s, new spot blocked %s)" % [lamp.xf.origin.distance_to(lamp_to), _walkable(_cell(lamp_from)), not _walkable(_cell(lamp.xf.origin))],
		picked_lamp and lamp.xf.origin.distance_to(lamp_to) < 0.3 and lamp.node.global_position.distance_to(lamp.xf.origin) < 0.001 and _walkable(_cell(lamp_from)) and not _walkable(_cell(lamp.xf.origin)))
	await _key_tap(KEY_R)
	await _key_tap(KEY_R)
	await _key_tap(KEY_R)
	var turned_left := rad_to_deg(angle_difference(GodMode._yaw(lamp.base), GodMode._yaw(lamp.xf)))
	await _key_tap(KEY_T)
	var lamp_turn := rad_to_deg(angle_difference(GodMode._yaw(lamp.base), GodMode._yaw(lamp.xf)))
	_check("god mode: R turns the selected thing 15 degrees to the left a press and T to the right (%.1f degrees after three Rs, %.1f after a T)" % [turned_left, lamp_turn],
		absf(turned_left - 45.0) < 0.1 and absf(lamp_turn - 30.0) < 0.1)
	await _key_tap(KEY_EQUAL) # + makes it a tenth bigger
	var lamp_size: float = GodMode._size_of(lamp)
	var copy: GodMode.El = god.duplicate_selected()
	_check("god mode: Copy sets a second lamp post down beside it", copy != null and copy.added and copy.node.visible and god.selected == copy and decor.has(copy.node))

	# the hay bale by the market: delete it, undo, delete it again
	var bale: GodMode.El = god.by_key.get("decor_hay_bale@51.60,-8.60")
	god.select(bale)
	await _key_tap(KEY_DELETE)
	var gone: bool = bale.deleted and not bale.node.visible and _walkable(_cell(bale.xf.origin)) and _ray_target(cam.unproject_position(bale.xf.origin + Vector3(0, 0.3, 0))) != bale.node
	god.undo()
	var back: bool = not bale.deleted and bale.node.visible and not _walkable(_cell(bale.xf.origin))
	god.select(bale)
	god.delete_selected()
	_check("god mode: Delete removes the hay bale and frees its spot; Undo brings it back (gone %s, back %s)" % [gone, back], gone and back and bale.deleted)

	# a tree: click its trunk, drag it; its fallen leaves come with it
	var tree: GodMode.El = god.scenery["tree_maple_autumn"][0]
	await _god_look(tree.xf.origin, 22.0)
	god.press(cam.unproject_position(tree.xf.origin + Vector3(0, 0.7, 0)))
	var picked_tree: bool = god.selected != null and god.selected.kind.begins_with("tree_")
	if picked_tree:
		tree = god.selected
	var tree_from: Vector3 = tree.xf.origin
	var leaf_from := Vector3.ZERO
	if not tree.leaves.is_empty():
		leaf_from = World.tree_litter.multimesh.get_instance_transform(tree.leaf0).origin
	god.move(cam.unproject_position(tree_from + Vector3(1.5, 0, 2.0)))
	god.release()
	var tree_moved: Vector3 = tree.xf.origin - tree_from
	var leaf_moved := tree_moved
	if not tree.leaves.is_empty():
		leaf_moved = World.tree_litter.multimesh.get_instance_transform(tree.leaf0).origin - leaf_from
	var drawn_at: Vector3 = (tree.mmi.transform * tree.mmi.multimesh.get_instance_transform(tree.idx)).origin
	_check("god mode: a tree is picked by its trunk and dragged, and its fallen leaves follow (moved %.2f m, leaves %.2f m)" % [tree_moved.length(), leaf_moved.length()],
		picked_tree and tree_moved.length() > 1.5 and drawn_at.distance_to(tree.xf.origin) < 0.001 and (leaf_moved - tree_moved).length() < 0.01)
	var tree_kind: String = tree.kind
	var tree_spot: Vector3 = tree.xf.origin
	# a rock: copy it; a bush: delete it
	var rock: GodMode.El = god.scenery["rock_single"][0]
	var rocks0: int = god.scenery["rock_single"].size()
	god.select(rock)
	var rock2: GodMode.El = god.duplicate_selected()
	var bush: GodMode.El = god.scenery["bush_round"][0]
	var bushes0: int = god.scenery["bush_round"].size()
	god.select(bush)
	god.delete_selected()
	var bush_scale: float = bush.mmi.multimesh.get_instance_transform(bush.idx).basis.get_scale().length()
	_check("god mode: scenery can be copied and deleted too (rocks %d to %d, the deleted bush is drawn at size %.2f)" % [rocks0, god.scenery["rock_single"].size(), bush_scale],
		rock2 != null and god.scenery["rock_single"].size() == rocks0 + 1 and rock2.mmi != null and bush.deleted and bush_scale < 0.001)

	# roads: one click of a wide cobble brush is a round patch; a drag paints a gravel track
	var patch := Vector3(21.0, 0, 7.5)
	await _god_look(patch, 20.0)
	var in_patch := func(e) -> bool: return GodMode.SMALL.has(e.kind) and not e.deleted and Vector2(e.xf.origin.x - patch.x, e.xf.origin.z - patch.z).length() < 1.9
	var plants0: int = god.els.filter(in_patch).size()
	god.set_tool("cobble")
	god.set_brush(2.0)
	god.press(cam.unproject_position(patch))
	god.release()
	await _wait(0.3)
	var plants1: int = god.els.filter(in_patch).size()
	var round_ok: bool = god.road_at(patch.x, patch.z) == "cobble" and god.road_at(patch.x + 1.3, patch.z + 1.3) == "cobble" and god.road_at(patch.x + 1.6, patch.z + 1.6) == ""
	var stock_gone: bool = find_children("Cobbles_*", "MultiMeshInstance3D", false, false).is_empty() and not find_children("PaintedCobbles_*", "MultiMeshInstance3D", false, false).is_empty()
	_check("god mode: a click of the cobblestone brush lays a round patch of paving (4 m across, corners clear %s), and the plaza and paths are still there (plaza %s, farm path %s, %d tiles)" % [round_ok, god.road_at(47.0, 0.0), god.road_at(12.0, 3.0), god.painted_tiles()],
		round_ok and stock_gone and god.road_at(47.0, 0.0) == "cobble" and god.road_at(12.0, 3.0) == "dirt" and god.painted_tiles() > 20)
	_check("god mode: no grass grows through the new paving, and the tufts and flowers it covered are cleared (grass %.2f there, %d blades before, %d now; small plants on it %d to %d)" % [grass.grass_at(patch.x, patch.z), blades0, grass.blade_count, plants0, plants1],
		grass.grass_at(patch.x, patch.z) < 0.2 and grass.blade_count < blades0 and plants1 == 0)
	god.set_tool("gravel")
	god.set_brush(0.6)
	god.press(cam.unproject_position(Vector3(11.0, 0, 8.5)))
	god.move(cam.unproject_position(Vector3(14.0, 0, 8.0)))
	god.move(cam.unproject_position(Vector3(17.0, 0, 8.5)))
	god.release()
	await _wait(0.3)
	await _shot("60_god_roads.png")
	_check("god mode: dragging the gravel brush paints a track (%s at its middle, %s beside it)" % [god.road_at(14.0, 8.0), god.road_at(14.0, 9.5)],
		god.road_at(14.0, 8.0) == "gravel" and god.road_at(12.5, 8.25) == "gravel" and god.road_at(14.0, 9.5) == "")
	god.set_tool("erase")
	god.set_brush(1.0)
	await _god_look(Vector3(47.0, 0, 2.0), 18.0)
	god.press(cam.unproject_position(Vector3(47.0, 0, 2.0)))
	god.release()
	var rubbed: bool = god.road_at(47.0, 2.0) == ""
	god.undo()
	_check("god mode: the eraser rubs paving out, and Undo puts it back (%s)" % god.road_at(47.0, 2.0), rubbed and god.road_at(47.0, 2.0) == "cobble")

	# Shift paints a straight line that snaps to 45 degrees and follows the pointer
	await _god_look(Vector3(31.0, 0, 9.5), 24.0)
	god.set_tool("gravel")
	god.set_brush(0.5)
	var line_a := Vector3(29.0, 0, 8.0)
	god.press(cam.unproject_position(line_a))
	god.move(cam.unproject_position(Vector3(34.0, 0, 9.2)), true) # 13 degrees off east: snaps to due east
	var east: bool = god.road_at(33.5, 8.0) == "gravel" and god.road_at(33.5, 9.2) == ""
	god.move(cam.unproject_position(Vector3(33.0, 0, 12.0)), true) # now south-east: the line swings round
	god.release()
	await _wait(0.2)
	_check("god mode: holding Shift paints a straight line that snaps to 45 degrees and swings with the pointer (due east first %s; then south-east: %s on the diagonal, %s where the east line was)" % [east, god.road_at(31.0, 10.0), god.road_at(33.5, 8.0)],
		east and god.road_at(31.0, 10.0) == "gravel" and god.road_at(32.5, 11.5) == "gravel" and god.road_at(33.5, 8.0) == "" and god.road_at(29.0, 8.0) == "gravel")
	# a square brush, and a brush 2.5 times the old largest
	god.set_brush_square(true)
	god.set_brush(1.0)
	var sq := Vector3(33.0, 0, 16.0)
	await _god_look(sq, 20.0)
	god.press(cam.unproject_position(sq))
	god.release()
	god.set_brush(99.0)
	var widest: float = god.brush
	god.set_brush_square(false)
	god.set_brush(1.0)
	_check("god mode: the square brush fills its corners, and the brush goes up to %.0f m across (corner %s, just outside %s)" % [widest * 2.0, god.road_at(sq.x + 0.9, sq.z + 0.9), god.road_at(sq.x + 1.2, sq.z)],
		god.road_at(sq.x + 0.9, sq.z + 0.9) == "gravel" and god.road_at(sq.x - 0.9, sq.z + 0.9) == "gravel" and god.road_at(sq.x + 1.2, sq.z) == "" and absf(widest - 15.0) < 0.001)

	# the Place tool: pick anything from the list and set it down one at a time
	var options: Array = god.place_options()
	var ids: Array = options.map(func(o): return o[0])
	var leaf_item := -1
	for i in god._place_pick.item_count:
		if str(god._place_pick.get_item_metadata(i)) == "scenery:leaf_yellow":
			leaf_item = i
	god._place_pick.select(leaf_item)
	god._place_pick.item_selected.emit(leaf_item)
	var leaf_spot := Vector3(30.0, 0, 15.0)
	# the chosen thing follows the pointer, outlined in green, before it is set down
	god.move(cam.unproject_position(leaf_spot))
	var preview: MeshInstance3D = god._ghost as MeshInstance3D
	var preview_ok: bool = preview != null and preview.visible and preview.mesh != null and preview.material_overlay != null \
		and (preview.material_overlay as StandardMaterial3D).albedo_color.g > 0.9 and preview.global_position.distance_to(leaf_spot) < 0.1
	god.press(cam.unproject_position(leaf_spot))
	god.release()
	god.press(cam.unproject_position(leaf_spot + Vector3(0.6, 0, 0.3)))
	god.release()
	var leaves_placed: int = god.scenery.get("leaf_yellow", []).size()
	var last_leaf: GodMode.El = god.scenery["leaf_yellow"][-1] if leaves_placed > 0 else null
	god.place_id = "decor:milk_churn"
	var churn: GodMode.El = god.place(Vector3(31.5, 0, 15.5))
	god.place_id = "scenery:tree_spruce"
	var spruces0: int = god.scenery["tree_spruce"].size()
	var spruce: GodMode.El = god.place(Vector3(36.0, 0, 17.0))
	_check("god mode: the Place list holds everything in the world (%d things), and a click sets one down: two gold leaves, a milk churn, a spruce" % options.size(),
		options.size() > 50 and ids.has("scenery:rock_boulder") and ids.has("scenery:hedge") and ids.has("decor:lantern") and ids.has("scenery:maplewood_bus") and not ids.has("scenery:cobble_plaza_0")
		and god.tool == "place" and preview_ok and leaves_placed == 2 and last_leaf != null and last_leaf.kind == "leaf_yellow" and last_leaf.xf.origin.distance_to(leaf_spot + Vector3(0.6, 0, 0.3)) < 0.2
		and churn != null and churn.added and decor.has(churn.node) and spruce != null and god.scenery["tree_spruce"].size() == spruces0 + 1 and not spruce.leaves.is_empty())

	# R and T turn the preview, and what is set down stands the way the preview showed it
	god.place_id = "scenery:fence_picket"
	god.set_tool("place")
	await _key_tap(KEY_T)
	await _key_tap(KEY_T)
	await _key_tap(KEY_R)
	var preview_turn := rad_to_deg(god._ghost_yaw)
	var turned_fence: GodMode.El = god.place(Vector3(27.0, 0, 18.5))
	var fence_yaw := rad_to_deg(GodMode._yaw(turned_fence.xf))
	await _key_tap(KEY_R) # square to the map again for the row below
	god.place_id = "scenery:tree_maple_autumn"
	god.set_tool("place")
	god.move(cam.unproject_position(Vector3(31.0, 0, 16.5)))
	await _shot("64_god_preview.png")
	god.place_id = "scenery:fence_picket"
	god.set_tool("place")
	# click and hold: a stream of them along the drag; fences dragged along their length join up
	var fences0: int = god.scenery["fence_picket"].size()
	var row_from := Vector3(29.0, 0, 18.0)
	god.press(cam.unproject_position(row_from))
	god.move(cam.unproject_position(row_from + Vector3(2.0, 0, 0)))
	god.move(cam.unproject_position(row_from + Vector3(4.3, 0, 0)))
	god.release()
	var row: Array = god.scenery["fence_picket"].slice(fences0)
	var joined := row.size() >= 4
	for i in range(1, row.size()):
		var step: Vector3 = row[i].xf.origin - row[i - 1].xf.origin
		joined = joined and absf(step.x - row[0].bounds.size.x) < 0.02 and absf(step.z) < 0.02
	# leaves stream out loosely, and one Undo takes the whole stream back
	god.place_id = "scenery:leaf_red"
	god.set_tool("place")
	god.press(cam.unproject_position(Vector3(28.0, 0, 13.0)))
	god.move(cam.unproject_position(Vector3(31.0, 0, 13.4)))
	god.release()
	var red_leaves: int = god.scenery["leaf_red"].filter(func(e): return not e.deleted).size()
	god.undo()
	var red_after: int = god.scenery["leaf_red"].filter(func(e): return not e.deleted).size()
	_check("god mode: R and T turn the preview and the thing is set down that way (preview %.0f, fence %.0f degrees); holding the button streams them out: %d fences joined end to end %s, %d red leaves, all gone after one Undo (%d left)" % [preview_turn, fence_yaw, row.size(), joined, red_leaves, red_after],
		absf(preview_turn + 15.0) < 0.1 and absf(fence_yaw + 15.0) < 0.1 and joined and row.size() <= 5 and red_leaves >= 6 and red_after == 0)

	# + and - resize the selected thing and the preview; the list has small rocks ready-made
	god.place_id = "scenery:rock_single:0.5"
	god.set_tool("place")
	var small_start: float = god.place_size
	await _key_tap(KEY_MINUS)
	var small_set: float = god.place_size
	var small_rock: GodMode.El = god.place(Vector3(33.0, 0, 13.5))
	var rock_size: float = GodMode._size_of(small_rock)
	god.set_tool("select")
	god.select(small_rock)
	await _key_tap(KEY_EQUAL)
	await _key_tap(KEY_EQUAL)
	var rock_grown: float = GodMode._size_of(small_rock)
	_check("god mode: + and - resize things: the lamp post grew to %.0f%%; \"Rock (small)\" and \"Rock cluster (small)\" are in the Place list at half size (%.0f%%, %.0f%% after a -), the rock was set down at %.0f%% and two + made it %.0f%%" % [lamp_size * 100.0, small_start * 100.0, small_set * 100.0, rock_size * 100.0, rock_grown * 100.0],
		absf(lamp_size - 1.1) < 0.001 and ids.has("scenery:rock_cluster:0.5") and ids.has("scenery:rock_single:0.5") and absf(small_start - 0.5) < 0.001 and absf(small_set - 0.5 / 1.1) < 0.001
		and rock_size > small_set * 0.89 and rock_size < small_set * 1.16 and absf(rock_grown / rock_size - 1.21) < 0.01)

	# the sheep pen is one piece: click a fence post, drag it, and the sheep come too
	god.set_tool("select")
	var pen: GodMode.El = god.by_key.get("pen@20.00,-1.00")
	var pen_from: Vector3 = pen.xf.origin
	await _god_look(pen_from, 20.0)
	var sheep_from: Vector3 = sheep_list[0].position
	god.press(cam.unproject_position(pen_from + Vector3(3.0, 0.45, 3.0))) # its south-east corner post
	var picked_pen: bool = god.selected == pen
	god.move(cam.unproject_position(pen_from + Vector3(4.0, 0.45, 4.5)))
	var sheep_moved: Vector3 = sheep_list[0].position - sheep_from # measured at once: sheep wander
	god.release()
	await _wait(0.2)
	var pen_moved: Vector3 = pen.xf.origin - pen_from
	var sheep_in := sheep_list.all(func(sh): return pen_rect.has_point(Vector2(sh.position.x, sh.position.z)))
	_check("god mode: the sheep pen's fence can be picked up, and the pen moves with its sheep (moved %.2f m, a sheep %.2f m, all inside %s; old fence line free %s, new one blocked %s)" % [pen_moved.length(), sheep_moved.length(), sheep_in, _walkable(_cell(pen_from + Vector3(-1.0, 0, -3.0))), not _walkable(_cell(pen.xf.origin + Vector3(-1.0, 0, -3.0)))],
		picked_pen and pen_moved.length() > 1.0 and (sheep_moved - pen_moved).length() < 0.01 and sheep_in and pen_rect.get_center().distance_to(Vector2(pen.xf.origin.x, pen.xf.origin.z)) < 0.01
		and _walkable(_cell(pen_from + Vector3(-1.0, 0, -3.0))) and not _walkable(_cell(pen.xf.origin + Vector3(-1.0, 0, -3.0))))
	var pond: GodMode.El = god.by_key.get("pond@2.50,-16.00")
	await _god_look(pond.xf.origin, 18.0)
	god.press(cam.unproject_position(pond.xf.origin + Vector3(0.6, 0.05, 0.4)))
	god.release()
	_check("god mode: the pond can be picked up too", god.selected == pond)
	god.set_tool("select")
	god.select(lamp)
	await _god_look(lamp.xf.origin, 16.0)
	await _shot("61_god_editor.png")

	# Done saves the layout (to the test's own file, never data/world_layout.json)
	var real_before := FileAccess.get_file_as_string(GodMode.LAYOUT_FILE) if FileAccess.file_exists(GodMode.LAYOUT_FILE) else ""
	god.set_active(false)
	await _wait(0.3)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(GOD_TEST_LAYOUT)) if FileAccess.file_exists(GOD_TEST_LAYOUT) else null
	var real_after := FileAccess.get_file_as_string(GodMode.LAYOUT_FILE) if FileAccess.file_exists(GodMode.LAYOUT_FILE) else ""
	var saved_ok: bool = typeof(saved) == TYPE_DICTIONARY and saved["nodes"].has(lamp.key) and saved["nodes"][bale.key].get("del", false) == true \
		and saved["added"].size() >= 1 and saved["scenery"].has(tree_kind) and saved["scenery"].has("rock_single") and saved["scenery"].has("bush_round") and saved.has("roads")
	_check("god mode: Done closes the editor and saves the layout (lamp, hay bale, copy, trees, rocks, bushes and roads in the file; the real layout file untouched %s)" % (real_before == real_after),
		not god.active and Game.time_running and saved_ok and real_before == real_after and hud.chrome.any(func(c): return c.visible))
	# the last step: the whole scene again, built from that layout
	Engine.set_meta("ke_god_reload", {"lamp": lamp.key, "lamp_at": lamp.xf.origin, "lamp_turn": lamp_turn, "bale": bale.key, "copy_at": copy.xf.origin,
		"tree_kind": tree_kind, "trees": god.scenery[tree_kind].filter(func(e): return not e.deleted).size(), "tree_at": tree_spot, "rocks": god.scenery["rock_single"].filter(func(e): return not e.deleted).size(), "bushes": bushes0 - 1, "lamp_size": lamp_size, "patch": patch,
		"tiles": god.painted_tiles(), "pen_at": pen.xf.origin, "spruces": spruces0 + 1})
	get_tree().reload_current_scene()


## The world built again from the layout _god_checks saved: everything is where it was left.
func _god_reload_checks() -> void:
	var want: Dictionary = Engine.get_meta("ke_god_reload")
	Engine.remove_meta("ke_god_reload")
	await _wait(1.0)
	var lamp: GodMode.El = god.by_key.get(want["lamp"])
	var lamp_at: Vector3 = want["lamp_at"]
	var turn := rad_to_deg(angle_difference(GodMode._yaw(lamp.base), GodMode._yaw(lamp.xf)))
	var bale: GodMode.El = god.by_key.get(want["bale"])
	var copies: Array = god.els.filter(func(e): return e.added and e.kind == "decor_lantern")
	var copy_at: Vector3 = want["copy_at"]
	_check("saved layout: the lamp post is where it was dragged and turned, its copy stands beside it and the hay bale is gone (lamp %.2f m off, turned %.1f, %d copy)" % [lamp.node.global_position.distance_to(lamp_at), turn, copies.size()],
		lamp.node.global_position.distance_to(lamp_at) < 0.01 and absf(turn - float(want["lamp_turn"])) < 0.1 and not _walkable(_cell(lamp_at))
		and absf(GodMode._size_of(lamp) - float(want["lamp_size"])) < 0.01 and absf(lamp.node.scale.x - float(want["lamp_size"])) < 0.01
		and copies.size() == 1 and copies[0].node.global_position.distance_to(copy_at) < 0.01 and not bale.node.visible and _walkable(_cell(bale.base.origin)))
	var kind: String = want["tree_kind"]
	var tree_at: Vector3 = want["tree_at"]
	var tree_there: bool = god.scenery[kind].any(func(e): return e.xf.origin.distance_to(tree_at) < 0.01)
	var drawn := 0
	for m in find_children("Trees_" + kind.substr(5), "MultiMeshInstance3D", false, false):
		drawn += (m as MultiMeshInstance3D).multimesh.instance_count
	var leaves := 0
	for e in god.scenery[kind]:
		leaves += e.leaves.size()
	_check("saved layout: the trees, rocks and bushes are the saved lists (%d trees drawn, the dragged one in place %s, %d leaves under them; %d rocks; %d bushes)" % [drawn, tree_there, leaves, god.scenery["rock_single"].size(), god.scenery["bush_round"].size()],
		god.scenery[kind].size() == int(want["trees"]) and drawn == int(want["trees"]) and tree_there and leaves > 0 and World.tree_litter.multimesh.instance_count >= leaves
		and god.scenery["rock_single"].size() == int(want["rocks"]) and god.scenery["bush_round"].size() == int(want["bushes"]))
	var patch: Vector3 = want["patch"]
	_check("saved layout: the painted roads are back (round cobble patch %s, gravel track %s, plaza %s, %d tiles, grass %.2f on the patch)" % [god.road_at(patch.x, patch.z), god.road_at(14.0, 8.0), god.road_at(47.0, 0.0), god.painted_tiles(), grass.grass_at(patch.x, patch.z)],
		god.road_at(patch.x, patch.z) == "cobble" and god.road_at(patch.x + 1.6, patch.z + 1.6) == "" and god.road_at(14.0, 8.0) == "gravel" and god.road_at(47.0, 0.0) == "cobble"
		and god.painted_tiles() == int(want["tiles"]) and grass.grass_at(patch.x, patch.z) < 0.2)
	var pen: GodMode.El = god.by_key.get("pen@20.00,-1.00")
	var pen_at: Vector3 = want["pen_at"]
	var sheep_in := sheep_list.all(func(sh): return pen_rect.has_point(Vector2(sh.position.x, sh.position.z)))
	var churns: Array = god.els.filter(func(e): return e.added and e.kind == "decor_milk_churn")
	_check("saved layout: the straight gravel line, the square patch, the placed gold leaves, spruce and milk churn, and the moved sheep pen are all back (line %s, square corner %s, %d leaves, %d spruces, pen %.2f m off, sheep inside %s)" % [god.road_at(31.0, 10.0), god.road_at(33.9, 16.9), god.scenery.get("leaf_yellow", []).size(), god.scenery["tree_spruce"].size(), pen.node.global_position.distance_to(pen_at), sheep_in],
		god.road_at(31.0, 10.0) == "gravel" and god.road_at(33.9, 16.9) == "gravel" and god.scenery.get("leaf_yellow", []).size() == 2 and god.scenery["tree_spruce"].size() == int(want["spruces"])
		and churns.size() == 1 and pen.node.global_position.distance_to(pen_at) < 0.01 and pen_rect.get_center().distance_to(Vector2(pen_at.x, pen_at.z)) < 0.01 and sheep_in)
	cam_follow = false
	await _god_look(Vector3(17.0, 0, 7.0), 24.0)
	await _shot("62_god_reloaded.png")
	await _god_look(Vector3(31.0, 0, 12.0), 22.0)
	await _shot("63_god_line_and_placed.png")
	print("AUTOTEST DONE")
	get_tree().quit()


## Typed chat, all offline: the request we'd send, reading replies and errors, and the chat
## window with a stand-in for the API (ai.mock), so the test never touches the network.
func _chat_checks() -> void:
	var rosa = _villager("rosa")
	var hist: Array = []
	AiChat.push_history(hist, "assistant", "dropped") # a conversation must start with Nora
	AiChat.push_history(hist, "user", "Hi Rosa!")
	var body := ai.build_request("rosa", hist, ai.situation_text("rosa", _chat_context(rosa)))
	var sys: Array = body["system"]
	_check("chat request: %s, cached character bible + live situation, starts with Nora" % body["model"],
		body["model"] == ai.model and sys.size() == 2 and sys[0].has("cache_control") and not sys[1].has("cache_control")
		and str(sys[0]["text"]).contains("Rosa Marchetti") and str(sys[1]["text"]).contains("Day ") and hist.size() == 1 and hist[0]["role"] == "user"
		and not JSON.stringify(body).contains("x-api-key"))
	# the API rejects fields a model doesn't support, so check the request each model would get
	var keep_model: String = ai.model
	ai.model = "claude-haiku-5-5"
	var b_haiku := ai.build_request("rosa", hist, "")
	ai.model = "claude-opus-5-5"
	var b_opus := ai.build_request("rosa", hist, "")
	ai.model = keep_model
	_check("Haiku is the default and gets no fallback list; Opus keeps it; both at low effort",
		AiChat.DEFAULT_MODEL == "claude-haiku-5-5" and not b_haiku.has("fallbacks") and b_haiku.get("output_config", {}).get("effort") == "low"
		and (ai.proxy_url != "" or b_opus.has("fallbacks")) and b_opus.get("output_config", {}).get("effort") == "low")
	_check("villagers only share secrets once they trust Nora",
		not ai.situation_text("rowan", {"trust": 0, "familiarity": 5}).contains("Anna") and ai.situation_text("rowan", {"trust": 50, "familiarity": 60}).contains("Anna"))
	var long: Array = []
	for i in 30:
		AiChat.push_history(long, "user" if i % 2 == 0 else "assistant", str(i))
	_check("chat history is trimmed to the last %d lines, starting with Nora (%d)" % [AiChat.MAX_HISTORY, long.size()], long.size() <= AiChat.MAX_HISTORY and long[0]["role"] == "user")
	var good := AiChat.parse_response(200, JSON.stringify({"content": [{"type": "text", "text": "[warm] *wipes her hands* Hello, pet!"}], "stop_reason": "end_turn"}))
	_check("a reply is read: mood %s, text '%s'" % [good["mood"], good["text"]], good["ok"] and good["mood"] == "warm" and good["text"] == "*wipes her hands* Hello, pet!")
	var errs := [AiChat.parse_response(401, "{}")["error"], AiChat.parse_response(529, "{}")["error"],
		AiChat.parse_response(200, JSON.stringify({"content": [], "stop_reason": "refusal"}))["error"], AiChat.parse_response(200, JSON.stringify({"content": []}))["error"]]
	_check("API errors are told apart (%s)" % str(errs), errs == ["key", "busy", "refusal", "empty"])
	_check("chat text can't inject markup", AiChat.to_bbcode("[b]hi *nods*") == "[lb]b]hi [i][color=#d9c9a8]nods[/color][/i]")

	var clock0 := Game.time_running
	var love0 := Game.love
	var fam0 := Game.stat("rosa", "familiarity")
	ai.mock = func(_b): return {"code": 200, "body": JSON.stringify({"content": [{"type": "text", "text": "[happy] Oh, lovely to see you, love! Busy as bees today."}], "stop_reason": "end_turn"})}
	player.position = rosa.talk_spot if rosa.talk_spot != null else rosa.position + Vector3(0, 0, 1.4)
	_villager_action(rosa, "chat")
	await _wait(0.3)
	_check("the chat window opens and the clock waits", hud.is_chat_open() and not Game.time_running and rosa.listening)
	hud.chat.input.text = "Hello Rosa! How's the market today?"
	hud.chat._send()
	await _wait(0.4)
	var msgs: Array = Game.chat("rosa")["msgs"]
	_check("Rosa answers in the chat (love %.0f→%.0f, familiarity %d→%d)" % [love0, Game.love, fam0, Game.stat("rosa", "familiarity")],
		hud.chat.transcript().contains("lovely to see you") and msgs.size() >= 2 and msgs[-1]["role"] == "assistant"
		and str(ai.last_request["messages"][-1]["content"]).contains("market") and Game.love > love0 and Game.stat("rosa", "familiarity") > fam0)
	var cam0 := cam_target
	await _shot("07_chat.png")
	ai.mock = func(_b): return {"code": 529, "body": "{}"}
	hud.chat.input.text = "Are you busy?"
	hud.chat._send()
	await _wait(0.4)
	msgs = Game.chat("rosa")["msgs"]
	_check("when the API is busy, the line comes back to the box and history stays in turns (last=%s, box='%s', note='%s', camera moved %.2f)" % [msgs[-1]["role"], hud.chat.input.text, hud.chat.note.text, cam_target.distance_to(cam0)],
		msgs[-1]["role"] == "assistant" and hud.chat.input.text == "Are you busy?" and hud.chat.note.text.contains("busy") and cam_target.distance_to(cam0) < 0.01)
	var saved := Game.to_dict()
	_check("the chat is saved with the game, and no API key is", (saved["chats"]["rosa"]["msgs"] as Array).size() >= 2 and not JSON.stringify(saved).contains("sk-ant"))
	close_chat()
	_check("closing the chat starts the clock again", not hud.is_chat_open() and Game.time_running == clock0 and not rosa.listening)
	ai.mock = Callable()


func _character_checks() -> void:
	_check("heroine model loaded (%s, %d bones)" % [player.body.id, player.body.bone_names().size()], player.detailed and player.body.id == Data.player_character())
	var cd0 := cam_dist
	cam_target = player.position
	cam_dist = 5.0
	await _wait(1.6)
	await _shot("02a_heroine_closeup.png")
	var home := player.position
	autotest_jog = false
	player.running = false # now, not on main's next frame: a slow frame here would start her off jogging
	player.walk(_find_path(player.position, home + Vector3(2.5, 0, 0)))
	await _wait(0.45)
	_check("heroine walks briskly, the Walk stride matching her speed (%s at %.1f m/s, %.2fx)" % [player.body.current(), player.speed, player.body.anim.speed_scale],
		player.body.current() == "Walk" and player.speed > 1.4 and player.speed < 2.0 and absf(player.body.anim.speed_scale * player.body.walk_anim_speed - player.speed) < 0.15)
	autotest_jog = true
	player.running = true
	await _wait(0.4)
	_check("holding Shift she jogs, with the stride matching her speed (%s at %.1f m/s, %.2fx)" % [player.body.current(), player.speed, player.body.anim.speed_scale],
		player.body.current() == "Run" and player.speed > 2.5 and absf(player.body.anim.speed_scale - 1.0) < 0.3)
	cam_target = player.position
	await _shot("02b_heroine_walk.png")
	await _wait(1.0)
	player.walk(_find_path(player.position, home))
	await _wait(1.5)
	# Rowan wears the same skeleton and plays the same loops as the heroine
	var rowan := _villager("rowan")
	var rb = rowan.body if rowan else null
	var same_bones: bool = rb != null and rb.bone_names() == player.body.bone_names() and rb.bone_names().size() == 22
	_check("Rowan is in Maplewood on the heroine's skeleton (%d bones, same names=%s)" % [rb.bone_names().size() if rb else 0, same_bones], same_bones)
	var shared := 0
	if rb:
		for n in player.body.ANIMS:
			var a: Animation = player.body.anim.get_animation(n)
			var b: Animation = rb.anim.get_animation(n)
			if a and b and _anim_bones(a) == _anim_bones(b) and absf(a.length - b.length) < 0.001:
				shared += 1
	_check("Rowan and the heroine share all %d animation loops (%d match)" % [player.body.ANIMS.size(), shared], shared == player.body.ANIMS.size())
	if rowan:
		rowan.face_point(rowan.position + Vector3(0, 0, 2), 2.5)
		var follow0 := cam_follow
		cam_follow = false
		cam_target = rowan.position + Vector3(0, 0.9, 0)
		cam_dist = 5.0
		await _wait(1.2)
		_check("Rowan gestures while talking (%s)" % rb.current(), rb.current() == "Talk")
		await _shot("02d_rowan.png")
		rowan.hold_time = 0.0
		cam_follow = follow0
		# the procedural rig turns her head toward someone standing beside her
		var r_pos := rowan.position
		var r_rot := rowan.rotation.y
		player.rotation.y = 0.0
		rowan.position = player.position + Vector3(1.6, 0, 0.5)
		rowan.hold_time = 3.0
		await _wait(1.6)
		var sk: Skeleton3D = player.body.skeleton
		var hb := sk.find_bone("Head")
		# modifiers pose the bones only for drawing, then Godot puts the animated pose back, so read
		# the head right after the skeleton updates
		var hz := [Vector3.ZERO]
		sk.skeleton_updated.connect(func(): hz[0] = sk.get_bone_global_pose(hb).basis * (player.body.rig._fwd_rest["Head"] as Vector3), CONNECT_ONE_SHOT)
		await _wait(0.1)
		var head_fwd: Vector3 = sk.global_transform.basis * (hz[0] as Vector3)
		var to_r := rowan.position - player.position
		var a_body := rad_to_deg(Vector2(0, 1).angle_to(Vector2(to_r.x, to_r.z)))
		var a_head := rad_to_deg(Vector2(head_fwd.x, head_fwd.z).angle_to(Vector2(to_r.x, to_r.z)))
		_check("she turns her head toward Rowan beside her (body %.0f° off, head %.0f° off)" % [absf(a_body), absf(a_head)], absf(a_head) < absf(a_body) - 25.0)
		cam_target = player.position + Vector3(0.6, 0.9, 0.2)
		cam_dist = 5.0
		await _wait(0.3)
		await _shot("02e_look_at.png")
		rowan.position = r_pos
		rowan.rotation.y = r_rot
		rowan.hold_time = 0.0
	cam_target = player.position
	cam_dist = cd0


## Napping in the bed: she lies on her back with her head on the pillows under the quilt, the bed's
## cushion and folded blanket are put away meanwhile, and everything is back when she gets up.
func _bed_checks() -> void:
	var beds = furniture.filter(func(f): return f.item_id == "bed")
	if beds.is_empty():
		_check("there is a bed to nap in", false)
		return
	var bed: Furniture = beds[0]
	var tidy := bed.find_child("tidy", true, false) as Node3D
	var tidy_seen: bool = tidy != null and tidy.visible
	_perform(bed, "nap")
	await _wait(1.2)
	var sk: Skeleton3D = player.body.skeleton
	var head: Vector3 = bed.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
	var feet: Vector3 = bed.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin)
	var cover := bed.get_node_or_null("LieCover") as Node3D
	await _shot("44_nap_in_bed.png")
	_check("napping, she lies in the bed on her back with her head on the pillows (head %.2f, %.2f; feet %.2f, %.2f)" % [head.y, head.z, feet.y, feet.z],
		player.is_lying() and head.z < -0.55 and head.y > 0.78 and head.y < 1.0 and feet.z > 0.4 and feet.z < 0.95 and absf(head.x) < 0.3)
	var cloth := cover.get_node_or_null("Cloth") as MeshInstance3D if cover != null else null
	var bulge: float = cloth.mesh.get_aabb().end.y if cloth != null and cloth.mesh != null else 0.0
	_check("the quilt lies over her in her shape and the cushion and folded blanket are put away (cover %s, highest point %.2f m, tidy %s)" % [cover != null and cover.visible, bulge, tidy != null and tidy.visible],
		tidy_seen and cover != null and cover.visible and bulge > 0.85 and bulge < 1.15 and tidy != null and not tidy.visible)
	player.cancel_activity()
	await _wait(0.3)
	_check("getting up brings the blanket back and she stands again (lying %s, tidy %s, cover %s)" % [player.is_lying(), tidy != null and tidy.visible, cover != null and cover.visible],
		not player.is_lying() and tidy != null and tidy.visible and cover != null and not cover.visible)


## Bones an animation moves, by name (track paths also carry the character's own node name).
func _anim_bones(a: Animation) -> Array:
	var out := []
	for i in a.get_track_count():
		out.append(str(a.track_get_path(i).get_concatenated_subnames()) + ":" + str(a.track_get_type(i)))
	out.sort()
	return out


func _key_tap(kc: Key, hold := 0.0) -> void:
	var ev := InputEventKey.new()
	ev.keycode = kc
	ev.physical_keycode = kc
	ev.pressed = true
	ev.set_meta("ke_test", true) # _input ignores every other key during the autotest
	Input.parse_input_event(ev)
	await _wait(maxf(hold, 0.05))
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	up.set_meta("ke_test", true)
	Input.parse_input_event(up)
	await get_tree().process_frame


func _camera_checks() -> void:
	# lock button starts locked and follows the heroine
	_set_cam_lock(true)
	_check("camera starts locked, lock icon closed", cam_follow and hud.cam_locked and hud.lock_btn.button_pressed)
	# a real key event for W must pan and unlock (even with the help panel open)
	hud.help_panel.visible = true
	var t0 := cam_target
	await _key_tap(KEY_W, 0.6)
	hud.help_panel.visible = false
	_check("W key pans the camera (moved %.1fm) and unlocks it" % t0.distance_to(cam_target), t0.distance_to(cam_target) > 3.0 and not cam_follow and not hud.cam_locked)
	# Q key goes through the event handler (proves keys aren't swallowed by the UI)
	var y0 := cam_yaw_goal
	await _key_tap(KEY_Q)
	_check("Q key rotates the camera", absf(cam_yaw_goal - y0 + PI * 0.5) < 0.01)
	await _key_tap(KEY_E)
	# clicking to walk no longer snaps the camera back while unlocked
	var t1 := cam_target
	_live_click(cam.unproject_position(player.position + Vector3(1.5, 0, 0)))
	await _wait(0.6)
	_check("walking keeps the camera unlocked", not cam_follow and t1.distance_to(cam_target) < 0.01)
	# on-screen arrow pad pans
	hud.cam_pad_pan = Vector2(1, 0)
	await _wait(0.5)
	hud.cam_pad_pan = Vector2.ZERO
	_check("on-screen arrow pans (moved %.1fm)" % t1.distance_to(cam_target), t1.distance_to(cam_target) > 3.0)
	# trackpad two-finger swipe and pinch
	var t2 := cam_target
	for i in 10:
		var pg := InputEventPanGesture.new()
		pg.delta = Vector2(0, 0.5)
		pg.position = Vector2(800, 450)
		Input.parse_input_event(pg)
		await get_tree().process_frame
	_check("trackpad swipe pans once per event (moved %.1fm)" % t2.distance_to(cam_target), absf(t2.distance_to(cam_target) - 10 * 0.5 * 0.6 * cam_dist / 23.0) < 0.2)
	var d0 := cam_dist
	var mg := InputEventMagnifyGesture.new()
	mg.factor = 1.5
	mg.position = Vector2(800, 450)
	Input.parse_input_event(mg)
	await get_tree().process_frame
	_check("trackpad pinch zooms once (%.1f→%.1f)" % [d0, cam_dist], absf(cam_dist - d0 / 1.5) < 0.1)
	cam_dist = d0
	await _shot("07_camera_unlocked.png")
	# clicking the lock button re-locks and flies back to the heroine
	hud.lock_btn.button_pressed = true
	await _wait(1.5)
	_check("lock button re-locks onto the heroine (%.1fm away)" % Vector2(cam_target.x - player.position.x, cam_target.z - player.position.z).length(), cam_follow and hud.cam_locked and Vector2(cam_target.x - player.position.x, cam_target.z - player.position.z).length() < 1.0)
	await _shot("08_camera_locked.png")


# --- Maplewood: town decor, villagers, market, cottage ----------------------------------------

func _build_town_decor() -> void:
	for p in [Vector3(46.0, 0, -5.4), Vector3(60.0, 0, -5.4), Vector3(46.0, 0, 4.6), Vector3(60.0, 0, 4.6), Vector3(37.5, 0, 4.2), Vector3(57.0, 0, 13.0)]:
		_decor("lantern", p, 0)
	for b in [[Vector3(53.0, 0, 2.0), 2], [Vector3(53.0, 0, -4.0), 0], [Vector3(49.5, 0, -1.0), 1]]:
		_decor(Catalog.world_bench(b[0].x, b[0].z), b[0], b[1]) # one bench in five is the short one
	for p in [Vector3(55.0, 0, -8.3), Vector3(58.2, 0, -8.3), Vector3(62.3, 0, -7.9), Vector3(44.9, 0, -7.9)]:
		_decor("flower_pot", p, 0)
	_decor("sunflowers", Vector3(45.2, 0, -12.0), 0)
	_decor("hay_bale", Vector3(51.6, 0, -8.6), 0)


func _decor(id: String, pos: Vector3, r: int) -> void:
	var f: Furniture = Furniture.new()
	decor_root.add_child(f)
	f.setup(id, r)
	f.position = pos
	decor.append(f)
	if not f.is_flat():
		grid_blockers.append(f.footprint())


func _add_sheep() -> void:
	var s = Sheep.new()
	s.pen = Rect2(pen_rect.position + Vector2(0.7, 0.7), pen_rect.size - Vector2(1.4, 1.4))
	var i := sheep_list.size()
	s.position = Vector3(pen_rect.position.x + 1.5 + (i % 3) * 1.5, 0, pen_rect.position.y + 1.5 + (i % 3) * 0.6 + (i / 3) * 1.8)
	add_child(s)
	sheep_list.append(s)


# --- story staging -----------------------------------------------------------------
# Scenes (data/scenes/*.scene) drive these through story_player.gd. What must survive a save
# (goal, weather, where a villager stands) lives in Game.flags.

func _setup_story_staging() -> void:
	var d := Data.load_json("areas")
	for k in d.get("areas", {}):
		var a: Array = d["areas"][k]
		areas[k] = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	goal_marker = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.38, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.68
	ring.mesh = tm
	ring.material_override = mat
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.05
	goal_marker.add_child(ring)
	var gem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.0
	cm.height = 0.45
	cm.radial_segments = 4
	cm.rings = 1
	gem.mesh = cm
	gem.material_override = mat
	gem.name = "Gem"
	gem.position.y = 2.4
	goal_marker.add_child(gem)
	goal_marker.visible = false
	add_child(goal_marker)
	rain_fx = CPUParticles3D.new()
	rain_fx.amount = 2200
	rain_fx.lifetime = 0.9
	rain_fx.local_coords = false
	rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_fx.emission_box_extents = Vector3(16, 0.5, 16)
	rain_fx.direction = Vector3(0.12, -1, 0.05)
	rain_fx.spread = 2.0
	rain_fx.initial_velocity_min = 15.0
	rain_fx.initial_velocity_max = 18.0
	rain_fx.gravity = Vector3(0, -6, 0)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.014, 0.5, 0.014)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.82, 0.87, 0.95, 0.32)
	drop.material = dm
	rain_fx.mesh = drop
	rain_fx.emitting = false
	add_child(rain_fx)


## After a load (or a fresh start): goal, weather and villagers a scene moved.
func _restore_story_state() -> void:
	_show_goal()
	rain = 1.0 if str(Game.flag("weather", "clear")) == "rain" else 0.0
	for v in villagers:
		var h = Game.flag("home_" + v.vid, null)
		if h is Array and h.size() >= 2:
			v.settle_at(Vector3(float(h[0]), 0, float(h[1])))


## A new game opens on Act 1, if a scene has "@trigger start"; otherwise on the help card.
func _begin_new_story() -> void:
	if Story.find_trigger("start") == "":
		hud.help_panel.visible = true
		return
	story.trigger("start")


func _update_story_staging(delta: float) -> void:
	var raining := str(Game.flag("weather", "clear")) == "rain"
	rain = move_toward(rain, 1.0 if raining else 0.0, delta * 0.5)
	Furniture.gloom = rain
	var indoors := interior_rect().has_point(Vector2(cam_target.x, cam_target.z)) and cam_dist < 16.0
	rain_fx.emitting = raining and not indoors
	rain_fx.position = cam_target + Vector3(0, 13, 0)
	if goal_marker.visible:
		var gem := goal_marker.get_node("Gem") as Node3D
		gem.position.y = 2.4 + 0.18 * sin(Time.get_ticks_msec() * 0.003)
		gem.rotation.y += delta * 1.6
	_area_t += delta
	if _area_t < 0.25 or story.is_playing() or sleeping or mode != Mode.LIVE:
		return
	_area_t = 0.0
	var p := Vector2(player.position.x, player.position.z)
	for k in areas:
		if (areas[k] as Rect2).has_point(p) and story.trigger("area", k) != "":
			return


## Where the heroine is, by area name ("" if none).
func area_at(p: Vector3) -> String:
	for k in areas:
		if (areas[k] as Rect2).has_point(Vector2(p.x, p.z)):
			return k
	return ""


func set_goal(text: String, pos = null) -> void:
	if text == "":
		Game.flags.erase("goal")
		Game.flags.erase("goal_pos")
	else:
		Game.set_flag("goal", text)
		if pos is Vector2:
			Game.set_flag("goal_pos", [pos.x, pos.y])
		else:
			Game.flags.erase("goal_pos")
	_show_goal()


func _show_goal() -> void:
	var text := str(Game.flag("goal", ""))
	hud.set_goal(text if text != "false" else "")
	var gp = Game.flag("goal_pos", null)
	goal_marker.visible = text != "" and text != "false" and gp is Array
	if goal_marker.visible:
		goal_marker.position = Vector3(float(gp[0]), 0, float(gp[1]))


func set_weather(kind: String) -> void:
	Game.set_flag("weather", kind)


func shake(secs: float) -> void:
	_shake_t = secs
	_shake_len = secs


## Builds a story prop: "bus", "suitcase", "rail" (a broken fence board), "letter", "lantern" (lit) or "rock" (big enough for two to sit on).
func spawn_prop(kind: String, prop_name: String, p: Vector3, yaw_deg := 0.0) -> void:
	remove_prop(prop_name)
	var n := Node3D.new()
	n.position = p
	n.rotation.y = deg_to_rad(yaw_deg)
	match kind:
		"bus":
			# The Maplewood bus (art/world_assets/maplewood_bus): front +X, doors on the +Z side.
			if Catalog.model("res://assets/props/maplewood_bus.glb", n) == null:
				_box_bus(n)
		"suitcase":
			Catalog.box(n, Vector3(0.52, 0.64, 0.22), Vector3(0, 0.36, 0), Color(0.55, 0.25, 0.2))
			Catalog.box(n, Vector3(0.54, 0.05, 0.24), Vector3(0, 0.5, 0), Color(0.35, 0.18, 0.14))
			Catalog.box(n, Vector3(0.18, 0.05, 0.05), Vector3(0, 0.72, 0), Color(0.2, 0.15, 0.12))
			for x in [-0.2, 0.2]:
				Catalog.cyl(n, 0.035, 0.035, 0.04, Vector3(x, 0.03, 0.08), Color(0.1, 0.1, 0.1))
		"rail":
			Catalog.box(n, Vector3(2.0, 0.07, 0.05), Vector3(0, 0.2, 0), Color(0.62, 0.48, 0.32), Vector3(0, 0, 14))
		"letter":
			Catalog.box(n, Vector3(0.22, 0.01, 0.15), Vector3(0, 0.01, 0), Color(0.96, 0.93, 0.85))
		"lantern":
			Catalog.cyl(n, 0.1, 0.11, 0.03, Vector3(0, 0.015, 0), Color(0.24, 0.23, 0.22))
			Catalog.glow(Catalog.cyl(n, 0.075, 0.075, 0.2, Vector3(0, 0.13, 0), Color(1.0, 0.86, 0.55)), Color(1.0, 0.8, 0.5), 2.2)
			for a in 4:
				var q := Vector3(cos(a * PI / 2) * 0.085, 0.13, sin(a * PI / 2) * 0.085)
				Catalog.box(n, Vector3(0.02, 0.22, 0.02), q, Color(0.24, 0.23, 0.22))
			Catalog.cyl(n, 0.04, 0.1, 0.06, Vector3(0, 0.26, 0), Color(0.24, 0.23, 0.22))
			Catalog.ring(n, 0.05, 0.065, Vector3(0, 0.32, 0), Color(0.24, 0.23, 0.22))
			Catalog.omni(n, Vector3(0, 0.2, 0), Color(1.0, 0.75, 0.45), 4.0, 0.2, 1.4)
		"rock":
			var stone := Color("57534c") # a shade under palette stone_dark: low sun washes it out
			Catalog.ball(n, 0.85, Vector3(0, 0.12, 0), stone, Vector3(1.05, 0.45, 0.6))
			Catalog.ball(n, 0.42, Vector3(0.75, 0.08, -0.3), Color("918c82"), Vector3(1.0, 0.7, 0.9))
			Catalog.ball(n, 0.5, Vector3(-0.2, 0.42, -0.25), Color("46653f"), Vector3(1.1, 0.22, 0.6)) # moss on top
		_:
			Catalog.box(n, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), Color(0.8, 0.3, 0.8))
	add_child(n)
	props[prop_name] = n


## The old box bus, used only if the bus model is missing.
func _box_bus(n: Node3D) -> void:
	var paint := Color(0.36, 0.55, 0.52)
	var cream := Color(0.93, 0.88, 0.76)
	Catalog.box(n, Vector3(6.4, 1.1, 2.3), Vector3(0, 0.95, 0), paint)
	Catalog.box(n, Vector3(6.4, 0.9, 2.3), Vector3(0, 1.95, 0), cream)
	Catalog.box(n, Vector3(6.3, 0.12, 2.2), Vector3(0, 2.46, 0), paint.darkened(0.2))
	for i in 6:
		Catalog.box(n, Vector3(0.78, 0.6, 2.34), Vector3(-2.4 + i * 0.92, 1.98, 0), Color(0.2, 0.26, 0.32))
	Catalog.box(n, Vector3(0.06, 0.8, 2.0), Vector3(3.21, 1.9, 0), Color(0.2, 0.26, 0.32))
	for z in [-1.16, 1.16]:
		for x in [-2.1, 2.1]:
			Catalog.cyl(n, 0.42, 0.42, 0.28, Vector3(x, 0.42, z), Color(0.12, 0.12, 0.13), Vector3(90, 0, 0))
	for z in [-0.75, 0.75]:
		var lamp := Catalog.ball(n, 0.13, Vector3(3.22, 0.85, z), Color(1.0, 0.92, 0.6))
		lamp.material_override = Catalog.mat(Color(1.0, 0.9, 0.6), 0.5, 2.5)


func move_prop(prop_name: String, p: Vector3, secs: float) -> void:
	var n = props.get(prop_name)
	if n and is_instance_valid(n):
		create_tween().tween_property(n, "position", p, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func remove_prop(prop_name: String) -> void:
	var n = props.get(prop_name)
	if n and is_instance_valid(n):
		n.queue_free()
	props.erase(prop_name)


## "out": the first three sheep slip the pen and mill about by the south fence. "home": back in.
func sheep_out(out: bool) -> void:
	var inside := Rect2(pen_rect.position + Vector2(0.7, 0.7), pen_rect.size - Vector2(1.4, 1.4))
	var loose := Rect2(10.9, -1.3, 4.0, 3.0) # the vegetable beds
	for i in mini(3, sheep_list.size()):
		var s = sheep_list[i]
		s.pen = loose if out else inside
		s.position = Vector3(loose.position.x + 1.2 + i * 2.1, 0, loose.position.y + 0.6 + (i % 2) * 1.4) if out else Vector3(pen_rect.position.x + 1.5 + i * 1.5, 0, pen_rect.position.y + 1.5 + i * 0.6)
		s._pick_target()


## A villager stands somewhere else until told otherwise ("off" = back to their usual spot).
func set_home(vid: String, p = null) -> void:
	var v := _villager(vid)
	if v == null:
		return
	if p is Vector3:
		Game.set_flag("home_" + vid, [p.x, p.z])
		v.settle_at(p)
	else:
		Game.flags.erase("home_" + vid)
		for d in _villager_defs():
			if d["id"] == vid:
				v.settle_at(d["pos"])
				v.roam = d["roam"]


## Who lives in Maplewood: res://data/villagers.json.
func _villager_defs() -> Array:
	return Data.villagers()


func _villager(id: String) -> Villager:
	for v in villagers:
		if v.vid == id:
			return v
	return null


func _rosa_price() -> int:
	return int(round(Game.market_price("sweater") * (1.0 + 0.04 * Game.hearts("rosa"))))


func _crop_value() -> int:
	return Game.count("turnip") * Game.market_price("turnip") + Game.count("pumpkin") * Game.market_price("pumpkin")


func _theo_price(base: int) -> int:
	return int(round(base * (1.0 - 0.05 * Game.hearts("theo"))))


func _cottage_price() -> int:
	return int(round(Game.COTTAGE_PRICE * (1.0 - 0.04 * Game.hearts("mabel"))))


func _update_price_board() -> void:
	if price_board:
		price_board.text = "TODAY'S PRICES\nSweater   %dc\nPumpkin   %dc\nTurnip     %dc" % [_rosa_price(), Game.market_price("pumpkin"), Game.market_price("turnip")]


func _villager_actions(v) -> Array:
	var acts := [_act("talk", "Talk")]
	if ai.has_persona(v.vid):
		acts.append(_act("chat", "Chat..."))
	match v.vid:
		"rosa":
			var sw := Game.count("sweater")
			acts.append(_act("sell_sweater", "Sell sweaters  (%d × %dc)" % [sw, _rosa_price()], sw > 0))
			var crops := _crop_value()
			acts.append(_act("sell_crops", "Sell crops  (%dc)" % crops, crops > 0))
		"theo":
			var wp := _theo_price(Game.WOOL_PACK_PRICE)
			acts.append(_act("buy_wool", "Buy 3 wool  (%dc)" % wp, Game.coins >= wp))
			if Game.sheep_count < Game.MAX_SHEEP:
				var sp := _theo_price(Game.SHEEP_PRICE)
				acts.append(_act("buy_sheep", "Buy a sheep  (%dc · you have %d)" % [sp, Game.sheep_count], Game.coins >= sp))
			else:
				acts.append(_act("noop", "Your pen is full (%d sheep)" % Game.MAX_SHEEP, false))
		"mabel":
			if Game.owns_cottage:
				acts.append(_act("noop", "Rosewood Cottage rent: %dc a day" % _cottage_rent(), false))
			else:
				var cp := _cottage_price()
				acts.append(_act("buy_cottage", "Buy Rosewood Cottage  (%dc)" % cp, Game.coins >= cp))
	if int(Game.friend(v.vid)["gift"]) == Game.day:
		acts.append(_act("noop", "Already gave a gift today", false))
	else:
		for item in ["sweater", "pumpkin", "turnip"]:
			if Game.count(item) > 0:
				var gift := _act("gift_" + item, "A %s" % item)
				gift["group"] = "Give a gift"
				acts.append(gift)
	return acts


func _say(v, text: String) -> void:
	hud.show_dialogue(v.title, Game.hearts(v.vid), text)


func _talk_line(v) -> String:
	var f := Game.friend(v.vid)
	var vars := {"sweater": _rosa_price(), "cottage": _cottage_price(), "rent": _cottage_rent()}
	if int(f["n"]) == 0:
		return str(Dialogue.INTRO[v.vid]).format(vars)
	var h := Game.hearts(v.vid)
	var tier := 0 if h < 2 else (1 if h < 4 else 2)
	var lines: Array = Dialogue.LINES[v.vid][tier]
	return str(lines[(int(f["n"]) + Game.day) % lines.size()]).format(vars)


func _villager_action(v, id: String) -> void:
	var f := Game.friend(v.vid)
	match id:
		"talk":
			var scene_id := Story.find_trigger("talk", v.vid)
			var line := "" if scene_id != "" else _talk_line(v)
			f["n"] = int(f["n"]) + 1
			if int(f["talk"]) != Game.day:
				f["talk"] = Game.day
				Game.add_friendship(v.vid, 8)
				Game.add_need("love", 6.0)
				Game.add_need("happiness", 2.0)
			if scene_id != "":
				v.face_point(player.position, 3.0)
				player.face_point(v.position)
				story.play(scene_id)
			else:
				_say(v, line)
		"chat":
			open_chat(v)
		"sell_sweater":
			var n := Game.count("sweater")
			var price := _rosa_price()
			if n > 0 and Game.take_item("sweater", n):
				Game.coins += n * price
				var praise: Array = ["Oh, these are gorgeous!", "Lovely work, as always.", "The city folks will snap these up!"]
				_say(v, "%s Here's %dc for %d sweater%s." % [praise[Game.day % 3], n * price, n, "s" if n > 1 else ""])
				hud.show_toast("Sold %d sweater%s for %dc!" % [n, "s" if n > 1 else "", n * price])
		"sell_crops":
			var value := _crop_value()
			if value > 0:
				Game.take_item("turnip", Game.count("turnip"))
				Game.take_item("pumpkin", Game.count("pumpkin"))
				Game.coins += value
				_say(v, "Fresh from Birchfield! %dc it is." % value)
				hud.show_toast("Sold your crops for %dc!" % value)
		"buy_wool":
			if Game.spend(_theo_price(Game.WOOL_PACK_PRICE)):
				Game.add_item("wool", 3)
				_say(v, "Three bundles of my finest. Enough for one sweater. Happy knitting!")
		"buy_sheep":
			if Game.sheep_count < Game.MAX_SHEEP and Game.spend(_theo_price(Game.SHEEP_PRICE)):
				var sheep_name: String = Dialogue.NEW_SHEEP[(Game.sheep_count - Game.START_SHEEP) % Dialogue.NEW_SHEEP.size()]
				Game.sheep_count += 1
				_add_sheep()
				_say(v, "Her name is %s. I walked her over to your pen myself. Be nice to her!" % sheep_name)
				hud.show_toast("%s the sheep joined your flock! (%d sheep)" % [sheep_name, Game.sheep_count])
		"buy_cottage":
			if not Game.owns_cottage and Game.spend(_cottage_price()):
				Game.owns_cottage = true
				_rebuild_house()
				_rebuild_grid()
				_say(v, "Congratulations, homeowner! Here are the keys to Rosewood Cottage. Furnish it in Build mode: the cozier it is, the more rent it brings in every morning.")
				hud.show_toast("You bought Rosewood Cottage!")
		_:
			if id.begins_with("gift_"):
				var item := id.substr(5)
				if int(f["gift"]) == Game.day or not Game.take_item(item):
					return
				f["gift"] = Game.day
				Game.add_need("love", 8.0)
				var loved: bool = item == v.loves
				var liked: bool = item in v.likes
				Game.add_friendship(v.vid, 25 if loved else (16 if liked else 10))
				if loved or liked:
					Game.add_stat(v.vid, "trust", 2 if loved else 1)
				if v.romance and Game.hearts(v.vid) >= 2 and (loved or liked):
					Game.add_stat(v.vid, "romance", 2 if loved else 1)
				# a first-time gift can have its own scene ("@trigger gift rowan sweater")
				var gift_scene := Story.find_trigger("gift", v.vid, item)
				if gift_scene != "":
					v.face_point(player.position, 3.0)
					player.face_point(v.position)
					story.play(gift_scene)
				elif loved:
					_say(v, Dialogue.GIFT_LOVED[v.vid])
				else:
					_say(v, str(Dialogue.GIFT_LINES.get(v.vid, {}).get(item, "Oh, a %s! That's very thoughtful of you. Thank you." % item)))
	_update_price_board()


# --- typed chat (ai_chat.gd, chat_panel.gd) -------------------------------------------

func open_chat(v) -> void:
	if hud.is_chat_open():
		close_chat()
	chat_v = v
	hud.hide_menu()
	hud.hide_dialogue()
	_chat_clock_was = Game.time_running
	Game.time_running = false # like a story scene, the day waits while you talk
	v.listening = true
	v.face_point(player.position, 2.0)
	player.face_point(v.position)
	var c := Game.chat(v.vid)
	hud.chat.open(v.title, Game.hearts(v.vid), c["msgs"], ai.available())


func close_chat() -> void:
	if chat_v == null:
		return
	chat_v.listening = false
	chat_v.hold_time = 2.0
	chat_v = null
	Game.time_running = _chat_clock_was
	hud.chat.visible = false


func _update_chat() -> void:
	if chat_v == null:
		return
	if story.is_playing() or sleeping or player.position.distance_to(chat_v.position) > 4.0:
		close_chat()
		return
	chat_v.face_point(player.position, 2.0)


func _chat_send(text: String) -> void:
	if chat_v == null or ai.busy:
		return
	text = text.substr(0, AiChat.MAX_INPUT)
	var v = chat_v
	var c := Game.chat(v.vid)
	AiChat.push_history(c["msgs"], "user", text)
	hud.chat.add_line("user", text)
	player.talk(1.5)
	if not ai.available() and not ai.mock.is_valid():
		_chat_reaction(v, "*smiles* " + ai.offline_line(v.vid), "neutral", false)
		c["msgs"].pop_back() # nothing was really said back; don't keep it
		return
	hud.chat.set_thinking(true)
	hud.chat.show_note("")
	ai.send(v.vid, c["msgs"], ai.situation_text(v.vid, _chat_context(v)))


func _on_chat_reply(vid: String, r: Dictionary) -> void:
	hud.chat.set_thinking(false)
	var c := Game.chat(vid)
	var v = chat_v if chat_v != null and chat_v.vid == vid else null
	if not r["ok"]:
		# the line Nora typed wasn't answered: take it back out so the history stays in turns
		if c["msgs"].size() > 0 and c["msgs"][-1]["role"] == "user":
			var t: String = c["msgs"].pop_back()["content"]
			if v != null and hud.chat.input.text == "":
				hud.chat.input.text = t
		if r["error"] == "refusal":
			if v != null:
				_chat_reaction(v, "*shifts a little* Let's talk about something else, eh?", "neutral", false)
		else:
			hud.chat.set_online(ai.available() and r["error"] != "key")
			hud.chat.show_note(AiChat.error_note(r["error"]))
		return
	AiChat.push_history(c["msgs"], "assistant", str(r.get("raw", r["text"])))
	if v == null:
		return
	_chat_reaction(v, str(r["text"]), str(r["mood"]), true)
	if int(c["day"]) != Game.day:
		# the first real chat of the day: time with people fills Love, and you get to know them
		c["day"] = Game.day
		Game.add_need("love", 4.0)
		Game.add_need("happiness", 1.0)
		Game.add_friendship(vid, 3)
		hud.chat.set_hearts(Game.hearts(vid))


func _chat_reaction(v, text: String, mood: String, keep: bool) -> void:
	if keep:
		hud.chat.add_line("assistant", text, mood)
	else:
		hud.chat.add_line("assistant", text)
	v.speak_time = clampf(text.length() * 0.05, 1.2, 5.0)


## What the villager knows about this moment, for the prompt (ai_chat.gd situation_text).
func _chat_context(v) -> Dictionary:
	var f := Game.friend(v.vid)
	var place := {"rosa": "your market stall on the plaza", "theo": "Woolly Goods, your shop", "mabel": "the Land Office"}
	var where: String = place.get(v.vid, "")
	if where == "":
		where = "Maplewood, near the plaza" if v.position.x > 30.0 else "Birchfield Farm, Nora's place"
	var weather := "raining" if rain > 0.5 else "dry"
	var h := Game.hour
	var part := "early morning" if h < 9.0 else ("morning" if h < 12.0 else ("afternoon" if h < 17.0 else ("evening" if h < 21.0 else "late at night")))
	var facts: Array = []
	match v.vid:
		"rowan":
			if Game.flag("nora_opened"):
				facts.append("When the gate slammed she flinched hard, then said: 'Sorry. Loud noises. Long story.' You didn't push.")
			elif Game.flag("nora_deflected"):
				facts.append("When the gate slammed she flinched hard and said she was fine, it just made her jump. It was more than that.")
			if Game.flag("act1_done"):
				facts.append("You owe her a fixed fence; she owes you tea.")
		"mabel":
			if Game.flag("asked_about_gran"):
				facts.append("Nora asked you whether it was bad at the end for Ellie. You told her it was peaceful.")
		"rosa":
			facts.append("Today you're paying %dc a sweater." % _rosa_price())
		"theo":
			facts.append("Today a bundle of 3 wool costs %dc and a sheep %dc." % [_theo_price(Game.WOOL_PACK_PRICE), _theo_price(Game.SHEEP_PRICE)])
	if int(f["gift"]) == Game.day:
		facts.append("Nora already gave you a gift today.")
	if Game.knit_xp > 0:
		facts.append("Nora has knitted %d sweater%s so far." % [Game.knit_xp, "" if Game.knit_xp == 1 else "s"])
	var looks: Array = []
	if Game.warmth < 35.0:
		looks.append("cold" + (", still in that thin city coat" if Game.worn_quality <= 1 else ""))
	elif Game.worn_quality >= 3:
		looks.append("cosy in a good hand-knit sweater")
	if Game.energy < 30.0:
		looks.append("tired")
	if Game.fullness < 30.0:
		looks.append("hungry")
	if Game.happiness > 75.0:
		looks.append("in good spirits")
	elif Game.happiness < 30.0:
		looks.append("low")
	var ctx := {
		"day": Game.day, "day_of_season": Game.day_of_season(), "season": Game.season_name(), "clock": "%s (%s)" % [part, Game.clock_text()],
		"weather": weather, "place": where,
		"familiarity": int(f["familiarity"]), "trust": int(f["trust"]), "romance": int(f["romance"]),
		"facts": facts, "last_day": int(Game.chat(v.vid)["day"]),
	}
	if looks.size() > 0:
		ctx["nora"] = ", ".join(looks)
	return ctx


func cottage_interior() -> Rect2:
	var c := Town.COTTAGE
	return Rect2(c.position.x + 0.1, c.position.y + 0.1, c.size.x - 0.2, c.size.y - 0.2)


func cottage_house_rect() -> Rect2:
	return Town.COTTAGE.grow(WALL_T * 0.5)


## Rent paid every morning: a base amount plus more for every piece of furniture.
func _cottage_rent() -> int:
	if not Game.owns_cottage:
		return 0
	var inside := 0
	var yard := 0
	for f in furniture:
		var r: Rect2 = f.footprint()
		if cottage_interior().encloses(r):
			inside += 1
		elif Town.COTTAGE_LOT.encloses(r):
			yard += 1
	return mini(450, 80 + 25 * inside + 10 * yard)


func _build_cottage() -> void:
	var c := Town.COTTAGE
	var x0 := c.position.x
	var x1 := c.end.x
	var z0 := c.position.y
	var z1 := c.end.y
	var dz := Town.COTTAGE_DOOR
	Catalog.box(house_root, Vector3(c.size.x + 0.7, 0.1, c.size.y + 0.7), Vector3(c.get_center().x, -0.04, c.get_center().y), Catalog.STONE)
	var plank_cols := [Color(0.66, 0.47, 0.3), Color(0.7, 0.5, 0.33), Color(0.62, 0.44, 0.28), Color(0.68, 0.49, 0.31)]
	for i in int(c.size.x / 0.4):
		Catalog.box(house_root, Vector3(0.385, 0.04, c.size.y), Vector3(x0 + 0.2 + i * 0.4, 0.0, c.get_center().y), plank_cols[(i * 5) % 4])
	_wall(Vector2(x0, z0), Vector2(dz.x, z0), Vector3(0, 0, -1), [59.4])
	_wall(Vector2(dz.y, z0), Vector2(x1, z0), Vector3(0, 0, -1), [63.6])
	_wall(Vector2(x0, z1), Vector2(x1, z1), Vector3(0, 0, 1), [60.0, 63.0])
	_wall(Vector2(x0, z0), Vector2(x0, z1), Vector3(-1, 0, 0), [9.5])
	_wall(Vector2(x1, z0), Vector2(x1, z1), Vector3(1, 0, 0), [9.5])
	# door: closed and locked until you buy the place
	var node := Node3D.new()
	node.position = Vector3((dz.x + dz.y) * 0.5, 0, z0)
	house_root.add_child(node)
	var tall := Node3D.new()
	node.add_child(tall)
	var short := Node3D.new()
	node.add_child(short)
	var gap := dz.y - dz.x
	var h := WALL_H - 2.15
	Catalog.box(tall, Vector3(gap, h, WALL_T), Vector3(0, 2.15 + h * 0.5, 0), PLASTER)
	Catalog.box(tall, Vector3(gap + 0.02, 0.16, WALL_T + 0.06), Vector3(0, WALL_H - 0.08, 0), Catalog.WOOD_DARK)
	Catalog.box(tall, Vector3(gap + 0.1, 0.1, WALL_T + 0.08), Vector3(0, 2.15, 0), Catalog.WOOD_DARK)
	if Game.owns_cottage:
		Catalog.box(tall, Vector3(0.06, 2.05, 1.2), Vector3(-gap * 0.5 + 0.06, 1.03, 0.64), Catalog.WOOD)
	else:
		Catalog.box(tall, Vector3(gap, 2.05, 0.08), Vector3(0, 1.03, 0), Catalog.WOOD)
		Catalog.ball(tall, 0.04, Vector3(gap * 0.32, 1.0, -0.06), Catalog.BRASS)
		wall_rects.append(Rect2(dz.x, z0 - WALL_T * 0.5, gap, WALL_T))
	walls.append({"tall": tall, "short": short, "normal": Vector3(0, 0, -1), "cut": true})
	# the sign out front
	var fsign := Landmark.new()
	fsign.kind = "for_sale"
	fsign.title = "Rosewood Cottage"
	fsign.position = Vector3(57.3, 0, 5.35)
	house_root.add_child(fsign)
	for sx in [-0.5, 0.5]:
		Catalog.box(fsign, Vector3(0.08, 1.25, 0.08), Vector3(sx, 0.62, 0), Catalog.WOOD_DARK)
	var owned := Game.owns_cottage
	Catalog.box(fsign, Vector3(1.25, 0.62, 0.06), Vector3(0, 1.0, 0.04), Catalog.CREAM if owned else Color(0.72, 0.2, 0.18))
	var l := Label3D.new()
	l.text = "ROSEWOOD\nCOTTAGE" if owned else "FOR SALE\n%dc" % _cottage_price()
	l.font_size = 34
	l.pixel_size = 0.0045
	l.outline_size = 0
	l.modulate = Color(0.3, 0.18, 0.1) if owned else Color(1, 0.96, 0.9)
	l.position = Vector3(0, 1.0, 0.075)
	fsign.add_child(l)
	Town.pickable(fsign, Vector3(1.4, 1.4, 0.4), Vector3(0, 0.7, 0))
	wall_rects.append(Rect2(56.7, 5.25, 1.2, 0.2))


func _walk_wait(timeout := 30.0) -> void:
	var t := 0.0
	while (not player.path.is_empty() or player.busy) and t < timeout:
		await _wait(0.25)
		t += 0.25
	await _wait(0.4)


func _town_checks() -> void:
	Game.hour = 10.0
	hud.hide_dialogue()
	_set_cam_lock(true)
	cam_dist = 23.0
	player.position = Vector3(16.6, 0, 3.0)
	cam_target = player.position
	_do_action(sign_to_town, "travel")
	await _walk_wait(40.0)
	_check("walked the road to Maplewood (at x=%.1f)" % player.position.x, Town.TOWN.has_point(Vector2(player.position.x, player.position.z)))
	cam_target = Vector3(53, 0, -3)
	_set_cam_lock(false)
	cam_dist = 30.0
	await _wait(0.8)
	await _shot("09_town.png")
	await _wait(2.0)
	print("FPS in town view: ", Engine.get_frames_per_second())
	_set_cam_lock(true)
	cam_dist = 20.0

	var rosa := _villager("rosa")
	var p0 := int(Game.friend("rosa")["familiarity"])
	_do_action(rosa, "talk")
	await _walk_wait()
	_check("talked to Rosa (friendship %d→%d, dialogue %s)" % [p0, int(Game.friend("rosa")["familiarity"]), hud.dlg_panel.visible], int(Game.friend("rosa")["familiarity"]) > p0 and hud.dlg_panel.visible)
	await _shot("10_dialogue.png")
	Game.add_item("pumpkin", 1)
	var p1 := int(Game.friend("rosa")["familiarity"])
	_do_action(rosa, "gift_pumpkin")
	await _walk_wait()
	_check("gave Rosa a pumpkin she loves (+%d)" % (int(Game.friend("rosa")["familiarity"]) - p1), int(Game.friend("rosa")["familiarity"]) == p1 + 25)
	_check("gift is once a day", _villager_actions(rosa).any(func(a): return a["label"] == "Already gave a gift today"))
	Game.add_item("sweater", 2)
	var price := _rosa_price()
	var c0 := Game.coins
	_do_action(rosa, "sell_sweater")
	await _walk_wait()
	_check("sold 2 sweaters at the market for %dc each (market %dc + Rosa's %d-heart bonus)" % [price, Game.market_price("sweater"), Game.hearts("rosa")], Game.coins == c0 + 2 * price and Game.count("sweater") == 0)

	Game.coins += 1000
	var theo := _villager("theo")
	var w0 := Game.count("wool")
	_do_action(theo, "buy_wool")
	await _walk_wait()
	_check("bought 3 wool from Theo", Game.count("wool") == w0 + 3)
	var n0 := sheep_list.size()
	_do_action(theo, "buy_sheep")
	await _walk_wait()
	_check("bought a sheep (%d → %d in the pen)" % [n0, sheep_list.size()], sheep_list.size() == n0 + 1 and Game.sheep_count == n0 + 1)

	var blocked := _find_path(Vector3(61.5, 0, 4.5), Vector3(61.5, 0, 9.5))
	_check("cottage is locked before buying", blocked.is_empty() or blocked[-1].distance_to(Vector3(61.5, 0, 9.5)) > 0.8)
	Game.coins += 3000
	var mabel := _villager("mabel")
	_do_action(mabel, "buy_cottage")
	await _walk_wait()
	_check("bought Rosewood Cottage from Mabel", Game.owns_cottage)
	var into := _find_path(Vector3(61.5, 0, 4.5), Vector3(61.5, 0, 9.5))
	_check("can walk into the cottage after buying", into.size() > 0 and into[-1].distance_to(Vector3(61.5, 0, 9.5)) < 0.8)

	set_mode(Mode.BUILD)
	cam_target = Vector3(61.5, 0, 9.5)
	cam_dist = 18.0
	player.position = Vector3(61.5, 0, 5.2)
	await _wait(0.8)
	var placed := 0
	for spec in [["armchair", Vector3(59.0, 0, 10.8), 0], ["bed", Vector3(63.6, 0, 10.6), 0], ["rug_round", Vector3(60.5, 0, 9.6), 0], ["lamp", Vector3(64.4, 0, 7.6), 0], ["bookshelf", Vector3(58.5, 0, 8.2), 1], ["flower_pot", Vector3(66.5, 0, 6.0), 0]]:
		ghost_rot = spec[2]
		_begin_place(spec[0])
		if ghost:
			ghost.set_rot(spec[2])
		var sp := cam.unproject_position(spec[1])
		_last_mouse = sp
		_update_ghost(sp)
		var ok := ghost_valid
		_build_click(sp, false)
		if ok:
			placed += 1
		else:
			print("  could not place ", spec[0])
			_cancel_ghost()
	ghost_rot = 0
	_check("furnished the cottage (%d of 6 pieces placed)" % placed, placed >= 5)
	_begin_place("flower_pot")
	var bad := cam.unproject_position(Vector3(53.0, 0, 3.0))
	_update_ghost(bad)
	_check("can't build in the town plaza", ghost != null and not ghost_valid)
	var stall_mesh := find_children("model", "MeshInstance3D", true, false).filter(func(m): return m.global_position.distance_to(Town.STALL) < 0.5)
	_check("Rosa's market stall is the new model, one mesh (%d)" % stall_mesh.size(), stall_mesh.size() == 1)
	_cancel_ghost()
	set_mode(Mode.LIVE)
	player.position = Vector3(61.0, 0, 9.3)
	_set_cam_lock(false)
	cam_target = Vector3(61.5, 0, 9.0)
	await _wait(1.0)
	await _shot("11_cottage.png")

	var rent := _cottage_rent()
	var coins_before := Game.coins
	_go_to_sleep(false)
	await _wait(2.5)
	_check("rent paid next morning (+%dc)" % rent, rent > 80 and Game.coins == coins_before + rent)
	_save_game()
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check("save has cottage, friendships and sheep", bool(d["owns_cottage"]) and int(d["friends"]["rosa"]["familiarity"]) > 0 and int(d["sheep_count"]) == n0 + 1)
