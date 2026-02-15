@icon("uid://sx50shr1w2g0")
@tool
extends MarchingSquaresPopulator
class_name MarchingSquaresVegetationPlanter


var terrain_system : MarchingSquaresTerrain

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var vegetation_mesh : Variant = null:
	set(value):
		if value is Mesh:
			vegetation_mesh = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_size : Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		mesh_size = value

var populated_chunks : Array[MarchingSquaresTerrainChunk]


func setup(redo: bool = true):
	if not terrain_system:
		printerr("SETUP FAILED - no terrain system found for VegetationPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = populated_chunks.size() * ((terrain_system.dimensions.x-1) * (terrain_system.dimensions.z-1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions)
	if vegetation_mesh:
		multimesh.mesh = vegetation_mesh
	else:
		multimesh.mesh = BoxMesh.new() # Create a temporary box
	multimesh.mesh.size = mesh_size
	
	cast_shadow = SHADOW_CASTING_SETTING_ON


func rebuild_cell_data() -> void:
	pass
