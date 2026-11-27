extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 2
# @e2e_features: F1, F2, F3


func register_cases() -> void:
	add_case("T2-F01-01", 2, "F1", "baseline", "Skill rejection mid-GCD, on skill CD, or low MP never advances/resets GCD or spends MP", "case_t2_f01_01_gcd_cd_mp_rejection")
	add_case("T2-F01-02", 2, "F1", "baseline", "Out-of-range skill queues approach waypoint without advancing GCD or spending MP; 0 enemies no-ops", "case_t2_f01_02_out_of_range_and_no_target")
	add_case("T2-F01-03", 2, "F1", "baseline", "Off-GCD Q against Dark-Red uninterruptible cast returns uninterruptible_red, keeps cast active & warns", "case_t2_f01_03_uninterruptible_red_cast")
	add_case("T2-F01-04", 2, "F1", "baseline", "Threat 110% melee / 130% ranged anti-jitter boundaries, nameplate colors & Pei Taunt lock", "case_t2_f01_04_threat_anti_jitter_and_taunt")
	add_case("T2-F01-05", 2, "F1", "baseline", "30s shared pill toxicity cooldown blocks slot 6 after slot 5 & mid-combat stealth talisman rejected", "case_t2_f01_05_shared_pill_cd_and_combat_stealth_block")
	add_case("T2-F01-06", 2, "F1", "baseline", "Extreme haste clamps at 1.00s MIN_GCD_SEC floor & Tab smart-locks distant interruptible caster first", "case_t2_f01_06_gcd_floor_and_smart_tab")
	add_case("T2-F02-01", 2, "F2", "baseline", "Non-matching element against Wood Mother Seal triggers 0 synergy and overwrites single seal slot (6.0s)", "case_t2_f02_01_non_matching_seal_overwrite")
	add_case("T2-F02-02", 2, "F2", "baseline", "Same-element hit on active Wood Mother Seal does not self-detonate and refreshes duration to 6.0s", "case_t2_f02_02_same_element_seal_refresh")
	add_case("T2-F02-03", 2, "F2", "baseline", "Neutral auto-attack and applies_mother_seal=false Q interrupt preserve existing Wood Mother Seal intact", "case_t2_f02_03_non_seal_hits_preserve_mother_seal")
	add_case("T2-F02-04", 2, "F2", "baseline", "Wood Mother Seal expires strictly after 6.0s; late Fire skill plants new Fire seal without wood_fire burst", "case_t2_f02_04_expired_mother_seal_no_synergy")
	add_case("T2-F02-05", 2, "F2", "baseline", "Resisted element (0.80x dmg, 0.50x ward), 100.0 Team Qi cap & no duplicate ward_broken_now during stagger", "case_t2_f02_05_resisted_qi_cap_and_stagger_guard")
	add_case("T2-F03-01", 2, "F3", "baseline", "KEY_SPACE 100% blocked in OOC, Dialogue, CG & DaoCasket modal + FORBIDDEN_SPACE_DIALOGUE keybind guard", "case_t2_f03_01_space_strictly_combat_only")
	add_case("T2-F03-02", 2, "F3", "polish_r1", "Space Tactical Pause freezes active combat GPUParticles2D (speed_scale==0.0) & projectile/slash timers", "case_t2_f03_02_paused_gpu_particles_freeze")
	add_case("T2-F03-03", 2, "F3", "baseline", "G Bond Ultimate rejected when Bond Tier 1 locked, at 99.5 < 100.0 Qi, or during 8.0s skill cooldown", "case_t2_f03_03_bond_ultimate_rejections")
	add_case("T2-F03-04", 2, "F3", "baseline", "Manual RMB dodge on casting Shen cancels cast immediately and suppresses AI override until waypoint reached", "case_t2_f03_04_manual_dodge_overrides_companion_ai")
	add_case("T2-F03-05", 2, "F3", "baseline", "Combat victory and party wipe while paused both clear tactical_paused and disable 900Hz LPF on audio buses", "case_t2_f03_05_combat_exit_clears_pause_and_lpf")


var _pinned_res: Array[Resource] = []


func _warm_suite_resources() -> void:
	if not _pinned_res.is_empty():
		return
	for rpath: String in [
		"res://src/presentation/world/qinglan_world.tscn",
		"res://assets/cg/title_qianli_jiangshan.png",
		"res://assets/world/tex_moss_earth.png",
		"res://assets/world/tex_cave_flagstone.png",
		"res://assets/world/tex_bluestone_wet.png",
		"res://assets/audio/bgm/bgm_qinglan_calm.ogg",
		"res://assets/audio/bgm/bgm_qinglan_combat.ogg",
		"res://assets/audio/bgm/amb_qinglan_rain.ogg",
		"res://assets/audio/bgm/bgm_boss_wolf_king.ogg",
		"res://assets/sprites/gu_changqing_sheet.png",
		"res://assets/sprites/shen_qinghe_sheet.png",
		"res://assets/sprites/pei_zhao_sheet.png",
		"res://assets/sprites/boss_mist_wolf_king_sheet.png",
	]:
		if ResourceLoader.exists(rpath):
			var r: Resource = load(rpath)
			if r != null:
				_pinned_res.append(r)


