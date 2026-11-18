@tool
extends VBoxContainer

const Names = preload("asset_name_util.gd")
const UI_ROOT := "res://gdframe_project/ui"
var _context: RefCounted
var _name: LineEdit
var _filter: LineEdit
var _rows: VBoxContainer
var _list: ItemList
var _layer: SpinBox
var _dim: CheckBox
var _nav: CheckBox


func _init(context: RefCounted) -> void:
	_context = context


func _ready() -> void:
	var actions := HBoxContainer.new()
	add_child(actions)
	_name = LineEdit.new()
	_name.placeholder_text = "名称，如 main → ui_main"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_name)
	_context.button(actions, "创建 UI", _create)
	_context.button(actions, "刷新", refresh)
	_filter = LineEdit.new()
	_filter.placeholder_text = "筛选界面名称"
	_filter.text_changed.connect(refresh.unbind(1))
	add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_selected.unbind(1))
	_list.item_activated.connect(_open_scene.unbind(1))
	add_child(_list)
	_list.hide()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var options := HBoxContainer.new()
	add_child(options)
	options.hide()
	_context.label(options, "默认层")
	_layer = SpinBox.new()
	_layer.max_value = 63
	options.add_child(_layer)
	_dim = CheckBox.new()
	_dim.text = "遮罩"
	options.add_child(_dim)
	_nav = CheckBox.new()
	_nav.text = "参与导航"
	options.add_child(_nav)
	_context.button(options, "保存 UI 属性", _save_options)
	_context.button(options, "打开场景", _open_scene)
	_context.button(options, "打开脚本", _open_script)
	_context.button(options, "定位", func(): _context.locate(_path()))
	_context.button(options, "刷新", refresh)
	refresh()


func refresh() -> void:
	if _list == null:
		return
	var selected := _path()
	_list.clear()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_scan(UI_ROOT, selected)
	_selected()


func _scan(directory: String, selected: String) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		return
	for file in DirAccess.get_files_at(directory):
		if not file.ends_with(".tscn") or not file.get_basename().begins_with("ui_"):
			continue
		if not _filter.text.is_empty() and not _filter.text.to_lower().is_subsequence_of(file.to_lower()):
			continue
		var path := directory.path_join(file)
		var index := _list.add_item(file.get_basename())
		_list.set_item_metadata(index, path)
		_list.set_item_tooltip(index, path)
		_build_row(path)
		if path == selected:
			_list.select(index)
	for folder in DirAccess.get_directories_at(directory):
		_scan(directory.path_join(folder), selected)


func _path() -> String:
	var selected := _list.get_selected_items()
	return "" if selected.is_empty() else str(_list.get_item_metadata(selected[0]))


func _selected() -> void:
	var path := _path()
	if path.is_empty():
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_layer.value = 0
	_dim.button_pressed = false
	_nav.button_pressed = true
	var state := scene.get_state()
	for index in state.get_node_property_count(0):
		var key := state.get_node_property_name(0, index)
		var value: Variant = state.get_node_property_value(0, index)
		match key:
			&"ui_default_layer": _layer.value = value
			&"ui_use_dim": _dim.button_pressed = value
			&"ui_nav_participates": _nav.button_pressed = value


func _create() -> void:
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	var id := Names.normalize_ui_name(_name.text)
	if id.is_empty() or id == "ui_":
		_context.report("请输入有效的 UI 名称。")
		return
	var path := UI_ROOT.path_join(id).path_join(id + ".tscn")
	if FileAccess.file_exists(path):
		_context.report("该 UI 已存在。")
		return
	var script := path.get_basename() + ".gd"
	if not _context.write_file(script, 'extends GDFrameUIBase\n\nfunc _on_init() -> void:\n\tpass\n\nfunc _on_show(_data: Variant = null) -> void:\n\tpass\n\nfunc _on_close() -> bool:\n\treturn true\n\nfunc _on_locale_changed() -> void:\n\tpass\n'):
		return
	if not _context.write_file(path, '[gd_scene format=3]\n\n[ext_resource type="Script" path="%s" id="script"]\n\n[node name="%s" type="Control"]\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\nscript = ExtResource("script")\n' % [script, id]):
		return
	var root := _context.root() as Node
	if root == null:
		return
	var scenes: Array[PackedScene] = root.get("ui_scenes").duplicate()
	scenes.append(load(path))
	_context.set_property(&"ui_scenes", scenes)
	_context.scan()
	refresh()
	_context.report("UI 已创建并显式注册，选择性导出会包含它。")


