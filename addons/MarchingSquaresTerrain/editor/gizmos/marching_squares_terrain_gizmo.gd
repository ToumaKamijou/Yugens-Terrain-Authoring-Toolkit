extends EditorNode3DGizmo
class_name MarchingSquaresTerrainGizmo


var lines : PackedVector3Array = PackedVector3Array()

var addchunk_material : Material
var removechunk_material : Material
var brush_material : Material

var terrain_plugin : MarchingSquaresTerrainPlugin


func _redraw():
	lines.clear()
	clear()
	
	addchunk_material = get_plugin().get_material("addchunk", self)
	removechunk_material = get_plugin().get_material("removechunk", self)
	brush_material = get_plugin().get_material("brush", self)
	
	var terrain_system: MarchingSquaresTerrain = get_node_3d()
	terrain_plugin = MarchingSquaresTerrainPlugin.instance
	
	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) != 1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] != terrain_system:
		return
	
	# Chunk management gizmo lines
	if terrain_system.chunks.is_empty():
		if MarchingSquaresTerrainPlugin.instance.is_chunk_plane_hovered:
			add_chunk_lines(terrain_system, MarchingSquaresTerrainPlugin.instance.current_hovered_chunk, addchunk_material)
	else:
		for chunk_coords: Vector2i in terrain_system.chunks:
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x-1, chunk_coords.y))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x+1, chunk_coords.y))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x, chunk_coords.y-1))
			try_add_chunk(terrain_system, Vector2i(chunk_coords.x, chunk_coords.y+1))
			try_add_chunk(terrain_system, chunk_coords)
	
	var pos: Vector3 = terrain_plugin.brush_position
	var cursor_chunk_coords: Vector2i
	var cursor_cell_coords: Vector2i
	
	if terrain_plugin.is_setting and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true
		
		var chunk_x = floor(pos.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x))
		var chunk_z = floor(pos.z / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y))
		cursor_chunk_coords = Vector2i(chunk_x, chunk_z)
		
		var x = int(floor(((pos.x + terrain_system.cell_size.x/2) / terrain_system.cell_size.x) - chunk_x * (terrain_system.dimensions.x - 1)))
		var z = int(floor(((pos.z + terrain_system.cell_size.y/2) / terrain_system.cell_size.y) - chunk_z * (terrain_system.dimensions.z - 1)))
		cursor_cell_coords = Vector2i(x, z)
		
		# When setting, if there is no pattern and alt not held, go to draw mode
		var has_pattern : bool = not terrain_plugin.current_draw_pattern.is_empty()
		if not has_pattern and not Input.is_key_pressed(KEY_ALT):
			terrain_plugin.current_draw_pattern.clear()
			terrain_plugin.is_setting = false
			terrain_plugin.is_drawing = true
			terrain_plugin.draw_height = pos.y
		
		# Otherwise, drag that pattern's height
		else:
			# If alt held, ONLY drag the cursor cell
			if Input.is_key_pressed(KEY_ALT) and terrain_system.chunks.has(cursor_chunk_coords):
				terrain_plugin.current_draw_pattern.clear()
				terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
				terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = terrain_system.chunks[cursor_chunk_coords].get_height(cursor_cell_coords)
				terrain_plugin.draw_height = pos.y
			terrain_plugin.base_position = pos
	
	if terrain_plugin.is_drawing and not terrain_plugin.draw_height_set:
		terrain_plugin.draw_height_set = true
		terrain_plugin.draw_height = terrain_plugin.brush_position.y
	
	var terrain_chunk_hovered: bool = terrain_plugin.terrain_hovered
	
	# Check if we're in wall painting mode
	var is_wall_painting : bool = terrain_plugin.paint_walls_mode and terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING
	
	if terrain_chunk_hovered:
		# Brush radius visualization
		var brush_transform : Transform3D
		brush_transform = Transform3D(Vector3.RIGHT * terrain_plugin.brush_size, Vector3.UP, Vector3.BACK * terrain_plugin.brush_size, pos)
		
		if is_wall_painting:
			var viewport := EditorInterface.get_editor_viewport_3d()
			var editor_camera := viewport.get_camera_3d()
			var mouse_pos := viewport.get_mouse_position()
			
			var ray_origin := editor_camera.project_ray_origin(mouse_pos)
			var ray_dir := editor_camera.project_ray_normal(mouse_pos)
			
			var space := terrain_system.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(
				ray_origin,
				ray_origin + ray_dir * 10000.0
			)
			
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit_result = space.intersect_ray(query)
			var wall_normal : Vector3 = Vector3.BACK
			if hit_result:
				wall_normal = hit_result.normal
			
			var basis := _create_brush_basis(wall_normal, terrain_plugin.brush_size)
			if wall_normal.y > 0.5:
				basis.z = Vector3.ZERO
			brush_transform = Transform3D(basis, pos)
			
		if terrain_plugin.mode == terrain_plugin.TerrainToolMode.VERTEX_PAINTING:
			if terrain_plugin.paint_walls_mode:
				add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, null, brush_transform)
		elif terrain_plugin.mode != terrain_plugin.TerrainToolMode.SMOOTH and terrain_plugin.mode != terrain_plugin.TerrainToolMode.GRASS_MASK and terrain_plugin.mode != terrain_plugin.TerrainToolMode.DEBUG_BRUSH and terrain_plugin.mode != terrain_plugin.TerrainToolMode.POPULATE:
			add_mesh(terrain_plugin.BRUSH_RADIUS_VISUAL, null, brush_transform)
		
		pos = terrain_plugin.brush_position
		
		var pos_tl := Vector2(pos.x + terrain_system.cell_size.x - terrain_plugin.brush_size/2, pos.z + terrain_system.cell_size.y - terrain_plugin.brush_size/2)
		var pos_br := Vector2(pos.x + terrain_system.cell_size.x + terrain_plugin.brush_size/2, pos.z + terrain_system.cell_size.y + terrain_plugin.brush_size/2)
		
		var chunk_tl_x := floori(pos_tl.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x))
		var chunk_tl_z := floori(pos_tl.y / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y))
		
		var chunk_br_x := floori(pos_br.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x))
		var chunk_br_z := floori(pos_br.y / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y))
		
		var x_tl := floori(pos_tl.x / terrain_system.cell_size.x - chunk_tl_x * (terrain_system.dimensions.x - 1))
		var z_tl := floori(pos_tl.y / terrain_system.cell_size.y - chunk_tl_z * (terrain_system.dimensions.z - 1))
		
		var x_br := floori(pos_br.x / terrain_system.cell_size.x - chunk_br_x * (terrain_system.dimensions.x - 1))
		var z_br := floori(pos_br.y / terrain_system.cell_size.y - chunk_br_z * (terrain_system.dimensions.z - 1))
		
		var max_distance = terrain_plugin.brush_size / 2
		match terrain_plugin.current_brush_index:
			0: # Round brush
				max_distance *= max_distance
			1: # Square brush
				max_distance *= max_distance * 2
		
		for chunk_z in range(chunk_tl_z, chunk_br_z+1):
			for chunk_x in range(chunk_tl_x, chunk_br_x+1):
				cursor_chunk_coords = Vector2i(chunk_x, chunk_z)
				if not terrain_system.chunks.has(cursor_chunk_coords):
					continue
				var chunk: MarchingSquaresTerrainChunk = terrain_system.chunks[cursor_chunk_coords]
				
				var x_min := x_tl if chunk_x == chunk_tl_x else 0
				var x_max := x_br if chunk_x == chunk_br_x else terrain_system.dimensions.x
				
				var z_min := z_tl if chunk_z == chunk_tl_z else 0
				var z_max := z_br if chunk_z == chunk_br_z else terrain_system.dimensions.z
				
				for z in range(z_min, z_max):
					for x in range(x_min, x_max):
						cursor_cell_coords = Vector2i(x, z)
						var world_x: float = (chunk_x * (terrain_system.dimensions.x-1) + x) * terrain_system.cell_size.x
						var world_z: float = (chunk_z * (terrain_system.dimensions.z-1) + z) * terrain_system.cell_size.y
						
						var distance_squared: float = Vector2(pos.x, pos.z).distance_squared_to(Vector2(world_x, world_z))
						if distance_squared > max_distance:
							continue
						
						var sample
						if terrain_plugin.falloff:
							var t: float
							match terrain_plugin.current_brush_index:
								0: # Round brush
									var d = (max_distance - distance_squared)/max_distance
									t = clamp(d, 0.0, 1.0)
								1: # Square brush
									var local = Vector2(world_x - pos.x, world_z - pos.z)
									var uv = local / (terrain_plugin.brush_size * 0.5)
									var d = max(abs(uv.x), abs(uv.y))
									t = 1.0 - clamp(d, 0.2, 1.0) 
							sample = terrain_plugin.falloff_curve.sample(clamp(t, 0.001, 0.999))
						else:
							sample = 1.0
						
						var y: float
						if not terrain_plugin.current_draw_pattern.is_empty() and terrain_plugin.flatten:
							y = terrain_plugin.draw_height
						else:
							y = chunk.height_map[z][x]
						
						var draw_position = Vector3(world_x, y, world_z)
						var draw_transform = Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
						# Only draw ground brush squares if NOT in wall paint mode
						if not is_wall_painting:
							add_mesh(terrain_plugin.BRUSH_VISUAL, brush_material, draw_transform)
						
						# Draw to current pattern
						if terrain_plugin.is_drawing:
							if not terrain_plugin.current_draw_pattern.has(cursor_chunk_coords):
								terrain_plugin.current_draw_pattern[cursor_chunk_coords] = {}
							if terrain_plugin.current_draw_pattern[cursor_chunk_coords].has(cursor_cell_coords):
								var prev_sample = terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords]
								if sample > prev_sample:
									terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
							else:
								terrain_plugin.current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
	
	var height_diff: float
	if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
		height_diff = terrain_plugin.brush_position.y - terrain_plugin.draw_height
	
	if not terrain_plugin.current_draw_pattern.is_empty():
		for draw_chunk_coords: Vector2i in terrain_plugin.current_draw_pattern:
			var chunk = terrain_system.chunks[draw_chunk_coords]
			var draw_chunk_dict: Dictionary = terrain_plugin.current_draw_pattern[draw_chunk_coords]
			for draw_coords: Vector2i in draw_chunk_dict:
				var draw_x = (draw_chunk_coords.x * (terrain_system.dimensions.x - 1) + draw_coords.x) * terrain_system.cell_size.x
				var draw_z = (draw_chunk_coords.y * (terrain_system.dimensions.z - 1) + draw_coords.y) * terrain_system.cell_size.y
				var draw_y = terrain_plugin.draw_height if terrain_plugin.flatten else chunk.height_map[draw_coords.y][draw_coords.x]
				
				var sample: float = draw_chunk_dict[draw_coords]
				
				# If setting, also show a square at the height to set to
				if terrain_plugin.is_setting and terrain_plugin.draw_height_set:
					var draw_position = Vector3(draw_x, draw_y + height_diff * sample, draw_z)
					var draw_transform = Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting:
						add_mesh(terrain_plugin.BRUSH_VISUAL, null, draw_transform)
				else:
					var draw_position = Vector3(draw_x, draw_y, draw_z)
					var draw_transform = Transform3D(Vector3.RIGHT*sample, Vector3.UP*sample, Vector3.BACK*sample, draw_position)
					if not is_wall_painting:
						add_mesh(terrain_plugin.BRUSH_VISUAL, null, draw_transform)


