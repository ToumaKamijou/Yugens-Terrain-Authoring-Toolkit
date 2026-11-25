@tool
class_name BrushPatternCalculator
## Calculates which cells fall within a brush and their falloff samples.
## Used by both plugin (for editing) and gizmo (for visualization).


class BrushBounds:
	var chunk_tl : Vector2i
	var chunk_br : Vector2i
	var cell_tl : Vector2i
	var cell_br : Vector2i


static func calculate_bounds(pos: Vector3, brush_size: float, terrain: MarchingSquaresTerrain) -> BrushBounds:
	var bounds := BrushBounds.new()
	
	# brush_size is treated as a radius everywhere (gizmo scale, UI). Using /2 here caused
	# the painted region to be much smaller/sparser than the visible brush circle.
	var pos_tl := Vector2(
	pos.x - brush_size,
	pos.z - brush_size
	)
	var pos_br := Vector2(
		pos.x + brush_size,
		pos.z + brush_size
	)
	
	var chunk_size_x : float = (terrain.dimensions.x - 1) * terrain.cell_size.x
	var chunk_size_z : float = (terrain.dimensions.z - 1) * terrain.cell_size.y
	
	bounds.chunk_tl = Vector2i(floori(pos_tl.x / chunk_size_x), floori(pos_tl.y / chunk_size_z))
	bounds.chunk_br = Vector2i(floori(pos_br.x / chunk_size_x), floori(pos_br.y / chunk_size_z))
	
	# +1 so that x_max/z_max can be used as an exclusive range bound.
	bounds.cell_tl = Vector2i(
		floori(pos_tl.x / terrain.cell_size.x - bounds.chunk_tl.x * (terrain.dimensions.x - 1)) + 1,
		floori(pos_tl.y / terrain.cell_size.y - bounds.chunk_tl.y * (terrain.dimensions.z - 1)) + 1
	)
	
	bounds.cell_br = Vector2i(
		floori(pos_br.x / terrain.cell_size.x - bounds.chunk_br.x * (terrain.dimensions.x - 1)) + 1,
		floori(pos_br.y / terrain.cell_size.y - bounds.chunk_br.y * (terrain.dimensions.z - 1)) + 1
	)
	
	return bounds


static func calculate_max_distance(brush_size: float, brush_index: int) -> float:
	# brush_size is a radius.
	var max_distance : float = brush_size
	match brush_index:
		0: # Round brush
			max_distance *= max_distance
		1: # Square brush (use bounding circle of the square)
			max_distance *= max_distance * 2
	return max_distance


static func calculate_falloff_sample(
	world_pos: Vector2,
	brush_pos: Vector2,
	brush_size: float,
	brush_index: int,
	max_distance: float,
	use_falloff: bool,
	falloff_curve: Curve
	) -> float:
	
	var distance_squared := brush_pos.distance_squared_to(world_pos)
	if distance_squared > max_distance:
		return -1.0  # Outside brush
	
	if not use_falloff:
		return 1.0
	
	var t : float = 0.0
	match brush_index:
		0: # Round brush (linear by radius, not squared-distance)
			var denom : float = max(brush_size, 0.0001)
			var dist : float = sqrt(distance_squared)
			t = 1.0 - clamp(dist / denom, 0.0, 1.0)
		1: # Square brush
			var local : Vector2 = world_pos - brush_pos
			var denom : float = max(brush_size, 0.0001)
			var uv : Vector2 = local / denom
			var d : float = max(abs(uv.x), abs(uv.y))
			t = 1.0 - clamp(d, 0.0, 1.0)
	
	# IMPORTANT: allow true endpoints so a full-strength stroke can reach the target.
	# Soften falloff: apply a square-root easing to expand the brush's effective area (gentler falloff).
	t = pow(t, 0.5)
	return falloff_curve.sample(clamp(t, 0.0, 1.0))


