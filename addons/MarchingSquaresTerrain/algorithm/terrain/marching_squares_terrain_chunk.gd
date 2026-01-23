@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk


enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}
const MERGE_MODE = {
	Mode.CUBIC: 0.6,
	Mode.POLYHEDRON: 1.3,
	Mode.ROUNDED_POLYHEDRON: 2.1,
	Mode.SEMI_ROUND: 5.0,
	Mode.SPHERICAL: 20.0,
}

# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : MarchingSquaresTerrain
@export var chunk_coords : Vector2i = Vector2i.ZERO
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.POLYHEDRON: # The max height distance between points before a wall is created between them
	set(mode):
		merge_mode = mode
		merge_threshold = MERGE_MODE[mode]
		if is_inside_tree():
			var grass_mat := grass_planter.multimesh.mesh.surface_get_material(0) as ShaderMaterial
			if mode == Mode.SEMI_ROUND or Mode.SPHERICAL:
				grass_mat.set_shader_parameter("is_merge_round", true)
			else:
				grass_mat.set_shader_parameter("is_merge_round", false)
			regenerate_all_cells()
@export_storage var height_map : Array # Stores the heights from the heightmap.
@export_storage var color_map_0 : PackedColorArray # Stores the colors from vertex_color_0
@export_storage var color_map_1 : PackedColorArray # Stores the colors from vertex_color_1.
@export_storage var grass_mask_map : PackedColorArray # Stores if a cell should have grass or not.

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : GrassPlanter = preload("res://addons/MarchingSquaresTerrain/algorithm/grass/grass_planter.tscn").instantiate()

var cell_factory : MarchingSquaresCellFactory = MarchingSquaresCellFactory.new(MarchingSquaresCellFactory.CellType.AUTHORED)

# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size

var new_chunk : bool = false

var st : SurfaceTool # The surfacetool used to construct the current terrain
var cell_coords : Vector2i # cell coordinates currently being evaluated

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.


# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool = true):
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)
	
	if not grass_planter:
		grass_planter = get_node_or_null("GrassPlanter")
		if grass_planter:
			grass_planter._chunk = self
	
		if not height_map:
			generate_height_map()
		if not color_map_0 or not color_map_1:
			generate_color_maps()
		if not grass_mask_map:
			generate_grass_mask_map()
		if not mesh and should_regenerate_mesh:
			regenerate_mesh()
		for child in get_children():
			if child is StaticBody3D:
				child.collision_layer = 17 # ground (1) + terrain (16)
		
		grass_planter.setup(self, true)
		grass_planter.regenerate_all_cells()


func _exit_tree() -> void:
	if terrain_system:
		terrain_system.chunks.erase(chunk_coords)
	
	var scene = get_tree().current_scene
	if scene:
		ResourceSaver.save(mesh, "res://"+scene.name+"/"+name+".tres", ResourceSaver.FLAG_COMPRESS)


