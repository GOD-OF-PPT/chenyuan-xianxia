extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 1
# @e2e_features: F4, F6, F7
## Worker 2 Tier 1 Visual (1920x1080 Xvfb OpenGL3) & Actor/Narrative Happy-Path Suite for F4, F6, and F7.


func register_cases() -> void:
	add_case("T1-F04-06", 1, "F4", "polish_r1", "Top-center CombatHud formation plaque above action bar (master_b)", "case_t1_f04_06_hud_formation_plaque")
	add_case("T1-F06-02", 1, "F6", "polish_r2", "Giant side-3/4 Mist Wolf King world silhouette (>=320px tall, >=380px wide)", "case_t1_f06_02_giant_wolf_king_silhouette")
	add_case("T1-F06-03", 1, "F6", "polish_r2", "BattleActor.get_vfx_origin_world & per-pose *_sheet.json VFX anchors", "case_t1_f06_03_vfx_origin_world_anchors")
	add_case("T1-F06-04", 1, "F6", "baseline", "8-direction WASD facing_dir NE/SE row selection, flip_h & Tactical Pause frame lock", "case_t1_f06_04_eight_dir_and_pause_lock")
	add_case("T1-F06-05", 1, "F6", "baseline", "Y-Sort FeetOrigin offset and non-floating ground contact pixels", "case_t1_f06_05_ysort_feet_origin")
	add_case("T1-F07-01", 1, "F7", "baseline", "Tier 1 overhead Xuan world bark non-blocking input & ui_delta decay", "case_t1_f07_01_world_bark_non_blocking")
	add_case("T1-F07-02", 1, "F7", "baseline", "Tier 2 Portrait Stage speaker/listener modulation, recruitment & replay Ctrl hint", "case_t1_f07_02_portrait_stage_and_replay")
	add_case("T1-F07-03", 1, "F7", "baseline", "Tier 3 4-layer parallax CG unlock, reduced_motion freeze & Enter transition", "case_t1_f07_03_four_layer_cg_parallax")
	add_case("T1-F07-04", 1, "F7", "baseline", "Night Talk Bond Tier 2 unlock & Marrow Choice Cinnabar Karma Seal branches", "case_t1_f07_04_bonds_and_karma_seals")
	add_case("T1-F07-06", 1, "F7", "polish_r2", "NarrativeStage carved dark-ebony vertical scroll rollers & >=22px typography (master_c)", "case_t1_f07_06_ebony_scroll_rollers")


func _measure_sheet_row_bbox(img: Image, meta: Dictionary, anim_name: String) -> Dictionary:
	var cell_w: int = int(meta.get("cell_w", 224))
	var cell_h: int = int(meta.get("cell_h", 224))
	var rows: Dictionary = meta.get("rows", {}) as Dictionary
	var rdef: Dictionary = rows.get(anim_name, {}) as Dictionary
	var row_idx: int = int(rdef.get("row", 0))
	var start_col: int = int(rdef.get("start_col", 0))
	var frame_cnt: int = maxi(1, int(rdef.get("frames", 1)))

	var max_w: int = 0
	var max_h: int = 0
	var min_max_y: int = cell_h
	var max_max_y: int = 0

	for f_i: int in range(frame_cnt):
		var col_idx: int = start_col + f_i
		var x0: int = col_idx * cell_w
		var y0: int = row_idx * cell_h
		var w_clamped: int = mini(cell_w, maxi(0, img.get_width() - x0))
		var h_clamped: int = mini(cell_h, maxi(0, img.get_height() - y0))
		if w_clamped <= 0 or h_clamped <= 0:
			continue
		var sub_img: Image = img.get_region(Rect2i(x0, y0, w_clamped, h_clamped))
		var used: Rect2i = sub_img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			max_w = maxi(max_w, used.size.x)
			max_h = maxi(max_h, used.size.y)
			var contact_y: int = used.position.y + used.size.y - 1
			min_max_y = mini(min_max_y, contact_y)
			max_max_y = maxi(max_max_y, contact_y)

	return {
		"max_w": max_w,
		"max_h": max_h,
		"min_max_y": min_max_y,
		"max_max_y": max_max_y,
	}


