extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 3
# @e2e_features: F4, F6, F7, F15
## Worker 2 Tier 3 Cross-Feature Multi-System Integration Suite (F4 x F6 x F7 x F15).


func register_cases() -> void:
	add_case("T3-W2-01", 3, "F7", "baseline", "Ruined Temple Clash: 4-layer CG -> Portrait Stage -> Pei slot-2 & auto-dizai -> wolf clear -> 0.8s settle -> flawless promotion", "case_t3_w2_01_ruined_temple_clash_flow")
	add_case("T3-W2-02", 3, "F15", "baseline", "Missed interrupt / telegraph wipe -> DefeatRecapScroll 5s chain -> stele_btn respawn preserving loot & clearing bruise", "case_t3_w2_02_wipe_recap_and_stele_respawn")
	add_case("T3-W2-03", 3, "F6", "baseline", "Beast Rescue (pet_spirit_turtle, exact 1 pet) -> Ctrl+1 50% loyal guard split -> Stele rest & Night Talk Bond Tier 2", "case_t3_w2_03_turtle_rescue_guard_and_night_talk")
	add_case("T3-W2-04", 3, "F15", "baseline", "Mist Wolf King defeat -> 0.85s settle -> Marrow Choice dual branches & auto_01.json -> tamper slot_01 -> P0 & .bak recovery", "case_t3_w2_04_wolf_king_marrow_auto_save_and_bak")
	add_case("T3-W2-05", 3, "F4", "baseline", "Formation Major Counter (dizai vs fengyang) + Z combat swap (45s CD) + NotifyHub P1/P2/P3 & 900Hz LPF cleanup", "case_t3_w2_05_formation_swap_notify_lpf_flow")
	add_case("T3-W2-06", 3, "F4", "baseline", "Formation slot reordering + Save/Load envelope persistence + CombatHud role & F1..F3 party selection sync", "case_t3_w2_06_slot_reorder_save_load_hud_sync")


func _count_pets(ysort: Node2D) -> int:
	var n: int = 0
	for ch: Node in ysort.get_children():
		if ch is BattleActor and not ch.is_queued_for_deletion():
			if (ch as BattleActor).faction == "pet":
				n += 1
	return n


func case_t3_w2_01_ruined_temple_clash_flow() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var stage: NarrativeStage = world._narrative

	# Walk controlled Gu Changqing into Ruined Temple gate trigger (1890, 640)
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	gu.position = Vector2(1890.0, 640.0)
	world.call("_check_dynamic_zone_triggers")

	assert_true(stage.visible, "Approaching Ruined Temple triggers dlg_ch01_temple_clash")
	assert_true(stage._cg_active, "Starts in Tier 3 4-layer parallax CG cg_ch01_ruined_temple")
	assert_eq(stage._cg_layers.size(), 4, "4 CG layers loaded")
	assert_true(CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple"), "Temple CG unlocked")

	# Dismiss CG into Tier 2 Portrait Stage (L01..L04)
	InputRouter._process(0.45)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage._cg_active, "Transitioned from CG to Tier 2 Portrait Stage")
	assert_true(stage._scroll_panel.visible, "Dialogue scroll visible")

	InputRouter._process(0.45) # _dismiss_cg_step re-arms 400ms lock when entering MODE_DIALOGUE
	for _ln: int in range(4):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage.visible, "dlg_ch01_temple_clash finished")

	# Verify Pei Zhao recruited into slot 2 (shifting Shen to slot 3), tianfu + auto-dizai, and enc_temple_wolves engaged
	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "pei_zhao", "shen_qinghe", ""],
		"Pei Zhao inserted at slot 2 and Shen shifted to slot 3"
	)
	assert_true(CampaignState.unlocked_formations.has("tianfu"), "tianfu unlocked")
	assert_eq(CampaignState.active_formation_id, "dizai", "dizai auto-equipped")
	assert_true(ctrl.in_combat, "enc_temple_wolves pack spawned and engaged")

	# Clear enc_temple_wolves pack
	for ea: BattleActor in ctrl.enemy_actors:
		var eu: Dictionary = ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("group_id", "")) == "enc_temple_wolves" and ea.alive:
			ctrl.call("_apply_direct_enemy_hp_loss", eu, ea, ea.hp + 200, "metal", true, "")
	for _clr_step: int in range(5):
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
		if not ctrl.in_combat:
			break
	assert_false(ctrl.in_combat, "enc_temple_wolves cleared")

	# Verify 0.80s post-combat floater settle before dlg_ch01_temple_aftermath opens
	await tree.create_timer(0.30).timeout
	assert_false(stage.visible, "At +0.30s (< 0.80s settle), aftermath dialogue stays closed")

	await tree.create_timer(0.60).timeout
	assert_true(stage.visible, "After 0.80s settle, dlg_ch01_temple_aftermath opens")
	assert_eq(stage._active_dialogue_id, "dlg_ch01_temple_aftermath", "Active dialogue is dlg_ch01_temple_aftermath")

	InputRouter._process(0.45)
	for _a: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage.visible, "Aftermath dialogue finished")

	var gu_m: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	assert_eq(str(gu_m.get("realm_id", "")), "qi_refining_1", "Gu Changqing promoted to qi_refining_1")
	assert_eq(str(gu_m.get("dao_foundation_grade", "")), "flawless", "Gu Changqing granted flawless Dao foundation")
	assert_eq(int(gu_m.get("free_potential", 0)), 5, "Gu Changqing granted +5 free potential points")

	var has_cave_portal: bool = false
	for p: Dictionary in world._zone_portals:
		if str(p.get("target_zone", "")) == "cangmu_cave":
			has_cave_portal = true
			break
	assert_true(has_cave_portal, "Portal to cangmu_cave spawned in Ruined Temple")


