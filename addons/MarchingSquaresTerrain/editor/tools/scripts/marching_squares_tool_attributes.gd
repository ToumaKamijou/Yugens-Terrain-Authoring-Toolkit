@tool
extends ScrollContainer
class_name MarchingSquaresToolAttributes


signal setting_changed(setting: String, value: Variant)
signal terrain_setting_changed(setting: String, value: Variant)

const TEXTURE_PRESETS_PATH : String= "res://addons/MarchingSquaresTerrain/resources/texture_presets/"
const GLOBAL_QUICK_PAINTS_PATH : String = "res://addons/MarchingSquaresTerrain/resources/quick_paints/global/"

enum SettingType {
	CHECKBOX,
	SLIDER,
	OPTION,
	TEXT,
	CHUNK,
	TERRAIN,
	PRESET,
	QUICK_PAINT,
	HEIGHTMAP,
	ERROR,
}

var terrain_settings_data : Dictionary = {
	"dimensions": "Vector3i",
	"cell_size": "Vector2",
	"blend_mode": "OptionButton",
	"blend_sharpness": "EditorSpinSlider",
	"floor_blend_mode": "OptionButton",
	"blend_noise_threshold": "EditorSpinSlider",
	"noise_hmap": "EditorResourcePicker",
	"default_wall_texture": "OptionButton",
	"collision_thickness": "EditorSpinSlider",
	"nav_agent_radius": "EditorSpinSlider",
	"nav_max_slope": "EditorSpinSlider",
	"nav_max_step_height": "EditorSpinSlider",
	"nav_min_region_size": "EditorSpinSlider",
	"extra_collision_layer": "OptionButton",
	# Grass settings
	"animation_fps": "SpinBox",
	"grass_subdivisions": "SpinBox",
	"grass_size": "Vector2",
	"grass_random_scale": "EditorSpinSlider",
	"use_flat_normals": "CheckBox",
	# Special texture settings
	"use_ridge_texture": "CheckBox",
	"use_ledge_texture": "CheckBox",
	"ridge_threshold": "EditorSpinSlider",
	"ledge_threshold": "EditorSpinSlider",
	"prefab_set": "EditorResourcePicker",
	"use_cell_shading": "CheckBox",
	"wind_direction_degrees": "EditorSpinSlider",
	"wind_speed": "EditorSpinSlider",
	"wind_tip_color": "ColorPickerButton",
	"wind_strength": "EditorSpinSlider",
	"wind_scale": "EditorSpinSlider",
	"wind_gust_strength": "EditorSpinSlider",
	"wind_gust_speed": "EditorSpinSlider",
	"wind_mode": "OptionButton",
	"flower_wind_strength": "EditorSpinSlider",
	"flower_stem_bend": "EditorSpinSlider",
	"flower_tip_flutter": "EditorSpinSlider",
}

const TERRAIN_SETTINGS_CHUNK_TAB := [
	"dimensions",
	"cell_size",
	"prefab_set",
	"extra_collision_layer",
	"collision_thickness",
]

const CHUNK_MANAGEMENT_NAVMESH_SETTINGS := [
	"nav_agent_radius",
	"nav_max_slope",
	"nav_max_step_height",
	"nav_min_region_size",
]

const TERRAIN_SETTINGS_VERTEX_PAINTER_TAB := [
	"floor_blend_mode",
	"blend_sharpness",
	"use_ridge_texture",
	"use_ledge_texture",
	"ridge_threshold",
	"ledge_threshold",
	"default_wall_texture",
]

const TERRAIN_SETTINGS_ENVIRONMENT_TAB := [
	"noise_hmap",
	"grass_subdivisions",
	"grass_size",
	"grass_random_scale",
	"use_flat_normals",
	"use_cell_shading",
]

const TERRAIN_SETTINGS_WIND_TAB := [
	"animation_fps",
	"wind_direction_degrees",
	"wind_speed",
	"wind_tip_color",
	"wind_strength",
	"wind_scale",
	"wind_gust_strength",
	"wind_gust_speed",
	"wind_mode",
	"flower_wind_strength",
	"flower_stem_bend",
	"flower_tip_flutter",
]

const TERRAIN_SETTINGS_LABEL_OVERRIDES := {
	"blend_sharpness": "Blend Smoothness",
	"floor_blend_mode": "Floor Blend Mode",
	"blend_noise_threshold": "Noise Threshold",
	"collision_thickness": "Collision Thickness",
	"nav_agent_radius": "Agent Radius",
	"nav_max_slope": "Max Slope",
	"nav_max_step_height": "Max Step Height",
	"nav_min_region_size": "Min Region Size",
	"wind_direction_degrees": "Wind Direction",
	"wind_tip_color": "Wind Tip Color",
	"wind_gust_strength": "Gust Strength",
	"wind_gust_speed": "Gust Speed",
	"wind_scale": "Wind Scale",
	"wind_mode": "Wind Mode",
	"flower_wind_strength": "Flower Strength",
	"flower_stem_bend": "Stem Bend",
	"flower_tip_flutter": "Tip Flutter",
	"grass_random_scale": "Grass Random Scale",
}

const TERRAIN_TAB_VISIBLE_HEIGHT := 132
const TOOL_TAB_MIN_HEIGHT := TERRAIN_TAB_VISIBLE_HEIGHT + 36

var plugin : MarchingSquaresTerrainPlugin
var attribute_list : MarchingSquaresToolAttributesList
var settings : Dictionary = {}

var last_setting_type : SettingType = SettingType.ERROR
var selected_chunk : MarchingSquaresTerrainChunk
var current_available_chunks : Array[MarchingSquaresTerrainChunk] = []

var _terrain_settings_selected_tab : int = 0
var _chunk_management_selected_tab : int = 0
var _terrain_settings_scroll_positions : Dictionary = {}
var _wind_setting_rows : Dictionary = {}

var _heightmap_tool_selected_tab : int = 0
var _heightmap_tool_scroll_positions : Dictionary = {}

var selected_populator : MarchingSquaresPopulator

var hbox_container


