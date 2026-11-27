extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 2
# @e2e_features: F5


func register_cases() -> void:
	add_case("T2-F05-01", 2, "F5", "polish_r1", "Comfort settings: 0% screen_shake_pct & reduced_motion suppress Ward-Break camera shake & hitstop (non-vacuous)", "case_t2_f05_01_comfort_suppresses_shake_and_hitstop")
	add_case("T2-F05-02", 2, "F5", "polish_r1", "Shaded actor_hit_flash.gdshader (zero unshaded) illuminated >=1.6x by PointLight2D under dark CanvasModulate", "case_t2_f05_02_shaded_hit_flash_pointlight_response")
	add_case("T2-F05-03", 2, "F5", "polish_r1", "Unshaded CombatVfxOverlay slashes, GPUParticles2D & Bagua telegraphs retain >=78% (>=0.55) brightness under 0.12 mood_modulate", "case_t2_f05_03_unshaded_vfx_ignores_dark_mood")
	add_case("T2-F05-04", 2, "F5", "polish_r1", "BattleActor hit-flash decays via ui_delta (>0.5 -> 0.0 within 0.30s) while tactical_paused == true", "case_t2_f05_04_hit_flash_decays_during_tactical_pause")
	add_case("T2-F05-05", 2, "F5", "polish_r1", "Golden fan-sweep radial progress: GCD slot 1 vs 5s CD slot 2 vs off-GCD Q across 0.05s..5.05s", "case_t2_f05_05_radial_gcd_vs_off_gcd_timeline")
	add_case("T2-F05-06", 2, "F5", "polish_r1", "BattleActor.get_vfx_origin_world('weapon') mirrors across +X/-X flip_h & empty F4 card hides avatar cleanly", "case_t2_f05_06_vfx_origin_mirror_and_f4_avatar_hygiene")


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


func _strip_gdshader_comments(code: String) -> String:
	return strip_shader_comments(code)


func _is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	return is_canvas_item_unshaded(ci)


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


func case_t2_f05_01_comfort_suppresses_shake_and_hitstop() -> void:
	allow_expected_engine_error("unsupported format character")

	# 1) Non-vacuity check: at screen_shake_pct = 0.80, reduced_motion = false, Ward-Break MUST trigger hitstop & shake
	SaveManager.screen_shake_pct = 0.80
	SaveManager.reduced_motion = false
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(120.0, 0.0), "enc_shk_all")
	var eu: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_shk_all", "gu_changqing", false)
	ctrl.step_world_and_combat(0.10, QinglanWorld.ZONE_BOUNDS)
	eu["ward_current"] = 25.0
	boss.ward_current = 25.0
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 45.0, 1.4, "metal", 30.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)

	assert_ge(float(obj_get(ctrl, "_hitstop_timer", -1.0)), 0.02, "Non-vacuity: 80% shake activates >=45ms Ward-Break hitstop")
	assert_gt(world._camera.offset.length(), 0.1, "Non-vacuity: 80% shake produces non-zero camera offset")

	for _i: int in range(16):
		ctrl.step_world_and_combat(0.03, QinglanWorld.ZONE_BOUNDS)
	world._camera.offset = Vector2.ZERO
	obj_set(ctrl, "_hitstop_timer", 0.0)

	# 2) Boundary A: screen_shake_pct == 0.0, reduced_motion == false -> 0.0 hitstop & Vector2.ZERO camera shake
	SaveManager.screen_shake_pct = 0.0
	SaveManager.reduced_motion = false
	eu["hp"] = 3500
	boss.hp = 3500
	eu["ward_current"] = 25.0
	boss.ward_current = 25.0
	eu["stagger_timer"] = 0.0
	boss.stagger_timer = 0.0
	var clk_z0: float = ctrl.combat_clock_sec
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 45.0, 1.4, "metal", 30.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)

	assert_approx(world._camera.offset.length(), 0.0, 0.001, "screen_shake_pct==0.0 suppresses camera offset to Vector2.ZERO")
	assert_approx(ctrl.combat_clock_sec - clk_z0, 0.02, 0.001, "screen_shake_pct==0.0 suppresses hitstop so combat_clock_sec advances full 0.02s")

	# 3) Boundary B: screen_shake_pct == 1.0, reduced_motion == true -> 0.0 hitstop & Vector2.ZERO camera shake
	SaveManager.screen_shake_pct = 1.0
	SaveManager.reduced_motion = true
	world._camera.offset = Vector2.ZERO
	obj_set(ctrl, "_hitstop_timer", 0.0)
	eu["hp"] = 3500
	boss.hp = 3500
	eu["ward_current"] = 25.0
	boss.ward_current = 25.0
	eu["stagger_timer"] = 0.0
	boss.stagger_timer = 0.0
	var clk_rm0: float = ctrl.combat_clock_sec
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, boss, 45.0, 1.4, "metal", 30.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)

	assert_approx(world._camera.offset.length(), 0.0, 0.001, "reduced_motion==true suppresses camera offset to Vector2.ZERO")
	assert_approx(ctrl.combat_clock_sec - clk_rm0, 0.02, 0.001, "reduced_motion==true suppresses hitstop so combat_clock_sec advances full 0.02s")


