@tool
extends Button
class_name MarchingSquaresPopulateButton


enum PopulatorType {FLOWER, VEGETATION}

const POPULATOR_TYPE = {
	PopulatorType.FLOWER: preload("uid://demjm5kq2kdpa"),
	PopulatorType.VEGETATION: preload("uid://jud8opcg5py5"),
}

var current_terrain_node : MarchingSquaresTerrain

var populator_dialog : AcceptDialog
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
	
	var label := Label.new()
	label.text = "Choose populator type:"
	cont.add_child(label)
	
	populator_type = OptionButton.new()
	for type in PopulatorType.size():
		populator_type.add_item(str(PopulatorType.find_key(type)))
		populator_type.selected = 0
	cont.add_child(populator_type)
	
	populator_dialog.add_child(cont)
	
	add_child(populator_dialog)


func _on_populator_confirmed() -> void:
	var populator = POPULATOR_TYPE[populator_type.selected].instantiate()
	
	current_terrain_node.add_child(populator)
	populator.terrain_system = current_terrain_node
	
	populator.setup()
	
	if Engine.is_editor_hint():
		populator.owner = Engine.get_singleton("EditorInterface").get_edited_scene_root()


func _add_new_populator() -> void:
	populator_dialog.popup_centered(Vector2(300, 130))
	populator_type.grab_focus()
