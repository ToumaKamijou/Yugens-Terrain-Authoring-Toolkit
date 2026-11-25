@tool
extends Node3D
class_name MarchingSquaresGrassPlanter


## MultiMesh data resource (transforms / custom data / bake). Drawn via RenderingServer.
var _multimesh : MultiMesh
var multimesh : MultiMesh:
	get:
		return _multimesh
	set(value):
		_multimesh = value
		_multimesh_rid_hydrated = false
		if is_inside_tree():
			sync_render_instance()
var _instance_rid : RID = RID()
## Baked MultiMeshes can deserialize with a packed `buffer` while the RenderingServer
## RID still has 0 instances (especially without MultiMeshInstance3D to hydrate them).
var _multimesh_rid_hydrated : bool = false

var _chunk : MarchingSquaresTerrainChunk
var terrain_system : MarchingSquaresTerrain
const _DEFERRED_GRASS_CELLS_PER_FRAME : int = 48
var _deferred_grass_cells : Array[Vector2i] = []
var _deferred_grass_cell_set:  Dictionary = {}
## Read cursor into `_deferred_grass_cells` (avoids O(n) pop_front on large cooks).
var _deferred_grass_read_index : int = 0
var _deferred_grass_pending := false
## True while a full-chunk cook is draining (initial build / subdivisions change).
## Incremental paint updates keep this false so undirtied grass stays visible.
var _deferred_grass_full_rebuild := false
## Set when a cook is cancelled mid-way so callers can resume afterwards.
var _deferred_grass_incomplete := false
## Bumped to invalidate stale async processors after cancel/restart.
var _deferred_grass_generation: int = 0

var visibility_range_begin : float = 0.0
var visibility_range_end : float = 0.0
var visibility_range_begin_margin : float = 0.0
var visibility_range_end_margin : float = 0.0

# Push grass points slightly inward when they're right next to a steep wall drop.
# This preserves normal random scattering on flat floors.
const _WALL_PUSH_SAMPLE_STEP_FRACTION : float = 0.5
# Pull blades back onto the upper surface before a steep drop.
const _WALL_PUSH_MAX_FRACTION : float = 0.25
# Reject triangles that are too steep to be a walkable grass surface. This is
# also a guard against legacy geometry incorrectly tagged as floor geometry.
const _MIN_GRASS_FACE_UP_DOT : float = 0.5
const _WALL_PUSH_DROP_TRIGGER_FACTOR : float = 0.6
const _MIN_NORMAL_LENGTH_SQUARED : float = 0.000001
# A zero-scale MultiMesh transform is invisible, but produces invalid planes in
# Godot's light culler. Keep hidden slots finite while remaining imperceptible.
const _HIDDEN_INSTANCE_SCALE : float = 0.0001

## Cached CPU copy of the terrain rl_noise_texture for noisy floor-blend grass picks.
var _cached_rl_noise_tex : Texture2D = null
var _cached_rl_noise_image : Image = null


func _enter_tree() -> void:
	set_notify_transform(true)
	sync_render_instance()


func _exit_tree() -> void:
	_free_render_instance()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			_sync_instance_transform()
		NOTIFICATION_VISIBILITY_CHANGED:
			_sync_instance_visible()
		NOTIFICATION_PREDELETE:
			_free_render_instance()


func set_grass_visible(p_visible: bool) -> void:
	visible = p_visible
	_sync_instance_visible()


func set_visibility_range(p_end: float, p_end_margin: float = 0.0) -> void:
	visibility_range_begin = 0.0
	visibility_range_begin_margin = 0.0
	visibility_range_end = maxf(p_end, 0.0)
	visibility_range_end_margin = maxf(p_end_margin, 0.0)
	_sync_visibility_range()


func sync_render_instance() -> void:
	if not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		_free_render_instance()
		return
	if multimesh == null:
		_free_render_instance()
		return
	
	_ensure_multimesh_render_rid()
	var multimesh_rid := multimesh.get_rid()
	if not multimesh_rid.is_valid():
		_free_render_instance()
		return
	
	if not _instance_rid.is_valid():
		_instance_rid = RenderingServer.instance_create2(multimesh_rid, world.scenario)
	else:
		RenderingServer.instance_set_base(_instance_rid, multimesh_rid)
		RenderingServer.instance_set_scenario(_instance_rid, world.scenario)
	
	RenderingServer.instance_geometry_set_cast_shadows_setting(
		_instance_rid,
		RenderingServer.SHADOW_CASTING_SETTING_OFF
	)
	_sync_instance_transform()
	_sync_instance_visible()
	_sync_visibility_range()


