@tool
extends EditorPlugin
class_name MarchingSquaresTerrainPlugin


static var instance : MarchingSquaresTerrainPlugin


const MAX_TEXTURE_SLOTS := 256
const MSTVertexColorHelper = preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")

# Vertex Paint dither: solid core + dithered outer ring.
const VP_DITHER_CORE_SAMPLE := 0.8


static func _ensure_texture_names_resource(res: Resource) -> void:
	if res == null:
		return
	var names := res.get("texture_names")
	if not (names is Array):
		names = []
	# Seed defaults if empty.
	if names.is_empty():
		names = [
			"Texture 1", "Texture 2", "Texture 3", "Texture 4",
			"Texture 5", "Texture 6", "Texture 7", "Texture 8",
			"Texture 9", "Texture 10", "Texture 11", "Texture 12",
			"Texture 13", "Texture 14", "Texture 15", "Void",
		]
	# Extend/truncate to MAX_TEXTURE_SLOTS.
	if names.size() < MAX_TEXTURE_SLOTS:
		for i in range(names.size(), MAX_TEXTURE_SLOTS):
			if i == 15:
				names.append("Void")
			elif i > 15:
				names.append("Texture %d" % i)
			else:
				names.append("Texture %d" % (i + 1))
	elif names.size() > MAX_TEXTURE_SLOTS:
		names.resize(MAX_TEXTURE_SLOTS)
	
	# Keep the legacy void slot name stable/obvious.
	# (Void is slot 15 internally; UI may display it as "Texture 16" if using 1-based numbering.)
	var VOID_SLOT := 15
	if names.size() > VOID_SLOT:
		names[VOID_SLOT] = "Void"
	if names.size() > 0 and (str(names[0]) == "Base Grass" or str(names[0]) == "Texture 1"):
		names[0] = "Texture 1"
	for i in range(1, min(names.size(), 6)):
		var current := str(names[i])
		if current == "Texture %d (g)" % (i + 1) or current == "Texture %d" % (i + 1):
			names[i] = "Texture %d" % (i + 1)
	for i in range(6, names.size()):
		var expected_old := "Texture %d" % (i + 1)
		var expected_new := "Void" if i == 15 else ("Texture %d" % i if i > 15 else "Texture %d" % (i + 1))
		if str(names[i]) == expected_old or str(names[i]) == expected_new:
			names[i] = expected_new
	
	res.set("texture_names", names)


@onready var EMPTY_TEXTURE_PRESET : MarchingSquaresTexturePreset = EngineWrapper.load_resource("uid://db4scsn2nqqyu") as MarchingSquaresTexturePreset
@onready var BrushPatternCalculator := EngineWrapper.load_resource("uid://bli1mnri3jwpa")

@onready var vp_texture_names : MarchingSquaresTextureNames = EngineWrapper.load_resource("uid://dd7fens03aosa") as MarchingSquaresTextureNames

# Instantiate these lazily in _safe_initialize() to avoid editor-load ordering issues.
const GizmoPluginScript := preload("uid://c4vnjk3ie0whl")
const ToolbarScript := preload("uid://3d77dnetkeik")
const ToolAttributesScript := preload("uid://buxevb44hutjm")

var gizmo_plugin : MarchingSquaresTerrainGizmoPlugin = null
var toolbar : MarchingSquaresToolbar = null
var tool_attributes : MarchingSquaresToolAttributes = null
var active_tool : int = 0

var UI : Script = preload("uid://bmedudg6sllf8")
var ui : MarchingSquaresUI

var is_initialized : bool = false
var initialization_error : String = ""

# Inspector edits to a ShaderMaterial/Shader do not reliably emit a change on
# the terrain effect resource. Track the Inspector directly so post-processing
# is rebuilt while editing, without requiring an effect toggle.
var _post_process_inspector_connected := false
var _post_process_inspector_refresh_queued := false

var current_terrain_node : MarchingSquaresTerrain

var current_heightmap_mesh : Mesh = null
var heightmap_tool_selected_tab : int = 0

var selected_chunk : MarchingSquaresTerrainChunk

# Flag to prevent _set_new_textures() when syncing preset from terrain node
var _syncing_from_terrain : bool = false

#region brush variables
var BrushMode : Dictionary = {
	"0": EngineWrapper.load_resource("uid://cg3lvmu68oaaa"),
	"1": EngineWrapper.load_resource("uid://b6uwsa1vjeb4"),
}

var BrushMat : Dictionary = {
	"0": EngineWrapper.load_resource("uid://dtevocyixqsgv"),
	"1": EngineWrapper.load_resource("uid://daofaifmtbyak"),
}

var current_brush_index : int = 0

var brush_position : Vector3
var brush_surface_normal : Vector3 = Vector3.UP

var BRUSH_VISUAL : Mesh = EngineWrapper.load_resource("uid://ch6cb07rh0m3l") as Mesh
var BRUSH_RADIUS_VISUAL : Mesh = EngineWrapper.load_resource("uid://cg3lvmu68oaaa") as Mesh
var BRUSH_RADIUS_MATERIAL : ShaderMaterial = EngineWrapper.load_resource("uid://dtevocyixqsgv") as ShaderMaterial
@onready var falloff_curve : Curve = EngineWrapper.load_resource("uid://c0bexjsfvvcxb") as Curve
#endregion

#region tool_mode vars
enum TerrainToolMode {
	BRUSH = 0,
	LEVEL = 1,
	SMOOTH = 2,
	BRIDGE = 3,
	GRASS_MASK = 4,
	VERTEX_PAINTING = 5,
	POPULATE = 6,
	DEBUG_BRUSH = 7,
	CHUNK_MANAGEMENT = 8,
	HEIGHTMAP = 9,
	TERRAIN_SETTINGS = 10,
}

enum NavMeshPaintMode { NONE, PAINT, ERASE }

var _mode : TerrainToolMode = TerrainToolMode.BRUSH
var mode : TerrainToolMode:
	get():
		return _mode
	set(value):
		_mode = value
		current_draw_pattern.clear()
		heightmap_pattern_samples.clear()
		_update_falloff_visual()

var navmesh_paint_mode : NavMeshPaintMode = NavMeshPaintMode.NONE
var _navmesh_stroke_undo : Dictionary = {}
var _navmesh_stroke_do : Dictionary = {}
var _navmesh_previous_tool_mode : TerrainToolMode = TerrainToolMode.TERRAIN_SETTINGS


func set_navmesh_paint_mode(value: NavMeshPaintMode) -> void:
	if value != NavMeshPaintMode.NONE and navmesh_paint_mode == NavMeshPaintMode.NONE:
		_navmesh_previous_tool_mode = mode
		navmesh_paint_mode = value
		mode = TerrainToolMode.BRUSH
		if current_terrain_node != null and is_instance_valid(current_terrain_node):
			# Baked scenes may not keep cell geometry in memory until a rebuild.
			# The permission overlay uses that same geometry as the bake path.
			current_terrain_node.navmesh_painting_enabled = true
			current_terrain_node._ensure_nav_chunks_ready_for_bake()
			if gizmo_plugin != null:
				gizmo_plugin.trigger_redraw(current_terrain_node)
	elif value == NavMeshPaintMode.NONE and navmesh_paint_mode != NavMeshPaintMode.NONE:
		navmesh_paint_mode = value
		mode = _navmesh_previous_tool_mode
	else:
		navmesh_paint_mode = value


func deactivate_navmesh_paint_mode() -> void:
	if navmesh_paint_mode == NavMeshPaintMode.NONE:
		return
	_commit_navmesh_stroke(current_terrain_node)
	set_navmesh_paint_mode(NavMeshPaintMode.NONE)
	is_drawing = false
	is_erasing = false
	is_setting = false
	current_draw_pattern.clear()
	if current_terrain_node != null and gizmo_plugin != null:
		gizmo_plugin.trigger_redraw(current_terrain_node)
#endregion

#region tool attribute vars
# Tool attribute variables
var brush_size : float = 15.0
var ease_value : float = -1.0 # No ease
var strength : float = 1.0
var height : float = 0.0
var flatten : bool = true
var falloff : bool = true

enum VertexPaintFalloffMode {
	HARD = 0,
	DITHERED = 1,
}
var _vp_falloff_mode : int = VertexPaintFalloffMode.HARD
var vp_falloff_mode : int:
	get():
		return _vp_falloff_mode
	set(value):
		_vp_falloff_mode = clampi(int(value), 0, 1)
		_update_falloff_visual()

var curve3d_mode : bool = false
var should_mask_grass : bool = false

# Used to reference populator data in the populator tool
var current_populator : MarchingSquaresPopulator = null

var remove_selection : bool = false

# Currently selected preset for vertex textures (DOES change the global terrain)
var _current_texture_preset : MarchingSquaresTexturePreset = EMPTY_TEXTURE_PRESET
var current_texture_preset : MarchingSquaresTexturePreset:
	get():
		return _current_texture_preset
	set(value):
		if value == null:
			value = EMPTY_TEXTURE_PRESET
		_current_texture_preset = value
		#current_quick_paint = null
		if not _syncing_from_terrain:
			_set_new_textures(value)

# Currently selected preset for quick painting (does NOT change the global terrain)
var current_quick_paint : MarchingSquaresQuickPaint = null

# Toggle for painting walls vs ground in VERTEX_PAINTING mode
var _paint_walls_mode : bool = false
var paint_walls_mode : bool:
	get():
		return _paint_walls_mode
	set(value):
		_paint_walls_mode = value

var _vertex_color_idx : int = 0
#endregion

#region heightmap importer vars
var hm_heightmap_image : Texture2D = null
var hm_grass_image : Texture2D = null
var hm_texture_image : Texture2D = null
var hm_chunks_x : int = 4
var hm_chunks_z : int = 4
var hm_max_height : int = 32
var hm_merge_mode : int = 1
var hm_single_file_import : bool = false
var hm_combined_image : Texture2D = null
#endregion

#region heightmap exporter vars
var hme_export_heightmap : bool = true
var hme_export_grass : bool = true
var hme_export_texture_index : bool = false
var hme_output_path : String = "res://"
var hme_single_file : bool = false
#endregion

#region heightmap library vars
const MESH_HEIGHTMAPS_FOLDER_PATH : String = "res://addons/MarchingSquaresTerrain/resources/mesh_heightmaps/"
var current_heightmap_image : Image
var can_place_heightmaps : bool = false
# Heightmap intensity captured per selected terrain cell. Keeping the sampled
# values with the selection lets a stroke accumulate without later mouse motion
# sliding one stamp across the entire retained pattern.
var heightmap_pattern_samples : Dictionary = {}
#endregion

