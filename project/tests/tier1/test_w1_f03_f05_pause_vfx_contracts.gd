extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 1
# @e2e_features: F3, F5


func register_cases() -> void:
	add_case("T1-F03-01", 1, "F3", "baseline", "Space Tactical Pause freezes combat clock/positions/timers 100%, shows banner & enables 900Hz LPF", "case_t1_f03_01_tactical_pause_freeze_and_lpf")
	add_case("T1-F03-02", 1, "F3", "baseline", "Paused LMB drag box-select + RMB spread waypoints + F2/F3 skill queueing lines", "case_t1_f03_02_paused_box_select_and_queue")
	add_case("T1-F03-03", 1, "F3", "baseline", "Unpausing Space disables 900Hz LPF, advances clock, moves party & executes queued F2/F3 skills", "case_t1_f03_03_unpause_executes_queued_orders")
	add_case("T1-F03-04", 1, "F3", "baseline", "Companion AI presets: Shen cleanse & 72% vs 52% heal threshold; Pei auto-Q interrupt & tank Taunt", "case_t1_f03_04_companion_ai_presets")
	add_case("T1-F03-05", 1, "F3", "baseline", "Tier-2 Bond unlocks G (ult_qinglian_sword): spends 100 Qi for 240px Wood AoE + 125 ward shred + party heal/cleanse", "case_t1_f03_05_bond_ultimate_qinglian")
	add_case("T1-F05-01", 1, "F5", "polish_r1", "Polish R1 flying-sword auto-attack projectile/trail & curved ink-feibai / blazing-fire slash arc textures", "case_t1_f05_01_flying_sword_and_slash_arcs")
	add_case("T1-F05-02", 1, "F5", "polish_r1", "Polish R1 unshaded GPUParticles2D 5-element burst on wood_fire synergy at 1920x1080", "case_t1_f05_02_gpu_particles_synergy_burst")
	add_case("T1-F05-03", 1, "F5", "polish_r1", "Polish R1 foreshortened cinnabar Bagua floor telegraph (circle & cone) with unshaded material & visible FeetOrigin", "case_t1_f05_03_bagua_floor_telegraphs")
	add_case("T1-F05-04", 1, "F5", "polish_r1", "Polish R1 Ward-Break hit-feel: actor_hit_flash.gdshader + 45-115ms hitstop + camera micro-shake & decay", "case_t1_f05_04_ward_break_hitfeel_and_hitstop")
	add_case("T1-F05-05", 1, "F5", "polish_r1", "Polish R1 F1~F3 party cards: square bust avatar TextureRect (~78x78px) + canonical 气血/真元 labels", "case_t1_f05_05_party_frame_bust_avatars")
	add_case("T1-F05-06", 1, "F5", "polish_r1", "Polish R1 carved ebony gilt-bronze action bar frames, gcd_total/cooldown_totals & golden radial GCD sweep", "case_t1_f05_06_carved_action_bar_and_radial_gcd")


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
	var candidates: Array[String] = ["flash_amount", "flash_intensity", "hit_flash", "flash", "intensity", "mix_amount"]
	for cname: String in candidates:
		var v: Variant = smat.get_shader_parameter(cname)
		if v is float or v is int:
			return float(v)
	var ulist: Array[Dictionary] = smat.shader.get_shader_uniform_list()
	for u: Dictionary in ulist:
		if int(u.get("type", -1)) == TYPE_FLOAT:
			var uname: String = str(u.get("name", ""))
			var val: Variant = smat.get_shader_parameter(uname)
			if val is float or val is int:
				return float(val)
	return 0.0


func _count_pngs_in_res_dir(res_dir: String) -> int:
	var abs_dir: String = ProjectSettings.globalize_path(res_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return 0
	var da: DirAccess = DirAccess.open(abs_dir)
	if da == null:
		return 0
	var cnt: int = 0
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".png"):
			cnt += 1
		fname = da.get_next()
	da.list_dir_end()
	return cnt


