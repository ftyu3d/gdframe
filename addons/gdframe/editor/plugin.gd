@tool
extends EditorPlugin

const COMPOSITION := "res://gdframe.tscn"
const TEMPLATE := """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://addons/gdframe/runtime/base.tscn" id="base"]

[node name="GDFrame" instance=ExtResource("base")]
"""
const ExportFilter = preload("export_filter.gd")
const Dock = preload("module_dock.gd")
var _filter := ExportFilter.new()
var _dock: VBoxContainer


func _enter_tree() -> void:
	add_export_plugin(_filter)
	if not FileAccess.file_exists(COMPOSITION):
		var file := FileAccess.open(COMPOSITION, FileAccess.WRITE)
		if file == null:
			push_error("GDFrame: 无法创建 %s" % COMPOSITION)
			return
		file.store_string(TEMPLATE)
		file.close()
	_dock = Dock.new(COMPOSITION, get_undo_redo())
	add_control_to_bottom_panel(_dock, "GDFrame")
	scene_changed.connect(_dock.refresh.unbind(1))
	# Fresh CI checkouts can enable the plugin directly in project.godot.
	if DisplayServer.get_name() == "headless":
		_register_autoload(false)


func _enable_plugin() -> void:
	_register_autoload(true)


func _register_autoload(update_editor: bool) -> void:
	var path: String = ProjectSettings.get_setting("autoload/GDFrame", "")
	if path.is_empty():
		if update_editor:
			add_autoload_singleton("GDFrame", COMPOSITION)
		ProjectSettings.set_setting("autoload/GDFrame", "*" + COMPOSITION)
		var err := ProjectSettings.save()
		if err != OK:
			push_error("GDFrame: 保存 Autoload 失败 (%s)" % error_string(err))
	elif path != "*" + COMPOSITION:
		push_error("GDFrame: Autoload 名称 GDFrame 已被其他入口占用。")


func _disable_plugin() -> void:
	if ProjectSettings.get_setting("autoload/GDFrame", "") == "*" + COMPOSITION:
		remove_autoload_singleton("GDFrame")


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
	remove_export_plugin(_filter)
