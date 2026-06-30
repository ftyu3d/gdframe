# GDFrame

面向 Godot 的 GDScript 插件化运行时框架。启用插件后会自动注册全局单例 **`GDFrame`**（Autoload）。

## 目录

- [1. 安装与启动](#1-安装与启动)
- [2. 全局 API 总览](#2-全局-api-总览)
- [3. 工程契约目录](#3-工程契约目录)
- [4. 全局信号](#4-全局信号)
- [5. 对象池 `pool_*`](#5-对象池-pool_)
- [6. UI 管理 `ui_*`](#6-ui-管理-ui_)
- [7. 输入 `input_*`](#7-输入-input_)
- [8. 状态机 `fsm_*`](#8-状态机-fsm_)
- [9. 服务容器 `service_*`](#9-服务容器-service_)
- [10. 存档、设置、音频与本地化](#10-存档设置音频与本地化)
- [11. 编辑器 Dock](#11-编辑器-dock)

---

## 1. 安装与启动

1. 将 **`gdframe`** 插件目录放入项目的 **`addons/`** 下（即 `res://addons/gdframe/`）。
2. 打开 **项目 → 项目设置 → 插件**，启用 **GDFrame**。
3. 首次启用会在 **`res://gdframe/`** 自动生成工程契约与 `GDFrameConstants`；之后即可使用 `GDFrame` / `GDFrameConstants`。

```gdscript
func _ready() -> void:
	# 业务 signal 须在 gdframe_signals.gd 中声明
	GDFrame.signal_example.connect(_on_example)
	await GDFrame.ui_preload(GDFrameConstants.UI_EXAMPLE)
	GDFrame.ui_open(GDFrameConstants.UI_EXAMPLE)
```

---

## 2. 全局 API 总览

在脚本编辑器中输入下列前缀可快速过滤 `GDFrame` 方法：

| 前缀 | 职责 |
|------|------|
| `signal_*` | 业务/框架信号（`GDFrame` 继承声明，直接用 `.connect` / `.emit`） |
| `pool_*` | 对象池 |
| `ui_*` | UI 预加载、打开/关闭 |
| `input_*` | 输入设备跟踪（`input_get_device_kind` 等） |
| `fsm_*` | 状态机绑定与句柄 |
| `service_*` | 轻量服务定位器 |
| `save_*` | 用户目录档案与槽位 `Resource` |
| `settings_*` | 窗口、垂直同步、语言（持久化到档案） |
| `audio_*` | 总线音量、BGM / SFX 播放 |
| `game_*` / `pause_*` | 游戏暂停栈（`get_tree().paused` + 音频暂停） |

在 Dock **扩展管理 → 生成扩展 API** 后，`GDFrame` 会挂上各扩展模块的 facade 方法；总览见 [GDFrame Ext](https://github.com/ftyu3d/gdframe-ext)（[Gitee](https://gitee.com/ftyu3d/gdframe-ext)），各模块 API 见工程内 `ext/<id>/editor/README.md`。

**约定**：经 **`GDFrame`** 调用；业务 signal 写在 `gdframe_signals.gd`；UI/FSM 标识用 **`GDFrameConstants`**；配置见 **`config/config.tres`**。无 facade 的扩展可使用独立 `class_name` API（由各扩展 README 说明）。

**生命周期**：启用后初始化存档、设置、音频与 UI 登记；UI 在首次 `ui_preload` / `ui_open` 时加载；FSM 在首次调用 `fsm_*` 时加载。改 profile 字段后须 `save_flush()` 写盘；槽位由 `save_write_game_resource` 单独写盘。

---

## 3. 工程契约目录

契约根目录为 **`GDFrameConfig.PROJECT_CONTRACT_ROOT`**（默认 `res://gdframe/`）。首次启用插件会自动生成；业务脚本与资源请放在此目录，**不要**放进 `addons/gdframe/`。

| 路径 | 说明 |
|------|------|
| `generated/gdframe_constants.gd` | `GDFrameConstants`：`UI_*`、`FSM_*`、状态名 |
| `generated/gdframe_result.gd` | `GDFrameResult`：存档等 API 的错误码与 `is_ok` / `is_error` |
| `generated/facade_modules.gd` | 已安装扩展挂到 `GDFrame` 上的 facade 方法（自动维护） |
| `gdframe_signals.gd` | 业务与扩展用全局信号（见 [§4](#4-全局信号)） |
| `profile_settings_data.gd` | 档案 `settings` 类型；含扩展字段的自动生成段 |
| `generated/profile_settings_defaults.gd` | 读档时扩展字段缺省补全（自动维护） |
| `dim.gd` / `dim.tscn` | 全屏遮罩契约场景与根脚本；缺失时重载插件自动生成 |
| `ext/` | 可选扩展模块；总览见 [GDFrame Ext](https://github.com/ftyu3d/gdframe-ext)（[Gitee](https://gitee.com/ftyu3d/gdframe-ext)），各模块 API 见 `ext/<id>/editor/README.md` |

在 Dock **扩展管理** 安装或增删扩展后，点 **生成扩展 API** 可同步 facade、错误码与 profile 字段。

**`GDFrameConstants`**：在 **启用插件** 或 Dock **UI管理 / 状态机** 增删改 UI、FSM 后自动更新。用法示例：

```gdscript
GDFrame.ui_open(GDFrameConstants.UI_EXAMPLE)
GDFrame.fsm_bind(GDFrameConstants.FSM_EXAMPLE, GDFrameConstants.IDLE, self)
change_state(GDFrameConstants.RUN)  # GDFrameFsmState 子类内
```

**`GDFrameConfig`**（`config/config.tres`；路径常量见 `config.gd`）

**UI**

| 字段 | 默认 | 说明 |
|------|------|------|
| `ui_max_layer` | `2` | 见 [§6 图层与遮罩](#图层与遮罩) |

**Input**

| 字段 | 默认 | 说明 |
|------|------|------|
| `keyboard_gamepad` | `false` | 光标与 UI 导航聚焦环互斥。`false`：键盘≈鼠标；`true`：键盘≈手柄。手柄恒隐藏光标并显示聚焦环 |

**Save**

| 字段 | 默认 | 说明 |
|------|------|------|
| `save_file_format` | `TEXT` | `TEXT` → `.tres`（便于 diff）；`BINARY` → `.res`。Dock 切换格式会转换现有存档 |

**Audio**

| 字段 | 默认 | 说明 |
|------|------|------|
| `audio_bgm_crossfade_sec` | `0.5` | BGM 换曲交叉淡入秒数；`0` = 硬切；`audio_play_bgm(..., {"crossfade_sec": -1})` 用此项 |
| `audio_bgm_fade_out_sec` | `0.0` | BGM 停止默认淡出；`audio_stop_bgm(-1)` 用此项；`0` = 立刻停 |
| `audio_sfx_pool_size` | `8` | 非空间 SFX 池大小；启动时创建 |
| `audio_sfx_spatial_pool_size` | `4` | 2D/3D 空间音效各自池大小；启动时创建 |
| `audio_sfx_max_per_bus` | `8` | 同总线 SFX 并发上限；`0` 不限制（仍受池大小约束） |
| `audio_sfx_max_per_key` | `4` | 同 `opts.key` 并发上限；`0` 不单独限制 |
| `audio_sfx_log_drops` | `false` | `true` 时限流丢弃输出日志（编辑器 `push_warning`，导出运行 `print`） |
| `audio_ui_polyphony` | `32` | `audio_play_ui_sfx` 复音上限；启动时创建 |

**Settings（运行时）**

窗口化「窗口大小」列表由 [code]settings_window_size_options()[/code] 运行时生成：以当前参考屏幕可用区域为上限，按 100% / 90% / … 缩放及常见高度（720p、1080p 等，保持宽高比）去重；应用时 snap 到最近档位。**不会**因换屏自动改写存档。

语言列表来自 [code]TranslationServer.get_loaded_locales()[/code]（[code]project.godot[/code] → [code]locale/translations[/code]）。在 Dock **通用 → 初始化本地化 CSV** 可生成含 [code]LOCALE_NAME[/code]、设置界面、通用提示与 [code]ERR_SAVE_*[/code] 等框架内置键的本地化 CSV（[code]res://locale/localization.csv[/code]）、导入翻译并注册到 [code]project.godot[/code]；业务及已安装扩展的文案键须在 CSV 中自行追加。

**池与限流**：三池物理上限 ≈ `audio_sfx_pool_size + audio_sfx_spatial_pool_size × 2`；`max_per_bus` 大于该值时启动 `push_warning`。

---

## 4. 全局信号

### 框架信号

| 信号 | 说明 |
|------|------|
| `signal_gdframe_input_device_changed(device_kind, device_id, is_emulated)` | 当前输入设备变化（类型见 `GDFrameInputEventDevice.DeviceKind`） |
| `signal_gdframe_locale_changed(locale)` | 语言切换后广播 |
| `signal_gdframe_profile_saved(error)` | `save_flush()` 完成；`GDFrameResult.is_ok(error)` 为成功 |
| `signal_gdframe_profile_startup_fallback()` | 启动时 profile 无法解析，已回退默认档案 |
| `signal_gdframe_game_save_written(slot_id, error)` | 槽位存档写入完成 |
| `signal_gdframe_game_save_deleted(slot_id, error)` | 槽位存档删除完成 |
| `signal_gdframe_bgm_changed(stream)` | BGM 逻辑曲目变更（`audio_stop_bgm` 后为 `null`） |
| `signal_gdframe_pause_changed(is_paused, depth)` | 暂停栈激活状态或深度变化 |

扩展模块可追加更多 `signal_*`（安装扩展并 **生成扩展 API** 后写入 `gdframe_signals.gd`）。

### 业务信号

在 **`res://gdframe/gdframe_signals.gd`** 的 **`# --- 业务自定义信号（可编辑）---`** 段声明，例如：

```gdscript
signal signal_example(example_id: int)
```

Dock → **通用** → **打开信号脚本** 可定位该文件。

### 存档操作结果（弹窗 / 多语言）

`save_flush`、`save_write_game_resource`、`save_delete_game_slot` 返回 **`StringName`**：成功为 **`GDFrameResult.OK`**（空串 `&""`），失败为 **`GDFrameResult.ERR_SAVE_*`**，提示用 **`tr(String(err))`**。

判断成功用 `GDFrameResult.is_ok(err)`，勿写 `err == GDFrameResult.OK`（空 `StringName` 在部分环境下不可靠）。

```gdscript
var err: StringName = GDFrame.save_flush()
# 需等待 UI 时：err = await GDFrame.save_flush_async()
if GDFrameResult.is_error(err):
	show_tip(tr(String(err)))
```

| 成员 | 典型触发 |
|------|----------|
| `GDFrameResult.OK` | 成功（空 `StringName`） |
| `GDFrameResult.is_ok(err)` / `is_error(err)` | 判断是否成功/失败 |
| `ERR_SAVE_WRITE_FAILED` | `save_flush` / `save_write_game_resource` 磁盘写入失败 |
| `ERR_SAVE_SLOT_ID_INVALID` | 槽位 id 非法字符或为空 |
| `ERR_SAVE_SLOT_NOT_FOUND` | 读/删不存在的槽位 |
| `ERR_SAVE_READ_FAILED` | 槽位文件存在但 `ResourceLoader.load` 失败 |
| `ERR_SAVE_PROFILE_READ_FAILED` | 启动时 profile 损坏已回退默认档案（`save_startup_profile_fallback()`）；`save_reload()` 失败时保留当前内存档案 |
| `ERR_SAVE_CORRUPTED` | 主档损坏且无可用 sidecar（`save_startup_recovery_error`） |
| `ERR_SAVE_DELETE_FAILED` | 删 profile / 槽位时磁盘删除失败 |
| `ERR_SAVE_META_WRITE_FAILED` | `save_write_game_resource` 主档成功但 meta sidecar 写入失败；可 `save_rebuild_slot_meta_from_save` 修复 |
| `read_resource(result)` / `read_error(result)` | 解析 `save_read_game_resource` 返回字典 |

请在项目本地化 CSV 中为上述 `ERR_SAVE_*` 配置译文。

---

## 5. 对象池 `pool_*`

| 方法 | 说明 |
|------|------|
| `pool_scene(key, scene, warmup_count=0, max_idle, max_active) -> bool` | **PackedScene** 池；`warmup_count` 可选，默认 **0**（不预热）。**同 key 重注册时若仍有借出项则拒绝**（返回 `false`；池内 `push_error`） |
| `pool_factory(key, factory, warmup_count=0, max_idle, max_active) -> bool` | **Callable 工厂** 池；须能 `call()` 出新实例；`warmup_count` 默认 **0**。**同 key 重注册时若仍有借出项则拒绝**（返回 `false`） |
| `pool_set_limits(key, max_idle, max_active)` | `0` 表示不限制；**未注册 key** 时 `push_error` 并忽略 |
| `pool_get(key, parent)` | 取出实例；`Node` 可挂到 `parent`。**未注册 key** 时 `push_error` 并返回 `null`；**`max_active` 满**时 `push_warning` 并返回 `null`。调用方须判空 |
| `pool_recycle(key, item)` | 回收；继承 [code]GDFramePoolPooled[/code] 时调用 [code]on_pool_recycle[/code]。**未注册 key** 或 **错 key** 时 `push_error` 并忽略 |
| `pool_clear(key, free_nodes)` | 清空空闲列表；`free_nodes=true` 时释放空闲实例。**仍有 `pool_get` 借出项时拒绝**（返回 `false` 并 `push_error`），须先 `pool_recycle` |
| `pool_stats(key)` / `pool_stats_all()` | 统计字典；**未注册 key** 时 `push_error` 并返回 `{}` |

```gdscript
# 注册 + 预热；max_idle / max_active 为 0 时不限制
GDFrame.pool_scene(&"example_pool_key", EXAMPLE_SCENE, 10, 20, 50)
var item: Node2D = GDFrame.pool_get(&"example_pool_key", self) as Node2D
# … 使用完毕后
GDFrame.pool_recycle(&"example_pool_key", item)
```

运行中可在 Dock **对象池** 页签点 **刷新** 查看统计。

---

## 6. UI 管理 `ui_*`

UI 放在 **`GDFrameConfig.UI_ROOT_DIR`**（含子目录），场景名 **`ui_*.tscn`**，根脚本 **`extends GDFrameUIBase`**（推荐 Dock 创建）。启动时自动扫描登记；首次 `ui_preload` / `ui_open` 时才 `load`。标识用 **`GDFrameConstants.UI_*`**。

### 图层与遮罩

层编号从 **0** 起，与 `ui_open(ui_id, data, layer)` 的 `layer` 一致。`ui_max_layer` 在 **`config.tres`** 与 Dock **通用** 编辑（检查器字段同名）；dim 不占层槽。

| 配置 | 位置 | 作用 |
|------|------|------|
| `ui_max_layer` | `config.tres` / Dock **通用** | 工程最高可用层（如 `2` → layer_0～layer_2） |
| `ui_default_layer` | UI 场景根 **GDFrame** / Dock **UI管理** | `layer=-1` 时该 UI 的默认层 |
| `ui_use_dim` | 同上 | 打开时是否显示全屏 dim |
| `resolve_use_dim(data)` | UI 脚本 override | 按次覆盖遮罩：`null` 用 `ui_use_dim` |

### 打开 / 关闭流程

1. **`await ui_preload(ui_id)`** — 实例化（隐藏）、执行 `_on_init`（可为协程）。
2. **`ui_open(ui_id, data)`** — **同步**打开；须先预加载，否则 `push_error` 并返回 `null`。
3. **`ui_close(ui_id, cache)`** — 关闭；`cache=true`（默认）仅隐藏并保留缓存。

**`cache=false`**：会 `queue_free` 并从缓存移除，之后须重新 **`await ui_preload`**。

| 方法 | 说明 |
|------|------|
| `ui_preload(ui_id)` | 预加载（**须 `await`**）；挂到场景 `ui_default_layer`；并发同一 `ui_id` 时等待首次 `_on_init` |
| `ui_open(ui_id, data, layer)` | 同步打开；`layer=-1` 用 `ui_default_layer`；**已打开**时刷新 `_on_show` 并升栈至顶 |
| `ui_is_preloaded(ui_id)` | 是否已完成预加载 |
| `ui_get(ui_id)` | 取缓存实例（未打开也可） |
| `ui_close(ui_id, cache)` | 关闭；未缓存/不存在时 `push_error` 并返回 `false`；`_on_close()` 返回 `false` 时拒绝关闭（不报错） |
| `ui_close_top()` | 关闭打开栈栈顶；栈空时 `push_error` 并返回 `false` |
| `ui_open_replace(close_id, open_id, data, layer)` | 关闭 `close_id` 并打开 `open_id`；关闭后者时自动重新打开前者并恢复聚焦。**两者均须已预加载**；若 `open_id` 打开失败会尝试重新打开 `close_id` |
| `ui_is_open(ui_id)` | 是否正在显示 |
| `ui_is_cached(ui_id)` | 是否已有缓存实例 |
| `ui_get_id(ui)` | 已缓存 UI 实例对应的 `ui_id`（如 Esc 关闭、自定义逻辑） |
| `ui_nav_refresh()` / `ui_nav_get_active_ui()` | 手动刷新导航 / 当前活跃面板 |
| `ui_is_pause_open_blocked()` | Esc 刚关 UI 后短暂禁止误开其它 UI |

### `ui_open` 的 `data` 键（`GDFrameUINav`）

| 键 | 说明 |
|----|------|
| `nav_from` | 打开子 UI 前记录触发控件，关闭后还焦 |
| `nav_restore_last` | 为 `true` 时聚焦上次离开时的项 |
| `nav_focus` | 指定要聚焦的 `Control` |

### UI 脚本钩子（`GDFrameUIBase`）

| 名称 | 说明 |
|------|------|
| `ui_default_layer` / `ui_use_dim` / `resolve_use_dim` | 见 [图层与遮罩](#图层与遮罩) |
| `_on_init()` | 首次预加载（`gdframe_init()`）；可 `await` |
| `_on_show(data)` | 每次 `ui_open` 之后 |
| `_on_close() -> bool` | 每次 `ui_close` 之前；返回 `false` 拦截关闭 |
| `_on_locale_changed()` | 语言切换后（打开栈中且可见的 UI） |

**导航（`GDFrameUIBase` 子类）**

| 名称 | 说明 |
|------|------|
| `ui_nav_set_items(items)` | 注册方向键导航列表（`Array[Control]`） |
| `ui_nav_focus_policy()` | `GDFrameUINav.FocusPolicy.ANY` / `BUTTONS_ONLY` |
| `ui_nav_wraps()` | 列表首尾是否循环（默认 `true`） |
| `ui_nav_uses_horizontal()` | 是否响应左右键（默认 `false`） |
| `ui_nav_auto_focus_on_show()` | `ui_open` 后是否自动聚焦（默认 `true`） |
| `ui_nav_set_items_input_enabled(enabled)` | 批量开关导航项输入 |
| `ui_closes_on_cancel()` | 栈顶时是否响应 Esc（`ui_cancel`）关闭 |
| `ui_cancel_close()` | Esc 关闭行为（默认 `GDFrame.ui_close`） |
| `ui_nav_focus_init(data)` / `ui_nav_focus_on_show(data)` | 手动或自动初始聚焦 |
| `ui_nav_apply_focus_by_path(path)` | 按节点路径还焦（关闭弹窗） |

**`GDFrameUINav` 辅助**（列表 wiring，可在 `_on_init` 调用）：

| 方法 | 说明 |
|------|------|
| `link_vertical_controls(controls)` | 上下邻居 |
| `link_horizontal_controls(controls)` | 左右邻居 |
| `link_vertical_buttons(buttons)` | `BaseButton` 竖向链 |
| `link_horizontal_buttons(buttons)` | `BaseButton` 横向链 |

**`visible` 由框架统一管理**，UI 脚本请勿自行切换根节点可见性。

键盘/手柄：框架 Autoload **自动**处理 UI 方向键与 `ui_accept`（业务无需写输入回调）；切至键盘/手柄时刷新焦点。`_on_close()` 返回 `false` 可拦截关闭。

---

## 7. 输入 `input_*`

与 Godot [InputEvent](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html) 子类对齐；设备分类见 **`GDFrameInputEventDevice`**。

### 设备类型 `GDFrameInputEventDevice.DeviceKind`

| 枚举 | 对应 Godot 事件 |
|------|-----------------|
| `KEYBOARD` | `InputEventKey` |
| `MOUSE` | `InputEventMouseButton` / `InputEventMouseMotion` |
| `JOYPAD` | `InputEventJoypadButton` / `InputEventJoypadMotion` |
| `TOUCHSCREEN` | `InputEventScreenTouch` / `InputEventScreenDrag` |
| `GESTURE` | `InputEventMagnifyGesture` / `InputEventPanGesture` |
| `MIDI` | `InputEventMIDI` |
| `UNKNOWN` | `InputEventAction` 等非物理事件 |

### `GDFrame` API

| 方法 | 说明 |
|------|------|
| `input_get_device_kind()` | 当前设备类型 |
| `input_get_device_id()` | 最近一次事件的 `InputEvent.device`（如手柄索引） |
| `input_is_using_gamepad()` | 当前是否为 Joypad |
| `input_is_using_pointer()` | 当前是否为鼠标 / 触屏 |
| `input_was_last_device_event_emulated()` | 是否为 Godot 模拟输入（`DEVICE_ID_EMULATION`） |
| `input_should_hide_cursor(device_kind)` | 切换至该设备时是否应隐藏鼠标（读 `keyboard_gamepad`） |
| `input_should_show_focus_on_grab()` | 程序化聚焦是否显示 UI 导航选中框（与 `input_should_hide_cursor` 互斥） |

设备切换时按 `keyboard_gamepad` 切换 `Input.mouse_mode` 与 UI 导航聚焦环（二者互斥，见 [§6](#6-ui-管理-ui_)）。

---

## 8. 状态机 `fsm_*`

定义放在 **`GDFrameConfig.FSM_ROOT`** 下 `fsm_xxx/fsm_xxx_registry.gd`，状态脚本在同级 **`states/`**。状态脚本 **`extends GDFrameFsmState`**；用 **`change_state(GDFrameConstants.XXX)`** 切换。不用 FSM 的项目勿调用 `fsm_*`（子系统仅在首次调用时创建）。

```gdscript
GDFrame.fsm_preload(GDFrameConstants.FSM_EXAMPLE)

func _ready() -> void:
	GDFrame.fsm_bind(GDFrameConstants.FSM_EXAMPLE, GDFrameConstants.IDLE, self)

func _physics_process(delta: float) -> void:
	GDFrame.fsm_physics_process(self, delta)
```

**性能**：框架不会全局 tick 状态机；仅在已 `fsm_bind` 的宿主里调用 `fsm_process` / `fsm_physics_process` / `fsm_dispatch_input`。`fsm_preload_all()` 会加载 `FSM_ROOT` 下全部 Registry，状态机多时建议按需 `fsm_preload(machine_id)`。

| 方法 | 说明 |
|------|------|
| `fsm_preload(machine_id)` | 预加载 Registry |
| `fsm_preload_all()` | 预加载全部 Registry（状态机多时慎用） |
| `fsm_is_machine_loaded(machine_id)` | 是否已加载 Registry |
| `fsm_bind(machine_id, initial_state, owner)` | 绑定到 `owner`；返回 `GDFrameFsmHandle`。**同一 owner + machine_id 重复 bind 返回已有句柄**（忽略新的 `initial_state`，会 `push_warning`） |
| `fsm_process(owner, delta)` | 驱动状态的 `_process` |
| `fsm_physics_process(owner, delta)` | 驱动状态的 `_physics_process`（推荐） |
| `fsm_dispatch_input(owner, event)` | 将输入转发到当前状态 |
| `fsm_handle(owner, machine_id)` | 取已有句柄；未 bind 为 `null` |

`fsm_process` 与 `fsm_physics_process` 可单独或同时使用（与 Godot 节点一致）。**`fsm_dispatch_input` 须在宿主 `_input` / `_unhandled_input` 中手动调用**，框架不会自动转发输入。

宿主节点离开场景树或调用 `GDFrameFsmHandle.release()` 时，框架会对当前状态调用 `_exit()` 并清理句柄缓存。

**`machine_id` 与 Registry**

- 约定目录：`fsm_<name>/fsm_<name>_registry.gd`，状态脚本在同级 `states/`。
- `fsm_bind` / `GDFrameConstants.FSM_*` 使用的 id 以 Registry 中 **`machine_id()`** 为准（一般与目录名一致）。
- 在 Dock 增删状态机后，已 bind 的宿主须重新 `fsm_bind`。

---

## 9. 服务容器 `service_*`

| 方法 | 说明 |
|------|------|
| `service_register(key, service)` | 注册或覆盖 |
| `service_get(key)` | 获取；不存在为 `null` |
| `service_has(key)` | 是否已注册 |

---

## 10. 存档、设置、音频与本地化

用户存档由 `save_*` API 读写；磁盘路径用 `save_profile_disk_path()`、`save_slots_directory()` 等查询。

档案 **`GDFrameProfileResource`** 含 **`settings`**（运行时统一为 **`GDFrameProfileSettingsData`**，见 `profile_settings_data.gd`；插件基类为 `GDFrameSettingsData`）。改设置/音量用 `settings_set_*` / `audio_set_*`，持久化用 `save_flush()`；直接改 `save_get_profile()` 只影响内存。

### 存档格式与恢复

- **启动时**自动检查并恢复 profile、槽位与 meta；`save_startup_recovery_error()` 可取结果（损坏档常为 `ERR_SAVE_CORRUPTED`）。
- 写入中断时框架会尝试从临时文件恢复；仍失败则返回 `ERR_SAVE_WRITE_FAILED`。主档损坏且无可用备份摘要时返回 `ERR_SAVE_CORRUPTED`（见下，玩家确认后删档）。
- Dock 切换 `save_file_format` 会弹窗确认并将 `user://gdframe` 下现有存档转换为新格式。

### 损坏存档（玩家确认后删除）

启动后检查 `save_startup_recovery_error()`：

```gdscript
func _check_startup_saves() -> void:
	var err: StringName = GDFrame.save_startup_recovery_error()
	if err == GDFrameResult.ERR_SAVE_CORRUPTED:
		if GDFrame.save_startup_corrupt_profile():
			_show_corrupt_delete_dialog(
				func () -> void: GDFrame.save_delete_profile_from_disk()
			)
		for slot_id: String in GDFrame.save_startup_corrupt_slots():
			_show_corrupt_delete_dialog(
				func () -> void: GDFrame.save_delete_game_slot(slot_id)
			)
		return
	if not GDFrameResult.is_ok(err):
		show_error_dialog(tr(String(err)))
```

槽位损坏：`save_delete_game_slot`；profile 损坏：`save_delete_profile_from_disk()`。

### 业务注意

- 写档前若遇 sidecar 残留，框架会自动尝试 recover；仍失败则返回 `ERR_SAVE_WRITE_FAILED`，可先 `save_recover_game_slot` / `save_recover_all_pending()` 再重试。
- 写档过程中勿用 `save_has_game_slot` 刷新 UI。
- 槽位 Resource 类型由业务保证读写一致。

### 写入失败

返回 `ERR_SAVE_WRITE_FAILED` 或 `ERR_SAVE_META_WRITE_FAILED`（主档已写、摘要失败），不自动重试；重试前先 `save_recover_game_slot` / `save_recover_all_pending()`。meta 专项失败可 `save_rebuild_slot_meta_from_save`。

### 错误码说明

存档相关 API 通过 **`GDFrameResult`** 返回结果，适合用 `tr(String(err))` 提示玩家。其它子系统（UI、池、FSM、音频等）误用时多在输出面板打印日志，并返回 `null` / `false`。

### 槽位 meta（`GDFrameSlotMetaResource`）

展示字段经 `save_write_slot_meta` 写入 `slots/meta/`。`save_write_game_resource` 在存档 Resource 含 `slot_label` / `play_time_sec` / `chapter` / `thumbnail_path` 时会**自动写入 meta sidecar**（与手动 `save_write_slot_meta` 等价）；meta 失败时框架会尝试 `save_rebuild_slot_meta_from_save`，仍失败则返回 `ERR_SAVE_META_WRITE_FAILED`（主档已落盘）。`save_slot_summary` **只读 meta**（不整档读盘）；无存 meta sidecar 时用 `save_rebuild_slot_meta_from_save`。`save_list_slot_ids` 仅有正式档的槽；固定槽位 UI 须遍历业务 id。写入 `slot_label`，summary 键为 `label`。

**固定槽位**：遍历业务约定的槽位 id，用 `save_slot_summary` 的 `exists` / 展示字段。**动态列表**：`save_list_slot_ids()` + 各 id 的 `save_slot_summary`（列表不必 `save_read_game_resource` 整档）。

框架**不**内置「当前槽位」；业务自维护 `current_slot_id`，选档后 `save_read_game_resource`，存档后建议 `save_write_slot_meta`。

### `save_*`

| 方法 | 说明 |
|------|------|
| `save_startup_recovery_error()` | 启动时恢复结果（含 `ERR_SAVE_CORRUPTED`） |
| `save_startup_corrupt_profile()` | 启动损坏：profile 是否为坏档 |
| `save_startup_corrupt_slots()` | 启动损坏：坏档槽位 id 列表 |
| `save_startup_profile_fallback()` | 启动时 profile 存在但无法解析，已回退默认档案 |
| `save_delete_profile_from_disk()` | 玩家确认后删除 profile 文件 |
| `save_recover_all_pending()` | 手动再次全量恢复 profile + 全部槽位 |
| `save_recover_game_slot(slot_id)` | 仅恢复单槽 sidecar（写档重试前推荐） |
| `save_get_profile()` | 内存档案；改字段后请 `save_flush()` |
| `save_flush()` | 写盘；返回操作结果；触发 `signal_gdframe_profile_saved` |
| `save_flush_async()` | 协程写 profile（让出一帧后落盘）；可先显示等待 UI 再据返回值提示 |
| `save_reload()` | 从盘重载 profile，重做扩展缺字段默认与总线键，并重新应用到设置与音频；成功时清除 `save_startup_profile_fallback()`；失败时保留当前内存档案并返回 `ERR_SAVE_PROFILE_READ_FAILED`（**不**改 `save_startup_profile_fallback()`） |
| `save_profile_disk_path()` | profile 完整路径 |
| `save_has_profile()` | 磁盘上是否已有 profile 文件 |
| `save_write_game_resource(slot_id, res)` | 槽位存档；含展示字段时自动写 meta sidecar。主档与 meta 均成功返回 `OK`；meta 失败返回 `ERR_SAVE_META_WRITE_FAILED`（主档已落盘，可 `save_rebuild_slot_meta_from_save` 修复） |
| `save_read_game_resource(slot_id)` | 读取槽位；返回 `{ "resource", "error" }` |
| `save_has_game_slot(slot_id)` | 是否存在 |
| `save_delete_game_slot(slot_id)` | 删除槽位文件（含 `.tmp`/`.bak` 与同槽 meta）；返回操作结果；触发 `signal_gdframe_game_save_deleted` |
| `save_list_slot_ids()` | 磁盘上已有槽位 id 列表（已排序） |
| `save_slot_last_modified_unix(slot_id)` | 槽位存档最后修改时间（Unix 秒）；无存档为 `0` |
| `save_slot_summary(slot_id)` | 选档摘要（**仅读 meta sidecar**）：`exists`、`slot_id`、`modified_unix`、`label`、`play_time_sec`、`chapter`、`thumbnail_path` |
| `save_write_slot_meta(slot_id, meta)` | 写 `slots/meta/{id}.tres` / `.res` sidecar（`GDFrameSlotMetaResource`；原子写 + 启动/`save_recover_game_slot` 恢复） |
| `save_rebuild_slot_meta_from_save(slot_id)` | 从槽位存档提取展示字段并写 meta sidecar |
| `save_slots_directory()` | 槽位目录 |
| `save_slot_meta_directory()` | 槽位 meta 目录 |
| `save_file_extension()` | `".tres"` 或 `".res"` |

### `settings_*`

| 方法 | 说明 |
|------|------|
| `settings_get/set_display_mode` | 显示模式：`windowed` / `maximized` / `borderless` / `exclusive` |
| `settings_display_mode_options()` | 设置界面显示模式下拉项（`key` 翻译键 + `mode` 取值） |
| `settings_is_windowed_display_mode(mode?)` | 是否窗口化（仅该模式下窗口大小生效） |
| `settings_get/set_window_size` | 窗口化模式下的窗口尺寸（像素） |
| `settings_window_size_options()` | 可选窗口尺寸（主屏可用区域上限 + 比例/常见高度档位） |
| `settings_snap_window_size(size)` | 将尺寸 snap 到最近可选档位 |
| `settings_is/set_vsync_enabled` | 垂直同步 |
| `settings_preview_display` / `settings_preview_vsync` | 预览（不写盘） |
| `settings_get/set/preview_locale` | 语言；`automatic` + 项目已加载 locale |
| `settings_locale_options()` | 设置界面语言下拉（含 `automatic`） |
| `settings_locale_display_name(code)` | 语言项显示名（`automatic` + CSV `LOCALE_NAME`） |
| `settings_apply()` | 按当前内存档案重新应用到引擎（含窗口/语言与**总线音量/静音**；预览取消时调用） |
| `settings_default_snapshot()` | 默认设置字典（`display_mode`、窗口尺寸、vsync、`locale`、`bus_linear`、`bus_muted`）；**不含** `profile_settings_data.gd` 扩展 `@export`——扩展项读 `profile_settings_data.gd` 或 `GDFrameProfileSettingsDefaults.apply` 补全后的值，或扩展 facade API |

### `game_*` / `pause_*`

| 方法 | 说明 |
|------|------|
| `pause_push(reason)` | 压入一层暂停（同 reason 可嵌套计数）；栈空→非空时同步 `get_tree().paused` 与 `audio_set_paused` |
| `pause_pop(reason)` | 弹出一层 reason；栈仍非空则保持暂停 |
| `pause_pop_deferred(reason)` | 下一帧再 `pause_pop`（关闭 UI 等同帧还焦时） |
| `pause_clear(reason="")` | 清空栈；`reason` 非空时仅移除该 reason 的全部计数 |
| `pause_is_active()` | 暂停栈是否非空 |
| `pause_depth()` | 栈总深度（各 reason 计数之和） |
| `signal_gdframe_pause_changed(is_paused, depth)` | 暂停激活状态或深度变化时广播 |
| `game_set_paused(paused)` | 单层快捷：`true` = 仅在**当前未暂停**时 push `&"game_set_paused"`（已在暂停时 `true` 无效）；`false` = 仅 pop 该 reason（**不会**清空其它 `pause_push` 来源）；多层请用 `pause_push/pop` |
| `game_set_paused_deferred(paused)` | 下一帧再 `game_set_paused` |

**与 UI 的分工**：`pause_*` 管游戏世界是否暂停；`ui_open` 自带的 suspend + dim 管多层 UI 键盘/鼠标隔离；`ui_is_pause_open_blocked()` 管 Esc 刚关 UI 后短暂禁止误开其它 UI（与栈深度无关）。

### `audio_*`

| 方法 | 说明 |
|------|------|
| `audio_set/get_bus_volume_linear` | 总线音量 0～1，写入档案（静音时听感为 0，档案仍保留滑块值） |
| `audio_set/get_bus_muted` | 总线静音开关，写入档案 |
| `audio_default_bus_muted()` | 默认静音字典 |
| `audio_preview_bus_effective(bus, linear, muted)` | 预览听感音量（muted 时传 0） |
| `audio_apply_from_profile()` | 按档案重放各总线音量 |
| `audio_ensure_bus_apply_from_profile(bus)` | 确保总线存在并按档案应用听感 |
| `audio_default_bus_volumes()` | 默认音量字典 |
| `audio_get_root()` | 音频子系统根节点（`GDFrameAudioRoot`；BGM/SFX 池挂载于此） |
| `audio_play_bgm(stream, opts)` | BGM；opts：`loop`、`from_position`、`crossfade_sec`、`pitch_scale`、`loop_start_sec`、`loop_end_sec` |
| `audio_await_play_bgm(stream, opts)` | 同 play，可 `await` 交叉淡入结束（同曲跳过 / 无淡入则立即返回） |
| `audio_stop_bgm(fade_out_sec)` | 仅发起停止（不等待）；`0` 立刻停；`>0` 淡出；`-1` 用 config 默认 |
| `audio_await_stop_bgm(fade_out_sec)` | 同 stop，可 `await` 淡出结束 |
| `audio_preload_stream(stream, opts)` | 预加载并缓存 stream 副本（`loop` / WAV A～B），减轻首次播放卡顿 |
| `audio_get_bgm_stream()` | 当前 BGM stream（`stop` 后为 `null`） |
| `audio_has_bgm_loop_region()` | 当前 BGM 是否配置了循环区间 |
| `audio_is_bgm_playing()` / `audio_get_bgm_playback_position()` / `audio_get_bgm_pitch_scale()` | BGM 状态查询 |
| `audio_set/tween_bgm_pitch_scale` | 仅 **active** 曲目 pitch；`tween_*` 只发起过渡，`await_tween_*` 可等待结束 |
| `audio_get/set/tween_bgm_volume_linear` | BGM 播放器音量 `0~1`（不存档）；**BGM 淡入淡出 tween 运行中 set/tween 忽略** |
| `audio_set_paused` / `audio_is_paused` | 暂停 / 恢复 BGM、SFX；暂停期间 `play_bgm` / `play_sfx*` 不启动新播；`play_ui_sfx` 不受影响 |
| `audio_play_ui_sfx(stream, opts) -> bool` | 界面音效（Polyphonic，走 [code]UI[/code] 总线；不受 [code]audio_set_paused[/code]）；opts：[code]volume_linear[/code]、[code]pitch_scale[/code]、[code]from_position[/code] |
| `audio_play_sfx(stream, opts) -> bool` | 游戏特效 / 非空间 SFX（[code]SFX[/code] 总线）；限流丢弃时返回 `false` |
| `audio_play_sfx_2d(stream, position, opts) -> bool` | 2D 空间音效（`AudioStreamPlayer2D` 池） |
| `audio_play_sfx_3d(stream, position, opts) -> bool` | 3D 空间音效（`AudioStreamPlayer3D` 池） |
| `audio_stop_all_sfx()` | 停止 SFX 池内全部播放（不含界面 Polyphonic） |
| `audio_stop_all_ui_sfx()` | 停止全部界面音效 |
| `audio_stop_sfx_by_key(key)` | 停止指定 key 的 SFX |
| `audio_stop_sfx_on_bus(bus_name)` | 停止 SFX 池内指定总线上的播放（不含 [code]UI[/code] Polyphonic） |
| `audio_set_sfx_max_per_bus(bus_name, max_count)` | 某总线 SFX 并发上限；`0` 不限制 |
| `audio_set_sfx_max_per_key(max_count)` | 同一 key SFX 并发上限；`0` 不单独限制 |

**整曲 loop**：opts 中 `loop=true`（默认）为 Ogg / MP3 / WAV 生成可循环副本（Ogg/MP3/WAV 整曲；WAV 亦支持原生 `loop_mode`）。

**A～B 区间 loop**：WAV 写入 `loop_begin` / `loop_end` 采样点并由引擎循环。Ogg / MP3 无区间字段，指定 A～B 时只播一遍（编辑器 `push_warning`）；需区间循环请用 WAV 或预拼曲。

**总线**：框架内置 **Master / Music / UI / SFX**。扩展模块可通过 `extra_bus_names()` 追加总线（见 §3）。`audio_play_ui_sfx` 走 UI 总线；`audio_play_sfx*` 默认 SFX 总线。部分扩展 facade 在 **`audio_set_paused(true)` 期间不会启动新播放**；`audio_play_ui_sfx` 不受暂停拦截。

**`AudioStreamPolyphonic`（界面音效）**：框架在 `GDFrameAudioRoot/UI_SFX` 挂一个 `AudioStreamPlayer` + `AudioStreamPolyphonic`（复音上限见 [member GDFrameConfig.audio_ui_polyphony]），由 **`audio_play_ui_sfx`** 调用 `play_stream`。与 **`audio_play_sfx`** 系列对比如下：

| | `audio_play_sfx` 系列 | `audio_play_ui_sfx` |
|--|------------------------|---------------------|
| 播放器 | 池里多个 `AudioStreamPlayer(2D/3D)` | 单个 `UI_SFX` + Polyphonic |
| 总线 | 默认 `SFX`（可 `opts.bus`） | 固定 `UI` |
| 并发控制 | bus/key 限流 + 池大小 | `audio_ui_polyphony` |
| 暂停 | 受 `audio_set_paused` 拦截 | **不受**拦截 |
| 空间定位 | 有 `play_sfx_2d/3d` | 无（界面短音） |
| 适合 | 游戏 SFX（脚步、受击等） | 界面短音（按钮、连点等） |

```gdscript
GDFrame.audio_play_ui_sfx(click_stream)
GDFrame.audio_play_ui_sfx(click_stream, {"volume_linear": 0.8, "pitch_scale": 1.05})
```

**SFX 限流**：`max_per_bus` / `max_per_key` 为 `0` 时不限；池满可能抢轨。限流丢弃时 `play_sfx*` 返回 `false`。**注意**：`false` 亦可能因池未初始化、`audio_set_paused(true)` 拦截等——不能单凭 `false` 断定是限流。需日志时将 `audio_sfx_log_drops` 设为 `true`（编辑器 `push_warning`，导出运行 `print`）；默认 `false` 时静默丢弃。

### 本地化

在项目 **本地化** 注册 CSV；`ERR_SAVE_*` 等错误 key 须配置译文。DLC 翻译用 Godot 标准 `TranslationServer.add_translation`；语言切换后订阅 `signal_gdframe_locale_changed` 或对相关 UI 调用 `_on_locale_changed`。

---

## 11. 编辑器 Dock

底部面板 **GDFrame**，侧栏页签：

| 页签 | 功能 |
|------|------|
| **通用** | `ui_max_layer`、存档格式、`config.tres` 定位与同步、初始化本地化 CSV、外部编辑器打开工程、清空存档等 |
| **UI管理** | 创建 `ui_*`、列表编辑层与遮罩、定位 / 打开 / 更名 / 删除（运行中禁止写操作） |
| **状态机** | 在 `FSM_ROOT` 创建/管理状态机与状态（**运行中禁止**增删改） |
| **对象池** | 运行中调试 `pool_stats`（F5 运行且调试器已连接时点 **刷新**） |
| **扩展管理** | 安装/更新可选扩展、创建扩展模块、**生成扩展 API** |
| **更新** | 检查 GDFrame 版本并安装；成功后**自动重载插件**（运行中须先停止再手动点 **重载插件**） |

`keyboard_gamepad`、音频池等其余项在 **`config.tres` 检查器**中编辑。
