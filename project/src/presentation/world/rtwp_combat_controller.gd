class_name RtwpCombatController
extends Node
## 第三层无缝大地图 RTwP 战斗运行时调度器
## 将世界场景中的 BattleActor 实体与第一层纯规则（StatLedger / FormationRules / RtwpSimStep）桥接，
## 完整实现：combat_delta 与 Space【战术凝时】解耦、明雷视野拉怪与敛息潜行、锁定自动平砍（走A不重置）、
## 1.5s GCD 与 Off-GCD 秒断、Mouseover 悬停施法、五行破罡与相生母印引爆、双阶段雾隐狼王及败北复盘溯源。

signal encounter_cleared(group_id: String, was_boss: bool)
signal party_wiped(recap_data: Dictionary)
signal boss_combat_changed(boss_actor: BattleActor)
signal combat_hud_dirty()

var audio_director: AudioDirector = null
var ground_vfx: CombatVfxOverlay = null
var sky_vfx: CombatVfxOverlay = null
var ysort_root: Node2D = null
var world_camera: Camera2D = null

## 战场实体注册表
var party_actors: Dictionary = {} # char_id -> BattleActor
var pet_actor: BattleActor = null
var enemy_actors: Array[BattleActor] = []
var obstacle_circles: Array[Dictionary] = [] # [{pos: Vector2, radius: float}]

## 战斗全局状态（严格绑定 combat_delta）
var in_combat: bool = false
var tactical_paused: bool = false
var combat_clock_sec: float = 0.0
var out_of_combat_sec: float = 10.0

var team_attunement: float = 0.0
var preemptive_buff_timer: float = 0.0
var stealth_timer: float = 0.0
var pill_cooldown_timer: float = 0.0
var pill_cooldown_total: float = RtwpSimStep.PILL_TOXICITY_COOLDOWN_SEC
var formation_switch_cd: float = 0.0
var formation_switch_cd_total: float = FormationRules.FORMATION_SWITCH_COOLDOWN_SEC
var party_haste_buff_timer: float = 0.0
var party_haste_buff_val: float = 0.0
var loyal_guard_timer: float = 0.0
var loyal_guard_share: float = 0.50

var _hitstop_timer: float = 0.0
var _minor_hitstop_cd: float = 0.0
var _shake_timer: float = 0.0
var _shake_duration: float = 0.18
var _shake_amplitude: float = 0.0
var _shake_impulse_dir: Vector2 = Vector2.ZERO
var _shake_phase: float = 0.0

## 交互选中与悬停指向
var locked_enemy_id: String = ""
var hovered_ally_id: String = ""
var hovered_world_actor_id: String = ""
var box_selected_ids: Array[String] = []
var auto_attack_enabled: bool = false

## 每个单位的详细战斗状态表 unit_id -> Dictionary
var unit_states: Dictionary = {}
var death_ring_buffer: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	SaveManager.settings_changed.connect(_on_comfort_settings_changed)
	CampaignState.party_updated.connect(_on_campaign_party_updated)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func _on_campaign_party_updated() -> void:
	if ysort_root != null and not party_actors.is_empty():
		sync_party_roster_in_place()


func _process(delta: float) -> void:
	if InputRouter.current_mode != InputRouter.MODE_WORLD_COMBAT:
		if _shake_timer > 0.0 or (world_camera != null and world_camera.offset != Vector2.ZERO):
			_step_camera_shake(delta)


func _on_comfort_settings_changed() -> void:
	if SaveManager.reduced_motion:
		for pa_var: Variant in party_actors.values():
			var pa: BattleActor = pa_var as BattleActor
			if is_instance_valid(pa):
				pa.clear_hit_flash()
		if pet_actor != null and is_instance_valid(pet_actor):
			pet_actor.clear_hit_flash()
		for ea: BattleActor in enemy_actors:
			if is_instance_valid(ea):
				ea.clear_hit_flash()
	if SaveManager.reduced_motion or SaveManager.screen_shake_pct <= 0.001:
		_hitstop_timer = 0.0
		_shake_timer = 0.0
		_shake_amplitude = 0.0
		if world_camera != null:
			world_camera.offset = Vector2.ZERO


func trigger_hitstop(duration_sec: float, is_major: bool = true) -> void:
	if duration_sec <= 0.0 or SaveManager.reduced_motion or SaveManager.screen_shake_pct <= 0.001:
		return
	if not is_major and _minor_hitstop_cd > 0.0:
		return
	var comfort_scale: float = lerpf(0.65, 1.0, clampf(SaveManager.screen_shake_pct / 0.40, 0.0, 1.0))
	var eff_dur: float = duration_sec * comfort_scale
	_hitstop_timer = maxf(_hitstop_timer, eff_dur)
	if not is_major:
		_minor_hitstop_cd = 0.16


func trigger_camera_shake(amplitude_px: float, duration_sec: float = 0.18, impulse_dir: Vector2 = Vector2.ZERO) -> void:
	if SaveManager.reduced_motion or SaveManager.screen_shake_pct <= 0.001 or world_camera == null:
		_shake_timer = 0.0
		_shake_amplitude = 0.0
		if world_camera != null:
			world_camera.offset = Vector2.ZERO
		return
	var eff_amp: float = clampf(amplitude_px, 0.0, 16.0) * clampf(SaveManager.screen_shake_pct, 0.0, 1.0)
	if eff_amp <= 0.05:
		return
	var cur_amp: float = 0.0
	if _shake_timer > 0.0 and _shake_duration > 0.001:
		var r: float = clampf(_shake_timer / _shake_duration, 0.0, 1.0)
		cur_amp = _shake_amplitude * r * r
	if eff_amp >= cur_amp or _shake_timer <= 0.0:
		_shake_amplitude = eff_amp
		_shake_duration = maxf(0.06, duration_sec)
		_shake_timer = _shake_duration
		_shake_impulse_dir = impulse_dir.normalized() if impulse_dir.length_squared() > 0.001 else Vector2.ZERO


func _step_camera_shake(ui_delta: float) -> void:
	if world_camera == null:
		return
	if SaveManager.reduced_motion or SaveManager.screen_shake_pct <= 0.001:
		_shake_timer = 0.0
		_shake_amplitude = 0.0
		world_camera.offset = Vector2.ZERO
		return
	if _shake_timer <= 0.0:
		if world_camera.offset != Vector2.ZERO:
			world_camera.offset = world_camera.offset.move_toward(Vector2.ZERO, ui_delta * 60.0)
		return
	_shake_timer = maxf(0.0, _shake_timer - ui_delta)
	_shake_phase += ui_delta * 46.0
	if _shake_timer <= 0.0:
		world_camera.offset = Vector2.ZERO
		return
	var ratio: float = clampf(_shake_timer / maxf(0.001, _shake_duration), 0.0, 1.0)
	var env: float = ratio * ratio
	var osc: Vector2 = Vector2(sin(_shake_phase * 1.13), cos(_shake_phase * 1.47 + 0.6))
	var kick: Vector2 = _shake_impulse_dir * sin(ratio * PI) * 0.55
	world_camera.offset = (osc * 0.75 + kick) * (_shake_amplitude * env)


func reset_for_zone(p_ysort: Node2D, p_ground_vfx: CombatVfxOverlay, p_sky_vfx: CombatVfxOverlay, p_cam: Camera2D, p_audio: AudioDirector) -> void:
	ysort_root = p_ysort
	ground_vfx = p_ground_vfx
	sky_vfx = p_sky_vfx
	world_camera = p_cam
	audio_director = p_audio

	if ground_vfx != null:
		ground_vfx.clear_all_fx()
	if sky_vfx != null:
		sky_vfx.clear_all_fx()

	_hitstop_timer = 0.0
	_minor_hitstop_cd = 0.0
	_shake_timer = 0.0
	_shake_amplitude = 0.0
	if world_camera != null:
		world_camera.offset = Vector2.ZERO

	in_combat = false
	tactical_paused = false
	InputRouter.combat_engaged = false
	NotifyHub.set_combat_active(false)
	if audio_director != null:
		audio_director.set_tactical_pause_filter(false)
		audio_director.set_combat_engaged(false)

	party_actors.clear()
	pet_actor = null
	enemy_actors.clear()
	obstacle_circles.clear()
	unit_states.clear()
	death_ring_buffer.clear()
	locked_enemy_id = ""
	box_selected_ids.clear()
	auto_attack_enabled = false
	combat_clock_sec = 0.0
	out_of_combat_sec = 10.0


func spawn_party_at(origin_pos: Vector2) -> void:
	if ysort_root == null:
		return
	for old_pa_var: Variant in party_actors.values():
		var old_pa: BattleActor = old_pa_var as BattleActor
		if is_instance_valid(old_pa):
			old_pa.queue_free()
	party_actors.clear()
	CampaignState.recalculate_all_party_stats(false)
	var active_ids: Array[String] = CampaignState.get_active_party_ids()
	var offsets: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(48.0, -24.0),
		Vector2(-52.0, 26.0),
		Vector2(-24.0, -42.0),
	]
	for idx: int in range(active_ids.size()):
		var cid: String = active_ids[idx]
		var cdef: Dictionary = DataDB.get_character(cid)
		var mstate: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var sheet: Dictionary = mstate.get("sheet", {}) as Dictionary
		var actor: BattleActor = BattleActor.new()
		actor.position = origin_pos + offsets[mini(idx, offsets.size() - 1)]
		actor.setup_actor(cid, "party", DataDB.loc(str(cdef.get("name_key", cid))), str(cdef.get("sprite_id", cid)), 1.0)
		actor.is_controlled = (idx == 0)
		ysort_root.add_child(actor)
		party_actors[cid] = actor
		_init_party_unit_state(cid, actor, mstate, sheet)

	CampaignState.controlled_slot = CampaignState.get_member_formation_slot(active_ids[0]) if not active_ids.is_empty() else 1
	sync_pet_actor(origin_pos + Vector2(36.0, 38.0))


func sync_party_roster_in_place() -> void:
	if ysort_root == null:
		return
	var leader_pos: Vector2 = get_controlled_actor_pos()
	CampaignState.recalculate_all_party_stats(false)
	var active_ids: Array[String] = CampaignState.get_active_party_ids()
	for idx: int in range(active_ids.size()):
		var cid: String = active_ids[idx]
		var mstate: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var sheet: Dictionary = mstate.get("sheet", {}) as Dictionary
		if not party_actors.has(cid):
			var cdef: Dictionary = DataDB.get_character(cid)
			var actor: BattleActor = BattleActor.new()
			actor.position = leader_pos + Vector2(-42.0 * float(idx), 28.0 * float(idx))
			actor.setup_actor(cid, "party", DataDB.loc(str(cdef.get("name_key", cid))), str(cdef.get("sprite_id", cid)), 1.0)
			ysort_root.add_child(actor)
			party_actors[cid] = actor
			_init_party_unit_state(cid, actor, mstate, sheet)
		else:
			var existing: BattleActor = party_actors[cid] as BattleActor
			_refresh_party_unit_sheet(cid, existing, mstate, sheet, true)

	_ensure_valid_controlled_slot()
	var ctrl_id: String = get_controlled_char_id()
	for cid2_var: Variant in party_actors.keys():
		var cid2: String = str(cid2_var)
		var pa: BattleActor = party_actors[cid2] as BattleActor
		pa.is_controlled = (cid2 == ctrl_id)

	sync_pet_actor(leader_pos + Vector2(38.0, 34.0))
	combat_hud_dirty.emit()


func sync_pet_actor(spawn_pos: Vector2) -> void:
	if ysort_root == null:
		return
	var pid: String = CampaignState.active_pet_id
	if pid == "":
		if pet_actor != null:
			unit_states.erase(pet_actor.actor_id)
			pet_actor.queue_free()
			pet_actor = null
		return

	var pdef: Dictionary = DataDB.get_pet(pid)
	if pdef.is_empty():
		return
	var uid: String = "pet_" + pid
	var same_pet_exists: bool = (pet_actor != null and pet_actor.actor_id == uid)
	var prev_u: Dictionary = (unit_states.get(uid, {}) as Dictionary) if same_pet_exists else {}
	if pet_actor != null and pet_actor.actor_id != uid:
		unit_states.erase(pet_actor.actor_id)
		pet_actor.queue_free()
		pet_actor = null

	var gu_m: Dictionary = CampaignState.party_members.get("gu_changqing", {}) as Dictionary
	var rdef: Dictionary = DataDB.get_realm(str(gu_m.get("realm_id", "mortal")))
	var realm_scale: float = 1.0 + float(int(rdef.get("sub_realm_total_index", 0))) * 0.28
	var max_hp: int = int(round(float(pdef.get("base_hp", 160)) * realm_scale))
	var pwr: float = float(pdef.get("base_power", 20.0)) * realm_scale

	if pet_actor == null:
		pet_actor = BattleActor.new()
		pet_actor.position = spawn_pos
		pet_actor.setup_actor(uid, "pet", DataDB.loc(str(pdef.get("name_key", pid))), str(pdef.get("sprite_id", pid)), 1.0)
		ysort_root.add_child(pet_actor)

	pet_actor.max_hp = max_hp
	if same_pet_exists and in_combat:
		pet_actor.hp = clampi(pet_actor.hp, 0, max_hp)
		pet_actor.alive = pet_actor.hp > 0
	else:
		pet_actor.hp = maxi(1, int(round(float(max_hp) * clampf(CampaignState.pet_hp_ratio, 0.2, 1.0))))
		pet_actor.alive = true
	unit_states[uid] = {
		"id": uid,
		"pet_def_id": pid,
		"faction": "pet",
		"actor": pet_actor,
		"max_hp": max_hp,
		"hp": pet_actor.hp,
		"power": pwr,
		"attack_interval": float(pdef.get("attack_interval", 1.7)),
		"attack_timer": float(prev_u.get("attack_timer", 0.4)),
		"attack_range_px": float(pdef.get("attack_range_px", 240.0)),
		"move_speed_px": float(pdef.get("move_speed_px", 220.0)),
		"damage_taken_mult": 0.80,
		"threat_mult": 1.35 if pid == "pet_spirit_turtle" else 0.75,
		"is_tank_role": pid == "pet_spirit_turtle",
		"cooldowns": prev_u.get("cooldowns", {}) as Dictionary,
		"cooldown_totals": prev_u.get("cooldown_totals", {}) as Dictionary,
		"shield": float(prev_u.get("shield", 0.0)),
	}


func spawn_enemy_unit(enemy_def_id: String, pos: Vector2, group_id: String, patrol_pts: Array[Vector2] = []) -> BattleActor:
	if ysort_root == null:
		return null
	var edef: Dictionary = DataDB.get_enemy(enemy_def_id)
	if edef.is_empty():
		return null
	var uid: String = "%s_%d" % [enemy_def_id, enemy_actors.size() + 1]
	var scale_m: float = float(edef.get("scale_mult", 1.0))
	var actor: BattleActor = BattleActor.new()
	actor.position = pos
	actor.setup_actor(uid, "enemy", DataDB.loc(str(edef.get("name_key", enemy_def_id))), str(edef.get("sprite_id", enemy_def_id)), scale_m)
	actor.is_boss = bool(edef.get("is_boss", false))
	actor.is_elite = bool(edef.get("is_elite", false))
	actor.patrol_points = patrol_pts.duplicate()
	actor.home_pos = pos

	var hp_mult: float = CampaignState.get_difficulty_enemy_hp_mult()
	var dmg_mult: float = CampaignState.get_difficulty_enemy_damage_mult()
	var max_hp: int = maxi(30, int(round(float(edef.get("max_hp", 180)) * hp_mult)))
	var w_max: float = float(edef.get("ward_max", 0.0))
	actor.max_hp = max_hp
	actor.hp = max_hp
	actor.ward_max = w_max
	actor.ward_current = w_max
	actor.ward_element = str(edef.get("ward_element", "none"))

	ysort_root.add_child(actor)
	enemy_actors.append(actor)

	unit_states[uid] = {
		"id": uid,
		"enemy_def_id": enemy_def_id,
		"edef": edef,
		"group_id": group_id,
		"faction": "enemy",
		"actor": actor,
		"engaged": false,
		"phase": 1,
		"summoned_p1": false,
		"max_hp": max_hp,
		"hp": max_hp,
		"power": float(edef.get("power", 16.0)) * dmg_mult,
		"damage_taken_mult": clampf(100.0 / (100.0 + float(edef.get("defense", 14.0)) / 32.0), 0.45, 1.0),
		"ward_max": w_max,
		"ward_current": w_max,
		"ward_element": actor.ward_element,
		"stagger_timer": 0.0,
		"stun_timer": 0.0,
		"lockout_timer": 0.0,
		"mother_seal_element": "",
		"mother_seal_timer": 0.0,
		"slow_timer": 0.0,
		"slow_pct": 0.0,
		"atk_slow_timer": 0.0,
		"dot_timer": 0.0,
		"dot_dps": 0.0,
		"dot_leech_pct": 0.0,
		"shield": 0.0,
		"attack_interval": float(edef.get("attack_interval", 1.85)),
		"attack_timer": 0.65,
		"attack_range_px": float(edef.get("attack_range_px", 130.0)),
		"move_speed_px": float(edef.get("move_speed_px", 195.0)),
		"aggro_radius_px": float(edef.get("aggro_radius_px", 250.0)),
		"leash_radius_px": float(edef.get("leash_radius_px", 580.0)),
		"vision_type": str(edef.get("vision_type", "circle")),
		"formation_id": str(edef.get("formation_id", "scatter")),
		"threat_table": {},
		"target_id": "",
		"taunt_target_id": "",
		"taunt_timer": 0.0,
		"cooldowns": {},
		"cooldown_totals": {},
		"casting": false,
		"cast_skill_id": "",
		"cast_progress": 0.0,
		"cast_duration": 0.0,
		"cast_interruptible": true,
		"cast_origin": Vector2.ZERO,
		"cast_dir": Vector2.RIGHT,
	}
	return actor


