@tool
extends VBoxContainer

const Settings = preload("../runtime/settings/settings_manager.gd")
const LocaleCsv = preload("locale_scaffold.gd")
const STARTUP_MODE := "display/window/size/mode"
const BORDERLESS := "display/window/size/borderless"
const DESKTOP_PLATFORMS := {"windows": "Windows", "macos": "macOS", "linuxbsd": "Linux"}
const WINDOW_MODES := {
	DisplayServer.WINDOW_MODE_WINDOWED: "窗口化",
	DisplayServer.WINDOW_MODE_MINIMIZED: "最小化",
	DisplayServer.WINDOW_MODE_MAXIMIZED: "最大化",
	DisplayServer.WINDOW_MODE_FULLSCREEN: "无边框全屏",
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: "独占全屏",
}
const VSYNC_MODES := {
	DisplayServer.VSYNC_DISABLED: "关闭",
	DisplayServer.VSYNC_ENABLED: "开启",
	DisplayServer.VSYNC_ADAPTIVE: "自适应",
	DisplayServer.VSYNC_MAILBOX: "邮箱模式",
}
const DISPLAY_MODES := {"windowed": "窗口化", "maximized": "最大化", "borderless": "无边框全屏", "exclusive": "独占全屏"}
const FIELD_TYPES := ["文本", "整数", "小数", "开关", "字典", "数组", "其他 Godot 值"]

var _context: RefCounted
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _add_default: Button
var _showing_defaults := false
var _saving := false


func _init(context: RefCounted) -> void:
	_context = context


func _ready() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var group := ButtonGroup.new()
	var project_button := _context.button(toolbar, "项目设置", _show_defaults.bind(false)) as Button
	var defaults_button := _context.button(toolbar, "档案默认值", _show_defaults.bind(true)) as Button
	for button in [project_button, defaults_button]:
		button.toggle_mode = true
		button.button_group = group
	project_button.set_pressed_no_signal(true)
	project_button.tooltip_text = "修改后立即写入 Godot 项目设置。"
	defaults_button.tooltip_text = "用于新档案和游戏内恢复默认。"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	_add_default = _context.button(toolbar, "新增自定义项", _edit_custom)
	_add_default.hide()
	_context.button(toolbar, "刷新", refresh)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows)


func _show_defaults(show_defaults: bool) -> void:
	_showing_defaults = show_defaults
	_add_default.visible = show_defaults
	refresh()
	_scroll.scroll_vertical = 0


