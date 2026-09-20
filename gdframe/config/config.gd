## 全局配置资源（[code]addons/gdframe/config/config.tres[/code]）；启动时由 [code]GDFrame[/code] 加载。
## 路径类常量在脚本内固定（[member UI_ROOT_DIR]、[member FSM_ROOT] 等），一般不改；可调项在检查器分组中编辑。
extends Resource
class_name GDFrameConfig

# =============================================================================
# Paths
# =============================================================================

## 项目配置资源路径（随仓库提交的 [code]config.tres[/code]）。
const PATH: String = "res://addons/gdframe/config/config.tres"

## Autoload 节点名（[code]project.godot[/code] 注册名；扩展模块定位 [code]GDFrame[/code] 时使用）。
const AUTOLOAD_NAME: StringName = &"GDFrame"

## 框架内置全局信号脚本（勿改）。
const SIGNALS_BASE_PATH: String = "res://addons/gdframe/runtime/gdframe_signals_base.gd"

## 工程目录根（固定）；业务与生成脚本写于此，勿放入 [code]addons/gdframe/[/code]。
const PROJECT_ROOT: String = "res://gdframe_project"
## 插件自动生成的脚本目录（勿手改；扫描 UI/FSM、扩展 API 写入此目录）。
const GENERATED_DIR: String = "res://gdframe_project/generated"
## 自动生成的 UI/FSM 常量脚本（[code]class_name GDFrameConstants[/code]）。
const CONSTANTS_SCRIPT_PATH: String = "res://gdframe_project/generated/gdframe_constants.gd"
## 自动生成的 API 错误码脚本（[code]class_name GDFrameResult[/code]；核心 [code]ERR_SAVE_*[/code] + 扩展 [code]result_constants()[/code]）。
const RESULT_SCRIPT_PATH: String = "res://gdframe_project/generated/gdframe_result.gd"
## 业务全局信号脚本（[code]extends[/code] [member SIGNALS_BASE_PATH]；扩展信号段自动生成，业务段手写）。
const SIGNALS_SCRIPT_PATH: String = "res://gdframe_project/gdframe_signals.gd"
## 工程 profile 设置 Resource（[code]extends GDFrameSettingsData[/code]；扩展 [code]@export[/code] 由生成器写入自动生成段）。
const PROFILE_SETTINGS_SCRIPT_PATH: String = "res://gdframe_project/profile_settings_data.gd"
## 扩展 profile 缺字段补默认（由各扩展 [code]editor/module_editor.gd[/code] 的 [code]profile_fields()[/code] 扫描生成；[code]GDFrameProfileSettingsExt[/code] 调用）。
const PROFILE_SETTINGS_DEFAULTS_PATH: String = "res://gdframe_project/generated/profile_settings_defaults.gd"
## 扩展插件所在目录（扫描 [code]addons/gdframe_*/module.gd[/code]；勿与核心 [code]addons/gdframe[/code] 混放）。
const EXT_ADDONS_DIR: String = "res://addons"
## 扩展插件目录前缀；逻辑 id 为 [code]account[/code] 时目录为 [code]addons/gdframe_account/[/code]。
const EXT_ADDON_PREFIX: String = "gdframe_"
## 项目扩展门面脚本（手写桩；[code]gdframe.gd[/code] [code]extends[/code] 此项）。
const EXT_FACADE_PATH: String = "res://gdframe_project/facade.gd"
## 自动生成的扩展 API 脚本（[code]GDFrame.account_*[/code] / [code]GDFrame.rumble[/code] 等；Dock [b]扩展管理 → 生成扩展 API[/b] 写入）。
const EXT_FACADE_MODULES_PATH: String = "res://gdframe_project/generated/facade_modules.gd"
## UI 场景根目录（[code]ui_*.tscn[/code]）；启动时自动扫描并登记路径（不预加载场景）。
const UI_ROOT_DIR: String = "res://gdframe_project/ui"
## 全屏遮罩场景（[code]dim.tscn[/code]）；缺失时运行时断言失败，请重载 GDFrame 插件。
const DIM_SCENE_PATH: String = "res://gdframe_project/dim.tscn"
## 全屏遮罩根脚本（与 [member DIM_SCENE_PATH] 配套）。
const DIM_SCRIPT_PATH: String = "res://gdframe_project/dim.gd"
## FSM 定义根目录（[code]fsm_*/fsm_*_registry.gd[/code]）；首次 [code]fsm_*[/code] 调用时建立索引。
const FSM_ROOT: String = "res://gdframe_project/fsm"


static func ext_normalize_module_id(raw_id: String) -> String:
	var id: String = raw_id.strip_edges()
	if id.begins_with(EXT_ADDON_PREFIX):
		id = id.substr(EXT_ADDON_PREFIX.length())
	return id


static func ext_addon_dir_name(module_id: String) -> String:
	return EXT_ADDON_PREFIX + ext_normalize_module_id(module_id)


static func ext_addon_path(module_id: String) -> String:
	return EXT_ADDONS_DIR.path_join(ext_addon_dir_name(module_id))


