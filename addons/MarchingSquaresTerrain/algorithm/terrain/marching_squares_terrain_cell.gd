extends RefCounted
class_name MarchingSquaresTerrainCell


# < 1.0 = more aggressive wall detection 
# > 1.0 = less aggressive / more slope blend
const BLEND_EDGE_SENSITIVITY : float = 1.25

enum CellRotation {DEG0 = 0, DEG270 = 3, DEG180 = 2, DEG90 = 1}

var ay: float: 
	get:
		match  rotation:
			CellRotation.DEG90: return _by
			CellRotation.DEG180: return _dy
			CellRotation.DEG270: return _cy
			_: return _ay

var by: float:
	get:
		match  rotation:
			CellRotation.DEG90: return _dy
			CellRotation.DEG180: return _cy
			CellRotation.DEG270: return _ay
			_: return _by

var dy: float:
	get:
		match  rotation:
			CellRotation.DEG90: return _cy
			CellRotation.DEG180: return _ay
			CellRotation.DEG270: return _by
			_: return _dy

var cy: float:
	get:
		match  rotation:
			CellRotation.DEG90: return _ay
			CellRotation.DEG180: return _by
			CellRotation.DEG270: return _dy
			_: return _cy

var _ay: float
var _by: float
var _cy: float
var _dy: float

var ab: bool: 
	get: return abs(ay-by) < merge_threshold  # top edge
var bd: bool:
	get: return abs(by-dy) < merge_threshold # right edge
var cd: bool:
	get: return abs(cy-dy) < merge_threshold # bottom edge
var ac: bool:
	get: return abs(ay-cy) < merge_threshold # left edge

var rotation: CellRotation

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


func generate_geometry() -> void:
	# Case 0
	# If all edges are connected, put a full floor here.
	if all_edges_are_connected():
		add_c0()
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
		
		# Case 12: Clockwise upwards spiral with A as the highest lowest point and C as the highest. A is lower than B, B is lower than D, D is lower than C, and C is higher than A.
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
	
	chunk.add_point(x, y, z, u, v, diag_midpoint, cell_has_walls_for_blend)


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
	chunk.start_floor()
	
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
	chunk.start_wall()
	add_point(0, by, 0.5, 0, 0)
	add_point(0.5, dy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 0)
	
	add_point(0.5, cy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 0)
	add_point(0.5, dy, 1, 0, 0)
	
	# C upper floor
	chunk.start_floor()
	add_point(0, cy, 1, 0, 0)
	add_point(0, cy, 0.5, 0, 1)
	add_point(0.5, cy, 1, 0, 1)


func add_c10() -> void:
	add_inner_corner(chunk, true, false, true)
	
	# D corner. C edge is connected, so use halfway point bewteen C and D
	chunk.start_floor()
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
	chunk.start_wall()
	add_point(0.5, cy, 0, 0, 0)
	add_point(0.5, by, 0, 0, 0)
	add_point(1, dy, 0.5, 0, 0)

	add_point(1, by, 0.5, 0, 0)
	add_point(1, dy, 0.5, 0, 0)
	add_point(0.5, by, 0, 0, 0)
	
	# B upper floor
	chunk.start_floor()
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
	chunk.start_floor()
	add_point(0, ay, 0, 0, 0)
	add_point(1, by, 0, 0, 0)
	add_point(1, edge_by, 0.5, 0, 0)
	
	add_point(1, edge_by, 0.5, 0, 1)
	add_point(0, ay, 0.5, 0, 1)
	add_point(0, ay, 0, 0, 0)
	
	# Wall
	chunk.start_wall()
	add_point(0, cy, 0.5, 0, 0)
	add_point(0, ay, 0.5, 0, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	
	# Lower floor
	chunk.start_floor()
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
	chunk.start_floor()
	add_point(0, ay, 0, 0, 0)
	add_point(1, by, 0, 0, 0)
	add_point(0, edge_ay, 0.5, 0, 0)
	
	add_point(1, by, 0.5, 0, 1)
	add_point(0, edge_ay, 0.5, 0, 1)
	add_point(1, by, 0, 0, 0)
	
	# Wall from left to right edge
	chunk.start_wall()
	add_point(1, by, 0.5, 1, 1)
	add_point(1, dy, 0.5, 1, 0)
	add_point(0, edge_ay, 0.5, 0, 0)
	
	# Lower floor - use C and D edge
	chunk.start_floor()
	add_point(0, edge_cy, 0.5, 1, 0)
	add_point(1, dy, 0.5, 1, 0)
	add_point(1, dy, 1, 0, 0)
	
	add_point(0, cy, 1, 0, 0)
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(1, dy, 1, 0, 0)


func add_full_floor(chunk: MarchingSquaresTerrainChunk):
	chunk.start_floor()
	
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
		chunk.start_floor()
		add_point(0, ay, 0, 0, 0)
		add_point(0.5, ay, 0, 0, 1)
		add_point(0, ay, 0.5, 0, 1)
	
	# Walls - bases will use B and C height, while cliff top will use A height.
	chunk.start_wall()
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(0, ay, 0.5, 0, 1)
	add_point(0.5, edge_by, 0, 1, 0)
	
	add_point(0.5, ay, 0, 1, 1)
	add_point(0.5, edge_by, 0, 1, 0)
	add_point(0, ay, 0.5, 0, 1)
	
	if floor_below:
		chunk.start_floor()
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
		chunk.start_floor()
		add_point(a_x, edge_ay, 0, 1 if a_x > 0 else 0, 0)
		add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0)
		add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1)
		
		add_point(1, edge_by, 0.5, -1 if a_x > 0  else (1 if b_x < 1 else 0), 1)
		add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1)
		add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0)
	
	# Wall from left to right edge
	chunk.start_wall()
	add_point(0, edge_cy, 0.5, 0, 0)
	add_point(0, edge_ay, 0.5, 0, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	
	add_point(1, edge_by, 0.5, 1, 1)
	add_point(1, edge_dy, 0.5, 1, 0)
	add_point(0, edge_ay, 0.5, 0, 1)
	
	# Lower floor - use C and D for height
	# Only place a flat floor below if CD is connected
	if floor_below:
		chunk.start_floor()
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
		chunk.start_floor()
		add_point(0, ay, 0, 0, 0)
		add_point(0.5, ay, 0, 1, 0)
		add_point(0, ay, 0.5, 1, 0)
	
	chunk.start_wall()
	add_point(0, ay, 0.5, 1, 0)
	add_point(0.5, ay, 0, 0, 0)
	add_point(0, corner_cy, 0.5, 1, 1)
	
	add_point(0.5, corner_by, 0, 0, 1)
	add_point(0, corner_cy, 0.5, 1, 1)
	add_point(0.5, ay, 0, 0, 0)
	
	chunk.start_floor()
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
	chunk.start_floor()
	
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
