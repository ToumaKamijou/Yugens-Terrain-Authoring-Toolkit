extends MarchingSquaresTerrainCell
class_name MarchingSquaresAuthoredlCell

@export var prefabs : MarchingSquaresTerrainPrefabCells

@export var detect_walls := false

@export var use_prefab_normals := false

func add_c0(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c0,chunk, [0,0,0,0])
	
func add_c1(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c1,chunk, [1,0,0,0])
	
func add_c2(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c2,chunk, [1,1,0,0])
	
func add_c3(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c3,chunk,[2,1,0,0])
	
func add_c4(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c4,chunk,[1,2,0,0])
	
func add_c5(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c5,chunk,[0,1,1,0])
	
func add_c5b(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c5b,chunk,[0,2,1,0])
	
func add_c6(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c6,chunk,[0,1,1,1])
	
func add_c7(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c7,chunk,[0,1,1,2])
	
func add_c8(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c8,chunk,[0,1,2,1])

func add_c9(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c9,chunk,[0,2,1,1])

func add_c10(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c10,chunk,[0,2,1,2])

func add_c11(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c11,chunk,[0,1,2,2])

func add_c12(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c12,chunk,[0,1,3,2])

func add_c13(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c13,chunk,[0,3,1,2])

func add_c14(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c14,chunk,[0,1,2,3])

func add_c15(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c15,chunk,[0,2,1,3])

func add_c16(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c16,chunk,[1,0,0,0])

func add_c17(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(prefabs.c17,chunk,[0,1,0,0])

func add_chunk_geometry(mesh: MeshInstance3D, chunk: MarchingSquaresTerrainChunk, offsets: Array[float] = [0,0,0,0]) -> void:
	var ay_idx := mesh.find_blend_shape_by_name("ay")
	var by_idx := mesh.find_blend_shape_by_name("by")
	var cy_idx := mesh.find_blend_shape_by_name("cy")
	var dy_idx := mesh.find_blend_shape_by_name("dy")
	
	var base_arrays := mesh.mesh.surface_get_arrays(0)
	var ay_arrays := mesh.mesh.surface_get_blend_shape_arrays(0)[ay_idx]
	var by_arrays := mesh.mesh.surface_get_blend_shape_arrays(0)[by_idx]
	var cy_arrays := mesh.mesh.surface_get_blend_shape_arrays(0)[cy_idx]
	var dy_arrays := mesh.mesh.surface_get_blend_shape_arrays(0)[dy_idx]
		
	var base_uv : PackedVector2Array = base_arrays[Mesh.ARRAY_TEX_UV]
	var base_idx : PackedInt32Array = base_arrays[Mesh.ARRAY_INDEX]
	var base_vertices : PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var base_normals : PackedVector3Array = base_arrays[Mesh.ARRAY_NORMAL]
	
	var ay_vertices : PackedVector3Array = ay_arrays[Mesh.ARRAY_VERTEX]
	var by_vertices : PackedVector3Array = by_arrays[Mesh.ARRAY_VERTEX]
	var cy_vertices : PackedVector3Array = cy_arrays[Mesh.ARRAY_VERTEX]
	var dy_vertices : PackedVector3Array = dy_arrays[Mesh.ARRAY_VERTEX]
	
	assert(base_vertices.size() == ay_vertices.size())
	assert(base_vertices.size() == by_vertices.size())
	assert(base_vertices.size() == cy_vertices.size())
	assert(base_vertices.size() == dy_vertices.size())
	
	var result := base_vertices.duplicate()
	
	for i in range(base_vertices.size()):
		result[i] += (ay_vertices[i] - base_vertices[i] ) * (ay-offsets[0])
		result[i] += (by_vertices[i] - base_vertices[i] ) * (by-offsets[1])
		result[i] += (cy_vertices[i] - base_vertices[i] ) * (cy-offsets[2])
		result[i] += (dy_vertices[i] - base_vertices[i] ) * (dy-offsets[3])
			
	assert(base_idx.size() % 3 == 0)
	
	const UP_MARGIN_DEG := 85.
	const UP_COS := cos(deg_to_rad(UP_MARGIN_DEG))
	if not detect_walls:
		chunk.start_floor()
	for i in range(base_idx.size()/3):
		var idx0 = base_idx[i*3]
		var idx1 = base_idx[i*3+1]
		var idx2 = base_idx[i*3+2]
			
		var v0 := result[idx0]
		var v1 := result[idx1]
		var v2 := result[idx2]
		
		var uv0 := base_uv[idx0]
		var uv1 := base_uv[idx1]
		var uv2 := base_uv[idx2]
		
		var n = (v2 - v0).cross(v1 - v0).normalized()
		
		var n0 := Vector3.ZERO
		var n1 := Vector3.ZERO
		var n2 := Vector3.ZERO
		
		if use_prefab_normals:
			if is_face_flat(n, base_normals[idx0], base_normals[idx1], base_normals[idx2]):
				n0 = n
				n1 = n
				n2 = n
			else:
				var a0 = (v1 - v0).angle_to(v2 - v0)
				var a1 = (v0 - v1).angle_to(v2 - v1)
				var a2 = (v0 - v2).angle_to(v1 - v2)
			
				n0 = (base_normals[idx0] + n * a0).normalized()
				n1 = (base_normals[idx1] + n * a1).normalized()
				n2 = (base_normals[idx2] + n * a2).normalized()
		
		if detect_walls:
			if abs(n.dot(Vector3.UP)) < UP_COS:
				#wall
				if chunk.floor_mode:
					chunk.start_wall()
			else:
				#not wall
				if not chunk.floor_mode:
					chunk.start_floor()
		
		chunk.add_point(v0, uv0, n0, rotation) 
		chunk.add_point(v1, uv1, n1, rotation) 
		chunk.add_point(v2, uv2, n2, rotation)

func is_face_flat(base_n: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, e: float = 0.999) -> bool:
	return n0.dot(n1) > e and \
		n1.dot(n2) > e and \
		n2.dot(n0) > e
