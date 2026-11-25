extends EditorNode3DGizmoPlugin
class_name MarchingSquaresTerrainGizmoPlugin


func _init():
	create_material("brush", Color(1, 1, 1), false, true)
	create_material("brush_pattern", Color(0.7, 0.7, 0.7), false, true)
	create_material("removechunk", Color(1,0,0), false, true)
	create_material("addchunk", Color(0,1,0), false, true)
	create_material("highlightchunk", Color(0, 0, 1), false, true)
	create_material("navmesh_permission", Color(0.12, 0.55, 1.0, 0.55), false, false)
	create_handle_material("handles")


var _chunk_gizmos : Dictionary[Node, MarchingSquaresTerrainChunkGizmo] = {}
var _terrain_gizmos : Dictionary[Node, MarchingSquaresTerrainGizmo] = {}


func _create_gizmo(node: Node):
	if node is MarchingSquaresTerrainChunk:
		if not _chunk_gizmos.has(node):
			node.tree_exited.connect(func(): _chunk_gizmos.erase(node), CONNECT_ONE_SHOT)
			var ret = MarchingSquaresTerrainChunkGizmo.new()
			_chunk_gizmos[node] = ret
			return ret
	elif node is MarchingSquaresTerrain:
		if not _terrain_gizmos.has(node):
			node.tree_exited.connect(func(): _terrain_gizmos.erase(node), CONNECT_ONE_SHOT)
			var ret = MarchingSquaresTerrainGizmo.new()
			_terrain_gizmos[node] = ret
			return ret
	return null


func trigger_redraw(node: Node) -> void:
	if node is MarchingSquaresTerrainChunk and _chunk_gizmos.has(node):
		_chunk_gizmos[node]._redraw()
	elif node is MarchingSquaresTerrain and _terrain_gizmos.has(node):
		_terrain_gizmos[node]._redraw()


func clear() -> void:
	for k in _chunk_gizmos:
		_chunk_gizmos[k].clear()
	for k in _terrain_gizmos:
		_terrain_gizmos[k].clear()


func _get_gizmo_name() -> String:
	return "Marching Squares Terrain"
