extends RefCounted
class_name GDFrameAudioManager

# =============================================================================
# Constants
# =============================================================================

const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"
const META_SFX_KEY: StringName = &"gdframe_sfx_key"
const META_SFX_TRACKING: StringName = &"gdframe_sfx_tracking"
const PROFILE_BUS_NAMES: PackedStringArray = ["Master", "Music", "UI", "SFX"]
const LOOP_STREAM_CACHE_MAX: int = 16

# =============================================================================
# State
# =============================================================================

var _save: GDFrameSaveManager
var _root: Node = null
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_active_idx: int = 0
var _bgm_source_stream: AudioStream = null
var _bgm_loop_start_sec: float = -1.0
var _bgm_loop_end_sec: float = -1.0
var _bgm_source_pitch_scale: float = 1.0
var _bgm_volume_linear: float = 1.0
var _default_bgm_crossfade_sec: float = 0.0
var _default_bgm_fade_out_sec: float = 0.0
var _default_sfx_max_per_bus: int = 8
var _default_sfx_max_per_key: int = 4
var _sfx_pool_size: int = 8
var _sfx_spatial_pool_size: int = 4
var _bgm_fade_tween: Tween = null
var _bgm_fade_run_id: int = 0
var _pitch_tween: Tween = null
var _pitch_tween_run_id: int = 0
var _volume_tween: Tween = null
var _volume_tween_run_id: int = 0
var _audio_paused: bool = false
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_2d: Array[AudioStreamPlayer2D] = []
var _sfx_pool_3d: Array[AudioStreamPlayer3D] = []
var _sfx_rr: int = 0
var _sfx_rr_2d: int = 0
var _sfx_rr_3d: int = 0
var _sfx_bus_max: Dictionary[StringName, int] = {}
var _sfx_active_by_bus: Dictionary[StringName, int] = {}
var _sfx_active_by_key: Dictionary[StringName, int] = {}
var _bus_index: Dictionary[StringName, int] = {}
var _prepared_stream_cache: Dictionary = {}
var _prepared_stream_cache_order: Array[String] = []
var _sfx_log_drops: bool = false
var _ui_polyphony: int = 32
var _ui_player: AudioStreamPlayer = null
var _ui_poly_stream: AudioStreamPolyphonic = null
var bgm_changed_listener: Callable = Callable()

# =============================================================================
# Init & setup
# =============================================================================

func _init(save: GDFrameSaveManager) -> void:
	_save = save


func setup(
	root_node: Node,
	bgm_crossfade_sec: float = 0.0,
	bgm_fade_out_sec: float = 0.0,
	sfx_max_per_bus: int = 8,
	sfx_max_per_key: int = 4,
	sfx_pool_size: int = 8,
	sfx_spatial_pool_size: int = 4,
	sfx_log_drops: bool = false,
	ui_polyphony: int = 32,
) -> void:
	# GDFrame 启动时只会调用一次；根节点与 SFX/UI 播放器已就绪则跳过，避免重复建池。
	if _root != null and not _sfx_pool.is_empty() and _ui_player != null:
		return
	_default_bgm_crossfade_sec = maxf(bgm_crossfade_sec, 0.0)
	_default_bgm_fade_out_sec = maxf(bgm_fade_out_sec, 0.0)
	_default_sfx_max_per_bus = maxi(sfx_max_per_bus, 0)
	_default_sfx_max_per_key = maxi(sfx_max_per_key, 0)
	_sfx_pool_size = maxi(sfx_pool_size, 1)
	_sfx_spatial_pool_size = maxi(sfx_spatial_pool_size, 1)
	_sfx_log_drops = sfx_log_drops
	_ui_polyphony = maxi(ui_polyphony, 1)
	if _root == null:
		_root = Node.new()
		_root.name = "GDFrameAudioRoot"
		root_node.add_child(_root)
		_ensure_bus(String(BUS_MUSIC))
		_ensure_bus(String(BUS_UI))
		_ensure_bus(String(BUS_SFX))
		_bus_index[&"Master"] = AudioServer.get_bus_index(&"Master")
		_bus_index[BUS_MUSIC] = AudioServer.get_bus_index(BUS_MUSIC)
		_bus_index[BUS_UI] = AudioServer.get_bus_index(BUS_UI)
		_bus_index[BUS_SFX] = AudioServer.get_bus_index(BUS_SFX)
		for i: int in 2:
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = "BGM_%d" % i
			player.bus = String(BUS_MUSIC)
			player.pitch_scale = 1.0
			_root.add_child(player)
			_bgm_players.append(player)
	_build_sfx_pool()
	_build_sfx_spatial_pools()
	_build_ui_player()
	_validate_sfx_pool_config()


func stop_all_sfx() -> void:
	_stop_sfx_players_in_pool(_sfx_pool)
	_stop_sfx_players_in_pool(_sfx_pool_2d)
	_stop_sfx_players_in_pool(_sfx_pool_3d)


func stop_sfx_by_key(key: StringName) -> void:
	if key.is_empty():
		return
	_stop_sfx_players_in_pool(_sfx_pool, key, &"")
	_stop_sfx_players_in_pool(_sfx_pool_2d, key, &"")
	_stop_sfx_players_in_pool(_sfx_pool_3d, key, &"")


func stop_sfx_on_bus(bus_name: StringName) -> void:
	_stop_sfx_players_in_pool(_sfx_pool, &"", bus_name)
	_stop_sfx_players_in_pool(_sfx_pool_2d, &"", bus_name)
	_stop_sfx_players_in_pool(_sfx_pool_3d, &"", bus_name)


func stop_all_ui_sfx() -> void:
	if _ui_player == null:
		return
	if _ui_player.playing:
		_ui_player.stop()
	_ui_player.play()


