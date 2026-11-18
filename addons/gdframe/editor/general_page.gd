@tool
extends VBoxContainer

const Locale = preload("locale_scaffold.gd")
const Ide = preload("ide_launcher.gd")
const State = preload("editor_state.gd")
var _context: RefCounted
var _layers: SpinBox
var _keyboard: CheckBox
var _ide: OptionButton
var _open_project_button: Button
var _open_repository_button: Button


func _init(context: RefCounted) -> void:
	_context = context


func _ready() -> void:
	var config := HBoxContainer.new()
	add_child(config)
	_context.label(config, "UI 图层数")
	_layers = SpinBox.new()
	_layers.min_value = 1
	_layers.max_value = 64
	config.add_child(_layers)
	_keyboard = CheckBox.new()
	_keyboard.text = "键盘导航焦点"
	config.add_child(_keyboard)
	_context.button(config, "保存配置", _save)
	_context.button(config, "从场景刷新", refresh)
	_context.button(config, "打开配置场景", func(): _context.root())
	var scripts := HBoxContainer.new()
	add_child(scripts)
	_context.button(scripts, "打开项目脚本 / 信号声明", _open_root_script)
	_context.button(scripts, "打开结果常量", _context.open_script.bind("res://addons/gdframe/runtime/save/save_result.gd"))
	_context.button(scripts, "创建 / 打开遮罩", _open_dim)
	var locale := HBoxContainer.new()
	add_child(locale)
	_context.button(locale, "初始化本地化 CSV", _locale)
	_context.button(locale, "定位本地化 CSV", _context.locate.bind(Locale.LOCALE_CSV_PATH))
	var saves := HBoxContainer.new()
	add_child(saves)
	_context.button(saves, "打开档案路径", _open_saves)
	_context.button(saves, "重置档案", _reset_saves)
	var editor := HBoxContainer.new()
	add_child(editor)
	_context.label(editor, "外部 IDE")
	_ide = OptionButton.new()
	_ide.add_item("不使用外部 IDE")
	_ide.set_item_metadata(0, "")
	for item in Ide.Candidates.all():
		_ide.add_item(item.label)
		_ide.set_item_metadata(_ide.item_count - 1, item.id)
	_ide.add_item("使用编辑器已配置的 IDE")
	_ide.set_item_disabled(_ide.item_count - 1, true)
	editor.add_child(_ide)
	_ide.item_selected.connect(func(_index: int): _apply_ide())
	move_child(editor, 0)
	_open_project_button = _context.button(editor, "打开工程", _open_project.bind(false))
	_open_repository_button = _context.button(editor, "打开仓库", _open_project.bind(true))
	for row in [editor, config, scripts, locale, saves]:
		for child in row.get_children():
			if child is Button and not child is CheckBox and not child is OptionButton:
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	State.settings().settings_changed.connect(_sync_ide, CONNECT_DEFERRED)
	_sync_ide()
	refresh()


func refresh() -> void:
	if _layers == null or not is_visible_in_tree():
		return
	_layers.value = _context.read_property(&"ui_layers", 3)
	_keyboard.button_pressed = _context.read_property(&"keyboard_nav_focus", true)


func _save() -> void:
	var layers := int(_layers.value)
	var keyboard := _keyboard.button_pressed
	_context.set_property(&"ui_layers", layers)
	_context.set_property(&"keyboard_nav_focus", keyboard)


func _open_root_script() -> void:
	var root := _context.root() as Node
	if root == null:
		return
	var script := root.get_script() as Script
	if script.resource_path == "res://addons/gdframe/runtime/gdframe.gd":
		var path := "res://gdframe_project/frame.gd"
		if not FileAccess.file_exists(path):
			if not _context.write_file(path, "extends GDFrameRoot\n\n# 项目专用信号和类型化服务入口。\n"):
				return
		script = load(path)
		_context.set_property(&"script", script)
		_context.scan()
	_context.open_script(script.resource_path)


func _open_dim() -> void:
	var root := _context.root() as Node
	if root == null:
		return
	var scene := root.get("dim_scene") as PackedScene
	if scene == null:
		var path := "res://gdframe_project/ui/dim/dim.tscn"
		if not FileAccess.file_exists(path):
			if not _context.write_file(path, '[gd_scene format=3]\n\n[node name="Dim" type="ColorRect"]\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\ncolor = Color(0, 0, 0, 0.5)\n'):
				return
		scene = load(path)
		_context.set_property(&"dim_scene", scene)
		_context.scan()
	EditorInterface.open_scene_from_path(scene.resource_path)


func _locale() -> void:
	var scaffold := Locale.new()
	var result: Dictionary = scaffold.prepare_csv()
	if not result.get("ok", false):
		_context.report("本地化初始化失败：%s" % result)
		return
	_context.scan()
	await EditorInterface.get_resource_filesystem().filesystem_changed
	scaffold.register_translations()
	_context.report("本地化 CSV 已初始化并注册。")


func _open_saves() -> void:
	var path := ProjectSettings.globalize_path("user://gdframe")
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_show_in_file_manager(path)


func _reset_saves() -> void:
	if EditorInterface.is_playing_scene():
		_context.report("请先停止运行游戏。")
		return
	_context.confirm(self, "重置档案", "将删除 user://gdframe 下的档案、备份和临时文件。", func():
		var path := "user://gdframe"
		if not DirAccess.dir_exists_absolute(path):
			_context.report("没有需要重置的档案。")
			return
		_context.report("档案已移入回收站。" if _context.remove_bundle(path, "user://") else "重置失败。")
	)


func _apply_ide() -> void:
	var id := str(_ide.get_item_metadata(_ide.selected))
	_context.report(Ide.configure(id))
	_sync_ide()


func _sync_ide() -> void:
	var enabled := Ide.is_enabled()
	var index := 0
	if enabled:
		index = _ide.item_count - 1
		var id := State.get_external_editor_ide()
		for candidate in range(1, index):
			if _ide.get_item_metadata(candidate) == id:
				index = candidate
				break
	_ide.select(index)
	var disabled := not Ide.can_open_folder()
	_open_project_button.disabled = disabled
	_open_repository_button.disabled = disabled


func _open_project(repository: bool) -> void:
	var path := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if repository:
		var candidate := path
		while candidate != candidate.get_base_dir():
			if DirAccess.dir_exists_absolute(candidate.path_join(".git")) or FileAccess.file_exists(candidate.path_join(".git")):
				path = candidate
				break
			candidate = candidate.get_base_dir()
	_context.report(Ide.open_folder(path))
