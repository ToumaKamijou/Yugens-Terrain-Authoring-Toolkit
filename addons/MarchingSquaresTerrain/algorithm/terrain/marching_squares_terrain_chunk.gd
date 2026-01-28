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

# < 1.0 = more aggressive wall detection 
# > 1.0 = less aggressive / more slope blend
const BLEND_EDGE_SENSITIVITY : float = 1.25

# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : MarchingSquaresTerrain
@export var chunk_coords : Vector2i = Vector2i.ZERO
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.POLYHEDRON: # The max height distance between points before a wall is created between them
	set(mode):
		merge_mode = mode
		if is_inside_tree():
			#Believe this might fix the Grass Color bug (part 1)
			var grass_mat :ShaderMaterial= grass_planter.multimesh.mesh.material as ShaderMaterial
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

var grass_planter : GrassPlanter = preload("res://addons/MarchingSquaresTerrain/algorithm/grass/grass_planter.tscn").instantiate()

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
var r : int # Current amount of counter-clockwise rotations performed on original heightmap to reach current state
var cell_edges : Array
var point_heights : Array
var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

# Heights of the 4 corners ini current rotation
var ay : float
var by : float
var cy : float
var dy : float
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
# Edge connected state
var ab : bool
var ac : bool
var bd : bool
var cd : bool

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
				child.collision_layer = 17 # ground (1) + terrain (16)
		
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
			grass_planter = GrassPlanter.new()
			if not color_map_0 or not color_map_1:
				generate_color_maps()
			if not grass_mask_map:
				generate_grass_mask_map()
			new_chunk = true
		grass_planter.name = "GrassPlanter"
		add_child(grass_planter)
		grass_planter._chunk = self
		grass_planter.setup(self)
		grass_planter.owner = EditorInterface.get_edited_scene_root()
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
			child.collision_layer = 17 # ground (1) + terrain (16)
	
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
			
			r = 0
			
			# Get heights of 4 surrounding corners
			ay = height_map[z][x] # top-left
			by = height_map[z][x+1] # top-right
			cy = height_map[z+1][x] # bottom-left
			dy = height_map[z+1][x+1] # bottom-right
			
			# Calculate cell height range for boundary detection (height-based color sampling)
			cell_min_height = min(ay, by, cy, dy)
			cell_max_height = max(ay, by, cy, dy)
			
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
				var corner_heights = [ay, by, cy, dy]
				
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
			
			# Track which edges shold be connected and not have a wall bewteen them.
			ab = abs(ay-by) < merge_threshold # top edge
			ac = abs(ay-cy) < merge_threshold # bottom edge
			bd = abs(by-dy) < merge_threshold # right edge
			cd = abs(cy-dy) < merge_threshold # bottom edge
			
			# Case 0
			# If all edges are connected, put a full floor here.
			if ab and bd and cd and ac:
				add_full_floor()
				if grass_planter and grass_planter.terrain_system:
					grass_planter.generate_grass_on_cell(cell_coords)
				continue
			
			# Edges going clockwise around the cell
			cell_edges = [ab, bd, cd, ac]
			# Point heights going clockwise around the cell
			point_heights = [ay, by, dy, cy]
			
			# Starting from the lowest corner, build the tile up
			var case_found: bool
			for i in range(4):
				# Use the rotation of the corner - the amount of counter-clockwise rotations for it to become the top-left corner, which is just its index in the point lists.
				r = i
				
				ab = cell_edges[r]
				bd = cell_edges[(r+1)%4]
				cd = cell_edges[(r+2)%4]
				ac = cell_edges[(r+3)%4]
				
				ay = point_heights[r]
				by = point_heights[(r+1)%4]
				dy = point_heights[(r+2)%4]
				cy = point_heights[(r+3)%4]
				
				# if none of the branches are hit, this will be set to false at the last else statement.
				# opted for this instead of putting a break in every branch, that would take up space
				case_found = true
				
				# Case 1
				# If A is higher than adjacent and opposite corner is connected to adjacent,
				# add an outer corner here with upper and lower floor covering whole tile.
				if is_higher(ay, by) and is_higher(ay, cy) and bd and cd:
					add_outer_corner(true, true)
				
				# Case 2
				# If A is higher than C and B is higher than D,
				# add an edge here covering whole tile.
				# (May want to prevent this if B and C are not within merge distance)
				elif is_higher(ay, cy) and is_higher(by, dy) and ab and cd:
					add_edge(true, true)
				
				# Case 3: AB edge with A outer corner above
				elif is_higher(ay, by) and is_higher(ay, cy) and is_higher(by, dy) and cd:
					add_edge(true, true, 0.5, 1)
					add_outer_corner(false, true, true, by)
				
				# Case 4: AB edge with B outer corner above
				elif is_higher(by, ay) and is_higher(ay, cy) and is_higher(by, dy) and cd:
					add_edge(true, true, 0, 0.5)
					rotate_cell(1)
					add_outer_corner(false, true, true, cy)
				
				# Case 5: B and C are higher than A and D.
				# Diagonal raised floor between B and C.
				# B and C must be within merge distance.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_merged(by, cy):
					add_inner_corner(true, false)
					add_diagonal_floor(by, cy, true, true)
					rotate_cell(2)
					add_inner_corner(true, false)
				
				# Case 5.5: B and C are higher than A and D, and B is higher than C.
				# Place a raised diagonal floor between, and an outer corner around B.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_higher(by, cy):
					add_inner_corner(true, false, true)
					add_diagonal_floor(cy, cy, true, true)
					
					# opposite lower floor
					rotate_cell(2)
					add_inner_corner(true, false, true)
					
					# higher corner B
					rotate_cell(-1)
					add_outer_corner(false, true)
				
				# Case 6: inner corner, where A is lower than B and C, and D is connected to B and C.
				elif is_lower(ay, by) and is_lower(ay, cy) and bd and cd:
					add_inner_corner(true, true)
				
				# Case 7: A is lower than B and C, B and C are merged, and D is higher than B and C.
				# Outer corner around A, and on top of that an inner corner around D
				elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and is_higher(dy, cy) and is_merged(by, cy):
					add_inner_corner(true, false)
					add_diagonal_floor(by, cy, true, false)
					rotate_cell(2)
					add_outer_corner(false, true)
				
				# Case 8: Inner corner surrounding A, with an outer corner sitting atop C.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, cy) and bd:
					add_inner_corner(true, false, true)
					start_floor()
					
					# D corner. B edge is connected, so use halfway point bewteen B and D
					add_point(1, dy, 1)
					add_point(0.5, dy, 1, 1, 0)
					add_point(1, (by+dy)/2, 0.5)
					
					# B corner
					add_point(1, by, 0)
					add_point(1, (by+dy)/2, 0.5)
					add_point(0.5, by, 0, 0, 1)
					
					# Center floors
					add_point(0.5, by, 0, 0, 1)
					add_point(1, (by+dy)/2, 0.5)
					add_point(0, by, 0.5, 1, 1)
					
					add_point(0.5, dy, 1, 1, 0)
					add_point(0, by, 0.5, 1, 1)
					add_point(1, (by+dy)/2, 0.5)
					#
					# Walls to upper corner
					start_wall()
					add_point(0, by, 0.5)
					add_point(0.5, dy, 1)
					add_point(0, cy, 0.5)
					
					add_point(0.5, cy, 1)
					add_point(0, cy, 0.5)
					add_point(0.5, dy, 1)
					
					# C upper floor
					start_floor()
					add_point(0, cy, 1)
					add_point(0, cy, 0.5, 0, 1)
					add_point(0.5, cy, 1, 0, 1)
				
				# Case 9: Inner corner surrounding A, with an outer corner sitting atop B.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and cd:
					add_inner_corner(true, false, true)
					
					# D corner. C edge is connected, so use halfway point bewteen C and D
					start_floor()
					add_point(1, dy, 1)
					add_point(0.5, (dy+cy)/2, 1)
					add_point(1, dy, 0.5)
					
					# C corner
					add_point(0, cy, 1)
					add_point(0, cy, 0.5)
					add_point(0.5, (dy+cy)/2, 1)
					
					# Center floors
					add_point(0, cy, 0.5)
					add_point(0.5, cy, 0)
					add_point(0.5, (dy+cy)/2, 1)
					
					add_point(1, dy, 0.5)
					add_point(0.5, (dy+cy)/2, 1)
					add_point(0.5, cy, 0)
					
					# Walls to upper corner
					start_wall()
					add_point(0.5, cy, 0)
					add_point(0.5, by, 0)
					add_point(1, dy, 0.5)
					
					add_point(1, by, 0.5)
					add_point(1, dy, 0.5)
					add_point(0.5, by, 0)
					
					# B upper floor
					start_floor()
					add_point(1, by, 0)
					add_point(1, by, 0.5)
					add_point(0.5, by, 0)
				
				# Case 10: Inner corner surrounding A, with an edge sitting atop BD.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, cy) and bd:
					add_inner_corner(true, false, true, true, false)
					
					rotate_cell(1)
					add_edge(false, true)
				
				# Case 11: Inner corner surrounding A, with an edge sitting atop CD.
				elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and cd:
					add_inner_corner(true, false, true, false, true)
					
					rotate_cell(2)
					add_edge(false, true)
				
				# Case 12: Clockwise upwards spiral with A as the highest lowest point and C as the highest. A is lower than B, B is lower than D, D is lower than C, and C is higher than A.
				elif is_lower(ay, by) and is_lower(by, dy) and is_lower(dy, cy) and is_higher(cy, ay):
					add_inner_corner(true, false, true, false, true)
					
					rotate_cell(2)
					add_edge(false, true, 0, 0.5)
					
					rotate_cell(1)
					add_outer_corner(false, true, true, cy)
				
				# Case 13: Clockwise upwards spiral, A lowest and B highest
				elif is_lower(ay, cy) and is_lower(cy, dy) and is_lower(dy, by) and is_higher(by, ay):
					add_inner_corner(true, false, true, true, false)
					
					rotate_cell(1)
					add_edge(false, true, 0.5, 1)
					
					add_outer_corner(false, true, true, by)
				
				# Case 14: A<B, B<C, C<D. outer corner atop edge atop inner corner
				elif is_lower(ay, by) and is_lower(by, cy) and is_lower(cy, dy):
					add_inner_corner(true, false, true, false, true)
					
					rotate_cell(2)
					add_edge(false, true, 0.5, 1)
					
					add_outer_corner(false, true, true, by)
				
				# Case 15: A<C, C<B, B<D
				elif is_lower(ay, cy) and is_lower(cy, by) and is_lower(by, dy):
					add_inner_corner(true, false, true, true, false)
					
					rotate_cell(1)
					add_edge(false, true, 0, 0.5)
					
					rotate_cell(1)
					add_outer_corner(false, true, true, cy)
				
				# Case 16: All edges are connected, except AC, and A is higher than C.
				# Make an edge here, but merge one side of the edge together
				elif ab and bd and cd and is_higher(ay, cy):
					var edge_by = (by+dy)/2
					var edge_dy = (by+dy)/2
					
					# Upper floor - use A and B edge for heights
					start_floor()
					add_point(0, ay, 0) #A
					add_point(1, by, 0) # B
					add_point(1, edge_by, 0.5) #D
					
					add_point(1, edge_by, 0.5, 0, 1) #D
					add_point(0, ay, 0.5, 0, 1) #C
					add_point(0, ay, 0) #A
					
					# Wall from left to right edge
					start_wall()
					add_point(0, cy, 0.5, 0, 0)
					add_point(0, ay, 0.5, 0, 1)
					add_point(1, edge_dy, 0.5, 1, 0)
					
					# Lower floor - use C and D edge
					start_floor()
					add_point(0, cy, 0.5, 1, 0)
					add_point(1, edge_dy, 0.5, 1, 0)
					add_point(0, cy, 1)
					
					add_point(1, dy, 1)
					add_point(0, cy, 1)
					add_point(1, edge_dy, 0.5)
				
				# Case 17: All edges are connected, except BD, and B is higher than D.
				# Make an edge here, but merge one side of the edge together
				elif ab and ac and cd and is_higher(by, dy):
					# Only merge the ay/cy edge if AC edge is connected
					var edge_ay = (ay+cy)/2
					var edge_cy = (ay+cy)/2
					
					# Upper floor - use A and B edge for heights
					start_floor()
					add_point(0, ay, 0)
					add_point(1, by, 0)
					add_point(0, edge_ay, 0.5)
					
					add_point(1, by, 0.5, 0, 1)
					add_point(0, edge_ay, 0.5, 0, 1)
					add_point(1, by, 0)
					
					# Wall from left to right edge
					start_wall()
					add_point(1, by, 0.5, 1, 1)
					add_point(1, dy, 0.5, 1, 0)
					add_point(0, edge_ay, 0.5, 0, 0)
					
					# Lower floor - use C and D edge
					start_floor()
					add_point(0, edge_cy, 0.5, 1, 0)
					add_point(1, dy, 0.5, 1, 0)
					add_point(1, dy, 1)
					
					add_point(0, cy, 1)
					add_point(0, edge_cy, 0.5)
					add_point(1, dy, 1)
				else:
					case_found = false
				
				if case_found:
					if grass_planter and grass_planter.terrain_system:
						grass_planter.generate_grass_on_cell(cell_coords)
					break
			
			if not case_found:
				# Invalid / unknown cell type. put a full floor here and hope it looks fine
				add_full_floor()


