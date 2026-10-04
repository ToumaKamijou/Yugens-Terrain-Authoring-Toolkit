@tool
extends AcceptDialog
class_name MarchingSquaresTextureEditWindow


signal blend_mode_changed(slot_idx: int, blend_mode: int)
signal color_value_changed(slot_idx: int, palette_idx: int, color: Color)
signal color_picker_closed(slot_idx: int)
signal weight_value_changed(slot_idx: int, palette_idx: int, value: float)
signal weight_drag_finished(slot_idx: int)
signal remove_color_requested(slot_idx: int, palette_idx: int)
signal add_color_requested(slot_idx: int)

const SINGLE_COLOR_CONTAINER := preload("uid://cf8710euu81ol")
const MSTextureLibraryScript := preload("uid://iyvy0c8carkd")

var available_preview_sources : Array = []
var current_preview_index : int = 0
var _material_preview_cache : Dictionary = {}
var _color_slot_idx : int = -1

# Viewport nodes
@export var texture_preview : TextureRect
@export var no_preview_label : Label
@export var prev_cam_button : Button
@export var next_cam_button : Button

# Texture settings nodes
@export var texture_name_edit : LineEdit
@export var albedo_picker : EditorResourcePicker
@export var normal_picker : EditorResourcePicker
@export var texture_scale_slider : EditorSpinSlider

# Color settings nodes
@export var blend_mode_button : OptionButton

@export var colors_container : VBoxContainer
@export var add_color_button : Button

# Advanced settings nodes
@export var has_grass_check_box : CheckBox
@export var grass_texture_picker : EditorResourcePicker

@export var floor_noise_attributes : VBoxContainer
@export var floor_noise_check_box : CheckBox
@export var floor_strength_slider : EditorSpinSlider
@export var floor_scale_slider : EditorSpinSlider

@export var wall_noise_attributes : VBoxContainer
@export var wall_noise_check_box : CheckBox
@export var wall_strength_slider : EditorSpinSlider
@export var wall_scale_slider : EditorSpinSlider

@export var wetness_attributes : VBoxContainer
@export var wetness_check_box : CheckBox
@export var wetness_mode_button : OptionButton
@export var wetness_terrain_slider : EditorSpinSlider
@export var wetness_grass_slider : EditorSpinSlider


func rebuild_color_rows(slot_idx: int, blend_mode: int, slot_indices: Array, palette_colors: Array, palette_weights: Array) -> void:
	_color_slot_idx = slot_idx
	blend_mode_button.selected = blend_mode
	for child in colors_container.get_children():
		colors_container.remove_child(child)
		child.queue_free()
	for ci in range(slot_indices.size()):
		var row := SINGLE_COLOR_CONTAINER.instantiate() as MSTSingleColorContainer
		colors_container.add_child(row)
		var palette_idx := int(slot_indices[ci])
		row.color_label.text = str(ci + 1)
		if palette_idx >= 0 and palette_idx < palette_colors.size():
			row.color_picker.color = palette_colors[palette_idx]
		row.color_picker.color_changed.connect(func(new_color, s = slot_idx, pidx = palette_idx):
			emit_signal("color_value_changed", s, pidx, new_color)
		)
		row.color_picker.popup_closed.connect(func(s = slot_idx):
			emit_signal("color_picker_closed", s)
		)
		if slot_indices.size() > 1:
			row.color_weight_h_box.visible = true
			row.weight_percentage_label.visible = true
			row.weight_slider.visible = true
			row.remove_color_button.visible = true
			var weight := clampf(float(palette_weights[palette_idx]) if palette_idx >= 0 and palette_idx < palette_weights.size() else 100.0, 0.0, 100.0)
			row.weight_percentage_label.text = str(int(round(weight))) + "%"
			row.weight_slider.value = weight
			row.weight_slider.value_changed.connect(func(val, s = slot_idx, pidx = palette_idx, label = row.weight_percentage_label):
				label.text = str(int(round(float(val)))) + "%"
				emit_signal("weight_value_changed", s, pidx, float(val))
			)
			row.weight_slider.drag_ended.connect(func(_ended, s = slot_idx):
				emit_signal("weight_drag_finished", s)
			)
		else:
			row.color_weight_h_box.size_flags_horizontal = Control.SIZE_FILL
			row.color_weight_h_box.visible = true
			row.weight_percentage_label.visible = false
			row.weight_slider.visible = false
			row.remove_color_button.visible = true
		row.remove_color_button.pressed.connect(func(s = slot_idx, pidx = palette_idx):
			emit_signal("remove_color_requested", s, pidx)
		)


