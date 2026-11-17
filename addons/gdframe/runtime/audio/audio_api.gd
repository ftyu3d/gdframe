extends RefCounted
class_name GDFrameAudioApi
## 音频 API 空壳基类（核心侧契约）。
##
## 未安装 [code]addons/gdframe_audio[/code] 时，生成的 [code]GDFrameAudioChannels[/code]
## 继承本类，[code]GDFrame.audio[/code] 的全部调用都是空实现，项目不会创建任何音频节点与总线。
## 安装音频扩展后由 [code]GDFrameAudioManager[/code] 覆盖同名方法，本类不再被直接使用。
##
## 注意：不要在基类声明 [code]_save[/code] / [code]_channels[/code]，
## 扩展的 [code]GDFrameAudioManager[/code] 已声明同名成员，重复声明会导致解析失败。

## BGM 变更监听（子类在通知 BGM 变化时调用）。
var bgm_changed_listener: Callable = Callable()

## 暂停状态变更监听。
var paused_listener: Callable = Callable()


func _init(_save: Variant = null) -> void:
	pass


# =============================================================================
# 初始化
# =============================================================================

func setup(
	_root_node: Node,
	_bgm_crossfade_sec: float = 0.0,
	_bgm_fade_out_sec: float = 0.0,
	_sfx_max_per_bus: int = 8,
	_sfx_max_per_key: int = 4,
	_sfx_pool_size: int = 8,
	_sfx_spatial_pool_size: int = 4,
	_sfx_log_drops: bool = false,
	_ui_polyphony: int = 32,
) -> void:
	pass


func register_channels(_service: Variant) -> void:
	pass


func channel_names() -> Array[StringName]:
	return []


func apply_from_profile() -> void:
	pass


# =============================================================================
# 音量 / 总线（空实现）
# =============================================================================

static func default_bus_volumes() -> Dictionary[String, float]:
	return {}


static func default_bus_muted() -> Dictionary[String, bool]:
	return {}


static func ensure_profile_bus_keys(_prof: GDFrameProfileResource) -> void:
	pass


func get_bus_volume_linear(_bus_name: StringName) -> float:
	return 1.0


func set_bus_volume_linear(_bus_name: StringName, _linear: float) -> void:
	pass


func is_bus_muted(_bus_name: StringName) -> bool:
	return false


func set_bus_muted(_bus_name: StringName, _muted: bool) -> void:
	pass


# =============================================================================
# BGM（空实现）
# =============================================================================

func play_bgm(_stream: AudioStream, _opts: Dictionary = {}) -> void:
	pass


func await_play_bgm(_stream: AudioStream, _opts: Dictionary = {}) -> void:
	pass


func stop_bgm(_fade_out_sec: float = 0.0) -> void:
	pass


func await_stop_bgm(_fade_out_sec: float = 0.0) -> void:
	pass


func is_bgm_playing() -> bool:
	return false


func get_bgm_stream() -> AudioStream:
	return null


func get_bgm_volume_linear() -> float:
	return 0.0


func set_bgm_volume_linear(_linear: float) -> void:
	pass


func get_bgm_pitch_scale() -> float:
	return 1.0


func set_bgm_pitch_scale(_pitch_scale: float) -> void:
	pass


# =============================================================================
# SFX / UI（空实现）
# =============================================================================

func play_sfx(_stream: AudioStream, _opts: Dictionary = {}) -> bool:
	return false


func play_ui_sfx(_stream: AudioStream, _opts: Dictionary = {}) -> bool:
	return false


func stop_all_sfx() -> void:
	pass


func stop_sfx_by_key(_key: StringName) -> void:
	pass


func stop_sfx_on_bus(_bus_name: StringName) -> void:
	pass


func stop_all_ui_sfx() -> void:
	pass


# =============================================================================
# 暂停（空实现）
# =============================================================================

func set_paused(_paused: bool) -> void:
	pass


func is_paused() -> bool:
	return false
