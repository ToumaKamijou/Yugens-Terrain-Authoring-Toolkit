@tool
extends ScrollContainer
class_name MarchingSquaresToolAttributes


signal setting_changed(setting: String, value: Variant)
signal terrain_setting_changed(setting: String, value: Variant)

const TEXTURE_PRESETS_PATH : String= "res://addons/MarchingSquaresTerrain/resources/texture presets/"
const GLOBAL_QUICK_PAINTS_PATH : String = "res://addons/MarchingSquaresTerrain/resources/quick paints/global/"

enum SettingType {
	CHECKBOX,
	SLIDER,
	OPTION,
	TEXT,
	POPULATE_BUTTON,
	CHUNK,
	TERRAIN,
	PRESET,
	QUICK_PAINT,
	ERROR,
}

var terrain_settings_data : Dictionary = {
	"dimensions": "Vector3i",
	"cell_size": "Vector2",
	"blend_mode": "OptionButton",
	"noise_hmap": "EditorResourcePicker",
	"default_wall_texture": "OptionButton",
	# Grass settings
	"animation_fps": "SpinBox",
	"grass_subdivisions": "SpinBox",
	"grass_size": "Vector2",
	"use_ridge_texture": "CheckBox",
	"ridge_threshold": "EditorSpinSlider",
	"ledge_threshold": "EditorSpinSlider",
	"extra_collision_layer": "OptionButton",
}

var plugin : MarchingSquaresTerrainPlugin
var attribute_list : MarchingSquaresToolAttributesList
var settings : Dictionary = {}

var last_setting_type : SettingType = SettingType.ERROR
var selected_chunk : MarchingSquaresTerrainChunk
var selected_populator : MarchingSquaresPopulator

var hbox_container


func _ready() -> void:
	set_custom_minimum_size(Vector2(0, 35))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func show_tool_attributes(tool_index: int) -> void:
	hbox_container = HBoxContainer.new()
	hbox_container.add_theme_constant_override("separation", 5)
	hbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_container.size_flags_vertical = Control.SIZE_FILL
	
	if not visible:
		return
	
	for child in get_children():
		child.queue_free()
	settings.clear()
	
	if not plugin.toolbar.toolbox:
		return
	
	var tool = plugin.toolbar.toolbox.tools.get(tool_index)
	var tool_attributes : MarchingSquaresToolAttributeSettings = tool.get("attributes")
	var type_map = {
		"slider": SettingType.SLIDER,
		"checkbox": SettingType.CHECKBOX,
		"option": SettingType.OPTION,
		"text": SettingType.TEXT,
		"populate_button": SettingType.POPULATE_BUTTON,
		"chunk": SettingType.CHUNK,
		"terrain": SettingType.TERRAIN,
		"preset": SettingType.PRESET,
		"quick_paint": SettingType.QUICK_PAINT,
	}
	
	var new_attributes := []
	if tool_attributes.brush_type:
		new_attributes.append(attribute_list.brush_type)
	if tool_attributes.size:
		new_attributes.append(attribute_list.size)
	if tool_attributes.ease_value:
		new_attributes.append(attribute_list.ease_value)
	if tool_attributes.height:
		new_attributes.append(attribute_list.height)
	if tool_attributes.strength:
		new_attributes.append(attribute_list.strength)
	if tool_attributes.flatten:
		new_attributes.append(attribute_list.flatten)
	if tool_attributes.falloff:
		new_attributes.append(attribute_list.falloff)
	if tool_attributes.mask_mode:
		new_attributes.append(attribute_list.mask_mode)
	if tool_attributes.material:
		new_attributes.append(attribute_list.material)
	if tool_attributes.texture_name:
		new_attributes.append(attribute_list.texture_name)
	if tool_attributes.texture_preset:
		new_attributes.append(attribute_list.texture_preset)
	if tool_attributes.quick_paint_selection:
		new_attributes.append(attribute_list.quick_paint_selection)
	if tool_attributes.paint_walls:
		new_attributes.append(attribute_list.paint_walls)
	if tool_attributes.planter:
		new_attributes.append(attribute_list.planter)
	if tool_attributes.populate_terrain:
		new_attributes.append(attribute_list.populate_terrain)
	if tool_attributes.chunk_management:
		new_attributes.append(attribute_list.chunk_management)
	if tool_attributes.terrain_settings:
		new_attributes.append(attribute_list.terrain_settings)
	
	for attribute in new_attributes:
		var setting_dict : Dictionary = attribute
		if setting_dict.has("type") and setting_dict["type"] is String:
			setting_dict["type"] = type_map.get(setting_dict["type"], SettingType.ERROR)
		add_setting(setting_dict)
	
	add_child(hbox_container)
	last_setting_type = SettingType.ERROR # Reset the setting type for correct VSeparators


