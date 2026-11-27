extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 4
# @e2e_features: F8, F9, F10, F11


func register_cases() -> void:
	add_case("T4-W3-01", 4, "F10", "baseline", "Live 1920x1080 Chapter 1 Economy, Casket 4-Tab Tour (C/N/B/J, P hidden), >=16px NotoSerifCJKsc Typography & Data/Locale Scenario", "case_t4_w3_01_live_1080p_economy_casket_baseline")
	add_case("T4-W3-02", 4, "F9", "polish_r3", "Live 1920x1080 master_d_dao_casket.png Open Thread-Bound Xuan Tome Visual Parity Gate (Ebony Box, 3-Col Xuan, Ink Meridian, 3+2 Slots, #8FD4E8 Compare)", "case_t4_w3_02_r3_master_d_xuan_tome_parity")
	add_case("T4-W3-03", 4, "F11", "polish_r3", "Live 1920x1080 Flickering-Flame Bronze Cauldron (文火 vs 武火) + World Unshaded RMB Jade Ripple, hover_outline.gdshader & Alt Nameplates", "case_t4_w3_03_r3_cauldron_and_world_interactions")


func _join_visible_texts(root_node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(root_node):
		out.append(lbl.text)
	for btn: Button in collect_visible_buttons(root_node):
		out.append(btn.text)
	return "\n".join(out)


func _capture_settled_1080p(frames: int = 18) -> Image:
	return await capture_1080p_frame(maxi(18, frames))


func _find_button_containing(root_node: Node, substr: String) -> Button:
	for btn: Button in collect_visible_buttons(root_node):
		if btn.text.contains(substr):
			return btn
	return null


func _count_fluorescent_sampled(img: Image, step_px: int = 4) -> int:
	if img == null or img.is_empty():
		return 0
	var cnt: int = 0
	for y: int in range(0, img.get_height(), step_px):
		for x: int in range(0, img.get_width(), step_px):
			var c: Color = img.get_pixel(x, y)
			var cmax: float = maxf(c.r, maxf(c.g, c.b))
			var cmin: float = minf(c.r, minf(c.g, c.b))
			var sat: float = (cmax - cmin) / maxf(cmax, 0.001)
			if cmax >= (245.0 / 255.0) and sat >= 0.92:
				cnt += 1
	return cnt


func _mean_abs_diff_in_rect(img_a: Image, img_b: Image, rect: Rect2i, skip_rect: Rect2i = Rect2i()) -> float:
	if img_a == null or img_b == null or img_a.is_empty() or img_b.is_empty():
		return 0.0
	var x0: int = clampi(rect.position.x, 0, mini(img_a.get_width(), img_b.get_width()))
	var y0: int = clampi(rect.position.y, 0, mini(img_a.get_height(), img_b.get_height()))
	var x1: int = clampi(rect.position.x + rect.size.x, 0, mini(img_a.get_width(), img_b.get_width()))
	var y1: int = clampi(rect.position.y + rect.size.y, 0, mini(img_a.get_height(), img_b.get_height()))
	var stride: int = 4 if rect.size.x > 240 else 2
	var total: float = 0.0
	var cnt: int = 0
	for y: int in range(y0, y1, stride):
		for x: int in range(x0, x1, stride):
			if skip_rect.size.x > 0 and skip_rect.has_point(Vector2i(x, y)):
				continue
			var ca: Color = img_a.get_pixel(x, y)
			var cb: Color = img_b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			cnt += 1
	return total / float(maxi(1, cnt))


func case_t4_w3_01_live_1080p_economy_casket_baseline() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", true)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")
	CampaignState.faction_reputation["jishi_pharmacy"] = 1000
	CampaignState.stamp_ink_seal("seal_yaolu_justice", "seek_truth")
	CampaignState.unlock_clue("clue_peddler_shard")
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("item_burnt_pill", 1, true)

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(4)

	# 1. Verify Yaolu Pharmacy Shop 95折 discount, sole Spirit-Stone currency & unsellable protection
	world._modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)
	var shop_txt: String = _join_visible_texts(world._modals)
	assert_str_contains(shop_txt, "灵石", "Sole Spirit-Stone currency displayed")
	assert_str_not_contains(shop_txt, "%s ×" % DataDB.loc("ITEM_BURNT_PILL_NAME"), "Unsellable burnt pill hidden from sell list")
	world._modals.close_modal()

	# 2. Live 1920x1080 4-Tab Casket Tour (C -> N -> B -> J -> C, P hidden)
	dispatch_input(make_key_event(KEY_P, true))
	await step_frames(1)
	assert_false(world._casket.visible, "KEY_P hidden / ignored in Ch1")

	var tab_hotkeys: Array[Array] = [
		[KEY_C, "cultivation"],
		[KEY_N, "specialization"],
		[KEY_B, "inventory"],
		[KEY_J, "journal"],
	]
	for pair: Array in tab_hotkeys:
		var kc: Key = int(pair[0]) as Key
		var expected_tab: String = str(pair[1])
		dispatch_input(make_key_event(kc, true))
		await step_frames(1)
		assert_eq(world._casket.active_tab, expected_tab, "Switched to casket tab '%s'" % expected_tab)

		var fstats: Dictionary = min_font_size_in_tree(world._casket)
		assert_ge(int(fstats.get("min_px", 0)), 16, "Tab '%s' runtime font floor >= 16px" % expected_tab)
		assert_true(as_arr(fstats.get("offenders", [])).is_empty(), "Tab '%s' 0 font-size offenders" % expected_tab)

		var tab_txt: String = _join_visible_texts(world._casket)
		assert_str_not_contains(tab_txt, "灵兽袋", "Tab '%s' hides unopened 灵兽袋" % expected_tab)
		if expected_tab == "cultivation":
			for st_cn: String in ["根骨", "灵识", "膂力", "体魄", "身法"]:
				assert_str_contains(tab_txt, st_cn, "Tab 1 renders Simplified Chinese '%s'" % st_cn)

	dispatch_input(make_key_event(KEY_C, true))
	var img_tab: Image = await _capture_settled_1080p(18)
	assert_eq(img_tab.get_width(), 1920, "Casket 1080p width == 1920")
	assert_eq(img_tab.get_height(), 1080, "Casket 1080p height == 1080")
	assert_eq(_count_fluorescent_sampled(img_tab, 12), 0, "Casket 1080p has 0 fluorescent pixels")
	var xuan_col: Dictionary = sample_image_roi_stats(img_tab, Rect2i(780, 240, 160, 140))
	assert_gt(float(xuan_col.get("std_luma", 0.0)), 0.03, "Rendered 1080p UI exhibits real typography/frame contrast")
	assert_gt(float(xuan_col.get("mean_r", 0.0)), float(xuan_col.get("mean_b", 1.0)), "Warm Xuan paper R > B in casket")

	dispatch_input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_false(world._casket.visible, "Esc closes casket cleanly")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Returned to MODE_WORLD_COMBAT")


