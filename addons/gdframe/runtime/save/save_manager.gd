extends RefCounted
class_name GDFrameSaveManager

# =============================================================================
# Constants
# =============================================================================

const USER_ROOT_URL: String = "user://gdframe"
const PROFILE_BASENAME: String = "profile"
const PROFILE_FILE: String = PROFILE_BASENAME + ".tres"

## sidecar 须保留资源扩展名（[code]profile.tmp.tres[/code]）；[code]profile.tres.tmp[/code] 会被当成 [code].tmp[/code] 格式导致 ResourceSaver 失败。

# =============================================================================
# State
# =============================================================================

var _profile: GDFrameProfileResource
var _user_root: String = ""
var _profile_disk_path: String = ""
var _startup_profile_fallback: bool = false
var _recover_load_cache: Dictionary = {}
var _startup_recovery_error: StringName = GDFrameResult.OK
var profile_saved_hook: Callable = Callable()

# =============================================================================
# Setup & profile
# =============================================================================

func setup() -> StringName:
	_user_root = USER_ROOT_URL
	_rebuild_paths()
	_ensure_dir(_user_root)
	var recover_err: StringName = recover_all_pending_saves()
	_profile = _load_profile_from_disk()
	return recover_err


func startup_recovery_error() -> StringName:
	return _startup_recovery_error


## 将内存档案原子写入磁盘（[code].tmp[/code]→正式档），成功后内存实例 [code]take_over_path[/code]。
func flush() -> StringName:
	var err: StringName = _save_profile()
	if profile_saved_hook.is_valid():
		profile_saved_hook.call(err)
	return err


func flush_async() -> StringName:
	await GDFrame.get_tree().process_frame
	return flush()


func get_profile() -> GDFrameProfileResource:
	if _profile.settings == null:
		_profile.ensure_children()
	return _profile


## 删除磁盘上的 profile（正式档与 sidecar），内存重置为默认档案。
func delete_profile_from_disk() -> StringName:
	if not GDFrameSaveSidecarPaths.remove_all_path_variants(_profile_disk_path):
		return GDFrameResult.ERR_SAVE_DELETE_FAILED
	_profile = _new_default_profile()
	return GDFrameResult.OK


func startup_profile_fallback() -> bool:
	return _startup_profile_fallback


func _save_profile() -> StringName:
	var prof: GDFrameProfileResource = get_profile()
	prof.ensure_children()
	_ensure_dir(_user_root)
	var snap: GDFrameProfileResource = prof.duplicate(true) as GDFrameProfileResource
	if snap == null:
		push_error("GDFrame Save: profile 快照失败")
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	_recover_load_cache.clear()
	_try_recover_incomplete_save(_profile_disk_path)
	var err: StringName = _atomic_save_resource(snap, _profile_disk_path)
	if GDFrameResult.is_ok(err):
		prof.take_over_path(_profile_disk_path)
	return err


# =============================================================================
# Recovery
# =============================================================================

## 处理断电残留的 [code].tmp[/code] / [code].bak[/code]（档案单文件）。
func recover_all_pending_saves() -> StringName:
	_recover_load_cache.clear()
	var profile_err: StringName = _recover_path(_profile_disk_path)
	_recover_load_cache.clear()
	_startup_recovery_error = profile_err
	return profile_err


# =============================================================================
# Profile helpers
# =============================================================================

func _rebuild_paths() -> void:
	_profile_disk_path = _user_root.path_join(PROFILE_FILE)


func _new_default_profile() -> GDFrameProfileResource:
	var prof: GDFrameProfileResource = GDFrameProfileResource.new()
	prof.ensure_children()
	GDFrameSettingsManager.apply_display_defaults(prof.settings)
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
	if not loaded is GDFrameProfileResource:
		return null
	(loaded as GDFrameProfileResource).ensure_children()
	return loaded as GDFrameProfileResource


# =============================================================================
# Atomic write
# =============================================================================

## profile 是已被 [code]ResourceLoader[/code] 加载的资源：不能把正式档改名移走
## （Windows 下已加载路径可能不可删），故写 [code].tmp[/code] 后复制覆盖提交。
func _atomic_save_resource(res: Resource, path: String) -> StringName:
	var side_err: StringName = _check_no_side_files(path)
	if not GDFrameResult.is_ok(side_err):
		return side_err
	var tmp_path: String = GDFrameSaveSidecarPaths.tmp_path(path)
	var abs_path: String = ProjectSettings.globalize_path(path)
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var save_err: Error = ResourceSaver.save(res, tmp_path)
	if save_err != OK:
		push_error("GDFrame Save: 写入 .tmp 失败 %s（err=%s）" % [tmp_path, save_err])
		DirAccess.remove_absolute(abs_tmp)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	if not _commit_tmp_to_main(abs_path, abs_tmp, res, path):
		push_error("GDFrame Save: 无法提交 %s" % path)
		DirAccess.remove_absolute(abs_tmp)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	return GDFrameResult.OK


func _commit_tmp_to_main(abs_main: String, abs_tmp: String, res: Resource, res_path: String) -> bool:
	if not FileAccess.file_exists(abs_tmp):
		return false
	var committed: bool = false
	if FileAccess.file_exists(abs_main):
		committed = DirAccess.copy_absolute(abs_tmp, abs_main) == OK
		if committed:
			DirAccess.remove_absolute(abs_tmp)
	else:
		committed = DirAccess.rename_absolute(abs_tmp, abs_main) == OK
	if not committed:
		return false
	if res != null:
		res.take_over_path(res_path)
	return true


# =============================================================================
# Recovery internals
# =============================================================================

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


# =============================================================================
func _ensure_dir(user_url: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(user_url)
	DirAccess.make_dir_recursive_absolute(abs_path)
