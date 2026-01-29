@icon("res://addons/MarchingSquaresTerrain/editor/icons/toolicon.svg")
extends Resource
class_name MarchingSquaresTool


# Tool data
@export var icon : CompressedTexture2D
@export var label : String
@export_multiline var tooltip : String
@export var attributes : MarchingSquaresToolAttributeSettings
