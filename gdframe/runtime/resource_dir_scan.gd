extends RefCounted
class_name GDFrameResourceDirScan
## 目录列举：导出包内优先 [method ResourceLoader.list_directory]，否则 [DirAccess] 回退。


static func each_child(
	dir_path: String,
	on_listing: Callable,
	on_dir_access: Callable,
) -> void:
	var listed: PackedStringArray = ResourceLoader.list_directory(dir_path)
	if not listed.is_empty():
		on_listing.call(dir_path, listed)
		return
	on_dir_access.call(dir_path)