static func ext_plugin_cfg_path(module_id: String) -> String:
	return ext_addon_path(module_id).path_join("plugin.cfg")


static func is_ext_addon_dir_name(dir_name: String) -> bool:
	return dir_name.begins_with(EXT_ADDON_PREFIX) and dir_name.length() > EXT_ADDON_PREFIX.length()


# =============================================================================
# Save format
# =============================================================================

## 存档文件序列化格式。
enum SaveFileFormat {
	## 文本 [code].tres[/code]，便于版本管理 diff。
	TEXT,
	## 二进制 [code].res[/code]，体积更小。
	BINARY,
}

# =============================================================================
# Inspector — UI
# =============================================================================

## 普通 UI 图层与 [CanvasLayer] 排序（模态遮罩 dim 由框架 UI 子系统单独维护，不占图层数）。
@export_group("UI")
## UI 最大层编号（从 0 起；[code]2[/code] 表示 [code]layer_0[/code]～[code]layer_2[/code]）。与 Dock [b]通用 → UI 最大层[/b]、[method GDFrame.ui_open] 的 [code]layer[/code] 同编号。
@export_range(0, 63) var ui_max_layer: int = 2

# =============================================================================
# Inspector — Input
# =============================================================================

## 谁可以给按钮等导航项抢 GUI 焦点（鼠标/触屏始终不可以；输入框点选打字不受限）。
@export_group("Input")
## [code]false[/code]：仅手柄可聚焦导航项；[code]true[/code]：键盘与手柄均可。
## 藏光标：手柄始终；键盘仅在本项为 [code]true[/code]；鼠标显示；触屏不强制隐藏。
@export var keyboard_nav_focus: bool = false

# =============================================================================
# Inspector — Save
# =============================================================================

## 玩家档案（profile）与槽位文件的磁盘序列化格式。
@export_group("Save")
## [code]TEXT[/code] → [code].tres[/code]（便于 diff）；[code]BINARY[/code] → [code].res[/code]。Dock 切换格式会将 [code]user://gdframe[/code] 下现有存档转换为新扩展名。
@export var save_file_format: SaveFileFormat = SaveFileFormat.TEXT

# =============================================================================
# Inspector — Pool
# =============================================================================

## 对象池运行时诊断日志（非错误类 push_error 不受影响）。
@export_group("Pool")
## [code]true[/code] 时 [code]max_active[/code] 已满仍 [code]pool_get[/code] 会输出日志：编辑器 [code]push_warning[/code]，导出运行 [code]print[/code]。
## 若用 [code]max_active[/code] 做限流且不想刷屏，可保持 [code]false[/code]。
@export var pool_log_limits: bool = false

# =============================================================================
# Inspector — Audio
# =============================================================================

## BGM / SFX / 界面音效默认行为（运行时 [code]audio_*[/code] opts 可覆盖单项）。
@export_group("Audio")
## BGM 换曲交叉淡入默认时长（秒）；[code]0[/code] = 硬切；[code]audio_play_bgm(stream, {"crossfade_sec": -1})[/code] 使用本项。
@export_range(0.0, 10.0, 0.05, "or_greater") var audio_bgm_crossfade_sec: float = 0.5
## BGM 停止默认淡出时长（秒）；[code]audio_stop_bgm(-1)[/code] 使用本项。[code]0[/code] = 立刻停止。
@export_range(0.0, 10.0, 0.05, "or_greater") var audio_bgm_fade_out_sec: float = 0.0
## 非空间 SFX 对象池节点数（启动时创建）。限流由 [member audio_sfx_max_per_bus] 控制；池为物理播放器上限。
@export_range(1, 64) var audio_sfx_pool_size: int = 8
## 2D / 3D 空间音效各自的对象池大小（启动时创建）。
@export_range(1, 64) var audio_sfx_spatial_pool_size: int = 4
## 同一总线 SFX 最大同时播放数（含 2D/3D 池）；[code]0[/code] = 不限制（仍受池大小约束，池满可能抢轨）。
@export_range(0, 64) var audio_sfx_max_per_bus: int = 8
## 同一 [code]key[/code]（[code]audio_play_sfx[/code] opts）最大同时播放数；[code]0[/code] = 不单独限制。
@export_range(0, 64) var audio_sfx_max_per_key: int = 4
## [code]true[/code] 时 SFX / UI 音效被限流丢弃会输出日志：编辑器 [code]push_warning[/code]，导出运行 [code]print[/code]。
@export var audio_sfx_log_drops: bool = false
## 界面音效 [code]UI_SFX[/code] Polyphonic 最大同时播放数（启动时创建）；[method GDFrame.audio_play_ui_sfx] 使用。
@export_range(1, 128) var audio_ui_polyphony: int = 32

# =============================================================================
# API
# =============================================================================

## 当前 [member save_file_format] 对应的文件扩展名（含点号）。
func get_save_extension() -> String:
	return ".res" if save_file_format == SaveFileFormat.BINARY else ".tres"