func _json_has_anchor_metadata(meta: Dictionary) -> bool:
	for k_var: Variant in meta.keys():
		var k: String = str(k_var).to_lower()
		if k.contains("anchor") or k.contains("origin") or k.contains("socket"):
			return true
	var rows: Dictionary = meta.get("rows", {}) as Dictionary
	for r_var: Variant in rows.values():
		if r_var is Dictionary:
			var rdict: Dictionary = r_var as Dictionary
			for rk_var: Variant in rdict.keys():
				var rk: String = str(rk_var).to_lower()
				if rk.contains("anchor") or rk.contains("origin") or rk.contains("socket"):
					return true
	return false


func _find_narrative_scroll_rollers(stage: NarrativeStage) -> Dictionary:
	var left_roller: bool = false
	var right_roller: bool = false
	var frame_tex_found: bool = false

	var da: DirAccess = DirAccess.open("res://assets/ui/frames")
	if da != null:
		da.list_dir_begin()
		var fn: String = da.get_next()
		while fn != "":
			var low: String = fn.to_lower()
			if not da.current_is_dir() and (low.contains("roller") or low.contains("scroll") or low.contains("narrative")):
				frame_tex_found = true
			fn = da.get_next()
		da.list_dir_end()

	var stack: Array[Node] = [stage]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == stage._cg_root or cur == stage._left_portrait or cur == stage._right_portrait or cur == stage._stage_dimmer:
			continue
		if cur is Control and _is_node_effectively_visible(cur, stage):
			var ctrl: Control = cur as Control
			var grect: Rect2 = ctrl.get_global_rect()
			var has_visual: bool = false
			if ctrl is TextureRect and (ctrl as TextureRect).texture != null:
				has_visual = true
			elif ctrl is NinePatchRect and (ctrl as NinePatchRect).texture != null:
				has_visual = true
			elif ctrl is PanelContainer or ctrl is Panel:
				var sb: StyleBox = ctrl.get_theme_stylebox("panel")
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					has_visual = true
			elif ctrl != stage._scroll_panel and ctrl != stage._speaker_plaque and ctrl.get_script() != null:
				has_visual = true

			if has_visual and grect.position.y >= 540.0 and grect.size.y >= 160.0:
				if grect.size.x >= 1600.0:
					left_roller = true
					right_roller = true
				else:
					if grect.position.x <= 250.0 and grect.size.x <= 220.0:
						left_roller = true
					if grect.end.x >= 1670.0 and grect.size.x <= 220.0:
						right_roller = true
		for ch: Node in cur.get_children():
			stack.append(ch)

	return {
		"left_roller": left_roller,
		"right_roller": right_roller,
		"frame_tex_found": frame_tex_found,
	}


func case_t1_f04_06_hud_formation_plaque() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(1)
	var hud: CombatHud = world._hud
	var ctrl: RtwpCombatController = world._combat_ctrl
	hud.refresh_static_bindings()

	var bottom_cluster: Control = hud._bottom_cluster
	assert_not_null(bottom_cluster, "CombatHud._bottom_cluster exists")

	var z_tile: Control = null
	var z_sw: Dictionary = as_dict(hud._slot_widgets.get("Z", {}))
	if z_sw.get("tile", null) is Control:
		z_tile = z_sw["tile"] as Control

	var found_dizai_plaque: Control = null
	for lbl: Label in collect_visible_labels(bottom_cluster):
		if hud._quick_drawer != null and (lbl == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(lbl)):
			continue
		if hud._pet_bar != null and (lbl == hud._pet_bar or hud._pet_bar.is_ancestor_of(lbl)):
			continue
		if z_tile != null and (lbl == z_tile or z_tile.is_ancestor_of(lbl)):
			continue
		if lbl.text.contains("地载阵"):
			found_dizai_plaque = lbl
			break
	if found_dizai_plaque == null:
		for btn: Button in collect_visible_buttons(bottom_cluster):
			if hud._quick_drawer != null and (btn == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(btn)):
				continue
			if hud._pet_bar != null and (btn == hud._pet_bar or hud._pet_bar.is_ancestor_of(btn)):
				continue
			if z_tile != null and (btn == z_tile or z_tile.is_ancestor_of(btn)):
				continue
			if btn.text.contains("地载阵"):
				found_dizai_plaque = btn
				break

	assert_not_null(
		found_dizai_plaque,
		"CombatHud._bottom_cluster displays a visible top-center formation plaque ('地载阵') above skill slots (master_b)"
	)
	if found_dizai_plaque != null:
		ctrl.try_switch_formation("tianfu")
		hud.refresh_static_bindings()
		hud._process(0.016)
		var updated_txt: String = ""
		if is_instance_valid(found_dizai_plaque):
			if found_dizai_plaque is Label:
				updated_txt = (found_dizai_plaque as Label).text
			elif found_dizai_plaque is Button:
				updated_txt = (found_dizai_plaque as Button).text
		if not updated_txt.contains("天覆阵"):
			for lbl2: Label in collect_visible_labels(bottom_cluster):
				if hud._quick_drawer != null and (lbl2 == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(lbl2)):
					continue
				if hud._pet_bar != null and (lbl2 == hud._pet_bar or hud._pet_bar.is_ancestor_of(lbl2)):
					continue
				if z_tile != null and (lbl2 == z_tile or z_tile.is_ancestor_of(lbl2)):
					continue
				if lbl2.text.contains("天覆阵"):
					updated_txt = lbl2.text
					break
		if not updated_txt.contains("天覆阵"):
			for btn2: Button in collect_visible_buttons(bottom_cluster):
				if hud._quick_drawer != null and (btn2 == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(btn2)):
					continue
				if hud._pet_bar != null and (btn2 == hud._pet_bar or hud._pet_bar.is_ancestor_of(btn2)):
					continue
				if z_tile != null and (btn2 == z_tile or z_tile.is_ancestor_of(btn2)):
					continue
				if btn2.text.contains("天覆阵"):
					updated_txt = btn2.text
					break
		assert_str_contains(
			updated_txt,
			"天覆阵",
			"HUD formation plaque dynamically updates to '天覆阵' when formation changes"
		)


