@tool
extends Node
class_name MarchingSquaresUI


@onready var TOOLBAR : Script = EngineWrapper.load_resource("uid://3d77dnetkeik") as Script
@onready var TOOL_ATTRIBUTES : Script = EngineWrapper.load_resource("uid://buxevb44hutjm") as Script
@onready var TEXTURE_SETTINGS : Script = EngineWrapper.load_resource("uid://blvx0jk6wxk5p") as Script
@onready var POPULATOR_SETTINGS : Script = EngineWrapper.load_resource("uid://twlshh2i85w1") as Script

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
var toolbar
var tool_attributes
var texture_settings
var populator_settings
var active_tool : int
var visible : bool = false


func _enter_tree() -> void:
	call_deferred("_deferred_enter_tree")


func _deferred_enter_tree() -> void:
	if not EngineWrapper.instance.is_editor():
		push_error("Attempt to load during runtime (NOT SUPPORTED IN CURRENT BUILD)")
		return
	
	if not plugin:
		push_error("Plugin not ready")
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
	if toolbar != null and is_instance_valid(toolbar) and toolbar.has_method("set_visible"):
		toolbar.set_visible(is_visible)
	if tool_attributes != null and is_instance_valid(tool_attributes) and tool_attributes.has_method("set_visible"):
		tool_attributes.set_visible(is_visible)
	if texture_settings != null and is_instance_valid(texture_settings) and texture_settings.has_method("set_visible"):
		texture_settings.set_visible(is_visible)
	if populator_settings != null and is_instance_valid(populator_settings) and populator_settings.has_method("set_visible"):
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
	if plugin.navmesh_paint_mode != MarchingSquaresTerrainPlugin.NavMeshPaintMode.NONE:
		plugin.deactivate_navmesh_paint_mode()
	active_tool = tool_index
	
	texture_settings.hide()
	populator_settings.hide()
	
	if tool_index == 5: # Vertex Painting:
		tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
		texture_settings.show()
		if not texture_settings.has_method("is_built_for_current_terrain") or not texture_settings.is_built_for_current_terrain():
			texture_settings.add_texture_settings()
	elif tool_index == 6: # Populator:
		tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
		populator_settings.show()
		if not populator_settings.has_method("is_built_for_current_terrain") or not populator_settings.is_built_for_current_terrain():
			populator_settings.add_populator_settings()
	
	if tool_index == 3: # Bridge tool:
		plugin.falloff = false
		plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", false)
	
	plugin.active_tool = tool_index
	plugin.mode = tool_index
	
	# Keep the user's selected material; only clamp to a valid range.
	if tool_index == 5:
		plugin.vertex_color_idx = clampi(plugin.vertex_color_idx, 0, plugin.MAX_TEXTURE_SLOTS - 1)
	
	tool_attributes.show_tool_attributes(active_tool)


