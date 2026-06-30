extends RefCounted
class_name GDFrameExtManageList
## 扩展管理 Dock 列表数据（已安装 + ext_index.cfg 可安装项）。

const EXT_INDEX_FILE: String = "ext_index.cfg"
const EXT_INDEX_REF: String = "main"
const EXT_INDEX_FETCH_URL_GITHUB: String = (
	"https://raw.githubusercontent.com/ftyu3d/gdframe-ext/%s/%s"
	% [EXT_INDEX_REF, EXT_INDEX_FILE]
)
const EXT_INDEX_FETCH_URL_GITEE: String = (
	"https://gitee.com/ftyu3d/gdframe-ext/raw/%s/%s"
	% [EXT_INDEX_REF, EXT_INDEX_FILE]
)

const _VERSION_SERIES: Script = preload("res://addons/gdframe/editor/version_series.gd")
const _MODULE_META: Script = preload("res://addons/gdframe/editor/module_meta.gd")


static func ext_index_fetch_url(source: String) -> String:
	if source == "gitee":
		return EXT_INDEX_FETCH_URL_GITEE
	return EXT_INDEX_FETCH_URL_GITHUB


static func build_manage_list(ext_index: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = _merge_installed_with_ext_index(ext_index)
	var installed_ids: Dictionary = {}
	for info: Dictionary in result:
		var ext_id: String = str(info.get("id", ""))
		if not ext_id.is_empty():
			installed_ids[ext_id] = true
	if not _ext_index_has_extensions(ext_index):
		return result
	var extensions_by_id: Dictionary = ext_index.get("extensions_by_id", {})
	for ext_id: Variant in extensions_by_id.keys():
		var ext_key: String = str(ext_id)
		if ext_key.is_empty() or installed_ids.has(ext_key):
			continue
		var supported: Dictionary = extensions_by_id[ext_key]
		var enriched: Dictionary = _enrich_ext_index_only(ext_key, supported, ext_index)
		if enriched.is_empty():
			continue
		result.append(enriched)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_installed: bool = bool(a.get("installed", false))
		var b_installed: bool = bool(b.get("installed", false))
		if a_installed != b_installed:
			return a_installed
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


static func supported_map_for_ext(ext_index: Dictionary, ext_id: String) -> Dictionary:
	var extensions_by_id: Dictionary = ext_index.get("extensions_by_id", {})
	if not extensions_by_id.has(ext_id):
		return {}
	var per_series: Variant = extensions_by_id[ext_id]
	if per_series is not Dictionary:
		return {}
	return _entries_to_supported(per_series as Dictionary)


static func _merge_installed_with_ext_index(ext_index: Dictionary) -> Array[Dictionary]:
	var infos: Array[Dictionary] = _MODULE_META.collect_infos()
	for info: Dictionary in infos:
		info["installed"] = true
		_apply_installed_module_meta(info)
		if not _ext_index_has_extensions(ext_index):
			info["supported_entries"] = []
			info["selection_status"] = "unknown"
			info["default_version"] = str(info.get("version", ""))
			continue
		var ext_id: String = str(info.get("id", ""))
		var supported: Dictionary = supported_map_for_ext(ext_index, ext_id)
		_apply_supported_fields(info, supported, ext_index, str(info.get("version", "")))
	return infos


static func _apply_installed_module_meta(info: Dictionary) -> void:
	var ext_dir: String = str(info.get("ext_dir", ""))
	if ext_dir.is_empty():
		return
	var meta: Dictionary = _MODULE_META.read_cfg(ext_dir)
	info["has_module_cfg"] = not meta.is_empty()
	if meta.is_empty():
		return
	var cfg_name: String = str(meta.get("name", "")).strip_edges()
	if not cfg_name.is_empty():
		info["name"] = cfg_name
	var cfg_version: String = str(meta.get("version", "")).strip_edges()
	if not cfg_version.is_empty():
		info["version"] = cfg_version


static func _enrich_ext_index_only(
	ext_id: String,
	per_series: Dictionary,
	ext_index: Dictionary,
) -> Dictionary:
	var supported: Dictionary = _entries_to_supported(per_series)
	if supported.is_empty():
		return {}
	var resolved: Dictionary = _VERSION_SERIES.resolve_selection(
		"",
		supported,
		_VERSION_SERIES.default_series_for_ext(ext_index, ext_id),
	)
	return {
		"id": ext_id,
		"name": _display_name_from_supported(supported),
		"version": "",
		"dir_name": ext_id,
		"ext_dir": "",
		"module_path": "",
		"facade_count": 0,
		"profile_count": 0,
		"capabilities": PackedStringArray(),
		"has_module_cfg": false,
		"installed": false,
		"supported": supported,
		"supported_entries": _VERSION_SERIES.sorted_supported_entries(supported),
		"selection_status": str(resolved.get("status", "not_installed")),
		"default_version": str(resolved.get("default_version", "")),
	}


static func _apply_supported_fields(
	info: Dictionary,
	supported: Dictionary,
	ext_index: Dictionary,
	local_version: String,
) -> void:
	info["supported"] = supported
	info["supported_entries"] = _VERSION_SERIES.sorted_supported_entries(supported)
	if supported.is_empty():
		info["selection_status"] = "unknown"
		info["default_version"] = local_version
		return
	var resolved: Dictionary = _VERSION_SERIES.resolve_selection(
		local_version,
		supported,
		_VERSION_SERIES.default_series_for_ext(ext_index, str(info.get("id", ""))),
	)
	info["selection_status"] = str(resolved.get("status", "unknown"))
	info["default_version"] = str(resolved.get("default_version", local_version))


static func _entries_to_supported(per_series: Dictionary) -> Dictionary:
	var supported: Dictionary = {}
	for series_key: Variant in per_series.keys():
		if per_series[series_key] is not Dictionary:
			continue
		var entry: Dictionary = (per_series[series_key] as Dictionary).duplicate()
		entry["series"] = str(entry.get("series", series_key))
		supported[str(entry.get("series", series_key))] = entry
	return supported


static func _display_name_from_supported(supported: Dictionary) -> String:
	for key: Variant in supported.keys():
		if supported[key] is not Dictionary:
			continue
		var name: String = str((supported[key] as Dictionary).get("name", "")).strip_edges()
		if not name.is_empty():
			return name
	return ""


static func _ext_index_has_extensions(ext_index: Dictionary) -> bool:
	if ext_index.is_empty() or ext_index.has("error"):
		return false
	return not (ext_index.get("extensions_by_id", {}) as Dictionary).is_empty()
