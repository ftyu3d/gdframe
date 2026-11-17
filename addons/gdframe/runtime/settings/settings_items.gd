extends RefCounted
class_name GDFrameSettingsItems
## 设置项清单：工程声明（[code]gdframe_project/settings/*.cfg[/code]）与扩展 [code]module.gd[/code]
## 的 [method settings_items] 汇总，供 Dock「设置项」页与运行时读取。
##
## 工程声明项写在 [code][item][/code] 段，字段：
## [code]id / kind / bus / title / title_key / order / default_linear / preset[/code]；
## 扩展声明的项属于只读项（[code]locked = true[/code]），不在工程目录里落盘。
##
## 每个设置项统一为字典：[code]{id, kind, bus, title, title_key, order,
## default_linear, preset, comment, source, owner_title, owner_source, locked}[/code]。
## [code]comment[/code] 是该项的说明：工程项取自 cfg 里的 [code];[/code] 注释行，
## profile 字段取自 [code]@export[/code] 上方的 [code]##[/code] 注释。

## 音轨项：一条音轨对应一个音频总线，运行时由音频模块消费。
const KIND_AUDIO_BUS: StringName = &"audio_bus"
const SECTION: String = "item"
const DEFAULT_ORDER: int = 100
const ORDER_STEP: int = 10
const DEFAULT_LINEAR: float = 1.0


## 设置项目录（[code]res://gdframe_project/settings[/code]）。
static func items_dir() -> String:
	return GDFrameConfig.SETTINGS_ITEMS_DIR


static func ensure_dir() -> Error:
	var abs_dir: String = ProjectSettings.globalize_path(items_dir())
	if DirAccess.dir_exists_absolute(abs_dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(abs_dir)


## 工程里声明的设置项，按 [code]order[/code] / [code]id[/code] 升序。
static func project_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var abs_dir: String = ProjectSettings.globalize_path(items_dir())
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".cfg"):
			continue
		var item: Dictionary = read_item(items_dir().path_join(file_name))
		if not item.is_empty():
			out.append(item)
	_sort_items(out)
	return out


## 解析单个工程声明项；文件缺失或缺少 [code][item][/code] 段时返回空字典。
static func read_item(res_path: String) -> Dictionary:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return {}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(abs_path) != OK or not cfg.has_section(SECTION):
		return {}
	var item_id: String = str(
		cfg.get_value(SECTION, "id", res_path.get_file().get_basename())
	).strip_edges()
	if item_id.is_empty():
		return {}
	var bus: String = str(cfg.get_value(SECTION, "bus", "")).strip_edges()
	var title: String = str(cfg.get_value(SECTION, "title", "")).strip_edges()
	return {
		"id": item_id,
		"kind": StringName(str(cfg.get_value(SECTION, "kind", String(KIND_AUDIO_BUS)))),
		"bus": bus if not bus.is_empty() else item_id,
		"title": title if not title.is_empty() else item_id,
		"title_key": str(cfg.get_value(SECTION, "title_key", "")),
		"order": int(cfg.get_value(SECTION, "order", DEFAULT_ORDER)),
		"default_linear": float(cfg.get_value(SECTION, "default_linear", DEFAULT_LINEAR)),
		"preset": str(cfg.get_value(SECTION, "preset", "")),
		"comment": _read_comment(abs_path),
		"source": res_path,
		"owner_title": "",
		"owner_source": "",
		"locked": false,
	}


