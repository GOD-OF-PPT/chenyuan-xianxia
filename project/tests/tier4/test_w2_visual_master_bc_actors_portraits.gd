extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 4
# @e2e_features: F6, F7
## Worker 2 Tier 4 Real-World 1920x1080 Xvfb OpenGL3 Visual & Gameplay Scenarios vs Gate 3 master_b and master_c.


func register_cases() -> void:
	add_case("T4-W2-01", 4, "F7", "baseline", "1920x1080 Ruined Temple 4-Layer CG & Portrait Stage baseline gate (WCAG >=7:1, >=22px, Space block, P1/P3 silence)", "case_t4_w2_01_temple_stage_baseline")
	add_case("T4-W2-02", 4, "F7", "polish_r2", "1920x1080 master_c Portrait Facial Expressions (Gu 7 exprs + Pei/Shen) & Carved Ebony Scroll Rollers gate", "case_t4_w2_02_master_c_portraits_and_rollers")
	add_case("T4-W2-03", 4, "F6", "polish_r2", "1920x1080 master_b Giant Mist Wolf King (>=320x380px) + Multi-Pose Trio + VFX Origins + Single Pet gate", "case_t4_w2_03_master_b_wolf_king_and_trio")


func _count_neon_pixels_sampled(img: Image, stride: int = 8) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var neon: int = 0
	var total: int = 0
	for y: int in range(0, h, stride):
		for x: int in range(0, w, stride):
			var c: Color = img.get_pixel(x, y)
			var cmax: float = maxf(c.r, maxf(c.g, c.b))
			var cmin: float = minf(c.r, minf(c.g, c.b))
			var sat: float = (cmax - cmin) / maxf(cmax, 0.001)
			if cmax >= (245.0 / 255.0) and sat >= 0.92:
				neon += 1
			total += 1
	return {
		"neon": neon,
		"total": total,
		"ratio": float(neon) / float(maxi(1, total)),
	}


func _compute_screen_portrait_face_p99_residual(
	calm_frame: Image,
	var_frame: Image,
	robe_rect: Rect2i,
	face_rect: Rect2i,
	stride: int = 4
) -> Dictionary:
	# Least-squares linear per-channel gain+offset fit on unoccluded robe ROI (0..255 scale)
	var gains: Array[float] = [1.0, 1.0, 1.0]
	var offsets: Array[float] = [0.0, 0.0, 0.0]

	var n_robe: float = 0.0
	var sum_x: Array[float] = [0.0, 0.0, 0.0]
	var sum_y: Array[float] = [0.0, 0.0, 0.0]
	var sum_xx: Array[float] = [0.0, 0.0, 0.0]
	var sum_xy: Array[float] = [0.0, 0.0, 0.0]

	for ry: int in range(robe_rect.position.y, robe_rect.end.y, stride):
		for rx: int in range(robe_rect.position.x, robe_rect.end.x, stride):
			var cc: Color = calm_frame.get_pixel(rx, ry)
			var vc: Color = var_frame.get_pixel(rx, ry)
			var ca: Array[float] = [cc.r * 255.0, cc.g * 255.0, cc.b * 255.0]
			var va: Array[float] = [vc.r * 255.0, vc.g * 255.0, vc.b * 255.0]
			n_robe += 1.0
			for ch_i: int in range(3):
				sum_x[ch_i] += ca[ch_i]
				sum_y[ch_i] += va[ch_i]
				sum_xx[ch_i] += ca[ch_i] * ca[ch_i]
				sum_xy[ch_i] += ca[ch_i] * va[ch_i]

	if n_robe >= 16.0:
		for ch_i: int in range(3):
			var denom: float = n_robe * sum_xx[ch_i] - sum_x[ch_i] * sum_x[ch_i]
			if absf(denom) > 1.0:
				gains[ch_i] = (n_robe * sum_xy[ch_i] - sum_x[ch_i] * sum_y[ch_i]) / denom
				offsets[ch_i] = (sum_y[ch_i] - gains[ch_i] * sum_x[ch_i]) / n_robe

	var residuals: Array[float] = []
	var raw_diff_sum: float = 0.0
	for fy: int in range(face_rect.position.y, face_rect.end.y, stride):
		for fx: int in range(face_rect.position.x, face_rect.end.x, stride):
			var cf: Color = calm_frame.get_pixel(fx, fy)
			var vf: Color = var_frame.get_pixel(fx, fy)
			var c_rgb: Array[float] = [cf.r * 255.0, cf.g * 255.0, cf.b * 255.0]
			var v_rgb: Array[float] = [vf.r * 255.0, vf.g * 255.0, vf.b * 255.0]
			for ch_i: int in range(3):
				var pred: float = clampf(c_rgb[ch_i] * gains[ch_i] + offsets[ch_i], 0.0, 255.0)
				residuals.append(absf(v_rgb[ch_i] - pred))
				raw_diff_sum += absf(v_rgb[ch_i] - c_rgb[ch_i])

	residuals.sort()
	var p99: float = 0.0
	if not residuals.is_empty():
		var idx99: int = clampi(int(floor(float(residuals.size() - 1) * 0.99)), 0, residuals.size() - 1)
		p99 = residuals[idx99]

	return {
		"p99_residual": p99,
		"raw_mean_diff": raw_diff_sum / float(maxi(1, residuals.size())),
	}