func case_t3_w2_02_wipe_recap_and_stele_respawn() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("tianfu", true)
	CampaignState.rest_at_stele("stele_wolf_altar")

	# Grant loot that MUST survive a wipe
	var stones_before: int = CampaignState.spirit_stones + 50
	CampaignState.spirit_stones = stones_before
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	(CampaignState.party_members["gu_changqing"] as Dictionary)["meridian_bruise"] = 2
	CampaignState.recalculate_all_party_stats(false)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var recap_ui: DefeatRecapScroll = world._recap_scroll

	ctrl.engage_enemy_group("enc_boss_wolf_king", "pei_zhao", false)
	ctrl.combat_clock_sec = 12.0
	assert_false(bool(SaveManager.can_save_now().get("ok", true)), "Mid-combat save blocked prior to wipe")

	# Apply lethal un-dodged ground telegraph + missed Amber-Gold interruptible cast across party
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	ctrl.call("_apply_damage_to_ally", "pei_zhao", pei, pei.max_hp + 500, "雾隐狼王", "裂爪扑击", "wood", false, true, false)
	ctrl.combat_clock_sec = 13.4
	ctrl.call("_apply_damage_to_ally", "shen_qinghe", shen, shen.max_hp + 500, "雾隐狼王", "腐木咆哮", "wood", true, false, true)
	ctrl.combat_clock_sec = 14.1
	ctrl.call("_apply_damage_to_ally", "gu_changqing", gu, gu.max_hp + 500, "雾隐狼王", "腐木咆哮", "wood", true, false, true)

	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
	await step_frames(2)

	assert_true(recap_ui.visible, "Party wipe opens DefeatRecapScroll without silent scene jump")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "InputRouter enters MODE_MODAL_MENU")

	# Space mash must NOT dismiss DefeatRecapScroll
	for _s: int in range(5):
		InputRouter._input(make_key_event(KEY_SPACE, true))
	assert_true(recap_ui.visible, "KEY_SPACE blocked on DefeatRecapScroll")

	var recap_texts: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(recap_ui):
		recap_texts.append(lbl.text)
	var joined: String = "\n".join(recap_texts)
	assert_str_contains(joined, "【朱砂危招圈·未走位】", "Recap shows un-dodged cinnabar telegraph tag")
	assert_str_contains(joined, "【琥珀金条·未打断】", "Recap shows missed Amber-Gold interrupt tag")
	assert_str_contains(joined, "腐木咆哮", "Recap tip cites fatal skill 腐木咆哮")

	# Click active stele_btn to respawn at stele_wolf_altar
	var btns: Array[Button] = collect_visible_buttons(recap_ui)
	assert_ge(float(btns.size()), 1.0, "Stele respawn button visible")
	btns[0].pressed.emit()
	await step_frames(3)

	assert_false(recap_ui.visible, "DefeatRecapScroll closed after stele respawn")
	assert_eq(CampaignState.current_zone_id, "cangmu_cave", "Respawned in cangmu_cave")
	var gu_after: BattleActor = world._combat_ctrl.party_actors["gu_changqing"] as BattleActor
	assert_eq(gu_after.hp, gu_after.max_hp, "Stele respawn restores 100% HP")
	assert_eq(gu_after.mp, gu_after.max_mp, "Stele respawn restores 100% MP")
	assert_eq(
		int((CampaignState.party_members["gu_changqing"] as Dictionary).get("meridian_bruise", -1)),
		0,
		"Stele respawn clears meridian_bruise == 0"
	)
	assert_eq(CampaignState.spirit_stones, stones_before, "100% of Spirit Stones preserved across wipe")
	assert_eq(CampaignState.get_item_count("eq_pendant_poxue"), 1, "100% of looted equipment preserved across wipe")


