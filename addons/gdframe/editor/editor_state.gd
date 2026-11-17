@tool
extends RefCounted
class_name GDFrameEditorState
## 编辑器侧状态（更新源、外部编辑器 IDE）统一存于 [EditorSettings] 的工程元数据，
## 不再往 [code]user://[/code] 额外写文件；随工程保存，换机器不继承。

const SOURCE_GITHUB: String = "github"
const SOURCE_GITEE: String = "gitee"

const META_SECTION: String = "gdframe"
const META_KEY_UPDATE_SOURCE: String = "update_source"
const META_KEY_EXTERNAL_EDITOR_IDE: String = "external_editor_ide"


static func get_update_source() -> String:
	var stored: String = str(
		settings().get_project_metadata(META_SECTION, META_KEY_UPDATE_SOURCE, "")
	).strip_edges()
	if _is_valid_source(stored):
		return stored
	return SOURCE_GITHUB


static func set_update_source(source: String) -> void:
	settings().set_project_metadata(
		META_SECTION,
		META_KEY_UPDATE_SOURCE,
		source if source == SOURCE_GITEE else SOURCE_GITHUB,
	)


static func get_external_editor_ide() -> String:
	return str(
		settings().get_project_metadata(META_SECTION, META_KEY_EXTERNAL_EDITOR_IDE, "")
	).strip_edges()


static func set_external_editor_ide(ide_id: String) -> void:
	settings().set_project_metadata(META_SECTION, META_KEY_EXTERNAL_EDITOR_IDE, ide_id)


static func settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()


static func _is_valid_source(source: String) -> bool:
	return source == SOURCE_GITHUB or source == SOURCE_GITEE