func _spawn_clean_arena(zone_id: String = "qinglan_pass") -> QinglanWorld:
	_warm_suite_resources()
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	CampaignState.cleared_encounters["enc_cave_pack_1"] = true
	CampaignState.cleared_encounters["enc_cave_golem"] = true
	CampaignState.world_flags["wolf_king_defeated"] = true
	var spawn_tag: String = "stele_wolf_altar" if zone_id == "cangmu_cave" else "stele_temple_courtyard"
	var world: QinglanWorld = spawn_qinglan_world(zone_id, spawn_tag) as QinglanWorld
	world.set_physics_process(false)
	world._combat_ctrl.obstacle_circles.clear()
	return world


func _spawn_combat_rig(with_hud: bool = false) -> Dictionary:
	_warm_suite_resources()
	var root: Node2D = Node2D.new()
	mount_node(root)
	var ground_vfx: CombatVfxOverlay = CombatVfxOverlay.new()
	ground_vfx.is_ground_layer = true
	root.add_child(ground_vfx)
	var ysort: Node2D = Node2D.new()
	ysort.y_sort_enabled = true
	root.add_child(ysort)
	var sky_vfx: CombatVfxOverlay = CombatVfxOverlay.new()
	sky_vfx.is_ground_layer = false
	root.add_child(sky_vfx)
	var cam: Camera2D = Camera2D.new()
	cam.position_smoothing_enabled = false
	cam.position = Vector2(960.0, 650.0)
	root.add_child(cam)
	var audio: AudioDirector = AudioDirector.new()
	root.add_child(audio)
	var ctrl: RtwpCombatController = RtwpCombatController.new()
	root.add_child(ctrl)
	ctrl.reset_for_zone(ysort, ground_vfx, sky_vfx, cam, audio)
	ctrl.spawn_party_at(Vector2(960.0, 650.0))
	InputRouter.tactical_pause_toggled.connect(func() -> void: ctrl.toggle_tactical_pause())
	var hud: CombatHud = null
	if with_hud:
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = 10
		root.add_child(canvas)
		hud = CombatHud.new()
		canvas.add_child(hud)
		hud.bind_combat_controller(ctrl)
	return {"ctrl": ctrl, "hud": hud, "root": root}


func case_t2_f01_01_gcd_cd_mp_rejection() -> void:
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(150.0, 0.0), "enc_rej")
	ctrl.engage_enemy_group("enc_rej", "gu_changqing", false)
	ctrl.set_locked_enemy(wolf.actor_id, false)

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var cds: Dictionary = u_gu["cooldowns"] as Dictionary

	# (A) Mid-GCD (1.10s): rejected without resetting GCD to 1.50s
	u_gu["gcd_timer"] = 1.10
	cds.clear()
	gu.mp = 60
	ctrl.trigger_hotkey_slot("2") # sk_gu_flame_sword (mp_cost=12, cd=5.0)
	assert_approx(float(u_gu["gcd_timer"]), 1.10, 0.0001, "(A) Mid-GCD rejection keeps gcd_timer==1.10s without resetting to 1.50s")
	assert_eq(gu.mp, 60, "(A) Mid-GCD rejection spends 0 MP")
	assert_false(cds.has("sk_gu_flame_sword"), "(A) Mid-GCD rejection does not start skill cooldown")

	# (B) Off-GCD (0.0s) while skill is on 3.4s cooldown: rejected without advancing GCD!
	u_gu["gcd_timer"] = 0.0
	cds["sk_gu_flame_sword"] = 3.40
	gu.mp = 60
	ctrl.trigger_hotkey_slot("2")
	assert_approx(float(u_gu["gcd_timer"]), 0.0, 0.0001, "(B) Cooldown rejection keeps gcd_timer==0.0s")
	assert_eq(gu.mp, 60, "(B) Cooldown rejection spends 0 MP")
	assert_approx(float(cds.get("sk_gu_flame_sword", 0.0)), 3.40, 0.0001, "(B) Remaining cooldown preserved at 3.40s")

	# (C) Off-GCD (0.0s), skill ready, MP = 4 (< 12): rejected without advancing GCD + emits warn banner
	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void: banners.append(p))
	u_gu["gcd_timer"] = 0.0
	cds.clear()
	gu.mp = 4
	ctrl.trigger_hotkey_slot("2")
	assert_approx(float(u_gu["gcd_timer"]), 0.0, 0.0001, "(C) Low-MP rejection keeps gcd_timer==0.0s")
	assert_true(cds.is_empty(), "(C) Low-MP rejection keeps cooldowns empty")
	assert_eq(gu.mp, 4, "(C) Low-MP rejection leaves MP==4 untouched")
	var saw_mp_warn: bool = false
	for b: Dictionary in banners:
		if str(b.get("category", "")) == "warn" and str(b.get("text", "")).contains("真元不足"):
			saw_mp_warn = true
	assert_true(saw_mp_warn, "(C) Low-MP rejection pushes '真元不足' warning banner")


