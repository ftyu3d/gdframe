## GDFrame 全局入口（Autoload 名仍为 [code]GDFrame[/code]）。
## 类型注解用 [code]GDFrameRoot[/code]；业务调用用 [code]GDFrame.ui[/code]、[code]GDFrame.audio[/code] 等服务。
## 勿直接改本插件内部实现类。
class_name GDFrameRoot
extends "res://gdframe_project/ext.gd"

# =============================================================================
# Preloads
# =============================================================================

const NodePool: Script = preload("res://addons/gdframe/runtime/pool/node_pool.gd")
const UIManager: Script = preload("res://addons/gdframe/runtime/ui/ui_manager.gd")
const FSMRunner: Script = preload("res://addons/gdframe/runtime/fsm/fsm_runner.gd")
const UISceneScan: Script = preload("res://addons/gdframe/runtime/ui/ui_scene_scan.gd")
const SaveManager: Script = preload("res://addons/gdframe/runtime/save/save_manager.gd")
const SettingsManager: Script = preload("res://addons/gdframe/runtime/settings/settings_manager.gd")
const InputDeviceTracker: Script = preload("res://addons/gdframe/runtime/input/input_device_tracker.gd")
const PauseManager: Script = preload("res://addons/gdframe/runtime/pause/pause_manager.gd")

# =============================================================================
# State — subsystems
# =============================================================================

var pool: GDFrameNodePool
var ui: GDFrameUIManager
var input: GDFrameInputDeviceTracker
var save: GDFrameSaveManager
var settings: GDFrameSettingsManager
var audio: GDFrameAudioChannels
var pause: GDFramePauseManager
var _fsm: GDFrameFSMRunner = null
var fsm: GDFrameFSMRunner:
	get:
		if _fsm == null:
			_fsm = FSMRunner.new()
			_fsm.setup_tree_pause_tracking(get_tree())
			_fsm.ensure_registry_index()
		return _fsm

# =============================================================================
# State — runtime
# =============================================================================

var _locale_broadcast_marker: String = ""
var _config: GDFrameConfig

# =============================================================================
# Lifecycle
# =============================================================================

## 启动时初始化：配置、存档、设置、音频、UI 层、对象池（FSM 在首次访问 [member fsm] 时初始化）；UI 场景目录见 [member GDFrameConfig.UI_ROOT_DIR]。
func _ready() -> void:
	_config = load(GDFrameConfig.PATH) as GDFrameConfig
	process_mode = Node.PROCESS_MODE_ALWAYS
	pool = NodePool.new()
	pool.setup(_config.pool_log_limits)
	save = SaveManager.new()
	save.setup(_config)
	if save.startup_profile_fallback():
		signal_gdframe_profile_startup_fallback.emit()
	settings = SettingsManager.new(save)
	audio = GDFrameAudioChannels.new(save)
	audio.setup(
		self,
		_config.audio_bgm_crossfade_sec,
		_config.audio_bgm_fade_out_sec,
		_config.audio_sfx_max_per_bus,
		_config.audio_sfx_max_per_key,
		_config.audio_sfx_pool_size,
		_config.audio_sfx_spatial_pool_size,
		_config.audio_sfx_log_drops,
		_config.audio_ui_polyphony,
	)
	audio.bgm_changed_listener = func(stream: AudioStream) -> void:
		signal_gdframe_bgm_changed.emit(stream)
	audio.paused_listener = func(paused: bool) -> void:
		signal_gdframe_audio_paused.emit(paused)
	save.profile_saved_hook = func(err: StringName) -> void:
		signal_gdframe_profile_saved.emit(err)
	save.game_save_written_hook = func(slot_id: String, err: StringName) -> void:
		signal_gdframe_game_save_written.emit(slot_id, err)
	save.game_save_deleted_hook = func(slot_id: String, err: StringName) -> void:
		signal_gdframe_game_save_deleted.emit(slot_id, err)
	save.profile_reloaded_hook = func() -> void:
		GDFrameExtBootstrap.ensure_profile(save.get_profile())
		settings.apply()
	settings.audio_apply_hook = Callable(audio, &"apply_from_profile")
	settings.locale_changed_hook = Callable(self, &"_locale_broadcast_if_changed")
	pause = PauseManager.new()
	pause.setup(self, Callable(self, &"_apply_pause"))
	_ext_bootstrap()
	call_deferred("_apply_settings_from_profile_deferred")
	_locale_broadcast_marker = TranslationServer.get_locale()
	ui = UIManager.new()
	ui.setup(self, _config.ui_max_layer + 1)
	ui.register_scanned_paths(UISceneScan.collect_ui_scene_paths(GDFrameConfig.UI_ROOT_DIR))
	input = InputDeviceTracker.new()
	input.setup(self, _config.keyboard_nav_focus)
	signal_gdframe_input_device_changed.connect(_on_input_device_changed)
	if OS.has_feature("editor"):
		EngineDebugger.register_message_capture("gdframe", _on_debugger_capture)
	audio.apply_from_profile()


