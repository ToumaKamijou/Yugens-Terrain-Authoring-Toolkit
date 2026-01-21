extends RefCounted
class_name MarchingSquaresCellFactory

enum CellType {
	PROCEDURAL, AUTHORED
}

@export var type: CellType = CellType.PROCEDURAL

func _init(type_: CellType = CellType.PROCEDURAL) -> void:
	type = type_

func create(y_top_left: float, y_top_right: float, y_bottom_left: float, y_bottom_right: float, merge_threshold: float) -> MarchingSquaresTerrainCell:
	match type:
		CellType.AUTHORED: return MarchingSquaresAuthoredlCell.new(y_top_left, y_top_right, y_bottom_left, y_bottom_right, merge_threshold)
		_: return MarchingSquaresProceduralCell.new(y_top_left, y_top_right, y_bottom_left, y_bottom_right, merge_threshold)
