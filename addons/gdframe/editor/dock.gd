@tool
extends HBoxContainer

const Context = preload("dock_context.gd")
const Modules = preload("module_dock.gd")
const General = preload("general_page.gd")
const UIPage = preload("ui_page.gd")
const Settings = preload("settings_page.gd")
const LocaleDocument = preload("locale_document.gd")
const Extensions = preload("extensions_page.gd")
const Updates = preload("updates_page.gd")

var context: RefCounted
var _pages: VBoxContainer
var _sidebar: VBoxContainer
var _group := ButtonGroup.new()
var _modules: VBoxContainer
var _general: General
var _body: VBoxContainer
var _extension_pages: Array[Control] = []
var _extension_buttons: Array[Button] = []


func _init(plugin: EditorPlugin, scene_path: String) -> void:
	name = "GDFrameDock"
	context = Context.new(plugin, scene_path)


func _ready() -> void:
	var navigation := ScrollContainer.new()
	navigation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation.custom_minimum_size.x = 120
	add_child(navigation)
	_sidebar = VBoxContainer.new()
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(_sidebar)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	var content := ScrollContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(content)
	_pages = VBoxContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_pages)
	context.status = Label.new()
	context.status.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	context.status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.add_child(context.status)
	_general = General.new(context)
	_add_page("通用", _general)
	_modules = Modules.new(context)
	var extensions := Extensions.new(context, _modules)
	_add_page("UI 管理", UIPage.new(context))
	var settings := Settings.new(context)
	_add_page("设置项", settings)
	LocaleDocument.shared().saved.connect(settings.refresh)
	_add_page("扩展管理", extensions)
	_add_page("更新", Updates.new(context))
	_general.minimum_size_changed.connect(_update_minimum_height, CONNECT_DEFERRED)
	context.status.minimum_size_changed.connect(_update_minimum_height, CONNECT_DEFERRED)
	(_sidebar.get_child(0) as Button).button_pressed = true
	_show(_pages.get_child(0))
	context.report("就绪。配置保存在 %s。" % context.scene_path.trim_prefix("res://"))
	_update_minimum_height()
	visibility_changed.connect(refresh)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_rebuild_extension_pages)
	_rebuild_extension_pages()


func _update_minimum_height() -> void:
	var general_height := _general.get_combined_minimum_size().y
	var status_height: float = context.status.get_combined_minimum_size().y
	custom_minimum_size.y = general_height + status_height + _body.get_theme_constant("separation")


func _add_page(title: String, page: Control, index: int = -1) -> Button:
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.hide()
	_pages.add_child(page)
	var button := context.button(_sidebar, title, _show.bind(page)) as Button
	button.toggle_mode = true
	button.button_group = _group
	if index >= 0:
		_pages.move_child(page, index)
		_sidebar.move_child(button, index)
	return button


func _show(page: Control) -> void:
	for child in _pages.get_children():
		child.visible = child == page
	if page.has_method(&"refresh"):
		page.call(&"refresh")


func refresh() -> void:
	if _pages == null or not is_visible_in_tree():
		return
	for page in _pages.get_children():
		if page.visible and page.has_method(&"refresh"):
			page.call(&"refresh")


func _rebuild_extension_pages() -> void:
	var active_title := ""
	for page in _extension_pages:
		if page.visible:
			active_title = str(page.name)
	for page in _extension_pages:
		_pages.remove_child(page)
		page.queue_free()
	for button in _extension_buttons:
		_sidebar.remove_child(button)
		button.queue_free()
	_extension_pages.clear()
	_extension_buttons.clear()
	# Editor pages belong to their extension, independent of the runtime service.
	for folder in DirAccess.get_directories_at("res://addons"):
		var path := "res://addons/%s/editor/dock_page.gd" % folder
		if not folder.begins_with("gdframe_") or not FileAccess.file_exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.has_method(&"create_dock_page"):
			continue
		var page: Control = script.call(&"create_dock_page", context)
		if page == null:
			continue
		_extension_pages.append(page)
		# Keep extension management and updates at the end of the sidebar.
		var button := _add_page(str(page.name), page, _sidebar.get_child_count() - 2)
		_extension_buttons.append(button)
		if str(page.name) == active_title:
			button.button_pressed = true
			_show(page)
	if not active_title.is_empty() and not _pages.get_children().any(func(page: Control): return page.visible):
		(_sidebar.get_child(0) as Button).button_pressed = true
		_show(_pages.get_child(0))