func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	match p_setting_name:
		"brush_type":
			if p_value is int:
				plugin.current_brush_index = p_value
				plugin.BRUSH_RADIUS_VISUAL = plugin.BrushMode.get(str(p_value))
				var mat := plugin.BrushMat.get(str(p_value))
				plugin.BRUSH_RADIUS_MATERIAL = mat.duplicate(true) if mat != null else null
				if plugin.BRUSH_RADIUS_MATERIAL:
					var visible := plugin.falloff
					if plugin.mode == plugin.TerrainToolMode.VERTEX_PAINTING:
						visible = (plugin.vp_falloff_mode == plugin.VertexPaintFalloffMode.DITHERED)
					plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", visible)
		"vp_falloff_mode":
			if p_value is bool:
				plugin.vp_falloff_mode = plugin.VertexPaintFalloffMode.DITHERED if p_value else plugin.VertexPaintFalloffMode.HARD
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
				if plugin.BRUSH_RADIUS_MATERIAL and plugin.mode !=  plugin.TerrainToolMode.VERTEX_PAINTING:
					plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", p_value)
		"curve3d_mode":
			if p_value is bool:
				plugin.curve3d_mode = p_value
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
		"texture_preset":
			if p_value is MarchingSquaresTexturePreset:
				plugin.current_texture_preset = p_value
			else:
				plugin.current_texture_preset = null
			tool_attributes.show_tool_attributes(active_tool)
			if active_tool == 5 and texture_settings != null:
				texture_settings.add_texture_settings()
		"quick_paint_selection":
					if p_value is MarchingSquaresQuickPaint:
						plugin.current_quick_paint = p_value
					else:
						plugin.current_quick_paint = null
		"paint_walls":
			if p_value is bool:
				plugin.paint_walls_mode = p_value
		"remove_selection":
			if p_value is bool:
				plugin.remove_selection = p_value
		"hm_heightmap_image":
			plugin.hm_heightmap_image = p_value if p_value is Texture2D else null
		"hm_grass_image":
			plugin.hm_grass_image = p_value if p_value is Texture2D else null
		"hm_texture_image":
			plugin.hm_texture_image = p_value if p_value is Texture2D else null
		"hm_chunks_x":
			if p_value is int or p_value is float:
				plugin.hm_chunks_x = int(p_value)
		"hm_chunks_z":
			if p_value is int or p_value is float:
				plugin.hm_chunks_z = int(p_value)
		"hm_max_height":
			if p_value is int or p_value is float:
				plugin.hm_max_height = int(p_value)
		"hm_merge_mode":
			if p_value is int:
				plugin.hm_merge_mode = p_value
		"hm_single_file_import":
			if p_value is bool:
				plugin.hm_single_file_import = p_value
				tool_attributes.show_tool_attributes(active_tool)
		"hm_combined_image":
			if p_value is Texture2D or p_value == null:
				plugin.hm_combined_image = p_value
		"import_heightmap":
			plugin.run_heightmap_import()
		"clear_chunks":
			plugin.run_clear_chunks()
		"hme_export_heightmap":
			if p_value is bool:
				plugin.hme_export_heightmap = p_value
		"hme_export_grass":
			if p_value is bool:
				plugin.hme_export_grass = p_value
		"hme_export_texture_index":
			if p_value is bool:
				plugin.hme_export_texture_index = p_value
		"hme_single_file":
			if p_value is bool:
				plugin.hme_single_file = p_value
				tool_attributes.show_tool_attributes(active_tool)
		"hme_output_path":
			if p_value is String:
				plugin.hme_output_path = p_value
		"selected_heightmap_mesh":
			if p_value is Mesh:
				plugin.current_heightmap_mesh = p_value
		"export_terrain_heightmap":
			plugin.run_heightmap_export()
		"extract_mesh_heightmap":
			plugin.run_heightmap_extraction()