## 扩展声明的设置项（只读）。[param modules] 为 [method GDFrameModuleScan.load_modules] 的结果。
static func module_items(modules: Array[Script]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mod: Script in modules:
		if mod == null or not mod.has_method(&"settings_items"):
			continue
		var raw: Variant = mod.call(&"settings_items")
		if not raw is Array:
			continue
		var owner_title: String = module_title(mod)
		var owner_source: String = mod.resource_path
		for entry: Variant in raw:
			if not entry is Dictionary:
				continue
			var item: Dictionary = _locked_item(entry as Dictionary, owner_title, owner_source)
			if not item.is_empty():
				out.append(item)
	_sort_items(out)
	return out


## 工程声明项 + 扩展声明项；同 id 时以扩展（只读）项为准。
static func all_items(modules: Array[Script]) -> Array[Dictionary]:
	# 工程声明项先行：它带 [code]preset[/code] / [code]source[/code] 等落盘信息，
	# 扩展 [method module_items] 里同 id 的项只是同一份数据的镜像，跳过即可。
	var out: Array[Dictionary] = project_items()
	var seen: Dictionary = {}
	for item: Dictionary in out:
		seen[str(item.get("id", ""))] = true
	for item: Dictionary in module_items(modules):
		var item_id: String = str(item.get("id", ""))
		if seen.has(item_id):
			continue
		seen[item_id] = true
		out.append(item)
	_sort_items(out)
	return out


## 新建或覆盖一项工程声明项；[param item] 只用 id/kind/bus/title/title_key/
## order/default_linear/preset 这几个字段。
static func save_item(item: Dictionary) -> Error:
	var item_id: String = str(item.get("id", "")).strip_edges()
	if item_id.is_empty():
		return ERR_INVALID_PARAMETER
	var err: Error = ensure_dir()
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "id", item_id)
	cfg.set_value(SECTION, "kind", str(item.get("kind", String(KIND_AUDIO_BUS))))
	cfg.set_value(SECTION, "bus", str(item.get("bus", item_id)))
	cfg.set_value(SECTION, "title", str(item.get("title", item_id)))
	var title_key: String = str(item.get("title_key", "")).strip_edges()
	if not title_key.is_empty():
		cfg.set_value(SECTION, "title_key", title_key)
	cfg.set_value(SECTION, "order", int(item.get("order", DEFAULT_ORDER)))
	cfg.set_value(SECTION, "default_linear", float(item.get("default_linear", DEFAULT_LINEAR)))
	var preset: String = str(item.get("preset", "")).strip_edges()
	if not preset.is_empty():
		cfg.set_value(SECTION, "preset", preset)
	var abs_path: String = ProjectSettings.globalize_path(item_path(item_id))
	var old_comment: String = _read_comment(abs_path)
	var err_save: Error = cfg.save(abs_path)
	if err_save != OK:
		return err_save
	# [method ConfigFile.save] 会丢掉注释行，这里把说明重新写回文件头。
	var comment: String = str(item.get("comment", "")).strip_edges()
	if comment.is_empty():
		comment = old_comment
	if not comment.is_empty():
		return _write_comment(abs_path, comment)
	return OK


## 删除一项工程声明项（连同文件）。目录空了顺手删掉，避免留空目录。
static func delete_item(res_path: String) -> Error:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return ERR_FILE_NOT_FOUND
	var err: Error = DirAccess.remove_absolute(abs_path)
	if err == OK:
		var abs_dir: String = ProjectSettings.globalize_path(items_dir())
		var dir: DirAccess = DirAccess.open(abs_dir)
		if dir != null and dir.get_files().is_empty() and dir.get_directories().is_empty():
			DirAccess.remove_absolute(abs_dir)
	return err


## 改写一项的排序值（其余字段原样保留）。
static func set_order(res_path: String, order: int) -> Error:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return ERR_FILE_NOT_FOUND
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(abs_path) != OK or not cfg.has_section(SECTION):
		return ERR_FILE_CORRUPT
	var comment: String = _read_comment(abs_path)
	cfg.set_value(SECTION, "order", order)
	var err: Error = cfg.save(abs_path)
	if err != OK:
		return err
	if not comment.is_empty():
		_write_comment(abs_path, comment)
	return OK


## 读取 cfg 里的说明注释：第一条非空 [code];[/code] / [code]#[/code] 行。
static func _read_comment(abs_path: String) -> String:
	if not FileAccess.file_exists(abs_path):
		return ""
	var text: String = FileAccess.get_file_as_string(abs_path)
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with(";") or line.begins_with("#"):
			var body: String = line.substr(1).strip_edges()
			if not body.is_empty():
				return body
	return ""


