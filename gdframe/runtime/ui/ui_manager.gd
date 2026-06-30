## UI 管理器：缓存、图层、打开/关闭栈（由 [code]GDFrame[/code] 转发调用）。
class_name GDFrameUIManager
extends RefCounted

# =============================================================================
# Constants
# =============================================================================

const ROOT_CANVAS_LAYER: int = 100
const INITED_META: StringName = &"gdframe_ui_inited"
const PREPARING_META: StringName = &"gdframe_ui_preparing"

# =============================================================================
# State — layers & registry
# =============================================================================

var _root: CanvasLayer = null
var _frame: Node = null
var _layer_roots: Array[Control] = []
var _dim: Control = null
var _layer_count: int = 0
var _scene_registry: Dictionary[StringName, Dictionary] = {}
var _cache: Dictionary[StringName, Control] = {}
var _stack: Array[StringName] = []
var _stack_index: Dictionary[StringName, int] = {}
var _dim_stack: Array[StringName] = []

# =============================================================================
# State — navigation
# =============================================================================

var _nav_return_focus: Dictionary = {}
var _nav_locked_by: Dictionary = {}
var _nav_reopen_on_close: Dictionary = {}
var _ui_instance_to_id: Dictionary = {}
var _nav_vp: Viewport = null

# =============================================================================
# State — input
# =============================================================================

var _pause_open_blocked_until_frame: int = -1

# =============================================================================
# Setup
# =============================================================================

func setup(root_node: Node, layer_slot_count: int) -> void:
	if _root != null:
		return
	_frame = root_node
	_root = CanvasLayer.new()
	_root.name = "GDFrameUIRoot"
	_root.layer = ROOT_CANVAS_LAYER
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	root_node.add_child(_root)
	_layer_count = maxi(layer_slot_count, 1)
	_layer_roots.clear()
	for i: int in range(_layer_count):
		var layer: Control = Control.new()
		layer.name = "layer_%d" % i
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		layer.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
		_root.add_child(layer)
		_layer_roots.append(layer)
	_dim = _instantiate_contract_dim()
	_dim.name = "dim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.process_mode = Node.PROCESS_MODE_ALWAYS
	_dim.visible = false

func register_scanned_paths(scene_paths: Array[String]) -> void:
	for full_path: String in scene_paths:
		var ui_id: StringName = StringName(full_path.get_file().get_basename())
		_scene_registry[ui_id] = {"path": full_path}

# =============================================================================
# Public API
# =============================================================================

func prepare(ui_id: StringName) -> void:
	if not _scene_registry.has(ui_id):
		push_error("GDFrame UI: 未注册 %s" % ui_id)
		return
	var ui: GDFrameUIBase = _mount_hidden(ui_id)
	if ui == null:
		push_error("GDFrame UI: prepare 失败（无法创建实例）%s" % ui_id)
		return
	if ui.has_meta(INITED_META):
		return
	while ui.has_meta(PREPARING_META):
		if not is_instance_valid(ui):
			return
		await _frame.get_tree().process_frame
	ui.set_meta(PREPARING_META, true)
	await ui.gdframe_init()
	if not is_instance_valid(ui):
		return
	ui.remove_meta(PREPARING_META)
	ui.set_meta(INITED_META, true)

