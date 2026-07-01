@tool
class_name GameWorld
extends Node3D
## The "world" as a single custom node.
##
## Builds and owns its own [WorldEnvironment] (Environment + camera auto-exposure)
## and a key [DirectionalLight3D] as internal children, and surfaces the interesting
## look knobs — sun, exposure, ambient, fog, glow, AO, colour grade — directly on
## this node, driven by SUNNY / OVERCAST / EVENING presets. The heavy, rarely-touched
## render settings are baked in code so the inspector stays focused.
##
## Standalone it shows a plain procedural sky; an independent VolumetricClouds node
## placed in the same GameEnvironment drives the cloud sky on its own — neither node
## references the other.

enum Preset { CUSTOM, SUNNY, OVERCAST, EVENING }

## Falloff model of the standard (non-volumetric) depth/height fog.
enum FogType { EXPONENTIAL, DEPTH }

## Directional shadow-map resolution options, in pixels (the enum values ARE the sizes).
enum ShadowResolution { SIZE_2048 = 2048, SIZE_4096 = 4096, SIZE_8192 = 8192, SIZE_16384 = 16384 }

# Volumetric clouds rendered as the sky (so they land in reflections + ambient and the
# sun/fog apply natively). Cloud raymarch ported from clayjohn's MIT demo; see THIRDPARTY.
const _CLOUD_SKY := preload("res://addons/game_environment/cloud_sky.gdshader")
const _EARTH_RADIUS := 6000000.0
const _MAX_CLOUD_LAYERS := 4

# Full look recipe per preset (only the exposed knobs; static settings live in
# _configure_environment).
const PRESETS := {
	Preset.SUNNY: {
		"sun_altitude": 22.0, "sun_azimuth": -48.0,
		"sun_color": Color(1.0, 0.91, 0.78), "sun_energy": 3.1, "sun_angular": 1.3,
		"shadow_opacity": 1.0, "ambient_energy": 1.0, "exposure": 0.85,
		"ssao_intensity": 2.2, "glow_intensity": 0.15,
		"fog_density": 0.0004, "volumetric_fog_density": 0.0012,
		"volumetric_fog_albedo": Color(0.7, 0.78, 0.9),
		"fog_light_color": Color(0.62, 0.72, 0.85), "fog_type": FogType.EXPONENTIAL,
		"saturation": 1.25, "contrast": 1.08,
	},
	Preset.OVERCAST: {
		"sun_altitude": 72.0, "sun_azimuth": -25.0,
		"sun_color": Color(0.86, 0.89, 0.94), "sun_energy": 0.55, "sun_angular": 3.5,
		"shadow_opacity": 0.32, "ambient_energy": 1.75, "exposure": 1.35,
		"ssao_intensity": 2.3, "glow_intensity": 0.1,
		"fog_density": 0.0015, "volumetric_fog_density": 0.006,
		"volumetric_fog_albedo": Color(0.72, 0.74, 0.77),
		"fog_light_color": Color(0.74, 0.76, 0.8), "fog_type": FogType.EXPONENTIAL,
		"saturation": 0.88, "contrast": 0.97,
	},
	Preset.EVENING: {
		"sun_altitude": 6.0, "sun_azimuth": -62.0,
		"sun_color": Color(0.8, 0.68, 0.62), "sun_energy": 1.1, "sun_angular": 1.6,
		"shadow_opacity": 0.65, "ambient_energy": 0.95, "exposure": 1.3,
		"ssao_intensity": 1.9, "glow_intensity": 0.22,
		"fog_density": 0.0012, "volumetric_fog_density": 0.007,
		"volumetric_fog_albedo": Color(0.45, 0.48, 0.62),
		"fog_light_color": Color(0.55, 0.45, 0.52), "fog_type": FogType.EXPONENTIAL,
		"saturation": 1.0, "contrast": 1.04,
	},
}

## Picking a preset fills the knobs below. Editing any knob afterwards flips this back to
## Custom (so what you see is exactly what gets saved and used at runtime — a named preset
## is NOT re-applied at runtime).
@export var preset := Preset.SUNNY