func _inspect_slot_radial_widget(slot_w: Dictionary) -> Dictionary:
	var tile: Control = slot_w.get("tile", null) as Control
	var cd_ov: Control = slot_w.get("cd_overlay", null) as Control
	if tile == null:
		return {"is_radial": false, "ratio": -1.0}

	var stack: Array[Node] = [tile]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is TextureProgressBar:
			var tpb: TextureProgressBar = cur as TextureProgressBar
			if tpb.fill_mode >= TextureProgressBar.FILL_CLOCKWISE:
				var r: float = (tpb.value / maxf(0.0001, tpb.max_value)) if tpb.visible else 0.0
				return {"is_radial": true, "ratio": r}
		if cur is CanvasItem:
			var ci: CanvasItem = cur as CanvasItem
			if ci.material is ShaderMaterial:
				var smat: ShaderMaterial = ci.material as ShaderMaterial
				for pname: String in ["progress", "ratio", "sweep_ratio", "cd_ratio", "remaining_ratio", "fill_ratio"]:
					var pv: Variant = smat.get_shader_parameter(pname)
					if pv is float or pv is int:
						return {"is_radial": true, "ratio": float(pv) if ci.visible else 0.0}
				if smat.shader != null:
					for u: Dictionary in smat.shader.get_shader_uniform_list():
						if int(u.get("type", -1)) == TYPE_FLOAT:
							var uname: String = str(u.get("name", ""))
							var uv: Variant = smat.get_shader_parameter(uname)
							if uv is float or uv is int:
								return {"is_radial": true, "ratio": float(uv) if ci.visible else 0.0}
			if cur.get_script() != null and cur != tile:
				for prop_n: String in ["progress", "ratio", "sweep_ratio", "cd_ratio", "remaining_ratio"]:
					if obj_has_prop(cur, prop_n):
						var sv: float = float(obj_get(cur, prop_n, 0.0))
						return {"is_radial": true, "ratio": sv if ci.visible else 0.0}
		for ch: Node in cur.get_children():
			stack.append(ch)

	if cd_ov != null and cd_ov.material == null and cd_ov.get_script() == null:
		return {"is_radial": false, "ratio": -1.0}
	return {"is_radial": false, "ratio": -1.0}


func case_t1_f03_01_tactical_pause_freeze_and_lpf() -> void:
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", gu.position + Vector2(210.0, 0.0), "enc_tp1")
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_tp1", "gu_changqing", false)
	ctrl.step_world_and_combat(0.15, QinglanWorld.ZONE_BOUNDS) # shaman starts casting

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	u_gu["gcd_timer"] = 1.15
	gu.move_waypoint = gu.position + Vector2(180.0, 40.0)
	gu.has_move_waypoint = true
	eu_sh["mother_seal_element"] = "wood"
	eu_sh["mother_seal_timer"] = 5.20
	shaman.mother_seal_element = "wood"
	shaman.mother_seal_timer = 5.20

	var snap_clock: float = ctrl.combat_clock_sec
	var snap_pos: Vector2 = gu.position
	var snap_gcd: float = float(u_gu["gcd_timer"])
	var snap_cast: float = shaman.cast_progress
	var snap_seal: float = shaman.mother_seal_timer

	dispatch_input(make_key_event(KEY_SPACE, true))
	await step_frames(2)

	assert_true(ctrl.tactical_paused, "KEY_SPACE enables tactical_paused in active combat")
	assert_true(world._hud._pause_banner.visible, "CombatHud tactical pause watermark banner is visible")

	var bgm_idx: int = AudioServer.get_bus_index("BGM_Bus")
	var amb_idx: int = AudioServer.get_bus_index("Ambient_UI_Bus")
	assert_ge(float(bgm_idx), 0.0, "BGM_Bus exists")
	assert_ge(float(amb_idx), 0.0, "Ambient_UI_Bus exists")
	assert_true(AudioServer.is_bus_effect_enabled(bgm_idx, 0), "BGM_Bus 900Hz LPF enabled during Tactical Pause")
	assert_true(AudioServer.is_bus_effect_enabled(amb_idx, 0), "Ambient_UI_Bus 900Hz LPF enabled during Tactical Pause")
	var lpf: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bgm_idx, 0) as AudioEffectLowPassFilter
	assert_not_null(lpf, "AudioEffectLowPassFilter mounted at slot 0")
	if lpf != null:
		assert_approx(lpf.cutoff_hz, 900.0, 1.0, "Tactical Pause underwater LPF cutoff is 900Hz")

	# Advance 2.0s real time (4 x 0.50s) while paused
	for _i: int in range(4):
		ctrl.step_world_and_combat(0.50, QinglanWorld.ZONE_BOUNDS)

	assert_approx(ctrl.combat_clock_sec, snap_clock, 0.0001, "combat_clock_sec 100% frozen during Tactical Pause")
	assert_approx(gu.position.distance_to(snap_pos), 0.0, 0.0001, "Actor world position 100% frozen during Tactical Pause")
	assert_approx(float(u_gu["gcd_timer"]), snap_gcd, 0.0001, "GCD timer 100% frozen during Tactical Pause")
	assert_approx(shaman.cast_progress, snap_cast, 0.0001, "Enemy cast_progress 100% frozen during Tactical Pause")
	assert_approx(shaman.mother_seal_timer, snap_seal, 0.0001, "Mother Seal countdown 100% frozen during Tactical Pause")