func _add_texture_preset_options(preset_button: OptionButton, base_path: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var path := base_path.path_join(file_name)
		if dir.current_is_dir():
			_add_texture_preset_options(preset_button, path)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			if file_name == "texture_library.tres":
				file_name = dir.get_next()
				continue
			var resource := load(path)
			if resource is MarchingSquaresTexturePreset:
				preset_button.add_item(_resource_label_from_file(path, "preset_name", path.get_file().get_basename()))
				preset_button.set_item_metadata(preset_button.item_count - 1, path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _resource_label_from_file(path: String, property_name: String, fallback: String) -> String:
	if not path.ends_with(".tres"):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var needle := property_name + " = "
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with(needle):
			var value := line.substr(needle.length()).strip_edges()
			return value.trim_prefix("\"").trim_suffix("\"")
	return fallback


func _get_vertex_paint_material_slots() -> Array[int]:
	var slots : Array[int] = []
	var terrain = plugin.current_terrain_node if plugin != null else null
	if terrain == null:
		slots.append(0)
		return slots
	
	slots.append(15)
	var highest_active_slot := 0
	for slot_idx in range(plugin.MAX_TEXTURE_SLOTS):
		if slot_idx == 15:
			continue
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		var is_active := slot_idx == 0
		if slot_obj != null and slot_obj.get("active") != null:
			is_active = bool(slot_obj.get("active")) or slot_idx == 0
		if is_active:
			highest_active_slot = slot_idx
	
	for slot_idx in range(highest_active_slot + 1):
		if slot_idx == 15:
			continue
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		var is_active := slot_idx == 0
		if slot_obj != null and slot_obj.get("active") != null:
			is_active = bool(slot_obj.get("active"))
		if slot_idx == 0 or is_active:
			slots.append(slot_idx)
	
	if slots.is_empty():
		slots.append(0)
	return slots


func _get_visible_texture_option_slots(include_void: bool = false) -> Array[int]:
	var slots : Array[int] = []
	var terrain = plugin.current_terrain_node if plugin != null else null
	if terrain == null:
		for slot_idx in range(6):
			if slot_idx == 15 and not include_void:
				continue
			slots.append(slot_idx)
		return slots
	
	var visible_count := 6
	if terrain.get("visible_texture_slot_count") != null:
		visible_count = clampi(int(terrain.get("visible_texture_slot_count")), 6, plugin.MAX_TEXTURE_SLOTS)
	
	for slot_idx in range(visible_count):
		if slot_idx == 15 and not include_void:
			continue
		slots.append(slot_idx)
	
	if slots.is_empty():
		slots.append(0)
	return slots


func _get_vertex_paint_material_label(slot_idx: int, terrain_names: Array) -> String:
	if slot_idx >= 0 and slot_idx < terrain_names.size():
		return str(terrain_names[slot_idx])
	return "Texture " + str(slot_idx + 1)


func _ready() -> void:
	set_custom_minimum_size(Vector2(0, 35))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func show_tool_attributes(tool_index: int) -> void:
	_cache_terrain_settings_ui_state()
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
	
	var tool := plugin.toolbar.toolbox.tools.get(tool_index)
	var tool_attributes : MarchingSquaresToolAttributeSettings = tool.get("attributes")
	var type_map := {
		"slider": SettingType.SLIDER,
		"checkbox": SettingType.CHECKBOX,
		"option": SettingType.OPTION,
		"text": SettingType.TEXT,
		"chunk": SettingType.CHUNK,
		"terrain": SettingType.TERRAIN,
		"preset": SettingType.PRESET,
		"quick_paint": SettingType.QUICK_PAINT,
		"heightmap": SettingType.HEIGHTMAP,
	}
	
	var new_attributes := []
	if tool_attributes.brush_type:
		new_attributes.append(attribute_list.brush_type)
	if tool_attributes.vp_falloff_mode:
		new_attributes.append(attribute_list.vp_falloff_mode)
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
	if tool_attributes.curve3d_mode:
		new_attributes.append(attribute_list.curve3d_mode)
	if tool_attributes.mask_mode:
		new_attributes.append(attribute_list.mask_mode)
	if tool_attributes.material:
		new_attributes.append(attribute_list.material)
	if tool_attributes.texture_preset:
		new_attributes.append(attribute_list.texture_preset)
	if tool_attributes.quick_paint_selection:
		new_attributes.append(attribute_list.quick_paint_selection)
	if tool_attributes.paint_walls:
		new_attributes.append(attribute_list.paint_walls)
	if tool_attributes.populator:
		new_attributes.append(attribute_list.populator)
	if tool_attributes.remove_selection:
		new_attributes.append(attribute_list.remove_selection)
	if tool_attributes.chunk_management:
		new_attributes.append(attribute_list.chunk_management)
	if tool_attributes.heightmap:
		new_attributes.append(attribute_list.heightmap)
	if tool_attributes.terrain_settings:
		new_attributes.append(attribute_list.terrain_settings)
	
	# Rebuild material names from the preset or fallback to defaults
	var terrain_names : Array = []
	if plugin.current_terrain_node and plugin.current_terrain_node.current_texture_preset and plugin.current_terrain_node.current_texture_preset.new_tex_names:
		terrain_names = plugin.current_terrain_node.current_texture_preset.new_tex_names.texture_names
	else:
		terrain_names = attribute_list.vp_tex_names.texture_names  # fallback
	var material_options : Array[String] = []
	for slot_idx in _get_vertex_paint_material_slots():
		material_options.append(_get_vertex_paint_material_label(slot_idx, terrain_names))
	attribute_list.material["options"] = material_options
	
	for attribute in new_attributes:
		var setting_dict : Dictionary = attribute
		if setting_dict.has("type") and setting_dict["type"] is String:
			setting_dict["type"] = type_map.get(setting_dict["type"], SettingType.ERROR)
		add_setting(setting_dict)
	
	add_child(hbox_container)
	last_setting_type = SettingType.ERROR # Reset the setting type for correct VSeparators
	
	plugin.gizmo_plugin.trigger_redraw(plugin.current_terrain_node)


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
	if setting_type in [SettingType.CHUNK, SettingType.TERRAIN, SettingType.HEIGHTMAP]:
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
	var saved_setting_value := _get_setting_value(setting_name)
	match setting_type:
		SettingType.CHECKBOX:
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = p_params.get("default", false) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) !=  "ERROR":
				checkbox.button_pressed = saved_setting_value
			checkbox.toggled.connect(func(pressed): _on_setting_changed(setting_name, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(checkbox, true)
			hbox_container.add_child(cont, true)
		SettingType.SLIDER:
			var range_data := p_params.get("range", Vector3(1.0, 50.0, 0.5))
			var setting_cell_size: Vector2 = plugin.current_terrain_node.get("cell_size")
			var setting_dimensions: Vector3i = plugin.current_terrain_node.get("dimensions")
			var cell_scale_factor := clamp(((setting_cell_size.x + setting_cell_size.y) / 4.0), 0.3, 1.0)
			var dimensions_scale_factor := clamp((((setting_dimensions.x / 33) + (setting_dimensions.z / 33)) / 2.0), 0.5, 2.0)
			var scale_factor : float = dimensions_scale_factor * cell_scale_factor
			var default_value := p_params.get("default", 10.0) # Fallback base value
			if setting_name == "size":
				range_data *= scale_factor
				default_value *= scale_factor
			var range_min = range_data.x
			var range_max = range_data.y
			var range_step = range_data.z
			if saved_setting_value is not String and str(saved_setting_value) !=  "ERROR":
				default_value = saved_setting_value
			
			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(80, 35))
			if setting_name == "height" or setting_name == "ease_value" or setting_name == "size":
				var spin_slider := EditorSpinSlider.new()
				spin_slider.set_flat(true)
				spin_slider.allow_greater = true
				spin_slider.allow_lesser = true
				spin_slider.set_min(range_min)
				spin_slider.set_max(range_max)
				spin_slider.set_step(range_step)
				spin_slider.set_value(default_value)
				spin_slider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				spin_slider.set_custom_minimum_size(Vector2(110, 35))
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
			var material_slots : Array[int] = []
			var default_value = p_params.get("default", 0) # Fallback base value
			if setting_name == "material":
				material_slots = _get_vertex_paint_material_slots()
				for idx in range(mini(options.size(), material_slots.size())):
					option_button.add_item(str(options[idx]))
					option_button.set_item_metadata(option_button.item_count - 1, material_slots[idx])
			elif setting_name == "populator":
				var index := -1
				for child in plugin.current_terrain_node.get_children():
					if child is MarchingSquaresPopulator:
						index += 1
						option_button.add_item(child.name)
						if child == selected_populator:
							default_value = index
			else:
				for option in options:
					option_button.add_item(option)
			
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				default_value = saved_setting_value
			
			if setting_name == "material":
				var selected_idx := 0
				for item_idx in range(option_button.item_count):
					if int(option_button.get_item_metadata(item_idx)) == int(default_value):
						selected_idx = item_idx
						break
				option_button.selected = selected_idx
			elif setting_name == "populator":
				option_button.selected = default_value
				if option_button.item_count > 0:
					_on_populator_selected(option_button.get_item_text(default_value))
			else:
				option_button.selected = default_value
			
			option_button.set_flat(true)
			if setting_name == "material":
				option_button.item_selected.connect(func(index):
					var slot_idx = option_button.get_item_metadata(index)
					_on_setting_changed(setting_name, int(slot_idx))
				)
			elif setting_name == "populator":
				option_button.item_selected.connect(func(populator):
					selected_populator = null
					var index : int = -1
					for child in plugin.current_terrain_node.get_children():
						if child is MarchingSquaresPopulator:
							index += 1
							if index == populator:
								selected_populator = child
								plugin.current_populator = child
								break
					_on_setting_changed(setting_name, selected_populator)
					_on_populator_selected(option_button.get_item_text(populator))
				)
			else:
				option_button.item_selected.connect(func(index): _on_setting_changed(setting_name, index))
			
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
		SettingType.PRESET:
			var preset_button := OptionButton.new()
			preset_button.add_item("None") # First option is no preset
			preset_button.set_item_metadata(0, null)
			if setting_name == "texture_preset":
				_add_texture_preset_options(preset_button, TEXTURE_PRESETS_PATH)
				
				preset_button.set_flat(true)
				preset_button.item_selected.connect(func(index):
					var selected_texture_preset = preset_button.get_item_metadata(index)
					if selected_texture_preset is String:
						selected_texture_preset = load(selected_texture_preset)
					_on_setting_changed(setting_name, selected_texture_preset)
				)
				preset_button.set_custom_minimum_size(Vector2(100, 35))
				
				# Sync dropdown selection with current plugin.current_texture_preset
				var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
				var current_texture_preset := terrain.current_texture_preset if terrain else null
				if current_texture_preset == null:
					preset_button.select(0)  # Select "None"
				else:
					# Find matching preset in dropdown
					for i in range(preset_button.item_count):
						var item_meta = preset_button.get_item_metadata(i)
						var matches_current := false
						if item_meta is String:
							matches_current = item_meta == current_texture_preset.resource_path
						else:
							matches_current = item_meta == current_texture_preset
						if matches_current:
							preset_button.select(i)
							break
				
				cont = CenterContainer.new()
				cont.set_custom_minimum_size(Vector2(100, 35))
				cont.add_child(preset_button, true)
				hbox_container.add_child(cont, true)
			else: # Can be used for e.g. terrain settings presets in the future:
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
				while file_name !=  "":
					if file_name.ends_with(".tres") or file_name.ends_with(".res"):
						var quick_paint_path := GLOBAL_QUICK_PAINTS_PATH + file_name
						quick_paint_button.add_item(_resource_label_from_file(quick_paint_path, "paint_name", file_name.get_basename()))
						quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint_path)
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
				if selected_quick_paint is String:
					selected_quick_paint = load(selected_quick_paint)
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
					var item_meta = quick_paint_button.get_item_metadata(i)
					var matches_current := false
					if item_meta is String:
						matches_current = current_quick_paint is Resource and item_meta == current_quick_paint.resource_path
					else:
						matches_current = item_meta == current_quick_paint
					if matches_current:
						quick_paint_button.select(i)
						break
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(100, 35))
			cont.add_child(quick_paint_button, true)
			hbox_container.add_child(cont, true)
		SettingType.CHUNK:
			hbox_container.add_child(_create_chunk_management_tabs(), true)
		SettingType.TERRAIN:
			hbox_container.add_child(_create_terrain_settings_tabs(), true)
		SettingType.HEIGHTMAP:
			emit_signal("setting_changed", "brush_type", 1)
			hbox_container.add_child(_create_heightmap_tool_tabs(), true)
		SettingType.ERROR: # Fallback
			push_error("Couldn't load tool attributes setting")
	
	last_setting_type = setting_type