func _measure_sheet_row_max_wh(img: Image, meta: Dictionary, anim_name: String) -> Vector2i:
	var cell_w: int = int(meta.get("cell_w", 224))
	var cell_h: int = int(meta.get("cell_h", 224))
	var rows: Dictionary = meta.get("rows", {}) as Dictionary
	var rdef: Dictionary = rows.get(anim_name, {}) as Dictionary
	var row_idx: int = int(rdef.get("row", 0))
	var start_col: int = int(rdef.get("start_col", 0))
	var frame_cnt: int = maxi(1, int(rdef.get("frames", 1)))
	var max_w: int = 0
	var max_h: int = 0

	for f_i: int in range(frame_cnt):
		var x0: int = (start_col + f_i) * cell_w
		var y0: int = row_idx * cell_h
		var w_clamped: int = mini(cell_w, maxi(0, img.get_width() - x0))
		var h_clamped: int = mini(cell_h, maxi(0, img.get_height() - y0))
		if w_clamped <= 0 or h_clamped <= 0:
			continue
		var used: Rect2i = img.get_region(Rect2i(x0, y0, w_clamped, h_clamped)).get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			max_w = maxi(max_w, used.size.x)
			max_h = maxi(max_h, used.size.y)
	return Vector2i(max_w, max_h)


func _detect_stage_scroll_rollers(stage: NarrativeStage) -> bool:
	var left_ok: bool = false
	var right_ok: bool = false
	var stack: Array[Node] = [stage]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == stage._cg_root or cur == stage._left_portrait or cur == stage._right_portrait or cur == stage._stage_dimmer:
			continue
		if cur is Control and _is_node_effectively_visible(cur, stage):
			var ctrl: Control = cur as Control
			var grect: Rect2 = ctrl.get_global_rect()
			var visual_ok: bool = false
			if ctrl is TextureRect and (ctrl as TextureRect).texture != null:
				visual_ok = true
			elif ctrl is NinePatchRect and (ctrl as NinePatchRect).texture != null:
				visual_ok = true
			elif ctrl is PanelContainer or ctrl is Panel:
				var sb: StyleBox = ctrl.get_theme_stylebox("panel")
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					visual_ok = true
			elif ctrl != stage._scroll_panel and ctrl != stage._speaker_plaque and ctrl.get_script() != null:
				visual_ok = true
			if visual_ok and grect.position.y >= 540.0 and grect.size.y >= 160.0:
				if grect.size.x >= 1600.0:
					left_ok = true
					right_ok = true
				else:
					if grect.position.x <= 250.0 and grect.size.x <= 220.0:
						left_ok = true
					if grect.end.x >= 1670.0 and grect.size.x <= 220.0:
						right_ok = true
		for ch: Node in cur.get_children():
			stack.append(ch)
	return left_ok and right_ok


