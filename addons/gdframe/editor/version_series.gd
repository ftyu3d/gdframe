extends RefCounted
class_name GDFrameVersionSeries
## SemVer minor 系列解析、plugin_index / ext_index 拉取流水线与更新目标选择。

const SERIES_PREFIX: String = "series."
const EXT_SERIES_MARKER: String = ".series."


## 将版本号规范为 Release 标签（[code]1.0.0[/code] → [code]v1.0.0[/code]）。
static func release_tag(version: String) -> String:
	var trimmed: String = version.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("v"):
		return trimmed
	return "v" + trimmed


static func minor_series(version: String) -> String:
	var trimmed: String = version.strip_edges()
	if trimmed.is_empty():
		return ""
	var parts: PackedStringArray = trimmed.split(".")
	if parts.size() >= 2:
		return parts[0] + "." + parts[1]
	if parts.size() == 1:
		return parts[0] + ".0"
	return ""


static func parse_cfg_text(text: String) -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	if text.is_empty():
		return null
	if cfg.parse(text) != OK:
		return null
	return cfg


static func _index_bucket_empty(parsed: Dictionary, nonempty_key: String) -> bool:
	var bucket: Variant = parsed.get(nonempty_key, {})
	return not (bucket is Dictionary) or (bucket as Dictionary).is_empty()


static func save_index_cfg_text(cache_path: String, text: String) -> bool:
	if cache_path.is_empty() or text.is_empty():
		return false
	var file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file = null
	return true


## 从本地缓存加载索引。[param parse_fn]：(ConfigFile) → Dictionary；[param nonempty_key]：判空键。
static func load_local_index_cfg(
	cache_path: String,
	parse_fn: Callable,
	nonempty_key: String,
) -> Dictionary:
	if cache_path.is_empty() or not FileAccess.file_exists(cache_path):
		return {"error": &"local_missing"}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(cache_path) != OK:
		return {"error": &"parse"}
	var parsed: Dictionary = parse_fn.call(cfg) as Dictionary
	if _index_bucket_empty(parsed, nonempty_key):
		return {"error": &"empty"}
	parsed["source"] = cache_path
	parsed["local"] = true
	return parsed


## 规范化并解析远端索引正文，成功则写入缓存并返回解析结果；失败返回 [code]{ "error": ... }[/code]。
static func parse_and_save_index_cfg(
	body: String,
	parse_fn: Callable,
	nonempty_key: String,
	cache_path: String,
) -> Dictionary:
	if body.is_empty():
		return {"error": &"parse"}
	var cfg: ConfigFile = parse_cfg_text(body)
	if cfg == null:
		return {"error": &"parse"}
	var parsed: Dictionary = parse_fn.call(cfg) as Dictionary
	if _index_bucket_empty(parsed, nonempty_key):
		return {"error": &"empty"}
	if not save_index_cfg_text(cache_path, body):
		return {"error": &"save"}
	return parsed


static func compare_versions(a: String, b: String) -> int:
	var av: PackedStringArray = a.split(".")
	var bv: PackedStringArray = b.split(".")
	var length: int = maxi(av.size(), bv.size())
	for i: int in range(length):
		var ai: int = _segment_int(av[i] if i < av.size() else "0")
		var bi: int = _segment_int(bv[i] if i < bv.size() else "0")
		if ai > bi:
			return 1
		if ai < bi:
			return -1
	return 0


static func is_newer(remote_version: String, local_version: String) -> bool:
	return compare_versions(remote_version, local_version) > 0


static func parse_plugin_index_cfg(cfg: ConfigFile) -> Dictionary:
	if cfg == null:
		return {"supported": {}, "default_series": ""}
	var supported: Dictionary = {}
	var default_series: String = str(cfg.get_value("meta", "default_series", ""))
	for section: String in cfg.get_sections():
		if not section.begins_with(SERIES_PREFIX):
			continue
		var series_key: String = section.substr(SERIES_PREFIX.length())
		if series_key.is_empty():
			continue
		supported[series_key] = {
			"series": series_key,
			"version": str(cfg.get_value(section, "version", "")),
			"deprecated": bool(cfg.get_value(section, "deprecated", false)),
		}
	return {"supported": supported, "default_series": default_series}


