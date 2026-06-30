extends RefCounted
class_name GDFrameModuleEditorScan
## 加载扩展 [code]editor/module_editor.gd[/code]（[code].gdignore[/code] 目录内；仅编辑器生成 API 用）。

const MODULE_EDITOR_DIR: String = "editor"
const MODULE_EDITOR_SCRIPT: String = "module_editor.gd"


static func editor_script_path(ext_dir: String) -> String:
	return ext_dir.path_join(MODULE_EDITOR_DIR).path_join(MODULE_EDITOR_SCRIPT)


static func load_editor_script(module_script: Script) -> Script:
	if module_script == null:
		return null
	var res_path: String = editor_script_path(module_script.resource_path.get_base_dir())
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var gd: GDScript = GDScript.new()
	gd.source_code = FileAccess.get_file_as_string(abs_path)
	if gd.reload() != OK:
		push_warning("GDFrame: 无法解析 %s" % res_path)
		return null
	return gd


static func call_editor_method(module_script: Script, method: StringName) -> Variant:
	var editor_script: Script = load_editor_script(module_script)
	if editor_script == null or not editor_script.has_method(method):
		return null
	return editor_script.call(method)
