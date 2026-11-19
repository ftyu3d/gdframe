@tool
extends RefCounted
## CSV document handling and Godot registration for the project localization editor.

const LOCALE_ROOT_DIR := "res://locale"
const LOCALE_CSV_PATH := "res://locale/localization.csv"
const IMPORT_PATH := LOCALE_CSV_PATH + ".import"
const TRANSLATIONS := "internationalization/locale/translations"
const FALLBACK := "internationalization/locale/fallback"
const DELIMITERS := [",", ";", "\t"]

const _BUILTIN_LOCALE_CSV: String = """keys,zh_CN,zh_TW,en
LOCALE_NAME,简体中文,繁體中文,English
UI_OPTIONS_LOCALE_AUTOMATIC,跟随系统,跟隨系統,System default
UI_OPTIONS_TITLE,选项,選項,Options
UI_OPTIONS_TAB_GENERAL,常规,常規,General
UI_OPTIONS_TAB_DISPLAY,画面,畫面,Display
UI_OPTIONS_TAB_AUDIO,音频,音訊,Audio
UI_OPTIONS_TAB_CONTROLS,操作,操作,Controls
UI_OPTIONS_LANGUAGE,语言,語言,Language
UI_OPTIONS_MUTE,静音,靜音,Mute
UI_OPTIONS_MASTER,主音量,主音量,Master
UI_OPTIONS_MUSIC,音乐,音樂,Music
UI_OPTIONS_UI,界面音效,介面音效,UI Sound
UI_OPTIONS_SFX,特效音效,特效音效,Game SFX
UI_OPTIONS_BGS,环境音,環境音,Ambient
UI_OPTIONS_VOICE,语音,語音,Voice
UI_OPTIONS_DISPLAY_MODE,屏幕显示,螢幕顯示,Display
UI_OPTIONS_WINDOW_SIZE,分辨率,解析度,Resolution
UI_OPTIONS_VSYNC,垂直同步,垂直同步,Vertical sync
UI_OPTIONS_FRAME_RATE,帧率,幀率,Frame rate
FRAME_RATE_UNLIMITED,无限制,無限制,Unlimited
UI_OPTIONS_SAVE,保存,儲存,Save
UI_OPTIONS_SAVING,正在保存…,正在儲存…,Saving…
UI_OPTIONS_SAVE_FAILED_TITLE,保存失败,儲存失敗,Save failed
UI_OPTIONS_RESET_DEFAULT,重置默认,重設為預設值,Reset to defaults
UI_OPTIONS_CLOSE,关闭,關閉,Close
UI_OPTIONS_UNSAVED_TITLE,未保存的修改,未儲存的變更,Unsaved changes
UI_OPTIONS_UNSAVED_MSG,设置已修改，是否保存？,設定已變更，是否儲存？,Settings were modified. Save changes?
DISPLAY_MODE_WINDOWED,窗口化,視窗化,Windowed
DISPLAY_MODE_MAXIMIZED,最大化,最大化,Maximized
DISPLAY_MODE_BORDERLESS,无边框全屏,無邊框全螢幕,Borderless fullscreen
DISPLAY_MODE_EXCLUSIVE,全屏,全螢幕,Fullscreen
DISPLAY_MODE_WEB_WINDOWED,页面内,頁面內,In browser
UI_OPTIONS_WINDOW_SIZE_CUSTOM,（自定义）,（自訂）, (Custom)
TIP_BTN_CONFIRM,确定,確定,OK
TIP_BTN_YES,是,是,Yes
TIP_BTN_NO,否,否,No
TIP_BTN_CANCEL,取消,取消,Cancel
TIP_BTN_RETRY,重试,重試,Retry
ERR_SAVE_WRITE_FAILED,无法保存：磁盘空间已满或没有写入权限。请处理后点击重试。,無法儲存：磁碟空間已滿或沒有寫入權限。請處理後點擊重試。,Could not save: disk full or no write permission. Free space or fix permissions then tap Retry.
ERR_SAVE_PROFILE_READ_FAILED,玩家档案已损坏，已恢复为默认设置。,玩家檔案已損壞，已恢復為預設設定。,Player profile is corrupted. Default settings were restored.
ERR_SAVE_DELETE_FAILED,无法删除存档文件。,無法刪除存檔檔案。,Could not delete save file.
ERR_SAVE_CORRUPTED,存档已损坏。点击确定将删除该存档。,存檔已損壞。點擊確定將刪除該存檔。,Save data is corrupted. Tap OK to delete this save.
"""


