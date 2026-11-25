@tool
extends MarchingSquaresPrefab
class_name MarchingSquaresPrefabDiagonal


@export var top_floor : PackedScene:
	set(value):
		top_floor = value
		_prepare("top_floor", top_floor)
@export var bottom_floor : PackedScene:
	set(value):
		bottom_floor = value
		_prepare("bottom_floor", bottom_floor, true, false)		
@export var wall_top : PackedScene:
	set(value):
		wall_top = value
		_prepare("wall_top", wall_top)
@export var wall : PackedScene:
	set(value):
		wall = value
		_prepare("wall", wall)
