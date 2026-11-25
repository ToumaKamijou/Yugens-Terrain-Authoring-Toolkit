extends RefCounted
class_name MSTPostProcessController


var terrain
var _connected_sources : Array[Resource] = []
var _rebuild_in_progress : bool = false
var _source_rebuild_queued : bool = false


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func rebuild(refresh_chunks: bool = true) -> void:
	if terrain == null or _rebuild_in_progress:
		return
	_rebuild_in_progress = true
	_source_rebuild_queued = false
	_disconnect_source_signals()
	if terrain.terrain_material != null:
		terrain.terrain_material.next_pass = _build_chain(MarchingSquaresPostProcessEffect.Target.TERRAIN)
	if terrain.grass_mesh != null and terrain.grass_mesh.material != null:
		terrain.grass_mesh.material.next_pass = _build_chain(MarchingSquaresPostProcessEffect.Target.GRASS)
	if refresh_chunks and terrain.is_inside_tree() and terrain.has_method("refresh_chunk_surface_materials"):
		terrain.refresh_chunk_surface_materials()
	_rebuild_in_progress = false


func _disconnect_source_signals() -> void:
	for source: Resource in _connected_sources:
		if is_instance_valid(source) and source.changed.is_connected(_on_effect_source_changed):
			source.changed.disconnect(_on_effect_source_changed)
	_connected_sources.clear()


func _connect_source_signal(source: Resource) -> void:
	if source == null or not is_instance_valid(source):
		return
	if not source.changed.is_connected(_on_effect_source_changed):
		source.changed.connect(_on_effect_source_changed)
		_connected_sources.append(source)
	if source is ShaderMaterial:
		_connect_source_signal(source.shader)


func _on_effect_source_changed() -> void:
	# Shader code and material inspector edits emit Resource.changed, but do not
	# change the terrain effect resource itself. Defer rebuilding until Godot has
	# finished mutating the shader/material resource to avoid re-entrant updates.
	if _rebuild_in_progress or _source_rebuild_queued or terrain == null:
		return
	_source_rebuild_queued = true
	if terrain.is_inside_tree():
		terrain.call_deferred("_rebuild_post_process_effects")


func _build_chain(target: int) -> Material:
	var head : Material = null
	var tail : Material = null
	for array_name in ["surface_effects", "overlay_effects"]:
		var effects : Array = terrain.get(array_name)
		for effect in effects:
			if not (effect is MarchingSquaresPostProcessEffect) or not effect.enabled or not effect.has_source():
				continue
			if effect.target != MarchingSquaresPostProcessEffect.Target.BOTH and effect.target != target:
				continue
			_connect_source_signal(effect.shader)
			_connect_source_signal(effect.material_override)
			var material : Material = effect.build_runtime_material()
			if material == null:
				continue
			material.next_pass = null
			if head == null:
				head = material
			else:
				tail.next_pass = material
			tail = material
	return head
