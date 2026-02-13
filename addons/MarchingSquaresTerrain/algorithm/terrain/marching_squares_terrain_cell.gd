extends RefCounted
class_name MarchingSquaresTerrainCell


# < 1.0 = more aggressive wall detection 
# > 1.0 = less aggressive / more slope blend
const BLEND_EDGE_SENSITIVITY : float = 1.25

enum CellRotation {DEG0 = 0, DEG270 = 3, DEG180 = 2, DEG90 = 1}

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


var pts : Array[Vector3]
var uvs : Array[Vector2]
var uv2s : Array[Vector2]
var color_0s : Array[Color]
var color_1s : Array[Color]
var g_masks : Array[Color]
var mat_blends : Array[Color]
var cell_coords : Vector2i

var floors : Array[bool]

var floor_mode : bool

var ay: float
var by: float
var dy: float
var cy: float

var _ay: float
var _by: float
var _cy: float
var _dy: float

var ab: bool
var bd: bool
var cd: bool
var ac: bool

var rotation: CellRotation:
	set(x):
		match x:
			CellRotation.DEG90: ay = _by
			CellRotation.DEG180: ay = _dy
			CellRotation.DEG270: ay = _cy
			_: ay = _ay
			
		match x:
			CellRotation.DEG90: by = _dy
			CellRotation.DEG180: by = _cy
			CellRotation.DEG270: by = _ay
			_: by = _by
			
		match  x:
			CellRotation.DEG90: dy = _cy
			CellRotation.DEG180: dy = _ay
			CellRotation.DEG270: dy = _by
			_: dy = _dy
			
		match  x:
			CellRotation.DEG90: cy = _ay
			CellRotation.DEG180: cy = _by
			CellRotation.DEG270: cy = _dy
			_: cy = _cy
		
		ab = abs(ay-by) < merge_threshold  # top edge
		bd = abs(by-dy) < merge_threshold # right edge
		cd = abs(cy-dy) < merge_threshold # bottom edge
		ac = abs(ay-cy) < merge_threshold # left edge
		
		rotation = x
		

var merge_threshold: float

var chunk: MarchingSquaresTerrainChunk


func _init(chunk_: MarchingSquaresTerrainChunk, y_top_left: float, y_top_right: float, y_bottom_left: float, y_bottom_right: float, merge_threshold_: float) -> void:
	chunk = chunk_
	_ay = y_top_left
	_by = y_top_right
	_cy = y_bottom_left
	_dy = y_bottom_right
	
	merge_threshold = merge_threshold_
	rotation = 0

func _reset_geometry_cache() -> void:
	pts = []
	uvs = []
	uv2s = []
	color_0s = []
	color_1s = []

func rotate(r: int) -> void:
	rotation = (4 + r + rotation) % 4


func all_edges_are_connected() -> bool:
	return ab and ac and bd and cd


# True if A is higher than B and outside of merge distance
func is_higher(a: float, b: float):
	return a - b > merge_threshold


# True if A is lower than B and outside of merge distance
func is_lower(a: float, b: float):
	return a - b < -merge_threshold


func is_merged(a: float, b: float):
	return abs(a - b) < merge_threshold


