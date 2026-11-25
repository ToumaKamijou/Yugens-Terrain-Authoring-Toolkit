@tool
extends Button
class_name MarchingSquaresTexturePresetExporter


const PRESET_DIR = "res://addons/MarchingSquaresTerrain/resources/texture_presets/"
const TEXTURE_NAMES = preload("uid://dd7fens03aosa")

var current_terrain_node : MarchingSquaresTerrain

var texture_preset_data : MarchingSquaresTextureList
var filename_dialog : AcceptDialog
var filename_input : LineEdit
var save_path_input : LineEdit
var include_texture_library_check : CheckBox


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
	
	var path_label := Label.new()
	path_label.text = "Save path:"
	cont.add_child(path_label)
	
	save_path_input = LineEdit.new()
	save_path_input.text = PRESET_DIR
	save_path_input.placeholder_text = PRESET_DIR
	cont.add_child(save_path_input)
	
	include_texture_library_check = CheckBox.new()
	include_texture_library_check.text = "Include Texture Library / Baked Arrays (*)"
	include_texture_library_check.tooltip_text = "Creates a self-contained preset folder with a texture library snapshot and any baked Texture2DArray resources."
	cont.add_child(include_texture_library_check)
	
	filename_dialog.add_child(cont)
	
	add_child(filename_dialog)


func _export_to_texture_preset() -> void:
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(TEXTURE_NAMES)
	texture_preset_data = _get_current_texture_data()
	
	filename_input.text = "new_texture_preset"
	save_path_input.text = PRESET_DIR
	include_texture_library_check.button_pressed = false
	
	filename_dialog.popup_centered(Vector2(400, 150))
	filename_input.grab_focus()
	filename_input.select_all()


func _on_filename_confirmed() -> void:
	var filename := filename_input.text.strip_edges().to_lower().to_snake_case()
	
	if filename == "":
		push_error("Filename cannot be empty!")
		return
	
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(PRESET_DIR):
		dir.make_dir_recursive(PRESET_DIR)
	
	var save_dir := _normalize_save_dir(save_path_input.text)
	var include_library := include_texture_library_check != null and include_texture_library_check.button_pressed
	var path := save_dir + filename + ".tres"
	if include_library:
		var preset_folder := save_dir.path_join(filename)
		var dir_abs := ProjectSettings.globalize_path(preset_folder)
		if not DirAccess.dir_exists_absolute(dir_abs):
			DirAccess.make_dir_recursive_absolute(dir_abs)
		path = preset_folder.path_join(filename + ".tres")
	
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


