extends RefCounted
## 启动时升级 [code]profile.settings[/code]（扩展缺字段默认 + 总线键）。

const _EXT_RUNTIME: Script = preload("ext_runtime.gd")


static func ensure_all(prof: GDFrameProfileResource, modules: Array[Script]) -> void:
	prof.ensure_children()
	GDFrameProfileSettingsExt.apply_extension_defaults(prof)
	GDFrameAudioManager.ensure_profile_bus_keys(prof)
	_EXT_RUNTIME.ensure_extra_bus_profile_keys(prof, modules)
