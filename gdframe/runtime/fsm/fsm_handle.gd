extends RefCounted
class_name GDFrameFSMHandle

## 单个节点上的状态机句柄；步进由宿主调用 [method GDFrame.fsm_process] / [method GDFrame.fsm_physics_process]。

# =============================================================================
# Signals
# =============================================================================

signal changed(from_state: StringName, to_state: StringName)

# =============================================================================
# Properties
# =============================================================================

var machine_id: StringName:
	get:
		return _machine_id

var current_state: StringName:
	get:
		return _current

var _machine_id: StringName = &""
var _current: StringName = &""
var _owner: WeakRef = null
var _owner_instance_id: int = -1
var _runner: GDFrameFSMRunner = null
var _released: bool = false
var _active_impl: GDFrameFSMState = null

# =============================================================================
# Public API
# =============================================================================

func is_released() -> bool:
	return _released

func _init(
	p_runner: GDFrameFSMRunner,
	p_machine_id: StringName,
	p_initial: StringName,
	owner: Node,
) -> void:
	_runner = p_runner
	_machine_id = p_machine_id
	_current = p_initial
	_owner = weakref(owner)
	_owner_instance_id = owner.get_instance_id()

func get_owner_node() -> Node:
	var n: Object = _owner.get_ref()
	return n as Node


## 切换到 [param next]；失败返回 [code]false[/code]。
func change_state(next: StringName) -> bool:
	if _released:
		push_error("GDFrame FSM: change_state 时句柄已释放（%s）" % _machine_id)
		return false
	return _runner._change_state(self, next)

func release() -> void:
	if _released:
		return
	_released = true
	_runner._unbind(self)
	_runner = null

