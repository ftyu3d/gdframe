class_name GDFrameExtBootstrap
extends RefCounted
## 扫描 [code]addons/gdframe_*/module.gd[/code] 并启动扩展。

const _MODULE_SCAN: Script = preload("module_scan.gd")
const _PROFILE_EXT: Script = preload("profile_ext.gd")
const _EXT_RUNTIME: Script = preload("ext_runtime.gd")


static func setup(host: Node, prof: GDFrameProfileResource) -> void:
	_EXT_RUNTIME.set_modules(_MODULE_SCAN.load_modules())
	ensure_profile(prof)
	for mod: Script in _EXT_RUNTIME.get_modules():
		mod.register(host)


## 升级 profile（settings 类型、总线键等）；不调用 [code]module.register[/code]。
static func ensure_profile(prof: GDFrameProfileResource) -> void:
	GDFrameAudioManager.ensure_profile_bus_keys(prof)
	_PROFILE_EXT.ensure_all(prof, _EXT_RUNTIME.get_modules())
