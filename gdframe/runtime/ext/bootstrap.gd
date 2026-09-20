class_name GDFrameExtBootstrap
extends RefCounted
## 扫描 [code]addons/gdframe_*/module.gd[/code] 并启动扩展。

const _MODULE_SCAN: Script = preload("module_scan.gd")
const _PROFILE_EXT: Script = preload("profile_ext.gd")

static var _modules: Array[Script] = []


static func setup(gdframe: Node) -> void:
	_modules = _MODULE_SCAN.load_modules()
	var prof: GDFrameProfileResource = GDFrame.save_get_profile()
	_PROFILE_EXT.ensure_all(prof, _modules)
	for mod: Script in _modules:
		mod.register(gdframe)


static func get_modules() -> Array[Script]:
	return _modules


## 升级 profile（settings 类型、总线键等）；不调用 [code]module.register[/code]。
static func ensure_profile(prof: GDFrameProfileResource) -> void:
	_PROFILE_EXT.ensure_all(prof, _modules)
