extends RefCounted
class_name GDFrameSaveManager

# =============================================================================
# Constants
# =============================================================================

const USER_ROOT_URL: String = "user://gdframe"
const SLOTS_SUBDIR: String = "slots"
const SLOTS_META_SUBDIR: String = "meta"
const PROFILE_BASENAME: String = "profile"
const SLOT_META_SCRIPT: Script = preload("res://addons/gdframe/runtime/save/save_slot_meta_resource.gd")

## sidecar 须保留资源扩展名（[code]profile.tmp.tres[/code]）；[code]profile.tres.tmp[/code] 会被当成 [code].tmp[/code] 格式导致 ResourceSaver 失败。

# =============================================================================
# State
# =============================================================================

var _profile: GDFrameProfileResource
var _user_root: String = ""
var _format_ext: String = ""
var _profile_disk_path: String = ""
var _slots_dir: String = ""
var _startup_corrupt_profile: bool = false
var _startup_corrupt_slots: Array[String] = []
var _startup_profile_fallback: bool = false
var _recover_load_cache: Dictionary = {}
var _warned_meta_read: Dictionary = {}

# =============================================================================
# Setup & profile
# =============================================================================

func setup(config: GDFrameConfig) -> StringName:
	_format_ext = config.get_save_extension()
	_user_root = USER_ROOT_URL
	_rebuild_paths()
	_ensure_dir(_user_root)
	var recover_err: StringName = recover_all_pending_saves()
	_profile = _load_profile_from_disk()
	return recover_err

func get_profile() -> GDFrameProfileResource:
	if _profile.settings == null:
		_profile.ensure_children()
	return _profile

func get_slots_dir() -> String:
	return _slots_dir

func get_slot_meta_dir() -> String:
	return _slots_dir.path_join(SLOTS_META_SUBDIR)

func profile_disk_path() -> String:
	return _profile_disk_path

func has_profile_on_disk() -> bool:
	return ResourceLoader.exists(_profile_disk_path)


## 从磁盘重载 profile。磁盘有文件但无法解析时返回 [member GDFrameResult.ERR_SAVE_PROFILE_READ_FAILED] 并[b]保留当前内存档案[/b]（不替换为默认）。

func reload_profile() -> StringName:
	_recover_load_cache.clear()
	var profile_err: StringName = _recover_path(_profile_disk_path)
	if profile_err == GDFrameResult.ERR_SAVE_CORRUPTED:
		_startup_corrupt_profile = true
	elif not GDFrameResult.is_ok(profile_err):
		_recover_load_cache.clear()
		return profile_err
	if not ResourceLoader.exists(_profile_disk_path):
		_profile = _new_default_profile()
		_startup_profile_fallback = false
		_recover_load_cache.clear()
		return GDFrameResult.OK
	var loaded: GDFrameProfileResource = _parse_profile_from_disk()
	if loaded != null:
		_profile = loaded
		_startup_profile_fallback = false
		_recover_load_cache.clear()
		return GDFrameResult.OK
	_recover_load_cache.clear()
	return GDFrameResult.ERR_SAVE_PROFILE_READ_FAILED


## 玩家档案：快照走原子写（[code].tmp[/code]→正式档），成功后内存实例 [code]take_over_path[/code]。

func save_profile() -> StringName:
	var prof: GDFrameProfileResource = get_profile()
	prof.ensure_children()
	_ensure_dir(_user_root)
	var snap: GDFrameProfileResource = prof.duplicate(true) as GDFrameProfileResource
	if snap == null:
		push_error("GDFrame Save: profile 快照失败")
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	_try_recover_incomplete_save(_profile_disk_path)
	var err: StringName = _atomic_save_resource(snap, _profile_disk_path, false)
	if GDFrameResult.is_ok(err):
		prof.take_over_path(_profile_disk_path)
	return err


## 删除磁盘上的 profile（正式档与 sidecar），内存重置为默认档案。

func delete_profile_from_disk() -> StringName:
	if not GDFrameSaveSidecarPaths.remove_all_path_variants(_profile_disk_path):
		return GDFrameResult.ERR_SAVE_DELETE_FAILED
	_profile = _new_default_profile()
	_startup_corrupt_profile = false
	return GDFrameResult.OK

