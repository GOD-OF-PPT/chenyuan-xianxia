extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 1
# @e2e_features: F10, F11


func register_cases() -> void:
	add_case("T1-F10-01", 1, "F10", "baseline", "Sole Spirit-Stone currency & 5-tier reputation discounts (95折->85折) in Yaolu shop vs Peddler stall", "case_t1_f10_01_reputation_discounts")
	add_case("T1-F10-02", 1, "F10", "baseline", "15s 3-phase Wen/Wu fire control flawless brew -> permanent HSlider batch quick-craft (x3)", "case_t1_f10_02_fire_minigame_and_quick_brew")
	add_case("T1-F10-03", 1, "F10", "baseline", "断玉剑匣 3-battle waste/material/shard purification -> flawless pills & eq_pendant_poxue", "case_t1_f10_03_sword_box_purification")
	add_case("T1-F10-04", 1, "F10", "baseline", "Peddler flea-market uniform non-spoiler borders & mouse_entered Sword-Box resonance appraisal", "case_t1_f10_04_peddler_stall_appraisal")
	add_case("T1-F10-05", 1, "F10", "polish_r3", "Polish R3 bronze cauldron (青铜丹炉) & live flickering 文火/武火 flames in 15s alchemy station", "case_t1_f10_05_r3_bronze_cauldron_flames")
	add_case("T1-F11-01", 1, "F11", "baseline", "万象道匣 C -> N -> B -> J -> J hotkey cycling & MODE_MODAL_MENU / MODE_WORLD_COMBAT restoration", "case_t1_f11_01_casket_hotkey_cycling")
	add_case("T1-F11-02", 1, "F11", "baseline", "NotoSerifCJKsc fonts, Simplified Chinese 根骨/灵识/膂力/体魄/身法 & >=16px runtime font floor", "case_t1_f11_02_fonts_zh_cn_and_16px_floor")
	add_case("T1-F11-03", 1, "F11", "polish_r3", "Polish R3 carved dark-ebony outer box, thread-bound Xuan tome spread & unfold/page-flip Tween + sfx_ui_page_turn", "case_t1_f11_03_r3_xuan_tome_unfold_tween")
	add_case("T1-F11-04", 1, "F11", "polish_r3", "Polish R3 unshaded ui_delta celadon-jade concentric water-ripple RMB ground marker during Space pause", "case_t1_f11_04_r3_rmb_jade_water_ripple")
	add_case("T1-F11-05", 1, "F11", "polish_r3", "Polish R3 shaded hover_outline.gdshader & Alt Xuan-paper nameplates on world interactables + NPCs", "case_t1_f11_05_r3_hover_outline_and_alt_plates")


func _join_visible_texts(root_node: Node) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(root_node):
		lines.append(lbl.text)
	return "\n".join(lines)


func _capture_settled_1080p(frames: int = 18) -> Image:
	return await capture_1080p_frame(maxi(18, frames))


func _find_button_containing(root_node: Node, substr: String) -> Button:
	for btn: Button in collect_visible_buttons(root_node):
		if btn.text.contains(substr):
			return btn
	return null


func _find_first_hslider(root_node: Node) -> HSlider:
	if root_node == null or not is_instance_valid(root_node):
		return null
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is HSlider and (cur as Control).is_visible_in_tree():
			return cur as HSlider
		for ch: Node in cur.get_children():
			stack.append(ch)
	return null


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


func _is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	return is_canvas_item_unshaded(ci)


