@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk


enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}

const MERGE_MODE = {
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
#endregion

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : MarchingSquaresGrassPlanter = preload("uid://b0dc71ti1ofmh").instantiate()

var higher_poly_floors : bool = true

var global_position_cached : Vector3 = position

var cell_generation_mutex : Mutex = Mutex.new()

#region chunk variables
# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size

var new_chunk : bool = false
#endregion

var st : SurfaceTool # The surfacetool used to construct the current terrain

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

#region cell variables
# Cell height range for boundary detection (height-based color sampling)
var cell_min_height : float
var cell_max_height : float
# Height-based material colors for FLOOR boundary cells (prevents color bleeding between heights)
var cell_floor_lower_color_0 : Color
var cell_floor_upper_color_0 : Color
var cell_floor_lower_color_1 : Color
var cell_floor_upper_color_1 : Color
# Height-based material colors for WALL/RIDGE boundary cells
var cell_wall_lower_color_0 : Color
var cell_wall_upper_color_0 : Color
var cell_wall_lower_color_1 : Color
var cell_wall_upper_color_1 : Color
var cell_is_boundary : bool = false
# Per-cell materials for to supports up to 3 textures
var cell_mat_a : int = 0
var cell_mat_b : int = 0
var cell_mat_c : int = 0
#endregion

var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.
var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)
var _data_dirty : bool = false # Set to true when source data changes, triggers save in MSTDataHandler

#region temporary storage vars
# Temporary storage for ephemeral resources during scene save
var _temp_mesh : ArrayMesh
var _temp_grass_multimesh : MultiMesh
var _temp_collision_shapes : Array[ConcavePolygonShape3D] = []  #old scenes may have duplicates
var _temp_height_map : Array  # Source data - saved to external storage, not scene file
#endregion

#region blend option vars
# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights 
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone = upper_thresh - lower_thresh
#endregion

# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool = true):
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)
	
	if not grass_planter:
		grass_planter = get_node_or_null("GrassPlanter")
		if grass_planter:
			grass_planter._chunk = self

	# Generate maps if not loaded from external storage (works for both editor and runtime)
	if not height_map:
		generate_height_map()
	if not color_map_0 or not color_map_1:
		generate_color_maps()
	if not wall_color_map_0 or not wall_color_map_1:
		generate_wall_color_maps()
	if not grass_mask_map:
		generate_grass_mask_map()

	if not mesh and should_regenerate_mesh:
		regenerate_mesh(true)
	elif mesh:
		if not _temp_collision_shapes.is_empty():
			_recreate_collision_body()
		else:
			for child in get_children():
				if child is StaticBody3D:
					child.free()
			create_trimesh_collision()
			for child in get_children():
				if child is StaticBody3D:
					child.collision_layer = 17
					child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
					for _child in child.get_children():
						if _child is CollisionShape3D:
							_child.set_visible(false)

	grass_planter.setup(self, true)
	grass_planter.regenerate_all_cells()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return

	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			# Store height_map and clear - source data saved to external storage, not scene
			_temp_height_map = height_map
			height_map = []

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
				body.queue_free()

		NOTIFICATION_EDITOR_POST_SAVE:
			# Restore height_map
			if _temp_height_map:
				height_map = _temp_height_map
				_temp_height_map = []

			# Restore mesh
			if _temp_mesh:
				mesh = _temp_mesh
				_temp_mesh = null

			# Restore grass multimesh
			if _temp_grass_multimesh and grass_planter:
				grass_planter.multimesh = _temp_grass_multimesh
				_temp_grass_multimesh = null

			# Recreate ONE collision body (only need one, even if old scene had duplicates)
			if not _temp_collision_shapes.is_empty():
				call_deferred("_recreate_collision_body")

		NOTIFICATION_PREDELETE:
			# Safety cleanup - clear owner on ALL collision nodes
			for child in get_children():
				if child is StaticBody3D:
					child.owner = null
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D:
							shape_child.owner = null


