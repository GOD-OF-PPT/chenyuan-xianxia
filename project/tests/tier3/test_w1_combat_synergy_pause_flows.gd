extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 3
# @e2e_features: F1, F2, F3, F5


func register_cases() -> void:
	add_case("T3-W1-01", 3, "F3", "polish_r1", "Tactical Pause + GPUParticles2D freeze + box-select scatter + queued Wood->Fire -> 100 Qi G Ultimate Ward-Break hitstop/flash", "case_t3_w1_01_pause_synergy_bond_ult_wardbreak")
	add_case("T3-W1-02", 3, "F1", "baseline", "Preemptive pull (+15% haste / 1.5x ward shred) + Fox Ctrl+2 haste + 1.00s GCD floor + off-GCD Q interrupt lockout", "case_t3_w1_02_preemptive_fox_haste_and_interrupt")
	add_case("T3-W1-03", 3, "F2", "baseline", "Shen AI cleanse/heal threat split + Pei tank Taunt (110%/130% anti-jitter hold) + Mouseover pill 5 off-GCD save", "case_t3_w1_03_ai_heal_threat_taunt_and_mouseover_pill")
	add_case("T3-W1-04", 3, "F5", "polish_r1", "Dual lighting contract: Shaded actor_hit_flash.gdshader lit by PointLight2D alongside Unshaded CombatVfxOverlay burst", "case_t3_w1_04_dual_shaded_actor_unshaded_vfx_lighting")
	add_case("T3-W1-05", 3, "F2", "baseline", "Mist Wolf King P1 (<=84% pup adds) -> Metal Ward Break (6s 气机破绽) -> P2 (<=55% Ward restore + 腐木咆哮 Amber-Gold cast & Q interrupt)", "case_t3_w1_05_mist_wolf_king_full_two_phase_loop")


var _pinned_res: Array[Resource] = []


func _warm_suite_resources() -> void:
	if not _pinned_res.is_empty():
		return
	for rpath: String in [
		"res://src/presentation/world/qinglan_world.tscn",
		"res://assets/cg/title_qianli_jiangshan.png",
		"res://assets/world/tex_cave_flagstone.png",
		"res://assets/world/tex_bluestone_wet.png",
		"res://assets/audio/bgm/bgm_qinglan_calm.ogg",
		"res://assets/audio/bgm/bgm_qinglan_combat.ogg",
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


func _spawn_clean_arena(zone_id: String = "cangmu_cave") -> QinglanWorld:
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


func _is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	return is_canvas_item_unshaded(ci)


func _step_combat_at_least(ctrl: RtwpCombatController, min_advance_sec: float, step_dt: float = 0.05, max_steps: int = 6) -> void:
	var clk0: float = ctrl.combat_clock_sec
	for _s: int in range(max_steps):
		if ctrl.combat_clock_sec - clk0 >= min_advance_sec:
			break
		ctrl.step_world_and_combat(step_dt, QinglanWorld.ZONE_BOUNDS)


func _read_hit_flash_amount(actor: BattleActor) -> float:
	if actor == null or actor._sprite == null:
		return -1.0
	var mat: Material = actor._sprite.material
	if not (mat is ShaderMaterial):
		return -1.0
	var smat: ShaderMaterial = mat as ShaderMaterial
	if smat.shader == null:
		return -1.0
	for cname: String in ["flash_amount", "flash_intensity", "hit_flash", "flash", "intensity", "mix_amount"]:
		var v: Variant = smat.get_shader_parameter(cname)
		if v is float or v is int:
			return float(v)
	for u: Dictionary in smat.shader.get_shader_uniform_list():
		if int(u.get("type", -1)) == TYPE_FLOAT:
			var uname: String = str(u.get("name", ""))
			var uv: Variant = smat.get_shader_parameter(uname)
			if uv is float or uv is int:
				return float(uv)
	return 0.0


func _make_radial_light_texture() -> GradientTexture2D:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.width = 256
	gtex.height = 256
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.0)
	gtex.gradient = grad
	return gtex


