@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk


# Explicit preloads avoid tool-script class resolution issues.
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")
const MSTTerrainCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_cell.gd")
const MSTPrefabCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/prefab/marching_squares_prefab_cell.gd")
const MSTDataHandler := preload("res://addons/MarchingSquaresTerrain/resources/mst_data_handler.gd")
const MAX_WALL_PAINT_STAMPS := 64
const MESH_TILE_SIZE := 8

enum BuildPhase {
	IDLE,
	GENERATING_CELLS,
	PUBLISHING_TILES,
	COLLISION_PENDING,
	GRASS_PENDING,
	READY,
}

enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}
enum GrassMode {GRASS, GRASSLESS}

const MERGE_MODE := {
	Mode.CUBIC: 0.6,
	Mode.POLYHEDRON: 1.3,
	Mode.ROUNDED_POLYHEDRON: 2.1,
	Mode.SEMI_ROUND: 5.0,
	Mode.SPHERICAL: 20.0,
}

# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : MarchingSquaresTerrain
@export var chunk_coords : Vector2i = Vector2i.ZERO

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.POLYHEDRON: # The max height distance between points before a wall is created between them
	set(mode):
		merge_mode = mode
		if is_inside_tree() and grass_planter and grass_planter.multimesh:
			var grass_mat : ShaderMaterial = grass_planter.multimesh.mesh.material as ShaderMaterial
			if mode == Mode.SEMI_ROUND or mode == Mode.SPHERICAL:
				grass_mat.set_shader_parameter("is_merge_round", true)
			else:
				grass_mat.set_shader_parameter("is_merge_round", false)
			merge_threshold = MERGE_MODE[mode]
			regenerate_all_cells(true)
@export_storage var height_map : Array # Stores the heights from the heightmap
#region cell_geometry storage
# Color maps are now ephemeral and created at runtime
# Persisted via MSTDataHandler
var color_map_0 : PackedColorArray # Stores the colors from vertex_color_0 (ground)
var color_map_1 : PackedColorArray # Stores the colors from vertex_color_1 (ground)
var wall_color_map_0 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 0)
var wall_color_map_1 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 1)
var grass_mask_map : PackedColorArray # Stores if a cell should have grass or not

## Persistent per-cell permission mask used by the terrain NavMesh baker.
@export_storage var navmesh_permission : PackedByteArray = PackedByteArray()
#endregion

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : MarchingSquaresGrassPlanter
var wall_paint_stamp_positions : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_normals : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_radii : PackedFloat32Array = PackedFloat32Array()
var wall_paint_stamp_texture_indices : PackedInt32Array = PackedInt32Array()

var terrain_position_cached : Vector3 = Vector3.ZERO

var cell_generation_mutex : Mutex = Mutex.new()

var bake_material : ShaderMaterial = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_baked.tres")

#region chunk variables
# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size
#endregion

# Per-regeneration packed mesh data. Cell workers append to these arrays while holding
# cell_generation_mutex; the final ArrayMesh is assembled once on the main thread.
var _mesh_vertices := PackedVector3Array()
var _mesh_uvs := PackedVector2Array()
var _mesh_uv2s := PackedVector2Array()
var _mesh_colors := PackedColorArray()
var _mesh_custom_0 := PackedFloat32Array()
var _mesh_custom_1 := PackedFloat32Array()
var _mesh_custom_2 := PackedFloat32Array()
var _mesh_floor_flags := PackedByteArray()
var _mesh_tiles : Dictionary = {}
var _dirty_mesh_tiles : Dictionary = {}
var _dirty_grass_cells : Dictionary = {}
var _collect_mesh_arrays := true
var _chunk_surface_material : ShaderMaterial
var _chunk_surface_material_source : ShaderMaterial
var _chunk_surface_material_revision : int = -1

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.
var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)
var _data_dirty : bool = false # Set to true when source data changes, triggers save in MSTDataHandler

#region temporary storage vars
# Temporary storage for ephemeral resources during scene save
var _temp_mesh : ArrayMesh
var _temp_grass_multimesh : MultiMesh
var _temp_collision_shapes : Array[ConcavePolygonShape3D] = []  # COMMENT: Old scenes may have duplicates
var _temp_height_map : Array  # Source data - saved to external storage, not scene file
var _temp_navmesh_permission : PackedByteArray = PackedByteArray()
# Runtime cache only — never serialized. Restored after save so grass cooking can resume.
var _temp_cell_geometry : Dictionary = {}
#endregion

var _grass_regen_queued : bool = false
var _mesh_regen_queued : bool = false
var _scene_save_in_progress : bool = false
var _suppress_grass_mode_side_effects : bool = false
var _initial_build_thread : Thread
var _initial_build_pending := false
var build_phase : BuildPhase = BuildPhase.IDLE
var _defer_mesh_regeneration := false
var _initial_build_tile_queue : Array[Vector2i] = []
var _baked_mesh_is_complete := false
# Set when an old persisted mesh was discarded during a 1.2.4 -> 1.3 load.
# The editor normally skips initial regeneration, so this flag requests one
# rebuild without making every new editor chunk regenerate on scene open.
var _legacy_mesh_rebuild_pending := false

#region blend option vars
# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone := upper_thresh - lower_thresh
#endregion

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_mode : GrassMode = GrassMode.GRASS:
	set(value):
		grass_mode = value
		if _suppress_grass_mode_side_effects:
			return
		_temp_grass_multimesh = null
		if is_inside_tree():
			_apply_grass_mode()
			if grass_planter:
				_queue_grass_regen()
		mark_dirty()


func _apply_shadow_visibility_settings() -> void:
	# Editor mountains can cover a large portion of the shadow atlas. Keep
	# authored shadows for runtime, but avoid rebuilding/rendering them while
	# editing dense terrain.
	cast_shadow = SHADOW_CASTING_SETTING_OFF if EngineWrapper.instance.is_editor() else SHADOW_CASTING_SETTING_ON
	if terrain_system == null:
		return
	# Keep culling bounds tight. The mesh already owns its real AABB; using the
	# entire chunk dimensions as an extra margin keeps distant terrain active.
	extra_cull_margin = maxf(cell_size.x, cell_size.y) * 2.0


func _clear_grass_planter() -> void:
	_temp_grass_multimesh = null
	if grass_planter:
		if grass_planter.multimesh:
			grass_planter.multimesh = null
		grass_planter.owner = null
		grass_planter.free()
	grass_planter = null


func _ensure_grass_planter() -> bool:
	grass_planter = get_node_or_null("GrassPlanter")
	# Legacy scenes stored GrassPlanter as MultiMeshInstance3D. Replace those
	# nodes so the RenderingServer-backed Node3D planter can take over.
	if grass_planter != null and not (grass_planter is MarchingSquaresGrassPlanter):
		grass_planter.free()
		grass_planter = null
	if not grass_planter:
		grass_planter = MarchingSquaresGrassPlanter.new()
		if not color_map_0 or not color_map_1:
			generate_color_maps()
		if not grass_mask_map:
			generate_grass_mask_map()
		add_child(grass_planter)
	grass_planter.name = "GrassPlanter"
	grass_planter._chunk = self
	grass_planter.terrain_system = terrain_system
	EngineWrapper.instance.set_owner_recursive(grass_planter)
	
	var grass_count_changed := false
	# Prefer a usable bake cache. Empty allocations (identity transforms /
	# visible_instance_count=0) are rejected so we cook grass again.
	if _temp_grass_multimesh != null:
		if MarchingSquaresGrassPlanter.is_multimesh_cooked(_temp_grass_multimesh):
			grass_planter.multimesh = _temp_grass_multimesh
			grass_planter.setup(self, false)
			grass_planter.reveal_cooked_multimesh()
		else:
			# Empty or partial bake (virgin identity slots). Recook from geometry.
			_temp_grass_multimesh = null
			grass_count_changed = true
	
	if grass_planter.multimesh == null \
			or not MarchingSquaresGrassPlanter.is_multimesh_cooked(grass_planter.multimesh):
		# Drop partial buffers so setup() can allocate a hidden-slot MultiMesh.
		if grass_planter.multimesh != null \
				and not MarchingSquaresGrassPlanter.is_multimesh_cooked(grass_planter.multimesh):
			grass_planter.multimesh = null
		grass_planter.setup(self)
		grass_count_changed = true
	else:
		grass_planter.setup(self, false)
	
	grass_count_changed = grass_planter.ensure_multimesh_count() or grass_count_changed
	if grass_planter.multimesh == null:
		grass_planter.setup(self)
		grass_count_changed = true
	if grass_planter.multimesh:
		if terrain_system and terrain_system.grass_mesh:
			grass_planter.multimesh.mesh = terrain_system.grass_mesh
		grass_planter.sync_render_instance()
	return grass_count_changed


func _apply_grass_mode() -> void:
	if grass_mode == GrassMode.GRASSLESS:
		_clear_grass_planter()
	else:
		_ensure_grass_planter()


# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool =  true, defer_grass_setup: bool = false):
	_apply_shadow_visibility_settings()
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)
	
	var has_baked_grass_multimesh := (
		grass_mode == GrassMode.GRASS
		and _temp_grass_multimesh != null
		and MarchingSquaresGrassPlanter.is_multimesh_cooked(_temp_grass_multimesh)
	)
	var grass_count_changed := false
	if grass_mode == GrassMode.GRASS and not defer_grass_setup:
		grass_count_changed = _ensure_grass_planter()
		# ensure() may reject an empty bake cache; treat that as "needs cook".
		if not has_baked_grass_multimesh:
			grass_count_changed = true
	elif grass_mode == GrassMode.GRASSLESS:
		_clear_grass_planter()
	
	# Generate maps if not loaded from external storage (works for both editor and runtime)
	# Validate height_map shape — serialized scenes may contain empty arrays or malformed rows.
	var need_hm := true
	if height_map and height_map is Array and height_map.size() == dimensions.z:
		need_hm = false
		for row in height_map:
			if not (row is Array) or row.size() !=  dimensions.x:
				need_hm = true
				break
	if need_hm:
		generate_height_map()
	# Validate color maps sizes
	if not (color_map_0 is PackedColorArray) or color_map_0.size() !=  dimensions.z * dimensions.x or not (color_map_1 is PackedColorArray) or color_map_1.size() != dimensions.z * dimensions.x:
		generate_color_maps()
	if not (wall_color_map_0 is PackedColorArray) or wall_color_map_0.size() !=  dimensions.z * dimensions.x or not (wall_color_map_1 is PackedColorArray) or wall_color_map_1.size() != dimensions.z * dimensions.x:
		generate_wall_color_maps()
	if not (grass_mask_map is PackedColorArray) or grass_mask_map.size() !=  dimensions.z * dimensions.x:
		generate_grass_mask_map()
	
	if should_regenerate_mesh and (mesh == null or _mesh_tiles.is_empty()):
		regenerate_mesh(true)
		if mesh != null or not _mesh_tiles.is_empty():
			_legacy_mesh_rebuild_pending = false
	elif mesh or not _mesh_tiles.is_empty():
		if terrain_system:
			_apply_chunk_surface_material()
		if not _temp_collision_shapes.is_empty():
			_recreate_collision_body()
		else:
			rebuild_collision()
	
	# Respect deferred initialization: chunk creation adds the node first, then paints/seams it,
	# and only after that should the first full mesh/grass build happen.
	var can_generate_grass_now := should_regenerate_mesh or mesh != null or has_baked_grass_multimesh
	if grass_mode == GrassMode.GRASS and grass_planter and can_generate_grass_now and (not has_baked_grass_multimesh or grass_count_changed):
		if mesh != null and not has_baked_grass_multimesh:
			_queue_grass_regen()
		else:
			grass_planter.regenerate_all_cells()
	
	var has_texture_array_source := (
		terrain_system.get("texture_library") != null
		or str(terrain_system.get("baked_albedo_array_path")) != ""
	)
	if not EngineWrapper.instance.is_editor() and terrain_system.enable_runtime_texture_baking and not has_texture_array_source:
		var baker := MarchingSquaresGeometryBaker.new()
		baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
		baker.finished.connect(func(mesh_: Mesh, _original: MeshInstance3D, img: Image):
			mesh = mesh_
			var mat : Material
			if terrain_system.bake_material_override:
				mat = terrain_system.bake_material_override.duplicate()
			else:
				mat = bake_material.duplicate()
			
			if mat is StandardMaterial3D:
				mat.albedo_texture = ImageTexture.create_from_image(img)
			elif mat is ShaderMaterial:
				mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
				var src_mat : ShaderMaterial = terrain_system.terrain_material
				if src_mat != null:
					mat.set_shader_parameter("tex_prefab_colormap", src_mat.get_shader_parameter("tex_prefab_colormap"))
					mat.set_shader_parameter("has_prefab_colormap", src_mat.get_shader_parameter("has_prefab_colormap"))
			# Runtime texture baking replaces the normal terrain material. Preserve
			# the post-processing chain, otherwise effects visible in the editor are
			# silently lost as soon as the bake completes.
			if mat != null and terrain_system != null and terrain_system.terrain_material != null:
				mat.next_pass = terrain_system.terrain_material.next_pass
			if mesh and mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, mat)
		, CONNECT_ONE_SHOT)
		baker.bake_geometry_texture(self, get_tree())


