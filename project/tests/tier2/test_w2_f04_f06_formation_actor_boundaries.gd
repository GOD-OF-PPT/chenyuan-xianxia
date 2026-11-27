extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 2
# @e2e_features: F4, F6
## Worker 2 Tier 2 Boundary, Negative & Corner-Case Suite for F4 (Qimen Formations) and F6 (Actors & Spirit Pets).


func register_cases() -> void:
	add_case("T2-F04-01", 2, "F4", "baseline", "45.0s in-combat formation swap cooldown vs 0.0s OOC instant swap", "case_t2_f04_01_combat_swap_cooldown")
	add_case("T2-F04-02", 2, "F4", "baseline", "Locked, empty, and duplicate formation swaps consume zero 45s cooldown", "case_t2_f04_02_invalid_swap_zero_cd_waste")
	add_case("T2-F04-03", 2, "F4", "baseline", "Neutral formation counter boundaries (scatter, empty, identical)", "case_t2_f04_03_neutral_counter_boundaries")
	add_case("T2-F04-04", 2, "F4", "baseline", "Bucket C 1.28x offensive multiplier ceiling under max stacked formation & elixir buffs", "case_t2_f04_04_bucket_c_cap")
	add_case("T2-F04-05", 2, "F4", "baseline", "Out-of-bounds slot clamping & sparse formation_slots payload compaction", "case_t2_f04_05_slot_clamp_and_compaction")
	add_case("T2-F04-06", 2, "F4", "baseline", "Formation slot swap self/clamped index boundaries & locked set_active_formation guard", "case_t2_f04_06_swap_and_locked_set_guard")
	add_case("T2-F06-01", 2, "F6", "baseline", "Max 1 active spirit pet regression guard across pet swaps, re-syncs, and Boss cave", "case_t2_f06_01_max_one_spirit_pet_guard")
	add_case("T2-F06-03", 2, "F6", "baseline", "Defeated enemy corpse 1.15s ui_delta miasma dissolve & target ring drop", "case_t2_f06_03_enemy_death_dissolve")
	add_case("T2-F06-05", 2, "F6", "baseline", "Mist Wolf King Ward-Break knockdown (>4.0s stagger) & recovery state transition", "case_t2_f06_05_boss_stagger_knockdown")
	add_case("T2-F06-06", 2, "F6", "baseline", "Downed party ally non-dissolve persistence & post-combat 20% revive + meridian bruise", "case_t2_f06_06_downed_ally_vs_enemy_boundary")


func case_t2_f04_01_combat_swap_cooldown() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", false)
	CampaignState.set_active_formation("scatter")

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl

	# 1. Out-of-combat rapid swaps succeed immediately with 0s cooldown
	assert_false(ctrl.in_combat, "Initially out of combat")
	assert_true(ctrl.try_switch_formation("dizai"), "OOC swap scatter -> dizai succeeds")
	assert_approx(ctrl.formation_switch_cd, 0.0, 0.001, "OOC swap sets 0.0s formation_switch_cd")
	assert_true(ctrl.try_switch_formation("tianfu"), "Immediate OOC swap dizai -> tianfu succeeds")
	assert_true(ctrl.try_switch_formation("scatter"), "Immediate OOC swap tianfu -> scatter succeeds")

	# 2. Enter active combat -> first swap succeeds and arms 45.0s cooldown
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", ctrl.get_controlled_actor_pos() + Vector2(300.0, 0.0), "enc_cd_test")
	assert_not_null(wolf, "Spawned test enemy")
	ctrl.engage_enemy_group("enc_cd_test", "gu_changqing", false)
	assert_true(ctrl.in_combat, "Entered combat")

	assert_true(ctrl.try_switch_formation("dizai"), "First in-combat swap scatter -> dizai returns true")
	assert_eq(CampaignState.active_formation_id, "dizai", "active_formation_id updated to dizai")
	assert_approx(ctrl.formation_switch_cd, 45.0, 0.01, "formation_switch_cd armed to 45.0s")

	# Step 44.5s -> 0.5s remaining -> swap MUST be rejected
	ctrl.call("_step_global_timers", 44.5)
	assert_approx(ctrl.formation_switch_cd, 0.5, 0.02, "0.5s cooldown remaining at 44.5s")
	assert_false(ctrl.try_switch_formation("tianfu"), "Swap rejected at 44.5s (0.5s CD remaining)")
	assert_eq(CampaignState.active_formation_id, "dizai", "active_formation_id stays dizai when swap rejected")

	# Step +0.6s (total 45.1s) -> 0.0s remaining -> swap MUST succeed and re-arm 45.0s
	ctrl.call("_step_global_timers", 0.6)
	assert_approx(ctrl.formation_switch_cd, 0.0, 0.001, "Cooldown reaches 0.0s at 45.1s")
	assert_true(ctrl.try_switch_formation("tianfu"), "Swap dizai -> tianfu succeeds after 45.0s CD")
	assert_eq(CampaignState.active_formation_id, "tianfu", "active_formation_id updated to tianfu")
	assert_approx(ctrl.formation_switch_cd, 45.0, 0.01, "Second in-combat swap re-arms 45.0s CD")