func _exit_tree() -> void:
	# Clear temp references
	_temp_height_map = []
	_temp_mesh = null
	_temp_grass_multimesh = null
	_temp_collision_shapes.clear()

	# Clear owner on ALL collision nodes to prevent serialization edge cases
	if Engine.is_editor_hint():
		for child in get_children():
			if child is StaticBody3D:
				child.owner = null
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.owner = null

	# Only erase if terrain_system still has THIS chunk at chunk_coords
	if terrain_system and terrain_system.chunks.get(chunk_coords) == self:
		terrain_system.chunks.erase(chunk_coords)


func regenerate_mesh(use_threads: bool = false):
	st = SurfaceTool.new()
	if mesh:
		st.create_from(mesh, 0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)  
	
	var start_time: int = Time.get_ticks_msec()
	
	if not get_node_or_null("GrassPlanter"):
		grass_planter = get_node_or_null("GrassPlanter")
		if not grass_planter:
			grass_planter = MarchingSquaresGrassPlanter.new()
			if not color_map_0 or not color_map_1:
				generate_color_maps()
			if not grass_mask_map:
				generate_grass_mask_map()
			new_chunk = true
		grass_planter.name = "GrassPlanter"
		add_child(grass_planter)
		grass_planter._chunk = self
		grass_planter.setup(self)
		if Engine.is_editor_hint():
			grass_planter.owner = Engine.get_singleton("EditorInterface").get_edited_scene_root()
		elif is_inside_tree():
			grass_planter.owner = get_tree().root
	else:
		grass_planter._chunk = self
	
	generate_terrain_cells(use_threads)
	
	if new_chunk:
		new_chunk = false
	
	st.generate_normals()
	st.index()
	# Create a new mesh out of floor, and add the wall surface to it
	mesh = st.commit()
	
	if mesh and terrain_system:
		mesh.surface_set_material(0, terrain_system.terrain_material)
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	create_trimesh_collision()
	for child in get_children():
		if child is StaticBody3D:
			child.collision_layer = 17
			child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			for _child in child.get_children():
				if _child is CollisionShape3D:
					_child.set_visible(false)
	
	var elapsed_time: int = Time.get_ticks_msec() - start_time
	print_verbose("Generated terrain in "+str(elapsed_time)+"ms")


