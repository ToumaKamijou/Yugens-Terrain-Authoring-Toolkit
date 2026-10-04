# This gizmo will have a handle for every single height value.
# Mostly for debugging.

extends EditorNode3DGizmo
class_name MarchingSquaresTerrainChunkGizmo


func _redraw():
	clear()
	
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	# height_map can be empty while a chunk is initializing or after load errors.
	if terrain.height_map.is_empty():
		return
	var dx := (terrain.dimensions.x - 1) * terrain.cell_size.x
	var dz := (terrain.dimensions.z - 1) * terrain.cell_size.y
	
	# Only draw the gizmo if this is the only selected node
	if len(EditorInterface.get_selection().get_selected_nodes()) !=  1:
		return
	if EditorInterface.get_selection().get_selected_nodes()[0] !=  terrain:
		return
	
	# Handles for raising/lowering terrain (will probably be removed later in favor of brush)
	var corners := PackedVector3Array()
	var ids := PackedInt32Array()
	for z in range(terrain.dimensions.z):
		if z < 0 or z >=  terrain.height_map.size():
			continue
		for x in range(terrain.dimensions.x):
			if x < 0 or x >=  terrain.height_map[z].size():
				continue
			var y = terrain.height_map[z][x]
			corners.append(Vector3(x * terrain.cell_size.x, y, z * terrain.cell_size.y))
			ids.append(z*terrain.dimensions.x + x)
	add_handles(corners, get_plugin().get_material("handles", self), ids)


func _get_handle_name(handle_id: int, secondary: bool) -> String:
	return str(handle_id);


func _get_handle_value(handle_id: int, secondary: bool) -> Variant:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return 0.0
	if terrain.height_map.is_empty():
		return 0.0
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return 0.0
	return terrain.height_map[z][x]


func _commit_handle(handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return
	
	if cancel:
		terrain.height_map[z][x] = restore
		terrain.mark_dirty()
	else:
		var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
		
		var do_value = terrain.height_map[z][x]
		
		undo_redo.create_action("move terrain point")
		undo_redo.add_do_method(self, "move_terrain_point", terrain, handle_id, do_value)
		undo_redo.add_undo_method(self, "move_terrain_point", terrain, handle_id, restore)
		undo_redo.commit_action()
	
	terrain.update_gizmos()


func move_terrain_point(terrain: MarchingSquaresTerrainChunk, handle_id: int, height: float):
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return
	terrain.draw_height(x, z, height)
	terrain.regenerate_mesh()
	terrain.update_gizmos()


func _set_handle(handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var terrain := get_node_3d() as MarchingSquaresTerrainChunk
	if terrain == null:
		return
	if terrain.height_map.is_empty():
		return
	var z = handle_id / terrain.dimensions.x
	var x = handle_id % terrain.dimensions.x
	if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
		return
	var y = terrain.height_map[z][x]
	# Get handle position
	var handle_position = terrain.to_global(Vector3(x * terrain.cell_size.x, y, z * terrain.cell_size.y))

	# Convert mouse movement to 3D world coordinates using raycasting
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	# We want the movement restricted to the Y-axis.
	# Create a plane that is parallel to the XZ plane (normal pointing along Y-axis)
	var plane = Plane(Vector3(ray_dir.x, 0, ray_dir.z), handle_position)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)

	if intersection:
		intersection = terrain.to_local(intersection)
		if z < 0 or z >=  terrain.height_map.size() or x < 0 or x >= terrain.height_map[z].size():
			return
		terrain.height_map[z][x] = intersection.y
		terrain.mark_dirty()
		terrain.update_gizmos()
