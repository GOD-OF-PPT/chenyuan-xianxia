extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 1
# @e2e_features: F4, F15
## Worker 2 Tier 1 Headless Happy-Path Suite for F4 (Qimen Formations) and F15 (Save/NotifyHub/InputRouter/Recap/Audio).


func register_cases() -> void:
	add_case("T1-F04-01", 1, "F4", "baseline", "Qimen slot role stat modifiers across scatter, tianfu, and dizai", "case_t1_f04_01_slot_modifiers")
	add_case("T1-F04-02", 1, "F4", "baseline", "Position-independent Qimen permanent aura across 1900px+ battlefield spread", "case_t1_f04_02_position_independent_aura")
	add_case("T1-F04-03", 1, "F4", "baseline", "Major & Minor 5-formation counter matrix and live Wolf King counter damage", "case_t1_f04_03_counter_matrix_and_live_hit")
	add_case("T1-F04-04", 1, "F4", "baseline", "CombatHud Z quick drawer formation switch and party card role updates", "case_t1_f04_04_z_drawer_switch")
	add_case("T1-F04-05", 1, "F4", "baseline", "Sequential F1..F3 slot recruitment & Pei Zhao slot-2 insertion without holes", "case_t1_f04_05_sequential_party_slots")
	add_case("T1-F15-01", 1, "F15", "baseline", "Isolated scratch SaveManager .tmp/.bak/.json atomic SHA-256 envelope roundtrip", "case_t1_f15_01_save_envelope_roundtrip")
	add_case("T1-F15-02", 1, "F15", "baseline", "NotifyHub AoE 90ms merge window & post-combat 1.0s P3 slip max-2 throttling", "case_t1_f15_02_notify_hub_arbitration")
	add_case("T1-F15-03", 1, "F15", "baseline", "Pure PC KB/M InputRouter Space vs Enter separation, 400ms lock & joypad block", "case_t1_f15_03_input_router_modes_and_rebind")
	add_case("T1-F15-04", 1, "F15", "baseline", "DefeatRecapScroll 5s fatal chain diagnostics, dual-coded badge & manual respawn gate", "case_t1_f15_04_defeat_recap_scroll")
	add_case("T1-F15-05", 1, "F15", "baseline", "4-bus AudioServer, 900Hz Tactical Pause LPF, Tier-S -5dB ducking & settings roundtrip", "case_t1_f15_05_audio_buses_and_settings")


func _get_member_sheet(char_id: String) -> Dictionary:
	var m: Dictionary = CampaignState.party_members.get(char_id, {}) as Dictionary
	return m.get("sheet", {}) as Dictionary


