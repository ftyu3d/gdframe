@tool
extends RefCounted
## 外部编辑器（VS Code 系）候选可执行文件来源。
## [member win] / [member mac] 为相对安装根目录的路径；[member linux] 为绝对路径（[code]~[/code] 前缀替换为 HOME）。
## [member prefixes] / [member exes] 用于扫描安装根目录下名称匹配的变体目录（如 CodeBuddy CN、Trae CN）。
## 均为 VS Code 系命令行：目录参数与 {project} / {file} --goto 通用。

## 本文件位于 .gdignore 目录，类名不会注册，故以 load 自引用方式构造实例。
const _SELF_PATH: String = "res://addons/gdframe/editor/external_editor_ide.gd"

var id: String
var label: String
var cli: PackedStringArray
var prefixes: PackedStringArray
var exes: PackedStringArray
var win: PackedStringArray
var mac: PackedStringArray
var linux: PackedStringArray

static var _all: Array = []


func _init(
	p_id: String,
	p_label: String,
	p_cli: PackedStringArray,
	p_prefixes: PackedStringArray,
	p_exes: PackedStringArray,
	p_win: PackedStringArray,
	p_mac: PackedStringArray,
	p_linux: PackedStringArray,
) -> void:
	id = p_id
	label = p_label
	cli = p_cli
	prefixes = p_prefixes
	exes = p_exes
	win = p_win
	mac = p_mac
	linux = p_linux


static func all() -> Array:
	if _all.is_empty():
		var ide_script = load(_SELF_PATH)
		_all = [
			ide_script.new(
				"vscode",
				"VS Code",
				PackedStringArray(["code", "code.cmd", "code.exe"]),
				PackedStringArray(["microsoft vs code", "visual studio code", "vscode"]),
				PackedStringArray(["Code.exe"]),
				PackedStringArray([
					"Programs/Microsoft VS Code/Code.exe",
					"Microsoft VS Code/Code.exe",
				]),
				PackedStringArray([
					"Visual Studio Code.app/Contents/Resources/app/bin/code",
					"Visual Studio Code.app/Contents/MacOS/Electron",
					"Code.app/Contents/Resources/app/bin/code",
					"Code.app/Contents/MacOS/Electron",
				]),
				PackedStringArray([
					"~/.local/bin/code",
					"/usr/bin/code",
					"/usr/share/code/bin/code",
					"/snap/bin/code",
				]),
			),
			ide_script.new(
				"cursor",
				"Cursor",
				PackedStringArray(["cursor", "cursor.cmd", "cursor.exe"]),
				PackedStringArray(["cursor"]),
				PackedStringArray(["Cursor.exe"]),
				PackedStringArray([
					"Programs/cursor/Cursor.exe",
					"Programs/Cursor/Cursor.exe",
					"Cursor/Cursor.exe",
				]),
				PackedStringArray([
					"Cursor.app/Contents/MacOS/Cursor",
					"Cursor.app/Contents/Resources/app/bin/cursor",
				]),
				PackedStringArray(["~/.local/bin/cursor", "/usr/bin/cursor", "/usr/share/cursor/cursor"]),
			),
			ide_script.new(
				"codebuddy",
				"CodeBuddy",
				PackedStringArray(["codebuddy"]),
				PackedStringArray(["codebuddy"]),
				PackedStringArray(["CodeBuddy.exe", "CodeBuddy CN.exe", "CodeBuddy IDE.exe"]),
				PackedStringArray([
					"Programs/CodeBuddy/CodeBuddy.exe",
					"Programs/CodeBuddy CN/CodeBuddy CN.exe",
					"Programs/CodeBuddy IDE/CodeBuddy IDE.exe",
					"CodeBuddy/CodeBuddy.exe",
					"CodeBuddy CN/CodeBuddy CN.exe",
					"CodeBuddy IDE/CodeBuddy IDE.exe",
				]),
				PackedStringArray([
					"CodeBuddy.app/Contents/MacOS/CodeBuddy",
					"CodeBuddy.app/Contents/Resources/app/bin/code",
					"CodeBuddy IDE.app/Contents/MacOS/CodeBuddy IDE",
					"CodeBuddy IDE.app/Contents/Resources/app/bin/code",
				]),
				PackedStringArray([
					"~/.local/bin/codebuddy",
					"/usr/bin/codebuddy",
					"/usr/share/codebuddy/codebuddy",
				]),
			),
			ide_script.new(
				"trae",
				"TRAE",
				PackedStringArray(["trae"]),
				PackedStringArray(["trae"]),
				PackedStringArray(["Trae.exe", "Trae CN.exe"]),
				PackedStringArray([
					"Programs/Trae/Trae.exe",
					"Programs/Trae CN/Trae CN.exe",
					"Programs/trae/Trae.exe",
					"Trae/Trae.exe",
					"Trae CN/Trae CN.exe",
				]),
				PackedStringArray([
					"Trae.app/Contents/MacOS/Trae",
					"Trae.app/Contents/Resources/app/bin/trae",
					"Trae CN.app/Contents/MacOS/Trae CN",
					"Trae CN.app/Contents/MacOS/Trae",
					"Trae CN.app/Contents/Resources/app/bin/trae",
				]),
				PackedStringArray(["~/.local/bin/trae", "/usr/bin/trae", "/usr/share/trae/trae"]),
			),
		]
	return _all


