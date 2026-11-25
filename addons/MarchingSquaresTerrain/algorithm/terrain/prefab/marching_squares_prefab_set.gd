@tool
class_name MarchingSquaresPrefabSet
extends Resource


@export var flats : Array[MarchingSquaresPrefabFlat]

@export var diagonals : Array[MarchingSquaresPrefabDiagonal]

@export var orthogonals : Array[MarchingSquaresPrefabOrthogonal]

@export var fillers : Array[MarchingSquaresPrefabFiller]

@export var color_map : Texture2D


func has_required_pieces() -> bool:
	return not flats.is_empty() and not diagonals.is_empty() and not orthogonals.is_empty() and not fillers.is_empty()


func get_random_flat() -> MarchingSquaresPrefab:
	return _random(flats)


func get_random_diagonal() -> MarchingSquaresPrefab:
	return _random(diagonals)


func get_random_orthogonal() -> MarchingSquaresPrefab:
	return _random(orthogonals)


func get_random_filler() -> MarchingSquaresPrefab:
	return _random(fillers)


func _random(array: Array) -> MarchingSquaresPrefab:
	if array.size() == 0:
		return null
	var i := randi_range(0, array.size()-1)
	return array[i]
