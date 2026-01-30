@tool
extends Button
class_name MarchingSquaresTexturePresetExporter


const PRESET_DIR = "res://addons/MarchingSquaresTerrain/resources/texture presets/"
const TEXTURE_NAMES = preload("res://addons/MarchingSquaresTerrain/resources/texture_names.tres")

var current_terrain_node : MarchingSquaresTerrain

var texture_preset_data : MarchingSquaresTextureList
var filename_dialog : AcceptDialog
var filename_input : LineEdit


func _ready() -> void:
	text = "Export Texture Preset"
	pressed.connect(_export_to_texture_preset)
	_create_texture_export_dialog()


func _create_texture_export_dialog() -> void:
	filename_dialog = AcceptDialog.new()
	filename_dialog.title = "Save Preset"
	filename_dialog.unresizable = true
	filename_dialog.confirmed.connect(_on_filename_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	var label := Label.new()
	label.text = "Enter preset name:"
	cont.add_child(label)
	
	filename_input = LineEdit.new()
	filename_input.placeholder_text = "new_texture_preset"
	cont.add_child(filename_input)
	
	filename_dialog.add_child(cont)
	
	add_child(filename_dialog)


func _export_to_texture_preset() -> void:
	texture_preset_data = _get_current_texture_data()
	
	filename_input.text = "new_texture_preset"
	
	filename_dialog.popup_centered(Vector2(400, 150))
	filename_input.grab_focus()
	filename_input.select_all()


func _on_filename_confirmed() -> void:
	var filename = filename_input.text.strip_edges().to_lower().to_snake_case()
	
	if filename == "":
		push_error("Filename cannot be empty!")
		return
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(PRESET_DIR):
		dir.make_dir_recursive(PRESET_DIR)
	
	var path = PRESET_DIR + filename + ".tres"
	
	if FileAccess.file_exists(path):
		_show_overwrite_confirmation(path)
	else:
		_save_preset(path)


func _show_overwrite_confirmation(path: String) -> void:
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Overwrite File?"
	confirm_dialog.dialog_text = "A preset with this name already exists.\nDo you want to overwrite it?"
	
	confirm_dialog.confirmed.connect(
		func():
			_save_preset(path)
			confirm_dialog.queue_free()
	)
	
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func _show_success_notification():
	if Engine.is_editor_hint():
		EditorInterface.get_base_control().show_accept_dialog("Preset saved successfully!\nSaved to: " + PRESET_DIR, "Success")


func _save_preset(path: String) -> void:
	var new_tex_preset = MarchingSquaresTexturePreset.new()
	
	new_tex_preset.preset_name = filename_input.text
	new_tex_preset.new_textures = texture_preset_data
	new_tex_preset.new_tex_names = TEXTURE_NAMES.duplicate()
	
	var save_error = ResourceSaver.save(new_tex_preset, path)
	if save_error == OK:
		print("Texture preset saved to: " + path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Failed to save texture preset: ", save_error)


func _get_current_texture_data() -> MarchingSquaresTextureList:
	var new_texture_list := MarchingSquaresTextureList.new()
	
	for i in range(5): # The range is 5 because MarchingSquaresTextureList has 5 export variables (terrain textures, texture scales, grass sprites, grass colors, has_grass)
		match i:
			0: # terrain_textures
				for i_tex in range(new_texture_list.terrain_textures.size()):
					var tex : Texture2D = Texture2D.new()
					match i_tex:
						0:
							tex = current_terrain_node.ground_texture
						1:
							tex = current_terrain_node.texture_2
						2:
							tex = current_terrain_node.texture_3
						3:
							tex = current_terrain_node.texture_4
						4:
							tex = current_terrain_node.texture_5
						5:
							tex = current_terrain_node.texture_6
						6:
							tex = current_terrain_node.texture_7
						7:
							tex = current_terrain_node.texture_8
						8:
							tex = current_terrain_node.texture_9
						9:
							tex = current_terrain_node.texture_10
						10:
							tex = current_terrain_node.texture_11
						11:
							tex = current_terrain_node.texture_12
						12:
							tex = current_terrain_node.texture_13
						13:
							tex = current_terrain_node.texture_14
						14:
							tex = current_terrain_node.texture_15
					new_texture_list.terrain_textures[i_tex] = tex
			1: # texture_scales
				for i_tex_scale in range(new_texture_list.texture_scales.size()):
					var scale : float = 1.0
					match i_tex_scale:
						0:
							scale = current_terrain_node.texture_scale_1
						1:
							scale = current_terrain_node.texture_scale_2
						2:
							scale = current_terrain_node.texture_scale_3
						3:
							scale = current_terrain_node.texture_scale_4
						4:
							scale = current_terrain_node.texture_scale_5
						5:
							scale = current_terrain_node.texture_scale_6
						6:
							scale = current_terrain_node.texture_scale_7
						7:
							scale = current_terrain_node.texture_scale_8
						8:
							scale = current_terrain_node.texture_scale_9
						9:
							scale = current_terrain_node.texture_scale_10
						10:
							scale = current_terrain_node.texture_scale_11
						11:
							scale = current_terrain_node.texture_scale_12
						12:
							scale = current_terrain_node.texture_scale_13
						13:
							scale = current_terrain_node.texture_scale_14
						14:
							scale = current_terrain_node.texture_scale_15
					new_texture_list.texture_scales[i_tex_scale] = scale
			1: # grass_sprites
				for i_grass_tex in range(new_texture_list.grass_sprites.size()):
					var tex : Texture2D = Texture2D.new()
					match i_grass_tex:
						0:
							tex = current_terrain_node.grass_sprite
						1:
							tex = current_terrain_node.grass_sprite_tex_2
						2:
							tex = current_terrain_node.grass_sprite_tex_3
						3:
							tex = current_terrain_node.grass_sprite_tex_4
						4:
							tex = current_terrain_node.grass_sprite_tex_5
						5:
							tex = current_terrain_node.grass_sprite_tex_6
					if tex != null:
						new_texture_list.grass_sprites[i_grass_tex] = tex
			2: # grass_colors
				for i_grass_col in range(new_texture_list.grass_colors.size()):
					var col : Color = Color.PURPLE
					match i_grass_col:
						0:
							col = current_terrain_node.ground_color
						1:
							col = current_terrain_node.ground_color_2
						2:
							col = current_terrain_node.ground_color_3
						3:
							col = current_terrain_node.ground_color_4
						4:
							col = current_terrain_node.ground_color_5
						5:
							col = current_terrain_node.ground_color_6
					if col != null:
						new_texture_list.grass_colors[i_grass_col] = col
			3: # has_grass
				for i_has_grass in range(new_texture_list.has_grass.size()):
					var val : bool = true
					match i_has_grass:
						0:
							val = current_terrain_node.tex2_has_grass
						1:
							val = current_terrain_node.tex3_has_grass
						2:
							val = current_terrain_node.tex4_has_grass
						3:
							val = current_terrain_node.tex5_has_grass
						4:
							val = current_terrain_node.tex6_has_grass
					if val != null:
						new_texture_list.has_grass[i_has_grass] = val
	
	return new_texture_list
