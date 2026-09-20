## 输入设备分类，与 Godot 物理 [InputEvent] 子类对应。
class_name GDFrameInputEventDevice
extends RefCounted

## [InputEventAction]、[InputEventShortcut] 等非物理事件归 [constant UNKNOWN]。
enum DeviceKind {
	UNKNOWN = 0,
	KEYBOARD,
	MOUSE,
	JOYPAD,
	TOUCHSCREEN,
}

# =============================================================================
# Classification
# =============================================================================

## 由 [InputEvent] 推断设备类型。
static func kind_from_event(event: InputEvent) -> DeviceKind:
	if event is InputEventKey:
		return DeviceKind.KEYBOARD
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return DeviceKind.MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return DeviceKind.JOYPAD
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return DeviceKind.TOUCHSCREEN
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

## 指针类输入（鼠标 / 触屏）。
static func is_pointer_kind(kind: DeviceKind) -> bool:
	return kind == DeviceKind.MOUSE or kind == DeviceKind.TOUCHSCREEN


## 是否允许导航聚焦：手柄始终可以；键盘仅 [param keyboard_nav_focus]；鼠标/触屏不可以。
static func should_allow_nav_focus(kind: DeviceKind, keyboard_nav_focus: bool) -> bool:
	if kind == DeviceKind.JOYPAD:
		return true
	if kind == DeviceKind.KEYBOARD:
		return keyboard_nav_focus
	return false


## 切换至 [param kind] 时是否应隐藏鼠标；与 [method should_allow_nav_focus] 一致。
static func should_hide_cursor(kind: DeviceKind, keyboard_nav_focus: bool) -> bool:
	return should_allow_nav_focus(kind, keyboard_nav_focus)
