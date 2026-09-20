extends AudioStreamPlayer
class_name GDFrameExtStreamService
## BGS / Voice 等单轨 stream 扩展服务的公共基类（总线、暂停、源 stream 追踪）。
## 入树时连接 [code]GDFrame.signal_gdframe_audio_paused[/code]。


var _source_stream: AudioStream


func _enter_tree() -> void:
	GDFrame.signal_gdframe_audio_paused.connect(set_audio_paused)


func _exit_tree() -> void:
	GDFrame.signal_gdframe_audio_paused.disconnect(set_audio_paused)


func init_bus(bus_name: StringName) -> void:
	bus = String(bus_name)


func get_source_stream() -> AudioStream:
	return _source_stream


func _clear_source() -> void:
	stop()
	_source_stream = null


func set_audio_paused(paused: bool) -> void:
	stream_paused = paused and playing
