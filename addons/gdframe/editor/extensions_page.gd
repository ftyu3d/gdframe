@tool
extends VBoxContainer

const Names = preload("asset_name_util.gd")
const Updater = preload("ext_updater.gd")
const Versions = preload("version_series.gd")
const Api = preload("project_api_gen.gd")
const State = preload("editor_state.gd")
var _context: RefCounted
var _modules: VBoxContainer
var _updater := Updater.new()
var _id: LineEdit
var _title: LineEdit
var _template: OptionButton
var _online_rows: VBoxContainer
var _index: Dictionary = {}
var _busy := false


func _init(context: RefCounted, modules: VBoxContainer) -> void:
	_context = context
	_modules = modules


func _ready() -> void:
	_modules.delete_requested.connect(func(path: String):
		for index in _modules._available.item_count:
			if _modules._available.get_item_metadata(index) == path:
				_modules._available.select(index)
		_delete()
	)
	var tools := HBoxContainer.new()
	add_child(tools)
	var online := VBoxContainer.new()
	online.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var views := ButtonGroup.new()
	var installed := _context.button(tools, "已安装", func(): _show_list(online, false)) as Button
	var available := _context.button(tools, "在线安装与更新", func(): _show_list(online, true)) as Button
	for button in [installed, available]:
		button.toggle_mode = true
		button.button_group = views
	installed.set_pressed_no_signal(true)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	var source := OptionButton.new()
	source.add_item("GitHub")
	source.add_item("Gitee")
	source.select(1 if State.get_update_source() == "gitee" else 0)
	source.item_selected.connect(func(index: int): State.set_update_source("gitee" if index == 1 else "github"))
	tools.add_child(source)
	_context.button(tools, "检查更新", _check)
	_context.button(tools, "生成项目类型入口", _generate_api)
	_context.button(tools, "高级配置", _modules._open_scene)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	online.add_child(scroll)
	_online_rows = VBoxContainer.new()
	_online_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_online_rows)
	var create := HBoxContainer.new()
	add_child(create)
	move_child(create, 0)
	_id = LineEdit.new()
	_id.placeholder_text = "扩展 ID"
	_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.add_child(_id)
	_title = LineEdit.new()
	_title.placeholder_text = "显示名称"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.add_child(_title)
	_template = OptionButton.new()
	for title in ["普通服务", "持久化服务", "Node 服务"]:
		_template.add_item(title)
	create.add_child(_template)
	_context.button(create, "创建扩展", _create)
	_modules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_modules)
	add_child(online)
	online.hide()

	_index = _updater.load_local_ext_index()
	_populate_remote()


func _show_list(online: Control, show_online: bool) -> void:
	online.visible = show_online
	_modules.visible = not show_online


func _exit_tree() -> void:
	_updater.cancel_fetch()


func refresh() -> void:
	if _modules != null:
		_modules.refresh()


func _create() -> void:
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	if _id.text.strip_edges().is_empty():
		_context.report("请输入扩展 ID。")
		return
	var id := Names.normalize_module_id(_id.text)
	var base := "res://addons/gdframe_" + id
	if DirAccess.dir_exists_absolute(base):
		_context.report("扩展目录已存在。")
		return
	var class_id := "Project%sService" % id.to_pascal_case()
	var service := "class_name %s\nextends %s\n" % [class_id, "Node" if _template.selected == 2 else "RefCounted"]
	if _template.selected == 1:
		service += '\nvar enabled := true\n\nfunc capture_state() -> Dictionary:\n\treturn {"enabled": enabled}\n\nfunc restore_state(state: Dictionary) -> void:\n\tenabled = state.get("enabled", true)\n'
	var files := {
		"service.gd": service,
		"module.gd": 'extends RefCounted\n\nstatic func create_service(_host: GDFrameRoot) -> %s:\n\treturn preload("service.gd").new()\n' % class_id,
		"module.tres": '[gd_resource type="Resource" script_class="GDFrameModule" format=3]\n\n[ext_resource type="Script" path="res://addons/gdframe/runtime/module.gd" id="descriptor"]\n[ext_resource type="Script" path="%s/module.gd" id="entry"]\n[ext_resource type="Script" path="%s/service.gd" id="service"]\n\n[resource]\nresource_name = %s\nmetadata/version = "1.0.0"\nscript = ExtResource("descriptor")\nentry = ExtResource("entry")\ndependencies = Array[Resource]([ExtResource("service")])\n' % [base, base, var_to_str(_title.text if not _title.text.is_empty() else id)],
		"README.md": '# %s\n\n在 GDFrame Dock 启用此扩展。通过 get_service(&"%s") 获取服务。\n' % [id, id],
	}
	for file in files:
		if not _context.write_file(base.path_join(file), files[file]):
			return
	_context.scan()
	_context.report("扩展已创建。扫描完成后，可在已安装页启用它。")