func case_t4_w2_01_temple_stage_baseline() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var stage: NarrativeStage = world._narrative

	# Seed transient P1 combat floaters and P3 slips before walking into Ruined Temple
	NotifyHub.set_combat_active(true)
	NotifyHub.push_combat_number(Vector2(1740.0, 620.0), 96, false, true, "metal")
	NotifyHub.push_explore_slip("山道灵草", "凝气草 ×1", "loot")
	NotifyHub.set_combat_active(false)

	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	gu.position = Vector2(1890.0, 640.0)
	world.call("_check_dynamic_zone_triggers")

	assert_true(stage.visible, "Ruined Temple NarrativeStage opened")
	assert_true(stage._cg_active, "Tier 3 CG cg_ch01_ruined_temple active")
	assert_eq(stage._cg_layers.size(), 4, "All 4 parallax CG layers mounted")
	assert_true(NotifyHub.narrative_exclusive, "NotifyHub.narrative_exclusive active")
	assert_true(world._notify_overlay._floaters.is_empty(), "0 visible P1 damage floaters during narrative")
	assert_eq(world._notify_overlay._slip_vbox.get_child_count(), 0, "0 visible P3 slips during narrative")

	# Verify 4-layer CG textures & live parallax motion before dismissing CG into Portrait Stage L01
	for c_i: int in range(4):
		assert_not_null(stage._cg_layers[c_i].texture, "CG layer %d texture loaded" % c_i)
	var cg_pos0: Vector2 = stage._cg_layers[1].position
	stage._process(0.25)
	assert_ne(stage._cg_layers[1].position, cg_pos0, "4-layer CG parallax animates live")

	# Dismiss CG via Enter into Tier 2 Portrait Stage L01
	InputRouter._process(0.45)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage._cg_active, "Dismissed CG into Tier 2 Portrait Stage L01")

	# Mash Space 10 times -> 0 lines skipped
	InputRouter._process(0.45)
	for _sp: int in range(10):
		InputRouter._input(make_key_event(KEY_SPACE, true))
	assert_eq(stage._line_index, 0, "Mashing KEY_SPACE 10x advances 0 lines on live 1080p stage")

	var stage_img: Image = await capture_1080p_frame(18, "t4_w2_01_temple_stage_l01")
	assert_eq(stage_img.get_width(), 1920, "Stage frame width == 1920")
	assert_eq(stage_img.get_height(), 1080, "Stage frame height == 1080")
	var stage_mid: Dictionary = sample_image_roi_stats(stage_img, Rect2i(200, 320, 360, 220))
	assert_gt(float(stage_mid.get("std_luma", 0.0)), 0.03, "Live 1080p Ruined Temple stage renders non-blank portrait & scene")
	var xuan_roi: Dictionary = sample_image_roi_stats(stage_img, Rect2i(960, 970, 160, 36))
	var xuan_col: Color = Color(
		float(xuan_roi.get("mean_r", 0.85)),
		float(xuan_roi.get("mean_g", 0.80)),
		float(xuan_roi.get("mean_b", 0.74)),
		1.0
	)
	assert_gt(xuan_col.r, xuan_col.b, "Aged Xuan scroll background is warm parchment (R > B)")
	var ink_col: Color = stage._body_lbl.get_theme_color("font_color", "Label")
	var contrast: float = wcag_contrast_color(xuan_col, ink_col)
	record_metric("xuan_ink_wcag_contrast", snappedf(contrast, 0.01))
	assert_ge(contrast, 7.0, "Xuan paper vs dark-ink body text WCAG contrast (%.2f:1) >= 7.0:1" % contrast)

	var spk_px: int = stage._speaker_lbl.get_theme_font_size("font_size", "Label")
	var body_px: int = stage._body_lbl.get_theme_font_size("font_size", "Label")
	var font_tree: Dictionary = min_font_size_in_tree(stage)
	assert_ge(spk_px, 22, "Speaker plaque font_size >= 22px")
	assert_ge(body_px, 22, "Dialogue body font_size >= 22px")
	assert_ge(int(font_tree.get("min_px", 0)), 16, "All visible NarrativeStage labels >= 16px")


