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

## Picking a preset overwrites the knobs below; editing a knob afterwards keeps the
## preset label but freely overrides it.
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
@export_range(20.0, 400.0, 5.0) var shadow_distance := 60.0

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

var _world_env: WorldEnvironment
var _env: Environment
var _sun: DirectionalLight3D
var _applied_preset := Preset.CUSTOM


func _enter_tree() -> void:
	_build()


func _ready() -> void:
	_build()
	_sync()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_sync()


## Apply a full preset to the exposed knobs (used by the inspector buttons).
func apply_preset(p: int) -> void:
	preset = p
	_load_preset(p)
	_sync()


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
	if preset != _applied_preset and preset != Preset.CUSTOM:
		_load_preset(preset)

	_sun.rotation_degrees = Vector3(-sun_altitude, sun_azimuth, 0.0)
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.light_angular_distance = sun_angular
	_sun.shadow_opacity = shadow_opacity
	# A live editor hot-reload can leave shadow_distance null until the scene reloads;
	# a typed-null hides from `== null`, so read via Variant and fall back to the default
	# — the shadow range then still applies immediately, in-editor, without a reload.
	var sd: Variant = shadow_distance
	_sun.directional_shadow_max_distance = sd if sd != null else 60.0

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


## The atmosphere — a plain gradient sky (the Unreal-like deep-blue zenith -> pale
## Mie horizon). Clouds are NOT here; they are separate VolumetricClouds nodes that
## render on top. This sky is always present.
func _make_sky() -> Sky:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.07, 0.28, 0.72)
	mat.sky_horizon_color = Color(0.84, 0.87, 0.91)
	mat.sky_curve = 0.1
	mat.sky_energy_multiplier = 1.0
	mat.ground_horizon_color = Color(0.84, 0.87, 0.91)
	mat.ground_bottom_color = Color(0.6, 0.62, 0.64)
	mat.ground_curve = 0.02
	var sky := Sky.new()
	sky.sky_material = mat
	return sky