func _init_party_unit_state(cid: String, actor: BattleActor, mstate: Dictionary, sheet: Dictionary) -> void:
	unit_states[cid] = {
		"id": cid,
		"faction": "party",
		"actor": actor,
		"gcd_timer": 0.0,
		"gcd_total": StatLedger.BASE_GCD_SEC,
		"attack_timer": 0.25,
		"aa_flip": false,
		"cooldowns": {},
		"cooldown_totals": {},
		"casting": false,
		"cast_skill_id": "",
		"cast_target_id": "",
		"cast_progress": 0.0,
		"cast_duration": 0.0,
		"queued_slot": "",
		"queued_target_id": "",
		"shield": 0.0,
		"dr_buff_timer": 0.0,
		"dr_buff_pct": 0.0,
		"ward_buff_timer": 0.0,
		"hot_timer": 0.0,
		"hot_hps": 0.0,
		"miasma_stacks": 0,
		"miasma_tick_timer": 0.0,
		"miasma_immune_timer": 0.0,
	}
	_refresh_party_unit_sheet(cid, actor, mstate, sheet)


func _refresh_party_unit_sheet(cid: String, actor: BattleActor, mstate: Dictionary, sheet: Dictionary, is_live_refresh: bool = false) -> void:
	if not unit_states.has(cid):
		return
	var u: Dictionary = unit_states[cid] as Dictionary
	var slot_idx: int = CampaignState.get_member_formation_slot(cid)
	var fdef: Dictionary = DataDB.get_formation(CampaignState.active_formation_id)
	var smod: Dictionary = FormationRules.get_slot_modifiers(fdef, slot_idx)

	u["sheet"] = sheet
	u["slot_index"] = slot_idx
	u["is_tank_role"] = (slot_idx == 2) or (str(mstate.get("active_spec", "spec_a")) == "spec_b" and cid == "gu_changqing")
	actor.role_badge = str(smod.get("role_title", "青龙位"))
	actor.max_hp = int(sheet.get("max_hp", 120))
	actor.max_mp = int(sheet.get("max_mp", 60))
	if is_live_refresh and in_combat:
		actor.hp = clampi(actor.hp, 0, actor.max_hp)
		actor.mp = clampi(actor.mp, 0, actor.max_mp)
	else:
		actor.hp = clampi(int(mstate.get("hp", actor.max_hp)), 0, actor.max_hp)
		actor.mp = clampi(int(mstate.get("mp", actor.max_mp)), 0, actor.max_mp)
	actor.alive = actor.hp > 0


func _ensure_valid_controlled_slot() -> void:
	var packed: Array[int] = get_occupied_formation_slots()
	if packed.is_empty():
		return
	var idx: int = clampi(CampaignState.controlled_slot - 1, 0, 3)
	var cur_cid: String = CampaignState.formation_slots[idx]
	if cur_cid == "" or not party_actors.has(cur_cid):
		CampaignState.controlled_slot = packed[0]


func get_controlled_char_id() -> String:
	var idx: int = clampi(CampaignState.controlled_slot - 1, 0, 3)
	var cid: String = CampaignState.formation_slots[idx]
	if cid != "" and party_actors.has(cid):
		return cid
	var packed: Array[int] = get_occupied_formation_slots()
	if not packed.is_empty():
		return CampaignState.formation_slots[packed[0] - 1]
	for k_var: Variant in party_actors.keys():
		return str(k_var)
	return "gu_changqing"


func get_controlled_actor() -> BattleActor:
	var cid: String = get_controlled_char_id()
	return party_actors.get(cid, null) as BattleActor


func get_controlled_actor_pos() -> Vector2:
	var a: BattleActor = get_controlled_actor()
	return a.position if a != null else Vector2(360.0, 620.0)


func toggle_tactical_pause() -> void:
	if not in_combat and not tactical_paused:
		# 仅在进入战斗时开启战术凝时（避免平时逛街误按空格冻住自己）
		return
	tactical_paused = not tactical_paused
	if audio_director != null:
		audio_director.set_tactical_pause_filter(tactical_paused)
	combat_hud_dirty.emit()


func switch_controlled_party_slot(slot_num: int, center_camera: bool = false) -> void:
	var packed: Array[int] = get_occupied_formation_slots()
	if slot_num < 1 or slot_num > packed.size():
		return
	var resolved_slot: int = packed[slot_num - 1]
	var cid: String = CampaignState.formation_slots[resolved_slot - 1]
	if cid == "" or not party_actors.has(cid):
		return
	CampaignState.controlled_slot = resolved_slot
	for k_var: Variant in party_actors.keys():
		var k: String = str(k_var)
		var pa: BattleActor = party_actors[k] as BattleActor
		pa.is_controlled = (k == cid)
	if center_camera and world_camera != null:
		world_camera.position = (party_actors[cid] as BattleActor).position
	combat_hud_dirty.emit()


func switch_controlled_member(cid: String, center_camera: bool = false) -> void:
	if cid == "" or not party_actors.has(cid):
		return
	var f_slot: int = CampaignState.get_member_formation_slot(cid)
	if f_slot < 1:
		return
	var packed_idx: int = get_occupied_formation_slots().find(f_slot) + 1
	if packed_idx >= 1:
		switch_controlled_party_slot(packed_idx, center_camera)


func get_occupied_formation_slots() -> Array[int]:
	var out: Array[int] = []
	for i: int in range(CampaignState.formation_slots.size()):
		var cid: String = CampaignState.formation_slots[i]
		if cid != "" and party_actors.has(cid):
			out.append(i + 1)
	return out


func cycle_tab_enemy_target() -> void:
	var ctrl_pos: Vector2 = get_controlled_actor_pos()
	var casting_candidates: Array[BattleActor] = []
	var normal_candidates: Array[BattleActor] = []
	for ea: BattleActor in enemy_actors:
		if not ea.alive:
			continue
		if ea.position.distance_to(ctrl_pos) <= 680.0:
			if ea.is_casting and ea.cast_interruptible:
				casting_candidates.append(ea)
			else:
				normal_candidates.append(ea)

	# 优先切正在读琥珀金条的施法怪！
	var ordered: Array[BattleActor] = []
	ordered.append_array(casting_candidates)
	ordered.append_array(normal_candidates)
	if ordered.is_empty():
		return

	var cur_idx: int = -1
	for i: int in range(ordered.size()):
		if ordered[i].actor_id == locked_enemy_id:
			cur_idx = i
			break
	var next_ea: BattleActor = ordered[(cur_idx + 1) % ordered.size()]
	set_locked_enemy(next_ea.actor_id, in_combat)


func set_locked_enemy(enemy_uid: String, enable_auto_atk: bool = false) -> void:
	locked_enemy_id = enemy_uid
	if enable_auto_atk and enemy_uid != "":
		auto_attack_enabled = true
	for ea: BattleActor in enemy_actors:
		ea.is_targeted = (ea.actor_id == locked_enemy_id)
	combat_hud_dirty.emit()


func command_move_selected_to(world_dest: Vector2) -> void:
	var targets: Array[BattleActor] = []
	if not box_selected_ids.is_empty():
		for sid: String in box_selected_ids:
			if party_actors.has(sid):
				targets.append(party_actors[sid] as BattleActor)
			elif pet_actor != null and pet_actor.actor_id == sid:
				targets.append(pet_actor)
	else:
		var ctrl: BattleActor = get_controlled_actor()
		if ctrl != null:
			targets.append(ctrl)

	if targets.is_empty():
		return
	var spread_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(-44.0, 26.0),
		Vector2(44.0, 26.0),
		Vector2(0.0, 48.0),
	]
	for i: int in range(targets.size()):
		var act: BattleActor = targets[i]
		if not act.alive:
			continue
		act.move_waypoint = _clamp_to_walkable(world_dest + spread_offsets[mini(i, spread_offsets.size() - 1)])
		act.has_move_waypoint = true
		# 移动立即打断该角色未完成的读条（零延迟走位躲圈）
		if unit_states.has(act.actor_id):
			var st: Dictionary = unit_states[act.actor_id] as Dictionary
			if bool(st.get("casting", false)):
				st["casting"] = false
				act.is_casting = false


func activate_stealth_talisman() -> bool:
	if in_combat:
		NotifyHub.push_combat_banner("已入斗法杀局，敛息符无法掩盖气机！", "warn", "none")
		return false
	if CampaignState.get_item_count("item_stealth_talisman") <= 0:
		return false
	CampaignState.remove_item("item_stealth_talisman", 1)
	stealth_timer = 20.0
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_page_turn", AudioDirector.TIER_A, true)
	NotifyHub.push_explore_slip(tr("ITEM_STEALTH_TALISMAN_NAME"), tr("HUD_STEALTH_ACTIVE"), "stealth")
	combat_hud_dirty.emit()
	return true


## 响应快捷栏按键（1~4, Q, E, R, G, 5, 6, STUNT）
func trigger_hotkey_slot(slot_code: String) -> void:
	var ctrl_id: String = get_controlled_char_id()
	if not unit_states.has(ctrl_id):
		return

	if slot_code == "5" or slot_code == "6":
		_use_instant_combat_pill(ctrl_id, CampaignState.quick_pill_5_id if slot_code == "5" else CampaignState.quick_pill_6_id)
		return

	var caster_id: String = ctrl_id
	var skill_id: String = ""
	if slot_code == "G":
		if CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"):
			skill_id = "ult_qinglian_sword"
		else:
			return
	elif slot_code == "STUNT":
		var stunt_info: Dictionary = get_active_blue_stunt_info()
		skill_id = str(stunt_info.get("skill_id", ""))
		var owner_id: String = str(stunt_info.get("owner_id", ""))
		if owner_id != "" and unit_states.has(owner_id):
			caster_id = owner_id
	else:
		var bar: Dictionary = CampaignState.get_member_active_skills(ctrl_id)
		skill_id = str(bar.get(slot_code, ""))

	if skill_id == "":
		return

	var sdef: Dictionary = DataDB.get_skill(skill_id)
	if sdef.is_empty():
		return

	var target_id: String = _resolve_skill_target_id(ctrl_id, sdef)
	if tactical_paused:
		# 战术凝时期间：为施法者预排下一个技能与目标！
		var u: Dictionary = unit_states[caster_id] as Dictionary
		u["queued_slot"] = slot_code
		u["queued_skill_id"] = skill_id
		u["queued_target_id"] = target_id
		if audio_director != null:
			audio_director.play_sfx("sfx_ui_jade_click", AudioDirector.TIER_B, true)
		combat_hud_dirty.emit()
		return

	_try_execute_party_skill(caster_id, skill_id, target_id, true)


func trigger_pet_manual_skill(pet_slot_idx: int) -> void:
	if pet_actor == null or not pet_actor.alive:
		return
	var pstate: Dictionary = unit_states.get(pet_actor.actor_id, {}) as Dictionary
	var pdef: Dictionary = DataDB.get_pet(str(pstate.get("pet_def_id", "")))
	var sk_id: String = str(pdef.get("skill_1" if pet_slot_idx == 1 else "skill_2", ""))
	if sk_id == "":
		return
	_execute_pet_skill(pstate, DataDB.get_skill(sk_id))


func try_switch_formation(new_formation_id: String) -> bool:
	if not CampaignState.unlocked_formations.has(new_formation_id):
		return false
	if new_formation_id == CampaignState.active_formation_id:
		return false
	if in_combat and formation_switch_cd > 0.0:
		return false
	CampaignState.set_active_formation(new_formation_id)
	sync_party_roster_in_place()
	if in_combat:
		formation_switch_cd = FormationRules.FORMATION_SWITCH_COOLDOWN_SEC
		formation_switch_cd_total = FormationRules.FORMATION_SWITCH_COOLDOWN_SEC
	if audio_director != null:
		audio_director.play_sfx("sfx_stele_activate", AudioDirector.TIER_A)
	var fdef: Dictionary = DataDB.get_formation(new_formation_id)
	NotifyHub.push_combat_banner("奇门变阵 ·【%s】！" % DataDB.loc(str(fdef.get("name_key", new_formation_id))), "formation", "earth")
	return true


## ==================== 主步进入口（由世界场景每物理帧调用） ====================
func step_world_and_combat(raw_delta: float, zone_bounds: Rect2) -> void:
	var ui_delta: float = raw_delta
	if SaveManager.reduced_motion or SaveManager.screen_shake_pct <= 0.001:
		_hitstop_timer = 0.0
	if _minor_hitstop_cd > 0.0:
		_minor_hitstop_cd = maxf(0.0, _minor_hitstop_cd - ui_delta)

	var in_hitstop: bool = _hitstop_timer > 0.0
	if _hitstop_timer > 0.0:
		_hitstop_timer = maxf(0.0, _hitstop_timer - ui_delta)

	var combat_delta: float = 0.0 if (tactical_paused or in_hitstop) else raw_delta
	_step_camera_shake(ui_delta)

	if stealth_timer > 0.0 and combat_delta > 0.0:
		stealth_timer = maxf(0.0, stealth_timer - combat_delta)

	# 1. 更新当前主控角色 WASD 走位（仅在非凝时态与非顿帧态实时推进；凝时态由右键路径线预览）
	var ctrl_actor: BattleActor = get_controlled_actor()
	var move_vec: Vector2 = InputRouter.get_movement_vector()
	var ctrl_moving_wasd: bool = false

	if not tactical_paused and not in_hitstop and ctrl_actor != null and ctrl_actor.alive and move_vec.length_squared() > 0.001:
		ctrl_moving_wasd = true
		ctrl_actor.has_move_waypoint = false
		var ctrl_u: Dictionary = unit_states.get(ctrl_actor.actor_id, {}) as Dictionary
		if bool(ctrl_u.get("casting", false)):
			# 走位立即中断自身未完成吟唱，但绝不重置自动平砍计时器！
			ctrl_u["casting"] = false
			ctrl_actor.is_casting = false
		var spd: float = float((ctrl_u.get("sheet", {}) as Dictionary).get("move_speed_px", 220.0))
		if stealth_timer > 0.0:
			spd *= 0.90
		ctrl_actor.set_facing(move_vec)
		ctrl_actor.position = _resolve_move_collision(ctrl_actor.position, ctrl_actor.position + move_vec * spd * combat_delta, zone_bounds)

	# 2. 步进所有战斗时钟、明雷视野、AI 与技能结算
	if combat_delta > 0.0:
		_step_global_timers(combat_delta)
		_check_overwatch_aggro_and_leash(combat_delta, zone_bounds)
		_step_party_units(combat_delta, ctrl_moving_wasd, zone_bounds)
		_step_pet_unit(combat_delta, zone_bounds)
		_step_enemy_units(combat_delta, zone_bounds)
		_check_combat_resolution()

	# 3. 同步地面危招阵纹与凝时走位预览线（即使 Space 凝时也 60fps 实时刷新，同时把粒子锁定为 0.0！）
	_refresh_vfx_overlays(combat_delta, ui_delta)

	# 4. 步进所有实体关键帧与头顶姓名板显示
	for cid_var: Variant in party_actors.keys():
		var cid: String = str(cid_var)
		var pa: BattleActor = party_actors[cid] as BattleActor
		pa.stealth_alpha = 0.52 if (stealth_timer > 0.0 and not in_combat) else 1.0
		var is_mov: bool = (pa == ctrl_actor and ctrl_moving_wasd) or pa.has_move_waypoint
		pa.step_visuals(combat_delta, ui_delta, is_mov)

	if pet_actor != null:
		pet_actor.stealth_alpha = 0.52 if (stealth_timer > 0.0 and not in_combat) else 1.0
		pet_actor.step_visuals(combat_delta, ui_delta, pet_actor.has_move_waypoint)

	for ea: BattleActor in enemy_actors:
		if is_instance_valid(ea):
			var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
			ea.step_visuals(combat_delta, ui_delta, bool(eu.get("is_moving", false)))

	if ctrl_actor != null:
		CampaignState.saved_player_pos = ctrl_actor.position


func _step_global_timers(dt: float) -> void:
	if in_combat:
		combat_clock_sec += dt
		out_of_combat_sec = 0.0
	else:
		out_of_combat_sec += dt

	if preemptive_buff_timer > 0.0:
		preemptive_buff_timer = maxf(0.0, preemptive_buff_timer - dt)
	if pill_cooldown_timer > 0.0:
		pill_cooldown_timer = maxf(0.0, pill_cooldown_timer - dt)
	if formation_switch_cd > 0.0:
		formation_switch_cd = maxf(0.0, formation_switch_cd - dt)
	if party_haste_buff_timer > 0.0:
		party_haste_buff_timer = maxf(0.0, party_haste_buff_timer - dt)
		if party_haste_buff_timer <= 0.0:
			party_haste_buff_val = 0.0
	if loyal_guard_timer > 0.0:
		loyal_guard_timer = maxf(0.0, loyal_guard_timer - dt)

	# 脱战满 3 秒自然回血回真元
	if not in_combat and out_of_combat_sec >= 3.0:
		for cid_var: Variant in party_actors.keys():
			var cid: String = str(cid_var)
			var pa: BattleActor = party_actors[cid] as BattleActor
			if not pa.alive:
				continue
			var u: Dictionary = unit_states[cid] as Dictionary
			var sh: Dictionary = u.get("sheet", {}) as Dictionary
			var hp_reg: float = float(sh.get("ooc_hp_regen_per_sec", 8.0)) * dt * 2.2
			var mp_reg: float = float(sh.get("ooc_mp_regen_per_sec", 6.0)) * dt * 2.5
			if pa.hp < pa.max_hp:
				pa.hp = mini(pa.max_hp, pa.hp + maxi(1, int(round(hp_reg))))
			if pa.mp < pa.max_mp:
				pa.mp = mini(pa.max_mp, pa.mp + maxi(1, int(round(mp_reg))))
			var mstate: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
			mstate["hp"] = pa.hp
			mstate["mp"] = pa.mp


