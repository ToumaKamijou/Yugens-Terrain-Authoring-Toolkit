@icon("res://addons/MarchingSquaresTerrain/editor/icons/3D_planters_icon.png")
@tool
extends MarchingSquaresPopulator
class_name MarchingSquaresFlowerPlanter


var terrain_system : MarchingSquaresTerrain
var populated_chunks : Array[MarchingSquaresTerrainChunk]

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_mesh : QuadMesh = null:
	set(value):
		flower_mesh = value
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var color_gradient : GradientTexture1D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/example_flower_gradient.tres"):
	set(value):
		color_gradient = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		if value != null:
			flower_mat.set_shader_parameter("use_custom_color", true)
		else:
			flower_mat.set_shader_parameter("use_custom_color", false)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var should_billboard : bool = true:
	set(value):
		should_billboard = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		if value == true:
			flower_mesh.orientation = PlaneMesh.FACE_Z
			flower_mat.set_shader_parameter("should_billboard", true)
		else:
			flower_mesh.orientation = PlaneMesh.FACE_Y
			flower_mat.set_shader_parameter("should_billboard", false)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var flower_sprite : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/round_leaf.png"):
	set(value):
		flower_sprite = value
		var flower_mat := flower_mesh.material as ShaderMaterial
		flower_mat.set_shader_parameter("flower_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var sprite_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		sprite_size = value


func setup(redo: bool = true):
	if not terrain_system:
		printerr("ERROR: SETUP FAILED - no terrain system found for FlowerPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = populated_chunks.size() * ((terrain_system.dimensions.x-1) * (terrain_system.dimensions.z-1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions)
	if flower_mesh:
		multimesh.mesh = flower_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = sprite_size
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF


func _init() -> void:
	var fallback_flower_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/mst_grass_mesh.tres")
	if not flower_mesh:
		flower_mesh = fallback_flower_mesh.duplicate(true)
		flower_mesh.material = fallback_flower_mesh.material.duplicate(true)
