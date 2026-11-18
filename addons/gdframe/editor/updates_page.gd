@tool
extends VBoxContainer

const Updater = preload("updater.gd")
const Versions = preload("version_series.gd")
var _context: RefCounted
var _updater := Updater.new()
var _source: OptionButton
var _versions: OptionButton
var _busy := false


func _init(context: RefCounted) -> void:
	_context = context


func _ready() -> void:
	var config := ConfigFile.new()
	config.load("res://addons/gdframe/plugin.cfg")
	_context.label(self, "GDFrame 当前版本：%s" % config.get_value("plugin", "version", ""))
	var actions := HBoxContainer.new()
	add_child(actions)
	_source = OptionButton.new()
	_source.add_item("GitHub")
	_source.add_item("Gitee")
	_source.select(1 if _updater.get_source() == "gitee" else 0)
	_source.item_selected.connect(func(index: int): _updater.set_source("gitee" if index == 1 else "github"))
	actions.add_child(_source)
	_context.button(actions, "检查更新", _check)
	_versions = OptionButton.new()
	actions.add_child(_versions)
	_context.button(actions, "安装所选版本", _confirm_update)
	_context.label(self, "安装后重启编辑器。项目的 gdframe.tscn 与 gdframe_project 不属于框架更新目录。")
	_populate(_updater.load_local_plugin_index())


func _populate(index: Dictionary) -> void:
	_versions.clear()
	for entry in Versions.sorted_supported_entries(index.get("supported", {})):
		_versions.add_item("%s%s" % [entry.version, "（已弃用）" if entry.get("deprecated", false) else ""])
		_versions.set_item_metadata(_versions.item_count - 1, entry)


func _check() -> void:
	if _busy:
		return
	_busy = true
	_context.report("正在检查 GDFrame 更新……")
	var index: Dictionary = await _updater.fetch_plugin_index(self, _updater.get_source())
	_busy = false
	_populate(index)
	_context.report("检查失败：%s" % index if index.has("error") else "版本列表已更新。")


func _confirm_update() -> void:
	if _busy or _versions.selected < 0 or EditorInterface.is_playing_scene():
		return
	var entry: Dictionary = _versions.get_item_metadata(_versions.selected)
	_context.confirm(self, "安装 GDFrame", "将安装 GDFrame %s，覆盖 addons/gdframe。完成后请重启编辑器。" % entry.version, _install.bind(str(entry.version)))


func _install(version: String) -> void:
	_busy = true
	EditorInterface.save_all_scenes()
	_context.report("正在下载 GDFrame %s……" % version)
	var url: String = _updater.release_download_url(_updater.get_source(), version)
	var success: bool = await _updater.apply_update(self, url)
	_busy = false
	_context.report("GDFrame 已更新，请重启编辑器。" if success else "更新失败，请检查下载源、网络和发布包格式。")