@export_group("Sun")
## Degrees above the horizon.
@export_range(-10.0, 90.0, 0.5) var sun_altitude := 22.0
## Compass heading in degrees.
@export_range(-180.0, 180.0, 0.5) var sun_azimuth := -48.0
@export var sun_color := Color(1.0, 0.91, 0.78)
@export_range(0.0, 16.0, 0.05) var sun_energy := 3.1
@export_range(0.0, 10.0, 0.1) var sun_angular := 1.3
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 1.0
## How far directional shadows reach (metres). Shorter = crisp, no shadow acne — the
## shadow map texels are denser. A long range (for driving) spreads the texels thin
## and small geometry (stairs/ramps) gets self-shadow striping. Keep it to your
## scene's scale: small lab ~40, open driving ~120.
@export_range(20.0, 400.0, 5.0) var shadow_distance := 100.0
## Directional shadow-map resolution. Higher = crisper shadows, especially over a long
## shadow_distance, at more VRAM/GPU. Applies to the scene's directional shadow atlas.
@export var shadow_resolution := ShadowResolution.SIZE_16384

@export_group("Exposure & Ambient")
@export_range(0.0, 4.0, 0.01) var exposure := 0.85
@export_range(0.0, 4.0, 0.01) var ambient_energy := 1.0

@export_group("Horizon Fog")
## Density of the distance/height fog that forms the haze along the horizon.
@export_range(0.0, 0.02, 0.0001) var fog_density := 0.0004
## World-space Y the fog sits at. Raise it for a higher fog bank up the horizon.
@export_range(-50.0, 50.0, 0.5) var fog_height := -4.0
## How quickly the fog thins out above fog_height (0 = uniform, higher = a thin
## low band).
@export_range(0.0, 0.5, 0.005) var fog_height_density := 0.03
## Tint of the horizon fog.
@export var fog_light_color := Color(0.62, 0.72, 0.85)
## Falloff model of the horizon fog.
@export var fog_type := FogType.EXPONENTIAL

@export_group("Volumetric Fog")
## Volumetric fog density (the in-air light scattering, separate from the horizon haze).
@export_range(0.0, 0.05, 0.0001) var volumetric_fog_density := 0.0012
@export var volumetric_fog_albedo := Color(0.7, 0.78, 0.9)

@export_group("Effects")
@export_range(0.0, 8.0, 0.05) var glow_intensity := 0.15
@export_range(0.0, 8.0, 0.05) var ssao_intensity := 2.2

@export_group("Colour Grade")
@export_range(0.0, 2.0, 0.01) var saturation := 1.25
@export_range(0.0, 2.0, 0.01) var contrast := 1.08

# Clouds are NOT configured here — add CloudLayer nodes to the scene and this node finds
# them. Settings live on each CloudLayer (so you can stack several at different heights).

var _world_env: WorldEnvironment
var _env: Environment
var _sun: DirectionalLight3D
var _applied_preset := Preset.SUNNY
var _applied_shadow_res := -1
var _cloud_sky_mat: ShaderMaterial


func _enter_tree() -> void:
	_build()


func _ready() -> void:
	_build()
	add_to_group(GROUP)  # so CloudLayer nodes can find us to request a refresh
	_sync()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_sync()


## Group GameWorld registers in so CloudLayer nodes can reach it without a path.
const GROUP := &"__game_world"


## Re-scan the scene for CloudLayer nodes and rebuild the sky clouds. Call this at RUNTIME
## after you add/remove a CloudLayer or change its settings from code (in the editor it
## updates live). Adding/removing a CloudLayer node calls this for you.
func refresh_clouds() -> void:
	_sync_clouds()


## Re-apply the whole environment (lighting + clouds) from the current property values.
func refresh() -> void:
	_sync()


## Apply a full preset to the exposed knobs (used by the inspector buttons).
func apply_preset(p: int) -> void:
	preset = p
	_sync()  # _sync sees preset changed and loads it


func _build() -> void:
	if _world_env != null:
		return
	_env = Environment.new()
	_configure_environment(_env)
	_env.sky = _make_sky()

	_world_env = WorldEnvironment.new()
	_world_env.environment = _env
	_world_env.camera_attributes = _make_camera_attributes()
	add_child(_world_env, false, Node.INTERNAL_MODE_BACK)

	_sun = DirectionalLight3D.new()
	_configure_sun(_sun)
	add_child(_sun, false, Node.INTERNAL_MODE_BACK)