func open(ui_id: StringName, data: Variant = null, layer: int = -1) -> Control:
	if not _scene_registry.has(ui_id):
		push_error("GDFrame UI: 未注册 %s" % ui_id)
		return null
	if not is_preloaded(ui_id):
		push_error(
			"GDFrame UI: 须先 await GDFrame.ui_preload(%s)，再调用 GDFrame.ui_open（ui_open 为同步，非协程）。"
			% ui_id
		)
		return null
	var ui: GDFrameUIBase = _cache[ui_id] as GDFrameUIBase
	var resolved_layer: int = _resolve_layer(ui, ui_id, layer)
	if is_open(ui_id):
		var use_dim_refresh: bool = _resolve_use_dim(ui, ui_id, data)
		_attach(ui, ui_id, resolved_layer)
		_stack_push_to_top(ui_id)
		if use_dim_refresh:
			if not _dim_stack.has(ui_id):
				_dim_push_stack(ui_id)
			_place_dim_before_ui(ui)
		else:
			_dim_remove_stack(ui_id)
			_restore_dim_from_stack()
		ui.gdframe_show(data)
		if ui.ui_nav_can_receive_focus() and ui.ui_nav_auto_focus_on_show():
			ui.call_deferred(&"ui_nav_focus_on_show", data)
		return ui
	var use_dim: bool = _resolve_use_dim(ui, ui_id, data)
	var nav_parent: GDFrameUIBase = _nav_find_parent_on_stack()
	var nav_opener: Control = GDFrameUINav.read_nav_from(data)
	if nav_opener == null:
		nav_opener = GDFrameUINav.capture_focused_child(nav_parent, _nav_viewport())
	if nav_parent == null and nav_opener != null:
		nav_parent = _nav_find_ui_ancestor(nav_opener)
	_attach(ui, ui_id, resolved_layer)
	_set_visible(ui, true)
	_stack_push_to_top(ui_id)
	if use_dim:
		_dim_push_stack(ui_id)
		_place_dim_before_ui(ui)
	else:
		_dim_remove_stack(ui_id)
		_restore_dim_from_stack()
	ui.gdframe_show(data)
	_nav_bind_return_focus_ticket(ui_id, nav_parent, nav_opener)
	_nav_lock_stack_below(ui_id)
	_nav_ensure_parent_locked(ui_id, nav_parent)
	_nav_release_gui_focus_from_locked(ui_id)
	if ui.ui_nav_can_receive_focus() and ui.ui_nav_auto_focus_on_show():
		ui.call_deferred(&"ui_nav_focus_on_show", data)
	return ui


## 关闭 [param close_id] 并打开 [param open_id]；之后关闭 [param open_id] 时会自动重新打开 [param close_id] 并 [code]nav_restore_last[/code] 还焦。

func open_replace(close_id: StringName, open_id: StringName, data: Variant = null, layer: int = -1) -> Control:
	if not close(close_id):
		push_error("GDFrame UI: open_replace 无法关闭 %s" % close_id)
		return null
	var opened: Control = open(open_id, data, layer)
	if opened == null:
		push_error("GDFrame UI: open_replace 无法打开 %s，正在恢复 %s" % [open_id, close_id])
		open(close_id, {GDFrameUINav.DATA_NAV_RESTORE_LAST: true})
		return null
	_nav_reopen_on_close[open_id] = close_id
	return opened

func is_preloaded(ui_id: StringName) -> bool:
	if not is_cached(ui_id):
		return false
	return _cache[ui_id].has_meta(INITED_META)

func close(ui_id: StringName, cache: bool = true) -> bool:
	if not _cache.has(ui_id):
		push_error("GDFrame UI: ui_close 失败，%s 未缓存或不存在" % ui_id)
		return false
	var ui: GDFrameUIBase = _get_cached_ui(ui_id)
	if ui == null:
		push_error("GDFrame UI: ui_close 失败，%s 缓存实例无效" % ui_id)
		return false
	if ui.gdframe_close() == false:
		return false
	var nav_restore: Dictionary = (_nav_return_focus.get(ui_id, {}) as Dictionary).duplicate()
	_stack_remove(ui_id)
	_nav_release_focus_for_closed_ui(ui)
	_set_visible(ui, false)
	_dim_remove_stack(ui_id)
	_restore_dim_from_stack()
	_nav_return_focus.erase(ui_id)
	_nav_prune_closed_ui_from_locks(ui_id)
	_nav_unlock_for_close(ui_id)
	_nav_clear_stale_suspend_on_stack()
	if _frame != null:
		_frame.call_deferred(&"_gdframe_nav_focus_restore", nav_restore)
	if _nav_reopen_on_close.has(ui_id):
		var reopen_id: StringName = _nav_reopen_on_close[ui_id] as StringName
		_nav_reopen_on_close.erase(ui_id)
		open(reopen_id, {GDFrameUINav.DATA_NAV_RESTORE_LAST: true})
	if cache:
		return true
	_ui_instance_to_id.erase(ui.get_instance_id())
	_cache.erase(ui_id)
	ui.queue_free()
	return true

