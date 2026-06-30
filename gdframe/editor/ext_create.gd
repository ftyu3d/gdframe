extends RefCounted
## 扩展模块脚手架模板（Dock「扩展管理 → 创建」）。

enum Template {
	FACADE,
	PROFILE_ONLY,
	MINIMAL,
}


const _ASSET_NAME_UTIL: Script = preload("res://addons/gdframe/editor/asset_name_util.gd")


static func normalize_module_id(raw_name: String) -> String:
	return _ASSET_NAME_UTIL.normalize_module_id(raw_name)


static func service_node_name(module_id: String) -> String:
	var buf: String = "GDFrame"
	for part: String in module_id.split("_"):
		if part.is_empty():
			continue
		buf += part[0].to_upper() + part.substr(1)
	return buf + "Service"


static func build_files(module_id: String, display_name: String, template: int) -> Dictionary:
	var files: Dictionary = {}
	files["editor/.gdignore"] = ""
	files["editor/module.cfg"] = _module_cfg_text(module_id, display_name)
	files["editor/README.md"] = _build_readme(module_id, display_name, template)
	files["module.gd"] = _build_module_gd(module_id, display_name, template)
	if template == Template.FACADE:
		files["%s_service.gd" % module_id] = _build_service_gd(module_id)
		files["editor/module_editor.gd"] = _build_module_editor_gd(module_id, display_name, template)
	elif template == Template.PROFILE_ONLY:
		files["editor/module_editor.gd"] = _build_module_editor_gd(module_id, display_name, template)
	return files


static func _module_cfg_text(_module_id: String, display_name: String) -> String:
	return (
		"[module]\n"
		+ 'name="%s"\n' % display_name
		+ 'version="0.1.0"\n'
	)


static func _build_readme(module_id: String, display_name: String, template: int) -> String:
	var api_hint: String = ""
	match template:
		Template.FACADE:
			api_hint = "Dock 扩展管理 →「生成扩展 API」后可通过 `GDFrame.%s_*()` 调用。" % module_id
		Template.PROFILE_ONLY:
			api_hint = "通过 profile 字段 `%s` 持久化配置；无 GDFrame facade。" % module_id
		_:
			api_hint = "仅注册占位模块，可按需扩展 facade 或 profile。"
	return (
		"# %s\n\n"
		+ "GDFrame 扩展模块 `%s`。\n\n"
		+ "## API\n\n"
		+ "%s\n"
	) % [display_name, module_id, api_hint]


static func _build_module_gd(module_id: String, display_name: String, template: int) -> String:
	match template:
		Template.FACADE:
			return (
				"extends RefCounted\n"
				+ "## %s 扩展（facade 型）。\n\n"
				+ "const _SERVICE: Script = preload(\"%s_service.gd\")\n\n\n"
				+ "static func register(gdframe: Node) -> void:\n"
				+ "\tvar svc: Node = _SERVICE.new()\n"
				+ "\tsvc.name = \"%s\"\n"
				+ "\tgdframe.add_child(svc)\n"
				+ "\tsvc.call(\"setup\", gdframe)\n"
				+ "\tgdframe.service_register(&\"%s\", svc)\n"
			) % [display_name, module_id, service_node_name(module_id), module_id]
		Template.PROFILE_ONLY:
			return (
				"extends RefCounted\n"
				+ "## %s 扩展（profile 型）。\n\n\n"
				+ "static func register(_gdframe: Node) -> void:\n"
				+ "\tpass\n"
			) % display_name
		_:
			return (
				"extends RefCounted\n"
				+ "## %s 扩展（最小占位）。\n\n\n"
				+ "static func register(_gdframe: Node) -> void:\n"
				+ "\tpass\n"
			) % display_name


static func _build_module_editor_gd(module_id: String, display_name: String, template: int) -> String:
	match template:
		Template.FACADE:
			return (
				"extends RefCounted\n"
				+ "## %s 扩展 facade 声明（仅 Dock 生成 API；不打进导出包）。\n\n\n"
				+ "static func facade_methods() -> Array[Dictionary]:\n"
				+ "\treturn [\n"
				+ "\t\t{\n"
				+ "\t\t\t\"signature\": \"func %s_ping() -> bool\",\n"
				+ "\t\t\t\"delegate\": &\"ping\",\n"
				+ "\t\t\t\"call_args\": \"\",\n"
				+ "\t\t\t\"return_wrap\": \"bool\",\n"
				+ "\t\t},\n"
				+ "\t]\n"
			) % [display_name, module_id]
		Template.PROFILE_ONLY:
			return (
				"extends RefCounted\n"
				+ "## %s 扩展 profile 声明（仅 Dock 生成 API；不打进导出包）。\n\n\n"
				+ "static func profile_fields() -> Array[Dictionary]:\n"
				+ "\treturn [\n"
				+ "\t\t{\n"
				+ "\t\t\t\"name\": \"%s\",\n"
				+ "\t\t\t\"type\": \"Dictionary\",\n"
				+ "\t\t\t\"default\": {},\n"
				+ "\t\t\t\"comment\": \"%s 扩展配置。\",\n"
				+ "\t\t},\n"
				+ "\t]\n"
			) % [display_name, module_id, display_name]
		_:
			return ""


static func _build_service_gd(module_id: String) -> String:
	return (
		"extends Node\n"
		+ "## %s 扩展运行时服务。\n\n"
		+ "var _gdframe: Node = null\n\n\n"
		+ "func setup(gdframe: Node) -> void:\n"
		+ "\t_gdframe = gdframe\n\n\n"
		+ "func ping() -> bool:\n"
		+ "\treturn true\n"
	) % module_id