func _build_sfx_pool() -> void:
	if _root == null:
		return
	for child: Node in _root.get_children():
		if child is AudioStreamPlayer and str(child.name).begins_with("SFX_"):
			child.queue_free()
	_sfx_pool.clear()
	_sfx_active_by_bus.clear()
	_sfx_active_by_key.clear()
	for idx: int in _sfx_pool_size:
		var sfx: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx.name = "SFX_%d" % idx
		sfx.bus = String(BUS_SFX)
		if not sfx.finished.is_connected(_on_sfx_player_finished):
			sfx.finished.connect(_on_sfx_player_finished.bind(sfx))
		_root.add_child(sfx)
		_sfx_pool.append(sfx)


func _build_sfx_spatial_pools() -> void:
	if _root == null:
		return
	for child: Node in _root.get_children():
		if child is AudioStreamPlayer2D and str(child.name).begins_with("SFX2D_"):
			child.queue_free()
		elif child is AudioStreamPlayer3D and str(child.name).begins_with("SFX3D_"):
			child.queue_free()
	_sfx_pool_2d.clear()
	_sfx_pool_3d.clear()
	for idx: int in _sfx_spatial_pool_size:
		var sfx2d: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sfx2d.name = "SFX2D_%d" % idx
		sfx2d.bus = String(BUS_SFX)
		if not sfx2d.finished.is_connected(_on_sfx_player_finished):
			sfx2d.finished.connect(_on_sfx_player_finished.bind(sfx2d))
		_root.add_child(sfx2d)
		_sfx_pool_2d.append(sfx2d)
		var sfx3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		sfx3d.name = "SFX3D_%d" % idx
		sfx3d.bus = String(BUS_SFX)
		if not sfx3d.finished.is_connected(_on_sfx_player_finished):
			sfx3d.finished.connect(_on_sfx_player_finished.bind(sfx3d))
		_root.add_child(sfx3d)
		_sfx_pool_3d.append(sfx3d)


func _build_ui_player() -> void:
	if _root == null:
		return
	var existing: Node = _root.get_node_or_null("UI_SFX")
	if existing != null:
		existing.queue_free()
	_ui_poly_stream = AudioStreamPolyphonic.new()
	_ui_poly_stream.polyphony = _ui_polyphony
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UI_SFX"
	_ui_player.bus = String(BUS_UI)
	_ui_player.stream = _ui_poly_stream
	_root.add_child(_ui_player)
	_ui_player.play()


func get_root() -> Node:
	return _root


## 预加载并缓存 BGM/SFX 用 stream 副本（整曲 loop 或 WAV A～B 区间）；减少首次播放卡顿。
## [param opts] 可选：[code]loop[/code]、[code]loop_start_sec[/code]、[code]loop_end_sec[/code]（语义同 [method play_bgm]）。
func preload_stream(stream: AudioStream, opts: Dictionary = {}) -> void:
	var loop_start_sec: float = float(opts.get("loop_start_sec", -1.0))
	var loop_end_sec: float = float(opts.get("loop_end_sec", -1.0))
	var use_custom_loop: bool = _is_valid_bgm_loop_region(loop_start_sec, loop_end_sec)
	var loop: bool = false if use_custom_loop else bool(opts.get("loop", false))
	_prepare_bgm_stream(stream, loop, use_custom_loop, loop_start_sec, loop_end_sec)


func _validate_sfx_pool_config() -> void:
	if _default_sfx_max_per_bus <= 0:
		return
	var physical_max: int = _sfx_pool_size + _sfx_spatial_pool_size * 2
	if _default_sfx_max_per_bus <= physical_max:
		return
	push_warning(
		"GDFrame Audio: audio_sfx_max_per_bus (%d) 大于物理播放器总数 (%d = 非空间 %d + 2D %d + 3D %d)；"
		% [
			_default_sfx_max_per_bus,
			physical_max,
			_sfx_pool_size,
			_sfx_spatial_pool_size,
			_sfx_spatial_pool_size,
		]
		+ "同一 SFX 总线上实际最多只能同时播 %d 路，超出部分会返回 false（或 max_per_bus=0 时抢轨）。"
		% physical_max
	)


# =============================================================================
# BGM playback
# =============================================================================

## [param opts] 可选：[code]loop[/code]、[code]from_position[/code]、[code]crossfade_sec[/code]、[code]pitch_scale[/code]、[code]loop_start_sec[/code]、[code]loop_end_sec[/code]（WAV A～B 原生 loop point）。
func play_bgm(stream: AudioStream, opts: Dictionary = {}) -> void:
	if _audio_paused:
		return
	var parsed: Dictionary = _parse_bgm_opts(opts)
	_play_bgm(stream, parsed)


func await_play_bgm(stream: AudioStream, opts: Dictionary = {}) -> void:
	if _audio_paused:
		return
	var parsed: Dictionary = _parse_bgm_opts(opts)
	var will_crossfade: bool = _will_start_bgm_crossfade(stream, parsed)
	_play_bgm(stream, parsed)
	if not will_crossfade:
		return
	await _await_active_tween(_bgm_fade_tween, _bgm_fade_run_id, _bgm_fade_tween_active)