func case_t1_f04_01_slot_modifiers() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", false)

	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "pei_zhao", "shen_qinghe", ""],
		"Trio slots match [gu_changqing, pei_zhao, shen_qinghe, '']"
	)

	CampaignState.set_active_formation("scatter")
	var gu_scatter: Dictionary = _get_member_sheet("gu_changqing")
	var pei_scatter: Dictionary = _get_member_sheet("pei_zhao")
	var shen_scatter: Dictionary = _get_member_sheet("shen_qinghe")

	CampaignState.set_active_formation("tianfu")
	var gu_tianfu: Dictionary = _get_member_sheet("gu_changqing")
	assert_approx(
		float(gu_tianfu.get("phys_power", 0.0)),
		float(gu_scatter.get("phys_power", 0.0)) * 1.18,
		0.05,
		"Tianfu slot 1 multiplies Gu Changqing phys_power by 1.18x"
	)
	assert_approx(
		float(gu_tianfu.get("spell_power", 0.0)),
		float(gu_scatter.get("spell_power", 0.0)) * 1.18,
		0.05,
		"Tianfu slot 1 multiplies Gu Changqing spell_power by 1.18x"
	)
	assert_approx(
		float(gu_tianfu.get("move_speed_px", 0.0)),
		float(gu_scatter.get("move_speed_px", 0.0)) * 0.92,
		0.25,
		"Tianfu applies 0.92x move_speed_px tradeoff"
	)

	CampaignState.set_active_formation("dizai")
	var pei_dizai: Dictionary = _get_member_sheet("pei_zhao")
	var shen_dizai: Dictionary = _get_member_sheet("shen_qinghe")
	var dizai_def: Dictionary = DataDB.get_formation("dizai")
	var slot2_mod: Dictionary = FormationRules.get_slot_modifiers(dizai_def, 2)
	assert_eq(str(slot2_mod.get("role_title", "")), "玄武镇岳", "Dizai slot 2 role title is 玄武镇岳")
	assert_approx(
		float(pei_dizai.get("damage_taken_mult", 1.0)),
		maxf(0.30, float(pei_scatter.get("damage_taken_mult", 1.0)) * 0.75),
		0.02,
		"Dizai slot 2 multiplies Pei Zhao damage_taken_mult by 0.75x"
	)
	assert_approx(
		float(pei_dizai.get("threat_mult", 1.0)),
		(float(pei_scatter.get("threat_mult", 1.0)) / 0.90) * 1.80,
		0.03,
		"Dizai slot 2 sets Pei Zhao threat_mult to 1.80x * stance_threat_mult"
	)
	assert_approx(
		float(shen_dizai.get("heal_power", 0.0)),
		float(shen_scatter.get("heal_power", 0.0)) * 1.12,
		0.05,
		"Dizai slot 3 (朱雀药灵) multiplies Shen Qinghe heal_power by 1.12x"
	)


func case_t1_f04_02_position_independent_aura() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	# Measure incoming damage when compactly grouped (~60px apart)
	gu.position = Vector2(500.0, 500.0)
	pei.position = Vector2(540.0, 510.0)
	shen.position = Vector2(460.0, 510.0)
	var pei_hp_start: int = pei.hp
	ctrl.call("_apply_damage_to_ally", "pei_zhao", pei, 60, "腐瘴灰狼", "扑咬", "wood", false, false, false)
	var loss_compact: int = pei_hp_start - pei.hp
	pei.hp = pei.max_hp

	# Spread party > 1950px apart across opposite corners of QinglanWorld
	gu.position = Vector2(150.0, 200.0)
	pei.position = Vector2(2100.0, 1200.0)
	shen.position = Vector2(1200.0, 150.0)
	var max_sep: float = gu.position.distance_to(pei.position)
	assert_gt(max_sep, 1900.0, "Gu and Pei separated by > 1900px in world space")

	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)
	var pei_u: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	var shen_u: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	var pei_sh: Dictionary = pei_u.get("sheet", {}) as Dictionary
	var shen_sh: Dictionary = shen_u.get("sheet", {}) as Dictionary

	var pei_hp_far_start: int = pei.hp
	ctrl.call("_apply_damage_to_ally", "pei_zhao", pei, 60, "腐瘴灰狼", "扑咬", "wood", false, false, false)
	var loss_spread: int = pei_hp_far_start - pei.hp

	assert_eq(loss_spread, loss_compact, "Dizai 0.75x tank mitigation is 100% identical at >1900px separation")
	assert_gt(float(pei_sh.get("threat_mult", 0.0)), 1.75, "Pei Zhao retains 1.80x Dizai threat_mult at >1900px")
	assert_gt(
		float(shen_sh.get("heal_power", 0.0)),
		float((DataDB.get_character("shen_qinghe").get("base_heal_power", 18.0))),
		"Shen Qinghe retains 1.12x Dizai heal bonus regardless of distance"
	)