func close_top() -> bool:
	_prune_stale_stack_top()
	if _stack.is_empty():
		push_error("GDFrame UI: ui_close_top 失败，打开栈为空")
		return false
	return close(_stack[_stack.size() - 1])

func is_open(ui_id: StringName) -> bool:
	var ui: GDFrameUIBase = _get_cached_ui(ui_id)
	return ui != null and ui.visible

func is_cached(ui_id: StringName) -> bool:
	return _get_cached_ui(ui_id) != null

func get(ui_id: StringName) -> Control:
	return _get_cached_ui(ui_id)

func get_ui_id(ui: GDFrameUIBase) -> StringName:
	return _nav_ui_id(ui)

func notify_locale() -> void:
	for ui_id: StringName in _stack:
		var ui: GDFrameUIBase = _cache.get(ui_id) as GDFrameUIBase
		if ui == null or not is_instance_valid(ui) or not ui.visible:
			continue
		ui.gdframe_locale_changed()


## 重新计算导航状态并聚焦当前活跃 UI。

func nav_refresh() -> void:
	var active: GDFrameUIBase = get_active_ui()
	if active == null:
		active = _nav_find_parent_on_stack()
	if active == null:
		return
	active.ui_nav_focus_on_show(null)

func get_active_ui() -> GDFrameUIBase:
	return _compute_active_ui()


func restore_nav_return_focus(restore_after_close: Dictionary) -> void:
	var parent: GDFrameUIBase = _nav_resolve_restore_parent(restore_after_close)
	if parent == null:
		return
	var restore_path: String = _nav_restore_control_path(parent, restore_after_close)
	if restore_path.is_empty():
		return
	parent.ui_nav_apply_focus_by_path(restore_path)


## 由框架 Autoload 输入回调调用；暂停时 UI Control 往往收不到 [code]ui_cancel[/code]。
func process_cancel_input(event: InputEvent) -> bool:
	if not event.is_action_pressed("ui_cancel"):
		return false
	var ui: GDFrameUIBase = _top_cancel_closable_ui()
	if ui == null:
		return false
	if _frame != null and _frame.get_tree().paused:
		mark_pause_open_blocked()
	ui.ui_cancel_close()
	return true

func mark_pause_open_blocked() -> void:
	_pause_open_blocked_until_frame = Engine.get_process_frames() + 2

func is_pause_open_blocked() -> bool:
	return Engine.get_process_frames() <= _pause_open_blocked_until_frame

func process_nav_action(nav_action: int, active: GDFrameUIBase = null) -> bool:
	if active == null:
		active = get_active_ui()
	if active == null or not active.ui_nav_has_items():
		return false
	var vp: Viewport = _nav_viewport()
	var focus_owner: Control = _nav_focus_owner_for_ui(active, vp)
	return active.ui_nav_process_input(nav_action, focus_owner)

# =============================================================================
# Stack
# =============================================================================

func _stack_push_to_top(ui_id: StringName) -> void:
	if _stack_index.has(ui_id):
		_stack_remove(ui_id)
	_stack_index[ui_id] = _stack.size()
	_stack.append(ui_id)

func _stack_remove(ui_id: StringName) -> void:
	if not _stack_index.has(ui_id):
		return
	var idx: int = int(_stack_index[ui_id])
	var last_idx: int = _stack.size() - 1
	if idx != last_idx:
		var swapped_id: StringName = _stack[last_idx]
		_stack[idx] = swapped_id
		_stack_index[swapped_id] = idx
	_stack.pop_back()
	_stack_index.erase(ui_id)