func case_t2_f01_02_out_of_range_and_no_target() -> void:
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	gu.position = Vector2(800.0, 650.0)

	# (A) Enemy at 720px (> sk_gu_qingming_qi range 390 + 32 = 422px)
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", Vector2(1520.0, 650.0), "enc_oor")
	ctrl.set_locked_enemy(wolf.actor_id, false)
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var cds: Dictionary = u_gu["cooldowns"] as Dictionary
	u_gu["gcd_timer"] = 0.0
	cds.clear()
	gu.mp = 60
	gu.has_move_waypoint = false

	ctrl.trigger_hotkey_slot("1")
	assert_approx(float(u_gu["gcd_timer"]), 0.0, 0.0001, "(A) Out-of-range skill does NOT advance gcd_timer")
	assert_eq(gu.mp, 60, "(A) Out-of-range skill does NOT deduct MP before reaching range")
	assert_true(cds.is_empty(), "(A) Out-of-range skill does NOT start cooldown")
	assert_true(gu.has_move_waypoint, "(A) Out-of-range player input sets automatic approach move_waypoint")
	assert_eq(str(u_gu.get("queued_skill_id", "")), "sk_gu_qingming_qi", "(A) Out-of-range skill queued for execution upon arrival")

	# (B) 0 alive enemies -> clean no-op
	wolf.alive = false
	ctrl.set_locked_enemy("", false)
	gu.has_move_waypoint = false
	u_gu["queued_skill_id"] = ""
	ctrl.trigger_hotkey_slot("1")
	assert_approx(float(u_gu["gcd_timer"]), 0.0, 0.0001, "(B) 0-enemy cast keeps gcd_timer==0.0s")
	assert_eq(gu.mp, 60, "(B) 0-enemy cast keeps MP==60")
	assert_false(gu.has_move_waypoint, "(B) 0-enemy cast sets no waypoint")


func case_t2_f01_03_uninterruptible_red_cast() -> void:
	var direct_res: Dictionary = RtwpSimStep.try_interrupt_cast(true, false, 450.0, 400.0)
	assert_false(bool(direct_res.get("interrupted", true)), "try_interrupt_cast returns interrupted==false on Dark-Red cast")
	assert_eq(str(direct_res.get("reason", "")), "uninterruptible_red", "try_interrupt_cast reason == 'uninterruptible_red'")
	assert_approx(float(direct_res.get("lockout_sec", 9.0)), 0.0, 0.0001, "Uninterruptible cast grants 0.0s lockout")

	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(140.0, 0.0), "enc_red")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_red", "gu_changqing", false)
	ctrl.set_locked_enemy(boss.actor_id, false)

	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_fan_pounce", DataDB.get_skill("sk_boss_fan_pounce"), gu)
	assert_true(boss.is_casting and not boss.cast_interruptible, "Boss casting Dark-Red uninterruptible sk_boss_fan_pounce")

	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void: banners.append(p))

	ctrl.trigger_hotkey_slot("Q") # sk_gu_throat_seal
	assert_true(boss.is_casting, "Pressing Q does NOT cancel Dark-Red uninterruptible cast")
	assert_approx(boss.lockout_timer, 0.0, 0.0001, "Dark-Red cast does NOT suffer spell lockout")

	var saw_red_warn: bool = false
	for b: Dictionary in banners:
		if str(b.get("text", "")).contains("暗红锁链危招不可常规打断"):
			saw_red_warn = true
	assert_true(saw_red_warn, "NotifyHub emitted Dark-Red uninterruptible warning banner")


func case_t2_f01_04_threat_anti_jitter_and_taunt() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.unlock_formation("dizai", true)
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1200.0, 650.0), "enc_threat")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	pei.position = Vector2(1100.0, 650.0) # 100px <= 175px melee tank
	gu.position = Vector2(1080.0, 650.0)  # 120px <= 175px melee DPS
	shen.position = Vector2(880.0, 650.0) # 320px > 175px ranged healer
	ctrl.engage_enemy_group("enc_threat", "pei_zhao", false)

	var cands: Array = ctrl._build_ally_threat_candidates(boss.position)
	var tbl: Dictionary = {"pei_zhao": 100.0, "gu_changqing": 89.0, "shen_qinghe": 50.0}

	var r89: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r89.get("target_id", "")), "pei_zhao", "89% melee threat keeps tank Pei Zhao")
	assert_eq(str(r89.get("nameplate_state", "")), "jade_safe", "89% threat shows jade_safe nameplate")

	tbl["gu_changqing"] = 95.0
	var r95: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r95.get("target_id", "")), "pei_zhao", "95% melee threat holds Pei Zhao")
	assert_eq(str(r95.get("nameplate_state", "")), "amber_warn", "95% threat transitions nameplate to amber_warn")

	tbl["gu_changqing"] = 109.5
	var r109: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r109.get("target_id", "")), "pei_zhao", "109.5% (<110%) melee threat does NOT pull OT")
	assert_eq(str(r109.get("nameplate_state", "")), "amber_warn", "109.5% remains amber_warn")

	tbl["gu_changqing"] = 110.5
	var r110: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r110.get("target_id", "")), "gu_changqing", "110.5% (>=110% melee) pulls aggro to Gu Changqing")
	assert_eq(str(r110.get("nameplate_state", "")), "cinnabar_ot", "OT switches nameplate to cinnabar_ot")

	# Ranged 130% threshold test for Shen Qinghe (320px > 175px)
	tbl = {"pei_zhao": 100.0, "gu_changqing": 50.0, "shen_qinghe": 125.0}
	var r125: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r125.get("target_id", "")), "pei_zhao", "125% (<130%) ranged threat does NOT pull OT")

	tbl["shen_qinghe"] = 131.0
	var r131: Dictionary = RtwpSimStep.update_threat_and_pick_target(tbl, "pei_zhao", "", 0.0, cands, "gu_changqing")
	assert_eq(str(r131.get("target_id", "")), "shen_qinghe", "131% (>=130% ranged) pulls aggro to Shen Qinghe")

	# Live Taunt (sk_pei_qingyun_challenge): sets threat = top_threat(500) + flat_threat(210) = 710 & locks 3.5s
	eu_b["threat_table"] = {"pei_zhao": 100.0, "gu_changqing": 80.0, "shen_qinghe": 500.0}
	eu_b["target_id"] = "shen_qinghe"
	var ok_taunt: bool = ctrl._try_execute_party_skill("pei_zhao", "sk_pei_qingyun_challenge", boss.actor_id, false)
	assert_true(ok_taunt, "Pei Zhao executed sk_pei_qingyun_challenge")
	assert_approx(float((eu_b["threat_table"] as Dictionary).get("pei_zhao", 0.0)), 710.0, 0.5, "Taunt snaps Pei threat to 500 + 210 = 710")
	assert_eq(str(eu_b.get("target_id", "")), "pei_zhao", "Taunt immediately locks target_id == 'pei_zhao'")
	assert_approx(float(eu_b.get("taunt_timer", 0.0)), 3.5, 0.05, "Taunt locks aggro for 3.5s (>= 3.0s)")


