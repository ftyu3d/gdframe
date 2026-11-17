extends RefCounted
## profile 字段清单：解析 [code]profile_settings_data.gd[/code] 里的 [code]@export[/code]，
## 区分业务自定义段（可编辑）与扩展生成段（只读），并补上尚未生成进脚本的
## 模块 [code]profile_fields()[/code]。
##
## 本脚本位于 [code]editor/[/code]（含 [code].gdignore[/code]），只能通过 preload 使用。

const KIND_PROFILE_FIELD: StringName = &"profile_field"
const SCRIPT_PATH: String = GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH

const MARKER_GEN_BEGIN: String = "## GDFrame generated profile fields — do not edit"
const MARKER_GEN_END: String = "## GDFrame generated profile fields end"
const MARKER_CUSTOM_BEGIN: String = "# --- 业务自定义 profile 字段（可编辑）---"

## 「新建字段」下拉里可选的类型（都是 [code]@export[/code] 能直接用的基础类型）。
const TYPE_OPTIONS: PackedStringArray = [
	"bool",
	"int",
	"float",
	"String",
	"Dictionary",
	"Array",
]

const _MODULE_EDITOR_SCAN: Script = preload("res://addons/gdframe/editor/module_editor_scan.gd")

const _REGION_TAIL: int = 2
const _REGION_CUSTOM: int = 1
const _REGION_GENERATED: int = 0

static var _cached_core_names: PackedStringArray


## 全部 profile 字段：脚本里已有的（自定义段可删、生成段只读）+ 模块声明但还没生成的（只读）。
static func items(modules: Array[Script]) -> Array[Dictionary]:
	var out: Array[Dictionary] = script_fields()
	var seen: Dictionary = {}
	for field: Dictionary in out:
		seen[str(field.get("id", ""))] = true
	for entry: Dictionary in module_fields(modules):
		var field_name: String = str(entry.get("id", ""))
		if field_name.is_empty() or seen.has(field_name):
			continue
		seen[field_name] = true
		out.append(entry)
	return out


