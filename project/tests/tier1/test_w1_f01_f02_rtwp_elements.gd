extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 1
# @e2e_features: F1, F2


func register_cases() -> void:
	add_case("T1-F01-01", 1, "F1", "baseline", "Seamless preemptive skill pull (+15% haste & 1.5x ward break) vs proximity aggro pull", "case_t1_f01_01_pull_modes")
	add_case("T1-F01-02", 1, "F1", "baseline", "Moving auto-attack (melee/ranged) without LMB click & WASD zero-delay cast cancel preserving attack_timer", "case_t1_f01_02_auto_attack_and_stutter_step")
	add_case("T1-F01-03", 1, "F1", "baseline", "1.50s base GCD on instant skill & dynamic haste compression with fox + preemptive haste", "case_t1_f01_03_gcd_and_haste")
	add_case("T1-F01-04", 1, "F1", "baseline", "Off-GCD Q interrupt fires mid-GCD without resetting GCD, locks out Amber-Gold cast 3.0s & shreds bonus ward", "case_t1_f01_04_off_gcd_interrupt")
	add_case("T1-F01-05", 1, "F1", "baseline", "Off-GCD Mouseover pill 5 heals hovered ally, cleanses miasma + 10s immunity & starts 30s pill cooldown", "case_t1_f01_05_mouseover_pill")
	add_case("T1-F01-06", 1, "F1", "baseline", "Leash reset (>560px) + victory 20% HP auto-revive with meridian bruise + >=3.0s OOC HP/MP regen", "case_t1_f01_06_leash_revive_ooc_regen")
	add_case("T1-F02-01", 1, "F2", "baseline", "All 5 element counter pairs grant 1.25x damage & 2.50x ward break in RtwpSimStep and live combat", "case_t1_f02_01_five_element_counters")
	add_case("T1-F02-02", 1, "F2", "baseline", "Active Ward 0.75x DR -> 0 Ward cancels uninterruptible Boss cast & opens 6.0s stagger (+35% dmg) + 2.0s stun", "case_t1_f02_02_ward_break_and_stagger")
	add_case("T1-F02-03", 1, "F2", "baseline", "Post-stagger 6.0s Ward recovery + Mist Wolf King <=84% pup adds & <=55% Phase 2 Ward restoration", "case_t1_f02_03_ward_regen_and_boss_phases")
	add_case("T1-F02-04", 1, "F2", "baseline", "Wood -> Fire generative synergy consumes 6s Mother Seal for 165px AoE fire burst, burn DoT & +15 Team Qi", "case_t1_f02_04_wood_fire_synergy")
	add_case("T1-F02-05", 1, "F2", "baseline", "Remaining 4 generative chains: fire->earth, earth->metal, metal->water, water->wood effects & +15 Qi each", "case_t1_f02_05_all_other_synergies")


func _spawn_clean_arena(zone_id: String = "qinglan_pass") -> QinglanWorld:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	CampaignState.cleared_encounters["enc_cave_pack_1"] = true
	CampaignState.cleared_encounters["enc_cave_golem"] = true
	CampaignState.world_flags["wolf_king_defeated"] = true
	var world: QinglanWorld = spawn_qinglan_world(zone_id, "stele_temple_courtyard") as QinglanWorld
	world.set_physics_process(false)
	world._combat_ctrl.obstacle_circles.clear()
	return world