func _check_overwatch_aggro_and_leash(dt: float, zone_bounds: Rect2) -> void:
	var active_party_list: Array[BattleActor] = []
	for cid_var: Variant in party_actors.keys():
		var pa: BattleActor = party_actors[str(cid_var)] as BattleActor
		if pa.alive:
			active_party_list.append(pa)
	if active_party_list.is_empty():
		return

	var stealth_mult: float = 0.30 if stealth_timer > 0.0 else 1.0

	for ea: BattleActor in enemy_actors:
		if not ea.alive:
			continue
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		var engaged: bool = bool(eu.get("engaged", false))

		if not engaged:
			# 110 巡逻移动
			if ea.patrol_points.size() >= 2:
				var pt_target: Vector2 = ea.patrol_points[ea.patrol_index]
				var to_pt: Vector2 = pt_target - ea.position
				if to_pt.length() <= 14.0:
					ea.patrol_index = (ea.patrol_index + 1) % ea.patrol_points.size()
					eu["is_moving"] = false
				else:
					var dir_p: Vector2 = to_pt.normalized()
					ea.set_facing(dir_p)
					ea.position = _resolve_move_collision(ea.position, ea.position + dir_p * float(eu.get("move_speed_px", 170.0)) * 0.68 * dt, zone_bounds)
					eu["is_moving"] = true
			else:
				var back_home: Vector2 = ea.home_pos - ea.position
				if back_home.length() > 16.0:
					var dir_h: Vector2 = back_home.normalized()
					ea.set_facing(dir_h)
					ea.position += dir_h * 220.0 * dt
					eu["is_moving"] = true
				else:
					eu["is_moving"] = false

			# 视野警戒检测（含障碍柱遮挡 Line of Sight 判断！）
			var eff_aggro: float = float(eu.get("aggro_radius_px", 250.0)) * (1.0 if ea.is_boss else stealth_mult)
			var vtype: String = str(eu.get("vision_type", "circle"))
			for pa2: BattleActor in active_party_list:
				var dist: float = ea.position.distance_to(pa2.position)
				if dist > eff_aggro:
					continue
				if _is_line_of_sight_blocked(ea.position, pa2.position):
					continue
				if vtype == "cone_120" and dist > eff_aggro * 0.48:
					var to_ally: Vector2 = (pa2.position - ea.position).normalized()
					if ea.facing_dir.dot(to_ally) < 0.35:
						continue
				_engage_enemy_group(str(eu.get("group_id", "")), pa2.actor_id, false)
				break
		else:
			# 牵引边界（Leash）脱战归位检测
			var leash_r: float = float(eu.get("leash_radius_px", 580.0))
			if ea.position.distance_to(ea.home_pos) > leash_r:
				_reset_enemy_leash(eu, ea)


func _is_line_of_sight_blocked(a: Vector2, b: Vector2) -> bool:
	var seg: Vector2 = b - a
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 1.0:
		return false
	for obs: Dictionary in obstacle_circles:
		var c: Vector2 = obs.get("pos", Vector2.ZERO) as Vector2
		var r: float = float(obs.get("radius", 40.0)) * 0.85
		var t: float = clampf((c - a).dot(seg) / seg_len_sq, 0.0, 1.0)
		var closest: Vector2 = a + seg * t
		if closest.distance_to(c) < r:
			return true
	return false


func engage_enemy_group(group_id: String, initial_target_id: String, is_preemptive_pull: bool) -> void:
	_engage_enemy_group(group_id, initial_target_id, is_preemptive_pull)


func _engage_enemy_group(group_id: String, initial_target_id: String, is_preemptive_pull: bool) -> void:
	var newly_entered: bool = not in_combat
	var boss_found: BattleActor = null

	for ea: BattleActor in enemy_actors:
		if not ea.alive:
			continue
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("group_id", "")) == group_id or ea.position.distance_to(get_controlled_actor_pos()) < 260.0 and str(eu.get("group_id", "")) == group_id:
			if not bool(eu.get("engaged", false)):
				eu["engaged"] = true
				var tbl: Dictionary = eu.get("threat_table", {}) as Dictionary
				# 初始给 2 号玄武位一定天然接怪注意，方便主坦稳接
				for cid_var: Variant in party_actors.keys():
					var cid: String = str(cid_var)
					var pu: Dictionary = unit_states[cid] as Dictionary
					tbl[cid] = 28.0 if bool(pu.get("is_tank_role", false)) else 10.0
				tbl[initial_target_id] = float(tbl.get(initial_target_id, 10.0)) + 25.0
				eu["target_id"] = initial_target_id
			if ea.is_boss:
				boss_found = ea

	stealth_timer = 0.0
	if newly_entered:
		in_combat = true
		combat_clock_sec = 0.0
		death_ring_buffer.clear()
		InputRouter.combat_engaged = true
		NotifyHub.set_combat_active(true)
		if is_preemptive_pull:
			preemptive_buff_timer = RtwpSimStep.PREEMPTIVE_PULL_DURATION_SEC
			NotifyHub.push_combat_banner(tr("HUD_PREEMPTIVE_BUFF"), "preemptive", "metal")
		if audio_director != null:
			if boss_found != null:
				audio_director.play_special_bgm("res://assets/audio/bgm/bgm_boss_wolf_king.ogg", "boss_wolf")
			else:
				audio_director.set_combat_engaged(true)

	if boss_found != null:
		boss_combat_changed.emit(boss_found)
	if locked_enemy_id == "":
		cycle_tab_enemy_target()
	auto_attack_enabled = true
	combat_hud_dirty.emit()


func _reset_enemy_leash(eu: Dictionary, ea: BattleActor) -> void:
	eu["engaged"] = false
	eu["casting"] = false
	eu["threat_table"] = {}
	eu["target_id"] = ""
	eu["phase"] = 1
	eu["hp"] = int(eu.get("max_hp", 200))
	eu["ward_current"] = float(eu.get("ward_max", 0.0))
	eu["stagger_timer"] = 0.0
	ea.hp = int(eu["hp"])
	ea.ward_current = float(eu["ward_current"])
	ea.is_casting = false


func _step_party_units(dt: float, ctrl_moving_wasd: bool, zone_bounds: Rect2) -> void:
	var ctrl_id: String = get_controlled_char_id()
	var ctrl_actor: BattleActor = get_controlled_actor()

	for idx_slot: int in range(CampaignState.formation_slots.size()):
		var cid: String = CampaignState.formation_slots[idx_slot]
		if cid == "" or not party_actors.has(cid):
			continue
		var actor: BattleActor = party_actors[cid] as BattleActor
		var u: Dictionary = unit_states[cid] as Dictionary
		if not actor.alive:
			continue

		var sheet: Dictionary = u.get("sheet", {}) as Dictionary
		var eff_haste: float = clampf(
			float(sheet.get("haste_pct", 0.0)) + party_haste_buff_val + (0.15 if preemptive_buff_timer > 0.0 else 0.0),
			0.0, 0.45
		)

		# 冷却与 Buff 计时
		u["gcd_timer"] = maxf(0.0, float(u.get("gcd_timer", 0.0)) - dt)
		u["attack_timer"] = maxf(0.0, float(u.get("attack_timer", 0.0)) - dt * (1.0 + eff_haste * 0.5))
		u["dr_buff_timer"] = maxf(0.0, float(u.get("dr_buff_timer", 0.0)) - dt)
		u["ward_buff_timer"] = maxf(0.0, float(u.get("ward_buff_timer", 0.0)) - dt)
		u["miasma_immune_timer"] = maxf(0.0, float(u.get("miasma_immune_timer", 0.0)) - dt)

		var cds: Dictionary = u.get("cooldowns", {}) as Dictionary
		var cd_tots: Dictionary = u.get("cooldown_totals", {}) as Dictionary
		for sk_k_var: Variant in cds.keys():
			var sk_k: String = str(sk_k_var)
			var rem_cd: float = float(cds[sk_k]) - dt
			if rem_cd <= 0.0:
				cds.erase(sk_k)
				cd_tots.erase(sk_k)
			else:
				cds[sk_k] = rem_cd

		# 持续回春 HoT 与腐瘴 DoT
		if float(u.get("hot_timer", 0.0)) > 0.0:
			var prev_hot: float = float(u["hot_timer"])
			u["hot_timer"] = maxf(0.0, prev_hot - dt)
			if int(floor(prev_hot)) != int(floor(float(u["hot_timer"]))):
				var tick_heal: int = maxi(2, int(round(float(u.get("hot_hps", 8.0)))))
				_apply_ally_heal(cid, actor, tick_heal, false)

		var m_stacks: int = int(u.get("miasma_stacks", 0))
		actor.miasma_stacks = m_stacks
		if m_stacks > 0:
			var mt: float = float(u.get("miasma_tick_timer", 0.0)) + dt
			if mt >= 2.0:
				mt -= 2.0
				var m_dmg: int = maxi(3, m_stacks * 6)
				_apply_damage_to_ally(cid, actor, m_dmg, "腐木疫瘴", "腐瘴侵脉", "wood", false, false)
			u["miasma_tick_timer"] = mt

		actor.shield = float(u.get("shield", 0.0))

		# 处理右键指定走位点或脱战跟随队形
		if actor.has_move_waypoint:
			var to_wp: Vector2 = actor.move_waypoint - actor.position
			if to_wp.length() <= 14.0:
				actor.has_move_waypoint = false
			else:
				var mdir: Vector2 = to_wp.normalized()
				actor.set_facing(mdir)
				actor.position = _resolve_move_collision(actor.position, actor.position + mdir * float(sheet.get("move_speed_px", 215.0)) * dt, zone_bounds)
		elif cid != ctrl_id and not in_combat and ctrl_actor != null:
			var follow_offset: Vector2 = Vector2(-54.0 * float(idx_slot), 28.0 * float((idx_slot % 2) * 2 - 1))
			var follow_goal: Vector2 = ctrl_actor.position + follow_offset
			var to_f: Vector2 = follow_goal - actor.position
			if to_f.length() > 68.0:
				var fdir: Vector2 = to_f.normalized()
				actor.set_facing(fdir)
				actor.position = _resolve_move_collision(actor.position, actor.position + fdir * float(sheet.get("move_speed_px", 215.0)) * 1.05 * dt, zone_bounds)

		# 吟唱读条推进
		if bool(u.get("casting", false)):
			var cp: float = float(u.get("cast_progress", 0.0)) + dt
			var cdur: float = float(u.get("cast_duration", 1.0))
			u["cast_progress"] = cp
			actor.is_casting = true
			actor.cast_progress = cp
			actor.cast_duration = cdur
			if cp >= cdur:
				u["casting"] = false
				actor.is_casting = false
				actor.play_action_anim("cast_release", 0.36)
				_resolve_party_skill_effect(cid, str(u.get("cast_skill_id", "")), str(u.get("cast_target_id", "")))
			continue

		# 执行战术凝时预排技能队列
		var q_sk: String = str(u.get("queued_skill_id", ""))
		if q_sk != "" and float(u.get("gcd_timer", 0.0)) <= 0.0:
			var q_tgt: String = str(u.get("queued_target_id", ""))
			u["queued_slot"] = ""
			u["queued_skill_id"] = ""
			u["queued_target_id"] = ""
			if _try_execute_party_skill(cid, q_sk, q_tgt, cid == ctrl_id):
				continue

		# 主控角色自动普攻 vs AI 队友协同职责循环
		if cid == ctrl_id:
			if auto_attack_enabled and locked_enemy_id != "":
				var tgt_ea: BattleActor = _find_enemy_actor(locked_enemy_id)
				if tgt_ea != null and tgt_ea.alive:
					var atk_rng: float = float(sheet.get("attack_range_px", 145.0))
					var dist_e: float = actor.position.distance_to(tgt_ea.position)
					if dist_e > atk_rng and not ctrl_moving_wasd and not actor.has_move_waypoint:
						var chase_dir: Vector2 = (tgt_ea.position - actor.position).normalized()
						actor.set_facing(chase_dir)
						actor.position = _resolve_move_collision(actor.position, actor.position + chase_dir * float(sheet.get("move_speed_px", 220.0)) * dt, zone_bounds)
					elif dist_e <= atk_rng + 12.0 and float(u.get("attack_timer", 0.0)) <= 0.0:
						_perform_party_auto_attack(cid, actor, u, tgt_ea)
		elif in_combat:
			_run_companion_ai(cid, actor, u, dt, zone_bounds)

		# 实时回写气血真元至 CampaignState
		var m_sync: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		m_sync["hp"] = actor.hp
		m_sync["mp"] = actor.mp


func _run_companion_ai(cid: String, actor: BattleActor, u: Dictionary, dt: float, zone_bounds: Rect2) -> void:
	if actor.has_move_waypoint:
		return
	var mstate: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
	var preset_idx: int = int(mstate.get("ai_preset_index", 0))
	var bar: Dictionary = CampaignState.get_member_active_skills(cid)
	var sheet: Dictionary = u.get("sheet", {}) as Dictionary

	# 1. 优先响应可打断琥珀金读条（裴照破罡断法 / 沈清禾远程银针）
	var q_skill_id: String = str(bar.get("Q", ""))
	if q_skill_id != "" and not (u.get("cooldowns", {}) as Dictionary).has(q_skill_id):
		for ea: BattleActor in enemy_actors:
			if ea.alive and ea.is_casting and ea.cast_interruptible and ea.cast_progress >= ea.cast_duration * 0.42:
				if cid == "pei_zhao" and preset_idx == 0:
					if _try_execute_party_skill(cid, q_skill_id, ea.actor_id, false):
						return

	# 2. 沈清禾医修职责 AI：驱散毒瘴 + 低血抬线 + 挂苍木母印
	if cid == "shen_qinghe":
		if float(u.get("gcd_timer", 0.0)) <= 0.0:
			var lowest_id: String = ""
			var lowest_ratio: float = 1.0
			var miasma_ally_id: String = ""
			for pid_var: Variant in party_actors.keys():
				var pid: String = str(pid_var)
				var pa: BattleActor = party_actors[pid] as BattleActor
				if not pa.alive:
					continue
				var r: float = float(pa.hp) / float(maxi(1, pa.max_hp))
				if r < lowest_ratio:
					lowest_ratio = r
					lowest_id = pid
				if pa.miasma_stacks > 0:
					miasma_ally_id = pid

			var threshold: float = 0.52 if preset_idx == 2 else 0.72
			if miasma_ally_id != "" and _can_cast_skill(u, actor, str(bar.get("2", ""))):
				if _try_execute_party_skill(cid, str(bar.get("2", "")), miasma_ally_id, false):
					return
			if lowest_id != "" and lowest_ratio < 0.55 and _can_cast_skill(u, actor, str(bar.get("E", ""))):
				if _try_execute_party_skill(cid, str(bar.get("E", "")), lowest_id, false):
					return
			if lowest_id != "" and lowest_ratio < threshold and _can_cast_skill(u, actor, str(bar.get("1", ""))):
				if _try_execute_party_skill(cid, str(bar.get("1", "")), lowest_id, false):
					return
			if preset_idx != 2:
				var focus_e: BattleActor = _pick_ai_enemy_target(actor.position)
				if focus_e != null and focus_e.mother_seal_element == "" and _can_cast_skill(u, actor, str(bar.get("4", ""))):
					if _try_execute_party_skill(cid, str(bar.get("4", "")), focus_e.actor_id, false):
						return

	# 3. 裴照 / 顾长青 AI：玄武位嘲讽接怪 + 五行相生引爆 + 破罡循环
	var target_enemy: BattleActor = _pick_ai_enemy_target(actor.position)
	if target_enemy == null:
		return

	if bool(u.get("is_tank_role", false)) or (cid == "pei_zhao" and preset_idx == 1):
		var e_sk: String = str(bar.get("E", ""))
		var e_def: Dictionary = DataDB.get_skill(e_sk)
		if bool(e_def.get("is_taunt", false)) and _can_cast_skill(u, actor, e_sk):
			var eu_t: Dictionary = unit_states.get(target_enemy.actor_id, {}) as Dictionary
			if str(eu_t.get("target_id", "")) != cid:
				_try_execute_party_skill(cid, e_sk, target_enemy.actor_id, false)

	var atk_range: float = float(sheet.get("attack_range_px", 145.0))
	var dist: float = actor.position.distance_to(target_enemy.position)
	if dist > atk_range:
		var dir_c: Vector2 = (target_enemy.position - actor.position).normalized()
		actor.set_facing(dir_c)
		actor.position = _resolve_move_collision(actor.position, actor.position + dir_c * float(sheet.get("move_speed_px", 215.0)) * dt, zone_bounds)
	else:
		actor.set_facing(target_enemy.position - actor.position)
		if float(u.get("gcd_timer", 0.0)) <= 0.0 and cid != "shen_qinghe":
			# 优先施放能引爆母印的子属性技能
			for slot_try: String in ["3", "2", "1"]:
				var try_id: String = str(bar.get(slot_try, ""))
				if _can_cast_skill(u, actor, try_id):
					var s_elem: String = str(DataDB.get_skill(try_id).get("element", "none"))
					if _does_trigger_synergy(target_enemy.mother_seal_element, s_elem):
						if _try_execute_party_skill(cid, try_id, target_enemy.actor_id, false):
							return
			var s1: String = str(bar.get("1", ""))
			if _can_cast_skill(u, actor, s1):
				if _try_execute_party_skill(cid, s1, target_enemy.actor_id, false):
					return

		if float(u.get("attack_timer", 0.0)) <= 0.0:
			_perform_party_auto_attack(cid, actor, u, target_enemy)


