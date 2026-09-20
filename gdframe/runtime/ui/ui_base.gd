class_name GDFrameUIBase
extends Control

## GDFrame UI 基类。默认层、遮罩与是否参与导航见根节点 [b]GDFrame[/b] 分组或 Dock [b]UI管理[/b]；按次遮罩可 override [method resolve_use_dim]。

# =============================================================================
# GDFrame settings
# =============================================================================

@export_group("GDFrame")
## [method GDFrame.ui_open] 的 [code]layer=-1[/code] 时使用的默认层编号（从 0 起）。
@export_range(0, 63) var ui_default_layer: int = 0
## 打开时是否显示全屏 dim 遮罩；[method resolve_use_dim] 返回 [code]bool[/code] 时按次覆盖。
@export var ui_use_dim: bool = false
## 是否参与 UI 打开栈与导航（锁定下层、还焦、成为活跃面板）。为 [code]false[/code] 时永不进入打开栈，因此不锁定下层、不抢焦点，适合浮层提示。
@export var ui_nav_participates: bool = true

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_behavior_recursive = FOCUS_BEHAVIOR_ENABLED

## 预加载钩子；内部可以 [code]await[/code]（如异步加载资源）。须 [code]await GDFrame.ui_preload[/code]。
func _on_init() -> void:
	pass

func _on_show(_data: Variant = null) -> void:
	pass

func _on_close() -> bool:
	return true

func _on_locale_changed() -> void:
	pass


# =============================================================================
# Dim & cancel
# =============================================================================

func resolve_use_dim(_data: Variant) -> Variant:
	return null


## Esc 关闭：从打开栈顶向下，第一个 [method ui_closes_on_cancel] 为 [code]true[/code] 的 UI 会响应。
func ui_closes_on_cancel() -> bool:
	return false


## Esc 关闭行为；默认 [code]GDFrame.ui_close[/code]。子类应复用关闭按钮同款逻辑（如未保存提示）。
func ui_cancel_close() -> void:
	var ui_id: StringName = GDFrame.ui_get_id(self)
	if not ui_id.is_empty():
		GDFrame.ui_close(ui_id)


# =============================================================================
# State — navigation
# =============================================================================

var _ui_nav_last_focus: Control = null
var _ui_nav_items: Array[Control] = []
var _ui_nav_items_input_enabled: bool = true
var _ui_nav_input_saved: Dictionary = {}

# =============================================================================
# Nav — overrides
# =============================================================================

func ui_nav_is_overlay_blocker() -> bool:
	return false

func ui_nav_can_receive_focus() -> bool:
	return true


## [code]ui_open[/code] 后是否自动聚焦；默认 [code]true[/code]。改为 [code]false[/code] 时须自行调用 [method ui_nav_focus_on_show]。
func ui_nav_auto_focus_on_show() -> bool:
	return true

func ui_nav_init_focus(_data: Variant) -> Control:
	return null

func ui_nav_uses_horizontal() -> bool:
	return false


## 方向键到达列表首尾时是否循环（默认 [code]true[/code]）。子类 override 为 [code]false[/code] 可改为到头停住。
func ui_nav_wraps() -> bool:
	return true

# =============================================================================
# Nav — items
# =============================================================================

func ui_nav_items_input_enabled() -> bool:
	return _ui_nav_items_input_enabled


## 批量开关 [method ui_nav_set_items] 注册的导航项：禁用为 [code]mouse_filter = IGNORE[/code] + [code]focus_mode = NONE[/code]。
func ui_nav_set_items_input_enabled(enabled: bool) -> void:
	if _ui_nav_items_input_enabled == enabled:
		return
	_ui_nav_items_input_enabled = enabled
	if enabled:
		_ui_nav_restore_items_input()
	else:
		_ui_nav_block_items_input()

func ui_nav_set_items(items: Array) -> void:
	_ui_nav_unbind_pointer_remember()
	_ui_nav_items.clear()
	for item: Variant in items:
		if item is Control:
			_ui_nav_items.append(item as Control)
	_ui_nav_bind_pointer_remember()
	ui_nav_sync_item_focus_modes()