func case_t1_f10_01_reputation_discounts() -> void:
	assert_eq(EconomyRules.compute_buy_price(100, 0), 100, "Tier 0 (0 rep) -> 100% price")
	assert_eq(EconomyRules.compute_buy_price(100, 1000), 95, "Tier 1 (1000 rep) -> 95折")
	assert_eq(EconomyRules.compute_buy_price(100, 3000), 92, "Tier 2 (3000 rep) -> 92折")
	assert_eq(EconomyRules.compute_buy_price(100, 6000), 88, "Tier 3 (6000 rep) -> 88折")
	assert_eq(EconomyRules.compute_buy_price(100, 10000), 85, "Tier 4 (10000 rep) -> 85折")

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)

	CampaignState.faction_reputation["jishi_pharmacy"] = 200
	modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)
	var txt_t0: String = _join_visible_texts(modals)
	var robe_name: String = DataDB.loc("EQ_QINGLAN_ROBE_NAME")
	var hc_name: String = DataDB.loc("ITEM_HUICHUN_NAME")
	assert_str_contains(txt_t0, "【%s】· 75 灵石" % robe_name, "Yaolu shop at 200 rep charges base 75 灵石 for 听雨青蓑衣")
	assert_str_contains(txt_t0, "【%s】· 32 灵石" % hc_name, "Yaolu shop at 200 rep charges base 32 灵石 for 回春散")

	CampaignState.faction_reputation["jishi_pharmacy"] = 3000
	modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)
	var txt_t2: String = _join_visible_texts(modals)
	var expected_robe_t2: int = EconomyRules.compute_buy_price(75, 3000) # round(75 * 0.92) = 69
	var expected_hc_t2: int = EconomyRules.compute_buy_price(32, 3000)   # round(32 * 0.92) = 29
	assert_str_contains(txt_t2, "【%s】· %d 灵石" % [robe_name, expected_robe_t2], "Yaolu shop at 3000 rep applies 92折 discount (69 灵石)")
	assert_str_contains(txt_t2, "【%s】· %d 灵石" % [hc_name, expected_hc_t2], "Yaolu shop at 3000 rep applies 92折 discount (29 灵石)")

	modals.open_shop_modal("shop_tingyu_peddler")
	await step_frames(2)
	var txt_peddler: String = _join_visible_texts(modals)
	var shard_name: String = DataDB.loc("ITEM_STALL_SHARD_NAME")
	assert_str_contains(txt_peddler, "【%s】· 60 灵石" % shard_name, "Peddler stall ignores pharmacy faction rep and keeps base 60 灵石")


func case_t1_f10_02_fire_minigame_and_quick_brew() -> void:
	var rdef: Dictionary = DataDB.get_recipe("recipe_huichun_powder")
	var targets: Array = as_arr(rdef.get("fire_targets", [0.32, 0.68, 0.42]))

	var eval_flaw: Dictionary = EconomyRules.evaluate_first_brew_fire(targets, [0.32, 0.68, 0.42], rdef)
	var eval_std: Dictionary = EconomyRules.evaluate_first_brew_fire(targets, [0.54, 0.46, 0.64], rdef)
	var eval_burnt: Dictionary = EconomyRules.evaluate_first_brew_fire(targets, [0.95, 0.05, 0.95], rdef)

	assert_eq(str(eval_flaw.get("quality", "")), "flawless", "avg_error==0 -> flawless")
	assert_approx(float(eval_flaw.get("potency_mult", 0.0)), 1.20, 0.01, "Flawless potency_mult == 1.20")
	assert_true(bool(eval_flaw.get("unlock_quick_brew", false)), "Flawless unlocks quick_brew")
	assert_eq(str(eval_std.get("quality", "")), "standard", "avg_error~0.22 -> standard")
	assert_false(bool(eval_std.get("unlock_quick_brew", true)), "Standard does not unlock quick_brew")
	assert_eq(str(eval_burnt.get("quality", "")), "burnt", "avg_error>0.34 -> burnt")
	assert_eq(str(eval_burnt.get("output_item_id", "")), "item_burnt_pill", "Burnt brew yields item_burnt_pill")

	CampaignState.add_item("item_ningqi_herb", 6, true)
	CampaignState.add_item("item_qingmu_leaf", 6, true)
	var herb_start: int = CampaignState.get_item_count("item_ningqi_herb")
	var leaf_start: int = CampaignState.get_item_count("item_qingmu_leaf")
	var flaw_start: int = CampaignState.get_item_count("item_huichun_powder_flawless")

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(2)
	assert_null(_find_first_hslider(modals), "Quick-brew HSlider hidden before first flawless brew")

	var start_btn: Button = _find_button_containing(modals, "15秒")
	assert_not_null(start_btn, "15s fire-control start button exists")
	if start_btn != null:
		start_btn.pressed.emit()
	await step_frames(1)
	assert_true(modals._brew_running, "15s fire minigame running")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_BREW_MINIGAME, "InputRouter enters MODE_BREW_MINIGAME")

	# Step 15s fire minigame in realistic 0.10s ticks while tracking 3-stage fire_targets
	var guard_ticks: int = 0
	while modals._brew_running and guard_ticks < 160:
		guard_ticks += 1
		var stg: int = clampi(int(floor(modals._brew_elapsed / 5.0)), 0, 2)
		modals._brew_heat = float(targets[stg])
		modals._process(0.10)
	await step_frames(2)

	assert_false(modals._brew_running, "15s minigame finished")
	assert_true(CampaignState.quick_brew_recipes.has("recipe_huichun_powder"), "Flawless 15s brew unlocks quick_brew_recipes")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), flaw_start + 1, "+1 flawless pill from 15s brew")

	var slider: HSlider = _find_first_hslider(modals)
	assert_not_null(slider, "Reopened furnace displays batch quick-brew HSlider")
	if slider != null:
		slider.value = 3.0
	var qb_btn: Button = _find_button_containing(modals, "一键完美速炼")
	assert_not_null(qb_btn, "Quick-brew button visible")
	if qb_btn != null:
		qb_btn.pressed.emit()
	await step_frames(2)

	assert_eq(CampaignState.get_item_count("item_ningqi_herb"), herb_start - 4, "1 first-brew + 3 batch quick-brew consumed 4 herbs")
	assert_eq(CampaignState.get_item_count("item_qingmu_leaf"), leaf_start - 4, "1 first-brew + 3 batch quick-brew consumed 4 leaves")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), flaw_start + 4, "Total +4 item_huichun_powder_flawless crafted")


