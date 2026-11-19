@tool
extends RefCounted

const Candidates = preload("external_editor_ide.gd")
const State = preload("editor_state.gd")
const ENABLED := "text_editor/external/use_external_editor"
const EXECUTABLE := "text_editor/external/exec_path"


static func is_enabled() -> bool:
	return EditorInterface.get_editor_settings().get_setting(ENABLED)


static func can_open_folder() -> bool:
	var path := str(EditorInterface.get_editor_settings().get_setting(EXECUTABLE))
	return is_enabled() and not path.is_empty() and (OS.get_name() != "Windows" or _is_windows_executable(path))


static func restore_project_preference() -> void:
	var ide := Candidates.by_id(State.get_external_editor_ide())
	if ide != null:
		var path := _detect(ide)
		if not path.is_empty():
			_enable(path)
			return
	EditorInterface.get_editor_settings().set_setting(ENABLED, false)


static func configure(id: String) -> String:
	var settings := EditorInterface.get_editor_settings()
	if id.is_empty():
		State.set_external_editor_ide("")
		settings.set_setting(ENABLED, false)
		return "已关闭外部 IDE，脚本将使用 Godot 内置编辑器打开。"
	var ide := Candidates.by_id(id)
	if ide == null:
		return "未知 IDE。"
	var path := _detect(ide)
	if path.is_empty():
		return "未找到 %s，请在编辑器设置 → 文本编辑器 → 外部填写执行路径。" % ide.label
	State.set_external_editor_ide(id)
	_enable(path)
	return "已配置 %s：%s" % [ide.label, path]


static func _enable(path: String) -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(EXECUTABLE, path)
	settings.set_setting("text_editor/external/exec_flags", '{project} --goto {file}:{line}:{col}')
	settings.set_setting(ENABLED, true)


static func open_folder(path: String) -> String:
	repair_configured_windows_ide()
	if not can_open_folder():
		return "请先选择并应用外部 IDE。"
	var executable := str(EditorInterface.get_editor_settings().get_setting(EXECUTABLE))
	var pid := OS.create_process(executable, PackedStringArray([path]))
	return "已打开外部 IDE。" if pid != -1 else "外部 IDE 启动失败。"


static func repair_configured_windows_ide() -> void:
	if OS.get_name() != "Windows" or not is_enabled():
		return
	var settings := EditorInterface.get_editor_settings()
	if _is_windows_executable(str(settings.get_setting(EXECUTABLE))):
		return
	var ide := Candidates.by_id(State.get_external_editor_ide())
	if ide == null:
		return
	var executable := _detect(ide)
	if not executable.is_empty():
		settings.set_setting(EXECUTABLE, executable)


static func _detect(ide: RefCounted) -> String:
	var candidates: PackedStringArray = []
	var windows := OS.get_name() == "Windows"
	if windows:
		var saved_path := str(EditorInterface.get_editor_settings().get_setting(EXECUTABLE)).replace("\\", "/")
		var filename := saved_path.get_file()
		var matches_executable := Array(ide.exes).any(func(exe: String) -> bool: return filename.nocasecmp_to(exe) == 0)
		if matches_executable and _is_windows_executable(saved_path):
			return saved_path
		if filename.to_lower() in ide.cli:
			var repaired := _windows_executable_near(saved_path.get_base_dir(), ide)
			if not repaired.is_empty():
				return repaired
		for key in ["LOCALAPPDATA", "ProgramFiles", "ProgramFiles(x86)"]:
			var base := OS.get_environment(key)
			if base.is_empty():
				continue
			for relative: String in ide.win:
				candidates.append(base.path_join(relative))
			_add_windows_candidates(base, ide, candidates)
			_add_windows_candidates(base.path_join("Programs"), ide, candidates)
	elif OS.get_name() == "macOS":
		for relative: String in ide.mac:
			candidates.append("/Applications".path_join(relative))
			candidates.append(OS.get_environment("HOME").path_join("Applications").path_join(relative))
	else:
		for path: String in ide.linux:
			candidates.append(path.replace("~", OS.get_environment("HOME")))
	for entry in OS.get_environment("PATH").split(";" if windows else ":", false):
		var folder := entry.strip_edges().trim_prefix('"').trim_suffix('"')
		if folder.is_empty():
			continue
		if windows:
			for executable: String in ide.exes:
				candidates.append(folder.path_join(executable))
			# VS Code 系 IDE 的 PATH 通常指向 resources/app/bin，里面只有 CLI 包装脚本。
			for launcher: String in ide.cli:
				if FileAccess.file_exists(folder.path_join(launcher)):
					var executable := _windows_executable_near(folder, ide)
					if not executable.is_empty():
						candidates.append(executable)
					break
			continue
		for executable: String in ide.cli:
			if not executable.ends_with(".cmd"):
				candidates.append(folder.path_join(executable))
	for path in candidates:
		var executable_exists := _is_windows_executable(path) if windows else FileAccess.file_exists(path)
		if executable_exists:
			return path
	return ""


static func _is_windows_executable(path: String) -> bool:
	return path.get_extension().to_lower() in ["exe", "com"] and FileAccess.file_exists(path)


static func _windows_executable_near(folder: String, ide: RefCounted) -> String:
	# resources/app/bin 到安装根目录是三层，限制向上搜索的范围。
	folder = folder.replace("\\", "/")
	for _level in range(4):
		if folder.is_empty():
			break
		for name_text: String in ide.exes:
			var executable := folder.path_join(name_text)
			if _is_windows_executable(executable):
				return executable
		var parent := folder.get_base_dir()
		if parent == folder:
			break
		folder = parent
	return ""


static func _add_windows_candidates(path: String, ide: RefCounted, candidates: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for folder in directory.get_directories():
		for prefix: String in ide.prefixes:
			if folder.to_lower().begins_with(prefix):
				for executable: String in ide.exes:
					candidates.append(path.path_join(folder).path_join(executable))
				break
