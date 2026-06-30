@tool
extends EditorPlugin


# =============================================================================
# Constants
# =============================================================================

const AUTOLOAD_PATH: String = "res://addons/gdframe/runtime/gdframe.gd"
const PLUGIN_CFG_PATH: String = "res://addons/gdframe/plugin.cfg"
const PLUGIN_DIR_NAME: String = "gdframe"
const RELOAD_META_KEY: String = "gdframe_plugin_reloading"

const PAGE_GENERAL: String = "general"
const PAGE_EXT: String = "ext"
const PAGE_CREATE_UI: String = "create_ui"
const PAGE_FSM: String = "fsm"
const PAGE_POOL: String = "pool"
const PAGE_UPDATE: String = "update"

const FSM_STATE_SCRIPT_PATH: String = "res://addons/gdframe/runtime/fsm/fsm_state.gd"
const FSM_REGISTRY_SCRIPT_PATH: String = "res://addons/gdframe/runtime/fsm/fsm_registry_base.gd"

const PoolDebuggerPlugin: Script = preload("res://addons/gdframe/editor/pool_debugger_plugin.gd")
const UpdaterScript: Script = preload("res://addons/gdframe/editor/updater.gd")
const ExtUpdaterScript: Script = preload("res://addons/gdframe/editor/ext_updater.gd")
const ExtManageList: Script = preload("res://addons/gdframe/editor/ext_manage_list.gd")
const VersionSeries: Script = preload("res://addons/gdframe/editor/version_series.gd")
const ExtModuleMeta: Script = preload("res://addons/gdframe/editor/module_meta.gd")
const ExtCreate: Script = preload("res://addons/gdframe/editor/ext_create.gd")
const ExtFacadeGen: Script = preload("res://addons/gdframe/editor/facade_gen.gd")
const ProfileSettingsGen: Script = preload("res://addons/gdframe/editor/profile_settings_gen.gd")
const LocaleScaffold: Script = preload("res://addons/gdframe/editor/locale_scaffold.gd")
const ProfileSettingsMigrate: Script = preload("res://addons/gdframe/editor/profile_settings_migrate.gd")
const SaveFormatConvert: Script = preload("res://addons/gdframe/editor/save_format_convert.gd")
const AssetNameUtil: Script = preload("res://addons/gdframe/editor/asset_name_util.gd")
const ResultGen: Script = preload("res://addons/gdframe/editor/result_gen.gd")
const SignalsGen: Script = preload("res://addons/gdframe/editor/signals_gen.gd")
const UISceneScan: Script = preload("res://addons/gdframe/runtime/ui/ui_scene_scan.gd")
const FsmScan: Script = preload("res://addons/gdframe/runtime/fsm/fsm_scan.gd")

const _SUPPORTED_VERSION_UNAVAILABLE_TEXT: String = "--"

const _POOL_FILTER_DEBOUNCE_SEC: float = 0.15
const _POOL_AUTO_REFRESH_INTERVAL_SEC: float = 0.1
const _EXTERNAL_EDITOR_COLD_START_WAIT_SEC: float = 2.5
const _EXTERNAL_EDITOR_GOTO_RETRY_WAIT_SEC: float = 1.2
const _EXTERNAL_EDITOR_GOTO_MAX_RETRIES: int = 8
const _PROFILE_MIGRATE_MAX_RETRIES: int = 12

# =============================================================================
# State — shared
# =============================================================================

var _updater: RefCounted
var _ext_updater: RefCounted
var _dock: PanelContainer
var _page_map: Dictionary[String, Control] = {}
var _config: GDFrameConfig

# =============================================================================
# State — General page
# =============================================================================

var _toggle_general: Button
var _general_status_label: Label
var _ui_max_layer_spin: SpinBox
var _save_fmt_opt: OptionButton
var _delete_all_saves_dialog: ConfirmationDialog
var _save_format_change_dialog: ConfirmationDialog
var _pending_save_format_index: int = -1
var _save_format_switch_busy: bool = false
var _profile_migrate_retries: int = 0

var _external_editor_project_launched: bool = false
var _external_editor_exec_cache: String = ""
var _external_editor_exec_cache_ready: bool = false
var _external_editor_goto_retries_left: int = 0

# =============================================================================
# State — Extension page
# =============================================================================

var _toggle_ext: Button
var _create_ext_id_edit: LineEdit
var _create_ext_name_edit: LineEdit
var _create_ext_template_opt: OptionButton
var _ext_status_label: Label
var _ext_installed_btn: Button
var _ext_available_btn: Button
var _ext_installed_scroll: ScrollContainer
var _ext_available_scroll: ScrollContainer
var _ext_installed_list: VBoxContainer
var _ext_available_list: VBoxContainer
var _ext_source_option: OptionButton
var _ext_delete_dialog: ConfirmationDialog
var _ext_version_confirm_dialog: ConfirmationDialog
var _pending_delete_ext_dir: String = ""
var _pending_ext_version_option: OptionButton
var _pending_ext_version_index: int = -1
var _ext_index_info: Dictionary = {}
var _ext_infos: Array[Dictionary] = []
var _ext_check_seq: int = 0

# =============================================================================
# State — UI page
# =============================================================================

var _toggle_create_ui: Button
var _create_ui_name_edit: LineEdit
var _create_ui_status_label: Label
var _ui_manage_list: VBoxContainer
var _delete_confirm_dialog: ConfirmationDialog
var _pending_delete_scene_path: String = ""
var _rename_ui_dialog: AcceptDialog
var _rename_ui_target_label: Label
var _rename_ui_name_edit: LineEdit
var _pending_rename_scene_path: String = ""
var _ui_list_dirty: bool = true

# =============================================================================
# State — Update page
# =============================================================================

var _toggle_update: Button
var _source_option: OptionButton
var _source_url_label: Label
var _local_version_label: Label
var _supported_version_option: OptionButton
var _supported_version_unavailable: Label
var _update_btn: Button
var _status_label: Label
var _plugin_index_info: Dictionary = {}
var _supported_select_block: bool = false
var _supported_option_last_index: int = 0
var _remote_check_seq: int = 0

# =============================================================================
# State — FSM page
# =============================================================================

var _toggle_fsm: Button
var _fsm_name_edit: LineEdit
var _fsm_status_label: Label
var _fsm_machine_option: OptionButton
var _fsm_states_rows: VBoxContainer
var _fsm_new_state_edit: LineEdit
var _fsm_delete_machine_btn: Button
var _fsm_delete_machine_dialog: ConfirmationDialog
var _pending_delete_fsm_id: String = ""
var _fsm_delete_state_dialog: ConfirmationDialog
var _pending_delete_state_sid: String = ""
var _pending_delete_state_key: String = ""
var _rename_fsm_machine_dialog: AcceptDialog
var _rename_fsm_machine_target_label: Label
var _rename_fsm_machine_name_edit: LineEdit
var _pending_rename_fsm_id: String = ""
var _rename_fsm_state_dialog: AcceptDialog
var _rename_fsm_state_target_label: Label
var _rename_fsm_state_name_edit: LineEdit
var _pending_rename_state_sid: String = ""
var _pending_rename_state_key: String = ""

# =============================================================================
# State — Pool page
# =============================================================================

var _toggle_pool: Button
var _pool_filter_edit: LineEdit
var _pool_tree: Tree
var _pool_status_label: Label
var _pool_auto_refresh_cb: CheckButton
var _pool_auto_refresh_timer: Timer
var _pool_page_visible: bool = false
var _pool_debug_plugin: EditorDebuggerPlugin
var _pool_last_stats: Dictionary = {}
var _pool_filter_seq: int = 0

# =============================================================================
# State — asset scan cache
# =============================================================================

var _asset_scan_ui_scenes: Array[String] = []
var _asset_scan_fsm_reg_paths: Array[String] = []
var _asset_scan_fsm_states: Dictionary = {}
var _asset_fs_sync_pending: bool = false
var _asset_fs_sync_paths: PackedStringArray = PackedStringArray()
var _asset_fs_sync_refresh_ui: bool = false
var _asset_fs_sync_refresh_ext_root: bool = false

var _dock_row_stripe_boxes: Array = [null, null]

# =============================================================================
# Lifecycle
# =============================================================================

func _enter_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	call_deferred("_ensure_gdframe_autoload")
	call_deferred("_prune_stale_locale_translations")
	call_deferred("_run_initial_contract_scaffold")
	_updater = UpdaterScript.new()
	_ensure_ext_updater()
	_build_dock()
	if Engine.has_meta(RELOAD_META_KEY):
		Engine.remove_meta(RELOAD_META_KEY)
		_set_dock_status("update", "插件已重载")
	_load_local_plugin_index()
	_load_local_ext_index()
	_pool_debug_plugin = PoolDebuggerPlugin.new()
	_pool_debug_plugin.set_stats_handler(Callable(self, "_on_runtime_pool_stats"))
	add_debugger_plugin(_pool_debug_plugin)
	_pool_auto_refresh_timer = Timer.new()
	_pool_auto_refresh_timer.wait_time = _POOL_AUTO_REFRESH_INTERVAL_SEC
	_pool_auto_refresh_timer.autostart = false
	_pool_auto_refresh_timer.timeout.connect(_on_pool_auto_refresh_timeout)
	add_child(_pool_auto_refresh_timer)


func _exit_tree() -> void:
	_reset_locale_import_state()
	_reset_asset_filesystem_sync_state()
	if _pool_debug_plugin != null:
		remove_debugger_plugin(_pool_debug_plugin)
		_pool_debug_plugin = null
	if _pool_auto_refresh_timer != null:
		_pool_auto_refresh_timer.stop()
		if is_instance_valid(_pool_auto_refresh_timer):
			_pool_auto_refresh_timer.queue_free()
		_pool_auto_refresh_timer = null
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	_config = null
	_ext_updater = null
	_external_editor_project_launched = false
	_external_editor_exec_cache_ready = false
	_external_editor_goto_retries_left = 0


# =============================================================================
# Dock — shared
# =============================================================================

const _DOCK_STATUS_DEFAULTS: Dictionary = {
	"general": "就绪",
	"ui": "待创建",
	"ext": "待操作",
	"fsm": "就绪",
	"pool": "尚未收到运行时数据",
	"update": "待检查",
}

func _dock_status_label() -> Label:
	var lbl: Label = Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl

func _format_dock_status_text(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("状态:"):
		return trimmed
	return "状态: %s" % trimmed

func _set_dock_status(slot: String, text: String) -> void:
	var label: Label = null
	match slot:
		"general":
			label = _general_status_label
		"ext":
			label = _ext_status_label
		"ui":
			label = _create_ui_status_label
		"fsm":
			label = _fsm_status_label
		"pool":
			label = _pool_status_label
		"update":
			label = _status_label
	var display: String = text.strip_edges()
	if display.is_empty():
		display = str(_DOCK_STATUS_DEFAULTS.get(slot, ""))
	display = _format_dock_status_text(display)
	if label != null:
		label.text = display
		label.tooltip_text = display

func _dock_row_stripe_stylebox(use_alt: bool) -> StyleBoxFlat:
	var idx: int = 1 if use_alt else 0
	if _dock_row_stripe_boxes[idx] == null:
		var gui: Control = get_editor_interface().get_base_control()
		var c_a: Color = gui.get_theme_color(&"dark_color_1", &"Editor")
		var c_b: Color = gui.get_theme_color(&"dark_color_2", &"Editor")
		var bg: Color = c_b if use_alt else c_a
		if c_a.is_equal_approx(c_b):
			bg = c_a if not use_alt else c_a.darkened(0.1)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(2)
		sb.set_content_margin_all(4)
		_dock_row_stripe_boxes[idx] = sb
	return _dock_row_stripe_boxes[idx] as StyleBoxFlat

func _build_dock_asset_row(
	row_index: int,
	title: String,
	tooltip: String,
	actions: Array,
) -> PanelContainer:
	var stripe: PanelContainer = PanelContainer.new()
	stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stripe.add_theme_stylebox_override(&"panel", _dock_row_stripe_stylebox((row_index % 2) == 1))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	row.add_child(name_label)
	for action: Variant in actions:
		if action is not Dictionary:
			continue
		var act: Dictionary = action as Dictionary
		var btn: Button = Button.new()
		btn.text = String(act.get("text", ""))
		btn.tooltip_text = String(act.get("tip", ""))
		var cb: Callable = act.get("callback", Callable()) as Callable
		if cb.is_valid():
			btn.pressed.connect(cb)
		row.add_child(btn)
	stripe.add_child(row)
	return stripe

func _require_editor_not_playing(status_slot: String, action_label: String) -> bool:
	if _editor_is_playing():
		_set_dock_status(status_slot, "请先停止运行中的游戏再%s" % action_label)
		return false
	return true

func _editor_is_playing() -> bool:
	return get_editor_interface().is_playing_scene()

func _configure_plugin_modal_dialog(dialog: Window) -> void:
	dialog.exclusive = false

func _build_dock() -> void:
	_dock = PanelContainer.new()
	_dock.name = "GDFrame"
	_dock.custom_minimum_size = Vector2(600, 0)

	var root: HBoxContainer = HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_dock.add_child(root)

	var sidebar: VBoxContainer = VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(120, 0)
	sidebar.add_theme_constant_override("separation", 6)
	root.add_child(sidebar)

	var button_group: ButtonGroup = ButtonGroup.new()

	_toggle_general = Button.new()
	_toggle_general.text = "通用"
	_toggle_general.toggle_mode = true
	_toggle_general.button_group = button_group
	_toggle_general.pressed.connect(func() -> void:
		_show_page(PAGE_GENERAL)
	)
	sidebar.add_child(_toggle_general)

	_toggle_create_ui = Button.new()
	_toggle_create_ui.text = "UI管理"
	_toggle_create_ui.toggle_mode = true
	_toggle_create_ui.button_group = button_group
	_toggle_create_ui.pressed.connect(func() -> void:
		_show_page(PAGE_CREATE_UI)
	)
	sidebar.add_child(_toggle_create_ui)

	_toggle_fsm = Button.new()
	_toggle_fsm.text = "状态机"
	_toggle_fsm.toggle_mode = true
	_toggle_fsm.button_group = button_group
	_toggle_fsm.pressed.connect(func() -> void:
		_show_page(PAGE_FSM)
	)
	sidebar.add_child(_toggle_fsm)

	_toggle_pool = Button.new()
	_toggle_pool.text = "对象池"
	_toggle_pool.toggle_mode = true
	_toggle_pool.button_group = button_group
	_toggle_pool.pressed.connect(func() -> void:
		_show_page(PAGE_POOL)
	)
	sidebar.add_child(_toggle_pool)

	_toggle_ext = Button.new()
	_toggle_ext.text = "扩展管理"
	_toggle_ext.toggle_mode = true
	_toggle_ext.button_group = button_group
	_toggle_ext.pressed.connect(func() -> void:
		_show_page(PAGE_EXT)
	)
	sidebar.add_child(_toggle_ext)

	_toggle_update = Button.new()
	_toggle_update.text = "更新"
	_toggle_update.toggle_mode = true
	_toggle_update.button_group = button_group
	_toggle_update.pressed.connect(func() -> void:
		_show_page(PAGE_UPDATE)
	)
	sidebar.add_child(_toggle_update)

	var page_container: VBoxContainer = VBoxContainer.new()
	page_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(page_container)

	_delete_confirm_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_delete_confirm_dialog)
	_delete_confirm_dialog.title = "确认删除 UI"
	_delete_confirm_dialog.dialog_text = "确认删除该 UI 吗？此操作会删除对应脚本和场景文件。"
	_delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_dock.add_child(_delete_confirm_dialog)

	_rename_ui_dialog = AcceptDialog.new()
	_configure_plugin_modal_dialog(_rename_ui_dialog)
	_rename_ui_dialog.title = "重命名 UI"
	_rename_ui_dialog.min_size = Vector2i(420, 120)
	_rename_ui_dialog.confirmed.connect(_on_rename_ui_confirmed)
	_dock.add_child(_rename_ui_dialog)
	var rename_builtin_label: Label = _rename_ui_dialog.get_label()
	if rename_builtin_label != null:
		rename_builtin_label.hide()
	var rename_box: VBoxContainer = VBoxContainer.new()
	rename_box.add_theme_constant_override("separation", 10)
	rename_box.custom_minimum_size = Vector2(380, 0)
	_rename_ui_dialog.add_child(rename_box)
	_rename_ui_target_label = Label.new()
	_rename_ui_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_box.add_child(_rename_ui_target_label)
	_rename_ui_name_edit = LineEdit.new()
	_rename_ui_name_edit.placeholder_text = "main → ui_main"
	_rename_ui_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_box.add_child(_rename_ui_name_edit)

	_delete_all_saves_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_delete_all_saves_dialog)
	_delete_all_saves_dialog.title = "确认删除所有存档"
	_delete_all_saves_dialog.dialog_text = (
		"将永久删除 user://gdframe 下的全部内容（profile 与 slots）。\n此操作不可撤销，是否继续？"
	)
	_delete_all_saves_dialog.confirmed.connect(_on_delete_all_saves_confirmed)
	_dock.add_child(_delete_all_saves_dialog)

	_save_format_change_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_save_format_change_dialog)
	_save_format_change_dialog.title = "切换存档格式"
	_save_format_change_dialog.dialog_text = (
		"切换存档格式将把 user://gdframe 下的现有存档转换为新格式（profile 与 slots）。\n"
		+ "是否继续？"
	)
	_save_format_change_dialog.confirmed.connect(_on_save_format_change_confirmed)
	_save_format_change_dialog.canceled.connect(_on_save_format_change_canceled)
	_dock.add_child(_save_format_change_dialog)

	_ext_delete_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_ext_delete_dialog)
	_ext_delete_dialog.title = "确认删除扩展"
	_ext_delete_dialog.dialog_text = "确认删除该扩展模块吗？将删除整个目录。"
	_ext_delete_dialog.confirmed.connect(_on_ext_delete_confirmed)
	_dock.add_child(_ext_delete_dialog)

	_ext_version_confirm_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_ext_version_confirm_dialog)
	_ext_version_confirm_dialog.title = "确认扩展版本"
	_ext_version_confirm_dialog.confirmed.connect(_on_ext_version_confirm_confirmed)
	_ext_version_confirm_dialog.canceled.connect(_on_ext_version_confirm_canceled)
	_dock.add_child(_ext_version_confirm_dialog)

	var general_page: Variant = _build_general_page()
	page_container.add_child(general_page)
	_page_map[PAGE_GENERAL] = general_page

	var ext_page: Variant = _build_ext_page()
	page_container.add_child(ext_page)
	_page_map[PAGE_EXT] = ext_page

	var create_page: Variant = _build_create_ui_page()
	page_container.add_child(create_page)
	_page_map[PAGE_CREATE_UI] = create_page

	var fsm_page: Variant = _build_fsm_page()
	page_container.add_child(fsm_page)
	_page_map[PAGE_FSM] = fsm_page

	var update_page: Variant = _build_update_page()
	page_container.add_child(update_page)
	_page_map[PAGE_UPDATE] = update_page

	var pool_page: Variant = _build_pool_page()
	page_container.add_child(pool_page)
	_page_map[PAGE_POOL] = pool_page

	_toggle_general.button_pressed = true
	_show_page(PAGE_GENERAL)

	add_control_to_bottom_panel(_dock, "GDFrame")

func _show_page(page_name: String) -> void:
	for key in _page_map.keys():
		var page: Control = _page_map.get(key) as Control
		if page != null:
			page.visible = (key == page_name)
	_pool_page_visible = page_name == PAGE_POOL
	_sync_pool_auto_refresh_timer()
	if page_name == PAGE_CREATE_UI and _ui_list_dirty:
		call_deferred("_refresh_ui_manage_list")
	if page_name == PAGE_EXT:
		call_deferred("_refresh_ext_on_page_show")
	if page_name == PAGE_FSM:
		call_deferred("_refresh_fsm_ui")

# =============================================================================
# Config
# =============================================================================

## 从 [code]config.tres[/code] 同步到插件缓存：优先用检查器里正在编辑的实例（含未保存修改），否则从磁盘重载。
func _reload_config_from_tres() -> void:
	var path: String = GDFrameConfig.PATH
	var edited: Object = get_editor_interface().get_inspector().get_edited_object()
	if edited is GDFrameConfig:
		var cfg: GDFrameConfig = edited as GDFrameConfig
		if cfg.resource_path == path:
			_config = cfg
			return
	if ResourceLoader.exists(path):
		var loaded: Resource = ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_REPLACE
		)
		if loaded is GDFrameConfig:
			_config = loaded as GDFrameConfig
			return

func _sync_general_page_from_config() -> void:
	if _config == null:
		return
	if _ui_max_layer_spin != null:
		_ui_max_layer_spin.set_value_no_signal(float(_config.ui_max_layer))
	if _save_fmt_opt != null:
		_save_fmt_opt.select(
			1 if _config.save_file_format == GDFrameConfig.SaveFileFormat.BINARY else 0
		)

func _save_config(ok_message: String) -> void:
	var err: Error = ResourceSaver.save(_config, GDFrameConfig.PATH)
	if err != OK:
		_set_dock_status("general", "保存失败（错误 %s）。" % err)
		return
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null:
		fs.update_file(GDFrameConfig.PATH)
	_set_dock_status("general", ok_message)


## 通用页 ui_max_layer 变更：写入 config.tres。
func _on_ui_max_layer_changed(max_layer: int) -> void:
	_config.ui_max_layer = clampi(max_layer, 0, 63)
	_save_config(
		"已写入 %s（层 0～层 %d）。" % [GDFrameConfig.PATH.get_file(), _config.ui_max_layer],
	)
	_refresh_ui_manage_list()