## Push the exposed knobs onto the environment + sun.
func _sync() -> void:
	if _env == null or _sun == null:
		return
	if preset != _applied_preset:
		# The dropdown value changed since last sync: load the newly-picked preset (Custom
		# loads nothing). A preset is applied ONLY here, when you pick it — never silently
		# re-applied over your edits at runtime.
		if preset != Preset.CUSTOM:
			_load_preset(preset)
		_applied_preset = preset
	elif preset != Preset.CUSTOM and not _knobs_match(preset):
		# Same preset still selected but a knob was edited -> flip the label to Custom, so
		# the dropdown stays honest and these exact values are what gets saved + used.
		preset = Preset.CUSTOM
		_applied_preset = Preset.CUSTOM
		if Engine.is_editor_hint():
			notify_property_list_changed()

	_sun.rotation_degrees = Vector3(-sun_altitude, sun_azimuth, 0.0)
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.light_angular_distance = sun_angular
	_sun.shadow_opacity = shadow_opacity
	# A live editor hot-reload can leave shadow_distance null until the scene reloads;
	# a typed-null hides from `== null`, so read via Variant and fall back to the default
	# — the shadow range then still applies immediately, in-editor, without a reload.
	var sd: Variant = shadow_distance
	_sun.directional_shadow_max_distance = sd if sd != null else 100.0
	# Resize the directional shadow atlas (global) only when it actually changes.
	if int(shadow_resolution) != _applied_shadow_res:
		_applied_shadow_res = int(shadow_resolution)
		RenderingServer.directional_shadow_atlas_set_size(_applied_shadow_res, false)

	_env.tonemap_exposure = exposure
	_env.ambient_light_energy = ambient_energy
	_env.volumetric_fog_density = volumetric_fog_density
	_env.volumetric_fog_albedo = volumetric_fog_albedo
	# Changing fog_mode resets the other standard-fog params to their defaults, so
	# set the mode first and then (re-)apply the horizon fog every time.
	_env.fog_mode = (Environment.FOG_MODE_DEPTH if fog_type == FogType.DEPTH
		else Environment.FOG_MODE_EXPONENTIAL)
	_env.fog_density = fog_density
	_env.fog_light_color = fog_light_color
	_env.fog_height = fog_height
	_env.fog_height_density = fog_height_density
	_env.fog_aerial_perspective = 0.0
	_env.fog_sky_affect = 0.0
	_env.glow_intensity = glow_intensity
	_env.ssao_intensity = ssao_intensity
	_env.adjustment_saturation = saturation
	_env.adjustment_contrast = contrast

	_sync_clouds()


func _load_preset(p: int) -> void:
	_applied_preset = p
	if not PRESETS.has(p):
		return
	var cfg: Dictionary = PRESETS[p]
	sun_altitude = cfg.sun_altitude
	sun_azimuth = cfg.sun_azimuth
	sun_color = cfg.sun_color
	sun_energy = cfg.sun_energy
	sun_angular = cfg.sun_angular
	shadow_opacity = cfg.shadow_opacity
	ambient_energy = cfg.ambient_energy
	exposure = cfg.exposure
	ssao_intensity = cfg.ssao_intensity
	glow_intensity = cfg.glow_intensity
	fog_density = cfg.fog_density
	volumetric_fog_density = cfg.get("volumetric_fog_density", volumetric_fog_density)
	volumetric_fog_albedo = cfg.get("volumetric_fog_albedo", volumetric_fog_albedo)
	fog_light_color = cfg.get("fog_light_color", fog_light_color)
	fog_type = cfg.get("fog_type", fog_type)
	saturation = cfg.saturation
	contrast = cfg.contrast


