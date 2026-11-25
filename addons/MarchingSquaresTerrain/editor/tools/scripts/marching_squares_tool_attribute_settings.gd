extends Resource
class_name MarchingSquaresToolAttributeSettings


# General brush attributes
@export var brush_type : bool = false
@export var size : bool = false
@export var ease_value : bool = false
@export var height : bool = false
@export var strength : bool = false
@export var flatten : bool = false
@export var falloff : bool = false

# Vertex Paint only: hard vs dithered edge (does not lerp colors).
@export var vp_falloff_mode : bool = false

# Brush specific attributes
@export var curve3d_mode : bool = false
@export var mask_mode : bool = false
@export var material : bool = false
@export var texture_name : bool = false

# Vertex painting-related special attributes
@export var texture_preset : bool = false
@export var quick_paint_selection : bool = false
@export var paint_walls : bool = false

# Populate-related special attributes
@export var populator : bool = false
@export var remove_selection : bool = false

# Non-brush attributes
@export var chunk_management : bool = false
@export var terrain_settings : bool = false
@export var heightmap : bool = false
