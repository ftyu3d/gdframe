@tool
extends MarginContainer

signal saved

const Document = preload("locale_document.gd")
const Csv = preload("locale_scaffold.gd")
const Usage = preload("locale_usage.gd")
const LOCALE_NAMES_PATH := "res://addons/gdframe/editor/locale_names_zh.json"

enum LanguageAction { RENAME, DELETE }
enum CsvAction { LOCATE, RELOAD, SEED }
enum EntryFilter { ALL, MISSING, UNUSED }

var document: RefCounted = Document.shared()
var _status_color: Color
var _locale_names: Dictionary
var _table: Dictionary:
	get:
		return document.table
var _refresh_pending := false
var _key := ""
var _locale_index := 0
var _search: LineEdit
var _languages: OptionButton
var _filter: OptionButton
var _rescan: Button
var _usage: Usage
var _scanning_usage := false
var _entries: Tree
var _preview_heading: Label
var _entry_heading: Label
var _translation_heading: Label
var _reference: Label
var _translation: TextEdit
var _count: Label
var _status: Label
var _save_button: Button
var _csv_menu: MenuButton
var _entry_actions: Array[Button] = []
var _add_language: Button
var _language_menu: MenuButton
var _new_key: Button


func _init(status_color := Color(0.65, 0.68, 0.75)) -> void:
	_status_color = status_color


func _ready() -> void:
	theme = EditorInterface.get_editor_theme()
	var locale_names: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCALE_NAMES_PATH))
	if locale_names is Dictionary:
		_locale_names = locale_names
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 12)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)

	var languages := HBoxContainer.new()
	body.add_child(languages)
	_label(languages, "翻译语言")
	_languages = OptionButton.new()
	_languages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_languages.item_selected.connect(_select_language)
	languages.add_child(_languages)
	_add_language = _button(languages, "添加语言", _edit_language.bind(false))
	_language_menu = MenuButton.new()
	_language_menu.text = "语言操作 ▾"
	languages.add_child(_language_menu)
	var language_actions := _language_menu.get_popup()
	language_actions.add_item("修改当前语言代码", LanguageAction.RENAME)
	language_actions.add_item("删除当前语言", LanguageAction.DELETE)
	language_actions.id_pressed.connect(func(id: int):
		match id:
			LanguageAction.RENAME: _edit_language(true)
			LanguageAction.DELETE: _delete_language()
	)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.x = 300
	split.add_child(list)
	var entries_toolbar := HBoxContainer.new()
	list.add_child(entries_toolbar)
	_count = _label(entries_toolbar, "")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_key = _button(entries_toolbar, "新增词条", _edit_key.bind(false))
	var filters := HBoxContainer.new()
	list.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索键名或译文"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_query: String): _refresh_entries())
	filters.add_child(_search)
	_filter = OptionButton.new()
	_filter.add_item("全部", EntryFilter.ALL)
	_filter.add_item("仅缺译", EntryFilter.MISSING)
	_filter.add_item("未使用", EntryFilter.UNUSED)
	_filter.set_item_tooltip(EntryFilter.MISSING, "查看当前语言尚未填写译文的词条。")
	_filter.set_item_tooltip(EntryFilter.UNUSED, "扫描项目代码和文本资源，找出没有发现引用的词条。")
	_filter.item_selected.connect(_entry_filter_changed)
	filters.add_child(_filter)
	_rescan = _button(filters, "重新扫描", _scan_usage)
	_rescan.tooltip_text = "重新检查项目中的翻译键引用，保留当前编辑内容。"
	var headings := HBoxContainer.new()
	list.add_child(headings)
	var key_heading := _label(headings, "翻译键") as Label
	key_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_heading = _label(headings, "译文预览")
	_preview_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries = Tree.new()
	_entries.columns = 2
	_entries.hide_root = true
	_entries.select_mode = Tree.SELECT_ROW
	_entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entries.item_selected.connect(_select_entry)
	list.add_child(_entries)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 260
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail)
	var entry_tools := HBoxContainer.new()
	detail.add_child(entry_tools)
	_entry_heading = _label(entry_tools, "")
	_entry_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var copy_key := _button(entry_tools, "复制键", _copy_key) as Button
	copy_key.tooltip_text = "将当前词条的翻译键复制到剪贴板。"
	_entry_actions.append(copy_key)
	_entry_actions.append(_button(entry_tools, "重命名", _edit_key.bind(true)))
	_entry_actions.append(_button(entry_tools, "删除", _delete_key))
	_reference = _label(detail, "")
	_reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reference.max_lines_visible = 3
	_reference.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_translation_heading = _label(detail, "")
	_translation = TextEdit.new()
	_translation.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_translation.placeholder_text = "译文留空时由 Godot 使用回退规则。"
	_translation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_translation.text_changed.connect(_edit_translation)
	detail.add_child(_translation)
	_entries.item_activated.connect(_translation.grab_focus)

	var footer := HBoxContainer.new()
	body.add_child(footer)
	_status = _label(footer, "")
	_status.add_theme_color_override(&"font_color", _status_color)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_csv_menu = MenuButton.new()
	_csv_menu.text = "CSV 工具 ▾"
	footer.add_child(_csv_menu)
	var csv_actions := _csv_menu.get_popup()
	csv_actions.add_item("定位 CSV", CsvAction.LOCATE)
	csv_actions.add_item("重新读取 CSV", CsvAction.RELOAD)
	csv_actions.set_item_tooltip(csv_actions.get_item_index(CsvAction.RELOAD), "读取磁盘上的 CSV。有未保存的修改时会先询问。")
	csv_actions.add_item("补全框架词条", CsvAction.SEED)
	csv_actions.id_pressed.connect(func(id: int):
		match id:
			CsvAction.LOCATE: EditorInterface.get_file_system_dock().navigate_to_path(Csv.LOCALE_CSV_PATH)
			CsvAction.RELOAD: _request_reload()
			CsvAction.SEED: _seed_builtin()
	)
	_save_button = _button(footer, "保存并应用", _request_save)
	var shortcut := Shortcut.new()
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.command_or_control_autoremap = true
	shortcut.events = [key]
	_save_button.shortcut = shortcut
	document.changed.connect(_on_document_changed)
	document.state_changed.connect(_refresh_status)
	document.saved.connect(func():
		_status.text = "CSV 已同步。有未保存的修改。" if document.dirty else "已保存 CSV 并同步项目翻译。"
		saved.emit()
	)
	visibility_changed.connect(_on_visibility_changed)
	document.reload()
	_refresh_languages()
	_refresh_status()
	if is_visible_in_tree() and _search.editable:
		_search.grab_focus()


