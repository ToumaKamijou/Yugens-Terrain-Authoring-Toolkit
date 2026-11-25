@tool
extends MarchingSquaresPrefab
class_name MarchingSquaresPrefabFiller


@export var top_floor : PackedScene:
	set(value):
		top_floor = value
		_prepare("top_floor", top_floor)
@export var top_floor_half : PackedScene:
	set(value):
		top_floor_half = value
		_prepare("top_floor_half", top_floor_half)
@export var bottom_floor : PackedScene:
	set(value):
		bottom_floor = value
		_prepare("bottom_floor", bottom_floor, false, true)		
@export var wall_top : PackedScene:
	set(value):
		wall_top = value
		_prepare("wall_top", wall_top)
@export var wall : PackedScene:
	set(value):
		wall = value
		_prepare("wall", wall)
@export var diagonal_orthogonal_cap_left_floor : PackedScene:
	set(value):
		diagonal_orthogonal_cap_left_floor = value
		_prepare("diagonal_orthogonal_cap_left_floor", diagonal_orthogonal_cap_left_floor)
		
@export var diagonal_orthogonal_cap_left_wall : PackedScene:
	set(value):
		diagonal_orthogonal_cap_left_wall = value
		_prepare("diagonal_orthogonal_cap_left_wall", diagonal_orthogonal_cap_left_wall)
		
@export var diagonal_orthogonal_cap_right_floor : PackedScene:
	set(value):
		diagonal_orthogonal_cap_right_floor = value
		_prepare("diagonal_orthogonal_cap_right_floor", diagonal_orthogonal_cap_right_floor)
		
@export var diagonal_orthogonal_cap_right_wall : PackedScene:
	set(value):
		diagonal_orthogonal_cap_right_wall = value
		_prepare("diagonal_orthogonal_cap_right_wall", diagonal_orthogonal_cap_right_wall)
		
@export var diagonal_diagonal_cap_left_floor : PackedScene:
	set(value):
		diagonal_diagonal_cap_left_floor = value
		_prepare("diagonal_diagonal_cap_left_floor", diagonal_diagonal_cap_left_floor)
		
@export var diagonal_diagonal_cap_left_wall : PackedScene:
	set(value):
		diagonal_diagonal_cap_left_wall = value
		_prepare("diagonal_diagonal_cap_left_wall", diagonal_diagonal_cap_left_wall)
		
@export var diagonal_diagonal_cap_right_floor : PackedScene:
	set(value):
		diagonal_diagonal_cap_right_floor = value
		_prepare("diagonal_diagonal_cap_right_floor", diagonal_diagonal_cap_right_floor)
		
@export var diagonal_diagonal_cap_right_wall : PackedScene:
	set(value):
		diagonal_diagonal_cap_right_wall = value
		_prepare("diagonal_diagonal_cap_right_wall", diagonal_diagonal_cap_right_wall)
		