func _save_external_data_before_scene_strip() -> bool:
	if not terrain_system or _skip_save_on_exit:
		return false
	var dir_path := terrain_system.data_directory
	if dir_path == null or dir_path == "":
		return false
	var needs_save := _data_dirty
	if not needs_save:
		needs_save = not MSTDataHandler.metadata_exists(dir_path, chunk_coords)
	if not needs_save:
		return true
	if not MSTDataHandler.ensure_directory_exists(dir_path):
		return false
	if not MSTDataHandler.save_chunk_resources(terrain_system, self):
		return false
	_data_dirty = false
	terrain_system._storage_initialized = true
	return MSTDataHandler.metadata_exists(dir_path, chunk_coords)


func _notification(what: int) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_scene_save_in_progress = true
			_grass_regen_queued = false
			if grass_planter:
				grass_planter.cancel_deferred_grass_generation()
			var can_strip_scene_data := _save_external_data_before_scene_strip()
			if not can_strip_scene_data:
				_scene_save_in_progress = false
				push_error("MST: Refusing to strip chunk source data because external save failed for " + str(chunk_coords))
				return
			# Store height_map and clear - source data saved to external storage, not scene
			_skip_save_on_exit = _skip_save_on_exit # Surpress warning
			_temp_height_map = height_map
			height_map = []
			_temp_navmesh_permission = navmesh_permission
			navmesh_permission = PackedByteArray()
			
			# Stash then clear so Vector2i keys are never serialized into the scene.
			_temp_cell_geometry = cell_geometry
			cell_geometry = {}
			
			# Store mesh and clear to prevent serialization
			_temp_mesh = mesh
			mesh = null
			
			# Store grass multimesh and clear
			if grass_planter and grass_planter.multimesh:
				_temp_grass_multimesh = grass_planter.multimesh
				grass_planter.multimesh = null
			
			# Handle ALL collision bodies (old scenes may have multiple duplicates!)
			_temp_collision_shapes.clear()
			var bodies_to_free : Array[StaticBody3D] = []
			for child in get_children():
				if child is StaticBody3D:
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
							_temp_collision_shapes.append(shape_child.shape)
							shape_child.shape = null  # Clear to prevent sub_resource save
						shape_child.owner = null
					child.owner = null
					bodies_to_free.append(child)
			# Free all bodies (after iteration to avoid modifying while iterating)
			for body in bodies_to_free:
				body.name += "_"
				body.queue_free()
		
		NOTIFICATION_EDITOR_POST_SAVE:
			_scene_save_in_progress = false
			# Restore height_map
			if _temp_height_map:
				height_map = _temp_height_map
				_temp_height_map = []
			if not _temp_navmesh_permission.is_empty():
				navmesh_permission = _temp_navmesh_permission
				_temp_navmesh_permission = PackedByteArray()
			
			# Restore mesh
			if _temp_mesh:
				mesh = _temp_mesh
				_temp_mesh = null
			
			# Restore runtime cell geometry so interrupted grass cooks can resume.
			if not _temp_cell_geometry.is_empty():
				cell_geometry = _temp_cell_geometry
				_temp_cell_geometry = {}
			
			# Restore grass multimesh and rebind the RenderingServer instance.
			if _temp_grass_multimesh and grass_planter:
				grass_planter.multimesh = _temp_grass_multimesh
				_temp_grass_multimesh = null
				grass_planter.sync_render_instance()
			
			# Recreate ONE collision body (only need one, even if old scene had duplicates)
			if not _temp_collision_shapes.is_empty():
				_recreate_collision_body.call_deferred()
			
			# A mid-cook save previously left missing grass rows until the user painted.
			# Resume the full cook now that source geometry is back.
			if grass_mode == GrassMode.GRASS and grass_planter != null and grass_planter.is_deferred_grass_incomplete():
				_queue_grass_regen()
		
		NOTIFICATION_PREDELETE:
			# Safety cleanup - clear owner on ALL collision nodes
			for child in get_children():
				if child is StaticBody3D:
					child.owner = null
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D:
							shape_child.owner = null


func _enter_tree() -> void:
	if not terrain_system:
		return
	# Defensive: clear any serialized runtime caches that can cause variant lookup errors.
	if cell_geometry and cell_geometry.size() > 0:
		# Ensure keys are Vector2i; if not, dump and clear to avoid variant errors on load.
		var keys_valid := true
		for k in cell_geometry.keys():
			if not (k is Vector2i):
				keys_valid = false
				break
		if not keys_valid:
			cell_geometry.clear()
			push_warning("[MST] Cleared unexpected serialized cell_geometry: please re-save the scene to remove runtime caches.")
	
	if get_parent() !=  terrain_system:
		push_error("Chunk must remain within its parent!")
		return
	terrain_system.chunks[chunk_coords] = self


func _exit_tree() -> void:
	abort_initial_build()
	# Clear temp references
	_temp_height_map = []
	_temp_navmesh_permission = PackedByteArray()
	_temp_mesh = null
	_temp_grass_multimesh = null
	_temp_cell_geometry = {}
	_temp_collision_shapes.clear()
	
	# Clear owner on ALL collision nodes to prevent serialization edge cases
	if EngineWrapper.instance.is_editor():
		for child in get_children():
			if child is StaticBody3D:
				child.owner = null
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.owner = null
	
	# Only erase if terrain_system still has THIS chunk at chunk_coords
	if terrain_system and terrain_system.chunks.get(chunk_coords) == self:
		terrain_system.chunks.erase(chunk_coords)


## Rebuild in-memory cell_geometry without republishing mesh tiles.
## Used to recook grass when a baked MultiMesh cache is empty/unusable.
func rebuild_cell_geometry_for_grass() -> void:
	# Always resize to current chunk dimensions so partial/stale needs_update
	# arrays cannot leave cells unmarked (and therefore missing from cell_geometry).
	var expected_z := dimensions.z - 1
	var expected_x := dimensions.x - 1
	if needs_update == null or needs_update.is_empty() \
			or needs_update.size() != expected_z \
			or (expected_z > 0 and needs_update[0].size() != expected_x):
		needs_update = []
		for z in range(expected_z):
			needs_update.append([])
			for x in range(expected_x):
				needs_update[z].append(true)
	else:
		for z in range(expected_z):
			for x in range(expected_x):
				needs_update[z][x] = true
	_cache_terrain_position_for_thread()
	var collect_was := _collect_mesh_arrays
	_collect_mesh_arrays = false
	generate_terrain_cells(false)
	_collect_mesh_arrays = collect_was


## Generate / refresh a single cell's in-memory geometry (used by FlowerPlanter and similar).
func regenerate_cell_geometry(cell_coords: Vector2i) -> void:
	if cell_coords.x < 0 or cell_coords.y < 0 \
			or cell_coords.x >= dimensions.x - 1 or cell_coords.y >= dimensions.z - 1:
		return
	if cell_geometry == null:
		cell_geometry = {}
	_cache_terrain_position_for_thread()
	_reset_cell_geometry(cell_coords)
	var cell = _create_cell_for_geometry(cell_coords)
	if cell == null:
		return
	var collect_was := _collect_mesh_arrays
	_collect_mesh_arrays = false
	cell.generate_geometry(cell_coords)
	_collect_mesh_arrays = collect_was
	if needs_update != null \
			and needs_update.size() > cell_coords.y \
			and needs_update[cell_coords.y].size() > cell_coords.x:
		needs_update[cell_coords.y][cell_coords.x] = false


func _reset_cell_geometry(cell_coords: Vector2i) -> void:
	cell_geometry[cell_coords] = {
		"verts": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(),
		"color_0s": PackedColorArray(),
		"color_1s": PackedColorArray(),
		"custom_1_values": PackedColorArray(),
		"mat_blend": PackedColorArray(),
		"is_floor": [],
	}


func _create_cell_for_geometry(cell_coords: Vector2i):
	var x := cell_coords.x
	var z := cell_coords.y
	var h00 := 0.0
	var h01 := 0.0
	var h10 := 0.0
	var h11 := 0.0
	if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x:
		h00 = float(height_map[z][x])
	if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x + 1:
		h01 = float(height_map[z][x + 1])
	else:
		h01 = h00
	if height_map is Array and height_map.size() > z + 1 and height_map[z + 1] is Array and height_map[z + 1].size() > x:
		h10 = float(height_map[z + 1][x])
	else:
		h10 = h00
	if height_map is Array and height_map.size() > z + 1 and height_map[z + 1] is Array and height_map[z + 1].size() > x + 1:
		h11 = float(height_map[z + 1][x + 1])
	else:
		h11 = h00

	var color_helper := MSTVertexColorHelper.new()
	var cell
	if terrain_system != null and terrain_system.prefab_set != null:
		cell = MSTPrefabCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
	else:
		cell = MSTTerrainCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
	color_helper.chunk = self
	color_helper.cell = cell
	return cell


