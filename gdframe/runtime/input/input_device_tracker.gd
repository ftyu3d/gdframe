## 当前输入设备跟踪（与 Godot [InputEvent] 一致）；与 UI 导航解耦。
class_name GDFrameInputDeviceTracker
extends RefCounted

# =============================================================================
# State
# =============================================================================

var _host: Node = null
var _device: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.DeviceKind.UNKNOWN
var _device_id: int = -1
var _last_event_emulated: bool = false

# =============================================================================
# Setup
# =============================================================================

func setup(host: Node) -> void:
	_host = host


# =============================================================================
# Public API
# =============================================================================

## 根据物理 [InputEvent] 更新当前设备；由 [method GDFrame.input_track_event] 驱动。
func process_event(event: InputEvent) -> void:
	var kind: GDFrameInputEventDevice.DeviceKind = GDFrameInputEventDevice.tracked_device_kind(event)
	if kind == GDFrameInputEventDevice.DeviceKind.UNKNOWN:
		return
	_last_event_emulated = GDFrameInputEventDevice.is_emulated(event)
	_device_id = event.device
	if kind == _device:
		return
	_device = kind
	if _host != null:
		_host.signal_gdframe_input_device_changed.emit(kind, _device_id, _last_event_emulated)

func get_device_kind() -> GDFrameInputEventDevice.DeviceKind:
	return _device

func get_device_id() -> int:
	return _device_id

func was_last_event_emulated() -> bool:
	return _last_event_emulated

func is_using_gamepad() -> bool:
	return _device == GDFrameInputEventDevice.DeviceKind.JOYPAD

func is_using_pointer() -> bool:
	return GDFrameInputEventDevice.is_pointer_kind(_device)

