extends RefCounted
class_name MSTNavMeshController


var terrain
var preview_revision : int = 0
var dirty_chunks : Dictionary = {}
var chunk_face_cache : Dictionary = {}
var cache_signature : String = ""
var needs_bake : bool = false


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func invalidate_preview() -> void:
	preview_revision += 1


func invalidate_chunk(chunk_coords: Vector2i) -> void:
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var affected : Vector2i = chunk_coords + offset
		if terrain.chunks.has(affected):
			dirty_chunks[affected] = true
	needs_bake = true


func invalidate_all() -> void:
	for chunk_coords: Vector2i in terrain.chunks.keys():
		dirty_chunks[chunk_coords] = true
	needs_bake = true


func clear_bake_state() -> void:
	dirty_chunks.clear()
	needs_bake = false


func clear_debug_mesh() -> void:
	var debug_mesh : Node = terrain.get_node_or_null("TerrainNavDebug")
	if debug_mesh != null:
		debug_mesh.queue_free()


func bake() -> void:
	var scene_root := EngineWrapper.instance.get_root_for_node(terrain)
	if scene_root == null:
		push_warning("[MST] NavMesh bake skipped because no scene root could be found.")
		return
	terrain._ensure_nav_chunks_ready_for_bake()
	var nav_region : NavigationRegion3D = terrain._get_or_create_navmesh_region(scene_root)
	if nav_region == null:
		push_warning("[MST] NavMesh bake skipped because a NavigationRegion3D could not be created.")
		return
	var bake_signature : String = terrain._get_navmesh_bake_signature()
	if cache_signature != bake_signature:
		chunk_face_cache.clear()
		cache_signature = bake_signature
		invalidate_all()
	if not needs_bake and nav_region.navigation_mesh != null:
		return
	var nav_mesh := NavigationMesh.new()
	terrain._configure_navigation_mesh(nav_mesh)
	var bake_result : Dictionary = terrain._build_navigation_mesh_from_walkable_faces(nav_mesh)
	nav_region.navigation_mesh = nav_mesh
	terrain._clear_nav_source_root()
	clear_debug_mesh()
	if int(bake_result.get("polygon_count", 0)) <= 0:
		push_warning("[MST] NavMesh bake finished but no nav polygons were generated. Check slope settings and terrain shape.")
	if EngineWrapper.instance.is_editor():
		EngineWrapper.instance.mark_scene_as_unsaved()
	clear_bake_state()


func clear_baked() -> void:
	var nav_region := terrain.get_node_or_null("TerrainNavMesh") as NavigationRegion3D
	if nav_region == null:
		return
	nav_region.navigation_mesh = null
	clear_debug_mesh()
	if EngineWrapper.instance.is_editor():
		EngineWrapper.instance.mark_scene_as_unsaved()
	clear_bake_state()


func snap_vertex(vertex: Vector3, epsilon: float) -> Vector3:
	if epsilon <= 0.0:
		return vertex
	return Vector3(roundf(vertex.x / epsilon) * epsilon, roundf(vertex.y / epsilon) * epsilon, roundf(vertex.z / epsilon) * epsilon)


func vertex_key(vertex: Vector3, epsilon: float) -> String:
	var snapped := snap_vertex(vertex, epsilon)
	return "%d,%d,%d" % [roundi(snapped.x / epsilon), roundi(snapped.y / epsilon), roundi(snapped.z / epsilon)]


func triangle_key(a: Vector3, b: Vector3, c: Vector3, epsilon: float) -> String:
	var points := [vertex_key(a, epsilon), vertex_key(b, epsilon), vertex_key(c, epsilon)]
	points.sort()
	return "|".join(points)


func add_vertex(lookup: Dictionary, vertices: PackedVector3Array, vertex: Vector3, epsilon: float) -> int:
	var key := vertex_key(vertex, epsilon)
	if lookup.has(key):
		return int(lookup[key])
	var index := vertices.size()
	vertices.append(snap_vertex(vertex, epsilon))
	lookup[key] = index
	return index


func triangle_area(vertices: PackedVector3Array, indices: PackedInt32Array, triangle_index: int) -> float:
	var base := triangle_index * 3
	if base + 2 >= indices.size():
		return 0.0
	var a := int(indices[base])
	var b := int(indices[base + 1])
	var c := int(indices[base + 2])
	if a < 0 or a >= vertices.size() or b < 0 or b >= vertices.size() or c < 0 or c >= vertices.size():
		return 0.0
	return ((vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])).length() * 0.5


func edge_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


func accumulate_edge(edge_use: Dictionary, a: int, b: int) -> void:
	var key := edge_key(a, b)
	edge_use[key] = int(edge_use.get(key, 0)) + 1


func is_boundary_edge(edge_use: Dictionary, a: int, b: int) -> bool:
	return int(edge_use.get(edge_key(a, b), 0)) <= 1