# Synchronize every visible weight control after one weight is normalized against
# the others. Signals are blocked so these programmatic changes do not normalize
# the same weights recursively.
func update_color_weight_rows(slot_idx: int, slot_indices: Array, palette_weights: Array) -> void:
	if slot_idx != _color_slot_idx:
		return
	var rows := colors_container.get_children()
	for row_idx in range(mini(rows.size(), slot_indices.size())):
		var row := rows[row_idx] as MSTSingleColorContainer
		if row == null:
			continue
		var palette_idx := int(slot_indices[row_idx])
		var weight := clampf(
			float(palette_weights[palette_idx]) if palette_idx >= 0 and palette_idx < palette_weights.size() else 100.0,
			0.0,
			100.0
		)
		row.weight_percentage_label.text = str(int(round(weight))) + "%"
		row.weight_slider.set_block_signals(true)
		row.weight_slider.value = weight
		row.weight_slider.set_block_signals(false)


func connect_color_events_once() -> void:
	if has_meta("_mst_modal_color_events_connected") and bool(get_meta("_mst_modal_color_events_connected")):
		return
	blend_mode_button.item_selected.connect(func(idx):
		emit_signal("blend_mode_changed", _color_slot_idx, idx)
	)
	add_color_button.pressed.connect(func():
		emit_signal("add_color_requested", _color_slot_idx)
	)
	set_meta("_mst_modal_color_events_connected", true)


func reset_preview_sources() -> void:
	available_preview_sources.clear()
	current_preview_index = 0
	texture_preview.texture = null
	_set_no_preview_label_visible(false)


func add_material_preview_source(slot_idx: int, terrain) -> void:
	available_preview_sources.append({
		"type": "material_preview",
		"terrain": terrain,
		"slot_idx": slot_idx,
	})


func add_viewport_preview_source(viewport) -> void:
	available_preview_sources.append({
		"type": "viewport",
		"viewport": viewport,
	})


func has_preview_sources() -> bool:
	return not available_preview_sources.is_empty()


func preview_source_count() -> int:
	return available_preview_sources.size()


func find_material_preview_source_index() -> int:
	for i in range(available_preview_sources.size()):
		if _is_material_preview_source(available_preview_sources[i]):
			return i
	return -1


func remove_preview_source_at(index: int) -> void:
	if index >= 0 and index < available_preview_sources.size():
		available_preview_sources.remove_at(index)


func set_current_preview_index(index: int) -> void:
	current_preview_index = index


func cycle_preview(step: int) -> void:
	apply_preview_source(current_preview_index + step)


func apply_preview_source(source_idx: int) -> void:
	if available_preview_sources.is_empty():
		clear_preview()
		return
	current_preview_index = wrapi(source_idx, 0, available_preview_sources.size())
	_show_preview_texture(_preview_texture_from_source(available_preview_sources[current_preview_index]))

func clear_preview() -> void:
	_show_preview_texture(null)


func apply_preview_source_after_open(source_idx: int) -> void:
	call_deferred("_apply_preview_source_after_open_impl", source_idx)


func refresh_active_material_preview() -> void:
	if available_preview_sources.is_empty():
		return
	if current_preview_index < 0 or current_preview_index >= available_preview_sources.size():
		return
	if _is_material_preview_source(available_preview_sources[current_preview_index]):
		_show_preview_texture(_preview_texture_from_source(available_preview_sources[current_preview_index]))


func queue_material_preview_refresh(terrain, slot_idx: int) -> void:
	if terrain == null:
		return
	_clear_material_preview_cache_for_slot(terrain, slot_idx)
	if has_meta("_mst_material_preview_refresh_queued") and bool(get_meta("_mst_material_preview_refresh_queued")):
		return
	set_meta("_mst_material_preview_refresh_queued", true)
	call_deferred("_flush_material_preview_refresh")