var vertex_color_idx : int = 0:
	set(value):
		_vertex_color_idx = value
		_set_vertex_colors(value)
var vertex_color_0 : Color = Color(1.0, 0.0, 0.0, 0.0)
var vertex_color_1 : Color = Color(1.0, 0.0, 0.0, 0.0)
#endregion

#region draw-related vars
# A dictionary with keys for each tile that is currently being drawn to with the brush
# In brush mode, the value is the height that preview was drawn to, aka the height BEFORE it is set
# In ground texture mode, the value is the color of the point BEFORE the draw
var current_draw_pattern : Dictionary

var terrain_hovered : bool
var is_chunk_plane_hovered : bool
var current_hovered_chunk : Vector2i
var curve3d_bridge_points : PackedVector3Array
var last_bridge_point : Vector3

# True if the mouse is currently held down to draw
var is_drawing : bool
# True if the mouse is held down with Ctrl to remove cells from the current draw pattern
var is_erasing : bool
var chunk_batch_dragging := false
var chunk_batch_drag_removing := false
var chunk_batch_drag_start := Vector2i.ZERO
var chunk_batch_drag_end := Vector2i.ZERO

# When the brush draws, if the gizmo sees the draw height is not set, it will set the draw height
var draw_height_set : bool

# Height of the current pattern that is being drawn at for the brush tool
var draw_height : float
var _wall_paint_stroke_active : bool = false
var _wall_paint_stroke_undo_states : Dictionary = {}
var _wall_paint_stroke_do_states : Dictionary = {}
var _wall_paint_stroke_dirty_chunks : Dictionary = {}
var _wall_paint_last_stamp_position : Vector3 = Vector3.ZERO
var _wall_paint_has_last_stamp_position : bool = false

# Is set to true when the user clicks on a tile that is part of the current draw pattern, will enter heightdrag setting mode
var is_setting : bool

# Variable for keeping the brush tool static when restarting the plugin
var _is_reselecting : bool = false

var is_making_bridge : bool
var bridge_start_pos : Vector3
var bridge_start_chunk_coords : Vector2i

# The point where the height drag started
var base_position : Vector3
#endregion

var terrain_heightmap_folder_name : String = "new_terrain_heightmap"
var mesh_heightmap_name : String = "new_mesh_heightmap"

#region raycast variables
# Use script-wide variables to provide data to the physics process function
var raycast_queued := false
var ray_origin : Vector3
var ray_dir : Vector3
var ray_camera : Camera3D
var queued_ray_result := {}
#endregion


func _enter_tree():
	instance = self
	# texture_names.tres is used for dropdown enums; but in-editor it can load as a
	# PlaceholderResource (scripts not loaded yet). Avoid calling methods on it.
	_ensure_texture_names_resource(vp_texture_names)
	call_deferred("_deferred_enter_tree")
	
	print_rich("Welcome to [color=MEDIUM_ORCHID][url=https://www.youtube.com/@yugen_seishin]Yūgen[/url][/color]'s [wave]Marching Squares Terrain Authoring Toolkit[/wave]\nThis plugin is under MIT license")


func _deferred_enter_tree() -> void:
	if not _safe_initialize():
		push_error("Failed to initialize plugin: " + initialization_error)
	else:
		print_verbose("[MarchingSquaresTerrainPlugin] initialized succesfully!")


func _safe_initialize() -> bool:
	if is_initialized:
		return true
	
	if not EngineWrapper.instance.is_editor():
		initialization_error = "Plugin was initialized during runtime"
		return false
	
	if not EditorInterface:
		initialization_error = "No EditorInterface detected"
		return false
	
	_connect_post_process_inspector_signal()
	
	if not get_tree():
		initialization_error = "No tree detected while initializing"
		return false
	
	var terrain_script := preload("uid://cddg1xr5hye1d")
	var chunk_script := preload("uid://cql4d8s5t5xcx")
	var terrain_icon := preload("uid://jfugomwkrm54")
	var chunk_icon := preload("uid://dj8y22ded0j8r")
	
	if terrain_script and chunk_script:
		add_custom_type("MarchingSquaresTerrain", "Node3D", terrain_script, terrain_icon)
		add_custom_type("MarchingSquaresTerrainChunk", "MeshInstance3D", chunk_script, chunk_icon)
	else:
		initialization_error = "Failed to load algorithm scripts"
		return false
	
	if not gizmo_plugin:
		gizmo_plugin = GizmoPluginScript.new()
	
	# Clear stale/detached gizmo instances from before restart
	gizmo_plugin._terrain_gizmos.clear()
	gizmo_plugin._chunk_gizmos.clear()
	
	add_node_3d_gizmo_plugin(gizmo_plugin)
	
	if not is_instance_valid(toolbar):
		toolbar = ToolbarScript.new()
	if not is_instance_valid(tool_attributes):
		tool_attributes = ToolAttributesScript.new()
	
	if not ui:
		ui = UI.new()
		if ui:
			ui.plugin = self
			add_child(ui)
		else:
			initialization_error = "Failed to create UI system"
			return false
	
	is_initialized = true
	call_deferred("_refresh_editor_state")
	return true


func _exit_tree():
	_disconnect_post_process_inspector_signal()
	if ui:
		ui.queue_free()
		ui = null
	
	remove_custom_type("MarchingSquaresTerrain")
	remove_custom_type("MarchingSquaresTerrainChunk")
	
	if gizmo_plugin:
		gizmo_plugin._terrain_gizmos.clear()
		gizmo_plugin._chunk_gizmos.clear()
		remove_node_3d_gizmo_plugin(gizmo_plugin)
	
	is_initialized = false
	initialization_error = ""


func _connect_post_process_inspector_signal() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector == null or not inspector.has_signal("property_edited"):
		return
	if not inspector.property_edited.is_connected(_on_post_process_inspector_property_edited):
		inspector.property_edited.connect(_on_post_process_inspector_property_edited)
	_post_process_inspector_connected = true


func _disconnect_post_process_inspector_signal() -> void:
	if not _post_process_inspector_connected:
		return
	var inspector := EditorInterface.get_inspector()
	if inspector != null and inspector.property_edited.is_connected(_on_post_process_inspector_property_edited):
		inspector.property_edited.disconnect(_on_post_process_inspector_property_edited)
	_post_process_inspector_connected = false


func _on_post_process_inspector_property_edited(_property_name: String) -> void:
	var terrain := current_terrain_node
	if terrain == null or not is_instance_valid(terrain):
		return
	var inspector := EditorInterface.get_inspector()
	if inspector == null:
		return
	var edited_object: Object = inspector.get_edited_object()
	if not _is_active_post_process_source(terrain, edited_object):
		return
	if _post_process_inspector_refresh_queued:
		return
	_post_process_inspector_refresh_queued = true
	call_deferred("_refresh_post_process_after_inspector_edit", terrain)


func _refresh_post_process_after_inspector_edit(terrain: MarchingSquaresTerrain) -> void:
	_post_process_inspector_refresh_queued = false
	if terrain == null or not is_instance_valid(terrain) or not terrain.is_inside_tree():
		return
	terrain._rebuild_post_process_effects()


func _is_active_post_process_source(terrain: MarchingSquaresTerrain, edited_object: Object) -> bool:
	if edited_object == null:
		return false
	for array_name in ["surface_effects", "overlay_effects"]:
		for effect in terrain.get(array_name):
			if not (effect is MarchingSquaresPostProcessEffect):
				continue
			if effect.shader == edited_object:
				return true
			if effect.material_override == edited_object:
				return true
			if effect.material_override is ShaderMaterial and effect.material_override.shader == edited_object:
				return true
	return false


func _refresh_editor_state() -> void:
	# Re-arm gizmos and _edit() for any currently-selected/edited terrain
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return
	for node in root.find_children("", "Node3D", true, false):
		if node is MarchingSquaresTerrain or node is MarchingSquaresTerrainChunk:
			node.update_gizmos()
			if node is MarchingSquaresTerrain and node in EditorInterface.get_selection().get_selected_nodes():
				EditorInterface.edit_node(node)


# Lazy grass rebuild helpers
func _maybe_rebuild_grass_on_scene_open() -> void:
	# Only run in editor
	if not EngineWrapper.instance.is_editor():
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	for node in root.find_children("", "Node3D", true, false):
		if not is_instance_valid(node):
			continue
		if node is MarchingSquaresTerrain:
			# Decide whether to rebuild: if runtime grass array is missing OR any slot requests grass
			var needs := false
			if node.has_method("get") and (node._runtime_grass_texture_array == null):
				needs = true
			else:
				# Check slots for has_grass flags
				if node.texture_slots:
					for si in range(node.texture_slots.size()):
						var s = node.texture_slots[si]
						if s != null and bool(s.get("has_grass")):
							needs = true
							break
			if needs:
				# Defer the actual rebuild so editor finishes loading
				call_deferred("_rebuild_grass_for_node", node)


func _rebuild_grass_for_node(node: Object) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("rebuild_grass_texture_array"):
		node.rebuild_grass_texture_array()
	if node.has_method("_request_grass_regen"):
		node._request_grass_regen()


func _ready():
	if BRUSH_RADIUS_MATERIAL:
		# Avoid mutating the shared .tres resource on disk.
		BRUSH_RADIUS_MATERIAL = BRUSH_RADIUS_MATERIAL.duplicate(true)
		BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", falloff)


func _queue_raycast(origin: Vector3, dir: Vector3, cam: Camera3D) -> void:
	ray_origin = origin
	ray_dir = dir
	ray_camera = cam
	raycast_queued = true


func _physics_process(delta: float) -> void:
	# Raycast inside the physics process function to prevent
	# crashes when "run physics on a different thread" is enabled.
	if not raycast_queued:
		return
	raycast_queued = false
	
	var world_3d := ray_camera.get_world_3d()
	var space_state := PhysicsServer3D.space_get_direct_state(world_3d.space)
	
	var ray_length := 10000.0 # Adjust ray length as needed
	var end := ray_origin + ray_dir * ray_length
	var collision_mask := 16 # only terrain
	var query := PhysicsRayQueryParameters3D.create(ray_origin, end, collision_mask)
	
	queued_ray_result = space_state.intersect_ray(query)


