extends RefCounted
class_name GDFrameFsmState

## 状态脚本基类；钩子名与 [Node] 一致，由宿主调用 [method GDFrame.fsm_process] / [method GDFrame.fsm_physics_process]。
## [method _process]：逻辑帧（计时、动画、AI 决策）。[method _physics_process]：物理帧（[code]velocity[/code]、[code]move_and_slide[/code]）。
## 输入（可选）：宿主 [code]_input[/code] 中 [method GDFrame.fsm_dispatch_input]。

# =============================================================================
# State
# =============================================================================

var owner: Node = null
var handle: WeakRef = null

# =============================================================================
# Public API
# =============================================================================

func change_state(next: StringName) -> bool:
	var h: GDFrameFsmHandle = handle.get_ref() as GDFrameFsmHandle
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
