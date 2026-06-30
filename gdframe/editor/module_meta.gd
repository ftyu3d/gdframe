extends RefCounted
class_name GDFrameModuleMeta
## 读取 [code]ext/*/editor/module.cfg[/code] 并汇总模块元数据（Dock 扩展管理页使用）。

const MODULE_EDITOR_DIR: String = "editor"
const MODULE_CFG_NAME: String = "module.cfg"
const MODULE_CFG_SECTION: String = "module"

const _MODULE_SCAN: Script = preload("res://addons/gdframe/runtime/ext/module_scan.gd")
const _MODULE_EDITOR_SCAN: Script = preload("res://addons/gdframe/editor/module_editor_scan.gd")


static func module_cfg_path(ext_dir: String) -> String:
	return ext_dir.path_join(MODULE_EDITOR_DIR).path_join(MODULE_CFG_NAME)


static func read_cfg(ext_dir: String) -> Dictionary:
	var cfg_path: String = module_cfg_path(ext_dir)
	if not FileAccess.file_exists(cfg_path):
		return {}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(cfg_path) != OK or not cfg.has_section(MODULE_CFG_SECTION):
		return {}
	return {
		"name": str(cfg.get_value(MODULE_CFG_SECTION, "name", "")),
		"version": str(cfg.get_value(MODULE_CFG_SECTION, "version", "")),
	}


static func collect_infos() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mod: Script in _MODULE_SCAN.load_modules():
		out.append(build_info(mod))
	return out


static func build_info(mod: Script) -> Dictionary:
	var ext_dir: String = mod.resource_path.get_base_dir()
	var dir_name: String = ext_dir.get_file()
	var meta: Dictionary = read_cfg(ext_dir)
	var facade_count: int = 0
	var facade_methods: Variant = _MODULE_EDITOR_SCAN.call_editor_method(mod, &"facade_methods")
	if facade_methods is Array:
		facade_count = (facade_methods as Array).size()
	var profile_count: int = 0
	var profile_fields: Variant = _MODULE_EDITOR_SCAN.call_editor_method(mod, &"profile_fields")
	if profile_fields is Array:
		profile_count = (profile_fields as Array).size()
	var capabilities: PackedStringArray = PackedStringArray(["register"])
	if facade_count > 0:
		capabilities.append("facade")
	if profile_count > 0:
		capabilities.append("profile")
	if mod.has_method(&"extra_bus_names"):
		capabilities.append("audio_bus")
	return {
		"id": dir_name,
		"name": str(meta.get("name", dir_name)),
		"version": str(meta.get("version", "0.0.0")),
		"dir_name": dir_name,
		"ext_dir": ext_dir,
		"module_path": mod.resource_path,
		"facade_count": facade_count,
		"profile_count": profile_count,
		"capabilities": capabilities,
		"has_module_cfg": not meta.is_empty(),
	}
