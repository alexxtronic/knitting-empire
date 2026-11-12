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
const KnitGame = preload("res://scripts/knit_game.gd")
const Town = preload("res://scripts/town.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Grass = preload("res://scripts/grass.gd")
const Villager = preload("res://scripts/villager.gd")
const Story = preload("res://scripts/story.gd")
const StoryPlayer = preload("res://scripts/story_player.gd")
const Landmark = preload("res://scripts/landmark.gd")
const Dialogue = preload("res://scripts/dialogue.gd")
const AiChat = preload("res://scripts/ai_chat.gd")
const GameAudio = preload("res://scripts/audio.gd")
const Nature = preload("res://scripts/nature.gd")
const Fireflies = preload("res://scripts/fireflies.gd")
const Lighting = preload("res://scripts/lighting.gd")
const GodMode = preload("res://scripts/god_mode.gd")
const Planks = preload("res://scripts/planks.gd")
const Homestead = preload("res://scripts/homestead.gd")
const Dog = preload("res://scripts/dog.gd")

const CELL := 0.5
const GRID_ORIGIN := Vector2(-8.0, -22.0)
const GRID_SIZE := Vector2i(200, 84) # covers x -8..92, z -22..20 (farm, road, Maple Grove and room round it)
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
var homestead: Homestead # homestead.gd: Act 1's farm (pen builder, gate crafting, strays, rent)
var god: GodMode # god_mode.gd: the admin's world editor, and the saved layout it applies at launch
var pond_rect := Rect2()
var pen_rect := PEN # where the sheep pen stands now (god mode can move it)
const SHEEP_IN := 19.5 # the hour the flock heads for its stalls in the barn
const SHEEP_OUT := 6.5 # the hour it comes back out to the pen
var flock_bedtime := true
var _flock_t := 0.0
var _flock_seen := false
var bin: Node3D
var grid_blockers: Array = [] # static outdoor obstacles (Rect2)
var place_blockers: Array = [] # areas furniture can't go (Rect2)
var astar := AStarGrid2D.new()
var player: Player
var dog: Dog # the golden retriever: keeps Nora company, and Tab hands him the clicks (dog.gd)
var hud: Hud
var knit: KnitGame # the knitting game (knit_game.gd), a rhythm game played to a song
var _knit_chair = null
var _knit_clock_was := true
var audio: GameAudio
var story: StoryPlayer
var villagers: Array = []
var ai: AiChat # typed chat with villagers, voiced by Claude
var chat_v = null # the villager you're chatting with
var _chat_clock_was := true
var decor: Array = [] # town lanterns/benches: furniture you can use but not pick up
var fireflies # fireflies.gd: glowing orbs round things near her at night
var lighting # lighting.gd: morning mist and its light shafts, SDFGI on High
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
	lighting = Lighting.new()
	add_child(lighting)
	lighting.setup(self)
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
	grid_blockers.append_array(World.build_barn(self, Vector3(21.5, 0, -9.5)))
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
	_place_shopkeepers() # behind their counters, wherever the layout put their shops
	god.reapply_scenery() # nothing grows on the shops' floors where they stand now
	if _autotest_dir != "":
		god.layout_path = GOD_TEST_LAYOUT # the test saves here, never over the real layout
	player = Player.new()
	player.position = Vector3(4.6, 0, 4.9)
	add_child(player)
	fireflies = Fireflies.new() # after the layout, so they gather round things where they now stand
	add_child(fireflies)
	fireflies.setup(self)
	hud = Hud.new()
	add_child(hud)
	audio = GameAudio.new()
	add_child(audio)
	audio.setup(self, _autotest_dir != "")
	hud.sfx = audio.play
	player.footstep.connect(func(): audio.footstep(player.position))
	player.needle_click.connect(audio.needle)
	knit = KnitGame.new()
	hud.root.add_child(knit)
	knit.stitched.connect(func(_g): audio.needle())
	knit.finished.connect(_on_knit_finished)
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
	homestead = Homestead.new()
	homestead.main = self
	add_child(homestead)
	homestead.apply()
	_setup_dog()
	_load_graphics()
	hud.render_thumbnails()
	_load_display()
	tips_enabled = _autotest_dir == "" # the autotest turns them on for its own check
	flock_bedtime = _autotest_dir == "" # and the flock stays in the pen but for its own check
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
	hud.hud_option.connect(_save_hud_option)
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
## Low / Medium / High, set in Settings and kept in user://settings.cfg (not the
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
	lighting.apply_graphics(gfx)
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
	lighting.update(rain, dl)
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
	for p in plots:
		if p.tilled: # the beds she dug herself
			dirt.append(Rect2(p.position.x - 0.75, p.position.z - 0.75, 1.5, 1.5))
	var clear: Array = grid_blockers.filter(func(r): return r != pond_rect)
	clear.append(Rect2(-0.35, _zmin() - 0.35, HOUSE_W + 0.7, HOUSE_FRONT - _zmin() + 0.7))
	if not painted:
		clear.append(Town.PLAZA)
	clear.append(Town.COTTAGE.grow(0.3))
	clear.append(Rect2(8.1, 2.35, 1.0, 1.3)) # doormat
	clear.append_array(World.barn_floor()) # its walls block the way; the floor between them only stops the grass
	clear.append_array(Interiors.floors()) # and the shops' floors (their walls and furniture block the way)
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
	_plank_floor(Rect2(0, z0, W, depth), 11, "house")
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
	var holes: Array = []
	for wpos in windows:
		var o := float(wpos) - (mid.x if horizontal else mid.y)
		_window(tall, o, horizontal)
		holes.append(Rect2(o - 0.58 + length * 0.5, 0.99, 1.16, 1.12))
	for side in ([-1.0, 1.0] if divider else [-1.0]): # a room divider is indoors on both sides
		_wall_boards(tall, horizontal, length, height, normal * side, holes)
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


## Pale boards over the face of a wall that looks `into` the room, from floor to top, round its
## windows, with a rail along the top and a skirting board along the floor (scripts/planks.gd).
func _wall_boards(tall: Node3D, horizontal: bool, length: float, height: float, into: Vector3, holes: Array) -> void:
	var out := WALL_T * 0.5 + 0.04 # in front of the posts, just behind the window frames
	var across := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
	var origin := into * out - across * length * 0.5
	var seed_from := tall.get_parent() as Node3D
	Planks.lay(tall, "wall", origin, across, Vector3.UP, Vector2(length, height), into, holes,
		hash(Vector3i(roundi(seed_from.position.x * 10.0), roundi(seed_from.position.z * 10.0), roundi(into.x + 2.0 * into.z))))
	var o := (into.z if horizontal else into.x) * (out + 0.015)
	Catalog.box(tall, _sz(horizontal, length, 0.14, 0.03), _at(horizontal, 0, height - 0.07, o), Planks.TRIM)
	Catalog.box(tall, _sz(horizontal, length, 0.13, 0.03), _at(horizontal, 0, 0.065, o), Planks.TRIM)


## A plank floor over a ground rectangle (x, z): boards run front to back, their ends staggered.
func _plank_floor(r: Rect2, plank_seed: int, shade: String) -> void:
	Catalog.box(house_root, Vector3(r.size.x, 0.012, r.size.y), Vector3(r.get_center().x, 0.006, r.get_center().y), Color(0.36, 0.22, 0.12)) # the boards' edge at the door
	Planks.lay(house_root, "floor", Vector3(r.position.x, 0.02, r.position.y), Vector3(1, 0, 0), Vector3(0, 0, 1), r.size, Vector3.UP, [], plank_seed, shade)


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
	# everything outside the walk areas is solid: mark it all, then open the areas up again
	astar.fill_solid_region(astar.region, true)
	for a in walk_areas():
		var r := a as Rect2
		var c0 := _cell(Vector3(r.position.x, 0, r.position.y))
		var c1 := _cell(Vector3(r.end.x, 0, r.end.y))
		for x in range(maxi(c0.x, 0), mini(c1.x + 1, GRID_SIZE.x)):
			for y in range(maxi(c0.y, 0), mini(c1.y + 1, GRID_SIZE.y)):
				var c := _cell_center(Vector2i(x, y))
				if r.has_point(Vector2(c.x, c.z)):
					astar.set_point_solid(Vector2i(x, y), false)
	var rects := []
	rects.append_array(wall_rects)
	rects.append_array(grid_blockers)
	for f in furniture:
		if not f.is_flat():
			rects.append(f.footprint())
	for r in rects:
		_mark_rect((r as Rect2).grow(0.2))


## Where she may walk: her land, the road, the town, and the ground round every building wherever
## the world editor has put it, so a shop moved to the edge of town can still be walked into.
func walk_areas() -> Array:
	var areas: Array = [LOT, Town.ROAD, Town.TOWN]
	for b in Town.built:
		var n := b[0] as Node3D
		if is_instance_valid(n) and n.visible:
			areas.append(Rect2(n.global_position.x - 6.5, n.global_position.z - 6.5, 13.0, 13.0))
	return areas


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
	_update_held_tool()
	_update_flock(delta)
	World.update_barn(player.position, cam_yaw, walls_up, delta,
		sheep_list.filter(func(s): return not s.route.is_empty()).map(func(s): return s.position))
	Interiors.update(player.position, cam_yaw, walls_up, delta, villagers.map(func(v): return v.position))
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
	player.walk_speed = (1.47 + 0.21 * Game.fitness / 100.0) * 1.25 # a brisk walk; the Walk loop speeds up to match
	player.run_speed = 2.75 + 0.6 * Game.fitness / 100.0
	player.running = autotest_jog or _held(KEY_SHIFT)
	_update_dog()
	var head := player.head_point()
	var show := player.busy and not story.is_playing() and not sleeping and not hide_activity_bar and not knit.active and not cam.is_position_behind(head)
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
		cam_target = cam_target.lerp(dog.position if dog and dog.controlled else player.position, 1.0 - exp(-4.0 * delta))
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
	if knit != null and knit.active:
		return false # the game's keys (D F J K) must not pan the camera
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
	if sleeping or story.is_playing() or title_on or knit.active:
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
					if mb.button_index == MOUSE_BUTTON_RIGHT:
						if mb.pressed:
							_rclick_from = mb.position
						elif mode == Mode.LIVE and mb.position.distance_to(_rclick_from) < 8.0:
							_right_click(mb.position) # a click, not a drag of the camera
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
	if sleeping or title_on or knit.active or not (e is InputEventKey):
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
	if kc >= KEY_1 and kc <= KEY_9 and not god.active:
		hud.hotbar_key(kc - KEY_0)
		get_viewport().set_input_as_handled()
		return
	var handled := true
	match kc:
		KEY_I:
			hud.toggle_bag()
		KEY_Q:
			cam_yaw_goal -= PI * 0.5
		KEY_E:
			cam_yaw_goal += PI * 0.5
		KEY_R:
			_rotate_ghost()
		KEY_C:
			walls_up = not walls_up
		KEY_TAB:
			toggle_dog()
		KEY_SPACE:
			_set_cam_lock(not cam_follow, true)
		KEY_B:
			set_mode(Mode.LIVE if mode == Mode.BUILD else Mode.BUILD)
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			_sell_ghost()
		KEY_ESCAPE:
			if ghost:
				_cancel_ghost()
			elif homestead.building:
				homestead.set_builder(false)
			elif homestead.ui.is_open():
				homestead.ui.close_all()
			elif hud.is_menu_open():
				hud.hide_menu()
			elif hud.help_panel.visible:
				hud.help_panel.visible = false
			elif hud.bag_panel.visible:
				hud.toggle_bag()
			elif hud.settings_panel.visible:
				hud.settings_panel.visible = false
			elif hud.journal_panel.visible:
				hud.journal_panel.visible = false
			elif mode == Mode.BUILD:
				set_mode(Mode.LIVE)
			else:
				hud.toggle_game_menu()
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


# --- the dog -------------------------------------------------------------------------

## He is on the farm from the start of a sandbox game or an old save; in Act 1 he turns up once
## the pen is built (homestead.gd's "pen_done", the "pen_built" story event).
func dog_here() -> bool:
	return Game.flag("story_farm") != true or Game.flag("pen_done") == true


func _setup_dog() -> void:
	dog = Dog.new()
	dog.main = self
	dog.position = player.position + Vector3(1.2, 0, 0.8)
	add_child(dog)
	_update_dog()


## Tab: the player's clicks move the dog (Shift gallops him) and the camera follows him; Tab again
## gives them back to Nora. A story scene or bedtime always hands them back.
func toggle_dog(on = null) -> void:
	if dog == null or not dog.visible:
		return
	dog.controlled = (not dog.controlled) if on == null else bool(on)
	dog.path = []
	if dog.controlled:
		player.walk([])
		hud.show_toast("You're the dog now. Click to run about, Shift to gallop, Tab to go back to Nora.")
	_set_cam_lock(true)


func _update_dog() -> void:
	if dog == null:
		return
	var here := dog_here()
	if here != dog.visible:
		dog.visible = here
		dog.process_mode = Node.PROCESS_MODE_INHERIT if here else Node.PROCESS_MODE_DISABLED
		if here: # he comes running up the lane
			dog.position = player.position + Vector3(-9.0, 0, 6.0)
	if not here:
		dog.controlled = false
		return
	if homestead and not homestead.herders.has(dog):
		homestead.herders.append(dog)
	if dog.controlled and (story.is_playing() or sleeping):
		dog.controlled = false
	dog.running = dog.controlled and (autotest_jog or _held(KEY_SHIFT))


func _live_click(mpos: Vector2) -> void:
	var t = _ray_target(mpos)
	if not (dog and dog.controlled) and _tool_click(hud.selected_item(), t, mpos):
		return
	if t != null and not (dog and dog.controlled):
		var acts := _actions_for(t)
		if not acts.is_empty():
			hud.show_menu(mpos, _name_of(t), acts, func(id): _do_action(t, id))
			return
	var g = _ground_point(mpos)
	if g != null and dog and dog.controlled:
		dog.walk(_find_path(dog.position, g))
		_click_marker(g)
		return
	if g != null:
		player.walk(_find_path(player.position, g))
		_click_marker(g)


var _rclick_from := Vector2(-999, -999)


## A right click: the ring of what she can do there. On a thing, its own actions; on open
## ground, walking there and (with her hoe) digging a bed. Beds are only ever dug from here, so a
## plain click never turns the lawn over by accident.
func _right_click(mpos: Vector2) -> void:
	var t = _ray_target(mpos)
	if t != null:
		var acts := _actions_for(t)
		if not acts.is_empty():
			hud.show_menu(mpos, _name_of(t), acts, func(id): _do_action(t, id))
			return
	var g = _ground_point(mpos)
	if g == null:
		return
	var at := _plot_spot(g)
	var acts := ground_actions(g)
	hud.show_menu(mpos, "Here", acts, _ground_action.bind(g, at))


func _ground_action(id: String, g: Vector3, at: Vector3) -> void:
	if id == "dig":
		dig_bed(at)
	else:
		player.walk(_find_path(player.position, g))
		_click_marker(g)


## The ground ring's choices at a spot.
func ground_actions(g: Vector3) -> Array:
	var acts := [_act("walk", "Walk here")]
	if Game.count("hoe") > 0 and LOT.has_point(Vector2(g.x, g.z)) and not building_at(g):
		acts.append(_act("dig", "Dig bed"))
	return acts


## Digs a new bed at a square of the beds' grid, if the ground there allows it. True if she set off.
func dig_bed(at: Vector3) -> bool:
	if player.busy:
		return false
	var why := _till_problem(at)
	if why != "":
		hud.show_toast(why)
		return false
	_tool_walk(at, at + Vector3(0, 0, 0.9), 4.0, "Digging a bed", 1.8, _finish_till.bind(at))
	return true


## Whether a spot is inside (or in the walls of) a building: her house, the barn, any walk-in shop,
## the cottage. Nothing gets dug or planted there. Buildings are found by their nodes, so this
## still holds after the world editor moves them.
func building_at(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if house_rect().grow(0.3).has_point(q) or Town.COTTAGE.grow(0.3).has_point(q):
		return true
	if Interiors.inside_of(p) != "":
		return true
	if World.barn != null and is_instance_valid(World.barn) and World.barn.visible:
		var b: Vector3 = World.barn.global_transform.affine_inverse() * p
		if absf(b.x) < World.BARN_SIZE.x * 0.5 + 0.3 and absf(b.z) < World.BARN_SIZE.y * 0.5 + 0.3:
			return true
	return false


# --- tools: with one in her hand (the hotbar), a click uses it ---------------------------

const PLOT_GRID := 1.2 # beds sit on the grid the first twelve were laid out on
const PLOT_ORIGIN := Vector2(11.0, -1.0)
const CHOP_WOOD := 2
var _chopped := {} # tree (a god mode element) -> the day it was last chopped: once a day each


const TOOL_MODEL := "res://assets/props/%s.glb"
## Her right fist, from tools/add_grip.py: the 'grip_R' shape key curls her fingers round a handle
## through FIST_C along FIST_AXIS (her model's own space in its rest pose: forward is +Z, the hand
## hanging down at her side). A tool's handle goes through that, so her fingers close round it.
const FIST_C := Vector3(-0.194, 0.716, 0.06)
const FIST_AXIS := Vector3(0, 0, 1)
const FIST_DOWN := Vector3(0, -1, 0)
## How each tool sits in the fist, in the tool model's own space (built standing up, art/world_assets/
## tools/build.py): the point held, the handle's direction toward the working end, the side that
## hangs down, and its size in the game. Each is held where its handle is as thick as the fist.
const TOOL_HOLD := {
	"axe": [Vector3(0.004, 0.36, 0), Vector3.UP, Vector3.RIGHT, 0.55],
	"hoe": [Vector3(0, 0.3, 0), Vector3.UP, Vector3.RIGHT, 0.65],
	"shovel": [Vector3(0, 0.3, 0), Vector3.UP, Vector3.BACK, 0.65],
	"scythe": [Vector3(0, 0.37, 0), Vector3.UP, Vector3.RIGHT, 0.65],
	"shears": [Vector3(0.044, 0.11, 0.0065), Vector3(-0.22, 0.975, 0), Vector3.RIGHT, 0.8],
	"watering_can": [Vector3(0, 0.368, 0), Vector3.RIGHT, Vector3.DOWN, 0.75],
}
var _tool_hand: BoneAttachment3D
var _held_id := ""
var _grip_meshes: Array = [] # her meshes with the grip_R shape key


## Shows the hotbar's tool in her fist (once that tool has a model), and takes it away while she
## sits, sleeps or is in a story scene.
func _update_held_tool() -> void:
	var id := hud.selected_item() if not title_on else ""
	if not Game.TOOLS.has(id) or not ResourceLoader.exists(TOOL_MODEL % id):
		id = ""
	if id != _held_id and player.body and player.body.skeleton:
		_held_id = id
		var sk: Skeleton3D = player.body.skeleton
		if _tool_hand == null:
			_tool_hand = BoneAttachment3D.new()
			sk.add_child(_tool_hand)
			_tool_hand.bone_name = "RightHand"
			_grip_meshes = player.body.find_children("*", "MeshInstance3D", true, false).filter(
				func(mi): return mi.mesh != null and mi.find_blend_shape_by_name("grip_R") >= 0)
		for c in _tool_hand.get_children():
			c.queue_free()
		if id != "":
			var m := Catalog.model(TOOL_MODEL % id, _tool_hand)
			if m:
				m.transform = _tool_in_fist(sk, id)
	if _tool_hand:
		_tool_hand.visible = _held_id != "" and mode == Mode.LIVE and not story.is_playing() and not player.is_sitting() and not player.is_lying()
		for mi in _grip_meshes:
			mi.set_blend_shape_value(mi.find_blend_shape_by_name("grip_R"), 1.0 if _tool_hand.visible else 0.0)


## Where a tool sits in the hand bone's space: its handle through the fist, the hanging side down.
func _tool_in_fist(sk: Skeleton3D, id: String) -> Transform3D:
	var hold: Array = TOOL_HOLD[id]
	var rest: Transform3D = sk.get_bone_global_rest(sk.find_bone("RightHand")).orthonormalized()
	var a: Vector3 = rest.basis.inverse() * FIST_AXIS
	var d: Vector3 = rest.basis.inverse() * FIST_DOWN
	var want := _frame(a, d)
	var have := _frame(hold[1], hold[2])
	var b: Basis = (want * have.inverse()).scaled(Vector3.ONE * float(hold[3]))
	return Transform3D(b, rest.affine_inverse() * FIST_C - b * (hold[0] as Vector3))


## A right-handed frame from a main direction and a second one squared off against it.
func _frame(main_dir: Vector3, second: Vector3) -> Basis:
	var x := main_dir.normalized()
	var y := (second - x * second.dot(x)).normalized()
	return Basis(x, y, x.cross(y))


## Uses the tool on whatever was clicked. False when the tool has nothing to do there, and the
## click then does what it always did (the ring of actions, or walking).
func _tool_click(tool: String, t, mpos: Vector2) -> bool:
	if not Game.TOOLS.has(tool) or player.busy:
		return false
	match tool:
		"watering_can":
			if t is Plot and t.crop != "" and not t.is_ready() and not t.watered:
				_do_action(t, "water")
				return true
		"shears":
			if t is Sheep and t.is_woolly():
				_do_action(t, "shear")
				return true
		"shovel":
			if t is Plot and t.crop == "":
				if not t.tilled:
					hud.show_toast("Gran dug these beds. They stay.")
					return true
				_tool_walk(t.position, t.position + Vector3(0, 0, 0.9), 3.0, "Clearing the bed", 1.4, _finish_clear_plot.bind(t))
				return true
		"axe":
			var tree = god.pick_kind(mpos, "tree_") if t == null else null
			if tree != null:
				if int(_chopped.get(tree, 0)) == Game.day:
					hud.show_toast("She's taken what this tree can spare today.")
					return true
				var trunk: Vector3 = tree.xf.origin
				trunk.y = 0.0
				var away := (player.position - trunk)
				away.y = 0.0
				away = away.normalized() if away.length() > 0.1 else Vector3(0, 0, 1)
				_tool_walk(trunk, trunk + away * 1.3, 6.0, "Chopping", 2.6, _finish_chop.bind(tree))
				return true
		"scythe":
			var g = _ground_point(mpos)
			if t == null and g != null and grass.grass_at(g.x, g.z) > 0.6:
				_tool_walk(g, g, 3.0, "Cutting hay", 1.6, _finish_mow)
				return true
	return false


## Walks to `stand`, faces `look` and starts the tool's work, if she has the energy for it.
func _tool_walk(look: Vector3, stand: Vector3, energy: float, text: String, secs: float, done: Callable) -> void:
	_click_marker(look)
	player.walk(_find_path(player.position, stand), func():
		player.face_point(look)
		if Game.use_energy(energy):
			player.start_activity(text, secs, done))


## The bed square a click on the ground means: the nearest one on the beds' grid.
func _plot_spot(g: Vector3) -> Vector3:
	var c := ((Vector2(g.x, g.z) - PLOT_ORIGIN) / PLOT_GRID).round() * PLOT_GRID + PLOT_ORIGIN
	return Vector3(c.x, 0, c.y)


## Why a bed can't be dug at this spot ("" when it can): it has to be open ground on her land.
func _till_problem(at: Vector3) -> String:
	var p := Vector2(at.x, at.z)
	var bed := Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0))
	if not LOT.grow(-0.6).has_point(p):
		return "That's past the edge of her land."
	for c in [Vector2(0, 0), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		if building_at(at + Vector3(c.x, 0, c.y)):
			return "Not indoors."
	for pl in plots:
		if absf(pl.position.x - at.x) < PLOT_GRID - 0.05 and absf(pl.position.z - at.z) < PLOT_GRID - 0.05:
			return "There's a bed here already."
	var house := Rect2(-0.6, _zmin() - 0.6, HOUSE_W + 1.2, HOUSE_FRONT - _zmin() + 1.2)
	if house.intersects(bed) or pen_rect.grow(0.5).intersects(bed):
		return "Not here: it's in the way."
	for r in grid_blockers:
		if (r as Rect2).intersects(bed):
			return "Not here: something's in the way."
	for c in [p, bed.position, bed.end, Vector2(bed.position.x, bed.end.y), Vector2(bed.end.x, bed.position.y)]:
		if god.road_at(c.x, c.y) != "":
			return "Not on the path."
	if not god.roads_on:
		for r in World.PATHS:
			if (r as Rect2).intersects(bed):
				return "Not on the path."
	return ""


func _add_plot(at: Vector3) -> Plot:
	var p = Plot.new()
	p.position = at
	p.tilled = true
	add_child(p)
	plots.append(p)
	return p


## The grass makes way for a bed she dug, and grows back when she clears it.
func _regrass(at: Vector3) -> void:
	_rebuild_grass(false)
	grass.replant(Rect2(at.x - 1.0, at.z - 1.0, 2.0, 2.0))


func _finish_till(at: Vector3) -> void:
	if _till_problem(at) != "":
		return
	_add_plot(at)
	_regrass(at)
	Game.add_need("fitness", 2.0)
	hud.show_toast("A new bed. Plant something in it.")


func _finish_clear_plot(p) -> void:
	if not plots.has(p) or p.crop != "":
		return
	plots.erase(p)
	var at: Vector3 = p.position
	p.queue_free()
	_regrass(at)
	Game.add_need("fitness", 1.0)


func _finish_chop(tree) -> void:
	_chopped[tree] = Game.day
	Game.add_item("wood", CHOP_WOOD)
	Game.add_need("fitness", 3.0)
	hud.show_toast("+%d wood" % CHOP_WOOD)


func _finish_mow() -> void:
	Game.add_item("hay")
	Game.add_need("fitness", 1.5)
	hud.show_toast("+1 hay")


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
	if t is Node and t.has_method("ke_actions"): # small things that list their own (Gran's tin)
		return t.ke_actions()
	if t == bin:
		var sw := Game.count("sweater")
		var crops: int = Game.count("turnip") * Game.SELL_PRICES["turnip"] + Game.count("pumpkin") * Game.SELL_PRICES["pumpkin"]
		var wool := Game.count("wool")
		return [
			_act("ship_sweater", "Ship sweaters (%d, %dc)" % [sw, Game.sweater_worth(Game.SELL_PRICES["sweater"])], sw > 0),
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
				return [_act("travel", "Walk to Maple Grove")]
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
	# a shopkeeper's spot in front of the counter, while they are at work (a scene may take them out)
	if t is Villager and t.talk_spot != null and t.position.distance_to(t.talk_spot) < 3.0:
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
		"rocking_chair", "sofa", "armchair":
			y = 0.42 # the top of their seat cushions (art/world_assets/house_furniture)
		"bench", "bench_short":
			y = 0.374 # the top of the boards of assets/props/bench_park.glb: the seated loops put the seat at her origin
			fwd = 0.03 # her back against the slats
	return f.global_position + Vector3(0, y, 0) + f.front() * fwd


func _do_action(t, id: String) -> void:
	if t is Landmark:
		match id:
			"travel":
				var dest: Vector3 = Town.TOWN_ARRIVE if t.kind == "travel_town" else Town.FARM_ARRIVE
				player.walk(_find_path(player.position, dest))
				_click_marker(dest)
			"info":
				hud.show_dialogue("Rosewood Cottage", -1, "A cozy cottage with a garden lot, just off the plaza. For sale: %dc. Mabel at Willow Homes handles the sale. Furnish it and renters pay you every morning." % _cottage_price())
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
	if t.has_method("ke_action"):
		t.ke_action(id)
		return
	match id:
		"knit":
			if not Game.has_item("wool", 3):
				hud.show_toast("You need 3 wool to knit a sweater. Shear a sheep!")
				return
			if Game.use_energy(10.0):
				_begin_knit(t)
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


## Sits her in the chair and opens the knitting game. The day waits while she plays.
func _begin_knit(chair) -> void:
	_knit_chair = chair
	_knit_clock_was = Game.time_running
	Game.time_running = false
	player.quiet_needles = true # the game makes the clicks now
	player.start_activity("Knitting", 100000.0, Callable(), _seat_point(chair), chair.rotation.y)
	var testing := _autotest_dir != ""
	var opts := {"best": Game.flag("knit_best", {}), "auto": testing, "fast": 11.0 if testing else 1.0, "silent": testing}
	if testing:
		opts["song"] = "cast_on"
	knit.open(opts)


func _on_knit_finished(res: Dictionary) -> void:
	Game.time_running = _knit_clock_was
	player.quiet_needles = false
	player.cancel_activity()
	if bool(res.get("cancelled", false)):
		Game.energy = minf(100.0, Game.energy + 10.0) # she didn't knit after all
		hud.show_toast("You put the needles down.")
		return
	var best: Dictionary = (Game.flag("knit_best", {}) as Dictionary).duplicate()
	if int(res["rarity"]) > int(best.get(str(res["song"]), 0)):
		best[str(res["song"])] = int(res["rarity"])
		Game.set_flag("knit_best", best)
	_finish_knit(int(res["rarity"]))


func _finish_knit(rarity := 0) -> void:
	if Game.take_item("wool", 3):
		var worn0 := Game.worn_quality
		var q := Game.knit_sweater(rarity)
		Game.add_need("happiness", 14.0)
		if q > worn0:
			hud.show_toast("A %s sweater! Warmer than anything she owns. She'll wear one like it." % KnitGame.rarity_name(q))
		else:
			hud.show_toast("You knitted a %s sweater! Ship it for %dc." % [KnitGame.rarity_name(q), Game.sweater_worth(Game.SELL_PRICES["sweater"]) if Game.count("sweater") == 1 else int(round(Game.SELL_PRICES["sweater"] * float(Game.RARITY_PRICE[q - 1])))])
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
		earned += Game.sweater_worth(int(Game.SELL_PRICES[k])) if k == "sweater" else n * int(Game.SELL_PRICES[k]) # sweaters sell by rarity
		Game.take_item(k, n)
	if earned > 0:
		Game.coins += earned
		hud.show_toast("Shipped! +%dc" % earned)


func _go_to_sleep(passed_out: bool) -> void:
	if sleeping:
		return
	sleeping = true
	player.stay_asleep = true
	if player.body:
		player.body.set_eyes_closed(true)
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
	player.stay_asleep = false
	if player.body:
		player.body.set_eyes_closed(false)
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

## One piece of her furniture as the save and the layout's "house" list keep it.
func furniture_entry(f: Furniture) -> Dictionary:
	var e := {"id": f.item_id, "x": snappedf(f.position.x, 0.001), "z": snappedf(f.position.z, 0.001), "rot": f.rot}
	var yaw := rad_to_deg(f.rotation.y)
	if absf(angle_difference(deg_to_rad(yaw), f.rot * PI * 0.5)) > 0.001:
		e["yaw"] = snappedf(yaw, 0.01) # turned in god mode by something other than a quarter turn
	var sc: float = f.scale.x
	if absf(sc - 1.0) > 0.0005:
		e["s"] = snappedf(sc, 0.001)
	return e


func _spawn_entry(e: Dictionary) -> void:
	if not Catalog.ITEMS.has(str(e.get("id", ""))):
		return
	var f := _spawn_furniture(str(e["id"]), Vector3(float(e["x"]), 0, float(e["z"])), int(e.get("rot", 0)))
	if e.has("yaw"):
		f.rotation.y = deg_to_rad(float(e["yaw"]))
	if e.has("s"):
		f.scale = Vector3.ONE * float(e["s"])


func _new_world() -> void:
	if god != null and not god.house_list.is_empty():
		# her house as arranged in god mode (data/world_layout.json's "house" list)
		for e in god.house_list:
			_spawn_entry(e)
		_new_world_crops()
		return
	_spawn_furniture("fireplace", Vector3(0.6, 0, 2.5), 1)
	_spawn_furniture("rug_red", Vector3(3.5, 0, 3.0), 0)
	_spawn_furniture("rocking_chair", Vector3(2.4, 0, 3.6), 3)
	_spawn_furniture("coffee_table", Vector3(4.0, 0, 3.0), 0) # toward where a sofa goes, off the middle of the rug
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
	_new_world_crops()


func _new_world_crops() -> void:
	plots[0].plant("turnip")
	plots[0].growth = 5.0
	plots[0].water()
	plots[1].plant("pumpkin")
	plots[1].growth = 4.0


func _save_game() -> void:
	var d := Game.to_dict()
	var fl := []
	for f in furniture:
		fl.append(furniture_entry(f))
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
		_spawn_entry(e)
	var pl: Array = d.get("plots", [])
	for i in pl.size():
		var at = (pl[i] as Dictionary).get("tilled") # a bed she dug: it comes with its place
		if at is Array and i >= plots.size():
			_add_plot(Vector3(float(at[0]), 0, float(at[1])))
		if i < plots.size():
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
		["sell", after_act1 and Game.count("sweater") > 0, "Sell sweaters to Rosa at the Maple Grove market (her price changes daily), ship them in the bin, or give one as a gift."],
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


## The frame counter and the on-screen camera buttons are off unless switched on in settings.
func _save_hud_option(option: String, on: bool) -> void:
	if _autotest_dir == "":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("hud", option, on)
		cfg.save(SETTINGS_PATH)


func _load_display() -> void:
	if _autotest_dir != "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for option in ["fps", "camera_pad"]:
			hud.set_option(option, bool(cfg.get_value("hud", option, false)))
	cfg = ConfigFile.new()
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
	Game.fullness = 100.0
	for vid in ["rowan", "mabel", "wren", "pip", "hazel", "gus", "theo", "rosa"]:
		set_home(vid)
	mode = Mode.LIVE
	story.shown.clear()
	story.auto = true
	story.auto_line = 0.3
	story.auto_choices = [0, 1, 0, 1, 0]
	homestead.start_story() # Act 1's farm: no pen, no sheep, no money
	var trust0 := Game.stat("rowan", "trust")
	var journal0: int = Game.journal().size()
	var day0 := Game.day
	var walk_secs := 0.0
	_check("a new game opens on Act 1 (%s) on Gran's farm as she finds it (coins %d, sheep %d, old pen hidden: %s)" % [Story.find_trigger("start"), Game.coins, sheep_list.size(), str(not World.pen.visible)],
		Story.find_trigger("start") == "act1_arrival" and Game.coins == 0 and sheep_list.is_empty() and not World.pen.visible and not homestead.has_pen())
	var sign_n := decor.filter(func(f): return f.item_id == "welcome_sign").size()
	_check("the Welcome to Maple Grove sign stands by the road (%d)" % sign_n, sign_n == 1)
	var hour0 := Game.hour
	var hour_end := [-1.0] # read the moment the scene ends, before the clock starts again
	story.scene_finished.connect(func(_id): hour_end[0] = Game.hour, CONNECT_ONE_SHOT)
	story.trigger("start")
	await _act1_shot("Last stop", "20_act1_rain_bus.png")
	await _act1_shot("No name", "21_act1_phone.png")
	await _act1_shot("WELCOME TO MAPLE GROVE", "21_act1_sign.png")
	await _act1_shot("Hazel the baker", "21_act1_town_hazel.png")
	var tune_on: bool = audio.tune_name == "arrival"
	await _act1_shot("Pip the postman", "21_act1_town_pip.png")
	await _act1_shot("going to like it here", "21_act1_like_it_here.png")
	await _act1_shot("expecting you", "22_act1_wren.png")
	await _act1_shot("Timber, nails", "22_act1_tour_gus.png")
	await _act1_shot("Ellie's girl", "22_act1_tour_theo.png")
	await _act1_shot("on the house", "22_act1_tour_hazel.png")
	await _act1_shot("Front door sticks", "23_act1_grans_door.png")
	await _act1_until_done(120.0)
	_check("the clock stands still during a scene (%.2f → %.2f)" % [hour0, hour_end[0]], absf(hour_end[0] - hour0) < 0.001 and Game.time_running)
	_check("the arrival: the rain stops at the sign to the arrival music (%s), the mayor's tour ends at Gran's door with a goal ('%s')" % [str(tune_on), hud.goal_label.text],
		tune_on and Game.flag("act1_toured") == true and str(Game.flag("weather")) == "clear" and player.position.distance_to(Vector3(10.4, 0, 3.0)) < 0.6
		and hud.goal_panel.visible and goal_marker.visible and hud.goal_label.text.begins_with("Go inside"))
	var keepers_back := 0
	for vid in ["hazel", "gus", "theo", "mabel"]:
		if _villager(vid).position.distance_to(_villager_post(vid)) < 1.5:
			keepers_back += 1
	_check("the shopkeepers went back to their counters after the tour (%d of 4)" % keepers_back, keepers_back == 4)
	await _wait(0.8)
	var t0 := Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(5.6, 0, 3.0)))
	var t := 0.0
	while story.playing != "act1_note" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("stepping inside starts Gran's note (%s)" % story.playing, story.playing == "act1_note")
	await _act1_shot("For my Nora", "24_act1_note.png")
	await _act1_until_done(60.0)
	_check("Gran's note: kept in her bag, 100 coins, rent to the tin (coins %d, note %s, rent due day %s)" % [Game.coins, str(Game.has_item("gran_note")), str(Game.flag("rent_due"))],
		Game.coins == 100 and Game.has_item("gran_note") and Game.flag("rent_on") == true and int(Game.flag("rent_due", 0)) == Game.day + 7
		and hud.goal_label.text.begins_with("Buy yarn") and homestead.note_prop == null)
	var tin_acts: Array = _actions_for(homestead.tin)
	_check("Gran's tin: nothing owed yet, and the note to read again (%s)" % str(tin_acts.map(func(x): return x["label"])),
		tin_acts.size() == 2 and not tin_acts[0]["enabled"] and tin_acts[1]["id"] == "read_note")
	homestead.ui.show_note(homestead.NOTE_TEXT)
	await _wait(0.4)
	await _shot("24_act1_note_paper.png")
	_check("the note opens on paper", homestead.ui.is_open())
	homestead.ui.close_all()
	# her first yarn, from Theo
	var theo := _villager("theo")
	var wool_price := _theo_price(Game.WOOL_PACK_PRICE)
	t0 = Time.get_ticks_msec()
	_do_action(theo, "buy_wool")
	t = 0.0
	while story.playing != "act1_yarn" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("buying her first yarn from Theo starts the next beat (%s after %.1fs)" % [story.playing, t], story.playing == "act1_yarn")
	await _act1_until_done(30.0)
	Game.hour = 9.0 # the test walks fast, but not that fast: keep the act on one day, as a player would sleep between
	_check("she has the yarn (coins %d, wool %d) and a goal to knit ('%s')" % [Game.coins, Game.count("wool"), hud.goal_label.text],
		Game.coins == 100 - wool_price and Game.count("wool") >= 3 and hud.goal_label.text.begins_with("Knit"))
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	t0 = Time.get_ticks_msec()
	_do_action(chair, "knit")
	t = 0.0
	while story.playing != "act1_knit" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("finishing her first sweater starts the memory (%s)" % story.playing, story.playing == "act1_knit")
	await _act1_shot("Babe.", "27_act1_memory.png")
	_check("the first knit opens memory thread #1 in the faded memory look", hud.memory_on())
	await _act1_until_done(40.0)
	_check("the memory is in her journal, and two strays are bleating out by the pond (%d strays, goal '%s')" % [homestead.strays.size(), hud.goal_label.text],
		Game.journal().size() == journal0 + 1 and Game.journal()[-1]["kind"] == "memory" and homestead.strays.size() == 2 and hud.goal_label.text.begins_with("Find"))
	# the hunt: walk out to the strays
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(12.2, 0, -12.4)))
	t = 0.0
	while story.playing != "act1_strays" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("finding the strays starts Rowan's scene (%s)" % story.playing, story.playing == "act1_strays")
	await _act1_shot("Two sheep", "25_act1_strays.png")
	await _act1_shot("You alright?", "25_act1_rowan.png")
	await _act1_until_done(60.0)
	Game.hour = 9.0
	_check("the strays: met Rowan, opened up (trust %d→%d), off to Gus for wood ('%s')" % [trust0, Game.stat("rowan", "trust"), hud.goal_label.text],
		Game.flag("met_rowan") == true and Game.flag("nora_opened") == true and Game.stat("rowan", "trust") == trust0 + 3 and hud.goal_label.text.begins_with("Buy wood"))
	# wood from Gus at Builder's Delight
	var gus := _villager("gus")
	var acts: Array = _villager_actions(gus).map(func(x): return x["id"])
	_check("Gus sells wood (%s)" % str(acts), "buy_wood" in acts)
	var coins1 := Game.coins
	t0 = Time.get_ticks_msec()
	_do_action(gus, "buy_wood")
	t = 0.0
	while story.playing != "act1_wood" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("buying wood starts the pen beat (%s)" % story.playing, story.playing == "act1_wood")
	await _act1_until_done(30.0)
	_villager_action(gus, "buy_wood")
	_villager_action(gus, "buy_wood")
	hud.hide_dialogue()
	_check("three packs of wood (%d wood, coins %d→%d)" % [Game.count("wood"), coins1, Game.coins], Game.count("wood") == 15 and Game.coins == coins1 - 45)
	# craft the gate, then build a 3 by 3 pen near the strays
	homestead.ui.toggle_craft()
	await _wait(0.3)
	await _shot("26_act1_crafting.png")
	_check("crafting a gate takes 2 wood", homestead.craft("gate") and Game.count("gate") == 1 and Game.count("wood") == 13)
	homestead.ui.close_all()
	homestead.set_builder(true)
	var origin := _act1_pen_spot()
	_check("found room for a 3 by 3 pen near the strays (%s)" % str(origin), origin.x > -100)
	var o := Vector2i(origin)
	homestead.set_builder(false)
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(o.x - 1.5, 0, o.y + 1.5))) # out to where the pen goes
	t = 0.0
	while not player.path.is_empty() and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	Game.hour = 10.0
	homestead.set_builder(true)
	var ring: Array = []
	for i in 3:
		ring.append(Homestead.edge_key(o.x + i, o.y, true))
		ring.append(Homestead.edge_key(o.x + i, o.y + 3, true))
		ring.append(Homestead.edge_key(o.x + 3, o.y + i, false))
		ring.append(Homestead.edge_key(o.x, o.y + i, false))
	var gate_key := Homestead.edge_key(o.x, o.y + 1, false) # the west side, toward the pond
	var cam0 := cam_target
	cam_target = Vector3(o.x + 1.5, 0, o.y + 1.5)
	var placed := 0
	for k in ring:
		if k != gate_key and homestead.place(k, "fence") == "":
			placed += 1
		if placed == 6:
			await _wait(0.4)
			homestead._update_ghost(cam.unproject_position(Vector3(o.x + 0.5, 0, o.y + 3)))
			await _shot("26_act1_building.png")
	var spare := Homestead.edge_key(o.x + 1, o.y + 1, true) # inside the pen-to-be
	var wood_before := Game.count("wood")
	var spare_ok := homestead.place(spare, "fence") == "" and homestead.remove(spare)
	_check("a panel taken back up gives its wood back (%d→%d)" % [wood_before, Game.count("wood")], spare_ok and Game.count("wood") == wood_before)
	_check("eleven panels, and no pen until the gate is in (%d, pen %s)" % [placed, str(homestead.has_pen())], placed == 11 and not homestead.has_pen())
	_check("the fence closes the path grid", not _walkable(_cell(Vector3(o.x + 1.5, 0, o.y))))
	homestead.place(gate_key, "gate")
	t = 0.0
	while story.playing != "act1_pen" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	_check("the gate closes the pen: 'pen_built' (%s), a 3 by 3 pen (%s), the sheep's pen moved there, the builder off" % [story.playing, str(homestead.pen_inner)],
		story.playing == "act1_pen" and homestead.has_pen() and homestead.pen_cells.size() == 9 and not homestead.building
		and pen_rect.has_point(Vector2(o.x + 1.5, o.y + 1.5)) and Game.count("wood") == 2 and Game.count("gate") == 0)
	_check("the gate lets her through", _walkable(_cell(Vector3(o.x, 0, o.y + 1.5))))
	await _act1_until_done(30.0)
	await _wait(0.6)
	cam_target = Vector3(o.x + 0.5, 0, o.y + 1.5)
	cam_dist = 9.0
	await _wait(0.8)
	await _shot("26_act1_pen.png")
	# herding: the strays move off from her
	var s0 = homestead.strays[0]
	s0.position = Vector3(o.x - 2.0, 0, o.y + 1.5)
	player.walk([])
	player.position = s0.position + Vector3(-1.4, 0, 0)
	var d0: float = s0.position.distance_to(player.position)
	await _wait(1.2)
	var d1: float = s0.position.distance_to(player.position)
	_check("a stray shies away from her (%.1f → %.1f m)" % [d0, d1], d1 > d0 + 0.4)
	_check("a fence turns her aside (%s)" % str(homestead._crosses_fence(Vector3(o.x + 1.5, 0, o.y - 0.3), Vector3(o.x + 1.5, 0, o.y + 0.3))), homestead._crosses_fence(Vector3(o.x + 1.5, 0, o.y - 0.3), Vector3(o.x + 1.5, 0, o.y + 0.3)))
	player.position = Vector3(o.x - 4.0, 0, o.y + 1.5)
	for s in homestead.strays.duplicate(): # herded through the gate
		s.position = Vector3(o.x + 1.5, 0, o.y + 1.5)
	t = 0.0
	while story.playing != "act1_flock" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	_check("both strays in the pen: 'sheep_penned' (%s), two sheep in her flock (%d)" % [story.playing, Game.sheep_count],
		story.playing == "act1_flock" and Game.sheep_count == 2 and sheep_list.size() == 2 and homestead.strays.is_empty() and Game.flag("act1_flock") == true)
	await _act1_until_done(30.0)
	cam_target = cam0
	_check("off to market ('%s')" % hud.goal_label.text, Game.flag("act1_fence_done") == true and hud.goal_label.text.contains("market"))
	var buy_ok: bool = _villager_actions(theo).filter(func(x): return x["id"] == "buy_sheep").size() == 1
	_check("Theo sells sheep now there's a pen", buy_ok)
	# market day: walk into Maple Grove to Rosa's stall
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
	day0 = Game.day
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
	# rent: 20c every seven days, into Gran's tin
	var due := int(Game.flag("rent_due", 0))
	homestead._on_day(due)
	var owed := homestead.rent_owed()
	var coins2 := Game.coins
	var paid := homestead.pay_rent()
	_check("rent comes due a week in (%dc owed on day %d) and goes in Gran's tin (coins %d→%d, next due day %d)" % [owed, due, coins2, Game.coins, int(Game.flag("rent_due", 0))],
		owed == 20 and paid and Game.coins == coins2 - 20 and homestead.rent_owed() == 0 and int(Game.flag("rent_due", 0)) == due + 7)
	# how long it takes a person: reading time for every line shown, choices, walks and the knit
	var read := 0.0
	var choices := 0
	for l in story.shown:
		var line := str(l)
		if line.begins_with("> "):
			choices += 1
		read += 0.7 + line.length() / 17.0
	var titles := 3 * 2.6
	var total := read + choices * 3.0 + walk_secs + titles + 120.0 # and a couple of minutes building and herding
	_check("Act 1 plays in about 15 minutes (%d lines, %d choices: %.0fs reading + %.0fs walking/knitting + building = %.1f min)" % [story.shown.size(), choices, read + choices * 3.0 + titles, walk_secs, total / 60.0],
		total > 600.0 and total < 1500.0)
	var d := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	Game.flags = {}
	Game.from_dict(d)
	homestead.apply()
	_check("Act 1 progress and the pen survive a save (journal %d, fences %d, pen %d cells, sheep %d)" % [Game.journal().size(), homestead.fences.size(), homestead.pen_cells.size(), Game.sheep_count],
		Game.flag("act1_done") == true and Game.flag("seen_act1_porch") == true and Game.journal().size() == journal0 + 3
		and homestead.fences.size() == 12 and homestead.pen_cells.size() == 9 and Game.sheep_count == 2)
	story.auto = false
	story.auto_line = 0.08
	homestead.reset_sandbox() # the rest of the autotest plays on the old farm: its pen and three sheep
	_check("the sandbox farm is back for the other checks (pen %s, %d sheep)" % [str(World.pen.visible), sheep_list.size()], World.pen.visible and sheep_list.size() == Game.START_SHEEP and homestead.fences.is_empty())


