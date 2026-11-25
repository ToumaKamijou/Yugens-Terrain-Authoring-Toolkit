@tool
extends RefCounted
class_name MarchingSquaresTextureImportHelper


const _TEXTURE_EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr"]

var max_texture_slots : int
var default_preset_dir : String
var texture_slot_script
var texture_library_script
var names_template : MarchingSquaresTextureNames


func _init(
	p_max_texture_slots: int,
	p_default_preset_dir: String,
	p_texture_slot_script,
	p_texture_library_script,
	p_names_template: MarchingSquaresTextureNames
) -> void:
	max_texture_slots = p_max_texture_slots
	default_preset_dir = p_default_preset_dir
	texture_slot_script = p_texture_slot_script
	texture_library_script = p_texture_library_script
	names_template = p_names_template


func import_to_terrain(
	terrain,
	preset_name: String,
	raw_save_dir: String,
	albedo_dir: String,
	normal_dir: String,
	compute_slot_albedo_color: Callable,
	sync_slot_legacy_fields: Callable,
	save_resource_if_external: Callable
) -> Dictionary:
	if terrain == null:
		return {"ok": false, "error": "[MST] No terrain selected for texture import."}
	
	var preset_slug := preset_name.strip_edges().to_lower().to_snake_case()
	if preset_name.strip_edges().is_empty() or preset_slug.is_empty():
		return {"ok": false, "error": "[MST] Texture import requires a preset name."}
	
	var clean_albedo_dir := albedo_dir.strip_edges()
	var clean_normal_dir := normal_dir.strip_edges()
	if clean_albedo_dir.is_empty() or clean_normal_dir.is_empty():
		return {"ok": false, "error": "[MST] Choose both an Albedo or Diffuse Maps folder and a Normal Maps folder."}
	
	var pairs := build_texture_import_pairs(clean_albedo_dir, clean_normal_dir)
	if pairs.is_empty():
		return {"ok": false, "error": "[MST] No matching albedo/diffuse and normal texture pairs were found."}
	
	var save_dir := normalize_texture_import_save_dir(raw_save_dir)
	var preset_folder := save_dir.path_join(preset_slug)
	var preset_folder_abs := ProjectSettings.globalize_path(preset_folder)
	if not DirAccess.dir_exists_absolute(preset_folder_abs):
		DirAccess.make_dir_recursive_absolute(preset_folder_abs)
	
	var preset_path := preset_folder.path_join(preset_slug + ".tres")
	var texture_names_path := preset_folder.path_join("texture_names.tres")
	var texture_library_path := preset_folder.path_join("texture_library.tres")
	
	var names_res : MarchingSquaresTextureNames = names_template.duplicate(true)
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(names_res)
	if ResourceSaver.save(names_res, texture_names_path) != OK:
		return {"ok": false, "error": "[MST] Failed to save texture names resource for import."}
	var saved_names := ResourceLoader.load(texture_names_path) as MarchingSquaresTextureNames
	if saved_names != null:
		names_res = saved_names
	
	var texture_library : Resource = texture_library_script.new()
	if texture_library.has_method("ensure_length"):
		texture_library.ensure_length()
	if ResourceSaver.save(texture_library, texture_library_path) != OK:
		return {"ok": false, "error": "[MST] Failed to save texture library for import."}
	var saved_library := ResourceLoader.load(texture_library_path)
	if saved_library != null:
		texture_library = saved_library
	if texture_library != null and texture_library.has_method("ensure_length"):
		texture_library.ensure_length()
	
	var imported_preset := MarchingSquaresTexturePreset.new()
	imported_preset.preset_name = preset_name.strip_edges()
	imported_preset.new_tex_names = names_res
	imported_preset.texture_library = texture_library
	if terrain.current_texture_preset != null:
		imported_preset.apply_vertex_painter_settings = bool(terrain.current_texture_preset.apply_vertex_painter_settings)
		imported_preset.apply_grass_settings = bool(terrain.current_texture_preset.apply_grass_settings)
	if ResourceSaver.save(imported_preset, preset_path) != OK:
		return {"ok": false, "error": "[MST] Failed to save imported texture preset."}
	var saved_preset := ResourceLoader.load(preset_path) as MarchingSquaresTexturePreset
	if saved_preset != null:
		imported_preset = saved_preset
	if imported_preset.texture_library == null:
		imported_preset.texture_library = texture_library
	if imported_preset.new_tex_names == null:
		imported_preset.new_tex_names = names_res
	
	terrain.set("current_texture_preset", imported_preset)
	terrain.set("texture_library", texture_library)
	_reset_terrain_texture_state(terrain, texture_library)
	
	var occupied_slots := {}
	var explicit_pairs : Array = []
	var auto_pairs : Array = []
	for pair in pairs:
		var forced_slot := int(pair.get("slot_idx", -1))
		if forced_slot >= 0 and forced_slot < max_texture_slots and forced_slot != 15:
			if not occupied_slots.has(forced_slot):
				explicit_pairs.append(pair)
				occupied_slots[forced_slot] = true
		else:
			auto_pairs.append(pair)
	
	var assigned := 0
	var highest_slot := -1
	for pair in explicit_pairs:
		var slot_idx := int(pair["slot_idx"])
		if assign_texture_import_pair(
			terrain,
			texture_library,
			names_res,
			slot_idx,
			pair,
			compute_slot_albedo_color,
			sync_slot_legacy_fields
		):
			assigned += 1
			highest_slot = maxi(highest_slot, slot_idx)
	
	var next_auto_slot := 0
	for pair in auto_pairs:
		next_auto_slot = next_texture_import_slot(next_auto_slot, occupied_slots)
		if next_auto_slot < 0:
			break
		if assign_texture_import_pair(
			terrain,
			texture_library,
			names_res,
			next_auto_slot,
			pair,
			compute_slot_albedo_color,
			sync_slot_legacy_fields
		):
			occupied_slots[next_auto_slot] = true
			assigned += 1
			highest_slot = maxi(highest_slot, next_auto_slot)
		next_auto_slot += 1
	
	if assigned <= 0:
		return {"ok": false, "error": "[MST] Texture import found files but could not assign any valid pairs."}
	
	terrain.visible_texture_slot_count = clampi(maxi(highest_slot + 1, 6), 6, max_texture_slots)
	if save_resource_if_external.is_valid():
		save_resource_if_external.call(texture_library)
		save_resource_if_external.call(names_res)
	
	return {
		"ok": true,
		"preset": imported_preset,
		"texture_library": texture_library,
		"names_res": names_res,
		"assigned": assigned,
	}