static func parse_ext_index_cfg(cfg: ConfigFile) -> Dictionary:
	if cfg == null:
		return {"extensions_by_id": {}, "extension_meta_by_id": {}, "default_series": ""}
	var extensions_by_id: Dictionary = {}
	var extension_meta_by_id: Dictionary = {}
	var default_series: String = str(cfg.get_value("meta", "default_series", ""))
	for section: String in cfg.get_sections():
		if section == "meta":
			continue
		var marker_pos: int = section.find(EXT_SERIES_MARKER)
		if marker_pos > 0:
			var ext_id: String = section.substr(0, marker_pos)
			var series_key: String = section.substr(marker_pos + EXT_SERIES_MARKER.length())
			if ext_id.is_empty() or series_key.is_empty():
				continue
			if not extensions_by_id.has(ext_id):
				extensions_by_id[ext_id] = {}
			extensions_by_id[ext_id][series_key] = {
				"id": ext_id,
				"series": series_key,
				"version": str(cfg.get_value(section, "version", "")),
				"name": str(cfg.get_value(section, "name", "")),
			}
			continue
		var meta_ext_id: String = section.strip_edges()
		if meta_ext_id.is_empty():
			continue
		var per_default_series: String = str(
			cfg.get_value(section, "default_series", "")
		).strip_edges()
		if per_default_series.is_empty():
			continue
		if not extension_meta_by_id.has(meta_ext_id):
			extension_meta_by_id[meta_ext_id] = {}
		extension_meta_by_id[meta_ext_id]["default_series"] = per_default_series
	return {
		"extensions_by_id": extensions_by_id,
		"extension_meta_by_id": extension_meta_by_id,
		"default_series": default_series,
	}


static func default_series_for_ext(ext_index: Dictionary, ext_id: String) -> String:
	var trimmed_id: String = ext_id.strip_edges()
	if trimmed_id.is_empty():
		return str(ext_index.get("default_series", "")).strip_edges()
	var meta_by_id: Dictionary = ext_index.get("extension_meta_by_id", {})
	if meta_by_id.has(trimmed_id) and meta_by_id[trimmed_id] is Dictionary:
		var per: String = str(
			(meta_by_id[trimmed_id] as Dictionary).get("default_series", "")
		).strip_edges()
		if not per.is_empty():
			return per
	return str(ext_index.get("default_series", "")).strip_edges()


static func sorted_supported_entries(supported: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: Variant in supported.keys():
		if supported[key] is Dictionary:
			entries.append((supported[key] as Dictionary).duplicate())
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return compare_versions(str(a.get("version", "")), str(b.get("version", ""))) < 0
	)
	return entries


static func resolve_selection(
	local_version: String,
	supported: Dictionary,
	default_series: String,
) -> Dictionary:
	var status: String = "up_to_date_in_series"
	var default_version: String = ""

	if local_version.is_empty():
		status = "not_installed"
	elif supported.has(minor_series(local_version)):
		var entry: Dictionary = supported[minor_series(local_version)]
		if bool(entry.get("deprecated", false)):
			status = "eol_upgrade_required"
		else:
			default_version = str(entry.get("version", ""))
			if is_newer(default_version, local_version):
				status = "patch_available"
			else:
				status = "up_to_date_in_series"
	else:
		status = "eol_upgrade_required"

	if default_version.is_empty():
		var pick: Dictionary = _pick_default_entry(supported, default_series)
		default_version = str(pick.get("version", ""))

	return {
		"status": status,
		"default_version": default_version,
	}


static func upgrade_kind(
	local_version: String,
	target_version: String,
	supported: Dictionary,
) -> String:
	if local_version.is_empty():
		return "install"
	var local_series: String = minor_series(local_version)
	if not supported.has(local_series):
		return "eol"
	if bool((supported[local_series] as Dictionary).get("deprecated", false)):
		return "eol"
	if minor_series(target_version) == local_series:
		return "patch"
	return "cross_series"


