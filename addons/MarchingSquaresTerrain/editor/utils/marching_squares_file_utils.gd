@tool
class_name MarchingSquaresFileUtils


## Recursively calculate the size of a directory in bytes
static func get_directory_size_recursive(dir_path: String) -> int:
	var total_size : int = 0
	var dir := DirAccess.open(dir_path)
	if not dir:
		return 0

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				total_size += get_directory_size_recursive(dir_path + file_name + "/")
		else:
			total_size += FileAccess.get_file_as_bytes(dir_path + file_name).size()
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return total_size