# =============================================================================
# Recovery
# =============================================================================

## 扫描 profile 与全部槽位目录，处理断电残留的 [code].tmp[/code]/[code].bak[/code]。

func recover_all_pending_saves() -> StringName:
	_recover_load_cache.clear()
	_startup_corrupt_profile = false
	_startup_corrupt_slots.clear()
	var profile_err: StringName = _recover_path(_profile_disk_path)
	if profile_err == GDFrameResult.ERR_SAVE_CORRUPTED:
		_startup_corrupt_profile = true
	elif not GDFrameResult.is_ok(profile_err):
		_recover_load_cache.clear()
		return profile_err
	var slots_err: StringName = _recover_slots_directory()
	if not GDFrameResult.is_ok(slots_err):
		_recover_load_cache.clear()
		return slots_err
	var meta_err: StringName = _recover_meta_directory()
	if not GDFrameResult.is_ok(meta_err):
		_recover_load_cache.clear()
		return meta_err
	if _startup_corrupt_profile or not _startup_corrupt_slots.is_empty():
		_recover_load_cache.clear()
		return GDFrameResult.ERR_SAVE_CORRUPTED
	_recover_load_cache.clear()
	return GDFrameResult.OK

func recover_game_slot(slot_id: String) -> StringName:
	_recover_load_cache.clear()
	var path: String = _slot_resource_path(slot_id)
	if path.is_empty():
		return GDFrameResult.ERR_SAVE_SLOT_ID_INVALID
	var err: StringName = _recover_path(path)
	if not GDFrameResult.is_ok(err):
		_recover_load_cache.clear()
		return err
	var meta_path: String = _slot_meta_path(slot_id)
	if not meta_path.is_empty() and _path_has_any_variant(meta_path):
		var meta_err: StringName = _recover_path(meta_path)
		if not GDFrameResult.is_ok(meta_err) and meta_err != GDFrameResult.ERR_SAVE_CORRUPTED:
			_recover_load_cache.clear()
			return meta_err
		if meta_err == GDFrameResult.ERR_SAVE_CORRUPTED:
			push_warning("GDFrame Save: 槽位 meta 损坏已丢弃 %s" % meta_path)
			GDFrameSaveSidecarPaths.remove_all_path_variants(meta_path)
	_recover_load_cache.clear()
	return GDFrameResult.OK


func startup_corrupt_profile() -> bool:
	return _startup_corrupt_profile

func startup_corrupt_slots() -> Array[String]:
	return _startup_corrupt_slots.duplicate()


func startup_profile_fallback() -> bool:
	return _startup_profile_fallback

# =============================================================================
# Slots
# =============================================================================

func write_game_resource(slot_id: String, res: Resource) -> StringName:
	var path: String = _slot_resource_path(slot_id)
	if path.is_empty():
		return GDFrameResult.ERR_SAVE_SLOT_ID_INVALID
	_ensure_dir(get_slots_dir())
	_try_recover_incomplete_save(path)
	var err: StringName = _atomic_save_resource(res, path, true)
	if GDFrameResult.is_ok(err):
		var fields: Dictionary = _meta_fields_from_resource(res)
		if not fields.is_empty():
			var meta_err: StringName = write_slot_meta(slot_id, fields)
			if GDFrameResult.is_error(meta_err):
				meta_err = rebuild_slot_meta_from_save(slot_id)
			if GDFrameResult.is_error(meta_err):
				return GDFrameResult.ERR_SAVE_META_WRITE_FAILED
	return err


## 返回 [code]{ "resource": Resource|null, "error": StringName }[/code]；成功时 [member GDFrameResult.OK]。

func read_game_resource(slot_id: String) -> Dictionary:
	var path: String = _slot_resource_path(slot_id)
	if path.is_empty():
		return {"resource": null, "error": GDFrameResult.ERR_SAVE_SLOT_ID_INVALID}
	_try_recover_incomplete_save(path)
	var side_err: StringName = _check_no_side_files(path)
	if not GDFrameResult.is_ok(side_err):
		return {"resource": null, "error": side_err}
	if not ResourceLoader.exists(path):
		return {"resource": null, "error": GDFrameResult.ERR_SAVE_SLOT_NOT_FOUND}
	var loaded: Resource = ResourceLoader.load(path) as Resource
	if loaded == null:
		return {"resource": null, "error": GDFrameResult.ERR_SAVE_READ_FAILED}
	return {"resource": loaded, "error": GDFrameResult.OK}