func case_t3_w2_03_turtle_rescue_guard_and_night_talk() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var stage: NarrativeStage = world._narrative

	# 1. Run dlg_ch01_rescue_beast and choose Choice 1 (pet_spirit_turtle)
	stage.start_dialogue("dlg_ch01_rescue_beast")
	InputRouter._process(0.45)
	for _i: int in range(2):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_true(stage._choices_box.visible, "Beast rescue choices visible")
	InputRouter._process(0.45)
	var cbtns: Array[Button] = collect_visible_buttons(stage._choices_box)
	assert_eq(cbtns.size(), 2, "Two pet choices presented")
	cbtns[1].pressed.emit()
	await step_frames(2)

	assert_eq(CampaignState.active_pet_id, "pet_spirit_turtle", "Contracted pet_spirit_turtle")
	assert_eq(_count_pets(world._ysort_root), 1, "Strictly 1 active spirit pet spawned in _ysort_root")
	assert_not_null(ctrl.pet_actor, "ctrl.pet_actor valid")

	# 2. Enter combat & press Ctrl+1 -> sk_pet_turtle_guard activates 50% loyal guard damage split
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", ctrl.get_controlled_actor_pos() + Vector2(130.0, 0.0), "enc_turtle_test")
	ctrl.engage_enemy_group("enc_turtle_test", "gu_changqing", false)

	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var hp_no_guard_0: int = gu.hp
	ctrl.call("_apply_damage_to_ally", "gu_changqing", gu, 80, "腐瘴灰狼", "扑咬", "wood", false, false, false)
	var unguarded_loss: int = hp_no_guard_0 - gu.hp
	gu.hp = gu.max_hp

	var turtle_hp_0: int = ctrl.pet_actor.hp
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	InputRouter._input(make_key_event(KEY_1, true, true, false)) # Ctrl+1
	assert_gt(ctrl.loyal_guard_timer, 7.0, "Ctrl+1 activates turtle loyal_guard_timer (~8.0s)")
	var shield_before: float = gu.shield
	assert_gt(shield_before, 0.0, "Ctrl+1 also grants protective water shield to party")

	var hp_guard_0: int = gu.hp
	ctrl.call("_apply_damage_to_ally", "gu_changqing", gu, 80, "腐瘴灰狼", "扑咬", "wood", false, false, false)
	var guarded_hp_loss: int = hp_guard_0 - gu.hp
	var shield_absorbed: float = shield_before - gu.shield
	var turtle_shared_loss: int = turtle_hp_0 - ctrl.pet_actor.hp

	assert_approx(float(turtle_shared_loss), float(unguarded_loss) * 0.50, 2.0, "Spirit turtle absorbs exact 50% shared damage")
	assert_approx(
		float(guarded_hp_loss) + shield_absorbed,
		float(unguarded_loss) * 0.50,
		2.0,
		"Remaining 50% damage on Gu is split cleanly across water shield + HP"
	)

	# Finish combat, rest at stele, and run dlg_night_talk_1 -> Bond Tier 2
	var eu: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	ctrl.call("_apply_direct_enemy_hp_loss", eu, wolf, wolf.hp + 100, "metal", false, "")
	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
	assert_lt(CampaignState.pet_hp_ratio, 1.0, "Pet HP ratio reflects battle damage before stele rest")

	CampaignState.rest_at_stele("stele_temple_courtyard")
	assert_approx(CampaignState.pet_hp_ratio, 1.0, 0.001, "Stele rest restores pet_hp_ratio == 1.0")

	world._modals.open_stele_modal("stele_temple_courtyard", "青岚山道 · 破庙前庭石碑")
	await step_frames(1)
	var nt_btn: Button = null
	for b: Button in collect_visible_buttons(world._modals):
		if b.text.contains("青莲旧事") or b.text.contains("沈清禾"):
			nt_btn = b
			break
	assert_not_null(nt_btn, "Stele modal lists Night Talk 1 button")
	if nt_btn != null:
		nt_btn.pressed.emit()
	assert_true(stage.visible, "Selecting Night Talk opens dlg_night_talk_1")
	InputRouter._process(0.45)
	for _n: int in range(4):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 0)), 2, "Shen Qinghe reaches Bond Tier 2")
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "ult_qinglian_sword unlocked")


