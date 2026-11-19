@tool
extends Window

signal saved

const LocalePanel = preload("locale_panel.gd")

var panel: LocalePanel
var _context: RefCounted


func _init(context: RefCounted) -> void:
	_context = context
	hide()
	force_native = true


func _ready() -> void:
	title = "GDFrame · 本地化管理"
	transient = true
	min_size = Vector2i(680, 440)
	wrap_controls = false
	close_requested.connect(_request_close)
	theme = EditorInterface.get_editor_theme()

	var background := ColorRect.new()
	background.color = EditorInterface.get_base_control().get_theme_color(&"base_color", &"Editor")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	panel = LocalePanel.new(_context.status.get_theme_color(&"font_color"))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.saved.connect(saved.emit)


func _request_close() -> void:
	var document := panel.document
	if document.saving:
		return
	if document.dirty:
		_context.confirm(self, "关闭本地化管理", "关闭窗口并放弃本地化的未保存修改？", func():
			document.reload(true)
			queue_free()
		)
	elif document.sync_pending:
		_context.confirm(self, "关闭本地化管理", "CSV 已保存，但尚未同步到项目。关闭窗口？", queue_free)
	else:
		queue_free()

