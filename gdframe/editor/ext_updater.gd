@tool
extends RefCounted
class_name GDFrameExtUpdater
## 扩展模块 ext_index.cfg 检查与 ZIP 安装（独立于插件本体 updater）。

const SOURCE_GITHUB: String = "github"
const SOURCE_GITEE: String = "gitee"
const GITHUB_REPO: String = "ftyu3d/gdframe-ext"
const GITEE_REPO: String = "ftyu3d/gdframe-ext"
const EDITOR_CFG_PATH: String = "user://gdframe_editor.cfg"
const CFG_SECTION: String = "updater"
const CFG_KEY_SOURCE: String = "update_source"
const EXT_INDEX_CACHE_PATH: String = "res://addons/gdframe/editor/ext_index.cfg"

const _VERSION_SERIES: Script = preload("res://addons/gdframe/editor/version_series.gd")
const _EXT_MANAGE_LIST: Script = preload("res://addons/gdframe/editor/ext_manage_list.gd")
const _ZIP_INSTALL: Script = preload("res://addons/gdframe/editor/zip_install.gd")
const _HTTP_FETCH: Script = preload("res://addons/gdframe/editor/http_fetch.gd")

var _last_http_status: int = 0
var _fetch_in_flight: Array = []
var _update_source: String = SOURCE_GITHUB


func get_last_http_status() -> int:
	return _last_http_status


func is_newer(remote_version: String, local_version: String) -> bool:
	return _VERSION_SERIES.is_newer(remote_version, local_version)


func set_source(source: String) -> void:
	if source != SOURCE_GITEE:
		source = SOURCE_GITHUB
	_update_source = source
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(EDITOR_CFG_PATH)
	cfg.set_value(CFG_SECTION, CFG_KEY_SOURCE, source)
	cfg.save(EDITOR_CFG_PATH)


func get_source() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(EDITOR_CFG_PATH) == OK:
		var stored: String = str(cfg.get_value(
			CFG_SECTION,
			CFG_KEY_SOURCE,
			"",
		))
		if stored == SOURCE_GITEE or stored == SOURCE_GITHUB:
			_update_source = stored
	return _update_source


func cancel_fetch() -> void:
	if _fetch_in_flight.size() > 0 and _fetch_in_flight[0] is HTTPRequest:
		var http: HTTPRequest = _fetch_in_flight[0] as HTTPRequest
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_fetch_in_flight.clear()


func load_local_ext_index() -> Dictionary:
	if not FileAccess.file_exists(EXT_INDEX_CACHE_PATH):
		return {"error": &"local_missing"}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(EXT_INDEX_CACHE_PATH) != OK:
		return {"error": &"parse"}
	var ext_index: Dictionary = _VERSION_SERIES.parse_ext_index_cfg(cfg)
	ext_index["source"] = EXT_INDEX_CACHE_PATH
	ext_index["local"] = true
	if (ext_index.get("extensions_by_id", {}) as Dictionary).is_empty():
		return {"error": &"empty"}
	return ext_index


func save_local_ext_index(text: String) -> bool:
	if text.is_empty():
		return false
	var file: FileAccess = FileAccess.open(EXT_INDEX_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file = null
	return true


func fetch_ext_index(owner: Node) -> Dictionary:
	cancel_fetch()
	var url: String = _EXT_MANAGE_LIST.ext_index_fetch_url(get_source())
	var body: String = await _http_get_text(owner, url)
	if body.is_empty():
		return _ext_index_fetch_failed(&"http")

	var cfg_text: String = _VERSION_SERIES.normalize_index_cfg_response(body)
	var cfg: ConfigFile = _VERSION_SERIES.parse_cfg_text(cfg_text)
	if cfg == null:
		return _ext_index_fetch_failed(&"parse")

	var ext_index: Dictionary = _VERSION_SERIES.parse_ext_index_cfg(cfg)
	if (ext_index.get("extensions_by_id", {}) as Dictionary).is_empty():
		return _ext_index_fetch_failed(&"empty")
	if not save_local_ext_index(cfg_text):
		return _ext_index_fetch_failed(&"save")
	ext_index["source"] = url
	return ext_index


func _ext_index_fetch_failed(err_kind: StringName) -> Dictionary:
	var local: Dictionary = load_local_ext_index()
	if not local.has("error"):
		local["fetch_error"] = err_kind
		local["http_status"] = _last_http_status
		return local
	return {"error": err_kind, "http_status": _last_http_status}


func extension_download_url(source: String, ext_id: String, version: String) -> String:
	var trimmed_id: String = ext_id.strip_edges()
	var trimmed_ver: String = version.strip_edges()
	if trimmed_ver.is_empty():
		return ""
	var zip_name: String = "%s.zip" % trimmed_id
	if zip_name == ".zip":
		return ""
	var tag: String = _extension_release_tag(source, trimmed_id, trimmed_ver)
	if tag.is_empty():
		return ""
	if source == SOURCE_GITEE:
		return (
			"https://gitee.com/%s/releases/download/%s/%s"
			% [GITEE_REPO, tag, zip_name]
		)
	return (
		"https://github.com/%s/releases/download/%s/%s"
		% [GITHUB_REPO, tag, zip_name]
	)


func apply_extension_update(owner: Node, download_url: String, ext_id: String) -> bool:
	cancel_fetch()
	var zip_data: PackedByteArray = await _http_get_bytes(owner, download_url)
	return _ZIP_INSTALL.extract_zip_to_res(
		zip_data,
		"user://ext_update_%s.zip" % ext_id,
		func(entry_path: String) -> String:
			return _resolve_ext_zip_path(entry_path, ext_id),
	)


static func _extension_release_tag(_source: String, _ext_id: String, version: String) -> String:
	if version.is_empty():
		return ""
	if version.begins_with("v"):
		return version
	return "v" + version


static func _resolve_ext_zip_path(entry_path: String, ext_id: String) -> String:
	var normalized: String = entry_path.replace("\\", "/").strip_edges()
	if normalized.contains(".."):
		return ""
	var trimmed_id: String = ext_id.strip_edges()
	if trimmed_id.is_empty():
		return ""
	var rel: String = ""
	var canonical_prefix: String = "gdframe/ext/%s/" % trimmed_id
	if normalized.begins_with(canonical_prefix):
		rel = normalized.substr(canonical_prefix.length())
	elif normalized.begins_with("%s/" % trimmed_id):
		rel = normalized.substr(trimmed_id.length() + 1)
	else:
		return ""
	if rel.is_empty() or rel.ends_with("/"):
		return ""
	return GDFrameConfig.EXT_ROOT_DIR.path_join(trimmed_id).path_join(rel)


func _http_get_text(owner: Node, url: String) -> String:
	var bytes: PackedByteArray = await _http_get_bytes(owner, url)
	if bytes.is_empty():
		return ""
	return bytes.get_string_from_utf8()


func _http_get_bytes(owner: Node, url: String) -> PackedByteArray:
	_fetch_in_flight.clear()
	var status_ref: Array = [0]
	var bytes: PackedByteArray = await _HTTP_FETCH.get_bytes(
		owner,
		url,
		15.0,
		"GDFrame-ExtUpdater/0.1.0",
		_fetch_in_flight,
		status_ref,
	)
	_fetch_in_flight.clear()
	_last_http_status = int(status_ref[0])
	return bytes
