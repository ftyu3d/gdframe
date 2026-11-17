# GDFrame

面向 Godot 的 GDScript 插件化运行时框架。启用插件后会自动注册全局单例 **`GDFrame`**（Autoload）。

## 目录

- [1. 安装与启动](#1-安装与启动)
- [2. 全局 API 总览](#2-全局-api-总览)
- [3. 工程目录](#3-工程目录)
- [4. 全局信号](#4-全局信号)
- [5. UI 管理 `ui`](#5-ui-管理-ui)
- [6. 输入 `input`](#6-输入-input)
- [7. 存档、设置、音频与本地化](#7-存档设置音频与本地化)
- [8. 编辑器 Dock](#8-编辑器-dock)

---

## 1. 安装与启动

1. 将 **`gdframe.zip`** 解压到工程根，或把本仓库 **`addons/gdframe/`** 复制到工程的 **`addons/gdframe/`**。
2. 打开 **项目 → 项目设置 → 插件**，启用 **GDFrame**。
3. 首次启用会在 **`res://gdframe_project/`** 自动生成工程目录与 `GDFrameConstants`；之后即可使用 `GDFrame` / `GDFrameConstants`。

要求 **Godot 4.7+**。

```gdscript
func _ready() -> void:
	# 业务 signal 须在 gdframe_signals.gd 中声明
	GDFrame.signal_example.connect(_on_example)
	await GDFrame.ui.preload_ui(GDFrameConstants.UI_EXAMPLE)
	GDFrame.ui.open(GDFrameConstants.UI_EXAMPLE)
```

---

## 2. 全局 API 总览

业务经服务对象调用（如 `GDFrame.ui.open`、`GDFrame.audio.play_bgm`）：

| 服务 | 职责 |
|------|------|
| `signal_*` | 业务/框架信号（`GDFrame` 继承声明，直接用 `.connect` / `.emit`） |
| `ui` | UI 预加载、打开/关闭 |
| `input` | 输入设备跟踪 |
| `save` | 玩家档案（profile）读写 |
| `settings` | 窗口、垂直同步、语言（持久化到档案） |
| `audio` | 总线音量、BGM / SFX；流总线生成 `play_bgs` 等 |
| `pause` | 游戏暂停栈（`get_tree().paused` + 音频暂停） |
| `ext_*` | 扩展服务槽位（安装扩展后挂载） |

在 Dock **扩展管理 → 生成扩展 API** 后，`GDFrame` 会挂上各扩展的强类型服务槽位（`GDFrame.example` 等，由 `ext_service_type()` 决定）；总览见 [GDFrame Ext](https://github.com/ftyu3d/gdframe-ext)（[Gitee](https://gitee.com/ftyu3d/gdframe-ext)），各模块 API 见 `addons/gdframe_<id>/editor/README.md`。

**约定**：经 Autoload **`GDFrame`** 调用；类型注解用 **`GDFrameRoot`**；扩展能力用 **`GDFrame.<模块>.方法()`**（如 `GDFrame.example.ping()`）；模块注册用 **`ext_register`**（见 [§3](#3-工程目录)）；业务 signal 写在 `gdframe_signals.gd`；UI 标识用 **`GDFrameConstants`**；配置见 **`config/config.tres`**。无服务槽位的扩展可使用独立 `class_name` API（由各扩展 README 说明）。流总线轨方法在 **`GDFrame.audio`** 上。

**生命周期**：启用后初始化存档、设置、音频与 UI 登记；UI 在首次 `GDFrame.ui.preload_ui` 时加载。改 profile 字段后须 `GDFrame.save.flush()` 写盘。对象池与状态机等扩展服务在安装对应扩展并 **生成扩展 API** 后于首次访问时加载（见下方「扩展服务槽位」）。

---

## 3. 工程目录

工程根目录为 **`GDFrameConfig.PROJECT_ROOT`**（默认 `res://gdframe_project/`）。首次启用插件会自动生成；业务脚本与资源请放在此目录，**不要**放进 `addons/gdframe/`。

| 路径 | 说明 |
|------|------|
| `generated/gdframe_constants.gd` | `GDFrameConstants`：`UI_*` |
| `generated/gdframe_result.gd` | `GDFrameResult`：存档等 API 的错误码与 `is_ok` / `is_error` |
| `generated/ext_slots.gd` | 已安装扩展挂到 `GDFrame` 上的强类型服务槽位（自动维护） |
| `generated/audio_channels.gd` | `GDFrameAudioChannels`（`GDFrame.audio`）。流总线生成 `play_bgs` 等；未安装时为空壳 |
| `gdframe_signals.gd` | 业务与扩展用全局信号（见 [§4](#4-全局信号)） |
| `profile_settings_data.gd` | 档案 `settings` 类型；含扩展字段的自动生成段 |
| `generated/profile_settings_defaults.gd` | 读档时扩展字段缺省补全（自动维护） |
| `dim.gd` / `dim.tscn` | 全屏遮罩场景与根脚本；缺失时重载插件自动生成 |
| `ext.gd` | 项目扩展层（继承槽位；仅手写跨服务编排） |
| `ui/` | UI 场景根目录（`ui_*.tscn`；对应 `GDFrameConfig.UI_ROOT_DIR`；首次创建 UI 时生成） |

可选扩展是独立插件，目录必须为 **`addons/gdframe_<id>/`**（含 `module.gd` 与 `plugin.cfg`）。更新核心 `addons/gdframe/` 不会覆盖它们。运行时扫描 `module.gd` 并 `register`；编辑器入口由各扩展自己的 `EditorPlugin` 提供。

在 Dock **扩展管理** 安装或增删扩展后，点 **生成扩展 API** 可同步服务槽位、错误码、profile 字段，以及扩展声明的 `generate_audio_channels()`（流总线的 `GDFrame.audio.play_bgs` 等）。未安装流总线时 `audio_channels.gd` 写回空壳。

### 扩展服务槽位 `ext_*`

`module.gd` 的 `register` 通过 `ext_register` 把运行时服务写入生成槽位；业务直调 `GDFrame.<模块>.方法()`（如 `GDFrame.example.ping()`）。未安装的扩展不要探测、不要调用。

| 方法 | 说明 |
|------|------|
| `ext_register(key, service)` | 注册并写入对应强类型槽位 |

```gdscript
# module.gd
gdframe.ext_register(&"example", svc)

# 业务（仅调用本工程已安装并生成槽位的扩展）
GDFrame.example.ping()
```

可选：`module.gd` 实现 `extra_bus_names() -> Array[StringName]` 声明额外音频总线（启动读档时创建并应用音量键）。流总线用 `generate_audio_channels()` 把轨方法写进 `GDFrame.audio`（如 `GDFrame.audio.play_bgs`）。Dock「流总线」页 **生成** 只写这一份；**生成扩展 API** 按已保存轨名写同一份。可参考扩展 [code]addons/gdframe_stream_bus/[/code]。

可选：`editor/module_editor.gd` 实现 `dock_tab() -> Dictionary`，向底部面板 **GDFrame** 注册页签：

```gdscript
static func dock_tab() -> Dictionary:
	return {
		"title": "流总线",
		"page": "res://addons/gdframe_stream_bus/editor/dock_page.gd",  # 须 extends Control
	}
```

未实现或返回空则不出现页签。

**`GDFrameConstants`**：在 **启用插件**、Dock **UI管理** 增删改，或点 **刷新列表 / 刷新** 后自动更新。用法示例：

```gdscript
GDFrame.ui.open(GDFrameConstants.UI_EXAMPLE)
```

**`GDFrameConfig`**（`config/config.tres`；路径常量见 `config.gd`）

**UI**

| 字段 | 默认 | 说明 |
|------|------|------|
| `ui_max_layer` | `2` | 见 [§5 图层与遮罩](#图层与遮罩) |

**Input**

| 字段 | 默认 | 说明 |
|------|------|------|
| `keyboard_nav_focus` | `false` | 仅影响键盘：`false` 时键盘不聚焦导航项（与鼠标/触屏相同）；`true` 时键盘可聚焦并显示环（与手柄相同）。鼠标/触屏始终不聚焦；手柄始终可聚焦并隐藏光标。触屏不强制隐藏系统光标 |

**Display**

| 字段 | 默认 | 说明 |
|------|------|------|
| `max_fps_options` | `0, 30, 60, 120` | 帧率上限可选项；`0` 不限制，放在第一项。不在列表中的档案值按不限制处理 |
| `default_display_mode` | `BORDERLESS` | 新建档案默认显示模式（检查器下拉）；Web 仅 `WINDOWED` / `BORDERLESS`，其余回退 `WINDOWED` |
| `min_window_size` | `1920×1080` | 窗口化分辨率下限。可用区放得下该尺寸时，更小的不进列表，已存的更小尺寸回退为默认窗口大小；放不下时列表仍按缩放档生成 |
| `window_size_scale_steps` | `0.9, 0.8, 0.75, 0.67, 0.5` | 相对可用区最大尺寸的缩放档；与最大适配尺寸一起构成推荐列表。空则仅最大适配尺寸 |
| `common_window_heights` | `360 … 2160` | 常见窗口高度；宽度按当前宽高比换算，超出可用区的不列入 |

**Save**

| 字段 | 默认 | 说明 |
|------|------|------|
| （无） | — | 档案固定存于 `user://gdframe/profile.tres` |

**Audio**

| 字段 | 默认 | 说明 |
|------|------|------|
| `audio_bgm_crossfade_sec` | `0.5` | BGM 换曲交叉淡入秒数；`0` = 硬切；`audio.play_bgm(..., {"crossfade_sec": -1})` 用此项 |
| `audio_bgm_fade_out_sec` | `0.0` | BGM 停止默认淡出；`audio.stop_bgm(-1)` 用此项；`0` = 立刻停 |
| `audio_sfx_pool_size` | `8` | 非空间 SFX 池大小；启动时创建 |
| `audio_sfx_spatial_pool_size` | `4` | 2D/3D 空间音效各自池大小；启动时创建 |
| `audio_sfx_max_per_bus` | `8` | 同总线 SFX 并发上限；`0` 不限制（仍受池大小约束） |
| `audio_sfx_max_per_key` | `4` | 同 `opts.key` 并发上限；`0` 不单独限制 |
| `audio_sfx_log_drops` | `false` | `true` 时限流丢弃输出日志（编辑器 `push_warning`，导出运行 `print`） |
| `audio_ui_polyphony` | `32` | `audio.play_ui_sfx` 复音上限；启动时创建 |

**Settings（运行时）**

窗口化「分辨率」列表由 [code]settings.window_size_options()[/code] 运行时生成：推荐列表（最大适配尺寸 + [code]window_size_scale_steps[/code]）再并入 [code]common_window_heights[/code] 与设计分辨率后去重。新建档案默认显示模式为 [code]default_display_mode[/code]（默认无边框全屏）；默认窗口化分辨率取推荐列表第二档。可用区放得下 [code]min_window_size[/code] 时，更小的尺寸不列入；放不下时仍保留各缩放档。宽高比：项目 [code]stretch/aspect=expand[/code] 时跟屏幕；否则跟设计分辨率（[code]viewport_*[/code]）。项目 [code]stretch/mode=disabled[/code]，窗口化时所选尺寸就是渲染分辨率，画面按该尺寸 1:1 绘制。设置界面在窗口化时以实际窗口尺寸为准，未在预设中的尺寸显示为「自定义」，保存后写入档案。非窗口化时下拉锁定，只显示当前画面尺寸，不改窗口化分辨率；全屏、最大化时视口跟着当前窗口，回到窗口化再恢复所选分辨率。换屏不自动改写存档。桌面冷启动不写 [code]override.cfg[/code]：窗口保持项目里的无边框固定尺寸，直到游戏调用 [code]settings.apply_startup_window()[/code]：先把窗口改到档案中的尺寸，再关掉无边框标志。进入全屏前会先把窗口摆到档案中的窗口化尺寸，离开全屏时按该尺寸恢复。客户区不会写成与屏幕完全相同，避免 Windows 把窗口化误判为独占全屏。Web 导出只提供窗口化与无边框全屏，界面分别显示为「页面内」和「全屏」；新建档案与桌面相同，取 [code]default_display_mode[/code]；最大化、独占全屏、分辨率、垂直同步不显示，也不读写、不调用对应引擎接口。帧率上限选项为 [code]max_fps_options[/code]（[code]Engine.max_fps[/code]，[code]0[/code] 不限制；不在列表中的档案值按不限制处理），桌面、Android 与 Web 都写入档案并生效；垂直同步在桌面与 Android 读写并生效，开启时实际帧率仍不会超过显示器刷新率。Android 不提供屏幕显示与分辨率：这两项不显示，不读写，也不调用窗口模式、尺寸与位置接口。浏览器全屏只能在玩家点击或按键时进入，启动阶段只记下选择，等下一次输入再申请。

语言列表来自 [code]TranslationServer.get_loaded_locales()[/code]（[code]project.godot[/code] → [code]locale/translations[/code]）。在 Dock **通用 → 初始化本地化 CSV** 可生成含 [code]LOCALE_NAME[/code]、设置界面、通用提示与 [code]ERR_SAVE_*[/code] 等框架内置键的本地化 CSV（[code]res://locale/localization.csv[/code]）、导入翻译并注册到 [code]project.godot[/code]；业务及已安装扩展的文案键须在 CSV 中自行追加。

**池与限流**：三池物理上限 ≈ `audio_sfx_pool_size + audio_sfx_spatial_pool_size × 2`；`max_per_bus` 大于该值时启动 `push_warning`。

---

## 4. 全局信号

### 框架信号

| 信号 | 说明 |
|------|------|
| `signal_gdframe_input_device_changed(device_kind, device_id, is_emulated)` | 当前输入设备变化（类型见 `GDFrameInputEventDevice.DeviceKind`） |
| `signal_gdframe_locale_changed(locale)` | 语言切换后广播 |
| `signal_gdframe_profile_saved(error)` | `save.flush()` 完成；`GDFrameResult.is_ok(error)` 为成功 |
| `signal_gdframe_profile_startup_fallback()` | 启动时 profile 无法解析，已回退默认档案 |
| `signal_gdframe_bgm_changed(stream)` | BGM 逻辑曲目变更（`audio.stop_bgm` 后为 `null`） |
| `signal_gdframe_pause_changed(is_paused, depth)` | 暂停栈激活状态或深度变化 |
| `signal_gdframe_audio_paused(paused)` | `audio.set_paused` 时发出（`GDFrameExtStreamService` 入树连接） |

扩展模块可追加更多 `signal_*`（安装扩展并 **生成扩展 API** 后写入 `gdframe_signals.gd`）。

### 业务信号

在 **`res://gdframe_project/gdframe_signals.gd`** 的 **`# --- 业务自定义信号（可编辑）---`** 段声明，例如：

```gdscript
signal signal_example(example_id: int)
```

Dock → **通用** → **打开信号脚本** 可定位该文件。

### 存档操作结果（弹窗 / 多语言）

`save.flush`、`save.flush_async`、`save.delete_profile_from_disk` 返回 **`StringName`**：成功为 **`GDFrameResult.OK`**（空串 `&""`），失败为 **`GDFrameResult.ERR_SAVE_*`**，提示用 **`tr(String(err))`**。

判断成功用 `GDFrameResult.is_ok(err)`，勿写 `err == GDFrameResult.OK`（空 `StringName` 在部分环境下不可靠）。

```gdscript
var err: StringName = GDFrame.save.flush()
# 需等待 UI 时：err = await GDFrame.save.flush_async()
if GDFrameResult.is_error(err):
	show_tip(tr(String(err)))
```

| 成员 | 典型触发 |
|------|----------|
| `GDFrameResult.OK` | 成功（空 `StringName`） |
| `GDFrameResult.is_ok(err)` / `is_error(err)` | 判断是否成功/失败 |
| `ERR_SAVE_WRITE_FAILED` | `save.flush` / `save.flush_async` 磁盘写入失败 |
| `ERR_SAVE_PROFILE_READ_FAILED` | 启动时 profile 损坏已回退默认档案（`save.startup_profile_fallback()`） |
| `ERR_SAVE_CORRUPTED` | profile 损坏且无可用备份（`save.startup_recovery_error`） |
| `ERR_SAVE_DELETE_FAILED` | 删 profile 时磁盘删除失败 |

请在项目本地化 CSV 中为上述 `ERR_SAVE_*` 配置译文。

---

## 5. UI 管理 `ui`

UI 放在 **`GDFrameConfig.UI_ROOT_DIR`**（含子目录），场景名 **`ui_*.tscn`**，根脚本 **`extends GDFrameUIBase`**（推荐 Dock 创建）。启动时自动扫描登记；首次 `ui.preload_ui` 时才 `load`（`ui.open` 须先预加载）。标识用 **`GDFrameConstants.UI_*`**。

业务 UI 与风格复查见 Cursor Skills（`editor/skills/`，启用时同步到 `.cursor/skills/`）：**gdframe-ui**、**gdframe-framework**（通用书写规范）。改 `addons/gdframe` 或扩展时另见 **gdframe-addon**。

### 图层与遮罩

层编号从 **0** 起，与 `ui.open(ui_id, data, layer)` 的 `layer` 一致。`ui_max_layer` 在 **`config.tres`** 与 Dock **通用** 编辑（检查器字段同名）；dim 不占层槽。

| 配置 | 位置 | 作用 |
|------|------|------|
| `ui_max_layer` | `config.tres` / Dock **通用** | 工程最高可用层（如 `2` → layer_0～layer_2） |
| `ui_default_layer` | UI 场景根 **GDFrame** / Dock **UI管理** | `layer=-1` 时该 UI 的默认层 |
| `ui_use_dim` | 同上 | 打开时是否显示全屏 dim |
| `ui_nav_participates` | 同上 | 是否进入打开栈并参与导航（锁定下层、还焦）；为 `false` 时永不进栈，不受 `ui.close_top` / Esc 栈遍历影响 |
| `resolve_use_dim(data)` | UI 脚本 override | 按次覆盖遮罩：`null` 用 `ui_use_dim` |

### 打开 / 关闭流程

1. **`await ui.preload_ui(ui_id)`** — 实例化（隐藏）、执行 `_on_init`（可为协程）。
2. **`ui.open(ui_id, data)`** — **同步**打开；须先预加载，否则 `push_error` 并返回 `null`。
3. **`ui.close(ui_id, cache)`** — 关闭；`cache=true`（默认）仅隐藏并保留缓存。

**`cache=false`**：会 `queue_free` 并从缓存移除，之后须重新 **`await ui.preload_ui`**。

| 方法 | 说明 |
|------|------|
| `ui.preload_ui(ui_id)` | 预加载（**须 `await`**）；挂到场景 `ui_default_layer`；并发同一 `ui_id` 时等待首次 `_on_init` |
| `ui.open(ui_id, data, layer)` | 同步打开；`layer=-1` 用 `ui_default_layer`；**已打开**时刷新 `_on_show`；仅 `ui_nav_participates` 时升栈至顶 |
| `ui.is_preloaded(ui_id)` | 是否已完成预加载 |
| `ui.get_cached(ui_id)` | 取缓存实例（未打开也可） |
| `ui.close(ui_id, cache)` | 关闭；未缓存/不存在时 `push_error` 并返回 `false`；`_on_close()` 返回 `false` 时拒绝关闭（不报错） |
| `ui.close_top()` | 关闭打开栈栈顶；栈空时 `push_error` 并返回 `false` |
| `ui.open_replace(close_id, open_id, data, layer)` | 关闭 `close_id` 并打开 `open_id`；关闭后者时自动重新打开前者并恢复聚焦。**两者均须已预加载**；若 `open_id` 打开失败会尝试重新打开 `close_id` |
| `ui.is_open(ui_id)` | 是否正在显示 |
| `ui.is_cached(ui_id)` | 是否已有缓存实例 |
| `ui.get_ui_id(ui)` | 已缓存 UI 实例对应的 `ui_id`（如 Esc 关闭、自定义逻辑） |
| `ui.nav_refresh()` / `ui.get_active_ui()` | 手动刷新导航 / 当前活跃面板 |

### `ui.open` 的 `data` 键（`GDFrameUINav`）

| 键 | 说明 |
|----|------|
| `nav_from` | 打开子 UI 前记录触发控件，关闭后还焦 |
| `nav_restore_last` | 为 `true` 时聚焦上次离开时的项 |
| `nav_focus` | 指定要聚焦的 `Control` |

### UI 脚本钩子（`GDFrameUIBase`）

| 名称 | 说明 |
|------|------|
| `ui_default_layer` / `ui_use_dim` / `ui_nav_participates` / `resolve_use_dim` | 见 [图层与遮罩](#图层与遮罩) |
| `_on_init()` | 首次预加载；内部可 `await` |
| `_on_show(data)` | 每次 `ui.open` 之后 |
| `_on_close() -> bool` | 每次 `ui.close` 之前；返回 `false` 拦截关闭 |
| `_on_locale_changed()` | 语言切换后（所有已打开且可见的 UI） |

**导航（`GDFrameUIBase` 子类）**

| 名称 | 说明 |
|------|------|
| `ui_nav_set_items(items)` | 注册方向键导航列表（`Array[Control]`） |
| `ui_nav_wraps()` | 列表首尾是否循环（默认 `true`） |
| `ui_nav_uses_horizontal()` | 是否响应左右键（默认 `false`） |
| `ui_nav_auto_focus_on_show()` | `ui.open` 后是否自动聚焦（默认 `true`） |
| `ui_nav_set_items_input_enabled(enabled)` | 批量开关导航项输入 |
| `ui_closes_on_cancel()` | 是否响应 Esc（`ui_cancel`）关闭；框架从栈顶向下找第一个返回 `true` 的 UI |
| `ui_cancel_close()` | Esc 关闭行为（默认 `GDFrame.ui.close`） |
| `ui_nav_focus_on_show(data)` | 手动或自动初始聚焦 |
| `ui_nav_apply_focus_by_path(path)` | 按节点路径还焦（关闭弹窗） |

**`GDFrameUINav` 辅助**（列表 wiring，可在 `_on_init` 调用）：

| 方法 | 说明 |
|------|------|
| `link_vertical_controls(controls)` | 上下邻居 |
| `link_horizontal_controls(controls)` | 左右邻居 |

**`visible` 由框架统一管理**，UI 脚本请勿自行切换根节点可见性。

允许导航聚焦时（手柄，或 `keyboard_nav_focus` 打开后的键盘）：框架 Autoload **自动**处理方向键与 `ui_accept`；切到这类设备时按上次记录的导航项聚焦。鼠标/触屏不聚焦导航项。`_on_close()` 返回 `false` 可拦截关闭。

---

## 6. 输入 `input`

与 Godot [InputEvent](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html) 子类对齐；设备分类见 **`GDFrameInputEventDevice`**。

### 设备类型 `GDFrameInputEventDevice.DeviceKind`

| 枚举 | 对应 Godot 事件 |
|------|-----------------|
| `KEYBOARD` | `InputEventKey` |
| `MOUSE` | `InputEventMouseButton` / `InputEventMouseMotion` |
| `JOYPAD` | `InputEventJoypadButton` / `InputEventJoypadMotion` |
| `TOUCHSCREEN` | `InputEventScreenTouch` / `InputEventScreenDrag` |
| `UNKNOWN` | 未纳入跟踪的物理输入及非物理事件（如 `InputEventAction`） |

### 查询

| 方法 | 说明 |
|------|------|
| `input.get_device_kind()` | 当前设备类型 |
| `input.get_device_id()` | 最近一次事件的 `InputEvent.device`（如手柄索引） |
| `input.is_using_gamepad()` | 当前是否为 Joypad |
| `input.is_using_pointer()` | 当前是否为鼠标 / 触屏 |
| `input.was_last_event_emulated()` | 是否为 Godot 模拟输入（`DEVICE_ID_EMULATION`） |
| `input.should_hide_cursor(device_kind)` | 切换至该设备时是否应隐藏鼠标（读 `keyboard_nav_focus`） |
| `input.should_allow_nav_focus()` | 当前设备是否允许给导航项抢 GUI 焦点（见 `keyboard_nav_focus`） |

设备切换时按上表刷新 `Input.mouse_mode` 与导航项 `focus_mode`。不允许聚焦时导航项为 `FOCUS_NONE`，不抢焦点、不画环。真实鼠标移动会切到鼠标并显示光标；触屏模拟的鼠标移动（`InputEvent.device` 为 `DEVICE_ID_EMULATION`）不切换。

---

## 7. 存档、设置、音频与本地化

框架自身只维护一份玩家档案，路径固定为 `user://gdframe/profile.tres`（`GDFrameSaveManager.USER_ROOT_URL` + `PROFILE_FILE`）。业务存档的格式、目录、数量全部由业务决定，框架不定义。

档案 **`GDFrameProfileResource`** 含 **`settings`**（运行时统一为 **`GDFrameProfileSettingsData`**，见 `profile_settings_data.gd`；插件基类为 `GDFrameSettingsData`）。改设置/音量用 `GDFrame.settings` / `GDFrame.audio`，持久化用 `GDFrame.save.flush()`；直接改 `save.get_profile()` 只影响内存。

### 档案恢复

- **启动时**自动检查并恢复 profile；`save.startup_recovery_error()` 可取结果（损坏档常为 `ERR_SAVE_CORRUPTED`）。
- 写入中断时框架会尝试从临时文件恢复；仍失败则返回 `ERR_SAVE_WRITE_FAILED`。profile 损坏且无可用备份时返回 `ERR_SAVE_CORRUPTED`（见下，玩家确认后删档）。

### 损坏存档（玩家确认后删除）

启动后检查 `save.startup_recovery_error()`：

```gdscript
func _check_startup_saves() -> void:
	var err: StringName = GDFrame.save.startup_recovery_error()
	if err == GDFrameResult.ERR_SAVE_CORRUPTED:
		_show_corrupt_delete_dialog(
			func () -> void: GDFrame.save.delete_profile_from_disk()
		)
		return
	if not GDFrameResult.is_ok(err):
		show_error_dialog(tr(String(err)))
```

profile 损坏：`save.delete_profile_from_disk()`。

### 业务注意

- 写档前若遇临时文件残留，框架会自动尝试 recover；仍失败则返回 `ERR_SAVE_WRITE_FAILED`，可先 `save.recover_all_pending_saves()` 再重试。
- profile 由框架统一管理，业务只读 `save.get_profile()` 改字段并 `save.flush()`。

### 写入失败

返回 `ERR_SAVE_WRITE_FAILED`，不自动重试；重试前先 `save.recover_all_pending_saves()`。

### 业务存档：原子写 `GDFrameSaveIO`

框架**不定义**业务存档的格式、目录、槽位或数量。需要「写到一半断电也不毁档」时，把任意路径交给 `GDFrameSaveIO`：

```gdscript
const SAVE_PATH: String = "user://saves/world/w1.sav"

# 启动时修一次（每条业务存档路径一次即可）
GDFrameSaveIO.recover(SAVE_PATH)

# 写：内部 .tmp → .bak → rename 提交；失败时旧档保持完好
var err: StringName = GDFrameSaveIO.write_text(SAVE_PATH, "\n".join(lines))
if GDFrameResult.is_error(err):
	show_tip(tr(String(err)))

# 二进制用同签名：GDFrameSaveIO.write_bytes(SAVE_PATH, bytes)
```

- 不假设内容是 `Resource`、JSON 还是自定义文本；不建目录以外的结构，不维护索引
- 目录不存在会自动创建；不调用就没有任何开销
- 写成功即返回 `GDFrameResult.OK`；返回错误时磁盘上仍是上一份完整内容

### 错误码说明

存档相关 API 通过 **`GDFrameResult`** 返回结果，适合用 `tr(String(err))` 提示玩家。其它子系统（UI、音频等）误用时多在输出面板打印日志，并返回 `null` / `false`。

### `save`

| 方法 | 说明 |
|------|------|
| `save.setup()` | 初始化存档子系统（无参） |
| `save.startup_recovery_error()` | 启动时恢复结果（含 `ERR_SAVE_CORRUPTED`） |
| `save.startup_profile_fallback()` | 启动时 profile 存在但无法解析，已回退默认档案 |
| `save.delete_profile_from_disk()` | 玩家确认后删除 profile 文件 |
| `save.recover_all_pending_saves()` | 手动再次全量恢复 profile |
| `save.get_profile()` | 内存档案；改字段后请 `save.flush()` |
| `save.flush()` | 写盘；返回操作结果；触发 `signal_gdframe_profile_saved` |
| `save.flush_async()` | 协程写 profile（让出一帧后落盘）；可先显示等待 UI 再据返回值提示 |

业务存档（进度、世界数据等）不走 `save`，用 `GDFrameSaveIO` 原子写任意路径，见第 7 节。

### `settings`

| 方法 | 说明 |
|------|------|
| `settings.get_display_mode` / `set_display_mode` | 显示模式：`windowed` / `maximized` / `borderless` / `exclusive` |
| `GDFrameSettingsManager.display_mode_options()` | 设置界面显示模式下拉项（`key` 翻译键 + `mode` 取值） |
| `GDFrameSettingsManager.is_windowed_display_mode(mode)` | 是否窗口化（可设分辨率） |
| `settings.get_window_size` / `set_window_size` | 窗口化分辨率（像素）；拉伸关闭，与渲染分辨率一致 |
| `GDFrameSettingsManager.window_size_options()` | 可选分辨率（可用区上限；档位见 `config.tres`；`expand` 跟屏幕比，否则跟设计分辨率比） |
| `GDFrameSettingsManager.window_size_aspect()` | 窗口尺寸列表所用宽高比 |
| `settings.is_vsync_enabled` / `set_vsync_enabled` | 垂直同步 |
| `settings.get_max_fps` / `set_max_fps` | 帧率上限；[code]0[/code] 不限制 |
| `GDFrameSettingsManager.max_fps_options()` | 帧率上限可选项（`config.tres` 的 `max_fps_options`） |
| `settings.preview_display` / `settings.preview_vsync` / `settings.preview_max_fps` | 预览（不写盘） |
| `settings.get_locale` / `set_locale` / `preview_locale` | 语言；`automatic` + 项目已加载 locale |
| `GDFrameSettingsManager.locale_options()` | 设置界面语言下拉（含 `automatic`） |
| `GDFrameSettingsManager.locale_display_name(code)` | 语言项显示名（`automatic` + CSV `LOCALE_NAME`） |
| `settings.apply()` | 按当前内存档案重新应用到引擎（含窗口/语言与**总线音量/静音**；预览取消时调用） |
| `settings.default_snapshot()` | 默认设置字典（`display_mode`、窗口尺寸、vsync、`max_fps`、`locale`、`bus_linear`、`bus_muted`）；**不含** `profile_settings_data.gd` 扩展 `@export`——扩展项读 `profile_settings_data.gd` 或 `GDFrameProfileSettingsDefaults.apply` 补全后的值，或 `GDFrame.<模块>` 服务 API |

### `pause`

| 方法 | 说明 |
|------|------|
| `pause.push(reason)` | 压入一层暂停（同 reason 可嵌套计数）；栈空→非空时同步 `get_tree().paused` 与 `audio.set_paused` |
| `pause.pop(reason)` | 弹出一层 reason；栈仍非空则保持暂停 |
| `pause.clear(reason="")` | 清空栈；`reason` 非空时仅移除该 reason 的全部计数 |
| `pause.is_active()` | 暂停栈是否非空 |
| `pause.depth()` | 栈总深度（各 reason 计数之和） |
| `signal_gdframe_pause_changed(is_paused, depth)` | 暂停激活状态或深度变化时广播 |

`pause` 控制 `get_tree().paused`；`ui.open` 的 suspend + dim 隔离多层 UI 输入。

### `audio`

| 方法 | 说明 |
|------|------|
| `audio.set_bus_volume_linear` / `get_bus_volume_linear` | 总线音量 0～1，写入档案（静音时听感为 0，档案仍保留滑块值） |
| `audio.set_bus_muted` / `get_bus_muted` | 总线静音开关，写入档案 |
| `audio.preview_bus_effective(bus, linear, muted)` | 预览听感音量（muted 时传 0） |
| `audio.apply_from_profile()` | 按档案重放各总线音量（核心 + 扩展 `extra_bus_names()`） |
| `audio.get_root()` | 音频子系统根节点（`GDFrameAudioRoot`；BGM/SFX 与扩展播放器挂载于此） |
| `audio.play_bgm(stream, opts)` | BGM；opts：`loop`、`from_position`、`crossfade_sec`、`pitch_scale`、`loop_start_sec`、`loop_end_sec` |
| `audio.await_play_bgm(stream, opts)` | 同 play，可 `await` 交叉淡入结束（同曲跳过 / 无淡入则立即返回） |
| `audio.stop_bgm(fade_out_sec)` | 仅发起停止（不等待）；`0` 立刻停；`>0` 淡出；`-1` 用 config 默认 |
| `audio.await_stop_bgm(fade_out_sec)` | 同 stop，可 `await` 淡出结束 |
| `audio.preload_stream(stream, opts)` | 预加载并缓存 stream 副本（`loop` / WAV A～B），减轻首次播放卡顿 |
| `audio.get_bgm_stream()` | 当前 BGM stream（`stop` 后为 `null`） |
| `audio.has_bgm_loop_region()` | 当前 BGM 是否配置了循环区间 |
| `audio.is_bgm_playing()` / `audio.get_bgm_playback_position()` / `audio.get_bgm_pitch_scale()` | BGM 状态查询 |
| `audio.set_bgm_pitch_scale` / `tween_bgm_pitch_scale` | 仅 **active** 曲目 pitch；`tween_*` 只发起过渡，`await_tween_*` 可等待结束 |
| `audio.get_bgm_volume_linear` / `set_bgm_volume_linear` / `tween_bgm_volume_linear` | BGM 播放器音量 `0~1`（不存档）；**BGM 淡入淡出 tween 运行中 set/tween 忽略** |
| `audio.set_paused` / `audio.is_paused` | 暂停 / 恢复 BGM、SFX（发出 `signal_gdframe_audio_paused`）；暂停期间 `play_bgm` / `play_sfx*` 不启动新播；`play_ui_sfx` 不受影响 |
| `audio.play_ui_sfx(stream, opts) -> bool` | 界面音效（Polyphonic，走 [code]UI[/code] 总线；不受 [code]audio.set_paused[/code]）；opts：[code]volume_linear[/code]、[code]pitch_scale[/code]、[code]from_position[/code] |
| `audio.play_sfx(stream, bus=&"SFX", opts) -> bool` | 游戏特效 / 非空间 SFX；限流丢弃时返回 `false` |
| `audio.play_sfx_2d(stream, position, bus=&"SFX", opts) -> bool` | 2D 空间音效（`AudioStreamPlayer2D` 池） |
| `audio.play_sfx_3d(stream, position, bus=&"SFX", opts) -> bool` | 3D 空间音效（`AudioStreamPlayer3D` 池） |
| `audio.stop_all_sfx()` | 停止 SFX 池内全部播放（不含界面 Polyphonic） |
| `audio.stop_all_ui_sfx()` | 停止全部界面音效 |
| `audio.stop_sfx_by_key(key)` | 停止指定 key 的 SFX |
| `audio.stop_sfx_on_bus(bus_name)` | 停止 SFX 池内指定总线上的播放（不含 [code]UI[/code] Polyphonic） |
| `audio.set_sfx_max_per_bus(bus_name, max_count)` | 某总线 SFX 并发上限；`0` 不限制 |
| `audio.set_sfx_max_per_key(max_count)` | 同一 key SFX 并发上限；`0` 不单独限制 |

**整曲 loop**：opts 中 `loop=true`（默认）为 Ogg / MP3 / WAV 生成可循环副本（Ogg/MP3/WAV 整曲；WAV 亦支持原生 `loop_mode`）。

**A～B 区间 loop**：WAV 写入 `loop_begin` / `loop_end` 采样点并由引擎循环。Ogg / MP3 无区间字段，指定 A～B 时只播一遍（编辑器 `push_warning`）；需区间循环请用 WAV 或预拼曲。

**总线**：框架内置 **Master / Music / UI / SFX**。扩展模块可通过 `extra_bus_names()` 追加总线（读档时创建并应用）。**总线只负责音量/静音路由**；流总线生成后用 `GDFrame.audio.play_bgs` 等，一次性走 `audio.play_sfx` / `audio.play_ui_sfx`。

| 形态 | API | 总线 |
|------|-----|------|
| 主 BGM（持续） | `audio.play_bgm` | 固定 `Music` |
| 扩展持续音 | `GDFrame.audio.play_bgs` 等 | 扩展 `extra_bus_names()` |
| 一次性 | `audio.play_sfx(stream, bus, …)` | 默认 `SFX`；亦可扩展总线如 `Voice` |
| 界面短音 | `audio.play_ui_sfx` | 固定 `UI` |

部分扩展服务在 **`audio.set_paused(true)` 期间不会启动新播放**；`audio.play_ui_sfx` 不受暂停拦截。

**`AudioStreamPolyphonic`（界面音效）**：框架在 `GDFrameAudioRoot/UI_SFX` 挂一个 `AudioStreamPlayer` + `AudioStreamPolyphonic`（复音上限见 [member GDFrameConfig.audio_ui_polyphony]），由 **`audio.play_ui_sfx`** 调用 `play_stream`。与 **`audio.play_sfx`** 系列对比如下：

| | `audio.play_sfx` 系列 | `audio.play_ui_sfx` |
|--|------------------------|---------------------|
| 播放器 | 池里多个 `AudioStreamPlayer(2D/3D)` | 单个 `UI_SFX` + Polyphonic |
| 总线 | 默认 `SFX`（第二参 `bus`） | 固定 `UI` |
| 并发控制 | bus/key 限流 + 池大小 | `audio_ui_polyphony` |
| 暂停 | 受 `audio.set_paused` 拦截 | **不受**拦截 |
| 空间定位 | 有 `play_sfx_2d/3d` | 无（界面短音） |
| 适合 | 游戏 SFX（脚步、受击等） | 界面短音（按钮、连点等） |

```gdscript
GDFrame.audio.play_ui_sfx(click_stream)
GDFrame.audio.play_ui_sfx(click_stream, {"volume_linear": 0.8, "pitch_scale": 1.05})
GDFrame.audio.play_sfx(hit_stream)                 # SFX
GDFrame.audio.play_bgs(ambience_stream)            # 流总线生成后
GDFrame.audio.play_voice(line_stream)              # 默认 Voice 轨
```

**SFX 限流**：`max_per_bus` / `max_per_key` 为 `0` 时不限；池满可能抢轨。限流丢弃时 `play_sfx*` 返回 `false`（池未初始化、`audio.set_paused(true)` 等也会返回 `false`）。`audio_sfx_log_drops` 为 `true` 时限流丢弃会打日志（编辑器 `push_warning`，导出运行 `print`）。

### 本地化

在项目 **本地化** 注册 CSV；`ERR_SAVE_*` 等错误 key 须配置译文。DLC 翻译用 Godot 标准 `TranslationServer.add_translation`；语言切换后订阅 `signal_gdframe_locale_changed` 或对相关 UI 调用 `_on_locale_changed`。

---

## 8. 编辑器 Dock

底部面板 **GDFrame**，侧栏页签：

| 页签 | 功能 |
|------|------|
| **通用** | `ui_max_layer`、`config.tres` 定位与同步、初始化本地化 CSV、外部编辑器下拉（VS Code / Cursor / CodeBuddy / TRAE，写入编辑器设置 `text_editor/external/exec_path`）打开仓库根或本工程、重置档案（删除 profile 文件）等 |
| **UI管理** | 创建 `ui_*`、模糊搜索列表、编辑层 / 遮罩 / 是否参与导航、定位 / 打开 / 更名 / 删除（运行中禁止写操作） |
| **设置项** | 隔行条纹列表：顶部一行「刷新 / 新建音轨 / 新建字段 / 生成音频」，每行「上移 / 下移 / 定位 / 删除」。内容为音轨（`gdframe_project/settings/*.cfg`，可增删与排序）与 `profile_settings_data.gd` 的 profile 字段（业务自定义段可删，自动生成段只读）；扩展 `settings_items()` / `profile_fields()` 声明的项标 `[模块]` 且只读 |
| **扩展管理** | 安装/更新可选扩展、创建扩展模块、**生成扩展 API** |
| **扩展页签** | 各扩展可选实现 [code]editor/module_editor.dock_tab()[/code]（返回 [code]{title, page}[/code]）时出现；挂在「扩展管理」与「更新」之间 |
| **更新** | 检查 GDFrame 版本并安装；点 **更新** 前会确认（跨系列提示可能有兼容性变化）。成功后**自动重载插件**（运行中须先停止再手动点 **重载插件**）。已有 `config/config.tres` 会保留工程配置不覆盖；`config.gd` 仍随版本更新 |

`keyboard_nav_focus`、音频池等其余项在 **`config.tres` 检查器**中编辑。
