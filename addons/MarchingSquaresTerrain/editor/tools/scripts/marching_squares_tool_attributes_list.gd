extends Resource
class_name MarchingSquaresToolAttributesList


var brush_type : Dictionary = {
	"name": "brush_type",
	"type": "option",
	"label": "Brush Type",
	"options": ["Round", "Square"],
	"default": 0,
}

var size : Dictionary = {
	"name": "size",
	"type": "slider",
	"label": "Size",
	"range": Vector3(1.0, 50.0, 0.5),
	"default": 15.0,
}

var ease_value : Dictionary = {
	"name": "ease_value",
	"type": "slider",
	"label": "Ease Value",
	"range": Vector3(-5.0, 5.0, 0.1),
	"default": -1.0, # No ease
}

var height : Dictionary = {
	"name": "height",
	"type": "slider",
	"label": "Height",
	"range": Vector3(-50.0, 50.0, 0.1),
	"default": 0.0,
}

var strength : Dictionary = {
	"name": "strength",
	"type": "slider",
	"label": "Strength",
	"range": Vector3(0.1, 10.0, 0.1),
	"default": 3.0,
}

var flatten : Dictionary = {
	"name": "flatten",
	"type": "checkbox",
	"label": "Flatten",
	"default": false,
}

var falloff : Dictionary = {
	"name": "falloff",
	"type": "checkbox",
	"label": "Falloff",
	"default": true,
}

var mask_mode : Dictionary = {
	"name": "mask_mode",
	"type": "checkbox",
	"label": "Mask Mode",
	"default": true,
}

var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")

var material : Dictionary = {
	"name": "material",
	"type": "option",
	"label": "Material",
	"options": vp_tex_names.texture_names,
	"default": 0,
}

var texture_name : Dictionary = {
	"name": "texture_name",
	"type": "text",
	"label": "Texture Name",
	"default": "New name here...",
}

var texture_preset : Dictionary = {
	"name": "texture_preset",
	"type": "preset",
	"label": "Texture Preset",
	"default": null,
}

var quick_paint_selection : Dictionary = {
	"name": "quick_paint_selection",
	"type": "quick_paint",
	"label": "Quick Paint",
	"default": null,
}

var paint_walls : Dictionary = {
	"name": "paint_walls",
	"type": "checkbox",
	"label": "Paint Walls",
	"default": false,
}

var planter : Dictionary = {
	"name": "planter",
	"type": "option",
	"label": "Planter",
	"default": 0,
}

var remove_selection : Dictionary = {
	"name": "remove_selection",
	"type": "checkbox",
	"label": "Remove Selection",
	"default": false,
}

var populate_terrain : Dictionary = {
	"name": "populate_terrain",
	"type": "populate_button",
	"label": "Populate Terrain",
}

var chunk_management : Dictionary = {
	"name": "chunk_management",
	"type": "chunk",
	"label": "Chunk Management",
}

var terrain_settings : Dictionary = {
	"name": "terrain_settings",
	"type": "terrain",
	"label": "Terrain Settings",
}

"""
# Example Attribute Entries
	"name": "",
	"type": "",
	"label": "",
	"range": Vector3(1.0, 50.0, 0.5),
	"options": ["Grass", "Sand", "Rock"],
	"default": 10.0,
"""