func case_t1_f03_02_paused_box_select_and_queue() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.contract_spirit_pet("pet_fire_fox")
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.spawn_party_at(Vector2(1200.0, 700.0))
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(150.0, 0.0), "enc_tp2")
	ctrl.engage_enemy_group("enc_tp2", "gu_changqing", false)
	ctrl.set_locked_enemy(golem.actor_id, false)
	world._camera.position = Vector2(1200.0, 700.0)
	await step_frames(2)

	ctrl.toggle_tactical_pause()
	assert_true(ctrl.tactical_paused, "Entered Tactical Pause")

	# Simulate LMB drag box-select across screen center (covering Gu, Pei, Shen, and pet_fire_fox)
	world._unhandled_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(720.0, 320.0), true))
	world._unhandled_input(make_mouse_motion_event(Vector2(1200.0, 720.0)))
	assert_true(world._hud._is_box_selecting, "HUD renders box-selection marquee during LMB drag")
	world._unhandled_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(1200.0, 720.0), false))

	assert_ge(float(ctrl.box_selected_ids.size()), 3.0, "Box-select captured >= 3 allied units")
	assert_true(ctrl.box_selected_ids.has("gu_changqing"), "gu_changqing box-selected")
	assert_true(ctrl.box_selected_ids.has("pei_zhao"), "pei_zhao box-selected")
	assert_true(ctrl.box_selected_ids.has("shen_qinghe"), "shen_qinghe box-selected")

	# Issue RMB spread move destination & queue skills on F2 (Pei) and F3 (Shen)
	var dest: Vector2 = gu.position + Vector2(-90.0, 110.0)
	ctrl.command_move_selected_to(dest)

	ctrl.switch_controlled_party_slot(2, false) # Pei Zhao
	ctrl.trigger_hotkey_slot("1") # sk_pei_jinghong_thrust
	ctrl.switch_controlled_party_slot(3, false) # Shen Qinghe
	ctrl.trigger_hotkey_slot("4") # sk_shen_vine_bind

	ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	assert_ge(float(world._ground_vfx.move_previews.size()), 3.0, "ground_vfx renders >= 3 tactical move_previews")
	var wp_gu: Vector2 = (ctrl.party_actors["gu_changqing"] as BattleActor).move_waypoint
	var wp_pei: Vector2 = (ctrl.party_actors["pei_zhao"] as BattleActor).move_waypoint
	var wp_shen: Vector2 = (ctrl.party_actors["shen_qinghe"] as BattleActor).move_waypoint
	assert_gt(wp_gu.distance_to(wp_pei), 20.0, "Spread offsets give distinct move_waypoints (Gu vs Pei)")
	assert_gt(wp_pei.distance_to(wp_shen), 20.0, "Spread offsets give distinct move_waypoints (Pei vs Shen)")
	for mp: Dictionary in world._ground_vfx.move_previews:
		assert_ne(str(mp.get("label", "")), "", "Paused move_preview carries character name label")

	var u_pei: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	assert_eq(str(u_pei.get("queued_skill_id", "")), "sk_pei_jinghong_thrust", "Pei Zhao queued sk_pei_jinghong_thrust")
	assert_eq(str(u_shen.get("queued_skill_id", "")), "sk_shen_vine_bind", "Shen Qinghe queued sk_shen_vine_bind")
	assert_eq(world._sky_vfx.queued_skill_lines.size(), 2, "sky_vfx renders 2 queued_skill_lines while paused")