static func confirm_dialog_text(
	kind: String,
	product_label: String,
	local_version: String,
	target_version: String,
) -> String:
	match kind:
		"install":
			return "将安装 %s %s。" % [product_label, target_version]
		"patch":
			return "将 %s 从 %s 更新至 %s（%s 系列补丁更新）。" % [
				product_label,
				local_version,
				target_version,
				minor_series(local_version),
			]
		"cross_series":
			return (
				"将 %s 从 %s 升级至 %s（%s 系列）。"
				+ "跨系列升级可能有兼容性变化，建议备份工程。"
			) % [
				product_label,
				local_version,
				target_version,
				minor_series(target_version),
			]
		"eol":
			return (
				"当前版本 %s 已弃用或不在受支持范围内。"
				+ "将安装 %s %s（%s 系列）。"
			) % [
				local_version,
				product_label,
				target_version,
				minor_series(target_version),
			]
	return "将 %s 安装/更新至 %s。" % [product_label, target_version]


static func status_message(status: String, local_version: String, default_version: String) -> String:
	match status:
		"patch_available":
			return "%s 系列有补丁更新：%s" % [minor_series(local_version), default_version]
		"up_to_date_in_series":
			return "已是最新受支持版本"
		"eol_upgrade_required":
			return "当前版本已弃用，请升级到受支持版本（建议 %s）" % default_version
		"not_installed":
			return "请选择受支持版本"
	return ""


static func _pick_default_entry(supported: Dictionary, default_series: String) -> Dictionary:
	if not default_series.is_empty() and supported.has(default_series):
		var preferred: Dictionary = supported[default_series] as Dictionary
		if not bool(preferred.get("deprecated", false)):
			return preferred
	var sorted: Array[Dictionary] = sorted_supported_entries(supported)
	for i: int in range(sorted.size() - 1, -1, -1):
		var entry: Dictionary = sorted[i]
		if not bool(entry.get("deprecated", false)):
			return entry
	if sorted.is_empty():
		return {}
	return sorted[sorted.size() - 1]


static func _segment_int(segment: String) -> int:
	var digits: String = ""
	for i: int in segment.length():
		var ch: String = segment[i]
		if ch.is_valid_int():
			digits += ch
		else:
			break
	if digits.is_empty():
		return 0
	return int(digits)


static func format_fetch_error_hint(
	err_kind: String,
	http_status: int,
	source: String = "",
) -> String:
	var kind: String = err_kind.strip_edges()
	var src: String = source.strip_edges().to_lower()
	match kind:
		"local_missing":
			return "尚未下载远端索引，请先点击「检查更新」"
		"parse":
			return "远端或本地配置文件格式无效，无法解析"
		"empty":
			return "配置文件中没有可用的版本条目"
		"save":
			return "写入本地缓存失败，请检查 addons/gdframe/editor 目录权限"
	if http_status == 403:
		if src == "gitee":
			return "Gitee 拒绝访问 (HTTP 403)，请检查仓库权限或稍后重试"
		if src == "github" or src.is_empty():
			return "GitHub 拒绝访问 (HTTP 403)，请稍后重试或切换 Gitee"
		return "远端拒绝访问 (HTTP 403)，请稍后重试或切换更新源"
	if http_status == 404:
		return "远端文件不存在 (HTTP 404)，请确认仓库 main 已发布 plugin_index / ext_index"
	if http_status == 401:
		return "远端要求认证 (HTTP 401)，当前未配置访问令牌"
	if http_status == 429:
		return "请求过于频繁 (HTTP 429)，请稍后重试"
	if http_status >= 500 and http_status < 600:
		return "远端服务器错误 (HTTP %d)，请稍后重试" % http_status
	if http_status > 0:
		var kind_label: String = kind if not kind.is_empty() else "http"
		return "HTTP %d 请求失败（%s）" % [http_status, kind_label]
	if kind == "http" or kind.is_empty():
		return "无法连接远端，请检查网络/代理或切换更新源"
	return kind


static func format_remote_failure_suffix(
	err_kind: String,
	http_status: int,
	source: String,
	cache_label: String,
) -> String:
	var hint: String = format_fetch_error_hint(err_kind, http_status, source)
	return "（远端失败：%s，使用%s）" % [hint, cache_label]