static func import_format() -> Dictionary:
	var config := ConfigFile.new()
	var delimiter := ","
	var import_error := config.load(IMPORT_PATH)
	if import_error == OK:
		if config.get_value("remap", "importer", "") != "csv_translation":
			return {"error": "请先在 Godot 导入面板中把此 CSV 设为 CSV Translation。"}
		var index: int = config.get_value("params", "delimiter", 0)
		if index >= 0 and index < DELIMITERS.size():
			delimiter = DELIMITERS[index]
	elif import_error != ERR_FILE_NOT_FOUND:
		return {"error": "无法读取 CSV 的导入设置。"}
	return {
		"delimiter": delimiter,
		"unescape_keys": config.get_value("params", "unescape_keys", false),
		"unescape_translations": config.get_value("params", "unescape_translations", true),
	}


static func read_csv() -> Dictionary:
	var format := import_format()
	if format.has("error"):
		return format
	var exists := FileAccess.file_exists(LOCALE_CSV_PATH)
	var source_hash := FileAccess.get_sha256(LOCALE_CSV_PATH) if exists else ""
	var file: FileAccess
	if exists:
		file = FileAccess.open(LOCALE_CSV_PATH, FileAccess.READ)
		if file == null:
			return {"error": "无法读取本地化 CSV。"}
	var table := _parse(file.get_as_text() if exists else _BUILTIN_LOCALE_CSV, format.delimiter if exists else ",", format.unescape_keys)
	table["hash"] = source_hash
	table["format"] = format
	return table


static func builtin_rows(locales: PackedStringArray) -> Dictionary:
	var template := _parse(_BUILTIN_LOCALE_CSV, ",")
	var columns := PackedInt32Array()
	for code: String in locales:
		columns.append(find_locale_index(template.locales, code))
	var result := {}
	for key: String in template.rows:
		var cells := PackedStringArray()
		for index: int in columns:
			cells.append(template.rows[key][index] if index >= 0 else "")
		result[key] = cells
	return result


static func current_hash() -> String:
	return FileAccess.get_sha256(LOCALE_CSV_PATH) if FileAccess.file_exists(LOCALE_CSV_PATH) else ""


