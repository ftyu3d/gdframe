# 在项目里使用 GDFrame 1.0

主要入口是底部 **GDFrame Dock**。保留旧 Dock 的通用、UI 管理、扩展管理、设置项、更新操作，数据改为 1.0 的显式场景组合。

从项目根目录的 `gdframe.tscn` 开始。根节点继承框架的 `base.tscn`，`modules` 数组中的资源就是游戏启用的扩展。保留这个场景的基础场景引用，选择性导出依靠它找到核心脚本。

## Dock 操作

| 页面 | 操作与新版保存位置 |
| --- | --- |
| 通用 | 图层数、键盘导航、配置场景、项目脚本与信号、结果常量、自定义遮罩、外部 IDE、本地化 CSV、档案路径与重置 |
| 扩展管理 | 已安装模块的启停和顺序；普通、持久化、Node 服务脚手架；删除已停用扩展；生成项目类型入口；GitHub/Gitee 在线安装与版本选择 |
| UI 管理 | 创建场景与脚本并注册到 `ui_scenes`；模糊筛选、打开和定位；默认层、遮罩和导航属性；重命名与删除 |
| 设置项 | 逐行设置显示、窗口尺寸、垂直同步、帧率和语言；新增或修改自定义项与扩展默认值 |
| 更新 | 检查框架版本、切换下载源、选择并安装版本 |

重命名或删除 UI 前，先保存并关闭该场景。重命名更新工程中的完整文件路径引用，场景与脚本保留在原目录；业务代码中使用的 UI ID、动态拼接路径需要同步调整。删除会移除 `ui_scenes` 注册，并将场景及同名脚本移入回收站。

「生成项目类型入口」写入 `gdframe_project/generated/services.gd`，只声明已启用扩展的 getter。已有项目根脚本中显式声明的 getter 保留。项目脚本继承生成脚本，生成脚本继承 `GDFrameRoot`。更改模块后重新生成；业务中的类型引用仍须随项目依赖一起调整。可直接手写这些 getter，无需使用生成器。

新档案从 `profile_defaults` 复制初始数据。例如字段 `settings` 的值 `{"max_fps": 60}` 设置首次运行的帧率上限。已有档案继续使用保存的数据。扩展可以通过自己的 `editor/dock_page.gd` 提供 `static func create_dock_page(context) -> Control`，挂载专用工具页；音频音轨编辑随音频扩展提供。核心与扩展的 `editor/` 文件均由导出过滤器排除。

在线安装会在写入前检查发布包是否包含新版模块描述文件，防止旧包覆盖新注册结构。完成框架或扩展更新后重启编辑器。

## 写业务代码

- 界面根节点继承 `GDFrameUIBase`。用 `GDFrame.ui.register_scene(id, scene)` 注册后，先 `await GDFrame.ui.preload_ui(id)`，再 `GDFrame.ui.open(id)`。使用检查器的 PackedScene 引用可随宿主一起导出。
- 手柄和键鼠都使用 Godot InputMap。`GDFrame.input.device_changed` 通知设备切换；根节点的 `keyboard_nav_focus` 决定键盘能否取得导航焦点。
- 设置通过 `GDFrame.settings` 读写，`GDFrame.save.flush()` 把当前设置和实现存档契约的扩展一起写盘。业务数据放在 `GDFrame.save.get_profile().data` 的项目专用键下。
- 核心没有可选扩展的 API 壳。可复用组件先用 `GDFrame.has_service(id)` 检查能力，再通过 `get_service(id)` 调用。确定依赖扩展的项目可以声明类型化 getter，或在 Dock 点「生成项目类型入口」。

## 添加项目扩展

在 `res://addons/gdframe_weather/` 中编写 `module.gd`。目录名决定服务 ID，比如 `weather`。

```gdscript
extends RefCounted

static func create_service(_host: GDFrameRoot) -> WeatherService:
	return WeatherService.new()
```

新建类型为 `GDFrameModule` 的资源并保存为同目录的 `module.tres`。`entry` 选择入口脚本，`dependencies` 加入服务脚本及该模块运行时使用的场景和资源。在 Dock 启用该模块，即可通过 `GDFrame.get_service(&"weather") as WeatherService` 调用。

返回 Node 的服务由 GDFrame 添加为子节点。顺序依赖可以用数组排序，可选服务间的连接可以放在 `host.services_ready` 回调中。持久化服务可以实现下列方法。

```gdscript
func capture_state() -> Dictionary:
	return {"enabled": enabled}

func restore_state(state: Dictionary) -> void:
	enabled = state.get("enabled", true)
```

新档案传入空字典。读取时提供字段默认值，后续版本就可以给旧档案补充设置。

Dock 布局沿用逐行配置：通用页第一行的外部 IDE 选择后直接应用，选择「不使用外部 IDE」会切回 Godot 内置编辑器并禁用「打开工程」「打开仓库」；扩展每行显示版本、状态、顺序及操作；UI 每行直接显示层级、遮罩、参与导航和文件操作，修改属性立即保存。在线扩展的版本选择和安装按钮也放在对应行。