func generate_geometry(cell_coords_: Vector2i) -> void:
	cell_coords = cell_coords_
	
	_reset_geometry_cache()
	calculate_corner_colors()
	
	# Case 0
	# If all edges are connected, put a full floor here.
	if all_edges_are_connected():
		add_c0()
		chunk.add_polygons(cell_coords, pts, uvs, uv2s, color_0s, color_1s, g_masks, mat_blends, floors)
		return
	
	# Starting from the lowest corner, build the tile up
	var case_found: bool
	for rot in range(4):
		# Use the rotation of the corner - the amount of counter-clockwise rotations for it to become the top-left corner, which is just its index in the point lists.
		rotation = rot
		
		# if none of the branches are hit, this will be set to false at the last else statement.
		# opted for this instead of putting a break in every branch, that would take up space
		case_found = true
		
		# Case 1
		# If A is higher than adjacent and opposite corner is connected to adjacent,
		# add an outer corner here with upper and lower floor covering whole tile.
		if is_higher(ay, by) and is_higher(ay, cy) and bd and cd:
			add_c1()
		
		# Case 2
		# If A is higher than C and B is higher than D,
		# add an edge here covering whole tile.
		# (May want to prevent this if B and C are not within merge distance)
		elif is_higher(ay, cy) and is_higher(by, dy) and ab and cd:
			add_c2()
		
		# Case 3: AB edge with A outer corner above
		elif is_higher(ay, by) and is_higher(ay, cy) and is_higher(by, dy) and cd:
			add_c3()
		
		# Case 4: AB edge with B outer corner above
		elif is_higher(by, ay) and is_higher(ay, cy) and is_higher(by, dy) and cd:
			add_c4()
		
		# Case 5: B and C are higher than A and D.
		# Diagonal raised floor between B and C.
		# B and C must be within merge distance.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_merged(by, cy):
			add_c5()
		
		# Case 6: B and C are higher than A and D, and B is higher than C.
		# Place a raised diagonal floor between, and an outer corner around B.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_higher(by, cy):
			add_c6()
		
		# Case 7: inner corner, where A is lower than B and C, and D is connected to B and C.
		elif is_lower(ay, by) and is_lower(ay, cy) and bd and cd:
			add_c7()
		
		# Case 8: A is lower than B and C, B and C are merged, and D is higher than B and C.
		# Outer corner around A, and on top of that an inner corner around D
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and is_higher(dy, cy) and is_merged(by, cy):
			add_c8()
		
		# Case 9: Inner corner surrounding A, with an outer corner sitting atop C.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, cy) and bd:
			add_c9()
		
		# Case 10: Inner corner surrounding A, with an outer corner sitting atop B.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and cd:
			add_c10()
		
		# Case 11: Inner corner surrounding A, with an edge sitting atop BD.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, cy) and bd:
			add_c11()
		
		# Case 12: Inner corner surrounding A, with an edge sitting atop CD.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and cd:
			add_c12()
		
		# Case 13: Clockwise upwards spiral with A as the highest lowest point and C as the highest. A is lower than B, B is lower than D, D is lower than C, and C is higher than A.
		elif is_lower(ay, by) and is_lower(by, dy) and is_lower(dy, cy) and is_higher(cy, ay):
			add_c13()
		
		# Case 14: Clockwise upwards spiral, A lowest and B highest
		elif is_lower(ay, cy) and is_lower(cy, dy) and is_lower(dy, by) and is_higher(by, ay):
			add_c14()
		
		# Case 15: A<B, B<C, C<D
		elif is_lower(ay, by) and is_lower(by, cy) and is_lower(cy, dy):
			add_c15()
		
		# Case 16: A<C, C<B, B<D
		elif is_lower(ay, cy) and is_lower(cy, by) and is_lower(by, dy):
			add_c16()
		
		# Case 17: All edges are connected, except AC, and A is higher than C.
		elif ab and bd and cd and is_higher(ay, cy):
			add_c17()
		
		# Case 18: All edges are connected, except BD, and B is higher than D.
		# Make an edge here, but merge one side of the edge together
		elif ab and ac and cd and is_higher(by, dy):
			add_c18()
		
		else:
			case_found = false
		
		if case_found:
			break
	
	if not case_found:
		#Invalid / unknown cell type. put a full floor here and hope it looks fine
		add_c0()
		
	chunk.add_polygons(cell_coords, pts, uvs, uv2s, color_0s, color_1s, g_masks, mat_blends, floors)

func start_floor() -> void:
	floor_mode = true
	
func start_wall() -> void:
	floor_mode = false

