@tool
extends VBoxContainer

const LABELS := {
	"display_mode": "显示模式",
	"window_width": "窗口宽度",
	"window_height": "窗口高度",
	"vsync_enabled": "垂直同步",
	"max_fps": "帧率上限",
	"locale": "游戏语言",
}
const DISPLAY_MODES := {"windowed": "窗口化", "maximized": "最大化", "borderless": "无边框全屏", "exclusive": "独占全屏"}
const FIELD_TYPES := ["文本", "整数", "小数", "开关", "字典", "数组", "其他 Godot 值"]

var _context: RefCounted
var _rows: VBoxContainer
var _saving := false


func _init(context: RefCounted) -> void:
	_context = context


func _ready() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var hint := _context.label(toolbar, "仅影响新建档案，已有档案保留各自的设置。") as Label
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context.button(toolbar, "新增自定义项", _edit_custom)
	_context.button(toolbar, "刷新", refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)


func refresh() -> void:
	if _saving or _rows == null or not is_visible_in_tree():
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
	var stored: Variant = defaults.get("settings", {})
	var basic: Dictionary = stored if stored is Dictionary else {}
	var fallback := GDFrameSettingsManager.default_settings()
	_context.label(_rows, "基础设置")
	for key: String in LABELS:
		_basic_row(key, basic, fallback[key])
	_context.label(_rows, "自定义项与扩展设置")
	var count := 0
	for key: Variant in defaults:
		if key == "settings" and stored is Dictionary:
			continue
		_custom_row(key, defaults[key], false)
		count += 1
	for key: Variant in basic:
		if not LABELS.has(key):
			_custom_row(key, basic[key], true)
			count += 1
	if count == 0:
		_context.label(_rows, "暂无自定义项。项目字段和扩展默认值可通过上方按钮添加。")


func _row(title: String, hint: String) -> HBoxContainer:
	var panel := PanelContainer.new()
	var stripe := StyleBoxFlat.new()
	stripe.bg_color = Color(1, 1, 1, 0.035 if _rows.get_child_count() % 2 == 0 else 0.075)
	stripe.content_margin_left = 8
	stripe.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", stripe)
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := _context.label(row, title) as Label
	label.custom_minimum_size.x = 155
	label.clip_text = true
	label.tooltip_text = hint
	return row


func _basic_row(key: String, basic: Dictionary, fallback: Variant) -> void:
	var row := _row(LABELS[key], key)
	var value: Variant = basic.get(key, fallback)
	if typeof(value) != typeof(fallback):
		value = fallback
	var control: Control
	var read: Callable
	if key == "vsync_enabled":
		var toggle := CheckBox.new()
		toggle.text = "启用"
		toggle.button_pressed = value
		control = toggle
		read = func(): return toggle.button_pressed
	elif key in ["window_width", "window_height"]:
		var pixels := SpinBox.new()
		pixels.min_value = 1
		pixels.allow_greater = true
		pixels.suffix = "px"
		pixels.value = value
		control = pixels
		read = func():
			pixels.apply()
			return int(pixels.value)
	else:
		var choices: Dictionary = DISPLAY_MODES
		if key == "max_fps":
			choices = {}
			for fps in GDFrameSettingsManager.max_fps_options():
				choices[fps] = "不限帧率" if fps == 0 else "%d FPS" % fps
		elif key == "locale":
			choices = {"automatic": "跟随系统"}
			for locale in GDFrameSettingsManager.project_locales():
				var language := TranslationServer.get_locale_name(locale)
				choices[locale] = "%s（%s）" % [language, locale] if not language.is_empty() else locale
		var options := OptionButton.new()
		for choice: Variant in choices:
			options.add_item(choices[choice])
			options.set_item_metadata(options.item_count - 1, choice)
			if choice == value:
				options.select(options.item_count - 1)
		if not choices.has(value):
			options.add_item("当前值（%s）" % str(value))
			options.set_item_metadata(options.item_count - 1, value)
			options.select(options.item_count - 1)
		control = options
		read = func(): return options.get_item_metadata(options.selected)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	var source := _context.label(row, "已自定义" if basic.has(key) else "跟随项目") as Label
	source.custom_minimum_size.x = 85
	_context.button(row, "保存", func(): _write(key, read.call(), true))
	var reset := _context.button(row, "恢复默认", func(): _write(key, null, true, true)) as Button
	reset.disabled = not basic.has(key)


func _custom_row(key: Variant, value: Variant, nested: bool) -> void:
	var title := "settings.%s" % str(key) if nested else str(key)
	var row := _row(title, title)
	var raw := var_to_str(value)
	var preview := _context.label(row, " ".join(raw.split("\n", false))) as Label
	preview.clip_text = true
	preview.tooltip_text = raw
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context.label(row, FIELD_TYPES[_type_index(value)])
	_context.button(row, "编辑", _edit_custom.bind(key, value, nested, true))
	_context.button(row, "删除", func():
		_context.confirm(self, "删除自定义项", "从新档案默认值中移除「%s」？" % title, func(): _write(key, null, nested, true))
	)


func _edit_custom(key: Variant = "", value: Variant = "", nested: bool = false, editing: bool = false) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "编辑自定义项" if editing else "新增自定义项"
	dialog.ok_button_text = "保存"
	dialog.dialog_hide_on_ok = false
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 380
	dialog.add_child(form)
	_context.label(form, "字段名（扩展设置请填服务 ID）")
	var field := LineEdit.new()
	field.text = str(key)
	field.editable = not editing
	form.add_child(field)
	var type := OptionButton.new()
	for name_text in FIELD_TYPES:
		type.add_item(name_text)
	form.add_child(type)
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
		if not editing and (name_text.is_empty() or name_text == "settings" or defaults.has(name_text)):
			feedback.text = "请输入未使用的字段名。基础设置请直接在列表中修改。"
			return
		var result := _parse_value(type.selected, input.text, toggle.button_pressed)
		if not result.has("value"):
			feedback.text = "值的格式与所选类型不符，请检查后重试。"
			return
		if _write(key if editing else name_text, result.value, nested):
			dialog.hide()
			dialog.queue_free()
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


func _write(key: Variant, value: Variant, nested: bool, remove := false) -> bool:
	var defaults: Dictionary = _context.read_property(&"profile_defaults", {})
	defaults = defaults.duplicate(true)
	var target := defaults
	if nested:
		var previous: Variant = defaults.get("settings", {})
		if not previous is Dictionary:
			_context.report("基础设置的数据格式有误，请先修正或删除自定义列表中的 settings 项。")
			return false
		target = previous
	if remove:
		target.erase(key)
	else:
		target[key] = value
	if nested:
		if target.is_empty():
			defaults.erase("settings")
		else:
			defaults["settings"] = target
	_saving = true
	var saved: bool = _context.set_property(&"profile_defaults", defaults)
	_saving = false
	if saved:
		refresh.call_deferred()
	return saved