func case_t1_f03_03_unpause_executes_queued_orders() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor

	pei.position = gu.position + Vector2(20.0, -15.0)
	shen.position = gu.position + Vector2(-30.0, 20.0)
	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(120.0, 0.0), "enc_tp3")
	ctrl.engage_enemy_group("enc_tp3", "gu_changqing", false)
	ctrl.set_locked_enemy(golem.actor_id, false)

	ctrl.toggle_tactical_pause()
	ctrl.box_selected_ids = ["gu_changqing", "pei_zhao", "shen_qinghe"]
	ctrl.command_move_selected_to(gu.position + Vector2(-80.0, 80.0))

	ctrl.switch_controlled_party_slot(2, false)
	ctrl.trigger_hotkey_slot("1") # sk_pei_jinghong_thrust (range 165px, dist ~101px)
	ctrl.switch_controlled_party_slot(3, false)
	ctrl.trigger_hotkey_slot("4") # sk_shen_vine_bind (range 410px)
	ctrl.switch_controlled_party_slot(1, false)

	var gu_pos_before: Vector2 = gu.position
	var golem_hp_before: int = golem.hp
	var clock_before: float = ctrl.combat_clock_sec

	# Unpause via Space and step 0.25s combat time
	ctrl.toggle_tactical_pause()
	assert_false(ctrl.tactical_paused, "tactical_paused cleared to false")
	assert_false(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("BGM_Bus"), 0), "BGM_Bus 900Hz LPF disabled on unpause")
	assert_false(AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index("Ambient_UI_Bus"), 0), "Ambient_UI_Bus 900Hz LPF disabled on unpause")

	for _i: int in range(12):
		if ctrl.combat_clock_sec - clock_before >= 0.245:
			break
		ctrl.step_world_and_combat(0.05, QinglanWorld.ZONE_BOUNDS)

	assert_approx(ctrl.combat_clock_sec - clock_before, 0.25, 0.005, "combat_clock_sec advanced by 0.25s after unpause")
	assert_lt(gu.position.distance_to(gu.move_waypoint), gu_pos_before.distance_to(gu.move_waypoint), "Box-selected Gu moved toward move_waypoint")

	var u_pei: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary
	assert_eq(str(u_pei.get("queued_skill_id", "")), "", "Pei Zhao queued_skill_id consumed & executed")
	assert_gt(float(u_pei.get("gcd_timer", 0.0)), 0.5, "Pei Zhao entered GCD after executing queued skill")
	assert_eq(str(u_shen.get("queued_skill_id", "")), "", "Shen Qinghe queued_skill_id consumed & executed")
	assert_gt(float(u_shen.get("gcd_timer", 0.0)), 0.5, "Shen Qinghe entered GCD after executing queued skill")
	assert_lt(float(golem.hp), float(golem_hp_before), "Enemy took damage from queued skills")


