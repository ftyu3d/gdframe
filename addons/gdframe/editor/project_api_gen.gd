@tool
extends RefCounted
## 只写项目组合脚本；核心无需知道扩展类型。

const OUTPUT := "res://gdframe_project/generated/services.gd"


static func generate(context: RefCounted) -> String:
	if EditorInterface.is_playing_scene():
		return "请先停止运行游戏。"
	var root := context.root() as Node
	if root == null:
		return "请等待配置场景打开后重试。"
	var original := root.get_script() as Script
	var custom := original.resource_path != "res://addons/gdframe/runtime/gdframe.gd" and original.resource_path != OUTPUT
	var source := FileAccess.get_file_as_string(original.resource_path) if custom else ""
	var contents := "extends GDFrameRoot\n# 由 GDFrame Dock 按已启用模块生成。\n"
	var signature := RegEx.new()
	signature.compile('static func create_service\\([^)]*\\)\\s*->\\s*([A-Za-z_][A-Za-z0-9_]*)')
	for descriptor: GDFrameModule in root.get("modules"):
		if descriptor == null or descriptor.entry == null:
			continue
		var id := descriptor.entry.resource_path.get_base_dir().get_file().trim_prefix("gdframe_")
		var match_result := signature.search(descriptor.entry.source_code)
		if match_result == null:
			return "扩展 %s 的 create_service 须声明返回类型，才能生成类型入口。" % id
		var declaration := RegEx.new()
		declaration.compile('(?m)^var\\s+' + id + '\\s*[:=]')
		if declaration.search(source) != null:
			continue
		var type := match_result.get_string(1)
		contents += '\nvar %s: %s:\n\tget: return get_service(&"%s") as %s\n' % [id, type, id, type]
	if custom and not source.contains('extends GDFrameRoot') and not source.contains('extends "%s"' % OUTPUT):
		return "项目根脚本有自定义继承链，请手动继承 %s。生成操作未修改文件。" % OUTPUT
	if not context.write_file(OUTPUT, contents):
		return "生成失败。"
	if custom:
		if not context.write_file(original.resource_path, source.replace('extends GDFrameRoot', 'extends "%s"' % OUTPUT)):
			return "生成成功，但更新项目继承声明失败。"
	else:
		var script := ResourceLoader.load(OUTPUT, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null or not context.set_property(&"script", script):
			return "脚本已生成，请检查并赋给项目配置场景。"
	context.scan()
	return "类型入口已生成。现有项目声明保留；更改模块后可再次生成。"
