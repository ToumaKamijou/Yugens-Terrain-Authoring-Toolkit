@tool
extends Resource
class_name MarchingSquaresTextureNames


const MAX_TEXTURE_SLOTS := 256

# Vertex painting texture display names (unified for both floor and wall painting)
@export var texture_names : Array[String] = []


static func _default_texture_slot_label(slot_idx: int) -> String:
	if slot_idx == 15:
		return "Void"
	var display_number := slot_idx + 1
	if slot_idx > 15:
		display_number -= 1
	return "Texture %d" % display_number


func _normalize_default_labels() -> void:
	if texture_names.size() != MAX_TEXTURE_SLOTS:
		return
	if texture_names.size() > 0 and (texture_names[0] == "Base Grass" or texture_names[0] == "Texture 1"):
		texture_names[0] = "Texture 1"
	for i in range(1, min(texture_names.size(), 6)):
		var current := str(texture_names[i])
		if current == "Texture %d (g)" % (i + 1) or current == "Texture %d" % (i + 1):
			texture_names[i] = "Texture %d" % (i + 1)
	for i in range(6, texture_names.size()):
		var expected_old := "Texture %d" % (i + 1)
		var expected_new := _default_texture_slot_label(i)
		if str(texture_names[i]) == expected_old or str(texture_names[i]) == expected_new:
			texture_names[i] = expected_new


func ensure_initialized() -> void:
	# NOTE: For Resources loaded from .tres, _init() may not run, so callers should
	# defensively call this before reading texture_names.
	if texture_names.is_empty():
		texture_names = [
			"Texture 1", "Texture 2", "Texture 3", "Texture 4",
			"Texture 5", "Texture 6", "Texture 7", "Texture 8",
			"Texture 9", "Texture 10", "Texture 11", "Texture 12",
			"Texture 13", "Texture 14", "Texture 15", "Void",
		]
	# Extend (do not overwrite existing custom names coming from presets/resources)
	if texture_names.size() < MAX_TEXTURE_SLOTS:
		for i in range(texture_names.size(), MAX_TEXTURE_SLOTS):
			texture_names.append(_default_texture_slot_label(i))
	elif texture_names.size() > MAX_TEXTURE_SLOTS:
		texture_names.resize(MAX_TEXTURE_SLOTS)
	
	# Keep the legacy void slot name stable/obvious.
	var VOID_SLOT := 15
	if texture_names.size() > VOID_SLOT:
		texture_names[VOID_SLOT] = "Void"
	_normalize_default_labels()


func _init() -> void:
	ensure_initialized()
