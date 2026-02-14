@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin

const VAR_NAMES : Array[Dictionary] = [
	{
		"tex_var": "texture_1",
		"scale_var": "texture_scale_1",
		"sprite_var": "grass_sprite_tex_1",
		"color_var": "texture_albedo_1",
	},
	{
		"tex_var": "texture_2",
		"scale_var": "texture_scale_2",
		"sprite_var": "grass_sprite_tex_2",
		"color_var": "texture_albedo_2",
		"use_grass_var": "tex2_has_grass",
	},
	{
		"tex_var": "texture_3",
		"scale_var": "texture_scale_3",
		"sprite_var": "grass_sprite_tex_3",
		"color_var": "texture_albedo_3",
		"use_grass_var": "tex3_has_grass",
	},
	{
		"tex_var": "texture_4",
		"scale_var": "texture_scale_4",
		"sprite_var": "grass_sprite_tex_4",
		"color_var": "texture_albedo_4",
		"use_grass_var": "tex4_has_grass",
	},
	{
		"tex_var": "texture_5",
		"scale_var": "texture_scale_5",
		"sprite_var": "grass_sprite_tex_5",
		"color_var": "texture_albedo_5",
		"use_grass_var": "tex5_has_grass",
	},
	{
		"tex_var": "texture_6",
		"scale_var": "texture_scale_6",
		"sprite_var": "grass_sprite_tex_6",
		"color_var": "texture_albedo_6",
		"use_grass_var": "tex6_has_grass",
	},
	{
		"tex_var": "texture_7",
		"scale_var": "texture_scale_7",
	},
	{
		"tex_var": "texture_8",
		"scale_var": "texture_scale_8",
	},
	{
		"tex_var": "texture_9",
		"scale_var": "texture_scale_9",
	},
	{
		"tex_var": "texture_10",
		"scale_var": "texture_scale_10",
	},
	{
		"tex_var": "texture_11",
		"scale_var": "texture_scale_11",
	},
	{
		"tex_var": "texture_12",
		"scale_var": "texture_scale_12",
	},
	{
		"tex_var": "texture_13",
		"scale_var": "texture_scale_13",
	},
	{
		"tex_var": "texture_14",
		"scale_var": "texture_scale_14",
	},
	{
		"tex_var": "texture_15",
		"scale_var": "texture_scale_15",
	},
]