func _prune_stale_stack_top() -> void:
	while not _stack.is_empty():
		var top_id: StringName = _stack[_stack.size() - 1]
		if is_open(top_id):
			return
		_stack_remove(top_id)

# =============================================================================
# Cache & mount
# =============================================================================

func _get_cached_ui(ui_id: StringName) -> GDFrameUIBase:
	if not _cache.has(ui_id):
		return null
	var ui: Variant = _cache[ui_id]
	if ui is GDFrameUIBase:
		return ui as GDFrameUIBase
	return null

func _mount_hidden(ui_id: StringName) -> GDFrameUIBase:
	if is_open(ui_id):
		return _cache.get(ui_id) as GDFrameUIBase
	var ui: GDFrameUIBase = _get_or_create(ui_id)
	if ui == null:
		return null
	var resolved_layer: int = _resolve_layer(ui, ui_id, -1)
	_attach(ui, ui_id, resolved_layer)
	_set_visible(ui, false)
	return ui

func _get_or_create(ui_id: StringName) -> GDFrameUIBase:
	if not _scene_registry.has(ui_id):
		return null
	var entry: Dictionary = _scene_registry[ui_id]
	var cached: Variant = _cache.get(ui_id)
	if cached is GDFrameUIBase:
		return cached as GDFrameUIBase
	var scene: PackedScene = _load_scene(entry, ui_id)
	if scene == null:
		return null
	var inst: Control = scene.instantiate() as Control
	if inst is not GDFrameUIBase:
		push_error("GDFrame UI: 根节点脚本须 extends GDFrameUIBase：%s" % ui_id)
		if inst != null:
			inst.queue_free()
		return null
	var ui: GDFrameUIBase = inst as GDFrameUIBase
	ui.visible = false
	_cache[ui_id] = ui
	_ui_instance_to_id[ui.get_instance_id()] = ui_id
	return ui

func _load_scene(entry: Dictionary, ui_id: StringName = &"") -> PackedScene:
	var scene: Variant = entry.get("scene")
	if scene is PackedScene:
		return scene
	var path: String = String(entry.get("path", ""))
	if path.is_empty():
		push_error("GDFrame UI: 场景路径为空（%s）" % ui_id)
		return null
	scene = ResourceLoader.load(path) as PackedScene
	if scene == null:
		push_error("GDFrame UI: 无法加载 %s" % path)
		return null
	entry["scene"] = scene
	return scene

func _attach(ui: Control, ui_id: StringName, resolved_layer: int) -> void:
	var parent: Control = _layer_roots[resolved_layer]
	if ui.get_parent() != parent:
		parent.add_child(ui)

func _set_visible(ui: Control, visible: bool) -> void:
	if ui != null and is_instance_valid(ui):
		ui.visible = visible

func _resolve_layer(ui: Control, _ui_id: StringName, layer: int) -> int:
	var resolved_layer: int = layer
	if resolved_layer < 0 and ui is GDFrameUIBase:
		resolved_layer = (ui as GDFrameUIBase).ui_default_layer
	return clampi(resolved_layer, 0, _layer_count - 1)

# =============================================================================
# Registry & dim
# =============================================================================

func _resolve_use_dim(ui: GDFrameUIBase, _ui_id: StringName, data: Variant) -> bool:
	var resolved: Variant = ui.resolve_use_dim(data)
	if resolved is bool:
		return resolved
	return ui.ui_use_dim

func _dim_push_stack(ui_id: StringName) -> void:
	var idx: int = _dim_stack.find(ui_id)
	if idx >= 0:
		_dim_stack.remove_at(idx)
	_dim_stack.append(ui_id)

func _dim_remove_stack(ui_id: StringName) -> void:
	var idx: int = _dim_stack.find(ui_id)
	if idx >= 0:
		_dim_stack.remove_at(idx)


## 从 dim 栈顶向下，把 dim 挂到第一个仍可见的 owner 前；栈空则隐藏。

