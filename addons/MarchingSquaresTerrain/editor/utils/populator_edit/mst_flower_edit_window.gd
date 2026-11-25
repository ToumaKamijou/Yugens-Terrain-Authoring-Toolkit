@tool
extends AcceptDialog
class_name MarchingSquaresFlowerEditWindow


# Albedo Settings
@export var albedo_texture_picker : EditorResourcePicker
@export var albedo_color_picker : EditorResourcePicker
@export var edit_gradient_button : Button
# Sprite Size
@export var vec_2_left : SpinBox
@export var vec_2_right : SpinBox

# RNG Settings
@export var flower_h_map_picker : EditorResourcePicker
@export var height_range_h_slider : HSlider
@export var size_range_h_slider : HSlider

# Advanced Settings
@export var billboard_check_box : CheckBox
@export var height_offset_spin_box : SpinBox
@export var flower_subdivions_spin_box : SpinBox


func _ready() -> void:
	if edit_gradient_button != null:
		edit_gradient_button.pressed.connect(_on_edit_gradient_pressed)


func _on_edit_gradient_pressed() -> void:
	if albedo_color_picker == null:
		return
	
	var gradient_texture := albedo_color_picker.edited_resource as GradientTexture1D
	if gradient_texture == null or gradient_texture.gradient == null:
		return
	
	# Open the actual Gradient resource so its color stops and offsets can be edited.
	EditorInterface.edit_resource(gradient_texture.gradient)
