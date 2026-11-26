extends Node
## 第二层状态服务单例（5/5）：版本化 JSON 信封原子存档与独立设置持久化（SaveManager）
## 严格对齐 docs/design/30-tech-architecture-godot.md 第 3.2 节 9 条安全铁律与 AGENTS.md：
## - SHA-256 校验版本化信封（magic: CHENYUAN_XIANXIA_SAVE, schema_version: 1）
## - .tmp 原子落盘 -> 校验 -> 旧档轮转 .bak -> 原子重命名
## - 损坏零覆盖保护：解析或校验失败立即触发 P0 警报，完整保留原损坏文件并提供 .bak 恢复！
## - 20 手动槽 + 3 滚动自动槽；非正式模式（sandbox_mode）物理禁用写入 user://saves/。

signal settings_changed()
signal save_completed(slot_id: String)
signal load_completed(slot_id: String)

const SAVE_MAGIC: String = "CHENYUAN_XIANXIA_SAVE"
const CURRENT_SCHEMA_VERSION: int = 1
const GAME_BUILD: String = "0.1.0-slice"
const SAVE_DIR: String = "user://saves"
const SETTINGS_PATH: String = "user://settings.cfg"
const MANUAL_SLOT_COUNT: int = 20
const AUTO_SLOT_COUNT: int = 3

var in_puzzle_lock: bool = false
var _auto_slot_cursor: int = 1

## 独立设置状态（4 总线音频 + 后台静音 + 无障碍双编码/减震）
var master_volume: float = 0.85
var bgm_volume: float = 0.80
var combat_sfx_volume: float = 0.85
var ambient_ui_volume: float = 0.85
var master_muted: bool = false
var mute_on_unfocus: bool = true
var screen_shake_pct: float = 0.40
var reduced_motion: bool = false
var colorblind_dual_code: bool = true

var _window_focused: bool = true


func _ready() -> void:
	_ensure_save_dir()
	load_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		_apply_audio_buses()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		_apply_audio_buses()


func can_save_now() -> Dictionary:
	if CampaignState.sandbox_mode:
		return {"ok": false, "reason_key": "MSG_SAVE_SANDBOX_BLOCKED"}
	if NotifyHub.combat_active:
		return {"ok": false, "reason_key": "MSG_SAVE_COMBAT_BLOCKED"}
	if in_puzzle_lock:
		return {"ok": false, "reason_key": "MSG_SAVE_PUZZLE_BLOCKED"}
	return {"ok": true, "reason_key": ""}


func save_manual_slot(slot_index: int) -> Dictionary:
	var clamped: int = clampi(slot_index, 1, MANUAL_SLOT_COUNT)
	return _write_slot("slot_%02d" % clamped)


func save_rolling_auto() -> Dictionary:
	var check: Dictionary = can_save_now()
	if not bool(check.get("ok", false)):
		return check
	var slot_id: String = "auto_%02d" % _auto_slot_cursor
	_auto_slot_cursor = (_auto_slot_cursor % AUTO_SLOT_COUNT) + 1
	return _write_slot(slot_id, true)


