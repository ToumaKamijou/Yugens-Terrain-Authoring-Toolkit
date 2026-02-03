@tool
extends VFlowContainer
class_name MarchingSquaresToolbar


signal tool_changed(tool_attributes: String)

var toolbox := MarchingSquaresToolbox.new()
var tool_button_group : ButtonGroup = ButtonGroup.new()
var tool_buttons : Dictionary = {}


func _init() -> void:
	set_custom_minimum_size(Vector2(35, 35))


func _ready() -> void:
	tool_button_group.pressed.connect(_on_tool_selected)
	add_child(HSeparator.new())
	
	_add_tools()
	
	var buttons_array : Array[BaseButton] = tool_button_group.get_buttons()
	if buttons_array.size() > 0:
		buttons_array[0].set_pressed(true)


func _add_tools() -> void:
	if not toolbox:
		return
	
	var tools = toolbox.tools
	
	alignment = FlowContainer.ALIGNMENT_CENTER
	for i in range(tools.size()):
		if i == 4 or i == 7 or i == 10:
			add_child(HSeparator.new())
		var tool = tools[i]
		var button := Button.new()
		
		button.set_name(tool.label)
		button.set_tooltip_text(tool.tooltip)
		button.set_button_icon(tool.icon)
		button.set_meta("Index", i)
		button.set_flat(true)
		button.set_toggle_mode(true)
		var scale = EditorInterface.get_editor_scale() # Lets the icons work on retina displays
		button.custom_minimum_size = Vector2(30, 30) * scale
		button.expand_icon = true
		button.set_button_group(tool_button_group)
		
		var c_cont = CenterContainer.new()
		c_cont.custom_minimum_size = Vector2(35, 35)
		c_cont.add_child(button, true)
		add_child(c_cont, true)
		
		tool_buttons[i] = button
	add_child(HSeparator.new())


func _on_tool_selected(_button: BaseButton) -> void:
	emit_signal("tool_changed", _button.get_meta("Index"))
