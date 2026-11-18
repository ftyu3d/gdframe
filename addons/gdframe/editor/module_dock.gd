@tool
extends VBoxContainer

signal delete_requested(path: String)

var _rows: VBoxContainer
var _scene_path: String
var _undo: EditorUndoRedoManager
var _enabled: ItemList
var _available: ItemList
var _context: RefCounted
var _enable_button: Button
var _disable_button: Button
var _up_button: Button
var _down_button: Button
var _confirm_disable: ConfirmationDialog
var _pending_disable: String


func _init(context: RefCounted) -> void:
	_context = context
	_scene_path = context.scene_path
	_undo = context.plugin.get_undo_redo()
	name = "GDFrameModuleDock"


func _ready() -> void:
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(lists)
	lists.hide()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_enabled = _create_list(lists, "已启用 · 从上到下加载")
	_available = _create_list(lists, "可用扩展")

	var actions := HBoxContainer.new()
	add_child(actions)
	_enable_button = _add_button(actions, "启用", _enable_selected)
	_disable_button = _add_button(actions, "停用", _confirm_selected)
	_up_button = _add_button(actions, "上移", _move_selected.bind(-1))
	_down_button = _add_button(actions, "下移", _move_selected.bind(1))
	actions.hide()
	_confirm_disable = ConfirmationDialog.new()
	_confirm_disable.title = "停用扩展"
	_confirm_disable.ok_button_text = "停用"
	_confirm_disable.confirmed.connect(_change.bind("disable"))
	add_child(_confirm_disable)

	EditorInterface.get_resource_filesystem().filesystem_changed.connect(refresh)
	_undo.version_changed.connect(refresh, CONNECT_DEFERRED)
	visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _enabled == null or not is_visible_in_tree():
		return
	var selected_enabled := _selected_path(_enabled)
	var selected_available := _selected_path(_available)
	_enabled.clear()
	_available.clear()
	var active: Dictionary[String, bool] = {}
	for module: GDFrameModule in _read_modules():
		if module == null:
			continue
		active[module.resource_path] = true
		_add_item(_enabled, module, selected_enabled)
	var folders := DirAccess.get_directories_at("res://addons")
	folders.sort()
	for folder in folders:
		var path := "res://addons/%s/module.tres" % folder
		if not folder.begins_with("gdframe_") or active.has(path) or not FileAccess.file_exists(path):
			continue
		var module := ResourceLoader.load(path) as GDFrameModule
		if module != null and module.entry != null:
			_add_item(_available, module, selected_available)
	_update_buttons()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for list in [_enabled, _available]:
		for index in list.item_count:
			_build_row(str(list.get_item_metadata(index)), list == _enabled, index, list.item_count)


func _read_modules() -> Array[GDFrameModule]:
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.scene_file_path == _scene_path:
		var modules: Variant = root.get("modules")
		if modules is Array:
			return modules
	var scene := ResourceLoader.load(_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene != null:
		var state := scene.get_state()
		for index in state.get_node_property_count(0):
			if state.get_node_property_name(0, index) == &"modules":
				return state.get_node_property_value(0, index)
	return []


func _create_list(parent: Container, label: String) -> ItemList:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var heading := Label.new()
	heading.text = label
	column.add_child(heading)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_update_buttons.unbind(1))
	column.add_child(list)
	return list