func case_t3_w2_04_wolf_king_marrow_auto_save_and_bak() -> void:
	if not begin_isolated_xdg_save_test():
		return
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.read_dialogues["dlg_ch01_wolf_king_intro"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	CampaignState.sandbox_mode = false
	var ctrl: RtwpCombatController = world._combat_ctrl
	var stage: NarrativeStage = world._narrative

	# Engage and defeat Mist Wolf King -> 0.85s settle -> dlg_ch01_marrow_choice
	ctrl.engage_enemy_group("enc_boss_wolf_king", "gu_changqing", false)
	for ea: BattleActor in ctrl.enemy_actors:
		var eu: Dictionary = ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("group_id", "")) == "enc_boss_wolf_king" and ea.alive:
			ctrl.call("_apply_direct_enemy_hp_loss", eu, ea, ea.hp + 500, "metal", true, "")
	for _clr_step: int in range(5):
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
		if not ctrl.in_combat:
			break

	await tree.create_timer(0.35).timeout
	assert_false(stage.visible, "At +0.35s (< 0.85s settle), Marrow Choice dialogue not yet open")
	await tree.create_timer(0.65).timeout
	assert_true(stage.visible, "At +1.00s (> 0.85s settle), dlg_ch01_marrow_choice opens")

	var pre_choice_snap: Dictionary = CampaignState.serialize_payload()

	# Branch 1: Scatter Rain -> epilogue -> rolling auto_01.json written
	InputRouter._process(0.45)
	for _i: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	InputRouter._process(0.45)
	(collect_visible_buttons(stage._choices_box)[1]).pressed.emit()
	InputRouter._process(0.45)
	for _e: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))

	assert_true(CampaignState.ink_seals.has("seal_scatter_rain"), "Scatter branch stamped seal_scatter_rain")
	assert_true(bool(CampaignState.world_flags.get("ch01_completed", false)), "ch01_completed == true")
	assert_true(FileAccess.file_exists("user://saves/auto_01.json"), "Chapter completion wrote valid rolling auto_01.json")
	assert_eq(str(SaveManager.inspect_slot("auto_01", true).get("status", "")), "valid", "auto_01.json checksum valid")
	world._modals.close_modal()

	# Branch 2 from snapshot: Absorb Marrow -> seal_absorb_marrow
	CampaignState.deserialize_payload(pre_choice_snap)
	CampaignState.sandbox_mode = false
	stage.start_dialogue("dlg_ch01_marrow_choice", true)
	InputRouter._process(0.45)
	for _i2: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	InputRouter._process(0.45)
	(collect_visible_buttons(stage._choices_box)[0]).pressed.emit()
	InputRouter._process(0.45)
	for _e2: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_true(CampaignState.ink_seals.has("seal_absorb_marrow"), "Absorb branch stamped seal_absorb_marrow")
	world._modals.close_modal()

	# Save slot_01 twice (400 -> .bak, 888 -> .json), tamper slot_01.json, verify P0 modal & _crisis_bak_btn recovery!
	CampaignState.spirit_stones = 400
	assert_true(bool(SaveManager.save_manual_slot(1).get("ok", false)), "Saved slot_01 (400 -> .bak)")
	CampaignState.spirit_stones = 888
	assert_true(bool(SaveManager.save_manual_slot(1).get("ok", false)), "Saved slot_01 (888 -> .json)")

	var s1_path: String = "user://saves/slot_01.json"
	var raw_s1: String = FileAccess.get_file_as_string(s1_path)
	var tampered_s1: String = raw_s1.replace("\"spirit_stones\": 888", "\"spirit_stones\": 77777")
	var fw: FileAccess = FileAccess.open(s1_path, FileAccess.WRITE)
	fw.store_string(tampered_s1)
	fw.flush()
	fw.close()

	var lbad: Dictionary = SaveManager.load_slot("slot_01", false)
	assert_false(bool(lbad.get("ok", true)), "Tampered slot_01 rejected")
	assert_true(world._notify_overlay._crisis_modal.visible, "P0 crisis modal opened")
	assert_true(world._notify_overlay._crisis_bak_btn.visible, ".bak recovery button visible")

	# Click NotificationOverlay._crisis_bak_btn -> triggers QinglanWorld backup_recovery_chosen -> restores 400!
	world._notify_overlay._crisis_bak_btn.pressed.emit()
	CampaignState.sandbox_mode = false
	await step_frames(2)
	assert_eq(CampaignState.spirit_stones, 400, "Clicking _crisis_bak_btn restored spirit_stones == 400 from .bak")
	assert_eq(FileAccess.get_file_as_string(s1_path), tampered_s1, "Tampered slot_01.json preserved 100% intact")
	end_isolated_xdg_save_test()


