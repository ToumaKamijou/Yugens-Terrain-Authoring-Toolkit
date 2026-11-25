extends RefCounted
class_name MSTCollisionController


const COLLISION_REFRESH_DEBOUNCE_MSEC := 180
const COLLISION_REBUILDS_PER_EDITOR_FRAME := 1

var terrain
var _refresh_pending := false
var _refresh_deadline_msec : int = 0
var _rebuild_queue : Array[Vector2i] = []
var _rebuild_queue_modes : Dictionary = {}
var in_progress := false
var completed : int = 0
var total : int = 0


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func refresh_chunks(mark_dirty: bool = false, rebuild_from_source: bool = false) -> void:
	if terrain == null or not terrain.is_inside_tree():
		return
	if EngineWrapper.instance.is_editor():
		for chunk_coords: Vector2i in terrain.chunks.keys():
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if not is_instance_valid(chunk):
				continue
			if mark_dirty:
				chunk.mark_dirty()
			_queue_rebuild(chunk_coords, rebuild_from_source)
		in_progress = not _rebuild_queue.is_empty()
		completed = 0
		total = _rebuild_queue.size()
		return
	for chunk_coords: Vector2i in terrain.chunks.keys():
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
		if not is_instance_valid(chunk):
			continue
		if mark_dirty:
			chunk.mark_dirty()
		if rebuild_from_source:
			chunk.force_full_collision_rebuild()
		else:
			chunk.rebuild_collision()
	_refresh_stats()


func _queue_rebuild(chunk_coords: Vector2i, rebuild_from_source: bool) -> void:
	if not _rebuild_queue_modes.has(chunk_coords):
		_rebuild_queue.append(chunk_coords)
		_rebuild_queue_modes[chunk_coords] = rebuild_from_source
	else:
		_rebuild_queue_modes[chunk_coords] = bool(_rebuild_queue_modes[chunk_coords]) or rebuild_from_source


func queue_chunk(chunk_coords: Vector2i, rebuild_from_source: bool = false) -> void:
	if terrain == null or not terrain.is_inside_tree():
		return
	_queue_rebuild(chunk_coords, rebuild_from_source)
	in_progress = true
	total = maxi(total, _rebuild_queue.size())


func process_queue() -> void:
	if _rebuild_queue.is_empty():
		if in_progress:
			in_progress = false
			_refresh_stats()
		return
	in_progress = true
	var rebuild_count := mini(COLLISION_REBUILDS_PER_EDITOR_FRAME, _rebuild_queue.size())
	for _i in range(rebuild_count):
		var chunk_coords : Vector2i = _rebuild_queue.pop_front()
		var rebuild_from_source : bool = bool(_rebuild_queue_modes.get(chunk_coords, false))
		_rebuild_queue_modes.erase(chunk_coords)
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
		if is_instance_valid(chunk):
			if rebuild_from_source:
				chunk.force_full_collision_rebuild()
			else:
				chunk.rebuild_collision()
		completed += 1
	if _rebuild_queue.is_empty():
		in_progress = false
		_refresh_stats()


func schedule_refresh() -> void:
	_refresh_pending = true
	_refresh_deadline_msec = Time.get_ticks_msec() + COLLISION_REFRESH_DEBOUNCE_MSEC
	if not EngineWrapper.instance.is_editor():
		flush_scheduled_refresh()


func process_scheduled_refresh() -> void:
	if _refresh_pending and Time.get_ticks_msec() >= _refresh_deadline_msec:
		flush_scheduled_refresh()


func flush_scheduled_refresh() -> void:
	if not _refresh_pending:
		return
	_refresh_pending = false
	_refresh_deadline_msec = 0
	refresh_chunks(true, false)


func _refresh_stats() -> void:
	if terrain == null:
		return
	var triangle_total := 0
	for chunk: MarchingSquaresTerrainChunk in terrain.chunks.values():
		if is_instance_valid(chunk):
			triangle_total += chunk.get_collision_triangle_count()
	terrain.collision_triangle_count_debug = triangle_total


func clear() -> void:
	_refresh_pending = false
	_refresh_deadline_msec = 0
	_rebuild_queue.clear()
	_rebuild_queue_modes.clear()
	in_progress = false
