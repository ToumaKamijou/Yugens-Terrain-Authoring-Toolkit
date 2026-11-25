@tool
extends Node
class_name MarchingSquaresToolbox


var tools : Dictionary[MarchingSquaresTerrainPlugin.TerrainToolMode, MarchingSquaresTool] = {
	# Landscaping tools
	MarchingSquaresTerrainPlugin.TerrainToolMode.BRUSH : preload("uid://bffrekor2ywbf"), # Brush tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.LEVEL : preload("uid://s20yvwyymlxn"), # Level tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.SMOOTH : preload("uid://bsitspr8c32u6"), # Smooth tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.BRIDGE : preload("uid://b0bj3ba8e7y17"), # Bridge tool
	# Terrain visuals tools
	MarchingSquaresTerrainPlugin.TerrainToolMode.GRASS_MASK : preload("uid://c3rtgj17vcsk6"), # Grass mask tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.VERTEX_PAINTING : preload("uid://bhf01bmk6l3gv"), # Vertex paint tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.POPULATE : preload("uid://bikg2xu4h6ulo"), # Populate tool
	# General plugin tools
	MarchingSquaresTerrainPlugin.TerrainToolMode.DEBUG_BRUSH : preload("uid://ktb4desoyt1j"), # Debug brush tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.CHUNK_MANAGEMENT : preload("uid://ups2hlmespdm"), # Chunk manager tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.HEIGHTMAP : preload("uid://cotf6d0khe2kn"), # Heightmap tool
	MarchingSquaresTerrainPlugin.TerrainToolMode.TERRAIN_SETTINGS : preload("uid://vh1ngh2y52b8"), # Terrain settings tool
}
