@tool
extends Resource
class_name MarchingSquaresPrefab



@export var size : Vector3 = Vector3(0.5, 0.5, 0.5)

class PrefabData:
	var arrays : Array
	var mesh : ArrayMesh
	var weights : Dictionary[String, PackedFloat32Array]
	var size : Vector3

var _arrays : Dictionary[String, PrefabData] = {}


func get_data(key: String) -> PrefabData:
	if _arrays.has(key):
		return _arrays[key]
	return null


func _prepare(key: String, scene: PackedScene, is_diag_floor: bool = false, is_cap_floor: bool = false) -> void:
	if not scene:
		return
	var _inst : Node3D = scene.instantiate()
	var n := _inst.name
	var inst := _inst.get_child(0) as MeshInstance3D
	
	if not inst or not inst.mesh:
		return
	if not inst.mesh is ArrayMesh:
		push_warning(resource_name, ":", " ", key, " Mesh is not an ArrayMesh")
		return
	
	var data := PrefabData.new()
	data.arrays = inst.mesh.surface_get_arrays(0)
	data.weights = {}
	data.mesh = inst.mesh
	
	var verts : PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	var weights_proto := PackedFloat32Array()
	weights_proto.resize(verts.size())
	var weights: Dictionary[String, PackedFloat32Array] = {
		"a": weights_proto,
		"a2": weights_proto.duplicate(),
		"b": weights_proto.duplicate(),
		"b2": weights_proto.duplicate(),
		"c": weights_proto.duplicate(),
		"c2": weights_proto.duplicate(),
		"d": weights_proto.duplicate(),
		"d2": weights_proto.duplicate(),
	}
	
	data.size = size
	for i in verts.size():
		var u : float = verts[i].x / size.x
		var v : float = verts[i].y / size.y
		var w : float = verts[i].z / size.z
		
		var iu := 1.0 - u
		var iv := 1.0 - v
		var iw := 1.0 - w
		
		weights["a2"][i] = iu * iv * iw # w000     a .────────.b        y
		weights["c2"][i] = iu * iv * w  # w001      / :      / │        │ 
		weights["a"][i] = iu * v  * iw  # w010   c ┌──+─────┐d │        │
		weights["c"][i] = iu * v  * w   # w011     │  :     │  │       ,└───> x
		weights["b2"][i] = u  * iv * iw # w100   a2│ ,:.....│..│ b2   /  a2 = origin
		weights["d2"][i] = u  * iv * w  # w101     │:       │ /      z
		weights["b"][i] = u  * v  * iw  # w110  c2 └────────┘ d2   
		weights["d"][i] = u  * v  * w   # w111     
		
		if is_diag_floor: # key.begins_with("m1.2"):
			weights["d"][i] = 0
			weights["a2"][i] = 0
		if is_cap_floor: # key.begins_with("m3.2"):
			weights["b2"][i] = 0
			weights["c2"][i] = 0
		
		# Normalize the weights
		var sum := 0.0
		for k in ["a","b","c","d","a2","b2","c2","d2"]:
			sum += weights[k][i]
		for k in ["a","b","c","d","a2","b2","c2","d2"]:
			weights[k][i] /= sum
	
	data.weights = weights
	_arrays[key] = data