func _create_heightmap_tool_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_FILL
	tabs.set_custom_minimum_size(Vector2(0, 150))
	
	tabs.add_child(_create_heightmap_tab("Import"))
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Import")
	
	tabs.add_child(_create_heightmap_tab("Export"))
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Export")
	
	tabs.add_child(_create_heightmap_tab("Library"))
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Library")
	
	tabs.current_tab = clampi(_heightmap_tool_selected_tab, 0, max(tabs.get_tab_count() - 1, 0))
	plugin.heightmap_tool_selected_tab = tabs.current_tab
	plugin.can_place_heightmaps = tabs.current_tab == 2
	tabs.tab_changed.connect(func(tab_idx: int): 
		_heightmap_tool_selected_tab = tab_idx
		plugin.heightmap_tool_selected_tab = tab_idx
		if tab_idx == 2: # Library
			plugin.can_place_heightmaps = true
		else:
			plugin.can_place_heightmaps = false
	)
	
	return tabs


func _create_heightmap_tab(tab_name: String) -> Control:
	var page := VBoxContainer.new()
	page.name = tab_name
	page.add_theme_constant_override("Separation", 8)
	page.add_child(_create_tab_scroll(page.name, _create_heightmap_settings_list(tab_name)), true)
	return page


func _create_tab_scroll(tab_name: String, content: Control) -> Control:
	var scroll := ScrollContainer.new()
	
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	
	scroll.set_custom_minimum_size(Vector2(0, 150))
	scroll.custom_minimum_size.y = 150
	
	scroll.add_child(content, true)
	if _heightmap_tool_scroll_positions.has(tab_name):
		scroll.set_deferred("scroll_vertical", int(_heightmap_tool_scroll_positions[tab_name]))
	else:
		scroll.set_deferred("scroll_vertical", 0)
	scroll.gui_input.connect(func(_event: InputEvent):
		_heightmap_tool_scroll_positions[tab_name] = scroll.scroll_vertical
	)
	
	return scroll