## Where a 3 by 3 pen fits near the strays: the first corner, nearest the pond first, whose twelve
## fence edges are all free. Vector2(-999, -999) if none.
func _act1_pen_spot() -> Vector2:
	var best := Vector2(-999, -999)
	var best_d := 1e9
	for x in range(8, 22):
		for z in range(-18, -8):
			var ok := true
			for i in 3:
				for k in [Homestead.edge_key(x + i, z, true), Homestead.edge_key(x + i, z + 3, true), Homestead.edge_key(x + 3, z + i, false), Homestead.edge_key(x, z + i, false)]:
					if homestead.edge_problem(k) != "":
						ok = false
			# and room outside the gate for the strays to come in
			if ok and _walkable(_cell(Vector3(x - 0.5, 0, z + 1.5))) and _walkable(_cell(Vector3(x - 2.0, 0, z + 1.5))):
				var dd := Vector2(x + 1.5, z + 1.5).distance_to(Vector2(Homestead.STRAYS_AT.x + 3.5, Homestead.STRAYS_AT.z))
				if dd < best_d:
					best_d = dd
					best = Vector2(x, z)
	return best


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


## Plays the opening of Act 1 from a new game at reading pace (the bus, the sign, the tour, Gran's note), then quits. Record it:
##   Godot --path . --resolution 1280x800 --write-movie opening.avi --fixed-fps 30 -- --capture
func _capture_opening() -> void:
	story.auto = true
	story.cinematic = true
	story.auto_line = 0.6
	story.auto_choices = [0, 1, 0, 1, 0]
	await _wait(0.5)
	_begin_new_story()
	await _act1_until_done(400.0)
	await _wait(1.5)
	player.walk(_find_path(player.position, Vector3(5.6, 0, 3.0)))
	var t := 0.0
	while story.playing != "act1_note" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	await _act1_until_done(300.0)
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
		"sdfgi": func(on): env.sdfgi_enabled = on,
		"morning mist": func(on): lighting.mist_enabled = on,
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
	for view in [["town noon", Vector3(53, 0, -3), 30.0, 10.8], ["farm night", Vector3(8, 0, -2), 23.0, 21.5], ["woods dawn", Lighting.SHOT_TARGET, Lighting.SHOT_DIST, 6.6]]:
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
		# the farm props and the bakery stall (art/world_assets/farm_props, bakery_stall); fireflies at night
		["asset_bakery_stall.png", Vector3(44.2, 0.6, -7.6), 6.5, 20.0, 10.5, 14.0],
		["asset_bakery_stall_night.png", Vector3(44.2, 0.6, -7.6), 6.5, 20.0, 21.5, 14.0],
		["asset_chalkboard.png", Vector3(42.85, 0.1, -7.0), 2.6, 20.0, 10.5, 14.0],
		["asset_pen.png", Vector3(20.0, 0.0, -1.0), 11.0, 25.0, 10.5, 30.0],
		["asset_barn_hay.png", Vector3(21.5, 0.2, -7.5), 12.0, 15.0, 10.5, 22.0],
		["asset_scarecrow.png", Vector3(13.0, 0.5, -2.6), 4.5, 15.0, 10.5, 10.0],
		["asset_fireflies.png", Vector3(13.5, 0.0, 0.5), 9.0, 20.0, 22.5, 20.0],
	]
	# pumpkins at each stage on the back row, turnips on the next (Plot.stage(): 0, 1/3, 2/3, ripe)
	for k in 4:
		for row in 2:
			var pl = plots[row * 4 + k]
			pl.plant("pumpkin" if row == 0 else "turnip")
			pl.growth = pl.hours_needed() * [0.0, 0.4, 0.75, 1.0][k]
			pl.water()
	spawn_prop("bus", "asset_bus", Vector3(31.0, 0, 3.0))
	# the stall stands wherever Alex set it in the world editor: frame it there, from its front
	var stall_el = god.by_key.get("decor_bakery_stall@44.25,-7.70") if god else null
	if stall_el:
		for v in views:
			if str(v[0]).begins_with("asset_bakery_stall"):
				v[1] = stall_el.xf.origin + Vector3(0, 0.6, 0)
				v[3] = 20.0 + rad_to_deg(GodMode._yaw(stall_el.xf))
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
		if str(v[0]).begins_with("asset_fireflies"): # give them time to gather round here and fade in
			fireflies._gather_anchors()
			for i in Fireflies.COUNT:
				fireflies._reset(i)
			await _wait(4.0)
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
		# the name: painted on its board (a Label3D) or a carved hanging sign (art/world_assets/shop_signs)
		var named := b.find_children("HangingSign", "Node3D", true, false).any(func(s: Node) -> bool: return s.find_children("*", "MeshInstance3D", true, false).size() > 0)
		for l in b.find_children("*", "Label3D", true, false):
			named = named or (l as Label3D).text != ""
		if meshes > 0 and named:
			built.append(str(b.get_meta("building_model", "")))
	built.sort()
	var want: Array[String] = ["bakery", "office", "shop"]
	_check("town buildings are the modelled Yarn Barn, Heart Bakery, Willow Homes and Builder's Delight, each with its sign (%s)" % ", ".join(built),
		want.all(func(k: String) -> bool: return k in built))
	# the carved hanging signs over the shops (town.gd HANGING_SIGNS), on the walls, under the eaves
	var hung: Array[String] = []
	for b in find_children("Building_*", "Node3D", true, false):
		for s in b.find_children("HangingSign", "Node3D", true, false):
			var top := (s as Node3D).global_position.y - (b as Node3D).global_position.y
			if top > 2.7 and top < 3.4:
				hung.append(str(b.get_meta("building_model", "")))
	hung.sort()
	_check("the carved signs hang over the Yarn Barn, Heart Bakery, Willow Homes and Builder's Delight (%s)" % ", ".join(hung),
		["bakery", "office", "shop"].all(func(k: String) -> bool: return k in hung))
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
	var flies_day: int = fireflies.lit_count()
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
	var flies_rain: int = fireflies.lit_count()
	Game.set_flag("weather", "clear")
	await _wait(4.5)
	var flies_night: int = fireflies.lit_count()
	_check("fireflies glow round the farm on a clear night, not by day or in the rain (day %d, rain %d, clear night %d of %d)" % [flies_day, flies_rain, flies_night, Fireflies.COUNT],
		flies_day == 0 and flies_rain < 5 and flies_night >= 20)
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
	if "--only=bench" in OS.get_cmdline_user_args(): # just the bench checks and their two pictures, in seconds
		await _wait(1.5)
		await _bench_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=house" in OS.get_cmdline_user_args(): # just the house furniture checks, with every piece set out for a picture
		await _wait(1.5)
		await _house_checks(true)
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=shops" in OS.get_cmdline_user_args(): # just the walk-in shops and their pictures
		await _wait(1.5)
		await _shop_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=barn" in OS.get_cmdline_user_args(): # just the barn checks and their pictures
		await _wait(1.5)
		await _barn_checks()
		await _flock_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=face" in OS.get_cmdline_user_args(): # just the eyes: blink, moods, sleep, where they look
		await _wait(1.5)
		await _face_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=act1" in OS.get_cmdline_user_args(): # just Act 1, from the bus to the porch (a few minutes)
		await _wait(1.5)
		await _act1_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=light" in OS.get_cmdline_user_args(): # just the lighting: the bake, the morning mist, dawn, noon and dusk
		await _wait(1.5)
		await _light_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=hud" in OS.get_cmdline_user_args(): # just the hotbar, bag, menu and needs checks
		await _wait(1.5)
		await _hud_checks()
		await _tool_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=dog" in OS.get_cmdline_user_args(): # just the dog: his model and loops, playing him, his gaits
		await _wait(1.5)
		await _dog_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
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
	await _face_checks()
	var happy0 := Game.happiness

	await _graphics_checks()
	await _character_checks()
	await _bed_checks()
	await _knit_checks()
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
		Game.happiness > happy0 + 8.0 and Game.worn_quality >= 2)

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
	await _house_checks(false)
	await _bench_checks()
	await _barn_checks()
	await _shop_checks()
	await _flock_checks()
	await _light_checks()
	await _dog_checks()
	await _hud_checks() # these two last: the tool checks walk her round the farm and dig it up
	await _tool_checks()
	await _god_checks() # ends by building the world again from the layout it saved, then "AUTOTEST DONE"


