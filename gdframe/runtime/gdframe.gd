## GDFrame 全局入口（Autoload）。
## 业务代码统一通过 [code]GDFrame.xxx()[/code] 调用；勿直接改本插件内部实现类。
extends "res://gdframe/ext/facade.gd"

# =============================================================================
# Preloads
# =============================================================================

const NodePool: Script = preload("res://addons/gdframe/runtime/pool/node_pool.gd")
const UIManager: Script = preload("res://addons/gdframe/runtime/ui/ui_manager.gd")
const FSMRunner: Script = preload("res://addons/gdframe/runtime/fsm/fsm_runner.gd")
const UISceneScan: Script = preload("res://addons/gdframe/runtime/ui/ui_scene_scan.gd")
const SaveManager: Script = preload("res://addons/gdframe/runtime/save/save_manager.gd")
const SettingsManager: Script = preload("res://addons/gdframe/runtime/settings/settings_manager.gd")
const AudioManager: Script = preload("res://addons/gdframe/runtime/audio/audio_manager.gd")
const InputDeviceTracker: Script = preload("res://addons/gdframe/runtime/input/input_device_tracker.gd")
const PauseManager: Script = preload("res://addons/gdframe/runtime/pause/pause_manager.gd")
const ExtRuntime: Script = preload("res://addons/gdframe/runtime/ext/ext_runtime.gd")

# =============================================================================
# State — subsystems
# =============================================================================

var _pool: GDFrameNodePool
var _ui: GDFrameUIManager
var _device_tracker: GDFrameInputDeviceTracker
var _fsm: GDFrameFSMRunner = null
var _save_manager: GDFrameSaveManager
var _settings: GDFrameSettingsManager
var _audio: GDFrameAudioManager
var _pause: GDFramePauseManager
var _services: Dictionary[StringName, Variant] = {}

# =============================================================================
# State — runtime
# =============================================================================

var _locale_broadcast_marker: String = ""
var _config: GDFrameConfig
var _save_startup_recovery_err: StringName = GDFrameResult.OK

# =============================================================================
# Lifecycle
# =============================================================================