func case_t1_f03_04_companion_ai_presets() -> void:
	allow_expected_engine_error("unsupported format character")
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(1)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var u_pei: Dictionary = ctrl.unit_states["pei_zhao"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary

	var shaman: BattleActor = ctrl.spawn_enemy_unit("miasma_shaman", gu.position + Vector2(130.0, 0.0), "enc_ai")
	var eu_sh: Dictionary = ctrl.unit_states[shaman.actor_id] as Dictionary
	eu_sh["max_hp"] = 2000
	eu_sh["hp"] = 2000
	shaman.max_hp = 2000
	shaman.hp = 2000
	ctrl.engage_enemy_group("enc_ai", "gu_changqing", false)
	ctrl.set_locked_enemy(shaman.actor_id, false)

	# 1) Shen AI cleanses miasma via sk_shen_sweet_rain
	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 0
	u_pei["miasma_stacks"] = 1
	pei.miasma_stacks = 1
	u_shen["gcd_timer"] = 0.0
	(u_shen["cooldowns"] as Dictionary).clear()
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_eq(str(u_shen.get("cast_skill_id", "")), "sk_shen_sweet_rain", "Shen AI starts sk_shen_sweet_rain when ally has miasma")
	_step_combat_at_least(ctrl, 1.50, 0.10, 22)
	assert_eq(pei.miasma_stacks, 0, "Shen AI completed cast and cleansed Pei Zhao miasma")

	# 2) Shen AI preset 2 (conserve_mana, threshold 0.52) vs preset 0 (mercy_healer, threshold 0.72) at 62% HP
	pei.hp = int(round(float(pei.max_hp) * 0.62))
	gu.hp = gu.max_hp
	shen.hp = shen.max_hp
	shen.mp = shen.max_mp
	u_shen["gcd_timer"] = 0.0
	(u_shen["cooldowns"] as Dictionary).clear()
	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 2
	var pei_hp_62: int = pei.hp
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_eq(pei.hp, pei_hp_62, "Shen preset 2 (conserve_mana, <52%) conserves mana at 62% ally HP")

	(CampaignState.party_members["shen_qinghe"] as Dictionary)["ai_preset_index"] = 0
	u_shen["gcd_timer"] = 0.0
	(u_shen["cooldowns"] as Dictionary).clear()
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_gt(float(pei.hp), float(pei_hp_62), "Shen preset 0 (mercy_healer, <72%) immediately heals 62% HP ally")

	# 3) Pei AI preset 0 (ward_breaker) auto-interrupts shaman Amber-Gold cast at >= 42% progress
	(CampaignState.party_members["pei_zhao"] as Dictionary)["ai_preset_index"] = 0
	(u_pei["cooldowns"] as Dictionary).clear()
	pei.mp = pei.max_mp
	eu_sh["lockout_timer"] = 0.0
	ctrl._start_enemy_cast(eu_sh, shaman, "sk_enemy_miasma_bolt", DataDB.get_skill("sk_enemy_miasma_bolt"), gu)
	eu_sh["cast_progress"] = 1.15 # > 2.10 * 0.42
	shaman.cast_progress = 1.15
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_false(shaman.is_casting, "Pei preset 0 (ward_breaker) auto-interrupted shaman cast via Q")
	assert_gt(shaman.lockout_timer, 2.8, "Pei auto-interrupt applied ~3.0s lockout")

	# 4) Pei AI preset 1 (tank_anchor) auto-Taunts when enemy targets Shen Qinghe
	(CampaignState.party_members["pei_zhao"] as Dictionary)["ai_preset_index"] = 1
	(u_pei["cooldowns"] as Dictionary).clear()
	pei.mp = pei.max_mp
	eu_sh["target_id"] = "shen_qinghe"
	eu_sh["taunt_timer"] = 0.0
	(eu_sh["threat_table"] as Dictionary)["shen_qinghe"] = 400.0
	_step_combat_at_least(ctrl, 0.049, 0.05, 6)
	assert_eq(str(eu_sh.get("taunt_target_id", "")), "pei_zhao", "Pei preset 1 auto-fired sk_pei_qingyun_challenge Taunt")
	assert_eq(str(eu_sh.get("target_id", "")), "pei_zhao", "Enemy target snapped to Pei Zhao after AI Taunt")


func case_t1_f03_05_bond_ultimate_qinglian() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.add_companion_bond("shen_qinghe", 1) # Tier 1 -> Tier 2 unlocks ult_qinglian_sword
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "Bond Tier 2 unlocks ult_qinglian_sword")

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	var u_shen: Dictionary = ctrl.unit_states["shen_qinghe"] as Dictionary

	var g_widget: Dictionary = world._hud._slot_widgets.get("G", {}) as Dictionary
	assert_true((g_widget["tile"] as Control).visible, "CombatHud G slot tile visible when ult_qinglian_sword unlocked")

	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(180.0, 0.0), "enc_ult")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	eu_g["ward_max"] = 250.0
	eu_g["ward_current"] = 250.0
	golem.ward_max = 250.0
	golem.ward_current = 250.0
	ctrl.engage_enemy_group("enc_ult", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.set_locked_enemy(golem.actor_id, false)

	gu.hp = int(round(float(gu.max_hp) * 0.50))
	shen.hp = int(round(float(shen.max_hp) * 0.50))
	u_gu["miasma_stacks"] = 1
	gu.miasma_stacks = 1
	u_shen["miasma_stacks"] = 1
	shen.miasma_stacks = 1
	u_gu["shield"] = 0.0
	u_shen["shield"] = 0.0
	ctrl.team_attunement = 100.0

	var banners: Array[Dictionary] = []
	NotifyHub.combat_banner_pushed.connect(func(p: Dictionary) -> void: banners.append(p))

	var golem_hp_before: int = golem.hp
	var gu_hp_before: int = gu.hp
	var shen_hp_before: int = shen.hp

	ctrl.trigger_hotkey_slot("G")
	assert_lt(ctrl.team_attunement, 20.0, "G ultimate consumed 100.0 Team Qi")
	assert_lt(float(golem.hp), float(golem_hp_before - 30), "ult_qinglian_sword dealt heavy Wood AoE damage within 240px")
	assert_ge(250.0 - golem.ward_current, 120.0, "ult_qinglian_sword shredded >=125 base ward")
	assert_gt(float(gu.hp), float(gu_hp_before), "ult_qinglian_sword healed Gu Changqing")
	assert_gt(float(shen.hp), float(shen_hp_before), "ult_qinglian_sword healed Shen Qinghe")
	assert_gt(float(u_gu.get("shield", 0.0)), 10.0, "ult_qinglian_sword granted lotus shield to party")
	assert_eq(gu.miasma_stacks, 0, "ult_qinglian_sword cleansed Gu miasma")
	assert_eq(shen.miasma_stacks, 0, "ult_qinglian_sword cleansed Shen miasma")

	var saw_ult: bool = false
	for b: Dictionary in banners:
		if str(b.get("category", "")) == "ultimate":
			saw_ult = true
	assert_true(saw_ult, "NotifyHub emitted 'ultimate' combat banner")


func case_t1_f05_01_flying_sword_and_slash_arcs() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	(CampaignState.party_members["pei_zhao"] as Dictionary)["active_spec"] = "spec_b" # sk_pei_blaze_slash on slot 1
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(130.0, 0.0), "enc_r1_slash")
	pei.position = boss.position + Vector2(-110.0, 40.0)
	ctrl.engage_enemy_group("enc_r1_slash", "gu_changqing", false)
	ctrl.set_locked_enemy(boss.actor_id, false)

	var vfx_png_cnt: int = _count_pngs_in_res_dir("res://assets/vfx")
	assert_ge(float(vfx_png_cnt), 3.0, "res://assets/vfx/ contains >= 3 registered sword/slash/VFX textures")

	var sky_vfx: CombatVfxOverlay = world._sky_vfx
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary

	# 1) Auto-attack must spawn a physical flying-sword / slash trail VFX (v0.1.3-slice spawns 0!)
	sky_vfx.transient_fx.clear()
	ctrl._perform_party_auto_attack("gu_changqing", gu, u_gu, boss)
	var auto_vfx_count: int = sky_vfx.transient_fx.size() + count_visible_canvas_children(sky_vfx)
	assert_gt(float(auto_vfx_count), 0.0, "Gu Changqing auto-attack spawns visible flying-sword/slash VFX on sky_vfx")

	# 2) Gu sk_gu_qingming_qi (ink-feibai / sword) & Pei sk_pei_blaze_slash (blazing-fire curved arc)
	u_gu["gcd_timer"] = 0.0
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_qingming_qi", boss.actor_id, true)
	ctrl._try_execute_party_skill("pei_zhao", "sk_pei_blaze_slash", boss.actor_id, false)

	var legacy_beam_count: int = 0
	for fx: Dictionary in sky_vfx.transient_fx:
		if str(fx.get("kind", "")) == "beam" and not fx.has("texture") and not fx.has("tex"):
			legacy_beam_count += 1
	assert_eq(legacy_beam_count, 0, "CombatVfxOverlay eliminated unpolished 2-line 'beam' placeholder FX")
	await step_frames(3)