func refresh() -> void:
	if _saving or _rows == null or not is_visible_in_tree():
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not _showing_defaults:
		var display := _project_group()
		_project_field(display, "display/window/size/viewport_width", "设计宽度", {}, 1)
		_project_field(display, "display/window/size/viewport_height", "设计高度", {}, 1)
		_project_field(display, Settings.PROJECT_VSYNC, "垂直同步", VSYNC_MODES)
		_context.label(_rows, "启动窗口 · 通用")
		_project_field(_project_group(), STARTUP_MODE, "启动窗口模式", WINDOW_MODES)
		for platform: String in DESKTOP_PLATFORMS:
			_context.label(_rows, "启动窗口 · %s" % DESKTOP_PLATFORMS[platform])
			var mode := _project_group()
			_project_field(mode, STARTUP_MODE, "启动窗口模式", WINDOW_MODES, 0, platform)
			_project_field(mode, BORDERLESS, "无边框窗口", {false: "关闭", true: "开启"}, 0, platform)
			var dimensions := _project_group()
			_project_field(dimensions, Settings.PROJECT_WINDOW_WIDTH, "窗口宽度覆盖", {}, 0, platform)
			_project_field(dimensions, Settings.PROJECT_WINDOW_HEIGHT, "窗口高度覆盖", {}, 0, platform)
		return
	var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
	var stored: Variant = defaults.get("settings", {})
	var basic: Dictionary = stored if stored is Dictionary else {}
	var labels: Dictionary = _context.read_property(&"profile_setting_labels", {})
	var display_mode: Variant = basic.get("display_mode", Settings.default_settings()["display_mode"])
	_profile_choice("显示模式", "display_mode", display_mode, DISPLAY_MODES, basic.has("display_mode"))
	var locales := {"automatic": "跟随系统"}
	var available := LocaleCsv.project_locales()
	if available.is_empty():
		available.append(str(ProjectSettings.get_setting(LocaleCsv.FALLBACK, "en")))
	for locale in available:
		var language := TranslationServer.get_locale_name(locale)
		locales[locale] = "%s（%s）" % [language, locale] if not language.is_empty() else locale
	_profile_choice("游戏语言", "locale", basic.get("locale", "automatic"), locales, basic.has("locale"))
	_fps_row(basic)
	for key: Variant in basic:
		if key not in ["display_mode", "locale", "max_fps"]:
			_custom_row(key, basic[key], "settings", labels.get("settings.%s" % str(key), "档案覆盖 · %s" % str(key)))
	var extension_fields := _extension_fields()
	for service: String in extension_fields:
		var module: GDFrameModule = extension_fields[service]
		var overrides: Variant = defaults.get(service, {})
		for field: Variant in module.profile_settings:
			var definition: Variant = module.profile_settings[field]
			if definition is Dictionary and definition.has("default"):
				var value: Variant = overrides.get(field, definition["default"]) if overrides is Dictionary else definition["default"]
				var title := str(definition.get("label", field))
				_custom_row(field, value, service, title, module.resource_name if not module.resource_name.is_empty() else service, overrides is Dictionary and overrides.has(field))
	for key: Variant in defaults:
		var field_name := str(key)
		var value: Variant = defaults[key]
		if field_name == "settings" and value is Dictionary:
			continue
		if extension_fields.has(field_name) and value is Dictionary:
			var module: GDFrameModule = extension_fields[field_name]
			for field: Variant in value:
				if not module.profile_settings.has(field):
					_custom_row(field, value[field], field_name, labels.get("%s.%s" % [field_name, field], str(field)))
			continue
		_custom_row(key, value, "", labels.get(field_name, field_name))


func _extension_fields() -> Dictionary:
	var fields := {}
	for module: GDFrameModule in _context.read_property(&"modules", []):
		if module != null and module.entry != null and not module.profile_settings.is_empty():
			fields[String(module.service_id())] = module
	return fields


func _fps_row(basic: Dictionary) -> void:
	var choices := {}
	for fps in Settings.max_fps_options():
		choices[fps] = "不限帧率" if fps == 0 else "%d FPS" % fps
	var current := int(basic.get("max_fps", 0))
	var row := _row("帧率上限", "新档案的默认帧率。下拉选项由预设管理。")
	_add_choices(row, choices, current, func(choice): _write("max_fps", choice, "settings"))
	_context.button(row, "编辑帧率预设", _edit_fps_presets)
	var restore_presets := _context.button(row, "恢复预设", _restore_fps_presets.bind(current)) as Button
	restore_presets.disabled = not ProjectSettings.has_setting(Settings.PROJECT_FPS_PRESETS)
	_add_restore(row, func(): _write("max_fps", null, "settings", true), basic.has("max_fps"))


func _restore_fps_presets(current: int) -> void:
	if not Settings.default_max_fps_options().has(current):
		if not _write("max_fps", null, "settings", true):
			return
	if _write_project(Settings.PROJECT_FPS_PRESETS, null):
		refresh.call_deferred()


