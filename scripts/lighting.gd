extends Node
## The live half of the game's lighting, on top of main.gd's sun, sky and Environment
## (_setup_environment, _update_lighting):
## - Morning mist: a low, patchy layer of volumetric fog over the whole map (shaders/mist.gdshader),
##   thickest just after first light and gone by mid-morning. The low sun's shadows through it are
##   the light shafts between the tree branches; the sun's fog energy and forward scattering go up
##   with it. On Low graphics (no volumetric fog) a plain height fog stands in.
## - SDFGI on High: light bouncing across the whole scene and the sky shut out under the trees and
##   inside buildings, which the screen-space effects (SSIL, SSAO) can't see off screen.
## The other half is baked: art/world_assets/light_bake/build.py path-traces each prop's own contact
## shadows and bounce light in Cycles into an atlas the prop's material reads as ambient occlusion.

## The map's extent (World and Town scatter from about x -24 to 92, z -40 to 34), plus a margin
## for the mist volume's soft edges.
const MIST_CENTRE := Vector3(34.0, 2.5, -3.0)
const MIST_SIZE := Vector3(150.0, 7.0, 100.0)
const MIST_DENSITY := 0.16 # at its thickest, at ground level
const SHAFT_FOG := 0.007 # thin fog in the air above the mist, for the shafts to show in

## The props that carry the Cycles light bake (art/world_assets/light_bake/build.py, PROPS): the
## autotest checks each one still does, since rebuilding a prop with its own build.py drops it.
const BAKED := [
	"armchair", "bakery_counter", "bakery_stall", "barn", "bench_park", "bench_park_short",
	"bookshelf", "bread_rack", "brick_oven", "chalkboard_sign", "coffee_table", "daisy_crate",
	"dining_table", "fence_post", "fence_rails", "fence_section", "filing_cabinet", "fireplace",
	"flour_sacks", "gran_bed", "hay_bale", "kitchen", "lamp", "lamp_post", "market_stall",
	"milk_churn", "office_desk", "plaza_fountain", "rocking_chair", "rug_red", "scarecrow",
	"shop_counter", "sofa", "spinning_wheel", "sweater_rack", "trash_can", "wardrobe", "yarn_shelf"
]

## The autotest's picture of the light (48_light_*.png): the north edge of the woods behind the farm.
const SHOT_TARGET := Vector3(8.0, 0.0, -24.0)
const SHOT_DIST := 22.0
const SHOT_YAW := 200.0
const SHOT_PITCH := 18.0

var main: Node
var env: Environment
var sun: DirectionalLight3D
var mist_volume: FogVolume
var mist_mat: ShaderMaterial
var mist := 0.0 # 0..1, how much morning mist there is now
var mist_enabled := true # the frame-cost probe (--fpsprobe) switches it off to time it
var gfx := 2
var _sun_fog_energy := 1.3
var _anisotropy := 0.6
var _ambient_inject := 0.04


## Morning mist by the hour: rising from 4:45, at its thickest from about 6:15 (she wakes at 6),
## thinning from 7:45 and gone by 10:15.
static func morning(h: float) -> float:
	return smoothstep(4.75, 6.25, h) * (1.0 - smoothstep(7.75, 10.25, h))


func setup(m: Node) -> void:
	main = m
	env = m.env
	sun = m.sun
	_sun_fog_energy = sun.light_volumetric_fog_energy
	_anisotropy = env.volumetric_fog_anisotropy
	_ambient_inject = env.volumetric_fog_ambient_inject
	mist_mat = ShaderMaterial.new()
	mist_mat.shader = preload("res://shaders/mist.gdshader")
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 32
	tex.depth = 64
	tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.06
	fn.fractal_octaves = 3
	tex.noise = fn
	mist_mat.set_shader_parameter("noise", tex)
	mist_volume = FogVolume.new()
	mist_volume.name = "MorningMist"
	mist_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	mist_volume.size = MIST_SIZE
	mist_volume.position = MIST_CENTRE
	mist_volume.material = mist_mat
	add_child(mist_volume)


func apply_graphics(level: int) -> void:
	gfx = level
	# SDFGI: big-scale bounce and sky occlusion. High only: it costs a few milliseconds a frame.
	env.sdfgi_enabled = level == 2
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_energy = 0.9
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT


## Called every frame from main._update_lighting, after it has set the day's fog and sun.
## dl: Game.daylight().
func update(rain: float, dl: float) -> void:
	var h: float = Game.hour
	# rain brings its own grey haze; the morning mist burns off in it too
	mist = morning(h) * (1.0 - 0.7 * rain) if mist_enabled else 0.0
	var lit := clampf(dl * 1.5, 0.0, 1.0) # before sunrise the mist is there but nothing shines through it
	mist_mat.set_shader_parameter("density", MIST_DENSITY * mist)
	var tint := Color(1.0, 0.95, 0.9).lerp(Color(0.75, 0.8, 0.95), 1.0 - lit)
	mist_mat.set_shader_parameter("albedo", tint)
	mist_volume.visible = mist > 0.01
	env.volumetric_fog_density += SHAFT_FOG * mist
	env.volumetric_fog_enabled = gfx >= 1 and (env.volumetric_fog_density > 0.0006 or mist > 0.01)
	# shafts: the low sun lights the mist strongly, mostly forward (towards the camera when you look at the sun)
	sun.light_volumetric_fog_energy = lerpf(_sun_fog_energy, 3.2, mist * lit)
	env.volumetric_fog_anisotropy = lerpf(_anisotropy, 0.72, mist)
	# a little of the sky's light in the mist, so it glows softly in the shade rather than going dark
	env.volumetric_fog_ambient_inject = lerpf(_ambient_inject, 0.35, mist)
	# Low graphics has no volumetric fog: a plain ground fog gives the look of the mist from afar
	env.fog_height = 0.6
	env.fog_height_density = (0.32 if gfx == 0 else 0.1) * mist
	env.fog_sun_scatter = 0.25 * mist * lit


## How many of a model's surfaces carry the Cycles light bake (ambient occlusion on UV2): for the autotest.
static func baked_ao_count(root: Node) -> int:
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat and mat.ao_enabled and mat.ao_texture and mat.ao_on_uv2:
				n += 1
	return n