func generate_terrain_cells(use_threads: bool):
	if not cell_geometry:
		cell_geometry = {}
	
	global_position_cached = position
	var thread_pool := MarchingSquaresThreadPool.new(max(1, OS.get_processor_count()))
	
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			var cell_coords = Vector2i(x, z)
			
			# If geometry did not change, copy already generated geometry and skip this cell
			if not needs_update[z][x]:
				var verts = cell_geometry[cell_coords]["verts"]
				var uvs = cell_geometry[cell_coords]["uvs"]
				var uv2s = cell_geometry[cell_coords]["uv2s"]
				var colors_0 = cell_geometry[cell_coords]["colors_0"]
				var colors_1 = cell_geometry[cell_coords]["colors_1"]
				var grass_mask = cell_geometry[cell_coords]["grass_mask"]
				var mat_blend = cell_geometry[cell_coords]["mat_blend"]
				var is_floor = cell_geometry[cell_coords]["is_floor"]
				for i in range(len(verts)):
					st.set_smooth_group(0 if is_floor[i] == true else -1)
					st.set_uv(uvs[i])
					st.set_uv2(uv2s[i])
					st.set_color(colors_0[i])
					st.set_custom(0, colors_1[i])
					st.set_custom(1, grass_mask[i])
					st.set_custom(2, mat_blend[i])
					st.add_vertex(verts[i])
				continue
			
			# Cell is now being updated
			needs_update[z][x] = false
			
			# If geometry did change or none exists yet, 
			# Create an entry for this cell (will also override any existing one)
			cell_geometry[cell_coords] = {
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"uv2s": PackedVector2Array(),
				"colors_0": PackedColorArray(),
				"colors_1": PackedColorArray(),
				"grass_mask": PackedColorArray(),
				"mat_blend": PackedColorArray(),
				"is_floor": [],
			}
			
			var cell := MarchingSquaresTerrainCell.new(self, height_map[z][x], height_map[z][x+1], height_map[z+1][x], height_map[z+1][x+1], merge_threshold)
			
			# Calculate cell height range for boundary detection (height-based color sampling)
			cell_min_height = min(cell.ay, cell.by, cell.cy, cell.dy)
			cell_max_height = max(cell.ay, cell.by, cell.cy, cell.dy)
			
			# Determine if this is a boundary cell (significant height variation)
			cell_is_boundary = (cell_max_height - cell_min_height) > merge_threshold
			
			# Calculate the 2 dominant textures for this cell
			calculate_cell_material_pair(cell_coords, color_map_0, color_map_1)
			
			if cell_is_boundary:
				# Identify corners at each height level for height-based color sampling
				# FLOOR colors - from color_map (used for regular floor vertices)
				var floor_corner_colors_0 = [
					color_map_0[z * dimensions.x + x],           # A (top-left)
					color_map_0[z * dimensions.x + x + 1],       # B (top-right)
					color_map_0[(z + 1) * dimensions.x + x],     # C (bottom-left)
					color_map_0[(z + 1) * dimensions.x + x + 1]  # D (bottom-right)
				]
				var floor_corner_colors_1 = [
					color_map_1[z * dimensions.x + x],
					color_map_1[z * dimensions.x + x + 1],
					color_map_1[(z + 1) * dimensions.x + x],
					color_map_1[(z + 1) * dimensions.x + x + 1]
				]
				# WALL colors - from wall_color_map (used for wall/ridge vertices)
				var wall_corner_colors_0 = [
					wall_color_map_0[z * dimensions.x + x],           # A (top-left)
					wall_color_map_0[z * dimensions.x + x + 1],       # B (top-right)
					wall_color_map_0[(z + 1) * dimensions.x + x],     # C (bottom-left)
					wall_color_map_0[(z + 1) * dimensions.x + x + 1]  # D (bottom-right)
				]
				var wall_corner_colors_1 = [
					wall_color_map_1[z * dimensions.x + x],
					wall_color_map_1[z * dimensions.x + x + 1],
					wall_color_map_1[(z + 1) * dimensions.x + x],
					wall_color_map_1[(z + 1) * dimensions.x + x + 1]
				]
				var corner_heights = [cell.ay, cell.by, cell.cy, cell.dy]
				
				# Find corners at min and max height
				var min_idx = 0
				var max_idx = 0
				for i in range(4):
					if corner_heights[i] < corner_heights[min_idx]:
						min_idx = i
					if corner_heights[i] > corner_heights[max_idx]:
						max_idx = i
				
				# Floor boundary colors (from ground color_map)
				cell_floor_lower_color_0 = floor_corner_colors_0[min_idx]
				cell_floor_upper_color_0 = floor_corner_colors_0[max_idx]
				cell_floor_lower_color_1 = floor_corner_colors_1[min_idx]
				cell_floor_upper_color_1 = floor_corner_colors_1[max_idx]
				# Wall boundary colors (from wall_color_map)
				cell_wall_lower_color_0 = wall_corner_colors_0[min_idx]
				cell_wall_upper_color_0 = wall_corner_colors_0[max_idx]
				cell_wall_lower_color_1 = wall_corner_colors_1[min_idx]
				cell_wall_upper_color_1 = wall_corner_colors_1[max_idx]
				
			var work_load := func():
				cell.generate_geometry(cell_coords)
				if grass_planter and grass_planter.terrain_system:
					grass_planter.generate_grass_on_cell(cell_coords)
			if use_threads:
				thread_pool.enqueue(work_load)
			else:
				work_load.call()
	
	if use_threads:
		thread_pool.start()
		thread_pool.wait()

#region color interpolation Helpers