func case_t1_f04_03_counter_matrix_and_live_hit() -> void:
	var major_pairs: Array[Array] = [
		["tianfu", "dizai"],
		["dizai", "fengyang"],
		["fengyang", "huyi"],
		["huyi", "longfei"],
		["longfei", "tianfu"],
	]
	for pair: Array in major_pairs:
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		var adv: Dictionary = FormationRules.evaluate_counter(a, b)
		var dis: Dictionary = FormationRules.evaluate_counter(b, a)
		assert_eq(str(adv.get("relation", "")), "major_advantage", "%s -> %s is major_advantage" % [a, b])
		assert_approx(float(adv.get("damage_mult", 0.0)), 1.10, 0.001, "%s -> %s damage_mult == 1.10" % [a, b])
		assert_approx(float(adv.get("damage_taken_mult", 0.0)), 0.90, 0.001, "%s -> %s damage_taken_mult == 0.90" % [a, b])
		assert_eq(str(dis.get("relation", "")), "major_disadvantage", "%s -> %s is major_disadvantage" % [b, a])
		assert_approx(float(dis.get("damage_mult", 0.0)), 0.90, 0.001, "%s -> %s damage_mult == 0.90" % [b, a])
		assert_approx(float(dis.get("damage_taken_mult", 0.0)), 1.10, 0.001, "%s -> %s damage_taken_mult == 1.10" % [b, a])

	var minor_pairs: Array[Array] = [
		["tianfu", "huyi"],
		["dizai", "longfei"],
		["fengyang", "tianfu"],
		["huyi", "dizai"],
		["longfei", "fengyang"],
	]
	for mpair: Array in minor_pairs:
		var ma: String = str(mpair[0])
		var mb: String = str(mpair[1])
		var m_adv: Dictionary = FormationRules.evaluate_counter(ma, mb)
		var m_dis: Dictionary = FormationRules.evaluate_counter(mb, ma)
		assert_eq(str(m_adv.get("relation", "")), "minor_advantage", "%s -> %s is minor_advantage" % [ma, mb])
		assert_approx(float(m_adv.get("damage_mult", 0.0)), 1.05, 0.001, "%s -> %s damage_mult == 1.05" % [ma, mb])
		assert_approx(float(m_adv.get("damage_taken_mult", 0.0)), 0.95, 0.001, "%s -> %s damage_taken_mult == 0.95" % [ma, mb])
		assert_eq(str(m_dis.get("relation", "")), "minor_disadvantage", "%s -> %s is minor_disadvantage" % [mb, ma])
		assert_approx(float(m_dis.get("damage_mult", 0.0)), 0.95, 0.001, "%s -> %s damage_mult == 0.95" % [mb, ma])
		assert_approx(float(m_dis.get("damage_taken_mult", 0.0)), 1.05, 0.001, "%s -> %s damage_taken_mult == 1.05" % [mb, ma])

	# Live deterministic non-crit hit on Mist Wolf King (formation_id == "fengyang")
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", true)
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl

	var boss_actor: BattleActor = null
	for ea: BattleActor in ctrl.enemy_actors:
		if ea.is_boss:
			boss_actor = ea
			break
	assert_not_null(boss_actor, "Mist Wolf King spawned in cangmu_cave")
	if boss_actor == null:
		return

	var boss_u: Dictionary = ctrl.unit_states[boss_actor.actor_id] as Dictionary
	assert_eq(str(boss_u.get("formation_id", "")), "fengyang", "Mist Wolf King uses fengyang formation")

	var gu_actor: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	gu_actor.position = boss_actor.position + Vector2(-95.0, 0.0)
	ctrl.engage_enemy_group("enc_boss_wolf_king", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0

	# Fix Gu's raw sheet power & zero crit so only active_formation_id counter mult varies via public hotkey '1'
	ctrl.set_locked_enemy(boss_actor.actor_id, false)
	CampaignState.active_formation_id = "dizai"
	var gu_u: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var fixed_sheet: Dictionary = (gu_u.get("sheet", {}) as Dictionary).duplicate(true)
	fixed_sheet["phys_power"] = 120.0
	fixed_sheet["spell_power"] = 120.0
	fixed_sheet["crit_pct"] = 0.0
	gu_u["sheet"] = fixed_sheet
	gu_u["gcd_timer"] = 0.0
	(gu_u["cooldowns"] as Dictionary).clear()
	gu_actor.mp = gu_actor.max_mp

	var hp_b0: int = boss_actor.hp
	boss_u["ward_current"] = 450.0
	boss_actor.ward_current = 450.0
	ctrl.trigger_hotkey_slot("1")
	var dmg_dizai: int = hp_b0 - boss_actor.hp

	CampaignState.active_formation_id = "tianfu"
	gu_u["sheet"] = fixed_sheet
	gu_u["gcd_timer"] = 0.0
	(gu_u["cooldowns"] as Dictionary).clear()
	gu_actor.mp = gu_actor.max_mp
	boss_u["ward_current"] = 450.0
	boss_actor.ward_current = 450.0
	boss_u["mother_seal_element"] = ""
	boss_u["mother_seal_timer"] = 0.0
	var hp_b1: int = boss_actor.hp
	ctrl.trigger_hotkey_slot("1")
	var dmg_tianfu: int = hp_b1 - boss_actor.hp

	var ratio: float = float(dmg_dizai) / float(maxi(1, dmg_tianfu))
	assert_approx(ratio, 1.10 / 0.95, 0.04, "Live hit vs fengyang Wolf King deals ~1.158x more damage in dizai than tianfu")
	record_metric("dizai_vs_tianfu_dmg_ratio", snappedf(ratio, 0.001))


func case_t1_f04_04_z_drawer_switch() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	var hud: CombatHud = world._hud
	hud.refresh_static_bindings()

	assert_false(hud.is_quick_drawer_open(), "Quick drawer initially closed")
	hud.toggle_quick_drawer()
	await step_frames(1)
	assert_true(hud.is_quick_drawer_open(), "Quick drawer opens on toggle_quick_drawer()")

	var drawer_vbox: VBoxContainer = hud.get("_drawer_vbox") as VBoxContainer
	var btns: Array[Button] = collect_visible_buttons(drawer_vbox)
	assert_eq(btns.size(), 3, "Z drawer lists all 3 unlocked Ch1 formations (scatter, dizai, tianfu)")

	var tianfu_btn: Button = null
	for b: Button in btns:
		if b.text.contains("天覆阵"):
			tianfu_btn = b
			break
	assert_not_null(tianfu_btn, "Found 天覆阵 button inside Z quick drawer")
	if tianfu_btn != null:
		tianfu_btn.pressed.emit()
	await step_frames(1)

	assert_eq(CampaignState.active_formation_id, "tianfu", "Pressing 天覆阵 updates CampaignState.active_formation_id")
	assert_false(hud.is_quick_drawer_open(), "Pressing formation button auto-closes Z quick drawer")

	var card0_lbl: Label = (hud._party_cards[0] as Dictionary).get("name_lbl", null) as Label
	var card1_lbl: Label = (hud._party_cards[1] as Dictionary).get("name_lbl", null) as Label
	var card2_lbl: Label = (hud._party_cards[2] as Dictionary).get("name_lbl", null) as Label
	assert_str_contains(card0_lbl.text, "青龙阵眼", "Slot 1 card displays 青龙阵眼")
	assert_str_contains(card1_lbl.text, "玄武前锋", "Slot 2 card displays 玄武前锋")
	assert_str_contains(card2_lbl.text, "朱雀焚灵", "Slot 3 card displays 朱雀焚灵")


func case_t1_f04_05_sequential_party_slots() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud

	assert_eq(CampaignState.formation_slots, ["gu_changqing", "", "", ""], "Starter campaign slots only Gu in F1")
	assert_true(((hud._party_cards[0] as Dictionary)["card"] as Control).visible, "F1 card visible")
	assert_false(((hud._party_cards[1] as Dictionary)["card"] as Control).visible, "F2 card hidden when solo")

	CampaignState.recruit_companion("shen_qinghe", 2)
	ctrl.sync_party_roster_in_place()
	hud.refresh_static_bindings()
	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "shen_qinghe", "", ""],
		"Shen Qinghe occupies slot 2 (F2)"
	)
	assert_true(((hud._party_cards[1] as Dictionary)["card"] as Control).visible, "F2 card visible after Shen joins")
	assert_false(((hud._party_cards[2] as Dictionary)["card"] as Control).visible, "F3 card hidden with duo")

	CampaignState.recruit_companion("pei_zhao", 2)
	ctrl.sync_party_roster_in_place()
	hud.refresh_static_bindings()
	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "pei_zhao", "shen_qinghe", ""],
		"Pei Zhao inserts at preferred slot 2 and shifts Shen Qinghe to slot 3 cleanly"
	)
	for s_i: int in range(3):
		var cdict: Dictionary = hud._party_cards[s_i] as Dictionary
		var card_ctrl: Control = cdict["card"] as Control
		var nlbl: Label = cdict["name_lbl"] as Label
		assert_true(card_ctrl.visible, "F%d card visible" % (s_i + 1))
		assert_str_contains(nlbl.text, "F%d " % (s_i + 1), "Card %d has sequential F%d badge" % [s_i + 1, s_i + 1])
	assert_false(((hud._party_cards[3] as Dictionary)["card"] as Control).visible, "F4 card remains hidden in Ch1 trio")