func _on_save_format_option_changed(index: int) -> void:
	var current_index: int = (
		1 if _config.save_file_format == GDFrameConfig.SaveFileFormat.BINARY else 0
	)
	if index == current_index:
		return
	if _save_format_switch_busy:
		_set_save_format_option_index(current_index)
		_set_dock_status("general", "存档格式转换进行中，请稍候。")
		return
	if _editor_is_playing():
		_set_save_format_option_index(current_index)
		_set_dock_status("general", "请先停止运行中的游戏，再切换存档格式。")
		return
	_pending_save_format_index = index
	_set_save_format_option_index(current_index)
	_save_format_change_dialog.popup_centered(Vector2i(520, 180))


func _set_save_format_option_index(index: int) -> void:
	if _save_fmt_opt == null:
		return
	_save_fmt_opt.set_block_signals(true)
	_save_fmt_opt.select(index)
	_save_fmt_opt.set_block_signals(false)


func _on_save_format_change_canceled() -> void:
	_pending_save_format_index = -1


func _on_save_format_change_confirmed() -> void:
	var new_index: int = _pending_save_format_index
	_pending_save_format_index = -1
	if new_index < 0:
		return
	if _save_format_switch_busy:
		return
	if _editor_is_playing():
		_set_dock_status("general", "请先停止运行中的游戏，再切换存档格式。")
		return
	_save_format_switch_busy = true
	_save_fmt_opt.disabled = true
	var target_ext: String = ".res" if new_index == 1 else ".tres"
	var conv: Dictionary = SaveFormatConvert.convert_user_saves_format(target_ext)
	_save_format_switch_busy = false
	_save_fmt_opt.disabled = false
	if not bool(conv.get("ok", false)):
		_set_dock_status("general", str(conv.get("message", "转换失败。")))
		return
	_config.save_file_format = (
		GDFrameConfig.SaveFileFormat.BINARY
		if new_index == 1
		else GDFrameConfig.SaveFileFormat.TEXT
	)
	var conv_msg: String = str(conv.get("message", "已切换存档格式。"))
	_save_config(conv_msg)
	_set_save_format_option_index(new_index)

func _on_general_refresh_config_pressed() -> void:
	_reload_config_from_tres()
	_sync_general_page_from_config()
	_set_dock_status("general","已从 config.tres 同步到本页。")


func _on_ui_locate_dim_scene() -> void:
	_set_dock_status("ui", "")
	var path: String = GDFrameConfig.DIM_SCENE_PATH
	if not FileAccess.file_exists(path):
		_set_dock_status("ui", "状态: 未找到场景 %s" % path.get_file())
		return
	var ei: EditorInterface = get_editor_interface()
	ei.get_file_system_dock().navigate_to_path(path)
	ei.select_file(path)
	_set_dock_status("ui", "状态: 已在文件系统中定位 %s" % path.get_file())


func _on_ui_open_dim_script() -> void:
	_set_dock_status("ui", "")
	var path: String = GDFrameConfig.DIM_SCRIPT_PATH
	if not FileAccess.file_exists(path):
		_set_dock_status("ui", "状态: 未找到或无法打开 %s" % path.get_file())
		return
	if _open_script_in_editor(path):
		_set_dock_status("ui", "状态: 已打开 %s" % path.get_file())
	else:
		_set_dock_status("ui", "状态: 未找到或无法打开 %s" % path.get_file())


func _on_ui_open_dim_scene() -> void:
	_set_dock_status("ui", "")
	var path: String = GDFrameConfig.DIM_SCENE_PATH
	if not FileAccess.file_exists(path):
		_set_dock_status("ui", "状态: 未找到场景 %s" % path.get_file())
		return
	get_editor_interface().open_scene_from_path(path)
	_set_dock_status("ui", "状态: 已在场景编辑器中打开 %s" % path.get_file())


func _call_editor_gen(gen: Script, method: StringName, label: String) -> Variant:
	if gen == null:
		push_error("GDFrame: %s 未加载。" % label)
		return null
	if not gen.has_method(method):
		push_error("GDFrame: %s 缺少 %s（请查看 Output 中的编译错误）。" % [label, method])
		return null
	return gen.call(method)


func _append_dock_status_line(status: String, line: String) -> String:
	var msg: String = line.strip_edges()
	if msg.is_empty():
		return status
	if status.is_empty():
		return msg
	return status + " " + msg


func _run_ext_facade_generate() -> Dictionary:
	var raw: Variant = _call_editor_gen(ExtFacadeGen, &"generate_all", "facade_gen.gd")
	if raw is Dictionary:
		return raw
	return {"ok": false, "changed": false, "message": "facade_gen.gd 生成失败。", "content": ""}


func _apply_ext_facade_generate_result(result: Dictionary) -> void:
	var profile_result: Dictionary = _sync_profile_settings_fields()
	_apply_profile_settings_generate_writes(profile_result)
	var result_registry: Dictionary = _sync_result_constants()
	_apply_result_generate_writes(result_registry)
	var signals_result: Dictionary = _sync_signals_script()
	_apply_signals_generate_writes(signals_result)
	var status: String = ""
	if bool(profile_result.get("ok", false)):
		if (
			bool(profile_result.get("changed_data", false))
			or bool(profile_result.get("changed_defaults", false))
		):
			status = _append_dock_status_line(status, str(profile_result.get("message", "")))
	else:
		status = _append_dock_status_line(
			status,
			str(profile_result.get("message", "profile 同步失败。")),
		)
	if bool(result_registry.get("ok", false)):
		if bool(result_registry.get("changed", false)):
			status = _append_dock_status_line(status, str(result_registry.get("message", "")))
	else:
		status = _append_dock_status_line(
			status,
			str(result_registry.get("message", "GDFrameResult 同步失败。")),
		)
	if bool(signals_result.get("ok", false)):
		if bool(signals_result.get("changed", false)):
			status = _append_dock_status_line(status, str(signals_result.get("message", "")))
	else:
		status = _append_dock_status_line(
			status,
			str(signals_result.get("message", "信号脚本同步失败。")),
		)
	if not bool(result.get("ok", false)):
		var err_msg: String = str(result.get("message", "生成失败。"))
		status = _append_dock_status_line(status, err_msg)
		_set_dock_status("general", status)
		return
	var content: String = str(result.get("content", ""))
	if bool(result.get("changed", false)):
		_ensure_ext_scaffold()
		if _write_res_text(GDFrameConfig.EXT_FACADE_MODULES_PATH, content) != OK:
			_set_dock_status("general", "状态: 写入 generated/facade_modules.gd 失败。")
			return
		_update_editor_filesystem(GDFrameConfig.EXT_FACADE_MODULES_PATH)
	var facade_msg: String = str(result.get("message", ""))
	status = _append_dock_status_line(status, facade_msg)
	_set_dock_status("general", status)


func _sync_profile_settings_fields() -> Dictionary:
	_ensure_generated_dir()
	if not _res_file_exists(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH):
		_ensure_profile_settings_script()
	return _call_profile_settings_generate()


func _call_profile_settings_generate() -> Dictionary:
	var raw: Variant = _call_editor_gen(
		ProfileSettingsGen,
		&"generate_all",
		"profile_settings_gen.gd",
	)
	if raw is Dictionary:
		return raw
	return {
		"ok": false,
		"changed_data": false,
		"changed_defaults": false,
		"message": "profile_settings_gen.gd 生成失败。",
		"data_content": "",
		"defaults_content": "",
	}


func _sync_result_constants() -> Dictionary:
	_ensure_generated_dir()
	var raw: Variant = _call_editor_gen(ResultGen, &"generate_all", "result_gen.gd")
	if raw is Dictionary:
		return raw
	return {"ok": false, "changed": false, "message": "result_gen.gd 生成失败。", "content": ""}


func _apply_generated_script_write(
	result: Dictionary,
	res_path: String,
	label: String,
	sync_filesystem: bool = true,
) -> void:
	if not bool(result.get("ok", false)):
		push_warning("GDFrame %s: %s" % [label, str(result.get("message", "同步失败。"))])
		return
	if not bool(result.get("changed", false)):
		return
	if _write_res_text(res_path, str(result.get("content", ""))) != OK:
		push_error("GDFrame: 无法写入 %s" % res_path)
		return
	if sync_filesystem:
		_update_editor_filesystem(res_path)


func _apply_result_generate_writes(result: Dictionary, sync_filesystem: bool = true) -> void:
	_apply_generated_script_write(
		result,
		GDFrameConfig.RESULT_SCRIPT_PATH,
		"result",
		sync_filesystem,
	)


func _sync_signals_script(ensure_sync_fs: bool = true) -> Dictionary:
	if not _res_file_exists(GDFrameConfig.SIGNALS_SCRIPT_PATH):
		_ensure_signals_script(ensure_sync_fs)
	var raw: Variant = _call_editor_gen(SignalsGen, &"generate_all", "signals_gen.gd")
	if raw is Dictionary:
		return raw
	return {"ok": false, "changed": false, "message": "signals_gen.gd 生成失败。", "content": ""}


func _apply_signals_generate_writes(result: Dictionary, sync_filesystem: bool = true) -> void:
	_apply_generated_script_write(
		result,
		GDFrameConfig.SIGNALS_SCRIPT_PATH,
		"signals",
		sync_filesystem,
	)


func _apply_profile_settings_generate_writes(result: Dictionary, sync_filesystem: bool = true) -> void:
	if not bool(result.get("ok", false)):
		push_warning(
			"GDFrame profile: %s" % str(result.get("message", "同步失败。"))
		)
		return
	if bool(result.get("changed_data", false)):
		var data_content: String = str(result.get("data_content", ""))
		if data_content.is_empty():
			return
		if _write_res_text(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH, data_content) != OK:
			push_error("GDFrame: 无法写入 %s" % GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH)
			return
		if sync_filesystem:
			_update_editor_filesystem(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH)
	if bool(result.get("changed_defaults", false)):
		var defaults_content: String = str(result.get("defaults_content", ""))
		if defaults_content.is_empty():
			return
		if _write_res_text(GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH, defaults_content) != OK:
			push_error("GDFrame: 无法写入 %s" % GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH)
			return
		if sync_filesystem:
			_update_editor_filesystem(GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH)
	if bool(result.get("changed_data", false)) or bool(result.get("changed_defaults", false)):
		_profile_migrate_retries = 0
		call_deferred("_deferred_migrate_user_profile_on_disk")


func _deferred_migrate_user_profile_on_disk() -> void:
	if not ProfileSettingsMigrate.settings_script_ready():
		_profile_migrate_retries += 1
		if _profile_migrate_retries <= _PROFILE_MIGRATE_MAX_RETRIES:
			call_deferred("_deferred_migrate_user_profile_on_disk")
			return
		_profile_migrate_retries = 0
		return
	_profile_migrate_retries = 0
	var migrate: Dictionary = ProfileSettingsMigrate.migrate_user_profile_on_disk()
	if not bool(migrate.get("ok", false)):
		push_warning("GDFrame profile: %s" % str(migrate.get("message", "磁盘 profile 迁移失败。")))

# =============================================================================
# Asset scan cache
# =============================================================================

func _invalidate_asset_scan_cache() -> void:
	_asset_scan_ui_scenes.clear()
	_asset_scan_fsm_reg_paths.clear()
	_asset_scan_fsm_states.clear()

func _get_ui_scene_paths() -> Array[String]:
	if _asset_scan_ui_scenes.is_empty():
		_asset_scan_ui_scenes = UISceneScan.collect_ui_scene_paths(GDFrameConfig.UI_ROOT_DIR)
		_asset_scan_ui_scenes.sort()
	return _asset_scan_ui_scenes

func _get_fsm_registry_paths() -> Array[String]:
	if _asset_scan_fsm_reg_paths.is_empty():
		_asset_scan_fsm_reg_paths = FsmScan.collect_fsm_registry_paths(GDFrameConfig.FSM_ROOT)
	return _asset_scan_fsm_reg_paths

func _get_fsm_state_keys(fsm_id: String) -> Array[String]:
	if not _asset_scan_fsm_states.has(fsm_id):
		_asset_scan_fsm_states[fsm_id] = _collect_fsm_state_keys(fsm_id)
	return _asset_scan_fsm_states[fsm_id] as Array[String]

func _after_asset_tree_change(
	refresh_ui_list: bool = false,
	refresh_fsm: bool = false,
	refresh_fsm_states_only: bool = false,
	changed_paths: PackedStringArray = PackedStringArray(),
	refresh_ext_list: bool = false,
) -> void:
	_invalidate_asset_scan_cache()
	var sync_paths: PackedStringArray = changed_paths.duplicate()
	if refresh_ui_list or refresh_fsm or refresh_fsm_states_only:
		if _regenerate_constants_registry(false):
			if GDFrameConfig.CONSTANTS_SCRIPT_PATH not in sync_paths:
				sync_paths.append(GDFrameConfig.CONSTANTS_SCRIPT_PATH)
	if not sync_paths.is_empty():
		_sync_filesystem_after_asset_writes(sync_paths)
	if refresh_ext_list:
		_scan_project_filesystem()
	if refresh_ui_list:
		_ui_list_dirty = true
		if changed_paths.is_empty():
			_refresh_ui_manage_list(_get_ui_scene_paths())
		else:
			_asset_fs_sync_refresh_ui = true
	if refresh_fsm:
		_refresh_fsm_ui()
	elif refresh_fsm_states_only:
		_fsm_refresh_states_list()
	if refresh_ext_list:
		_refresh_ext_manage_list()

# =============================================================================
# Filesystem helpers
# =============================================================================

func _update_editor_filesystem(res_path: String) -> void:
	if res_path.is_empty():
		return
	# 新建资源时 update_file 不足以让文件系统 Dock 显示；与资产写入共用 scan 批处理。
	_sync_filesystem_after_asset_writes(PackedStringArray([res_path]))

func _ensure_res_dir(res_dir: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(res_dir))

func _res_dir_exists(res_dir: String) -> bool:
	if res_dir.is_empty():
		return false
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(res_dir))

func _res_file_exists(res_path: String) -> bool:
	return FileAccess.file_exists(res_path)

func _read_res_text(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		return ""
	return FileAccess.get_file_as_string(res_path)

func _write_res_text(res_path: String, text: String) -> Error:
	var dir_path: String = res_path.get_base_dir()
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dir_path)
	)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_error("GDFrame: 无法创建目录 %s（错误 %s）" % [dir_path, dir_err])
		return dir_err
	var f: FileAccess = FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		var open_err: Error = FileAccess.get_open_error()
		push_error("GDFrame: 无法打开 %s（错误 %s）" % [res_path, open_err])
		return open_err
	f.store_string(text)
	f = null
	return OK

func _scan_project_filesystem() -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null:
		fs.scan()


func _reset_asset_filesystem_sync_state() -> void:
	_asset_fs_sync_pending = false
	_asset_fs_sync_paths = PackedStringArray()
	_asset_fs_sync_refresh_ui = false
	_asset_fs_sync_refresh_ext_root = false


func _sync_filesystem_after_asset_writes(changed_paths: PackedStringArray) -> void:
	if changed_paths.is_empty():
		return
	for res_path: String in changed_paths:
		if res_path not in _asset_fs_sync_paths:
			_asset_fs_sync_paths.append(res_path)
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	# 新建/改写资源后一律 scan：父目录已在索引内时 update_file 不足以让 Dock 显示新文件。
	if fs.is_scanning():
		if not _asset_fs_sync_pending:
			_asset_fs_sync_pending = true
			fs.filesystem_changed.connect(_on_asset_filesystem_scan_done, CONNECT_ONE_SHOT)
		return
	_asset_fs_sync_pending = true
	fs.filesystem_changed.connect(_on_asset_filesystem_scan_done, CONNECT_ONE_SHOT)
	fs.scan()


func _on_asset_filesystem_scan_done() -> void:
	_asset_fs_sync_pending = false
	var paths: PackedStringArray = _asset_fs_sync_paths.duplicate()
	var refresh_ui: bool = _asset_fs_sync_refresh_ui
	var refresh_ext_root: bool = _asset_fs_sync_refresh_ext_root
	_asset_fs_sync_paths = PackedStringArray()
	_asset_fs_sync_refresh_ui = false
	_asset_fs_sync_refresh_ext_root = false
	_finish_asset_filesystem_sync(paths)
	if refresh_ui:
		_refresh_ui_manage_list(_get_ui_scene_paths())
	if refresh_ext_root:
		_refresh_ext_root_in_filesystem()


func _finish_asset_filesystem_sync(paths: PackedStringArray) -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	var updated_dirs: Dictionary = {}
	for res_path: String in paths:
		if res_path.is_empty():
			continue
		var is_file: bool = _res_file_exists(res_path)
		if is_file or _res_dir_exists(res_path):
			fs.update_file(res_path)
		var walk_dir: String = res_path.get_base_dir() if is_file else res_path
		while walk_dir.begins_with("res://") and walk_dir.length() > 6:
			if not updated_dirs.has(walk_dir) and _res_dir_exists(walk_dir):
				updated_dirs[walk_dir] = true
				fs.update_file(walk_dir)
			var slash_at: int = walk_dir.rfind("/")
			if slash_at <= 0:
				break
			walk_dir = walk_dir.substr(0, slash_at)

