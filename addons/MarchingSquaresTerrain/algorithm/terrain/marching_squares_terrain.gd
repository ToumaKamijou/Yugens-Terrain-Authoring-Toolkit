@tool
extends Node3D
class_name MarchingSquaresTerrain

const MSTVertexColorHelper := preload("uid://xpss2m323r5l")
const MarchingSquaresTerrainHelpers := preload("uid://b33pjajd0cl83")
const MSTMaterialControllerScript := preload("uid://n4nhvdllgv3l")
const MSTCollisionControllerScript := preload("uid://yh3m1d5hor3k")
const MSTNavMeshControllerScript := preload("uid://d34l577jn5vnn")
const MSTPostProcessControllerScript := preload("uid://b2q8tk4axi713")
const MSTTerrainLodControllerScript := preload("uid://bxbpf5pn7x4nr")
const MSTNavMeshScript := preload("uid://iyh3il0mdthx")
const DEFAULT_TEXTURE_PRESET_PATH := "res://addons/MarchingSquaresTerrain/resources/empty_project.tres"
var _material_controller := MSTMaterialControllerScript.new(self)
var _collision_controller := MSTCollisionControllerScript.new(self)
var _nav_controller := MSTNavMeshControllerScript.new(self)
var _post_process_controller := MSTPostProcessControllerScript.new(self)
var _lod_controller := MSTTerrainLodControllerScript.new(self)

# Uses global class_name MSTDataHandler (static utility).

signal chunk_dimensions_changed(value: Vector3i)

enum StorageMode {
	## Saves load time. Loads a pre-built visual mesh from disk.
	## The collision mesh, grass etc. are generated when the scene loads.
	## (faster load, slightly larger files).
	BAKED,
	## Saves disk space. Generates everything from heightmaps when the scene loads.
	## This is overkill for most games.
	## (slower load, smallest files).
	RUNTIME,
}

enum CollisionMode {
	SIMPLIFIED_PROXY,
}

@export_category("Storage Options")
## The storage mode for terrain data.
@export_storage var _storage_mode_internal : StorageMode = StorageMode.BAKED
@export var storage_mode : StorageMode:
	get():
		return _storage_mode_internal
	set(value):
		_set_storage_mode_internal(value)
@export_tool_button("Repair Chunk Storage") var repair_chunk_storage_button = func():
	_repair_chunk_storage()


func _set_storage_mode_internal(value: StorageMode) -> void:
	if _storage_mode_internal != value:
		_storage_mode_internal = value
		if chunks:
			for chunk in chunks.values():
				chunk.mark_dirty()
		print_verbose("[MST] Storage mode changed. All chunks marked for save.")
	notify_property_list_changed()


## If true, storage will include grass data, ignored if storage_mode = RUNTIME
var _bake_grass : bool = true
@export var bake_grass : bool = true:
	get():
		return _bake_grass
	set(value):
		_bake_grass = value
		for chunk in chunks.values():
			chunk.mark_dirty()

## If true, storage will include collision data, ignored if storage_mode = RUNTIME
var _bake_collision : bool = true
@export var bake_collision : bool = true:
	get():
		return _bake_collision
	set(value):
		_bake_collision = value
		for chunk in chunks.values():
			chunk.mark_dirty()

@export_storage var collision_mode : CollisionMode = CollisionMode.SIMPLIFIED_PROXY

## The folder where this terrain's data is saved.
## If left empty, it automatically fills with a folder name relative to your scene file.
## Note: Manually setting a path locks the save location even if you rename the terrain node later.
var _collision_thickness : float = 0.0
@export_range(0.0, 8.0, 0.05) var collision_thickness : float:
	get:
		return _collision_thickness
	set(value):
		_collision_thickness = clampf(float(value), 0.0, 8.0)
		_schedule_collision_refresh()

var _data_directory : String = ""
@export_dir var data_directory : String = "":
	get():
		if EngineWrapper.instance.is_editor() and _data_directory.is_empty():
			var auto_path := MSTDataHandler.generate_data_directory(self)
			if not auto_path.is_empty():
				_data_directory = auto_path
		return _data_directory
	set(value):
		_data_directory = value

@export_category("Performance")
## Number of worker threads used when generating terrain cells concurrently.
@export_range(1, 8, 1) var terrain_generation_threads: int = 4
## Main-thread time budget used while publishing deferred mesh tiles.
## Keeping this small prevents large batch builds from freezing the editor.
@export_range(1.0, 33.0, 1.0, "suffix: ms") var initial_mesh_tile_budget_msec: float = 8.0

@export_category("Texture Arrays")
# ---------------- Texture2DArray baking / library ----------------
## Optional texture library resource that stores the terrain's albedo, normal, and grass textures in one shared asset.
## Leave this assigned if you want texture edits and baked texture-array output to persist cleanly across sessions.
@export var texture_library : Resource
@export_storage var baked_albedo_array_path : String = ""
@export_storage var baked_normal_array_path : String = ""
@export_storage var baked_grass_array_path : String = ""
@export_storage var baked_dense_slot_lookup: PackedInt32Array = PackedInt32Array()
## Texture size used for live editor preview arrays when no baked array is loaded.
## Lower values keep inspector edits responsive and explain the intentionally softer editor preview.
@export_range(32, 2048, 1) var editor_preview_texture_size : int = 128
## Texture size used when saving Texture2DArray resources for runtime/export.
@export_range(32, 4096, 1) var runtime_baked_texture_size : int = 512
## Legacy name kept for older scenes/presets. Use runtime_baked_texture_size for new bakes.
@export_storage var baked_texture_size : int = 512
## Separate bake size for grass atlases.
## Lower values save memory and load faster, while higher values keep individual grass textures sharper.
@export var baked_grass_texture_size : int = 64

## The resolution used per polygon by the legacy runtime geometry baker.
## TextureArray workflows usually do not need this unless Legacy Runtime Baking is enabled.
@export var polygon_texture_resolution : int = 32

## Used for overriding the material of the legacy baked terrain texture.
@export var bake_material_override : Material

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var prefab_set : MarchingSquaresPrefabSet:
	set(value):
		if value != null and value.has_method("has_required_pieces") and not value.has_required_pieces():
			push_warning("This prefab set lacks pieces, the geometry will appear empty or have holes! Make sure to complete the prefab set before assigning it. The previous prefab setup was kept unchanged.")
			return
		prefab_set = value
		_sync_prefab_material_state()
		refresh_chunk_surface_materials()
		if not is_inside_tree():
			return
		if not is_batch_updating:
			rebuild_grass_texture_array()
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if is_instance_valid(chunk):
				chunk.mark_dirty()
				# Prefab swaps invalidate every cell of the chunk, cache need to be invalidated fully
				chunk.queue_full_mesh_regen(true)
		if not is_batch_updating:
			_request_grass_regen()

@export_group("Visibility & Detail")
## Enables renderer-level distance culling without removing terrain nodes or collision.
@export var visibility_detail_enabled : bool = false:
	set(value):
		visibility_detail_enabled = value
		_visibility_detail_settings_dirty = true
## Maximum draw distance for authored terrain chunks. Zero disables terrain culling.
@export_range(0.0, 10000.0, 1.0) var chunk_visibility_end_distance : float = 0.0:
	set(value):
		chunk_visibility_end_distance = maxf(float(value), 0.0)
		_visibility_detail_settings_dirty = true
## Maximum draw distance for grass. Zero disables grass-specific culling.
@export_range(0.0, 10000.0, 1.0) var grass_visibility_end_distance : float = 0.0:
	set(value):
		grass_visibility_end_distance = maxf(float(value), 0.0)
		_visibility_detail_settings_dirty = true
## Maximum draw distance for flower-populator instances. Zero disables flower culling.
@export_range(0.0, 10000.0, 1.0) var flower_visibility_end_distance : float = 0.0:
	set(value):
		flower_visibility_end_distance = maxf(float(value), 0.0)
		_visibility_detail_settings_dirty = true
## Extra distance margin used to reduce visibility-range popping.
@export_range(0.0, 1000.0, 1.0) var visibility_range_margin : float = 0.0:
	set(value):
		visibility_range_margin = maxf(float(value), 0.0)
		_visibility_detail_settings_dirty = true
@export_tool_button("Apply Visibility Settings") var apply_visibility_settings_button = func():
	_apply_visibility_detail_settings()
## Builds a renderer-only reduced terrain proxy for distant views.
@export var terrain_lod_enabled : bool = false:
	set(value):
		terrain_lod_enabled = value
		_visibility_detail_settings_dirty = true
## Distance where the full authored chunk hands off to its reduced proxy.
@export_range(1.0, 10000.0, 1.0) var terrain_lod_start_distance : float = 128.0:
	set(value):
		terrain_lod_start_distance = maxf(float(value), 1.0)
		_visibility_detail_settings_dirty = true
## Distance where the reduced proxy is culled.
@export_range(2.0, 20000.0, 1.0) var terrain_lod_end_distance : float = 512.0:
	set(value):
		terrain_lod_end_distance = maxf(float(value), terrain_lod_start_distance + 1.0)
		_visibility_detail_settings_dirty = true
## Sampling stride for the reduced proxy. Higher values use fewer vertices.
@export_range(2, 16, 1) var terrain_lod_step : int = 2:
	set(value):
		terrain_lod_step = clampi(int(value), 2, 16)
		_visibility_detail_settings_dirty = true
@export_tool_button("Rebuild Terrain LOD Proxies") var rebuild_terrain_lod_button = func():
	if _lod_controller != null:
		_lod_controller.clear()
	_apply_visibility_detail_settings()

@export_group("Legacy Runtime Baking")
## Legacy fallback: bakes generated geometry into per-polygon texture atlases at runtime.
## Not needed for the Texture Library / Texture2DArray workflow.
@export var enable_runtime_texture_baking : bool = false
@export_group("")

## True after external storage has been initialized.
## Used to detect when migration from embedded data is needed.
@export_storage var _storage_initialized : bool = false
## True after the editor has auto-created or assigned the texture library once.
@export_storage var _auto_quick_setup_done : bool = false

## Tracks the mode used during the last successful save for reporting purposes.
@export_storage var _last_storage_mode : StorageMode = StorageMode.BAKED
@export_storage var _warned_storage_mode_message : bool = false
@export_storage var _warned_data_directory_message : bool = false
@export_storage var _warned_embedded_chunk_migration : bool = false

## One-time mesh migration flag: walls are now tagged via UV sentinel so shaders reliably detect walls.
## Existing chunks need a one-time regen to pick up the new UV values.
@export_storage var _uv_wall_sentinel_migrated : bool = false

## One-time mesh migration flag (v2): ensures wall UV sentinel uses UV=(2,2) to match shader detection.
@export_storage var _uv_wall_sentinel_v2_migrated : bool = false

## One-time mesh migration flag: wall vertices now compute their dominant materials from wall maps.
## Existing chunks need a one-time regen to pick up corrected wall material indices.
@export_storage var _wall_material_pair_migrated : bool = false

## One-time data migration flag: older chunks may have wall maps defaulted to Texture 1.
## We retarget these unpainted/legacy-initialized wall slots to default_wall_texture.
@export_storage var _default_wall_texture_migrated : bool = false
@export_storage var _slot_blend_mode_defaults_migrated : bool = false

#region global terrain settings
# Terrain Settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
		if EngineWrapper.instance.is_editor():
			emit_signal("chunk_dimensions_changed", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2.0, 2.0): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
		grass_size = grass_size

#region blend options
@export_custom(PROPERTY_HINT_RANGE, "0, 0", PROPERTY_USAGE_STORAGE) var blend_mode : int = 0:
	set(value):
		blend_mode = 0
		terrain_material.set_shader_parameter("use_hard_textures", false)
		terrain_material.set_shader_parameter("blend_mode", 0)
		if not is_inside_tree():
			return
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var blend_sharpness : float = 0.5:
	set(value):
		var normalized := float(value)
		# Normalize older scene values that still used the legacy 0..10 range.
		if normalized > 1.0:
			normalized /= 10.0
		blend_sharpness = clampf(normalized, 0.0, 1.0)
		terrain_material.set_shader_parameter("blend_sharpness", blend_sharpness)
		if not is_inside_tree():
			return
		refresh_chunk_surface_materials()

