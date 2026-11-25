@tool
extends MarchingSquaresPrefab
class_name MarchingSquaresPrefabFlat


@export var top_floor : PackedScene:
	set(value):
		top_floor = value
		_prepare("top_floor", top_floor)