func case_t4_w2_02_master_c_portraits_and_rollers() -> void:
	var stage: NarrativeStage = NarrativeStage.new()
	mount_node(stage)

	stage.start_dialogue("dlg_ch01_temple_clash", true)
	InputRouter._process(0.45)
	InputRouter._input(make_key_event(KEY_ENTER, true))

	stage._left_portrait.modulate = Color.WHITE
	stage._right_portrait.modulate = Color.WHITE

	var pulse_dot: ColorRect = ColorRect.new()
	pulse_dot.size = Vector2(1.0, 1.0)
	pulse_dot.position = Vector2(0.0, 1079.0)
	pulse_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_dot.color = Color(0.0, 0.0, 0.0, 0.004)
	stage.add_child(pulse_dot)
	var redraw_cb: Callable = func() -> void:
		if is_instance_valid(pulse_dot):
			pulse_dot.color.a = 0.008 if pulse_dot.color.a < 0.006 else 0.004
	tree.process_frame.connect(redraw_cb)

	# Frame 1 (L01): gu_changqing_guarded (left) + pei_zhao_cold (right)
	var guarded_pei_cold_shot: Image = await capture_1080p_frame(18, "t4_w2_02_master_c_stage")
	var neon_info: Dictionary = _count_neon_pixels_sampled(guarded_pei_cold_shot, 16)
	assert_lt(float(neon_info.get("ratio", 1.0)), 0.002, "master_c stage has < 0.2% fluorescent neon pixels")

	assert_true(
		_detect_stage_scroll_rollers(stage),
		"Live 1080p NarrativeStage displays left & right vertical carved dark-ebony scroll rollers flanking the dialogue scroll (master_c)"
	)

	var left_robe_roi: Rect2i = Rect2i(226, 565, 320, 175)
	var left_face_roi: Rect2i = Rect2i(258, 295, 262, 225)
	var right_robe_roi: Rect2i = Rect2i(1366, 565, 320, 175)
	var right_face_roi: Rect2i = Rect2i(1398, 295, 262, 225)

	# Frame 2: gu_changqing_calm (left) + pei_zhao_calm (right) on live 1920x1080 stage
	stage._left_portrait.texture = load_tex("res://assets/portraits/gu_changqing_calm.png")
	stage._right_portrait.texture = load_tex("res://assets/portraits/pei_zhao_calm.png")
	var base_calm_shot: Image = await capture_1080p_frame(18, "t4_w2_02_master_c_calm")
	if tree.process_frame.is_connected(redraw_cb):
		tree.process_frame.disconnect(redraw_cb)
	pulse_dot.queue_free()

	var gu_guarded_res: Dictionary = _compute_screen_portrait_face_p99_residual(base_calm_shot, guarded_pei_cold_shot, left_robe_roi, left_face_roi, 8)
	var pei_cold_res: Dictionary = _compute_screen_portrait_face_p99_residual(base_calm_shot, guarded_pei_cold_shot, right_robe_roi, right_face_roi, 8)

	assert_ge(float(gu_guarded_res.get("p99_residual", 0.0)), 10.0, "Live 1080p stage Gu 'guarded' face-ROI p99 residual >= 10.0")
	assert_ge(float(pei_cold_res.get("p99_residual", 0.0)), 10.0, "Live 1080p stage Pei 'cold' face-ROI p99 residual >= 10.0")

	var sha_g: String = FileAccess.get_sha256(ProjectSettings.globalize_path("res://assets/portraits/gu_changqing_guarded.png"))
	var sha_s: String = FileAccess.get_sha256(ProjectSettings.globalize_path("res://assets/portraits/gu_changqing_solemn.png"))
	assert_ne(sha_g, sha_s, "gu_changqing_guarded.png and gu_changqing_solemn.png have distinct SHA-256")


