@tool
extends Resource
class_name MSTextureLibrary


@export_category("MarchingSquares")
@export var max_slots : int = 256
@export var albedo_textures : Array[Texture2D] = []
@export var normal_textures : Array[Texture2D] = []
@export var grass_textures : Array[Texture2D] = []
@export var dense_slot_lookup : PackedInt32Array = PackedInt32Array()


func _init():
	ensure_length()


func ensure_length():
	if albedo_textures.size() !=  max_slots:
		albedo_textures.resize(max_slots)
	if normal_textures.size() !=  max_slots:
		normal_textures.resize(max_slots)
	if grass_textures.size() !=  max_slots:
		grass_textures.resize(max_slots)
	if dense_slot_lookup.size() != max_slots:
		dense_slot_lookup.resize(max_slots)
		for i in range(max_slots):
			dense_slot_lookup[i] = -1


func get_slot_albedo(idx: int) -> Texture2D:
	return albedo_textures[idx] if idx >= 0 and idx < max_slots else null


func set_slot_albedo(idx: int, tex: Texture2D) -> void:
	if idx >= 0 and idx < max_slots:
		albedo_textures[idx] = tex
