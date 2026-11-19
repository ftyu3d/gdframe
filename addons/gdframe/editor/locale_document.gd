@tool
extends RefCounted
## Shared editor document for every localization view and tool in this project.

signal changed(source: Object)
signal state_changed
signal saved

const Csv = preload("locale_scaffold.gd")

static var _shared: RefCounted

var table: Dictionary
var dirty := false
var saving := false
var sync_pending := false
var last_error := ""
var _previous_outputs := PackedStringArray()
var _previous_locales := PackedStringArray()


static func shared() -> RefCounted:
	if _shared == null:
		var script := load("res://addons/gdframe/editor/locale_document.gd") as Script
		_shared = script.new()
		_shared.reload(true)
	return _shared


func reload(discard := false) -> void:
	if saving or not discard and (dirty or sync_pending):
		return
	if not discard and table.get("hash", "") == Csv.current_hash() and table.get("format", {}) == Csv.import_format():
		return
	table = Csv.read_csv()
	dirty = false
	sync_pending = false
	last_error = ""
	_previous_outputs = Csv.generated_paths()
	_previous_locales = table.locales.duplicate() if table.has("locales") and not table.hash.is_empty() else PackedStringArray()
	changed.emit(null)
	state_changed.emit()


func update(source: Object = null, mark_dirty := true) -> void:
	var was_dirty := dirty
	dirty = dirty or mark_dirty
	changed.emit(source)
	if was_dirty != dirty:
		state_changed.emit()


## Write the CSV synchronously for tools that commit their data on close.
func persist() -> String:
	if saving:
		return "本地化正在导入，请稍后重试。"
	return _persist()


func _persist() -> String:
	if table.has("error"):
		return table.error
	if Csv.current_hash() != table.hash:
		return "CSV 已被其他工具修改。请重新读取后再编辑。"
	if Csv.import_format() != table.format:
		return "Godot 的 CSV 导入设置已变更。请重新读取。"
	if dirty or not FileAccess.file_exists(Csv.LOCALE_CSV_PATH):
		var message := Csv.write_csv(table)
		if not message.is_empty():
			return message
		dirty = false
		sync_pending = true
		state_changed.emit()
	return ""


## Apply the current file to Godot. Once written, registration uses the saved
## snapshot so edits made from another view during import stay in the draft.
func apply(tree: SceneTree) -> void:
	if saving:
		return
	saving = true
	last_error = ""
	state_changed.emit()
	await tree.process_frame
	var editor := EditorInterface.get_resource_filesystem()
	while editor.is_scanning() or editor.is_importing():
		await tree.process_frame
	var message := _persist()
	if message.is_empty():
		sync_pending = true
		var snapshot := table.duplicate(true)
		var path := Csv.LOCALE_CSV_PATH
		if editor.get_file_type(path).is_empty():
			var imported := [false]
			var remember_import := func(paths: PackedStringArray):
				if path in paths:
					imported[0] = true
			editor.resources_reimported.connect(remember_import)
			editor.scan()
			var deadline := Time.get_ticks_msec() + 10000
			while not imported[0] and Time.get_ticks_msec() < deadline:
				await tree.process_frame
			editor.resources_reimported.disconnect(remember_import)
		elif FileAccess.file_exists(Csv.IMPORT_PATH):
			editor.reimport_files(PackedStringArray([path]))
		message = Csv.register_translations(snapshot, _previous_outputs, _previous_locales)
		if message.is_empty():
			message = Csv.remove_obsolete_outputs(_previous_outputs)
		if message.is_empty():
			sync_pending = false
			_previous_outputs = Csv.generated_paths()
			_previous_locales = snapshot.locales.duplicate()
	last_error = message
	saving = false
	state_changed.emit()
	if message.is_empty():
		saved.emit()
