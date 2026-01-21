extends MarchingSquaresTerrainCell
class_name MarchingSquaresProceduralCell

func add_c0(chunk: MarchingSquaresTerrainChunk) -> void:
	add_full_floor(chunk)

func add_c1(chunk: MarchingSquaresTerrainChunk) -> void:
	add_outer_corner(chunk, true, true)
	
func add_c2(chunk: MarchingSquaresTerrainChunk) -> void:
	add_edge(chunk, true, true)
	
func add_c3(chunk: MarchingSquaresTerrainChunk) -> void:
	add_edge(chunk, true, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)
	
func add_c4(chunk: MarchingSquaresTerrainChunk) -> void:
	add_edge(chunk, true, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)
	
func add_c5(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false)
	add_diagonal_floor(chunk, by, cy, rotation, true, true)
	rotate(2)
	add_inner_corner(chunk, true, false)

func add_c5b(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk ,true, false, true)
	add_diagonal_floor(chunk, cy, cy, rotation, true, true)
	
	# opposite lower floor
	rotate(2)
	add_inner_corner(chunk, true, false, true)
	
	# higher corner B
	rotate(-1)
	add_outer_corner(chunk, false, true)
	
func add_c6(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, true)
	
func add_c7(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false)
	add_diagonal_floor(chunk, by, cy, rotation, true, false)
	rotate(2)
	add_outer_corner(chunk, false, true)
	
func add_c8(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true)
	chunk.start_floor()
	
	# D corner. B edge is connected, so use halfway point bewteen B and D
	chunk.add_point(1, dy, 1, 0, 0, rotation)
	chunk.add_point(0.5, dy, 1, 1, 0, rotation)
	chunk.add_point(1, (by+dy)/2, 0.5, 0, 0, rotation)
	
	# B corner
	chunk.add_point(1, by, 0, 0, 0, rotation)
	chunk.add_point(1, (by+dy)/2, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, by, 0, 0, 1, rotation)
	
	# Center floors
	chunk.add_point(0.5, by, 0, 0, 1, rotation)
	chunk.add_point(1, (by+dy)/2, 0.5, 0, 0, rotation)
	chunk.add_point(0, by, 0.5, 1, 1, rotation)
	
	chunk.add_point(0.5, dy, 1, 1, 0, rotation)
	chunk.add_point(0, by, 0.5, 1, 1, rotation)
	chunk.add_point(1, (by+dy)/2, 0.5, 0, 0, rotation)
	#
	# Walls to upper corner
	chunk.start_wall()
	chunk.add_point(0, by, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, dy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 0.5, 0, 0, rotation)
	
	chunk.add_point(0.5, cy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, dy, 1, 0, 0, rotation)
	
	# C upper floor
	chunk.start_floor()
	chunk.add_point(0, cy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 0.5, 0, 1, rotation)
	chunk.add_point(0.5, cy, 1, 0, 1, rotation)
	
func add_c9(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true)
	
	# D corner. C edge is connected, so use halfway point bewteen C and D
	chunk.start_floor()
	chunk.add_point(1, dy, 1, 0, 0, rotation)
	chunk.add_point(0.5, (dy + cy) / 2, 1, 0, 0, rotation)
	chunk.add_point(1, dy, 0.5, 0, 0, rotation)

	# C corner
	chunk.add_point(0, cy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, (dy + cy) / 2, 1, 0, 0, rotation)

	# Center floors
	chunk.add_point(0, cy, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, cy, 0, 0, 0, rotation)
	chunk.add_point(0.5, (dy + cy) / 2, 1, 0, 0, rotation)

	chunk.add_point(1, dy, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, (dy + cy) / 2, 1, 0, 0, rotation)
	chunk.add_point(0.5, cy, 0, 0, 0, rotation)

	# Walls to upper corner
	chunk.start_wall()
	chunk.add_point(0.5, cy, 0, 0, 0, rotation)
	chunk.add_point(0.5, by, 0, 0, 0, rotation)
	chunk.add_point(1, dy, 0.5, 0, 0, rotation)

	chunk.add_point(1, by, 0.5, 0, 0, rotation)
	chunk.add_point(1, dy, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, by, 0, 0, 0, rotation)

	# B upper floor
	chunk.start_floor()
	chunk.add_point(1, by, 0, 0, 0, rotation)
	chunk.add_point(1, by, 0.5, 0, 0, rotation)
	chunk.add_point(0.5, by, 0, 0, 0, rotation)
	