func _step_pet_unit(dt: float, zone_bounds: Rect2) -> void:
	if pet_actor == null or not pet_actor.alive or not unit_states.has(pet_actor.actor_id):
		return
	var pu: Dictionary = unit_states[pet_actor.actor_id] as Dictionary
	pu["attack_timer"] = maxf(0.0, float(pu.get("attack_timer", 0.0)) - dt)
	var cds: Dictionary = pu.get("cooldowns", {}) as Dictionary
	var p_cd_tots: Dictionary = pu.get("cooldown_totals", {}) as Dictionary
	for k_var: Variant in cds.keys():
		var k: String = str(k_var)
		var rem: float = float(cds[k]) - dt
		if rem <= 0.0:
			cds.erase(k)
			p_cd_tots.erase(k)
		else:
			cds[k] = rem

	if pet_actor.has_move_waypoint:
		var to_wp: Vector2 = pet_actor.move_waypoint - pet_actor.position
		if to_wp.length() <= 14.0:
			pet_actor.has_move_waypoint = false
		else:
			var pdir: Vector2 = to_wp.normalized()
			pet_actor.set_facing(pdir)
			pet_actor.position = _resolve_move_collision(pet_actor.position, pet_actor.position + pdir * float(pu.get("move_speed_px", 220.0)) * dt, zone_bounds)
		return

	var leader: BattleActor = get_controlled_actor()
	if not in_combat or CampaignState.pet_stance == "follow":
		if leader != null:
			var goal: Vector2 = leader.position + Vector2(44.0, 34.0)
			if pet_actor.position.distance_to(goal) > 48.0:
				var fdir: Vector2 = (goal - pet_actor.position).normalized()
				pet_actor.set_facing(fdir)
				pet_actor.position = _resolve_move_collision(pet_actor.position, pet_actor.position + fdir * float(pu.get("move_speed_px", 220.0)) * dt, zone_bounds)
		return

	if CampaignState.pet_stance == "hold":
		return

	var target_e: BattleActor = _pick_ai_enemy_target(pet_actor.position)
	if target_e == null:
		return
	var rng: float = float(pu.get("attack_range_px", 220.0))
	if pet_actor.position.distance_to(target_e.position) > rng:
		var cdir: Vector2 = (target_e.position - pet_actor.position).normalized()
		pet_actor.set_facing(cdir)
		pet_actor.position = _resolve_move_collision(pet_actor.position, pet_actor.position + cdir * float(pu.get("move_speed_px", 220.0)) * dt, zone_bounds)
	elif float(pu.get("attack_timer", 0.0)) <= 0.0:
		pu["attack_timer"] = float(pu.get("attack_interval", 1.75))
		pet_actor.set_facing(target_e.position - pet_actor.position)
		pet_actor.play_action_anim("attack_1", 0.35)
		var pdef: Dictionary = DataDB.get_pet(str(pu.get("pet_def_id", "")))
		if sky_vfx != null:
			if str(pu.get("pet_def_id", "")) == "pet_fire_fox":
				sky_vfx.spawn_element_bolt(pet_actor.get_vfx_origin_world("mouth"), target_e.get_vfx_origin_world("chest"), "fire", 0.19)
			else:
				sky_vfx.spawn_slash_arc(pet_actor.get_vfx_origin_world("mouth"), target_e.position - pet_actor.position, "water_frost", 78.0, 0.24, false)
		_deal_damage_to_enemy(pet_actor.actor_id, pet_actor.position, target_e, float(pu.get("power", 18.0)), 1.0, str(pdef.get("element", "none")), 14.0, 0.08, 1.5, false, 0.0, 1.0, 1.0, false, float(pu.get("threat_mult", 1.0)), 0.0, "")


func _step_enemy_units(dt: float, zone_bounds: Rect2) -> void:
	var ctrl_id: String = get_controlled_char_id()
	for i: int in range(enemy_actors.size()):
		var ea: BattleActor = enemy_actors[i]
		if not is_instance_valid(ea) or not ea.alive:
			continue
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		if not bool(eu.get("engaged", false)):
			continue

		eu["is_moving"] = false
		eu["taunt_timer"] = maxf(0.0, float(eu.get("taunt_timer", 0.0)) - dt)
		eu["lockout_timer"] = maxf(0.0, float(eu.get("lockout_timer", 0.0)) - dt)
		eu["slow_timer"] = maxf(0.0, float(eu.get("slow_timer", 0.0)) - dt)
		eu["atk_slow_timer"] = maxf(0.0, float(eu.get("atk_slow_timer", 0.0)) - dt)
		ea.lockout_timer = float(eu["lockout_timer"])

		if float(eu.get("mother_seal_timer", 0.0)) > 0.0:
			eu["mother_seal_timer"] = maxf(0.0, float(eu["mother_seal_timer"]) - dt)
			if float(eu["mother_seal_timer"]) <= 0.0:
				eu["mother_seal_element"] = ""
		ea.mother_seal_element = str(eu.get("mother_seal_element", ""))
		ea.mother_seal_timer = float(eu.get("mother_seal_timer", 0.0))

		# DoT 持续伤害与枯荣吸血
		if float(eu.get("dot_timer", 0.0)) > 0.0:
			var prev_d: float = float(eu["dot_timer"])
			eu["dot_timer"] = maxf(0.0, prev_d - dt)
			if int(floor(prev_d)) != int(floor(float(eu["dot_timer"]))):
				var tick_d: int = maxi(2, int(round(float(eu.get("dot_dps", 6.0)))))
				_apply_direct_enemy_hp_loss(eu, ea, tick_d, "wood", false, "", true)
				var leech: float = float(eu.get("dot_leech_pct", 0.0))
				if leech > 0.0:
					_heal_lowest_party_member(maxi(2, int(round(float(tick_d) * leech))))
				if not ea.alive:
					continue

		# 破罡 6 秒【气机破绽】窗口恢复
		if float(eu.get("stagger_timer", 0.0)) > 0.0:
			eu["stagger_timer"] = maxf(0.0, float(eu["stagger_timer"]) - dt)
			ea.stagger_timer = float(eu["stagger_timer"])
			if float(eu["stagger_timer"]) <= 0.0 and float(eu.get("ward_max", 0.0)) > 0.0:
				eu["ward_current"] = float(eu["ward_max"])
				ea.ward_current = float(eu["ward_current"])

		if float(eu.get("stun_timer", 0.0)) > 0.0:
			eu["stun_timer"] = maxf(0.0, float(eu["stun_timer"]) - dt)
			continue

		var ecds: Dictionary = eu.get("cooldowns", {}) as Dictionary
		for ek_var: Variant in ecds.keys():
			var ek: String = str(ek_var)
			var erem: float = float(ecds[ek]) - dt
			if erem <= 0.0:
				ecds.erase(ek)
			else:
				ecds[ek] = erem

		# 雾隐狼王阶段转换与幼狼召唤机制
		if ea.is_boss:
			var hp_pct: float = float(ea.hp) / float(maxi(1, ea.max_hp))
			var edef: Dictionary = eu.get("edef", {}) as Dictionary
			if not bool(eu.get("summoned_p1", false)) and hp_pct <= 0.84:
				eu["summoned_p1"] = true
				var pup_id: String = str(edef.get("summon_p1_enemy_id", "wolf_pup"))
				var pup_cnt: int = int(edef.get("summon_p1_count", 2))
				for p_i: int in range(pup_cnt):
					var offset_p: Vector2 = Vector2(-95.0 + 190.0 * float(p_i), 55.0)
					var pup: BattleActor = spawn_enemy_unit(pup_id, _clamp_to_walkable(ea.position + offset_p), str(eu.get("group_id", "")))
					if pup != null:
						var pup_u: Dictionary = unit_states[pup.actor_id] as Dictionary
						pup_u["engaged"] = true
						pup_u["target_id"] = ctrl_id
				ea.show_world_bark("嗷——群狼听令，撕碎闯坛者！", 3.5)
				NotifyHub.push_combat_banner("【雾隐狼王】唤出腐木幼狼冲击后排！", "warn", "wood")

			if int(eu.get("phase", 1)) == 1 and hp_pct <= float(edef.get("phase2_hp_ratio", 0.55)):
				eu["phase"] = 2
				eu["ward_current"] = float(eu.get("ward_max", 450.0))
				ea.ward_current = float(eu["ward_current"])
				eu["stagger_timer"] = 0.0
				ea.stagger_timer = 0.0
				ea.show_world_bark(tr("BARK_BOSS_P2"), 4.5)
				NotifyHub.push_combat_banner("【雾隐狼王 · 二阶段狂暴】护体木罡重聚！留好 Q 打断腐木咆哮！", "boss_phase", "wood")

		# 吟唱读条推进
		var cast_spd_mult: float = 0.75 if float(eu.get("atk_slow_timer", 0.0)) > 0.0 else 1.0
		if bool(eu.get("casting", false)):
			var cp: float = float(eu.get("cast_progress", 0.0)) + dt * cast_spd_mult
			var cdur: float = float(eu.get("cast_duration", 2.0))
			eu["cast_progress"] = cp
			ea.is_casting = true
			ea.cast_progress = cp
			ea.cast_duration = cdur
			if cp >= cdur:
				eu["casting"] = false
				ea.is_casting = false
				ea.play_action_anim("cast_release", 0.42)
				_resolve_enemy_cast_finish(eu, ea)
			continue

		# 杀意（Threat Table）目标选择与防抖
		var candidates: Array = _build_ally_threat_candidates(ea.position)
		var threat_res: Dictionary = RtwpSimStep.update_threat_and_pick_target(
			eu.get("threat_table", {}) as Dictionary,
			str(eu.get("target_id", "")),
			str(eu.get("taunt_target_id", "")),
			float(eu.get("taunt_timer", 0.0)),
			candidates,
			ctrl_id
		)
		var tgt_id: String = str(threat_res.get("target_id", ""))
		eu["target_id"] = tgt_id
		ea.nameplate_threat_state = str(threat_res.get("nameplate_state", "jade_safe"))
		var tgt_actor: BattleActor = _find_ally_or_pet_actor(tgt_id)
		if tgt_actor == null:
			continue

		# 检查是否发起敌方危招吟唱（封脉期间不可施法）
		if float(eu.get("lockout_timer", 0.0)) <= 0.0:
			var sk_list: Array = _get_enemy_available_skills(eu)
			for raw_sk: Variant in sk_list:
				var esk_id: String = str(raw_sk)
				if not ecds.has(esk_id):
					var esdef: Dictionary = DataDB.get_skill(esk_id)
					if ea.position.distance_to(tgt_actor.position) <= float(esdef.get("range_px", 260.0)):
						_start_enemy_cast(eu, ea, esk_id, esdef, tgt_actor)
						break
			if bool(eu.get("casting", false)):
				continue

		# 追击与平砍
		eu["attack_timer"] = maxf(0.0, float(eu.get("attack_timer", 0.0)) - dt * cast_spd_mult)
		var dist_t: float = ea.position.distance_to(tgt_actor.position)
		var erange: float = float(eu.get("attack_range_px", 130.0))
		if dist_t > erange:
			var move_mult: float = (1.0 - float(eu.get("slow_pct", 0.0))) if float(eu.get("slow_timer", 0.0)) > 0.0 else 1.0
			var edir: Vector2 = (tgt_actor.position - ea.position).normalized()
			ea.set_facing(edir)
			ea.position = _resolve_move_collision(ea.position, ea.position + edir * float(eu.get("move_speed_px", 190.0)) * move_mult * dt, zone_bounds)
			eu["is_moving"] = true
		elif float(eu.get("attack_timer", 0.0)) <= 0.0:
			eu["attack_timer"] = float(eu.get("attack_interval", 1.85))
			ea.set_facing(tgt_actor.position - ea.position)
			ea.play_action_anim("attack_1", 0.38)
			if sky_vfx != null:
				if erange >= 220.0:
					sky_vfx.spawn_element_bolt(ea.get_vfx_origin_world("cast"), tgt_actor.get_vfx_origin_world("chest"), "miasma", 0.22)
				else:
					var e_style: String = "ink_cyan" if str(eu.get("enemy_def_id", "")) == "rogue_cultivator" else "feral_claw"
					sky_vfx.spawn_slash_arc(ea.get_vfx_origin_world("weapon"), tgt_actor.position - ea.position, e_style, 142.0 if ea.is_boss else 84.0, 0.24, false)
			var raw_hit: int = maxi(4, int(round(float(eu.get("power", 16.0)))))
			_apply_damage_to_ally(tgt_id, tgt_actor, raw_hit, ea.display_name, "利爪重击", str((eu.get("edef", {}) as Dictionary).get("element", "none")), false, false)


func _start_enemy_cast(eu: Dictionary, ea: BattleActor, sk_id: String, sdef: Dictionary, tgt_actor: BattleActor) -> void:
	var ctime: float = maxf(1.2, float(sdef.get("cast_time_sec", 2.0)))
	var intr: bool = bool(sdef.get("interruptible", true))
	var ecds: Dictionary = eu.get("cooldowns", {}) as Dictionary
	var ecd_tots: Dictionary = eu.get("cooldown_totals", {}) as Dictionary
	var c_cd: float = float(sdef.get("cooldown_sec", 9.0))
	ecds[sk_id] = c_cd
	ecd_tots[sk_id] = c_cd

	eu["casting"] = true
	eu["cast_skill_id"] = sk_id
	eu["cast_progress"] = 0.0
	eu["cast_duration"] = ctime
	eu["cast_interruptible"] = intr
	eu["cast_origin"] = tgt_actor.position if str(sdef.get("target_type", "")) == "ground_circle" else ea.position
	eu["cast_dir"] = (tgt_actor.position - ea.position).normalized()
	ea.set_facing(eu["cast_dir"] as Vector2)

	ea.is_casting = true
	ea.cast_skill_name = DataDB.loc(str(sdef.get("name_key", sk_id)))
	ea.cast_progress = 0.0
	ea.cast_duration = ctime
	ea.cast_interruptible = intr

	if sky_vfx != null:
		var c_elem: String = "metal" if str(eu.get("enemy_def_id", "")) == "rogue_cultivator" else "miasma"
		sky_vfx.spawn_qi_ribbon(ea, ea.get_vfx_origin_world("cast"), c_elem, 1.25 if ea.is_boss else 0.88, minf(ctime, 0.85))

	if intr and audio_director != null:
		# Tier S 青铜古钟危招警报，闭眼也能听出按 Q 打断时机！
		audio_director.play_sfx("sfx_boss_cast_chime", AudioDirector.TIER_S)


func _resolve_enemy_cast_finish(eu: Dictionary, ea: BattleActor) -> void:
	var sk_id: String = str(eu.get("cast_skill_id", ""))
	var sdef: Dictionary = DataDB.get_skill(sk_id)
	var ttype: String = str(sdef.get("target_type", "enemy"))
	var coeff: float = float(sdef.get("power_coeff", 1.8))
	var raw_dmg: int = maxi(8, int(round(float(eu.get("power", 18.0)) * coeff)))
	var sname: String = DataDB.loc(str(sdef.get("name_key", sk_id)))
	var elem: String = str(sdef.get("element", "wood"))
	var intr: bool = bool(sdef.get("interruptible", true))
	var add_miasma: bool = bool(sdef.get("apply_miasma", false))

	if audio_director != null:
		audio_director.play_element_sfx(elem, AudioDirector.TIER_A)

	if ttype == "ground_circle":
		var orig: Vector2 = eu.get("cast_origin", ea.position) as Vector2
		var rad: float = float(sdef.get("telegraph_radius_px", 135.0))
		if sky_vfx != null:
			sky_vfx.spawn_shockwave_ring(orig, rad, UIThemeBuilder.COL_CINNABAR_RED, 0.46)
			sky_vfx.spawn_particle_burst(orig, "syn_fire_earth", 20)
		trigger_hitstop(0.080 if ea.is_boss else 0.060, true)
		trigger_camera_shake(10.0 if ea.is_boss else 7.5, 0.24, Vector2(0.0, 1.0))
		for ally: BattleActor in _get_all_living_allies_and_pet():
			if ally.position.distance_to(orig) <= rad:
				_apply_damage_to_ally(ally.actor_id, ally, raw_dmg, ea.display_name, sname, elem, intr, true, add_miasma)

	elif ttype == "ground_cone":
		var orig_c: Vector2 = eu.get("cast_origin", ea.position) as Vector2
		var cdir: Vector2 = (eu.get("cast_dir", Vector2.RIGHT) as Vector2).normalized()
		var rad_c: float = float(sdef.get("telegraph_radius_px", 245.0))
		var half_cos: float = cos(deg_to_rad(float(sdef.get("telegraph_angle_deg", 95.0)) * 0.5))
		if sky_vfx != null:
			sky_vfx.spawn_slash_arc(orig_c + Vector2(0.0, -48.0), cdir, "feral_claw", rad_c * 0.85, 0.32, false)
			sky_vfx.spawn_particle_burst(orig_c + cdir * (rad_c * 0.55), "hit_miasma", 24)
		trigger_hitstop(0.080 if ea.is_boss else 0.060, true)
		trigger_camera_shake(10.0 if ea.is_boss else 7.5, 0.26, cdir)
		for ally2: BattleActor in _get_all_living_allies_and_pet():
			var delta_v: Vector2 = ally2.position - orig_c
			if delta_v.length() <= rad_c and (delta_v.length() < 18.0 or cdir.dot(delta_v.normalized()) >= half_cos):
				_apply_damage_to_ally(ally2.actor_id, ally2, raw_dmg, ea.display_name, sname, elem, intr, true, add_miasma)

	elif ttype == "party_aoe":
		if sky_vfx != null:
			sky_vfx.spawn_shockwave_ring(ea.position, 280.0, UIThemeBuilder.COL_MIASMA_PURPLE, 0.55)
			sky_vfx.spawn_particle_burst(ea.get_vfx_origin_world("mouth"), "hit_miasma", 30)
		trigger_hitstop(0.080, true)
		trigger_camera_shake(9.5, 0.26, Vector2.ZERO)
		for ally3: BattleActor in _get_all_living_allies_and_pet():
			_apply_damage_to_ally(ally3.actor_id, ally3, raw_dmg, ea.display_name, sname, elem, intr, false, add_miasma)

	else:
		var tgt: BattleActor = _find_ally_or_pet_actor(str(eu.get("target_id", "")))
		if tgt != null and tgt.alive:
			if sky_vfx != null:
				if sk_id == "sk_enemy_rogue_ambush":
					sky_vfx.spawn_slash_arc(ea.get_vfx_origin_world("weapon"), tgt.position - ea.position, "ink_cyan", 118.0, 0.25, false)
				else:
					sky_vfx.spawn_element_bolt(ea.get_vfx_origin_world("cast"), tgt.get_vfx_origin_world("chest"), "miasma", 0.20)
			_apply_damage_to_ally(tgt.actor_id, tgt, raw_dmg, ea.display_name, sname, elem, intr, false, add_miasma)