func _create_heightmap_settings_list(tab_name: String) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(left_spacer, true)
	
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.set_custom_minimum_size(Vector2(320, 0))
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	match(tab_name):
		"Import":
			var vbox := VBoxContainer.new()
			
			# Row 0: Single File toggle
			var hbox_sf := HBoxContainer.new()
			var label_sf := Label.new()
			label_sf.set_text("Single File:")
			label_sf.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
			label_sf.set_custom_minimum_size(Vector2(80, 25))
			var lcc_sf := CenterContainer.new()
			lcc_sf.set_custom_minimum_size(Vector2(80, 35))
			lcc_sf.add_child(label_sf, true)
			hbox_sf.add_child(lcc_sf, true)
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox_sf.add_child(spacer, true)
			var cb_sf := CheckBox.new()
			cb_sf.set_flat(true)
			cb_sf.set_custom_minimum_size(Vector2(25, 25))
			cb_sf.button_pressed = plugin.hm_single_file_import
			cb_sf.toggled.connect(func(pressed): _on_importer_setting_changed("hm_single_file_import", pressed))
			var cb_sc := CenterContainer.new()
			cb_sc.set_custom_minimum_size(Vector2(40, 35))
			cb_sc.add_child(cb_sf, true)
			hbox_sf.add_child(cb_sc, true)
			vbox.add_child(hbox_sf, true)
			
			if plugin.hm_single_file_import:
				# Single-file mode: one combined RGBA picker
				var hbox_combined := HBoxContainer.new()
				var label_combined := Label.new()
				label_combined.set_text("Combined Map:")
				label_combined.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
				label_combined.set_custom_minimum_size(Vector2(80, 25))
				var lcc_combined := CenterContainer.new()
				lcc_combined.set_custom_minimum_size(Vector2(80, 35))
				lcc_combined.add_child(label_combined, true)
				hbox_combined.add_child(lcc_combined, true)
				var spacer_combined := Control.new()
				spacer_combined.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox_combined.add_child(spacer_combined, true)
				var rp_combined := EditorResourcePicker.new()
				rp_combined.set_base_type("Texture2D")
				rp_combined.edited_resource = plugin.hm_combined_image
				_hide_textures(rp_combined)
				rp_combined.resource_changed.connect(func(res): _on_importer_setting_changed("hm_combined_image", res))
				rp_combined.set_custom_minimum_size(Vector2(120, 25))
				var rp_combined_cont := CenterContainer.new()
				rp_combined_cont.set_custom_minimum_size(Vector2(130, 35))
				rp_combined_cont.add_child(rp_combined, true)
				hbox_combined.add_child(rp_combined_cont, true)
				vbox.add_child(hbox_combined, true)
			else:
				# Row 1: Heightmap texture picker
				var hbox_tex := HBoxContainer.new()
				var label_tex := Label.new()
				label_tex.set_text("Heightmap:")
				label_tex.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
				label_tex.set_custom_minimum_size(Vector2(80, 25))
				var lcc_tex := CenterContainer.new()
				lcc_tex.set_custom_minimum_size(Vector2(80, 35))
				lcc_tex.add_child(label_tex, true)
				hbox_tex.add_child(lcc_tex, true)
				var spacer_tex := Control.new()
				spacer_tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox_tex.add_child(spacer_tex, true)
				var rp := EditorResourcePicker.new()
				rp.set_base_type("Texture2D")
				rp.edited_resource = plugin.hm_heightmap_image
				_hide_textures(rp)
				rp.resource_changed.connect(func(res): _on_importer_setting_changed("hm_heightmap_image", res))
				rp.set_custom_minimum_size(Vector2(120, 25))
				var rp_cont := CenterContainer.new()
				rp_cont.set_custom_minimum_size(Vector2(130, 35))
				rp_cont.add_child(rp, true)
				hbox_tex.add_child(rp_cont, true)
				vbox.add_child(hbox_tex, true)
			
				# Row 2: Grass map picker (optional)
				var hbox_grass := HBoxContainer.new()
				var label_grass := Label.new()
				label_grass.set_text("Grass Map:")
				label_grass.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
				label_grass.set_custom_minimum_size(Vector2(80, 25))
				var lcc_grass := CenterContainer.new()
				lcc_grass.set_custom_minimum_size(Vector2(80, 35))
				lcc_grass.add_child(label_grass, true)
				hbox_grass.add_child(lcc_grass, true)
				var spacer_grass := Control.new()
				spacer_grass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox_grass.add_child(spacer_grass, true)
				var rp_grass := EditorResourcePicker.new()
				rp_grass.set_base_type("Texture2D")
				rp_grass.edited_resource = plugin.hm_grass_image
				_hide_textures(rp_grass)
				rp_grass.resource_changed.connect(func(res): _on_importer_setting_changed("hm_grass_image", res))
				rp_grass.set_custom_minimum_size(Vector2(120, 25))
				var rp_grass_cont := CenterContainer.new()
				rp_grass_cont.set_custom_minimum_size(Vector2(130, 35))
				rp_grass_cont.add_child(rp_grass, true)
				hbox_grass.add_child(rp_grass_cont, true)
				vbox.add_child(hbox_grass, true)
				
				# Row 3: Texture index map picker (optional)
				var hbox_texmap := HBoxContainer.new()
				var label_texmap := Label.new()
				label_texmap.set_text("Texture Map:")
				label_texmap.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
				label_texmap.set_custom_minimum_size(Vector2(80, 25))
				var lcc_texmap := CenterContainer.new()
				lcc_texmap.set_custom_minimum_size(Vector2(80, 35))
				lcc_texmap.add_child(label_texmap, true)
				hbox_texmap.add_child(lcc_texmap, true)
				var spacer_texmap := Control.new()
				spacer_texmap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox_texmap.add_child(spacer_texmap, true)
				var rp_texmap := EditorResourcePicker.new()
				rp_texmap.set_base_type("Texture2D")
				rp_texmap.edited_resource = plugin.hm_texture_image
				_hide_textures(rp_texmap)
				rp_texmap.resource_changed.connect(func(res): _on_importer_setting_changed("hm_texture_image", res))
				rp_texmap.set_custom_minimum_size(Vector2(120, 25))
				var rp_texmap_cont := CenterContainer.new()
				rp_texmap_cont.set_custom_minimum_size(Vector2(130, 35))
				rp_texmap_cont.add_child(rp_texmap, true)
				hbox_texmap.add_child(rp_texmap_cont, true)
				vbox.add_child(hbox_texmap, true)
			# end if/else single_file
			
			# Flush the texture pickers, then give Chunks X/Z their own column
			if vbox.get_child_count() > 0:
				list.add_child(vbox)
				list.add_child(HSeparator.new())
				vbox = VBoxContainer.new()
			
			# Chunks X and Chunks Z share a dedicated column
			vbox.add_child(_make_importer_spinbox_row("Chunks X:", "hm_chunks_x", plugin.hm_chunks_x, 1, 64), true)
			vbox.add_child(_make_importer_spinbox_row("Chunks Z:", "hm_chunks_z", plugin.hm_chunks_z, 1, 64), true)
			list.add_child(vbox)
			list.add_child(HSeparator.new())
			vbox = VBoxContainer.new()
			
			# Row 5: Merge mode dropdown and Max Height spinboxes
			var hbox_mode := HBoxContainer.new()
			var label_mode := Label.new()
			label_mode.set_text("Merge Mode:")
			label_mode.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
			label_mode.set_custom_minimum_size(Vector2(80, 25))
			var lcc_mode := CenterContainer.new()
			lcc_mode.set_custom_minimum_size(Vector2(80, 35))
			lcc_mode.add_child(label_mode, true)
			hbox_mode.add_child(lcc_mode, true)
			var spacer_mode := Control.new()
			spacer_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox_mode.add_child(spacer_mode, true)
			var opt := OptionButton.new()
			opt.set_flat(true)
			for mode_name in ["Cubic", "Polyhedron", "Rounded Polyhedron", "Semi Round", "Spherical"]:
				opt.add_item(mode_name)
			opt.selected = plugin.hm_merge_mode
			opt.item_selected.connect(func(idx): _on_importer_setting_changed("hm_merge_mode", idx))
			opt.set_custom_minimum_size(Vector2(130, 35))
			var opt_cont := CenterContainer.new()
			opt_cont.set_custom_minimum_size(Vector2(130, 35))
			opt_cont.add_child(opt, true)
			hbox_mode.add_child(opt_cont, true)
			vbox.add_child(hbox_mode, true)
			
			if vbox.get_child_count() % 2 == 0:
				list.add_child(vbox)
				list.add_child(HSeparator.new())
				vbox = VBoxContainer.new()
			vbox.add_child(_make_importer_spinbox_row("Max Height:", "hm_max_height", plugin.hm_max_height, 1, 256), true)
			if vbox.get_child_count() % 2 == 0:
				list.add_child(vbox)
				list.add_child(HSeparator.new())
				vbox = VBoxContainer.new()
			
			# Row 6: Import button
			var import_btn := Button.new()
			import_btn.text = "Import Heightmap"
			import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			import_btn.set_custom_minimum_size(Vector2(140, 30))
			import_btn.pressed.connect(_on_import_heightmap_pressed)
			var btn_cont := MarginContainer.new()
			btn_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn_cont.add_theme_constant_override("margin_bottom", 3)
			btn_cont.set_custom_minimum_size(Vector2(140, 35))
			btn_cont.add_child(import_btn, true)
			vbox.add_child(btn_cont, true)
			if vbox.get_child_count() % 2 == 0:
				list.add_child(vbox)
				list.add_child(HSeparator.new())
				vbox = VBoxContainer.new()
			
			# Row 7: Clear Chunks button
			var clear_btn := Button.new()
			clear_btn.text = "Clear Chunks"
			clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			clear_btn.set_custom_minimum_size(Vector2(140, 30))
			clear_btn.pressed.connect(_on_clear_chunks_pressed)
			var clear_cont := MarginContainer.new()
			clear_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			clear_cont.add_theme_constant_override("margin_bottom", 3)
			clear_cont.set_custom_minimum_size(Vector2(140, 35))
			clear_cont.add_child(clear_btn, true)
			vbox.add_child(clear_cont, true)
			if vbox.get_child_count() % 2 == 0:
				list.add_child(vbox)
		"Export":
			var export_vbox := VBoxContainer.new()
			
			# Column: Export layer checkboxes (hidden in single-file mode)
			if not plugin.hme_single_file:
				export_vbox.add_child(_make_exporter_checkbox_row("Heightmap", "hme_export_heightmap", plugin.hme_export_heightmap), true)
				export_vbox.add_child(_make_exporter_checkbox_row("Grass Mask", "hme_export_grass", plugin.hme_export_grass), true)
				export_vbox.add_child(_make_exporter_checkbox_row("Texture Index", "hme_export_texture_index", plugin.hme_export_texture_index), true)
			else:
				var single_label := Label.new()
				single_label.text = "All channels packed"
				single_label.modulate = Color(1, 1, 1, 0.5)
				export_vbox.add_child(single_label, true)
			list.add_child(export_vbox)
			list.add_child(HSeparator.new())
			export_vbox = VBoxContainer.new()
			
			export_vbox.add_child(_make_exporter_checkbox_row("Single File", "hme_single_file", plugin.hme_single_file), true)
			
			var export_btn := MarchingSquaresTerrainHeightmapExporterButton.new()
			export_btn.tool_attributes = self
			export_vbox.add_child(export_btn, true)
			
			list.add_child(export_vbox)
		"Library":
			var extract_btn := MarchingSquaresMeshHeightmapExtractorButton.new()
			extract_btn.tool_attributes = self
			list.add_child(extract_btn)
			
			var s_hbox := HBoxContainer.new()
			var s_label := Label.new()
			s_label.text = "Heightmap:"
			s_hbox.add_child(s_label)
			
			var heightmap_selector := OptionButton.new()
			heightmap_selector.flat = true
			
			var dir := DirAccess.open(plugin.MESH_HEIGHTMAPS_FOLDER_PATH)
			if dir:
				for file in dir.get_files():
					if file.get_extension().to_lower() in ["png", "jpg", "jpeg"]:
						var path := plugin.MESH_HEIGHTMAPS_FOLDER_PATH + file
						var texture := ResourceLoader.load(path) as Texture2D
						if texture:
							var image := texture.get_image()
							heightmap_selector.add_item(file)
							heightmap_selector.set_item_metadata(heightmap_selector.item_count - 1, image)
			
			heightmap_selector.item_selected.connect(func(index):
					plugin.current_heightmap_image = heightmap_selector.get_item_metadata(index)
			)
			
			if heightmap_selector.item_count > 0:
				plugin.current_heightmap_image = heightmap_selector.get_item_metadata(0)
			
			s_hbox.add_child(heightmap_selector)
			list.add_child(s_hbox)
			
			var a_hbox := HBoxContainer.new()
			for child in hbox_container.get_children():
				if child is VSeparator:
					child.queue_free()
					continue
				child.reparent(a_hbox)
				if a_hbox.get_child_count() == 2:
					if child.get_child(0) is CheckBox:
						var spacer := Control.new()
						spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						a_hbox.add_child(spacer)
						a_hbox.move_child(spacer, 1)
					else:
						child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					
					list.add_child(a_hbox)
					a_hbox = HBoxContainer.new()
		_:
			printerr("Tab name does not have a matching heightmap settings list yet.")
	
	wrapper.add_child(list, true)
	
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(right_spacer, true)
	
	return wrapper


func _create_chunk_management_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_FILL
	tabs.set_custom_minimum_size(Vector2(0, TOOL_TAB_MIN_HEIGHT))
	tabs.add_child(_create_chunk_configuration_page(), true)
	tabs.set_tab_title(0, "Manager")
	tabs.add_child(_create_chunk_navmesh_page(), true)
	tabs.set_tab_title(1, "NavMesh")
	tabs.current_tab = clampi(_chunk_management_selected_tab, 0, 1)
	tabs.tab_changed.connect(func(tab_index: int):
		_chunk_management_selected_tab = tab_index
		if tab_index != 1 and plugin.navmesh_paint_mode != MarchingSquaresTerrainPlugin.NavMeshPaintMode.NONE:
			plugin.deactivate_navmesh_paint_mode()
			var nav_row := tabs.get_child(1).get_child(1) as HBoxContainer
			if nav_row != null:
				var paint_button := nav_row.get_child(0) as Button
				var erase_button := nav_row.get_child(1) as Button
				if paint_button != null:
					paint_button.button_pressed = false
				if erase_button != null:
					erase_button.button_pressed = false
	)
	return tabs


