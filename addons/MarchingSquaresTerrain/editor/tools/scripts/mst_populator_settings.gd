@tool
extends ScrollContainer
class_name MarchingSquaresPopulatorSettings


var plugin : MarchingSquaresTerrainPlugin
var _built_for_terrain_id : int = 0

const TEXTURE_SETTINGS_MIN_WIDTH_SMALL := 205
const TEXTURE_SETTINGS_MIN_WIDTH_LARGE := 324
const POPULATOR_PREVIEW_SIZE_SMALL := 96
const POPULATOR_PREVIEW_SIZE_LARGE := 128
const LARGE_EDITOR_RESOLUTION := Vector2i(1920, 1080)

const _FLOWER_EDIT_WINDOW := preload("uid://dbarg5nvaylij")


func _ready() -> void:
	# Reserve enough width for populator previews and labels on larger editor layouts.
	set_custom_minimum_size(Vector2(_get_texture_settings_min_width(), 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _get_texture_settings_min_width() -> int:
	var editor_window := get_window()
	var window_size := editor_window.size if editor_window != null else DisplayServer.screen_get_size()
	if window_size.x > LARGE_EDITOR_RESOLUTION.x and window_size.y > LARGE_EDITOR_RESOLUTION.y:
		return TEXTURE_SETTINGS_MIN_WIDTH_LARGE
	return TEXTURE_SETTINGS_MIN_WIDTH_SMALL


func _get_slot_preview_texture(populator: MarchingSquaresPopulator) -> Texture2D:
	if populator == null:
		return null
	
	match populator.CLASS_NAME:
		"MarchingSquaresFlowerPlanter":
			return populator.flower_sprite
	
	return null


func _make_slot_preview(texture: Texture2D, _size: int = 64) -> TextureRect:
	var thumb := TextureRect.new()
	thumb.texture = texture
	# Keep flower/sprite previews sharp instead of bilinear-softened.
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(_size, _size)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return thumb


func add_populator_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		_built_for_terrain_id = 0
		return
	_built_for_terrain_id = terrain.get_instance_id()
	
	var selected_populator := plugin.current_populator
	
	var vbox := VBoxContainer.new()
	# Match the dock width so slot cards do not collapse into unreadable previews/labels.
	var texture_settings_min_width := _get_texture_settings_min_width()
	var populator_preview_size := _get_populator_preview_size()
	vbox.set_custom_minimum_size(Vector2(texture_settings_min_width, 0))
	
	var pop_button := MarchingSquaresPopulateButton.new()
	pop_button.current_terrain_node = plugin.current_terrain_node
	var pop_cont := MarginContainer.new()
	pop_cont.add_theme_constant_override("margin_bottom", 2)
	pop_cont.set_custom_minimum_size(Vector2(65, 35))
	pop_cont.add_child(pop_button, true)
	vbox.add_child(pop_cont, true)
	
	for child in plugin.current_terrain_node.get_children():
		if child is MarchingSquaresPopulator:
			var tile := VBoxContainer.new()
			tile.set_custom_minimum_size(Vector2(texture_settings_min_width - 20, populator_preview_size + 60))
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var tex_var : Texture2D = _get_slot_preview_texture(child)
			
			var thumb := _make_slot_preview(tex_var, populator_preview_size)
			var thumb_center := CenterContainer.new()
			thumb_center.add_child(thumb)
			tile.add_child(thumb_center)
			
			var nameplate := PanelContainer.new()
			nameplate.set_custom_minimum_size(Vector2(texture_settings_min_width - 52, 24))
			nameplate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			
			var lbl := Label.new()
			lbl.text = child.name
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			lbl.clip_text = true
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lbl.set_custom_minimum_size(Vector2(texture_settings_min_width - 60, 20))
			nameplate.add_child(lbl)
			
			var nameplate_center := CenterContainer.new()
			nameplate_center.add_child(nameplate)
			tile.add_child(nameplate_center)
			
			var btn_h := HBoxContainer.new()
			btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
			
			var edit_btn := Button.new()
			edit_btn.text = "Edit"
			edit_btn.set_custom_minimum_size(Vector2(48, 24))
			edit_btn.pressed.connect(func(): _open_populator_edit_window(child))
			btn_h.add_child(edit_btn)
			
			var rem_btn := Button.new()
			rem_btn.text = "X"
			rem_btn.set_custom_minimum_size(Vector2(28, 24))
			rem_btn.pressed.connect(func(): _clear_slot(child, true))
			btn_h.add_child(rem_btn)
		
			var btn_center := CenterContainer.new()
			btn_center.add_child(btn_h)
			tile.add_child(btn_center)
			vbox.add_child(HSeparator.new())
			vbox.add_child(tile)
	
	add_child(vbox)


func _clear_slot(populator: MarchingSquaresPopulator, p_refresh_ui: bool = true) -> void:
	if populator == null:
		return
	
	if populator == plugin.current_populator:
		plugin.current_populator = null
	
	populator.tree_exited.connect(func():
		_refresh_editor(p_refresh_ui), CONNECT_ONE_SHOT)
	
	populator.queue_free()


func _refresh_editor(p_refresh_ui: bool = true) -> void:
	if plugin and plugin.ui and plugin.ui.tool_attributes:
		plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
	if p_refresh_ui:
		call_deferred("add_populator_settings")


func _open_populator_edit_window(populator: MarchingSquaresPopulator) -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	match populator.CLASS_NAME:
		"MarchingSquaresFlowerPlanter":
			var existing := get_tree().get_root().get_node_or_null("FlowerEditWindow")
			if existing:
				existing.queue_free()
			
			var dialog : MarchingSquaresFlowerEditWindow = _FLOWER_EDIT_WINDOW.instantiate()
			dialog.title = "Edit Flower"
			
			dialog.albedo_texture_picker.edited_resource = populator.flower_sprite
			dialog.albedo_texture_picker.resource_changed.connect(func(res):
				_on_populator_setting_changed("flower_sprite", res)
				_refresh_editor(true)
			)
			
			dialog.albedo_color_picker.edited_resource = populator.color_gradient
			dialog.albedo_color_picker.resource_changed.connect(func(res):
				_on_populator_setting_changed("color_gradient", res)
			)
			
			dialog.vec_2_left.value = populator.sprite_size.x
			dialog.vec_2_left.value_changed.connect(func(val):
				var new_sprite_size : Vector2 = populator.sprite_size
				new_sprite_size.x = val
				_on_populator_setting_changed("sprite_size", new_sprite_size)
			)
			
			dialog.vec_2_right.value = populator.sprite_size.y
			dialog.vec_2_right.value_changed.connect(func(val):
				var new_sprite_size : Vector2 = populator.sprite_size
				new_sprite_size.y = val
				_on_populator_setting_changed("sprite_size", new_sprite_size)
			)
			
			dialog.flower_h_map_picker.edited_resource = populator.flower_hmap
			dialog.flower_h_map_picker.resource_changed.connect(func(res):
				_on_populator_setting_changed("flower_hmap", res)
			)
			
			dialog.height_range_h_slider.value = populator.rng_height_range
			dialog.height_range_h_slider.value_changed.connect(func(val):
				_on_populator_setting_changed("rng_height_range", val)
			)
			
			dialog.size_range_h_slider.value = populator.rng_size_range
			dialog.size_range_h_slider.value_changed.connect(func(val):
				_on_populator_setting_changed("rng_size_range", val)
			)
			
			dialog.billboard_check_box.button_pressed = populator.should_billboard
			dialog.billboard_check_box.toggled.connect(func(_bool):
				_on_populator_setting_changed("should_billboard", _bool)
			)
			
			dialog.height_offset_spin_box.value = populator.base_height_offset
			dialog.height_offset_spin_box.value_changed.connect(func(val):
				_on_populator_setting_changed("base_height_offset", val)
			)
			
			dialog.flower_subdivions_spin_box.value = populator.flower_subdivisions
			dialog.flower_subdivions_spin_box.value_changed.connect(func(val):
				_on_populator_setting_changed("flower_subdivisions", val)
			)
			
			# Dialog window confirmation
			dialog.confirmed.connect(func():
				_refresh_editor(true)
			)
			dialog.canceled.connect(func():
				_refresh_editor(true)
			)
			# Parent window to the scene root so rebuilding it won't free it
			var root := get_tree().get_root()
			if root != null:
				root.add_child(dialog)
			else:
				add_child(dialog)
			dialog.popup_centered()


func _get_populator_preview_size() -> int:
	return POPULATOR_PREVIEW_SIZE_LARGE if _use_large_editor_layout() else POPULATOR_PREVIEW_SIZE_SMALL


func _use_large_editor_layout() -> bool:
	var editor_window := get_window()
	var window_size := editor_window.size if editor_window != null else DisplayServer.screen_get_size()
	return window_size.x > LARGE_EDITOR_RESOLUTION.x and window_size.y > LARGE_EDITOR_RESOLUTION.y


func is_built_for_current_terrain() -> bool:
	var terrain := plugin.current_terrain_node if plugin != null else null
	return terrain != null and _built_for_terrain_id == terrain.get_instance_id() and get_child_count() > 0


func _on_populator_setting_changed(p_var_name: String, p_value: Variant) -> void:
	plugin.current_populator.set(p_var_name, p_value)
