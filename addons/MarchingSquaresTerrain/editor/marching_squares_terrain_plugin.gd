@tool
extends EditorPlugin
class_name MarchingSquaresTerrainPlugin


static var instance : MarchingSquaresTerrainPlugin

const EMPTY_TEXTURE_PRESET : MarchingSquaresTexturePreset = preload("res://addons/MarchingSquaresTerrain/resources/empty_project.tres")

var gizmo_plugin := MarchingSquaresTerrainGizmoPlugin.new()
var toolbar := MarchingSquaresToolbar.new()
var tool_attributes := MarchingSquaresToolAttributes.new()
var active_tool : int = 0

var UI : Script = preload("res://addons/MarchingSquaresTerrain/editor/marching_squares_ui.gd")
var ui : MarchingSquaresUI

var is_initialized : bool = false
var initialization_error : String = ""

var current_terrain_node : MarchingSquaresTerrain

enum TerrainToolMode {
	BRUSH = 0,
	LEVEL = 1,
	SMOOTH = 2,
	BRIDGE = 3,
	GRASS_MASK = 4,
	VERTEX_PAINTING = 5,
	DEBUG_BRUSH = 6,
	CHUNK_MANAGEMENT = 7,
	TERRAIN_SETTINGS = 8,
}

var BrushMode : Dictionary = {
	"0" = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/round_brush_radius_visual.tres"),
	"1" = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/square_brush_radius_visual.tres"),
}

var BrushMat : Dictionary = {
	"0" = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/round_brush_radius_material.tres"),
	"1" = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/square_brush_radius_material.tres"),
}

var mode : TerrainToolMode = TerrainToolMode.BRUSH:
	set(value):
		mode = value
		current_draw_pattern.clear()
		if mode == TerrainToolMode.VERTEX_PAINTING:
			falloff = false
			BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", false)

var vp_texture_names = preload("res://addons/MarchingSquaresTerrain/resources/texture_names.tres")

var current_brush_index : int = 0

var is_chunk_plane_hovered : bool
var current_hovered_chunk : Vector2i

var brush_position : Vector3

# Tool attribute variables
var brush_size : float = 15.0
var ease_value : float = -1.0 # No ease
var strength : float = 1.0
var height : float = 0.0
var flatten : bool = true
var falloff : bool = true

var should_mask_grass : bool = false

# Flag to prevent _set_new_textures() when syncing preset from terrain node
var _syncing_from_terrain : bool = false

# Currently selected preset for vertex textures (DOES change the global terrain)
var current_texture_preset : MarchingSquaresTexturePreset = EMPTY_TEXTURE_PRESET.duplicate():
	set(value):
		current_texture_preset = value
		current_quick_paint = null
		if not _syncing_from_terrain:
			_set_new_textures(value)

# Currently selected preset for quick painting (does NOT change the global terrain)
var current_quick_paint : MarchingSquaresQuickPaint = null

# Toggle for painting walls vs ground in VERTEX_PAINTING mode
var paint_walls_mode : bool = false:
	set(value):
		paint_walls_mode = value
		

var vertex_color_idx : int = 0:
	set(value):
		vertex_color_idx = value
		_set_vertex_colors(value)
var vertex_color_0 : Color = Color(1.0, 0.0, 0.0, 0.0)
var vertex_color_1 : Color = Color(1.0, 0.0, 0.0, 0.0)

# A dictionary with keys for each tile that is currently being drawn to with the brush 
# In brush mode, the value is the height that preview was drawn to, aka the height BEFORE it is set
# In ground texture mode, the value is the color of the point BEFORE the draw
var current_draw_pattern : Dictionary

var terrain_hovered : bool

# True if the mouse is currently held down to draw
var is_drawing : bool

# When the brush draws, if the gizmo sees the draw height is not set, it will set the draw height
var draw_height_set : bool

# Height of the current pattern that is being drawn at for the brush tool
var draw_height : float

# Is set to true when the user clicks on a tile that is part of the current draw pattern, will enter heightdrag setting mode
var is_setting : bool

var is_making_bridge : bool
var bridge_start_pos : Vector3

# The point where the height drag started
var base_position : Vector3

const BRUSH_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/brush_visual.tres")
var BRUSH_RADIUS_VISUAL : Mesh = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/round_brush_radius_visual.tres")
var BRUSH_RADIUS_MATERIAL : ShaderMaterial = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/round_brush_radius_material.tres")
@onready var falloff_curve : Curve = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/curve_falloff.tres")


func _enter_tree():
	instance = self
	call_deferred("_deferred_enter_tree")
	
	print_rich("Welcome to [color=MEDIUM_ORCHID][url=https://www.youtube.com/@yugen_seishin]Yūgen[/url][/color]'s [wave]Marching Squares Terrain Authoring Toolkit[/wave]\nThis plugin is under MIT license")


func _deferred_enter_tree() -> void:
	if not _safe_initialize():
		printerr("ERROR: [MarchingSquaresTerrainPlugin] failed to initialize plugin: " + initialization_error)
	else:
		print_verbose("[MarchingSquaresTerrainPlugin] initialized succesfully!")