func _safe_delete(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parent_dir: String = path.get_base_dir()
	var file_name: String = path.get_file()
	var dir: DirAccess = DirAccess.open(parent_dir)
	if dir == null:
		return false
	return dir.remove(file_name) == OK

func _try_remove_empty_dir(dir_path: String, root_guard: String = "") -> void:
	if not root_guard.is_empty() and dir_path == root_guard:
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	if dir.get_directories().is_empty() and dir.get_files().is_empty():
		var parent: DirAccess = DirAccess.open(dir_path.get_base_dir())
		if parent != null:
			parent.remove(dir_path.get_file())

# =============================================================================
# General page
# =============================================================================

func _general_form_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size.x = 72
	return lbl

func _general_tool_button(text: String, tip: String, method: StringName) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(Callable(self, method))
	return btn

func _build_general_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row_tools: HBoxContainer = HBoxContainer.new()
	row_tools.add_theme_constant_override("separation", 6)
	row_tools.add_child(_general_tool_button(
		"从外部编辑器打开工程",
		"依赖「编辑器设置 → 文本编辑器 → 外部」可执行路径，以工程根目录启动（VS Code / Cursor 等）。",
		&"_on_open_external_editor_project_folder",
	))
	panel.add_child(row_tools)

	var row_cfg_fields: HBoxContainer = HBoxContainer.new()
	row_cfg_fields.add_theme_constant_override("separation", 8)
	row_cfg_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(row_cfg_fields)

	row_cfg_fields.add_child(_general_form_label("UI 最大层"))
	_ui_max_layer_spin = SpinBox.new()
	_ui_max_layer_spin.prefix = "层 "
	_ui_max_layer_spin.min_value = 0.0
	_ui_max_layer_spin.max_value = 63.0
	_ui_max_layer_spin.step = 1.0
	_ui_max_layer_spin.rounded = true
	_ui_max_layer_spin.custom_minimum_size = Vector2(120, 0)
	_ui_max_layer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_max_layer_spin.size_flags_stretch_ratio = 0.45
	var max_layer_line: LineEdit = _ui_max_layer_spin.get_line_edit()
	max_layer_line.custom_minimum_size.x = 96
	max_layer_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_max_layer_spin.tooltip_text = "写入 config.tres 的 ui_max_layer，与检查器 UI 分组同项。"
	_ui_max_layer_spin.value_changed.connect(
		func(value: float) -> void:
			_on_ui_max_layer_changed(int(value))
	)
	row_cfg_fields.add_child(_ui_max_layer_spin)

	row_cfg_fields.add_child(_general_form_label("存档格式"))
	_save_fmt_opt = OptionButton.new()
	_save_fmt_opt.add_item(".tres 文本", 0)
	_save_fmt_opt.add_item(".res 二进制", 1)
	_save_fmt_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_fmt_opt.size_flags_stretch_ratio = 0.55
	_save_fmt_opt.tooltip_text = (
		"与 %s 中 save_file_format 一致；profile 与 slots 共用。切换时将现有存档转换为新格式。"
		% GDFrameConfig.PATH
	)
	_save_fmt_opt.item_selected.connect(_on_save_format_option_changed)
	row_cfg_fields.add_child(_save_fmt_opt)

	row_cfg_fields.add_child(_general_tool_button(
		"从文件同步配置",
		"将 %s 的最新内容同步到本页；若检查器正在编辑该资源，会包含未保存的修改。" % GDFrameConfig.PATH,
		&"_on_general_refresh_config_pressed",
	))

	var row_cfg: HBoxContainer = HBoxContainer.new()
	row_cfg.add_theme_constant_override("separation", 6)
	row_cfg.add_child(_general_tool_button(
		"定位配置文件",
		"在文件系统 Dock 定位并在检查器中打开：%s。" % GDFrameConfig.PATH,
		&"_on_general_locate_gdframe_config_in_filesystem",
	))
	row_cfg.add_child(_general_tool_button(
		"打开信号脚本",
		"定位并在编辑器中打开 %s；若启用外部编辑器且尚未打开工程，会先打开工程目录。"
			% GDFrameConfig.SIGNALS_SCRIPT_PATH,
		&"_on_general_locate_signals_script",
	))
	panel.add_child(row_cfg)

	var row_locale: HBoxContainer = HBoxContainer.new()
	row_locale.add_theme_constant_override("separation", 6)
	row_locale.add_child(_general_tool_button(
		"初始化本地化 CSV",
		"若无 %s 则生成（含 LOCALE_NAME、设置/ui_tip/核心 ERR_SAVE_* 等框架内置键）；若已存在则补全缺失的内置键，并注册 project.godot 翻译资源。"
			% LocaleScaffold.LOCALE_CSV_PATH,
		&"_on_general_init_locale_pressed",
	))
	row_locale.add_child(_general_tool_button(
		"定位本地化 CSV",
		"在文件系统 Dock 中选中 %s。" % LocaleScaffold.LOCALE_CSV_PATH,
		&"_on_general_locate_locale_csv_pressed",
	))
	panel.add_child(row_locale)

	var row_saves: HBoxContainer = HBoxContainer.new()
	row_saves.add_theme_constant_override("separation", 6)
	row_saves.add_child(_general_tool_button(
		"打开存档路径",
		"在文件管理器中打开 %s（含 profile 与 slots）；不存在则先创建。" % GDFrameSaveManager.USER_ROOT_URL,
		&"_on_open_save_directory_pressed",
	))
	row_saves.add_child(_general_tool_button(
		"清空存档",
		"删除 %s 下全部存档（不可撤销）。" % GDFrameSaveManager.USER_ROOT_URL,
		&"_on_delete_all_saves_pressed",
	))
	panel.add_child(row_saves)

	_general_status_label = _dock_status_label()
	panel.add_child(_general_status_label)
	_set_dock_status("general", "")

	_reload_config_from_tres()
	_sync_general_page_from_config()

	return panel

func _save_user_global_path() -> String:
	return ProjectSettings.globalize_path(GDFrameSaveManager.USER_ROOT_URL).rstrip("/\\")

func _on_open_save_directory_pressed() -> void:
	_set_dock_status("general","")
	var abs_path: Variant = _save_user_global_path()
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and not DirAccess.dir_exists_absolute(abs_path):
		_set_dock_status("general","无法创建存档目录（错误 %s）。" % err)
		return
	var shell_err: int = OS.shell_show_in_file_manager(abs_path)
	if shell_err != OK:
		_set_dock_status("general","无法在文件管理器中打开目录（错误 %s）。" % shell_err)
		return
	_set_dock_status("general","已在文件管理器中打开：%s" % abs_path)

func _on_delete_all_saves_pressed() -> void:
	_set_dock_status("general","")
	if _editor_is_playing():
		_set_dock_status("general","请先停止运行中的游戏，再删除存档。")
		return
	_delete_all_saves_dialog.popup_centered(Vector2i(480, 160))

func _on_delete_all_saves_confirmed() -> void:
	if _editor_is_playing():
		_set_dock_status("general","请先停止运行中的游戏，再删除存档。")
		return
	var err: Error = _delete_user_save_data()
	if err != OK:
		_set_dock_status("general","删除失败（错误 %s）。" % err)
		return
	_set_dock_status("general","已删除所有存档：%s" % GDFrameSaveManager.USER_ROOT_URL)


func _delete_user_save_data() -> Error:
	var abs_path: Variant = _save_user_global_path()
	if not DirAccess.dir_exists_absolute(abs_path):
		return OK
	return _remove_dir_recursive(abs_path)

func _remove_dir_recursive(abs_path: String) -> Error:
	if _purge_abs_dir(abs_path):
		return OK
	return FAILED


func _purge_abs_dir(abs_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(abs_path):
		return true
	var dir: DirAccess = DirAccess.open(abs_path)
	if dir == null:
		return false
	for sub: String in dir.get_directories():
		if not _purge_abs_dir(abs_path.path_join(sub)):
			return false
	for fname: String in dir.get_files():
		if DirAccess.remove_absolute(abs_path.path_join(fname)) != OK:
			return false
	return DirAccess.remove_absolute(abs_path) == OK

func _on_general_locate_signals_script() -> void:
	_set_dock_status("general","")
	if not FileAccess.file_exists(GDFrameConfig.SIGNALS_SCRIPT_PATH):
		_set_dock_status("general","未找到：%s" % GDFrameConfig.SIGNALS_SCRIPT_PATH)
		return
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null:
		fs.update_file(GDFrameConfig.SIGNALS_SCRIPT_PATH)
	if not _navigate_script_in_filesystem(GDFrameConfig.SIGNALS_SCRIPT_PATH):
		_set_dock_status("general","无法在文件系统中定位 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())
		return
	if _external_editor_enabled():
		if not _external_editor_project_launched:
			# 冷启动：优先一次传入「工程目录 + goto」，与 VS Code/Cursor 推荐用法一致。
			if _open_script_in_external_editor(GDFrameConfig.SIGNALS_SCRIPT_PATH, 1, 1, false):
				_external_editor_project_launched = true
				_set_dock_status("general","已在外部编辑器打开 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())
				return
			# 回退：先只开工程，待 Cursor 就绪后多次用「工程 + goto」重试（仅 --goto 冷启动易丢）。
			if not _launch_external_editor_project():
				return
			_begin_external_editor_open_signals_retry()
			return
		if _try_open_signals_in_running_external_editor():
			return
	_finish_open_signals_script()

func _on_general_locate_gdframe_config_in_filesystem() -> void:
	_set_dock_status("general","")
	var path: String = GDFrameConfig.PATH
	if not FileAccess.file_exists(path):
		_set_dock_status("general","未找到：%s" % path)
		return
	var ei: EditorInterface = get_editor_interface()
	ei.get_file_system_dock().navigate_to_path(path)
	ei.select_file(path)
	var cfg: GDFrameConfig = load(path) as GDFrameConfig
	if cfg != null:
		ei.edit_resource(cfg)
	_set_dock_status("general","已在文件系统中定位，并在检查器中打开。")

func _on_open_external_editor_project_folder() -> void:
	_set_dock_status("general","")
	if _launch_external_editor_project():
		_set_dock_status("general","已请求打开: %s" % _project_root_global_path())

func _on_reload_gdframe_plugin_pressed() -> void:
	if _editor_is_playing():
		_set_dock_status("update", "请先停止运行中的游戏，再重载插件。")
		return
	_reload_gdframe_plugin()

func _reload_gdframe_plugin(delay_sec: float = 0.75) -> void:
	var ei: EditorInterface = get_editor_interface()
	if not ei.is_plugin_enabled(PLUGIN_DIR_NAME):
		return
	Engine.set_meta(RELOAD_META_KEY, true)
	var tree: SceneTree = ei.get_base_control().get_tree()
	if tree == null:
		return
	# 定时器挂在 SceneTree 上；回调仅捕获 ei，勿捕获 self（插件卸载后 EditorPlugin 会释放）。
	var timer: SceneTreeTimer = tree.create_timer(maxf(delay_sec, 0.05))
	timer.timeout.connect(
		func() -> void:
			if is_instance_valid(ei) and not ei.is_plugin_enabled(PLUGIN_DIR_NAME):
				ei.call_deferred("set_plugin_enabled", PLUGIN_CFG_PATH, true),
		CONNECT_ONE_SHOT,
	)
	ei.call_deferred("set_plugin_enabled", PLUGIN_CFG_PATH, false)


func _ensure_gdframe_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % GDFrameConfig.AUTOLOAD_NAME):
		add_autoload_singleton(String(GDFrameConfig.AUTOLOAD_NAME), AUTOLOAD_PATH)


func _prune_stale_locale_translations() -> void:
	var scaffold: RefCounted = LocaleScaffold.new()
	scaffold.prune_stale_translations()
	if not scaffold.has_missing_translation_files():
		scaffold.register_translations()


# --- Locale init (Dock「初始化本地化 CSV」) ----------------------------------------

var _locale_prepare_result: Dictionary = {}
var _locale_scaffold: RefCounted = null
var _locale_show_done_status: bool = false
var _locale_import_scheduled: bool = false
var _locale_import_busy: bool = false
var _locale_scan_pending: bool = false
var _locale_import_attempts: int = 0


func _on_general_init_locale_pressed() -> void:
	_locale_show_done_status = true
	_locale_scaffold = LocaleScaffold.new()
	_locale_prepare_result = _locale_scaffold.prepare_csv(true)
	if not bool(_locale_prepare_result.get("ok", true)):
		_set_dock_status(
			"general",
			str(_locale_prepare_result.get("message", "本地化初始化失败。")),
		)
		_reset_locale_import_state()
		return
	_set_dock_status("general", "正在初始化本地化…")
	_defer_locale_import()


func _on_general_locate_locale_csv_pressed() -> void:
	var path: String = LocaleScaffold.LOCALE_CSV_PATH
	if not FileAccess.file_exists(path):
		_set_dock_status("general", "未找到：%s（可点「初始化本地化 CSV」生成）。" % path)
		return
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
	get_editor_interface().select_file(path)
	_set_dock_status("general", "已在文件系统中定位 %s" % path.get_file())


func _defer_locale_import() -> void:
	if _locale_import_scheduled:
		return
	var tree: SceneTree = get_editor_interface().get_base_control().get_tree()
	if tree == null:
		return
	_locale_import_scheduled = true
	tree.process_frame.connect(_on_locale_import_frame, CONNECT_ONE_SHOT)


func _on_locale_import_frame() -> void:
	_locale_import_scheduled = false
	_run_locale_import()


func _run_locale_import() -> void:
	if _locale_import_busy:
		return
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	if fs.is_scanning():
		_locale_import_attempts += 1
		if _locale_import_attempts < 60:
			_defer_locale_import()
		return

	var csv_path: String = LocaleScaffold.LOCALE_CSV_PATH
	if not FileAccess.file_exists(csv_path):
		_reset_locale_import_state()
		return

	var scaffold: RefCounted = _locale_scaffold if _locale_scaffold != null else LocaleScaffold.new()

	if fs.get_filesystem_path(LocaleScaffold.LOCALE_ROOT_DIR) == null:
		if not _locale_scan_pending:
			_locale_scan_pending = true
			fs.filesystem_changed.connect(_on_locale_scan_done, CONNECT_ONE_SHOT)
			fs.scan()
		return

	_locale_scan_pending = false
	if scaffold.has_missing_translation_files():
		_locale_import_busy = true
		fs.reimport_files(PackedStringArray([csv_path]))
		_locale_import_busy = false

	var translations_ok: bool = (
		scaffold.register_translations() or scaffold.translations_registered()
	)
	if _locale_show_done_status:
		_set_dock_status("general", _locale_done_message(translations_ok))
	fs.update_file(csv_path)
	for path: String in scaffold.expected_translation_paths():
		if FileAccess.file_exists(path):
			fs.update_file(path)
	_reset_locale_import_state()


func _on_locale_scan_done() -> void:
	_locale_scan_pending = false
	_defer_locale_import()


func _locale_done_message(translations_ok: bool) -> String:
	var csv_path: String = LocaleScaffold.LOCALE_CSV_PATH
	var action: String = "内置键已齐全（%s）" % csv_path
	if bool(_locale_prepare_result.get("created_csv", false)):
		action = "已生成 %s" % csv_path
	else:
		var merged: PackedStringArray = _locale_prepare_result.get(
			"merged_keys",
			PackedStringArray(),
		)
		if not merged.is_empty():
			action = "已补全 %d 个内置键（%s）" % [merged.size(), csv_path]
	if translations_ok:
		return "%s，已导入翻译并注册到 project.godot。" % action
	return "%s；翻译导入或注册未完成，请重试。" % action


func _reset_locale_import_state() -> void:
	_locale_prepare_result = {}
	_locale_scaffold = null
	_locale_show_done_status = false
	_locale_import_scheduled = false
	_locale_import_busy = false
	_locale_scan_pending = false
	_locale_import_attempts = 0


# =============================================================================
# External editor
# =============================================================================

func _external_editor_enabled() -> bool:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	return bool(settings.get_setting("text_editor/external/use_external_editor"))

func _external_editor_exec_path() -> String:
	if _external_editor_exec_cache_ready:
		return _external_editor_exec_cache
	if not _external_editor_enabled():
		_external_editor_exec_cache = ""
	else:
		var settings: EditorSettings = get_editor_interface().get_editor_settings()
		_external_editor_exec_cache = str(
			settings.get_setting("text_editor/external/exec_path")
		).strip_edges()
	_external_editor_exec_cache_ready = true
	return _external_editor_exec_cache

func _expand_external_editor_placeholders(
	template: String,
	project_dir: String,
	file_abs: String,
	line: int,
	col: int,
) -> String:
	var result: String = template
	result = result.replace("{project}", project_dir)
	result = result.replace("{file}", file_abs)
	result = result.replace("{line}", str(maxi(1, line)))
	result = result.replace("{col}", str(maxi(1, col)))
	return result

func _shell_split_argv(cmdline: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current: String = ""
	var in_single: bool = false
	var in_double: bool = false
	var i: int = 0
	while i < cmdline.length():
		var c: String = cmdline[i]
		if c == "'" and not in_double:
			in_single = not in_single
		elif c == '"' and not in_single:
			in_double = not in_double
		elif (c == " " or c == "\t") and not in_single and not in_double:
			if not current.is_empty():
				result.append(_strip_outer_quotes(current))
				current = ""
		else:
			current += c
		i += 1
	if not current.is_empty():
		result.append(_strip_outer_quotes(current))
	return result

func _strip_outer_quotes(s: String) -> String:
	if s.length() >= 2:
		if s.begins_with('"') and s.ends_with('"'):
			return s.substr(1, s.length() - 2)
		if s.begins_with("'") and s.ends_with("'"):
			return s.substr(1, s.length() - 2)
	return s

func _build_external_editor_args_project_only() -> PackedStringArray:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	var flags: String = str(settings.get_setting("text_editor/external/exec_flags"))
	var project_dir: Variant = _project_root_global_path()
	var expanded: String
	if flags.contains("{project}") and not flags.contains("{file}"):
		expanded = _expand_external_editor_placeholders(flags, project_dir, "", 1, 1)
	elif flags.contains("{project}"):
		expanded = '"{project}"'.replace("{project}", project_dir)
	else:
		expanded = '"%s"' % project_dir
	return _shell_split_argv(expanded)

func _build_external_editor_args_for_script(
	script_path: String, line: int, col: int, goto_only: bool = false
) -> PackedStringArray:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	var flags: String = str(settings.get_setting("text_editor/external/exec_flags"))
	var project_dir: Variant = _project_root_global_path()
	var file_abs: String = ProjectSettings.globalize_path(script_path)
	var line_n: int = maxi(1, line)
	var col_n: int = maxi(1, col)
	var expanded: String
	if goto_only:
		expanded = '--goto "%s:%d:%d"' % [file_abs, line_n, col_n]
	elif flags.contains("{project}") and flags.contains("{file}"):
		# 仅当同时包含 {project} 与 {file} 时才沿用用户模板；Godot 默认 {file} 只会打开单文件。
		expanded = _expand_external_editor_placeholders(
			flags, project_dir, file_abs, line_n, col_n
		)
	else:
		expanded = '"%s" --goto "%s:%d:%d"' % [project_dir, file_abs, line_n, col_n]
	return _shell_split_argv(expanded)

func _project_root_global_path() -> String:
	return ProjectSettings.globalize_path("res://").rstrip("/\\")

func _launch_external_editor_project() -> bool:
	if not _external_editor_enabled():
		_set_dock_status("general","未启用外部文本编辑器，请在编辑器设置中开启。")
		return false
	var exec_path: Variant = _external_editor_exec_path()
	if exec_path.is_empty():
		_set_dock_status("general","外部编辑器可执行文件路径为空。")
		return false
	var args: Variant = _build_external_editor_args_project_only()
	var pid: int = OS.create_process(exec_path, args)
	if pid < 0:
		_set_dock_status("general","启动失败，请检查可执行路径与启动参数。")
		return false
	_external_editor_project_launched = true
	return true

func _open_script_in_external_editor(
	script_path: String, line: int = 1, col: int = 1, goto_only: bool = false
) -> bool:
	if not FileAccess.file_exists(script_path):
		return false
	var exec_path: Variant = _external_editor_exec_path()
	if exec_path.is_empty():
		return false
	var args: Variant = _build_external_editor_args_for_script(script_path, line, col, goto_only)
	var pid: int = OS.create_process(exec_path, args)
	if pid < 0:
		push_warning(
			"GDFrame: 无法在外部编辑器打开 %s（create_process 返回 %s）。"
			% [script_path, pid]
		)
		return false
	return true

func _try_open_signals_in_running_external_editor() -> bool:
	for use_running_project in [true, false]:
		if _open_script_in_external_editor(GDFrameConfig.SIGNALS_SCRIPT_PATH, 1, 1, use_running_project):
			_set_dock_status("general","已在外部编辑器打开 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())
			return true
	return false

func _begin_external_editor_open_signals_retry() -> void:
	_set_dock_status("general","已在外部编辑器打开工程，正在打开信号脚本…")
	_external_editor_goto_retries_left = _EXTERNAL_EDITOR_GOTO_MAX_RETRIES
	_schedule_external_editor_goto_retry(_EXTERNAL_EDITOR_COLD_START_WAIT_SEC)

func _schedule_external_editor_goto_retry(wait_sec: float) -> void:
	var tree: SceneTree = get_editor_interface().get_base_control().get_tree()
	tree.create_timer(wait_sec).timeout.connect(
		Callable(self, "_external_editor_goto_retry_tick"),
		CONNECT_ONE_SHOT,
	)

func _external_editor_goto_retry_tick() -> void:
	if _open_script_in_external_editor(GDFrameConfig.SIGNALS_SCRIPT_PATH, 1, 1, false):
		_external_editor_goto_retries_left = 0
		_set_dock_status("general","已在外部编辑器打开 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())
		return
	_external_editor_goto_retries_left -= 1
	if _external_editor_goto_retries_left > 0:
		_schedule_external_editor_goto_retry(_EXTERNAL_EDITOR_GOTO_RETRY_WAIT_SEC)
		return
	_finish_open_signals_script()

func _finish_open_signals_script() -> void:
	if _external_editor_enabled():
		if _try_open_signals_in_running_external_editor():
			return
	if _open_script_in_editor(GDFrameConfig.SIGNALS_SCRIPT_PATH):
		_set_dock_status("general","已定位并在脚本编辑器中打开 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())
	else:
		_set_dock_status("general","已定位 %s，但无法在编辑器中打开" % GDFrameConfig.SIGNALS_SCRIPT_PATH.get_file())

# =============================================================================
# UI page
# =============================================================================

func _ui_tool_button(text: String, tip: String, method: StringName) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(Callable(self, method))
	return btn


func _build_create_ui_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var name_label: Label = Label.new()
	name_label.text = "新建 UI"
	row.add_child(name_label)

	_create_ui_name_edit = LineEdit.new()
	_create_ui_name_edit.placeholder_text = "main → ui_main.gd"
	_create_ui_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_create_ui_name_edit)

	var create_btn: Button = Button.new()
	create_btn.text = "创建"
	create_btn.pressed.connect(_on_create_ui_pressed)
	row.add_child(create_btn)

	_create_ui_status_label = _dock_status_label()
	panel.add_child(_create_ui_status_label)
	_set_dock_status("ui", "")

	var manage_row: HBoxContainer = HBoxContainer.new()
	manage_row.add_theme_constant_override("separation", 6)
	panel.add_child(manage_row)

	var manage_label: Label = Label.new()
	manage_label.text = "已创建 UI 列表"
	manage_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	manage_row.add_child(manage_label)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "刷新列表"
	refresh_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	refresh_btn.pressed.connect(_refresh_ui_manage_list)
	manage_row.add_child(refresh_btn)

	var manage_row_spacer: Control = Control.new()
	manage_row_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manage_row.add_child(manage_row_spacer)

	var dim_label: Label = Label.new()
	dim_label.text = "UI自定义遮罩："
	dim_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	manage_row.add_child(dim_label)

	manage_row.add_child(_ui_tool_button(
		"定位",
		"在文件系统 Dock 中选中该场景",
		&"_on_ui_locate_dim_scene",
	))
	manage_row.add_child(_ui_tool_button(
		"打开脚本",
		"在脚本编辑器中打开",
		&"_on_ui_open_dim_script",
	))
	manage_row.add_child(_ui_tool_button(
		"打开场景",
		"在场景编辑器中打开",
		&"_on_ui_open_dim_scene",
	))

	var list_scroll: ScrollContainer = ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(list_scroll)

	_ui_manage_list = VBoxContainer.new()
	_ui_manage_list.add_theme_constant_override("separation", 2)
	_ui_manage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_manage_list.custom_minimum_size = Vector2(0, 1)
	list_scroll.add_child(_ui_manage_list)

	_refresh_ui_manage_list()

	return panel

func _build_ui_template(_file_stem: String) -> String:
	return """extends GDFrameUIBase

@export_category("节点绑定")
# @export var _label_example: Label

func _on_init() -> void:
	pass

func _on_show(_data: Variant = null) -> void:
	pass

func _on_close() -> bool:
	return true

func _on_locale_changed() -> void:
	pass
"""

func _build_ui_scene_template(file_stem: String, script_path: String) -> String:
	return """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="%s" id="1"]

[node name="%s" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
ui_default_layer = 0
ui_use_dim = false
""" % [script_path, file_stem]

func _on_create_ui_pressed() -> void:
	if not _require_editor_not_playing("ui", "创建 UI"):
		return
	var raw_name: String = _create_ui_name_edit.text.strip_edges()
	if raw_name.is_empty():
		_set_dock_status("ui", "状态: 请输入 UI 名称")
		return

	var file_stem: Variant = AssetNameUtil.normalize_ui_name(raw_name)
	var ui_dir: String = "%s/%s" % [GDFrameConfig.UI_ROOT_DIR, file_stem]
	var script_path: String = "%s/%s.gd" % [ui_dir, file_stem]
	var scene_path: String = "%s/%s.tscn" % [ui_dir, file_stem]
	var dir_err: Error = _ensure_res_dir(ui_dir)
	if dir_err != OK:
		_set_dock_status("ui", "状态: 无法创建目录（错误 %s）" % dir_err)
		return

	if _res_file_exists(script_path) or _res_file_exists(scene_path):
		_set_dock_status("ui", "状态: 已存在 %s" % file_stem)
		return

	_ensure_generated_dir()
	if not _res_file_exists(GDFrameConfig.CONSTANTS_SCRIPT_PATH):
		_regenerate_constants_registry(true)

	var script_err: Error = _write_res_text(script_path, _build_ui_template(file_stem))
	if script_err != OK:
		_set_dock_status("ui", "状态: 创建脚本失败（错误 %s）" % script_err)
		return

	var scene_err: Error = _write_res_text(
		scene_path, _build_ui_scene_template(file_stem, script_path)
	)
	if scene_err != OK:
		_safe_delete(script_path)
		_set_dock_status("ui", "状态: 创建场景失败（错误 %s）" % scene_err)
		return

	_set_dock_status("ui", "状态: 已创建 %s（见文件系统 %s）" % [file_stem, ui_dir])
	_after_asset_tree_change(true, false, false, PackedStringArray([scene_path, script_path]))
	_create_ui_name_edit.text = ""

func _refresh_ui_manage_list(scenes: Array[String] = []) -> void:
	if _ui_manage_list == null:
		return
	_ui_list_dirty = false
	for child in _ui_manage_list.get_children():
		child.queue_free()

	if scenes.is_empty():
		scenes = _get_ui_scene_paths()

	var row_i: int = 0
	for scene_path in scenes:
		if not _res_file_exists(scene_path):
			continue
		var scene_name: String = scene_path.get_file().get_basename()
		var script_path: String = "%s/%s.gd" % [scene_path.get_base_dir(), scene_name]
		var settings: Dictionary = _read_ui_scene_settings(scene_path)
		_ui_manage_list.add_child(
			_build_ui_manage_row(
				row_i,
				scene_path,
				scene_name,
				script_path,
				settings,
			)
		)
		row_i += 1

	if scenes.is_empty():
		var empty: Label = Label.new()
		empty.text = "暂无 UI 场景"
		_ui_manage_list.add_child(empty)
	else:
		_set_dock_status("ui", "状态: 已加载 %d 个 UI" % scenes.size())

func _read_ui_scene_settings(scene_path: String) -> Dictionary:
	var defaults: Dictionary = {"layer": 0, "use_dim": false}
	if not _res_file_exists(scene_path):
		return defaults
	return _parse_ui_scene_settings_from_tscn(_read_res_text(scene_path))


func _parse_ui_scene_settings_from_tscn(tscn_text: String) -> Dictionary:
	var settings: Dictionary = {"layer": 0, "use_dim": false}
	for line: String in tscn_text.split("\n", false):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("ui_default_layer = "):
			settings["layer"] = clampi(
				int(stripped.trim_prefix("ui_default_layer = ").strip_edges()),
				0,
				63,
			)
		elif stripped.begins_with("ui_use_dim = "):
			settings["use_dim"] = stripped.trim_prefix("ui_use_dim = ").strip_edges() == "true"
	return settings


func _patch_ui_scene_settings_in_tscn(tscn_text: String, layer: int, use_dim: bool) -> String:
	if tscn_text.is_empty():
		return ""
	var layer_line: String = "ui_default_layer = %d" % layer
	var dim_line: String = "ui_use_dim = %s" % ("true" if use_dim else "false")
	var has_layer: bool = false
	var has_dim: bool = false
	var out: PackedStringArray = PackedStringArray()
	for line: String in tscn_text.split("\n", false):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("ui_default_layer = "):
			out.append(layer_line)
			has_layer = true
		elif stripped.begins_with("ui_use_dim = "):
			out.append(dim_line)
			has_dim = true
		else:
			out.append(line)
			if stripped.begins_with("script = ") and not has_layer:
				out.append(layer_line)
				out.append(dim_line)
				has_layer = true
				has_dim = true
	if not has_layer:
		out.append(layer_line)
	if not has_dim:
		out.append(dim_line)
	var joined: String = "\n".join(out)
	if tscn_text.ends_with("\n"):
		joined += "\n"
	return joined


func _write_ui_scene_settings(scene_path: String, layer: int, use_dim: bool) -> Error:
	if not _res_file_exists(scene_path):
		return ERR_FILE_NOT_FOUND
	layer = clampi(layer, 0, _config.ui_max_layer)
	var content: String = _patch_ui_scene_settings_in_tscn(
		_read_res_text(scene_path),
		layer,
		use_dim,
	)
	if content.is_empty():
		return ERR_INVALID_DATA
	return _write_res_text(scene_path, content)

func _build_ui_manage_row(
	row_index: int,
	scene_path: String,
	scene_name: String,
	script_path: String,
	settings: Dictionary,
) -> PanelContainer:
	var stripe: PanelContainer = PanelContainer.new()
	stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stripe.add_theme_stylebox_override(&"panel", _dock_row_stripe_stylebox((row_index % 2) == 1))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label: Label = Label.new()
	name_label.text = scene_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = "%s\n%s" % [scene_path, script_path]
	row.add_child(name_label)

	var layer_opt: OptionButton = OptionButton.new()
	layer_opt.tooltip_text = "ui_default_layer，与场景根 GDFrame 分组一致"
	var layer_max: int = _config.ui_max_layer
	for i: int in range(layer_max + 1):
		layer_opt.add_item("层 %d" % i, i)
	var layer_val: int = clampi(int(settings.get("layer", 0)), 0, layer_max)
	layer_opt.select(layer_val)
	layer_opt.custom_minimum_size.x = 64.0
	layer_opt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(layer_opt)

	var dim_check: CheckBox = CheckBox.new()
	dim_check.text = "遮罩"
	dim_check.button_pressed = bool(settings.get("use_dim", false))
	row.add_child(dim_check)

	var save_settings := func() -> void:
		if not _require_editor_not_playing("ui", "修改 UI 设置"):
			layer_opt.select(clampi(int(settings.get("layer", 0)), 0, layer_max))
			dim_check.set_pressed_no_signal(bool(settings.get("use_dim", false)))
			return
		var layer: int = layer_opt.selected
		var use_dim: bool = dim_check.button_pressed
		if layer == int(settings.get("layer", 0)) and use_dim == bool(settings.get("use_dim", false)):
			return
		var err: Error = _write_ui_scene_settings(scene_path, layer, use_dim)
		if err != OK:
			_set_dock_status("ui", "状态: 保存 %s 失败（错误 %s）" % [scene_name, err])
			layer_opt.select(clampi(int(settings.get("layer", 0)), 0, layer_max))
			dim_check.set_pressed_no_signal(bool(settings.get("use_dim", false)))
			return
		settings["layer"] = layer
		settings["use_dim"] = use_dim
		_update_editor_filesystem(scene_path)
		_set_dock_status("ui", "状态: 已保存 %s（层 %d%s）" % [
			scene_name,
			layer,
			"，遮罩" if use_dim else "",
		])

	layer_opt.item_selected.connect(func(_index: int) -> void: save_settings.call())
	dim_check.toggled.connect(func(_pressed: bool) -> void: save_settings.call())

	var actions: Array = [
		{
			"text": "定位",
			"tip": "在文件系统 Dock 中选中该脚本",
			"callback": _on_ui_navigate_script_in_filesystem.bind(script_path),
		},
		{
			"text": "打开脚本",
			"tip": "在脚本编辑器中打开",
			"callback": _on_ui_open_script.bind(script_path),
		},
		{
			"text": "打开场景",
			"tip": "在场景编辑器中打开",
			"callback": _on_ui_open_scene.bind(scene_path),
		},
		{
			"text": "更名",
			"tip": "重命名 UI 目录、脚本与场景（并刷新 GDFrameConstants）",
			"callback": func() -> void:
				_request_rename_ui(scene_path),
		},
		{
			"text": "删除",
			"tip": "删除此 UI 的 .gd/.tscn 及 .uid",
			"callback": func() -> void:
				_request_delete_ui(scene_path),
		},
	]
	for action: Variant in actions:
		if action is not Dictionary:
			continue
		var act: Dictionary = action as Dictionary
		var btn: Button = Button.new()
		btn.text = String(act.get("text", ""))
		btn.tooltip_text = String(act.get("tip", ""))
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var cb: Callable = act.get("callback", Callable()) as Callable
		if cb.is_valid():
			btn.pressed.connect(cb)
		row.add_child(btn)

	stripe.add_child(row)
	return stripe

func _navigate_script_in_filesystem(script_path: String) -> bool:
	if not FileAccess.file_exists(script_path):
		return false
	get_editor_interface().get_file_system_dock().navigate_to_path(script_path)
	return true

func _open_script_in_editor(script_path: String) -> bool:
	if not FileAccess.file_exists(script_path):
		return false
	var scr: Resource = load(script_path)
	if scr is Script:
		get_editor_interface().edit_script(scr as Script)
		return true
	return false

func _on_ui_navigate_script_in_filesystem(script_path: String) -> void:
	if _navigate_script_in_filesystem(script_path):
		_set_dock_status("ui", "状态: 已在文件系统中定位 %s" % script_path.get_file())
	else:
		_set_dock_status("ui", "状态: 未找到脚本 %s" % script_path.get_file())

func _on_ui_open_script(script_path: String) -> void:
	if _open_script_in_editor(script_path):
		_set_dock_status("ui", "状态: 已打开 %s" % script_path.get_file())
	else:
		_set_dock_status("ui", "状态: 未找到或无法打开 %s" % script_path.get_file())


func _on_ui_open_scene(scene_path: String) -> void:
	_set_dock_status("ui", "")
	if not FileAccess.file_exists(scene_path):
		_set_dock_status("ui", "状态: 未找到场景 %s" % scene_path.get_file())
		return
	get_editor_interface().open_scene_from_path(scene_path)
	_set_dock_status("ui", "状态: 已在场景编辑器中打开 %s" % scene_path.get_file())


func _request_rename_ui(scene_path: String) -> void:
	if not _require_editor_not_playing("ui", "重命名 UI"):
		return
	_pending_rename_scene_path = scene_path
	var scene_name: String = scene_path.get_file().get_basename()
	_rename_ui_name_edit.text = ""
	_rename_ui_target_label.text = "将 %s 重命名为：" % scene_name
	_rename_ui_dialog.popup_centered(Vector2i(420, 120))
	_rename_ui_name_edit.grab_focus()

func _on_rename_ui_confirmed() -> void:
	if _pending_rename_scene_path.is_empty():
		return
	var raw_name: String = _rename_ui_name_edit.text.strip_edges()
	if raw_name.is_empty():
		_set_dock_status("ui", "状态: 请输入新 UI 名称")
		return
	var scene_path: Variant = _pending_rename_scene_path
	_pending_rename_scene_path = ""
	_rename_ui_bundle.call_deferred(scene_path, raw_name)

func _rename_ui_bundle(old_scene_path: String, raw_new_name: String) -> void:
	var old_stem: String = old_scene_path.get_file().get_basename()
	var new_stem: Variant = AssetNameUtil.normalize_ui_name(raw_new_name)
	if new_stem == old_stem:
		_set_dock_status("ui", "状态: 名称未变化")
		return

	var old_dir: String = old_scene_path.get_base_dir()
	var old_script_path: String = "%s/%s.gd" % [old_dir, old_stem]
	var new_dir: String = "%s/%s" % [GDFrameConfig.UI_ROOT_DIR, new_stem]
	var new_script_path: String = "%s/%s.gd" % [new_dir, new_stem]
	var new_scene_path: String = "%s/%s.tscn" % [new_dir, new_stem]

	if _res_dir_exists(new_dir) or _res_file_exists(new_scene_path):
		_set_dock_status("ui", "状态: 目标已存在 %s" % new_stem)
		return
	if not _res_file_exists(old_scene_path) or not _res_file_exists(old_script_path):
		_set_dock_status("ui", "状态: 源 UI 文件缺失，无法重命名")
		return

	var script_text: Variant = _read_res_text(old_script_path)
	var old_script_uid: Variant = _read_resource_uid("%s.uid" % old_script_path)
	script_text = _replace_gdframe_constants_refs(script_text, old_stem, new_stem, true)

	var dir_err: Variant = _ensure_res_dir(new_dir)
	if dir_err != OK:
		_set_dock_status("ui", "状态: 无法创建目录 %s（错误 %s）" % [new_dir, dir_err])
		return

	if _write_res_text(new_script_path, script_text) != OK:
		_set_dock_status("ui", "状态: 无法写入脚本 %s" % new_script_path.get_file())
		_try_remove_empty_dir(new_dir, GDFrameConfig.UI_ROOT_DIR)
		return

	if not old_script_uid.is_empty():
		_write_res_text("%s.uid" % new_script_path, old_script_uid + "\n")

	var scene_text: Variant = _read_res_text(old_scene_path)
	scene_text = _update_ui_scene_for_rename(
		scene_text, old_script_path, new_script_path, old_stem, new_stem
	)

	if _write_res_text(new_scene_path, scene_text) != OK:
		_safe_delete(new_script_path)
		_safe_delete("%s.uid" % new_script_path)
		_try_remove_empty_dir(new_dir, GDFrameConfig.UI_ROOT_DIR)
		_set_dock_status("ui", "状态: 无法写入场景 %s" % new_scene_path.get_file())
		return

	_delete_ui_bundle(old_scene_path, false)

	_after_asset_tree_change(
		true,
		false,
		false,
		PackedStringArray([new_scene_path, new_script_path]),
	)
	_set_dock_status("ui", "状态: 已重命名 %s → %s" % [old_stem, new_stem])

func _update_ui_scene_for_rename(
	source: String,
	old_script_path: String,
	new_script_path: String,
	old_stem: String,
	new_stem: String,
) -> String:
	var result: String = source.replace(old_script_path, new_script_path)
	result = result.replace('[node name="%s"' % old_stem, '[node name="%s"' % new_stem)
	return _sync_ui_scene_script_uid(result, new_script_path)

func _sync_ui_scene_script_uid(scene_text: String, script_path: String) -> String:
	var script_uid: Variant = _read_resource_uid("%s.uid" % script_path)
	var lines: PackedStringArray = scene_text.split("\n")
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if not line.begins_with('[ext_resource type="Script"'):
			continue
		if script_uid.is_empty():
			lines[i] = _remove_script_uid_from_ext_resource(line)
		else:
			lines[i] = _set_script_uid_on_ext_resource(line, script_uid)
		break
	return "\n".join(lines)

func _read_resource_uid(uid_path: String) -> String:
	if not FileAccess.file_exists(uid_path):
		return ""
	return FileAccess.get_file_as_string(uid_path).strip_edges()

func _remove_script_uid_from_ext_resource(line: String) -> String:
	var uid_pos: int = line.find(' uid="uid://')
	if uid_pos == -1:
		return line
	var uid_end: int = line.find('"', uid_pos + 6)
	if uid_end == -1:
		return line
	return line.substr(0, uid_pos) + line.substr(uid_end + 1)

func _set_script_uid_on_ext_resource(line: String, script_uid: String) -> String:
	var uid_pos: int = line.find(' uid="uid://')
	if uid_pos == -1:
		var insert_pos: int = line.find(' path="')
		if insert_pos == -1:
			return line
		return line.substr(0, insert_pos) + ' uid="%s"' % script_uid + line.substr(insert_pos)
	var uid_end: int = line.find('"', uid_pos + 6)
	if uid_end == -1:
		return line
	return line.substr(0, uid_pos) + ' uid="%s"' % script_uid + line.substr(uid_end + 1)

func _request_delete_ui(scene_path: String) -> void:
	if not _require_editor_not_playing("ui", "删除 UI"):
		return
	_pending_delete_scene_path = scene_path
	var scene_name: String = scene_path.get_file().get_basename()
	_delete_confirm_dialog.dialog_text = "确认删除 %s 吗？\n将删除同目录下同名 .gd/.tscn 及 .uid 文件。" % scene_name
	_delete_confirm_dialog.popup_centered(Vector2i(460, 140))

func _on_delete_confirmed() -> void:
	if _pending_delete_scene_path.is_empty():
		return
	var scene_path: String = _pending_delete_scene_path
	_pending_delete_scene_path = ""
	_delete_ui_bundle.call_deferred(scene_path)

func _delete_ui_bundle(scene_path: String, refresh_registry: bool = true) -> void:
	var scene_name: String = scene_path.get_file().get_basename()
	var script_path: String = "%s/%s.gd" % [scene_path.get_base_dir(), scene_name]
	var scene_uid_path: String = "%s.uid" % scene_path
	var script_uid_path: String = "%s.uid" % script_path

	var deleted_any: bool = false
	deleted_any = _safe_delete(scene_path) or deleted_any
	deleted_any = _safe_delete(scene_uid_path) or deleted_any
	deleted_any = _safe_delete(script_path) or deleted_any
	deleted_any = _safe_delete(script_uid_path) or deleted_any

	_try_remove_empty_dir(scene_path.get_base_dir(), GDFrameConfig.UI_ROOT_DIR)
	if refresh_registry:
		var ui_dir: String = scene_path.get_base_dir()
		var notify_paths: PackedStringArray = PackedStringArray()
		if _res_dir_exists(ui_dir):
			notify_paths.append(ui_dir)
		else:
			notify_paths.append(GDFrameConfig.UI_ROOT_DIR)
		_after_asset_tree_change(true, false, false, notify_paths)

	if deleted_any:
		if refresh_registry:
			_set_dock_status("ui", "状态: 已删除 %s" % scene_name)
	else:
		if refresh_registry:
			_set_dock_status("ui", "状态: 删除失败 %s" % scene_name)

# =============================================================================
# Extension page
# =============================================================================

func _build_ext_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var create_row: HBoxContainer = HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 6)
	panel.add_child(create_row)

	var create_title: Label = Label.new()
	create_title.text = "新建扩展"
	create_title.custom_minimum_size.x = 56
	create_row.add_child(create_title)

	var id_label: Label = Label.new()
	id_label.text = "ID"
	id_label.custom_minimum_size.x = 28
	create_row.add_child(id_label)

	_create_ext_id_edit = LineEdit.new()
	_create_ext_id_edit.placeholder_text = "example_feature"
	_create_ext_id_edit.custom_minimum_size.x = 88
	_create_ext_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_create_ext_id_edit)

	var name_label: Label = Label.new()
	name_label.text = "名称"
	name_label.custom_minimum_size.x = 36
	create_row.add_child(name_label)

	_create_ext_name_edit = LineEdit.new()
	_create_ext_name_edit.placeholder_text = "我的功能"
	_create_ext_name_edit.custom_minimum_size.x = 88
	_create_ext_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_create_ext_name_edit)

	_create_ext_template_opt = OptionButton.new()
	_create_ext_template_opt.add_item("Facade 型", ExtCreate.Template.FACADE)
	_create_ext_template_opt.add_item("Profile 型", ExtCreate.Template.PROFILE_ONLY)
	_create_ext_template_opt.add_item("最小占位", ExtCreate.Template.MINIMAL)
	create_row.add_child(_create_ext_template_opt)

	var create_btn: Button = Button.new()
	create_btn.text = "创建"
	create_btn.pressed.connect(_on_create_ext_pressed)
	create_row.add_child(create_btn)

	var ext_status_row: HBoxContainer = HBoxContainer.new()
	ext_status_row.add_theme_constant_override("separation", 6)
	panel.add_child(ext_status_row)

	_ext_status_label = _dock_status_label()
	_ext_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ext_status_row.add_child(_ext_status_label)

	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	panel.add_child(tab_row)

	var ext_btn_group: ButtonGroup = ButtonGroup.new()

	_ext_installed_btn = Button.new()
	_ext_installed_btn.text = "已安装"
	_ext_installed_btn.toggle_mode = true
	_ext_installed_btn.button_pressed = true
	_ext_installed_btn.button_group = ext_btn_group
	_ext_installed_btn.pressed.connect(func() -> void:
		_show_ext_list_tab(0)
	)
	tab_row.add_child(_ext_installed_btn)

	_ext_available_btn = Button.new()
	_ext_available_btn.text = "未安装"
	_ext_available_btn.toggle_mode = true
	_ext_available_btn.button_group = ext_btn_group
	_ext_available_btn.pressed.connect(func() -> void:
		_show_ext_list_tab(1)
	)
	tab_row.add_child(_ext_available_btn)

	var tab_spacer: Control = Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)

	var source_label: Label = Label.new()
	source_label.text = "更新源"
	source_label.custom_minimum_size.x = 48
	tab_row.add_child(source_label)

	_ext_source_option = OptionButton.new()
	_ext_source_option.add_item("GitHub", 0)
	_ext_source_option.add_item("Gitee", 1)
	var ext_source: String = _updater.get_source()
	if ext_source == "gitee":
		_ext_source_option.select(1)
	else:
		_ext_source_option.select(0)
	_ext_source_option.item_selected.connect(_on_ext_source_changed)
	tab_row.add_child(_ext_source_option)
	_sync_ext_source_display(ext_source, false)

	var check_btn: Button = Button.new()
	check_btn.text = "检查更新"
	check_btn.pressed.connect(_on_ext_check_updates_pressed)
	tab_row.add_child(check_btn)

	var gen_btn: Button = Button.new()
	gen_btn.text = "生成扩展 API"
	gen_btn.pressed.connect(_on_ext_generate_api_pressed)
	tab_row.add_child(gen_btn)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "刷新列表"
	refresh_btn.pressed.connect(_refresh_ext_manage_list)
	tab_row.add_child(refresh_btn)
	_set_dock_status("ext", "")

	var list_host: Control = Control.new()
	list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(list_host)

	_ext_installed_scroll = ScrollContainer.new()
	_ext_installed_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ext_installed_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ext_installed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_host.add_child(_ext_installed_scroll)

	_ext_installed_list = VBoxContainer.new()
	_ext_installed_list.add_theme_constant_override("separation", 2)
	_ext_installed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ext_installed_list.custom_minimum_size = Vector2(0, 1)
	_ext_installed_scroll.add_child(_ext_installed_list)

	_ext_available_scroll = ScrollContainer.new()
	_ext_available_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ext_available_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ext_available_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ext_available_scroll.visible = false
	list_host.add_child(_ext_available_scroll)

	_ext_available_list = VBoxContainer.new()
	_ext_available_list.add_theme_constant_override("separation", 2)
	_ext_available_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ext_available_list.custom_minimum_size = Vector2(0, 1)
	_ext_available_scroll.add_child(_ext_available_list)

	return panel


func _on_create_ext_pressed() -> void:
	if not _require_editor_not_playing("ext", "创建扩展"):
		return
	var raw_id: String = _create_ext_id_edit.text.strip_edges()
	if raw_id.is_empty():
		_set_dock_status("ext", "状态: 请输入扩展 ID")
		return
	var module_id: String = ExtCreate.normalize_module_id(raw_id)
	var display_name: String = _create_ext_name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = module_id
	var ext_dir: String = "%s/%s" % [GDFrameConfig.EXT_ROOT_DIR, module_id]
	var module_path: String = "%s/module.gd" % ext_dir
	if _res_file_exists(module_path):
		_set_dock_status("ext", "状态: 扩展 %s 已存在" % module_id)
		return
	var dir_err: Error = _ensure_res_dir(ext_dir)
	if dir_err != OK:
		_set_dock_status("ext", "状态: 无法创建目录（错误 %s）" % dir_err)
		return
	dir_err = _ensure_res_dir(ext_dir.path_join("editor"))
	if dir_err != OK:
		_set_dock_status("ext", "状态: 无法创建 editor 目录（错误 %s）" % dir_err)
		return
	_ensure_ext_scaffold()
	var template: int = _create_ext_template_opt.get_selected_id()
	var files: Dictionary = ExtCreate.build_files(module_id, display_name, template)
	var written_paths: PackedStringArray = PackedStringArray()
	for rel_path: String in files.keys():
		var file_path: String = ext_dir.path_join(rel_path)
		if _write_res_text(file_path, str(files[rel_path])) != OK:
			_set_dock_status("ext", "状态: 写入 %s 失败" % rel_path)
			return
		written_paths.append(file_path)
	_set_dock_status("ext", "状态: 已创建 %s（%d 个文件）" % [module_id, written_paths.size()])
	_apply_ext_facade_generate_result(_run_ext_facade_generate())
	written_paths.append(GDFrameConfig.EXT_FACADE_MODULES_PATH)
	written_paths.append(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH)
	written_paths.append(GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH)
	_after_asset_tree_change(false, false, false, written_paths, true)
	_create_ext_id_edit.text = ""
	_create_ext_name_edit.text = ""


func _on_ext_generate_api_pressed() -> void:
	_apply_ext_facade_generate_result(_run_ext_facade_generate())
	if _general_status_label != null:
		var general_text: String = _general_status_label.text
		var default_general: String = _format_dock_status_text(
			str(_DOCK_STATUS_DEFAULTS.get("general", ""))
		)
		if not general_text.is_empty() and general_text != default_general:
			_set_dock_status("ext", general_text)
	_refresh_ext_manage_list()


func _ensure_ext_updater() -> void:
	if _ext_updater == null:
		_ext_updater = ExtUpdaterScript.new()


func _refresh_ext_on_page_show() -> void:
	_ensure_ext_updater()
	var source: String = _updater.get_source()
	if _ext_source_option != null:
		_ext_source_option.select(1 if source == "gitee" else 0)
	_sync_ext_source_display(source, false)
	_load_local_ext_index()


func _on_ext_check_updates_pressed() -> void:
	_ensure_ext_updater()
	_refresh_ext_index()


func _on_ext_source_changed(index: int) -> void:
	_apply_update_source(index, false, false)
	_sync_ext_source_display(_updater.get_source(), true)


func _sync_ext_source_display(source: String, update_status: bool = true) -> void:
	var url: String = ExtManageList.ext_index_fetch_url(source)
	if _ext_source_option != null:
		_ext_source_option.tooltip_text = "URL: %s" % url
	if update_status:
		_set_dock_status("ext", "状态: URL: %s" % url)


func _apply_update_source(index: int, refresh_plugin: bool, refresh_ext: bool) -> void:
	_updater.set_source("gitee" if index == 1 else "github")
	var source: String = _updater.get_source()
	if _source_option != null:
		_source_option.select(index)
	if _ext_source_option != null:
		_ext_source_option.select(index)
	_sync_update_source_display(source)
	if refresh_plugin:
		_load_local_plugin_index()
	if refresh_ext:
		_load_local_ext_index()


func _load_local_ext_index() -> void:
	_ensure_ext_updater()
	_ext_check_seq += 1
	var check_seq: int = _ext_check_seq
	var source_str: String = _updater.get_source()
	_ext_updater.set_source(source_str)
	_ext_index_info = _ext_updater.load_local_ext_index()
	if check_seq != _ext_check_seq:
		return
	_apply_ext_index_status(_ext_index_info)


func _refresh_ext_index() -> void:
	_ensure_ext_updater()
	_ext_check_seq += 1
	var check_seq: int = _ext_check_seq
	var source_str: String = _updater.get_source()
	_set_dock_status("ext", "状态: 正在检查扩展更新 (%s)..." % source_str)
	_ext_updater.set_source(source_str)
	var ext_index: Dictionary = await _ext_updater.fetch_ext_index(self)
	if check_seq != _ext_check_seq:
		return
	if not ext_index.has("error"):
		_ext_index_info = ext_index
	else:
		var local: Dictionary = _ext_updater.load_local_ext_index()
		if not local.has("error"):
			local["fetch_error"] = str(ext_index.get("error", "http"))
			local["http_status"] = int(ext_index.get("http_status", _ext_updater.get_last_http_status()))
			_ext_index_info = local
		else:
			_ext_index_info = ext_index
	_apply_ext_index_status(_ext_index_info)


func _apply_ext_index_status(ext_index: Dictionary) -> void:
	if ext_index.is_empty() or (ext_index.has("error") and not ext_index.has("fetch_error")):
		var status: int = int(ext_index.get("http_status", _ext_updater.get_last_http_status()))
		var err_kind: String = String(ext_index.get("error", "http"))
		if err_kind == "local_missing":
			_set_dock_status("ext", "状态: 尚未检查扩展更新，请点击「检查更新」")
		elif err_kind == "parse" or err_kind == "empty":
			_set_dock_status("ext", "状态: 本地扩展版本索引无效，请点击「检查更新」")
		else:
			_set_dock_status(
				"ext",
				"状态: 扩展版本索引获取失败（%s）" % VersionSeries.format_fetch_error_hint(
					err_kind,
					status,
					_updater.get_source(),
				),
			)
		_refresh_ext_manage_list()
		return
	var fetch_err: String = str(ext_index.get("fetch_error", ""))
	var fetch_http: int = int(ext_index.get("http_status", _ext_updater.get_last_http_status()))
	var patch_count: int = 0
	var eol_count: int = 0
	var install_count: int = 0
	for info: Dictionary in ExtManageList.build_manage_list(ext_index):
		var selection_status: String = str(info.get("selection_status", ""))
		if selection_status == "patch_available":
			patch_count += 1
		elif selection_status == "eol_migrate_required":
			eol_count += 1
		if not bool(info.get("installed", true)):
			install_count += 1
	var status_text: String = ""
	if patch_count > 0 and install_count > 0:
		status_text = "%d 个可安装，%d 个扩展有补丁更新" % [install_count, patch_count]
	elif eol_count > 0:
		status_text = "%d 个扩展需选择受支持版本" % eol_count
	elif install_count > 0:
		status_text = "%d 个扩展可安装" % install_count
	elif patch_count > 0:
		status_text = "%d 个扩展有补丁更新" % patch_count
	else:
		status_text = "扩展已是最新受支持版本"
	if not fetch_err.is_empty():
		status_text += VersionSeries.format_remote_failure_suffix(
			fetch_err,
			fetch_http,
			_updater.get_source(),
			"本地扩展版本索引",
		)
	_set_dock_status("ext", "状态: %s" % status_text)
	_refresh_ext_manage_list()


func _clear_ext_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()


func _refresh_ext_manage_list() -> void:
	if _ext_installed_list == null or _ext_available_list == null:
		return
	if _ext_updater == null:
		_ensure_ext_updater()
	_clear_ext_list(_ext_installed_list)
	_clear_ext_list(_ext_available_list)
	var infos: Array[Dictionary] = ExtManageList.build_manage_list(_ext_index_info)
	_ext_infos = infos
	var installed_row: int = 0
	var available_row: int = 0
	var installed_count: int = 0
	var available_count: int = 0
	for info: Dictionary in infos:
		if bool(info.get("installed", true)):
			installed_row = _append_ext_manage_row(_ext_installed_list, installed_row, info, true)
			installed_count += 1
		else:
			available_row = _append_ext_manage_row(_ext_available_list, available_row, info, false)
			available_count += 1
	if installed_count == 0:
		var empty_installed: Label = Label.new()
		empty_installed.text = "暂无已安装扩展（可上方创建，或切到「未安装」下载）"
		_ext_installed_list.add_child(empty_installed)
	if available_count == 0:
		var empty_available: Label = Label.new()
		empty_available.text = "暂无可安装扩展（检查扩展版本索引或切换更新源）"
		_ext_available_list.add_child(empty_available)
	if _ext_installed_btn != null:
		_ext_installed_btn.text = "已安装 (%d)" % installed_count
	if _ext_available_btn != null:
		_ext_available_btn.text = "未安装 (%d)" % available_count


func _show_ext_list_tab(tab: int) -> void:
	if _ext_installed_scroll != null:
		_ext_installed_scroll.visible = tab == 0
	if _ext_available_scroll != null:
		_ext_available_scroll.visible = tab == 1
	if _ext_installed_btn != null:
		_ext_installed_btn.button_pressed = tab == 0
	if _ext_available_btn != null:
		_ext_available_btn.button_pressed = tab == 1


func _append_ext_manage_row(list: VBoxContainer, row_i: int, info: Dictionary, is_installed: bool) -> int:
	var module_id: String = str(info.get("id", ""))
	var module_path: String = str(info.get("module_path", ""))
	var ext_dir: String = str(info.get("ext_dir", ""))
	var module_name: String = str(info.get("name", "")).strip_edges()
	var local_version: String = str(info.get("version", ""))
	var caps: String = ", ".join(info.get("capabilities", PackedStringArray()))
	var meta_hint: String = ""
	var has_module_cfg: bool = bool(info.get("has_module_cfg", false))
	if is_installed and not has_module_cfg:
		meta_hint = "（无 module.cfg）"
	var display_label: String = module_name if not module_name.is_empty() else module_id
	var default_version: String = str(info.get("default_version", ""))
	var version_text: String = ""
	if is_installed:
		version_text = "v%s" % local_version
	elif not default_version.is_empty():
		version_text = "v%s" % default_version
	else:
		version_text = "未安装"
	var tooltip: String = ""
	if is_installed:
		tooltip = (
			"%s\n%s\nfacade: %d  profile: %d\n能力: %s"
			% [module_path, ext_dir, int(info.get("facade_count", 0)), int(info.get("profile_count", 0)), caps]
		)
	else:
		tooltip = "扩展索引 %s" % module_id
	var title_parts: PackedStringArray = PackedStringArray()
	if is_installed:
		if not module_name.is_empty() and module_name != module_id:
			title_parts.append(module_name)
		title_parts.append(module_id)
	else:
		if not module_name.is_empty():
			title_parts.append(module_name)
		title_parts.append(module_id)
	title_parts.append("%s%s" % [version_text, meta_hint])
	var title: String = "  ".join(title_parts)

	var stripe: PanelContainer = PanelContainer.new()
	stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stripe.add_theme_stylebox_override(&"panel", _dock_row_stripe_stylebox((row_i % 2) == 1))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label: Label = Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	row.add_child(name_label)

	var version_opt: OptionButton = _build_ext_supported_version_option(info, is_installed)
	if version_opt.get_item_count() > 0:
		row.add_child(version_opt)

	if is_installed:
		if version_opt.get_item_count() > 0:
			var update_btn: Button = Button.new()
			update_btn.text = "更新"
			update_btn.pressed.connect(_on_ext_update_pressed.bind(version_opt))
			version_opt.item_selected.connect(
				_on_ext_installed_version_selected.bind(version_opt, update_btn)
			)
			_sync_ext_update_button(update_btn, version_opt)
			row.add_child(update_btn)
		var nav_btn: Button = Button.new()
		nav_btn.text = "定位"
		nav_btn.tooltip_text = "在文件系统 Dock 中选中 module.gd"
		nav_btn.pressed.connect(_on_ext_navigate_module.bind(module_path))
		row.add_child(nav_btn)
		var open_btn: Button = Button.new()
		open_btn.text = "打开"
		open_btn.tooltip_text = "在脚本编辑器中打开 module.gd"
		open_btn.pressed.connect(_on_ext_open_module.bind(module_path))
		row.add_child(open_btn)
		var del_btn: Button = Button.new()
		del_btn.text = "删除"
		del_btn.tooltip_text = "删除整个扩展目录"
		del_btn.pressed.connect(func() -> void:
			_request_delete_ext(ext_dir, display_label),
		)
		row.add_child(del_btn)
	else:
		var install_btn: Button = Button.new()
		install_btn.text = "安装"
		install_btn.tooltip_text = "安装所选扩展版本"
		install_btn.disabled = version_opt.get_item_count() == 0
		install_btn.pressed.connect(_on_ext_install_pressed.bind(version_opt))
		row.add_child(install_btn)

	stripe.add_child(row)
	list.add_child(stripe)
	return row_i + 1


func _build_ext_supported_version_option(info: Dictionary, is_installed: bool) -> OptionButton:
	var version_opt: OptionButton = OptionButton.new()
	version_opt.custom_minimum_size.x = 108
	var supported_entries: Array = info.get("supported_entries", [])
	var local_version: String = str(info.get("version", ""))
	var default_version: String = str(info.get("default_version", ""))
	var selected_idx: int = 0
	for i: int in supported_entries.size():
		if supported_entries[i] is not Dictionary:
			continue
		var entry: Dictionary = supported_entries[i] as Dictionary
		var ver: String = str(entry.get("version", ""))
		if ver.is_empty():
			continue
		version_opt.add_item(ver)
		var idx: int = version_opt.get_item_count() - 1
		version_opt.set_item_metadata(idx, entry)
		if is_installed and not local_version.is_empty() and ver == local_version:
			selected_idx = idx
		elif not is_installed and not default_version.is_empty() and ver == default_version:
			selected_idx = idx
		elif (
			is_installed
			and local_version.is_empty()
			and not default_version.is_empty()
			and ver == default_version
		):
			selected_idx = idx
	version_opt.set_meta("ext_info", info.duplicate(true))
	version_opt.set_meta("local_version", local_version)
	version_opt.set_meta("block_select", false)
	if version_opt.get_item_count() > 0:
		selected_idx = clampi(selected_idx, 0, version_opt.get_item_count() - 1)
		version_opt.set_meta("last_index", selected_idx)
		version_opt.select(selected_idx)
	else:
		version_opt.set_meta("last_index", 0)
	return version_opt


func _on_ext_installed_version_selected(
	_index: int,
	option: OptionButton,
	update_btn: Button,
) -> void:
	_sync_ext_update_button(update_btn, option)


func _sync_ext_update_button(update_btn: Button, option: OptionButton) -> void:
	if option.get_item_count() == 0:
		update_btn.visible = false
		return
	var local_version: String = str(option.get_meta("local_version", ""))
	var selected_version: String = _ext_option_selected_version(option)
	var can_update: bool = (
		not selected_version.is_empty()
		and selected_version != local_version
	)
	update_btn.visible = can_update
	if can_update:
		update_btn.tooltip_text = "更新至 v%s" % selected_version


func _ext_option_selected_version(option: OptionButton) -> String:
	if option.get_item_count() == 0:
		return ""
	var sel: int = option.selected
	if sel < 0 or sel >= option.get_item_count():
		return ""
	var entry: Variant = option.get_item_metadata(sel)
	if entry is Dictionary:
		return str((entry as Dictionary).get("version", "")).strip_edges()
	return ""


func _on_ext_install_pressed(option: OptionButton) -> void:
	if option.get_item_count() == 0:
		return
	_prompt_ext_version_change(option, option.selected, true)


func _on_ext_update_pressed(option: OptionButton) -> void:
	if option.get_item_count() == 0:
		return
	_prompt_ext_version_change(option, option.selected, true)


func _prompt_ext_version_change(option: OptionButton, index: int, from_action_button: bool) -> void:
	if option.get_meta("block_select", false):
		return
	if option.get_item_count() == 0:
		return
	var safe_index: int = clampi(index, 0, option.get_item_count() - 1)
	var last_index: int = int(option.get_meta("last_index", safe_index))
	if not from_action_button and safe_index == last_index:
		return
	var entry: Variant = option.get_item_metadata(safe_index)
	if entry is not Dictionary:
		_revert_supported_option(option, last_index)
		return
	var entry_dict: Dictionary = entry as Dictionary
	var target_version: String = str(entry_dict.get("version", ""))
	var local_version: String = str(option.get_meta("local_version", ""))
	if target_version.is_empty():
		_revert_supported_option(option, last_index)
		return
	if not local_version.is_empty() and target_version == local_version:
		option.set_meta("last_index", safe_index)
		return
	var info: Dictionary = option.get_meta("ext_info", {}) as Dictionary
	var supported: Dictionary = info.get("supported", {}) as Dictionary
	var ext_id: String = str(info.get("id", ""))
	var module_name: String = str(info.get("name", "")).strip_edges()
	var product_label: String = (
		"扩展「%s」" % module_name
		if not module_name.is_empty() and module_name != ext_id
		else "扩展 %s" % ext_id
	)
	var kind: String = VersionSeries.upgrade_kind(local_version, target_version, supported)
	_pending_ext_version_option = option
	_pending_ext_version_index = safe_index
	_ext_version_confirm_dialog.dialog_text = VersionSeries.confirm_dialog_text(
		kind,
		product_label,
		local_version,
		target_version,
	)
	_ext_version_confirm_dialog.set_meta("ext_id", ext_id)
	_ext_version_confirm_dialog.set_meta("target_version", target_version)
	_ext_version_confirm_dialog.set_meta("is_new_install", local_version.is_empty())
	_ext_version_confirm_dialog.popup_centered(Vector2i(520, 160))


func _on_ext_version_confirm_canceled() -> void:
	_pending_ext_version_option = null
	_pending_ext_version_index = -1


func _on_ext_version_confirm_confirmed() -> void:
	var option: OptionButton = _pending_ext_version_option
	var index: int = _pending_ext_version_index
	_pending_ext_version_option = null
	_pending_ext_version_index = -1
	if option == null or not is_instance_valid(option):
		return
	var ext_id: String = str(_ext_version_confirm_dialog.get_meta("ext_id", ""))
	var target_version: String = str(_ext_version_confirm_dialog.get_meta("target_version", ""))
	var is_new_install: bool = bool(_ext_version_confirm_dialog.get_meta("is_new_install", false))
	var download_url: String = _ext_updater.extension_download_url(
		_ext_updater.get_source(),
		ext_id,
		target_version,
	)
	if download_url.is_empty() or ext_id.is_empty():
		_revert_supported_option(option, int(option.get_meta("last_index", 0)))
		_set_dock_status("ext", "状态: %s 无法解析下载地址" % ext_id)
		return
	option.set_meta("last_index", index)
	await _apply_ext_version_install(ext_id, download_url, is_new_install)


func _apply_ext_version_install(ext_id: String, download_url: String, is_new_install: bool) -> void:
	_ensure_ext_updater()
	if not _require_editor_not_playing("ext", "安装扩展" if is_new_install else "更新扩展"):
		return
	var action_label: String = "下载" if is_new_install else "更新"
	_set_dock_status("ext", "状态: 正在%s %s..." % [action_label, ext_id])
	var ok: bool = await _ext_updater.apply_extension_update(self, download_url, ext_id)
	if ok:
		_apply_ext_facade_generate_result(_run_ext_facade_generate())
		_after_asset_tree_change(
			false,
			false,
			false,
			PackedStringArray([
				GDFrameConfig.EXT_ROOT_DIR.path_join(ext_id),
				GDFrameConfig.EXT_FACADE_MODULES_PATH,
				GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH,
				GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH,
			]),
			true,
		)
		_set_dock_status(
			"ext",
			"状态: 已%s %s" % ["安装" if is_new_install else "更新", ext_id],
		)
		_load_local_ext_index()
	else:
		var http_status: int = _ext_updater.get_last_http_status()
		if http_status >= 200 and http_status < 300:
			_set_dock_status(
				"ext",
				"状态: %s %s 失败（ZIP 内容路径不匹配，无法解压到扩展目录）" % [action_label, ext_id],
			)
		elif http_status > 0:
			_set_dock_status(
				"ext",
				"状态: %s %s 失败（%s）" % [
					action_label,
					ext_id,
					VersionSeries.format_fetch_error_hint(
						"http",
						http_status,
						_updater.get_source(),
					),
				],
			)
		else:
			_set_dock_status("ext", "状态: %s %s 失败" % [action_label, ext_id])


func _revert_supported_option(option: OptionButton, index: int) -> void:
	if option.get_item_count() == 0:
		return
	var safe_index: int = clampi(index, 0, option.get_item_count() - 1)
	option.set_meta("block_select", true)
	option.select(safe_index)
	option.set_meta("block_select", false)
	option.set_meta("last_index", safe_index)


func _on_ext_navigate_module(module_path: String) -> void:
	if _navigate_script_in_filesystem(module_path):
		_set_dock_status("ext", "状态: 已定位 %s" % module_path.get_file())
	else:
		_set_dock_status("ext", "状态: 找不到 %s" % module_path.get_file())


func _on_ext_open_module(module_path: String) -> void:
	if _open_script_in_editor(module_path):
		_set_dock_status("ext", "状态: 已打开 %s" % module_path.get_file())
	else:
		_set_dock_status("ext", "状态: 无法打开 %s" % module_path.get_file())


func _request_delete_ext(ext_dir: String, display_name: String) -> void:
	if not _require_editor_not_playing("ext", "删除扩展"):
		return
	_pending_delete_ext_dir = ext_dir
	_ext_delete_dialog.dialog_text = "确认删除扩展「%s」吗？\n将删除目录 %s 及其全部文件。" % [
		display_name,
		ext_dir,
	]
	_ext_delete_dialog.popup_centered(Vector2i(480, 150))


func _on_ext_delete_confirmed() -> void:
	if _pending_delete_ext_dir.is_empty():
		return
	var ext_dir: String = _pending_delete_ext_dir
	_pending_delete_ext_dir = ""
	_delete_ext_bundle.call_deferred(ext_dir)

func _delete_ext_bundle(ext_dir: String) -> void:
	var dir_name: String = ext_dir.get_file()
	if not _res_dir_exists(ext_dir):
		_set_dock_status("ext", "状态: 删除扩展 %s 失败" % dir_name)
		return
	if _purge_abs_dir(ProjectSettings.globalize_path(ext_dir)):
		_apply_ext_facade_generate_result(_run_ext_facade_generate())
		_after_asset_tree_change(
			false,
			false,
			false,
			PackedStringArray([
				ext_dir,
				GDFrameConfig.EXT_FACADE_MODULES_PATH,
				GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH,
				GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH,
			]),
			true,
		)
		_set_dock_status("ext", "状态: 已删除扩展 %s" % dir_name)
	else:
		_set_dock_status("ext", "状态: 删除扩展 %s 失败" % dir_name)


# =============================================================================
# Update page
# =============================================================================

func _sync_update_source_display(source: String) -> void:
	var url: String = _updater.get_plugin_index_fetch_url(source)
	if _source_option != null:
		_source_option.tooltip_text = "更新源 URL: %s" % url
	if _source_url_label != null:
		_source_url_label.text = "URL: %s" % url
		_source_url_label.tooltip_text = url

func _build_update_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title: Label = Label.new()
	title.text = "GDFrame 更新"
	panel.add_child(title)

	var version_row: HBoxContainer = HBoxContainer.new()
	version_row.add_theme_constant_override("separation", 16)
	version_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(version_row)

	_local_version_label = Label.new()
	_local_version_label.text = "当前版本: %s" % _get_local_version()
	version_row.add_child(_local_version_label)

	var supported_label: Label = Label.new()
	supported_label.text = "受支持版本"
	version_row.add_child(supported_label)

	_supported_version_unavailable = Label.new()
	_supported_version_unavailable.text = _SUPPORTED_VERSION_UNAVAILABLE_TEXT
	version_row.add_child(_supported_version_unavailable)

	_supported_version_option = OptionButton.new()
	_supported_version_option.custom_minimum_size.x = 120
	_supported_version_option.visible = false
	_supported_version_option.item_selected.connect(_on_supported_version_selected)
	version_row.add_child(_supported_version_option)
	_show_supported_version_unavailable()

	var source_row: HBoxContainer = HBoxContainer.new()
	source_row.add_theme_constant_override("separation", 8)
	source_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(source_row)

	var source_label: Label = Label.new()
	source_label.text = "更新源"
	source_row.add_child(source_label)

	_source_option = OptionButton.new()
	_source_option.add_item("GitHub", 0)
	_source_option.add_item("Gitee", 1)
	var current_source: String = _updater.get_source()
	if current_source == "gitee":
		_source_option.select(1)
	else:
		_source_option.select(0)
	_source_option.item_selected.connect(_on_source_changed)
	source_row.add_child(_source_option)

	_source_url_label = Label.new()
	_source_url_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_url_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_source_url_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_source_url_label)
	_sync_update_source_display(current_source)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	panel.add_child(buttons)

	var check_btn: Button = Button.new()
	check_btn.text = "检查更新"
	check_btn.pressed.connect(_on_check_pressed)
	buttons.add_child(check_btn)

	_update_btn = Button.new()
	_update_btn.text = "更新"
	_update_btn.disabled = true
	_update_btn.pressed.connect(_on_update_pressed)
	buttons.add_child(_update_btn)

	var reload_btn: Button = Button.new()
	reload_btn.text = "重载插件"
	reload_btn.tooltip_text = (
		"禁用再启用本插件，使 Dock 与磁盘上的 addons/gdframe 一致。"
		+ " 更新成功后会自动重载（运行中游戏时须先停止，再手动点此按钮）。"
	)
	reload_btn.pressed.connect(_on_reload_gdframe_plugin_pressed)
	buttons.add_child(reload_btn)

	var status: Label = _dock_status_label()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(status)
	_status_label = status
	_set_dock_status("update", "")
	_sync_update_button()

	return panel


func _get_local_version() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load("res://addons/gdframe/plugin.cfg")
	if err != OK:
		return "0.0.0"
	return str(cfg.get_value("plugin", "version", "0.0.0"))


func _load_local_plugin_index() -> void:
	_remote_check_seq += 1
	var check_seq: int = _remote_check_seq
	if _local_version_label != null:
		_local_version_label.text = "当前版本: %s" % _get_local_version()

	var source_str: String = _updater.get_source()
	_sync_update_source_display(source_str)

	_show_supported_version_unavailable()
	_plugin_index_info = _updater.load_local_plugin_index()
	if check_seq != _remote_check_seq:
		return
	if _plugin_index_info.has("error"):
		var err_kind: StringName = _plugin_index_info.get("error", &"")
		if err_kind == &"local_missing":
			_set_dock_status("update", "状态: 尚未检查更新，请点击「检查更新」")
		else:
			_set_dock_status("update", "状态: 本地插件版本索引无效，请点击「检查更新」")
		return
	_populate_supported_version_option(_plugin_index_info)


func _refresh_plugin_index() -> void:
	_remote_check_seq += 1
	var check_seq: int = _remote_check_seq
	_local_version_label.text = "当前版本: %s" % _get_local_version()

	var source_str: String = _updater.get_source()
	_sync_update_source_display(source_str)

	_set_dock_status("update", "状态: 正在检查更新 (%s)..." % source_str)
	_show_supported_version_unavailable()
	_plugin_index_info = await _updater.fetch_plugin_index(self, source_str)
	if check_seq != _remote_check_seq:
		return
	_populate_supported_version_option(_plugin_index_info)


func _show_supported_version_unavailable() -> void:
	if _supported_version_unavailable != null:
		_supported_version_unavailable.text = _SUPPORTED_VERSION_UNAVAILABLE_TEXT
		_supported_version_unavailable.visible = true
	if _supported_version_option != null:
		_supported_select_block = true
		_supported_version_option.clear()
		_supported_version_option.visible = false
		_supported_option_last_index = 0
		_supported_select_block = false
	_sync_update_button()


func _show_supported_version_selector() -> void:
	if _supported_version_unavailable != null:
		_supported_version_unavailable.visible = false
	if _supported_version_option != null:
		_supported_version_option.visible = true
	_sync_update_button()


func _selected_supported_entry() -> Dictionary:
	if _supported_version_option == null or not _supported_version_option.visible:
		return {}
	if _supported_version_option.get_item_count() == 0:
		return {}
	var entry: Variant = _supported_version_option.get_item_metadata(_supported_version_option.selected)
	if entry is Dictionary:
		return entry as Dictionary
	return {}


func _can_apply_selected_update(entry: Dictionary = {}) -> bool:
	if entry.is_empty():
		entry = _selected_supported_entry()
	var target_version: String = str(entry.get("version", ""))
	if target_version.is_empty():
		return false
	return target_version != _get_local_version()


func _sync_update_button() -> void:
	if _update_btn == null:
		return
	_update_btn.disabled = not _can_apply_selected_update()


func _index_for_supported_version_selection(
	entries: Array[Dictionary],
	local_version: String,
	default_version: String,
) -> int:
	if not default_version.is_empty():
		for i: int in entries.size():
			if str(entries[i].get("version", "")) == default_version:
				return i
	var local_series: String = VersionSeries.minor_series(local_version)
	if not local_series.is_empty():
		for i: int in range(entries.size() - 1, -1, -1):
			var ver: String = str(entries[i].get("version", ""))
			if VersionSeries.minor_series(ver) == local_series:
				return i
	return 0 if not entries.is_empty() else 0


func _populate_supported_version_option(plugin_index: Dictionary) -> void:
	_supported_select_block = true
	_supported_version_option.clear()
	_supported_option_last_index = 0

	if plugin_index.is_empty() or plugin_index.has("error"):
		var status: int = int(plugin_index.get("http_status", _updater.get_last_http_status()))
		var err_kind: String = String(plugin_index.get("error", "http"))
		_set_dock_status(
			"update",
			"状态: 获取失败（%s）" % VersionSeries.format_fetch_error_hint(
				err_kind,
				status,
				_updater.get_source(),
			),
		)
		_show_supported_version_unavailable()
		return

	var supported: Dictionary = plugin_index.get("supported", {})
	var local_version: String = _get_local_version()
	var resolved: Dictionary = VersionSeries.resolve_selection(
		local_version,
		supported,
		str(plugin_index.get("default_series", "")),
	)
	var default_version: String = str(resolved.get("default_version", ""))
	var entries: Array[Dictionary] = VersionSeries.sorted_supported_entries(supported)
	var listed: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if not str(entry.get("version", "")).is_empty():
			listed.append(entry)
	if listed.is_empty():
		_set_dock_status("update", "状态: 插件版本索引无受支持版本")
		_show_supported_version_unavailable()
		return

	_show_supported_version_selector()
	var selected_idx: int = _index_for_supported_version_selection(
		listed,
		local_version,
		default_version,
	)
	var pick_ver: String = str(listed[selected_idx].get("version", ""))
	var dropdown_selected: int = 0
	for entry: Dictionary in listed:
		var ver: String = str(entry.get("version", ""))
		_supported_version_option.add_item(ver)
		var idx: int = _supported_version_option.get_item_count() - 1
		_supported_version_option.set_item_metadata(idx, entry)
		if ver == pick_ver:
			dropdown_selected = idx
	_supported_version_option.select(dropdown_selected)
	_supported_option_last_index = dropdown_selected

	var selection_status: String = str(resolved.get("status", ""))
	var status_text: String = VersionSeries.status_message(
		selection_status,
		local_version,
		default_version,
	)
	if bool(plugin_index.get("cached", false)):
		var fetch_err: String = String(plugin_index.get("fetch_error", "http"))
		var http_status: int = int(plugin_index.get("http_status", 0))
		status_text += VersionSeries.format_remote_failure_suffix(
			fetch_err,
			http_status,
			_updater.get_source(),
			"本会话缓存",
		)
	if bool(plugin_index.get("local", false)):
		status_text = "%s（本地插件版本索引）" % status_text
	_set_dock_status("update", "状态: %s" % status_text)
	_supported_select_block = false
	_sync_update_button()


func _on_supported_version_selected(index: int) -> void:
	if _supported_select_block:
		return
	_supported_option_last_index = index
	_sync_update_button()


func _on_update_pressed() -> void:
	var entry: Dictionary = _selected_supported_entry()
	var target_version: String = str(entry.get("version", ""))
	if not _can_apply_selected_update(entry):
		if target_version.is_empty():
			_set_dock_status("update", "状态: 请先选择受支持版本")
		else:
			_set_dock_status("update", "状态: 所选版本与当前版本相同")
		return
	if not _require_editor_not_playing("update", "更新 GDFrame"):
		return
	var download_url: String = _updater.release_download_url(_updater.get_source(), target_version)
	_update_btn.disabled = true
	_set_dock_status("update", "状态: 下载并应用 %s 中..." % target_version)
	var ok: bool = await _updater.apply_update(self, download_url)
	if ok:
		if _editor_is_playing():
			_set_dock_status(
				"update",
				"状态: 更新完成。请先停止游戏，再点「重载插件」使界面生效。",
			)
		else:
			_reload_gdframe_plugin(1.0)
	else:
		var http_status: int = _updater.get_last_http_status()
		if http_status >= 200 and http_status < 300:
			_set_dock_status(
				"update",
				"状态: 更新失败（下载成功但 ZIP 格式或路径不匹配，Release 附件内路径须为 gdframe/...）",
			)
		elif http_status > 0:
			_set_dock_status(
				"update",
				"状态: 更新失败（%s）" % VersionSeries.format_fetch_error_hint(
					"http",
					http_status,
					_updater.get_source(),
				),
			)
		else:
			_set_dock_status(
				"update",
				"状态: 更新失败（%s）" % VersionSeries.format_fetch_error_hint("http", 0, _updater.get_source()),
			)
	_sync_update_button()


func _on_check_pressed() -> void:
	_refresh_plugin_index()


func _on_source_changed(index: int) -> void:
	_apply_update_source(index, false, false)

# =============================================================================
# Pool page
# =============================================================================

func _pool_column_docs_tooltip() -> String:
	return (
		"[对象池 — 各列含义]\n\n"
		+ "池 key\n"
		+ "  池注册名（StringName）。与 GDFrame.pool_scene、pool_get、pool_recycle 使用的 key 相同。\n\n"
		+ "idle\n"
		+ "  空闲队列长度：已创建且当前在池中、可被 pool_get 直接取走的实例数。\n\n"
		+ "active\n"
		+ "  已 pool_get 借出、尚未 pool_recycle 的实例数。\n\n"
		+ "peak\n"
		+ "  peak_active：历史 active 达到过的最大值。\n\n"
		+ "total_created\n"
		+ "  累计新建次数（含 pool_scene 第三参预热，以及空闲队列为空时 pool_get 触发的创建）。\n\n"
		+ "max_idle\n"
		+ "  归还时空闲队列允许保留的最大个数；超过则多出的实例销毁不入池。0 表示不限制。\n\n"
		+ "max_active\n"
		+ "  允许同时外借（active）的上限；达到后 pool_get 返回 null。0 表示不限制。\n\n"
		+ "get_rejects\n"
		+ "  统计字段 active_get_rejects：已达 max_active 时仍调用 pool_get 被拒的累计次数；"
		+ "仅调试器连接时递增，便于在编辑器中观察。\n\n"
		+ "[排查提示]\n\n"
		+ "若 active 长期偏高且 total_created 持续上涨，重点排查是否忘记 pool_recycle，"
		+ "或 max_active / max_idle 策略不合理。"
	)

func _build_pool_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "PoolPage"
	panel.add_theme_constant_override("separation", 6)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var filter_row: HBoxContainer = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	var filter_label: Label = Label.new()
	filter_label.text = "池 key 筛选"
	filter_row.add_child(filter_label)
	_pool_filter_edit = LineEdit.new()
	_pool_filter_edit.placeholder_text = "子串匹配，不区分大小写"
	_pool_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_filter_edit.text_changed.connect(_on_pool_key_filter_changed)
	filter_row.add_child(_pool_filter_edit)
	var pool_filter_clear_btn: Button = Button.new()
	pool_filter_clear_btn.text = "清空"
	pool_filter_clear_btn.tooltip_text = "清空筛选条件并显示全部池"
	pool_filter_clear_btn.pressed.connect(_on_pool_filter_clear_pressed)
	filter_row.add_child(pool_filter_clear_btn)
	var pool_refresh_btn: Button = Button.new()
	pool_refresh_btn.text = "刷新"
	pool_refresh_btn.tooltip_text = "向运行中的游戏请求一次对象池快照（须已 F5 运行且调试器已连接）"
	pool_refresh_btn.pressed.connect(_on_pool_refresh_pressed)
	filter_row.add_child(pool_refresh_btn)
	_pool_auto_refresh_cb = CheckButton.new()
	_pool_auto_refresh_cb.text = "自动刷新"
	_pool_auto_refresh_cb.tooltip_text = (
		"游戏运行且本页可见时，每 %.1f 秒自动向运行时请求一次对象池快照"
		% _POOL_AUTO_REFRESH_INTERVAL_SEC
	)
	_pool_auto_refresh_cb.toggled.connect(_on_pool_auto_refresh_toggled)
	filter_row.add_child(_pool_auto_refresh_cb)
	panel.add_child(filter_row)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.tooltip_text = (
		"运行游戏后点「刷新」或勾选「自动刷新」向 GDFrame 请求对象池快照。"
	)
	panel.add_child(scroll)

	_pool_tree = Tree.new()
	_pool_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pool_tree.columns = 8
	_pool_tree.column_titles_visible = true
	_pool_tree.hide_root = true
	_pool_tree.set_column_title(0, "池 key")
	_pool_tree.set_column_title(1, "idle")
	_pool_tree.set_column_title(2, "active")
	_pool_tree.set_column_title(3, "peak")
	_pool_tree.set_column_title(4, "total_created")
	_pool_tree.set_column_title(5, "max_idle")
	_pool_tree.set_column_title(6, "max_active")
	_pool_tree.set_column_title(7, "get_rejects")
	_pool_tree.set_column_expand(0, true)
	# 数值列最小宽度均以 total_created 表头文本宽度为准（idle/active/peak/max_*/get_rejects 同宽）。
	var num_col_min_w: int = 100
	var col_font: Font = _pool_tree.get_theme_font("font", "Tree") as Font
	if col_font != null:
		var col_fs: int = _pool_tree.get_theme_font_size("font_size", "Tree")
		var sz: Vector2 = col_font.get_string_size(
			"total_created", HORIZONTAL_ALIGNMENT_LEFT, -1, col_fs
		)
		num_col_min_w = int(sz.x) + 28
	num_col_min_w = maxi(num_col_min_w, 88)
	for c in range(1, 8):
		_pool_tree.set_column_expand(c, false)
		_pool_tree.set_column_custom_minimum_width(c, num_col_min_w)
	scroll.add_child(_pool_tree)

	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	var status_left_pad: Control = Control.new()
	status_left_pad.custom_minimum_size = Vector2(18, 1)
	status_row.add_child(status_left_pad)

	var base_ctrl: Control = get_editor_interface().get_base_control()
	var help_tex: Texture2D = base_ctrl.get_theme_icon(&"Help", &"EditorIcons") as Texture2D
	var pool_hint_icon: TextureRect = TextureRect.new()
	pool_hint_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	pool_hint_icon.mouse_default_cursor_shape = Control.CURSOR_HELP
	pool_hint_icon.ignore_texture_size = true
	pool_hint_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pool_hint_icon.custom_minimum_size = Vector2(22, 22)
	if help_tex != null:
		pool_hint_icon.texture = help_tex
	pool_hint_icon.tooltip_text = _pool_column_docs_tooltip()
	status_row.add_child(pool_hint_icon)

	_pool_status_label = _dock_status_label()
	status_row.add_child(_pool_status_label)
	panel.add_child(status_row)
	_set_dock_status("pool", "")

	return panel

func _on_pool_key_filter_changed(_new_text: String) -> void:
	_pool_filter_seq += 1
	var seq: int = _pool_filter_seq
	await get_tree().create_timer(_POOL_FILTER_DEBOUNCE_SEC).timeout
	if seq != _pool_filter_seq:
		return
	_refresh_pool_tree_display()

func _on_pool_filter_clear_pressed() -> void:
	if _pool_filter_edit != null:
		_pool_filter_edit.text = ""

func _on_pool_auto_refresh_toggled(_on: bool) -> void:
	_sync_pool_auto_refresh_timer()

func _on_pool_auto_refresh_timeout() -> void:
	if _pool_auto_refresh_cb == null or not _pool_auto_refresh_cb.button_pressed:
		return
	if not _pool_page_visible:
		_sync_pool_auto_refresh_timer()
		return
	if not _editor_is_playing():
		_sync_pool_auto_refresh_timer()
		return
	_request_pool_stats(false)

func _sync_pool_auto_refresh_timer() -> void:
	if _pool_auto_refresh_timer == null:
		return
	var want_auto: bool = (
		_pool_auto_refresh_cb != null
		and _pool_auto_refresh_cb.button_pressed
		and _pool_page_visible
	)
	if not want_auto:
		_pool_auto_refresh_timer.stop()
		return
	if _editor_is_playing():
		_pool_auto_refresh_timer.wait_time = 0.1
		if _pool_auto_refresh_timer.is_stopped():
			_request_pool_stats(false)
	else:
		_pool_auto_refresh_timer.wait_time = 0.5
	_pool_auto_refresh_timer.start()

func _request_pool_stats(show_errors: bool = false) -> bool:
	if not _editor_is_playing():
		if show_errors:
			_set_dock_status("pool", "请先运行游戏（F5）。")
		return false
	if _pool_debug_plugin == null:
		if show_errors:
			_set_dock_status("pool", "调试插件未就绪。")
		return false
	if not _pool_debug_plugin.request_pool_stats():
		if show_errors:
			_set_dock_status("pool", "调试器未连接，请先 F5 运行。")
		return false
	return true

func _on_pool_refresh_pressed() -> void:
	_request_pool_stats(true)

func _refresh_pool_tree_display() -> void:
	if _pool_tree == null:
		return
	var stats: Dictionary = _pool_last_stats
	if stats.is_empty():
		_pool_tree.clear()
		_set_dock_status("pool","尚未收到运行时数据。")
		return
	_pool_tree.clear()
	var root: TreeItem = _pool_tree.create_item()
	var keys: Array = stats.keys()
	keys.sort()
	var filter_raw: String = ""
	if _pool_filter_edit != null:
		filter_raw = _pool_filter_edit.text.strip_edges()
	var filter_lower: String = filter_raw.to_lower()
	var keys_visible: Array = []
	if filter_lower.is_empty():
		keys_visible = keys.duplicate()
	else:
		for kk: Variant in keys:
			if String(kk).to_lower().contains(filter_lower):
				keys_visible.append(kk)
	var sum_idle: int = 0
	var sum_active: int = 0
	var sum_created: int = 0
	var sum_rejects: int = 0
	for k: Variant in keys_visible:
		var row: Variant = stats[k]
		if row is not Dictionary:
			continue
		var d: Dictionary = row as Dictionary
		var it: TreeItem = _pool_tree.create_item(root)
		it.set_text(0, str(k))
		var idle_v: int = int(d.get("idle", 0))
		var active_v: int = int(d.get("active", 0))
		var peak_v: int = int(d.get("peak_active", 0))
		var total_v: int = int(d.get("total_created", 0))
		var max_idle_v: int = int(d.get("max_idle", 0))
		var max_active_v: int = int(d.get("max_active", 0))
		var rejects_v: int = int(d.get("active_get_rejects", 0))
		it.set_text(1, str(idle_v))
		it.set_text(2, str(active_v))
		it.set_text(3, str(peak_v))
		it.set_text(4, str(total_v))
		it.set_text(5, str(max_idle_v))
		it.set_text(6, str(max_active_v))
		it.set_text(7, str(rejects_v))
		sum_idle += idle_v
		sum_active += active_v
		sum_created += total_v
		sum_rejects += rejects_v
		if max_active_v > 0 and active_v >= max_active_v:
			it.set_custom_color(2, Color(1.0, 0.65, 0.2))
		elif active_v > 0 and max_active_v == 0:
			it.set_custom_color(2, Color(0.75, 0.75, 0.85))
		if rejects_v > 0:
			it.set_custom_color(7, Color(1.0, 0.45, 0.35))

	var t: Dictionary = Time.get_datetime_dict_from_system()
	var shown: int = keys_visible.size()
	var total: int = keys.size()
	_set_dock_status("pool",
		"快照 %02d:%02d:%02d  |  显示 %d/%d 池  |  Σ idle=%d  active=%d  total_created=%d  get_rejects=%d"
		% [
			int(t.get("hour", 0)),
			int(t.get("minute", 0)),
			int(t.get("second", 0)),
			shown,
			total,
			sum_idle,
			sum_active,
			sum_created,
			sum_rejects,
		]
	)

func _on_runtime_pool_stats(stats: Dictionary) -> void:
	_pool_last_stats = stats.duplicate()
	_refresh_pool_tree_display()

# =============================================================================
# FSM page
# =============================================================================

func _build_fsm_page() -> Control:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var create_row: HBoxContainer = HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 6)
	panel.add_child(create_row)

	var new_lbl: Label = Label.new()
	new_lbl.text = "新建状态机"
	create_row.add_child(new_lbl)

	_fsm_name_edit = LineEdit.new()
	_fsm_name_edit.placeholder_text = "player → fsm_player.gd"
	_fsm_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_fsm_name_edit)

	var create_btn: Button = Button.new()
	create_btn.text = "创建"
	create_btn.tooltip_text = "生成 registry 与 states 目录；状态请用「添加状态」创建"
	create_btn.pressed.connect(_on_create_fsm_pressed)
	create_row.add_child(create_btn)

	_fsm_status_label = _dock_status_label()
	panel.add_child(_fsm_status_label)

	var pick_row: HBoxContainer = HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 6)
	panel.add_child(pick_row)

	_fsm_machine_option = OptionButton.new()
	_fsm_machine_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fsm_machine_option.tooltip_text = "当前编辑的状态机"
	_fsm_machine_option.item_selected.connect(_on_fsm_machine_selected)
	pick_row.add_child(_fsm_machine_option)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "刷新"
	refresh_btn.tooltip_text = "重新扫描列表"
	refresh_btn.pressed.connect(_refresh_fsm_ui)
	pick_row.add_child(refresh_btn)

	_fsm_delete_machine_btn = Button.new()
	_fsm_delete_machine_btn.text = "删除状态机"
	_fsm_delete_machine_btn.tooltip_text = "删除整个 fsm_xxx 目录"
	_fsm_delete_machine_btn.pressed.connect(_on_fsm_delete_machine_requested)
	pick_row.add_child(_fsm_delete_machine_btn)

	var rename_machine_btn: Button = Button.new()
	rename_machine_btn.text = "更名"
	rename_machine_btn.tooltip_text = "重命名状态机目录、registry 与 states 脚本"
	rename_machine_btn.pressed.connect(_on_fsm_rename_machine_requested)
	pick_row.add_child(rename_machine_btn)

	_fsm_delete_machine_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_fsm_delete_machine_dialog)
	_fsm_delete_machine_dialog.title = "确认删除状态机"
	_fsm_delete_machine_dialog.ok_button_text = "删除"
	_fsm_delete_machine_dialog.confirmed.connect(_on_fsm_delete_machine_confirmed)
	panel.add_child(_fsm_delete_machine_dialog)

	_fsm_delete_state_dialog = ConfirmationDialog.new()
	_configure_plugin_modal_dialog(_fsm_delete_state_dialog)
	_fsm_delete_state_dialog.title = "确认删除状态"
	_fsm_delete_state_dialog.ok_button_text = "删除"
	_fsm_delete_state_dialog.confirmed.connect(_on_fsm_delete_state_confirmed)
	panel.add_child(_fsm_delete_state_dialog)

	_rename_fsm_machine_dialog = AcceptDialog.new()
	_configure_plugin_modal_dialog(_rename_fsm_machine_dialog)
	_rename_fsm_machine_dialog.title = "重命名状态机"
	_rename_fsm_machine_dialog.min_size = Vector2i(420, 120)
	_rename_fsm_machine_dialog.confirmed.connect(_on_rename_fsm_machine_confirmed)
	panel.add_child(_rename_fsm_machine_dialog)
	var rename_machine_builtin: Label = _rename_fsm_machine_dialog.get_label()
	if rename_machine_builtin != null:
		rename_machine_builtin.hide()
	var rename_machine_box: VBoxContainer = VBoxContainer.new()
	rename_machine_box.add_theme_constant_override("separation", 10)
	rename_machine_box.custom_minimum_size = Vector2(380, 0)
	_rename_fsm_machine_dialog.add_child(rename_machine_box)
	_rename_fsm_machine_target_label = Label.new()
	_rename_fsm_machine_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_machine_box.add_child(_rename_fsm_machine_target_label)
	_rename_fsm_machine_name_edit = LineEdit.new()
	_rename_fsm_machine_name_edit.placeholder_text = "player → fsm_player"
	_rename_fsm_machine_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_machine_box.add_child(_rename_fsm_machine_name_edit)

	_rename_fsm_state_dialog = AcceptDialog.new()
	_configure_plugin_modal_dialog(_rename_fsm_state_dialog)
	_rename_fsm_state_dialog.title = "重命名状态"
	_rename_fsm_state_dialog.min_size = Vector2i(420, 120)
	_rename_fsm_state_dialog.confirmed.connect(_on_rename_fsm_state_confirmed)
	panel.add_child(_rename_fsm_state_dialog)
	var rename_state_builtin: Label = _rename_fsm_state_dialog.get_label()
	if rename_state_builtin != null:
		rename_state_builtin.hide()
	var rename_state_box: VBoxContainer = VBoxContainer.new()
	rename_state_box.add_theme_constant_override("separation", 10)
	rename_state_box.custom_minimum_size = Vector2(380, 0)
	_rename_fsm_state_dialog.add_child(rename_state_box)
	_rename_fsm_state_target_label = Label.new()
	_rename_fsm_state_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_state_box.add_child(_rename_fsm_state_target_label)
	_rename_fsm_state_name_edit = LineEdit.new()
	_rename_fsm_state_name_edit.placeholder_text = "idle → idle.gd"
	_rename_fsm_state_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_state_box.add_child(_rename_fsm_state_name_edit)

	var add_row: HBoxContainer = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	panel.add_child(add_row)

	var list_lbl: Label = Label.new()
	list_lbl.text = "添加状态"
	add_row.add_child(list_lbl)

	_fsm_new_state_edit = LineEdit.new()
	_fsm_new_state_edit.placeholder_text = "idle → idle.gd"
	_fsm_new_state_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_fsm_new_state_edit)

	var add_btn: Button = Button.new()
	add_btn.text = "添加状态"
	add_btn.tooltip_text = "生成 states 脚本并更新 registry"
	add_btn.pressed.connect(_on_fsm_add_state_pressed)
	add_row.add_child(add_btn)

	var states_scroll: ScrollContainer = ScrollContainer.new()
	states_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	states_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	states_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(states_scroll)

	_fsm_states_rows = VBoxContainer.new()
	_fsm_states_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fsm_states_rows.add_theme_constant_override("separation", 2)
	states_scroll.add_child(_fsm_states_rows)

	_set_dock_status("fsm", "")
	return panel