func case_t4_w3_02_r3_master_d_xuan_tome_parity() -> void:
	SaveManager.reduced_motion = false
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_2", "flawless")
	for sk: String in ["con", "spi", "str", "end", "agi"]:
		CampaignState.allocate_potential_point("gu_changqing", sk, 1)

	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	CampaignState.add_item("item_marrow_dew", 1, true)
	CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_jingqing")

	var audio_dir: AudioDirector = AudioDirector.new()
	mount_node(audio_dir)
	var casket: DaoCasketPanel = DaoCasketPanel.new()
	casket.audio_director = audio_dir
	mount_node(casket)
	await step_frames(2)

	casket.selected_item_id = "eq_pendant_poxue"
	casket.open_tab("cultivation")
	var img_casket: Image = await _capture_settled_1080p(20)

	assert_eq(img_casket.get_width(), 1920, "1920px width")
	assert_eq(img_casket.get_height(), 1080, "1080px height")
	assert_eq(_count_fluorescent_sampled(img_casket, 12), 0, "0 fluorescent pixels in 1080p casket capture")
	assert_eq(casket._tab_buttons.size(), 4, "Strict 4 Ch1 tabs (C/N/B/J)")

	# 1. Carved dark-ebony outer frame + 3 warm aged Xuan paper columns
	var outer_ebony: Dictionary = sample_image_roi_stats(img_casket, Rect2i(16, 16, 96, 96))
	var col_left: Dictionary = sample_image_roi_stats(img_casket, Rect2i(180, 240, 140, 140))
	var col_mid: Dictionary = sample_image_roi_stats(img_casket, Rect2i(780, 240, 140, 140))
	var col_right: Dictionary = sample_image_roi_stats(img_casket, Rect2i(1360, 240, 140, 140))

	assert_lt(float(outer_ebony.get("mean_luma", 1.0)), 0.17, "Carved dark-ebony outer box (#1C1815)")
	assert_gt(float(col_left.get("mean_luma", 0.0)), 0.50, "Left Xuan-paper page mean_luma > 0.50")
	assert_gt(float(col_left.get("mean_r", 0.0)), float(col_left.get("mean_b", 1.0)), "Left Xuan page warm R > B")
	assert_gt(float(col_mid.get("mean_r", 0.0)), float(col_mid.get("mean_b", 1.0)), "Middle Xuan page warm R > B")
	assert_gt(float(col_right.get("mean_r", 0.0)), float(col_right.get("mean_b", 1.0)), "Right Xuan page warm R > B")

	# 2. Left-page classical brush-ink meridian figure + celadon-jade acupoints
	var jade_acupoints: int = 0
	for y: int in range(215, 760, 4):
		for x: int in range(180, 560, 4):
			var px: Color = img_casket.get_pixel(x, y)
			if px.g > 0.40 and px.g > px.r + 0.045:
				jade_acupoints += 1

	# 3. Middle-page 3+2 square embossed artifact icon slots + 5 bronze potential bars
	var mid_icons: int = 0
	var mid_bars: int = 0
	var stack: Array[Node] = [casket]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Control and (cur as Control).is_visible_in_tree():
			var c: Control = cur as Control
			var cx: float = c.global_position.x + c.size.x * 0.5
			if cx >= 670.0 and cx <= 1290.0:
				if c is TextureRect and (c as TextureRect).texture != null and c.size.x >= 44.0 and c.size.y >= 44.0 and c.size.x <= 240.0:
					mid_icons += 1
				elif (c is Range and not (c is ScrollBar)) or (c is ColorRect and c.size.x >= 90.0 and c.size.y >= 8.0 and c.size.y <= 36.0):
					mid_bars += 1
				elif c.get_script() != null and not (c is Label) and not (c is Button) and c.size.x >= 120.0 and c.size.y >= 12.0 and c.size.y <= 48.0 and obj_has_method(c, "_draw"):
					mid_bars += 1
		for ch: Node in cur.get_children():
			stack.append(ch)

	# 4. Right-page hairline ledger + side-by-side #8FD4E8 sky-blue stunt comparison card
	var target_sky: Color = Color("#8FD4E8")
	var sky_ok: bool = (
		absf(UIThemeBuilder.COL_BLUE_STUNT.r - target_sky.r) <= 0.08
		and absf(UIThemeBuilder.COL_BLUE_STUNT.g - target_sky.g) <= 0.08
		and absf(UIThemeBuilder.COL_BLUE_STUNT.b - target_sky.b) <= 0.08
	)
	var all_txt: String = _join_visible_texts(casket)
	var has_both_pendants_in_tab1: bool = (
		all_txt.contains(DataDB.loc("EQ_PENDANT_JINGQING_NAME"))
		and all_txt.contains(DataDB.loc("EQ_PENDANT_POXUE_NAME"))
	)

	record_metric("jade_acupoints_px", jade_acupoints)
	record_metric("mid_embossed_icons", mid_icons)
	record_metric("mid_potential_bars", mid_bars)
	record_metric("sky_blue_stunt_ok", sky_ok)
	record_metric("tab1_side_by_side_compare", has_both_pendants_in_tab1)

	assert_ge(jade_acupoints, 24, "Left page renders ink meridian figure with glowing celadon-jade acupoints (master_d)")
	assert_ge(mid_icons, 5, "Middle page renders 3+2 embossed artifact icon slots (master_d)")
	assert_ge(mid_bars, 5, "Middle page renders 5 bronze-framed potential bars (master_d)")
	assert_true(sky_ok, "Right page stunt comparison uses #8FD4E8 sky-blue (master_d)")
	assert_true(has_both_pendants_in_tab1, "Right page lower half renders side-by-side equipped vs compared pendant cards (master_d)")