func normalize_texture_import_save_dir(raw_dir: String) -> String:
	var save_dir := raw_dir.strip_edges().replace("\\", "/")
	if save_dir.is_empty():
		save_dir = default_preset_dir
	if not save_dir.begins_with("res://"):
		save_dir = default_preset_dir
	if not save_dir.ends_with("/"):
		save_dir += "/"
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists(save_dir):
		dir.make_dir_recursive(save_dir)
	return save_dir


func assign_texture_import_pair(
	terrain,
	texture_library,
	names_res: MarchingSquaresTextureNames,
	slot_idx: int,
	pair: Dictionary,
	compute_slot_albedo_color: Callable,
	sync_slot_legacy_fields: Callable
) -> bool:
	if slot_idx < 0 or slot_idx >= max_texture_slots or slot_idx == 15:
		return false
	var albedo_tex := ResourceLoader.load(str(pair["albedo"]), "Texture2D") as Texture2D
	var normal_tex := ResourceLoader.load(str(pair["normal"]), "Texture2D") as Texture2D
	if albedo_tex == null or normal_tex == null:
		push_warning("[MST] Skipping unreadable texture pair: " + str(pair))
		return false
	
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = texture_slot_script.new()
	terrain.texture_slots[slot_idx].active = true
	terrain.texture_slots[slot_idx].texture = albedo_tex
	terrain.texture_slots[slot_idx].grass_texture = null
	terrain.texture_slots[slot_idx].has_grass = (slot_idx == 0)
	terrain.texture_slots[slot_idx].scale = 1.0
	
	if compute_slot_albedo_color.is_valid():
		terrain.texture_slots[slot_idx].albedo = compute_slot_albedo_color.call(terrain, albedo_tex)
	if sync_slot_legacy_fields.is_valid():
		sync_slot_legacy_fields.call(terrain, slot_idx)
	if texture_library != null:
		if slot_idx < texture_library.albedo_textures.size():
			texture_library.albedo_textures[slot_idx] = albedo_tex
		if slot_idx < texture_library.normal_textures.size():
			texture_library.normal_textures[slot_idx] = normal_tex
	if names_res != null:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(names_res)
		var names := names_res.texture_names
		if slot_idx < names.size():
			var display_name := str(pair.get("display_name", "")).strip_edges()
			if not display_name.is_empty():
				names[slot_idx] = display_name
			names_res.texture_names = names
	
	return true


func build_texture_import_pairs(albedo_dir: String, normal_dir: String) -> Array:
	var albedo_files := list_texture_import_files(albedo_dir)
	var normal_files := list_texture_import_files(normal_dir)
	var normal_by_key := {}
	for path in normal_files:
		var normal_info := texture_import_file_info(path, true)
		var normal_key := str(normal_info["key"])
		if not normal_by_key.has(normal_key):
			normal_by_key[normal_key] = path
	
	var pairs : Array = []
	for albedo_path in albedo_files:
		var albedo_info := texture_import_file_info(albedo_path, false)
		var key := str(albedo_info["key"])
		if not normal_by_key.has(key):
			continue
		
		pairs.append({
			"key": key,
			"albedo": albedo_path,
			"normal": normal_by_key[key],
			"slot_idx": int(albedo_info["slot_idx"]),
			"display_name": str(albedo_info["display_name"]),
		})
	
	pairs.sort_custom(func(a, b):
		var a_slot := int(a["slot_idx"])
		var b_slot := int(b["slot_idx"])
		if a_slot >= 0 and b_slot >= 0:
			return a_slot < b_slot
		if a_slot >= 0:
			return true
		if b_slot >= 0:
			return false
		return str(a["key"]) < str(b["key"])
	)
	
	return pairs


