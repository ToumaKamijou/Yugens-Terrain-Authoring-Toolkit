@tool
extends Resource
class_name MarchingSquaresTextureList


const GRASS_TEXTURE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res")
const GRASS_SPRITE : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png")

@export var terrain_textures : Array[Texture2D] = [
	GRASS_TEXTURE, GRASS_TEXTURE, GRASS_TEXTURE, GRASS_TEXTURE,
	GRASS_TEXTURE, GRASS_TEXTURE, Texture2D.new(), Texture2D.new(),
	Texture2D.new(), Texture2D.new(), Texture2D.new(), Texture2D.new(),
	Texture2D.new(), Texture2D.new(), Texture2D.new(),
]

@export var texture_scales : Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]

@export var grass_sprites : Array[Texture2D] = [
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
]

@export var grass_colors : Array[Color] = [
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"),
	Color("647941ff"), Color("4a7e5dff"), Color("71725dff"),
]

@export var has_grass : Array[bool] = [
	true, true, true, true, true,
]
