extends RefCounted
class_name GDFrameSettingsManager

# =============================================================================
# Constants
# =============================================================================

const LOCALE_AUTOMATIC: String = "automatic"
const LOCALE_NAME_KEY: String = "LOCALE_NAME"
const LOCALE_AUTOMATIC_LABEL_KEY: String = "UI_SETTINGS_LOCALE_AUTOMATIC"

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

const _MIN_WINDOW_SIZE: Vector2i = Vector2i(640, 360)
const _WINDOW_SIZE_SCALE_STEPS: Array[float] = [
	0.9, 0.8, 0.75, 0.67, 0.5,
]
const _COMMON_WINDOW_HEIGHTS: Array[int] = [
	360, 480, 720, 900, 1080, 1200, 1440, 1600, 2160,
]

# =============================================================================
# State
# =============================================================================

var _save: GDFrameSaveManager
var _config: GDFrameConfig

# =============================================================================
# Init & apply
# =============================================================================

func _init(save: GDFrameSaveManager, config: GDFrameConfig) -> void:
	_save = save
	_config = config

static func default_window_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)),
	)

static func default_settings(
	bus_linear: Dictionary = GDFrameAudioManager.default_bus_volumes(),
	bus_muted: Dictionary = GDFrameAudioManager.default_bus_muted(),
) -> Dictionary[String, Variant]:
	var size: Vector2i = default_window_size()
	return {
		"display_mode": DISPLAY_MODE_WINDOWED,
		"window_width": size.x,
		"window_height": size.y,
		"vsync_enabled": true,
		"locale": LOCALE_AUTOMATIC,
		"bus_linear": bus_linear.duplicate(),
		"bus_muted": bus_muted.duplicate(),
	}

func apply_from_profile() -> void:
	_apply_locale(_locale_setting_from_profile())
	var s: GDFrameSettingsData = _settings()
	_apply_display(
		_normalize_display_mode(s.display_mode),
		_normalize_window_size(Vector2i(s.window_width, s.window_height)),
	)
	_apply_vsync(s.vsync_enabled)

# =============================================================================
# Display
# =============================================================================

func get_display_mode() -> String:
	return _normalize_display_mode(_settings().display_mode)

func set_display_mode(mode: String) -> void:
	var s: GDFrameSettingsData = _settings()
	s.display_mode = _normalize_display_mode(mode)
	_apply_display(s.display_mode, _window_size_from_settings(s))

func get_window_size() -> Vector2i:
	return _window_size_from_settings(_settings())

func set_window_size(size: Vector2i) -> void:
	var normalized: Vector2i = _normalize_window_size(size)
	var s: GDFrameSettingsData = _settings()
	s.window_width = normalized.x
	s.window_height = normalized.y
	_apply_display(_normalize_display_mode(s.display_mode), normalized)

func preview_display(display_mode: String, window_size: Vector2i) -> void:
	_apply_display(_normalize_display_mode(display_mode), _normalize_window_size(window_size))

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

static func is_windowed_display_mode(display_mode: String) -> bool:
	return _normalize_display_mode(display_mode) == DISPLAY_MODE_WINDOWED


static func display_mode_options() -> Array[Dictionary]:
	return [
		{"key": "DISPLAY_MODE_WINDOWED", "mode": DISPLAY_MODE_WINDOWED},
		{"key": "DISPLAY_MODE_MAXIMIZED", "mode": DISPLAY_MODE_MAXIMIZED},
		{"key": "DISPLAY_MODE_BORDERLESS", "mode": DISPLAY_MODE_BORDERLESS},
		{"key": "DISPLAY_MODE_EXCLUSIVE", "mode": DISPLAY_MODE_EXCLUSIVE},
	]