func case_t1_f10_03_sword_box_purification() -> void:
	var slip_tags: Array[String] = []
	var slip_cb: Callable = func(payload: Dictionary) -> void:
		slip_tags.append(str(payload.get("tag", "")))
	NotifyHub.explore_slip_spawned.connect(slip_cb)

	# 1. Burnt pill -> 1x item_huichun_powder_flawless
	CampaignState.add_item("item_burnt_pill", 1, true)
	var hc_before: int = CampaignState.get_item_count("item_huichun_powder_flawless")
	assert_true(CampaignState.start_sword_box_purify("item_burnt_pill"), "Load item_burnt_pill into Sword Box")
	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 3, "Starts at 3 battles_remaining")
	CampaignState.advance_sword_box_progress(1)
	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 2, "2 battles remaining")
	CampaignState.advance_sword_box_progress(1)
	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 1, "1 battle remaining")
	CampaignState.advance_sword_box_progress(1)
	await step_frames(2)
	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 0, "0 battles remaining -> ready")
	assert_true(slip_tags.has("sword_box"), "Emits sword_box ready explore slip on completion")
	assert_true(CampaignState.claim_sword_box_output(), "Claim purified burnt pill")
	assert_true(CampaignState.sword_box_slot.is_empty(), "Sword Box slot cleared on claim")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), hc_before + 1, "Granted 1x item_huichun_powder_flawless")

	# 2. Corrupt flower -> 2x item_qingmu_pill_flawless
	CampaignState.add_item("item_corrupt_flower", 1, true)
	var qm_before: int = CampaignState.get_item_count("item_qingmu_pill_flawless")
	assert_true(CampaignState.start_sword_box_purify("item_corrupt_flower"), "Load item_corrupt_flower into Sword Box")
	CampaignState.advance_sword_box_progress(3)
	assert_true(CampaignState.claim_sword_box_output(), "Claim purified corrupt flower")
	assert_eq(CampaignState.get_item_count("item_qingmu_pill_flawless"), qm_before + 2, "Granted 2x item_qingmu_pill_flawless")

	# 3. Stall sword shard -> 1x eq_pendant_poxue
	CampaignState.add_item("item_stall_sword_shard", 1, true)
	var px_before: int = CampaignState.get_item_count("eq_pendant_poxue")
	assert_true(CampaignState.start_sword_box_purify("item_stall_sword_shard"), "Load item_stall_sword_shard into Sword Box")
	CampaignState.advance_sword_box_progress(3)
	assert_true(CampaignState.claim_sword_box_output(), "Claim purified sword shard")
	assert_eq(CampaignState.get_item_count("eq_pendant_poxue"), px_before + 1, "Granted 1x eq_pendant_poxue")


