extends RefCounted
## The sun and the moon: where each one is in the sky at an hour of the game's day, the moon's
## phase from the game's calendar, the clouds, and the light the one DirectionalLight3D (main.sun) gives. By day
## it is the sun's light and its shadows; through dusk it turns to the moon (or, when the moon is
## down, a faint high starlight), so shadows always fall away from whatever is lighting the scene.
## shaders/sky.gdshader draws both discs from the directions set here (sun_dir, moon_dir), with
## the moon's lit side toward the sun and its terminator from the phase.
##
## The moon goes round once a season: new on the 1st, first quarter on the 8th, full on the 15th,
## last quarter on the 22nd (a season is 28 days), moving on a little every hour of the game's
## clock. Each day it rises later behind the sun, by the phase: a new moon goes round with the sun,
## a first quarter is high at sunset, a full moon rises as the sun goes down and is up all night.
##
## Clouds come and go on their own: a slow random drift over the game's hours between clear, fair,
## broken and nearly overcast (cloudiness()), with rain covering the rest. Cloudier skies dim the
## sun a little and soften its shadows.
const LUNAR_DAYS := 28.0 # one cycle a season (game_state.gd: 28 days a season)
const SUNRISE := 6.0
const SUNSET := 19.5
const PEAK := 60.0 # the sun's height at midday, degrees
const NOON_YAW := -25.0 # the light's yaw at midday (rises at 35, sets at -85, as main.gd had it)
const MOON_FULL := 0.55 # moonlight at full moon (the sun is 1.85 at noon)
const MOON_NEW := 0.05
const STARLIGHT := 0.06
const MOON_COLOR := Color(0.62, 0.72, 1.0)

## For the autotest and screenshots: a fixed phase (0 new, 0.5 full) instead of the game day's; -1 is off.
static var phase_override := -1.0


## The moon's age in its cycle on a game day and hour: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
static func phase_at(day: int, hour: float) -> float:
	return fposmod((float(day - 1) + hour / 24.0) / LUNAR_DAYS, 1.0)


static func phase() -> float:
	return phase_override if phase_override >= 0.0 else phase_at(Game.day, Game.hour)


## How cloudy the sky is with no rain, 0 clear .. about 0.75 broken, by the game's day and hour: a
## slow random drift (a new spell every few hours), the same for the same day and hour every time.
static func cloudiness(day: int, hour: float) -> float:
	var t := (float(day) * 24.0 + hour) / 5.0 # a spell every five game hours or so
	var i := floori(t)
	var f := t - float(i)
	f = f * f * (3.0 - 2.0 * f)
	var a := _spell(i)
	var b := _spell(i + 1)
	return lerpf(a, b, f)


static func _spell(i: int) -> float:
	var r := fposmod(sin(float(i) * 12.9898 + 4.1) * 43758.5453, 1.0)
	# more clear and fair spells than cloudy ones
	return 0.08 + 0.7 * r * r


## How much of the disc is lit, 0 at new moon to 1 at full.
static func illumination(p: float) -> float:
	return 0.5 * (1.0 - cos(TAU * p))


static func phase_name(p: float) -> String:
	var names := ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
	return names[int(floor(fposmod(p + 1.0 / 16.0, 1.0) * 8.0)) % 8]


## Elevation and yaw (degrees, as a light's rotation_degrees takes them) of the sun at hour h.
## Up from 6:00 to 19:30, highest at 12:45; below the horizon the rest of the night.
static func sun_angles(h: float) -> Vector2:
	h = fposmod(h, 24.0)
	var day_len := SUNSET - SUNRISE
	if h >= SUNRISE and h <= SUNSET:
		var s := (h - SUNRISE) / day_len
		return Vector2(PEAK * sin(PI * s), lerpf(35.0, -85.0, s))
	var s2 := fposmod(h - SUNSET, 24.0) / (24.0 - day_len)
	return Vector2(-40.0 * sin(PI * s2), lerpf(-85.0, -325.0, s2))


## The direction toward a body with those angles (what a light at that rotation shines from).
static func dir_of(a: Vector2) -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(-a.x), deg_to_rad(a.y), 0.0)).z


## Where the moon is at hour h with phase p: it trails the sun round the sky by p of a day.
static func moon_angles(h: float, p: float) -> Vector2:
	return sun_angles(h - p * 24.0)


var main: Node
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var moon_up := 0.0 # 0..1: how far over the horizon the moon is (for the autotest, and the light)
var current_phase := 0.0
var clouds := 0.0 # 0..1, the sky's own cloudiness now (without rain)
static var clouds_override := -1.0 # for the autotest and screenshots


func setup(m: Node) -> void:
	main = m
	sun = m.sun
	sky_mat = m.sky_mat


## Every frame, after main._update_lighting has set the day's sun energy and colour (dl: daylight).
func update(h: float, dl: float, rain: float) -> void:
	current_phase = phase()
	var p := current_phase
	var lit := illumination(p)
	var sa := sun_angles(h)
	var ma := moon_angles(h, p)
	var sun_d := dir_of(sa)
	var moon_d := dir_of(ma)
	moon_up = smoothstep(-2.0, 10.0, ma.x)
	# the night light: the moon when it's up, by how much of it is lit; else starlight from on high
	var night_a := Vector2(maxf(ma.x, 16.0), ma.y) if moon_up > 0.01 else Vector2(55.0, -20.0)
	var night_e := lerpf(STARLIGHT, lerpf(MOON_NEW, MOON_FULL, lit), moon_up) * (1.0 - 0.75 * rain)
	# by day the light comes from the sun itself, no lower than 12 degrees (long but sane shadows)
	var day_a := Vector2(maxf(sa.x, 12.0), sa.y)
	var q_day := Basis.from_euler(Vector3(deg_to_rad(-day_a.x), deg_to_rad(day_a.y), 0.0)).get_rotation_quaternion()
	var q_night := Basis.from_euler(Vector3(deg_to_rad(-night_a.x), deg_to_rad(night_a.y), 0.0)).get_rotation_quaternion()
	# swing over in the dim part of twilight, so the shadows turn while they're faint
	var k := smoothstep(0.0, 0.35, dl)
	sun.quaternion = q_night.slerp(q_day, k)
	sun.light_energy = lerpf(night_e, sun.light_energy, k)
	sun.light_color = MOON_COLOR.lerp(sun.light_color, k)
	sky_mat.set_shader_parameter("sun_dir", sun_d)
	sky_mat.set_shader_parameter("moon_dir", moon_d)
	sky_mat.set_shader_parameter("moon_phase", p)
	sky_mat.set_shader_parameter("moon_lit", lit)
	# the day's clouds, rain covering the rest of the sky; a cloudier sky dims the sun and softens its shadows
	clouds = cloudiness(Game.day, h) if clouds_override < 0.0 else clouds_override
	var cover := lerpf(clouds, 0.92, rain)
	sky_mat.set_shader_parameter("cloud_cover", cover)
	var dim := smoothstep(0.35, 0.8, clouds) * (1.0 - rain)
	sun.light_energy *= 1.0 - 0.3 * dim * k
	sun.light_angular_distance = lerpf(0.55, 2.5, dim * k)
	sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.93, 0.8).lerp(Color(1.0, 0.55, 0.3), 1.0 - smoothstep(2.0, 22.0, sa.x)))