## Returns [source_map_0, source_map_1] based on floor/wall/ridge state
func _get_color_sources(is_floor: bool, is_ridge: bool) -> Array[PackedColorArray]:
	var use_wall_colors := (not is_floor) or is_ridge
	if terrain_system.blend_mode == 1 and is_floor and not is_ridge:
		use_wall_colors = false  # Only force floor colors for non-ridge floor vertices

	var src_0 : PackedColorArray = wall_color_map_0 if use_wall_colors else color_map_0
	var src_1 : PackedColorArray = wall_color_map_1 if use_wall_colors else color_map_1
	return [src_0, src_1]


## Calculates color for diagonal midpoint vertices
func _calc_diagonal_color(cell_coords: Vector2i, source_map: PackedColorArray) -> Color:
	if terrain_system.blend_mode == 1:
		# Hard edge mode uses same color as cell's top-left corner
		return source_map[cell_coords.y * dimensions.x + cell_coords.x]

	# Smooth blend mode - lerp diagonal corners for smoother effect
	var idx := cell_coords.y * dimensions.x + cell_coords.x
	var ad_color : Color = lerp(source_map[idx], source_map[idx + dimensions.x + 1], 0.5)
	var bc_color : Color = lerp(source_map[idx + 1], source_map[idx + dimensions.x], 0.5)
	var result := Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
	if ad_color.r > 0.99 or bc_color.r > 0.99: result.r = 1.0
	if ad_color.g > 0.99 or bc_color.g > 0.99: result.g = 1.0
	if ad_color.b > 0.99 or bc_color.b > 0.99: result.b = 1.0
	if ad_color.a > 0.99 or bc_color.a > 0.99: result.a = 1.0
	return result


## Calculates height-based color for boundary cells (prevents color bleeding between heights)
func _calc_boundary_color(cell_coords: Vector2i, y: float, source_map: PackedColorArray, lower_color: Color, upper_color: Color) -> Color:
	if terrain_system.blend_mode == 1:
		# Hard edge mode uses cell's corner color
		return source_map[cell_coords.y * dimensions.x + cell_coords.x]

	# HEIGHT-BASED SAMPLING for smooth blend mode
	var height_range := cell_max_height - cell_min_height
	var height_factor : float = clamp((y - cell_min_height) / height_range, 0.0, 1.0)

	# Sharp bands: < lower_thresh = lower color, > upper_thresh = upper color, middle = blend
	var color: Color
	if height_factor < lower_thresh:
		color = lower_color
	elif height_factor > upper_thresh:
		color = upper_color
	else:
		var blend_factor : float = (height_factor - lower_thresh) / blend_zone
		color = lerp(lower_color, upper_color, blend_factor)

	return get_dominant_color(color)


## Calculates bilinearly interpolated color for flat cells
func _calc_bilinear_color(cell_coords: Vector2i, x: float, z: float, source_map: PackedColorArray) -> Color:
	var idx := cell_coords.y * dimensions.x + cell_coords.x
	var ab_color : Color = lerp(source_map[idx], source_map[idx + 1], x)
	var cd_color : Color = lerp(source_map[idx + dimensions.x], source_map[idx + dimensions.x + 1], x)

	if terrain_system.blend_mode != 1:
		return get_dominant_color(lerp(ab_color, cd_color, z))  # Mixed triangles
	return source_map[idx]  # Perfect square tiles


