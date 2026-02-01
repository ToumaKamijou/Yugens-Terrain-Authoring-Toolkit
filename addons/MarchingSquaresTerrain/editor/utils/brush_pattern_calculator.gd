@tool
class_name BrushPatternCalculator

## Calculates which cells fall within a brush and their falloff samples.
## Used by both plugin (for editing) and gizmo (for visualization).
class BrushBounds:
	var chunk_tl: Vector2i
	var chunk_br: Vector2i
	var cell_tl: Vector2i
	var cell_br: Vector2i


static func calculate_bounds(
	pos: Vector3,
	brush_size: float,
	terrain: MarchingSquaresTerrain
) -> BrushBounds:
	var bounds := BrushBounds.new()

	var pos_tl := Vector2(
		pos.x + terrain.cell_size.x - brush_size / 2,
		pos.z + terrain.cell_size.y - brush_size / 2
	)
	var pos_br := Vector2(
		pos.x + terrain.cell_size.x + brush_size / 2,
		pos.z + terrain.cell_size.y + brush_size / 2
	)

	var chunk_size_x : float = (terrain.dimensions.x - 1) * terrain.cell_size.x
	var chunk_size_z : float = (terrain.dimensions.z - 1) * terrain.cell_size.y

	bounds.chunk_tl = Vector2i(floori(pos_tl.x / chunk_size_x), floori(pos_tl.y / chunk_size_z))
	bounds.chunk_br = Vector2i(floori(pos_br.x / chunk_size_x), floori(pos_br.y / chunk_size_z))

	bounds.cell_tl = Vector2i(
		floori(pos_tl.x / terrain.cell_size.x - bounds.chunk_tl.x * (terrain.dimensions.x - 1)),
		floori(pos_tl.y / terrain.cell_size.y - bounds.chunk_tl.y * (terrain.dimensions.z - 1))
	)
	bounds.cell_br = Vector2i(
		floori(pos_br.x / terrain.cell_size.x - bounds.chunk_br.x * (terrain.dimensions.x - 1)),
		floori(pos_br.y / terrain.cell_size.y - bounds.chunk_br.y * (terrain.dimensions.z - 1))
	)

	return bounds


static func calculate_max_distance(brush_size: float, brush_index: int) -> float:
	var max_distance : float = brush_size / 2
	match brush_index:
		0: # Round brush
			max_distance *= max_distance
		1: # Square brush
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

	var t: float
	match brush_index:
		0: # Round brush
			var d : float = (max_distance - distance_squared) / max_distance
			t = clamp(d, 0.0, 1.0)
		1: # Square brush
			var local := world_pos - brush_pos
			var uv := local / (brush_size * 0.5)
			var d : float = max(abs(uv.x), abs(uv.y))
			t = 1.0 - clamp(d, 0.2, 1.0)

	return falloff_curve.sample(clamp(t, 0.001, 0.999))


## Calculate world position for a cell in a chunk
static func cell_to_world_pos(
	chunk_coords: Vector2i,
	cell_coords: Vector2i,
	terrain: MarchingSquaresTerrain
) -> Vector2:
	var world_x : float = (chunk_coords.x * (terrain.dimensions.x - 1) + cell_coords.x) * terrain.cell_size.x
	var world_z : float = (chunk_coords.y * (terrain.dimensions.z - 1) + cell_coords.y) * terrain.cell_size.y
	return Vector2(world_x, world_z)


## Get cell range for a specific chunk within the brush bounds
static func get_cell_range_for_chunk(
	chunk_coords: Vector2i,
	bounds: BrushBounds,
	terrain: MarchingSquaresTerrain
) -> Dictionary:
	var x_min : int = bounds.cell_tl.x if chunk_coords.x == bounds.chunk_tl.x else 0
	var x_max : int = bounds.cell_br.x if chunk_coords.x == bounds.chunk_br.x else terrain.dimensions.x
	var z_min : int = bounds.cell_tl.y if chunk_coords.y == bounds.chunk_tl.y else 0
	var z_max : int = bounds.cell_br.y if chunk_coords.y == bounds.chunk_br.y else terrain.dimensions.z
	return {"x_min": x_min, "x_max": x_max, "z_min": z_min, "z_max": z_max}
