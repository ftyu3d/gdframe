@tool
extends VBoxContainer

var _scene_path: String
var _undo: EditorUndoRedoManager
var _enabled: ItemList
var _available: ItemList
var _status: Label
var _enable_button: Button
var _disable_button: Button
var _up_button: Button
var _down_button: Button
var _confirm_disable: ConfirmationDialog
var _pending_disable: String


func _init(scene_path: String, undo: EditorUndoRedoManager) -> void:
	_scene_path = scene_path
	_undo = undo
	name = "GDFrameModuleDock"


func _ready() -> void:
	custom_minimum_size.y = 230
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(lists)
	_enabled = _create_list(lists, "已启用 · 从上到下加载")
	_available = _create_list(lists, "可用扩展")

	var actions := HBoxContainer.new()
	add_child(actions)
	_enable_button = _add_button(actions, "启用", _enable_selected)
	_disable_button = _add_button(actions, "停用", _confirm_selected)
	_up_button = _add_button(actions, "上移", _move_selected.bind(-1))
	_down_button = _add_button(actions, "下移", _move_selected.bind(1))
	_add_button(actions, "高级配置", _open_scene)

	_status = Label.new()
	_status.text = "将扩展目录放进 addons 后即可在这里启用。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
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


func _read_modules() -> Array[GDFrameModule]:
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.scene_file_path == _scene_path:
		return root.get("modules")
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
	if action == "disable":
		path = _pending_disable
	if path.is_empty():
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != _scene_path:
		_open_scene()
		root = EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != _scene_path:
		_status.text = "配置场景已打开，请再执行一次操作。"
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
				_status.text = "无法加载扩展：%s" % path
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
	_status.text = "扩展配置已保存。" if error == OK else "保存失败：%s" % error_string(error)
	refresh()
