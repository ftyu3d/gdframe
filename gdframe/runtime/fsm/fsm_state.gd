extends RefCounted
class_name GDFrameFSMState

## 状态脚本基类；由宿主经 [method GDFrame.fsm_process] / [method GDFrame.fsm_physics_process] / [method GDFrame.fsm_dispatch_input] 驱动。

# =============================================================================
# State
# =============================================================================

var owner: Node = null
var handle: WeakRef = null

# =============================================================================
# Public API
# =============================================================================

func change_state(next: StringName) -> bool:
	var h: GDFrameFSMHandle = handle.get_ref() as GDFrameFSMHandle
	if h == null:
		return false
	return h.change_state(next)


# =============================================================================
# Hooks（override in subclass）
# =============================================================================

func _enter() -> void:
	pass


func _exit() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass


func _input(_event: InputEvent) -> void:
	pass