func _apply_settings_from_profile_deferred() -> void:
	settings.apply_from_profile(false)
	_locale_broadcast_if_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and OS.has_feature("editor"):
		EngineDebugger.unregister_message_capture("gdframe")


func _input(event: InputEvent) -> void:
	settings.apply_pending_web_fullscreen(event)
	input.process_event(event)
	if not event.is_pressed() or event.is_echo():
		return
	var is_key: bool = event is InputEventKey
	var is_joy_btn: bool = event is InputEventJoypadButton
	var is_joy_motion: bool = event is InputEventJoypadMotion
	if not is_key and not is_joy_btn and not is_joy_motion:
		return
	if (is_key or is_joy_btn) and ui.process_cancel_input(event):
		get_viewport().set_input_as_handled()
		return
	var active: GDFrameUIBase = ui.get_active_ui()
	if active == null:
		return
	var nav_action: int = GDFrameUINav.nav_pressed_action(event)
	if nav_action == GDFrameUINav.NavPress.NONE:
		return
	if not input.should_allow_nav_focus():
		return
	if ui.process_nav_action(nav_action, active):
		get_viewport().set_input_as_handled()
		return
	# 竖排页不吃左右键时，避免 Godot 默认邻居导航抢走焦点。
	if nav_action != GDFrameUINav.NavPress.ACCEPT and active.ui_nav_has_items():
		get_viewport().set_input_as_handled()


## 编辑器调试器拉取对象池统计时的回调（仅编辑器）。
func _on_debugger_capture(message: String, _data: Array) -> bool:
	if message == "request_pool_stats":
		EngineDebugger.send_message("gdframe:pool_stats", [pool.get_all_stats()])
		return true
	return false


## 子 UI 关闭后，等 GUI 输入帧结束再确认父面板焦点。
func _nav_focus_restore(restore_after_close: Dictionary) -> void:
	await get_tree().process_frame
	if ui != null:
		ui.restore_nav_return_focus(restore_after_close)


# =============================================================================
# Internal
# =============================================================================

## 语言变更时广播 [code]signal_gdframe_locale_changed[/code] 并通知可见 UI。
func _locale_broadcast_if_changed() -> void:
	var cur: String = TranslationServer.get_locale()
	if cur == _locale_broadcast_marker:
		return
	_locale_broadcast_marker = cur
	signal_gdframe_locale_changed.emit(cur)
	ui.notify_locale()


## 切换设备时更新光标，并按当前设备决定是否给导航项聚焦。
func _on_input_device_changed(
	device_kind: GDFrameInputEventDevice.DeviceKind,
	_device_id: int,
	_is_emulated: bool,
) -> void:
	_apply_input_cursor(device_kind)
	_refresh_active_ui_nav_focus()


func _apply_input_cursor(device_kind: GDFrameInputEventDevice.DeviceKind) -> void:
	if input.should_hide_cursor(device_kind):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_active_ui_nav_focus() -> void:
	var active: GDFrameUIBase = ui.get_active_ui()
	if active == null:
		return
	active.ui_nav_sync_item_focus_modes()
	if not input.should_allow_nav_focus():
		return
	var items: Array[Control] = active.ui_nav_get_items()
	if items.is_empty():
		return
	var owner: Control = get_viewport().gui_get_focus_owner() as Control
	if owner != null and GDFrameUINav.is_text_input(owner) and active.is_ancestor_of(owner):
		return
	var current: Control = active.ui_nav_current_item(items, owner)
	if current != null:
		active.ui_nav_apply_focus(current)
		return
	var target: Control = GDFrameUINav.resolve_focus_target(active, null, null)
	if target != null:
		active.ui_nav_apply_focus(target)


func _ext_bootstrap() -> void:
	GDFrameExtBootstrap.setup(self, save.get_profile())


func _apply_pause(paused: bool) -> void:
	get_tree().paused = paused
	audio.set_paused(paused)


# =============================================================================
# Ext — 扩展服务槽位（module.gd register 写入；业务优先用已生成槽位字段）
# =============================================================================

## 注册扩展服务并写入生成的强类型槽位（如 [code]example[/code]）。
func ext_register(key: StringName, service: Variant) -> void:
	_bind_ext_service(key, service)