func case_t3_w2_05_formation_swap_notify_lpf_flow() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.read_dialogues["dlg_ch01_wolf_king_intro"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", false)
	CampaignState.set_active_formation("scatter")

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud

	var banners: Array[Dictionary] = []
	var slips: Array[Dictionary] = []
	var cb_b: Callable = func(p: Dictionary) -> void: banners.append(p.duplicate(true))
	var cb_s: Callable = func(p: Dictionary) -> void: slips.append(p.duplicate(true))
	NotifyHub.combat_banner_pushed.connect(cb_b)
	NotifyHub.explore_slip_spawned.connect(cb_s)

	ctrl.engage_enemy_group("enc_boss_wolf_king", "pei_zhao", false)
	assert_true(ctrl.in_combat, "Boss combat active")

	# Open Z drawer in combat and switch to dizai (Major Advantage vs Boss fengyang)
	hud.toggle_quick_drawer()
	await step_frames(1)
	var dz_btn: Button = null
	for b: Button in collect_visible_buttons(hud.get("_drawer_vbox") as Node):
		if b.text.contains("地载阵"):
			dz_btn = b
			break
	assert_not_null(dz_btn, "Found 地载阵 button in Z drawer")
	if dz_btn != null:
		dz_btn.pressed.emit()

	assert_eq(CampaignState.active_formation_id, "dizai", "Switched to dizai in combat")
	assert_approx(ctrl.formation_switch_cd, 45.0, 0.01, "45.0s in-combat swap CD started")
	assert_false(ctrl.try_switch_formation("tianfu"), "Immediate second swap blocked by 45s CD")
	var c_eval: Dictionary = FormationRules.evaluate_counter("dizai", "fengyang")
	assert_eq(str(c_eval.get("relation", "")), "major_advantage", "dizai has major_advantage vs Wolf King fengyang")

	# Toggle Space Tactical Pause -> 900Hz LPF enabled on BGM_Bus & Ambient_UI_Bus
	var bgm_idx: int = AudioServer.get_bus_index("BGM_Bus")
	var amb_idx: int = AudioServer.get_bus_index("Ambient_UI_Bus")
	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused, "Tactical Pause active")
	assert_true(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "BGM_Bus 900Hz LPF enabled")
	assert_true(AudioServer.is_bus_effect_enabled(amb_idx, 0), "Ambient_UI_Bus 900Hz LPF enabled")

	NotifyHub.push_explore_slip("古窟秘宝_A", "数量 +1", "loot")
	NotifyHub.push_explore_slip("古窟秘宝_B", "数量 +1", "loot")
	assert_eq(slips.size(), 0, "Zero P3 slips emitted while in combat")

	# Defeat Boss while Tactical Pause was active -> victory MUST auto-clean 900Hz LPF!
	for ea: BattleActor in ctrl.enemy_actors:
		var eu: Dictionary = ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("group_id", "")) == "enc_boss_wolf_king" and ea.alive:
			ctrl.call("_apply_direct_enemy_hp_loss", eu, ea, ea.hp + 500, "metal", false, "")
	ctrl.call("_check_combat_resolution")

	assert_false(ctrl.tactical_paused, "Combat victory resets tactical_paused == false")
	assert_false(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "BGM_Bus 900Hz LPF disabled on combat exit")
	assert_false(AudioServer.is_bus_effect_enabled(amb_idx, 0), "Ambient_UI_Bus 900Hz LPF disabled on combat exit")

	# Wait 0.90s -> dlg_ch01_marrow_choice opens (P2 holds P3 slips!)
	await tree.create_timer(0.92).timeout
	assert_true(world._narrative.visible, "Marrow Choice opened")
	assert_eq(slips.size(), 0, "P3 slips remain held during P2 NarrativeStage")

	NotifyHub.combat_banner_pushed.disconnect(cb_b)
	NotifyHub.explore_slip_spawned.disconnect(cb_s)


