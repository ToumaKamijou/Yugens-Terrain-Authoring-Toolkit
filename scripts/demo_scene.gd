extends Node3D


@onready var world_environment : WorldEnvironment = $SubViewportContainer/SubViewport/WorldEnvironment


func _ready() -> void:
	world_environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	RenderingServer.set_default_clear_color(Color.BLACK)
