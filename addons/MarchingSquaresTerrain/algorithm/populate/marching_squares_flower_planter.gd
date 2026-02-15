@icon("uid://sx50shr1w2g0")
@tool
extends MarchingSquaresPopulator
class_name MarchingSquaresFlowerPlanter


var terrain_system : MarchingSquaresTerrain

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_mesh : QuadMesh = null:
	set(value):
		flower_mesh = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var color_gradient : GradientTexture1D = preload("uid://cjkufv3o3pg57"):
	set(value):
		color_gradient = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		if value != null:
			flower_mat.set_shader_parameter("use_custom_color", true)
		else:
			flower_mat.set_shader_parameter("use_custom_color", false)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var should_billboard : bool = true:
	set(value):
		should_billboard = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		if value == true:
			flower_mesh.orientation = PlaneMesh.FACE_Z
			flower_mat.set_shader_parameter("should_billboard", true)
		else:
			flower_mesh.orientation = PlaneMesh.FACE_Y
			flower_mat.set_shader_parameter("should_billboard", false)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_sprite : CompressedTexture2D = preload("uid://ld4ildjiaxlw"):
	set(value):
		flower_sprite = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		flower_mat.set_shader_parameter("flower_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var sprite_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		sprite_size = value
		multimesh.mesh.size = value
		multimesh.mesh.center_offset.y = value.y / 2
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var flower_subdivisions : int = 1:
	set(value):
		flower_subdivisions = value
		if Engine.is_editor_hint():
			setup(false)
			regenerate_flowers()

@export_storage var planted_chunks : Dictionary = {} 
var populated_chunks : Array[MarchingSquaresTerrainChunk]
var cell_data : Dictionary

var rng = RandomNumberGenerator.new()


func setup(redo: bool = true):
	if not terrain_system:
		printerr("SETUP FAILED - no terrain system found for FlowerPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	
	var total_cells := 0
	for chunk in populated_chunks:
		if cell_data.has(chunk):
			total_cells += cell_data[chunk].size()
	multimesh.instance_count = total_cells * flower_subdivisions
	
	if flower_mesh:
		multimesh.mesh = flower_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = sprite_size
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF


func _init() -> void:
	var fallback_flower_mesh := preload("uid://ds5vman6g5424")
	if not flower_mesh:
		flower_mesh = fallback_flower_mesh.duplicate(true)
		flower_mesh.material = fallback_flower_mesh.material.duplicate(true)


func regenerate_flowers() -> void:
	if not populated_chunks:
		printerr("No populated chunks set while regenerating cells")
		return
	
	if not cell_data:
		printerr("No cell data set while regenerating cells")
		return
	
	if not multimesh:
		setup()
	
	var index := 0
	
	for chunk in populated_chunks:
		for cell in cell_data[chunk]:
			index = generate_flowers_on_cell(chunk, cell, index)
	
	multimesh.mesh.center_offset.y = multimesh.mesh.size.y / 2


func add_flowers_to_cell(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> void:
	if not planted_chunks.has(chunk.chunk_coords):
		planted_chunks[chunk.chunk_coords] = []
	if cell not in planted_chunks[chunk.chunk_coords]:
		planted_chunks[chunk.chunk_coords].append(cell)
	if not cell_data.has(chunk):
		cell_data[chunk] = {}
		populated_chunks.append(chunk)
	
	if cell_data[chunk].has(cell):
		return # Already populated
	
	cell_data[chunk][cell] = _get_flower_cell_data(chunk, cell)


func remove_flowers_from_cell(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> void:
	if not cell_data.has(chunk):
		return
	
	cell_data[chunk].erase(cell)
	
	if cell_data[chunk].is_empty():
		cell_data.erase(chunk)
		populated_chunks.erase(chunk)


func generate_flowers_on_cell(chunk: MarchingSquaresTerrainChunk, cell: Vector2i, start_index: int) -> int:
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		return start_index
	
	var current_cell_data = cell_data[chunk][cell]
	
	if not current_cell_data.has("verts") or not current_cell_data.has("uvs") or not current_cell_data.has("custom_1_values") or not current_cell_data.has("is_floor"):
		printerr("[MarchingSquaresFlowerPlanter] current_cell_data doesn't have one of the following required data: 1) verts, 2) uvs, 3) custom_1_values, 4) is_floor")
		return start_index
	
	var points: PackedVector2Array = []
	var count := flower_subdivisions 
	var chunk_offset := chunk.global_transform.origin
	
	for z in range(flower_subdivisions):
		for x in range(flower_subdivisions):
			if rng.randf() < 0.05:
				points.append(Vector2(
					chunk_offset.x + (cell.x + (x + randf_range(0, 1)) / flower_subdivisions) * terrain_system.cell_size.x,
					chunk_offset.z + (cell.y + (z + randf_range(0, 1)) / flower_subdivisions) * terrain_system.cell_size.y
				))
	
	var index := start_index
	var end_index := index + count
	
	var verts: PackedVector3Array = current_cell_data["verts"]
	var uvs: PackedVector2Array = current_cell_data["uvs"]
	var custom_1_values: PackedColorArray = current_cell_data["custom_1_values"]
	var is_floor: Array = current_cell_data["is_floor"]
	
	for i in range(0, len(verts), 3):
		if i+2 >= len(verts):
			continue # Skip incomplete triangle
		# Only place flowers on floors
		if not is_floor[i]:
			continue
		
		var a := verts[i] + chunk_offset
		var b := verts[i+1] + chunk_offset
		var c := verts[i+2] + chunk_offset
		
		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		
		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0/(dot00 * dot11 - dot01 * dot01)
		
		var point_index := 0
		while (point_index < len(points)):
			var v2 = Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
			var dot02 := v0.dot(v2)
			var dot12 := v1.dot(v2)
			
			var u := (dot11 * dot02 - dot01 * dot12) * invDenom
			if u < 0:
				point_index += 1
				continue
			
			var v := (dot00 * dot12 - dot01 * dot02) * invDenom
			if v < 0:
				point_index += 1
				continue
			
			if u + v <= 1:
				# Point is inside triangle, won't be inside any other floor triangle
				points.remove_at(point_index)
				var p = a*(1-u-v) + b*u + c*v
				
				# Don't place flowers on ledge or ridges
				var uv = uvs[i]*u + uvs[i+1]*v + uvs[i+2]*(1-u-v)
				var on_ledge_or_ridge: bool = uv.y > 0.0 or uv.x > 0.5
				
				if not on_ledge_or_ridge:
					_create_flower_instance(index, p, a, b, c)
				else:
					_hide_flower_instance(index)
				index += 1
			else:
				point_index += 1
	
	# Fill remaining points with hidden instances
	while index < end_index:
		if index >= multimesh.instance_count:
			return end_index
		_hide_flower_instance(index)
		index += 1
	
	return end_index


func rebuild_cell_data() -> void:
	populated_chunks.clear()
	cell_data.clear()
	
	for chunk_coords in planted_chunks.keys():
		if terrain_system.chunks.has(chunk_coords):
			var chunk_node = terrain_system.chunks[chunk_coords]
			populated_chunks.append(chunk_node)
			
			cell_data[chunk_node] = {}
			for cell in planted_chunks[chunk_coords]:
				cell_data[chunk_node][cell] = _get_flower_cell_data(chunk_node, cell)


func _get_flower_cell_data(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Dictionary:
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		return {}
	
	var cell_data_copy := {}
	var geo_data = chunk.cell_geometry[cell]
	
	cell_data_copy["verts"] = geo_data["verts"]
	cell_data_copy["uvs"] = geo_data["uvs"]
	cell_data_copy["custom_1_values"] = geo_data["custom_1_values"]
	cell_data_copy["is_floor"] = geo_data["is_floor"]
	
	return cell_data_copy


## Creates a flower instance at the given position with proper transform and random color
func _create_flower_instance(index: int, instance_position: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var edge1 := b - a
	var edge2 := c - a
	var normal := edge1.cross(edge2).normalized()
	
	var right := Vector3.FORWARD.cross(normal).normalized()
	var forward := normal.cross(Vector3.RIGHT).normalized()
	var instance_basis := Basis(right, forward, -normal)
	
	multimesh.set_instance_transform(index, Transform3D(instance_basis, instance_position))
	
	if color_gradient:
		var color_idx := rng.randi_range(0, color_gradient.get_width() - 1)
		var gradient_img := color_gradient.get_image()
		var instance_color := gradient_img.get_pixelv(Vector2i(color_idx, 0))
		instance_color *= instance_color
		multimesh.set_instance_custom_data(index, instance_color)


func _hide_flower_instance(index: int) -> void:
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