func case_t1_f15_01_save_envelope_roundtrip() -> void:
	if not begin_isolated_xdg_save_test():
		return
	CampaignState.start_new_campaign("tribulation")
	CampaignState.sandbox_mode = false
	CampaignState.spirit_stones = 321
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.stamp_ink_seal("seal_scatter_rain", "mortal_mercy")

	var s1: Dictionary = SaveManager.save_manual_slot(1)
	assert_true(bool(s1.get("ok", false)), "First save_manual_slot(1) succeeded")

	CampaignState.spirit_stones = 654
	var s2: Dictionary = SaveManager.save_manual_slot(1)
	assert_true(bool(s2.get("ok", false)), "Second save_manual_slot(1) succeeded and rotated .bak")

	var slot_path: String = "user://saves/slot_01.json"
	var tmp_path: String = "user://saves/slot_01.json.tmp"
	var bak_path: String = "user://saves/slot_01.json.bak"
	assert_true(FileAccess.file_exists(slot_path), "slot_01.json exists on scratch disk")
	assert_false(FileAccess.file_exists(tmp_path), "Zero leftover slot_01.json.tmp after atomic rename")
	assert_true(FileAccess.file_exists(bak_path), "slot_01.json.bak created from previous valid save")

	var env: Dictionary = load_json_dict(slot_path)
	assert_eq(str(env.get("magic", "")), "CHENYUAN_XIANXIA_SAVE", "Envelope magic matches CHENYUAN_XIANXIA_SAVE")
	assert_eq(int(env.get("schema_version", 0)), 1, "Envelope schema_version == 1")
	assert_eq(str(env.get("checksum_sha256", "")).length(), 64, "Envelope carries 64-hex SHA-256 checksum")

	var bak_env: Dictionary = load_json_dict(bak_path)
	var bak_sum: Dictionary = bak_env.get("summary", {}) as Dictionary
	assert_eq(int(bak_sum.get("spirit_stones", 0)), 321, ".bak preserves first save's spirit_stones == 321")

	# Reset live state completely to different difficulty & empty companions
	CampaignState.start_new_campaign("ask_heart")
	CampaignState.sandbox_mode = false
	assert_eq(CampaignState.difficulty, "ask_heart", "State reset to ask_heart prior to load")

	var lres: Dictionary = SaveManager.load_slot("slot_01", false)
	assert_true(bool(lres.get("ok", false)), "load_slot('slot_01') succeeded")
	assert_eq(CampaignState.difficulty, "tribulation", "Restored difficulty == tribulation")
	assert_eq(CampaignState.spirit_stones, 654, "Restored spirit_stones == 654")
	assert_true(
		bool((CampaignState.party_members.get("shen_qinghe", {}) as Dictionary).get("recruited", false)),
		"Restored shen_qinghe recruited state"
	)
	assert_true(CampaignState.ink_seals.has("seal_scatter_rain"), "Restored Cinnabar Karma Seal seal_scatter_rain")
	end_isolated_xdg_save_test()