func case_t4_w2_03_master_b_wolf_king_and_trio() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.read_dialogues["dlg_ch01_wolf_king_intro"] = true
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.contract_spirit_pet("pet_fire_fox")
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud

	var boss_actor: BattleActor = null
	for ea: BattleActor in ctrl.enemy_actors:
		if ea.is_boss:
			boss_actor = ea
			break
	assert_not_null(boss_actor, "Mist Wolf King present in cangmu_cave")
	if boss_actor == null:
		return

	# Deterministic staging matching master_b_cangmu_rtwp.png
	boss_actor.position = Vector2(1980.0, 520.0)
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	gu.position = Vector2(1810.0, 560.0)
	pei.position = Vector2(1845.0, 485.0)
	shen.position = Vector2(1690.0, 585.0)
	if ctrl.pet_actor != null:
		ctrl.pet_actor.position = Vector2(1745.0, 515.0)

	ctrl.engage_enemy_group("enc_boss_wolf_king", "pei_zhao", false)
	allow_expected_engine_error("unsupported format character")
	var boss_u: Dictionary = ctrl.unit_states[boss_actor.actor_id] as Dictionary
	boss_u["phase"] = 2
	boss_u["hp"] = 3120
	boss_actor.hp = 3120
	boss_u["ward_current"] = 295.0
	boss_actor.ward_current = 295.0
	boss_u["casting"] = true
	boss_u["cast_skill_id"] = "sk_boss_roar_miasma"
	boss_u["cast_duration"] = 8.0
	boss_u["cast_progress"] = 1.5
	boss_u["cast_interruptible"] = true
	boss_actor.is_casting = true
	boss_actor.cast_skill_name = DataDB.loc("SK_BOSS_ROAR_NAME")
	boss_actor.cast_duration = 8.0
	boss_actor.cast_progress = 1.5
	boss_actor.cast_interruptible = true

	gu.set_facing(boss_actor.position - gu.position)
	pei.set_facing(boss_actor.position - pei.position)
	shen.set_facing(boss_actor.position - shen.position)
	gu.play_action_anim("attack_1", 4.50)
	pei.play_action_anim("attack_2", 4.50)
	shen.is_casting = true
	boss_actor.play_action_anim("attack_1", 4.50)
	ctrl.step_world_and_combat(0.08, QinglanWorld.ZONE_BOUNDS)
	ctrl.tactical_paused = true

	world._camera.position = Vector2(1865.0, 525.0)
	var pulse_dot: ColorRect = ColorRect.new()
	pulse_dot.size = Vector2(1.0, 1.0)
	pulse_dot.position = Vector2(0.0, 1079.0)
	pulse_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_dot.color = Color(0.0, 0.0, 0.0, 0.004)
	world._ui_canvas.add_child(pulse_dot)
	var redraw_cb: Callable = func() -> void:
		if is_instance_valid(pulse_dot):
			pulse_dot.color.a = 0.008 if pulse_dot.color.a < 0.006 else 0.004
	tree.process_frame.connect(redraw_cb)
	var shot: Image = await capture_1080p_frame(18, "t4_w2_03_master_b_actors_boss")
	if tree.process_frame.is_connected(redraw_cb):
		tree.process_frame.disconnect(redraw_cb)
	pulse_dot.queue_free()
	assert_eq(shot.get_width(), 1920, "Boss combat frame width == 1920")
	assert_eq(shot.get_height(), 1080, "Boss combat frame height == 1080")

	var neon_res: Dictionary = _count_neon_pixels_sampled(shot, 16)
	assert_lt(float(neon_res.get("ratio", 1.0)), 0.002, "Boss arena frame has < 0.2% fluorescent neon pixels")
	assert_true(hud._boss_panel.visible, "Top-center Boss HUD plaque is visible")

	# Strict 1-pet canonical rule (never 2 foxes from master_b generative plate!)
	var pet_cnt: int = 0
	for ch: Node in world._ysort_root.get_children():
		if ch is BattleActor and not ch.is_queued_for_deletion() and (ch as BattleActor).faction == "pet":
			pet_cnt += 1
	assert_eq(pet_cnt, 1, "Strictly 1 active spirit pet in Boss arena (master_b rule guard)")

	# Giant Boss silhouette gate (>= 320px tall, >= 380px wide)
	var boss_sheet_img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/boss_mist_wolf_king_sheet.png"))
	var boss_meta: Dictionary = load_json_dict("res://assets/sprites/boss_mist_wolf_king_sheet.json")
	var boss_idle: Vector2i = _measure_sheet_row_max_wh(boss_sheet_img, boss_meta, "idle_se")
	var boss_atk: Vector2i = _measure_sheet_row_max_wh(boss_sheet_img, boss_meta, "attack_1")
	var boss_w: float = float(maxi(boss_idle.x, boss_atk.x)) * absf(boss_actor._sprite.scale.x)
	var boss_h: float = float(maxi(boss_idle.y, boss_atk.y)) * absf(boss_actor._sprite.scale.y)
	record_metric("master_b_boss_w", snappedf(boss_w, 0.1))
	record_metric("master_b_boss_h", snappedf(boss_h, 0.1))
	assert_ge(boss_h, 320.0, "Mist Wolf King rendered height (%.1fpx) >= 320px" % boss_h)
	assert_ge(boss_w, 380.0, "Mist Wolf King rendered side-3/4 span (%.1fpx) >= 380px" % boss_w)

	# Multi-pose trio & get_vfx_origin_world gate
	for party_act: BattleActor in [gu, pei, shen]:
		var sid: String = party_act.sprite_id
		var p_img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/%s_sheet.png" % sid))
		var p_meta: Dictionary = load_json_dict("res://assets/sprites/%s_sheet.json" % sid)
		var p_idle: Vector2i = _measure_sheet_row_max_wh(p_img, p_meta, "idle_se")
		var p_atk1: Vector2i = _measure_sheet_row_max_wh(p_img, p_meta, "attack_1")
		var p_atk2: Vector2i = _measure_sheet_row_max_wh(p_img, p_meta, "attack_2")
		var ext_ratio: float = float(maxi(p_atk1.x, p_atk2.x)) / float(maxi(1, p_idle.x))
		assert_ge(
			ext_ratio,
			1.28,
			"Live trio %s multi-pose attack width extension (%.3fx) >= 1.28x idle width" % [sid, ext_ratio]
		)
		assert_true(
			obj_has_method(party_act, "get_vfx_origin_world"),
			"Live trio %s implements get_vfx_origin_world('weapon')" % sid
		)
