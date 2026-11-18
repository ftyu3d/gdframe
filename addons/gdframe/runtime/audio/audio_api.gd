class_name GDFrameAudioApi
extends RefCounted
## 音频可选调用的公共接口。未启用扩展时播放请求返回空结果。

func play_bgm(_stream: AudioStream, _opts: Dictionary = {}) -> void:
	pass


func stop_bgm(_fade_out_sec: float = 0.0) -> void:
	pass


func is_bgm_playing() -> bool:
	return false


func play_sfx(_stream: AudioStream, _bus: StringName = &"SFX", _opts: Dictionary = {}) -> bool:
	return false


func play_ui_sfx(_stream: AudioStream, _opts: Dictionary = {}) -> bool:
	return false


func set_paused(_paused: bool) -> void:
	pass