func case_t1_f05_02_gpu_particles_synergy_burst() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(160.0, 0.0), "enc_r1_part")
	ctrl.engage_enemy_group("enc_r1_part", "gu_changqing", false)
	ctrl.set_locked_enemy(boss.actor_id, false)
	world._camera.position = boss.position

	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)

	var active_particles: Array[GPUParticles2D] = collect_active_gpu_particles(world)
	assert_ge(float(active_particles.size()), 1.0, "wood_fire synergy spawns >= 1 active visible GPUParticles2D burst node")

	var valid_unshaded_particles: int = 0
	for gp: GPUParticles2D in active_particles:
		if _is_canvas_item_unshaded(gp):
			valid_unshaded_particles += 1
	assert_ge(float(valid_unshaded_particles), 1.0, "Active 5-element GPUParticles2D has process_material != null and unshaded material")

	var img: Image = await capture_1080p_frame(18)
	var impact_roi: Dictionary = sample_image_roi_stats(img, Rect2i(860, 420, 220, 220))
	assert_gt(float(impact_roi.get("max_luma", 0.0)), 0.45, "1920x1080 viewport shows bright mineral-fire burst luminance at Boss impact center")


func case_t1_f05_03_bagua_floor_telegraphs() -> void:
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()

	var golem: BattleActor = ctrl.spawn_enemy_unit("wood_golem", gu.position + Vector2(180.0, -40.0), "enc_r1_tele")
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(-180.0, 40.0), "enc_r1_tele")
	var eu_g: Dictionary = ctrl.unit_states[golem.actor_id] as Dictionary
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_r1_tele", "gu_changqing", false)

	ctrl._start_enemy_cast(eu_g, golem, "sk_enemy_golem_slam", DataDB.get_skill("sk_enemy_golem_slam"), gu)
	eu_g["cast_progress"] = float(eu_g["cast_duration"]) * 0.55
	golem.cast_progress = float(eu_g["cast_progress"])

	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_fan_pounce", DataDB.get_skill("sk_boss_fan_pounce"), gu)
	eu_b["cast_progress"] = float(eu_b["cast_duration"]) * 0.55
	boss.cast_progress = float(eu_b["cast_progress"])

	ctrl._refresh_vfx_overlays(0.016)
	var ground_vfx: CombatVfxOverlay = world._ground_vfx
	assert_eq(ground_vfx.active_telegraphs.size(), 2, "Both circle and cone telegraphs registered on ground_vfx")

	# Verify ground_vfx (or child Bagua sprite/shader node) is unshaded and uses Bagua texture/trigram art
	var has_bagua_asset: bool = false
	var abs_vfx: String = ProjectSettings.globalize_path("res://assets/vfx")
	if DirAccess.dir_exists_absolute(abs_vfx):
		var da: DirAccess = DirAccess.open(abs_vfx)
		if da != null:
			da.list_dir_begin()
			var fn: String = da.get_next()
			while fn != "":
				var low: String = fn.to_lower()
				if low.ends_with(".png") and (low.contains("bagua") or low.contains("telegraph") or low.contains("circle") or low.contains("ring") or low.contains("cone")):
					has_bagua_asset = true
				fn = da.get_next()
			da.list_dir_end()
	assert_true(has_bagua_asset, "res://assets/vfx/ contains dedicated cinnabar Bagua telegraph texture")
	assert_true(_is_canvas_item_unshaded(ground_vfx), "ground_vfx uses unshaded material so _mood_modulate never darkens danger telegraphs")
	await step_frames(3)