func _apply_preview_source_after_open_impl(source_idx: int) -> void:
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	apply_preview_source(source_idx)


func _flush_material_preview_refresh() -> void:
	if not is_instance_valid(self):
		return
	set_meta("_mst_material_preview_refresh_queued", false)
	refresh_active_material_preview()


func _preview_texture_from_source(source: Variant) -> Texture2D:
	if source == null:
		return null
	if source is Dictionary:
		var source_type := str(source.get("type", ""))
		if source_type == "material_preview":
			var terrain = source.get("terrain")
			var slot_idx := int(source.get("slot_idx", -1))
			return _make_material_preview_texture(terrain, slot_idx)
		if source_type == "viewport":
			var viewport = source.get("viewport")
			if is_instance_valid(viewport) and viewport.has_method("get_texture"):
				return viewport.get_texture()
	elif source is Texture2D:
		return source
	elif source != null and source.has_method("get_texture"):
		return source.get_texture()
	return null


func _is_material_preview_source(source: Variant) -> bool:
	return source is Dictionary and str(source.get("type", "")) == "material_preview"


func _show_preview_texture(tex: Texture2D) -> void:
	texture_preview.texture = tex
	_set_no_preview_label_visible(tex == null)


func _set_no_preview_label_visible(show_label: bool) -> void:
	if no_preview_label != null:
		no_preview_label.visible = show_label


func _coerce_texture2d(tex) -> Texture2D:
	if tex == null or not (tex is Texture2D):
		return null
	return tex as Texture2D if tex.get_class() != "Texture2D" else null


func _get_texture_library(terrain) -> Resource:
	if terrain == null or not terrain.has_method("get"):
		return null
	var lib_res: Resource = terrain.get("texture_library")
	if lib_res != null and lib_res is MSTextureLibraryScript:
		if lib_res.has_method("ensure_length"):
			lib_res.ensure_length()
		return lib_res
	if lib_res is Resource and lib_res.resource_path != null and not str(lib_res.resource_path).is_empty():
		var loaded := ResourceLoader.load(str(lib_res.resource_path))
		if loaded != null and loaded is MSTextureLibraryScript:
			if loaded.has_method("ensure_length"):
				loaded.ensure_length()
			terrain.set("texture_library", loaded)
			return loaded
	return null


func _get_slot_albedo_texture(terrain, slot_idx: int) -> Texture2D:
	if terrain == null or slot_idx < 0:
		return null
	if terrain.texture_slots.size() > slot_idx and terrain.texture_slots[slot_idx] != null:
		var slot_tex := _coerce_texture2d(terrain.texture_slots[slot_idx].texture)
		if slot_tex != null:
			return slot_tex
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.albedo_textures.size():
		return _coerce_texture2d(lib_res.albedo_textures[slot_idx])
	return null


func _compute_slot_albedo_color(terrain, texture: Texture2D) -> Color:
	if terrain == null or texture == null:
		return Color(1, 1, 1, 0)
	if not terrain.has_method("_get_decompressed_image"):
		return Color(1, 1, 1, 0)
	
	var img : Image = terrain._get_decompressed_image(texture)
	if img == null or img.is_empty():
		return Color(1, 1, 1, 0)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	
	var sample_img : Image = img
	var max_dim := maxi(sample_img.get_width(), sample_img.get_height())
	if max_dim > 16:
		var scale := 16.0 / float(max_dim)
		var target_w := maxi(1, int(round(sample_img.get_width() * scale)))
		var target_h := maxi(1, int(round(sample_img.get_height() * scale)))
		sample_img = sample_img.duplicate()
		sample_img.resize(target_w, target_h, Image.INTERPOLATE_BILINEAR)
	
	var accum := Color(0, 0, 0, 0)
	var count := 0.0
	for y in range(sample_img.get_height()):
		for x in range(sample_img.get_width()):
			var px : Color = sample_img.get_pixel(x, y)
			if px.a <= 0.001:
				continue
			accum.r += px.r
			accum.g += px.g
			accum.b += px.b
			count += 1.0
	
	if count <= 0.0:
		return Color(1, 1, 1, 0)
	
	return Color(accum.r / count, accum.g / count, accum.b / count, 1.0)