## 设置界面可选窗口尺寸：以 [method reference_screen] 可用区域为上限，按缩放比例与常见高度（保持宽高比）生成档位并去重。
static func window_size_options() -> Array[Vector2i]:
	var max_size: Vector2i = usable_size_for_screen(reference_screen())
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	var aspect: float = float(max_size.x) / float(maxi(max_size.y, 1))

	_add_unique_size(out, seen, max_size)

	for scale: float in _WINDOW_SIZE_SCALE_STEPS:
		var scaled: Vector2i = Vector2i(
			maxi(_MIN_WINDOW_SIZE.x, int(floor(float(max_size.x) * scale))),
			maxi(_MIN_WINDOW_SIZE.y, int(floor(float(max_size.y) * scale))),
		)
		_add_unique_size(out, seen, scaled)

	for height: int in _COMMON_WINDOW_HEIGHTS:
		if height > max_size.y:
			continue
		var width: int = mini(int(round(float(height) * aspect)), max_size.x)
		var fitted_height: int = int(round(float(width) / aspect))
		_add_unique_size(out, seen, Vector2i(width, fitted_height))

	var default_size: Vector2i = clamp_to_usable(default_window_size())
	_add_unique_size(out, seen, default_size)

	if out.is_empty():
		out.append(default_size)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y > b.x * b.y)
	return out