func case_t2_f04_02_invalid_swap_zero_cd_waste() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.unlock_formation("dizai", true)
	assert_eq(CampaignState.unlocked_formations, ["scatter", "dizai"], "Only scatter and dizai unlocked")

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.spawn_enemy_unit("rot_wolf", ctrl.get_controlled_actor_pos() + Vector2(280.0, 0.0), "enc_inv_cd")
	ctrl.engage_enemy_group("enc_inv_cd", "gu_changqing", false)
	ctrl.formation_switch_cd = 0.0

	assert_false(ctrl.try_switch_formation("fengyang"), "Locked formation fengyang rejected")
	assert_approx(ctrl.formation_switch_cd, 0.0, 0.001, "Locked formation attempt consumes 0.0s CD")

	assert_false(ctrl.try_switch_formation(""), "Empty formation ID rejected")
	assert_approx(ctrl.formation_switch_cd, 0.0, 0.001, "Empty formation ID consumes 0.0s CD")

	assert_false(ctrl.try_switch_formation("dizai"), "Redundant swap to already-active dizai rejected")
	assert_eq(CampaignState.active_formation_id, "dizai", "active_formation_id unchanged")
	assert_approx(ctrl.formation_switch_cd, 0.0, 0.001, "Redundant swap consumes 0.0s CD")

	# Valid swap afterward still works immediately because CD was not wasted
	assert_true(ctrl.try_switch_formation("scatter"), "Valid swap to scatter succeeds immediately")
	assert_approx(ctrl.formation_switch_cd, 45.0, 0.01, "Valid swap arms 45.0s CD")


func case_t2_f04_03_neutral_counter_boundaries() -> void:
	var neutral_cases: Array[Array] = [
		["scatter", "tianfu"],
		["dizai", "scatter"],
		["scatter", "scatter"],
		["tianfu", "tianfu"],
		["dizai", "dizai"],
		["", "dizai"],
		["tianfu", ""],
		["", ""],
		["unknown_form", "dizai"],
	]
	for pair: Array in neutral_cases:
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		var res: Dictionary = FormationRules.evaluate_counter(a, b)
		assert_eq(str(res.get("relation", "")), "neutral", "(%s vs %s) relation == neutral" % [a, b])
		assert_approx(float(res.get("damage_mult", 0.0)), 1.0, 0.0001, "(%s vs %s) damage_mult == 1.0" % [a, b])
		assert_approx(float(res.get("damage_taken_mult", 0.0)), 1.0, 0.0001, "(%s vs %s) damage_taken_mult == 1.0" % [a, b])


func case_t2_f04_04_bucket_c_cap() -> void:
	var cdef: Dictionary = DataDB.get_character("gu_changqing")
	var rdef: Dictionary = DataDB.get_realm("qi_refining_2")
	var fdef: Dictionary = DataDB.get_formation("tianfu")
	var slot1_mod: Dictionary = FormationRules.get_slot_modifiers(fdef, 1) # damage_mult = 1.18
	var major_adv: Dictionary = FormationRules.evaluate_counter("tianfu", "dizai") # damage_mult = 1.10
	var elixir: Dictionary = {
		"item_id": "item_juqi_pellet_flawless",
		"power_pct": 0.12,
		"max_hp_pct": 0.10,
	}
	# nd_gu_a3 (+8% dmg) + marrow absorb (+8% dmg) => 1.18 * 1.10 * 1.12 * 1.16 = 1.686x unclamped!
	var talents: Dictionary = {
		"damage_pct": 0.16,
		"mastery_pct": 0.05,
	}
	var sheet: Dictionary = StatLedger.compute_character_sheet(
		cdef,
		rdef,
		{"str": 5, "spi": 5},
		"flawless",
		[],
		DataDB.equip_sets,
		talents,
		slot1_mod,
		major_adv,
		elixir,
		0,
		0
	)
	var bbreak: Dictionary = sheet.get("bucket_breakdown", {}) as Dictionary
	var bc_mult: float = float(bbreak.get("bucket_c_offense_mult", 0.0))
	assert_le(bc_mult, 1.2801, "Bucket C offense multiplier clamped <= 1.28")
	assert_approx(bc_mult, 1.28, 0.001, "Extreme stacked buffs hit exact 1.28x ceiling")