func regenerate_mesh():
	st = SurfaceTool.new()
	if mesh:
		st.create_from(mesh, 0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	
	var start_time: int = Time.get_ticks_msec()
	
	if not get_node_or_null("GrassPlanter"):
		grass_planter = get_node_or_null("GrassPlanter")
		if not grass_planter:
			grass_planter = GrassPlanter.new()
			if not color_map_0 or not color_map_1:
				generate_color_maps()
			if not grass_mask_map:
				generate_grass_mask_map()
			new_chunk = true
		grass_planter.name = "GrassPlanter"
		add_child(grass_planter)
		grass_planter._chunk = self
		grass_planter.setup(self)
		if Engine.is_editor_hint():
			grass_planter.owner = EditorInterface.get_edited_scene_root()
	else:
		grass_planter._chunk = self
	
	generate_terrain_cells()
	
	if new_chunk:
		new_chunk = false
	
	st.generate_normals()
	st.index()
	
	# Create a new mesh out of floor, and add the wall surface to it
	mesh = st.commit()
	
	if mesh and terrain_system:
		mesh.surface_set_material(0, terrain_system.terrain_material)
	
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	create_trimesh_collision()
	for child in get_children():
		if child is StaticBody3D:
			child.collision_layer = 17 # ground (1) + terrain (16)
	
	var elapsed_time: int = Time.get_ticks_msec() - start_time
	print_verbose("Generated terrain in "+str(elapsed_time)+"ms")


func generate_terrain_cells():
	if not cell_geometry:
		cell_geometry = {}
	
	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			cell_coords = Vector2i(x, z)
			
			# If geometry did not change, copy already generated geometry and skip this cell
			if not needs_update[z][x]:
				var verts = cell_geometry[cell_coords]["verts"]
				var uvs = cell_geometry[cell_coords]["uvs"]
				var uv2s = cell_geometry[cell_coords]["uv2s"]
				var colors_0 = cell_geometry[cell_coords]["colors_0"]
				var colors_1 = cell_geometry[cell_coords]["colors_1"]
				var grass_mask = cell_geometry[cell_coords]["grass_mask"]
				var is_floor = cell_geometry[cell_coords]["is_floor"]
				for i in range(len(verts)):
					st.set_smooth_group(0 if is_floor[i] == true else -1)
					st.set_uv(uvs[i])
					st.set_uv2(uv2s[i])
					st.set_color(colors_0[i])
					st.set_custom(0, colors_1[i])
					st.set_custom(1, grass_mask[i])
					st.add_vertex(verts[i])
				continue
			
			# Cell is now being updated, set needs update to false
			needs_update[z][x] = false
			
			# If geometry did change or none exists yet, 
			# Create an entry for this cell (will also override any existing one)
			cell_geometry[cell_coords] = {
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"uv2s": PackedVector2Array(),
				"colors_0": PackedColorArray(),
				"colors_1": PackedColorArray(),
				"grass_mask": PackedColorArray(),
				"is_floor": [],
			}
			
			var cell := cell_factory.create(height_map[z][x], height_map[z][x+1], height_map[z+1][x], height_map[z+1][x+1], merge_threshold)
			cell.generate_geometry(self)
			if grass_planter and grass_planter.terrain_system:
				grass_planter.generate_grass_on_cell(cell_coords)

# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative).
# UV.x is closeness to the bottom of an edge. and UV.Y is closeness to the edge of a cliff.
func add_point(x: float, y: float, z: float, uv_x: float, uv_y: float, ro: MarchingSquaresTerrainCell.CellRotation, diag_midpoint: bool = false):
	for i in range(ro as int):
		var temp = x
		x = 1 - z
		z = temp
	
	# uv - used for ledge detection. X = closeness to top terrace, Y = closeness to bottom of terrace
	# Walls will always have UV of 1, 1
	var uv = Vector2(uv_x, uv_y) if floor_mode else Vector2(1, 1)
	st.set_uv(uv)
	
	# Use the minimum between both lerped diagonals, component-wise
	# Will result in smoother diagonal paths
	var color_0: Color
	if new_chunk:
		color_0 = Color(1.0, 0.0, 0.0, 0.0)
		color_map_0[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		var ad_color = lerp(color_map_0[cell_coords.y*dimensions.x + cell_coords.x], color_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], 0.5)
		var bc_color = lerp(color_map_0[cell_coords.y*dimensions.x + cell_coords.x + 1], color_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x], 0.5)
		color_0 = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
		if ad_color.r > 0.99 or bc_color.r > 0.99: color_0.r = 1.0;
		if ad_color.g > 0.99 or bc_color.g > 0.99: color_0.g = 1.0;
		if ad_color.b > 0.99 or bc_color.b > 0.99: color_0.b = 1.0;
		if ad_color.a > 0.99 or bc_color.a > 0.99: color_0.a = 1.0;
	else:
		var ab_color = lerp(color_map_0[cell_coords.y*dimensions.x + cell_coords.x], color_map_0[cell_coords.y*dimensions.x + cell_coords.x + 1], x)
		var cd_color = lerp(color_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x], color_map_0[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], x)
		color_0 = get_dominant_color(lerp(ab_color, cd_color, z)) #Use this for mixed triangles
		#color_0 = color_map_0[cell_coords.y * dimensions.x + cell_coords.x] #Use this for perfect square tiles
	st.set_color(color_0)
	
	var color_1: Color
	if new_chunk:
		color_1 = Color(1.0, 0.0, 0.0, 0.0)
		color_map_1[cell_coords.y*dimensions.x + cell_coords.x] = Color(1.0, 0.0, 0.0, 0.0)
	elif diag_midpoint:
		var ad_color = lerp(color_map_1[cell_coords.y*dimensions.x + cell_coords.x], color_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], 0.5)
		var bc_color = lerp(color_map_1[cell_coords.y*dimensions.x + cell_coords.x + 1], color_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x], 0.5)
		color_1 = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
		if ad_color.r > 0.99 or bc_color.r > 0.99: color_0.r = 1.0;
		if ad_color.g > 0.99 or bc_color.g > 0.99: color_0.g = 1.0;
		if ad_color.b > 0.99 or bc_color.b > 0.99: color_0.b = 1.0;
		if ad_color.a > 0.99 or bc_color.a > 0.99: color_0.a = 1.0;
	else:
		var ab_color = lerp(color_map_1[cell_coords.y*dimensions.x + cell_coords.x], color_map_1[cell_coords.y*dimensions.x + cell_coords.x + 1], x)
		var cd_color = lerp(color_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x], color_map_1[(cell_coords.y + 1)*dimensions.x + cell_coords.x + 1], x)
		color_1 = get_dominant_color(lerp(ab_color, cd_color, z)) #Use this for mixed triangles
		#color_1 = color_map_1[cell_coords.y * dimensions.x + cell_coords.x] #Use this for perfect square tiles
	st.set_custom(0, color_1)
	
	var is_ridge := false
	if floor_mode and terrain_system.use_ridge_texture:
		is_ridge = (uv.y > 1.0 - terrain_system.ridge_threshold)
	var g_mask: Color = grass_mask_map[cell_coords.y*dimensions.x + cell_coords.x]
	g_mask.g = 1.0 if is_ridge else 0.0
	st.set_custom(1, g_mask)
	
	var vert := Vector3((cell_coords.x+x) * cell_size.x, y, (cell_coords.y+z) * cell_size.y)
	var uv2: Vector2
	if floor_mode:
		uv2 = Vector2(vert.x, vert.z) / cell_size
	else:
		var global_pos := vert + get_global_pos()
		uv2 = (Vector2(global_pos.x, global_pos.y) + Vector2(global_pos.z, global_pos.y))
	
	st.set_uv2(uv2)
	st.add_vertex(vert)
	
	cell_geometry[cell_coords]["verts"].append(vert)
	cell_geometry[cell_coords]["uvs"].append(uv)
	cell_geometry[cell_coords]["uv2s"].append(uv2)
	cell_geometry[cell_coords]["colors_0"].append(color_0)
	cell_geometry[cell_coords]["colors_1"].append(color_1)
	cell_geometry[cell_coords]["grass_mask"].append(g_mask)
	cell_geometry[cell_coords]["is_floor"].append(floor_mode)