func _set_physical_key_held(keycode: Key, held: bool) -> void:
	var ev: InputEventKey = make_key_event(keycode, held)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func case_t1_f01_01_pull_modes() -> void:
	# 1. Preemptive cast-time pull from OOC -> arms 4.0s preemptive buff & combat state
	var world_a: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl_a: RtwpCombatController = world_a._combat_ctrl
	var gu_a: BattleActor = ctrl_a.get_controlled_actor()
	var golem_cast: BattleActor = ctrl_a.spawn_enemy_unit("wood_golem", gu_a.position + Vector2(310.0, 0.0), "enc_pull_cast")
	ctrl_a.set_locked_enemy(golem_cast.actor_id, false)

	assert_false(ctrl_a.in_combat, "Initially out of combat before preemptive pull")
	ctrl_a.trigger_hotkey_slot("4") # sk_gu_gale_blades (1.1s cast, range 370px)
	assert_true(ctrl_a.in_combat, "Preemptive OOC skill pull enters combat immediately")
	assert_true(NotifyHub.combat_active, "NotifyHub.combat_active set true on preemptive pull")
	assert_true(InputRouter.combat_engaged, "InputRouter.combat_engaged set true on preemptive pull")
	assert_approx(ctrl_a.preemptive_buff_timer, 4.0, 0.05, "Preemptive pull grants 4.0s buff")

	# 2. Compare first-hit ward break on instant OOC opener vs proximity overwatch aggro
	reset_sandbox_campaign("cultivation")
	var world_b: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl_b: RtwpCombatController = world_b._combat_ctrl
	var gu_b: BattleActor = ctrl_b.get_controlled_actor()
	var golem_pre: BattleActor = ctrl_b.spawn_enemy_unit("wood_golem", gu_b.position + Vector2(320.0, 0.0), "enc_pull_inst")
	var ward_init: float = golem_pre.ward_current
	ctrl_b.set_locked_enemy(golem_pre.actor_id, false)
	ctrl_b.trigger_hotkey_slot("1") # sk_gu_qingming_qi (metal vs wood, ward_damage 28)
	var ward_loss_preemptive: float = ward_init - golem_pre.ward_current

	reset_sandbox_campaign("cultivation")
	var world_c: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl_c: RtwpCombatController = world_c._combat_ctrl
	var gu_c: BattleActor = ctrl_c.get_controlled_actor()
	var _prox_shaman: BattleActor = ctrl_c.spawn_enemy_unit("miasma_shaman", gu_c.position + Vector2(180.0, 0.0), "enc_pull_prox")
	var golem_prox: BattleActor = ctrl_c.spawn_enemy_unit("wood_golem", gu_c.position + Vector2(300.0, 0.0), "enc_pull_prox")
	ctrl_c.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
	assert_true(ctrl_c.in_combat, "Walking inside aggro_radius_px triggers proximity combat")
	assert_approx(ctrl_c.preemptive_buff_timer, 0.0, 0.001, "Proximity aggro pull grants 0.0s preemptive buff")

	ctrl_c.set_locked_enemy(golem_prox.actor_id, false)
	ctrl_c.trigger_hotkey_slot("1")
	var ward_loss_proximity: float = ward_init - golem_prox.ward_current
	assert_gt(ward_loss_proximity, 10.0, "Proximity counter hit shreds positive ward")
	assert_approx(ward_loss_preemptive / ward_loss_proximity, 1.50, 0.02, "Preemptive opener applies 1.50x ward break multiplier")
	record_metric("ward_loss_preemptive", ward_loss_preemptive)
	record_metric("ward_loss_proximity", ward_loss_proximity)


func case_t1_f01_02_auto_attack_and_stutter_step() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var shen_m: Dictionary = CampaignState.party_members["shen_qinghe"] as Dictionary
	shen_m["ai_preset_index"] = 2 # conserve_mana so Shen auto-attacks at healthy HP
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	gu.position = Vector2(1200.0, 650.0)
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", Vector2(1325.0, 650.0), "enc_aa") # 125px <= 145px melee
	var eu_wolf: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	eu_wolf["max_hp"] = 900
	eu_wolf["hp"] = 900
	wolf.max_hp = 900
	wolf.hp = 900
	shen.position = Vector2(1005.0, 650.0) # 320px <= 380px ranged

	ctrl.engage_enemy_group("enc_aa", "gu_changqing", false)
	ctrl.set_locked_enemy(wolf.actor_id, true)
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	u_gu["attack_timer"] = 0.20
	u_shen["attack_timer"] = 0.20
	u_shen["gcd_timer"] = 1.20 # block GCD skill so Shen fires pure ranged auto-attack

	var hp_before_gu: int = wolf.hp
	ctrl.step_world_and_combat(0.25, QinglanWorld.ZONE_BOUNDS)
	assert_lt(float(wolf.hp), float(hp_before_gu), "Melee & ranged auto-attacks fire automatically without LMB clicks")
	assert_gt(float(u_gu["attack_timer"]), 1.0, "Gu attack_timer cycled to attack_interval (~1.75s) after auto-attack")
	assert_gt(float(u_shen["attack_timer"]), 1.0, "Shen attack_timer cycled to ranged attack_interval (~1.85s) from 320px")

	# Drain any residual auto-attack Crit _hitstop_timer (~45ms) before testing WASD cast-cancel & stutter-step
	for _hs: int in range(6):
		if float(obj_get(ctrl, "_hitstop_timer", 0.0)) <= 0.0:
			break
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	# Start 1.1s cast skill sk_gu_gale_blades, then move via WASD while attack_timer == 0.60s
	u_gu["gcd_timer"] = 0.0
	gu.mp = gu.max_mp
	ctrl.trigger_hotkey_slot("4")
	assert_true(bool(u_gu.get("casting", false)) and gu.is_casting, "Gu started casting sk_gu_gale_blades")

	u_gu["attack_timer"] = 0.60
	var x_before: float = gu.position.x
	var wasd_clk0: float = ctrl.combat_clock_sec
	_set_physical_key_held(KEY_D, true)
	var move_vec: Vector2 = InputRouter.get_movement_vector()
	for _ws: int in range(4):
		if ctrl.combat_clock_sec - wasd_clk0 >= 0.095:
			break
		ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)
	_set_physical_key_held(KEY_D, false)

	assert_gt(move_vec.x, 0.5, "KEY_D produces +X WASD movement vector")
	assert_false(bool(u_gu.get("casting", false)), "WASD move immediately cancels unit_state casting")
	assert_false(gu.is_casting, "WASD move immediately cancels BattleActor.is_casting (zero-delay dodge)")
	assert_gt(gu.position.x, x_before + 5.0, "Gu moved right during WASD step")
	var atk_after: float = float(u_gu.get("attack_timer", 9.9))
	assert_approx(atk_after, 0.50, 0.03, "Stutter-step (走A) preserves attack_timer countdown without resetting to 1.75s")