func case_t1_f05_04_ward_break_hitfeel_and_hitstop() -> void:
	allow_expected_engine_error("unsupported format character")
	SaveManager.screen_shake_pct = 0.40
	SaveManager.reduced_motion = false

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(130.0, 0.0), "enc_r1_hit")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_r1_hit", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)

	assert_true(res_exists("res://src/presentation/shaders/actor_hit_flash.gdshader"), "actor_hit_flash.gdshader exists")

	# Shatter remaining Wood Ward -> triggers hit_flash + 45-115ms hitstop + camera micro-shake
	eu_b["ward_current"] = 30.0
	boss.ward_current = 30.0
	var clock_at_break: float = ctrl.combat_clock_sec
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 45.0, 1.4, "metal", 30.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")

	var flash_val: float = _read_hit_flash_amount(boss)
	assert_gt(flash_val, 0.1, "BattleActor._sprite ShaderMaterial activates hit-flash uniform > 0.1 on Ward-Break")

	var hitstop_v: Variant = obj_get(ctrl, "_hitstop_timer", -1.0)
	var hitstop_sec: float = float(hitstop_v)
	assert_ge(hitstop_sec, 0.045, "Ward-Break _hitstop_timer >= 45ms")
	assert_le(hitstop_sec, 0.120, "Ward-Break _hitstop_timer <= 115ms")

	# Step 0.02s (< 45ms): combat_clock_sec MUST stay frozen while tactical_paused == false!
	ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)
	assert_false(ctrl.tactical_paused, "Hitstop freeze is distinct from Space tactical_paused")
	assert_approx(ctrl.combat_clock_sec, clock_at_break, 0.0005, "combat_clock_sec stays frozen during 0.02s hitstop step")

	var cam_shake_during: float = world._camera.offset.length()
	assert_gt(cam_shake_during, 0.1, "world._camera.offset > 0.1px during Ward-Break micro-shake")

	# Step 0.45s so hitstop & camera shake decay completely
	for _i: int in range(15):
		ctrl.step_world_and_combat(0.03, QinglanWorld.ZONE_BOUNDS)
	assert_gt(ctrl.combat_clock_sec, clock_at_break + 0.25, "combat_clock_sec resumes advancing after hitstop expires")
	assert_approx(world._camera.offset.length(), 0.0, 0.05, "world._camera.offset decays cleanly back to 0.0")


