@tool
class_name GDFrameUpdater
extends RefCounted

# =============================================================================
# Constants
# =============================================================================

const SOURCE_GITHUB: String = "github"
const SOURCE_GITEE: String = "gitee"
const EDITOR_CFG_PATH: String = "user://gdframe_editor.cfg"
const CFG_SECTION: String = "updater"
const CFG_KEY_SOURCE: String = "update_source"

const GITHUB_REPO: String = "ftyu3d/gdframe"
const GITEE_REPO: String = "ftyu3d/gdframe"
const PLUGIN_INDEX_REF: String = "main"
const PLUGIN_INDEX_FILE: String = "plugin_index.cfg"
const PLUGIN_INDEX_CACHE_PATH: String = "res://addons/gdframe/editor/plugin_index.cfg"
const UPDATE_ZIP_NAME: String = "gdframe.zip"

const _VERSION_SERIES: Script = preload("res://addons/gdframe/editor/version_series.gd")
const _ZIP_INSTALL: Script = preload("res://addons/gdframe/editor/zip_install.gd")
const _HTTP_FETCH: Script = preload("res://addons/gdframe/editor/http_fetch.gd")

var _last_http_status: int = 0
var _plugin_index_session_cache: Dictionary = {}

# =============================================================================
# Public API
# =============================================================================

func get_source() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(EDITOR_CFG_PATH) == OK:
		var stored: String = str(cfg.get_value(CFG_SECTION, CFG_KEY_SOURCE, ""))
		if stored == SOURCE_GITEE or stored == SOURCE_GITHUB:
			return stored
	return SOURCE_GITHUB


func set_source(source: String) -> void:
	if source != SOURCE_GITEE:
		source = SOURCE_GITHUB
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(EDITOR_CFG_PATH)
	cfg.set_value(CFG_SECTION, CFG_KEY_SOURCE, source)
	cfg.save(EDITOR_CFG_PATH)


func get_last_http_status() -> int:
	return _last_http_status


func load_local_plugin_index() -> Dictionary:
	if not FileAccess.file_exists(PLUGIN_INDEX_CACHE_PATH):
		return {"error": &"local_missing"}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PLUGIN_INDEX_CACHE_PATH) != OK:
		return {"error": &"parse"}
	var parsed: Dictionary = _VERSION_SERIES.parse_plugin_index_cfg(cfg)
	parsed["source"] = PLUGIN_INDEX_CACHE_PATH
	parsed["local"] = true
	if (parsed.get("supported", {}) as Dictionary).is_empty():
		return {"error": &"empty"}
	return parsed


func save_local_plugin_index(text: String) -> bool:
	if text.is_empty():
		return false
	var file: FileAccess = FileAccess.open(PLUGIN_INDEX_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file = null
	return true


func fetch_plugin_index(owner: Node, source: String) -> Dictionary:
	if source != SOURCE_GITEE:
		source = SOURCE_GITHUB
	var url: String = get_plugin_index_fetch_url(source)
	var body: String = await _http_get_text(owner, url)
	if body.is_empty():
		return _plugin_index_fetch_failed(source, &"http")

	var cfg_text: String = _VERSION_SERIES.normalize_index_cfg_response(body)
	var cfg: ConfigFile = _VERSION_SERIES.parse_cfg_text(cfg_text)
	if cfg == null:
		return _plugin_index_fetch_failed(source, &"parse")

	var parsed: Dictionary = _VERSION_SERIES.parse_plugin_index_cfg(cfg)
	if (parsed.get("supported", {}) as Dictionary).is_empty():
		return _plugin_index_fetch_failed(source, &"empty")
	if not save_local_plugin_index(cfg_text):
		return _plugin_index_fetch_failed(source, &"save")
	parsed["source"] = url
	_store_plugin_index_session_cache(source, parsed)
	return parsed.duplicate(true)


func clear_plugin_index_session_cache() -> void:
	_plugin_index_session_cache.clear()


func _store_plugin_index_session_cache(source: String, parsed: Dictionary) -> void:
	var copy: Dictionary = parsed.duplicate(true)
	copy.erase("cached")
	_plugin_index_session_cache[source] = copy


func _plugin_index_fetch_failed(source: String, err_kind: StringName) -> Dictionary:
	if _plugin_index_session_cache.has(source):
		var cached: Dictionary = (_plugin_index_session_cache[source] as Dictionary).duplicate(true)
		cached["cached"] = true
		cached["fetch_error"] = err_kind
		cached["http_status"] = _last_http_status
		return cached
	return {"error": err_kind, "http_status": _last_http_status}


func apply_update(owner: Node, download_url: String) -> bool:
	var zip_data: PackedByteArray = await _http_get_bytes(owner, download_url)
	return _ZIP_INSTALL.extract_zip_to_res(
		zip_data,
		"user://gdframe_update.zip",
		_to_target_path,
	)


func is_newer(remote_version: String, local_version: String) -> bool:
	return _VERSION_SERIES.is_newer(remote_version, local_version)


func get_plugin_index_fetch_url(source: String) -> String:
	if source == SOURCE_GITHUB:
		return (
			"https://raw.githubusercontent.com/%s/%s/%s"
			% [GITHUB_REPO, PLUGIN_INDEX_REF, PLUGIN_INDEX_FILE]
		)
	if source == SOURCE_GITEE:
		return (
			"https://gitee.com/%s/raw/%s/%s"
			% [GITEE_REPO, PLUGIN_INDEX_REF, PLUGIN_INDEX_FILE]
		)
	return ""


func release_download_url(source: String, version: String) -> String:
	var tag: String = _release_tag(version)
	if tag.is_empty():
		return ""
	if source == SOURCE_GITEE:
		return (
			"https://gitee.com/%s/releases/download/%s/%s"
			% [GITEE_REPO, tag, UPDATE_ZIP_NAME]
		)
	return (
		"https://github.com/%s/releases/download/%s/%s"
		% [GITHUB_REPO, tag, UPDATE_ZIP_NAME]
	)


static func _release_tag(version: String) -> String:
	var trimmed: String = version.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("v"):
		return trimmed
	return "v" + trimmed

# =============================================================================
# HTTP & install
# =============================================================================

func _to_target_path(entry_path: String) -> String:
	var normalized: String = entry_path.replace("\\", "/").strip_edges()
	if normalized.is_empty() or normalized.begins_with("/"):
		return ""
	if normalized.find("..") >= 0:
		return ""
	if not normalized.begins_with("gdframe/"):
		return ""
	return "res://addons/" + normalized


func _http_get_text(owner: Node, url: String) -> String:
	var bytes: PackedByteArray = await _http_get_bytes(owner, url)
	if bytes.is_empty():
		return ""
	return bytes.get_string_from_utf8()


func _http_get_bytes(owner: Node, url: String) -> PackedByteArray:
	var status_ref: Array = [0]
	var bytes: PackedByteArray = await _HTTP_FETCH.get_bytes(
		owner,
		url,
		30.0,
		"GDFrame-Updater/0.1.0",
		[],
		status_ref,
	)
	_last_http_status = int(status_ref[0])
	return bytes
