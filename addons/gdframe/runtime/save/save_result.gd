class_name GDFrameResult
extends RefCounted

const OK := &""
const ERR_SAVE_WRITE_FAILED := &"save_write_failed"
const ERR_SAVE_CORRUPTED := &"save_corrupted"
const ERR_SAVE_DELETE_FAILED := &"save_delete_failed"


static func is_ok(err: StringName) -> bool:
	return err == OK
