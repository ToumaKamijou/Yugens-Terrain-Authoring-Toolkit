@tool
## chunk data for external storage with source data needed to reconstruct terrain at runtime.
class_name MSTChunkData
extends Resource


## Chunk coordinates in the terrain grid
@export var chunk_coords: Vector2i

## Merge mode setting 
@export var merge_mode: int

## Height values as 2D array 
@export var height_map: Array

## Ground texture indices 
@export var ground_texture_idx: PackedByteArray

## Wall texture indices 
@export var wall_texture_idx: PackedByteArray

## Grass mask 
@export var grass_mask: PackedByteArray

## Legacy format (V1.1) for backward compatibility during migration
@export var color_map_0: PackedColorArray
@export var color_map_1: PackedColorArray
@export var wall_color_map_0: PackedColorArray
@export var wall_color_map_1: PackedColorArray
@export var grass_mask_map: PackedColorArray

## Ephemeral data saved for caching but regenerated on load if missing
@export var mesh: Mesh
@export var collision_faces: PackedVector3Array
@export var grass_multimesh: MultiMesh


## Helper to set collision from a ConcavePolygonShape3D
func set_collision_from_shape(shape: ConcavePolygonShape3D) -> void:
	if shape:
		collision_faces = shape.get_faces()


## Helper to create ConcavePolygonShape3D from stored collision data
func get_collision_shape() -> ConcavePolygonShape3D:
	if collision_faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision_faces)
	return shape


## Check if this is V2 compact format (has byte arrays) vs V1 legacy (has color arrays)
func is_v2_format() -> bool:
	return not ground_texture_idx.is_empty()