## selects the appropriate color interpolation method
func _interpolate_vertex_color(
	cell_coords: Vector2i,
	x: float, y: float, z: float,
	source_map: PackedColorArray,
	diag_midpoint: bool,
	lower_color: Color,
	upper_color: Color
) -> Color:
	if new_chunk:
		source_map[cell_coords.y * dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
		return Color(1.0, 0.0, 0.0, 0.0)

	if diag_midpoint:
		return _calc_diagonal_color(cell_coords, source_map)

	if cell_is_boundary:
		return _calc_boundary_color(cell_coords, y, source_map, lower_color, upper_color)

	return _calc_bilinear_color(cell_coords, x, z, source_map)

#endregion

func add_polygons(cell_coords: Vector2i, pts:Array[Vector3], uvs: Array[Vector2], diag_mids: Array[bool], blends: Array[bool], floors: Array[bool]):
		assert(pts.size() % 3 == 0)
		assert(pts.size() == uvs.size())
		assert(pts.size() == diag_mids.size())
		assert(pts.size() == blends.size())
		
		cell_generation_mutex.lock()
		for i in range(pts.size()):
			if floor_mode and not floors[i]:
				_start_wall()
			elif not floor_mode and floors[i]:
				_start_floor()
			_add_point(cell_coords, pts[i].x, pts[i].y, pts[i].z, uvs[i].x, uvs[i].y, diag_mids[i], blends[i])
		cell_generation_mutex.unlock()

# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func _add_point(cell_coords: Vector2i, x: float, y: float, z: float, uv_x: float, uv_y: float, diag_midpoint: bool = false, cell_has_walls_for_blend: bool = false):
	# UV - used for ledge detection. X = closeness to top terrace, Y = closeness to bottom of terrace
	# Walls will always have UV of 1, 1
	var uv := Vector2(uv_x, uv_y) if floor_mode else Vector2(1, 1)
	st.set_uv(uv)

	# Detect ridge BEFORE selecting color maps (ridge needs wall colors, not ground colors)
	var is_ridge := floor_mode and terrain_system.use_ridge_texture and (uv.y > 1.0 - terrain_system.ridge_threshold)

	# Get color source maps based on floor/wall/ridge state
	var sources := _get_color_sources(floor_mode, is_ridge)
	var source_map_0 : PackedColorArray = sources[0]
	var source_map_1 : PackedColorArray = sources[1]
	var use_wall_colors := (source_map_0 == wall_color_map_0)

	# Calculate vertex colors using appropriate interpolation method
	var lower_0 : Color = cell_wall_lower_color_0 if use_wall_colors else cell_floor_lower_color_0
	var upper_0 : Color = cell_wall_upper_color_0 if use_wall_colors else cell_floor_upper_color_0
	var color_0 := _interpolate_vertex_color(cell_coords, x, y, z, source_map_0, diag_midpoint, lower_0, upper_0)
	st.set_color(color_0)

	var lower_1 : Color = cell_wall_lower_color_1 if use_wall_colors else cell_floor_lower_color_1
	var upper_1 : Color = cell_wall_upper_color_1 if use_wall_colors else cell_floor_upper_color_1
	var color_1 := _interpolate_vertex_color(cell_coords, x, y, z, source_map_1, diag_midpoint, lower_1, upper_1)
	st.set_custom(0, color_1)

	# is_ridge already calculated above
	var g_mask: Color = grass_mask_map[cell_coords.y*dimensions.x + cell_coords.x]
	g_mask.g = 1.0 if is_ridge else 0.0
	st.set_custom(1, g_mask)
	
	# Use edge connection to determine blending path
	# Avoid issues on weird Cliffs vs Slopes blending giving each a different path
	var mat_blend : Color = calculate_material_blend_data(cell_coords, x, z, source_map_0, source_map_1)
	if cell_has_walls_for_blend and floor_mode:
		mat_blend.a = 2.0 
	st.set_custom(2, mat_blend)
	
	#same calculations from here
	var vert = Vector3((cell_coords.x+x) * cell_size.x, y, (cell_coords.y+z) * cell_size.y)
	var uv2
	if floor_mode:
		uv2 = Vector2(vert.x, vert.z) / cell_size
	else:
		# This avoids is_inside_tree() errors when inactive scene tabs are loaded
		var chunk_pos : Vector3 = global_position_cached if is_inside_tree() else position
		var global_pos = vert + chunk_pos
		uv2 = (Vector2(global_pos.x, global_pos.y) + Vector2(global_pos.z, global_pos.y))
	
	st.set_uv2(uv2)
	st.add_vertex(vert)
	
	cell_geometry[cell_coords]["verts"].append(vert)
	cell_geometry[cell_coords]["uvs"].append(uv)
	cell_geometry[cell_coords]["uv2s"].append(uv2)
	cell_geometry[cell_coords]["colors_0"].append(color_0)
	cell_geometry[cell_coords]["colors_1"].append(color_1)
	cell_geometry[cell_coords]["grass_mask"].append(g_mask)
	cell_geometry[cell_coords]["mat_blend"].append(mat_blend)
	cell_geometry[cell_coords]["is_floor"].append(floor_mode)

#region cell_geometry helpers and calculation functions

func get_dominant_color(c: Color) -> Color:
	var max_val := c.r
	var idx : int = 0
	
	if c.g > max_val:
		max_val = c.g
		idx = 1
	if c.b > max_val:
		max_val = c.b
		idx = 2
	if c.a > max_val:
		idx = 3
	
	var new_color := Color(0, 0, 0, 0)
	match idx:
		0: new_color.r = 1.0
		1: new_color.g = 1.0
		2: new_color.b = 1.0
		3: new_color.a = 1.0
	
	return new_color


# Convert vertex color pair to texture index
func get_texture_index_from_colors(c0: Color, c1: Color) -> int:
	var c0_idx : int = 0
	var c0_max : float = c0.r
	if c0.g > c0_max: c0_max = c0.g; c0_idx = 1
	if c0.b > c0_max: c0_max = c0.b; c0_idx = 2
	if c0.a > c0_max: c0_idx = 3
	
	var c1_idx : int = 0
	var c1_max : float = c1.r
	if c1.g > c1_max: c1_max = c1.g; c1_idx = 1
	if c1.b > c1_max: c1_max = c1.b; c1_idx = 2
	if c1.a > c1_max: c1_idx = 3
	
	return c0_idx * 4 + c1_idx


# Convert texture index (0-15) back to color pair 
func texture_index_to_colors(idx: int) -> Array[Color]:
	var c0_channel : int = idx / 4
	var c1_channel : int = idx % 4
	var c0 := Color(0, 0, 0, 0)
	var c1 := Color(0, 0, 0, 0)
	match c0_channel:
		0: c0.r = 1.0
		1: c0.g = 1.0
		2: c0.b = 1.0
		3: c0.a = 1.0
	match c1_channel:
		0: c1.r = 1.0
		1: c1.g = 1.0
		2: c1.b = 1.0
		3: c1.a = 1.0
	return [c0, c1]


# Calculate 2 dominant textures for current cell 
func calculate_cell_material_pair(cell_coords: Vector2i, source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> void:
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * dimensions.x + cell_coords.x + 1])
	
	var tex_counts : Dictionary = {}
	tex_counts[tex_a] = tex_counts.get(tex_a, 0) + 1
	tex_counts[tex_b] = tex_counts.get(tex_b, 0) + 1
	tex_counts[tex_c] = tex_counts.get(tex_c, 0) + 1
	tex_counts[tex_d] = tex_counts.get(tex_d, 0) + 1
	
	var sorted_textures : Array = tex_counts.keys()
	sorted_textures.sort_custom(func(a, b): return tex_counts[a] > tex_counts[b])
	
	cell_mat_a = sorted_textures[0]
	cell_mat_b = sorted_textures[1] if sorted_textures.size() > 1 else sorted_textures[0]
	cell_mat_c = sorted_textures[2] if sorted_textures.size() > 2 else cell_mat_b