## Reveals an exact translation key, clearing filters that may hide it.
func select_key(key: String) -> bool:
	if not is_node_ready() or not _table.has("rows") or not _table.rows.has(key):
		return false
	_search.text = ""
	_filter.select(EntryFilter.ALL)
	_key = key
	_refresh_languages(true)
	_entries.grab_focus()
	return _key == key


func _request_reload() -> void:
	if document.saving:
		return
	if document.dirty:
		_confirm("重新读取 CSV", "放弃本地化的未保存修改并读取磁盘上的 CSV？", func(): document.reload(true))
	else:
		document.reload(true)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	document.reload()
	_refresh_pending = false
	_refresh_languages(true)
	_refresh_status()
	if _search.editable:
		_search.grab_focus()


func _on_document_changed(source: Object) -> void:
	if source == self or not is_visible_in_tree() or _refresh_pending:
		return
	_refresh_pending = true
	_refresh_document.call_deferred()


func _refresh_document() -> void:
	if not _refresh_pending:
		return
	_refresh_pending = false
	if is_visible_in_tree():
		_refresh_languages(true)
		_refresh_status()


func _refresh_status() -> void:
	_save_button.disabled = not _table.has("rows") or document.saving
	if document.saving:
		_status.text = "正在保存并导入…"
	elif not document.last_error.is_empty():
		_status.text = document.last_error
	elif document.dirty:
		_status.text = "有未保存的修改。"
	elif _table.has("error"):
		_status.text = _table.error
	elif _table.hash.is_empty():
		_status.text = "保存后将在 %s 创建本地化 CSV。" % Csv.LOCALE_CSV_PATH
	else:
		_status.text = Csv.LOCALE_CSV_PATH