func _generate_api() -> void:
	_context.report(Api.generate(_context))


func _delete() -> void:
	var path: String = _modules._selected_path(_modules._available)
	if path.is_empty():
		_context.report("请先停用扩展，再在可用扩展列表选择要删除的扩展。")
		return
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	_context.confirm(self, "删除扩展", "将整个 %s 目录移入回收站。请先调整业务代码中对该扩展的引用。" % path.get_base_dir(), func():
		var success: bool = _context.remove_bundle(path.get_base_dir(), "res://addons")
		_context.scan()
		_context.report("扩展已移入回收站。" if success else "扩展删除失败。")
	)


func _check() -> void:
	if _busy:
		return
	_busy = true
	_context.report("正在检查扩展更新……")
	_index = await _updater.fetch_ext_index(self)
	_busy = false
	_populate_remote()
	_context.report("检查失败：%s" % _index if _index.has("error") else "扩展版本列表已更新。")


func _populate_remote() -> void:
	for row in _online_rows.get_children():
		_online_rows.remove_child(row)
		row.queue_free()
	var entries: Dictionary = _index.get("extensions_by_id", {})
	if entries.is_empty():
		_context.label(_online_rows, "暂无在线扩展列表，请点击「检查更新」。")
		return
	for id in entries:
		var installed := FileAccess.file_exists("res://addons/gdframe_%s/module.tres" % id)
		_online_row(str(id), entries[id], installed)


func _install(entry: Dictionary) -> void:
	_busy = true
	EditorInterface.save_all_scenes()
	_context.report("正在下载 %s……" % entry.id)
	var url: String = _updater.extension_download_url(_updater.get_source(), entry.id, entry.version)
	var success: bool = await _updater.apply_extension_update(self, url, entry.id)
	_busy = false
	_context.scan()
	_context.report("安装完成。新扩展可在已安装页启用；更新后请重启编辑器。" if success else "安装失败，请检查下载源、网络和发布包格式。")


func _online_row(id: String, supported: Dictionary, installed: bool) -> void:
	var panel := PanelContainer.new()
	var stripe := StyleBoxFlat.new()
	stripe.bg_color = Color(1, 1, 1, 0.035 if _online_rows.get_child_count() % 2 == 0 else 0.075)
	panel.add_theme_stylebox_override("panel", stripe)
	_online_rows.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var title := _context.label(row, id) as Label
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := "未安装"
	if installed:
		var descriptor := load("res://addons/gdframe_%s/module.tres" % id) as GDFrameModule
		current = "当前 %s" % str(descriptor.get_meta("version", ""))
	_context.label(row, current)
	var versions := OptionButton.new()
	for entry in Versions.sorted_supported_entries(supported):
		versions.add_item(str(entry.version))
		versions.set_item_metadata(versions.item_count - 1, entry)
	row.add_child(versions)
	_context.button(row, "更新" if installed else "安装", func():
		if _busy or versions.selected < 0 or EditorInterface.is_playing_scene():
			return
		var entry: Dictionary = versions.get_item_metadata(versions.selected)
		_context.confirm(self, "安装扩展", "安装 %s %s？" % [id, entry.version], _install.bind(entry))
	)
