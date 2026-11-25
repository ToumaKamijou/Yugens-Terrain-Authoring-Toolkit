@tool
extends Resource
class_name MarchingSquaresTextureSlot


# Whether this slot is shown in the UI/selectors.
@export var active : bool = true

@export var texture : Texture2D
@export var scale : float = 1.0
@export var albedo : Color = Color(1, 1, 1, 0)

# Grass system (only used by first few slots currently)
@export var grass_texture : Texture2D
@export var has_grass : bool = false