func _on_chunk_dimensions_changed(value: Vector3i):
	brush_size *= ((value.x / 33) + (value.y / 33)) / 2.0


func _flush_current_terrain_external_data() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	if current_terrain_node == null or not is_instance_valid(current_terrain_node):
		return
	if current_terrain_node.data_directory == null or current_terrain_node.data_directory.is_empty():
		return
	MSTDataHandler.save_all_chunks(current_terrain_node)

#region input-handlers

func _edit(object: Object) -> void:
	if not is_initialized:
		push_error("Plugin not yet initialized, calling _safe_initialize() as failsafe")
		if not _safe_initialize():
			push_error("Failed to initialize plugin for editing")
			return
	if object is MarchingSquaresTerrain:
		if ui:
			ui.set_visible(true)
			current_populator = null
			current_terrain_node = object
			# Use signal-name connect to avoid hard crashes during script reload/parse errors.
			var cb := Callable(self, "_on_chunk_dimensions_changed")
			if current_terrain_node.has_signal("chunk_dimensions_changed") and not current_terrain_node.is_connected("chunk_dimensions_changed", cb):
				current_terrain_node.connect("chunk_dimensions_changed", cb)
			
			if current_terrain_node.current_texture_preset == null:
				current_terrain_node.current_texture_preset = EMPTY_TEXTURE_PRESET
			
			# Sync plugin's preset from the selected terrain's saved preset
			# This ensures each terrain keeps its own preset on selection/reload
			_syncing_from_terrain = true
			current_texture_preset = object.current_texture_preset
			_syncing_from_terrain = false
	else:
		if not _is_reselecting:
			_flush_current_terrain_external_data()
			if ui:
				ui.set_visible(false)
			current_draw_pattern.clear()
			heightmap_pattern_samples.clear()
			is_drawing = false
			is_erasing = false
			draw_height_set = false
			gizmo_plugin.clear()
			current_terrain_node = null


# This function handles the mouse click in the 3D viewport
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_initialized:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	var selected := EditorInterface.get_selection().get_selected_nodes()
	# Only proceed if exactly 1 terrain system is selected
	if not selected or len(selected) > 1:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Handle clicks
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return handle_mouse(camera, event)
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handles(object: Object) -> bool:
	if not is_initialized:
		return false
	
	return object is MarchingSquaresTerrain


func _input(event: InputEvent) -> void:
	if mode == TerrainToolMode.HEIGHTMAP and Input.is_key_pressed(KEY_SHIFT) and Input.is_key_pressed(KEY_R):
		current_heightmap_image.rotate_90(CLOCKWISE)


func handle_mouse(camera: Camera3D, event: InputEvent) -> int:
	terrain_hovered = false
	var terrain : MarchingSquaresTerrain = EditorInterface.get_selection().get_selected_nodes()[0]
	
	var mouse_pos := camera.get_viewport().get_mouse_position()
	
	var _ray_origin := camera.project_ray_origin(mouse_pos)
	var _ray_dir := camera.project_ray_normal(mouse_pos)
	
	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	
	# If not in a settings mode, perform terrain raycast
	if mode in [TerrainToolMode.BRUSH, TerrainToolMode.GRASS_MASK, TerrainToolMode.LEVEL,
				TerrainToolMode.SMOOTH, TerrainToolMode.BRIDGE, TerrainToolMode.VERTEX_PAINTING,
				TerrainToolMode.DEBUG_BRUSH, TerrainToolMode.CHUNK_MANAGEMENT, TerrainToolMode.HEIGHTMAP,
				TerrainToolMode.POPULATE]:
		var draw_position
		var draw_area_hovered : bool = false
		
		if mode == TerrainToolMode.HEIGHTMAP and not can_place_heightmaps:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		
		if is_setting and draw_height_set:
			var local_ray : Array = _ray_to_terrain_space(terrain, _ray_origin, _ray_dir)
			var local_ray_dir : Vector3 = local_ray[1]
			var set_plane := Plane(Vector3(local_ray_dir.x, 0, local_ray_dir.z), base_position)
			var set_position := set_plane.intersects_ray(local_ray[0], local_ray_dir)
			if set_position:
				brush_position = set_position
		
		# If there is any pattern and flatten is enabled, draw along that height plane instead of the terrain intersection
		elif not current_draw_pattern.is_empty() and flatten:
			draw_position = _intersect_terrain_height_plane(terrain, _ray_origin, _ray_dir, draw_height)
			if draw_position:
				draw_area_hovered = true
		
		else:
			# Perform the raycast to check for intersection with a physics body (terrain)
			_queue_raycast(_ray_origin, _ray_dir, camera)
			if queued_ray_result and queued_ray_result.has("position"):
				draw_position = terrain.to_local(queued_ray_result.position)
				if queued_ray_result.has("normal"):
					brush_surface_normal = (terrain.global_transform.basis.inverse() * queued_ray_result.normal).normalized()
				else:
					brush_surface_normal = Vector3.UP
				draw_area_hovered = true
			else:
				brush_surface_normal = Vector3.UP
				# FALLBACK: If we didn't hit a chunk, project onto a virtual plane at draw_height
				# This allows painting onto chunks while the mouse is in "negative space"
				var fallback_height := 0.0
				if is_drawing or is_setting or not current_draw_pattern.is_empty():
					fallback_height = draw_height
				
				var plane_pos = _intersect_terrain_height_plane(terrain, _ray_origin, _ray_dir, fallback_height)
				if plane_pos:
					draw_position = plane_pos
					draw_area_hovered = true
		
		# ALT or Right Click to clear the current draw pattern. Don't clear while setting
		var _right_clicked : bool = (
			event is InputEventMouseButton and
			event.button_index == MOUSE_BUTTON_RIGHT and
			event.pressed
		)
		
		if not is_setting:
			if _right_clicked or Input.is_key_pressed(KEY_ALT):
				current_draw_pattern.clear()
				heightmap_pattern_samples.clear()
		
		# Check for terrain collision
		if draw_area_hovered:
			terrain_hovered = true
			var chunk_x : int = floor(draw_position.x / ((terrain.dimensions.x - 1) * terrain.cell_size.x))
			var chunk_z : int = floor(draw_position.z / ((terrain.dimensions.z - 1) * terrain.cell_size.y))
			var chunk_coords := Vector2i(chunk_x, chunk_z)
			
			is_chunk_plane_hovered = true
			current_hovered_chunk = chunk_coords
		if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT and navmesh_paint_mode != NavMeshPaintMode.NONE:
			if event.is_pressed() and draw_area_hovered:
				_navmesh_stroke_undo.clear()
				_navmesh_stroke_do.clear()
				update_draw_pattern(draw_position)
				_apply_navmesh_pattern(terrain, current_draw_pattern)
				is_drawing = true
			else:
				is_drawing = false
				_commit_navmesh_stroke(terrain)
				current_draw_pattern.clear()
			gizmo_plugin.trigger_redraw(terrain)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		if event is InputEventMouseMotion and navmesh_paint_mode != NavMeshPaintMode.NONE and is_drawing and draw_area_hovered:
			brush_position = draw_position
			update_draw_pattern(draw_position)
			_apply_navmesh_pattern(terrain, current_draw_pattern)
			current_draw_pattern.clear()
			gizmo_plugin.trigger_redraw(terrain)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			if event.is_pressed() and draw_area_hovered:
				draw_height_set = false
				if mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode:
					brush_position = draw_position
					_begin_wall_paint_stroke()
					_sample_wall_paint_stroke(terrain)
				if mode in [TerrainToolMode.BRIDGE] and not is_making_bridge:
					flatten = false
					is_making_bridge = true
					curve3d_bridge_points.clear()
					bridge_start_pos = brush_position
					bridge_start_chunk_coords = current_hovered_chunk
					last_bridge_point = brush_position
					curve3d_bridge_points.append(bridge_start_pos)
				if mode in [TerrainToolMode.SMOOTH] and falloff == false:
					falloff = true
				if mode in [TerrainToolMode.GRASS_MASK, TerrainToolMode.DEBUG_BRUSH, TerrainToolMode.HEIGHTMAP, TerrainToolMode.POPULATE] and falloff == true:
					falloff = false
				if mode in [TerrainToolMode.GRASS_MASK, TerrainToolMode.VERTEX_PAINTING, TerrainToolMode.DEBUG_BRUSH, TerrainToolMode.POPULATE] and flatten == true:
					flatten = false
				if mode in [TerrainToolMode.LEVEL, TerrainToolMode.CHUNK_MANAGEMENT] and Input.is_key_pressed(KEY_CTRL):
					height = brush_position.y
					ui.tool_attributes.show_tool_attributes(ui.active_tool)
				elif Input.is_key_pressed(KEY_SHIFT) and mode not in [TerrainToolMode.CHUNK_MANAGEMENT, TerrainToolMode.HEIGHTMAP]:
					is_drawing = true
					brush_position = draw_position
				elif Input.is_key_pressed(KEY_CTRL) and mode not in [TerrainToolMode.CHUNK_MANAGEMENT, TerrainToolMode.HEIGHTMAP] and not (mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode):
					is_erasing = true
					brush_position = draw_position
				elif mode not in [TerrainToolMode.CHUNK_MANAGEMENT]:
					is_setting = true
					if not flatten:
						draw_height = draw_position.y
			elif event.is_released():
				if is_making_bridge:
					is_making_bridge = false
				if is_drawing:
					is_drawing = false
					if mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode:
						_commit_wall_paint_stroke(terrain)
						current_draw_pattern.clear()
					if mode in [TerrainToolMode.GRASS_MASK, TerrainToolMode.LEVEL, TerrainToolMode.BRIDGE, TerrainToolMode.DEBUG_BRUSH, TerrainToolMode.VERTEX_PAINTING, TerrainToolMode.POPULATE]:
						if not (mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode):
							if mode == TerrainToolMode.BRIDGE and not curve3d_mode:
								rebuild_bridge_line_pattern(brush_position)
							draw_pattern(terrain)
							current_draw_pattern.clear()
					if mode in [TerrainToolMode.SMOOTH]:
						current_draw_pattern.clear()
				if is_erasing:
					is_erasing = false
				if is_setting:
					is_setting = false
					if mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode:
						_commit_wall_paint_stroke(terrain)
						current_draw_pattern.clear()
					else:
						if mode == TerrainToolMode.BRIDGE and not curve3d_mode:
							rebuild_bridge_line_pattern(brush_position)
						draw_pattern(terrain)
						if Input.is_key_pressed(KEY_SHIFT):
							draw_height = brush_position.y
						else:
							current_draw_pattern.clear()
							heightmap_pattern_samples.clear()
			gizmo_plugin.trigger_redraw(terrain)
			if mode not in [TerrainToolMode.CHUNK_MANAGEMENT]:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		# Collect Curve3D bridge points
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and is_making_bridge:
			if brush_position.distance_to(last_bridge_point) > terrain.cell_size.x:
				curve3d_bridge_points.append(brush_position)
				last_bridge_point = brush_position
		
		# Adjust brush size
		if event is InputEventMouseButton and Input.is_key_pressed(KEY_SHIFT) and mode not in [TerrainToolMode.CHUNK_MANAGEMENT]:
			var cell_scale_factor := clamp(((terrain.cell_size.x + terrain.cell_size.y) / 4.0), 0.3, 1.0)
			var dimensions_scale_factor := clamp((((terrain.dimensions.x / 33) + (terrain.dimensions.z / 33)) / 2.0), 0.5, 2.0)
			var size_scale_factor : float = dimensions_scale_factor * cell_scale_factor
			var factor : float = event.factor if event.factor else 1
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				brush_size += (0.5 * size_scale_factor) * factor
				if brush_size > 50 * size_scale_factor:
					brush_size = 50 * size_scale_factor
				gizmo_plugin.trigger_redraw(terrain)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				brush_size -= (0.5 * size_scale_factor) * factor
				if brush_size < 1.0 * size_scale_factor:
					brush_size = 1.0 * size_scale_factor
				gizmo_plugin.trigger_redraw(terrain)
			ui.tool_attributes.show_tool_attributes(ui.active_tool)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		
		if draw_area_hovered and event is InputEventMouseMotion:
			brush_position = draw_position
			if navmesh_paint_mode != NavMeshPaintMode.NONE and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				draw_pattern(terrain)
				_apply_navmesh_pattern(terrain, current_draw_pattern)
				current_draw_pattern.clear()
			elif mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode and (is_drawing or is_setting):
				if _should_sample_wall_paint_stroke(brush_position):
					_sample_wall_paint_stroke(terrain)
			elif is_drawing and mode in [TerrainToolMode.SMOOTH]:
				draw_pattern(terrain)
				current_draw_pattern.clear()
		
		gizmo_plugin.trigger_redraw(terrain)
		if mode not in [TerrainToolMode.CHUNK_MANAGEMENT]:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Check for hovering over/clicking a new chunk
	var intersection = _intersect_terrain_height_plane(terrain, _ray_origin, _ray_dir, 0.0)
	
	if intersection:
		var chunk_x : int = floor(intersection.x / ((terrain.dimensions.x-1) * terrain.cell_size.x))
		var chunk_z : int = floor(intersection.z / ((terrain.dimensions.z-1) * terrain.cell_size.y))
		
		var chunk_coords := Vector2i(chunk_x, chunk_z)
		var chunk := terrain.chunks.get(chunk_coords)
		
		current_hovered_chunk = chunk_coords
		is_chunk_plane_hovered = true
		if chunk_batch_dragging:
			chunk_batch_drag_end = chunk_coords
		if mode == TerrainToolMode.CHUNK_MANAGEMENT and chunk != null:
			selected_chunk = chunk
			if ui != null and ui.tool_attributes != null:
				ui.tool_attributes.selected_chunk = chunk
		
		# Physical click-drag fill for chunk management. Ctrl and Alt retain
		# their existing shortcuts and do not start a batch selection.
		if mode == TerrainToolMode.CHUNK_MANAGEMENT and event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT and event.is_pressed() and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_ALT):
			chunk_batch_dragging = true
			chunk_batch_drag_removing = terrain.chunks.has(chunk_coords)
			chunk_batch_drag_start = chunk_coords
			chunk_batch_drag_end = chunk_coords
			gizmo_plugin.trigger_redraw(terrain)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		if mode == TerrainToolMode.CHUNK_MANAGEMENT and event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_LEFT and not event.is_pressed() and chunk_batch_dragging:
			chunk_batch_dragging = false
			chunk_batch_drag_end = chunk_coords
			var min_coords := Vector2i(mini(chunk_batch_drag_start.x, chunk_batch_drag_end.x), mini(chunk_batch_drag_start.y, chunk_batch_drag_end.y))
			var max_coords := Vector2i(maxi(chunk_batch_drag_start.x, chunk_batch_drag_end.x), maxi(chunk_batch_drag_start.y, chunk_batch_drag_end.y))
			var selection_size := max_coords - min_coords + Vector2i.ONE
			if selection_size == Vector2i.ONE:
				if chunk:
					var removed_chunk = terrain.chunks[chunk_coords]
					get_undo_redo().create_action("remove chunk")
					get_undo_redo().add_do_method(terrain, "remove_chunk_from_tree", chunk_x, chunk_z, self)
					get_undo_redo().add_undo_method(terrain, "add_chunk", chunk_coords, removed_chunk, self)
					get_undo_redo().commit_action()
				else:
					var can_add_empty : bool = terrain.chunks.is_empty() or terrain.has_chunk(chunk_x-1, chunk_z) or terrain.has_chunk(chunk_x+1, chunk_z) or terrain.has_chunk(chunk_x, chunk_z-1) or terrain.has_chunk(chunk_x, chunk_z+1)
					if can_add_empty:
						get_undo_redo().create_action("add chunk")
						get_undo_redo().add_do_method(terrain, "add_new_chunk", chunk_x, chunk_z, self)
						get_undo_redo().add_undo_method(terrain, "remove_chunk", chunk_x, chunk_z, self)
						get_undo_redo().commit_action()
			elif chunk_batch_drag_removing:
				var remove_action := "remove chunk area"
				get_undo_redo().create_action(remove_action)
				for area_z in range(min_coords.y, max_coords.y + 1):
					for area_x in range(min_coords.x, max_coords.x + 1):
						var area_coords := Vector2i(area_x, area_z)
						var existing_chunk = terrain.chunks.get(area_coords)
						if existing_chunk == null:
							continue
						get_undo_redo().add_do_method(terrain, "remove_chunk_from_tree", area_coords.x, area_coords.y, self)
						get_undo_redo().add_undo_method(terrain, "add_chunk", area_coords, existing_chunk, self)
				get_undo_redo().commit_action()
			else:
				terrain.add_chunk_batch(min_coords, selection_size, self)
			gizmo_plugin.trigger_redraw(terrain)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		if mode == TerrainToolMode.CHUNK_MANAGEMENT and event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_ALT):
			selected_chunk = terrain.chunks.get(current_hovered_chunk)
			ui.tool_attributes.show_tool_attributes(TerrainToolMode.CHUNK_MANAGEMENT)
			ui.tool_attributes.selected_chunk = selected_chunk
		
		gizmo_plugin.trigger_redraw(terrain)
	else:
		is_chunk_plane_hovered = false
	
	# Consume clicks but allow other click / mouse motion types to reach the gui, for camera movement, etc
	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS

#endregion

#region draw-related functions

func _ray_to_terrain_space(terrain: Node3D, origin: Vector3, dir: Vector3) -> Array:
	return [terrain.to_local(origin), terrain.global_transform.basis.inverse() * dir]


func _intersect_terrain_height_plane(terrain: Node3D, origin: Vector3, dir: Vector3, local_height: float) -> Variant:
	var local_ray : Array = _ray_to_terrain_space(terrain, origin, dir)
	return Plane(Vector3.UP, Vector3(0.0, local_height, 0.0)).intersects_ray(local_ray[0], local_ray[1])


# Calculates brush pattern and updates current_draw_pattern
func update_draw_pattern(b_pos: Vector3):
	var terrain_system : MarchingSquaresTerrain = current_terrain_node
	
	var bounds : BrushPatternCalculator.BrushBounds = BrushPatternCalculator.calculate_bounds(b_pos, brush_size, terrain_system)
	var max_distance : float = BrushPatternCalculator.calculate_max_distance(brush_size, current_brush_index)
	var brush_pos : Vector2 = Vector2(b_pos.x, b_pos.z)
	
	for chunk_z in range(bounds.chunk_tl.y, bounds.chunk_br.y + 1):
		for chunk_x in range(bounds.chunk_tl.x, bounds.chunk_br.x + 1):
			var cursor_chunk_coords : Vector2i = Vector2i(chunk_x, chunk_z)
			if not (terrain_system.get("chunks") as Dictionary).has(cursor_chunk_coords):
				continue
			
			var cell_range : Dictionary = BrushPatternCalculator.get_cell_range_for_chunk(cursor_chunk_coords, bounds, terrain_system)
			
			for z in range(cell_range.z_min, cell_range.z_max):
				for x in range(cell_range.x_min, cell_range.x_max):
					var cursor_cell_coords : Vector2i = Vector2i(x, z)
					var world_pos : Vector2 = BrushPatternCalculator.cell_to_world_pos(
						cursor_chunk_coords,
						cursor_cell_coords,
						terrain_system
					)
					
					var use_falloff := falloff
					if mode == TerrainToolMode.VERTEX_PAINTING:
						use_falloff = (_vp_falloff_mode == VertexPaintFalloffMode.DITHERED)
					var sample : float = BrushPatternCalculator.calculate_falloff_sample(
						world_pos, brush_pos, brush_size, current_brush_index,
						max_distance, use_falloff, falloff_curve
					)
					if mode == TerrainToolMode.VERTEX_PAINTING and paint_walls_mode:
						var wall_sample_pos : Vector3 = BrushPatternCalculator.cell_to_wall_sample_pos(
							cursor_chunk_coords,
							cursor_cell_coords,
							terrain_system,
							b_pos
						)
						sample = BrushPatternCalculator.calculate_wall_falloff_sample(
							wall_sample_pos,
							b_pos,
							brush_surface_normal,
							brush_size,
							current_brush_index,
							max_distance,
							use_falloff,
							falloff_curve
						)
					
					if sample < 0:
						continue  # Outside brush
					
					# Store largest sample
					if not current_draw_pattern.has(cursor_chunk_coords):
						current_draw_pattern[cursor_chunk_coords] = {}
					if current_draw_pattern[cursor_chunk_coords].has(cursor_cell_coords):
						var prev_sample = current_draw_pattern[cursor_chunk_coords][cursor_cell_coords]
						if sample > prev_sample:
							current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample
					else:
						current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample


func store_heightmap_pattern_sample(chunk_coords: Vector2i, cell_coords: Vector2i, value: float) -> void:
	if not heightmap_pattern_samples.has(chunk_coords):
		heightmap_pattern_samples[chunk_coords] = {}
	var chunk_samples : Dictionary = heightmap_pattern_samples[chunk_coords]
	var previous := float(chunk_samples.get(cell_coords, 0.0))
	if value > previous:
		chunk_samples[cell_coords] = value


func get_heightmap_pattern_sample(chunk_coords: Vector2i, cell_coords: Vector2i) -> float:
	if not heightmap_pattern_samples.has(chunk_coords):
		return 0.0
	return float((heightmap_pattern_samples[chunk_coords] as Dictionary).get(cell_coords, 0.0))


static func _distance_sq_point_to_segment_2d(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment : Vector2 = end - start
	var segment_length_sq : float = segment.length_squared()
	if segment_length_sq <= 0.000001:
		return point.distance_squared_to(start)
	var t : float = clampf((point - start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest : Vector2 = start + segment * t
	return point.distance_squared_to(closest)


func rebuild_bridge_line_pattern(end_pos: Vector3) -> void:
	var terrain_system : MarchingSquaresTerrain = current_terrain_node
	if terrain_system == null:
		current_draw_pattern.clear()
		return
	
	var start_2d := Vector2(bridge_start_pos.x, bridge_start_pos.z)
	var end_2d := Vector2(end_pos.x, end_pos.z)
	var brush_radius : float = maxf(brush_size, 0.001)
	var radius_sq : float = brush_radius * brush_radius
	var chunk_span_x : float = float(terrain_system.dimensions.x - 1) * terrain_system.cell_size.x
	var chunk_span_z : float = float(terrain_system.dimensions.z - 1) * terrain_system.cell_size.y
	var min_x : float = minf(start_2d.x, end_2d.x) - brush_radius
	var max_x : float = maxf(start_2d.x, end_2d.x) + brush_radius
	var min_z : float = minf(start_2d.y, end_2d.y) - brush_radius
	var max_z : float = maxf(start_2d.y, end_2d.y) + brush_radius
	var min_chunk_x : int = int(floor(min_x / chunk_span_x))
	var max_chunk_x : int = int(floor(max_x / chunk_span_x))
	var min_chunk_z : int = int(floor(min_z / chunk_span_z))
	var max_chunk_z : int = int(floor(max_z / chunk_span_z))
	var max_distance : float = BrushPatternCalculator.calculate_max_distance(brush_size, current_brush_index)
	var use_falloff : bool = falloff
	
	current_draw_pattern.clear()
	
	for chunk_z in range(min_chunk_z, max_chunk_z + 1):
		for chunk_x in range(min_chunk_x, max_chunk_x + 1):
			var cursor_chunk_coords := Vector2i(chunk_x, chunk_z)
			if not (terrain_system.get("chunks") as Dictionary).has(cursor_chunk_coords):
				continue
			
			var chunk_origin_x : float = float(chunk_x) * chunk_span_x
			var chunk_origin_z : float = float(chunk_z) * chunk_span_z
			var local_min_x : int = maxi(0, int(floor((min_x - chunk_origin_x) / terrain_system.cell_size.x)) - 1)
			var local_max_x : int = mini(terrain_system.dimensions.x, int(ceil((max_x - chunk_origin_x) / terrain_system.cell_size.x)) + 1)
			var local_min_z : int = maxi(0, int(floor((min_z - chunk_origin_z) / terrain_system.cell_size.y)) - 1)
			var local_max_z : int = mini(terrain_system.dimensions.z, int(ceil((max_z - chunk_origin_z) / terrain_system.cell_size.y)) + 1)
			
			for z in range(local_min_z, local_max_z):
				for x in range(local_min_x, local_max_x):
					var cursor_cell_coords := Vector2i(x, z)
					var world_pos: Vector2 = BrushPatternCalculator.cell_to_world_pos(
						cursor_chunk_coords,
						cursor_cell_coords,
						terrain_system
					)
					var distance_sq : float = _distance_sq_point_to_segment_2d(world_pos, start_2d, end_2d)
					if distance_sq > radius_sq:
						continue
					
					var distance_to_line : float = sqrt(distance_sq)
					var sample : float = 1.0
					if use_falloff:
						sample = clampf(1.0 - (distance_to_line / maxf(max_distance, 0.001)), 0.0, 1.0)
						if falloff_curve != null:
							sample = clampf(falloff_curve.sample(sample), 0.0, 1.0)
					if sample <= 0.0:
						continue
					
					if not current_draw_pattern.has(cursor_chunk_coords):
						current_draw_pattern[cursor_chunk_coords] = {}
					current_draw_pattern[cursor_chunk_coords][cursor_cell_coords] = sample


func _reset_wall_paint_stroke() -> void:
	_wall_paint_stroke_active = false
	_wall_paint_stroke_undo_states.clear()
	_wall_paint_stroke_do_states.clear()
	_wall_paint_stroke_dirty_chunks.clear()
	_wall_paint_has_last_stamp_position = false


func _begin_wall_paint_stroke() -> void:
	_wall_paint_stroke_active = true
	_wall_paint_stroke_undo_states = {
		"wall_color_0": {},
		"wall_color_1": {},
	}
	_wall_paint_stroke_do_states = {
		"wall_color_0": {},
		"wall_color_1": {},
	}
	_wall_paint_stroke_dirty_chunks.clear()
	_wall_paint_has_last_stamp_position = false


func _wall_paint_step_distance() -> float:
	return maxf(brush_size * 0.12, 0.04)


func _should_sample_wall_paint_stroke(pos: Vector3) -> bool:
	if not _wall_paint_stroke_active or not _wall_paint_has_last_stamp_position:
		return true
	return _wall_paint_last_stamp_position.distance_to(pos) >= _wall_paint_step_distance()


func _sample_wall_paint_stroke(terrain: MarchingSquaresTerrain) -> void:
	if terrain == null or not _wall_paint_stroke_active:
		return
	current_draw_pattern.clear()
	update_draw_pattern(brush_position)
	if current_draw_pattern.is_empty():
		return
	_apply_wall_paint_stroke_sample(terrain)
	current_draw_pattern.clear()
	_wall_paint_last_stamp_position = brush_position
	_wall_paint_has_last_stamp_position = true


func _apply_wall_paint_stroke_sample(terrain: MarchingSquaresTerrain) -> void:
	var undo_wall_color_0 : Dictionary = _wall_paint_stroke_undo_states.get("wall_color_0", {})
	var undo_wall_color_1 : Dictionary = _wall_paint_stroke_undo_states.get("wall_color_1", {})
	var do_wall_color_0 : Dictionary = _wall_paint_stroke_do_states.get("wall_color_0", {})
	var do_wall_color_1 : Dictionary = _wall_paint_stroke_do_states.get("wall_color_1", {})
	var sample_dirty_chunks : Dictionary = {}
	
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(draw_chunk_coords)
		if chunk == null:
			continue
		if not undo_wall_color_0.has(draw_chunk_coords):
			undo_wall_color_0[draw_chunk_coords] = {}
		if not undo_wall_color_1.has(draw_chunk_coords):
			undo_wall_color_1[draw_chunk_coords] = {}
		if not do_wall_color_0.has(draw_chunk_coords):
			do_wall_color_0[draw_chunk_coords] = {}
		if not do_wall_color_1.has(draw_chunk_coords):
			do_wall_color_1[draw_chunk_coords] = {}
		
		var draw_chunk_dict : Dictionary = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict.keys():
			if not undo_wall_color_0[draw_chunk_coords].has(draw_cell_coords):
				undo_wall_color_0[draw_chunk_coords][draw_cell_coords] = chunk.get_wall_color_0(draw_cell_coords)
				undo_wall_color_1[draw_chunk_coords][draw_cell_coords] = chunk.get_wall_color_1(draw_cell_coords)
			chunk.draw_wall_color_0(draw_cell_coords.x, draw_cell_coords.y, vertex_color_0)
			chunk.draw_wall_color_1(draw_cell_coords.x, draw_cell_coords.y, vertex_color_1)
			do_wall_color_0[draw_chunk_coords][draw_cell_coords] = vertex_color_0
			do_wall_color_1[draw_chunk_coords][draw_cell_coords] = vertex_color_1
		
		_wall_paint_stroke_dirty_chunks[draw_chunk_coords] = chunk
		sample_dirty_chunks[draw_chunk_coords] = chunk
	
	_wall_paint_stroke_undo_states["wall_color_0"] = undo_wall_color_0
	_wall_paint_stroke_undo_states["wall_color_1"] = undo_wall_color_1
	_wall_paint_stroke_do_states["wall_color_0"] = do_wall_color_0
	_wall_paint_stroke_do_states["wall_color_1"] = do_wall_color_1
	
	for draw_chunk_coords: Vector2i in sample_dirty_chunks.keys():
		var chunk : MarchingSquaresTerrainChunk = sample_dirty_chunks[draw_chunk_coords]
		chunk.queue_mesh_regen()


func _commit_wall_paint_stroke(terrain: MarchingSquaresTerrain) -> void:
	if terrain == null:
		_reset_wall_paint_stroke()
		return
	if _wall_paint_stroke_do_states.has("wall_color_0") and not _wall_paint_stroke_do_states["wall_color_0"].is_empty():
		var undo_redo := get_undo_redo()
		undo_redo.create_action("terrain wall paint")
		undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, _wall_paint_stroke_do_states.duplicate(true))
		undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, _wall_paint_stroke_undo_states.duplicate(true))
		undo_redo.commit_action()
	_reset_wall_paint_stroke()


static func _fract(p_x: float) -> float:
	return p_x - floor(p_x)


# “Blue-noise-ish” hashless noise (interleaved gradient noise). This avoids low-bit patterns
# that can create checkerboard-like flat runs on the brush edge.
static func _blue_noise_unit_2i(p_x: int, p_y: int) -> float:
	# Scramble the integer lattice a bit to avoid axis-aligned artifacts.
	var sx := float(p_x * 2 + p_y * 3)
	var sy := float(p_x * 5 - p_y * 7)
	var v := _fract(0.06711056 * sx + 0.00583715 * sy)
	return _fract(52.9829189 * v)


func _vp_dither_should_paint(terrain: MarchingSquaresTerrain, chunk_coords: Vector2i, cell_coords: Vector2i, p_sample: float) -> bool:
	# Want a solid core + dithered outer ring (soft edge).
	# p_sample is a (0..1) falloff sample where higher means closer to brush center.
	if p_sample >=  VP_DITHER_CORE_SAMPLE:
		return true
	if p_sample <=  0.0:
		return false
	
	# Remap outer-ring probability so core -> 1.0 (always) and 0.0 -> 0.0 (never).
	var prob := clampf(p_sample / VP_DITHER_CORE_SAMPLE, 0.0, 1.0)
	
	# Use global grid coords so the pattern is stable across chunk boundaries.
	var gx : int = chunk_coords.x * (terrain.dimensions.x - 1) + cell_coords.x
	var gz : int = chunk_coords.y * (terrain.dimensions.z - 1) + cell_coords.y
	var r := _blue_noise_unit_2i(gx, gz)
	return r <= prob


func _update_falloff_visual() -> void:
	if BRUSH_RADIUS_MATERIAL == null:
		return
	if mode == TerrainToolMode.VERTEX_PAINTING:
		BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", _vp_falloff_mode == VertexPaintFalloffMode.DITHERED)
	else:
		BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", falloff)


func _ensure_navmesh_permission(chunk: MarchingSquaresTerrainChunk) -> void:
	var cell_count := maxi((chunk.dimensions.x - 1) * (chunk.dimensions.z - 1), 0)
	if chunk.navmesh_permission.size() != cell_count:
		chunk.navmesh_permission.resize(cell_count)


func _apply_navmesh_pattern(terrain: MarchingSquaresTerrain, pattern: Dictionary) -> void:
	if terrain == null:
		return
	terrain.navmesh_painting_enabled = true
	
	for chunk_coords: Vector2i in pattern.keys():
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
		if chunk == null:
			continue
		
		_ensure_navmesh_permission(chunk)
		
		var width := maxi(chunk.dimensions.x - 1, 1)
		var depth := maxi(chunk.dimensions.z - 1, 1)
		if not _navmesh_stroke_undo.has(chunk_coords):
			_navmesh_stroke_undo[chunk_coords] = {}
		if not _navmesh_stroke_do.has(chunk_coords):
			_navmesh_stroke_do[chunk_coords] = {}
		
		for cell_coords: Vector2i in pattern[chunk_coords].keys():
			if cell_coords.x < 0 or cell_coords.y < 0 or cell_coords.x >= width or cell_coords.y >= depth:
				continue
			var index : int = cell_coords.y * width + cell_coords.x
			if index >= chunk.navmesh_permission.size():
				continue
			if not _navmesh_stroke_undo[chunk_coords].has(index):
				_navmesh_stroke_undo[chunk_coords][index] = chunk.navmesh_permission[index]
			
			var value := 1 if navmesh_paint_mode == NavMeshPaintMode.PAINT else 0
			chunk.navmesh_permission[index] = value
			_navmesh_stroke_do[chunk_coords][index] = value
		
		chunk.mark_dirty()
		# Painting changes the permission-filtered face cache as well as the
		# editor overlay, so the next bake must rebuild this chunk.
		terrain._nav_controller.invalidate_chunk(chunk_coords)
		terrain._nav_controller.invalidate_preview()


func _commit_navmesh_stroke(terrain: MarchingSquaresTerrain) -> void:
	if terrain == null or _navmesh_stroke_do.is_empty():
		_navmesh_stroke_undo.clear()
		_navmesh_stroke_do.clear()
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action("terrain NavMesh paint")
	undo_redo.add_do_method(self, "apply_navmesh_permission_action", terrain, _navmesh_stroke_do.duplicate(true))
	undo_redo.add_undo_method(self, "apply_navmesh_permission_action", terrain, _navmesh_stroke_undo.duplicate(true))
	undo_redo.commit_action()
	_navmesh_stroke_undo.clear()
	_navmesh_stroke_do.clear()


func apply_navmesh_permission_action(terrain: MarchingSquaresTerrain, states: Dictionary) -> void:
	if terrain == null:
		return
	terrain.navmesh_painting_enabled = true
	
	for chunk_coords: Vector2i in states.keys():
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
		if chunk == null:
			continue
		
		_ensure_navmesh_permission(chunk)
		
		for index in states[chunk_coords].keys():
			var cell_index := int(index)
			if cell_index >= 0 and cell_index < chunk.navmesh_permission.size():
				chunk.navmesh_permission[cell_index] = int(states[chunk_coords][index])
		
		chunk.mark_dirty()
		terrain._nav_controller.invalidate_chunk(chunk_coords)
		terrain._nav_controller.invalidate_preview()


func draw_pattern(terrain: MarchingSquaresTerrain):
	var undo_redo := MarchingSquaresTerrainPlugin.instance.get_undo_redo()
	
	var pattern := {}
	var pattern_cc := {}
	var restore_pattern := {}
	var restore_pattern_cc := {}
	
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
		var first_draw_cell : Vector2i
		var last_draw_cell : Vector2i
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			if not first_draw_cell:
				first_draw_cell = draw_cell_coords
			last_draw_cell.x = maxi(last_draw_cell.x, draw_cell_coords.x)
			last_draw_cell.y = maxi(last_draw_cell.y, draw_cell_coords.y)
		
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.0, 1.0)
			var restore_value
			var draw_value
			var restore_value_cc
			var draw_value_cc
			if mode == TerrainToolMode.GRASS_MASK:
				restore_value = chunk.get_grass_mask(draw_cell_coords)
				draw_value = Color(0.0, 0.0, 0.0, 0.0) if should_mask_grass else Color(1.0, 1.0, 1.0, 1.0)
			elif mode == TerrainToolMode.LEVEL:
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = lerp(restore_value, height, sample)
			elif mode == TerrainToolMode.SMOOTH:
				var heights : Array[float] = []
				var global_cells : Array[Vector2i] = []
				
				for chunk_coords in current_draw_pattern.keys():
					var chunk_dict = current_draw_pattern[chunk_coords]
					for cell_coords in chunk_dict.keys():
						var global_x = chunk_coords.x * terrain.dimensions.x + cell_coords.x
						var global_y = chunk_coords.y * terrain.dimensions.z + cell_coords.y
						global_cells.append(Vector2i(global_x, global_y))
				
				for global_cell in global_cells:
					var current_chunk_coords := Vector2i(floor(float(global_cell.x) / terrain.dimensions.x), floor(float(global_cell.y) / terrain.dimensions.z))
					if not terrain.chunks.has(current_chunk_coords):
						continue
					var current_chunk = terrain.chunks[current_chunk_coords]
					var local_cell := Vector2i(posmod(global_cell.x, terrain.dimensions.x), posmod(global_cell.y, terrain.dimensions.z))
					heights.append(current_chunk.get_height(local_cell))
				
				var avg_height := 0.0
				for h in heights:
					avg_height += h
				avg_height /= heights.size()
				
				for global_cell in global_cells:
					var current_chunk_coords := Vector2i(floor(float(global_cell.x) / terrain.dimensions.x), floor(float(global_cell.y) / terrain.dimensions.z))
					if not terrain.chunks.has(current_chunk_coords):
						continue
					var current_chunk = terrain.chunks[current_chunk_coords]
					var local_cell := Vector2i(posmod(global_cell.x, terrain.dimensions.x), posmod(global_cell.y, terrain.dimensions.z))
					
					if not restore_pattern.has(current_chunk_coords):
						restore_pattern[current_chunk_coords] = {}
					if not pattern.has(current_chunk_coords):
						pattern[current_chunk_coords] = {}
					
					# Overwrite sample var with neighbouring chunks' data included
					sample = clamp(current_draw_pattern.get(current_chunk_coords, {}).get(local_cell, sample), 0.001, 0.999)
					restore_value = current_chunk.get_height(local_cell)
					draw_value = lerp(restore_value, avg_height, sample * strength)
					
					restore_pattern[current_chunk_coords][local_cell] = restore_value
					pattern[current_chunk_coords][local_cell] = draw_value
			elif mode == TerrainToolMode.BRIDGE:
				if curve3d_mode:
					var bridge_curve := Curve3D.new()
					bridge_curve.bake_interval = terrain.cell_size.x
					
					for point in curve3d_bridge_points:
						bridge_curve.add_point(Vector3(point.x, 0.0, point.z))
					
					if bridge_curve.get_baked_length() < 0.5:
						return
					
					var global_cell := Vector2(
						(draw_chunk_coords.x * (terrain.dimensions.x - 1) + draw_cell_coords.x) * terrain.cell_size.x,
						(draw_chunk_coords.y * (terrain.dimensions.z - 1) + draw_cell_coords.y) * terrain.cell_size.y
					)
					
					var closest_offset : float = _find_closest_curve_offset(bridge_curve, global_cell)
					var progress : float = closest_offset / bridge_curve.get_baked_length()
					
					if ease_value != -1.0:
						progress = ease(progress, ease_value)
					progress = min(progress / sample, 1)
					var bridge_height := lerpf(bridge_start_pos.y, brush_position.y, progress)
					
					restore_value = chunk.get_height(draw_cell_coords)
					draw_value = bridge_height
				else:
					var b_end := Vector2(brush_position.x, brush_position.z)
					var b_start := Vector2(bridge_start_pos.x, bridge_start_pos.z)
					var bridge_length := (b_end - b_start).length()
					if bridge_length < 0.5 or draw_chunk_dict.size() < 3:
						return
					
					var global_cell := Vector2(
						(draw_chunk_coords.x * terrain.dimensions.x + draw_cell_coords.x) * terrain.cell_size.x,
						(draw_chunk_coords.y * terrain.dimensions.z + draw_cell_coords.y) * terrain.cell_size.y)
					
					if draw_chunk_coords !=  first_chunk:
						global_cell.x += (first_chunk.x - draw_chunk_coords.x) * terrain.cell_size.x
					if draw_chunk_coords !=  first_chunk:
						global_cell.y += (first_chunk.y - draw_chunk_coords.y) * terrain.cell_size.y
					
					var bridge_dir := (b_end - b_start) / bridge_length
					var cell_vec := global_cell - b_start
					var linear_offset := cell_vec.dot(bridge_dir)
					var progress := clamp(linear_offset / bridge_length, 0.0, 1.0)
					
					if ease_value !=  -1.0:
						progress = ease(progress, ease_value)
					var bridge_height := lerpf(bridge_start_pos.y, brush_position.y, progress)
					
					restore_value = chunk.get_height(draw_cell_coords)
					draw_value = bridge_height
			elif mode == TerrainToolMode.VERTEX_PAINTING:
				if _vp_falloff_mode == VertexPaintFalloffMode.DITHERED and not _vp_dither_should_paint(terrain, draw_chunk_coords, draw_cell_coords, sample):
					continue
				
				if paint_walls_mode:
					restore_value = chunk.get_wall_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_wall_color_1(draw_cell_coords)
				else:
					restore_value = chunk.get_color_0(draw_cell_coords)
					restore_value_cc = chunk.get_color_1(draw_cell_coords)
				
				# Overwrite (matches origin/main). Lerp creates unintended texture indices.
				draw_value = vertex_color_0
				draw_value_cc = vertex_color_1
			elif mode == TerrainToolMode.POPULATE:
				if current_populator == null:
					return
			elif mode == TerrainToolMode.DEBUG_BRUSH:
				var g_pos := chunk.to_global(Vector3(float(draw_cell_coords.x), chunk.get_height(draw_cell_coords), float(draw_cell_coords.y)))
				var normal := get_cell_normal(chunk, draw_cell_coords)
				print("MST debug brush: global_pos = " + str(g_pos) +
					", vertex_color_idx = " + str(MSTVertexColorHelper.get_texture_index_from_colors(chunk.get_color_0(draw_cell_coords), chunk.get_color_1(draw_cell_coords))) +
					", normal = " + str(normal))
				continue
			elif mode == TerrainToolMode.CHUNK_MANAGEMENT:
				restore_value = chunk.get_height(draw_cell_coords)
				draw_value = restore_value
			elif mode == TerrainToolMode.HEIGHTMAP:
				restore_value = chunk.get_height(draw_cell_coords)
				var heightmap_sample := get_heightmap_pattern_sample(draw_chunk_coords, draw_cell_coords)
				if heightmap_sample <= 0.0:
					continue
				if flatten:
					draw_value = lerp(restore_value, brush_position.y, sample)
				else:
					var height_diff := brush_position.y - draw_height
					draw_value = lerp(restore_value, restore_value + height_diff, sample)
				draw_value += brush_size / terrain.cell_size.x * heightmap_sample
			else: # Brush tool:
				restore_value = chunk.get_height(draw_cell_coords)
				if flatten:
					draw_value = lerp(restore_value, brush_position.y, sample)
				else:
					var height_diff := brush_position.y - draw_height
					draw_value = lerp(restore_value, restore_value + height_diff, sample)
			
			restore_pattern[draw_chunk_coords][draw_cell_coords] = restore_value
			pattern[draw_chunk_coords][draw_cell_coords] = draw_value
			if mode == TerrainToolMode.VERTEX_PAINTING:
				restore_pattern_cc[draw_chunk_coords][draw_cell_coords] = restore_value_cc
				pattern_cc[draw_chunk_coords][draw_cell_coords] = draw_value_cc
	if mode in [TerrainToolMode.DEBUG_BRUSH]:
		return
	for draw_chunk_coords: Vector2i in current_draw_pattern.keys():
		var draw_chunk_dict = current_draw_pattern[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			# VP dither mode can skip cells. Only expand borders for cells that were actually painted.
			if not pattern.has(draw_chunk_coords) or not pattern[draw_chunk_coords].has(draw_cell_coords):
				continue
			var sample : float = clamp(draw_chunk_dict[draw_cell_coords], 0.0, 1.0)
			for cx in range(-1, 2):
				for cz in range(-1, 2):
					if (cx == 0 and cz == 0):
						continue
					
					var adjacent_chunk_coords = Vector2i(draw_chunk_coords.x + cx, draw_chunk_coords.y + cz)
					if not terrain.chunks.has(adjacent_chunk_coords):
						continue
					
					var x : int = draw_cell_coords.x
					var z : int = draw_cell_coords.y
					
					if cx == -1:
						if x == 0:
							x = terrain.dimensions.x - 1
						else:
							continue
					elif cx == 1:
						if x == terrain.dimensions.x - 1:
							x = 0
						else:
							continue
					
					if cz == -1:
						if z == 0:
							z = terrain.dimensions.z - 1
						else:
							continue
					elif cz == 1:
						if z == terrain.dimensions.z - 1:
							z = 0
						else:
							continue
					
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
		if paint_walls_mode:
			if _wall_paint_stroke_active:
				return
			var affected_wall_chunks := {}
			
			for draw_chunk_coords: Vector2i in pattern.keys():
				var chunk: MarchingSquaresTerrainChunk = terrain.chunks.get(draw_chunk_coords)
				if chunk == null:
					continue
				if _wall_paint_stroke_active and not _wall_paint_stroke_undo_states.has(draw_chunk_coords):
					_wall_paint_stroke_undo_states[draw_chunk_coords] = chunk.get_wall_color_map_state()
				
				for draw_cell_coords: Vector2i in pattern[draw_chunk_coords]:
					chunk.draw_wall_color_0(draw_cell_coords.x, draw_cell_coords.y, pattern[draw_chunk_coords][draw_cell_coords])
					chunk.draw_wall_color_1(draw_cell_coords.x, draw_cell_coords.y, pattern_cc[draw_chunk_coords][draw_cell_coords])
				affected_wall_chunks[draw_chunk_coords] = chunk
			
			for draw_chunk_coords: Vector2i in affected_wall_chunks.keys():
				var chunk: MarchingSquaresTerrainChunk = affected_wall_chunks[draw_chunk_coords]
				chunk.regenerate_mesh()
			
			if not _wall_paint_stroke_active and not affected_wall_chunks.is_empty():
				undo_redo.create_action("terrain wall paint")
				undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, {
					"wall_color_0": pattern,
					"wall_color_1": pattern_cc
				})
				undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, {
					"wall_color_0": restore_pattern,
					"wall_color_1": restore_pattern_cc
				})
				undo_redo.commit_action()
		else:
			# Standard 2D ground painting
			var do_patterns := {
				"color_0": pattern,
				"color_1": pattern_cc
			}
			var undo_patterns := {
				"color_0": restore_pattern,
				"color_1": restore_pattern_cc
			}
			undo_redo.create_action("terrain vertex paint")
			undo_redo.add_do_method(self, "apply_composite_pattern_action", terrain, do_patterns)
			undo_redo.add_undo_method(self, "apply_composite_pattern_action", terrain, undo_patterns)
			undo_redo.commit_action()
	elif mode == TerrainToolMode.GRASS_MASK:
		undo_redo.create_action("terrain grass mask draw")
		undo_redo.add_do_method(self, "draw_grass_mask_pattern_action", terrain, pattern)
		undo_redo.add_undo_method(self, "draw_grass_mask_pattern_action", terrain, restore_pattern)
		undo_redo.commit_action()
	elif mode == TerrainToolMode.POPULATE:
		var action_name := "unkown populator undo/redo"
		if current_populator is MarchingSquaresFlowerPlanter:
			action_name = "terrain flower mask draw"
		undo_redo.create_action(action_name)
		undo_redo.add_do_method(self, "draw_populator_mask_pattern_action", terrain, pattern, remove_selection)
		undo_redo.add_undo_method(self, "draw_populator_mask_pattern_action", terrain, restore_pattern, !remove_selection)
		undo_redo.commit_action()
	else:
		# Handle BRUSH, LEVEL, SMOOTH, BRIDGE, CHUNK_MANAGEMENT modes
		if current_quick_paint:
			# QUICK PAINT MODE: Apply all changes as ONE atomic undo/redo action
			# This fixes the issue where 6 separate actions are created
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
							elif adj_x >=  terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >=  terrain.dimensions.z:
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
						grass_pattern[chunk_coords][cell_coords] = Color(1, 1, 1, 1)
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
			
			if mode == TerrainToolMode.CHUNK_MANAGEMENT:
				apply_composite_pattern_action(terrain, do_patterns)
			else:
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
							elif adj_x >=  terrain.dimensions.x:
								adj_chunk_coords = Vector2i(chunk_coords.x + 1, chunk_coords.y)
								adj_x = 0
							
							if adj_z < 0:
								adj_chunk_coords = Vector2i(adj_chunk_coords.x, chunk_coords.y - 1)
								adj_z = terrain.dimensions.z - 1
							elif adj_z >=  terrain.dimensions.z:
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
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var _height : float = draw_chunk_dict[draw_cell_coords]
			chunk.draw_height(draw_cell_coords.x, draw_cell_coords.y, _height)
		chunk.regenerate_mesh()