func _play_bgm(stream: AudioStream, parsed: Dictionary) -> void:
	var loop: bool = parsed["loop"]
	var from_position: float = parsed["from_position"]
	var crossfade_sec: float = parsed["crossfade_sec"]
	var loop_start_sec: float = parsed["loop_start_sec"]
	var loop_end_sec: float = parsed["loop_end_sec"]
	var pitch_scale: float = parsed["pitch_scale"]
	var use_custom_loop: bool = parsed["use_custom_loop"]
	var pitch: float = maxf(pitch_scale, 0.01)
	var prepared: AudioStream = _prepare_bgm_stream(stream, loop, use_custom_loop, loop_start_sec, loop_end_sec)
	var start_pos: float = from_position
	if use_custom_loop:
		start_pos = loop_start_sec if from_position < 0.0 else from_position
		start_pos = clampf(start_pos, loop_start_sec, loop_end_sec)
	elif from_position < 0.0:
		start_pos = 0.0
	if _should_skip_bgm_replay(stream, parsed):
		return
	var fade_sec: float = _resolve_crossfade_sec(crossfade_sec)
	_abort_bgm_fade()
	_kill_pitch_tween()
	_bgm_source_stream = stream
	_bgm_source_pitch_scale = pitch
	_set_bgm_loop_region(use_custom_loop, loop_start_sec, loop_end_sec)
	_notify_bgm_changed(stream)
	if fade_sec <= 0.0 or not _active_bgm().playing:
		_switch_bgm_immediate(prepared, start_pos, pitch)
		return
	var outgoing: AudioStreamPlayer = _active_bgm()
	var incoming: AudioStreamPlayer = _inactive_bgm()
	var out_start: float = _bgm_volume_linear
	incoming.stop()
	incoming.stream = prepared
	_set_player_pitch(incoming, pitch)
	incoming.volume_db = linear_to_db(0.0001)
	incoming.play(start_pos)
	_apply_stream_paused(incoming)
	_set_player_linear_volume(outgoing, out_start)
	_bgm_fade_run_id += 1
	var run_id: int = _bgm_fade_run_id
	_bgm_fade_tween = _root.create_tween()
	_bgm_fade_tween.set_parallel(true)
	_bgm_fade_tween.tween_method(
		func(v: float) -> void: _set_player_linear_volume(outgoing, v),
		out_start,
		0.0,
		fade_sec,
	)
	_bgm_fade_tween.tween_method(
		func(v: float) -> void: _set_player_linear_volume(incoming, v),
		0.0,
		_bgm_volume_linear,
		fade_sec,
	)
	_bgm_fade_tween.chain().tween_callback(func() -> void:
		if _bgm_fade_run_id != run_id:
			return
		_kill_pitch_tween()
		outgoing.stop()
		_set_player_linear_volume(outgoing, 1.0)
		_set_player_pitch(outgoing, 1.0)
		_set_player_linear_volume(incoming, _bgm_volume_linear)
		_bgm_active_idx = 1 - _bgm_active_idx
		_bgm_fade_tween = null
	)


## [param fade_out_sec] [code]0[/code] 立刻停止；[code]>0[/code] 淡出；[code]-1[/code] 使用 config 默认 [member GDFrameConfig.audio_bgm_fade_out_sec]。
func stop_bgm(fade_out_sec: float = 0.0) -> void:
	_abort_bgm_fade()
	_kill_pitch_tween()
	_kill_volume_tween()
	var fade_sec: float = _resolve_fade_out_sec(fade_out_sec)
	var playing: Array[AudioStreamPlayer] = _playing_bgm_players()
	if playing.is_empty() or fade_sec <= 0.0:
		_stop_all_bgm_immediate()
		return
	_bgm_fade_run_id += 1
	var run_id: int = _bgm_fade_run_id
	_bgm_fade_tween = _root.create_tween()
	_bgm_fade_tween.set_parallel(true)
	for player: AudioStreamPlayer in playing:
		var vol_start: float = db_to_linear(player.volume_db)
		_bgm_fade_tween.tween_method(
			func(v: float) -> void: _set_player_linear_volume(player, v),
			vol_start,
			0.0,
			fade_sec,
		)
	_bgm_fade_tween.chain().tween_callback(func() -> void:
		if _bgm_fade_run_id != run_id:
			return
		_stop_all_bgm_immediate()
		_bgm_fade_tween = null
	)


func await_stop_bgm(fade_out_sec: float = 0.0) -> void:
	var fade_sec: float = _resolve_fade_out_sec(fade_out_sec)
	var had_playing: bool = is_bgm_playing()
	stop_bgm(fade_out_sec)
	if fade_sec <= 0.0 or not had_playing:
		return
	await _await_active_tween(_bgm_fade_tween, _bgm_fade_run_id, _bgm_fade_tween_active)


func get_bgm_volume_linear() -> float:
	return _bgm_volume_linear


func get_bgm_stream() -> AudioStream:
	return _bgm_source_stream


func is_bgm_playing() -> bool:
	return not _playing_bgm_players().is_empty()


func has_bgm_loop_region() -> bool:
	return _has_custom_bgm_loop()


func get_bgm_playback_position() -> float:
	var player: AudioStreamPlayer = _active_bgm()
	if player.playing:
		return player.get_playback_position()
	for p: AudioStreamPlayer in _bgm_players:
		if p.playing:
			return p.get_playback_position()
	return 0.0


func get_bgm_pitch_scale() -> float:
	var player: AudioStreamPlayer = _active_bgm()
	if player.playing:
		return player.pitch_scale
	return _bgm_source_pitch_scale


func set_bgm_pitch_scale(pitch_scale: float) -> void:
	_kill_pitch_tween()
	var pitch: float = maxf(pitch_scale, 0.01)
	_bgm_source_pitch_scale = pitch
	var player: AudioStreamPlayer = _active_bgm()
	_set_player_pitch(player, pitch, true)


func tween_bgm_pitch_scale(pitch_scale: float, duration_sec: float) -> void:
	var target: float = maxf(pitch_scale, 0.01)
	if duration_sec <= 0.0:
		set_bgm_pitch_scale(target)
		return
	_begin_pitch_tween(target, duration_sec)


