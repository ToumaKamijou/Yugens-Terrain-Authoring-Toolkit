extends MarchingSquaresTerrainCell
class_name MarchingSquaresAuthoredlCell

var c0: MeshInstance3D = preload("uid://cqg72yl74cqf7").instantiate().get_child(0)
var c1: MeshInstance3D = preload("uid://t4flqvcyafog").instantiate().get_child(0)
var c2: MeshInstance3D = preload("uid://cisql05w1tg1e").instantiate().get_child(0)
var c3: MeshInstance3D = preload("uid://dt38rwma05yd3").instantiate().get_child(0)
var c4: MeshInstance3D = preload("uid://b34pux3e3pnft").instantiate().get_child(0)
var c5: MeshInstance3D = preload("uid://d0crhnc15or7").instantiate().get_child(0)
var c5b: MeshInstance3D = preload("uid://cf7v67q8s4gsa").instantiate().get_child(0)
var c6: MeshInstance3D = preload("uid://b1yitv1oysrk8").instantiate().get_child(0)
var c7: MeshInstance3D = preload("uid://c6ke17d6q15yw").instantiate().get_child(0)
var c8: MeshInstance3D = preload("uid://dj17tbqb6dtky").instantiate().get_child(0)
var c9: MeshInstance3D = preload("uid://bhjyyn86u3raq").instantiate().get_child(0)
var c10: MeshInstance3D = preload("uid://bcd6vlsah6r3a").instantiate().get_child(0)
var c11: MeshInstance3D = preload("uid://by5fhtfe821v1").instantiate().get_child(0)
var c12: MeshInstance3D = preload("uid://66ukx5q67u1r").instantiate().get_child(0)
var c13: MeshInstance3D = preload("uid://dir2u5jlbtaoc").instantiate().get_child(0)
var c14: MeshInstance3D = preload("uid://cm8e8x3026kb1").instantiate().get_child(0)
var c15: MeshInstance3D = preload("uid://c2vi7uic1sbev").instantiate().get_child(0)
var c16: MeshInstance3D = preload("uid://nw716v010u2o").instantiate().get_child(0)
var c17: MeshInstance3D = preload("uid://d3boe1vqqnu35").instantiate().get_child(0)

func add_c0(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c0, chunk)

func add_c1(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c1, chunk, [1,0,0,0])
	
func add_c2(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c2, chunk, [1,1,0,0])
	
func add_c3(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c3, chunk,[2,1,0,0])
	
func add_c4(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c4, chunk,[1,2,0,0])
	
func add_c5(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c5, chunk,[0,1,1,0])
	
func add_c5b(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c5b, chunk,[0,2,1,0])
	
func add_c6(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c6, chunk,[0,1,1,1])
	
func add_c7(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c7, chunk,[0,1,1,2])
	
func add_c8(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c8, chunk,[0,1,2,1])

func add_c9(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c9, chunk,[0,2,1,1])

func add_c10(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c10, chunk,[0,2,1,2])

func add_c11(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c11, chunk,[0,1,2,2])

func add_c12(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c12, chunk,[0,1,3,2])

func add_c13(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c13, chunk,[0,3,1,2])

func add_c14(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c14, chunk,[0,1,2,3])

func add_c15(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c15, chunk,[0,2,1,3])

func add_c16(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c16, chunk,[1,0,0,0])

func add_c17(chunk: MarchingSquaresTerrainChunk) -> void:
	add_chunk_geometry(c17, chunk,[0,1,0,0])

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
	
	chunk.start_floor()
	assert(base_idx.size() % 3 == 0)
	
	const UP_MARGIN_DEG := 85.
	const UP_COS := cos(deg_to_rad(UP_MARGIN_DEG))
	
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
		
		var normal = (v1 - v0).cross(v2 - v0).normalized()
		if abs(normal.dot(Vector3.UP)) < UP_COS:
			#wall
			if chunk.floor_mode:
				chunk.start_wall()
		else:
			#not wall
			if not chunk.floor_mode:
				chunk.start_floor()
		
		chunk.add_point(v0.x, v0.y, v0.z, uv0.x, uv0.y, rotation) 
		chunk.add_point(v1.x, v1.y, v1.z, uv1.x, uv1.y, rotation) 
		chunk.add_point(v2.x, v2.y, v2.z, uv2.x, uv2.y, rotation) 
