extends Node2D

@onready var test: MarchingSquaresGenerationBenchmarkTests = $Test
@onready var label: RichTextLabel = $Label

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	test.disable_non_threaded = true
	test.test_done.connect(_show_times)
	
	
func _show_times(t: float, nt: float) -> void:
	label.text = "Threaded time: " + str(t) + "ms \n" + "Non-threaded time: " + str(nt) + "ms"
