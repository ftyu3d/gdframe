# 在项目里使用 GDFrame 1.0

从项目根目录的 `gdframe.tscn` 开始。根节点继承框架的 `base.tscn`，`modules` 数组中的资源就是游戏启用的扩展。保留这个场景的基础场景引用，选择性导出依靠它找到核心脚本。

## 写业务代码

- 界面根节点继承 `GDFrameUIBase`。用 `GDFrame.ui.register_scene(id, scene)` 注册后，先 `await GDFrame.ui.preload_ui(id)`，再 `GDFrame.ui.open(id)`。使用检查器的 PackedScene 引用可随宿主一起导出。
- 手柄和键鼠都使用 Godot InputMap。`GDFrame.input.device_changed` 通知设备切换；根节点的 `keyboard_nav_focus` 决定键盘能否取得导航焦点。
- 设置通过 `GDFrame.settings` 读写，`GDFrame.save.flush()` 把当前设置和实现存档契约的扩展一起写盘。业务数据放在 `GDFrame.save.get_profile().data` 的项目专用键下。
- 可选调用可直接使用 `GDFrame.audio`、`GDFrame.fsm`、`GDFrame.pool` 的基础方法。完整扩展类型只用于确定选择该扩展的业务代码。可复用组件先调用 `GDFrame.has_service(id)` 检查能力。

## 添加项目扩展

在 `res://addons/gdframe_weather/` 中编写 `module.gd`。目录名决定服务 ID，比如 `weather`。

```gdscript
extends RefCounted

static func create_service(_host: GDFrameRoot) -> WeatherService:
	return WeatherService.new()
```

新建类型为 `GDFrameModule` 的资源并保存为同目录的 `module.tres`。`entry` 选择入口脚本，`dependencies` 加入服务脚本及该模块运行时使用的场景和资源。将描述资源拖入项目根场景的 **Modules**，即可通过 `GDFrame.get_service(&"weather") as WeatherService` 调用。

返回 Node 的服务由 GDFrame 添加为子节点。顺序依赖可以用数组排序，可选服务间的连接可以放在 `host.services_ready` 回调中。持久化服务可以实现下列方法。

```gdscript
func capture_state() -> Dictionary:
	return {"enabled": enabled}

func restore_state(state: Dictionary) -> void:
	enabled = state.get("enabled", true)
```

新档案传入空字典。读取时提供字段默认值，后续版本就可以给旧档案补充设置。