func add_c10(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true)
	
func add_c11(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true)
	
func add_c12(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)
	
func add_c13(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)
	
func add_c14(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, false, true)
	rotate(2)
	add_edge(chunk, false, true, 0.5, 1)
	add_outer_corner(chunk, false, true, true, by)
	
func add_c15(chunk: MarchingSquaresTerrainChunk) -> void:
	add_inner_corner(chunk, true, false, true, true, false)
	rotate(1)
	add_edge(chunk, false, true, 0, 0.5)
	rotate(1)
	add_outer_corner(chunk, false, true, true, cy)
	
func add_c16(chunk: MarchingSquaresTerrainChunk) -> void:
	var edge_by = (by + dy) / 2
	var edge_dy = (by + dy) / 2

	# Upper floor
	chunk.start_floor()
	chunk.add_point(0, ay, 0, 0, 0, rotation)
	chunk.add_point(1, by, 0, 0, 0, rotation)
	chunk.add_point(1, edge_by, 0.5, 0, 0, rotation)

	chunk.add_point(1, edge_by, 0.5, 0, 1, rotation)
	chunk.add_point(0, ay, 0.5, 0, 1, rotation)
	chunk.add_point(0, ay, 0, 0, 0, rotation)

	# Wall
	chunk.start_wall()
	chunk.add_point(0, cy, 0.5, 0, 0, rotation)
	chunk.add_point(0, ay, 0.5, 0, 1, rotation)
	chunk.add_point(1, edge_dy, 0.5, 1, 0, rotation)

	# Lower floor
	chunk.start_floor()
	chunk.add_point(0, cy, 0.5, 1, 0, rotation)
	chunk.add_point(1, edge_dy, 0.5, 1, 0, rotation)
	chunk.add_point(0, cy, 1, 0, 0, rotation)

	chunk.add_point(1, dy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 1, 0, 0, rotation)
	chunk.add_point(1, edge_dy, 0.5, 0, 0, rotation)
	
func add_c17(chunk: MarchingSquaresTerrainChunk) -> void:
	# Only merge the ay/cy edge if AC edge is connected
	var edge_ay = (ay+cy)/2
	var edge_cy = (ay+cy)/2
	
	# Upper floor - use A and B edge for heights
	chunk.start_floor()
	chunk.add_point(0, ay, 0, 0, 0, rotation)
	chunk.add_point(1, by, 0, 0, 0, rotation)
	chunk.add_point(0, edge_ay, 0.5, 0, 0, rotation)
	
	chunk.add_point(1, by, 0.5, 0, 1, rotation)
	chunk.add_point(0, edge_ay, 0.5, 0, 1, rotation)
	chunk.add_point(1, by, 0, 0, 0, rotation)
	
	# Wall from left to right edge
	chunk.start_wall()
	chunk.add_point(1, by, 0.5, 1, 1, rotation)
	chunk.add_point(1, dy, 0.5, 1, 0, rotation)
	chunk.add_point(0, edge_ay, 0.5, 0, 0, rotation)
	
	# Lower floor - use C and D edge
	chunk.start_floor()
	chunk.add_point(0, edge_cy, 0.5, 1, 0, rotation)
	chunk.add_point(1, dy, 0.5, 1, 0, rotation)
	chunk.add_point(1, dy, 1, 0, 0, rotation)
	
	chunk.add_point(0, cy, 1, 0, 0, rotation)
	chunk.add_point(0, edge_cy, 0.5, 0, 0, rotation)
	chunk.add_point(1, dy, 1, 0, 0, rotation)

func add_full_floor(chunk: MarchingSquaresTerrainChunk):
	chunk.start_floor()
	
	chunk.add_point(0, ay, 0, 0, 0, rotation)
	chunk.add_point(1, by, 0, 0, 0, rotation)
	chunk.add_point(0, cy, 1, 0, 0, rotation)

	chunk.add_point(1, dy, 1, 0, 0, rotation)
	chunk.add_point(0, cy, 1, 0, 0, rotation)
	chunk.add_point(1, by, 0, 0, 0, rotation)
	
