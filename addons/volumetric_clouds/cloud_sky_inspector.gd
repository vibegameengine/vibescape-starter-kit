@tool
extends EditorInspectorPlugin
## Adds a custom "Cloud form" header with one-click preset buttons on top of the
## default property list of a [VolumetricClouds] node.


func _can_handle(object: Object) -> bool:
	return object is VolumetricClouds


func _parse_begin(object: Object) -> void:
	var clouds := object as VolumetricClouds

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Cloud form"
	title.add_theme_color_override("font_color", Color(0.6, 0.78, 1.0))
	root.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_add_button(row, "Stratus", clouds, VolumetricClouds.CloudType.STRATUS)
	_add_button(row, "Stratocumulus", clouds, VolumetricClouds.CloudType.STRATOCUMULUS)
	_add_button(row, "Cumulus", clouds, VolumetricClouds.CloudType.CUMULUS)
	root.add_child(row)

	add_custom_control(root)


func _add_button(parent: Control, text: String, clouds: VolumetricClouds, type: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void:
		clouds.apply_cloud_type(type)
		clouds.notify_property_list_changed())
	parent.add_child(btn)
