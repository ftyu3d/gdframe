@tool
class_name GDFrameZipInstall
extends RefCounted

## 将 ZIP 解压到项目资源根；[param map_entry] 将 ZIP 内路径映射为目标资源路径，空串表示跳过。

static func extract_zip_to_res(
	zip_data: PackedByteArray,
	temp_zip_path: String,
	map_entry: Callable,
) -> bool:
	if zip_data.is_empty():
		return false
	var zip_file: FileAccess = FileAccess.open(temp_zip_path, FileAccess.WRITE)
	if zip_file == null:
		return false
	zip_file.store_buffer(zip_data)
	zip_file = null

	var zip: ZIPReader = ZIPReader.new()
	if zip.open(temp_zip_path) != OK:
		_remove_temp_zip(temp_zip_path)
		return false

	var failed_paths: PackedStringArray = PackedStringArray()
	var written_count: int = 0
	for entry_path: String in zip.get_files():
		if entry_path.ends_with("/"):
			continue
		if not map_entry.is_valid():
			continue
		var target_path: String = str(map_entry.call(entry_path))
		if target_path.is_empty():
			continue
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(target_path.get_base_dir())
		)
		var out: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
		if out == null:
			failed_paths.append(target_path)
			continue
		out.store_buffer(zip.read_file(entry_path))
		written_count += 1

	zip.close()
	_remove_temp_zip(temp_zip_path)
	if written_count == 0:
		return false
	return failed_paths.is_empty()


static func _remove_temp_zip(zip_path: String) -> void:
	var abs_zip: String = ProjectSettings.globalize_path(zip_path)
	if FileAccess.file_exists(abs_zip):
		DirAccess.remove_absolute(abs_zip)