func case_t4_w3_03_r3_cauldron_and_world_interactions() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.add_item("item_ningqi_herb", 3, true)
	CampaignState.add_item("item_qingmu_leaf", 3, true)

	# Part A: Live 1920x1080 Bronze Cauldron Wen-Fire (frame_1) vs Wu-Fire (frame_2)
	var standalone_modals: WorldModals = WorldModals.new()
	mount_node(standalone_modals)
	await step_frames(2)
	standalone_modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(1)
	var sbtn: Button = _find_button_containing(standalone_modals, "15秒")
	if sbtn != null:
		sbtn.pressed.emit()
	await step_frames(1)

	var cauldron_rect: Rect2i = find_alchemy_cauldron_rect(standalone_modals)
	standalone_modals._brew_heat = 0.22
	var frame_1_wen: Image = await _capture_settled_1080p(18)
	standalone_modals._brew_heat = 0.85
	var frame_2_wu: Image = await _capture_settled_1080p(18)

	var cauldron_shift: float = 0.0
	if cauldron_rect.size.x > 0 and cauldron_rect.size.y > 0:
		cauldron_shift = _mean_abs_diff_in_rect(frame_1_wen, frame_2_wu, cauldron_rect)
	standalone_modals.close_modal()
	_spawned_nodes.erase(standalone_modals)
	standalone_modals.get_parent().remove_child(standalone_modals)
	standalone_modals.free()

	# Part B: Live 1920x1080 World RMB Jade Water-Ripple + hover_outline.gdshader + Alt Nameplates
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(18)
	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(1280.0, 660.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	var rmb_world: Vector2 = Vector2(1210.0, 725.0)
	var rmb_scr: Vector2 = world.get_canvas_transform() * rmb_world
	Input.warp_mouse(rmb_scr)
	dispatch_input(make_mouse_motion_event(rmb_scr))
	await step_frames(1)
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, rmb_scr, true))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, rmb_scr, false))

	var alch_scr: Vector2 = world.get_canvas_transform() * Vector2(1405.0, 614.0)
	Input.warp_mouse(alch_scr)
	dispatch_input(make_mouse_motion_event(alch_scr))
	InputRouter.alt_held = true
	InputRouter.alt_highlight_changed.emit(true)

	var frame_world_a: Image = await capture_1080p_subframe(3)
	var frame_world_b: Image = await capture_1080p_subframe(5)

	var shader_ok: bool = false
	for inter: Dictionary in world._interactables:
		if str(inter.get("id", "")) == "yaolu_alchemy":
			var sp: Sprite2D = inter.get("sprite", null) as Sprite2D
			if sp != null and sp.material is ShaderMaterial:
				var sm: ShaderMaterial = sp.material as ShaderMaterial
				if sm.shader != null and sm.shader.resource_path.ends_with("hover_outline.gdshader"):
					shader_ok = true
			break

	var rscr_i: Vector2i = Vector2i(int(round(rmb_scr.x)), int(round(rmb_scr.y)))
	var ripple_shift: float = _mean_abs_diff_in_rect(frame_world_a, frame_world_b, Rect2i(rscr_i.x - 42, rscr_i.y - 28, 84, 56))

	record_metric("cauldron_wen_wu_shift", snappedf(cauldron_shift, 0.0001))
	record_metric("alchemy_hover_shader", shader_ok)
	record_metric("world_ripple_shift", snappedf(ripple_shift, 0.0001))

	assert_gt(cauldron_shift, 0.010, "Live 1080p bronze cauldron flames shift dynamically between 文火 (0.22) and 武火 (0.85)")
	assert_true(shader_ok, "Live 1080p hovering yaolu_alchemy activates shaded hover_outline.gdshader")
	assert_gt(ripple_shift, 0.004, "Live 1080p RMB ground click renders animated unshaded celadon-jade concentric water-ripple")