func has_game_slot(slot_id: String) -> bool:
	var path: String = _slot_resource_path(slot_id)
	return not path.is_empty() and ResourceLoader.exists(path)

func delete_game_resource(slot_id: String) -> StringName:
	var path: String = _slot_resource_path(slot_id)
	if path.is_empty():
		return GDFrameResult.ERR_SAVE_SLOT_ID_INVALID
	if not _path_has_any_variant(path) and not _path_has_any_variant(_slot_meta_path(slot_id)):
		return GDFrameResult.ERR_SAVE_SLOT_NOT_FOUND
	if _path_has_any_variant(path) and not GDFrameSaveSidecarPaths.remove_all_path_variants(path):
		return GDFrameResult.ERR_SAVE_DELETE_FAILED
	var meta_path: String = _slot_meta_path(slot_id)
	if not meta_path.is_empty() and _path_has_any_variant(meta_path):
		if not GDFrameSaveSidecarPaths.remove_all_path_variants(meta_path):
			push_warning("GDFrame Save: 槽位主档已删但 meta 删除失败 %s" % meta_path)
			return GDFrameResult.ERR_SAVE_DELETE_FAILED
	var idx: int = _startup_corrupt_slots.find(slot_id)
	if idx >= 0:
		_startup_corrupt_slots.remove_at(idx)
	return GDFrameResult.OK


func list_slot_ids() -> Array[String]:
	_ensure_dir(get_slots_dir())
	var ids: Dictionary = {}
	var abs_dir: String = ProjectSettings.globalize_path(get_slots_dir())
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return []
	for file_name: String in dir.get_files():
		var res_path: String = _slot_path_from_filename(file_name)
		if res_path.is_empty():
			continue
		var slot_key: String = _slot_id_from_resource_path(res_path)
		if not slot_key.is_empty():
			ids[slot_key] = true
	var result: Array[String] = []
	for key: String in ids.keys():
		result.append(key)
	result.sort()
	return result