func regenerate_mesh(use_threads: bool =  false):
	if _defer_mesh_regeneration:
		return
	# Hydrated chunks leave this flag set while their source geometry is
	# stripped. A live edit is rebuilding source geometry again, so it must no
	# longer be treated as a baked, geometry-less chunk by grass regeneration.
	var was_hydrated_mesh := _baked_mesh_is_complete
	_baked_mesh_is_complete = false
	_apply_shadow_visibility_settings()
	_cache_terrain_position_for_thread()
	if _mesh_tiles.is_empty():
		_mark_all_mesh_tiles_dirty()
	_clear_mesh_build_arrays()
	
	_collect_mesh_arrays = false
	generate_terrain_cells(use_threads)
	_collect_mesh_arrays = true
	
	_rebuild_dirty_mesh_tiles()
	_apply_chunk_surface_material()
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	if terrain_system != null and terrain_system.has_method("_queue_chunk_collision_rebuild"):
		terrain_system._queue_chunk_collision_rebuild(chunk_coords)
	else:
		rebuild_collision()
	if grass_mode == GrassMode.GRASS and grass_planter != null and not _scene_save_in_progress:
		var dirty_grass_cells : Array = _dirty_grass_cells.keys()
		_dirty_grass_cells.clear()
		if was_hydrated_mesh:
			# A persisted MultiMesh can contain blades from the old texture
			# state. Rebuild once after the first edit via the progressive full
			# cook path so we do not zero every cell up front.
			grass_planter.regenerate_all_cells_deferred()
		elif not dirty_grass_cells.is_empty():
			grass_planter.queue_cells_for_regeneration(dirty_grass_cells)
	
	if terrain_system != null and terrain_system.has_method("_invalidate_terrain_lod_chunk"):
		terrain_system._invalidate_terrain_lod_chunk(chunk_coords)


func _clear_mesh_build_arrays() -> void:
	_mesh_vertices = PackedVector3Array()
	_mesh_uvs = PackedVector2Array()
	_mesh_uv2s = PackedVector2Array()
	_mesh_colors = PackedColorArray()
	_mesh_custom_0 = PackedFloat32Array()
	_mesh_custom_1 = PackedFloat32Array()
	_mesh_custom_2 = PackedFloat32Array()
	_mesh_floor_flags = PackedByteArray()


func _append_mesh_vertex(
	vert: Vector3,
	uv: Vector2,
	uv2: Vector2,
	color_0: Color,
	color_1: Color,
	custom_1_value: Color,
	mat_blend: Color,
	is_floor: bool,
) -> void:
	if not _collect_mesh_arrays:
		return
	_mesh_vertices.append(vert)
	_mesh_uvs.append(uv)
	_mesh_uv2s.append(uv2)
	_mesh_colors.append(color_0)
	_mesh_custom_0.append(color_1.r)
	_mesh_custom_0.append(color_1.g)
	_mesh_custom_0.append(color_1.b)
	_mesh_custom_0.append(color_1.a)
	_mesh_custom_1.append(custom_1_value.r)
	_mesh_custom_1.append(custom_1_value.g)
	_mesh_custom_1.append(custom_1_value.b)
	_mesh_custom_1.append(custom_1_value.a)
	_mesh_custom_2.append(mat_blend.r)
	_mesh_custom_2.append(mat_blend.g)
	_mesh_custom_2.append(mat_blend.b)
	_mesh_custom_2.append(mat_blend.a)
	_mesh_floor_flags.append(1 if is_floor else 0)


func _build_mesh_surface_arrays() -> Array:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	tool.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	tool.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for vertex_idx in range(_mesh_vertices.size()):
		tool.set_smooth_group(0 if _mesh_floor_flags[vertex_idx] != 0 else -1)
		tool.set_uv(_mesh_uvs[vertex_idx])
		tool.set_uv2(_mesh_uv2s[vertex_idx])
		tool.set_color(_mesh_colors[vertex_idx])
		tool.set_custom(0, Color(_mesh_custom_0[vertex_idx * 4], _mesh_custom_0[vertex_idx * 4 + 1], _mesh_custom_0[vertex_idx * 4 + 2], _mesh_custom_0[vertex_idx * 4 + 3]))
		tool.set_custom(1, Color(_mesh_custom_1[vertex_idx * 4], _mesh_custom_1[vertex_idx * 4 + 1], _mesh_custom_1[vertex_idx * 4 + 2], _mesh_custom_1[vertex_idx * 4 + 3]))
		tool.set_custom(2, Color(_mesh_custom_2[vertex_idx * 4], _mesh_custom_2[vertex_idx * 4 + 1], _mesh_custom_2[vertex_idx * 4 + 2], _mesh_custom_2[vertex_idx * 4 + 3]))
		tool.add_vertex(_mesh_vertices[vertex_idx])
	tool.generate_normals()
	tool.index()
	return tool.commit_to_arrays()


func _mark_all_mesh_tiles_dirty() -> void:
	_dirty_mesh_tiles.clear()
	_dirty_grass_cells.clear()
	var tile_count_x := ceili(float(dimensions.x - 1) / float(MESH_TILE_SIZE))
	var tile_count_z := ceili(float(dimensions.z - 1) / float(MESH_TILE_SIZE))
	for tile_z in range(tile_count_z):
		for tile_x in range(tile_count_x):
			_dirty_mesh_tiles[Vector2i(tile_x, tile_z)] = true
	for cell_z in range(maxi(dimensions.z - 1, 0)):
		for cell_x in range(maxi(dimensions.x - 1, 0)):
			_dirty_grass_cells[Vector2i(cell_x, cell_z)] = true


func _mark_mesh_tile_dirty_for_cell(cell_coords: Vector2i) -> void:
	if cell_coords.x < 0 or cell_coords.y < 0 or cell_coords.x >= dimensions.x - 1 or cell_coords.y >= dimensions.z - 1:
		return
	_dirty_mesh_tiles[Vector2i(cell_coords.x / MESH_TILE_SIZE, cell_coords.y / MESH_TILE_SIZE)] = true
	_dirty_grass_cells[cell_coords] = true


func _build_mesh_surface_arrays_for_tile(tile_coords: Vector2i) -> Array:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	tool.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	tool.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var has_vertices := false
	var start_x := tile_coords.x * MESH_TILE_SIZE
	var start_z := tile_coords.y * MESH_TILE_SIZE
	var end_x := mini(start_x + MESH_TILE_SIZE, dimensions.x - 1)
	var end_z := mini(start_z + MESH_TILE_SIZE, dimensions.z - 1)
	for z in range(start_z, end_z):
		for x in range(start_x, end_x):
			var entry : Dictionary = cell_geometry.get(Vector2i(x, z), {})
			var verts : PackedVector3Array = entry.get("verts", PackedVector3Array())
			var uvs : PackedVector2Array = entry.get("uvs", PackedVector2Array())
			var uv2s : PackedVector2Array = entry.get("uv2s", PackedVector2Array())
			var color_0s : PackedColorArray = entry.get("color_0s", PackedColorArray())
			var color_1s : PackedColorArray = entry.get("color_1s", PackedColorArray())
			var custom_values : PackedColorArray = entry.get("custom_1_values", PackedColorArray())
			var mat_blends : PackedColorArray = entry.get("mat_blend", PackedColorArray())
			var floor_flags : Array = entry.get("is_floor", [])
			for i in range(verts.size()):
				tool.set_smooth_group(0 if bool(floor_flags[i]) else -1)
				tool.set_uv(uvs[i])
				tool.set_uv2(uv2s[i])
				tool.set_color(color_0s[i])
				tool.set_custom(0, color_1s[i])
				tool.set_custom(1, custom_values[i])
				tool.set_custom(2, mat_blends[i])
				tool.add_vertex(verts[i])
				has_vertices = true
	if not has_vertices:
		return []
	tool.generate_normals()
	tool.index()
	return tool.commit_to_arrays()


func _get_or_create_mesh_tile(tile_coords: Vector2i) -> MeshInstance3D:
	var tile : MeshInstance3D = _mesh_tiles.get(tile_coords)
	if tile != null and is_instance_valid(tile):
		return tile
	if tile_coords == Vector2i.ZERO:
		tile = self
	else:
		tile = MeshInstance3D.new()
		tile.name = "MeshTile_%d_%d" % [tile_coords.x, tile_coords.y]
		tile.owner = null
		add_child(tile)
	_mesh_tiles[tile_coords] = tile
	_apply_mesh_tile_visibility(tile)
	return tile


func _apply_mesh_tile_visibility(tile: MeshInstance3D) -> void:
	if tile == null or terrain_system == null:
		return
	if terrain_system.visibility_detail_enabled:
		tile.visibility_range_end = terrain_system.chunk_visibility_end_distance
		tile.visibility_range_end_margin = terrain_system.visibility_range_margin
	else:
		tile.visibility_range_end = 0.0
		tile.visibility_range_end_margin = 0.0


func hydrate_mesh_tiles_from_persisted_mesh(persisted_mesh: Mesh) -> bool:
	if persisted_mesh == null or not is_persisted_mesh_complete(persisted_mesh):
		return false
	if not _mesh_tiles.is_empty():
		return true
	
	var tile_count_x := ceili(float(dimensions.x - 1) / float(MESH_TILE_SIZE))
	var tile_count_z := ceili(float(dimensions.z - 1) / float(MESH_TILE_SIZE))
	var expected_surface_count := tile_count_x * tile_count_z
	if persisted_mesh.get_surface_count() != expected_surface_count:
		print("[MST Persistence] hydrate chunk=%s skipped surfaces=%d expected=%d" % [
			str(chunk_coords),
			persisted_mesh.get_surface_count(),
			expected_surface_count,
		])
		return false
	
	var surface_arrays : Array[Array] = []
	var surface_primitives : Array[int] = []
	var surface_formats : Array[int] = []
	var surface_materials : Array[Material] = []
	for source_surface in range(expected_surface_count):
		var arrays : Array = persisted_mesh.surface_get_arrays(source_surface)
		if arrays.is_empty():
			print("[MST Persistence] hydrate chunk=%s skipped empty_surface=%d" % [
				str(chunk_coords),
				source_surface,
			])
			return false
		surface_arrays.append(arrays)
		surface_primitives.append(persisted_mesh.surface_get_primitive_type(source_surface))
		surface_formats.append(persisted_mesh.surface_get_format(source_surface))
		surface_materials.append(persisted_mesh.surface_get_material(source_surface))
	
	var surface_index := 0
	for tile_z in range(tile_count_z):
		for tile_x in range(tile_count_x):
			var tile_coords := Vector2i(tile_x, tile_z)
			var tile := _get_or_create_mesh_tile(tile_coords)
			var tile_mesh := ArrayMesh.new()
			tile_mesh.add_surface_from_arrays(
				surface_primitives[surface_index],
				surface_arrays[surface_index],
				[],
				{},
				surface_formats[surface_index]
			)
			var material : Material = surface_materials[surface_index]
			if material != null:
				tile_mesh.surface_set_material(0, material)
			tile.mesh = tile_mesh
			surface_index += 1
	
	_dirty_mesh_tiles.clear()
	_baked_mesh_is_complete = true
	print("[MST Persistence] hydrate chunk=%s tiles=%d surfaces=%d" % [
		str(chunk_coords),
		_mesh_tiles.size(),
		persisted_mesh.get_surface_count(),
	])
	return true


func _rebuild_dirty_mesh_tiles() -> void:
	for tile_coords in _dirty_mesh_tiles.keys():
		_rebuild_mesh_tile(tile_coords)
	_dirty_mesh_tiles.clear()


func _rebuild_mesh_tile(tile_coords: Vector2i) -> void:
	var custom_float_format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	custom_float_format |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	custom_float_format |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
	var arrays := _build_mesh_surface_arrays_for_tile(tile_coords)
	var tile := _get_or_create_mesh_tile(tile_coords)
	if arrays.is_empty():
		tile.mesh = null
		return
	var tile_mesh := tile.mesh as ArrayMesh
	if tile_mesh == null:
		tile_mesh = ArrayMesh.new()
	else:
		tile_mesh.clear_surfaces()
	tile_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_float_format)
	tile.mesh = tile_mesh
	if _chunk_surface_material != null:
		tile_mesh.surface_set_material(0, _chunk_surface_material)