func _perform_party_auto_attack(cid: String, actor: BattleActor, u: Dictionary, tgt_ea: BattleActor) -> void:
	var sheet: Dictionary = u.get("sheet", {}) as Dictionary
	u["attack_timer"] = float(sheet.get("attack_interval", 1.75))
	var flip_aa: bool = not bool(u.get("aa_flip", false))
	u["aa_flip"] = flip_aa
	actor.set_facing(tgt_ea.position - actor.position)
	actor.play_action_anim("attack_2" if flip_aa else "attack_1", 0.35)
	if audio_director != null:
		audio_director.play_sfx("sfx_auto_slash", AudioDirector.TIER_C)

	_spawn_party_auto_attack_vfx(cid, actor, u, tgt_ea, flip_aa)

	var pwr: float = maxf(float(sheet.get("phys_power", 16.0)), float(sheet.get("spell_power", 14.0)) * 0.85)
	_deal_damage_to_enemy(
		cid, actor.position, tgt_ea, pwr, 0.92, "none", 10.0,
		float(sheet.get("crit_pct", 0.05)), float(sheet.get("crit_mult", 1.6)),
		false, 0.0, float(sheet.get("ward_break_mult", 1.0)), float(sheet.get("synergy_dmg_mult", 1.0)),
		false, float(sheet.get("threat_mult", 1.0)), 0.0, ""
	)


func _spawn_party_auto_attack_vfx(cid: String, actor: BattleActor, u: Dictionary, tgt_ea: BattleActor, flip_aa: bool) -> void:
	if sky_vfx == null:
		return
	var sheet: Dictionary = u.get("sheet", {}) as Dictionary
	var wpn_pos: Vector2 = actor.get_vfx_origin_world("weapon")
	var tgt_chest: Vector2 = tgt_ea.get_vfx_origin_world("chest")
	var dir: Vector2 = tgt_ea.position - actor.position
	if cid == "shen_qinghe":
		sky_vfx.spawn_needle_projectile(actor.get_vfx_origin_world("cast"), tgt_chest, "wood", 0.17)
	elif cid == "pei_zhao":
		var m_pei: Dictionary = CampaignState.party_members.get("pei_zhao", {}) as Dictionary
		var is_fire_spec: bool = (str(m_pei.get("active_spec", "spec_a")) == "spec_b")
		sky_vfx.spawn_slash_arc(wpn_pos, dir, "fire_blade" if is_fire_spec else "metal_gold", 102.0, 0.23, flip_aa)
		sky_vfx.spawn_particle_burst(tgt_chest, "hit_fire" if is_fire_spec else "hit_metal", 6)
	else:
		if float(sheet.get("attack_range_px", 145.0)) >= 190.0:
			sky_vfx.spawn_sword_projectile(wpn_pos, tgt_chest, "metal", 0.16, 14.0, 0.88, 0.0, true)
		else:
			sky_vfx.spawn_slash_arc(wpn_pos, dir, "ink_cyan", 98.0, 0.24, flip_aa)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_metal", 6)


func _try_execute_party_skill(cid: String, skill_id: String, target_id: String, is_player_input: bool) -> bool:
	if skill_id == "" or not party_actors.has(cid):
		return false
	var actor: BattleActor = party_actors[cid] as BattleActor
	if not actor.alive:
		return false
	var u: Dictionary = unit_states[cid] as Dictionary
	var sdef: Dictionary = DataDB.get_skill(skill_id)
	if sdef.is_empty():
		return false

	var uses_gcd: bool = bool(sdef.get("uses_gcd", true))
	if uses_gcd and float(u.get("gcd_timer", 0.0)) > 0.0:
		return false
	if bool(u.get("casting", false)) and uses_gcd:
		return false

	var cds: Dictionary = u.get("cooldowns", {}) as Dictionary
	if cds.has(skill_id):
		return false
	if bool(sdef.get("is_blue_stunt", false)):
		var stunt_owner: String = _resolve_blue_stunt_owner_id(cid, skill_id)
		var owner_cds: Dictionary = (unit_states.get(stunt_owner, {}) as Dictionary).get("cooldowns", {}) as Dictionary
		if owner_cds.has(skill_id):
			return false

	var mp_cost: int = int(sdef.get("mp_cost", 0))
	if actor.mp < mp_cost:
		if is_player_input:
			NotifyHub.push_combat_banner("真元不足，可服回元灵丹或平砍回气", "warn", "water")
		return false

	var att_cost: float = float(sdef.get("attunement_cost", 0.0))
	if att_cost > 0.0 and team_attunement < att_cost:
		if is_player_input:
			NotifyHub.push_combat_banner("同调气机未满 %.0f 点！" % att_cost, "warn", "wood")
		return false

	# 敌向技能距离与先手开怪校验
	var ttype: String = str(sdef.get("target_type", "enemy"))
	var resolved_target: String = target_id if target_id != "" else _resolve_skill_target_id(cid, sdef)
	if ttype == "enemy":
		var ea: BattleActor = _find_enemy_actor(resolved_target)
		if ea == null or not ea.alive:
			cycle_tab_enemy_target()
			ea = _find_enemy_actor(locked_enemy_id)
			if ea == null or not ea.alive:
				return false
			resolved_target = ea.actor_id
		var max_r: float = float(sdef.get("range_px", 260.0))
		if actor.position.distance_to(ea.position) > max_r + 32.0:
			if is_player_input:
				# 自动走近射程并入队执行
				actor.move_waypoint = ea.position + (actor.position - ea.position).normalized() * (max_r * 0.85)
				actor.has_move_waypoint = true
				u["queued_skill_id"] = skill_id
				u["queued_target_id"] = resolved_target
			return false
		# 脱战先手远程施法直接开怪并赋【先机】！
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		if not bool(eu.get("engaged", false)):
			_engage_enemy_group(str(eu.get("group_id", "")), cid, true)

	# 扣除资源与启动 GCD
	actor.mp = maxi(0, actor.mp - mp_cost)
	if att_cost > 0.0:
		team_attunement = maxf(0.0, team_attunement - att_cost)

	var sheet: Dictionary = u.get("sheet", {}) as Dictionary
	var eff_haste: float = clampf(float(sheet.get("haste_pct", 0.0)) + party_haste_buff_val + (0.15 if preemptive_buff_timer > 0.0 else 0.0), 0.0, 0.45)
	if uses_gcd:
		var gcd_dur: float = maxf(StatLedger.MIN_GCD_SEC, StatLedger.BASE_GCD_SEC / (1.0 + eff_haste))
		u["gcd_timer"] = gcd_dur
		u["gcd_total"] = gcd_dur

	var base_cast: float = float(sdef.get("cast_time_sec", 0.0))
	if base_cast > 0.0:
		var actual_cast: float = StatLedger.compute_actual_cast_time(base_cast, eff_haste)
		u["casting"] = true
		u["cast_skill_id"] = skill_id
		u["cast_target_id"] = resolved_target
		u["cast_progress"] = 0.0
		u["cast_duration"] = actual_cast
		actor.is_casting = true
		actor.cast_skill_name = DataDB.loc(str(sdef.get("name_key", skill_id)))
		actor.cast_progress = 0.0
		actor.cast_duration = actual_cast
		actor.cast_interruptible = true
		if sky_vfx != null:
			sky_vfx.spawn_qi_ribbon(actor, actor.get_vfx_origin_world("cast"), str(sdef.get("element", "wood")), 0.92, minf(actual_cast, 0.95))
		combat_hud_dirty.emit()
		return true

	_resolve_party_skill_effect(cid, skill_id, resolved_target)
	combat_hud_dirty.emit()
	return true


func _resolve_party_skill_effect(cid: String, skill_id: String, target_id: String) -> void:
	if not party_actors.has(cid):
		return
	var actor: BattleActor = party_actors[cid] as BattleActor
	var u: Dictionary = unit_states[cid] as Dictionary
	var sheet: Dictionary = u.get("sheet", {}) as Dictionary
	var sdef: Dictionary = DataDB.get_skill(skill_id)
	var cd_owner_id: String = _resolve_blue_stunt_owner_id(cid, skill_id) if bool(sdef.get("is_blue_stunt", false)) else cid
	var cd_owner_u: Dictionary = unit_states.get(cd_owner_id, u) as Dictionary
	var cds: Dictionary = cd_owner_u.get("cooldowns", {}) as Dictionary
	var cd_tots: Dictionary = cd_owner_u.get("cooldown_totals", {}) as Dictionary
	var cd_sec: float = float(sdef.get("cooldown_sec", 0.0))
	if cd_sec > 0.0:
		cds[skill_id] = cd_sec
		cd_tots[skill_id] = cd_sec

	var elem: String = str(sdef.get("element", "none"))
	var ttype: String = str(sdef.get("target_type", "enemy"))
	var sname: String = DataDB.loc(str(sdef.get("name_key", skill_id)))
	var att_gain: float = float(sdef.get("attunement_gain", 4.0))
	team_attunement = minf(RtwpSimStep.MAX_ATTUNEMENT, team_attunement + att_gain)

	var is_ctrl: bool = (cid == get_controlled_char_id())
	var sfx_tier: int = AudioDirector.TIER_A if is_ctrl else AudioDirector.TIER_B

	# 双人羁绊合击【青莲引剑】高光演出
	if bool(sdef.get("is_bond_ultimate", false)):
		if audio_director != null:
			audio_director.play_sfx("sfx_bond_ult_qinglian", AudioDirector.TIER_S)
		NotifyHub.push_combat_banner("【双人羁绊合击 · %s】剑莲涤世！" % sname, "ultimate", "wood")
		trigger_hitstop(0.085, true)
		trigger_camera_shake(9.5, 0.28, Vector2.ZERO)

	# 蓝字特技提示
	if bool(sdef.get("is_blue_stunt", false)):
		NotifyHub.push_combat_banner("【古宝蓝字特技 · %s】！" % sname, "stunt", elem)

	if ttype == "ally":
		var ally: BattleActor = _find_ally_or_pet_actor(target_id)
		if ally == null or not ally.alive:
			ally = actor
		actor.play_action_anim("cast_release", 0.35)
		if audio_director != null:
			audio_director.play_sfx("sfx_heal_chime", sfx_tier)
		if sky_vfx != null:
			if ally != actor:
				sky_vfx.spawn_needle_projectile(actor.get_vfx_origin_world("cast"), ally.get_vfx_origin_world("chest"), elem, 0.14)
			sky_vfx.spawn_heal_ribbons(ally, elem, 1.35 if skill_id == "sk_shen_sweet_rain" else 1.0)
		var heal_amt: int = maxi(6, int(round(float(sheet.get("heal_power", 20.0)) * float(sdef.get("heal_coeff", 1.4)))))
		_apply_ally_heal(ally.actor_id, ally, heal_amt, bool(sdef.get("cleanse_debuff", false)), cid)
		if float(sdef.get("hot_duration_sec", 0.0)) > 0.0 and unit_states.has(ally.actor_id):
			var au: Dictionary = unit_states[ally.actor_id] as Dictionary
			au["hot_timer"] = float(sdef.get("hot_duration_sec", 6.0))
			au["hot_hps"] = float(sheet.get("heal_power", 20.0)) * float(sdef.get("hot_coeff", 0.35))
		return

	if ttype == "party" or ttype == "self":
		actor.play_action_anim("cast_release", 0.38)
		if audio_director != null:
			audio_director.play_sfx("sfx_heal_chime", sfx_tier)
		var targets: Array[BattleActor] = [actor] if ttype == "self" else _get_all_living_allies_and_pet()
		var h_coeff: float = float(sdef.get("heal_coeff", 0.0))
		var h_pct: float = float(sdef.get("heal_max_hp_pct", 0.0))
		var sh_coeff: float = float(sdef.get("shield_coeff", 0.0))
		var dr_val: float = float(sdef.get("dr_pct", 0.0))
		var b_dur: float = float(sdef.get("buff_duration_sec", 5.0))
		for t_ally: BattleActor in targets:
			var tu: Dictionary = unit_states.get(t_ally.actor_id, {}) as Dictionary
			var tot_h: int = 0
			if h_coeff > 0.0:
				tot_h += int(round(float(sheet.get("heal_power", 20.0)) * h_coeff))
			if h_pct > 0.0:
				tot_h += int(round(float(t_ally.max_hp) * h_pct))
			if tot_h > 0 or bool(sdef.get("cleanse_debuff", false)):
				_apply_ally_heal(t_ally.actor_id, t_ally, tot_h, bool(sdef.get("cleanse_debuff", false)), cid)
			if sh_coeff > 0.0:
				var add_sh: float = maxf(float(sheet.get("heal_power", 18.0)), float(sheet.get("phys_power", 18.0))) * sh_coeff
				tu["shield"] = float(tu.get("shield", 0.0)) + add_sh
				t_ally.shield = float(tu["shield"])
			if dr_val > 0.0:
				tu["dr_buff_pct"] = dr_val
				tu["dr_buff_timer"] = b_dur
			if sky_vfx != null:
				if ttype == "self":
					sky_vfx.spawn_qi_ribbon(t_ally, t_ally.get_vfx_origin_world("chest"), elem if elem != "none" else "metal", 1.05, 0.65)
				else:
					sky_vfx.spawn_heal_ribbons(t_ally, elem if elem != "none" else "wood", 1.0)
		if sky_vfx != null:
			var wave_r: float = 230.0 if skill_id == "sk_shen_herb_field" else 175.0
			sky_vfx.spawn_shockwave_ring(actor.position, wave_r, UIThemeBuilder.get_element_color(elem), 0.48)
		return

	# ==================== 敌向攻击 / 打断 / 嘲讽 / 范围技 ====================
	var main_ea: BattleActor = _find_enemy_actor(target_id)
	if main_ea == null or not main_ea.alive:
		return

	var pre_dash_pos: Vector2 = actor.position
	if bool(sdef.get("dash_to_melee", false)) and actor.position.distance_to(main_ea.position) > 105.0:
		actor.position = main_ea.position + (actor.position - main_ea.position).normalized() * 88.0

	actor.set_facing(main_ea.position - actor.position)
	actor.play_action_anim("attack_2" if float(sdef.get("aoe_radius_px", 0.0)) > 0.0 else "attack_1", 0.40)

	# 1. 处理嘲讽（Taunt）
	if bool(sdef.get("is_taunt", false)):
		var eu_taunt: Dictionary = unit_states.get(main_ea.actor_id, {}) as Dictionary
		var tbl_t: Dictionary = eu_taunt.get("threat_table", {}) as Dictionary
		var top_t: float = 10.0
		for tv: Variant in tbl_t.values():
			top_t = maxf(top_t, float(tv))
		tbl_t[cid] = top_t + float(sdef.get("flat_threat", 180.0))
		eu_taunt["taunt_target_id"] = cid
		eu_taunt["taunt_timer"] = 3.5
		eu_taunt["target_id"] = cid
		u["shield"] = float(u.get("shield", 0.0)) + float(sheet.get("phys_power", 20.0)) * float(sdef.get("shield_coeff", 1.5))
		u["dr_buff_pct"] = float(sdef.get("dr_pct", 0.22))
		u["dr_buff_timer"] = float(sdef.get("buff_duration_sec", 4.5))
		if sky_vfx != null:
			sky_vfx.spawn_shockwave_ring(actor.position, 155.0, UIThemeBuilder.get_element_color(elem), 0.44)
			sky_vfx.spawn_particle_burst(main_ea.get_vfx_origin_world("chest"), "hit_metal", 10)
		NotifyHub.push_combat_banner("%s【%s】强锁杀意！" % [actor.display_name, sname], "taunt", "earth")
		if audio_director != null:
			audio_director.play_element_sfx("earth", sfx_tier)
		return

	# 2. 处理专属打断技（Q 键）
	if bool(sdef.get("is_interrupt", false)):
		var eu_int: Dictionary = unit_states.get(main_ea.actor_id, {}) as Dictionary
		var int_res: Dictionary = RtwpSimStep.try_interrupt_cast(
			bool(eu_int.get("casting", false)),
			bool(eu_int.get("cast_interruptible", true)),
			float(eu_int.get("ward_max", 0.0)),
			float(eu_int.get("ward_current", 0.0))
		)
		if bool(int_res.get("interrupted", false)):
			eu_int["casting"] = false
			eu_int["lockout_timer"] = float(int_res.get("lockout_sec", 3.0))
			main_ea.is_casting = false
			main_ea.lockout_timer = float(eu_int["lockout_timer"])
			main_ea.trigger_hit_flash(0.16, 1.0)
			trigger_hitstop(0.080, true)
			trigger_camera_shake(7.5, 0.20, (main_ea.position - pre_dash_pos).normalized())
			if sky_vfx != null:
				sky_vfx.spawn_particle_burst(main_ea.get_vfx_origin_world("overhead"), "interrupt_shatter", 22)
			var bonus_wd: float = float(int_res.get("bonus_ward_damage", 0.0))
			if bonus_wd > 0.0:
				_apply_ward_damage_only(eu_int, main_ea, bonus_wd)
			# 青云惊鸿套 3件效果：成功打断后 5 秒削罡 +20%
			if (sheet.get("active_set_effects", []) as Array).has("interrupt_ward_buff_20"):
				u["ward_buff_timer"] = 5.0
			if audio_director != null:
				audio_director.play_sfx("sfx_interrupt_shatter", AudioDirector.TIER_S)
			NotifyHub.push_combat_banner("【打断破功】%s 封脉 3 秒！" % main_ea.display_name, "interrupt", "metal")
		elif str(int_res.get("reason", "")) == "uninterruptible_red":
			NotifyHub.push_combat_banner("暗红锁链危招不可常规打断，速走位或击破护罡！", "warn", "fire")

	# 3. 结算单体或 AoE 命中与五行母印连携
	if not bool(sdef.get("is_bond_ultimate", false)) and audio_director != null:
		audio_director.play_element_sfx(elem, sfx_tier)

	_spawn_party_skill_vfx(cid, actor, skill_id, sdef, main_ea, pre_dash_pos)

	var aoe_r: float = float(sdef.get("aoe_radius_px", 0.0))
	var hit_enemies: Array[BattleActor] = [main_ea]
	if aoe_r > 0.0:
		for other_e: BattleActor in enemy_actors:
			if other_e != main_ea and other_e.alive and other_e.position.distance_to(main_ea.position) <= aoe_r:
				hit_enemies.append(other_e)

	var base_pwr: float = maxf(float(sheet.get("phys_power", 18.0)), float(sheet.get("spell_power", 18.0)))
	var ward_mult_total: float = float(sheet.get("ward_break_mult", 1.0)) * (1.20 if float(u.get("ward_buff_timer", 0.0)) > 0.0 else 1.0)
	var merge_tag: String = ("%s_%d" % [skill_id, int(combat_clock_sec * 10.0)]) if hit_enemies.size() > 1 else ""

	for hit_e: BattleActor in hit_enemies:
		_deal_damage_to_enemy(
			cid, actor.position, hit_e, base_pwr, float(sdef.get("power_coeff", 1.2)),
			elem, float(sdef.get("ward_damage", 24.0)),
			float(sheet.get("crit_pct", 0.05)), float(sheet.get("crit_mult", 1.6)),
			false, 0.0, ward_mult_total, float(sheet.get("synergy_dmg_mult", 1.0)),
			bool(sdef.get("applies_mother_seal", false)),
			float(sheet.get("threat_mult", 1.0)), float(sdef.get("flat_threat", 0.0)),
			merge_tag, sdef
		)

	# 合击附带全队回血护盾与净化
	if float(sdef.get("party_heal_coeff", 0.0)) > 0.0:
		var p_heal: int = int(round(base_pwr * float(sdef.get("party_heal_coeff", 1.5))))
		var p_sh: float = base_pwr * float(sdef.get("party_shield_coeff", 1.0))
		for ally_u: BattleActor in _get_all_living_allies_and_pet():
			_apply_ally_heal(ally_u.actor_id, ally_u, p_heal, true, cid)
			if sky_vfx != null:
				sky_vfx.spawn_heal_ribbons(ally_u, "wood", 1.15)
			if p_sh > 0.0 and unit_states.has(ally_u.actor_id):
				var au2: Dictionary = unit_states[ally_u.actor_id] as Dictionary
				au2["shield"] = float(au2.get("shield", 0.0)) + p_sh
				ally_u.shield = float(au2["shield"])