## Ensure the MultiMesh resource buffer is uploaded to a live RenderingServer RID.
## Loaded bake caches often keep transforms only in `buffer` until something
## (historically MultiMeshInstance3D) forces hydration.
func _ensure_multimesh_render_rid() -> void:
	if _multimesh_rid_hydrated or _multimesh == null:
		return
	var count := _multimesh.instance_count
	var buf := _multimesh.buffer
	if count <= 0 or buf.is_empty():
		_multimesh_rid_hydrated = true
		return
	# Older baked caches used an exact zero scale for hidden slots. Uploading
	# those transforms makes the renderer normalize a degenerate plane.
	var safe_buf := buf.duplicate()
	var has_degenerate_transform := false
	var hidden_scale := _HIDDEN_INSTANCE_SCALE
	var stride := _multimesh_buffer_stride(_multimesh)
	for i in count:
		var o := i * stride
		var basis_len2 := 0.0
		for axis in 3:
			var axis_offset := axis * 4
			basis_len2 += Vector3(safe_buf[o + axis_offset], safe_buf[o + axis_offset + 1], safe_buf[o + axis_offset + 2]).length_squared()
		if basis_len2 <= _MIN_NORMAL_LENGTH_SQUARED:
			has_degenerate_transform = true
			safe_buf[o] = hidden_scale
			safe_buf[o + 5] = hidden_scale
			safe_buf[o + 10] = hidden_scale
	var rid := _multimesh.get_rid()
	if not has_degenerate_transform and rid.is_valid() and RenderingServer.multimesh_get_instance_count(rid) == count:
		_multimesh_rid_hydrated = true
		return
	# Rebuild a fresh MultiMesh so allocate+buffer upload happens on a new RID.
	var live := MultiMesh.new()
	live.transform_format = _multimesh.transform_format
	live.use_colors = _multimesh.use_colors
	live.use_custom_data = _multimesh.use_custom_data
	live.instance_count = count
	live.mesh = _multimesh.mesh
	live.buffer = safe_buf
	live.visible_instance_count = _multimesh.visible_instance_count
	_multimesh = live
	_multimesh_rid_hydrated = true


func _free_render_instance() -> void:
	if _instance_rid.is_valid():
		RenderingServer.free_rid(_instance_rid)
		_instance_rid = RID()


func _sync_instance_transform() -> void:
	if _instance_rid.is_valid() and is_inside_tree():
		RenderingServer.instance_set_transform(_instance_rid, global_transform)


func _sync_instance_visible() -> void:
	if _instance_rid.is_valid():
		RenderingServer.instance_set_visible(_instance_rid, is_visible_in_tree())


func _sync_visibility_range() -> void:
	if not _instance_rid.is_valid():
		return
	RenderingServer.instance_geometry_set_visibility_range(
		_instance_rid,
		visibility_range_begin,
		visibility_range_end,
		visibility_range_begin_margin,
		visibility_range_end_margin,
		RenderingServer.VISIBILITY_RANGE_FADE_DISABLED
	)


func _safe_normalized(vec: Vector3, fallback: Vector3) -> Vector3:
	return vec.normalized() if vec.length_squared() > _MIN_NORMAL_LENGTH_SQUARED else fallback


func _build_grass_basis(normal: Vector3) -> Basis:
	var up := _safe_normalized(normal, Vector3.UP)
	var right := Vector3.FORWARD.cross(up)
	if right.length_squared() <= _MIN_NORMAL_LENGTH_SQUARED:
		right = Vector3.RIGHT.cross(up)
	right = _safe_normalized(right, Vector3.RIGHT)
	var forward := _safe_normalized(up.cross(right), Vector3.FORWARD)
	return Basis(right, forward, -up)