func case_t3_w1_01_pause_synergy_bond_ult_wardbreak() -> void:
	allow_expected_engine_error("unsupported format character")
	SaveManager.screen_shake_pct = 0.45
	SaveManager.reduced_motion = false

	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.add_companion_bond("shen_qinghe", 1) # Tier 2 unlocks G ult_qinglian_sword
	CampaignState.contract_spirit_pet("pet_fire_fox")
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.spawn_party_at(Vector2(1150.0, 680.0))
	world._camera.position = Vector2(1200.0, 660.0)
	await step_frames(2)

	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1310.0, 660.0), "enc_t3_1")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_t3_1", "pei_zhao", false)
	ctrl.set_locked_enemy(boss.actor_id, false)

	# Boss starts ground_cone telegraph; spawn an initial element skill so GPUParticles2D are live before Space
	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_fan_pounce", DataDB.get_skill("sk_boss_fan_pounce"), gu)
	eu_b["cast_progress"] = 0.90
	boss.cast_progress = 0.90
	ctrl._try_execute_party_skill("pei_zhao", "sk_pei_sun_flare", boss.actor_id, false)
	eu_b["mother_seal_element"] = ""
	eu_b["mother_seal_timer"] = 0.0
	boss.mother_seal_element = ""
	boss.mother_seal_timer = 0.0

	# Set team Qi to 80.0 (Shen +4 + Gu +4 + wood_fire +15 -> clamps at 100.0!)
	ctrl.team_attunement = 80.0
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	u_shen["gcd_timer"] = 0.0
	u_gu["gcd_timer"] = 0.12 # Shen lands wood seal at +0.05s, Gu lands fire child at +0.15s!

	# 1) Press Space -> Tactical Pause freezes GPUParticles2D & combat clock
	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused, "Tactical Pause active")
	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	var active_particles: Array[GPUParticles2D] = collect_active_gpu_particles(world)
	assert_ge(float(active_particles.size()), 1.0, "Active 5-element GPUParticles2D present on battlefield")
	for gp: GPUParticles2D in active_particles:
		assert_true(is_zero_approx(gp.speed_scale) or gp.process_mode == Node.PROCESS_MODE_DISABLED, "Active GPUParticles2D frozen during Space pause")

	# 2) LMB drag box-select party + RMB scatter out of Boss cone + F3/F1 queue Wood->Fire
	world._unhandled_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(680.0, 320.0), true))
	world._unhandled_input(make_mouse_motion_event(Vector2(1180.0, 760.0)))
	world._unhandled_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(1180.0, 760.0), false))
	assert_ge(float(ctrl.box_selected_ids.size()), 3.0, "Box-selected trio in Tactical Pause")

	ctrl.command_move_selected_to(Vector2(1160.0, 560.0)) # Flanking scatter within skill range
	ctrl.switch_controlled_party_slot(3, false) # Shen Qinghe
	ctrl.trigger_hotkey_slot("4") # sk_shen_vine_bind (wood seal)
	ctrl.switch_controlled_party_slot(1, false) # Gu Changqing
	ctrl.trigger_hotkey_slot("2") # sk_gu_flame_sword (fire child)
	ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)
	assert_eq(world._sky_vfx.queued_skill_lines.size(), 2, "2 queued synergy skill lines visible while paused")

	# 3) Unpause -> Shen plants Wood, Gu detonates Wood->Fire -> Team Qi reaches 100.0
	ctrl.toggle_tactical_pause()
	_step_combat_at_least(ctrl, 0.249, 0.05, 12)
	assert_approx(ctrl.team_attunement, 100.0, 0.1, "Queued Wood->Fire synergy boosted Team Qi to 100.0")

	# 4) Set Boss Wood Ward to 90.0 and fire G Bond Ultimate (青莲引剑, 125 base ward shred) -> Ward Break + Hitstop + Hit-Flash!
	eu_b["ward_current"] = 90.0
	boss.ward_current = 90.0
	ctrl.trigger_hotkey_slot("G")

	assert_approx(boss.ward_current, 0.0, 0.01, "G Bond Ultimate shattered remaining Boss Wood Ward")
	assert_approx(boss.stagger_timer, 6.0, 0.05, "Boss entered 6.0s 气机破绽 stagger")
	assert_gt(_read_hit_flash_amount(boss), 0.1, "Boss actor_hit_flash.gdshader triggered on Ultimate Ward-Break")
	assert_ge(float(obj_get(ctrl, "_hitstop_timer", -1.0)), 0.045, "Boss Ward-Break triggered >=45ms hitstop")