@export_storage var floor_blend_mode : int = 0:
	set(value):
		floor_blend_mode = clampi(int(value), 0, 1)
		if terrain_material != null:
			terrain_material.set_shader_parameter("floor_blend_mode", floor_blend_mode)
			refresh_chunk_surface_materials()
		if is_inside_tree():
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.regenerate_all_cells(true)
			# Grass follows noisy island selection; rebuild when mode changes.
			regenerate_all_chunk_grass(true)

@export_storage var blend_noise_threshold : float = 0.5:
	set(value):
		blend_noise_threshold = clampf(float(value), 0.0, 1.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("blend_noise_threshold", blend_noise_threshold)
			refresh_chunk_surface_materials()
		# Grass placement mirrors noisy islands; rebuild when the threshold moves.
		if is_inside_tree() and floor_blend_mode == 1:
			regenerate_all_chunk_grass(true)

# Texture boundary waviness (blend noise). This controls ONLY the blend jitter/waves.
# Palette color distribution stays stable regardless.
@export_storage var blend_noise_enabled : bool = false:
	set(value):
		blend_noise_enabled = false
		if is_batch_updating:
			return
		_apply_blend_noise_settings()

# Saved "on" strength so the toggle can restore your previous value.
@export_storage var _blend_noise_strength_saved : float = 0.2


func _apply_blend_noise_settings() -> void:
	if terrain_material == null:
		return
	var current := terrain_material.get_shader_parameter("blend_noise_strength")
	if current != null:
		var cs := float(current)
		if cs > 0.0:
			_blend_noise_strength_saved = cs
	terrain_material.set_shader_parameter("blend_noise_strength", 0.0)
#endregion

#region environment + vertex settings
@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int = 9:
	set(value):
		extra_collision_layer = value
		if not is_inside_tree():
			return
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_cell_shading : bool = true:
	set(value):
		use_cell_shading = value
		if terrain_material != null:
			terrain_material.set_shader_parameter("use_cell_shading", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		if grass_mat != null:
			grass_mat.set_shader_parameter("use_cell_shading", value)
		if not is_inside_tree():
			return
		refresh_chunk_surface_materials()

# Backwards/forwards compat: scenes/presets may reference either "use_flat_normals" (shader) or legacy "flat_normals".
# Default is false (smooth normals).
var _use_flat_normals : bool = false
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_flat_normals : bool = false:
	get():
		return _use_flat_normals
	set(value):
		_apply_flat_normals(bool(value))
var flat_normals : bool = false:
	get():
		return _use_flat_normals
	set(value):
		_apply_flat_normals(bool(value))

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		if not is_inside_tree():
			return
		regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold : float = 1.0:
	set(value):
		ridge_threshold = clampf(float(value), 0.0, 1.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("ridge_threshold", ridge_threshold)
		refresh_chunk_surface_materials()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold : float = 1.0:
	set(value):
		ledge_threshold = clampf(float(value), 0.0, 1.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("ledge_threshold", ledge_threshold)
		refresh_chunk_surface_materials()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture : bool = true:
	set(value):
		use_ridge_texture = value
		if terrain_material != null:
			terrain_material.set_shader_parameter("use_ridge_texture", value)
		refresh_chunk_surface_materials()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ledge_texture : bool = true:
	set(value):
		use_ledge_texture = value
		if terrain_material != null:
			terrain_material.set_shader_parameter("use_ledge_texture", value)
		refresh_chunk_surface_materials()
#endregion

#region global noise settings
# Convenience: texture used by the shader's global noise multiplier.
# Defaults to the same noise used for ridge/ledge so porting feels consistent.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var global_noise_texture : Texture2D = preload("uid://dbnc04k3n0sro"):
	set(value):
		global_noise_texture = value
		if terrain_material != null:
			terrain_material.set_shader_parameter("global_noise_texture", value)
		refresh_chunk_surface_materials()
		_sync_global_noise_to_grass()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var global_noise_strength : float = 1.0:
	set(value):
		global_noise_strength = clampf(float(value), 0.0, 1.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
		refresh_chunk_surface_materials()
		_sync_global_noise_to_grass()

@export_custom(PROPERTY_HINT_RANGE, "0.001, 1.0, 0.001", PROPERTY_USAGE_STORAGE) var global_noise_scale : float = 0.037:
	set(value):
		global_noise_scale = clampf(float(value), 0.001, 1.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
		refresh_chunk_surface_materials()
		_sync_global_noise_to_grass()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 10.0, 0.1", PROPERTY_USAGE_STORAGE) var global_noise_scroll : float = 0.0:
	set(value):
		global_noise_scroll = clampf(float(value), 0.0, 10.0)
		if terrain_material != null:
			terrain_material.set_shader_parameter("global_noise_scroll", global_noise_scroll)
		refresh_chunk_surface_materials()
		_sync_global_noise_to_grass()
#endregion

#region wind settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wind_noise_texture : Texture2D = preload("uid://dk1t5hy2tiil7"):
	set(value):
		wind_noise_texture = value
		_sync_wind_state()

var _is_syncing_wind_state := false

@export_custom(PROPERTY_HINT_RANGE, "0.0, 360.0, 0.1", PROPERTY_USAGE_STORAGE) var wind_direction_degrees : float = 45.0:
	set(value):
		wind_direction_degrees = wrapf(float(value), 0.0, 360.0)
		if _is_syncing_wind_state:
			return
		_is_syncing_wind_state = true
		wind_direction = _material_controller.direction_vector_from_degrees(wind_direction_degrees)
		_is_syncing_wind_state = false
		_sync_wind_state()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wind_direction : Vector2 = Vector2(0.70710677, 0.70710677):
	set(value):
		var dir := value
		if dir.length_squared() <= 0.000001:
			dir = _material_controller.direction_vector_from_degrees(wind_direction_degrees)
		wind_direction = dir.normalized()
		if _is_syncing_wind_state:
			return
		_is_syncing_wind_state = true
		wind_direction_degrees = _material_controller.direction_degrees_from_vector(wind_direction)
		_is_syncing_wind_state = false
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_speed : float = 0.08:
	set(value):
		wind_speed = clampf(float(value), 0.0, 1.0)
		_sync_wind_state()

@export var wind_tip_color : Color = Color(1.0, 1.0, 1.0, 0.0):
	set(value):
		wind_tip_color = value
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 2.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_strength : float = 1.0:
	set(value):
		wind_strength = clampf(float(value), 0.0, 2.0)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.005, 1.0, 0.005", PROPERTY_USAGE_STORAGE) var wind_scale : float = 0.037:
	set(value):
		wind_scale = clampf(float(value), 0.005, 1.0)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 2.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_gust_strength : float = 0.35:
	set(value):
		wind_gust_strength = clampf(float(value), 0.0, 2.0)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_gust_speed : float = 0.12:
	set(value):
		wind_gust_speed = clampf(float(value), 0.0, 1.0)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_ENUM, "Smooth,Gusty,Turbulent", PROPERTY_USAGE_STORAGE) var wind_mode : int = 0:
	set(value):
		wind_mode = clampi(int(value), 0, 2)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 2.0, 0.01", PROPERTY_USAGE_STORAGE) var flower_wind_strength : float = 1.0:
	set(value):
		flower_wind_strength = clampf(float(value), 0.0, 2.0)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "1.0, 2.5, 0.01", PROPERTY_USAGE_STORAGE) var flower_stem_bend : float = 1.35:
	set(value):
		flower_stem_bend = clampf(float(value), 1.0, 2.5)
		_sync_wind_state()

@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var flower_tip_flutter : float = 0.2:
	set(value):
		flower_tip_flutter = clampf(float(value), 0.0, 1.0)
		_sync_wind_state()
#endregion

#region grass-environment settings
## Used to generate smooth initial heights for more natural-looking terrain.
## If null, initial terrain will be flat.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise

@export_custom(PROPERTY_HINT_RANGE, "0, 30", PROPERTY_USAGE_STORAGE) var animation_fps : int = 0: # Also applies to flowers from the FlowerPlanter
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat: ShaderMaterial = null
		if grass_mesh != null:
			grass_mat = grass_mesh.material as ShaderMaterial
		if grass_mat != null:
			grass_mat.set_shader_parameter("fps", animation_fps)
			grass_mat.set_shader_parameter("animate_active", true)
		_material_controller.sync_flower_wind_materials()
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var grass_random_scale : float = 0.0:
	set(value):
		grass_random_scale = clampf(float(value), 0.0, 1.0)
		if not _grass_random_scale_apply_queued:
			_grass_random_scale_apply_queued = true
			call_deferred("_apply_grass_random_scale")
@export_custom(PROPERTY_HINT_RANGE, "0, 4", PROPERTY_USAGE_STORAGE) var grass_subdivisions := 3:
	set(value):
		grass_subdivisions = value
		if not is_inside_tree():
			return
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if not chunk.grass_planter or not chunk.grass_planter.multimesh:
				continue
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		var scale_factor := (cell_size.x + cell_size.y) / 4.0
		var scaled_value := value * scale_factor
		
		# Update the shared grass mesh first (safe even before chunks initialize).
		if grass_mesh:
			grass_mesh.size = scaled_value
			grass_mesh.center_offset.y = scaled_value.y / 2.0
		
		# Chunks may not have created GrassPlanter/Multimesh yet during early startup.
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if not chunk or not chunk.grass_planter or not chunk.grass_planter.multimesh or not chunk.grass_planter.multimesh.mesh:
				continue
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0
#endregion

#region vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_1 : Texture2D = null:
	set(value):
		texture_1 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(0, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = null:
	set(value):
		texture_2 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(1, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = null:
	set(value):
		texture_3 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(2, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = null:
	set(value):
		texture_4 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(3, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = null:
	set(value):
		texture_5 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(4, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = null:
	set(value):
		texture_6 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(5, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D = null:
	set(value):
		texture_7 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(6, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D = null:
	set(value):
		texture_8 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(7, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D = null:
	set(value):
		texture_9 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(8, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D = null:
	set(value):
		texture_10 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(9, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D = null:
	set(value):
		texture_11 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(10, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D = null:
	set(value):
		texture_12 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(11, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D = null:
	set(value):
		texture_13 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(12, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D = null:
	set(value):
		texture_14 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(13, value)
			regenerate_all_chunk_grass()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D = null:
	set(value):
		texture_15 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_slot(14, value)
			regenerate_all_chunk_grass()
#endregion

#region texture slots (256)
const MAX_TEXTURE_SLOTS := 256
# Keep legacy VOID behavior for now (texture_15 in the old system).
const VOID_TEXTURE_SLOT := 15

# NOTE: Avoid hard type-hints here; headless/script-cache builds may not resolve global class_names reliably.
const _TEXTURE_SLOT_SCRIPT := preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_texture_slot.gd")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_slots: Array = []
@export_custom(PROPERTY_HINT_RANGE, "1,256,1", PROPERTY_USAGE_STORAGE) var visible_texture_slot_count: int = 6

# Runtime-built Texture2DArrays. Intentionally NOT stored in scenes (prevents .tscn bloat).
var _runtime_texture_array : Texture2DArray = null
var _runtime_normal_texture_array : Texture2DArray = null
var _runtime_grass_texture_array : Texture2DArray = null
var _runtime_slot_layer_lookup_tex : Texture2D = null

var texture_array : Texture2DArray:
	get:
		return _runtime_texture_array
	set(value):
		# Ignore any serialized value from older scenes; we always rebuild at runtime.
		pass

var grass_texture_array : Texture2DArray:
	get:
		return _runtime_grass_texture_array
	set(value):
		pass

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var _grass_slots_migrated : bool = false

# Warn about normalization/mismatches only once per slot to avoid editor spam.
var _warned_texture_array_slots : Dictionary = {}
var _warned_grass_array_slots : Dictionary = {}
#endregion

#region grass textures (legacy exports -> slot grass_texture)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_1 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_1 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].grass_texture = value
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
#endregion

#region has grass variables (legacy exports -> slot has_grass)
# Texture 1 was historically always-on; now exposed so "Base Grass" can be disabled.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_has_grass : bool = true:
	set(value):
		tex1_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].has_grass = tex1_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].has_grass = tex2_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].has_grass = tex3_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].has_grass = tex4_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].has_grass = tex5_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = bool(value) if value != null else true
		if not is_batch_updating and is_inside_tree():
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].has_grass = tex6_has_grass
			invalidate_grass_bake_state()
			rebuild_grass_texture_array()
			_request_grass_regen()
#endregion

#region texture albedos
#These are just for migration into the Palette system
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_color_1 : Color = Color("c4a57aff")  # Light-brown default for Texture 6 (base wall)

#endregion

#region texture scales
# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(0, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(1, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(2, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(3, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(4, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(5, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(6, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(7, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(8, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(9, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(10, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(11, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(12, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(13, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating and is_inside_tree():
			_set_legacy_texture_scale(14, value)
#endregion

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null
var _main_texture_library : Resource = null
var _main_visible_texture_slot_count: int = 6

# Palette System
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_colors : Array[Color] = []
# Per palette-index weight (0-100). Used to control per-slot palette distribution.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_weights : Array[float] = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_color_indices : Array = [
	[], [], [], [], [], [], [], [], [], [], [], [], [], [], []
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_blend_modes: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

@export_category("Vertex Painter")
# Wetness controls (per texture slot)
## Slot wet enabled toggles wetness effects on/off for that slot.
## Slot wet modes: 0 = Wet (darken only), 1 = Glossy puddles (noise-masked).
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_enabled : Array[bool] = [
	false, false, false, false, false,
	false, false, false, false, false,
	false, false, false, false, false,
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_modes : Array[int] = [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
]

## Slot roughnesses control surface roughness (0 = shiny/wet, 1 = matte/dry).
# (UI presents this as "Terrain" wetness by storing roughness = 1 - wetness)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_roughnesses : Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]
## Slot grass wetness controls how strongly the upper half of each grass blade gets the wet look.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_grass_wetnesses : Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0, 0.0,
]

# Per-slot access to the shared global noise texture.
# Floor and wall controls are split so a material can use noise on one surface type without affecting the other.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_floor_noise_enabled : Array = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_floor_noise_strengths : Array = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_floor_noise_scales : Array = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wall_noise_enabled : Array = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wall_noise_strengths : Array = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wall_noise_scales : Array = []

# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int = 5:
	set(value):
		var old := default_wall_texture
		default_wall_texture = clampi(int(value), 0, 255)
		if is_batch_updating or not is_inside_tree():
			return
		_apply_default_wall_texture_change(old, default_wall_texture)


func _apply_default_wall_texture_change(old_idx: int, new_idx: int) -> void:
	if chunks.is_empty():
		return
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		var changed: bool = bool(chunk.apply_default_wall_texture(old_idx, new_idx))
		# Also update "unpainted" wall cells (those matching ground) to follow the new default.
		changed = bool(chunk.apply_default_wall_to_unpainted(new_idx)) or changed
		if changed:
			chunk.regenerate_all_cells(true)

signal load_finished

var void_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/void_texture.tres")

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null

var is_batch_updating : bool = false

var chunks : Dictionary = {}
var collision_triangle_count_debug: int = 0
var _visibility_detail_settings_dirty := true
var _grass_random_scale_apply_queued := false
var _batch_chunk_creation_in_progress := false
var navmesh_painting_enabled : bool = false
const POST_PROCESS_SLOT_COUNT := 5
@export_storage var surface_effects : Array[Resource] = []
@export_storage var overlay_effects : Array[Resource] = []
@export_storage var surface_effect_slot_count : int = 1
@export_storage var overlay_effect_slot_count : int = 1
enum NavBakeMode { WALKABLE_SURFACE_ONLY, WALKABLE_REGION_CLEANUP, WALKABLE_REGION_CLEANUP_AGENT_CLEARANCE }
@export var nav_bake_mode : NavBakeMode = NavBakeMode.WALKABLE_REGION_CLEANUP_AGENT_CLEARANCE
@export_range(0.0, 8.0, 0.05) var nav_agent_radius : float = 1.0
@export_range(0.0, 89.0, 0.5) var nav_max_slope : float = 45.0
@export_range(0.0, 8.0, 0.05) var nav_max_step_height : float = 0.5
@export_range(0.0, 256.0, 0.25) var nav_min_region_size : float = 2.0
var navmesh_needs_bake : bool:
	get:
		return _nav_controller.needs_bake
var navmesh_preview_revision : int:
	get:
		return _nav_controller.preview_revision


func get_post_process_effects(array_name: String = "surface_effects") -> Array:
	var effects : Array = get(array_name)
	while effects.size() < POST_PROCESS_SLOT_COUNT:
		effects.append(null)
	return effects


func get_post_process_slot_count(array_name: String = "surface_effects") -> int:
	var count_name := "surface_effect_slot_count" if array_name == "surface_effects" else "overlay_effect_slot_count"
	return clampi(int(get(count_name)), 1, POST_PROCESS_SLOT_COUNT)


func get_post_process_effect(slot_idx: int, array_name: String = "surface_effects") -> Resource:
	var effects := get_post_process_effects(array_name)
	return effects[slot_idx] if slot_idx >= 0 and slot_idx < effects.size() else null


func ensure_post_process_effect(slot_idx: int, array_name: String = "surface_effects") -> Resource:
	var effects := get_post_process_effects(array_name)
	if slot_idx < 0 or slot_idx >= POST_PROCESS_SLOT_COUNT:
		return null
	if effects[slot_idx] == null:
		effects[slot_idx] = preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_post_process_effect.gd").new()
		set(array_name, effects)
	_rebuild_post_process_effects()
	return effects[slot_idx]


func add_post_process_effect_slot(array_name: String = "surface_effects") -> int:
	var count_name := "surface_effect_slot_count" if array_name == "surface_effects" else "overlay_effect_slot_count"
	var count := mini(get_post_process_slot_count(array_name) + 1, POST_PROCESS_SLOT_COUNT)
	set(count_name, count)
	ensure_post_process_effect(count - 1, array_name)
	return count - 1


func clear_post_process_effect(slot_idx: int, array_name: String = "surface_effects") -> void:
	var effects := get_post_process_effects(array_name)
	if slot_idx >= 0 and slot_idx < effects.size():
		effects[slot_idx] = null
		set(array_name, effects)
		_rebuild_post_process_effects()


func delete_post_process_effect_slot(slot_idx: int, array_name: String = "surface_effects") -> void:
	clear_post_process_effect(slot_idx, array_name)
	var count_name := "surface_effect_slot_count" if array_name == "surface_effects" else "overlay_effect_slot_count"
	set(count_name, maxi(get_post_process_slot_count(array_name) - 1, 1))


func _rebuild_post_process_effects(refresh_chunks: bool = true) -> void:
	_post_process_controller.rebuild(refresh_chunks)

#region collision helpers

func _refresh_chunk_collisions(mark_dirty: bool = false, rebuild_from_source: bool = false) -> void:
	_collision_controller.refresh_chunks(mark_dirty, rebuild_from_source)


func _refresh_collision_stats() -> void:
	if _collision_controller != null:
		_collision_controller._refresh_stats()


func _queue_chunk_collision_rebuild(chunk_coords: Vector2i, rebuild_from_source: bool = false) -> void:
	_collision_controller.queue_chunk(chunk_coords, rebuild_from_source)


func _schedule_collision_refresh() -> void:
	_collision_controller.schedule_refresh()


func _flush_scheduled_collision_refresh() -> void:
	_collision_controller.flush_scheduled_refresh()

#endregion

#region navmesh helpers

func invalidate_navmesh_preview() -> void:
	_nav_controller.invalidate_preview()


func invalidate_navmesh_chunk(chunk_coords: Vector2i) -> void:
	_nav_controller.invalidate_chunk(chunk_coords)


func invalidate_all_navmesh_chunks() -> void:
	_nav_controller.invalidate_all()


func bake_navmesh_from_tool() -> void:
	_nav_controller.bake()


func clear_baked_navmesh() -> void:
	_nav_controller.clear_baked()


func _clear_nav_debug_mesh() -> void:
	_nav_controller.clear_debug_mesh()


func _clear_nav_source_root() -> void:
	var source_root := get_node_or_null("TerrainNavSources")
	if source_root != null:
		source_root.queue_free()


func _get_navmesh_bake_signature() -> String:
	return "%s|%s|%.4f|%.4f|%.4f|%.4f" % [
		str(navmesh_painting_enabled),
		str(nav_bake_mode),
		nav_agent_radius,
		nav_max_slope,
		nav_max_step_height,
		nav_min_region_size,
	]


func _ensure_nav_chunks_ready_for_bake() -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk) or not chunk.cell_geometry.is_empty():
			continue
		if not data_directory.is_empty() and MSTDataHandler.metadata_exists(data_directory, chunk.chunk_coords):
			MSTDataHandler.load_chunk_from_directory(self, chunk.chunk_coords)
		if chunk.cell_geometry.is_empty():
			chunk.regenerate_all_cells(false)


func _get_or_create_navmesh_region(scene_root: Node) -> NavigationRegion3D:
	var region := get_node_or_null("TerrainNavMesh") as NavigationRegion3D
	if region == null:
		region = MSTNavMeshScript.new()
		region.name = "TerrainNavMesh"
		add_child(region)
		if EngineWrapper.instance.is_editor():
			region.owner = scene_root
	elif region.get_script() == null and EngineWrapper.instance.is_editor():
		region.set_script(MSTNavMeshScript)
	region.visible = false
	return region


func _configure_navigation_mesh(nav_mesh: NavigationMesh) -> void:
	nav_mesh.agent_max_slope = nav_max_slope
	nav_mesh.agent_max_climb = nav_max_step_height
	nav_mesh.agent_radius = nav_agent_radius if nav_bake_mode == NavBakeMode.WALKABLE_REGION_CLEANUP_AGENT_CLEARANCE else 0.0
	nav_mesh.region_min_size = nav_min_region_size if nav_bake_mode != NavBakeMode.WALKABLE_SURFACE_ONLY else 0.0


func _build_navigation_mesh_from_walkable_faces(nav_mesh: NavigationMesh) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var lookup := {}
	var seen_triangles := {}
	var epsilon := maxf(minf(cell_size.x, cell_size.y) * 0.001, 0.0001)
	var rebuild_all := _nav_controller.chunk_face_cache.is_empty()
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk):
			continue
		var faces: PackedVector3Array
		if rebuild_all or _nav_controller.dirty_chunks.has(chunk.chunk_coords) or not _nav_controller.chunk_face_cache.has(chunk.chunk_coords):
			var permission = chunk.navmesh_permission if navmesh_painting_enabled else null
			faces = chunk.get_nav_walkable_faces_for_permission(nav_max_slope, permission)
			_nav_controller.chunk_face_cache[chunk.chunk_coords] = faces
		else:
			faces = _nav_controller.chunk_face_cache[chunk.chunk_coords]
		for index in range(0, faces.size(), 3):
			if index + 2 >= faces.size():
				break
			var a := chunk.transform * faces[index]
			var b := chunk.transform * faces[index + 1]
			var c := chunk.transform * faces[index + 2]
			var triangle_key := _nav_controller.triangle_key(a, b, c, epsilon)
			if seen_triangles.has(triangle_key):
				continue
			seen_triangles[triangle_key] = true
			var tri := [a, b, c]
			var tri_indices := PackedInt32Array()
			for vertex in tri:
				tri_indices.append(_nav_controller.add_vertex(lookup, vertices, vertex, epsilon))
			indices.append_array(tri_indices)
	if vertices.is_empty() or indices.is_empty():
		return {"polygon_count": 0}
	if nav_mesh.has_method("set_vertices") and nav_mesh.has_method("add_polygon"):
		nav_mesh.set_vertices(vertices)
		for index in range(0, indices.size(), 3):
			nav_mesh.add_polygon(PackedInt32Array([indices[index], indices[index + 1], indices[index + 2]]))
	elif nav_mesh.has_method("create_from_mesh"):
		var source_mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		nav_mesh.create_from_mesh(source_mesh)
	return {"polygon_count": int(indices.size() / 3)}

#endregion

func _sync_global_noise_to_grass() -> void:
	if grass_mesh == null or terrain_material == null:
		return
	var grass_mat := grass_mesh.material as ShaderMaterial
	if grass_mat == null:
		return
	grass_mat.set_shader_parameter("global_noise_texture", global_noise_texture)
	grass_mat.set_shader_parameter("chunk_size", dimensions)
	grass_mat.set_shader_parameter("cell_size", cell_size)
	# Shader uniform is blade_variation; grass_random_scale is the terrain/UI property name.
	grass_mat.set_shader_parameter("blade_variation", grass_random_scale)
	grass_mat.set_shader_parameter("fps", animation_fps)
	grass_mat.set_shader_parameter("animate_active", true)
	grass_mat.set_shader_parameter("vc_floor_tex_array", _runtime_texture_array)
	grass_mat.set_shader_parameter("use_floor_tex_array", _runtime_texture_array != null)
	for p in ["global_noise_scale", "global_noise_strength", "global_noise_scroll", "wind_direction", "wind_speed"]:
		var v := terrain_material.get_shader_parameter(p)
		if v != null:
			grass_mat.set_shader_parameter(p, v)
	_apply_grass_random_scale()
	_sync_prefab_material_state()


func _apply_grass_random_scale() -> void:
	_grass_random_scale_apply_queued = false
	var materials : Array[ShaderMaterial] = []
	if grass_mesh != null and grass_mesh.material is ShaderMaterial:
		materials.append(grass_mesh.material as ShaderMaterial)
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk) or chunk.grass_planter == null:
			continue
		var multimesh := chunk.grass_planter.multimesh
		if multimesh == null or not (multimesh.mesh is QuadMesh):
			continue
		if multimesh.mesh.material is ShaderMaterial:
			var material := multimesh.mesh.material as ShaderMaterial
			if not materials.has(material):
				materials.append(material)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("global_noise_texture", global_noise_texture)
		material.set_shader_parameter("global_noise_scale", global_noise_scale)
		material.set_shader_parameter("blade_variation", grass_random_scale)
		material.set_shader_parameter("fps", animation_fps)
		material.set_shader_parameter("animate_active", true)


func _sync_wind_state(refresh_chunks: bool = true) -> void:
	_material_controller.sync_wind_state(refresh_chunks)


func _sync_prefab_material_state() -> void:
	var has_map := prefab_set != null and prefab_set.color_map != null
	var color_map := prefab_set.color_map if has_map else null
	if terrain_material != null:
		terrain_material.set_shader_parameter("tex_prefab_colormap", color_map)
		terrain_material.set_shader_parameter("has_prefab_colormap", has_map)
	if grass_mesh != null and grass_mesh.material is ShaderMaterial:
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("tex_prefab_colormap", color_map)
		grass_mat.set_shader_parameter("has_prefab_colormap", has_map)


func _validate_property(property: Dictionary) -> void:
	if property.name in ["bake_grass", "bake_collision"]:
		if storage_mode != StorageMode.BAKED:
			property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name in [
		"collision_mode",
		"collision_thickness",
		"nav_bake_mode",
		"nav_agent_radius",
		"nav_max_slope",
		"nav_max_step_height",
		"nav_min_region_size",
		"surface_effects",
		"overlay_effects",
		"surface_effect_slot_count",
		"overlay_effect_slot_count",
		"wind_tip_color",
	]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name in ["enable_runtime_texture_baking", "polygon_texture_resolution", "bake_material_override"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "blend_noise_enabled":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_shader.tres").duplicate(true)
	terrain_material.set_shader_parameter("use_hard_textures", false)
	terrain_material.set_shader_parameter("blend_mode", 0)
	terrain_material.set_shader_parameter("blend_sharpness", blend_sharpness)
	terrain_material.set_shader_parameter("floor_blend_mode", floor_blend_mode)
	terrain_material.set_shader_parameter("blend_noise_threshold", blend_noise_threshold)
	terrain_material.set_shader_parameter("global_noise_texture", global_noise_texture)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	terrain_material.set_shader_parameter("global_noise_scroll", global_noise_scroll)
	_sync_prefab_material_state()
	var base_grass_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_grass_mesh.tres")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)
	_sync_global_noise_to_grass()
	_sync_wind_state(false)
	print_verbose("Last storage mode: ", _last_storage_mode)
	
	# Sync shader state for scenes/presets that set flat normals.
	_apply_flat_normals(_use_flat_normals)
	
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()


## Bumped when shared terrain surface shader params change so chunks re-duplicate materials.
var _surface_material_revision: int = 0


func get_chunk_surface_material() -> Material:
	return terrain_material


func refresh_chunk_surface_materials() -> void:
	# Chunks render duplicated materials; bump revision so refresh re-copies
	# shared uniforms (blend/ridge/ledge/etc.) from terrain_material.
	_surface_material_revision += 1
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.refresh_surface_material()

#region grass cooking related

var _grass_regen_timer : Timer = null
var _grass_regen_pending : bool = false
## Serialize full-chunk grass cooks so ~100 chunks don't all process in parallel
## (which left many incomplete / partially revealed).
var _grass_cook_queue : Array[Dictionary] = []
var _grass_cook_active_planter : MarchingSquaresGrassPlanter = null


func _enqueue_grass_cook(planter: MarchingSquaresGrassPlanter, generation: int) -> void:
	if planter == null or not is_instance_valid(planter):
		return
	for i in range(_grass_cook_queue.size() - 1, -1, -1):
		if _grass_cook_queue[i].get("planter") == planter:
			_grass_cook_queue.remove_at(i)
	# Restart in-place when this planter is already the active cook.
	if _grass_cook_active_planter == planter:
		planter.call_deferred("_process_deferred_grass_cells", generation)
		return
	_grass_cook_queue.append({"planter": planter, "generation": generation})
	_kick_grass_cook_queue()


func _grass_cook_finished(planter: MarchingSquaresGrassPlanter) -> void:
	if _grass_cook_active_planter == planter:
		_grass_cook_active_planter = null
	call_deferred("_kick_grass_cook_queue")


func _kick_grass_cook_queue() -> void:
	if _grass_cook_active_planter != null:
		if is_instance_valid(_grass_cook_active_planter) and _grass_cook_active_planter._deferred_grass_pending:
			return
		_grass_cook_active_planter = null
	while not _grass_cook_queue.is_empty():
		var entry : Dictionary = _grass_cook_queue.pop_front()
		var planter : MarchingSquaresGrassPlanter = entry.get("planter")
		var generation := int(entry.get("generation", -1))
		if planter == null or not is_instance_valid(planter):
			continue
		if generation != planter._deferred_grass_generation:
			continue
		if not planter._deferred_grass_pending and planter._deferred_grass_remaining() <= 0:
			continue
		_grass_cook_active_planter = planter
		planter.call_deferred("_process_deferred_grass_cells", generation)
		return


func invalidate_grass_bake_state() -> void:
	baked_grass_array_path = ""
	baked_dense_slot_lookup = PackedInt32Array()
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk):
			continue
		chunk._temp_grass_multimesh = null
		chunk.mark_dirty()


func _request_grass_regen() -> void:
	if is_batch_updating:
		return
	
	# Coalesce editor slider drags into a single grass rebuild.
	if EngineWrapper.instance.is_editor():
		# Tool scripts can run while the node is not inside the scene tree (e.g. during load).
		# Timers cannot be started until we're inside the tree.
		if not is_inside_tree():
			_grass_regen_pending = true
			return
		if _grass_regen_timer == null:
			_grass_regen_timer = Timer.new()
			_grass_regen_timer.name = "_mst_grass_regen_timer"
			_grass_regen_timer.one_shot = true
			add_child(_grass_regen_timer)
			_grass_regen_timer.timeout.connect(_apply_grass_regen)
		_grass_regen_timer.wait_time = 0.12
		_grass_regen_timer.start()
		return
	
	_apply_grass_regen()


func _apply_grass_regen() -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.grass_planter:
			chunk.grass_planter.regenerate_all_cells()


func regenerate_all_chunk_grass(force_recook: bool = false) -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.grass_planter:
			chunk.grass_planter.regenerate_all_cells(force_recook)

#endregion

func _apply_flat_normals(p_enabled: bool) -> void:
	_use_flat_normals = p_enabled
	# Terrain shader expects "use_flat_normals".
	if terrain_material != null:
		terrain_material.set_shader_parameter("use_flat_normals", _use_flat_normals)
	if is_inside_tree():
		refresh_chunk_surface_materials()
	# Grass instances use this flag when generating normals.
	_request_grass_regen()


func _ensure_texture_slots() -> void:
	MarchingSquaresTerrainHelpers.ensure_texture_slots(self)


func _ensure_palette_settings() -> void:
	MarchingSquaresTerrainHelpers.ensure_palette_settings(self)

#region legacy related

func _maybe_migrate_legacy_textures() -> void:
	MarchingSquaresTerrainHelpers.maybe_migrate_legacy_textures(self)


func _maybe_migrate_legacy_grass() -> void:
	MarchingSquaresTerrainHelpers.maybe_migrate_legacy_grass(self)


func _build_texture_library_from_slots() -> MSTextureLibrary:
	_ensure_texture_slots()
	var lib := MSTextureLibrary.new()
	lib.max_slots = MAX_TEXTURE_SLOTS
	lib.ensure_length()
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			continue
		var tex = texture_slots[i].texture
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(tex):
			lib.albedo_textures[i] = tex
		var grass_tex = texture_slots[i].grass_texture
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(grass_tex):
			lib.grass_textures[i] = grass_tex
	return lib


func ensure_texture_library_resource() -> Resource:
	if texture_library != null:
		return texture_library
	var lib := _build_texture_library_from_slots()
	var out_dir := data_directory
	if out_dir == null or out_dir == "":
		out_dir = "res://scenes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var lib_path := out_dir.path_join("mst_texture_library.tres")
	var save_err := ResourceSaver.save(lib, lib_path)
	if save_err != OK:
		push_warning("[MST] Failed to create texture library at %s (err=%s)." % [lib_path, str(save_err)])
		return null
	var lib_res : Resource = ResourceLoader.load(lib_path)
	if lib_res != null:
		texture_library = lib_res
		return lib_res
	push_warning("[MST] Created texture library but failed to reload it from %s." % lib_path)
	texture_library = lib
	return lib


func _set_legacy_texture_slot(slot_idx: int, tex: Texture2D) -> void:
	MarchingSquaresTerrainHelpers.set_legacy_texture_slot(self, slot_idx, tex)


func _set_legacy_texture_scale(slot_idx: int, scale: float) -> void:
	MarchingSquaresTerrainHelpers.set_legacy_texture_scale(self, slot_idx, scale)

#endregion

func _push_tex_scales() -> void:
	MarchingSquaresTerrainHelpers.push_tex_scales(self)


func _get_decompressed_image(tex: Texture2D) -> Image:
	return MSTVertexColorHelper.get_decompressed_image(tex)


func _warn_once(cache: Dictionary, key, message: String) -> void:
	MSTVertexColorHelper.warn_once(cache, key, message)

#region texture arrays

func _normalize_image_for_texture_array(src: Image, w: int, h: int) -> Image:
	return MSTVertexColorHelper.normalize_image_for_texture_array(src, w, h)


func rebuild_texture_array() -> void:
	_surface_material_revision += 1
	MarchingSquaresTerrainHelpers.rebuild_texture_array(self)


func rebuild_grass_texture_array() -> void:
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(self)


func _clear_runtime_texture_arrays_for_scene_save() -> void:
	_runtime_texture_array = null
	_runtime_normal_texture_array = null
	_runtime_grass_texture_array = null
	_runtime_slot_layer_lookup_tex = null
	if terrain_material:
		terrain_material.set_shader_parameter("vc_tex_array", null)
		terrain_material.set_shader_parameter("vc_normal_array", null)
		terrain_material.set_shader_parameter("use_normal_array", false)
		terrain_material.set_shader_parameter("vc_slot_layer_lookup_tex", null)
		terrain_material.set_shader_parameter("use_slot_layer_lookup", false)
	if grass_mesh and grass_mesh.material and grass_mesh.material is ShaderMaterial:
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("vc_grass_tex_array", null)
		grass_mat.set_shader_parameter("use_grass_tex_array", false)
		grass_mat.set_shader_parameter("vc_floor_tex_array", null)
		grass_mat.set_shader_parameter("use_floor_tex_array", false)
		grass_mat.set_shader_parameter("vc_slot_layer_lookup_tex", null)
		grass_mat.set_shader_parameter("use_slot_layer_lookup", false)


func _restore_runtime_texture_arrays_after_scene_save() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	rebuild_texture_array()
	rebuild_grass_texture_array()


func _ensure_default_texture_preset_bound() -> void:
	if current_texture_preset != null:
		# A 1.2.4 scene can deserialize its old preset successfully while its
		# 1.3 texture_slots remain empty. Import the old 15-texture list once so
		# the rebuilt meshes do not use the white placeholder layers.
		if _needs_legacy_preset_texture_migration(current_texture_preset):
			load_from_preset(current_texture_preset)
		return
	var default_preset := ResourceLoader.load(DEFAULT_TEXTURE_PRESET_PATH) as MarchingSquaresTexturePreset
	if default_preset == null:
		push_warning("[MST] Failed to load default texture preset from %s." % DEFAULT_TEXTURE_PRESET_PATH)
		return
	current_texture_preset = default_preset
	load_from_preset(default_preset)


func _needs_legacy_preset_texture_migration(preset: MarchingSquaresTexturePreset) -> bool:
	if preset == null or preset.new_textures == null:
		return false
	if preset.new_textures.terrain_textures.size() < 15:
		return false
	for i in range(mini(MAX_TEXTURE_SLOTS, texture_slots.size())):
		if texture_slots[i] != null and MarchingSquaresTerrainHelpers.is_valid_texture2d(texture_slots[i].texture):
			return false
	for legacy_tex in preset.new_textures.terrain_textures:
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(legacy_tex):
			return true
	return false


func _is_default_empty_texture_preset(preset: MarchingSquaresTexturePreset) -> bool:
	if preset == null:
		return false
	return str(preset.resource_path) == DEFAULT_TEXTURE_PRESET_PATH

#endregion

func _notification(what: int) -> void:
	# Save all dirty chunks externally and keep generated runtime arrays out of .tscn files.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if EngineWrapper.instance.is_editor():
			_clear_runtime_texture_arrays_for_scene_save()
			MSTDataHandler.save_all_chunks(self)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_restore_runtime_texture_arrays_after_scene_save()


func _process(_delta: float) -> void:
	if EngineWrapper.instance.is_editor():
		if _visibility_detail_settings_dirty:
			_apply_visibility_detail_settings()
		elif _lod_controller != null and _lod_controller.has_pending_updates():
			_lod_controller.apply()
		_update_building_chunk_visibility()
	if _collision_controller != null:
		_collision_controller.process_queue()
		_collision_controller.process_scheduled_refresh()

#region lod related

func _update_building_chunk_visibility() -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk):
			continue
		var building := chunk.build_phase in [
			MarchingSquaresTerrainChunk.BuildPhase.GENERATING_CELLS,
			MarchingSquaresTerrainChunk.BuildPhase.PUBLISHING_TILES,
		]
		chunk.visible = not building
		if chunk.grass_planter != null and is_instance_valid(chunk.grass_planter):
			chunk.grass_planter.set_grass_visible(not building)
		for child in chunk.get_children():
			if child is StaticBody3D:
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.visible = false


func _apply_visibility_detail_settings() -> void:
	_visibility_detail_settings_dirty = false
	var terrain_end := 0.0
	var grass_end := 0.0
	var flower_end := 0.0
	if visibility_detail_enabled:
		terrain_end = chunk_visibility_end_distance
		grass_end = grass_visibility_end_distance
		flower_end = flower_visibility_end_distance
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if not is_instance_valid(chunk):
			continue
		chunk.visibility_range_end = terrain_end
		chunk.visibility_range_end_margin = visibility_range_margin if terrain_end > 0.0 else 0.0
		for tile in chunk._mesh_tiles.values():
			if tile is MeshInstance3D:
				chunk._apply_mesh_tile_visibility(tile)
		if chunk.grass_planter != null and is_instance_valid(chunk.grass_planter):
			chunk.grass_planter.set_visibility_range(
				grass_end,
				visibility_range_margin if grass_end > 0.0 else 0.0
			)
	for child in get_children():
		if child is MarchingSquaresFlowerPlanter:
			child.set_flower_visibility_range(
				flower_end,
				visibility_range_margin if flower_end > 0.0 else 0.0
			)
	if _lod_controller != null:
		_lod_controller.apply()


func _invalidate_terrain_lod_chunk(coords: Vector2i) -> void:
	if _lod_controller != null:
		_lod_controller.invalidate_chunk(coords)

#endregion

func _enter_tree() -> void:
	_deferred_enter_tree.call_deferred()


func _initialize_data_directory() -> void:
	var copy_from_dir := ""
	if EngineWrapper.instance.is_editor() and not data_directory.is_empty():
		var normalized_dir := str(data_directory).replace("\\", "/")
		if not normalized_dir.begins_with("res://"):
			push_warning("[MST] Ignoring invalid data_directory '" + str(data_directory) + "'. Falling back to an auto-generated project-relative terrain data folder.")
			data_directory = ""
		elif not MSTDataHandler.is_data_directory_unique(self):
			copy_from_dir = data_directory
			data_directory = ""
			push_warning("[MST] This terrain shared a data_directory with another terrain. A unique terrain data folder will be generated automatically to prevent chunk data overlap.")
	
	if EngineWrapper.instance.is_editor() and (data_directory.is_empty()):
		var auto_path := MSTDataHandler.generate_data_directory(self)
		if not auto_path.is_empty():
			data_directory = auto_path
	if copy_from_dir:
		MSTDataHandler.copy_recursive(copy_from_dir, data_directory)
	if EngineWrapper.instance.is_editor() and data_directory.is_empty() and not _warned_data_directory_message:
		_warned_data_directory_message = true
		push_warning("[MST] Terrain data_directory could not be generated yet. Save the scene once so MST can assign a stable external chunk storage folder.")


func _warn_storage_expectations() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	if storage_mode == StorageMode.BAKED and not _warned_storage_mode_message:
		_warned_storage_mode_message = true
		push_warning("[MST] Storage Mode is BAKED. Chunk metadata can be larger because mesh, collision, and baked grass cache data may be stored externally. Use RUNTIME for smaller files with more rebuild/load work.")


func _repair_chunk_storage() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	_initialize_data_directory()
	if data_directory == null or data_directory == "":
		push_error("[MST] Cannot repair chunk storage because no data directory is assigned. Save the scene first, then try again.")
		return
	chunks.clear()
	for child in get_children():
		var terrain_chunk := child as MarchingSquaresTerrainChunk
		if terrain_chunk != null:
			chunks[terrain_chunk.chunk_coords] = terrain_chunk
			terrain_chunk.terrain_system = self
			terrain_chunk.mark_dirty()
	if MSTDataHandler.save_all_chunks(self):
		_storage_initialized = true
		if EngineWrapper.instance.is_editor():
			EngineWrapper.instance.mark_scene_as_unsaved()
		push_warning("[MST] Chunk metadata was repaired and externalized. Save the scene now to strip embedded chunk payload from the .tscn.")
	else:
		push_error("[MST] Failed to repair chunk storage. Embedded chunk data was left untouched.")


func _deferred_enter_tree() -> void:
	_initialize_data_directory()
	if blend_mode != 0:
		blend_mode = 0
	
	_ensure_default_texture_preset_bound()
	
	print_verbose("Terrain data dir: ", data_directory)
	
	# Populate chunks dictionary from scene children
	# NOTE: Chunks can legitimately be "dirty" in editor (e.g. after property edits).
	# Never abort initialization because that prevents terrain from loading/rendering.
	chunks.clear()
	for child in get_children():
		if child is MarchingSquaresTerrainChunk:
			chunks[child.chunk_coords] = child
			child.terrain_system = self
			child.grass_planter = null
	
	_warn_storage_expectations()
	
	# Load external data if storage was previously initialized
	if _storage_initialized:
		MSTDataHandler.load_terrain_data(self)
	elif EngineWrapper.instance.is_editor() and MSTDataHandler.needs_migration(self):
		if not _warned_embedded_chunk_migration:
			_warned_embedded_chunk_migration = true
			push_warning("[MST] Embedded legacy chunk data was detected for this terrain. MST is auto-migrating chunk source data to external storage. Save the scene after migration to strip embedded chunk payload from the .tscn.")
		# Auto-migrate embedded data to external storage (editor only)
		MSTDataHandler.migrate_to_external_storage(self)
	
	# Apply all persisted textures/colors to this terrain's unique shader materials.
	# _init() creates fresh duplicated materials with only the base resource defaults.
	# IMPORTANT: do this BEFORE chunk initialization so runtime texture baking sees correct uniforms.
	migrate_colors_to_palette()
	force_batch_update()
	_rebuild_post_process_effects(false)
	
	# One-time editor migrations: regenerate meshes so new wall tagging/material selection is present in geometry.
	
	# Initialize all chunks (regenerate mesh/grass from loaded data)
	var force_regen_for_wall_fixes : bool = false
	var force_regen_for_default_wall : bool = false
	if EngineWrapper.instance.is_editor():
		if not _uv_wall_sentinel_migrated:
			_uv_wall_sentinel_migrated = true
		if not _uv_wall_sentinel_v2_migrated:
			_uv_wall_sentinel_v2_migrated = true
		if not _wall_material_pair_migrated:
			_wall_material_pair_migrated = true
		if not _default_wall_texture_migrated:
			_default_wall_texture_migrated = true
	else:
		await get_tree().process_frame
	
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		# Runtime regenerates immediately because generated mesh resources are ephemeral.
		# The editor normally defers this, except for a legacy 1.2.4 mesh that the
		# persistence loader explicitly discarded and must rebuild automatically.
		var regenerate_on_load := not EngineWrapper.instance.is_editor() or chunk._legacy_mesh_rebuild_pending
		chunk.initialize_terrain(regenerate_on_load)
		if force_regen_for_wall_fixes:
			chunk.regenerate_mesh(true)
		if force_regen_for_default_wall:
			var changed_default := bool(chunk.apply_default_wall_to_unpainted(default_wall_texture))
			changed_default = bool(chunk.apply_default_wall_to_legacy_init(default_wall_texture)) or changed_default
			if changed_default:
				chunk.regenerate_all_cells(true)
	
	# Chunk initialization can recreate or hydrate mesh materials after the
	# initial post-process build. Reapply the chain once the runtime materials
	# actually exist so the running scene cannot lose its configured effects.
	_rebuild_post_process_effects(true)
	
	if EngineWrapper.instance.is_editor():
		for child in get_children():
			if child is MarchingSquaresPopulator: # Prep the populators
				child.terrain_system = self
				child.rebuild_cell_data()
				if child is MarchingSquaresFlowerPlanter:
					child.regenerate_flowers()
	# Runtime grass planters may have been created or hydrated during chunk
	# initialization. Sync the live materials after that work, not only during
	# terrain _init(), so editor wind settings are preserved at runtime.
	_sync_global_noise_to_grass()
	_sync_wind_state(false)
	
	_grass_regen_pending = false
	load_finished.emit()
	# Do not rebuild missing chunk meshes automatically while the editor is opening scenes.
	# Generated meshes are intentionally stripped from .tscn files to prevent bloat.
	# Rebuilding them during editor layout can stall Godot at "Loading editor".


func _recover_missing_editor_chunk_meshes() -> void:
	if not EngineWrapper.instance.is_editor() or not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	await tree.process_frame
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		if not is_inside_tree():
			return
		if not is_instance_valid(chunk) or chunk.mesh != null:
			continue
		if not _chunk_has_rebuild_source(chunk):
			if MSTDataHandler.metadata_exists(data_directory, chunk.chunk_coords):
				MSTDataHandler.load_chunk_from_directory(self, chunk.chunk_coords)
		if not _chunk_has_rebuild_source(chunk):
			push_error("MST: Cannot recover chunk " + str(chunk.chunk_coords) + " because no scene source data or external metadata exists.")
			continue
		await tree.process_frame
		if not is_instance_valid(chunk) or chunk.mesh != null:
			continue
		chunk.regenerate_mesh(false)


func _chunk_has_rebuild_source(chunk: MarchingSquaresTerrainChunk) -> bool:
	if not is_instance_valid(chunk):
		return false
	if not (chunk.height_map is Array) or chunk.height_map.size() != dimensions.z:
		return false
	for row in chunk.height_map:
		if not (row is Array) or row.size() != dimensions.x:
			return false
	return true


func recover_missing_chunk_meshes() -> void:
	if EngineWrapper.instance.is_editor():
		call_deferred("_recover_missing_editor_chunk_meshes")
		return
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		if is_instance_valid(chunk) and chunk.mesh == null:
			if not _chunk_has_rebuild_source(chunk) and MSTDataHandler.metadata_exists(data_directory, chunk.chunk_coords):
				MSTDataHandler.load_chunk_from_directory(self, chunk.chunk_coords)
			if _chunk_has_rebuild_source(chunk):
				chunk.regenerate_mesh(false)
			else:
				push_error("MST: Cannot recover chunk " + str(chunk.chunk_coords) + " because no source data exists.")


func _exit_tree() -> void:
	# Scene switching detaches this node before _exit_tree() runs. Normal editor
	# saves are handled by NOTIFICATION_EDITOR_PRE_SAVE above; do not call into
	# the SceneTree from teardown, because data.tree is already null here.
	if EngineWrapper.instance.is_editor():
		# Clear chunks map to avoid holding references after exit
		chunks.clear()
		# Let children handle their own cleanup (chunk._exit_tree will run)


func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


func add_new_chunk(chunk_x: int, chunk_z: int, plugin, regenerate_mesh: bool = true):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := MarchingSquaresTerrainChunk.new()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.chunk_coords = chunk_coords
	new_chunk.terrain_system = self
	
	new_chunk.generate_height_map(plugin.height)
	new_chunk.mark_dirty()
	
	var chunk_left : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left and not chunk_left.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_left.height_map.size() and z < new_chunk.height_map.size() and chunk_left.height_map[z].size() >= dimensions.x and new_chunk.height_map[z].size() >= 1:
				new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right and not chunk_right.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_right.height_map.size() and z < new_chunk.height_map.size() and chunk_right.height_map[z].size() >= 1 and new_chunk.height_map[z].size() >= dimensions.x:
				new_chunk.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up and not chunk_up.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_up.height_map.size() >= dimensions.z and new_chunk.height_map.size() >= 1:
			for x in range(0, dimensions.x):
				if x < chunk_up.height_map[dimensions.z - 1].size() and x < new_chunk.height_map[0].size():
					new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down and not chunk_down.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_down.height_map.size() >= 1 and new_chunk.height_map.size() >= dimensions.z:
			for x in range(0, dimensions.x):
				if x < chunk_down.height_map[0].size() and x < new_chunk.height_map[dimensions.z - 1].size():
					new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]
	
	add_chunk(chunk_coords, new_chunk, plugin, false)
	
	if plugin.current_quick_paint:
		plugin.current_draw_pattern.clear()
		plugin.current_draw_pattern[chunk_coords] = {}
	
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var cell := Vector2i(x, z)
				plugin.current_draw_pattern[chunk_coords][cell] = 1.0
	
		plugin.draw_pattern(self) # Apply the current selected quick paint after seam heights are finalized
		plugin.current_draw_pattern.clear()
	elif regenerate_mesh:
		new_chunk.regenerate_mesh()


## Adds missing chunks in a rectangle, yielding between chunks so the editor
## remains responsive and mesh generation does not start for the whole batch at once.
func add_chunk_batch(start_coords: Vector2i, size: Vector2i, plugin) -> void:
	if _batch_chunk_creation_in_progress:
		push_warning("[MST] A batch chunk creation is already in progress.")
		return
	if size.x <= 0 or size.y <= 0:
		return
	_batch_chunk_creation_in_progress = true
	_add_chunk_batch_deferred(start_coords, size, plugin)


func _add_chunk_batch_deferred(start_coords: Vector2i, size: Vector2i, plugin) -> void:
	var created := 0
	var skipped := 0
	var active_builds: Array[MarchingSquaresTerrainChunk] = []
	# Four background builds reduce total batch time while leaving enough CPU
	# headroom for Godot's editor and avoiding one worker per chunk.
	const MAX_ACTIVE_BUILDS := 4
	for z in range(start_coords.y, start_coords.y + size.y):
		for x in range(start_coords.x, start_coords.x + size.x):
			var coords := Vector2i(x, z)
			if chunks.has(coords):
				skipped += 1
				continue
			add_new_chunk(x, z, plugin, false)
			created += 1
			var chunk := chunks.get(coords) as MarchingSquaresTerrainChunk
			if chunk != null:
				# Build cells on the chunk's background thread. The publication path
				# is frame-budgeted, and limiting concurrency avoids oversubscribing
				# the editor when a large rectangle is selected.
				chunk.begin_deferred_initial_build()
				active_builds.append(chunk)
			while active_builds.size() >= MAX_ACTIVE_BUILDS:
				await get_tree().process_frame
				for active_chunk in active_builds.duplicate():
					if not is_instance_valid(active_chunk) or not active_chunk._initial_build_pending:
						active_builds.erase(active_chunk)
	while not active_builds.is_empty():
		await get_tree().process_frame
		for active_chunk in active_builds.duplicate():
			if not is_instance_valid(active_chunk) or not active_chunk._initial_build_pending:
				active_builds.erase(active_chunk)
	_batch_chunk_creation_in_progress = false
	print("[MST] Batch chunk creation complete: created=%d skipped=%d" % [created, skipped])
	if plugin != null and is_instance_valid(plugin) and plugin.ui != null:
		plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)


func remove_chunk(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	_nav_controller.invalidate_chunk(chunk_coords)
	_invalidate_terrain_lod_chunk(chunk_coords)
	chunk.free()
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			var terrain_chunk := child as MarchingSquaresTerrainChunk
			if terrain_chunk != null:
				plugin.selected_chunk = terrain_chunk
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)
	
	if not Engine.is_editor_hint():
		return
	
	for child in get_children():
		if child is MarchingSquaresFlowerPlanter:
			if child.planted_chunks.has(chunk_coords):
				child.planted_chunks.erase(chunk_coords)
				child.populated_chunks.erase(chunk)
				child.cell_data.erase(chunk)
				
				child.terrain_system = self
				for p_chunk in child.populated_chunks:
					if p_chunk.cell_geometry.is_empty():
						for cell in child.planted_chunks[p_chunk.chunk_coords]:
							p_chunk.regenerate_cell_geometry(cell)
				child.setup(false)
				child.regenerate_flowers()


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	_nav_controller.invalidate_chunk(chunk_coords)
	_invalidate_terrain_lod_chunk(chunk_coords)
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			var terrain_chunk := child as MarchingSquaresTerrainChunk
			if terrain_chunk != null:
				plugin.selected_chunk = terrain_chunk
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)
	
	if not Engine.is_editor_hint():
		return
	
	for child in get_children():
		if child is MarchingSquaresFlowerPlanter:
			if child.planted_chunks.has(chunk_coords):
				child.planted_chunks.erase(chunk_coords)
				child.populated_chunks.erase(chunk)
				child.cell_data.erase(chunk)
				
				for p_chunk in child.populated_chunks:
					if p_chunk.cell_geometry.is_empty():
						for cell in child.planted_chunks[p_chunk.chunk_coords]:
							p_chunk.regenerate_cell_geometry(cell)
				child.setup(false)
				child.regenerate_flowers()


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunk, plugin, regenerate_mesh: bool = true) -> void:
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	print(coords)
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	add_child(chunk)
	chunks[coords] = chunk
	_nav_controller.invalidate_chunk(coords)
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors.
	# This matters when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	chunk.position = Vector3(
		coords.x * ((dimensions.x - 1) * cell_size.x),
		0,
		coords.y * ((dimensions.z - 1) * cell_size.y)
	)
	
	EngineWrapper.instance.set_owner_recursive(chunk)
	chunk.initialize_terrain(regenerate_mesh)
	# Rebuild all chunk proxies after insertion so flat regions can merge
	# across the newly completed chunk grid.
	_schedule_collision_refresh()
	_apply_visibility_detail_settings()
	print_verbose("[MST] Added new chunk to terrain system at ", chunk)
	if plugin:
		if not plugin.selected_chunk or plugin.selected_chunk.chunk_coords == Vector2i(99999, 99999):
			plugin.selected_chunk = chunk
		plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
		plugin.gizmo_plugin.trigger_redraw(self)

#region texture (set) functions

# WARNING: this function is currently not being used anymore. [Q] Yūgen: was that intentional?
# This (legacy) function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	# Keep legacy behavior of ensuring textures are hooked up on startup.
	# This now uses Texture2DArray.
	var need_tex_array := terrain_material.get_shader_parameter("vc_tex_array") == null
	if need_tex_array:
		_ensure_texture_slots()
		_maybe_migrate_legacy_textures()
		rebuild_texture_array()
		_push_tex_scales()
	
	# Even if the texture array exists, ensure the palette/slot lookup textures are present.
	# Otherwise the shader may sample defaults.
	var need_palette := (
		terrain_material.get_shader_parameter("palette_colors_tex") == null
		or terrain_material.get_shader_parameter("palette_weights_tex") == null
		or terrain_material.get_shader_parameter("palette_meta_tex") == null
		or terrain_material.get_shader_parameter("palette_surface_settings_tex") == null
	)
	if need_palette:
		_ensure_texture_slots()
		_ensure_palette_settings()
		_rebuild_palette_uniforms()
	
	# PR1 grass shader expects 6 separate textures (grass_texture_1..6).
	if grass_mat.get_shader_parameter("grass_texture_1") == null:
		_ensure_texture_slots()
		_maybe_migrate_legacy_grass()
		rebuild_grass_texture_array()


func migrate_colors_to_palette() -> void:
	MarchingSquaresTerrainHelpers.migrate_colors_to_palette(self)


func _ensure_palette_weights() -> void:
	MarchingSquaresTerrainHelpers.ensure_palette_weights(self)


func _rebuild_palette_uniforms() -> void:
	_surface_material_revision += 1
	MarchingSquaresTerrainHelpers.rebuild_palette_uniforms(self)
	refresh_chunk_surface_materials()


func _push_slot_blend_modes() -> void:
	# Blend modes are packed into palette_meta_tex now.
	_rebuild_palette_uniforms()


## Applies all shader parameters and regenerates grass once
## Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("chunk_size", dimensions)
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Texture2DArray + per-slot scales
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()
	var has_prefab_map := prefab_set != null and prefab_set.color_map != null
	terrain_material.set_shader_parameter("tex_prefab_colormap", prefab_set.color_map if has_prefab_map else null)
	terrain_material.set_shader_parameter("has_prefab_colormap", has_prefab_map)
	_sync_prefab_material_state()
	refresh_chunk_surface_materials()
	
	# GRASS MATERIAL - Grass Textures (Texture2DArray)
	_maybe_migrate_legacy_grass()
	rebuild_grass_texture_array()
	
	terrain_material.set_shader_parameter("global_noise_texture", global_noise_texture)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	terrain_material.set_shader_parameter("global_noise_scroll", global_noise_scroll)
	terrain_material.set_shader_parameter("floor_blend_mode", floor_blend_mode)
	terrain_material.set_shader_parameter("blend_noise_threshold", blend_noise_threshold)
	_sync_global_noise_to_grass()
	_apply_blend_noise_settings()


## Syncs and saves current UI texture values to the given preset resource
## Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null or current_texture_preset.resource_path.is_empty():
		return
	var preset_owns_texture_resources := (
		current_texture_preset.get("texture_library") != null
		and current_texture_preset.texture_library != null
	) or (
		current_texture_preset.get("baked_albedo_array_path") != null
		and current_texture_preset.has_baked_arrays()
	)
	var preset_has_legacy_texture_payload := false
	if current_texture_preset.new_textures != null and current_texture_preset.new_textures.terrain_textures.size() >= 15:
		for legacy_tex in current_texture_preset.new_textures.terrain_textures:
			if MarchingSquaresTerrainHelpers.is_valid_texture2d(legacy_tex):
				preset_has_legacy_texture_payload = true
				break
	current_texture_preset.visible_texture_slot_count = clampi(int(visible_texture_slot_count), 6, MAX_TEXTURE_SLOTS)
	
	# Terrain textures
	if preset_owns_texture_resources or preset_has_legacy_texture_payload:
		current_texture_preset.new_textures.terrain_textures[0] = texture_1
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
	
	# Grass sprites (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.grass_sprites.size() != MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.grass_sprites.resize(MAX_TEXTURE_SLOTS)
	if current_texture_preset.get("slot_texture_scales") is Array and current_texture_preset.slot_texture_scales.size() != MAX_TEXTURE_SLOTS:
		current_texture_preset.slot_texture_scales.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if preset_owns_texture_resources:
			current_texture_preset.new_textures.grass_sprites[i] = texture_slots[i].grass_texture if texture_slots[i] != null else null
		if current_texture_preset.get("slot_texture_scales") is Array:
			current_texture_preset.slot_texture_scales[i] = float(texture_slots[i].scale) if texture_slots[i] != null else 1.0
	
	# Palette system
	current_texture_preset.new_textures.grass_colors.resize(128)
	for i in range(128):
		current_texture_preset.new_textures.grass_colors[i] = palette_colors[i]
	_ensure_palette_weights()
	current_texture_preset.palette_weights = palette_weights.duplicate()
	current_texture_preset.slot_color_indices = slot_color_indices.duplicate(true)
	current_texture_preset.slot_blend_modes = slot_blend_modes.duplicate()
	_ensure_palette_settings()
	current_texture_preset.slot_wet_enabled = slot_wet_enabled.duplicate()
	current_texture_preset.slot_wet_modes = slot_wet_modes.duplicate()
	current_texture_preset.slot_roughnesses = slot_roughnesses.duplicate()
	current_texture_preset.slot_grass_wetnesses = slot_grass_wetnesses.duplicate()
	current_texture_preset.slot_floor_noise_enabled = slot_floor_noise_enabled.duplicate()
	current_texture_preset.slot_floor_noise_strengths = slot_floor_noise_strengths.duplicate()
	current_texture_preset.slot_floor_noise_scales = slot_floor_noise_scales.duplicate()
	current_texture_preset.slot_wall_noise_enabled = slot_wall_noise_enabled.duplicate()
	current_texture_preset.slot_wall_noise_strengths = slot_wall_noise_strengths.duplicate()
	current_texture_preset.slot_wall_noise_scales = slot_wall_noise_scales.duplicate()
	
	# Has grass flags (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.has_grass.size() != MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.has_grass.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		current_texture_preset.new_textures.has_grass[i] = bool(texture_slots[i].has_grass) if texture_slots[i] != null else false
	
	if preset_owns_texture_resources and current_texture_preset.get("texture_library") != null:
		current_texture_preset.texture_library = texture_library
	if preset_owns_texture_resources and current_texture_preset.get("baked_albedo_array_path") != null:
		current_texture_preset.baked_albedo_array_path = baked_albedo_array_path
	if preset_owns_texture_resources and current_texture_preset.get("baked_normal_array_path") != null:
		current_texture_preset.baked_normal_array_path = baked_normal_array_path
	if preset_owns_texture_resources and current_texture_preset.get("baked_grass_array_path") != null:
		current_texture_preset.baked_grass_array_path = baked_grass_array_path
	if preset_owns_texture_resources and current_texture_preset.get("baked_dense_slot_lookup") != null:
		current_texture_preset.baked_dense_slot_lookup = baked_dense_slot_lookup
	
	ResourceSaver.save(current_texture_preset)


func load_from_preset(preset: MarchingSquaresTexturePreset) -> void:
	if preset == null:
		return
	var is_default_empty_preset := _is_default_empty_texture_preset(preset)
	
	var current_preset_owns_texture_resources := false
	if current_texture_preset != null:
		var current_has_texture_library := current_texture_preset.get("texture_library") != null and current_texture_preset.texture_library != null
		var current_has_baked_arrays := current_texture_preset.get("baked_albedo_array_path") != null and current_texture_preset.has_baked_arrays()
		var current_has_legacy_textures := false
		if current_texture_preset.new_textures != null and current_texture_preset.new_textures.terrain_textures.size() >= 15:
			for legacy_tex in current_texture_preset.new_textures.terrain_textures:
				if MarchingSquaresTerrainHelpers.is_valid_texture2d(legacy_tex):
					current_has_legacy_textures = true
					break
		current_preset_owns_texture_resources = current_has_texture_library or current_has_baked_arrays or current_has_legacy_textures
	
	var preset_has_texture_library := preset.get("texture_library") != null and preset.texture_library != null
	if preset_has_texture_library:
		if texture_library != null and texture_library != preset.texture_library and (_main_texture_library == null or not current_preset_owns_texture_resources):
			_main_texture_library = texture_library
			_main_visible_texture_slot_count = clampi(int(visible_texture_slot_count), 6, MAX_TEXTURE_SLOTS)
		texture_library = preset.texture_library
	else:
		if _main_texture_library != null:
			texture_library = _main_texture_library
	if preset.get("baked_albedo_array_path") != null and preset.has_baked_arrays():
		baked_albedo_array_path = preset.baked_albedo_array_path
		baked_normal_array_path = preset.baked_normal_array_path
		baked_grass_array_path = preset.baked_grass_array_path
		baked_dense_slot_lookup = preset.baked_dense_slot_lookup if preset.get("baked_dense_slot_lookup") != null else PackedInt32Array()
	else:
		baked_albedo_array_path = ""
		baked_normal_array_path = ""
		baked_grass_array_path = ""
		baked_dense_slot_lookup = PackedInt32Array()
	
	var has_real_palette_data := false
	for arr in preset.slot_color_indices:
		if arr.size() > 0:
			has_real_palette_data = true
			break
	
	if (preset.slot_color_indices.size() == 15 or preset.slot_color_indices.size() == MAX_TEXTURE_SLOTS) and has_real_palette_data:
		slot_color_indices = preset.slot_color_indices.duplicate(true)
		if preset.new_textures.grass_colors.size() == 128:
			palette_colors = preset.new_textures.grass_colors.duplicate()
		if preset.palette_weights.size() == 128:
			palette_weights = preset.palette_weights.duplicate()
		else:
			palette_weights.resize(128)
			for i in range(128):
				palette_weights[i] = 100.0
	else:
		# Old preset — reset everything to clean defaults
		slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]
		palette_colors.resize(128)
		palette_weights.resize(128)
		for i in range(128):
			palette_colors[i] = MarchingSquaresTerrainHelpers.default_palette_color_for_slot(i)
			palette_weights[i] = 100.0
	
	if preset.slot_blend_modes.size() == 15 or preset.slot_blend_modes.size() == MAX_TEXTURE_SLOTS:
		slot_blend_modes = preset.slot_blend_modes.duplicate()
	else:
		slot_blend_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	
	if preset.get("slot_wet_enabled") is Array and (preset.slot_wet_enabled.size() == 15 or preset.slot_wet_enabled.size() == MAX_TEXTURE_SLOTS):
		slot_wet_enabled = preset.slot_wet_enabled.duplicate()
	else:
		slot_wet_enabled = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
	
	if preset.get("slot_wet_modes") is Array and (preset.slot_wet_modes.size() == 15 or preset.slot_wet_modes.size() == MAX_TEXTURE_SLOTS):
		slot_wet_modes = preset.slot_wet_modes.duplicate()
	else:
		slot_wet_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	
	if preset.get("slot_roughnesses") is Array and (preset.slot_roughnesses.size() == 15 or preset.slot_roughnesses.size() == MAX_TEXTURE_SLOTS):
		slot_roughnesses = preset.slot_roughnesses.duplicate()
	else:
		slot_roughnesses = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	
	if preset.get("slot_grass_wetnesses") is Array and (preset.slot_grass_wetnesses.size() == 15 or preset.slot_grass_wetnesses.size() == MAX_TEXTURE_SLOTS):
		slot_grass_wetnesses = preset.slot_grass_wetnesses.duplicate()
	else:
		slot_grass_wetnesses = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	
	if preset.get("slot_floor_noise_enabled") is Array and (preset.slot_floor_noise_enabled.size() == 15 or preset.slot_floor_noise_enabled.size() == MAX_TEXTURE_SLOTS):
		slot_floor_noise_enabled = preset.slot_floor_noise_enabled.duplicate()
	else:
		slot_floor_noise_enabled = []
	if preset.get("slot_floor_noise_strengths") is Array and (preset.slot_floor_noise_strengths.size() == 15 or preset.slot_floor_noise_strengths.size() == MAX_TEXTURE_SLOTS):
		slot_floor_noise_strengths = preset.slot_floor_noise_strengths.duplicate()
	else:
		slot_floor_noise_strengths = []
	if preset.get("slot_floor_noise_scales") is Array and (preset.slot_floor_noise_scales.size() == 15 or preset.slot_floor_noise_scales.size() == MAX_TEXTURE_SLOTS):
		slot_floor_noise_scales = preset.slot_floor_noise_scales.duplicate()
	else:
		slot_floor_noise_scales = []
	if preset.get("slot_wall_noise_enabled") is Array and (preset.slot_wall_noise_enabled.size() == 15 or preset.slot_wall_noise_enabled.size() == MAX_TEXTURE_SLOTS):
		slot_wall_noise_enabled = preset.slot_wall_noise_enabled.duplicate()
	else:
		slot_wall_noise_enabled = []
	if preset.get("slot_wall_noise_strengths") is Array and (preset.slot_wall_noise_strengths.size() == 15 or preset.slot_wall_noise_strengths.size() == MAX_TEXTURE_SLOTS):
		slot_wall_noise_strengths = preset.slot_wall_noise_strengths.duplicate()
	else:
		slot_wall_noise_strengths = []
	if preset.get("slot_wall_noise_scales") is Array and (preset.slot_wall_noise_scales.size() == 15 or preset.slot_wall_noise_scales.size() == MAX_TEXTURE_SLOTS):
		slot_wall_noise_scales = preset.slot_wall_noise_scales.duplicate()
	else:
		slot_wall_noise_scales = []
	
	var preset_slot_scales : Array = []
	if preset.get("slot_texture_scales") is Array:
		preset_slot_scales = preset.slot_texture_scales
	if preset.new_textures != null and preset.new_textures.has_method("_ensure_grass_arrays"):
		preset.new_textures._ensure_grass_arrays()
	var requested_visible_slot_count : int = 0
	if preset.get("visible_texture_slot_count") != null:
		requested_visible_slot_count = clampi(int(preset.visible_texture_slot_count), 6, MAX_TEXTURE_SLOTS)
	var preset_has_legacy_textures := false
	if preset.new_textures != null and preset.new_textures.terrain_textures.size() >= 15:
		for legacy_tex in preset.new_textures.terrain_textures:
			if MarchingSquaresTerrainHelpers.is_valid_texture2d(legacy_tex):
				preset_has_legacy_textures = true
				break
	var apply_legacy_texture_resources := preset_has_legacy_textures and not preset_has_texture_library
	if not is_default_empty_preset and not preset_has_texture_library and not apply_legacy_texture_resources and not current_preset_owns_texture_resources:
		if texture_library != null:
			_main_texture_library = texture_library
		_main_visible_texture_slot_count = clampi(int(visible_texture_slot_count), 6, MAX_TEXTURE_SLOTS)
	
	_ensure_palette_settings()
	_rebuild_palette_uniforms()
	_push_slot_blend_modes()
	
	# Apply textures + grass from the preset.
	is_batch_updating = true
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	_maybe_migrate_legacy_grass()
	
	var lib_res : Resource = texture_library
	if lib_res != null and lib_res is Resource and lib_res.resource_path != null and not str(lib_res.resource_path).is_empty():
		var loaded_lib : Resource = ResourceLoader.load(str(lib_res.resource_path))
		if loaded_lib != null:
			lib_res = loaded_lib
			texture_library = loaded_lib
	var highest_library_slot := -1
	if lib_res != null and lib_res is MSTextureLibrary:
		lib_res.ensure_length()
		for i in range(MAX_TEXTURE_SLOTS):
			if texture_slots[i] == null:
				texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
			var tex = lib_res.albedo_textures[i] if i < lib_res.albedo_textures.size() else null
			if MarchingSquaresTerrainHelpers.is_valid_texture2d(tex):
				texture_slots[i].texture = tex
				texture_slots[i].active = true
				highest_library_slot = i
			else:
				texture_slots[i].texture = null
				texture_slots[i].active = false
			var gtex = lib_res.grass_textures[i] if i < lib_res.grass_textures.size() else null
			if MarchingSquaresTerrainHelpers.is_valid_texture2d(gtex):
				texture_slots[i].grass_texture = gtex
			else:
				texture_slots[i].grass_texture = null
			if i < preset_slot_scales.size() and preset_slot_scales[i] != null:
				texture_slots[i].scale = float(preset_slot_scales[i])
		if highest_library_slot >= 0:
			visible_texture_slot_count = clampi(max(visible_texture_slot_count, highest_library_slot + 1), 1, MAX_TEXTURE_SLOTS)
	
	# Terrain textures (first 15)
	if apply_legacy_texture_resources:
		texture_1 = preset.new_textures.terrain_textures[0] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[0]) else null
		texture_2 = preset.new_textures.terrain_textures[1] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[1]) else null
		texture_3 = preset.new_textures.terrain_textures[2] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[2]) else null
		texture_4 = preset.new_textures.terrain_textures[3] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[3]) else null
		texture_5 = preset.new_textures.terrain_textures[4] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[4]) else null
		texture_6 = preset.new_textures.terrain_textures[5] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[5]) else null
		texture_7 = preset.new_textures.terrain_textures[6] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[6]) else null
		texture_8 = preset.new_textures.terrain_textures[7] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[7]) else null
		texture_9 = preset.new_textures.terrain_textures[8] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[8]) else null
		texture_10 = preset.new_textures.terrain_textures[9] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[9]) else null
		texture_11 = preset.new_textures.terrain_textures[10] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[10]) else null
		texture_12 = preset.new_textures.terrain_textures[11] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[11]) else null
		texture_13 = preset.new_textures.terrain_textures[12] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[12]) else null
		texture_14 = preset.new_textures.terrain_textures[13] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[13]) else null
		texture_15 = preset.new_textures.terrain_textures[14] if MarchingSquaresTerrainHelpers.is_valid_texture2d(preset.new_textures.terrain_textures[14]) else null
	
		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
			var legacy_slot_tex = preset.new_textures.terrain_textures[i]
			texture_slots[i].texture = legacy_slot_tex if MarchingSquaresTerrainHelpers.is_valid_texture2d(legacy_slot_tex) else null
		if texture_library != null and (_main_texture_library == null or not current_preset_owns_texture_resources):
			_main_texture_library = texture_library
			_main_visible_texture_slot_count = clampi(int(visible_texture_slot_count), 6, MAX_TEXTURE_SLOTS)
		texture_library = _build_texture_library_from_slots()
	
	# Texture scales (first 15)
	if preset.new_textures != null and preset.new_textures.texture_scales.size() >= 15:
		texture_scale_1 = preset.new_textures.texture_scales[0]
		texture_scale_2 = preset.new_textures.texture_scales[1]
		texture_scale_3 = preset.new_textures.texture_scales[2]
		texture_scale_4 = preset.new_textures.texture_scales[3]
		texture_scale_5 = preset.new_textures.texture_scales[4]
		texture_scale_6 = preset.new_textures.texture_scales[5]
		texture_scale_7 = preset.new_textures.texture_scales[6]
		texture_scale_8 = preset.new_textures.texture_scales[7]
		texture_scale_9 = preset.new_textures.texture_scales[8]
		texture_scale_10 = preset.new_textures.texture_scales[9]
		texture_scale_11 = preset.new_textures.texture_scales[10]
		texture_scale_12 = preset.new_textures.texture_scales[11]
		texture_scale_13 = preset.new_textures.texture_scales[12]
		texture_scale_14 = preset.new_textures.texture_scales[13]
		texture_scale_15 = preset.new_textures.texture_scales[14]
		
		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
			texture_slots[i].scale = float(preset.new_textures.texture_scales[i])
	
	# Grass sprites + has-grass flags (slot-based 0..255)
	# IMPORTANT: if an older preset does not contain these arrays, do NOT wipe existing grass.
	var p_sprites : Array = []
	var p_has : Array = []
	if preset.new_textures != null and preset.new_textures.get("grass_sprites") is Array:
		p_sprites = preset.new_textures.grass_sprites
	if preset.new_textures != null and preset.new_textures.get("has_grass") is Array:
		p_has = preset.new_textures.has_grass
	
	var has_sprite_data := false
	for sprite_tex in p_sprites:
		if MarchingSquaresTerrainHelpers.is_valid_texture2d(sprite_tex):
			has_sprite_data = true
			break
	var has_flag_data := p_has.size() > 0
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		if has_sprite_data and i < p_sprites.size():
			texture_slots[i].grass_texture = p_sprites[i] if MarchingSquaresTerrainHelpers.is_valid_texture2d(p_sprites[i]) else null
		if has_flag_data and i < p_has.size():
			texture_slots[i].has_grass = bool(p_has[i])
		elif not has_flag_data:
			# Default only when the preset provides no flags at all.
			texture_slots[i].has_grass = (i == 0)
	
	# Keep legacy inspector fields in sync (first 6)
	if has_sprite_data:
		grass_sprite_tex_1 = p_sprites[0] if p_sprites.size() > 0 and p_sprites[0] != null else grass_sprite_tex_1
		grass_sprite_tex_2 = p_sprites[1] if p_sprites.size() > 1 and p_sprites[1] != null else grass_sprite_tex_2
		grass_sprite_tex_3 = p_sprites[2] if p_sprites.size() > 2 and p_sprites[2] != null else grass_sprite_tex_3
		grass_sprite_tex_4 = p_sprites[3] if p_sprites.size() > 3 and p_sprites[3] != null else grass_sprite_tex_4
		grass_sprite_tex_5 = p_sprites[4] if p_sprites.size() > 4 and p_sprites[4] != null else grass_sprite_tex_5
		grass_sprite_tex_6 = p_sprites[5] if p_sprites.size() > 5 and p_sprites[5] != null else grass_sprite_tex_6
	if p_has.size() > 0:
		tex1_has_grass = bool(p_has[0]) if p_has.size() > 0 else tex1_has_grass
		tex2_has_grass = bool(p_has[1]) if p_has.size() > 1 else tex2_has_grass
		tex3_has_grass = bool(p_has[2]) if p_has.size() > 2 else tex3_has_grass
		tex4_has_grass = bool(p_has[3]) if p_has.size() > 3 else tex4_has_grass
		tex5_has_grass = bool(p_has[4]) if p_has.size() > 4 else tex5_has_grass
		tex6_has_grass = bool(p_has[5]) if p_has.size() > 5 else tex6_has_grass
	
	# Restore UI-visible slot layout from preset intent, not just from whichever albedo textures happen
	# to exist in the currently linked library. This keeps older/light presets from collapsing down to
	# only Texture 1 when they mainly carry color-array data.
	var highest_preset_slot : int = 0
	var reset_to_empty_layout : bool = (preset.resource_path.is_empty() or is_default_empty_preset) and not preset_has_texture_library and not apply_legacy_texture_resources
	for i in range(MAX_TEXTURE_SLOTS):
		var slot_palette_indices : Array = slot_color_indices[i] if i < slot_color_indices.size() and slot_color_indices[i] is Array else []
		var slot_has_palette : bool = slot_palette_indices.size() > 0
		var slot_has_texture : bool = texture_slots[i] != null and MarchingSquaresTerrainHelpers.is_valid_texture2d(texture_slots[i].texture)
		var slot_has_grass_flag : bool = texture_slots[i] != null and bool(texture_slots[i].has_grass)
		var should_show: bool = (i == 0) or slot_has_palette or slot_has_texture or slot_has_grass_flag
		if should_show and i != 15:
			highest_preset_slot = i
	
	var inferred_visible_slot_count : int = clampi(max(highest_preset_slot + 1, 6), 6, MAX_TEXTURE_SLOTS)
	var target_visible_slot_count : int = inferred_visible_slot_count
	if reset_to_empty_layout:
		target_visible_slot_count = clampi(max(requested_visible_slot_count, 6), 6, MAX_TEXTURE_SLOTS)
	if not reset_to_empty_layout and not preset_has_texture_library and not apply_legacy_texture_resources and _main_visible_texture_slot_count > 0:
		target_visible_slot_count = clampi(max(_main_visible_texture_slot_count, inferred_visible_slot_count), 6, MAX_TEXTURE_SLOTS)
	if reset_to_empty_layout:
		target_visible_slot_count = clampi(max(requested_visible_slot_count, 6), 6, MAX_TEXTURE_SLOTS)
	elif requested_visible_slot_count > 0:
		target_visible_slot_count = clampi(max(requested_visible_slot_count, inferred_visible_slot_count), 6, MAX_TEXTURE_SLOTS)
	
	for i in range(MAX_TEXTURE_SLOTS):
		var slot_palette_indices : Array = slot_color_indices[i] if i < slot_color_indices.size() and slot_color_indices[i] is Array else []
		var slot_has_palette : bool = slot_palette_indices.size() > 0
		var slot_has_texture : bool = texture_slots[i] != null and MarchingSquaresTerrainHelpers.is_valid_texture2d(texture_slots[i].texture)
		var slot_has_grass_flag : bool = texture_slots[i] != null and bool(texture_slots[i].has_grass)
		var should_show : bool
		if reset_to_empty_layout:
			should_show = (i < target_visible_slot_count and i != 15)
		else:
			should_show = (i == 0) or slot_has_palette or slot_has_texture or slot_has_grass_flag or (i < target_visible_slot_count and i != 15)
		if texture_slots[i] == null:
			texture_slots[i] = _TEXTURE_SLOT_SCRIPT.new()
		texture_slots[i].active = should_show
	
	visible_texture_slot_count = target_visible_slot_count
	
	is_batch_updating = false
	
	# Applying a preset can be frequent (scrolling presets). Avoid heavy work unless needed.
	# Terrain textures/palette always need a refresh.
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()
	
	# Only rebuild the 256-layer grass Texture2DArray when the preset actually provides sprite data.
	if has_sprite_data:
		rebuild_grass_texture_array()
	
	_request_grass_regen()

#endregion