func _create_chunk_configuration_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	settings_scroll.set_custom_minimum_size(Vector2(0, 80))
	settings_scroll.add_child(_create_terrain_settings_list(TERRAIN_SETTINGS_CHUNK_TAB), true)
	page.add_child(settings_scroll, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	current_available_chunks.clear()
	var chunk_button := OptionButton.new()
	for child in plugin.current_terrain_node.get_children():
		var terrain_chunk := child as MarchingSquaresTerrainChunk
		if terrain_chunk != null:
			chunk_button.add_item("Chunk " + str(terrain_chunk.chunk_coords))
			current_available_chunks.append(terrain_chunk)
	if not current_available_chunks.is_empty():
		var preferred_chunk : MarchingSquaresTerrainChunk = plugin.selected_chunk
		if preferred_chunk == null and plugin.current_terrain_node.chunks.has(plugin.current_hovered_chunk):
			preferred_chunk = plugin.current_terrain_node.chunks[plugin.current_hovered_chunk]
		if preferred_chunk == null:
			preferred_chunk = current_available_chunks[0]
		plugin.selected_chunk = preferred_chunk
		selected_chunk = preferred_chunk
		chunk_button.selected = current_available_chunks.find(preferred_chunk)
	else:
		chunk_button.selected = -1
	
	var option_button := OptionButton.new()
	option_button.set_flat(true)
	for mode in MarchingSquaresTerrainChunk.Mode:
		option_button.add_item(_format_constant_string(mode))
	option_button.selected = plugin.selected_chunk.merge_mode if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
	option_button.item_selected.connect(_on_chunk_mode_changed)
	
	var grass_mode_button := OptionButton.new()
	grass_mode_button.set_flat(true)
	grass_mode_button.add_item("Grass")
	grass_mode_button.add_item("Grassless")
	grass_mode_button.selected = plugin.selected_chunk.grass_mode if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
	grass_mode_button.item_selected.connect(_on_chunk_grass_mode_changed)
	
	var height_button := EditorSpinSlider.new()
	height_button.set_flat(true)
	height_button.allow_greater = true
	height_button.allow_lesser = true
	height_button.set_min(-50.0)
	height_button.set_max(50.0)
	height_button.set_step(0.1)
	height_button.set_value(plugin.height)
	height_button.value_changed.connect(func(value): _on_setting_changed("height", value))
	height_button.set_custom_minimum_size(Vector2(110, 35))
	
	var qp_selection_button := OptionButton.new()
	qp_selection_button.add_item("None")  # First option is no paint. #TODO Doesn't seem to work right now and needs to be fixed later.
	qp_selection_button.set_item_metadata(0, null)
	
	# 1. Load GLOBAL quick paints from folder (always available)
	var dir := DirAccess.open(GLOBAL_QUICK_PAINTS_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name !=  "":
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var quick_paint_path := GLOBAL_QUICK_PAINTS_PATH + file_name
				qp_selection_button.add_item(_resource_label_from_file(quick_paint_path, "paint_name", file_name.get_basename()))
				qp_selection_button.set_item_metadata(qp_selection_button.item_count - 1, quick_paint_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	# 2. Load PRESET-SPECIFIC quick paints (if preset is selected and has any)
	var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
	if terrain and terrain.current_texture_preset:
		var preset := terrain.current_texture_preset
		if preset.quick_paints.size() > 0:
			qp_selection_button.add_separator()  # Visual separator
			for quick_paint in preset.quick_paints:
				if quick_paint:
					qp_selection_button.add_item(quick_paint.paint_name)
					qp_selection_button.set_item_metadata(qp_selection_button.item_count - 1, quick_paint)
	
	qp_selection_button.set_flat(true)
	qp_selection_button.item_selected.connect(func(index):
		var selected_quick_paint = qp_selection_button.get_item_metadata(index)
		if selected_quick_paint is String:
			selected_quick_paint = load(selected_quick_paint)
		_on_setting_changed("quick_paint_selection", selected_quick_paint)
	)
	qp_selection_button.set_custom_minimum_size(Vector2(100, 35))
	
	# Sync dropdown selection with current plugin.current_quick_paint
	var current_quick_paint = _get_setting_value("quick_paint_selection")
	if current_quick_paint == null:
		qp_selection_button.select(0)  # Select "None"
	else:
		# Find matching quick paint in dropdown
		for i in range(qp_selection_button.item_count):
			var item_meta = qp_selection_button.get_item_metadata(i)
			var matches_current := false
			if item_meta is String:
				matches_current = current_quick_paint is Resource and item_meta == current_quick_paint.resource_path
			else:
				matches_current = item_meta == current_quick_paint
			if matches_current:
				qp_selection_button.select(i)
				break
	
	chunk_button.set_flat(true)
	chunk_button.item_selected.connect(func(chunk): _on_chunk_selected(option_button, grass_mode_button, chunk_button.get_item_text(chunk)))
	var mult_apply_button := Button.new()
	mult_apply_button.text = "Apply mode to all chunks"
	mult_apply_button.pressed.connect(_apply_mode_to_all_chunks)
	var chunk_container := CenterContainer.new()
	chunk_container.custom_minimum_size = Vector2(65, 35)
	chunk_container.add_child(chunk_button, true)
	row.add_child(chunk_container, true)
	row.add_child(VSeparator.new(), true)
	var mode_container := CenterContainer.new()
	mode_container.custom_minimum_size = Vector2(65, 35)
	mode_container.add_child(option_button, true)
	row.add_child(mode_container, true)
	row.add_child(VSeparator.new(), true)
	var grass_container := CenterContainer.new()
	grass_container.custom_minimum_size = Vector2(85, 35)
	grass_container.add_child(grass_mode_button, true)
	row.add_child(grass_container, true)
	row.add_child(VSeparator.new(), true)
	var apply_container := MarginContainer.new()
	apply_container.custom_minimum_size = Vector2(220, 35)
	apply_container.add_theme_constant_override("margin_bottom", 3)
	apply_container.add_child(mult_apply_button, true)
	row.add_child(apply_container, true)
	row.add_child(VSeparator.new(), true)
	var height_container := CenterContainer.new()
	height_container.custom_minimum_size = Vector2(65, 35)
	height_container.add_child(height_button, true)
	row.add_child(height_container, true)
	row.add_child(VSeparator.new(), true)
	var qp_container := CenterContainer.new()
	qp_container.custom_minimum_size = Vector2(65, 35)
	qp_container.add_child(qp_selection_button, true)
	row.add_child(qp_container, true)
	var row_center := CenterContainer.new()
	row_center.add_child(row, true)
	page.add_child(row_center, true)
	return page


func _create_chunk_navmesh_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(_create_terrain_settings_list(CHUNK_MANAGEMENT_NAVMESH_SETTINGS), true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var paint := Button.new()
	paint.text = "Paint NavMesh"
	paint.toggle_mode = true
	paint.button_pressed = plugin.navmesh_paint_mode == MarchingSquaresTerrainPlugin.NavMeshPaintMode.PAINT
	var erase := Button.new()
	erase.text = "Erase NavMesh"
	erase.toggle_mode = true
	erase.button_pressed = plugin.navmesh_paint_mode == MarchingSquaresTerrainPlugin.NavMeshPaintMode.ERASE
	var bake := Button.new()
	bake.text = "Bake NavMesh"
	paint.pressed.connect(func():
		if paint.button_pressed:
			plugin.set_navmesh_paint_mode(MarchingSquaresTerrainPlugin.NavMeshPaintMode.PAINT)
			erase.button_pressed = false
		else:
			plugin.deactivate_navmesh_paint_mode()
	)
	erase.pressed.connect(func():
		if erase.button_pressed:
			plugin.set_navmesh_paint_mode(MarchingSquaresTerrainPlugin.NavMeshPaintMode.ERASE)
			paint.button_pressed = false
		else:
			plugin.deactivate_navmesh_paint_mode()
	)
	bake.pressed.connect(func():
		plugin.deactivate_navmesh_paint_mode()
		if plugin.current_terrain_node != null:
			plugin.current_terrain_node.bake_navmesh_from_tool()
		paint.button_pressed = false
		erase.button_pressed = false
	)
	row.add_child(paint, true)
	row.add_child(VSeparator.new(), true)
	row.add_child(erase, true)
	row.add_child(VSeparator.new(), true)
	row.add_child(bake, true)
	var row_center := CenterContainer.new()
	row_center.add_child(row, true)
	page.add_child(row_center, true)
	return page


func _create_terrain_settings_tabs() -> Control:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_FILL
	tabs.set_custom_minimum_size(Vector2(0, TOOL_TAB_MIN_HEIGHT))
	
	tabs.add_child(_create_vertex_painter_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Vertex Painter")
	
	tabs.add_child(_create_environment_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Environment")
	
	tabs.add_child(_create_wind_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Wind")
	
	tabs.add_child(_create_post_processing_tab())
	tabs.set_tab_title(tabs.get_tab_count() - 1, "Post-Processing")
	
	tabs.current_tab = clampi(_terrain_settings_selected_tab, 0, max(tabs.get_tab_count() - 1, 0))
	tabs.tab_changed.connect(func(tab_idx: int): _terrain_settings_selected_tab = tab_idx)
	
	return tabs


func _create_post_processing_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "PostProcessing"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(page.name, _create_post_processing_content()), true)
	return page


func _create_post_processing_content() -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrapper.add_theme_constant_override("separation", 18)
	wrapper.add_child(_create_post_process_column("Surface Effects", "surface_effects"), true)
	wrapper.add_child(_create_post_process_column("Overlay Effects", "overlay_effects"), true)
	return wrapper


func _create_post_process_column(title: String, array_name: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.set_custom_minimum_size(Vector2(285, 0))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = title
	column.add_child(label, true)
	var terrain = plugin.current_terrain_node if plugin != null else null
	var count := terrain.get_post_process_slot_count(array_name) if terrain != null else 1
	for slot_idx in range(count):
		column.add_child(_create_post_process_effect_row(array_name, slot_idx), true)
	var add_button := Button.new()
	add_button.text = "+ Add Effect"
	add_button.disabled = count >= 5
	add_button.pressed.connect(func():
		if terrain != null:
			terrain.add_post_process_effect_slot(array_name)
			show_tool_attributes(plugin.active_tool)
	)
	column.add_child(add_button, true)
	return column


func _create_post_process_effect_row(array_name: String, slot_idx: int) -> Control:
	var terrain = plugin.current_terrain_node if plugin != null else null
	var effect := terrain.ensure_post_process_effect(slot_idx, array_name) if terrain != null else null
	var panel := PanelContainer.new()
	var body := VBoxContainer.new()
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header, true)
	var slot_label := Label.new()
	slot_label.text = "Effect " + str(slot_idx + 1)
	header.add_child(slot_label, true)
	var enabled := CheckBox.new()
	enabled.text = "On"
	enabled.button_pressed = effect.enabled if effect != null else false
	header.add_child(enabled, true)
	var target := OptionButton.new()
	target.add_item("Terrain")
	target.add_item("Grass")
	target.add_item("Both")
	target.selected = int(effect.target) if effect != null else 0
	header.add_child(target, true)
	var clear := Button.new()
	clear.text = "Clear" if slot_idx == 0 else "Delete"
	header.add_child(clear, true)
	var shader_row := HBoxContainer.new()
	var shader_label := Label.new()
	shader_label.text = "Shader:"
	shader_row.add_child(shader_label, true)
	var picker := EditorResourcePicker.new()
	picker.set_base_type("Shader")
	picker.edited_resource = effect.shader if effect != null else null
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shader_row.add_child(picker, true)
	body.add_child(shader_row, true)
	var material_row := HBoxContainer.new()
	var material_label := Label.new()
	material_label.text = "Material Override:"
	material_row.add_child(material_label, true)
	var material_picker := EditorResourcePicker.new()
	material_picker.set_base_type("Material")
	material_picker.edited_resource = effect.material_override if effect != null else null
	material_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_row.add_child(material_picker, true)
	body.add_child(material_row, true)
	enabled.toggled.connect(func(value: bool):
		var current = terrain.ensure_post_process_effect(slot_idx, array_name)
		current.enabled = value
		_commit_post_process_effect(terrain, array_name, slot_idx)
		terrain._rebuild_post_process_effects()
		EditorInterface.mark_scene_as_unsaved()
	)
	target.item_selected.connect(func(value: int):
		var current = terrain.ensure_post_process_effect(slot_idx, array_name)
		current.target = value
		_commit_post_process_effect(terrain, array_name, slot_idx)
		terrain._rebuild_post_process_effects()
		EditorInterface.mark_scene_as_unsaved()
	)
	picker.resource_changed.connect(func(resource: Resource):
		var current = terrain.ensure_post_process_effect(slot_idx, array_name)
		current.shader = resource as Shader
		_commit_post_process_effect(terrain, array_name, slot_idx)
		terrain._rebuild_post_process_effects()
		EditorInterface.mark_scene_as_unsaved()
	)
	picker.resource_selected.connect(func(resource: Resource, inspect: bool):
		if inspect and resource != null:
			EditorInterface.inspect_object(resource)
	)
	material_picker.resource_changed.connect(func(resource: Resource):
		var current = terrain.ensure_post_process_effect(slot_idx, array_name)
		current.material_override = resource as Material
		_commit_post_process_effect(terrain, array_name, slot_idx)
		terrain._rebuild_post_process_effects()
		EditorInterface.mark_scene_as_unsaved()
	)
	material_picker.resource_selected.connect(func(resource: Resource, inspect: bool):
		if inspect and resource != null:
			EditorInterface.inspect_object(resource)
	)
	clear.pressed.connect(func():
		if slot_idx == 0:
			terrain.clear_post_process_effect(slot_idx, array_name)
		else:
			terrain.delete_post_process_effect_slot(slot_idx, array_name)
		show_tool_attributes(plugin.active_tool)
	)
	return panel


func _commit_post_process_effect(terrain: MarchingSquaresTerrain, array_name: String, slot_idx: int) -> void:
	if terrain == null or slot_idx < 0:
		return
	var effects: Array = terrain.get(array_name).duplicate()
	while effects.size() <= slot_idx:
		effects.append(null)
	var effect := terrain.get_post_process_effect(slot_idx, array_name)
	if effect != null:
		# Keep custom-created effect resources scene-local so nested shader/material
		# assignments are serialized with the terrain scene.
		effect.resource_local_to_scene = true
		effects[slot_idx] = effect
	terrain.set(array_name, effects)


func _create_vertex_painter_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "VertexPainter"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(page.name, _create_terrain_settings_list(TERRAIN_SETTINGS_VERTEX_PAINTER_TAB)), true)
	call_deferred("_update_floor_blend_setting_visibility")
	return page


func _create_environment_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Environment"
	page.add_theme_constant_override("separation", 8)
	page.add_child(_create_tab_scroll(page.name, _create_terrain_settings_list(TERRAIN_SETTINGS_ENVIRONMENT_TAB)), true)
	return page


func _create_wind_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Wind"
	page.add_theme_constant_override("separation", 8)
	_wind_setting_rows.clear()
	page.add_child(_create_tab_scroll(page.name, _create_terrain_settings_list(TERRAIN_SETTINGS_WIND_TAB)), true)
	call_deferred("_update_wind_setting_visibility")
	return page


func _update_wind_setting_visibility() -> void:
	var terrain = plugin.current_terrain_node if plugin != null else null
	var mode := int(terrain.get("wind_mode")) if terrain != null else 0
	var show_gust := mode == 1
	for setting in ["wind_gust_speed", "wind_gust_strength"]:
		if _wind_setting_rows.has(setting) and is_instance_valid(_wind_setting_rows[setting]):
			_wind_setting_rows[setting].visible = show_gust


func _create_empty_tab(tab_name: String) -> Control:
	var page := VBoxContainer.new()
	page.name = tab_name
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_FILL
	
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer, true)
	
	var label := Label.new()
	label.text = tab_name + " settings coming soon."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(label, true)
	
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer_bottom, true)
	
	return page


func _cache_terrain_settings_ui_state() -> void:
	var tabs := _find_terrain_settings_tabs()
	if tabs == null:
		return
	
	_terrain_settings_selected_tab = tabs.current_tab
	for page in tabs.get_children():
		if page is Control:
			var scroll := _find_first_scroll_container(page)
			if scroll != null:
				_terrain_settings_scroll_positions[String(page.name)] = scroll.scroll_vertical


func _find_terrain_settings_tabs() -> TabContainer:
	for child in get_children():
		var tabs := _find_first_tab_container(child)
		if tabs != null:
			return tabs
	return null


func _find_first_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child in node.get_children():
		var found := _find_first_tab_container(child)
		if found != null:
			return found
	return null


func _find_first_scroll_container(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node as ScrollContainer
	for child in node.get_children():
		var found := _find_first_scroll_container(child)
		if found != null:
			return found
	return null


func _create_terrain_settings_list(setting_names: Array) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(left_spacer, true)
	
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.set_custom_minimum_size(Vector2(1060, 0))
	columns.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	columns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 6)
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 6)
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var valid_settings : Array[String] = []
	for setting_name_variant in setting_names:
		var setting_name := str(setting_name_variant)
		if not terrain_settings_data.has(setting_name):
			continue
		valid_settings.append(setting_name)
	
	for i in range(valid_settings.size()):
		var setting_row := _create_terrain_setting_row(valid_settings[i])
		if i % 2 == 0:
			left_column.add_child(setting_row, true)
		else:
			right_column.add_child(setting_row, true)
	
	columns.add_child(left_column, true)
	columns.add_child(VSeparator.new(), true)
	columns.add_child(right_column, true)
	wrapper.add_child(columns, true)
	
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(right_spacer, true)
	
	return wrapper


func _create_terrain_setting_row(setting: String) -> Control:
	var editor_setting = terrain_settings_data[setting]
	var s_value := plugin.current_terrain_node.get(setting)
	var floor_blend_is_noisy := int(plugin.current_terrain_node.get("floor_blend_mode")) == 1
	if setting == "blend_sharpness" and floor_blend_is_noisy:
		s_value = plugin.current_terrain_node.get("blend_noise_threshold")
	
	var hbox := HBoxContainer.new()
	hbox.name = setting
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var label := Label.new()
	var label_text := TERRAIN_SETTINGS_LABEL_OVERRIDES.get(setting, _make_editor_name(setting))
	if setting == "blend_sharpness" and floor_blend_is_noisy:
		label_text = "Noise Threshold"
	label.set_text(str(label_text) + ':')
	label.name = "SettingLabel"
	label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	label.set_custom_minimum_size(Vector2(170, 25))
	
	var label_c_cont := CenterContainer.new()
	label_c_cont.set_custom_minimum_size(Vector2(170, 35))
	label_c_cont.add_child(label, true)
	hbox.add_child(label_c_cont, true)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	
	var ts_cont : Control
	match editor_setting:
		"Vector2":
			var editor_vec2 := _make_vector_editor(editor_setting, s_value, setting)
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(editor_vec2, true)
		"Vector3i":
			var editor_vec3i := _make_vector_editor(editor_setting, s_value, setting)
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(185, 35))
			ts_cont.add_child(editor_vec3i, true)
		"SpinBox":
			var spin_box := SpinBox.new()
			spin_box.value = plugin.current_terrain_node.get(setting)
			spin_box.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
			spin_box.set_custom_minimum_size(Vector2(70, 25))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(80, 35))
			ts_cont.add_child(spin_box, true)
		"EditorSpinSlider":
			var spin_slider := EditorSpinSlider.new()
			spin_slider.set_flat(true)
			spin_slider.set_min(0.0)
			if setting == "collision_thickness":
				spin_slider.set_max(8.0)
				spin_slider.set_step(0.05)
			elif setting == "nav_agent_radius" or setting == "nav_max_step_height":
				spin_slider.set_max(8.0)
				spin_slider.set_step(0.05)
			elif setting == "nav_max_slope":
				spin_slider.set_max(89.0)
				spin_slider.set_step(0.5)
			elif setting == "nav_min_region_size":
				spin_slider.set_max(256.0)
				spin_slider.set_step(0.25)
			elif setting == "wind_direction_degrees":
				spin_slider.set_max(360.0)
			elif setting == "wind_speed" or setting == "wind_gust_speed" or setting == "flower_tip_flutter":
				spin_slider.set_max(1.0)
			elif setting == "wind_strength" or setting == "wind_gust_strength" or setting == "flower_wind_strength":
				spin_slider.set_max(2.0)
			elif setting == "flower_stem_bend":
				spin_slider.set_min(1.0)
				spin_slider.set_max(2.5)
			elif setting == "wind_scale":
				spin_slider.set_max(1.0)
			elif setting == "wall_threshold":
				spin_slider.set_max(0.5)
			else:
				spin_slider.set_max(1.0)
			if setting not in ["collision_thickness", "nav_agent_radius", "nav_max_slope", "nav_max_step_height", "nav_min_region_size"]:
				spin_slider.set_step(0.01)
			spin_slider.set_value(s_value)
			spin_slider.value_changed.connect(func(value):
				var target_setting := setting
				if setting == "blend_sharpness" and int(plugin.current_terrain_node.get("floor_blend_mode")) == 1:
					target_setting = "blend_noise_threshold"
				_on_terrain_setting_changed(target_setting, value)
			)
			spin_slider.name = "SettingEditor"
			spin_slider.set_custom_minimum_size(Vector2(120, 35))
			
			ts_cont = MarginContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(120, 35))
			ts_cont.add_theme_constant_override("margin_top", -5)
			ts_cont.add_child(spin_slider, true)
		"EditorResourcePicker":
			var editor_r_picker := EditorResourcePicker.new()
			if setting == "noise_hmap":
				editor_r_picker.set_base_type("Noise")
			elif setting == "prefab_set":
				editor_r_picker.set_base_type("MarchingSquaresPrefabSet")
			else:
				editor_r_picker.set_base_type("Texture2D")
			editor_r_picker.edited_resource = plugin.current_terrain_node.get(setting)
			_hide_textures(editor_r_picker)
			editor_r_picker.resource_changed.connect(func(resource): _on_terrain_setting_changed(setting, resource))
			editor_r_picker.set_custom_minimum_size(Vector2(120, 25))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(editor_r_picker, true)
		"ColorPickerButton":
			var c_pick_button := ColorPickerButton.new()
			c_pick_button.color = plugin.current_terrain_node.get(setting)
			c_pick_button.color_changed.connect(func(color): _on_terrain_setting_changed(setting, color))
			c_pick_button.set_custom_minimum_size(Vector2(105, 25))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(115, 35))
			ts_cont.add_child(c_pick_button, true)
		"CheckBox":
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = plugin.current_terrain_node.get(setting)
			checkbox.toggled.connect(func(pressed): _on_terrain_setting_changed(setting, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(35, 35))
			ts_cont.add_child(checkbox, true)
		"OptionButton":
			var option_button := OptionButton.new()
			option_button.set_flat(true)
			if setting == "default_wall_texture":
				var terrain_names : Array = []
				if plugin.current_terrain_node and plugin.current_terrain_node.current_texture_preset and plugin.current_terrain_node.current_texture_preset.new_tex_names:
					terrain_names = plugin.current_terrain_node.current_texture_preset.new_tex_names.texture_names
				else:
					terrain_names = attribute_list.vp_tex_names.texture_names
				var wall_slots := _get_visible_texture_option_slots(false)
				for slot_idx in wall_slots:
					option_button.add_item(_get_vertex_paint_material_label(slot_idx, terrain_names))
					option_button.set_item_metadata(option_button.item_count - 1, slot_idx)
			elif setting == "blend_mode":
				option_button.add_item("Smoothed")
			elif setting == "floor_blend_mode":
				option_button.add_item("Smooth")
				option_button.add_item("Noisy")
			elif setting == "wind_mode":
				option_button.add_item("Smooth")
				option_button.add_item("Gusty")
				option_button.add_item("Turbulent")
			elif setting == "extra_collision_layer":
				for i in range(24):
					option_button.add_item(str(i + 9))
			
			if setting == "extra_collision_layer":
				option_button.selected = plugin.current_terrain_node.get(setting) - 9
			elif setting == "default_wall_texture":
				var current_slot := int(plugin.current_terrain_node.get(setting))
				var selected_idx := 0
				for item_idx in range(option_button.item_count):
					if int(option_button.get_item_metadata(item_idx)) == current_slot:
						selected_idx = item_idx
						break
				option_button.selected = selected_idx
			elif setting == "blend_mode":
				option_button.selected = 0
			elif setting == "wind_mode":
				option_button.selected = clampi(int(plugin.current_terrain_node.get(setting)), 0, 2)
			else:
				option_button.selected = plugin.current_terrain_node.get(setting)
			
			if setting == "default_wall_texture":
				option_button.item_selected.connect(func(index):
					_on_terrain_setting_changed(setting, int(option_button.get_item_metadata(index)))
				)
			else:
				option_button.item_selected.connect(func(index):
					_on_terrain_setting_changed(setting, index)
					if setting == "floor_blend_mode":
						call_deferred("_update_floor_blend_setting_visibility")
				)
			option_button.set_custom_minimum_size(Vector2(120, 35))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(130, 35))
			ts_cont.add_child(option_button, true)
		"LineEdit":
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.text = str(plugin.current_terrain_node.get(setting))
			line_edit.placeholder_text = "(auto - scene relative)"
			line_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			line_edit.set_custom_minimum_size(Vector2(200, 25))
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(210, 35))
			ts_cont.add_child(line_edit, true)
		"FolderPicker":
			var folder_hbox := HBoxContainer.new()
			folder_hbox.add_theme_constant_override("separation", 4)
			
			var path_edit := LineEdit.new()
			path_edit.set_flat(true)
			path_edit.text = str(plugin.current_terrain_node.get(setting))
			path_edit.placeholder_text = "(auto - scene relative)"
			path_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			path_edit.set_custom_minimum_size(Vector2(180, 25))
			folder_hbox.add_child(path_edit, true)
			
			var browse_btn := Button.new()
			browse_btn.text = "..."
			browse_btn.tooltip_text = "Browse for folder"
			browse_btn.set_custom_minimum_size(Vector2(30, 25))
			browse_btn.pressed.connect(func(): _open_folder_dialog(setting, path_edit))
			folder_hbox.add_child(browse_btn, true)
			
			ts_cont = CenterContainer.new()
			ts_cont.set_custom_minimum_size(Vector2(220, 35))
			ts_cont.add_child(folder_hbox, true)
		_:
			ts_cont = Control.new()
	
	hbox.add_child(ts_cont, true)
	if setting in ["wind_gust_speed", "wind_gust_strength"]:
		_wind_setting_rows[setting] = hbox
	return hbox