func _restore_dim_from_stack() -> void:
	for i: int in range(_dim_stack.size() - 1, -1, -1):
		var ui_id: StringName = _dim_stack[i]
		var ui: GDFrameUIBase = _cache.get(ui_id) as GDFrameUIBase
		if ui != null and is_instance_valid(ui) and ui.visible:
			_place_dim_before_ui(ui)
			return
	_hide_dim()


## 将 dim 置于 [param ui] 正前方，并保持 [param ui] 为同级最末（见 [GDFrameUIBase]）。

func _place_dim_before_ui(ui: Control) -> void:
	if ui == null or not is_instance_valid(ui):
		_hide_dim()
		return
	var parent: Node = ui.get_parent()
	if parent == null:
		_hide_dim()
		return
	if _dim.get_parent() != null:
		_dim.get_parent().remove_child(_dim)
	parent.move_child(ui, -1)
	parent.add_child(_dim)
	parent.move_child(_dim, ui.get_index())
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.set_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = true
	_notify_dim_visible(true, ui)

func _hide_dim() -> void:
	if _dim != null and _dim.visible:
		_notify_dim_visible(false, null)
	_dim.visible = false


func _instantiate_contract_dim() -> Control:
	var path: String = GDFrameConfig.DIM_SCENE_PATH
	var msg_missing: String = "GDFrame UI: 缺少契约遮罩场景 %s（请重载 GDFrame 插件）。" % path
	assert(ResourceLoader.exists(path), msg_missing)
	var scene: PackedScene = load(path) as PackedScene
	var msg_load: String = "GDFrame UI: 无法加载契约遮罩场景 %s" % path
	assert(scene != null, msg_load)
	var dim: Control = scene.instantiate() as Control
	var msg_root: String = "GDFrame UI: 契约遮罩场景根节点须为 Control — %s" % path
	assert(dim != null, msg_root)
	return dim


func _notify_dim_visible(visible: bool, ui: Control) -> void:
	if _dim == null:
		return
	var ui_id: StringName = &""
	if ui is GDFrameUIBase:
		ui_id = _nav_ui_id(ui as GDFrameUIBase)
	if visible:
		if _dim.has_method(&"on_dim_show"):
			_dim.call("on_dim_show", ui_id)
	else:
		if _dim.has_method(&"on_dim_hide"):
			_dim.call("on_dim_hide")

# =============================================================================
# Navigation — focus restore
# =============================================================================

func _nav_viewport() -> Viewport:
	if _nav_vp != null and is_instance_valid(_nav_vp):
		return _nav_vp
	if _root == null:
		return null
	_nav_vp = _root.get_viewport()
	return _nav_vp


## 关闭 UI 后释放仍挂在该面板（或已不可见控件）上的 GUI 焦点。

func _nav_release_focus_for_closed_ui(ui: GDFrameUIBase) -> void:
	if ui == null or not is_instance_valid(ui):
		return
	var vp: Viewport = _nav_viewport()
	if vp == null:
		return
	GDFrameUINav.release_focus_within(ui, vp)
	var owner: Control = vp.gui_get_focus_owner() as Control
	if owner == null:
		return
	if ui.is_ancestor_of(owner) or not owner.is_visible_in_tree():
		vp.gui_release_focus()


## 焦点不在 [param ui] 内时释放，并返回仍有效的 GUI 焦点控件。

func _nav_focus_owner_for_ui(ui: GDFrameUIBase, vp: Viewport) -> Control:
	if ui == null or vp == null:
		return null
	var owner: Control = vp.gui_get_focus_owner() as Control
	if owner == null:
		return null
	if not ui.is_ancestor_of(owner) or not owner.is_visible_in_tree():
		vp.gui_release_focus()
		return null
	return owner


## 子 UI 关闭后还焦；[code]close[/code] 同步调用，框架延迟一帧再确认焦点。

