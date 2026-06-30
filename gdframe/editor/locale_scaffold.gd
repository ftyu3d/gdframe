extends RefCounted
## 为新工程生成/补全含框架内置翻译键的本地化 CSV（[member LOCALE_CSV_PATH]）。
## 内置模板以字符串常量存放于本编辑器脚本，不随 [code]addons/[/code] 资源导出进包体。
## [code]project.godot[/code] 翻译注册须在 CSV 导入为 [code].translation[/code] 后由 [method register_translations] 完成。

## 本地化资源根目录。
const LOCALE_ROOT_DIR: String = "res://locale"
## 项目本地化 CSV 路径。
const LOCALE_CSV_PATH: String = "res://locale/localization.csv"

const _SETTING_TRANSLATIONS: String = "internationalization/locale/translations"
const _SETTING_FALLBACK: String = "internationalization/locale/fallback"
const _DEFAULT_FALLBACK: String = "zh_CN"

const _BUILTIN_LOCALE_CSV: String = """keys,zh_CN,zh_TW,en
LOCALE_NAME,简体中文,繁體中文,English
UI_SETTINGS_LOCALE_AUTOMATIC,跟随系统,跟隨系統,System default
UI_SETTINGS_TITLE,设置,設定,Settings
UI_SETTINGS_LANGUAGE,语言,語言,Language
UI_SETTINGS_MUTE,静音,靜音,Mute
UI_SETTINGS_MASTER,主音量,主音量,Master
UI_SETTINGS_MUSIC,音乐,音樂,Music
UI_SETTINGS_UI,界面音效,介面音效,UI Sound
UI_SETTINGS_SFX,特效音效,特效音效,Game SFX
UI_SETTINGS_DISPLAY_MODE,屏幕显示,螢幕顯示,Display
UI_SETTINGS_WINDOW_SIZE,窗口大小,視窗大小,Window size
UI_SETTINGS_VSYNC,垂直同步,垂直同步,Vertical sync
UI_SETTINGS_SAVE,保存,儲存,Save
UI_SETTINGS_SAVING,正在保存…,正在儲存…,Saving…
UI_SETTINGS_SAVE_FAILED_TITLE,保存失败,儲存失敗,Save failed
UI_SETTINGS_RESET_DEFAULT,重置默认,重設為預設值,Reset to defaults
UI_SETTINGS_CLOSE,关闭,關閉,Close
UI_SETTINGS_UNSAVED_TITLE,未保存的修改,未儲存的變更,Unsaved changes
UI_SETTINGS_UNSAVED_MSG,设置已修改，是否保存？,設定已變更，是否儲存？,Settings were modified. Save changes?
DISPLAY_MODE_WINDOWED,窗口化,視窗化,Windowed
DISPLAY_MODE_MAXIMIZED,最大化,最大化,Maximized
DISPLAY_MODE_BORDERLESS,无边框全屏,無邊框全螢幕,Borderless fullscreen
DISPLAY_MODE_EXCLUSIVE,全屏,全螢幕,Fullscreen
TIP_BTN_CONFIRM,确认,確認,OK
TIP_BTN_YES,是,是,Yes
TIP_BTN_NO,否,否,No
TIP_BTN_CANCEL,取消,取消,Cancel
TIP_BTN_RETRY,重试,重試,Retry
ERR_SAVE_WRITE_FAILED,无法保存：磁盘空间已满或没有写入权限。请处理后点击重试。,無法儲存：磁碟空間已滿或沒有寫入權限。請處理後點擊重試。,Could not save: disk full or no write permission. Free space or fix permissions then tap Retry.
ERR_SAVE_SLOT_ID_INVALID,存档槽名称无效（仅允许字母、数字、下划线与连字符）。,存檔槽名稱無效（僅允許字母、數字、底線與連字號）。,Invalid save slot id (letters digits underscore hyphen only).
ERR_SAVE_SLOT_NOT_FOUND,该存档槽不存在。,該存檔槽不存在。,Save slot not found.
ERR_SAVE_READ_FAILED,无法读取存档文件，文件可能已损坏。,無法讀取存檔檔案，檔案可能已損壞。,Could not read save file. It may be corrupted.
ERR_SAVE_PROFILE_READ_FAILED,玩家档案已损坏，已恢复为默认设置。,玩家檔案已損壞，已恢復為預設設定。,Player profile is corrupted. Default settings were restored.
ERR_SAVE_DELETE_FAILED,无法删除存档文件。,無法刪除存檔檔案。,Could not delete save file.
ERR_SAVE_CORRUPTED,存档已损坏。点击确定将删除该存档。,存檔已損壞。點擊確定將刪除該存檔。,Save data is corrupted. Tap OK to delete this save.
ERR_SAVE_META_WRITE_FAILED,游戏进度已保存，但存档摘要更新失败。可尝试重新保存或从存档重建摘要。,遊戲進度已儲存，但存檔摘要更新失敗。可嘗試重新儲存或從存檔重建摘要。,Progress was saved but the save summary could not be updated. Try saving again or rebuild the summary from the save file.
"""