func _write_slot(slot_id: String, silent_slip: bool = false) -> Dictionary:
	var check: Dictionary = can_save_now()
	if not bool(check.get("ok", false)):
		return check

	_ensure_save_dir()
	var payload: Dictionary = CampaignState.serialize_payload()
	var canonical_payload: String = _canonical_json(payload)
	var sha: String = _sha256_text(canonical_payload)

	var gu_state: Dictionary = CampaignState.party_members.get("gu_changqing", {}) as Dictionary
	var realm_def: Dictionary = DataDB.get_realm(str(gu_state.get("realm_id", "mortal")))
	var realm_label: String = DataDB.loc(str(realm_def.get("name_key", "REALM_MORTAL")))
	var zone_label: String = tr("ZONE_NAME_" + CampaignState.current_zone_id.to_upper())

	var envelope: Dictionary = {
		"magic": SAVE_MAGIC,
		"schema_version": CURRENT_SCHEMA_VERSION,
		"game_build": GAME_BUILD,
		"saved_at_utc": Time.get_datetime_string_from_system(true, true) + "Z",
		"chapter_id": CampaignState.chapter_id,
		"summary": {
			"realm": realm_label,
			"location": zone_label,
			"playtime_sec": int(round(CampaignState.playtime_sec)),
			"spirit_stones": CampaignState.spirit_stones,
		},
		"checksum_sha256": sha,
		"payload": payload,
	}

	var base_path: String = "%s/%s.json" % [SAVE_DIR, slot_id]
	var tmp_path: String = base_path + ".tmp"
	var bak_path: String = base_path + ".bak"
	var json_text: String = JSON.stringify(envelope, "  ")

	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		NotifyHub.push_crisis(tr("ERR_SAVE_WRITE_TITLE"), tr("ERR_SAVE_WRITE_BODY"), slot_id, false)
		return {"ok": false, "reason_key": "ERR_SAVE_WRITE_BODY"}
	f.store_string(json_text)
	f.flush()
	f.close()

	# 读回校验 .tmp 完整性后再轮转 .bak 与正式文件
	var verify_res: Dictionary = _read_and_validate_file(tmp_path)
	if not bool(verify_res.get("ok", false)):
		NotifyHub.push_crisis(tr("ERR_SAVE_WRITE_TITLE"), tr("ERR_SAVE_VERIFY_FAIL"), slot_id, false)
		return {"ok": false, "reason_key": "ERR_SAVE_VERIFY_FAIL"}

	var abs_base: String = ProjectSettings.globalize_path(base_path)
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_bak: String = ProjectSettings.globalize_path(bak_path)

	if FileAccess.file_exists(base_path):
		# 仅在旧主档本身未损坏时才覆盖 .bak，绝不用坏档污染健康备份
		var old_check: Dictionary = _read_and_validate_file(base_path)
		if bool(old_check.get("ok", false)):
			if FileAccess.file_exists(bak_path):
				DirAccess.remove_absolute(abs_bak)
			DirAccess.copy_absolute(abs_base, abs_bak)

	if FileAccess.file_exists(base_path):
		DirAccess.remove_absolute(abs_base)
	var rename_err: Error = DirAccess.rename_absolute(abs_tmp, abs_base)
	if rename_err != OK:
		NotifyHub.push_crisis(tr("ERR_SAVE_WRITE_TITLE"), tr("ERR_SAVE_RENAME_FAIL"), slot_id, FileAccess.file_exists(bak_path))
		return {"ok": false, "reason_key": "ERR_SAVE_RENAME_FAIL"}

	if not silent_slip:
		NotifyHub.push_explore_slip(tr("NOTIFY_SAVE_OK"), "%s · %s" % [zone_label, realm_label], "save")
	save_completed.emit(slot_id)
	return {"ok": true, "slot_id": slot_id}


func load_slot(slot_id: String, use_backup: bool = false) -> Dictionary:
	var target_path: String = "%s/%s.json%s" % [SAVE_DIR, slot_id, ".bak" if use_backup else ""]
	var bak_path: String = "%s/%s.json.bak" % [SAVE_DIR, slot_id]
	if not FileAccess.file_exists(target_path):
		return {"ok": false, "error": "missing"}

	var res: Dictionary = _read_and_validate_file(target_path)
	if not bool(res.get("ok", false)):
		# 损坏零覆盖铁律：绝不删除或覆盖损坏原文件！立即弹出 P0 警报提供 .bak 恢复选项
		var has_valid_bak: bool = false
		if not use_backup and FileAccess.file_exists(bak_path):
			var bak_check: Dictionary = _read_and_validate_file(bak_path)
			has_valid_bak = bool(bak_check.get("ok", false))
		NotifyHub.push_crisis(
			tr("ERR_SAVE_CORRUPT_TITLE"),
			"%s\n(%s)" % [tr("ERR_SAVE_CORRUPT_BODY"), ProjectSettings.globalize_path(target_path)],
			slot_id,
			has_valid_bak
		)
		return {"ok": false, "error": "corrupted", "has_backup": has_valid_bak}

	var envelope: Dictionary = res.get("envelope", {}) as Dictionary
	var migrated: Dictionary = _migrate_envelope(envelope)
	var payload: Dictionary = migrated.get("payload", {}) as Dictionary
	CampaignState.deserialize_payload(payload)
	load_completed.emit(slot_id)
	return {"ok": true, "slot_id": slot_id}