func _nav_resolve_restore_parent(restore_after_close: Dictionary) -> GDFrameUIBase:
	var parent: GDFrameUIBase = null

	var restore_control: Control = restore_after_close.get("control") as Control
	if restore_control != null:
		parent = _nav_find_ui_ancestor(restore_control, false)

	if parent == null:
		var parent_id_v: Variant = restore_after_close.get("parent_id")
		if parent_id_v != null and String(parent_id_v) != "":
			parent = get(StringName(String(parent_id_v))) as GDFrameUIBase

	if parent == null:
		parent = _nav_find_parent_by_control_path(restore_after_close)

	if parent == null or not is_instance_valid(parent):
		parent = _nav_visible_stack_ui(_stack.size() - 1) if not _stack.is_empty() else null

	if parent == null or not is_instance_valid(parent):
		parent = get_active_ui()

	if parent == null or not is_instance_valid(parent):
		return null
	return parent

func _nav_restore_control_path(parent: GDFrameUIBase, restore_after_close: Dictionary) -> String:
	var stored: NodePath = GDFrameUINav.read_return_path(parent, restore_after_close)
	if not stored.is_empty():
		return str(stored)
	var restore_control: Control = restore_after_close.get("control") as Control
	if restore_control != null and parent.is_ancestor_of(restore_control):
		return str(parent.get_path_to(restore_control))
	var idx_v: Variant = restore_after_close.get("control_index", -1)
	if idx_v is int or idx_v is float:
		var idx: int = int(idx_v)
		if idx >= 0:
			var items: Array[Control] = parent.ui_nav_get_items()
			if idx < items.size():
				var item: Control = items[idx]
				if item != null and parent.is_ancestor_of(item):
					return str(parent.get_path_to(item))
	return ""

func _nav_find_parent_by_control_path(restore_after_close: Dictionary) -> GDFrameUIBase:
	var stored: NodePath = GDFrameUINav.read_return_path(null, restore_after_close)
	if stored.is_empty():
		return null
	var parent_id_v: Variant = restore_after_close.get("parent_id")
	if parent_id_v == null or String(parent_id_v) == "":
		return null
	var parent: GDFrameUIBase = get(StringName(String(parent_id_v))) as GDFrameUIBase
	if parent == null or not is_instance_valid(parent):
		return null
	if parent.get_node_or_null(stored) != null:
		return parent
	return null

func _nav_find_parent_on_stack() -> GDFrameUIBase:
	for i: int in range(_stack.size() - 1, -1, -1):
		var ui: GDFrameUIBase = _nav_visible_stack_ui(i)
		if ui == null:
			continue
		if not ui.ui_nav_participates() or ui.ui_nav_is_overlay_blocker():
			continue
		if ui.ui_nav_can_receive_focus():
			return ui
	return null

func _nav_find_ui_ancestor(control: Control, require_in_cache: bool = true) -> GDFrameUIBase:
	var node: Node = control
	while node != null:
		if node is GDFrameUIBase:
			var ui: GDFrameUIBase = node as GDFrameUIBase
			if not require_in_cache or _nav_ui_id(ui) != &"":
				return ui
		node = node.get_parent()
	return null

func _nav_ui_id(ui: GDFrameUIBase) -> StringName:
	if ui == null or not is_instance_valid(ui):
		return &""
	return _ui_instance_to_id.get(ui.get_instance_id(), &"") as StringName

# =============================================================================
# Navigation — lock & suspend
# =============================================================================

## [b]仅[/b]在 [code]open[/code] 子 UI 时调用：把 [code]data.nav_from[/code] 写入恢复票据，供 [code]close[/code] 还焦。