func generate_terrain_cells(use_threads: bool):
	if not cell_geometry:
		cell_geometry = {}
	
	var thread_pool: MarchingSquaresThreadPool = null
	if use_threads:
		var worker_count := 1
		if terrain_system != null:
			worker_count = clampi(terrain_system.terrain_generation_threads, 1, 8)
		thread_pool = MarchingSquaresThreadPool.new(worker_count)
	
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			var cell_coords := Vector2i(x, z)
			var work_load : Callable
			# If geometry did not change, copy already generated geometry and skip this cell
			if not needs_update[z][x]:
				# If cached geometry is missing or malformed, fallback to regenerating this cell.
				if not cell_geometry.has(cell_coords) or not _cached_cell_geometry_is_valid(cell_coords):
					needs_update[z][x] = true
					# fall through to generation
					
					# continue to next iteration so generation handles it
					# (avoid executing the cached-copy branch)
					# Note: do NOT call continue here because we want the generation code below to run in this iteration.
					pass
				else:
					if use_threads:
						work_load = func():
							cell_generation_mutex.lock()
							_append_cached_cell_geometry(cell_coords)
							cell_generation_mutex.unlock()
						thread_pool.enqueue(work_load)
					else:
						_append_cached_cell_geometry(cell_coords)
					continue
			
			# Cell is now being updated
			needs_update[z][x] = false
			
			# If geometry did change or none exists yet,
			# Create an entry for this cell (will also override any existing one)
			cell_geometry[cell_coords] = {
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"uv2s": PackedVector2Array(),
				"color_0s": PackedColorArray(),
				"color_1s": PackedColorArray(),
				"custom_1_values": PackedColorArray(),
				"mat_blend": PackedColorArray(),
				"is_floor": [],
			}
			
			var color_helper := MSTVertexColorHelper.new()
			# Defensive: guard against malformed/serialized height_map rows
			var h00 := 0.0
			var h01 := 0.0
			var h10 := 0.0
			var h11 := 0.0
			if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x:
				h00 = float(height_map[z][x])
			if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x+1:
				h01 = float(height_map[z][x+1])
			else:
				h01 = h00
			if height_map is Array and height_map.size() > z+1 and height_map[z+1] is Array and height_map[z+1].size() > x:
				h10 = float(height_map[z+1][x])
			else:
				h10 = h00
			if height_map is Array and height_map.size() > z+1 and height_map[z+1] is Array and height_map[z+1].size() > x+1:
				h11 = float(height_map[z+1][x+1])
			else:
				h11 = h00
			var cell
			if terrain_system != null and terrain_system.prefab_set != null:
				cell = MSTPrefabCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
			else:
				cell = MSTTerrainCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
			color_helper.chunk = self
			color_helper.cell = cell
			
			work_load =  func():
				cell.generate_geometry(cell_coords)
			if use_threads:
				thread_pool.enqueue(work_load)
			else:
				work_load.call()
	
	if use_threads:
		thread_pool.start()
		thread_pool.wait()


func _append_cached_cell_geometry(cell_coords: Vector2i) -> void:
	if not _collect_mesh_arrays:
		return
	var entry: Dictionary = cell_geometry.get(cell_coords, {})
	if not entry.has("verts"):
		return
	var verts : PackedVector3Array = entry["verts"]
	var uvs : PackedVector2Array = entry["uvs"]
	var uv2s : PackedVector2Array = entry["uv2s"]
	var color_0s : PackedColorArray = entry["color_0s"]
	var color_1s : PackedColorArray = entry["color_1s"]
	var custom_1_values : PackedColorArray = entry["custom_1_values"]
	var mat_blend : PackedColorArray = entry["mat_blend"]
	var is_floor : Array = entry["is_floor"]
	for i in range(verts.size()):
		_append_mesh_vertex(verts[i], uvs[i], uv2s[i], color_0s[i], color_1s[i], custom_1_values[i], mat_blend[i], bool(is_floor[i]))


func _cached_cell_geometry_is_valid(cell_coords: Vector2i) -> bool:
	var entry: Dictionary = cell_geometry.get(cell_coords, {})
	if not entry.has("verts") or not entry.has("uvs") or not entry.has("uv2s"):
		return false
	if not entry.has("color_0s") or not entry.has("color_1s") or not entry.has("custom_1_values"):
		return false
	if not entry.has("mat_blend") or not entry.has("is_floor"):
		return false
	var count: int = entry["verts"].size()
	return entry["uvs"].size() == count and entry["uv2s"].size() == count \
		and entry["color_0s"].size() == count and entry["color_1s"].size() == count \
		and entry["custom_1_values"].size() == count and entry["mat_blend"].size() == count \
		and entry["is_floor"].size() == count


func add_polygons(
	cell_coords : Vector2i,
	pts : PackedVector3Array,
	uvs : PackedVector2Array,
	uv2s : PackedVector2Array,
	color_0s : PackedColorArray,
	color_1s : PackedColorArray,
	custom_1_values : PackedColorArray,
	mat_blends : PackedColorArray,
	floors : PackedByteArray,
	):
		assert(pts.size() % 3 == 0)
		assert(pts.size() == uvs.size())
		assert(pts.size() == uv2s.size())
		assert(pts.size() == color_0s.size())
		assert(pts.size() == color_1s.size())
		assert(pts.size() == custom_1_values.size())
		assert(pts.size() == mat_blends.size())
		assert(pts.size() == floors.size())
		
		cell_generation_mutex.lock()
		for i in range(pts.size()):
			_add_point(cell_coords, pts[i], uvs[i], uv2s[i], color_0s[i], color_1s[i], custom_1_values[i], mat_blends[i], floors[i])
		cell_generation_mutex.unlock()


# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func _add_point(cell_coords: Vector2i, vert: Vector3, uv: Vector2, uv2: Vector2, color_0: Color, color_1: Color, custom_1_value: Color, mat_blend: Color, is_floor: bool):
	_append_mesh_vertex(vert, uv, uv2, color_0, color_1, custom_1_value, mat_blend, is_floor)
	
	cell_geometry[cell_coords]["verts"].append(vert)
	cell_geometry[cell_coords]["uvs"].append(uv)
	cell_geometry[cell_coords]["uv2s"].append(uv2)
	cell_geometry[cell_coords]["color_0s"].append(color_0)
	cell_geometry[cell_coords]["color_1s"].append(color_1)
	cell_geometry[cell_coords]["custom_1_values"].append(custom_1_value)
	cell_geometry[cell_coords]["mat_blend"].append(mat_blend)
	cell_geometry[cell_coords]["is_floor"].append(is_floor)

#region cell_geometry generators (on being empty)

func generate_height_map(base_height: float = 0.0):
	height_map = []
	height_map.resize(dimensions.z)
	for z in range(dimensions.z):
		height_map[z] = []
		height_map[z].resize(dimensions.x)
		for x in range(dimensions.x):
			height_map[z][x] = base_height
	
	var noise := terrain_system.noise_hmap
	if noise:
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var noise_x = (chunk_coords.x * (dimensions.x - 1)) + x
				var noise_z = (chunk_coords.y * (dimensions.z -1)) + z
				var noise_sample = noise.get_noise_2d(noise_x, noise_z)
				height_map[z][x] = base_height + (noise_sample * dimensions.y)


func generate_color_maps():
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	color_map_0.resize(dimensions.z * dimensions.x)
	color_map_1.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			color_map_0[z*dimensions.x + x] = Color(0,0,0,0)
			color_map_1[z*dimensions.x + x] = Color(0,0,0,0)


func generate_wall_color_maps():
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	wall_color_map_0.resize(dimensions.z * dimensions.x)
	wall_color_map_1.resize(dimensions.z * dimensions.x)
	var default_idx := 0
	if terrain_system !=  null:
		default_idx = int(terrain_system.default_wall_texture)
	var cols := MSTVertexColorHelper.texture_index_to_colors(default_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			wall_color_map_0[z*dimensions.x + x] = c0
			wall_color_map_1[z*dimensions.x + x] = c1


func apply_default_wall_texture(old_idx: int, new_idx: int) -> bool:
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if old_idx == new_idx:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		var idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		if idx == old_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_unpainted(new_idx: int) -> bool:
	# "Unpainted" is defined as wall map still matching ground map.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if not color_map_0 or not color_map_1:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	var count := min(wall_color_map_0.size(), color_map_0.size())
	for i in range(count):
		var wall_idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		var ground_idx := MSTVertexColorHelper.get_texture_index_from_colors(color_map_0[i], color_map_1[i])
		if wall_idx == ground_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_legacy_init(new_idx: int) -> bool:
	# Legacy wall map initialization used Color(1,0,0,0) for BOTH channels to mean "texture 0".
	# This breaks default wall texture behavior and should be treated as unpainted.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	var legacy := Color(1, 0, 0, 0)
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		if wall_color_map_0[i] == legacy and wall_color_map_1[i] == legacy:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func generate_grass_mask_map():
	grass_mask_map = PackedColorArray()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.x + x] = Color(1.0, 1.0, 1.0, 1.0)

#endregion

#region cell_geometry getters

func get_height(cc: Vector2i) -> float:
	return height_map[cc.y][cc.x]


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cc.y*dimensions.x + cc.x]


func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_0(cc: Vector2i) -> Color:
	return wall_color_map_0[cc.y*dimensions.x + cc.x]


func get_wall_color_1(cc: Vector2i) -> Color:
	return wall_color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_map_state() -> Dictionary:
	return {
		"color_0": wall_color_map_0.duplicate(),
		"color_1": wall_color_map_1.duplicate(),
	}


func get_grass_mask(cc: Vector2i) -> Color:
	return grass_mask_map[cc.y*dimensions.x + cc.x]

#endregion

#region cell_geometry setters

# Draw to height.
# Returns the coordinates of all additional chunks affected by this height change.
# Empty for inner points, neightoring edge for non-corner edges, and 3 other corners for corner points.
func draw_height(x: int, z: int, y: float):
	# Contains chunks that were updated
	height_map[z][x] = y
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_0(x: int, z: int, color: Color):
	wall_color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_1(x: int, z: int, color: Color):
	wall_color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[z*dimensions.x + x] = masked
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func set_wall_color_map_state(state: Dictionary, use_threads: bool = false) -> void:
	wall_color_map_0 = state.get("color_0", PackedColorArray()).duplicate()
	wall_color_map_1 = state.get("color_1", PackedColorArray()).duplicate()
	mark_dirty()
	regenerate_all_cells(use_threads)


func get_wall_paint_stamp_state() -> Dictionary:
	return {
		"positions": wall_paint_stamp_positions.duplicate(),
		"normals": wall_paint_stamp_normals.duplicate(),
		"radii": wall_paint_stamp_radii.duplicate(),
		"texture_indices": wall_paint_stamp_texture_indices.duplicate(),
	}


func set_wall_paint_stamp_state(state: Dictionary) -> void:
	wall_paint_stamp_positions = state.get("positions", PackedVector3Array())
	wall_paint_stamp_normals = state.get("normals", PackedVector3Array())
	wall_paint_stamp_radii = state.get("radii", PackedFloat32Array())
	wall_paint_stamp_texture_indices = state.get("texture_indices", PackedInt32Array())
	mark_dirty()
	_apply_chunk_surface_material()


