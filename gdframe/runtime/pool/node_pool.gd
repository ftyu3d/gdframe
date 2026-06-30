class_name GDFrameNodePool
extends RefCounted

# =============================================================================
# State
# =============================================================================

var _store: Dictionary[StringName, Dictionary] = {}
var _log_limits: bool = false

# =============================================================================
# Public API
# =============================================================================

func setup(log_limits: bool = false) -> void:
	_log_limits = log_limits

func register_scene(key: StringName, scene: PackedScene) -> bool:
	if _store.has(key):
		if not clear(key, true):
			return false
	_store[key] = _make_bucket_scene(scene)
	return true

func set_limits(key: StringName, max_idle: int = 0, max_active: int = 0) -> void:
	if not _store.has(key):
		push_error("GDFrame Pool: 未注册的 key，set_limits 忽略: %s" % key)
		return
	var bucket: Dictionary = _store[key]
	bucket["max_idle"] = maxi(0, max_idle)
	bucket["max_active"] = maxi(0, max_active)

func warmup(key: StringName, count: int) -> void:
	if not _store.has(key):
		if count > 0:
			push_error("GDFrame Pool: 未注册的 key，warmup 忽略: %s" % key)
		return
	if count <= 0:
		return
	var items: Array = _store[key]["items"]
	for repeat_index in range(count):
		items.append(_create_item(_store[key]))

func warmup_factory(key: StringName, factory: Callable, count: int) -> bool:
	if _store.has(key):
		if not clear(key, true):
			return false
	_store[key] = _make_bucket_factory(factory)
	var bucket: Dictionary = _store[key]
	var items: Array = bucket["items"]
	for repeat_index in range(count):
		items.append(_create_item(bucket))
	return true

func get_item(key: StringName, parent: Node = null) -> Variant:
	if not _store.has(key):
		push_error("GDFrame Pool: 未注册的 key，pool_get 返回 null: %s" % key)
		return null
	var bucket: Dictionary = _store[key]
	var max_active: int = bucket["max_active"]
	if max_active > 0 and bucket["active"] >= max_active:
		_log_limit_message("GDFrame Pool: max_active 已满，pool_get 返回 null: %s" % key)
		if EngineDebugger.is_active():
			bucket["active_get_rejects"] += 1
		return null
	var items: Array = bucket["items"]
	var item: Variant
	if items.is_empty():
		item = _create_item(bucket)
	else:
		item = items.pop_back()
		_untrack_idle(bucket, item)
	bucket["active"] += 1
	bucket["peak_active"] = maxi(bucket["peak_active"], bucket["active"])
	_track_active(bucket, item)
	if item is Node:
		if parent != null and item.get_parent() != parent:
			parent.add_child(item)
		item.set_process_mode(Node.PROCESS_MODE_INHERIT)
		if item is CanvasItem:
			(item as CanvasItem).show()
		elif item is Node3D:
			(item as Node3D).show()
		_notify_pool_get(item)
	return item

func recycle_item(key: StringName, item: Variant) -> void:
	if not _store.has(key):
		push_error("GDFrame Pool: 未注册的 key，recycle 忽略: %s" % key)
		return
	var bucket: Dictionary = _store[key]
	if _is_idle(bucket, item):
		push_error("GDFrame Pool: recycle 跳过（项已在空闲列表，重复 recycle）: %s" % key)
		return
	if not _is_active(bucket, item):
		push_error("GDFrame Pool: recycle 跳过（非本池 active 项或错 key）: %s" % key)
		return
	_untrack_active(bucket, item)
	if bucket["active"] > 0:
		bucket["active"] -= 1
	if item is Node:
		var parent: Node = item.get_parent()
		if parent != null:
			parent.remove_child(item)
		if item is CanvasItem:
			(item as CanvasItem).hide()
		elif item is Node3D:
			(item as Node3D).hide()
		item.set_process_mode(Node.PROCESS_MODE_DISABLED)
		_notify_pool_recycle(item)
	var max_idle: int = bucket["max_idle"]
	if max_idle > 0 and bucket["items"].size() >= max_idle:
		_discard_item(item)
		return
	bucket["items"].append(item)
	_track_idle(bucket, item)

