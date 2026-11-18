class_name GDFrameRoot
extends Node
## 将所需扩展的 module.tres 拖入此数组，顺序即初始化顺序。
@export var modules: Array[GDFrameModule] = []
@export_range(1, 64) var ui_layers := 3
@export var keyboard_nav_focus := true

## 所有服务完成注册后发出，用于连接可选的兄弟服务。
signal services_ready

var ui: GDFrameUIManager
var input: GDFrameInputDeviceTracker
var settings: GDFrameSettingsManager
var save := GDFrameSaveManager.new()

var audio: GDFrameAudioApi = GDFrameAudioApi.new()
var pool: GDFramePoolApi = GDFramePoolApi.new()
var fsm: GDFrameFSMApi = GDFrameFSMApi.new()
var _services: Dictionary[StringName, Object] = {}


func has_service(id: StringName) -> bool:
	return _services.has(id)


func service_ids() -> Array[StringName]:
	return _services.keys()


func get_service(id: StringName) -> Object:
	return _services.get(id)


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
	save.setup(self)
	for descriptor in modules:
		if descriptor == null or descriptor.entry == null:
			push_error("GDFrame: Modules 中存在空模块或缺少入口脚本。")
			continue
		var module := descriptor.entry
		if not module.has_method(&"create_service"):
			push_error("GDFrame: modules 中每个脚本都须实现 static func create_service(host)。")
			continue
		var id := StringName(module.resource_path.get_base_dir().get_file().trim_prefix("gdframe_"))
		if has_service(id):
			push_error("GDFrame: 重复模块 %s" % id)
			continue
		var service: Object = module.call(&"create_service", self)
		if service == null:
			push_error("GDFrame: %s 初始化失败" % id)
			continue
		match id:
			&"audio":
				if not service is GDFrameAudioApi:
					push_error("GDFrame: audio 须继承 GDFrameAudioApi")
					continue
				audio = service
			&"pool":
				if not service is GDFramePoolApi:
					push_error("GDFrame: pool 须继承 GDFramePoolApi")
					continue
				pool = service
			&"fsm":
				if not service is GDFrameFSMApi:
					push_error("GDFrame: fsm 须继承 GDFrameFSMApi")
					continue
				fsm = service
		_services[id] = service
		if service is Node:
			service.name = id
			add_child(service)
	save.restore_services()
	services_ready.emit()
