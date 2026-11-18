class_name GDFrameModule
extends Resource
## 项目从检查器选择模块描述资源。entry 负责创建服务，dependencies 供选择性导出追踪。
@export var entry: Script
@export var dependencies: Array[Resource] = []