func _refresh_languages(keep_code := false) -> void:
	var previous: Variant = _languages.get_selected_metadata() if keep_code and _languages.selected >= 0 else null
	var valid := _table.has("locales")
	_languages.clear()
	if valid:
		for code: String in _table.locales:
			_languages.add_item(_language_label(code))
			_languages.set_item_metadata(_languages.item_count - 1, code)
		if previous != null:
			_locale_index = maxi(0, _table.locales.find(str(previous)))
		_locale_index = clampi(_locale_index, 0, _table.locales.size() - 1)
		_languages.select(_locale_index)
	_languages.disabled = not valid
	_search.editable = valid
	_filter.disabled = not valid
	_new_key.disabled = not valid
	_add_language.disabled = not valid
	_language_menu.disabled = not valid
	var actions := _language_menu.get_popup()
	actions.set_item_disabled(actions.get_item_index(LanguageAction.DELETE), not valid or _table.locales.size() <= 1)
	_refresh_csv_actions()
	_save_button.disabled = not valid or document.saving
	_refresh_entries()


func _refresh_csv_actions() -> void:
	var actions := _csv_menu.get_popup()
	actions.set_item_disabled(actions.get_item_index(CsvAction.LOCATE), not FileAccess.file_exists(Csv.LOCALE_CSV_PATH))
	actions.set_item_disabled(actions.get_item_index(CsvAction.SEED), not _table.has("rows"))


func _language_label(code: String) -> String:
	var display := _language_name(code)
	return "%s（%s）" % [display, code] if not display.is_empty() else code


func _language_name(code: String) -> String:
	var regional: Dictionary = _locale_names.get("locales", {})
	if regional.has(code):
		return regional[code]
	var parts := code.get_slice("@", 0).split("_")
	var names: Dictionary = _locale_names.get("languages", {})
	if not names.has(parts[0]):
		return TranslationServer.get_locale_name(code)
	var scripts: Dictionary = _locale_names.get("scripts", {})
	var regions: Dictionary = _locale_names.get("regions", {})
	var qualifiers := PackedStringArray()
	for index in range(1, parts.size()):
		var part := parts[index]
		qualifiers.append(scripts.get(part, regions.get(part, part)))
	if code.contains("@"):
		qualifiers.append(code.get_slice("@", 1))
	var name: String = names[parts[0]]
	return "%s（%s）" % [name, "、".join(qualifiers)] if not qualifiers.is_empty() else name


func _copy_key() -> void:
	if _key.is_empty():
		return
	DisplayServer.clipboard_set(_key)
	_status.text = "已复制翻译键：%s%s" % [_key, "（有未保存的修改）" if document.dirty else ""]


func _select_language(index: int) -> void:
	_locale_index = index
	_refresh_entries()


func _entry_filter_changed(index: int) -> void:
	if index == EntryFilter.UNUSED and not _scanning_usage:
		_scan_usage()
	else:
		_refresh_entries()


func _scan_usage() -> void:
	if _scanning_usage or not _table.has("rows"):
		return
	_scanning_usage = true
	_usage = null
	_refresh_entries()
	await get_tree().process_frame
	var scan := Usage.new()
	var frame_started := Time.get_ticks_usec()
	while scan.step():
		if Time.get_ticks_usec() - frame_started >= 5000:
			await get_tree().process_frame
			frame_started = Time.get_ticks_usec()
	_usage = scan
	_scanning_usage = false
	_refresh_entries()