func _edit_fps_presets() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "编辑帧率预设"
	dialog.ok_button_text = "应用"
	dialog.dialog_hide_on_ok = false
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 380
	dialog.add_child(form)
	_context.label(form, "填写下拉框中的帧率，用逗号分隔。0 表示不限帧率，始终可用。")
	var input := LineEdit.new()
	var labels := PackedStringArray()
	for fps in Settings.max_fps_options():
		labels.append(str(fps))
	input.text = ", ".join(labels)
	form.add_child(input)
	var feedback := _context.label(form, "") as Label
	dialog.confirmed.connect(func():
		var presets: Array[int] = [0]
		for text_value in input.text.replace("，", ",").split(",", false):
			var candidate := text_value.strip_edges()
			if candidate.is_empty():
				continue
			if not candidate.is_valid_int() or candidate.to_int() < 0:
				feedback.text = "请填写非负整数，例如 30, 60, 120。"
				return
			var fps := candidate.to_int()
			if not presets.has(fps):
				presets.append(fps)
		var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
		var basic: Variant = defaults.get("settings", {})
		if basic is Dictionary and not presets.has(int(basic.get("max_fps", 0))):
			feedback.text = "请先将默认帧率切换为要保留的预设。"
			return
		presets.sort()
		dialog.get_ok_button().disabled = true
		dialog.hide.call_deferred()
		await get_tree().process_frame
		await get_tree().process_frame
		if _write_project(Settings.PROJECT_FPS_PRESETS, presets):
			dialog.queue_free()
			refresh.call_deferred()
		else:
			dialog.get_ok_button().disabled = false
			dialog.popup_centered()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _row_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(get_theme_color("font_color", "Label"), 0.12)
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 14
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	_rows.add_child(panel)
	return panel


func _row(title: String, hint: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_row_panel().add_child(row)
	var label := _context.label(row, title) as Label
	label.custom_minimum_size.x = 215
	label.clip_text = true
	label.tooltip_text = "%s\n%s" % [title, hint]
	return row


func _project_group() -> HFlowContainer:
	var group := HFlowContainer.new()
	group.add_theme_constant_override("h_separation", 18)
	group.add_theme_constant_override("v_separation", 4)
	_row_panel().add_child(group)
	return group


func _project_field(group: HFlowContainer, key: String, title: String, choices: Dictionary, minimum: int = 0, platform: String = "") -> void:
	var is_override := not platform.is_empty()
	var setting := key + "." + platform if is_override else key
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	group.add_child(row)
	var label := _context.label(row, title) as Label
	label.tooltip_text = "%s\n%s" % [title, setting]
	var value: Variant = ProjectSettings.get_setting(setting, ProjectSettings.get_setting(key))
	var default_value: Variant = null if is_override else ProjectSettings.property_get_revert(key)
	var can_restore: bool = ProjectSettings.has_setting(setting) if is_override else value != default_value
	var restore_hint := "清除此平台的覆盖值，恢复使用通用项目设置。" if is_override else "恢复为 Godot 的默认值：%s" % str(default_value)
	var restore := func():
		if _write_project(setting, default_value):
			refresh.call_deferred()
	var reset := _add_restore(row, restore, can_restore, restore_hint)
	var apply := func(changed: Variant):
		if _write_project(setting, changed):
			reset.disabled = changed == default_value
	if not choices.is_empty():
		_add_choices(row, choices, value, apply)
	else:
		var number := SpinBox.new()
		number.custom_minimum_size.x = 110
		number.min_value = minimum
		number.allow_greater = true
		number.suffix = "px"
		if is_override:
			number.tooltip_text = "0 表示窗口尺寸使用设计分辨率。"
		number.value = value
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(number)
		number.value_changed.connect(func(changed: float): apply.call(int(changed)))
	row.move_child(reset, -1)


func _write_project(key: String, value: Variant) -> bool:
	var previous: Variant = ProjectSettings.get_setting(key, null) if ProjectSettings.has_setting(key) else null
	if previous == value:
		return true
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		refresh.call_deferred()
		return false
	ProjectSettings.set_setting(key, value)
	var error := ProjectSettings.save()
	if error == OK:
		_context.report("项目设置已保存。")
		return true
	else:
		ProjectSettings.set_setting(key, previous)
		_context.report("项目设置保存失败：%s" % error_string(error))
		refresh.call_deferred()
		return false


func _add_choices(row: HBoxContainer, choices: Dictionary, value: Variant, apply: Callable) -> void:
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: Variant in choices:
		options.add_item(choices[choice])
		options.set_item_metadata(options.item_count - 1, choice)
		if choice == value:
			options.select(options.item_count - 1)
	if not choices.has(value):
		options.add_item("当前值（%s）" % str(value))
		options.set_item_metadata(options.item_count - 1, value)
		options.select(options.item_count - 1)
	options.item_selected.connect(func(index: int): apply.call(options.get_item_metadata(index)))
	row.add_child(options)


func _profile_choice(title: String, key: String, value: Variant, choices: Dictionary, has_override: bool) -> void:
	var row := _row(title, "档案默认值")
	_add_choices(row, choices, value, func(choice): _write(key, choice, "settings"))
	_add_restore(row, func(): _write(key, null, "settings", true), has_override)


func _add_restore(row: HBoxContainer, action: Callable, enabled: bool, hint := "恢复默认") -> Button:
	var button := _context.button(row, "", action) as Button
	button.icon = EditorInterface.get_editor_theme().get_icon(&"ReloadSmall", &"EditorIcons")
	button.flat = true
	button.disabled = not enabled
	button.tooltip_text = hint
	return button


func _custom_row(key: Variant, value: Variant, section: String, title: String, extension: String = "", has_override := false) -> void:
	var path := str(key) if section.is_empty() else "%s.%s" % [section, key]
	var row := _row(title, path)
	var field := _context.label(row, path) as Label
	field.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	field.tooltip_text = path
	if value is bool:
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var toggle := CheckBox.new()
		toggle.text = "启用"
		toggle.button_pressed = value
		row.add_child(toggle)
		toggle.toggled.connect(func(changed: bool): _write(key, changed, section))
	else:
		field.custom_minimum_size.x = 180
		var raw := var_to_str(value)
		var preview := _context.label(row, " ".join(raw.split("\n", false))) as Label
		preview.clip_text = true
		preview.tooltip_text = raw
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_context.label(row, FIELD_TYPES[_type_index(value)])
	if extension.is_empty():
		var initial: Dictionary = _context.read_property(&"profile_setting_initial_values", {})
		_add_restore(row, func(): _write(key, initial[path], section), initial.has(path) and initial.get(path) != value)
		_context.button(row, "编辑", _edit_custom.bind(key, value, section, true))
		_context.button(row, "删除", func():
			_context.confirm(self, "删除自定义项", "从新档案默认值移除「%s」？" % title, func():
				await get_tree().process_frame
				_write(key, null, section, true)
			)
		)
	else:
		_add_restore(row, func(): _write(key, null, section, true), has_override)
		if not value is bool:
			_context.button(row, "编辑", _edit_custom.bind(key, value, section, true, extension))
		_context.label(row, "扩展：%s" % extension)


func _edit_custom(key: Variant = "", value: Variant = "", section: String = "", editing: bool = false, extension: String = "") -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "编辑自定义项" if editing else "新增自定义项"
	dialog.ok_button_text = "保存"
	dialog.dialog_hide_on_ok = false
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 380
	dialog.add_child(form)
	_context.label(form, "字段名（代码中使用）")
	var field := LineEdit.new()
	field.text = str(key)
	field.editable = not editing
	form.add_child(field)
	_context.label(form, "显示名（留空时显示字段名）")
	var display_name := LineEdit.new()
	var path := str(key) if section.is_empty() else "%s.%s" % [section, key]
	var labels: Dictionary = _context.read_property(&"profile_setting_labels", {})
	display_name.text = labels.get(path, "") if extension.is_empty() else extension
	display_name.editable = extension.is_empty()
	form.add_child(display_name)
	var type := OptionButton.new()
	for name_text in FIELD_TYPES:
		type.add_item(name_text)
	form.add_child(type)
	type.disabled = not extension.is_empty()
	var input := TextEdit.new()
	input.custom_minimum_size.y = 92
	form.add_child(input)
	var toggle := CheckBox.new()
	toggle.text = "启用"
	form.add_child(toggle)
	var feedback := _context.label(form, "") as Label
	var select_type := func(index: int):
		toggle.visible = index == 3
		input.visible = index != 3
		input.placeholder_text = ["直接输入文本", "例如 42", "例如 0.5", "", '{"enabled": true}', "[1, 2, 3]", "例如 Vector2(0, 0)"][index]
	type.item_selected.connect(select_type)
	type.select(_type_index(value))
	select_type.call(type.selected)
	toggle.button_pressed = value if value is bool else false
	input.text = str(value) if type.selected == 0 else var_to_str(value)
	dialog.confirmed.connect(func():
		var name_text := field.text.strip_edges()
		var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
		if not editing and (name_text.is_empty() or name_text == "settings" or defaults.has(name_text) or _extension_fields().has(name_text)):
			feedback.text = "请输入未使用的字段名。基础设置请直接在列表中修改。"
			return
		var result := _parse_value(type.selected, input.text, toggle.button_pressed)
		if not result.has("value"):
			feedback.text = "值的格式与所选类型不符，请检查后重试。"
			return
		var label: Variant = display_name.text.strip_edges() if extension.is_empty() else null
		dialog.get_ok_button().disabled = true
		dialog.hide.call_deferred()
		# Scene saving can run editor events. Let the modal finish its close first.
		await get_tree().process_frame
		await get_tree().process_frame
		if _write(key if editing else name_text, result.value, section, false, label):
			dialog.queue_free()
		else:
			dialog.get_ok_button().disabled = false
			dialog.popup_centered()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _type_index(value: Variant) -> int:
	match typeof(value):
		TYPE_STRING: return 0
		TYPE_INT: return 1
		TYPE_FLOAT: return 2
		TYPE_BOOL: return 3
		TYPE_DICTIONARY: return 4
		TYPE_ARRAY: return 5
	return 6


func _parse_value(index: int, raw: String, checked: bool) -> Dictionary:
	match index:
		0: return {"value": raw}
		1: return {"value": raw.to_int()} if raw.strip_edges().is_valid_int() else {}
		2: return {"value": raw.to_float()} if raw.strip_edges().is_valid_float() else {}
		3: return {"value": checked}
	var expression := Expression.new()
	if expression.parse(raw) != OK:
		return {}
	var value: Variant = str_to_var(raw)
	if index == 4 and not value is Dictionary or index == 5 and not value is Array:
		return {}
	if value == null and raw.strip_edges() != "null":
		return {}
	return {"value": value}


func _write(key: Variant, value: Variant, section: String, remove := false, display_name: Variant = null) -> bool:
	var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
	defaults = defaults.duplicate(true)
	var target := defaults
	var path := str(key) if section.is_empty() else "%s.%s" % [section, key]
	var initial: Dictionary = _context.read_property(&"profile_setting_initial_values", {}).duplicate(true)
	var previous_initial := initial.duplicate()
	if not section.is_empty():
		var previous: Variant = defaults.get(section, {})
		if not previous is Dictionary:
			_context.report("该组默认值不是字典，请先修正对应的自定义项。")
			return false
		target = previous
	if remove:
		target.erase(key)
		initial.erase(path)
	else:
		if display_name == null and target.has(key) and target[key] == value:
			return true
		var module: GDFrameModule = _extension_fields().get(section)
		var built_in: bool = section == "settings" and key in ["display_mode", "locale", "max_fps"]
		var extension_field := module != null and module.profile_settings.has(key)
		if not built_in and not extension_field and not initial.has(path):
			initial[path] = target.get(key, value)
		target[key] = value
	if not section.is_empty():
		if target.is_empty():
			defaults.erase(section)
		else:
			defaults[section] = target
	_saving = true
	var properties := {&"profile_defaults": defaults}
	if initial != previous_initial:
		properties[&"profile_setting_initial_values"] = initial
	if remove or display_name != null:
		var labels: Dictionary[String, String] = {}
		labels.assign(_context.read_property(&"profile_setting_labels", {}))
		if remove or display_name == "":
			labels.erase(path)
		else:
			labels[path] = display_name
		properties[&"profile_setting_labels"] = labels
	var saved: bool = _context.set_properties(properties, "GDFrame · 档案默认值")
	_saving = false
	refresh.call_deferred()
	return saved