func case_t1_f06_02_giant_wolf_king_silhouette() -> void:
	var png_abs: String = ProjectSettings.globalize_path("res://assets/sprites/boss_mist_wolf_king_sheet.png")
	var sheet_img: Image = Image.load_from_file(png_abs)
	var meta: Dictionary = load_json_dict("res://assets/sprites/boss_mist_wolf_king_sheet.json")
	assert_not_null(sheet_img, "boss_mist_wolf_king_sheet.png loaded")
	assert_false(meta.is_empty(), "boss_mist_wolf_king_sheet.json loaded")

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	var ctrl: RtwpCombatController = world._combat_ctrl
	var boss_actor: BattleActor = null
	for ea: BattleActor in ctrl.enemy_actors:
		if ea.is_boss:
			boss_actor = ea
			break
	assert_not_null(boss_actor, "Mist Wolf King spawned in cangmu_cave arena")
	if boss_actor == null or sheet_img == null:
		return

	world._camera.position = boss_actor.position + Vector2(-120.0, -40.0)
	var redraw_cb: Callable = func() -> void:
		if is_instance_valid(boss_actor):
			boss_actor.queue_redraw()
	tree.process_frame.connect(redraw_cb)
	var frame_img: Image = await capture_1080p_frame(18, "t1_f06_02_wolf_king")
	if tree.process_frame.is_connected(redraw_cb):
		tree.process_frame.disconnect(redraw_cb)
	assert_eq(frame_img.get_width(), 1920, "Captured 1920px viewport width")
	assert_eq(frame_img.get_height(), 1080, "Captured 1080px viewport height")

	var scale_x: float = absf(boss_actor._sprite.scale.x)
	var scale_y: float = absf(boss_actor._sprite.scale.y)
	var idle_box: Dictionary = _measure_sheet_row_bbox(sheet_img, meta, "idle_se")
	var atk_box: Dictionary = _measure_sheet_row_bbox(sheet_img, meta, "attack_1")

	var rendered_h: float = float(maxi(int(idle_box.get("max_h", 0)), int(atk_box.get("max_h", 0)))) * scale_y
	var rendered_w: float = float(maxi(int(idle_box.get("max_w", 0)), int(atk_box.get("max_w", 0)))) * scale_x
	record_metric("wolf_king_rendered_w", snappedf(rendered_w, 0.1))
	record_metric("wolf_king_rendered_h", snappedf(rendered_h, 0.1))

	assert_ge(
		rendered_h,
		320.0,
		"Rendered Mist Wolf King height (%.1fpx) >= 320px giant beast scale (master_b)" % rendered_h
	)
	assert_ge(
		rendered_w,
		380.0,
		"Rendered Mist Wolf King side-3/4 horizontal span (%.1fpx) >= 380px commanding silhouette (master_b)" % rendered_w
	)


