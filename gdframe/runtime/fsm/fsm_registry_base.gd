extends RefCounted
class_name GDFrameFSMRegistryBase

## 编辑器生成的 [code]fsm_*_registry.gd[/code] 继承本类。
## 各状态为独立 [Script]，由 [method state_script] 按 [param state_key] 映射。
## 首状态由 [method GDFrame.fsm_bind] 的 [code]initial_state[/code] 指定，不在 Registry 中声明。

# =============================================================================
# API（override in generated registry）
# =============================================================================

func machine_id() -> StringName:
	return &""


func state_keys() -> Array[StringName]:
	return []


func state_script(_state_key: StringName) -> Script:
	return null
