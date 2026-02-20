@icon("uid://sx50shr1w2g0")
@tool
extends MarchingSquaresPopulator
class_name MarchingSquaresVegetationContainer


var terrain_system : MarchingSquaresTerrain

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var vegetation_scene : PackedScene = null:
	set(value):
		vegetation_scene = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_size : Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		mesh_size = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_position : Vector3 = Vector3(0.0, 0.0, 0.0):
	set(value):
		mesh_position = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var mesh_rotation : Vector3 = Vector3(0.0, 0.0, 0.0):
	set(value):
		mesh_rotation = value

# Outline related exports
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_outlines : bool = false:
	set(value):
		use_outlines = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var inner_outline_color : Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		inner_outline_color = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var outer_outline_color : Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		outer_outline_color = value

## TODO: Change this to fit the random/selective vegetation planter container classes
@export_storage var planted_chunks : Dictionary = {} 
var populated_chunks : Array[MarchingSquaresTerrainChunk]
var cell_data : Dictionary

var vegetation_scene_root
var extracted_meshes : Array[Dictionary] = []


func setup(redo: bool = true):
	if not terrain_system:
		printerr("SETUP FAILED - no terrain system found for VegetationContainer")
		return


func collect_meshes(node: Node3D, parent_transform: Transform3D):
	if node is MeshInstance3D:
		var local_transform = parent_transform * node.transform
		store_mesh_data(node.mesh, node.material_override, local_transform)
	
	for child in node.get_children():
		collect_meshes(child, parent_transform * node.transform)


func store_mesh_data(mesh: Mesh, material: Material, local_transform: Transform3D):
	if mesh == null:
		return
	
	extracted_meshes.append({
		"mesh": mesh,
		"material": material,
		"local_transform": local_transform
	})