func case_t1_f01_03_gcd_and_haste() -> void:
	CampaignState.contract_spirit_pet("pet_fire_fox")
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(180.0, 0.0), "enc_gcd")
	var eu_wolf: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	eu_wolf["max_hp"] = 1200
	eu_wolf["hp"] = 1200
	wolf.max_hp = 1200
	wolf.hp = 1200

	ctrl.engage_enemy_group("enc_gcd", "gu_changqing", false)
	ctrl.set_locked_enemy(wolf.actor_id, false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.party_haste_buff_timer = 0.0
	ctrl.party_haste_buff_val = 0.0

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var gu_sheet: Dictionary = u_gu["sheet"] as Dictionary
	var starter_haste: float = float(gu_sheet.get("haste_pct", 0.0))
	assert_gt(starter_haste, 0.05, "Starter 3pc set_qinglan_walker grants positive baseline haste_pct")

	# Isolate 0.0% haste baseline first -> exact 1.50s base GCD
	gu_sheet["haste_pct"] = 0.0
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	gu.mp = gu.max_mp

	ctrl.trigger_hotkey_slot("1") # sk_gu_qingming_qi (instant, uses_gcd: true, cd: 2.5s)
	var base_gcd: float = float(u_gu.get("gcd_timer", 0.0))
	assert_approx(base_gcd, 1.50, 0.01, "0% haste instant skill starts exact 1.50s base GCD")
	assert_approx(float((u_gu["cooldowns"] as Dictionary).get("sk_gu_qingming_qi", 0.0)), 2.50, 0.01, "Skill cooldown set to 2.50s")

	# Apply fox haste (+14%) + preemptive buff (+15% -> +29% total haste)
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	gu.mp = gu.max_mp
	ctrl.trigger_pet_manual_skill(2) # sk_pet_fox_haste (+0.14 haste for 6.0s)
	assert_approx(ctrl.party_haste_buff_val, 0.14, 0.005, "Fox Ctrl+2 applies +14% party haste buff")
	ctrl.preemptive_buff_timer = 3.5

	ctrl.trigger_hotkey_slot("1")
	var hasted_gcd: float = float(u_gu.get("gcd_timer", 0.0))
	assert_approx(hasted_gcd, 1.50 / 1.29, 0.02, "+29% effective haste compresses GCD to 1.50 / 1.29 ~= 1.163s")
	assert_lt(hasted_gcd, base_gcd - 0.25, "Hasted GCD is strictly faster than 1.50s base GCD")
	assert_ge(hasted_gcd, 1.00, "Hasted GCD respects 1.00s GCD floor")
	record_metric("base_gcd_sec", base_gcd)
	record_metric("hasted_gcd_sec", hasted_gcd)


func case_t1_f01_04_off_gcd_interrupt() -> void:
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", gu.position + Vector2(210.0, 0.0), "enc_int")
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	eu_sh["ward_max"] = 200.0
	eu_sh["ward_current"] = 200.0
	shaman.ward_max = 200.0
	shaman.ward_current = 200.0

	ctrl.engage_enemy_group("enc_int", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.set_locked_enemy(shaman.actor_id, false)

	# Step once so shaman begins Amber-Gold interruptible sk_enemy_miasma_bolt (2.10s)
	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)
	assert_true(shaman.is_casting and shaman.cast_interruptible, "Shaman started Amber-Gold interruptible cast")
	assert_approx(shaman.cast_duration, 2.10, 0.05, "sk_enemy_miasma_bolt cast duration is 2.10s")

	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(payload: Dictionary) -> void: banners.append(payload))

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	u_gu["gcd_timer"] = 1.25
	gu.mp = gu.max_mp

	ctrl.trigger_hotkey_slot("Q") # sk_gu_throat_seal (uses_gcd: false, is_interrupt: true)
	assert_approx(float(u_gu.get("gcd_timer", 0.0)), 1.25, 0.001, "Off-GCD Q fires mid-GCD and leaves gcd_timer=1.25s untouched")
	assert_false(shaman.is_casting, "Off-GCD Q aborts shaman cast immediately")
	assert_approx(shaman.lockout_timer, 3.0, 0.01, "Interrupt applies 3.0s spell lockout (破功封脉)")

	# Bonus ward shred = max(35.0, 200 * 0.22) = 44.0, plus metal counter skill ward_damage 22 * 2.5 * ward_break_mult
	var wb_mult: float = float((u_gu["sheet"] as Dictionary).get("ward_break_mult", 1.0))
	var expected_ward_loss: float = 44.0 + 22.0 * 2.50 * wb_mult
	var ward_lost: float = 200.0 - shaman.ward_current
	assert_approx(ward_lost, expected_ward_loss, 0.5, "Interrupt shreds bonus ward max(35, 22% ward_max) + skill ward damage")

	var saw_int_banner: bool = false
	for b: Dictionary in banners:
		if str(b.get("category", "")) == "interrupt":
			saw_int_banner = true
	assert_true(saw_int_banner, "NotifyHub emitted 'interrupt' combat banner")


