extends RefCounted
class_name GDFrameSettingsManager

# =============================================================================
# Constants
# =============================================================================

const LOCALE_AUTOMATIC: String = "automatic"
const LOCALE_NAME_KEY: String = "LOCALE_NAME"

const DISPLAY_MODE_WINDOWED: String = "windowed"
const DISPLAY_MODE_MAXIMIZED: String = "maximized"
const DISPLAY_MODE_BORDERLESS: String = "borderless"
const DISPLAY_MODE_EXCLUSIVE: String = "exclusive"

const _VALID_DISPLAY_MODES: PackedStringArray = [
	DISPLAY_MODE_WINDOWED,
	DISPLAY_MODE_MAXIMIZED,
	DISPLAY_MODE_BORDERLESS,
	DISPLAY_MODE_EXCLUSIVE,
]

## [code]0[/code] 表示不限制帧率（[member Engine.max_fps]）。可选项见 [member GDFrameConfig.max_fps_options]。
const MAX_FPS_UNLIMITED: int = 0
const _EXT_RUNTIME: Script = preload("res://addons/gdframe/runtime/ext/ext_runtime.gd")

# =============================================================================
# State
# =============================================================================

var _save: GDFrameSaveManager
var locale_changed_hook: Callable = Callable()
var audio_apply_hook: Callable = Callable()
## 档案要全屏，但浏览器只允许在玩家输入回调里进入全屏。
var _web_fullscreen_pending: bool = false


# =============================================================================
# Init & apply
# =============================================================================

func _init(save: GDFrameSaveManager) -> void:
	_save = save


## 项目设计分辨率（[code]display/window/size/viewport_*[/code]）。
static func project_viewport_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")),
	)


## 窗口尺寸列表所用宽高比：[code]stretch/aspect=expand[/code] 跟屏幕；否则跟项目设计分辨率。
static func window_size_aspect(screen: int = -1) -> float:
	if str(ProjectSettings.get_setting("display/window/stretch/aspect")) != "expand":
		var project_size: Vector2i = project_viewport_size()
		return float(project_size.x) / float(maxi(project_size.y, 1))
	if screen < 0:
		screen = reference_screen()
	var full: Vector2i = DisplayServer.screen_get_size(screen)
	return float(maxi(full.x, 1)) / float(maxi(full.y, 1))


## 默认窗口化分辨率：当前屏幕可用区按 [member GDFrameConfig.window_size_scale_steps] 首档缩小。
static func default_window_size() -> Vector2i:
	var screen: int = reference_screen()
	var usable: Vector2i = usable_size_for_screen(screen)
	if usable.x < 1 or usable.y < 1:
		return project_viewport_size()
	var max_fitted: Vector2i = _fit_size_to_aspect(usable, window_size_aspect(screen))
	return _scaled_fitted_size(max_fitted, _default_window_scale())


static func _frame_config() -> GDFrameConfig:
	return load(GDFrameConfig.PATH) as GDFrameConfig


static func _default_window_scale() -> float:
	var steps: Array[float] = _frame_config().window_size_scale_steps
	if steps.is_empty():
		return 1.0
	return steps[0]


static func default_settings(
	bus_linear: Dictionary = GDFrameAudioManager.default_bus_volumes(),
	bus_muted: Dictionary = GDFrameAudioManager.default_bus_muted(),
) -> Dictionary[String, Variant]:
	var size: Vector2i = (
		project_viewport_size()
		if OS.has_feature("web") or OS.has_feature("android")
		else default_window_size()
	)
	return {
		"display_mode": DISPLAY_MODE_BORDERLESS,
		"window_width": size.x,
		"window_height": size.y,
		"vsync_enabled": true,
		"max_fps": MAX_FPS_UNLIMITED,
		"locale": LOCALE_AUTOMATIC,
		"bus_linear": bus_linear.duplicate(),
		"bus_muted": bus_muted.duplicate(),
	}


## 将显示相关字段写成 [method default_settings]（新建档案用）。
static func apply_display_defaults(settings: GDFrameSettingsData) -> void:
	if OS.has_feature("android"):
		return
	var d: Dictionary[String, Variant] = default_settings()
	settings.display_mode = str(d["display_mode"])
	if OS.has_feature("web"):
		return
	settings.window_width = int(d["window_width"])
	settings.window_height = int(d["window_height"])


