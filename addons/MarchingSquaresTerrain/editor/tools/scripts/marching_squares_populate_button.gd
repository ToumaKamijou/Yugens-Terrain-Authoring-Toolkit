@tool
extends Button
class_name MarchingSquaresPopulateButton


enum PopulatorType {FLOWER}

const POPULATOR_TYPE : Dictionary = {
	PopulatorType.FLOWER: preload("uid://demjm5kq2kdpa"),
}

const POPULATOR_NAMES : Array[String] = [
	"FlowerPlanter",
]

var current_terrain_node : MarchingSquaresTerrain

var populator_dialog : AcceptDialog
var filename_input : LineEdit
var populator_type : OptionButton


func _ready() -> void:
	text = "Add Populator"
	pressed.connect(_add_new_populator)
	_create_populate_dialog()


func _create_populate_dialog() -> void:
	populator_dialog = AcceptDialog.new()
	populator_dialog.title = "Add Populator"
	populator_dialog.unresizable = true
	populator_dialog.confirmed.connect(_on_populator_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	
	var type_hbox := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Type:"
	type_hbox.add_child(type_label)
	
	populator_type = OptionButton.new()
	populator_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for type in PopulatorType.size():
		populator_type.add_item(str(PopulatorType.find_key(type)))
		populator_type.selected = 0
	type_hbox.add_child(populator_type)
	cont.add_child(type_hbox)
	
	var name_hbox := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Name:"
	name_hbox.add_child(name_label)
	
	filename_input = LineEdit.new()
	filename_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filename_input.placeholder_text = "NewPopulator"
	name_hbox.add_child(filename_input)
	cont.add_child(name_hbox)
	
	populator_dialog.add_child(cont)
	
	add_child(populator_dialog)


func _on_populator_confirmed() -> void:
	var populator = POPULATOR_TYPE[populator_type.selected].instantiate()
	
	current_terrain_node.add_child(populator)
	if filename_input.text:
		populator.name = filename_input.text
	else:
		populator.name = POPULATOR_NAMES[populator_type.selected]
	
	populator.terrain_system = current_terrain_node
	populator.setup()
	
	if Engine.is_editor_hint():
		populator.owner = Engine.get_singleton("EditorInterface").get_edited_scene_root()
		
		var plugin := MarchingSquaresTerrainPlugin.instance
		if plugin:
			plugin.current_populator = populator
			plugin.ui.tool_attributes.show_tool_attributes(plugin.mode)
			plugin.ui.populator_settings.add_populator_settings()
			plugin.gizmo_plugin.trigger_redraw(current_terrain_node)


func _add_new_populator() -> void:
	populator_dialog.popup_centered(Vector2(300, 130))
	populator_type.grab_focus()