## 生成或合并 [member LOCALE_CSV_PATH] 中缺失的内置键；不写入 [code]project.godot[/code]。
func prepare_csv(merge_builtin: bool = true) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"created_csv": false,
		"merged_keys": PackedStringArray(),
		"message": "",
	}

	var dir_err: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LOCALE_ROOT_DIR)
	)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		result.ok = false
		result.message = "无法创建目录 %s（错误 %s）。" % [LOCALE_ROOT_DIR, dir_err]
		return result

	var builtin_table: Dictionary = _builtin_csv_table()
	if builtin_table.is_empty():
		result.ok = false
		result.message = "框架内置翻译模板无效。"
		return result

	if not FileAccess.file_exists(LOCALE_CSV_PATH):
		if not _write_text_file(LOCALE_CSV_PATH, _BUILTIN_LOCALE_CSV.strip_edges() + "\n"):
			result.ok = false
			result.message = "无法写入 %s。" % LOCALE_CSV_PATH
			return result
		_write_csv_import_file(builtin_table.locales)
		result.created_csv = true
		return result

	var csv_check: Dictionary = _validate_csv_file(LOCALE_CSV_PATH)
	if not bool(csv_check.get("ok", true)):
		result.ok = false
		result.message = str(csv_check.get("message", "本地化 CSV 格式无效。"))
		return result

	if not merge_builtin:
		return result

	var merged: Dictionary = _merge_builtin_into_existing(builtin_table)
	if not bool(merged.get("ok", false)):
		result.ok = false
		result.message = str(merged.get("message", "合并失败。"))
		return result
	result.merged_keys = merged.get("merged_keys", PackedStringArray())
	return result


## 将已存在的 [code].translation[/code] 注册到 [code]project.godot[/code]。
func register_translations() -> bool:
	var locales: PackedStringArray = _locale_codes_from_csv()
	if locales.is_empty():
		return false
	return _sync_project_translations(locales)


## 移除 [code]project.godot[/code] 中指向不存在文件的翻译条目。
func prune_stale_translations() -> bool:
	var existing: PackedStringArray = ProjectSettings.get_setting(
		_SETTING_TRANSLATIONS,
		PackedStringArray(),
	)
	var kept: PackedStringArray = PackedStringArray()
	for path: String in existing:
		if FileAccess.file_exists(path):
			kept.append(path)
	if kept == existing:
		return false
	ProjectSettings.set_setting(_SETTING_TRANSLATIONS, kept)
	var err: Error = ProjectSettings.save()
	if err != OK:
		push_warning("GDFrame: 清理 project.godot 无效翻译条目失败（错误 %s）。" % err)
	return true


func expected_translation_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for locale: String in _locale_codes_from_csv():
		paths.append(_translation_path(locale))
	return paths


