@tool
extends Resource
class_name MarchingSquaresPostProcessEffect


enum Target { TERRAIN, GRASS, BOTH }


@export var enabled : bool = false
@export var effect_name : String = ""
@export var target : Target = Target.TERRAIN
@export var shader : Shader
@export var material_override : Material


func build_runtime_material() -> Material:
	if material_override != null:
		return material_override.duplicate(true)
	if shader != null:
		var material := ShaderMaterial.new()
		material.shader = shader
		return material
	return null


func has_source() -> bool:
	return material_override != null or shader != null
