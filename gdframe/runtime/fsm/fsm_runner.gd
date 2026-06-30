extends RefCounted
class_name GDFrameFSMRunner

## 扫描 FSM Registry，步进由宿主调用 [method process] / [method physics_process]；根目录见 [member GDFrameConfig.FSM_ROOT]。
## 由 GDFrame 在首次 fsm_* 调用时创建；仅建立路径索引，[method bind] 再加载 Registry。

# =============================================================================
# Constants
# =============================================================================

const FsmScan: Script = preload("res://addons/gdframe/runtime/fsm/fsm_scan.gd")
const OWNER_HANDLES_META: StringName = &"gdframe_fsm_handles"
const OWNER_EXIT_HOOK_META: StringName = &"gdframe_fsm_exit_hook"

# =============================================================================
# State
# =============================================================================

var _registry_by_machine: Dictionary[StringName, GDFrameFsmRegistryBase] = {}
var _registry_path_by_machine: Dictionary[StringName, String] = {}
## 合法状态名集合（[StringName] → [code]true[/code]），供 bind 时 O(1) 校验。
var _state_set_by_machine: Dictionary[StringName, Dictionary] = {}
## [code]machine_id → owner_instance_id → state_key → GDFrameFsmState[/code]
var _impl_cache: Dictionary = {}
var _scene_tree: WeakRef

# =============================================================================
# Setup
# =============================================================================

func setup_tree_pause_tracking(tree: SceneTree) -> void:
	_scene_tree = weakref(tree) if tree != null else null


## 仅扫描 registry 路径并建立 [code]machine_id → path[/code] 索引，不实例化 Registry。

func ensure_registry_index() -> void:
	_rebuild_registry_index()


# Public API
# =============================================================================

## 是否已加载指定状态机的 Registry（[method bind] 前的轻量检查）。

func is_machine_loaded(machine_id: StringName) -> bool:
	return _registry_by_machine.has(machine_id)


## 预加载 Registry（建议在批量预加载阶段调用，避免首次 [method bind] 同帧卡顿）。

func preload_machine(machine_id: StringName, force_reload: bool = false) -> void:
	_ensure_machine_loaded(machine_id, force_reload)


## 预加载全部 FSM Registry（批量预加载阶段可选）；根目录见 [member GDFrameConfig.FSM_ROOT]。

func preload_all_machines(force_reload: bool = false) -> void:
	if _registry_path_by_machine.is_empty():
		_rebuild_registry_index()
	for mid: StringName in _registry_path_by_machine:
		_ensure_machine_loaded(mid, force_reload)

func bind(machine_id: StringName, initial_state: StringName, owner: Node) -> GDFrameFsmHandle:
	var existing: GDFrameFsmHandle = handle_for(owner, machine_id)
	if existing != null:
		if existing.current_state != initial_state:
			push_warning(
				"GDFrame FSM: %s 已在 %s 上 bind（当前 %s），忽略 initial_state %s"
				% [machine_id, owner.name, existing.current_state, initial_state]
			)
		return existing
	if not _ensure_machine_loaded(machine_id):
		return null
	var state_set: Dictionary = _state_set_by_machine.get(machine_id, {})
	if not state_set.has(initial_state):
		push_error(
			"GDFrame FSM: 初始状态 %s 不在 %s 的 state_keys 中" % [initial_state, machine_id]
		)
		return null
	var reg: GDFrameFsmRegistryBase = _registry_by_machine[machine_id]
	var oid: int = owner.get_instance_id()
	var impl: GDFrameFsmState = _get_state_impl(machine_id, initial_state, reg, oid)
	if impl == null:
		return null
	var handle: GDFrameFsmHandle = GDFrameFsmHandle.new(self, machine_id, initial_state, owner)
	_store_handle_meta(owner, machine_id, handle)
	if not owner.has_meta(OWNER_EXIT_HOOK_META):
		owner.tree_exited.connect(_on_owner_exited.bind(owner), CONNECT_ONE_SHOT)
		owner.set_meta(OWNER_EXIT_HOOK_META, true)
	_bind_impl(impl, owner, handle)
	impl._enter()
	handle._active_impl = impl
	return handle

func handle_for(owner: Node, machine_id: StringName) -> GDFrameFsmHandle:
	if not owner.has_meta(OWNER_HANDLES_META):
		return null
	var h: Variant = owner.get_meta(OWNER_HANDLES_META).get(machine_id)
	if h is GDFrameFsmHandle and not (h as GDFrameFsmHandle).is_released():
		return h as GDFrameFsmHandle
	return null

func process(owner: Node, delta: float) -> void:
	_tick_process(owner, delta)

func physics_process(owner: Node, delta: float) -> void:
	_tick_physics_process(owner, delta)

func dispatch_input(owner: Node, event: InputEvent) -> void:
	if event == null or (event is InputEventKey and event.is_echo()):
		return
	_tick_input(owner, event)

# =============================================================================
# State change & owner
# =============================================================================

