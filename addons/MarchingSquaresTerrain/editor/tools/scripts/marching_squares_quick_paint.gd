@tool
extends Resource
class_name MarchingSquaresQuickPaint


const TEXTURE_NAMES = preload("res://addons/MarchingSquaresTerrain/resources/texture_names.tres")

@export var paint_name : String = "New Paint"

# Store values (no @export - we define them dynamically)
var wall_texture_slot : int = 0
var ground_texture_slot : int = 0

@export_group("Textures")
@export var has_grass : bool = true


# Dynamically define the dropdowns using the shared resource (unified 16-texture system)
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	# Wall texture dropdown (uses unified texture names - any of 16 textures can be used for walls)
	properties.append({
		"name": "wall_texture_slot",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(TEXTURE_NAMES.texture_names),
		"usage": PROPERTY_USAGE_DEFAULT,
	})

	# Ground texture dropdown (uses unified texture names)
	properties.append({
		"name": "ground_texture_slot",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(TEXTURE_NAMES.texture_names),
		"usage": PROPERTY_USAGE_DEFAULT,
	})

	return properties
