@tool
extends Button
class_name MarchingSquaresToolbarButton


const TOOLTIP_PANEL := preload("uid://dc1s2agj1xhhc")

var tool_name := "Tool..."
var tooltip := "Tooltip..."
var tool_index := "x"


func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := TOOLTIP_PANEL.instantiate() as MarchingSquaresTooltipPanelContainer
	panel.tooltip_name_label.text = tool_name
	panel.tooltip_text_label.text = tooltip
	panel.tooltip_index_label.text = ":  index (" + tool_index + ')'
	return panel
