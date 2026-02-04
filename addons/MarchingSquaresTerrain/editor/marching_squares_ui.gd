@tool
extends Node
class_name MarchingSquaresUI


const TOOLBAR : Script = preload("res://addons/MarchingSquaresTerrain/editor/tools/scripts/marching_squares_toolbar.gd")
const TOOL_ATTRIBUTES : Script = preload("res://addons/MarchingSquaresTerrain/editor/tools/scripts/marching_squares_tool_attributes.gd")
const TEXTURE_SETTINGS : Script = preload("res://addons/MarchingSquaresTerrain/editor/tools/scripts/marching_squares_texture_settings.gd")
const POPULATOR_SETTINGS : Script = preload("res://addons/MarchingSquaresTerrain/editor/tools/scripts/marching_squares_populator_settings.gd")

var plugin : MarchingSquaresTerrainPlugin
var toolbar : TOOLBAR
var tool_attributes : TOOL_ATTRIBUTES
var texture_settings : TEXTURE_SETTINGS
var populator_settings : POPULATOR_SETTINGS
var active_tool : int
var visible: bool = false


func _enter_tree() -> void:
	call_deferred("_deferred_enter_tree")


func _deferred_enter_tree() -> void:
	if not Engine.is_editor_hint():
		printerr("ERROR: [MarchingSquaresUI] attempt to load during runtime (NOT SUPPORTED)")
		return
	
	if not plugin:
		printerr("ERROR: [MarchingSquaresUI] plugin not ready")
		return
	
	toolbar = TOOLBAR.new()
	toolbar.tool_changed.connect(_on_tool_changed)
	toolbar.hide()
	
	tool_attributes = TOOL_ATTRIBUTES.new()
	tool_attributes.setting_changed.connect(_on_setting_changed)
	tool_attributes.terrain_setting_changed.connect(_on_terrain_setting_changed)
	tool_attributes.plugin = plugin
	tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
	tool_attributes.hide()
	
	texture_settings = TEXTURE_SETTINGS.new()
	texture_settings.texture_setting_changed.connect(_on_texture_setting_changed)
	texture_settings.plugin = plugin
	texture_settings.hide()
	
	populator_settings = POPULATOR_SETTINGS.new()
	populator_settings.plugin = plugin
	populator_settings.hide()
	
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, toolbar)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, tool_attributes)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, texture_settings)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, populator_settings)


func _exit_tree() -> void:
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, toolbar)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, tool_attributes)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, texture_settings)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, populator_settings)
	
	toolbar.queue_free()
	tool_attributes.queue_free()
	texture_settings.queue_free()
	populator_settings.queue_free()


func set_visible(is_visible: bool) -> void:
	visible = is_visible
	toolbar.set_visible(is_visible)
	tool_attributes.set_visible(is_visible)
	texture_settings.set_visible(is_visible)
	populator_settings.set_visible(is_visible)
	
	if is_visible:
		await get_tree().create_timer(.01).timeout
		
		if active_tool == null:
			active_tool = 0
		
		if toolbar and toolbar.tool_buttons.has(active_tool):
			toolbar.tool_buttons[active_tool].set_pressed(true)
		
		tool_attributes.show()
		_on_tool_changed(active_tool)


func _on_tool_changed(tool_index: int) -> void:
	active_tool = tool_index
	
	if tool_index == 5: # Vertex Painting
		tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
		texture_settings.show()
		populator_settings.hide()
		texture_settings.add_texture_settings()
	elif tool_index == 6: # Populate
		populator_settings.show()
		texture_settings.hide()
		populator_settings.add_populator_settings()
	else:
		texture_settings.hide()
		populator_settings.hide()
	
	if tool_index == 3: # Bridge tool
		plugin.falloff = false
		plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", false)
	
	plugin.active_tool = tool_index
	plugin.mode = tool_index
	plugin.vertex_color_idx = 0 # Set to the first material on start # Working around a UI sync bug. #TODO: This is temp workaround - Possible refactor.
	tool_attributes.show_tool_attributes(active_tool)


