@tool
extends RefCounted
class_name GDFrameProfileSettingsMigrate
## 编辑器：将 [member GDFrameProfileResource.settings] 统一为工程 [code]profile_settings_data.gd[/code] 类型并写回磁盘。


static func unified_script() -> Script:
	var path: String = GDFrameConfig.PROFILE_SETTINGS_SCRIPT_PATH
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Script


static func settings_script_ready() -> bool:
	var script: Script = unified_script()
	return script != null and script.can_instantiate()


static func ensure_unified(prof: GDFrameProfileResource) -> void:
	prof.ensure_children()
	var script: Script = unified_script()
	if script == null or not script.can_instantiate():
		return
	var current: GDFrameSettingsData = prof.settings
	if current != null and current.get_script() == script:
		return
	var unified: GDFrameSettingsData = script.new() as GDFrameSettingsData
	if unified == null:
		return
	if current != null:
		_copy_settings_fields(current, unified)
	prof.settings = unified


## 不加载 [code]config.tres[/code]（重写契约脚本后可能是 placeholder）；只根据磁盘上的 profile 文件迁移。
static func migrate_user_profile_on_disk() -> Dictionary:
	if not settings_script_ready():
		return {"ok": true, "message": "profile settings 脚本尚未就绪，已跳过迁移。"}
	var migrated: bool = false
	for ext: String in [".tres", ".res"]:
		var result: Dictionary = _migrate_profile_at_extension(ext)
		var status: String = str(result.get("status", ""))
		if status == "failed":
			return {"ok": false, "message": str(result.get("message", "磁盘 profile 迁移失败。"))}
		if status == "migrated":
			migrated = true
	if migrated:
		return {"ok": true, "message": "已迁移 profile settings 类型。"}
	return {"ok": true, "message": "无 profile 需迁移。"}


static func _migrate_profile_at_extension(ext: String) -> Dictionary:
	var profile_path: String = "%s/profile%s" % [GDFrameSaveManager.USER_ROOT_URL, ext]
	if not _profile_exists(profile_path):
		return {"status": "missing"}
	var loaded: Variant = ResourceLoader.load(profile_path)
	if not loaded is GDFrameProfileResource:
		return {
			"status": "failed",
			"message": "profile 无法加载：%s" % profile_path,
		}
	var prof: GDFrameProfileResource = loaded as GDFrameProfileResource
	var before: Script = prof.settings.get_script() if prof.settings != null else null
	ensure_unified(prof)
	var after: Script = prof.settings.get_script() if prof.settings != null else null
	if before == after:
		return {"status": "unchanged"}
	var err: Error = ResourceSaver.save(prof, profile_path)
	if err != OK:
		return {
			"status": "failed",
			"message": "profile 迁移写盘失败：%s" % profile_path,
		}
	return {"status": "migrated"}


static func _profile_exists(profile_path: String) -> bool:
	if ResourceLoader.exists(profile_path):
		return true
	return FileAccess.file_exists(ProjectSettings.globalize_path(profile_path))


static func _copy_settings_fields(from: Resource, to: Resource) -> void:
	for prop: Dictionary in from.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if not (usage & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = String(prop.get("name", ""))
		if name.is_empty() or name == "script":
			continue
		var value: Variant = from.get(name)
		if value is Dictionary:
			to.set(name, (value as Dictionary).duplicate(true))
		elif value is Array:
			to.set(name, (value as Array).duplicate(true))
		else:
			to.set(name, value)
