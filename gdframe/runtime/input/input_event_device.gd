## 输入设备分类，与 Godot [InputEvent] 类型层次一致。
## 见官方文档：Using InputEvent / InputEvent 各类子类。
class_name GDFrameInputEventDevice
extends RefCounted

## 与 Godot 物理输入 [InputEvent] 子类一一对应。
## [InputEventAction]、[InputEventShortcut] 等非物理事件归 [constant UNKNOWN]。
enum DeviceKind {
	UNKNOWN = 0,
	KEYBOARD,
	MOUSE,
	JOYPAD,
	TOUCHSCREEN,
	GESTURE,
	MIDI,
}

# =============================================================================
# Classification
# =============================================================================

## 由 [InputEvent] 推断设备类型（与 Godot 事件类层次一致）。
static func kind_from_event(event: InputEvent) -> DeviceKind:
	if event is InputEventKey:
		return DeviceKind.KEYBOARD
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return DeviceKind.MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return DeviceKind.JOYPAD
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return DeviceKind.TOUCHSCREEN
	if event is InputEventMagnifyGesture or event is InputEventPanGesture:
		return DeviceKind.GESTURE
	if event is InputEventMIDI:
		return DeviceKind.MIDI
	return DeviceKind.UNKNOWN


## 应参与设备跟踪的设备类型；[constant UNKNOWN] 表示忽略（含悬停移动）。
static func tracked_device_kind(event: InputEvent) -> DeviceKind:
	if event is InputEventMouseMotion:
		return DeviceKind.UNKNOWN
	return kind_from_event(event)


## 是否为模拟事件（触屏转鼠标 / 鼠标转触屏等，[member InputEvent.device] 为 [constant InputEvent.DEVICE_ID_EMULATION]）。
static func is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION

# =============================================================================
# Helpers
# =============================================================================

## 设备类型调试字符串（日志/UI 显示用）。
static func kind_to_string(kind: DeviceKind) -> String:
	match kind:
		DeviceKind.KEYBOARD:
			return "keyboard"
		DeviceKind.MOUSE:
			return "mouse"
		DeviceKind.JOYPAD:
			return "joypad"
		DeviceKind.TOUCHSCREEN:
			return "touchscreen"
		DeviceKind.GESTURE:
			return "gesture"
		DeviceKind.MIDI:
			return "midi"
		_:
			return "unknown"


## 指针类输入（鼠标 / 触屏），可用于 UI 提示样式等。
static func is_pointer_kind(kind: DeviceKind) -> bool:
	return kind == DeviceKind.MOUSE or kind == DeviceKind.TOUCHSCREEN


## 键盘 / 手柄应参与 UI 焦点导航（切换设备时刷新聚焦环等）。
static func supports_ui_focus_navigation(kind: DeviceKind) -> bool:
	return kind == DeviceKind.KEYBOARD or kind == DeviceKind.JOYPAD


## 切换至 [param kind] 时是否应隐藏鼠标（[param keyboard_gamepad] 来自 [member GDFrameConfig.keyboard_gamepad]）。
## 指针类（鼠标/触屏）始终显示；手柄始终隐藏；键盘取决于 [param keyboard_gamepad]。
static func should_hide_cursor(kind: DeviceKind, keyboard_gamepad: bool) -> bool:
	if is_pointer_kind(kind):
		return false
	if kind == DeviceKind.JOYPAD:
		return true
	if kind == DeviceKind.KEYBOARD:
		return keyboard_gamepad
	return false


## 是否显示 UI 导航聚焦环；与 [method should_hide_cursor] 互斥（隐藏光标时为 [code]true[/code]）。
static func should_show_nav_focus_on_grab(kind: DeviceKind, keyboard_gamepad: bool) -> bool:
	return should_hide_cursor(kind, keyboard_gamepad)