func has_missing_translation_files() -> bool:
	for path: String in expected_translation_paths():
		if not FileAccess.file_exists(path):
			return true
	return false


func translations_registered() -> bool:
	if has_missing_translation_files():
		return false
	var expected: PackedStringArray = expected_translation_paths()
	var existing: PackedStringArray = ProjectSettings.get_setting(
		_SETTING_TRANSLATIONS,
		PackedStringArray(),
	)
	for path: String in expected:
		if path not in existing:
			return false
	return not expected.is_empty()


func _builtin_csv_table() -> Dictionary:
	return _parse_csv_table(_BUILTIN_LOCALE_CSV)


func _load_csv_table(path: String) -> Dictionary:
	return _parse_csv_table(_read_text_file(path))


func _parse_csv_table(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var lines: PackedStringArray = PackedStringArray(text.split("\n", false))
	if lines.is_empty():
		return {}
	var header: PackedStringArray = _split_csv_line(_normalize_csv_line(lines[0]))
	if header.is_empty() or header[0] != "keys":
		return {}
	var locales: PackedStringArray = PackedStringArray()
	for i: int in range(1, header.size()):
		locales.append(header[i])
	var rows: Dictionary = {}
	for line_idx: int in range(1, lines.size()):
		var line: String = _normalize_csv_line(lines[line_idx])
		if line.is_empty():
			continue
		var cells: PackedStringArray = _split_csv_line(line)
		if cells.is_empty():
			continue
		rows[cells[0]] = cells
	return {"locales": locales, "rows": rows}


func _merge_builtin_into_existing(builtin_table: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": true, "merged_keys": PackedStringArray(), "message": ""}
	var user_table: Dictionary = _load_csv_table(LOCALE_CSV_PATH)
	if user_table.is_empty():
		out.ok = false
		out.message = "现有 CSV 表头无效（首列须为 keys）。"
		return out

	var locales: PackedStringArray = user_table.locales.duplicate()
	for locale: String in builtin_table.locales:
		if locale not in locales:
			locales.append(locale)

	var values: Dictionary = {}
	for key: String in user_table.rows:
		values[key] = _row_to_locale_map(user_table.rows[key], user_table.locales)

	for key: String in builtin_table.rows:
		if values.has(key):
			continue
		values[key] = _row_to_locale_map(builtin_table.rows[key], builtin_table.locales)
		out.merged_keys.append(key)

	if out.merged_keys.is_empty():
		return out

	var header: PackedStringArray = PackedStringArray(["keys"])
	header.append_array(locales)
	var lines: PackedStringArray = PackedStringArray([",".join(header)])
	var keys_sorted: Array = values.keys()
	keys_sorted.sort()
	for key: String in keys_sorted:
		var locale_map: Dictionary = values[key]
		var row: PackedStringArray = PackedStringArray([key])
		for locale: String in locales:
			row.append(str(locale_map.get(locale, "")))
		lines.append(",".join(row))

	if not _write_text_file(LOCALE_CSV_PATH, "\n".join(lines) + "\n"):
		out.ok = false
		out.message = "无法写入合并后的 CSV。"
	return out


func _row_to_locale_map(cells: PackedStringArray, locales: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for i: int in range(locales.size()):
		out[locales[i]] = cells[i + 1] if i + 1 < cells.size() else ""
	return out


func _sync_project_translations(locales: PackedStringArray) -> bool:
	var changed: bool = false
	var to_register: PackedStringArray = PackedStringArray()
	for locale: String in locales:
		var path: String = _translation_path(locale)
		if FileAccess.file_exists(path):
			to_register.append(path)

	var existing: PackedStringArray = ProjectSettings.get_setting(
		_SETTING_TRANSLATIONS,
		PackedStringArray(),
	)
	var merged: PackedStringArray = PackedStringArray()
	for path: String in existing:
		if FileAccess.file_exists(path):
			if path not in merged:
				merged.append(path)
		else:
			changed = true
	for path: String in to_register:
		if path not in merged:
			merged.append(path)
			changed = true
	if merged != existing:
		ProjectSettings.set_setting(_SETTING_TRANSLATIONS, merged)
		changed = true

	if not ProjectSettings.has_setting(_SETTING_FALLBACK):
		ProjectSettings.set_setting(_SETTING_FALLBACK, _DEFAULT_FALLBACK)
		changed = true

	if changed:
		var err: Error = ProjectSettings.save()
		if err != OK:
			push_warning("GDFrame: 保存 project.godot 本地化设置失败（错误 %s）。" % err)
	return changed


func _locale_codes_from_csv() -> PackedStringArray:
	if FileAccess.file_exists(LOCALE_CSV_PATH):
		var table: Dictionary = _load_csv_table(LOCALE_CSV_PATH)
		if not table.is_empty():
			return table.locales
	return _builtin_csv_table().get("locales", PackedStringArray())


func _translation_path(locale: String) -> String:
	return "%s/localization.%s.translation" % [LOCALE_ROOT_DIR, locale]


func _write_csv_import_file(locales: PackedStringArray) -> void:
	var dest_files: PackedStringArray = PackedStringArray()
	for locale: String in locales:
		dest_files.append(_translation_path(locale))
	var files_json: String = _packed_string_array_to_json(dest_files)
	var body: String = (
		"[remap]\n\n"
		+ 'importer="csv_translation"\n'
		+ 'type="Translation"\n\n'
		+ "[deps]\n\n"
		+ "files=%s\n\n" % files_json
		+ 'source_file="%s"\n' % LOCALE_CSV_PATH
		+ "dest_files=%s\n\n" % files_json
		+ "[params]\n\n"
		+ "compress=1\n"
		+ "delimiter=0\n"
		+ "unescape_keys=false\n"
		+ "unescape_translations=true\n"
	)
	_write_text_file("%s.import" % LOCALE_CSV_PATH, body)


func _packed_string_array_to_json(arr: PackedStringArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item: String in arr:
		parts.append('"%s"' % item)
	return "[%s]" % ", ".join(parts)


func _split_csv_line(line: String) -> PackedStringArray:
	return PackedStringArray(line.split(",", false))


func _validate_csv_file(path: String) -> Dictionary:
	var text: String = _read_text_file(path)
	if text.is_empty():
		return {"ok": false, "message": "本地化 CSV 为空或无法读取。"}
	var lines: PackedStringArray = PackedStringArray(text.split("\n", false))
	if lines.is_empty():
		return {"ok": false, "message": "本地化 CSV 为空。"}
	var header: PackedStringArray = _split_csv_line_quoted(_normalize_csv_line(lines[0]))
	if header.is_empty() or header[0] != "keys":
		return {"ok": false, "message": "CSV 表头无效（首列须为 keys）。"}
	var col_count: int = header.size()
	for line_idx: int in range(1, lines.size()):
		var line: String = _normalize_csv_line(lines[line_idx])
		if line.is_empty():
			continue
		var cells: PackedStringArray = _split_csv_line_quoted(line)
		if cells.is_empty():
			continue
		if cells.size() != col_count:
			return {
				"ok": false,
				"message": (
					"CSV 第 %d 行列数不匹配（期望 %d 列，实际 %d 列）：%s"
					% [line_idx + 1, col_count, cells.size(), cells[0]]
				),
			}
	return {"ok": true, "message": ""}


func _split_csv_line_quoted(line: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	var field: String = ""
	var in_quotes: bool = false
	while i < line.length():
		var c: String = line[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			field += c
			i += 1
			continue
		if c == "\"":
			in_quotes = true
			i += 1
			continue
		if c == ",":
			out.append(field)
			field = ""
			i += 1
			continue
		field += c
		i += 1
	if in_quotes:
		return PackedStringArray()  # 未闭合引号
	out.append(field)
	return out


func _normalize_csv_line(line: String) -> String:
	return line.replace("\r", "").strip_edges()


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _write_text_file(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true
