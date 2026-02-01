@tool
extends Node3D
class_name MarchingSquaresTerrain


enum StorageMode { RUNTIME, BAKED }


## Custom data directory path (leave empty for auto scene-relative path)
## Format when empty: [SceneDir]/[SceneName]_TerrainData/[NodeName]_[UID]/
@export var data_directory : String = "":
	set(value):
		data_directory = value

## The storage mode for terrain data. 
## RUNTIME: Rebuilds mesh/collision from source data on load (Smallest files, higher load time)
## BAKED: Saves and loads pre-built mesh/collision assets (Larger files, instant load)
@export var storage_mode : StorageMode = StorageMode.RUNTIME

## Unique identifier for this terrain instance (auto-generated on first save)
## Prevents path collisions when nodes are recreated with same name
@export_storage var _terrain_uid : String = ""

## True after external storage has been initialized
## Used to detect when migration from embedded data is needed
@export_storage var _storage_initialized : bool = false

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2, 2): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var blend_mode : int = 0:
	set(value):
		blend_mode = value
		if value == 1 or value == 2:
			terrain_material.set_shader_parameter("use_hard_textures", true)
		else:
			terrain_material.set_shader_parameter("use_hard_textures", false)
		terrain_material.set_shader_parameter("blend_mode", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells()
@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int = 9:
	set(value):
		extra_collision_layer = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines on what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise # used to generate smooth initial heights for more natrual looking terrain. if null, initial terrain will be flat
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_texture : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		ground_texture = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if ground_texture:
				grass_mat.set_shader_parameter("use_base_color", false)
			else:
				grass_mat.set_shader_parameter("use_base_color", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color : Color = Color("647851ff"):
	set(value):
		ground_color = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_base_color", value)

# Base grass settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var animation_fps : int = 0:
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("fps", clamp(value, 0, 30))
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_subdivisions := 3:
	set(value):
		grass_subdivisions = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size := Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.mesh.size = value
			chunk.grass_planter.multimesh.mesh.center_offset.y = value.y / 2
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold: float = 1.0:
	set(value):
		ridge_threshold = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold: float = 0.25:
	set(value):
		ledge_threshold = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture: bool = false:
	set(value):
		use_ridge_texture = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells()

# Vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_2:
				grass_mat.set_shader_parameter("use_base_color_2", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_2", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rb", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_3:
				grass_mat.set_shader_parameter("use_base_color_3", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_3", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ra", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_4:
				grass_mat.set_shader_parameter("use_base_color_4", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_4", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_5:
				grass_mat.set_shader_parameter("use_base_color_5", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_5", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_6:
				grass_mat.set_shader_parameter("use_base_color_6", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_6", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ga", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_br", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bg", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ba", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ar", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ag", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ab", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_2 : Color = Color("527b62ff"):
	set(value):
		ground_color_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_2", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_3 : Color = Color("5f6c4bff"):
	set(value):
		ground_color_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_3", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_4 : Color = Color("647941ff"):
	set(value):
		ground_color_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_4", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_5 : Color = Color("4a7e5dff"):
	set(value):
		ground_color_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_5", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_6 : Color = Color("71725dff"):
	set(value):
		ground_color_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_6", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_6", value)

# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_7", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_8", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_9", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_10", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_11", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_12", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_13", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_14", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_15", value)

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int = 5

var void_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/void_texture.tres")
var placeholder_wind_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wind_noise_texture.tres") # Change to your own texture

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null 

var is_batch_updating : bool = false

var chunks : Dictionary = {}


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/mst_terrain_shader.tres").duplicate(true)
	var base_grass_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/mst_grass_mesh.tres")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)


func _notification(what: int) -> void:
	# Save all dirty chunks to external storage before scene save
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if Engine.is_editor_hint():
			MSTDataHandler.save_all_chunks(self)


func _enter_tree() -> void:
	call_deferred("_deferred_enter_tree")


func _deferred_enter_tree() -> void:
	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	force_batch_update()

	# Populate chunks dictionary from scene children
	chunks.clear()
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			chunks[chunk.chunk_coords] = chunk
			chunk.terrain_system = self
			chunk.grass_planter = null

	# Load external data if storage was previously initialized
	if _storage_initialized:
		MSTDataHandler.load_terrain_data(self)
	elif Engine.is_editor_hint() and MSTDataHandler.needs_migration(self):
		# Auto-migrate embedded data to external storage (editor only)
		MSTDataHandler.migrate_to_external_storage(self)

	# Initialize all chunks (regenerate mesh/grass from loaded data)
	for chunk in chunks.values():
		chunk.initialize_terrain(true)


func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


func add_new_chunk(chunk_x: int, chunk_z: int):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := MarchingSquaresTerrainChunk.new()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.terrain_system = self
	add_chunk(chunk_coords, new_chunk, false)
	
	var chunk_left: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left:
		for z in range(0, dimensions.z):
			new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right:
		for z in range(0, dimensions.z):
			chunk_right.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up:
		for x in range(0, dimensions.x):
			new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down:
		for x in range(0, dimensions.x):
			new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]
	
	new_chunk.regenerate_mesh()


func remove_chunk(x: int, z: int):
	var chunk_coords := Vector2i(x, z)
	var chunk: MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk.free()


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int):
	var chunk_coords := Vector2i(x, z)
	var chunk: MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunk, regenerate_mesh: bool = true):
	chunks[coords] = chunk
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	
	add_child(chunk)
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors
	# when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	chunk.position = Vector3(
		coords.x * ((dimensions.x - 1) * cell_size.x),
		0,
		coords.y * ((dimensions.z - 1) * cell_size.y)
	)
	
	if Engine.is_editor_hint():
		var editor_interface = Engine.get_singleton('EditorInterface')
		_set_owner_recursive(chunk, editor_interface.get_edited_scene_root())
	else:
		_set_owner_recursive(chunk, get_tree().root)
	chunk.initialize_terrain(regenerate_mesh)
	print_verbose("Added new chunk to terrain system at ", chunk)


func _set_owner_recursive(node: Node, _owner: Node) -> void:
	node.owner = _owner
	for c in node.get_children():
		_set_owner_recursive(c, _owner)


# This function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	if not grass_mat.get_shader_parameter("use_base_color") and terrain_material.get_shader_parameter("vc_tex_rr") == null:
		terrain_material.set_shader_parameter("vc_tex_rr", ground_texture)
	if grass_mat.get_shader_parameter("use_grass_tex_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if grass_mat.get_shader_parameter("use_grass_tex_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if grass_mat.get_shader_parameter("use_grass_tex_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if grass_mat.get_shader_parameter("use_grass_tex_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if grass_mat.get_shader_parameter("use_grass_tex_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	if grass_mat.get_shader_parameter("wind_texture") == null:
		grass_mat.set_shader_parameter("wind_texture", placeholder_wind_texture)
	if grass_sprite and grass_mat.get_shader_parameter("grass_texture") == null:
		grass_mat.set_shader_parameter("grass_texture", grass_sprite)
	if grass_sprite_tex_2 and grass_mat.get_shader_parameter("grass_texture_2") == null:
		grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	if grass_sprite_tex_3 and grass_mat.get_shader_parameter("grass_texture_3") == null:
		grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	if grass_sprite_tex_4 and grass_mat.get_shader_parameter("grass_texture_4") == null:
		grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	if grass_sprite_tex_5 and grass_mat.get_shader_parameter("grass_texture_5") == null:
		grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	if grass_sprite_tex_6 and grass_mat.get_shader_parameter("grass_texture_6") == null:
		grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	if terrain_material.get_shader_parameter("vc_tex_aa") == null:
		terrain_material.set_shader_parameter("vc_tex_aa", void_texture)


# Applies all shader parameters and regenerates grass once
# Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Ground TExtures
	terrain_material.set_shader_parameter("vc_tex_rr", ground_texture)
	terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	terrain_material.set_shader_parameter("vc_tex_gb", texture_7)
	terrain_material.set_shader_parameter("vc_tex_ga", texture_8)
	terrain_material.set_shader_parameter("vc_tex_br", texture_9)
	terrain_material.set_shader_parameter("vc_tex_bg", texture_10)
	terrain_material.set_shader_parameter("vc_tex_bb", texture_11)
	terrain_material.set_shader_parameter("vc_tex_ba", texture_12)
	terrain_material.set_shader_parameter("vc_tex_ar", texture_13)
	terrain_material.set_shader_parameter("vc_tex_ag", texture_14)
	terrain_material.set_shader_parameter("vc_tex_ab", texture_15)

	# TERRAIN MATERIAL - Ground Colors (used for both floor and wall in unified system)
	terrain_material.set_shader_parameter("ground_albedo", ground_color)
	terrain_material.set_shader_parameter("ground_albedo_2", ground_color_2)
	terrain_material.set_shader_parameter("ground_albedo_3", ground_color_3)
	terrain_material.set_shader_parameter("ground_albedo_4", ground_color_4)
	terrain_material.set_shader_parameter("ground_albedo_5", ground_color_5)
	terrain_material.set_shader_parameter("ground_albedo_6", ground_color_6)

	# TERRAIN MATERIAL - Per-Texture UV Scales
	terrain_material.set_shader_parameter("texture_scale_1", texture_scale_1)
	terrain_material.set_shader_parameter("texture_scale_2", texture_scale_2)
	terrain_material.set_shader_parameter("texture_scale_3", texture_scale_3)
	terrain_material.set_shader_parameter("texture_scale_4", texture_scale_4)
	terrain_material.set_shader_parameter("texture_scale_5", texture_scale_5)
	terrain_material.set_shader_parameter("texture_scale_6", texture_scale_6)
	terrain_material.set_shader_parameter("texture_scale_7", texture_scale_7)
	terrain_material.set_shader_parameter("texture_scale_8", texture_scale_8)
	terrain_material.set_shader_parameter("texture_scale_9", texture_scale_9)
	terrain_material.set_shader_parameter("texture_scale_10", texture_scale_10)
	terrain_material.set_shader_parameter("texture_scale_11", texture_scale_11)
	terrain_material.set_shader_parameter("texture_scale_12", texture_scale_12)
	terrain_material.set_shader_parameter("texture_scale_13", texture_scale_13)
	terrain_material.set_shader_parameter("texture_scale_14", texture_scale_14)
	terrain_material.set_shader_parameter("texture_scale_15", texture_scale_15)
	
	# GRASS MATERIAL - Grass Textures 
	grass_mat.set_shader_parameter("grass_texture", grass_sprite)
	grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	# GRASS MATERIAL - Grass Colors 
	grass_mat.set_shader_parameter("grass_base_color", ground_color)
	grass_mat.set_shader_parameter("grass_color_2", ground_color_2)
	grass_mat.set_shader_parameter("grass_color_3", ground_color_3)
	grass_mat.set_shader_parameter("grass_color_4", ground_color_4)
	grass_mat.set_shader_parameter("grass_color_5", ground_color_5)
	grass_mat.set_shader_parameter("grass_color_6", ground_color_6)
	
	# GRASS MATERIAL - Use Base Color Flags 
	grass_mat.set_shader_parameter("use_base_color", ground_texture == null)
	grass_mat.set_shader_parameter("use_base_color_2", texture_2 == null)
	grass_mat.set_shader_parameter("use_base_color_3", texture_3 == null)
	grass_mat.set_shader_parameter("use_base_color_4", texture_4 == null)
	grass_mat.set_shader_parameter("use_base_color_5", texture_5 == null)
	grass_mat.set_shader_parameter("use_base_color_6", texture_6 == null)
	
	# GRASS MATERIAL - Has Grass Flags 
	grass_mat.set_shader_parameter("use_grass_tex_2", tex2_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_3", tex3_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_4", tex4_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_5", tex5_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_6", tex6_has_grass)
	
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		chunk.grass_planter.regenerate_all_cells()


# Syncs and saves current UI texture values to the given preset resource
# Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null:
		# Don't print an error here as not having a preset just means the user is making a new one
		return
	
	# Terrain textures
	current_texture_preset.new_textures.terrain_textures[0] = ground_texture
	current_texture_preset.new_textures.terrain_textures[1] = texture_2
	current_texture_preset.new_textures.terrain_textures[2] = texture_3
	current_texture_preset.new_textures.terrain_textures[3] = texture_4
	current_texture_preset.new_textures.terrain_textures[4] = texture_5
	current_texture_preset.new_textures.terrain_textures[5] = texture_6
	current_texture_preset.new_textures.terrain_textures[6] = texture_7
	current_texture_preset.new_textures.terrain_textures[7] = texture_8
	current_texture_preset.new_textures.terrain_textures[8] = texture_9
	current_texture_preset.new_textures.terrain_textures[9] = texture_10
	current_texture_preset.new_textures.terrain_textures[10] = texture_11
	current_texture_preset.new_textures.terrain_textures[11] = texture_12
	current_texture_preset.new_textures.terrain_textures[12] = texture_13
	current_texture_preset.new_textures.terrain_textures[13] = texture_14
	current_texture_preset.new_textures.terrain_textures[14] = texture_15
	
	# Texture scales
	current_texture_preset.new_textures.texture_scales[0] = texture_scale_1
	current_texture_preset.new_textures.texture_scales[1] = texture_scale_2
	current_texture_preset.new_textures.texture_scales[2] = texture_scale_3
	current_texture_preset.new_textures.texture_scales[3] = texture_scale_4
	current_texture_preset.new_textures.texture_scales[4] = texture_scale_5
	current_texture_preset.new_textures.texture_scales[5] = texture_scale_6
	current_texture_preset.new_textures.texture_scales[6] = texture_scale_7
	current_texture_preset.new_textures.texture_scales[7] = texture_scale_8
	current_texture_preset.new_textures.texture_scales[8] = texture_scale_9
	current_texture_preset.new_textures.texture_scales[9] = texture_scale_10
	current_texture_preset.new_textures.texture_scales[10] = texture_scale_11
	current_texture_preset.new_textures.texture_scales[11] = texture_scale_12
	current_texture_preset.new_textures.texture_scales[12] = texture_scale_13
	current_texture_preset.new_textures.texture_scales[13] = texture_scale_14
	current_texture_preset.new_textures.texture_scales[14] = texture_scale_15
	
	# Grass sprites
	current_texture_preset.new_textures.grass_sprites[0] = grass_sprite
	current_texture_preset.new_textures.grass_sprites[1] = grass_sprite_tex_2
	current_texture_preset.new_textures.grass_sprites[2] = grass_sprite_tex_3
	current_texture_preset.new_textures.grass_sprites[3] = grass_sprite_tex_4
	current_texture_preset.new_textures.grass_sprites[4] = grass_sprite_tex_5
	current_texture_preset.new_textures.grass_sprites[5] = grass_sprite_tex_6
	
	# Grass colors
	current_texture_preset.new_textures.grass_colors[0] = ground_color
	current_texture_preset.new_textures.grass_colors[1] = ground_color_2
	current_texture_preset.new_textures.grass_colors[2] = ground_color_3
	current_texture_preset.new_textures.grass_colors[3] = ground_color_4
	current_texture_preset.new_textures.grass_colors[4] = ground_color_5
	current_texture_preset.new_textures.grass_colors[5] = ground_color_6
	
	# Has grass flags
	current_texture_preset.new_textures.has_grass[0] = tex2_has_grass
	current_texture_preset.new_textures.has_grass[1] = tex3_has_grass
	current_texture_preset.new_textures.has_grass[2] = tex4_has_grass
	current_texture_preset.new_textures.has_grass[3] = tex5_has_grass
	current_texture_preset.new_textures.has_grass[4] = tex6_has_grass