func case_t3_w1_02_preemptive_fox_haste_and_interrupt() -> void:
	allow_expected_engine_error("unsupported format character")
	CampaignState.contract_spirit_pet("pet_fire_fox")
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", gu.position + Vector2(290.0, 0.0), "enc_t3_2")
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	eu_sh["ward_max"] = 240.0
	eu_sh["ward_current"] = 240.0
	shaman.ward_max = 240.0
	shaman.ward_current = 240.0
	ctrl.set_locked_enemy(shaman.actor_id, false)

	# 1) Preemptive cast-time pull (sk_gu_gale_blades) + Fox Ctrl+2 haste (+14%)
	ctrl.trigger_hotkey_slot("4")
	assert_true(ctrl.in_combat, "Preemptive pull engaged combat")
	assert_approx(ctrl.preemptive_buff_timer, 4.0, 0.05, "Preemptive 4.0s buff active")

	ctrl.trigger_pet_manual_skill(2) # sk_pet_fox_haste (+14% haste, +12 Qi)
	assert_approx(ctrl.party_haste_buff_val, 0.14, 0.005, "Fox haste +14% active")
	assert_ge(ctrl.team_attunement, 12.0, "Fox haste granted +12 Team Qi")

	# Finish Gu's gale blades cast -> first hit consumes preemptive 1.5x ward shred
	_step_combat_at_least(ctrl, 1.15, 0.10, 16)
	assert_lt(shaman.ward_current, 200.0, "Preemptive gale blades shredded ward")

	# 2) Stack high sheet haste + fox haste -> verify GCD respects 1.00s floor
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	(u_gu["sheet"] as Dictionary)["haste_pct"] = 0.35
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	gu.mp = gu.max_mp
	ctrl.trigger_hotkey_slot("1")
	var gcd_after_1: float = float(u_gu["gcd_timer"])
	assert_ge(gcd_after_1, 0.9999, "Combined haste respects 1.00s MIN_GCD_SEC floor")
	assert_le(gcd_after_1, 1.08, "Combined haste reaches near 1.00s minimum GCD")

	# 3) While Gu is STILL on GCD (~1.03s), Shaman casts Amber-Gold bolt -> Gu fires off-GCD Q interrupt!
	ctrl._start_enemy_cast(eu_sh, shaman, "sk_enemy_miasma_bolt", DataDB.get_skill("sk_enemy_miasma_bolt"), gu)
	var ward_pre_q: float = shaman.ward_current
	ctrl.trigger_hotkey_slot("Q")

	assert_approx(float(u_gu["gcd_timer"]), gcd_after_1, 0.001, "Off-GCD Q left active GCD timer unchanged")
	assert_false(shaman.is_casting, "Off-GCD Q interrupted Amber-Gold cast")
	assert_approx(shaman.lockout_timer, 3.0, 0.01, "Shaman locked out for 3.0s (破功封脉)")
	assert_lt(shaman.ward_current, ward_pre_q - 60.0, "Off-GCD Q applied bonus interrupt ward shred + counter ward damage")


func case_t3_w1_03_ai_heal_threat_taunt_and_mouseover_pill() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.unlock_formation("dizai", true)
	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 0
	(CampaignState.party_members["pei_zhao"] as Dictionary)["ai_preset_index"] = 1 # tank_anchor

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary

	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1300.0, 650.0), "enc_t3_3")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	pei.position = Vector2(1190.0, 650.0) # melee tank
	gu.position = Vector2(1170.0, 675.0)  # melee DPS
	shen.position = Vector2(960.0, 650.0) # ranged healer (>175px)
	ctrl.engage_enemy_group("enc_t3_3", "shen_qinghe", false)
	ctrl.set_locked_enemy(boss.actor_id, false)

	# 1) Shen has initial aggro; Pei tank_anchor AI immediately fires Taunt & snaps threat above Shen!
	(eu_b["threat_table"] as Dictionary)["shen_qinghe"] = 220.0
	eu_b["target_id"] = "shen_qinghe"
	gu.hp = int(round(float(gu.max_hp) * 0.45))
	u_gu["miasma_stacks"] = 2
	gu.miasma_stacks = 2
	u_shen["gcd_timer"] = 0.0

	var shen_threat_before: float = float((eu_b["threat_table"] as Dictionary).get("shen_qinghe", 0.0))
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_eq(str(eu_b.get("taunt_target_id", "")), "pei_zhao", "Pei tank AI auto-taunted Boss off healer Shen")
	assert_eq(str(eu_b.get("target_id", "")), "pei_zhao", "Boss target locked onto Pei Zhao")

	# Step >=1.45s combat_clock_sec so Shen finishes sk_shen_sweet_rain cleanse+heal -> adds split heal threat, yet stays <130% of Pei's taunted threat!
	_step_combat_at_least(ctrl, 1.45, 0.10, 22)
	assert_eq(gu.miasma_stacks, 0, "Shen AI cleansed Gu's miasma stacks")
	var shen_threat_after: float = float((eu_b["threat_table"] as Dictionary).get("shen_qinghe", 0.0))
	assert_gt(shen_threat_after, shen_threat_before, "Effective AI heal added split healer threat to Boss threat_table")
	assert_eq(str(eu_b.get("target_id", "")), "pei_zhao", "Pei Zhao held Boss aggro against healer threat via Taunt + 130% ranged anti-jitter")

	# 2) Injure Pei to 35% HP + miasma & recover instantly via player Mouseover pill 5 while Gu is mid-GCD
	var cur_p: int = CampaignState.get_item_count("item_qingmu_pill")
	if cur_p > 0:
		CampaignState.remove_item("item_qingmu_pill", cur_p)
	CampaignState.add_item("item_qingmu_pill", 2, true)
	CampaignState.quick_pill_5_id = "item_qingmu_pill"

	pei.hp = int(round(float(pei.max_hp) * 0.35))
	var pei_low_hp: int = pei.hp
	(ctrl.unit_states["pei_zhao"] as Dictionary)["miasma_stacks"] = 1
	pei.miasma_stacks = 1
	u_gu["gcd_timer"] = 1.20
	ctrl.pill_cooldown_timer = 0.0
	ctrl.hovered_ally_id = "pei_zhao"

	ctrl.trigger_hotkey_slot("5")
	assert_approx(float(u_gu["gcd_timer"]), 1.20, 0.001, "Mouseover pill 5 did not disturb Gu's active GCD")
	assert_gt(float(pei.hp), float(pei_low_hp), "Mouseover pill 5 healed hovered tank Pei Zhao")
	assert_eq(pei.miasma_stacks, 0, "Mouseover pill 5 cleansed Pei Zhao miasma")