func _ready() -> void:
	set_custom_minimum_size(Vector2(195, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	
	var vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(150, 0))
	# Floor textures loop (15 slots)
	for i in range(15):
		var label := Label.new()
		label.set_text("Texture " + str(i+1))
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 15))
		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 25))
		c_cont.add_child(label, true)
		vbox.add_child(c_cont, true)
		
		var tex_var : Texture2D = terrain.get(VAR_NAMES[i].get("tex_var")) #EditorResourcePicker
		# Skip empty/abstract Texture2D objects (causes EditorResourcePicker validation error)
		# Valid textures are always concrete subclasses, never the base Texture2D class
		if tex_var != null and tex_var.get_class() == "Texture2D":
			tex_var = null
		var sprite_var : CompressedTexture2D #EditorResourcePicker
		var color_var : Color #ColorPickerButton
		var use_grass_var : bool #Checkbox
		
		# Add the ground vertex texture
		var editor_r_picker := EditorResourcePicker.new()
		editor_r_picker.set_base_type("Texture2D")
		editor_r_picker.edited_resource = tex_var
		editor_r_picker.resource_changed.connect(func(resource): _on_texture_setting_changed(VAR_NAMES[i].get("tex_var"), resource))
		editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
		
		vbox.add_child(editor_r_picker, true)
		
		# Add scale slider for each texture
		if VAR_NAMES[i].has("scale_var"):
			var scale_var_name : String = VAR_NAMES[i].get("scale_var")
			var scale_value : float = terrain.get(scale_var_name) if terrain.get(scale_var_name) else 1.0
			
			var scale_hbox := HBoxContainer.new()
			scale_hbox.set_custom_minimum_size(Vector2(150, 20))
			
			var scale_label := Label.new()
			scale_label.text = "Scale:"
			scale_label.set_custom_minimum_size(Vector2(40, 20))
			scale_hbox.add_child(scale_label)
			
			var c_cont_2 := CenterContainer.new()
			var scale_slider := HSlider.new()
			scale_slider.min_value = 0.1
			scale_slider.max_value = 40.0
			scale_slider.step = 0.1
			scale_slider.value = scale_value
			scale_slider.set_custom_minimum_size(Vector2(80, 20))
			scale_slider.value_changed.connect(
				func(val): _on_texture_setting_changed(scale_var_name, val)
			)
			scale_slider.drag_ended.connect(
				func(val): _on_slider_drag_ended(val)
			)
			c_cont_2.add_child(scale_slider, true)
			scale_hbox.add_child(c_cont_2, true)
			
			var scale_value_label := Label.new()
			scale_value_label.text = str(scale_value)
			scale_value_label.set_custom_minimum_size(Vector2(25, 20))
			scale_slider.value_changed.connect(
				func(val): scale_value_label.text = str(snapped(val, 0.1))
			)
			scale_hbox.add_child(scale_value_label)
			
			vbox.add_child(scale_hbox, true)
		
		if i <= 5:
			# Add the grass instance sprite
			sprite_var = terrain.get(VAR_NAMES[i].get("sprite_var"))
			# Skip empty/abstract Texture2D objects
			if sprite_var != null and sprite_var.get_class() == "Texture2D":
				sprite_var = null
			
			var editor_r_picker2 := EditorResourcePicker.new()
			editor_r_picker2.set_base_type("Texture2D")
			editor_r_picker2.edited_resource = sprite_var
			editor_r_picker2.resource_changed.connect(func(resource): _on_texture_setting_changed(VAR_NAMES[i].get("sprite_var"), resource))
			editor_r_picker2.set_custom_minimum_size(Vector2(100, 25))
			
			vbox.add_child(editor_r_picker2, true)
			
			# Add the vertex ground color
			color_var = terrain.get(VAR_NAMES[i].get("color_var"))
			var c_pick_button := ColorPickerButton.new()
			c_pick_button.color = color_var
			c_pick_button.color_changed.connect(func(color): _on_texture_setting_changed(VAR_NAMES[i].get("color_var"), color))
			c_pick_button.set_custom_minimum_size(Vector2(150, 25))
			
			var c_cont_2 = CenterContainer.new()
			c_cont_2.set_custom_minimum_size(Vector2(150, 30))
			c_cont_2.add_child(c_pick_button, true)
			vbox.add_child(c_cont_2, true)
		
		if i <= 5 and i >= 1:
			# Add the checkbox to control grass on texture 2~5
			use_grass_var = terrain.get(VAR_NAMES[i].get("use_grass_var"))
			var checkbox := CheckBox.new()
			checkbox.text = "Has grass"
			checkbox.set_flat(true)
			checkbox.button_pressed = use_grass_var
			checkbox.toggled.connect(func(pressed): _on_texture_setting_changed(VAR_NAMES[i].get("use_grass_var"), pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 15))
			
			var c_cont_2 = CenterContainer.new()
			c_cont_2.set_custom_minimum_size(Vector2(25, 25))
			c_cont_2.add_child(checkbox, true)
			vbox.add_child(c_cont_2, true)
		
		vbox.add_child(HSeparator.new())
	
	var m_cont := MarginContainer.new()
	m_cont.add_theme_constant_override("margin_bottom", 7)
	var export_button = MarchingSquaresTexturePresetExporter.new()
	export_button.current_terrain_node = terrain
	m_cont.add_child(export_button, true)
	vbox.add_child(m_cont, true)
	
	add_child(vbox, true)


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("texture_setting_changed", p_setting_name, p_value)


func _on_slider_drag_ended(ended: bool) -> void:
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		chunk.grass_planter.regenerate_all_cells()
