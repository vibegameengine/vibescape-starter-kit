@tool
extends EditorInspectorPlugin
## Adds a "Cloud form" header with one-click preset buttons on top of a [CloudLayer].


func _can_handle(object: Object) -> bool:
	return object is CloudLayer


func _parse_begin(object: Object) -> void:
	var layer := object as CloudLayer

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Cloud form"
	title.add_theme_color_override("font_color", Color(0.6, 0.78, 1.0))
	root.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_add_button(row, "Stratus", layer, CloudLayer.CloudType.STRATUS)
	_add_button(row, "Stratocumulus", layer, CloudLayer.CloudType.STRATOCUMULUS)
	_add_button(row, "Cumulus", layer, CloudLayer.CloudType.CUMULUS)
	root.add_child(row)

	add_custom_control(root)


func _add_button(parent: Control, text: String, layer: CloudLayer, type: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		layer.apply_cloud_type(type)
		layer.notify_property_list_changed())
	parent.add_child(btn)
