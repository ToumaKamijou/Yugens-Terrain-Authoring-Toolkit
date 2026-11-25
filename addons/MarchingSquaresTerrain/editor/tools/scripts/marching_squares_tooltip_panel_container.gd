@tool
extends PanelContainer
class_name MarchingSquaresTooltipPanelContainer


@export var _tooltip_tool_label : RichTextLabel

@export var tooltip_name_label : RichTextLabel
@export var tooltip_text_label : RichTextLabel
@export var tooltip_index_label : RichTextLabel


func _ready() -> void:
	var accent_color := EditorInterface.get_base_control().get_theme_color("accent_color", "Editor")
	_tooltip_tool_label.add_theme_color_override("default_color", accent_color)
