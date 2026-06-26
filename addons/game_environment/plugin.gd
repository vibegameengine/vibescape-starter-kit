@tool
extends EditorPlugin
## Registers the GameWorld + CloudLayer custom nodes (Create-dialog entries) and their
## preset-button inspectors.

const EnvironmentInspector := preload("res://addons/game_environment/environment_inspector.gd")
const CloudLayerInspector := preload("res://addons/game_environment/cloud_layer_inspector.gd")
const GAME_WORLD := preload("res://addons/game_environment/game_world.gd")
const CLOUD_LAYER := preload("res://addons/game_environment/cloud_layer.gd")

var _inspector: EditorInspectorPlugin
var _cloud_inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	add_custom_type("GameWorld", "Node3D", GAME_WORLD, null)
	add_custom_type("CloudLayer", "Node3D", CLOUD_LAYER, null)
	_inspector = EnvironmentInspector.new()
	add_inspector_plugin(_inspector)
	_cloud_inspector = CloudLayerInspector.new()
	add_inspector_plugin(_cloud_inspector)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	remove_inspector_plugin(_cloud_inspector)
	_inspector = null
	_cloud_inspector = null
	remove_custom_type("CloudLayer")
	remove_custom_type("GameWorld")
