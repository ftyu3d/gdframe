## 当前输入设备跟踪（与 Godot [InputEvent] 一致）。
class_name GDFrameInputDeviceTracker
extends Node

# =============================================================================
# State
# =============================================================================

signal device_changed(kind: GDFrameInputEventDevice.DeviceKind, id: int, emulated: bool)

var keyboard_nav_focus := true
var _device: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.DeviceKind.UNKNOWN
var _device_id: int = -1
var _last_event_emulated: bool = false

# =============================================================================
# Public API
# =============================================================================

## 按 [method GDFrameInputEventDevice.tracked_device_kind] 更新当前设备。
func _input(event: InputEvent) -> void:
	var kind: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.tracked_device_kind(event)
	if kind == GDFrameInputEventDevice.DeviceKind.UNKNOWN:
		return
	_last_event_emulated = GDFrameInputEventDevice.is_emulated(event)
	_device_id = event.device
	if kind == _device:
		return
	_device = kind
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if should_hide_cursor(kind) else Input.MOUSE_MODE_VISIBLE
	device_changed.emit(kind, _device_id, _last_event_emulated)

func get_device_kind() -> GDFrameInputEventDevice.DeviceKind:
	return _device

func get_device_id() -> int:
	return _device_id

func was_last_event_emulated() -> bool:
	return _last_event_emulated

func is_using_gamepad() -> bool:
	return _device == GDFrameInputEventDevice.DeviceKind.JOYPAD

func should_hide_cursor(device_kind: GDFrameInputEventDevice.DeviceKind) -> bool:
	return GDFrameInputEventDevice.should_hide_cursor(device_kind, keyboard_nav_focus)


func should_allow_nav_focus() -> bool:
	return GDFrameInputEventDevice.should_allow_nav_focus(get_device_kind(), keyboard_nav_focus)


func is_using_pointer() -> bool:
	return GDFrameInputEventDevice.is_pointer_kind(_device)
