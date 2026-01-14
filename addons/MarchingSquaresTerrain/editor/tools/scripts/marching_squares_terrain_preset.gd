@tool
extends Resource
class_name MarchingSquaresTerrainPreset

# Load the names resource
const TextureNames = preload("res://addons/MarchingSquaresTerrain/resources/texture_names.tres")

@export var preset_name: String = "New Preset"

# Store values (no @export - we define them dynamically)
var wall_texture_slot: int = 0
var ground_texture_slot: int = 0

@export_group("Grass")
@export var has_grass: bool = true

# Dynamically define the dropdowns using the shared resource
func _get_property_list() -> Array[Dictionary]:
    var properties: Array[Dictionary] = []
    
    # Wall texture dropdown
    properties.append({
        "name": "wall_texture_slot",
        "type": TYPE_INT,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": ",".join(TextureNames.wall_texture_names),
        "usage": PROPERTY_USAGE_DEFAULT,
    })
    
    # Ground texture dropdown
    properties.append({
        "name": "ground_texture_slot", 
        "type": TYPE_INT,
        "hint": PROPERTY_HINT_ENUM,
        "hint_string": ",".join(TextureNames.texture_names),
        "usage": PROPERTY_USAGE_DEFAULT,
    })
    
    return properties




# @tool
# extends Resource
# class_name MarchingSquaresTerrainPreset


# # Preset identification
# @export var preset_name: String = "New Preset"

# # Wall Configuration (which wall texture slot to use when painting with this preset)
# @export_group("Wall")
# @export_enum("Wall 1", "Wall 2", "Wall 3", "Wall 4", "Wall 5", "Wall 6")
# var wall_texture_slot: int = 0

# # Ground Configuration (which ground texture slot to use when painting with this preset)
# @export_group("Ground")
# @export_enum("Base Grass", "Texture 2 (g)", "Texture 3 (g)", "Texture 4 (g)",
#              "Texture 5 (g)", "Texture 6 (g)", "Texture 7", "Texture 8",
#              "Texture 9", "Texture 10", "Texture 11", "Texture 12",
#              "Texture 13", "Texture 14", "Texture 15", "Void")
# var ground_texture_slot: int = 0

# # Grass Configuration
# @export_group("Grass")
# @export var has_grass: bool = true
