extends Node3D
## Knitting Empire prototype: world setup, camera, input, pathfinding,
## actions, build mode, house expansion and saving.

const Catalog = preload("res://scripts/catalog.gd")
const World = preload("res://scripts/world.gd")
const Furniture = preload("res://scripts/furniture.gd")
const PerfCheck = preload("res://scripts/perf_check.gd")
const SuburbCheck = preload("res://scripts/suburb_check.gd")
const WalkinCheck = preload("res://scripts/walkin_check.gd")
const TownsfolkCheck = preload("res://scripts/townsfolk_check.gd")
const LightBudget = preload("res://scripts/light_budget.gd")
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
const GameAudio = preload("res://scripts/audio.gd")
const Nature = preload("res://scripts/nature.gd")
const Fireflies = preload("res://scripts/fireflies.gd")
const Lighting = preload("res://scripts/lighting.gd")
const Regions = preload("res://scripts/regions.gd")
const Suburb = preload("res://scripts/suburb.gd")
const GodMode = preload("res://scripts/god_mode.gd")
const Planks = preload("res://scripts/planks.gd")
const HouseSkin = preload("res://scripts/house_skin.gd")
const Homestead = preload("res://scripts/homestead.gd")
const Dog = preload("res://scripts/dog.gd")
const Cinematic = preload("res://scripts/cinematic.gd")
const FirstPerson = preload("res://scripts/first_person.gd")
const Mail = preload("res://scripts/mail.gd")
const Jobs = preload("res://scripts/jobs.gd")
const Forage = preload("res://scripts/forage.gd")
const Sweaters = preload("res://scripts/sweaters.gd")
const WardrobePanel = preload("res://scripts/wardrobe_panel.gd")
const WardrobeView = preload("res://scripts/wardrobe_view.gd")
const SweaterSale = preload("res://scripts/sweater_sale.gd")
const Keys = preload("res://scripts/keybinds.gd")
const SeeThrough = preload("res://scripts/see_through.gd")
const Wildlife = preload("res://scripts/wildlife.gd")
const Empire = preload("res://scripts/empire.gd")
const Wolves = preload("res://scripts/wolves.gd")
const Townsfolk = preload("res://scripts/townsfolk.gd")
const BookPanel = preload("res://scripts/book_panel.gd")
const CafeVisits = preload("res://scripts/cafe_visits.gd")
const ReadingPose = preload("res://scripts/reading_pose.gd")
const Barista = preload("res://scripts/barista.gd")
const OnlineStore = preload("res://scripts/online_store.gd")
const HouseBuilder = preload("res://scripts/house_builder.gd")

const CELL := 0.5
const GRID_ORIGIN := Vector2(-96.0, -100.0)
const GRID_SIZE := Vector2i(480, 324) # covers x -96..144, z -100..62: the farm, Maple Grove and the lands round them (Regions.BOUNDS)
const HOUSE_W := 8.0
const HOUSE_FRONT := 6.0
const WALL_H := 2.6
const WALL_T := 0.2
const DOOR_Z0 := 2.3
const DOOR_Z1 := 3.7
const LOT := Rect2(-5, -19, 32, 31) # walkable / buildable yard: x -5..27, z -19..12
const PEN := Rect2(17, -4, 6, 6)
const PEN_GATE := Vector2(-1.6, -0.4)
const CAM_PITCH := 48.0
const CAM_PITCH_LOW := 20.0 # story close-ups ("@camera ... low")
const CAM_BOUNDS := Regions.BOUNDS # the farm, the town and the lands round them
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
var roofs: Array = [] # {node, rect}: the roofs of Nora's house and the cottage (_house_roof)
var house_roof: Node3D # the roof of Nora's own house, where her chimneys stand (_update_chimneys)
var _chimney_sig := "" # where the fireplaces were when the chimneys were last built
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
var town_rounds := true # the cast's routines (_update_rounds); off in the autotest but for its own check
var _flock_t := 0.0
var _flock_seen := false
var wardrobe_ui: WardrobePanel # Nora's wardrobe: which of her sweaters she wears (wardrobe_panel.gd)
var barista: Barista # working the Coffee Shop's counter in first person (barista.gd)
var store: OnlineStore # the online sweater store on her computer (online_store.gd)
var wview: WardrobeView # the wardrobe from her eyes: her sweaters on hangers (wardrobe_view.gd)
var sale: SweaterSale # selling a sweater to anyone in town, haggling over the price (sweater_sale.gd)
var books_ui: BookPanel # the books she reads (book_panel.gd, data/books.json)
var _reading := false # she's sitting (or standing) with a book open; the panel's `closed` gets her up
var _read_spot = null # the café seat she has (Interiors.ReadSpot), so no villager is sent to it
var cafe_visits: CafeVisits # villagers dropping into the Coffee Shop for a coffee and a book (cafe_visits.gd)
var mail: Mail # the post (mail.gd): the mailbox by the porch, letters and sweater orders
const MAILBOX_POS := Vector3(11.6, 0, 5.0) # beside the lane, just past the porch; its door faces the lane
const MAILBOX_YAW := PI
const TOWN_MAILBOXES := [[Vector3(57.0, 0, 6.6), 2], [Vector3(55.6, 0, -12.5), 0], [Vector3(68.5, 0, -1.0), 3]] # [where, quarter turns]
var grid_blockers: Array = [] # static outdoor obstacles (Rect2)
var place_blockers: Array = [] # areas furniture can't go (Rect2)
var astar := AStarGrid2D.new()
var player: Player
var dog: Dog # the golden retriever: keeps Nora company, and Tab hands him the clicks (dog.gd)
var wildlife: Wildlife # the wild animals and birds round the farm (wildlife.gd, data/wildlife.json)
var empire: Empire # needles, the lantern and the locals' requests (empire.gd)
var wolves: Wolves # wolves at night, after her penned animals (wolves.gd, data/wolves.json)
var townsfolk: Townsfolk # the town's passers-by and the red pin over anyone who wants a sweater (townsfolk.gd)
var builder: HouseBuilder # walls she builds in build mode, the rooms they close, Gary's plots (house_builder.gd)
var hud: Hud
var cinema: Cinematic # cinematic mode: the free camera and its photos (cinematic.gd), P
var fps: FirstPerson # first person: the camera at her eyes (first_person.gd), V
var jobs: Jobs # work beside knitting: the bakery, the Coffee Shop, the post round (jobs.gd)
var forage: Forage # trees she fells with the axe, plants she trims with the shears (forage.gd)
var knit: KnitGame # the knitting game (knit_game.gd), a rhythm game played to a song
var _knit_chair = null
var _knit_fibre := "" # the wild fibre going into the sweater on the needles ("" for plain wool)
var _knit_clock_was := true
var audio: GameAudio
var story: StoryPlayer
var villagers: Array = []
var minimap: Minimap # the map under the coins (minimap.gd): click it to walk there
var see_through: SeeThrough # scenery between the camera and the people fades (see_through.gd)
var decor: Array = [] # town lanterns/benches: furniture you can use but not pick up
var fireflies # fireflies.gd: glowing orbs round things near her at night
var lighting # lighting.gd: morning mist and its light shafts, SDFGI on High and Ultra
var regions # regions.gd: the swamp, the foothills and mountains, the beach and the sea, the east meadows
var decor_root: Node3D
var suburb # suburb.gd: Bretton Oaks, the cul-de-sac where the town sleeps
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
var rain_splash: CPUParticles3D # rings where the drops land
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
	regions = Regions.new()
	add_child(regions)
	grid_blockers.append_array(regions.build(self))
	var town := Town.build(self)
	grid_blockers.append_array(town["blockers"])
	price_board = town["board"]
	sign_to_town = town["sign_to_town"]
	sign_to_farm = town["sign_to_farm"]
	decor_root = Node3D.new()
	add_child(decor_root)
	_build_town_decor()
	suburb = Suburb.new()
	add_child(suburb)
	grid_blockers.append_array(suburb.build(self))
	grid_blockers.append_array(World.build_barn(self, Vector3(21.5, 0, -9.5)))
	pond_rect = World.build_pond(self, Vector3(2.5, 0, -16.0), 2.0)
	grid_blockers.append(pond_rect)
	grid_blockers.append_array(World.build_pen(self, PEN, PEN_GATE))
	mail = Mail.new()
	mail.main = self
	add_child(mail)
	mail.build_box(self, MAILBOX_POS, MAILBOX_YAW)
	grid_blockers.append(Rect2(MAILBOX_POS.x - Mail.SIZE.x * 0.5, MAILBOX_POS.z - Mail.SIZE.y * 0.5, Mail.SIZE.x, Mail.SIZE.y))
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
		vg.job = str(v.get("title", "")) # "Farmer Lars" over his head: set before setup() makes the tag
		vg.nick = str(v.get("nick", ""))
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
	if Town.COTTAGE_ON:
		place_blockers.append(Rect2(Town.COTTAGE_DOOR.x - 0.2, Town.COTTAGE.position.y - 1.2, Town.COTTAGE_DOOR.y - Town.COTTAGE_DOOR.x + 0.4, 2.5)) # cottage doorway
		place_blockers.append(Rect2(56.6, 5.1, 1.4, 0.5)) # cottage sign
	# the world as arranged in god mode (data/world_layout.json) goes on top of what was just built
	god = GodMode.new()
	god.main = self
	add_child(god)
	god.collect()
	see_through = SeeThrough.new()
	see_through.setup(self)
	add_child(see_through)
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
	Keys.persist = _autotest_dir == "" # the autotest never writes the player's key bindings
	hud = Hud.new()
	add_child(hud)
	hud.letters.mail = mail
	wardrobe_ui = WardrobePanel.new()
	wardrobe_ui.setup(hud)
	hud.root.add_child(wardrobe_ui)
	hud._place(wardrobe_ui, 0.5, 0.5, Vector2.ZERO)
	hud.wardrobe_pressed.connect(func(): wardrobe_ui.open())
	sale = SweaterSale.new()
	sale.setup(hud, self)
	hud.root.add_child(sale)
	hud._place(sale, 0.5, 0.5, Vector2.ZERO)
	minimap = Minimap.new()
	books_ui = BookPanel.new()
	books_ui.setup(hud)
	hud.root.add_child(books_ui)
	hud._place(books_ui, 0.5, 0.5, Vector2.ZERO)
	books_ui.closed.connect(_on_book_closed)
	books_ui.picked.connect(_on_book_picked)
	Interiors.ReadSpot.main = self
	minimap.main = self
	hud.add_minimap(minimap)
	if _autotest_dir != "":
		Cinematic.dir = _autotest_dir.path_join("photos") # never the player's own album
	cinema = Cinematic.new()
	cinema.main = self
	add_child(cinema)
	fps = FirstPerson.new() # after the player, so it places the camera once she has moved this frame
	fps.main = self
	add_child(fps)
	wview = WardrobeView.new() # after first person, so it moves the hangers once her eyes are placed
	wview.main = self
	add_child(wview)
	barista = Barista.new() # after first person too: it turns her view every frame
	barista.main = self
	add_child(barista)
	store = OnlineStore.new() # after first person too: it steers her view to the screen
	store.main = self
	add_child(store)
	Interiors.WorkSpot.main = self
	Interiors.StairSpot.main = self
	player.steer_ok = func(q: Vector3) -> bool:
		var lo: Variant = Interiors.steer_ok(player.position, q) # in the café: its stairs and loft
		return lo if lo != null else _walkable(_cell(q))
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
	story.scene_finished.connect(func(_id): _send_visitors_home())
	cafe_visits = CafeVisits.new()
	cafe_visits.main = self
	story.scene_started.connect(func(_id): cafe_visits.end_all()) # before the scene places anyone
	story.scene_started.connect(func(_id): suburb.wake_all()) # everyone out of bed for it
	jobs = Jobs.new()
	jobs.main = self
	add_child(jobs)
	_setup_story_staging()
	_connect_hud()
	Game.toast.connect(hud.show_toast)
	Game.day_started.connect(_on_day_started)
	_setup_ghost_marker()
	builder = HouseBuilder.new()
	builder.main = self
	add_child(builder)
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
	forage = Forage.new()
	forage.main = self
	add_child(forage)
	forage.apply()
	_setup_dog()
	wildlife = Wildlife.new()
	wildlife.main = self
	add_child(wildlife)
	if _autotest_dir == "": # the autotest places them only for its own check (_wildlife_checks)
		wildlife.build()
	townsfolk = Townsfolk.new() # Maple Grove's passers-by (townsfolk.gd); like the wildlife, only outside the autotest
	townsfolk.main = self
	add_child(townsfolk)
	if _autotest_dir == "":
		townsfolk.build()
	empire = Empire.new()
	empire.main = self
	add_child(empire)
	wolves = Wolves.new()
	wolves.main = self
	add_child(wolves)
	_load_graphics()
	hud.render_thumbnails()
	_load_display()
	tips_enabled = _autotest_dir == "" # the autotest turns them on for its own check
	hints_enabled = _autotest_dir == "" # Act 1's checks turn the control hints on for themselves
	flock_bedtime = _autotest_dir == "" # and the flock stays in the pen but for its own check
	town_rounds = _autotest_dir == "" # and the town keeps still (Rosa's stall, the post, Gary's visits)
	suburb.on = _autotest_dir == "" # and nobody goes home to Bretton Oaks at night but in its own check
	jobs.nudge = _autotest_dir == "" # and no goal sends her to Giorgio after Act 1
	Wolves.on = _autotest_dir == "" # and no wolves come but in their own check (_wolf_checks)
	Jobs.on = _autotest_dir == "" # and no boss offers a job but in the jobs check, which turns them on
	Game.fast_clock = _autotest_dir != "" # the checks were timed on the old 4-minute day; --only=empire checks the real one
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
	hud.render_scale_changed.connect(set_render_scale)
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
	hud.cinematic_pressed.connect(func(): cinema.enter())
	hud.first_person_pressed.connect(func(): fps.enter())
	hud.eat_pressed.connect(func(item: String): eat_item(item))
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
	hud.color_chosen.connect(recolor_held)
	hud.wall_tool_chosen.connect(func(k: String):
		if ghost:
			_cancel_ghost()
		if mode != Mode.BUILD and k != "":
			set_mode(Mode.BUILD)
		builder.set_tool(k))
	hud.floor_kind_chosen.connect(func(k: String): builder.set_floor_kind(k))
	hud.rotate_pressed.connect(_rotate_ghost)
	hud.sell_pressed.connect(_sell_ghost)
	hud.cancel_pressed.connect(_cancel_ghost)
	hud.stop_activity_pressed.connect(func():
		if player.activity_text() != "Zzz":
			player.cancel_activity())
	hud.cam_lock_pressed.connect(func(): _set_cam_lock(not cam_follow, true))
	hud.cam_rotate.connect(func(d): cam_yaw_goal += d * PI * 0.5)
	hud.cam_zoom.connect(func(d): cam_dist = clampf(cam_dist + d * 3.0, 8.0, 45.0))


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
## Per graphics level (Low, Medium, High, Ultra): 3D pixels to aim for and the lowest scale allowed.
const TARGET_3D_PIXELS := [0.7e6, 1.1e6, 1.35e6, 1.6e6]
const MIN_3D_SCALE := [0.25, 0.3, 0.33, 0.35]
const METALFX_MIN_SCALE := 0.34 # MetalFX temporal upscales at most 3x

# --- graphics setting ----------------------------------------------------------------
## Low / Medium / High / Ultra, set in Settings and kept in user://settings.cfg (not the
## save file: it belongs to the computer, not the farm). Ultra is everything (the High of before
## 2026-11-17); High keeps Ultra's look (light bounce, reflections, haze) at a lower cost. The
## autotest always runs on Ultra.
const GFX_NAMES := ["Low", "Medium", "High", "Ultra"]
const GFX_HIGH := 2
const GFX_ULTRA := 3
const SETTINGS_PATH := "user://settings.cfg"
var gfx := GFX_ULTRA
var light_budget := LightBudget.new() # which lamps cast shadows (light_budget.gd)
## Per graphics level: how many of the nearest lit lamps cast real shadows.
const LAMP_SHADOWS := [0, 1, 2, 4]
## Per graphics level: how far from the camera a lamp's shadow fades out (Catalog.omni's 40 m on Ultra).
## Measured from the camera, which sits about 23 m from Nora: 30 keeps the shadow of a lamp beside her
## at the usual zoom and drops it sooner when zoomed out.
const LAMP_SHADOW_FADE := [20.0, 30.0, 35.0, 40.0]
## grass.gd per level: the share of blades drawn, how far from the camera they go, and the share
## left at the end of that range
const GRASS_FRAC := [0.45, 0.75, 1.0, 1.0]
const GRASS_RANGE := [30.0, 32.0, 40.0, 46.0]
const GRASS_THIN := [0.4, 0.4, 0.4, 0.45]
## How far the sun's shadow reaches at most, per level (it follows the zoom below that).
const SUN_SHADOW_REACH := [40.0, 55.0, 62.0, 70.0]
const RECOMMENDED_APPLE := 1 # Medium: on an M4 MacBook Air at 2560x1378 High runs 19-29 fps, Medium 30-50 (--only=perf)


## The Settings slider "3D detail": how many 3D pixels to draw, as a share of the level's own
## (TARGET_3D_PIXELS), from RENDER_SCALE_MIN to RENDER_SCALE_MAX. Kept in user://settings.cfg.
var render_scale := 1.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 1.5
## Settings saved before the graphics pass of 2026-11-16 (version 1) start once on the computer's
## recommended level, since High then cost three times what it does now. Version 2 had three levels:
## its High (2) is read as the new High, the lighter one; Ultra has to be picked.
const GFX_SETTINGS_VERSION := 3


## The level a computer starts on before the player picks one: what --only=perf shows holds
## 30 fps or more everywhere on that kind of graphics chip.
func default_graphics() -> int:
	return recommended_graphics(RenderingServer.get_video_adapter_name(), OS.get_processor_count())


static func recommended_graphics(gpu: String, cores: int) -> int:
	var g := gpu.to_lower()
	if g.contains("apple"): # M-series: one chip for CPU and GPU, a MacBook Air has no fan
		return RECOMMENDED_APPLE
	if g.contains("intel") or g.contains("llvmpipe") or g.contains("swiftshader"):
		return 0
	if cores <= 4:
		return 1
	return GFX_HIGH


func _load_graphics() -> void:
	gfx = default_graphics() if _autotest_dir == "" else GFX_ULTRA # the autotest always runs on Ultra
	if _autotest_dir == "":
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			if int(cfg.get_value("graphics", "version", 1)) >= 2:
				gfx = clampi(int(cfg.get_value("graphics", "quality", gfx)), 0, GFX_NAMES.size() - 1)
			render_scale = clampf(float(cfg.get_value("graphics", "render_scale", 1.0)), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	hud.set_render_scale(render_scale)
	apply_graphics()


func _save_graphics() -> void:
	if _autotest_dir != "":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", gfx)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "version", GFX_SETTINGS_VERSION)
	cfg.save(SETTINGS_PATH)


func _cycle_graphics() -> void:
	gfx = (gfx + GFX_NAMES.size() - 1) % GFX_NAMES.size() # Ultra → High → Medium → Low → Ultra
	apply_graphics()
	_save_graphics()
	hud.show_toast("Graphics: %s" % GFX_NAMES[gfx])


func set_render_scale(v: float) -> void:
	render_scale = clampf(v, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	_fit_3d_resolution()
	_save_graphics()


func apply_graphics() -> void:
	var med := gfx >= 1
	var hi := gfx >= GFX_HIGH # High and Ultra: the full look
	var ultra := gfx == GFX_ULTRA # everything at full cost
	env.ssao_enabled = med # contact shading
	env.ssil_enabled = hi # light bouncing off nearby surfaces
	env.ssr_enabled = hi # reflections in the pond and wet ground
	# the sun's soft shadows use the high filter at every setting: the shadow filter jitters its
	# samples each frame for the upscaler to average out, and with fewer samples the soft edges
	# (the long end of a shadow most of all) visibly vibrate. Rendering at a third of the screen
	# keeps the extra samples cheap.
	# (High had the ultra filter, 5: 4-5 ms a frame on a MacBook Air for edges you can't tell apart)
	RenderingServer.directional_soft_shadow_filter_set_quality(4)
	RenderingServer.positional_soft_shadow_filter_set_quality([1, 2, 3, 3][gfx])
	Catalog.lamp_shadows = med
	light_budget.max_shadows = LAMP_SHADOWS[gfx] # only the nearest lit lamps cast shadows (candles never)
	light_budget.fade = LAMP_SHADOW_FADE[gfx]
	# the sun's shadow on Low and Medium (Alex, 2026-11-17: "keep high as it is", now Ultra): two splits
	# and a 2048 map instead of four and 4096, and shut shops' lights left off (interiors.gd). High
	# keeps four splits and the big map but reaches less far (SUN_SHADOW_REACH). Below Ultra a shop's
	# furnishings cast no shadow while its roof is on.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if hi else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(4096 if hi else 2048, true)
	Interiors.no_casters = not ultra
	Interiors.lights_off = not hi
	light_budget.update(get_tree(), cam_target, 0.0, true)
	grass.set_quality(GRASS_FRAC[gfx], GRASS_RANGE[gfx], GRASS_THIN[gfx])
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
	var scale := clampf(sqrt(float(TARGET_3D_PIXELS[gfx]) * render_scale / maxf(px.x * px.y, 1.0)), float(MIN_3D_SCALE[gfx]), 1.0)
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
	return "wood" if interior_rect().has_point(q) or builder.indoors(q) or (Town.COTTAGE_ON and Town.COTTAGE.has_point(q)) else "grass"


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
	dirt.append_array(regions.trails) # the trails out to the swamp, the mountains, the beach and the meadows
	for p in plots:
		if p.tilled: # the beds she dug herself
			dirt.append(Rect2(p.position.x - 0.75, p.position.z - 0.75, 1.5, 1.5))
	var clear: Array = grid_blockers.filter(func(r): return r != pond_rect)
	clear.append(Rect2(-0.35, _zmin() - 0.35, HOUSE_W + 0.7, HOUSE_FRONT - _zmin() + 0.7))
	if builder != null: # under the rooms she built (house_builder.gd)
		for room in builder.rooms:
			for rr in room["rects"]:
				clear.append((rr as Rect2).grow(0.35))
	if not painted:
		clear.append(Town.PLAZA)
	if Town.COTTAGE_ON:
		clear.append(Town.COTTAGE.grow(0.3))
	clear.append(Rect2(8.1, 2.35, 1.0, 1.3)) # doormat
	clear.append_array(World.barn_floor()) # its walls block the way; the floor between them only stops the grass
	clear.append_array(Interiors.floors()) # and the shops' floors (their walls and furniture block the way)
	var roads: Image = god.roads_over(Grass.REGION) if painted else null # the grass's mask covers less than the road map
	var pond: Array = god.pond_circles() if god != null else [Vector3(2.5, -16.0, 2.55)]
	if replant:
		grass.build(dirt, clear, pond, roads)
	else:
		grass.remask(dirt, clear, pond, roads)


func _rebuild_house() -> void:
	for c in house_root.get_children():
		c.free()
	walls.clear()
	roofs.clear()
	builder.doors.clear()
	builder.compute() # the rooms her walls close (house_builder.gd)
	_rebuild_grass()
	wall_rects.clear()
	divider_rects.clear()
	var z0 := _zmin()
	var W := HOUSE_W
	var D := HOUSE_FRONT
	var depth := D - z0
	HouseSkin.on(Catalog.box(house_root, Vector3(W + 0.7, 0.1, depth + 0.7), Vector3(W * 0.5, -0.04, z0 + depth * 0.5), Catalog.STONE), "stone")
	_plank_floor(Rect2(0, z0, W, depth), 11, "house")
	var lvl := Game.house_level
	var left_windows := [4.8]
	var right_windows := [0.9]
	for k in range(1, lvl + 1):
		left_windows.append(-4.0 * k + 2.0)
		right_windows.append(-4.0 * k + 2.0)
	# where a room she built joins the house, its wall opens in a doorway (house_builder.gd)
	var sp := builder.house_spans()
	# and where she put a door, sliding doors, a window or a doorway in one of its own walls
	var back := _wall_line(Vector2(0, z0), Vector2(W, z0), Vector3(0, 0, -1), [2.0, 6.0], sp["back"], 6.9, builder.line_edits("back"))
	_wall_line(Vector2(0, D), Vector2(W, D), Vector3(0, 0, 1), [2.0, 6.0], sp["front"], INF, builder.line_edits("front"))
	_wall_line(Vector2(0, z0), Vector2(0, D), Vector3(-1, 0, 0), left_windows, sp["left"], INF, builder.line_edits("left"))
	var right := builder.line_edits("right")
	_wall_line(Vector2(W, z0), Vector2(W, DOOR_Z0), Vector3(1, 0, 0), right_windows, sp["right"], INF, right)
	_wall_line(Vector2(W, DOOR_Z1), Vector2(W, D), Vector3(1, 0, 0), [4.9], sp["right"], INF, right)
	_door_lintel()
	for k in range(1, lvl + 1):
		var z := -4.0 * (k - 1)
		_wall(Vector2(0, z), Vector2(2.6, z), Vector3(0, 0, 1), [], 1.1, false, true)
		_wall(Vector2(5.4, z), Vector2(W, z), Vector3(0, 0, 1), [], 1.1, false, true)
	# the empire banner hangs on the back wall, above the bed corner
	var tall: Node3D = back.get("tall") if not back.is_empty() else null
	var bx := 6.9 - (tall.get_parent() as Node3D).position.x if tall != null else 0.0
	if tall != null: # the banner hangs where the back wall still stands there (_wall_line)
		_banner(tall, bx)
	house_roof = _house_roof(Rect2(0, z0, W, depth), true, "house") # the ridge runs front to back, so it grows with the house
	_chimney_sig = ""
	_update_chimneys()
	builder.build_into() # the walls she built, and each room's floor and roof
	_build_cottage()
	_update_walls()
	if god != null and not god.els.is_empty():
		god.sync_built() # her walls are new nodes now: the world editor's list follows


func _banner(tall: Node3D, bx: float) -> void:
	Catalog.cyl(tall, 0.02, 0.02, 0.9, Vector3(bx, 2.28, 0.14), Catalog.WOOD_DARK, Vector3(0, 0, 90))
	Catalog.box(tall, Vector3(0.7, 1.0, 0.03), Vector3(bx, 1.75, 0.13), Catalog.PLAID_DARK)
	Catalog.box(tall, Vector3(0.6, 0.04, 0.035), Vector3(bx, 2.15, 0.135), Catalog.BRASS)
	Catalog.ball(tall, 0.15, Vector3(bx, 1.8, 0.15), Color(0.78, 0.25, 0.3), Vector3(1, 1, 0.3))
	Catalog.ring(tall, 0.17, 0.2, Vector3(bx, 1.8, 0.15), Catalog.BRASS, Vector3(90, 0, 0))


## A wall line of the house, from a to b, with doorways where a room she built joins it: `spans`
## are the stretches (along x or z) a room shares, each a divider with a doorway in its middle
## (house_builder.gd). `edits` are the 2 m edges she put an opening in ({metres along the line where
## the edge starts: kind}, builder.line_edits()), each drawn by _edge_piece(). Windows go only where
## the wall still stands outdoors. With no spans or edits it's one plain wall. Returns the piece that
## stands at least 0.4 m either side of `keep_at` (along the line), or {}.
func _wall_line(a: Vector2, b: Vector2, normal: Vector3, windows: Array, spans: Array, keep_at := INF, edits := {}) -> Dictionary:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var t0 := a.x if horizontal else a.y
	var t1 := b.x if horizontal else b.y
	var pieces: Array = [] # [from, to, "wall" | "divider" | "gap"]
	var cur := t0
	for s in spans:
		var s0 := maxf(float(s[0]), t0)
		var s1 := minf(float(s[1]), t1)
		if s1 - s0 < 0.6:
			continue
		if s0 > cur:
			pieces.append([cur, s0, "wall"])
		var c := (s0 + s1) * 0.5
		var g := minf(HouseBuilder.DOORWAY, s1 - s0 - 0.3) * 0.5
		pieces.append([s0, c - g, "divider"])
		pieces.append([c - g, c + g, "gap"])
		pieces.append([c + g, s1, "divider"])
		cur = s1
	if cur < t1:
		pieces.append([cur, t1, "wall"])
	if not edits.is_empty():
		var ts: Array = edits.keys()
		ts.sort()
		var split: Array = []
		for p in pieces:
			if p[2] != "wall":
				split.append(p)
				continue
			var at := float(p[0])
			for t in ts:
				var e0 := float(t)
				var e1 := e0 + HouseBuilder.STEP
				if e0 < float(p[0]) - 0.01 or e1 > float(p[1]) + 0.01:
					continue
				if e0 > at:
					split.append([at, e0, "wall"])
				split.append([e0, e1, "edit", str(edits[t])])
				at = e1
			if at < float(p[1]):
				split.append([at, p[1], "wall"])
		pieces = split
	var keep := {}
	for p in pieces:
		var p0: float = p[0]
		var p1: float = p[1]
		if p1 - p0 < 0.02:
			continue
		var pa := Vector2(p0, a.y) if horizontal else Vector2(a.x, p0)
		var pb := Vector2(p1, a.y) if horizontal else Vector2(a.x, p1)
		if p[2] == "gap":
			_lintel(pa, pb, normal)
			continue
		if p[2] == "edit":
			_edge_piece(pa, pb, normal, str(p[3]), [], false)
			continue
		var wins := windows.filter(func(w): return p[2] == "wall" and float(w) - 0.62 >= p0 and float(w) + 0.62 <= p1)
		var w := _wall(pa, pb, normal, wins, WALL_H, true, p[2] == "divider")
		if keep_at - 0.4 >= p0 and keep_at + 0.4 <= p1:
			keep = w
	return keep


## One grid edge of wall from a to b with what's in it (house_builder.gd's kinds): a plain wall with
## `windows` (positions along the line), a window in its middle, or a gap for a doorway, a door or
## sliding doors, the wall standing either side and a lintel over it. Her walls and the house's own
## both use it, so every house takes the same openings.
func _edge_piece(a: Vector2, b: Vector2, normal: Vector3, kind: String, windows: Array, divider: bool, parent: Node3D = null) -> void:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var mid := (a + b) * 0.5
	if kind == "window":
		_wall(a, b, normal, [mid.x if horizontal else mid.y], WALL_H, true, divider, parent)
		return
	if not HouseBuilder.GAPS.has(kind):
		_wall(a, b, normal, windows, WALL_H, true, divider, parent)
		return
	var along := (b - a).normalized()
	var side := (a.distance_to(b) - float(HouseBuilder.GAPS[kind])) * 0.5
	_wall(a, a + along * side, normal, [], WALL_H, true, divider, parent)
	_wall(b - along * side, b, normal, [], WALL_H, true, divider, parent)
	var tall := _lintel(a + along * side, b - along * side, normal, parent)
	if kind != "door":
		builder.hang_door(tall, kind, a + along * side, b - along * side)


## The plaster and beam over a doorway from a to b (no door leaf): a room she built joined to the
## house, or a doorway she put in a wall. Returns the node that stands with the wall (hidden when
## it's cut down), for a door to hang in.
func _lintel(a: Vector2, b: Vector2, normal: Vector3, parent: Node3D = null) -> Node3D:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var gap := a.distance_to(b)
	var mid := (a + b) * 0.5
	var node := Node3D.new()
	var into: Node3D = parent if parent != null else house_root
	into.add_child(node)
	node.position = Vector3(mid.x, 0, mid.y) - (into.position if parent != null else Vector3.ZERO)
	var tall := Node3D.new()
	node.add_child(tall)
	var short := Node3D.new()
	node.add_child(short)
	short.visible = false
	var h := WALL_H - 2.15
	Catalog.box(tall, _sz(horizontal, gap, h, WALL_T), _at(horizontal, 0, 2.15 + h * 0.5), PLASTER)
	Catalog.box(tall, _sz(horizontal, gap + 0.02, 0.16, WALL_T + 0.06), _at(horizontal, 0, WALL_H - 0.08), Catalog.WOOD_DARK)
	Catalog.box(tall, _sz(horizontal, gap + 0.1, 0.1, WALL_T + 0.08), _at(horizontal, 0, 2.15), Catalog.WOOD_DARK)
	for d in [-1.0, 1.0]: # the jambs
		Catalog.box(tall, _sz(horizontal, 0.08, 2.15, WALL_T + 0.08), _at(horizontal, d * (gap * 0.5 - 0.04), 1.075), Catalog.WOOD_DARK)
	walls.append({"tall": tall, "short": short, "normal": normal, "cut": true})
	return tall


func _wall(a: Vector2, b: Vector2, normal: Vector3, windows: Array, height := WALL_H, cut := true, divider := false, parent: Node3D = null) -> Dictionary:
	var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var node := Node3D.new()
	node.position = Vector3(mid.x, 0, mid.y) - (parent.position if parent != null else Vector3.ZERO)
	(parent if parent != null else house_root).add_child(node)
	var tall := Node3D.new()
	node.add_child(tall)
	var short := Node3D.new()
	node.add_child(short)
	# the plaster, in pieces round the windows, so the glass has the room behind it
	var pieces: Array = [Rect2(0, 0.07, length, height - 0.15)] # its ends tucked inside the oak rails, never flush with them
	for wpos in windows:
		pieces = Planks._cut(pieces, Rect2(float(wpos) - (mid.x if horizontal else mid.y) - 0.58 + length * 0.5, 0.99, 1.16, 1.12))
	for pr in pieces:
		var q := pr as Rect2
		HouseSkin.on(Catalog.box(tall, _sz(horizontal, q.size.x, q.size.y, WALL_T), _at(horizontal, q.get_center().x - length * 0.5, q.get_center().y), PLASTER), "plaster")
	HouseSkin.oak(Catalog.box(tall, _sz(horizontal, length + 0.02, 0.16, WALL_T + 0.06), _at(horizontal, 0, height - 0.08), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(tall, _sz(horizontal, length, 0.14, WALL_T + 0.04), _at(horizontal, 0, 0.07), Catalog.WOOD_DARK))
	var posts := maxi(1, int(round(length / 2.0)))
	for i in posts + 1:
		var o := -length * 0.5 + length * i / posts
		if windows.any(func(wp): return absf(float(wp) - (mid.x if horizontal else mid.y) - o) < 0.66):
			continue # no post across a window: the glass shows the room now
		HouseSkin.oak(Catalog.box(tall, _sz(horizontal, 0.16, height, WALL_T + 0.05), _at(horizontal, o, height * 0.5), Catalog.WOOD_DARK))
	if not divider: # a fieldstone footing along the outside, under the sill rail
		var fo := (normal.z if horizontal else normal.x) * (WALL_T * 0.5 + 0.03)
		HouseSkin.on(Catalog.box(tall, _sz(horizontal, length + 0.08, 0.3, 0.1), _at(horizontal, 0, 0.13, fo), Catalog.STONE), "stone")
	var holes: Array = []
	for wpos in windows:
		var o := float(wpos) - (mid.x if horizontal else mid.y)
		_window(tall, o, horizontal)
		holes.append(Rect2(o - 0.58 + length * 0.5, 0.99, 1.16, 1.12))
	for side in ([-1.0, 1.0] if divider else [-1.0]): # a room divider is indoors on both sides
		_wall_boards(tall, horizontal, length, height, normal * side, holes)
	HouseSkin.on(Catalog.box(short, _sz(horizontal, length, 0.32, WALL_T), _at(horizontal, 0, 0.16), PLASTER), "plaster")
	HouseSkin.oak(Catalog.box(short, _sz(horizontal, length + 0.02, 0.06, WALL_T + 0.06), _at(horizontal, 0, 0.33), Catalog.WOOD_DARK))
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
	glass.material_override = Catalog.window_glass()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # sunlight comes in through it
	var t := WALL_T + 0.08
	for y in [1.03, 2.07]:
		HouseSkin.oak(Catalog.box(parent, _sz(horizontal, 1.16, 0.08, t), _at(horizontal, o, y), Catalog.WOOD_DARK))
	for d in [-0.54, 0.54]:
		HouseSkin.oak(Catalog.box(parent, _sz(horizontal, 0.08, 1.12, t), _at(horizontal, o + d, 1.55), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(parent, _sz(horizontal, 0.04, 1.0, t - 0.02), _at(horizontal, o, 1.55), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(parent, _sz(horizontal, 1.0, 0.04, t - 0.02), _at(horizontal, o, 1.55), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(parent, _sz(horizontal, 1.25, 0.06, WALL_T + 0.24), _at(horizontal, o, 0.98), Catalog.WOOD), HouseSkin.LIGHT_OAK)


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
	HouseSkin.on(Catalog.box(tall, Vector3(WALL_T, h, gap), Vector3(0, 2.15 + h * 0.5, 0), PLASTER), "plaster")
	HouseSkin.oak(Catalog.box(tall, Vector3(WALL_T + 0.06, 0.16, gap + 0.02), Vector3(0, WALL_H - 0.08, 0), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(tall, Vector3(WALL_T + 0.08, 0.1, gap + 0.1), Vector3(0, 2.15, 0), Catalog.WOOD_DARK))
	# open door leaf, swung outward
	HouseSkin.oak(Catalog.box(tall, Vector3(1.2, 2.05, 0.06), Vector3(0.62, 1.03, -gap * 0.5 + 0.05), Catalog.WOOD), HouseSkin.LIGHT_OAK)
	Catalog.ball(tall, 0.035, Vector3(1.1, 1.0, -gap * 0.5 + 0.1), Catalog.BRASS)
	walls.append({"tall": tall, "short": short, "normal": Vector3(1, 0, 0), "cut": true})


const ROOF_PITCH := 34.0 # degrees
const ROOF_EAVES := 0.35 # metres the roof reaches past the walls
const ROOF_COLOR := Color(0.42, 0.21, 0.16) # weathered red-brown shingles
const RIDGE_COLOR := Color(0.27, 0.15, 0.11)


## A gable roof over the walls of rect r (wall lines), its ridge along z (or x): a plastered
## gable with its flat underside as the ceiling, two shingled slopes with eaves, a ridge cap and
## dark fascia boards along the eaves. Like the barn and the shops, it lifts off while she's
## inside, from above, and stays on in first person (_update_walls).
func _house_roof(r: Rect2, ridge_z: bool, group := "") -> Node3D:
	var root := Node3D.new()
	root.name = "Roof"
	root.position = Vector3(r.get_center().x, WALL_H, r.get_center().y)
	root.rotation.y = 0.0 if ridge_z else PI * 0.5
	house_root.add_child(root)
	var span := (r.size.x if ridge_z else r.size.y) + WALL_T # across the ridge
	var length := (r.size.y if ridge_z else r.size.x) + WALL_T # along it
	var half := span * 0.5
	var rise := tan(deg_to_rad(ROOF_PITCH)) * half
	var gable := PrismMesh.new()
	gable.size = Vector3(span, rise, length)
	var g := MeshInstance3D.new()
	g.name = "Gable"
	g.mesh = gable
	g.material_override = HouseSkin.material("plaster")
	g.position = Vector3(0, rise * 0.5, 0)
	root.add_child(g)
	var out := half + ROOF_EAVES
	var slope := out / cos(deg_to_rad(ROOF_PITCH))
	var run := length + ROOF_EAVES * 2.0
	var t := 0.12
	for sx in [-1.0, 1.0]:
		# each slope hangs from the ridge, in its own space: x down the slope, y out of it
		var side := Node3D.new()
		side.position = Vector3(0, rise, 0)
		side.rotation.z = -sx * deg_to_rad(ROOF_PITCH)
		root.add_child(side)
		# cedar shingles in courses down the slope (art/world_assets/house_exterior): the map's
		# butts face +x, so the slope whose down is -x takes its mirror
		HouseSkin.on(Catalog.box(side, Vector3(slope, t, run), Vector3(sx * slope * 0.5, t * 0.5, 0), ROOF_COLOR), "shingles" if sx > 0.0 else "shingles_r")
		HouseSkin.oak(Catalog.box(side, Vector3(0.06, 0.22, run + 0.04), Vector3(sx * (slope + 0.02), t * 0.5 - 0.02, 0), RIDGE_COLOR), HouseSkin.DARK_OAK) # fascia
	HouseSkin.oak(Catalog.box(root, Vector3(0.22, 0.14, length + ROOF_EAVES * 2.0 + 0.06), Vector3(0, rise + 0.1, 0), RIDGE_COLOR), HouseSkin.DARK_OAK) # ridge cap
	roofs.append({"node": root, "rect": r, "group": group if group != "" else str(r)}) # a building's roofs lift together
	return root


## A chimney stands out of her roof over every fireplace in the house (Alex, 2026-11-16: "add
## chimneys coming out of the roof whenever there's a fireplace"): a fieldstone stack rising from
## behind the fireplace, against the wall it backs onto, past the ridge, with a corbelled band, a
## cap and two clay pots. They're children of the roof, so they lift off with it, and they're built
## again whenever a fireplace is placed, moved or sold (checked each frame by where they stand).
func _update_chimneys() -> void:
	if house_roof == null or not is_instance_valid(house_roof):
		return
	var inside := interior_rect()
	var spots: Array = []
	var sig := ""
	for f in furniture:
		if not is_instance_valid(f) or (f as Furniture).item_id != "fireplace" or (f as Furniture).is_queued_for_deletion():
			continue
		var fp := f as Furniture
		if not inside.has_point(Vector2(fp.position.x, fp.position.z)):
			continue
		var back := fp.position - fp.front() * 0.3 # its flue runs up behind it, into the wall it backs onto
		spots.append(back)
		sig += "%.2f,%.2f;" % [back.x, back.z]
	if sig == _chimney_sig:
		return
	_chimney_sig = sig
	for c in house_roof.get_children():
		if c.name.begins_with("Chimney"):
			c.free()
	var r := house_rect().grow(-0.45)
	var half := (house_rect().size.x) * 0.5
	var rise := tan(deg_to_rad(ROOF_PITCH)) * half
	for p in spots:
		var at := Vector3(clampf(p.x, r.position.x, r.end.x), 0, clampf(p.z, r.position.y, r.end.y))
		var ch := Node3D.new()
		ch.name = "Chimney"
		ch.position = at - Vector3(house_roof.position.x, 0, house_roof.position.z)
		house_roof.add_child(ch)
		var top := rise + 0.8
		HouseSkin.on(Catalog.box(ch, Vector3(0.62, top, 0.74), Vector3(0, top * 0.5, 0), Catalog.STONE), "stone")
		HouseSkin.on(Catalog.box(ch, Vector3(0.74, 0.12, 0.86), Vector3(0, top - 0.24, 0), Catalog.STONE), "stone") # the corbelled band
		HouseSkin.on(Catalog.box(ch, Vector3(0.7, 0.07, 0.82), Vector3(0, top + 0.02, 0), Catalog.STONE), "stone") # the cap
		for dz in [-0.17, 0.17]:
			Catalog.cyl(ch, 0.075, 0.095, 0.3, Vector3(0, top + 0.21, dz), Color(0.62, 0.32, 0.22))
	return


## Whether the roofs over her lift off now: from above while she's inside (as the barn's and
## the shops' do), and whenever she's furnishing (building mode, placing a piece, the world
## editor). Never in first person, where she's under them.
func _roof_lifted(r: Rect2) -> bool:
	if fps != null and fps.active:
		return false
	if mode == Mode.BUILD or ghost != null or (god != null and god.active):
		return true
	if player == null:
		return false
	# in a story scene on the porch or at the door she's outside, and the house should look like one
	var grow := 0.0 if _scene_outdoors() else 0.3
	return r.grow(grow).has_point(Vector2(player.position.x, player.position.z))


## A story scene is playing with Nora outside her house and the cottage: the house's walls stay up
## and its roof on, so the shot shows a home rather than a cutaway.
func _scene_outdoors() -> bool:
	if story == null or not story.is_playing() or player == null:
		return false
	var p := Vector2(player.position.x, player.position.z)
	return not interior_rect().has_point(p) and not builder.indoors(p) and not (cottage_owned() and cottage_interior().has_point(p))


func _update_walls() -> void:
	var open_rects: Array = [] # the buildings whose roof is off: only theirs cut their walls down
	var lifted_groups := {} # a house and the rooms she built onto it lift their roofs together
	for rf in roofs:
		if _roof_lifted(rf["rect"]):
			lifted_groups[rf["group"]] = true
	for rf in roofs:
		var n := rf["node"] as Node3D
		var lifted := lifted_groups.has(rf["group"])
		if is_instance_valid(n):
			n.visible = not lifted
		if lifted:
			open_rects.append((rf["rect"] as Rect2).grow(0.5))
	var cdir := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var outdoors := _scene_outdoors()
	for w in walls:
		# with its roof on (she's outside), a house keeps all four walls
		var at: Vector3 = (w["tall"] as Node3D).get_parent().global_position if (w["tall"] as Node3D).is_inside_tree() else Vector3.ZERO
		var open := roofs.is_empty() or open_rects.any(func(r): return (r as Rect2).has_point(Vector2(at.x, at.z)))
		var hide_it: bool = w["cut"] and open and not walls_up and not outdoors and (w["normal"] as Vector3).dot(cdir) > 0.25
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
	if builder.blocks(new_area.grow(-0.15)):
		hud.show_toast("The walls you built behind the house are in the way.")
		return
	for f in furniture:
		if f.footprint().intersects(new_area):
			hud.show_toast("Move the %s out of the way first — the new room goes there." % f.display_name())
			return
	if not Game.spend(Game.EXPAND_COSTS[Game.house_level]):
		return
	Game.house_level += 1
	builder.prune_house() # openings in the old back wall come out, paid back
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
	rects.append_array(regions.trunk_blocks())
	for f in furniture:
		if not f.is_flat():
			rects.append(f.footprint())
	for r in rects:
		_mark_rect((r as Rect2).grow(0.2))
	if suburb != null and suburb.walk_in != null:
		suburb.walk_in.mark_grid() # Marcus's house: its own walls, on the floor she's on (split_house.gd)


## Where she may walk: the whole map (Alex, 2026-11-14: she, and the dog, can go anywhere until the
## map ends), from the mountains' foot down to the shore. Her land, the road, the town, the lands
## and the ground round every building are listed too, so a shop moved to the edge still counts.
## What stands in the way (trees, rocks, buildings, pools) blocks it in _rebuild_grid.
func walk_areas() -> Array:
	var areas: Array = [LOT, Town.ROAD, Town.TOWN]
	areas.append(whole_map())
	areas.append_array(regions.walk_areas())
	for b in Town.built:
		var n := b[0] as Node3D
		if is_instance_valid(n) and n.visible:
			var half := 6.5
			if str(b[1]) == "building_cafe": # its lot and terrace are bigger than the rest
				half = maxf(Town.CAFE.size.x, Town.CAFE.size.y) * 0.5 + 1.5
			areas.append(Rect2(n.global_position.x - half, n.global_position.z - half, half * 2.0, half * 2.0))
	return areas


## All of the map she can walk on: the grid's bounds, short of the sea.
func whole_map() -> Rect2:
	var b := CAM_BOUNDS.grow(-0.5)
	var shore: float = regions.shore_z - 1.5 if regions and regions.shore_z > 0.0 else b.end.y
	return Rect2(b.position, Vector2(b.size.x, minf(b.end.y, shore) - b.position.y))


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
	# a walk up or down the café's stairs: its loft has a grid of its own (interiors.gd)
	var loft: Variant = Interiors.loft_route(from, to, _find_path_ground)
	if loft != null:
		return loft
	return _find_path_ground(from, to)


func _find_path_ground(from: Vector3, to: Vector3) -> Array:
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
	player.in_scene = story.is_playing()
	_update_tags(delta)
	_update_camera(delta)
	see_through.update(delta)
	_update_walls()
	_update_chimneys()
	_update_held_tool()
	_update_sweater()
	_update_hold(delta)
	_update_flock(delta)
	World.update_barn(player.position, cam_yaw, walls_up, delta,
		sheep_list.filter(func(s): return not s.route.is_empty()).map(func(s): return s.position))
	Interiors.update(player.position, cam_yaw, walls_up, delta, villagers.map(func(v): return v.position), fps.active)
	_update_lighting()
	light_budget.update(get_tree(), cam.global_position if fps.active or cinema.active else cam_target, delta)
	_update_story_staging(delta)
	_update_needs(delta)
	_update_gaze()
	_update_tips(delta)
	_update_hints(delta)
	_update_new_talk(delta)
	if not title_on and not get_tree().paused: # how long she has played this save (Max's visit waits for it)
		Game.flags["play_secs"] = float(Game.flags.get("play_secs", 0.0)) + delta
	_update_rounds(delta)
	jobs.update(delta)
	empire.update(delta)
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
	grass.follow(cam.global_position)
	if player.walked > 0.0:
		if Game.time_running:
			Game.add_need("fitness", player.walked * 0.06)
		player.walked = 0.0
	player.walk_speed = (1.47 + 0.21 * Game.fitness / 100.0) * 1.25 # a brisk walk; the Walk loop speeds up to match
	player.run_speed = 2.75 + 0.6 * Game.fitness / 100.0
	player.running = autotest_jog or _held(KEY_SHIFT)
	_update_dog()
	var head := player.head_point()
	var show := player.busy and not story.is_playing() and not sleeping and not hide_activity_bar and not knit.active and not fps.active and not cam.is_position_behind(head)
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
	var book = ReadingPose.holding(a)
	if book != null:
		return book.look_point() # down into the pages
	if a == player and fps.active and not player.busy:
		return fps.look_point() # her head turns the way the view looks
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
	if cinema.active or fps.active:
		return # cinematic.gd flies the camera; first_person.gd puts it at her eyes
	if not _photo_dof.is_empty():
		_apply_photo_dof()
	# close-ups get a soft background
	var near := cam_dist < 9.0 and _photo_dof.is_empty()
	if _photo_dof.is_empty():
		cam_attr.dof_blur_far_enabled = near
	# spend the shadow map on what's on screen: sharper shadows the closer the camera is
	sun.directional_shadow_max_distance = clampf(cam_dist * 2.4 + 8.0, 20.0, SUN_SHADOW_REACH[gfx])
	if near and _photo_dof.is_empty():
		cam_attr.dof_blur_far_distance = cam_dist + 2.5
		cam_attr.dof_blur_far_transition = 6.0
	var pan := hud.cam_pad_pan if not story.is_playing() else Vector2.ZERO
	if not sleeping and not story.is_playing() and not books_ui.visible:
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


## What stops first person (first_person.gd), or ends it when it starts: a story scene, sleep,
## the title, the knitting game, the cinematic camera, the world editor, building mode
## and playing the dog.
func fp_blocked() -> bool:
	return sleeping or title_on or knit.active or story.is_playing() or cinema.active or god.active \
		or mode != Mode.LIVE or (dog != null and dog.controlled)


## Layout-proof key check: matches the key by its label or by its physical position.
func _held(k: Key) -> bool:
	if knit != null and knit.active:
		return false # the game's keys (D F J K) must not pan the camera
	k = Keys.key_for(k, ["move"]) # walking and running, wherever the player bound them
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
	if cinema.active:
		cinema.handle_mouse(e)
		return
	if wview.active:
		wview.handle_mouse(e)
		return
	if barista.active:
		barista.handle_mouse(e)
		return
	if store.active:
		store.handle_mouse(e)
		return
	if fps.active:
		fps.handle_mouse(e)
		return
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
				elif mb.pressed and builder.tool != "" and mb.button_index == MOUSE_BUTTON_RIGHT:
					builder.set_tool("") # right-click puts the wall tool down
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
					hud.hide_dialogue()
					if mode == Mode.BUILD and builder.tool != "":
						builder.click(_ground_point(mb.position)) # lay a wall, or take one of hers down
					elif mode == Mode.BUILD:
						_build_click(mb.position, mb.shift_pressed)
					else:
						_live_click(mb.position)
				else:
					hold_release()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		_last_mouse = mm.position
		if drag_pan:
			_set_cam_lock(false)
			_pan_camera(Vector2(-mm.relative.x, -mm.relative.y) * 0.03 * cam_dist / 23.0)
		if ghost:
			_update_ghost(mm.position)
		elif mode == Mode.BUILD and builder.tool != "":
			builder.hover_at(_ground_point(mm.position))
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
	if e is InputEventKey and hud.binding_key() and (_autotest_dir == "" or e.has_meta("ke_test")):
		# Settings > Key bindings is waiting for a key: it gets the next one, whatever it is
		var bk := e as InputEventKey
		if bk.pressed and not bk.echo:
			hud.capture_key(bk.keycode if bk.keycode != KEY_NONE else bk.physical_keycode)
		get_viewport().set_input_as_handled()
		return
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
	if cinema.active:
		cinema.handle_key(kc) # every key belongs to the free camera while it flies
		get_viewport().set_input_as_handled()
		return
	if wview.active and wview.handle_key(kc):
		get_viewport().set_input_as_handled()
		return
	if barista.active and barista.handle_key(kc):
		get_viewport().set_input_as_handled()
		return
	if store.active and store.handle_key(kc):
		get_viewport().set_input_as_handled()
		return
	if fps.active and fps.handle_key(kc):
		get_viewport().set_input_as_handled()
		return
	if books_ui.visible and books_ui.handle_key(kc): # the arrow keys turn the pages
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
	match Keys.map(kc, ["world"]): # the player's key bindings, as the default keys below
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
		KEY_P:
			cinema.enter()
		KEY_V:
			fps.enter()
		KEY_SPACE:
			_set_cam_lock(not cam_follow, true)
		KEY_B:
			set_mode(Mode.LIVE if mode == Mode.BUILD else Mode.BUILD)
		KEY_DELETE, KEY_BACKSPACE, KEY_X:
			_sell_ghost()
		KEY_ESCAPE:
			if ghost:
				_cancel_ghost()
			elif builder.tool != "":
				builder.set_tool("")
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
			elif hud.keys_open():
				hud.close_keys()
			elif hud.settings_panel.visible:
				hud.settings_panel.visible = false
			elif hud.journal_panel.visible:
				hud.journal_panel.visible = false
			elif hud.album.visible:
				hud.album.close()
			elif hud.letters.visible:
				hud.letters.close()
			elif wardrobe_ui.visible:
				wardrobe_ui.close()
			elif sale.visible:
				sale.close()
			elif books_ui.visible:
				books_ui.close()
			elif mode == Mode.BUILD:
				set_mode(Mode.LIVE)
			else:
				hud.toggle_game_menu()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## A panel that wants the mouse is open (a book, the bag, a letter...): first person lets the mouse
## go while it is, and gives Esc to it (first_person.gd).
func panel_open() -> bool:
	return books_ui.visible or wardrobe_ui.visible or sale.visible or hud.letters.visible or hud.bag_panel.visible \
		or hud.album.visible or hud.journal_panel.visible or hud.settings_panel.visible or hud.help_panel.visible \
		or hud.keys_open() or hud.game_menu.visible or homestead.ui.is_open()


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
	var lp: Variant = Interiors.loft_pick(player.position, cam.project_ray_origin(mpos), cam.project_ray_normal(mpos))
	if lp != null: # upstairs in the café: its floor
		return lp
	if suburb != null and suburb.walk_in != null and suburb.walk_in.inside:
		return suburb.walk_in.pick(cam.project_ray_origin(mpos), cam.project_ray_normal(mpos)) # its floors aren't at ground level
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(mpos), cam.project_ray_normal(mpos))


func _update_hover(mpos: Vector2) -> void:
	var t = _ray_target(mpos)
	var clickable := false
	if t != null:
		clickable = (mode == Mode.BUILD and t is Furniture and furniture.has(t)) or (mode == Mode.LIVE and not _actions_for(t).is_empty())
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if clickable else Input.CURSOR_ARROW)
	_hover_v = t if t != null and villagers.has(t) else null


## Name tags: only the villager under the mouse and the one nearest Nora (within TAG_NEAR) show
## theirs, fading in and out, so two people standing together never stack their names.
const TAG_NEAR := 7.0
var _hover_v = null


func _update_tags(delta: float) -> void:
	var nearest = null
	var best := TAG_NEAR
	for v in villagers:
		var d: float = (v.position - player.position).length()
		if d < best and v.visible:
			best = d
			nearest = v
	for v in villagers:
		if v.tag == null:
			continue
		var want := 1.0 if (v == _hover_v or v == nearest) else 0.0
		v.tag.modulate.a = move_toward(v.tag.modulate.a, want, delta * 4.0)
		v.tag.outline_modulate.a = v.tag.modulate.a


# --- the dog -------------------------------------------------------------------------

## For now he's with her from the start of every game, Act 1 included (Alex, 2026-11-13); his
## arrival in the story comes later. False brings back the old cue: on the story farm he turns up
## once the pen is built (homestead.gd's "pen_done", the "pen_built" story event).
const DOG_FROM_START := true


func dog_here() -> bool:
	return DOG_FROM_START or dog_herds()


## Whether he can herd yet. On the story farm only once the pen is built, so he doesn't scatter
## the strays before there's a pen to drive them into. Even then only while the player plays him
## (_update_dog): following Nora he moves nothing (Alex, 2026-11-16).
func dog_herds() -> bool:
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
		hud.show_toast("You're the dog now. Click to run about, Shift to gallop, right-click to bark at wild animals, Tab to go back to Nora.")
	_set_cam_lock(true)


## The dog barks (a right click while you play him, or by himself when sent to round an animal up): the
## sound, and every wild animal near him takes fright (wildlife.gd). False if he has no breath yet.
func dog_bark() -> bool:
	if dog == null or not dog.bark():
		return false
	audio.play("bark", -3.0, 0.12)
	if wildlife:
		wildlife.barked(dog.global_position)
	if wolves:
		wolves.barked(dog.global_position)
	return true


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
	if homestead:
		var herds := dog_herds() and dog.controlled
		if herds and not homestead.herders.has(dog):
			homestead.herders.append(dog)
		elif not herds:
			homestead.herders.erase(dog)
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
		_hold_t = 0.0 # held down, he keeps going the way the mouse points (_update_hold)
		return
	if g != null:
		player.walk(_find_path(player.position, g))
		_click_marker(g)
		_hold_t = 0.0


# --- walking: a click on the map, or the mouse held down -----------------------------------

const HOLD_AFTER := 0.22 # s the button must stay down before a click becomes steering
const HOLD_AHEAD := 2.5 # m: while steering she always heads for a point this far toward the mouse
var _hold_t := -1.0 # s the left button has been down after a click on open ground; -1 when it isn't
var _hold_steering := false
var _hold_repath := 0.0


## Who a click on the ground moves: the dog while the player steers him (Tab), else Nora.
func _walker() -> Node3D:
	return dog if dog and dog.controlled else player


## A click on the minimap: she (or the dog) walks to that spot of the world. True if they set off.
func minimap_walk(g: Vector3) -> bool:
	if sleeping or story.is_playing() or title_on or knit.active or cinema.active or god.active or mode != Mode.LIVE:
		return false
	Game.set_flag("hint_map") # she found the map by herself: no need for its hint
	hud.hide_menu()
	hud.hide_dialogue()
	var w := _walker()
	var p := _find_path(w.position, g)
	if p.is_empty():
		return false
	w.walk(p)
	_click_marker(g)
	return true


## The left button came up: if she was being steered she stops where she is; a quick click just
## carries on to where it was sent.
func hold_release() -> void:
	if _hold_steering:
		_walker().walk([])
	_hold_t = -1.0
	_hold_steering = false


## While the button stays down after a click on open ground, she walks the way the mouse points
## from her, until it comes up.
func _update_hold(delta: float) -> void:
	if _hold_t < 0.0:
		return
	if _autotest_dir == "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hold_release() # the button came up over a panel, where we never heard of it
		return
	if sleeping or story.is_playing() or title_on or knit.active or cinema.active or god.active or mode != Mode.LIVE or hud.is_menu_open():
		_hold_t = -1.0
		_hold_steering = false
		return
	_hold_t += delta
	if _hold_t < HOLD_AFTER:
		return
	_hold_steering = true
	_hold_repath -= delta
	if _hold_repath > 0.0:
		return
	_hold_repath = 0.12
	var w := _walker()
	var g = _ground_point(_last_mouse)
	if g == null:
		return
	var d := Vector3(g.x - w.position.x, 0, g.z - w.position.z)
	if d.length() < 0.6:
		w.walk([]) # the mouse is on her: she waits there
		return
	var to := w.position + d.normalized() * HOLD_AHEAD
	w.walk(_find_path(w.position, to))


var _rclick_from := Vector2(-999, -999)


## A right click: the ring of what she can do there. On a thing, its own actions; on open
## ground, walking there and (with her hoe) digging a bed. Beds are only ever dug from here, so a
## plain click never turns the lawn over by accident.
func _right_click(mpos: Vector2) -> void:
	if dog and dog.controlled: # as the dog, a right click barks (and the camera comes back to him)
		dog_bark()
		_set_cam_lock(true)
		return
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
	if house_rect().grow(0.3).has_point(q) or (Town.COTTAGE_ON and Town.COTTAGE.grow(0.3).has_point(q)):
		return true
	if builder.indoors(q) or builder.blocks(Rect2(q - Vector2(0.3, 0.3), Vector2(0.6, 0.6))): # a room or a wall she built
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


## Dresses her in the sweater she wears (Game.worn_design; none in the city coat).
func _update_sweater() -> void:
	if player.body == null or player.body.skeleton == null:
		return
	var want := Game.worn_design # a Common one too (warmth 1, like the coat, but she has it on)
	if want == "" and not Sweaters.coat_on(player.body):
		Sweaters.wear_coat(player.body) # no sweater: her thin city coat
	elif want != "" and want != Sweaters.worn(player.body):
		Sweaters.wear(player.body, want)
	var bought: Dictionary = Game.flag("npc_sweaters", {}) # villagers wear only what they bought from her
	for v in villagers:
		if v.body and v.body.skeleton:
			var w: String = str(bought.get(v.vid, ""))
			if w != Sweaters.worn(v.body):
				Sweaters.wear(v.body, w)


## What a villager pays for one of her sweaters to wear: Rosa's price for it.
func _wear_price(rarity: int) -> int:
	return int(round(_rosa_price() * float(Game.RARITY_PRICE[clampi(rarity, 1, 5) - 1])))


## She sells the villager her i-th sweater for `price` (agreed in sweater_sale.gd); they pay and
## keep it, and anyone with a sweater fitted to them puts it on.
func sell_sweater_to(v, i: int, price: int) -> bool:
	if i < 0 or i >= Game.sweaters.size():
		return false
	var sw := Game.remove_sweater(i)
	var d := Sweaters.design(str(sw.get("design", "")))
	Game.coins += price
	if Sweaters.fits(v.vid) and not d.is_empty():
		var bought: Dictionary = Game.flag("npc_sweaters", {}).duplicate()
		bought[v.vid] = str(d["id"])
		Game.set_flag("npc_sweaters", bought)
	var days: Dictionary = Game.flag("npc_sweater_day", {}).duplicate()
	days[v.vid] = Game.day
	Game.set_flag("npc_sweater_day", days)
	Game.add_friendship(v.vid, 10)
	Game.add_need("happiness", 4.0)
	var wearing := Sweaters.fits(v.vid) and not d.is_empty()
	hud.show_toast("Sold %s to %s for %dc.%s" % [str(d.get("name", "a sweater")), v.title, price, " They're wearing it!" if wearing else ""])
	return true


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
			var plant = forage.plant_at(mpos) if t == null and forage else null
			if plant != null: # Gran's shears take a bush, a tuft or a flower clump down to the ground, for leaves
				var at: Vector3 = plant.xf.origin
				at.y = 0.0
				var side := player.position - at
				side.y = 0.0
				side = side.normalized() if side.length() > 0.1 else Vector3(0, 0, 1)
				_tool_walk(at, at + side * (0.6 + plant.radius * 0.4), 1.5, "Trimming", 1.2, _finish_trim.bind(plant))
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
				var why: String = forage.fell_problem(tree)
				if why != "":
					hud.show_toast(why)
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


## The tree comes down (forage.gd): it's gone until it grows back, and its wood is hers.
func _finish_chop(tree) -> void:
	if tree.cut:
		return
	var wood: int = forage.fell(tree)
	Game.add_need("fitness", 3.0)
	hud.show_toast("Timber! +%d wood" % wood)
	_story_event_soon("wood_bought") # Act 1's pen wants wood, bought or felled


func _finish_trim(plant) -> void:
	if plant.cut:
		return
	var n: int = forage.trim(plant)
	Game.add_need("fitness", 0.5)
	hud.show_toast("+%d leaves" % n)


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
	return t.display_name()


## A bed's planting row: it takes one of her seeds (Gran's tin, a villager's gift, Builder's Delight).
func _plant_row(crop: String) -> Dictionary:
	var n := Game.count(crop + "_seeds")
	var hours := int(Plot.CROPS[crop]["hours"])
	if n <= 0:
		return _act("plant_" + crop, "Plant %ss  (no seeds: Builder's Delight sells them)" % crop, false)
	return _act("plant_" + crop, "Plant %ss  (%d seeds · %d hrs)" % [crop, n, hours], true)


func _act(id: String, label: String, enabled := true) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled}


func _actions_for(t) -> Array:
	if t is Node and t.has_method("ke_actions"): # small things that list their own (Gran's tin)
		return t.ke_actions()
	if t is Furniture:
		match t.item_id:
			"rocking_chair", "armchair":
				return [_act("knit", "Knit Sweater…  (3 wool)", Game.has_item("wool", 3))] + wildlife.knit_rows() + [_act("rest", "Rest  (+energy)"), _act("read_book", "Read a book…")]
			"sofa":
				return [_act("rest", "Rest  (+energy)"), _act("nap", "Take a nap  (1 hour)"), _act("read_book", "Read a book…")]
			"bench", "bench_short":
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
				return [_act("read", "Read a knitting book"), _act("read_pick", "Choose a book…")]
			"wardrobe":
				return [_act("wardrobe", "Choose a sweater…")]
			"computer":
				return [_act("computer", "Use the computer…  (%d orders)" % store.orders().size() if store.started() else "Use the computer…")]
		return []
	if t is Plot:
		if t.crop == "":
			return [_plant_row("turnip"), _plant_row("pumpkin")]
		if t.is_ready():
			return [_act("harvest", "Harvest %s" % t.display_name())]
		var acts := []
		if t.watered:
			acts.append(_act("noop", "Watered today ✓", false))
		else:
			acts.append(_act("water", "Water"))
		var ml := int(forage.econ("mulch_leaves", 3))
		acts.append(_act("mulch", "Mulch with leaves  (%d of %d · grows on faster)" % [ml, Game.count("leaves")], Game.count("leaves") >= ml))
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
	if t is Node and t.has_method("stand_point"): # a reading seat or shelf in a shop knows its own
		return t.stand_point()
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
				hud.show_dialogue("Rosewood Cottage", -1, "A cozy cottage with a garden lot, just off the plaza. For sale: %dc. Gary at Willow Homes handles the sale. Furnish it and renters pay you every morning." % _cottage_price())
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
	if t is Villager and not t.has_method("ke_action"): # the townsfolk answer for themselves (townsperson.gd)
		t.face_point(player.position, 10.0)
		player.talk(4.0)
		_villager_action(t, id)
		return
	if t.has_method("ke_action"):
		t.ke_action(id)
		return
	if id.begins_with("knit_fibre:"): # two wool and one wild fibre: the sweater is at least that fibre's floor
		var fibre := id.trim_prefix("knit_fibre:")
		if not (Game.has_item("wool", 2) and Game.has_item(fibre)):
			hud.show_toast("You need 2 wool and the %s." % wildlife.item_name(fibre))
			return
		if Game.use_energy(10.0):
			_knit_fibre = fibre
			_begin_knit(t)
		return
	match id:
		"knit":
			if not Game.has_item("wool", 3):
				hud.show_toast("You need 3 wool to knit a sweater. Shear a sheep!")
				return
			if Game.use_energy(10.0):
				_knit_fibre = ""
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
		"wardrobe":
			wview.open(t) # the list (wardrobe_ui) if first person can't start
		"computer":
			store.open(t) # the online store's page on its screen (online_store.gd)
		"read_book", "read_pick":
			begin_read(t, id)
		"read":
			player.start_activity("Reading", 3.0, func():
				Game.energy = minf(100.0, Game.energy + 8.0)
				Game.add_need("happiness", 6.0)
				hud.show_toast("You learned a new cable stitch. (+8 energy)"))
		"plant_turnip", "plant_pumpkin":
			var crop := id.substr(6)
			if t.crop != "":
				return
			if Game.has_item(crop + "_seeds") and Game.use_energy(2.0) and Game.take_item(crop + "_seeds", 1):
				player.start_activity("Planting", 1.2, _finish_plant.bind(t, crop))
		"water":
			if Game.use_energy(2.0):
				player.start_activity("Watering", 1.0, _finish_water.bind(t))
		"mulch": # leaves from her shears, tucked round the crop: it comes on a good way at once
			var ml := int(forage.econ("mulch_leaves", 3))
			if t.crop != "" and not t.is_ready() and Game.use_energy(1.0) and Game.take_item("leaves", ml):
				player.start_activity("Mulching", 1.0, func():
					t.growth = minf(t.hours_needed(), t.growth + t.hours_needed() * float(forage.econ("mulch_growth", 0.25)))
					t.refresh()
					hud.show_toast("Leaf mulch: the %s comes on." % t.display_name().to_lower()))
		"harvest":
			if Game.use_energy(2.0):
				player.start_activity("Harvesting", 1.0, _finish_harvest.bind(t))
		"shear":
			if t.is_woolly() and Game.use_energy(5.0):
				player.start_activity("Shearing", 2.5, _finish_shear.bind(t))
		"pet":
			player.start_activity("Petting", 1.2, _finish_pet.bind(t))


## Reading (data/books.json, scripts/book_panel.gd). `spot` is a reading seat or shelf in a shop
## (Interiors.ReadSpot) or one of her own chairs or bookshelves; id "read_book" sits her down with
## the book she last had open, "read_pick" opens the shelf to choose one (then _on_book_picked).
func begin_read(spot, id: String) -> void:
	if id == "read_pick":
		books_ui.open("", true)
	elif spot is Furniture:
		_sit_and_read(_seat_point(spot), spot.rotation.y, "")
	else:
		_sit_and_read(spot.seat_point(), spot.seat_yaw(), "", spot)


func _sit_and_read(seat: Vector3, yaw: float, book_id: String, spot = null) -> void:
	_take_read_spot(spot)
	player.start_activity("Reading", 100000.0, Callable(), seat, yaw)
	_reading = true
	ReadingPose.attach(player) # the open book in both hands (reading_pose.gd)
	books_ui.open(book_id)


## She took a book off the shelf: she carries it to the nearest free reading seat and sits down with
## it, or reads it standing if there's no seat near.
func _on_book_picked(id: String) -> void:
	books_ui.visible = false
	var seat = reading_seat_near(player.position)
	if seat == null:
		_reading = true
		books_ui.open(id)
		return
	var at: Vector3 = _stand_point(seat)
	var sit: Callable
	if seat is Furniture:
		sit = _sit_and_read.bind(_seat_point(seat), seat.rotation.y, id)
	else:
		_take_read_spot(seat) # hers while she walks over with the book
		sit = _sit_and_read.bind(seat.seat_point(), seat.seat_yaw(), id, seat)
	player.walk(_find_path(player.position, at), sit)


## The nearest reading seat to p (within 12 m): in the shop she's in, its ReadSpots; elsewhere her own
## armchairs, rocking chairs and sofas. null if none.
func reading_seat_near(p: Vector3):
	var best = null
	var bd := 12.0
	var shop := Interiors.inside_of(p)
	var seats: Array = []
	if shop != "":
		var up := Interiors.upstairs(p) # a seat on the floor she's on: upstairs in the café, or down
		seats = Interiors.read_spots(shop).filter(func(r): return r.kind == "seat" and not r.taken() and r.upstairs == up)
	else:
		seats = furniture.filter(func(f): return is_instance_valid(f) and f.item_id in ["armchair", "rocking_chair", "sofa"])
	for st in seats:
		var d: float = (st as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = st
	return best


## The café seat she's in (or on her way to), or null as she gets up.
func _take_read_spot(spot) -> void:
	if _read_spot != null and is_instance_valid(_read_spot) and _read_spot.occupant == player:
		_read_spot.occupant = null
	_read_spot = spot if spot != null and not (spot is Furniture) else null
	if _read_spot != null:
		_read_spot.occupant = player


## She puts the book down: she gets up, a little happier for every page she read (more for an ending).
func _on_book_closed() -> void:
	if not _reading:
		return
	_reading = false
	_take_read_spot(null)
	ReadingPose.detach(player)
	player.cancel_activity()
	var pages := books_ui.pages_read
	var joy := minf(12.0, 2.0 + pages * 0.6)
	var line := "A good read. (+%d happiness)" % roundi(joy)
	if not books_ui.finished.is_empty():
		joy += 6.0
		line = "You finished %s. (+%d happiness)" % [books_ui.book(str(books_ui.finished[0])).get("title", "the book"), roundi(joy)]
	Game.add_need("happiness", joy)
	Game.energy = minf(100.0, Game.energy + minf(10.0, pages * 0.5))
	hud.show_toast(line)


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
	var fibre := _knit_fibre
	_knit_fibre = ""
	if fibre != "" and not (Game.has_item("wool", 2) and Game.has_item(fibre)):
		fibre = ""
	var paid := false
	# better needles set the least any sweater can be (empire.gd); a wild fibre lifts it to its own floor
	rarity = maxi(rarity if rarity > 0 else Game.knit_quality(), empire.needle_floor())
	if fibre != "":
		paid = Game.take_item("wool", 2) and Game.take_item(fibre)
		rarity = maxi(rarity, wildlife.knit_floor(fibre))
	else:
		paid = Game.take_item("wool", 3)
	if paid:
		var worn0 := Game.worn_quality
		var q := Game.knit_sweater(rarity)
		if fibre != "": # what it was knitted with: the online store's orders ask for a fibre
			Game.sweater_fibres[Game.sweater_fibres.size() - 1] = fibre
		Game.add_need("happiness", 14.0)
		if fibre != "" and empire.knitted(fibre, q): # the one a local asked for: put by for them
			var who = _villager(str(empire.request().get("who", "")))
			hud.show_toast("A %s %s sweater, just as %s asked. Take it to them for %dc." % [KnitGame.rarity_name(q), wildlife.item_name(fibre).to_lower(), who.title if who else "they", empire.payout()])
		elif q > worn0:
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
	_story_event_soon("planted") # Act 1: her first turnips


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


## The mailbox's shipping rows (it took over from the shipping bin, Alex 2026-11-15): what she can
## send off for the plain price, paid at once. scripts/mail.gd adds them to the mailbox's menu.
func ship_rows() -> Array:
	var sw := Game.count("sweater")
	# only sweaters (Alex, 2026-11-15: sweaters are the economy): crops are to eat, wool and wild fibre to knit
	return [_act("ship_sweater", "Ship sweaters (%d, %dc)" % [sw, Game.sweater_worth(Game.SELL_PRICES["sweater"])], sw > 0)]


func _ship(kind: String) -> void:
	var earned := 0
	if kind == "ship_sweater": # sweaters sell by rarity, at the plain price: less than in person
		earned = Game.sweater_worth(int(Game.SELL_PRICES["sweater"]))
		Game.take_item("sweater", Game.count("sweater"))
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
	if forage:
		forage.apply() # what she cut a while ago grows back
	if wildlife:
		wildlife.restock() # another animal turns up where one was caught, once its time is up
	if wolves:
		_morning_note += wolves.morning_note(_day) # a night she slept through, and any animal the wolves took
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
	if builder != null and builder.tool != "":
		builder.set_tool("")
	if m != Mode.LIVE:
		player.cancel_activity()
		hud.show_toast("Build mode: pick something from the catalog, or Walls to build onto your house.")


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
	if builder.tool != "":
		builder.set_tool("") # a piece from the catalogue puts the wall tool down
	if ghost:
		_cancel_ghost()
	if not Catalog.affordable(id, Game.coins, Game.count("wood")):
		var w := Catalog.wood_cost(id)
		hud.show_toast("Not enough coins for that yet." if w <= 0 else "Not enough coins or wood for that yet (%s)." % Catalog.price_text(id))
		return
	ghost = Furniture.new()
	furniture_root.add_child(ghost)
	ghost.setup(id, ghost_rot)
	ghost.set_ghost(true)
	ghost_from = null
	ghost_marker.visible = true
	hud.set_holding(true, 0)
	ghost.set_color(str(_last_color.get(id, "")))
	hud.set_colors(ghost.colors(), ghost.color, recolor_price())
	_update_ghost(_last_mouse)


## Pays for a new piece: a wooden one from her wood when she has enough (felled or bought from
## Steve), otherwise in coins. False if she can do neither.
func _pay_for(id: String) -> bool:
	if Catalog.given(id) > 0: # a job's drop: hers already
		var g: Dictionary = (Game.flag("given", {}) as Dictionary).duplicate()
		g[id] = int(g[id]) - 1
		if int(g[id]) <= 0:
			g.erase(id)
		Game.set_flag("given", g)
		hud.show_toast("Placed the %s you were given." % str(Catalog.ITEMS[id]["name"]).to_lower())
		return true
	var w := Catalog.wood_cost(id)
	if w > 0 and Game.count("wood") >= w and Game.take_item("wood", w):
		hud.show_toast("Built it from %d wood." % w)
		return true
	return Game.spend(int(Catalog.ITEMS[id]["price"]))


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
	var in_cottage := cottage_owned() and cottage_interior().encloses(r)
	var inside := interior_rect().encloses(r) or in_cottage or builder.encloses(r) # a room she built is indoors too
	var in_yard := cottage_owned() and Town.COTTAGE_LOT.encloses(r) and not cottage_house_rect().grow(0.25).intersects(r)
	var outside := (LOT.encloses(r) and not house_rect().grow(0.25).intersects(r) and not builder.blocks(r.grow(0.25))) or in_yard
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
		if bought and not _pay_for(id):
			return
		if bought and ghost.color != "" and not Game.spend(recolor_price()): # a new piece pays for its colour as it goes down
			ghost.set_color("")
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
		hud.set_colors(t.colors(), t.color, recolor_price())
		_update_ghost(mpos)


var _last_color := {} # item id -> the colour she last chose for one, for the next she places


func recolor_price() -> int:
	return int(HouseBuilder.econ().get("recolor", 15))


## A colour for the piece in her hands (furniture.json "palettes"). A piece she already owns pays
## for it now; a new one pays when it's put down. Its own colour back is free.
func recolor_held(cid: String) -> void:
	if ghost == null or cid == ghost.color:
		hud.set_colors(ghost.colors() if ghost != null else [], ghost.color if ghost != null else "", recolor_price())
		return
	if ghost_from != null and cid != "" and not Game.spend(recolor_price()):
		hud.set_colors(ghost.colors(), ghost.color, recolor_price())
		return
	ghost.set_color(cid)
	_last_color[ghost.item_id] = ghost.color
	hud.set_colors(ghost.colors(), ghost.color, recolor_price())
	if ghost_from != null and cid != "":
		hud.show_toast("Recoloured the %s (%dc)." % [ghost.display_name().to_lower(), recolor_price()])


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
	if f.color != "":
		e["c"] = f.color # a colour she bought for it
	return e


## Pieces taken out of the game that a saved layout or an old save may still list: the flower pot
## by the porch went with the shipping bin when the mailbox took over (Alex, 2026-11-15).
const RETIRED := [["flower_pot", Vector2(9.0, 5.0)]]


func _spawn_entry(e: Dictionary) -> void:
	if not Catalog.ITEMS.has(str(e.get("id", ""))):
		return
	for r in RETIRED:
		if str(e["id"]) == r[0] and Vector2(float(e["x"]), float(e["z"])).distance_to(r[1]) < 0.05:
			return
	var f := _spawn_furniture(str(e["id"]), Vector3(float(e["x"]), 0, float(e["z"])), int(e.get("rot", 0)))
	if e.has("yaw"):
		f.rotation.y = deg_to_rad(float(e["yaw"]))
	if e.has("s"):
		f.scale = Vector3.ONE * float(e["s"])
	if e.has("c"):
		f.set_color(str(e["c"]))


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
		["sell", after_act1 and Game.count("sweater") > 0, "Sell sweaters to Rosa at the Maple Grove market (her price changes daily), ship them from the mailbox, or give one as a gift."],
		["night", after_act1 and Game.hour >= 21.0, "It's getting late. Click the bed to sleep: crops grow, prices change, and the game saves."],
		["rowan", after_act1 and Game.hearts("rowan") >= 1, "Rowan has more to say than he lets on. Talk to him once a day and a little more comes out."],
		["build", mode == Mode.BUILD, "Pick a piece from the catalog and click to place it. R rotates, right-click cancels. Click a placed piece to move, recolour or sell it. Walls builds onto your house."],
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


# --- control hints and the glow on people with something to say -----------------------------------

## Short control hints for a new player, once Wren has left her free in Maple Grove (Alex,
## 2026-11-14: the opening teaches by doing, with glowing things and a few words, not a lecture).
## One at a time, bottom left: a keycap or two and a few words. Each shows once per save (flag
## hint_<id>), and is marked done without showing as soon as she does it by herself.
var hints_enabled := true
var _hint_t := 1.5
var _hint_up := 0.0 # how long the hint on show has been up
var _hint_last := Vector3.INF
var _hint_walked := 0.0
var _hint_cam := -1.0
const HINT_SECS := 9.0
const HINT_GAP := 9.0


## [id, ready, done, keys, words]: in order; the first ready one not yet done shows next.
func _hints() -> Array:
	var met: bool = Game.flags.keys().any(func(k): return str(k).begins_with("met_") and str(k) != "met_rowan")
	return [
		["walk", true, _hint_walked > 8.0, ["Click"], "Walk there. Hold the button down to keep going"],
		["talk", _new_talker_near(9.0), met, ["Click"], "A gold star marks someone with something to say. Click them"],
		["camera", true, _hint_cam >= 0.0 and absf(cam_dist - _hint_cam) > 2.0, [_key("turn_left"), _key("turn_right")], "Turn the camera. The mouse wheel zooms"],
		["run", _hint_walked > 20.0, player.running and not player.path.is_empty(), [_key("run")], "Hold to hurry"],
		["fps", true, fps.active, [_key("first_person")], "See the world through her eyes"],
		["dog", dog != null and dog.visible, dog != null and dog.controlled, [_key("dog")], "Play as the dog"],
		["photo", true, cinema.active, [_key("cinematic")], "A free camera, for photos"],
		["map", true, false, [], "Click the map, top right, to walk anywhere"],
		["bag", Game.flag("act1_note") == true, hud.bag_panel.visible, [_key("bag")], "Look in your bag"],
	]


func _key(action: String) -> String:
	return Keys.key_name(Keys.bound(action))


func _update_hints(delta: float) -> void:
	var on: bool = hints_enabled and Game.flag("act1_toured") == true
	# what she does by herself counts, whether or not the hint has shown yet
	if on and _hint_last != Vector3.INF and not story.is_playing():
		_hint_walked += minf(player.position.distance_to(_hint_last), 1.0)
	_hint_last = player.position
	if _hint_cam < 0.0 and on and not story.is_playing() and cam_follow:
		_hint_cam = cam_dist
	var list := _hints() if on else []
	for h in list:
		if h[2] and not Game.flag("hint_" + str(h[0])):
			Game.set_flag("hint_" + str(h[0]))
	if hud.hint_id != "":
		_hint_up += delta
		var now: Array = list.filter(func(h): return h[0] == hud.hint_id)
		var busy := story.is_playing() or title_on or sleeping or knit.active
		if busy or _hint_up > HINT_SECS or (not now.is_empty() and now[0][2]):
			hud.hide_hint()
			_hint_t = HINT_GAP
		return
	_hint_t -= delta
	if not on or _hint_t > 0.0 or title_on or story.is_playing() or sleeping or knit.active or mode != Mode.LIVE \
			or fps.active or cinema.active:
		return
	_hint_t = 0.5
	for h in list:
		if h[1] and not h[2] and not Game.flag("hint_" + str(h[0])):
			Game.set_flag("hint_" + str(h[0]))
			hud.show_hint(str(h[0]), h[3], str(h[4]))
			_hint_up = 0.0
			return


## A gold star over anyone with a story scene waiting when she talks to them (a first hello, a
## topic, a gift of seeds), so the town shows you who to visit without a word of text.
var _new_talk_t := 0.0
var _glow_tex: Texture2D


func _update_new_talk(delta: float) -> void:
	_new_talk_t -= delta
	var t := Time.get_ticks_msec() * 0.001
	var check := _new_talk_t <= 0.0
	if check:
		_new_talk_t = 0.5
	for v in villagers:
		var g := v.get_node_or_null("NewTalk") as Sprite3D
		if check:
			var want: bool = v.visible and not story.is_playing() and not title_on and (Story.find_trigger("talk", v.vid) != "" or empire.wants(v.vid))
			if want and g == null:
				g = _new_talk_glow(v)
			if g:
				g.visible = want
		if g and g.visible:
			var k := 0.5 + 0.5 * sin(t * 3.0 + v.position.x)
			g.modulate.a = 0.88 + 0.12 * k
			g.scale = Vector3.ONE * (0.92 + 0.14 * k)
			# just over their head, and up clear of the name tag (one line: "Farmer Lars") while that shows
			var clear: float = 0.38 * v.tag.modulate.a if v.tag and v.tag.visible else 0.0
			g.position.y = float(g.get_meta("y")) + clear + 0.06 * sin(t * 2.0)


func _new_talk_glow(v) -> Sprite3D:
	if _glow_tex == null:
		_glow_tex = ImageTexture.create_from_image(star_image())
	var g := Sprite3D.new()
	g.name = "NewTalk"
	g.texture = _glow_tex
	g.pixel_size = 0.5 / STAR_PX # half a metre across with its halo; the star itself about 36 cm
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false
	g.no_depth_test = true
	g.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	g.transparent = true
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y: float = (v.tag.position.y if v.tag else 2.0) + 0.15
	g.set_meta("y", y)
	g.position.y = y
	v.add_child(g)
	return g


const STAR_PX := 96


## The marker's picture, drawn once: a gold five-pointed star with rounded points, lighter at the
## top, a darker gold rim, a small shine, and a soft warm halo that is clear by the picture's edge.
static func star_image() -> Image:
	var n := float(STAR_PX)
	var mid := Vector2(n, n) * 0.5 + Vector2(0.0, 0.02 * n)
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(mid + Vector2(cos(a), sin(a)) * n * (0.32 if i % 2 == 0 else 0.15))
	var round_px := 0.04 * n # the points and the notches between them are rounded by this much
	var rim_px := 0.028 * n
	var top := mid.y - 0.36 * n
	var shine := mid + Vector2(-0.07, -0.1) * n
	var img := Image.create(STAR_PX, STAR_PX, true, Image.FORMAT_RGBA8)
	for y in STAR_PX:
		for x in STAR_PX:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := 1e9
			for i in 10:
				d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % 10])))
			if Geometry2D.is_point_in_polygon(p, pts):
				d = -d
			d -= round_px # under 0: inside the star
			var body := clampf(0.5 - d, 0.0, 1.0)
			var col := Color(1.0, 0.9, 0.42).lerp(Color(0.97, 0.64, 0.1), clampf((p.y - top) / (0.7 * n), 0.0, 1.0))
			col = col.lerp(Color(1.0, 0.98, 0.86), 0.75 * exp(-p.distance_squared_to(shine) / (0.006 * n * n)))
			col = col.lerp(Color(0.72, 0.42, 0.04), clampf(1.0 + (d + 0.5) / rim_px, 0.0, 1.0))
			var halo := 0.55 * exp(-maxf(d, 0.0) / (0.07 * n)) * clampf((0.5 * n - p.distance_to(Vector2(n, n) * 0.5)) / (0.14 * n), 0.0, 1.0)
			var a_out := body + halo * (1.0 - body)
			if a_out > 0.001:
				col = (col * body + Color(1.0, 0.84, 0.4) * halo * (1.0 - body)) / a_out
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a_out))
	img.generate_mipmaps()
	return img


## The nearest villager with something new to say within `r` metres of her, or null.
func _new_talker_near(r: float) -> bool:
	for v in villagers:
		var g := v.get_node_or_null("NewTalk") as Sprite3D
		if g and g.visible and v.position.distance_to(player.position) < r:
			return true
	return false


# --- title screen and display ----------------------------------------------------------------------

var title_on := false
var _title_clock := true
var _title_keep := {} # the save's hour and weather, while the title shows its own golden hour
const TITLE_HOUR := 17.4 # the title is always a clear late afternoon: low warm sun, long shadows


func show_title(has_save: bool) -> void:
	title_on = true
	_title_clock = Game.time_running
	Game.time_running = false
	_title_keep = {"hour": Game.hour, "weather": Game.flag("weather", "clear")}
	Game.hour = TITLE_HOUR
	Game.set_flag("weather", "clear")
	rain = 0.0
	cam_follow = false
	cam_glide = {"pos": Vector3(10.0, 0.0, 0.0), "dist": 21.0}
	cam_yaw_goal = deg_to_rad(20.0)
	hud.show_title(has_save)


func _leave_title() -> void:
	title_on = false
	if not _title_keep.is_empty():
		Game.hour = float(_title_keep["hour"])
		Game.set_flag("weather", _title_keep["weather"])
		_title_keep = {}
	cam_glide = {}
	cam_follow = true
	cam_yaw_goal = deg_to_rad(45.0)
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
## The walk-in shops she isn't in whose doors are shut (for the graphics checks).
func _shut_shops() -> Array:
	var out := []
	for sh in Interiors.shops.values():
		if is_instance_valid(sh.node) and sh.node.visible and not sh.inside and sh.open <= 0.0 and not sh.all_lights.is_empty():
			out.append(sh)
	return out


## A shut shop's state: its lights on or off, and its furnishings casting their own shadows or none.
func _shop_state(sh: Interiors.Shop, lights_on: bool, casting: bool) -> bool:
	for l in sh.all_lights:
		if is_instance_valid(l) and (l as Light3D).visible != lights_on:
			return false
	for e in sh.casters:
		if not is_instance_valid(e[0]):
			continue
		var want: int = e[1] if casting else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if (e[0] as GeometryInstance3D).cast_shadow != want:
			return false
	return true


func _graphics_checks() -> void:
	var blades_ultra: int = grass.drawn_blades()
	var scale_ultra := get_viewport().scaling_3d_scale
	var had_cfg := FileAccess.file_exists(SETTINGS_PATH)
	var lamps: Array = find_children("*", "OmniLight3D", true, false)
	var shut := _shut_shops()
	_cycle_graphics() # High
	await _wait(0.3)
	_check("High graphics: Ultra's look (light bounce in 3 cascades, reflections, haze, the sun's shadow in 4 splits) for less: %d lamp shadows at most, grass to %d m, 3D at %d%% (Ultra %d%%), and %d shut shops keep their lights with their furnishings casting nothing under the roof" % [LAMP_SHADOWS[GFX_HIGH], int(GRASS_RANGE[GFX_HIGH]), roundi(get_viewport().scaling_3d_scale * 100), roundi(scale_ultra * 100), shut.size()],
		gfx == GFX_HIGH and env.sdfgi_enabled and env.sdfgi_cascades == 3 and env.ssao_enabled and env.ssil_enabled and env.ssr_enabled
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		and light_budget.casting(get_tree()) <= LAMP_SHADOWS[GFX_HIGH] and get_viewport().scaling_3d_scale <= scale_ultra
		and not shut.is_empty() and shut.all(func(sh) -> bool: return _shop_state(sh, true, false))
		and hud.graphics_btn.text == "Graphics: High")
	_cycle_graphics() # Medium
	await _wait(0.3)
	_check("Medium graphics: the sun's shadow in 2 splits, %d lamp shadow at most (fading by %d m), and %d shops she isn't in with their door shut have their lights off and their furnishings casting nothing" % [LAMP_SHADOWS[1], int(LAMP_SHADOW_FADE[1]), shut.size()],
		gfx == 1 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and not env.sdfgi_enabled
		and light_budget.casting(get_tree()) <= LAMP_SHADOWS[1]
		and shut.all(func(sh) -> bool: return _shop_state(sh, false, false)))
	_cycle_graphics() # Low
	await _wait(0.3)
	_check("Low graphics: no light bounce, reflections, haze or lamp shadows; %d of %d grass blades; 3D at %d%% (Ultra %d%%)" % [grass.drawn_blades(), blades_ultra, roundi(get_viewport().scaling_3d_scale * 100), roundi(scale_ultra * 100)],
		gfx == 0 and not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled
		and lamps.all(func(l): return not is_instance_valid(l) or not l.shadow_enabled) and grass.drawn_blades() < blades_ultra * 0.5
		and get_viewport().scaling_3d_scale <= scale_ultra and hud.graphics_btn.text == "Graphics: Low")
	_cycle_graphics() # Ultra
	await _wait(0.3)
	var flush := coplanar_faces()
	for f in flush:
		print("      flush: ", f)
	_check("no two surfaces sit flush in the same plane (they'd flicker in stripes): %d" % flush.size(), flush.is_empty())
	var casting: int = light_budget.casting(get_tree())
	_check("back on Ultra: every effect and all the grass return, %d of the nearest lit lamps cast shadows (at most %d, never a candle); settings file untouched" % [casting, LAMP_SHADOWS[GFX_ULTRA]],
		gfx == GFX_ULTRA and env.ssao_enabled and env.ssil_enabled and env.ssr_enabled and casting <= LAMP_SHADOWS[GFX_ULTRA]
		and lamps.all(func(l): return not is_instance_valid(l) or not l.has_meta("no_shadow") or not l.shadow_enabled)
		and grass.drawn_blades() == blades_ultra and FileAccess.file_exists(SETTINGS_PATH) == had_cfg
		and hud.graphics_btn.text == "Graphics: Ultra")
	_check("Ultra as High was: the sun's shadow in 4 splits, and every shop's lights on and furnishings casting their shadows again",
		sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and not Interiors.no_casters and not Interiors.lights_off
		and env.sdfgi_cascades == 4
		and shut.all(func(sh) -> bool: return _shop_state(sh, true, true)))


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


## Act 1 from a fresh story: the rain bus, Wren's tour of the town, Gran's basket, knitting and the
## first memory thread, Rowan at the broken fence, market day in Maplewood, and the porch at
## night. The heroine walks between the triggers for real.
func _act1_checks() -> void:
	Game.flags = {}
	Game.hour = 9.0
	Game.energy = 100.0
	Game.fullness = 100.0
	for d in _villager_defs():
		set_home(str(d["id"]))
	mode = Mode.LIVE
	story.shown.clear()
	story.auto = true
	story.auto_line = 0.3
	story.auto_choices = [0, 1, 1, 0, 0] # the phone, Rosa at the market, Rowan by the pond (twice), the porch
	homestead.start_story() # Act 1's farm: no pen, no sheep, no money
	hints_enabled = true
	_hint_t = 1.5
	_hint_walked = 0.0
	hud.hide_hint()
	Game.wear("")
	await _wait(0.2)
	_check("she arrives in her thin city coat, not a sweater (coat %s, worn '%s')" % [Sweaters.coat_on(player.body), Sweaters.worn(player.body)],
		Sweaters.coat_on(player.body) and Sweaters.worn(player.body) == "")
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
	var sign_spot: Dictionary = _spot_at({"building": "welcome_sign", "pos": [-1.4, 3.6]})
	var at_sign: bool = not sign_spot.is_empty() and Vector2(player.position.x - sign_spot["pos"].x, player.position.z - sign_spot["pos"].z).length() < 1.0
	_check("the sign beat finds the sign where the world editor put it, and she stands at it (%s)" % at_sign, at_sign)
	_check("her selection ring is hidden while a scene plays (%s)" % player._ring.visible, not player._ring.visible)
	_check("the faded HUD doesn't catch the mouse in a scene: no minimap tooltip over a cutscene",
		hud.minimap == null or hud.minimap.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED)
	await _act1_shot("Giorgio the baker", "21_act1_town_giorgio.png")
	var tune_on: bool = audio.tune_name == "arrival"
	await _act1_shot("Barbara the postwoman", "21_act1_town_barbara.png")
	await _act1_shot("going to like it here", "21_act1_like_it_here.png")
	await _act1_shot("Good, you're here", "22_act1_wren.png")
	var wren_v = _villager("wren")
	var dog_gap: float = dog.position.distance_to(wren_v.global_position) if dog != null and wren_v != null else -1.0
	_check("in Wren's scene the dog makes way for her: he waits on Nora's other side (%.1f m from Wren)" % dog_gap, dog_gap > Dog.ROOM + 0.2)
	await _act1_shot("The Yarn Barn. Rosa", "22_act1_overview_shop.png")
	await _act1_shot("Heart Bakery. Giorgio", "22_act1_overview_bakery.png")
	await _act1_shot("Builder's Delight. Steve", "22_act1_overview_homegoods.png")
	await _act1_shot("Willow Homes. That's Gary", "22_act1_overview_office.png")
	await _act1_shot("Sabrina's Cappuccino Cafe", "22_act1_overview_cafe.png")
	await _act1_shot("Front door sticks", "23_act1_wren_leaves.png")
	await _act1_until_done(120.0)
	_check("the clock stands still during a scene (%.2f → %.2f)" % [hour0, hour_end[0]], absf(hour_end[0] - hour0) < 0.001 and Game.time_running)
	var free_at_sign: bool = not sign_spot.is_empty() and Vector2(player.position.x - sign_spot["pos"].x, player.position.z - sign_spot["pos"].z).length() < 4.0
	_check("the arrival: the rain stops at the sign to the arrival music (%s), Wren points out the town and leaves her free by the sign (%s) with one goal ('%s')" % [str(tune_on), free_at_sign, hud.goal_label.text],
		tune_on and Game.flag("act1_toured") == true and str(Game.flag("weather")) == "clear" and free_at_sign
		and hud.goal_panel.visible and goal_marker.visible and hud.goal_label.text.begins_with("Go to Gran"))
	_check("the goal has a column of light you can see from the sign", (goal_marker.get_node("Beam") as Node3D).visible)
	var keepers_back := 0
	var keepers := ["giorgio", "steve", "rosa", "gary", "sabrina"]
	for vid in keepers:
		if _villager(vid).position.distance_to(_villager_post(vid)) < 1.5:
			keepers_back += 1
	_check("the shopkeepers are at work (%d of %d)" % [keepers_back, keepers.size()], keepers_back == keepers.size())
	await _wait(2.4)
	var glowing := []
	for vid in keepers:
		var g := _villager(vid).get_node_or_null("NewTalk") as Node3D
		if g != null and g.visible:
			glowing.append(vid)
	_check("the shopkeepers she hasn't met glow, waiting to say hello (%s)" % str(glowing), glowing.size() == keepers.size())
	_check("a hint shows how to walk, a keycap and a few words (%s: '%s')" % [hud.hint_id, hud.hint_text()], hud.hint_id == "walk" and hud.hint_text() != "")
	await _shot("23_act1_free.png")
	# she says hello to Rosa on her own
	var hello_v := _villager("rosa")
	var t0 := Time.get_ticks_msec()
	_do_action(hello_v, "talk")
	var t := 0.0
	while story.playing != "meet_rosa" and t < 40.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("talking to Rosa the first time plays her hello (%s)" % story.playing, story.playing == "meet_rosa")
	await _act1_shot("worst payer", "23_act1_meet_rosa.png")
	await _act1_until_done(30.0)
	await _wait(0.7)
	var rg = hello_v.get_node_or_null("NewTalk")
	_check("after hello Rosa stops glowing, and walking there ticked off the walk hint (glow %s, hint_walk %s)" % [rg != null and rg.visible, Game.flag("hint_walk")],
		Game.flag("met_rosa") == true and (rg == null or not rg.visible) and Game.flag("hint_walk") == true)
	await _wait(0.8)
	t0 = Time.get_ticks_msec()
	player.walk(_find_path(player.position, Vector3(5.6, 0, 3.0)))
	t = 0.0
	while story.playing != "act1_note" and t < 90.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("stepping inside starts Gran's note (%s)" % story.playing, story.playing == "act1_note")
	await _act1_shot("For my Nora", "24_act1_note.png")
	await _act1_until_done(60.0)
	_check("Gran's note: kept in her bag, no coins but her needles and 3 wool, rent to the tin, a goal to knit (coins %d, wool %d, note %s, rent due day %s, '%s')" % [Game.coins, Game.count("wool"), str(Game.has_item("gran_note")), str(Game.flag("rent_due")), hud.goal_label.text],
		Game.coins == 0 and Game.count("wool") == 3 and Game.has_item("gran_note") and Game.flag("rent_on") == true and int(Game.flag("rent_due", 0)) == Game.day + 7
		and hud.goal_label.text.begins_with("Knit your first") and homestead.note_prop == null and homestead.seed_tin == null)
	var tin_acts: Array = _actions_for(homestead.tin)
	_check("Gran's tin: nothing owed yet, and the note to read again (%s)" % str(tin_acts.map(func(x): return x["label"])),
		tin_acts.size() == 2 and not tin_acts[0]["enabled"] and tin_acts[1]["id"] == "read_note")
	homestead.ui.show_note(homestead.NOTE_TEXT)
	await _wait(0.4)
	await _shot("24_act1_note_paper.png")
	_check("the note opens on paper", homestead.ui.is_open())
	homestead.ui.close_all()
	var rosa := _villager("rosa")
	var steve := _villager("steve")
	var wool_price := _yarn_price(Game.WOOL_PACK_PRICE)
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	t0 = Time.get_ticks_msec()
	_do_action(chair, "knit")
	t = 0.0
	while story.playing != "act1_knit" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("finishing her first sweater starts the memory (%s)" % story.playing, story.playing == "act1_knit")
	_check("her first sweater goes on over the city coat (wearing '%s', coat %s)" % [Sweaters.worn(player.body), Sweaters.coat_on(player.body)],
		Sweaters.worn(player.body) != "" and not Sweaters.coat_on(player.body))
	await _act1_shot("Babe.", "27_act1_memory.png")
	_check("the first knit opens memory thread #1 in the faded memory look", hud.memory_on())
	_check("no toast talks over the memory (%s)" % hud.toast_panel.visible, not hud.toast_panel.visible or hud.toast_panel.modulate.a < 0.05)
	await _act1_shot("How much is it?", "27_act1_wren.png")
	await _act1_until_done(40.0)
	await _wait(0.5)
	_check("the memory is in her journal; then Wren knocks, wants the sweater, and the price panel opens in its guided form (journal %s, panel %s, guided '%s', goal '%s')" % [Game.journal().size() == journal0 + 1, sale.visible, sale.guided, hud.goal_label.text],
		Game.journal().size() == journal0 + 1 and Game.journal()[-1]["kind"] == "memory" and homestead.strays.is_empty()
		and sale.visible and sale.guided == "wren" and hud.goal_label.text.begins_with("Name your price"))
	# the first sale: Wren says her range; inside it she's all but sure to buy; above it she offers her top
	var rar0 := int(Game.sweaters[sale.choice]) if sale.choice >= 0 else 0
	var wr: Vector2i = sale.guided_range(rar0)
	var said_range: bool = sale._said.text.contains("%dc to %dc" % [wr.x, wr.y])
	sale.set_price(wr.x)
	var c_low: float = sale.chance("wren", rar0, wr.x)
	sale.set_price(wr.y + 30)
	var c_dear: float = sale.chance("wren", rar0, wr.y + 30)
	await _wait(0.3)
	await _shot("27_act1_wren_sale.png")
	var dear_said: String = sale.offer()
	_check("Wren names her range out loud (%s: %dc to %dc), the meter is all but sure inside it (%.0f%%) and falls above it (%.0f%%); too dear, she offers her top (%s, %dc)" % [said_range, wr.x, wr.y, c_low * 100.0, c_dear * 100.0, dear_said, sale.counter],
		said_range and c_low > 0.95 and c_dear < 0.5 and dear_said == "counter" and sale.counter == wr.y and sale.visible)
	var first_price: int = wr.x + int((wr.y - wr.x) / 10) * 5
	sale.set_price(first_price)
	var sold_said: String = sale.offer()
	t = 0.0
	while story.playing != "act1_sold" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	_check("a price inside her range sells it (%s for %dc, coins %d) and Wren's scene carries on (%s)" % [sold_said, first_price, Game.coins, story.playing],
		sold_said == "sold" and Game.coins == first_price and story.playing == "act1_sold" and not sale.visible)
	await _act1_until_done(40.0)
	_check("Wren sends her for seed and yarn ('%s'), and the villagers' free seeds wait for the end of Act 1 (%s)" % [hud.goal_label.text, Story.find_trigger("talk", "barbara")],
		Game.flag("act1_sold") == true and hud.goal_label.text.begins_with("Buy turnip seeds") and Story.find_trigger("talk", "barbara") != "seeds_barbara")
	# seed from Steve
	var coins_s := Game.coins
	t0 = Time.get_ticks_msec()
	_do_action(steve, "buy_seeds_turnip")
	t = 0.0
	while story.playing != "act1_seeds" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	await _act1_until_done(30.0)
	hud.hide_dialogue()
	var seed_pack: Array = _store().get("seeds", {}).get("turnip", [5, 25])
	_check("she buys turnip seed from Steve with Wren's coins (coins %d→%d, seeds %d) and goes to plant it ('%s')" % [coins_s, Game.coins, Game.count("turnip_seeds"), hud.goal_label.text],
		Game.coins == coins_s - int(seed_pack[1]) and Game.count("turnip_seeds") == int(seed_pack[0]) and hud.goal_label.text.begins_with("Plant"))
	# her first turnips, in one of Gran's beds
	var bed0 = null
	for p in plots:
		if p.crop == "":
			bed0 = p
			break
	t0 = Time.get_ticks_msec()
	_do_action(bed0, "plant_turnip")
	t = 0.0
	while story.playing != "act1_planted" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	await _act1_until_done(30.0)
	_check("planting the turnips (%s) sends her to Rosa for more yarn ('%s')" % [bed0.crop if bed0 else "no bed", hud.goal_label.text],
		bed0 != null and bed0.crop == "turnip" and hud.goal_label.text.begins_with("Buy more yarn"))
	# more yarn from Rosa at the Yarn Barn
	var coins_y := Game.coins
	t0 = Time.get_ticks_msec()
	_do_action(rosa, "buy_wool")
	t = 0.0
	while story.playing != "act1_yarn" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("buying yarn from Rosa starts the next beat (%s after %.1fs)" % [story.playing, t], story.playing == "act1_yarn")
	await _act1_until_done(30.0)
	Game.hour = 9.0 # the test walks fast, but not that fast: keep the act on one day, as a player would sleep between
	_check("she has the yarn (coins %d→%d, wool %d) and a goal to knit again ('%s')" % [coins_y, Game.coins, Game.count("wool"), hud.goal_label.text],
		Game.coins == coins_y - wool_price and Game.count("wool") >= 3 and hud.goal_label.text.begins_with("Knit another"))
	t0 = Time.get_ticks_msec()
	_do_action(chair, "knit")
	t = 0.0
	while story.playing != "act1_knit2" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	await _act1_until_done(30.0)
	_check("the second sweater sends her to Rosa's stall (%s, sweaters %d, '%s')" % [Game.flag("act1_knit2"), Game.count("sweater"), hud.goal_label.text],
		Game.flag("act1_knit2") == true and Game.count("sweater") >= 1 and hud.goal_label.text.contains("market"))
	# market day: walk into Maple Grove to Rosa's stall
	var coins0 := Game.coins
	var sweaters0 := Game.count("sweater")
	var wool1 := Game.count("wool")
	var rosa0 := Game.stat("rosa", "trust")
	t0 = Time.get_ticks_msec()
	story.pause_on = "Hold ON" # armed before she gets there: the scene's first line comes quickly
	player.walk(_find_path(player.position, Vector3(48.5, 0, -5.6)))
	t = 0.0
	while story.playing != "act1_market" and t < 45.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("walking to Rosa's stall starts market day (%s after %.1fs)" % [story.playing, t], story.playing == "act1_market")
	await _act1_shot("Hold ON", "28_act1_market_rosa.png")
	await _act1_shot("standing ovation", "29_act1_market_steve.png")
	await _act1_until_done(60.0)
	_check("Rosa bought the second sweater (coins %d→%d, sweaters %d→%d) and gave wool on credit (wool %d→%d, trust %d→%d), and the strays are bleating out by the pond (%d, '%s')" % [coins0, Game.coins, sweaters0, Game.count("sweater"), wool1, Game.count("wool"), rosa0, Game.stat("rosa", "trust"), homestead.strays.size(), hud.goal_label.text],
		Game.coins == coins0 + 60 and Game.count("sweater") == sweaters0 - 1 and Game.count("wool") == wool1 + 5 and Game.flag("rosa_credit") == true
		and Game.stat("rosa", "trust") == rosa0 + 2 and Game.flag("act1_market") == true and homestead.strays.size() == 2 and hud.goal_label.text.begins_with("Find"))
	_check("the dog is with her from the start (for now), but the strays don't shy from him before there's a pen (here %s, herding %s)" % [dog != null and dog.visible, homestead.herders.has(dog)],
		dog != null and dog.visible and not homestead.herders.has(dog))
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
	_check("the strays: met Rowan, opened up (trust %d→%d), off to Steve for wood ('%s')" % [trust0, Game.stat("rowan", "trust"), hud.goal_label.text],
		Game.flag("met_rowan") == true and Game.flag("nora_opened") == true and Game.stat("rowan", "trust") == trust0 + 3 and hud.goal_label.text.begins_with("Get wood"))
	# wood from Steve at Builder's Delight
	var acts: Array = _villager_actions(steve).map(func(x): return x["id"])
	_check("Steve sells wood (%s)" % str(acts), "buy_wood" in acts)
	var coins1 := Game.coins
	t0 = Time.get_ticks_msec()
	_do_action(steve, "buy_wood")
	t = 0.0
	while story.playing != "act1_wood" and t < 60.0:
		await _wait(0.1)
		t += 0.1
	walk_secs += (Time.get_ticks_msec() - t0) / 1000.0
	_check("buying wood starts the pen beat (%s)" % story.playing, story.playing == "act1_wood")
	await _act1_until_done(30.0)
	_villager_action(steve, "buy_wood")
	_villager_action(steve, "buy_wood")
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
	var toast_r: Rect2 = hud.toast_panel.get_global_rect()
	_check("a long toast wraps and stays clear of the minimap (%s)" % toast_r, hud.minimap == null or not toast_r.intersects(hud.minimap.get_global_rect()))
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
	# a stray may have wandered through the open gate by itself while the scene played: count those as well
	_check("with the pen built the dog can herd, but only while she plays him: following her he leaves the strays be (can %s, herding now %s, strays %d, %d already in)" % [dog_herds(), homestead.herders.has(dog), homestead.strays.size(), sheep_list.size()],
		dog_herds() and not homestead.herders.has(dog) and homestead.strays.size() >= 1 and homestead.strays.size() + sheep_list.size() == 2)
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
	_check("their own wool now, and home by dusk ('%s', %.1fh)" % [hud.goal_label.text, Game.hour], Game.flag("act1_fence_done") == true and hud.goal_label.text.begins_with("Head home") and Game.hour > 18.0)
	var buy_ok: bool = _villager_actions(rosa).filter(func(x): return x["id"] == "buy_sheep").size() == 1
	_check("Rosa sells sheep now there's a pen", buy_ok)
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
	await _act1_shot("Nora. It's me.", "30_act1_voicemail.png")
	_check("it's night on the porch and Max's voicemail is on her phone (%.1fh, '%s')" % [Game.hour, hud.phone_label.text],
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
	# rent (data/economy.json "story" rent) every seven days, into Gran's tin
	var due := int(Game.flag("rent_due", 0))
	homestead._on_day(due)
	var owed := homestead.rent_owed()
	Game.coins = maxi(Game.coins, owed) # this quick run of the week didn't stop to earn it
	var coins2 := Game.coins
	var paid := homestead.pay_rent()
	_check("rent comes due a week in (%dc owed on day %d) and goes in Gran's tin (coins %d→%d, next due day %d)" % [owed, due, coins2, Game.coins, int(Game.flag("rent_due", 0))],
		owed == homestead.econ("rent", 20) and owed > 0 and paid and Game.coins == coins2 - owed and homestead.rent_owed() == 0 and int(Game.flag("rent_due", 0)) == due + 7)
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
	hints_enabled = false
	hud.hide_hint()
	for vid in ["rosa", "giorgio", "gary", "steve", "sabrina"]: # the rest of the autotest has met them all
		Game.set_flag("seen_meet_" + vid)
		Game.set_flag("met_" + vid)
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


## The town's cast (Alex's, 2026-11-12, and Lars next door, 2026-11-13) and their routines: the nine
## villagers and nobody else, the nine new faces in their own models with real eyes (Rosa's and Lars's since 2026-11-13, Rebecca's since 2026-11-15),
## Sabrina starting cool by the Coffee Shop, Rosa's mornings at the market stall and afternoons in the
## Yarn Barn, Barbara's nine o'clock post round (every door in town and Nora's porch), Gary's land and
## his visit on her second day, and Lars by his barn, renting her its stalls by the month.
func _cast_checks() -> void:
	hud.hide_dialogue()
	hud.tip_panel.visible = false
	mode = Mode.LIVE
	var hour0 := Game.hour
	var day0 := Game.day
	var auto0: bool = story.auto
	var ids: Array = villagers.map(func(v): return str(v.vid))
	ids.sort()
	_check("the cast is Barbara, Gary, Giorgio, Lars, Rebecca, Rosa, Rowan, Sabrina, Steve and Wren (%s)" % ", ".join(ids),
		ids == ["barbara", "gary", "giorgio", "lars", "rebecca", "rosa", "rowan", "sabrina", "steve", "wren"])
	var officer := _villager("rebecca") # the police officer (Alex, 2026-11-15), on her beat in the square
	var beat := _villager_post("rebecca")
	_check("Rebecca the police officer is on her beat in the square, on open ground (%.1f m from her post, walkable %s), with nothing to report (%s)" % [officer.position.distance_to(beat) if officer != null else -1.0, str(_walkable(_cell(beat))), str(officer != null and not _villager_actions(officer).any(func(a): return str(a.get("id", "")) == "report_max"))],
		officer != null and officer.position.distance_to(beat) < 2.5 and _walkable(_cell(beat)) and not _villager_actions(officer).any(func(a): return str(a.get("id", "")) == "report_max"))
	var bodies: Array = []
	for id in ["barbara", "gary", "giorgio", "lars", "rebecca", "rosa", "sabrina", "steve", "wren"]:
		var v := _villager(id)
		if v != null and v.body != null and v.body.face != null:
			bodies.append(id)
	_check("the nine new faces wear their own models, with real eyes (%s)" % ", ".join(bodies), bodies.size() == 9)
	var tags := {} # what they do, then their name (Alex, 2026-11-15: "Farmer Lars", not "Lars, Farmer")
	for v in villagers:
		tags[str(v.vid)] = str(v.tag.text) if v.tag != null else ""
	_check("every name tag reads what they do, then their name, on one line (%s)" % ", ".join(tags.values()),
		str(tags.get("lars", "")) == "Farmer Lars" and str(tags.get("rebecca", "")) == "Officer Bekka" and str(tags.get("wren", "")) == "Mayor Wren"
		and villagers.all(func(v): return v.job != "" and v.tag != null and v.tag.text == v.display_name() and not v.tag.text.contains("\n") and v.tag.text.begins_with(v.job + " ")))
	var no_portrait: Array = [] # tools/render_portraits.py makes them; a story line shows them beside the text
	for c in Data.load_json("characters").get("characters", []):
		for mood in ["neutral", "happy", "warm", "sad", "wry", "surprised", "worried", "angry"]:
			if not ResourceLoader.exists("res://assets/portraits/%s_%s.png" % [str(c.get("id", "")), mood]):
				no_portrait.append("%s_%s" % [str(c.get("id", "")), mood])
	_check("every character has a portrait for each story mood (missing: %s)" % str(no_portrait), no_portrait.is_empty())
	var missing: Array = ids.filter(func(id): return not (Dialogue.INTRO.has(id) and Dialogue.LINES.has(id)))
	_check("every villager has an intro and lines (missing: %s)" % str(missing), missing.is_empty())
	var old_f = Game.friends.get("sabrina")
	Game.friends.erase("sabrina")
	_check("Sabrina starts cool (trust %d)" % Game.stat("sabrina", "trust"), Game.stat("sabrina", "trust") == -20)
	if old_f != null:
		Game.friends["sabrina"] = old_f
	for d in _villager_defs():
		set_home(str(d["id"]))
	# Sabrina, on the Coffee Shop's terrace wherever the layout puts it
	var sab := _villager("sabrina")
	var cafe := _spot_at(_villager_def("sabrina")["at"])
	_check("Sabrina works on the Coffee Shop's terrace (%.1f m from her spot)" % (sab.position.distance_to(cafe["pos"]) if not cafe.is_empty() else -1.0),
		not cafe.is_empty() and sab.position.distance_to(cafe["pos"]) < 1.5)
	var sab_acts: Array = _villager_actions(sab).map(func(a): return a["id"])
	Game.coins = maxi(Game.coins, 100)
	var warm0 := Game.warmth
	Game.warmth = minf(Game.warmth, 60.0)
	warm0 = Game.warmth
	_villager_action(sab, "buy_coffee")
	_check("she sells coffee, and it warms Nora up (%.0f -> %.0f)" % [warm0, Game.warmth], "buy_coffee" in sab_acts and Game.warmth > warm0)
	hud.hide_dialogue()
	if not cafe.is_empty():
		player.position = cafe["talk"]
		player.face_point(sab.position)
		await _cast_frame(cafe["pos"], float(cafe["yaw"]), 9.0)
		await _shot("51_cast_sabrina.png")
	# Gary's listings
	var land: Array = _villager_actions(_villager("gary")).filter(func(a): return str(a.get("group", "")) == "Land for sale")
	_check("Gary lists three plots of land, all out of reach (%s)" % ", ".join(land.map(func(a): return a["label"])),
		land.size() == 3 and land.all(func(a): return not a["enabled"]))
	# Lars, by his barn next door, and the barn's rent
	var lars := _villager("lars")
	var by_barn := _spot_at(_villager_def("lars")["at"])
	_check("Lars stands by the barn doors next door (%.1f m from his spot)" % (lars.position.distance_to(by_barn["pos"]) if lars != null and not by_barn.is_empty() else -1.0),
		lars != null and not by_barn.is_empty() and lars.position.distance_to(by_barn["pos"]) < 1.5)
	if not by_barn.is_empty():
		player.position = by_barn["talk"]
		player.face_point(lars.position)
		await _cast_frame(by_barn["pos"], float(by_barn["yaw"]), 8.0)
		await _shot("51_cast_lars.png")
	if officer != null:
		player.position = officer.position + Vector3(0.6, 0, 1.7)
		player.face_point(officer.position)
		await _cast_frame(officer.position, 0.0, 8.0)
		await _shot("51_cast_rebecca.png")
		var visit0 = Game.flags.get("max_visit_done") # as if Max had come and gone: she has something to say
		Game.set_flag("max_visit_done", true)
		await _wait(1.2)
		var star := officer.get_node_or_null("NewTalk") as Sprite3D
		var over: float = star.position.y - officer.tag.position.y if star != null and officer.tag != null else -1.0
		await _shot("51_cast_rebecca_star.png")
		_check("with something to say she wears the gold star, just above her name tag (star %s, tag shown %.1f, %.2f m over it)" % [str(star != null and star.visible), officer.tag.modulate.a if officer.tag != null else 0.0, over],
			star != null and star.visible and officer.tag != null and officer.tag.modulate.a > 0.9 and over > 0.4 and over < 0.7)
		if visit0 == null:
			Game.flags.erase("max_visit_done")
		else:
			Game.flags["max_visit_done"] = visit0
		await _wait(0.6)
	var rent0 := {}
	for k in ["barn_rent_due", "barn_rent_owed"]:
		rent0[k] = Game.flags.get(k)
		Game.flags.erase(k)
	var pay_row := func() -> bool: return _villager_actions(lars).any(func(a): return str(a["id"]) == "pay_barn_rent" and a["enabled"])
	var before: bool = pay_row.call()
	homestead.start_barn_rent()
	var month := homestead.econ("barn_rent_days", 28)
	homestead._barn_rent_day(Game.day + month)
	var owed := homestead.barn_rent_owed()
	Game.coins = maxi(Game.coins, owed + 10)
	var row: bool = pay_row.call()
	var coins0 := Game.coins
	_villager_action(lars, "pay_barn_rent")
	_check("he rents her the barn's stalls: %dc due after %d days, paid to him (row before: %s, then: %s; coins %d -> %d, owed now %d)" % [owed, month, str(before), str(row), coins0, Game.coins, homestead.barn_rent_owed()],
		not before and owed == homestead.econ("barn_rent", 60) and row and Game.coins == coins0 - owed and homestead.barn_rent_owed() == 0)
	hud.hide_dialogue()
	for k in rent0:
		if rent0[k] == null:
			Game.flags.erase(k)
		else:
			Game.flags[k] = rent0[k]
	# the town's routines
	town_rounds = true
	story.auto = true
	story.auto_line = 0.2
	var rosa := _villager("rosa")
	var stall := _spot_at(_villager_def("rosa")["stall"])
	var barbara := _villager("barbara")
	post_day = 0
	_post_stops.clear()
	player.position = Vector3(44.0, 0, 1.0) # in town, away from the farm (Gary calls at the farm)
	Game.hour = 9.0
	var t := 0.0
	while post_day != Game.day and t < 5.0: # Barbara sets out on the hour: count her stops before Rosa's walk
		await _wait(0.1)
		t += 0.1
	var stops := _post_stops.size()
	t = 0.0
	while not stall.is_empty() and rosa.position.distance_to(stall["pos"]) > 0.4 and t < 40.0:
		await _wait(0.25)
		t += 0.25
	_check("Rosa keeps the market stall in the morning (%.1fs to walk over, at the stall: %s)" % [t, str(rosa_at_stall)],
		not stall.is_empty() and rosa.position.distance_to(stall["pos"]) <= 0.4 and rosa_at_stall)
	var kinds: Array = Town.built.filter(func(e): return str(e[1]).begins_with("building_")).map(func(e): return str(e[1]).substr(9))
	_check("Barbara set out with the post at nine (%d stops for %s, Nora's porch among them: %s)" % [stops, ", ".join(kinds), str(post_farm_stop() in _post_stops)],
		post_day == Game.day and stops >= 7 and post_farm_stop() in _post_stops)
	if not stall.is_empty():
		await _cast_frame(stall["pos"], float(stall["yaw"]), 7.0, CAM_PITCH_LOW) # low, to see her under the awning
		await _shot("51_cast_rosa_stall.png")
	t = 0.0
	while _post_stops.size() >= stops and t < 40.0:
		await _wait(0.25)
		t += 0.25
	_check("she calls at the first door and moves on (%.1fs)" % t, _post_stops.size() < stops and not _post_stops.is_empty())
	await _cast_frame(barbara.position, cam_yaw, 8.0)
	await _shot("51_cast_barbara.png")
	var to_farm := _find_path(Vector3(50.5, 0, 1.6), post_farm_stop())
	_check("the post can walk from the plaza to Nora's mailbox (%d steps)" % to_farm.size(),
		not to_farm.is_empty() and (to_farm[-1] as Vector3).distance_to(post_farm_stop()) < 0.8)
	Game.hour = 13.0
	t = 0.0
	while Interiors.inside_of(rosa.position) != "shop" and t < 40.0:
		await _wait(0.25)
		t += 0.25
	_check("and she's back behind the Yarn Barn's counter after noon (%.1fs)" % t, Interiors.inside_of(rosa.position) == "shop" and not rosa_at_stall)
	# Gary calls at the farm on her second day, then every two weeks
	Game.day = maxi(Game.day, 2)
	Game.flags.erase("gary_visit_day")
	Game.flags.erase("gary_met")
	Game.flags.erase("seen_gary_intro")
	_post_stops.clear()
	set_home("barbara")
	player.position = Vector3(12.0, 0, 4.5)
	cam_glide = {}
	_set_cam_lock(true)
	cam_pitch = CAM_PITCH
	Game.hour = 11.0
	t = 0.0
	while story.playing != "gary_intro" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	_check("Gary calls at the farm on her second day (%s after %.1fs)" % [story.playing, t], story.playing == "gary_intro")
	await _act1_shot("Three listings", "51_cast_gary_visit.png")
	await _act1_until_done(40.0)
	var gary := _villager("gary")
	_check("he pitches three plots and goes back to Willow Homes (met %s, %.1f m from his desk)" % [str(Game.flag("gary_met")), gary.position.distance_to(_villager_post("gary"))],
		Game.flag("gary_met") == true and int(Game.flag("gary_visit_day", 0)) == Game.day and gary.position.distance_to(_villager_post("gary")) < 1.5
		and story.shown.any(func(l): return str(l).contains("Saltmeadow Point")))
	var due_now := gary_visit_due()
	Game.day += GARY_EVERY
	var due_later := gary_visit_due()
	_check("and comes back every two weeks (due tomorrow: %s, in %d days: %s, then the pitch: %s)" % [str(due_now), GARY_EVERY, str(due_later), Story.find_trigger("event", "gary_visit")],
		not due_now and due_later and Story.find_trigger("event", "gary_visit") == "gary_pitch")
	town_rounds = false
	Game.day = day0
	Game.hour = hour0
	story.auto = auto0
	hud.hide_dialogue()
	for d in _villager_defs():
		set_home(str(d["id"]))
	cam_glide = {}
	_set_cam_lock(true)
	cam_yaw = deg_to_rad(45.0)
	cam_yaw_goal = cam_yaw
	cam_target = player.position


## The cast check's pictures: the camera off Nora, looking at `at` from the side `yaw` faces
## (a three-quarter view of a front), `dist` away.
## Jobs beside knitting (scripts/jobs.gd, data/economy.json "jobs", data/scenes/jobs.scene): no
## offers during Act 1; Giorgio's bakery job after it, and a shift there (the oven, the flour, the
## shelves, the floor: the clock moves on, she tires, she's paid, and a click away doesn't lose the
## shift); Sabrina's Coffee Shop once she trusts Nora, which leaves the bakery; Barbara's post round,
## turned down and then taken from her menu, door to door; one shift a day; stopping early pays part.
## Saves 52_job_bakery.png, 52_job_cafe.png and 52_job_post.png.
func _job_checks() -> void:
	var auto0: bool = story.auto
	var jog0 := autotest_jog
	var day0 := Game.day
	var hour0 := Game.hour
	var flags0: Dictionary = Game.flags.duplicate(true)
	var sab_trust0 := Game.stat("sabrina", "trust")
	story.auto = true
	story.auto_choices = []
	autotest_jog = true
	hud.hide_dialogue()
	hud.tip_panel.visible = false
	# jobs are off in the autotest (Jobs.on, on in the game): nobody offers one and no menu has Work
	# rows, so talking to a boss elsewhere starts no offer. The rest of this check turns them on
	Game.set_flag("job", "bakery")
	var parked_rows: Array = _villager_actions(_villager("giorgio")).filter(func(a): return str(a.get("group", "")) == "Work")
	_check("jobs are off in the autotest: no job, no offer and no Work rows (on %s, job '%s', offer '%s', rows %d)" % [Jobs.on, Jobs.current(), Jobs.offer_scene("giorgio"), parked_rows.size()],
		not Jobs.on and Jobs.current() == "" and Jobs.offer_scene("giorgio") == "" and parked_rows.is_empty())
	Jobs.on = true
	var defs := Jobs.defs()
	var bad: Array = []
	for id in defs:
		var d: Dictionary = defs[id]
		if _villager(str(d["boss"])) == null:
			bad.append("%s: no boss %s" % [id, d["boss"]])
		if not Story.has_scene("job_" + id):
			bad.append("%s: no scene job_%s" % [id, id])
		if jobs.stops(id).is_empty():
			bad.append("%s: no stops" % id)
	var ids: Array = defs.keys()
	ids.sort()
	_check("three jobs (%s), each with its boss, its offer scene and a shift's stops %s" % [", ".join(ids), str(bad)], ids == ["bakery", "cafe", "post"] and bad.is_empty())
	for id in defs:
		Game.flags.erase("job_offer_" + id)
		Game.flags.erase("seen_job_" + id)
	Game.flags.erase("job")
	Game.flags.erase("job_shift_day")
	Game.set_flag("story_farm")
	Game.flags.erase("act1_done")
	var during := Jobs.offer_scene("giorgio")
	Game.set_flag("act1_done")
	var after := Jobs.offer_scene("giorgio")
	Game.flags.erase("story_farm")
	_check("Giorgio offers no job during Act 1 ('%s') and the bakery job after it ('%s')" % [during, after], during == "" and after == "job_bakery")

	# Giorgio's offer, and a morning at Heart Bakery
	var talk_to := func(v) -> String:
		_do_action(v, "talk")
		var t := 0.0
		while not story.is_playing() and t < 40.0:
			await _wait(0.2)
			t += 0.2
		var id := story.playing
		await _act1_until_done(40.0)
		hud.hide_dialogue()
		return id
	var gio := _villager("giorgio")
	var offer: String = await talk_to.call(gio)
	var acts: Array = _villager_actions(gio)
	var row := func(list: Array, id: String) -> Dictionary:
		for a in list:
			if str(a["id"]) == id:
				return a
		return {}
	_check("talking to him plays his offer and she takes it (%s, job '%s', rows %s)" % [offer, Jobs.current(), str(acts.filter(func(a): return str(a.get("group", "")) == "Work").map(func(a): return a["label"]))],
		offer == "job_bakery" and Jobs.current() == "bakery" and Game.flag("job_offer_bakery") == true and not row.call(acts, "job_shift").is_empty() and not row.call(acts, "job_quit").is_empty())
	Game.hour = 15.0
	var late: Dictionary = row.call(_villager_actions(gio), "job_shift")
	_check("no bakery shift in the afternoon (%s)" % str(late.get("label", "")), not late.is_empty() and not bool(late.get("enabled", true)))
	Game.hour = 6.4
	Game.energy = 100.0
	Game.fullness = 50.0
	var c0 := Game.coins
	var h0 := Game.hour
	_do_action(gio, "job_shift")
	var tw := 0.0
	while not jobs.working() and tw < 20.0:
		await _wait(0.2)
		tw += 0.2
	var n_bake: int = jobs.shift["stops"].size() if jobs.working() else 0
	var goal_text := str(Game.flag("goal", ""))
	var interrupted := false
	var inside := ""
	var tasks_seen := {}
	tw = 0.0
	while jobs.working() and tw < 150.0:
		if player.busy:
			tasks_seen[player.activity_text()] = true
		if not interrupted and int(jobs.shift["i"]) == 1 and player.busy:
			interrupted = true # a click away mid-task: she should pick the shift up again
			player.walk(_find_path(player.position, player.position + Vector3(1.2, 0, 1.2)))
		if inside == "" and int(jobs.shift["i"]) == 2 and player.busy:
			inside = Interiors.inside_of(player.position)
			cam_target = player.position + Vector3(0, 1.0, 0)
			cam_dist = 11.0
			await _wait(0.8)
			await _shot("52_job_bakery.png")
		await _wait(0.2)
		tw += 0.2
	_check("a bakery shift: %d tasks inside Heart Bakery (%s, in '%s'), the goal shows the next ('%s'), picked up again after a click away" % [n_bake, ", ".join(tasks_seen.keys()), inside, goal_text],
		n_bake == 8 and inside == "bakery" and tasks_seen.has("Feeding the oven") and tasks_seen.has("Sweeping up") and goal_text.contains("Heart Bakery") and interrupted and not jobs.working())
	_check("the shift pays and takes its hours and her energy (+%dc, %.1fh -> %.1fh, energy %.0f, food %.0f after a warm loaf)" % [Game.coins - c0, h0, Game.hour, Game.energy, Game.fullness],
		Game.coins == c0 + int(defs["bakery"]["pay"]) and Game.hour >= h0 + float(defs["bakery"]["hours"]) - 0.01 and Game.energy < 90.0 and str(Game.flag("goal", "")) in ["", "false"])
	Game.hour = 6.5
	_check("one shift a day ('%s')" % jobs.shift_problem("bakery"), jobs.shift_problem("bakery") == "already worked today")

	# Sabrina's Coffee Shop, once she trusts Nora
	Game.flags.erase("job_shift_day")
	Game.hour = 12.1
	var sab := _villager("sabrina")
	Game.friend("sabrina")["trust"] = 0
	var cool := Jobs.offer_scene("sabrina")
	Game.friend("sabrina")["trust"] = 12
	var cafe_offer: String = await talk_to.call(sab)
	_check("Sabrina has no work for her while she's cool on Nora ('%s'), then offers the Coffee Shop at trust 12 (%s); taking it leaves the bakery (job '%s', bakery row %s)" % [cool, cafe_offer, Jobs.current(), str(row.call(_villager_actions(gio), "job_take").get("label", ""))],
		cool == "" and cafe_offer == "job_cafe" and Jobs.current() == "cafe" and not row.call(_villager_actions(gio), "job_take").is_empty())
	Game.hour = 12.1
	Game.warmth = 40.0
	c0 = Game.coins
	_do_action(sab, "job_shift")
	tw = 0.0
	var cafe_shot := false
	var cafe_n := 0
	while (not jobs.working() or not cafe_shot) and tw < 30.0:
		if jobs.working() and int(jobs.shift["i"]) == 1 and player.busy:
			cafe_n = jobs.shift["stops"].size()
			cafe_shot = true
			await _cast_frame(player.position, cam_yaw, 10.0)
			await _shot("52_job_cafe.png")
		await _wait(0.2)
		tw += 0.2
	tw = 0.0
	while jobs.working() and tw < 120.0:
		await _wait(0.2)
		tw += 0.2
	var to_sab := player.position.distance_to(sab.position)
	_check("a Coffee Shop shift on the terrace: %d tasks, +%dc, a coffee after (warmth 40 -> %.0f, %.1f m from Sabrina at the end)" % [cafe_n, Game.coins - c0, Game.warmth, to_sab],
		cafe_n == 6 and Game.coins == c0 + int(defs["cafe"]["pay"]) and Game.warmth > 50.0 and to_sab < 8.0 and not jobs.working())

	# Barbara's post round: she thinks about it, then takes it from Barbara's menu
	Game.flags.erase("job_shift_day")
	var bar := _villager("barbara")
	story.auto_choices = [1]
	var post_offer: String = await talk_to.call(bar)
	var still := Jobs.current()
	var take: Dictionary = row.call(_villager_actions(bar), "job_take")
	_check("Barbara offers the post round and Nora says she'll think (%s, job still '%s', menu '%s')" % [post_offer, still, str(take.get("label", ""))],
		post_offer == "job_post" and still == "cafe" and not take.is_empty())
	_do_action(bar, "job_take")
	await _walk_wait(30.0)
	hud.hide_dialogue()
	Game.hour = 8.3
	c0 = Game.coins
	_do_action(bar, "job_shift")
	tw = 0.0
	while not jobs.working() and tw < 20.0:
		await _wait(0.2)
		tw += 0.2
	var doors: int = jobs.shift["stops"].size() if jobs.working() else 0
	var delivered := 0
	var post_shot := false
	tw = 0.0
	while jobs.working() and tw < 240.0:
		delivered = maxi(delivered, int(jobs.shift["i"]))
		if not post_shot and int(jobs.shift["i"]) == 2 and player.busy:
			post_shot = true
			await _cast_frame(player.position, cam_yaw, 14.0)
			await _shot("52_job_post.png")
		await _wait(0.2)
		tw += 0.2
	_check("the post round: she takes the job from Barbara's menu (job '%s') and delivers to every door in town (%d doors, +%dc)" % [Jobs.current(), doors, Game.coins - c0],
		Jobs.current() == "post" and doors >= 5 and Game.coins == c0 + int(defs["post"]["pay"]) and not jobs.working())

	# stopping early pays for what she did
	Game.flags.erase("job_shift_day")
	_do_action(gio, "job_take")
	await _walk_wait(30.0)
	hud.hide_dialogue()
	Game.hour = 6.3
	Game.energy = 100.0
	c0 = Game.coins
	_do_action(gio, "job_shift")
	tw = 0.0
	while (not jobs.working() or int(jobs.shift["i"]) < 2) and tw < 60.0:
		await _wait(0.2)
		tw += 0.2
	var stop_row: Dictionary = row.call(_villager_actions(gio), "job_end")
	jobs.action(gio, "job_end")
	var part := int(round(float(defs["bakery"]["pay"]) * 2.0 / 8.0))
	_check("back at the bakery, she stops after two tasks and is paid for them (row '%s', +%dc of %d)" % [str(stop_row.get("label", "")), Game.coins - c0, part],
		Jobs.current() == "bakery" and not stop_row.is_empty() and Game.coins == c0 + part and not jobs.working())

	player.walk([])
	player.cancel_activity()
	hud.hide_dialogue()
	Game.flags = flags0
	Game.friend("sabrina")["trust"] = sab_trust0
	Game.day = day0
	Game.hour = hour0
	_show_goal()
	await _wait(0.3) # jobs.update sees the job go back to how it was
	Jobs.on = false
	story.auto = auto0
	story.auto_choices = []
	autotest_jog = jog0
	cam_glide = {}
	_set_cam_lock(true)
	cam_target = player.position


## The post (scripts/mail.gd, data/mail.json): the mailbox by the porch, letters coming on
## Barbara's round, reading them (coins and wool enclosed), and a sweater order: she posts a
## sweater, Barbara takes it, and the next morning's post pays for it. Pictures: 53_mail_barbara.png,
## 53_mail_letter.png, 53_mail_order.png and 53_mailbox_flag.png.
func _mail_checks() -> void:
	hud.hide_dialogue()
	hud.tip_panel.visible = false
	mode = Mode.LIVE
	var hour0 := Game.hour
	var day0 := Game.day
	var coins0 := Game.coins
	var sweaters0: Array = Game.sweaters.duplicate()
	var wool0 := Game.count("wool")
	var mail0: Variant = Game.flags.get("mail", null)
	Game.flags.erase("mail")
	var story0 := {}
	for f in ["act1_note", "act1_done"]: # the letters wait for Act 1; the check doesn't depend on what ran before
		story0[f] = Game.flags.get(f, null)
		Game.set_flag(f)
	var defs := Data.load_json("mail")
	var custom: Array = defs.get("orders", {}).get("customers", [])
	var ids: Array = defs.get("letters", []).map(func(d): return str(d["id"]))
	_check("data/mail.json: Gran's letters from Florida, Max's and %d sweater customers (%s)" % [custom.size(), ", ".join(ids)],
		ids.has("gran_florida_1") and ids.has("gran_florida_2") and ids.has("max_1") and custom.size() >= 3
		and custom.all(func(c): return str(c.get("thanks", "")) != "" and int(c.get("pay", 0)) > 0))
	var box: Node3D = mail.box
	var in_editor: bool = god.els.any(func(e): return e.node == box and e.kind == "mailbox")
	_check("a mailbox stands by the porch, flag down, and the world editor can move it (%s, editor %s, %s)" % [str(box.global_position), str(in_editor), mail.actions()[0]["label"]],
		box.visible and box.global_position.distance_to(POST_FARM_DOOR) < 4.0 and in_editor and not mail.flag_up() and not mail.actions()[0]["enabled"])
	# the blue post box model (art/world_assets/mailbox) by the porch, and three more in town
	var meshes := box.find_children("*", "MeshInstance3D", true, false).size()
	var town_boxes: Array = decor.filter(func(f): return is_instance_valid(f) and f.item_id == "mailbox")
	_check("the mailbox is the blue post box model, and %d more stand in town (%d meshes)" % [town_boxes.size(), meshes],
		box.get_child(0) is Node3D and str(box.get_child(0).scene_file_path).ends_with("mailbox.glb") and meshes >= 2 and town_boxes.size() == 3)
	for i in town_boxes.size():
		var tb: Furniture = town_boxes[i]
		await _cast_frame(tb.global_position, tb.rotation.y, 6.5)
		await _shot("53_town_mailbox_%d.png" % i)
	# Barbara brings the post on day 4: Gran's first letter, Max's, and the first order
	Game.day = 4
	Game.sweaters.clear()
	Game.inv["sweater"] = 0
	town_rounds = true
	set_home("barbara")
	player.walk([])
	player.position = Vector3(12.6, 0, 3.6)
	await _cast_frame(box.global_position, MAILBOX_YAW, 9.0)
	await _shot("53_mailbox.png")
	await _cast_frame(box.global_position, MAILBOX_YAW, 5.0, CAM_PITCH_LOW)
	var came := await _mail_round()
	var box_ids: Array = mail.letters_in_box().map(func(l): return str(l["id"]))
	_check("Barbara calls at the mailbox on her round and leaves three letters, flag up (%s; '%s')" % [", ".join(box_ids), hud.toast_label.text],
		came and box_ids == ["gran_florida_1", "max_1", "order_1"] and mail.flag_up() and hud.toast_label.text.contains("Barbara brings the post"))
	await _shot("53_mail_barbara.png")
	# the order wants a sweater she hasn't got yet
	var post_act: Array = mail.actions().filter(func(a): return str(a["id"]) == "post:order_1")
	_check("the mailbox offers to take the post, and the order waits for a sweater (%s)" % ", ".join(mail.actions().map(func(a): return a["label"])),
		mail.actions()[0]["id"] == "take" and post_act.size() == 1 and not post_act[0]["enabled"])
	# she takes the post out and the letters panel opens on Gran's letter, with its coins
	var coins1 := Game.coins
	_do_action(box, "take")
	var t := 0.0
	while not hud.letters.visible and t < 15.0:
		await _wait(0.1)
		t += 0.1
	var first: Dictionary = mail.letters()[hud.letters.current] if hud.letters.current >= 0 else {}
	_check("she walks to the box and takes the post: Gran's letter from Florida opens, 25c enclosed (%.1fs, '%s', coins %d→%d, %d unread)" % [t, first.get("from", ""), coins1, Game.coins, mail.unread()],
		hud.letters.visible and str(first.get("id", "")) == "gran_florida_1" and bool(first["read"]) and Game.coins == coins1 + 25
		and mail.letters_in_box().is_empty() and mail.letters().size() == 3 and mail.unread() == 2 and not mail.flag_up()
		and hud.letters._meta.text.contains("Florida") and hud.letters._list.get_child_count() == 3)
	await _shot("53_mail_letter.png")
	hud.letters.show_letter(1)
	_check("Max's letter asks her to come home", hud.letters._from.text == "From Max" and hud.letters._body.text.contains("Come home"))
	hud.letters.show_letter(2)
	var order_def: Dictionary = Data.load_json("mail").get("orders", {})
	var order_pay := int(order_def["customers"][0]["pay"])
	var order_tip := int(order_def.get("tip_per_star", 0))
	_check("the order letter says what it wants and pays ('%s')" % hud.letters._note.text,
		hud.letters._note.text.contains("Common or better") and hud.letters._body.text.contains("%d coins" % order_pay) and mail.unread() == 0)
	await _shot("53_mail_order.png")
	hud.letters.close()
	# she knits two sweaters; the order takes the plainest that will do
	Game.add_sweater(4)
	Game.add_sweater(2)
	_do_action(box, "post:order_1")
	t = 0.0
	while str(mail.orders()["order_1"]["state"]) != "posted" and t < 10.0:
		await _wait(0.1)
		t += 0.1
	_check("she posts a sweater for the order: the Uncommon one goes, the Epic stays, flag up (%s, carrying %s)" % [mail.orders()["order_1"]["state"], str(Game.sweaters)],
		str(mail.orders()["order_1"]["state"]) == "posted" and int(mail.orders()["order_1"]["rarity"]) == 2 and Game.sweaters == [4] and Game.count("sweater") == 1 and mail.flag_up())
	await _cast_frame(box.global_position, MAILBOX_YAW + 0.9, 2.6, CAM_PITCH_LOW)
	await _shot("53_mailbox_flag.png")
	# the next morning Barbara takes it; the morning after, the payment comes
	Game.day = 5
	came = await _mail_round()
	_check("next morning Barbara takes the sweater and has nothing for her (%s, box %d, flag up %s, '%s')" % [mail.orders()["order_1"]["state"], mail.letters_in_box().size(), str(mail.flag_up()), hud.toast_label.text],
		came and str(mail.orders()["order_1"]["state"]) == "sent" and mail.letters_in_box().is_empty() and not mail.flag_up() and hud.toast_label.text.contains("Nothing for you"))
	Game.day = 6
	came = await _mail_round()
	var coins2 := Game.coins
	mail.do_action("take")
	var paid: Dictionary = mail.letters()[hud.letters.current] if hud.letters.current >= 0 else {}
	_check("the day after, Marjorie's payment comes: %dc and a %dc tip for the extra star (coins %d→%d, '%s', order %s)" % [order_pay, order_tip, coins2, Game.coins, paid.get("from", ""), mail.orders()["order_1"]["state"]],
		came and str(paid.get("id", "")) == "paid_order_1" and Game.coins == coins2 + order_pay + order_tip and str(mail.orders()["order_1"]["state"]) == "paid")
	hud.letters.close()
	# a week after Gran's first letter, her second, with wool; and the next customer writes
	Game.day = 11
	came = await _mail_round()
	box_ids = mail.letters_in_box().map(func(l): return str(l["id"]))
	var wool1 := Game.count("wool")
	mail.do_action("take")
	_check("a week on, Gran writes again with 3 wool enclosed, and the next customer orders (%s; wool %d→%d)" % [", ".join(box_ids), wool1, Game.count("wool")],
		came and box_ids == ["gran_florida_2", "order_2"] and Game.count("wool") == wool1 + 3 and str(mail.orders()["order_2"]["from"]) == "Tom Beckett")
	hud.letters.close()
	# it all saves: the state goes through JSON like the save file (numbers come back as floats)
	var n_letters := mail.letters().size()
	Game.flags["mail"] = JSON.parse_string(JSON.stringify(Game.flags["mail"]))
	var reopen: Array = mail.open_orders()
	_check("the post saves with the game (%d letters, open orders %s)" % [mail.letters().size(), str(reopen.map(func(e): return e[0]))],
		mail.letters().size() == n_letters and reopen.size() == 1 and reopen[0][0] == "order_2" and mail.sweater_for(reopen[0][1]) == 0)
	var menu_btn: bool = hud.game_menu.find_children("*", "Button", true, false).any(func(b): return (b as Button).text == "Letters")
	_check("Letters is in the Esc menu", menu_btn)
	# put everything back
	town_rounds = false
	set_home("barbara")
	if mail0 == null:
		Game.flags.erase("mail")
	else:
		Game.flags["mail"] = mail0
	for f in story0:
		if story0[f] == null:
			Game.flags.erase(f)
		else:
			Game.flags[f] = story0[f]
	mail.update_flag()
	Game.coins = coins0
	Game.sweaters = sweaters0
	Game.inv["sweater"] = sweaters0.size()
	Game.inv["wool"] = wool0
	Game.day = day0
	Game.hour = hour0
	cam_glide = {}
	_set_cam_lock(true)
	cam_target = player.position


## One of Barbara's rounds, quickly: she sets out at nine, the test skips the doors in town and
## starts her a little way down the lane, and she walks to the mailbox. True once she has called.
func _mail_round() -> bool:
	var barbara := _villager("barbara")
	post_day = 0
	_post_stops.clear()
	_rounds_t = 0.0
	Game.hour = 9.0
	var t := 0.0
	while _post_stops.is_empty() and t < 5.0:
		await _wait(0.1)
		t += 0.1
	if _post_stops.is_empty():
		return false
	while _post_stops.size() > 2: # the mailbox, then her spot on the plaza
		_post_stops.pop_front()
	barbara.position = post_farm_stop() + Vector3(5.0, 0, 0)
	_post_next(barbara)
	t = 0.0
	while _post_stops.size() > 1 and t < 30.0:
		await _wait(0.1)
		t += 0.1
	return _post_stops.size() == 1


## Max's visit (data/scenes/max.scene): play time counts up, he isn't due before the hours are
## played or before Act 1, then he drives up to the farm in his own model (a visitor, not one
## of the town's cast). Say yes and he shows his true colours; say no and his temper comes out;
## either way she sends him away, and he's gone when the scene ends. Pictures:
## 54_max_arrives.png and 54_max_true_colours.png.
func _max_checks() -> void:
	hud.hide_dialogue()
	hud.tip_panel.visible = false
	mode = Mode.LIVE
	var hour0 := Game.hour
	var auto0: bool = story.auto
	var keys := ["play_secs", "act1_done", "seen_max_visit", "max_accepted", "max_refused", "max_visit_done", "journal", "gary_visit_day",
		"max_visit_day", "seen_max_return", "max_report_open", "max_reported", "seen_rebecca_max", "seen_max_arrest", "max_arrested"]
	var saved := {}
	for k in keys:
		saved[k] = Game.flags.get(k, null)
	var p0 := float(Game.flags.get("play_secs", 0.0))
	await _wait(0.5)
	var p1 := float(Game.flags.get("play_secs", 0.0))
	_check("play time counts up while she plays (%.2f → %.2f s)" % [p0, p1], p1 > p0 + 0.3)
	var hours: float = float(Data.economy().get("story", {}).get("max_visit_hours", 4.0))
	for k in ["act1_done", "seen_max_visit", "max_accepted", "max_refused", "max_visit_done",
			"max_visit_day", "seen_max_return", "max_report_open", "max_reported", "seen_rebecca_max", "seen_max_arrest", "max_arrested"]:
		Game.flags.erase(k)
	var officer := _villager("rebecca")
	var report_row := func() -> bool: return officer != null and _villager_actions(officer).any(func(a): return str(a.get("id", "")) == "report_max")
	var quiet: bool = Story.find_trigger("talk", "rebecca") == "" and not report_row.call() and not max_return_due()
	Game.flags["play_secs"] = hours * 3600.0 + 10.0
	var before_act1 := max_visit_due()
	Game.set_flag("act1_done")
	Game.flags["play_secs"] = hours * 3600.0 - 60.0
	var short := max_visit_due()
	Game.flags["play_secs"] = hours * 3600.0 + 1.0
	_check("Max is due after %.0f hours of play and Act 1 (before Act 1 %s, a minute short %s, after %s)" % [hours, str(before_act1), str(short), str(max_visit_due())],
		not before_act1 and not short and max_visit_due())
	# he comes: she's home on the farm in the late morning
	Game.flags["gary_visit_day"] = Game.day # Gary isn't calling today
	post_day = Game.day # nor is the post
	town_rounds = true
	story.auto = true
	story.auto_line = 0.2
	story.auto_choices = [0]
	player.walk([])
	player.position = Vector3(9.6, 0, 4.2)
	Game.hour = 11.0
	_rounds_t = 0.0
	var t := 0.0
	while story.playing != "max_visit" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	var ex := _villager("max")
	_check("he drives up to the farm (%s after %.1fs), a visitor in his own model, not one of the town's cast" % [story.playing, t],
		story.playing == "max_visit" and ex != null and ex.body != null and not villagers.has(ex) and ex.visible)
	await _act1_shot("Hey, Nor.", "54_max_arrives.png")
	await _act1_shot("tea cosy", "54_max_true_colours.png")
	await _act1_until_done(60.0)
	await _wait(0.3)
	var j: Array = Game.journal()
	_check("say yes and he shows his true colours; she sends him away and he's gone (accepted %s, done %s, journal '%s', still here %s)" % [str(Game.flag("max_accepted")), str(Game.flag("max_visit_done")), j[-1]["title"] if not j.is_empty() else "", str(_villager("max") != null)],
		Game.flag("max_accepted") == true and Game.flag("max_visit_done") == true and not j.is_empty() and str(j[-1]["title"]) == "Max came"
		and _villager("max") == null and visitors.is_empty() and story.shown.any(func(l): return str(l).contains("tea cosy")))
	_check("he comes only once", not max_visit_due())
	# the other choice
	for k in ["seen_max_visit", "max_accepted", "max_visit_done"]:
		Game.flags.erase(k)
	story.auto_choices = [1]
	story.shown.clear()
	player.position = Vector3(9.6, 0, 4.2)
	_rounds_t = 0.0
	t = 0.0
	while story.playing != "max_visit" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	await _act1_until_done(60.0)
	await _wait(0.3)
	_check("say no and his temper comes out; she sends him away (refused %s, accepted %s)" % [str(Game.flag("max_refused")), str(Game.flag("max_accepted"))],
		Game.flag("max_refused") == true and Game.flag("max_accepted") != true and Game.flag("max_visit_done") == true
		and story.shown.any(func(l): return str(l).contains("six hours for this")) and _villager("max") == null)
	# Rebecca (Alex, 2026-11-15): reporting him is Nora's to choose. Left alone, he comes back once
	var back_days: int = int(Data.economy().get("story", {}).get("max_return_days", 3))
	var offer: String = Story.find_trigger("talk", "rebecca")
	Game.flags["max_visit_day"] = Game.day - back_days + 1
	var early := max_return_due()
	Game.flags["max_visit_day"] = Game.day - back_days
	_check("before his visit Rebecca had nothing to raise (%s); after it she has (%s), with no report row yet (%s), and he is due back after %d days, not a day sooner (%s, then %s)" % [str(quiet), offer, str(report_row.call()), back_days, str(early), str(max_return_due())],
		quiet and offer == "rebecca_max" and not report_row.call() and not early and max_return_due())
	story.shown.clear()
	player.position = Vector3(9.6, 0, 4.2)
	Game.hour = 11.0
	_rounds_t = 0.0
	t = 0.0
	while story.playing != "max_return" and t < 5.0:
		await _wait(0.1)
		t += 0.1
	var came_back: bool = story.playing == "max_return" and _villager("max") != null
	await _act1_until_done(60.0)
	await _wait(0.3)
	_check("unreported, he comes back once (%s) and she sends him off again; the offer is open on Rebecca's menu (%s) and he isn't due a third time (%s)" % [str(came_back), str(report_row.call()), str(max_return_due())],
		came_back and Game.flag("max_report_open") == true and report_row.call() and not max_return_due() and _villager("max") == null)
	# she can still say not today: nothing is forced
	story.auto_choices = [1]
	story.shown.clear()
	player.walk([])
	player.position = officer.position + Vector3(0.3, 0, 1.5)
	_do_action(officer, "talk")
	t = 0.0
	while story.playing != "rebecca_max" and t < 8.0:
		await _wait(0.1)
		t += 0.1
	var raised: bool = story.playing == "rebecca_max"
	await _act1_until_done(40.0)
	await _wait(1.0)
	_check("talking to Rebecca, she raises it (%s); Nora says not today and nothing happens (reported %s, arrested %s, the row still there %s)" % [str(raised), str(Game.flag("max_reported")), str(Game.flag("max_arrested")), str(report_row.call())],
		raised and Game.flag("max_reported") != true and Game.flag("max_arrested") != true and not story.is_playing() and report_row.call())
	# then she reports him from Rebecca's menu: Rebecca is waiting when he turns up, and that is the last of him
	story.shown.clear()
	_villager_action(officer, "report_max")
	t = 0.0
	while story.playing != "max_arrest" and t < 20.0:
		await _wait(0.1)
		t += 0.1
	var waiting: bool = story.playing == "max_arrest" and _villager("max") != null
	await _act1_shot("Officer Rebecca, Maple Grove", "54_max_arrest.png")
	await _act1_until_done(60.0)
	await _wait(0.3)
	j = Game.journal()
	_check("reported from her menu (%s), Rebecca is waiting for him at the lane (%s): he is arrested and gone for good (arrested %s, still here %s, due again %s or %s, journal '%s', the row gone %s)" % [str(Game.flag("max_reported")), str(waiting), str(Game.flag("max_arrested")), str(_villager("max") != null), str(max_visit_due()), str(max_return_due()), j[-1]["title"] if not j.is_empty() else "", str(not report_row.call())],
		Game.flag("max_reported") == true and waiting and Game.flag("max_arrested") == true and _villager("max") == null and visitors.is_empty()
		and not max_visit_due() and not max_return_due() and not j.is_empty() and str(j[-1]["title"]) == "Max is gone" and not report_row.call()
		and Story.find_trigger("event", "max_arrest") == "" and Story.find_trigger("talk", "rebecca") != "rebecca_max")
	var kept: Dictionary = Game.migrate(JSON.parse_string(JSON.stringify({"version": Game.SAVE_VERSION, "flags": Game.flags})))["flags"]
	_check("a save keeps it: arrested %s, reported %s" % [str(kept.get("max_arrested")), str(kept.get("max_reported"))], kept.get("max_arrested") == true and kept.get("max_reported") == true)
	# a save from before he was renamed (he was Daniel) keeps its place in his story
	var old_save := {"version": 6, "flags": {"seen_daniel_visit": true, "daniel_refused": true, "declined_daniel": true,
		"mail": {"box": [], "got": [{"id": "daniel_1", "from": "Daniel", "body": "Call me.\n\nD.", "read": true}], "sent": {"daniel_1": 4}},
		"journal": [{"kind": "note", "title": "Daniel came", "text": "Daniel left a voicemail.", "day": 5}]}}
	var of: Dictionary = Game.migrate(old_save)["flags"]
	var old_letter: Dictionary = of["mail"]["got"][0]
	_check("a save from before the rename says Max: his flags, his letter (not posted again) and her journal (%s)" % ", ".join(of.keys().filter(func(k): return k != "mail" and k != "journal")),
		of.get("seen_max_visit") == true and of.get("max_refused") == true and of.get("declined_max") == true and not of.has("seen_daniel_visit")
		and (of["mail"]["sent"] as Dictionary).has("max_1") and str(old_letter["from"]) == "Max" and str(old_letter["body"]).ends_with("M.")
		and str(of["journal"][0]["title"]) == "Max came" and str(of["journal"][0]["text"]).begins_with("Max "))
	# put everything back
	town_rounds = false
	for k in saved:
		if saved[k] == null:
			Game.flags.erase(k)
		else:
			Game.flags[k] = saved[k]
	story.auto = auto0
	story.auto_choices = []
	Game.hour = hour0
	cam_glide = {}
	_set_cam_lock(true)
	cam_target = player.position


func _cast_frame(at: Vector3, yaw: float, dist: float, pitch := CAM_PITCH) -> void:
	_set_cam_lock(false)
	cam_target = at + Vector3(0, 1.0, 0)
	cam_yaw = yaw + deg_to_rad(25.0)
	cam_yaw_goal = cam_yaw
	cam_dist = dist
	cam_pitch = pitch
	cam_glide = {"pos": cam_target, "dist": dist, "pitch": pitch}
	await _wait(1.0)


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
	# the theme song (Alex's Sunset Lullaby) loops on the Music bus, and the panel shows its slider
	var theme: AudioStream = audio.music.stream
	var theme_loops: bool = theme is AudioStreamMP3 and (theme as AudioStreamMP3).loop
	_check("the theme song, Sunset Lullaby, loops in the background on the Music bus (%s, %.0f s, loop %s, playing %s, slider shown %s)" % [theme.resource_path.get_file() if theme else "none", theme.get_length() if theme else 0.0, theme_loops, audio.music.playing, hud.music_slider.is_visible_in_tree()],
		theme != null and theme.resource_path.ends_with("sunset_lullaby.mp3") and theme_loops and audio.music.playing and audio.music.bus == "Music" and hud.music_slider.is_visible_in_tree())
	audio.set_volumes(0.7, 0.8)
	hud.settings_panel.visible = false
	# title screen
	var hour_before := Game.hour
	Game.set_flag("weather", "rain")
	show_title(true)
	await _wait(1.2)
	await _shot("41_title.png")
	_check("the title is a clear golden hour over the farm (hour %.1f, weather %s)" % [Game.hour, Game.flag("weather")],
		absf(Game.hour - TITLE_HOUR) < 0.01 and str(Game.flag("weather")) == "clear")
	var faded := hud.chrome.all(func(c): return c.modulate.a < 0.05)
	_check("title screen: shown over the farm, clock paused, chrome hidden (visible %s, continue %s, chrome hidden %s)" % [hud.title_visible(), hud.title_continue_btn.visible, faded],
		hud.title_visible() and hud.title_continue_btn.visible and not Game.time_running and faded)
	_title_continue()
	await _wait(1.0)
	_check("Continue leaves the title and starts the clock again, at the save's own hour and weather (title %s, clock %s, hour %.2f from %.2f)" % [hud.title_visible(), Game.time_running, Game.hour, hour_before],
		not hud.title_visible() and Game.time_running and not title_on and Game.hour >= hour_before - 0.01 and Game.hour < hour_before + 0.6 and str(Game.flag("weather")) == "rain")
	Game.set_flag("weather", "clear")
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
	if "--only=perf" in OS.get_cmdline_user_args(): # just the frame rate at fixed spots, each graphics level (perf_check.gd)
		await _wait(1.5)
		await PerfCheck.new().run(self)
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=knit" in OS.get_cmdline_user_args(): # just the knitting game's checks and its pictures
		await _wait(1.5)
		await _knit_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=bench" in OS.get_cmdline_user_args(): # just the bench checks and their two pictures, in seconds
		await _wait(1.5)
		await _bench_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=flowers" in OS.get_cmdline_user_args(): # just the garden's Tripo flowers and the grass round them
		await _wait(1.5)
		await _flower_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=house" in OS.get_cmdline_user_args(): # just the house furniture checks, with every piece set out for a picture
		await _wait(1.5)
		await _house_checks(true)
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=cafe" in OS.get_cmdline_user_args(): # just the Coffee Shop, its candles and the books (about a minute)
		await _wait(1.5)
		await _cafe_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=store" in OS.get_cmdline_user_args(): # just the computer and the online store (about thirty seconds)
		await _wait(1.5)
		await _store_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=barista" in OS.get_cmdline_user_args(): # just working the café's counter (about a minute)
		await _wait(1.5)
		await _barista_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=fire" in OS.get_cmdline_user_args(): # just the fire and the candle flames, close up at night
		await _wait(1.5)
		await _fire_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=shops" in OS.get_cmdline_user_args(): # just the walk-in shops and their pictures
		await _wait(1.5)
		await _shop_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=townsfolk" in OS.get_cmdline_user_args(): # just the townsfolk: wandering, benches, the café, the red pin
		await _wait(1.5)
		await _townsfolk_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=cast" in OS.get_cmdline_user_args(): # just the town's cast and their routines (about a minute)
		await _wait(1.5)
		await _cast_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=mail" in OS.get_cmdline_user_args(): # just the post: the mailbox, letters on Barbara's round, a sweater order
		await _wait(1.5)
		await _mail_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=max" in OS.get_cmdline_user_args(): # just Max's visit: when he's due, both choices
		await _wait(1.5)
		await _max_checks()
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
	if "--only=world" in OS.get_cmdline_user_args(): # just the lands round the farm: paths there and a picture of each
		await _wait(1.5)
		await _world_checks()
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
	if "--only=early" in OS.get_cmdline_user_args(): # just the first half hour's systems: tools from Steve, trimming, felling, wood, seeds
		await _wait(1.5)
		await _early_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=sale" in OS.get_cmdline_user_args(): # just the money: sweaters the only income, asking and haggling, jobs' drops
		await _wait(1.5)
		await _sale_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=empire" in OS.get_cmdline_user_args(): # just the empire: the 20-minute day, bright nights, lantern, needles, catching, requests
		await _wait(1.5)
		await _empire_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=wolves" in OS.get_cmdline_user_args(): # just the wolves at night: the roll, the alert, scaring them off, a loss, the barn, a save
		await _wait(1.5)
		await _wolf_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=wildlife" in OS.get_cmdline_user_args(): # just the wild animals and birds: placing, combing, fleeing, flushing
		await _wait(1.5)
		await _wildlife_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=dog" in OS.get_cmdline_user_args(): # just the dog: his model and loops, playing him, his gaits
		await _wait(1.5)
		await _dog_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=suburb" in OS.get_cmdline_user_args(): # just Bretton Oaks: its houses, its sign, a night there (suburb_check.gd)
		await _wait(1.5)
		await SuburbCheck.new().run(self)
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=walkin" in OS.get_cmdline_user_args(): # just Marcus's house: in, up, down to the basement, out (walkin_check.gd)
		await _wait(1.5)
		await WalkinCheck.new().run(self)
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=buildings" in OS.get_cmdline_user_args(): # just the town's buildings and the barn in the house's textures
		await _wait(1.5)
		await _building_skin_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=exterior" in OS.get_cmdline_user_args(): # just the house's outside and its window glass
		await _wait(1.5)
		await _exterior_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=seethrough" in OS.get_cmdline_user_args(): # just scenery fading out of the camera's way
		await _wait(1.5)
		await _see_through_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=minimap" in OS.get_cmdline_user_args(): # just the minimap and walking by holding the mouse down
		await _wait(1.5)
		await _minimap_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=jobs" in OS.get_cmdline_user_args(): # just the jobs: the three offers, a shift of each, the pay
		await _wait(1.5)
		await _job_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=photo" in OS.get_cmdline_user_args(): # just cinematic mode: the free camera, photos and the album
		await _wait(1.5)
		await _photo_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=sweater" in OS.get_cmdline_user_args(): # just the knitted sweaters: the designs, wearing them
		await _wait(1.5)
		await _sweater_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=wardrobe" in OS.get_cmdline_user_args(): # just the wardrobe from her eyes: hangers, browsing, picking
		await _wait(1.5)
		await _wardrobe_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=build" in OS.get_cmdline_user_args(): # just building walls: rooms on the house, Gary's plots, a new house
		await _wait(1.5)
		await _build_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	if "--only=fps" in OS.get_cmdline_user_args(): # just first person: through her eyes
		await _wait(1.5)
		await _fps_checks()
		print("AUTOTEST DONE")
		get_tree().quit()
		return
	autotest_jog = true
	await _wait(1.5)
	await _shot("01_live.png")
	var chair = furniture.filter(func(f): return f.item_id == "rocking_chair")[0]
	_live_click(cam.unproject_position(chair.global_position + Vector3(0, 0.6, 0)))
	await _wait(0.4)
	_check("action menu opens on rocking chair as a ring (%s)" % str(hud.pie.labels()), hud.is_menu_open() and hud.pie.labels().size() == 3 and str(hud.pie.labels()[2]).begins_with("Read a book"))
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
	# her fingers round the needles (the knit_R and knit_L keys, tools/add_grip.py), close up from in front
	_check("her fingers close round both needles while she knits (grip %.2f)" % player.body.knit_grip(), player.body.knit_grip() > 0.99)
	var knit_sk: Skeleton3D = player.body.skeleton
	var knit_at: Vector3 = knit_sk.global_transform * ((knit_sk.get_bone_global_pose(knit_sk.find_bone("LeftHand")).origin + knit_sk.get_bone_global_pose(knit_sk.find_bone("RightHand")).origin) * 0.5)
	var knit_cam := Camera3D.new()
	add_child(knit_cam)
	var knit_front: Vector3 = player.global_transform.basis.z.normalized()
	knit_cam.fov = 40.0
	knit_cam.global_position = knit_at + knit_front * 0.85 + Vector3(0, 0.35, 0)
	knit_cam.look_at(knit_at + knit_front * 0.1, Vector3.UP)
	knit_cam.current = true
	var knit_screen: bool = knit.visible # the knitting game covers the screen: out of the way for this picture
	knit.visible = false
	await _wait(0.2)
	await _shot("02d_knit_hands.png")
	knit.visible = knit_screen
	knit_cam.queue_free()
	cam.current = true
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
	# click the shorn sheep herself: another may stand in front of her from the camera, so try a few
	# points on her and take the first the click's ray finds her at (it had opened a woolly one's menu)
	for sh in sheep_list:
		sh.hold_time = 2.0
	var shorn_at: Vector2 = cam.unproject_position(sheep_list[0].global_position + Vector3(0, 0.5, 0))
	for off in [Vector3(0, 0.5, 0), Vector3(0, 0.75, 0), Vector3(0.3, 0.5, 0), Vector3(-0.3, 0.5, 0), Vector3(0, 0.5, 0.3), Vector3(0, 0.5, -0.3)]:
		var sp: Vector2 = cam.unproject_position(sheep_list[0].global_position + off)
		if _ray_target(sp) == sheep_list[0]:
			shorn_at = sp
			break
	_live_click(shorn_at)
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
	Game.inv.erase("pumpkin_seeds")
	var no_seed: Dictionary = _plant_row("pumpkin")
	Game.add_item("pumpkin_seeds", 2)
	_do_action(plots[3], "plant_pumpkin")
	await _wait(6.0)
	_check("planted pumpkin from a seed (crop=%s, seeds 2→%d, coins %d→%d; with none the row is off: %s)" % [plots[3].crop, Game.count("pumpkin_seeds"), coins0, Game.coins, no_seed["label"]],
		plots[3].crop == "pumpkin" and Game.count("pumpkin_seeds") == 1 and Game.coins == coins0 and not bool(no_seed["enabled"]))
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
	_do_action(mail.box, "ship_sweater")
	await _wait(5.0)
	_check("shipped sweater (+%d)" % (Game.coins - coins1), Game.coins == coins1 + int(Game.SELL_PRICES["sweater"]))

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
	await _story_checks()
	await _act1_checks()
	await _romance_checks()
	await _polish_checks()
	await _house_checks(false)
	await _bench_checks()
	await _barn_checks()
	await _shop_checks()
	await _cafe_checks()
	await _barista_checks()
	await _store_checks()
	await _cast_checks()
	await _townsfolk_checks()
	await _mail_checks()
	await _max_checks()
	await _job_checks()
	await _flock_checks()
	await _light_checks()
	await _world_checks()
	await SuburbCheck.new().run(self)
	await _dog_checks()
	await _wildlife_checks()
	await _empire_checks()
	await _wolf_checks()
	await _sale_checks()
	await _sweater_checks()
	await _wardrobe_checks()
	await _photo_checks()
	await _fps_checks()
	await _minimap_checks()
	await _see_through_checks()
	await _early_checks()
	await _build_checks()
	await _hud_checks() # these two last: the tool checks walk her round the farm and dig it up
	await _tool_checks()
	await _god_checks() # ends by building the world again from the layout it saved, then "AUTOTEST DONE"


## The lands round the farm (scripts/regions.gd, data/regions.json): she can walk from her door to
## each one, their scenery is in the world editor's lists, the sea and the mountains are there,
## and a picture of each (49_world_<id>.png) with the frame time printed.
func _world_checks() -> void:
	var was_running: bool = Game.time_running
	Game.time_running = false
	_set_cam_lock(false)
	var peaks: AABB = regions.mountains.get_aabb() if is_instance_valid(regions.mountains) else AABB()
	_check("the mountains rise to %.0f m over %.0f m of the north; the sea meets the sand at z %.1f" % [peaks.end.y, peaks.size.x, regions.shore_z],
		peaks.end.y > 40.0 and peaks.size.x > 300.0 and is_instance_valid(regions.sea) and regions.shore_z > Regions.SAND_FLAT_TO)
	var home := Vector3(4.6, 0, 4.9)
	for id in regions.defs:
		var walk: Rect2 = Regions._rect(regions.defs[id]["walk"])
		var goal := Vector3(walk.get_center().x, 0, walk.get_center().y)
		var path := _find_path(home, goal)
		var end: Vector3 = path[path.size() - 1] if not path.is_empty() else home
		var off := Vector2(end.x, end.z).distance_to(Vector2(goal.x, goal.z))
		var kinds: Array = god.scenery.keys().filter(func(k): return str(k).begins_with(id + "-"))
		var things: int = kinds.reduce(func(n, k): return n + god.scenery[k].size(), 0)
		_check("%s: walkable from her door (%d steps, ends %.1f m from the middle) and its scenery is in the world editor (%d kinds, %d things)" % [regions.display_name(id), path.size(), off, kinds.size(), things],
			off < 6.0 and regions.region_at(end.x, end.z) == id and kinds.size() >= 2)
		# each from the side that shows it off: the swamp westward, the mountains northward, the sea southward
		var view: Array = {"swamp": [90.0, 32.0, 30.0], "mountains": [0.0, 44.0, 20.0], "beach": [180.0, 36.0, 24.0]}.get(id, [-90.0, 34.0, 30.0])
		Game.hour = 8.0 if id == "swamp" else 11.0
		player.position = end
		cam_yaw = deg_to_rad(float(view[0]))
		cam_yaw_goal = cam_yaw
		cam_target = end
		cam_dist = float(view[1])
		cam_pitch = float(view[2])
		cam_glide = {"pos": end, "dist": view[1], "pitch": view[2]}
		await _wait(3.0)
		var ms := await _frame_ms()
		print("      %s: %.1f ms a frame (%.0f fps), 3D at %d%%" % [id, ms, 1000.0 / ms, roundi(get_viewport().scaling_3d_scale * 100)])
		await _shot("49_world_%s.png" % id)
		cam_glide = {}
	# the range from the foothills, wide
	cam_yaw = 0.0
	cam_yaw_goal = 0.0
	cam_glide = {"pos": Vector3(35.0, 0.0, -70.0), "dist": 60.0, "pitch": 12.0}
	await _wait(3.0)
	await _shot("49_world_range.png")
	cam_glide = {}
	player.position = home
	cam_target = home
	Game.hour = 10.0
	await _wait(0.5)
	Game.time_running = was_running


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
	_check("SDFGI is on at Ultra graphics", gfx == GFX_ULTRA and env.sdfgi_enabled)
	Lighting.SkyBodies.clouds_override = 0.15 # a fair sky for the pictures, whatever the day's clouds (_sky_checks puts it back)
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
		if v[0] == "noon": # the same without the day's warm key and cool fill, to compare
			lighting.depth_enabled = false
			await _wait(1.0)
			await _shot("48_light_noon_flat.png")
			lighting.depth_enabled = true
		cam_glide = {}
	_check("the mist has burnt off by noon and stays away at dusk (%.2f, %.2f)" % [mist_at["noon"], mist_at["dusk"]],
		mist_at["noon"] < 0.01 and mist_at["dusk"] < 0.01 and not lighting.mist_volume.visible)
	await _sky_checks()
	Game.hour = 10.0
	await _wait(0.2)
	Game.time_running = was_running


## The sun and the moon (scripts/sky_bodies.gd): the moon's phase from the game's days, the clouds' own spells, the
## light (and its shadows) coming from the sun by day and the moon by night, brighter at full moon,
## and pictures of each in the sky (48_sky_sun.png, 48_sky_full_moon.png, 48_sky_crescent.png).
func _sky_checks() -> void:
	const SB = Lighting.SkyBodies
	var names: Array = [1, 8, 15, 22, 29].map(func(d): return Lighting.SkyBodies.phase_name(Lighting.SkyBodies.phase_at(d, 0.0)))
	_check("the moon goes round once a season, by the game's days: %s on days 1, 8, 15, 22 and 29; today (day %d) %s" % [", ".join(names), Game.day, SB.phase_name(SB.phase())],
		names == ["New moon", "First quarter", "Full moon", "Last quarter", "New moon"] and SB.phase_at(3, 18.0) > SB.phase_at(3, 6.0))
	var lo := 1.0
	var hi := 0.0
	var spells := 0
	var was := false
	for i in 28 * 24:
		var c := SB.cloudiness(1 + i / 24, float(i % 24))
		lo = minf(lo, c)
		hi = maxf(hi, c)
		var cloudy := c > 0.45
		if cloudy and not was:
			spells += 1
		was = cloudy
	_check("clouds come and go on their own over a season: from %.2f to %.2f, %d cloudy spells, the same hour gives the same sky" % [lo, hi, spells],
		lo < 0.2 and hi > 0.55 and spells >= 4 and SB.cloudiness(9, 13.5) == SB.cloudiness(9, 13.5))
	Game.hour = 12.5
	await _wait(0.3)
	var toward_sun: Vector3 = SB.dir_of(SB.sun_angles(12.5))
	_check("at noon the light comes from the sun in the sky (%.2f)" % sun.global_basis.z.dot(toward_sun), sun.global_basis.z.dot(toward_sun) > 0.98)
	var night := {}
	for ph in [0.5, 0.0]:
		SB.phase_override = ph
		Game.hour = 23.0
		await _wait(0.3)
		night[ph] = [sun.light_energy, sun.global_basis.z, SB.dir_of(SB.moon_angles(23.0, ph))]
	_check("a full moon lights the night from where it hangs (%.2f, from %.0f deg up); with no moon there's still some light to see by (%.2f)" % [night[0.5][0], rad_to_deg(asin(night[0.5][1].y)), night[0.0][0]],
		night[0.5][0] > 0.6 and night[0.0][0] > 0.3 and night[0.0][0] < night[0.5][0] - 0.2 and night[0.5][1].dot(night[0.5][2]) > 0.95)
	# pictures: the low sun before evening, a full moon rising, a crescent at dusk; the camera looks up at each
	for v in [["sun", 17.4, -1.0], ["clouds", 17.4, -1.0], ["full_moon", 20.7, 0.5], ["crescent", 19.9, 0.12]]:
		SB.phase_override = v[2]
		SB.clouds_override = 0.62 if v[0] == "clouds" else 0.1
		Game.hour = v[1]
		await _wait(0.2)
		var d: Vector3 = SB.dir_of(SB.sun_angles(v[1])) if v[0] == "sun" else SB.dir_of(SB.moon_angles(v[1], v[2]))
		cam_yaw = atan2(-d.x, -d.z)
		cam_yaw_goal = cam_yaw
		var up := rad_to_deg(asin(d.y))
		var aim := Vector3(30.0, 30.0, -10.0)
		cam_target = aim
		cam_dist = 30.0
		cam_pitch = -up + 4.0
		cam_glide = {"pos": aim, "dist": 30.0, "pitch": -up + 4.0}
		await _wait(2.5)
		await _shot("48_sky_%s.png" % v[0])
		cam_glide = {}
	SB.phase_override = -1.0
	SB.clouds_override = -1.0


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
		var fire_flames: Array = f.flames.filter(func(m): return not m.has_meta("candle")) # the mantel's candles aside
		var own_lights: Array = f.lights.filter(func(l): return not l.has_meta("candle"))
		if id == "fireplace":
			flames = fire_flames.size()
			lights += own_lights.size()
		if id == "lamp":
			lights += own_lights.size()
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
## the counter, and she talks to them from across it (Giorgio sells her a warm croissant). Each
## closes up again when she leaves.
## The Coffee Shop (data/interiors.json "cafe", art/world_assets/coffee_shop and cafe_props): walking in
## through its door, the room opening up, its candles and lamps coming up at dusk, the reading seats
## and shelves, the books (data/books.json, book_panel.gd): sitting down with one, turning its pages,
## the bookmark, choosing one from the shelf and carrying it to a seat, reading to the end; and the
## candles in Nora's house. Saves 56_cafe.png, 56_cafe_inside.png, 56_cafe_reading.png,
## 56_book_open.png, 56_cafe_shelf.png, 56_cafe_night.png and 56_house_candles.png.
## The café's upstairs (interiors.gd, data/interiors.json "cafe" "loft"): its seats and shelves, the
## walk from the door up the stairs to a sofa and back down, the loft shown only while she's up.
func _cafe_loft_checks(s, door_in: Vector3) -> void:
	var by: float = s.node.global_position.y
	var up_spots: Array = Interiors.read_spots("cafe").filter(func(r): return r.upstairs)
	var up_seats: Array = up_spots.filter(func(r): return r.kind == "seat")
	var open_cells := 0
	if s.loft_grid != null:
		for x in s.loft_grid.region.size.x:
			for z in s.loft_grid.region.size.y:
				if not s.loft_grid.is_point_solid(Vector2i(x, z)):
					open_cells += 1
	_check("the café has an upstairs: its floor part, %d pieces up there, %d reading seats and %d shelves, %.1f m² to walk on, and none of its seats offered to the regulars (%d downstairs)" % [s.loft_root.get_child_count() if s.loft_root else 0, up_seats.size(), up_spots.size() - up_seats.size(), open_cells * Interiors.LOFT_CELL * Interiors.LOFT_CELL, cafe_visits.free_seats().size()],
		s.parts.has("loft") and s.loft_root != null and s.loft_root.get_child_count() >= 20 and up_seats.size() >= 3 and up_spots.size() - up_seats.size() >= 2 and open_cells * 0.0625 > 25.0
		and cafe_visits.free_seats().all(func(r): return not r.upstairs))
	var sofa = up_seats.filter(func(r): return r.label.contains("Sofa"))
	if sofa.is_empty():
		return
	sofa = sofa[0]
	player.walk([])
	player.position = Vector3(door_in.x, 0, door_in.z)
	await _wait(0.3)
	_check("she's downstairs in the café and the loft is out of the way from above (loft %s)" % ("shown" if (s.parts["loft"] as Node3D).visible else "hidden"),
		s.inside and not s.up and not (s.parts["loft"] as Node3D).visible and not s.loft_root.visible)
	cam_target = s.node.global_transform * Vector3(3.0, 1.5, 0.0)
	cam_dist = 13.0
	var stairs: Node = s.node.find_child("StairSpot", false, false)
	var labels: Array = stairs.ke_actions().map(func(a): return a["label"]) if stairs else []
	if stairs:
		_do_action(stairs, "stairs_up")
	var t := 0.0
	var top_y := 0.0
	var mid_shot := false
	while (player.path.is_empty() == false or t < 0.3) and t < 40.0:
		await _wait(0.1)
		t += 0.1
		top_y = maxf(top_y, player.position.y - by)
		if not mid_shot and player.position.y - by > 1.5:
			mid_shot = true
			await _shot("56_cafe_stairs.png")
	await _wait(0.4)
	var dy: float = player.position.y - by - s.loft_y
	_check("the stairs say %s from below, and up them she goes (%.1f s, %.2f m off the loft's floor, upstairs %s, loft %s, roof %s)" % [str(labels), t, dy, s.up, "shown" if (s.parts["loft"] as Node3D).visible else "hidden", "on" if (s.parts["roof"] as Node3D).visible else "off"],
		labels == ["Go upstairs"] and t < 40.0 and absf(dy) < 0.08 and s.up and (s.parts["loft"] as Node3D).visible and s.loft_root.visible and not (s.parts["roof"] as Node3D).visible)
	# sits on a sofa up there with a book, and gets up again on the loft's floor
	_do_action(sofa, "read_book")
	t = 0.0
	while not books_ui.visible and t < 30.0:
		await _wait(0.25)
		t += 0.25
	await _wait(0.5)
	var seat_dy: float = player.position.y - (sofa.seat_point() as Vector3).y
	cam_target = player.position + Vector3(0, 0.5, 0)
	cam_dist = 11.0
	await _wait(1.2)
	await _shot("56_cafe_loft.png")
	_check("she sits down on a sofa upstairs with a book (%.1f s, %.2f m off its seat, reading %s)" % [t, seat_dy, books_ui.visible], books_ui.visible and player.busy and absf(seat_dy) < 0.05)
	await _key_tap(KEY_ESCAPE)
	await _wait(0.6)
	dy = player.position.y - by - s.loft_y
	_check("and gets up on the loft's floor (%.2f m off it, sitting %s)" % [dy, player.busy], not player.busy and absf(dy) < 0.05)
	# a click on the loft's floor lands up there
	var mid: Vector3 = s.node.global_transform * Vector3(-1.0, s.loft_y, -2.0)
	var hit: Variant = _ground_point(cam.unproject_position(mid))
	_check("a click upstairs lands on the loft's floor (%s)" % str(hit), hit != null and absf((hit as Vector3).y - (by + s.loft_y)) < 0.01 and (hit as Vector3).distance_to(mid) < 0.2)
	# down by the stairs, then to the door
	labels = stairs.ke_actions().map(func(a): return a["label"]) if stairs else []
	if stairs:
		_do_action(stairs, "stairs_down")
	t = 0.0
	while (player.path.is_empty() == false or t < 0.3) and t < 40.0:
		await _wait(0.1)
		t += 0.1
	await _wait(0.3)
	var foot_y: float = player.position.y - by
	player.walk(_find_path(player.position, door_in))
	var t2 := 0.0
	while not player.path.is_empty() and t2 < 20.0:
		await _wait(0.1)
		t2 += 0.1
	await _wait(0.4)
	_check("from above the stairs say %s, and down she goes and out to the door (%.1f + %.1f s, %.2f m up at the foot, %.2f m now, upstairs %s, %.2f m from the door)" % [str(labels), t, t2, foot_y, player.position.y - by, s.up, Vector2(player.position.x - door_in.x, player.position.z - door_in.z).length()],
		labels == ["Go downstairs"] and t < 40.0 and absf(foot_y) < 0.05 and absf(player.position.y - by) < 0.05 and not s.up and Vector2(player.position.x - door_in.x, player.position.z - door_in.z).length() < 0.6)


func _cafe_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	# the books
	var books: Array = books_ui.books()
	var bad := []
	var genres := {}
	var ids := {}
	for b in books:
		var n: int = (b.get("pages", []) as Array).size()
		genres[str(b.get("genre", ""))] = int(genres.get(str(b.get("genre", "")), 0)) + 1
		ids[str(b.get("id", ""))] = true
		if n < 10 or n > 20 or str(b.get("title", "")) == "" or not BookPanel.COVER.has(str(b.get("cover", ""))):
			bad.append(str(b.get("id", "?")))
	_check("data/books.json: %d books of 10 to 20 pages, horror %d, thriller %d, romance %d %s" % [books.size(), int(genres.get("horror", 0)), int(genres.get("thriller", 0)), int(genres.get("romance", 0)), str(bad)],
		books.size() >= 20 and ids.size() == books.size() and bad.is_empty() and genres.size() == 3 and genres.values().all(func(c): return int(c) >= 5))
	# a candle on its own, from the catalogue
	var probe := Furniture.new()
	add_child(probe)
	probe.setup("candle", 0)
	_check("the candle is in Builder's Delight's catalogue with the books, and lit (%d light, %d flames, %d halo)" % [probe.lights.size(), probe.flames.size(), probe.find_children("*", "Sprite3D", false, false).size()],
		"candle" in Catalog.INDOOR and "book_plum" in Catalog.INDOOR and "book_stack" in Catalog.INDOOR and probe.lights.size() == 1 and probe.flames.size() == 1
		and probe.find_children("*", "Sprite3D", false, false).size() == 1 and probe.lights[0].has_meta("no_shadow"))
	probe.queue_free()
	var s = Interiors.shops.get("cafe")
	if s == null or not s.node.visible:
		_check("the Coffee Shop is a walk-in shop", false)
		return
	var xf: Transform3D = s.node.global_transform
	var room: Node = s.node.find_child("Furnishings", false, false)
	var spots: Array = Interiors.read_spots("cafe")
	var seats: Array = spots.filter(func(r): return r.kind == "seat")
	var shelves: Array = spots.filter(func(r): return r.kind == "shelf")
	var candles: Array = s.lights.filter(func(l): return l.has_meta("candle"))
	_check("the Coffee Shop is a walk-in shop: %d parts, %d pieces, %d reading seats, %d bookshelves, %d candles and %d lamps lit" % [s.parts.size(), room.get_child_count() if room else 0, seats.size(), shelves.size(), candles.size(), s.lights.size() - candles.size()],
		s.parts.size() >= 11 and room != null and room.get_child_count() >= 40 and seats.size() >= 16 and shelves.size() >= 3 and candles.size() >= 20)
	# every seat and shelf can be walked up to from the door (none boxed in by the furniture)
	var door_in: Vector3 = xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y - 1.0)
	var cut_off := []
	for r in spots:
		var sp: Vector3 = r.stand_point()
		var route := _find_path(door_in, sp)
		var end: Vector3 = route[-1] if not route.is_empty() else door_in
		if Vector2(end.x - sp.x, end.z - sp.z).length() > 0.75 or Interiors.inside_of(end) != "cafe":
			cut_off.append("%s@%s" % [r.label, str(snapped(xf.affine_inverse() * sp, Vector3(0.1, 0.1, 0.1)))])
	_check("every reading seat and bookshelf in the café can be walked up to from the door %s" % str(cut_off), cut_off.is_empty())
	if not cut_off.is_empty(): # the room's walking grid, back wall at the top: # blocked, . open
		for zi in range(int(s.room.position.y * 4.0), int(s.room.end.y * 4.0) + 1):
			var row := ""
			for xi in range(int(s.room.position.x * 4.0), int(s.room.end.x * 4.0) + 1):
				row += "." if _walkable(_cell(xf * Vector3(xi * 0.25, 0, zi * 0.25))) else "#"
			print("CAFE GRID %5.2f %s" % [zi * 0.25, row])
	# the walls block the walking grid all the way round (a thin wall can fall between cell centres)
	var leaks := []
	for side in [["left", -1], ["right", 1]]:
		for z in range(int(ceilf(s.room.position.y + 0.6)), int(s.room.end.y - 0.4)):
			var solid := false
			for k in 9:
				var x: float = float(side[1]) * (s.room.size.x * 0.5 - 0.35 + k * 0.1)
				solid = solid or not _walkable(_cell(xf * Vector3(x, 0, z)))
			if not solid:
				leaks.append("%s@%.1f" % [side[0], z])
	for x in [-5.2, -4.2, -3.2, -2.2, -1.2, 1.2, 2.2, 3.2, 4.2, 5.2]:
		if absf(x) > s.room.size.x * 0.5 - 0.4:
			continue
		for zz in [s.room.position.y, s.room.end.y]:
			var solid2 := false
			for k in 9:
				solid2 = solid2 or not _walkable(_cell(xf * Vector3(x, 0, zz - 0.4 + k * 0.1)))
			if not solid2:
				leaks.append("z%.1f@%.1f" % [zz, x])
	_check("she can't walk through the Coffee Shop's walls %s" % str(leaks), leaks.is_empty())
	await _cafe_loft_checks(s, door_in)
	# outside, shut; then in through the door to the armchair by the fire
	var out_front: Vector3 = xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y + 2.2)
	out_front.y = 0.0
	player.walk([])
	player.position = out_front
	_set_cam_lock(false)
	cam_target = xf * Vector3(0, 2.0, 1.0)
	cam_dist = 30.0
	await _wait(1.6)
	var shut: bool = s.open < 0.05 and (s.parts["roof"] as Node3D).visible and not s.inside
	var shut_t := 0.0
	while not shut and shut_t < 5.0: # the checks before may have left the door open behind her
		await _wait(0.25)
		shut_t += 0.25
		shut = s.open < 0.05 and (s.parts["roof"] as Node3D).visible and not s.inside
	await _shot("56_cafe.png")
	var chair = seats.filter(func(r): return r.label.contains("Armchair"))
	chair = chair[0] if not chair.is_empty() else seats[0]
	Game.flags.erase("books")
	Game.flags.erase("book_last")
	Game.happiness = 50.0
	var joy0: float = Game.happiness
	_do_action(chair, "read_book")
	var t := 0.0
	while not books_ui.visible and t < 30.0:
		await _wait(0.25)
		t += 0.25
	await _wait(0.6)
	var seat_d: float = Vector2(player.position.x, player.position.z).distance_to(Vector2(chair.seat_point().x, chair.seat_point().z))
	_check("she walks in through the café's door to the armchair and sits down with a book (shut first %s, %.1f s, inside %s, door %.0f%% open, roof %s, %.2f m from the seat, sitting %s, '%s' %s, picking %s)" % [shut, t, s.inside, s.open * 100.0, "hidden" if not (s.parts["roof"] as Node3D).visible else "shown", seat_d, player.busy, books_ui._head.text, books_ui.current, books_ui.pick_mode],
		shut and s.inside and s.open > 0.9 and not (s.parts["roof"] as Node3D).visible and player.busy and seat_d < 0.1 and books_ui.visible and books_ui.current == str(books[0]["id"]) and not books_ui.pick_mode)
	books_ui.visible = false
	cam_target = xf * Vector3(-0.6, 1.0, -1.6)
	cam_dist = 9.5
	await _wait(1.5)
	await _shot("56_cafe_inside.png")
	cam_target = player.position + Vector3(0, 1.0, 0)
	cam_dist = 4.5
	await _wait(1.2)
	await _shot("56_cafe_reading.png")
	var nbook = ReadingPose.holding(player)
	_check("Nora reads with the open book held up in both hands (%s)" % str(nbook != null and nbook.reach.size() == 2), nbook != null and nbook.reach.size() == 2)
	books_ui.visible = true
	await _key_tap(KEY_RIGHT)
	await _key_tap(KEY_RIGHT)
	await _key_tap(KEY_RIGHT)
	await _wait(0.3)
	await _shot("56_book_open.png")
	var spread: int = books_ui.spread
	var shown: String = books_ui._pages[0].text
	await _key_tap(KEY_ESCAPE)
	await _wait(0.4)
	var mark: Dictionary = (Game.flag("books", {}) as Dictionary).get(str(books[0]["id"]), {})
	_check("the arrow keys turn the pages (pages %d–%d, the page's own words shown), Esc puts the book down: she gets up a little happier (%.0f -> %.0f) and it keeps her place (page %d)" % [spread + 1, spread + 2, joy0, Game.happiness, int(mark.get("page", -1)) + 1],
		spread == 6 and shown == str((books[0]["pages"] as Array)[6]) and not books_ui.visible and not player.busy and Game.happiness > joy0 and int(mark.get("page", -1)) == 6)
	# choosing a book from a shelf: she carries it to the nearest seat
	var shelf = shelves[0]
	_do_action(shelf, "read_pick")
	t = 0.0
	while not books_ui.visible and t < 30.0:
		await _wait(0.25)
		t += 0.25
	books_ui.show_book("the_night_ferry")
	await _wait(0.4)
	cam_target = player.position + Vector3(0, 1.2, 0)
	cam_dist = 6.0
	await _wait(0.8)
	await _shot("56_cafe_shelf.png")
	var picking: bool = books_ui.visible and books_ui.pick_mode and books_ui._cover_box.visible
	books_ui._take_it()
	t = 0.0
	while not (books_ui.visible and player.busy) and t < 30.0:
		await _wait(0.25)
		t += 0.25
	var near = reading_seat_near(player.position)
	_check("from the bookshelf she chooses The Night Ferry and sits down with it in the nearest seat (%.1f s, reading '%s', %s)" % [t, books_ui.current, near.label if near != null else "no seat"],
		picking and books_ui.visible and player.busy and books_ui.current == "the_night_ferry" and not books_ui.pick_mode and near != null and Interiors.inside_of(player.position) == "cafe")
	for i in 12:
		books_ui.turn_page(1)
	var ended: bool = books_ui._where.text.contains("The End")
	books_ui.close()
	await _wait(0.3)
	_check("she reads it to the end, and finishing it says so (%s; '%s')" % [str(books_ui.finished), hud.toast_label.text],
		ended and "the_night_ferry" in books_ui.finished and hud.toast_label.text.contains("finished") and bool(((Game.flag("books", {}) as Dictionary).get("the_night_ferry", {}) as Dictionary).get("done", false)))
	# a regular drops in for a coffee and a book (cafe_visits.gd): to the counter, then a free seat
	var reg := _villager("rowan")
	var home_was: Vector3 = reg.home if reg != null else Vector3.ZERO
	var home0 := Vector3.ZERO
	var visited := false
	var steps := []
	if reg != null:
		cafe_visits.visits.clear()
		cafe_visits.seen.clear()
		reg.settle_at(xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y + 2.5)) # just outside, to save the walk
		reg.position.y = 0.0
		home0 = reg.home
		visited = cafe_visits.start("rowan")
		t = 0.0
		while visited and t < 40.0 and str(cafe_visits.visits.get("rowan", {}).get("state", "")) != "reading":
			cafe_visits.update()
			var st := str(cafe_visits.visits.get("rowan", {}).get("state", ""))
			if steps.is_empty() or steps[-1] != st:
				steps.append(st)
			await _wait(0.5)
			t += 0.5
	var vis: Dictionary = cafe_visits.visits.get("rowan", {})
	var rseat = vis.get("seat")
	var book_on: bool = reg != null and reg.find_child("ReadingBook", false, false) != null
	var seat_off: float = 99.0 if rseat == null else Vector2(reg.position.x, reg.position.z).distance_to(Vector2(rseat.seat_point().x, rseat.seat_point().z))
	cam_target = reg.position + Vector3(0, 1.0, 0) if reg != null else cam_target
	cam_dist = 5.0
	await _wait(1.2)
	await _shot("56_cafe_regular.png")
	# he holds the open book up in both hands and looks down into it (reading_pose.gd)
	var rbook = ReadingPose.holding(reg) if reg != null else null
	var gaps: Array = []
	if rbook != null:
		for ik in rbook.reach:
			gaps.append(snappedf((ik as WardrobeView.ReachIK).hand_gap, 0.01))
	var eyes_on: bool = rbook != null and reg.body != null and reg.body.look_target != null and (reg.body.look_target as Vector3).distance_to(rbook.look_point()) < 0.05
	var in_front: bool = rbook != null and (reg.global_transform.affine_inverse() * rbook.global_position).z > 0.15
	_check("reading, Rowan holds the open book up in front of him in both hands and looks into it (hands %s m from the pages, looking %s, in front %s)" % [str(gaps), eyes_on, in_front],
		rbook != null and gaps.size() == 2 and gaps.all(func(g): return float(g) < 0.12) and eyes_on and in_front)
	var blocked: bool = rseat != null and rseat.taken() and not rseat.ke_actions()[0]["enabled"] and reading_seat_near(rseat.global_position) != rseat
	_check("Rowan drops into the café for a coffee: up to the counter, then sits reading in a free seat with a book (%s, %.1f s, %.2f m from the seat, book %s), and Nora isn't offered his seat" % [" > ".join(steps), t, seat_off, book_on],
		visited and str(vis.get("state", "")) == "reading" and steps.has("ordering") and reg.anim_override == "SitIdle" and seat_off < 0.1 and book_on and blocked)
	if reg != null and cafe_visits.visits.has("rowan"):
		cafe_visits.visits["rowan"]["until"] = 0.0
		cafe_visits.update()
		await _wait(0.6)
		var left_ok: bool = str(cafe_visits.visits.get("rowan", {}).get("state", "")) == "leaving" and reg.anim_override == "" and reg.find_child("ReadingBook", false, false) == null and (rseat == null or rseat.occupant == null)
		story.scene_started.emit("test") # a scene starting sends everyone home at once
		_check("when his time's up he gets up, leaves the book and heads back; a story scene sends him home at once (seat free %s)" % str(rseat == null or rseat.occupant == null),
			left_ok and cafe_visits.visits.is_empty() and Vector2(reg.position.x, reg.position.z).distance_to(Vector2(home0.x, home0.z)) < 0.1)
	if reg != null:
		reg.settle_at(home_was)
	# at night: the candles and lamps are up and flicker each in its own time
	var day_e: float = candles[0].light_energy
	Game.hour = 21.5
	await _wait(1.5)
	var es := []
	for l in candles.slice(0, 4):
		es.append(snappedf((l as OmniLight3D).light_energy, 0.001))
	_check("at night the café's candles are lit up (%.2f by day, now %s) and flicker out of step" % [day_e, str(es)],
		float(es[0]) > day_e * 2.0 and es.size() == 4 and es.max() - es.min() > 0.01)
	player.walk([])
	player.position = xf * Vector3(-0.3, 0, 0.6) # inside, so the roof is off
	player.position.y = 0.0
	cam_target = xf * Vector3(0.0, 1.0, -2.0)
	cam_dist = 14.0
	await _wait(1.2)
	await _shot("56_cafe_night.png")
	# candles in Nora's house: on the mantel, the coffee table, the kitchen counter and the bookshelf
	var lit := {}
	for f in furniture:
		if is_instance_valid(f) and f.lights.any(func(l): return l.has_meta("candle")):
			lit[f.item_id] = f.lights.filter(func(l): return l.has_meta("candle")).size()
	_check("candles are lit in Nora's house %s" % str(lit), lit.size() >= 3 and lit.values().reduce(func(a, b): return a + b, 0) >= 4)
	var fp = furniture.filter(func(f): return is_instance_valid(f) and f.item_id == "fireplace")
	player.walk([])
	player.position = Vector3(4.6, 0, 4.9)
	if not fp.is_empty():
		cam_target = (fp[0] as Node3D).global_position + Vector3(0, 1.0, 0)
		cam_dist = 7.0
		await _wait(1.5)
		await _shot("56_house_candles.png")
	Game.hour = 11.0
	_set_cam_lock(true)
	await _wait(0.5)


## The fire in her fireplace and the candles on its mantel at night (shaders/fire.gdshader,
## candle_flame.gdshader): three sheets of flame, the coals and the sparks; a camera of its own looks
## at them close up a few moments apart, then from the game's own camera. Saves 61_fire_*.png.
## Working behind the café's counter (barista.gd): the counter's row, first person behind it, a
## customer asking, grind, filter, the button, ten seconds, pour, hand over, 5 coins; a pot pours 4.
func _barista_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var s = Interiors.shops.get("cafe")
	var found: Array = s.node.find_children("WorkSpot", "Node3D", true, false) if s != null else []
	if found.is_empty():
		_check("the café's counter has a place to work behind it", false)
		return
	var spot = found[0]
	var xf: Transform3D = s.node.global_transform
	var acts: Array = _actions_for(spot)
	_check("the café counter's menu says 'Work behind the counter' at any hour (%s at 11:00)" % str(acts.map(func(a): return a["label"])),
		acts.size() == 1 and str(acts[0]["label"]) == "Work behind the counter" and bool(acts[0]["enabled"]))
	Game.hour = 22.5
	acts = _actions_for(spot)
	_check("and late at night too (%s at 22:30)" % str(acts.map(func(a): return a["label"])), acts.size() == 1 and bool(acts[0]["enabled"]))
	Game.hour = 11.0
	# from out in the square, in through the door to the counter
	player.walk([])
	player.position = xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y + 2.0)
	player.position.y = 0.0
	await _wait(0.5)
	_do_action(spot, "work_counter")
	var t := 0.0
	while not barista.active and t < 30.0:
		await _wait(0.25)
		t += 0.25
	barista.next_customer_t = 999.0 # the test calls its own customers
	await _wait(1.0)
	var local: Vector3 = xf.affine_inverse() * player.position
	_check("she walks in to the counter and steps behind it in first person, the café's ceiling over her (%.1f s, first person %s, locked %s, at %s in the café, roof %s)" % [t, fps.active, fps.locked, str(snapped(local, Vector3(0.01, 0.01, 0.01))), (s.parts["roof"] as Node3D).visible],
		barista.active and fps.active and fps.locked and local.z < -5.2 and local.z > -6.0 and absf(local.x - 2.2) < 0.9 and (s.parts["roof"] as Node3D).visible)
	await _shot("62_barista_counter.png")
	# Rowan comes in and asks for a coffee
	var rowan = _villager("rowan")
	rowan.settle_at(xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y - 1.0))
	var called: bool = barista.call_customer("rowan")
	t = 0.0
	while (barista.customer.is_empty() or str(barista.customer["state"]) != "waiting") and t < 25.0:
		await _wait(0.25)
		t += 0.25
	await _wait(0.6)
	_check("Rowan walks up to the counter and asks for a coffee (%s, %.1f s, '%s', next: %s)" % [called, t, barista.line, barista.next_step()["label"]],
		called and not barista.customer.is_empty() and str(barista.customer["state"]) == "waiting" and barista.line.contains("coffee") and str(barista.next_step()["id"]) == "grind")
	await _shot("62_barista_customer.png")
	# grind, filter, the button
	var order := []
	for want in ["grind", "filter", "brew"]:
		order.append(str(barista.next_step()["id"]))
		await _key_tap(KEY_E)
		t = 0.0
		while (barista.busy != "" or barista.steps_done.size() < order.size()) and t < 5.0:
			await _wait(0.1)
			t += 0.1
		if want == "grind":
			await _shot("62_barista_grind.png")
	var started := Time.get_ticks_msec()
	_check("E grinds the beans, puts them in the filter and presses the button, in that order (%s, done %s, brewing %s)" % [str(order), str(barista.steps_done), barista.brewing],
		order == ["grind", "filter", "brew"] and barista.steps_done == ["grind", "filter", "brew"] and barista.brewing)
	await _key_tap(KEY_E) # nothing to do while it brews
	await _wait(2.0)
	await _shot("62_barista_brewing.png")
	var early: bool = barista.pot == 0 and barista.brewing and str(barista.next_step()["id"]) == ""
	while barista.brewing and Time.get_ticks_msec() - started < 20000:
		await _wait(0.1)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	_check("the pot brews for ten seconds and holds four cups (nothing to do meanwhile %s, %.1f s, %d cups)" % [early, secs, barista.pot],
		early and secs > 9.0 and secs < 11.5 and barista.pot == Barista.CUPS)
	# pour and hand it over
	var coins0: int = Game.coins
	await _key_tap(KEY_E)
	while barista.busy != "":
		await _wait(0.1)
	await _shot("62_barista_pour.png")
	var poured: bool = barista.poured and barista._cup.visible
	await _key_tap(KEY_E)
	while barista.busy != "":
		await _wait(0.1)
	await _wait(0.3)
	var vis: Dictionary = cafe_visits.visits.get("rowan", {})
	_check("she pours Rowan a cup and hands it over: 5 coins, all hers, three cups left, and Rowan takes it to a seat (poured %s, +%d coins, %d cups, Rowan %s with a cup %s)" % [poured, Game.coins - coins0, barista.pot, str(vis.get("state", "gone")), vis.get("cup") != null],
		poured and Game.coins - coins0 == Barista.PAY and barista.pot == Barista.CUPS - 1 and str(vis.get("state", "")) == "to_seat" and vis.get("cup") != null)
	var paused: bool = barista.customer.is_empty() and barista._last == "rowan" and barista.next_customer_t >= Barista.PAUSE - 0.5
	await _wait(3.0)
	_check("one customer at a time: nobody else comes up while Rowan carries his coffee off, then a %.0f s pause (waiting on him %s, next in %.1f s, customer %s)" % [Barista.PAUSE, paused, barista.next_customer_t, not barista.customer.is_empty()],
		paused and barista.customer.is_empty())
	# the next customer gets a cup from the same pot, no grinding
	var wren = _villager("wren")
	wren.settle_at(xf * Vector3(float(s.info.get("door_x", 0.0)), 0, s.room.end.y - 1.0))
	barista.call_customer("wren")
	t = 0.0
	while (barista.customer.is_empty() or str(barista.customer["state"]) != "waiting") and t < 25.0:
		await _wait(0.25)
		t += 0.25
	var nxt := str(barista.next_step()["id"])
	await _key_tap(KEY_E)
	while barista.busy != "":
		await _wait(0.1)
	await _key_tap(KEY_E)
	while barista.busy != "":
		await _wait(0.1)
	_check("Wren's coffee comes from the same pot, no grinding (next was '%s', +%d coins in all, %d cups left, %d served)" % [nxt, Game.coins - coins0, barista.pot, barista.served],
		nxt == "pour" and Game.coins - coins0 == Barista.PAY * 2 and barista.pot == Barista.CUPS - 2 and barista.served == 2)
	# Rowan sits down with the coffee
	t = 0.0
	while str(cafe_visits.visits.get("rowan", {}).get("state", "")) != "reading" and t < 20.0:
		await _wait(0.5)
		t += 0.5
	_check("Rowan sits down with the coffee and a book (%s after %.1f s)" % [str(cafe_visits.visits.get("rowan", {}).get("state", "gone")), t],
		str(cafe_visits.visits.get("rowan", {}).get("state", "")) == "reading")
	await _shot("62_barista_regular.png")
	# Esc: out from behind the counter, the overhead camera back
	await _key_tap(KEY_ESCAPE)
	await _wait(0.6)
	local = xf.affine_inverse() * player.position
	_check("Esc steps her out from behind the counter with the overhead camera back (active %s, first person %s, at z %.2f in the café)" % [barista.active, fps.active, local.z],
		not barista.active and not fps.active and not fps.locked and local.z > -4.5)
	await _shot("62_barista_after.png")
	cafe_visits.end_all()


func _fire_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	var fps_ := furniture.filter(func(f): return is_instance_valid(f) and f.item_id == "fireplace")
	if fps_.is_empty():
		_check("there is a fireplace in her house", false)
		return
	var fp: Furniture = fps_[0]
	var sheets: Array = fp.flames.filter(func(m): return not m.has_meta("candle") and m.material_override is ShaderMaterial)
	var candles: Array = fp.flames.filter(func(m): return m.has_meta("candle") and m.material_override is ShaderMaterial)
	var sparks := fp.find_child("Sparks", false, false) as GPUParticles3D
	_check("the fire is three living sheets of flame over glowing coals with sparks rising, and the mantel's candles burn with real flames (%d sheets, %d candle flames, sparks %s)" % [sheets.size(), candles.size(), sparks != null and sparks.emitting],
		sheets.size() == 3 and candles.size() == 2 and sparks != null and sparks.emitting)
	# its crackle (Catalog.fire_sound): a looping 3D sound by the fire, and one in the café's fireplace
	await _wait(0.2)
	var snd := fp.find_child("FireSound", false, false) as AudioStreamPlayer3D
	var cafe_snd := 0
	var cafe = Interiors.shops.get("cafe")
	if cafe != null:
		cafe_snd = cafe.node.find_children("FireSound", "AudioStreamPlayer3D", true, false).size()
	var looped: bool = snd != null and snd.stream is AudioStreamOggVorbis and (snd.stream as AudioStreamOggVorbis).loop
	_check("the fire crackles: a looping sound by the hearth, heard within %.0f m on the Ambience bus (playing %s, looped %s), and the café's fireplace too (%d)" % [snd.max_distance if snd else 0.0, snd != null and snd.playing, looped, cafe_snd],
		snd != null and snd.playing and looped and snd.bus == "Ambience" and cafe_snd >= 1)
	Game.hour = 21.5
	player.walk([])
	player.position = fp.global_transform * Vector3(0, 0, 2.6)
	player.position.y = 0.0
	await _wait(1.5)
	var eye := Camera3D.new()
	eye.fov = 45.0
	add_child(eye)
	var xf := fp.global_transform
	eye.look_at_from_position(xf * Vector3(0.0, 0.75, 2.0), xf * Vector3(0.0, 0.5, -0.1))
	eye.make_current()
	for i in 3:
		await _wait(0.35)
		await _shot("61_fire_%d.png" % i)
	eye.look_at_from_position(xf * Vector3(0.45, 1.62, 0.75), xf * Vector3(0.62, 1.6, 0.18))
	await _wait(0.4)
	await _shot("61_fire_candle.png")
	eye.look_at_from_position(xf * Vector3(0.0, 1.2, 1.6), xf * Vector3(0.0, 0.45, -0.1))
	await _wait(0.4)
	await _shot("61_fire_above.png")
	cam.make_current()
	eye.queue_free()
	cam_target = fp.global_position + Vector3(0, 0.8, 0)
	var cd := cam_dist
	cam_dist = 9.0
	await _wait(1.2)
	await _shot("61_fire_overhead.png")
	cam_dist = cd
	Game.hour = 11.0
	await _wait(0.3)


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
		var price := _pastry_price()
		var c0 := Game.coins
		var pastries0 := Game.count("pastry")
		if id == "bakery":
			Game.coins = maxi(Game.coins, price + 5)
			c0 = Game.coins
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
			_check("Giorgio sells her a pastry for her bag (%dc, pastries %d -> %d)" % [c0 - Game.coins, pastries0, Game.count("pastry")],
				Game.coins == c0 - price and Game.count("pastry") == pastries0 + 1)
			await _pastry_checks(v)
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


## The townsfolk (scripts/townsfolk_check.gd).
func _townsfolk_checks() -> void:
	await TownsfolkCheck.new().run(self)


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


const FLOWER_IDS := ["sunflowers", "rose_bush", "mallow", "hollyhocks", "hydrangea"]


## The garden's big flowers (art/world_assets/flowers: one Tripo lineup cut into five models), set out
## in a row on the grass east of the house, and the grass blades round them close up.
func _flower_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 10.5
	var at := Vector3(14.0, 0, 6.0)
	var set_out: Array = []
	for i in FLOWER_IDS.size():
		var id: String = FLOWER_IDS[i]
		var f := Furniture.new()
		add_child(f)
		f.setup(id, 0)
		f.position = at + Vector3(i * 1.3 - 2.6, 0, 0)
		set_out.append(f)
		var meshes: Array = f.find_children("*", "MeshInstance3D", true, false)
		var tall := 0.0
		for m in meshes:
			var mi: MeshInstance3D = m
			tall = maxf(tall, (mi.global_transform * mi.get_aabb()).end.y)
		var want: float = float(Catalog.ITEMS[id].get("height", 1.0))
		_check("flowers: %s is its Tripo model (%d meshes, %.2f m tall, catalogue says %.2f)" % [id, meshes.size(), tall, want],
			Catalog.ITEMS[id].has("model") and meshes.size() >= 1 and absf(tall - want) < 0.15)
	_set_cam_lock(false)
	player.position = at + Vector3(0, 0, 2.6)
	cam_target = at + Vector3(0, 0.6, 0)
	cam_dist = 8.0
	await _wait(2.0)
	await _shot("62_flowers.png")
	cam_target = at + Vector3(-2.6, 0.9, 0)
	cam_dist = 3.2
	await _wait(1.6)
	await _shot("62_flowers_sunflowers.png")
	cam_target = at + Vector3(0, 0.0, 3.5)
	cam_dist = 8.0
	await _wait(1.6)
	await _shot("62_grass.png")
	var blades: int = grass.drawn_blades()
	_check("flowers: the grass still draws the same blades (%d)" % blades, blades > 10000)
	# the blade is 7 shared points, and the patches come from the bake (grass.gd _bake_patches): the same
	# view worked out per blade is saved beside it to compare
	var bm: ArrayMesh = grass._blade_mesh
	var arrs := bm.surface_get_arrays(0)
	var pts: int = (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var idx: int = (arrs[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arrs[Mesh.ARRAY_INDEX] != null else 0
	var baked: bool = grass.blade_mat.get_shader_parameter("patch_baked") == true
	var pimg: Image = grass.patch_vp.get_texture().get_image()
	var lo := 1.0
	var hi := 0.0
	for i in 64:
		var c := pimg.get_pixel(i * 37 % pimg.get_width(), i * 53 % pimg.get_height())
		lo = minf(lo, c.r)
		hi = maxf(hi, c.r)
	grass.blade_mat.set_shader_parameter("patch_baked", false)
	await _wait(0.3)
	await _shot("62_grass_unbaked.png")
	grass.blade_mat.set_shader_parameter("patch_baked", true)
	_check("grass: each blade is %d shared points (%d indices), and its light and dark patches come from the %dx%d bake (drifts %.2f..%.2f)" % [pts, idx, pimg.get_width(), pimg.get_height(), lo, hi],
		pts == 7 and idx == 15 and baked and hi - lo > 0.3)
	for f in set_out:
		f.queue_free()
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

	# roads reach the whole map (Alex, 2026-11-17), and the dropdown has pavement and sidewalk:
	# out in the east meadows, past where the map used to end, on the meadow's own ground
	var far_pave := Vector3(120.0, 0, -20.0)
	var far_side := far_pave + Vector3(2.5, 0, 0)
	await _god_look(far_pave, 18.0)
	var pave_item := -1
	for i in god._road_pick.item_count:
		if str(god._road_pick.get_item_metadata(i)) == "pavement":
			pave_item = i
	god._road_pick.select(pave_item)
	god._road_pick.item_selected.emit(pave_item)
	var pave_tool: String = god.tool
	god.press(cam.unproject_position(far_pave))
	god.release()
	god.set_tool("sidewalk")
	god.press(cam.unproject_position(far_side))
	god.release()
	await _shot("60_god_pavement.png")
	var meadow_has: bool = regions.ground_mats.size() > 0 and regions.ground_mats.all(func(m): return (m as ShaderMaterial).get_shader_parameter("roads") == god.road_tex)
	var both: bool = god.road_at(far_pave.x, far_pave.z) == "pavement" and god.road_at(far_side.x, far_side.z) == "sidewalk"
	var side_tiles: bool = god._cell_cobbled(Vector2i(((Vector2(far_side.x, far_side.z) - god.TILE_ORIGIN) / god.TILE).floor()))
	god.undo()
	_check("god mode: the road dropdown's pavement and sidewalk paint out in the east meadows, on the lands' ground too, and Undo takes the sidewalk back (tool %s, %s, after Undo %s, cobble tiles laid on the sidewalk %s)" % [pave_tool, "pavement and sidewalk" if both else "missing", god.road_at(far_side.x, far_side.z), side_tiles],
		pave_tool == "pavement" and both and meadow_has and not side_tiles and god.road_at(far_side.x, far_side.z) == "" and god.road_at(far_pave.x, far_pave.z) == "pavement")
	god.undo()

	# Bretton Oaks' cul-de-sac is on the road map, its meshes hidden, and "Grass" rubs it out
	# (Alex, 2026-11-17: "can't delete original cul-de-sac pavement", "add grass as a god mode painting option")
	if suburb != null:
		var cds: Vector3 = suburb.centre
		var meshes_hidden: bool = get_tree().get_nodes_in_group("suburb_paving").size() > 0 and get_tree().get_nodes_in_group("suburb_paving").all(func(n): return not (n as Node3D).visible)
		var before: String = god.road_at(cds.x, cds.z)
		var drives: Array = suburb.paving.filter(func(sh): return str(sh["kind"]) == "sidewalk" and sh.has("quad") and float(sh["quad"][2]) > 1.0)
		var drive: Dictionary = drives[0] if not drives.is_empty() else {}
		var dmid: Vector2 = (Vector2(drive["quad"][0]) + Vector2(drive["quad"][1])) * 0.5 if not drive.is_empty() else Vector2.ZERO
		var drive_on: String = god.road_at(dmid.x, dmid.y) if not drive.is_empty() else "none"
		await _god_look(cds, 18.0)
		god.set_tool("grass")
		var grass_tool: String = god.tool
		god.press(cam.unproject_position(cds))
		god.release()
		await _shot("60_god_cul_de_sac_grass.png")
		var grassed: String = god.road_at(cds.x, cds.z)
		god.undo()
		_check("god mode: the cul-de-sac is painted pavement (driveway %s) with its own meshes hidden, and the Grass brush rubs it out and Undo brings it back (before %s, hidden %s, tool %s, after grass '%s', after Undo %s)" % [drive_on, before, meshes_hidden, grass_tool, grassed, god.road_at(cds.x, cds.z)],
			before == "pavement" and drive_on == "sidewalk" and meshes_hidden and grass_tool == "grass" and grassed == "" and god.road_at(cds.x, cds.z) == "pavement")

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

	# the furniture inside the walk-in buildings: every piece on its own, the roofs off while editing
	var furn: Dictionary = await _god_furnishing_checks()

	# Done saves the layout (to the test's own file, never data/world_layout.json)
	var real_before := FileAccess.get_file_as_string(GodMode.LAYOUT_FILE) if FileAccess.file_exists(GodMode.LAYOUT_FILE) else ""
	god.set_active(false)
	await _wait(0.3)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(GOD_TEST_LAYOUT)) if FileAccess.file_exists(GOD_TEST_LAYOUT) else null
	var real_after := FileAccess.get_file_as_string(GodMode.LAYOUT_FILE) if FileAccess.file_exists(GodMode.LAYOUT_FILE) else ""
	var saved_ok: bool = typeof(saved) == TYPE_DICTIONARY and saved["nodes"].has(lamp.key) and saved["nodes"][bale.key].get("del", false) == true \
		and (furn.is_empty() or (saved["nodes"].has(furn["piece"]) and saved["nodes"][furn["gone"]].get("del", false) == true and saved.get("added_in", []).size() == int(furn["added"]) and saved["nodes"].has(furn["msofa"]))) \
		and saved["added"].size() >= 1 and saved["scenery"].has(tree_kind) and saved["scenery"].has("rock_single") and saved["scenery"].has("bush_round") and saved.has("roads")
	_check("god mode: Done closes the editor and saves the layout (lamp, hay bale, copy, trees, rocks, bushes and roads in the file; the real layout file untouched %s)" % (real_before == real_after),
		not god.active and Game.time_running and saved_ok and real_before == real_after and hud.chrome.any(func(c): return c.visible))
	# the last step: the whole scene again, built from that layout
	Engine.set_meta("ke_god_reload", {"lamp": lamp.key, "lamp_at": lamp.xf.origin, "lamp_turn": lamp_turn, "bale": bale.key, "copy_at": copy.xf.origin,
		"tree_kind": tree_kind, "trees": god.scenery[tree_kind].filter(func(e): return not e.deleted).size(), "tree_at": tree_spot, "rocks": god.scenery["rock_single"].filter(func(e): return not e.deleted).size(), "bushes": bushes0 - 1, "lamp_size": lamp_size, "patch": patch,
		"tiles": god.painted_tiles(), "pen_at": pen.xf.origin, "spruces": spruces0 + 1, "furn": furn})
	get_tree().reload_current_scene()


## The world editor on the furniture inside the walk-in buildings (god_mode.gd _collect_furnishings):
## in the café a click picks a piece, not the building, with the roof off; a piece moves, another is
## deleted (its spot freed), one is copied beside itself and a catalogue pouf is placed in the room;
## in Marcus's house the grey couch moves on the main floor. Returns what the reload checks look for.
func _god_furnishing_checks() -> Dictionary:
	var cafe_b: GodMode.El = null
	var house_b: GodMode.El = null
	for e in god.els:
		if e.kind == "building_cafe":
			cafe_b = e
		elif suburb != null and suburb.walk_in != null and e.node == suburb.walk_in.house:
			house_b = e
	_check("god mode: the café and Marcus's house have their furniture as pieces of their own (%d in the café, %d in the house)" % [cafe_b.pieces.size() if cafe_b else 0, house_b.pieces.size() if house_b else 0],
		cafe_b != null and cafe_b.pieces.size() >= 20 and house_b != null and house_b.pieces.size() >= 15)
	if cafe_b == null or house_b == null:
		return {}
	var blocking: Array = cafe_b.pieces.filter(func(e): return not e.block_world.is_empty())
	var piece: GodMode.El = blocking[0]
	var gone_el: GodMode.El = blocking[1]
	await _god_look(piece.xf.origin, 9.0)
	await _wait(0.3)
	var roof_off: bool = not (Interiors.shops["cafe"].parts["roof"] as Node3D).visible
	god.press(cam.unproject_position(piece.xf * piece.bounds.get_center()))
	god.release()
	var picked: GodMode.El = god.selected
	_check("god mode: in the café, with its roof off (%s), a click picks up a piece of furniture, not the building (%s)" % [roof_off, picked.title if picked else "nothing"],
		roof_off and picked != null and picked.inside == cafe_b)
	var from := piece.xf
	var block0: Rect2 = piece.block_world[0]
	var step: Vector3 = cafe_b.xf.basis.x.normalized() * 0.5
	piece.xf.origin += step
	god._edited(piece, from, false)
	god.select(gone_el)
	var gone_rect: Rect2 = gone_el.block_world[0]
	god.delete_selected()
	god.select(piece)
	var copy: GodMode.El = god.duplicate_selected()
	god.place_id = "decor:pouf"
	god.set_tool("place")
	var pouf: GodMode.El = god.place(cafe_b.xf * Vector3(0.0, 0, 0.5))
	god.set_tool("select")
	var moved_ok: bool = piece.node.global_position.distance_to(from.origin + step) < 0.001 and (piece.block_world[0] as Rect2).get_center().distance_to(block0.get_center() + Vector2(step.x, step.z)) < 0.01 \
		and grid_blockers.has(piece.block_world[0]) and not grid_blockers.has(block0)
	_check("god mode: a café piece moves with its obstacle (%s), another is deleted and its spot freed (%s), a copy stands beside it in the same room (%s) and a pouf placed in the café joins its furnishings (%s)" % [moved_ok, not grid_blockers.has(gone_rect), copy != null and copy.inside == cafe_b, pouf != null and pouf.inside == cafe_b],
		moved_ok and gone_el.deleted and not gone_el.node.visible and not grid_blockers.has(gone_rect) and copy != null and copy.inside == cafe_b and copy.node.get_parent() == piece.node.get_parent()
		and pouf != null and pouf.inside == cafe_b and pouf.node.get_parent().name == "Furnishings" and grid_blockers.has(pouf.block_world[0]))
	# Marcus's grey couch, on the main floor
	var msofa: GodMode.El = null
	for e in house_b.pieces:
		if e.kind == "piece_sofa_grey":
			msofa = e
	var mfrom := msofa.xf
	var mstep: Vector3 = house_b.xf.basis.z.normalized() * -0.4
	msofa.xf.origin += mstep
	god._edited(msofa, mfrom, false)
	await _god_look(msofa.xf.origin, 12.0)
	await _wait(0.3)
	_check("god mode: in Marcus's house the roof is off and the grey couch moves on the main floor (%.2f m)" % msofa.node.global_position.distance_to(mfrom.origin),
		not (suburb.walk_in.parts["roof"] as Node3D).visible and msofa.node.global_position.distance_to(mfrom.origin + mstep) < 0.001 and (suburb.walk_in.roots["main"] as Node3D).visible)
	await _shot("61_god_furnishings.png")
	return {"piece": piece.key, "piece_at": piece.xf.origin, "gone": gone_el.key, "added": 2, "msofa": msofa.key, "msofa_at": msofa.xf.origin}


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
	var furn: Dictionary = want["furn"]
	if not furn.is_empty():
		var piece: GodMode.El = god.by_key.get(furn["piece"])
		var gone: GodMode.El = god.by_key.get(furn["gone"])
		var msofa: GodMode.El = god.by_key.get(furn["msofa"])
		var added_in: Array = god.els.filter(func(e): return e.added and e.inside != null and not e.deleted)
		_check("saved layout: the café's moved piece, its deleted one, the two added inside and Marcus's moved couch are all as they were left (piece %.2f m off, deleted gone %s, %d added, couch %.2f m off)" % [
			piece.node.global_position.distance_to(furn["piece_at"]) if piece else -1.0, gone != null and not gone.node.visible, added_in.size(), msofa.node.global_position.distance_to(furn["msofa_at"]) if msofa else -1.0],
			piece != null and piece.node.global_position.distance_to(furn["piece_at"]) < 0.01 and gone != null and not gone.node.visible and added_in.size() == int(furn["added"])
			and msofa != null and msofa.node.global_position.distance_to(furn["msofa_at"]) < 0.01)
	cam_follow = false
	await _god_look(Vector3(17.0, 0, 7.0), 24.0)
	await _shot("62_god_reloaded.png")
	await _god_look(Vector3(31.0, 0, 12.0), 22.0)
	await _shot("63_god_line_and_placed.png")
	print("AUTOTEST DONE")
	get_tree().quit()


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
	knit.open({"auto": false, "fast": 0.0, "silent": true, "best": {"cast_on": 3}}) # the song list
	await _shot("51_knit_select.png")
	knit._finish(true)
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
	await _shot("51_knit_play.png")
	knit.now = float(hn["t"]) + float(hn["hold"])
	knit.release(lane)
	_check("a hold is two stitches: pressed on the beat and let go at the end (made %d then %d, holding mid-way %s, perfect %d)" % [made, knit.stitches.size(), mid_hold, knit.counts[0]],
		made == 1 and mid_hold and knit.stitches.size() == 2 and knit.counts[0] == 2 and knit.combo == 2)
	knit.now = float(hn["t"]) + float(hn["hold"]) + 3.0
	await get_tree().process_frame
	await get_tree().process_frame # the game's own _process runs after the first signal
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
## The body bones a loop moves (bone:track type), sorted. The eye bones are left out: face.gd turns them over
## whatever a loop holds, and the importer keeps a still eye's track on one model and drops it on another (Rowan's
## left eye since 2026-11-14), which made the two look unalike when they play the same loops.
func _anim_bones(a: Animation) -> Array:
	var out := []
	for i in a.get_track_count():
		var bone := str(a.track_get_path(i).get_concatenated_subnames())
		if bone in ["LeftEye", "RightEye"]:
			continue
		out.append(bone + ":" + str(a.track_get_type(i)))
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
	player.position = Vector3(9.0, 0, 8.0) # out in the yard: the checks before may leave her indoors, walls all round
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
	_check("clicked, he trots off with his stride matching his speed (%s at %.2f m/s, loop covers %.2f m/s; controlled %s, path %d, reading %s, menu %s)" % [dog.current_loop(), dog.speed, rate_trot, dog.controlled, dog.path.size() if "path" in dog else -1, _reading or books_ui.visible, hud.is_menu_open()],
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
	# he (and she) can go anywhere on the map, not just the farm, the town and the trails (Alex,
	# 2026-11-14): through the woods into the swamp's far edge, and into the woods between the lands
	var far := Vector3(-90.0, 0, -2.0)
	var woods := Vector3(-60.0, 0, -70.0) # north-west: no land, no trail
	var off_trails: bool = regions.region_at(woods.x, woods.z) == "" and not regions.trails.any(func(t): return (t as Rect2).has_point(Vector2(woods.x, woods.z)))
	var to_woods := _find_path(dog.position, woods)
	var to_far := _find_path(dog.position, far)
	hold_release() # the clicks above count as a held button in the test: let go, or it keeps steering him at the mouse
	dog.walk(to_far.duplicate()) # he uses the path up as he goes
	var tw := 0.0
	while not dog.path.is_empty() and tw < 60.0:
		await _wait(0.5)
		tw += 0.5
	var got_far := Vector2(dog.position.x - far.x, dog.position.z - far.z).length()
	await _shot("48_dog_far.png")
	_check("he can run anywhere on the map: to the swamp's far edge (%.1f m short, %.0f s) and into the woods between the lands (off the trails %s, path ends %.1f m from it)" % [got_far, tw, off_trails, (to_woods[-1] as Vector3).distance_to(woods) if not to_woods.is_empty() else -1.0],
		not to_far.is_empty() and got_far < 2.0 and off_trails and not to_woods.is_empty() and (to_woods[-1] as Vector3).distance_to(woods) < 1.5)
	dog.position = player.position + Vector3(1.2, 0, 0.8)
	cam_target = dog.position
	autotest_jog = false
	var herding_played: bool = homestead.herders.has(dog)
	await _key_tap(KEY_TAB)
	_check("Tab again gives the clicks back to Nora", not dog.controlled)
	await _wait(5.0)
	_check("off the lead he comes back to her side (%.1f m away)" % dog.position.distance_to(player.position),
		dog.position.distance_to(player.position) < 2.6)
	_check("he herds only while you play him: the strays shy from him then, further off than from her, and not once he's back at her side (played %s, now %s)" % [herding_played, homestead.herders.has(dog)],
		herding_played and not homestead.herders.has(dog) and dog.scare_radius() > Homestead.HERD_RADIUS)
	cam_dist = cd0


## A walkable spot about `r` metres from `at` (for the autotest to stand her near something).
func _open_near(at: Vector3, r: float) -> Vector3:
	for i in 24:
		var a := TAU * i / 24.0
		var p := at + Vector3(cos(a), 0.0, sin(a)) * r
		if _walkable(_cell(p)) and not _find_path(p, at).is_empty():
			return p
	return at + Vector3(r, 0, 0)


## Where the tall scenery stands (trees and anything else over 1.6 m scattered as MultiMeshes), for
## the autotest to keep its pictures clear of canopies.
func _tall_scenery() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := c as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var h := mmi.multimesh.mesh.get_aabb().size.y
		for i in mmi.multimesh.instance_count:
			var t := mmi.global_transform * mmi.multimesh.get_instance_transform(i)
			if h * t.basis.get_scale().y >= 1.6:
				out.append(t.origin)
	return out


## How far (up to 8 m) from `at` the nearest tall scenery or blocked cell is (for the autotest to
## pick something in the open to photograph). With `toward` (the flat way to the camera), the
## ground 3 and 6 m that way counts too, so no canopy stands between.
func _openness(at: Vector3, tall: PackedVector3Array, toward := Vector3.ZERO) -> float:
	if toward != Vector3.ZERO:
		return minf(_openness(at, tall), minf(_openness(at + toward * 3.0, tall), _openness(at + toward * 6.0, tall)))
	var best := 8.0
	for p in tall:
		best = minf(best, Vector2(p.x - at.x, p.z - at.z).length())
	var n := int(minf(best, 6.0) / CELL)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var d := Vector2(i, j).length() * CELL
			if d < best and not _walkable(_cell(at + Vector3(i * CELL, 0.0, j * CELL))):
				best = d
	return best


## The most open walkable spot within 12 m of `at` (the autotest stands an animal there for its
## picture when every one of its kind is under the trees).
func _clear_spot(at: Vector3, tall: PackedVector3Array, toward := Vector3.ZERO) -> Vector3:
	var best := at
	var score := _openness(at, tall, toward)
	for r in [2.0, 4.0, 6.0, 9.0, 12.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := at + Vector3(cos(a), 0.0, sin(a)) * float(r)
			if not _walkable(_cell(p)):
				continue
			var s := _openness(p, tall, toward)
			if s > score + 0.5:
				score = s
				best = p
	return best


## The wild animals and birds (scripts/wildlife.gd, data/wildlife.json): every species' model and
## loops; the rarer the tier, the fewer and the further out, with sheep the commonest; combing one
## for its fibre and its coat growing back; bolting when she runs at it; birds flying off as she
## walks up and settling elsewhere; knitting with a fibre lifting the sweater to its floor; shipping.
func _wildlife_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	Game.energy = maxf(Game.energy, 80.0)
	var jog0 := autotest_jog
	autotest_jog = false # she walks up: a run would send them off
	player.walk([])
	var cd0 := cam_dist
	_set_cam_lock(false) # the camera stays on what the check looks at, not on her
	wildlife.build()
	await _wait(0.6)
	var by := {}
	for a in wildlife.animals:
		if not by.has(a.species):
			by[a.species] = []
		by[a.species].append(a)
	var bad := []
	for id in by:
		if not by[id][0].ok():
			bad.append(id)
	_check("every wild animal has its model and loops (%d species; without: %s)" % [by.size(), str(bad)], by.size() == 10 and bad.is_empty())
	var bare := by.keys().filter(func(id): return not by[id][0].shorn_ok())
	_check("every wild animal has its shorn model with its loops too (without: %s)" % str(bare), by.size() == 10 and bare.is_empty())
	var farm := Vector3(10.0, 0, -3.0)
	var n := [0, 0, 0, 0, 0]
	var far := [0.0, 0.0, 0.0, 0.0, 0.0]
	for a in wildlife.animals:
		var r: int = wildlife.tier_rank(a.tier())
		n[r] += 1
		far[r] += Vector2(a.position.x - farm.x, a.position.z - farm.z).length()
	var fewer := true
	var further := true
	for i in 5:
		far[i] = far[i] / maxf(1.0, float(n[i]))
		if i > 0:
			fewer = fewer and n[i] < n[i - 1]
			further = further and far[i] > far[i - 1]
	_check("the rarer the tier, the fewer the animals (%s) and the further from the farm (%s m)" % [str(n), str(far.map(func(x): return int(x)))],
		n.min() > 0 and fewer and further)
	var most := 0
	for id in by:
		if id != "sheep":
			most = maxi(most, by[id].size())
	_check("sheep are the commonest animal (%d wild, %d in the pen; next %d)" % [by.get("sheep", []).size(), sheep_list.size(), most], by.get("sheep", []).size() > most)
	_check("every animal stands on open ground in its habitat", wildlife.animals.all(func(a): return _walkable(_cell(a.position)) and a._at_home(a.position)))
	# combing a rabbit
	var rab = by["rabbit"][0]
	player.position = _open_near(rab.position, 3.0)
	cam_target = rab.position
	cam_dist = 5.0
	await _wait(0.4)
	var acts: Array = _actions_for(rab)
	_check("clicking a rabbit holds it still and offers to comb it (%s)" % str(acts[0]["label"]), acts[0]["id"] == "comb" and acts[0]["enabled"])
	var a0 := Game.count("angora")
	_do_action(rab, "comb")
	var tw := 0.0
	while (not player.path.is_empty() or player.busy or Game.count("angora") == a0) and tw < 10.0:
		await _wait(0.25)
		tw += 0.25
	_check("she walks up and combs it: +1 %s (%d -> %d)" % [wildlife.item_name("angora"), a0, Game.count("angora")], Game.count("angora") == a0 + 1)
	cam_target = (player.position + rab.position) * 0.5
	await _wait(0.3)
	await _shot("59_wild_comb.png")
	acts = _actions_for(rab)
	_check("its coat needs time to grow back (%s), and it shows its shorn model (%s)" % [str(acts[0].get("hint", "")), rab.coat()],
		not rab.has_fur() and not acts[0]["enabled"] and rab.coat() == "shorn")
	var wild: Dictionary = (Game.flag("wild", {}) as Dictionary).duplicate()
	wild[rab.key] = Game.day - 1
	Game.set_flag("wild", wild)
	tw = 0.0
	while rab.coat() != "furry" and tw < 4.0: # it looks at its coat every couple of seconds
		await _wait(0.25)
		tw += 0.25
	_check("a day later its coat has grown back and its furry model shows again (%s)" % rab.coat(), rab.has_fur() and rab.coat() == "furry")
	# running at a fox
	var fox = by["fox"][0]
	player.position = _open_near(fox.position, 9.0)
	fox.hold(0.0)
	await _wait(0.2)
	cam_target = fox.position
	cam_dist = 9.0
	autotest_jog = true # as if Shift were held: she runs at it
	player.walk(_find_path(player.position, fox.position))
	tw = 0.0
	while fox.fleeing <= 0.0 and tw < 8.0:
		await _wait(0.1)
		tw += 0.1
	await _wait(0.7)
	var stride := float((fox.info["stride"] as Dictionary).get(fox.current_loop(), 1.0))
	_check("running at a fox, it bolts (%s at %.1f m/s, loop covers %.1f m/s)" % [fox.current_loop(), fox.speed, fox.loop_rate() * stride],
		fox.fleeing > 0.0 and fox.current_loop() == "Run" and absf(fox.loop_rate() * stride - fox.speed) < 0.4)
	cam_target = fox.position
	await _shot("59_wild_flee.png")
	autotest_jog = false
	player.walk([])
	# a lynx at the camera: let it stand for its picture, and the rest of the rarer ones
	var tall := _tall_scenery()
	var back: Vector3 = cam.global_position - cam_target # the flat way to the camera
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3(0, 0, 1)
	for id in ["sheep", "rabbit", "fox", "raccoon", "beaver", "mink", "coyote", "sable", "lynx", "chinchilla"]:
		var a = by[id][0]
		for b in by[id]: # the one standing most in the open, so no canopy hides it from the camera
			if _openness(b.position, tall, back) > _openness(a.position, tall, back):
				a = b
		if _openness(a.position, tall, back) < 4.0: # all of them under the trees: it steps out for its picture
			a.position = _clear_spot(a.position, tall, back)
		a.hold(4.0)
		player.position = _open_near(a.position, 6.0) # out of the picture, and too far for it to turn to her
		cam_target = a.position + Vector3(0, 0.15, 0)
		cam_dist = 3.2 if id in ["rabbit", "mink", "sable", "chinchilla"] else 4.5
		await _wait(0.4)
		var to: Vector3 = cam.global_position - a.global_position
		a.rotation.y = atan2(to.x, to.z) + 0.7 # three-quarters on to the camera
		await _wait(0.4)
		await _shot("59_wild_%s.png" % id)
		var coats: Dictionary = (Game.flag("wild", {}) as Dictionary).duplicate() # and shorn, as it is after a comb
		coats[a.key] = Game.day
		Game.set_flag("wild", coats)
		a._show_coat()
		a.hold(4.0)
		await _wait(0.3)
		await _shot("59_shorn_%s.png" % id)
		coats.erase(a.key)
		Game.set_flag("wild", coats)
		a._show_coat()
	cam_dist = cd0
	# walking up to sparrows
	var fl = null
	for f in wildlife.flocks:
		if f.kind == "sparrow" and (fl == null or _openness(f.global_position, tall, back) > _openness(fl.global_position, tall, back)):
			fl = f
	player.position = _open_near(fl.global_position, 10.0) # (a flock already up is heading here: its spot moves with it)
	var tl := 0.0
	while fl.flying and tl < 15.0: # one she put up while posing for the pictures above lands first
		await _wait(0.25)
		tl += 0.25
	cam_target = (fl.global_position + player.position) * 0.5
	cam_dist = 12.0
	await _wait(1.2)
	_check("the sparrows peck about on the ground", not fl.flying and fl.in_air() == 0)
	player.walk(_find_path(player.position, fl.global_position))
	tw = 0.0
	while fl.flushes == 0 and tw < 10.0:
		await _wait(0.1)
		tw += 0.1
	await _wait(0.5)
	_check("walking up to them, the sparrows fly off (%d of %d in the air)" % [fl.in_air(), fl.birds.size()], fl.flushes > 0 and fl.in_air() > 0)
	var up := Vector3.ZERO # frame the birds in the air, not her
	var ups := 0
	for b in fl.birds:
		if b["air"]:
			up += (b["node"] as Node3D).global_position
			ups += 1
	cam_target = up / maxf(1.0, ups) if ups > 0 else player.position
	cam_dist = 9.0
	await _wait(0.3)
	await _shot("59_birds_flush.png")
	player.walk([])
	tw = 0.0
	while fl.flying and tw < 15.0:
		await _wait(0.25)
		tw += 0.25
	_check("they settle again in their zone, somewhere else (%.0f s)" % tw, not fl.flying and fl.zone.grow(2.0).has_point(Vector2(fl.position.x, fl.position.z)))
	cam_dist = cd0
	autotest_jog = jog0
	# knitting with a wild fibre, and shipping it
	var keep := {"q": Game.worn_quality, "d": Game.worn_design, "w": Game.wardrobe.duplicate(), "s": Game.sweaters.duplicate(),
		"sd": Game.sweater_designs.duplicate(), "xp": Game.knit_xp, "c": Game.coins, "wool": Game.count("wool")}
	Game.add_item("wool", 2)
	Game.add_item("lynx_fibre", 1)
	var rows := wildlife.knit_rows()
	_check("with a wild fibre in her bag the chair offers to knit with it (%s)" % (str(rows[0]["label"]) if not rows.is_empty() else "none"),
		rows.any(func(r): return r["id"] == "knit_fibre:lynx_fibre" and r["enabled"]))
	_knit_fibre = "lynx_fibre"
	var s0 := Game.sweaters.size()
	_finish_knit(1)
	var got: int = Game.sweaters[-1] if Game.sweaters.size() > s0 else 0
	_check("knitting with lynx fluff, a Common knit comes out at least %s (%s), from 2 wool and the fluff" % [KnitGame.rarity_name(wildlife.knit_floor("lynx_fibre")), KnitGame.rarity_name(got)],
		got >= wildlife.knit_floor("lynx_fibre") and Game.count("wool") == keep["wool"] and Game.count("lynx_fibre") == 0)
	Game.add_item("fox_fibre", 2)
	var c0 := Game.coins
	var ship_ids: Array = ship_rows().map(func(a): return str(a["id"]))
	_ship("ship_fibre")
	_check("wild fibre can't be sold, only knitted (mailbox rows %s, coins +%d, fibre kept %d)" % [str(ship_ids), Game.coins - c0, Game.count("fox_fibre")],
		ship_ids == ["ship_sweater"] and Game.coins == c0 and Game.count("fox_fibre") == 2)
	Game.take_item("fox_fibre", 2)
	Game.worn_quality = keep["q"]
	Game.worn_design = keep["d"]
	Game.wardrobe = keep["w"]
	Game.sweaters = keep["s"]
	Game.sweater_designs = keep["sd"]
	Game.knit_xp = keep["xp"]
	Game.coins = keep["c"]
	Game.take_item("angora", Game.count("angora"))
	Game.set_flag("wild", {})
	# out of sight, out of mind
	player.position = Vector3(9.0, 0, 8.0)
	cam_target = player.position
	_set_cam_lock(true)
	await _wait(0.6)
	var shown: int = wildlife.animals.filter(func(a): return a.visible).size()
	_check("animals far from her and the camera are hidden and still (%d of %d shown from the yard)" % [shown, wildlife.animals.size()],
		shown < wildlife.animals.size() and not by["chinchilla"][0].visible and by["chinchilla"][0].process_mode == Node.PROCESS_MODE_DISABLED)
	wildlife.clear()


## Sweaters are the economy (Alex, 2026-11-15): the mailbox and Rosa buy nothing but sweaters, jobs
## pay petty cash; anyone in town may be looking for a sweater, some days not; she sets a price and
## a meter shows how likely they are to say yes; too dear and they turn it down or come back with
## their own; three refusals and they walk away; a job's drop goes in her bag, or is a piece of
## furniture she places for nothing. Saves 61_sale_haggle.png.
func _sale_checks() -> void:
	var day0 := Game.day
	var flags0: Dictionary = Game.flags.duplicate(true)
	var coins_start := Game.coins
	var inv0: Dictionary = Game.inv.duplicate(true)
	var sw0: Array = Game.sweaters.duplicate()
	var sd0: Array = Game.sweater_designs.duplicate()
	var friends0: Dictionary = Game.friends.duplicate(true)
	hud.hide_dialogue()
	Game.add_item("turnip", 3)
	Game.add_item("wool", 3)
	var ship_ids: Array = ship_rows().map(func(a): return str(a["id"]))
	var rosa_ids: Array = _villager_actions(_villager("rosa")).map(func(a): return str(a["id"]))
	var pays: Array = Jobs.defs().values().map(func(d): return int(d["pay"]))
	_check("only sweaters earn money: the mailbox ships %s, Rosa's menu has no crops to buy (%s), and a job pays petty cash (%s)" % [str(ship_ids), str(rosa_ids.has("sell_crops")), str(pays)],
		ship_ids == ["ship_sweater"] and not rosa_ids.has("sell_crops") and rosa_ids.has("sell_sweater") and pays.all(func(p): return p <= 15))
	# some days they're not looking
	var wren := _villager("wren")
	Game.friend("wren")["familiarity"] = 0
	Game.set_flag("npc_sweater_day", {})
	Game.add_sweater(1, "")
	Game.add_sweater(3, "")
	var no_day := -1
	var yes_day := -1
	for d in range(day0, day0 + 60):
		Game.day = d
		if no_day < 0 and not SweaterSale.looking("wren"):
			no_day = d
		if yes_day < 0 and SweaterSale.looking("wren"):
			yes_day = d
	Game.day = no_day
	var ask_row: Array = sale.rows_for(wren)
	_villager_action(wren, "sale_ask")
	var after_no: Array = sale.rows_for(wren)
	_check("asked on a day she isn't looking, Wren says no and the panel stays shut ('%s' -> '%s', panel %s, %d%% chance)" % [str(ask_row[0]["label"]) if not ask_row.is_empty() else "?", str(after_no[0]["label"]) if not after_no.is_empty() else "?", sale.visible, int(SweaterSale.yes_chance("wren") * 100)],
		not ask_row.is_empty() and ask_row[0]["id"] == "sale_ask" and not after_no.is_empty() and not after_no[0]["enabled"] and not sale.visible)
	hud.hide_dialogue()
	# a day she is: the panel, the meter, and haggling
	Game.day = yes_day
	_villager_action(wren, "sale_ask")
	await _wait(0.4)
	var rare := Game.sweaters.find(3)
	sale.pick(rare)
	var fair := sale.fair(3)
	var res := sale.reserve("wren", 3)
	var at_fair := sale.chance("wren", 3, fair)
	sale.set_price(int(res * 1.1))
	await _wait(0.3)
	await _shot("61_sale_haggle.png")
	var at_dear := sale.chance("wren", 3, int(fair * 2))
	_check("on a day she's looking, the panel opens on her best sweater at Rosa's price, and the meter falls as the price rises (open %s, fair %dc: %d%%, her top %dc, at %dc: %d%%)" % [sale.visible, fair, int(at_fair * 100), res, int(fair * 2), int(at_dear * 100)],
		sale.visible and at_fair > at_dear and at_fair > 0.3 and at_dear < 0.2 and absf(sale.chance("wren", 3, res) - 0.5) < 0.01)
	sale.force_roll = 0.99 # whatever the meter says, this one is turned down
	sale.set_price(int(res * 3))
	var r1 := sale.offer()
	sale.set_price(int(res * 1.15))
	var r2 := sale.offer()
	var countered := sale.counter
	var c0 := Game.coins
	var n0 := Game.sweaters.size()
	sale.take_counter()
	sale.force_roll = -1.0
	hud.hide_dialogue()
	_check("far too dear she turns it down ('%s'); a little dear and she names her own price ('%s', %dc under her %dc); taking it sells the Rare (+%dc, bag %d -> %d, panel %s, '%s')" % [r1, r2, countered, res, Game.coins - c0, n0, Game.sweaters.size(), sale.visible, str(sale.rows_for(wren)[0]["label"]) if not sale.rows_for(wren).is_empty() else "-"],
		r1 == "no" and r2 == "counter" and countered > 0 and countered < int(res * 1.15) and Game.coins - c0 == countered and Game.sweaters.size() == n0 - 1 and not Game.sweaters.has(3) and not sale.visible and SweaterSale.bought_today("wren"))
	# three refusals and they walk away for the day
	var stv := _villager("steve")
	var asked: Dictionary = (Game.flag("sweater_asked", {}) as Dictionary).duplicate()
	asked["steve"] = {"day": Game.day, "yes": true, "tries": 0}
	Game.set_flag("sweater_asked", asked)
	_villager_action(stv, "sale_haggle")
	sale.force_roll = 0.99
	var outs := []
	for i in 3:
		sale.set_price(sale.fair(1) * 4)
		outs.append(sale.offer())
	sale.force_roll = -1.0
	hud.hide_dialogue()
	var done_row: Array = sale.rows_for(stv)
	_check("turned down three times, Steve walks away for the day (%s, panel %s, '%s')" % [str(outs), sale.visible, str(done_row[0]["label"]) if not done_row.is_empty() else "?"],
		outs[-1] == "gone" and not sale.visible and not done_row.is_empty() and not done_row[0]["enabled"])
	# a job's drop
	Game.flags.erase("given")
	var w0 := Game.count("wool")
	var got_wool := Jobs.drop(0.0) # the first in the table: wool
	var table: Array = Data.economy()["jobs"]["loot"]
	var total := 0.0
	var before := 0.0
	for e in table:
		total += float(e["weight"])
	for e in table:
		if e.has("piece"):
			break
		before += float(e["weight"])
	var got_piece := Jobs.drop((before + 0.5) / total)
	var piece: String = (Game.flag("given", {}) as Dictionary).keys()[0] if not (Game.flag("given", {}) as Dictionary).is_empty() else ""
	var label := Catalog.price_text(piece) if piece != "" else ""
	var coins1 := Game.coins
	var paid := _pay_for(piece) if piece != "" else false
	_check("a job drops wool ('%s', +%d) or a piece for the house ('%s': the catalogue says '%s', placing it costs nothing: %s, coins %d -> %d, left %d)" % [got_wool, Game.count("wool") - w0, got_piece, label, paid, coins1, Game.coins, Catalog.given(piece)],
		Game.count("wool") > w0 and piece != "" and label.begins_with("Yours") and paid and Game.coins == coins1 and Catalog.given(piece) == 0)
	Game.flags = flags0
	Game.day = day0
	Game.coins = coins_start
	Game.inv = inv0
	Game.sweaters = sw0
	Game.sweater_designs = sd0
	Game.friends = friends0


## The knitting empire's loop (Alex, 2026-11-15; docs/DIRECTION.md): a day is 20 real minutes, 14 of
## day and 6 of night; the darkest night still has light to see by; Steve's lantern lights itself
## after dark; Rosa's better needles lift every knit; played as the dog, a right click barks, a bark fills
## a wild animal's fright meter and it bolts, at full fright it follows him, three at most, and he
## leads them home to a pen that holds four; she combs them there, a second pen makes room, the dog
## can be sent from Nora's side, and another animal turns up in the wild later; a local asks for a
## sweater of a wild fibre, the one she knits is put by for them, and handing it over pays.
## Saves 60_night_new_moon.png, 60_night_woods.png, 60_night_lantern.png, 60_bark.png,
## 60_round_up.png and 60_penned.png.
func _empire_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	var SB := Lighting.SkyBodies
	var keep := {"flags": Game.flags.duplicate(true), "coins": Game.coins, "inv": Game.inv.duplicate(true), "day": Game.day, "hour": Game.hour,
		"q": Game.worn_quality, "d": Game.worn_design, "w": Game.wardrobe.duplicate(), "s": Game.sweaters.duplicate(),
		"sd": Game.sweater_designs.duplicate(), "xp": Game.knit_xp, "jog": autotest_jog, "cd": cam_dist, "ph": SB.phase_override, "cl": SB.clouds_override}
	var friends0: Dictionary = Game.friends.duplicate(true)
	player.walk([])
	autotest_jog = false
	# the clock: 14 minutes of day and 6 of night (the rest of the autotest runs on the old fast one)
	Game.fast_clock = false
	var day_s := 0.0
	var night_s := 0.0
	for i in 240:
		var h := i * 0.1 + 0.05
		if h >= Game.DAY_START and h < Game.DAY_END:
			day_s += Game.hour_seconds(h) * 0.1
		else:
			night_s += Game.hour_seconds(h) * 0.1
	Game.hour = 12.0
	var h0 := Game.hour
	await _wait(2.0)
	var moved := (Game.hour - h0) * Game.hour_seconds(12.0)
	Game.fast_clock = true
	_check("a day is 20 real minutes: %.0f s of daytime (6:00 to 20:00) and %.0f s of night; two seconds move the clock two seconds on (%.1f)" % [day_s, night_s, moved],
		absf(day_s - 840.0) < 1.0 and absf(night_s - 360.0) < 1.0 and absf(moved - 2.0) < 0.4)
	# the darkest night: no moon, 1 a.m.
	SB.phase_override = 0.0
	SB.clouds_override = 0.1
	Game.hour = 1.0
	player.position = Vector3(9.0, 0, 8.0)
	if dog:
		dog.position = player.position + Vector3(1.2, 0, 0.8)
	cam_dist = 20.0
	cam_target = player.position
	_set_cam_lock(true)
	await _wait(0.8)
	var dark_sun := sun.light_energy
	var dark_fill := env.ambient_light_energy
	await _shot("60_night_new_moon.png")
	var lum_farm := _screen_brightness()
	player.position = Vector3(-52.0, 0, -8.0) # in the swamp's trees
	if dog:
		dog.position = player.position + Vector3(1.2, 0, 0.8)
	cam_target = player.position
	await _wait(0.8)
	await _shot("60_night_woods.png")
	var lum_woods := _screen_brightness()
	_check("the darkest night (no moon, 1 a.m.) still has light to see by: moonlight %.2f, fill %.2f, the picture's brightness %.2f on the farm and %.2f in the swamp" % [dark_sun, dark_fill, lum_farm, lum_woods],
		dark_sun > 0.5 and dark_fill > 1.0 and lum_farm > 0.2 and lum_woods > 0.13)
	# the lantern
	var steve := _villager("steve")
	Game.coins = 5000
	var lrow: Array = _villager_actions(steve).filter(func(a): return a["id"] == "buy_lantern")
	_villager_action(steve, "buy_lantern")
	hud.hide_dialogue()
	await _wait(0.5)
	var lit_night: bool = empire.lantern_lit()
	await _shot("60_night_lantern.png")
	var lum_lantern := _screen_brightness()
	# in her left hand, hanging from its ring
	var lantern_node := get_node_or_null("Lantern") as Node3D
	var in_hand: bool = empire.lantern_in_hand() and lantern_node != null
	var hand_gap := 9.0
	var hangs := 0.0
	if in_hand:
		var lsk: Skeleton3D = player.body.skeleton
		var wrist: Vector3 = lsk.global_transform * lsk.get_bone_global_pose(lsk.find_bone("LeftHand")).origin
		hand_gap = lantern_node.global_position.distance_to(wrist)
		hangs = lantern_node.global_transform.basis.y.dot(Vector3.UP)
	var cd_l := cam_dist
	cam_dist = 4.2
	await _wait(0.6)
	await _shot("60_lantern_hand.png")
	cam_dist = cd_l
	_check("after dark the lantern hangs from her left hand (in hand %s, %.2f m from her wrist, upright %.2f)" % [in_hand, hand_gap, hangs], in_hand and hand_gap < 0.2 and hangs > 0.9)
	Game.hour = 12.0
	await _wait(0.4)
	_check("Steve sells a lantern (%s, %d left): it lights itself in the dark (%s, the picture %.2f against %.2f without) and is out by day (%s)" % [str(lrow[0]["label"]) if not lrow.is_empty() else "no row", Game.coins, lit_night, lum_lantern, lum_woods, empire.lantern_lit()],
		not lrow.is_empty() and Game.coins == 5000 - empire.lantern_price() and Game.has_item("lantern") and lit_night and lum_lantern > lum_woods * 1.15 and not empire.lantern_lit())
	SB.phase_override = keep["ph"]
	SB.clouds_override = keep["cl"]
	# needles
	var rosa := _villager("rosa")
	Game.flags.erase("needles")
	var floor0: int = empire.needle_floor()
	var nrow: Array = _villager_actions(rosa).filter(func(a): return a["id"] == "buy_needles")
	var c0 := Game.coins
	_villager_action(rosa, "buy_needles")
	hud.hide_dialogue()
	Game.add_item("wool", 3)
	var s0 := Game.sweaters.size()
	_knit_fibre = ""
	_finish_knit(1)
	var got: int = Game.sweaters[-1] if Game.sweaters.size() > s0 else 0
	_check("Rosa sells better needles a step at a time (%s): with Gran's a knit can be Common (floor %d), with steel a Common knit comes out %s (-%dc)" % [str(nrow[0]["label"]) if not nrow.is_empty() else "no row", floor0, KnitGame.rarity_name(got), c0 - Game.coins],
		not nrow.is_empty() and floor0 == 1 and str(Game.flag("needles", "")) == "steel" and got == 2 and c0 - Game.coins == 150)
	# catching: play the dog and bark; a frightened animal follows him home to a pen
	Game.flags.erase("penned")
	Game.flags.erase("wild_gone")
	Game.flags.erase("wild")
	wildlife.build()
	await _wait(0.5)
	var rabbits: Array = wildlife.animals.filter(func(a): return a.species == "rabbit" and not a.penned)
	var sheep0 := Game.sheep_count
	Game.sheep_count = 1 # room for three in the one pen
	_check("a pen holds four animals, sheep included (%d pen, %d places, %d left with one sheep), and there are wild rabbits to catch (%d)" % [wildlife.pens().size(), wildlife.pen_capacity() - (4 if wildlife.stalls_rented() else 0), wildlife.pen_room(), rabbits.size()],
		wildlife.pens().size() == 1 and wildlife.pen_capacity() - (4 if wildlife.stalls_rented() else 0) == 4 and rabbits.size() >= 4)
	if rabbits.size() < 4:
		wildlife.clear()
		Game.sheep_count = sheep0
		return
	var rabbit = rabbits[0]
	var key0 := ""
	# four rabbits in a field by the farm, the dog among them
	var field := Vector3(-6.0, 0, 22.0)
	for i in 4:
		rabbits[i].position = field + Vector3([2.5, -2.5, 0.0, 6.5][i], 0, [0.0, 1.0, -2.5, 5.0][i])
		rabbits[i].hold(30.0)
	player.position = field + Vector3(0, 0, 9.0)
	dog.position = field
	dog.path = []
	cam_target = field
	cam_dist = 17.0
	_set_cam_lock(false)
	toggle_dog(true)
	hud.hide_dialogue()
	await _wait(0.5)
	var barks0: int = dog.barks
	var fm0 = rabbit.get_node_or_null("Fright")
	var waiting: bool = fm0 != null and fm0.visible and rabbit.fright <= 0.0 # the empty meter, up as soon as he is near
	await _key_tap(Keys.key_for(KEY_SPACE, ["world"])) # Space is the camera's again: no bark
	await _wait(0.1)
	var space_barks: int = dog.barks - barks0
	_right_click(get_viewport().get_visible_rect().size * 0.5)
	await _wait(0.1)
	var fright1: float = rabbit.fright
	var bolted: bool = rabbit.fleeing > 0.0
	var meter: bool = rabbit.get_node_or_null("Fright") != null and rabbit.get_node("Fright").visible
	var word: String = (rabbit.get_node("Fright/Word") as Label3D).text if meter else ""
	await _shot("60_bark.png")
	_check("as the dog, a right click barks (%d bark) and Space doesn't (%d): the rabbit's meter was up, empty, as he came near (%s); it takes fright (meter %.2f, shown %s, it says '%s') and bolts (%s), and he can't bark again at once (%s)" % [dog.barks - barks0, space_barks, waiting, fright1, meter, word, bolted, not dog_bark()],
		dog.barks - barks0 == 1 and space_barks == 0 and waiting and fright1 > 0.3 and fright1 < 1.0 and meter and word == "Fright" and bolted)
	# he keeps after them, barking: up to three give in and follow him
	var tw := 0.0
	while wildlife.following().size() < 3 and tw < 45.0:
		var near = null
		var best := INF
		for a in rabbits.slice(0, 4):
			var d: float = a.position.distance_to(dog.position)
			if not a.caught and d < best:
				best = d
				near = a
		if near != null:
			dog.running = true
			if best > 2.5:
				dog.walk(_find_path(dog.position, near.position))
			dog_bark()
		await _wait(0.25)
		tw += 0.25
		cam_target = dog.position
	dog.running = false
	var herd: Array = wildlife.following()
	var gave_in := "" # what the full meter says over the one that has just given in
	for a in herd:
		var fm = a.get_node_or_null("Fright")
		if fm != null and fm.visible:
			gave_in = (fm.get_node("Word") as Label3D).text
	if not herd.is_empty():
		key0 = herd[0].key # its place in the wild, before the pen gives it a new key
	var fourth = null
	for a in rabbits.slice(0, 4):
		if not a.caught:
			fourth = a
	var f4 := 0.0
	Game.sheep_count = 0 # a place free in the pen, so it's the herd's size that stops a fourth
	if fourth != null: # a fourth won't join: three is all he can herd
		f4 = fourth.fright
		dog.position = fourth.position + Vector3(1.5, 0, 0)
		dog.path = []
		for i in 4:
			await _wait(BARK_WAIT)
			dog_bark()
	_check("barking fills their meters and three give in and follow him (%d after %.1f s; the full meter says '%s'); a fourth only bolts (caught %s, fright %.2f -> %.2f, '%s')" % [herd.size(), tw, gave_in, fourth.caught if fourth != null else true, f4, fourth.fright if fourth != null else -1.0, wildlife.round_up_problem(fourth) if fourth != null else "?"],
		herd.size() == 3 and gave_in == "Following!" and fourth != null and not fourth.caught and fourth.fright <= f4 + 0.001 and wildlife.round_up_problem(fourth).contains("3 at a time"))
	Game.sheep_count = 1
	# home: he runs back to the pen and they follow him in
	var pen: Rect2 = wildlife.pen()
	var gate := Vector3(pen.get_center().x, 0, pen.end.y + 9.0)
	for off in [Vector3(0, 0, pen.size.y * 0.5 + 9.0), Vector3(pen.size.x * 0.5 + 9.0, 0, 0), Vector3(-pen.size.x * 0.5 - 9.0, 0, 0), Vector3(0, 0, -pen.size.y * 0.5 - 9.0)]:
		var c: Vector3 = Vector3(pen.get_center().x, 0, pen.get_center().y) + (off as Vector3)
		if _walkable(_cell(c)):
			gate = c
			break
	dog.position = gate
	dog.path = []
	for i in herd.size():
		herd[i].position = gate + Vector3(1.2 + i, 0, 1.0)
	cam_target = dog.position
	_set_cam_lock(true)
	await _wait(0.3)
	var shot_home := false
	dog.walk(_find_path(dog.position, Vector3(pen.get_center().x, 0, pen.get_center().y)))
	tw = 0.0
	var followed := 0.0
	var p_was: Vector3 = herd[0].position if not herd.is_empty() else Vector3.ZERO
	while wildlife.penned().size() < 3 and tw < 40.0:
		await _wait(0.2)
		tw += 0.2
		if not herd.is_empty():
			followed += herd[0].position.distance_to(p_was)
			p_was = herd[0].position
		if not shot_home and tw > 1.0:
			shot_home = true
			await _shot("60_round_up.png")
	dog.walk([])
	toggle_dog(false)
	hud.hide_dialogue()
	player.position = gate
	cam_target = Vector3(pen.get_center().x, 0, pen.get_center().y)
	_set_cam_lock(false)
	cam_dist = 13.0
	await _wait(0.8)
	await _shot("60_penned.png")
	var inside: int = wildlife.penned().filter(func(a): return pen.grow(0.3).has_point(Vector2(a.position.x, a.position.z))).size()
	_check("they follow him home (%.1f m on their own legs) and move into the pen (%d penned, %d inside it, %d on her list); with her one sheep the pen is full (%d places left, Rosa: %s)" % [followed, wildlife.penned().size(), inside, wildlife.penned_list().size(), wildlife.pen_room(), str(_villager_actions(rosa).filter(func(a): return str(a["label"]).begins_with("Buy a sheep")).map(func(a): return a["label"]))],
		wildlife.penned().size() == 3 and inside == 3 and followed > 2.0 and wildlife.penned_list().size() == 3 and (Game.flag("wild_gone", {}) as Dictionary).has(key0)
		and (wildlife.pen_room() == 0 or wildlife.stalls_rented()))
	rabbit = wildlife.penned()[0] if not wildlife.penned().is_empty() else rabbit
	var a0 := Game.count("angora")
	var rows_pen: Array = rabbit.ke_actions()
	wildlife.combed(rabbit)
	dog_bark()
	_check("in the pen she combs one (+%d angora), a bark doesn't trouble it (fleeing %.1f, fright %.2f), and its menu lets it go (%s)" % [Game.count("angora") - a0, rabbit.fleeing, rabbit.fright, str(rows_pen.map(func(a): return a["id"]))],
		Game.count("angora") == a0 + 1 and rabbit.fleeing <= 0.0 and rabbit.fright <= 0.0 and rows_pen.any(func(a): return a["id"] == "free") and not rows_pen.any(func(a): return a["id"] == "round_up"))
	_check("combed in the pen, it shows its shorn model (%s)" % rabbit.coat(), rabbit.coat() == "shorn")
	# a second pen makes room for four more; the caught ones spread over the pens
	var pens0: Array = homestead.pens.duplicate()
	var second := Rect2(pen.position + Vector2(pen.size.x + 4.0, 0.0), Vector2(3.0, 3.0))
	homestead.pens = [pen, second]
	var cap2: int = wildlife.pen_capacity() - (4 if wildlife.stalls_rented() else 0)
	Game.sheep_count = 2 # two sheep in the first pen: one caught rabbit has to move to the second
	wildlife._assign_pens()
	var in_second: int = wildlife.penned().filter(func(a): return second.grow(0.3).has_point(Vector2(a.position.x, a.position.z))).size()
	_check("another pen makes room for four more (%d places with two pens), and her animals spread over them (%d of 3 moved to the second with two sheep in the first)" % [cap2, in_second],
		cap2 == 8 and in_second == 1)
	homestead.pens = pens0
	Game.sheep_count = 1
	wildlife._assign_pens()
	# only the player herds: from Nora's side there's no sending him, and beside her he frightens nothing
	var wild_one = null
	for a in rabbits:
		if is_instance_valid(a) and not a.caught and not a.penned:
			wild_one = a
			break
	wildlife.set_free(wildlife.penned()[0])
	hud.hide_dialogue()
	if dog.controlled:
		toggle_dog(false)
	player.position = field + Vector3(0, 0, 2.0)
	dog.position = field + Vector3(1.0, 0, 1.0)
	dog.path = []
	wild_one.position = field
	wild_one.fright = 0.0
	wild_one.hold(5.0)
	cam_target = field
	await _wait(2.0)
	var rows_wild: Array = wild_one.ke_actions().map(func(a): return a["id"])
	_check("only the player herds: a wild one's menu has no 'send the dog' (%s), and with him beside her it isn't frightened or caught (fright %.2f, caught %s)" % [str(rows_wild), wild_one.fright, wild_one.caught],
		not rows_wild.has("round_up") and wild_one.fright <= 0.0 and not wild_one.caught)
	# its place in the wild stays empty for a while, then another turns up; the pens survive a rebuild
	var wild_now: Array = wildlife.animals.filter(func(a): return a.key == key0)
	Game.day += 5
	wildlife.restock()
	var wild_later: Array = wildlife.animals.filter(func(a): return a.key == key0 and not a.penned)
	wildlife.build()
	await _wait(0.4)
	var again: Array = wildlife.penned()
	_check("another rabbit turns up in its place after a few days (%d there before, %d after); the penned ones are back after a reload (%d, all rabbits %s)" % [wild_now.size(), wild_later.size(), again.size(), again.all(func(a): return a.species == "rabbit")],
		wild_now.is_empty() and wild_later.size() == 1 and again.size() == 2 and again.all(func(a): return a.species == "rabbit"))
	wildlife.clear()
	Game.sheep_count = sheep0
	# a local's request: nobody asks until they like her; then Steve wants a better-than-plain one
	Game.flags.erase("request")
	Game.flags.erase("requests_done")
	Game.flags.erase("requests_filled")
	Game.flags.erase("request_day")
	var req_friends0: Dictionary = Game.friends.duplicate(true)
	for vid in Game.friends:
		Game.friends[vid]["familiarity"] = 0
	var cold: Dictionary = empire.due()
	Game.friend("steve")["familiarity"] = 20 # one heart
	var warm: Dictionary = empire.due()
	var stv := _villager("steve")
	_villager_action(stv, "request_ask")
	hud.hide_dialogue()
	var want_row: Array = _villager_actions(stv).filter(func(a): return str(a.get("group", "")) == "Request")
	Game.add_sweater(1, "")
	Game.add_sweater(3, "")
	var n_sw := Game.sweaters.size()
	var give1: Array = _villager_actions(stv).filter(func(a): return a["id"] == "request_give")
	c0 = Game.coins
	var pay1: int = empire.payout()
	_villager_action(stv, "request_give")
	hud.hide_dialogue()
	_check("nobody asks for a sweater until they like her (%s); at a heart Steve asks for an Uncommon or better ('%s', row '%s'), and the plainest in her bag that will do pays %dc (+%d, bag %d -> %d, Common kept %s)" % [str(cold.get("id", "none")), str(warm.get("id", "")), str(want_row[0]["label"]) if not want_row.is_empty() else "?", pay1, Game.coins - c0, n_sw, Game.sweaters.size(), Game.sweaters.has(1)],
		cold.is_empty() and str(warm.get("id", "")) == "steve_warm" and not give1.is_empty() and pay1 >= 140 and Game.coins - c0 == pay1 and Game.sweaters.size() == n_sw - 1 and Game.sweaters.has(1) and empire.filled() == ["steve_warm"])
	Game.remove_sweater(Game.sweaters.find(1))
	# Sabrina wants angora, once she likes her (the plain-wool ones before it filled)
	Game.set_flag("requests_filled", ["steve_warm", "wren_first", "barbara_rain", "giorgio_good"])
	Game.set_flag("requests_done", 0)
	Game.flags.erase("request_day")
	Game.friend("sabrina")["familiarity"] = 40
	Game.friend("steve")["familiarity"] = 0 # his thanks brought him to two hearts: his fox request would come next
	var sab := _villager("sabrina")
	var due: Dictionary = empire.due()
	var ask_rows: Array = _villager_actions(sab).filter(func(a): return a["id"] == "request_ask")
	_villager_action(sab, "request_ask")
	hud.hide_dialogue()
	var goal1 := str(Game.flag("goal", ""))
	Game.add_item("wool", 2)
	Game.add_item("angora", 1)
	s0 = Game.sweaters.size()
	_knit_fibre = "angora"
	_finish_knit(1)
	var made := int(empire.request().get("made", 0))
	var goal2 := str(Game.flag("goal", ""))
	var give_rows: Array = _villager_actions(sab).filter(func(a): return a["id"] == "request_give")
	c0 = Game.coins
	var pay: int = empire.payout()
	_villager_action(sab, "request_give")
	hud.hide_dialogue()
	_check("Sabrina asks for an angora sweater (due %s/%s, she glows %s, row %d): the goal sends her for a rabbit ('%s'), the one she knits with angora is put by (grade %d, bag %d -> %d, '%s'), and handing it over pays %dc (+%d)" % [str(due.get("who", "")), str(due.get("fibre", "")), not ask_rows.is_empty(), ask_rows.size(), goal1, made, s0, Game.sweaters.size(), goal2, pay, Game.coins - c0],
		str(due.get("who", "")) == "sabrina" and not ask_rows.is_empty() and goal1.contains("rabbit") and made >= 2 and Game.sweaters.size() == s0 and goal2.contains("Sabrina")
		and not give_rows.is_empty() and pay >= 180 and Game.coins - c0 == pay and empire.request().is_empty() and empire.filled().has("sabrina_angora"))
	var soon: Dictionary = empire.due()
	Game.day += 2
	var not_yet: Dictionary = empire.due()
	Game.friend("barbara")["familiarity"] = 40
	var next: Dictionary = empire.due()
	_check("the next local asks a couple of days later, once they like her (none the same day: %s; Barbara at no hearts: %s; at two she wants %s)" % [soon.is_empty(), str(not_yet.get("id", "nobody")), str(next.get("fibre", ""))],
		soon.is_empty() and not_yet.is_empty() and str(next.get("id", "")) == "barbara_raccoon")
	Game.friends = req_friends0
	# Rosa has only so much wool a day
	Game.flags.erase("wool_bought")
	Game.coins = 1000
	var w0 := Game.count("wool")
	var packs: int = int(_store().get("wool_packs_a_day", 2))
	for i in packs + 1:
		_villager_action(rosa, "buy_wool")
		hud.hide_dialogue()
	var sold_out: Array = _villager_actions(rosa).filter(func(a): return str(a["label"]).begins_with("Buy 3 wool"))
	var got_wool := Game.count("wool") - w0
	Game.day += 1
	_check("Rosa sells %d packs of wool a day and no more (+%d wool from %d tries, then '%s'); there's more tomorrow (%d left)" % [packs, got_wool, packs + 1, str(sold_out[0]["label"]) if not sold_out.is_empty() else "?", _wool_packs_left()],
		got_wool == packs * 3 and not sold_out.is_empty() and not sold_out[0]["enabled"] and _wool_packs_left() == packs)
	# back as it was
	Game.flags = keep["flags"]
	Game.friends = friends0
	Game.coins = keep["coins"]
	Game.inv = keep["inv"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	Game.worn_quality = keep["q"]
	Game.worn_design = keep["d"]
	Game.wardrobe = keep["w"]
	Game.sweaters = keep["s"]
	Game.sweater_designs = keep["sd"]
	Game.knit_xp = keep["xp"]
	Game.sync_slots()
	autotest_jog = keep["jog"]
	cam_dist = keep["cd"]
	player.position = Vector3(9.0, 0, 8.0)
	if dog:
		dog.position = player.position + Vector3(1.2, 0, 0.8)
	cam_target = player.position
	_set_cam_lock(true)
	_show_goal()
	await _wait(0.3)


const BARK_WAIT := 0.65 # a little longer than the dog needs between barks (Dog.BARK_EVERY)


## How bright the picture on screen is, 0..1 (the mean of its pixels' luminance), for the night checks.
func _screen_brightness() -> float:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return 0.0
	img.resize(64, 40, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y).get_luminance()
	return sum / float(img.get_width() * img.get_height())


## The knitted sweaters: fifty designs; Nora's wardrobe (what she knits hangs there, she picks what
## she wears, or her city coat); villagers wear a sweater only once they buy one from her.
func _sweater_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var ds := Sweaters.designs()
	var by := [0, 0, 0, 0]
	for d in ds:
		by[clampi(int(d["stars"]), 1, 4) - 1] += 1
	_check("fifty sweater designs, 20 common, 15 rare, 10 ultra rare and 5 legendary (%s)" % str(by), ds.size() == 50 and by == [20, 15, 10, 5])
	_check("every design has its colour map", ds.all(func(d): return ResourceLoader.exists(Sweaters.TEX + str(d["id"]) + ".png")))
	var keep := {"q": Game.worn_quality, "d": Game.worn_design, "w": Game.wardrobe.duplicate(), "s": Game.sweaters.duplicate(),
		"sd": Game.sweater_designs.duplicate(), "n": Game.count("sweater"), "c": Game.coins,
		"bought": Game.flag("npc_sweaters", {}), "days": Game.flag("npc_sweater_day", {})}
	# her wardrobe
	Game.wear("")
	await _wait(0.2)
	_check("in her city coat she wears no knitted sweater", Sweaters.worn(player.body) == "")
	var xp0 := Game.knit_xp
	var q := Game.knit_sweater(4)
	var knitted: String = str(Game.sweater_designs[-1])
	_check("a sweater she knits has a design of its stars, one like it hangs in her wardrobe and she puts it on (%s, %s)" % [knitted, Game.worn_design],
		Sweaters.stars_for(q) == int(Sweaters.design(knitted).get("stars", 0)) and Game.wardrobe.has(knitted) and Game.worn_design == knitted)
	Game.knit_xp = xp0
	Game.wardrobe = {"flock": 4, "cranberry": 2, "northern_lights": 5, "snowfall_yoke": 3}
	Game.wear("flock")
	await _wait(0.2)
	var sw := player.body.skeleton.get_node_or_null(Sweaters.NODE) as MeshInstance3D
	_check("she wears the sweater from her wardrobe, on her own skeleton (%s)" % Sweaters.worn(player.body),
		Sweaters.worn(player.body) == "flock" and sw != null and sw.visible and sw.skin != null)
	var tuck_on := Sweaters._body_meshes(player.body).any(func(m): return m.find_blend_shape_by_name(Sweaters.KEY) >= 0 and m.get_blend_shape_value(m.find_blend_shape_by_name(Sweaters.KEY)) > 0.99)
	_check("the skin under it is tucked in (%d points)" % Sweaters.tucked_points(player.body), Sweaters.tucked_points(player.body) > 1000 and tuck_on)
	var aabb := sw.get_aabb() if sw else AABB()
	_check("the sweater is her size (%.2f m tall, %.2f m wide)" % [aabb.size.y, aabb.size.x], aabb.size.y > 0.5 and aabb.size.y < 1.0 and aabb.size.x > 0.4 and aabb.size.x < 1.3)
	if _wardrobe_piece():
		_check("the wardrobe in her house offers her sweaters", _actions_for(_wardrobe_piece()).any(func(a): return a["id"] == "wardrobe"))
	wardrobe_ui.open()
	await _wait(0.2)
	var rows := wardrobe_ui._list.get_children()
	_check("the wardrobe lists her city coat and her four sweaters, best first (%d rows)" % rows.size(),
		rows.size() == 5 and str(rows[1].get_meta("design")) == "northern_lights" and str(rows[0].get_meta("design")) == "")
	var picked := str(rows[3].get_meta("design")) # rows: the coat, then Northern Lights, Flock, Snowfall Yoke, Cranberry
	(rows[3] as Button).pressed.emit()
	await _wait(0.3)
	_check("picking one there puts it on (%s, warmth from %s)" % [Game.worn_design, Game.stars(Game.worn_quality)], Game.worn_design == picked and Sweaters.worn(player.body) == Game.worn_design and Game.worn_quality == int(Game.wardrobe[Game.worn_design]))
	await _shot("55_wardrobe.png")
	(wardrobe_ui._list.get_child(0) as Button).pressed.emit()
	await _wait(0.2)
	_check("and the city coat takes it off", Game.worn_design == "" and Game.worn_quality == 1 and Sweaters.worn(player.body) == "")
	wardrobe_ui.close()
	Game.wear("flock")
	var cam2 := Camera3D.new()
	add_child(cam2)
	cam2.fov = 30.0
	var fwd: Vector3 = player.body.global_transform.basis.z.normalized()
	var mid := player.global_position + Vector3(0, 1.05, 0)
	cam2.global_position = mid + fwd.rotated(Vector3.UP, 0.35) * 3.4 + Vector3(0, 0.25, 0)
	cam2.look_at(mid, Vector3.UP)
	cam2.current = true
	for id in ["flock", "cranberry", "northern_lights"]:
		Game.wear(id)
		await _wait(0.3)
		await _shot("55_sweater_%s.png" % id)
	cam2.global_position = mid - fwd.rotated(Vector3.UP, 0.35) * 3.4 + Vector3(0, 0.25, 0)
	cam2.look_at(mid, Vector3.UP)
	await _wait(0.2)
	await _shot("55_sweater_back.png")
	player.body.play("Walk", 1.0)
	cam2.global_position = mid + fwd.rotated(Vector3.UP, 1.2) * 3.4 + Vector3(0, 0.25, 0)
	cam2.look_at(mid, Vector3.UP)
	await _wait(0.6)
	await _shot("55_sweater_walk.png")
	player.body.play("Idle")
	# the villagers: none wears one until they buy it from her
	Game.set_flag("npc_sweaters", {})
	Game.set_flag("npc_sweater_day", {})
	await _wait(0.2)
	var dressed := villagers.filter(func(v): return v.body != null and Sweaters.worn(v.body) != "")
	_check("no villager wears a sweater she didn't sell them (%d do)" % dressed.size(), dressed.is_empty())
	var fitted := villagers.filter(func(v): return v.body != null and Sweaters.fits(v.vid))
	_check("the villagers with models have sweaters fitted to them (%s)" % ", ".join(fitted.map(func(v): return v.vid)), fitted.size() >= 6)
	for pair in [["steve", "snowfall_yoke", 3], ["barbara", "oatmeal_stripe", 1]]:
		var v := _villager(pair[0])
		if v == null or v.body == null:
			_check("%s is in town to buy a sweater" % pair[0], false)
			continue
		Game.add_sweater(int(pair[2]), str(pair[1]))
		# they're looking today (the haggle itself is _sale_checks'), and say yes to the fair price
		var asked: Dictionary = (Game.flag("sweater_asked", {}) as Dictionary).duplicate()
		asked[v.vid] = {"day": Game.day, "yes": true, "tries": 0}
		Game.set_flag("sweater_asked", asked)
		var offer: Array = _villager_actions(v).filter(func(a): return str(a["id"]) == "sale_haggle")
		var coins0 := Game.coins
		var n0 := Game.count("sweater")
		if not offer.is_empty():
			_villager_action(v, "sale_haggle")
			sale.pick(Game.sweater_designs.find(str(pair[1])))
			sale.force_roll = 0.0
			sale.offer()
			sale.force_roll = -1.0
		await _wait(0.3)
		_check("%s buys %s from her and puts it on (offered %d, coins %d→%d, sweaters %d→%d, wearing '%s', %d points tucked)" % [pair[0], pair[1], offer.size(), coins0, Game.coins, n0, Game.count("sweater"), Sweaters.worn(v.body), Sweaters.tucked_points(v.body)],
			offer.size() == 1 and Game.coins > coins0 and Game.count("sweater") == n0 - 1 and Sweaters.worn(v.body) == pair[1] and Sweaters.tucked_points(v.body) > 1000)
		_check("%s buys only one a day" % pair[0], _villager_actions(v).filter(func(a): return str(a["id"]).begins_with("sale_")).is_empty() or Game.count("sweater") == 0)
		hud.hide_dialogue()
		var vf: Vector3 = v.body.global_transform.basis.z.normalized()
		var vm := v.global_position + Vector3(0, 1.05, 0)
		cam2.global_position = vm + vf * 3.4 + Vector3(0, 0.25, 0)
		cam2.look_at(vm, Vector3.UP)
		await _wait(0.4)
		await _shot("55_sweater_%s.png" % pair[0])
	for vid in ["rowan", "wren", "gary", "giorgio", "sabrina", "rosa", "lars"]:
		var v := _villager(vid)
		if v == null or v.body == null or not Sweaters.fits(vid):
			continue
		var home := v.global_position
		v.global_position = player.global_position + Vector3(3, 0, 3) # out in the open, for the picture
		var dress: Dictionary = Game.flag("npc_sweaters", {})
		dress[vid] = "grans_heirloom" # as if she'd sold them one; _update_sweater dresses them from this
		Game.set_flag("npc_sweaters", dress)
		var vf: Vector3 = v.body.global_transform.basis.z.normalized()
		var vm := v.global_position + Vector3(0, 1.05, 0)
		cam2.global_position = vm + vf * 3.4 + Vector3(0, 0.25, 0)
		cam2.look_at(vm, Vector3.UP)
		await _wait(0.4)
		await _shot("55_fit_%s.png" % vid)
		_check("%s's sweater fits (wearing '%s', %d points tucked)" % [vid, Sweaters.worn(v.body), Sweaters.tucked_points(v.body)], Sweaters.worn(v.body) == "grans_heirloom" and Sweaters.tucked_points(v.body) > 1000)
		dress.erase(vid)
		Game.set_flag("npc_sweaters", dress)
		await _wait(0.1)
		v.global_position = home
	cam2.queue_free()
	Game.set_flag("npc_sweaters", keep["bought"])
	Game.set_flag("npc_sweater_day", keep["days"])
	Game.wardrobe = keep["w"]
	Game.worn_quality = keep["q"]
	Game.worn_design = keep["d"]
	Game.sweaters = keep["s"]
	Game.sweater_designs = keep["sd"]
	Game.inv["sweater"] = keep["n"]
	Game.coins = keep["c"]
	await _wait(0.2)


## The wardrobe from her eyes (wardrobe_view.gd): "Choose a sweater…" opens its doors in first person,
## every sweater in her wardrobe hangs on its own hanger in its own design (the one she has on leaves
## an empty hanger), Right and Left browse with her arm reaching in and the hangers sliding and
## swinging, a click or Enter puts one on, X her city coat, Esc closes, and the camera she had comes back.
func _wardrobe_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var keep := {"q": Game.worn_quality, "d": Game.worn_design, "w": Game.wardrobe.duplicate()}
	Game.wardrobe = {"flock": 4, "cranberry": 1, "northern_lights": 5, "snowfall_yoke": 3, "oatmeal_stripe": 2, "forest": 1}
	Game.wear("cranberry")
	var w = _wardrobe_piece()
	var made: bool = w == null
	if made:
		w = _spawn_furniture("wardrobe", Vector3(7.5, 0, 3.0), 3)
	var dl := w.find_child("door_l", true, false) as Node3D
	var dr := w.find_child("door_r", true, false) as Node3D
	_check("the wardrobe model has its two doors as parts of their own, on their hinges (%s, %s)" % [dl != null, dr != null],
		dl != null and dr != null and dl.position.x < -0.4 and dr.position.x > 0.4)
	_check("the wardrobe offers 'Choose a sweater…'", _actions_for(w).any(func(a): return a["id"] == "wardrobe"))
	var cam0 := {"yaw": cam_yaw, "dist": cam_dist}
	player.position = _stand_point(w)
	await _wait(0.3)
	_perform(w, "wardrobe")
	await _wardrobe_settle(true)
	var opened: float = rad_to_deg(absf(dl.rotation.y)) if dl else 0.0
	_check("it opens from her eyes: first person, locked, the doors swung open (%.0f deg), %d hangers" % [opened, wview.hangers.size()],
		wview.active and fps.active and fps.locked and opened > 90.0 and wview.hangers.size() == 6)
	var designs := {}
	var own := true
	for h in wview.hangers:
		designs[h["design"]] = true
		own = own and (h["sweater"] as MeshInstance3D).material_override == Sweaters.material(str(h["design"]))
	var worn_h: Array = wview.hangers.filter(func(h): return h["design"] == "cranberry")
	_check("every sweater hangs on its own hanger in its own design, and the one she has on leaves an empty hanger",
		designs.size() == 6 and own and worn_h.size() == 1 and not (worn_h[0]["sweater"] as MeshInstance3D).visible
		and wview.hangers.filter(func(h): return (h["sweater"] as MeshInstance3D).visible).size() == 5)
	var sw0 := wview.hangers[wview.focus]["sweater"] as MeshInstance3D
	var box: AABB = (wview._model.global_transform.affine_inverse() * sw0.global_transform) * sw0.get_aabb() # in the wardrobe's own frame
	var rail_y: float = WardrobeView.RAIL_Y
	_check("the hung sweater is a sweater's size and hangs under the rail (%.2f wide, %.2f tall, top %.2f m under it)" % [box.size.x, box.size.y, rail_y - box.end.y],
		box.size.x > 0.4 and box.size.x < 0.8 and box.size.y > 0.4 and box.size.y < 0.8 and rail_y - box.end.y > 0.0 and rail_y - box.end.y < 0.15)
	var front_rect := wview.screen_rect(wview.focus)
	var vp := get_viewport().get_visible_rect()
	var shown: float = front_rect.intersection(vp).get_area() / maxf(front_rect.get_area(), 1.0)
	_check("the one in front is in the middle of the view, %.0f%% of it on screen (%s)" % [shown * 100.0, str(front_rect)],
		front_rect.has_area() and shown > 0.85 and absf(front_rect.get_center().x - vp.get_center().x) < vp.size.x * 0.08
		and front_rect.has_point(vp.get_center()) and front_rect.size.y < vp.size.y)
	await _shot("57_wardrobe_open.png")
	var f0: int = wview.focus
	await _key_tap(KEY_RIGHT)
	var swing_max := 0.0 # the biggest swing on any hanger as they slide
	var st := 0.0
	while st < 0.35:
		await get_tree().process_frame
		st += get_process_delta_time()
		for h in wview.hangers:
			swing_max = maxf(swing_max, absf(float(h["roll"])))
	var reach_w: float = wview.reach.weight if wview.reach else 0.0
	var gap: float = wview.reach.hand_gap if wview.reach else 9.0
	var swinging: bool = swing_max > 0.01
	_check("Right browses: the next one comes to the middle, her right arm reaches in for it (weight %.2f, hand %.2f m off) and the hangers swing" % [reach_w, gap],
		wview.focus == f0 + 1 and reach_w > 0.6 and wview.reach.side == 1 and swinging)
	await _shot("57_wardrobe_reach.png")
	await _wait(1.4)
	var settled := true
	for i in wview.hangers.size():
		settled = settled and absf(float(wview.hangers[i]["x"]) - wview._target_x(i)) < 0.01
	_check("then the hangers settle on the rail and her arm drops (weight %.2f)" % wview.reach.weight, settled and wview.reach.weight < 0.05)
	await _key_tap(KEY_LEFT)
	await _wait(0.3)
	_check("Left browses back with her left arm", wview.focus == f0 and wview.reach.side == -1 and wview.reach.weight > 0.6)
	await _wait(1.4)
	# a click on one at the side
	var j := -1
	for i in wview.hangers.size():
		if i != wview.focus and wview.hangers[i]["design"] != Game.worn_design and wview.screen_rect(i).has_area():
			j = i
			break
	var want: String = str(wview.hangers[j]["design"]) if j >= 0 else ""
	if j >= 0:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = wview.screen_rect(j).get_center()
		_check("a click there finds that sweater (%s)" % want, wview.hanger_at(ev.position) == j)
		wview.handle_mouse(ev)
	await _wait(0.3)
	await _shot("57_wardrobe_pick.png")
	await _wardrobe_settle(false)
	_check("a click on a sweater puts it on (%s, on her %s), the doors shut and the camera she had is back" % [Game.worn_design, Sweaters.worn(player.body)],
		want != "" and Game.worn_design == want and Sweaters.worn(player.body) == want and not wview.active and not fps.active
		and absf(rad_to_deg(dl.rotation.y)) < 1.0 and is_equal_approx(cam_dist, float(cam0["dist"])) and is_equal_approx(cam_yaw, float(cam0["yaw"])))
	# Enter on the one in front
	_perform(w, "wardrobe")
	await _wardrobe_settle(true)
	await _key_tap(KEY_RIGHT)
	await _wait(0.8)
	if str(wview.hangers[wview.focus]["design"]) == Game.worn_design:
		await _key_tap(KEY_RIGHT) # past the empty hanger of the one she has on
		await _wait(0.8)
	var front: String = str(wview.hangers[wview.focus]["design"])
	await _key_tap(KEY_ENTER)
	await _wardrobe_settle(false)
	_check("Enter puts on the one in front (%s)" % front, Game.worn_design == front and Sweaters.worn(player.body) == front and not wview.active)
	# Esc changes nothing; X is her city coat
	_perform(w, "wardrobe")
	await _wardrobe_settle(true)
	await _key_tap(KEY_RIGHT)
	await _key_tap(KEY_ESCAPE)
	await _wardrobe_settle(false)
	_check("Esc closes it without changing (%s)" % Game.worn_design, Game.worn_design == front and not wview.active and not fps.active)
	_perform(w, "wardrobe")
	await _wardrobe_settle(true)
	await _key_tap(KEY_X)
	await _wardrobe_settle(false)
	_check("X puts her back in her city coat", Game.worn_design == "" and Sweaters.worn(player.body) == "" and not wview.active)
	# from first person it comes back to first person
	Game.wear("northern_lights")
	fps.enter()
	await _wait(0.2)
	_perform(w, "wardrobe")
	await _wardrobe_settle(true)
	await _key_tap(KEY_ESCAPE)
	await _wardrobe_settle(false)
	_check("opened from first person, it goes back to first person, free to walk", fps.active and not fps.locked and not wview.active)
	fps.leave()
	await _wait(0.3)
	cam_target = player.position + Vector3(0, 0.9, 0)
	cam_dist = 4.5
	await _wait(1.2)
	await _shot("57_wardrobe_worn.png")
	Game.wardrobe = keep["w"]
	Game.worn_design = keep["d"]
	Game.worn_quality = keep["q"]
	if made:
		furniture.erase(w)
		w.queue_free()
	await _wait(0.2)


## Waits (up to six seconds) for the wardrobe view to finish opening or to have closed: its doors
## move by game frames, which a busy machine draws slowly.
func _wardrobe_settle(opened: bool) -> void:
	var t := 0.0
	while t < 6.0 and not ((wview.active and wview._door_t >= 1.0) if opened else not wview.active):
		await get_tree().process_frame
		t += get_process_delta_time()
	await _wait(0.1)


## The wardrobe piece in her house, if there is one.
func _wardrobe_piece():
	for f in furniture:
		if is_instance_valid(f) and f.item_id == "wardrobe":
			return f
	return null


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
	# coins earned pop up beside the coin chip with the cha-ching; spending them doesn't
	var pops0 := hud.coin_pops
	var chings0 := int(audio.played.get("coins", 0))
	Game.coins += 25
	await _wait(0.75) # risen, the coin's turn done
	await _shot("46_coin_pop.png")
	Game.coins -= 25
	await _wait(0.1)
	_check("coins: +25 pops up once with the cha-ching (%d pop, %d sound), spending them doesn't" % [hud.coin_pops - pops0, int(audio.played.get("coins", 0)) - chings0],
		hud.coin_pops == pops0 + 1 and int(audio.played.get("coins", 0)) == chings0 + 1 and hud.coin_chip.get_child(0).get_child(0) is TextureRect)
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
	# Settings > Key bindings: the bag moved to K opens on K and no longer on I; a clash swaps keys
	hud.open_keys()
	hud.start_binding("bag")
	await _key_tap(KEY_K)
	var on_k := Keys.bound("bag") == KEY_K
	await _shot("46_keys.png")
	await _key_tap(KEY_ESCAPE)
	var page_shut := not hud.keys_open()
	await _key_tap(KEY_I)
	var by_i := hud.bag_panel.visible
	await _key_tap(KEY_K)
	var by_k := hud.bag_panel.visible
	if by_k:
		await _key_tap(KEY_K)
	var swap_to := Keys.bind("turn_left", KEY_E)
	var swapped: bool = swap_to == "turn_right" and Keys.bound("turn_right") == KEY_Q
	Keys.reset()
	_check("key bindings: the bag rebound to K (%s) opens on K (%s), not on I (%s), Esc shuts the page (%s); turn left onto E moved turn right to Q (%s); reset" % [on_k, by_k, by_i, page_shut, swapped],
		on_k and by_k and not by_i and page_shut and swapped and Keys.bound("bag") == KEY_I and not hud.bag_panel.visible)
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
## The first half hour (Alex, 2026-11-14): a new game has only the shears, and Steve sells the rest at
## Builder's Delight with seeds and wood; the shears trim plants for leaves and the axe fells trees
## for wood, and both grow back; wooden pieces are built from her wood; Gran's seed tin, seeds
## given in talk, and planting that takes a seed.
func _early_checks() -> void:
	var energy0 := Game.energy
	Game.energy = 100.0
	story.auto = false
	hud.hide_dialogue()
	set_mode(Mode.LIVE)
	player.cancel_activity()
	# a new game: the shears and nothing else; an older save keeps all six and gets seeds to go on with
	var start_tools: Array = Game.TOOLS.filter(func(t): return Game.START_INVENTORY.has(t) or Game.START_TOOLS.has(t))
	var old: Dictionary = Game.migrate({"version": 7, "inv": {"wool": 2}})
	var kept: Array = Game.TOOLS.filter(func(t): return int(old["inv"].get(t, 0)) == 1)
	_check("early: a new game starts with only the shears (%s); a save from before keeps all six tools (%d) and gets %d turnip seeds" % [str(start_tools), kept.size(), int(old["inv"].get("turnip_seeds", 0))],
		start_tools == ["shears"] and kept.size() == 6 and int(old["inv"].get("turnip_seeds", 0)) == 6)
	# Steve sells the tools and the seeds
	for t in Game.TOOLS:
		if t != "shears":
			Game.inv.erase(t)
	Game.sync_slots()
	Game.coins = 400
	var steve := _villager("steve")
	var acts: Array = _villager_actions(steve)
	var ids: Array = acts.map(func(a): return a["id"])
	var hoe_price := int(_store()["tools"]["hoe"])
	_villager_action(steve, "buy_tool_hoe")
	var after: Array = _villager_actions(steve).filter(func(a): return str(a["label"]).begins_with("Hoe"))
	_check("early: Steve sells every tool but the shears, and seeds (%s); the hoe for %dc goes in a slot (coins %d, slot %d) and its row says she has one" % [str(ids), hoe_price, Game.coins, Game.slots.find("hoe") + 1],
		ids.has("buy_tool_hoe") and ids.has("buy_tool_axe") and not ids.has("buy_tool_shears") and ids.has("buy_seeds_turnip") and ids.has("buy_wood")
		and Game.has_item("hoe") and Game.coins == 400 - hoe_price and Game.slots.has("hoe") and after.size() == 1 and not bool(after[0]["enabled"]))
	var ts0 := Game.count("turnip_seeds")
	var pack: Array = _store()["seeds"]["turnip"]
	var c0 := Game.coins
	_villager_action(steve, "buy_seeds_turnip")
	_check("early: a packet of %d turnip seeds from Steve for %dc (seeds %d→%d)" % [int(pack[0]), int(pack[1]), ts0, Game.count("turnip_seeds")],
		Game.count("turnip_seeds") == ts0 + int(pack[0]) and Game.coins == c0 - int(pack[1]))
	_villager_action(steve, "buy_tool_axe")
	hud.hide_dialogue()
	# the shears trim a bush (or tuft) on the farm for leaves, and it grows back
	var plant = null
	var best := INF
	for el in god.els:
		if el.deleted or el.cut or not el.scenery or not el.kind.begins_with("bush_"):
			continue
		var d: float = el.xf.origin.distance_to(Vector3(9, 0, 8))
		if d < best and not Town.TOWN.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)):
			best = d
			plant = el
	if plant == null:
		_check("early: there's a bush on the farm to trim", false)
	else:
		player.position = plant.xf.origin + Vector3(0, 0, 2.2)
		_set_cam_lock(true)
		await _wait(1.2)
		var leaves0 := Game.count("leaves")
		var used := _tool_click("shears", null, cam.unproject_position(plant.xf.origin + Vector3(0, 0.4, 0)))
		await _tool_wait(func(): return Game.count("leaves") > leaves0, 30.0)
		var got := Game.count("leaves") - leaves0
		await _wait(0.4)
		await _shot("56_trimmed.png")
		var day0 := Game.day
		Game.day += int(forage.econ("plant_regrow_days", 2))
		forage.apply()
		var back: bool = not plant.cut
		Game.day = day0
		_check("early: the shears trim the bush under the click (%s) for %d leaves (it's gone: %s) and it grows back in a couple of days (%s)" % [used, got, Game.flag("cut", {}).has(Forage.key_of(plant)) or back, back],
			used and got == forage.leaves_for(plant) and back)
	# the axe fells a farm tree for wood, and it grows back
	var tree = null
	best = INF
	for el in god.els:
		if el.deleted or el.cut or not el.kind.begins_with("tree_") or forage.fell_problem(el) != "":
			continue
		var d: float = el.xf.origin.distance_to(Vector3(9, 0, 8))
		if d < best:
			best = d
			tree = el
	if tree == null:
		_check("early: there's a farm tree to fell", false)
	else:
		player.position = tree.xf.origin + Vector3(0, 0, 3.0)
		await _wait(1.2)
		var wood0 := Game.count("wood")
		var used := _tool_click("axe", null, cam.unproject_position(tree.xf.origin + Vector3(0, 0.8, 0)))
		await _tool_wait(func(): return Game.count("wood") > wood0, 45.0)
		await _wait(0.6)
		await _shot("56_felled.png")
		var felled: bool = tree.cut
		var day0 := Game.day
		Game.day += int(forage.econ("tree_regrow_days", 14))
		forage.apply()
		var back: bool = not tree.cut
		Game.day = day0
		_check("early: the axe fells the tree (%s, gone %s) for %d wood, and it grows back in a fortnight (%s)" % [used, felled, Game.count("wood") - wood0, back],
			used and felled and Game.count("wood") - wood0 == int(forage.econ("tree_wood", 8)) and back)
	# wooden pieces are built from her wood when she has enough, otherwise bought
	var bw := Catalog.wood_cost("bench")
	Game.inv["wood"] = bw + 3
	Game.coins = 1000
	var from_wood := _pay_for("bench")
	var w_left := Game.count("wood")
	var c_left := Game.coins
	var from_coins := _pay_for("bench")
	_check("early: a bench (%s) is built from %d wood when she has it (%s: wood %d, coins %d), and bought when she hasn't (%s: coins %d)" % [Catalog.price_text("bench"), bw, from_wood, w_left, c_left, from_coins, Game.coins],
		bw > 0 and from_wood and w_left == 3 and c_left == 1000 and from_coins and Game.coins == 1000 - int(Catalog.ITEMS["bench"]["price"]))
	Game.inv.erase("wood")
	Game.coins = 0
	var poor := Catalog.affordable("bench", 0, 0)
	Game.inv["wood"] = bw
	var rich := Catalog.affordable("bench", 0, bw)
	Game.inv.erase("wood")
	_check("early: with no coins, her wood alone pays for a wooden piece (none %s, %d wood %s)" % [poor, bw, rich], not poor and rich)
	# the catalogue: six rooms, every piece in one, every model there
	var tabs: Array = []
	var bad: Array = []
	for id in Catalog.INDOOR + Catalog.OUTDOOR:
		if not str(Catalog.ITEMS[id].get("cat", "")) in Catalog.CATS:
			bad.append(id)
		var m := str(Catalog.ITEMS[id].get("model", ""))
		if m != "" and not ResourceLoader.exists(m):
			bad.append(id)
	for c in Catalog.CATS:
		tabs.append("%s %d" % [c, Catalog.in_cat(c).size()])
	_check("early: Builder's Delight's catalogue has %d pieces in six rooms (%s), each with its room and model (%s)" % [(Catalog.INDOOR + Catalog.OUTDOOR).size(), ", ".join(tabs), str(bad)],
		bad.is_empty() and (Catalog.INDOOR + Catalog.OUTDOOR).size() >= 50 and Catalog.CATS.all(func(c): return Catalog.in_cat(c).size() >= 4))
	Game.coins = 500
	Game.inv["wood"] = 30
	set_mode(Mode.BUILD)
	await _wait(1.0)
	await _shot("56_catalog.png")
	set_mode(Mode.LIVE)
	Game.inv.erase("wood")
	# Gran's seed tin on the kitchen counter, on the story farm
	var was_story: bool = Game.flag("story_farm") == true
	var was_done: bool = Game.flag("act1_done") == true # the tin and the villagers' seeds wait for the end of Act 1
	Game.set_flag("act1_done")
	Game.flags.erase("seed_tin_opened")
	Game.set_flag("story_farm")
	homestead._place_seed_tin()
	var tin = homestead.seed_tin
	if tin == null:
		_check("early: Gran's seed tin is on the kitchen counter", false)
	else:
		player.position = tin.position + Vector3(0, 0, 1.2)
		player.position.y = 0.0
		cam_dist = 6.0
		await _wait(1.2)
		await _shot("56_seed_tin.png")
		var tseeds := Game.count("turnip_seeds")
		var pseeds := Game.count("pumpkin_seeds")
		var labels: Array = tin.ke_actions().map(func(a): return a["label"])
		_do_action(tin, "open_seeds")
		await _tool_wait(func(): return Game.flag("seed_tin_opened") == true, 20.0)
		await _wait(0.5)
		var note_up: bool = homestead.ui._note.visible
		await _shot("56_seed_note.png")
		homestead.ui.close_all()
		_check("early: Gran's seed tin (%s) gives %d turnip and %d pumpkin seeds, with her note (%s), and it's gone from the counter (%s)" % [str(labels), Game.count("turnip_seeds") - tseeds, Game.count("pumpkin_seeds") - pseeds, note_up, homestead.seed_tin == null],
			Game.count("turnip_seeds") - tseeds == 6 and Game.count("pumpkin_seeds") - pseeds == 2 and note_up and homestead.seed_tin == null)
	if not was_story:
		Game.flags.erase("story_farm")
	cam_dist = 11.0
	# a villager gives her seeds when they talk, once
	var toured: bool = Game.flag("act1_toured") == true
	Game.set_flag("act1_toured")
	var lars := _villager("lars") # Barbara and Giorgio offer their jobs first, once Act 1 is done
	story.auto = true # the scene plays itself through
	var bs0 := Game.count("turnip_seeds")
	_villager_action(lars, "talk")
	var playing := story.playing
	await _act1_until_done(40.0)
	hud.hide_dialogue()
	var bs1 := Game.count("turnip_seeds")
	_villager_action(lars, "talk") # once only: the next talk is an ordinary one
	var again := story.playing
	await _act1_until_done(10.0)
	story.auto = false
	hud.hide_dialogue()
	_check("early: talking to Lars, he gives her turnip seeds ('%s', %d→%d), once ('%s' the next time)" % [playing, bs0, bs1, again],
		playing == "seeds_lars" and bs1 == bs0 + 4 and again != "seeds_lars" and Game.count("turnip_seeds") == bs1)
	if not toured:
		Game.flags.erase("act1_toured")
	if not was_done:
		Game.flags.erase("act1_done")
	# planting takes a seed
	var bed = null
	for p in plots:
		if p.crop == "":
			bed = p
			break
	if bed == null:
		_check("early: an empty bed to plant", false)
	else:
		var n0 := Game.count("turnip_seeds")
		var c1 := Game.coins
		var row: Dictionary = _plant_row("turnip")
		_do_action(bed, "plant_turnip")
		await _tool_wait(func(): return bed.crop != "", 30.0)
		_check("early: planting turnips takes one of her seeds ('%s': seeds %d→%d, coins %d→%d)" % [row["label"], n0, Game.count("turnip_seeds"), c1, Game.coins],
			bed.crop == "turnip" and Game.count("turnip_seeds") == n0 - 1 and Game.coins == c1)
		Game.inv["leaves"] = 3
		var g0: float = bed.growth
		_do_action(bed, "mulch")
		await _tool_wait(func(): return not Game.has_item("leaves"), 20.0)
		await _wait(1.4)
		_check("early: three leaves mulch the growing bed and bring it on (growth %.1f→%.1f of %.0f hrs)" % [g0, bed.growth, bed.hours_needed()],
			not Game.has_item("leaves") and bed.growth >= g0 + bed.hours_needed() * 0.2)
	Game.energy = energy0
	_set_cam_lock(false)


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
	Game.give_tools() # a new game has only the shears; the rest come from Builder's Delight (_early_checks)
	Game.sync_slots()
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
	# the axe: she fells the tree for its wood, and it's gone until it grows back
	var tree = null
	best = INF
	for el in god.els:
		if not el.deleted and not el.cut and el.kind.begins_with("tree_") and forage.fell_problem(el) == "" and el.xf.origin.distance_to(player.position) < best:
			best = el.xf.origin.distance_to(player.position)
			tree = el
	var at_tree := cam.unproject_position(tree.xf.origin + Vector3(0, 0.8, 0))
	used = _tool_click("axe", null, at_tree)
	await _tool_wait(func(): return Game.count("wood") > 0, 45.0)
	var wood := Game.count("wood")
	await _wait(0.6) # the camera follows her, so the tree is somewhere else on screen now
	var again = god.pick_kind(cam.unproject_position(tree.xf.origin + Vector3(0, 0.8, 0)), "tree_")
	var tree_wood: int = forage.econ("tree_wood", 5)
	_check("axe: fells the tree under the click for %d wood (%s, wood %d), and it's gone (cut %s, picked again %s)" % [tree_wood, used, wood, tree.cut, again == tree],
		used and wood == tree_wood and tree.cut and again != tree and Game.flag("cut", {}).has(Forage.key_of(tree)))
	var town_tree = null
	for el in god.els:
		if not el.deleted and el.kind.begins_with("tree_") and Town.TOWN.has_point(Vector2(el.xf.origin.x, el.xf.origin.z)):
			town_tree = el
			break
	_check("axe: the town's trees aren't hers to fell (%s)" % (forage.fell_problem(town_tree) if town_tree else "no tree in town"),
		town_tree == null or forage.fell_problem(town_tree) != "")
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


## Cinematic mode (cinematic.gd): P frees the camera from Nora and stops the clock, it flies close
## to the ground and no higher than 300 m, F saves a photo to the album (the autotest's own folder,
## never the player's), the album lists, shows and deletes it, and Esc brings the camera back to Nora.
## Scenery fading out of the camera's way (see_through.gd): she stands just behind a tall tree as
## the camera sees it, the tree fades to see-through, and when she walks off it comes back solid.
## The town's buildings and the barn (scripts/building_skin.gd): every model's walls, frame, stone,
## trim and roof wear the house's maps in their own colours, roofs in tiled courses down the slope;
## a picture of each by day and the town at night.
func _building_skin_checks() -> void:
	var models: Array = Town.built.filter(func(e): return str(e[1]).begins_with("building_")).map(func(e): return [e[0], str(e[1]).substr(9)])
	if World.barn:
		models.append([World.barn, "barn"])
	var report: Array = []
	var all_ok := models.size() >= 7
	for e in models:
		var kinds := {}
		for mi in (e[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var o := m.get_surface_override_material(i)
				if o and o.resource_name.begins_with("skin_"):
					kinds[o.resource_name.substr(5)] = true
		var roofed := kinds.has("tiles") or kinds.has("shingles")
		all_ok = all_ok and roofed and kinds.size() >= 3
		report.append("%s: %s" % [e[1], ",".join(kinds.keys())])
	_check("every building wears the house's textures, with a tiled roof (%s)" % "; ".join(report), all_ok)
	_set_cam_lock(false)
	var yaw0 := cam_yaw
	Game.hour = 11.0
	for e in models:
		var b := e[0] as Node3D
		player.position = b.global_position + Vector3(0, 0, 14) # out of the way, so the roof stays on
		cam_target = b.global_position + Vector3(0, 1.5, 0)
		cam_dist = 17.0
		cam_yaw = b.global_rotation.y + deg_to_rad(25.0)
		cam_yaw_goal = cam_yaw
		await _wait(2.2)
		await _shot("63_building_%s.png" % e[1])
	var cafe: Array = models.filter(func(e): return e[1] == "cafe")
	if not cafe.is_empty():
		# Low graphics (no SDFGI): the café's front in the afternoon must not go black
		var b := cafe[0][0] as Node3D
		var g0 := gfx
		Game.hour = 13.5
		cam_target = b.global_position + Vector3(0, 1.5, 0)
		cam_dist = 14.0
		cam_yaw = b.global_rotation.y + deg_to_rad(-20.0)
		cam_yaw_goal = cam_yaw
		var p0 := cam_pitch
		cam_pitch = 14.0
		for lv in [0, 3]:
			gfx = lv
			apply_graphics()
			await _wait(2.5)
			await _shot("63_cafe_gfx%d.png" % lv)
		cam_pitch = p0
		gfx = g0
		apply_graphics()
	# the light bake reads from UV2 everywhere: Godot's glTF import swaps a mesh's UV sets for a
	# material whose only texture is the bake, which drew grey zebra stripes (light_bake white_base())
	var swapped: Array = []
	for e in models:
		for mi in (e[0] as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i) as BaseMaterial3D
				if mat and mat.ao_enabled and not mat.ao_on_uv2:
					swapped.append("%s:%s" % [e[1], mat.resource_name])
	_check("every building's light bake is read from UV2, none swapped by the import (%s)" % str(swapped.slice(0, 5)), swapped.is_empty())
	Game.hour = 22.0
	if not cafe.is_empty():
		var b := cafe[0][0] as Node3D
		cam_target = b.global_position + Vector3(0, 1.5, 0)
		cam_dist = 22.0
		await _wait(2.2)
		await _shot("63_town_night.png")
	cam_yaw = yaw0
	cam_yaw_goal = yaw0
	_set_cam_lock(true)


## The outside of Nora's house (scripts/house_skin.gd, art/world_assets/house_exterior): plaster,
## oak and fieldstone maps on the walls, frame, footing and the flags round it, the porch step's
## boards, the roof's cedar shingles, and the window glass (shaders/window_glass.gdshader) with the room behind it, by day,
## at dusk and at night.
func _exterior_checks() -> void:
	var skinned := {}
	for mi in get_tree().get_nodes_in_group("house_skin"):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m and m.albedo_texture:
			skinned[m.albedo_texture.resource_path.get_file().get_basename()] = true
	var panes := 0
	var holed := 0
	for w in walls:
		for c in (w["tall"] as Node3D).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override == Catalog.window_glass():
				panes += 1
		var plaster := (w["tall"] as Node3D).get_children().filter(func(c): return c is MeshInstance3D and (c as MeshInstance3D).material_override == HouseSkin.material("plaster"))
		if plaster.size() > 1:
			holed += 1
	var porch := get_tree().get_nodes_in_group("planks_floor").filter(func(f): return str(f.get_meta("shade", "")) == "porch")
	_check("the house's outside is textured: %s; %d window panes of glass in walls cut round them (%d walls), a porch step of boards (%d)" % [", ".join(skinned.keys()), panes, holed, porch.size()],
		skinned.has("plaster") and skinned.has("timber") and skinned.has("timber_h") and skinned.has("stone") and skinned.has("shingles") and skinned.has("shingles_r") and panes >= 4 and holed >= 3 and porch.size() == 1)
	var shops_glazed := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm and sm.resource_name.begins_with("glass_") and m.get_surface_override_material(i) == Catalog.window_glass():
				shops_glazed += 1
	_check("the walk-in shops' windows are the same glass (%d panes)" % shops_glazed, shops_glazed >= 4)
	# a chimney over every fireplace, and it follows one that's moved
	var fires := furniture.filter(func(f): return is_instance_valid(f) and f.item_id == "fireplace" and interior_rect().has_point(Vector2(f.position.x, f.position.z)))
	var chims := func() -> Array: return house_roof.get_children().filter(func(c): return c.name.begins_with("Chimney"))
	_update_chimneys()
	_check("a chimney stands out of the roof over each fireplace (%d fireplaces, %d chimneys)" % [fires.size(), chims.call().size()], fires.size() >= 1 and chims.call().size() == fires.size())
	if not fires.is_empty():
		var fp := fires[0] as Furniture
		var was := fp.position
		fp.position = Vector3(HOUSE_W - 0.6, 0, was.z)
		await get_tree().process_frame
		await get_tree().process_frame
		var moved: Array = chims.call()
		_check("the chimney follows the fireplace across the house", moved.size() == fires.size() and moved.any(func(c): return (c as Node3D).global_position.x > HOUSE_W * 0.5))
		fp.position = was
		await get_tree().process_frame
		await get_tree().process_frame
	_set_cam_lock(false)
	player.position = Vector3(14.0, 0, 9.0) # out in the yard, so the roof stays on
	var yaw0 := cam_yaw
	for shot in [[10.0, "62_house_day.png"], [18.6, "62_house_dusk.png"], [22.5, "62_house_night.png"]]:
		Game.hour = shot[0]
		cam_target = Vector3(8.5, 1.2, 3.2)
		cam_dist = 8.0
		cam_yaw = deg_to_rad(85.0)
		cam_yaw_goal = cam_yaw
		await _wait(2.0)
		await _shot(shot[1])
	# a window from outside, close: the room through the glass
	Game.hour = 11.0
	cam_target = Vector3(6.0, 1.4, 6.0)
	cam_dist = 8.0
	cam_yaw = deg_to_rad(10.0)
	cam_yaw_goal = cam_yaw
	await _wait(2.0)
	await _shot("62_window.png")
	# the roof from above, both slopes in the sun
	Game.hour = 12.0
	cam_target = Vector3(4.0, 2.5, 1.0)
	cam_dist = 13.0
	cam_yaw = deg_to_rad(20.0)
	cam_yaw_goal = cam_yaw
	await _wait(2.0)
	await _shot("62_roof.png")
	# the chimney, from the side of the house the fireplace backs onto
	cam_target = Vector3(0.0, 4.0, 2.0)
	cam_dist = 10.0
	cam_yaw = deg_to_rad(-70.0)
	cam_yaw_goal = cam_yaw
	await _wait(2.0)
	await _shot("62_chimney.png")
	cam_yaw = yaw0
	cam_yaw_goal = yaw0
	_set_cam_lock(true)


func _see_through_checks() -> void:
	mode = Mode.LIVE
	cam_follow = true
	cam_dist = 18.0
	cam_yaw_goal = cam_yaw
	var tree = null
	for el in god.els:
		if el.scenery and el.kind.begins_with("tree_") and not el.deleted and not el.cut and absf(el.xf.origin.x - 20.0) < 30.0 and absf(el.xf.origin.z) < 30.0:
			var box: AABB = el.xf * el.bounds
			if box.size.y > 4.0:
				tree = el
				break
	_check("there's a tall tree near the farm to stand behind", tree != null)
	if tree == null:
		return
	var away := Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * -1.0 # from the camera toward what it looks at, flat
	var spot: Vector3 = tree.xf.origin + away * 1.6
	player.walk([])
	player.position = Vector3(spot.x, 0, spot.z)
	cam_target = player.position
	await _wait(1.2)
	var f: float = see_through.fade_of(tree)
	await _shot("58_see_through.png")
	_check("a tree between the camera and her fades to see-through (%.2f)" % f, f > 0.5)
	var side := Vector3(away.z, 0, -away.x)
	player.position = tree.xf.origin + side * 14.0
	cam_target = player.position
	if dog:
		dog.position = player.position + side * 1.5
	await _wait(2.4)
	var back: Transform3D = tree.mmi.multimesh.get_instance_transform(tree.idx)
	_check("when she's clear of it the tree comes back solid, in its own place (fade %.2f, scale %.2f)" % [see_through.fade_of(tree), back.basis.get_scale().x],
		see_through.fade_of(tree) == 0.0 and back.basis.get_scale().x > 0.01)
	# deep in the woods the camera itself ends up inside a tree's crown (the swamp's far edge): that
	# tree fades too, or the screen is all leaves
	var box: AABB = (tree.xf * tree.bounds).abs()
	var pitch := deg_to_rad(cam_pitch)
	var keep_dist := cam_dist
	cam_dist = (box.position.y + box.size.y * 0.65) / sin(pitch)
	var flat := Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * cos(pitch) * cam_dist
	player.position = Vector3(tree.xf.origin.x, 0, tree.xf.origin.z) - flat
	cam_target = player.position
	if dog:
		dog.position = player.position + side * 1.5
	await _wait(1.2)
	var inside := box.has_point(cam.global_position)
	var fi: float = see_through.fade_of(tree)
	await _shot("58_see_through_inside.png")
	_check("a tree whose crown holds the camera fades too (camera inside %s, fade %.2f)" % [inside, fi], inside and fi > 0.5)
	cam_dist = keep_dist


## The minimap under the coins: where it sits, that it shows the world, a click on it walks her
## there, it zooms; and a click held down on the ground walks her the way the mouse points until
## the button comes up.
func _minimap_checks() -> void:
	var mm := hud.minimap
	_check("there is a minimap", mm != null)
	if mm == null:
		return
	_set_cam_lock(true)
	hold_release()
	player.cancel_activity()
	player.walk([])
	player.position = Vector3(4.6, 0, 4.9)
	await _wait(0.8)
	var vw := get_viewport().get_visible_rect().size
	var r := mm.get_global_rect()
	var coins := (hud.res_labels["coins"] as Control).get_global_rect()
	_check("it sits in the top right corner under the coins (map %s, coins %s, screen %s)" % [r, coins, vw],
		mm.is_visible_in_tree() and absf(r.end.x - (vw.x - 16.0)) < 2.0 and r.position.y > coins.end.y and r.size.x >= 150.0)
	var img := mm._sv.get_texture().get_image()
	var lo := 9.0
	var hi := -9.0
	for i in 64:
		var c := img.get_pixel(int(i % 8) * 31 + 8, int(i / 8) * 31 + 8)
		lo = minf(lo, c.get_luminance())
		hi = maxf(hi, c.get_luminance())
	_check("it shows the world from above, not a blank square (brightness %.2f..%.2f)" % [lo, hi], hi - lo > 0.08)
	await _shot("50_minimap.png")
	var full := get_viewport().get_texture().get_image()
	var k := float(full.get_width()) / vw.x # the HUD is laid out in its own units; the picture is in pixels
	var crop := full.get_region(Rect2i(Vector2i((r.position - Vector2(8, 60)) * k), Vector2i((r.size + Vector2(16, 68)) * k)))
	crop.save_png(_autotest_dir.path_join("50_minimap_close.png"))
	# a click on it walks her there
	var goal := Vector3(10.5, 0, 6.5)
	var m := mm.to_map(goal)
	_check("the map and the world agree (%s back to %s)" % [m, mm.to_world(m)], mm.to_world(m).distance_to(goal) < 0.05)
	_check("a click off the map does nothing", not mm.click(Vector2(-5, -5)))
	var went := mm.click(m)
	var t := 0.0
	while t < 9.0 and player.position.distance_to(goal) > 0.6:
		await _wait(0.25)
		t += 0.25
	_check("a click on the map walks her there (set off %s, %.1f m from it after %.1f s)" % [went, player.position.distance_to(goal), t],
		went and player.position.distance_to(goal) < 0.8)
	var s0 := mm.span()
	mm.set_zoom(1)
	await _wait(0.4)
	_check("it zooms out and back (%.0f m -> %.0f m across)" % [s0, mm.span()], mm.span() > s0)
	mm.set_zoom(-1)
	# held down: she walks the way the mouse points until it comes up
	player.walk([])
	player.position = Vector3(10.5, 0, 6.5) # out on the grass, clear of the house walls
	await _wait(0.6)
	var p0 := player.position
	var aim := Vector3(10.5, 0, 11.5) # 5 m south of her
	_last_mouse = cam.unproject_position(aim)
	_live_click(_last_mouse)
	await _wait(1.8)
	var gone := player.position - p0
	_check("held down on the ground, she keeps walking toward the mouse (steering %s, %.1f m south, %.1f m off to the side)" % [_hold_steering, gone.z, gone.x],
		_hold_steering and gone.z > 1.2 and absf(gone.x) < gone.z * 0.5)
	await _shot("50_hold_walk.png")
	hold_release()
	await _wait(0.3)
	var p1 := player.position
	await _wait(0.6)
	_check("let go and she stops where she is (%.2f m more, path %d)" % [player.position.distance_to(p1), player.path.size()],
		player.position.distance_to(p1) < 0.25 and player.path.is_empty())
	# a quick click still walks her all the way
	_last_mouse = cam.unproject_position(player.position + Vector3(0, 0, -3.0)) # back the way she came
	_live_click(_last_mouse)
	await _wait(0.05)
	hold_release()
	await _wait(0.5)
	_check("a quick click still sends her all the way (path %d)" % player.path.size(), not player.path.is_empty() and not _hold_steering)
	player.walk([])


func _photo_checks() -> void:
	_check("the photos go to the autotest's own folder (%s)" % Cinematic.dir, Cinematic.dir == _autotest_dir.path_join("photos"))
	for f in Cinematic.list_photos():
		Cinematic.delete_photo(f)
	cinema.last_photo = ""
	_set_cam_lock(true)
	await _wait(0.5)
	var clock0: bool = Game.time_running
	var p0 := player.position
	var hour0: float = Game.hour
	await _key_tap(KEY_P)
	await _wait(0.3)
	_check("cinematic mode: P frees the camera, hides the HUD and stops the clock (active %s, HUD %s, clock %s)" % [cinema.active, hud.visible, Game.time_running],
		cinema.active and not hud.visible and not Game.time_running)
	var c0 := cam.global_position
	await _key_tap(KEY_W, 1.0)
	await _wait(0.8)
	var moved := cam.global_position.distance_to(c0)
	_check("WASD flies it and it glides to a stop (%.1f m; still moving at %.2f m/s); Nora and the clock stay put" % [moved, cinema.vel.length()],
		moved > 2.0 and cinema.vel.length() < 0.3 and player.position.distance_to(p0) < 0.05 and Game.hour == hour0)
	# right down to the ground
	cinema.pos = Vector3(14.0, 1.5, 6.0)
	await _key_tap(KEY_Q, 1.5)
	_check("it sinks right down to the grass and no lower (%.2f m)" % cinema.pos.y, absf(cinema.pos.y - Cinematic.GROUND_CLEAR) < 0.001)
	# up to the ceiling
	cinema.pos = Vector3(42.0, 280.0, 12.0) # over the farm and the town, looking nearly straight down
	cinema.yaw_goal = 0.0
	cinema.pitch_goal = deg_to_rad(-78.0)
	cinema.key_down[KEY_SHIFT] = true
	await _key_tap(KEY_E, 2.0)
	cinema.key_down.clear()
	await _wait(0.6)
	var far := cinema.clamp_pos(Vector3(5000, 0, -5000))
	_check("Shift and E climb it to 300 m and it stops there (%.2f m, camera %.2f m); far away is clamped to the map (%s)" % [cinema.pos.y, cam.global_position.y, far],
		absf(cinema.pos.y - Cinematic.MAX_HEIGHT) < 0.001 and absf(cam.global_position.y - Cinematic.MAX_HEIGHT) < 0.01
		and far.x == Cinematic.BOUNDS.end.x and far.z == Cinematic.BOUNDS.position.y)
	await _key_tap(KEY_F)
	var t := 0.0
	while cinema.last_photo == "" and t < 8.0: # it waits two drawn frames, so the hint is off the picture
		await _wait(0.1)
		t += 0.1
	var high: String = cinema.last_photo
	var img: Image = Image.load_from_file(high) if high != "" else null
	_check("F takes a photo from up high: %s (%s)" % [high.get_file(), str(img.get_size()) if img else "missing"],
		high != "" and FileAccess.file_exists(high) and img != null and img.get_width() >= 640 and img.get_height() >= 400)
	await _shot("49_cinematic_high.png")
	# a close one: low over the farm, looking toward the house
	cinema.pos = Vector3(9.0, 1.2, 9.5)
	cinema.yaw_goal = deg_to_rad(10.0)
	cinema.pitch_goal = deg_to_rad(-6.0)
	await _wait(1.0)
	var low: String = await cinema.take_photo()
	await _shot("49_cinematic_low.png")
	_check("a second photo, close to the ground: %s" % low.get_file(), low != "" and low != high and FileAccess.file_exists(low))
	await _key_tap(KEY_ESCAPE)
	await _wait(0.5)
	var back := cam.global_position.distance_to(player.position)
	_check("Esc goes back to Nora: the camera follows her again, the HUD is back, the clock runs (%.1f m from her, near plane %.2f)" % [back, cam.near],
		not cinema.active and hud.visible and Game.time_running == clock0 and absf(back - cam_dist) < 3.0 and is_equal_approx(cam.near, 0.5))
	# the album
	hud.album.open()
	await _wait(0.4)
	_check("the photo album lists both photos, newest first (%d)" % hud.album.paths.size(),
		hud.album.visible and hud.album.paths.size() == 2 and hud.album.paths[0] == low and hud.album.paths[1] == high and hud.album._grid.get_child_count() == 2)
	await _shot("49_album.png")
	hud.album.show_photo(1)
	await _wait(0.3)
	_check("a click shows a photo full size", hud.album._viewer.visible and hud.album._big.texture != null and hud.album.current == 1)
	await _shot("49_album_photo.png")
	hud.album.delete_current()
	await _wait(0.2)
	_check("Delete takes it out of the album and off the disk (%d left)" % hud.album.paths.size(),
		not FileAccess.file_exists(high) and hud.album.paths.size() == 1 and hud.album.paths[0] == low and hud.album.current == 0)
	await _key_tap(KEY_ESCAPE)
	_check("Esc closes the album", not hud.album.visible)
	Cinematic.delete_photo(low)


## First person (first_person.gd): V puts the camera at her eyes with her head hidden from it,
## WASD walks her the way she looks and her body turns with the view, looking down shows her own
## feet (52_fps_feet.png), a click or E on what's under the dot opens its ring, it won't start
## asleep and gives way to the cinematic camera, and V brings the overhead camera back.
func _fps_checks() -> void:
	var was_running: bool = Game.time_running
	Game.time_running = false
	_set_cam_lock(true)
	if hud.is_menu_open():
		hud.hide_menu()
	# open ground on the farm
	var start := Vector3(20.0, 0, 8.0)
	var open_round := func(q: Vector3) -> bool:
		for a in 16:
			for r in [1.0, 2.5, 4.0]:
				if not _walkable(_cell(q + Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0)) * r)):
					return false
		return true
	for i in 200:
		var q := Vector3(20.0 + (i % 20) * 2.0, 0, 8.0 - (i / 20) * 2.0)
		if open_round.call(q):
			start = q
			break
	player.walk([])
	player.cancel_activity()
	player.position = start
	player.rotation.y = 0.0
	await _wait(0.4)
	var fov0 := cam.fov
	var near0 := cam.near
	await _key_tap(KEY_V)
	await _wait(0.3)
	var eye: Vector3 = player.global_transform.affine_inverse() * cam.global_position
	_check("V puts the camera at her eyes (active %s, %.2f m up, %.2f m before her, fov %.0f, near %.2f)" % [fps.active, eye.y, eye.z, cam.fov, cam.near],
		fps.active and eye.y > 1.3 and eye.y < 1.85 and eye.z > 0.0 and eye.z < 0.35 and is_equal_approx(cam.fov, FirstPerson.FOV) and cam.near < 0.1)
	var copies: Array = fps.body_copies()
	var tri_orig := 0
	var tri_copy := 0
	for c in fps._copies:
		if c[1] == null:
			continue # a mesh that is all head (her eyes) has no copy: none of it is drawn for this camera
		var o := c[0] as MeshInstance3D
		for sidx in o.mesh.get_surface_count():
			tri_orig += o.mesh.surface_get_array_index_len(sidx) / 3
		var m := (c[1] as MeshInstance3D).mesh
		for sidx in m.get_surface_count():
			tri_copy += m.surface_get_array_index_len(sidx) / 3
	var shown := fps._copies.all(func(c): return c[1] == null or (c[1] as MeshInstance3D).visible == (c[0] as MeshInstance3D).visible)
	_check("her head isn't drawn for this camera: her %d meshes only cast their shadow (head drawn %s) and %d headless copies are drawn with them (%s; %d of %d triangles kept)" % [fps._copies.size(), fps.head_drawn(), copies.size(), shown, tri_copy, tri_orig],
		not fps.head_drawn() and not copies.is_empty() and shown and tri_copy > tri_orig * 0.4 and tri_copy < tri_orig)
	# walking: W goes the way she looks, and she turns with the view
	for yaw_deg in [30.0, -100.0]:
		player.position = start
		fps.yaw = deg_to_rad(yaw_deg)
		fps.pitch = deg_to_rad(-5.0)
		await _wait(0.3)
		var p0 := player.position
		await _key_tap(KEY_W, 1.0)
		await _wait(0.2)
		var d := player.position - p0
		var fwd := Vector3(-sin(fps.yaw), 0, -cos(fps.yaw))
		var along := d.dot(fwd)
		var side := (d - fwd * along).length()
		var facing := absf(angle_difference(player.rotation.y, fps.yaw + PI))
		_check("W walks her the way she looks (view at %.0f°: %.2f m ahead, %.2f m aside; her body %.0f° off the view)" % [yaw_deg, along, side, rad_to_deg(facing)],
			along > 1.2 and side < 0.2 and facing < deg_to_rad(5.0))
	var p1 := player.position
	await _key_tap(KEY_S, 0.6)
	var back := (player.position - p1).dot(Vector3(-sin(fps.yaw), 0, -cos(fps.yaw)))
	_check("S steps her backward (%.2f m) and she still faces the view" % back,
		back < -0.4 and absf(angle_difference(player.rotation.y, fps.yaw + PI)) < deg_to_rad(5.0))
	# looking down: her feet, on the screen and in front of the camera
	fps.pitch = deg_to_rad(FirstPerson.PITCH_MIN)
	await _wait(0.5)
	var sk: Skeleton3D = player.body.skeleton
	var vp := get_viewport().get_visible_rect().size
	var feet := 0
	for bn in ["LeftFoot", "RightFoot"]:
		var b := sk.find_bone(bn)
		if b < 0:
			continue
		var w := sk.global_transform * sk.get_bone_global_pose(b).origin
		var sp := cam.unproject_position(w)
		if not cam.is_position_behind(w) and Rect2(Vector2.ZERO, vp).has_point(sp):
			feet += 1
	var head_w := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	_check("looking down she sees both her feet (%d on screen); the Head bone is behind the camera's view (%.2f m below it)" % [feet, cam.global_position.y - head_w.y],
		feet == 2 and cam.global_position.y > head_w.y)
	await _shot("52_fps_feet.png")
	fps.key_down[KEY_W] = true # and walking, looking down
	await _wait(0.6)
	await _shot("52_fps_feet_walk.png")
	fps.key_down.clear()
	await _wait(0.4)
	fps.pitch = deg_to_rad(-6.0)
	await _wait(0.3)
	await _shot("52_fps_ahead.png")
	# using something: the dot on a piece of her furniture opens its ring, as a click from above would
	var used := ""
	var tried := 0
	var with_acts := 0
	for f in furniture:
		if used != "":
			break
		if not is_instance_valid(f) or not (f as Node3D).visible or _actions_for(f).is_empty():
			continue
		with_acts += 1
		var fp: Vector3 = (f as Node3D).global_position
		for dir in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]:
			var spot: Vector3 = fp + dir * 2.4
			if not _walkable(_cell(spot)):
				continue
			player.position = spot
			fps.yaw = atan2(dir.x, dir.z) # looking back at it
			await _wait(0.3)
			var to := fp + Vector3(0, 0.45, 0) - cam.global_position
			fps.yaw = atan2(-to.x, -to.z)
			fps.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			await _wait(0.3)
			tried += 1
			if _ray_target(get_viewport().get_visible_rect().size * 0.5) != f:
				continue
			await _key_tap(KEY_E)
			await _wait(0.2)
			if hud.is_menu_open():
				used = _name_of(f)
				await _shot("52_fps_use.png")
			break
	_check("E on what's under the dot opens its ring of actions (%s; %d of %d pieces with actions tried)" % [used if used != "" else "nothing opened", tried, with_acts], used != "" and fps.active)
	hud.hide_menu()
	await _wait(0.2)
	# a book opened from her eyes has the mouse: clicks past it do nothing, and Esc puts the book
	# down while she stays at her eyes
	books_ui.open("", true)
	await _wait(0.2)
	var book_has_it := panel_open()
	await _key_tap(KEY_ESCAPE)
	await _wait(0.2)
	_check("a book opened in first person keeps the mouse, and Esc closes it without leaving her eyes (panel %s, book open %s, first person %s)" % [book_has_it, books_ui.visible, fps.active],
		book_has_it and not books_ui.visible and fps.active)
	if books_ui.visible:
		books_ui.close()
	# the roofs: on over her from her eyes indoors, lifted from above while she's inside or furnishing,
	# on again from above once she's outside
	var house_roof: Node3D = roofs[0]["node"] if not roofs.is_empty() else null
	player.position = Vector3(4.0, 0, 3.0)
	fps.yaw = deg_to_rad(-60.0)
	fps.pitch = deg_to_rad(12.0)
	await _wait(0.5)
	var on_inside := house_roof != null and house_roof.visible
	await _shot("52_fps_indoors.png")
	await _key_tap(KEY_V)
	await _wait(0.3)
	var lifted := house_roof != null and not house_roof.visible
	var cut_in := walls.filter(func(w): return (w["short"] as Node3D).visible).size()
	player.position = Vector3(4.0, 0, 9.5)
	await _wait(0.3)
	var on_outside := house_roof != null and house_roof.visible
	var cut_out := walls.filter(func(w): return (w["short"] as Node3D).visible).size()
	set_mode(Mode.BUILD)
	await _wait(0.2)
	var build_lifted := house_roof != null and not house_roof.visible
	set_mode(Mode.LIVE)
	await _wait(0.2)
	_check("her house and the cottage have roofs (%d): on from her eyes indoors %s, lifted from above while she's inside %s (%d walls cut down), on from above outside %s with every wall standing (%d cut), lifted in building mode %s" % [roofs.size(), on_inside, lifted, cut_in, on_outside, cut_out, build_lifted],
		roofs.size() == (2 if Town.COTTAGE_ON else 1) and on_inside and lifted and cut_in >= 1 and on_outside and cut_out == 0 and build_lifted and house_roof.visible)
	_set_cam_lock(false)
	cam_target = Vector3(4.0, 0.5, 2.0)
	cam_dist = 22.0
	await _wait(1.5)
	await _shot("52_roof_outside.png")
	_set_cam_lock(true)
	await _key_tap(KEY_V)
	await _wait(0.3)
	# handing over: the cinematic camera takes over from it, and it won't start asleep
	await _key_tap(KEY_P)
	await _wait(0.3)
	_check("P leaves first person for the cinematic camera (first person %s, cinematic %s)" % [fps.active, cinema.active], not fps.active and cinema.active)
	cinema.leave()
	await _wait(0.2)
	sleeping = true
	fps.enter()
	var asleep_on: bool = fps.active
	sleeping = false
	_check("it won't start while she's asleep", not asleep_on)
	await _key_tap(KEY_V)
	await _wait(0.2)
	_check("V again goes into first person", fps.active)
	await _key_tap(KEY_V)
	await _wait(0.5)
	var dist := cam.global_position.distance_to(player.position)
	_check("V comes out: the overhead camera is back (%.1f m from her, fov %.0f, near %.2f), her head is drawn again, the copies hidden" % [dist, cam.fov, cam.near],
		not fps.active and is_equal_approx(cam.fov, fov0) and is_equal_approx(cam.near, near0) and dist > 6.0
		and fps.head_drawn() and copies.all(func(m): return not m.visible))
	Game.time_running = was_running
	player.walk([])
	player.position = Vector3(4.6, 0, 4.9)


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
	# post boxes (art/world_assets/mailbox, the same blue box as Nora's): by the Coffee Shop, the Mayor's
	# office and Willow Homes (where they stand is in data/world_layout.json, set in the world editor)
	for m in TOWN_MAILBOXES:
		_decor("mailbox", m[0], m[1])
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
	# a soft column of light and a warm glow over the goal, so it can be found from across town
	var bg := Gradient.new()
	bg.set_color(0, Color(1.0, 0.85, 0.45, 0.0))
	bg.set_color(1, Color(1.0, 0.82, 0.4, 0.5))
	var btex := GradientTexture2D.new()
	btex.gradient = bg
	btex.fill_from = Vector2(0, 0)
	btex.fill_to = Vector2(0, 1)
	btex.width = 4
	btex.height = 64
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_texture = btex
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.22
	bm.bottom_radius = 0.42
	bm.height = 7.0
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 3.5
	beam.name = "Beam"
	goal_marker.add_child(beam)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.45)
	glow.light_energy = 1.4
	glow.omni_range = 3.5
	glow.position.y = 1.2
	glow.name = "Glow"
	goal_marker.add_child(glow)
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
	# a thin streak that turns to face the camera and fades out at both ends, not a white stick
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.55)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	var streak := GradientTexture2D.new()
	streak.gradient = fade
	streak.width = 4
	streak.height = 64
	streak.fill_from = Vector2(0, 0)
	streak.fill_to = Vector2(0, 1)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.albedo_texture = streak
	dm.albedo_color = Color(0.84, 0.89, 0.96, 0.26)
	drop.material = dm
	rain_fx.mesh = drop
	rain_fx.emitting = false
	add_child(rain_fx)
	# where the drops land: small rings that spread and fade on the ground round her
	rain_splash = CPUParticles3D.new()
	rain_splash.amount = 260
	rain_splash.lifetime = 0.35
	rain_splash.local_coords = false
	rain_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_splash.emission_box_extents = Vector3(14, 0.0, 14)
	rain_splash.direction = Vector3.UP
	rain_splash.initial_velocity_min = 0.0
	rain_splash.initial_velocity_max = 0.0
	rain_splash.gravity = Vector3.ZERO
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.25))
	grow.add_point(Vector2(1, 1.0))
	rain_splash.scale_amount_curve = grow
	var out := Gradient.new()
	out.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	rain_splash.color_ramp = out
	var ring_fade := Gradient.new()
	ring_fade.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 1.0])
	ring_fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ring_tex := GradientTexture2D.new()
	ring_tex.gradient = ring_fade
	ring_tex.fill = GradientTexture2D.FILL_RADIAL
	ring_tex.fill_from = Vector2(0.5, 0.5)
	ring_tex.fill_to = Vector2(1.0, 0.5)
	ring_tex.width = 32
	ring_tex.height = 32
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = ring_tex
	sm.albedo_color = Color(0.85, 0.9, 0.97, 0.5)
	var splash := PlaneMesh.new() # flat on the ground
	splash.size = Vector2(0.22, 0.22)
	splash.material = sm
	rain_splash.mesh = splash
	rain_splash.emitting = false
	add_child(rain_splash)


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
	rain_splash.emitting = rain_fx.emitting
	rain_splash.position = Vector3(cam_target.x, 0.03, cam_target.z)
	if goal_marker.visible:
		var gem := goal_marker.get_node("Gem") as Node3D
		gem.position.y = 2.4 + 0.18 * sin(Time.get_ticks_msec() * 0.003)
		gem.rotation.y += delta * 1.6
		# the column fades as she comes close, so it never washes out what she's walking up to
		var near := clampf((goal_marker.position.distance_to(player.position) - 2.5) / 8.0, 0.0, 1.0)
		var beam := goal_marker.get_node("Beam") as GeometryInstance3D
		beam.transparency = 1.0 - near * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.002))
		beam.visible = near > 0.01
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
				var k := _work_spot(d)
				v.settle_at(k.get("pos", d["pos"]))
				v.roam = k.get("roam", d["roam"])
				if d.has("route"): # back to their round
					v.route = d["route"]
					v._next_stop()
				if k.has("yaw"):
					v.rotation.y = float(k["yaw"])
				if vid == "rosa":
					rosa_at_stall = false # _update_rounds sends her back out if it's a stall morning
					v.set_role(str(d["role"]))


## Shopkeepers (villagers.json "works_in") work inside their shops (scripts/interiors.gd): they
## stand behind the counter facing the door, and you talk to them from across it. A scene that
## has sent one somewhere else (a "home_" flag) keeps them there.
func _place_shopkeepers() -> void:
	for d in _villager_defs():
		var v := _villager(str(d["id"]))
		if v == null or not (d.has("works_in") or d.has("at")):
			continue
		var k := _work_spot(d)
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
			return _work_spot(d).get("pos", d["pos"])
	return Vector3.ZERO


## Where a villager works, wherever the world editor put the building: behind a walk-in shop's
## counter ("works_in"), or by a building that isn't walk-in ("at"). {"pos", "talk", "yaw",
## "roam"} like Interiors.keeper; {} for anyone who just has a spot ("pos").
func _work_spot(d: Dictionary) -> Dictionary:
	if d.has("works_in"):
		return Interiors.keeper(str(d["works_in"]))
	if d.has("at"):
		var k := _spot_at(d["at"])
		if not k.is_empty():
			k["roam"] = d["roam"]
		return k
	return {}


## A spot by building `at.building` (a Town.built kind, or "barn" for the farm's barn): `at.pos` and
## `at.talk` are [x, z] in the building's own space, its front toward +z. {} if the building isn't there.
func _spot_at(at: Dictionary) -> Dictionary:
	if str(at["building"]) == "barn": # the farm's barn (world.gd), wherever the world editor has put it
		if not is_instance_valid(World.barn) or not World.barn.visible:
			return {}
		var bx: Transform3D = World.barn.global_transform
		var bp: Vector2 = Data.vec2(at["pos"])
		var bt: Vector2 = Data.vec2(at.get("talk", [bp.x, bp.y + 1.2]))
		var bpos: Vector3 = bx * Vector3(bp.x, 0, bp.y)
		var btalk: Vector3 = bx * Vector3(bt.x, 0, bt.y)
		return {"pos": Vector3(bpos.x, 0, bpos.z), "talk": Vector3(btalk.x, 0, btalk.z), "yaw": atan2(bx.basis.z.x, bx.basis.z.z), "roam": Vector2.ZERO}
	for b in Town.built:
		if str(b[1]) != str(at["building"]) or not is_instance_valid(b[0]) or not (b[0] as Node3D).visible:
			continue
		var xf: Transform3D = (b[0] as Node3D).global_transform
		var p: Vector2 = Data.vec2(at["pos"])
		var t: Vector2 = Data.vec2(at.get("talk", [p.x, p.y + 1.2]))
		var pos: Vector3 = xf * Vector3(p.x, 0, p.y)
		var talk: Vector3 = xf * Vector3(t.x, 0, t.y)
		var front: Vector3 = xf.basis.z
		return {"pos": Vector3(pos.x, 0, pos.z), "talk": Vector3(talk.x, 0, talk.z), "yaw": atan2(front.x, front.z), "roam": Vector2.ZERO}
	# not a building: a single piece of town decor by its id ("by welcome_sign 0 3"), wherever the
	# world editor has put it
	for f in decor:
		if not is_instance_valid(f) or f.item_id != str(at["building"]) or not f.visible:
			continue
		var dx: Transform3D = f.global_transform
		var dp: Vector2 = Data.vec2(at["pos"])
		var dt: Vector2 = Data.vec2(at.get("talk", [dp.x, dp.y + 1.2]))
		var dpos: Vector3 = dx * Vector3(dp.x, 0, dp.y)
		var dtalk: Vector3 = dx * Vector3(dt.x, 0, dt.y)
		var dfront: Vector3 = dx.basis.z
		return {"pos": Vector3(dpos.x, 0, dpos.z), "talk": Vector3(dtalk.x, 0, dtalk.z), "yaw": atan2(dfront.x, dfront.z), "roam": Vector2.ZERO}
	return {}


## The town's daily routines, checked twice a second (from _process): Rosa keeps the market stall
## on mornings (villagers.json "stall") and the Yarn Barn the rest of the day; Barbara sets out
## with the post at nine ("post_round"), door to door round the town and out to Nora's farm, then
## back to the plaza. A story scene that has sent either somewhere (a "home_" flag) comes first.
var rosa_at_stall := false
var _rounds_t := 0.0
var post_day := 0 # the day Barbara last set out
var _post_stops: Array = [] # the doors still to call at today (Vector3s), her post spot last
const POST_FARM_DOOR := Vector3(10.6, 0, 3.0) # Gran's porch step; the round now stops at the mailbox instead (post_farm_stop())


func _update_rounds(delta: float) -> void:
	_rounds_t -= delta
	if _rounds_t > 0.0 or title_on or not town_rounds or story.is_playing():
		return
	_rounds_t = 0.5
	_update_rosa()
	_update_post()
	mail.update()
	_update_gary_visit()
	_update_max_visit()
	cafe_visits.update()
	suburb.update() # to bed in Bretton Oaks at night, out in the morning


## Gary from Willow Homes calls at the farm: first on her second day (data/scenes/town.scene
## "gary_intro": he introduces himself and pitches three plots of land she can't afford yet), then
## every two weeks with another pitch about trading up ("gary_pitch"). He comes while she's home
## on the farm, mid-morning to mid-afternoon, and not in the middle of something.
const GARY_EVERY := 14


func gary_visit_due() -> bool:
	var last: int = int(Game.flag("gary_visit_day", 0))
	if last == 0:
		return Game.day >= 2
	return Game.day - last >= GARY_EVERY


func _update_gary_visit() -> void:
	if not gary_visit_due() or Game.hour < 10.0 or Game.hour > 16.0 or mode != Mode.LIVE or sleeping:
		return
	if not LOT.has_point(Vector2(player.position.x, player.position.z)) or player.busy or knit.active:
		return
	if homestead.story_farm() and not Game.flag("act1_note"):
		return
	var id := Story.find_trigger("event", "gary_visit")
	if id == "":
		return
	Game.set_flag("gary_visit_day", Game.day)
	story.play(id)


## Max's visit (data/scenes/max.scene; Alex, 2026-11-13): once she has played
## "max_visit_hours" hours of this save (data/economy.json "story"; counted in the flag
## play_secs), he drives out to the farm to win her back. He comes while she's home on the farm,
## mid-morning to late afternoon, after Act 1, and only once.
func max_visit_due() -> bool:
	if Game.flag("act1_done") != true or Game.flag("seen_max_visit") == true:
		return false
	var hours: float = float(Data.economy().get("story", {}).get("max_visit_hours", 4.0))
	return float(Game.flags.get("play_secs", 0.0)) >= hours * 3600.0


## Sent away, he comes back once, "max_return_days" days later (data/economy.json "story"), unless
## she has reported him to Rebecca by then (data/scenes/max.scene; Alex, 2026-11-15).
func max_return_due() -> bool:
	if Game.flag("max_visit_done") != true or Game.flag("seen_max_return") == true or Game.flag("max_reported") == true or Game.flag("max_arrested") == true:
		return false
	if not Game.flags.has("max_visit_day"):
		Game.set_flag("max_visit_day", Game.day) # a save from before he could come back: count from today
	var days: int = int(Data.economy().get("story", {}).get("max_return_days", 3))
	return Game.day >= int(Game.flags["max_visit_day"]) + days


func _update_max_visit() -> void:
	if story.is_playing() or mode != Mode.LIVE or sleeping or player.busy or knit.active:
		return
	if Game.flag("max_reported") == true and Game.flag("max_arrested") != true:
		# reported to Rebecca: she is waiting the next time he turns up at the lane, wherever Nora is now
		var arrest := Story.find_trigger("event", "max_arrest")
		if arrest != "":
			visitor("max")
			story.play(arrest)
		return
	if Game.hour < 10.0 or Game.hour > 17.0 or not LOT.has_point(Vector2(player.position.x, player.position.z)):
		return
	var first := max_visit_due()
	if not first and not max_return_due():
		return
	var id := Story.find_trigger("event", "max_visit" if first else "max_return")
	if id == "":
		return
	if first:
		Game.set_flag("max_visit_day", Game.day)
	visitor("max")
	story.play(id)


## People who come for one scene and go (Max): story scenes find them by id like the villagers
## (_villager), but they aren't in the town's cast and leave when their scene ends. Max plays in
## his own model (data/characters.json "max"); the colours are only a fallback if it won't load.
var visitors := {} # id -> Villager


func _visitor_def(id: String) -> Dictionary:
	match id:
		"max":
			return {"name": "Max", "role": "Visitor", "pos": Vector3(18.0, 0, 4.3),
				"look": {"model": "max", "skin": Color(0.9, 0.74, 0.62), "hair": Color(0.33, 0.23, 0.15), "top": Color(0.22, 0.24, 0.29), "bottom": Color(0.15, 0.16, 0.19)}}
	return {}


func visitor(id: String) -> Villager:
	var have: Variant = visitors.get(id)
	if have != null and is_instance_valid(have):
		return have as Villager
	var d := _visitor_def(id)
	if d.is_empty():
		return null
	var v = Villager.new()
	v.setup(id, str(d["name"]), str(d["role"]), "", d["pos"], d["look"])
	v.roam = Vector2.ZERO
	add_child(v)
	if v.tag:
		v.tag.visible = false # only here for a scene, where name tags are too big for the close-ups
	visitors[id] = v
	return v


func _send_visitors_home() -> void:
	for id in visitors:
		if is_instance_valid(visitors[id]):
			(visitors[id] as Node).queue_free()
	visitors.clear()


func _villager_def(vid: String) -> Dictionary:
	for d in _villager_defs():
		if str(d["id"]) == vid:
			return d
	return {}


func _update_rosa() -> void:
	var v := _villager("rosa")
	var d := _villager_def("rosa")
	if v == null or not d.has("stall") or Game.flag("home_rosa", null) != null:
		return
	var hours: Array = d["stall"]["hours"]
	var want: bool = Game.hour >= float(hours[0]) and Game.hour < float(hours[1])
	if want == rosa_at_stall:
		return
	var k := _spot_at(d["stall"]) if want else _work_spot(d)
	if k.is_empty():
		return
	rosa_at_stall = want
	v.set_role("Market Stall" if want else str(d["role"]))
	v.walk_to(k["pos"], _find_path(v.position, k["pos"]))
	v.talk_spot = k["talk"]
	v.rest_yaw = k["yaw"]


## The doors on Barbara's round today, from where she stands: every building in town, nearest
## first, then Nora's mailbox by Gran's porch, then back to her spot on the plaza.
func post_round_stops(from: Vector3) -> Array:
	var doors: Array = []
	for b in Town.built:
		var kind := str(b[1])
		if not kind.begins_with("building_") or not is_instance_valid(b[0]) or not (b[0] as Node3D).visible:
			continue
		var id := kind.substr(9)
		var depth := 0.0
		if Interiors.shops.has(id):
			depth = (Interiors.shops[id] as Interiors.Shop).size.y
		elif id == "cafe":
			depth = Town.CAFE.size.y
		elif id == "mayor":
			depth = Town.MAYOR.size.y
		else:
			continue
		var xf: Transform3D = (b[0] as Node3D).global_transform
		var p: Vector3 = xf * Vector3(0, 0, depth * 0.5 + 0.9)
		doors.append(Vector3(p.x, 0, p.z))
	var out: Array = []
	var at := from
	while not doors.is_empty():
		var best := 0
		for i in doors.size():
			if (doors[i] as Vector3).distance_to(at) < (doors[best] as Vector3).distance_to(at):
				best = i
		at = doors.pop_at(best)
		out.append(at)
	out.append(post_farm_stop())
	out.append(_villager_def("barbara").get("pos", from))
	return out


## Where Barbara stops at the farm: in front of Nora's mailbox, wherever it stands (mail.gd).
func post_farm_stop() -> Vector3:
	return mail.stop_point()


## Barbara has been round with today's post (and is free for a coffee).
func post_round_done() -> bool:
	return post_day == Game.day and _post_stops.is_empty()


func _update_post() -> void:
	var v := _villager("barbara")
	var d := _villager_def("barbara")
	if v == null or not d.has("post_round") or Game.flag("home_barbara", null) != null:
		_post_stops.clear()
		return
	if _post_stops.is_empty():
		if post_day != Game.day and Game.hour >= float(d["post_round"]) and Game.hour < 17.0:
			post_day = Game.day
			_post_stops = post_round_stops(v.position)
			_post_next(v)
		return
	# at this door: a moment to put the letters through, then on to the next
	var here: Vector3 = _post_stops[0]
	if Vector2(v.position.x - here.x, v.position.z - here.z).length() < 0.3 and v._via.is_empty():
		if v.hold_time <= 0.0 and v.get_meta("posted", false) == false:
			v.set_meta("posted", true)
			v.hold(1.5)
			if here.distance_to(post_farm_stop()) < 0.5:
				var n: int = mail.post_call() # letters in, any sweater for a customer out
				if player.position.distance_to(here) < 14.0:
					mail.told_today()
					hud.show_toast("Barbara brings the post." if n > 0 else "Barbara looks in at the mailbox. Nothing for you today.")
		elif v.hold_time <= 0.0:
			_post_stops.pop_front()
			if _post_stops.is_empty():
				v.roam = d["roam"]
			else:
				_post_next(v)


func _post_next(v) -> void:
	v.set_meta("posted", false)
	var p: Vector3 = _post_stops[0]
	v.walk_to(p, _find_path(v.position, p))


## Lines kept in data/economy.json "building" (drafts for Alex).
func econ_lines(k: String) -> Array:
	return HouseBuilder.econ().get(k, [])


## Gary's listings at Willow Homes (data/economy.json "land"): name, where, price, his pitch.
func land_plots() -> Array:
	return Data.economy().get("land", [])


func _cheapest_plot() -> int:
	var best := 0
	for l in land_plots():
		if best == 0 or int(l["price"]) < best:
			best = int(l["price"])
	return best


## 12500 -> "12,500".
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Who lives in Maplewood: res://data/villagers.json.
func _villager_defs() -> Array:
	return Data.villagers()


func _villager(id: String) -> Villager:
	for v in villagers:
		if v.vid == id:
			return v
	var w: Variant = visitors.get(id) # someone here for one scene (Max)
	if (w == null or not is_instance_valid(w)) and townsfolk and id.begins_with("tf_"):
		w = townsfolk.find(id) # one of the townsfolk (townsfolk.gd), for the café's visits
	return w as Villager if w != null and is_instance_valid(w) else null


func _rosa_price() -> int:
	return int(round(Game.market_price("sweater") * (1.0 + 0.04 * Game.hearts("rosa"))))


## Rosa's Yarn Barn prices (wool, sheep), a little less for every heart.
## Rosa only has so much wool a day (data/economy.json "store" wool_packs_a_day), so buying it in
## can't replace her own animals. Game.flags["wool_bought"] is [day, packs bought that day].
func _wool_packs_bought() -> int:
	var b: Variant = Game.flag("wool_bought", [])
	return int(b[1]) if b is Array and b.size() == 2 and int(b[0]) == Game.day else 0


func _wool_packs_left() -> int:
	return maxi(0, int(_store().get("wool_packs_a_day", 2)) - _wool_packs_bought())


func _yarn_price(base: int) -> int:
	return int(round(base * (1.0 - 0.05 * Game.hearts("rosa"))))


const COFFEE_PRICE := 6 # a coffee from Sabrina: warms her up
const COFFEE_WARMTH := 15.0


## Heart Bakery's pastries: data/economy.json "pastry" (price, energy, food, happiness, max).
func pastry() -> Dictionary:
	return Data.economy().get("pastry", {"price": 20, "energy": 30, "food": 30, "happiness": 40, "max": 6})


func _pastry_price() -> int:
	return int(round(float(pastry().get("price", 20)) * (1.0 - 0.05 * Game.hearts("giorgio"))))


## Pastries (--only=shops, at Giorgio's counter): one in her bag is eaten by clicking it again in her
## hand, giving data/economy.json "pastry"'s energy, food and happiness; the bag holds "max" at most.
func _pastry_checks(giorgio) -> void:
	var p := pastry()
	hud.hide_dialogue()
	await _wait(0.3)
	var at := Game.slots.find("pastry")
	_check("the pastry is in her bag (slot %d)" % (at + 1), at >= 0)
	if at < 0:
		return
	if at >= Hud.HOTBAR: # a full hotbar: bring it down from the bag first
		Game.swap_slots(at, Hud.HOTBAR - 1)
		at = Hud.HOTBAR - 1
	Game.energy = 40.0
	Game.fullness = 40.0
	Game.happiness = 40.0
	var n0 := Game.count("pastry")
	hud.slot_btns[at].pressed.emit() # in her hand
	var in_hand := hud.selected_item() == "pastry" and Game.count("pastry") == n0
	hud.slot_btns[at].pressed.emit() # and eaten
	await _wait(0.2)
	_check("clicking the pastry in her hand again eats it (held first %s, pastries %d -> %d, energy %.0f, food %.0f, happiness %.0f from 40)" % [in_hand, n0, Game.count("pastry"), Game.energy, Game.fullness, Game.happiness],
		in_hand and Game.count("pastry") == n0 - 1 and absf(Game.energy - 40.0 - float(p["energy"])) < 1.0 and absf(Game.fullness - 40.0 - float(p["food"])) < 1.0 and absf(Game.happiness - 40.0 - float(p["happiness"])) < 1.0)
	var mx := int(p.get("max", 6))
	Game.add_item("pastry", mx - Game.count("pastry"))
	Game.coins = maxi(Game.coins, 500)
	var row: Dictionary = {}
	for a in _villager_actions(giorgio):
		if str(a.get("id", "")) == "buy_pastry":
			row = a
	_check("with %d pastries her bag is full and Giorgio's row says so ('%s')" % [mx, str(row.get("label", ""))],
		not row.is_empty() and not bool(row.get("enabled", true)))
	Game.take_item("pastry", Game.count("pastry"))
	hud.hot_sel = 0


## Eats one of a food she carries (hud.eat_pressed: a second click on it in her hand). Returns
## whether she ate it: not while she's busy, in a story scene or asleep.
func eat_item(item: String) -> bool:
	if item != "pastry" or not Game.has_item(item) or player.busy or story.is_playing() or sleeping:
		return false
	var p := pastry()
	if not Game.take_item(item):
		return false
	Game.add_need("energy", float(p.get("energy", 30)))
	Game.add_need("fullness", float(p.get("food", 30)))
	Game.add_need("happiness", float(p.get("happiness", 40)))
	hud.click("ui_open")
	hud.show_toast("A pastry from Heart Bakery. (+%d energy, +%d food, +%d happiness)" % [int(p.get("energy", 30)), int(p.get("food", 30)), int(p.get("happiness", 40))])
	return true


func _cottage_price() -> int:
	return int(round(Game.COTTAGE_PRICE * (1.0 - 0.04 * Game.hearts("gary"))))


func _update_price_board() -> void:
	if price_board:
		price_board.text = "TODAY'S PRICES\nSweater   %dc\nPumpkin   %dc\nTurnip     %dc" % [_rosa_price(), Game.market_price("pumpkin"), Game.market_price("turnip")]


## What Builder's Delight sells over Steve's counter besides wood: data/economy.json "store".
var _store_cache := {}
func _store() -> Dictionary:
	if _store_cache.is_empty():
		_store_cache = Data.load_json("economy").get("store", {})
	return _store_cache


func _buy_from_store(v, id: String) -> void:
	var store := _store()
	if id.begins_with("buy_tool_"):
		var t := id.trim_prefix("buy_tool_")
		var price := int(store.get("tools", {}).get(t, 0))
		if price <= 0 or Game.has_item(t) or not Game.spend(price):
			return
		Game.add_item(t, 1)
		Game.sync_slots()
		var said := {"hoe": "Hoe. Breaks ground for a bed. Right-click the grass.", "watering_can": "Fill it at the pump. Crops grow faster wet.",
			"shovel": "Digs a bed back out. Or anything else.", "scythe": "Long grass. Hay for the sheep.", "axe": "Farm trees only. They grow back. Mind your feet."}
		_say(v, str(said.get(t, "Good tool. Look after it.")))
		var hint := Hud.Slot.tool_hint(t)
		hud.show_toast("New tool: %s. %s." % [Hud.Slot.item_name(t), hint.left(1).to_upper() + hint.substr(1)])
		_story_event_soon("tool_bought")
	else:
		var crop := id.trim_prefix("buy_seeds_")
		var pack: Array = store.get("seeds", {}).get(crop, [])
		if pack.size() < 2 or not Game.spend(int(pack[1])):
			return
		Game.add_item(crop + "_seeds", int(pack[0]))
		_say(v, "%d %s seeds. Plant them in a dug bed." % [int(pack[0]), crop.capitalize()])
		hud.show_toast("+%d %s seeds" % [int(pack[0]), crop])
		_story_event_soon("seeds_bought") # Act 1: Wren sent her for seed


func _villager_actions(v) -> Array:
	var acts := [_act("talk", "Talk")]
	match v.vid:
		"rosa": # the Yarn Barn, and some mornings the market stall
			var sw := Game.count("sweater")
			acts.append(_act("sell_sweater", "Sell sweaters  (%d, %dc)" % [sw, Game.sweater_worth(_rosa_price())], sw > 0))
			var wp := _yarn_price(Game.WOOL_PACK_PRICE)
			if _wool_packs_left() > 0:
				acts.append(_act("buy_wool", "Buy 3 wool  (%dc · %d left today)" % [wp, _wool_packs_left()], Game.coins >= wp))
			else:
				acts.append(_act("noop", "Buy 3 wool  (sold out till tomorrow)", false))
			acts.append_array(empire.needle_rows()) # better needles, a step at a time
			if homestead.story_farm() and not homestead.has_pen():
				acts.append(_act("noop", "Buy a sheep  (build a pen first)", false))
			elif wildlife.pen_room() <= 0: # a pen holds four animals; another pen makes room
				acts.append(_act("noop", "Buy a sheep  (your pens are full)", false))
			elif Game.sheep_count < Game.MAX_SHEEP:
				var sp := _yarn_price(Game.SHEEP_PRICE)
				acts.append(_act("buy_sheep", "Buy a sheep  (%dc · you have %d)" % [sp, Game.sheep_count], Game.coins >= sp))
			else:
				acts.append(_act("noop", "Your pen is full (%d sheep)" % Game.MAX_SHEEP, false))
		"rebecca": # the police officer: once she has left the offer open, Max can be reported any day (data/scenes/max.scene)
			if Game.flag("max_report_open") == true and Game.flag("max_reported") != true and Game.flag("max_arrested") != true:
				acts.append(_act("report_max", "Report Max"))
		"steve": # Builder's Delight: wood, tools and seeds, anything for the house that isn't wool, food or coffee
			var n := homestead.econ("wood_pack", 5)
			var wp := homestead.econ("wood_pack_price", 15)
			acts.append(_act("buy_wood", "Buy %d wood  (%dc)" % [n, wp], Game.coins >= wp))
			var store := _store()
			var tools: Dictionary = store.get("tools", {})
			for t in tools:
				var tp := int(tools[t])
				if Game.has_item(t):
					acts.append(_act("noop", "%s  (you have one)" % Hud.Slot.item_name(t), false))
				else:
					acts.append(_act("buy_tool_" + t, "Buy a %s  (%dc)" % [Hud.Slot.item_name(t).to_lower(), tp], Game.coins >= tp))
			var seeds: Dictionary = store.get("seeds", {})
			for crop in seeds:
				var pack: Array = seeds[crop]
				acts.append(_act("buy_seeds_" + crop, "Buy %d %s seeds  (%dc)" % [int(pack[0]), crop, int(pack[1])], Game.coins >= int(pack[1])))
			acts.append_array(empire.lantern_rows())
		"giorgio":
			var pp := _pastry_price()
			var room: bool = Game.count("pastry") < int(pastry().get("max", 6))
			acts.append(_act("buy_pastry", "Buy a pastry  (%dc)" % pp if room else "Your bag's full of pastries", Game.coins >= pp and room))
		"sabrina":
			acts.append(_act("buy_coffee", "Buy a coffee  (%dc)" % COFFEE_PRICE, Game.coins >= COFFEE_PRICE and Game.warmth < 99.0))
		"gary":
			if not Town.COTTAGE_ON: # Rosewood Cottage is hidden for now (town.gd)
				pass
			elif Game.owns_cottage:
				acts.append(_act("noop", "Rosewood Cottage rent: %dc a day" % _cottage_rent(), false))
			else:
				var cp := _cottage_price()
				acts.append(_act("buy_cottage", "Buy Rosewood Cottage  (%dc)" % cp, Game.coins >= cp))
			for pl in HouseBuilder.plots(): # building plots: room for a new house (house_builder.gd)
				var pid := str(pl["id"])
				var row: Dictionary
				if builder.owns(pid):
					row = _act("noop", "%s is yours. Build on it in Build mode (B)" % pl["name"], false)
				else:
					var pp := builder.plot_price(pl)
					row = _act("buy_plot:" + pid, "Buy a plot: %s, %s  (%sc)" % [pl["name"], pl["where"], _thousands(pp)], Game.coins >= pp)
				row["group"] = "Building plots"
				acts.append(row)
			for l in land_plots(): # his listings: out of reach for now, and not for sale yet
				var row := _act("noop", "%s, %s  (%sc)" % [l["name"], l["where"], _thousands(int(l["price"]))], false)
				row["group"] = "Land for sale"
				acts.append(row)
		"lars": # he rents her the barn's stalls for her flock (homestead.gd)
			if homestead.barn_rent_on():
				var owed := homestead.barn_rent_owed()
				if owed > 0:
					acts.append(_act("pay_barn_rent", "Pay the barn rent  (%dc)" % owed, Game.coins >= owed))
				else:
					acts.append(_act("noop", "Barn rent's paid. Next %dc on day %d" % [homestead.econ("barn_rent", 60), int(Game.flag("barn_rent_due", 0))], false))
	acts.append_array(jobs.actions_for(v.vid)) # take a job, work a shift (jobs.gd)
	acts.append_array(empire.rows_for(v)) # a request for a rare knit: ask, or hand it over
	acts.append_array(sale.rows_for(v)) # ask if they want a sweater, and haggle (sweater_sale.gd)
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
	if id == "report_max": # Rebecca's row: she takes it from here (rebecca_report, then max_arrest)
		var rid := Story.find_trigger("event", "report_max")
		if rid != "":
			story.play(rid)
		return
	if id.begins_with("job_"):
		jobs.action(v, id)
		return
	if id == "sale_ask" or id == "sale_haggle":
		sale.ask(v)
		return
	if id == "sale_guided": # Act 1: Wren's first sale, if she shut the panel before it was done
		sale.open_guided(v)
		return
	if id.begins_with("buy_tool_") or id.begins_with("buy_seeds_"):
		_buy_from_store(v, id)
		return
	match id: # the empire's own rows (empire.gd)
		"buy_needles":
			empire.buy_needles(v)
			return
		"buy_lantern":
			empire.buy_lantern(v)
			return
		"request_ask":
			empire.ask(v)
			return
		"request_give":
			empire.give(v)
			return
	match id:
		"talk":
			var scene_id := Jobs.offer_scene(v.vid) # a job offer comes first, once it's due
			if scene_id == "":
				scene_id = Story.find_trigger("talk", v.vid)
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
		"sell_sweater":
			var n := Game.count("sweater")
			var price := _rosa_price()
			var worth := Game.sweater_worth(price) # by rarity
			if n > 0 and Game.take_item("sweater", n):
				Game.coins += worth
				var praise: Array = ["Oh, these are gorgeous!", "Lovely work, as always.", "The city folks will snap these up!"]
				_say(v, "%s Here's %dc for %d sweater%s." % [praise[Game.day % 3], worth, n, "s" if n > 1 else ""])
				hud.show_toast("Sold %d sweater%s for %dc!" % [n, "s" if n > 1 else "", worth])
		"buy_wool":
			if _wool_packs_left() > 0 and Game.spend(_yarn_price(Game.WOOL_PACK_PRICE)):
				Game.set_flag("wool_bought", [Game.day, _wool_packs_bought() + 1])
				Game.add_item("wool", 3)
				_say(v, "Three bundles, love, my best oatmeal. Enough for one sweater, if you don't drop stitches.")
				_story_event_soon("yarn_bought")
		"buy_wood":
			if Game.spend(homestead.econ("wood_pack_price", 15)):
				Game.add_item("wood", homestead.econ("wood_pack", 5))
				var said: Array = ["Straight lengths. Panel each. Two for a gate.", "Mind your thumbs.", "Sheep lean. Build it like you mean it."]
				_say(v, said[(Game.day + int(f["n"])) % said.size()])
				hud.show_toast("+%d wood" % homestead.econ("wood_pack", 5))
				homestead.ui.refresh()
				_story_event_soon("wood_bought")
		"buy_sheep":
			if Game.sheep_count < Game.MAX_SHEEP and Game.spend(_yarn_price(Game.SHEEP_PRICE)):
				var sheep_name: String = Dialogue.NEW_SHEEP[(Game.sheep_count - Game.START_SHEEP) % Dialogue.NEW_SHEEP.size()]
				Game.sheep_count += 1
				_add_sheep()
				_say(v, "Her name is %s. I'll have her walked over to your pen by teatime. Be nice to her!" % sheep_name)
				hud.show_toast("%s the sheep joined your flock! (%d sheep)" % [sheep_name, Game.sheep_count])
		"buy_pastry":
			if Game.count("pastry") < int(pastry().get("max", 6)) and Game.spend(_pastry_price()):
				Game.add_item("pastry")
				var said: Array = ["Still warm. Wrap it up, eat it when the day gets long.", "Out of the oven at six, like every day. Some things you can count on.", "You're too thin, cara. Take it for later. Take two."]
				_say(v, said[(Game.day + int(f["n"])) % said.size()])
				hud.show_toast("A pastry, wrapped for later (%d in your bag). Click it in your hand to eat it." % Game.count("pastry"))
		"buy_coffee":
			if Game.spend(COFFEE_PRICE):
				Game.add_need("warmth", COFFEE_WARMTH)
				Game.add_need("happiness", 2.0)
				var said: Array = ["One coffee. Don't say it's cute in here.", "It's hot. Obviously. It's coffee.", "Here. You look like you needed it. Whatever."] if Game.stat("sabrina", "trust") < 10 else ["Made it the way you like. Don't make it weird.", "Extra hot. You're always freezing.", "On the house. Kidding. Six coins."]
				_say(v, said[(Game.day + int(f["n"])) % said.size()])
				hud.show_toast("A hot coffee. (+%d warmth)" % int(COFFEE_WARMTH))
		"pay_barn_rent":
			if homestead.pay_barn_rent():
				var thanks: Array = ["Cheers, neighbour. Stalls are mucked out and the straw's fresh.", "All good. Your lot are the best-behaved lodgers I've had.", "Thanks! I'll put it towards a new radio for the barn. The sheep have opinions."]
				_say(v, thanks[(Game.day + int(f["n"])) % thanks.size()])
		"buy_cottage":
			if Town.COTTAGE_ON and not Game.owns_cottage and Game.spend(_cottage_price()):
				Game.owns_cottage = true
				_rebuild_house()
				_rebuild_grid()
				_say(v, "Look at you, a property owner. Keys to Rosewood Cottage. Furnish it in Build mode: cozier means more rent every morning. You're welcome.")
				hud.show_toast("You bought Rosewood Cottage!")
		_:
			if id.begins_with("buy_plot:"):
				var pd := HouseBuilder.plot_def(id.substr(9))
				if not pd.is_empty() and builder.buy_plot(str(pd["id"])):
					var lines: Array = econ_lines("plot_sold")
					_say(v, str(lines[Game.day % lines.size()]) if not lines.is_empty() else "Sold! It's yours.")
					hud.show_toast("You bought %s. Press B and lay its first wall." % pd["name"])
				return
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


## She owns Rosewood Cottage and it's in the game (Town.COTTAGE_ON): an old save that bought it
## keeps the flag while it's hidden, but gets no rooms, yard or rent from it.
func cottage_owned() -> bool:
	return Town.COTTAGE_ON and Game.owns_cottage


func cottage_interior() -> Rect2:
	var c := Town.COTTAGE
	return Rect2(c.position.x + 0.1, c.position.y + 0.1, c.size.x - 0.2, c.size.y - 0.2)


func cottage_house_rect() -> Rect2:
	return Town.COTTAGE.grow(WALL_T * 0.5)


## Rent paid every morning: a base amount plus more for every piece of furniture.
func _cottage_rent() -> int:
	if not cottage_owned():
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
	if not Town.COTTAGE_ON: # hidden for now (town.gd)
		return
	var c := Town.COTTAGE
	var x0 := c.position.x
	var x1 := c.end.x
	var z0 := c.position.y
	var z1 := c.end.y
	var dz := Town.COTTAGE_DOOR
	HouseSkin.on(Catalog.box(house_root, Vector3(c.size.x + 0.7, 0.1, c.size.y + 0.7), Vector3(c.get_center().x, -0.04, c.get_center().y), Catalog.STONE), "stone")
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
	HouseSkin.on(Catalog.box(tall, Vector3(gap, h, WALL_T), Vector3(0, 2.15 + h * 0.5, 0), PLASTER), "plaster")
	HouseSkin.oak(Catalog.box(tall, Vector3(gap + 0.02, 0.16, WALL_T + 0.06), Vector3(0, WALL_H - 0.08, 0), Catalog.WOOD_DARK))
	HouseSkin.oak(Catalog.box(tall, Vector3(gap + 0.1, 0.1, WALL_T + 0.08), Vector3(0, 2.15, 0), Catalog.WOOD_DARK))
	if Game.owns_cottage:
		HouseSkin.oak(Catalog.box(tall, Vector3(0.06, 2.05, 1.2), Vector3(-gap * 0.5 + 0.06, 1.03, 0.64), Catalog.WOOD), HouseSkin.LIGHT_OAK)
	else:
		HouseSkin.oak(Catalog.box(tall, Vector3(gap, 2.05, 0.08), Vector3(0, 1.03, 0), Catalog.WOOD), HouseSkin.LIGHT_OAK)
		Catalog.ball(tall, 0.04, Vector3(gap * 0.32, 1.0, -0.06), Catalog.BRASS)
		wall_rects.append(Rect2(dz.x, z0 - WALL_T * 0.5, gap, WALL_T))
	walls.append({"tall": tall, "short": short, "normal": Vector3(0, 0, -1), "cut": true})
	_house_roof(c, c.size.y > c.size.x)
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


## Rosewood Cottage in the town checks (only while Town.COTTAGE_ON): locked, bought from Gary,
## walked into, furnished, and paying rent the next morning.
func _cottage_buy_checks() -> void:
	var blocked := _find_path(Vector3(61.5, 0, 4.5), Vector3(61.5, 0, 9.5))
	_check("cottage is locked before buying", blocked.is_empty() or blocked[-1].distance_to(Vector3(61.5, 0, 9.5)) > 0.8)
	Game.coins += 3000
	var gary := _villager("gary")
	_do_action(gary, "buy_cottage")
	await _walk_wait()
	_check("bought Rosewood Cottage from Gary", Game.owns_cottage)
	var into := _find_path(Vector3(61.5, 0, 4.5), Vector3(61.5, 0, 9.5))
	_check("can walk into the cottage after buying", into.size() > 0 and into[-1].distance_to(Vector3(61.5, 0, 9.5)) < 0.8)


func _cottage_furnish_checks() -> void:
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


func _cottage_rent_checks() -> void:
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
	var tags_shown := villagers.filter(func(v): return v.tag != null and v.tag.modulate.a > 0.5).size()
	_check("in town only the nearest villager's name tag shows (%d)" % tags_shown, tags_shown <= 1)
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
	var w0 := Game.count("wool")
	_do_action(rosa, "buy_wool")
	await _walk_wait()
	_check("bought 3 wool from Rosa", Game.count("wool") == w0 + 3)
	var n0 := sheep_list.size()
	_do_action(rosa, "buy_sheep")
	await _walk_wait()
	_check("bought a sheep (%d → %d in the pen)" % [n0, sheep_list.size()], sheep_list.size() == n0 + 1 and Game.sheep_count == n0 + 1)

	if Town.COTTAGE_ON:
		await _cottage_buy_checks()
	else:
		var gary_rows: Array = _villager_actions(_villager("gary")).map(func(a): return str(a.get("id", "")))
		_check("Rosewood Cottage is hidden: no house, sign or sale (Gary's rows %s, rent %dc, the lot walkable %s)" % [str(gary_rows), _cottage_rent(), str(not _find_path(Vector3(61.5, 0, 4.5), Vector3(61.5, 0, 9.5)).is_empty())],
			not gary_rows.has("buy_cottage") and _cottage_rent() == 0 and house_root.get_children().all(func(n): return n.get("kind") != "for_sale"))
	set_mode(Mode.BUILD)
	cam_target = Vector3(61.5, 0, 9.5)
	cam_dist = 18.0
	player.position = Vector3(61.5, 0, 5.2)
	await _wait(0.8)
	if Town.COTTAGE_ON:
		await _cottage_furnish_checks()
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
	if Town.COTTAGE_ON:
		await _cottage_rent_checks()
	_save_game()
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check("save has cottage, friendships and sheep", (bool(d["owns_cottage"]) or not Town.COTTAGE_ON) and int(d["friends"]["rosa"]["familiarity"]) > 0 and int(d["sheep_count"]) == n0 + 1)


## Building walls (house_builder.gd): B opens build mode and its wall tool; each wall costs coins;
## four walls close a room against the house, which joins it with a doorway and gets a plank floor
## and a roof; she walks into it; a plot bought from Gary takes a new house (its first wall pays
## for the foundations), walked into through its doorway; the world editor lists her walls and
## takes one down; all of it survives a save. It leaves the farm as it found it.
func _build_checks() -> void:
	var coins0 := Game.coins
	var wood0 := Game.count("wood")
	Game.take_item("wood", wood0) # walls are paid in wood when she has it: these checks count coins
	var hour0 := Game.hour
	Game.hour = 11.0
	Game.flags.erase("built_walls")
	Game.flags.erase("built_paid")
	Game.flags.erase("house_openings")
	Game.flags.erase("floors")
	Game.flags.erase("floors_paid")
	Game.flags.erase("plots_owned")
	builder.refresh_world()
	set_mode(Mode.LIVE)
	hud.hide_dialogue()
	player.position = Vector3(10.5, 0, 7.5) # out on the grass, clear of the house
	Game.coins = 5000
	await _key_tap(KEY_B)
	hud.wall_tool_chosen.emit("wall") # the Wall button in Build & Buy
	await _wait(0.2)
	_check("build: B opens build mode, and Walls picks up the wall tool (mode %s, tool '%s', button lit %s)" % [mode, builder.tool, hud.wall_btn.button_pressed],
		mode == Mode.BUILD and builder.tool == "wall" and hud.wall_btn.button_pressed and hud.catalog_panel.visible)
	# a room against the house: the first candidate whose four walls can all go up
	var candidates := [["2,6,v", "2,8,h", "4,8,h", "6,6,v"], ["-2,2,h", "-2,2,v", "-2,4,v", "-2,6,h"], ["0,6,v", "0,8,h", "2,8,h", "4,6,v"]]
	var room: Array = []
	for cand in candidates:
		var why := ""
		Game.set_flag("built_walls", {})
		var trial := {}
		for k in cand:
			var c := builder.check(k)
			if not c["ok"]:
				why = "%s: %s" % [k, c["why"]]
				break
			trial[k] = "wall"
			Game.set_flag("built_walls", trial.duplicate())
		Game.flags.erase("built_walls")
		if why == "":
			room = cand
			break
		print("build: room %s can't go up (%s)" % [str(cand), why])
	builder.compute()
	_check("build: there's room for a room against the house (%s)" % str(room), not room.is_empty())
	if room.is_empty():
		Game.coins = coins0
		set_mode(Mode.LIVE)
		return
	var c0 := Game.coins
	var mid0 := _edge_mid(room[0])
	builder.click(mid0)
	_check("build: a wall costs coins (%dc for it, %d of her walls up)" % [c0 - Game.coins, builder.edges().size()],
		c0 - Game.coins == HouseBuilder.price("wall") and builder.edges().size() == 1 and builder.rooms.is_empty())
	var roofs0 := roofs.size()
	for i in range(1, room.size()):
		builder.click(_edge_mid(room[i]))
	await _wait(0.3)
	var r: Dictionary = builder.rooms[0] if builder.rooms.size() == 1 else {}
	var rect: Rect2 = r["rects"][0] if not r.is_empty() else Rect2()
	var c := rect.get_center()
	var roofed := roofs.any(func(rf): return (rf["rect"] as Rect2).has_point(c) and rf["group"] == "house")
	var floored := house_root.find_children("*", "MeshInstance3D", true, false).any(func(m): return absf((m as Node3D).global_position.y - 0.02) < 0.05 and Vector2((m as Node3D).global_position.x, (m as Node3D).global_position.z).distance_to(c) < rect.size.length() * 0.5 and (m as Node3D).global_position.y < 0.1)
	_check("build: four walls close a room (%s, %dc in all) that joins the house with a doorway, gets a plank floor (%s) and a roof (%s, %d roofs from %d)" % [str(rect), c0 - Game.coins, floored, roofed, roofs.size(), roofs0],
		builder.rooms.size() == 1 and bool(r.get("joined", false)) and not builder.open_house.is_empty() and roofed and floored and c0 - Game.coins == HouseBuilder.price("wall") * 4)
	_set_cam_lock(false)
	cam_target = Vector3(c.x, 0, c.y)
	cam_dist = 16.0
	await _wait(1.0)
	await _shot("62_build_room.png")
	builder.set_tool("")
	set_mode(Mode.LIVE)
	# she walks from the house through the new doorway into the room
	player.position = Vector3(4.0, 0, 4.6)
	var path := _find_path(player.position, Vector3(c.x, 0, c.y))
	var steps := path.size()
	player.walk(path)
	await _walk_wait(15.0)
	var at := Vector2(player.position.x, player.position.z)
	_check("build: she walks from the house into the new room (path %d steps, %.2f m from its middle, underfoot '%s', roof lifted %s)" % [steps, at.distance_to(c), surface_at(player.position), not _roof_visible_at(c)],
		steps > 0 and at.distance_to(c) < 0.8 and surface_at(player.position) == "wood")
	await _wait(0.6)
	await _shot("62_build_room_inside.png")
	player.position = Vector3(10.5, 0, 7.5)
	await _wait(0.6)
	_check("build: from outside, the room keeps its roof on with the house (%s)" % _roof_visible_at(c), _roof_visible_at(c))
	await _opening_checks(room, c)
	await _floor_checks(c)
	# a new house: only on a plot bought from Gary
	var plot: Dictionary = HouseBuilder.plot_def("lane_end")
	var pr := HouseBuilder.plot_rect(plot)
	var hx := int(pr.position.x) + 2
	var hz := int(pr.position.y) + 4
	var house_edges := ["%d,%d,h" % [hx, hz], "%d,%d,h" % [hx + 2, hz], "%d,%d,v" % [hx, hz], "%d,%d,v" % [hx, hz + 2],
		"%d,%d,v" % [hx + 4, hz], "%d,%d,v" % [hx + 4, hz + 2], "%d,%d,h" % [hx + 2, hz + 4], "%d,%d,h" % [hx, hz + 4]]
	var refused := str(builder.check(house_edges[0])["why"])
	var gary := _villager("gary")
	var rows: Array = _villager_actions(gary).filter(func(a): return str(a.get("group", "")) == "Building plots")
	var row_ids: Array = rows.map(func(a): return a["id"])
	_villager_action(gary, "buy_plot:lane_end")
	await _wait(0.3)
	var standing := 0
	for el in god.els:
		if el.scenery and not el.cut and pr.grow(-0.3).has_point(Vector2(el.xf.origin.x, el.xf.origin.z)) and (el.kind.begins_with("tree_") or el.kind.begins_with("rock_")):
			standing += 1
	_check("build: no walls on land that isn't hers ('%s'); Gary sells building plots (%s), and Lane End is hers and cleared of trees and rocks (owned %s, %d left standing)" % [refused, str(row_ids), str(builder.owned()), standing],
		refused.contains("Gary") and row_ids.has("buy_plot:lane_end") and builder.owns("lane_end") and standing == 0)
	hud.hide_dialogue()
	set_mode(Mode.BUILD)
	builder.set_tool("wall")
	var c1 := Game.coins
	var first := builder.check(house_edges[0])
	builder.click(_edge_mid(house_edges[0]))
	var first_cost := c1 - Game.coins
	for i in range(1, house_edges.size()):
		builder.set_tool("door" if i == 6 else "wall")
		builder.click(_edge_mid(house_edges[i]))
	builder.set_tool("")
	var new_rooms: Array = builder.rooms.filter(func(rm): return rm["plot"] == "lane_end")
	_check("build: the first wall on the plot lays a new house's foundations (%dc = wall %d + fee %d), and eight walls with a doorway make a house of its own (%d rooms there, %d walls, joined %s)" % [first_cost, HouseBuilder.price("wall"), HouseBuilder.new_house_fee(), new_rooms.size(), builder.edges().size(), str(new_rooms.map(func(rm): return rm["joined"]))],
		bool(first["ok"]) and first_cost == HouseBuilder.price("wall") + HouseBuilder.new_house_fee() and new_rooms.size() == 1 and not bool(new_rooms[0]["joined"]) and builder.edges().size() == room.size() + 8)
	set_mode(Mode.LIVE)
	var hc := Vector3(hx + 2.0, 0, hz + 2.0)
	player.position = Vector3(hx + 3.0, 0, hz + 6.5) # outside her new front door
	var path2 := _find_path(player.position, hc)
	var steps2 := path2.size()
	player.walk(path2)
	await _walk_wait(15.0)
	_check("build: she walks in through the new house's doorway (%d steps, %.2f m from its middle, underfoot '%s')" % [steps2, Vector2(player.position.x, player.position.z).distance_to(Vector2(hc.x, hc.z)), surface_at(player.position)],
		steps2 > 0 and player.position.distance_to(hc) < 0.8 and surface_at(player.position) == "wood")
	# a piece from the catalogue goes inside it
	var lamp := Furniture.new()
	furniture_root.add_child(lamp)
	lamp.setup("lamp", 0)
	var inside_ok := _placement_valid(lamp, Vector3(hx + 1.0, 0, hz + 1.0))
	lamp.queue_free()
	_check("build: furniture can be placed inside the house she built (%s)" % inside_ok, inside_ok)
	player.position = Vector3(hx + 3.0, 0, hz + 7.5)
	_set_cam_lock(false)
	cam_target = hc
	cam_dist = 18.0
	await _wait(1.0)
	await _shot("62_build_new_house.png")
	# the world editor lists her walls; one deleted there comes down when it closes
	god.sync_built()
	var listed: int = god.els.filter(func(el): return el.built).size()
	var n_edges := builder.edges().size()
	var gone: Variant = null
	for el in god.els:
		if el.built and str(el.node.get_meta("edge")) == room[0]:
			gone = el
	if gone != null:
		gone.deleted = true
	god._return_built()
	var after := builder.edges().size()
	var room_open := builder.rooms.filter(func(rm): return rm["joined"]).is_empty()
	_check("build: the world editor lists her %d walls (%d), and one deleted there comes down (%d left, the room's open again %s); her walls stay out of the layout file (%s)" % [n_edges, listed, after, room_open, not JSON.stringify(god.layout()).contains("built_wall")],
		listed == n_edges and after == n_edges - 1 and room_open and not JSON.stringify(god.layout()).contains("built_wall"))
	var d2: Dictionary = builder.edges().duplicate()
	d2[room[0]] = "wall"
	Game.set_flag("built_walls", d2)
	builder.refresh_world()
	# a save keeps it all
	var walls_n := builder.edges().size()
	var rooms_n := builder.rooms.size()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	Game.flags.erase("built_walls")
	Game.flags.erase("plots_owned")
	builder.refresh_world()
	var cleared := builder.rooms.size()
	Game.from_dict(saved)
	builder.refresh_world()
	_check("build: the walls, rooms and plot survive a save (%d walls, %d rooms; %d with the flags gone; plot %s)" % [builder.edges().size(), builder.rooms.size(), cleared, str(builder.owned())],
		builder.edges().size() == walls_n and builder.rooms.size() == rooms_n and rooms_n == 2 and cleared == 0 and builder.owns("lane_end"))
	await _recolor_checks()
	# put the farm back as it was for the rest of the autotest
	Game.flags.erase("built_walls")
	Game.flags.erase("plots_owned")
	Game.flags.erase("built_paid")
	Game.flags.erase("house_openings")
	Game.flags.erase("floors")
	Game.flags.erase("floors_paid")
	builder.refresh_world()
	Game.coins = coins0
	Game.take_item("wood", Game.count("wood"))
	Game.add_item("wood", wood0)
	Game.hour = hour0
	_set_cam_lock(true)
	cam_dist = 23.0
	player.position = Vector3(10.5, 0, 6.5)
	await _wait(0.3)


## Openings (Alex, 2026-11-17): a window and then a door in a wall of the room just built, paid in
## coins and then in wood, the door walkable and swinging open for her, the window not walkable,
## each taken out for half back in what paid for it; sliding doors in one of the house's own walls,
## kept by a save; and a doorway from a save made before payments were kept, paid back in coins.
func _opening_checks(room: Array, c: Vector2) -> void:
	set_mode(Mode.BUILD)
	var wk: String = room[1]
	var mid := _edge_mid(wk)
	var cell := _cell(mid)
	# a window, in coins (she has no wood)
	builder.set_tool("window")
	var c0 := Game.coins
	builder.click(mid)
	var win_cost := c0 - Game.coins
	_check("build: the Window tool puts a window in her wall for coins (%s, %dc), and it doesn't let her through (%s)" % [builder.edges().get(wk), win_cost, not _walkable(cell)],
		builder.edges().get(wk) == "window" and win_cost == int(HouseBuilder.opening_cost("window")[0]) and not _walkable(cell))
	# swapped for a door, in wood: the window comes out with half its coins back
	Game.add_item("wood", 10)
	builder.set_tool("hdoor")
	c0 = Game.coins
	builder.click(mid)
	var back_c := Game.coins - c0
	var wood_used := 10 - Game.count("wood")
	var leaf := house_root.find_children("Door", "Node3D", true, false).size()
	_check("build: the Door tool swaps it for a door paid in wood (%s, %d wood, +%dc for the window), hung in the gap (%d), and she can walk through (%s)" % [builder.edges().get(wk), wood_used, back_c, leaf, _walkable(cell)],
		builder.edges().get(wk) == "hdoor" and wood_used == int(HouseBuilder.opening_cost("hdoor")[1]) and back_c == int(round(win_cost * 0.5)) and leaf >= 1 and _walkable(cell))
	set_mode(Mode.LIVE)
	player.position = Vector3(mid.x, 0, mid.z) + (Vector3(0, 0, 1.0) if wk.ends_with("h") else Vector3(1.0, 0, 0))
	await _wait(1.2)
	var opened := 0.0
	for dr in builder.doors:
		opened = maxf(opened, float(dr["open"]))
	_check("build: the door swings open as she comes up (%.2f)" % opened, opened > 0.9)
	_set_cam_lock(false)
	cam_target = mid
	cam_dist = 9.0
	await _wait(0.8)
	await _shot("62_build_door.png")
	set_mode(Mode.BUILD)
	builder.set_tool("hdoor")
	var w0 := Game.count("wood")
	c0 = Game.coins
	builder.click(mid)
	_check("build: clicked again, the door comes out with half its wood back, not coins (%s, +%d wood, +%dc)" % [builder.edges().get(wk), Game.count("wood") - w0, Game.coins - c0],
		builder.edges().get(wk) == "wall" and Game.count("wood") - w0 == int(HouseBuilder.opening_cost("hdoor")[1]) / 2 and Game.coins == c0)
	Game.take_item("wood", Game.count("wood"))
	# sliding doors in one of the house's own walls
	builder.set_tool("slide")
	var hk := ""
	for k in ["0,0,v", "0,2,v", "0,4,v", "0,-2,v", "8,4,v", "8,0,v"]:
		var oc := builder.opening_check(k, "slide")
		if not oc.is_empty() and bool(oc["ok"]):
			hk = k
			break
	var hmid := _edge_mid(hk) if hk != "" else Vector3.ZERO
	var front := builder.opening_check(HouseBuilder.FRONT_DOOR, "slide")
	c0 = Game.coins
	if hk != "":
		builder.click(hmid)
	var slide_cost := c0 - Game.coins
	var sliders := house_root.find_children("SlidingDoor", "Node3D", true, false).size()
	_check("build: sliding doors go in the house's own wall (%s: %s, %dc, %d hung, walkable %s), but not in its front door ('%s')" % [hk, builder.house_openings().get(hk), slide_cost, sliders, _walkable(_cell(hmid)), front.get("why", "")],
		hk != "" and builder.house_openings().get(hk) == "slide" and slide_cost == int(HouseBuilder.opening_cost("slide")[0]) and sliders >= 1 and _walkable(_cell(hmid)) and not bool(front.get("ok", true)))
	_set_cam_lock(false)
	cam_target = hmid
	cam_dist = 10.0
	await _wait(0.8)
	await _shot("62_build_house_slide.png")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	Game.flags.erase("house_openings")
	Game.flags.erase("built_paid")
	builder.refresh_world()
	Game.from_dict(saved)
	builder.refresh_world()
	_check("build: the house's sliding doors and what paid for them survive a save (%s, %s)" % [builder.house_openings().get(hk), str(Game.flag("built_paid", {}).get(hk, {}))],
		builder.house_openings().get(hk) == "slide" and (Game.flag("built_paid", {}) as Dictionary).has(hk))
	c0 = Game.coins
	builder.click(hmid)
	_check("build: taken out again, half the coins come back (+%dc) and the wall is whole (%s)" % [Game.coins - c0, not builder.house_openings().has(hk)],
		Game.coins - c0 == int(round(slide_cost * 0.5)) and not builder.house_openings().has(hk))
	# a doorway from an older save, with nothing kept of what paid for it
	var d: Dictionary = builder.edges().duplicate()
	d[wk] = "door"
	Game.set_flag("built_walls", d)
	builder.refresh_world()
	builder.set_tool("wall")
	c0 = Game.coins
	builder.click(mid)
	_check("build: a doorway from an older save comes down for half its price in coins (+%dc of %dc)" % [Game.coins - c0, HouseBuilder.price("door")],
		Game.coins - c0 == int(round(HouseBuilder.price("door") * 0.5)) and not builder.edges().has(wk))
	builder.set_tool("wall")
	builder.click(mid) # back up as the plain wall it was
	builder.set_tool("")
	set_mode(Mode.LIVE)
	player.position = Vector3(10.5, 0, 7.5)
	cam_target = Vector3(c.x, 0, c.y)


## Floors (Alex, 2026-11-17): blue carpet over the room she built for coins, oak boards over it for
## wood with the carpet's coins half back, white tile over the whole house, all kept by a save, and
## the planks back with half returned.
func _floor_checks(c: Vector2) -> void:
	set_mode(Mode.BUILD)
	var g := Vector3(c.x, 0, c.y)
	var cells := builder.floor_cells_at(c)
	var n := cells.size()
	Game.take_item("wood", Game.count("wood"))
	hud.wall_tool_chosen.emit("floor")
	hud.floor_pick.select(HouseBuilder.FLOORS.find("carpet_blue"))
	hud.floor_pick.item_selected.emit(HouseBuilder.FLOORS.find("carpet_blue"))
	await _wait(0.1)
	builder.hover_at(g)
	var ghosts := builder._floor_ghost.get_child_count() if builder._floor_ghost != null else 0
	var c0 := Game.coins
	builder.click(g)
	var laid := _laid_floors()
	var carpet_cost := c0 - Game.coins
	_check("build: the Floor tool lays blue carpet over the whole room she built for coins (%d cells, %d shown before the click, %d laid, %dc)" % [n, ghosts, laid.size(), carpet_cost],
		builder.tool == "floor" and hud.wall_btns["floor"].button_pressed and n >= 2 and ghosts == n and laid.size() == n \
		and carpet_cost == n * int(HouseBuilder.floor_cost("carpet_blue")[0]) and builder.floors().get(HouseBuilder.cell_key(cells[0])) == "carpet_blue")
	# oak boards over it, paid in wood: the carpet comes up with half its coins back
	Game.add_item("wood", 40)
	builder.set_floor_kind("wood_oak")
	c0 = Game.coins
	builder.click(g)
	var wood_used := 40 - Game.count("wood")
	_check("build: oak boards over it are paid in wood (%d wood) and the carpet comes up for half its coins (+%dc)" % [wood_used, Game.coins - c0],
		wood_used == n * int(HouseBuilder.floor_cost("wood_oak")[1]) and Game.coins - c0 == int(round(carpet_cost * 0.5)) and builder.floors().get(HouseBuilder.cell_key(cells[0])) == "wood_oak")
	Game.take_item("wood", Game.count("wood"))
	# white tile through the house
	var hq := Vector2(HOUSE_W * 0.5, 1.0)
	var hcells := builder.floor_cells_at(hq)
	builder.set_floor_kind("tile_white")
	c0 = Game.coins
	builder.click(Vector3(hq.x, 0, hq.y))
	var tile_cost := c0 - Game.coins
	laid = _laid_floors()
	_check("build: white tile through her house (%d cells, %dc, %d floors laid in all)" % [hcells.size(), tile_cost, laid.size()],
		hcells.size() == builder.house_cells().size() and tile_cost == hcells.size() * int(HouseBuilder.floor_cost("tile_white")[0]) and laid.size() == n + hcells.size())
	builder.hover_at(null)
	_set_cam_lock(false)
	cam_target = Vector3(HOUSE_W * 0.5, 0, 3.0)
	cam_dist = 16.0
	await _wait(0.8)
	await _shot("62_build_floors.png") # in build mode, the roofs lifted
	set_mode(Mode.LIVE)
	# a save keeps them
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	Game.flags.erase("floors")
	Game.flags.erase("floors_paid")
	builder.refresh_world()
	Game.from_dict(saved)
	builder.refresh_world()
	laid = _laid_floors()
	_check("build: the floors survive a save (%d laid)" % laid.size(), laid.size() == n + hcells.size())
	# the planks again: the tile comes up, half its coins back
	set_mode(Mode.BUILD)
	builder.set_tool("floor")
	builder.set_floor_kind("planks")
	c0 = Game.coins
	builder.click(Vector3(hq.x, 0, hq.y))
	var w0 := Game.count("wood")
	builder.click(g)
	_check("build: plank boards take them up again, half back in what paid (+%dc for the tile, +%d wood for the oak, %d left)" % [Game.coins - c0, Game.count("wood") - w0, builder.floors().size()],
		Game.coins - c0 == int(round(tile_cost * 0.5)) and Game.count("wood") - w0 == n * int(HouseBuilder.floor_cost("wood_oak")[1]) / 2 and builder.floors().is_empty())
	Game.take_item("wood", Game.count("wood"))
	builder.set_tool("")
	set_mode(Mode.LIVE)
	player.position = Vector3(10.5, 0, 7.5)


## The laid floors standing now (house_builder.gd _draw_floors()).
func _laid_floors() -> Array:
	return house_root.find_children("*", "MeshInstance3D", true, false).filter(func(n: Node): return n.has_meta("floor") and not n.is_queued_for_deletion())


## The middle of a grid edge, on the ground (house_builder.gd keys).
func _edge_mid(k: String) -> Vector3:
	var e := HouseBuilder.ends(k)
	var m: Vector2 = ((e[0] as Vector2) + (e[1] as Vector2)) * 0.5
	return Vector3(m.x, 0, m.y)


## Whether a roof over this ground point is showing now.
func _roof_visible_at(q: Vector2) -> bool:
	for rf in roofs:
		if (rf["rect"] as Rect2).has_point(q) and is_instance_valid(rf["node"]) and (rf["node"] as Node3D).visible:
			return true
	return false


## Colours for her furniture (furniture.gd set_color, furniture.json "palettes"): picked up in build
## mode, the rocking chair offers its own colour and six fabrics; a new one costs a few coins and
## tints only its cushion, keeping the plaid; the save keeps it; its own colour back is free.
func _recolor_checks() -> void:
	var chair: Furniture = null
	for f in furniture:
		if f.item_id == "rocking_chair":
			chair = f
	if chair == null:
		_check("colours: her rocking chair is there to recolour", false)
		return
	player.position = chair.position + Vector3(2.5, 0, 2.5)
	_set_cam_lock(false)
	cam_target = chair.position
	cam_dist = 9.0
	set_mode(Mode.BUILD)
	await _wait(0.8)
	_build_click(cam.unproject_position(chair.global_position + Vector3(0, 0.5, 0)), false)
	await _wait(0.2)
	var held := ghost == chair
	var swatches := hud.color_btns.size()
	var c0 := Game.coins
	recolor_held("wine")
	var mats := 0
	var tinted := 0
	for m in chair.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mats += 1
			var o := mi.get_surface_override_material(i) as BaseMaterial3D
			if o != null and o.albedo_color.is_equal_approx(Color.html("#8a2f3b")) and o.albedo_texture != null:
				tinted += 1
	_cancel_ghost() # set back down where it was
	var entry := furniture_entry(chair)
	_check("colours: the rocking chair picked up in build mode (%s) offers %d colours; Wine costs %dc and tints its cushion's plaid only (%d of %d parts), and the save keeps it (%s)" % [held, swatches, c0 - Game.coins, tinted, mats, str(entry.get("c", ""))],
		held and swatches == 7 and c0 - Game.coins == recolor_price() and tinted == 1 and mats > 2 and str(entry.get("c", "")) == "wine")
	set_mode(Mode.LIVE)
	cam_dist = 5.5
	await _wait(1.0)
	await _shot("62_recolor.png")
	var c1 := Game.coins
	chair.set_color("")
	var spawned := _spawn_furniture("sofa", Vector3(-30, 0, -30), 0)
	spawned.set_color("denim")
	var e2 := furniture_entry(spawned)
	furniture.erase(spawned)
	spawned.queue_free()
	_check("colours: its own colour back costs nothing (%dc), and a sofa takes the fabrics too (%s)" % [c1 - Game.coins, str(e2.get("c", ""))], c1 == Game.coins and str(e2.get("c", "")) == "denim")


## The online store (online_store.gd, data/store_orders.json): the computer in the catalogue, no orders
## until she owns one, then orders for wild-fibre sweaters; "Use the computer…" puts her at its screen in
## first person; a knitted fox sweater remembers its fibre and fills a fox order, scoring five stars
## sent at once and fewer sent late; an expired order costs her rating; a better rating brings orders
## sooner and more at once; the coins come the next morning; the state keeps through a save. Saves
## 63_store_screen.png, 63_store_sent.png and 63_store_after.png.
func _store_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	Game.hour = 11.0
	var keep := {"coins": Game.coins, "s": Game.sweaters.duplicate(), "d": Game.sweater_designs.duplicate(),
		"f": Game.sweater_fibres.duplicate(), "inv": Game.inv.duplicate(), "store": Game.flags.get("store", null),
		"request": Game.flags.get("request", null), "day": Game.day, "hour": Game.hour,
		"wq": Game.worn_quality, "wd": Game.worn_design, "w": Game.wardrobe.duplicate(), "xp": Game.knit_xp}
	Game.flags.erase("store")
	Game.flags.erase("request") # a local's fibre request would claim the fox sweater first
	var info: Dictionary = Catalog.ITEMS.get("computer", {})
	_check("the computer is a catalogue piece and a big purchase (%s, %dc, needles top out at 1500c)" % [str(info.get("cat", "?")), int(info.get("price", 0))],
		str(info.get("shop", "")) == "indoors" and int(info.get("price", 0)) >= 2000 and Catalog.has_builder("computer"))
	for f in furniture.filter(func(x): return is_instance_valid(x) and x.item_id == "computer"):
		furniture.erase(f)
		f.queue_free()
	await _wait(0.2)
	store.update()
	_check("no computer, no orders (%s)" % str(Game.flags.get("store", {})), not store.started() and store.orders().is_empty())
	var comp := _spawn_furniture("computer", Vector3(5.6, 0, 5.3), 2)
	_rebuild_grid()
	_check("the computer has a screen to look at", comp.find_child("screen", true, false) != null)
	store.update()
	var first: Array = store.orders()
	var sane := true
	for o in first:
		sane = sane and wildlife.is_fibre(str(o["fibre"])) and int(o["pay"]) > 0 \
			and int(o["stars"]) >= Sweaters.stars_for(wildlife.knit_floor(str(o["fibre"])))
	_check("once it stands in her house, orders come in, each for a wild fibre's sweater (%s, rating %.1f)" % [str(first.map(func(o): return "%s %d★ %dc" % [o["fibre"], o["stars"], o["pay"]])), store.rating()],
		store.started() and first.size() == int(store.data.get("seed_orders", 2)) and sane and is_equal_approx(store.rating(), float(store.data.get("start_rating", 3.0))))
	var acts := _actions_for(comp)
	_check("its menu says 'Use the computer…' with the orders waiting (%s)" % str(acts.map(func(a): return a["label"])),
		acts.size() == 1 and str(acts[0]["id"]) == "computer" and str(acts[0]["label"]).begins_with("Use the computer…"))
	# a fox sweater knitted with its fibre remembers it; a plain one doesn't
	Game.add_sweater(3, "")
	Game.add_item("wool", 2)
	Game.add_item("fox_fibre", 1)
	_knit_fibre = "fox_fibre"
	_finish_knit(3)
	await _wait(1.0) # its knit_done event plays nothing outside Act 1
	hud.hide_dialogue()
	var fox_i: int = Game.sweater_fibres.find("fox_fibre")
	_check("a sweater knitted with fox fluff is kept as a fox sweater in her bag (%s)" % str(Game.sweater_fibres),
		fox_i >= 0 and Game.sweater_fibres.size() == Game.sweaters.size() and Game.sweater_fibres.count("fox_fibre") == 1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game.to_dict()))
	_check("the save keeps which sweater was knitted with what", (saved.get("sweater_fibres", []) as Array).has("fox_fibre"))
	var fox := store.place_order(-1.0, "fox_fibre", 2)
	var lynx := store.place_order(-1.0, "lynx_fibre", 4)
	_check("an order can ask for a fibre and stars (%s %d★, %s %d★)" % [fox["fibre"], fox["stars"], lynx["fibre"], lynx["stars"]],
		str(fox["fibre"]) == "fox_fibre" and int(fox["stars"]) == 2 and store.sweater_for(fox) == fox_i and store.sweater_for(lynx) < 0)
	# at the screen
	player.walk([])
	player.position = _stand_point(comp)
	await _wait(0.3)
	_perform(comp, "computer")
	await _wait(1.2)
	var r: Rect2 = store.screen_rect()
	_check("'Use the computer…' puts her at its screen in first person, the page on it (active %s, first person %s, locked %s, page %s)" % [store.active, fps.active, fps.locked, str(r)],
		store.active and fps.active and fps.locked and r.size.x >= 480.0 and absf(cam.fov - OnlineStore.FOV) < 0.5)
	var k: int = store.orders().find(fox)
	store.select(k)
	await _wait(0.4)
	await _shot("63_store_screen.png")
	var coins0 := Game.coins
	var n0: int = store.orders().size()
	var nsw := Game.sweaters.size()
	var want: int = store.pay_for(fox, int(Game.sweaters[fox_i]))
	var rate0: float = store.rating()
	store.handle_key(KEY_ENTER)
	await _wait(0.4)
	await _shot("63_store_sent.png")
	_check("Enter sends the fox sweater for the fox order: gone from her bag and the list, five stars sent at once, %dc to come in the morning, none yet (rating %.2f -> %.2f)" % [store.coming(), rate0, store.rating()],
		store.orders().size() == n0 - 1 and Game.sweaters.size() == nsw - 1 and Game.sweater_fibres.find("fox_fibre") < 0
		and is_equal_approx(float(store.state().get("last_score", 0.0)), 5.0) and store.coming() == want and Game.coins == coins0 and store.rating() > rate0)
	store.select(store.orders().find(lynx))
	_check("she can't send the lynx order without a lynx sweater", not store.send_selected() and store.orders().find(lynx) >= 0)
	# a late one scores less
	Game.add_sweater(3, "")
	Game.sweater_fibres[Game.sweater_fibres.size() - 1] = "fox_fibre"
	var late := store.place_order(-1.0, "fox_fibre", 2)
	late["placed"] = float(late["placed"]) - store.expire_hours(late) * 0.8
	var late_score: float = store.score_for(late)
	store.fill(store.orders().find(late))
	_check("an order sent late scores fewer stars (%.1f after %.0f of %.0f h)" % [late_score, store.age(late), store.expire_hours(late)],
		late_score < 3.0 and late_score > 1.0 and is_equal_approx(float(store.state().get("last_score", 0.0)), late_score))
	# one left to expire costs her
	var rate1: float = store.rating()
	var exp0 := int(store.state().get("expired", 0))
	var old := store.place_order(-1.0, "angora", 0)
	old["placed"] = float(old["placed"]) - store.expire_hours(old) - 0.5
	store.update()
	_check("an order left past its time expires and lowers her rating (%.2f -> %.2f)" % [rate1, store.rating()],
		store.orders().find(old) < 0 and int(store.state().get("expired", 0)) == exp0 + 1 and store.rating() < rate1)
	# a better rating brings orders sooner and more of them at once
	var sc0: Array = store.scores().duplicate()
	store.state()["scores"] = [1.0]
	var slow: float = store.interval()
	var few: int = store.max_open()
	store.state()["scores"] = [5.0]
	var fast: float = store.interval()
	var many: int = store.max_open()
	_check("a five-star shop gets orders every %.0f h, up to %d open; a one-star shop every %.0f h, up to %d" % [fast, many, slow, few],
		fast < slow and many > few)
	store.state()["orders"] = []
	store.state()["next_at"] = OnlineStore.now_h() - 30.0 # a long night: what came in is waiting, up to the cap
	store.update()
	var after: int = store.orders().size()
	store.state()["next_at"] = OnlineStore.now_h() - 0.01
	store.state()["orders"] = []
	store.update()
	_check("orders keep coming: %d after a long night (at most %d), one more when the timer's up (%d)" % [after, many, store.orders().size()],
		after > 1 and after <= many and store.orders().size() == 1)
	store.state()["orders"] = []
	store.state()["next_at"] = OnlineStore.now_h() - 200.0 # the computer gone for days, then back
	var exp_a := int(store.state().get("expired", 0))
	store.update()
	var oldest := 0.0
	for o in store.orders():
		oldest = maxf(oldest, store.age(o))
	_check("back after days away, she finds no pile of old orders: none older than a night, none expired at once (%d orders, oldest %.1f h)" % [store.orders().size(), oldest],
		store.orders().size() >= 1 and oldest <= float(store.data.get("catch_up_hours", 12.0)) + 0.01 and int(store.state().get("expired", 0)) == exp_a)
	store.state()["scores"] = sc0
	# the state keeps through a save: numbers come back from JSON as floats
	var st: Dictionary = JSON.parse_string(JSON.stringify(store.state()))
	var rate2: float = store.rating()
	var due0: int = store.coming()
	var n2: int = store.orders().size()
	Game.flags["store"] = st
	_check("the store keeps through a save (rating %.2f, %d orders, %dc coming)" % [store.rating(), store.orders().size(), store.coming()],
		is_equal_approx(store.rating(), rate2) and store.coming() == due0 and due0 > want and store.orders().size() == n2)
	# the morning post
	var due: int = store.coming()
	coins0 = Game.coins
	store._on_day_started(Game.day)
	_check("the next morning's post brings the coins (+%d)" % (Game.coins - coins0),
		Game.coins - coins0 == due and store.coming() == 0 and int(store.state().get("earned", 0)) == due)
	store.handle_key(KEY_ESCAPE)
	await _wait(0.5)
	_check("Esc steps her back from the computer, where she can walk, with the overhead camera back (walkable %s)" % _walkable(_cell(player.position)),
		not store.active and not fps.active and not fps.locked and _walkable(_cell(player.position)))
	cam_target = player.position + Vector3(0, 0.9, 0)
	await _wait(0.8)
	await _shot("63_store_after.png")
	# put it all back
	furniture.erase(comp)
	comp.queue_free()
	_rebuild_grid()
	Game.coins = keep["coins"]
	Game.sweaters = keep["s"]
	Game.sweater_designs = keep["d"]
	Game.sweater_fibres = keep["f"]
	Game.inv = keep["inv"]
	Game.worn_quality = keep["wq"]
	Game.worn_design = keep["wd"]
	Game.wardrobe = keep["w"]
	Game.knit_xp = keep["xp"]
	for key in ["store", "request"]:
		if keep[key] == null:
			Game.flags.erase(key)
		else:
			Game.flags[key] = keep[key]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	await _wait(0.2)

# --- wolves at night (wolves.gd, data/wolves.json) -------------------------------------------

## Her flock at `n` sheep, in the pen (the wolves check takes them and puts them back).
func _set_flock(n: int) -> void:
	while sheep_list.size() > n:
		var s = sheep_list.pop_back()
		s.queue_free()
	Game.sheep_count = n
	while sheep_list.size() < n:
		_add_sheep()


## Wolves: nothing comes while nothing is at risk; a forced night brings the howl, the toast and the
## pack walking in; Nora's rush and the dog's barks see them off, the bigger taking more; a missed
## window costs one animal and the morning says which; a night slept through can cost one too; the
## barn (housed sheep, rented stalls) keeps them safe; a raid and the tally survive a save.
func _wolf_checks() -> void:
	hud.tip_panel.visible = false
	hud.hide_dialogue()
	var keep := {"flags": Game.flags.duplicate(true), "day": Game.day, "hour": Game.hour, "sheep": Game.sheep_count, "clock": Game.time_running,
		"jog": autotest_jog, "cd": cam_dist, "bed": flock_bedtime, "pos": player.position, "follow": cam_follow}
	player.walk([])
	autotest_jog = false
	Game.time_running = false
	flock_bedtime = false
	Wolves.on = true
	wolves.clear()
	wildlife.clear()
	for k in ["wolves", "wolf_note", "penned", "wild_gone", "wild", "barn_rent_due", "barn_rent_owed", "wolves_tamed"]:
		Game.flags.erase(k)
	Game.flags["act1_done"] = true
	Game.hour = 20.0
	var home: Vector3 = wolves.pen_centre()
	# nothing at risk: the night passes quietly
	_set_flock(0)
	wildlife.build()
	wolves.force_next = true
	Game.hour = 21.5
	await _wait(0.3)
	_check("with nothing in the pens the wolves don't come (raid %s, night rolled %s)" % [wolves.active(), int(wolves.state().get("night", -1)) == Game.day],
		not wolves.active() and int(wolves.state().get("night", -1)) == Game.day)
	# a forced wolf night: the howl, the toast, the pack walking in from the woods
	Game.set_flag("penned", [{"species": "rabbit", "key": "pen_rabbit_901"}, {"species": "fox", "key": "pen_fox_902"}])
	_set_flock(2)
	wildlife.build()
	await _wait(0.3)
	var risk0: int = wolves.at_risk().size()
	var howls0 := int(audio.played.get("howl", 0))
	Game.hour = 20.0
	var s0: Dictionary = wolves.state()
	s0.erase("night")
	Game.set_flag("wolves", s0)
	wolves.force_next = true
	Game.hour = 21.5
	await _wait(0.3)
	var n0: int = wolves.pack.size()
	var toast0: String = hud.toast_label.text
	var models_ok: bool = wolves.pack.all(func(w): return w._model != null and w._anim != null and w._anim.has_animation("Walk"))
	var d_start: float = wolves.pack[0].position.distance_to(home) if n0 > 0 else 0.0
	_set_cam_lock(false) # the camera on the pack, not on her
	cam_dist = 16.0
	for i in 30: # long enough for the warning to settle
		cam_target = wolves.pack[0].position if n0 > 0 else home
		await _wait(0.1)
	var walking: String = wolves.pack[0].current_loop() if n0 > 0 else ""
	var toast_box: Vector2 = hud.toast_panel.size
	await _shot("63_wolves_coming.png")
	_check("a forced wolf night: %d animals at risk, a howl (%d), the toast ('%s', a small box %.0f x %.0f px), %d wolves (%s) %.0f m off in the woods, walking in (%s), the models loaded %s, %.0f s to see them off" % [
		risk0, int(audio.played.get("howl", 0)) - howls0, toast0.left(48), toast_box.x, toast_box.y, n0, str(wolves.pack.map(func(w): return w.size_id)), d_start, walking, models_ok, wolves.raid_left],
		risk0 == 4 and toast_box.y < 110.0 and toast_box.x <= 680.0 and wolves.active() and int(audio.played.get("howl", 0)) == howls0 + 1 and toast0.contains("howl") and n0 >= 1 and n0 <= 3
		and d_start > 20.0 and walking == "Walk" and models_ok and wolves.raid_left > 40.0)
	# scaring them off: three of them at the pen; Nora rushes the small one, the dog barks at the rest
	wolves.clear()
	wolves.start_raid(3)
	await _wait(0.1)
	for w in wolves.pack:
		w.position = w.goal
		w._path = []
	var small = wolves.pack.filter(func(w): return w.size_id == "small")[0]
	var medium = wolves.pack.filter(func(w): return w.size_id == "medium")[0]
	var large = wolves.pack.filter(func(w): return w.size_id == "large")[0]
	var nerves := [small.nerve, medium.nerve, large.nerve]
	var out_dir: Vector3 = (small.goal - home)
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	var side := Vector3(-out_dir.z, 0, out_dir.x)
	for w in [medium, large]: # the other two along the fence, out of her rush at the small one
		w.goal += side * 12.0
		w.position = w.goal
	var start: Vector3 = small.position + out_dir * 11.0
	var sc = _nearest_walkable(_cell(start), start)
	player.position = _cell_center(sc) if sc != null else start
	player.walk([])
	if dog:
		dog.position = player.position + Vector3(1.2, 0, 0.8)
		dog.path = []
	_set_cam_lock(false)
	cam_target = small.position + side * 6.0 + out_dir * 3.0
	cam_dist = 19.0
	await _wait(0.6)
	await _shot("63_wolves_at_pen.png")
	autotest_jog = true
	var tw := 0.0
	var closest := INF
	var top_speed := 0.0
	while is_instance_valid(small) and not small.fleeing and tw < 12.0:
		if player.path.is_empty():
			player.walk(_find_path(player.position, small.position))
		closest = minf(closest, Vector2(player.position.x - small.position.x, player.position.z - small.position.z).length())
		top_speed = maxf(top_speed, player.speed)
		await _wait(0.1)
		tw += 0.1
	autotest_jog = false
	player.walk([])
	var small_ran: bool = not is_instance_valid(small) or small.fleeing
	var others_stay: bool = not medium.fleeing and not large.fleeing
	_check("the wolves have more nerve the bigger they are (%s), and Nora running at the small one sends it off (%s after %.1f s; she came within %.1f m at up to %.1f m/s, walking pace %.1f) while the others hold (%s)" % [
		str(nerves), small_ran, tw, closest, top_speed, player.walk_speed, others_stay],
		nerves == [1, 2, 3] and small_ran and others_stay and wolves.active())
	toggle_dog(true)
	hud.hide_dialogue()
	dog.position = (medium.position + large.position) * 0.5 + out_dir * 2.0
	dog.path = []
	cam_target = dog.position
	await _wait(BARK_WAIT)
	dog_bark()
	await _wait(0.1)
	var after1 := [medium.nerve, large.nerve, medium.fleeing, large.fleeing]
	await _shot("63_wolves_bark.png")
	for i in 4:
		if not wolves.active():
			break
		await _wait(BARK_WAIT)
		for w in wolves.pack:
			if is_instance_valid(w) and not w.fleeing:
				dog.position = w.position + out_dir * 2.0
				break
		dog_bark()
	await _wait(0.4)
	await _shot("63_wolves_flee.png")
	toggle_dog(false)
	hud.hide_dialogue()
	var st: Dictionary = wolves.state()
	_check("as the dog, a bark takes nerve from every wolf near (after one: medium %d, large %d, running %s %s); the big one takes three, and they're seen off ('%s'; seen off %d, raid saved %s, nothing lost %s)" % [
		after1[0], after1[1], after1[2], after1[3], hud.toast_label.text.left(30), int(st.get("seen_off", 0)), st.has("raid"), wolves.at_risk().size() == 4],
		after1[0] == 1 and after1[1] == 2 and after1[2] == false and after1[3] == false and not wolves.active() and int(st.get("seen_off", 0)) == 1
		and not st.has("raid") and wolves.at_risk().size() == 4)
	# a bark from her side does nothing: only the player herds and scares
	wolves.start_raid(1)
	await _wait(0.1)
	var w1 = wolves.pack[0]
	w1.position = w1.goal
	w1._path = []
	dog.position = w1.position + Vector3(1.0, 0, 0)
	var reached: int = wolves.barked(dog.position)
	_check("beside Nora the dog's bark doesn't reach the wolves (%d reached, nerve %d)" % [reached, w1.nerve], reached == 0 and w1.nerve == 2)
	# missing the window: they take one, and the morning says which
	wolves.clear()
	st = wolves.state()
	st["night"] = Game.day
	Game.set_flag("wolves", st)
	var penned0: int = wildlife.penned_list().size()
	var sheep0 := Game.sheep_count
	wolves.start_raid(1, 2.5)
	await _wait(0.1)
	var w_in = wolves.pack[0] # a few steps out from the pen, coming in
	w_in.position = w_in.goal + (w_in.den - w_in.goal).normalized() * 3.0
	w_in.go_to(w_in.goal)
	_set_cam_lock(false)
	cam_target = w_in.goal
	cam_dist = 15.0
	await _wait(1.6)
	await _shot("63_wolves_missed.png")
	await _wait(1.2)
	var note_now: String = str(Game.flag("wolf_note", ""))
	var taken := penned0 + sheep0 - wildlife.penned_list().size() - Game.sheep_count
	var morning: String = wolves.morning_note(Game.day + 1)
	_check("missing the window loses one animal (%d gone: %d penned, %d sheep left, %d sheep nodes) and the morning says which ('%s')" % [taken, wildlife.penned_list().size(), Game.sheep_count, sheep_list.size(), morning.strip_edges()],
		taken == 1 and not wolves.active() and sheep_list.size() == Game.sheep_count and note_now != "" and morning.contains(note_now)
		and (morning.contains("rabbit") or morning.contains("fox") or morning.contains("sheep")) and Game.flag("wolf_note", "") == "" and int(wolves.state().get("lost", 0)) == 1)
	# a night slept through: rolled in the morning, and a hit costs one while she slept
	st = wolves.state()
	st["night"] = Game.day - 2
	Game.set_flag("wolves", st)
	var risk1: int = wolves.at_risk().size()
	wolves.force_next = true
	Game.hour = 6.0
	var slept: String = wolves.morning_note(Game.day)
	_check("a night she slept through is rolled in the morning, and the wolves took one while she slept ('%s', %d -> %d at risk)" % [slept.strip_edges(), risk1, wolves.at_risk().size()],
		slept.contains("While you slept") and wolves.at_risk().size() == risk1 - 1 and not wolves.active())
	# the barn: sheep in their stalls and animals in rented stalls are safe
	Game.hour = 21.5 # bedtime: the flock keeps to its stalls
	flock_bedtime = true
	st = wolves.state()
	st["night"] = Game.day # tonight is rolled only by this check's own calls
	Game.set_flag("wolves", st)
	Game.set_flag("penned", [{"species": "rabbit", "key": "pen_rabbit_903"}, {"species": "fox", "key": "pen_fox_904"}])
	_set_flock(2)
	wildlife.build()
	await _wait(0.2)
	var barn_ok: bool = World.barn_ready()
	if barn_ok:
		for i in sheep_list.size():
			var stall: Dictionary = World.barn_stall(i)
			sheep_list[i].place(stall["stall"], true, stall["yaw"])
	var housed_risk: int = wolves.at_risk().size()
	Game.set_flag("barn_rent_due", Game.day + 10)
	Game.set_flag("barn_rent_owed", 0)
	var rented: bool = wildlife.stalls_rented()
	var risk_rented: int = wolves.at_risk().size()
	wolves.force_next = true
	var came: bool = wolves.roll(Game.day, false)
	var safe_all: bool = not came and not wolves.active() and wildlife.penned_list().size() == 2 and Game.sheep_count == 2
	cam_target = World.barn.global_position if World.barn and is_instance_valid(World.barn) else home
	await _wait(0.4)
	await _shot("63_wolves_barn.png")
	Game.set_flag("barn_rent_owed", 60) # behind with the rent: the stalls aren't hers
	var risk_owed: int = wolves.at_risk().size()
	wolves.force_next = true
	var came_owed: bool = wolves.roll(Game.day, false)
	_check("the barn keeps them safe: sheep in their stalls (%s) are off the wolves' list (%d at risk, the two wild ones), and with the stalls rented (%s) nobody is (%d), so a forced night brings nothing (%s); behind with the rent the wild ones are at risk again (%d) and the wolves come (%s)" % [
		barn_ok, housed_risk, rented, risk_rented, safe_all, risk_owed, came_owed],
		barn_ok and housed_risk == 2 and rented and risk_rented == 0 and safe_all and risk_owed == 2 and came_owed and wolves.active())
	# a save: the raid in progress, its seconds and the tally come back
	await _wait(0.2)
	wolves.raid_left = 30.0
	wolves._note_raid()
	var pack_n: int = wolves.pack.size()
	var saved := JSON.parse_string(JSON.stringify(Game.to_dict())) as Dictionary
	wolves.clear()
	Game.flags.erase("wolves")
	Game.flags = (saved["flags"] as Dictionary).duplicate(true) # as Game.from_dict() reads them, without reloading the rest of the game (the checks after this one count on it)
	wolves._resumed = false
	await _wait(0.3)
	var st2: Dictionary = wolves.state()
	_check("a save keeps the wolves: the raid comes back with its pack (%d of %d) and about its seconds (%.0f), and the tally (seen off %d, lost %d)" % [wolves.pack.size(), pack_n, wolves.raid_left, int(st2.get("seen_off", 0)), int(st2.get("lost", 0))],
		wolves.active() and wolves.pack.size() == pack_n and wolves.raid_left > 25.0 and wolves.raid_left <= 30.0 and int(st2.get("seen_off", 0)) == 1 and int(st2.get("lost", 0)) == 2)
	# taming isn't built: the hook keeps the wild ones away once it is
	wolves.clear()
	Game.set_flag("wolves_tamed", true)
	wolves.force_next = true
	var came_tamed: bool = wolves.roll(Game.day, false)
	_check("the taming hook: once tamed (wolves_tamed) no wild wolves come (%s)" % came_tamed, not came_tamed and not wolves.active())
	# put it all back
	wolves.clear()
	wolves.force_next = false
	Wolves.on = false
	wildlife.clear()
	Game.flags = keep["flags"]
	Game.day = keep["day"]
	Game.hour = keep["hour"]
	_set_flock(int(keep["sheep"]))
	Game.time_running = keep["clock"]
	autotest_jog = keep["jog"]
	cam_dist = keep["cd"]
	flock_bedtime = keep["bed"]
	player.position = keep["pos"]
	player.walk([])
	if dog:
		dog.position = player.position + Vector3(1.2, 0, 0.8)
		dog.path = []
	cam_target = player.position
	_set_cam_lock(keep["follow"])
	hud.hide_dialogue()