func ui_nav_has_items() -> bool:
	return not _ui_nav_items.is_empty()

func ui_nav_get_items() -> Array[Control]:
	return _ui_nav_filter_nav_items()

func ui_nav_get_last_focus() -> Control:
	if is_instance_valid(_ui_nav_last_focus):
		return _ui_nav_last_focus
	return null


## 弹窗关闭后解除挂起并恢复全部导航项（忽略挂起守卫）。
func ui_nav_force_ready_for_input() -> void:
	GDFrameUINav.force_enable_navigation(self)
	if not _ui_nav_items_input_enabled:
		return
	ui_nav_sync_item_focus_modes()


## 按节点路径聚焦（子 UI 关闭还焦）。
func ui_nav_apply_focus_by_path(path: String) -> void:
	ui_nav_force_ready_for_input()
	var control: Control = _ui_nav_control_at_path(path)
	if control != null:
		ui_nav_apply_focus(control)


## 记录导航项（不抢焦点），供关闭子 UI 后还焦。
func ui_nav_remember_focus(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not is_ancestor_of(control):
		return
	_ui_nav_last_focus = control


## 子类在需要重置导航记忆时调用（如每次打开都从首项开始时）
func ui_nav_clear_stored_focus() -> void:
	_ui_nav_last_focus = null


func _ui_nav_block_items_input() -> void:
	_ui_nav_input_saved.clear()
	for item: Control in _ui_nav_items:
		if item == null or not is_instance_valid(item):
			continue
		var id: int = item.get_instance_id()
		_ui_nav_input_saved[id] = item.mouse_filter
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.focus_mode = Control.FOCUS_NONE
	var vp: Viewport = get_viewport()
	if vp != null:
		GDFrameUINav.release_focus_within(self, vp)


func _ui_nav_restore_items_input() -> void:
	for item: Control in _ui_nav_items:
		if item == null or not is_instance_valid(item):
			continue
		var id: int = item.get_instance_id()
		if not _ui_nav_input_saved.has(id):
			continue
		item.mouse_filter = int(_ui_nav_input_saved[id])
	_ui_nav_input_saved.clear()
	ui_nav_sync_item_focus_modes()


func _ui_nav_filter_nav_items() -> Array[Control]:
	var filtered: Array[Control] = []
	for item: Control in _ui_nav_items:
		if GDFrameUINav.is_nav_candidate(item):
			filtered.append(item)
	return filtered


func _ui_nav_bind_pointer_remember() -> void:
	for item: Control in _ui_nav_items:
		if item == null or not is_instance_valid(item):
			continue
		item.mouse_entered.connect(ui_nav_remember_focus.bind(item))


func _ui_nav_unbind_pointer_remember() -> void:
	for item: Control in _ui_nav_items:
		if item == null or not is_instance_valid(item):
			continue
		var cb: Callable = ui_nav_remember_focus.bind(item)
		if item.mouse_entered.is_connected(cb):
			item.mouse_entered.disconnect(cb)


func _ui_nav_release_non_text_focus() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var owner: Control = vp.gui_get_focus_owner() as Control
	if owner == null or not is_instance_valid(owner) or not is_ancestor_of(owner):
		return
	if GDFrameUINav.is_text_input(owner):
		return
	owner.release_focus()


## 按当前设备同步导航项 [member Control.focus_mode]：允许导航聚焦则 [constant Control.FOCUS_ALL]，否则非输入框为 [constant Control.FOCUS_NONE]。
func ui_nav_sync_item_focus_modes() -> void:
	if GDFrameUINav.is_suspended(self) or not _ui_nav_items_input_enabled:
		return
	var allow: bool = GDFrame.input_should_allow_nav_focus()
	for item: Control in _ui_nav_items:
		if item == null or not is_instance_valid(item):
			continue
		if GDFrameUINav.is_text_input(item):
			continue
		item.focus_mode = Control.FOCUS_ALL if allow else Control.FOCUS_NONE
	if not allow:
		_ui_nav_release_non_text_focus()


# =============================================================================
# Nav — focus
# =============================================================================

## 在 [code]_on_show[/code] 完成后聚焦导航项。
## 默认 [code]ui_nav_init_focus[/code] / 第一项；[code]data.nav_restore_last[/code] 为 [code]true[/code] 时恢复上次聚焦；[code]data.nav_focus[/code] 指定控件。
func ui_nav_focus_on_show(data: Variant) -> void:
	if not ui_nav_can_receive_focus():
		return
	var restore_last: bool = GDFrameUINav.should_restore_last_focus(data)
	if not restore_last:
		ui_nav_clear_stored_focus()
		_ui_nav_release_non_text_focus()
	ui_nav_sync_item_focus_modes()
	var last: Control = ui_nav_get_last_focus() if restore_last else null
	var target: Control = GDFrameUINav.resolve_focus_target(self, data, last)
	if target != null:
		ui_nav_apply_focus(target)


## 将 GUI 焦点移到 [param control] 并更新上次聚焦项；当前设备不允许导航聚焦时只记项、不抢焦点。
func ui_nav_apply_focus(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	_ui_nav_last_focus = control
	if not GDFrame.input_should_allow_nav_focus():
		return
	_ui_nav_ensure_focusable(control)
	if not _ui_nav_grab_focus(control):
		call_deferred(&"_ui_nav_deferred_grab_focus", control)


func _ui_nav_ensure_focusable(control: Control) -> void:
	if control.focus_mode == Control.FOCUS_NONE:
		control.focus_mode = Control.FOCUS_ALL


func _ui_nav_grab_focus(control: Control) -> bool:
	control.grab_focus()
	return get_viewport().gui_get_focus_owner() == control


func _ui_nav_deferred_grab_focus(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	if not GDFrame.input_should_allow_nav_focus():
		return
	_ui_nav_ensure_focusable(control)
	_ui_nav_grab_focus(control)


func _ui_nav_control_at_path(path: String) -> Control:
	if path.is_empty():
		return null
	var node: Node = get_node_or_null(NodePath(path))
	if node is Control and is_ancestor_of(node):
		return node as Control
	return null

# =============================================================================
# Nav — input
# =============================================================================

func ui_nav_current_item(items: Array[Control], focus_owner: Control = null) -> Control:
	if items.is_empty():
		return null
	var owner: Control = focus_owner
	if owner == null:
		owner = get_viewport().gui_get_focus_owner() as Control
	if owner != null and is_instance_valid(owner) and owner.is_visible_in_tree():
		if items.find(owner) >= 0:
			return owner
	if _ui_nav_last_focus != null and is_instance_valid(_ui_nav_last_focus):
		if items.find(_ui_nav_last_focus) >= 0:
			return _ui_nav_last_focus
	return null


func ui_nav_process_input(nav_action: int, focus_owner: Control = null) -> bool:
	if (
		(nav_action == GDFrameUINav.NavPress.LEFT or nav_action == GDFrameUINav.NavPress.RIGHT)
		and not ui_nav_uses_horizontal()
	):
		return false
	var items: Array[Control] = ui_nav_get_items()
	if items.is_empty():
		return false
	if nav_action == GDFrameUINav.NavPress.ACCEPT:
		var current: Control = ui_nav_current_item(items, focus_owner)
		if current == null:
			ui_nav_apply_focus(items[0])
			current = items[0]
		if GDFrameUINav.activate_accept(current):
			return true
		return false
	var delta: int = 0
	match nav_action:
		GDFrameUINav.NavPress.UP:
			delta = -1
		GDFrameUINav.NavPress.DOWN:
			delta = 1
		GDFrameUINav.NavPress.LEFT:
			delta = -1
		GDFrameUINav.NavPress.RIGHT:
			delta = 1
		_:
			return false
	var current_item: Control = ui_nav_current_item(items, focus_owner)
	if current_item == null:
		var index: int = 0 if delta > 0 else items.size() - 1
		ui_nav_apply_focus(items[index])
		return true
	if focus_owner != current_item:
		ui_nav_apply_focus(current_item)
	var next: Control = GDFrameUINav.move_in_items(
		items, current_item, delta, ui_nav_wraps()
	)
	if next != null:
		ui_nav_apply_focus(next)
		return true
	return false
