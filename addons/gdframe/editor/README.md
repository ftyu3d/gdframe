# GDFrame 使用指南

在 Godot 项目中启用 GDFrame 后，点击编辑器底部的「GDFrame」打开 Dock。项目的框架入口是 `res://gdframe_project/gdframe.tscn`。这个场景记录 UI、共享遮罩、扩展和档案默认值，游戏启动时由 `GDFrame` Autoload 加载。

## 使用 Dock

| 页签 | 可以做什么 |
| --- | --- |
| 通用 | 配置 UI 图层数、键盘导航焦点和外部 IDE，打开项目脚本、本地化管理和档案目录 |
| UI 管理 | 创建、筛选和定位界面，逐行设置默认图层、遮罩和导航，配置共享遮罩 |
| 设置项 | 修改项目显示设置，编辑和恢复新档案的默认值 |
| 扩展管理 | 安装、启用、停用和排序扩展，创建项目扩展，生成类型入口 |
| 更新 | 选择 GitHub 或 Gitee，检查并安装框架版本 |

扩展提供的工具页显示在「设置项」下方。「扩展管理」和「更新」位于最后两项。通用页的外部 IDE 默认为「不使用外部 IDE」，脚本使用 Godot 内置编辑器。选中外部 IDE 后直接应用，可用「打开工程」和「打开仓库」打开对应目录。安装更新后请重启 Godot 编辑器。

## 界面、导航与遮罩

在「UI 管理」创建界面时，Dock 会生成场景和继承 `GDFrameUIBase` 的脚本，并将场景加入项目的 `ui_scenes`。运行时使用场景文件名作为 UI ID。可以在加载阶段调用 `await GDFrame.ui.preload_ui(id)`，需要显示时调用 `GDFrame.ui.open(id, data)`，关闭时调用 `GDFrame.ui.close(id)`。

界面脚本可以用 `_on_init()` 绑定信号，用 `_on_show(data)` 刷新内容，用 `_on_close()` 决定是否允许关闭。键鼠和手柄动作通过 Godot InputMap 配置。项目根节点的 `keyboard_nav_focus` 控制键盘是否参与焦点导航，`GDFrame.input.device_changed` 可以用于切换按键提示。

在筛选栏右侧点击「创建 / 打开遮罩」，即可编辑项目的共享遮罩。需要多种效果时，可在 `gdframe_project/dim.tscn` 下添加效果节点，通过其脚本的 `on_dim_show(ui_id)` 切换。运行时也可以在预加载或打开界面前调用 `GDFrame.ui.get_dim()` 设置效果参数。多个需要遮罩的界面同时打开时，共享遮罩显示在其中最上层的界面下方。

重命名或删除界面前请保存并关闭场景。重命名后同步修改业务代码中的 UI ID 和动态路径。删除时，Dock 会移除注册并将场景及同名脚本移入回收站。

## 本地化

打开「通用 → 本地化管理」，维护 `res://locale/localization.csv`。

1. 从「添加语言」选择所需语言。支持用中文名称或语言代码搜索，项目已有语言会标记为「已添加」。按地区区分的翻译可分别维护。
2. 搜索翻译键或译文，选中词条后编辑。选择「仅缺译」可检查当前语言。选择「未使用」可查找静态扫描未发现引用的键，删除前请核对外部数据和运行时动态构造的键。
3. 点击「保存并应用」，导入 CSV 并在 Godot 项目中注册翻译。首次保存会创建翻译表。使用「CSV 工具 → 补全框架词条」可补齐缺失词条并保留已有译文。重命名键后请同步更新引用。

「未使用」旁的「重新扫描」检查项目代码和文本资源中的引用。「CSV 工具 → 重新读取 CSV」从磁盘加载翻译表，会放弃尚未保存的编辑。

