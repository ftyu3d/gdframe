param(
    [string]$Godot = "godot",
    [string]$Extensions = (Join-Path $PSScriptRoot "../../gdframe-ext"),
    [switch]$LayoutOnly,
    [switch]$GraphicalLayout
)
$ErrorActionPreference = "Stop"
$work = Join-Path ([IO.Path]::GetTempPath()) ("gdframe-dock-" + [guid]::NewGuid().ToString("N"))
$project = Join-Path $work "project"
$utf8 = New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path "$project/addons/probe", "$project/gdframe_project" -Force | Out-Null
function Write-Project($name, $content) {
    [IO.File]::WriteAllText((Join-Path $project $name), $content, $utf8)
}
function Invoke-Editor([string]$arguments) {
    # A real rendering device also exercises UI scene thumbnails during save.
    $process = Start-Process -FilePath $Godot -ArgumentList "--rendering-method gl_compatibility --path `"$project`" --log-file `"$work/godot.log`" $arguments" -WindowStyle Hidden -Wait -PassThru
    $log = [IO.File]::ReadAllText("$work/godot.log")
    if ($process.ExitCode -ne 0 -or $log -match '(?m)^(SCRIPT ERROR|ERROR):') {
        throw "Dock test failed in $work (exit $($process.ExitCode))`n$log"
    }
    return $log
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../addons/gdframe") -Destination "$project/addons/gdframe" -Recurse
foreach ($id in @("pool", "pause", "audio", "rumble")) {
    Copy-Item -LiteralPath (Join-Path $Extensions "addons/gdframe_$id") -Destination "$project/addons/gdframe_$id" -Recurse
}
Write-Project "project.godot" @'
config_version=5
[application]
config/name="GDFrame Dock test"
run/main_scene="res://main.tscn"
[autoload]
GDFrame="*res://gdframe_project/gdframe.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gdframe/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'@
Write-Project "gdframe_project/gdframe.tscn" @'
[gd_scene format=3]
[ext_resource type="PackedScene" path="res://addons/gdframe/runtime/base.tscn" id="base"]
[ext_resource type="Script" path="res://custom.gd" id="script"]
[node name="GDFrame" instance=ExtResource("base")]
script = ExtResource("script")
marker = "project-value"
[node name="ProjectChild" type="Node" parent="."]
'@
Write-Project "custom.gd" "extends GDFrameRoot`n@export var marker := `"default`"`n"
Write-Project "gdframe_project/locale_usage_fixture.gd" @'
extends RefCounted
const PREFIX := &"DOCK_USAGE_LITERAL_PREFIX"

func messages(id: int) -> Array[String]:
    # tr("DOCK_USAGE_COMMENT")
    return [
        tr("DOCK_USAGE_CALL"),
        TranslationServer.translate("DOCK_USAGE_FMT_%d" % id),
        tr("DOCK_USAGE_JOIN_" + str(id)),
        tr(PREFIX),
        "DOCK_USAGE_EXACT_LONG",
    ]
'@
Write-Project "gdframe_project/locale_usage_fixture.tscn" @'
[gd_scene format=3]
[node name="Fixture" type="Label"]
text = "DOCK_USAGE_SCENE"
'@
Write-Project "gdframe_project/locale_usage_fixture.json" '{"name_key":"DOCK_USAGE_DATA"}'
Write-Project "main.tscn" @'
[gd_scene format=3]
[ext_resource type="Script" path="res://main.gd" id="script"]
[node name="Smoke" type="Node"]
script = ExtResource("script")
'@
Write-Project "main.gd" @'
extends Node
func _ready() -> void:
    var root := get_node("/root/GDFrame")
    if root.marker != "project-value" or root.get("pool") == null or root.settings.get_max_fps() != 60 or not root.save.get_profile().data.abc or root.save.get_profile().data.rumble.enabled:
        get_tree().quit(1)
        return
    print("GDFRAME_DOCK_RUNTIME_OK")
    get_tree().quit()
'@
Write-Project "addons/probe/plugin.cfg" @'
[plugin]
name="Dock probe"
description=""
author=""
version="1.0"
script="plugin.gd"
'@
Write-Project "addons/probe/plugin.gd" @'
@tool
extends EditorPlugin
const Api = preload("res://addons/gdframe/editor/project_api_gen.gd")
const Zip = preload("res://addons/gdframe/editor/zip_install.gd")
const Versions = preload("res://addons/gdframe/editor/version_series.gd")
func _enter_tree() -> void:
    call_deferred("_run")
func _check(ok: bool, message: String) -> bool:
    if not ok:
        push_error(message)
        get_tree().quit(1)
    return ok
func _find(node: Node) -> Node:
    if node.name == "GDFrameDock":
        return node
    for child in node.get_children():
        var found := _find(child)
        if found != null:
            return found
    return null
func _run() -> void:
    await get_tree().create_timer(0.5).timeout
    var dock = _find(EditorInterface.get_base_control())
    if not _check(dock != null, "Dock missing"):
        return
    dock.context.plugin.make_bottom_panel_item_visible(dock)
    await get_tree().process_frame
    if not _check(dock._pages.get_child_count() == 6, "Five core pages and audio page required"):
        return
    var titles: Array = dock._sidebar.get_children().map(func(button: Button): return button.text)
    if not _check(titles == ["\u901a\u7528", "UI \u7ba1\u7406", "\u8bbe\u7f6e\u9879", "\u97f3\u9891\u97f3\u8f68", "\u6269\u5c55\u7ba1\u7406", "\u66f4\u65b0"], "Extension tabs must appear between settings and extension management"):
        return
    (dock._sidebar.get_child(3) as Button).pressed.emit()
    dock._rebuild_extension_pages()
    if not _check(dock._pages.get_child(3).visible and dock._sidebar.get_child(3).button_pressed, "Rebuilding extension tabs must preserve the active tab"):
        return
    (dock._sidebar.get_child(0) as Button).button_pressed = true
    dock._show(dock._pages.get_child(0))
    if not _check(dock._pages.get_children().filter(func(page): return page.visible).size() == 1, "Only one page may be visible"):
        return
    var general = dock._pages.get_child(0)
    if "dock-layout" in OS.get_cmdline_user_args():
        await _check_layout(dock, general)
        return
    general._layers.value = 5
    general._keyboard.button_pressed = true
    general._save()
    var modules = dock._modules
    dock._show(dock._pages.get_child(-2))
    modules.refresh()
    for id in ["pool", "pause"]:
        for index in modules._available.item_count:
            if str(modules._available.get_item_metadata(index)).contains("gdframe_" + id + "/"):
                modules._available.select(index)
                break
        modules._enable_button.pressed.emit()
    modules._enabled.select(0)
    modules._down_button.pressed.emit()
    modules._enabled.select(0)
    modules._disable_button.pressed.emit()
    modules._confirm_disable.confirmed.emit()
    modules._confirm_disable.hide()
    var root = dock.context.root()
    if not _check(root.modules.size() == 1 and root.modules[0].entry.resource_path.contains("gdframe_pool"), "Enable/order/disable failed"):
        return
    var filesystem := EditorInterface.get_resource_filesystem()
    while filesystem.is_scanning():
        await get_tree().process_frame
    await get_tree().create_timer(0.2).timeout
    modules._change("enable", "res://addons/gdframe_rumble/module.tres")
    await get_tree().create_timer(0.3).timeout
    while filesystem.is_scanning():
        await get_tree().process_frame
    var settings = dock._pages.get_child(2)
    dock._show(settings)
    settings._show_defaults(true)
    var fps_row = settings._rows.get_child(2).get_child(0)
    var fps_options: OptionButton = fps_row.get_child(1)
    for item_index in fps_options.item_count:
        if fps_options.get_item_metadata(item_index) == 60:
            fps_options.select(item_index)
            fps_options.item_selected.emit(item_index)
            break
    await get_tree().create_timer(0.3).timeout
    while filesystem.is_scanning():
        await get_tree().process_frame
    settings._edit_fps_presets()
    var preset_dialog = settings.get_child(settings.get_child_count() - 1)
    for child in preset_dialog.get_children():
        if child is VBoxContainer:
            child.get_child(1).text = "30, 60, 144"
            break
    preset_dialog.confirmed.emit()
    await get_tree().create_timer(0.15).timeout
    if not _check(GDFrameSettingsManager.max_fps_options() == [0, 30, 60, 144], "Edited FPS presets must replace the dropdown options"):
        return
    var rumble_toggle: CheckBox
    for item in settings._rows.get_children():
        if item is PanelContainer and item.get_child(0).get_child_count() == 5 and item.get_child(0).get_child(1) is Label and item.get_child(0).get_child(1).text == "rumble.enabled":
            rumble_toggle = item.get_child(0).get_child(2)
            if not _check(item.get_child(0).get_child(4) is Label, "Extension setting must show its source instead of a delete button"):
                return
            break
    if not _check(rumble_toggle != null and rumble_toggle.button_pressed, "Declared extension default must appear by name"):
        return
    rumble_toggle.button_pressed = false
    await get_tree().create_timer(0.15).timeout
    settings._edit_custom()
    var dialog = settings.get_child(settings.get_child_count() - 1)
    var form = dialog.get_child(0)
    for child in dialog.get_children():
        if child is VBoxContainer:
            form = child
    form.get_child(1).text = "abc"
    form.get_child(3).text = "Example"
    form.get_child(4).select(3)
    form.get_child(4).item_selected.emit(3)
    form.get_child(6).button_pressed = true
    dialog.confirmed.emit()
    await get_tree().create_timer(0.2).timeout
    var ui = dock._pages.get_child(1)
    dock._show(ui)
    ui._name.text = "smoke"
    ui._create()
    ui.refresh()
    ui._list.select(0)
    ui._selected()
    ui._layer.value = 2
    ui._dim.button_pressed = true
    ui._nav.button_pressed = false
    ui._save_options()
    var ui_scene := ResourceLoader.load("res://gdframe_project/ui/ui_smoke/ui_smoke.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
    var instance := ui_scene.instantiate()
    if not _check(instance.ui_default_layer == 2 and instance.ui_use_dim and not instance.ui_nav_participates, "UI properties not saved"):
        instance.free()
        return
    instance.free()
    ui._name.text = "temporary"
    ui._create()
    var previous_path := "res://gdframe_project/ui/ui_temporary/" + "ui_temporary.tscn"
    dock.context.write_file("res://reference.gd", 'extends RefCounted\nconst PATH = ' + var_to_str(previous_path) + '\n')
    ui._rename_files(previous_path, "ui_renamed")
    root = dock.context.root()
    if not _check(root.ui_scenes[1].resource_path.ends_with("ui_renamed.tscn") and FileAccess.get_file_as_string("res://reference.gd").contains("ui_renamed.tscn"), "UI rename must update scene registration and resource paths"):
        return
    ui._delete_files("res://gdframe_project/ui/ui_temporary/ui_renamed.tscn")
    if not _check(root.ui_scenes.size() == 1 and not FileAccess.file_exists("res://gdframe_project/ui/ui_temporary/ui_renamed.tscn"), "UI delete must remove files and registration"):
        return
    # The extension scaffold must use the same module descriptor format as releases.
    var extensions = dock._pages.get_child(-2)
    extensions._id.text = "smoke_service"
    extensions._title.text = "Smoke service"
    extensions._template.select(1)
    extensions._create()
    if not _check(FileAccess.file_exists("res://addons/gdframe_smoke_service/module.tres") and FileAccess.get_file_as_string("res://addons/gdframe_smoke_service/service.gd").contains("capture_state"), "Extension scaffold missing"):
        return
    var audio = dock._extension_pages[0]
    audio._name.text = "Voice"
    audio._add()
    if not _check(PackedStringArray(ProjectSettings.get_setting("gdframe/audio/channels")).has("Voice"), "Audio channel creation failed"):
        return
    # Installer rejects an old bundle before writing any files, then accepts a valid bundle.
    var archive := ZIPPacker.new()
    archive.open("user://probe.zip")
    archive.start_file("addons/gdframe_probe/service.gd")
    archive.write_file("extends RefCounted".to_utf8_buffer())
    archive.close_file()
    archive.close()
    var mapper := func(path: String): return Zip.map_entry_under_prefix(path, "addons/gdframe_probe")
    var bytes := FileAccess.get_file_as_bytes("user://probe.zip")
    if not _check(not Zip.extract_zip_to_res(bytes, OS.get_temp_dir().path_join("gdframe-probe-install.zip"), mapper, "res://addons/gdframe_probe", [], [], ["module.tres"]) and not DirAccess.dir_exists_absolute("res://addons/gdframe_probe"), "Old extension bundle must be rejected before writes"):
        return
    archive.open("user://probe.zip")
    for path in ["addons/gdframe_probe/module.tres", "addons/gdframe_probe/service.gd"]:
        archive.start_file(path)
        archive.write_file("fixture".to_utf8_buffer())
        archive.close_file()
    archive.close()
    bytes = FileAccess.get_file_as_bytes("user://probe.zip")
    if not _check(Zip.extract_zip_to_res(bytes, OS.get_temp_dir().path_join("gdframe-probe-install.zip"), mapper, "res://addons/gdframe_probe", [], [], ["module.tres"]), "Valid new extension bundle rejected"):
        return
    # Remove the synthetic resource before a filesystem scan attempts to import it.
    DirAccess.remove_absolute("res://addons/gdframe_probe/module.tres")
    DirAccess.remove_absolute("res://addons/gdframe_probe/service.gd")
    DirAccess.remove_absolute("res://addons/gdframe_probe")
    var index := Versions.parse_plugin_index_cfg(Versions.parse_cfg_text('[meta]\ndefault_series="1.0"\n[series.1.0]\nversion="1.0.0"\n'))
    if not _check(index.supported["1.0"].version == "1.0.0", "Release index parsing failed"):
        return
    var result := Api.generate(dock.context)
    if not _check(FileAccess.file_exists(Api.OUTPUT), result):
        return
    var generated := FileAccess.get_file_as_string(Api.OUTPUT)
    if not _check(generated.contains("var pool: GDFrameNodePool") and not generated.contains("audio"), "Typed API must contain selected services only"):
        return
    root = dock.context.root()
    if not _check(root.marker == "project-value" and root.has_node("ProjectChild") and root.ui_layers == 5 and root.ui_scenes.size() == 1 and root.profile_defaults.get("abc") == true and root.profile_setting_labels.get("abc") == "Example", "Project scene data or custom display name lost"):
        return
    await get_tree().process_frame
    print("GDFRAME_DOCK_OK")
    get_tree().quit()

func _check_layout(dock: Control, general: Control) -> void:
    var minimum := float(dock.custom_minimum_size.y)
    for page in dock._pages.get_children():
        dock._show(page)
        await get_tree().process_frame
        if not _check(is_equal_approx(dock.get_combined_minimum_size().y, minimum), "All Dock pages must share the compact minimum height"):
            return
    dock._show(dock._pages.get_child(-2))
    await get_tree().process_frame
    var rows: VBoxContainer = dock._modules._rows
    var viewport := rows.get_parent() as ScrollContainer
    var height_at_minimum := viewport.size.y - (dock.size.y - minimum)
    var two_rows := (rows.get_child(0) as Control).size.y + (rows.get_child(1) as Control).size.y + rows.get_theme_constant("separation")
    if not _check(height_at_minimum + 1.0 >= two_rows, "At least two installed extensions must fit at the Dock minimum height"):
        return
    var design_width := "display/window/size/viewport_width"
    var width_override := "display/window/size/window_width_override"
    var engine_width: int = ProjectSettings.property_get_revert(design_width)
    ProjectSettings.set_setting(design_width, engine_width + 32)
    ProjectSettings.set_setting(width_override + ".windows", 1280)
    ProjectSettings.set_setting(width_override + ".macos", 1024)
    var settings = dock._pages.get_child(2)
    dock._show(settings)
    var display = settings._rows.get_child(0).get_child(0)
    if not _check(display is HFlowContainer and display.get_child_count() == 3, "Design width, height and VSync must share one wrapping row"):
        return
    var layout := display.duplicate(0) as HFlowContainer
    add_child(layout)
    layout.size.x = 1000
    await get_tree().process_frame
    var first := layout.get_child(0) as Control
    var last := layout.get_child(2) as Control
    if not _check(is_equal_approx(last.position.y, first.position.y), "Display settings must fit on one line at a typical Dock width"):
        return
    layout.size.x = layout.get_combined_minimum_size().x
    await get_tree().process_frame
    if not _check(last.position.y > first.position.y, "Display settings must wrap at the minimum width"):
        return
    layout.queue_free()
    var design_row = display.get_child(0)
    var revert_icon := EditorInterface.get_editor_theme().get_icon(&"ReloadSmall", &"EditorIcons")
    var design_restore := design_row.get_child(-1) as Button
    if not _check(revert_icon != null and design_restore.icon == revert_icon and design_restore.text.is_empty(), "Project restore must use the native revert icon"):
        return
    design_restore.pressed.emit()
    await get_tree().process_frame
    if not _check(ProjectSettings.get_setting(design_width) == engine_width, "Design width must use the Godot engine default when reverted"):
        return
    for item in settings._rows.get_children():
        if not item is PanelContainer:
            continue
        var group = item.get_child(0)
        var width_field = group.get_child(0)
        if width_field.get_child(0).tooltip_text.ends_with(width_override + ".windows"):
            if not _check(group is HFlowContainer and group.get_child_count() == 2 and group.get_child(1).get_child(0).tooltip_text.ends_with("window_height_override.windows"), "Platform width and height must share one wrapping row"):
                return
            width_field.get_child(-1).pressed.emit()
            break
    if not _check(not ProjectSettings.has_setting(width_override + ".windows") and ProjectSettings.get_setting(width_override + ".macos") == 1024, "Reverting one platform must only clear that platform override"):
        return
    settings._show_defaults(true)
    if not _check(settings._write("max_fps", 60, "settings"), "Fixture must be able to set a profile default"):
        return
    await get_tree().create_timer(0.2).timeout
    var fps_row = settings._rows.get_child(2).get_child(0)
    var fps_restore := fps_row.get_child(-1) as Button
    if not _check(fps_restore.icon == revert_icon and fps_restore.text.is_empty(), "Profile restore must use the native revert icon"):
        return
    fps_restore.pressed.emit()
    if not _check(not dock.context.read_property(&"profile_defaults", {}).get("settings", {}).has("max_fps"), "Resetting FPS must clear the profile override"):
        return
    await get_tree().create_timer(0.2).timeout
    settings._custom_row("always_show_dropped_item_names", true, "settings", "Drop labels")
    var toggle_row := settings._rows.get_child(-1).get_child(0) as HBoxContainer
    var field_label := toggle_row.get_child(1) as Label
    var enabled_toggle := toggle_row.get_child(2) as CheckBox
    if not _check(field_label.size_flags_horizontal == Control.SIZE_EXPAND_FILL and enabled_toggle.size_flags_horizontal == Control.SIZE_FILL, "The field name must receive the space to the left of the compact checkbox"):
        return
    settings._show_defaults(false)
    dock._show(general)
    var launcher = preload("res://addons/gdframe/editor/ide_launcher.gd")
    launcher._detect(launcher.Candidates.by_id("vscode"))
    var editor_settings := EditorInterface.get_editor_settings()
    var external_enabled := "text_editor/external/use_external_editor"
    var external_path := "text_editor/external/exec_path"
    launcher.State.set_external_editor_ide("")
    editor_settings.set_setting(external_path, OS.get_executable_path())
    editor_settings.set_setting(external_enabled, true)
    launcher.restore_project_preference()
    general._sync_ide()
    if not _check(general._ide.selected == 0 and not launcher.is_enabled() and general._open_project_button.disabled and general._open_repository_button.disabled, "A project without an IDE choice must start with the built-in editor"):
        return
    if OS.get_name() == "Windows":
        var install := ProjectSettings.globalize_path("user://IDE test/Cursor")
        var bin := install.path_join("resources/app/bin")
        DirAccess.make_dir_recursive_absolute(bin)
        var wrapper := bin.path_join("cursor")
        var cursor := install.path_join("Cursor.exe")
        for path in [wrapper, cursor]:
            var file := FileAccess.open(path, FileAccess.WRITE)
            file.close()
        var previous_ide: String = launcher.State.get_external_editor_ide()
        launcher.State.set_external_editor_ide("cursor")
        editor_settings.set_setting(external_path, wrapper.replace("/", "\\"))
        editor_settings.set_setting(external_enabled, true)
        if not _check(not launcher.can_open_folder(), "Windows CLI wrapper must not be launched directly"):
            return
        launcher.repair_configured_windows_ide()
        if not _check(editor_settings.get_setting(external_path) == cursor and launcher.can_open_folder(), "Saved Cursor wrapper must resolve to Cursor.exe"):
            return
        editor_settings.set_setting(external_enabled, false)
        launcher.restore_project_preference()
        if not _check(launcher.is_enabled() and editor_settings.get_setting(external_path) == cursor, "An explicit project IDE choice must be restored"):
            return
        launcher.State.set_external_editor_ide(previous_ide)
    editor_settings.set_setting(external_path, OS.get_executable_path())
    editor_settings.set_setting(external_enabled, true)
    general._sync_ide()
    if not _check(not general._open_project_button.disabled and not general._open_repository_button.disabled, "Folder actions must be available with an external editor"):
        return
    general._ide.select(0)
    general._ide.item_selected.emit(0)
    if not _check(not editor_settings.get_setting(external_enabled) and launcher.State.get_external_editor_ide().is_empty() and general._open_project_button.disabled and general._open_repository_button.disabled, "Disabling external IDE must clear the project choice and disable both folder actions"):
        return
    if not _check(editor_settings.get_setting(external_path) == OS.get_executable_path(), "Disabling external IDE must retain its executable path"):
        return
    if not await _check_localization(dock, general, settings):
        return
    await get_tree().create_timer(0.2).timeout
    print("GDFRAME_DOCK_LAYOUT_OK")
    get_tree().quit()

func _check_localization(dock: Control, general: Control, settings: Control) -> bool:
    const Csv = preload("res://addons/gdframe/editor/locale_scaffold.gd")
    const RuntimeSettings = preload("res://addons/gdframe/runtime/settings/settings_manager.gd")
    const KEY_NAME := "DOCK_TEST_QUOTED"
    const MESSAGE := "Comma, and \"quotes\"\n\u7b2c\u4e8c\u884c"
    var chinese_locales := PackedStringArray(["zh_Hans_CN", "zh_Hant_TW"])
    if not _check(RuntimeSettings._match_locale("zh_TW", chinese_locales) == "zh_Hant_TW" and RuntimeSettings._match_locale("pt_BR", PackedStringArray(["pt_PT"]), 10).is_empty(), "Runtime locale selection must match equivalent codes while keeping explicit regional variants distinct"):
        return false
    if not _check(not Csv.builtin_rows(chinese_locales).LOCALE_NAME[1].is_empty(), "Framework seed translations must recognize equivalent locale codes"):
        return false
    var separate := Translation.new()
    separate.set_locale("it")
    separate.add_message("SEPARATE", "Altro")
    const SEPARATE_PATH := "res://separate.translation"
    if not _check(ResourceSaver.save(separate, SEPARATE_PATH) == OK, "Could not stage separate translation"):
        return false
    ProjectSettings.set_setting(Csv.TRANSLATIONS, PackedStringArray([SEPARATE_PATH]))

    general._open_localization()
    var window = general._locale_window
    var manager = window.panel
    general._open_localization()
    if not _check(window == general._locale_window and window.visible and manager._table.locales.has("en"), "The locale manager must open a single window with the initial template"):
        return false
    if not _check(manager._status.get_theme_color(&"font_color") == dock.context.status.get_theme_color(&"font_color"), "The locale window and Dock must share the same status text color"):
        return false
    var editor_base := EditorInterface.get_base_control().get_theme_color(&"base_color", &"Editor")
    var background := window.get_child(0) as ColorRect
    if not _check(background != null and background.color == editor_base and background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The locale window must use the editor background without intercepting clicks"):
        return false
    var entries := manager._entries as Tree
    if not _check(entries.select_mode == Tree.SELECT_ROW and not entries.column_titles_visible, "The locale list must select whole rows and use passive column labels"):
        return false
    if not await _check_unused_translation_keys(manager):
        return false
    manager._edit_language(false)
    var dialog := manager.get_child(-1) as ConfirmationDialog
    var form := dialog.get_child(0) as VBoxContainer
    var language_search := form.get_child(0) as LineEdit
    var language_matches := form.get_child(1) as ItemList
    var defaults := PackedStringArray(["zh_CN", "zh_TW", "en"])
    for index in defaults.size():
        if not _check(language_matches.get_item_metadata(index) == defaults[index] and language_matches.is_item_disabled(index) and language_matches.get_item_text(index).ends_with("\u5df2\u6dfb\u52a0"), "Installed languages must appear first and be marked and disabled"):
            return false
    language_search.text_changed.emit("zh-Hans-CN")
    if not _check(language_matches.item_count == 1 and language_matches.get_item_metadata(0) == "zh_CN" and language_matches.is_item_disabled(0), "A Chinese locale alias must return only the installed equivalent"):
        return false
    language_search.text_changed.emit("zh-Hant-TW")
    if not _check(language_matches.item_count == 1 and language_matches.get_item_metadata(0) == "zh_TW" and language_matches.is_item_disabled(0), "A traditional Chinese alias must resolve to the installed equivalent"):
        return false
    language_search.text = "ZH-hans-cn"
    dialog.confirmed.emit()
    if not _check(not dialog.is_queued_for_deletion() and manager._table.locales == defaults, "Typing an installed language code must not add a duplicate"):
        return false
    var choices: Dictionary = manager._locale_choices("")
    if not _check(choices.has("sr_Cyrl_RS") and choices.has("sr_Latn_RS") and choices.has("pt_BR") and choices.has("pt_PT") and not choices.has("es_419"), "Available choices must keep distinct scripts and regions and exclude unsupported numeric region codes"):
        return false
    language_search.text_changed.emit("sr-RS")
    if not _check(language_matches.item_count == 1 and language_matches.get_item_metadata(0) == "sr_Cyrl_RS", "Searching an equivalent code must find its target even if the catalog lists only the fully qualified code"):
        return false
    language_search.text_changed.emit("\u5df4\u897f")
    var found_brazilian_portuguese := false
    for index in language_matches.item_count:
        if language_matches.get_item_metadata(index) == "pt_BR":
            found_brazilian_portuguese = language_matches.get_item_text(index).contains("\u8461\u8404\u7259\u8bed")
    if not _check(found_brazilian_portuguese, "Searching for a Chinese country name must find its regional locale"):
        return false
    language_search.text_changed.emit("Japanese")
    if not _check(language_matches.item_count > 0 and language_matches.get_item_metadata(0) == "ja", "The language picker must still support English searches"):
        return false
    language_search.text_changed.emit("\u65e5\u8bed")
    if not _check(language_matches.item_count > 0 and language_matches.get_item_metadata(0) == "ja", "The language picker must support Chinese searches"):
        return false
    await _accept_locale_dialog(manager, "\u65e5\u8bed")
    if not _check(manager._languages.get_item_text(manager._languages.selected) == "\u65e5\u8bed\uff08ja\uff09", "The translation language dropdown must show the Chinese name and locale code"):
        return false
    manager._edit_key(false)
    await _accept_locale_dialog(manager, KEY_NAME)
    manager._translation.text = MESSAGE
    manager._edit_translation()
    manager._search.text = MESSAGE.get_slice("\n", 1)
    manager._refresh_entries()
    if not _check(manager._key == KEY_NAME and manager._entries.get_root().get_child_count() == 1, "Search must find a key using its translated text"):
        return false
    if not _check(entries.get_selected().is_selected(0) and entries.get_selected().is_selected(1) and manager._translation.text == MESSAGE, "Selecting a translation row must highlight its key and preview together"):
        return false
    var tabs := TabContainer.new()
    add_child(tabs)
    tabs.add_child(Control.new())
    var embedded := preload("res://addons/gdframe/editor/locale_panel.gd").new()
    tabs.add_child(embedded)
    tabs.current_tab = 1
    embedded._locale_index = manager._locale_index
    embedded._refresh_languages()
    embedded._search.text = "excluded"
    embedded._filter.select(1)
    if not _check(embedded.document == manager.document and embedded.select_key(KEY_NAME) and embedded._translation.text == MESSAGE, "An embedded panel must locate the exact key and show the shared unsaved edit"):
        return false
    tabs.queue_free()
    var copy := manager._entry_actions[0] as Button
    var rename := manager._entry_actions[1] as Button
    if not _check(not copy.disabled and copy.get_index() + 1 == rename.get_index(), "The key copy button must be immediately left of Rename"):
        return false
    if DisplayServer.get_name() != "headless":
        var previous_clipboard := DisplayServer.clipboard_get()
        copy.pressed.emit()
        var copied := DisplayServer.clipboard_get() == KEY_NAME
        DisplayServer.clipboard_set(previous_clipboard)
        if not _check(copied and manager._status.text.contains(KEY_NAME), "Copy must send the selected translation key to the clipboard"):
            return false
    manager._filter.select(1)
    manager._filter.item_selected.emit(1)
    if not _check(manager._entries.get_root().get_child_count() == 0, "Only missing must hide translated entries"):
        return false
    manager._filter.select(0)
    await _save_localization(manager)
    var table := Csv.read_csv()
    var japanese := "res://locale/localization.ja.translation"
    var registered: PackedStringArray = ProjectSettings.get_setting(Csv.TRANSLATIONS)
    if not _check(table.has("rows") and table.rows[KEY_NAME][table.locales.find("ja")] == MESSAGE and japanese in registered and SEPARATE_PATH in registered, "New language and quoted multiline translation must round-trip and register: " + manager._status.text):
        return false
    var japanese_translation := ResourceLoader.load(japanese, "Translation") as Translation
    if not _check(japanese_translation.get_message(KEY_NAME) == MESSAGE, "The imported resource must contain the multiline translation"):
        return false
    dock._show(settings)
    settings._show_defaults(true)
    var language_options := settings._rows.get_child(1).get_child(0).get_child(1) as OptionButton
    var settings_has_japanese := false
    for index in language_options.item_count:
        if language_options.get_item_metadata(index) == "ja":
            settings_has_japanese = true
    if not _check(settings_has_japanese, "New project locales must be available immediately in profile defaults"):
        return false
    dock._show(general)

    manager._edit_language(true)
    await _accept_locale_dialog(manager, "ko")
    manager._search.text = KEY_NAME
    manager._refresh_entries()
    manager._edit_key(true)
    await _accept_locale_dialog(manager, KEY_NAME + "_RENAMED")
    await _save_localization(manager)
    registered = ProjectSettings.get_setting(Csv.TRANSLATIONS)
    var korean := "res://locale/localization.ko.translation"
    if not _check(korean in registered and japanese not in registered and SEPARATE_PATH in registered and manager._translation.text == MESSAGE, "Renaming the language and key must preserve its translation and unregister the old resource: " + manager._status.text):
        return false
    manager._delete_key()
    await _accept_locale_dialog(manager)
    manager._delete_language()
    await _accept_locale_dialog(manager)
    await _save_localization(manager)
    table = Csv.read_csv()
    registered = ProjectSettings.get_setting(Csv.TRANSLATIONS)
    if not _check(not table.rows.has(KEY_NAME + "_RENAMED") and "ko" not in table.locales and korean not in registered and SEPARATE_PATH in registered, "Deleting a language or key must remove it and preserve unrelated registrations"):
        return false
    if not _check(not FileAccess.file_exists(japanese) and not FileAccess.file_exists(korean), "Removed locales must not leave generated translation files in the project"):
        return false
    ProjectSettings.set_setting(Csv.FALLBACK, "zh_CN")
    manager._select_language(table.locales.find("zh_CN"))
    manager._edit_language(true)
    await _accept_locale_dialog(manager, "zh_Hans_CN")
    await _save_localization(manager)
    table = Csv.read_csv()
    if not _check("zh_Hans_CN" in table.locales and "zh_CN" not in table.locales and ProjectSettings.get_setting(Csv.FALLBACK) == "zh_Hans_CN", "An explicit rename to the fully qualified code must preserve the fallback target"):
        return false
    var file := FileAccess.open(Csv.LOCALE_CSV_PATH, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_line("")
    file.close()
    manager._edit_key(false)
    await _accept_locale_dialog(manager, "UNSAVED_CONFLICT")
    await _save_localization(manager)
    if not _check(manager.document.dirty and not Csv.read_csv().rows.has("UNSAVED_CONFLICT"), "An external CSV edit must prevent overwriting it"):
        return false
    var csv_menu := manager._csv_menu as MenuButton
    if not _check(csv_menu.get_parent().get_child_count() == 3, "The footer must contain a status label, CSV tools, and Save"):
        return false
    var tools := csv_menu.get_popup()
    var reload_index := -1
    for index in tools.item_count:
        if tools.get_item_text(index) == "\u91cd\u65b0\u8bfb\u53d6 CSV":
            reload_index = index
            break
    if not _check(reload_index >= 0, "Reload CSV must appear in the CSV tools menu"):
        return false
    tools.id_pressed.emit(tools.get_item_id(reload_index))
    if not _check(manager.get_child(-1) is ConfirmationDialog and manager.document.dirty, "Reloading from the menu must still ask before discarding edits"):
        return false
    await _accept_locale_dialog(manager)
    if not _check(not manager.document.dirty and not manager._table.rows.has("UNSAVED_CONFLICT"), "Confirming reload must read the on-disk translation table"):
        return false
    window.queue_free()
    return true

func _check_unused_translation_keys(manager: Control) -> bool:
    if not _check(not manager._rescan.visible, "Rescan must be hidden in the All filter"):
        return false
    var suffixes := ["call", "literal_prefix", "fmt_1", "join_1", "scene", "data", "comment", "exact", "orphan"]
    var keys := PackedStringArray()
    for suffix: String in suffixes:
        var key := ("dock_usage_" + suffix).to_upper()
        var cells := PackedStringArray()
        cells.resize(manager._table.locales.size())
        manager._table.rows[key] = cells
        keys.append(key)
    manager._search.text = "dock_usage_"
    manager._filter.select(2)
    manager._filter.item_selected.emit(2)
    if not _check(manager._rescan.visible and manager._rescan.disabled, "Rescan must appear beside the unused filter and be disabled while scanning"):
        return false
    while manager._scanning_usage:
        await get_tree().process_frame
    var shown := PackedStringArray()
    for item: TreeItem in manager._entries.get_root().get_children():
        shown.append(item.get_metadata(0))
    if not _check(shown == keys.slice(6), "Unused must omit direct calls, constants, dynamic prefixes and resource references, but retain comment-only keys and exact-name collision candidates: " + str(shown)):
        return false
    if not _check(not manager._rescan.disabled, "Rescan must be available once scanning completes"):
        return false
    for key: String in keys:
        manager._table.rows.erase(key)
    manager._search.text = ""
    manager._filter.select(0)
    manager._filter.item_selected.emit(0)
    return true

func _accept_locale_dialog(manager: Control, value := "") -> void:
    var dialog := manager.get_child(-1) as ConfirmationDialog
    if not value.is_empty():
        var form := dialog.get_child(0) as VBoxContainer
        (form.get_child(0) as LineEdit).text = value
    dialog.confirmed.emit()
    await get_tree().process_frame

func _save_localization(manager: Control) -> void:
    manager._request_save()
    while manager.document.saving:
        await get_tree().process_frame
'@
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $work "userdata"
    $null = Invoke-Editor "--import"
    $config = [IO.File]::ReadAllText("$project/project.godot").Replace('enabled=PackedStringArray("res://addons/gdframe/plugin.cfg")', 'enabled=PackedStringArray("res://addons/gdframe/plugin.cfg", "res://addons/probe/plugin.cfg")')
    Write-Project "project.godot" $config
    $layoutMode = if ($LayoutOnly -and -not $GraphicalLayout) { "--headless " } else { "" }
    $layout = Invoke-Editor "${layoutMode}--editor --quit-after 600 -- dock-layout"
    if ($layout -notmatch "GDFRAME_DOCK_LAYOUT_OK") { throw "Dock layout test did not complete in $work`n$layout" }
    Write-Output "Passed Dock layout, project and profile resets, external IDE detection, and localization CRUD/import."
    if (-not $LayoutOnly) {
        $log = Invoke-Editor "--editor --quit-after 600"
        if ($log -notmatch "GDFRAME_DOCK_OK") { throw "Dock test did not complete in $work`n$log" }
        $config = [IO.File]::ReadAllText("$project/project.godot").Replace(', "res://addons/probe/plugin.cfg"', '')
        Write-Project "project.godot" $config
        $null = Invoke-Editor "--import"
        $log = Invoke-Editor "--headless --quit-after 120"
        if ($log -notmatch "GDFRAME_DOCK_RUNTIME_OK") { throw "Generated project did not start in $work`n$log" }
        Write-Output "Passed Dock pages, module operations, UI scaffold, defaults, typed API and ZIP installation."
    }
    $resolved = (Resolve-Path -LiteralPath $work).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($resolved) -eq $tempRoot -and (Split-Path $resolved -Leaf) -match '^gdframe-dock-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
} finally {
    $env:APPDATA = $previousAppData
}