## The lighting (scripts/lighting.gd, art/world_assets/light_bake): the props carry their Cycles
## light bake, the morning mist comes and goes with the hour, SDFGI is on at High, and a picture of
## the same corner of the woods at dawn, noon and dusk (48_light_*.png).
func _light_checks() -> void:
	var was_running: bool = Game.time_running
	Game.time_running = false
	_set_cam_lock(false)
	var missing: Array = []
	for id in Lighting.BAKED:
		var path := "res://assets/props/%s.glb" % id
		if not ResourceLoader.exists(path):
			missing.append(id + " (no model)")
			continue
		var inst := (load(path) as PackedScene).instantiate()
		if Lighting.baked_ao_count(inst) == 0:
			missing.append(id)
		inst.free()
	_check("the %d baked props carry their Cycles light bake (ambient occlusion on UV2)%s" % [Lighting.BAKED.size(), "" if missing.is_empty() else ": missing " + ", ".join(missing)], missing.is_empty())
	_check("SDFGI is on at High graphics", gfx == 2 and env.sdfgi_enabled)
	var hours := [["dawn", 6.6], ["noon", 12.5], ["dusk", 18.7]]
	var mist_at := {}
	for v in hours:
		Game.hour = v[1]
		player.position = Vector3(2.0, 0, 9.0)
		cam_yaw = deg_to_rad(Lighting.SHOT_YAW)
		cam_yaw_goal = cam_yaw
		cam_target = Lighting.SHOT_TARGET
		cam_dist = Lighting.SHOT_DIST
		cam_pitch = Lighting.SHOT_PITCH
		cam_glide = {"pos": Lighting.SHOT_TARGET, "dist": Lighting.SHOT_DIST, "pitch": Lighting.SHOT_PITCH}
		await _wait(2.5) # the volumetric fog settles over a few frames
		mist_at[v[0]] = lighting.mist
		if v[0] == "dawn":
			var ms := await _frame_ms()
			print("      dawn, mist and shafts: %.1f ms a frame (%.0f fps), 3D at %d%%" % [ms, 1000.0 / ms, roundi(get_viewport().scaling_3d_scale * 100)])
			_check("morning mist at 6:36: thick, in volumetric fog, and the sun lights it (%.2f)" % lighting.mist,
				lighting.mist > 0.8 and lighting.mist_volume.visible and env.volumetric_fog_enabled and sun.light_volumetric_fog_energy > 2.5)
		await _shot("48_light_%s.png" % v[0])
		cam_glide = {}
	_check("the mist has burnt off by noon and stays away at dusk (%.2f, %.2f)" % [mist_at["noon"], mist_at["dusk"]],
		mist_at["noon"] < 0.01 and mist_at["dusk"] < 0.01 and not lighting.mist_volume.visible)
	Game.hour = 10.0
	await _wait(0.2)
	Game.time_running = was_running