func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	match p_setting_name:
		"brush_type":
			if p_value is int:
				plugin.current_brush_index = p_value
				plugin.BRUSH_RADIUS_VISUAL = plugin.BrushMode.get(str(p_value))
				plugin.BRUSH_RADIUS_MATERIAL = plugin.BrushMat.get(str(p_value))
				plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", plugin.falloff)
		"size":
			if p_value is float or p_value is int:
				plugin.brush_size = float(p_value)
		"ease_value":
			if p_value is float:
				plugin.ease_value = p_value
		"flatten":
			if p_value is bool:
				plugin.flatten = p_value
		"falloff":
			if p_value is bool:
				plugin.falloff = p_value
				if plugin.BRUSH_RADIUS_MATERIAL:
					plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", p_value)
		"strength":
			if p_value is float or p_value is int:
				plugin.strength = float(p_value)
		"height":
			if p_value is float or p_value is int:
				plugin.height = float(p_value)
		"mask_mode": # Grass mask mode
			if p_value is bool:
				plugin.should_mask_grass = p_value
		"material": # Vertex paint setting
			if p_value is int:
				plugin.vertex_color_idx = p_value
		"texture_name":
			if p_value is String:
				if plugin.vertex_color_idx == 0 or plugin.vertex_color_idx == 15:
					return
				var new_preset_names = plugin.current_texture_preset.new_tex_names.texture_names.duplicate()
				new_preset_names[plugin.vertex_color_idx] = p_value
				plugin.current_texture_preset.new_tex_names.texture_names = new_preset_names
			tool_attributes.show_tool_attributes(active_tool)
		"texture_preset":
			if p_value is MarchingSquaresTexturePreset:
				plugin.current_texture_preset = p_value
			else:
				plugin.current_texture_preset = null
			# Rebuild tool attributes to refresh Quick Paint dropdown
			tool_attributes.show_tool_attributes(active_tool)
		"quick_paint_selection":
			if p_value is MarchingSquaresQuickPaint:
				plugin.current_quick_paint = p_value
			else:
				plugin.current_quick_paint = null
		"paint_walls":
			if p_value is bool:
				plugin.paint_walls_mode = p_value


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	var terrain := plugin.current_terrain_node
	match p_setting_name:
		"dimensions":
			if p_value is Vector3i:
				terrain.dimensions = p_value
		"cell_size":
			if p_value is Vector2:
				terrain.cell_size = p_value
		"blend_mode":
			if p_value is int:
				terrain.blend_mode = p_value
		"wall_threshold":
			if p_value is float:
				terrain.wall_threshold = p_value
		"noise_hmap":
			if p_value is Noise or p_value == null:
				terrain.noise_hmap = p_value
		"wall_texture":
			if p_value is Texture2D or p_value == null:
				terrain.wall_texture = p_value
		"wall_color":
			if p_value is Color:
				terrain.wall_color = p_value
		"animation_fps":
			if p_value is int or p_value is float:
				terrain.animation_fps = p_value
		"grass_subdivisions":
			if p_value is int or p_value is float:
				terrain.grass_subdivisions = p_value
		"grass_size":
			if p_value is Vector2:
				terrain.grass_size = p_value
		"ridge_threshold":
			if p_value is float:
				terrain.ridge_threshold = p_value
		"ledge_threshold":
			if p_value is float:
				terrain.ledge_threshold = p_value
		"use_ridge_texture":
			if p_value is bool:
				terrain.use_ridge_texture = p_value
		"default_wall_texture":
			if p_value is int:
				terrain.default_wall_texture = p_value
		"extra_collision_layer":
			if p_value is int:
				# +1 because collision layers don't start from 0 like indexed items
				# +8 because the selectable collision layers range from 9 to 32
				terrain.extra_collision_layer = p_value + 9


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	var terrain := plugin.current_terrain_node
	if not terrain:
		printerr("ERROR: [MarchingSquaresUI] No current terrain node to apply texture settings to")
		return
	match p_setting_name:
		"ground_texture":
			if p_value is Texture2D or p_value == null:
				terrain.ground_texture = p_value
		"grass_sprite":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite = p_value
		"ground_color":
			if p_value is Color:
				terrain.ground_color = p_value
		"texture_2":
			if p_value is Texture2D or p_value == null:
				terrain.texture_2 = p_value
		"grass_sprite_tex_2":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite_tex_2 = p_value
		"ground_color_2":
			if p_value is Color:
				terrain.ground_color_2 = p_value
		"tex2_has_grass":
			if p_value is bool:
				terrain.tex2_has_grass = p_value
		"texture_3":
			if p_value is Texture2D or p_value == null:
				terrain.texture_3 = p_value
		"grass_sprite_tex_3":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite_tex_3 = p_value
		"ground_color_3":
			if p_value is Color:
				terrain.ground_color_3 = p_value
		"tex3_has_grass":
			if p_value is bool:
				terrain.tex3_has_grass = p_value
		"texture_4":
			if p_value is Texture2D or p_value == null:
				terrain.texture_4 = p_value
		"grass_sprite_tex_4":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite_tex_4 = p_value
		"ground_color_4":
			if p_value is Color:
				terrain.ground_color_4 = p_value
		"tex4_has_grass":
			if p_value is bool:
				terrain.tex4_has_grass = p_value
		"texture_5":
			if p_value is Texture2D or p_value == null:
				terrain.texture_5 = p_value
		"grass_sprite_tex_5":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite_tex_5 = p_value
		"ground_color_5":
			if p_value is Color:
				terrain.ground_color_5 = p_value
		"tex5_has_grass":
			if p_value is bool:
				terrain.tex5_has_grass = p_value
		"texture_6":
			if p_value is Texture2D or p_value == null:
				terrain.texture_6 = p_value
		"grass_sprite_tex_6":
			if p_value is CompressedTexture2D or p_value == null:
				terrain.grass_sprite_tex_6 = p_value
		"ground_color_6":
			if p_value is Color:
				terrain.ground_color_6 = p_value
		"tex6_has_grass":
			if p_value is bool:
				terrain.tex6_has_grass = p_value
		"texture_7":
			if p_value is Texture2D or p_value == null:
				terrain.texture_7 = p_value
		"texture_8":
			if p_value is Texture2D or p_value == null:
				terrain.texture_8 = p_value
		"texture_9":
			if p_value is Texture2D or p_value == null:
				terrain.texture_9 = p_value
		"texture_10":
			if p_value is Texture2D or p_value == null:
				terrain.texture_10 = p_value
		"texture_11":
			if p_value is Texture2D or p_value == null:
				terrain.texture_11 = p_value
		"texture_12":
			if p_value is Texture2D or p_value == null:
				terrain.texture_12 = p_value
		"texture_13":
			if p_value is Texture2D or p_value == null:
				terrain.texture_13 = p_value
		"texture_14":
			if p_value is Texture2D or p_value == null:
				terrain.texture_14 = p_value
		"texture_15":
			if p_value is Texture2D or p_value == null:
				terrain.texture_15 = p_value
		# Per-texture UV scale handlers
		"texture_scale_1":
			if p_value is float or p_value is int:
				terrain.texture_scale_1 = float(p_value)
		"texture_scale_2":
			if p_value is float or p_value is int:
				terrain.texture_scale_2 = float(p_value)
		"texture_scale_3":
			if p_value is float or p_value is int:
				terrain.texture_scale_3 = float(p_value)
		"texture_scale_4":
			if p_value is float or p_value is int:
				terrain.texture_scale_4 = float(p_value)
		"texture_scale_5":
			if p_value is float or p_value is int:
				terrain.texture_scale_5 = float(p_value)
		"texture_scale_6":
			if p_value is float or p_value is int:
				terrain.texture_scale_6 = float(p_value)
		"texture_scale_7":
			if p_value is float or p_value is int:
				terrain.texture_scale_7 = float(p_value)
		"texture_scale_8":
			if p_value is float or p_value is int:
				terrain.texture_scale_8 = float(p_value)
		"texture_scale_9":
			if p_value is float or p_value is int:
				terrain.texture_scale_9 = float(p_value)
		"texture_scale_10":
			if p_value is float or p_value is int:
				terrain.texture_scale_10 = float(p_value)
		"texture_scale_11":
			if p_value is float or p_value is int:
				terrain.texture_scale_11 = float(p_value)
		"texture_scale_12":
			if p_value is float or p_value is int:
				terrain.texture_scale_12 = float(p_value)
		"texture_scale_13":
			if p_value is float or p_value is int:
				terrain.texture_scale_13 = float(p_value)
		"texture_scale_14":
			if p_value is float or p_value is int:
				terrain.texture_scale_14 = float(p_value)
		"texture_scale_15":
			if p_value is float or p_value is int:
				terrain.texture_scale_15 = float(p_value)
	
	terrain.save_to_preset()
