@tool
extends RefCounted

const Candidates = preload("external_editor_ide.gd")
const State = preload("editor_state.gd")
const ENABLED := "text_editor/external/use_external_editor"
const EXECUTABLE := "text_editor/external/exec_path"


static func is_enabled() -> bool:
	return EditorInterface.get_editor_settings().get_setting(ENABLED)


static func can_open_folder() -> bool:
	return is_enabled() and not str(EditorInterface.get_editor_settings().get_setting(EXECUTABLE)).is_empty()


static func configure(id: String) -> String:
	var settings := EditorInterface.get_editor_settings()
	if id.is_empty():
		settings.set_setting(ENABLED, false)
		return "已关闭外部 IDE，脚本将使用 Godot 内置编辑器打开。"
	var ide := Candidates.by_id(id)
	if ide == null:
		return "未知 IDE。"
	var path := _detect(ide)
	if path.is_empty():
		return "未找到 %s，请在编辑器设置 → 文本编辑器 → 外部填写执行路径。" % ide.label
	settings.set_setting(EXECUTABLE, path)
	settings.set_setting("text_editor/external/exec_flags", '{project} --goto {file}:{line}:{col}')
	State.set_external_editor_ide(id)
	settings.set_setting(ENABLED, true)
	return "已配置 %s：%s" % [ide.label, path]


static func open_folder(path: String) -> String:
	if not can_open_folder():
		return "请先选择并应用外部 IDE。"
	var executable := str(EditorInterface.get_editor_settings().get_setting(EXECUTABLE))
	var pid := OS.create_process(executable, PackedStringArray([path]))
	return "已打开外部 IDE。" if pid != -1 else "外部 IDE 启动失败。"


static func _detect(ide: RefCounted) -> String:
	var candidates: PackedStringArray = []
	if OS.get_name() == "Windows":
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
	for folder in OS.get_environment("PATH").split(";" if OS.get_name() == "Windows" else ":"):
		for executable: String in ide.cli:
			if not executable.ends_with(".cmd"):
				candidates.append(folder.path_join(executable))
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
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