func _add_button(parent: Container, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _add_item(list: ItemList, module: GDFrameModule, selected_path: String) -> void:
	var path := module.resource_path
	var id := path.get_base_dir().get_file().trim_prefix("gdframe_")
	var index := list.add_item(id if module.resource_name.is_empty() else module.resource_name)
	list.set_item_metadata(index, path)
	list.set_item_tooltip(index, path)
	if path == selected_path:
		list.select(index)


func _selected_path(list: ItemList) -> String:
	var selection := list.get_selected_items()
	return "" if selection.is_empty() else str(list.get_item_metadata(selection[0]))


func _update_buttons() -> void:
	var index := _enabled.get_selected_items()
	_enable_button.disabled = _available.get_selected_items().is_empty()
	_disable_button.disabled = index.is_empty()
	_up_button.disabled = index.is_empty() or index[0] == 0
	_down_button.disabled = index.is_empty() or index[0] == _enabled.item_count - 1


func _enable_selected() -> void:
	_change("enable", _selected_path(_available))


func _move_selected(offset: int) -> void:
	_change("move", _selected_path(_enabled), offset)


func _confirm_selected() -> void:
	_pending_disable = _selected_path(_enabled)
	if _pending_disable.is_empty():
		return
	_confirm_disable.dialog_text = "停用后，该扩展不会在游戏启动时加载。依赖它的脚本可能需要调整。"
	_confirm_disable.popup_centered()


func _open_scene() -> void:
	EditorInterface.open_scene_from_path(_scene_path)


func _change(action: String, path: String = "", offset: int = 0) -> void:
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	if action == "disable":
		path = _pending_disable
	if path.is_empty():
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != _scene_path:
		_open_scene()
		root = EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != _scene_path:
		_context.report("配置场景已打开，请再执行一次操作。")
		return
	if not root.get("modules") is Array:
		_context.report("请等待配置场景加载完成后重试。")
		return
	var before: Array[GDFrameModule] = root.get("modules")
	var after: Array[GDFrameModule] = before.duplicate()
	var index := -1
	for i in after.size():
		if after[i] != null and after[i].resource_path == path:
			index = i
			break
	match action:
		"enable":
			if index != -1:
				return
			var module := ResourceLoader.load(path) as GDFrameModule
			if module == null or module.entry == null:
				_context.report("无法加载扩展：%s" % path)
				return
			after.append(module)
		"disable":
			if index == -1:
				return
			after.remove_at(index)
		"move":
			if index == -1 or index + offset < 0 or index + offset >= after.size():
				return
			var module: GDFrameModule = after[index]
			after.remove_at(index)
			after.insert(index + offset, module)

	_undo.create_action("GDFrame 扩展配置", UndoRedo.MERGE_DISABLE, root)
	_undo.add_do_property(root, &"modules", after)
	_undo.add_undo_property(root, &"modules", before)
	_undo.commit_action()
	var error := EditorInterface.save_scene()
	_context.report("扩展配置已保存。" if error == OK else "保存失败：%s" % error_string(error))
	refresh()


func _build_row(path: String, active: bool, index: int, count: int) -> void:
	var module := load(path) as GDFrameModule
	var panel := PanelContainer.new()
	var stripe := StyleBoxFlat.new()
	stripe.bg_color = Color(1, 1, 1, 0.035 if _rows.get_child_count() % 2 == 0 else 0.075)
	panel.add_theme_stylebox_override("panel", stripe)
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var title := Label.new()
	var id := path.get_base_dir().get_file().trim_prefix("gdframe_")
	title.text = "%s · %s" % [module.resource_name if not module.resource_name.is_empty() else id, str(module.get_meta("version", ""))]
	title.tooltip_text = path
	title.custom_minimum_size.x = 200
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var state := Label.new()
	state.text = "已启用 · 顺序 %s" % (index + 1) if active else "未启用"
	state.custom_minimum_size.x = 140
	row.add_child(state)
	if active:
		_add_button(row, "停用", func():
			_pending_disable = path
			_confirm_disable.dialog_text = "停用后该扩展不再加载，业务中的类型引用需同步调整。"
			_confirm_disable.popup_centered()
		)
		_add_button(row, "上移", _change.bind("move", path, -1)).disabled = index == 0
		_add_button(row, "下移", _change.bind("move", path, 1)).disabled = index == count - 1
	else:
		_add_button(row, "启用", _change.bind("enable", path))
		_add_button(row, "删除", func(): delete_requested.emit(path))
	_add_button(row, "脚本", func(): EditorInterface.edit_script(module.entry))
	_add_button(row, "定位", EditorInterface.get_file_system_dock().navigate_to_path.bind(path))