## True if the exposed knobs still equal preset [param p] (i.e. the user hasn't edited any).
func _knobs_match(p: int) -> bool:
	if not PRESETS.has(p):
		return false
	var c: Dictionary = PRESETS[p]
	return (is_equal_approx(sun_altitude, c.sun_altitude)
		and is_equal_approx(sun_azimuth, c.sun_azimuth)
		and sun_color.is_equal_approx(c.sun_color)
		and is_equal_approx(sun_energy, c.sun_energy)
		and is_equal_approx(sun_angular, c.sun_angular)
		and is_equal_approx(shadow_opacity, c.shadow_opacity)
		and is_equal_approx(ambient_energy, c.ambient_energy)
		and is_equal_approx(exposure, c.exposure)
		and is_equal_approx(ssao_intensity, c.ssao_intensity)
		and is_equal_approx(glow_intensity, c.glow_intensity)
		and is_equal_approx(fog_density, c.fog_density)
		and is_equal_approx(volumetric_fog_density, c.get("volumetric_fog_density", volumetric_fog_density))
		and volumetric_fog_albedo.is_equal_approx(c.get("volumetric_fog_albedo", volumetric_fog_albedo))
		and fog_light_color.is_equal_approx(c.get("fog_light_color", fog_light_color))
		and int(fog_type) == int(c.get("fog_type", fog_type))
		and is_equal_approx(saturation, c.saturation)
		and is_equal_approx(contrast, c.contrast))


# --- Static configuration (baked, not exposed) -------------------------------