func add_point(x: float, y: float, z: float, u: float, v: float, diag_midpoint: bool = false):
	for i in range(rotation as int):
		var temp := x
		x = 1 - z
		z = temp
	
	var blend_threshold : float = merge_threshold * BLEND_EDGE_SENSITIVITY # We can tweak the BLEND_EDGE_SENSITIVITY to allow more "agressive" Cliff vs Slope detection
	var blend_ab : bool = abs(ay-by) < blend_threshold
	var blend_ac : bool = abs(ay-cy) < blend_threshold
	var blend_bd : bool = abs(by-dy) < blend_threshold
	var blend_cd : bool = abs(cy-dy) < blend_threshold
	var cell_has_walls_for_blend : bool = not (blend_ab and blend_ac and blend_bd and blend_cd)
	
	# UV - used for ledge detection. X = closeness to top terrace, Y = closeness to bottom of terrace
	# Walls will always have UV of 1, 1
	var uv := Vector2(u, v) if floor_mode else Vector2(1, 1)
	

	# Detect ridge BEFORE selecting color maps (ridge needs wall colors, not ground colors)
	var is_ridge := floor_mode and chunk.terrain_system.use_ridge_texture and (uv.y > 1.0 - chunk.terrain_system.ridge_threshold)

	# Get color source maps based on floor/wall/ridge state
	var sources := _get_color_sources(floor_mode, is_ridge)
	var source_map_0 : PackedColorArray = sources[0]
	var source_map_1 : PackedColorArray = sources[1]
	var use_wall_colors := (source_map_0 == chunk.wall_color_map_0)

	# Calculate vertex colors using appropriate interpolation method
	var lower_0 : Color = cell_wall_lower_color_0 if use_wall_colors else cell_floor_lower_color_0
	var upper_0 : Color = cell_wall_upper_color_0 if use_wall_colors else cell_floor_upper_color_0
	var color_0 := _interpolate_vertex_color(x, y, z, source_map_0, diag_midpoint, lower_0, upper_0)

	var lower_1 : Color = cell_wall_lower_color_1 if use_wall_colors else cell_floor_lower_color_1
	var upper_1 : Color = cell_wall_upper_color_1 if use_wall_colors else cell_floor_upper_color_1
	var color_1 := _interpolate_vertex_color(x, y, z, source_map_1, diag_midpoint, lower_1, upper_1)

	# is_ridge already calculated above
	var g_mask: Color = Color(chunk.grass_mask_map[cell_coords.y*chunk.dimensions.x + cell_coords.x])
	g_mask.g = 1.0 if is_ridge else 0.0
	
	# Use edge connection to determine blending path
	# Avoid issues on weird Cliffs vs Slopes blending giving each a different path
	var mat_blend : Color = calculate_material_blend_data(x, z, source_map_0, source_map_1)
	if cell_has_walls_for_blend and floor_mode:
		mat_blend.a = 2.0 
	
	# same calculations from here
	var vert = Vector3((cell_coords.x+x) * chunk.cell_size.x, y, (cell_coords.y+z) * chunk.cell_size.y)
	var uv2 : Vector2
	if floor_mode:
		uv2 = Vector2(vert.x, vert.z) / chunk.cell_size
	else:
		# This avoids is_inside_tree() errors when inactive scene tabs are loaded
		var chunk_pos : Vector3 = chunk.global_position_cached
		var global_pos = vert + chunk_pos
		uv2 = (Vector2(global_pos.x, global_pos.y) + Vector2(global_pos.z, global_pos.y))
	
	pts.append(vert)
	uvs.append(uv)
	uv2s.append(uv2)
	g_masks.append(g_mask)
	color_0s.append(color_0)
	color_1s.append(color_1)
	mat_blends.append(mat_blend)
	floors.append(floor_mode)


func add_c0() -> void:
	add_full_floor(chunk)


func add_c1() -> void:
	add_outer_corner(chunk, true, true)