func _sample_height_local(x: float, z: float) -> float:
	if not _chunk or not terrain_system or not _chunk.height_map:
		return 0.0
	var cs := terrain_system.cell_size
	if cs.x == 0.0 or cs.y == 0.0:
		return 0.0
	
	var gx := clampf(x / cs.x, 0.0, float(_chunk.dimensions.x - 1))
	var gz := clampf(z / cs.y, 0.0, float(_chunk.dimensions.z - 1))
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1 := mini(x0 + 1, _chunk.dimensions.x - 1)
	var z1 := mini(z0 + 1, _chunk.dimensions.z - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	
	var h00 : float = float(_chunk.height_map[z0][x0])
	var h10 : float = float(_chunk.height_map[z0][x1])
	var h01 : float = float(_chunk.height_map[z1][x0])
	var h11 : float = float(_chunk.height_map[z1][x1])
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _wall_push_offset(p: Vector3) -> Vector3:
	if not _chunk or not terrain_system:
		return Vector3.ZERO
	var cs := terrain_system.cell_size
	var cell_min := minf(cs.x, cs.y)
	if cell_min <=  0.0001:
		return Vector3.ZERO
	
	var step := cell_min * _WALL_PUSH_SAMPLE_STEP_FRACTION
	var h := _sample_height_local(p.x, p.z)
	var drop_trigger := float(_chunk.merge_threshold) * _WALL_PUSH_DROP_TRIGGER_FACTOR
	
	var best_drop := 0.0
	var dir := Vector3.ZERO
	
	var drop_px := h - _sample_height_local(p.x + step, p.z)
	if drop_px > best_drop:
		best_drop = drop_px
		dir = Vector3(-1, 0, 0)
	var drop_nx := h - _sample_height_local(p.x - step, p.z)
	if drop_nx > best_drop:
		best_drop = drop_nx
		dir = Vector3(1, 0, 0)
	var drop_pz := h - _sample_height_local(p.x, p.z + step)
	if drop_pz > best_drop:
		best_drop = drop_pz
		dir = Vector3(0, 0, -1)
	var drop_nz := h - _sample_height_local(p.x, p.z - step)
	if drop_nz > best_drop:
		best_drop = drop_nz
		dir = Vector3(0, 0, 1)
	
	if best_drop <=  drop_trigger:
		return Vector3.ZERO
	
	var push_max := cell_min * _WALL_PUSH_MAX_FRACTION
	# Scale push by how "wall-like" the drop is, so small slopes don't get biased.
	var t := clampf((best_drop - drop_trigger) / maxf(drop_trigger, 0.0001), 0.0, 1.0)
	return dir * (push_max * t)


static func _multimesh_buffer_stride(mm: MultiMesh) -> int:
	var stride := 8 if mm.transform_format == MultiMesh.TRANSFORM_2D else 12
	if mm.use_colors:
		stride += 4
	if mm.use_custom_data:
		stride += 4
	return stride


## Transform stats from the packed MultiMesh buffer (not get_instance_transform).
## Baked resources can have a full `buffer` while the RS RID is still empty, so
## reading transforms via the RID API falsely reports every slot as identity.
## - placed: blade has a non-zero origin
## - hidden: zero-scale placeholder (intentional empty slot)
## - virgin: uncooked/garbage slot at origin (safe to treat as needs-recook)
## Revealing virgin slots looks like a giant grass pillar at the chunk origin.
static func get_multimesh_cook_stats(mm: MultiMesh) -> Dictionary:
	var placed := 0
	var hidden := 0
	var virgin := 0
	if mm == null or mm.instance_count <= 0:
		return {"placed": 0, "hidden": 0, "virgin": 0}
	var buf := mm.buffer
	var stride := _multimesh_buffer_stride(mm)
	if buf.size() < mm.instance_count * stride:
		# No packed buffer — fall back to API transforms.
		for i in mm.instance_count:
			var t: Transform3D = mm.get_instance_transform(i)
			if not t.origin.is_equal_approx(Vector3.ZERO):
				placed += 1
			elif t.basis.get_scale().length_squared() <= 0.000001:
				hidden += 1
			else:
				virgin += 1
		return {"placed": placed, "hidden": hidden, "virgin": virgin}
	for i in mm.instance_count:
		var o := i * stride
		var origin := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		var c0 := Vector3(buf[o], buf[o + 1], buf[o + 2])
		var c1 := Vector3(buf[o + 4], buf[o + 5], buf[o + 6])
		var c2 := Vector3(buf[o + 8], buf[o + 9], buf[o + 10])
		var basis_len2 := c0.length_squared() + c1.length_squared() + c2.length_squared()
		if not origin.is_equal_approx(Vector3.ZERO):
			placed += 1
		elif basis_len2 <= 0.000001:
			hidden += 1
		else:
			virgin += 1
	return {"placed": placed, "hidden": hidden, "virgin": virgin}


## True only when every slot is cooked (placed or hidden). Safe to persist/reveal.
static func is_multimesh_cooked(mm: MultiMesh) -> bool:
	if mm == null or mm.instance_count <= 0:
		return false
	var stats := get_multimesh_cook_stats(mm)
	return int(stats["virgin"]) == 0 and (int(stats["placed"]) > 0 or int(stats["hidden"]) == mm.instance_count)


func reveal_cooked_multimesh() -> void:
	if not is_multimesh_cooked(multimesh):
		return
	# Persisted cooks sometimes keep visible_instance_count at 0 (progressive cook /
	# mid-save). Reveal the full buffer once transforms are known to be present.
	if multimesh.visible_instance_count == 0:
		multimesh.visible_instance_count = multimesh.instance_count
	set_grass_visible(true)
	sync_render_instance()


func _hide_all_grass_instances() -> void:
	if multimesh == null:
		return
	var hidden := Transform3D(Basis.from_scale(Vector3.ONE * _HIDDEN_INSTANCE_SCALE), Vector3.ZERO)
	for i in multimesh.instance_count:
		multimesh.set_instance_transform(i, hidden)


func setup(chunk: MarchingSquaresTerrainChunk, redo: bool =  true) -> void:
	_chunk = chunk
	terrain_system = _chunk.terrain_system if _chunk else null
	
	if not _chunk or not terrain_system:
		push_error("SETUP FAILED - no chunk or terrain system found for GrassPlanter")
		return
	
	# The terrain may have applied visibility settings before this planter was
	# created. Apply them here as well so newly-created grass layers inherit the
	# current culling configuration immediately.
	if terrain_system.visibility_detail_enabled:
		set_visibility_range(
			terrain_system.grass_visibility_end_distance,
			terrain_system.visibility_range_margin if terrain_system.grass_visibility_end_distance > 0.0 else 0.0
		)
	else:
		set_visibility_range(0.0, 0.0)
	
	# Never reallocate a fully cooked MultiMesh — that wipes blade transforms.
	# Partial cooks (any virgin identity slots) must be rebuilt, not revealed.
	if is_multimesh_cooked(multimesh):
		_assign_grass_mesh()
		reveal_cooked_multimesh()
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	
	multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	
	multimesh.instance_count = (_chunk.dimensions.x - 1) * (_chunk.dimensions.z - 1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	# Default MultiMesh slots are identity (visible giant blades if revealed).
	# Hide every slot up front so progressive visible_instance_count is safe.
	_hide_all_grass_instances()
	multimesh.visible_instance_count = 0
	
	_assign_grass_mesh()
	sync_render_instance()


func _assign_grass_mesh() -> void:
	if not terrain_system or not multimesh:
		return
	# Prefer the terrain's already-scaled shared mesh. Do not re-apply grass_size
	# here — MarchingSquaresTerrain.grass_size already sizes grass_mesh.
	if terrain_system.grass_mesh:
		multimesh.mesh = terrain_system.grass_mesh
	else:
		var q := QuadMesh.new()
		var scale_factor := (terrain_system.cell_size.x + terrain_system.cell_size.y) / 4.0
		q.size = terrain_system.grass_size * scale_factor
		q.center_offset.y = q.size.y * 0.5
		multimesh.mesh = q


func ensure_multimesh_count() -> bool:
	if not multimesh or not _chunk or not terrain_system:
		return false
	
	var expected := (_chunk.dimensions.x - 1) * (_chunk.dimensions.z - 1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	if multimesh.instance_count != expected:
		# Resizing clears transforms. Drop a wrong-sized cooked cache so callers
		# can allocate/cook fresh instead of silently wiping blades in-place.
		if is_multimesh_cooked(multimesh):
			multimesh = null
			return true
		multimesh.instance_count = expected
		_hide_all_grass_instances()
		return true
	return false


func _expected_grass_cell_count() -> int:
	if _chunk == null:
		return 0
	return maxi((_chunk.dimensions.x - 1) * (_chunk.dimensions.z - 1), 0)


func _cell_geometry_ready_for_grass() -> bool:
	if _chunk == null or _chunk.cell_geometry == null:
		return false
	if _chunk.cell_geometry.is_empty():
		return false
	# Partial caches (common after bake strip / interrupted rebuild) still report
	# non-empty; require a complete key set before iterating every cell.
	return _chunk.cell_geometry.size() >= _expected_grass_cell_count()


func _ensure_cell_geometry_for_grass(force_recook: bool = false) -> bool:
	if _chunk == null:
		return false
	if _chunk._baked_mesh_is_complete and _chunk.cell_geometry.is_empty():
		# Baked chunks strip cell_geometry; skip recook unless placement rules changed.
		if is_multimesh_cooked(multimesh) and not force_recook:
			reveal_cooked_multimesh()
			return false
	elif _cell_geometry_ready_for_grass() and not force_recook:
		return true
	
	_chunk.rebuild_cell_geometry_for_grass()
	# Require a complete cell set — a partial dict is not enough to walk every cell.
	return _cell_geometry_ready_for_grass()


func regenerate_all_cells(force_recook: bool = false) -> void:
	# Safety checks
	if not _chunk:
		push_error("_chunk not set while regenerating cells")
		return
	
	if not terrain_system:
		push_error("terrain_system not set while regenerating cells")
		return
	
	if not multimesh:
		setup(_chunk)
	
	if not _ensure_cell_geometry_for_grass(force_recook):
		# Cooked bake already revealed inside ensure, or geometry is unavailable.
		# Unbaked empty caches may still need a mesh pass before grass can cook.
		if _chunk.cell_geometry.is_empty() and not _chunk._baked_mesh_is_complete:
			_chunk.regenerate_mesh()
		return
	
	_hide_all_grass_instances()
	for z in range(_chunk.dimensions.z - 1):
		for x in range(_chunk.dimensions.x - 1):
			generate_grass_on_cell(Vector2i(x, z))
	multimesh.visible_instance_count = multimesh.instance_count
	sync_render_instance()


func regenerate_all_cells_deferred() -> void:
	if not _chunk or not terrain_system:
		return
	# Hydrated chunks intentionally do not retain cell_geometry. Their persisted
	# MultiMesh is already usable, so do not launch a full grass rebuild that
	# would repeatedly fail on the stripped source cache.
	if not _ensure_cell_geometry_for_grass(false):
		if is_multimesh_cooked(multimesh):
			_deferred_grass_incomplete = false
		return
	if not multimesh:
		setup(_chunk)
	
	# Restarting replaces any in-flight cook. Bump the generation so stale
	# awaited processors cannot mark an incomplete MultiMesh as finished.
	_deferred_grass_generation += 1
	var generation := _deferred_grass_generation
	_deferred_grass_cells.clear()
	_deferred_grass_cell_set.clear()
	_deferred_grass_read_index = 0
	_deferred_grass_full_rebuild = true
	_deferred_grass_incomplete = false
	# Hide virgin identity slots before progressive reveal starts.
	_hide_all_grass_instances()
	if multimesh:
		multimesh.visible_instance_count = 0
	set_grass_visible(true)
	sync_render_instance()
	for z in range(_chunk.dimensions.z - 1):
		for x in range(_chunk.dimensions.x - 1):
			var cell_coords := Vector2i(x, z)
			_deferred_grass_cells.append(cell_coords)
			_deferred_grass_cell_set[cell_coords] = true
	_deferred_grass_pending = true
	if terrain_system != null and terrain_system.has_method("_enqueue_grass_cook"):
		terrain_system._enqueue_grass_cook(self, generation)
	else:
		call_deferred("_process_deferred_grass_cells", generation)


func queue_cells_for_regeneration(cells: Array) -> void:
	if not _chunk or not terrain_system or _chunk._scene_save_in_progress:
		return
	if not multimesh:
		setup(_chunk)
	var already_pending := _deferred_grass_pending
	for cell_value in cells:
		var cell_coords : Vector2i = cell_value
		if cell_coords.x < 0 or cell_coords.y < 0:
			continue
		if cell_coords.x >= _chunk.dimensions.x - 1 or cell_coords.y >= _chunk.dimensions.z - 1:
			continue
		# Hide only the dirty cell. Leaving the planter visible keeps the rest
		# of the chunk's grass on-screen during incremental paint updates.
		_hide_grass_cell(cell_coords)
		if _deferred_grass_cell_set.has(cell_coords):
			continue
		_deferred_grass_cells.append(cell_coords)
		_deferred_grass_cell_set[cell_coords] = true
	if _deferred_grass_read_index >= _deferred_grass_cells.size():
		return
	_deferred_grass_pending = true
	_deferred_grass_incomplete = false
	# Incremental cooks must not hide undirtied grass.
	if not _deferred_grass_full_rebuild:
		set_grass_visible(true)
		if multimesh:
			multimesh.visible_instance_count = multimesh.instance_count
	if already_pending:
		return
	_deferred_grass_generation += 1
	call_deferred("_process_deferred_grass_cells", _deferred_grass_generation)


func _hide_grass_cell(cell_coords: Vector2i) -> void:
	if multimesh == null:
		return
	var count := terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	var start := (cell_coords.y * (_chunk.dimensions.x - 1) + cell_coords.x) * count
	var end := mini(start + count, multimesh.instance_count)
	for index in range(start, end):
		_hide_grass_instance(index)


func cancel_deferred_grass_generation() -> void:
	var had_work := _deferred_grass_pending or _deferred_grass_read_index < _deferred_grass_cells.size()
	_deferred_grass_generation += 1
	_deferred_grass_cells.clear()
	_deferred_grass_cell_set.clear()
	_deferred_grass_read_index = 0
	_deferred_grass_pending = false
	_deferred_grass_full_rebuild = false
	if had_work:
		_deferred_grass_incomplete = true
	set_grass_visible(true)
	_notify_grass_cook_finished()


func _notify_grass_cook_finished() -> void:
	if terrain_system != null and terrain_system.has_method("_grass_cook_finished"):
		terrain_system._grass_cook_finished(self)


func is_deferred_grass_incomplete() -> bool:
	return _deferred_grass_incomplete


func _deferred_grass_remaining() -> int:
	return maxi(_deferred_grass_cells.size() - _deferred_grass_read_index, 0)


func _reveal_cooked_grass_through_cell(cell_coords: Vector2i) -> void:
	if multimesh == null or not _deferred_grass_full_rebuild:
		return
	var count := terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	var cell_end := (cell_coords.y * (_chunk.dimensions.x - 1) + cell_coords.x + 1) * count
	if cell_end > multimesh.visible_instance_count:
		multimesh.visible_instance_count = mini(cell_end, multimesh.instance_count)


func _process_deferred_grass_cells(generation: int = -1) -> void:
	if generation < 0:
		generation = _deferred_grass_generation
	if generation != _deferred_grass_generation:
		return
	
	if not is_inside_tree() or not _chunk or not terrain_system:
		if generation == _deferred_grass_generation:
			_deferred_grass_pending = false
			_deferred_grass_full_rebuild = false
			_deferred_grass_incomplete = _deferred_grass_remaining() > 0
			_notify_grass_cook_finished()
		return
	
	# Pause across scene saves instead of clearing the queue and declaring done.
	# PRE_SAVE cancel invalidates this generation; POST_SAVE resumes if needed.
	if _chunk._scene_save_in_progress:
		return
	
	var count := mini(_DEFERRED_GRASS_CELLS_PER_FRAME, _deferred_grass_remaining())
	for _i in range(count):
		if generation != _deferred_grass_generation:
			return
		var cell_coords := _deferred_grass_cells[_deferred_grass_read_index]
		_deferred_grass_read_index += 1
		_deferred_grass_cell_set.erase(cell_coords)
		generate_grass_on_cell(cell_coords)
		_reveal_cooked_grass_through_cell(cell_coords)
	
	if generation != _deferred_grass_generation:
		return
	
	if _deferred_grass_remaining() > 0:
		await get_tree().process_frame
		if generation != _deferred_grass_generation:
			return
		if _chunk == null or _chunk._scene_save_in_progress:
			return
		_process_deferred_grass_cells(generation)
		return
	
	_deferred_grass_cells.clear()
	_deferred_grass_cell_set.clear()
	_deferred_grass_read_index = 0
	_deferred_grass_pending = false
	_deferred_grass_full_rebuild = false
	_deferred_grass_incomplete = false
	set_grass_visible(true)
	if multimesh:
		multimesh.visible_instance_count = multimesh.instance_count
	_notify_grass_cook_finished()


func generate_grass_on_cell(cell_coords: Vector2i) -> void:
	# Safety checks
	if not _chunk:
		push_error("Couldn't find a reference to _chunk")
		return
	if _chunk._scene_save_in_progress:
		return
	
	if not terrain_system:
		push_error("Couldn't find a reference to terrain_system")
		return
	if cell_coords.x < 0 or cell_coords.y < 0 or cell_coords.x >= _chunk.dimensions.x - 1 or cell_coords.y >= _chunk.dimensions.z - 1:
		return
	
	if _chunk.cell_geometry == null or _chunk.cell_geometry.is_empty():
		# Baked chunks intentionally strip cell_geometry; other paths rebuild first.
		return
	
	if not _chunk.cell_geometry.has(cell_coords):
		# Void / unauthored / incomplete-cache cells have no floor geometry — hide
		# any leftover instances quietly instead of spamming the editor log.
		_hide_grass_cell(cell_coords)
		return
	
	var cell_geometry = _chunk.cell_geometry[cell_coords]

	if not cell_geometry.has("verts") or not cell_geometry.has("uvs") or not cell_geometry.has("color_1s") or not cell_geometry.has("custom_1_values") or not cell_geometry.has("mat_blend") or not cell_geometry.has("is_floor"):
		push_error("cell_geometry missing required data: verts, uvs, color_1s (CUSTOM0), custom_1_values (CUSTOM1), mat_blend (CUSTOM2), is_floor")
		return
	
	ensure_multimesh_count()
	
	var points : Array[Vector2] = []
	var count := terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	
	for sz in range(terrain_system.grass_subdivisions):
		for sx in range(terrain_system.grass_subdivisions):
			# Edge detection so grass doesn't bleed through other textures
			var edge_margin := 0.12
			var slotx := lerpf(edge_margin, 1.0 - edge_margin, randf())
			var slotz := lerpf(edge_margin, 1.0 - edge_margin, randf())
			points.append(Vector2(
				(cell_coords.x + (sx + slotx) / terrain_system.grass_subdivisions) * terrain_system.cell_size.x,
				(cell_coords.y + (sz + slotz) / terrain_system.grass_subdivisions) * terrain_system.cell_size.y
			))
	
	var index : int = (cell_coords.y * (_chunk.dimensions.x - 1) + cell_coords.x) * count
	var end_index : int = index + count
	
	if multimesh == null:
		return
	
	for slot in range(index, end_index):
		if slot >=  multimesh.instance_count:
			break
		_hide_grass_instance(slot)
	
	var verts : PackedVector3Array = cell_geometry["verts"]
	var uvs : PackedVector2Array = cell_geometry["uvs"]
	var custom_0_values : PackedColorArray = cell_geometry["color_1s"] # CUSTOM0
	var custom_1_values : PackedColorArray = cell_geometry["custom_1_values"] # CUSTOM1
	var mat_blend : PackedColorArray = cell_geometry["mat_blend"] # CUSTOM2
	var is_floor : Array = cell_geometry["is_floor"]
	
	for i in range(0, len(verts), 3):
		if i + 2 >=  len(verts):
			continue # Skip incomplete triangle
		
		# Only place grass on floors
		if not is_floor[i]:
			continue
		
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var face_normal := _safe_normalized((b - a).cross(c - a), Vector3.ZERO)
		# Floor winding can face either direction depending on the generated
		# triangle order; use the absolute slope so valid flat floors survive.
		if face_normal == Vector3.ZERO or absf(face_normal.dot(Vector3.UP)) < _MIN_GRASS_FACE_UP_DOT:
			continue
		
		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		
		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0 / (dot00 * dot11 - dot01 * dot01)
		
		var point_index := 0
		while point_index < len(points):
			var v2 := Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
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
			
			if u + v <=  1:
				# Barycentric weights: wa for vertex a, wb for b, wc for c
				var wa := 1.0 - u - v
				var wb := u
				var wc := v
				
				# Order is irrelevant here, so use swap-remove to avoid O(n) PackedArray shifts
				# for every accepted blade during full chunk grass generation.
				var last_idx := points.size() - 1
				points[point_index] = points[last_idx]
				points.pop_back()
				var p := a * (1 - u - v) + b * u + c * v
				
				# If we're near a steep ledge, pull the blade inward only when the
				# destination remains on the same height surface. A large height
				# change means the offset crossed into the wall or a lower layer.
				var push := _wall_push_offset(p)
				if push != Vector3.ZERO:
					var pushed_p := p + push
					var surface_tolerance := maxf(minf(terrain_system.cell_size.x, terrain_system.cell_size.y) * 0.15, 0.05)
					var pushed_height := _sample_height_local(pushed_p.x, pushed_p.z)
					if absf(pushed_height - p.y) > surface_tolerance:
						continue
					p = pushed_p
				
				# Interpolated material blend payload (CUSTOM2) + extra weight (CUSTOM0.r)
				var raw_blend := mat_blend[i] * wa + mat_blend[i + 1] * wb + mat_blend[i + 2] * wc
				var raw_custom0 := custom_0_values[i] * wa + custom_0_values[i + 1] * wb + custom_0_values[i + 2] * wc
				
				# Check grass mask first - green channel forces grass ON, red channel masks grass OFF
				var mask := custom_1_values[i] * wa + custom_1_values[i + 1] * wb + custom_1_values[i + 2] * wc
				var is_masked : bool = mask.r < 0.9999
				var force_grass_on : bool = mask.g >= 0.9999
				
				var mat_a := clampi(int(round(raw_blend.r)), 0, 255)
				var mat_b := clampi(int(round(raw_blend.g)), 0, 255)
				var mat_c := clampi(int(round(raw_blend.b)), 0, 255)
				var w_a := clamp(raw_blend.a, 0.0, 1.0)
				var w_b := clamp(raw_custom0.r, 0.0, 1.0)
				var w_c := clamp(1.0 - w_a - w_b, 0.0, 1.0)
				
				# Match terrain floor selection: dominant weights in Smooth mode,
				# noisy source/target islands when Floor Blend Mode is Noisy.
				var world_sample_pos := p
				if _chunk != null:
					world_sample_pos = _chunk.to_global(p)
				var selected_mat := _resolve_floor_material_index(
					world_sample_pos, mat_a, mat_b, mat_c, w_a, w_b, w_c
				)
				var texture_id := selected_mat + 1
				var on_grass_tex := _has_grass_for_texture(texture_id, force_grass_on)
				
				var ground_uv := uvs[i] * wa + uvs[i + 1] * wb + uvs[i + 2] * wc
				
				if on_grass_tex and not is_masked:
					_create_grass_instance(index, p, a, b, c, texture_id, ground_uv)
				else:
					_hide_grass_instance(index)
				
				index += 1
			else:
				point_index += 1
	
	# Fill remaining points with hidden instances
	while index < end_index:
		if index >=  multimesh.instance_count:
			return
		_hide_grass_instance(index)
		index += 1

#region grass property getters

func _get_terrain_image(texture_id: int) -> Image:
	var slot_idx := clampi(texture_id - 1, 0, 255)
	var terrain_texture : Texture2D = null
	
	if terrain_system and terrain_system.texture_slots.size() > slot_idx and terrain_system.texture_slots[slot_idx] !=  null:
		terrain_texture = terrain_system.texture_slots[slot_idx].texture
	if not _is_valid_texture2d(terrain_texture):
		terrain_texture = _get_library_albedo_texture(slot_idx)
	
	if not _is_valid_texture2d(terrain_texture):
		return null
	
	var img : Image = terrain_texture.get_image()
	if img:
		img.decompress()
	return img


func _is_valid_texture2d(tex) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return tex.get_class() != "Texture2D"


func _get_library_albedo_texture(slot_idx: int) -> Texture2D:
	if terrain_system == null or not terrain_system.has_method("get"):
		return null
	var lib = terrain_system.get("texture_library")
	if lib == null:
		return null
	if lib is Resource and lib.resource_path != null and not str(lib.resource_path).is_empty():
		var loaded = ResourceLoader.load(str(lib.resource_path))
		if loaded != null:
			lib = loaded
	if not (lib is MSTextureLibrary):
		return null
	if lib.has_method("ensure_length"):
		lib.ensure_length()
	if slot_idx < 0 or slot_idx >= lib.albedo_textures.size():
		return null
	var tex = lib.albedo_textures[slot_idx]
	return tex as Texture2D if _is_valid_texture2d(tex) else null


func _get_texture_id(vc_col_0: Color, vc_col_1: Color) -> int:
	var id : int = 1
	if vc_col_0.r > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 1
		elif vc_col_1.g > 0.9999:
			id = 2
		elif vc_col_1.b > 0.9999:
			id = 3
		elif vc_col_1.a > 0.9999:
			id = 4
	elif vc_col_0.g > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 5
		elif vc_col_1.g > 0.9999:
			id = 6
		elif vc_col_1.b > 0.9999:
			id = 7
		elif vc_col_1.a > 0.9999:
			id = 8
	elif vc_col_0.b > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 9
		elif vc_col_1.g > 0.9999:
			id = 10
		elif vc_col_1.b > 0.9999:
			id = 11
		elif vc_col_1.a > 0.9999:
			id = 12
	elif vc_col_0.a > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 13
		elif vc_col_1.g > 0.9999:
			id = 14
		elif vc_col_1.b > 0.9999:
			id = 15
		elif vc_col_1.a > 0.9999:
			id = 16
	return id


## Picks the visible floor material index (0-based), mirroring mst_terrain noisy blend.
func _resolve_floor_material_index(
	world_pos: Vector3,
	mat_a: int,
	mat_b: int,
	mat_c: int,
	w_a: float,
	w_b: float,
	w_c: float
) -> int:
	w_a = maxf(w_a, 0.0)
	w_b = maxf(w_b, 0.0)
	w_c = maxf(w_c, 0.0)
	var weight_sum := w_a + w_b + w_c
	if weight_sum > 0.001:
		w_a /= weight_sum
		w_b /= weight_sum
		w_c /= weight_sum
	
	var dominant_mat := mat_a
	var confidence := w_a
	if w_b > confidence:
		dominant_mat = mat_b
		confidence = w_b
	if w_c > confidence:
		dominant_mat = mat_c
		confidence = w_c
	
	if terrain_system == null or int(terrain_system.floor_blend_mode) != 1:
		return dominant_mat
	
	# Noisy floor blending: lowest-index present material vs dominant alternative.
	var source_idx := -1
	var source_w := 0.0
	if w_a > 0.001:
		source_idx = mat_a
		source_w = w_a
	if w_b > 0.001 and (source_idx < 0 or mat_b < source_idx):
		source_idx = mat_b
		source_w = w_b
	if w_c > 0.001 and (source_idx < 0 or mat_c < source_idx):
		source_idx = mat_c
		source_w = w_c
	if source_idx < 0:
		return dominant_mat
	
	var target_idx := dominant_mat
	if target_idx == source_idx:
		if mat_a != source_idx:
			target_idx = mat_a
		else:
			target_idx = mat_b
	
	var tile_size := 0.075
	var rl_strength := 10.0
	var threshold := float(terrain_system.blend_noise_threshold)
	var mat := terrain_system.terrain_material
	if mat != null:
		var ts: Variant = mat.get_shader_parameter("rl_noise_tile_size")
		if ts != null:
			tile_size = float(ts)
		var rs: Variant = mat.get_shader_parameter("rl_noise_strength")
		if rs != null:
			rl_strength = float(rs)
	
	var blend_noise := _sample_rl_world_noise(world_pos, tile_size)
	var noise_variation := (blend_noise - 0.5) * rl_strength
	# step(threshold + noise, source_w) in the shader
	if source_w >= threshold + noise_variation:
		return source_idx
	return target_idx


func _get_rl_noise_image() -> Image:
	var tex : Texture2D = null
	if terrain_system != null and terrain_system.terrain_material != null:
		tex = terrain_system.terrain_material.get_shader_parameter("rl_noise_texture") as Texture2D
	if tex == null:
		return null
	if _cached_rl_noise_image != null and _cached_rl_noise_tex == tex:
		return _cached_rl_noise_image
	_cached_rl_noise_tex = tex
	_cached_rl_noise_image = tex.get_image()
	if _cached_rl_noise_image != null:
		_cached_rl_noise_image.decompress()
	return _cached_rl_noise_image


func _sample_rl_world_noise(world_pos: Vector3, tile_size: float) -> float:
	var img := _get_rl_noise_image()
	if img == null or img.get_width() <= 0 or img.get_height() <= 0:
		return 0.5
	var uv := Vector2(world_pos.x, world_pos.z) * maxf(tile_size, 0.0001)
	uv.x = uv.x - floorf(uv.x)
	uv.y = uv.y - floorf(uv.y)
	if uv.x < 0.0:
		uv.x += 1.0
	if uv.y < 0.0:
		uv.y += 1.0
	# Nearest sampling to match rl_noise_texture filter_nearest.
	var x := clampi(int(floorf(uv.x * float(img.get_width()))), 0, img.get_width() - 1)
	var y := clampi(int(floorf(uv.y * float(img.get_height()))), 0, img.get_height() - 1)
	return img.get_pixel(x, y).r


## Checks if the given texture ID should have grass placed on it.
func _has_grass_for_texture(texture_id: int, force_grass_on: bool) -> bool:
	if force_grass_on:
		return true
	if terrain_system == null:
		return false
	
	# Prefer the PR1 slot-based flags (texture_slots[].has_grass) so toggles actually work.
	var slot_idx := texture_id - 1
	if slot_idx >=  0 and slot_idx < terrain_system.texture_slots.size():
		var slot = terrain_system.texture_slots[slot_idx]
		if slot !=  null and slot.get("has_grass") != null:
			return bool(slot.has_grass)
	
	# Fallback to legacy exported flags.
	if texture_id == 1:
		return bool(terrain_system.tex1_has_grass) if terrain_system.get("tex1_has_grass") != null else true
	if texture_id < 2 or texture_id > 6:
		return false
	
	var has_grass_flags := [
		terrain_system.tex2_has_grass,
		terrain_system.tex3_has_grass,
		terrain_system.tex4_has_grass,
		terrain_system.tex5_has_grass,
		terrain_system.tex6_has_grass
	]
	return bool(has_grass_flags[texture_id - 2])


## Gets the texture scale for the given texture ID.
func _get_texture_scale(texture_id: int) -> float:
	if terrain_system == null:
		return 1.0
	var slot_idx := clampi(texture_id - 1, 0, 255)
	if slot_idx >= 0 and slot_idx < terrain_system.texture_slots.size():
		var slot = terrain_system.texture_slots[slot_idx]
		if slot != null and slot.get("scale") != null:
			return maxf(float(slot.scale), 0.001)
	
	var scales := [
		terrain_system.texture_scale_1,
		terrain_system.texture_scale_2,
		terrain_system.texture_scale_3,
		terrain_system.texture_scale_4,
		terrain_system.texture_scale_5,
		terrain_system.texture_scale_6
	]
	var legacy_idx := clampi(texture_id - 1, 0, 5)
	return scales[legacy_idx]


func _encode_grass_slot_id(texture_id: int) -> float:
	var slot_idx := clampi(texture_id - 1, 0, 255)
	return float(slot_idx) / 255.0


## Samples the terrain texture color at the given world position.
func _sample_terrain_texture_color(world_pos: Vector3, texture_id: int, tex_scale: float) -> Color:
	var terrain_image := _get_terrain_image(texture_id)
	if not terrain_image:
		return Color.WHITE
	
	var uv_x : float = clamp(world_pos.x / ((terrain_system.dimensions.x - 1) * terrain_system.cell_size.x), 0.0, 1.0)
	var uv_y : float = clamp(world_pos.z / ((terrain_system.dimensions.z - 1) * terrain_system.cell_size.y), 0.0, 1.0)
	
	uv_x = abs(fmod(uv_x * tex_scale, 1.0))
	uv_y = abs(fmod(uv_y * tex_scale, 1.0))
	
	var px := int(uv_x * (terrain_image.get_width() - 1))
	var py := int(uv_y * (terrain_image.get_height() - 1))
	var color := terrain_image.get_pixelv(Vector2(px, py))
	if _format_needs_conversion(terrain_image.get_format()):
		return color.srgb_to_linear()
	return color


func _format_needs_conversion(fmt: Image.Format) -> bool:
	match(fmt):
		Image.FORMAT_RGB8, \
		Image.FORMAT_RGBA8, \
		Image.FORMAT_DXT1, \
		Image.FORMAT_DXT3, \
		Image.FORMAT_DXT5, \
		Image.FORMAT_BPTC_RGBA, \
		Image.FORMAT_ETC2_RGB8, \
		Image.FORMAT_ETC2_RGBA8, \
		Image.FORMAT_ETC2_RGB8A1:
			return true
	return false

#endregion

#region grass placement helpers

## Creates a grass instance at the given position with proper transform and color.
func _create_grass_instance(index: int, world_pos: Vector3, a: Vector3, b: Vector3, c: Vector3, texture_id: int, ground_uv: Vector2) -> void:
	var edge1 := b - a
	var edge2 := c - a
	
	var normal : Vector3
	var use_flat := false
	if terrain_system !=  null:
		var flat_val = terrain_system.get("use_flat_normals")
		if flat_val == null:
			flat_val = terrain_system.get("flat_normals")
		use_flat = bool(flat_val) if flat_val != null else false
	if use_flat:
		normal = -Vector3.UP
	else:
		normal = _safe_normalized(edge1.cross(edge2), Vector3.UP)
	
	var instance_basis := _build_grass_basis(normal)
	
	# PR1: no per-blade size variation (kept for PR2/PR4 scope).
	var height_s := 1.0
	var width_s := 1.0
	
	var scaled_basis := instance_basis.scaled(Vector3(width_s, height_s, width_s))
	multimesh.set_instance_transform(index, Transform3D(scaled_basis, world_pos))
	
	var packed_uv := Vector2(clampf(ground_uv.x, 0.0, 1.0), clampf(ground_uv.y, 0.0, 1.0))
	multimesh.set_instance_custom_data(index, Color(packed_uv.x, packed_uv.y, 1.0, _encode_grass_slot_id(texture_id)))


## Hides a grass instance by scaling it to zero.
func _hide_grass_instance(index: int) -> void:
	multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * _HIDDEN_INSTANCE_SCALE), Vector3.ZERO))

#endregion
