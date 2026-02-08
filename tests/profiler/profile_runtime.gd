extends Node3D

@onready var camera : Camera3D = $Camera3D
@onready var timer : Node = $FrameTimer
@onready var label : RichTextLabel = $CanvasLayer/Label
@onready var graph = $CanvasLayer/Graph

func _ready() -> void:
	var tween := create_tween()
	tween.tween_property(camera, "global_position", Vector3(30, 10, -600), 30)
	tween.finished.connect(_tween_finished)

func _tween_finished():
	var frames : Array[float] = timer.frame_times
	var sum : float = frames.reduce(func(accum, val): return accum + val, 0)
	label.text = "Average FPS: " + str(frames.size()/sum)
	
	graph.set_frame_times(frames)
	graph.visible = true
	
	timer.queue_free()
	
