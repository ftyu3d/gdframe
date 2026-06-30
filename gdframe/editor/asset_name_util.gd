extends RefCounted
class_name GDFrameAssetNameUtil
## UI / FSM / 扩展模块 id 规范化（Dock 脚手架与重命名共用）。


static func clean_alnum_underscore(raw_name: String) -> String:
	var name: String = raw_name.strip_edges().to_lower()
	for sep: String in [" ", "-", "."]:
		name = name.replace(sep, "_")
	var cleaned: String = ""
	for i: int in name.length():
		var ch: String = name[i]
		if ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cleaned += ch
	return cleaned


static func normalize_ui_name(raw_name: String) -> String:
	var cleaned: String = clean_alnum_underscore(raw_name)
	if cleaned.is_empty():
		cleaned = "ui_new"
	if not cleaned.begins_with("ui_"):
		cleaned = "ui_" + cleaned
	return cleaned


static func normalize_fsm_name(raw_name: String) -> String:
	var cleaned: String = clean_alnum_underscore(raw_name)
	if cleaned.is_empty():
		cleaned = "new"
	if not cleaned.begins_with("fsm_"):
		cleaned = "fsm_" + cleaned
	return cleaned


static func normalize_module_id(raw_name: String) -> String:
	var cleaned: String = ""
	for i: int in raw_name.length():
		var ch: String = raw_name[i]
		if ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cleaned += ch
		elif ch >= "A" and ch <= "Z":
			cleaned += ch.to_lower()
	if cleaned.is_empty():
		cleaned = "ext_new"
	if cleaned[0].is_valid_int():
		cleaned = "ext_" + cleaned
	return cleaned
