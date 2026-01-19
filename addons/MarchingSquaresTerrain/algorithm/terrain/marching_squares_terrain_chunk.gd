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
		if is_inside_tree():
			var grass_mat : ShaderMaterial = grass_planter.multimesh.mesh.material as ShaderMaterial
			if mode == Mode.SEMI_ROUND or Mode.SPHERICAL:
				grass_mat.set_shader_parameter("is_merge_round", true)
			else:
				grass_mat.set_shader_parameter("is_merge_round", false)
			merge_threshold = MERGE_MODE[mode]
			regenerate_all_cells()
@export_storage var height_map : Array # Stores the heights from the heightmap
@export_storage var color_map_0 : PackedColorArray # Stores the colors from vertex_color_0 (ground)
@export_storage var color_map_1 : PackedColorArray # Stores the colors from vertex_color_1 (ground)
@export_storage var wall_color_map_0 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 0)
@export_storage var wall_color_map_1 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 1)
@export_storage var grass_mask_map : PackedColorArray # Stores if a cell should have grass or not

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : MarchingSquaresGrassPlanter = preload("res://addons/MarchingSquaresTerrain/algorithm/grass/marching_squares_grass_planter.tscn").instantiate()

var higher_poly_floors : bool = true

# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size

var new_chunk : bool = false

var st : SurfaceTool # The surfacetool used to construct the current terrain
var cell_coords : Vector2i # cell coordinates currently being evaluated

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

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


var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.
var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)

# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights 
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone = upper_thresh - lower_thresh


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
	if Engine.is_editor_hint():
		if not height_map:
			generate_height_map()
		if not color_map_0 or not color_map_1:
			generate_color_maps()
		if not wall_color_map_0 or not wall_color_map_1:
			generate_wall_color_maps()
		if not grass_mask_map:
			generate_grass_mask_map()
		if not mesh and should_regenerate_mesh:
			regenerate_mesh()
		for child in get_children():
			if child is StaticBody3D:
				child.collision_layer = 17
				child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
		
		grass_planter.setup(self, true)
		grass_planter.regenerate_all_cells()
	
	else:
		printerr("ERROR: Trying to generate terrain during runtime (NOT SUPPORTED)")


func _exit_tree() -> void:
	# Only erase if terrain_system still has THIS chunk at chunk_coords
	# (avoids double-erasure when remove_chunk_from_tree already erased it)
	if terrain_system and terrain_system.chunks.get(chunk_coords) == self:
		terrain_system.chunks.erase(chunk_coords)
	
	# Only save mesh if not being removed temporarily (undo/redo)
	if not _skip_save_on_exit:
		# Guard get_tree() - can be null during multi-scene transitions
		var tree = get_tree()
		if tree and tree.current_scene and Engine.is_editor_hint():
			var scene = tree.current_scene
			ResourceSaver.save(mesh, "res://"+scene.name+"/"+name+".tres", ResourceSaver.FLAG_COMPRESS)


func regenerate_mesh():
	st = SurfaceTool.new()
	if mesh:
		st.create_from(mesh, 0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)  
	
	var start_time: int = Time.get_ticks_msec()
	
	if not find_child("GrassPlanter"):
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
		else:
			grass_planter.owner = get_tree().root
	else:
		grass_planter._chunk = self
	
	generate_terrain_cells()
	
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


func generate_terrain_cells():
	if not cell_geometry:
		cell_geometry = {}
	
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			cell_coords = Vector2i(x, z)
			
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
			calculate_cell_material_pair(color_map_0, color_map_1)
			
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
				
			cell.generate_geometry()
			if grass_planter and grass_planter.terrain_system:
				grass_planter.generate_grass_on_cell(cell_coords)
				

# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func add_point(x: float, y: float, z: float, uv_x: float, uv_y: float, diag_midpoint: bool = false, cell_has_walls_for_blend: bool = false):
	
	# uv - used for ledge detection. X = closeness to top terrace, Y = closeness to bottom of terrace
	# Walls will always have UV of 1, 1
	var uv = Vector2(uv_x, uv_y) if floor_mode else Vector2(1, 1)
	st.set_uv(uv)
	
	# Detect ridge BEFORE selecting color maps (ridge needs wall colors, not ground colors)
	var is_ridge := false
	if floor_mode and terrain_system.use_ridge_texture:
		is_ridge = (uv.y > 1.0 - terrain_system.ridge_threshold)
	
	# Wall vertices AND ridge vertices use wall_color_map_0/1
	# In hard edge mode, non-ridge floor vertices use floor colors
	# Ridge vertices MUST keep wall colors for correct wall texture display
	var use_wall_colors := (not floor_mode) or is_ridge
	if terrain_system.blend_mode == 1 and floor_mode and not is_ridge:
		use_wall_colors = false  # Only force floor colors for non-ridge floor vertices
	var source_map_0 : PackedColorArray = wall_color_map_0 if use_wall_colors else color_map_0
	var source_map_1 : PackedColorArray = wall_color_map_1 if use_wall_colors else color_map_1
	
	# Attempt to have smoother diagonal paths
	var color_0: Color
	if new_chunk:
		color_0 = Color(1.0, 0.0, 0.0, 0.0)
		source_map_0[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		if terrain_system.blend_mode == 1:
			# Hard edge mode uses same color as cell's top-left corner
			color_0 = source_map_0[cell_coords.y * dimensions.x + cell_coords.x]
		else:
			# Smooth blend mode welerp diagonal corners for smoother effect
			var ad_color = lerp(source_map_0[cell_coords.y*dimensions.x + cell_coords.x], source_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], 0.5)
			var bc_color = lerp(source_map_0[cell_coords.y*dimensions.x + cell_coords.x + 1], source_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x], 0.5)
			color_0 = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
			if ad_color.r > 0.99 or bc_color.r > 0.99: color_0.r = 1.0;
			if ad_color.g > 0.99 or bc_color.g > 0.99: color_0.g = 1.0;
			if ad_color.b > 0.99 or bc_color.b > 0.99: color_0.b = 1.0;
			if ad_color.a > 0.99 or bc_color.a > 0.99: color_0.a = 1.0;
	elif cell_is_boundary:
		if terrain_system.blend_mode == 1:
			# Use cell's corner color
			color_0 = source_map_0[cell_coords.y * dimensions.x + cell_coords.x]
		else:
			# HEIGHT-BASED SAMPLING for smooth blend mode
			# This prevents color bleeding between different height levels
			var height_range = cell_max_height - cell_min_height
			var height_factor = clamp((y - cell_min_height) / height_range, 0.0, 1.0)
			
			# Select appropriate color set based on vertex type (floor vs wall/ridge)
			var lower_0: Color = cell_wall_lower_color_0 if use_wall_colors else cell_floor_lower_color_0
			var upper_0: Color = cell_wall_upper_color_0 if use_wall_colors else cell_floor_upper_color_0
			
			# Sharp bands: < 0.3 = lower color, > 0.7 = upper color, middle = blend
			if height_factor < lower_thresh:
				color_0 = lower_0
			elif height_factor > upper_thresh:
				color_0 = upper_0
			else:
				var blend_factor = (height_factor - lower_thresh) / blend_zone
				color_0 = lerp(lower_0, upper_0, blend_factor)
			color_0 = get_dominant_color(color_0)
	else:
		var ab_color = lerp(source_map_0[cell_coords.y*dimensions.x + cell_coords.x], source_map_0[cell_coords.y*dimensions.x + cell_coords.x + 1], x)
		var cd_color = lerp(source_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x], source_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], x)
		if terrain_system.blend_mode != 1:
			color_0 = get_dominant_color(lerp(ab_color, cd_color, z)) # Use this for mixed triangles
		else:
			color_0 = source_map_0[cell_coords.y * dimensions.x + cell_coords.x] # Use this for perfect square tiles
	st.set_color(color_0)
	
	var color_1: Color
	if new_chunk:
		color_1 = Color(1.0, 0.0, 0.0, 0.0)
		source_map_1[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		if terrain_system.blend_mode == 1:
			# Hard edge - again same... vertex uses same color as cell's top-left corner
			color_1 = source_map_1[cell_coords.y * dimensions.x + cell_coords.x]
		else:
			# Smooth blend mode - keep the blend we had
			var ad_color = lerp(source_map_1[cell_coords.y*dimensions.x + cell_coords.x], source_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], 0.5)
			var bc_color = lerp(source_map_1[cell_coords.y*dimensions.x + cell_coords.x + 1], source_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x], 0.5)
			color_1 = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
			if ad_color.r > 0.99 or bc_color.r > 0.99: color_1.r = 1.0;
			if ad_color.g > 0.99 or bc_color.g > 0.99: color_1.g = 1.0;
			if ad_color.b > 0.99 or bc_color.b > 0.99: color_1.b = 1.0;
			if ad_color.a > 0.99 or bc_color.a > 0.99: color_1.a = 1.0;
	elif cell_is_boundary:
		if terrain_system.blend_mode == 1:
			color_1 = source_map_1[cell_coords.y * dimensions.x + cell_coords.x]
		else:
			var height_range = cell_max_height - cell_min_height
			var height_factor = clamp((y - cell_min_height) / height_range, 0.0, 1.0)
			
			var lower_1: Color = cell_wall_lower_color_1 if use_wall_colors else cell_floor_lower_color_1
			var upper_1: Color = cell_wall_upper_color_1 if use_wall_colors else cell_floor_upper_color_1
			
			if height_factor < 0.3:
				color_1 = lower_1
			elif height_factor > 0.7:
				color_1 = upper_1
			else:
				var blend_factor = (height_factor - 0.3) / 0.4
				color_1 = lerp(lower_1, upper_1, blend_factor)
			color_1 = get_dominant_color(color_1)
	else:
		var ab_color = lerp(source_map_1[cell_coords.y*dimensions.x + cell_coords.x], source_map_1[cell_coords.y*dimensions.x + cell_coords.x + 1], x)
		var cd_color = lerp(source_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x], source_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], x)
		if terrain_system.blend_mode != 1:
			color_1 = get_dominant_color(lerp(ab_color, cd_color, z)) # Use this for mixed triangles
		else:
			color_1 = source_map_1[cell_coords.y * dimensions.x + cell_coords.x] # Use this for perfect square tiles
	st.set_custom(0, color_1)
	
	# is_ridge already calculated above (before color source selection)
	var g_mask: Color = grass_mask_map[cell_coords.y*dimensions.x + cell_coords.x]
	g_mask.g = 1.0 if is_ridge else 0.0
	st.set_custom(1, g_mask)
	
	# Use edge connection to determine blending path
	# Avoid issues on weird Cliffs vs Slopes blending giving each a different path
	var mat_blend : Color = calculate_material_blend_data(x, z, source_map_0, source_map_1)
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
		var chunk_pos : Vector3 = global_position if is_inside_tree() else position
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
func calculate_cell_material_pair(source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> void:
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
func calculate_material_blend_data(vert_x: float, vert_z: float, source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> Color:
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


# If true, currently making floor geometry. if false, currently making wall geometry.
var floor_mode : bool = true

func start_floor():
	floor_mode = true
	st.set_smooth_group(0)


func start_wall():
	floor_mode = false
	st.set_smooth_group(-1)


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
	grass_mask_map = Array()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.z + x] = Color(1.0, 1.0, 1.0, 1.0)


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


# Draw to height.
# Returns the coordinates of all additional chunks affected by this height change.
# Empty for inner points, neightoring edge for non-corner edges, and 3 other corners for corner points.
func draw_height(x: int, z: int, y: float):
	# Contains chunks that were updated
	height_map[z][x] = y
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_0(x: int, z: int, color: Color):
	wall_color_map_0[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_1(x: int, z: int, color: Color):
	wall_color_map_1[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[z*dimensions.x + x] = masked
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func notify_needs_update(z: int, x: int):
	if z < 0 or z >= terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return
	
	needs_update[z][x] = true


func regenerate_all_cells():
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true
	
	regenerate_mesh()