func _material_preview_cache_key(terrain, slot_idx: int) -> String:
	var terrain_id : int = terrain.get_instance_id() if terrain != null else 0
	return "%s:%s" % [terrain_id, slot_idx]


func _build_material_preview_signature(terrain, slot_idx: int) -> String:
	if terrain == null or slot_idx < 0:
		return "invalid"
	
	var parts : Array[String] = []
	var albedo_tex := _get_slot_albedo_texture(terrain, slot_idx)
	parts.append(str(albedo_tex.get_rid()) if albedo_tex != null else "no_albedo")
	
	var noise_tex := _coerce_texture2d(terrain.get("global_noise_texture")) if terrain.has_method("get") else null
	parts.append(str(noise_tex.get_rid()) if noise_tex != null else "no_noise")
	
	if slot_idx < terrain.texture_slots.size() and terrain.texture_slots[slot_idx] != null:
		var raw_scale : Variant = terrain.texture_slots[slot_idx].get("scale")
		parts.append(str(raw_scale))
		var raw_albedo : Variant = terrain.texture_slots[slot_idx].get("albedo")
		parts.append(str(raw_albedo))
	if slot_idx < terrain.slot_blend_modes.size():
		parts.append(str(terrain.slot_blend_modes[slot_idx]))
	if slot_idx < terrain.slot_color_indices.size():
		for palette_idx_variant in terrain.slot_color_indices[slot_idx]:
			var palette_idx := int(palette_idx_variant)
			parts.append("idx:%d" % palette_idx)
			if palette_idx >= 0 and palette_idx < terrain.palette_colors.size():
				parts.append(str(terrain.palette_colors[palette_idx]))
			if palette_idx >= 0 and palette_idx < terrain.palette_weights.size():
				parts.append(str(terrain.palette_weights[palette_idx]))
	
	return "|".join(parts)


func _clear_material_preview_cache_for_slot(terrain, slot_idx: int) -> void:
	var preview_cache : Variant = _material_preview_cache
	if not (preview_cache is Dictionary):
		_material_preview_cache = {}
		return
	var cache_key := _material_preview_cache_key(terrain, slot_idx)
	if preview_cache.has(cache_key):
		preview_cache.erase(cache_key)


func _get_preview_noise_image(terrain) -> Image:
	if terrain == null or not terrain.has_method("_get_decompressed_image"):
		return null
	var noise_tex: Texture2D = _coerce_texture2d(terrain.get("global_noise_texture")) if terrain.has_method("get") else null
	if noise_tex == null:
		return null
	return terrain._get_decompressed_image(noise_tex)


func _get_slot_preview_entries(terrain, slot_idx: int) -> Array:
	var entries : Array = []
	if terrain == null or slot_idx < 0 or slot_idx >= terrain.slot_color_indices.size():
		return entries
	var indices: Array = terrain.slot_color_indices[slot_idx]
	for idx in indices:
		var palette_idx := int(idx)
		if palette_idx < 0 or palette_idx >= terrain.palette_colors.size():
			continue
		var weight := 100.0
		if palette_idx < terrain.palette_weights.size():
			weight = maxf(float(terrain.palette_weights[palette_idx]), 0.0)
		entries.append({
			"color": terrain.palette_colors[palette_idx],
			"weight": weight,
		})
	return entries


func _sample_preview_noise(noise_img: Image, uv: Vector2) -> float:
	if noise_img == null:
		var seed_value: float = sin(uv.dot(Vector2(12.9898, 78.233))) * 43758.5453
		return seed_value - floor(seed_value)
	var w : int = noise_img.get_width()
	var h : int = noise_img.get_height()
	if w <= 0 or h <= 0:
		return 0.5
	var fx : float = uv.x - floor(uv.x)
	var fy : float = uv.y - floor(uv.y)
	var px : int = clampi(int(floor(fx * float(w))), 0, w - 1)
	var py : int = clampi(int(floor(fy * float(h))), 0, h - 1)
	return noise_img.get_pixel(px, py).r


