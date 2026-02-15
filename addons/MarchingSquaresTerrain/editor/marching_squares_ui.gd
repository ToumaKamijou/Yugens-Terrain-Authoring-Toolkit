@tool
extends Node
class_name MarchingSquaresUI


const TOOLBAR : Script = preload("uid://3d77dnetkeik")
const TOOL_ATTRIBUTES : Script = preload("uid://buxevb44hutjm")
const TEXTURE_SETTINGS : Script = preload("uid://blvx0jk6wxk5p")
const POPULATOR_SETTINGS : Script = preload("uid://3mi36g1r2oy2")

#region texture setting property maps
# Property names that map directly to terrain properties with same name
const TEXTURE_PROPERTIES := [
	"texture_1", "texture_2", "texture_3", "texture_4", "texture_5",
	"texture_6", "texture_7", "texture_8", "texture_9", "texture_10",
	"texture_11", "texture_12", "texture_13", "texture_14", "texture_15"
]

const GRASS_SPRITE_PROPERTIES := [
	"grass_sprite_tex_1", "grass_sprite_tex_2", "grass_sprite_tex_3",
	"grass_sprite_tex_4", "grass_sprite_tex_5", "grass_sprite_tex_6"
]

const COLOR_PROPERTIES := [
	"texture_albedo_1", "texture_albedo_2", "texture_albedo_3",
	"texture_albedo_4", "texture_albedo_5", "texture_albedo_6"
]

const HAS_GRASS_PROPERTIES := [
	"tex2_has_grass", "tex3_has_grass", "tex4_has_grass",
	"tex5_has_grass", "tex6_has_grass"
]

const TEXTURE_SCALE_PROPERTIES := [
	"texture_scale_1", "texture_scale_2", "texture_scale_3", "texture_scale_4", "texture_scale_5",
	"texture_scale_6", "texture_scale_7", "texture_scale_8", "texture_scale_9", "texture_scale_10",
	"texture_scale_11", "texture_scale_12", "texture_scale_13", "texture_scale_14", "texture_scale_15"
]
#endregion

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

#region on-signal functions

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
		"use_ledge_texture":
			if p_value is bool:
				terrain.use_ledge_texture = p_value
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

	# Texture properties (Texture2D or null)
	if p_setting_name in TEXTURE_PROPERTIES:
		if p_value is Texture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Grass sprite properties (CompressedTexture2D or null)
	elif p_setting_name in GRASS_SPRITE_PROPERTIES:
		if p_value is CompressedTexture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Color properties
	elif p_setting_name in COLOR_PROPERTIES:
		if p_value is Color:
			terrain.set(p_setting_name, p_value)
	# Has grass flags (bool)
	elif p_setting_name in HAS_GRASS_PROPERTIES:
		if p_value is bool:
			terrain.set(p_setting_name, p_value)
	# Texture scale properties (float)
	elif p_setting_name in TEXTURE_SCALE_PROPERTIES:
		if p_value is float or p_value is int:
			terrain.set(p_setting_name, float(p_value))

	terrain.save_to_preset()

#endregion
