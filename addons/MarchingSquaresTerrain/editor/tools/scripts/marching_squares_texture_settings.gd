@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin

const VAR_NAMES : Array[Dictionary] = [
	{
		"tex_var": "ground_texture",
		"sprite_var": "grass_sprite",
		"color_var": "ground_color",
	},
	{
		"tex_var": "texture_2",
		"sprite_var": "grass_sprite_tex_2",
		"color_var": "ground_color_2",
		"use_grass_var": "tex2_has_grass",
	},
	{
		"tex_var": "texture_3",
		"sprite_var": "grass_sprite_tex_3",
		"color_var": "ground_color_3",
		"use_grass_var": "tex3_has_grass",
	},
	{
		"tex_var": "texture_4",
		"sprite_var": "grass_sprite_tex_4",
		"color_var": "ground_color_4",
		"use_grass_var": "tex4_has_grass",
	},
	{
		"tex_var": "texture_5",
		"sprite_var": "grass_sprite_tex_5",
		"color_var": "ground_color_5",
		"use_grass_var": "tex5_has_grass",
	},
	{
		"tex_var": "texture_6",
		"sprite_var": "grass_sprite_tex_6",
		"color_var": "ground_color_6",
		"use_grass_var": "tex6_has_grass",
	},
	{
		"tex_var": "texture_7",
	},
	{
		"tex_var": "texture_8",
	},
	{
		"tex_var": "texture_9",
	},
	{
		"tex_var": "texture_10",
	},
	{
		"tex_var": "texture_11",
	},
	{
		"tex_var": "texture_12",
	},
	{
		"tex_var": "texture_13",
	},
	{
		"tex_var": "texture_14",
	},
	{
		"tex_var": "texture_15",
	},
]

const WALL_VAR_NAMES : Array[Dictionary] = [
	{ "tex_var": "wall_texture", "color_var": "wall_color" },
	{ "tex_var": "wall_texture_2", "color_var": "wall_color_2" },
	{ "tex_var": "wall_texture_3", "color_var": "wall_color_3" },
	{ "tex_var": "wall_texture_4", "color_var": "wall_color_4" },
	{ "tex_var": "wall_texture_5", "color_var": "wall_color_5" },
	{ "tex_var": "wall_texture_6", "color_var": "wall_color_6" },
]

var vflow_container


func _ready() -> void:
	set_custom_minimum_size(Vector2(165, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func add_texture_settings() -> void:
	if not vflow_container:
		vflow_container = VFlowContainer.new()
	
	for child in get_children():
		child.queue_free()
	
	set_custom_minimum_size(Vector2(165, 0))
	
	var terrain := plugin.current_terrain_node
	
	vflow_container.alignment = FlowContainer.ALIGNMENT_BEGIN
	var vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(150, 0))
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
		
		if i <= 5:
			# Add the grass instance sprite
			sprite_var = terrain.get(VAR_NAMES[i].get("sprite_var"))
			
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
			c_cont_2.set_custom_minimum_size(Vector2(150, 25))
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
		
		if i <= 5:
			vbox.add_child(HSeparator.new())

	# Wall Textures Section Header
	var wall_header := Label.new()
	wall_header.set_text("=== WALL TEXTURES ===")
	wall_header.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(wall_header)
	vbox.add_child(HSeparator.new())

	# Wall textures loop (6 slots)
	for i in range(6):
		var label := Label.new()
		label.set_text("Wall " + str(i+1))
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 15))
		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 25))
		c_cont.add_child(label, true)
		vbox.add_child(c_cont, true)

		# Wall texture picker
		var wall_tex : Texture2D = terrain.get(WALL_VAR_NAMES[i].get("tex_var"))
		var editor_r_picker := EditorResourcePicker.new()
		editor_r_picker.set_base_type("Texture2D")
		editor_r_picker.edited_resource = wall_tex
		editor_r_picker.resource_changed.connect(
			func(resource): _on_texture_setting_changed(WALL_VAR_NAMES[i].get("tex_var"), resource)
		)
		editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
		vbox.add_child(editor_r_picker, true)

		# Wall color picker
		var wall_color : Color = terrain.get(WALL_VAR_NAMES[i].get("color_var"))
		var c_pick_button := ColorPickerButton.new()
		c_pick_button.color = wall_color
		c_pick_button.color_changed.connect(
			func(color): _on_texture_setting_changed(WALL_VAR_NAMES[i].get("color_var"), color)
		)
		c_pick_button.set_custom_minimum_size(Vector2(150, 25))
		var c_cont_2 := CenterContainer.new()
		c_cont_2.set_custom_minimum_size(Vector2(150, 25))
		c_cont_2.add_child(c_pick_button, true)
		vbox.add_child(c_cont_2, true)

		vbox.add_child(HSeparator.new())

	add_child(vbox, true)


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("texture_setting_changed", p_setting_name, p_value)
