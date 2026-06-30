extends RefCounted
## 同步 [member GDFrameConfig.SIGNALS_SCRIPT_PATH] 的扩展信号段（[code]global_signals()[/code]）；
## 不改动 [member MARKER_CUSTOM_BEGIN] 以下用户手写区。框架信号仍在 [member GDFrameConfig.SIGNALS_BASE_PATH]。

const _MODULE_SCAN: Script = preload("res://addons/gdframe/runtime/ext/module_scan.gd")
const _MODULE_EDITOR_SCAN: Script = preload("res://addons/gdframe/editor/module_editor_scan.gd")

const MARKER_EXT_BEGIN: String = "## GDFrame generated extension signals — do not edit"
const MARKER_EXT_END: String = "## GDFrame generated extension signals end"
const MARKER_CUSTOM_BEGIN: String = "# --- 业务自定义信号（可编辑）---"


static func skeleton_template() -> String:
	return _build_signals_script([], "")


static func generate_all() -> Dictionary:
	return generate_from_modules(_MODULE_SCAN.load_modules())


static func generate_from_modules(modules: Array[Script]) -> Dictionary:
	var ext_signals: Array[Dictionary] = _collect_ext_signals(modules)
	var custom_section: String = _read_custom_section()
	var content: String = _build_signals_script(ext_signals, custom_section)
	if content.is_empty():
		return {
			"ok": false,
			"changed": false,
			"message": "gdframe_signals.gd 生成内容无效。",
			"content": "",
		}
	var ext_count: int = ext_signals.size()
	var changed: bool = _should_write(content)
	var msg: String
	if changed:
		msg = "已同步扩展信号至 gdframe_signals.gd（%d 个信号）。" % ext_count
		if ext_count == 0:
			msg = "已同步 gdframe_signals.gd（当前无 global_signals）。"
	else:
		msg = "gdframe_signals.gd 已是最新（%d 个扩展信号）。" % ext_count
	return {
		"ok": true,
		"changed": changed,
		"message": msg,
		"content": content,
	}


static func _collect_ext_signals(modules: Array[Script]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for mod: Script in modules:
		var raw: Variant = _MODULE_EDITOR_SCAN.call_editor_method(mod, &"global_signals")
		if raw == null or not raw is Array:
			continue
		var module_id: String = mod.resource_path.get_base_dir().get_file()
		for entry: Variant in raw:
			var decl: String = _signal_declaration(entry)
			if decl.is_empty():
				continue
			var sig_name: String = _parse_signal_name(decl)
			if sig_name.is_empty():
				continue
			if seen.has(sig_name):
				push_warning(
					"GDFrame signals: 重复信号 %s（跳过模块 %s）" % [sig_name, module_id]
				)
				continue
			seen[sig_name] = true
			out.append({
				"module_id": module_id,
				"declaration": decl,
			})
	return out


static func _signal_declaration(entry: Variant) -> String:
	if entry is String:
		return String(entry).strip_edges()
	if entry is Dictionary:
		return str(entry.get("declaration", "")).strip_edges()
	return ""


static func _parse_signal_name(declaration: String) -> String:
	var trimmed: String = declaration.strip_edges()
	if not trimmed.begins_with("signal "):
		return ""
	var rest: String = trimmed.substr(7).strip_edges()
	var paren: int = rest.find("(")
	if paren >= 0:
		return rest.substr(0, paren).strip_edges()
	return rest.strip_edges()


static func _build_signals_script(ext_signals: Array[Dictionary], custom_section: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("## GDFrame 全局信号（业务侧）。命名：snake_case，以 signal_ 开头。")
	lines.append("## 框架内置信号：%s" % GDFrameConfig.SIGNALS_BASE_PATH)
	lines.append("## 用法：GDFrame.signal_example.connect / GDFrame.signal_example.emit")
	lines.append("extends \"%s\"" % GDFrameConfig.SIGNALS_BASE_PATH)
	lines.append("")
	lines.append("@warning_ignore_start(\"unused_signal\")")
	lines.append("")
	lines.append(MARKER_CUSTOM_BEGIN)
	if custom_section.is_empty():
		lines.append(_default_custom_body())
	else:
		lines.append(custom_section)
	lines.append("")
	lines.append(MARKER_EXT_BEGIN)
	if ext_signals.is_empty():
		lines.append("# （当前已安装模块无 global_signals）")
	else:
		var last_module: String = ""
		for entry: Dictionary in ext_signals:
			var module_id: String = String(entry.get("module_id", ""))
			if module_id != last_module:
				if not last_module.is_empty():
					lines.append("")
				lines.append(
					"# --- 扩展 %s（ext/%s）---" % [module_id, module_id]
				)
				last_module = module_id
			lines.append(String(entry.get("declaration", "")))
	lines.append(MARKER_EXT_END)
	lines.append("")
	lines.append("@warning_ignore_restore(\"unused_signal\")")
	return "\n".join(lines) + "\n"


static func _default_custom_body() -> String:
	return "# signal signal_example(example_id: int, example_name: String)"


static func _read_custom_section() -> String:
	var existing: String = _read_existing_script()
	if existing.is_empty():
		return ""
	var custom_idx: int = existing.find(MARKER_CUSTOM_BEGIN)
	if custom_idx < 0:
		return ""
	var after_custom: String = existing.substr(custom_idx + MARKER_CUSTOM_BEGIN.length())
	var ext_idx: int = after_custom.find(MARKER_EXT_BEGIN)
	var slice: String = after_custom
	if ext_idx >= 0:
		slice = after_custom.substr(0, ext_idx)
	return _strip_warning_ignore_decorators(slice.strip_edges())


static func _strip_warning_ignore_decorators(text: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n", false):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("@warning_ignore"):
			continue
		out.append(line)
	return "\n".join(out).strip_edges()


static func _read_existing_script() -> String:
	var abs_path: String = ProjectSettings.globalize_path(GDFrameConfig.SIGNALS_SCRIPT_PATH)
	if not FileAccess.file_exists(abs_path):
		return ""
	return FileAccess.get_file_as_string(abs_path)


static func _should_write(content: String) -> bool:
	var abs_path: String = ProjectSettings.globalize_path(GDFrameConfig.SIGNALS_SCRIPT_PATH)
	if not FileAccess.file_exists(abs_path):
		return true
	return FileAccess.get_file_as_string(abs_path) != content
