@tool
class_name MarchingSquaresHeightmapExporter
extends RefCounted
## Exports terrain chunk data to PNG images.
## Multi-file (single_file=false): up to 3 greyscale L8 PNGs.
##   Heightmap: each pixel encodes height normalised to dimensions.y.
##   Grass mask: white = has grass, black = no grass.
##   Texture index: each pixel encodes the ground texture slot (0-255).
## Single-file (single_file=true): one RGBA8 PNG named {terrain}_terrain.png.
##   R = texture slot (0-255), G = normalised height, B = grass (1 or 0), A = 255 (reserved).


static func run(
	terrain: MarchingSquaresTerrain,
	chunks_to_export: Array,
	export_heightmap: bool,
	export_grass: bool,
	export_texture_index: bool,
	output_path: String,
	caller: Node,
	single_file: bool = false,
	folder_name: String = "new_terrain_heightmap"
) -> void:
	# --- Build progress dialog ---
	var base_control := EditorInterface.get_base_control()
		
	var dialog := Popup.new()
	dialog.exclusive = true
	dialog.unresizable = true
	var window_size := DisplayServer.window_get_size()
	dialog.size = Vector2i(int(window_size.x * 0.3), int(window_size.y * 0.15))
	dialog.theme = base_control.get_theme()
		
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = base_control.get_theme_color("base_color", "Editor")
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", panel_style)
	dialog.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Initializing..."
	vbox.add_child(status_label)
	
	var progress_bar := ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	vbox.add_child(progress_bar)
	
	var ok_button := Button.new()
	ok_button.text = "OK"
	ok_button.visible = false
	ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_button.pressed.connect(dialog.queue_free)
	vbox.add_child(ok_button)
	
	dialog.close_requested.connect(func():
		if ok_button.visible:
			dialog.queue_free()
	)
	
	base_control.add_child(dialog)
	dialog.popup_centered()
	await caller.get_tree().process_frame
	
	var finish_error := func(msg: String) -> void:
		status_label.add_theme_color_override("font_color", base_control.get_theme_color("error_color", "Editor"))
		status_label.text = msg
		ok_button.visible = true
	
	var finish_ok := func(files_saved: int) -> void:
		status_label.text = "Done! Saved %d file(s)." % files_saved
		progress_bar.value = 100.0
		dialog.queue_free()
	
	# --- Validate inputs ---
	if chunks_to_export.is_empty():
		finish_error.call("No chunks to export.")
		return
	
	if not single_file and not export_heightmap and not export_grass and not export_texture_index:
		finish_error.call("No export layers selected.")
		return
	
	if output_path.is_empty():
		finish_error.call("No output path specified.")
		return
	
	# --- Calculate bounding box of the chunk grid ---
	var min_cx : int = chunks_to_export[0].x
	var min_cz : int = chunks_to_export[0].y
	var max_cx : int = chunks_to_export[0].x
	var max_cz : int = chunks_to_export[0].y
	for coords in chunks_to_export:
		if coords.x < min_cx: min_cx = coords.x
		if coords.y < min_cz: min_cz = coords.y
		if coords.x > max_cx: max_cx = coords.x
		if coords.y > max_cz: max_cz = coords.y
	
	# Seam-deduplicated image dimensions:
	# chunks share edge vertices, so total unique verts = chunks * (dims-1) + 1
	var dims : Vector3i = terrain.dimensions
	var cells_x : int = dims.x - 1
	var cells_z : int = dims.z - 1
	var img_w : int = (max_cx - min_cx + 1) * cells_x + 1
	var img_h : int = (max_cz - min_cz + 1) * cells_z + 1
	
	# --- Allocate output images ---
	var hmap_img : Image = null
	var grass_img : Image = null
	var tex_img : Image = null
	var combined_img : Image = null
	
	if single_file:
		combined_img = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
		# Default alpha to 1.0 and grass channel to 1.0 (all grass) before overwriting
		combined_img.fill(Color(0.0, 0.0, 1.0, 1.0))
	else:
		if export_heightmap:
			hmap_img = Image.create(img_w, img_h, false, Image.FORMAT_L8)
		if export_grass:
			grass_img = Image.create(img_w, img_h, false, Image.FORMAT_L8)
			# Default to white (all grass) before overwriting with chunk data
			grass_img.fill(Color.WHITE)
		if export_texture_index:
			tex_img = Image.create(img_w, img_h, false, Image.FORMAT_L8)
	
	# --- Sample each chunk into the images ---
	var total_chunks : int = chunks_to_export.size()
	var step_pct : float = 80.0 / float(max(total_chunks, 1))
	status_label.text = "Exporting chunks..."
	var chunk_idx : int = 0
	
	for coords in chunks_to_export:
		var chunk := terrain.chunks.get(coords) as MarchingSquaresTerrainChunk
		chunk_idx += 1
		if not chunk:
			progress_bar.value = chunk_idx * step_pct
			continue
		
		# Top-left pixel origin for this chunk inside the full image
		var px_ox : int = (coords.x - min_cx) * cells_x
		var px_oz : int = (coords.y - min_cz) * cells_z
		
		for lz in dims.z:
			for lx in dims.x:
				var px : int = px_ox + lx
				var pz : int = px_oz + lz
				# Flat index into the packed colour arrays
				var vi : int = lz * dims.x + lx
				
				if combined_img:
					var h : float = chunk.height_map[lz][lx]
					var h_norm := clamp(h / float(dims.y), 0.0, 1.0)
					var slot : int = 0
					if chunk.color_map_0.size() > vi:
						slot = MarchingSquaresTerrainVertexColorHelper.get_texture_index_from_colors(chunk.color_map_0[vi], chunk.color_map_1[vi])
					var grass_b : float = 1.0
					if chunk.grass_mask_map.size() > vi:
						grass_b = 1.0 if chunk.grass_mask_map[vi].r > 0.5 else 0.0
					# R = slot 0-255 (direct byte, no scaling)
					# G = normalised height
					# B = grass boolean (1.0 or 0.0 only)
					# A = 1.0 reserved
					combined_img.set_pixel(px, pz, Color(float(slot) / 255.0, h_norm, grass_b, 1.0))
				else:
					if hmap_img:
						var h : float = chunk.height_map[lz][lx]
						var normalized := clamp(h / float(dims.y), 0.0, 1.0)
						hmap_img.set_pixel(px, pz, Color(normalized, normalized, normalized, 1.0))
					
					if grass_img:
						# Default to 1.0 (grass present) if the mask hasn't been initialised
						var g : float = 1.0
						if chunk.grass_mask_map.size() > vi:
							g = chunk.grass_mask_map[vi].r
						grass_img.set_pixel(px, pz, Color(g, g, g, 1.0))
					
					if tex_img:
						var slot : int = 0
						if chunk.color_map_0.size() > vi:
							slot = MarchingSquaresTerrainVertexColorHelper.get_texture_index_from_colors(chunk.color_map_0[vi], chunk.color_map_1[vi])
						# Map vertex_color_idx 0-255 to pixel value 0-255
						var val : float = float(slot) / 255.0
						tex_img.set_pixel(px, pz, Color(val, val, val, 1.0))
		
		progress_bar.value = chunk_idx * step_pct
		await caller.get_tree().process_frame
	
	# --- Ensure output directory exists ---
	status_label.text = "Saving files..."
	
	# Create an export folder inside the output path
	var export_path := output_path.path_join(folder_name)
	
	var abs_path : String = ProjectSettings.globalize_path(export_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		var make_err := DirAccess.make_dir_recursive_absolute(abs_path)
		if make_err != OK:
			finish_error.call("Failed to create output directory:\n%s" % export_path)
			return
	
	# --- Save images ---
	var terrain_name : String = terrain.name
	var files_saved : int = 0
	
	if combined_img:
		var path := export_path.path_join(terrain_name + "_terrain.png")
		var err := combined_img.save_png(path)
		if err != OK:
			finish_error.call("Failed to save combined terrain map:\n%s" % path)
			return
		files_saved += 1
	
	if hmap_img:
		var path := export_path.path_join(terrain_name + "_heightmap.png")
		var err := hmap_img.save_png(path)
		if err != OK:
			finish_error.call("Failed to save heightmap:\n%s" % path)
			return
		files_saved += 1
	
	if grass_img:
		var path := export_path.path_join(terrain_name + "_grass.png")
		var err := grass_img.save_png(path)
		if err != OK:
			finish_error.call("Failed to save grass mask:\n%s" % path)
			return
		files_saved += 1
	
	if tex_img:
		var path := export_path.path_join(terrain_name + "_texture_index.png")
		var err := tex_img.save_png(path)
		if err != OK:
			finish_error.call("Failed to save texture index:\n%s" % path)
			return
		files_saved += 1
	
	progress_bar.value = 95.0
	await caller.get_tree().process_frame
	
	EditorInterface.get_resource_filesystem().scan()
	finish_ok.call(files_saved)