func _safe_initialize() -> bool:
	if is_initialized:
		return true
	
	if not Engine.is_editor_hint():
		initialization_error = "Plugin was initialized during runtime"
		return false
	
	if not EditorInterface:
		initialization_error = "No EditorInterface detected"
		return false
	
	if not get_tree():
		initialization_error = "No tree detected while initializing"
		return false
	
	var terrain_script := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain.gd")
	var chunk_script := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_chunk.gd")
	var terrain_icon := preload("res://addons/MarchingSquaresTerrain/editor/icons/Marching_Squares_Terrain_Icon.svg")
	var chunk_icon := preload("res://addons/MarchingSquaresTerrain/editor/icons/Marching_Squares_Terrain_Chunk_Icon.svg")
	
	if terrain_script and chunk_script:
		add_custom_type("MarchingSquaresTerrain", "Node3D", terrain_script, terrain_icon)
		add_custom_type("MarchingSquaresTerrainChunk", "MeshInstance3D", chunk_script, chunk_icon)
	else:
		initialization_error = "Failed to load algorithm scripts"
		return false
	
	if gizmo_plugin:
		add_node_3d_gizmo_plugin(gizmo_plugin)
	else:
		initialization_error = "Failed to create gizmo plugin"
		return false
	
	if not ui:
		ui = UI.new()
		if ui:
			ui.plugin = self
			add_child(ui)
		else:
			initialization_error = "Failed to create UI system"
			return false
	
	is_initialized = true
	return true


func _exit_tree():
	if ui:
		ui.queue_free()
		ui = null
	
	remove_custom_type("MarchingSquaresTerrain")
	remove_custom_type("MarchingSquaresTerrainChunk")
	
	if gizmo_plugin:
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null
	
	is_initialized = false
	initialization_error = ""


func _ready():
	BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", falloff)


func _edit(object: Object) -> void:
	if not is_initialized:
		printerr("ERROR: [MarchingSquaresTerrainPlugin] plugin not yet initialized, calling _safe_initialize() as failsafe")
		if not _safe_initialize():
			printerr("ERROR: [MarchingSquaresTerrainPlugin] failed to initialize plugin for editing")
			return
	if object is MarchingSquaresTerrain:
		if ui:
			ui.set_visible(true)
			current_terrain_node = object
			
			# Sync plugin's preset from the selected terrain's saved preset
			# This ensures each terrain keeps its own preset on selection/reload
			_syncing_from_terrain = true
			current_texture_preset = object.current_texture_preset
			_syncing_from_terrain = false
	else:
		if ui:
			ui.set_visible(false)
		current_draw_pattern.clear()
		is_drawing = false
		draw_height_set = false
		if gizmo_plugin.terrain_gizmo:
			gizmo_plugin.terrain_gizmo.clear()


# This function handles the mouse click in the 3D viewport
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_initialized:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	var selected = EditorInterface.get_selection().get_selected_nodes()
	# Only proceed if exactly 1 terrain system is selected
	if not selected or len(selected) > 1:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Handle Global Cancel (Right Click)
	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_RIGHT and event.is_pressed():
		if not current_draw_pattern.is_empty() or is_drawing or is_setting:
			current_draw_pattern.clear()
			is_drawing = false
			is_setting = false
			is_making_bridge = false
			gizmo_plugin.terrain_gizmo._redraw()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Handle clicks
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return handle_mouse(camera, event)
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handles(object: Object) -> bool:
	if not is_initialized:
		return false
	
	return object is MarchingSquaresTerrain


func handle_hotkey(keycode: int) -> bool:
	pass
	return false