func case_t2_f01_05_shared_pill_cd_and_combat_stealth_block() -> void:
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	var _wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(180.0, 0.0), "enc_pill_cd")
	ctrl.engage_enemy_group("enc_pill_cd", "gu_changqing", false)

	for item_id: String in ["item_huichun_powder", "item_qingmu_pill", "item_stealth_talisman"]:
		var existing: int = CampaignState.get_item_count(item_id)
		if existing > 0:
			CampaignState.remove_item(item_id, existing)
		CampaignState.add_item(item_id, 2, true)

	CampaignState.quick_pill_5_id = "item_huichun_powder"
	CampaignState.quick_pill_6_id = "item_qingmu_pill"
	gu.hp = 40
	ctrl.pill_cooldown_timer = 0.0

	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void: banners.append(p))

	ctrl.trigger_hotkey_slot("5")
	assert_eq(CampaignState.get_item_count("item_huichun_powder"), 1, "Slot 5 consumed 1 item_huichun_powder")
	assert_approx(ctrl.pill_cooldown_timer, 30.0, 0.01, "Slot 5 started 30.0s shared pill cooldown")

	# Advance 10.0s (20.0s remaining) and press Slot 6 -> rejected!
	ctrl._step_global_timers(10.0)
	assert_approx(ctrl.pill_cooldown_timer, 20.0, 0.05, "20.0s remaining on shared pill toxicity cooldown")
	ctrl.trigger_hotkey_slot("6")
	assert_eq(CampaignState.get_item_count("item_qingmu_pill"), 2, "Slot 6 rejected during shared 30s pill cooldown (count stays 2)")

	# Attempt stealth talisman mid-combat -> rejected!
	var stealth_ok: bool = ctrl.activate_stealth_talisman()
	assert_false(stealth_ok, "activate_stealth_talisman() returns false while in_combat == true")
	assert_approx(ctrl.stealth_timer, 0.0, 0.0001, "stealth_timer stays 0.0 mid-combat")
	assert_eq(CampaignState.get_item_count("item_stealth_talisman"), 2, "Mid-combat stealth rejection preserves talisman count == 2")

	var saw_cd_warn: bool = false
	for b: Dictionary in banners:
		if str(b.get("text", "")).contains("丹毒调息中"):
			saw_cd_warn = true
	assert_true(saw_cd_warn, "NotifyHub emitted pill toxicity cooldown warning banner")