func case_t1_f10_04_peddler_stall_appraisal() -> void:
	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_shop_modal("shop_tingyu_peddler")
	await step_frames(3)

	var bone_name: String = DataDB.loc("ITEM_STALL_BONE_NAME")
	var shard_name: String = DataDB.loc("ITEM_STALL_SHARD_NAME")
	var stall_cards: Array[PanelContainer] = []
	var bone_card: PanelContainer = null
	var shard_card: PanelContainer = null

	var stack: Array[Node] = [modals]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is PanelContainer:
			var pc: PanelContainer = cur as PanelContainer
			var sub_txt: String = _join_visible_texts(pc)
			var has_buy_btn: bool = (_find_button_containing(pc, "购入") != null)
			if has_buy_btn and pc.get_parent() is VBoxContainer:
				stall_cards.append(pc)
				if sub_txt.contains(bone_name):
					bone_card = pc
				elif sub_txt.contains(shard_name):
					shard_card = pc
		for ch: Node in cur.get_children():
			stack.append(ch)

	assert_eq(stall_cards.size(), 4, "Peddler stall renders 4 curio stock cards")
	for card: PanelContainer in stall_cards:
		var sb: StyleBox = card.get_theme_stylebox("panel", "PanelContainer")
		if sb is StyleBoxFlat:
			assert_eq((sb as StyleBoxFlat).border_color, UIThemeBuilder.COL_BRONZE_DIM, "All 4 stall cards share uniform non-spoiler border color")

	assert_not_null(bone_card, "Found mundane bone card")
	assert_not_null(shard_card, "Found sword shard card")
	if bone_card != null:
		bone_card.mouse_entered.emit()
		await step_frames(1)
		var txt_bone: String = _join_visible_texts(modals)
		assert_str_contains(txt_bone, "毫无动静", "Mundane curio hover shows dispersed-qi / zero Sword-Box reaction")

	if shard_card != null:
		shard_card.mouse_entered.emit()
		await step_frames(1)
		var txt_shard: String = _join_visible_texts(modals)
		assert_str_contains(txt_shard, "断玉剑匣", "Hovering sword shard triggers subtle 断玉剑匣 warm resonance text")
		assert_str_contains(txt_shard, "温热", "Resonance text describes warm vibration")


func case_t1_f10_05_r3_bronze_cauldron_flames() -> void:
	CampaignState.add_item("item_ningqi_herb", 2, true)
	CampaignState.add_item("item_qingmu_leaf", 2, true)

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(2)

	var start_btn: Button = _find_button_containing(modals, "15秒")
	assert_not_null(start_btn, "15s alchemy button present")
	if start_btn != null:
		start_btn.pressed.emit()
	await step_frames(2)

	var cauldron_rect: Rect2i = find_alchemy_cauldron_rect(modals)
	var has_cauldron_visual: bool = (cauldron_rect.size.x > 0 and cauldron_rect.size.y > 0)

	modals._brew_heat = 0.18
	var img_wen: Image = await _capture_settled_1080p(18)
	modals._brew_heat = 0.88
	var img_wu: Image = await _capture_settled_1080p(18)

	var cauldron_diff: float = 0.0
	if has_cauldron_visual:
		cauldron_diff = _mean_abs_diff_in_rect(img_wen, img_wu, cauldron_rect)
	record_metric("has_cauldron_visual", has_cauldron_visual)
	record_metric("cauldron_flame_diff", snappedf(cauldron_diff, 0.0001))

	assert_true(
		has_cauldron_visual,
		"Polish R3 active alchemy UI must render a bronze cauldron + flame canvas/sprite/particles (>=110px tall, replacing flat 860x44 ColorRect stub)"
	)
	assert_gt(
		cauldron_diff,
		0.010,
		"Polish R3 cauldron flames must visibly flicker & shift color between 文火 (0.18) and 武火 (0.88)"
	)