func await_tween_bgm_pitch_scale(pitch_scale: float, duration_sec: float) -> void:
	var target: float = maxf(pitch_scale, 0.01)
	if duration_sec <= 0.0:
		set_bgm_pitch_scale(target)
		return
	var run_id: int = _begin_pitch_tween(target, duration_sec)
	if run_id < 0:
		return
	await _await_active_tween(_pitch_tween, run_id, _pitch_tween_active)


func set_bgm_volume_linear(linear: float) -> void:
	if _is_bgm_fade_running():
		return
	_kill_volume_tween()
	_bgm_volume_linear = clampf(linear, 0.0, 1.0)
	_apply_bgm_volume_to_playing()


func tween_bgm_volume_linear(linear: float, duration_sec: float) -> void:
	if _is_bgm_fade_running():
		return
	var target: float = clampf(linear, 0.0, 1.0)
	if duration_sec <= 0.0:
		set_bgm_volume_linear(target)
		return
	_begin_volume_tween(target, duration_sec)


func await_tween_bgm_volume_linear(linear: float, duration_sec: float) -> void:
	if _is_bgm_fade_running():
		return
	var target: float = clampf(linear, 0.0, 1.0)
	if duration_sec <= 0.0:
		set_bgm_volume_linear(target)
		return
	var run_id: int = _begin_volume_tween(target, duration_sec)
	if run_id < 0:
		return
	await _await_active_tween(_volume_tween, run_id, _volume_tween_active)


func set_audio_paused(paused: bool) -> void:
	_audio_paused = paused
	for player: AudioStreamPlayer in _bgm_players:
		_apply_stream_paused(player)
	for player: AudioStreamPlayer in _sfx_pool:
		_apply_stream_paused(player)
	for player: AudioStreamPlayer2D in _sfx_pool_2d:
		_apply_stream_paused_2d(player)
	for player: AudioStreamPlayer3D in _sfx_pool_3d:
		_apply_stream_paused_3d(player)


func is_audio_paused() -> bool:
	return _audio_paused


## 界面音效（Polyphonic；不受 [method set_audio_paused] 拦截，不走 SFX 池）。
## [param opts] 可选：[code]volume_linear[/code]、[code]pitch_scale[/code]、[code]from_position[/code]。
## 复音满时返回 [code]false[/code]。
func play_ui_sfx(stream: AudioStream, opts: Dictionary = {}) -> bool:
	if _ui_player == null:
		push_error("GDFrame Audio: play_ui_sfx ignored — UI SFX player not ready.")
		return false
	if not _ui_player.playing:
		_ui_player.play()
	var playback: Variant = _ui_player.get_stream_playback()
	if playback == null or not playback is AudioStreamPlaybackPolyphonic:
		push_error("GDFrame Audio: play_ui_sfx ignored — invalid polyphonic playback.")
		return false
	var pitch: float = maxf(float(opts.get("pitch_scale", 1.0)), 0.01)
	var volume: float = clampf(float(opts.get("volume_linear", 1.0)), 0.0, 1.0)
	var from_offset: float = maxf(float(opts.get("from_position", 0.0)), 0.0)
	var vol_db: float = linear_to_db(maxf(volume, 0.0001))
	var poly_playback: AudioStreamPlaybackPolyphonic = playback as AudioStreamPlaybackPolyphonic
	var voice_id: int = poly_playback.play_stream(
		stream,
		from_offset,
		vol_db,
		pitch,
		0,
		BUS_UI,
	)
	if voice_id == AudioStreamPlaybackPolyphonic.INVALID_ID:
		_log_ui_sfx_dropped("play_ui_sfx")
		return false
	return true


## [param opts] 可选：[code]bus[/code]、[code]key[/code]、[code]pitch_scale[/code]、[code]volume_linear[/code]（[code]0~1[/code]）。
## 限流未播放时返回 [code]false[/code]。
func play_sfx(stream: AudioStream, opts: Dictionary = {}) -> bool:
	return _play_sfx_from_pool(_sfx_pool, _sfx_rr, stream, opts, "play_sfx")


## 在 [param position] 播放 2D 音效；opts 同 [method play_sfx]。
func play_sfx_2d(stream: AudioStream, position: Vector2, opts: Dictionary = {}) -> bool:
	var ok: bool = _play_sfx_from_pool(_sfx_pool_2d, _sfx_rr_2d, stream, opts, "play_sfx_2d")
	if not ok:
		return false
	var player: AudioStreamPlayer2D = _last_started_spatial_2d
	if player != null:
		player.global_position = position
	return true


var _last_started_spatial_2d: AudioStreamPlayer2D = null


## 在 [param position] 播放 3D 音效；opts 同 [method play_sfx]。
func play_sfx_3d(stream: AudioStream, position: Vector3, opts: Dictionary = {}) -> bool:
	var ok: bool = _play_sfx_from_pool(_sfx_pool_3d, _sfx_rr_3d, stream, opts, "play_sfx_3d")
	if not ok:
		return false
	var player: AudioStreamPlayer3D = _last_started_spatial_3d
	if player != null:
		player.global_position = position
	return true


var _last_started_spatial_3d: AudioStreamPlayer3D = null


func set_sfx_max_per_bus(bus_name: StringName, max_count: int) -> void:
	_sfx_bus_max[bus_name] = maxi(max_count, 0)


func set_sfx_max_per_key(max_count: int) -> void:
	_default_sfx_max_per_key = maxi(max_count, 0)

# =============================================================================
# Bus volume
# =============================================================================

static func default_bus_volumes() -> Dictionary[String, float]:
	return {
		"Master": 1.0,
		"Music": 1.0,
		"UI": 1.0,
		"SFX": 1.0,
	}