func case_t1_f06_03_vfx_origin_world_anchors() -> void:
	for sid: String in ["gu_changqing", "shen_qinghe", "pei_zhao"]:
		var meta: Dictionary = load_json_dict("res://assets/sprites/%s_sheet.json" % sid)
		assert_true(
			_json_has_anchor_metadata(meta),
			"%s_sheet.json defines per-pose VFX origin/anchor metadata" % sid
		)

		var actor: BattleActor = BattleActor.new()
		actor.position = Vector2(600.0, 500.0)
		mount_node(actor)
		actor.setup_actor(sid, "party", sid, sid, 1.0)

		var has_fn: bool = obj_has_method(actor, "get_vfx_origin_world")
		assert_true(has_fn, "BattleActor (%s) implements get_vfx_origin_world(slot)" % sid)
		if not has_fn:
			continue

		actor.set_facing(Vector2(1.0, 0.4))
		actor.step_visuals(0.05, 0.05, false)
		var pt_right_v: Variant = obj_call(actor, "get_vfx_origin_world", ["weapon"])
		assert_true(pt_right_v is Vector2, "get_vfx_origin_world returns Vector2")
		if not (pt_right_v is Vector2):
			continue
		var pt_right: Vector2 = pt_right_v as Vector2
		assert_gt(pt_right.x, actor.position.x, "%s weapon VFX origin lies +X of FeetOrigin when facing right" % sid)
		assert_lt(pt_right.y, actor.position.y - 16.0, "%s weapon VFX origin lies above FeetOrigin" % sid)

		actor.play_action_anim("attack_1", 0.42)
		actor.step_visuals(0.18, 0.18, false)
		var pt_atk: Vector2 = obj_call(actor, "get_vfx_origin_world", ["weapon"]) as Vector2
		assert_ge(
			pt_atk.distance_to(pt_right),
			2.0,
			"%s VFX origin shifts across idle vs attack_1 per-pose anchors" % sid
		)

		actor.set_facing(Vector2(-1.0, 0.4))
		actor.step_visuals(0.02, 0.02, false)
		var pt_left: Vector2 = obj_call(actor, "get_vfx_origin_world", ["weapon"]) as Vector2
		assert_true(actor._sprite.flip_h, "%s _sprite.flip_h is true when facing -X" % sid)
		assert_lt(pt_left.x, actor.position.x, "%s weapon VFX origin mirrors to -X when flip_h is true" % sid)


func case_t1_f06_04_eight_dir_and_pause_lock() -> void:
	var actor: BattleActor = BattleActor.new()
	actor.position = Vector2(400.0, 400.0)
	mount_node(actor)
	actor.setup_actor("gu_changqing", "party", "顾长青", "gu_changqing", 1.0)
	var cell_h: int = actor._cell_h

	var dirs: Array[Dictionary] = [
		{"name": "SE", "vec": Vector2(1.0, 1.0), "expect_back": false, "expect_flip": false},
		{"name": "S", "vec": Vector2(0.0, 1.0), "expect_back": false, "expect_flip": false},
		{"name": "SW", "vec": Vector2(-1.0, 1.0), "expect_back": false, "expect_flip": true},
		{"name": "W", "vec": Vector2(-1.0, 0.0), "expect_back": false, "expect_flip": true},
		{"name": "NW", "vec": Vector2(-1.0, -1.0), "expect_back": true, "expect_flip": true},
		{"name": "N", "vec": Vector2(0.0, -1.0), "expect_back": true, "expect_flip": false},
		{"name": "NE", "vec": Vector2(1.0, -1.0), "expect_back": true, "expect_flip": false},
		{"name": "E", "vec": Vector2(1.0, 0.0), "expect_back": false, "expect_flip": false},
	]

	for d: Dictionary in dirs:
		var v: Vector2 = d["vec"] as Vector2
		var dname: String = str(d["name"])
		var exp_back: bool = bool(d["expect_back"])
		var exp_flip: bool = bool(d["expect_flip"])
		actor.set_facing(v)
		actor.step_visuals(0.02, 0.02, true)
		var row_now: int = int(round(actor._sprite.region_rect.position.y / float(cell_h)))
		var expected_row: int = 3 if exp_back else 2
		assert_eq(row_now, expected_row, "Direction %s selects run_%s row %d" % [dname, "ne" if exp_back else "se", expected_row])
		assert_eq(actor._sprite.flip_h, exp_flip, "Direction %s sets flip_h == %s" % [dname, str(exp_flip)])

	# Verify combat_delta > 0 advances region_rect.x whereas combat_delta == 0 locks frame 100%
	actor.set_facing(Vector2(1.0, 0.5))
	actor._anim_timer = 0.0
	actor.step_visuals(0.01, 0.01, true)
	var r0: Rect2 = actor._sprite.region_rect
	actor.step_visuals(0.22, 0.22, true)
	var r_moving: Rect2 = actor._sprite.region_rect
	assert_ne(r_moving.position.x, r0.position.x, "region_rect advances when combat_delta > 0")

	for _p: int in range(10):
		actor.step_visuals(0.0, 0.25, true)
	assert_eq(actor._sprite.region_rect, r_moving, "region_rect stays 100% locked when combat_delta == 0.0")