# Calculate CUSTOM2 blend data with 3 texture support 
# Encoding: Color(packed_mats, mat_c/15, weight_a, weight_b)
# R: (mat_a + mat_b * 16) / 255.0  (packs 2 indices, each 0-15)
# G: mat_c / 15.0
# B: weight_a (0.0 to 1.0)
# A: weight_b (0.0 to 1.0), or 2.0 to signal use_vertex_colors
func calculate_material_blend_data(cell_coords: Vector2i, vert_x: float, vert_z: float, source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> Color:
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * dimensions.x + cell_coords.x + 1])
	
	# Position weights for bilinear interpolation
	var weight_a : float = (1.0 - vert_x) * (1.0 - vert_z)
	var weight_b : float = vert_x * (1.0 - vert_z)
	var weight_c : float = (1.0 - vert_x) * vert_z
	var weight_d : float = vert_x * vert_z
	
	# Accumulate weights for all 3 cell materials
	var weight_mat_a : float = 0.0
	var weight_mat_b : float = 0.0
	var weight_mat_c : float = 0.0
	
	# Corner A
	if tex_a == cell_mat_a: weight_mat_a += weight_a
	elif tex_a == cell_mat_b: weight_mat_b += weight_a
	elif tex_a == cell_mat_c: weight_mat_c += weight_a
	# Corner B
	if tex_b == cell_mat_a: weight_mat_a += weight_b
	elif tex_b == cell_mat_b: weight_mat_b += weight_b
	elif tex_b == cell_mat_c: weight_mat_c += weight_b
	# Corner C
	if tex_c == cell_mat_a: weight_mat_a += weight_c
	elif tex_c == cell_mat_b: weight_mat_b += weight_c
	elif tex_c == cell_mat_c: weight_mat_c += weight_c
	# Corner D
	if tex_d == cell_mat_a: weight_mat_a += weight_d
	elif tex_d == cell_mat_b: weight_mat_b += weight_d
	elif tex_d == cell_mat_c: weight_mat_c += weight_d
	
	# Normalize weights
	var total_weight : float = weight_mat_a + weight_mat_b + weight_mat_c
	if total_weight > 0.001:
		weight_mat_a /= total_weight
		weight_mat_b /= total_weight
	
	# Pack mat_a and mat_b into one channel (each is 0-15, so together 0-255)
	var packed_mats : float = (float(cell_mat_a) + float(cell_mat_b) * 16.0) / 255.0
	
	return Color(packed_mats, float(cell_mat_c) / 15.0, weight_mat_a, weight_mat_b)