func get_global_pos() -> Vector3:
	if is_inside_tree():
		return global_position
	return Vector3.ZERO

func get_dominant_color(c: Color) -> Color:
	var max_val := c.r
	var idx : int = 0
	
	if c.g > max_val:
		max_val = c.g
		idx = 1
	if c.b > max_val:
		max_val = c.b
		idx = 2
	if c.a > max_val:
		idx = 3
	
	var new_color := Color(0, 0, 0, 0)
	match idx:
		0: new_color.r = 1.0
		1: new_color.g = 1.0
		2: new_color.b = 1.0
		3: new_color.a = 1.0
	
	return new_color


# If true, currently making floor geometry. if false, currently making wall geometry.
var floor_mode : bool = true

func start_floor():
	floor_mode = true
	st.set_smooth_group(0)


func start_wall():
	floor_mode = false
	st.set_smooth_group(-1)

func generate_height_map():
	height_map = []
	height_map.resize(dimensions.z)
	for z in range(dimensions.z):
		height_map[z] = []
		height_map[z].resize(dimensions.x)
		for x in range(dimensions.x):
			height_map[z][x] = 0.0
		
	var noise = terrain_system.noise_hmap
	if noise:
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var noise_x = (chunk_coords.x * (dimensions.x - 1)) + x
				var noise_z = (chunk_coords.y * (dimensions.z -1)) + z
				var noise_sample = noise.get_noise_2d(noise_x, noise_z)
				height_map[z][x] = noise_sample * dimensions.y


func generate_color_maps():
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	color_map_0.resize(dimensions.z * dimensions.x)
	color_map_1.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			color_map_0[z*dimensions.x + x] = Color(0,0,0,0)
			color_map_1[z*dimensions.x + x] = Color(0,0,0,0)


func generate_grass_mask_map():
	grass_mask_map = Array()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.z + x] = Color(1.0, 1.0, 1.0, 1.0)


func get_height(cc: Vector2i) -> float:
	return height_map[cc.y][cc.x]


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cc.y*dimensions.x + cc.x]

func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cc.y*dimensions.x + cc.x]


func get_grass_mask(cc: Vector2i) -> Color:
	return grass_mask_map[cc.y*dimensions.x + cc.x]


# Draw to height.
# Returns the coordinates of all additional chunks affected by this height change.
# Empty for inner points, neightoring edge for non-corner edges, and 3 other corners for corner points.
func draw_height(x: int, z: int, y: float):
	# Contains chunks that were updated
	height_map[z][x] = y
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[z*dimensions.x + x] = color
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[z*dimensions.x + x] = masked
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func notify_needs_update(z: int, x: int):
	if z < 0 or z >= terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return
		
	needs_update[z][x] = true


func regenerate_all_cells():
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true
			
	regenerate_mesh()
