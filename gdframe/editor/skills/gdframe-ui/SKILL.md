---
name: gdframe-ui
description: >-
  Author GDFrame game UI under gdframe_project/ui: GDFrameUIBase lifecycle,
  nav focus, ui_open/preload, locale, toast/tip patterns. Use when creating or
  editing ui_* scenes/scripts, wiring Dock-created UI, or when the user asks
  how to write GDFrame UI code.
---

# GDFrame UI

在 **`res://gdframe_project/ui/`** 编写，与 Dock「创建 UI」一致。API 见 `editor/README.md` §6。

## Layout

```
gdframe_project/ui/ui_<name>/
  ui_<name>.tscn    # 根 Control，脚本挂根上
  ui_<name>.gd      # extends GDFrameUIBase
```

- 导出：`ui_default_layer` / `ui_use_dim` / `ui_nav_participates`，或 Dock **UI管理**
- 跨文件引用再加 `class_name UiXxx`
- `@export_category("节点绑定")` + `@export var _btn_…`，拖引用；禁止长路径 `get_node`

## Lifecycle

| 钩子 | 用途 |
|------|------|
| `_on_init()` | 一次：信号、`ui_nav_set_items`、`GDFrameUINav.link_*` |
| `_on_show(data)` | 每次打开；非 restore 时 `ui_nav_clear_stored_focus()` |
| `_on_close() -> bool` | `return false` 可拦截关闭 |
| `_on_locale_changed()` | `tr()` 刷新 |

文案优先 `title_key` / `message_key` + `tr()`。

## Navigation

- 参与栈：`FOCUS_ALL` → `link_vertical_controls` / `link_horizontal_controls` → `ui_nav_set_items`；`ui_nav_init_focus`；需 Esc 则 `ui_closes_on_cancel() -> true`
- Toast / 浮层：`ui_nav_participates = false` → **永不进栈**
- 还焦：`ui_open(..., {"nav_from": _btn})`；替换栈顶：`ui_open_replace`
- 先 `await ui_preload`；ID 用 `GDFrameConstants.UI_*`

## Tip / Toast

- **Tip**：模态；`mode` + `on_result`；Esc 与 `ui_cancel_close` 一致
- **Toast**：`ui_open(UI_TOAST, {"message_key": "…"})`；可重复 open

## Anti-patterns

- 业务逻辑进 `addons/gdframe/`；硬编码 `ui_*.tscn` 路径；`_process` 轮询 UI
- Toast 使用 `ui_nav_participates = true`

## Template

```gdscript
extends GDFrameUIBase

@export_category("节点绑定")
@export var _btn_ok: Button
@export var _title: Label


func _on_init() -> void:
	_btn_ok.focus_mode = Control.FOCUS_ALL
	ui_nav_set_items([_btn_ok])
	_btn_ok.pressed.connect(_on_ok_pressed)


func _on_show(_data: Variant = null) -> void:
	_refresh_ui()
	if not GDFrameUINav.should_restore_last_focus(_data):
		ui_nav_clear_stored_focus()


func _on_locale_changed() -> void:
	_refresh_ui()


func ui_nav_init_focus(_data: Variant) -> Control:
	return _btn_ok


func ui_closes_on_cancel() -> bool:
	return true


func _refresh_ui() -> void:
	_title.text = tr("UI_EXAMPLE_TITLE")
	_btn_ok.text = tr("UI_EXAMPLE_OK")


func _on_ok_pressed() -> void:
	GDFrame.ui_close(GDFrameConstants.UI_EXAMPLE)
```
