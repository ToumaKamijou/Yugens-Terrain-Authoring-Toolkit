extends Object
class_name EngineWrapper


static var _instance : EngineWrapper = null
static var instance : EngineWrapper:
	get:
		if _instance == null:
			_instance = EngineWrapper.new()
		return _instance


func is_editor() -> bool:
	return Engine.is_editor_hint()


func get_edited_scene_root() -> Node:
	var editor_interface := Engine.get_singleton('EditorInterface')
	return editor_interface.get_edited_scene_root()


func mark_scene_as_unsaved() -> void:
	var editor_interface = Engine.get_singleton('EditorInterface')
	editor_interface.mark_scene_as_unsaved()


func get_root_for_node(node: Node) -> Node:
	if is_editor():
		return get_edited_scene_root()
	return node.get_tree().root


func set_owner_recursive(node: Node, _owner: Node = null) -> void:
	if not _owner:
		_owner = get_root_for_node(node)
	node.owner = _owner
	for c in node.get_children():
		set_owner_recursive(c, _owner)


static func load_resource(path: String) -> Resource:
	if not path:
		return null
	# Prefer direct ResourceLoader for both uid:// and res:// paths
	if path.begins_with("uid://") or path.begins_with("res://"):
		return ResourceLoader.load(path)
	# Fallback: try as res:// path
	var res_path := path
	if not res_path.begins_with("res://"):
		res_path = "res://" + path
	return ResourceLoader.load(res_path)


static func load_script(path: String) -> Script:
	return load_resource(path) as Script
