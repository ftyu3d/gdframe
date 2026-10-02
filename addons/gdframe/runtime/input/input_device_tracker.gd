## 当前输入设备跟踪（与 Godot [InputEvent] 一致）。
class_name GDFrameInputDeviceTracker
extends RefCounted

# =============================================================================
# State
# =============================================================================

var _host: Node = null
var _keyboard_nav_focus: bool = false
var _device: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.DeviceKind.UNKNOWN
var _device_id: int = -1
var _last_event_emulated: bool = false

# =============================================================================
# Setup
# =============================================================================

func setup(host: Node, keyboard_nav_focus: bool) -> void:
	_host = host
	_keyboard_nav_focus = keyboard_nav_focus


# =============================================================================
# Public API
# =============================================================================

## 按 [method GDFrameInputEventDevice.tracked_device_kind] 更新当前设备。
func process_event(event: InputEvent) -> void:
	var kind: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.tracked_device_kind(event)
	if kind == GDFrameInputEventDevice.DeviceKind.UNKNOWN:
		return
	_last_event_emulated = GDFrameInputEventDevice.is_emulated(event)
	_device_id = event.device
	if kind == _device:
		return
	_device = kind
	_host.signal_gdframe_input_device_changed.emit(kind, _device_id, _last_event_emulated)

func get_device_kind() -> GDFrameInputEventDevice.DeviceKind:
	return _device

func get_device_id() -> int:
	return _device_id

func was_last_event_emulated() -> bool:
	return _last_event_emulated

func is_using_gamepad() -> bool:
	return _device == GDFrameInputEventDevice.DeviceKind.JOYPAD

func should_hide_cursor(device_kind: GDFrameInputEventDevice.DeviceKind) -> bool:
	return GDFrameInputEventDevice.should_hide_cursor(device_kind, _keyboard_nav_focus)


func should_allow_nav_focus() -> bool:
	return GDFrameInputEventDevice.should_allow_nav_focus(get_device_kind(), _keyboard_nav_focus)


func is_using_pointer() -> bool:
	return GDFrameInputEventDevice.is_pointer_kind(_device)

