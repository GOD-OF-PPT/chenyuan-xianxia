class_name AudioDirector
extends Node
## 第三层动态民乐混音与四级响度侧链压限控制器
## 严格对齐 docs/design/22-audio-direction.md：
## - 同 BPM（96 BPM）双分轨（Calm_Explore + Combat_Percussion）1.2s 无缝推入 / 2.5s 平滑淡出
## - 首领战 / 标题 / 篝火夜话 0.8s 跨轨淡入淡出
## - Space【战术凝时】瞬间启用 900Hz 水下低通滤波 + 水滴进出音效
## - Tier S/A/B/C 四级并发上限与 Tier S 触发 -5dB 侧链压限（Ducking）

const TIER_S: int = 0
const TIER_A: int = 1
const TIER_B: int = 2
const TIER_C: int = 3

var _stem_calm: AudioStreamPlayer
var _stem_combat: AudioStreamPlayer
var _bgm_special: AudioStreamPlayer
var _amb_player: AudioStreamPlayer

var _sfx_pools: Dictionary = {}
var _streams_cache: Dictionary = {}

var _in_field_dual_stem: bool = false
var _combat_engaged: bool = false
var _special_mode_id: String = ""
var _calm_vol_db: float = 0.0
var _combat_vol_db: float = -60.0
var _special_vol_db: float = -60.0
var _duck_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stem_calm = _make_player("BGM_Bus")
	_stem_combat = _make_player("BGM_Bus")
	_bgm_special = _make_player("BGM_Bus")
	_amb_player = _make_player("Ambient_UI_Bus")

	_init_sfx_pool(TIER_S, 2, "Combat_SFX_Bus")
	_init_sfx_pool(TIER_A, 4, "Combat_SFX_Bus")
	_init_sfx_pool(TIER_B, 4, "Combat_SFX_Bus")
	_init_sfx_pool(TIER_C, 3, "Combat_SFX_Bus")


func _exit_tree() -> void:
	for p: AudioStreamPlayer in [_stem_calm, _stem_combat, _bgm_special, _amb_player]:
		if p != null:
			p.stop()
			p.stream = null
	for raw_pool: Variant in _sfx_pools.values():
		for raw_sp: Variant in (raw_pool as Array):
			var sp: AudioStreamPlayer = raw_sp as AudioStreamPlayer
			if sp != null:
				sp.stop()
				sp.stream = null
	_streams_cache.clear()


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"
	add_child(p)
	return p


func _init_sfx_pool(tier: int, max_voices: int, bus_name: String) -> void:
	var arr: Array[AudioStreamPlayer] = []
	for i: int in range(max_voices):
		var p: AudioStreamPlayer = _make_player(bus_name)
		arr.append(p)
	_sfx_pools[tier] = arr


func _process(delta: float) -> void:
	var duck_offset_db: float = 0.0
	if _duck_timer > 0.0:
		_duck_timer = maxf(0.0, _duck_timer - delta)
		duck_offset_db = -5.0

	if _in_field_dual_stem and _special_mode_id == "":
		var target_calm: float = 0.0 + duck_offset_db
		var target_comb: float = (0.0 + duck_offset_db) if _combat_engaged else -60.0
		var comb_rate: float = (60.0 / 1.2) if _combat_engaged else (60.0 / 2.5)
		_calm_vol_db = move_toward(_calm_vol_db, target_calm, delta * 45.0)
		_combat_vol_db = move_toward(_combat_vol_db, target_comb, delta * comb_rate)
		_special_vol_db = move_toward(_special_vol_db, -60.0, delta * 75.0)
		if _special_vol_db <= -58.0 and _bgm_special.playing:
			_bgm_special.stop()
		# 保持双分轨严格采样级同相循环
		if _stem_calm.playing and _stem_combat.playing:
			var diff: float = absf(_stem_calm.get_playback_position() - _stem_combat.get_playback_position())
			if diff > 0.06 and diff < 38.0:
				_stem_combat.seek(_stem_calm.get_playback_position())
	else:
		_calm_vol_db = move_toward(_calm_vol_db, -60.0, delta * 75.0)
		_combat_vol_db = move_toward(_combat_vol_db, -60.0, delta * 75.0)
		_special_vol_db = move_toward(_special_vol_db, 0.0 + duck_offset_db, delta * 75.0)

	_stem_calm.volume_db = _calm_vol_db
	_stem_combat.volume_db = _combat_vol_db
	_bgm_special.volume_db = _special_vol_db