func _refresh_entries() -> void:
	_rescan.visible = _filter.selected == EntryFilter.UNUSED and _table.has("rows")
	_rescan.disabled = _scanning_usage
	var preferred := _key
	_entries.clear()
	_key = ""
	_count.text = ""
	_count.tooltip_text = ""
	_preview_heading.text = "译文预览"
	if _table.has("rows"):
		var root := _entries.create_item()
		_preview_heading.text = "译文预览 · %s" % _table.locales[_locale_index]
		var filter := _filter.selected
		if filter == EntryFilter.UNUSED and _usage == null:
			_count.text = "正在扫描翻译键…" if _scanning_usage else "等待扫描"
			_refresh_detail()
			return
		var query := _search.text.strip_edges().to_lower()
		var matching := 0
		var selection: TreeItem
		for key: String in _table.rows:
			var cells: PackedStringArray = _table.rows[key]
			if filter == EntryFilter.MISSING and not cells[_locale_index].strip_edges().is_empty():
				continue
			if filter == EntryFilter.UNUSED and _usage.is_referenced(key.c_unescape() if _table.format.unescape_keys else key):
				continue
			if not query.is_empty() and not key.to_lower().contains(query):
				if not _matches_value(cells, query):
					continue
			var entry := _entries.create_item(root)
			entry.set_text(0, key)
			entry.set_tooltip_text(0, key)
			entry.set_metadata(0, key)
			_set_preview(entry, cells[_locale_index])
			matching += 1
			if selection == null or key == preferred:
				selection = entry
		var total: int = _table.rows.size()
		_count.text = "%d 条词条" % total if matching == total else "%d / %d 条词条" % [matching, total]
		if filter == EntryFilter.UNUSED:
			_count.text = "%d 条未发现引用" % matching
			_count.tooltip_text = "根据项目磁盘上的文本文件判断，运行时生成或外部提供的键可能未被识别。"
			if _usage.skipped_files > 0:
				_count.tooltip_text += "\n另有 %d 个文件无法读取。" % _usage.skipped_files
		if selection != null:
			selection.select(0)
			_entries.scroll_to_item(selection)
			_key = selection.get_metadata(0)
	_refresh_detail()


func _matches_value(cells: PackedStringArray, query: String) -> bool:
	for cell: String in cells:
		if cell.to_lower().contains(query):
			return true
	return false


func _select_entry() -> void:
	var item := _entries.get_selected()
	if item != null:
		_key = item.get_metadata(0)
		_refresh_detail()


func _refresh_detail() -> void:
	var selected := not _key.is_empty()
	_entry_heading.text = _key if selected else "请选择词条"
	_entry_heading.tooltip_text = _key
	_translation_heading.text = "编辑译文 · %s" % _table.locales[_locale_index] if selected else "编辑译文"
	_translation.editable = selected
	_translation.set_block_signals(true)
	_translation.text = _table.rows[_key][_locale_index] if selected else ""
	_translation.set_block_signals(false)
	_reference.hide()
	if selected:
		var cells: PackedStringArray = _table.rows[_key]
		var reference_index: int = _table.locales.find(ProjectSettings.get_setting(Csv.FALLBACK, "en"))
		if reference_index == _locale_index or reference_index < 0 or cells[reference_index].strip_edges().is_empty():
			reference_index = -1
			for index in cells.size():
				if index != _locale_index and not cells[index].strip_edges().is_empty():
					reference_index = index
					break
		if reference_index >= 0:
			_reference.text = "参考译文（%s）　%s" % [_table.locales[reference_index], cells[reference_index]]
			_reference.tooltip_text = cells[reference_index]
			_reference.show()
	for button in _entry_actions:
		button.disabled = not selected


func _set_preview(entry: TreeItem, value: String) -> void:
	var preview := value.replace("\n", " ")
	if preview.length() > 150:
		preview = preview.left(150) + "…"
	if value.strip_edges().is_empty():
		entry.set_text(1, "未翻译")
		entry.set_custom_color(1, Color(_entries.get_theme_color(&"font_color"), 0.55))
	else:
		entry.set_text(1, preview)
		entry.clear_custom_color(1)
	entry.set_tooltip_text(1, value)


func _edit_translation() -> void:
	if _key.is_empty():
		return
	var cells: PackedStringArray = _table.rows[_key]
	if cells[_locale_index] == _translation.text:
		return
	cells[_locale_index] = _translation.text
	_table.rows[_key] = cells
	var item := _entries.get_selected()
	if item != null:
		_set_preview(item, _translation.text)
	_mark_dirty()


func _mark_dirty() -> void:
	document.update(self)
	_status.text = "有未保存的修改。"