func case_t1_f06_05_ysort_feet_origin() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	assert_true(world._ysort_root.y_sort_enabled, "QinglanWorld._ysort_root has y_sort_enabled == true")

	for sid: String in ["gu_changqing", "shen_qinghe", "pei_zhao", "boss_mist_wolf_king"]:
		var actor: BattleActor = BattleActor.new()
		mount_node(actor)
		actor.setup_actor(sid, "party", sid, sid, 1.0)
		assert_false(actor._sprite.centered, "%s _sprite.centered == false" % sid)
		assert_approx(actor._sprite.offset.x, -float(actor._cell_w) * 0.5, 0.01, "%s _sprite.offset.x == -cell_w/2" % sid)
		assert_approx(actor._sprite.offset.y, -float(actor._foot_y), 0.01, "%s _sprite.offset.y == -foot_y" % sid)

		var png_abs: String = ProjectSettings.globalize_path("res://assets/sprites/%s_sheet.png" % sid)
		var img: Image = Image.load_from_file(png_abs)
		var meta: Dictionary = load_json_dict("res://assets/sprites/%s_sheet.json" % sid)
		assert_not_null(img, "Loaded %s_sheet.png" % sid)
		if img == null:
			continue
		for rname: String in ["idle_se", "run_se"]:
			var box: Dictionary = _measure_sheet_row_bbox(img, meta, rname)
			var min_contact_y: int = int(box.get("min_max_y", 0))
			var max_contact_y: int = int(box.get("max_max_y", 0))
			assert_ge(
				min_contact_y,
				actor._foot_y - 10,
				"%s %s lowest foot/shadow pixel (%d) >= foot_y - 10 (%d)" % [sid, rname, min_contact_y, actor._foot_y - 10]
			)
			assert_le(
				max_contact_y,
				actor._cell_h - 1,
				"%s %s lowest foot/shadow pixel (%d) <= cell_h - 1 (%d)" % [sid, rname, max_contact_y, actor._cell_h - 1]
			)


func case_t1_f07_01_world_bark_non_blocking() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor

	gu.show_world_bark("测试轻云气泡", 3.5)
	assert_true(gu.has_active_bark(), "World bark is active immediately after show_world_bark()")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Tier 1 bark keeps MODE_WORLD_COMBAT non-blocking")
	assert_false(NotifyHub.narrative_exclusive, "Tier 1 bark does not enter narrative_exclusive")

	var start_pos: Vector2 = gu.position
	ctrl.command_move_selected_to(start_pos + Vector2(120.0, 0.0))
	ctrl.step_world_and_combat(0.25, QinglanWorld.ZONE_BOUNDS)
	assert_gt(gu.position.distance_to(start_pos), 15.0, "Player moves freely while Tier 1 world bark is active")

	# Bark decays via ui_delta even when combat_delta == 0.0
	gu.step_visuals(0.0, 3.60, false)
	assert_false(gu.has_active_bark(), "Tier 1 world bark expires cleanly after 3.6s of ui_delta")


