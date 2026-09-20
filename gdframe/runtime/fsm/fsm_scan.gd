extends RefCounted

## 收集 FSM Registry（命名 fsm_xxx/fsm_xxx_registry.gd）；根目录见 [member GDFrameConfig.FSM_ROOT]。
## 导出包内须用 [method ResourceLoader.list_directory]；[DirAccess] 无法可靠列出资源根下脚本。

const _DIR_SCAN: Script = preload("res://addons/gdframe/runtime/resource_dir_scan.gd")


static func collect_fsm_registry_paths(root_dir: String) -> Array[String]:
	var out: Array[String] = []
	_collect_registry_paths(root_dir, out)
	out.sort()
	return out


static func _collect_registry_paths(dir_path: String, out: Array[String]) -> void:
	_DIR_SCAN.each_child(
		dir_path,
		func(parent: String, listed: PackedStringArray) -> void:
			_collect_from_listing(parent, listed, out),
		func(parent: String) -> void:
			_collect_with_dir_access(parent, out),
	)


static func _collect_from_listing(dir_path: String, listed: PackedStringArray, out: Array[String]) -> void:
	for item: String in listed:
		if not item.ends_with("/"):
			continue
		var sub: String = item.trim_suffix("/")
		if not sub.begins_with("fsm_"):
			continue
		var reg_path: String = "%s/%s/%s_registry.gd" % [dir_path, sub, sub]
		if ResourceLoader.exists(reg_path):
			out.append(reg_path)


static func _collect_with_dir_access(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for item: String in dir.get_directories():
		if not item.begins_with("fsm_"):
			continue
		var reg_path: String = "%s/%s/%s_registry.gd" % [dir_path, item, item]
		if FileAccess.file_exists(reg_path):
			out.append(reg_path)
