extends RefCounted
class_name MarchingSquaresTerrainCell

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

func _init(y_top_left: float, y_top_right: float, y_bottom_left: float, y_bottom_right: float, merge_threshold_: float) -> void:
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
	
func generate_geometry(chunk) -> void:
	# Case 0
	# If all edges are connected, put a full floor here.
	if all_edges_are_connected():
		add_c0(chunk)
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
			add_c1(chunk)
		
		# Case 2
		# If A is higher than C and B is higher than D,
		# add an edge here covering whole tile.
		# (May want to prevent this if B and C are not within merge distance)
		elif is_higher(ay, cy) and is_higher(by, dy) and ab and cd:
			add_c2(chunk)
		
		# Case 3: AB edge with A outer corner above
		elif is_higher(ay, by) and is_higher(ay, cy) and is_higher(by, dy) and cd:
			add_c3(chunk)
		
		# Case 4: AB edge with B outer corner above
		elif is_higher(by, ay) and is_higher(ay, cy) and is_higher(by, dy) and cd:
			add_c4(chunk)
		
		# Case 5: B and C are higher than A and D.
		# Diagonal raised floor between B and C.
		# B and C must be within merge distance.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_merged(by, cy):
			add_c5(chunk)
		
		# Case 5.5: B and C are higher than A and D, and B is higher than C.
		# Place a raised diagonal floor between, and an outer corner around B.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and is_lower(dy, cy) and is_higher(by, cy):
			add_c5b(chunk)
		
		# Case 6: inner corner, where A is lower than B and C, and D is connected to B and C.
		elif is_lower(ay, by) and is_lower(ay, cy) and bd and cd:
			add_c6(chunk)
		
		# Case 7: A is lower than B and C, B and C are merged, and D is higher than B and C.
		# Outer corner around A, and on top of that an inner corner around D
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and is_higher(dy, cy) and is_merged(by, cy):
			add_c7(chunk)
		
		# Case 8: Inner corner surrounding A, with an outer corner sitting atop C.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, cy) and bd:
			add_c8(chunk)
		
		# Case 9: Inner corner surrounding A, with an outer corner sitting atop B.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_lower(dy, by) and cd:
			add_c9(chunk)

		# Case 10: Inner corner surrounding A, with an edge sitting atop BD.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, cy) and bd:
			add_c10(chunk)

		# Case 11: Inner corner surrounding A, with an edge sitting atop CD.
		elif is_lower(ay, by) and is_lower(ay, cy) and is_higher(dy, by) and cd:
			add_c11(chunk)
			
		# Case 12: Clockwise upwards spiral with A as the highest lowest point and C as the highest. A is lower than B, B is lower than D, D is lower than C, and C is higher than A.
		elif is_lower(ay, by) and is_lower(by, dy) and is_lower(dy, cy) and is_higher(cy, ay):
			add_c12(chunk)

		# Case 13: Clockwise upwards spiral, A lowest and B highest
		elif is_lower(ay, cy) and is_lower(cy, dy) and is_lower(dy, by) and is_higher(by, ay):
			add_c13(chunk)

		# Case 14: A<B, B<C, C<D
		elif is_lower(ay, by) and is_lower(by, cy) and is_lower(cy, dy):
			add_c14(chunk)

		# Case 15: A<C, C<B, B<D
		elif is_lower(ay, cy) and is_lower(cy, by) and is_lower(by, dy):
			add_c15(chunk)

		# Case 16: All edges are connected, except AC, and A is higher than C.
		elif ab and bd and cd and is_higher(ay, cy):
			add_c16(chunk)
		
		# Case 17: All edges are connected, except BD, and B is higher than D.
		# Make an edge here, but merge one side of the edge together
		elif ab and ac and cd and is_higher(by, dy):
			add_c17(chunk)
		
		else:
			case_found = false
		
		if case_found:
			break
			
	if not case_found:
		#Invalid / unknown cell type. put a full floor here and hope it looks fine
		add_c0(chunk)
		
func add_c0(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c1(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c2(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c3(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c4(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c5(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c5b(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c6(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c7(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c8(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c9(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c10(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c11(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c12(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c13(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c14(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c15(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c16(chunk: MarchingSquaresTerrainChunk) -> void: pass
func add_c17(chunk: MarchingSquaresTerrainChunk) -> void: pass
