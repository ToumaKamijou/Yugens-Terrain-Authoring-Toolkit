@tool
extends MarchingSquaresPrefab
class_name MarchingSquaresPrefabOrthogonal


@export var top_floor : PackedScene:
	set(value):
		top_floor = value
		_prepare("top_floor", top_floor)
@export var bottom_floor : PackedScene:
	set(value):
		bottom_floor = value
		_prepare("bottom_floor", bottom_floor, false, false)		
@export var wall_top : PackedScene:
	set(value):
		wall_top = value
		_prepare("wall_top", wall_top)
@export var wall : PackedScene:
	set(value):
		wall = value
		_prepare("wall", wall)
@export var orthogonal_orthogonal_cap_left_floor : PackedScene:
	set(value):
		orthogonal_orthogonal_cap_left_floor = value
		_prepare("orthogonal_orthogonal_cap_left_floor", orthogonal_orthogonal_cap_left_floor)
		
@export var orthogonal_orthogonal_cap_left_wall : PackedScene:
	set(value):
		orthogonal_orthogonal_cap_left_wall = value
		_prepare("orthogonal_orthogonal_cap_left_wall", orthogonal_orthogonal_cap_left_wall)
		
@export var orthogonal_orthogonal_cap_right_floor : PackedScene:
	set(value):
		orthogonal_orthogonal_cap_right_floor = value
		_prepare("orthogonal_orthogonal_cap_right_floor", orthogonal_orthogonal_cap_right_floor)
		
@export var orthogonal_orthogonal_cap_right_wall : PackedScene:
	set(value):
		orthogonal_orthogonal_cap_right_wall = value
		_prepare("orthogonal_orthogonal_cap_right_wall", orthogonal_orthogonal_cap_right_wall)
