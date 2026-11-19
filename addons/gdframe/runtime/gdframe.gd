class_name GDFrameRoot
extends Node

## 本项目启用的扩展。可在 Dock 的「扩展管理」中调整，列表从上到下依次初始化。
@export var modules: Array[GDFrameModule] = []

## UI 图层的数量。从第 0 层开始，填 3 表示可用第 0、1、2 层。
@export_range(1, 64) var ui_layers := 3

## 开启后可用键盘和手柄在按钮等控件之间切换焦点；关闭后仅手柄可以。
@export var keyboard_nav_focus := true

## 游戏启动时要注册的界面场景。用场景文件名（不含扩展名）作为界面 ID。
@export var ui_scenes: Array[PackedScene] = []

## 所有界面共用的遮罩场景，根节点须为 Control。留空时使用默认半透明黑色遮罩。
@export var dim_scene: PackedScene

## 仅在新建档案时使用的默认值。例如，用 settings 作为键设置初始显示与语言选项。
@export var profile_defaults: Dictionary = {}

## 项目自定义项在 Dock 中显示的名称。键为代码使用的字段名。
@export var profile_setting_labels: Dictionary[String, String] = {}

## Dock 用于恢复项目自定义项的初始值。第一次修改已有项时自动记录。
@export var profile_setting_initial_values: Dictionary = {}

## 所有服务完成注册后发出，用于连接可选的兄弟服务。
signal services_ready

## 注册、预加载、打开和关闭游戏界面。
var ui: GDFrameUIManager
## 获取当前输入设备，判断是否允许界面导航聚焦。
var input: GDFrameInputDeviceTracker
## 读写游戏的基础设置，例如语言、窗口模式和帧率上限。
var settings: GDFrameSettingsManager
## 读取和保存玩家档案。
var save := GDFrameSaveManager.new()

var _services: Dictionary[StringName, Object] = {}


func has_service(id: StringName) -> bool:
	return _services.has(id)


func service_ids() -> Array[StringName]:
	return _services.keys()


func get_service(id: StringName) -> Object:
	return _services.get(id)


## 合并已启用扩展的默认值和项目自定义值，项目值优先。
func get_profile_defaults() -> Dictionary:
	var defaults := profile_defaults.duplicate(true)
	for module in modules:
		if module == null or module.entry == null or module.profile_settings.is_empty():
			continue
		var id := module.service_id()
		var values: Variant = defaults.get(id, {})
		if not values is Dictionary:
			continue
		for field: Variant in module.profile_settings:
			var definition: Variant = module.profile_settings[field]
			if definition is Dictionary and definition.has("default") and not values.has(field):
				values[field] = definition["default"]
		defaults[id] = values
	return defaults.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = GDFrameUIManager.new()
	input = GDFrameInputDeviceTracker.new()
	input.keyboard_nav_focus = keyboard_nav_focus
	settings = GDFrameSettingsManager.new()
	_services = {&"ui": ui, &"input": input, &"settings": settings, &"save": save}
	ui.name = "UI"
	settings.name = "Settings"
	input.name = "Input"
	add_child(ui)
	add_child(settings)
	add_child(input)
	for scene in ui_scenes:
		if scene != null:
			ui.register_scene(StringName(scene.resource_path.get_file().get_basename()), scene)
	save.setup(self)
	for descriptor in modules:
		if descriptor == null or descriptor.entry == null:
			push_error("GDFrame: Modules 中存在空模块或缺少入口脚本。")
			continue
		var module := descriptor.entry
		if not module.has_method(&"create_service"):
			push_error("GDFrame: modules 中每个脚本都须实现 static func create_service(host)。")
			continue
		var id := descriptor.service_id()
		if has_service(id):
			push_error("GDFrame: 重复模块 %s" % id)
			continue
		var service: Object = module.call(&"create_service", self)
		if service == null:
			push_error("GDFrame: %s 初始化失败" % id)
			continue
		_services[id] = service
		if service is Node:
			service.name = id
			add_child(service)
	save.restore_services()
	services_ready.emit()
