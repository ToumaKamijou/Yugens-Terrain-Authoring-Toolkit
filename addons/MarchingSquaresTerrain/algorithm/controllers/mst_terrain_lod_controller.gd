@tool
extends RefCounted
class_name MSTTerrainLodController


var terrain
var _proxies : Dictionary = {}
var _pending_updates := false


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func apply() -> void:
	if terrain == null or not terrain.is_inside_tree():
		return
	if not terrain.terrain_lod_enabled:
		_clear_proxies()
		return
	_pending_updates = false
	
	var step := maxi(2, int(terrain.terrain_lod_step))
	for coords in terrain.chunks.keys():
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(coords)
		if not is_instance_valid(chunk):
			continue
		var proxy : MeshInstance3D = _proxies.get(coords)
		if proxy == null or not is_instance_valid(proxy):
			proxy = _build_proxy(chunk, step)
			if proxy == null:
				continue
			_proxies[coords] = proxy
		_configure_proxy_visibility(chunk, proxy)
	
	var stale_coords : Array[Vector2i] = []
	for coords in _proxies.keys():
		if not terrain.chunks.has(coords):
			stale_coords.append(coords)
	for coords in stale_coords:
		var stale_proxy : Node = _proxies[coords]
		if is_instance_valid(stale_proxy):
			stale_proxy.queue_free()
		_proxies.erase(coords)


func _build_proxy(chunk: MarchingSquaresTerrainChunk, step: int) -> MeshInstance3D:
	if not (chunk.height_map is Array) or chunk.height_map.size() < chunk.dimensions.z:
		return null
	var dims_x := int(chunk.dimensions.x)
	var dims_z := int(chunk.dimensions.z)
	var sample_x: Array[int] = []
	var sample_z: Array[int] = []
	for x in range(0, dims_x, step):
		sample_x.append(x)
	if sample_x.is_empty() or sample_x[-1] != dims_x - 1:
		sample_x.append(dims_x - 1)
	for z in range(0, dims_z, step):
		sample_z.append(z)
	if sample_z.is_empty() or sample_z[-1] != dims_z - 1:
		sample_z.append(dims_z - 1)
	
	var width := sample_x.size()
	var depth := sample_z.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var custom2 := PackedFloat32Array()
	vertices.resize(width * depth)
	normals.resize(width * depth)
	uvs.resize(width * depth)
	uv2s.resize(width * depth)
	colors.resize(width * depth)
	custom0.resize(width * depth * 4)
	custom1.resize(width * depth * 4)
	custom2.resize(width * depth * 4)
	
	var height_at := func(x: int, z: int) -> float:
		x = clampi(x, 0, dims_x - 1)
		z = clampi(z, 0, dims_z - 1)
		if not (chunk.height_map[z] is Array) or chunk.height_map[z].size() <= x:
			return 0.0
		return float(chunk.height_map[z][x])
	
	for z_idx in range(depth):
		var z := sample_z[z_idx]
		for x_idx in range(width):
			var x := sample_x[x_idx]
			var vertex_idx := z_idx * width + x_idx
			var h := height_at.call(x, z)
			vertices[vertex_idx] = Vector3(float(x) * chunk.cell_size.x, h, float(z) * chunk.cell_size.y)
			var left := height_at.call(x - step, z)
			var right := height_at.call(x + step, z)
			var down := height_at.call(x, z - step)
			var up := height_at.call(x, z + step)
			var dx : float = (left - right) / maxf(0.0001, 2.0 * chunk.cell_size.x * float(step))
			var dz : float = (down - up) / maxf(0.0001, 2.0 * chunk.cell_size.y * float(step))
			normals[vertex_idx] = Vector3(dx, 1.0, dz).normalized()
			uvs[vertex_idx] = Vector2(float(x) / maxf(1.0, float(dims_x - 1)), float(z) / maxf(1.0, float(dims_z - 1)))
			uv2s[vertex_idx] = Vector2(float(x), float(z))
			colors[vertex_idx] = Color.WHITE
			custom2[vertex_idx * 4 + 3] = 1.0
	
	var indices := PackedInt32Array()
	indices.resize((width - 1) * (depth - 1) * 6)
	var write_idx := 0
	for z_idx in range(depth - 1):
		for x_idx in range(width - 1):
			var i0 := z_idx * width + x_idx
			var i1 := i0 + 1
			var i2 := i0 + width
			var i3 := i2 + 1
			indices[write_idx + 0] = i0
			indices[write_idx + 1] = i1
			indices[write_idx + 2] = i2
			indices[write_idx + 3] = i1
			indices[write_idx + 4] = i3
			indices[write_idx + 5] = i2
			write_idx += 6
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_CUSTOM2] = custom2
	arrays[Mesh.ARRAY_INDEX] = indices
	var format := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_INDEX
	format |= Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	format |= Mesh.ARRAY_FORMAT_CUSTOM1 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	format |= Mesh.ARRAY_FORMAT_CUSTOM2 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	var lod_mesh := ArrayMesh.new()
	lod_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	
	var proxy := MeshInstance3D.new()
	proxy.name = "TerrainLODProxy"
	proxy.mesh = lod_mesh
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.owner = null
	chunk.add_child(proxy)
	var source_material := chunk.mesh.surface_get_material(0) if chunk.mesh != null and chunk.mesh.get_surface_count() > 0 else null
	if source_material != null:
		proxy.material_override = source_material
	
	return proxy


func _configure_proxy_visibility(chunk: MarchingSquaresTerrainChunk, proxy: MeshInstance3D) -> void:
	var start_distance := maxf(1.0, float(terrain.terrain_lod_start_distance))
	var end_distance := maxf(start_distance + 1.0, float(terrain.terrain_lod_end_distance))
	# Chunks are Node3D containers; visibility ranges must be applied to the
	# actual authored MeshInstance3D tile children or the full mesh remains
	# visible alongside the proxy.
	for tile in chunk._mesh_tiles.values():
		if tile is MeshInstance3D:
			tile.visibility_range_end = start_distance
			tile.visibility_range_end_margin = float(terrain.visibility_range_margin)
	proxy.visibility_range_begin = start_distance
	proxy.visibility_range_begin_margin = float(terrain.visibility_range_margin)
	proxy.visibility_range_end = end_distance
	proxy.visibility_range_end_margin = float(terrain.visibility_range_margin)


func _clear_proxies() -> void:
	for proxy in _proxies.values():
		if is_instance_valid(proxy):
			proxy.queue_free()
	_proxies.clear()
	_pending_updates = false


func invalidate_chunk(coords: Vector2i) -> void:
	var proxy : Node = _proxies.get(coords)
	if is_instance_valid(proxy):
		proxy.queue_free()
	_proxies.erase(coords)
	_pending_updates = true


func has_pending_updates() -> bool:
	return _pending_updates


func clear() -> void:
	_clear_proxies()