## 模块 [code]profile_fields()[/code] 声明、但脚本里还没生成出来的字段（只读）。
static func module_fields(modules: Array[Script]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mod: Script in modules:
		var raw: Variant = _MODULE_EDITOR_SCAN.call_editor_method(mod, &"profile_fields")
		if not raw is Array:
			continue
		for entry: Variant in raw:
			if not entry is Dictionary:
				continue
			var field: Dictionary = entry as Dictionary
			var field_name: String = str(field.get("name", "")).strip_edges()
			if field_name.is_empty():
				continue
			out.append({
				"id": field_name,
				"kind": KIND_PROFILE_FIELD,
				"title": field_name,
				"type": str(field.get("type", "Variant")),
				"default": _format_default_literal(
					field.get("default"), str(field.get("type", "Variant"))
				),
				"comment": str(field.get("comment", field.get("summary", ""))).strip_edges(),
				"line": 0,
				"source": "",
				"owner_title": module_title(mod),
				"owner_source": mod.resource_path,
				"locked": true,
			})
	return out


## 解析脚本里现有的 [code]@export[/code] 字段。
static func script_fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var abs_path: String = ProjectSettings.globalize_path(SCRIPT_PATH)
	if not FileAccess.file_exists(abs_path):
		return out
	var text: String = FileAccess.get_file_as_string(abs_path)
	var lines: PackedStringArray = text.split("\n")
	var region: int = _REGION_TAIL
	for index: int in range(lines.size()):
		var trimmed: String = lines[index].strip_edges()
		if trimmed == MARKER_GEN_BEGIN:
			region = _REGION_GENERATED
			continue
		if trimmed == MARKER_GEN_END:
			region = _REGION_TAIL
			continue
		if trimmed == MARKER_CUSTOM_BEGIN:
			region = _REGION_CUSTOM
			continue
		if not trimmed.begins_with("@export var "):
			continue
		var parsed: Dictionary = _parse_export_line(trimmed)
		if parsed.is_empty():
			continue
		parsed["kind"] = KIND_PROFILE_FIELD
		parsed["title"] = str(parsed.get("id", ""))
		parsed["comment"] = _comment_before(lines, index)
		parsed["line"] = index + 1
		parsed["source"] = SCRIPT_PATH
		parsed["owner_title"] = "" if region != _REGION_GENERATED else "扩展生成"
		parsed["owner_source"] = ""
		parsed["locked"] = region == _REGION_GENERATED
		out.append(parsed)
	return out


## 只取 [code]@export var[/code] 紧贴的上一行 [code]##[/code] 注释作为该项说明，
## 再往上的多行注释不收集。
static func _comment_before(lines: PackedStringArray, index: int) -> String:
	var cursor: int = index - 1
	if cursor < 0 or cursor >= lines.size():
		return ""
	var line: String = lines[cursor].strip_edges()
	if not line.begins_with("##"):
		return ""
	return line.trim_prefix("##").strip_edges()


## 在业务自定义段追加一个字段（类型与默认值已在调用侧校验过）。
static func append_field(field_name: String, type_name: String, default_literal: String) -> Error:
	var clean_name: String = field_name.strip_edges()
	if clean_name.is_empty():
		return ERR_INVALID_PARAMETER
	var abs_path: String = ProjectSettings.globalize_path(SCRIPT_PATH)
	if not FileAccess.file_exists(abs_path):
		return ERR_FILE_NOT_FOUND
	var text: String = FileAccess.get_file_as_string(abs_path)
	var lines: PackedStringArray = text.split("\n")
	var insert_at: int = -1
	for index: int in range(lines.size()):
		if lines[index].strip_edges() == MARKER_CUSTOM_BEGIN:
			insert_at = index + 1
			break
	if insert_at < 0:
		return ERR_FILE_CORRUPT
	var literal: String = default_literal.strip_edges()
	if literal.is_empty():
		literal = _default_literal(type_name)
	var new_lines: PackedStringArray = PackedStringArray()
	for index: int in range(lines.size()):
		if index == insert_at:
			new_lines.append("@export var %s: %s = %s" % [clean_name, type_name, literal])
		new_lines.append(lines[index])
	if insert_at >= lines.size():
		new_lines.append("@export var %s: %s = %s" % [clean_name, type_name, literal])
	return _write_text(abs_path, "\n".join(new_lines))


## 删除业务自定义段里的字段（连同紧贴在它上方的注释行）。生成段字段不可删。
static func delete_field(field_name: String) -> Error:
	var abs_path: String = ProjectSettings.globalize_path(SCRIPT_PATH)
	if not FileAccess.file_exists(abs_path):
		return ERR_FILE_NOT_FOUND
	var text: String = FileAccess.get_file_as_string(abs_path)
	var lines: PackedStringArray = text.split("\n")
	var region: int = _REGION_TAIL
	var target: int = -1
	for index: int in range(lines.size()):
		var trimmed: String = lines[index].strip_edges()
		if trimmed == MARKER_GEN_BEGIN:
			region = _REGION_GENERATED
			continue
		if trimmed == MARKER_GEN_END:
			region = _REGION_TAIL
			continue
		if trimmed == MARKER_CUSTOM_BEGIN:
			region = _REGION_CUSTOM
			continue
		if region != _REGION_CUSTOM or not trimmed.begins_with("@export var "):
			continue
		var parsed: Dictionary = _parse_export_line(trimmed)
		if str(parsed.get("id", "")) == field_name:
			target = index
			break
	if target < 0:
		return ERR_DOES_NOT_EXIST
	var start: int = target
	while start > 0:
		var above: String = lines[start - 1].strip_edges()
		if not above.begins_with("#") or above.begins_with("# -"):
			break
		start -= 1
	var new_lines: PackedStringArray = PackedStringArray()
	for index: int in range(lines.size()):
		if index >= start and index <= target:
			continue
		new_lines.append(lines[index])
	return _write_text(abs_path, "\n".join(new_lines))


static func field_exists(field_name: String) -> bool:
	for field: Dictionary in script_fields():
		if str(field.get("id", "")) == field_name:
			return true
	return false


## 校验字段名是否是合法的 GDScript 标识符且不撞现有字段/核心字段。
static func validate_new_name(field_name: String) -> String:
	var clean_name: String = field_name.strip_edges()
	if clean_name.is_empty():
		return "字段名不能为空。"
	for i: int in range(clean_name.length()):
		var ch: String = clean_name[i]
		var is_head: bool = i == 0
		var ok_char: bool = ch.to_lower() != ch.to_upper()
		ok_char = ok_char or ch == "_" or ch.is_valid_int()
		if is_head and ch.is_valid_int():
			ok_char = false
		if not ok_char:
			return "字段名只能使用字母、数字与下划线，且不能以数字开头。"
	if _core_field_names().has(clean_name):
		return "%s 与核心设置字段重名。" % clean_name
	if field_exists(clean_name):
		return "字段 %s 已存在。" % clean_name
	return ""


## 核心设置字段名（[code]GDFrameSettingsData[/code] 的导出属性），只取一次。
static func _core_field_names() -> PackedStringArray:
	if not _cached_core_names.is_empty():
		return _cached_core_names
	var base_script: Script = GDFrameSettingsData
	for prop: Dictionary in base_script.get_script_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty():
			continue
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		_cached_core_names.append(prop_name)
	return _cached_core_names


## 解析一行 [code]@export var name: Type = default[/code]。
static func _parse_export_line(trimmed: String) -> Dictionary:
	var rest: String = trimmed.trim_prefix("@export var ").strip_edges()
	var colon: int = rest.find(":")
	if colon <= 0:
		return {}
	var field_name: String = rest.substr(0, colon).strip_edges()
	if field_name.is_empty():
		return {}
	var after: String = rest.substr(colon + 1).strip_edges()
	var type_name: String = after
	var default_literal: String = ""
	var assign: int = after.find("=")
	if assign >= 0:
		type_name = after.substr(0, assign).strip_edges()
		default_literal = after.substr(assign + 1).strip_edges()
	return {
		"id": field_name,
		"type": type_name,
		"default": default_literal,
	}


static func _default_literal(type_name: String) -> String:
	match type_name:
		"bool":
			return "false"
		"int":
			return "0"
		"float":
			return "0.0"
		"String":
			return '""'
		"Dictionary":
			return "{}"
		"Array":
			return "[]"
		_:
			return "null"


static func _format_default_literal(default_value: Variant, type_name: String) -> String:
	if default_value == null:
		return _default_literal(type_name)
	if default_value is bool:
		return "true" if default_value else "false"
	if default_value is int:
		return str(default_value)
	if default_value is float:
		return str(default_value)
	if default_value is String:
		return '"%s"' % (default_value as String).c_escape()
	if default_value is Dictionary:
		return "{}"
	if default_value is Array:
		return "[]"
	return str(default_value)


static func _write_text(abs_path: String, content: String) -> Error:
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK


static func module_title(mod: Script) -> String:
	var cfg_path: String = mod.resource_path.get_base_dir().path_join("plugin.cfg")
	var abs_path: String = ProjectSettings.globalize_path(cfg_path)
	if FileAccess.file_exists(abs_path):
		var cfg: ConfigFile = ConfigFile.new()
		if cfg.load(abs_path) == OK:
			var display: String = str(cfg.get_value("plugin", "name", "")).strip_edges()
			if not display.is_empty():
				return display
	return mod.resource_path.get_base_dir().get_file()