func case_t1_f07_02_portrait_stage_and_replay() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	var stage: NarrativeStage = world._narrative

	stage.start_dialogue("dlg_ch01_meet_shen")
	assert_true(stage.visible, "NarrativeStage opens for dlg_ch01_meet_shen")
	assert_true(NotifyHub.narrative_exclusive, "NotifyHub.narrative_exclusive is true during Tier 2 dialogue")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_DIALOGUE, "InputRouter enters MODE_DIALOGUE")
	assert_str_not_contains(stage._hint_lbl.text, "Ctrl", "Unread first-play dialogue hides Ctrl fast-forward hint")

	# L01: speaker is CHAR_SHEN_NAME (right portrait), Gu is listener (left portrait)
	assert_eq(stage._right_portrait.modulate, Color.WHITE, "Active speaker (Shen right) modulate == Color.WHITE")
	assert_approx(stage._left_portrait.modulate.r, 0.62, 0.02, "Listener (Gu left) dimmed to ~0.62")

	# Advance all 5 lines via Enter after 0.45s anti-mash lock
	InputRouter._process(0.45)
	for step_i: int in range(5):
		InputRouter._input(make_key_event(KEY_ENTER, true))
		if step_i == 0 and stage.visible:
			# L02: speaker switches to CHAR_GU_NAME (left portrait)
			assert_eq(stage._left_portrait.modulate, Color.WHITE, "L02 speaker (Gu left) highlighted Color.WHITE")
			assert_approx(stage._right_portrait.modulate.r, 0.62, 0.02, "L02 listener (Shen right) dimmed")

	assert_false(stage.visible, "NarrativeStage closes after final line L05")
	assert_true(
		bool((CampaignState.party_members.get("shen_qinghe", {}) as Dictionary).get("recruited", false)),
		"on_finish_actions recruited shen_qinghe"
	)
	assert_true(CampaignState.read_dialogues.has("dlg_ch01_meet_shen"), "read_dialogues marks dlg_ch01_meet_shen")

	# Replay dialogue -> Ctrl fast-forward hint appears ONLY now
	stage.start_dialogue("dlg_ch01_meet_shen", true)
	assert_true(stage._is_already_read, "_is_already_read is true on replay")
	assert_str_contains(stage._hint_lbl.text, "Ctrl", "Already-read replay displays Ctrl fast-forward hint")