func case_t1_f11_01_casket_hotkey_cycling() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	assert_false(world._casket.visible, "Casket starts closed")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Starts in MODE_WORLD_COMBAT")

	dispatch_input(make_key_event(KEY_C, true))
	await step_frames(1)
	assert_true(world._casket.visible, "KEY_C opens DaoCasketPanel")
	assert_eq(world._casket.active_tab, "cultivation", "KEY_C selects cultivation tab")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "Mode is MODE_MODAL_MENU")

	dispatch_input(make_key_event(KEY_N, true))
	await step_frames(1)
	assert_eq(world._casket.active_tab, "specialization", "KEY_N switches to specialization tab")

	dispatch_input(make_key_event(KEY_B, true))
	await step_frames(1)
	assert_eq(world._casket.active_tab, "inventory", "KEY_B switches to inventory tab")

	dispatch_input(make_key_event(KEY_J, true))
	await step_frames(1)
	assert_eq(world._casket.active_tab, "journal", "KEY_J switches to journal tab")

	dispatch_input(make_key_event(KEY_J, true))
	await step_frames(1)
	assert_false(world._casket.visible, "Pressing KEY_J again closes DaoCasketPanel")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Closing casket restores MODE_WORLD_COMBAT")


func case_t1_f11_02_fonts_zh_cn_and_16px_floor() -> void:
	var reg_font: Font = UIThemeBuilder.get_regular_font()
	var bold_font: Font = UIThemeBuilder.get_bold_font()
	assert_not_null(reg_font, "Regular font loaded")
	assert_not_null(bold_font, "Bold font loaded")
	if reg_font != null:
		assert_str_contains(reg_font.resource_path, "NotoSerifCJKsc-Regular.otf", "Regular font is NotoSerifCJKsc-Regular.otf")
	if bold_font != null:
		assert_str_contains(bold_font.resource_path, "NotoSerifCJKsc-Bold.otf", "Bold font is NotoSerifCJKsc-Bold.otf")

	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)

	casket.open_tab("cultivation")
	await step_frames(3)
	var cult_txt: String = _join_visible_texts(casket)
	for term: String in ["根骨", "灵识", "膂力", "体魄", "身法", "气血", "真元"]:
		assert_str_contains(cult_txt, term, "Tab 1 renders canonical Simplified Chinese '%s'" % term)

	for tab_id: String in ["cultivation", "specialization", "inventory", "journal"]:
		if casket.active_tab != tab_id or not casket.visible:
			casket.open_tab(tab_id)
			await step_frames(3)
		var fstats: Dictionary = min_font_size_in_tree(casket)
		var min_px: int = int(fstats.get("min_px", 0))
		var offenders: Array = as_arr(fstats.get("offenders", []))
		assert_ge(min_px, 16, "Casket tab '%s' min font size >= 16px" % tab_id)
		assert_true(offenders.is_empty(), "Casket tab '%s' has 0 <16px offenders (%s)" % [tab_id, str(offenders)])


