@tool
extends EditorExportPlugin

var _excluded: PackedStringArray = []
var _composition_path: String


func _init(composition_path: String) -> void:
	_composition_path = composition_path


func _get_name() -> String:
	return "GDFrameModules"


func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_excluded.clear()
	var scene := ResourceLoader.load(_composition_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return
	var state := scene.get_state()
	var selected: PackedStringArray = []
	for index in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == &"modules":
			for module: GDFrameModule in state.get_node_property_value(0, index):
				if module != null and module.entry != null:
					selected.append(module.entry.resource_path.get_base_dir())
	for dir in DirAccess.get_directories_at("res://addons"):
		var path := "res://addons/" + dir
		if not dir.begins_with("gdframe_") or not FileAccess.file_exists(path + "/module.tres"):
			continue
		_excluded.append(path + "/editor/" if selected.has(path) else path + "/")


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://addons/gdframe/editor/") or path == "res://addons/gdframe/plugin.cfg":
		skip()
		return
	for prefix in _excluded:
		if path.begins_with(prefix):
			skip()
			return
