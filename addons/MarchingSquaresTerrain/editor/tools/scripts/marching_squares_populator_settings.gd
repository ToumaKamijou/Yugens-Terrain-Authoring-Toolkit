@tool
extends ScrollContainer
class_name MarchingSquaresPopulatorSettings


var plugin : MarchingSquaresTerrainPlugin

const FLOWER_VAR_DATA : Array[Dictionary] = [
	{
		"name": "flower_sprite",
		"label": "Flower Sprite",
		"type": "EditorResourcePicker",
	},
	{
		"name": "color_gradient",
		"label": "Color Gradient",
		"type": "EditorResourcePicker",
	},
	{
		"name": "sprite_size",
		"label": "Sprite Size",
		"type": "Vector2",
	},
	{
		"name": "flower_subdivisions",
		"label": "Flower Subdivisions",
		"type": "SpinBox",
	},
	{
		"name": "should_billboard",
		"label": "Should Billboard",
		"type": "CheckBox",
	},
]

const VEGETATION_VAR_DATA : Array[Dictionary] = [
	{
	"": "",
	},
]


func _ready() -> void:
	set_custom_minimum_size(Vector2(183, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func add_populator_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var selected_populator := plugin.current_populator
	
	var var_data : Array[Dictionary]
	if selected_populator is MarchingSquaresFlowerPlanter:
		var_data = FLOWER_VAR_DATA.duplicate()
	elif selected_populator is MarchingSquaresVegetationPlanter:
		var_data = VEGETATION_VAR_DATA.duplicate()
	else: # Null or invalid
		return
	
	var vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(150, 0))
	for i in range(var_data.size()):
		var label := Label.new()
		label.set_text(var_data[i].get("label"))
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 15))
		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 25))
		c_cont.add_child(label, true)
		vbox.add_child(c_cont, true)
		
		var ts_cont
		var var_type := var_data[i].get("type")
		var var_name := var_data[i].get("name")
		match var_type:
			"EditorResourcePicker":
				var editor_r_picker := EditorResourcePicker.new()
				if var_name == "color_gradient":
					editor_r_picker.set_base_type("GradientTexture1D")
				else:
					editor_r_picker.set_base_type("Texture2D")
				editor_r_picker.edited_resource = selected_populator.get(var_name)
				editor_r_picker.resource_changed.connect(func(resource): _on_populator_setting_changed(var_name, resource))
				editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
				
				ts_cont = CenterContainer.new()
				ts_cont.set_custom_minimum_size(Vector2(110, 35))
				ts_cont.add_child(editor_r_picker, true)
				vbox.add_child(ts_cont, true)
			"Vector2":
				var editor_vec2 = _make_vector_editor(var_type, selected_populator.get(var_name), var_name)
				ts_cont = CenterContainer.new()
				ts_cont.set_custom_minimum_size(Vector2(130, 35))
				ts_cont.add_child(editor_vec2, true)
				vbox.add_child(ts_cont, true)
			"SpinBox":
				var spin_box := SpinBox.new()
				spin_box.value = selected_populator.get(var_name)
				spin_box.value_changed.connect(func(value): _on_populator_setting_changed(var_name, value))
				spin_box.set_custom_minimum_size(Vector2(25, 25))
				
				ts_cont = CenterContainer.new()
				ts_cont.set_custom_minimum_size(Vector2(35, 35))
				ts_cont.add_child(spin_box, true)
				vbox.add_child(ts_cont, true)
			"CheckBox":
				var checkbox := CheckBox.new()
				checkbox.set_flat(true)
				checkbox.button_pressed = selected_populator.get(var_name)
				checkbox.toggled.connect(func(pressed): _on_populator_setting_changed(var_name, pressed))
				checkbox.set_custom_minimum_size(Vector2(25, 25))
				
				ts_cont = CenterContainer.new()
				ts_cont.set_custom_minimum_size(Vector2(35, 35))
				ts_cont.add_child(checkbox, true)
				vbox.add_child(ts_cont, true)
		
		if i != var_data.size() - 1:
			vbox.add_child(HSeparator.new())
	
	add_child(vbox, true)


func _on_populator_setting_changed(p_var_name: String, p_value: Variant) -> void:
	plugin.current_populator.set(p_var_name, p_value)


func _make_vector_editor(type: String, value: Variant, setting_name: String) -> HBoxContainer:
	var hbox_cont := HBoxContainer.new()
	
	if type == "Vector2":
		var spin_x := _make_spinbox(value.x, 0.1)
		var spin_y := _make_spinbox(value.y, 0.1)
		
		var handler_x = func(v):
			var updated_val = Vector2(v, spin_y.value)
			_on_populator_setting_changed(setting_name, updated_val)
		var handler_y = func(v):
			var updated_val = Vector2(spin_x.value, v)
			_on_populator_setting_changed(setting_name, updated_val)
		
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
			_on_populator_setting_changed(setting_name, updated_val)
		var handler_y = func(v):
			var updated_val = Vector3i(int(spin_x.value), int(v), int(spin_z.value))
			_on_populator_setting_changed(setting_name, updated_val)
		var handler_z = func(v):
			var updated_val = Vector3i(int(spin_x.value), int(spin_y.value), int(v))
			_on_populator_setting_changed(setting_name, updated_val)
		
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