func list_all_slots() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for a: int in range(1, AUTO_SLOT_COUNT + 1):
		entries.append(inspect_slot("auto_%02d" % a, true))
	for m: int in range(1, MANUAL_SLOT_COUNT + 1):
		entries.append(inspect_slot("slot_%02d" % m, false))
	return entries


func has_any_valid_save() -> bool:
	for entry: Dictionary in list_all_slots():
		if str(entry.get("status", "empty")) == "valid":
			return true
	return false


func load_latest_valid_save() -> Dictionary:
	var best_slot: String = ""
	var best_utc: String = ""
	for entry: Dictionary in list_all_slots():
		if str(entry.get("status", "empty")) == "valid":
			var utc: String = str(entry.get("saved_at_utc", ""))
			if utc >= best_utc:
				best_utc = utc
				best_slot = str(entry.get("slot_id", ""))
	if best_slot == "":
		return {"ok": false, "error": "none"}
	return load_slot(best_slot, false)


func inspect_slot(slot_id: String, is_auto: bool = false) -> Dictionary:
	var path: String = "%s/%s.json" % [SAVE_DIR, slot_id]
	var bak_path: String = path + ".bak"
	if not FileAccess.file_exists(path):
		return {
			"slot_id": slot_id,
			"is_auto": is_auto,
			"status": "empty",
			"has_backup": FileAccess.file_exists(bak_path),
		}
	var check: Dictionary = _read_and_validate_file(path)
	if not bool(check.get("ok", false)):
		return {
			"slot_id": slot_id,
			"is_auto": is_auto,
			"status": "corrupted",
			"has_backup": FileAccess.file_exists(bak_path),
		}
	var env: Dictionary = check.get("envelope", {}) as Dictionary
	var sum_d: Dictionary = env.get("summary", {}) as Dictionary
	return {
		"slot_id": slot_id,
		"is_auto": is_auto,
		"status": "valid",
		"saved_at_utc": str(env.get("saved_at_utc", "")),
		"realm": str(sum_d.get("realm", "")),
		"location": str(sum_d.get("location", "")),
		"playtime_sec": int(sum_d.get("playtime_sec", 0)),
		"spirit_stones": int(sum_d.get("spirit_stones", 0)),
		"has_backup": FileAccess.file_exists(bak_path),
	}


func _read_and_validate_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "not_found"}
	var raw: String = FileAccess.get_file_as_string(path)
	if raw.strip_edges() == "":
		return {"ok": false, "reason": "empty"}
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json"}
	var env: Dictionary = parsed as Dictionary
	if str(env.get("magic", "")) != SAVE_MAGIC:
		return {"ok": false, "reason": "bad_magic"}
	var schema_ver: int = int(env.get("schema_version", 0))
	if schema_ver < 1 or schema_ver > CURRENT_SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_schema"}
	if not (env.get("payload", null) is Dictionary):
		return {"ok": false, "reason": "missing_payload"}
	var payload: Dictionary = env.get("payload", {}) as Dictionary
	var expected_sha: String = str(env.get("checksum_sha256", ""))
	var actual_sha: String = _sha256_text(_canonical_json(payload))
	if expected_sha == "" or expected_sha != actual_sha:
		return {"ok": false, "reason": "checksum_mismatch"}
	return {"ok": true, "envelope": env}


func _migrate_envelope(env: Dictionary) -> Dictionary:
	var ver: int = int(env.get("schema_version", 1))
	var out: Dictionary = env.duplicate(true)
	# 预留纯单向版本迁移链 migrate_v1_to_v2(dict)
	if ver == 1:
		return out
	return out


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "combat_sfx_volume", combat_sfx_volume)
	cfg.set_value("audio", "ambient_ui_volume", ambient_ui_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "mute_on_unfocus", mute_on_unfocus)

	cfg.set_value("comfort", "screen_shake_pct", screen_shake_pct)
	cfg.set_value("comfort", "reduced_motion", reduced_motion)
	cfg.set_value("comfort", "colorblind_dual_code", colorblind_dual_code)

	var kb: Dictionary = InputRouter.export_keybinds_dict()
	for k_var: Variant in kb.keys():
		var k_str: String = str(k_var)
		cfg.set_value("keybinds", k_str, int(kb[k_str]))

	cfg.save(SETTINGS_PATH)
	_apply_audio_buses()
	settings_changed.emit()


