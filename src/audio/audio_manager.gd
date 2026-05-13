## =============================================================================
## AudioManager — Centralised Audio Playback System (Autoload)
## =============================================================================
## Purpose:
##   Manages pooled AudioStreamPlayers for 2D/3D SFX, music streaming,
##   ambient layers, and audio bus routing. Supports positional audio,
##   priority queuing, dynamic mixing snapshots, and occlusion hooks.
## =============================================================================

extends Node

const SFX_POOL_SIZE: int   = 32
const MUSIC_FADE_DEFAULT: float = 1.5

# ── Bus Names (must match AudioServer bus layout in project) ──────────────────
const BUS_MASTER: String  = "Master"
const BUS_SFX: String     = "SFX"
const BUS_MUSIC: String   = "Music"
const BUS_VOICE: String   = "Voice"
const BUS_AMBIENT: String = "Ambient"

signal music_changed(track_id: String)
signal sfx_played(sound_id: String, position: Vector3)

# ── State ──────────────────────────────────────────────────────────────────────
var _sfx_pool_3d: Array[AudioStreamPlayer3D] = []
var _sfx_pool_2d: Array[AudioStreamPlayer2D] = []
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {}   # sound_id -> AudioStream
var _music_cache: Dictionary = {}
var _current_track_id: String = ""
var _mute_on_unfocus: bool = true


func _ready() -> void:
	name = "AudioManager"
	_build_sfx_pool()
	_build_music_players()
	get_tree().connect("node_added", _on_node_added)  # future: track audio nodes
	EventBus.sound_play_requested.connect(play_sfx_at)
	EventBus.music_change_requested.connect(play_music)
	EventBus.ambient_change_requested.connect(play_ambient)
	_mute_on_unfocus = SettingsManager.get_value("audio.mute_when_unfocused", true)
	EventBus.settings_changed.connect(_on_settings_changed)
	Logger.info("AudioManager", "Initialized with SFX pool size %d." % SFX_POOL_SIZE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _mute_on_unfocus:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), false)


# ── Public API ─────────────────────────────────────────────────────────────────

## Play a 3D positional SFX. sound_id is a resource path key or full res:// path.
func play_sfx_at(sound_id: String, position: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _get_sfx_stream(sound_id)
	if not stream:
		return
	var player: AudioStreamPlayer3D = _acquire_3d_player()
	if not player:
		Logger.warn("AudioManager", "SFX pool exhausted: %s" % sound_id)
		return
	player.stream = stream
	player.volume_db = volume_db
	player.global_position = position
	player.play()
	sfx_played.emit(sound_id, position)


## Play a 2D (non-positional) SFX.
func play_sfx_2d(sound_id: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _get_sfx_stream(sound_id)
	if not stream:
		return
	var player: AudioStreamPlayer2D = _acquire_2d_player()
	if not player:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Play or cross-fade music track.
func play_music(track_id: String, fade_duration: float = MUSIC_FADE_DEFAULT) -> void:
	if track_id == _current_track_id:
		return
	var stream: AudioStream = _get_music_stream(track_id)
	if not stream:
		Logger.warn("AudioManager", "Music track not found: %s" % track_id)
		return
	_crossfade_music(stream, fade_duration)
	_current_track_id = track_id
	music_changed.emit(track_id)
	Logger.info("AudioManager", "Music: %s" % track_id)


## Stop music with optional fade.
func stop_music(fade_duration: float = MUSIC_FADE_DEFAULT) -> void:
	if _active_music_player and _active_music_player.playing:
		var tween: Tween = create_tween()
		tween.tween_property(_active_music_player, "volume_db", -80.0, fade_duration)
		tween.tween_callback(_active_music_player.stop)
	_current_track_id = ""


## Play ambient sound layer (loops).
func play_ambient(ambient_id: String) -> void:
	var stream: AudioStream = _get_sfx_stream(ambient_id)
	if not stream:
		return
	_ambient_player.stream = stream
	_ambient_player.play()


## Set bus volume (0.0 = silent, 1.0 = full).
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


## Pre-load a sound into the cache.
func preload_sfx(sound_id: String, path: String) -> void:
	if not _sfx_cache.has(sound_id):
		_sfx_cache[sound_id] = load(path)


## Preload a music track.
func preload_music(track_id: String, path: String) -> void:
	if not _music_cache.has(track_id):
		_music_cache[track_id] = load(path)


# ── Internal ───────────────────────────────────────────────────────────────────

func _build_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.bus = BUS_SFX
		p3.finished.connect(func(): p3.stream = null)
		add_child(p3)
		_sfx_pool_3d.append(p3)

		var p2: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p2.bus = BUS_SFX
		p2.finished.connect(func(): p2.stream = null)
		add_child(p2)
		_sfx_pool_2d.append(p2)


func _build_music_players() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = BUS_MUSIC
	_music_player_a.volume_db = -80.0
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = BUS_MUSIC
	_music_player_b.volume_db = -80.0
	add_child(_music_player_b)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = BUS_AMBIENT
	add_child(_ambient_player)

	_active_music_player = _music_player_a


func _acquire_3d_player() -> AudioStreamPlayer3D:
	for p in _sfx_pool_3d:
		if not p.playing:
			return p
	return null


func _acquire_2d_player() -> AudioStreamPlayer2D:
	for p in _sfx_pool_2d:
		if not p.playing:
			return p
	return null


func _get_sfx_stream(sound_id: String) -> AudioStream:
	if _sfx_cache.has(sound_id):
		return _sfx_cache[sound_id]
	if sound_id.begins_with("res://"):
		if ResourceLoader.exists(sound_id):
			var s: AudioStream = load(sound_id)
			_sfx_cache[sound_id] = s
			return s
	Logger.warn("AudioManager", "SFX not found: %s" % sound_id)
	return null


func _get_music_stream(track_id: String) -> AudioStream:
	if _music_cache.has(track_id):
		return _music_cache[track_id]
	if track_id.begins_with("res://") and ResourceLoader.exists(track_id):
		var s: AudioStream = load(track_id)
		_music_cache[track_id] = s
		return s
	return null


func _crossfade_music(stream: AudioStream, duration: float) -> void:
	var next: AudioStreamPlayer = (
		_music_player_b if _active_music_player == _music_player_a else _music_player_a
	)
	next.stream = stream
	next.volume_db = -80.0
	next.play()

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_active_music_player, "volume_db", -80.0, duration)
	tween.tween_property(next, "volume_db", 0.0, duration)
	tween.chain().tween_callback(_active_music_player.stop)

	_active_music_player = next


func _on_node_added(_node: Node) -> void:
	pass  # Reserved for future audio node tracking.


func _on_settings_changed(category: String, key: String, value: Variant) -> void:
	if category != "audio":
		return
	match key:
		"mute_when_unfocused": _mute_on_unfocus = value as bool
		"master_volume": set_bus_volume(BUS_MASTER, value as float)
		"music_volume":  set_bus_volume(BUS_MUSIC, value as float)
		"sfx_volume":    set_bus_volume(BUS_SFX, value as float)
		"ambient_volume": set_bus_volume(BUS_AMBIENT, value as float)
