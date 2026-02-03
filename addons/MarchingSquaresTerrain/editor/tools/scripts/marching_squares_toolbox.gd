@tool
extends Node
class_name MarchingSquaresToolbox


var tools : Array[MarchingSquaresTool] = [
	# Landscaping tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/brush_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/level_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/smooth_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/bridge_tool.tres"),
	# Terrain visuals tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/grass_mask_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/vertex_paint_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/populate_tool.tres"),
	# General plugin tools
	preload("res://addons/MarchingSquaresTerrain/editor/tools/debug_brush_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/chunk_manager_tool.tres"),
	preload("res://addons/MarchingSquaresTerrain/editor/tools/terrain_settings_tool.tres"),
]