func add_setting(p_params: Dictionary) -> void:
	var setting_name : String = p_params.get("name", "")
	var setting_type : SettingType = p_params.get("type", SettingType.ERROR)
	var label_text : String = p_params.get("label", setting_name)
	
	if last_setting_type != SettingType.ERROR:
		if last_setting_type == SettingType.SLIDER and setting_type == SettingType.SLIDER:
			pass
		elif last_setting_type != setting_type:
			hbox_container.add_child(VSeparator.new())
	
	var add_label := true
	if setting_type == SettingType.CHUNK or setting_type == SettingType.TERRAIN:
		add_label = false
	if add_label:
		var label := Label.new()
		label.set_text(label_text + ':')
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 25))
		
		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 35))
		c_cont.add_child(label, true)
		hbox_container.add_child(c_cont, true)
	
	var cont
	var saved_setting_value = _get_setting_value(setting_name)
	match setting_type:
		SettingType.CHECKBOX:
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = p_params.get("default", false) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				checkbox.button_pressed = saved_setting_value
			checkbox.toggled.connect(func(pressed): _on_setting_changed(setting_name, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(checkbox, true)
			hbox_container.add_child(cont, true)
		SettingType.SLIDER:
			var range_data = p_params.get("range", Vector3(1.0, 50.0, 0.5))
			var range_min = range_data.x
			var range_max = range_data.y
			var range_step = range_data.z
			var default_value = p_params.get("default", 10.0) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				default_value = saved_setting_value
			
			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(80, 35))
			if setting_name == "height" or setting_name == "ease_value":
				var spin_slider := EditorSpinSlider.new()
				spin_slider.set_flat(true)
				spin_slider.allow_greater = true
				spin_slider.allow_lesser = true
				spin_slider.set_min(range_min)
				spin_slider.set_max(range_max)
				spin_slider.set_step(range_step)
				spin_slider.set_value(default_value)
				spin_slider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				spin_slider.set_custom_minimum_size(Vector2(80, 35))
				
				cont.add_theme_constant_override("margin_top", -5)
				cont.add_child(spin_slider, true)
			else:
				var hslider := HSlider.new()
				hslider.set_min(range_min)
				hslider.set_max(range_max)
				hslider.set_step(range_step)
				hslider.set_value(default_value)
				hslider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				hslider.set_custom_minimum_size(Vector2(80, 35))
				
				cont.add_theme_constant_override("margin_right", 10)
				cont.add_theme_constant_override("margin_left", -3)
				cont.add_child(hslider, true)
			hbox_container.add_child(cont, true)
		SettingType.OPTION:
			var options : Array = p_params.get("options", [])
			var option_button := OptionButton.new()
			for option in options:
				option_button.add_item(option)
			if setting_name == "planter":
				for child in plugin.current_terrain_node.get_children():
					if child is MarchingSquaresPopulator:
						option_button.add_item(str(child.name))
						if plugin.current_populator == null:
							plugin.current_populator = child
			var default_value = p_params.get("default", 0) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				default_value = saved_setting_value
			option_button.selected = default_value
			
			option_button.set_flat(true)
			option_button.item_selected.connect(func(index): _on_setting_changed(setting_name, index))
			if setting_name == "planter":
				option_button.item_selected.connect(func(planter): _on_populator_selected(option_button.get_item_text(planter)))
			option_button.set_custom_minimum_size(Vector2(65, 35))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TEXT:
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.expand_to_text_length = true
			line_edit.placeholder_text = p_params.get("default", "New text here...")
			line_edit.text_submitted.connect(func(new_text): _on_setting_changed(setting_name, new_text))
			line_edit.text_submitted.connect(func(_text): line_edit.clear())
			line_edit.set_custom_minimum_size(Vector2(25, 25))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(line_edit, true)
			hbox_container.add_child(cont, true)
		SettingType.POPULATE_BUTTON:
			var button = MarchingSquaresPopulateButton.new()
			button.current_terrain_node = plugin.current_terrain_node
			
			cont = MarginContainer.new()
			cont.add_theme_constant_override("margin_bottom", 2)
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(button, true)
			hbox_container.add_child(cont, true)
		SettingType.PRESET:
			var preset_button := OptionButton.new()
			var dir : DirAccess
			var file_name : String
			preset_button.add_item("None") # First option is no preset
			preset_button.set_item_metadata(0, null)
			if setting_name == "texture_preset":
				dir = DirAccess.open(TEXTURE_PRESETS_PATH)
				if dir:
					dir.list_dir_begin()
					file_name = dir.get_next()
					while file_name != "":
						if file_name.ends_with(".tres") or file_name.ends_with(".res"):
							var texture_preset := load(TEXTURE_PRESETS_PATH + file_name) as MarchingSquaresTexturePreset
							if texture_preset:
								preset_button.add_item(texture_preset.preset_name)
								preset_button.set_item_metadata(preset_button.item_count - 1, texture_preset)
						file_name = dir.get_next()
					dir.list_dir_end()
				
				preset_button.set_flat(true)
				preset_button.item_selected.connect(func(index):
					var selected_texture_preset = preset_button.get_item_metadata(index)
					_on_setting_changed(setting_name, selected_texture_preset)
				)
				preset_button.set_custom_minimum_size(Vector2(100, 35))
				
				# Sync dropdown selection with current plugin.current_texture_preset
				var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
				var current_texture_preset = terrain.current_texture_preset if terrain else null
				if current_texture_preset == null:
					preset_button.select(0)  # Select "None"
				else:
					# Find matching preset in dropdown
					for i in range(preset_button.item_count):
						if preset_button.get_item_metadata(i) == current_texture_preset:
							preset_button.select(i)
							break
				
				cont = CenterContainer.new()
				cont.set_custom_minimum_size(Vector2(100, 35))
				cont.add_child(preset_button, true)
				hbox_container.add_child(cont, true)
			else: # Can be used for e.g. terrain settings presets in the future
				pass 
		SettingType.QUICK_PAINT:
			var quick_paint_button := OptionButton.new()
			quick_paint_button.add_item("None")  # First option is no paint. #TODO Doesn't seem to work right now and needs to be fixed later.
			quick_paint_button.set_item_metadata(0, null)
			
			# 1. Load GLOBAL quick paints from folder (always available)
			var dir := DirAccess.open(GLOBAL_QUICK_PAINTS_PATH)
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name != "":
					if file_name.ends_with(".tres") or file_name.ends_with(".res"):
						var quick_paint := load(GLOBAL_QUICK_PAINTS_PATH + file_name) as MarchingSquaresQuickPaint
						if quick_paint:
							quick_paint_button.add_item(quick_paint.paint_name)
							quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint)
					file_name = dir.get_next()
				dir.list_dir_end()
			
			# 2. Load PRESET-SPECIFIC quick paints (if preset is selected and has any)
			var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
			if terrain and terrain.current_texture_preset:
				var preset := terrain.current_texture_preset
				if preset.quick_paints.size() > 0:
					quick_paint_button.add_separator()  # Visual separator
					for quick_paint in preset.quick_paints:
						if quick_paint:
							quick_paint_button.add_item(quick_paint.paint_name)
							quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint)
			
			quick_paint_button.set_flat(true)
			quick_paint_button.item_selected.connect(func(index):
				var selected_quick_paint = quick_paint_button.get_item_metadata(index)
				_on_setting_changed(setting_name, selected_quick_paint)
			)
			quick_paint_button.set_custom_minimum_size(Vector2(100, 35))
			
			# Sync dropdown selection with current plugin.current_quick_paint
			var current_quick_paint = _get_setting_value(setting_name)
			if current_quick_paint == null:
				quick_paint_button.select(0)  # Select "None"
			else:
				# Find matching quick paint in dropdown
				for i in range(quick_paint_button.item_count):
					if quick_paint_button.get_item_metadata(i) == current_quick_paint:
						quick_paint_button.select(i)
						break
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(100, 35))
			cont.add_child(quick_paint_button, true)
			hbox_container.add_child(cont, true)
		SettingType.CHUNK:
			if plugin.current_terrain_node.get_child_count() == 0:
				return
			var chunks : Array[MarchingSquaresTerrainChunk]
			for child in plugin.current_terrain_node.get_children():
				if child is MarchingSquaresTerrainChunk:
					chunks.append(child)
			var chunk_button := OptionButton.new()
			for chunk in chunks:
				chunk_button.add_item("Chunk " + str(chunk.chunk_coords))
			chunk_button.selected = 0
			for child in plugin.current_terrain_node.get_children():
				if child is MarchingSquaresTerrainChunk:
					selected_chunk = child
					break
				else:
					continue
			
			var option_button := OptionButton.new()
			option_button.set_flat(true)
			option_button.set_custom_minimum_size(Vector2(65, 35))
			for mode in MarchingSquaresTerrainChunk.Mode:
				option_button.add_item(mode)
			option_button.selected = 1 # Fallback base value
			option_button.selected = selected_chunk.merge_mode
			option_button.item_selected.connect(_on_chunk_mode_changed)
			
			chunk_button.set_flat(true)
			chunk_button.item_selected.connect(func(chunk): _on_chunk_selected(option_button, chunk_button.get_item_text(chunk)))
			chunk_button.set_custom_minimum_size(Vector2(65, 35))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(chunk_button, true)
			hbox_container.add_child(cont, true)
			
			var v_sep := VSeparator.new()
			hbox_container.add_child(v_sep, true)
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TERRAIN:
			var vbox := VBoxContainer.new()
			for setting in terrain_settings_data:
				var editor_setting = terrain_settings_data[setting]
				var s_value = plugin.current_terrain_node.get(setting)
				
				var hbox := HBoxContainer.new()
				
				var label := Label.new()
				label.set_text(_make_editor_name(setting) + ':')
				label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
				label.set_custom_minimum_size(Vector2(50, 25))
				
				var label_c_cont := CenterContainer.new()
				label_c_cont.set_custom_minimum_size(Vector2(50, 35))
				label_c_cont.offset_right = 200
				label_c_cont.add_child(label, true)
				hbox.add_child(label_c_cont, true)
				
				var spacer := Control.new()
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(spacer)
				
				var ts_cont : Control
				match editor_setting:
					"Vector2":
						var editor_vec2 = _make_vector_editor(editor_setting, s_value, setting)
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(130, 35))
						ts_cont.add_child(editor_vec2, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"Vector3i":
						var editor_vec3i = _make_vector_editor(editor_setting, s_value, setting)
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(185, 35))
						ts_cont.add_child(editor_vec3i, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"SpinBox":
						var spin_box := SpinBox.new()
						spin_box.value = plugin.current_terrain_node.get(setting)
						spin_box.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
						spin_box.set_custom_minimum_size(Vector2(25, 25))
						
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(35, 35))
						ts_cont.add_child(spin_box, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"EditorSpinSlider":
						var spin_slider := EditorSpinSlider.new()
						spin_slider.set_flat(true)
						spin_slider.set_min(0.0)
						if setting == "wall_threshold":
							spin_slider.set_max(0.5)
						else:
							spin_slider.set_max(1.0)
						spin_slider.set_step(0.01)
						spin_slider.set_value(s_value)
						spin_slider.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
						spin_slider.set_custom_minimum_size(Vector2(105, 35))
						
						ts_cont = MarginContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(105, 35))
						ts_cont.add_theme_constant_override("margin_top", -5)
						ts_cont.add_child(spin_slider, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"EditorResourcePicker":
						var editor_r_picker := EditorResourcePicker.new()
						if setting == "noise_hmap":
							editor_r_picker.set_base_type("Noise")
						else:
							editor_r_picker.set_base_type("Texture2D")
						editor_r_picker.edited_resource = plugin.current_terrain_node.get(setting)
						_hide_textures(editor_r_picker)
						editor_r_picker.resource_changed.connect(func(resource): _on_terrain_setting_changed(setting, resource))
						editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
						
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(110, 35))
						ts_cont.add_child(editor_r_picker, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"ColorPickerButton":
						var c_pick_button := ColorPickerButton.new()
						c_pick_button.color = plugin.current_terrain_node.get(setting)
						c_pick_button.color_changed.connect(func(color): _on_terrain_setting_changed(setting, color))
						c_pick_button.set_custom_minimum_size(Vector2(105, 25))
						
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(105, 35))
						ts_cont.add_child(c_pick_button, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"CheckBox":
						var checkbox := CheckBox.new()
						checkbox.set_flat(true)
						checkbox.button_pressed = plugin.current_terrain_node.get(setting)
						checkbox.toggled.connect(func(pressed): _on_terrain_setting_changed(setting, pressed))
						checkbox.set_custom_minimum_size(Vector2(25, 25))
						
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(35, 35))
						ts_cont.add_child(checkbox, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
					"OptionButton":
						var option_button := OptionButton.new()
						option_button.set_flat(true)
						if setting == "default_wall_texture":
							# Populate with texture names from the shared texture names resource
							for tex_name in attribute_list.vp_tex_names.texture_names:
								option_button.add_item(tex_name)
						elif setting == "blend_mode":
							option_button.add_item("Smoothed Triangles")
							option_button.add_item("Hard Squares")
							option_button.add_item("Hard Triangles")
						elif setting == "extra_collision_layer":
							for i in range(24):
								option_button.add_item(str(i+9))
						# Set current selection from terrain node
						if setting == "extra_collision_layer":
							option_button.selected = plugin.current_terrain_node.get(setting) - 9
						else:
							option_button.selected = plugin.current_terrain_node.get(setting)
						option_button.item_selected.connect(func(index): _on_terrain_setting_changed(setting, index))
						option_button.set_custom_minimum_size(Vector2(100, 35))
						
						ts_cont = CenterContainer.new()
						ts_cont.set_custom_minimum_size(Vector2(100, 35))
						ts_cont.add_child(option_button, true)
						hbox.add_child(ts_cont, true)
						vbox.add_child(hbox, true)
				if vbox.get_child_count() % 3 == 0 and setting != terrain_settings_data.keys().back():
					hbox_container.add_child(vbox)
					hbox_container.add_child(VSeparator.new())
					vbox = VBoxContainer.new()
			if vbox.get_child_count() > 0:
				hbox_container.add_child(vbox)
		SettingType.ERROR: # Fallback
			printerr("ERROR: [MarchingSquaresToolAttributes] couldn't load tool attributes setting")
	
	last_setting_type = setting_type


func _get_setting_value(p_setting_name: String) -> Variant:
	match p_setting_name:
		"brush_type":
			return plugin.current_brush_index
		"size":
			return plugin.brush_size
		"ease_value":
			return plugin.ease_value
		"height":
			return plugin.height
		"strength":
			return plugin.height
		"flatten":
			return plugin.flatten
		"falloff":
			return plugin.falloff
		"mask_mode":
			return plugin.should_mask_grass
		"material":
			return plugin.vertex_color_idx
		"texture_name":
			pass
		"texture_preset":
			return plugin.current_texture_preset
		"quick_paint_selection":
			return plugin.current_quick_paint
		"paint_walls":
			return plugin.paint_walls_mode
		"planter":
			pass
		"populate_terrain":
			pass
		"chunk_management":
			pass
		"terrain_settings":
			pass
		_:
			printerr("ERROR: [MarchingSquaresToolAttributes] couldn't find tool attributes setting name")
	return "ERROR"


func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_setting_name, p_value)


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("terrain_setting_changed", p_setting_name, p_value)