策划工具等编辑器插件可以实例化 `res://addons/gdframe/editor/locale_panel.gd` 并放入自己的页签。显示页签后调用 `select_key(key)` 定位到具体词条，监听 `saved` 信号可在翻译保存并应用后刷新界面。多个面板共享同一份编辑中的翻译表。

## 项目设置与玩家档案

「设置项」里的**项目设置**直接写入 `project.godot`。设计分辨率用于 UI 和游戏画面的布局，Windows、macOS、Linux 可以分别覆盖启动时的窗口尺寸与模式。点击恢复图标可恢复 Godot 默认值或清除对应平台的覆盖值。桌面游戏可以在启动画面结束时调用 `GDFrame.settings.apply_startup_window()`，应用玩家已保存的窗口尺寸和显示模式。

**档案默认值**用于创建新档案。帧率上限从预设中选择，可通过「编辑帧率预设」维护可选值。自定义项的字段名供代码读取，显示名供 Dock 展示。扩展提供的字段会标明来源。已创建的档案以玩家保存的数据为准。

通过 `GDFrame.settings` 读写基础设置，将游戏进度放在自己定义的档案键下。扩展服务用各自的服务 ID 作为存档键。

```gdscript
func save_progress(chapter: int) -> void:
	GDFrame.settings.set_max_fps(60)
	GDFrame.save.get_profile().data["game"] = {"chapter": chapter}
	var result := GDFrame.save.flush()
	if not GDFrameResult.is_ok(result):
		push_error("保存失败：%s" % result)
```

## 管理和开发扩展

在「扩展管理 → 已安装」启停模块。启用模块从上到下初始化，有顺序依赖时把提供服务的模块放在前面。删除扩展前先停用，再检查项目脚本中是否仍有对应的类型引用。

通过 `GDFrame.has_service(id)` 判断可选能力是否已启用，再用 `GDFrame.get_service(id)` 取得服务。固定依赖扩展的项目可以用「生成项目类型入口」创建 `gdframe_project/generated/services.gd`，用于类型提示和跳转。启停模块后可重新生成，也可以在项目根脚本里手写对应的 getter。

### 创建项目扩展

在「扩展管理」填写扩展 ID 和名称并选择脚手架，或手工创建 `res://addons/gdframe_weather/`，以下以 `weather` 为服务 ID。入口文件 `module.gd` 提供服务工厂，`WeatherService` 是项目自己的服务类。

```gdscript
extends RefCounted

static func create_service(_host: GDFrameRoot) -> WeatherService:
	return WeatherService.new()
```

在同目录保存一个 `GDFrameModule` 类型的 `module.tres`，把 `entry` 指向入口脚本，在 `dependencies` 声明运行时使用的脚本、场景和资源。启用模块后可通过 `GDFrame.get_service(&"weather") as WeatherService` 取得实例。返回 `Node` 的服务会挂到框架根节点下。需要连接可选的其他服务时，使用 `host.services_ready` 信号，在所有服务注册完成后获取。

服务可以实现档案读写方法，`enabled` 是此服务需要持久化的字段。

```gdscript
func capture_state() -> Dictionary:
	return {"enabled": enabled}

func restore_state(state: Dictionary) -> void:
	enabled = bool(state.get("enabled", true))
```

在模块资源的 `profile_settings` 中为字段声明 `label` 和 `default`，即可供项目在 Dock 中编辑初始值。通过 `editor/dock_page.gd` 实现 `static func create_dock_page(context) -> Control`，可以给扩展添加专用工具页。

## 导出检查

- 在导出前保持 GDFrame 插件启用，并确认 `project.godot` 的 `GDFrame` Autoload 指向项目配置场景。配置场景继承框架的 `runtime/base.tscn`。
- 确认已启用运行时需要的所有扩展。导出过滤器排除未启用的 GDFrame 模块以及核心和扩展的 `editor/` 文件。
- 使用选择性导出时，通过 `PackedScene` 等资源属性引用项目 UI 和其他游戏资产，并把仅由代码动态加载的资产加入导出预设。