## [param apply_window] 为 [code]false[/code] 时不改窗口，桌面冷启动先保持项目里的无边框启动图尺寸。
func apply_from_profile(apply_window: bool = true) -> void:
	_apply_locale(get_locale())
	var s: GDFrameSettingsData = _settings()
	_apply_max_fps(s.max_fps)
	if OS.has_feature("android"):
		_apply_vsync(s.vsync_enabled)
		return
	s.display_mode = _normalize_display_mode(s.display_mode)
	if OS.has_feature("web"):
		if apply_window:
			_apply_web_display(s.display_mode, false)
		return
	if apply_window:
		_apply_display(s.display_mode, _window_size_from_settings(s))
	_apply_vsync(s.vsync_enabled)


## 冷启动的无边框图显示结束后，套用档案里的窗口模式与尺寸。
func apply_startup_window() -> void:
	if OS.has_feature("android"):
		return
	var s: GDFrameSettingsData = _settings()
	s.display_mode = _normalize_display_mode(s.display_mode)
	if OS.has_feature("web"):
		_apply_web_display(s.display_mode, false)
		return
	_apply_display(s.display_mode, _window_size_from_settings(s))


## 应用档案中的显示与语言，并回调音频与语言广播。
func apply() -> void:
	apply_from_profile()
	if audio_apply_hook.is_valid():
		audio_apply_hook.call()
	_notify_locale()


func default_snapshot() -> Dictionary:
	var modules: Array[Script] = _EXT_RUNTIME.get_modules()
	var merged: Dictionary = _EXT_RUNTIME.merge_extra_bus_defaults(
		{
			"bus_linear": GDFrameAudioManager.default_bus_volumes(),
			"bus_muted": GDFrameAudioManager.default_bus_muted(),
		},
		modules,
	)
	return default_settings(merged["bus_linear"], merged["bus_muted"])


# =============================================================================
# Display
# =============================================================================

func get_display_mode() -> String:
	return _normalize_display_mode(_settings().display_mode)


func set_display_mode(mode: String) -> void:
	if OS.has_feature("android"):
		return
	var s: GDFrameSettingsData = _settings()
	s.display_mode = _normalize_display_mode(mode)
	if OS.has_feature("web"):
		_apply_web_display(s.display_mode, true)
		return
	_apply_display(s.display_mode, _window_size_from_settings(s))


func get_window_size() -> Vector2i:
	return _window_size_from_settings(_settings())


func set_window_size(size: Vector2i) -> void:
	if OS.has_feature("web") or OS.has_feature("android"):
		return
	var s: GDFrameSettingsData = _settings()
	var mode: String = _normalize_display_mode(s.display_mode)
	var normalized: Vector2i = _normalize_window_size(size)
	s.window_width = normalized.x
	s.window_height = normalized.y
	_apply_display(mode, normalized)


func preview_display(display_mode: String, window_size: Vector2i) -> void:
	if OS.has_feature("android"):
		return
	var mode: String = _normalize_display_mode(display_mode)
	if OS.has_feature("web"):
		_apply_web_display(mode, true)
		return
	_apply_display(mode, _normalize_window_size(window_size))


static func display_mode_to_window_mode(display_mode: String) -> DisplayServer.WindowMode:
	match _normalize_display_mode(display_mode):
		DISPLAY_MODE_MAXIMIZED:
			return DisplayServer.WINDOW_MODE_MAXIMIZED
		DISPLAY_MODE_BORDERLESS:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		DISPLAY_MODE_EXCLUSIVE:
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


## 将引擎窗口模式映射回设置项取值（标题栏最大化 / 还原时同步下拉用）。
static func window_mode_to_display_mode(window_mode: DisplayServer.WindowMode) -> String:
	match window_mode:
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return DISPLAY_MODE_MAXIMIZED
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return DISPLAY_MODE_BORDERLESS
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return DISPLAY_MODE_EXCLUSIVE
		_:
			return DISPLAY_MODE_WINDOWED


## 是否为窗口化显示模式。
static func is_windowed_display_mode(display_mode: String) -> bool:
	return _normalize_display_mode(display_mode) == DISPLAY_MODE_WINDOWED