func case_t1_f15_02_notify_hub_arbitration() -> void:
	var floater_events: Array[Dictionary] = []
	var slip_events: Array[Dictionary] = []
	var cb_f: Callable = func(payload: Dictionary) -> void: floater_events.append(payload.duplicate(true))
	var cb_s: Callable = func(payload: Dictionary) -> void: slip_events.append(payload.duplicate(true))
	NotifyHub.combat_floater_pushed.connect(cb_f)
	NotifyHub.explore_slip_spawned.connect(cb_s)

	# 1. AoE 90ms merge bucket
	NotifyHub.set_combat_active(true)
	NotifyHub.push_combat_number(Vector2(400.0, 400.0), 42, false, false, "fire", "sk_gu_flame_sword")
	NotifyHub._process(0.02)
	NotifyHub.push_combat_number(Vector2(430.0, 410.0), 58, false, true, "fire", "sk_gu_flame_sword")
	NotifyHub._process(0.02)
	NotifyHub.push_combat_number(Vector2(450.0, 395.0), 50, false, false, "fire", "sk_gu_flame_sword")
	assert_eq(floater_events.size(), 0, "AoE hits held inside 90ms merge window")

	NotifyHub._process(0.10)
	assert_eq(floater_events.size(), 1, "3 AoE hits merged into exactly 1 combat_floater_pushed event")
	if floater_events.size() == 1:
		assert_eq(int(floater_events[0].get("hit_count", 0)), 3, "Merged floater hit_count == 3")
		assert_eq(int(floater_events[0].get("amount", 0)), 150, "Merged floater summed amount == 150")
		assert_true(bool(floater_events[0].get("is_crit", false)), "Merged floater preserves crit flag")

	# 2. P3 explore slip gating: held in combat, 1.0s post-combat delay, max 2 concurrent slips
	for idx: int in range(4):
		NotifyHub.push_explore_slip("拾取灵材_%d" % idx, "数量 +1", "loot")

	NotifyHub._process(0.50)
	assert_eq(slip_events.size(), 0, "Zero P3 slips emitted while combat_active == true")

	NotifyHub.set_combat_active(false)
	for _t1: int in range(10):
		NotifyHub._process(0.05) # 0.50s total (< 1.0s POST_BUSY_DELAY_SEC)
	assert_eq(slip_events.size(), 0, "Zero P3 slips emitted at 0.50s (< 1.0s POST_BUSY_DELAY_SEC)")

	for _t2: int in range(12):
		NotifyHub._process(0.05) # +0.60s => 1.10s total (> 1.0s POST_BUSY_DELAY_SEC)
	assert_eq(slip_events.size(), 2, "Exactly MAX_ACTIVE_SLIPS == 2 emitted at 1.10s post-combat")
	assert_eq(NotifyHub._p3_queue.size(), 2, "Remaining 2 P3 slips stay queued while 2 are active")

	for _t3: int in range(66):
		NotifyHub._process(0.05) # +3.30s (> 3.2s SLIP_DURATION_SEC)
	assert_eq(slip_events.size(), 4, "Remaining 2 P3 slips drain after SLIP_DURATION_SEC (3.2s)")

	NotifyHub.combat_floater_pushed.disconnect(cb_f)
	NotifyHub.explore_slip_spawned.disconnect(cb_s)