## The furniture of her house (art/world_assets/house_furniture): each of the eleven pieces is its
## model, the fireplace still has its flickering flames and firelight and the lamp its light, and
## she sits on the cushions. showcase (the --only=house run) also sets out the pieces a new house
## doesn't start with, for a picture.
func _house_checks(showcase: bool) -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var ids := ["rocking_chair", "fireplace", "kitchen", "sofa", "armchair", "spinning_wheel", "dining_table", "bookshelf", "wardrobe", "lamp", "plant", "rug_red"]
	var modelled: Array = []
	var flames := 0
	var lights := 0
	for id in ids:
		var f := Furniture.new()
		add_child(f)
		f.setup(id, 0)
		if f.find_children("model", "MeshInstance3D", true, false).size() == 1:
			modelled.append(id)
		if id == "fireplace":
			flames = f.flames.size()
			lights += f.lights.size()
		if id == "lamp":
			lights += f.lights.size()
		f.queue_free()
	_check("her house's furniture is the new models (%d of %d; the fire has %d flames, fire and lamp %d lights)" % [modelled.size(), ids.size(), flames, lights],
		modelled.size() == ids.size() and flames == 3 and lights == 2)
	var floors := get_tree().get_nodes_in_group("planks_floor")
	var linings := get_tree().get_nodes_in_group("planks_wall")
	var floor_boards := 0
	for f in floors:
		floor_boards += int(f.get_meta("boards", 0))
	var shades := {}
	for f in floors:
		shades[str(f.get_meta("shade", ""))] = true
	_check("every building has a plank floor in its own shade, and the houses boarded walls (%d floors of %d boards in %d shades, %d walls boarded)" % [floors.size(), floor_boards, shades.size(), linings.size()],
		floors.size() >= 6 and shades.size() == floors.size() and floor_boards > 250 and linings.size() >= 9)
	if not showcase:
		return
	for extra in [["sofa", Vector3(5.5, 0, 3.0), 3], ["armchair", Vector3(3.5, 0, 5.0), 2], ["dining_table", Vector3(6.0, 0, 5.0), 0],
			["wardrobe", Vector3(7.5, 0, 3.0), 3], ["spinning_wheel", Vector3(5.0, 0, 1.5), 0]]:
		_spawn_furniture(extra[0], extra[1], extra[2])
	_set_cam_lock(false)
	player.position = Vector3(4.2, 0, 4.2)
	cam_target = Vector3(4.0, 0.5, 3.0)
	cam_dist = 14.0
	await _wait(2.0)
	await _shot("46_house.png")
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	_perform(chair, "rest")
	cam_target = chair.global_position
	cam_dist = 6.0
	await _wait(1.8)
	await _shot("46_rocking_chair.png")
	await _wait(3.0)
	var sofa = furniture.filter(func(f): return f.item_id == "sofa")[0]
	_perform(sofa, "rest")
	cam_target = sofa.global_position
	await _wait(1.8)
	await _shot("46_sofa.png")
	cam_target = Vector3(1.6, 0.6, 1.6)
	cam_dist = 7.5
	await _wait(3.0)
	await _shot("46_hearth_kitchen.png")
	_set_cam_lock(true)


