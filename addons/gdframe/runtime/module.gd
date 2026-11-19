@tool
class_name GDFrameModule
extends Resource
## 项目从检查器选择模块描述资源。entry 负责创建服务，dependencies 供选择性导出追踪。
@export var entry: Script
@export var dependencies: Array[Resource] = []
## 模块提供的档案设置，按字段填写显示名 label 和默认值 default。
@export var profile_settings: Dictionary = {}


func service_id() -> StringName:
	if entry == null:
		return &""
	return StringName(entry.resource_path.get_base_dir().get_file().trim_prefix("gdframe_"))