func case_t2_f01_06_gcd_floor_and_smart_tab() -> void:
	assert_approx(StatLedger.MIN_GCD_SEC, 1.00, 0.0001, "GDD 1.00s MIN_GCD_SEC constant")
	assert_approx(StatLedger.BASE_GCD_SEC, 1.50, 0.0001, "GDD 1.50s BASE_GCD_SEC constant")
	assert_approx(StatLedger.MAX_HASTE_PCT, 0.35, 0.0001, "GDD 0.35 MAX_HASTE_PCT constant")
	var capped_haste: float = StatLedger.convert_haste_rating(9999.0, 1.0)
	assert_le(capped_haste, 0.3501, "Hyperbolic haste rating caps at 35% (0.35)")

	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	gu.position = Vector2(900.0, 650.0)

	var wolf_close: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", Vector2(1020.0, 650.0), "enc_tab") # 120px idle
	var shaman_far: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", Vector2(1350.0, 650.0), "enc_tab") # 450px casting
	var eu_sh: Dictionary = ctrl.unit_states[shaman_far.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_tab", "gu_changqing", false)

	# Stack extreme haste (sheet 0.35 + fox 0.25 + preemptive 0.15) -> verify GCD >= 1.00s MIN_GCD_SEC
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	(u_gu["sheet"] as Dictionary)["haste_pct"] = 0.35
	ctrl.party_haste_buff_val = 0.25
	ctrl.party_haste_buff_timer = 5.0
	ctrl.preemptive_buff_timer = 4.0
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	ctrl.set_locked_enemy(wolf_close.actor_id, false)
	ctrl.trigger_hotkey_slot("1")
	assert_ge(float(u_gu["gcd_timer"]), 0.9999, "Stacked extreme haste never pushes GCD below 1.00s floor")

	# Smart Tab target cycling: prioritizes Amber-Gold interruptible caster at 450px over idle wolf at 120px
	ctrl._start_enemy_cast(eu_sh, shaman_far, "sk_enemy_miasma_bolt", DataDB.get_skill("sk_enemy_miasma_bolt"), gu)
	ctrl.set_locked_enemy("", false)
	ctrl.cycle_tab_enemy_target()
	assert_eq(ctrl.locked_enemy_id, shaman_far.actor_id, "Tab smart-locks distant interruptible caster (450px) ahead of closer idle wolf (120px)")


func case_t2_f02_01_non_matching_seal_overwrite() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(160.0, 0.0), "enc_ow")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_ow", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0

	var syn_banners: int = 0
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void:
		if str(p.get("category", "")) == "synergy":
			syn_banners += 1
	)

	# 1) Plant 'wood' Mother Seal -> step 1.5s (4.5s left) -> hit with non-child 'metal' (sk_gu_qingming_qi)
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", golem.actor_id, false)
	eu_g["mother_seal_timer"] = 4.50
	golem.mother_seal_timer = 4.50
	ctrl.team_attunement = 20.0

	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_qingming_qi", golem.actor_id, true)
	assert_eq(syn_banners, 0, "Metal on Wood seal triggers 0 synergy banners")
	assert_approx(ctrl.team_attunement, 24.0, 0.01, "Only +4.0 base skill Qi gained (0 +15 synergy Qi)")
	assert_eq(golem.mother_seal_element, "metal", "Wood Mother Seal overwritten to single 'metal' seal")
	assert_approx(golem.mother_seal_timer, 6.0, 0.01, "Overwritten 'metal' seal timer reset to 6.0s")

	# 2) Re-plant 'wood' Mother Seal (4.5s left) -> hit with non-child 'water' (sk_gu_frost_stream)
	eu_g["mother_seal_element"] = "wood"
	eu_g["mother_seal_timer"] = 4.50
	golem.mother_seal_element = "wood"
	golem.mother_seal_timer = 4.50
	(ctrl.unit_states["gu_changqing"] as Dictionary)["gcd_timer"] = 0.0
	gu.mp = gu.max_mp

	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_frost_stream", golem.actor_id, true)
	assert_eq(syn_banners, 0, "Water on Wood seal triggers 0 synergy (Water generates Wood, not Wood->Water)")
	assert_approx(ctrl.team_attunement, 28.0, 0.01, "Only +4.0 base skill Qi gained")
	assert_eq(golem.mother_seal_element, "water", "Wood Mother Seal overwritten to 'water'")
	assert_approx(golem.mother_seal_timer, 6.0, 0.01, "Overwritten 'water' seal timer reset to 6.0s")


func case_t2_f02_02_same_element_seal_refresh() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(160.0, 0.0), "enc_ref")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_ref", "gu_changqing", false)

	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", golem.actor_id, false)
	eu_g["mother_seal_timer"] = 1.80
	golem.mother_seal_timer = 1.80
	ctrl.team_attunement = 10.0

	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	u_shen["gcd_timer"] = 0.0
	(ctrl.party_actors["shen_qinghe"] as BattleActor).mp = 80
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_wither_thorn", golem.actor_id, false)

	assert_approx(ctrl.team_attunement, 14.0, 0.01, "Same-element wood hit does NOT self-detonate (+4 skill Qi only)")
	assert_eq(golem.mother_seal_element, "wood", "Mother Seal remains 'wood'")
	assert_approx(golem.mother_seal_timer, 6.0, 0.01, "Same-element wood hit refreshes Mother Seal timer from 1.8s back to 6.0s")


func case_t2_f02_03_non_seal_hits_preserve_mother_seal() -> void:
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(120.0, 0.0), "enc_pres")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_pres", "gu_changqing", false)

	eu_g["mother_seal_element"] = "wood"
	eu_g["mother_seal_timer"] = 4.00
	golem.mother_seal_element = "wood"
	golem.mother_seal_timer = 4.00

	# 1) Neutral ('none') auto-attack
	ctrl._perform_party_auto_attack("gu_changqing", gu, u_gu, golem)
	assert_eq(golem.mother_seal_element, "wood", "Auto-attack ('none') preserves 'wood' Mother Seal")
	assert_approx(golem.mother_seal_timer, 4.00, 0.001, "Auto-attack preserves 4.00s Mother Seal timer")

	# 2) Off-GCD Q interrupt (sk_gu_throat_seal, element='metal', applies_mother_seal=false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_throat_seal", golem.actor_id, true)
	assert_eq(golem.mother_seal_element, "wood", "applies_mother_seal=false Q interrupt preserves 'wood' Mother Seal")
	assert_approx(golem.mother_seal_timer, 4.00, 0.001, "Q interrupt preserves 4.00s Mother Seal timer")


