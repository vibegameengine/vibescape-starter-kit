@tool
class_name VolumetricClouds
extends Node3D
## Volumetric clouds as a SEPARATE overlay layer — not the sky.
##
## Renders the raymarched cloud deck onto an inverted sky-dome that follows the
## camera, composited (premultiplied alpha) OVER the atmosphere sky from GameWorld
## and occluded by scene geometry. Because it's just transparent geometry:
##  - hiding this node hides its clouds (the sky stays);
##  - you can drop SEVERAL of these at different heights / settings and they stack
##    (blend over each other), exactly like distinct cloud layers.
## It needs a DirectionalLight3D somewhere in the scene for the sun (found at runtime).
##
## Cloud model: "The Real-time Volumetric Cloudscapes of Horizon: Zero Dawn"
## (Schneider / Guerrilla, SIGGRAPH 2015), ported from clayjohn's MIT demo.
## See docs/CREDITS.md.

const _SHADER: Shader = preload("res://addons/volumetric_clouds/cloud_overlay.gdshader")
const _EARTH_RADIUS := 6000000.0
const _SHELL_THICKNESS := 2500.0

## Loose cloud-form presets for the inspector buttons; they nudge cloudiness/density.
enum CloudType { STRATUS, STRATOCUMULUS, CUMULUS }

@export_group("Shape")
## Altitude of this cloud deck above the horizon (metres). Stack layers at different
## heights for multiple decks.
@export_range(500.0, 4000.0, 10.0) var height := 1500.0
## How much of the sky this layer fills.
@export_range(0.1, 1.0, 0.01) var cloudiness := 0.4
## Optical thickness of the cloud medium.
@export_range(0.01, 0.2, 0.001) var density := 0.055

@export_group("Light")
## Overall brightness of the in-cloud lighting.
@export_range(0.0, 1.0, 0.005) var brightness := 0.21
## How far the sun's brightening spreads (higher = wider, more even).
@export_range(0.1, 0.9, 0.01) var sun_spread := 0.5

@export_group("Wind")
@export var wind_direction := Vector2(1.0, 0.3)
@export_range(0.0, 20.0, 0.1) var wind_speed := 1.0
## Speed of the edge churn / turbulence, independent of the drift. 1.0 = original.
@export_range(0.0, 4.0, 0.05) var turbulence_speed := 1.0

@export_group("Quality")
## Raymarch steps toward the horizon (higher = less far-cloud shimmer, more GPU).
@export_range(16, 256, 1) var march_steps_horizon := 160
## Raymarch steps overhead (a short path, so it needs fewer).
@export_range(16, 256, 1) var march_steps_zenith := 64

var _mesh: MeshInstance3D
var _mat: ShaderMaterial


func _enter_tree() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()
	# Follow the camera + track the sun every frame, in the editor AND in game.
	set_process(true)
	_update()


func _process(_delta: float) -> void:
	_update()


## Used by the inspector buttons.
func apply_cloud_type(type: CloudType) -> void:
	match type:
		CloudType.STRATUS:
			cloudiness = 0.6
			density = 0.04
		CloudType.STRATOCUMULUS:
			cloudiness = 0.45
			density = 0.052
		CloudType.CUMULUS:
			cloudiness = 0.34
			density = 0.07
	_sync()


func _update() -> void:
	_follow_camera()
	_update_sun()
	_sync()


func _ensure_built() -> void:
	if _mesh != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER

	_mat.set_shader_parameter("perlworlnoise",
		_noise3d(64, FastNoiseLite.TYPE_CELLULAR, 0.04, FastNoiseLite.FRACTAL_PING_PONG, 4))
	_mat.set_shader_parameter("worlnoise",
		_noise3d(48, FastNoiseLite.TYPE_CELLULAR, 0.09, -1, 0))
	_mat.set_shader_parameter("weathermap", _noise2d(256, 0.012, 3))

	# Fixed Nishita atmosphere that only tints the cloud lighting.
	_mat.set_shader_parameter("rayleigh", 2.3)
	_mat.set_shader_parameter("rayleigh_color", Color(0.26, 0.41, 0.58))
	_mat.set_shader_parameter("mie", 0.003)
	_mat.set_shader_parameter("mie_eccentricity", 0.8)
	_mat.set_shader_parameter("mie_color", Color(0.63, 0.77, 0.92))
	_mat.set_shader_parameter("turbidity", 4.0)
	_mat.set_shader_parameter("sun_disk_scale", 1.0)
	_mat.set_shader_parameter("ground_color", Color(0.8, 0.82, 0.85))
	_mat.set_shader_parameter("_time_offset", 0.0)

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 16384.0  # huge & camera-locked — never frustum-cull it
	add_child(_mesh, false, Node.INTERNAL_MODE_BACK)


## Centre the dome on the active camera and size it just inside the far plane so the
## camera is always inside it and scene geometry occludes the clouds.
func _follow_camera() -> void:
	if _mesh == null:
		return
	var cam := get_viewport().get_camera_3d()
	# When editing the prefab alone there's no scene Camera3D, so follow the editor
	# viewport camera — otherwise the dome has nowhere to sit and the clouds vanish.
	if cam == null and Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei: Object = Engine.get_singleton("EditorInterface")
		var vp: SubViewport = ei.get_editor_viewport_3d(0)
		if vp != null:
			cam = vp.get_camera_3d()
	if cam == null:
		return
	_mesh.global_position = cam.global_position
	var r: float = maxf(cam.far * 0.9, 100.0)
	_mesh.scale = Vector3(r, r, r)


## Feed the shader the scene's sun (direction the light travels, colour, energy).
func _update_sun() -> void:
	if _mat == null:
		return
	var sun := _find_sun()
	if sun == null:
		return
	# Direction TOWARD the sun (matches the sky shader's LIGHT0_DIRECTION: it's where
	# the sun disk is drawn). A DirectionalLight shines along -Z, so +Z points back at it.
	_mat.set_shader_parameter("sun_direction", sun.global_transform.basis.z)
	_mat.set_shader_parameter("sun_color", sun.light_color)
	_mat.set_shader_parameter("sun_energy", sun.light_energy)


## Push the exposed knobs into the shader.
func _sync() -> void:
	if _mat == null:
		return
	var b := _EARTH_RADIUS + height
	_mat.set_shader_parameter("sky_b_radius", b)
	_mat.set_shader_parameter("sky_t_radius", b + _SHELL_THICKNESS)
	_mat.set_shader_parameter("cloud_coverage", cloudiness)
	_mat.set_shader_parameter("_density", density)
	_mat.set_shader_parameter("exposure", brightness)
	_mat.set_shader_parameter("sun_anisotropy", 1.0 - sun_spread)
	_mat.set_shader_parameter("wind_direction", wind_direction)
	_mat.set_shader_parameter("wind_speed", wind_speed)
	_mat.set_shader_parameter("turbulence_speed", turbulence_speed)
	_mat.set_shader_parameter("march_steps_horizon", float(march_steps_horizon))
	_mat.set_shader_parameter("march_steps_zenith", float(march_steps_zenith))


func _find_sun() -> DirectionalLight3D:
	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if root == null:
		root = owner
	return _search_sun(root)


func _search_sun(node: Node) -> DirectionalLight3D:
	if node == null:
		return null
	if node is DirectionalLight3D:
		return node
	for child in node.get_children(true):
		var found := _search_sun(child)
		if found != null:
			return found
	return null


# --- Procedural noise --------------------------------------------------------

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
