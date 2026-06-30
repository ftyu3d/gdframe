@tool
extends RefCounted
class_name GDFrameSaveFormatConvert
## 编辑器 Dock：将 [code]user://gdframe[/code] 下存档在 [code].tres[/code] / [code].res[/code] 间批量转换。

## 返回 [code]ok[/code]、[code]message[/code]、[code]converted[/code]。
static func convert_user_saves_format(target_ext: String) -> Dictionary:
	if target_ext != ".tres" and target_ext != ".res":
		return {"ok": false, "message": "无效存档扩展名。", "converted": 0}
	var old_ext: String = ".res" if target_ext == ".tres" else ".tres"
	var mgr := GDFrameSaveManager.new()
	mgr._format_ext = old_ext
	mgr._user_root = GDFrameSaveManager.USER_ROOT_URL
	mgr._rebuild_paths()
	var recover_err: StringName = mgr.recover_all_pending_saves()
	if not GDFrameResult.is_ok(recover_err):
		return {
			"ok": false,
			"message": "恢复未完成存档失败，请先处理残留文件。",
			"converted": 0,
		}
	var paths: PackedStringArray = _collect_main_resource_paths(mgr, old_ext)
	if paths.is_empty():
		return {"ok": true, "message": "无现有存档，已切换格式。", "converted": 0}
	var staged: Array[Dictionary] = []
	for path: String in paths:
		var stage: Dictionary = _stage_resource_file_conversion(path, target_ext)
		if not bool(stage.get("ok", false)):
			_rollback_staged_conversions(staged)
			return {
				"ok": false,
				"message": str(stage.get("message", "转换失败：%s" % path)),
				"converted": 0,
			}
		staged.append(stage)
	for stage: Dictionary in staged:
		var old_path: String = str(stage.get("old_path", ""))
		if not _remove_all_path_variants(old_path):
			_rollback_staged_conversions(staged)
			return {
				"ok": false,
				"message": "转换失败：无法删除旧文件 %s" % old_path,
				"converted": 0,
			}
	return {
		"ok": true,
		"message": "已转换 %d 个存档文件。" % staged.size(),
		"converted": staged.size(),
	}


static func _collect_main_resource_paths(mgr: GDFrameSaveManager, ext: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var profile_path: String = mgr._user_root.path_join(
		GDFrameSaveManager.PROFILE_BASENAME + ext
	)
	if _disk_path_exists(profile_path):
		out.append(profile_path)
	_collect_dir_main_resource_paths(mgr.get_slots_dir(), ext, out)
	_collect_dir_main_resource_paths(mgr.get_slot_meta_dir(), ext, out)
	return out


static func _collect_dir_main_resource_paths(
	dir_url: String, ext: String, out: PackedStringArray
) -> void:
	var abs_dir: String = ProjectSettings.globalize_path(dir_url)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return
	var tmp_tail: String = ".tmp" + ext
	var bak_tail: String = ".bak" + ext
	for file_name: String in dir.get_files():
		if file_name.ends_with(tmp_tail) or file_name.ends_with(bak_tail):
			continue
		if file_name.ends_with(ext):
			out.append(dir_url.path_join(file_name))


static func _disk_path_exists(res_path: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(res_path))


static func _stage_resource_file_conversion(old_path: String, target_ext: String) -> Dictionary:
	if _has_side_files(old_path):
		return {"ok": false, "message": "存在未完成 sidecar：%s" % old_path}
	if not ResourceLoader.exists(old_path):
		return {"ok": false, "message": "无法加载：%s" % old_path}
	var loaded: Resource = ResourceLoader.load(old_path) as Resource
	if loaded == null:
		return {"ok": false, "message": "无法加载：%s" % old_path}
	var old_ext: String = ".%s" % old_path.get_extension()
	var new_path: String = old_path.trim_suffix(old_ext) + target_ext
	if new_path == old_path:
		return {"ok": true, "old_path": old_path, "new_path": new_path}
	if _disk_path_exists(new_path):
		return {"ok": false, "message": "目标已存在：%s" % new_path}
	var save_err: Error = ResourceSaver.save(loaded, new_path)
	if save_err != OK:
		push_error("GDFrame Save: 转换写入失败 %s（err=%s）" % [new_path, save_err])
		return {"ok": false, "message": "写入失败：%s" % new_path}
	return {"ok": true, "old_path": old_path, "new_path": new_path}


static func _rollback_staged_conversions(staged: Array[Dictionary]) -> void:
	for stage: Dictionary in staged:
		var new_path: String = str(stage.get("new_path", ""))
		if new_path.is_empty():
			continue
		_remove_all_path_variants(new_path)


static func _has_side_files(path: String) -> bool:
	return GDFrameSaveSidecarPaths.has_side_files(path)


static func _remove_all_path_variants(path: String) -> bool:
	return GDFrameSaveSidecarPaths.remove_all_path_variants(path)