func case_t1_f07_03_four_layer_cg_parallax() -> void:
	var stage: NarrativeStage = NarrativeStage.new()
	mount_node(stage)

	assert_false(CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple"), "Temple CG initially locked")
	SaveManager.reduced_motion = false
	stage.start_dialogue("dlg_ch01_temple_clash")

	assert_true(stage._cg_active, "dlg_ch01_temple_clash starts in Tier 3 CG mode")
	assert_true(stage._cg_root.visible, "_cg_root is visible")
	assert_eq(stage._cg_layers.size(), 4, "Tier 3 CG mounts 4 parallax TextureRect layers")
	for l_idx: int in range(4):
		assert_not_null(stage._cg_layers[l_idx].texture, "CG layer %d has loaded Texture2D" % l_idx)
	assert_true(CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple"), "cg_ch01_ruined_temple unlocked in gallery")

	var pos_before: Vector2 = stage._cg_layers[1].position
	stage._process(0.25)
	var pos_after_motion: Vector2 = stage._cg_layers[1].position
	assert_ne(pos_after_motion, pos_before, "Parallax layer 1 shifts position when reduced_motion == false")

	SaveManager.reduced_motion = true
	var pos_frozen: Vector2 = stage._cg_layers[1].position
	stage._process(0.40)
	assert_eq(stage._cg_layers[1].position, pos_frozen, "Parallax layer 1 stays stationary when reduced_motion == true")
	SaveManager.reduced_motion = false

	InputRouter._process(0.45)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage._cg_active, "Enter dismisses CG step into Tier 2 dialogue line L01")
	assert_false(stage._cg_root.visible, "_cg_root hidden on L01")
	assert_true(stage._scroll_panel.visible, "_scroll_panel visible on L01")
	assert_eq(stage._line_index, 0, "Transitioned cleanly to line index 0")


func case_t1_f07_04_bonds_and_karma_seals() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	var stage: NarrativeStage = world._narrative

	# 1. Night Talk 1 promotes Shen Qinghe bond 1 -> 2 and unlocks ult_qinglian_sword
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), 1, "Shen bond starts at Tier 1")
	stage.start_dialogue("dlg_night_talk_1")
	InputRouter._process(0.45)
	for _i: int in range(4):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 0)), 2, "dlg_night_talk_1 promotes Shen bond to Tier 2")
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "Bond Tier 2 unlocks ult_qinglian_sword")

	# 2. Branch A: CHOICE_MARROW_ABSORB -> seal_absorb_marrow + lone_peak + qi_refining_2 (+8% dmg bonus) -> epilogue
	stage.start_dialogue("dlg_ch01_marrow_choice")
	InputRouter._process(0.45)
	for _j: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_true(stage._choices_box.visible, "dlg_ch01_marrow_choice presents choices")
	InputRouter._process(0.45)
	var btns_a: Array[Button] = collect_visible_buttons(stage._choices_box)
	assert_eq(btns_a.size(), 2, "Marrow choice offers 2 Dao-heart choices")
	btns_a[0].pressed.emit()

	assert_true(CampaignState.ink_seals.has("seal_absorb_marrow"), "Choice A stamps seal_absorb_marrow")
	assert_eq(int(CampaignState.dao_heart_weights.get("lone_peak", 0)), 1, "Choice A increments lone_peak == 1")
	var gu_m_a: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	assert_eq(str(gu_m_a.get("realm_id", "")), "qi_refining_2", "Choice A promotes Gu to qi_refining_2")
	assert_eq(stage._active_dialogue_id, "dlg_ch01_epilogue", "Choice A chains dlg_ch01_epilogue")
	InputRouter._process(0.45)
	for _e: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_true(bool(CampaignState.world_flags.get("ch01_completed", false)), "Epilogue sets ch01_completed == true")
	var gu_absorb_phys: float = float((gu_m_a.get("sheet", {}) as Dictionary).get("phys_power", 0.0))

	# 3. Branch B on clean sandbox state: CHOICE_MARROW_SCATTER -> seal_scatter_rain + mortal_mercy + +800 rep + pill
	world._modals.close_modal()
	reset_sandbox_campaign("cultivation")
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	world.load_zone("cangmu_cave", "stele_wolf_altar", false)

	stage.start_dialogue("dlg_ch01_marrow_choice", true)
	InputRouter._process(0.45)
	for _k: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	InputRouter._process(0.45)
	var btns_b: Array[Button] = collect_visible_buttons(stage._choices_box)
	btns_b[1].pressed.emit()

	assert_true(CampaignState.ink_seals.has("seal_scatter_rain"), "Choice B stamps seal_scatter_rain")
	assert_eq(int(CampaignState.dao_heart_weights.get("mortal_mercy", 0)), 1, "Choice B increments mortal_mercy == 1")
	assert_ge(int(CampaignState.faction_reputation.get("jishi_pharmacy", 0)), 800, "Choice B grants +800 jishi_pharmacy rep")
	assert_ge(CampaignState.get_item_count("item_ningqi_vein_pill"), 1, "Choice B grants item_ningqi_vein_pill")
	var gu_scatter_phys: float = float(((CampaignState.party_members["gu_changqing"] as Dictionary).get("sheet", {}) as Dictionary).get("phys_power", 0.0))
	assert_gt(gu_absorb_phys, gu_scatter_phys * 1.05, "Absorb marrow grants Gu +8% offensive power over Scatter")


func case_t1_f07_06_ebony_scroll_rollers() -> void:
	var stage: NarrativeStage = NarrativeStage.new()
	mount_node(stage)

	stage.start_dialogue("dlg_ch01_temple_clash", true)
	InputRouter._process(0.45)
	InputRouter._input(make_key_event(KEY_ENTER, true))
	var redraw_cb: Callable = func() -> void:
		if is_instance_valid(stage):
			stage.queue_redraw()
	tree.process_frame.connect(redraw_cb)
	var shot: Image = await capture_1080p_frame(18, "t1_f07_06_narrative_rollers")
	if tree.process_frame.is_connected(redraw_cb):
		tree.process_frame.disconnect(redraw_cb)
	assert_eq(shot.get_width(), 1920, "Captured 1920px NarrativeStage frame")

	var spk_fs: int = stage._speaker_lbl.get_theme_font_size("font_size", "Label")
	var body_fs: int = stage._body_lbl.get_theme_font_size("font_size", "Label")
	assert_ge(spk_fs, 22, "Speaker plaque font_size >= 22px")
	assert_ge(body_fs, 22, "Dialogue body font_size >= 22px")

	var roller_info: Dictionary = _find_narrative_scroll_rollers(stage)
	assert_true(
		bool(roller_info.get("left_roller", false)) and bool(roller_info.get("right_roller", false)),
		"NarrativeStage renders visible left and right vertical carved dark-ebony scroll rollers flanking the Xuan dialogue scroll (master_c)"
	)
	assert_true(
		bool(roller_info.get("frame_tex_found", false)),
		"res://assets/ui/frames/ contains registered narrative scroll/roller frame art"
	)
