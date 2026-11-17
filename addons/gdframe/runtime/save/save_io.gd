extends RefCounted
class_name GDFrameSaveIO

## 通用原子文件写入：任意路径 + 任意文本/字节。
##
## 只保证「磁盘上要么是完整旧内容、要么是完整新内容」，不定义文件名、目录、格式、数量或元数据；
## 业务自行决定怎么分文件、怎么命名、写什么内容。不调用则框架零开销。
##
## 实现：写 [code]<name>.tmp.<ext>[/code] → 正式档存在时先改名为 [code]<name>.bak.<ext>[/code]
## → [code].tmp[/code] 改名为正式档 → 删 [code].bak[/code]。全程只有 rename，不产生半截正式档。


## 原子写入文本（UTF-8）。
static func write_text(path: String, text: String) -> StringName:
	var prep: StringName = _prepare(path)
	if not GDFrameResult.is_ok(prep):
		return prep
	var abs_tmp: String = ProjectSettings.globalize_path(GDFrameSaveSidecarPaths.tmp_path(path))
	var f: FileAccess = FileAccess.open(abs_tmp, FileAccess.WRITE)
	if f == null:
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	f.store_string(text)
	return _commit(path, abs_tmp, f)


## 原子写入字节（[param data] 原样落盘，不做编码转换）。
static func write_bytes(path: String, data: PackedByteArray) -> StringName:
	var prep: StringName = _prepare(path)
	if not GDFrameResult.is_ok(prep):
		return prep
	var abs_tmp: String = ProjectSettings.globalize_path(GDFrameSaveSidecarPaths.tmp_path(path))
	var f: FileAccess = FileAccess.open(abs_tmp, FileAccess.WRITE)
	if f == null:
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	f.store_buffer(data)
	return _commit(path, abs_tmp, f)


## 修复上次写入中断留下的 sidecar。启动时对每个业务存档路径调用一次。
## 正式档存在（rename 语义下一定是完整文件）→ 清掉残留 [code].tmp[/code] / [code].bak[/code]；
## 正式档缺失 → 用 [code].tmp[/code]（更新的内容）提升，其次用 [code].bak[/code]。
static func recover(path: String) -> StringName:
	var abs_main: String = ProjectSettings.globalize_path(path)
	var abs_tmp: String = ProjectSettings.globalize_path(GDFrameSaveSidecarPaths.tmp_path(path))
	var abs_bak: String = ProjectSettings.globalize_path(GDFrameSaveSidecarPaths.bak_path(path))
	if FileAccess.file_exists(abs_main):
		if FileAccess.file_exists(abs_tmp):
			DirAccess.remove_absolute(abs_tmp)
		if FileAccess.file_exists(abs_bak):
			DirAccess.remove_absolute(abs_bak)
		return GDFrameResult.OK
	if FileAccess.file_exists(abs_tmp) and DirAccess.rename_absolute(abs_tmp, abs_main) == OK:
		push_warning("GDFrame SaveIO: 已从未完成写入恢复 %s" % path)
		if FileAccess.file_exists(abs_bak):
			DirAccess.remove_absolute(abs_bak)
		return GDFrameResult.OK
	if FileAccess.file_exists(abs_bak) and DirAccess.rename_absolute(abs_bak, abs_main) == OK:
		push_warning("GDFrame SaveIO: 已从 .bak 恢复 %s" % path)
		return GDFrameResult.OK
	if FileAccess.file_exists(abs_tmp) or FileAccess.file_exists(abs_bak):
		push_error("GDFrame SaveIO: 无法恢复 %s" % path)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	return GDFrameResult.OK


# =============================================================================
# Private
# =============================================================================

static func _prepare(path: String) -> StringName:
	var recover_err: StringName = recover(path)
	if not GDFrameResult.is_ok(recover_err):
		return recover_err
	var abs_dir: String = ProjectSettings.globalize_path(path).get_base_dir()
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		push_error("GDFrame SaveIO: 无法创建目录 %s" % abs_dir)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	return GDFrameResult.OK


static func _commit(path: String, abs_tmp: String, f: FileAccess) -> StringName:
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(abs_tmp)
		push_error("GDFrame SaveIO: 写入 .tmp 失败 %s（err=%s）" % [abs_tmp, write_err])
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	if not _commit_tmp(abs_tmp, path):
		DirAccess.remove_absolute(abs_tmp)
		push_error("GDFrame SaveIO: 无法提交 %s" % path)
		return GDFrameResult.ERR_SAVE_WRITE_FAILED
	return GDFrameResult.OK


static func _commit_tmp(abs_tmp: String, main_path: String) -> bool:
	var abs_main: String = ProjectSettings.globalize_path(main_path)
	if not FileAccess.file_exists(abs_main):
		return DirAccess.rename_absolute(abs_tmp, abs_main) == OK
	var abs_bak: String = ProjectSettings.globalize_path(GDFrameSaveSidecarPaths.bak_path(main_path))
	if FileAccess.file_exists(abs_bak) and DirAccess.remove_absolute(abs_bak) != OK:
		return false
	if DirAccess.rename_absolute(abs_main, abs_bak) != OK:
		return false
	if DirAccess.rename_absolute(abs_tmp, abs_main) != OK:
		DirAccess.rename_absolute(abs_bak, abs_main)
		return false
	DirAccess.remove_absolute(abs_bak)
	return true