func add_c2() -> void:
	add_edge(chunk, true, true)


func add_c3() -> void:
	add_edge(chunk, true, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)


func add_c4() -> void:
	add_edge(chunk, true, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)


func add_c5() -> void:
	add_inner_corner(chunk, true, false)
	add_diagonal_floor(chunk, by, cy, true, true)
	rotate(2)
	add_inner_corner(chunk, true, false)


func add_c6() -> void:
	add_inner_corner(chunk ,true, false, true)
	add_diagonal_floor(chunk, cy, cy, true, true)
	
	# opposite lower floor
	rotate(2)
	add_inner_corner(chunk, true, false, true)
	
	# higher corner B
	rotate(-1)
	add_outer_corner(chunk, false, true)


func add_c7() -> void:
	add_inner_corner(chunk, true, true)


func add_c8() -> void:
	add_inner_corner(chunk, true, false)
	add_diagonal_floor(chunk, by, cy, true, false)
	rotate(2)
	add_outer_corner(chunk, false, true)


func add_c9() -> void:
	add_inner_corner(chunk, true, false, true)
	start_floor()
	
	# D corner. B edge is connected, so use halfway point bewteen B and D
	add_point(1, dy, 1, 0, 0)
	add_point(0.5, dy, 1, 1, 0)
	add_point(1, (by+dy)/2, 0.5, 0, 0)
	
	# B corner
	add_point(1, by, 0, 0, 0)
	add_point(1, (by+dy)/2, 0.5, 0, 0)
	add_point(0.5, by, 0, 0, 1)
	
	# Center floors
	add_point(0.5, by, 0, 0, 1)
	add_point(1, (by+dy)/2, 0.5, 0, 0)
	add_point(0, by, 0.5, 1, 1)
	
	add_point(0.5, dy, 1, 1, 0)
	add_point(0, by, 0.5, 1, 1)
	add_point(1, (by+dy)/2, 0.5, 0, 0)
	
	# Walls to upper corner
	start_wall()
	add_point(0, by, 0.5, 0, 0)
	add_point(0.5, dy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 0)
	
	add_point(0.5, cy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 0)
	add_point(0.5, dy, 1, 0, 0)
	
	# C upper floor
	start_floor()
	add_point(0, cy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 1)
	add_point(0.5, cy, 1, 0, 1)


func add_c10() -> void:
	add_inner_corner(chunk, true, false, true)
	
	# D corner. C edge is connected, so use halfway point bewteen C and D
	start_floor()
	add_point(1, dy, 1, 0, 0)
	add_point(0.5, (dy + cy) / 2, 1, 0, 0)
	add_point(1, dy, 0.5, 0, 0)
	
	# C corner
	add_point(0, cy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 0)
	add_point(0.5, (dy + cy) / 2, 1, 0, 0)
	
	# Center floors
	add_point(0, cy, 0.5, 0, 0)
	add_point(0.5, cy, 0, 0, 0)
	add_point(0.5, (dy + cy) / 2, 1, 0, 0)
	
	add_point(1, dy, 0.5, 0, 0)
	add_point(0.5, (dy + cy) / 2, 1, 0, 0)
	add_point(0.5, cy, 0, 0, 0)
	
	# Walls to upper corner
	start_wall()
	add_point(0.5, cy, 0, 0, 0)
	add_point(0.5, by, 0, 0, 0)
	add_point(1, dy, 0.5, 0, 0)

	add_point(1, by, 0.5, 0, 0)
	add_point(1, dy, 0.5, 0, 0)
	add_point(0.5, by, 0, 0, 0)
	
	# B upper floor
	start_floor()
	add_point(1, by, 0, 0, 0)
	add_point(1, by, 0.5, 0, 0)
	add_point(0.5, by, 0, 0, 0)


func add_c11() -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true)


func add_c12() -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true)


func add_c13() -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)


