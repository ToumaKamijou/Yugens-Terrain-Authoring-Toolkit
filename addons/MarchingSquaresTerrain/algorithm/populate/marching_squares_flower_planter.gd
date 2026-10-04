@icon("uid://sx50shr1w2g0")
@tool
extends MarchingSquaresPopulator
class_name MarchingSquaresFlowerPlanter


# All populators need this variable at the top so the mst_populator_settings.gd script can reference it properly
const CLASS_NAME := "MarchingSquaresFlowerPlanter"
# Slope limit floor faces steeper than this get no flowers, same as grass planter (_MIN_GRASS_FACE_UP_DOT)
const _MIN_FLOWER_FACE_UP_DOT : float = 0.5

var terrain_system : MarchingSquaresTerrain
var _connected_color_gradient: Gradient
var _gradient_refresh_queued := false
var _flower_visibility_end_distance := 0.0
var _flower_visibility_fade_margin := 0.0

@export var flower_mesh : QuadMesh = null:
	set(value):
		flower_mesh = value.duplicate(true)
		if value.material:
			flower_mesh.material = value.material.duplicate(true)
		if multimesh:
			multimesh.mesh = flower_mesh
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var color_gradient : GradientTexture1D = preload("uid://cjkufv3o3pg57"):
	set(value):
		_disconnect_color_gradient()
		color_gradient = value
		_connect_color_gradient()
		var flower_mat := flower_mesh.material as ShaderMaterial
		if value != null:
			flower_mat.set_shader_parameter("use_custom_color", true)
		else:
			flower_mat.set_shader_parameter("use_custom_color", false)
		_queue_color_gradient_refresh()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_sprite : CompressedTexture2D:
	set(value):
		flower_sprite = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		flower_mat.set_shader_parameter("flower_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var sprite_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		sprite_size = value
		multimesh.mesh.size = value
		multimesh.mesh.center_offset.y = base_height_offset + value.y / 2
@export_custom(PROPERTY_HINT_RANGE, "0, 8", PROPERTY_USAGE_STORAGE) var flower_subdivisions : int = 3:
	set(value):
		flower_subdivisions = value
		if Engine.is_editor_hint() and terrain_system:
			for chunk in populated_chunks:
				if chunk.cell_geometry.is_empty():
					for cell in planted_chunks[chunk.chunk_coords]:
						chunk.regenerate_cell_geometry(cell)
			setup()
			regenerate_flowers()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var should_billboard : bool = false:
	set(value):
		should_billboard = value
		_apply_billboard_state()


func _apply_billboard_state() -> void:
	if flower_mesh == null or multimesh == null or multimesh.mesh == null:
		return
	var flower_mat := flower_mesh.material as ShaderMaterial
	if should_billboard:
		flower_mesh.orientation = PlaneMesh.FACE_Z
		flower_mat.set_shader_parameter("should_billboard", true)
	else:
		flower_mesh.orientation = PlaneMesh.FACE_Y
		flower_mat.set_shader_parameter("should_billboard", false)
	multimesh.mesh.center_offset.y = base_height_offset + multimesh.mesh.size.y / 2


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var base_height_offset : float = 0.75:
	set(value):
		base_height_offset = value
		multimesh.mesh.center_offset.y = base_height_offset + multimesh.mesh.size.y / 2
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_hmap : Texture2D:
	set(value):
		flower_hmap = value
		if Engine.is_editor_hint() and terrain_system:
			for chunk in populated_chunks:
				if chunk.cell_geometry.is_empty():
					for cell in planted_chunks[chunk.chunk_coords]:
						chunk.regenerate_cell_geometry(cell)
			regenerate_flowers()
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var rng_height_range : float = 0.1:
	set(value):
		rng_height_range = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		flower_mat.set_shader_parameter("rng_height_range", value)
@export_custom(PROPERTY_HINT_RANGE, "0, 1", PROPERTY_USAGE_STORAGE) var rng_size_range : float = 0.2:
	set(value):
		rng_size_range = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		flower_mat.set_shader_parameter("rng_size_range", value)

@export_storage var planted_chunks : Dictionary = {} 
var populated_chunks : Array[MarchingSquaresTerrainChunk]
var cell_data : Dictionary


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
	multimesh.instance_count = total_cells * flower_subdivisions * flower_subdivisions
	
	if flower_mesh:
		multimesh.mesh = flower_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = sprite_size
	_apply_billboard_state()
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	if terrain_system != null:
		set_flower_visibility_range(
			terrain_system.flower_visibility_end_distance if terrain_system.visibility_detail_enabled else 0.0,
			terrain_system.visibility_range_margin if terrain_system.visibility_detail_enabled else 0.0
		)
		terrain_system._sync_wind_state(false)
	else:
		_sync_flower_visibility_shader()


func _init() -> void:
	var fallback_flower_mesh := preload("uid://dp1hfchm2o7c3")
	if not flower_mesh:
		flower_mesh = fallback_flower_mesh.duplicate(true)


func _ready() -> void:
	# The default false value may not invoke the property setter during scene
	# instantiation. Apply it once after the mesh and MultiMesh are available.
	_apply_billboard_state()
	_connect_color_gradient()
	if terrain_system != null:
		set_flower_visibility_range(
			terrain_system.flower_visibility_end_distance if terrain_system.visibility_detail_enabled else 0.0,
			terrain_system.visibility_range_margin if terrain_system.visibility_detail_enabled else 0.0
		)


func set_flower_visibility_range(p_end: float, p_fade_margin: float = 0.0) -> void:
	_flower_visibility_end_distance = maxf(p_end, 0.0)
	_flower_visibility_fade_margin = clampf(p_fade_margin, 0.0, _flower_visibility_end_distance)
	_sync_flower_visibility_shader()


func _sync_flower_visibility_shader() -> void:
	if flower_mesh == null or not (flower_mesh.material is ShaderMaterial):
		return
	var flower_mat := flower_mesh.material as ShaderMaterial
	flower_mat.set_shader_parameter("visibility_end_distance", _flower_visibility_end_distance)
	flower_mat.set_shader_parameter("visibility_fade_margin", _flower_visibility_fade_margin)


func _disconnect_color_gradient() -> void:
	if _connected_color_gradient == null:
		return
	var callback := Callable(self, "_on_color_gradient_changed")
	if _connected_color_gradient.changed.is_connected(callback):
		_connected_color_gradient.changed.disconnect(callback)
	_connected_color_gradient = null


func _connect_color_gradient() -> void:
	if color_gradient == null or color_gradient.gradient == null:
		return
	if _connected_color_gradient == color_gradient.gradient:
		return
	_disconnect_color_gradient()
	_connected_color_gradient = color_gradient.gradient
	var callback := Callable(self, "_on_color_gradient_changed")
	if not _connected_color_gradient.changed.is_connected(callback):
		_connected_color_gradient.changed.connect(callback)


func _on_color_gradient_changed() -> void:
	_queue_color_gradient_refresh()


func _queue_color_gradient_refresh() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _gradient_refresh_queued:
		return
	_gradient_refresh_queued = true
	call_deferred("_refresh_color_gradient")


func _refresh_color_gradient() -> void:
	_gradient_refresh_queued = false
	if not is_inside_tree() or multimesh == null or populated_chunks.is_empty():
		return
	regenerate_flowers()


func regenerate_flowers() -> void:
	for chunk in populated_chunks:
		if not is_instance_valid(chunk):
			continue
		if chunk.cell_geometry.is_empty():
			printerr("No cell_geometry data set while regenerating cells")
			return
	
	var remove_selection := false
	if Engine.is_editor_hint():
		var plugin_script: Resource = load("res://addons/MarchingSquaresTerrain/editor/marching_squares_terrain_plugin.gd")
		var plugin: Object = plugin_script.get("instance") if plugin_script != null else null
		remove_selection = plugin != null and bool(plugin.get("remove_selection"))
	if not planted_chunks.is_empty() and cell_data.is_empty() and not remove_selection:
		printerr("No cell data set while regenerating cells")
		return
	if not multimesh:
		setup()
	
	var index := 0
	
	for chunk in populated_chunks:
		for cell in cell_data[chunk]:
			index = generate_flowers_on_cell(chunk, cell, index)
	
	if should_billboard:
		multimesh.mesh.center_offset.y = base_height_offset + multimesh.mesh.size.y / 2
	else:
		multimesh.mesh.center_offset.y = base_height_offset + multimesh.mesh.size.y / 2


func add_flowers_to_cell(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= terrain_system.dimensions.x - 1:
		return
	if cell.y < 0 or cell.y >= terrain_system.dimensions.z - 1:
		return
	
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
	
	if planted_chunks.has(chunk.chunk_coords):
		planted_chunks[chunk.chunk_coords].erase(cell)
		if planted_chunks[chunk.chunk_coords].is_empty():
			planted_chunks.erase(chunk.chunk_coords)


func generate_flowers_on_cell(chunk: MarchingSquaresTerrainChunk, cell: Vector2i, start_index: int) -> int:
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		return start_index
	
	var current_cell_data = cell_data[chunk][cell]
	
	if not current_cell_data.has("verts") or not current_cell_data.has("uvs") or not current_cell_data.has("custom_1_values") or not current_cell_data.has("is_floor"):
		printerr("[MarchingSquaresFlowerPlanter] current_cell_data doesn't have one of the following required data: 1) verts, 2) uvs, 3) custom_1_values, 4) is_floor")
		return start_index
	
	var points : PackedVector2Array = []
	var count := flower_subdivisions * flower_subdivisions
	var chunk_offset: Vector3
	if is_inside_tree() and chunk.is_inside_tree():
		chunk_offset = to_local(chunk.global_position)
	else:
		chunk_offset = chunk.position
	
	var pos_rng := RandomNumberGenerator.new()
	pos_rng.seed = hash(Vector3i(
		chunk.chunk_coords.x,
		cell.x,
		cell.y
	))
	
	var color_rng := RandomNumberGenerator.new()
	color_rng.seed = hash(Vector4i(
		chunk.chunk_coords.x,
		cell.x,
		cell.y,
		123
	))
	
	for z in range(flower_subdivisions):
		for x in range(flower_subdivisions):
			if pos_rng.randf() < 0.05:
				points.append(Vector2(
					chunk_offset.x + (cell.x + (x + pos_rng.randf_range(0, 1)) / flower_subdivisions) * terrain_system.cell_size.x,
					chunk_offset.z + (cell.y + (z + pos_rng.randf_range(0, 1)) / flower_subdivisions) * terrain_system.cell_size.y
				))
	
	var index := start_index
	var end_index := index + count
	
	var verts: PackedVector3Array = current_cell_data["verts"]
	var uvs: PackedVector2Array = current_cell_data["uvs"]
	var custom_1_values: PackedColorArray = current_cell_data["custom_1_values"]
	var is_floor: Array = current_cell_data["is_floor"]
	var uv_marks_ledges : bool = terrain_system == null or terrain_system.prefab_set == null
	
	for i in range(0, len(verts), 3):
		if i+2 >= len(verts):
			continue # Skip incomplete triangle
		# Only place flowers on floors
		if not is_floor[i]:
			continue
		
		var a := verts[i] + chunk_offset
		var b := verts[i+1] + chunk_offset
		var c := verts[i+2] + chunk_offset
		var face_normal := (b - a).cross(c - a)
		if face_normal.length_squared() < 0.000001 or absf(face_normal.normalized().y) < _MIN_FLOWER_FACE_UP_DOT:
			continue
		
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
				var on_ledge_or_ridge : bool = uv_marks_ledges and (uv.y > 0.0 or uv.x > 0.5)
				
				if not on_ledge_or_ridge:
					_create_flower_instance(index, p, a, b, c, color_rng)
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


func recalculate_cells_in_pattern(pattern: Dictionary) -> void:
	for chunk_coords : Vector2i in pattern.keys():
		var chunk = terrain_system.chunks.get(chunk_coords)
		if not chunk:
			continue
		
		if not cell_data.has(chunk):
			continue
		
		var chunk_cells : Dictionary = cell_data[chunk]
		
		for cell_coords in chunk_cells.keys():
			chunk_cells[cell_coords] = _get_flower_cell_data(chunk, cell_coords)


func rebuild_cell_data() -> void:
	populated_chunks.clear()
	cell_data.clear()
	
	for chunk_coords in planted_chunks.keys():
		if terrain_system.chunks.has(chunk_coords):
			var chunk_node = terrain_system.chunks[chunk_coords]
			populated_chunks.append(chunk_node)
			
			cell_data[chunk_node] = {}
			for cell in planted_chunks[chunk_coords]:
				if cell.x < 0 or cell.x >= terrain_system.dimensions.x - 1:
					continue
				if cell.y < 0 or cell.y >= terrain_system.dimensions.z - 1:
					continue
				cell_data[chunk_node][cell] = _get_flower_cell_data(chunk_node, cell)	


func _get_flower_cell_data(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Dictionary:
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		# Persisted flower masks can be restored before terrain geometry exists.
		# Generate only this cell before copying its geometry.
		chunk.regenerate_cell_geometry(cell)
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		printerr("[MarchingSquaresFlowerPlanter] cell_geometry is missing for cell: ", cell)
		return {}
	
	var cell_data_copy := {}
	var geo_data = chunk.cell_geometry[cell]
	if not geo_data.has("verts") or not geo_data.has("uvs") or not geo_data.has("custom_1_values") or not geo_data.has("is_floor"):
		chunk.regenerate_cell_geometry(cell)
		geo_data = chunk.cell_geometry.get(cell, {})
	if not geo_data.has("verts") or not geo_data.has("uvs") or not geo_data.has("custom_1_values") or not geo_data.has("is_floor"):
		printerr("[MarchingSquaresFlowerPlanter] invalid cell_geometry data for cell: ", cell)
		return {}
	cell_data_copy["verts"] = geo_data["verts"]
	cell_data_copy["uvs"] = geo_data["uvs"]
	cell_data_copy["custom_1_values"] = geo_data["custom_1_values"]
	cell_data_copy["is_floor"] = geo_data["is_floor"]
	
	return cell_data_copy


func _get_hmap_image() -> Image:
	if not _is_valid_texture2d(flower_hmap):
		return null
	
	var img : Image = flower_hmap.get_image()
	if img:
		img.decompress()
	return img


func _is_valid_texture2d(tex) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return tex.get_class() != "Texture2D"


## Samples the flower heightmap at the given world position.
func _sample_flower_heightmap_value(world_pos: Vector3) -> float:
	var hmap_image := _get_hmap_image()
	if not hmap_image:
		return 0.0
	
	var uv_x : float = clamp(world_pos.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x), 0.0, 1.0)
	var uv_y : float = clamp(world_pos.z / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y), 0.0, 1.0)
	
	uv_x = abs(fmod(uv_x, 1.0))
	uv_y = abs(fmod(uv_y, 1.0))
	
	var px := int(uv_x * (hmap_image.get_width() - 1))
	var py := int(uv_y * (hmap_image.get_height() - 1))
	var height := hmap_image.get_pixelv(Vector2(px, py))
	
	return height.r * terrain_system.cell_size.x * terrain_system.dimensions.x / 16


## Creates a flower instance at the given position with proper transform and random color
func _create_flower_instance(index: int, instance_position: Vector3, a: Vector3, b: Vector3, c: Vector3, color_rng: RandomNumberGenerator) -> void:
	if not multimesh or index < 0 or index >= multimesh.instance_count:
		return
	var edge1 := b - a
	var edge2 := c - a
	var normal := edge1.cross(edge2).normalized()
	
	var right := Vector3.FORWARD.cross(normal).normalized()
	var forward := normal.cross(Vector3.RIGHT).normalized()
	var instance_basis := Basis(right, forward, -normal)
	
	instance_position.y += _sample_flower_heightmap_value(instance_position)
	
	multimesh.set_instance_transform(index, Transform3D(instance_basis, instance_position))
	
	if color_gradient:
		var color_idx := color_rng.randi_range(0, color_gradient.get_width() - 1)
		var gradient_img := color_gradient.get_image()
		var instance_color := gradient_img.get_pixelv(Vector2i(color_idx, 0))
		instance_color *= instance_color
		multimesh.set_instance_custom_data(index, instance_color)


func _hide_flower_instance(index: int) -> void:
	# Keep hidden slots finite so Godot's renderer does not normalize a degenerate
	# plane while culling MultiMesh instances.
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
	multimesh.set_instance_custom_data(index, Color(0,0,0,0))