func _create_brush_basis(normal: Vector3, brush_size: float) -> Basis:
	var n := normal.normalized()
	
	var tangent := Vector3.UP.cross(n)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT.cross(n)
	
	tangent = tangent.normalized()
	var bitangent := n.cross(tangent)
	
	tangent *= brush_size
	bitangent *= brush_size
	
	return Basis(tangent, n, bitangent)


func try_add_chunk(terrain_system: MarchingSquaresTerrain, coords: Vector2i):
	var terrain_plugin = MarchingSquaresTerrainPlugin.instance
	
	# Add chunk
	if (terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT or Input.is_key_pressed(KEY_SHIFT)) and not terrain_system.chunks.has(coords) and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, coords, addchunk_material)
	
	# Remove chunk (Manage Chunk tool only)
	elif terrain_plugin.mode == terrain_plugin.TerrainToolMode.CHUNK_MANAGEMENT and terrain_plugin.is_chunk_plane_hovered and terrain_plugin.current_hovered_chunk == coords:
		add_chunk_lines(terrain_system, coords, removechunk_material) 


# Draw chunk lines around a chunk
func add_chunk_lines(terrain_system: MarchingSquaresTerrain, coords: Vector2i, material: Material):
	var dx = (terrain_system.dimensions.x - 1) * terrain_system.cell_size.x
	var dz = (terrain_system.dimensions.z - 1) * terrain_system.cell_size.y
	var x = coords.x * dx
	var z = coords.y * dz
	dx += x
	dz += z
	
	lines.clear()
	if not terrain_system.chunks.has(Vector2i(coords.x, coords.y-1)):
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,z))
	if not terrain_system.chunks.has(Vector2i(coords.x+1, coords.y)):
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(dx,0,dz))
	if not terrain_system.chunks.has(Vector2i(coords.x, coords.y+1)):
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(x,0,dz))
	if not terrain_system.chunks.has(Vector2i(coords.x-1, coords.y)):
		lines.append(Vector3(x,0,dz))
		lines.append(Vector3(x,0,z))
	
	if material == removechunk_material:
		lines.append(Vector3(x,0,z))
		lines.append(Vector3(dx,0,dz))
		lines.append(Vector3(dx,0,z))
		lines.append(Vector3(x,0,dz))
	
	if material == addchunk_material:
		lines.append(Vector3(lerp(x, dx, 0.25), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.75), 0, lerp(z, dz, 0.5)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.25)))
		lines.append(Vector3(lerp(x, dx, 0.5), 0, lerp(z, dz, 0.75)))
	
	add_lines(lines, material, false)
