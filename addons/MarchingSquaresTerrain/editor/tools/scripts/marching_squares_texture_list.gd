@tool
extends Resource
class_name MarchingSquaresTextureList


const MAX_TEXTURE_SLOTS := 256
const GRASS_SPRITE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png")

@export var terrain_textures : Array[Texture2D] = [
	null, null, null, null,
	null, null, null, null,
	null, null, null, null,
	null, null, null,
]

@export var texture_scales : Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]

# Slot-based grass sprites (0..255). Older presets may have only 6 entries.
@export var grass_sprites : Array[Texture2D] = []

@export var grass_colors : Array[Color] = [
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex1
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex2
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex3
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex4
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex5
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex6
]

# Slot-based has-grass flags (0..255).
# Older presets may have only 5 entries (textures 2-6) or 6 entries (textures 1-6).
@export var has_grass : Array[bool] = []


func _init() -> void:
	_ensure_grass_arrays()


func _ensure_grass_arrays() -> void:
	# Grass sprites
	var prev := grass_sprites.duplicate()
	if grass_sprites.size() !=  MAX_TEXTURE_SLOTS:
		grass_sprites.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if i < prev.size() and prev[i] is Texture2D:
				grass_sprites[i] = prev[i]
			elif prev.is_empty() and i < 6:
				grass_sprites[i] = GRASS_SPRITE
			else:
				grass_sprites[i] = null
	
	# Has grass
	if has_grass.size() == 5:
		# old format: textures 2-6 only
		var prev_h := has_grass.duplicate()
		has_grass.resize(MAX_TEXTURE_SLOTS)
		has_grass[0] = true
		for i in range(1, 6):
			has_grass[i] = bool(prev_h[i - 1])
		for i in range(6, MAX_TEXTURE_SLOTS):
			has_grass[i] = false
	elif has_grass.size() == 6:
		# old format: textures 1-6
		var prev_h6 := has_grass.duplicate()
		has_grass.resize(MAX_TEXTURE_SLOTS)
		for i in range(6):
			has_grass[i] = bool(prev_h6[i])
		for i in range(6, MAX_TEXTURE_SLOTS):
			has_grass[i] = false
	elif has_grass.size() !=  MAX_TEXTURE_SLOTS:
		has_grass.resize(MAX_TEXTURE_SLOTS)
		# default: only Texture 1 starts with grass enabled
		for i in range(MAX_TEXTURE_SLOTS):
			has_grass[i] = (i == 0)
	
	# Older placeholder presets expanded every slot to the default grass sprite.
	# Treat disabled slots as empty so they do not masquerade as 256 meaningful slots.
	for i in range(6, MAX_TEXTURE_SLOTS):
		if not bool(has_grass[i]) and grass_sprites[i] == GRASS_SPRITE:
			grass_sprites[i] = null