func case_t3_w1_04_dual_shaded_actor_unshaded_vfx_lighting() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	SaveManager.reduced_motion = true

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	world._hud.visible = false
	world._rain_overlay.visible = false
	world._mood_modulate.color = Color(0.15, 0.15, 0.17, 1.0)
	world._camera.position = Vector2(1100.0, 620.0)

	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.spawn_party_at(Vector2(860.0, 660.0))
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	gu.position = Vector2(860.0, 660.0)   # Lit by warm PointLight2D
	shen.position = Vector2(720.0, 660.0)

	var unlit_npc: BattleActor = BattleActor.new()
	unlit_npc.position = Vector2(1360.0, 660.0) # Far in dark cavern without PointLight2D
	unlit_npc.setup_actor("dark_ref", "party", "暗处参照", "gu_changqing", 1.0)
	world._ysort_root.add_child(unlit_npc)

	var pt_light: PointLight2D = PointLight2D.new()
	pt_light.position = Vector2(860.0, 590.0)
	pt_light.texture = _make_radial_light_texture()
	pt_light.texture_scale = 1.5
	pt_light.energy = 2.3
	pt_light.color = Color(1.0, 0.90, 0.72, 1.0)
	world._ysort_root.add_child(pt_light)

	# Spawn Boss in middle-right (1120, 640) outside the PointLight2D radius and detonate unshaded Wood->Fire VFX!
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1120.0, 640.0), "enc_t3_light")
	ctrl.engage_enemy_group("enc_t3_light", "gu_changqing", false)
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	ctrl._refresh_vfx_overlays(0.016)

	assert_true(gu._sprite.material is ShaderMaterial, "Gu mounts shaded actor_hit_flash.gdshader")
	assert_false(_is_canvas_item_unshaded(gu._sprite), "Gu sprite is shaded (receives PointLight2D)")
	assert_true(_is_canvas_item_unshaded(world._sky_vfx), "sky_vfx is unshaded (immune to 0.15 _mood_modulate)")

	var img: Image = await capture_1080p_frame(18)
	# Screen coords: camera (1100, 620) -> Gu torso (720, 505), unlit_npc torso (1220, 505), Boss VFX impact (980, 520)
	var roi_gu_lit: Dictionary = sample_image_roi_stats(img, Rect2i(696, 470, 48, 72))
	var roi_unlit: Dictionary = sample_image_roi_stats(img, Rect2i(1196, 470, 48, 72))
	var roi_vfx: Dictionary = sample_image_roi_stats(img, Rect2i(900, 440, 180, 180))

	var luma_lit: float = float(roi_gu_lit.get("mean_luma", 0.0))
	var luma_unlit: float = maxf(0.001, float(roi_unlit.get("mean_luma", 0.0)))
	var vfx_peak: float = float(roi_vfx.get("max_luma", 0.0))

	assert_ge(luma_lit / luma_unlit, 1.60, "Warm PointLight2D illuminates shaded BattleActor >= 1.6x in dark cavern")
	assert_gt(vfx_peak, 0.38, "Simultaneous unshaded CombatVfxOverlay burst shines brightly (>0.38 luma) outside PointLight2D")


