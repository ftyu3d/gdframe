class_name GDFrameExtBootstrap
extends RefCounted
## 扫描项目 [code]ext/*/module.gd[/code] 并启动扩展。

const _MODULE_SCAN: Script = preload("module_scan.gd")
const _PROFILE_EXT: Script = preload("profile_ext.gd")
const _EXT_RUNTIME: Script = preload("ext_runtime.gd")

static var _modules: Array[Script] = []


static func setup(gdframe: Node) -> void:
	_modules = _MODULE_SCAN.load_modules()
	var prof: GDFrameProfileResource = GDFrame.save_get_profile()
	_PROFILE_EXT.ensure_all(prof, _modules)
	for mod: Script in _modules:
		if mod.has_method(&"register"):
			mod.call(&"register", gdframe)


static func get_modules() -> Array[Script]:
	return _modules


## 仅升级 profile（settings 类型、总线键等）；不重复 [code]module.register[/code]。
static func ensure_profile(prof: GDFrameProfileResource) -> void:
	_PROFILE_EXT.ensure_all(prof, _modules)