func _nav_bind_return_focus_ticket(
	opened_ui_id: StringName,
	parent: GDFrameUIBase,
	opener: Control,
) -> void:
	if parent == null and opener != null:
		parent = _nav_find_ui_ancestor(opener)
	if parent == null:
		return
	var parent_id: StringName = _nav_ui_id(parent)
	if parent_id.is_empty():
		return
	var return_focus: Control = opener
	if return_focus == null:
		return_focus = parent.ui_nav_get_last_focus()
	if return_focus == null:
		return_focus = parent.ui_nav_init_focus(null)
	var entry: Dictionary = {
		"parent_id": String(parent_id),
		"control": return_focus,
	}
	if (
		return_focus != null
		and parent.is_ancestor_of(return_focus)
	):
		entry["control_path"] = str(parent.get_path_to(return_focus))
		GDFrameUINav.set_return_path(parent, return_focus)
		parent.ui_nav_remember_focus(return_focus)
		var items: Array[Control] = parent.ui_nav_get_items()
		var idx: int = items.find(return_focus)
		if idx >= 0:
			entry["control_index"] = idx
	_nav_return_focus[opened_ui_id] = entry


## 打开子 UI 时锁定栈内下层 UI（[code]focus_mode = NONE[/code]），阻止 Godot neighbor 导航。

func _nav_lock_stack_below(opened_ui_id: StringName) -> void:
	var top_idx: int = int(_stack_index.get(opened_ui_id, -1))
	if top_idx < 0:
		top_idx = _stack.find(opened_ui_id)
	if top_idx < 0:
		return
	var vp: Viewport = _nav_viewport()
	var locked_ids: Array[StringName] = []
	for i: int in range(top_idx - 1, -1, -1):
		var below_id: StringName = _stack[i]
		var below_ui: GDFrameUIBase = get(below_id) as GDFrameUIBase
		if below_ui == null or not is_instance_valid(below_ui) or not below_ui.visible:
			continue
		if not below_ui.ui_nav_participates():
			continue
		GDFrameUINav.suspend(below_ui, vp)
		locked_ids.append(below_id)
	if not locked_ids.is_empty():
		_nav_locked_by[opened_ui_id] = locked_ids


## 打开子 UI 后，若 GUI 焦点仍停在被锁定的下层控件上则强制释放（避免 Godot 内置 neighbor 导航）。

func _nav_release_gui_focus_from_locked(opened_ui_id: StringName) -> void:
	var vp: Viewport = _nav_viewport()
	if vp == null:
		return
	var locked_ids: Variant = _nav_locked_by.get(opened_ui_id, [])
	if not locked_ids is Array:
		return
	var owner: Control = vp.gui_get_focus_owner() as Control
	if owner == null:
		return
	for below_id: Variant in locked_ids as Array:
		var below_ui: GDFrameUIBase = get(below_id as StringName) as GDFrameUIBase
		if below_ui == null or not is_instance_valid(below_ui):
			continue
		if below_ui.is_ancestor_of(owner):
			vp.gui_release_focus()
			return


## 栈遍历未锁定时仍挂起 [param nav_parent]，以便关闭子 UI 后还焦。

func _nav_ensure_parent_locked(opened_ui_id: StringName, nav_parent: GDFrameUIBase) -> void:
	if nav_parent == null or not is_instance_valid(nav_parent) or not nav_parent.visible:
		return
	if not nav_parent.ui_nav_participates():
		return
	var parent_id: StringName = _nav_ui_id(nav_parent)
	if parent_id.is_empty():
		return
	var locked_ids: Array = _nav_locked_by.get(opened_ui_id, []) as Array
	if _nav_locked_id_present(locked_ids, parent_id):
		return
	if GDFrameUINav.is_suspended(nav_parent):
		locked_ids.append(parent_id)
		_nav_locked_by[opened_ui_id] = locked_ids
		return
	var vp: Viewport = _nav_viewport()
	GDFrameUINav.suspend(nav_parent, vp)
	locked_ids.append(parent_id)
	_nav_locked_by[opened_ui_id] = locked_ids

func _nav_locked_id_present(locked_ids: Array, ui_id: StringName) -> bool:
	for entry: Variant in locked_ids:
		if StringName(String(entry)) == ui_id:
			return true
	return false


## 关闭子 UI 时解锁本次打开所锁定的下层 UI。