func _apply_preset_to_terrain(preset: MarchingSquaresTexturePreset, terrain: MarchingSquaresTerrain) -> void:
	var t := preset.new_textures
	
	# Terrain textures
	terrain.texture_1  = t.terrain_textures[0]
	terrain.texture_2  = t.terrain_textures[1]
	terrain.texture_3  = t.terrain_textures[2]
	terrain.texture_4  = t.terrain_textures[3]
	terrain.texture_5  = t.terrain_textures[4]
	terrain.texture_6  = t.terrain_textures[5]
	terrain.texture_7  = t.terrain_textures[6]
	terrain.texture_8  = t.terrain_textures[7]
	terrain.texture_9  = t.terrain_textures[8]
	terrain.texture_10 = t.terrain_textures[9]
	terrain.texture_11 = t.terrain_textures[10]
	terrain.texture_12 = t.terrain_textures[11]
	terrain.texture_13 = t.terrain_textures[12]
	terrain.texture_14 = t.terrain_textures[13]
	terrain.texture_15 = t.terrain_textures[14]
	# Texture scales
	terrain.texture_scale_1  = t.texture_scales[0]
	terrain.texture_scale_2  = t.texture_scales[1]
	terrain.texture_scale_3  = t.texture_scales[2]
	terrain.texture_scale_4  = t.texture_scales[3]
	terrain.texture_scale_5  = t.texture_scales[4]
	terrain.texture_scale_6  = t.texture_scales[5]
	terrain.texture_scale_7  = t.texture_scales[6]
	terrain.texture_scale_8  = t.texture_scales[7]
	terrain.texture_scale_9  = t.texture_scales[8]
	terrain.texture_scale_10 = t.texture_scales[9]
	terrain.texture_scale_11 = t.texture_scales[10]
	terrain.texture_scale_12 = t.texture_scales[11]
	terrain.texture_scale_13 = t.texture_scales[12]
	terrain.texture_scale_14 = t.texture_scales[13]
	terrain.texture_scale_15 = t.texture_scales[14]
	# Grass sprites
	terrain.grass_sprite_tex_1 = t.grass_sprites[0]
	terrain.grass_sprite_tex_2 = t.grass_sprites[1]
	terrain.grass_sprite_tex_3 = t.grass_sprites[2]
	terrain.grass_sprite_tex_4 = t.grass_sprites[3]
	terrain.grass_sprite_tex_5 = t.grass_sprites[4]
	terrain.grass_sprite_tex_6 = t.grass_sprites[5]
	# Palette system
	terrain.load_from_preset(preset)
	# Has grass flags
	terrain.tex2_has_grass = t.has_grass[0]
	terrain.tex3_has_grass = t.has_grass[1]
	terrain.tex4_has_grass = t.has_grass[2]
	terrain.tex5_has_grass = t.has_grass[3]
	terrain.tex6_has_grass = t.has_grass[4]


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
		"blend_sharpness":
			if p_value is float or p_value is int:
				terrain.blend_sharpness = float(p_value)
		"floor_blend_mode":
			if p_value is int:
				terrain.floor_blend_mode = p_value
		"blend_noise_threshold":
			if p_value is float or p_value is int:
				terrain.blend_noise_threshold = float(p_value)
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
		"grass_random_scale":
			if p_value is float or p_value is int:
				terrain.grass_random_scale = float(p_value)
		"use_flat_normals":
			if p_value is bool:
				terrain.use_flat_normals = p_value
		"use_cell_shading":
			if p_value is bool:
				terrain.use_cell_shading = p_value
		"ridge_threshold":
			if p_value is float or p_value is int:
				terrain.ridge_threshold = float(p_value)
		"ledge_threshold":
			if p_value is float or p_value is int:
				terrain.ledge_threshold = float(p_value)
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
		"collision_thickness":
			terrain.collision_thickness = float(p_value)
		"nav_agent_radius":
			terrain.nav_agent_radius = float(p_value)
		"nav_max_slope":
			terrain.nav_max_slope = float(p_value)
		"nav_max_step_height":
			terrain.nav_max_step_height = float(p_value)
		"nav_min_region_size":
			terrain.nav_min_region_size = float(p_value)
		"wind_direction_degrees":
			terrain.wind_direction_degrees = float(p_value)
		"wind_speed":
			terrain.wind_speed = float(p_value)
		"wind_tip_color":
			if p_value is Color:
				terrain.wind_tip_color = p_value
		"wind_strength":
			terrain.wind_strength = float(p_value)
		"wind_scale":
			terrain.wind_scale = float(p_value)
		"wind_gust_strength":
			terrain.wind_gust_strength = float(p_value)
		"wind_gust_speed":
			terrain.wind_gust_speed = float(p_value)
		"wind_mode":
			terrain.wind_mode = int(p_value)
		"flower_wind_strength":
			terrain.flower_wind_strength = float(p_value)
		"flower_stem_bend":
			terrain.flower_stem_bend = float(p_value)
		"flower_tip_flutter":
			terrain.flower_tip_flutter = float(p_value)
		"prefab_set":
			if p_value is MarchingSquaresPrefabSet:
				if p_value.has_method("has_required_pieces") and not p_value.has_required_pieces():
					push_warning("This prefab set lacks pieces, the geometry will appear empty or have holes! Make sure to complete the prefab set before assigning it. The previous prefab setup was kept unchanged.")
				else:
					terrain.prefab_set = p_value
			elif p_value == null:
				terrain.prefab_set = null

	# Tool-panel settings are assigned directly to the live node rather than
	# through the Inspector, so explicitly mark the scene dirty. Without this,
	# wind/FPS can appear in the editor but runtime reloads the old defaults.
	if terrain != null and Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	var terrain := plugin.current_terrain_node
	if not terrain:
		push_error("No current terrain node to apply texture settings to")
		return
	
	# Texture properties (Texture2D or null)
	if p_setting_name in TEXTURE_PROPERTIES:
		if p_value is Texture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Grass sprite properties (CompressedTexture2D or null)
	elif p_setting_name in GRASS_SPRITE_PROPERTIES:
		if p_value is CompressedTexture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Has grass flags (bool)
	elif p_setting_name in HAS_GRASS_PROPERTIES:
		if p_value is bool:
			terrain.set(p_setting_name, p_value)
	# Texture scale properties (float)
	elif p_setting_name in TEXTURE_SCALE_PROPERTIES:
		if p_value is float or p_value is int:
			terrain.set(p_setting_name, float(p_value))
	
	if terrain.current_texture_preset !=  null and not terrain.current_texture_preset.resource_path.is_empty():
		terrain.save_to_preset()

#endregion