static func default_bus_muted() -> Dictionary[String, bool]:
	return {
		"Master": false,
		"Music": false,
		"UI": false,
		"SFX": false,
	}


## 补齐档案中的核心总线键（缺项写入 [method default_bus_volumes] / [method default_bus_muted]）。
static func ensure_profile_bus_keys(prof: GDFrameProfileResource) -> void:
	prof.ensure_children()
	var defaults: Dictionary = default_bus_volumes()
	var default_mutes: Dictionary = default_bus_muted()
	for key: String in PROFILE_BUS_NAMES:
		if not prof.settings.bus_linear.has(key):
			prof.settings.bus_linear[key] = float(defaults.get(key, 1.0))
		if not prof.settings.bus_muted.has(key):
			prof.settings.bus_muted[key] = bool(default_mutes.get(key, false))


## 为 Ogg / MP3 / WAV 生成整曲可循环副本。
static func with_loop(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		var dup: AudioStreamOggVorbis = (stream as AudioStreamOggVorbis).duplicate()
		dup.loop = true
		return dup
	if stream is AudioStreamMP3:
		var dup_mp3: AudioStreamMP3 = (stream as AudioStreamMP3).duplicate()
		dup_mp3.loop = true
		return dup_mp3
	if stream is AudioStreamWAV:
		var dup_wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
		dup_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return dup_wav
	return stream


func set_bus_volume_linear(bus_name: StringName, linear: float) -> void:
	var clamped: float = clampf(linear, 0.0, 1.0)
	_profile_ref().settings.bus_linear[String(bus_name)] = clamped
	_apply_bus_effective(bus_name)


func get_bus_volume_linear(bus_name: StringName) -> float:
	var stored: Variant = _profile_ref().settings.bus_linear.get(String(bus_name), null)
	if stored is float or stored is int:
		return clampf(float(stored), 0.0, 1.0)
	var idx: int = _bus_index.get(bus_name, -1)
	if idx < 0:
		idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func get_bus_muted(bus_name: StringName) -> bool:
	return bool(_profile_ref().settings.bus_muted.get(String(bus_name), false))


func set_bus_muted(bus_name: StringName, muted: bool) -> void:
	_profile_ref().settings.bus_muted[String(bus_name)] = muted
	_apply_bus_effective(bus_name)


func preview_bus_effective(bus_name: StringName, linear: float, muted: bool) -> void:
	var effective: float = 0.0 if muted else clampf(linear, 0.0, 1.0)
	_apply_bus_linear(bus_name, effective)


func apply_from_profile(extra_bus_names: Array[StringName] = []) -> void:
	for bus_name: String in PROFILE_BUS_NAMES:
		_apply_bus_effective(StringName(bus_name))
	for bus: StringName in extra_bus_names:
		ensure_and_apply_bus_from_profile(bus)


func ensure_and_apply_bus_from_profile(bus_name: StringName) -> void:
	_ensure_bus(String(bus_name))
	_apply_bus_effective(bus_name)

# =============================================================================
# Private
# =============================================================================

func _active_bgm() -> AudioStreamPlayer:
	return _bgm_players[_bgm_active_idx]


func _inactive_bgm() -> AudioStreamPlayer:
	return _bgm_players[1 - _bgm_active_idx]


func _playing_bgm_players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for player: AudioStreamPlayer in _bgm_players:
		if player.playing:
			out.append(player)
	return out


func _apply_stream_paused(player: AudioStreamPlayer) -> void:
	player.stream_paused = _audio_paused and player.playing


func _apply_stream_paused_2d(player: AudioStreamPlayer2D) -> void:
	player.stream_paused = _audio_paused and player.playing


func _apply_stream_paused_3d(player: AudioStreamPlayer3D) -> void:
	player.stream_paused = _audio_paused and player.playing


func _set_player_pitch(player: AudioStreamPlayer, pitch_scale: float, only_if_playing: bool = false) -> void:
	if only_if_playing and (not is_instance_valid(player) or not player.playing):
		return
	player.pitch_scale = maxf(pitch_scale, 0.01)


func _kill_pitch_tween() -> void:
	if _pitch_tween != null and _pitch_tween.is_valid():
		_pitch_tween.kill()
	_pitch_tween = null
	_pitch_tween_run_id += 1


func _begin_pitch_tween(target: float, duration_sec: float) -> int:
	_kill_pitch_tween()
	var player: AudioStreamPlayer = _active_bgm()
	if not player.playing:
		_bgm_source_pitch_scale = target
		return -1
	var start: float = player.pitch_scale
	if is_equal_approx(start, target):
		_bgm_source_pitch_scale = target
		return -1
	var run_id: int = _pitch_tween_run_id
	var bound: AudioStreamPlayer = player
	_pitch_tween = _root.create_tween()
	_pitch_tween.tween_method(
		func(v: float) -> void: _set_player_pitch(bound, v, true),
		start,
		target,
		duration_sec,
	)
	_pitch_tween.chain().tween_callback(func() -> void:
		if _pitch_tween_run_id != run_id:
			return
		if is_instance_valid(bound) and bound == _active_bgm() and bound.playing:
			_bgm_source_pitch_scale = target
			_set_player_pitch(bound, target)
		_pitch_tween = null
	)
	return run_id


func _apply_bgm_volume_to_playing() -> void:
	for player: AudioStreamPlayer in _bgm_players:
		if player.playing:
			_set_player_linear_volume(player, _bgm_volume_linear)


func _set_bgm_volume_live(v: float) -> void:
	_bgm_volume_linear = clampf(v, 0.0, 1.0)
	_apply_bgm_volume_to_playing()


func _kill_volume_tween() -> void:
	if _volume_tween != null and _volume_tween.is_valid():
		_volume_tween.kill()
	_volume_tween = null
	_volume_tween_run_id += 1


func _begin_volume_tween(target: float, duration_sec: float) -> int:
	if _is_bgm_fade_running():
		return -1
	_kill_volume_tween()
	if is_equal_approx(_bgm_volume_linear, target):
		return -1
	var run_id: int = _volume_tween_run_id
	var start: float = _bgm_volume_linear
	_volume_tween = _root.create_tween()
	_volume_tween.tween_method(_set_bgm_volume_live, start, target, duration_sec)
	_volume_tween.chain().tween_callback(func() -> void:
		if _volume_tween_run_id != run_id:
			return
		_bgm_volume_linear = target
		_apply_bgm_volume_to_playing()
		_volume_tween = null
	)
	return run_id


func _resolve_crossfade_sec(sec: float) -> float:
	if sec >= 0.0:
		return sec
	return _default_bgm_crossfade_sec


func _resolve_fade_out_sec(sec: float) -> float:
	if sec >= 0.0:
		return sec
	return _default_bgm_fade_out_sec


func _await_active_tween(tween: Tween, expected_run_id: int, is_still_active: Callable) -> void:
	while is_still_active.call(expected_run_id, tween):
		if tween.is_valid() and not tween.is_running():
			break
		await _root.get_tree().process_frame


func _bgm_fade_tween_active(expected_run_id: int, tween: Tween) -> bool:
	return _bgm_fade_run_id == expected_run_id and tween != null


func _pitch_tween_active(expected_run_id: int, tween: Tween) -> bool:
	return _pitch_tween_run_id == expected_run_id and tween != null


func _volume_tween_active(expected_run_id: int, tween: Tween) -> bool:
	return _volume_tween_run_id == expected_run_id and tween != null


func _abort_bgm_fade() -> void:
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_fade_tween = null
	_bgm_fade_run_id += 1
	var incoming: AudioStreamPlayer = _inactive_bgm()
	incoming.stop()
	_set_player_linear_volume(incoming, 1.0)
	_set_player_pitch(incoming, 1.0)


func _play_sfx_from_pool(
	pool: Array,
	rr: int,
	stream: AudioStream,
	opts: Dictionary,
	method_label: String,
) -> bool:
	if pool.is_empty():
		push_error("GDFrame Audio: %s ignored — SFX pool is empty." % method_label)
		return false
	if _audio_paused:
		return false
	var bus: StringName = BUS_SFX
	if opts.has("bus"):
		bus = StringName(str(opts["bus"]))
	var key: StringName = &""
	if opts.has("key"):
		key = StringName(str(opts["key"]))
	var pitch: float = maxf(float(opts.get("pitch_scale", 1.0)), 0.01)
	var volume: float = clampf(float(opts.get("volume_linear", 1.0)), 0.0, 1.0)
	if not _sfx_bus_max.has(bus) and bus != BUS_SFX:
		_ensure_bus(String(bus))
	if not _can_play_sfx(bus, key):
		_log_sfx_dropped(bus, key, method_label)
		return false
	var player: Variant = _find_free_sfx_in_pool(pool, rr)
	var next_rr: int = rr
	if player == null:
		if _resolve_sfx_bus_max(bus) == 0 and pool.size() > 0:
			next_rr = rr % pool.size()
			player = pool[next_rr]
			_stop_sfx_player(player)
			next_rr = (next_rr + 1) % pool.size()
		else:
			_log_sfx_dropped(bus, key, "%s (pool busy)" % method_label)
			return false
	else:
		next_rr = _advance_sfx_rr(pool, rr, player)
	if pool == _sfx_pool:
		_sfx_rr = next_rr
	elif pool == _sfx_pool_2d:
		_sfx_rr_2d = next_rr
		_last_started_spatial_2d = player as AudioStreamPlayer2D
	elif pool == _sfx_pool_3d:
		_sfx_rr_3d = next_rr
		_last_started_spatial_3d = player as AudioStreamPlayer3D
	_apply_sfx_player(player, stream, bus, key, pitch, volume)
	return true


func _apply_sfx_player(
	player: Variant,
	stream: AudioStream,
	bus: StringName,
	key: StringName,
	pitch: float,
	volume: float,
) -> void:
	player.bus = String(bus)
	player.stream = stream
	if player is AudioStreamPlayer:
		_set_player_pitch(player, pitch)
	elif player is AudioStreamPlayer2D or player is AudioStreamPlayer3D:
		player.pitch_scale = maxf(pitch, 0.01)
	_set_player_linear_volume(player, volume)
	if key.is_empty():
		if player.has_meta(META_SFX_KEY):
			player.remove_meta(META_SFX_KEY)
	else:
		player.set_meta(META_SFX_KEY, key)
	_track_sfx_player(player, bus, key)
	player.play()
	if player is AudioStreamPlayer:
		_apply_stream_paused(player)
	elif player is AudioStreamPlayer2D:
		_apply_stream_paused_2d(player)
	elif player is AudioStreamPlayer3D:
		_apply_stream_paused_3d(player)


func _resolve_sfx_bus_max(bus: StringName) -> int:
	if _sfx_bus_max.has(bus):
		return _sfx_bus_max[bus]
	return _default_sfx_max_per_bus


func _can_play_sfx(bus: StringName, key: StringName) -> bool:
	var bus_max: int = _resolve_sfx_bus_max(bus)
	if bus_max > 0 and _count_sfx_on_bus(bus) >= bus_max:
		return false
	if not key.is_empty() and _default_sfx_max_per_key > 0:
		if _count_sfx_with_key(key) >= _default_sfx_max_per_key:
			return false
	return true


func _count_sfx_on_bus(bus: StringName) -> int:
	return int(_sfx_active_by_bus.get(bus, 0))


func _count_sfx_with_key(key: StringName) -> int:
	if key.is_empty():
		return 0
	return int(_sfx_active_by_key.get(key, 0))


func _track_sfx_player(player: Variant, bus: StringName, key: StringName) -> void:
	if player.has_meta(META_SFX_TRACKING):
		_untrack_sfx_player(player)
	_sfx_active_by_bus[bus] = int(_sfx_active_by_bus.get(bus, 0)) + 1
	if not key.is_empty():
		_sfx_active_by_key[key] = int(_sfx_active_by_key.get(key, 0)) + 1
	player.set_meta(META_SFX_TRACKING, true)


func _untrack_sfx_player(player: Variant) -> void:
	if not player.has_meta(META_SFX_TRACKING):
		return
	player.remove_meta(META_SFX_TRACKING)
	var bus: StringName = StringName(String(player.bus))
	var key: StringName = player.get_meta(META_SFX_KEY, &"") as StringName
	if _sfx_active_by_bus.has(bus):
		var next_bus: int = int(_sfx_active_by_bus[bus]) - 1
		if next_bus <= 0:
			_sfx_active_by_bus.erase(bus)
		else:
			_sfx_active_by_bus[bus] = next_bus
	if not key.is_empty() and _sfx_active_by_key.has(key):
		var next_key: int = int(_sfx_active_by_key[key]) - 1
		if next_key <= 0:
			_sfx_active_by_key.erase(key)
		else:
			_sfx_active_by_key[key] = next_key


func _on_sfx_player_finished(player: Variant) -> void:
	_untrack_sfx_player(player)
	if player.has_meta(META_SFX_KEY):
		player.remove_meta(META_SFX_KEY)


func _find_free_sfx_in_pool(pool: Array, rr: int) -> Variant:
	for i: int in pool.size():
		var idx: int = (rr + i) % pool.size()
		var player: Variant = pool[idx]
		if not player.playing:
			return player
	return null


func _advance_sfx_rr(pool: Array, rr: int, player: Variant) -> int:
	for i: int in pool.size():
		var idx: int = (rr + i) % pool.size()
		if pool[idx] == player:
			return (idx + 1) % pool.size()
	return (rr + 1) % maxi(pool.size(), 1)


func _stop_sfx_player(player: Variant) -> void:
	_untrack_sfx_player(player)
	player.stop()
	if player.has_meta(META_SFX_KEY):
		player.remove_meta(META_SFX_KEY)


func _log_sfx_dropped(bus: StringName, key: StringName, method_label: String) -> void:
	var msg: String = "GDFrame Audio: %s dropped (bus=%s, key=%s)." % [
		method_label,
		String(bus),
		String(key),
	]
	_log_drop_message(msg)


func _log_ui_sfx_dropped(method_label: String) -> void:
	var msg: String = "GDFrame Audio: %s dropped (UI polyphony full)." % method_label
	_log_drop_message(msg)


func _log_drop_message(msg: String) -> void:
	if not _sfx_log_drops:
		return
	if OS.has_feature("editor"):
		push_warning(msg)
	else:
		print(msg)


func _stop_sfx_players_in_pool(
	players: Array,
	key_filter: StringName = &"",
	bus_filter: StringName = &"",
) -> void:
	var bus_str: String = String(bus_filter)
	for player: Variant in players:
		if not player.playing:
			continue
		if not key_filter.is_empty() and player.get_meta(META_SFX_KEY, &"") != key_filter:
			continue
		if not bus_filter.is_empty() and String(player.bus) != bus_str:
			continue
		_stop_sfx_player(player)


func _switch_bgm_immediate(prepared: AudioStream, from_position: float, pitch_scale: float) -> void:
	var inactive: AudioStreamPlayer = _inactive_bgm()
	inactive.stop()
	var active: AudioStreamPlayer = _active_bgm()
	active.stop()
	active.stream = prepared
	_set_player_pitch(active, pitch_scale)
	_set_player_linear_volume(active, _bgm_volume_linear)
	active.play(from_position)
	_apply_stream_paused(active)


func _stop_all_bgm_immediate() -> void:
	var had_bgm: bool = _bgm_source_stream != null
	_kill_pitch_tween()
	_kill_volume_tween()
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_fade_tween = null
	_bgm_fade_run_id += 1
	_set_bgm_loop_region(false, -1.0, -1.0)
	for player: AudioStreamPlayer in _bgm_players:
		player.stop()
		_set_player_linear_volume(player, 1.0)
		_set_player_pitch(player, 1.0)
	_bgm_source_stream = null
	_bgm_source_pitch_scale = 1.0
	if had_bgm:
		_notify_bgm_changed(null)


func _set_player_linear_volume(player: Variant, linear: float) -> void:
	player.volume_db = linear_to_db(maxf(clampf(linear, 0.0, 1.0), 0.0001))


func _profile_ref() -> GDFrameProfileResource:
	return _save.get_profile()


func _apply_bus_effective(bus_name: StringName) -> void:
	var linear: float = get_bus_volume_linear(bus_name)
	if get_bus_muted(bus_name):
		linear = 0.0
	_apply_bus_linear(bus_name, linear)


func _apply_bus_linear(bus_name: StringName, linear: float) -> float:
	var clamped: float = clampf(linear, 0.0, 1.0)
	var idx: int = _bus_index.get(bus_name, -1)
	if idx < 0:
		idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return clamped
	if clamped <= 0.0:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))
	return clamped


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	_bus_index[StringName(bus_name)] = AudioServer.get_bus_index(bus_name)


