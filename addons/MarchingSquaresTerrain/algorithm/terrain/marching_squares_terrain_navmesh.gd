@tool
extends NavigationRegion3D
class_name MarchingSquaresTerrainNavMesh


## Generated navigation output is cleared here; the terrain's painted
## permission mask is intentionally preserved.
@export_tool_button("Clear Baked NavMesh") var clear_baked_navmesh_button = func():
	clear_baked_navmesh()


func clear_baked_navmesh() -> void:
	navigation_mesh = null
	var terrain := get_parent() as MarchingSquaresTerrain
	if terrain != null and terrain.has_method("_clear_nav_debug_mesh"):
		terrain._clear_nav_debug_mesh()
	if EngineWrapper.instance != null and EngineWrapper.instance.is_editor():
		EngineWrapper.instance.mark_scene_as_unsaved()