func case_t1_f15_03_input_router_modes_and_rebind() -> void:
	var pause_cnt: Array[int] = [0]
	var adv_cnt: Array[int] = [0]
	var cb_p: Callable = func() -> void: pause_cnt[0] += 1
	var cb_a: Callable = func() -> void: adv_cnt[0] += 1
	InputRouter.tactical_pause_toggled.connect(cb_p)
	InputRouter.dialogue_advance_requested.connect(cb_a)

	# Space emits tactical_pause_toggled ONLY in MODE_WORLD_COMBAT
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	InputRouter._input(make_key_event(KEY_SPACE, true))
	assert_eq(pause_cnt[0], 1, "KEY_SPACE emits tactical_pause_toggled in MODE_WORLD_COMBAT")

	for non_combat_mode: int in [InputRouter.MODE_DIALOGUE, InputRouter.MODE_MODAL_MENU, InputRouter.MODE_CUTSCENE_CG]:
		InputRouter.set_mode(non_combat_mode)
		InputRouter._input(make_key_event(KEY_SPACE, true))
	assert_eq(pause_cnt[0], 1, "KEY_SPACE is 100% swallowed in MODE_DIALOGUE, MODE_MODAL_MENU, MODE_CUTSCENE_CG")
	assert_eq(adv_cnt[0], 0, "KEY_SPACE never emits dialogue_advance_requested")

	# 400ms dialogue anti-mash lock on Enter
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	InputRouter._process(0.35)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_eq(adv_cnt[0], 0, "KEY_ENTER blocked during 0.40s DIALOGUE_LOCK_DURATION_SEC")

	InputRouter._process(0.07)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_eq(adv_cnt[0], 1, "KEY_ENTER advances dialogue once 0.41s lock expires")

	# Joypad events unconditionally swallowed (pure PC KB/M rule)
	var joy_btn: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_btn.button_index = JOY_BUTTON_A
	joy_btn.pressed = true
	InputRouter._input(joy_btn)
	var joy_mot: InputEventJoypadMotion = InputEventJoypadMotion.new()
	joy_mot.axis = JOY_AXIS_LEFT_X
	joy_mot.axis_value = 1.0
	InputRouter._input(joy_mot)
	assert_eq(adv_cnt[0], 1, "Joypad button & motion events trigger zero actions")

	# Keybind conflict guards
	var bad_space: Dictionary = InputRouter.rebind_action("dialogue_confirm", KEY_SPACE)
	assert_false(bool(bad_space.get("ok", true)), "Binding dialogue_confirm to Space is forbidden")
	assert_eq(str(bad_space.get("conflict", "")), "FORBIDDEN_SPACE_DIALOGUE", "Returns FORBIDDEN_SPACE_DIALOGUE")

	var dup_key: Dictionary = InputRouter.rebind_action("skill_q", KEY_E)
	assert_false(bool(dup_key.get("ok", true)), "Duplicate keybind onto KEY_E rejected")
	assert_eq(str(dup_key.get("conflict", "")), "skill_e", "Conflict reports existing action skill_e")

	InputRouter.tactical_pause_toggled.disconnect(cb_p)
	InputRouter.dialogue_advance_requested.disconnect(cb_a)