func _change_state(handle: GDFrameFsmHandle, next: StringName) -> bool:
	if handle._released:
		push_error("GDFrame FSM: change_state 时句柄已释放（%s）" % handle.machine_id)
		return false
	var state_set: Dictionary = _state_set_by_machine.get(handle.machine_id, {})
	if not state_set.has(next):
		push_error("GDFrame FSM: 状态 %s 不在 %s 中" % [next, handle.machine_id])
		return false
	var reg: GDFrameFsmRegistryBase = _registry_by_machine[handle.machine_id]
	var prev: StringName = handle._current
	if prev == next:
		return true
	var owner: Node = handle.get_owner_node()
	if not is_instance_valid(owner):
		push_error("GDFrame FSM: change_state 时 owner 无效（%s）" % handle.machine_id)
		return false
	var oid: int = owner.get_instance_id()
	var old_impl: GDFrameFsmState = handle._active_impl
	var new_impl: GDFrameFsmState = _get_state_impl(handle.machine_id, next, reg, oid)
	if new_impl == null:
		return false
	if old_impl != null:
		old_impl._exit()
	handle._current = next
	_bind_impl(new_impl, owner, handle)
	new_impl._enter()
	handle._active_impl = new_impl
	handle.changed.emit(prev, next)
	return true

func _unbind(handle: GDFrameFsmHandle) -> void:
	if handle._active_impl != null:
		handle._active_impl._exit()
		handle._active_impl = null
	var owner: Node = handle.get_owner_node()
	var oid: int = handle._owner_instance_id
	var mid: StringName = handle.machine_id
	if is_instance_valid(owner):
		_clear_handle_meta(owner, mid)
	if oid >= 0:
		_impl_cache_purge(mid, oid)

func _store_handle_meta(owner: Node, mid: StringName, handle: GDFrameFsmHandle) -> void:
	if owner.has_meta(OWNER_HANDLES_META):
		var d: Dictionary = owner.get_meta(OWNER_HANDLES_META)
		d[mid] = handle
	else:
		owner.set_meta(OWNER_HANDLES_META, {mid: handle})

func _clear_handle_meta(owner: Node, mid: StringName) -> void:
	if not owner.has_meta(OWNER_HANDLES_META):
		return
	var d: Dictionary = owner.get_meta(OWNER_HANDLES_META)
	d.erase(mid)
	if d.is_empty():
		owner.remove_meta(OWNER_HANDLES_META)

func _on_owner_exited(owner: Node) -> void:
	if not is_instance_valid(owner):
		return
	if not owner.has_meta(OWNER_HANDLES_META):
		return
	var handles: Dictionary = owner.get_meta(OWNER_HANDLES_META)
	var mids: Array = handles.keys().duplicate()
	for _mid: Variant in mids:
		var h: Variant = handles.get(_mid)
		if h is GDFrameFsmHandle:
			var handle: GDFrameFsmHandle = h as GDFrameFsmHandle
			if not handle.is_released():
				handle.release()
	owner.remove_meta(OWNER_HANDLES_META)
	owner.remove_meta(OWNER_EXIT_HOOK_META)

# =============================================================================
# Registry
# =============================================================================

func _rebuild_registry_index() -> void:
	_registry_path_by_machine.clear()
	for reg_path: String in FsmScan.collect_fsm_registry_paths(GDFrameConfig.FSM_ROOT):
		var fsm_id: String = reg_path.get_file().get_basename().trim_suffix("_registry")
		if fsm_id.is_empty():
			continue
		_registry_path_by_machine[StringName(fsm_id)] = reg_path

func _ensure_machine_loaded(machine_id: StringName, force_reload: bool = false) -> bool:
	if _registry_by_machine.has(machine_id) and not force_reload:
		return true
	if _registry_path_by_machine.is_empty():
		_rebuild_registry_index()
	var reg_path: String = _registry_path_by_machine.get(machine_id, "")
	if reg_path.is_empty():
		push_error("GDFrame FSM: 未找到状态机 %s（检查 res://fsm 与 Registry 命名）" % machine_id)
		return false
	var reg: GDFrameFsmRegistryBase = _load_registry_from_path(reg_path, force_reload)
	if reg == null:
		return false
	return _register_registry(machine_id, reg, reg_path, true)