func slot_last_modified_unix(slot_id: String) -> int:
	var path: String = _slot_resource_path(slot_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return 0
	return int(FileAccess.get_modified_time(ProjectSettings.globalize_path(path)))


func write_slot_meta(slot_id: String, meta: Dictionary) -> StringName:
	var path: String = _slot_meta_path(slot_id)
	if path.is_empty():
		return GDFrameResult.ERR_SAVE_SLOT_ID_INVALID
	_ensure_dir(get_slot_meta_dir())
	_try_recover_incomplete_save(path)
	var snap: Resource = _meta_dict_to_resource(meta)
	return _atomic_save_resource(snap, path, true)


## 从槽位存档 Resource 提取展示字段并写回 meta sidecar；无存档或无可提取字段时返回 [member GDFrameResult.OK]。
func rebuild_slot_meta_from_save(slot_id: String) -> StringName:
	var id: String = _sanitize_slot_id(slot_id)
	if id.is_empty():
		return GDFrameResult.ERR_SAVE_SLOT_ID_INVALID
	if not has_game_slot(id):
		return GDFrameResult.ERR_SAVE_SLOT_NOT_FOUND
	var extracted: Dictionary = _extract_meta_from_resource(id)
	if extracted.is_empty():
		return GDFrameResult.OK
	return write_slot_meta(id, extracted)


func slot_summary(slot_id: String) -> Dictionary:
	var id: String = _sanitize_slot_id(slot_id)
	if id.is_empty():
		return _make_slot_summary("", false, 0, "", 0.0, "", "")
	var exists: bool = has_game_slot(id)
	var modified: int = slot_last_modified_unix(id) if exists else 0
	var meta: Dictionary = _read_slot_meta_dict(id)
	if modified == 0 and not meta.is_empty():
		var meta_path: String = _slot_meta_path(id)
		if FileAccess.file_exists(meta_path):
			modified = int(FileAccess.get_modified_time(ProjectSettings.globalize_path(meta_path)))
	var label: String = str(meta.get("slot_label", ""))
	var play_time: float = _meta_number(meta.get("play_time_sec", 0))
	var chapter: String = str(meta.get("chapter", ""))
	var thumb: String = str(meta.get("thumbnail_path", ""))
	return _make_slot_summary(id, exists, modified, label, play_time, chapter, thumb)

# =============================================================================
# Profile helpers
# =============================================================================

func _rebuild_paths() -> void:
	_profile_disk_path = _user_root.path_join(PROFILE_BASENAME + _format_ext)
	_slots_dir = _user_root.path_join(SLOTS_SUBDIR)


func _new_default_profile() -> GDFrameProfileResource:
	var prof: GDFrameProfileResource = GDFrameProfileResource.new()
	prof.ensure_children()
	return prof

func _load_profile_from_disk() -> GDFrameProfileResource:
	_startup_profile_fallback = false
	if not ResourceLoader.exists(_profile_disk_path):
		return _new_default_profile()
	var loaded: GDFrameProfileResource = _parse_profile_from_disk()
	if loaded != null:
		return loaded
	_startup_profile_fallback = true
	return _new_default_profile()

func _parse_profile_from_disk() -> GDFrameProfileResource:
	var loaded: Variant = ResourceLoader.load(_profile_disk_path)
	if not _is_save_profile(loaded):
		return null
	loaded.ensure_children()
	return loaded

func _is_save_profile(v: Variant) -> bool:
	return v is GDFrameProfileResource

# =============================================================================
# Atomic write
# =============================================================================

## [param move_main_to_bak] 为 [code]true[/code]（槽位）：正式档→[code].bak[/code] 再写 [code].tmp[/code]。
## 为 [code]false[/code]（profile）：保留正式档，写 [code].tmp[/code] 后覆盖提交（避免 Windows 下无法删除已加载路径）。

func _atomic_save_resource(res: Resource, path: String, move_main_to_bak: bool = true) -> StringName:
	var side_err: StringName = _check_no_side_files(path)
	if not GDFrameResult.is_ok(side_err):
		return side_err
	var tmp_path: String = GDFrameSaveSidecarPaths.tmp_path(path)
	var bak_path: String = GDFrameSaveSidecarPaths.bak_path(path)
	var abs_path: String = ProjectSettings.globalize_path(path)
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_bak: String = ProjectSettings.globalize_path(bak_path)
	if move_main_to_bak and FileAccess.file_exists(abs_path):
		if FileAccess.file_exists(abs_bak):
			DirAccess.remove_absolute(abs_bak)
		if not _backup_main_to_bak(abs_path, abs_bak):
			push_error("GDFrame Save: 无法备份正式档 %s" % path)
			return GDFrameResult.ERR_SAVE_WRITE_FAILED
	var save_err: Error = ResourceSaver.save(res, tmp_path)
	if save_err != OK:
		push_error("GDFrame Save: 写入 .tmp 失败 %s（err=%s）" % [tmp_path, save_err])
		_rollback_bak_to_main(abs_path, abs_bak, abs_tmp)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	if FileAccess.file_exists(abs_bak):
		DirAccess.remove_absolute(abs_bak)
	if not _commit_tmp_to_main(abs_path, abs_tmp, res, path):
		push_error("GDFrame Save: 无法提交 %s（覆盖/rename 均失败）" % path)
		_rollback_bak_to_main(abs_path, abs_bak, abs_tmp)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	return GDFrameResult.OK


## 槽位用：复制到 [code].bak[/code]；能删正式档则删，删不掉也视为成功（后续用 .tmp 覆盖正式档）。

func _backup_main_to_bak(abs_main: String, abs_bak: String) -> bool:
	if DirAccess.copy_absolute(abs_main, abs_bak) == OK:
		DirAccess.remove_absolute(abs_main)
		return true
	return DirAccess.rename_absolute(abs_main, abs_bak) == OK

func _commit_tmp_to_main(abs_main: String, abs_tmp: String, res: Resource, res_path: String) -> bool:
	if not FileAccess.file_exists(abs_tmp):
		return false
	if FileAccess.file_exists(abs_main):
		if DirAccess.copy_absolute(abs_tmp, abs_main) == OK:
			DirAccess.remove_absolute(abs_tmp)
			if res != null:
				res.take_over_path(res_path)
			return true
	if not FileAccess.file_exists(abs_main):
		if DirAccess.rename_absolute(abs_tmp, abs_main) == OK:
			if res != null:
				res.take_over_path(res_path)
			return true
	DirAccess.remove_absolute(abs_main)
	if DirAccess.rename_absolute(abs_tmp, abs_main) == OK:
		if res != null:
			res.take_over_path(res_path)
		return true
	if DirAccess.copy_absolute(abs_tmp, abs_main) == OK:
		DirAccess.remove_absolute(abs_tmp)
		if res != null:
			res.take_over_path(res_path)
		return true
	return false

func _rollback_bak_to_main(abs_path: String, abs_bak: String, abs_tmp: String) -> void:
	if FileAccess.file_exists(abs_tmp):
		DirAccess.remove_absolute(abs_tmp)
	if FileAccess.file_exists(abs_bak) and not FileAccess.file_exists(abs_path):
		DirAccess.rename_absolute(abs_bak, abs_path)

# =============================================================================
# Recovery internals
# =============================================================================

func _recover_slots_directory() -> StringName:
	_ensure_dir(get_slots_dir())
	var abs_dir: String = ProjectSettings.globalize_path(get_slots_dir())
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return GDFrameResult.OK
	var paths: Dictionary = {}
	for file_name: String in dir.get_files():
		var res_path: String = _slot_path_from_filename(file_name)
		if not res_path.is_empty():
			paths[res_path] = true
	for res_path: String in paths:
		var err: StringName = _recover_path(res_path)
		if err == GDFrameResult.ERR_SAVE_CORRUPTED:
			var slot_id: String = _slot_id_from_resource_path(res_path)
			if not slot_id.is_empty() and slot_id not in _startup_corrupt_slots:
				_startup_corrupt_slots.append(slot_id)
		elif not GDFrameResult.is_ok(err):
			return err
	return GDFrameResult.OK

func _recover_path(path: String) -> StringName:
	if not GDFrameSaveSidecarPaths.has_side_files(path) and not _has_corrupt_main(path):
		return GDFrameResult.OK
	_try_recover_incomplete_save(path)
	if GDFrameSaveSidecarPaths.has_side_files(path):
		push_error("GDFrame Save: 恢复后仍有残留 .tmp/.bak：%s" % path)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	if _has_corrupt_main(path):
		return GDFrameResult.ERR_SAVE_CORRUPTED
	return GDFrameResult.OK

## 尝试从不完整 sidecar（[code].tmp[/code]/[code].bak[/code]）恢复指定路径的存档。

func _try_recover_incomplete_save(path: String) -> void:
	var tmp_path: String = GDFrameSaveSidecarPaths.tmp_path(path)
	var bak_path: String = GDFrameSaveSidecarPaths.bak_path(path)
	var abs_path: String = ProjectSettings.globalize_path(path)
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_bak: String = ProjectSettings.globalize_path(bak_path)
	var has_tmp: bool = FileAccess.file_exists(abs_tmp)
	var has_bak: bool = FileAccess.file_exists(abs_bak)
	var has_main: bool = FileAccess.file_exists(abs_path)
	if not has_tmp and not has_bak:
		return
	if has_bak and not has_main and not has_tmp:
		_restore_bak_as_main(path, bak_path, abs_path, abs_bak, "")
		return
	if has_main:
		if _resource_load_ok(path):
			if has_tmp:
				DirAccess.remove_absolute(abs_tmp)
			if has_bak:
				DirAccess.remove_absolute(abs_bak)
			return
		if has_bak and _restore_bak_as_main(path, bak_path, abs_path, abs_bak, abs_tmp):
			return
		if has_tmp and _resource_load_ok(tmp_path):
			DirAccess.remove_absolute(abs_path)
			if DirAccess.rename_absolute(abs_tmp, abs_path) == OK:
				push_warning("GDFrame Save: 主文件损坏，已用 .tmp 恢复 %s" % path)
			else:
				DirAccess.remove_absolute(abs_tmp)
		elif has_tmp:
			DirAccess.remove_absolute(abs_tmp)
		return
	if has_bak:
		_restore_bak_as_main(path, bak_path, abs_path, abs_bak, abs_tmp)
		return
	if has_tmp:
		if _resource_load_ok(tmp_path):
			if DirAccess.rename_absolute(abs_tmp, abs_path) == OK:
				push_warning("GDFrame Save: 已从未完成写入恢复 %s" % path)
			else:
				DirAccess.remove_absolute(abs_tmp)
		else:
			DirAccess.remove_absolute(abs_tmp)

func _restore_bak_as_main(
	path: String,
	bak_path: String,
	abs_path: String,
	abs_bak: String,
	abs_tmp: String,
) -> bool:
	if not FileAccess.file_exists(abs_bak):
		return false
	if not _resource_load_ok(bak_path):
		push_warning("GDFrame Save: .bak 无法加载，跳过恢复 %s" % path)
		return false
	if FileAccess.file_exists(abs_tmp):
		DirAccess.remove_absolute(abs_tmp)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	if DirAccess.rename_absolute(abs_bak, abs_path) == OK:
		push_warning("GDFrame Save: 已从 .bak 恢复 %s（丢弃未完成 .tmp）" % path)
		return true
	return false

func _resource_load_ok(res_path: String) -> bool:
	if _recover_load_cache.has(res_path):
		return bool(_recover_load_cache[res_path])
	var ok: bool = false
	if ResourceLoader.exists(res_path):
		var abs_path: String = ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var f: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
			if f != null and f.get_length() > 0:
				f = null
				ok = ResourceLoader.load(res_path) != null
	_recover_load_cache[res_path] = ok
	return ok

# =============================================================================
# Meta sidecar recovery（与槽位存档共用 _recover_path / _try_recover_incomplete_save）
# =============================================================================

func _recover_meta_directory() -> StringName:
	_ensure_dir(get_slot_meta_dir())
	var abs_dir: String = ProjectSettings.globalize_path(get_slot_meta_dir())
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return GDFrameResult.OK
	var paths: Dictionary = {}
	for file_name: String in dir.get_files():
		var meta_path: String = _meta_path_from_filename(file_name)
		if not meta_path.is_empty():
			paths[meta_path] = true
	for meta_path: String in paths:
		var err: StringName = _recover_path(meta_path)
		if not GDFrameResult.is_ok(err) and err != GDFrameResult.ERR_SAVE_CORRUPTED:
			return err
		if err == GDFrameResult.ERR_SAVE_CORRUPTED:
			push_warning("GDFrame Save: 丢弃损坏的槽位 meta %s" % meta_path)
			GDFrameSaveSidecarPaths.remove_all_path_variants(meta_path)
	return GDFrameResult.OK

func _meta_path_from_filename(file_name: String) -> String:
	return _resource_path_from_filename(file_name, get_slot_meta_dir())

# =============================================================================
# Sidecar paths
# =============================================================================

func _check_no_side_files(path: String) -> StringName:
	if not GDFrameSaveSidecarPaths.has_side_files(path):
		return GDFrameResult.OK
	_try_recover_incomplete_save(path)
	if not GDFrameSaveSidecarPaths.has_side_files(path):
		return GDFrameResult.OK
	push_error("GDFrame Save: 写入前仍有残留 .tmp/.bak：%s" % path)
	return GDFrameResult.ERR_SAVE_WRITE_FAILED

func _has_corrupt_main(path: String) -> bool:
	var abs_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return false
	return not _resource_load_ok(path)

func _path_has_any_variant(path: String) -> bool:
	if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return true
	for side: String in GDFrameSaveSidecarPaths.all_side_paths(path):
		if FileAccess.file_exists(ProjectSettings.globalize_path(side)):
			return true
	return false

# =============================================================================
# Slot paths & filesystem
# =============================================================================

func _slot_resource_path(slot_id: String) -> String:
	var key: String = _sanitize_slot_id(slot_id)
	if key.is_empty():
		return ""
	return get_slots_dir().path_join(key + _format_ext)

func _slot_id_from_resource_path(res_path: String) -> String:
	return res_path.get_file().trim_suffix(_format_ext)

func _slot_path_from_filename(file_name: String) -> String:
	return _resource_path_from_filename(file_name, get_slots_dir())


func _resource_path_from_filename(file_name: String, dir_url: String) -> String:
	var tmp_tail: String = ".tmp" + _format_ext
	var bak_tail: String = ".bak" + _format_ext
	if file_name.ends_with(tmp_tail):
		return dir_url.path_join(file_name.trim_suffix(tmp_tail) + _format_ext)
	if file_name.ends_with(bak_tail):
		return dir_url.path_join(file_name.trim_suffix(bak_tail) + _format_ext)
	if file_name.ends_with(_format_ext):
		return dir_url.path_join(file_name)
	return ""


func _sanitize_slot_id(slot_id: String) -> String:
	var s: String = slot_id.strip_edges()
	if s.is_empty():
		return ""
	for i: int in range(s.length()):
		var code: int = s.unicode_at(i)
		var ok: bool = (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code == 95
			or code == 45
		)
		if not ok:
			return ""
	return s


func _slot_meta_path(slot_id: String) -> String:
	var key: String = _sanitize_slot_id(slot_id)
	if key.is_empty():
		return ""
	return get_slot_meta_dir().path_join(key + _format_ext)


func _read_slot_meta_dict(slot_id: String) -> Dictionary:
	var path: String = _slot_meta_path(slot_id)
	if path.is_empty():
		return {}
	_try_recover_incomplete_save(path)
	if GDFrameSaveSidecarPaths.has_side_files(path):
		_warn_meta_read_once(
			"sidecar:%s" % path,
			"GDFrame Save: meta 存在未完成 sidecar，跳过读取 %s" % path,
		)
		return {}
	if not ResourceLoader.exists(path):
		return {}
	var loaded: Variant = ResourceLoader.load(path)
	if loaded == null:
		_warn_meta_read_once(
			"load:%s" % path,
			"GDFrame Save: meta 无法加载 %s" % path,
		)
		return {}
	if _is_slot_meta_resource(loaded):
		return _meta_resource_to_dict(loaded as Resource)
	_warn_meta_read_once(
		"type:%s" % path,
		"GDFrame Save: meta 类型不匹配 %s" % path,
	)
	return {}


func _is_slot_meta_resource(value: Variant) -> bool:
	return value is GDFrameSlotMetaResource


func _meta_dict_to_resource(meta: Dictionary) -> Resource:
	var res: Resource = SLOT_META_SCRIPT.new() as Resource
	res.set("slot_label", str(meta.get("slot_label", "")))
	res.set("play_time_sec", _meta_number(meta.get("play_time_sec", 0)))
	res.set("chapter", str(meta.get("chapter", "")))
	res.set("thumbnail_path", str(meta.get("thumbnail_path", "")))
	return res


func _meta_resource_to_dict(res: Resource) -> Dictionary:
	return {
		"slot_label": str(res.get("slot_label")),
		"play_time_sec": _meta_number(res.get("play_time_sec")),
		"chapter": str(res.get("chapter")),
		"thumbnail_path": str(res.get("thumbnail_path")),
	}


func _make_slot_summary(
	slot_key: String,
	exists: bool,
	modified_unix: int,
	label: String,
	play_time_sec: float,
	chapter: String,
	thumbnail_path: String,
) -> Dictionary:
	return {
		"exists": exists,
		"slot_id": slot_key,
		"modified_unix": modified_unix,
		"label": label,
		"play_time_sec": play_time_sec,
		"chapter": chapter,
		"thumbnail_path": thumbnail_path,
	}


func _meta_number(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0


func _warn_meta_read_once(cache_key: String, message: String) -> void:
	if _warned_meta_read.has(cache_key):
		return
	_warned_meta_read[cache_key] = true
	push_warning(message)


func _extract_meta_from_resource(slot_id: String) -> Dictionary:
	var read: Dictionary = read_game_resource(slot_id)
	if not GDFrameResult.is_ok(GDFrameResult.read_error(read)):
		return {}
	var res: Resource = GDFrameResult.read_resource(read)
	if res == null:
		return {}
	return _meta_fields_from_resource(res)


func _meta_fields_from_resource(res: Resource) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["slot_label", "play_time_sec", "chapter", "thumbnail_path"]:
		var v: Variant = res.get(key)
		if v != null:
			out[key] = v
	return out


func _ensure_dir(user_url: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(user_url)
	DirAccess.make_dir_recursive_absolute(abs_path)