func _get_setting_value(p_setting_name: String) -> Variant:
	match p_setting_name:
		"brush_type":
			return plugin.current_brush_index
		"vp_falloff_mode":
			return plugin.vp_falloff_mode == plugin.VertexPaintFalloffMode.DITHERED
		"size":
			return plugin.brush_size
		"ease_value":
			return plugin.ease_value
		"height":
			return plugin.height
		"strength":
			return plugin.strength
		"flatten":
			return plugin.flatten
		"falloff":
			return plugin.falloff
		"curve3d_mode":
			return plugin.curve3d_mode
		"mask_mode":
			return plugin.should_mask_grass
		"material":
			return plugin.vertex_color_idx
		"texture_preset":
			return plugin.current_texture_preset
		"quick_paint_selection":
			return plugin.current_quick_paint
		"paint_walls":
			return plugin.paint_walls_mode
		"populator":
			pass
		"remove_selection":
			return plugin.remove_selection
		"chunk_management":
			pass
		"terrain_settings":
			pass
		"hm_heightmap_image":
			return plugin.hm_heightmap_image
		"hm_grass_image":
			return plugin.hm_grass_image
		"hm_texture_image":
			return plugin.hm_texture_image
		"hm_chunks_x":
			return plugin.hm_chunks_x
		"hm_chunks_z":
			return plugin.hm_chunks_z
		"hm_max_height":
			return plugin.hm_max_height
		"hm_merge_mode":
			return plugin.hm_merge_mode
		"heightmap":
			pass
		_:
			push_error("Couldn't find tool attributes setting name: " + p_setting_name)
	return "ERROR"


