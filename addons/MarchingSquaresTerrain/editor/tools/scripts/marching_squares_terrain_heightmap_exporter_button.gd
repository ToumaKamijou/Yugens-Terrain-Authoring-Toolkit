@tool
extends Button
class_name MarchingSquaresTerrainHeightmapExporterButton


var export_dir : String = "res://"

signal _should_change_line_edit

var tool_attributes : MarchingSquaresToolAttributes

var filename_dialog : AcceptDialog
var filename_input : LineEdit


func _ready() -> void:
	text = "Export Terrain Heightmap"
	pressed.connect(_export_to_heightmap)
	_create_heightmap_export_dialog()


func _create_heightmap_export_dialog() -> void:
	export_dir = tool_attributes.plugin.hme_output_path
	
	filename_dialog = AcceptDialog.new()
	filename_dialog.title = "Save Terrain Heightmap"
	filename_dialog.unresizable = true
	filename_dialog.confirmed.connect(_on_filename_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	var hbox_name := HBoxContainer.new()
	var label := Label.new()
	label.text = "Enter name:"
	hbox_name.add_child(label)
	
	filename_input = LineEdit.new()
	filename_input.placeholder_text = "new_terrain_heightmap"
	filename_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_name.add_child(filename_input)
	cont.add_child(hbox_name)
	
	var hbox_path := HBoxContainer.new()
	hbox_path.add_theme_constant_override("separation", 4)
	var label_path := Label.new()
	label_path.set_text("Output Path:")
	label_path.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	label_path.set_custom_minimum_size(Vector2(75, 25))
	hbox_path.add_child(label_path, true)
	
	var path_edit := LineEdit.new()
	path_edit.text = export_dir
	path_edit.placeholder_text = "res://"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.text_submitted.connect(func(t):
		open_exporter_folder_dialog("hme_output_path", t)
		export_dir = t
	)
	_should_change_line_edit.connect(func(): path_edit.text = export_dir)
	path_edit.set_custom_minimum_size(Vector2(120, 25))
	hbox_path.add_child(path_edit, true)
	
	var browse_btn := Button.new()
	browse_btn.text = "..."
	browse_btn.tooltip_text = "Browse for output folder"
	browse_btn.set_custom_minimum_size(Vector2(28, 25))
	browse_btn.pressed.connect(func():
		export_dir = tool_attributes.plugin.hme_output_path
		open_exporter_folder_dialog("hme_output_path", export_dir)
	)
	hbox_path.add_child(browse_btn, true)
	cont.add_child(hbox_path)
	
	filename_dialog.add_child(cont)
	
	add_child(filename_dialog)


func open_exporter_folder_dialog(setting_name: String, path: String) -> void:
	var dialog := EditorFileDialog.new()
	dialog.exclusive = false
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Select Output Directory"
	
	if path.is_empty():
		dialog.current_dir = "res://"
	else:
		dialog.current_dir = path
	
	dialog.dir_selected.connect(func(dir: String):
		tool_attributes.on_exporter_setting_changed(setting_name, dir)
		dialog.queue_free()
		export_dir = dir
		_should_change_line_edit.emit()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _export_to_heightmap() -> void:
	filename_input.text = "new_terrain_heightmap"
	
	filename_dialog.popup_centered(Vector2(400, 100))
	filename_input.grab_focus()
	filename_input.select_all()


func _on_filename_confirmed() -> void:
	var filename := filename_input.text.strip_edges().to_lower().to_snake_case()
	
	if filename == "":
		push_error("Filename cannot be empty!")
		return
	
	export_dir = tool_attributes.plugin.hme_output_path
	
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(export_dir):
		dir.make_dir_recursive(export_dir)
	
	var path := export_dir + filename + ".tres"
	
	if FileAccess.file_exists(path):
		_show_overwrite_confirmation(path)
	else:
		_save_heightmap(filename)


func _show_overwrite_confirmation(path: String) -> void:
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "Overwrite File?"
	confirm_dialog.dialog_text = "A heightmap with this name already exists.\nDo you want to overwrite it?"
	
	confirm_dialog.confirmed.connect(
		func():
			_save_heightmap(path)
			confirm_dialog.queue_free()
	)
	
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func _save_heightmap(filename: String) -> void:
	tool_attributes.export_terrain_heightmap(filename)
