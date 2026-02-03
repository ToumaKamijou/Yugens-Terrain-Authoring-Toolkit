@tool
extends Button
class_name MarchingSquaresPopulateButton


enum PlanterType {FLOWER, VEGETATION}

const PLANTER_TYPE = {
	PlanterType.FLOWER: preload("res://addons/MarchingSquaresTerrain/algorithm/populate/marching_squares_flower_planter.tscn"),
	PlanterType.VEGETATION: preload("res://addons/MarchingSquaresTerrain/algorithm/populate/marching_squares_vegetation_planter.tscn"),
}

var current_terrain_node : MarchingSquaresTerrain

var planter_dialog : AcceptDialog
var planter_type : OptionButton


func _ready() -> void:
	text = "Add Planter"
	pressed.connect(_add_new_planter)
	_create_populate_dialog()


func _create_populate_dialog() -> void:
	planter_dialog = AcceptDialog.new()
	planter_dialog.title = "Add Planter"
	planter_dialog.unresizable = true
	planter_dialog.confirmed.connect(_on_planter_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	var label := Label.new()
	label.text = "Choose planter type:"
	cont.add_child(label)
	
	planter_type = OptionButton.new()
	for type in PlanterType.size():
		planter_type.add_item(str(PlanterType.find_key(type)))
		planter_type.selected = 0
	cont.add_child(planter_type)
	
	planter_dialog.add_child(cont)
	
	add_child(planter_dialog)


func _on_planter_confirmed() -> void:
	var planter = PLANTER_TYPE[planter_type.selected].instantiate()
	
	current_terrain_node.add_child(planter)
	planter.terrain_system = current_terrain_node
	
	planter.setup()
	
	if Engine.is_editor_hint():
		planter.owner = Engine.get_singleton("EditorInterface").get_edited_scene_root()


func _add_new_planter() -> void:
	planter_dialog.popup_centered(Vector2(300, 130))
	planter_type.grab_focus()
