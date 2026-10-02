@tool
class_name GDFrameZipInstall
extends RefCounted

## 将 ZIP 解压到工程；[param map_entry] 把条目映射为 [code]res://[/code] 路径（空串跳过）。
## [param mirror_sync_root] 非空时删除该目录下未出现在 ZIP 中的文件。
## [param preserve_rel_paths] / [param keep_existing_rel_paths]：相对 [param mirror_sync_root]；后者在目标已存在时不解压覆盖。

static func map_entry_under_prefix(entry_path: String, addons_prefix: String) -> String:
	var normalized: String = entry_path.replace("\\", "/").strip_edges()
	if normalized.is_empty() or normalized.begins_with("/") or normalized.find("..") >= 0:
		return ""
	var prefix: String = addons_prefix.replace("\\", "/").strip_edges()
	if not prefix.ends_with("/"):
		prefix += "/"
	if not normalized.begins_with(prefix) or normalized.ends_with("/"):
		return ""
	return "res://" + normalized


static func extract_zip_to_res(
	zip_data: PackedByteArray,
	temp_zip_path: String,
	map_entry: Callable,
	mirror_sync_root: String = "",
	preserve_rel_paths: Array[String] = [],
	keep_existing_rel_paths: Array[String] = [],
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

	var root_res: String = _normalize_res_path(mirror_sync_root)
	var keep_existing: Dictionary = {}
	if not root_res.is_empty():
		keep_existing = _build_preserve_set(root_res, keep_existing_rel_paths)

	var failed_paths: PackedStringArray = PackedStringArray()
	var written_paths: Dictionary = {}
	var written_count: int = 0
	for entry_path: String in zip.get_files():
		if entry_path.ends_with("/"):
			continue
		var target_path: String = _normalize_res_path(str(map_entry.call(entry_path)))
		if target_path.is_empty():
			continue
		if keep_existing.has(target_path) and FileAccess.file_exists(target_path):
			written_paths[target_path] = true
			written_count += 1
			continue
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(target_path.get_base_dir())
		)
		var out: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
		if out == null:
			failed_paths.append(target_path)
			continue
		out.store_buffer(zip.read_file(entry_path))
		written_paths[target_path] = true
		written_count += 1

	zip.close()
	_remove_temp_zip(temp_zip_path)
	if written_count == 0 or not failed_paths.is_empty():
		return false
	if mirror_sync_root.is_empty():
		return true

	var sync_preserve: Array[String] = preserve_rel_paths.duplicate()
	for rel_path: String in keep_existing_rel_paths:
		sync_preserve.append(rel_path)
	return _mirror_sync_res_tree(mirror_sync_root, written_paths, sync_preserve).is_empty()


static func _mirror_sync_res_tree(
	mirror_sync_root: String,
	expected_files: Dictionary,
	preserve_rel_paths: Array[String],
) -> PackedStringArray:
	var failed_paths: PackedStringArray = PackedStringArray()
	var root_res: String = _normalize_res_path(mirror_sync_root)
	if not _is_safe_mirror_root(root_res):
		failed_paths.append(root_res)
		return failed_paths

	var preserve: Dictionary = _build_preserve_set(root_res, preserve_rel_paths)
	var abs_root: String = ProjectSettings.globalize_path(root_res)
	if not DirAccess.dir_exists_absolute(abs_root):
		return failed_paths

	_mirror_sync_abs_dir(abs_root, root_res, expected_files, preserve, failed_paths)
	_prune_empty_dirs(abs_root)
	return failed_paths


static func _mirror_sync_abs_dir(
	abs_dir: String,
	res_dir: String,
	expected_files: Dictionary,
	preserve: Dictionary,
	failed_paths: PackedStringArray,
) -> void:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		failed_paths.append(res_dir)
		return

	for sub: String in dir.get_directories():
		_mirror_sync_abs_dir(
			abs_dir.path_join(sub),
			res_dir.path_join(sub),
			expected_files,
			preserve,
			failed_paths,
		)

	for fname: String in dir.get_files():
		var res_file: String = _normalize_res_path(res_dir.path_join(fname))
		if expected_files.has(res_file) or preserve.has(res_file):
			continue
		var abs_file: String = abs_dir.path_join(fname)
		if DirAccess.remove_absolute(abs_file) != OK:
			failed_paths.append(res_file)


static func _build_preserve_set(
	root_res: String,
	preserve_rel_paths: Array[String],
) -> Dictionary:
	var preserve: Dictionary = {}
	for rel_path: String in preserve_rel_paths:
		var rel: String = rel_path.replace("\\", "/").strip_edges()
		if rel.is_empty():
			continue
		while rel.begins_with("/"):
			rel = rel.substr(1)
		preserve[_normalize_res_path(root_res.path_join(rel))] = true
	return preserve


static func _prune_empty_dirs(abs_root: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_root):
		return
	var dir: DirAccess = DirAccess.open(abs_root)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		var sub_abs: String = abs_root.path_join(sub)
		_prune_empty_dirs(sub_abs)
		if _is_dir_empty(sub_abs):
			DirAccess.remove_absolute(sub_abs)


static func _is_dir_empty(abs_dir: String) -> bool:
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return false
	return dir.get_directories().is_empty() and dir.get_files().is_empty()


static func _is_safe_mirror_root(res_path: String) -> bool:
	if not res_path.begins_with("res://"):
		return false
	var rel: String = res_path.substr(6)
	return not rel.is_empty() and rel.find("..") < 0 and rel.contains("/")


static func _normalize_res_path(path: String) -> String:
	var normalized: String = path.replace("\\", "/").strip_edges()
	while normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized


static func _remove_temp_zip(zip_path: String) -> void:
	var abs_zip: String = ProjectSettings.globalize_path(zip_path)
	if FileAccess.file_exists(abs_zip):
		DirAccess.remove_absolute(abs_zip)