func _prepared_stream_cache_key(
	stream: AudioStream,
	loop: bool,
	use_custom_loop: bool,
	loop_start_sec: float,
	loop_end_sec: float,
) -> String:
	return "%d:%s:%s:%f:%f" % [
		stream.get_instance_id(),
		loop,
		use_custom_loop,
		loop_start_sec,
		loop_end_sec,
	]


func _prepare_bgm_stream(
	stream: AudioStream,
	loop: bool,
	use_custom_loop: bool,
	loop_start_sec: float,
	loop_end_sec: float,
) -> AudioStream:
	var cache_key: String = _prepared_stream_cache_key(
		stream, loop, use_custom_loop, loop_start_sec, loop_end_sec
	)
	if _prepared_stream_cache.has(cache_key):
		_touch_prepared_stream_cache(cache_key)
		return _prepared_stream_cache[cache_key]
	var out: AudioStream = stream
	if use_custom_loop:
		out = with_loop_region(stream, loop_start_sec, loop_end_sec)
	elif loop:
		out = with_loop(stream)
	_prepared_stream_cache[cache_key] = out
	_prepared_stream_cache_order.append(cache_key)
	while _prepared_stream_cache_order.size() > LOOP_STREAM_CACHE_MAX:
		var evict_key: String = _prepared_stream_cache_order.pop_front()
		_prepared_stream_cache.erase(evict_key)
	return out