func _preview_hash(coord: Vector2) -> float:
	var seed_value : float = sin(coord.dot(Vector2(127.1, 311.7))) * 43758.5453
	return seed_value - floor(seed_value)


func _preview_smoothstep(edge0: float, edge1: float, x: float) -> float:
	if absf(edge1 - edge0) <= 0.000001:
		return 0.0 if x < edge0 else 1.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _sample_preview_albedo(albedo_img: Image, uv: Vector2) -> Color:
	if albedo_img == null:
		return Color(1.0, 1.0, 1.0, 1.0)
	var w : int = albedo_img.get_width()
	var h : int = albedo_img.get_height()
	if w <= 0 or h <= 0:
		return Color(1.0, 1.0, 1.0, 1.0)
	var fx : float = clampf(uv.x, 0.0, 1.0)
	var fy : float = clampf(uv.y, 0.0, 1.0)
	var px : int = clampi(int(floor(fx * float(w))), 0, w - 1)
	var py : int = clampi(int(floor(fy * float(h))), 0, h - 1)
	return albedo_img.get_pixel(px, py)


func _preview_palette_color(entries: Array, blend_mode: int, noise_uv: Vector2, surface_coords: Vector2, noise_img: Image) -> Color:
	if entries.is_empty():
		return Color(1.0, 1.0, 1.0, 0.0)
	if entries.size() == 1:
		return entries[0]["color"]
	
	var color_count := entries.size()
	var gradient_mode := blend_mode != 1 and blend_mode != 2 and blend_mode != 3
	
	# Match terrain palette remap scales (gradient 0.014 / discrete 0.008).
	var palette_gn_scale := 0.014 if gradient_mode else 0.008
	var n := 1.0 - _sample_preview_noise(noise_img, noise_uv * palette_gn_scale)
	if gradient_mode:
		var centered := (clampf(n, 0.0, 1.0) - 0.5) * 2.0
		n = clampf(sign(centered) * pow(absf(centered), 0.55) * 0.5 + 0.5, 0.0, 1.0)
	else:
		n = _preview_smoothstep(0.0, 1.0, n)
	
	var ws : Array[float] = []
	ws.resize(color_count)
	var total := 0.0
	for i in range(color_count):
		var current_weight := maxf(float(entries[i]["weight"]) / 100.0, 0.0)
		ws[i] = current_weight
		total += current_weight
	
	if total <= 0.0001:
		total = float(color_count)
		for i in range(color_count):
			ws[i] = 1.0
	
	var x := clampf(n, 0.0, 1.0) * total
	var i0 := 0
	var start := 0.0
	var w0 := ws[0]
	var cumulative := 0.0
	for i in range(color_count):
		var wi := ws[i]
		if x < cumulative + wi or i == color_count - 1:
			i0 = i
			start = cumulative
			w0 = wi
			break
		cumulative += wi
	
	var i1 := mini(i0 + 1, color_count - 1)
	var t := 0.0
	if w0 > 0.00001:
		t = clampf((x - start) / w0, 0.0, 1.0)
	if blend_mode == 1:
		return entries[i0]["color"]
	elif blend_mode == 2:
		var result : Color = entries[i0]["color"]
		var boundary := 0.0
		var transition := maxf(total * 0.09, 0.0001)
		var dither_coord := Vector2(floor(surface_coords.x * 8.0), floor(surface_coords.y * 8.0))
		var dither := _preview_hash(dither_coord)
		for i in range(color_count - 1):
			boundary += ws[i]
			if ws[i] <= 0.0001 or ws[i + 1] <= 0.0001:
				continue
			var blend_t := _preview_smoothstep(boundary - transition, boundary + transition, x)
			if dither <= blend_t:
				result = entries[i + 1]["color"]
		return result
	elif blend_mode == 3:
		var result : Color = entries[i0]["color"]
		var boundary := 0.0
		var transition := maxf(total * 0.09, 0.0001)
		var seam := 0.12
		var checker_coord := Vector2(floor(surface_coords.x * 4.0), floor(surface_coords.y * 4.0))
		var checker := fposmod(checker_coord.x + checker_coord.y, 2.0)
		for i in range(color_count - 1):
			boundary += ws[i]
			if ws[i] <= 0.0001 or ws[i + 1] <= 0.0001:
				continue
			var blend_t := _preview_smoothstep(boundary - transition, boundary + transition, x)
			var next_color: Color = entries[i + 1]["color"]
			if blend_t > 0.5 + seam:
				result = next_color
			elif blend_t >= 0.5 - seam:
				result = next_color if checker > 0.5 else result
		return result
	
	var accum_color := Color(0.0, 0.0, 0.0, 0.0)
	var accum_weight := 0.0
	var band_start := 0.0
	for i in range(color_count):
		var wi := ws[i]
		var band_end := band_start + wi
		if wi > 0.0001:
			var left_width := 0.0 if i == 0 else maxf(minf(ws[i - 1], wi) * 0.75, total * 0.004)
			var right_width := 0.0 if i == color_count - 1 else maxf(minf(wi, ws[i + 1]) * 0.75, total * 0.004)
			var left := 1.0
			var right := 1.0
			if i > 0:
				left = _preview_smoothstep(band_start - left_width, band_start + left_width, x)
			if i < color_count - 1:
				right = 1.0 - _preview_smoothstep(band_end - right_width, band_end + right_width, x)
			var band_weight := clampf(left * right, 0.0, 1.0)
			if band_weight > 0.0001:
				accum_color += entries[i]["color"] * band_weight
				accum_weight += band_weight
		band_start = band_end
	
	if accum_weight > 0.0001:
		return accum_color / accum_weight
	
	return entries[i0]["color"].lerp(entries[i1]["color"], t)