static func calculate_wall_falloff_sample(
	world_pos: Vector3,
	brush_pos: Vector3,
	wall_normal: Vector3,
	brush_size: float,
	brush_index: int,
	max_distance: float,
	use_falloff: bool,
	falloff_curve: Curve
	) -> float:
	var n := wall_normal.normalized()
	if n.length_squared() < 0.001:
		n = Vector3.BACK
	
	var tangent := Vector3.UP.cross(n)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT.cross(n)
	tangent = tangent.normalized()
	
	var bitangent := n.cross(tangent).normalized()
	var delta := world_pos - brush_pos
	var plane_pos := Vector2(delta.dot(tangent), delta.dot(bitangent))
	
	return calculate_falloff_sample(
		plane_pos,
		Vector2.ZERO,
		brush_size,
		brush_index,
		max_distance,
		use_falloff,
		falloff_curve
	)


static func _sample_chunk_height(chunk: MarchingSquaresTerrainChunk, x: int, z: int, fallback: float) -> float:
	if chunk == null:
		return fallback
	if not (chunk.height_map is Array):
		return fallback
	if z < 0 or z >= chunk.height_map.size():
		return fallback
	if not (chunk.height_map[z] is Array):
		return fallback
	if x < 0 or x >= chunk.height_map[z].size():
		return fallback
	return float(chunk.height_map[z][x])


static func cell_to_wall_sample_pos(
	chunk_coords: Vector2i,
	cell_coords: Vector2i,
	terrain: MarchingSquaresTerrain,
	brush_pos: Vector3
	) -> Vector3:
	# Sample wall painting from the center of each cell instead of the corner.
	# This keeps the old wall-color workflow, but makes the brush footprint feel
	# less like a snapped column selection and more like the visible brush area.
	var world_pos := cell_to_world_pos(chunk_coords, cell_coords, terrain, true)
	if terrain == null or not terrain.chunks.has(chunk_coords):
		return Vector3(world_pos.x, brush_pos.y, world_pos.y)
	
	var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
	var center_height := _sample_chunk_height(chunk, cell_coords.x, cell_coords.y, brush_pos.y)
	var min_height := center_height
	var max_height := center_height
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if abs(dx) + abs(dz) > 1:
				continue
			var h := _sample_chunk_height(chunk, cell_coords.x + dx, cell_coords.y + dz, center_height)
			min_height = min(min_height, h)
			max_height = max(max_height, h)
	
	var sample_y := clampf(brush_pos.y, min_height, max_height)
	
	return Vector3(world_pos.x, sample_y, world_pos.y)


## Calculate world position for a cell in a chunk.
## p_centered=true returns the center of the cell (half-cell offset). This is useful for Vertex Paint
## so round brushes look less octagon-y on low-resolution grids.
static func cell_to_world_pos(chunk_coords: Vector2i, cell_coords: Vector2i, terrain: MarchingSquaresTerrain, p_centered: bool =  false) -> Vector2:
	var world_x : float = (chunk_coords.x * (terrain.dimensions.x - 1) + cell_coords.x) * terrain.cell_size.x
	var world_z : float = (chunk_coords.y * (terrain.dimensions.z - 1) + cell_coords.y) * terrain.cell_size.y
	if p_centered:
		world_x += terrain.cell_size.x * 0.5
		world_z += terrain.cell_size.y * 0.5
	return Vector2(world_x, world_z)


## Get cell range for a specific chunk within the brush bounds
static func get_cell_range_for_chunk(chunk_coords: Vector2i, bounds: BrushBounds, terrain: MarchingSquaresTerrain) -> Dictionary:
	var vertex_count_x := maxi(terrain.dimensions.x, 0)
	var vertex_count_z := maxi(terrain.dimensions.z, 0)
	var x_min : int = clampi(bounds.cell_tl.x, 0, vertex_count_x) if chunk_coords.x == bounds.chunk_tl.x else 0
	var x_max : int = clampi(bounds.cell_br.x, 0, vertex_count_x) if chunk_coords.x == bounds.chunk_br.x else vertex_count_x
	var z_min : int = clampi(bounds.cell_tl.y, 0, vertex_count_z) if chunk_coords.y == bounds.chunk_tl.y else 0
	var z_max : int = clampi(bounds.cell_br.y, 0, vertex_count_z) if chunk_coords.y == bounds.chunk_br.y else vertex_count_z
	return {"x_min": x_min, "x_max": x_max, "z_min": z_min, "z_max": z_max}
