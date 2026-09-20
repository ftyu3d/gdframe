extends Resource
class_name GDFrameProfileResource

@export var settings: GDFrameSettingsData = null


func ensure_children() -> void:
	if settings != null:
		return
	var script: Script = load(GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH) as Script
	settings = script.new() as GDFrameSettingsData