func _touch_prepared_stream_cache(cache_key: String) -> void:
	var idx: int = _prepared_stream_cache_order.find(cache_key)
	if idx >= 0:
		_prepared_stream_cache_order.remove_at(idx)
	_prepared_stream_cache_order.append(cache_key)


## WAV A～B 区间：写入 [member AudioStreamWAV.loop_begin] / [member AudioStreamWAV.loop_end]（采样点）。
static func with_loop_region(stream: AudioStream, loop_start_sec: float, loop_end_sec: float) -> AudioStream:
	if stream is AudioStreamWAV:
		var dup: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
		var rate: float = maxf(float(dup.mix_rate), 1.0)
		dup.loop_mode = AudioStreamWAV.LOOP_FORWARD
		dup.loop_begin = maxi(int(loop_start_sec * rate), 0)
		dup.loop_end = maxi(int(loop_end_sec * rate), dup.loop_begin + 1)
		return dup
	if OS.has_feature("editor"):
		push_warning(
			"GDFrame Audio: A~B loop region requires AudioStreamWAV; got %s."
			% stream.get_class()
		)
	return stream.duplicate()


func _is_valid_bgm_loop_region(loop_start_sec: float, loop_end_sec: float) -> bool:
	return loop_start_sec >= 0.0 and loop_end_sec > loop_start_sec