func case_t2_f02_04_expired_mother_seal_no_synergy() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 2
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(220.0, 0.0), "enc_exp")
	ctrl.engage_enemy_group("enc_exp", "gu_changqing", false)
	ctrl.auto_attack_enabled = false

	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", golem.actor_id, false)
	assert_eq(golem.mother_seal_element, "wood", "Planted 6.0s wood Mother Seal")

	# Step >= 6.05s of simulated combat_clock_sec (accounting for M1 hitstop frames) without any child skill hitting
	var clock_start: float = ctrl.combat_clock_sec
	for _i: int in range(40):
		if ctrl.combat_clock_sec - clock_start >= 6.05:
			break
		gu.hp = gu.max_hp
		ctrl.step_world_and_combat(0.25, QinglanWorld.ZONE_BOUNDS)

	assert_approx(golem.mother_seal_timer, 0.0, 0.001, "Mother Seal timer expired to 0.0s after >6.0s")
	assert_eq(golem.mother_seal_element, "", "Expired Mother Seal cleared to empty string")

	ctrl.team_attunement = 30.0
	(ctrl.unit_states["gu_changqing"] as Dictionary)["gcd_timer"] = 0.0
	gu.mp = gu.max_mp
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", golem.actor_id, true)

	assert_approx(ctrl.team_attunement, 34.0, 0.01, "Fire skill after expiry does NOT trigger wood_fire (+4 Qi only)")
	assert_eq(golem.mother_seal_element, "fire", "Fire skill plants fresh 'fire' Mother Seal")
	assert_approx(golem.mother_seal_timer, 6.0, 0.01, "Fresh 'fire' Mother Seal starts at 6.0s")


func case_t2_f02_05_resisted_qi_cap_and_stagger_guard() -> void:
	# 1) Resisted element matchup: earth vs wood (since wood counters earth)
	var res_m: Dictionary = RtwpSimStep.evaluate_element_matchup("earth", "wood", 1.25)
	assert_eq(str(res_m.get("relation", "")), "resisted", "earth attacking wood Ward is 'resisted'")
	assert_approx(float(res_m.get("damage_mult", 0.0)), 0.80, 0.001, "Resisted damage_mult == 0.80")
	assert_approx(float(res_m.get("ward_break_mult", 0.0)), 0.50, 0.001, "Resisted ward_break_mult == 0.50")

	# 2) Team Qi clamps strictly at 100.0 (MAX_ATTUNEMENT)
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(140.0, 0.0), "enc_cap")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_cap", "gu_changqing", false)

	ctrl.team_attunement = 95.0
	eu_b["mother_seal_element"] = "wood"
	eu_b["mother_seal_timer"] = 5.0
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	assert_approx(RtwpSimStep.MAX_ATTUNEMENT, 100.0, 0.0001, "GDD 100.0 MAX_ATTUNEMENT constant")
	assert_approx(ctrl.team_attunement, 100.0, 0.001, "Team Qi clamps strictly at 100.0")

	# 3) Hitting already-staggered Boss (stagger_timer = 4.0s) does NOT re-trigger ward_broken_now or reset stagger to 6.0s
	var snap_stagger: Dictionary = {
		"ward_current": 0.0,
		"ward_max": 450.0,
		"ward_element": "wood",
		"stagger_timer": 4.0,
		"damage_taken_mult": 0.90,
		"shield_current": 0.0,
	}
	var hit_st: Dictionary = RtwpSimStep.compute_hit_outcome(40.0, 2.0, "metal", 95.0, 0.0, 1.6, false, 0.0, 1.0, false, snap_stagger, 0.99)
	assert_false(bool(hit_st.get("ward_broken_now", true)), "Hitting staggered target does NOT re-trigger ward_broken_now")

	eu_b["ward_current"] = 0.0
	boss.ward_current = 0.0
	eu_b["stagger_timer"] = 3.80
	boss.stagger_timer = 3.80
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 40.0, 1.5, "metal", 95.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	assert_approx(boss.stagger_timer, 3.80, 0.001, "Live hit during stagger does NOT reset stagger_timer back to 6.0s")


func case_t2_f03_01_space_strictly_combat_only() -> void:
	# Keybind rebind guard: Space forbidden on dialogue_confirm
	var rebind_res: Dictionary = InputRouter.rebind_action("dialogue_confirm", KEY_SPACE)
	assert_false(bool(rebind_res.get("ok", true)), "rebind_action('dialogue_confirm', KEY_SPACE) rejected")
	assert_eq(str(rebind_res.get("conflict", "")), "FORBIDDEN_SPACE_DIALOGUE", "Conflict code == FORBIDDEN_SPACE_DIALOGUE")

	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl

	# (A) OOC exploration (in_combat == false, MODE_WORLD_COMBAT)
	assert_false(ctrl.in_combat, "Out of combat")
	dispatch_input(make_key_event(KEY_SPACE, true))
	ctrl.toggle_tactical_pause()
	assert_false(ctrl.tactical_paused, "(A) Space does NOT enable tactical_paused outside combat")

	# (B) MODE_DIALOGUE (NarrativeStage open)
	world._narrative.start_dialogue("dlg_ch01_meet_shen", true)
	InputRouter._dialogue_cooldown_sec = 0.0
	var line_before: int = world._narrative._line_index
	dispatch_input(make_key_event(KEY_SPACE, true))
	await step_frames(1)
	assert_eq(InputRouter.current_mode, InputRouter.MODE_DIALOGUE, "(B) Mode is MODE_DIALOGUE")
	assert_eq(world._narrative._line_index, line_before, "(B) KEY_SPACE advances 0 dialogue lines")
	assert_false(ctrl.tactical_paused, "(B) tactical_paused stays false in dialogue")
	world._narrative.visible = false

	# (C) MODE_CUTSCENE_CG (4-layer CG active)
	world._narrative.start_dialogue("dlg_ch01_temple_clash", true)
	InputRouter._dialogue_cooldown_sec = 0.0
	assert_true(world._narrative._cg_active, "(C) Tier 3 CG stage active")
	dispatch_input(make_key_event(KEY_SPACE, true))
	await step_frames(1)
	assert_true(world._narrative._cg_active, "(C) KEY_SPACE does NOT skip Tier 3 CG")
	assert_false(ctrl.tactical_paused, "(C) tactical_paused stays false in CG")
	world._narrative.visible = false
	world._narrative._cg_active = false

	# (D) MODE_MODAL_MENU (DaoCasketPanel open)
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	world._casket.open_tab("cultivation")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "(D) DaoCasketPanel sets MODE_MODAL_MENU")
	dispatch_input(make_key_event(KEY_SPACE, true))
	await step_frames(1)
	assert_true(world._casket.visible, "(D) DaoCasketPanel stays open without unintended Space action")
	assert_false(ctrl.tactical_paused, "(D) tactical_paused stays false in modal menu")
	world._casket.close_casket()


