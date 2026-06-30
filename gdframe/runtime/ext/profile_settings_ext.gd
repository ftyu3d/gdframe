extends RefCounted
class_name GDFrameProfileSettingsExt
## 读档时为 [member GDFrameProfileResource.settings] 补扩展缺字段默认（由编辑器生成的 [code]profile_settings_defaults.gd[/code]）。

static func apply_extension_defaults(prof: GDFrameProfileResource) -> void:
	prof.ensure_children()
	if prof.settings != null:
		_apply_defaults(prof.settings)


static func _apply_defaults(settings: GDFrameSettingsData) -> void:
	var script: Script = load(GDFrameConfig.PROFILE_SETTINGS_DEFAULTS_PATH) as Script
	if script.has_method(&"apply"):
		script.call(&"apply", settings)