func _configure_environment(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0

	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_out = 4.0
	env.ssr_depth_tolerance = 0.2

	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_power = 1.8
	env.ssao_detail = 0.6

	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.1

	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.0976563
	env.sdfgi_energy = 1.05

	env.glow_enabled = true
	env.set("glow_levels/2", 0.2)
	env.set("glow_levels/4", 1.0)
	env.set("glow_levels/5", 0.7)
	env.glow_strength = 0.9
	env.glow_blend_mode = 0  # match the tuned scene exactly (0 in the .tscn)
	env.glow_hdr_threshold = 2.2

	# Standard-fog params (density/height/aerial) are applied in _sync, because they
	# have to be re-set after every fog_mode change (which resets them).
	env.fog_enabled = true

	env.volumetric_fog_enabled = true
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_gi_inject = 0.4

	env.adjustment_enabled = true


func _configure_sun(sun: DirectionalLight3D) -> void:
	sun.position = Vector3(0.0, 50.0, 0.0)
	sun.shadow_enabled = true
	# Acne is the dominant problem here (confirmed: disabling the shadow removes the
	# stripes). normal_bias is the primary anti-acne lever — it offsets the shadow
	# lookup along the surface normal, scaled by texel size, so grazing-lit flat faces
	# stop self-shadowing into stripes. We had pushed these BELOW Godot's defaults
	# (0.1 / 2.0) chasing peter-panning, which is what caused the acne on large scenes
	# where texels are spread thin. Back to (slightly above) the defaults. Tune live
	# with gi_debug ([ ] = normal_bias, - = = bias) if a scene still stripes.
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	sun.shadow_blur = 1.0
	# Pull the near cascade in tight so contact shadows get the densest texels.
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.35
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	# directional_shadow_max_distance is driven by the exposed shadow_distance in _sync.


func _make_camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 300.0
	ca.auto_exposure_max_sensitivity = 640.0
	ca.auto_exposure_scale = 0.5
	ca.auto_exposure_speed = 0.6
	return ca


## The atmosphere — a gradient sky (deep-blue zenith -> pale Mie horizon) that can ALSO
## raymarch volumetric clouds when [member clouds_enabled] is on. It's a real sky shader,
## so clouds land in the radiance cubemap (reflections + ambient) and the sun/fog apply
## natively — no overlay, no faking. With clouds off it's just the gradient.
func _make_sky() -> Sky:
	_cloud_sky_mat = ShaderMaterial.new()
	_cloud_sky_mat.shader = _CLOUD_SKY
	_cloud_sky_mat.set_shader_parameter("perlworlnoise",
		_noise3d(64, FastNoiseLite.TYPE_CELLULAR, 0.04, FastNoiseLite.FRACTAL_PING_PONG, 4))
	_cloud_sky_mat.set_shader_parameter("worlnoise",
		_noise3d(48, FastNoiseLite.TYPE_CELLULAR, 0.09, -1, 0))
	_cloud_sky_mat.set_shader_parameter("weathermap", _noise2d(256, 0.012, 3))
	var sky := Sky.new()
	sky.sky_material = _cloud_sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	return sky


## Scan the scene for CloudLayer nodes and push them (sorted highest-first) + the sun into
## the sky shader. No layers = plain gradient sky.
func _sync_clouds() -> void:
	if _cloud_sky_mat == null:
		return
	var layers := _collect_cloud_layers()
	layers.sort_custom(func(a: CloudLayer, b: CloudLayer) -> bool: return a.height > b.height)
	var n: int = mini(layers.size(), _MAX_CLOUD_LAYERS)

	# The sun comes from the key DirectionalLight via the sky shader's built-in LIGHT0_*, so
	# nothing sun-related is fed here.
	var b_rad := PackedFloat32Array()
	var t_rad := PackedFloat32Array()
	var cov := PackedFloat32Array()
	var den := PackedFloat32Array()
	var bri := PackedFloat32Array()
	var wind := PackedVector2Array()
	var wspd := PackedFloat32Array()
	var turb := PackedFloat32Array()
	var spr := PackedFloat32Array()
	for i in _MAX_CLOUD_LAYERS:
		if i < n:
			var l: CloudLayer = layers[i]
			var b := _EARTH_RADIUS + l.height
			b_rad.append(b)
			t_rad.append(b + l.thickness)
			cov.append(l.coverage)
			den.append(l.density)
			bri.append(l.brightness)
			wind.append(l.wind_direction)
			wspd.append(l.wind_speed)
			turb.append(l.turbulence_speed)
			spr.append(l.sun_spread)
		else:
			b_rad.append(_EARTH_RADIUS + 1000.0)
			t_rad.append(_EARTH_RADIUS + 3500.0)
			cov.append(0.4); den.append(0.05); bri.append(0.1)
			wind.append(Vector2(1.0, 0.0)); wspd.append(1.0); turb.append(1.0); spr.append(0.5)

	_cloud_sky_mat.set_shader_parameter("layer_count", n)
	_cloud_sky_mat.set_shader_parameter("layer_b_radius", b_rad)
	_cloud_sky_mat.set_shader_parameter("layer_t_radius", t_rad)
	_cloud_sky_mat.set_shader_parameter("layer_coverage", cov)
	_cloud_sky_mat.set_shader_parameter("layer_density", den)
	_cloud_sky_mat.set_shader_parameter("layer_brightness", bri)
	_cloud_sky_mat.set_shader_parameter("layer_wind", wind)
	_cloud_sky_mat.set_shader_parameter("layer_wind_speed", wspd)
	_cloud_sky_mat.set_shader_parameter("layer_turbulence", turb)
	_cloud_sky_mat.set_shader_parameter("layer_spread", spr)


## Find every CloudLayer node in the current scene (editor or running).
func _collect_cloud_layers() -> Array[CloudLayer]:
	var tree := get_tree()
	if tree == null:
		return []
	var root: Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
	if root == null:
		root = owner
	var out: Array[CloudLayer] = []
	_gather_cloud_layers(root, out)
	return out


func _gather_cloud_layers(node: Node, out: Array[CloudLayer]) -> void:
	if node == null:
		return
	# Hidden layers (eye icon off, or a hidden parent) are skipped — toggling visibility
	# turns a deck on/off.
	if node is CloudLayer and (node as CloudLayer).is_visible_in_tree():
		out.append(node)
	for c in node.get_children():
		_gather_cloud_layers(c, out)


func _noise3d(size: int, type: int, freq: float, fractal_type: int, octaves: int) -> NoiseTexture3D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = type
	fnl.frequency = freq
	if fractal_type >= 0:
		fnl.fractal_type = fractal_type
		fnl.fractal_octaves = octaves
	var tex := NoiseTexture3D.new()
	tex.width = size
	tex.height = size
	tex.depth = size
	tex.seamless = true
	tex.noise = fnl
	return tex


func _noise2d(size: int, freq: float, octaves: int) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_PERLIN
	fnl.frequency = freq
	fnl.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = fnl
	return tex