## The barn (art/world_assets/barn): the model stands where the box barn stood, she can walk in
## through the doors, and it opens up while she is inside: doors swung back, roof hidden, the
## walls toward the camera cut down to stubs. It closes up again when she leaves.
func _barn_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var parts: Dictionary = World.barn_parts
	_check("the barn is the model, in its parts (%d: base, roof, interior, two doors, four stall gates, four walls and their stubs)" % parts.size(),
		parts.size() == 17 and parts.has("roof") and parts.has("door_l") and parts.has("interior") and parts.has("wall_front_low") and parts.has("gate_l1"))
	if parts.is_empty() or not World.barn.visible:
		return
	var xf: Transform3D = World.barn.global_transform
	var out_front: Vector3 = xf * Vector3(0.25, 0, 6.4)
	var aisle: Vector3 = xf * Vector3(0.25, 0, -0.4)
	out_front.y = 0.0
	aisle.y = 0.0
	player.position = out_front
	_set_cam_lock(false)
	cam_target = xf.origin + Vector3(0, 1.5, 0)
	cam_dist = 19.0
	await _wait(1.8)
	var shut: bool = World.barn_open < 0.05 and (parts["roof"] as Node3D).visible and not World.barn_inside
	await _shot("44_barn.png")
	player.walk(_find_path(player.position, aisle))
	await _walk_wait(25.0)
	cam_target = aisle
	cam_dist = 12.5
	await _wait(1.6)
	var cut := 0
	for side in World.BARN_WALLS:
		if (parts["wall_%s_low" % side] as Node3D).visible and not (parts["wall_" + side] as Node3D).visible:
			cut += 1
	_check("she walks into the barn through its doors and it opens up round her (%.1f m from the aisle, doors %.0f%% open, roof %s, %d walls cut down)" % [player.position.distance_to(aisle), World.barn_open * 100.0, "hidden" if not (parts["roof"] as Node3D).visible else "shown", cut],
		shut and player.position.distance_to(aisle) < 0.8 and World.barn_inside and World.barn_open > 0.95 and not (parts["roof"] as Node3D).visible and cut >= 1 and cut <= 2)
	await _shot("44_barn_inside.png")
	player.walk(_find_path(player.position, out_front))
	await _walk_wait(25.0)
	cam_target = xf.origin + Vector3(0, 1.5, 0)
	cam_dist = 19.0
	await _wait(1.8)
	var whole: bool = World.BARN_WALLS.keys().all(func(s): return (parts["wall_" + s] as Node3D).visible and not (parts["wall_%s_low" % s] as Node3D).visible)
	_check("the barn closes up again when she leaves (doors %.0f%% open, roof %s)" % [World.barn_open * 100.0, "shown" if (parts["roof"] as Node3D).visible else "hidden"],
		not World.barn_inside and World.barn_open < 0.05 and (parts["roof"] as Node3D).visible and whole and player.position.distance_to(out_front) < 0.8)
	_set_cam_lock(true)


## The shops (scripts/interiors.gd): she walks in through each door and it opens up round her
## (door swung in, roof hidden, the walls toward the camera cut down); its shopkeeper is behind
## the counter, and she talks to them from across it (Hazel sells her a warm croissant). Each
## closes up again when she leaves.
func _shop_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var furnished: bool = Interiors.shops.size() >= 4
	var rooms := []
	for sh in Interiors.shops.values():
		var room: Node = sh.node.find_child("Furnishings", false, false)
		rooms.append("%s %d parts, %d pieces" % [sh.id, sh.parts.size(), room.get_child_count() if room else 0])
		furnished = furnished and sh.parts.size() >= 11 and room != null and room.get_child_count() >= 6
	_check("the walk-in shops are in their parts and furnished (%s)" % ", ".join(rooms), furnished)
	var keepers := {}
	for d in _villager_defs():
		if d.has("works_in"):
			keepers[str(d["works_in"])] = str(d["id"])
			set_home(str(d["id"])) # back behind their counters, wherever earlier scenes sent them
	Game.coins = maxi(Game.coins, 200)
	for id in ["shop", "bakery", "office", "homegoods"]:
		var s = Interiors.shops.get(id)
		var v := _villager(str(keepers.get(id, "")))
		if s == null or v == null or not s.node.visible:
			_check("%s has its shopkeeper" % id, false)
			continue
		var xf: Transform3D = s.node.global_transform
		var out_front: Vector3 = xf * Vector3(0, 0, s.size.y * 0.5 + 2.4)
		out_front.y = 0.0
		hud.hide_dialogue()
		player.walk([])
		player.position = out_front
		_set_cam_lock(false)
		cam_target = xf.origin + Vector3(0, 1.5, 0)
		cam_dist = 16.0
		await _wait(1.6)
		var shut: bool = s.open < 0.05 and (s.parts["roof"] as Node3D).visible and not s.inside
		await _shot("46_%s.png" % id)
		var k: Dictionary = Interiors.keeper(id)
		var at_post: bool = v.position.distance_to(k["pos"]) < 0.8 and Interiors.inside_of(v.position) == id
		var price := _hazel_price()
		var c0 := Game.coins
		if id == "bakery":
			Game.fullness = 40.0
			_do_action(v, "buy_pastry")
		else:
			_do_action(v, "talk")
		await _walk_wait(30.0)
		cam_target = player.position + Vector3(0, 1.0, 0)
		cam_dist = 11.0
		await _wait(1.4)
		var cut := 0
		for side in Interiors.WALLS:
			if (s.parts["wall_%s_low" % side] as Node3D).visible and not (s.parts["wall_" + side] as Node3D).visible:
				cut += 1
		_check("she walks into the %s through its door and it opens up round her (shut before %s, inside %s, %.1f m from the counter, door %.0f%% open, roof %s, %d walls cut down)" % [id, shut, s.inside, player.position.distance_to(k["talk"]), s.open * 100.0, "hidden" if not (s.parts["roof"] as Node3D).visible else "shown", cut],
			shut and s.inside and player.position.distance_to(k["talk"]) < 0.8 and s.open > 0.95 and not (s.parts["roof"] as Node3D).visible and cut >= 1 and cut <= 2)
		_check("%s is behind the counter inside, and talks to her across it (%.1f m from their post)" % [v.title, v.position.distance_to(k["pos"])],
			at_post and v.position.distance_to(k["pos"]) < 1.0 and hud.dlg_panel.visible)
		if id == "bakery":
			_check("Hazel sells her a warm croissant (%dc, food 40 -> %.0f)" % [c0 - Game.coins, Game.fullness],
				Game.coins == c0 - price and Game.fullness > 40.0 + PASTRY_FOOD - 3.0) # less what she burned walking over
		await _shot("46_%s_inside.png" % id)
		hud.hide_dialogue()
		player.walk(_find_path(player.position, out_front))
		await _walk_wait(25.0)
		cam_target = xf.origin + Vector3(0, 1.5, 0)
		cam_dist = 16.0
		await _wait(1.6)
		var whole: bool = Interiors.WALLS.keys().all(func(w): return (s.parts["wall_" + w] as Node3D).visible and not (s.parts["wall_%s_low" % w] as Node3D).visible)
		_check("the %s closes up again when she leaves (door %.0f%% open, roof %s)" % [id, s.open * 100.0, "shown" if (s.parts["roof"] as Node3D).visible else "hidden"],
			not s.inside and s.open < 0.05 and (s.parts["roof"] as Node3D).visible and whole and player.position.distance_to(out_front) < 0.8)
	# a picture of each carved hanging sign (art/world_assets/shop_signs) where it hangs, the Mayor's
	# Office's among them: 46_sign_<building>.png (_polish_checks checks where they hang)
	for b in find_children("Building_*", "Node3D", true, false):
		var hs: Array[Node] = b.find_children("HangingSign", "Node3D", true, false)
		var own: bool = str(b.get_meta("building_model", "")) in Town.OWN_SIGN # the café wears its own plaque
		if hs.is_empty() and not own:
			continue
		var sg := (b as Node3D) if own else (hs[0] as Node3D)
		var front: Vector3 = sg.global_position + (b as Node3D).global_transform.basis.z * (9.0 if own else 4.5)
		front.y = 0.0
		hud.hide_dialogue()
		player.walk([])
		player.position = front
		_set_cam_lock(false)
		cam_target = sg.global_position + (Vector3(0, 2.8, 0) if own else Vector3(0, -0.8, 0))
		cam_dist = 16.0 if own else 9.0
		await _wait(1.2)
		await _shot("46_sign_%s.png" % str(b.get_meta("building_model", "")))
	_set_cam_lock(true)