func case_t1_f01_05_mouseover_pill() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var _wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(200.0, 0.0), "enc_pill")
	ctrl.engage_enemy_group("enc_pill", "gu_changqing", false)

	var cur_cnt: int = CampaignState.get_item_count("item_qingmu_pill")
	if cur_cnt > 0:
		CampaignState.remove_item("item_qingmu_pill", cur_cnt)
	CampaignState.add_item("item_qingmu_pill", 2, true)
	CampaignState.quick_pill_5_id = "item_qingmu_pill"

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	shen.hp = 40
	u_shen["miasma_stacks"] = 2
	shen.miasma_stacks = 2
	u_gu["gcd_timer"] = 1.30
	ctrl.pill_cooldown_timer = 0.0
	ctrl.hovered_ally_id = "shen_qinghe"

	ctrl.trigger_hotkey_slot("5")
	assert_eq(CampaignState.get_item_count("item_qingmu_pill"), 1, "Consumed exactly 1 item_qingmu_pill")
	assert_approx(float(u_gu.get("gcd_timer", 0.0)), 1.30, 0.001, "Instant combat pill is off-GCD and leaves gcd_timer=1.30s untouched")
	assert_gt(float(shen.hp), 40.0, "Mouseover pill healed hovered shen_qinghe")
	assert_eq(shen.miasma_stacks, 0, "Qingmu pill cleansed shen_qinghe miasma stacks to 0")
	assert_eq(int(u_shen.get("miasma_stacks", -1)), 0, "shen_qinghe unit_state miasma_stacks == 0")
	assert_approx(float(u_shen.get("miasma_immune_timer", 0.0)), 10.0, 0.05, "Qingmu pill grants 10.0s miasma immunity")
	assert_approx(ctrl.pill_cooldown_timer, 30.0, 0.05, "Pill sets 30.0s shared toxicity cooldown")