func _has_custom_bgm_loop() -> bool:
	return _is_valid_bgm_loop_region(_bgm_loop_start_sec, _bgm_loop_end_sec)


func _bgm_loop_region_matches(use_custom_loop: bool, loop_start_sec: float, loop_end_sec: float) -> bool:
	if not use_custom_loop:
		return not _has_custom_bgm_loop()
	return (
		_has_custom_bgm_loop()
		and is_equal_approx(_bgm_loop_start_sec, loop_start_sec)
		and is_equal_approx(_bgm_loop_end_sec, loop_end_sec)
	)


func _set_bgm_loop_region(use_custom_loop: bool, loop_start_sec: float, loop_end_sec: float) -> void:
	if use_custom_loop:
		_bgm_loop_start_sec = loop_start_sec
		_bgm_loop_end_sec = loop_end_sec
	else:
		_bgm_loop_start_sec = -1.0
		_bgm_loop_end_sec = -1.0


func _parse_bgm_opts(opts: Dictionary) -> Dictionary:
	var loop_start_sec: float = float(opts.get("loop_start_sec", -1.0))
	var loop_end_sec: float = float(opts.get("loop_end_sec", -1.0))
	var use_custom_loop: bool = _is_valid_bgm_loop_region(loop_start_sec, loop_end_sec)
	var loop: bool = false if use_custom_loop else bool(opts.get("loop", true))
	var from_position: float = float(opts["from_position"]) if opts.has("from_position") else -1.0
	return {
		"loop": loop,
		"from_position": from_position,
		"crossfade_sec": float(opts.get("crossfade_sec", -1.0)),
		"loop_start_sec": loop_start_sec,
		"loop_end_sec": loop_end_sec,
		"pitch_scale": float(opts.get("pitch_scale", 1.0)),
		"use_custom_loop": use_custom_loop,
	}


func _should_skip_bgm_replay(stream: AudioStream, parsed: Dictionary) -> bool:
	var pitch: float = maxf(float(parsed["pitch_scale"]), 0.01)
	var use_custom_loop: bool = parsed["use_custom_loop"]
	return (
		_bgm_source_stream == stream
		and _bgm_loop_region_matches(
			use_custom_loop,
			float(parsed["loop_start_sec"]),
			float(parsed["loop_end_sec"]),
		)
		and is_equal_approx(_bgm_source_pitch_scale, pitch)
		and _active_bgm().playing
		and float(parsed["from_position"]) < 0.0
	)


func _will_start_bgm_crossfade(stream: AudioStream, parsed: Dictionary) -> bool:
	if _should_skip_bgm_replay(stream, parsed):
		return false
	if _resolve_crossfade_sec(float(parsed["crossfade_sec"])) <= 0.0:
		return false
	return _active_bgm().playing


func _is_bgm_fade_running() -> bool:
	return _bgm_fade_tween != null and _bgm_fade_tween.is_valid() and _bgm_fade_tween.is_running()


func _notify_bgm_changed(stream: AudioStream) -> void:
	if bgm_changed_listener.is_valid():
		bgm_changed_listener.call(stream)
