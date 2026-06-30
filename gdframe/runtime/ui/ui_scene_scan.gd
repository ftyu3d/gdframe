extends RefCounted

## 递归收集 `ui_*.tscn` 路径（`GDFrame` 启动注册与编辑器 Dock 列表共用）。
## 导出包内用 [method ResourceLoader.list_directory]（[DirAccess] 不可靠）。

const _DIR_SCAN: Script = preload("res://addons/gdframe/runtime/resource_dir_scan.gd")


static func collect_ui_scene_paths(root_dir: String) -> Array[String]:
	var out: Array[String] = []
	_collect_recursive(root_dir, out)
	return out


static func _collect_recursive(dir_path: String, out: Array[String]) -> void:
	_DIR_SCAN.each_child(
		dir_path,
		func(parent: String, listed: PackedStringArray) -> void:
			_collect_from_listing(parent, listed, out),
		func(parent: String) -> void:
			_collect_with_dir_access(parent, out),
	)


static func _collect_from_listing(dir_path: String, listed: PackedStringArray, out: Array[String]) -> void:
	for item: String in listed:
		if item.ends_with("/"):
			var sub: String = item.trim_suffix("/")
			_collect_recursive("%s/%s" % [dir_path, sub], out)
			continue
		if not item.ends_with(".tscn"):
			continue
		var scene_name: String = item.get_basename()
		if scene_name.begins_with("ui_"):
			out.append("%s/%s" % [dir_path, item])


static func _collect_with_dir_access(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for item: String in dir.get_files():
		if item.ends_with(".tscn"):
			var scene_name: String = item.get_basename()
			if scene_name.begins_with("ui_"):
				out.append("%s/%s" % [dir_path, item])
	for sub: String in dir.get_directories():
		_collect_recursive("%s/%s" % [dir_path, sub], out)
