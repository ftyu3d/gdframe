@tool
extends RefCounted
## Dock 各页共用的编辑器操作；不实例化运行时场景。

var plugin: EditorPlugin
var scene_path: String
var status: Label


func _init(owner: EditorPlugin, path: String) -> void:
	plugin = owner
	scene_path = path


func report(message: String) -> void:
	status.text = message.replace("\n", " ")
	status.tooltip_text = message


func root() -> Node:
	var node := EditorInterface.get_edited_scene_root()
	if node == null or node.scene_file_path != scene_path:
		EditorInterface.open_scene_from_path(scene_path)
		node = EditorInterface.get_edited_scene_root()
	if node != null and node.scene_file_path == scene_path and node.get("modules") is Array:
		return node
	return null


func read_property(key: StringName, fallback: Variant = null) -> Variant:
	var node := EditorInterface.get_edited_scene_root()
	if node != null and node.scene_file_path == scene_path and node.get("modules") is Array:
		return node.get(key)
	var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene != null:
		var state := scene.get_state()
		for index in state.get_node_property_count(0):
			if state.get_node_property_name(0, index) == key:
				return state.get_node_property_value(0, index)
	return fallback


func set_property(key: StringName, value: Variant) -> bool:
	if EditorInterface.is_playing_scene():
		report("请先停止运行游戏。")
		return false
	var node := root()
	if node == null:
		report("请等待配置场景打开后重试。")
		return false
	var undo := plugin.get_undo_redo()
	undo.create_action("GDFrame · %s" % key, UndoRedo.MERGE_DISABLE, node)
	undo.add_do_property(node, key, value)
	undo.add_undo_property(node, key, node.get(key))
	undo.commit_action()
	var error := EditorInterface.save_scene()
	report("配置已保存。" if error == OK else "保存失败：%s" % error_string(error))
	return error == OK


func write_file(path: String, content: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		report("创建目录失败：%s" % error_string(error))
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		report("写入失败：%s" % path)
		return false
	file.store_string(content)
	file.close()
	return true


func scan() -> void:
	EditorInterface.get_resource_filesystem().scan()


func locate(path: String) -> void:
	EditorInterface.get_file_system_dock().navigate_to_path(path)


func open_script(path: String) -> void:
	var script := load(path) as Script
	if script != null:
		EditorInterface.edit_script(script)
		EditorInterface.set_main_screen_editor("Script")


func confirm(owner: Node, title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(action)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	owner.add_child(dialog)
	dialog.popup_centered()


func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func label(parent: Node, text: String) -> Label:
	var control := Label.new()
	control.text = text
	parent.add_child(control)
	return control


func remove_bundle(path: String, guard: String) -> bool:
	# Only explicitly selected generated bundles may be removed.
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var boundary := ProjectSettings.globalize_path(guard).simplify_path().trim_suffix("/") + "/"
	if not absolute.begins_with(boundary) or absolute == boundary.trim_suffix("/"):
		report("删除路径超出允许目录。")
		return false
	return OS.move_to_trash(absolute) == OK