func _save_preset(path: String) -> void:
	var new_tex_preset := MarchingSquaresTexturePreset.new()
	var include_library := include_texture_library_check != null and include_texture_library_check.button_pressed
	
	new_tex_preset.preset_name = filename_input.text
	new_tex_preset.new_textures = texture_preset_data
	if not include_library:
		_strip_texture_resources(new_tex_preset.new_textures)
	
	# Copy per-slot names from the currently active preset (if present) so names persist.
	var src_names : MarchingSquaresTextureNames = TEXTURE_NAMES
	if current_terrain_node and current_terrain_node.current_texture_preset and current_terrain_node.current_texture_preset.new_tex_names:
		src_names = current_terrain_node.current_texture_preset.new_tex_names
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(src_names)
	new_tex_preset.new_tex_names = src_names.duplicate(true)
	
	# Copy palette and surface settings from the current terrain so the exported preset is a true "look" preset.
	if current_terrain_node != null:
		if current_terrain_node.get("visible_texture_slot_count") != null:
			new_tex_preset.visible_texture_slot_count = clampi(int(current_terrain_node.visible_texture_slot_count), 6, MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
		if current_terrain_node.get("slot_color_indices") is Array:
			new_tex_preset.slot_color_indices = current_terrain_node.slot_color_indices.duplicate(true)
		if current_terrain_node.get("slot_blend_modes") is Array:
			new_tex_preset.slot_blend_modes = current_terrain_node.slot_blend_modes.duplicate()
		if current_terrain_node.get("palette_weights") is Array:
			new_tex_preset.palette_weights = current_terrain_node.palette_weights.duplicate()
		if current_terrain_node.get("slot_wet_enabled") is Array:
			new_tex_preset.slot_wet_enabled = current_terrain_node.slot_wet_enabled.duplicate()
		if current_terrain_node.get("slot_wet_modes") is Array:
			new_tex_preset.slot_wet_modes = current_terrain_node.slot_wet_modes.duplicate()
		if current_terrain_node.get("slot_roughnesses") is Array:
			new_tex_preset.slot_roughnesses = current_terrain_node.slot_roughnesses.duplicate()
		if current_terrain_node.get("slot_grass_wetnesses") is Array:
			new_tex_preset.slot_grass_wetnesses = current_terrain_node.slot_grass_wetnesses.duplicate()
		if current_terrain_node.get("slot_floor_noise_enabled") is Array:
			new_tex_preset.slot_floor_noise_enabled = current_terrain_node.slot_floor_noise_enabled.duplicate()
		if current_terrain_node.get("slot_floor_noise_strengths") is Array:
			new_tex_preset.slot_floor_noise_strengths = current_terrain_node.slot_floor_noise_strengths.duplicate()
		if current_terrain_node.get("slot_floor_noise_scales") is Array:
			new_tex_preset.slot_floor_noise_scales = current_terrain_node.slot_floor_noise_scales.duplicate()
		if current_terrain_node.get("slot_wall_noise_enabled") is Array:
			new_tex_preset.slot_wall_noise_enabled = current_terrain_node.slot_wall_noise_enabled.duplicate()
		if current_terrain_node.get("slot_wall_noise_strengths") is Array:
			new_tex_preset.slot_wall_noise_strengths = current_terrain_node.slot_wall_noise_strengths.duplicate()
		if current_terrain_node.get("slot_wall_noise_scales") is Array:
			new_tex_preset.slot_wall_noise_scales = current_terrain_node.slot_wall_noise_scales.duplicate()
		if current_terrain_node.get("texture_slots") is Array:
			new_tex_preset.slot_texture_scales.resize(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
			for i in range(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS):
				var slot = current_terrain_node.texture_slots[i] if i < current_terrain_node.texture_slots.size() else null
				new_tex_preset.slot_texture_scales[i] = float(slot.scale) if slot != null else 1.0
	
	# If a preset is currently selected, inherit its Global Settings apply flags so exports preserve intent.
	if current_terrain_node != null and current_terrain_node.current_texture_preset != null:
		var src_preset := current_terrain_node.current_texture_preset
		if src_preset.get("apply_vertex_painter_settings") != null:
			new_tex_preset.apply_vertex_painter_settings = bool(src_preset.apply_vertex_painter_settings)
		if src_preset.get("apply_grass_settings") != null:
			new_tex_preset.apply_grass_settings = bool(src_preset.apply_grass_settings)
	
	if include_library:
		_save_texture_library_snapshot(new_tex_preset, path)
		_copy_baked_arrays_to_preset(new_tex_preset, path)
	
	var save_error := ResourceSaver.save(new_tex_preset, path)
	if save_error == OK:
		print_verbose("Texture preset saved to: " + path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Failed to save texture preset: ", save_error)


func _coerce_texture2d(tex) -> Texture2D:
	return tex as Texture2D if tex is Texture2D else null


func _get_slot_albedo_texture(slot_idx: int) -> Texture2D:
	if current_terrain_node == null or slot_idx < 0 or slot_idx >= MarchingSquaresTextureList.MAX_TEXTURE_SLOTS:
		return null
	if current_terrain_node.get("texture_slots") is Array and current_terrain_node.texture_slots.size() > slot_idx:
		var slot = current_terrain_node.texture_slots[slot_idx]
		if slot != null:
			var slot_tex := _coerce_texture2d(slot.get("texture"))
			if slot_tex != null:
				return slot_tex
	var lib_res = current_terrain_node.get("texture_library")
	if lib_res != null and lib_res is MSTextureLibrary:
		lib_res.ensure_length()
		if slot_idx < lib_res.albedo_textures.size():
			return _coerce_texture2d(lib_res.albedo_textures[slot_idx])
	if slot_idx < 15:
		return _coerce_texture2d(current_terrain_node.get("texture_%d" % (slot_idx + 1)))
	return null


func _get_slot_scale(slot_idx: int) -> float:
	if current_terrain_node == null or slot_idx < 0 or slot_idx >= MarchingSquaresTextureList.MAX_TEXTURE_SLOTS:
		return 1.0
	if current_terrain_node.get("texture_slots") is Array and current_terrain_node.texture_slots.size() > slot_idx:
		var slot = current_terrain_node.texture_slots[slot_idx]
		if slot != null and slot.get("scale") != null:
			return float(slot.scale)
	if slot_idx < 15 and current_terrain_node.get("texture_scale_%d" % (slot_idx + 1)) != null:
		return float(current_terrain_node.get("texture_scale_%d" % (slot_idx + 1)))
	return 1.0


func _build_export_texture_library_snapshot() -> Resource:
	if current_terrain_node == null or not current_terrain_node.has_method("get"):
		return null
	
	var lib_copy : MSTextureLibrary = null
	if current_terrain_node.has_method("_build_texture_library_from_slots"):
		lib_copy = current_terrain_node._build_texture_library_from_slots()
	else:
		lib_copy = MSTextureLibrary.new()
	
	if lib_copy == null:
		return null
	
	lib_copy.max_slots = MarchingSquaresTextureList.MAX_TEXTURE_SLOTS
	lib_copy.ensure_length()
	if current_terrain_node.has_method("_ensure_texture_slots"):
		current_terrain_node._ensure_texture_slots()
	if current_terrain_node.get("texture_slots") is Array:
		for i in range(min(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS, current_terrain_node.texture_slots.size())):
			var slot = current_terrain_node.texture_slots[i]
			if slot == null:
				continue
			lib_copy.albedo_textures[i] = _coerce_texture2d(slot.get("texture"))
			lib_copy.grass_textures[i] = _coerce_texture2d(slot.get("grass_texture"))
	
	return lib_copy


func _get_current_texture_data() -> MarchingSquaresTextureList:
	var new_texture_list := MarchingSquaresTextureList.new()
	
	if current_terrain_node.has_method("_ensure_texture_slots"):
		current_terrain_node._ensure_texture_slots()
	
	# Terrain textures (first 15 legacy compatibility payload)
	for i_tex in range(new_texture_list.terrain_textures.size()):
		new_texture_list.terrain_textures[i_tex] = _get_slot_albedo_texture(i_tex)
	
	# Texture scales (first 15 legacy compatibility payload)
	for i_tex_scale in range(new_texture_list.texture_scales.size()):
		new_texture_list.texture_scales[i_tex_scale] = _get_slot_scale(i_tex_scale)
	
	# Palette colors (0..127) are stored in new_textures.grass_colors for historical reasons.
	if current_terrain_node.get("palette_colors") is Array:
		new_texture_list.grass_colors.resize(128)
		var pal_size := current_terrain_node.palette_colors.size()
		for i in range(128):
			new_texture_list.grass_colors[i] = current_terrain_node.palette_colors[i] if i < pal_size else Color.WHITE
	
	# Slot-based grass sprites + has-grass flags (0..255)
	if current_terrain_node.get("texture_slots") is Array and current_terrain_node.texture_slots.size() >= MarchingSquaresTextureList.MAX_TEXTURE_SLOTS:
		new_texture_list.grass_sprites.resize(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
		new_texture_list.has_grass.resize(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
		for i in range(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS):
			var slot = current_terrain_node.texture_slots[i]
			new_texture_list.grass_sprites[i] = slot.grass_texture if slot != null else null
			new_texture_list.has_grass[i] = bool(slot.has_grass) if slot != null else (i == 0)
	else:
		# Legacy fallback (first 6 only); keep arrays at MAX_TEXTURE_SLOTS.
		new_texture_list.grass_sprites[0] = current_terrain_node.grass_sprite_tex_1
		new_texture_list.grass_sprites[1] = current_terrain_node.grass_sprite_tex_2
		new_texture_list.grass_sprites[2] = current_terrain_node.grass_sprite_tex_3
		new_texture_list.grass_sprites[3] = current_terrain_node.grass_sprite_tex_4
		new_texture_list.grass_sprites[4] = current_terrain_node.grass_sprite_tex_5
		new_texture_list.grass_sprites[5] = current_terrain_node.grass_sprite_tex_6
		new_texture_list.has_grass[0] = bool(current_terrain_node.get("tex1_has_grass")) if current_terrain_node.get("tex1_has_grass") != null else true
		new_texture_list.has_grass[1] = bool(current_terrain_node.tex2_has_grass)
		new_texture_list.has_grass[2] = bool(current_terrain_node.tex3_has_grass)
		new_texture_list.has_grass[3] = bool(current_terrain_node.tex4_has_grass)
		new_texture_list.has_grass[4] = bool(current_terrain_node.tex5_has_grass)
		new_texture_list.has_grass[5] = bool(current_terrain_node.tex6_has_grass)
	
	return new_texture_list


func _strip_texture_resources(texture_list: MarchingSquaresTextureList) -> void:
	if texture_list == null:
		return
	for i in range(texture_list.terrain_textures.size()):
		texture_list.terrain_textures[i] = null
	for i in range(texture_list.grass_sprites.size()):
		texture_list.grass_sprites[i] = null


func _normalize_save_dir(raw_dir: String) -> String:
	var save_dir := raw_dir.strip_edges().replace("\\", "/")
	if save_dir.is_empty():
		save_dir = PRESET_DIR
	if not save_dir.begins_with("res://"):
		save_dir = PRESET_DIR
	if not save_dir.ends_with("/"):
		save_dir += "/"
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(save_dir):
		dir.make_dir_recursive(save_dir)
	return save_dir


func _copy_resource_file(src_res_path: String, dst_res_path: String) -> bool:
	if src_res_path.is_empty() or not ResourceLoader.exists(src_res_path):
		return false
	var src_abs := ProjectSettings.globalize_path(src_res_path)
	var dst_abs := ProjectSettings.globalize_path(dst_res_path)
	var src := FileAccess.open(src_abs, FileAccess.READ)
	if src == null:
		push_warning("Failed to read baked array: " + src_res_path)
		return false
	var data := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(dst_abs, FileAccess.WRITE)
	if dst == null:
		push_warning("Failed to write baked array: " + dst_res_path)
		return false
	dst.store_buffer(data)
	dst.close()
	return true


func _copy_baked_arrays_to_preset(preset: MarchingSquaresTexturePreset, preset_path: String) -> void:
	if current_terrain_node == null:
		return
	var preset_dir := preset_path.get_base_dir()
	var baked_dir := preset_dir
	var dir_abs := ProjectSettings.globalize_path(baked_dir)
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
	var paths := {
		"albedo": str(current_terrain_node.get("baked_albedo_array_path")) if current_terrain_node.get("baked_albedo_array_path") != null else "",
		"normal": str(current_terrain_node.get("baked_normal_array_path")) if current_terrain_node.get("baked_normal_array_path") != null else "",
		"grass": str(current_terrain_node.get("baked_grass_array_path")) if current_terrain_node.get("baked_grass_array_path") != null else "",
	}
	var albedo_dst := baked_dir.path_join("baked_albedo_array.res")
	var normal_dst := baked_dir.path_join("baked_normal_array.res")
	var grass_dst := baked_dir.path_join("baked_grass_array.res")
	if _copy_resource_file(paths["albedo"], albedo_dst):
		preset.baked_albedo_array_path = albedo_dst
	if _copy_resource_file(paths["normal"], normal_dst):
		preset.baked_normal_array_path = normal_dst
	if _copy_resource_file(paths["grass"], grass_dst):
		preset.baked_grass_array_path = grass_dst
	if current_terrain_node.get("baked_dense_slot_lookup") != null:
		preset.baked_dense_slot_lookup = current_terrain_node.baked_dense_slot_lookup


func _save_texture_library_snapshot(preset: MarchingSquaresTexturePreset, preset_path: String) -> void:
	var lib_copy := _build_export_texture_library_snapshot()
	if lib_copy == null:
		return
	var lib_path := preset_path.get_base_dir().path_join("texture_library.tres")
	var save_error := ResourceSaver.save(lib_copy, lib_path)
	if save_error == OK:
		var loaded: Resource = ResourceLoader.load(lib_path)
		preset.texture_library = loaded if loaded != null else lib_copy
	else:
		push_warning("Failed to save texture library snapshot for preset: " + str(save_error))