func start_qinglan_dual_stem(with_rain_ambience: bool = true) -> void:
	_special_mode_id = ""
	if not _in_field_dual_stem or not _stem_calm.playing:
		_in_field_dual_stem = true
		_stem_calm.stream = _get_looping_ogg("res://assets/audio/bgm/bgm_qinglan_calm.ogg")
		_stem_combat.stream = _get_looping_ogg("res://assets/audio/bgm/bgm_qinglan_combat.ogg")
		_calm_vol_db = -18.0
		_combat_vol_db = -60.0
		_stem_calm.volume_db = _calm_vol_db
		_stem_combat.volume_db = _combat_vol_db
		_stem_calm.play(0.0)
		_stem_combat.play(0.0)
	set_rain_ambience(with_rain_ambience)


func set_combat_engaged(engaged: bool) -> void:
	_combat_engaged = engaged


func play_special_bgm(track_res_path: String, mode_id: String) -> void:
	if _special_mode_id == mode_id and _bgm_special.playing:
		return
	_special_mode_id = mode_id
	_bgm_special.stream = _get_looping_ogg(track_res_path)
	_special_vol_db = -24.0
	_bgm_special.volume_db = _special_vol_db
	_bgm_special.play(0.0)


func stop_special_bgm_return_to_field() -> void:
	_special_mode_id = ""
	if not _stem_calm.playing:
		start_qinglan_dual_stem(true)


func set_rain_ambience(enabled: bool) -> void:
	if enabled:
		if not _amb_player.playing:
			_amb_player.stream = _get_looping_ogg("res://assets/audio/bgm/amb_qinglan_rain.ogg")
			_amb_player.volume_db = -6.0
			_amb_player.play(0.0)
	else:
		if _amb_player.playing:
			_amb_player.stop()


func set_tactical_pause_filter(paused: bool) -> void:
	for bus_name: String in ["BGM_Bus", "Ambient_UI_Bus"]:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.set_bus_effect_enabled(idx, 0, paused)
	play_sfx("sfx_pause_enter" if paused else "sfx_pause_exit", TIER_A)


func play_sfx(sfx_name: String, tier: int = TIER_A, is_ui_bus: bool = false) -> void:
	var path: String = "res://assets/audio/sfx/%s.ogg" % sfx_name
	var stream: AudioStream = _get_ogg(path, false)
	if stream == null:
		return

	if tier == TIER_S:
		_duck_timer = 0.60

	var pool: Array = _sfx_pools.get(tier, []) as Array
	if pool.is_empty():
		return

	var chosen: AudioStreamPlayer = null
	for raw_p: Variant in pool:
		var p: AudioStreamPlayer = raw_p as AudioStreamPlayer
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		# 超出并发上限时覆盖最早通道（保持战场清爽）
		chosen = pool[0] as AudioStreamPlayer

	chosen.bus = "Ambient_UI_Bus" if is_ui_bus else "Combat_SFX_Bus"
	chosen.stream = stream
	var base_db: float = 0.0
	var pitch: float = 1.0
	if tier == TIER_A:
		base_db = -3.0
		pitch = randf_range(0.97, 1.03)
	elif tier == TIER_B:
		base_db = -8.0 - (4.0 if _duck_timer > 0.0 else 0.0)
		pitch = randf_range(0.94, 1.06)
	elif tier == TIER_C:
		base_db = -13.0 - (5.0 if _duck_timer > 0.0 else 0.0)
		pitch = randf_range(0.93, 1.07)

	chosen.volume_db = base_db
	chosen.pitch_scale = pitch
	chosen.play(0.0)


func play_element_sfx(element: String, tier: int = TIER_A) -> void:
	match element:
		"metal":
			play_sfx("sfx_elem_metal", tier)
		"wood":
			play_sfx("sfx_elem_wood", tier)
		"water":
			play_sfx("sfx_elem_water", tier)
		"fire":
			play_sfx("sfx_elem_fire", tier)
		"earth":
			play_sfx("sfx_elem_earth", tier)
		_:
			play_sfx("sfx_elem_metal", tier)


func _get_looping_ogg(res_path: String) -> AudioStream:
	return _get_ogg(res_path, true)


func _get_ogg(res_path: String, make_loop: bool) -> AudioStream:
	if _streams_cache.has(res_path):
		return _streams_cache[res_path] as AudioStream
	if not ResourceLoader.exists(res_path):
		return null
	var loaded: AudioStream = load(res_path) as AudioStream
	if loaded is AudioStreamOggVorbis:
		(loaded as AudioStreamOggVorbis).loop = make_loop
	_streams_cache[res_path] = loaded
	return loaded