func _on_chunk_selected(option_button: OptionButton, p_chunk: String) -> void:
	var terrain := plugin.current_terrain_node
	var chunk : MarchingSquaresTerrainChunk = terrain.find_child(p_chunk)
	
	option_button.selected = chunk.merge_mode
	selected_chunk = chunk


func _on_populator_selected(p_populator: String) -> void:
	var terrain := plugin.current_terrain_node
	var populator : MarchingSquaresPopulator = terrain.find_child(p_populator)
	
	selected_populator = populator
	plugin.current_populator = populator


func _on_chunk_mode_changed(m_mode: int) -> void:
	match MarchingSquaresTerrainChunk.Mode.find_key(m_mode):
		"CUBIC":
			selected_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
		"POLYHEDRON":
			selected_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.POLYHEDRON
		"ROUNDED_POLYHEDRON":
			selected_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.ROUNDED_POLYHEDRON
		"SEMI_ROUND":
			selected_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SEMI_ROUND
		"SPHERICAL":
			selected_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SPHERICAL


func _make_vector_editor(type: String, value: Variant, setting_name: String) -> HBoxContainer:
	var hbox_cont := HBoxContainer.new()
	
	if type == "Vector2":
		var spin_x := _make_spinbox(value.x, 0.1)
		var spin_y := _make_spinbox(value.y, 0.1)
		
		var handler_x = func(v):
			var updated_val = Vector2(v, spin_y.value)
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y = func(v):
			var updated_val = Vector2(spin_x.value, v)
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
	
	elif type == "Vector3i":
		var spin_x := _make_spinbox(value.x, 1.0)
		var spin_y := _make_spinbox(value.y, 1.0)
		var spin_z := _make_spinbox(value.z, 1.0)
		
		var handler_x = func(v):
			var updated_val = Vector3i(int(v), int(spin_y.value), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y = func(v):
			var updated_val = Vector3i(int(spin_x.value), int(v), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_z = func(v):
			var updated_val = Vector3i(int(spin_x.value), int(spin_y.value), int(v))
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		spin_z.value_changed.connect(handler_z)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
		hbox_cont.add_child(spin_z)
	
	return hbox_cont


func _make_spinbox(val: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.set_step(step)
	spin_box.set_value(float(val))
	spin_box.set_custom_minimum_size(Vector2(50, 25))
	return spin_box


func _make_editor_name(var_name: String) -> String:
	var loose_words := var_name.split("_")
	for word in loose_words:
		loose_words[loose_words.find(word)] = word.capitalize()
	return " ".join(loose_words)


func _hide_textures(texture_node: Node) -> void:
	var texture_button := texture_node.get_child(0) as Button
	texture_button.visible = false
