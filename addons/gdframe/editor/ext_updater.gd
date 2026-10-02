@tool
extends RefCounted
class_name GDFrameExtUpdater
## 扩展模块索引拉取与 ZIP 安装。

const SOURCE_GITHUB: String = "github"
const SOURCE_GITEE: String = "gitee"
const GITHUB_REPO: String = "ftyu3d/gdframe-ext"
const GITEE_REPO: String = "ftyu3d/gdframe-ext"
const EDITOR_CFG_PATH: String = "user://gdframe_editor.cfg"
const CFG_SECTION: String = "updater"
const CFG_KEY_SOURCE: String = "update_source"
const EXT_INDEX_CACHE_PATH: String = "res://addons/gdframe/editor/ext_index.cfg"
const EXT_INDEX_NONEMPTY_KEY: String = "extensions_by_id"

const _VERSION_SERIES: Script = preload("res://addons/gdframe/editor/version_series.gd")
const _EXT_MANAGE_LIST: Script = preload("res://addons/gdframe/editor/ext_manage_list.gd")
const _ZIP_INSTALL: Script = preload("res://addons/gdframe/editor/zip_install.gd")
const _HTTP_FETCH: Script = preload("res://addons/gdframe/editor/http_fetch.gd")

var _last_http_status: int = 0
var _fetch_in_flight: Array = []


func get_last_http_status() -> int:
	return _last_http_status


func get_source() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(EDITOR_CFG_PATH) == OK:
		var stored: String = str(cfg.get_value(CFG_SECTION, CFG_KEY_SOURCE, ""))
		if stored == SOURCE_GITEE or stored == SOURCE_GITHUB:
			return stored
	return SOURCE_GITHUB


func cancel_fetch() -> void:
	if _fetch_in_flight.size() > 0 and _fetch_in_flight[0] is HTTPRequest:
		var http: HTTPRequest = _fetch_in_flight[0] as HTTPRequest
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_fetch_in_flight.clear()


func load_local_ext_index() -> Dictionary:
	return _VERSION_SERIES.load_local_index_cfg(
		EXT_INDEX_CACHE_PATH,
		_VERSION_SERIES.parse_ext_index_cfg,
		EXT_INDEX_NONEMPTY_KEY,
	)


func fetch_ext_index(owner: Node) -> Dictionary:
	cancel_fetch()
	var url: String = _EXT_MANAGE_LIST.ext_index_fetch_url(get_source())
	var body: String = await _http_get_text(owner, url)
	if body.is_empty():
		return _ext_index_fetch_failed(&"http")

	var ext_index: Dictionary = _VERSION_SERIES.parse_and_save_index_cfg(
		body,
		_VERSION_SERIES.parse_ext_index_cfg,
		EXT_INDEX_NONEMPTY_KEY,
		EXT_INDEX_CACHE_PATH,
	)
	if ext_index.has("error"):
		return _ext_index_fetch_failed(ext_index.get("error", &"parse") as StringName)

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
	if trimmed_id.is_empty() or trimmed_ver.is_empty():
		return ""
	var tag: String = _VERSION_SERIES.release_tag(trimmed_ver)
	if tag.is_empty():
		return ""
	var zip_name: String = "%s.zip" % trimmed_id
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
	var trimmed_id: String = ext_id.strip_edges()
	if trimmed_id.is_empty():
		return false
	var zip_data: PackedByteArray = await _http_get_bytes(owner, download_url)
	var ext_root: String = GDFrameConfig.ext_addon_path(trimmed_id)
	return _ZIP_INSTALL.extract_zip_to_res(
		zip_data,
		"user://ext_update_%s.zip" % trimmed_id,
		func(entry_path: String) -> String:
			return _ZIP_INSTALL.map_entry_under_prefix(
				entry_path,
				"addons/%s" % GDFrameConfig.ext_addon_dir_name(trimmed_id),
			),
		ext_root,
	)


func _http_get_text(owner: Node, url: String) -> String:
	_fetch_in_flight.clear()
	var status_ref: Array = [0]
	var text: String = await _HTTP_FETCH.get_text(
		owner,
		url,
		15.0,
		"GDFrame-ExtUpdater/1.0.0",
		_fetch_in_flight,
		status_ref,
	)
	_fetch_in_flight.clear()
	_last_http_status = int(status_ref[0])
	return text


func _http_get_bytes(owner: Node, url: String) -> PackedByteArray:
	_fetch_in_flight.clear()
	var status_ref: Array = [0]
	var bytes: PackedByteArray = await _HTTP_FETCH.get_bytes(
		owner,
		url,
		15.0,
		"GDFrame-ExtUpdater/1.0.0",
		_fetch_in_flight,
		status_ref,
	)
	_fetch_in_flight.clear()
	_last_http_status = int(status_ref[0])
	return bytes
