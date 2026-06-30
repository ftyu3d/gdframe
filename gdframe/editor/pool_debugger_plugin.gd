@tool
extends EditorDebuggerPlugin

## 接收运行中游戏上报的对象池快照，并转发给 GDFrame 底部面板。

# =============================================================================
# State
# =============================================================================

var _on_stats: Callable = Callable()
var _session_id: int = -1

# =============================================================================
# Public API
# =============================================================================

func set_stats_handler(on_stats: Callable) -> void:
	_on_stats = on_stats

func request_pool_stats() -> bool:
	if _session_id < 0:
		return false
	var session: EditorDebuggerSession = get_session(_session_id)
	if session == null:
		return false
	session.send_message("gdframe:request_pool_stats", [])
	return true

# =============================================================================
# EditorDebuggerPlugin
# =============================================================================

func _setup_session(session_id: int) -> void:
	_session_id = session_id

func _break_session(session_id: int) -> void:
	if session_id == _session_id:
		_session_id = -1

func _has_capture(capture: String) -> bool:
	return capture == "gdframe"

func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message != "gdframe:pool_stats":
		return false
	var payload: Dictionary = {}
	if data.size() > 0 and data[0] is Dictionary:
		payload = data[0] as Dictionary
	if _on_stats.is_valid():
		_on_stats.call(payload)
	return true
