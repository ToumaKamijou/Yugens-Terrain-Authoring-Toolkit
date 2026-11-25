@tool
extends RefCounted
class_name MarchingSquaresHeightmapExtractor
## Extracts a heightmap from 3D mesh data.


const IMAGE_RESOLUTION : int = 512


static func run(
	target_mesh: Mesh,
	output_path: String,
	caller: Node,
	file_name: String = "new_mesh_heightmap"
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
	
	var finish_ok := func() -> void:
		status_label.text = "Done! Saved 1 file."
		progress_bar.value = 100.0
		dialog.queue_free()
	
	# --- Validate inputs ---
	if not target_mesh:
		finish_error.call("No mesh to extract from.")
		return
	
	if output_path.is_empty():
		finish_error.call("No output path specified.")
		return
	
	# --- Calculate the mesh bounds ---
	status_label.text = "Calculating mesh bounds..."
	var array_mesh := convert_to_array_mesh(target_mesh)
	if array_mesh == null:
		finish_error.call("Target mesh couldn't be converted to an ArrayMesh.")
		return
	
	var aabb := array_mesh.get_aabb()
	
	var min_x := aabb.position.x
	var max_x := aabb.end.x
	var min_y := aabb.position.y
	var max_y := aabb.end.y
	var min_z := aabb.position.z
	var max_z := aabb.end.z
	
	# --- Gather the highest point for each pixel on the to-be heightmap ---
	var heights := PackedFloat32Array()
	heights.resize(IMAGE_RESOLUTION * IMAGE_RESOLUTION)
	for i in heights.size():
		heights[i] = -INF # Use the lowest number possible as a base (Color.Black)
	
	for surface in array_mesh.get_surface_count():
		var mdt := MeshDataTool.new()
		
		var mesh_error := mdt.create_from_surface(array_mesh, surface)
		if mesh_error == OK: # Go through all triangles
			var face_count := mdt.get_face_count()
			for i in range(face_count):
				status_label.text = "Looping over triangles in surface " + str(surface) + "..."
				var v1_idx := mdt.get_face_vertex(i, 0)
				var v2_idx := mdt.get_face_vertex(i, 1)
				var v3_idx := mdt.get_face_vertex(i, 2)
				
				var v1 := mdt.get_vertex(v1_idx)
				var v2 := mdt.get_vertex(v2_idx)
				var v3 := mdt.get_vertex(v3_idx)
				
				# Convert to pixel coords
				var p1 := Vector2(
					global_to_pixel_x(v1.x, min_x, max_x),
					global_to_pixel_y(v1.z, min_z, max_z)
				)
				
				var p2 := Vector2(
					global_to_pixel_x(v2.x, min_x, max_x),
					global_to_pixel_y(v2.z, min_z, max_z)
				)
				
				var p3 := Vector2(
					global_to_pixel_x(v3.x, min_x, max_x),
					global_to_pixel_y(v3.z, min_z, max_z)
				)
				
				# Calculate triangle pixel bounds inside the full heightmap image
				var min_px := maxi(0, floor(min(p1.x, p2.x, p3.x)))
				var max_px := mini(IMAGE_RESOLUTION - 1, ceil(max(p1.x, p2.x, p3.x)))
				
				var min_py := maxi(0, floor(min(p1.y, p2.y, p3.y)))
				var max_py := mini(IMAGE_RESOLUTION - 1, ceil(max(p1.y, p2.y, p3.y)))
				
				for py in range(min_py, max_py + 1):
					for px in range(min_px, max_px + 1): # Check if the current pixel is inside the triangle
						# Barycentric weight calculations for point p(xz)
						var p_sample := Vector2(px + 0.5, py + 0.5)
						
						var w1 := (
							((p2.y - p3.y) * (p_sample.x - p3.x) +
							(p3.x - p2.x) * (p_sample.y - p3.y))
							/
							((p2.y - p3.y) * (p1.x - p3.x) +
							(p3.x - p2.x) * (p1.y - p3.y))
						)
						
						var w2 := (
							((p3.y - p1.y) * (p_sample.x - p3.x) +
							(p1.x - p3.x) * (p_sample.y - p3.y))
							/
							((p2.y - p3.y) * (p1.x - p3.x) +
							(p3.x - p2.x) * (p1.y - p3.y))
						)
						
						var w3 := 1.0 - w1 - w2
						
						"""
						BARYCENTRIC WEIGHTS IN CONTEXT
						
						w1, w2 and w3 are the weights of p1, p2 and p3,
						these weights are used to find a point on a triangle.
						
						We first get the XZ bounds of the current mesh face,
						then we match those bounds to a box of heightmap pixels,
						for every pixel we look if it sits inside the face.
						
						The pixel is inside the triangle when all weights are >= 0.
						
						If w1 == 1.0, the pixel lies exactly on p1;
						If w2 == 1.0, the pixel lies exactly on p2;
						If w3 == 1.0, the pixel lies exactly on p3.
						
						This way any pixel can find its lerped height (y),
						and corresponding translated greyscale color value.
						
						See the video below for a more in-depth explanation:
						https://www.youtube.com/watch?v=HYAgJN3x4GA
						"""
						
						if w1 >= 0.0 and w2 >= 0.0 and w3 >= 0.0 and w1 + w2 + w3 <= 1.0:
							# Interpolate the height (y)
							var p_height := (
								w1 * v1.y +
								w2 * v2.y +
								w3 * v3.y
							)
							# Look if this pixel already exists and if so if its the highest value
							# This way meshes with non-heightmap based shapes still convert properly
							var p_idx := py * IMAGE_RESOLUTION + px
							heights[p_idx] = max(heights[p_idx], p_height)
						else:
							continue # Pixel lies outside the triangle
				
				if i % maxi(1, face_count / 100) == 0:
					progress_bar.value = 100.0 * float(i + 1) / face_count
					await caller.get_tree().process_frame
			progress_bar.value = 100.0
			await caller.get_tree().process_frame
	
	# --- Convert heights to greyscale pixels ---
	status_label.text = "Converting to image..."
	var image := Image.create_empty(IMAGE_RESOLUTION, IMAGE_RESOLUTION, false, Image.FORMAT_L8)
	
	var min_height := max_y
	for h in heights:
		if h != -INF:
			min_height = min(min_height, h)
	
	for y in IMAGE_RESOLUTION:
		for x in IMAGE_RESOLUTION:
			var h = heights[y * IMAGE_RESOLUTION + x]
			var value = inverse_lerp(min_height, max_y, h)
			image.set_pixel(x, y, Color(value, 0, 0))
	
	# --- Ensure output directory exists ---
	status_label.text = "Saving file..."
	
	var abs_path : String = ProjectSettings.globalize_path(output_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		var make_err := DirAccess.make_dir_recursive_absolute(abs_path)
		if make_err != OK:
			finish_error.call("Failed to create output directory:\n%s" % output_path)
			return
	
	# --- Save image ---
	var path := output_path.path_join(file_name + ".png")
	var err := image.save_png(path)
	if err != OK:
		finish_error.call("Failed to heightmap image:\n%s" % path)
		return
	
	progress_bar.value = 95.0
	await caller.get_tree().process_frame
	
	EditorInterface.get_resource_filesystem().scan()
	finish_ok.call()


static func convert_to_array_mesh(mesh: Mesh) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return array_mesh


static func global_to_pixel_x(x: float, min_x: float, max_x: float) -> float:
	return inverse_lerp(min_x, max_x, x) * (IMAGE_RESOLUTION - 1)


static func global_to_pixel_y(z: float, min_z: float, max_z: float) -> float:
	return inverse_lerp(min_z, max_z, z) * (IMAGE_RESOLUTION - 1)