func _open_scene() -> void:
	if not _path().is_empty():
		EditorInterface.open_scene_from_path(_path())


func _open_script() -> void:
	if _path().is_empty():
		return
	var scene := load(_path()) as PackedScene
	var state := scene.get_state()
	for index in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == &"script":
			var script := state.get_node_property_value(0, index) as Script
			_context.open_script(script.resource_path)
			return


func _save_options() -> void:
	var path := _path()
	if path.is_empty() or EditorInterface.is_playing_scene():
		return
	var values := {&"ui_default_layer": int(_layer.value), &"ui_use_dim": _dim.button_pressed, &"ui_nav_participates": _nav.button_pressed}
	_save_values(path, values)


func _save_values(path: String, values: Dictionary) -> void:
	EditorInterface.open_scene_from_path(path)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		return
	var undo := _context.plugin.get_undo_redo() as EditorUndoRedoManager
	undo.create_action("GDFrame UI 属性", UndoRedo.MERGE_DISABLE, root)
	for key in values:
		undo.add_do_property(root, key, values[key])
		undo.add_undo_property(root, key, root.get(key))
	undo.commit_action()
	var error := EditorInterface.save_scene()
	_context.report("UI 属性已保存。" if error == OK else "保存失败。")


func _rename() -> void:
	var path := _path()
	var id := Names.normalize_ui_name(_name.text)
	if path.is_empty() or id.is_empty() or id == "ui_":
		_context.report("请选择 UI 并填写新名称。")
		return
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	_context.confirm(self, "重命名 UI", "将场景及同名脚本改名为 %s，并更新工程中的文件路径引用。动态拼接的 UI ID 需自行调整。" % id, _rename_files.bind(path, id))


