## GDFrame 框架内置全局信号（随插件分发，请勿修改）。
## 业务自定义信号声明见 [member GDFrameConfig.SIGNALS_SCRIPT_PATH]。
extends Node

# =============================================================================
# Signals
# =============================================================================

signal signal_gdframe_input_device_changed(
	device_kind: GDFrameInputEventDevice.DeviceKind,
	device_id: int,
	is_emulated: bool,
)
signal signal_gdframe_locale_changed(locale: String)
signal signal_gdframe_profile_saved(error: StringName)
## 启动时磁盘 profile 存在但无法解析，已回退默认档案（见 [method GDFrame.save_startup_profile_fallback]）。
signal signal_gdframe_profile_startup_fallback()
signal signal_gdframe_game_save_written(slot_id: String, error: StringName)
signal signal_gdframe_game_save_deleted(slot_id: String, error: StringName)
signal signal_gdframe_bgm_changed(stream: AudioStream)
signal signal_gdframe_pause_changed(is_paused: bool, depth: int)
