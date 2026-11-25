extends MarchingSquaresTerrainCell
class_name MarchingSquaresPrefabCell


func add_c0() -> void:
	add_flat(0,0, 0, ay, aby, acy, abcdy)
	add_flat(0.5,0, 0, aby, by, abcdy, bdy)
	add_flat(0,0.5, 0, acy, abcdy, cy, cdy)
	add_flat(0.5,0.5, 0, abcdy, bdy, cdy, dy)


func add_c1() -> void:
	add_diagonal(0,0, 0, ay, ay, ay, ay, bcy, by, cy, bcy)
	add_flat(0.5,0, 0, by, by, bcy, bdy)
	add_flat(0,0.5, 0, cy, bcy, cy, cdy)
	add_flat(0.5,0.5, 0, bcy,bdy,cdy,dy)


func add_c2() -> void:
	add_orthogonal(0,0, 0, ay, aby, ay, aby, cy, cdy, cy, cdy)
	add_orthogonal(0.5,0 ,0, aby, by, aby, by, cdy, dy, cdy, dy)
	add_flat(0,0.5, 0, cy, cdy, cy, cdy)
	add_flat(0.5,0.5, 0, cdy,dy,cdy,dy)


func add_c3() -> void:
	add_diagonal(0,0, 0, ay, ay, ay, ay, by, by, by, by, false)
	add_orthogonal(0, 0, 0, by, by, by, by, cy, cdy, cy, cdy, true, true)
	add_orthogonal(0.5, 0, 0, by, by, by, by, cdy, dy, cdy, dy)
	add_flat(0, 0.5, 0, cy, cdy, cy, cdy)
	add_flat(0.5, 0.5, 0, cdy, dy, cdy, dy)


func add_c4() -> void:
	add_orthogonal(0, 0, 0, ay, ay, ay, ay, cy, cdy, cy, cdy)
	add_diagonal(0.5, 0, PI/2, by, by, by, by, ay, ay, ay, ay, false)
	add_orthogonal(0.5, 0, 0, ay, ay, ay, ay, cdy, dy, cdy, dy, true, false, true)
	add_flat(0, 0.5, 0, cy, cdy, cy, cdy)
	add_flat(0.5, 0.5, 0, cdy, dy, cdy, dy)


func add_c5() -> void:
	add_diagonal(0, 0, PI, bcy, cy, by, bcy, ady, ay, ay, ay)
	add_filler(0, 0.5, PI, cy, cy, bcy, cy, dy, ady, ady, ay, false)
	add_filler(0, 0.5, 0, cy, bcy, cy, cy, ay, ady, ady, dy, false)
	add_filler(0.5, 0, PI, by, bcy, by, by, dy, ady, ady, ay, false)
	add_filler(0.5, 0, 0, by, by, bcy, by, ay, ady, ady, dy, false)	
	add_diagonal(0.5, 0.5, 0, bcy, by, cy, bcy, ady, dy, dy, dy)


func add_c6() -> void:
	add_diagonal(0.5, 0, PI/2, by, by, by, by, cy, cy, cy, cy, false)
	add_diagonal(0, 0, PI, cy, cy, cy, cy, ady, ay, ay, ay)
	add_filler(0, 0.5, PI, cy, cy, cy, cy, dy, ady, ady, ay, false)
	add_filler(0, 0.5, 0, cy, cy, cy, cy, ay, ady, ady, dy, false)
	add_filler(0.5, 0, PI, cy, cy, cy, cy, dy, ady, ady, ay, false, true)
	add_filler(0.5, 0, 0, cy, cy, cy, cy, ay, ady, ady, dy, false, false, true)
	add_diagonal(0.5, 0.5, 0, cy, cy, cy, cy, ady, dy, dy, dy)


func add_c7() -> void:
	add_diagonal(0, 0, PI, bcy, cy, by, bcy, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, bdy, bcy, by, by, ay, ay, ay, ay)
	add_filler(0, 0.5, PI, cdy, cy, bcy, cy, ay, ay, ay, ay)
	add_flat(0.5, 0.5, 0, bcy, bdy, cdy, dy)


func add_c8() -> void:
	add_diagonal(0, 0, PI, bcy, cy, by, bcy, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, by, bcy, by, by, ay, ay, ay, ay)
	add_filler(0, 0.5, PI, cy, cy, bcy, cy, ay, ay, ay, ay)
	add_diagonal(0.5, 0.5, PI, dy, dy, dy, dy, bcy, cy, by, bcy)