# Add an outer corner, where A is the raised corner.
# if flatten_bottom is true, then bottom_height is used for the lower height of the wall
func add_outer_corner(chunk: MarchingSquaresTerrainChunk, floor_below: bool = true, floor_above: bool = true, flatten_bottom: bool = false, bottom_height: float = -1):
	var edge_by = bottom_height if flatten_bottom else by
	var edge_cy = bottom_height if flatten_bottom else cy
	
	if floor_above:
		chunk.start_floor()
		chunk.add_point(0, ay, 0, 0, 0, rotation)
		chunk.add_point(0.5, ay, 0, 0, 1, rotation)
		chunk.add_point(0, ay, 0.5, 0, 1, rotation)
	
	# Walls - bases will use B and C height, while cliff top will use A height.
	chunk.start_wall()
	chunk.add_point(0, edge_cy, 0.5, 0, 0, rotation)
	chunk.add_point(0, ay, 0.5, 0, 1, rotation)
	chunk.add_point(0.5, edge_by, 0, 1, 0, rotation)
	
	chunk.add_point(0.5, ay, 0, 1, 1, rotation)
	chunk.add_point(0.5, edge_by, 0, 1, 0, rotation)
	chunk.add_point(0, ay, 0.5, 0, 1, rotation)

	if floor_below:
		chunk.start_floor()
		chunk.add_point(1, dy, 1,0,0, rotation)
		chunk.add_point(0, cy, 1,0,0, rotation)
		chunk.add_point(1, by, 0,0,0, rotation)	
		
		chunk.add_point(0, cy, 1,0,0, rotation)
		chunk.add_point(0, cy, 0.5, 1, 0, rotation)
		chunk.add_point(0.5, by, 0, 1, 0, rotation)
		
		chunk.add_point(1, by, 0,0,0, rotation)	
		chunk.add_point(0, cy, 1,0,0, rotation)
		chunk.add_point(0.5, by, 0, 1, 0, rotation)

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
		chunk.add_point(a_x, edge_ay, 0, 1 if a_x > 0 else 0, 0, rotation)
		chunk.add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0, rotation)
		chunk.add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1, rotation)
		
		chunk.add_point(1, edge_by, 0.5, -1 if a_x > 0  else (1 if b_x < 1 else 0), 1, rotation)
		chunk.add_point(0, edge_ay, 0.5, -1 if b_x < 1 else (1 if a_x > 0 else 0), 1, rotation)
		chunk.add_point(b_x, edge_by, 0, 1 if b_x < 1 else 0, 0, rotation)
	
	# Wall from left to right edge
	chunk.start_wall()
	chunk.add_point(0, edge_cy, 0.5, 0, 0, rotation)
	chunk.add_point(0, edge_ay, 0.5, 0, 1, rotation)
	chunk.add_point(1, edge_dy, 0.5, 1, 0, rotation)
	
	chunk.add_point(1, edge_by, 0.5, 1, 1, rotation)
	chunk.add_point(1, edge_dy, 0.5, 1, 0, rotation)
	chunk.add_point(0, edge_ay, 0.5, 0, 1, rotation)
	
	# Lower floor - use C and D for height
	# Only place a flat floor below if CD is connected
	if floor_below:
		chunk.start_floor()
		chunk.add_point(0, cy, 0.5, 1, 0, rotation)
		chunk.add_point(1, dy, 0.5, 1, 0, rotation)
		chunk.add_point(0, cy, 1, 0, 0, rotation)
		
		chunk.add_point(1, dy, 1, 0, 0, rotation)
		chunk.add_point(0, cy, 1, 0, 0, rotation)
		chunk.add_point(1, dy, 0.5, 1, 0, rotation)
		
	# Add an inner corner, where A is the lowered corner.