## 启动时初始化：配置、存档、设置、音频、UI 层、对象池（FSM 在首次 fsm_* 调用时初始化）；UI 场景目录见 [member GDFrameConfig.UI_ROOT_DIR]。
func _ready() -> void:
	_config = load(GDFrameConfig.PATH) as GDFrameConfig
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pool = NodePool.new()
	_pool.setup(_config.pool_log_limits)
	_save_manager = SaveManager.new()
	_save_startup_recovery_err = _save_manager.setup(_config)
	if _save_manager.startup_profile_fallback():
		signal_gdframe_profile_startup_fallback.emit()
	_settings = SettingsManager.new(_save_manager, _config)
	_audio = AudioManager.new(_save_manager)
	_audio.setup(
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
	# GDFrameAudioManager 是 RefCounted，不能直接 emit；经 Callable 转到 Autoload 信号。
	_audio.bgm_changed_listener = func(stream: AudioStream) -> void:
		signal_gdframe_bgm_changed.emit(stream)
	_pause = PauseManager.new()
	_pause.setup(self, Callable(self, &"_apply_game_paused"))
	_ext_bootstrap()
	call_deferred("_apply_settings_from_profile_deferred")
	_locale_broadcast_marker = TranslationServer.get_locale()
	_ui = UIManager.new()
	_ui.setup(self, _config.ui_max_layer + 1)
	_ui.register_scanned_paths(UISceneScan.collect_ui_scene_paths(GDFrameConfig.UI_ROOT_DIR))
	_device_tracker = InputDeviceTracker.new()
	_device_tracker.setup(self)
	signal_gdframe_input_device_changed.connect(_on_input_device_changed)
	if OS.has_feature("editor"):
		EngineDebugger.register_message_capture("gdframe", _on_debugger_capture)
	audio_apply_from_profile()


func _apply_settings_from_profile_deferred() -> void:
	_settings.apply_from_profile()
	_locale_broadcast_if_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and OS.has_feature("editor"):
		EngineDebugger.unregister_message_capture("gdframe")


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	input_track_event(event)
	var is_key: bool = event is InputEventKey
	var is_joy_btn: bool = event is InputEventJoypadButton
	var is_joy_motion: bool = event is InputEventJoypadMotion
	if not is_key and not is_joy_btn and not is_joy_motion:
		return
	if (is_key or is_joy_btn) and _ui.process_cancel_input(event):
		get_viewport().set_input_as_handled()
		return
	var active: GDFrameUIBase = _ui.get_active_ui()
	if active == null:
		return
	var nav_action: int = GDFrameUINav.nav_pressed_action(event)
	if nav_action == GDFrameUINav.NavPress.NONE:
		return
	if _ui.process_nav_action(nav_action, active):
		get_viewport().set_input_as_handled()


## 编辑器调试器拉取对象池统计时的回调（仅编辑器）。
func _on_debugger_capture(message: String, _data: Array) -> bool:
	if message == "request_pool_stats":
		EngineDebugger.send_message("gdframe:pool_stats", [_pool.get_all_stats()])
		return true
	return false


## 子 UI 关闭后，等 GUI 输入帧结束再确认父面板焦点。
func _gdframe_nav_focus_restore(restore_after_close: Dictionary) -> void:
	await get_tree().process_frame
	if _ui != null:
		_ui.restore_nav_return_focus(restore_after_close)


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
	_ui.notify_locale()


## 切换到键盘/手柄/指针时切换光标可见性，并刷新 UI 导航聚焦环（与光标互斥）。
func _on_input_device_changed(
	device_kind: GDFrameInputEventDevice.DeviceKind,
	_device_id: int,
	_is_emulated: bool,
) -> void:
	_apply_input_cursor(device_kind)
	_refresh_active_ui_nav_focus()


func _apply_input_cursor(device_kind: GDFrameInputEventDevice.DeviceKind) -> void:
	if input_should_hide_cursor(device_kind):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_active_ui_nav_focus() -> void:
	if _ui == null:
		return
	var active: GDFrameUIBase = _ui.get_active_ui()
	if active == null:
		return
	var items: Array[Control] = active.ui_nav_get_items()
	if items.is_empty():
		return
	var owner: Control = get_viewport().gui_get_focus_owner() as Control
	if owner != null and active.is_ancestor_of(owner):
		var current: Control = active.ui_nav_current_item(items, owner)
		if current != null:
			active.ui_nav_apply_focus(current)
			return
	if not GDFrameInputEventDevice.supports_ui_focus_navigation(input_get_device_kind()):
		return
	_ui.nav_refresh()


func _ext_bootstrap() -> void:
	GDFrameExtBootstrap.setup(self)


func _ensure_fsm() -> GDFrameFSMRunner:
	if _fsm != null:
		return _fsm
	_fsm = FSMRunner.new()
	_fsm.setup_tree_pause_tracking(get_tree())
	_fsm.ensure_registry_index()
	return _fsm


func _fsm_tick(owner: Node, method: StringName, arg: Variant = null) -> void:
	if _fsm == null and not owner.has_meta(GDFrameFSMRunner.OWNER_HANDLES_META):
		return
	var runner: GDFrameFSMRunner = _ensure_fsm()
	match method:
		&"process":
			runner.process(owner, arg as float)
		&"physics_process":
			runner.physics_process(owner, arg as float)
		&"dispatch_input":
			runner.dispatch_input(owner, arg as InputEvent)


# =============================================================================
# Service
# =============================================================================

## 注册一个业务服务对象，之后用 [code]service_get[/code] 取出。
func service_register(key: StringName, service: Variant) -> void:
	_services[key] = service


## 按 key 取已注册的服务；没有则返回 [code]null[/code]。
func service_get(key: StringName) -> Variant:
	return _services.get(key, null)


## 是否已注册指定 key 的服务。
func service_has(key: StringName) -> bool:
	return _services.has(key)


func _broadcast_audio_paused_to_services(paused: bool) -> void:
	for key: StringName in _services:
		var svc: Variant = _services[key]
		if svc != null and svc.has_method(&"set_audio_paused"):
			svc.call(&"set_audio_paused", paused)


# =============================================================================
# UI
# =============================================================================

## 预加载：实例化并执行 UI 脚本的 [code]_on_init[/code]（经 [code]gdframe_init()[/code]；可为协程）。
## 用法：[code]await GDFrame.ui_preload(ui_id)[/code]。
## 打开前必须先预加载；仅预加载需要 [code]await[/code]（协程在框架内部，[code]ui_open[/code] 仍为同步）。
func ui_preload(ui_id: StringName) -> void:
	await _ui.prepare(ui_id)


## 同步打开已预加载的 UI（不是协程，不要 [code]await[/code]）。
## 若未预加载会 [code]push_error[/code] 并返回 [code]null[/code]。
## [param data] 传给 [code]_on_show(data)[/code] 的自定义数据。
## [param layer] 为 -1 时使用场景根 ui_default_layer；预加载挂默认层，ui_open 可覆盖。
func ui_open(ui_id: StringName, data: Variant = null, layer: int = -1) -> Control:
	return _ui.open(ui_id, data, layer)


## 关闭 [param close_id] 并打开 [param open_id]；关闭 [param open_id] 时自动重新打开 [param close_id] 并恢复离开时的聚焦项。
func ui_open_replace(close_id: StringName, open_id: StringName, data: Variant = null, layer: int = -1) -> Control:
	return _ui.open_replace(close_id, open_id, data, layer)


## 是否已完成预加载（含 [code]_on_init[/code]）。
func ui_is_preloaded(ui_id: StringName) -> bool:
	return _ui.is_preloaded(ui_id)


## 取缓存中的 UI 节点（不要求当前可见）。
func ui_get(ui_id: StringName) -> Control:
	return _ui.get(ui_id)


## 是否已有该 UI 的缓存实例（可能仍隐藏）。
func ui_is_cached(ui_id: StringName) -> bool:
	return _ui.is_cached(ui_id)


## 关闭 UI。[param cache] 为 [code]true[/code] 时仅隐藏并保留实例。
## 返回 [code]false[/code] 表示拒绝关闭（[code]_on_close[/code] 返回了 [code]false[/code]）。
func ui_close(ui_id: StringName, cache: bool = true) -> bool:
	return _ui.close(ui_id, cache)


## 该 UI 是否正在显示。
func ui_is_open(ui_id: StringName) -> bool:
	return _ui.is_open(ui_id)


## 关闭栈顶 UI（最后打开的那个）。
func ui_close_top() -> bool:
	return _ui.close_top()


## 取已缓存 UI 实例对应的 [code]ui_id[/code]。
func ui_get_id(ui: GDFrameUIBase) -> StringName:
	return _ui.get_ui_id(ui)


## Esc 刚关闭 UI 后的短暂窗口内为 [code]true[/code]；宿主可用来避免同帧误触发其它 UI。
func ui_is_pause_open_blocked() -> bool:
	return _ui.is_pause_open_blocked()


## 重新计算 UI 导航并聚焦当前活跃面板（遮挡层消失后可调用）。
func ui_nav_refresh() -> void:
	_ui.nav_refresh()


## 当前接收键盘/手柄导航的 UI 面板。
func ui_nav_get_active_ui() -> GDFrameUIBase:
	return _ui.get_active_ui()


# =============================================================================
# Input
# =============================================================================

## 由框架 Autoload 输入回调自动调用；业务一般无需手动调用。[InputEventMouseMotion] 直接跳过（悬停不切换设备）。
## 若业务在其它节点自行消费输入且仍须更新设备跟踪，可对该事件调用本方法。
func input_track_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	_device_tracker.process_event(event)


## 当前输入设备类型（与 Godot [InputEvent] 子类对应，见 [GDFrameInputEventDevice]）。
func input_get_device_kind() -> GDFrameInputEventDevice.DeviceKind:
	return _device_tracker.get_device_kind()


## 最近一次切换设备事件的 [member InputEvent.device]（手柄索引等；-1 表示未知或未跟踪）。
func input_get_device_id() -> int:
	return _device_tracker.get_device_id()


## 当前是否以手柄（Joypad）为主要输入设备。
func input_is_using_gamepad() -> bool:
	return _device_tracker.is_using_gamepad()


## 当前是否为指针类输入（鼠标 / 触屏）。
func input_is_using_pointer() -> bool:
	return _device_tracker.is_using_pointer()


## 最近一次切换设备的事件是否为 Godot 模拟输入（如触屏转鼠标）。
func input_was_last_device_event_emulated() -> bool:
	return _device_tracker.was_last_event_emulated()


## 切换至 [param device_kind] 时是否应隐藏鼠标（见 [member GDFrameConfig.keyboard_gamepad]）。
func input_should_hide_cursor(
	device_kind: GDFrameInputEventDevice.DeviceKind,
) -> bool:
	return GDFrameInputEventDevice.should_hide_cursor(
		device_kind,
		_config.keyboard_gamepad,
	)


## 程序化聚焦时是否显示 UI 导航选中框；与 [method input_should_hide_cursor] 互斥。
func input_should_show_focus_on_grab() -> bool:
	return GDFrameInputEventDevice.should_show_nav_focus_on_grab(
		input_get_device_kind(),
		_config.keyboard_gamepad,
	)


# =============================================================================
# Pool
# =============================================================================

## 用场景注册对象池，并可预热、设置空闲/在用上限。仍有借出项时重注册返回 [code]false[/code]。
func pool_scene(
	key: StringName,
	scene: PackedScene,
	warmup_count: int = 0,
	max_idle: int = 0,
	max_active: int = 0,
) -> bool:
	if not _pool.register_scene(key, scene):
		return false
	_pool.set_limits(key, max_idle, max_active)
	if warmup_count > 0:
		_pool.warmup(key, warmup_count)
	return true


## 用工厂函数注册对象池（代码里 [code]new[/code] 节点时用）；参数含义同 [method pool_scene]。失败时返回 [code]false[/code]。
func pool_factory(
	key: StringName,
	factory: Callable,
	warmup_count: int = 0,
	max_idle: int = 0,
	max_active: int = 0,
) -> bool:
	if not _pool.warmup_factory(key, factory, warmup_count):
		return false
	_pool.set_limits(key, max_idle, max_active)
	return true


## 从池中取一个实例；[param parent] 非空时会 [code]add_child[/code]。
func pool_get(key: StringName, parent: Node = null) -> Variant:
	return _pool.get_item(key, parent)


## 把实例还回池里（[GDFramePoolPooled] 会先调用 [code]on_pool_recycle[/code]）。
func pool_recycle(key: StringName, item: Variant) -> void:
	_pool.recycle_item(key, item)


## 清空某 key 的空闲列表；[param free_nodes] 为 [code]true[/code] 时释放空闲节点。
## 仍有借出项时返回 [code]false[/code] 且不修改池状态。
func pool_clear(key: StringName, free_nodes: bool = false) -> bool:
	return _pool.clear(key, free_nodes)


## 调整某 key 的空闲数、在用数上限。
func pool_set_limits(key: StringName, max_idle: int = 0, max_active: int = 0) -> void:
	_pool.set_limits(key, max_idle, max_active)


## 单个 key 的池统计（数量、上限等）。
func pool_stats(key: StringName) -> Dictionary:
	return _pool.get_stats(key)


## 所有已注册 key 的池统计。
func pool_stats_all() -> Dictionary:
	return _pool.get_all_stats()


# =============================================================================
# Save
# =============================================================================

## 启动时存档恢复结果；成功为 [member GDFrameResult.OK]。
func save_startup_recovery_error() -> StringName:
	return _save_startup_recovery_err


## 扫描并恢复全部 profile / 槽位上的 [code].tmp[/code]/[code].bak[/code] sidecar。
func save_recover_all_pending() -> StringName:
	var err: StringName = _save_manager.recover_all_pending_saves()
	_save_startup_recovery_err = err
	return err


## 仅恢复指定槽位路径上的 [code].tmp[/code]/[code].bak[/code]（写档重试前推荐，避免扫描全部槽位）。
func save_recover_game_slot(slot_id: String) -> StringName:
	return _save_manager.recover_game_slot(slot_id)


## 启动恢复为 [member GDFrameResult.ERR_SAVE_CORRUPTED] 时，玩家档案（profile）是否损坏。
func save_startup_corrupt_profile() -> bool:
	return _save_manager.startup_corrupt_profile()


## 启动恢复为 [member GDFrameResult.ERR_SAVE_CORRUPTED] 时，损坏的槽位 id 列表。
func save_startup_corrupt_slots() -> Array[String]:
	return _save_manager.startup_corrupt_slots()


## 启动时 profile 文件存在但无法解析，已回退默认档案（非 [member GDFrameResult.ERR_SAVE_CORRUPTED]）。
func save_startup_profile_fallback() -> bool:
	return _save_manager.startup_profile_fallback()


## 删除磁盘 profile 并改用内存默认档案（玩家确认「损坏存档」后调用）。
func save_delete_profile_from_disk() -> StringName:
	return _save_manager.delete_profile_from_disk()


## 取得当前内存中的玩家档案资源（设置、音量等）。
func save_get_profile() -> GDFrameProfileResource:
	return _save_manager.get_profile()


## 将内存中的 profile 写入磁盘。返回 [member GDFrameResult.OK] 或 [GDFrameResult.ERR_SAVE_*]。
func save_flush() -> StringName:
	var err: StringName = _save_manager.save_profile()
	signal_gdframe_profile_saved.emit(err)
	return err


## 协程写 profile：让出一帧再落盘，便于等待 UI 绘制；流程结束后再根据返回值提示失败。
func save_flush_async() -> StringName:
	await get_tree().process_frame
	return save_flush()


## 从磁盘重新加载档案，并应用到设置与音频。返回 [member GDFrameResult.OK] 或存档相关 [code]ERR_SAVE_*[/code]。
func save_reload() -> StringName:
	var err: StringName = _save_manager.reload_profile()
	if GDFrameResult.is_ok(err):
		GDFrameExtBootstrap.ensure_profile(_save_manager.get_profile())
	_settings.apply_from_profile()
	audio_apply_from_profile()
	_locale_broadcast_if_changed()
	return err


## 玩家档案文件在磁盘上的完整路径。
func save_profile_disk_path() -> String:
	return _save_manager.profile_disk_path()


## 磁盘上是否已有玩家档案文件。
func save_has_profile() -> bool:
	return _save_manager.has_profile_on_disk()


## 写入某一存档槽的游戏资源（如关卡进度）。返回 [member GDFrameResult.OK] 或 [GDFrameResult.ERR_SAVE_*]。
func save_write_game_resource(slot_id: String, res: Resource) -> StringName:
	var err: StringName = _save_manager.write_game_resource(slot_id, res)
	signal_gdframe_game_save_written.emit(slot_id, err)
	return err


## 读取某一存档槽。返回 [code]{ "resource", "error" }[/code]；用 [method GDFrameResult.read_resource] / [method GDFrameResult.read_error] 取值。
func save_read_game_resource(slot_id: String) -> Dictionary:
	return _save_manager.read_game_resource(slot_id)


## 是否存在该存档槽文件。
func save_has_game_slot(slot_id: String) -> bool:
	return _save_manager.has_game_slot(slot_id)


## 删除某一存档槽文件（含残留 [code].tmp[/code]）。返回 [member GDFrameResult.OK] 或 [GDFrameResult.ERR_SAVE_*]。
func save_delete_game_slot(slot_id: String) -> StringName:
	var err: StringName = _save_manager.delete_game_resource(slot_id)
	signal_gdframe_game_save_deleted.emit(slot_id, err)
	return err


## 多存档文件所在目录。
func save_slots_directory() -> String:
	return _save_manager.get_slots_dir()


## 槽位 meta 目录（[code]user://gdframe/slots/meta/[/code]；格式与槽位存档相同，见 [code]GDFrameSlotMetaResource[/code]）。
func save_slot_meta_directory() -> String:
	return _save_manager.get_slot_meta_dir()


## 列出磁盘上已有存档槽 id（扫描 [code]slots/[/code] 下正式档，不含 sidecar）。
func save_list_slot_ids() -> Array[String]:
	return _save_manager.list_slot_ids()


## 槽位存档文件最后修改时间（Unix 秒）；无存档或非法 id 为 [code]0[/code]。
func save_slot_last_modified_unix(slot_id: String) -> int:
	return _save_manager.slot_last_modified_unix(slot_id)


## 槽位摘要，供选档 UI 列表展示。字段：[code]exists[/code]、[code]slot_id[/code]、[code]modified_unix[/code]、[code]label[/code]、[code]play_time_sec[/code]、[code]chapter[/code]、[code]thumbnail_path[/code]。
func save_slot_summary(slot_id: String) -> Dictionary:
	return _save_manager.slot_summary(slot_id)


## 写入槽位 sidecar meta（[code]slots/meta/{slot_id}{.tres|.res}[/code]，[code]GDFrameSlotMetaResource[/code]）。非法 id 返回 [member GDFrameResult.ERR_SAVE_SLOT_ID_INVALID]。
func save_write_slot_meta(slot_id: String, meta: Dictionary) -> StringName:
	return _save_manager.write_slot_meta(slot_id, meta)


## 从槽位存档 Resource 提取 [code]slot_label[/code] 等字段并写入 meta sidecar。无存档返回 [member GDFrameResult.ERR_SAVE_SLOT_NOT_FOUND]。
func save_rebuild_slot_meta_from_save(slot_id: String) -> StringName:
	return _save_manager.rebuild_slot_meta_from_save(slot_id)


## 存档文件扩展名（来自配置）。
func save_file_extension() -> String:
	return _config.get_save_extension()


# =============================================================================
# Settings
# =============================================================================

## 当前显示模式：[code]windowed[/code]、[code]maximized[/code]、[code]borderless[/code]、[code]exclusive[/code]。
func settings_get_display_mode() -> String:
	return _settings.get_display_mode()


## 设置显示模式（仅内存与引擎；落盘请 [code]save_flush()[/code]）。
func settings_set_display_mode(mode: String) -> void:
	_settings.set_display_mode(mode)


## 窗口化模式下的窗口尺寸（像素）。
func settings_get_window_size() -> Vector2i:
	return _settings.get_window_size()


## 设置窗口尺寸（仅 [code]windowed[/code] 时生效；落盘请 [code]save_flush()[/code]）。
func settings_set_window_size(size: Vector2i) -> void:
	_settings.set_window_size(size)


## 设置界面显示模式下拉项（`key` 为翻译键，`mode` 为 [code]settings_get/set_display_mode[/code] 取值）。
func settings_display_mode_options() -> Array[Dictionary]:
	return GDFrameSettingsManager.display_mode_options()


## 是否窗口化显示模式（仅该模式下窗口大小设置生效）。
func settings_is_windowed_display_mode(display_mode: String = "") -> bool:
	var mode: String = display_mode if not display_mode.is_empty() else settings_get_display_mode()
	return GDFrameSettingsManager.is_windowed_display_mode(mode)


## 窗口化可选尺寸（当前屏幕可用区域为上限，按比例与常见高度生成；应用时会 snap 到最近档位）。
func settings_window_size_options() -> Array[Vector2i]:
	return GDFrameSettingsManager.window_size_options()


## 将窗口尺寸 snap 到 [method settings_window_size_options] 最近档位（不超过当前屏幕可用区域）。
func settings_snap_window_size(size: Vector2i) -> Vector2i:
	return GDFrameSettingsManager.snap_window_size(size)


## 设置界面语言选项（首项 [code]automatic[/code]；其余来自 [code]TranslationServer.get_loaded_locales()[/code]）。
func settings_locale_options() -> PackedStringArray:
	return GDFrameSettingsManager.locale_options()


## 设置界面语言项显示名（[code]automatic[/code] 与各 locale 自称均内置处理）。
func settings_locale_display_name(locale_code: String) -> String:
	return GDFrameSettingsManager.locale_display_name(locale_code)


## 是否开启垂直同步。
func settings_is_vsync_enabled() -> bool:
	return _settings.is_vsync_enabled()


## 设置垂直同步（仅内存与引擎；落盘请 [code]save_flush()[/code]）。
func settings_set_vsync_enabled(enabled: bool) -> void:
	_settings.set_vsync_enabled(enabled)


## 仅预览显示模式与窗口尺寸，不写档案（设置界面拖动时用）。
func settings_preview_display(display_mode: String, window_size: Vector2i) -> void:
	_settings.preview_display(display_mode, window_size)


## 仅预览垂直同步，不写档案。
func settings_preview_vsync(enabled: bool) -> void:
	_settings.preview_vsync(enabled)


## 默认设置字典（含 [code]bus_linear[/code]、[code]bus_muted[/code]；含已安装扩展总线默认值）。
func settings_default_snapshot() -> Dictionary:
	var modules: Array[Script] = GDFrameExtBootstrap.get_modules()
	return GDFrameSettingsManager.default_settings(
		ExtRuntime.default_bus_volumes(modules),
		ExtRuntime.default_bus_muted(modules),
	)


## 从档案重新应用所有设置到引擎（含总线音量/静音；预览取消时亦调用）。
func settings_apply() -> void:
	_settings.apply_from_profile()
	audio_apply_from_profile()
	_locale_broadcast_if_changed()


# =============================================================================
# Game pause
# =============================================================================

## 压入一层暂停（[param reason] 非空；同 reason 可嵌套计数）。栈从空→非空时同步 [code]get_tree().paused[/code] 与 [code]audio_set_paused[/code]。
func pause_push(reason: StringName) -> void:
	_pause.push(reason)


## 弹出一层 [param reason]；栈仍非空则保持暂停。
func pause_pop(reason: StringName) -> void:
	_pause.pop(reason)


## 下一帧再 [method pause_pop]（关闭 UI 等同帧还焦时避免竞态）。
func pause_pop_deferred(reason: StringName) -> void:
	call_deferred(&"_deferred_pause_pop", reason)


func _deferred_pause_pop(reason: StringName) -> void:
	pause_pop(reason)


## 清空暂停栈；[param reason] 非空时仅移除该 reason 的全部计数。
func pause_clear(reason: StringName = &"") -> void:
	_pause.clear(reason)


## 暂停栈是否非空（等价于当前是否应暂停游戏世界）。
func pause_is_active() -> bool:
	return _pause.is_active()


## 暂停栈总深度（各 reason 计数之和）。
func pause_depth() -> int:
	return _pause.depth()


## 单层快捷：[code]true[/code] = 尚未暂停时 [method pause_push][code](&"game_set_paused")[/code]；[code]false[/code] = 仅 [method pause_pop][code](&"game_set_paused")[/code]。多层场景请直接用 [code]pause_push/pop[/code]。
func game_set_paused(paused: bool) -> void:
	if paused:
		if not pause_is_active():
			pause_push(&"game_set_paused")
	else:
		pause_pop(&"game_set_paused")


## 下一帧再 [method game_set_paused]（关闭 UI 等需 defer 时）。
func game_set_paused_deferred(paused: bool) -> void:
	call_deferred(&"_deferred_game_set_paused", paused)


func _deferred_game_set_paused(paused: bool) -> void:
	game_set_paused(paused)


func _apply_game_paused(paused: bool) -> void:
	get_tree().paused = paused
	audio_set_paused(paused)


## 当前语言代码。
func settings_get_locale() -> String:
	return _settings.get_locale()


## 设置语言（仅内存与引擎；落盘请 [code]save_flush()[/code]）。
func settings_set_locale(locale_code: String) -> void:
	_settings.set_locale(locale_code)
	_locale_broadcast_if_changed()


## 仅预览语言，不写档案。
func settings_preview_locale(locale_code: String) -> void:
	_settings.preview_locale(locale_code)
	_locale_broadcast_if_changed()


# =============================================================================
# Audio
# =============================================================================

## 设置某总线音量（线性 0~1，仅内存与引擎；落盘请 [code]save_flush()[/code]）。
func audio_set_bus_volume_linear(bus_name: StringName, linear: float) -> void:
	_audio.set_bus_volume_linear(bus_name, linear)


## 预览总线听感音量（[param muted] 为 [code]true[/code] 时传 [code]0[/code]），不写档案。
func audio_preview_bus_effective(bus_name: StringName, linear: float, muted: bool) -> void:
	_audio.preview_bus_effective(bus_name, linear, muted)


## 默认各总线音量字典（含已安装扩展总线）。
func audio_default_bus_volumes() -> Dictionary:
	return ExtRuntime.default_bus_volumes(GDFrameExtBootstrap.get_modules())


## 音频子系统根节点（[code]GDFrameAudioRoot[/code]；BGM/SFX 与扩展播放器挂载于此）。
func audio_get_root() -> Node:
	return _audio.get_root()


## 读取某总线当前音量（线性）。
func audio_get_bus_volume_linear(bus_name: StringName) -> float:
	return _audio.get_bus_volume_linear(bus_name)


## 读取某总线是否静音（档案值；听感静音时 [method audio_get_bus_volume_linear] 仍返回滑块值）。
func audio_get_bus_muted(bus_name: StringName) -> bool:
	return _audio.get_bus_muted(bus_name)


## 设置某总线静音并立即应用听感（写入档案内存；落盘请 [code]save_flush()[/code]）。
func audio_set_bus_muted(bus_name: StringName, muted: bool) -> void:
	_audio.set_bus_muted(bus_name, muted)


## 默认各总线静音字典（含已安装扩展总线）。
func audio_default_bus_muted() -> Dictionary:
	return ExtRuntime.default_bus_muted(GDFrameExtBootstrap.get_modules())


## 从档案应用所有总线音量（含扩展总线）。
func audio_apply_from_profile() -> void:
	_audio.apply_from_profile(ExtRuntime.collect_extra_bus_names(GDFrameExtBootstrap.get_modules()))


## 确保总线存在并按档案应用听感音量（扩展总线用）。
func audio_ensure_bus_apply_from_profile(bus_name: StringName) -> void:
	_audio.ensure_and_apply_bus_from_profile(bus_name)


## 播放 BGM。[param opts] 可选：[code]loop[/code]、[code]from_position[/code]、[code]crossfade_sec[/code]、[code]pitch_scale[/code]、[code]loop_start_sec[/code]、[code]loop_end_sec[/code]（A～B 区间循环）。
func audio_play_bgm(stream: AudioStream, opts: Dictionary = {}) -> void:
	_audio.play_bgm(stream, opts)


## 同 [method audio_play_bgm]，[code]await[/code] 至交叉淡入结束（无淡入 / 同曲跳过则立即返回）。
func audio_await_play_bgm(stream: AudioStream, opts: Dictionary = {}) -> void:
	await _audio.await_play_bgm(stream, opts)


## 停止背景音乐（仅发起，不等待）。[param fade_out_sec]：[code]0[/code] 立刻停；[code]>0[/code] 淡出；[code]-1[/code] 使用 [member GDFrameConfig.audio_bgm_fade_out_sec]。
func audio_stop_bgm(fade_out_sec: float = 0.0) -> void:
	_audio.stop_bgm(fade_out_sec)


## 同 [method audio_stop_bgm]，[code]await[/code] 至淡出结束（无淡出则立即返回）。
func audio_await_stop_bgm(fade_out_sec: float = 0.0) -> void:
	await _audio.await_stop_bgm(fade_out_sec)


## 预加载 stream 副本（整曲 loop 或 WAV A～B 区间），减少首次播放卡顿。
func audio_preload_stream(stream: AudioStream, opts: Dictionary = {}) -> void:
	_audio.preload_stream(stream, opts)


## 当前 BGM 播放器音量比例（[code]0~1[/code]；不存档）。未播放时仍为最近一次目标值。
func audio_get_bgm_volume_linear() -> float:
	return _audio.get_bgm_volume_linear()


## 当前逻辑 BGM stream（[code]stop[/code] 后为 [code]null[/code]）。
func audio_get_bgm_stream() -> AudioStream:
	return _audio.get_bgm_stream()


## 是否有 BGM 正在播放。
func audio_is_bgm_playing() -> bool:
	return _audio.is_bgm_playing()


## 当前是否启用 A～B 区间循环。
func audio_has_bgm_loop_region() -> bool:
	return _audio.has_bgm_loop_region()


## 当前 active BGM 播放位置（秒）；未播放时为 [code]0[/code]。
func audio_get_bgm_playback_position() -> float:
	return _audio.get_bgm_playback_position()


## 当前 active BGM [member AudioStreamPlayer.pitch_scale]；未播放时返回最近一次 [code]play_bgm[/code] 的 pitch。
func audio_get_bgm_pitch_scale() -> float:
	return _audio.get_bgm_pitch_scale()


## 立即设置当前逻辑曲目的 pitch（仅 active 播放器；交叉淡入中的 incoming 不受影响）。会取消 pitch 过渡。
func audio_set_bgm_pitch_scale(pitch_scale: float) -> void:
	_audio.set_bgm_pitch_scale(pitch_scale)


## 发起 BGM pitch 过渡（不等待）；[param duration_sec] [code]<=0[/code] 时等同 [method audio_set_bgm_pitch_scale]。
func audio_tween_bgm_pitch_scale(pitch_scale: float, duration_sec: float) -> void:
	_audio.tween_bgm_pitch_scale(pitch_scale, duration_sec)


## 同 [method audio_tween_bgm_pitch_scale]，[code]await[/code] 至过渡结束。
func audio_await_tween_bgm_pitch_scale(pitch_scale: float, duration_sec: float) -> void:
	await _audio.await_tween_bgm_pitch_scale(pitch_scale, duration_sec)


## 立即设置 BGM 播放器音量比例（[code]0~1[/code]；仅正在播放的 BGM）。不影响 Music 总线设置。
func audio_set_bgm_volume_linear(linear: float) -> void:
	_audio.set_bgm_volume_linear(linear)


## 发起 BGM 播放器音量过渡（不等待）；[param duration_sec] [code]<=0[/code] 时等同 [method audio_set_bgm_volume_linear]。
func audio_tween_bgm_volume_linear(linear: float, duration_sec: float) -> void:
	_audio.tween_bgm_volume_linear(linear, duration_sec)


## 同 [method audio_tween_bgm_volume_linear]，[code]await[/code] 至过渡结束。
func audio_await_tween_bgm_volume_linear(linear: float, duration_sec: float) -> void:
	await _audio.await_tween_bgm_volume_linear(linear, duration_sec)


## 暂停 / 恢复 BGM、SFX 与已注册 service 的 [code]set_audio_paused[/code]；[method audio_play_ui_sfx] 不受拦截。
func audio_set_paused(paused: bool) -> void:
	_audio.set_audio_paused(paused)
	_broadcast_audio_paused_to_services(paused)


## 是否处于 [method audio_set_paused] 暂停状态。
func audio_is_paused() -> bool:
	return _audio.is_audio_paused()


## 播放一次性音效；返回 [code]false[/code] 表示被限流丢弃。[param opts]：[code]bus[/code]、[code]key[/code]、[code]pitch_scale[/code]、[code]volume_linear[/code]。
func audio_play_sfx(stream: AudioStream, opts: Dictionary = {}) -> bool:
	return _audio.play_sfx(stream, opts)


## 播放界面音效（Polyphonic，走 [code]UI[/code] 总线；不受 [method audio_set_paused] 拦截）。
## [param opts]：[code]volume_linear[/code]、[code]pitch_scale[/code]、[code]from_position[/code]；复音满时返回 [code]false[/code]。
func audio_play_ui_sfx(stream: AudioStream, opts: Dictionary = {}) -> bool:
	return _audio.play_ui_sfx(stream, opts)


## 在 [param position] 播放 2D 空间音效；opts 同 [method audio_play_sfx]。
func audio_play_sfx_2d(stream: AudioStream, position: Vector2, opts: Dictionary = {}) -> bool:
	return _audio.play_sfx_2d(stream, position, opts)


## 在 [param position] 播放 3D 空间音效；opts 同 [method audio_play_sfx]。
func audio_play_sfx_3d(stream: AudioStream, position: Vector3, opts: Dictionary = {}) -> bool:
	return _audio.play_sfx_3d(stream, position, opts)


## 停止所有 SFX 池内播放（过场 / 读档时清场；不含界面 Polyphonic）。
func audio_stop_all_sfx() -> void:
	_audio.stop_all_sfx()


## 停止全部界面音效（[method audio_play_ui_sfx]；不影响 SFX 池）。
func audio_stop_all_ui_sfx() -> void:
	_audio.stop_all_ui_sfx()


## 停止指定 [param key] 的 SFX（[code]play_sfx[/code] opts.key）。
func audio_stop_sfx_by_key(key: StringName) -> void:
	_audio.stop_sfx_by_key(key)


## 停止指定总线上的 SFX 池播放（不含 [code]UI[/code] Polyphonic）。
func audio_stop_sfx_on_bus(bus_name: StringName) -> void:
	_audio.stop_sfx_on_bus(bus_name)


## 设置某总线 SFX 并发上限；[code]0[/code] 表示该总线不限制。
func audio_set_sfx_max_per_bus(bus_name: StringName, max_count: int) -> void:
	_audio.set_sfx_max_per_bus(bus_name, max_count)


## 设置同一 [code]key[/code] SFX 并发上限；[code]0[/code] 不单独限制。
func audio_set_sfx_max_per_key(max_count: int) -> void:
	_audio.set_sfx_max_per_key(max_count)


# =============================================================================
# FSM
# =============================================================================

## 是否已预加载指定状态机的 Registry（[code]fsm_bind[/code] 前可选检查）。
func fsm_is_machine_loaded(machine_id: StringName) -> bool:
	if _fsm == null:
		return false
	return _fsm.is_machine_loaded(machine_id)


## 预加载 Registry；建议在批量预加载阶段调用，避免首次 [code]fsm_bind[/code] 同帧读盘卡顿。
func fsm_preload(machine_id: StringName) -> void:
	_ensure_fsm().preload_machine(machine_id)


## 预加载全部 FSM Registry；根目录见 [member GDFrameConfig.FSM_ROOT]。
func fsm_preload_all() -> void:
	_ensure_fsm().preload_all_machines()


## 给节点绑定一台状态机，返回句柄供状态脚本使用。
## 在宿主 [code]_physics_process[/code] 里调 [code]fsm_physics_process[/code] 驱动。
func fsm_bind(machine_id: StringName, initial_state: StringName, owner: Node) -> GDFrameFsmHandle:
	return _ensure_fsm().bind(machine_id, initial_state, owner)


## 驱动宿主上 FSM 状态的 [code]_process[/code]。
func fsm_process(owner: Node, delta: float) -> void:
	_fsm_tick(owner, &"process", delta)


## 驱动宿主上 FSM 状态的 [code]_physics_process[/code]（推荐）。
func fsm_physics_process(owner: Node, delta: float) -> void:
	_fsm_tick(owner, &"physics_process", delta)


## 把输入事件分发给宿主上的 FSM 当前状态。
func fsm_dispatch_input(owner: Node, event: InputEvent) -> void:
	_fsm_tick(owner, &"dispatch_input", event)


## 取宿主上已绑定的 FSM 句柄；若该 [param owner] 尚未 [code]fsm_bind[/code]，则返回 [code]null[/code]。
func fsm_handle(owner: Node, machine_id: StringName) -> GDFrameFsmHandle:
	if _fsm == null:
		return null
	return _fsm.handle_for(owner, machine_id)