func _register_registry(
	index_mid: StringName,
	reg: GDFrameFsmRegistryBase,
	reg_path: String,
	commit_active: bool,
) -> bool:
	var mid: Variant = reg.machine_id()
	var mid_sn: StringName = mid if mid is StringName else StringName(str(mid))
	if String(mid_sn).is_empty():
		var msg: String = "GDFrame FSM: machine_id 为空，跳过 %s" % reg_path
		if commit_active:
			push_error(msg)
		else:
			push_warning(msg)
		return false
	if mid_sn != index_mid:
		push_warning(
			"GDFrame FSM: registry 路径为 %s，但 machine_id() 为 %s，以 machine_id 为准。"
			% [index_mid, mid_sn]
		)
	var key_sn: Array[StringName] = _normalize_state_keys(reg.state_keys())
	if key_sn.is_empty():
		var msg: String = "GDFrame FSM: 状态列表为空，跳过 %s" % reg_path
		if commit_active:
			push_error(msg)
		else:
			push_warning(msg)
		return false
	var state_set: Dictionary = {}
	for sk: StringName in key_sn:
		state_set[sk] = true
	if commit_active:
		_registry_by_machine[mid_sn] = reg
		_state_set_by_machine[mid_sn] = state_set
		_registry_path_by_machine[mid_sn] = reg_path
		if mid_sn != index_mid:
			_registry_path_by_machine.erase(index_mid)
	return true

func _load_registry_from_path(reg_path: String, force_reload: bool) -> GDFrameFsmRegistryBase:
	var load_mode: ResourceLoader.CacheMode = (
		ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
	)
	var scr: Script = ResourceLoader.load(reg_path, "", load_mode) as Script
	if scr == null:
		push_error("GDFrame FSM: 无法加载 Registry %s" % reg_path)
		return null
	var reg_obj: Object = scr.new()
	if not reg_obj is GDFrameFsmRegistryBase:
		push_error("GDFrame FSM: %s 不是有效的 Registry" % reg_path)
		return null
	return reg_obj as GDFrameFsmRegistryBase

func _normalize_state_keys(keys: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if keys is Array:
		for k: Variant in keys:
			out.append(k if k is StringName else StringName(str(k)))
	return out

# =============================================================================
# Tick & state impl
# =============================================================================

enum _TickMode { PROCESS, PHYSICS, INPUT }


func _tick_process(owner: Node, delta: float) -> void:
	_tick_owner_handles(owner, _TickMode.PROCESS, delta)


func _tick_physics_process(owner: Node, delta: float) -> void:
	_tick_owner_handles(owner, _TickMode.PHYSICS, delta)


func _tick_input(owner: Node, event: InputEvent) -> void:
	_tick_owner_handles(owner, _TickMode.INPUT, event)


func _tick_owner_handles(owner: Node, mode: _TickMode, arg: Variant) -> void:
	if not is_instance_valid(owner) or not owner.has_meta(OWNER_HANDLES_META):
		return
	if _is_tree_paused_for_owner(owner):
		return
	for h: Variant in owner.get_meta(OWNER_HANDLES_META).values():
		if h is not GDFrameFsmHandle:
			continue
		var handle: GDFrameFsmHandle = h as GDFrameFsmHandle
		if handle._released or handle._active_impl == null:
			continue
		var impl: GDFrameFsmState = handle._active_impl
		match mode:
			_TickMode.PROCESS:
				impl._process(arg as float)
			_TickMode.PHYSICS:
				impl._physics_process(arg as float)
			_TickMode.INPUT:
				impl._input(arg as InputEvent)

func _impl_cache_purge(machine_id: StringName, owner_instance_id: int) -> void:
	if not _impl_cache.has(machine_id):
		return
	var by_owner: Dictionary = _impl_cache[machine_id]
	by_owner.erase(owner_instance_id)
	if by_owner.is_empty():
		_impl_cache.erase(machine_id)

func _get_state_impl(
	machine_id: StringName,
	state_key: StringName,
	reg: GDFrameFsmRegistryBase,
	owner_instance_id: int,
) -> GDFrameFsmState:
	if not _impl_cache.has(machine_id):
		_impl_cache[machine_id] = {}
	var by_owner: Dictionary = _impl_cache[machine_id]
	if not by_owner.has(owner_instance_id):
		by_owner[owner_instance_id] = {}
	var by_state: Dictionary = by_owner[owner_instance_id]
	if by_state.has(state_key):
		return by_state[state_key] as GDFrameFsmState
	var scr: Script = reg.state_script(state_key)
	if scr == null:
		push_error(
			"GDFrame FSM: 状态 %s 缺少 state_script（%s）" % [state_key, machine_id]
		)
		return null
	var inst: Variant = scr.new()
	if inst is not GDFrameFsmState:
		push_error(
			"GDFrame FSM: 无法实例化状态 %s（%s，须 extends GDFrameFsmState）"
			% [state_key, machine_id]
		)
		return null
	by_state[state_key] = inst
	return inst as GDFrameFsmState

func _bind_impl(impl: GDFrameFsmState, owner: Node, handle: GDFrameFsmHandle) -> void:
	impl.owner = owner
	impl.handle = weakref(handle)

func _is_tree_paused_for_owner(owner: Node) -> bool:
	var tree: SceneTree = _scene_tree.get_ref() if _scene_tree != null else null
	if tree == null or not tree.paused:
		return false
	return not _owner_processes_while_tree_paused(owner)

func _owner_processes_while_tree_paused(owner: Node) -> bool:
	match owner.process_mode:
		Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED:
			return true
		_:
			return false