func _nav_unlock_for_close(closed_ui_id: StringName) -> void:
	var locked_ids: Variant = _nav_locked_by.get(closed_ui_id, [])
	_nav_locked_by.erase(closed_ui_id)
	if locked_ids is Array:
		for below_id: Variant in locked_ids as Array:
			var below_ui: GDFrameUIBase = get(below_id as StringName) as GDFrameUIBase
			if below_ui == null or not is_instance_valid(below_ui):
				continue
			GDFrameUINav.restore(below_ui)
			if not GDFrameUINav.is_suspended(below_ui):
				below_ui.ui_nav_force_ready_for_input()


## 从各 opener 的锁定列表中移除已关闭 UI（子 UI 先于 opener 关闭时）。

func _nav_prune_closed_ui_from_locks(closed_ui_id: StringName) -> void:
	for opener_id: Variant in _nav_locked_by.keys():
		var locked_ids: Array = _nav_locked_by[opener_id] as Array
		locked_ids.erase(closed_ui_id)
		if locked_ids.is_empty():
			_nav_locked_by.erase(opener_id)
		else:
			_nav_locked_by[opener_id] = locked_ids


## 关闭弹窗后清除栈顶 UI 的过时挂起状态。

func _nav_clear_stale_suspend_on_stack() -> void:
	if _stack.is_empty():
		return
	var top_id: StringName = _stack[_stack.size() - 1]
	var top: GDFrameUIBase = get(top_id) as GDFrameUIBase
	if top == null or not is_instance_valid(top):
		return
	if not top.ui_nav_participates() or not top.ui_nav_can_receive_focus():
		return
	GDFrameUINav.force_enable_navigation(top)
	top.ui_nav_force_ready_for_input()


# =============================================================================
# Navigation — active UI
# =============================================================================

## 返回当前应接收导航焦点的可见 UI（自栈顶向下扫描）。

func _compute_active_ui() -> GDFrameUIBase:
	var seen_blocker: bool = false
	for i: int in range(_stack.size() - 1, -1, -1):
		var ui: GDFrameUIBase = _nav_visible_stack_ui(i)
		if ui == null:
			continue
		var blocker_above: bool = seen_blocker
		if ui.ui_nav_is_overlay_blocker():
			seen_blocker = true
		if not ui.ui_nav_participates() or ui.ui_nav_is_overlay_blocker():
			continue
		if blocker_above:
			continue
		if not _nav_unsuspend_if_stack_top(ui, i):
			continue
		if not ui.ui_nav_can_receive_focus():
			continue
		if ui.ui_nav_has_items() and not ui.ui_nav_items_input_enabled():
			continue
		return ui
	return null

func _nav_visible_stack_ui(index: int) -> GDFrameUIBase:
	if index < 0 or index >= _stack.size():
		return null
	var ui: Variant = _cache.get(_stack[index])
	if ui is not GDFrameUIBase:
		return null
	var base: GDFrameUIBase = ui as GDFrameUIBase
	if not is_instance_valid(base) or not base.visible:
		return null
	return base

func _nav_unsuspend_if_stack_top(ui: GDFrameUIBase, stack_index: int) -> bool:
	if not GDFrameUINav.is_suspended(ui):
		return true
	if stack_index != _stack.size() - 1:
		return false
	GDFrameUINav.force_enable_navigation(ui)
	ui.ui_nav_ensure_item_focus_modes()
	return true


## 从栈顶向下找第一个 [method GDFrameUIBase.ui_closes_on_cancel] 为 [code]true[/code] 的 UI。

func _top_cancel_closable_ui() -> GDFrameUIBase:
	for i: int in range(_stack.size() - 1, -1, -1):
		var ui_id: StringName = _stack[i]
		var ui: GDFrameUIBase = _get_cached_ui(ui_id)
		if ui == null:
			continue
		if not is_open(ui_id):
			continue
		if ui.ui_closes_on_cancel():
			return ui
	return null