func case_t2_f05_02_shaded_hit_flash_pointlight_response() -> void:
	var sh_path: String = "res://src/presentation/shaders/actor_hit_flash.gdshader"
	assert_true(res_exists(sh_path), "actor_hit_flash.gdshader exists")
	if res_exists(sh_path):
		var raw_code: String = FileAccess.get_file_as_string(sh_path)
		var clean_code: String = strip_shader_comments(raw_code)
		assert_str_contains(clean_code, "shader_type canvas_item;", "actor_hit_flash.gdshader is canvas_item")
		assert_false(shader_code_has_unshaded_render_mode(raw_code), "actor_hit_flash.gdshader MUST NOT contain 'unshaded' render_mode")

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	world._hud.visible = false
	world._rain_overlay.visible = false
	world._mood_modulate.color = Color(0.14, 0.14, 0.14, 1.0)
	world._camera.position = Vector2(1100.0, 620.0)

	var actor_lit: BattleActor = BattleActor.new()
	actor_lit.position = Vector2(880.0, 660.0)
	actor_lit.setup_actor("lit_test", "party", "受光角色", "gu_changqing", 1.0)
	world._ysort_root.add_child(actor_lit)

	var actor_unlit: BattleActor = BattleActor.new()
	actor_unlit.position = Vector2(1320.0, 660.0)
	actor_unlit.setup_actor("unlit_test", "party", "暗处角色", "gu_changqing", 1.0)
	world._ysort_root.add_child(actor_unlit)

	assert_true(actor_lit._sprite.material is ShaderMaterial, "BattleActor._sprite mounts actor_hit_flash ShaderMaterial")
	assert_false(_is_canvas_item_unshaded(actor_lit._sprite), "BattleActor._sprite remains shaded (not LIGHT_MODE_UNSHADED)")

	var pt_light: PointLight2D = PointLight2D.new()
	pt_light.position = Vector2(880.0, 590.0)
	pt_light.texture = _make_radial_light_texture()
	pt_light.texture_scale = 1.6
	pt_light.energy = 2.4
	pt_light.color = Color(1.0, 0.92, 0.76, 1.0)
	world._ysort_root.add_child(pt_light)

	var img: Image = await capture_1080p_frame(18)
	# Camera centered at (1100, 620) on 1920x1080 -> screen x = world_x - 1100 + 960, screen y = world_y - 620 + 540
	# actor_lit torso around world (880, 585) -> screen (740, 505); actor_unlit torso around world (1320, 585) -> screen (1180, 505)
	var roi_lit: Dictionary = sample_image_roi_stats(img, Rect2i(716, 470, 48, 72))
	var roi_unlit: Dictionary = sample_image_roi_stats(img, Rect2i(1156, 470, 48, 72))

	var lum_lit: float = float(roi_lit.get("mean_luma", 0.0))
	var lum_unlit: float = maxf(0.001, float(roi_unlit.get("mean_luma", 0.0)))
	record_metric("lit_actor_mean_luma", lum_lit)
	record_metric("unlit_actor_mean_luma", lum_unlit)
	assert_ge(lum_lit / lum_unlit, 1.60, "PointLight2D illuminates shaded actor_hit_flash.gdshader >= 1.6x vs unlit actor")


