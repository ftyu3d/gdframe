extends RefCounted
## 扫描 [member GDFrameConfig.EXT_ROOT_DIR] 下各子目录的 [code]module.gd[/code]。
## 导出包内用 [method ResourceLoader.list_directory]（[DirAccess] 不可靠）。

const _DIR_SCAN: Script = preload("res://addons/gdframe/runtime/resource_dir_scan.gd")


static func load_modules() -> Array[Script]:
	var out: Array[Script] = []
	_collect_modules(GDFrameConfig.EXT_ROOT_DIR, out)
	out.sort_custom(func(a: Script, b: Script) -> bool:
		return a.resource_path < b.resource_path
	)
	return out


static func _collect_modules(dir_path: String, out: Array[Script]) -> void:
	_DIR_SCAN.each_child(
		dir_path,
		func(parent: String, listed: PackedStringArray) -> void:
			_collect_from_listing(parent, listed, out),
		func(parent: String) -> void:
			_collect_with_dir_access(parent, out),
	)


static func _collect_from_listing(
	dir_path: String, listed: PackedStringArray, out: Array[Script]
) -> void:
	for entry: String in listed:
		if not entry.ends_with("/"):
			continue
		var sub: String = entry.trim_suffix("/")
		if sub.begins_with("."):
			continue
		var module_path: String = dir_path.path_join(sub).path_join("module.gd")
		if ResourceLoader.exists(module_path):
			var script: Script = load(module_path) as Script
			if script != null:
				out.append(script)


static func _collect_with_dir_access(dir_path: String, out: Array[Script]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for entry: String in dir.get_directories():
		if entry.begins_with("."):
			continue
		var module_path: String = dir_path.path_join(entry).path_join("module.gd")
		if ResourceLoader.exists(module_path):
			var script: Script = load(module_path) as Script
			if script != null:
				out.append(script)