static func display_mode_options() -> Array[Dictionary]:
	if OS.has_feature("web"):
		return [
			{"key": "DISPLAY_MODE_WEB_WINDOWED", "mode": DISPLAY_MODE_WINDOWED},
			{"key": "DISPLAY_MODE_EXCLUSIVE", "mode": DISPLAY_MODE_BORDERLESS},
		]
	return [
		{"key": "DISPLAY_MODE_WINDOWED", "mode": DISPLAY_MODE_WINDOWED},
		{"key": "DISPLAY_MODE_MAXIMIZED", "mode": DISPLAY_MODE_MAXIMIZED},
		{"key": "DISPLAY_MODE_BORDERLESS", "mode": DISPLAY_MODE_BORDERLESS},
		{"key": "DISPLAY_MODE_EXCLUSIVE", "mode": DISPLAY_MODE_EXCLUSIVE},
	]


## 设置界面可选分辨率：比例见 [method window_size_aspect]，档位见 [member GDFrameConfig.window_size_scale_steps] 与 [member GDFrameConfig.common_window_heights]。不超过可用区域。设计分辨率放得下时列入。
static func window_size_options() -> Array[Vector2i]:
	var cfg: GDFrameConfig = _frame_config()
	var screen: int = reference_screen()
	var usable: Vector2i = usable_size_for_screen(screen)
	var aspect: float = window_size_aspect(screen)
	var seen: Dictionary[String, bool] = {}
	var out: Array[Vector2i] = []
	var max_fitted: Vector2i = _fit_size_to_aspect(usable, aspect)

	_add_unique_size(out, seen, max_fitted)
	for scale: float in cfg.window_size_scale_steps:
		_add_unique_size(out, seen, _scaled_fitted_size(max_fitted, scale))
	for height: int in cfg.common_window_heights:
		if height > usable.y:
			continue
		var width: int = int(round(float(height) * aspect))
		if width > usable.x:
			continue
		_add_unique_size(out, seen, Vector2i(width, height))

	var project_size: Vector2i = project_viewport_size()
	if project_size.x <= usable.x and project_size.y <= usable.y:
		_add_unique_size(out, seen, project_size)

	if out.is_empty():
		out.append(default_window_size())
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y > b.x * b.y)
	return out


## 在 [param max_size] 内取最大且符合 [param aspect] 的尺寸。
static func _fit_size_to_aspect(max_size: Vector2i, aspect: float) -> Vector2i:
	if max_size.x < 1 or max_size.y < 1:
		return _frame_config().min_window_size
	if float(max_size.x) / float(max_size.y) >= aspect:
		var height: int = max_size.y
		return Vector2i(maxi(1, int(round(float(height) * aspect))), height)
	var width: int = max_size.x
	return Vector2i(width, maxi(1, int(round(float(width) / aspect))))


static func _scaled_fitted_size(fitted: Vector2i, scale: float) -> Vector2i:
	var min_size: Vector2i = _frame_config().min_window_size
	return Vector2i(
		maxi(min_size.x, int(floor(float(fitted.x) * scale))),
		maxi(min_size.y, int(floor(float(fitted.y) * scale))),
	)


static func reference_screen() -> int:
	var screen: int = DisplayServer.window_get_current_screen()
	if screen < 0:
		return DisplayServer.get_primary_screen()
	return screen


static func usable_size_for_screen(screen: int = -1) -> Vector2i:
	if screen < 0:
		screen = reference_screen()
	var max_size: Vector2i = DisplayServer.screen_get_usable_rect(screen).size
	if max_size.x < 1 or max_size.y < 1:
		return DisplayServer.screen_get_size(screen)
	return max_size


static func clamp_to_usable(size: Vector2i, screen: int = -1) -> Vector2i:
	var max_size: Vector2i = usable_size_for_screen(screen)
	return Vector2i(mini(size.x, max_size.x), mini(size.y, max_size.y))


static func _add_unique_size(out: Array[Vector2i], seen: Dictionary[String, bool], size: Vector2i) -> void:
	var guarded: Vector2i = _guard_windowed_client_size(size)
	var min_size: Vector2i = _frame_config().min_window_size
	if guarded.x < min_size.x or guarded.y < min_size.y:
		return
	var key: String = "%d,%d" % [guarded.x, guarded.y]
	if seen.has(key):
		return
	seen[key] = true
	out.append(guarded)