func handle_mouse(camera: Camera3D, event: InputEvent) -> int:
	terrain_hovered = false
	var terrain: MarchingSquaresTerrain = EditorInterface.get_selection().get_selected_nodes()[0]
	
	var editor_viewport = EditorInterface.get_editor_viewport_3d()
	var mouse_pos = editor_viewport.get_mouse_position()	
	
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var shift_held = Input.is_key_pressed(KEY_SHIFT)
	
	# If not in a settings mode, perform terrain raycast
	if mode == TerrainToolMode.BRUSH or mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.LEVEL or mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.BRIDGE or mode == TerrainToolMode.VERTEX_PAINTING or mode == TerrainToolMode.DEBUG_BRUSH:
		var draw_position
		var draw_area_hovered: bool = false
		
		if is_setting and draw_height_set:
			var local_ray_dir = ray_dir * terrain.transform
			var set_plane = Plane(Vector3(local_ray_dir.x, 0, local_ray_dir.z), base_position)
			var set_position = set_plane.intersects_ray(terrain.to_local(ray_origin), local_ray_dir)
			if set_position:
				brush_position = set_position
		
		# If there is any pattern and flatten is enabled, draw along that height plane instead of the terrain intersection
		elif not current_draw_pattern.is_empty() and flatten:
			var chunk_plane = Plane(Vector3.UP, Vector3(0, draw_height, 0))
			draw_position = chunk_plane.intersects_ray(ray_origin, ray_dir)
			if draw_position:
				draw_position = terrain.to_local(draw_position)
				draw_area_hovered = true
		
		else:
			# Perform the raycast to check for intersection with a physics body (terrain)
			var space_state = camera.get_world_3d().direct_space_state
			var ray_length := 10000.0  # Adjust ray length as needed
			var end := ray_origin + ray_dir * ray_length
			var collision_mask = 16 # only terrain
			var query := PhysicsRayQueryParameters3D.create(ray_origin, end, collision_mask)
			var result = space_state.intersect_ray(query)
			if result:
				draw_position = terrain.to_local(result.position)
				draw_area_hovered = true
			else:
				# FALLBACK: If we didn't hit a chunk, project onto a virtual plane at draw_height
				# This allows painting onto chunks while the mouse is in "negative space"
				var virtual_plane = Plane(Vector3.UP, Vector3(0, draw_height, 0))
				var plane_pos = virtual_plane.intersects_ray(ray_origin, ray_dir)
				if plane_pos:
					draw_position = terrain.to_local(plane_pos)
					draw_area_hovered = true
		
		# ALT to clear the current draw pattern. Don't clear while setting
		if Input.is_key_pressed(KEY_ALT) and not is_setting:
			current_draw_pattern.clear()
		
		# Check for terrain collision
		if draw_area_hovered:
			terrain_hovered = true
			var chunk_x: int = floor(draw_position.x / (terrain.dimensions.x * terrain.cell_size.x))
			var chunk_z: int = floor(draw_position.z / (terrain.dimensions.z * terrain.cell_size.y))
			var chunk_coords = Vector2i(chunk_x, chunk_z)
			
			is_chunk_plane_hovered = true
			current_hovered_chunk = chunk_coords
		
		if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if event.is_pressed() and draw_area_hovered:
				draw_height_set = false
				if mode == TerrainToolMode.BRIDGE and not is_making_bridge:
					flatten = false
					is_making_bridge = true
					bridge_start_pos = brush_position
				if mode == TerrainToolMode.SMOOTH and falloff == false:
					falloff = true
				if (mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.DEBUG_BRUSH) and falloff == true:
					falloff = false
				if (mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.VERTEX_PAINTING or mode == TerrainToolMode.DEBUG_BRUSH) and flatten == true:
					flatten = false
				if mode == TerrainToolMode.LEVEL and Input.is_key_pressed(KEY_CTRL):
					height = brush_position.y
				elif Input.is_key_pressed(KEY_SHIFT):
					is_drawing = true
					brush_position = draw_position
				else:
					is_setting = true
					if not flatten:
						draw_height = draw_position.y
			elif event.is_released():
				if is_making_bridge:
					is_making_bridge = false
				if is_drawing:
					is_drawing = false
					if mode == TerrainToolMode.GRASS_MASK or mode == TerrainToolMode.LEVEL or mode == TerrainToolMode.BRIDGE or mode == TerrainToolMode.DEBUG_BRUSH:
						draw_pattern(terrain)
						current_draw_pattern.clear()
					if mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.VERTEX_PAINTING:
						current_draw_pattern.clear()
				if is_setting:
					is_setting = false
					draw_pattern(terrain)
					if Input.is_key_pressed(KEY_SHIFT):
						draw_height = brush_position.y
					else:
						current_draw_pattern.clear()
			gizmo_plugin.terrain_gizmo._redraw()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# Adjust brush size
		if event is InputEventMouseButton and Input.is_key_pressed(KEY_SHIFT):
			var factor: float = event.factor if event.factor else 1
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				brush_size += 0.5 * factor
				if brush_size > 50:
					brush_size = 50
				gizmo_plugin.terrain_gizmo._redraw()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				brush_size -= 0.5 * factor
				if brush_size < 1:
					brush_size = 1
				gizmo_plugin.terrain_gizmo._redraw()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		if draw_area_hovered and event is InputEventMouseMotion:
			brush_position = draw_position
			if is_drawing and (mode == TerrainToolMode.SMOOTH or mode == TerrainToolMode.VERTEX_PAINTING or mode == TerrainToolMode.GRASS_MASK):
				draw_pattern(terrain)
				current_draw_pattern.clear()
		
		gizmo_plugin.terrain_gizmo._redraw()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Check for hovering over/clicking a new chunk
	var chunk_plane = Plane(Vector3.UP, Vector3.ZERO)
	var intersection = chunk_plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection:
		var chunk_x: int = floor(intersection.x / (terrain.dimensions.x * terrain.cell_size.x))
		var chunk_z: int = floor(intersection.z / (terrain.dimensions.z * terrain.cell_size.y))
		var chunk_coords = Vector2i(chunk_x, chunk_z)
		var chunk = terrain.chunks.get(chunk_coords)
		
		current_hovered_chunk = chunk_coords
		is_chunk_plane_hovered = true
		
		# On click, add or remove chunk if in chunk_management mode
		if mode == TerrainToolMode.CHUNK_MANAGEMENT and event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			# Remove chunk
			if chunk:
				var removed_chunk = terrain.chunks[chunk_coords]
				get_undo_redo().create_action("remove chunk")
				get_undo_redo().add_do_method(terrain, "remove_chunk_from_tree", chunk_x, chunk_z)
				get_undo_redo().add_undo_method(terrain, "add_chunk", chunk_coords, removed_chunk)
				get_undo_redo().commit_action()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			
			# Add new chunk
			elif not chunk:
				# Can add a new chunk here if there is a neighbouring non-empty chunk
				# Also add if there are no chunks at all in the current terrain system
				var can_add_empty: bool = terrain.chunks.is_empty() or terrain.has_chunk(chunk_x-1, chunk_z) or terrain.has_chunk(chunk_x+1, chunk_z) or terrain.has_chunk(chunk_x, chunk_z-1) or terrain.has_chunk(chunk_x, chunk_z+1)
				if can_add_empty:
					get_undo_redo().create_action("add chunk")
					get_undo_redo().add_do_method(terrain, "add_new_chunk", chunk_x, chunk_z)
					get_undo_redo().add_undo_method(terrain, "remove_chunk", chunk_x, chunk_z)
					get_undo_redo().commit_action()
					return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		gizmo_plugin.terrain_gizmo._redraw()
	else:
		is_chunk_plane_hovered = false
	
	# Consume clicks but allow other click / mouse motion types to reach the gui, for camera movement, etc	
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func draw_pattern(terrain: MarchingSquaresTerrain):
	var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
	
	var pattern = {}
	var pattern_cc = {}
	var restore_pattern = {}
	var restore_pattern_cc = {}
	
	
	# Ensure points on both sides of chunk borders are updated
	var first_chunk = null
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		if first_chunk == null:
			first_chunk = draw_chunk_coords
		pattern[draw_chunk_coords] = {}
		restore_pattern[draw_chunk_coords] = {}
		pattern_cc[draw_chunk_coords] = {}
		restore_pattern_cc[draw_chunk_coords] = {}
		var draw_chunk_dict = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.001, 0.999)
			var restore_value
			var draw_value
			var restore_value_cc
			var draw_value_cc
			if mode == TerrainToolMode.GRASS_MASK:
				restore_value = chunk.get_grass_mask(draw_cell_coords)
				draw_value = Color(0.0, 0.0, 0.0, 0.0) if should_mask_grass else Color(1.0, 0.0, 0.0, 0.0)
			elif mode == TerrainToolMode.LEVEL:
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = lerp(restore_value, height, sample)
			elif mode == TerrainToolMode.SMOOTH:
				var heights : Array[float] = []
				
				for dc in draw_chunk_dict.keys():
					var _chunk = terrain.chunks[draw_chunk_coords]
					heights.append(_chunk.get_height(dc))
				
				var avg_height := 0.0
				for h in heights:
					avg_height += h
				avg_height /= heights.size()
				
				for dc in draw_chunk_dict.keys():
					var _chunk = terrain.chunks[draw_chunk_coords]
					restore_value = _chunk.get_height(dc)
					
					var f = sample * strength
					draw_value = lerp(restore_value, avg_height, f)
					
					restore_pattern[draw_chunk_coords][dc] = restore_value
					pattern[draw_chunk_coords][dc] = draw_value
			elif mode == TerrainToolMode.BRIDGE:
				var b_end := Vector2(brush_position.x, brush_position.z)
				var b_start := Vector2(bridge_start_pos.x, bridge_start_pos.z)
				var bridge_length := (b_end - b_start).length()
				if bridge_length < 0.5 or draw_chunk_dict.size() < 3: # Skip small bridges so the terrain doesn't glitch
					continue
				
				# Convert cell to world-space
				var global_cell := Vector2(
					(draw_chunk_coords.x * terrain.dimensions.x + draw_cell_coords.x) * terrain.cell_size.x,
					(draw_chunk_coords.y * terrain.dimensions.z + draw_cell_coords.y) * terrain.cell_size.y)
				
				if draw_chunk_coords != first_chunk:
					global_cell.x += (first_chunk.x - draw_chunk_coords.x) * 2
				if draw_chunk_coords != first_chunk:
					global_cell.y += (first_chunk.y - draw_chunk_coords.y) * 2
				
				# Calculate the 2D bridge direction vector
				var bridge_dir := (b_end - b_start) / bridge_length
				var cell_vec := global_cell - b_start
				var linear_offset := cell_vec.dot(bridge_dir)
				var progress := clamp(linear_offset / bridge_length, 0.0, 1.0)
				
				if ease_value != -1.0:
					progress = ease(progress, ease_value)
				var bridge_height = lerpf(bridge_start_pos.y, brush_position.y, progress)
				
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = bridge_height
			elif mode == TerrainToolMode.VERTEX_PAINTING:
				if paint_walls_mode:
					restore_value = chunk.get_wall_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_wall_color_1(draw_cell_coords)
				else:
					restore_value = chunk.get_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_color_1(draw_cell_coords)
				draw_value = vertex_color_0
				draw_value_cc = vertex_color_1
			elif mode == TerrainToolMode.DEBUG_BRUSH:
				var g_pos := chunk.to_global(Vector3(float(draw_cell_coords.x), chunk.get_height(draw_cell_coords), float(draw_cell_coords.y)))
				var normal := get_cell_normal(chunk, draw_cell_coords)
				print("DEBUG INFO: global pos = " + str(g_pos) +
					", color id = " + str(chunk.get_color_0(draw_cell_coords)) + " " + str(chunk.get_color_1(draw_cell_coords)) +
					", normal = " + str(normal))
				continue
			else: # Brush tool
				restore_value = chunk.get_height(draw_cell_coords)
				if flatten:
					draw_value = lerp(restore_value, brush_position.y, sample)
				else:
					var height_diff = brush_position.y - draw_height
					draw_value = lerp(restore_value, restore_value + height_diff, sample)
			
			restore_pattern[draw_chunk_coords][draw_cell_coords] = restore_value
			pattern[draw_chunk_coords][draw_cell_coords] = draw_value
			if mode == TerrainToolMode.VERTEX_PAINTING:
				restore_pattern_cc[draw_chunk_coords][draw_cell_coords] = restore_value_cc
				pattern_cc[draw_chunk_coords][draw_cell_coords] = draw_value_cc
	if mode == TerrainToolMode.DEBUG_BRUSH:
		return
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		var draw_chunk_dict = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var sample: float = clamp(draw_chunk_dict[draw_cell_coords], 0.001, 0.999)
			for cx in range(-1, 2):
				for cz in range(-1, 2):
					if (cx == 0 and cz == 0):
						continue
					
					var adjacent_chunk_coords = Vector2i(draw_chunk_coords.x + cx, draw_chunk_coords.y + cz)
					if not terrain.chunks.has(adjacent_chunk_coords):
						continue
					
					var x: int = draw_cell_coords.x
					var z: int = draw_cell_coords.y
					
					if cx == -1:
						if x == 0: x = terrain.dimensions.x-1
						else: continue
					elif cx == 1:
						if x == terrain.dimensions.x-1: x = 0
						else: continue
					
					if cz == -1:
						if z == 0: z = terrain.dimensions.z-1
						else: continue
					elif cz == 1:
						if z == terrain.dimensions.z-1: z = 0
						else: continue
					
					var adjacent_cell_coords := Vector2i(x, z)
					
					if not pattern.has(adjacent_chunk_coords):
						pattern[adjacent_chunk_coords] = {}
					if not restore_pattern.has(adjacent_chunk_coords):
						restore_pattern[adjacent_chunk_coords] = {}
					
					var draw_value_cc
					var restore_value_cc
					if mode == TerrainToolMode.VERTEX_PAINTING:
						if not pattern_cc.has(adjacent_chunk_coords):
							pattern_cc[adjacent_chunk_coords] = {}
						if not restore_pattern_cc.has(adjacent_chunk_coords):
							restore_pattern_cc[adjacent_chunk_coords] = {}
						draw_value_cc = pattern_cc[draw_chunk_coords][draw_cell_coords]
						restore_value_cc = restore_pattern_cc[draw_chunk_coords][draw_cell_coords]
					
					var draw_value = pattern[draw_chunk_coords][draw_cell_coords]
					var restore_value = restore_pattern[draw_chunk_coords][draw_cell_coords]
					
					var adj_draw_value
					var adj_draw_value_cc
					if current_draw_pattern.has(adjacent_chunk_coords) and current_draw_pattern[adjacent_chunk_coords].has(adjacent_cell_coords) and current_draw_pattern[adjacent_chunk_coords][adjacent_cell_coords] > sample:
						adj_draw_value = pattern[adjacent_chunk_coords][adjacent_cell_coords]
						if mode == TerrainToolMode.VERTEX_PAINTING:
							adj_draw_value_cc = pattern_cc[adjacent_chunk_coords][adjacent_cell_coords]
					else:
						adj_draw_value = draw_value
						if mode == TerrainToolMode.VERTEX_PAINTING:
							adj_draw_value_cc = draw_value_cc
					
					pattern[adjacent_chunk_coords][adjacent_cell_coords] = adj_draw_value
					restore_pattern[adjacent_chunk_coords][adjacent_cell_coords] = restore_value
					if mode == TerrainToolMode.VERTEX_PAINTING:
						pattern_cc[adjacent_chunk_coords][adjacent_cell_coords] = adj_draw_value_cc
						restore_pattern_cc[adjacent_chunk_coords][adjacent_cell_coords] = restore_value_cc
	
	if mode == TerrainToolMode.VERTEX_PAINTING:
		# Standard 2D painting (ground or walls)
		# Create ONE composite action instead of 2 separate actions
		# Use wall_color keys when painting walls, color keys when painting ground
		var color_key_0 := "wall_color_0" if paint_walls_mode else "color_0"
		var color_key_1 := "wall_color_1" if paint_walls_mode else "color_1"
		var do_patterns := {
			color_key_0: pattern,
			color_key_1: pattern_cc
		}
		var undo_patterns := {
			color_key_0: restore_pattern,
			color_key_1: restore_pattern_cc
		}
		
		var action_name := "terrain wall paint" if paint_walls_mode else "terrain vertex paint"
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
		undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
		undo_redo.commit_action()
	elif mode == TerrainToolMode.GRASS_MASK:
		undo_redo.create_action("terrain grass mask draw")
		undo_redo.add_do_method(self, "draw_grass_mask_pattern_action", terrain, pattern)
		undo_redo.add_undo_method(self, "draw_grass_mask_pattern_action", terrain, restore_pattern)
		undo_redo.commit_action()
	else:
		# Handle BRUSH, LEVEL, SMOOTH, BRIDGE modes
		if current_quick_paint:
			# QUICK PAINT MODE: Apply all changes as ONE atomic undo/redo action
			# This fixes the issue where 6 separate actions are 
			_set_vertex_colors(current_quick_paint.wall_texture_slot)
			
			var wall_color_pattern := {}
			var wall_color_pattern_cc := {}
			var wall_color_restore := {}
			var wall_color_restore_cc := {}
			
			# First pass: collect all cells in the pattern
			for chunk_coords in pattern:
				wall_color_pattern[chunk_coords] = {}
				wall_color_pattern_cc[chunk_coords] = {}
				wall_color_restore[chunk_coords] = {}
				wall_color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					wall_color_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
					wall_color_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
					wall_color_pattern[chunk_coords][cell_coords] = vertex_color_0
					wall_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Second pass: expand to adjacent cells (walls appear at boundaries between cells)
			# This ensures uniform wall color by painting adjacent cells that share wall corners
			for chunk_coords in pattern:
				for cell_coords in pattern[chunk_coords]:
					# Check all 8 adjacent cells
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							if dx == 0 and dz == 0:
								continue
							
							var adj_x : int = cell_coords.x + dx
							var adj_z : int = cell_coords.y + dz
							var adj_chunk_coords : Vector2i = chunk_coords
							
							# Handle chunk boundary crossings
							if adj_x < 0:
								adj_chunk_coords = Vector2i(chunk_coords.x - 1, chunk_coords.y)
								adj_x = terrain.dimensions.x - 1
							elif adj_x >= terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >= terrain.dimensions.z:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y + 1)
								adj_z = 0
							
							# Skip if chunk doesn't exist
							if not terrain.chunks.has(adj_chunk_coords):
								continue
							
							var adj_cell := Vector2i(adj_x, adj_z)
							
							# Skip if already in pattern
							if wall_color_pattern.has(adj_chunk_coords) and wall_color_pattern[adj_chunk_coords].has(adj_cell):
								continue
							
							# Add adjacent cell
							if not wall_color_pattern.has(adj_chunk_coords):
								wall_color_pattern[adj_chunk_coords] = {}
								wall_color_pattern_cc[adj_chunk_coords] = {}
								wall_color_restore[adj_chunk_coords] = {}
								wall_color_restore_cc[adj_chunk_coords] = {}
							
							var adj_chunk : MarchingSquaresTerrainChunk = terrain.chunks[adj_chunk_coords]
							wall_color_restore[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_0(adj_cell)
							wall_color_restore_cc[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_1(adj_cell)
							wall_color_pattern[adj_chunk_coords][adj_cell] = vertex_color_0
							wall_color_pattern_cc[adj_chunk_coords][adj_cell] = vertex_color_1
			
			# Build grass mask patterns
			var grass_pattern := {}
			var grass_restore := {}
			for chunk_coords in pattern:
				grass_pattern[chunk_coords] = {}
				grass_restore[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					grass_restore[chunk_coords][cell_coords] = chunk.get_grass_mask(cell_coords)
					if current_quick_paint.has_grass:
						grass_pattern[chunk_coords][cell_coords] = Color(1, 1, 0, 0)
					else:
						grass_pattern[chunk_coords][cell_coords] = Color(0, 0, 0, 0)
			
			# Build ground color patterns
			_set_vertex_colors(current_quick_paint.ground_texture_slot)
			
			var color_pattern := {}
			var color_pattern_cc := {}
			var color_restore := {}
			var color_restore_cc := {}
			
			for chunk_coords in pattern:
				color_pattern[chunk_coords] = {}
				color_pattern_cc[chunk_coords] = {}
				color_restore[chunk_coords] = {}
				color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					color_restore[chunk_coords][cell_coords] = chunk.get_color_0(cell_coords)
					color_restore_cc[chunk_coords][cell_coords] = chunk.get_color_1(cell_coords)
					color_pattern[chunk_coords][cell_coords] = vertex_color_0
					color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Create ONE composite action instead of 6 separate actions
			var do_patterns := {
				"height": pattern,
				"wall_color_0": wall_color_pattern,
				"wall_color_1": wall_color_pattern_cc,
				"grass_mask": grass_pattern,
				"color_0": color_pattern,
				"color_1": color_pattern_cc
			}
			var undo_patterns := {
				"height": restore_pattern,
				"wall_color_0": wall_color_restore,
				"wall_color_1": wall_color_restore_cc,
				"grass_mask": grass_restore,
				"color_0": color_restore,
				"color_1": color_restore_cc
			}
			
			undo_redo.create_action("terrain brush with quick paint")
			undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
			undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
			undo_redo.commit_action()
		else:
			# NON-QUICK PAINT MODE: Apply height + default wall texture
			# Use the terrain's default_wall_texture for wall colors
			_set_vertex_colors(terrain.default_wall_texture)
			
			var wall_color_pattern := {}
			var wall_color_pattern_cc := {}
			var wall_color_restore := {}
			var wall_color_restore_cc := {}
			
			# First pass: collect all cells in the pattern
			for chunk_coords in pattern:
				wall_color_pattern[chunk_coords] = {}
				wall_color_pattern_cc[chunk_coords] = {}
				wall_color_restore[chunk_coords] = {}
				wall_color_restore_cc[chunk_coords] = {}
				var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
				for cell_coords in pattern[chunk_coords]:
					wall_color_restore[chunk_coords][cell_coords] = chunk.get_wall_color_0(cell_coords)
					wall_color_restore_cc[chunk_coords][cell_coords] = chunk.get_wall_color_1(cell_coords)
					wall_color_pattern[chunk_coords][cell_coords] = vertex_color_0
					wall_color_pattern_cc[chunk_coords][cell_coords] = vertex_color_1
			
			# Second pass: expand to adjacent cells (walls appear at boundaries between cells)
			for chunk_coords in pattern:
				for cell_coords in pattern[chunk_coords]:
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							if dx == 0 and dz == 0:
								continue
							
							var adj_x : int = cell_coords.x + dx
							var adj_z : int = cell_coords.y + dz
							var adj_chunk_coords : Vector2i = chunk_coords
							
							if adj_x < 0:
								adj_chunk_coords = Vector2i(chunk_coords.x - 1, chunk_coords.y)
								adj_x = terrain.dimensions.x - 1
							elif adj_x >= terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >= terrain.dimensions.z:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y + 1)
								adj_z = 0
							
							if not terrain.chunks.has(adj_chunk_coords):
								continue
							
							var adj_cell := Vector2i(adj_x, adj_z)
							
							if wall_color_pattern.has(adj_chunk_coords) and wall_color_pattern[adj_chunk_coords].has(adj_cell):
								continue
							
							if not wall_color_pattern.has(adj_chunk_coords):
								wall_color_pattern[adj_chunk_coords] = {}
								wall_color_pattern_cc[adj_chunk_coords] = {}
								wall_color_restore[adj_chunk_coords] = {}
								wall_color_restore_cc[adj_chunk_coords] = {}
							
							var adj_chunk : MarchingSquaresTerrainChunk = terrain.chunks[adj_chunk_coords]
							wall_color_restore[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_0(adj_cell)
							wall_color_restore_cc[adj_chunk_coords][adj_cell] = adj_chunk.get_wall_color_1(adj_cell)
							wall_color_pattern[adj_chunk_coords][adj_cell] = vertex_color_0
							wall_color_pattern_cc[adj_chunk_coords][adj_cell] = vertex_color_1
			
			# Create composite action with height + wall colors
			var do_patterns := {
				"height": pattern,
				"wall_color_0": wall_color_pattern,
				"wall_color_1": wall_color_pattern_cc
			}
			var undo_patterns := {
				"height": restore_pattern,
				"wall_color_0": wall_color_restore,
				"wall_color_1": wall_color_restore_cc
			}
			
			undo_redo.create_action("terrain height draw")
			undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
			undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
			undo_redo.commit_action()


# For each cell in pattern, raise/lower by y delta
func draw_height_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var height: float = draw_chunk_dict[draw_cell_coords]
			chunk.draw_height(draw_cell_coords.x, draw_cell_coords.y, height)
		chunk.regenerate_mesh()


func draw_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color: Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color: Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_grass_mask_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var mask: Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_grass_mask(draw_cell_coords.x, draw_cell_coords.y, mask)
		chunk.regenerate_mesh()


func draw_wall_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color: Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_wall_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk: MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color: Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


# Applies all terrain patterns  (for quick paint brush and vertex painting operations)
func apply_composite_pattern_action(terrain: MarchingSquaresTerrain, patterns: Dictionary) -> void:
	var affected_chunks : Dictionary = {}  # chunk_coords -> chunk reference
	
	var composite_disabled := false
	if mode == TerrainToolMode.SMOOTH and current_quick_paint == null:
		composite_disabled = true
	
	# Apply wall colors FIRST (before height changes that create ridge vertices)
	if patterns.has("wall_color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_0:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_0[chunk_coords]:
					chunk.draw_wall_color_0(cell_coords.x, cell_coords.y, patterns.wall_color_0[chunk_coords][cell_coords])
	
	if patterns.has("wall_color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_1:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_1[chunk_coords]:
					chunk.draw_wall_color_1(cell_coords.x, cell_coords.y, patterns.wall_color_1[chunk_coords][cell_coords])
	
	# Apply height changes (triggers ridge creation which uses wall colors)
	if patterns.has("height"):
		for chunk_coords: Vector2i in patterns.height:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.height[chunk_coords]:
					chunk.draw_height(cell_coords.x, cell_coords.y, patterns.height[chunk_coords][cell_coords])
	
	# Apply grass mask
	if patterns.has("grass_mask") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.grass_mask:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.grass_mask[chunk_coords]:
					chunk.draw_grass_mask(cell_coords.x, cell_coords.y, patterns.grass_mask[chunk_coords][cell_coords])
	
	# Apply ground colors LAST
	if patterns.has("color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_0:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_0[chunk_coords]:
					chunk.draw_color_0(cell_coords.x, cell_coords.y, patterns.color_0[chunk_coords][cell_coords])
	
	if patterns.has("color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_1:
			var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_1[chunk_coords]:
					chunk.draw_color_1(cell_coords.x, cell_coords.y, patterns.color_1[chunk_coords][cell_coords])
	
	# Regenerate mesh ONCE for each affected chunk (instead of 6 times!)
	for chunk in affected_chunks.values():
		chunk.regenerate_mesh()


func _set_vertex_colors(vc_idx: int) -> void:
	match vc_idx:
		0: #rr
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		1: #rg
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		2: #rb
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		3: #ra
			vertex_color_0 = Color(1.0, 0.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		4: #gr
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		5: #gg
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		6: #gb
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		7: #ga
			vertex_color_0 = Color(0.0, 1.0, 0.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		8: #br
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		9: #bg
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		10: #bb
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		11: #ba
			vertex_color_0 = Color(0.0, 0.0, 1.0, 0.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)
		12: #ar
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(1.0, 0.0, 0.0, 0.0)
		13: #ag
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 1.0, 0.0, 0.0)
		14: #ab
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 0.0, 1.0, 0.0)
		15: #aa
			vertex_color_0 = Color(0.0, 0.0, 0.0, 1.0)
			vertex_color_1 = Color(0.0, 0.0, 0.0, 1.0)


func _set_new_textures(_preset: MarchingSquaresTexturePreset) -> void:
	if _preset == null:
		_preset = EMPTY_TEXTURE_PRESET.duplicate()
	
	# Set BatchUpdate flag to avoid indivudal setters triggering updates
	current_terrain_node.is_batch_updating = true
	
	for i in range(5): # The range is 5 because MarchingSquaresTextureList has 5 export variables (terrain textures, texture scales, grass sprites, grass colors, has_grass)
		match i:
			0: # terrain_textures (unified for both floor and wall painting)
				for i_tex in range(_preset.new_textures.terrain_textures.size()):
					var tex : Texture2D = _preset.new_textures.terrain_textures[i_tex]
					match i_tex:
						0:
							current_terrain_node.ground_texture = tex
						1:
							current_terrain_node.texture_2 = tex
						2:
							current_terrain_node.texture_3 = tex
						3:
							current_terrain_node.texture_4 = tex
						4:
							current_terrain_node.texture_5 = tex
						5:
							current_terrain_node.texture_6 = tex
						6:
							current_terrain_node.texture_7 = tex
						7:
							current_terrain_node.texture_8 = tex
						8:
							current_terrain_node.texture_9 = tex
						9:
							current_terrain_node.texture_10 = tex
						10:
							current_terrain_node.texture_11 = tex
						11:
							current_terrain_node.texture_12 = tex
						12:
							current_terrain_node.texture_13 = tex
						13:
							current_terrain_node.texture_14 = tex
						14: # texture_15 is reserved for VOID
							current_terrain_node.texture_15 = tex
			1: # texture_scales
				for i_tex_scale in range(_preset.new_textures.texture_scales.size()):
					var scale : float = _preset.new_textures.texture_scales[i_tex_scale]
					match i_tex_scale:
						0:
							current_terrain_node.texture_scale_1 = scale
						1:
							current_terrain_node.texture_scale_2 = scale
						2:
							current_terrain_node.texture_scale_3 = scale
						3:
							current_terrain_node.texture_scale_4 = scale
						4:
							current_terrain_node.texture_scale_5 = scale
						5:
							current_terrain_node.texture_scale_6 = scale
						6:
							current_terrain_node.texture_scale_7 = scale
						7:
							current_terrain_node.texture_scale_8 = scale
						8:
							current_terrain_node.texture_scale_9 = scale
						9:
							current_terrain_node.texture_scale_10 = scale
						10:
							current_terrain_node.texture_scale_11 = scale
						11:
							current_terrain_node.texture_scale_12 = scale
						12:
							current_terrain_node.texture_scale_13 = scale
						13:
							current_terrain_node.texture_scale_14 = scale
						14:
							current_terrain_node.texture_scale_15 = scale
			2: # grass_sprites
				for i_grass_tex in range(_preset.new_textures.grass_sprites.size()):
					var tex : Texture2D = _preset.new_textures.grass_sprites[i_grass_tex]
					if tex == null:
						continue
					match i_grass_tex:
						0:
							current_terrain_node.grass_sprite = tex
						1:
							current_terrain_node.grass_sprite_tex_2 = tex
						2:
							current_terrain_node.grass_sprite_tex_3 = tex
						3:
							current_terrain_node.grass_sprite_tex_4 = tex
						4:
							current_terrain_node.grass_sprite_tex_5 = tex
						5:
							current_terrain_node.grass_sprite_tex_6 = tex
			3: # grass_colors
				for i_grass_col in range(_preset.new_textures.grass_colors.size()):
					var col : Color = _preset.new_textures.grass_colors[i_grass_col]
					if col == null:
						continue
					match i_grass_col:
						0:
							current_terrain_node.ground_color = col
						1:
							current_terrain_node.ground_color_2 = col
						2:
							current_terrain_node.ground_color_3 = col
						3:
							current_terrain_node.ground_color_4 = col
						4:
							current_terrain_node.ground_color_5 = col
						5:
							current_terrain_node.ground_color_6 = col
			4: # has_grass
				for i_has_grass in range(_preset.new_textures.has_grass.size()):
					var val : bool = _preset.new_textures.has_grass[i_has_grass]
					match i_has_grass:
						0:
							current_terrain_node.tex2_has_grass = val
						1:
							current_terrain_node.tex3_has_grass = val
						2:
							current_terrain_node.tex4_has_grass = val
						3:
							current_terrain_node.tex5_has_grass = val
						4:
							current_terrain_node.tex6_has_grass = val
	
	vp_texture_names.texture_names = _preset.new_tex_names.texture_names
	
	# Apply a batch update
	current_terrain_node.force_batch_update()
	
	# Mark scene as modified so user knows to save
	EditorInterface.mark_scene_as_unsaved()
	
	# Store current preset
	current_terrain_node.current_texture_preset = _preset
	
	# Set batch update to false, to allow setters to work individually
	current_terrain_node.is_batch_updating = false
	
	# Ensure the Editor is updated live (trick it to redraw - There might be an easier way but this works)
	EditorInterface.inspect_object(current_terrain_node)


func get_cell_normal(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Vector3:
	var h_c := chunk.get_height(cell)
	
	var x0 := max(cell.x - 1, 0)
	var x1 := min(cell.x + 1, chunk.dimensions.x - 1)
	var y0 := max(cell.y - 1, 0)
	var y1 := min(cell.y + 1, chunk.dimensions.y - 1)
	
	var h_left := chunk.get_height(Vector2i(x0, cell.y))
	var h_right := chunk.get_height(Vector2i(x1, cell.y))
	var h_below := chunk.get_height(Vector2i(cell.x, y0))
	var h_above := chunk.get_height(Vector2i(cell.x, y1))
	
	var sx := (h_right - h_left) / (2.0 * current_terrain_node.cell_size.x)
	var sz := (h_above - h_below) / (2.0 * current_terrain_node.cell_size.y)
	
	var normal := Vector3(-sx, 1.0, -sz).normalized()
	return normal