func _spawn_party_skill_vfx(
	cid: String,
	actor: BattleActor,
	skill_id: String,
	sdef: Dictionary,
	main_ea: BattleActor,
	pre_dash_pos: Vector2
) -> void:
	if sky_vfx == null:
		return
	var elem: String = str(sdef.get("element", "metal"))
	var wpn: Vector2 = actor.get_vfx_origin_world("weapon")
	var cast_p: Vector2 = actor.get_vfx_origin_world("cast")
	var tgt_chest: Vector2 = main_ea.get_vfx_origin_world("chest")
	var dir: Vector2 = main_ea.position - actor.position
	var aoe_r: float = float(sdef.get("aoe_radius_px", 0.0))

	match skill_id:
		"ult_qinglian_sword":
			sky_vfx.spawn_shockwave_ring(main_ea.position, 240.0, UIThemeBuilder.COL_JADE_GREEN, 0.68)
			for i: int in range(6):
				var ang: float = -PI * 0.65 + float(i) * (PI * 0.26)
				var start_p: Vector2 = tgt_chest + Vector2(cos(ang) * 210.0, sin(ang) * 140.0 - 95.0)
				sky_vfx.spawn_sword_projectile(start_p, tgt_chest, "wood" if i % 2 == 0 else "metal", 0.18, 8.0, 1.12, float(i) * 0.035, i == 5)
			sky_vfx.spawn_particle_burst(tgt_chest, "bond_qinglian", 36)
		"sk_gu_sword_box_burst":
			var elems_5: Array[String] = ["metal", "fire", "water", "wood", "earth"]
			for i2: int in range(5):
				var off_v: Vector2 = Vector2(-36.0 + float(i2) * 18.0, -78.0 - float(i2 % 2) * 22.0)
				sky_vfx.spawn_sword_projectile(actor.position + off_v, tgt_chest, elems_5[i2], 0.17, 26.0, 1.0, float(i2) * 0.035, i2 == 4)
			sky_vfx.spawn_shockwave_ring(main_ea.position, 175.0, UIThemeBuilder.COL_BRONZE_GOLD, 0.50)
			sky_vfx.spawn_particle_burst(tgt_chest, "syn_earth_metal", 26)
		"sk_pei_starfall_sword":
			for i3: int in range(6):
				var sx: float = -80.0 + float(i3) * 32.0
				sky_vfx.spawn_sword_projectile(main_ea.position + Vector2(sx, -310.0), tgt_chest + Vector2(sx * 0.25, 0.0), "metal", 0.16, 4.0, 1.05, float(i3) * 0.03, i3 == 5)
			sky_vfx.spawn_shockwave_ring(main_ea.position, 155.0, UIThemeBuilder.COL_BRONZE_GOLD, 0.48)
		"sk_pei_prairie_array":
			for i4: int in range(4):
				var fx_x: float = -66.0 + float(i4) * 44.0
				sky_vfx.spawn_sword_projectile(main_ea.position + Vector2(fx_x, -260.0), tgt_chest, "fire", 0.16, 4.0, 1.02, float(i4) * 0.035, i4 == 3)
			sky_vfx.spawn_shockwave_ring(main_ea.position, 165.0, UIThemeBuilder.COL_CINNABAR_RED, 0.50)
			sky_vfx.spawn_particle_burst(tgt_chest, "syn_wood_fire", 26)
		"sk_gu_gale_blades":
			for i5: int in range(3):
				sky_vfx.spawn_sword_projectile(cast_p, tgt_chest, "wood", 0.16, 20.0 - float(i5) * 8.0, 0.92, float(i5) * 0.04, false)
			sky_vfx.spawn_slash_arc(tgt_chest, dir, "wood_gale", 136.0, 0.28, false)
			sky_vfx.spawn_slash_arc(tgt_chest, -dir, "wood_gale", 128.0, 0.28, true, 0.05)
			sky_vfx.spawn_shockwave_ring(main_ea.position, 150.0, UIThemeBuilder.COL_JADE_GREEN, 0.46)
		"sk_pei_flash_flurry":
			sky_vfx.spawn_slash_arc(wpn, dir, "metal_gold", 108.0, 0.22, false, 0.0)
			sky_vfx.spawn_slash_arc(wpn, dir.rotated(0.28), "ink_cyan", 112.0, 0.22, true, 0.05)
			sky_vfx.spawn_slash_arc(wpn, dir.rotated(-0.24), "metal_gold", 118.0, 0.24, false, 0.10)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_metal", 14)
		"sk_gu_metal_rend":
			sky_vfx.spawn_slash_arc(wpn, dir, "metal_gold", 114.0, 0.24, false, 0.0)
			sky_vfx.spawn_slash_arc(wpn, dir, "ink_cyan", 114.0, 0.24, true, 0.05)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_metal", 14)
		"sk_gu_earth_cleave":
			sky_vfx.spawn_slash_arc(wpn, dir, "earth_heavy", 128.0, 0.28, false)
			sky_vfx.spawn_shockwave_ring(main_ea.position, 105.0, UIThemeBuilder.COL_EARTH_AMBER, 0.40)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_earth", 14)
		"sk_gu_searing_sweep", "sk_pei_sun_flare", "sk_pei_blaze_slash", "sk_pei_crimson_whirl":
			sky_vfx.spawn_slash_arc(wpn, dir, "fire_blade", 138.0 if aoe_r > 0.0 else 118.0, 0.28, false)
			if skill_id == "sk_pei_crimson_whirl":
				sky_vfx.spawn_slash_arc(wpn, -dir, "fire_blade", 132.0, 0.28, true, 0.04)
			if aoe_r > 0.0:
				sky_vfx.spawn_shockwave_ring(main_ea.position, aoe_r, UIThemeBuilder.COL_CINNABAR_RED, 0.44)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_fire", 16)
		"stunt_poxue_assault":
			sky_vfx.spawn_slash_arc(wpn, dir, "fire_blade", 126.0, 0.25, false, 0.0)
			sky_vfx.spawn_slash_arc(wpn, dir, "metal_gold", 126.0, 0.25, true, 0.06)
			sky_vfx.spawn_particle_burst(tgt_chest, "syn_earth_metal", 20)
		"sk_gu_throat_seal", "sk_pei_sword_interrupt":
			sky_vfx.spawn_sword_projectile(pre_dash_pos + Vector2(0.0, -52.0), tgt_chest, "metal", 0.11, 4.0, 1.0, 0.0, true)
		"sk_shen_needle_seal":
			sky_vfx.spawn_needle_projectile(cast_p, tgt_chest, "metal", 0.10)
		"sk_shen_vine_bind", "sk_shen_leech_briar":
			sky_vfx.spawn_needle_projectile(cast_p, tgt_chest, "wood", 0.15)
			sky_vfx.spawn_qi_ribbon(main_ea, tgt_chest, "wood", 1.05, 0.65)
			if aoe_r > 0.0:
				sky_vfx.spawn_shockwave_ring(main_ea.position, aoe_r, UIThemeBuilder.COL_JADE_GREEN, 0.44)
			sky_vfx.spawn_particle_burst(tgt_chest, "hit_wood", 14)
		_:
			if cid == "shen_qinghe":
				sky_vfx.spawn_needle_projectile(cast_p, tgt_chest, elem, 0.16)
			elif float(sdef.get("range_px", 165.0)) >= 220.0:
				sky_vfx.spawn_sword_projectile(cast_p, tgt_chest, elem, 0.17, 16.0, 1.15 if skill_id == "sk_pei_sky_pierce" else 0.96, 0.0, true)
			else:
				var st_fb: String = "fire_blade" if elem == "fire" else ("metal_gold" if cid == "pei_zhao" else "ink_cyan")
				sky_vfx.spawn_slash_arc(wpn, dir, st_fb, 114.0, 0.25, false)
			if aoe_r > 0.0:
				sky_vfx.spawn_shockwave_ring(main_ea.position, aoe_r, UIThemeBuilder.get_element_color(elem), 0.42)


func _execute_pet_skill(pu: Dictionary, sdef: Dictionary) -> void:
	if sdef.is_empty() or pet_actor == null:
		return
	var sk_id: String = str(sdef.get("id", ""))
	var cds: Dictionary = pu.get("cooldowns", {}) as Dictionary
	var cd_tots: Dictionary = pu.get("cooldown_totals", {}) as Dictionary
	if cds.has(sk_id):
		return
	var p_cd: float = float(sdef.get("cooldown_sec", 10.0))
	cds[sk_id] = p_cd
	cd_tots[sk_id] = p_cd
	var elem: String = str(sdef.get("element", "fire"))
	var sname: String = DataDB.loc(str(sdef.get("name_key", sk_id)))

	if float(sdef.get("party_haste_bonus", 0.0)) > 0.0:
		party_haste_buff_val = float(sdef.get("party_haste_bonus", 0.14))
		party_haste_buff_timer = float(sdef.get("buff_duration_sec", 6.0))
		team_attunement = minf(RtwpSimStep.MAX_ATTUNEMENT, team_attunement + float(sdef.get("attunement_gain", 12.0)))
		if sky_vfx != null:
			sky_vfx.spawn_shockwave_ring(pet_actor.position, 145.0, UIThemeBuilder.COL_JADE_GREEN, 0.42)
			for ally_h: BattleActor in _get_all_living_allies_and_pet():
				sky_vfx.spawn_qi_ribbon(ally_h, ally_h.get_vfx_origin_world("chest"), "wood", 0.80, 0.55)
		NotifyHub.push_combat_banner("%s【%s】全队急速 +14%%！" % [pet_actor.display_name, sname], "pet", "wood")
		if audio_director != null:
			audio_director.play_element_sfx("wood", AudioDirector.TIER_B)
		return

	if float(sdef.get("loyal_guard_share_pct", 0.0)) > 0.0:
		loyal_guard_share = float(sdef.get("loyal_guard_share_pct", 0.50))
		loyal_guard_timer = float(sdef.get("buff_duration_sec", 8.0))
		var sh_val: float = float(pu.get("power", 16.0)) * float(sdef.get("shield_coeff", 1.8))
		for ally: BattleActor in _get_all_living_allies_and_pet():
			if unit_states.has(ally.actor_id):
				var au: Dictionary = unit_states[ally.actor_id] as Dictionary
				au["shield"] = float(au.get("shield", 0.0)) + sh_val
				ally.shield = float(au["shield"])
			if sky_vfx != null:
				sky_vfx.spawn_qi_ribbon(ally, ally.get_vfx_origin_world("chest"), "water", 0.82, 0.60)
		if sky_vfx != null:
			sky_vfx.spawn_shockwave_ring(pet_actor.position, 150.0, UIThemeBuilder.COL_WATER_BLUE, 0.45)
		NotifyHub.push_combat_banner("%s【%s】替队友分担五成重伤！" % [pet_actor.display_name, sname], "pet", "water")
		if audio_director != null:
			audio_director.play_element_sfx("water", AudioDirector.TIER_B)
		return

	var tgt_e: BattleActor = _pick_ai_enemy_target(pet_actor.position)
	if tgt_e == null:
		return
	if not in_combat:
		var eu0: Dictionary = unit_states.get(tgt_e.actor_id, {}) as Dictionary
		_engage_enemy_group(str(eu0.get("group_id", "")), get_controlled_char_id(), true)

	pet_actor.play_action_anim("attack_2", 0.40)
	if audio_director != null:
		audio_director.play_element_sfx(elem, AudioDirector.TIER_B)
	var aoe_r: float = float(sdef.get("aoe_radius_px", 125.0))
	if sky_vfx != null:
		sky_vfx.spawn_element_bolt(pet_actor.get_vfx_origin_world("mouth"), tgt_e.get_vfx_origin_world("chest"), elem, 0.18)
		sky_vfx.spawn_shockwave_ring(tgt_e.position, aoe_r, UIThemeBuilder.get_element_color(elem), 0.44)
		sky_vfx.spawn_particle_burst(tgt_e.get_vfx_origin_world("chest"), "hit_fire" if elem == "fire" else "hit_water", 18)
	for ea: BattleActor in enemy_actors:
		if ea.alive and ea.position.distance_to(tgt_e.position) <= aoe_r:
			_deal_damage_to_enemy(
				pet_actor.actor_id, pet_actor.position, ea, float(pu.get("power", 20.0)),
				float(sdef.get("power_coeff", 1.4)), elem, float(sdef.get("ward_damage", 30.0)),
				0.10, 1.55, false, 0.0, 1.0, 1.0, bool(sdef.get("applies_mother_seal", true)),
				float(pu.get("threat_mult", 1.0)), 0.0, sk_id
			)
	if float(sdef.get("party_heal_coeff", 0.0)) > 0.0:
		var ph: int = int(round(float(pu.get("power", 16.0)) * float(sdef.get("party_heal_coeff", 0.85))))
		for ally2: BattleActor in _get_all_living_allies_and_pet():
			_apply_ally_heal(ally2.actor_id, ally2, ph, false)
			if sky_vfx != null:
				sky_vfx.spawn_heal_ribbons(ally2, "water", 0.85)