## The flock's bedtime: at dusk the sheep walk from the pen to their stalls in the barn, the stall
## gates and the barn doors shutting behind them, and at first light they walk back out. (The
## rest of the autotest runs with bedtime off, so its sheep stay where it expects them.)
func _flock_checks() -> void:
	if not World.barn_ready() or sheep_list.is_empty():
		return
	hud.hide_dialogue()
	var xf: Transform3D = World.barn.global_transform
	var pen_mid := Vector3(pen_rect.get_center().x, 0, pen_rect.get_center().y)
	for s in sheep_list: # a known start: everyone in the pen
		s.place(Vector3(randf_range(s.pen.position.x, s.pen.end.x), 0, randf_range(s.pen.position.y, s.pen.end.y)), false)
	player.position = pen_mid + (pen_mid - xf.origin).normalized() * 6.0 # out of the way, on the far side of the pen
	_set_cam_lock(false)
	cam_target = (pen_mid + xf.origin) * 0.5
	cam_dist = 26.0
	flock_bedtime = true
	_flock_seen = true
	Game.hour = 20.0
	await _wait(7.0)
	var walking: int = sheep_list.filter(func(s): return s.heading_in and not s.route.is_empty()).size()
	await _shot("45_flock_going_in.png")
	var t := 0.0
	while t < 75.0 and not sheep_list.all(func(s): return s.housed):
		await _wait(0.5)
		t += 0.5
	await _wait(2.5) # gates and doors swing shut
	var housed: int = sheep_list.filter(func(s): return s.housed).size()
	var in_place := true
	for i in sheep_list.size():
		in_place = in_place and sheep_list[i].position.distance_to(World.barn_stall(i)["stall"]) < 0.35
	var gates_shut: bool = World.barn_gate.values().all(func(g): return float(g) < 0.05)
	_check("at dusk the flock walks from the pen to its stalls in the barn (%d setting off, %d of %d housed after %.0f s, gates %s, doors %.0f%% open)" % [walking, housed, sheep_list.size(), t, "shut" if gates_shut else "open", World.barn_open * 100.0],
		walking >= 1 and housed == sheep_list.size() and in_place and gates_shut and World.barn_open < 0.05)
	# a look inside: she steps into the aisle, which lifts the roof off
	var aisle: Vector3 = xf * Vector3(0.25, 0, 0.9)
	aisle.y = 0.0
	player.position = aisle
	cam_target = xf.origin
	cam_dist = 12.5
	await _wait(1.8)
	await _shot("45_flock_in_stalls.png")
	player.position = pen_mid + (pen_mid - xf.origin).normalized() * 6.0
	cam_target = (pen_mid + xf.origin) * 0.5
	cam_dist = 26.0
	Game.hour = 7.0
	t = 0.0
	var home := func(s) -> bool: return not s.housed and s.route.is_empty() and pen_rect.has_point(Vector2(s.position.x, s.position.z))
	while t < 75.0 and not sheep_list.all(home):
		await _wait(0.5)
		t += 0.5
	_check("at first light they walk back out to the pen (%d of %d in the pen after %.0f s)" % [sheep_list.filter(home).size(), sheep_list.size(), t],
		sheep_list.all(home))
	flock_bedtime = false
	_set_cam_lock(true)


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
	# the trash can is a model too; the ones out in the world stand by benches (Alex can move them in the editor)
	var can := Furniture.new()
	add_child(can)
	can.setup("trash_can", 0)
	var can_model: bool = can.find_children("model", "MeshInstance3D", true, false).size() == 1
	can.queue_free()
	var cans: Array = []
	for n in find_children("*", "Node3D", true, false):
		if n is Furniture and n != can and not n.is_ghost and n.item_id == "trash_can":
			cans.append(n)
	var by_bench: Array = cans.filter(func(c): return benches.any(func(b): return b.global_position.distance_to(c.global_position) < 3.0))
	_check("the trash can is the barrel model (%d out in the world, %d of them by a bench)" % [cans.size(), by_bench.size()], can_model)
	_set_cam_lock(false)
	for i in mini(by_bench.size(), 3):
		player.position = by_bench[i].global_position + Vector3(2.5, 0, 2.5)
		cam_target = by_bench[i].global_position
		cam_dist = 7.5
		await _wait(1.6)
		await _shot("43_trash_can_%d.png" % i)
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


## Guardrails: whatever is in the world now, and whatever is added later, the world editor can
## reach it. Every piece of furniture anywhere (her house, the yard, the town's decor) is something
## it picks up, or part of something it picks up (a shop's furnishings move with the shop); every
## model in assets/props and every catalog piece is in the Place list; and her house's furniture
## can be moved and is kept in the layout's "house" list for new games.
func _god_guardrail_checks() -> void:
	god.sync_home()
	var owned := {}
	for el in god.els:
		if el.node != null:
			owned[el.node] = true
	var loose: Array = []
	for n in find_children("*", "Node3D", true, false):
		if not (n is Furniture) or not (n as Node3D).is_visible_in_tree() or n == ghost:
			continue
		var up: Node = n
		while up != null and up != self and not owned.has(up):
			up = up.get_parent()
		if up == null or up == self:
			loose.append(str(n.get("item_id")))
	_check("god mode guardrail: every piece of furniture in the world can be picked up (%d not: %s)" % [loose.size(), str(loose)], loose.is_empty())
	var options := {}
	for o in god.place_options():
		options[str(o[0]).get_slice(":", 1)] = true
	var unplaceable: Array = []
	for f in DirAccess.get_files_at("res://assets/props"):
		var m := f.get_basename()
		if f.ends_with(".glb") and not GodMode._starts(m, GodMode.NOT_PLACED) and not options.has(m):
			var by_catalog := false
			for id in Catalog.ITEMS:
				if str(Catalog.ITEMS[id].get("model", "")).get_file().get_basename() == m and options.has(str(id)):
					by_catalog = true
			if not by_catalog:
				unplaceable.append(m)
	_check("god mode guardrail: every model in assets/props can be placed (%d can't: %s)" % [unplaceable.size(), str(unplaceable)], unplaceable.is_empty())
	var beds: Array = god.els.filter(func(e): return e.home and e.node.get("item_id") == "bed")
	if beds.is_empty():
		_check("god mode: her bed is in the editor", false)
		return
	var bed: GodMode.El = beds[0]
	var from := bed.xf
	god.select(bed)
	bed.xf.origin += Vector3(-0.5, 0, 0)
	god._edited(bed, from, false)
	var listed: Array = god.layout().get("house", [])
	var in_list: bool = listed.any(func(e): return e["id"] == "bed" and absf(float(e["x"]) - bed.xf.origin.x) < 0.01)
	_check("god mode: her house's furniture moves (the bed %.2f m) and the layout keeps the house's list for new games (%d pieces, bed there %s)" % [from.origin.distance_to(bed.node.global_position), listed.size(), in_list],
		bed.node.global_position.distance_to(from.origin) > 0.45 and listed.size() == furniture.size() and in_list)
	god.undo()
	god.select(null)
	god.home_edited = false


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
		god.els.size() > 400 and int(kinds.get("trees", 0)) > 50 and int(kinds.get("buildings", 0)) >= Interiors.shops.size() and Interiors.shops.size() >= 4 and int(kinds.get("lamps", 0)) >= 10)
	await _god_guardrail_checks()
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
	await _wait(0.05)
	var early: float = player.speed
	await _wait(0.4)
	_check("she eases into her walk rather than snapping to full speed (%.2f m/s at the first step, then %.2f)" % [early, player.speed],
		early > 0.0 and early < player.speed - 0.3)
	_check("heroine walks briskly on the longer Brisk stride, matching her speed (%s at %.1f m/s, %.2fx)" % [player.body.current(), player.speed, player.body.anim.speed_scale],
		player.body.current() == "Brisk" and player.speed > 1.4 and player.speed < 2.0 and player.body.anim.speed_scale < 1.75 and absf(player.body.anim.speed_scale * player.body.brisk_anim_speed - player.speed) < 0.15)
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
	# 22 body bones, and two eye bones on models with real eyes (tools/add_eyes.py)
	var same_bones: bool = rb != null and rb.bone_names() == player.body.bone_names() and rb.bone_names().size() in [22, 24]
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


## The knitting game: rarity from accuracy and how hard the song is, taps and holds, dropped stitches,
## a whole song played through, and what a sweater of each rarity sells for.
func _knit_checks() -> void:
	var rar := [KnitGame.rarity_for(0.5, 1), KnitGame.rarity_for(0.85, 1), KnitGame.rarity_for(1.0, 1), KnitGame.rarity_for(1.0, 2), KnitGame.rarity_for(1.0, 3), KnitGame.rarity_for(0.96, 2), KnitGame.rarity_for(0.96, 3)]
	_check("rarity comes from accuracy, and harder songs can go higher (%s)" % [rar], rar == [1, 3, 3, 4, 5, 4, 5])
	var songs := KnitGame.load_songs()
	var diffs := songs.map(func(s): return int(s["difficulty"]))
	_check("there are songs from easy to expert, each with notes (%s)" % [diffs], songs.size() >= 4 and diffs[0] == 1 and diffs[-1] == 4 and songs.all(func(s): return s["notes"].size() > 20))
	var hold_song := ""
	for sg in songs:
		if sg["notes"].any(func(n): return float(n[2]) > 0.0):
			hold_song = str(sg["id"])
			break
	knit.open({"auto": false, "fast": 0.0, "silent": true, "song": hold_song, "best": {}})
	await get_tree().process_frame
	var ni := 0
	for i in knit.notes.size():
		if float(knit.notes[i]["hold"]) > 0.0:
			ni = i
			break
	var hn: Dictionary = knit.notes[ni]
	var lane := int(hn["lane"])
	for i in ni: # the notes before it are let go by; they drop
		knit.notes[i]["state"] = 4
		knit.ptr[int(knit.notes[i]["lane"])] = maxi(knit.ptr[int(knit.notes[i]["lane"])], knit.lane_notes[int(knit.notes[i]["lane"])].find(i) + 1)
	knit.now = float(hn["t"]) - 0.5
	knit.press(lane)
	_check("pressing a note long before it arrives does nothing (stitches %d)" % knit.stitches.size(), knit.stitches.size() == 0)
	knit.now = float(hn["t"]) + 0.02
	knit.press(lane)
	var made: int = knit.stitches.size()
	knit.now = float(hn["t"]) + float(hn["hold"]) * 0.5
	await get_tree().process_frame
	var mid_hold: bool = knit.holding[lane] == ni
	knit.now = float(hn["t"]) + float(hn["hold"])
	knit.release(lane)
	_check("a hold is two stitches: pressed on the beat and let go at the end (made %d then %d, holding mid-way %s, perfect %d)" % [made, knit.stitches.size(), mid_hold, knit.counts[0]],
		made == 1 and mid_hold and knit.stitches.size() == 2 and knit.counts[0] == 2 and knit.combo == 2)
	knit.now = float(hn["t"]) + float(hn["hold"]) + 3.0
	await get_tree().process_frame
	_check("notes that go by unplayed are dropped stitches and break the run (dropped %d, run %d)" % [knit.counts[3], knit.combo], knit.counts[3] >= 1 and knit.combo == 0)
	knit.finished.disconnect(_on_knit_finished)
	knit._finish(true)
	knit.finished.connect(_on_knit_finished)
	# a whole song, played perfectly at speed, on the hardest one
	var results := []
	var catcher := func(r): results.append(r)
	knit.finished.disconnect(_on_knit_finished)
	knit.finished.connect(catcher)
	knit.open({"auto": true, "fast": 80.0, "silent": true, "song": str(songs[-1]["id"]), "best": {}})
	var guard := 0
	while results.is_empty() and guard < 600:
		await get_tree().process_frame
		guard += 1
	knit.finished.disconnect(catcher)
	knit.finished.connect(_on_knit_finished)
	var res: Dictionary = results[0] if not results.is_empty() else {}
	_check("a whole expert song played perfectly gives a Legendary sweater (accuracy %.3f, rarity %s, run %d)" % [float(res.get("accuracy", 0.0)), res.get("rarity"), int(res.get("max_combo", 0))],
		float(res.get("accuracy", 0.0)) > 0.99 and int(res.get("rarity", 0)) == 5 and int(res.get("max_combo", 0)) > 50)
	var sw0 := Game.sweaters.duplicate()
	var inv0 := Game.count("sweater")
	Game.add_sweater(5)
	Game.add_sweater(1)
	var worth := Game.sweater_worth(100)
	Game.take_item("sweater", 2) # the lowest go first
	_check("a sweater sells by rarity: Legendary 240, Common 60 on a base of 100 (worth %d; carrying %d, rarities %s)" % [worth, Game.count("sweater"), Game.sweaters],
		worth == Game.sweater_worth(100) + 240 + 60 and Game.count("sweater") == inv0 and Game.sweaters == sw0 and Game.sweaters.size() == inv0)


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
	var eyes_shut: bool = player.body.face != null and player.body.face.closed
	await _shot("44_nap_in_bed.png")
	_check("napping, her eyes are shut under the tartan (shut %s, cover cloth %s)" % [eyes_shut, Catalog.TARTAN_TEX.get_file()], eyes_shut or player.body.face == null)
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


## The pared-down HUD: the hotbar and bag, the menu behind Esc, the need bars top left,
## and the frame counter and camera buttons off until settings turns them on.
## Real eyes (scripts/face.gd, models from tools/add_eyes.py): Nora and Rowan have them, they blink,
## take a story line's mood, shut for sleep and turn toward what she looks at.
## The dog: the model has four legs' worth of loops, Tab hands him the clicks, he trots and gallops
## at the speeds his strides were keyed for (so his paws don't slide), Tab hands them back and he
## heads back to Nora's side.
func _dog_checks() -> void:
	_check("the dog is on the farm with his model and his four loops (%s)" % [dog.current_loop() if dog else "none"],
		dog != null and dog.visible and dog.ok())
	if dog == null or not dog.ok():
		return
	autotest_jog = false
	player.running = false
	player.walk([])
	var start := player.position
	dog.position = start + Vector3(1.2, 0, 0.8)
	cam_target = dog.position
	var cd0 := cam_dist
	cam_dist = 6.0
	await _wait(1.0)
	_check("standing by Nora he idles (%s)" % dog.current_loop(), dog.current_loop() == "Idle")
	await _shot("48_dog.png")
	await _key_tap(KEY_TAB)
	_check("Tab hands the clicks to the dog", dog.controlled)
	var goal := start + Vector3(9.0, 0, 0)
	if _find_path(dog.position, goal).is_empty():
		goal = start + Vector3(-9.0, 0, 0)
	_live_click(cam.unproject_position(goal))
	await _wait(0.9)
	var rate_trot := dog.loop_rate() * float(dog.STRIDE.get(dog.current_loop(), 1.0))
	_check("clicked, he trots off with his stride matching his speed (%s at %.2f m/s, loop covers %.2f m/s)" % [dog.current_loop(), dog.speed, rate_trot],
		dog.current_loop() == "Trot" and dog.speed > 1.2 and absf(rate_trot - dog.speed) < 0.12)
	_check("Nora stays where she was while you play him", player.path.is_empty() and player.position.distance_to(start) < 0.3)
	await _shot("48_dog_trot.png")
	autotest_jog = true # as if Shift were held
	_live_click(cam.unproject_position(start - (goal - start)))
	await _wait(1.2)
	var rate_run := dog.loop_rate() * float(dog.STRIDE.get(dog.current_loop(), 1.0))
	_check("holding Shift he gallops, his stride matching his speed (%s at %.2f m/s, loop covers %.2f m/s)" % [dog.current_loop(), dog.speed, rate_run],
		dog.current_loop() == "Run" and dog.speed > 3.0 and absf(rate_run - dog.speed) < 0.15)
	_check("the camera follows the dog", cam_target.distance_to(dog.position) < 2.5)
	await _shot("48_dog_run.png")
	autotest_jog = false
	await _key_tap(KEY_TAB)
	_check("Tab again gives the clicks back to Nora", not dog.controlled)
	await _wait(5.0)
	_check("off the lead he comes back to her side (%.1f m away)" % dog.position.distance_to(player.position),
		dog.position.distance_to(player.position) < 2.6)
	_check("he herds: the strays shy from him too", homestead.herders.has(dog) and dog.scare_radius() > Homestead.HERD_RADIUS)
	cam_dist = cd0