# =============================================================================
# VSync
# =============================================================================

func is_vsync_enabled() -> bool:
	return _settings().vsync_enabled


func set_vsync_enabled(enabled: bool) -> void:
	if OS.has_feature("web"):
		return
	_settings().vsync_enabled = enabled
	_apply_vsync(enabled)


func preview_vsync(enabled: bool) -> void:
	if OS.has_feature("web"):
		return
	_apply_vsync(enabled)


## 帧率上限可选项，见 [member GDFrameConfig.max_fps_options]。
static func max_fps_options() -> Array[int]:
	return _frame_config().max_fps_options


func get_max_fps() -> int:
	return _normalize_max_fps(_settings().max_fps)


func set_max_fps(value: int) -> void:
	var fps: int = _normalize_max_fps(value)
	_settings().max_fps = fps
	_apply_max_fps(fps)


func preview_max_fps(value: int) -> void:
	_apply_max_fps(value)


# =============================================================================
# Locale
# =============================================================================

## 项目已注册语言；空则回退 [code]internationalization/locale/fallback[/code]。
static func project_locales() -> PackedStringArray:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	if not locales.is_empty():
		return locales
	var fallback: String = _project_fallback_locale()
	if fallback.is_empty():
		return PackedStringArray()
	return PackedStringArray([fallback])


## [code]automatic[/code] → [code]UI_OPTIONS_LOCALE_AUTOMATIC[/code]；其余读 [member LOCALE_NAME_KEY]。
static func locale_display_name(locale_code: String) -> String:
	var code: String = locale_code.strip_edges()
	if code.is_empty() or code == LOCALE_AUTOMATIC:
		return String(TranslationServer.translate("UI_OPTIONS_LOCALE_AUTOMATIC"))
	var name: String = _message_in_locale(LOCALE_NAME_KEY, code)
	return name if not name.is_empty() else code


## 首项 [code]automatic[/code]，其余为 [method project_locales]。
static func locale_options() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([LOCALE_AUTOMATIC])
	out.append_array(project_locales())
	return out


static func _message_in_locale(key: String, locale_code: String) -> String:
	# 精确匹配 locale。
	for translation: Translation in TranslationServer.find_translations(locale_code, true):
		var message: String = translation.get_message(key)
		if not message.is_empty():
			return message
	return ""


func get_locale() -> String:
	return _normalize_stored_locale(_settings().locale)


func set_locale(locale_code: String) -> void:
	var stored: String = _normalize_stored_locale(locale_code)
	_settings().locale = stored
	_apply_locale(stored)
	_notify_locale()


func preview_locale(locale_code: String) -> void:
	_apply_locale(_normalize_stored_locale(locale_code))
	_notify_locale()


# =============================================================================
# Private
# =============================================================================

func _notify_locale() -> void:
	if locale_changed_hook.is_valid():
		locale_changed_hook.call()


func _settings() -> GDFrameSettingsData:
	return _save.get_profile().settings


func _window_size_from_settings(s: GDFrameSettingsData) -> Vector2i:
	return _normalize_window_size(Vector2i(s.window_width, s.window_height))


## Web 只有窗口化与浏览器全屏。全屏必须发生在玩家输入回调里，启动时先记下，等下一次按键或点击。
func _apply_web_display(display_mode: String, from_input: bool) -> void:
	if display_mode != DISPLAY_MODE_BORDERLESS:
		_web_fullscreen_pending = false
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		_web_fullscreen_pending = false
		return
	if from_input:
		_web_fullscreen_pending = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	_web_fullscreen_pending = true