func case_t2_f04_05_slot_clamp_and_compaction() -> void:
	var fdef: Dictionary = DataDB.get_formation("dizai")
	var low_mod: Dictionary = FormationRules.get_slot_modifiers(fdef, -5)
	var high_mod: Dictionary = FormationRules.get_slot_modifiers(fdef, 99)
	assert_eq(int(low_mod.get("slot_index", 0)), 1, "Out-of-bounds slot -5 clamps to slot 1")
	assert_eq(str(low_mod.get("role_title", "")), "青龙阵眼", "Slot -5 receives slot 1 role_title")
	assert_eq(int(high_mod.get("slot_index", 0)), 4, "Out-of-bounds slot 99 clamps to slot 4")
	assert_eq(str(high_mod.get("role_title", "")), "白虎破锐", "Slot 99 receives slot 4 role_title")

	CampaignState.recruit_companion("shen_qinghe", 2)
	var snap: Dictionary = CampaignState.serialize_payload()
	snap["formation_slots"] = ["gu_changqing", "", "shen_qinghe", ""]
	snap["controlled_slot"] = 4

	CampaignState.deserialize_payload(snap)
	CampaignState.sandbox_mode = true # Re-assert Lock 2 immediately after deserialize_payload!

	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "shen_qinghe", "", ""],
		"deserialize_payload compacts sparse slot 3 into slot 2"
	)
	assert_eq(CampaignState.controlled_slot, 1, "Invalid empty controlled_slot 4 resets safely to 1")


func case_t2_f04_06_swap_and_locked_set_guard() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	assert_eq(CampaignState.formation_slots, ["gu_changqing", "pei_zhao", "shen_qinghe", ""], "Initial trio order")

	# Attempting set_active_formation on an unlocked=false formation must be ignored
	CampaignState.set_active_formation("fengyang")
	assert_eq(CampaignState.active_formation_id, "scatter", "set_active_formation ignores locked formation fengyang")

	# Swapping identical slot indices or clamped out-of-range indices (-3 -> 1, 1 -> 1) is a safe no-op
	CampaignState.swap_formation_slots(-3, 1)
	assert_eq(
		CampaignState.formation_slots,
		["gu_changqing", "pei_zhao", "shen_qinghe", ""],
		"Swapping clamped (-3, 1) is a safe no-op"
	)

	# Valid swap between slot 1 and slot 2 updates role modifiers cleanly
	CampaignState.unlock_formation("dizai", true)
	CampaignState.swap_formation_slots(1, 2)
	assert_eq(
		CampaignState.formation_slots,
		["pei_zhao", "gu_changqing", "shen_qinghe", ""],
		"swap_formation_slots(1, 2) swaps Pei Zhao and Gu Changqing"
	)
	assert_eq(CampaignState.get_member_formation_slot("gu_changqing"), 2, "Gu Changqing is now in tank slot 2")
	var gu_sh: Dictionary = ((CampaignState.party_members["gu_changqing"] as Dictionary).get("sheet", {}) as Dictionary)
	assert_gt(float(gu_sh.get("threat_mult", 0.0)), 1.70, "Gu Changqing inherits slot 2 玄武镇岳 1.80x threat aura")


func _count_pet_actors_in_ysort(ysort: Node2D) -> int:
	var count: int = 0
	for ch: Node in ysort.get_children():
		if ch is BattleActor and not ch.is_queued_for_deletion():
			if (ch as BattleActor).faction == "pet":
				count += 1
	return count


func case_t2_f06_01_max_one_spirit_pet_guard() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl

	assert_eq(_count_pet_actors_in_ysort(world._ysort_root), 0, "Zero pet actors before contracting starter pet")

	CampaignState.contract_spirit_pet("pet_fire_fox")
	ctrl.sync_party_roster_in_place()
	await step_frames(2)
	assert_eq(_count_pet_actors_in_ysort(world._ysort_root), 1, "Exactly 1 pet actor after contracting pet_fire_fox")

	# Switch to pet_spirit_turtle and call sync_party_roster_in_place 3 times
	CampaignState.contract_spirit_pet("pet_spirit_turtle")
	for _i: int in range(3):
		ctrl.sync_party_roster_in_place()
	await step_frames(2)
	assert_eq(
		_count_pet_actors_in_ysort(world._ysort_root),
		1,
		"Strictly 1 active pet actor after switching fox -> turtle and triple re-sync"
	)

	# Load cangmu_cave Boss arena (never spawns a 2nd decorative fox from master_b!)
	world.load_zone("cangmu_cave", "stele_wolf_altar", false)
	await step_frames(3)
	assert_eq(_count_pet_actors_in_ysort(world._ysort_root), 1, "Strictly 1 pet actor in cangmu_cave Boss arena")

	var pet_state_keys: int = 0
	var allied_entities: int = 0
	for k_var: Variant in ctrl.unit_states.keys():
		var u: Dictionary = ctrl.unit_states[str(k_var)] as Dictionary
		var fac: String = str(u.get("faction", ""))
		if fac == "pet":
			pet_state_keys += 1
			allied_entities += 1
		elif fac == "party":
			allied_entities += 1

	assert_eq(pet_state_keys, 1, "unit_states contains at most 1 pet_* state entry")
	assert_le(allied_entities, 4, "Total Ch1 allied field entities <= 4 (3 party + 1 pet)")