func add_c14() -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)


func add_c15() -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)


func add_c16() -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)


func add_c17() -> void:
	var edge_by = (by + dy) / 2
	var edge_dy = (by + dy) / 2
	
	# Upper floor
	start_floor()
	add_point(0, ay, 0, 0, 0)
	add_point(1, by, 0, 0, 0)
	add_point(1, edge_by, 0.5, 0, 0)
	
	add_point(1, edge_by, 0.5, 0, 1)
	add_point(0, ay, 0.5, 0, 1)
	add_point(0, ay, 0, 0, 0)
	
	# Wall
	start_wall()
	add_point(0, cy, 0.5, 0, 0)
	add_point(0, ay, 0.5, 0, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	
	# Lower floor
	start_floor()
	add_point(0, cy, 0.5, 1, 0)
	add_point(1, edge_dy, 0.5, 1, 0)
	add_point(0, cy, 1, 0, 0)
	
	add_point(1, dy, 1, 0, 0)
	add_point(0, cy, 1, 0, 0)
	add_point(1, edge_dy, 0.5, 0, 0)


func add_c18() -> void:
	# Only merge the ay/cy edge if AC edge is connected
	var edge_ay = (ay+cy)/2
	var edge_cy = (ay+cy)/2
	
	# Upper floor - use A and B edge for heights
	start_floor()
	add_point(0, ay, 0, 0, 0)
	add_point(1, by, 0, 0, 0)
	add_point(0, edge_ay, 0.5, 0, 0)
	
	add_point(1, by, 0.5, 0, 1)
	add_point(0, edge_ay, 0.5, 0, 1)
	add_point(1, by, 0, 0, 0)
	
	# Wall from left to right edge
	start_wall()
	add_point(1, by, 0.5, 1, 1)
	add_point(1, dy, 0.5, 1, 0)
	add_point(0, edge_ay, 0.5, 0, 0)
	
	# Lower floor - use C and D edge
	start_floor()
	add_point(0, edge_cy, 0.5, 1, 0)
	add_point(1, dy, 0.5, 1, 0)
	add_point(1, dy, 1, 0, 0)
	
	add_point(0, cy, 1, 0, 0)
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(1, dy, 1, 0, 0)


func add_full_floor(chunk: MarchingSquaresTerrainChunk):
	start_floor()
	
	add_point(0, ay, 0, 0, 0)
	add_point(1, by, 0, 0, 0)
	add_point(0, cy, 1, 0, 0)
	
	add_point(1, dy, 1, 0, 0)
	add_point(0, cy, 1, 0, 0)
	add_point(1, by, 0, 0, 0)


# Add an outer corner, where A is the raised corner.
# if flatten_bottom is true, then bottom_height is used for the lower height of the wall
func add_outer_corner(chunk: MarchingSquaresTerrainChunk, floor_below: bool = true, floor_above: bool = true, flatten_bottom: bool = false, bottom_height: float = -1):
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
		add_point(1, dy, 1,0,0)
		add_point(0, cy, 1,0,0)
		add_point(1, by, 0,0,0)	
		
		add_point(0, cy, 1,0,0)
		add_point(0, cy, 0.5, 1, 0)
		add_point(0.5, by, 0, 1, 0)
		
		add_point(1, by, 0,0,0)	
		add_point(0, cy, 1,0,0)
		add_point(0.5, by, 0, 1, 0)


# Add an edge, where AB is the raised edge.
# a_x is the x coordinate that the top-left of the uper floor connects to
# b_x is the x coordinate that the top-right of the upper floor connects to
func add_edge(chunk: MarchingSquaresTerrainChunk, floor_below: bool, floor_above: bool, a_x: float = 0, b_x: float = 1):
	# If A and B are out of merge distance, use the lower of the two
	var edge_ay = ay if ab else min(ay, by)
	var edge_by = by if ab else min(ay, by)
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
		add_point(0, cy, 1, 0, 0)
		
		add_point(1, dy, 1, 0, 0)
		add_point(0, cy, 1, 0, 0)
		add_point(1, dy, 0.5, 1, 0)


# Add an inner corner, where A is the lowered corner.
func add_inner_corner(chunk: MarchingSquaresTerrainChunk, lower_floor: bool = true, full_upper_floor: bool = true, flatten: bool = false, bd_floor: bool = false, cd_floor: bool = false):
	var corner_by = min(by, cy) if flatten else by
	var corner_cy = min(by, cy) if flatten else cy
	
	# Lower floor with height of point A
	if lower_floor:
		start_floor()
		add_point(0, ay, 0, 0, 0)
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
		add_point(1, dy, 1, 0, 0)
		add_point(0, corner_cy, 1, 0, 0)
		add_point(1, corner_by, 0, 0, 0)
		
		add_point(0, corner_cy, 1, 0, 0)
		add_point(0, corner_cy, 0.5, 0, 1)
		add_point(0.5, corner_by, 0, 0, 1)
		
		add_point(1, corner_by, 0, 0, 0)
		add_point(0, corner_cy, 1, 0, 0)
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
func add_diagonal_floor(chunk: MarchingSquaresTerrainChunk, b_y: float, c_y: float, a_cliff: bool, d_cliff: bool):
	start_floor()
	
	add_point(1, b_y, 0, 0 ,0)
	add_point(0, c_y, 1, 0 ,0)
	add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0)
	
	add_point(0, c_y, 1, 0, 0)
	add_point(0, c_y, 0.5, 0 if a_cliff else 1, 1 if a_cliff else 0)
	add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0)
	
	add_point(1, b_y, 0, 0 ,0)
	add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0)
	add_point(0, c_y, 1, 0 ,0)
	
	add_point(0, c_y, 1, 0, 0)
	add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0)
	add_point(0.5, c_y, 1, 0 if d_cliff else 1, 1 if d_cliff else 0)
	