func _fsm_registry_path(fsm_id: String) -> String:
	return "%s/%s/%s_registry.gd" % [GDFrameConfig.FSM_ROOT, fsm_id, fsm_id]

func _load_fsm_registry(fsm_id: String) -> GDFrameFsmRegistryBase:
	var reg_path: Variant = _fsm_registry_path(fsm_id)
	if not FileAccess.file_exists(reg_path):
		return null
	# Dock 频繁改写 registry；须 IGNORE，否则仍可能读到旧 Script 的 state_keys。
	var scr: Script = ResourceLoader.load(
		reg_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as Script
	if scr == null:
		return null
	var reg_obj: Object = scr.new()
	if reg_obj is GDFrameFsmRegistryBase:
		return reg_obj as GDFrameFsmRegistryBase
	return null

func _collect_fsm_ids() -> Array[String]:
	var out: Array[String] = []
	for reg_path: String in _get_fsm_registry_paths():
		out.append(reg_path.get_file().get_basename().trim_suffix("_registry"))
	return out

func _fsm_selected_id() -> String:
	if _fsm_machine_option == null:
		return ""
	var idx: int = _fsm_machine_option.selected
	if idx < 0 or idx >= _fsm_machine_option.item_count:
		return ""
	var text: String = _fsm_machine_option.get_item_text(idx)
	if text.begins_with("("):
		return ""
	return text

func _refresh_fsm_ui() -> void:
	_refresh_fsm_machine_option()
	_fsm_refresh_states_list()

func _refresh_fsm_machine_option() -> void:
	if _fsm_machine_option == null:
		return
	_fsm_machine_option.clear()
	var ids: Variant = _collect_fsm_ids()
	for id in ids:
		_fsm_machine_option.add_item(id)
	if ids.is_empty():
		_fsm_machine_option.add_item("(暂无)")
		_fsm_machine_option.set_item_disabled(0, true)
	else:
		_fsm_machine_option.select(0)
	_on_fsm_machine_selected(_fsm_machine_option.selected)

func _on_fsm_machine_selected(_index: int) -> void:
	var sid: Variant = _fsm_selected_id()
	if sid.is_empty():
		_set_dock_status("fsm","就绪")
	else:
		_set_dock_status("fsm",sid)
	_fsm_refresh_states_list()

func _fsm_refresh_states_list() -> void:
	if _fsm_states_rows == null:
		return
	for child in _fsm_states_rows.get_children():
		child.queue_free()
	var sid: Variant = _fsm_selected_id()
	if sid.is_empty():
		return
	var keys: Variant = _get_fsm_state_keys(sid)
	if keys.is_empty():
		var warn: Label = Label.new()
		warn.text = "尚未创建任何状态，请在上方输入名称后点击「添加状态」。"
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2))
		_fsm_states_rows.add_child(warn)
		return

	var row_i: int = 0
	for st in keys:
		var actions: Array = [
			{
				"text": "定位",
				"tip": "在文件系统 Dock 中选中该脚本",
				"callback": _on_fsm_navigate_state_in_filesystem.bind(sid, st),
			},
			{
				"text": "打开",
				"tip": "在脚本编辑器中打开",
				"callback": _on_fsm_open_state_script.bind(sid, st),
			},
			{
				"text": "更名",
				"tip": "重命名状态脚本并更新 registry",
				"callback": _on_fsm_rename_state_requested.bind(sid, st),
			},
			{
				"text": "删除",
				"tip": "删除此状态脚本并刷新 registry",
				"callback": _on_fsm_delete_state_requested.bind(sid, st),
			},
		]
		_fsm_states_rows.add_child(
			_build_dock_asset_row(
				row_i,
				st,
				"%s/%s/states/%s.gd" % [GDFrameConfig.FSM_ROOT, sid, st],
				actions,
			)
		)
		row_i += 1