func case_t1_f15_04_defeat_recap_scroll() -> void:
	var ring: Array = []
	RtwpSimStep.record_damage_event(ring, 10.2, "腐瘴灰狼", "扑咬", "wood", 38, false, false, "裴照")
	RtwpSimStep.record_damage_event(ring, 13.8, "雾隐狼王", "腐木咆哮", "wood", 142, true, false, "顾长青")
	var recap: Dictionary = RtwpSimStep.build_defeat_recap(ring, 14.2, "dizai", 0, "")

	var scroll: DefeatRecapScroll = DefeatRecapScroll.new()
	mount_node(scroll)
	await step_frames(1)

	var respawn_signals: Array[int] = [0]
	scroll.respawn_at_stele_requested.connect(func() -> void: respawn_signals[0] += 1)

	scroll.show_recap(recap)
	await step_frames(2)

	assert_true(scroll.visible, "DefeatRecapScroll becomes visible on show_recap()")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "InputRouter enters MODE_MODAL_MENU")

	var all_txt: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(scroll):
		all_txt.append(lbl.text)
	var joined: String = "\n".join(all_txt)

	assert_str_contains(joined, "【琥珀金条·未打断】", "Fatal chain highlights missed Amber-Gold interruptible cast")
	assert_str_contains(joined, "❖木", "Fatal chain includes dual-coded Wood element badge ❖木")
	assert_str_contains(joined, "腐木咆哮", "Tip & chain identify the fatal skill 腐木咆哮")
	assert_eq(respawn_signals[0], 0, "Scene never auto-reloads without explicit player click")

	var btns: Array[Button] = collect_visible_buttons(scroll)
	assert_eq(btns.size(), 2, "Recap scroll exposes Stele Respawn and Load Save buttons")
	btns[0].pressed.emit()
	assert_eq(respawn_signals[0], 1, "Clicking stele_btn emits respawn_at_stele_requested")
	assert_false(scroll.visible, "Recap scroll closes after player chooses respawn")


