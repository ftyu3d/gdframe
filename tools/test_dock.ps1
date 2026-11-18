param(
    [string]$Godot = "godot",
    [string]$Extensions = (Join-Path $PSScriptRoot "../../gdframe-ext")
)
$ErrorActionPreference = "Stop"
$work = Join-Path ([IO.Path]::GetTempPath()) ("gdframe-dock-" + [guid]::NewGuid().ToString("N"))
$project = Join-Path $work "project"
$utf8 = New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path "$project/addons/probe" -Force | Out-Null
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
foreach ($id in @("pool", "pause", "audio")) {
    Copy-Item -LiteralPath (Join-Path $Extensions "addons/gdframe_$id") -Destination "$project/addons/gdframe_$id" -Recurse
}
Write-Project "project.godot" @'
config_version=5
[application]
config/name="GDFrame Dock test"
run/main_scene="res://main.tscn"
[autoload]
GDFrame="*res://gdframe.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gdframe/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'@
Write-Project "gdframe.tscn" @'
[gd_scene format=3]
[ext_resource type="PackedScene" path="res://addons/gdframe/runtime/base.tscn" id="base"]
[ext_resource type="Script" path="res://custom.gd" id="script"]
[node name="GDFrame" instance=ExtResource("base")]
script = ExtResource("script")
marker = "project-value"
[node name="ProjectChild" type="Node" parent="."]
'@
Write-Project "custom.gd" "extends GDFrameRoot`n@export var marker := `"default`"`n"
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
    if root.marker != "project-value" or root.get("pool") == null or root.settings.get_max_fps() != 60 or root.save.get_profile().data.chapter != 2:
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
    dock._show(dock._pages.get_child(1))
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
    var ui = dock._pages.get_child(2)
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
    var extensions = dock._pages.get_child(1)
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
    var filesystem := EditorInterface.get_resource_filesystem()
    while filesystem.is_scanning():
        await get_tree().process_frame
    await get_tree().create_timer(0.2).timeout
    var settings = dock._pages.get_child(3)
    dock._show(settings)
    var fps_row = settings._rows.get_child(5).get_child(0)
    var fps_options = fps_row.get_child(1)
    for option_index in fps_options.item_count:
        if fps_options.get_item_metadata(option_index) == 60:
            fps_options.select(option_index)
    fps_row.get_child(3).pressed.emit()
    await get_tree().process_frame
    settings._edit_custom()
    var dialog = settings.get_child(settings.get_child_count() - 1)
    var form = dialog.get_child(0)
    for child in dialog.get_children():
        if child is VBoxContainer:
            form = child
    form.get_child(1).text = "chapter"
    form.get_child(2).select(1)
    form.get_child(2).item_selected.emit(1)
    form.get_child(3).text = "2"
    dialog.confirmed.emit()
    await get_tree().create_timer(0.2).timeout
    var result := Api.generate(dock.context)
    if not _check(FileAccess.file_exists(Api.OUTPUT), result):
        return
    var generated := FileAccess.get_file_as_string(Api.OUTPUT)
    if not _check(generated.contains("var pool: GDFrameNodePool") and not generated.contains("audio"), "Typed API must contain selected services only"):
        return
    root = dock.context.root()
    if not _check(root.marker == "project-value" and root.has_node("ProjectChild") and root.ui_layers == 5 and root.ui_scenes.size() == 1 and root.profile_defaults.get("chapter") == 2, "Project scene data lost"):
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
    dock._show(dock._pages.get_child(1))
    await get_tree().process_frame
    var rows: VBoxContainer = dock._modules._rows
    var viewport := rows.get_parent() as ScrollContainer
    var height_at_minimum := viewport.size.y - (dock.size.y - minimum)
    var two_rows := (rows.get_child(0) as Control).size.y + (rows.get_child(1) as Control).size.y + rows.get_theme_constant("separation")
    if not _check(height_at_minimum + 1.0 >= two_rows, "At least two installed extensions must fit at the Dock minimum height"):
        return
    dock._show(general)
    var launcher = preload("res://addons/gdframe/editor/ide_launcher.gd")
    launcher._detect(launcher.Candidates.by_id("vscode"))
    var editor_settings := EditorInterface.get_editor_settings()
    var external_enabled := "text_editor/external/use_external_editor"
    var external_path := "text_editor/external/exec_path"
    editor_settings.set_setting(external_path, OS.get_executable_path())
    editor_settings.set_setting(external_enabled, true)
    general._sync_ide()
    if not _check(not general._open_project_button.disabled and not general._open_repository_button.disabled, "Folder actions must be available with an external editor"):
        return
    general._ide.select(0)
    general._ide.item_selected.emit(0)
    if not _check(not editor_settings.get_setting(external_enabled) and general._open_project_button.disabled and general._open_repository_button.disabled, "Disabling external IDE must disable both folder actions"):
        return
    if not _check(editor_settings.get_setting(external_path) == OS.get_executable_path(), "Disabling external IDE must retain its executable path"):
        return
    await get_tree().create_timer(0.2).timeout
    print("GDFRAME_DOCK_LAYOUT_OK")
    get_tree().quit()
'@
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $work "userdata"
    $null = Invoke-Editor "--import"
    $config = [IO.File]::ReadAllText("$project/project.godot").Replace('enabled=PackedStringArray("res://addons/gdframe/plugin.cfg")', 'enabled=PackedStringArray("res://addons/gdframe/plugin.cfg", "res://addons/probe/plugin.cfg")')
    Write-Project "project.godot" $config
    $layout = Invoke-Editor "--editor --quit-after 600 -- dock-layout"
    if ($layout -notmatch "GDFRAME_DOCK_LAYOUT_OK") { throw "Dock layout test did not complete in $work`n$layout" }
    Write-Output "Passed Dock minimum height, visible extension rows and external IDE detection."
    $log = Invoke-Editor "--editor --quit-after 600"
    if ($log -notmatch "GDFRAME_DOCK_OK") { throw "Dock test did not complete in $work`n$log" }
    $config = [IO.File]::ReadAllText("$project/project.godot").Replace(', "res://addons/probe/plugin.cfg"', '')
    Write-Project "project.godot" $config
    $null = Invoke-Editor "--import"
    $log = Invoke-Editor "--headless --quit-after 120"
    if ($log -notmatch "GDFRAME_DOCK_RUNTIME_OK") { throw "Generated project did not start in $work`n$log" }
    $resolved = (Resolve-Path -LiteralPath $work).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($resolved) -eq $tempRoot -and (Split-Path $resolved -Leaf) -match '^gdframe-dock-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Write-Output "Passed Dock pages, module operations, UI scaffold, defaults, typed API and ZIP installation."
} finally {
    $env:APPDATA = $previousAppData
}