static func write_csv(table: Dictionary) -> String:
	if current_hash() != table.hash:
		return "CSV 已被其他工具修改。请重新读取后再编辑。"
	if DirAccess.make_dir_recursive_absolute(LOCALE_ROOT_DIR) != OK:
		return "无法创建本地化目录。"
	var temporary := "%s.%s.tmp" % [LOCALE_CSV_PATH, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入本地化目录。"
	var header := PackedStringArray(["keys"])
	header.append_array(table.locales)
	var delimiter: String = table.format.delimiter
	var written := file.store_csv_line(header, delimiter)
	for key: String in table.rows:
		if not written:
			break
		var line := PackedStringArray([key])
		line.append_array(table.rows[key])
		written = file.store_csv_line(line, delimiter)
	file.flush()
	written = written and file.get_error() == OK
	file.close()
	if current_hash() != table.hash:
		DirAccess.remove_absolute(temporary)
		return "CSV 已被其他工具修改。请重新读取后再编辑。"
	if written and DirAccess.rename_absolute(temporary, LOCALE_CSV_PATH) == OK:
		table.hash = FileAccess.get_sha256(LOCALE_CSV_PATH)
		return ""
	DirAccess.remove_absolute(temporary)
	return "写入 CSV 失败，请检查文件是否正被占用以及磁盘权限。"


static func generated_paths() -> PackedStringArray:
	var config := ConfigFile.new()
	if config.load(IMPORT_PATH) != OK:
		return []
	return PackedStringArray(config.get_value("deps", "dest_files", []))


static func remove_obsolete_outputs(previous: PackedStringArray) -> String:
	var imported := generated_paths()
	var removed := false
	var failed := PackedStringArray()
	for path: String in previous:
		if path in imported or path.get_base_dir() != LOCALE_ROOT_DIR:
			continue
		if not path.begins_with(LOCALE_CSV_PATH.get_basename() + ".") or path.get_extension() != "translation" or not FileAccess.file_exists(path):
			continue
		if OS.move_to_trash(ProjectSettings.globalize_path(path)) == OK:
			removed = true
		else:
			failed.append(path.get_file())
	if removed:
		EditorInterface.get_resource_filesystem().scan.call_deferred()
	return "翻译已注册，旧导入文件移入回收站失败：%s。可重试保存。" % "、".join(failed) if not failed.is_empty() else ""


static func register_translations(table: Dictionary, previous: PackedStringArray, previous_locales: PackedStringArray) -> String:
	var expected := {}
	var rows: Array = table.rows.values()
	for index in table.locales.size():
		for cells: PackedStringArray in rows:
			if not cells[index].is_empty():
				expected[table.locales[index]] = true
				break
	var imported := generated_paths()
	for path: String in imported:
		if not FileAccess.file_exists(path):
			return "Godot 尚未生成翻译资源。请重试保存。"
		var resource := ResourceLoader.load(path, "Translation", ResourceLoader.CACHE_MODE_IGNORE) as Translation
		if resource == null:
			return "无法读取翻译资源：%s" % path
		expected.erase(resource.get_locale())
	if not expected.is_empty():
		return "以下语言尚未完成 Godot 导入：%s。请重试保存。" % "、".join(expected.keys())

	var original: PackedStringArray = ProjectSettings.get_setting(TRANSLATIONS, PackedStringArray())
	var registered := PackedStringArray()
	for path: String in original:
		if path not in previous or path in imported:
			registered.append(path)
	for path: String in imported:
		if path not in registered:
			registered.append(path)
	var had_fallback := ProjectSettings.has_setting(FALLBACK)
	var fallback: String = ProjectSettings.get_setting(FALLBACK, "en")
	var next_fallback := fallback
	if fallback in previous_locales and fallback not in table.locales:
		var locales := _registered_locales(registered)
		var index := find_locale_index(locales, fallback)
		next_fallback = locales[index] if index >= 0 else table.locales[0]
	elif previous_locales.is_empty() and original.is_empty() and fallback not in table.locales:
		next_fallback = table.locales[0]
	if registered == original and next_fallback == fallback:
		return ""
	ProjectSettings.set_setting(TRANSLATIONS, registered)
	if next_fallback != fallback:
		ProjectSettings.set_setting(FALLBACK, next_fallback)
	var error := ProjectSettings.save()
	if error == OK:
		return ""
	ProjectSettings.set_setting(TRANSLATIONS, original)
	if next_fallback != fallback:
		ProjectSettings.set_setting(FALLBACK, fallback if had_fallback else null)
	return "CSV 已保存，写入项目翻译设置失败：%s。可重试保存。" % error_string(error)


static func project_locales() -> PackedStringArray:
	var paths: PackedStringArray = ProjectSettings.get_setting(TRANSLATIONS, PackedStringArray())
	return _registered_locales(paths)


static func _registered_locales(paths: PackedStringArray) -> PackedStringArray:
	var locales := PackedStringArray()
	for path: String in paths:
		if not ResourceLoader.exists(path, "Translation"):
			continue
		var resource := ResourceLoader.load(path, "Translation") as Translation
		if resource != null and not resource.get_locale() in locales:
			locales.append(resource.get_locale())
	return locales


static func normalize_locale(value: String) -> String:
	var code := value.strip_edges()
	if code.is_empty() or code == "automatic":
		return ""
	return TranslationServer.standardize_locale(code)


## Godot compares locales after filling in default scripts and countries.
static func locale_target(code: String) -> String:
	return TranslationServer.standardize_locale(code, true)


static func find_locale_index(locales: PackedStringArray, code: String) -> int:
	var exact := locales.find(code)
	if exact >= 0:
		return exact
	var target := locale_target(code)
	for index in locales.size():
		if locale_target(locales[index]) == target:
			return index
	return -1


static func normalize_locale_input(value: String) -> String:
	var text := value.strip_edges().replace("-", "_")
	var fields := text.get_slice("@", 0).split("_")
	if fields[0].length() not in [2, 3] or not fields[0].is_valid_ascii_identifier():
		return ""
	fields[0] = fields[0].to_lower()
	for index in range(1, fields.size()):
		var field := fields[index]
		match field.length():
			2: fields[index] = field.to_upper()
			4: fields[index] = field.left(1).to_upper() + field.substr(1).to_lower()
			_: fields[index] = field.to_lower()
	var suffix := text.substr(text.find("@")) if text.contains("@") else ""
	var normalized := normalize_locale("_".join(fields) + suffix)
	# A dropped qualifier (e.g. the numeric region in es_419 on Godot 4.7)
	# cannot be offered as a separate translation target.
	return normalized if normalized.split("_").size() >= fields.size() else ""


static func _parse(source: String, delimiter: String, unescape_keys := false) -> Dictionary:
	var records := _read_records(source, delimiter)
	if records.has("error"):
		return records
	var lines: Array[PackedStringArray] = records.lines
	if lines.is_empty() or lines[0].size() < 2 or lines[0][0].nocasecmp_to("keys") != 0:
		return {"error": "CSV 首列应为 keys，后面至少有一个语言列。"}
	var locales := PackedStringArray()
	for index in range(1, lines[0].size()):
		var header := lines[0][index]
		if header.begins_with("?") or header.begins_with("_"):
			return {"error": "此 CSV 含上下文、复数或注释列，请使用外部工具编辑。"}
		var code := normalize_locale(header)
		if code.is_empty() or code in locales:
			return {"error": "无效或重复的语言代码：%s" % header}
		locales.append(code)
	var rows := {}
	var decoded_keys := {}
	for index in range(1, lines.size()):
		var record := lines[index]
		var key := record[0]
		if record.size() != locales.size() + 1 or key.strip_edges().is_empty():
			return {"error": "CSV 第 %d 条记录的键或列数不正确。" % (index + 1)}
		if key.to_lower() == "?pluralrule":
			return {"error": "此 CSV 含复数规则，请使用外部工具编辑。"}
		var decoded := key.c_unescape() if unescape_keys else key
		if decoded in decoded_keys:
			return {"error": "翻译键重复：%s" % key}
		decoded_keys[decoded] = true
		rows[key] = record.slice(1)
	return {"locales": locales, "rows": rows}


static func _read_records(source: String, delimiter: String) -> Dictionary:
	var input := source.trim_prefix("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
	var records: Array[PackedStringArray] = []
	var record := PackedStringArray()
	var field := ""
	var quoted := false
	var closed_quote := false
	var index := 0
	while index < input.length():
		var character := input[index]
		index += 1
		if quoted:
			if character != '"':
				field += character
			elif index < input.length() and input[index] == '"':
				field += '"'
				index += 1
			else:
				quoted = false
				closed_quote = true
		elif character == delimiter or character == "\n":
			record.append(field)
			field = ""
			closed_quote = false
			if character == "\n":
				if record.size() > 1 or not record[0].is_empty():
					records.append(record)
				record = PackedStringArray()
		elif closed_quote:
			return {"error": "CSV 第 %d 条记录的引号后有多余字符。" % (records.size() + 1)}
		elif character == '"' and field.is_empty():
			quoted = true
		else:
			field += character
	if quoted:
		return {"error": "CSV 第 %d 条记录的引号未闭合。" % (records.size() + 1)}
	if not record.is_empty() or not field.is_empty():
		record.append(field)
		records.append(record)
	return {"lines": records}