func _on_create_fsm_pressed() -> void:
	if not _require_editor_not_playing("fsm", "创建状态机"):
		return
	var raw: String = _fsm_name_edit.text.strip_edges()
	if raw.is_empty():
		_set_dock_status("fsm","请输入状态机名称")
		return
	var id: Variant = AssetNameUtil.normalize_fsm_name(raw)
	var dir_path: String = "%s/%s" % [GDFrameConfig.FSM_ROOT, id]
	var reg_path: String = "%s/%s_registry.gd" % [dir_path, id]
	var states_dir: String = "%s/states" % dir_path
	var dir_err: Error = _ensure_res_dir(states_dir)
	if dir_err != OK:
		_set_dock_status("fsm", "无法创建目录（错误 %s）" % dir_err)
		return

	if _res_file_exists(reg_path):
		_set_dock_status("fsm","已存在 %s" % id)
		return

	var states: Array[String] = []
	if not _write_fsm_registry_file(id, states):
		_set_dock_status("fsm","创建 registry 失败")
		return
	_set_dock_status("fsm","已创建 %s（请添加状态）" % id)
	_after_asset_tree_change(false, true, false, PackedStringArray([reg_path]))
	_select_fsm_option_by_id(id)
	_fsm_name_edit.text = ""

func _select_fsm_option_by_id(id: String) -> void:
	if _fsm_machine_option == null:
		return
	for i in range(_fsm_machine_option.item_count):
		if _fsm_machine_option.get_item_text(i) == id:
			_fsm_machine_option.select(i)
			_on_fsm_machine_selected(i)
			break