func case_t1_f11_03_r3_xuan_tome_unfold_tween() -> void:
	SaveManager.reduced_motion = false
	var audio_dir: AudioDirector = AudioDirector.new()
	mount_node(audio_dir)
	var casket: DaoCasketPanel = DaoCasketPanel.new()
	casket.audio_director = audio_dir
	mount_node(casket)
	await step_frames(2)

	var tweens_before: int = tree.get_processed_tweens().size()
	casket.open_tab("cultivation")
	var tweens_on_open: int = tree.get_processed_tweens().size()
	await step_frames(4)
	casket.open_tab("inventory")
	var tweens_on_flip: int = tree.get_processed_tweens().size()
	var img: Image = await _capture_settled_1080p(20)

	var has_tome_art_or_stacked_draw: bool = false
	var stack: Array[Node] = [casket]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is TextureRect:
			var tr_f: TextureRect = cur as TextureRect
			if tr_f.is_visible_in_tree() and tr_f.texture != null and tr_f.size.x >= 900.0 and tr_f.size.y >= 600.0:
				has_tome_art_or_stacked_draw = true
				break
		elif cur is NinePatchRect:
			var np_f: NinePatchRect = cur as NinePatchRect
			if np_f.is_visible_in_tree() and np_f.texture != null and np_f.size.x >= 900.0:
				has_tome_art_or_stacked_draw = true
				break
		elif cur is PanelContainer:
			var sb: StyleBox = (cur as PanelContainer).get_theme_stylebox("panel", "PanelContainer")
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				has_tome_art_or_stacked_draw = true
				break
		elif cur is Control and cur.get_script() != null and cur != casket:
			var ctrl_f: Control = cur as Control
			if ctrl_f.is_visible_in_tree() and ctrl_f.size.x >= 900.0 and ctrl_f.size.y >= 600.0 and obj_has_method(ctrl_f, "_draw"):
				has_tome_art_or_stacked_draw = true
				break
		for ch: Node in cur.get_children():
			stack.append(ch)

	var outer_stats: Dictionary = sample_image_roi_stats(img, Rect2i(20, 20, 120, 120))
	var tween_triggered: bool = (tweens_on_open > tweens_before) or (tweens_on_flip > tweens_before)
	record_metric("tome_spread_visual", has_tome_art_or_stacked_draw)
	record_metric("tween_triggered", tween_triggered)
	record_metric("outer_luma", snappedf(float(outer_stats.get("mean_luma", 0.0)), 0.001))

	assert_lt(float(outer_stats.get("mean_luma", 1.0)), 0.18, "Outer frame region is dark carved ebony (<0.18 luma)")
	assert_true(
		has_tome_art_or_stacked_draw,
		"Polish R3 DaoCasketPanel must render an open thread-bound Xuan-paper tome frame/spread (not plain flat StyleBoxFlat)"
	)
	assert_true(
		tween_triggered,
		"Polish R3 DaoCasketPanel open_tab / tab switch must drive an unfold & page-flip Tween when reduced_motion == false"
	)


func case_t1_f11_04_r3_rmb_jade_water_ripple() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(18)

	# Engage tactical pause so combat_delta == 0.0 while ui_delta > 0.0
	world._combat_ctrl.in_combat = true
	world._combat_ctrl.toggle_tactical_pause()
	assert_true(world._combat_ctrl.tactical_paused, "Tactical pause active (combat_delta == 0.0)")

	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(960.0, 720.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	var target_world_pt: Vector2 = Vector2(760.0, 780.0)
	var screen_pt: Vector2 = world.get_canvas_transform() * target_world_pt
	Input.warp_mouse(screen_pt)
	dispatch_input(make_mouse_motion_event(screen_pt))
	await step_frames(1)
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, screen_pt, true))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, screen_pt, false))

	var img_early: Image = await capture_1080p_subframe(3)
	var img_late: Image = await capture_1080p_subframe(5)

	var has_ripple_api: bool = (
		obj_has_method(world._ground_vfx, "spawn_move_ripple")
		or obj_has_method(world._sky_vfx, "spawn_move_ripple")
		or obj_method_arg_count(world._ground_vfx, "step_fx") >= 2
	)
	var vfx_unshaded: bool = _is_canvas_item_unshaded(world._ground_vfx) or _is_canvas_item_unshaded(world._sky_vfx)
	if not vfx_unshaded:
		for ch: Node in world._ground_vfx.get_children():
			if ch is CanvasItem and _is_canvas_item_unshaded(ch as CanvasItem):
				vfx_unshaded = true
				break

	var scr_i: Vector2i = Vector2i(int(round(screen_pt.x)), int(round(screen_pt.y)))
	var ripple_roi: Rect2i = Rect2i(scr_i.x - 42, scr_i.y - 28, 84, 56)
	var ripple_anim_diff: float = _mean_abs_diff_in_rect(img_early, img_late, ripple_roi)

	record_metric("has_ripple_api", has_ripple_api)
	record_metric("vfx_unshaded", vfx_unshaded)
	record_metric("ripple_ui_delta_diff", snappedf(ripple_anim_diff, 0.0001))

	assert_true(
		has_ripple_api,
		"Polish R3 CombatVfxOverlay must expose spawn_move_ripple / step_fx(combat_delta, ui_delta) contract (PROJECT.md:82)"
	)
	assert_true(
		vfx_unshaded,
		"Polish R3 RMB celadon-jade water-ripple VFX must render unshaded (LIGHT_MODE_UNSHADED or render_mode unshaded; per PROJECT.md:92)"
	)
	assert_gt(
		ripple_anim_diff,
		0.004,
		"Polish R3 RMB jade water-ripple must animate smoothly via real-time ui_delta even while Space tactical_paused freezes combat_delta == 0.0"
	)