func calculate_corner_colors():
	# Calculate cell height range for boundary detection (height-based color sampling)
	cell_min_height = min(ay, by, cy, dy)
	cell_max_height = max(ay, by, cy, dy)
	
	var x = cell_coords.x
	var z = cell_coords.y
	
	# Determine if this is a boundary cell (significant height variation)
	cell_is_boundary = (cell_max_height - cell_min_height) > merge_threshold
	
	# Calculate the 2 dominant textures for this cell
	calculate_cell_material_pair(chunk.color_map_0, chunk.color_map_1)
	
	if cell_is_boundary:
		# Identify corners at each height level for height-based color sampling
		# FLOOR colors - from color_map (used for regular floor vertices)
		var floor_corner_colors_0 = [
			chunk.color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var floor_corner_colors_1 = [
			chunk.color_map_1[z * chunk.dimensions.x + x],
			chunk.color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
		]
		# WALL colors - from wall_color_map (used for wall/ridge vertices)
		var wall_corner_colors_0 = [
			chunk.wall_color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.wall_color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var wall_corner_colors_1 = [
			chunk.wall_color_map_1[z * chunk.dimensions.x + x],
			chunk.wall_color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
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


# Calculate 2 dominant textures for current cell 
func calculate_cell_material_pair(source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> void:
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1])
	
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


## Calculates height-based color for boundary cells (prevents color bleeding between heights)
func _calc_boundary_color(y: float, source_map: PackedColorArray, lower_color: Color, upper_color: Color) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses cell's corner color
		return source_map[cell_coords.y * chunk.dimensions.x + cell_coords.x]

	# HEIGHT-BASED SAMPLING for smooth blend mode
	var height_range := cell_max_height - cell_min_height
	var height_factor : float = clamp((y - cell_min_height) / height_range, 0.0, 1.0)

	# Sharp bands: < lower_thresh = lower color, > upper_thresh = upper color, middle = blend
	var color: Color
	if height_factor < chunk.lower_thresh:
		color = lower_color
	elif height_factor > chunk.upper_thresh:
		color = upper_color
	else:
		var blend_factor : float = (height_factor - chunk.lower_thresh) / chunk.blend_zone
		color = lerp(lower_color, upper_color, blend_factor)

	return get_dominant_color(color)
	
	
#region color interpolation Helpers

## Returns [source_map_0, source_map_1] based on floor/wall/ridge state
func _get_color_sources(is_floor: bool, is_ridge: bool) -> Array[PackedColorArray]:
	var use_wall_colors := (not is_floor) or is_ridge
	if chunk.terrain_system.blend_mode == 1 and is_floor and not is_ridge:
		use_wall_colors = false  # Only force floor colors for non-ridge floor vertices

	var src_0 : PackedColorArray = chunk.wall_color_map_0 if use_wall_colors else chunk.color_map_0
	var src_1 : PackedColorArray = chunk.wall_color_map_1 if use_wall_colors else chunk.color_map_1
	return [src_0, src_1]


## Calculates color for diagonal midpoint vertices
func _calc_diagonal_color(source_map: PackedColorArray) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses same color as cell's top-left corner
		return source_map[cell_coords.y * chunk.dimensions.x + cell_coords.x]

	# Smooth blend mode - lerp diagonal corners for smoother effect
	var idx := cell_coords.y * chunk.dimensions.x + cell_coords.x
	var ad_color : Color = lerp(source_map[idx], source_map[idx + chunk.dimensions.x + 1], 0.5)
	var bc_color : Color = lerp(source_map[idx + 1], source_map[idx + chunk.dimensions.x], 0.5)
	var result := Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
	if ad_color.r > 0.99 or bc_color.r > 0.99: result.r = 1.0
	if ad_color.g > 0.99 or bc_color.g > 0.99: result.g = 1.0
	if ad_color.b > 0.99 or bc_color.b > 0.99: result.b = 1.0
	if ad_color.a > 0.99 or bc_color.a > 0.99: result.a = 1.0
	return result


## Calculates bilinearly interpolated color for flat cells
func _calc_bilinear_color(x: float, z: float, source_map: PackedColorArray) -> Color:
	var idx := cell_coords.y * chunk.dimensions.x + cell_coords.x
	var ab_color : Color = lerp(source_map[idx], source_map[idx + 1], x)
	var cd_color : Color = lerp(source_map[idx + chunk.dimensions.x], source_map[idx + chunk.dimensions.x + 1], x)

	if chunk.terrain_system.blend_mode != 1:
		return get_dominant_color(lerp(ab_color, cd_color, z))  # Mixed triangles
	return source_map[idx]  # hard squares/hard triangles

## selects the appropriate color interpolation method
func _interpolate_vertex_color(
	x: float, y: float, z: float,
	source_map: PackedColorArray,
	diag_midpoint: bool,
	lower_color: Color,
	upper_color: Color
) -> Color:
	if diag_midpoint:
		return _calc_diagonal_color(source_map)

	if cell_is_boundary:
		return _calc_boundary_color(y, source_map, lower_color, upper_color)

	return _calc_bilinear_color(x, z, source_map)

#endregion

#region cell_geometry helpers and calculation functions

static func get_dominant_color(c: Color) -> Color:
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


# Calculate CUSTOM2 blend data with 3 texture support 
# Encoding: Color(packed_mats, mat_c/15, weight_a, weight_b)
# R: (mat_a + mat_b * 16) / 255.0  (packs 2 indices, each 0-15)
# G: mat_c / 15.0
# B: weight_a (0.0 to 1.0)
# A: weight_b (0.0 to 1.0), or 2.0 to signal use_vertex_colors
func calculate_material_blend_data(vert_x: float, vert_z: float, source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> Color:
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1])
	
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