func _on_fsm_add_state_pressed() -> void:
	if not _require_editor_not_playing("fsm", "添加状态"):
		return
	var sid: Variant = _fsm_selected_id()
	if sid.is_empty():
		_set_dock_status("fsm","请先选择状态机")
		return
	var key: Variant = AssetNameUtil.clean_alnum_underscore(_fsm_new_state_edit.text.strip_edges())
	if key.is_empty():
		_set_dock_status("fsm","请输入合法状态名")
		return
	_asset_scan_fsm_states.erase(sid)
	var states: Array[String] = _collect_fsm_state_keys(sid).duplicate()
	if key in states:
		_set_dock_status("fsm","已存在 %s" % key)
		return
	states.append(key)
	states.sort()
	if not _write_state_script_if_missing(sid, key):
		_set_dock_status("fsm","创建状态脚本失败")
		return
	var reg_path: Variant = _fsm_registry_path(sid)
	var script_path: Variant = _fsm_state_script_path(sid, key)
	if not _write_fsm_registry_file(sid, states):
		_set_dock_status("fsm","写入 registry 失败")
		return
	_fsm_new_state_edit.text = ""
	_set_dock_status("fsm","已添加 %s" % key)
	var states_dir: String = script_path.get_base_dir()
	_after_asset_tree_change(
		false,
		false,
		true,
		PackedStringArray([reg_path, script_path, states_dir]),
	)