func _open_folder_dialog(setting_name: String, path_edit: LineEdit) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Select Directory"
	
	# Set initial path from current value or project root
	var current_path : String = path_edit.text
	if current_path.is_empty():
		dialog.current_dir = "res://"
	else:
		dialog.current_dir = current_path.get_base_dir()
	
	dialog.dir_selected.connect(func(dir: String):
		path_edit.text = dir
		_on_terrain_setting_changed(setting_name, dir)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	# Add to editor base control for proper modal behavior
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

#region on-signal functions

func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_setting_name, p_value)


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("terrain_setting_changed", p_setting_name, p_value)
	if p_setting_name == "wind_mode":
		call_deferred("_update_wind_setting_visibility")


func _on_chunk_selected(option_button: OptionButton, grass_mode_button: OptionButton, p_chunk: String) -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		selected_chunk = null
		plugin.selected_chunk = null
		option_button.selected = -1
		grass_mode_button.selected = -1
		return
	
	var chunk := terrain.find_child(p_chunk) as MarchingSquaresTerrainChunk
	if chunk == null:
		selected_chunk = null
		plugin.selected_chunk = null
		option_button.selected = -1
		grass_mode_button.selected = -1
		return
	
	option_button.selected = int(chunk.merge_mode)
	grass_mode_button.selected = int(chunk.grass_mode)
	selected_chunk = chunk
	plugin.selected_chunk = selected_chunk
	
	plugin.gizmo_plugin.trigger_redraw(terrain)


