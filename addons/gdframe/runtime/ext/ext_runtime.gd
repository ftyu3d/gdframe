extends RefCounted
## 扩展运行时：汇总各模块的额外总线并应用到引擎。


static func collect_extra_bus_names(modules: Array[Script]) -> Array[StringName]:
	var out: Array[StringName] = []
	var seen: Dictionary = {}
	for mod: Script in modules:
		if not mod.has_method(&"extra_bus_names"):
			continue
		var names: Variant = mod.call(&"extra_bus_names")
		if names is Array:
			for bus: Variant in names:
				if bus is StringName and not seen.has(bus):
					seen[bus] = true
					out.append(bus)
	return out


static func merge_extra_bus_defaults(snap: Dictionary, modules: Array[Script]) -> Dictionary:
	var out: Dictionary = snap.duplicate(true)
	var buses: Dictionary = out.get("bus_linear", {}).duplicate() if out.get("bus_linear") is Dictionary else {}
	var mutes: Dictionary = out.get("bus_muted", {}).duplicate() if out.get("bus_muted") is Dictionary else {}
	for bus: StringName in collect_extra_bus_names(modules):
		var key: String = String(bus)
		if not buses.has(key):
			buses[key] = 1.0
		if not mutes.has(key):
			mutes[key] = false
	out["bus_linear"] = buses
	out["bus_muted"] = mutes
	return out


static var _modules: Array[Script] = []


static func set_modules(modules: Array[Script]) -> void:
	_modules = modules


static func get_modules() -> Array[Script]:
	return _modules


static func ensure_extra_bus_profile_keys(prof: GDFrameProfileResource, modules: Array[Script]) -> void:
	prof.ensure_children()
	for bus: StringName in collect_extra_bus_names(modules):
		var key: String = String(bus)
		if not prof.settings.bus_linear.has(key):
			prof.settings.bus_linear[key] = 1.0
		if not prof.settings.bus_muted.has(key):
			prof.settings.bus_muted[key] = false