func _collect_fsm_state_keys(fsm_id: String) -> Array[String]:
	var reg: GDFrameFsmRegistryBase = _load_fsm_registry(fsm_id)
	if reg == null:
		return []
	var out: Array[String] = []
	for k: StringName in reg.state_keys():
		out.append(String(k))
	out.sort()
	return out

func _fsm_state_script_path(sid: String, st: String) -> String:
	return "%s/%s/states/%s.gd" % [GDFrameConfig.FSM_ROOT, sid, st]

func _build_fsm_state_template() -> String:
	return """extends \"%s\"


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
""" % FSM_STATE_SCRIPT_PATH

func _build_fsm_registry_gd(fsm_id: String, states: Array[String]) -> String:
	var match_lines: PackedStringArray = PackedStringArray()
	for st in states:
		var script_res: String = "%s/%s/states/%s.gd" % [GDFrameConfig.FSM_ROOT, fsm_id, st]
		match_lines.append("\t\t&\"%s\":" % st)
		match_lines.append("\t\t\treturn preload(\"%s\") as Script" % script_res)
	var keys_parts: PackedStringArray = PackedStringArray()
	for st in states:
		keys_parts.append("&\"%s\"" % st)
	var keys_inner: String = ", ".join(keys_parts)
	return """## Auto-generated by GDFrame — 由 Dock 维护，勿手改 state_script 的 match（除非你知道后果）。
extends \"%s\"


func machine_id() -> StringName:
	return &\"%s\"


func state_keys() -> Array[StringName]:
	return [%s]


func state_script(state_key: StringName) -> Script:
	match state_key:
%s
		_:
			return null
""" % [
		FSM_REGISTRY_SCRIPT_PATH,
		fsm_id,
		keys_inner,
		"\n".join(match_lines),
	]

func _write_fsm_registry_file(fsm_id: String, states: Array[String]) -> bool:
	var path: String = "%s/%s/%s_registry.gd" % [GDFrameConfig.FSM_ROOT, fsm_id, fsm_id]
	if _write_res_text(path, _build_fsm_registry_gd(fsm_id, states)) != OK:
		return false
	_asset_scan_fsm_states[fsm_id] = states.duplicate()
	return true

func _write_state_script_if_missing(fsm_id: String, state_key: String) -> bool:
	var script_path: Variant = _fsm_state_script_path(fsm_id, state_key)
	if _res_file_exists(script_path):
		return true
	var states_dir: String = "%s/%s/states" % [GDFrameConfig.FSM_ROOT, fsm_id]
	if _ensure_res_dir(states_dir) != OK:
		return false
	return _write_res_text(script_path, _build_fsm_state_template()) == OK

func _write_gd_file_with_uid(path: String, text: String, uid_source_path: String) -> bool:
	if _write_res_text(path, text) != OK:
		return false
	var uid: Variant = _read_resource_uid("%s.uid" % uid_source_path)
	if uid.is_empty():
		return true
	return _write_res_text("%s.uid" % path, uid + "\n") == OK

func _on_fsm_navigate_state_in_filesystem(sid: String, st: String) -> void:
	var path: Variant = _fsm_state_script_path(sid, st)
	if _navigate_script_in_filesystem(path):
		_set_dock_status("fsm","已定位 %s" % st)
	else:
		_set_dock_status("fsm","未找到脚本")

func _on_fsm_open_state_script(sid: String, st: String) -> void:
	var path: Variant = _fsm_state_script_path(sid, st)
	if _open_script_in_editor(path):
		_set_dock_status("fsm","已打开 %s" % st)
	else:
		_set_dock_status("fsm","未找到或无法打开脚本")

func _on_fsm_rename_machine_requested() -> void:
	if not _require_editor_not_playing("fsm", "重命名状态机"):
		return
	var sid: Variant = _fsm_selected_id()
	if sid.is_empty():
		_set_dock_status("fsm","没有可重命名的状态机")
		return
	_pending_rename_fsm_id = sid
	_rename_fsm_machine_name_edit.text = ""
	_rename_fsm_machine_target_label.text = "将 %s 重命名为：" % sid
	_rename_fsm_machine_dialog.popup_centered(Vector2i(420, 120))
	_rename_fsm_machine_name_edit.grab_focus()

func _on_rename_fsm_machine_confirmed() -> void:
	if _pending_rename_fsm_id.is_empty():
		return
	var raw_name: String = _rename_fsm_machine_name_edit.text.strip_edges()
	if raw_name.is_empty():
		_set_dock_status("fsm","请输入新状态机名称")
		return
	var old_id: Variant = _pending_rename_fsm_id
	_pending_rename_fsm_id = ""
	_rename_fsm_machine_bundle.call_deferred(old_id, raw_name)

