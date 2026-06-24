@tool
extends EditorInspectorPlugin
## Adds one-click lighting-preset buttons at the top of a [GameWorld] node.


func _can_handle(object: Object) -> bool:
	return object is GameWorld


func _parse_begin(object: Object) -> void:
	var world := object as GameWorld

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Lighting preset"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	root.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_add_button(row, "Sunny", world, GameWorld.Preset.SUNNY)
	_add_button(row, "Overcast", world, GameWorld.Preset.OVERCAST)
	_add_button(row, "Evening", world, GameWorld.Preset.EVENING)
	root.add_child(row)

	add_custom_control(root)


func _add_button(parent: Control, text: String, world: GameWorld, preset: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		world.apply_preset(preset)
		world.notify_property_list_changed())
	parent.add_child(btn)