func _rename_files(path: String, id: String) -> void:
	if EditorInterface.get_open_scenes().has(path):
		_context.report("请先保存并关闭要重命名的 UI 场景，再执行重命名。")
		return
	var target := path.get_base_dir().path_join(id + ".tscn")
	var old_script := path.get_basename() + ".gd"
	var new_script := target.get_basename() + ".gd"
	if target == path or FileAccess.file_exists(target) or FileAccess.file_exists(new_script):
		_context.report("名称未变化或目标文件已存在。")
		return
	EditorInterface.save_all_scenes()
	var root := _context.root() as Node
	if root == null:
		return
	var scenes: Array[PackedScene] = root.get("ui_scenes").duplicate()
	var source := FileAccess.get_file_as_string(path)
	source = source.replace(old_script, new_script).replace('[node name="%s"' % path.get_file().get_basename(), '[node name="%s"' % id)
	var copies: Dictionary = {target: source}
	if FileAccess.file_exists(old_script):
		copies[new_script] = FileAccess.get_file_as_string(old_script)
	if FileAccess.file_exists(old_script + ".uid"):
		copies[new_script + ".uid"] = FileAccess.get_file_as_string(old_script + ".uid")
	for file: String in copies:
		if not _context.write_file(file, copies[file]):
			return
	# Load a fresh scene state. Existing cached states still refer to the old script.
	var renamed := ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if renamed == null:
		_context.report("新场景加载失败，原文件已保留。")
		return
	for index in scenes.size():
		if scenes[index] != null and scenes[index].resource_path == path:
			scenes[index] = renamed
	if not _context.set_property(&"ui_scenes", scenes):
		return
	var updates: Dictionary = {}
	_collect_references("res://", path, target, old_script, new_script, updates)
	for file: String in updates:
		if not _context.write_file(file, str(updates[file]).replace(path, target).replace(old_script, new_script)):
			_context.report("部分路径引用更新失败。新旧文件均已保留，请检查。")
			return
	var scene_uid := ResourceLoader.get_resource_uid(path)
	if scene_uid != ResourceUID.INVALID_ID:
		ResourceUID.set_id(scene_uid, target)
	if FileAccess.file_exists(new_script + ".uid"):
		var script_uid := ResourceUID.text_to_id(FileAccess.get_file_as_string(new_script + ".uid").strip_edges())
		if script_uid != ResourceUID.INVALID_ID:
			ResourceUID.set_id(script_uid, new_script)
	for file in [path, old_script, old_script + ".uid"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_context.scan()
	refresh()
	_context.report("UI 已重命名并更新文件路径引用。请重新打开引用该 UI 的场景；业务中的 UI ID 请同步调整。")


func _collect_references(directory: String, old_scene: String, new_scene: String, old_script: String, new_script: String, updates: Dictionary) -> void:
	for file in DirAccess.get_files_at(directory):
		var path := directory.path_join(file)
		if path == old_scene or path == old_script or not file.get_extension() in ["tscn", "tres", "gd", "cfg", "godot"]:
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains(old_scene) or text.contains(old_script):
			updates[path] = text
	for folder in DirAccess.get_directories_at(directory):
		if not folder.begins_with("."):
			_collect_references(directory.path_join(folder), old_scene, new_scene, old_script, new_script, updates)


func _delete() -> void:
	var path := _path()
	if path.is_empty():
		return
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	_context.confirm(self, "删除 UI", "将 %s 及同名脚本移入回收站，并移除 UI 注册。业务中的 UI ID 和其他资源引用需自行调整。" % path.get_file(), _delete_files.bind(path))


func _delete_files(path: String) -> void:
	if EditorInterface.get_open_scenes().has(path):
		_context.report("请先保存并关闭要删除的 UI 场景，再执行删除。")
		return
	var root := _context.root() as Node
	if root == null:
		return
	var scenes: Array[PackedScene] = root.get("ui_scenes").duplicate()
	for index in range(scenes.size() - 1, -1, -1):
		if scenes[index] != null and scenes[index].resource_path == path:
			scenes.remove_at(index)
	if not _context.set_property(&"ui_scenes", scenes):
		return
	var success := true
	for file in [path, path + ".uid", path.get_basename() + ".gd", path.get_basename() + ".gd.uid"]:
		if FileAccess.file_exists(file):
			success = _context.remove_bundle(file, UI_ROOT) and success
	_context.scan()
	refresh()
	_context.report("UI 已移入回收站并取消注册。" if success else "部分文件移入回收站失败。")


func _row_select(path: String) -> void:
	for index in _list.item_count:
		if _list.get_item_metadata(index) == path:
			_list.select(index)
			return


func _build_row(path: String) -> void:
	var panel := PanelContainer.new()
	var stripe := StyleBoxFlat.new()
	stripe.bg_color = Color(1, 1, 1, 0.035 if _rows.get_child_count() % 2 == 0 else 0.075)
	panel.add_theme_stylebox_override("panel", stripe)
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var title := _context.label(row, path.get_file().get_basename()) as Label
	title.custom_minimum_size.x = 180
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = path
	_row_select(path)
	_selected()
	_context.label(row, "层级")
	var layer := SpinBox.new()
	layer.max_value = 63
	layer.value = _layer.value
	row.add_child(layer)
	var dim := CheckBox.new()
	dim.text = "遮罩"
	dim.button_pressed = _dim.button_pressed
	row.add_child(dim)
	var nav := CheckBox.new()
	nav.text = "参与导航"
	nav.button_pressed = _nav.button_pressed
	row.add_child(nav)
	var save := func():
		if EditorInterface.is_playing_scene():
			_context.report("请先停止运行游戏。")
			return
		_save_values(path, {&"ui_default_layer": int(layer.value), &"ui_use_dim": dim.button_pressed, &"ui_nav_participates": nav.button_pressed})
	layer.value_changed.connect(func(_value: float): save.call())
	dim.toggled.connect(func(_value: bool): save.call())
	nav.toggled.connect(func(_value: bool): save.call())
	_context.button(row, "脚本", func(): _row_select(path); _open_script())
	_context.button(row, "场景", EditorInterface.open_scene_from_path.bind(path))
	_context.button(row, "定位", _context.locate.bind(path))
	_context.button(row, "重命名", _rename_row.bind(path))
	_context.button(row, "删除", func(): _row_select(path); _delete())


func _rename_row(path: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "重命名 UI"
	var input := LineEdit.new()
	input.text = path.get_file().get_basename()
	input.custom_minimum_size.x = 350
	dialog.add_child(input)
	dialog.confirmed.connect(func():
		if not EditorInterface.is_playing_scene():
			_rename_files(path, Names.normalize_ui_name(input.text))
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()
	input.select_all()