static func by_id(ide_id: String) -> RefCounted:
	for ide in all():
		if ide.id == ide_id:
			return ide
	return null


static func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for ide in all():
		out.append(ide.id)
	return out


## 本机候选路径：固定目录 + 安装目录扫描 + PATH 查找；重复项已去除。
func candidates() -> PackedStringArray:
	var os_name: String = OS.get_name()
	var out: PackedStringArray = PackedStringArray()
	out.append_array(_installed_paths(os_name))
	out.append_array(_scan_installs(os_name))
	out.append_array(_which_paths())
	# 扫描到的真实安装目录优先于 PATH 里的启动脚本（.cmd 无法被 create_process 直接执行）。
	return _unique(out)


func first_existing() -> String:
	for candidate: String in candidates():
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _installed_paths(os_name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	match os_name:
		"Windows":
			for install_root: String in [
				OS.get_environment("LOCALAPPDATA"),
				OS.get_environment("ProgramFiles"),
				OS.get_environment("ProgramFiles(x86)"),
			]:
				var base: String = install_root.replace("\\", "/").rstrip("/")
				if base.is_empty():
					continue
				for win_rel: String in win:
					out.append("%s/%s" % [base, win_rel])
		"macOS":
			var home: String = OS.get_environment("HOME").replace("\\", "/").rstrip("/")
			var app_roots: PackedStringArray = PackedStringArray(["/Applications"])
			if not home.is_empty():
				app_roots.append("%s/Applications" % home)
			for app_root: String in app_roots:
				for mac_rel: String in mac:
					out.append("%s/%s" % [app_root, mac_rel])
		_:
			var home_unix: String = OS.get_environment("HOME").replace("\\", "/").rstrip("/")
			for linux_path: String in linux:
				if not linux_path.begins_with("~"):
					out.append(linux_path)
					continue
				if not home_unix.is_empty():
					out.append("%s/%s" % [home_unix, linux_path.trim_prefix("~/")])
	return out


## 扫描安装根目录下与 IDE 名称前缀匹配的目录，适配不同发行版目录名（如 CodeBuddy CN、Trae CN）。
func _scan_installs(os_name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if prefixes.is_empty():
		return out
	match os_name:
		"Windows":
			for root: String in _windows_scan_roots():
				for dir_name: String in DirAccess.get_directories_at(root):
					if not _name_matches(dir_name):
						continue
					for exe_name: String in exes:
						out.append("%s/%s/%s" % [root, dir_name, exe_name])
		"macOS":
			for root: String in _mac_scan_roots():
				for dir_name: String in DirAccess.get_directories_at(root):
					if not dir_name.ends_with(".app"):
						continue
					var stem: String = dir_name.trim_suffix(".app")
					if not _name_matches(stem):
						continue
					var app_path: String = "%s/%s" % [root, dir_name]
					out.append("%s/Contents/MacOS/%s" % [app_path, stem])
					for exe_name: String in exes:
						out.append("%s/Contents/MacOS/%s" % [app_path, exe_name.get_basename()])
					for cli_name: String in cli:
						out.append("%s/Contents/Resources/app/bin/%s" % [app_path, cli_name])
		_:
			for root: String in ["/opt", "/usr/share"]:
				for dir_name: String in DirAccess.get_directories_at(root):
					if not _name_matches(dir_name):
						continue
					out.append("%s/%s/%s" % [root, dir_name, dir_name])
					for cli_name: String in cli:
						out.append("%s/%s/%s" % [root, dir_name, cli_name])
	return out


func _name_matches(dir_name: String) -> bool:
	var lower: String = dir_name.strip_edges().to_lower()
	for prefix: String in prefixes:
		if lower.begins_with(prefix):
			return true
	return false


func _windows_scan_roots() -> PackedStringArray:
	var roots: PackedStringArray = PackedStringArray()
	for env_name: String in ["LOCALAPPDATA", "ProgramFiles", "ProgramFiles(x86)"]:
		var base: String = OS.get_environment(env_name).replace("\\", "/").rstrip("/")
		if base.is_empty():
			continue
		if env_name == "LOCALAPPDATA":
			roots.append("%s/Programs" % base)
			roots.append(base)
		else:
			roots.append(base)
	var existing: PackedStringArray = PackedStringArray()
	for root: String in roots:
		if DirAccess.dir_exists_absolute(root) and not existing.has(root):
			existing.append(root)
	return existing


func _mac_scan_roots() -> PackedStringArray:
	var roots: PackedStringArray = PackedStringArray(["/Applications"])
	var home: String = OS.get_environment("HOME").replace("\\", "/").rstrip("/")
	if not home.is_empty():
		var user_apps: String = "%s/Applications" % home
		if DirAccess.dir_exists_absolute(user_apps):
			roots.append(user_apps)
	return roots


func _which_paths() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var finder: String = "where" if OS.get_name() == "Windows" else "which"
	for name: String in cli:
		var output: Array = []
		if OS.execute(finder, [name], output, true, false) != 0:
			continue
		for line_variant: Variant in output:
			for raw_line: String in str(line_variant).split("\n"):
				var line: String = raw_line.strip_edges().replace("\\", "/")
				if not line.is_empty() and FileAccess.file_exists(line):
					found.append(line)
	return found


static func _unique(paths: PackedStringArray) -> PackedStringArray:
	var seen: Dictionary = {}
	var out: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if seen.has(path):
			continue
		seen[path] = true
		out.append(path)
	return out
