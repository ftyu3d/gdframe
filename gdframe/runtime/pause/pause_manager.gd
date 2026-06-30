## 暂停栈：多来源 [code]pause_push/pop[/code] 共用 [code]get_tree().paused[/code] 与音频暂停。
class_name GDFramePauseManager
extends RefCounted

# =============================================================================
# State
# =============================================================================

var _host: Node = null
var _apply_cb: Callable = Callable()
var _counts: Dictionary = {}

# =============================================================================
# Setup
# =============================================================================

func setup(host: Node, apply_cb: Callable) -> void:
	_host = host
	_apply_cb = apply_cb

# =============================================================================
# Public API
# =============================================================================

func push(reason: StringName) -> void:
	var prev_depth: int = depth()
	var key: String = String(reason)
	_counts[key] = int(_counts.get(key, 0)) + 1
	_sync_after_depth_change(prev_depth)


func pop(reason: StringName) -> void:
	var key: String = String(reason)
	if not _counts.has(key) or int(_counts[key]) <= 0:
		push_error("GDFrame Pause: pop(%s) ignored — reason not active." % key)
		return
	var prev_depth: int = depth()
	_counts[key] = int(_counts[key]) - 1
	if int(_counts[key]) <= 0:
		_counts.erase(key)
	_sync_after_depth_change(prev_depth)


func clear(reason: StringName = &"") -> void:
	var prev_depth: int = depth()
	if reason.is_empty():
		if _counts.is_empty():
			return
		_counts.clear()
	elif not _counts.has(String(reason)):
		push_error("GDFrame Pause: clear(%s) ignored — reason not active." % String(reason))
		return
	else:
		_counts.erase(String(reason))
	_sync_after_depth_change(prev_depth)


func is_active() -> bool:
	return depth() > 0


func depth() -> int:
	var total: int = 0
	for count: Variant in _counts.values():
		total += int(count)
	return total

# =============================================================================
# Internal
# =============================================================================

func _sync_after_depth_change(prev_depth: int) -> void:
	var cur_depth: int = depth()
	var prev_active: bool = prev_depth > 0
	var cur_active: bool = cur_depth > 0
	if prev_active != cur_active and _apply_cb.is_valid():
		_apply_cb.call(cur_active)
	if _host != null and (prev_active != cur_active or prev_depth != cur_depth):
		_host.signal_gdframe_pause_changed.emit(cur_active, cur_depth)