func case_t1_f11_05_r3_hover_outline_and_alt_plates() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(3)

	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(1380.0, 650.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	var shader_exists: bool = res_exists("res://src/presentation/shaders/hover_outline.gdshader")

	# Hover yaolu_alchemy at Vector2(1405, 646)
	var alchemy_inter: Dictionary = {}
	for inter: Dictionary in world._interactables:
		if str(inter.get("id", "")) == "yaolu_alchemy":
			alchemy_inter = inter
			break
	var alch_pos: Vector2 = alchemy_inter.get("pos", Vector2(1405.0, 646.0)) as Vector2
	var alch_screen: Vector2 = world.get_canvas_transform() * (alch_pos + Vector2(0.0, -32.0))
	Input.warp_mouse(alch_screen)
	dispatch_input(make_mouse_motion_event(alch_screen))
	await step_frames(4)

	var alch_sp: Sprite2D = alchemy_inter.get("sprite", null) as Sprite2D
	var hovered_has_outline_shader: bool = false
	if alch_sp != null and alch_sp.material is ShaderMaterial:
		var sm: ShaderMaterial = alch_sp.material as ShaderMaterial
		if sm.shader != null and sm.shader.resource_path.ends_with("hover_outline.gdshader"):
			hovered_has_outline_shader = true

	# Hold Alt and check interactable Xuan nameplates
	var img_no_alt: Image = await _capture_settled_1080p(18)
	dispatch_input(make_key_event(KEY_ALT, true, false, true))
	InputRouter.alt_held = true
	InputRouter.alt_highlight_changed.emit(true)
	var img_alt: Image = await _capture_settled_1080p(18)

	# Above yaolu_shop (Vector2(1085, 632)) where player is NOT standing and cursor is NOT hovering
	var shop_overhead_scr: Vector2 = world.get_canvas_transform() * Vector2(1085.0, 505.0)
	var shop_plate_roi: Rect2i = Rect2i(int(shop_overhead_scr.x) - 90, int(shop_overhead_scr.y) - 36, 180, 64)
	var interactable_alt_diff: float = _mean_abs_diff_in_rect(img_no_alt, img_alt, shop_plate_roi)

	record_metric("hover_shader_exists", shader_exists)
	record_metric("alchemy_has_hover_shader", hovered_has_outline_shader)
	record_metric("alt_interactable_plate_diff", snappedf(interactable_alt_diff, 0.0001))

	assert_true(shader_exists, "Polish R3 hover_outline.gdshader exists at res://src/presentation/shaders/hover_outline.gdshader")
	assert_true(hovered_has_outline_shader, "Hovering yaolu_alchemy applies hover_outline.gdshader ShaderMaterial")
	assert_gt(
		interactable_alt_diff,
		0.012,
		"Holding Alt renders Xuan-paper nameplates above world _interactables (yaolu_shop / yaolu_alchemy) in QinglanWorld"
	)