func add_inner_corner(chunk: MarchingSquaresTerrainChunk, lower_floor: bool = true, full_upper_floor: bool = true, flatten: bool = false, bd_floor: bool = false, cd_floor: bool = false):
	var corner_by = min(by, cy) if flatten else by
	var corner_cy = min(by, cy) if flatten else cy
	
	# Lower floor with height of point A
	if lower_floor:
		chunk.start_floor()
		chunk.add_point(0, ay, 0, 0, 0, rotation)
		chunk.add_point(0.5, ay, 0, 1, 0, rotation)
		chunk.add_point(0, ay, 0.5, 1, 0, rotation)

	chunk.start_wall()
	chunk.add_point(0, ay, 0.5, 1, 0, rotation)
	chunk.add_point(0.5, ay, 0, 0, 0, rotation)
	chunk.add_point(0, corner_cy, 0.5, 1, 1, rotation)
	
	chunk.add_point(0.5, corner_by, 0, 0, 1, rotation)
	chunk.add_point(0, corner_cy, 0.5, 1, 1, rotation)
	chunk.add_point(0.5, ay, 0, 0, 0, rotation)

	chunk.start_floor()
	if full_upper_floor:
		chunk.add_point(1, dy, 1, 0, 0, rotation)
		chunk.add_point(0, corner_cy, 1, 0, 0, rotation)
		chunk.add_point(1, corner_by, 0, 0, 0, rotation)
		
		chunk.add_point(0, corner_cy, 1, 0, 0, rotation)
		chunk.add_point(0, corner_cy, 0.5, 0, 1, rotation)
		chunk.add_point(0.5, corner_by, 0, 0, 1, rotation)
		
		chunk.add_point(1, corner_by, 0, 0, 0, rotation)
		chunk.add_point(0, corner_cy, 1, 0, 0, rotation)
		chunk.add_point(0.5, corner_by, 0, 0, 1, rotation)
		
	# if C and D are both higher than B, and B does not connect the corners, there's an edge above, place floors that will connect to the CD edge
	if cd_floor:
		# use height of B corner
		chunk.add_point(1, by, 0, 0, 0, rotation)
		chunk.add_point(0, by, 0.5, 1, 1, rotation)
		chunk.add_point(0.5, by, 0, 0, 1, rotation)
		
		chunk.add_point(1, by, 0, 0, 0, rotation)
		chunk.add_point(1, by, 0.5, 1, -1, rotation)
		chunk.add_point(0, by, 0.5, 1, 1, rotation)
		
	# if B and D are both higher than C, and C does not connect the corners, there's an edge above, place floors that will connect to the BD edge
	if bd_floor: 
		chunk.add_point(0, cy, 0.5, 0, 1, rotation)
		chunk.add_point(0.5, cy, 0, 1, 1, rotation)
		chunk.add_point(0, cy, 1, 0, 0, rotation)
		
		chunk.add_point(0.5, cy, 1, 1, -1, rotation)
		chunk.add_point(0, cy, 1, 0, 0, rotation)
		chunk.add_point(0.5, cy, 0, 1, 1, rotation)


# Add a diagonal floor, using heights of B and C and connecting their points using passed heights.
func add_diagonal_floor(chunk: MarchingSquaresTerrainChunk, b_y: float, c_y: float, rot: CellRotation, a_cliff: bool, d_cliff: bool):
	chunk.start_floor()
	
	chunk.add_point(1, b_y, 0, 0 ,0 , rot)
	chunk.add_point(0, c_y, 1, 0 ,0 , rot)
	chunk.add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0, rot)
	
	chunk.add_point(0, c_y, 1, 0, 0,  rot)
	chunk.add_point(0, c_y, 0.5, 0 if a_cliff else 1, 1 if a_cliff else 0, rot)
	chunk.add_point(0.5, b_y, 0, 0 if a_cliff else 1, 1 if a_cliff else 0, rot)
	
	chunk.add_point(1, b_y, 0, 0 ,0 , rot)
	chunk.add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0, rot)
	chunk.add_point(0, c_y, 1, 0 ,0 , rot)
	
	chunk.add_point(0, c_y, 1, 0, 0, rot)
	chunk.add_point(1, b_y, 0.5, 0 if d_cliff else 1, 1 if d_cliff else 0, rot)
	chunk.add_point(0.5, c_y, 1, 0 if d_cliff else 1, 1 if d_cliff else 0, rot)