# True if A is higher than B and outside of merge distance
func is_higher(a: float, b: float):
	return a - b > merge_threshold


# True if A is lower than B and outside of merge distance
func is_lower(a: float, b: float):
	return a - b < -merge_threshold


func is_merged(a: float, b: float):
	return abs(a - b) < merge_threshold


# Rotate r times clockwise. if negative, rotate clockwise -r times.
func rotate_cell(rotations: int):
	r = (r + 4 + rotations) % 4
	
	ab = cell_edges[r]
	bd = cell_edges[(r+1)%4]
	cd = cell_edges[(r+2)%4]
	ac = cell_edges[(r+3)%4]
	
	ay = point_heights[r]
	by = point_heights[(r+1)%4]
	dy = point_heights[(r+2)%4]
	cy = point_heights[(r+3)%4]


# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func add_point(x: float, y: float, z: float, uv_x: float = 0, uv_y: float = 0, diag_midpoint: bool = false):
	for i in range(r):
		var temp = x
		x = 1 - z
		z = temp
	
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
	if terrain_system.use_hard_textures and floor_mode and not is_ridge:
		use_wall_colors = false  # Only force floor colors for non-ridge floor vertices
	var source_map_0 : PackedColorArray = wall_color_map_0 if use_wall_colors else color_map_0
	var source_map_1 : PackedColorArray = wall_color_map_1 if use_wall_colors else color_map_1
	
	# Attempt to have smoother diagonal paths
	var color_0: Color
	if new_chunk:
		color_0 = Color(1.0, 0.0, 0.0, 0.0)
		source_map_0[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		if terrain_system.use_hard_textures:
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
		if terrain_system.use_hard_textures:
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
		if not terrain_system.use_hard_textures:
			color_0 = get_dominant_color(lerp(ab_color, cd_color, z)) # Use this for mixed triangles
		else:
			color_0 = source_map_0[cell_coords.y * dimensions.x + cell_coords.x] # Use this for perfect square tiles
	st.set_color(color_0)
	
	var color_1: Color
	if new_chunk:
		color_1 = Color(1.0, 0.0, 0.0, 0.0)
		source_map_1[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		if terrain_system.use_hard_textures:
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
		if terrain_system.use_hard_textures:
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
		if not terrain_system.use_hard_textures:
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
	var blend_threshold : float = merge_threshold * BLEND_EDGE_SENSITIVITY # We can tweak the BLEND_EDGE_SENSITIVITY to allow more "agressive" Cliff vs Slope detection
	var blend_ab : bool = abs(ay-by) < blend_threshold
	var blend_ac : bool = abs(ay-cy) < blend_threshold
	var blend_bd : bool = abs(by-dy) < blend_threshold
	var blend_cd : bool = abs(cy-dy) < blend_threshold
	var cell_has_walls_for_blend : bool = not (blend_ab and blend_ac and blend_bd and blend_cd)
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


func add_full_floor():
	start_floor()
	
	if (higher_poly_floors):
		var ey = (ay+by+cy+dy)/4
		
		add_point(0, ay, 0)
		add_point(1, by, 0)
		add_point(0.5, ey, 0.5, 0, 0, true)
		
		add_point(1, by, 0)
		add_point(1, dy, 1)
		add_point(0.5, ey, 0.5, 0, 0, true)
		
		add_point(1, dy, 1)
		add_point(0, cy, 1)
		add_point(0.5, ey, 0.5, 0, 0, true)
		
		add_point(0, cy, 1)
		add_point(0, ay, 0)
		add_point(0.5, ey, 0.5, 0, 0, true)
	else:
		add_point(0, ay, 0)
		add_point(1, by, 0)
		add_point(0, cy, 1)
		
		add_point(1, dy, 1)
		add_point(0, cy, 1)
		add_point(1, by, 0)


# Add an outer corner, where A is the raised corner.
# if flatten_bottom is true, then bottom_height is used for the lower height of the wall
func add_outer_corner(floor_below: bool = true, floor_above: bool = true, flatten_bottom: bool = false, bottom_height: float = -1):
	var edge_by = bottom_height if flatten_bottom else by
	var edge_cy = bottom_height if flatten_bottom else cy
	
	if floor_above:
		start_floor()
		add_point(0, ay, 0, 0, 0)
		add_point(0.5, ay, 0, 0, 1)
		add_point(0, ay, 0.5, 0, 1)
	
	# Walls - bases will use B and C height, while cliff top will use A height.
	start_wall()
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(0, ay, 0.5, 0, 1)
	add_point(0.5, edge_by, 0, 1, 0)
	
	add_point(0.5, ay, 0, 1, 1)
	add_point(0.5, edge_by, 0, 1, 0)
	add_point(0, ay, 0.5, 0, 1)
	
	if floor_below:
		start_floor()
		add_point(1, dy, 1)
		add_point(0, cy, 1)
		add_point(1, by, 0)	
		
		add_point(0, cy, 1)
		add_point(0, cy, 0.5, 1, 0)
		add_point(0.5, by, 0, 1, 0)
		
		add_point(1, by, 0)	
		add_point(0, cy, 1)
		add_point(0.5, by, 0, 1, 0)


# Add an edge, where AB is the raised edge.
# a_x is the x coordinate that the top-left of the uper floor connects to
# b_x is the x coordinate that the top-right of the upper floor connects to
func add_edge(floor_below: bool, floor_above: bool, a_x: float = 0, b_x: float = 1):
	# If A and B are out of merge distance, use the lower of the two
	var edge_ay = ay if ab else min(ay,by)
	var edge_by = by if ab else min(ay,by)
	var edge_cy = cy if cd else max(cy, dy)
	var edge_dy = dy if cd else max(cy, dy)
	
	# Upper floor - use A and B for heights
	if floor_above:
		start_floor()
		add_point(a_x, edge_ay, 0, 1 if a_x > 0 else 0, 0)
		add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0)
		add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1)
		
		add_point(1, edge_by, 0.5, -1 if a_x > 0  else (1 if b_x < 1 else 0), 1)
		add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1)
		add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0)
	
	# Wall from left to right edge
	start_wall()
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(0, edge_ay, 0.5, 0, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	
	add_point(1, edge_by, 0.5, 1, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	add_point(0, edge_ay, 0.5, 0, 1)
	
	# Lower floor - use C and D for height
	# Only place a flat floor below if CD is connected
	if floor_below:
		start_floor()
		add_point(0, cy, 0.5, 1, 0)
		add_point(1, dy, 0.5, 1, 0)
		add_point(0, cy, 1)
		
		add_point(1, dy, 1)
		add_point(0, cy, 1)
		add_point(1, dy, 0.5, 1, 0)


# Add an inner corner, where A is the lowered corner.
func add_inner_corner(lower_floor: bool = true, full_upper_floor: bool = true, flatten: bool = false, bd_floor: bool = false, cd_floor: bool = false):
	var corner_by = min(by,cy) if flatten else by
	var corner_cy = min(by,cy) if flatten else cy
	
	# Lower floor with height of point A
	if lower_floor:
		start_floor()
		add_point(0, ay, 0)
		add_point(0.5, ay, 0, 1, 0)
		add_point(0, ay, 0.5, 1, 0)
	
	start_wall()
	add_point(0, ay, 0.5, 1, 0)
	add_point(0.5, ay, 0, 0, 0)
	add_point(0, corner_cy, 0.5, 1, 1)
	
	add_point(0.5, corner_by, 0, 0, 1)
	add_point(0, corner_cy, 0.5, 1, 1)
	add_point(0.5, ay, 0, 0, 0)
	
	start_floor()
	if full_upper_floor:
		add_point(1, dy, 1)
		add_point(0, corner_cy, 1)
		add_point(1, corner_by, 0)
		
		add_point(0, corner_cy, 1)
		add_point(0, corner_cy, 0.5, 0, 1)
		add_point(0.5, corner_by, 0, 0, 1)
		
		add_point(1, corner_by, 0)
		add_point(0, corner_cy, 1)
		add_point(0.5, corner_by, 0, 0, 1)
	
	# if C and D are both higher than B, and B does not connect the corners, there's an edge above, place floors that will connect to the CD edge
	if cd_floor:
		# use height of B corner
		add_point(1, by, 0, 0, 0)
		add_point(0, by, 0.5, 1, 1)
		add_point(0.5, by, 0, 0, 1)
		
		add_point(1, by, 0, 0, 0)
		add_point(1, by, 0.5, 1, -1)
		add_point(0, by, 0.5, 1, 1)
	
	# if B and D are both higher than C, and C does not connect the corners, there's an edge above, place floors that will connect to the BD edge
	if bd_floor: 
		add_point(0, cy, 0.5, 0, 1)
		add_point(0.5, cy, 0, 1, 1)
		add_point(0, cy, 1, 0, 0)
		
		add_point(0.5, cy, 1, 1, -1)
		add_point(0, cy, 1, 0, 0)
		add_point(0.5, cy, 0, 1, 1)


# Add a diagonal floor, using heights of B and C and connecting their points using passed heights.
func add_diagonal_floor(b_y: float, c_y: float, a_cliff: bool, d_cliff: bool):
	start_floor()
	
	add_point(1, b_y, 0)
	add_point(0, c_y, 1)
	add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0)
	
	add_point(0, c_y, 1)
	add_point(0, c_y, 0.5, 0 if a_cliff else 1, 1 if a_cliff else 0)
	add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0)
	
	add_point(1, b_y, 0)
	add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0)
	add_point(0, c_y, 1)
	
	add_point(0, c_y, 1)
	add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0)
	add_point(0.5, c_y, 1, 0 if d_cliff else 1, 1 if d_cliff else 0)


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