func case_t2_f03_02_paused_gpu_particles_freeze() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(160.0, 0.0), "enc_p_freeze")
	ctrl.engage_enemy_group("enc_p_freeze", "gu_changqing", false)
	ctrl.set_locked_enemy(boss.actor_id, false)

	# Disable hitstop via comfort setting so Space pause is isolated cleanly
	SaveManager.reduced_motion = true
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	ctrl.step_world_and_combat(0.03, QinglanWorld.ZONE_BOUNDS)

	var active_particles: Array[GPUParticles2D] = collect_active_gpu_particles(world._sky_vfx)
	if active_particles.is_empty():
		active_particles = collect_active_gpu_particles(world)
	assert_ge(float(active_particles.size()), 1.0, "Combat skill & wood_fire synergy spawned >= 1 active visible GPUParticles2D")

	# Press Space -> tactical_paused = true -> step 0.20s real time
	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused, "Tactical Pause active")

	var fx_timer_before: float = -1.0
	if not world._sky_vfx.transient_fx.is_empty():
		fx_timer_before = float((world._sky_vfx.transient_fx[0] as Dictionary).get("timer", 0.0))

	for _i: int in range(4):
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	for gp: GPUParticles2D in active_particles:
		if gp != null and is_instance_valid(gp) and gp.visible and gp.process_material != null:
			var frozen: bool = is_zero_approx(gp.speed_scale) or gp.process_mode == Node.PROCESS_MODE_DISABLED
			assert_true(frozen, "Active GPUParticles2D '%s' freezes (speed_scale==0.0) during Tactical Pause" % gp.name)

	if fx_timer_before > 0.0 and not world._sky_vfx.transient_fx.is_empty():
		var fx_timer_after: float = float((world._sky_vfx.transient_fx[0] as Dictionary).get("timer", 0.0))
		assert_approx(fx_timer_after, fx_timer_before, 0.0001, "Projectile/slash transient_fx timer does NOT decay while paused")

	# Unpause -> active visible pool slots restore speed_scale > 0.0 (ignoring hidden inactive pool slots)
	ctrl.toggle_tactical_pause()
	ctrl.step_world_and_combat(0.03, QinglanWorld.ZONE_BOUNDS)
	var resumed_particles: Array[GPUParticles2D] = collect_active_gpu_particles(world._sky_vfx)
	if resumed_particles.is_empty():
		resumed_particles = collect_active_gpu_particles(world)
	assert_ge(float(resumed_particles.size()), 1.0, "Active visible GPUParticles2D remains live immediately after unpause")
	for gp2: GPUParticles2D in resumed_particles:
		assert_gt(gp2.speed_scale, 0.05, "Active GPUParticles2D '%s' restores speed_scale > 0.0 on unpause" % gp2.name)


