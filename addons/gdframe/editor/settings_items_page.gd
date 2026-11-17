@tool
extends VBoxContainer
## Dock「设置项」页：音轨声明（[code]gdframe_project/settings/*.cfg[/code]）与
## [code]profile_settings_data.gd[/code] 的 profile 字段合成一份清单。
##
## 布局与其它页签一致：顶部一行工具按钮、隔行条纹行列表、底部共用状态栏。
## 本脚本位于 [code]editor/[/code]（含 [code].gdignore[/code]），由 [code]plugin.gd[/code] preload。

const ITEMS: Script = preload("res://addons/gdframe/runtime/settings/settings_items.gd")
const PROFILE_FIELDS: Script = preload("res://addons/gdframe/editor/profile_field_items.gd")
const MODULE_SCAN: Script = preload("res://addons/gdframe/runtime/ext/module_scan.gd")
const MODULE_EDITOR_SCAN: Script = preload("res://addons/gdframe/editor/module_editor_scan.gd")

const PAGE_KEY: String = "settings"

var _dock: Node = null
var _rows: VBoxContainer = null
var _status: Label = null
var _items: Array[Dictionary] = []
var _modules: Array[Script] = []
var _filter_opt: OptionButton = null
var _filter_keys: Array[String] = []
var _filter_key: String = "all"
var _filter_guard: bool = false

var _audio_dialog: ConfirmationDialog = null
var _audio_preset_opt: OptionButton = null
var _audio_presets: Array[Dictionary] = []
var _audio_hint: Label = null
var _audio_id_edit: LineEdit = null
var _audio_bus_edit: LineEdit = null
var _audio_title_edit: LineEdit = null

var _field_dialog: ConfirmationDialog = null
var _field_name_edit: LineEdit = null
var _field_type_opt: OptionButton = null
var _field_default_edit: LineEdit = null


func _ready() -> void:
	_build_ui()


## 由 plugin.gd 注入 Dock，用于共用状态栏、行底纹与生成/写盘逻辑。
func bind_dock(dock: Node) -> void:
	_dock = dock


func status_label() -> Label:
	return _status


# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# 工具按钮收成一行，随最窄 Dock 宽度均分。
	var row_actions: HBoxContainer = HBoxContainer.new()
	row_actions.add_theme_constant_override("separation", 6)
	# 筛选下拉放在「刷新」左侧：按类别 / 扩展来源收窄列表。
	_filter_opt = OptionButton.new()
	_filter_opt.tooltip_text = "按类别或扩展来源筛选下面的设置项。"
	_filter_opt.custom_minimum_size = Vector2(88, 0)
	_filter_opt.add_item("全部")
	_filter_opt.item_selected.connect(_on_filter_selected)
	row_actions.add_child(_filter_opt)
	row_actions.add_child(_tool_button(
		"刷新", "重新扫描音轨设置项与 profile 字段。", &"_on_refresh_pressed"
	))
	row_actions.add_child(_tool_button(
		"新建音轨", "在设置项目录新建一条音轨（kind=\"audio_bus\"）。", &"_on_add_audio_pressed"
	))
	row_actions.add_child(_tool_button(
		"新建字段",
		"在 profile_settings_data.gd 的业务自定义段追加一个 @export 字段。",
		&"_on_add_field_pressed",
	))
	row_actions.add_child(_tool_button(
		"生成音频", "重新生成 generated/audio_channels.gd（GDFrame.audio.play_* 方法）。",
		&"_on_generate_audio_pressed",
	))
	add_child(row_actions)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.custom_minimum_size = Vector2(0, 1)
	scroll.add_child(_rows)

	_status = _dock_status_label()
	add_child(_status)

	_build_audio_dialog()
	_build_field_dialog()


func _tool_button(text: String, tip: String, action: StringName) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: self.call(action))
	return btn