func list_texture_import_files(dir_path: String) -> Array:
	var out : Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[MST] Directory not found: " + dir_path)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			for ext in _TEXTURE_EXTENSIONS:
				if lower.ends_with(ext):
					out.append(dir_path.path_join(name))
					break
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func texture_import_file_info(path: String, is_normal: bool) -> Dictionary:
	var base := path.get_file().get_basename().strip_edges()
	var slot_info := extract_texture_import_slot_prefix(base)
	var raw_name := str(slot_info["name"])
	var suffixes := texture_import_normal_suffixes() if is_normal else texture_import_albedo_suffixes()
	var key_name := strip_texture_import_suffix(raw_name.to_lower(), suffixes)
	var display_name := strip_texture_import_suffix_ignore_case(raw_name, suffixes)
	display_name = collapse_texture_import_spaces(display_name.replace("_", " ").replace("-", " ").strip_edges())
	return {
		"slot_idx": int(slot_info["slot_idx"]),
		"key": collapse_texture_import_spaces(key_name.replace("_", " ").replace("-", " ").strip_edges()),
		"display_name": display_name,
	}


func extract_texture_import_slot_prefix(name: String) -> Dictionary:
	var idx := 0
	while idx < name.length() and texture_import_is_ascii_digit(name.unicode_at(idx)):
		idx += 1
	if idx <= 0 or idx >= name.length():
		return {"slot_idx": -1, "name": name}
	var sep := name[idx]
	if sep != " " and sep != "_" and sep != "-":
		return {"slot_idx": -1, "name": name}
	var slot_number := int(name.substr(0, idx))
	if slot_number < 1 or slot_number > max_texture_slots:
		return {"slot_idx": -1, "name": name}
	var raw_rest := name.substr(idx + 1).strip_edges()
	while raw_rest.begins_with("_") or raw_rest.begins_with("-"):
		raw_rest = raw_rest.substr(1).strip_edges()
	if raw_rest.is_empty():
		raw_rest = name
	return {"slot_idx": slot_number - 1, "name": raw_rest}


func texture_import_is_ascii_digit(codepoint: int) -> bool:
	return codepoint >= 48 and codepoint <= 57


func texture_import_albedo_suffixes() -> Array:
	return [
		"_albedo", "-albedo", " albedo", "-a",
		"_diffuse", "-diffuse", " diffuse", "-d",
		"_basecolor", "-basecolor",
		"_base_color", "-base_color",
		"_color", "-color"
	]


func texture_import_normal_suffixes() -> Array:
	return ["_normal", "-normal", " normal", "_nrm", "-nrm", "_nor", "-nor", "_n", "-n"]


func strip_texture_import_suffix_ignore_case(name: String, suffixes: Array) -> String:
	var lower_name := name.to_lower()
	for suffix in suffixes:
		if lower_name.ends_with(str(suffix)):
			return name.substr(0, name.length() - str(suffix).length())
	return name


func strip_texture_import_suffix(name: String, suffixes: Array) -> String:
	for suffix in suffixes:
		var suffix_str := str(suffix)
		if name.ends_with(suffix_str):
			return name.substr(0, name.length() - suffix_str.length())
	return name


func collapse_texture_import_spaces(value: String) -> String:
	var s := value
	while s.find("  ") != -1:
		s = s.replace("  ", " ")
	return s.strip_edges()


func next_texture_import_slot(start_slot: int, occupied_slots: Dictionary) -> int:
	for slot_idx in range(maxi(start_slot, 0), max_texture_slots):
		if slot_idx == 15:
			continue
		if occupied_slots.has(slot_idx):
			continue
		return slot_idx
	return -1


func _reset_terrain_texture_state(terrain, texture_library) -> void:
	var slots: Array = terrain.texture_slots
	for slot_idx in range(max_texture_slots):
		if slots[slot_idx] == null:
			slots[slot_idx] = texture_slot_script.new()
		slots[slot_idx].texture = null
		slots[slot_idx].grass_texture = null
		slots[slot_idx].active = false
		slots[slot_idx].scale = 1.0
		slots[slot_idx].has_grass = (slot_idx == 0)
		if slot_idx < 15:
			terrain.set("texture_%d" % (slot_idx + 1), null)
			terrain.set("texture_scale_%d" % (slot_idx + 1), 1.0)
		if texture_library != null:
			if slot_idx < texture_library.albedo_textures.size():
				texture_library.albedo_textures[slot_idx] = null
			if slot_idx < texture_library.normal_textures.size():
				texture_library.normal_textures[slot_idx] = null
			if slot_idx < texture_library.grass_textures.size():
				texture_library.grass_textures[slot_idx] = null
