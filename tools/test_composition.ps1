# Run against a clean temporary consumer project. Requires Godot 4.7+.
param(
    [string]$Godot = "godot",
    [string]$Extensions = (Join-Path $PSScriptRoot "../../gdframe-ext")
)

$ErrorActionPreference = "Stop"
$core = (Resolve-Path (Join-Path $PSScriptRoot "../addons/gdframe")).Path
$modulesDir = (Resolve-Path (Join-Path $Extensions "addons")).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("gdframe-" + [guid]::NewGuid().ToString("N"))
$project = Join-Path $work "project"
$isolated = Join-Path $work "exported"
$utf8 = New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path "$project/addons", $isolated | Out-Null
function Write-Project($name, $content) {
    [IO.File]::WriteAllText((Join-Path $project $name), $content, $utf8)
}
function Invoke-Godot($dir, [string[]]$arguments) {
    $ErrorActionPreference = "Continue" # Native stderr includes Godot diagnostics.
    $output = & $Godot --headless --path $dir --log-file "$work/godot.log" @arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if (Test-Path "$work/godot.log") { $output += [IO.File]::ReadAllText("$work/godot.log") }
    if ($exitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR):') {
        throw "Godot failed ($arguments, exit $exitCode) in $work`n$output"
    }
    return $output
}
function Select-Modules([string[]]$ids) {
    $resources = @()
    $refs = @()
    foreach ($id in $ids) {
        $resources += '[ext_resource type="Resource" path="res://addons/gdframe_{0}/module.tres" id="{0}"]' -f $id
        $refs += 'ExtResource("{0}")' -f $id
    }
    Write-Project "gdframe_project/gdframe.tscn" (@(
        '[gd_scene format=3]', '',
        '[ext_resource type="PackedScene" path="res://addons/gdframe/runtime/base.tscn" id="root"]',
        '[ext_resource type="Script" path="res://addons/gdframe/runtime/module.gd" id="module"]',
        '[ext_resource type="PackedScene" path="res://gdframe_project/dim.tscn" id="dim"]'
    ) + $resources + @('', '[node name="GDFrame" instance=ExtResource("root")]',
        ('modules = Array[ExtResource("module")]([{0}])' -f ($refs -join ', ')),
        'dim_scene = ExtResource("dim")') -join "`n")
}
Copy-Item -LiteralPath $core -Destination "$project/addons/gdframe" -Recurse
Write-Project "project.godot" @'
config_version=5
[application]
config/name="GDFrame composition smoke"
run/main_scene="res://main.tscn"
[editor_plugins]
enabled=PackedStringArray("res://addons/gdframe/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'@
Write-Project "main.tscn" @'
[gd_scene format=3]
[ext_resource type="Script" path="res://main.gd" id="1"]
[ext_resource type="PackedScene" path="res://panel.tscn" id="panel"]
[node name="Smoke" type="Node"]
script = ExtResource("1")
panel = ExtResource("panel")
'@
Write-Project "panel.tscn" @'
[gd_scene format=3]
[ext_resource type="Script" path="res://addons/gdframe/runtime/ui/ui_base.gd" id="1"]
[node name="Panel" type="Control"]
script = ExtResource("1")
ui_use_dim = true
'@
Write-Project "main.gd" @'
extends Node

@export var panel: PackedScene

func _ready() -> void:
	var host := get_node("/root/GDFrame") as GDFrameRoot
	var expected := OS.get_cmdline_user_args()
	if host == null or host.service_ids().size() != expected.size() + 4:
		get_tree().quit(1)
		return
	for id in [&"ui", &"input", &"settings", &"save"]:
		if not host.has_service(id):
			get_tree().quit(7)
			return
	for id in expected:
		if not host.has_service(id):
			get_tree().quit(2)
			return
	if host.ui.get_child_count() != 0:
		get_tree().quit(8)
		return
	var dim: Control = host.ui.get_dim()
	if dim == null or dim.visible:
		get_tree().quit(9)
		return
	host.ui.register_scene(&"panel", panel)
	host.ui.register_scene(&"higher", panel)
	await host.ui.preload_ui(&"panel")
	await host.ui.preload_ui(&"higher")
	var higher: Control = host.ui.open(&"higher", null, 1)
	var lower: Control = host.ui.open(&"panel", null, 0)
	if higher == null or lower == null or not dim.visible or dim != host.ui.get_dim() or dim.get_parent() != higher.get_parent() or dim.get_index() + 1 != higher.get_index():
		get_tree().quit(9)
		return
	if host.dim_scene != null and (dim.get("effect") != &"higher" or not dim.get("was_hidden")):
		get_tree().quit(9)
		return
	if not host.ui.close(&"higher") or not dim.visible or dim.get_parent() != lower.get_parent() or dim.get_index() + 1 != lower.get_index():
		get_tree().quit(9)
		return
	if host.dim_scene != null and dim.get("effect") != &"panel":
		get_tree().quit(9)
		return
	if not host.ui.close(&"panel") or dim.visible or (host.dim_scene != null and dim.get("effect") != &""):
		get_tree().quit(9)
		return
	var button := InputEventJoypadButton.new()
	button.pressed = true
	get_viewport().push_input(button, true)
	if not host.input.is_using_gamepad() or not host.input.should_allow_nav_focus():
		get_tree().quit(10)
		return
	if host.save.get_profile().data.has("roundtrip") and host.settings.get_max_fps() != 60:
		get_tree().quit(11)
		return
	host.settings.set_max_fps(60)
	host.save.get_profile().data["roundtrip"] = true
	if not GDFrameResult.is_ok(host.save.flush()):
		get_tree().quit(12)
		return
	if host.has_service(&"audio"):
		var audio := host.get_service(&"audio")
		audio.set_bus_volume_linear(&"Music", 0.45)
		if not is_equal_approx(audio.get_bus_volume_linear(&"Music"), 0.45):
			get_tree().quit(16)
			return
	if host.has_service(&"input_remap"):
		InputMap.add_action(&"smoke_action")
		var remap := host.get_service(&"input_remap")
		remap.restore_state({"smoke_action": [{"type": &"key", "physical_keycode": KEY_SPACE}]})
		if InputMap.action_get_events(&"smoke_action").size() != 1:
			get_tree().quit(17)
			return
	if host.has_service(&"pool"):
		if not host.get_service(&"pool").register_scene(&"panel", panel):
			get_tree().quit(13)
			return
		var item := host.get_service(&"pool").get_item(&"panel", self) as Node
		if item == null:
			get_tree().quit(14)
			return
		host.get_service(&"pool").recycle_item(&"panel", item)
		host.get_service(&"pool").clear(&"panel", true)
	if host.has_service(&"rumble"):
		var rumble := host.get_service(&"rumble")
		rumble.set_enabled(false)
		if rumble.get_enabled():
			get_tree().quit(15)
			return
	if host.has_service(&"pause"):
		var pause := host.get_service(&"pause")
		pause.push(&"test")
		if not get_tree().paused:
			get_tree().quit(6)
			return
		pause.pop(&"test")
	print("GDFRAME_SMOKE_OK")
	get_tree().quit()
'@
Write-Project "export_presets.cfg" @'
[preset.0]
name="Smoke"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
[preset.0.options]
binary_format/architecture="x86_64"
'@
function Run-Smoke($dir, [string[]]$arguments) {
    $log = Invoke-Godot $dir $arguments
    if ($log -notmatch "GDFRAME_SMOKE_OK") { throw "Smoke scene did not finish in $work`n$log" }
}
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $work "userdata"
    $null = Invoke-Godot $project @("--import")
    Write-Project "gdframe_project/dim.tscn" @'
[gd_scene format=3]
[ext_resource type="Script" path="res://gdframe_project/dim.gd" id="1"]
[node name="Dim" type="Control"]
script = ExtResource("1")
'@
    Write-Project "gdframe_project/dim.gd" @'
extends Control
var effect: StringName
var was_hidden := false
func on_dim_show(ui_id: StringName) -> void:
    effect = ui_id
    was_hidden = not visible
func on_dim_hide() -> void:
    effect = &""
'@
    # Exercise the public autoload name after the plugin has registered it.
    $entry = [IO.File]::ReadAllText("$project/main.gd").Replace('get_node("/root/GDFrame") as GDFrameRoot', 'GDFrame')
    Write-Project "main.gd" $entry
    Run-Smoke $project @("--quit-after", "120")
    $folders = Get-ChildItem $modulesDir -Directory -Filter "gdframe_*" |
        Where-Object { Test-Path (Join-Path $_.FullName "module.tres") }
    foreach ($folder in $folders) {
        Copy-Item -LiteralPath $folder.FullName -Destination "$project/addons/$($folder.Name)" -Recurse
    }
    $null = Invoke-Godot $project @("--import")
    $ids = @($folders | ForEach-Object { $_.Name.Substring(8) })
    foreach ($id in $ids) {
        Select-Modules @($id)
        Run-Smoke $project @("--quit-after", "120", "--", $id)
    }
    Select-Modules $ids
    Run-Smoke $project (@("--quit-after", "120", "--") + $ids)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($selection in (@("") + $ids + @($ids -join ","))) {
        $enabled = @($selection -split "," | Where-Object { $_ })
        Select-Modules $enabled
        $zip = Join-Path $isolated "game.zip"
        $null = Invoke-Godot $project @("--export-pack", "Smoke", $zip)
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $paths = @($archive.Entries.FullName)
            foreach ($id in $ids) {
                $included = [bool]($paths -like "addons/gdframe_$id/*")
                if ($included -ne ($enabled -contains $id)) { throw "Export mismatch for $id ($selection)" }
            }
            if ($paths -match "addons/gdframe/runtime/(audio/|pool_api|fsm_api)") { throw "Optional API shell in core export" }
            if ($paths -like "addons/gdframe/editor/*") { throw "Editor scripts in export" }
        } finally { $archive.Dispose() }
        Run-Smoke $isolated (@("--main-pack", $zip, "--quit-after", "120", "--") + $enabled)
    }
    # Selected-scenes export exercises dependencies referenced by the autoload and scripts.
    $preset = [IO.File]::ReadAllText("$project/export_presets.cfg").Replace('export_filter="all_resources"', ('export_filter="scenes"' + "`n" + 'export_files=PackedStringArray("res://main.tscn")'))
    Write-Project "export_presets.cfg" $preset
    $pck = Join-Path $isolated "selected.pck"
    foreach ($selection in (@("") + $ids + @($ids -join ","))) {
        $enabled = @($selection -split "," | Where-Object { $_ })
        Select-Modules $enabled
        $null = Invoke-Godot $project @("--export-pack", "Smoke", $pck)
        Run-Smoke $isolated (@("--main-pack", $pck, "--quit-after", "120", "--") + $enabled)
    }
    # Exercise a project-defined registry through the same public FSM interface as game code.
    Select-Modules @("fsm")
    Write-Project "state.gd" 'extends GDFrameFSMState'
    Write-Project "registry.gd" @'
extends GDFrameFSMRegistryBase
func machine_id() -> StringName:
	return &"door"
func state_keys() -> Array[StringName]:
	return [&"closed", &"open"]
func state_script(_key: StringName) -> Script:
	return preload("res://state.gd")
'@
    Write-Project "main.gd" @'
extends Node
@export var panel: PackedScene
func _ready() -> void:
	var runner := GDFrame.get_service(&"fsm") as GDFrameFSMRunner
	if not runner.register_machine(preload("res://registry.gd").new()):
		get_tree().quit(20)
		return
	var handle := runner.bind(&"door", &"closed", self)
	if handle == null or not handle.change_state(&"open") or handle.current_state != &"open":
		get_tree().quit(21)
		return
	handle.release()
	print("GDFRAME_SMOKE_OK")
	get_tree().quit()
'@
    Run-Smoke $project @("--quit-after", "120")
    $resolved = (Resolve-Path -LiteralPath $work).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($resolved) -eq $tempRoot -and (Split-Path $resolved -Leaf) -match '^gdframe-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Write-Output "Passed core, $($ids.Count) standalone modules, full composition and exported packs."
} finally {
    $env:APPDATA = $previousAppData
}