func case_t3_w2_06_slot_reorder_save_load_hud_sync() -> void:
	if not begin_isolated_xdg_save_test():
		return
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("dizai", true)
	CampaignState.swap_formation_slots(1, 2) # ["pei_zhao", "gu_changqing", "shen_qinghe", ""]
	CampaignState.sandbox_mode = false

	assert_true(bool(SaveManager.save_manual_slot(5).get("ok", false)), "Saved reordered formation to slot_05")

	CampaignState.start_new_campaign("ask_heart")
	CampaignState.sandbox_mode = false
	assert_true(bool(SaveManager.load_slot("slot_05", false).get("ok", false)), "Loaded slot_05")
	CampaignState.sandbox_mode = true

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud
	hud.refresh_static_bindings()

	assert_eq(CampaignState.formation_slots, ["pei_zhao", "gu_changqing", "shen_qinghe", ""], "Restored reordered slots")
	var c0: Label = (hud._party_cards[0] as Dictionary)["name_lbl"] as Label
	var c1: Label = (hud._party_cards[1] as Dictionary)["name_lbl"] as Label
	assert_str_contains(c0.text, "裴照", "F1 card shows Pei Zhao")
	assert_str_contains(c0.text, "青龙阵眼", "F1 card shows 青龙阵眼 role")
	assert_str_contains(c1.text, "顾长青", "F2 card shows Gu Changqing")
	assert_str_contains(c1.text, "玄武镇岳", "F2 card shows 玄武镇岳 role")

	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	InputRouter._input(make_key_event(KEY_F2, true))
	assert_eq(ctrl.get_controlled_char_id(), "gu_changqing", "Pressing F2 selects slot-2 Gu Changqing")
	InputRouter._input(make_key_event(KEY_F1, true))
	assert_eq(ctrl.get_controlled_char_id(), "pei_zhao", "Pressing F1 selects slot-1 Pei Zhao")
	end_isolated_xdg_save_test()
