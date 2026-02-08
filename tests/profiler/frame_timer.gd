extends Node

var frame_times : Array[float] = []
func _process(delta: float) -> void:
	frame_times.append(delta)