func case_t1_f01_06_leash_revive_ooc_regen() -> void:
	# Subcase A: Pulling > leash_radius_px resets enemy HP/Ward & drops combat
	CampaignState.recruit_companion("shen_qinghe", 2)
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	var home_pt: Vector2 = Vector2(900.0, 650.0)
	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", home_pt, "enc_leash") # leash 580px
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_leash", "gu_changqing", false)
	eu_sh["hp"] = 90
	shaman.hp = 90
	eu_sh["ward_current"] = 25.0
	shaman.ward_current = 25.0
	shaman.position = home_pt + Vector2(610.0, 0.0) # 610px > 580px leash

	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)
	assert_false(bool(eu_sh.get("engaged", true)), "Enemy exceeding leash_radius_px disengages")
	assert_eq(shaman.hp, shaman.max_hp, "Leashed enemy restores 100% HP")
	assert_approx(shaman.ward_current, shaman.ward_max, 0.01, "Leashed enemy restores 100% Ward")
	assert_false(ctrl.in_combat, "Party exits combat when sole engaged pack leashes")
	shaman.alive = false

	# Subcase B: Downed companion revives at 20% HP with +1 meridian_bruise (-6% max_hp) + 3.0s OOC regen
	var clean_shen_max_hp: int = shen.max_hp
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(120.0, 0.0), "enc_victory_rev")
	var eu_wolf: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_victory_rev", "gu_changqing", false)

	shen.hp = 0
	shen.alive = false
	gu.hp = 45
	gu.mp = 18

	ctrl._apply_direct_enemy_hp_loss(eu_wolf, wolf, 9999, "metal")
	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)

	assert_false(ctrl.in_combat, "Defeating pack resolves combat victory")
	assert_true(shen.alive, "Downed shen_qinghe auto-revives on combat victory")
	var shen_m: Dictionary = CampaignState.party_members["shen_qinghe"] as Dictionary
	assert_eq(int(shen_m.get("meridian_bruise", 0)), 1, "Revival inflicts +1 meridian_bruise stack")
	var bruised_max_hp: int = int((shen_m.get("sheet", {}) as Dictionary).get("max_hp", 0))
	assert_lt(float(bruised_max_hp), float(clean_shen_max_hp), "Meridian bruise reduces max_hp (~6% per stack)")
	assert_eq(shen.hp, maxi(15, int(round(float(shen.max_hp) * 0.20))), "Shen revives at exact 20% max_hp")

	var gu_hp_post_win: int = gu.hp
	var gu_mp_post_win: int = gu.mp
	for _i: int in range(7):
		ctrl.step_world_and_combat(0.50, QinglanWorld.ZONE_BOUNDS) # 3.5s OOC >= 3.0s threshold
	assert_gt(float(gu.hp), float(gu_hp_post_win), "OOC >= 3.0s automatically regenerates party HP")
	assert_gt(float(gu.mp), float(gu_mp_post_win), "OOC >= 3.0s automatically regenerates party MP")


func case_t1_f02_01_five_element_counters() -> void:
	var pairs: Array[Array] = [
		["metal", "wood"],
		["wood", "earth"],
		["earth", "water"],
		["water", "fire"],
		["fire", "metal"],
	]
	for p: Array in pairs:
		var atk_e: String = str(p[0])
		var def_e: String = str(p[1])
		var res: Dictionary = RtwpSimStep.evaluate_element_matchup(atk_e, def_e, 1.20)
		assert_eq(str(res.get("relation", "")), "counter", "%s -> %s is counter" % [atk_e, def_e])
		assert_approx(float(res.get("damage_mult", 0.0)), 1.25, 0.001, "%s -> %s grants 1.25x damage_mult" % [atk_e, def_e])
		assert_approx(float(res.get("ward_break_mult", 0.0)), 2.50 * 1.20, 0.001, "%s -> %s grants 2.50x * mastery ward_break_mult" % [atk_e, def_e])

	# Verify live combat ward shred ratio: metal (counter) vs water (neutral) against wood ward
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(180.0, 0.0), "enc_cnt")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_cnt", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0

	eu_g["ward_max"] = 300.0
	eu_g["ward_current"] = 300.0
	golem.ward_max = 300.0
	golem.ward_current = 300.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, golem, 25.0, 1.0, "water", 24.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var neutral_shred: float = 300.0 - golem.ward_current

	eu_g["ward_current"] = 300.0
	golem.ward_current = 300.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, golem, 25.0, 1.0, "metal", 24.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var counter_shred: float = 300.0 - golem.ward_current
	assert_approx(counter_shred / neutral_shred, 2.50, 0.01, "Live counter hit shreds exact 2.5x ward of neutral hit")