func append_wall_paint_stamp_to_state(state: Dictionary, world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	var positions : PackedVector3Array = state.get("positions", PackedVector3Array()).duplicate()
	var normals : PackedVector3Array = state.get("normals", PackedVector3Array()).duplicate()
	var radii : PackedFloat32Array = state.get("radii", PackedFloat32Array()).duplicate()
	var texture_indices : PackedInt32Array = state.get("texture_indices", PackedInt32Array()).duplicate()
	if positions.size() >= MAX_WALL_PAINT_STAMPS:
		positions.remove_at(0)
		normals.remove_at(0)
		radii.remove_at(0)
		texture_indices.remove_at(0)
	positions.append(world_pos)
	normals.append(world_normal.normalized())
	radii.append(maxf(radius, 0.001))
	texture_indices.append(clampi(texture_idx, 0, 255))
	return {
		"positions": positions,
		"normals": normals,
		"radii": radii,
		"texture_indices": texture_indices,
	}


func append_wall_paint_stamp(world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	return append_wall_paint_stamp_to_state(get_wall_paint_stamp_state(), world_pos, world_normal, radius, texture_idx)

#endregion


func _apply_chunk_surface_material() -> void:
	if terrain_system == null:
		return
	var base_mat := terrain_system.get_chunk_surface_material()
	var material_to_apply : Material = base_mat
	if base_mat is ShaderMaterial:
		var source_material := base_mat as ShaderMaterial
		var source_revision : int = terrain_system._surface_material_revision
		if _chunk_surface_material == null or _chunk_surface_material_source != source_material or _chunk_surface_material_revision != source_revision:
			_chunk_surface_material = source_material.duplicate()
			_chunk_surface_material_source = source_material
			_chunk_surface_material_revision = source_revision
		_sync_wall_paint_shader_params(_chunk_surface_material)
		material_to_apply = _chunk_surface_material
	for tile in _mesh_tiles.values():
		if tile is MeshInstance3D and tile.mesh != null and tile.mesh.get_surface_count() > 0:
			if tile.mesh.surface_get_material(0) != material_to_apply:
				tile.mesh.surface_set_material(0, material_to_apply)


func refresh_surface_material() -> void:
	_apply_chunk_surface_material()


func needs_mesh_tile_recovery() -> bool:
	return _mesh_tiles.is_empty() and not _baked_mesh_is_complete


func is_mesh_complete_for_storage() -> bool:
	if _initial_build_pending:
		return false
	if build_phase != BuildPhase.IDLE and build_phase != BuildPhase.READY:
		return false
	if not _mesh_tiles.is_empty():
		if not _dirty_mesh_tiles.is_empty():
			return false
		var tile_count_x := ceili(float(dimensions.x - 1) / float(MESH_TILE_SIZE))
		var tile_count_z := ceili(float(dimensions.z - 1) / float(MESH_TILE_SIZE))
		var expected_tiles := tile_count_x * tile_count_z
		if _mesh_tiles.size() < expected_tiles:
			return false
		for tile in _mesh_tiles.values():
			if not is_instance_valid(tile) or tile.mesh == null or tile.mesh.get_surface_count() <= 0:
				return false
		return true
	return _baked_mesh_is_complete and mesh != null


func is_persisted_mesh_complete(mesh_to_check: Mesh) -> bool:
	if mesh_to_check == null:
		return false
	var tile_count_x := ceili(float(dimensions.x - 1) / float(MESH_TILE_SIZE))
	var tile_count_z := ceili(float(dimensions.z - 1) / float(MESH_TILE_SIZE))
	return mesh_to_check.get_surface_count() >= tile_count_x * tile_count_z


func get_persisted_mesh() -> ArrayMesh:
	if _mesh_tiles.is_empty():
		return mesh as ArrayMesh
	var persisted_mesh := ArrayMesh.new()
	for tile_coords in _mesh_tiles.keys():
		var tile : MeshInstance3D = _mesh_tiles[tile_coords]
		if not is_instance_valid(tile) or tile.mesh == null:
			continue
		for surface_idx in range(tile.mesh.get_surface_count()):
			var arrays : Array = tile.mesh.surface_get_arrays(surface_idx)
			if arrays.is_empty():
				continue
			var surface_format : int = tile.mesh.surface_get_format(surface_idx)
			persisted_mesh.add_surface_from_arrays(tile.mesh.surface_get_primitive_type(surface_idx), arrays, [], {}, surface_format)
			var material := tile.mesh.surface_get_material(surface_idx)
			if material != null:
				persisted_mesh.surface_set_material(persisted_mesh.get_surface_count() - 1, material)
	return persisted_mesh


func queue_mesh_regen(use_threads: bool = false) -> void:
	if _mesh_regen_queued:
		return
	_mesh_regen_queued = true
	call_deferred("_run_deferred_mesh_regen", use_threads)


func _run_deferred_mesh_regen(use_threads: bool = false) -> void:
	_mesh_regen_queued = false
	if not is_inside_tree():
		return
	regenerate_mesh(use_threads)


func begin_deferred_initial_build() -> void:
	if _initial_build_pending or not is_inside_tree():
		return
	# Scene-tree transforms must be read on the main thread before the worker starts.
	_cache_terrain_position_for_thread()
	_mark_all_mesh_tiles_dirty()
	_initial_build_pending = true
	build_phase = BuildPhase.GENERATING_CELLS
	visible = false
	if terrain_system != null and terrain_system.has_method("_queue_initial_chunk_build"):
		terrain_system._queue_initial_chunk_build(self)
		return
	_start_deferred_initial_build_thread()


func _start_deferred_initial_build_thread() -> void:
	if _initial_build_thread != null or not _initial_build_pending:
		return
	_initial_build_thread = Thread.new()
	_initial_build_thread.start(_run_deferred_initial_cell_generation)


func _cache_terrain_position_for_thread() -> void:
	terrain_position_cached = position


func wait_for_initial_build() -> void:
	# Legacy name: joins the worker, then releases the terrain build gate.
	abort_initial_build()


func abort_initial_build() -> void:
	var was_pending := _initial_build_pending or _initial_build_thread != null or not _initial_build_tile_queue.is_empty()
	if _initial_build_thread != null:
		_initial_build_thread.wait_to_finish()
		_initial_build_thread = null
	_initial_build_pending = false
	_initial_build_tile_queue.clear()
	if build_phase != BuildPhase.IDLE and build_phase != BuildPhase.READY:
		build_phase = BuildPhase.READY
	if terrain_system != null and terrain_system.has_method("_remove_from_initial_chunk_build_queue"):
		terrain_system._remove_from_initial_chunk_build_queue(self)
	# Always release the serialized build gate when aborting. Leaving
	# `_initial_chunk_build_active` set permanently blocks all future chunk adds.
	if was_pending and terrain_system != null and terrain_system.has_method("_initial_chunk_build_finished"):
		terrain_system._initial_chunk_build_finished(self)


func _release_initial_build_gate() -> void:
	_initial_build_pending = false
	_initial_build_tile_queue.clear()
	if build_phase != BuildPhase.IDLE and build_phase != BuildPhase.READY:
		build_phase = BuildPhase.READY
	if terrain_system != null and terrain_system.has_method("_initial_chunk_build_finished"):
		terrain_system._initial_chunk_build_finished(self)


func prepare_for_storage() -> bool:
	if not is_inside_tree():
		return is_mesh_complete_for_storage()

	# A worker may have finished cell generation while deferred tile publication
	# is still waiting in the idle queue. Complete both phases before exporting.
	if _initial_build_thread != null:
		_initial_build_thread.wait_to_finish()
		_initial_build_thread = null

	if not _initial_build_tile_queue.is_empty():
		while not _initial_build_tile_queue.is_empty():
			_rebuild_mesh_tile(_initial_build_tile_queue.pop_front())
	elif _initial_build_pending or not _dirty_mesh_tiles.is_empty():
		for tile_coords in _dirty_mesh_tiles.keys():
			_rebuild_mesh_tile(tile_coords)

	_dirty_mesh_tiles.clear()
	if build_phase != BuildPhase.IDLE and build_phase != BuildPhase.READY:
		rebuild_collision()
		build_phase = BuildPhase.READY
		visible = true
		if terrain_system != null and terrain_system.has_method("_initial_chunk_build_finished"):
			terrain_system._initial_chunk_build_finished(self)
	_initial_build_pending = false
	_apply_chunk_surface_material()
	if terrain_system != null and terrain_system.storage_mode != MarchingSquaresTerrain.StorageMode.BAKED:
		return true
	return is_mesh_complete_for_storage()


func _run_deferred_initial_cell_generation() -> void:
	_collect_mesh_arrays = false
	# This function already runs on the chunk's dedicated background thread.
	# Spawning one WorkerThreadPool task per cell here oversubscribes the editor
	# CPU and causes severe input/frame hitches while a chunk is added.
	generate_terrain_cells(false)
	_collect_mesh_arrays = true
	call_deferred("_finish_deferred_initial_build")


func _finish_deferred_initial_build() -> void:
	if _initial_build_thread != null:
		_initial_build_thread.wait_to_finish()
	_initial_build_thread = null
	if not _initial_build_pending:
		# Aborted while the worker was finishing; gate already released.
		return
	if not is_inside_tree():
		_release_initial_build_gate()
		return
	_initial_build_tile_queue.clear()
	for tile_coords in _dirty_mesh_tiles.keys():
		_initial_build_tile_queue.append(tile_coords)
	_dirty_mesh_tiles.clear()
	build_phase = BuildPhase.PUBLISHING_TILES
	# Initialize the cached material once before tile publication. Each tile then
	# receives that material directly instead of refreshing the entire chunk.
	_apply_chunk_surface_material()
	_commit_next_initial_mesh_tile()


func _commit_next_initial_mesh_tile() -> void:
	if not _initial_build_pending:
		return
	if not is_inside_tree():
		_release_initial_build_gate()
		return
	var frame_start_usec := Time.get_ticks_usec()
	var budget_usec := 8000
	if terrain_system != null:
		budget_usec = maxi(int(terrain_system.initial_mesh_tile_budget_msec * 1000.0), 100)
	while not _initial_build_tile_queue.is_empty():
		_rebuild_mesh_tile(_initial_build_tile_queue.pop_front())
		if Time.get_ticks_usec() - frame_start_usec >= budget_usec:
			break
	if not _initial_build_tile_queue.is_empty():
		# Keep publication frame-budgeted. A deferred call can otherwise be
		# drained repeatedly in one idle cycle and recreate the editor hitch.
		await get_tree().process_frame
		if not _initial_build_pending:
			return
		if not is_inside_tree():
			_release_initial_build_gate()
			return
		_commit_next_initial_mesh_tile()
		return
	_apply_chunk_surface_material()
	# Mesh is usable now. Release the serialized build gate so the next chunk
	# can start while collision/grass finish in the background.
	_initial_build_pending = false
	build_phase = BuildPhase.READY
	visible = true
	if terrain_system != null and terrain_system.has_method("_invalidate_terrain_lod_chunk"):
		terrain_system._invalidate_terrain_lod_chunk(chunk_coords)
	if terrain_system != null and terrain_system.has_method("_initial_chunk_build_finished"):
		terrain_system._initial_chunk_build_finished(self)
	call_deferred("_finish_deferred_initial_collision")


func _finish_deferred_initial_collision() -> void:
	if not is_inside_tree():
		return
	if terrain_system != null and terrain_system.has_method("_queue_chunk_collision_rebuild"):
		terrain_system._queue_chunk_collision_rebuild(chunk_coords)
	else:
		rebuild_collision()
	if grass_mode == GrassMode.GRASS and grass_planter != null and _temp_grass_multimesh == null:
		_queue_grass_regen()
	elif grass_mode == GrassMode.GRASS and grass_planter == null:
		call_deferred("_finish_deferred_grass_setup")
	else:
		call_deferred("_finish_deferred_initial_ready")


func _finish_deferred_initial_ready() -> void:
	if not is_inside_tree():
		return
	# A newly-created chunk may have allocated its planter before it entered
	# the scene tree. Ensure that deferred grass is still kicked once the mesh
	# is published; painting should not be required to wake it up.
	if grass_mode == GrassMode.GRASS and grass_planter == null:
		_ensure_grass_planter()
	if grass_mode == GrassMode.GRASS and is_instance_valid(grass_planter):
		# Never reveal a partial cook — virgin identity slots become giant grass piles.
		if grass_planter._deferred_grass_pending:
			pass
		elif MarchingSquaresGrassPlanter.is_multimesh_cooked(grass_planter.multimesh):
			grass_planter.reveal_cooked_multimesh()
		else:
			_queue_grass_regen()
	visible = true
	if terrain_system != null and terrain_system.has_method("_invalidate_terrain_lod_chunk"):
		terrain_system._invalidate_terrain_lod_chunk(chunk_coords)


func _finish_deferred_grass_setup() -> void:
	if not is_inside_tree() or grass_mode != GrassMode.GRASS or grass_planter != null:
		return
	_ensure_grass_planter()
	_queue_grass_regen()


func _queue_grass_regen() -> void:
	if _grass_regen_queued:
		return
	_grass_regen_queued = true
	call_deferred("_run_deferred_grass_regen")


func _run_deferred_grass_regen() -> void:
	_grass_regen_queued = false
	if _scene_save_in_progress or grass_mode != GrassMode.GRASS or not is_inside_tree() or not is_instance_valid(grass_planter):
		return
	grass_planter.regenerate_all_cells_deferred()


func _sync_wall_paint_shader_params(mat: ShaderMaterial) -> void:
	var positions : Array[Vector4] = []
	var data_b : Array[Vector4] = []
	var stamp_count := min(
		wall_paint_stamp_positions.size(),
		min(wall_paint_stamp_normals.size(), min(wall_paint_stamp_radii.size(), wall_paint_stamp_texture_indices.size()))
	)
	stamp_count = mini(stamp_count, MAX_WALL_PAINT_STAMPS)
	for i in range(MAX_WALL_PAINT_STAMPS):
		if i < stamp_count:
			var p := wall_paint_stamp_positions[i]
			var n := wall_paint_stamp_normals[i].normalized()
			positions.append(Vector4(p.x, p.y, p.z, float(wall_paint_stamp_radii[i])))
			data_b.append(Vector4(n.x, n.y, n.z, float(wall_paint_stamp_texture_indices[i])))
		else:
			positions.append(Vector4.ZERO)
			data_b.append(Vector4.ZERO)
	mat.set_shader_parameter("wall_paint_count", stamp_count)
	mat.set_shader_parameter("wall_paint_stamps_a", positions)
	mat.set_shader_parameter("wall_paint_stamps_b", data_b)
	mat.set_shader_parameter("wall_paint_plane_thickness", maxf(minf(cell_size.x, cell_size.y) * 0.08, 0.03))
	mat.set_shader_parameter("wall_paint_blend_width", maxf(minf(cell_size.x, cell_size.y) * 0.18, 0.06))


func notify_needs_update(z: int, x: int):
	if z < 0 or z >=  terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return
	
	needs_update[z][x] = true
	_mark_mesh_tile_dirty_for_cell(Vector2i(x, z))


## Mark chunk as having modified source data - triggers save in MSTDataHandler.
func mark_dirty() -> void:
	_data_dirty = true
	if terrain_system != null and terrain_system.has_method("invalidate_navmesh_preview"):
		terrain_system.invalidate_navmesh_preview()
	if terrain_system != null and terrain_system.has_method("invalidate_navmesh_chunk"):
		terrain_system.invalidate_navmesh_chunk(chunk_coords)


func force_full_collision_rebuild() -> void:
	_temp_collision_shapes.clear()
	regenerate_mesh(false)


func get_collision_triangle_count() -> int:
	var total := 0
	for child in get_children():
		if child is StaticBody3D:
			for shape_child in child.get_children():
				if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
					total += int(shape_child.shape.get_faces().size() / 3)
	return total


func rebuild_collision() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	var shape := _create_simplified_collision_shape()
	if shape == null:
		return
	_create_collision_body_from_shape(shape)
	_apply_collision_layers()


func _create_simplified_collision_shape() -> ConcavePolygonShape3D:
	if terrain_system == null:
		return null
	return _create_simplified_proxy_collision_shape()


func get_nav_walkable_faces(max_slope_degrees: float) -> PackedVector3Array:
	return get_nav_walkable_faces_for_permission(max_slope_degrees, null)


func get_nav_walkable_faces_for_permission(max_slope_degrees: float, permission: Variant) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var fallback_faces := PackedVector3Array()
	if not cell_geometry:
		return faces
	
	var max_angle := deg_to_rad(clampf(max_slope_degrees, 0.0, 89.0))
	var up := Vector3.UP
	var min_triangle_area := maxf(cell_size.x * cell_size.y * 0.00005, 0.000001)
	var chunk_max_x := float(dimensions.x - 1) * cell_size.x
	var chunk_max_z := float(dimensions.z - 1) * cell_size.y
	var seam_snap_epsilon := maxf(minf(cell_size.x, cell_size.y) * 0.001, 0.0001)
	var seen_triangles := {}
	for entry_key in cell_geometry.keys():
		if permission != null:
			if not (entry_key is Vector2i):
				continue
			var cell_index: int = entry_key.y * maxi(dimensions.x - 1, 1) + entry_key.x
			if cell_index < 0 or cell_index >= permission.size() or permission[cell_index] == 0:
				continue
		var entry = cell_geometry[entry_key]
		if not entry.has("verts") or not entry.has("is_floor"):
			continue
		var verts : PackedVector3Array = entry["verts"]
		var is_floor : Array = entry["is_floor"]
		if verts.is_empty() or is_floor.is_empty():
			continue
		
		var tri_count := int(verts.size() / 3)
		for tri_idx in range(tri_count):
			var base := tri_idx * 3
			if base + 2 >= verts.size() or base + 2 >= is_floor.size():
				break
			if not (bool(is_floor[base]) and bool(is_floor[base + 1]) and bool(is_floor[base + 2])):
				continue
			
			var a := verts[base]
			var b := verts[base + 1]
			var c := verts[base + 2]
			fallback_faces.append(a)
			fallback_faces.append(b)
			fallback_faces.append(c)
			
			a = _snap_nav_vertex_to_chunk_bounds(a, chunk_max_x, chunk_max_z, seam_snap_epsilon)
			b = _snap_nav_vertex_to_chunk_bounds(b, chunk_max_x, chunk_max_z, seam_snap_epsilon)
			c = _snap_nav_vertex_to_chunk_bounds(c, chunk_max_x, chunk_max_z, seam_snap_epsilon)
			
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area < min_triangle_area:
				continue
			
			var normal := cross.normalized()
			if normal.length_squared() <= 0.000001:
				continue
			if normal.dot(up) <= 0.0:
				continue
			var slope_angle := acos(clampf(normal.dot(up), -1.0, 1.0))
			if slope_angle > max_angle:
				continue
			
			var triangle_key := _make_nav_triangle_key(a, b, c)
			if seen_triangles.has(triangle_key):
				continue
			seen_triangles[triangle_key] = true
			
			faces.append(a)
			faces.append(b)
			faces.append(c)
	
	if faces.is_empty() and not fallback_faces.is_empty():
		return fallback_faces
	return faces


func _snap_nav_vertex_to_chunk_bounds(vertex: Vector3, max_x: float, max_z: float, epsilon: float) -> Vector3:
	var snapped := vertex
	if absf(snapped.x) <= epsilon:
		snapped.x = 0.0
	elif absf(snapped.x - max_x) <= epsilon:
		snapped.x = max_x
	
	if absf(snapped.z) <= epsilon:
		snapped.z = 0.0
	elif absf(snapped.z - max_z) <= epsilon:
		snapped.z = max_z
	
	return snapped


func _make_nav_triangle_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var points := [
		"%d,%d,%d" % [roundi(a.x * 1000.0), roundi(a.y * 1000.0), roundi(a.z * 1000.0)],
		"%d,%d,%d" % [roundi(b.x * 1000.0), roundi(b.y * 1000.0), roundi(b.z * 1000.0)],
		"%d,%d,%d" % [roundi(c.x * 1000.0), roundi(c.y * 1000.0), roundi(c.z * 1000.0)],
	]
	points.sort()
	return "|".join(points)


func _create_simplified_proxy_collision_shape() -> ConcavePolygonShape3D:
	if not (height_map is Array) or height_map.size() < dimensions.z:
		return null
	
	var faces : Array[Vector3] = []
	var base_height := INF
	for z in range(dimensions.z):
		if z >= height_map.size() or not (height_map[z] is Array):
			return null
		var row : Array = height_map[z]
		if row.size() < dimensions.x:
			return null
		for x in range(dimensions.x):
			base_height = minf(base_height, float(row[x]))
	
	var extra_thickness := terrain_system.collision_thickness
	base_height -= extra_thickness
	var cell_rows := dimensions.z - 1
	var cell_cols := dimensions.x - 1
	var merged_cells: Array = []
	merged_cells.resize(cell_rows)
	for z in range(cell_rows):
		merged_cells[z] = []
		merged_cells[z].resize(cell_cols)
		for x in range(cell_cols):
			merged_cells[z][x] = false
	
	for z in range(cell_rows):
		for x in range(cell_cols):
			if bool(merged_cells[z][x]):
				continue
			
			var flat_height := _get_flat_cell_height(z, x)
			if flat_height == null:
				_append_cell_top_surface(faces, z, x)
				_append_exact_cell_wall_triangles(faces, Vector2i(x, z))
				continue
			if _should_keep_flat_cell_unmerged(z, x, float(flat_height)):
				merged_cells[z][x] = true
				_append_cell_top_surface(faces, z, x)
				_append_merged_wall_strips(faces, z, x, 1, 1, float(flat_height), base_height)
				continue
			
			var width := 1
			while x + width < cell_cols:
				if bool(merged_cells[z][x + width]):
					break
				if _get_flat_cell_height(z, x + width) != flat_height:
					break
				if _should_keep_flat_cell_unmerged(z, x + width, float(flat_height)):
					break
				width += 1
			
			var depth := 1
			var can_extend := true
			while z + depth < cell_rows and can_extend:
				for check_x in range(x, x + width):
					if bool(merged_cells[z + depth][check_x]):
						can_extend = false
						break
					if _get_flat_cell_height(z + depth, check_x) != flat_height:
						can_extend = false
						break
					if _should_keep_flat_cell_unmerged(z + depth, check_x, float(flat_height)):
						can_extend = false
						break
				if can_extend:
					depth += 1
			
			for mark_z in range(z, z + depth):
				for mark_x in range(x, x + width):
					merged_cells[mark_z][mark_x] = true
			
			_append_merged_top_surface(faces, z, x, width, depth, float(flat_height))
			_append_merged_wall_strips(faces, z, x, width, depth, float(flat_height), base_height)
	
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			if is_zero_approx(extra_thickness):
				continue
			
			var x0 := float(x) * cell_size.x
			var x1 := float(x + 1) * cell_size.x
			var z0 := float(z) * cell_size.y
			var z1 := float(z + 1) * cell_size.y
			var p00 := Vector3(x0, float(height_map[z][x]), z0)
			var p10 := Vector3(x1, float(height_map[z][x + 1]), z0)
			var p01 := Vector3(x0, float(height_map[z + 1][x]), z1)
			var p11 := Vector3(x1, float(height_map[z + 1][x + 1]), z1)
			var b00 := Vector3(x0, base_height, z0)
			var b10 := Vector3(x1, base_height, z0)
			var b01 := Vector3(x0, base_height, z1)
			var b11 := Vector3(x1, base_height, z1)
			
			if z == 0:
				_append_proxy_quad(faces, p10, p00, b00, b10)
			if x == 0:
				_append_proxy_quad(faces, p00, p01, b01, b00)
			if x == dimensions.x - 2:
				_append_proxy_quad(faces, p11, p10, b10, b11)
			if z == dimensions.z - 2:
				_append_proxy_quad(faces, p01, p11, b11, b01)
	
	if not is_zero_approx(extra_thickness):
		var chunk_max_x := float(dimensions.x - 1) * cell_size.x
		var chunk_max_z := float(dimensions.z - 1) * cell_size.y
		var b00 := Vector3(0.0, base_height, 0.0)
		var b10 := Vector3(chunk_max_x, base_height, 0.0)
		var b01 := Vector3(0.0, base_height, chunk_max_z)
		var b11 := Vector3(chunk_max_x, base_height, chunk_max_z)
		_append_proxy_quad(faces, b01, b11, b10, b00)
	
	if faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PackedVector3Array(faces))
	return shape


func _get_flat_cell_height(z: int, x: int) -> Variant:
	var h00 := float(height_map[z][x])
	var h10 := float(height_map[z][x + 1])
	var h01 := float(height_map[z + 1][x])
	var h11 := float(height_map[z + 1][x + 1])
	if is_equal_approx(h00, h10) and is_equal_approx(h00, h01) and is_equal_approx(h00, h11):
		return h00
	return null


func _should_keep_flat_cell_unmerged(z: int, x: int, flat_height: float) -> bool:
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var info := _get_adjacent_edge_info(z, x, dir)
		if not bool(info.get("has_cell", false)):
			continue
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return true
		if not is_equal_approx(float(neighbor_height), flat_height):
			return true
	return false


func _append_cell_top_surface(faces: Array[Vector3], z: int, x: int) -> void:
	if _append_exact_cell_floor_triangles(faces, Vector2i(x, z)):
		return
	var x0 := float(x) * cell_size.x
	var x1 := float(x + 1) * cell_size.x
	var z0 := float(z) * cell_size.y
	var z1 := float(z + 1) * cell_size.y
	var p00 := Vector3(x0, float(height_map[z][x]), z0)
	var p10 := Vector3(x1, float(height_map[z][x + 1]), z0)
	var p01 := Vector3(x0, float(height_map[z + 1][x]), z1)
	var p11 := Vector3(x1, float(height_map[z + 1][x + 1]), z1)
	_append_top_surface_cell(faces, p00, p10, p11, p01)


func _append_exact_cell_floor_triangles(faces: Array[Vector3], cell_coords: Vector2i) -> bool:
	if not cell_geometry.has(cell_coords):
		return false
	var entry = cell_geometry[cell_coords]
	if not entry.has("verts") or not entry.has("is_floor"):
		return false
	var verts: PackedVector3Array = entry["verts"]
	var is_floor: Array = entry["is_floor"]
	if verts.is_empty() or is_floor.is_empty():
		return false
	
	var appended := false
	var tri_count := int(verts.size() / 3)
	for tri_idx in range(tri_count):
		var base := tri_idx * 3
		if base + 2 >= verts.size() or base + 2 >= is_floor.size():
			break
		if not (bool(is_floor[base]) and bool(is_floor[base + 1]) and bool(is_floor[base + 2])):
			continue
		faces.append(verts[base])
		faces.append(verts[base + 1])
		faces.append(verts[base + 2])
		appended = true
	return appended


func _append_exact_cell_wall_triangles(faces: Array[Vector3], cell_coords: Vector2i) -> bool:
	if not cell_geometry.has(cell_coords):
		return false
	var entry = cell_geometry[cell_coords]
	if not entry.has("verts") or not entry.has("is_floor"):
		return false
	var verts : PackedVector3Array = entry["verts"]
	var is_floor : Array = entry["is_floor"]
	if verts.is_empty() or is_floor.is_empty():
		return false
	
	var appended := false
	var tri_count := int(verts.size() / 3)
	for tri_idx in range(tri_count):
		var base := tri_idx * 3
		if base + 2 >= verts.size() or base + 2 >= is_floor.size():
			break
		if bool(is_floor[base]) and bool(is_floor[base + 1]) and bool(is_floor[base + 2]):
			continue
		if _is_wall_triangle_on_valid_neighbor_seam(verts[base], verts[base + 1], verts[base + 2]):
			continue
		faces.append(verts[base])
		faces.append(verts[base + 1])
		faces.append(verts[base + 2])
		appended = true
	return appended


func _append_merged_top_surface(faces: Array[Vector3], start_z: int, start_x: int, width: int, depth: int, height: float) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(start_x + width) * cell_size.x
	var z0 := float(start_z) * cell_size.y
	var z1 := float(start_z + depth) * cell_size.y
	var p00 := Vector3(x0, height, z0)
	var p10 := Vector3(x1, height, z0)
	var p01 := Vector3(x0, height, z1)
	var p11 := Vector3(x1, height, z1)
	_append_top_surface_cell(faces, p00, p10, p11, p01)


func _append_merged_wall_strips(faces: Array[Vector3], start_z: int, start_x: int, width: int, depth: int, top_height: float, fallback_bottom: float) -> void:
	_append_horizontal_edge_walls(faces, start_z, start_x, width, top_height, fallback_bottom, true)
	_append_horizontal_edge_walls(faces, start_z + depth - 1, start_x, width, top_height, fallback_bottom, false)
	_append_vertical_edge_walls(faces, start_z, start_x, depth, top_height, fallback_bottom, true)
	_append_vertical_edge_walls(faces, start_z, start_x + width - 1, depth, top_height, fallback_bottom, false)


func _append_horizontal_edge_walls(faces: Array[Vector3], z: int, start_x: int, width: int, top_height: float, fallback_bottom: float, north: bool) -> void:
	if _edge_has_valid_neighbor_chunk_horizontal(z, start_x, width, north):
		return
	var merged_bottom = _try_get_flat_horizontal_edge_bottom(z, start_x, width, north, fallback_bottom)
	if merged_bottom != null:
		if float(merged_bottom) < top_height:
			_append_horizontal_wall_quad(faces, start_x, start_x + width, z if north else z + 1, top_height, float(merged_bottom), north)
		return

	for x in range(start_x, start_x + width):
		var info := _get_adjacent_edge_info(z, x, Vector2i(0, -1 if north else 1))
		if not bool(info.get("has_cell", false)) or bool(info.get("has_neighbor_chunk", false)):
			continue
		var bottom_a := fallback_bottom
		var bottom_b := fallback_bottom
		bottom_a = minf(top_height, float(info.get("edge_start", top_height)))
		bottom_b = minf(top_height, float(info.get("edge_end", top_height)))
		if bottom_a < top_height or bottom_b < top_height:
			_append_horizontal_wall_segment_quad(faces, x, x + 1, z if north else z + 1, top_height, bottom_a, bottom_b, north)


func _append_vertical_edge_walls(faces: Array[Vector3], start_z: int, x: int, depth: int, top_height: float, fallback_bottom: float, west: bool) -> void:
	if _edge_has_valid_neighbor_chunk_vertical(start_z, x, depth, west):
		return
	var merged_bottom = _try_get_flat_vertical_edge_bottom(start_z, x, depth, west, fallback_bottom)
	if merged_bottom != null:
		if float(merged_bottom) < top_height:
			_append_vertical_wall_quad(faces, start_z, start_z + depth, x if west else x + 1, top_height, float(merged_bottom), west)
		return
	
	for z in range(start_z, start_z + depth):
		var info := _get_adjacent_edge_info(z, x, Vector2i(-1 if west else 1, 0))
		if not bool(info.get("has_cell", false)) or bool(info.get("has_neighbor_chunk", false)):
			continue
		var bottom_a := fallback_bottom
		var bottom_b := fallback_bottom
		bottom_a = minf(top_height, float(info.get("edge_start", top_height)))
		bottom_b = minf(top_height, float(info.get("edge_end", top_height)))
		if bottom_a < top_height or bottom_b < top_height:
			_append_vertical_wall_segment_quad(faces, z, z + 1, x if west else x + 1, top_height, bottom_a, bottom_b, west)


func _try_get_flat_horizontal_edge_bottom(z: int, start_x: int, width: int, north: bool, fallback_bottom: float) -> Variant:
	var bottom: Variant = null
	for x in range(start_x, start_x + width):
		var info := _get_adjacent_edge_info(z, x, Vector2i(0, -1 if north else 1))
		if not bool(info.get("has_cell", false)):
			return null
		if bool(info.get("has_neighbor_chunk", false)):
			return null
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return null
		if bottom == null:
			bottom = neighbor_height
		elif not is_equal_approx(float(bottom), float(neighbor_height)):
			return null
	return bottom


func _try_get_flat_vertical_edge_bottom(start_z: int, x: int, depth: int, west: bool, fallback_bottom: float) -> Variant:
	var bottom : Variant = null
	for z in range(start_z, start_z + depth):
		var info := _get_adjacent_edge_info(z, x, Vector2i(-1 if west else 1, 0))
		if not bool(info.get("has_cell", false)):
			return null
		if bool(info.get("has_neighbor_chunk", false)):
			return null
		var neighbor_height = info.get("flat_height", null)
		if neighbor_height == null:
			return null
		if bottom == null:
			bottom = neighbor_height
		elif not is_equal_approx(float(bottom), float(neighbor_height)):
			return null
	return bottom


func _get_adjacent_edge_info(local_z: int, local_x: int, dir: Vector2i) -> Dictionary:
	var info := {
		"has_cell": false,
		"has_neighbor_chunk": false,
		"flat_height": null,
		"edge_start": 0.0,
		"edge_end": 0.0,
	}
	var target_z := local_z + dir.y
	var target_x := local_x + dir.x
	info["edge_start"] = _get_shared_edge_vertex_height(local_z, local_x, dir, false)
	info["edge_end"] = _get_shared_edge_vertex_height(local_z, local_x, dir, true)
	if target_x >= 0 and target_x < dimensions.x - 1 and target_z >= 0 and target_z < dimensions.z - 1:
		info["has_cell"] = true
		info["flat_height"] = _get_flat_cell_height(target_z, target_x)
		return info
	
	if terrain_system == null:
		return info
	
	var chunk_dx := 0
	var chunk_dy := 0
	if target_x < 0:
		chunk_dx = -1
		target_x = dimensions.x - 2
	elif target_x >= dimensions.x - 1:
		chunk_dx = 1
		target_x = 0
	
	if target_z < 0:
		chunk_dy = -1
		target_z = dimensions.z - 2
	elif target_z >= dimensions.z - 1:
		chunk_dy = 1
		target_z = 0
	
	var neighbor_chunk : MarchingSquaresTerrainChunk = terrain_system.chunks.get(chunk_coords + Vector2i(chunk_dx, chunk_dy))
	if neighbor_chunk == null or not is_instance_valid(neighbor_chunk):
		return info
	
	info["has_cell"] = true
	info["has_neighbor_chunk"] = true
	info["flat_height"] = _get_flat_cell_height_from_chunk(neighbor_chunk, target_z, target_x)
	return info


func _edge_has_valid_neighbor_chunk_horizontal(z: int, start_x: int, width: int, north: bool) -> bool:
	for x in range(start_x, start_x + width):
		var info := _get_adjacent_edge_info(z, x, Vector2i(0, -1 if north else 1))
		if bool(info.get("has_neighbor_chunk", false)):
			return true
	return false


func _edge_has_valid_neighbor_chunk_vertical(start_z: int, x: int, depth: int, west: bool) -> bool:
	for z in range(start_z, start_z + depth):
		var info := _get_adjacent_edge_info(z, x, Vector2i(-1 if west else 1, 0))
		if bool(info.get("has_neighbor_chunk", false)):
			return true
	return false


func _is_wall_triangle_on_valid_neighbor_seam(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var epsilon := maxf(minf(cell_size.x, cell_size.y) * 0.001, 0.0001)
	var chunk_max_x := float(dimensions.x - 1) * cell_size.x
	var chunk_max_z := float(dimensions.z - 1) * cell_size.y
	if absf(a.x) <= epsilon and absf(b.x) <= epsilon and absf(c.x) <= epsilon:
		if _has_valid_neighbor_chunk(Vector2i(-1, 0)):
			return true
	if absf(a.x - chunk_max_x) <= epsilon and absf(b.x - chunk_max_x) <= epsilon and absf(c.x - chunk_max_x) <= epsilon:
		if _has_valid_neighbor_chunk(Vector2i(1, 0)):
			return true
	if absf(a.z) <= epsilon and absf(b.z) <= epsilon and absf(c.z) <= epsilon:
		if _has_valid_neighbor_chunk(Vector2i(0, -1)):
			return true
	if absf(a.z - chunk_max_z) <= epsilon and absf(b.z - chunk_max_z) <= epsilon and absf(c.z - chunk_max_z) <= epsilon:
		if _has_valid_neighbor_chunk(Vector2i(0, 1)):
			return true
	return false


func _has_valid_neighbor_chunk(direction: Vector2i) -> bool:
	if terrain_system == null:
		return false
	var neighbor_chunk: MarchingSquaresTerrainChunk = terrain_system.chunks.get(chunk_coords + direction)
	return neighbor_chunk != null and is_instance_valid(neighbor_chunk)


func _get_adjacent_flat_cell_height(local_z: int, local_x: int, dir: Vector2i) -> Variant:
	var info := _get_adjacent_edge_info(local_z, local_x, dir)
	if not bool(info.get("has_cell", false)):
		return null
	return info.get("flat_height", null)


func _get_shared_edge_vertex_height(local_z: int, local_x: int, dir: Vector2i, second_vertex: bool) -> float:
	if dir.y < 0:
		return float(height_map[local_z][local_x + (1 if second_vertex else 0)])
	if dir.y > 0:
		return float(height_map[local_z + 1][local_x + (1 if second_vertex else 0)])
	if dir.x < 0:
		return float(height_map[local_z + (1 if second_vertex else 0)][local_x])
	return float(height_map[local_z + (1 if second_vertex else 0)][local_x + 1])


func _get_flat_cell_height_from_chunk(chunk: MarchingSquaresTerrainChunk, z: int, x: int) -> Variant:
	if chunk == null or not (chunk.height_map is Array) or chunk.height_map.size() <= z + 1:
		return null
	if not (chunk.height_map[z] is Array) or not (chunk.height_map[z + 1] is Array):
		return null
	if chunk.height_map[z].size() <= x + 1 or chunk.height_map[z + 1].size() <= x + 1:
		return null
	var h00 := float(chunk.height_map[z][x])
	var h10 := float(chunk.height_map[z][x + 1])
	var h01 := float(chunk.height_map[z + 1][x])
	var h11 := float(chunk.height_map[z + 1][x + 1])
	if is_equal_approx(h00, h10) and is_equal_approx(h00, h01) and is_equal_approx(h00, h11):
		return h00
	return null


func _append_horizontal_wall_quad(faces: Array[Vector3], start_x: int, end_x: int, z: int, top_height: float, bottom_height: float, north: bool) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(end_x) * cell_size.x
	var world_z := float(z) * cell_size.y
	var top_a := Vector3(x0, top_height, world_z)
	var top_b := Vector3(x1, top_height, world_z)
	var bottom_a := Vector3(x0, bottom_height, world_z)
	var bottom_b := Vector3(x1, bottom_height, world_z)
	if north:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)
	else:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)