func _deal_damage_to_enemy(
	attacker_id: String,
	_attacker_pos: Vector2,
	ea: BattleActor,
	raw_power: float,
	coeff: float,
	elem: String,
	ward_dmg: float,
	crit_pct: float,
	crit_mult: float,
	force_crit: bool,
	ignore_armor: float,
	mastery_ward_mult: float,
	synergy_mult: float,
	applies_seal: bool,
	threat_mult: float,
	flat_threat: float,
	merge_tag: String,
	sdef: Dictionary = {}
) -> void:
	if not ea.alive or not unit_states.has(ea.actor_id):
		return
	var eu: Dictionary = unit_states[ea.actor_id] as Dictionary
	if not bool(eu.get("engaged", false)):
		_engage_enemy_group(str(eu.get("group_id", "")), attacker_id, true)

	# 阵法相克加成修正
	var form_counter: Dictionary = FormationRules.evaluate_counter(CampaignState.active_formation_id, str(eu.get("formation_id", "scatter")))
	var adj_power: float = raw_power * float(form_counter.get("damage_mult", 1.0))

	# 先检查【土生金·淬锋】是否触发必暴无视护甲
	var pre_syn: Dictionary = RtwpSimStep.resolve_elemental_synergy(
		str(eu.get("mother_seal_element", "")),
		float(eu.get("mother_seal_timer", 0.0)),
		elem,
		applies_seal,
		adj_power,
		synergy_mult
	)
	var syn_id: String = str(pre_syn.get("synergy_id", ""))
	if syn_id == "earth_metal":
		force_crit = true
		ignore_armor = 0.40

	var target_snapshot: Dictionary = {
		"ward_current": float(eu.get("ward_current", 0.0)),
		"ward_max": float(eu.get("ward_max", 0.0)),
		"ward_element": str(eu.get("ward_element", "none")),
		"stagger_timer": float(eu.get("stagger_timer", 0.0)),
		"damage_taken_mult": float(eu.get("damage_taken_mult", 1.0)),
		"shield_current": float(eu.get("shield", 0.0)),
	}
	var outcome: Dictionary = RtwpSimStep.compute_hit_outcome(
		adj_power, coeff, elem, ward_dmg, crit_pct, crit_mult, force_crit, ignore_armor,
		mastery_ward_mult, preemptive_buff_timer > 0.0, target_snapshot, _rng.randf()
	)
	preemptive_buff_timer = 0.0 if preemptive_buff_timer > 0.0 and ward_dmg > 15.0 else preemptive_buff_timer

	var hp_dmg: int = int(outcome.get("hp_damage", 1))
	eu["shield"] = float(outcome.get("remaining_shield", 0.0))
	eu["ward_current"] = float(outcome.get("new_ward", 0.0))
	ea.ward_current = float(eu["ward_current"])

	_apply_direct_enemy_hp_loss(eu, ea, hp_dmg, elem, bool(outcome.get("is_crit", false)), merge_tag)
	RtwpSimStep.add_damage_threat(eu.get("threat_table", {}) as Dictionary, attacker_id, hp_dmg, threat_mult, flat_threat)

	# 附加减速 / 持续伤害
	if float(sdef.get("slow_duration_sec", 0.0)) > 0.0:
		eu["slow_pct"] = float(sdef.get("slow_pct", 0.30))
		eu["slow_timer"] = float(sdef.get("slow_duration_sec", 4.0))
	if float(sdef.get("dot_duration_sec", 0.0)) > 0.0:
		eu["dot_timer"] = float(sdef.get("dot_duration_sec", 4.0))
		eu["dot_dps"] = adj_power * float(sdef.get("dot_dps_coeff", 0.25))
		eu["dot_leech_pct"] = float(sdef.get("leech_party_heal_pct", 0.0))

	# 结算护体灵罡击碎 -> 6 秒【气机破绽】！
	if bool(outcome.get("ward_broken_now", false)):
		_trigger_enemy_ward_stagger(eu, ea)

	# 结算【五行母印】更新或【五行相生连携】大爆发！
	eu["mother_seal_element"] = str(pre_syn.get("new_seal_element", ""))
	eu["mother_seal_timer"] = float(pre_syn.get("new_seal_timer", 0.0))
	ea.mother_seal_element = str(eu["mother_seal_element"])
	ea.mother_seal_timer = float(eu["mother_seal_timer"])

	if bool(pre_syn.get("triggered", false)):
		_execute_synergy_detonation(attacker_id, eu, ea, pre_syn)


func _apply_ward_damage_only(eu: Dictionary, ea: BattleActor, bonus_ward_loss: float) -> void:
	if float(eu.get("ward_current", 0.0)) <= 0.0:
		return
	eu["ward_current"] = maxf(0.0, float(eu["ward_current"]) - bonus_ward_loss)
	ea.ward_current = float(eu["ward_current"])
	if float(eu["ward_current"]) <= 0.0:
		_trigger_enemy_ward_stagger(eu, ea)


func _trigger_enemy_ward_stagger(eu: Dictionary, ea: BattleActor) -> void:
	eu["casting"] = false
	ea.is_casting = false
	eu["stagger_timer"] = RtwpSimStep.STAGGER_DURATION_SEC
	eu["stun_timer"] = RtwpSimStep.STAGGER_STUN_SEC
	ea.stagger_timer = RtwpSimStep.STAGGER_DURATION_SEC
	ea.trigger_hit_flash(0.22 if ea.is_boss else 0.18, 1.0)
	trigger_hitstop(0.115 if ea.is_boss else 0.085, true)
	trigger_camera_shake(12.5 if ea.is_boss else 8.5, 0.30 if ea.is_boss else 0.22, Vector2.ZERO)
	if audio_director != null:
		audio_director.play_sfx("sfx_ward_break_thunder", AudioDirector.TIER_S)
	if sky_vfx != null:
		sky_vfx.spawn_shockwave_ring(ea.position, 185.0, UIThemeBuilder.COL_BRONZE_GOLD, 0.55)
		sky_vfx.spawn_particle_burst(ea.get_vfx_origin_world("chest"), "ward_break", 30)
	NotifyHub.push_combat_banner("【破罡重创】%s 陷入 6 秒气机破绽（承伤+35%%）！" % ea.display_name, "ward_break", "metal")


func _execute_synergy_detonation(attacker_id: String, eu: Dictionary, ea: BattleActor, syn_res: Dictionary) -> void:
	var syn_id: String = str(syn_res.get("synergy_id", ""))
	var bonus_dmg: int = maxi(8, int(round(float(syn_res.get("bonus_damage", 24.0)))))
	team_attunement = minf(RtwpSimStep.MAX_ATTUNEMENT, team_attunement + float(syn_res.get("attunement_gain", 15.0)))

	ea.trigger_hit_flash(0.16, 1.0)
	trigger_hitstop(0.080, true)
	trigger_camera_shake(8.0, 0.22, Vector2.ZERO)

	if audio_director != null:
		audio_director.play_sfx("sfx_synergy_burst", AudioDirector.TIER_A)
	NotifyHub.push_combat_banner(tr(str(syn_res.get("title_key", "SYN_WOOD_FIRE"))), "synergy", syn_id)

	var tank_actor: BattleActor = null
	for cid_t_var: Variant in party_actors.keys():
		var cid_t: String = str(cid_t_var)
		var pu_t: Dictionary = unit_states.get(cid_t, {}) as Dictionary
		var pa_t: BattleActor = party_actors[cid_t] as BattleActor
		if pa_t.alive and bool(pu_t.get("is_tank_role", false)):
			tank_actor = pa_t
			break
	if tank_actor == null:
		tank_actor = get_controlled_actor()

	if sky_vfx != null:
		sky_vfx.spawn_synergy_burst(ea.position, syn_id, tank_actor, party_actors.get(attacker_id, null) as BattleActor)

	# 青岚行者套 3件套回真元
	if party_actors.has(attacker_id):
		var au: Dictionary = unit_states[attacker_id] as Dictionary
		var sh: Dictionary = au.get("sheet", {}) as Dictionary
		if (sh.get("active_set_effects", []) as Array).has("synergy_restore_mp_8"):
			var pa: BattleActor = party_actors[attacker_id] as BattleActor
			pa.mp = mini(pa.max_mp, pa.mp + 8)

	match syn_id:
		"wood_fire":
			for other_e: BattleActor in enemy_actors:
				if other_e.alive and other_e.position.distance_to(ea.position) <= 165.0:
					var oeu: Dictionary = unit_states[other_e.actor_id] as Dictionary
					_apply_direct_enemy_hp_loss(oeu, other_e, bonus_dmg, "fire", true, "syn_wf")
					oeu["dot_timer"] = 4.0
					oeu["dot_dps"] = float(bonus_dmg) * 0.22
		"fire_earth":
			eu["slow_pct"] = 0.40
			eu["slow_timer"] = 5.0
			_apply_direct_enemy_hp_loss(eu, ea, int(round(float(bonus_dmg) * 0.85)), "earth", false, "")
			# 为当前主坦附加岩石护盾
			for cid_var: Variant in party_actors.keys():
				var cid: String = str(cid_var)
				var pu: Dictionary = unit_states[cid] as Dictionary
				if bool(pu.get("is_tank_role", false)):
					pu["shield"] = float(pu.get("shield", 0.0)) + float(bonus_dmg) * 1.15
		"earth_metal":
			_apply_ward_damage_only(eu, ea, 45.0)
			_apply_direct_enemy_hp_loss(eu, ea, bonus_dmg, "metal", true, "")
		"metal_water":
			eu["atk_slow_timer"] = 5.0
			_apply_direct_enemy_hp_loss(eu, ea, int(round(float(bonus_dmg) * 0.9)), "water", false, "")
			if party_actors.has(attacker_id):
				var pa2: BattleActor = party_actors[attacker_id] as BattleActor
				pa2.mp = mini(pa2.max_mp, pa2.mp + maxi(6, int(round(float(pa2.max_mp) * 0.08))))
		"water_wood":
			var heal_v: int = maxi(12, int(round(float(bonus_dmg) * 0.95)))
			_heal_lowest_party_member(heal_v, true)
			_heal_lowest_party_member(int(round(float(heal_v) * 0.75)), true)


func _apply_direct_enemy_hp_loss(
	eu: Dictionary,
	ea: BattleActor,
	dmg: int,
	elem: String,
	is_crit: bool = false,
	merge_tag: String = "",
	is_dot: bool = false
) -> void:
	if not ea.alive or dmg <= 0:
		return
	var next_hp: int = maxi(0, int(eu.get("hp", ea.hp)) - dmg)
	eu["hp"] = next_hp
	ea.hp = next_hp
	ea.trigger_hit_flash(0.07 if is_dot else (0.14 if is_crit else 0.11), 0.35 if is_dot else (1.0 if is_crit else 0.82))
	if is_crit and not is_dot:
		trigger_hitstop(0.045, false)
		trigger_camera_shake(4.5, 0.14, Vector2.ZERO)
	if not is_dot and not bool(eu.get("casting", false)):
		ea.play_action_anim("hit", 0.20)
	NotifyHub.push_combat_number(ea.position + Vector2(0.0, -110.0), dmg, false, is_crit, elem, merge_tag)

	if next_hp <= 0:
		ea.alive = false
		ea.is_targeted = false
		ea.is_hovered = false
		eu["engaged"] = false
		eu["casting"] = false
		ea.is_casting = false
		_grant_enemy_drops(eu, ea)
		if ea.actor_id == locked_enemy_id:
			set_locked_enemy("", false)
			if in_combat:
				cycle_tab_enemy_target()


func _grant_enemy_drops(eu: Dictionary, _ea: BattleActor) -> void:
	var edef: Dictionary = eu.get("edef", {}) as Dictionary
	var stones: int = int(edef.get("drop_stones", 0))
	if stones > 0:
		CampaignState.add_spirit_stones(stones, false)
	var drops: Array = edef.get("drop_items", []) as Array
	for raw_d: Variant in drops:
		if raw_d is Dictionary:
			var d: Dictionary = raw_d as Dictionary
			if _rng.randf() <= float(d.get("chance", 0.5)):
				CampaignState.add_item(str(d.get("id", "")), 1, false)


func _apply_damage_to_ally(
	uid: String,
	actor: BattleActor,
	raw_enemy_damage: int,
	source_name: String,
	skill_name: String,
	elem: String,
	was_interruptible: bool,
	was_telegraph: bool,
	add_miasma: bool = false
) -> void:
	if not actor.alive or not unit_states.has(uid):
		return
	var u: Dictionary = unit_states[uid] as Dictionary
	var taken_mult: float = 0.80
	if u.get("faction", "party") == "party":
		var sh: Dictionary = u.get("sheet", {}) as Dictionary
		taken_mult = float(sh.get("damage_taken_mult", 0.85))
		if float(u.get("dr_buff_timer", 0.0)) > 0.0:
			taken_mult *= (1.0 - float(u.get("dr_buff_pct", 0.0)))

	var final_dmg: float = maxf(1.0, float(raw_enemy_damage) * taken_mult)

	# 玄甲灵龟【忠心护主】分担 50% 伤害
	if loyal_guard_timer > 0.0 and pet_actor != null and pet_actor.alive and actor != pet_actor:
		var shared: int = int(round(final_dmg * loyal_guard_share))
		final_dmg -= float(shared)
		pet_actor.hp = maxi(0, pet_actor.hp - shared)
		if pet_actor.hp <= 0:
			pet_actor.alive = false
			NotifyHub.push_combat_banner("灵宠【%s】护主力竭退场！" % pet_actor.display_name, "warn", "water")

	var cur_sh: float = float(u.get("shield", 0.0))
	var absorbed: float = minf(cur_sh, final_dmg)
	u["shield"] = maxf(0.0, cur_sh - absorbed)
	actor.shield = float(u["shield"])
	var hp_loss: int = int(round(maxf(0.0, final_dmg - absorbed)))

	if add_miasma and u.get("faction", "") == "party" and float(u.get("miasma_immune_timer", 0.0)) <= 0.0:
		u["miasma_stacks"] = mini(4, int(u.get("miasma_stacks", 0)) + 1)
		actor.miasma_stacks = int(u["miasma_stacks"])

	if hp_loss > 0:
		actor.hp = maxi(0, actor.hp - hp_loss)
		var is_miasma_tick: bool = (skill_name == "腐瘴侵脉")
		actor.trigger_hit_flash(0.08 if is_miasma_tick else 0.12, 0.40 if is_miasma_tick else 0.90)
		if not is_miasma_tick and not bool(u.get("casting", false)):
			actor.play_action_anim("hit", 0.22)
		if was_telegraph and actor.is_controlled:
			trigger_camera_shake(6.5, 0.18, Vector2.ZERO)
		NotifyHub.push_combat_number(actor.position + Vector2(0.0, -108.0), hp_loss, false, false, elem)
		RtwpSimStep.record_damage_event(
			death_ring_buffer, combat_clock_sec, source_name, skill_name, elem,
			hp_loss, was_interruptible, was_telegraph, actor.display_name
		)
		if actor.hp <= 0:
			actor.alive = false
			u["casting"] = false
			actor.is_casting = false
			if u.get("faction", "") == "party":
				NotifyHub.push_combat_banner("%s 重伤倒地！" % actor.display_name, "warn", "fire")

	combat_hud_dirty.emit()


func _apply_ally_heal(uid: String, actor: BattleActor, heal_amount: int, cleanse: bool, healer_id: String = "") -> void:
	if not actor.alive or not unit_states.has(uid):
		return
	var u: Dictionary = unit_states[uid] as Dictionary
	if cleanse and u.get("faction", "") == "party":
		u["miasma_stacks"] = 0
		actor.miasma_stacks = 0
	if heal_amount <= 0:
		return
	var missing: int = maxi(0, actor.max_hp - actor.hp)
	var eff_heal: int = mini(missing, heal_amount)
	var overheal: int = maxi(0, heal_amount - missing)
	actor.hp = mini(actor.max_hp, actor.hp + heal_amount)
	NotifyHub.push_combat_number(actor.position + Vector2(0.0, -112.0), heal_amount, true, false, "wood")

	# 药庐长生套 3件效果：过量治疗 50% 转木灵护盾！
	if overheal > 2 and healer_id != "" and unit_states.has(healer_id):
		var hu: Dictionary = unit_states[healer_id] as Dictionary
		var hsh: Dictionary = hu.get("sheet", {}) as Dictionary
		if (hsh.get("active_set_effects", []) as Array).has("overheal_wood_shield_50"):
			u["shield"] = minf(float(actor.max_hp) * 0.45, float(u.get("shield", 0.0)) + float(overheal) * 0.50)
			actor.shield = float(u["shield"])

	# 治疗杀意均摊计入当前交战敌人杀意表
	if eff_heal > 0 and healer_id != "" and unit_states.has(healer_id):
		var hu2: Dictionary = unit_states[healer_id] as Dictionary
		var h_mult: float = float((hu2.get("sheet", {}) as Dictionary).get("threat_mult", 0.85))
		var engaged_tables: Array = []
		for ea: BattleActor in enemy_actors:
			if ea.alive:
				var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
				if bool(eu.get("engaged", false)):
					engaged_tables.append(eu.get("threat_table", {}))
		RtwpSimStep.add_heal_threat_split(engaged_tables, healer_id, eff_heal, h_mult)


func _use_instant_combat_pill(cid: String, pill_id: String) -> void:
	if pill_id == "" or CampaignState.get_item_count(pill_id) <= 0:
		NotifyHub.push_combat_banner("快捷丹符槽已空！", "warn", "none")
		return
	var idef: Dictionary = DataDB.get_any_item_or_equip(pill_id)
	if str(idef.get("category", "")) == "talisman":
		activate_stealth_talisman()
		return
	if pill_cooldown_timer > 0.0:
		NotifyHub.push_combat_banner("丹毒调息中（剩余 %.1fs）" % pill_cooldown_timer, "warn", "wood")
		return
	if str(idef.get("category", "")) != "instant_pill":
		return
	var target_id: String = hovered_ally_id if hovered_ally_id != "" else cid
	var target_actor: BattleActor = party_actors.get(target_id, party_actors.get(cid, null)) as BattleActor
	if target_actor == null or not target_actor.alive:
		return

	CampaignState.remove_item(pill_id, 1)
	pill_cooldown_timer = RtwpSimStep.PILL_TOXICITY_COOLDOWN_SEC
	pill_cooldown_total = RtwpSimStep.PILL_TOXICITY_COOLDOWN_SEC
	var heal_amt: int = maxi(15, int(round(float(target_actor.max_hp) * float(idef.get("heal_hp_pct", 0.35)))))
	_apply_ally_heal(target_actor.actor_id, target_actor, heal_amt, bool(idef.get("cleanse_miasma", false)), cid)
	if sky_vfx != null:
		sky_vfx.spawn_heal_ribbons(target_actor, "wood", 0.85)
	var imm: float = float(idef.get("miasma_immune_sec", 0.0))
	if imm > 0.0 and unit_states.has(target_actor.actor_id):
		(unit_states[target_actor.actor_id] as Dictionary)["miasma_immune_timer"] = imm
	if audio_director != null:
		audio_director.play_sfx("sfx_pill_drink", AudioDirector.TIER_A)
	NotifyHub.push_combat_banner("%s 服下【%s】！" % [target_actor.display_name, DataDB.loc(str(idef.get("name_key", pill_id)))], "pill", "wood")
	combat_hud_dirty.emit()