func _tint_preview_pixel(src: Color, palette: Color, base_albedo: Color) -> Color:
	var alpha := clampf(palette.a, 0.0, 1.0)
	if alpha <= 0.0001:
		return src
	
	var src_linear := src.srgb_to_linear()
	var palette_linear := palette.srgb_to_linear()
	var base_linear := base_albedo.srgb_to_linear()
	var base_r := maxf(base_linear.r, 0.001)
	var base_g := maxf(base_linear.g, 0.001)
	var base_b := maxf(base_linear.b, 0.001)
	var ratio_r := clampf(palette_linear.r / base_r, 0.0, 4.0)
	var ratio_g := clampf(palette_linear.g / base_g, 0.0, 4.0)
	var ratio_b := clampf(palette_linear.b / base_b, 0.0, 4.0)
	var mul_r := lerpf(1.0, ratio_r, alpha)
	var mul_g := lerpf(1.0, ratio_g, alpha)
	var mul_b := lerpf(1.0, ratio_b, alpha)
	var tinted_linear := Color(
		clampf(src_linear.r * mul_r, 0.0, 1.0),
		clampf(src_linear.g * mul_g, 0.0, 1.0),
		clampf(src_linear.b * mul_b, 0.0, 1.0),
		src.a
	)
	
	return tinted_linear.linear_to_srgb()