func case_t1_f15_05_audio_buses_and_settings() -> void:
	if not begin_isolated_xdg_save_test():
		return
	SaveManager.load_settings()

	for bname: String in ["Master", "BGM_Bus", "Combat_SFX_Bus", "Ambient_UI_Bus"]:
		assert_ge(AudioServer.get_bus_index(bname), 0, "Audio bus '%s' exists" % bname)

	var ad: AudioDirector = AudioDirector.new()
	mount_node(ad)
	await step_frames(1)

	var bgm_idx: int = AudioServer.get_bus_index("BGM_Bus")
	var amb_idx: int = AudioServer.get_bus_index("Ambient_UI_Bus")
	ad.set_tactical_pause_filter(true)
	assert_true(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "900Hz LPF enabled on BGM_Bus during Tactical Pause")
	assert_true(AudioServer.is_bus_effect_enabled(amb_idx, 0), "900Hz LPF enabled on Ambient_UI_Bus during Tactical Pause")
	var lpf_fx: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bgm_idx, 0) as AudioEffectLowPassFilter
	assert_not_null(lpf_fx, "Bus effect 0 on BGM_Bus is AudioEffectLowPassFilter")
	if lpf_fx != null:
		assert_approx(lpf_fx.cutoff_hz, 900.0, 1.0, "Tactical Pause LPF cutoff_hz == 900Hz")

	ad.set_tactical_pause_filter(false)
	assert_false(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "900Hz LPF disabled on BGM_Bus on unpause")
	assert_false(AudioServer.is_bus_effect_enabled(amb_idx, 0), "900Hz LPF disabled on Ambient_UI_Bus on unpause")

	ad.play_sfx("sfx_ward_break_thunder", AudioDirector.TIER_S)
	assert_approx(ad._duck_timer, 0.60, 0.02, "TIER_S SFX arms 0.60s -5dB sidechain ducking timer")

	# Settings roundtrip via user://settings.cfg in isolated scratch
	SaveManager.master_volume = 0.72
	SaveManager.bgm_volume = 0.61
	SaveManager.combat_sfx_volume = 0.77
	SaveManager.ambient_ui_volume = 0.54
	SaveManager.mute_on_unfocus = false
	SaveManager.screen_shake_pct = 0.25
	SaveManager.reduced_motion = true
	SaveManager.save_settings()

	SaveManager.master_volume = 0.10
	SaveManager.bgm_volume = 0.10
	SaveManager.mute_on_unfocus = true
	SaveManager.screen_shake_pct = 0.90
	SaveManager.reduced_motion = false
	SaveManager.load_settings()

	assert_approx(SaveManager.master_volume, 0.72, 0.005, "master_volume roundtripped")
	assert_approx(SaveManager.bgm_volume, 0.61, 0.005, "bgm_volume roundtripped")
	assert_approx(SaveManager.combat_sfx_volume, 0.77, 0.005, "combat_sfx_volume roundtripped")
	assert_approx(SaveManager.ambient_ui_volume, 0.54, 0.005, "ambient_ui_volume roundtripped")
	assert_false(SaveManager.mute_on_unfocus, "mute_on_unfocus roundtripped")
	assert_approx(SaveManager.screen_shake_pct, 0.25, 0.005, "screen_shake_pct roundtripped")
	assert_true(SaveManager.reduced_motion, "reduced_motion roundtripped")
	end_isolated_xdg_save_test()
