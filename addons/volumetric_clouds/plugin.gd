@tool
extends EditorPlugin
## Registers the VolumetricClouds custom node (Create-dialog entry) and its
## "Cloud form" inspector buttons.

const CloudsInspector := preload("res://addons/volumetric_clouds/cloud_sky_inspector.gd")
const SCRIPT := preload("res://addons/volumetric_clouds/volumetric_clouds.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	add_custom_type("VolumetricClouds", "Node3D", SCRIPT, null)
	_inspector = CloudsInspector.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	_inspector = null
	remove_custom_type("VolumetricClouds")