func case_t1_f02_02_ward_break_and_stagger() -> void:
	allow_expected_engine_error("unsupported format character")
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(150.0, 0.0), "enc_boss_wb")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_boss_wb", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0

	# Force Boss to start uninterruptible Dark-Red sk_boss_fan_pounce
	var pounce_def: Dictionary = DataDB.get_skill("sk_boss_fan_pounce")
	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_fan_pounce", pounce_def, gu)
	assert_true(boss.is_casting and not boss.cast_interruptible, "Boss started uninterruptible Dark-Red sk_boss_fan_pounce")

	# Measure deterministic non-crit hit while shielded (ward_current == 450 -> 0.75x DR)
	var hp_before_shielded: int = boss.hp
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 100.0, 1.0, "water", 10.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var shielded_dmg: int = hp_before_shielded - boss.hp
	assert_gt(float(shielded_dmg), 50.0, "Shielded hit dealt mitigated damage")

	# Shatter remaining Wood Ward with Metal counter hit
	eu_b["ward_current"] = 50.0
	boss.ward_current = 50.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 40.0, 1.0, "metal", 30.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")

	assert_approx(boss.ward_current, 0.0, 0.001, "Boss Wood Ward depleted to 0.0")
	assert_false(boss.is_casting, "Ward break forcibly cancels uninterruptible Dark-Red sk_boss_fan_pounce")
	assert_approx(boss.stagger_timer, 6.0, 0.01, "Ward break opens 6.0s stagger window (气机破绽)")
	assert_approx(float(eu_b.get("stun_timer", 0.0)), 2.0, 0.01, "Ward break applies 2.0s paralysis stun")

	var hp_before_staggered: int = boss.hp
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 100.0, 1.0, "water", 10.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var staggered_dmg: int = hp_before_staggered - boss.hp
	assert_approx(float(staggered_dmg) / float(shielded_dmg), 1.35 / 0.75, 0.05, "Staggered Boss takes 1.35x vs 0.75x shielded (1.80x ratio)")


func case_t1_f02_03_ward_regen_and_boss_phases() -> void:
	allow_expected_engine_error("unsupported format character")
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()

	# 1. Shaman ward recovers to full after 6.0s stagger expires
	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", gu.position + Vector2(220.0, 0.0), "enc_sh_reg")
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_sh_reg", "gu_changqing", false)
	ctrl.auto_attack_enabled = false
	ctrl._trigger_enemy_ward_stagger(eu_sh, shaman)
	eu_sh["ward_current"] = 0.0
	shaman.ward_current = 0.0
	var stag_clk0: float = ctrl.combat_clock_sec
	for _i: int in range(18):
		if ctrl.combat_clock_sec - stag_clk0 >= 6.20:
			break
		gu.hp = gu.max_hp
		ctrl.step_world_and_combat(0.50, QinglanWorld.ZONE_BOUNDS) # >= 6.20s combat_clock_sec > 6.0s stagger
	assert_approx(shaman.stagger_timer, 0.0, 0.001, "Shaman stagger_timer expired to 0.0")
	assert_approx(shaman.ward_current, 85.0, 0.01, "Shaman regenerated full 85.0 Wood Ward after stagger")
	shaman.alive = false
	eu_sh["engaged"] = false

	# 2. Mist Wolf King <=84% HP pup summon & <=55% HP Phase 2 transition
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(200.0, 0.0), "enc_boss_p2")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_boss_p2", "gu_changqing", false)

	eu_b["hp"] = int(round(float(boss.max_hp) * 0.80)) # 80% <= 84%
	boss.hp = int(eu_b["hp"])
	var p1_clk0: float = ctrl.combat_clock_sec
	for _p1_step: int in range(6):
		if ctrl.combat_clock_sec - p1_clk0 >= 0.049:
			break
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
	assert_true(bool(eu_b.get("summoned_p1", false)), "Boss triggered P1 wolf_pup summon at <=84% HP")
	var pup_count: int = 0
	for ea: BattleActor in ctrl.enemy_actors:
		if ea.alive and ea.actor_id.begins_with("wolf_pup_"):
			pup_count += 1
	assert_eq(pup_count, 2, "Mist Wolf King spawned exact 2 wolf_pup adds")

	# Put Boss in broken-ward stagger, then drop HP to 54% (<= 0.55 phase2_hp_ratio)
	eu_b["ward_current"] = 0.0
	boss.ward_current = 0.0
	eu_b["stagger_timer"] = 4.5
	boss.stagger_timer = 4.5
	eu_b["stun_timer"] = 0.0
	eu_b["hp"] = int(round(float(boss.max_hp) * 0.54))
	boss.hp = int(eu_b["hp"])
	var p2_clk0: float = ctrl.combat_clock_sec
	for _p2_step: int in range(6):
		if ctrl.combat_clock_sec - p2_clk0 >= 0.049:
			break
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	assert_eq(int(eu_b.get("phase", 1)), 2, "Mist Wolf King entered Phase 2 at <=55% HP")
	assert_approx(boss.stagger_timer, 0.0, 0.001, "Phase 2 transition clears remaining stagger_timer")
	assert_approx(boss.ward_current, 450.0, 0.01, "Phase 2 transition restores full 450.0 Wood Ward")