func _row_button(text: String, tip: String, on_press: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.pressed.connect(on_press)
	return btn


func _dock_status_label() -> Label:
	if _dock != null and _dock.has_method(&"_dock_status_label"):
		var shared: Variant = _dock.call(&"_dock_status_label")
		if shared is Label:
			return shared as Label
	var fallback: Label = Label.new()
	fallback.autowrap_mode = TextServer.AUTOWRAP_OFF
	fallback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fallback.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	fallback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return fallback


func _row_stripe_style(use_alt: bool) -> StyleBox:
	if _dock != null and _dock.has_method(&"_dock_row_stripe_stylebox"):
		var sb: Variant = _dock.call(&"_dock_row_stripe_stylebox", use_alt)
		if sb is StyleBox:
			return sb as StyleBox
	return StyleBoxEmpty.new()


func _build_audio_dialog() -> void:
	_audio_dialog = ConfirmationDialog.new()
	_configure_dialog(_audio_dialog)
	_audio_dialog.title = "新建音轨"
	add_child(_audio_dialog)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(380, 0)
	_audio_dialog.add_child(box)
	_audio_preset_opt = _labeled_option(
		box, "内置预设", "由扩展 audio_presets() 提供；选中后自动填好下面三项并锁定为只读。"
	)
	_audio_preset_opt.item_selected.connect(_on_audio_preset_selected)
	_audio_id_edit = _labeled_edit(box, "名称（id）", "必填，如 bgs → 生成 play_bgs")
	_audio_bus_edit = _labeled_edit(box, "音频总线（bus）", "必填，如 BGS")
	_audio_title_edit = _labeled_edit(box, "显示标题（title）", "必填，如 环境音（BGS）")
	_audio_hint = Label.new()
	_audio_hint.visible = false
	_audio_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audio_hint.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
	box.add_child(_audio_hint)
	# 校验不通过时保持弹窗打开，只有真正写入成功才关窗。
	_audio_dialog.dialog_hide_on_ok = false
	_audio_dialog.confirmed.connect(_on_audio_confirmed)


func _build_field_dialog() -> void:
	_field_dialog = ConfirmationDialog.new()
	_configure_dialog(_field_dialog)
	_field_dialog.title = "新建 profile 字段"
	add_child(_field_dialog)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(380, 0)
	_field_dialog.add_child(box)
	_field_name_edit = _labeled_edit(box, "字段名", "如 show_fps")
	var type_row: HBoxContainer = HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	var type_label: Label = Label.new()
	type_label.text = "类型"
	type_label.custom_minimum_size = Vector2(96, 0)
	type_row.add_child(type_label)
	_field_type_opt = OptionButton.new()
	_field_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for type_name: String in PROFILE_FIELDS.TYPE_OPTIONS:
		_field_type_opt.add_item(type_name)
	type_row.add_child(_field_type_opt)
	box.add_child(type_row)
	_field_default_edit = _labeled_edit(box, "默认值", "留空按类型取零值")
	_field_dialog.confirmed.connect(_on_field_confirmed)


func _configure_dialog(dialog: Window) -> void:
	if _dock != null and _dock.has_method(&"_configure_plugin_modal_dialog"):
		_dock.call(&"_configure_plugin_modal_dialog", dialog)


func _labeled_edit(box: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96, 0)
	row.add_child(label)
	var edit: LineEdit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	box.add_child(row)
	return edit


func _labeled_option(box: VBoxContainer, label_text: String, tip: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label: Label = Label.new()
	label.text = label_text
	label.tooltip_text = tip
	label.custom_minimum_size = Vector2(96, 0)
	row.add_child(label)
	var opt: OptionButton = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	box.add_child(row)
	return opt


# =============================================================================
# List
# =============================================================================

## 重新扫描：扩展声明的设置项（只读）+ 工程声明项 + profile 字段。
func refresh() -> void:
	if _rows == null:
		return
	_modules = MODULE_SCAN.load_modules()
	_items = ITEMS.all_items(_modules)
	var seen: Dictionary = {}
	for item: Dictionary in _items:
		seen[str(item.get("id", ""))] = true
	for field: Dictionary in PROFILE_FIELDS.items(_modules):
		var field_id: String = str(field.get("id", ""))
		if field_id.is_empty() or seen.has(field_id):
			continue
		seen[field_id] = true
		_items.append(field)
	_rebuild_filter_options()
	for child: Node in _rows.get_children():
		child.queue_free()
	if _items.is_empty():
		var empty: Label = Label.new()
		empty.text = "暂无设置项"
		_rows.add_child(empty)
		_set_status("0 项")
		return
	var visible: Array[Dictionary] = []
	for item: Dictionary in _items:
		if _passes_filter(item):
			visible.append(item)
	if visible.is_empty():
		var none: Label = Label.new()
		none.text = "当前筛选下没有设置项"
		_rows.add_child(none)
		_set_status("0 / %d 项" % _items.size())
		return
	for index: int in range(visible.size()):
		_rows.add_child(_build_row(index, visible[index]))
	_set_status(_summary(visible))


## 重建筛选下拉：全部 / 音轨 / profile 字段 / 各扩展来源。
func _rebuild_filter_options() -> void:
	if _filter_opt == null:
		return
	var keys: Array[String] = ["all", "audio", "field"]
	var labels: Array[String] = ["全部", "音轨", "profile 字段"]
	var owners: PackedStringArray = PackedStringArray()
	for item: Dictionary in _items:
		var owner_title: String = str(item.get("owner_title", "")).strip_edges()
		if owner_title.is_empty() or owners.has(owner_title):
			continue
		owners.append(owner_title)
	for owner_title: String in owners:
		keys.append("owner:" + owner_title)
		labels.append(owner_title)
	_filter_keys = keys
	_filter_guard = true
	_filter_opt.clear()
	for index: int in range(keys.size()):
		_filter_opt.add_item(labels[index])
		_filter_opt.set_item_metadata(index, keys[index])
	var target: int = 0
	for index: int in range(keys.size()):
		if keys[index] == _filter_key:
			target = index
			break
	_filter_opt.select(target)
	_filter_key = keys[target]
	_filter_guard = false


func _on_filter_selected(index: int) -> void:
	if _filter_guard or _filter_opt == null:
		return
	_filter_key = str(_filter_opt.get_item_metadata(index))
	refresh()


func _passes_filter(item: Dictionary) -> bool:
	if _filter_key == "all":
		return true
	if _filter_key == "audio":
		return StringName(item.get("kind", &"")) == ITEMS.KIND_AUDIO_BUS
	if _filter_key == "field":
		return StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD
	if _filter_key.begins_with("owner:"):
		return str(item.get("owner_title", "")) == _filter_key.substr(6)
	return true


func _build_row(index: int, item: Dictionary) -> PanelContainer:
	var stripe: PanelContainer = PanelContainer.new()
	stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stripe.add_theme_stylebox_override(&"panel", _row_stripe_style((index % 2) == 1))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label: Label = Label.new()
	label.text = _row_text(item)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = _row_tooltip(item)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)

	if _is_movable(item):
		row.add_child(_row_button("上移", "与上一项交换顺序", _move_item.bind(item, -1)))
		row.add_child(_row_button("下移", "与下一项交换顺序", _move_item.bind(item, 1)))
	row.add_child(_row_button("定位", "定位该项的定义文件。", _locate_item.bind(item)))
	if not bool(item.get("locked", false)):
		row.add_child(_row_button("删除", "删除该项定义。", _delete_item.bind(item)))

	stripe.add_child(row)
	return stripe


func _row_text(item: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var item_id: String = str(item.get("id", ""))
	var title: String = str(item.get("title", item_id))
	if bool(item.get("locked", false)):
		parts.append("[模块]")
	if StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD:
		parts.append("%s: %s" % [title, str(item.get("type", ""))])
	else:
		parts.append(title)
	var owner_title: String = str(item.get("owner_title", ""))
	if not owner_title.is_empty():
		parts.append(owner_title)
	if item_id != title:
		parts.append(item_id)
	# 说明取自该项定义处的注释（cfg 的 ; 行 / @export 上方的 ##），作为行内的一项。
	var comment: String = str(item.get("comment", "")).strip_edges()
	if not comment.is_empty():
		parts.append(comment)
	return "  ·  ".join(parts)


func _row_tooltip(item: Dictionary) -> String:
	var item_id: String = str(item.get("id", ""))
	if StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD:
		var lines: PackedStringArray = PackedStringArray([
			"profile 字段：%s（%s）" % [item_id, str(item.get("type", ""))],
			"默认值：%s" % str(item.get("default", "")),
		])
		var source: String = str(item.get("source", ""))
		if not source.is_empty():
			lines.append("脚本：%s:%d" % [source, int(item.get("line", 0))])
		var field_comment: String = str(item.get("comment", "")).strip_edges()
		if not field_comment.is_empty():
			lines.append("说明：%s" % field_comment)
		if bool(item.get("locked", false)):
			lines.append("由模块 profile_fields() 生成或位于自动生成段，只读。")
		else:
			lines.append("业务自定义字段，可删除。")
		return "\n".join(lines)
	var lines_setting: PackedStringArray = PackedStringArray(["音轨：%s" % item_id])
	var bus: String = str(item.get("bus", ""))
	if not bus.is_empty():
		lines_setting.append("音频总线：%s" % bus)
	var setting_source: String = str(item.get("source", ""))
	if not setting_source.is_empty():
		lines_setting.append("定义：%s" % setting_source)
	var setting_comment: String = str(item.get("comment", "")).strip_edges()
	if not setting_comment.is_empty():
		lines_setting.append("说明：%s" % setting_comment)
	if bool(item.get("locked", false)):
		lines_setting.append("由扩展 settings_items() 提供，只读。")
	return "\n".join(lines_setting)


## 只有工程声明的音轨项参与排序（扩展项与 profile 字段不动）。
func _is_movable(item: Dictionary) -> bool:
	if bool(item.get("locked", false)):
		return false
	if StringName(item.get("kind", &"")) != ITEMS.KIND_AUDIO_BUS:
		return false
	return not str(item.get("source", "")).is_empty()


func _summary(visible: Array[Dictionary]) -> String:
	var audio_count: int = 0
	var field_count: int = 0
	for item: Dictionary in visible:
		if StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD:
			field_count += 1
		else:
			audio_count += 1
	var text: String = "音轨 %d 项 · profile 字段 %d 个" % [audio_count, field_count]
	if visible.size() != _items.size():
		text += "（共 %d 项，已筛选）" % _items.size()
	return text


# =============================================================================
# Actions
# =============================================================================

func _on_refresh_pressed() -> void:
	refresh()


func _on_add_audio_pressed() -> void:
	if not _require_not_playing("新建音轨"):
		return
	if _modules.is_empty():
		_modules = MODULE_SCAN.load_modules()
	_audio_presets = _collect_audio_presets()
	_fill_preset_options()
	_clear_audio_fields()
	_audio_dialog.popup_centered(Vector2i(420, 280))
	_audio_id_edit.grab_focus()


## 尚未添加的内置预设（扩展 [code]audio_presets()[/code] 提供）。
## 已添加的判定看工程项里的 [code]preset[/code] 字段，已用过的不再列出。
func _collect_audio_presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used: Dictionary = {}
	for item: Dictionary in _items:
		if StringName(item.get("kind", &"")) != ITEMS.KIND_AUDIO_BUS:
			continue
		var preset_id: String = str(item.get("preset", "")).strip_edges()
		if not preset_id.is_empty():
			used[preset_id] = true
	for mod: Script in _modules:
		if not MODULE_EDITOR_SCAN.has_editor_method(mod, &"audio_presets"):
			continue
		var raw: Variant = MODULE_EDITOR_SCAN.call_editor_method(mod, &"audio_presets")
		if not (raw is Array):
			continue
		for entry: Variant in raw as Array:
			if not (entry is Dictionary):
				continue
			var preset: Dictionary = (entry as Dictionary).duplicate(true)
			var entry_id: String = str(preset.get("id", "")).strip_edges()
			if entry_id.is_empty() or used.has(entry_id):
				continue
			out.append(preset)
	return out


func _fill_preset_options() -> void:
	if _audio_preset_opt == null:
		return
	_audio_preset_opt.clear()
	_audio_preset_opt.add_item("（自定义，手动填写）")
	for preset: Dictionary in _audio_presets:
		var title: String = str(preset.get("title", preset.get("id", "")))
		var bus: String = str(preset.get("bus", ""))
		_audio_preset_opt.add_item("%s（%s）" % [title, bus])
		var index: int = _audio_preset_opt.item_count - 1
		var summary: String = str(preset.get("summary", ""))
		if not summary.is_empty():
			_audio_preset_opt.set_item_tooltip(index, summary)
	_audio_preset_opt.select(0)


func _on_audio_preset_selected(index: int) -> void:
	var preset: Dictionary = _selected_preset(index)
	if preset.is_empty():
		_clear_audio_fields()
		_audio_id_edit.grab_focus()
		return
	_audio_id_edit.text = str(preset.get("id", ""))
	_audio_bus_edit.text = str(preset.get("bus", ""))
	_audio_title_edit.text = str(preset.get("title", ""))
	# 预设决定生成器产出的方法签名，锁定为只读避免改出前后不一致的配置。
	_set_audio_fields_editable(false)
	_show_audio_hint("")


func _clear_audio_fields() -> void:
	_audio_id_edit.text = ""
	_audio_bus_edit.text = ""
	_audio_title_edit.text = ""
	_set_audio_fields_editable(true)
	_show_audio_hint("")


func _set_audio_fields_editable(editable: bool) -> void:
	for edit: LineEdit in [_audio_id_edit, _audio_bus_edit, _audio_title_edit]:
		if edit != null:
			edit.editable = editable


func _show_audio_hint(text: String) -> void:
	if _audio_hint == null:
		return
	_audio_hint.text = text
	_audio_hint.visible = not text.is_empty()


## 下拉第 0 项是「自定义」，其余与 [member _audio_presets] 一一对应。
func _selected_preset(index: int = -1) -> Dictionary:
	if _audio_preset_opt == null:
		return {}
	var pick: int = _audio_preset_opt.selected if index < 0 else index
	if pick <= 0 or pick - 1 >= _audio_presets.size():
		return {}
	return _audio_presets[pick - 1]


func _on_add_field_pressed() -> void:
	if not _require_not_playing("新建字段"):
		return
	_field_name_edit.text = ""
	_field_default_edit.text = ""
	_field_type_opt.select(0)
	_field_dialog.popup_centered(Vector2i(420, 220))
	_field_name_edit.grab_focus()


func _on_audio_confirmed() -> void:
	var item_id: String = _audio_id_edit.text.strip_edges()
	if item_id.is_empty():
		_show_audio_hint("请填写名称（id）。")
		_audio_id_edit.grab_focus()
		return
	if not _is_valid_identifier(item_id):
		_show_audio_hint("名称只能使用字母、数字与下划线，且不能以数字开头。")
		_audio_id_edit.grab_focus()
		return
	var bus: String = _audio_bus_edit.text.strip_edges()
	if bus.is_empty():
		_show_audio_hint("请填写音频总线（bus）。")
		_audio_bus_edit.grab_focus()
		return
	if not _is_valid_identifier(bus):
		_show_audio_hint("音频总线名只能使用字母、数字与下划线。")
		_audio_bus_edit.grab_focus()
		return
	var title: String = _audio_title_edit.text.strip_edges()
	if title.is_empty():
		_show_audio_hint("请填写显示标题（title）。")
		_audio_title_edit.grab_focus()
		return
	if FileAccess.file_exists(ITEMS.item_path(item_id)):
		_show_audio_hint("音轨 %s 已存在。" % item_id)
		_audio_id_edit.grab_focus()
		return
	var preset: Dictionary = _selected_preset()
	var order: int = ITEMS.next_order()
	if not preset.is_empty():
		order = int(preset.get("order", order))
	var item: Dictionary = {
		"id": item_id,
		"kind": ITEMS.KIND_AUDIO_BUS,
		"bus": bus,
		"title": title,
		"order": order,
		"default_linear": ITEMS.DEFAULT_LINEAR,
		"preset": str(preset.get("id", "")),
		"comment": str(preset.get("summary", "")),
	}
	var err: Error = ITEMS.save_item(item)
	if err != OK:
		_show_audio_hint("写入设置项失败（%d）。" % int(err))
		return
	_show_audio_hint("")
	_audio_dialog.hide()
	_update_filesystem(ITEMS.item_path(item_id))
	_generate_audio()
	refresh()
	_set_status("已新建音轨 %s。" % item_id)


func _on_field_confirmed() -> void:
	var field_name: String = _field_name_edit.text.strip_edges()
	var name_error: String = PROFILE_FIELDS.validate_new_name(field_name)
	if not name_error.is_empty():
		_set_status(name_error)
		return
	if _dock != null and _dock.has_method(&"_ensure_profile_settings_script"):
		_dock.call(&"_ensure_profile_settings_script", true)
	var type_name: String = _field_type_opt.get_item_text(_field_type_opt.selected)
	var err: Error = PROFILE_FIELDS.append_field(
		field_name, type_name, _field_default_edit.text.strip_edges()
	)
	if err != OK:
		_set_status("写入 profile 字段失败（%d）。" % int(err))
		return
	_update_filesystem(PROFILE_FIELDS.SCRIPT_PATH)
	_regenerate_profile()
	refresh()
	_set_status("已新增 profile 字段 %s。" % field_name)


func _on_generate_audio_pressed() -> void:
	if not _require_not_playing("生成音频 API"):
		return
	_generate_audio()
	refresh()


func _move_item(item: Dictionary, delta: int) -> void:
	if not _require_not_playing("调整顺序"):
		return
	var movable: Array[Dictionary] = []
	for entry: Dictionary in _items:
		if _is_movable(entry):
			movable.append(entry)
	var item_id: String = str(item.get("id", ""))
	var pos: int = -1
	for index: int in range(movable.size()):
		if str(movable[index].get("id", "")) == item_id:
			pos = index
			break
	var target_pos: int = pos + delta
	if pos < 0 or target_pos < 0 or target_pos >= movable.size():
		_set_status("已经到头了。")
		return
	var other: Dictionary = movable[target_pos]
	var order_a: int = int(item.get("order", ITEMS.DEFAULT_ORDER))
	var order_b: int = int(other.get("order", ITEMS.DEFAULT_ORDER))
	var err_a: Error = ITEMS.set_order(str(item["source"]), order_b)
	var err_b: Error = ITEMS.set_order(str(other["source"]), order_a)
	if err_a != OK or err_b != OK:
		_set_status("写入排序失败。")
		return
	_generate_audio()
	refresh()
	_set_status("已调整 %s 的顺序。" % item_id)


func _delete_item(item: Dictionary) -> void:
	if not _require_not_playing("删除设置项"):
		return
	var item_id: String = str(item.get("id", ""))
	if StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD:
		var err_field: Error = PROFILE_FIELDS.delete_field(item_id)
		if err_field != OK:
			_set_status("删除 profile 字段失败（%d）。" % int(err_field))
			return
		_update_filesystem(PROFILE_FIELDS.SCRIPT_PATH)
		_regenerate_profile()
		refresh()
		_set_status("已删除 profile 字段 %s。" % item_id)
		return
	var source: String = str(item.get("source", ""))
	var err: Error = ITEMS.delete_item(source)
	if err != OK:
		_set_status("删除设置项失败（%d）。" % int(err))
		return
	# [method GDFrameSettingsItems.delete_item] 目录空了会连带删掉 settings 目录，
	# res 路径此时已不存在；刷新函数会向上找到仍存在的父目录做 scan。
	_update_filesystem(source)
	_generate_audio()
	refresh()
	_set_status("已删除音轨 %s。" % item_id)


func _locate_item(item: Dictionary) -> void:
	var path: String = str(item.get("source", ""))
	if path.is_empty():
		path = str(item.get("owner_source", ""))
	if path.is_empty() and StringName(item.get("kind", &"")) == PROFILE_FIELDS.KIND_PROFILE_FIELD:
		path = PROFILE_FIELDS.SCRIPT_PATH
	if path.is_empty():
		path = ITEMS.items_dir()
	EditorInterface.get_file_system_dock().navigate_to_path(path)
	_set_status("已定位 %s。" % path)


func _generate_audio() -> void:
	if _dock == null or not _dock.has_method(&"_sync_audio_channels"):
		_set_status("当前环境不支持生成音频 API。")
		return
	var result: Dictionary = _dock.call(&"_sync_audio_channels")
	_dock.call(&"_apply_audio_channels_generate_writes", result)
	var message: String = str(result.get("message", "")).strip_edges()
	_set_status(message if not message.is_empty() else "已生成 audio_channels.gd。")


func _regenerate_profile() -> void:
	if _dock == null or not _dock.has_method(&"_sync_profile_settings_fields"):
		return
	var result: Dictionary = _dock.call(&"_sync_profile_settings_fields")
	_dock.call(&"_apply_profile_settings_generate_writes", result)


func _update_filesystem(res_path: String) -> void:
	if _dock != null and _dock.has_method(&"_update_editor_filesystem"):
		_dock.call(&"_update_editor_filesystem", res_path)


func _require_not_playing(action_label: String) -> bool:
	if _dock == null or not _dock.has_method(&"_require_editor_not_playing"):
		return true
	return bool(_dock.call(&"_require_editor_not_playing", PAGE_KEY, action_label))


# =============================================================================
# Helpers
# =============================================================================

func _is_valid_identifier(text: String) -> bool:
	var value: String = text.strip_edges()
	if value.is_empty():
		return false
	if value[0].is_valid_int():
		return false
	for index: int in range(value.length()):
		var ch: String = value[index]
		if ch == "_" or ch.is_valid_int():
			continue
		if ch.to_lower() != ch.to_upper():
			continue
		return false
	return true


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = _format_status_text(text)
		_status.tooltip_text = _status.text
	if _dock != null and _dock.has_method(&"_set_dock_status"):
		_dock.call(&"_set_dock_status", PAGE_KEY, text)


func _format_status_text(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return "状态: 就绪"
	if trimmed.begins_with("状态:"):
		return trimmed
	return "状态: %s" % trimmed