func _apply_mode_to_all_chunks() -> void:
	if plugin.current_terrain_node == null:
		return
	if selected_chunk == null:
		return
	for child in plugin.current_terrain_node.get_children():
		var terrain_chunk := child as MarchingSquaresTerrainChunk
		if terrain_chunk != null:
			_change_chunk_mode(terrain_chunk, int(selected_chunk.merge_mode))
			_change_chunk_grass_mode(terrain_chunk, int(selected_chunk.grass_mode))


func _on_populator_selected(p_populator: String) -> void:
	var terrain := plugin.current_terrain_node
	var populator : MarchingSquaresPopulator = terrain.find_child(p_populator)
	
	selected_populator = populator
	plugin.current_populator = populator
	plugin.ui.populator_settings.add_populator_settings()


func _on_chunk_mode_changed(m_mode: int) -> void:
	_change_chunk_mode(selected_chunk, m_mode)


func _on_chunk_grass_mode_changed(m_mode: int) -> void:
	_change_chunk_grass_mode(selected_chunk, m_mode)


func _change_chunk_mode(_chunk: MarchingSquaresTerrainChunk, m_mode: int) -> void:
	match MarchingSquaresTerrainChunk.Mode.find_key(m_mode):
		"CUBIC":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
		"POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.POLYHEDRON
		"ROUNDED_POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.ROUNDED_POLYHEDRON
		"SEMI_ROUND":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SEMI_ROUND
		"SPHERICAL":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SPHERICAL


func _change_chunk_grass_mode(_chunk: MarchingSquaresTerrainChunk, m_mode: int) -> void:
	if _chunk == null:
		return
	match MarchingSquaresTerrainChunk.GrassMode.find_key(m_mode):
		"GRASS":
			_chunk.grass_mode = MarchingSquaresTerrainChunk.GrassMode.GRASS
		"GRASSLESS":
			_chunk.grass_mode = MarchingSquaresTerrainChunk.GrassMode.GRASSLESS

#endregion

#region UI-helpers

func _make_vector_editor(type: String, value: Variant, setting_name: String) -> HBoxContainer:
	var hbox_cont := HBoxContainer.new()
	
	if type == "Vector2":
		var spin_x := make_spinbox(value.x, 0.1)
		var spin_y := make_spinbox(value.y, 0.1)
		
		var handler_x := func(v):
			var updated_val = Vector2(v, spin_y.value)
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector2(spin_x.value, v)
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
	
	elif type == "Vector3i":
		var spin_x := make_spinbox(value.x, 1.0)
		var spin_y := make_spinbox(value.y, 1.0)
		var spin_z := make_spinbox(value.z, 1.0)
		
		var handler_x := func(v):
			var updated_val = Vector3i(int(v), int(spin_y.value), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(v), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_z := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(spin_y.value), int(v))
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		spin_z.value_changed.connect(handler_z)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
		hbox_cont.add_child(spin_z)
	
	return hbox_cont


func make_spinbox(val: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.set_step(step)
	spin_box.set_value(float(val))
	spin_box.set_custom_minimum_size(Vector2(50, 25))
	return spin_box


func _make_editor_name(var_name: String) -> String:
	if var_name == "blend_sharpness":
		return "Smoothness"
	var loose_words := var_name.split("_")
	for word in loose_words:
		loose_words[loose_words.find(word)] = word.capitalize()
	return " ".join(loose_words)


func _update_floor_blend_setting_visibility() -> void:
	var blend_row := _find_named_control(self, "blend_sharpness")
	if blend_row == null or plugin == null or plugin.current_terrain_node == null:
		return
	var is_noisy := int(plugin.current_terrain_node.get("floor_blend_mode")) == 1
	var label := _find_named_control(blend_row, "SettingLabel") as Label
	var editor := _find_named_control(blend_row, "SettingEditor") as EditorSpinSlider
	if label != null:
		label.text = ("Noise Threshold" if is_noisy else "Blend Smoothness") + ":"
	if editor != null:
		editor.set_value(float(plugin.current_terrain_node.get("blend_noise_threshold" if is_noisy else "blend_sharpness")))


func _find_named_control(node: Node, target_name: String) -> Control:
	if node is Control and node.name == target_name:
		return node as Control
	for child in node.get_children():
		var found := _find_named_control(child, target_name)
		if found != null:
			return found
	return null


func _hide_textures(texture_node: Node) -> void:
	var texture_button := texture_node.get_child(0) as Button
	texture_button.visible = false


func _make_importer_spinbox_row(label_text: String, setting_name: String, current_val: int, min_val: int, max_val: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.set_text(label_text)
	label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	label.set_custom_minimum_size(Vector2(80, 25))
	var lcc := CenterContainer.new()
	lcc.set_custom_minimum_size(Vector2(80, 35))
	lcc.add_child(label, true)
	hbox.add_child(lcc, true)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer, true)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = 1
	spin.value = current_val
	spin.value_changed.connect(func(v): _on_importer_setting_changed(setting_name, int(v)))
	spin.set_custom_minimum_size(Vector2(70, 25))
	var sc := CenterContainer.new()
	sc.set_custom_minimum_size(Vector2(80, 35))
	sc.add_child(spin, true)
	hbox.add_child(sc, true)
	return hbox


func _on_importer_setting_changed(p_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_name, p_value)


func _on_import_heightmap_pressed() -> void:
	emit_signal("setting_changed", "import_heightmap", true)


func _on_clear_chunks_pressed() -> void:
	emit_signal("setting_changed", "clear_chunks", true)


func _make_exporter_checkbox_row(label_text: String, setting_name: String, current_val: bool) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.set_text(label_text)
	label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
	label.set_custom_minimum_size(Vector2(90, 25))
	var lcc := CenterContainer.new()
	lcc.set_custom_minimum_size(Vector2(90, 35))
	lcc.add_child(label, true)
	hbox.add_child(lcc, true)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer, true)
	var cb := CheckBox.new()
	cb.set_flat(true)
	cb.button_pressed = current_val
	cb.toggled.connect(func(pressed): on_exporter_setting_changed(setting_name, pressed))
	cb.set_custom_minimum_size(Vector2(25, 25))
	var sc := CenterContainer.new()
	sc.set_custom_minimum_size(Vector2(35, 35))
	sc.add_child(cb, true)
	hbox.add_child(sc, true)
	return hbox


func on_exporter_setting_changed(p_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_name, p_value)


func on_extractor_setting_changed(p_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_name, p_value)


func export_terrain_heightmap(filename) -> void:
	plugin.terrain_heightmap_folder_name = filename
	emit_signal("setting_changed", "export_terrain_heightmap", true)


func extract_mesh_heightmap(filename) -> void:
	plugin.mesh_heightmap_name = filename
	emit_signal("setting_changed", "extract_mesh_heightmap", true)


func _format_constant_string(text: String) -> String:
	var words := text.to_lower().split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

#endregion