func _edit_key(rename: bool) -> void:
	var previous := _key if rename else ""
	_prompt("重命名词条" if rename else "新增词条", "翻译键，例如 UI_MENU_PLAY", previous, func(value: String) -> String:
		var key := value.strip_edges()
		if key.is_empty() or key.to_lower() == "?pluralrule":
			return "请输入有效的翻译键。"
		if key == previous:
			return ""
		if _table.rows.has(key):
			return "这个翻译键已存在。"
		if _table.format.unescape_keys:
			for existing: String in _table.rows:
				if existing != previous and existing.c_unescape() == key.c_unescape():
					return "处理转义字符后，这个翻译键已存在。"
		var cells := PackedStringArray()
		if rename:
			cells = _table.rows[previous]
			# Preserve the row's position to keep version-control diffs local.
			var rows := {}
			for existing: String in _table.rows:
				rows[key if existing == previous else existing] = _table.rows[existing]
			_table.rows = rows
		else:
			cells.resize(_table.locales.size())
			_table.rows[key] = cells
		_search.set_text("")
		_filter.select(EntryFilter.ALL)
		_key = key
		_mark_dirty()
		_refresh_entries()
		_translation.grab_focus.call_deferred()
		return ""
	)


func _delete_key() -> void:
	var key := _key
	_confirm("删除词条", "删除「%s」及其所有语言的译文？保存后生效。" % key, func():
		_table.rows.erase(key)
		_mark_dirty()
		_refresh_entries()
	)


func _edit_language(rename: bool) -> void:
	var index := _locale_index
	var previous: String = _table.locales[index] if rename else ""
	_prompt("修改语言代码" if rename else "添加语言", "搜索中文名、英文名或语言代码", previous, func(value: String) -> String:
		var input_code := Csv.normalize_locale_input(value)
		if input_code.is_empty():
			return "请从搜索结果选择语言，或输入有效的 Godot 语言代码。"
		var code := Csv.locale_target(input_code)
		if input_code == previous or code == previous:
			return ""
		var other_locales: PackedStringArray = _table.locales.duplicate()
		if rename:
			other_locales.remove_at(index)
		var existing := Csv.find_locale_index(other_locales, code)
		if existing >= 0:
			return "同一翻译目标已添加：%s。" % _language_label(other_locales[existing])
		var locales: PackedStringArray = _table.locales
		if rename:
			locales[index] = code
		else:
			_locale_index = locales.size()
			locales.append(code)
			for key: String in _table.rows:
				var cells: PackedStringArray = _table.rows[key]
				cells.append("")
				_table.rows[key] = cells
			if not _table.rows.has("LOCALE_NAME"):
				var cells := PackedStringArray()
				cells.resize(locales.size())
				_table.rows["LOCALE_NAME"] = cells
			var names: PackedStringArray = _table.rows["LOCALE_NAME"]
			var display_name := TranslationServer.get_locale_name(code)
			names[_locale_index] = display_name if not display_name.is_empty() else code
			_table.rows["LOCALE_NAME"] = names
		_table.locales = locales
		_mark_dirty()
		_refresh_languages()
		return ""
	, true)


func _delete_language() -> void:
	var index := _locale_index
	if _table.locales.size() <= 1:
		return
	var code: String = _table.locales[index]
	_confirm("删除语言", "删除 %s 及该语言的所有译文？保存后生效。" % _language_label(code), func():
		var locales: PackedStringArray = _table.locales
		locales.remove_at(index)
		_table.locales = locales
		for key: String in _table.rows:
			var cells: PackedStringArray = _table.rows[key]
			cells.remove_at(index)
			_table.rows[key] = cells
		_locale_index = mini(index, locales.size() - 1)
		_mark_dirty()
		_refresh_languages()
	)


func _seed_builtin() -> void:
	var added := 0
	var defaults := Csv.builtin_rows(_table.locales)
	for key: String in defaults:
		if not _table.rows.has(key):
			_table.rows[key] = defaults[key]
			added += 1
	if added == 0:
		_status.text = "框架词条已齐全。"
		return
	_mark_dirty()
	_status.text = "已补全 %d 条框架词条，保存后应用。" % added
	_refresh_entries()