func draw_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_grass_mask_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var mask : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_grass_mask(draw_cell_coords.x, draw_cell_coords.y, mask)
		chunk.regenerate_mesh()


func draw_wall_color_0_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_0(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func draw_wall_color_1_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary):
	for draw_chunk_coords: Vector2i in pattern:
		var draw_chunk_dict = pattern[draw_chunk_coords]
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[draw_chunk_coords]
		for draw_cell_coords: Vector2i in draw_chunk_dict:
			var color : Color = draw_chunk_dict[draw_cell_coords]
			chunk.draw_wall_color_1(draw_cell_coords.x, draw_cell_coords.y, color)
		chunk.regenerate_mesh()


func apply_wall_color_map_states_action(terrain: MarchingSquaresTerrain, states: Dictionary) -> void:
	for chunk_coords: Vector2i in states:
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
		if chunk:
			chunk.set_wall_color_map_state(states[chunk_coords])


# Applies all terrain patterns  (for quick paint brush and vertex painting operations)
func apply_composite_pattern_action(terrain: MarchingSquaresTerrain, patterns: Dictionary) -> void:
	var affected_chunks : Dictionary = {}  # chunk_coords -> chunk reference
	
	var composite_disabled := false
	if mode == TerrainToolMode.SMOOTH and current_quick_paint == null:
		composite_disabled = true
	
	# Apply wall colors FIRST (before height changes that create ridge vertices)
	if patterns.has("wall_color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_0:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_0[chunk_coords]:
					chunk.draw_wall_color_0(cell_coords.x, cell_coords.y, patterns.wall_color_0[chunk_coords][cell_coords])
	
	if patterns.has("wall_color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.wall_color_1:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.wall_color_1[chunk_coords]:
					chunk.draw_wall_color_1(cell_coords.x, cell_coords.y, patterns.wall_color_1[chunk_coords][cell_coords])
	
	# Apply height changes (triggers ridge creation which uses wall colors)
	if patterns.has("height") and mode != TerrainToolMode.CHUNK_MANAGEMENT:
		for chunk_coords: Vector2i in patterns.height:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.height[chunk_coords]:
					chunk.draw_height(cell_coords.x, cell_coords.y, patterns.height[chunk_coords][cell_coords])
	
	# Apply grass mask
	if patterns.has("grass_mask") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.grass_mask:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.grass_mask[chunk_coords]:
					chunk.draw_grass_mask(cell_coords.x, cell_coords.y, patterns.grass_mask[chunk_coords][cell_coords])
	
	# Apply ground colors LAST
	if patterns.has("color_0") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_0:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_0[chunk_coords]:
					chunk.draw_color_0(cell_coords.x, cell_coords.y, patterns.color_0[chunk_coords][cell_coords])
	
	if patterns.has("color_1") and not composite_disabled:
		for chunk_coords: Vector2i in patterns.color_1:
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks.get(chunk_coords)
			if chunk:
				affected_chunks[chunk_coords] = chunk
				for cell_coords: Vector2i in patterns.color_1[chunk_coords]:
					chunk.draw_color_1(cell_coords.x, cell_coords.y, patterns.color_1[chunk_coords][cell_coords])
	
	# Regenerate mesh ONCE for each affected chunk (instead of 6 times!)
	for chunk in affected_chunks.values():
		chunk.regenerate_mesh()
	
	# Make affected populators regenerate
	if patterns.has("height"):
		for child in terrain.get_children():
			if child is MarchingSquaresFlowerPlanter:
				for chunk in affected_chunks.values():
					if child.cell_data.has(chunk):
						child.recalculate_cells_in_pattern(patterns.height)
						child.regenerate_flowers()
						break


# Stores chunk and mask data for FlowerPlanters directly in the instance
func draw_populator_mask_pattern_action(terrain: MarchingSquaresTerrain, pattern: Dictionary, is_erase: bool) -> void:
	if current_populator == null:
		printerr("No valid populator selected")
		return
	if not current_populator is MarchingSquaresFlowerPlanter:
		printerr("Couldn't identify a known populator type to draw to")
		return
	
	var flower_planter := current_populator as MarchingSquaresFlowerPlanter
	for chunk_coords in pattern:
		if not terrain.chunks.has(chunk_coords):
			continue
		
		var chunk : MarchingSquaresTerrainChunk = terrain.chunks[chunk_coords]
		for cell_coords in pattern[chunk_coords]:
			# Populate can run before editor geometry exists. Rebuild only the
			# cells being painted instead of regenerating the whole chunk mesh.
			if not chunk.cell_geometry.has(cell_coords):
				chunk.regenerate_cell_geometry(cell_coords)
			if is_erase:
				flower_planter.remove_flowers_from_cell(chunk, cell_coords)
			else:
				flower_planter.add_flowers_to_cell(chunk, cell_coords)
	
	flower_planter.rebuild_cell_data()
	flower_planter.setup(false)
	flower_planter.regenerate_flowers()

#region heightmap related

func run_heightmap_import() -> void:
	if not current_terrain_node:
		push_error("MarchingSquaresTerrainPlugin: No terrain selected for heightmap import.")
		return
	var terrain := current_terrain_node
	
	# Calculate which coords the import will touch (mirrors the importer's offset logic)
	@warning_ignore("integer_division")
	var offset_x : int = -(hm_chunks_x / 2)
	@warning_ignore("integer_division")
	var offset_z : int = -(hm_chunks_z / 2)
	var import_coords : Array = []
	for cz in hm_chunks_z:
		for cx in hm_chunks_x:
			import_coords.append(Vector2i(cx + offset_x, cz + offset_z))
	
	# Snapshot existing chunks at those coords before the import
	var before_snapshot : Dictionary = {}
	for coords in import_coords:
		if terrain.chunks.has(coords):
			before_snapshot[coords] = MSTDataHandler.export_chunk_data(terrain.chunks[coords])
	
	await MarchingSquaresHeightmapImporter.run(
		terrain,
		hm_heightmap_image,
		hm_chunks_x,
		hm_chunks_z,
		hm_max_height,
		hm_merge_mode,
		hm_grass_image,
		hm_texture_image,
		self,
		hm_combined_image if hm_single_file_import else null
	)
	
	# Snapshot newly created chunks after the import
	var after_snapshot : Dictionary = {}
	for coords in import_coords:
		if terrain.chunks.has(coords):
			after_snapshot[coords] = MSTDataHandler.export_chunk_data(terrain.chunks[coords])
	
	var undo_redo := get_undo_redo()
	undo_redo.create_action("heightmap import")
	undo_redo.add_do_method(self, "_replace_chunks_action", terrain, import_coords, after_snapshot)
	undo_redo.add_undo_method(self, "_replace_chunks_action", terrain, import_coords, before_snapshot)
	undo_redo.commit_action(false)


func run_clear_chunks() -> void:
	if not current_terrain_node:
		push_error("MarchingSquaresTerrainPlugin: No terrain selected for clear chunks.")
		return
	var terrain := current_terrain_node
	if terrain.chunks.is_empty():
		return
	
	var coords_to_clear : Array = terrain.chunks.keys().duplicate()
	
	# Snapshot all current chunks before clearing
	var before_snapshot : Dictionary = {}
	for coords in coords_to_clear:
		before_snapshot[coords] = MSTDataHandler.export_chunk_data(terrain.chunks[coords])
	
	var undo_redo := get_undo_redo()
	undo_redo.create_action("clear all chunks")
	undo_redo.add_do_method(self, "_replace_chunks_action", terrain, coords_to_clear, {})
	undo_redo.add_undo_method(self, "_replace_chunks_action", terrain, coords_to_clear, before_snapshot)
	undo_redo.commit_action()


# Removes all chunks at coords_to_clear, then reconstructs from snapshot data.
# Used by undo/redo for heightmap import and clear-all-chunks operations.
func _replace_chunks_action(terrain: MarchingSquaresTerrain, coords_to_clear: Array, snapshot: Dictionary) -> void:
	for coords in coords_to_clear:
		if terrain.chunks.has(coords):
			var chunk : MarchingSquaresTerrainChunk = terrain.chunks[coords]
			terrain.chunks.erase(coords)
			chunk.queue_free()
	for coords in snapshot.keys():
		var data : MSTChunkData = snapshot[coords]
		var chunk := MarchingSquaresTerrainChunk.new()
		chunk.name = "Chunk %s" % str(coords)
		chunk.terrain_system = terrain
		MSTDataHandler.import_chunk_data(chunk, data)
		chunk._data_dirty = true
		terrain.add_chunk(coords, chunk, null, true)
	gizmo_plugin.trigger_redraw(terrain)


func run_heightmap_export() -> void:
	if not current_terrain_node:
		push_error("MarchingSquaresTerrainPlugin: No terrain selected for heightmap export.")
		return
	
	var chunks_to_export : Array[Vector2i] = []
	chunks_to_export.assign(current_terrain_node.chunks.keys())
	
	if chunks_to_export.is_empty():
		push_warning("MarchingSquaresTerrainPlugin: No chunks to export.")
		return
	
	var output_path := hme_output_path if not hme_output_path.is_empty() else "res://"
	
	await MarchingSquaresHeightmapExporter.run(
		current_terrain_node,
		chunks_to_export,
		hme_export_heightmap,
		hme_export_grass,
		hme_export_texture_index,
		output_path,
		self,
		hme_single_file,
		terrain_heightmap_folder_name
	)


func run_heightmap_extraction() -> void:
	if current_heightmap_mesh == null:
		push_error("MarchingSquaresTerrainPlugin: No mesh selected for heightmap extraction.")
		return
	
	var output_path := MESH_HEIGHTMAPS_FOLDER_PATH if not MESH_HEIGHTMAPS_FOLDER_PATH.is_empty() else "res://"
	
	await MarchingSquaresHeightmapExtractor.run(
		current_heightmap_mesh,
		output_path,
		self,
		mesh_heightmap_name
	)

#endregion

#region vertex/texture setters and getters

func _set_vertex_colors(vc_idx: int) -> void:
	var encoded_colors : Array = MSTVertexColorHelper.texture_index_to_colors(vc_idx)
	vertex_color_0 = encoded_colors[0]
	vertex_color_1 = encoded_colors[1]


func _set_new_textures(_preset: MarchingSquaresTexturePreset) -> void:
	if current_terrain_node == null:
		return
	
	if _preset == null:
		_preset = EMPTY_TEXTURE_PRESET
	
	# Apply via terrain API (handles palette/slots/grass + internal batching).
	current_terrain_node.load_from_preset(_preset)
	current_terrain_node.current_texture_preset = _preset
	
	# Mark scene as modified so user knows to save
	EditorInterface.mark_scene_as_unsaved()
	
	# Ensure the Editor is updated live
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
	
	var terrain_cell_size: Vector2 = current_terrain_node.get("cell_size")
	var sx := (h_right - h_left) / (2.0 * terrain_cell_size.x)
	var sz := (h_above - h_below) / (2.0 * terrain_cell_size.y)
	
	var normal := Vector3(-sx, 1.0, -sz).normalized()
	return normal


func _get_flower_cell_data(chunk: MarchingSquaresTerrainChunk, cell: Vector2i) -> Dictionary:
	if not chunk.cell_geometry or not chunk.cell_geometry.has(cell):
		return {}
	
	var cell_data_copy := {}
	var geo_data = chunk.cell_geometry[cell]
	
	cell_data_copy["verts"] = geo_data["verts"]
	cell_data_copy["uvs"] = geo_data["uvs"]
	cell_data_copy["custom_1_values"] = geo_data["custom_1_values"]
	cell_data_copy["is_floor"] = geo_data["is_floor"]
	
	return cell_data_copy


func _find_closest_curve_offset(curve: Curve3D, pos: Vector2) -> float:
	var curve_length : float = curve.get_baked_length()
	var interval : float = curve.bake_interval * 0.25
	var final_offset : float = 0.0
	var optimal_dist_sq : float = INF
	var current_offset : float = 0.0
	
	while current_offset <= curve_length:
		var curve_pos : Vector3 = curve.sample_baked(current_offset)
		var dist_sq : float = pos.distance_squared_to(Vector2(curve_pos.x, curve_pos.z))
		if dist_sq < optimal_dist_sq:
			optimal_dist_sq = dist_sq
			final_offset = current_offset
		current_offset += interval
	
	return final_offset

#endregion