func case_t1_f02_04_wood_fire_synergy() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var shen_m: Dictionary = CampaignState.party_members["shen_qinghe"] as Dictionary
	shen_m["ai_preset_index"] = 2 # prevent Shen AI from auto-casting extra skills
	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(180.0, 0.0), "enc_syn_wf")
	var wolf_near: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", golem.position + Vector2(130.0, 0.0), "enc_syn_wf") # 130px <= 165px synergy AoE (outside 110px skill AoE!)
	ctrl.engage_enemy_group("enc_syn_wf", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.set_locked_enemy(golem.actor_id, false)
	ctrl.team_attunement = 10.0

	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void: banners.append(p))

	# Step 1: Shen plants 6.0s wood Mother Seal via sk_shen_vine_bind
	var ok_wood: bool = ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", golem.actor_id, false)
	assert_true(ok_wood, "Shen cast sk_shen_vine_bind")
	assert_eq(golem.mother_seal_element, "wood", "Golem received 'wood' Mother Seal")
	assert_approx(golem.mother_seal_timer, 6.0, 0.01, "Mother Seal duration is 6.0s")
	var att_after_wood: float = ctrl.team_attunement # 10.0 + 4.0 = 14.0
	var wolf_hp_before_fire: int = wolf_near.hp

	# Step 2: Gu casts sk_gu_flame_sword (fire child of wood; skill aoe=110 < 130, so wolf_near is ONLY hit by 165px wood_fire synergy!)
	shen.mp = shen.max_mp
	gu.mp = gu.max_mp
	var ok_fire: bool = ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", golem.actor_id, true)
	assert_true(ok_fire, "Gu cast sk_gu_flame_sword to detonate wood->fire")
	assert_eq(golem.mother_seal_element, "", "Wood Mother Seal consumed upon wood_fire detonation")
	assert_approx(golem.mother_seal_timer, 0.0, 0.001, "Consumed Mother Seal timer reset to 0.0")
	assert_lt(float(wolf_near.hp), float(wolf_hp_before_fire), "Nearby enemy at 130px (<=165px) took wood_fire AoE burst damage")
	var eu_wolf: Dictionary = ctrl.unit_states[wolf_near.actor_id] as Dictionary
	assert_approx(float(eu_wolf.get("dot_timer", 0.0)), 4.0, 0.05, "wood_fire applies 4.0s burn DoT to AoE targets")
	assert_approx(ctrl.team_attunement - att_after_wood, 4.0 + 15.0, 0.05, "Team Qi gained +4.0 skill + +15.0 synergy = +19.0 (total 33.0)")

	var saw_wf: bool = false
	for b: Dictionary in banners:
		if str(b.get("category", "")) == "synergy" and str(b.get("element", "")) == "wood_fire":
			saw_wf = true
	assert_true(saw_wf, "NotifyHub emitted wood_fire synergy combat banner")