#endregion

# If true, currently making floor geometry. if false, currently making wall geometry.
var floor_mode : bool = true

func _start_floor():
	floor_mode = true
	st.set_smooth_group(0)


func _start_wall():
	floor_mode = false
	st.set_smooth_group(-1)

#region cell_geometry generators (on being empty)

func generate_height_map():
	height_map = []
	height_map.resize(dimensions.z)
	for z in range(dimensions.z):
		height_map[z] = []
		height_map[z].resize(dimensions.x)
		for x in range(dimensions.x):
			height_map[z][x] = 0.0
	
	var noise = terrain_system.noise_hmap
	if noise:
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var noise_x = (chunk_coords.x * (dimensions.x - 1)) + x
				var noise_z = (chunk_coords.y * (dimensions.z -1)) + z
				var noise_sample = noise.get_noise_2d(noise_x, noise_z)
				height_map[z][x] = noise_sample * dimensions.y


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
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			wall_color_map_0[z*dimensions.x + x] = Color(1,0,0,0)  # Default to texture slot 0
			wall_color_map_1[z*dimensions.x + x] = Color(1,0,0,0)


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

#endregion

func notify_needs_update(z: int, x: int):
	if z < 0 or z >= terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return

	needs_update[z][x] = true


## Mark chunk as having modified source data - triggers save in MSTDataHandler
func mark_dirty() -> void:
	_data_dirty = true


## Recreate collision body after scene save (deferred call for proper physics refresh)
func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return

	# Only create ONE body with the FIRST shape
	var shape : ConcavePolygonShape3D = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()

	var body := StaticBody3D.new()
	body.collision_layer = 17
	if terrain_system:
		body.set_collision_layer_value(terrain_system.extra_collision_layer, true)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	col_shape.visible = false
	body.add_child(col_shape)
	add_child(body)

	# Set owner for editor visibility at first, but we clear it later
	if Engine.is_editor_hint():
		var scene_root = Engine.get_singleton("EditorInterface").get_edited_scene_root()
		if scene_root:
			body.owner = scene_root
			col_shape.owner = scene_root


func regenerate_all_cells(use_threads: bool):
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true
	
	regenerate_mesh(use_threads)