func add_c9() -> void:
	add_diagonal(0, 0, PI, bdy, bdy, by, bdy, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, bdy, bdy, by, by, ay, ay, ay, ay)
	add_diagonal(0, 0.5, -PI/2, cy, cy, cy, cy, dy, bdy, dy, bdy, false)
	add_filler(0, 0.5, PI, dy, dy, bdy, bdy, ay, ay, ay, ay, true, false, true)
	add_flat(0.5, 0.5, 0, bdy, bdy, dy, dy)


func add_c10() -> void:
	add_diagonal(0, 0, PI, cdy, cy, cdy, cy, ay, ay, ay, ay)
	add_diagonal(0.5, 0, PI/2, by, by, by, by, dy, dy, cdy, cdy, false)
	add_filler(0.5, 0, PI, dy, cdy, dy, cdy, ay, ay, ay, ay, true, true)
	add_filler(0, 0.5, PI, cdy, cy, cdy, cy, ay, ay, ay, ay)
	add_flat(0.5, 0.5, 0, cdy, dy, cdy, dy)


func add_c11() -> void:
	add_diagonal(0, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay, true, false, false, true)
	add_orthogonal(0.5, 0, PI/2, by, bdy, by, bdy, cy, cy, cy, cy, false)
	add_filler(0, 0.5, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_orthogonal(0.5, 0.5, PI/2, bdy, dy, bdy, dy, cy, cy, cy, cy)


func add_c12() -> void:
	add_diagonal(0, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_orthogonal(0, 0.5, PI, cdy, cy, cdy, cy, by, by, by, by, false)
	add_filler(0, 0.5, PI, by, by, by, by, ay, ay, ay, ay, true, false, false, false, true)
	add_orthogonal(0.5, 0.5, PI, dy, cdy, dy, cdy, by, by, by, by)


func add_c13() -> void:
	add_diagonal(0, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_diagonal(0, 0.5, -PI/2, cy, cy, cy, cy, dy, dy, dy, dy, false)
	add_orthogonal(0, 0.5, PI, dy, dy, dy, dy, by, by, by, by, false, false, true)
	add_filler(0, 0.5, PI, by, by, by, by, ay, ay, ay, ay, true, false, false, false, true)
	add_orthogonal(0.5, 0.5, PI, dy, dy, dy, dy, by, by, by, by)


func add_c14() -> void:
	add_diagonal(0, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_diagonal(0.5, 0, PI/2, by, by, by, by, dy, dy, dy, dy, false)
	add_orthogonal(0.5, 0, PI/2, dy, dy, dy, dy, cy, cy, cy, cy, false, true)
	add_filler(0.5, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay, true, false, false, true)
	add_filler(0, 0.5, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_orthogonal(0.5, 0.5, PI/2, dy, dy, dy, dy, cy, cy, cy, cy)


func add_c15() -> void:
	add_diagonal(0, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_filler(0.5, 0, PI, by, by, by, by, ay, ay, ay, ay)
	add_orthogonal(0, 0.5, PI, cy, cy, cy, cy, by, by, by, by, false)
	add_filler(0, 0.5, PI, by, by, by, by, ay, ay, ay, ay, true, false, false, false, true)
	add_diagonal(0.5, 0.5, PI, dy, dy, dy, dy, cy, cy, cy, cy, false)
	add_orthogonal(0.5, 0.5, PI, cy, cy, cy, cy, by, by, by, by, true, true)


func add_c16() -> void:
	add_diagonal(0, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_orthogonal(0.5, 0, PI/2, by, by, by, by, cy, cy, cy, cy, false)
	add_filler(0.5, 0, PI, cy, cy, cy, cy, ay, ay, ay, ay, true, false, false, true)
	add_filler(0, 0.5, PI, cy, cy, cy, cy, ay, ay, ay, ay)
	add_diagonal(0.5, 0.5, PI, dy, dy, dy, dy, by, by, by, by, false)
	add_orthogonal(0.5, 0.5, PI/2, by, by, by, by, cy, cy, cy, cy, true, false, true)


func add_c17() -> void:
	var abdy := (ay+bdy)/2
	var bcdy := (cy+bdy)/2
	add_orthogonal(0, 0, 0, ay, aby, ay, abdy, cy, bcdy, cy, bcdy)
	add_flat(0, 0.5, 0, cy, bcdy, cy, cdy)
	add_flat(0.5, 0.5, 0, bcdy, bdy, cdy, dy)
	
	if not chunk.terrain_system.prefab_set:
		return
	var obj: MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_orthogonal()
	if not obj:
		return
	add_wall(obj.get_data("wall_top"), obj.get_data("wall"), Vector2(0.5, 0), 0, {"a": aby, "c": abdy, "b": by, "d": bdy, "c2": bcdy, "d2": bdy, "a2": bcdy, "b2": by}, true, false)
	add_chunk(obj.get_data("top_floor"), Vector2(0.5, 0), 0, {"a": aby, "c": abdy, "b": by, "d": bdy, "a2": aby - merge_threshold, "c2": abdy - merge_threshold, "b2": by, "d2": bdy})
	add_chunk(obj.get_data("bottom_floor"), Vector2(0.5, 0), 0, {"a": bcdy + merge_threshold, "b": by + merge_threshold, "c": bcdy + merge_threshold, "d": bdy + merge_threshold, "c2": bcdy, "d2": bdy, "a2": bcdy, "b2": by})


func add_c18() -> void:
	var acdy := (acy+dy)/2
	var abcy := (acy+by)/2
	
	if not chunk.terrain_system.prefab_set:
		return
	var obj : MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_orthogonal()
	if not obj:
		return
	add_wall(obj.get_data("wall_top"), obj.get_data("wall"), Vector2(0, 0), 0, {"a": ay, "c": acy, "b": aby, "d": abcy, "c2": acy, "d2": acdy, "a2": ay, "b2": acdy}, false, true)
	add_chunk(obj.get_data("top_floor"), Vector2(0, 0), 0, {"a": ay, "c": acy, "b": aby, "d": abcy, "a2": ay, "c2": acy, "b2": aby - merge_threshold, "d2": abcy - merge_threshold})
	add_chunk(obj.get_data("bottom_floor"), Vector2(0, 0), 0, {"c": acy + merge_threshold, "d": acdy + merge_threshold, "a": ay + merge_threshold, "b": acdy + merge_threshold, "c2": acy, "d2": acdy, "a2": ay, "b2": acdy})	
	
	add_orthogonal(0.5, 0, 0, aby, by, abcy, by, acdy, dy, acdy, dy)
	add_flat(0, 0.5, 0, acy, acdy, cy, cdy)
	add_flat(0.5, 0.5, 0, acdy, dy, cdy, dy)


func floor_snap(value: float, t: float) -> float:
	if t == 0.0:
		return value
	
	return floor(value / t) * t


func snap(value: float, t: float) -> float:
	if t == 0.0:
		return value
	
	return ceil(value / t) * t


func round_snap(a0: float, a1: float, t: float) -> float:
	if t == 0.0:
		return a0
	
	var n : int = round((a1 - a0) / t)
	return a0 + t * n


func add_wall(top, mid, offset: Vector2, rotation: float, corner_heights: Dictionary[String, float], snap_ac: bool = true, snap_bd: bool = true) -> void:
	var base_a := floor_snap(corner_heights["a2"], merge_threshold) if snap_ac else corner_heights["a2"]
	var base_b := floor_snap(corner_heights["b2"], merge_threshold) if snap_bd else corner_heights["b2"]
	var base_c := floor_snap(corner_heights["c2"], merge_threshold) if snap_ac else corner_heights["c2"]
	var base_d := floor_snap(corner_heights["d2"], merge_threshold) if snap_bd else corner_heights["d2"]
	
	var cur_a := corner_heights["a"]
	var cur_b := corner_heights["b"]
	var cur_c := corner_heights["c"]
	var cur_d := corner_heights["d"]
	
	# First step (this defines the TOP chunk thickness)
	var n_a := max(cur_a - merge_threshold, base_a)
	var n_b := max(cur_b - merge_threshold, base_b)
	var n_c := max(cur_c - merge_threshold, base_c)
	var n_d := max(cur_d - merge_threshold, base_d)
	
	# Add TOP chunk
	add_chunk(top, offset, rotation, {
		"a": cur_a, "b": cur_b, "c": cur_c, "d": cur_d,
		"a2": n_a, "b2": n_b, "c2": n_c, "d2": n_d
	}, true)
	
	cur_a = n_a
	cur_b = n_b
	cur_c = n_c
	cur_d = n_d
	
	# Continue with MID chunks downward
	while true:
		n_a = max(floor_snap(cur_a - merge_threshold, merge_threshold), base_a)
		n_b = max(floor_snap(cur_b - merge_threshold, merge_threshold), base_b)
		n_c = max(floor_snap(cur_c - merge_threshold, merge_threshold), base_c)
		n_d = max(floor_snap(cur_d - merge_threshold, merge_threshold), base_d)
		
		# Stop BEFORE adding if we've reached the base
		if cur_a <= base_a and cur_b <= base_b and cur_c <= base_c and cur_d <= base_d:
			break
		
		add_chunk(mid, offset, rotation, {
			"a": cur_a, "b": cur_b, "c": cur_c, "d": cur_d,
			"a2": n_a, "b2": n_b, "c2": n_c, "d2": n_d
		}, true)
		
		if n_a <= base_a and n_b <= base_b and n_c <= base_c and n_d <= base_d:
			break
		
		cur_a = n_a
		cur_b = n_b
		cur_c = n_c
		cur_d = n_d


func add_flat(ox: float, oy: float, rot: float, a: float, b: float, c: float, d: float) -> void:
	if not chunk.terrain_system.prefab_set:
		return
	
	var obj: MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_flat()
	if not obj:
		return
	
	add_chunk(obj.get_data("top_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})


func add_diagonal(ox: float, oy: float, rot: float, a: float, b: float, c: float, d: float, a2: float, b2: float, c2: float, d2: float, has_bfloor: bool = true) -> void:
	if not chunk.terrain_system.prefab_set:
		return
	
	var obj : MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_diagonal()
	if not obj:
		return
	
	add_wall(obj.get_data("wall_top"), obj.get_data("wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2})
	add_chunk(obj.get_data("top_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
	if has_bfloor:
		add_chunk(obj.get_data("bottom_floor"), Vector2(ox, oy), rot, {"a": a2 + merge_threshold, "b": b2 + merge_threshold, "c": c2 + merge_threshold, "d": d2 + merge_threshold, "a2": a2, "b2": b2, "c2": c2, "d2": d2})


func add_orthogonal(ox: float, oy: float, rot: float, a: float, b: float, c: float, d: float, a2: float, b2: float, c2: float, d2: float, has_bfloor: bool = true, cap_left: bool = false, cap_right: bool = false) -> void:
	if not chunk.terrain_system.prefab_set:
		return
	
	var obj : MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_orthogonal()
	if not obj:
		return
	
	add_wall(obj.get_data("wall_top"), obj.get_data("wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2})
	add_chunk(obj.get_data("top_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
	if has_bfloor:
		add_chunk(obj.get_data("bottom_floor"), Vector2(ox, oy), rot, {"a": a2 + merge_threshold, "b": b2 + merge_threshold, "c": c2 + merge_threshold, "d": d2 + merge_threshold, "a2": a2, "b2": b2, "c2": c2, "d2": d2})
	if cap_left:
		add_chunk(obj.get_data("orthogonal_orthogonal_cap_left_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("orthogonal_orthogonal_cap_left_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)
	if cap_right:
		add_chunk(obj.get_data("orthogonal_orthogonal_cap_right_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("orthogonal_orthogonal_cap_right_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)


func add_filler(ox: float, oy: float, rot: float, a: float, b: float, c: float, d: float, a2: float, b2: float, c2: float, d2: float, full_top: bool = true, dd_cap_left: bool = false, dd_cap_right: bool = false, do_cap_left: bool = false, do_cap_right: bool = false) -> void:
	if not chunk.terrain_system.prefab_set:
		return
	
	var obj: MarchingSquaresPrefab = chunk.terrain_system.prefab_set.get_random_filler()
	if not obj:
		return
	
	add_wall(obj.get_data("wall_top"), obj.get_data("wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2})
	add_chunk(obj.get_data("top_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
	add_chunk(obj.get_data("bottom_floor"), Vector2(ox, oy), rot, {"a": a2 + merge_threshold, "b": b2 + merge_threshold, "c": c2 + merge_threshold, "d": d2 + merge_threshold, "a2": a2, "b2": b2, "c2": c2, "d2": d2})
	if full_top:
		add_chunk(obj.get_data("top_floor_half"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
	if dd_cap_left:
		add_chunk(obj.get_data("diagonal_diagonal_cap_left_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("diagonal_diagonal_cap_left_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)
	if dd_cap_right:
		add_chunk(obj.get_data("diagonal_diagonal_cap_right_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("diagonal_diagonal_cap_right_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)
	if do_cap_left:
		add_chunk(obj.get_data("diagonal_orthogonal_cap_left_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("diagonal_orthogonal_cap_left_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)
	if do_cap_right:
		add_chunk(obj.get_data("diagonal_orthogonal_cap_right_floor"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a - merge_threshold, "b2": b - merge_threshold, "c2": c - merge_threshold, "d2": d - merge_threshold})
		add_chunk(obj.get_data("diagonal_orthogonal_cap_right_wall"), Vector2(ox, oy), rot, {"a": a, "b": b, "c": c, "d": d, "a2": a2, "b2": b2, "c2": c2, "d2": d2}, true)


func add_chunk(dat, offset: Vector2, rotation: float, corner_heights: Dictionary[String, float], is_wall: bool = false) -> void:
	if not dat:
		return
	var base_arrays := dat.arrays as Array
	
	var base_uv : PackedVector2Array = base_arrays[Mesh.ARRAY_TEX_UV]
	var base_uv2 : PackedVector2Array = []
	if base_arrays[Mesh.ARRAY_TEX_UV2]:
		base_uv2 = base_arrays[Mesh.ARRAY_TEX_UV2]
	var base_idx : PackedInt32Array = base_arrays[Mesh.ARRAY_INDEX]
	var base_vertices : PackedVector3Array = base_arrays[Mesh.ARRAY_VERTEX]
	var base_normals : PackedVector3Array = base_arrays[Mesh.ARRAY_NORMAL]
	var vtx_color : PackedColorArray = base_arrays[Mesh.ARRAY_COLOR]
	var result := base_vertices.duplicate()
	
	for i in base_vertices.size():
		var delta_y := 0.0
		for key in dat.weights:
			if not corner_heights.has(key):
				continue
			var vy := corner_heights[key] 
			if not key.ends_with("2"):
				vy -= dat.size.y
			delta_y += dat.weights[key][i] * vy
		result[i].y += delta_y
	
	if is_wall:
		start_wall()
	else:
		start_floor()
	
	assert(base_idx.size() % 3 == 0)
	
	const UP_MARGIN_DEG := 85.
	const UP_COS := cos(deg_to_rad(UP_MARGIN_DEG))
	
	var r := int(rotation / (PI/2) ) & 3
	var tx := offset.x + (0.5 if r == 1 or r == 2 else 0.)
	var tz := offset.y + (0.5 if r >= 2 else 0.)
	
	for i in range(base_idx.size()/3):
		var idx0 := base_idx[i*3]
		var idx1 := base_idx[i*3+1]
		var idx2 := base_idx[i*3+2]
		
		var v0 : Vector3
		var v1 : Vector3
		var v2 : Vector3
		
		v0 = transform_point(result[idx0],r, tx, tz)
		v1 = transform_point(result[idx1],r, tx, tz)
		v2 = transform_point(result[idx2],r, tx, tz)
		
		var uv0 := base_uv[idx0]
		var uv1 := base_uv[idx1]
		var uv2 := base_uv[idx2]
		
		var uv2_0 := Vector2.ZERO
		var uv2_1 := Vector2.ZERO
		var uv2_2 := Vector2.ZERO
		if base_uv2:
			uv2_0 = base_uv2[idx0]
			uv2_1 = base_uv2[idx1]
			uv2_2 = base_uv2[idx2]
		
		add_point(v0.x, v0.y, v0.z, uv0.x, uv0.y, uv2_0.x, uv2_0.y)
		add_point(v1.x, v1.y, v1.z, uv1.x, uv1.y, uv2_1.x, uv2_1.y)
		add_point(v2.x, v2.y, v2.z, uv2.x, uv2.y, uv2_2.x, uv2_2.y)


func transform_point(v: Vector3, r: int, tx: float, tz: float) -> Vector3:
	match r:
		1:
			return Vector3(-v.z + tx, v.y,  v.x + tz)
		2:
			return Vector3(-v.x + tx, v.y, -v.z + tz)
		3:
			return Vector3( v.z + tx, v.y, -v.x + tz)
		_:
			return Vector3(v.x + tx, v.y, v.z + tz)


func is_face_flat(base_n: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, e: float = 0.999) -> bool:
	return n0.dot(n1) > e and \
		n1.dot(n2) > e and \
		n2.dot(n0) > e