func case_t2_f05_03_unshaded_vfx_ignores_dark_mood() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	SaveManager.reduced_motion = true

	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	world._hud.visible = false
	world._rain_overlay.visible = false
	world._mood_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.spawn_party_at(Vector2(1020.0, 640.0))
	world._camera.position = Vector2(1100.0, 620.0)
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1180.0, 640.0), "enc_vfx_mood")
	var eu: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_vfx_mood", "gu_changqing", false)
	ctrl._start_enemy_cast(eu, boss, "sk_boss_fan_pounce", DataDB.get_skill("sk_boss_fan_pounce"), ctrl.get_controlled_actor())
	eu["cast_progress"] = 1.6
	boss.cast_progress = 1.6

	# Capture 1: _mood_modulate = Color(1, 1, 1, 1)
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	ctrl._refresh_vfx_overlays(0.016)

	assert_true(_is_canvas_item_unshaded(world._sky_vfx), "sky_vfx uses LIGHT_MODE_UNSHADED / unshaded shader")
	assert_true(_is_canvas_item_unshaded(world._ground_vfx), "ground_vfx uses LIGHT_MODE_UNSHADED / unshaded shader")
	var img_bright: Image = await capture_1080p_frame(18)
	var stats_bright: Dictionary = sample_image_roi_stats(img_bright, Rect2i(940, 460, 240, 220))
	var max_lum_bright: float = float(stats_bright.get("max_luma", 0.0))

	# Capture 2: Same world with _mood_modulate = Color(0.12, 0.12, 0.14, 1.0) & fresh identical synergy burst
	world._mood_modulate.color = Color(0.12, 0.12, 0.14, 1.0)
	(ctrl.unit_states["shen_qinghe"] as Dictionary)["gcd_timer"] = 0.0
	((ctrl.unit_states["shen_qinghe"] as Dictionary)["cooldowns"] as Dictionary).clear()
	(ctrl.party_actors["shen_qinghe"] as BattleActor).mp = 90
	(ctrl.unit_states["gu_changqing"] as Dictionary)["gcd_timer"] = 0.0
	((ctrl.unit_states["gu_changqing"] as Dictionary)["cooldowns"] as Dictionary).clear()
	(ctrl.party_actors["gu_changqing"] as BattleActor).mp = 90
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	ctrl._refresh_vfx_overlays(0.016)

	var img_dark: Image = await capture_1080p_frame(18)
	var stats_dark: Dictionary = sample_image_roi_stats(img_dark, Rect2i(940, 460, 240, 220))
	var max_lum_dark: float = float(stats_dark.get("max_luma", 0.0))

	record_metric("vfx_max_luma_mood_100", max_lum_bright)
	record_metric("vfx_max_luma_mood_012", max_lum_dark)
	assert_gt(max_lum_bright, 0.45, "Bright combat VFX peak luminance > 0.45")
	assert_ge(max_lum_dark, max_lum_bright * 0.78, "Unshaded semi-transparent VFX retains >=78% peak brightness under 0.12 _mood_modulate")
	assert_ge(max_lum_dark, 0.55, "Unshaded combat VFX peak luminance >= 0.55 under 0.12 _mood_modulate")


