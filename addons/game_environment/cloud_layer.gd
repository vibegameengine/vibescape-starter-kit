@tool
class_name CloudLayer
extends Node3D
## One volumetric cloud deck. Add one (or several) anywhere in the scene and the GameWorld
## node finds them and renders them in the sky — so they show in reflections + ambient and
## catch the sun/fog natively. Stack several at different [member height]s for layered skies
## (up to 4 are used, composited highest-first).
##
## This node only holds the deck's settings; GameWorld reads them. Cloud model:
## "Real-time Volumetric Cloudscapes of Horizon: Zero Dawn", ported from clayjohn's MIT
## demo — see THIRDPARTY.md.

## Loose cloud-form presets for the inspector buttons; they nudge coverage/density.
enum CloudType { STRATUS, STRATOCUMULUS, CUMULUS }

@export_group("Shape")
## Altitude of the deck base, metres above the horizon.
@export_range(500.0, 8000.0, 50.0) var height := 2000.0
## Vertical thickness of the deck, metres.
@export_range(100.0, 4000.0, 50.0) var thickness := 2500.0
## How much of the sky this layer fills.
@export_range(0.1, 1.0, 0.01) var coverage := 0.4
## Optical thickness of the cloud medium.
@export_range(0.01, 0.2, 0.001) var density := 0.05

@export_group("Light")
## Overall brightness of the clouds (clayjohn's `exposure`).
@export_range(0.0, 1.0, 0.005) var brightness := 0.1
## Evenness of the cloud lighting: 0 = directional (bright toward the sun, darker away),
## 1 = flat/uniformly lit. Use it to dial out the bright-near-sun / dark-far contrast.
@export_range(0.0, 1.0, 0.01) var sun_spread := 0.5

@export_group("Wind")
@export var wind_direction := Vector2(1.0, 0.3)
@export_range(0.0, 20.0, 0.1) var wind_speed := 2.0
## Speed of the edge churn / turbulence, independent of the drift. 1.0 = reference.
@export_range(0.0, 4.0, 0.05) var turbulence_speed := 1.0


func _enter_tree() -> void:
	# Toggling the eye icon (visible) should turn this deck on/off at runtime too.
	if not visibility_changed.is_connected(_notify_world):
		visibility_changed.connect(_notify_world)
	_notify_world()


func _exit_tree() -> void:
	# Refresh AFTER we've left, so the rebuilt sky no longer includes this layer.
	_notify_world()


## Ask the GameWorld (if any) to rebuild its sky clouds. Call this yourself if you change a
## setting from code at runtime; in the editor GameWorld already updates live.
func notify_world() -> void:
	_notify_world()


func _notify_world() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var gw := tree.get_first_node_in_group(GameWorld.GROUP)
	if gw != null:
		gw.refresh_clouds.call_deferred()


## Used by the inspector buttons.
func apply_cloud_type(type: CloudType) -> void:
	match type:
		CloudType.STRATUS:
			coverage = 0.6
			density = 0.04
		CloudType.STRATOCUMULUS:
			coverage = 0.45
			density = 0.052
		CloudType.CUMULUS:
			coverage = 0.34
			density = 0.07