func case_t1_f05_05_party_frame_bust_avatars() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(5)
	var hud: CombatHud = world._hud

	for idx: int in range(3):
		var cinfo: Dictionary = hud._party_cards[idx]
		var card: PanelContainer = cinfo["card"] as PanelContainer
		assert_true(card.visible, "Party card F%d is visible" % (idx + 1))

		var tex_rects: Array[TextureRect] = collect_visible_texture_rects(card)
		var found_square_bust: bool = false
		for tr_node: TextureRect in tex_rects:
			var sz: Vector2 = tr_node.size
			if sz.x < 1.0:
				sz = tr_node.custom_minimum_size
			if tr_node.texture != null and sz.x >= 54.0 and sz.x <= 98.0 and sz.y >= 54.0 and sz.y <= 98.0:
				found_square_bust = true
				break
		assert_true(found_square_bust, "Party card F%d contains visible square bust avatar TextureRect (~78x78px)" % (idx + 1))

		var hp_txt: String = (cinfo["hp_lbl"] as Label).text
		var mp_txt: String = (cinfo["mp_lbl"] as Label).text
		assert_str_contains(hp_txt, "气血", "F%d HP bar uses canonical '气血' label" % (idx + 1))
		assert_str_contains(mp_txt, "真元", "F%d MP bar uses canonical '真元' label" % (idx + 1))
		assert_str_not_contains(hp_txt, "HP", "F%d HP bar has zero raw 'HP' English token" % (idx + 1))
		assert_str_not_contains(mp_txt, "MP", "F%d MP bar has zero raw 'MP' English token" % (idx + 1))


func case_t1_f05_06_carved_action_bar_and_radial_gcd() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.unlock_formation("dizai", true)
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(3)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(180.0, 0.0), "enc_r1_hud")
	ctrl.engage_enemy_group("enc_r1_hud", "gu_changqing", false)
	ctrl.preemptive_buff_timer = 0.0
	ctrl.set_locked_enemy(boss.actor_id, false)

	# 1) Carved ebony/gilt-bronze HUD frame textures in res://assets/ui/frames/
	var frame_pngs: int = _count_pngs_in_res_dir("res://assets/ui/frames")
	assert_ge(float(frame_pngs), 2.0, "res://assets/ui/frames/ contains carved dark-ebony gilt-bronze HUD frame assets")

	# 2) Cast sk_gu_flame_sword (slot "2", cd=5.0s, uses_gcd=true) and inspect gcd_total / cooldown_totals
	ctrl.trigger_hotkey_slot("2")
	await step_frames(2)

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	assert_true(u_gu.has("gcd_total"), "unit_states['gu_changqing'] exposes 'gcd_total' (PROJECT.md Contract 1)")
	assert_ge(float(u_gu.get("gcd_total", 0.0)), 1.0, "gcd_total >= 1.0s")
	assert_true(u_gu.has("cooldown_totals"), "unit_states['gu_changqing'] exposes 'cooldown_totals' Dictionary")
	var cd_totals: Dictionary = as_dict(u_gu.get("cooldown_totals", {}))
	assert_approx(float(cd_totals.get("sk_gu_flame_sword", 0.0)), 5.0, 0.05, "cooldown_totals['sk_gu_flame_sword'] == 5.0s")

	# 3) Verify slot "1" & "2" use golden fan-sweep radial widget (not plain unscripted ColorRect)
	var rad_1: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["1"] as Dictionary)
	var rad_2: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["2"] as Dictionary)
	assert_true(bool(rad_1.get("is_radial", false)), "Slot '1' renders golden fan-sweep radial GCD sector")
	assert_true(bool(rad_2.get("is_radial", false)), "Slot '2' renders golden fan-sweep radial cooldown sector")

	# 4) Verify canonical PC hotkey labels (never circled numbers ①-⑩)
	var forbidden_circled: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
	for slot_code: String in ["1", "2", "3", "4", "Q", "E", "R", "5", "6", "Z"]:
		var sw: Dictionary = hud._slot_widgets[slot_code] as Dictionary
		var klbl: String = (sw["key_lbl"] as Label).text
		assert_str_contains(klbl, slot_code, "Action slot '%s' displays canonical key '%s'" % [slot_code, slot_code])
		for circ: String in forbidden_circled:
			assert_str_not_contains(klbl, circ, "Action slot '%s' never uses circled number '%s'" % [slot_code, circ])
