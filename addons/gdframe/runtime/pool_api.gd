class_name GDFramePoolApi
extends RefCounted

func register_scene(_key: StringName, _scene: PackedScene) -> bool:
	return false


func get_item(_key: StringName, _parent: Node = null) -> Variant:
	return null


func recycle_item(_key: StringName, _item: Variant) -> void:
	pass
