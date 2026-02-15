@tool
extends Node
class_name MarchingSquaresToolbox


var tools : Array[MarchingSquaresTool] = [
	# Landscaping tools
	preload("uid://bffrekor2ywbf"), # Brush tool
	preload("uid://s20yvwyymlxn"), # Level tool
	preload("uid://bsitspr8c32u6"), # Smooth tool
	preload("uid://b0bj3ba8e7y17"), # Bridge tool
	# Terrain visuals tools
	preload("uid://c3rtgj17vcsk6"), # Grass mask tool
	preload("uid://bhf01bmk6l3gv"), # Vertex paint tool
	preload("uid://bikg2xu4h6ulo"), # Populate tool
	# General plugin tools
	preload("uid://ktb4desoyt1j"), # Debug brush tool
	preload("uid://ups2hlmespdm"), # Chunk manager tool
	preload("uid://vh1ngh2y52b8"), # Terrain settings tool
]
