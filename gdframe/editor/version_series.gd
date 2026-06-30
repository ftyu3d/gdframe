extends RefCounted
class_name GDFrameVersionSeries
## SemVer minor 系列解析、plugin_index.cfg / ext_index.cfg 解析与更新目标选择。

const SERIES_PREFIX: String = "series."
const EXT_SERIES_MARKER: String = ".series."


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


## 将 HTTP 响应体规范为 index .cfg 纯文本（raw 直链原样返回；Gitee JSON API 则解码 content）。
static func normalize_index_cfg_response(body: String) -> String:
	if body.is_empty():
		return ""
	var trimmed: String = body.strip_edges()
	# GitHub/Gitee raw 返回纯 .cfg 文本（以 [section] 开头）；Gitee API 返回 JSON 包装。
	if not trimmed.begins_with("{"):
		return body
	var parsed: Variant = JSON.parse_string(trimmed)
	if typeof(parsed) != TYPE_DICTIONARY:
		return body
	var wrapper: Dictionary = parsed as Dictionary
	if not wrapper.has("content"):
		return body
	var encoded: String = str(wrapper["content"]).replace("\n", "")
	if encoded.is_empty():
		return ""
	return Marshalls.base64_to_raw(encoded).get_string_from_utf8()


static func parse_cfg_text(text: String) -> ConfigFile:
	var cfg: ConfigFile = ConfigFile.new()
	if text.is_empty():
		return null
	if cfg.parse(text) != OK:
		return null
	return cfg


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
		default_version = str(entry.get("version", ""))
		if is_newer(default_version, local_version):
			status = "patch_available"
		else:
			status = "up_to_date_in_series"
	else:
		status = "eol_migrate_required"

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
				"当前版本 %s 已不在受支持范围内。"
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
		"eol_migrate_required":
			return "当前版本不在受支持范围内，请选择受支持版本"
		"not_installed":
			return "请选择受支持版本"
	return ""


static func entry_for_version(supported: Dictionary, version: String) -> Dictionary:
	for key: Variant in supported.keys():
		if supported[key] is not Dictionary:
			continue
		var entry: Dictionary = supported[key] as Dictionary
		if str(entry.get("version", "")) == version:
			return entry
	return {}


static func _pick_default_entry(supported: Dictionary, default_series: String) -> Dictionary:
	if not default_series.is_empty() and supported.has(default_series):
		return supported[default_series] as Dictionary
	var sorted: Array[Dictionary] = sorted_supported_entries(supported)
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
			return "Gitee API 拒绝访问 (HTTP 403)，请检查仓库权限或稍后重试"
		if src == "github" or src.is_empty():
			return (
				"GitHub 访问被拒绝 (HTTP 403)，常见为 api.github.com 未认证限速；"
				+ "请切换 Gitee 或更新插件后重试"
			)
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