func apply_pending_web_fullscreen(event: InputEvent) -> void:
	if not _web_fullscreen_pending or not event.is_pressed() or event.is_echo():
		return
	var gesture: bool = (
		event is InputEventMouseButton
		or event is InputEventScreenTouch
		or event is InputEventKey
		or event is InputEventJoypadButton
	)
	if not gesture:
		return
	_web_fullscreen_pending = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _apply_display(display_mode: String, window_size: Vector2i) -> void:
	var mode: DisplayServer.WindowMode = display_mode_to_window_mode(display_mode)
	var current: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		# 全屏期间 window_set_size 无效，须先切模式再设尺寸。
		var leaving: bool = current != DisplayServer.WINDOW_MODE_WINDOWED
		if leaving:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# 仍无边框时先改客户区，再出标题栏；出框会缩进客户区，须再写一次尺寸。
		if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
			_place_windowed(window_size, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		_place_windowed(window_size, leaving)
		return
	# 进入非窗口化前写入目标尺寸，供离开时恢复 pre_fs_rect。
	if current == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		current = DisplayServer.WINDOW_MODE_WINDOWED
	if current == DisplayServer.WINDOW_MODE_WINDOWED:
		_place_windowed(window_size, false)
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		if current == DisplayServer.WINDOW_MODE_WINDOWED:
			_place_windowed(window_size, false)
	if current != mode:
		DisplayServer.window_set_mode(mode)


func _place_windowed(window_size: Vector2i, center: bool) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var size_changed: bool = DisplayServer.window_get_size() != window_size
	if size_changed:
		DisplayServer.window_set_size(window_size)
	if center or size_changed:
		_center_window(window_size)


func _center_window(window_size: Vector2i) -> void:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(reference_screen())
	var delta: Vector2i = usable.size - window_size
	var pos: Vector2i = usable.position + Vector2i(delta.x >> 1, delta.y >> 1)
	pos.x = maxi(pos.x, usable.position.x)
	pos.y = maxi(pos.y, usable.position.y)
	DisplayServer.window_set_position(pos)


func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)


func _apply_max_fps(value: int) -> void:
	Engine.max_fps = _normalize_max_fps(value)


static func _normalize_max_fps(value: int) -> int:
	return value if _frame_config().max_fps_options.has(value) else MAX_FPS_UNLIMITED


func _apply_locale(locale_setting: String) -> void:
	if locale_setting == LOCALE_AUTOMATIC:
		TranslationServer.set_locale(_resolve_automatic_locale())
	else:
		TranslationServer.set_locale(_normalize_explicit_locale(locale_setting))


static func _normalize_display_mode(mode: String) -> String:
	var s: String = mode.strip_edges()
	if OS.has_feature("web"):
		return s if s == DISPLAY_MODE_WINDOWED or s == DISPLAY_MODE_BORDERLESS else DISPLAY_MODE_WINDOWED
	return s if s in _VALID_DISPLAY_MODES else DISPLAY_MODE_BORDERLESS


static func _normalize_window_size(size: Vector2i) -> Vector2i:
	var min_size: Vector2i = _frame_config().min_window_size
	if size.x < min_size.x or size.y < min_size.y:
		return default_window_size()
	return _guard_windowed_client_size(clamp_to_usable(size))


## 客户区恰好等于屏幕时会被当成独占全屏，窗口化尺寸须至少少 1px。
static func _guard_windowed_client_size(size: Vector2i, screen: int = -1) -> Vector2i:
	if screen < 0:
		screen = reference_screen()
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	if size != screen_size:
		return size
	var min_size: Vector2i = _frame_config().min_window_size
	var shrunk: Vector2i = clamp_to_usable(
		Vector2i(maxi(min_size.x, screen_size.x - 1), maxi(min_size.y, screen_size.y - 1)),
		screen,
	)
	return _fit_size_to_aspect(shrunk, window_size_aspect(screen))


func _resolve_automatic_locale() -> String:
	var locales: PackedStringArray = project_locales()
	var os_locale: String = OS.get_locale()
	if os_locale in locales:
		return os_locale
	var lang: String = OS.get_locale_language()
	if lang == "zh":
		return "zh_CN"
	for loc: String in locales:
		if loc == lang or loc.begins_with(lang + "_"):
			return loc
	return _project_fallback_locale()


func _normalize_stored_locale(locale_code: String) -> String:
	var s: String = locale_code.strip_edges()
	if s.is_empty() or s == LOCALE_AUTOMATIC:
		return LOCALE_AUTOMATIC
	return s if s in project_locales() else LOCALE_AUTOMATIC


func _normalize_explicit_locale(locale_code: String) -> String:
	var stored: String = _normalize_stored_locale(locale_code)
	if stored != LOCALE_AUTOMATIC:
		return stored
	return _project_fallback_locale()


static func _project_fallback_locale() -> String:
	return String(ProjectSettings.get_setting("internationalization/locale/fallback"))