func case_t2_f06_03_enemy_death_dissolve() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl

	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", ctrl.get_controlled_actor_pos() + Vector2(180.0, 0.0), "enc_dissolve")
	assert_not_null(wolf, "Spawned rot_wolf")
	if wolf == null:
		return
	ctrl.engage_enemy_group("enc_dissolve", "gu_changqing", false)
	ctrl.set_locked_enemy(wolf.actor_id, true)
	assert_true(wolf.is_targeted, "rot_wolf initially targeted")

	var eu: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	ctrl.call("_apply_direct_enemy_hp_loss", eu, wolf, wolf.hp + 50, "metal", true, "")
	assert_false(wolf.alive, "rot_wolf alive == false after lethal damage")
	assert_false(wolf.is_targeted, "Defeated enemy immediately drops targeting ring")

	# Step visuals with combat_delta == 0.0 and ui_delta == 0.25 -> dissolves smoothly over 1.15s
	wolf.step_visuals(0.0, 0.25, false)
	assert_eq(wolf._anim_state, "down", "Defeated enemy enters 'down' collapse state")
	assert_true(wolf.visible, "Enemy still mid-dissolve at 0.25s (< 1.15s)")
	assert_lt(wolf._sprite.modulate.a, 0.90, "Dissolve alpha < 0.90 at 0.25s")

	for _s: int in range(4):
		wolf.step_visuals(0.0, 0.25, false)
	assert_false(wolf.visible, "Defeated enemy becomes visible == false at 1.25s (>= 1.15s, zero standing corpse)")


func case_t2_f06_05_boss_stagger_knockdown() -> void:
	var boss: BattleActor = BattleActor.new()
	boss.position = Vector2(800.0, 500.0)
	mount_node(boss)
	boss.setup_actor("boss_mist_wolf_king_1", "enemy", "雾隐狼王", "boss_mist_wolf_king", 1.0)
	boss.is_boss = true
	boss.alive = true

	boss.stagger_timer = 5.8 # > 4.0s initial knockdown phase of 6.0s Ward-Break stagger
	boss.step_visuals(0.20, 0.20, false)
	assert_eq(boss._anim_state, "down", "Mist Wolf King enters 'down' knockdown while stagger_timer > 4.0s")

	boss.stagger_timer = 0.0
	boss.step_visuals(0.20, 0.20, false)
	assert_eq(boss._anim_state, "idle", "Mist Wolf King cleanly recovers from 'down' to 'idle' once stagger expires")


func case_t2_f06_06_downed_ally_vs_enemy_boundary() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", ctrl.get_controlled_actor_pos() + Vector2(120.0, 0.0), "enc_ally_down")
	ctrl.engage_enemy_group("enc_ally_down", "gu_changqing", false)

	# Down Shen Qinghe mid-combat
	ctrl.call("_apply_damage_to_ally", "shen_qinghe", shen, shen.max_hp + 200, "腐瘴灰狼", "扑咬", "wood", false, false, false)
	assert_false(shen.alive, "Shen Qinghe downed (alive == false)")

	for _k: int in range(6):
		shen.step_visuals(0.25, 0.25, false)
	assert_eq(shen._anim_state, "down", "Downed party ally stays in 'down' kneel state")
	assert_true(shen.visible, "Downed party ally remains visible on field (never miasma-dissolved like enemies)")
	assert_approx(shen._sprite.modulate.a, 0.72, 0.02, "Downed party ally renders at 0.72 wounded alpha")

	# Defeat enemy -> combat victory revives Shen at 20% HP and adds +1 meridian_bruise
	var eu: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	ctrl.call("_apply_direct_enemy_hp_loss", eu, wolf, wolf.hp + 100, "metal", false, "")
	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	assert_false(ctrl.in_combat, "Combat resolved on pack kill")
	assert_true(shen.alive, "Downed Shen Qinghe automatically revives at 20% HP post-combat")
	var shen_m: Dictionary = CampaignState.party_members["shen_qinghe"] as Dictionary
	assert_eq(int(shen_m.get("meridian_bruise", 0)), 1, "Post-combat revive increments meridian_bruise to 1")
	var expected_hp: int = maxi(15, int(round(float(shen.max_hp) * 0.20)))
	assert_eq(shen.hp, expected_hp, "Revived HP equals max(15, round(0.20 * post-bruise max_hp))")
