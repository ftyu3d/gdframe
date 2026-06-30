extends RefCounted
class_name GDFrameFsmRegistryBase

## 由编辑器生成的 `fsm_xxx_registry.gd` 继承本类；运行时用 [method ResourceLoader.load] 即可，不必做成 C# 式程序集扫描。
## 各状态用独立 [Script]，由 [method state_script] 映射到 [param state_key]。
## 进入场景时的首状态由 [method GDFrame.fsm_bind] 的 [code]initial_state[/code] 参数指定，不在 Registry 中声明。

# =============================================================================
# API（override in generated registry）
# =============================================================================

func machine_id() -> StringName:
	return &""


func state_keys() -> Array[StringName]:
	return []


func state_script(_state_key: StringName) -> Script:
	return null