## 用 [param comment] 替换 cfg 的注释行（写在文件首行）；空串表示只清理旧注释。
static func _write_comment(abs_path: String, comment: String) -> Error:
	var clean: String = comment.strip_edges()
	var kept: PackedStringArray = PackedStringArray()
	if FileAccess.file_exists(abs_path):
		var text: String = FileAccess.get_file_as_string(abs_path)
		for raw_line: String in text.split("\n"):
			var trimmed: String = raw_line.strip_edges()
			if trimmed.begins_with(";") or trimmed.begins_with("#"):
				continue
			kept.append(raw_line)
	var body: String = "\n".join(kept).strip_edges()
	if not body.is_empty():
		body += "\n"
	var out: String = body
	if not clean.is_empty():
		out = "; %s\n%s" % [clean, body]
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(out)
	f.close()
	return OK


## 工程声明项的落盘路径：[code]settings/<id>.cfg[/code]。
static func item_path(item_id: String) -> String:
	return items_dir().path_join("%s.cfg" % item_id)


## 追加一项时用的排序值：现有最大值 + [constant ORDER_STEP]。
static func next_order() -> int:
	var max_order: int = DEFAULT_ORDER - ORDER_STEP
	for item: Dictionary in project_items():
		max_order = maxi(max_order, int(item.get("order", DEFAULT_ORDER)))
	return max_order + ORDER_STEP


## 生成不与现有项冲突的 id：[code]audio_1[/code]、[code]audio_2[/code]……
static func unique_id(base: String, modules: Array[Script]) -> String:
	var stem: String = base.strip_edges()
	if stem.is_empty():
		stem = "item"
	var taken: Dictionary = {}
	for item: Dictionary in all_items(modules):
		taken[str(item.get("id", ""))] = true
	if not taken.has(stem):
		return stem
	var index: int = 2
	while taken.has("%s_%d" % [stem, index]):
		index += 1
	return "%s_%d" % [stem, index]


## 扩展名字：优先取模块 [code]plugin.cfg[/code] 的 name，退回目录名。
static func module_title(mod: Script) -> String:
	var cfg_path: String = mod.resource_path.get_base_dir().path_join("plugin.cfg")
	var abs_path: String = ProjectSettings.globalize_path(cfg_path)
	if FileAccess.file_exists(abs_path):
		var cfg: ConfigFile = ConfigFile.new()
		if cfg.load(abs_path) == OK:
			var display: String = str(cfg.get_value("plugin", "name", "")).strip_edges()
			if not display.is_empty():
				return display
	return mod.resource_path.get_base_dir().get_file()


static func _locked_item(
	entry: Dictionary, owner_title: String, owner_source: String,
) -> Dictionary:
	var item_id: String = str(entry.get("id", entry.get("name", ""))).strip_edges()
	if item_id.is_empty():
		return {}
	var bus: String = str(entry.get("bus", "")).strip_edges()
	var title: String = str(entry.get("title", "")).strip_edges()
	return {
		"id": item_id,
		"kind": StringName(str(entry.get("kind", String(KIND_AUDIO_BUS)))),
		"bus": bus if not bus.is_empty() else item_id,
		"title": title if not title.is_empty() else item_id,
		"title_key": str(entry.get("title_key", "")),
		"order": int(entry.get("order", DEFAULT_ORDER)),
		"default_linear": float(entry.get("default_linear", DEFAULT_LINEAR)),
		"preset": str(entry.get("preset", "")),
		"comment": str(entry.get("comment", entry.get("summary", ""))).strip_edges(),
		"source": "",
		"owner_title": owner_title,
		"owner_source": owner_source,
		"locked": true,
	}


## 原地排序：先按 [code]order[/code]，再按 [code]id[/code]。
static func _sort_items(items: Array[Dictionary]) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a: int = int(a.get("order", DEFAULT_ORDER))
		var order_b: int = int(b.get("order", DEFAULT_ORDER))
		if order_a != order_b:
			return order_a < order_b
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
