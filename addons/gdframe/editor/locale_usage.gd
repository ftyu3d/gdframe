@tool
extends RefCounted
## A read-only index of translation references in the project's text sources.

const SOURCE_EXTENSIONS := ["gd", "cs", "tscn", "tres", "cfg", "godot", "json"]
const STRINGS := r"""(?<text>"{3}(?:\\[\s\S]|(?!"{3})[\s\S])*"{3}|'{3}(?:\\[\s\S]|(?!'{3})[\s\S])*'{3}|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*')"""
const FORMAT_SLOT := r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?[sdifvouxXc]|(?<!\{)\{(?:[0-9]+|[a-zA-Z_][a-zA-Z_0-9]*)?(?:\:[^{}\r\n]+)?\}(?!\})"

var _root: String
var _pending: PackedStringArray
var _exact := {}
var _prefixes := {}
var _script_tokens := RegEx.new()
var _csharp_tokens := RegEx.new()
var _resource_tokens := RegEx.new()
var _json_tokens := RegEx.new()
var _format_slot := RegEx.new()
var skipped_files := 0


func _init(root := "res://") -> void:
	_root = root
	_pending = PackedStringArray([root])
	_script_tokens.compile(r"#[^\r\n]*|" + STRINGS)
	_csharp_tokens.compile(r"//[^\r\n]*|/\*[\s\S]*?\*/|" + STRINGS)
	_resource_tokens.compile(r";[^\r\n]*|" + STRINGS)
	_json_tokens.compile(STRINGS)
	_format_slot.compile(FORMAT_SLOT)


## Process one directory or source file. The editor can yield between steps.
func step() -> bool:
	if _pending.is_empty():
		return false
	var path: String = _pending[-1]
	_pending.remove_at(_pending.size() - 1)
	if FileAccess.file_exists(path):
		_scan_file(path)
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		skipped_files += 1
		return true
	if FileAccess.file_exists(path.path_join(".gdignore")):
		return true
	for name in directory.get_directories():
		var child := path.path_join(name)
		if not name.begins_with(".") and not directory.is_link(name) and not _is_editor_tool(child):
			_pending.append(child)
	for name in directory.get_files():
		if not name.begins_with(".") and name.get_extension().to_lower() in SOURCE_EXTENSIONS and not directory.is_link(name):
			_pending.append(path.path_join(name))
	return true


func is_referenced(key: String) -> bool:
	if _exact.has(key):
		return true
	for length in range(3, key.length()):
		if _prefixes.has(key.left(length)):
			return true
	return false


func _is_editor_tool(path: String) -> bool:
	var relative := path.trim_prefix(_root).trim_prefix("/")
	var parts := relative.split("/")
	return parts.size() == 3 and parts[0] == "addons" and parts[1].begins_with("gdframe") and parts[2] == "editor"


func _scan_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		skipped_files += 1
		return
	var source := file.get_as_text()
	var tokens := _resource_tokens
	var script := path.get_extension().to_lower()
	match script:
		"gd": tokens = _script_tokens
		"cs": tokens = _csharp_tokens
		"json": tokens = _json_tokens
	for token: RegExMatch in tokens.search_all(source):
		var literal := token.get_string("text")
		if literal.length() < 2:
			continue
		var quote_size := 3 if literal.begins_with('"""') or literal.begins_with("'''") else 1
		var value := literal.substr(quote_size, literal.length() - quote_size * 2).c_unescape()
		if value.is_empty():
			continue
		_exact[value] = true
		var placeholder := _format_slot.search(value)
		if placeholder != null:
			_remember_prefix(value.left(placeholder.get_start()))
		elif script in ["gd", "cs"] and source.substr(token.get_end(), 32).strip_edges().begins_with("+"):
			_remember_prefix(value)


func _remember_prefix(prefix: String) -> void:
	if prefix.length() >= 3 and not prefix.contains("\n"):
		_prefixes[prefix] = true
