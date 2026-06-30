## UI 键盘/手柄焦点导航辅助（框架内部使用）。
class_name GDFrameUINav
extends RefCounted

# =============================================================================
# Enums
# =============================================================================

enum FocusPolicy {
	ANY,
	BUTTONS_ONLY,
}

enum NavPress {
	NONE = 0,
	ACCEPT,
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

# =============================================================================
# Constants
# =============================================================================

const META_SUSPEND_DEPTH: StringName = &"gdframe_ui_nav_suspend_depth"
const META_FOCUS_MODES: StringName = &"gdframe_ui_nav_focus_modes"
const META_NAV_RETURN_PATH: StringName = &"gdframe_nav_return_path"

## [code]ui_open[/code] / [code]ui_nav_focus_on_show[/code] 的 [code]data[/code] 键。
const DATA_NAV_FROM: StringName = &"nav_from"
const DATA_NAV_RESTORE_LAST: StringName = &"nav_restore_last"
const DATA_NAV_FOCUS: StringName = &"nav_focus"

# =============================================================================
# Return path & data
# =============================================================================

static func set_return_path(parent: GDFrameUIBase, control: Control) -> void:
	if parent == null or control == null or not is_instance_valid(parent) or not is_instance_valid(control):
		return
	if not parent.is_ancestor_of(control):
		return
	parent.set_meta(META_NAV_RETURN_PATH, str(parent.get_path_to(control)))

static func read_return_path(parent: GDFrameUIBase, restore: Dictionary) -> NodePath:
	var path_v: Variant = restore.get("control_path")
	if path_v is NodePath:
		var stored_path: NodePath = path_v as NodePath
		if not stored_path.is_empty():
			return stored_path
	if path_v is String and not String(path_v).is_empty():
		return NodePath(String(path_v))
	if parent != null and is_instance_valid(parent) and parent.has_meta(META_NAV_RETURN_PATH):
		var meta: Variant = parent.get_meta(META_NAV_RETURN_PATH)
		if meta is String and not String(meta).is_empty():
			return NodePath(String(meta))
		if meta is NodePath and not (meta as NodePath).is_empty():
			return meta as NodePath
	return NodePath()

static func read_open_focus_control(data: Variant) -> Control:
	return _read_control_field(data, DATA_NAV_FOCUS)

static func read_nav_from(data: Variant) -> Control:
	return _read_control_field(data, DATA_NAV_FROM)

static func should_restore_last_focus(data: Variant) -> bool:
	if data is Dictionary:
		return bool((data as Dictionary).get(DATA_NAV_RESTORE_LAST, false))
	return false

# =============================================================================
# Focus query
# =============================================================================

static func is_focusable(c: Control, policy: int = FocusPolicy.ANY) -> bool:
	if not c.is_visible_in_tree():
		return false
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	if c.focus_mode == Control.FOCUS_NONE:
		return false
	if policy == FocusPolicy.BUTTONS_ONLY:
		if not (c is Button or c is LinkButton):
			return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	if c is Slider and not (c as Slider).editable:
		return false
	return true

static func find_first_focusable(root: Control, policy: int = FocusPolicy.ANY) -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var found: Control = null
	_walk(root, func(c: Control) -> bool:
		if is_focusable(c, policy):
			found = c
			return true
		return false
	)
	return found

static func move_in_items(items: Array, current: Control, delta: int, wraps: bool = true) -> Control:
	if items.is_empty() or delta == 0:
		return null
	var size: int = items.size()
	var index: int = items.find(current)
	if index < 0:
		index = 0 if delta > 0 else size - 1
	else:
		var next_index: int = index + delta
		if wraps:
			index = posmod(next_index, size)
		elif next_index < 0 or next_index >= size:
			return null
		else:
			index = next_index
	for _attempt: int in range(size):
		var candidate: Control = items[index] as Control
		if candidate != null and is_focusable(candidate, FocusPolicy.ANY):
			return candidate
		if not wraps:
			return null
		index = posmod(index + delta, size)
	return null

static func resolve_focus_target(
	ui: GDFrameUIBase,
	data: Variant,
	last_focus: Control,
	policy: int,
) -> Control:
	var explicit: Control = read_open_focus_control(data)
	if (
		explicit != null
		and is_instance_valid(explicit)
		and ui.is_ancestor_of(explicit)
		and is_focusable(explicit, policy)
	):
		return explicit
	if (
		last_focus != null
		and is_instance_valid(last_focus)
		and ui.is_ancestor_of(last_focus)
		and is_focusable(last_focus, policy)
	):
		return last_focus
	var init_focus: Control = ui.ui_nav_init_focus(data)
	if init_focus != null and is_instance_valid(init_focus) and is_focusable(init_focus, policy):
		return init_focus
	if ui.ui_nav_has_items():
		var items: Array[Control] = ui.ui_nav_get_items()
		if not items.is_empty():
			return items[0]
	return find_first_focusable(ui, policy)

# =============================================================================
# Neighbor wiring
# =============================================================================

static func link_vertical_buttons(buttons: Array, wraps: bool = true) -> void:
	link_vertical_controls(buttons, wraps)

static func link_horizontal_buttons(buttons: Array, wraps: bool = true) -> void:
	link_horizontal_controls(buttons, wraps)

static func link_horizontal_controls(controls: Array, wraps: bool = true) -> void:
	_link_control_neighbors(controls, false, wraps)

static func link_vertical_controls(controls: Array, wraps: bool = true) -> void:
	_link_control_neighbors(controls, true, wraps)

static func _link_control_neighbors(controls: Array, vertical: bool, wraps: bool = true) -> void:
	var prev_key: StringName = &"focus_neighbor_top" if vertical else &"focus_neighbor_left"
	var next_key: StringName = &"focus_neighbor_bottom" if vertical else &"focus_neighbor_right"
	var prev_on_next: StringName = &"focus_neighbor_bottom" if vertical else &"focus_neighbor_right"
	var next_on_prev: StringName = &"focus_neighbor_top" if vertical else &"focus_neighbor_left"
	for i: int in range(controls.size()):
		var ctrl: Control = controls[i] as Control
		if ctrl == null:
			continue
		if i > 0:
			var prev: Control = controls[i - 1] as Control
			if prev != null:
				ctrl.set(prev_key, ctrl.get_path_to(prev))
				prev.set(prev_on_next, prev.get_path_to(ctrl))
		if i + 1 < controls.size():
			var next: Control = controls[i + 1] as Control
			if next != null:
				ctrl.set(next_key, ctrl.get_path_to(next))
				next.set(next_on_prev, next.get_path_to(ctrl))
	if not wraps or controls.size() < 2:
		return
	var first: Control = controls[0] as Control
	var last: Control = controls[controls.size() - 1] as Control
	if first == null or last == null:
		return
	first.set(prev_key, first.get_path_to(last))
	last.set(next_key, last.get_path_to(first))

# =============================================================================
# Viewport focus
# =============================================================================

static func capture_focused_child(parent: Control, viewport: Viewport) -> Control:
	if viewport == null:
		return null
	var owner: Control = viewport.gui_get_focus_owner() as Control
	if owner == null:
		return null
	if parent != null and parent.is_ancestor_of(owner):
		return owner
	return null

static func release_focus_within(ui: Control, viewport: Viewport) -> void:
	if ui == null or viewport == null:
		return
	var owner: Control = viewport.gui_get_focus_owner() as Control
	if owner != null and ui.is_ancestor_of(owner):
		owner.release_focus()

# =============================================================================
# Suspend
# =============================================================================

static func is_suspended(ui: GDFrameUIBase) -> bool:
	if ui == null or not is_instance_valid(ui):
		return false
	return int(ui.get_meta(META_SUSPEND_DEPTH, 0)) > 0

static func suspend(ui: GDFrameUIBase, viewport: Viewport) -> void:
	if ui == null or not is_instance_valid(ui):
		return
	var depth: int = int(ui.get_meta(META_SUSPEND_DEPTH, 0))
	if depth == 0:
		var modes: Dictionary = {}
		_walk(ui, func(c: Control) -> bool:
			if c.focus_mode == Control.FOCUS_NONE:
				return false
			modes[c.get_instance_id()] = c.focus_mode
			c.focus_mode = Control.FOCUS_NONE
			return false
		)
		ui.set_meta(META_FOCUS_MODES, modes)
		release_focus_within(ui, viewport)
	depth += 1
	ui.set_meta(META_SUSPEND_DEPTH, depth)

static func restore(ui: GDFrameUIBase) -> void:
	if ui == null or not is_instance_valid(ui):
		return
	var depth: int = int(ui.get_meta(META_SUSPEND_DEPTH, 0))
	if depth <= 0:
		return
	depth -= 1
	ui.set_meta(META_SUSPEND_DEPTH, depth)
	if depth > 0:
		return
	force_enable_navigation(ui)


## 解除挂起并恢复全部可导航控件的 [member Control.focus_mode]（栈顶 UI 或挂起深度归零后调用）。

static func force_enable_navigation(ui: GDFrameUIBase) -> void:
	if ui == null or not is_instance_valid(ui):
		return
	var modes: Dictionary = {}
	if ui.has_meta(META_FOCUS_MODES):
		modes = ui.get_meta(META_FOCUS_MODES) as Dictionary
	if not modes.is_empty():
		_walk(ui, func(c: Control) -> bool:
			var id: int = c.get_instance_id()
			if modes.has(id):
				c.focus_mode = int(modes[id])
			return false
		)
	_reenable_default_focus_modes(ui)
	if ui.has_meta(META_FOCUS_MODES):
		ui.remove_meta(META_FOCUS_MODES)
	if ui.has_meta(META_SUSPEND_DEPTH):
		ui.remove_meta(META_SUSPEND_DEPTH)

static func _reenable_default_focus_modes(ui: GDFrameUIBase) -> void:
	_walk(ui, func(c: Control) -> bool:
		if (
			c is BaseButton
			or c is Slider
			or c is OptionButton
			or c is CheckBox
		):
			if c.focus_mode == Control.FOCUS_NONE:
				c.focus_mode = Control.FOCUS_ALL
		return false
	)

# =============================================================================
# Input
# =============================================================================

static func nav_pressed_action(event: InputEvent) -> int:
	var joy_motion: bool = event is InputEventJoypadMotion
	if not joy_motion and event.is_action_pressed("ui_accept"):
		return NavPress.ACCEPT
	if event.is_action_pressed("ui_up"):
		return NavPress.UP
	if event.is_action_pressed("ui_down"):
		return NavPress.DOWN
	if event.is_action_pressed("ui_left"):
		return NavPress.LEFT
	if event.is_action_pressed("ui_right"):
		return NavPress.RIGHT
	return NavPress.NONE


## 键盘/手柄 [code]ui_accept[/code] 时触发当前控件的确认行为（按类型分发）。

static func activate_accept(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if control is OptionButton:
		var option: OptionButton = control as OptionButton
		if option.disabled:
			return false
		option.show_popup()
		return true
	if control is MenuButton:
		var menu: MenuButton = control as MenuButton
		if menu.disabled:
			return false
		menu.show_popup()
		return true
	if control is CheckBox or control is CheckButton:
		var check: BaseButton = control as BaseButton
		if check.disabled:
			return false
		check.button_pressed = not check.button_pressed
		return true
	if control is BaseButton:
		var btn: BaseButton = control as BaseButton
		if btn.disabled:
			return false
		btn.pressed.emit()
		return true
	return false

# =============================================================================
# Private
# =============================================================================

static func _read_control_field(data: Variant, key: StringName) -> Control:
	if data is Dictionary:
		var field_v: Variant = (data as Dictionary).get(key)
		if field_v is Control:
			return field_v as Control
	return null

static func _walk(node: Node, visitor: Callable) -> bool:
	if node is Control:
		if visitor.call(node as Control):
			return true
	for child: Node in node.get_children():
		if _walk(child, visitor):
			return true
	return false