func _append_horizontal_wall_segment_quad(faces: Array[Vector3], start_x: int, end_x: int, z: int, top_height: float, bottom_a_height: float, bottom_b_height: float, north: bool) -> void:
	var x0 := float(start_x) * cell_size.x
	var x1 := float(end_x) * cell_size.x
	var world_z := float(z) * cell_size.y
	var top_a := Vector3(x0, top_height, world_z)
	var top_b := Vector3(x1, top_height, world_z)
	var bottom_a := Vector3(x0, bottom_a_height, world_z)
	var bottom_b := Vector3(x1, bottom_b_height, world_z)
	if north:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)
	else:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)


func _append_vertical_wall_quad(faces: Array[Vector3], start_z: int, end_z: int, x: int, top_height: float, bottom_height: float, west: bool) -> void:
	var z0 := float(start_z) * cell_size.y
	var z1 := float(end_z) * cell_size.y
	var world_x := float(x) * cell_size.x
	var top_a := Vector3(world_x, top_height, z0)
	var top_b := Vector3(world_x, top_height, z1)
	var bottom_a := Vector3(world_x, bottom_height, z0)
	var bottom_b := Vector3(world_x, bottom_height, z1)
	if west:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)
	else:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)


func _append_vertical_wall_segment_quad(faces: Array[Vector3], start_z: int, end_z: int, x: int, top_height: float, bottom_a_height: float, bottom_b_height: float, west: bool) -> void:
	var z0 := float(start_z) * cell_size.y
	var z1 := float(end_z) * cell_size.y
	var world_x := float(x) * cell_size.x
	var top_a := Vector3(world_x, top_height, z0)
	var top_b := Vector3(world_x, top_height, z1)
	var bottom_a := Vector3(world_x, bottom_a_height, z0)
	var bottom_b := Vector3(world_x, bottom_b_height, z1)
	if west:
		_append_proxy_quad(faces, top_a, top_b, bottom_b, bottom_a)
	else:
		_append_proxy_quad(faces, top_b, top_a, bottom_a, bottom_b)