func _prompt(caption: String, hint: String, initial: String, apply: Callable, pick_locale := false) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = caption
	dialog.dialog_hide_on_ok = false
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 375
	dialog.add_child(form)
	var input := LineEdit.new()
	input.placeholder_text = hint
	input.text = initial
	form.add_child(input)
	var suggestions := _add_locale_suggestions(form, input, initial) if pick_locale else null
	var feedback := _label(form, "") as Label
	dialog.confirmed.connect(func():
		if dialog.is_queued_for_deletion():
			return
		var value := input.text.strip_edges() if pick_locale else input.text
		if suggestions != null:
			for index in suggestions.item_count:
				var code: String = suggestions.get_item_metadata(index)
				if value.nocasecmp_to(_language_name(code)) == 0 or value.nocasecmp_to(TranslationServer.get_locale_name(code)) == 0:
					value = code
					break
		var message: String = apply.call(value)
		if message.is_empty():
			dialog.queue_free()
		else:
			feedback.text = message
	)
	if suggestions != null:
		suggestions.item_activated.connect(func(_index: int): dialog.confirmed.emit())
	input.text_submitted.connect(func(_value: String): dialog.confirmed.emit())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()
	input.select_all()


func _add_locale_suggestions(form: VBoxContainer, input: LineEdit, initial: String) -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size.y = 180
	form.add_child(list)
	var choices := _locale_choices(initial)
	var filter := func(query: String):
		list.clear()
		var terms := query.strip_edges().to_lower().replace("-", "_").split(" ", false)
		var code := Csv.normalize_locale_input(query)
		var requested := Csv.locale_target(code) if not code.is_empty() else ""
		for target: String in choices:
			var choice: Dictionary = choices[target]
			if terms.is_empty() and not choice.featured:
				continue
			var search_text: String = choice.search
			var matches := true
			if target != requested:
				for term: String in terms:
					if not search_text.contains(term):
						matches = false
						break
			if matches:
				var label := _language_label(choice.code)
				list.add_item(label + " · 已添加" if choice.installed else label)
				var index := list.item_count - 1
				list.set_item_metadata(index, choice.code)
				list.set_item_disabled(index, choice.installed)
	input.text_changed.connect(filter)
	list.item_selected.connect(func(index: int): input.set_text(list.get_item_metadata(index)))
	filter.call("")
	return list


func _locale_choices(initial: String) -> Dictionary:
	var choices := {}
	var installed := {}
	var initial_target := Csv.locale_target(initial) if not initial.is_empty() else ""
	for code: String in _table.locales:
		var target := Csv.locale_target(code)
		if installed.has(target):
			continue
		installed[target] = true
		if initial.is_empty() or target == initial_target:
			var displayed := initial if target == initial_target else code
			choices[target] = {
				"code": displayed, "installed": initial.is_empty(), "featured": true,
				"search": _locale_search_text(displayed) + _locale_search_text(target),
			}

	var regional: Dictionary = _locale_names.get("locales", {})
	var candidates := TranslationServer.get_all_languages()
	candidates.append_array(PackedStringArray(regional.keys()))
	candidates.sort()
	for candidate: String in candidates:
		var normalized := Csv.normalize_locale_input(candidate)
		if normalized.is_empty():
			continue
		var target := Csv.locale_target(normalized)
		if not choices.has(target):
			if installed.has(target):
				continue
			choices[target] = {"code": target, "installed": false, "featured": false, "search": _locale_search_text(target)}
		var choice: Dictionary = choices[target]
		var fields := normalized.split("_")
		choice.featured = choice.featured or fields.size() == 1 or fields.size() == 2 and fields[1].length() == 4
		choice.search += _locale_search_text(candidate)
	return choices


func _locale_search_text(code: String) -> String:
	return " %s %s %s" % [code.to_lower().replace("-", "_"), _language_name(code).to_lower(), TranslationServer.get_locale_name(code).to_lower()]


func _request_save() -> void:
	if _table.has("rows"):
		document.apply(get_tree())


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _confirm(title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(action)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