func _rename_fsm_machine_bundle(old_id: String, raw_new_name: String) -> void:
	var new_id: Variant = AssetNameUtil.normalize_fsm_name(raw_new_name)
	if new_id == old_id:
		_set_dock_status("fsm","名称未变化")
		return
	var old_reg: Variant = _fsm_registry_path(old_id)
	if not FileAccess.file_exists(old_reg):
		_set_dock_status("fsm","源 registry 缺失，无法重命名")
		return
	var new_dir: String = "%s/%s" % [GDFrameConfig.FSM_ROOT, new_id]
	if _res_dir_exists(new_dir):
		_set_dock_status("fsm","目标已存在 %s" % new_id)
		return

	var states: Variant = _get_fsm_state_keys(old_id)
	var states_dir: String = "%s/states" % new_dir
	var dir_err: Variant = _ensure_res_dir(states_dir)
	if dir_err != OK:
		_set_dock_status("fsm","无法创建目录 %s（错误 %s）" % [new_dir, dir_err])
		return

	for st in states:
		var old_script: Variant = _fsm_state_script_path(old_id, st)
		var new_script: Variant = _fsm_state_script_path(new_id, st)
		if not FileAccess.file_exists(old_script):
			_set_dock_status("fsm","源状态脚本缺失：%s" % st)
			_try_remove_empty_dir(states_dir, GDFrameConfig.FSM_ROOT)
			_try_remove_empty_dir(new_dir, GDFrameConfig.FSM_ROOT)
			return
		var script_text: String = FileAccess.get_file_as_string(old_script)
		script_text = _replace_gdframe_constants_refs(script_text, old_id, new_id)
		if not _write_gd_file_with_uid(new_script, script_text, old_script):
			_set_dock_status("fsm","无法写入状态脚本 %s" % st)
			_try_remove_empty_dir(states_dir, GDFrameConfig.FSM_ROOT)
			_try_remove_empty_dir(new_dir, GDFrameConfig.FSM_ROOT)
			return

	if not _write_fsm_registry_file(new_id, states):
		_set_dock_status("fsm","写入 registry 失败")
		_try_remove_empty_dir(states_dir, GDFrameConfig.FSM_ROOT)
		_try_remove_empty_dir(new_dir, GDFrameConfig.FSM_ROOT)
		return
	var new_reg: Variant = _fsm_registry_path(new_id)
	var old_reg_uid: Variant = _read_resource_uid("%s.uid" % old_reg)
	if not old_reg_uid.is_empty():
		var uid_file: FileAccess = FileAccess.open("%s.uid" % new_reg, FileAccess.WRITE)
		if uid_file != null:
			uid_file.store_string(old_reg_uid + "\n")
			uid_file = null

	_delete_fsm_machine_bundle(old_id, false)

	_after_asset_tree_change(false, true)
	_select_fsm_option_by_id(new_id)
	_set_dock_status("fsm","已重命名 %s → %s" % [old_id, new_id])

func _on_fsm_rename_state_requested(sid: String, st: String) -> void:
	if not _require_editor_not_playing("fsm", "重命名状态"):
		return
	if sid.is_empty():
		_set_dock_status("fsm","请先选择状态机")
		return
	_pending_rename_state_sid = sid
	_pending_rename_state_key = st
	_rename_fsm_state_name_edit.text = ""
	_rename_fsm_state_target_label.text = "将状态「%s」重命名为：" % st
	_rename_fsm_state_dialog.popup_centered(Vector2i(420, 120))
	_rename_fsm_state_name_edit.grab_focus()

func _on_rename_fsm_state_confirmed() -> void:
	if _pending_rename_state_sid.is_empty() or _pending_rename_state_key.is_empty():
		return
	var raw_name: String = _rename_fsm_state_name_edit.text.strip_edges()
	if raw_name.is_empty():
		_set_dock_status("fsm","请输入新状态名")
		return
	var sid: Variant = _pending_rename_state_sid
	var old_key: Variant = _pending_rename_state_key
	_pending_rename_state_sid = ""
	_pending_rename_state_key = ""
	_rename_fsm_state_bundle.call_deferred(sid, old_key, raw_name)

func _rename_fsm_state_bundle(sid: String, old_key: String, raw_new_key: String) -> void:
	var new_key: Variant = AssetNameUtil.clean_alnum_underscore(raw_new_key)
	if new_key.is_empty():
		_set_dock_status("fsm","请输入合法状态名")
		return
	if new_key == old_key:
		_set_dock_status("fsm","名称未变化")
		return
	var old_script: Variant = _fsm_state_script_path(sid, old_key)
	var new_script: Variant = _fsm_state_script_path(sid, new_key)
	if FileAccess.file_exists(new_script):
		_set_dock_status("fsm","目标已存在 %s" % new_key)
		return
	if not FileAccess.file_exists(old_script):
		_set_dock_status("fsm","源状态脚本缺失，无法重命名")
		return

	var script_text: String = FileAccess.get_file_as_string(old_script)
	script_text = _replace_gdframe_constants_refs(script_text, old_key, new_key)
	if not _write_gd_file_with_uid(new_script, script_text, old_script):
		_set_dock_status("fsm","无法写入状态脚本 %s" % new_key)
		return

	_asset_scan_fsm_states.erase(sid)
	var states: Array[String] = _collect_fsm_state_keys(sid).duplicate()
	if old_key in states:
		states.erase(old_key)
	if not new_key in states:
		states.append(new_key)
	states.sort()
	if not _write_fsm_registry_file(sid, states):
		_set_dock_status("fsm","更新 registry 失败")
		_safe_delete("%s.uid" % new_script)
		_safe_delete(new_script)
		return

	for st in states:
		var script_path: Variant = _fsm_state_script_path(sid, st)
		if not FileAccess.file_exists(script_path):
			continue
		var existing: String = FileAccess.get_file_as_string(script_path)
		var updated: Variant = _replace_gdframe_constants_refs(existing, old_key, new_key)
		if updated == existing:
			continue
		var patch_file: FileAccess = FileAccess.open(script_path, FileAccess.WRITE)
		if patch_file == null:
			_set_dock_status("fsm","更新引用失败：%s" % st)
			return
		patch_file.store_string(updated)
		patch_file = null

	_safe_delete("%s.uid" % old_script)
	_safe_delete(old_script)

	_after_asset_tree_change(false, false, true)
	_set_dock_status("fsm","已重命名状态 %s → %s" % [old_key, new_key])

func _on_fsm_delete_state_requested(sid: String, st: String) -> void:
	if not _require_editor_not_playing("fsm", "删除状态"):
		return
	if sid.is_empty():
		_set_dock_status("fsm","请先选择状态机")
		return
	_pending_delete_state_sid = sid
	_pending_delete_state_key = st
	_fsm_delete_state_dialog.dialog_text = "确认删除状态「%s」吗？\n将删除对应脚本并更新 registry。" % st
	_fsm_delete_state_dialog.popup_centered(Vector2i(420, 140))

func _on_fsm_delete_state_confirmed() -> void:
	var sid: Variant = _pending_delete_state_sid
	var key: Variant = _pending_delete_state_key
	_pending_delete_state_sid = ""
	_pending_delete_state_key = ""
	if sid.is_empty() or key.is_empty():
		return
	_delete_fsm_state_bundle.call_deferred(sid, key)

func _delete_fsm_state_bundle(sid: String, key: String) -> void:
	_asset_scan_fsm_states.erase(sid)
	var states: Array[String] = _collect_fsm_state_keys(sid).duplicate()
	if not key in states:
		_set_dock_status("fsm","磁盘上无此状态")
		return
	states.erase(key)
	states.sort()
	var script_path: Variant = _fsm_state_script_path(sid, key)
	var reg_path: Variant = _fsm_registry_path(sid)
	_safe_delete("%s.uid" % script_path)
	_safe_delete(script_path)
	if not _write_fsm_registry_file(sid, states):
		_set_dock_status("fsm","删除文件后重写 registry 失败")
		return
	_set_dock_status("fsm","已删除状态 %s" % key)
	_after_asset_tree_change(false, false, true, PackedStringArray([reg_path, script_path]))

func _on_fsm_delete_machine_requested() -> void:
	if not _require_editor_not_playing("fsm", "删除状态机"):
		return
	var sid: Variant = _fsm_selected_id()
	if sid.is_empty():
		_set_dock_status("fsm","没有可删除的状态机")
		return
	_pending_delete_fsm_id = sid
	_fsm_delete_machine_dialog.dialog_text = "确认删除状态机 %s 吗？\n将删除 registry、states 下全部脚本及目录（不可恢复）。" % sid
	_fsm_delete_machine_dialog.popup_centered(Vector2i(480, 160))

func _on_fsm_delete_machine_confirmed() -> void:
	if _pending_delete_fsm_id.is_empty():
		return
	var fsm_id: String = _pending_delete_fsm_id
	_pending_delete_fsm_id = ""
	_delete_fsm_machine_bundle.call_deferred(fsm_id)

func _delete_fsm_machine_bundle(fsm_id: String, refresh_registry: bool = true) -> void:
	if fsm_id.is_empty():
		return
	var machine_dir: String = "%s/%s" % [GDFrameConfig.FSM_ROOT, fsm_id]
	_asset_scan_fsm_states.erase(fsm_id)
	var deleted_any: bool = false
	if _res_dir_exists(machine_dir):
		deleted_any = _purge_abs_dir(ProjectSettings.globalize_path(machine_dir))
	else:
		for st: String in _collect_fsm_state_keys(fsm_id):
			var sp: String = _fsm_state_script_path(fsm_id, st)
			deleted_any = _safe_delete("%s.uid" % sp) or deleted_any
			deleted_any = _safe_delete(sp) or deleted_any
		var reg: String = _fsm_registry_path(fsm_id)
		deleted_any = _safe_delete("%s.uid" % reg) or deleted_any
		deleted_any = _safe_delete(reg) or deleted_any
	if refresh_registry:
		_after_asset_tree_change(false, true, false, PackedStringArray([machine_dir]))
	if deleted_any:
		if refresh_registry:
			_set_dock_status("fsm", "已删除状态机 %s" % fsm_id)
	else:
		if refresh_registry:
			_set_dock_status("fsm", "未删除任何文件（可能已不存在）")

# =============================================================================
# Constants generation
# =============================================================================

func _gdc_const_identifier(id: String) -> String:
	if id.is_valid_identifier() and not id.begins_with("_"):
		return id.to_upper()
	return ("state_%s" % id).to_upper()

func _replace_gdframe_constants_refs(
	source: String,
	old_id: String,
	new_id: String,
	replace_raw_const_name: bool = false,
) -> String:
	var old_const: String = _gdc_const_identifier(old_id)
	var new_const: String = _gdc_const_identifier(new_id)
	var result: String = source.replace(
		"GDFrameConstants.%s" % old_const, "GDFrameConstants.%s" % new_const
	)
	result = result.replace("&\"%s\"" % old_id, "&\"%s\"" % new_id)
	if replace_raw_const_name and old_const != new_const:
		result = result.replace(old_const, new_const)
	return result


func _ensure_contract_root_dir() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(GDFrameConfig.PROJECT_CONTRACT_ROOT)
	)


func _ensure_generated_dir() -> void:
	_ensure_contract_root_dir()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(GDFrameConfig.GENERATED_DIR)
	)

func _signals_script_template() -> String:
	var raw: Variant = _call_editor_gen(SignalsGen, &"skeleton_template", "signals_gen.gd")
	if raw is String:
		return raw
	return ""

func _ensure_signals_script(sync_filesystem: bool = true) -> void:
	if _res_file_exists(GDFrameConfig.SIGNALS_SCRIPT_PATH):
		return
	_ensure_generated_dir()
	if _write_res_text(GDFrameConfig.SIGNALS_SCRIPT_PATH, _signals_script_template()) != OK:
		push_error("GDFrame: 无法写入 %s" % GDFrameConfig.SIGNALS_SCRIPT_PATH)
		return
	if sync_filesystem:
		_update_editor_filesystem(GDFrameConfig.SIGNALS_SCRIPT_PATH)

func _profile_settings_script_template() -> String:
	var raw: Variant = _call_editor_gen(
		ProfileSettingsGen,
		&"skeleton_template",
		"profile_settings_gen.gd",
	)
	if raw is String:
		return raw
	return ""

func _ensure_profile_settings_script(sync_filesystem: bool = true) -> void:
	if _res_file_exists(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH):
		return
	_ensure_res_dir(GDFrameConfig.PROJECT_CONTRACT_ROOT)
	if _write_res_text(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH, _profile_settings_script_template()) != OK:
		push_error("GDFrame: 无法写入 %s" % GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH)
		return
	if sync_filesystem:
		_update_editor_filesystem(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH)


func _is_dim_script_scaffold(content: String) -> bool:
	if content.is_empty():
		return false
	if not content.contains("extends Control"):
		return false
	if not content.contains("func on_dim_show"):
		return false
	if not content.contains("func on_dim_hide"):
		return false
	return true


func _dim_script_template() -> String:
	return (
		"## UI 全屏遮罩（契约场景根脚本）；可改场景节点或在此写逻辑。\n"
		+ "## 框架在显隐时会调用 on_dim_show / on_dim_hide。\n"
		+ "extends Control\n\n\n"
		+ "# func on_dim_show(ui_id: StringName) -> void:\n\n\n"
		+ "# func on_dim_hide() -> void:\n"
	)


func _dim_scene_template() -> String:
	return (
		"[gd_scene load_steps=2 format=3]\n\n"
		+ "[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n\n"
		+ "[node name=\"dim\" type=\"Control\"]\n"
		+ "layout_mode = 3\n"
		+ "anchors_preset = 15\n"
		+ "anchor_right = 1.0\n"
		+ "anchor_bottom = 1.0\n"
		+ "grow_horizontal = 2\n"
		+ "grow_vertical = 2\n"
		+ "mouse_filter = 0\n"
		+ "script = ExtResource(\"1\")\n\n"
		+ "[node name=\"Background\" type=\"ColorRect\" parent=\".\"]\n"
		+ "layout_mode = 1\n"
		+ "anchors_preset = 15\n"
		+ "anchor_right = 1.0\n"
		+ "anchor_bottom = 1.0\n"
		+ "grow_horizontal = 2\n"
		+ "grow_vertical = 2\n"
		+ "mouse_filter = 2\n"
		+ "color = Color(0, 0, 0, 0.55)\n"
	) % GDFrameConfig.DIM_SCRIPT_PATH


func _ensure_contract_dim() -> void:
	_ensure_contract_root_dir()
	_ensure_dim_script()
	_ensure_dim_scene_and_return_wrote()


func _ensure_dim_script() -> bool:
	_ensure_contract_root_dir()
	var template: String = _dim_script_template()
	if _res_file_exists(GDFrameConfig.DIM_SCRIPT_PATH):
		var existing: String = _read_res_text(GDFrameConfig.DIM_SCRIPT_PATH)
		if _is_dim_script_scaffold(existing):
			return false
	if _write_res_text(GDFrameConfig.DIM_SCRIPT_PATH, template) != OK:
		return false
	return true


func _ensure_dim_scene_and_return_wrote() -> bool:
	if _res_file_exists(GDFrameConfig.DIM_SCENE_PATH):
		return false
	_ensure_dim_script()
	_ensure_contract_root_dir()
	var scene_text: String = _dim_scene_template()
	if _write_res_text(GDFrameConfig.DIM_SCENE_PATH, scene_text) != OK:
		return false
	return true


func _run_initial_contract_scaffold() -> void:
	_regenerate_gdc_registry()


func _contract_scaffold_sync_paths() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray([
		GDFrameConfig.PROJECT_CONTRACT_ROOT,
		GDFrameConfig.GENERATED_DIR,
		GDFrameConfig.EXT_ROOT_DIR,
	])
	for file_path: String in [
		GDFrameConfig.DIM_SCRIPT_PATH,
		GDFrameConfig.DIM_SCENE_PATH,
		GDFrameConfig.SIGNALS_SCRIPT_PATH,
		GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH,
		GDFrameConfig.EXT_FACADE_PATH,
		GDFrameConfig.EXT_FACADE_MODULES_PATH,
		GDFrameConfig.CONSTANTS_SCRIPT_PATH,
		GDFrameConfig.RESULT_SCRIPT_PATH,
		GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH,
	]:
		if _res_file_exists(file_path):
			paths.append(file_path)
	return paths


func _sync_contract_scaffold_filesystem() -> void:
	_asset_fs_sync_refresh_ext_root = true
	_sync_filesystem_after_asset_writes(_contract_scaffold_sync_paths())


func _refresh_ext_root_in_filesystem() -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	var ext_root: String = GDFrameConfig.EXT_ROOT_DIR
	if _res_dir_exists(ext_root):
		fs.update_file(ext_root)
	var facade_path: String = GDFrameConfig.EXT_FACADE_PATH
	if _res_file_exists(facade_path):
		fs.update_file(facade_path)


func _regenerate_gdc_registry() -> void:
	_ensure_contract_dim()
	_ensure_generated_dir()
	_ensure_signals_script(false)
	_ensure_profile_settings_script(false)
	_apply_profile_settings_generate_writes(_sync_profile_settings_fields(), false)
	_apply_result_generate_writes(_sync_result_constants(), false)
	_apply_signals_generate_writes(_sync_signals_script(false), false)
	_ensure_ext_scaffold()
	_regenerate_constants_registry(false)
	_sync_contract_scaffold_filesystem()

func _regenerate_constants_registry(sync_filesystem: bool = true) -> bool:
	_ensure_generated_dir()
	var out_path: String = GDFrameConfig.CONSTANTS_SCRIPT_PATH
	var lines: PackedStringArray = []
	lines.append("## Auto-generated by GDFrame — do not edit manually.")
	lines.append("class_name GDFrameConstants")
	lines.append("extends RefCounted")
	lines.append("")
	var scenes: Array[String] = _get_ui_scene_paths()
	lines.append("# --- UI（[method GDFrame.ui_open] / [method GDFrame.ui_close]）---")
	if scenes.is_empty():
		lines.append("# （尚无 UI）")
	else:
		for scene_path: String in scenes:
			var ui_id: String = scene_path.get_file().get_basename()
			var cn: Variant = _gdc_const_identifier(ui_id)
			lines.append("const %s: StringName = &\"%s\"" % [cn, ui_id])
	lines.append("")
	var reg_paths: Array[String] = _get_fsm_registry_paths()
	lines.append("# --- FSM machines ([method GDFrame.fsm_bind] machine_id) ---")
	if reg_paths.is_empty():
		lines.append("# （尚无状态机）")
	else:
		var state_keys: Dictionary = {}
		for reg_path: String in reg_paths:
			var fsm_id: String = reg_path.get_file().get_basename().trim_suffix("_registry")
			var fsm_cn: Variant = _gdc_const_identifier(fsm_id)
			lines.append("const %s: StringName = &\"%s\"" % [fsm_cn, fsm_id])
			for st: String in _get_fsm_state_keys(fsm_id):
				var st_cn: Variant = _gdc_const_identifier(st)
				if state_keys.has(st_cn) and String(state_keys[st_cn]) != st:
					push_warning(
						"GDFrameConstants: 状态常量名冲突 %s（%s 与 %s）"
						% [st_cn, state_keys[st_cn], st]
					)
					continue
				state_keys[st_cn] = st
		var sorted_state_consts: Array = state_keys.keys()
		sorted_state_consts.sort()
		lines.append("")
		lines.append(
			"# --- FSM state keys（state_key，多台状态机可复用同一 [StringName]）---"
		)
		if sorted_state_consts.is_empty():
			lines.append("# （尚无状态）")
		else:
			for cn: String in sorted_state_consts:
				var st: String = String(state_keys[cn])
				lines.append("const %s: StringName = &\"%s\"" % [cn, st])
	var new_content: String = "\n".join(lines) + "\n"
	if _read_res_text(out_path) == new_content:
		return false
	if _write_res_text(out_path, new_content) != OK:
		push_error("GDFrame: 无法写入 %s" % out_path)
		return false
	if sync_filesystem:
		_update_editor_filesystem(out_path)
	return true

func _ensure_ext_scaffold() -> void:
	_ensure_generated_dir()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(GDFrameConfig.EXT_ROOT_DIR)
	)
	if _facade_modules_needs_scaffold():
		_write_res_text(GDFrameConfig.EXT_FACADE_MODULES_PATH, _facade_modules_empty_template())
	if not _res_file_exists(GDFrameConfig.EXT_FACADE_PATH):
		_write_res_text(GDFrameConfig.EXT_FACADE_PATH, _facade_script_template())

func _facade_modules_empty_template() -> String:
	return (
		"## Auto-generated by GDFrame — do not edit manually.\n"
		+ "extends \"%s\"\n\n" % GDFrameConfig.SIGNALS_SCRIPT_PATH
	)


func _facade_modules_needs_scaffold() -> bool:
	if not _res_file_exists(GDFrameConfig.EXT_FACADE_MODULES_PATH):
		return true
	return not _read_res_text(GDFrameConfig.EXT_FACADE_MODULES_PATH).contains("extends \"")

func _facade_script_template() -> String:
	return (
		"## 项目扩展门面：默认继承自动生成 API；仅在此追加项目专属 [code]GDFrame.xxx()[/code]。\n"
		+ "extends \"%s\"\n" % GDFrameConfig.EXT_FACADE_MODULES_PATH
	)