func _check_combat_resolution() -> void:
	if not in_combat:
		return

	# 1. 检测我方是否全灭 -> 弹出【问道败北复盘卷轴】
	var any_party_alive: bool = false
	for cid_var: Variant in party_actors.keys():
		var pa: BattleActor = party_actors[str(cid_var)] as BattleActor
		if pa.alive:
			any_party_alive = true
			break

	if not any_party_alive:
		in_combat = false
		tactical_paused = false
		_hitstop_timer = 0.0
		_shake_timer = minf(_shake_timer, 0.10)
		InputRouter.combat_engaged = false
		NotifyHub.set_combat_active(false)
		if audio_director != null:
			audio_director.set_tactical_pause_filter(false)
			audio_director.set_combat_engaged(false)
		var unused_pills: int = CampaignState.get_item_count(CampaignState.quick_pill_5_id) + CampaignState.get_item_count(CampaignState.quick_pill_6_id)
		var stunt_id: String = _find_party_blue_stunt_id()
		var stunt_name: String = DataDB.loc(str(DataDB.get_skill(stunt_id).get("name_key", ""))) if stunt_id != "" else ""
		var recap: Dictionary = RtwpSimStep.build_defeat_recap(death_ring_buffer, combat_clock_sec, CampaignState.active_formation_id, unused_pills, stunt_name)
		boss_combat_changed.emit(null)
		party_wiped.emit(recap)
		return

	# 2. 检测当前交战敌群是否全部肃清或脱战
	var any_enemy_engaged: bool = false
	for ea: BattleActor in enemy_actors:
		if ea.alive:
			var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
			if bool(eu.get("engaged", false)):
				any_enemy_engaged = true
				break

	if not any_enemy_engaged:
		_finish_combat_victory()


func _finish_combat_victory() -> void:
	in_combat = false
	tactical_paused = false
	_hitstop_timer = 0.0
	_shake_timer = minf(_shake_timer, 0.10)
	auto_attack_enabled = false
	InputRouter.combat_engaged = false
	NotifyHub.set_combat_active(false)
	boss_combat_changed.emit(null)

	if audio_director != null:
		audio_director.set_tactical_pause_filter(false)
		audio_director.stop_special_bgm_return_to_field()
		audio_director.set_combat_engaged(false)

	# 重伤倒地队友自动以 20% 气血复苏（附 1 层经脉暗伤）
	for cid_var: Variant in party_actors.keys():
		var cid: String = str(cid_var)
		var pa: BattleActor = party_actors[cid] as BattleActor
		var mstate: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		if not pa.alive:
			pa.alive = true
			pa.hp = maxi(15, int(round(float(pa.max_hp) * 0.20)))
			mstate["meridian_bruise"] = mini(3, int(mstate.get("meridian_bruise", 0)) + 1)
		mstate["hp"] = pa.hp
		mstate["mp"] = pa.mp

	if pet_actor != null:
		if not pet_actor.alive:
			pet_actor.alive = true
			pet_actor.hp = maxi(20, int(round(float(pet_actor.max_hp) * 0.35)))
		CampaignState.pet_hp_ratio = float(pet_actor.hp) / float(maxi(1, pet_actor.max_hp))

	# 推进【断玉剑匣】废丹提纯进度！
	CampaignState.advance_sword_box_progress(1)
	CampaignState.recalculate_all_party_stats(false)

	# 检查已彻底消灭的 group_id 并派发事件（如破庙狼群清场、竹林劫修掉落储物袋、雾隐狼王灵髓抉择）
	var groups_alive: Dictionary = {}
	var all_groups: Dictionary = {}
	var boss_group_cleared: String = ""
	for ea: BattleActor in enemy_actors:
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		var gid: String = str(eu.get("group_id", ""))
		if gid == "":
			continue
		all_groups[gid] = bool(all_groups.get(gid, false)) or ea.is_boss
		if ea.alive:
			groups_alive[gid] = true

	for gid_var: Variant in all_groups.keys():
		var g: String = str(gid_var)
		if not groups_alive.has(g) and not CampaignState.cleared_encounters.has(g):
			CampaignState.cleared_encounters[g] = true
			var was_b: bool = bool(all_groups[g])
			if was_b:
				boss_group_cleared = g
			encounter_cleared.emit(g, was_b)

	if boss_group_cleared == "":
		SaveManager.save_rolling_auto()
	combat_hud_dirty.emit()


func _refresh_vfx_overlays(combat_delta: float, ui_delta: float = 0.0) -> void:
	if ground_vfx == null or sky_vfx == null:
		return
	ground_vfx.active_telegraphs.clear()
	ground_vfx.move_previews.clear()
	sky_vfx.queued_skill_lines.clear()

	for ea: BattleActor in enemy_actors:
		if not ea.alive:
			continue
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		if bool(eu.get("casting", false)):
			var sdef: Dictionary = DataDB.get_skill(str(eu.get("cast_skill_id", "")))
			var ttype: String = str(sdef.get("target_type", ""))
			var prog: float = float(eu.get("cast_progress", 0.0)) / maxf(0.1, float(eu.get("cast_duration", 1.0)))
			var is_intr: bool = bool(eu.get("cast_interruptible", false))
			if ttype == "ground_circle":
				ground_vfx.active_telegraphs.append({
					"type": "circle",
					"origin": eu.get("cast_origin", ea.position),
					"radius": float(sdef.get("telegraph_radius_px", 135.0)),
					"progress": prog,
					"interruptible": is_intr,
				})
			elif ttype == "ground_cone":
				ground_vfx.active_telegraphs.append({
					"type": "cone",
					"origin": eu.get("cast_origin", ea.position),
					"dir": eu.get("cast_dir", Vector2.RIGHT),
					"radius": float(sdef.get("telegraph_radius_px", 245.0)),
					"angle_deg": float(sdef.get("telegraph_angle_deg", 95.0)),
					"progress": prog,
					"interruptible": is_intr,
				})
			elif ttype == "party_aoe":
				var roar_dir: Vector2 = (eu.get("cast_dir", Vector2.LEFT) as Vector2).normalized()
				ground_vfx.active_telegraphs.append({
					"type": "circle",
					"origin": ea.position + roar_dir * (115.0 if ea.is_boss else 0.0),
					"radius": 215.0 if ea.is_boss else 155.0,
					"progress": prog,
					"interruptible": is_intr,
				})

	for ally: BattleActor in _get_all_living_allies_and_pet():
		if ally.has_move_waypoint:
			ground_vfx.move_previews.append({
				"from": ally.position,
				"to": ally.move_waypoint,
				"label": ally.display_name if tactical_paused else "",
			})
		var au: Dictionary = unit_states.get(ally.actor_id, {}) as Dictionary
		var q_sk: String = str(au.get("queued_skill_id", ""))
		if q_sk != "":
			var qtgt: BattleActor = _find_any_actor(str(au.get("queued_target_id", "")))
			if qtgt != null:
				var qsdef: Dictionary = DataDB.get_skill(q_sk)
				sky_vfx.queued_skill_lines.append({
					"from": ally.position,
					"to": qtgt.position,
					"skill_name": DataDB.loc(str(qsdef.get("name_key", q_sk))),
					"color": UIThemeBuilder.get_element_color(str(qsdef.get("element", "metal"))),
				})

	ground_vfx.step_fx(combat_delta, ui_delta)
	sky_vfx.step_fx(combat_delta, ui_delta)


## ==================== 辅助目标解析与几何碰撞 ====================
func _resolve_skill_target_id(caster_id: String, sdef: Dictionary) -> String:
	var ttype: String = str(sdef.get("target_type", "enemy"))
	if ttype == "ally":
		# 原生魔兽式 Mouseover（鼠标悬停小队框或场景友方小人直接施法！）
		if hovered_ally_id != "" and party_actors.has(hovered_ally_id):
			var ha: BattleActor = party_actors[hovered_ally_id] as BattleActor
			if ha.alive:
				return hovered_ally_id
		if hovered_world_actor_id != "" and party_actors.has(hovered_world_actor_id):
			var hwa: BattleActor = party_actors[hovered_world_actor_id] as BattleActor
			if hwa.alive:
				return hovered_world_actor_id
		# 否则智能选中气血比例最低的存活队友
		var best_id: String = caster_id
		var best_r: float = 2.0
		for cid_var: Variant in party_actors.keys():
			var cid: String = str(cid_var)
			var pa: BattleActor = party_actors[cid] as BattleActor
			if pa.alive:
				var r: float = float(pa.hp) / float(maxi(1, pa.max_hp))
				if r < best_r:
					best_r = r
					best_id = cid
		return best_id
	elif ttype == "self" or ttype == "party":
		return caster_id

	if locked_enemy_id != "":
		var le: BattleActor = _find_enemy_actor(locked_enemy_id)
		if le != null and le.alive:
			return locked_enemy_id
	var caster_actor: BattleActor = party_actors.get(caster_id, null) as BattleActor
	var near_e: BattleActor = _pick_ai_enemy_target(caster_actor.position if caster_actor != null else Vector2.ZERO)
	if near_e != null:
		set_locked_enemy(near_e.actor_id, true)
		return near_e.actor_id
	return ""


func _pick_ai_enemy_target(from_pos: Vector2) -> BattleActor:
	if locked_enemy_id != "":
		var le: BattleActor = _find_enemy_actor(locked_enemy_id)
		if le != null and le.alive:
			var leu: Dictionary = unit_states.get(le.actor_id, {}) as Dictionary
			if bool(leu.get("engaged", false)) or not in_combat:
				return le
	var best: BattleActor = null
	var best_d: float = 999999.0
	for ea: BattleActor in enemy_actors:
		if not ea.alive:
			continue
		var eu: Dictionary = unit_states.get(ea.actor_id, {}) as Dictionary
		if in_combat and not bool(eu.get("engaged", false)):
			continue
		var d: float = from_pos.distance_to(ea.position)
		if d < best_d:
			best_d = d
			best = ea
	return best


func _build_ally_threat_candidates(enemy_pos: Vector2) -> Array:
	var list: Array = []
	for cid_var: Variant in party_actors.keys():
		var cid: String = str(cid_var)
		var pa: BattleActor = party_actors[cid] as BattleActor
		var pu: Dictionary = unit_states[cid] as Dictionary
		list.append({
			"id": cid,
			"alive": pa.alive,
			"is_melee_range": enemy_pos.distance_to(pa.position) <= 175.0,
			"is_tank_role": bool(pu.get("is_tank_role", false)),
		})
	if pet_actor != null and pet_actor.alive and unit_states.has(pet_actor.actor_id):
		var pet_u: Dictionary = unit_states[pet_actor.actor_id] as Dictionary
		list.append({
			"id": pet_actor.actor_id,
			"alive": true,
			"is_melee_range": enemy_pos.distance_to(pet_actor.position) <= 175.0,
			"is_tank_role": bool(pet_u.get("is_tank_role", false)),
		})
	return list


func _get_enemy_available_skills(eu: Dictionary) -> Array:
	var edef: Dictionary = eu.get("edef", {}) as Dictionary
	if bool(edef.get("is_boss", false)):
		var phase: int = int(eu.get("phase", 1))
		return (edef.get("skills_p2" if phase >= 2 else "skills_p1", []) as Array)
	return (edef.get("skills", []) as Array)


func _can_cast_skill(u: Dictionary, actor: BattleActor, sk_id: String) -> bool:
	if sk_id == "":
		return false
	if (u.get("cooldowns", {}) as Dictionary).has(sk_id):
		return false
	var sdef: Dictionary = DataDB.get_skill(sk_id)
	return actor.mp >= int(sdef.get("mp_cost", 0))


func _does_trigger_synergy(seal_elem: String, skill_elem: String) -> bool:
	if seal_elem == "" or not RtwpSimStep.ELEMENT_SYNERGY_MAP.has(seal_elem):
		return false
	var rule: Dictionary = RtwpSimStep.ELEMENT_SYNERGY_MAP[seal_elem] as Dictionary
	return str(rule.get("child", "")) == skill_elem


func _heal_lowest_party_member(amount: int, cleanse: bool = false) -> void:
	var best_a: BattleActor = null
	var best_r: float = 2.0
	for cid_var: Variant in party_actors.keys():
		var pa: BattleActor = party_actors[str(cid_var)] as BattleActor
		if pa.alive:
			var r: float = float(pa.hp) / float(maxi(1, pa.max_hp))
			if r < best_r:
				best_r = r
				best_a = pa
	if best_a != null:
		_apply_ally_heal(best_a.actor_id, best_a, amount, cleanse)


func _get_member_blue_stunt_ids(cid: String) -> Array:
	var sh: Dictionary = (unit_states.get(cid, {}) as Dictionary).get("sheet", {}) as Dictionary
	var stunts: Array = sh.get("blue_stunt_ids", []) as Array
	if stunts.is_empty():
		var pm: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var cs_sh: Dictionary = pm.get("sheet", {}) as Dictionary
		stunts = cs_sh.get("blue_stunt_ids", []) as Array
	return stunts


func _char_has_blue_stunt(cid: String, skill_id: String) -> bool:
	var stunts: Array = _get_member_blue_stunt_ids(cid)
	for st_var: Variant in stunts:
		if str(st_var) == skill_id:
			return true
	return false


func _resolve_blue_stunt_owner_id(fallback_cid: String, skill_id: String) -> String:
	if fallback_cid != "" and _char_has_blue_stunt(fallback_cid, skill_id):
		return fallback_cid
	var packed: Array[int] = get_occupied_formation_slots()
	for fslot: int in packed:
		var cid: String = CampaignState.formation_slots[fslot - 1]
		if cid != "" and _char_has_blue_stunt(cid, skill_id):
			return cid
	for cid_var: Variant in party_actors.keys():
		var k: String = str(cid_var)
		if _char_has_blue_stunt(k, skill_id):
			return k
	return fallback_cid


func get_active_blue_stunt_info() -> Dictionary:
	var candidates: Array[String] = []
	var ctrl_id: String = get_controlled_char_id()
	if ctrl_id != "" and party_actors.has(ctrl_id):
		candidates.append(ctrl_id)
	var packed: Array[int] = get_occupied_formation_slots()
	for fslot: int in packed:
		var cid: String = CampaignState.formation_slots[fslot - 1]
		if cid != "" and not candidates.has(cid):
			candidates.append(cid)
	for cid_var: Variant in party_actors.keys():
		var k: String = str(cid_var)
		if not candidates.has(k):
			candidates.append(k)

	for cid2: String in candidates:
		if not party_actors.has(cid2):
			continue
		var pa: BattleActor = party_actors[cid2] as BattleActor
		if not pa.alive:
			continue
		var stunts: Array = _get_member_blue_stunt_ids(cid2)
		if not stunts.is_empty():
			return {
				"skill_id": str(stunts[0]),
				"owner_id": cid2,
			}
	return {"skill_id": "", "owner_id": ""}


func _find_party_blue_stunt_id() -> String:
	return str(get_active_blue_stunt_info().get("skill_id", ""))


func get_active_blue_stunt_id() -> String:
	return str(get_active_blue_stunt_info().get("skill_id", ""))


func _get_all_living_allies_and_pet() -> Array[BattleActor]:
	var out: Array[BattleActor] = []
	for cid_var: Variant in party_actors.keys():
		var pa: BattleActor = party_actors[str(cid_var)] as BattleActor
		if pa.alive:
			out.append(pa)
	if pet_actor != null and pet_actor.alive:
		out.append(pet_actor)
	return out


func _find_enemy_actor(uid: String) -> BattleActor:
	for ea: BattleActor in enemy_actors:
		if is_instance_valid(ea) and ea.actor_id == uid:
			return ea
	return null


func _find_ally_or_pet_actor(uid: String) -> BattleActor:
	if party_actors.has(uid):
		return party_actors[uid] as BattleActor
	if pet_actor != null and pet_actor.actor_id == uid:
		return pet_actor
	return null


func _find_any_actor(uid: String) -> BattleActor:
	var a: BattleActor = _find_ally_or_pet_actor(uid)
	if a != null:
		return a
	return _find_enemy_actor(uid)


func _clamp_to_walkable(pt: Vector2) -> Vector2:
	var res: Vector2 = pt
	for obs: Dictionary in obstacle_circles:
		var c: Vector2 = obs.get("pos", Vector2.ZERO) as Vector2
		var r: float = float(obs.get("radius", 40.0))
		var diff: Vector2 = res - c
		var dist: float = diff.length()
		if dist < r and dist > 0.001:
			res = c + diff.normalized() * (r + 2.0)
	return res


func _resolve_move_collision(from_pt: Vector2, to_pt: Vector2, bounds: Rect2) -> Vector2:
	var clamped: Vector2 = Vector2(
		clampf(to_pt.x, bounds.position.x + 36.0, bounds.end.x - 36.0),
		clampf(to_pt.y, bounds.position.y + 52.0, bounds.end.y - 32.0)
	)
	for obs: Dictionary in obstacle_circles:
		var c: Vector2 = obs.get("pos", Vector2.ZERO) as Vector2
		var r: float = float(obs.get("radius", 40.0))
		var diff: Vector2 = clamped - c
		var dist: float = diff.length()
		if dist < r:
			if dist > 0.01:
				clamped = c + diff.normalized() * r
			else:
				clamped = from_pt
	return clamped
