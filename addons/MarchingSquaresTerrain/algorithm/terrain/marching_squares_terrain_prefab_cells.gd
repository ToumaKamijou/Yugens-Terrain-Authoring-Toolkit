@tool
extends Resource
class_name MarchingSquaresTerrainPrefabCells

@export var c0_scene: PackedScene
@export var c1_scene: PackedScene
@export var c2_scene: PackedScene
@export var c3_scene: PackedScene
@export var c4_scene: PackedScene
@export var c5_scene: PackedScene
@export var c5b_scene: PackedScene
@export var c6_scene: PackedScene
@export var c7_scene: PackedScene
@export var c8_scene: PackedScene
@export var c9_scene: PackedScene
@export var c10_scene: PackedScene
@export var c11_scene: PackedScene
@export var c12_scene: PackedScene
@export var c13_scene: PackedScene
@export var c14_scene: PackedScene
@export var c15_scene: PackedScene
@export var c16_scene: PackedScene
@export var c17_scene: PackedScene

var _c0: MeshInstance3D 
var _c1: MeshInstance3D
var _c2: MeshInstance3D
var _c3: MeshInstance3D
var _c4: MeshInstance3D
var _c5: MeshInstance3D
var _c5b: MeshInstance3D
var _c6: MeshInstance3D
var _c7: MeshInstance3D
var _c8: MeshInstance3D
var _c9: MeshInstance3D
var _c10: MeshInstance3D
var _c11: MeshInstance3D
var _c12: MeshInstance3D
var _c13: MeshInstance3D
var _c14: MeshInstance3D
var _c15: MeshInstance3D
var _c16: MeshInstance3D
var _c17: MeshInstance3D

var c0: MeshInstance3D:
	get: 
		if not _c0: 
			_c0 = c0_scene.instantiate().get_child(0)
		return _c0
var c1: MeshInstance3D:
	get: 
		if not _c1: 
			_c1 = c1_scene.instantiate().get_child(0)
		return _c1
var c2: MeshInstance3D:
	get: 
		if not _c2: 
			_c2 = c2_scene.instantiate().get_child(0)
		return _c2
var c3: MeshInstance3D:
	get: 
		if not _c3: 
			_c3 = c3_scene.instantiate().get_child(0)
		return _c3
var c4: MeshInstance3D:
	get: 
		if not _c4: 
			_c4 = c4_scene.instantiate().get_child(0)
		return _c4
var c5: MeshInstance3D:
	get: 
		if not _c5: 
			_c5 = c5_scene.instantiate().get_child(0)
		return _c5
var c5b: MeshInstance3D:
	get: 
		if not _c5b:
			_c5b = c5b_scene.instantiate().get_child(0)
		return _c5b
var c6: MeshInstance3D:
	get: 
		if not _c6: 
			_c6 = c6_scene.instantiate().get_child(0)
		return _c6
var c7: MeshInstance3D:
	get: 
		if not _c7: 
			_c7 = c7_scene.instantiate().get_child(0)
		return _c7
var c8: MeshInstance3D:
	get: 
		if not _c8: 
			_c8 = c8_scene.instantiate().get_child(0)
		return _c8
var c9: MeshInstance3D:
	get: 
		if not _c9: 
			_c9 = c9_scene.instantiate().get_child(0)
		return _c9
var c10: MeshInstance3D:
	get: 
		if not _c10:
			_c10 = c10_scene.instantiate().get_child(0)
		return _c10
var c11: MeshInstance3D:
	get: 
		if not _c11:
			_c11 = c11_scene.instantiate().get_child(0)
		return _c11
var c12: MeshInstance3D:
	get: 
		if not _c12:
			_c12 = c12_scene.instantiate().get_child(0)
		return _c12
var c13: MeshInstance3D:
	get: 
		if not _c13:
			_c13 = c13_scene.instantiate().get_child(0)
		return _c13
var c14: MeshInstance3D:
	get: 
		if not _c14:
			_c14 = c14_scene.instantiate().get_child(0)
		return _c14
var c15: MeshInstance3D:
	get: 
		if not _c15:
			_c15 = c15_scene.instantiate().get_child(0)
		return _c15
var c16: MeshInstance3D:
	get: 
		if not _c16:
			_c16 = c16_scene.instantiate().get_child(0)
		return _c16
var c17: MeshInstance3D:
	get: 
		if not _c17:
			_c17 = c17_scene.instantiate().get_child(0)
		return _c17