func _face_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var f = player.body.face if player.body else null
	_check("Nora's model has real eyes with every lid shape", f != null and f.shape_value("squint") >= 0.0
		and ["blink_L", "blink_R", "lid_half", "lid_angry", "lid_sad", "squint"].all(func(n): return f._shape.has(n)))
	if f == null:
		return
	var rowan := _villager("rowan")
	_check("Rowan's model has them too", rowan != null and rowan.body != null and rowan.body.face != null)
	var mayor := _villager("wren")
	_check("Wren the mayor wears her rigged model with real eyes", mayor != null and mayor.body != null and mayor.body.id == "wren" and mayor.body.face != null)
	if mayor != null and mayor.body != null:
		var w_cam := Camera3D.new()
		add_child(w_cam)
		var w_fwd: Vector3 = mayor.body.global_transform.basis.z.normalized()
		var w_eye := mayor.global_position + Vector3(0, 1.49, 0)
		w_cam.fov = 30.0
		w_cam.global_position = w_eye + w_fwd * 0.9 + Vector3(0, 0.02, 0)
		w_cam.look_at(w_eye, Vector3.UP)
		w_cam.current = true
		await _wait(0.5)
		await _shot("47_face_wren.png")
		w_cam.global_position = mayor.global_position + w_fwd * 3.2 + Vector3(0, 1.1, 0)
		w_cam.look_at(mayor.global_position + Vector3(0, 0.9, 0), Vector3.UP)
		await _wait(0.2)
		await _shot("47_wren_body.png")
		w_cam.queue_free()
	# a close camera on her face for the pictures
	var face_cam := Camera3D.new()
	add_child(face_cam)
	var eye := player.global_position + Vector3(0, 1.49, 0)
	var fwd: Vector3 = player.body.global_transform.basis.z.normalized()
	face_cam.fov = 30.0
	face_cam.global_position = eye + fwd * 0.75 + Vector3(0, 0.02, 0)
	face_cam.look_at(eye, Vector3.UP)
	face_cam.current = true
	f.blinks = false
	f.mood = "neutral"
	player.body.look_target = null
	await _wait(0.5)
	await _shot("47_face_rest.png")
	# a blink shuts the eyes and opens them again within a third of a second
	f.blink()
	var peak := 0.0
	var t := 0.0
	while t < 0.4:
		await get_tree().process_frame
		t += get_process_delta_time()
		peak = maxf(peak, f.shut())
	_check("a blink shuts her eyes and opens them again (peak %.2f, now %.2f)" % [peak, f.shut()], peak > 0.95 and f.shut() < 0.05)
	# moods from story lines
	player.body.set_mood("sad")
	await _wait(0.6)
	var sad: float = f.shape_value("lid_sad")
	await _shot("47_face_sad.png")
	player.body.set_mood("happy")
	await _wait(0.6)
	var happy: float = f.shape_value("squint")
	await _shot("47_face_happy.png")
	_check("her eyes take a mood (sad %.2f, happy %.2f) and an unknown mood is neutral" % [sad, happy], sad > 0.7 and happy > 0.6)
	player.body.set_mood("no such mood")
	await _wait(0.6)
	_check("back to neutral (squint %.2f)" % f.shape_value("squint"), f.shape_value("squint") < 0.05 and f.mood == "neutral")
	# asleep
	player.body.set_eyes_closed(true)
	await _wait(0.5)
	var shut: float = f.shape_value("blink_L")
	await _shot("47_face_asleep.png")
	player.body.set_eyes_closed(false)
	await _wait(0.4)
	_check("asleep her eyes are shut, awake they open (shut %.2f, then %.2f)" % [shut, f.shape_value("blink_L")], shut > 0.98 and f.shape_value("blink_L") < 0.05)
	# the eyes turn toward what she looks at: a point to her left, then one to her right
	var left: Vector3 = player.body.global_transform.basis.x.normalized()
	f.hold_gaze = eye + fwd * 1.0 + left * 0.6
	await _wait(0.5)
	var gl: Vector2 = f.gaze()
	await _shot("47_face_look_left.png")
	f.hold_gaze = eye + fwd * 1.0 - left * 0.6
	await _wait(0.5)
	var gr: Vector2 = f.gaze()
	f.hold_gaze = null
	_check("her eyes turn toward what she looks at, within their range (left %.0f deg, right %.0f deg)" % [rad_to_deg(gl.x), rad_to_deg(gr.x)],
		gl.x > deg_to_rad(3.0) and gr.x < deg_to_rad(-3.0) and absf(gl.x) <= f.MAX_YAW + 0.001 and absf(gr.x) <= f.MAX_YAW + 0.001)
	# a story line carries its mood to the speaker's eyes, and the scene's end clears it
	f.blinks = true
	face_cam.queue_free()
	cam.current = true


func _hud_checks() -> void:
	var inv0: Dictionary = Game.inv.duplicate()
	Game.add_item("wool", 1)
	await _wait(0.1)
	var wool_at: int = Game.slots.find("wool")
	_check("hotbar: nine slots and a bag of 27, wool in slot %d showing %d" % [wool_at + 1, hud.slot_btns[maxi(wool_at, 0)].n],
		hud.slot_btns.size() == 36 and wool_at >= 0 and hud.slot_btns[wool_at].n == Game.count("wool") and hud.hotbar.visible)
	await _key_tap(KEY_3)
	var third := hud.hot_sel
	await _key_tap(KEY_1)
	_check("hotbar: number keys pick the slot in her hand (3 gave slot %d, 1 gave slot %d holding '%s')" % [third + 1, hud.hot_sel + 1, hud.selected_item()],
		third == 2 and hud.hot_sel == 0 and hud.selected_item() == str(Game.slots[0]))
	await _shot("46_hud.png")
	# something new takes the first empty slot, and leaves it when it's used up
	Game.add_item("test_thing", 2)
	await _wait(0.1)
	var thing_at: int = Game.slots.find("test_thing")
	Game.take_item("test_thing", 2)
	await _wait(0.1)
	Game.inv.erase("test_thing")
	_check("hotbar: a new thing gets a slot (%d) and gives it up when it's gone" % (thing_at + 1), thing_at >= 0 and not Game.slots.has("test_thing"))
	# the bag: I opens it, two clicks swap slots, Esc shuts it
	await _key_tap(KEY_I)
	var bag_open := hud.bag_panel.visible
	var other := 20 if wool_at != 20 else 21
	hud.slot_btns[wool_at].pressed.emit()
	hud.slot_btns[other].pressed.emit()
	await _wait(0.1)
	var moved: bool = Game.slots[other] == "wool" and hud.slot_btns[other].n == Game.count("wool")
	await _shot("46_bag.png")
	hud.slot_btns[other].pressed.emit()
	hud.slot_btns[wool_at].pressed.emit()
	await _key_tap(KEY_ESCAPE)
	_check("bag: I opens it (%s), clicking two slots swaps them (%s) and back, Esc shuts it" % [bag_open, moved],
		bag_open and moved and Game.slots[wool_at] == "wool" and not hud.bag_panel.visible)
	# Esc with nothing else open is the menu
	await _key_tap(KEY_ESCAPE)
	var menu_open := hud.game_menu.visible
	await _key_tap(KEY_ESCAPE)
	_check("menu: Esc opens it (%s) and shuts it again" % menu_open, menu_open and not hud.game_menu.visible)
	# B and the Build button on the bar
	await _key_tap(KEY_B)
	var build_on := mode == Mode.BUILD and hud.build_btn.button_pressed and hud.catalog_panel.visible
	await _key_tap(KEY_B)
	_check("build: B opens Build & Buy and lights the bar's button (%s), B again leaves" % build_on, build_on and mode == Mode.LIVE and not hud.build_btn.button_pressed)
	# her needs sit top left, under the Menu button
	var needs_at := hud.needs_panel.get_global_rect()
	var shown: Array = Game.NEEDS.filter(func(n): return hud.needs_cells[n].is_visible_in_tree())
	_check("needs: all six bars show top left under Menu (%d shown, panel at %s)" % [shown.size(), str(needs_at.position)],
		shown.size() == 6 and needs_at.position.x < 40.0 and needs_at.position.y > hud.menu_btn.get_global_rect().end.y and needs_at.end.y < 420.0)
	# the frame counter and the camera buttons are off until settings turns them on
	var off := not hud.fps_label.visible and not hud.cam_pad.visible
	hud.set_option("fps", true)
	hud.set_option("camera_pad", true)
	var on := hud.fps_label.visible and hud.cam_pad.visible and hud.fps_check.button_pressed
	hud.set_option("fps", false)
	hud.set_option("camera_pad", false)
	_check("settings: frame counter and camera buttons start hidden (%s) and can be shown (%s)" % [off, on], off and on)
	Game.inv = inv0
	await _wait(0.1)


## Waits (up to `secs`) for a tool's work to be over: `done` true and her hands free.
func _tool_wait(done: Callable, secs := 30.0) -> void:
	var t := 0.0
	while (not done.call() or player.busy) and t < secs:
		await _wait(0.2)
		t += 0.2


## The six tools: she owns them, and with one in hand a click uses it.
func _tool_checks() -> void:
	var energy0 := Game.energy
	Game.energy = 100.0
	# on the farm, out in front of the house, in daylight and with her hands free
	story.auto = false
	hud.hide_dialogue()
	set_mode(Mode.LIVE)
	player.cancel_activity()
	player.position = Vector3(9.0, 0, 8.0)
	_set_cam_lock(true)
	await _wait(1.0)
	var owned: Array = Game.TOOLS.filter(func(t): return Game.count(t) == 1 and Game.slots.has(t) and Hud.Slot.icon(t) != null)
	_check("tools: she owns all six, each with a slot and a picture (%s)" % str(owned), owned.size() == 6)
	hud.hot_sel = Game.slots.find("hoe")
	_check("tools: picking the hoe's slot puts it in her hand ('%s')" % hud.selected_item(), hud.selected_item() == "hoe")
	await _shot("47_tools_hotbar.png")
	# the hoe: a new bed on open ground, the grass making way; never on a bed that's there
	var spot := Vector3.ZERO
	var best := INF
	for j in range(-8, 9):
		for i in range(-8, 9):
			var c := Vector3(PLOT_ORIGIN.x + i * PLOT_GRID, 0, PLOT_ORIGIN.y + j * PLOT_GRID)
			if _till_problem(c) == "" and c.distance_to(player.position) < best and grass.grass_at(c.x, c.z) > 0.8:
				best = c.distance_to(player.position)
				spot = c
	var n0 := plots.size()
	var taken := _till_problem(plots[0].position)
	var clicked := _tool_click("hoe", null, cam.unproject_position(spot))
	var offered: bool = ground_actions(spot).any(func(a): return a["id"] == "dig")
	var used := dig_bed(_plot_spot(spot))
	await _tool_wait(func(): return plots.size() > n0)
	_check("hoe: a plain click never digs (%s); right click offers 'Dig bed' on open ground (%s)" % [clicked, offered], not clicked and offered)
	# never in a building: the barn, her house, a shop
	var inside := []
	if World.barn != null:
		inside.append(World.barn.global_position)
	inside.append(Vector3(interior_rect().get_center().x, 0, interior_rect().get_center().y))
	for sid in Interiors.shops:
		inside.append(Interiors.shops[sid].node.global_position)
	var dug_inside: Array = inside.filter(func(q): return _till_problem(_plot_spot(q)) == "" or ground_actions(q).any(func(a): return a["id"] == "dig"))
	_check("hoe: no bed can be dug inside a building (%d tried, %d allowed)" % [inside.size(), dug_inside.size()], inside.size() >= 3 and dug_inside.is_empty())
	var bed: Plot = plots[plots.size() - 1]
	_check("hoe: digs a new bed on open ground (%s, beds %d→%d, grass there %.2f) and not on an old one ('%s')" % [used, n0, plots.size(), grass.grass_at(spot.x, spot.z), taken],
		used and plots.size() == n0 + 1 and bed.tilled and bed.position.distance_to(spot) < 0.7 and grass.grass_at(spot.x, spot.z) < 0.5 and taken != "")
	# the watering can
	bed.plant("turnip")
	used = _tool_click("watering_can", bed, Vector2.ZERO)
	await _tool_wait(func(): return bed.watered)
	_check("watering can: waters the crop under the click (%s, watered %s)" % [used, bed.watered], used and bed.watered)
	await _shot("47_tools_bed.png")
	# a bed she dug is saved with its place
	var saved: Dictionary = bed.to_dict()
	_check("hoe: the bed is saved with its place (%s)" % str(saved.get("tilled")), saved.get("tilled") is Array)
	# the shovel: clears a bed she dug, leaves Gran's
	bed.clear_crop()
	var grans: Array = plots.filter(func(p): return not p.tilled and p.crop == "")
	var kept := _tool_click("shovel", grans[0], Vector2.ZERO)
	var n1 := plots.size()
	used = _tool_click("shovel", bed, Vector2.ZERO)
	await _tool_wait(func(): return plots.size() < n1)
	await _wait(0.2)
	_check("shovel: clears the bed she dug (beds %d→%d, grass back %.2f) and leaves Gran's (%s)" % [n1, plots.size(), grass.grass_at(spot.x, spot.z), kept],
		used and kept and plots.size() == n0 and grass.grass_at(spot.x, spot.z) > 0.5)
	# the shears
	var woolly: Array = sheep_list.filter(func(s): return s.is_woolly())
	if woolly.is_empty():
		sheep_list[0].wool = 1.0
		woolly = [sheep_list[0]]
	var wool0 := Game.count("wool")
	used = _tool_click("shears", woolly[0], Vector2.ZERO)
	await _tool_wait(func(): return Game.count("wool") > wool0)
	_check("shears: shear the sheep under the click (wool %d→%d)" % [wool0, Game.count("wool")], used and Game.count("wool") == wool0 + 2)
	# the scythe
	var hay_at := player.position
	for r in [3.0, 5.0, 8.0]:
		for a in 8:
			var c: Vector3 = player.position + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * float(r)
			if grass.grass_at(c.x, c.z) > 0.9 and LOT.has_point(Vector2(c.x, c.z)) and hay_at == player.position:
				hay_at = c
	used = _tool_click("scythe", null, cam.unproject_position(hay_at))
	await _tool_wait(func(): return Game.count("hay") > 0)
	_check("scythe: cuts hay from the grass (%s, hay %d)" % [used, Game.count("hay")], used and Game.count("hay") == 1)
	# the axe: wood from a tree, once a day each
	var tree = null
	best = INF
	for el in god.els:
		if not el.deleted and el.kind.begins_with("tree_") and el.xf.origin.distance_to(player.position) < best:
			best = el.xf.origin.distance_to(player.position)
			tree = el
	var at_tree := cam.unproject_position(tree.xf.origin + Vector3(0, 0.8, 0))
	used = _tool_click("axe", null, at_tree)
	await _tool_wait(func(): return Game.count("wood") > 0, 45.0)
	var wood := Game.count("wood")
	await _wait(0.6) # the camera follows her, so the tree is somewhere else on screen now
	var again := _tool_click("axe", null, cam.unproject_position(tree.xf.origin + Vector3(0, 0.8, 0)))
	await _wait(0.5)
	_check("axe: chops wood from the tree under the click (%s, wood %d), once a day each (asked again %s, wood %d, busy %s)" % [used, wood, again, Game.count("wood"), player.busy],
		used and wood == CHOP_WOOD and again and Game.count("wood") == wood and not player.busy)
	# the axe has a model, so it shows in her hand
	hud.hot_sel = Game.slots.find("axe")
	player.position = Vector3(9.0, 0, 8.0) # out from under the tree she just chopped
	player.rotation.y = cam_yaw + 0.5
	var dist0 := cam_dist
	cam_dist = 5.0
	await _wait(1.2)
	var held: Array = _tool_hand.find_children("*", "MeshInstance3D", true, false) if _tool_hand else []
	_check("axe: shows in her right hand while it's the tool picked (%d mesh, visible %s)" % [held.size(), _tool_hand != null and _tool_hand.visible],
		held.size() >= 1 and _tool_hand.visible and _tool_hand.bone_name == "RightHand")
	await _shot("47_tool_in_hand.png")
	# every tool has a model now: each shows in her hand in turn
	var shown := PackedStringArray()
	for tid in Game.TOOLS:
		hud.hot_sel = Game.slots.find(tid)
		await _wait(0.6)
		var ms: Array = _tool_hand.find_children("*", "MeshInstance3D", true, false) if _tool_hand else []
		var fist: bool = _grip_meshes.size() > 0 and _grip_meshes[0].get_blend_shape_value(_grip_meshes[0].find_blend_shape_by_name("grip_R")) > 0.99
		if _held_id == tid and ms.size() >= 1 and _tool_hand.visible and fist:
			shown.append(tid)
		await _shot("47_in_hand_%s.png" % tid)
		# and close up, from her right and a little in front, to see her fingers round it
		var hand_at: Vector3 = _tool_hand.global_position
		var fist_cam := Camera3D.new()
		add_child(fist_cam)
		var right: Vector3 = -player.global_transform.basis.x.normalized()
		var front: Vector3 = player.global_transform.basis.z.normalized()
		fist_cam.fov = 40.0
		fist_cam.global_position = hand_at + right * 0.9 + front * 0.5 + Vector3(0, 0.15, 0)
		fist_cam.look_at(hand_at + Vector3(0, -0.1, 0), Vector3.UP)
		fist_cam.current = true
		await _wait(0.2)
		await _shot("47_fist_%s.png" % tid)
		fist_cam.queue_free()
		cam.current = true
	_check("each of the six tools sits in her closed fist when picked (%s)" % ", ".join(shown), shown.size() == Game.TOOLS.size())
	# a slot with no tool: the tool goes and her hand opens
	var empty_slot := -1
	for i in hud.HOTBAR:
		if not Game.TOOLS.has(str(Game.slots[i])):
			empty_slot = i
			break
	hud.hot_sel = maxi(empty_slot, 0)
	await _wait(0.3)
	var open_now: bool = _grip_meshes.size() > 0 and _grip_meshes[0].get_blend_shape_value(_grip_meshes[0].find_blend_shape_by_name("grip_R")) < 0.01
	_check("her hand opens when no tool is picked (slot %d, open %s, tool shown %s)" % [empty_slot + 1, open_now, _tool_hand.visible],
		empty_slot >= 0 and open_now and not _tool_hand.visible)
	cam_dist = dist0
	# an empty hand, or a tool with nothing to do there, leaves the click alone
	_check("tools: nothing to do means the click is left alone", not _tool_click("", plots[0], Vector2.ZERO) and not _tool_click("watering_can", sheep_list[0], Vector2.ZERO))
	Game.take_item("wood", Game.count("wood"))
	Game.take_item("hay", Game.count("hay"))
	Game.take_item("wool", 2)
	woolly[0].wool = 1.0
	hud.hot_sel = 0
	Game.energy = energy0
	await _wait(0.2)


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
	# trash cans (art/world_assets/trash_can) at the end of two plaza benches, where Alex's layout has them
	_decor("trash_can", Vector3(54.5, 0, 2.0), 0)
	_decor("trash_can", Vector3(56.05, 0, -2.45), 1)
	for p in [Vector3(55.0, 0, -8.3), Vector3(58.2, 0, -8.3), Vector3(62.3, 0, -7.9)]:
		_decor("flower_pot", p, 0)
	_decor("sunflowers", Vector3(45.2, 0, -12.0), 0)
	_decor("hay_bale", Vector3(51.6, 0, -8.6), 0)
	# "Welcome to Maple Grove" where the road comes in from the bus stop (art/world_assets/welcome_sign)
	_decor("welcome_sign", Vector3(37.6, 0, -1.2), 0)
	# the bakery's street stall right of its door, the chalkboard by the door, daisies beside it
	# (art/world_assets/bakery_stall; the bakery stands where Alex moved it, front at about z = -9)
	_decor("bakery_stall", Vector3(44.25, 0, -7.7), 0)
	_decor("chalkboard_sign", Vector3(42.85, 0, -7.0), 0)
	_decor("daisy_crate", Vector3(45.7, 0, -7.95), 0)
	# hay bales round the barn and the sheep pen (art/world_assets/farm_props)
	for b in [[Vector3(17.9, 0, -8.4), 1], [Vector3(17.75, 0, -7.15), 0], [Vector3(25.0, 0, -9.1), 1], [Vector3(25.0, 0, -10.35), 1], [Vector3(23.8, 0, -2.7), 1], [Vector3(16.3, 0, -3.6), 1]]:
		_decor("hay_bale", b[0], b[1])