func load_settings() -> void:
	_ensure_audio_buses()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.85)), 0.0, 1.0)
		bgm_volume = clampf(float(cfg.get_value("audio", "bgm_volume", 0.80)), 0.0, 1.0)
		combat_sfx_volume = clampf(float(cfg.get_value("audio", "combat_sfx_volume", 0.85)), 0.0, 1.0)
		ambient_ui_volume = clampf(float(cfg.get_value("audio", "ambient_ui_volume", 0.85)), 0.0, 1.0)
		master_muted = bool(cfg.get_value("audio", "master_muted", false))
		mute_on_unfocus = bool(cfg.get_value("audio", "mute_on_unfocus", true))

		screen_shake_pct = clampf(float(cfg.get_value("comfort", "screen_shake_pct", 0.40)), 0.0, 1.0)
		reduced_motion = bool(cfg.get_value("comfort", "reduced_motion", false))
		colorblind_dual_code = bool(cfg.get_value("comfort", "colorblind_dual_code", true))

		if cfg.has_section("keybinds"):
			var loaded_kb: Dictionary = {}
			for key_name: String in cfg.get_section_keys("keybinds"):
				loaded_kb[key_name] = int(cfg.get_value("keybinds", key_name, 0))
			InputRouter.import_keybinds_dict(loaded_kb)
	_apply_audio_buses()


func _ensure_audio_buses() -> void:
	var required_buses: Array[String] = ["BGM_Bus", "Combat_SFX_Bus", "Ambient_UI_Bus"]
	for bus_name: String in required_buses:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# 在 BGM_Bus 与 Ambient_UI_Bus 预挂低通滤波器（默认禁用，按下 Space 战术凝时瞬间切换 900Hz）
	for lpf_bus: String in ["BGM_Bus", "Ambient_UI_Bus"]:
		var bidx: int = AudioServer.get_bus_index(lpf_bus)
		if bidx >= 0 and AudioServer.get_bus_effect_count(bidx) == 0:
			var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
			lpf.cutoff_hz = 900.0
			lpf.resonance = 0.45
			AudioServer.add_bus_effect(bidx, lpf, 0)
			AudioServer.set_bus_effect_enabled(bidx, 0, false)


func _apply_audio_buses() -> void:
	_ensure_audio_buses()
	var effective_mute: bool = master_muted or (mute_on_unfocus and not _window_focused)
	AudioServer.set_bus_mute(0, effective_mute)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, master_volume)))

	var bgm_idx: int = AudioServer.get_bus_index("BGM_Bus")
	if bgm_idx >= 0:
		AudioServer.set_bus_volume_db(bgm_idx, linear_to_db(maxf(0.0001, bgm_volume)))
		AudioServer.set_bus_mute(bgm_idx, bgm_volume <= 0.001)

	var sfx_idx: int = AudioServer.get_bus_index("Combat_SFX_Bus")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(0.0001, combat_sfx_volume)))
		AudioServer.set_bus_mute(sfx_idx, combat_sfx_volume <= 0.001)

	var amb_idx: int = AudioServer.get_bus_index("Ambient_UI_Bus")
	if amb_idx >= 0:
		AudioServer.set_bus_volume_db(amb_idx, linear_to_db(maxf(0.0001, ambient_ui_volume)))
		AudioServer.set_bus_mute(amb_idx, ambient_ui_volume <= 0.001)


func _ensure_save_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _canonical_json(val: Variant) -> String:
	if val is Dictionary:
		var d: Dictionary = val as Dictionary
		var keys: Array = d.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var parts: PackedStringArray = PackedStringArray()
		for k_var: Variant in keys:
			var k: String = str(k_var)
			parts.append("%s:%s" % [JSON.stringify(k), _canonical_json(d[k_var])])
		return "{%s}" % ",".join(parts)
	elif val is Array:
		var arr: Array = val as Array
		var parts2: PackedStringArray = PackedStringArray()
		for item: Variant in arr:
			parts2.append(_canonical_json(item))
		return "[%s]" % ",".join(parts2)
	elif val is float:
		return "%.4f" % float(val)
	elif val is int:
		return "%d" % int(val)
	return JSON.stringify(val)


func _sha256_text(text: String) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