## 将 [param size] 对齐到 [method window_size_options] 中不超过可用区域的最接近档位。
static func snap_window_size(size: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = window_size_options()
	if options.is_empty():
		return clamp_to_usable(size)

	var target: Vector2i = clamp_to_usable(size)
	for option: Vector2i in options:
		if option == target:
			return option

	var best: Vector2i = options[options.size() - 1]
	var best_score: int = 0x7FFFFFFF
	for option: Vector2i in options:
		if option.x > target.x or option.y > target.y:
			continue
		var score: int = absi(option.x - target.x) + absi(option.y - target.y)
		if score < best_score:
			best_score = score
			best = option
	return best


static func reference_screen() -> int:
	var screen: int = DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	return screen


static func usable_size_for_screen(screen: int = -1) -> Vector2i:
	if screen < 0:
		screen = reference_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var max_size: Vector2i = usable.size
	if max_size.x < 1 or max_size.y < 1:
		max_size = DisplayServer.screen_get_size(screen)
	return max_size


static func clamp_to_usable(size: Vector2i, screen: int = -1) -> Vector2i:
	var max_size: Vector2i = usable_size_for_screen(screen)
	return Vector2i(mini(size.x, max_size.x), mini(size.y, max_size.y))


static func _add_unique_size(
	out: Array[Vector2i],
	seen: Dictionary,
	size: Vector2i,
) -> void:
	if size.x < _MIN_WINDOW_SIZE.x or size.y < _MIN_WINDOW_SIZE.y:
		return
	var key: String = "%d,%d" % [size.x, size.y]
	if seen.has(key):
		return
	seen[key] = true
	out.append(size)

# =============================================================================
# VSync
# =============================================================================

func is_vsync_enabled() -> bool:
	return _settings().vsync_enabled

func set_vsync_enabled(enabled: bool) -> void:
	var s: GDFrameSettingsData = _settings()
	s.vsync_enabled = enabled
	_apply_vsync(enabled)

func preview_vsync(enabled: bool) -> void:
	_apply_vsync(enabled)


# Locale
# =============================================================================

## 项目已注册语言（[code]TranslationServer.get_loaded_locales()[/code]）；空则回退 [code]internationalization/locale/fallback[/code]。
static func project_locales() -> PackedStringArray:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	if not locales.is_empty():
		return locales
	var fallback: String = String(
		ProjectSettings.get_setting("internationalization/locale/fallback", "zh_CN")
	)
	if fallback.is_empty():
		return PackedStringArray()
	return PackedStringArray([fallback])


## 设置界面语言项显示名：[code]automatic[/code] → [member LOCALE_AUTOMATIC_LABEL_KEY]；其余读 [member LOCALE_NAME_KEY] 对应列，缺失则回退 locale 码。
static func locale_display_name(locale_code: String) -> String:
	var code: String = locale_code.strip_edges()
	if code.is_empty() or code == LOCALE_AUTOMATIC:
		return String(TranslationServer.translate(LOCALE_AUTOMATIC_LABEL_KEY))
	var name: String = _message_in_locale(LOCALE_NAME_KEY, code)
	if name.is_empty():
		return code
	return name


## 设置界面语言选项（首项 [code]automatic[/code]，其余为 [method project_locales]）。
static func locale_options() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append(LOCALE_AUTOMATIC)
	out.append_array(project_locales())
	return out


static func _message_in_locale(key: String, locale_code: String) -> String:
	for translation: Translation in TranslationServer.find_translations(locale_code, false):
		var message: String = translation.get_message(key)
		if not message.is_empty():
			return message
	var fallback: Translation = TranslationServer.get_translation_object(locale_code)
	if fallback != null:
		var message: String = fallback.get_message(key)
		if not message.is_empty():
			return message
	return ""


## 返回档案中的语言设置：[code]automatic[/code] 或已加载 locale 码。

func get_locale() -> String:
	return _locale_setting_from_profile()

func set_locale(locale_code: String) -> void:
	var stored: String = _normalize_stored_locale(locale_code)
	_settings().locale = stored
	_apply_locale(stored)

func preview_locale(locale_code: String) -> void:
	_apply_locale(_normalize_stored_locale(locale_code))

# =============================================================================
# Private
# =============================================================================

func _settings() -> GDFrameSettingsData:
	return _save.get_profile().settings

func _window_size_from_settings(s: GDFrameSettingsData) -> Vector2i:
	return _normalize_window_size(Vector2i(s.window_width, s.window_height))

func _apply_display(display_mode: String, window_size: Vector2i) -> void:
	var mode: DisplayServer.WindowMode = display_mode_to_window_mode(display_mode)
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
		_center_window(window_size)
	else:
		DisplayServer.window_set_mode(mode)

func _center_window(window_size: Vector2i) -> void:
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var pos: Vector2i = usable.position + (usable.size - window_size) / 2
	pos.x = maxi(pos.x, usable.position.x)
	pos.y = maxi(pos.y, usable.position.y)
	DisplayServer.window_set_position(pos)

func _apply_vsync(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply_locale(locale_setting: String) -> void:
	if locale_setting == LOCALE_AUTOMATIC:
		TranslationServer.set_locale(_resolve_automatic_locale())
	else:
		TranslationServer.set_locale(_normalize_explicit_locale(locale_setting))

static func _normalize_display_mode(mode: String) -> String:
	var s: String = mode.strip_edges()
	if s in _VALID_DISPLAY_MODES:
		return s
	return DISPLAY_MODE_WINDOWED

static func _normalize_window_size(size: Vector2i) -> Vector2i:
	if size.x < _MIN_WINDOW_SIZE.x or size.y < _MIN_WINDOW_SIZE.y:
		size = default_window_size()
	return snap_window_size(clamp_to_usable(size))

func _resolve_automatic_locale() -> String:
	var os_locale: String = OS.get_locale()
	if os_locale in _explicit_locales():
		return os_locale
	var lang: String = OS.get_locale_language()
	if lang == "zh":
		return "zh_CN"
	for loc: String in _explicit_locales():
		if loc == lang or loc.begins_with(lang + "_"):
			return loc
	return _normalize_explicit_locale(LOCALE_AUTOMATIC)

func _locale_setting_from_profile() -> String:
	return _normalize_stored_locale(_settings().locale)

func _normalize_stored_locale(locale_code: String) -> String:
	var s: String = locale_code.strip_edges()
	if s.is_empty() or s == LOCALE_AUTOMATIC:
		return LOCALE_AUTOMATIC
	if s in _explicit_locales():
		return s
	return LOCALE_AUTOMATIC

func _explicit_locales() -> PackedStringArray:
	return project_locales()

func _normalize_explicit_locale(locale_code: String) -> String:
	var stored: String = _normalize_stored_locale(locale_code)
	if stored != LOCALE_AUTOMATIC:
		return stored
	return String(ProjectSettings.get_setting("internationalization/locale/fallback", "zh_CN"))
