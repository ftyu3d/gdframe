<p align="center"><img src="docs/gdframe-logo.png" alt="GDFrame" width="720"></p>

# GDFrame 1.0.0

Godot 4.7+ 的 GDScript 游戏框架。启用插件后，Autoload `GDFrame` 提供 UI、键鼠与手柄导航、显示与语言设置，以及保存这些设置所需的玩家档案。UI 图层在第一次预加载界面时创建。

## 接入新项目

1. 把 `addons/gdframe/` 复制到工程同名目录，在「项目 → 项目设置 → 插件」启用 GDFrame。
2. 插件创建 `res://gdframe.tscn` 并注册 Autoload。将这个场景和 `project.godot` 提交到版本控制。空的 **Modules** 数组就是完整可用的基础配置。
3. 需要扩展时，从 gdframe-ext 复制对应的 `addons/gdframe_<id>/`。在 Godot 底部打开 **GDFrame**，从「可用扩展」选择并点「启用」。Dock 会保存修改，已启用的扩展从上到下加载。删除扩展目录前，先在 Dock 停用它。[扩展清单与用法](https://github.com/ftyu3d/gdframe-ext)

## 基础 API

| 入口 | 用途 |
| --- | --- |
| `GDFrame.ui` | 显式注册、预加载、打开与关闭 UI，管理图层、遮罩和导航焦点 |
| `GDFrame.input` | 识别键盘、鼠标、触屏和手柄，发出 `device_changed`，按设备调整光标与导航 |
| `GDFrame.settings` | 显示模式、窗口尺寸、帧率、垂直同步与语言 |
| `GDFrame.save` | 保存和恢复基础设置、扩展状态和项目数据，包含临时文件与备份恢复 |
| `GDFrame.audio`、`GDFrame.fsm`、`GDFrame.pool` | 三个随核心提供的类型化接口，未启用时分别静默、返回空句柄、返回空实例 |
| `has_service(id)`、`get_service(id)`、`service_ids()` | 检查当前组合，取得实现或枚举已注册的服务 |

在 `gdframe.tscn` 根节点的检查器中可设置 UI 图层数和键盘导航焦点。界面场景的根节点脚本继承 `GDFrameUIBase`。在业务节点的检查器里将菜单场景赋给 `menu_scene`，这样选择性导出也会包含它。

```gdscript
@export var menu_scene: PackedScene

func _ready() -> void:
	GDFrame.ui.register_scene(&"menu", menu_scene)
	await GDFrame.ui.preload_ui(&"menu")
	GDFrame.ui.open(&"menu")
```

```gdscript
func save_preferences() -> void:
	GDFrame.settings.set_max_fps(60)
	GDFrame.save.get_profile().data[&"game"] = {"chapter": 2}
	var err := GDFrame.save.flush()
	if not GDFrameResult.is_ok(err):
		push_error("保存失败 %s" % err)
```

设置会在启动时恢复。桌面项目在启动画面结束后可调用 `GDFrame.settings.apply_startup_window()` 应用保存的窗口尺寸与模式。把游戏进度放在自己的档案键下，服务 ID 对应的键供服务序列化使用。

## 模块契约与导出

扩展入口约定为 `res://addons/gdframe_<id>/module.tres`。其中 `entry` 指向同目录的 `module.gd`，`dependencies` 显式列出运行时脚本和资源。入口脚本实现 `static func create_service(host: GDFrameRoot)`，返回一个 Node 或 RefCounted。核心按清单顺序创建服务，接管 Node 的生命周期。在 `host.services_ready` 回调里连接其他可选服务。服务可实现 `capture_state() -> Dictionary` 和 `restore_state(state: Dictionary)` 接入档案。业务依赖完整实现时，可用 `GDFrame.get_service(&"pool") as GDFrameNodePool` 获得扩展的类型提示。

游戏启动只读取场景引用的模块。导出时保持 GDFrame 插件启用，即使选择「导出所有资源」，过滤器也会跳过未选中的 `gdframe_<id>/module.tres` 所在扩展目录，并排除核心编辑器脚本。静态引用某个扩展类型的业务代码需要选择对应扩展。选择性导出时，项目自己的 UI、状态定义等资产可通过场景或资源的导出属性引用。仅在脚本中加载的资产需加入导出预设。

插件内还附有可离线查阅的业务接入与扩展示例。[本地 API 指南](addons/gdframe/editor/README.md)

## 构建与验证

- Windows 运行 `tools/pack_release.bat`，macOS/Linux 运行 `bash tools/pack_release.sh`，得到 `dist/gdframe.zip`。
- 将 gdframe-ext 放在同级目录后，运行 `powershell -ExecutionPolicy Bypass -File tools/test_composition.ps1 -Godot <Godot可执行文件>`。可用 `-Extensions` 指定其他检出位置。

[MIT License](LICENSE)
