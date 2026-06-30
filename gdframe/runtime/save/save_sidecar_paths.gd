extends RefCounted
class_name GDFrameSaveSidecarPaths

## 存档 sidecar（[code].tmp[/code] / [code].bak[/code]）路径工具；profile 与槽位共用。


static func tmp_path(path: String) -> String:
	var ext: String = path.get_extension()
	if ext.is_empty():
		return path + ".tmp"
	return "%s.tmp.%s" % [path.get_basename(), ext]


static func bak_path(path: String) -> String:
	var ext: String = path.get_extension()
	if ext.is_empty():
		return path + ".bak"
	return "%s.bak.%s" % [path.get_basename(), ext]


static func all_side_paths(path: String) -> Array[String]:
	return [tmp_path(path), bak_path(path)]


static func has_side_files(path: String) -> bool:
	for side: String in all_side_paths(path):
		if FileAccess.file_exists(ProjectSettings.globalize_path(side)):
			return true
	return false


static func remove_all_path_variants(path: String) -> bool:
	var ok: bool = true
	var paths: Array[String] = [path]
	paths.append_array(all_side_paths(path))
	for p: String in paths:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs) and DirAccess.remove_absolute(abs) != OK:
			ok = false
	return ok
