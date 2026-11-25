@tool
extends Button
class_name MarchingSquaresMeshHeightmapExtractorButton


var tool_attributes : MarchingSquaresToolAttributes

var filename_dialog : AcceptDialog
var filename_input : LineEdit


func _ready() -> void:
	text = "Extract Mesh Heightmap"
	pressed.connect(_extract_to_heightmap)
	_create_heightmap_extraction_dialog()


func _create_heightmap_extraction_dialog() -> void:
	tool_attributes.plugin.current_heightmap_mesh == null
	
	filename_dialog = AcceptDialog.new()
	filename_dialog.title = "Save Mesh Heightmap"
	filename_dialog.unresizable = true
	filename_dialog.exclusive = false
	filename_dialog.confirmed.connect(_on_filename_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	var hbox_name := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Enter name:"
	hbox_name.add_child(name_label)
	
	filename_input = LineEdit.new()
	filename_input.placeholder_text = "new_mesh_heightmap"
	filename_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_name.add_child(filename_input)
	cont.add_child(hbox_name)
	
	var hbox_mesh := HBoxContainer.new()
	var mesh_label := Label.new()
	mesh_label.text = "Selected mesh:"
	hbox_mesh.add_child(mesh_label)
	
	var mesh_selector := EditorResourcePicker.new()
	mesh_selector.base_type = "Mesh"
	mesh_selector.edited_resource = tool_attributes.plugin.current_heightmap_mesh
	mesh_selector.resource_changed.connect(func(mesh):
		tool_attributes.on_extractor_setting_changed("selected_heightmap_mesh", mesh)
	)
	mesh_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_mesh.add_child(mesh_selector)
	cont.add_child(hbox_mesh)
	
	filename_dialog.add_child(cont)
	
	add_child(filename_dialog)


func _extract_to_heightmap() -> void:
	filename_input.text = "new_mesh_heightmap"
	
	filename_dialog.popup_centered(Vector2(400, 100))
	filename_input.grab_focus()
	filename_input.select_all()


func _on_filename_confirmed() -> void:
	var filename := filename_input.text.strip_edges().to_lower().to_snake_case()
	
	if filename == "":
		push_error("Filename cannot be empty!")
		return
	
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(tool_attributes.plugin.MESH_HEIGHTMAPS_FOLDER_PATH):
		dir.make_dir_recursive(tool_attributes.plugin.MESH_HEIGHTMAPS_FOLDER_PATH)
	
	var path := tool_attributes.plugin.MESH_HEIGHTMAPS_FOLDER_PATH + filename + ".png"
	
	if FileAccess.file_exists(path):
		_show_overwrite_confirmation(path, filename)
	else:
		_save_heightmap(filename)


func _show_overwrite_confirmation(path: String, filename: String) -> void:
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "Overwrite File?"
	confirm_dialog.dialog_text = "A heightmap with this name already exists.\nDo you want to overwrite it?"
	
	confirm_dialog.confirmed.connect(
		func():
			_save_heightmap(filename)
			confirm_dialog.queue_free()
	)
	
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func _save_heightmap(filename: String) -> void:
	tool_attributes.extract_mesh_heightmap(filename)