## 清空空闲列表；[param free_nodes] 为 [code]true[/code] 时 [code]queue_free[/code] 空闲实例。
## 仍有 [code]pool_get[/code] 借出项时拒绝并 [code]push_error[/code]（避免 active 追踪失真）。
func clear(key: StringName, free_nodes: bool = false) -> bool:
	if not _store.has(key):
		return true
	var bucket: Dictionary = _store[key]
	if int(bucket["active"]) > 0:
		push_error(
			"GDFrame Pool: clear 拒绝（仍有 %d 个借出项，请先 pool_recycle）: %s"
			% [int(bucket["active"]), key]
		)
		return false
	if free_nodes:
		for pooled in bucket["items"]:
			_discard_item(pooled)
	bucket["items"] = []
	bucket["idle_keys"] = {}
	bucket["active_keys"] = {}
	bucket["active"] = 0
	return true

func get_stats(key: StringName) -> Dictionary:
	if not _store.has(key):
		push_error("GDFrame Pool: 未注册的 key，pool_stats 返回空字典: %s" % key)
		return {}
	return _bucket_stats(_store[key])

func get_all_stats() -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in _store:
		out[String(k)] = _bucket_stats(_store[k])
	return out

# =============================================================================
# Bucket internals
# =============================================================================

func _empty_bucket_meta() -> Dictionary:
	return {
		"items": [],
		"idle_keys": {},
		"active_keys": {},
		"active": 0,
		"total_created": 0,
		"peak_active": 0,
		"max_idle": 0,
		"max_active": 0,
		"active_get_rejects": 0,
	}

func _make_bucket_scene(scene: PackedScene) -> Dictionary:
	var b: Dictionary = _empty_bucket_meta()
	b["scene"] = scene
	return b

func _make_bucket_factory(factory: Callable) -> Dictionary:
	var b: Dictionary = _empty_bucket_meta()
	b["factory"] = factory
	return b

func _create_item(bucket: Dictionary) -> Variant:
	var item: Variant = null
	if bucket.has("factory"):
		item = bucket["factory"].call()
	elif bucket.has("scene"):
		item = bucket["scene"].instantiate()
	if item != null:
		bucket["total_created"] += 1
	else:
		push_error("GDFrame Pool: 创建实例失败（检查 scene 或 factory 返回值）")
	return item

func _bucket_stats(bucket: Dictionary) -> Dictionary:
	return {
		"idle": bucket["items"].size(),
		"active": bucket["active"],
		"peak_active": bucket["peak_active"],
		"total_created": bucket["total_created"],
		"max_idle": bucket["max_idle"],
		"max_active": bucket["max_active"],
		"active_get_rejects": bucket["active_get_rejects"],
	}

func _idle_key(item: Variant) -> Variant:
	return item.get_instance_id() if item is Node else item

func _is_idle(bucket: Dictionary, item: Variant) -> bool:
	return bucket["idle_keys"].has(_idle_key(item))

func _is_active(bucket: Dictionary, item: Variant) -> bool:
	return bucket["active_keys"].has(_idle_key(item))

func _track_active(bucket: Dictionary, item: Variant) -> void:
	bucket["active_keys"][_idle_key(item)] = true

func _untrack_active(bucket: Dictionary, item: Variant) -> void:
	bucket["active_keys"].erase(_idle_key(item))

func _track_idle(bucket: Dictionary, item: Variant) -> void:
	bucket["idle_keys"][_idle_key(item)] = true

func _untrack_idle(bucket: Dictionary, item: Variant) -> void:
	bucket["idle_keys"].erase(_idle_key(item))

func _discard_item(item: Variant) -> void:
	if item is Node:
		item.queue_free()

func _notify_pool_get(item: Node) -> void:
	if item is GDFramePoolPooled:
		(item as GDFramePoolPooled).on_pool_get()

func _notify_pool_recycle(item: Node) -> void:
	if item is GDFramePoolPooled:
		(item as GDFramePoolPooled).on_pool_recycle()

func _log_limit_message(msg: String) -> void:
	if not _log_limits:
		return
	if OS.has_feature("editor"):
		push_warning(msg)
	else:
		print(msg)

