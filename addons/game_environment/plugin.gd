@tool
extends EditorPlugin
## Registers the GameWorld custom node (Create-dialog entry) and its preset-button
## inspector.

const EnvironmentInspector := preload("res://addons/game_environment/environment_inspector.gd")
const SCRIPT := preload("res://addons/game_environment/game_world.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	add_custom_type("GameWorld", "Node3D", SCRIPT, null)
	_inspector = EnvironmentInspector.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	_inspector = null
	remove_custom_type("GameWorld")