func _decor(id: String, pos: Vector3, r: int) -> void:
	var f: Furniture = Furniture.new()
	decor_root.add_child(f)
	f.setup(id, r)
	f.position = pos
	decor.append(f)
	if not f.is_flat():
		grid_blockers.append(f.footprint())


## The flock keeps farm hours: at dusk each sheep walks from the pen to her stall in the barn, and
## at first light back out to the pen. A game that starts at night finds them already in their
## stalls. Without the barn (deleted in the editor, or the old box) they stay in the pen.
func _update_flock(delta: float) -> void:
	_flock_t -= delta
	if _flock_t > 0.0:
		return
	_flock_t = 0.5
	var night: bool = flock_bedtime and World.barn_ready() and (Game.hour >= SHEEP_IN or Game.hour < SHEEP_OUT)
	var first := not _flock_seen
	_flock_seen = true
	for i in sheep_list.size():
		var s = sheep_list[i]
		if night:
			if s.housed or s.heading_in:
				continue
			var st: Dictionary = World.barn_stall(i)
			if first:
				s.place(st["stall"], true, st["yaw"])
				continue
			var way_in: Array = _find_path(s.position, st["aisle"])
			way_in.append(st["stall"])
			s.walk_route(way_in, true, st["yaw"])
		elif s.housed or s.heading_in:
			var to := Vector3(randf_range(s.pen.position.x, s.pen.end.x), 0, randf_range(s.pen.position.y, s.pen.end.y))
			var way_out: Array = []
			if s.housed and World.barn_ready():
				var from: Vector3 = World.barn_stall(i)["aisle"]
				way_out = _find_path(from, to)
				way_out.push_front(from)
			else:
				way_out = _find_path(s.position, to)
			s.walk_route(way_out, false)


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


## Fires a story event a moment after an action, once its line has shown.
func _story_event_soon(event: String) -> void:
	get_tree().create_timer(0.8).timeout.connect(func():
		if not story.is_playing():
			story.trigger("event", event))


## A new game opens on Act 1, if a scene has "@trigger start"; otherwise on the help card.
func _begin_new_story() -> void:
	if Story.find_trigger("start") == "":
		hud.help_panel.visible = true
		return
	homestead.start_story()
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
				var k: Dictionary = Interiors.keeper(str(d["works_in"])) if d.has("works_in") else {}
				v.settle_at(k.get("pos", d["pos"]))
				v.roam = k.get("roam", d["roam"])
				if d.has("route"): # the postman goes back to his round
					v.route = d["route"]
					v._next_stop()
				if k.has("yaw"):
					v.rotation.y = float(k["yaw"])


## Shopkeepers (villagers.json "works_in") work inside their shops (scripts/interiors.gd): they
## stand behind the counter facing the door, and you talk to them from across it. A scene that
## has sent one somewhere else (a "home_" flag) keeps them there.
func _place_shopkeepers() -> void:
	for d in _villager_defs():
		var v := _villager(str(d["id"]))
		if v == null or not d.has("works_in"):
			continue
		var k: Dictionary = Interiors.keeper(str(d["works_in"]))
		if k.is_empty():
			continue
		v.talk_spot = k["talk"]
		v.rest_yaw = k["yaw"]
		if Game.flag("home_" + v.vid, null) == null:
			v.settle_at(k["pos"])
			v.roam = k["roam"]
			v.rotation.y = float(k["yaw"])


## Where villager `vid` stands when nobody has sent them anywhere: their counter, or their spot.
func _villager_post(vid: String) -> Vector3:
	for d in _villager_defs():
		if d["id"] == vid:
			var k: Dictionary = Interiors.keeper(str(d["works_in"])) if d.has("works_in") else {}
			return k.get("pos", d["pos"])
	return Vector3.ZERO


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


const PASTRY_PRICE := 12 # Hazel's croissants, before her friendship discount
const PASTRY_FOOD := 25.0


func _hazel_price() -> int:
	return int(round(PASTRY_PRICE * (1.0 - 0.05 * Game.hearts("hazel"))))


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
			acts.append(_act("sell_sweater", "Sell sweaters  (%d, %dc)" % [sw, Game.sweater_worth(_rosa_price())], sw > 0))
			var crops := _crop_value()
			acts.append(_act("sell_crops", "Sell crops  (%dc)" % crops, crops > 0))
		"theo":
			var wp := _theo_price(Game.WOOL_PACK_PRICE)
			acts.append(_act("buy_wool", "Buy 3 wool  (%dc)" % wp, Game.coins >= wp))
			if homestead.story_farm() and not homestead.has_pen():
				acts.append(_act("noop", "Buy a sheep  (build a pen first)", false))
			elif Game.sheep_count < Game.MAX_SHEEP:
				var sp := _theo_price(Game.SHEEP_PRICE)
				acts.append(_act("buy_sheep", "Buy a sheep  (%dc · you have %d)" % [sp, Game.sheep_count], Game.coins >= sp))
			else:
				acts.append(_act("noop", "Your pen is full (%d sheep)" % Game.MAX_SHEEP, false))
		"gus":
			var n := homestead.econ("wood_pack", 5)
			var wp := homestead.econ("wood_pack_price", 15)
			acts.append(_act("buy_wood", "Buy %d wood  (%dc)" % [n, wp], Game.coins >= wp))
		"hazel":
			var pp := _hazel_price()
			acts.append(_act("buy_pastry", "Buy a warm croissant  (%dc)" % pp, Game.coins >= pp and Game.fullness < 99.0))
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
			var worth := Game.sweater_worth(price) # by rarity
			if n > 0 and Game.take_item("sweater", n):
				Game.coins += worth
				var praise: Array = ["Oh, these are gorgeous!", "Lovely work, as always.", "The city folks will snap these up!"]
				_say(v, "%s Here's %dc for %d sweater%s." % [praise[Game.day % 3], worth, n, "s" if n > 1 else ""])
				hud.show_toast("Sold %d sweater%s for %dc!" % [n, "s" if n > 1 else "", worth])
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
				_story_event_soon("yarn_bought")
		"buy_wood":
			if Game.spend(homestead.econ("wood_pack_price", 15)):
				Game.add_item("wood", homestead.econ("wood_pack", 5))
				var said: Array = ["Good straight lengths, those. A panel each, and two for a gate.", "Mind your thumbs. Nobody ever does.", "Fencing, is it? Sheep'll lean on anything. Build it like they mean it."]
				_say(v, said[(Game.day + int(f["n"])) % said.size()])
				hud.show_toast("+%d wood" % homestead.econ("wood_pack", 5))
				homestead.ui.refresh()
				_story_event_soon("wood_bought")
		"buy_sheep":
			if Game.sheep_count < Game.MAX_SHEEP and Game.spend(_theo_price(Game.SHEEP_PRICE)):
				var sheep_name: String = Dialogue.NEW_SHEEP[(Game.sheep_count - Game.START_SHEEP) % Dialogue.NEW_SHEEP.size()]
				Game.sheep_count += 1
				_add_sheep()
				_say(v, "Her name is %s. I walked her over to your pen myself. Be nice to her!" % sheep_name)
				hud.show_toast("%s the sheep joined your flock! (%d sheep)" % [sheep_name, Game.sheep_count])
		"buy_pastry":
			if Game.spend(_hazel_price()):
				Game.fullness = minf(100.0, Game.fullness + PASTRY_FOOD)
				Game.add_need("happiness", 4.0)
				var said: Array = ["Still warm. Eat it here, crumbs and all.", "Ten minutes out of the oven. Mind, it's hot.", "Take the window seat if you like. Nobody's in a hurry in here."]
				_say(v, said[(Game.day + int(f["n"])) % said.size()])
				hud.show_toast("A warm croissant. (+%d food)" % int(PASTRY_FOOD))
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
	if v.get("body") != null and v.body:
		v.body.set_mood(mood) # their eyes show the reply's mood


## What the villager knows about this moment, for the prompt (ai_chat.gd situation_text).
func _chat_context(v) -> Dictionary:
	var f := Game.friend(v.vid)
	var place := {"rosa": "your market stall on the plaza", "theo": "the Yarn Barn, your shop", "mabel": "Willow Homes, your office", "hazel": "Heart Bakery, your bakery", "gus": "Builder's Delight, your shop"}
	var where: String = place.get(v.vid, "")
	if where == "":
		where = "Maple Grove, near the plaza" if v.position.x > 30.0 else "Birchfield Farm, Nora's place"
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
	_plank_floor(c, 23, "cottage")
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
	# where the stall stands now: Alex's layout moved it off Town.STALL
	var stall_el = god.by_key.get("market_stall@%.2f,%.2f" % [Town.STALL.x, Town.STALL.z]) if god else null
	var stall_at: Vector3 = stall_el.xf.origin if stall_el else Town.STALL
	var stall_mesh := find_children("model", "MeshInstance3D", true, false).filter(func(m): return m.global_position.distance_to(stall_at) < 0.5)
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