func _make_material_preview_texture(terrain, slot_idx: int) -> Texture2D:
	if terrain == null or slot_idx < 0:
		return null
	
	var preview_cache : Variant = _material_preview_cache
	if not (preview_cache is Dictionary):
		_material_preview_cache = {}
		preview_cache = _material_preview_cache
	
	var cache_key := _material_preview_cache_key(terrain, slot_idx)
	var signature := _build_material_preview_signature(terrain, slot_idx)
	if preview_cache.has(cache_key):
		var cached : Variant = preview_cache[cache_key]
		if cached is Dictionary and str(cached.get("signature", "")) == signature:
			var cached_texture : Variant = cached.get("texture")
			if cached_texture is Texture2D:
				return cached_texture
	
	var texture := _get_slot_albedo_texture(terrain, slot_idx)
	if texture == null:
		return null
	if not terrain.has_method("_get_decompressed_image"):
		return texture
	
	var img : Image = terrain._get_decompressed_image(texture)
	if img == null:
		return texture
	img = img.duplicate()
	if img == null:
		return texture
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	
	var iw := img.get_width()
	var ih := img.get_height()
	if iw <= 0 or ih <= 0:
		return texture
	
	var frame_w := 484
	var frame_h := 267
	var card_size := 256
	var card_img := Image.create_empty(card_size, card_size, false, Image.FORMAT_RGBA8)
	var base_albedo := Color(1.0, 1.0, 1.0, 0.0)
	if slot_idx < terrain.texture_slots.size() and terrain.texture_slots[slot_idx] != null:
		var raw_albedo : Variant = terrain.texture_slots[slot_idx].get("albedo")
		if raw_albedo is Color:
			base_albedo = raw_albedo
	if base_albedo.a <= 0.0001:
		base_albedo = _compute_slot_albedo_color(terrain, texture)
	var noise_img := _get_preview_noise_image(terrain)
	if noise_img != null:
		noise_img = noise_img.duplicate()
	
	var entries := _get_slot_preview_entries(terrain, slot_idx)
	var mode := 0
	if slot_idx < terrain.slot_blend_modes.size():
		mode = clampi(int(terrain.slot_blend_modes[slot_idx]), 0, 3)
	# Larger tile_scale = more of the albedo pattern visible (less zoomed-in).
	var tile_scale := 0.62
	var slot_scale := 1.0
	if slot_idx < terrain.texture_slots.size() and terrain.texture_slots[slot_idx] != null:
		var raw_scale : Variant = terrain.texture_slots[slot_idx].get("scale")
		if raw_scale is float or raw_scale is int:
			slot_scale = maxf(float(raw_scale), 0.01)
	
	var preview_zoom := tile_scale / slot_scale
	var preview_extent := clampf(preview_zoom, 0.2, 1.0)
	var preview_offset := Vector2((1.0 - preview_extent) * 0.5, (1.0 - preview_extent) * 0.5)
	for y in range(card_size):
		for x in range(card_size):
			var uv := Vector2(float(x) / float(card_size), float(y) / float(card_size))
			var sample_uv := preview_offset + uv * preview_extent
			var src := _sample_preview_albedo(img, sample_uv)
			var px := src
			if not entries.is_empty():
				# Use card-space coords so palette noise frequency stays stable when zooming.
				var palette_color := _preview_palette_color(entries, mode, uv * 256.0, uv * 256.0, noise_img)
				px = _tint_preview_pixel(src, palette_color, base_albedo)
			var centered_uv := uv - Vector2(0.5, 0.5)
			var dist := centered_uv.length()
			var edge_fade := clampf(1.0 - maxf(dist - 0.60, 0.0) * 2.4, 0.78, 1.0)
			px.r = clampf(px.r * edge_fade, 0.0, 1.0)
			px.g = clampf(px.g * edge_fade, 0.0, 1.0)
			px.b = clampf(px.b * edge_fade, 0.0, 1.0)
			card_img.set_pixel(x, y, px)
	
	var preview_img := Image.create_empty(frame_w, frame_h, false, Image.FORMAT_RGBA8)
	preview_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shadow_size := card_size + 12
	var shadow_img := Image.create_empty(shadow_size, shadow_size, false, Image.FORMAT_RGBA8)
	shadow_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(shadow_size):
		for x in range(shadow_size):
			var centered := Vector2(float(x) / float(shadow_size), float(y) / float(shadow_size)) - Vector2(0.5, 0.5)
			var dist := centered.length()
			var alpha := clampf(1.0 - _preview_smoothstep(0.44, 0.72, dist), 0.0, 1.0) * 0.18
			shadow_img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	
	var offset_x := int((frame_w - card_size) * 0.5)
	var offset_y := int((frame_h - card_size) * 0.5)
	preview_img.blit_rect(shadow_img, Rect2i(0, 0, shadow_size, shadow_size), Vector2i(offset_x - 6, offset_y + 8))
	preview_img.blit_rect(card_img, Rect2i(0, 0, card_size, card_size), Vector2i(offset_x, offset_y))
	var preview_texture := ImageTexture.create_from_image(preview_img)
	_material_preview_cache[cache_key] = {
		"signature": signature,
		"texture": preview_texture,
	}
	
	return preview_texture