func _append_top_surface_cell(faces: Array[Vector3], p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3) -> void:
	faces.append(p00)
	faces.append(p10)
	faces.append(p11)
	faces.append(p00)
	faces.append(p11)
	faces.append(p01)


func _append_proxy_quad(faces: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append(a)
	faces.append(b)
	faces.append(c)
	faces.append(a)
	faces.append(c)
	faces.append(d)


func _create_collision_body_from_shape(shape: ConcavePolygonShape3D) -> void:
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = name + "_col"
	body.visible = false
	body.collision_layer = 17
	if terrain_system:
		body.set_collision_layer_value(terrain_system.extra_collision_layer, true)
	
	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	col_shape.shape = shape
	col_shape.visible = false
	body.add_child(col_shape)
	add_child(body)
	
	# Set owner for editor visibility at first, but we clear it later
	if EngineWrapper.instance.is_editor():
		var scene_root = EngineWrapper.instance.get_root_for_node(self)
		if scene_root:
			body.owner = scene_root
			col_shape.owner = scene_root
		for group in get_groups():
			if group.begins_with("navmesh_"):
				body.add_to_group(group)


## Recreate collision body after scene save (deferred call for proper physics refresh).
func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	
	# Only create ONE body with the FIRST shape
	var shape : ConcavePolygonShape3D = null
	if _temp_collision_shapes.size() > 0 and _temp_collision_shapes[0] !=  null:
		shape = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()
	if shape == null:
		# Nothing to create
		return
	_create_collision_body_from_shape(shape)


func _apply_collision_layers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.visible = false
			child.collision_layer = 17
			child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			for _child in child.get_children():
				if _child is CollisionShape3D:
					_child.set_visible(false)


func mark_all_cells_for_update() -> void:
	_mark_all_mesh_tiles_dirty()
	var expected_z := maxi(dimensions.z - 1, 0)
	var expected_x := maxi(dimensions.x - 1, 0)
	if needs_update == null or needs_update.size() != expected_z \
			or (expected_z > 0 and needs_update[0].size() != expected_x):
		needs_update = []
		for z in range(expected_z):
			needs_update.append([])
			for x in range(expected_x):
				needs_update[z].append(true)
		return
	for z in range(expected_z):
		for x in range(expected_x):
			needs_update[z][x] = true


func regenerate_all_cells(use_threads: bool):
	mark_all_cells_for_update()
	regenerate_mesh(use_threads)


func queue_full_mesh_regen(use_threads: bool = false) -> void:
	mark_all_cells_for_update()
	queue_mesh_regen(use_threads)


@export_tool_button("Export GLB") var bake = func():
	var tree := get_tree()
	
	if not prepare_for_storage():
		push_error("Cannot export GLB: chunk mesh is not complete.")
		return
	
	var persisted_mesh := get_persisted_mesh()
	
	if persisted_mesh == null or persisted_mesh.get_surface_count() == 0:
		push_error("Cannot export GLB: persisted mesh is empty.")
		return
	
	print("[MST Export] surfaces=%d vertices=%d"% [
			persisted_mesh.get_surface_count(),
			persisted_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		]
	)
	
	var export_inst := MeshInstance3D.new()
	export_inst.mesh = persisted_mesh
	export_inst.transform = transform
	
	var baker := MarchingSquaresGeometryBaker.new()
	baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
	
	var f := func(bakedMesh: Mesh, original: MeshInstance3D, bakedTexture: Image):
		var dialog := FileDialog.new()
		get_tree().root.add_child(dialog)
		
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		
		var inst := MeshInstance3D.new()
		inst.mesh = bakedMesh
		
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(bakedTexture)
		
		if inst.mesh and inst.mesh.get_surface_count() > 0:
			inst.mesh.surface_set_material(0, mat)
		
		var file_selected := func(path: String):
			var state := GLTFState.new()
			var doc := GLTFDocument.new()
			
			doc.append_from_scene(inst, state)
			doc.write_to_filesystem(state, path)
			
			dialog.queue_free()
		
		dialog.add_filter("*.glb", "GLB file")
		dialog.connect("file_selected", file_selected)
		dialog.popup_centered()
	
	baker.finished.connect(f, CONNECT_ONE_SHOT)
	baker.bake_geometry_texture(export_inst, tree)