func case_t2_f03_03_bond_ultimate_rejections() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var rig: Dictionary = _spawn_combat_rig(true)
	await step_frames(1)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var hud: CombatHud = rig["hud"] as CombatHud
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(160.0, 0.0), "enc_ult_rej")
	ctrl.engage_enemy_group("enc_ult_rej", "gu_changqing", false)
	ctrl.set_locked_enemy(golem.actor_id, false)

	var hp0: int = golem.hp

	# (A) Bond Tier 1 (ult_qinglian_sword locked) & 100.0 Qi -> rejected & HUD G tile hidden
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), 1, "Initial Shen bond is Tier 1")
	hud.refresh_static_bindings()
	assert_false(((hud._slot_widgets["G"] as Dictionary)["tile"] as Control).visible, "(A) HUD G tile hidden before Tier-2 bond")
	ctrl.team_attunement = 100.0
	ctrl.trigger_hotkey_slot("G")
	assert_approx(ctrl.team_attunement, 100.0, 0.001, "(A) Locked ultimate does NOT spend Qi")
	assert_eq(golem.hp, hp0, "(A) Locked ultimate deals 0 damage")

	# Unlock Tier-2 Bond
	CampaignState.add_companion_bond("shen_qinghe", 1)
	hud.refresh_static_bindings()
	assert_true(((hud._slot_widgets["G"] as Dictionary)["tile"] as Control).visible, "HUD G tile visible at Tier-2 bond")

	# (B) Unlocked, but team_attunement == 99.5 (< 100.0) -> rejected!
	ctrl.team_attunement = 99.5
	ctrl.trigger_hotkey_slot("G")
	assert_approx(ctrl.team_attunement, 99.5, 0.001, "(B) 99.5 < 100.0 Qi rejected without spending Qi")
	assert_eq(golem.hp, hp0, "(B) 99.5 Qi ultimate deals 0 damage")

	# (C) Unlocked & 100.0 Qi, but ult_qinglian_sword is on its 8.0s cooldown -> rejected!
	ctrl.team_attunement = 100.0
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	(u_gu["cooldowns"] as Dictionary)["ult_qinglian_sword"] = 6.5
	ctrl.trigger_hotkey_slot("G")
	assert_approx(ctrl.team_attunement, 100.0, 0.001, "(C) Cooldown-blocked ultimate preserves 100.0 Qi")
	assert_eq(golem.hp, hp0, "(C) Cooldown-blocked ultimate deals 0 damage")


func case_t2_f03_04_manual_dodge_overrides_companion_ai() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 0
	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary

	var _wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(180.0, 0.0), "enc_dodge")
	ctrl.engage_enemy_group("enc_dodge", "gu_changqing", false)

	# Injure Gu to 30% HP & add miasma so Shen AI begins 1.35s cast of sk_shen_sweet_rain
	gu.hp = int(round(float(gu.max_hp) * 0.30))
	(ctrl.unit_states["gu_changqing"] as Dictionary)["miasma_stacks"] = 1
	gu.miasma_stacks = 1
	u_shen["gcd_timer"] = 0.0
	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)
	assert_true(shen.is_casting, "Shen AI started casting sk_shen_sweet_rain")

	# Box-select Shen and issue manual dodge move 250px away
	var dodge_dest: Vector2 = shen.position + Vector2(-250.0, 0.0)
	ctrl.box_selected_ids = ["shen_qinghe"]
	ctrl.command_move_selected_to(dodge_dest)

	assert_false(shen.is_casting, "command_move_selected_to immediately cancels Shen mid-cast (zero-delay dodge)")
	assert_false(bool(u_shen.get("casting", true)), "Shen unit_state casting set false")
	assert_true(shen.has_move_waypoint, "Shen has manual dodge move_waypoint")

	var start_dist: float = shen.position.distance_to(shen.move_waypoint)
	for _i: int in range(8):
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS) # 0.40s (~85px moved, still > 14px from dest)

	assert_true(shen.has_move_waypoint, "Companion AI does NOT override manual move_waypoint before arrival")
	assert_false(shen.is_casting, "Companion AI does NOT stop to cast while moving to dodge waypoint")
	assert_lt(shen.position.distance_to(shen.move_waypoint), start_dist - 40.0, "Shen continuously ran toward dodge waypoint")


func case_t2_f03_05_combat_exit_clears_pause_and_lpf() -> void:
	var bgm_idx: int = AudioServer.get_bus_index("BGM_Bus")
	var amb_idx: int = AudioServer.get_bus_index("Ambient_UI_Bus")

	var rig: Dictionary = _spawn_combat_rig(false)
	var ctrl: RtwpCombatController = rig["ctrl"] as RtwpCombatController
	var gu: BattleActor = ctrl.get_controlled_actor()

	# Path A: Combat Victory while tactical_paused == true
	var wolf_a: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(140.0, 0.0), "enc_exit_win")
	ctrl.engage_enemy_group("enc_exit_win", "gu_changqing", false)
	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused and AudioServer.is_bus_effect_enabled(bgm_idx, 0), "Paused with 900Hz LPF before victory")

	wolf_a.alive = false
	(ctrl.unit_states[wolf_a.actor_id] as Dictionary)["engaged"] = false
	ctrl._check_combat_resolution()

	assert_false(ctrl.tactical_paused, "Victory exit resets tactical_paused == false")
	assert_false(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "Victory exit disables BGM_Bus 900Hz LPF")
	assert_false(AudioServer.is_bus_effect_enabled(amb_idx, 0), "Victory exit disables Ambient_UI_Bus 900Hz LPF")

	# Path B: Party Wipe while tactical_paused == true
	var _wolf_b: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(140.0, 0.0), "enc_exit_wipe")
	ctrl.engage_enemy_group("enc_exit_wipe", "gu_changqing", false)
	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused and AudioServer.is_bus_effect_enabled(bgm_idx, 0), "Paused with 900Hz LPF before wipe")

	for pa_var: Variant in ctrl.party_actors.values():
		var pa: BattleActor = pa_var as BattleActor
		pa.hp = 0
		pa.alive = false
	ctrl._check_combat_resolution()

	assert_false(ctrl.in_combat, "Party wipe exits combat")
	assert_false(ctrl.tactical_paused, "Party wipe resets tactical_paused == false")
	assert_false(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "Party wipe disables BGM_Bus 900Hz LPF")
	assert_false(AudioServer.is_bus_effect_enabled(amb_idx, 0), "Party wipe disables Ambient_UI_Bus 900Hz LPF")