func case_t2_f05_04_hit_flash_decays_during_tactical_pause() -> void:
	var world: QinglanWorld = _spawn_clean_arena("qinglan_pass")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.get_controlled_actor()
	var wolf: BattleActor = ctrl.spawn_enemy_unit("rot_wolf", gu.position + Vector2(120.0, 0.0), "enc_flash_pause")
	var eu_w: Dictionary = ctrl.unit_states[wolf.actor_id] as Dictionary
	eu_w["max_hp"] = 900
	eu_w["hp"] = 900
	wolf.max_hp = 900
	wolf.hp = 900
	ctrl.engage_enemy_group("enc_flash_pause", "gu_changqing", false)

	assert_true(obj_has_method(wolf, "trigger_hit_flash"), "BattleActor exposes trigger_hit_flash(duration, intensity) per PROJECT.md")
	ctrl._deal_damage_to_enemy("gu_changqing", gu.position, wolf, 30.0, 1.2, "metal", 20.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	if obj_has_method(wolf, "trigger_hit_flash"):
		obj_call(wolf, "trigger_hit_flash", [0.14, 1.0])

	var flash_t0: float = _read_hit_flash_amount(wolf)
	assert_gt(flash_t0, 0.50, "Hit-flash shader intensity > 0.50 immediately on hit")

	# Immediately enter Tactical Pause (combat_delta == 0.0) and step 0.30s ui_delta
	ctrl.toggle_tactical_pause()
	var clk_paused: float = ctrl.combat_clock_sec
	for _i: int in range(15):
		ctrl.step_world_and_combat(0.02, QinglanWorld.ZONE_BOUNDS)

	assert_approx(ctrl.combat_clock_sec, clk_paused, 0.0001, "combat_clock_sec stayed frozen while paused")
	var flash_after: float = _read_hit_flash_amount(wolf)
	assert_ge(flash_after, 0.0, "ShaderMaterial remains valid")
	assert_le(flash_after, 0.02, "Hit-flash decays via ui_delta to ~0.0 within 0.30s even while tactical_paused == true")


func case_t2_f05_05_radial_gcd_vs_off_gcd_timeline() -> void:
	SaveManager.reduced_motion = true
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud
	var gu: BattleActor = ctrl.get_controlled_actor()
	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", gu.position + Vector2(160.0, 0.0), "enc_rad")
	ctrl.engage_enemy_group("enc_rad", "gu_changqing", false)
	ctrl.set_locked_enemy(boss.actor_id, false)
	ctrl.auto_attack_enabled = false
	ctrl.preemptive_buff_timer = 0.0
	ctrl.party_haste_buff_val = 0.0

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	(u_gu["sheet"] as Dictionary)["haste_pct"] = 0.0
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	gu.mp = gu.max_mp

	# Cast sk_gu_flame_sword (slot "2", uses_gcd=true -> 1.50s GCD, cd=5.00s)
	ctrl.trigger_hotkey_slot("2")

	# Sample at t = 0.75s (halfway through 1.50s GCD, 4.25/5.00 = 0.85 of slot 2 CD)
	ctrl.step_world_and_combat(0.75, QinglanWorld.ZONE_BOUNDS)
	hud._process(0.016)
	var r1_075: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["1"] as Dictionary)
	var r2_075: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["2"] as Dictionary)
	var rq_075: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["Q"] as Dictionary)

	assert_true(bool(r1_075.get("is_radial", false)), "Slot '1' uses golden fan-sweep radial GCD widget")
	assert_approx(float(r1_075.get("ratio", -1.0)), 0.50, 0.08, "At t=0.75s, GCD slot '1' radial sweep is ~0.50")
	assert_approx(float(r2_075.get("ratio", -1.0)), 0.85, 0.08, "At t=0.75s, 5.0s CD slot '2' radial sweep is ~0.85")
	assert_le(float(rq_075.get("ratio", 1.0)), 0.01, "At t=0.75s, off-GCD slot 'Q' radial sweep stays 0.0 / hidden")

	# Sample at t = 1.55s (+0.80s): GCD finished on slot "1" (0.0), slot "2" at ~3.45/5.00 = 0.69
	ctrl.step_world_and_combat(0.80, QinglanWorld.ZONE_BOUNDS)
	hud._process(0.016)
	var r1_155: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["1"] as Dictionary)
	var r2_155: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["2"] as Dictionary)
	assert_le(float(r1_155.get("ratio", 1.0)), 0.01, "At t=1.55s, GCD slot '1' radial sweep clears to 0.0")
	assert_approx(float(r2_155.get("ratio", -1.0)), 0.69, 0.08, "At t=1.55s, 5.0s CD slot '2' radial sweep continues at ~0.69")

	# Sample at t = 5.05s (+3.50s): slot "2" 5.0s CD completed -> clears to 0.0
	for _i: int in range(7):
		gu.hp = gu.max_hp
		ctrl.step_world_and_combat(0.50, QinglanWorld.ZONE_BOUNDS)
	hud._process(0.016)
	var r2_505: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["2"] as Dictionary)
	assert_le(float(r2_505.get("ratio", 1.0)), 0.01, "At t=5.05s, 5.0s CD slot '2' radial sweep clears to 0.0")


func case_t2_f05_06_vfx_origin_mirror_and_f4_avatar_hygiene() -> void:
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	var world: QinglanWorld = _spawn_clean_arena("cangmu_cave")
	await step_frames(3)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor

	assert_true(obj_has_method(gu, "get_vfx_origin_world"), "BattleActor implements get_vfx_origin_world(slot) per PROJECT.md")
	if obj_has_method(gu, "get_vfx_origin_world"):
		gu.set_facing(Vector2(1.0, 0.35))
		gu.step_visuals(0.016, 0.016, false)
		assert_false(gu._sprite.flip_h, "Facing +X sets _sprite.flip_h == false")
		var pt_pos_x: Vector2 = obj_call(gu, "get_vfx_origin_world", ["weapon"]) as Vector2
		assert_lt(pt_pos_x.y, gu.position.y - 18.0, "Weapon VFX origin sits above FeetOrigin")
		assert_gt(pt_pos_x.x, gu.position.x + 2.0, "Weapon VFX origin lies on +X side when facing right")

		gu.set_facing(Vector2(-1.0, 0.35))
		gu.step_visuals(0.016, 0.016, false)
		assert_true(gu._sprite.flip_h, "Facing -X sets _sprite.flip_h == true")
		var pt_neg_x: Vector2 = obj_call(gu, "get_vfx_origin_world", ["weapon"]) as Vector2
		assert_lt(pt_neg_x.y, gu.position.y - 18.0, "Mirrored weapon VFX origin sits above FeetOrigin")
		assert_lt(pt_neg_x.x, gu.position.x - 2.0, "Weapon VFX origin mirrors to -X side when _sprite.flip_h == true")

	# Verify 4th empty party slot card is hidden with zero stray visible avatar TextureRects
	var card4: PanelContainer = (hud._party_cards[3] as Dictionary)["card"] as PanelContainer
	assert_false(card4.visible, "Empty 4th party slot card stays hidden in 3-person Chapter 1 roster")
	assert_eq(collect_visible_texture_rects(card4).size(), 0, "Hidden F4 card exposes 0 visible avatar TextureRects")