func case_t3_w1_05_mist_wolf_king_full_two_phase_loop() -> void:
	allow_expected_engine_error("unsupported format character")
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(140.0, 0.0), "enc_boss_loop")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_boss_loop", "pei_zhao", false)
	ctrl.set_locked_enemy(boss.actor_id, false)
	ctrl.preemptive_buff_timer = 0.0

	# 1) Phase 1 <=84% HP -> summons 2 wolf_pup adds
	var hp_p1_before: int = boss.hp
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 80.0, 1.0, "none", 5.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var shielded_ref_dmg: int = hp_p1_before - boss.hp

	eu_b["hp"] = int(round(float(boss.max_hp) * 0.82)) # 3444 / 4200 <= 84%
	boss.hp = int(eu_b["hp"])
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_true(bool(eu_b.get("summoned_p1", false)), "Phase 1 <=84% HP triggered wolf_pup summons")

	# 2) Shatter Wood Ward with Metal counter skill -> cancels P1 cast & opens 6.0s 气机破绽 (+35% vulnerability vs 25% shielded DR)
	var u_pei: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	u_pei["gcd_timer"] = 0.0
	(u_pei["cooldowns"] as Dictionary).clear()
	(ctrl.party_actors["pei_zhao"] as BattleActor).mp = 80
	eu_b["ward_current"] = 60.0
	boss.ward_current = 60.0
	ctrl._try_execute_party_skill("pei_zhao", "sk_pei_jinghong_thrust", boss.actor_id, false)
	assert_approx(boss.ward_current, 0.0, 0.01, "Metal thrust shattered Boss Wood Ward")
	assert_approx(boss.stagger_timer, 6.0, 0.05, "Boss entered 6.0s 气机破绽 stagger")

	eu_b["mother_seal_element"] = ""
	eu_b["mother_seal_timer"] = 0.0
	var hp_stagger_before: int = boss.hp
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 80.0, 1.0, "none", 5.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	var staggered_ref_dmg: int = hp_stagger_before - boss.hp
	assert_approx(float(staggered_ref_dmg) / float(shielded_ref_dmg), 1.35 / 0.75, 0.06, "气机破绽 boosts damage by 1.80x relative to shielded state")

	# 3) Push Boss to <=55% HP -> Phase 2 restores 450.0 Wood Ward, clears stagger, & casts Amber-Gold 腐木咆哮!
	eu_b["stun_timer"] = 0.0
	eu_b["lockout_timer"] = 0.0
	(eu_b["cooldowns"] as Dictionary).clear()
	eu_b["hp"] = int(round(float(boss.max_hp) * 0.52)) # 2184 / 4200 <= 55%
	boss.hp = int(eu_b["hp"])
	var p2_clk0: float = ctrl.combat_clock_sec
	for _p2_step: int in range(5):
		ctrl.step_world_and_combat(0.06, QinglanWorld.ZONE_BOUNDS)
		if ctrl.combat_clock_sec - p2_clk0 >= 0.05:
			break

	assert_eq(int(eu_b.get("phase", 1)), 2, "Boss transitioned to Phase 2 at <=55% HP")
	assert_approx(boss.ward_current, 450.0, 0.01, "Phase 2 restored full 450.0 Wood Ward")
	assert_approx(boss.stagger_timer, 0.0, 0.001, "Phase 2 cleared stagger_timer")
	assert_true(boss.is_casting and boss.cast_interruptible, "Phase 2 Boss immediately began Amber-Gold interruptible cast (腐木咆哮)")
	assert_eq(str(eu_b.get("cast_skill_id", "")), "sk_boss_roar_miasma", "Phase 2 cast skill is sk_boss_roar_miasma")

	# 4) Interrupt 腐木咆哮 with off-GCD Q -> 3.0s spell lockout + bonus ward shred
	(ctrl.unit_states["gu_changqing"] as Dictionary)["cooldowns"] = {}
	gu.mp = gu.max_mp
	ctrl.trigger_hotkey_slot("Q")
	assert_false(boss.is_casting, "Player off-GCD Q interrupted Phase 2 腐木咆哮")
	assert_approx(boss.lockout_timer, 3.0, 0.01, "Boss suffered 3.0s 破功封脉 lockout")
	assert_lt(boss.ward_current, 450.0 - 95.0, "Boss Phase 2 Wood Ward shredded by 22% bonus (99.0) + Q counter hit")