func case_t1_f02_05_all_other_synergies() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.unlock_formation("dizai", true)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_2", "flawless")
	CampaignState.advance_member_realm("pei_zhao", "qi_refining_2", "flawless")
	CampaignState.advance_member_realm("shen_qinghe", "qi_refining_2", "flawless")

	var world: QinglanWorld = _spawn_clean_arena()
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_pei: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary

	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(120.0, 0.0), "enc_syn_4")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_syn_4", "pei_zhao", false)
	ctrl.preemptive_buff_timer = 0.0

	# 1) fire -> earth (40% slow 5s + tank Pei gains rock shield + +15 Qi)
	ctrl.team_attunement = 0.0
	u_pei["shield"] = 0.0
	eu_b["mother_seal_element"] = "fire"
	eu_b["mother_seal_timer"] = 5.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 32.0, 1.38, "earth", 34.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, true, 1.0, 0.0, "")
	assert_approx(float(eu_b.get("slow_pct", 0.0)), 0.40, 0.005, "fire_earth applies 40% enemy move slow")
	assert_approx(float(eu_b.get("slow_timer", 0.0)), 5.0, 0.01, "fire_earth slow lasts 5.0s")
	assert_gt(float(u_pei.get("shield", 0.0)), 15.0, "fire_earth grants rock shield to slot-2 tank Pei Zhao")
	assert_approx(ctrl.team_attunement, 15.0, 0.01, "fire_earth grants +15.0 Team Qi")

	# 2) earth -> metal (guaranteed crit + 40% armor ignore + +45 bonus ward shred + +15 Qi)
	eu_b["ward_current"] = 400.0
	boss.ward_current = 400.0
	eu_b["mother_seal_element"] = "earth"
	eu_b["mother_seal_timer"] = 5.0
	ctrl._deal_damage_to_enemy("pei_zhao", pei.position, boss, 35.0, 1.50, "metal", 20.0, 0.0, 1.60, false, 0.0, 1.0, 1.0, true, 1.0, 0.0, "")
	# Counter metal->wood (2.5x) * guaranteed_crit (2.0x) * 20.0 = 100.0 + 45.0 earth_metal bonus = 145.0 ward shred!
	assert_approx(400.0 - boss.ward_current, 145.0, 0.5, "earth_metal applies 2.0x crit ward mult + +45 flat ward shred")
	assert_approx(ctrl.team_attunement, 30.0, 0.01, "earth_metal grants +15.0 Team Qi (total 30.0)")

	# 3) metal -> water (atk_slow_timer 5.0s + caster restores >=8% max_mp [+8 if 3pc set_qinglan_walker] + +15 Qi)
	gu.mp = 15
	eu_b["mother_seal_element"] = "metal"
	eu_b["mother_seal_timer"] = 5.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 32.0, 1.35, "water", 24.0, 0.0, 1.60, false, 0.0, 1.0, 1.0, true, 1.0, 0.0, "")
	assert_approx(float(eu_b.get("atk_slow_timer", 0.0)), 5.0, 0.01, "metal_water applies 5.0s attack/cast speed slow")
	var set_mp_bonus: int = 8 if ((u_gu["sheet"] as Dictionary).get("active_set_effects", []) as Array).has("synergy_restore_mp_8") else 0
	var expected_mp_gain: int = set_mp_bonus + maxi(6, int(round(float(gu.max_mp) * 0.08)))
	assert_eq(gu.mp, 15 + expected_mp_gain, "metal_water restores >=8% max_mp (+ set bonus) to caster")
	assert_approx(ctrl.team_attunement, 45.0, 0.01, "metal_water grants +15.0 Team Qi (total 45.0)")

	# 4) water -> wood (heals 2 lowest injured allies & cleanses miasma on both + +15 Qi)
	gu.hp = int(round(float(gu.max_hp) * 0.20))
	pei.hp = int(round(float(pei.max_hp) * 0.24))
	shen.hp = shen.max_hp
	u_gu["miasma_stacks"] = 2
	gu.miasma_stacks = 2
	u_pei["miasma_stacks"] = 1
	pei.miasma_stacks = 1
	var gu_hp_low: int = gu.hp
	var pei_hp_low: int = pei.hp

	eu_b["mother_seal_element"] = "water"
	eu_b["mother_seal_timer"] = 5.0
	ctrl._deal_damage_to_enemy("shen_qinghe", shen.position, boss, 38.0, 1.25, "wood", 24.0, 0.0, 1.60, false, 0.0, 1.0, 1.0, true, 1.0, 0.0, "")
	assert_gt(float(gu.hp), float(gu_hp_low), "water_wood healed lowest ally Gu Changqing")
	assert_gt(float(pei.hp), float(pei_hp_low), "water_wood healed 2nd-lowest ally Pei Zhao")
	assert_eq(gu.miasma_stacks, 0, "water_wood cleansed Gu Changqing miasma")
	assert_eq(pei.miasma_stacks, 0, "water_wood cleansed Pei Zhao miasma")
	assert_approx(ctrl.team_attunement, 60.0, 0.01, "water_wood grants +15.0 Team Qi (total 60.0)")
	assert_not_null(u_gu, "Gu state valid")
	assert_not_null(u_shen, "Shen state valid")
