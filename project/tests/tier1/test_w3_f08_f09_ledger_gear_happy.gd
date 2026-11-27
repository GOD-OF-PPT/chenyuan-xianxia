extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 1
# @e2e_features: F8, F9


func register_cases() -> void:
	add_case("T1-F08-01", 1, "F8", "baseline", "Realm progression mortal -> qi_refining_1 -> qi_refining_2 (+5 potential, lifespan, talent tiers, full restore)", "case_t1_f08_01_realm_progression")
	add_case("T1-F08-02", 1, "F8", "baseline", "5 Potentials (con/spi/str/end/agi) allocation math & free Marrow Dew (洗髓灵露) 100% lossless respec", "case_t1_f08_02_potentials_and_respec")
	add_case("T1-F08-03", 1, "F8", "baseline", "Hyperbolic secondary rating diminishing across k_realm & DaoCasketPanel post-diminishing ledger", "case_t1_f08_03_hyperbolic_ratings_and_ledger")
	add_case("T1-F08-04", 1, "F8", "baseline", "Breakthrough grade evaluation & Flawless (+8% five-stats) vs Solid Dao-foundation multiplier", "case_t1_f08_04_flawless_foundation_bonus")
	add_case("T1-F08-05", 1, "F8", "polish_r3", "Polish R3 Tab 1 left-page brush-ink meridian figure & glowing celadon-jade acupoints (master_d)", "case_t1_f08_05_r3_ink_meridian_figure")
	add_case("T1-F09-01", 1, "F9", "baseline", "5-slot artifact equipping (eq_ancient_wood_blade & eq_pendant_poxue), inventory swap & weapon range/interval", "case_t1_f09_01_five_slot_equip_swap")
	add_case("T1-F09-02", 1, "F9", "baseline", "3-piece sect set bonuses (3/3 -> 2/3 -> 1/3) & active_set_effects across Gu, Shen & Pei", "case_t1_f09_02_sect_set_bonuses")
	add_case("T1-F09-03", 1, "F9", "baseline", "Blue stunts (晶清玉露 55 Qi, 破血狂攻 40 Qi) & Gu Natal Treasure 断玉剑匣 R skill mapping", "case_t1_f09_03_blue_stunts_and_natal_treasure")
	add_case("T1-F09-04", 1, "F9", "polish_r3", "Polish R3 Tab 1 middle-page 3+2 square embossed artifact icon slots & 5 bronze potential bars (master_d)", "case_t1_f09_04_r3_embossed_slots_and_bars")
	add_case("T1-F09-05", 1, "F9", "polish_r3", "Polish R3 right-page hairline ledger & #8FD4E8 sky-blue stunt side-by-side comparison card (master_d)", "case_t1_f09_05_r3_sky_blue_stunt_comparison")


func _get_member_dict(cid: String) -> Dictionary:
	return as_dict(CampaignState.party_members.get(cid, {}))


func _get_member_sheet(cid: String) -> Dictionary:
	return as_dict(_get_member_dict(cid).get("sheet", {}))


func _join_visible_label_texts(root_node: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(root_node):
		parts.append(lbl.text)
	return "\n".join(parts)


func _collect_visible_controls_in_x_band(root_node: Node, min_x: float, max_x: float) -> Array[Control]:
	var out: Array[Control] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Control:
			var ctrl: Control = cur as Control
			if ctrl.is_visible_in_tree():
				var cx: float = ctrl.global_position.x + ctrl.size.x * 0.5
				if cx >= min_x and cx <= max_x:
					out.append(ctrl)
		for ch: Node in cur.get_children():
			stack.append(ch)
	return out


func case_t1_f08_01_realm_progression() -> void:
	var gu_m0: Dictionary = _get_member_dict("gu_changqing")
	var sheet0: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(str(gu_m0.get("realm_id", "")), "mortal", "Gu starts at mortal realm")
	assert_eq(int(gu_m0.get("free_potential", -1)), 0, "Mortal starts with 0 free potential")
	assert_eq(int(sheet0.get("lifespan_max", 0)), 80, "Mortal base lifespan_max == 80")
	var tal0: Array = as_arr(gu_m0.get("unlocked_talents", []))
	assert_eq(tal0.size(), 1, "Mortal unlocks tier 1 specialization node only")
	assert_true(tal0.has("nd_gu_a1"), "Tier 1 node nd_gu_a1 unlocked at mortal")

	gu_m0["hp"] = 35
	gu_m0["mp"] = 12
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "solid")

	var gu_m1: Dictionary = _get_member_dict("gu_changqing")
	var sheet1: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(str(gu_m1.get("realm_id", "")), "qi_refining_1", "Advanced to qi_refining_1")
	assert_eq(str(gu_m1.get("dao_foundation_grade", "")), "solid", "Dao foundation recorded as solid")
	assert_eq(int(gu_m1.get("free_potential", -1)), 5, "+5 free potential on qi_refining_1 breakthrough")
	assert_eq(int(sheet1.get("lifespan_max", 0)), 120, "Qi Refining lifespan_max == 120")
	assert_gt(int(sheet1.get("max_hp", 0)), int(sheet0.get("max_hp", 0)), "Qi Refining 1 raises max_hp")
	assert_eq(int(gu_m1.get("hp", 0)), int(sheet1.get("max_hp", 0)), "Breakthrough full-restores HP")
	assert_eq(int(gu_m1.get("mp", 0)), int(sheet1.get("max_mp", 0)), "Breakthrough full-restores MP")
	var tal1: Array = as_arr(gu_m1.get("unlocked_talents", []))
	assert_eq(tal1.size(), 2, "Qi Refining 1 unlocks 2 talent tiers")
	assert_true(tal1.has("nd_gu_a2"), "Tier 2 node nd_gu_a2 unlocked")

	gu_m1["hp"] = 40
	gu_m1["mp"] = 10
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_2", "flawless")

	var gu_m2: Dictionary = _get_member_dict("gu_changqing")
	var sheet2: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(str(gu_m2.get("realm_id", "")), "qi_refining_2", "Advanced to qi_refining_2")
	assert_eq(str(gu_m2.get("dao_foundation_grade", "")), "flawless", "Dao foundation updated to flawless")
	assert_eq(int(gu_m2.get("free_potential", -1)), 10, "Cumulative free_potential == 10")
	assert_eq(int(sheet2.get("lifespan_max", 0)), 120, "Qi Refining 2 lifespan_max == 120")
	assert_gt(int(sheet2.get("max_hp", 0)), int(sheet1.get("max_hp", 0)), "Qi Refining 2 raises max_hp further")
	assert_eq(int(gu_m2.get("hp", 0)), int(sheet2.get("max_hp", 0)), "Qi Refining 2 full-restores HP")
	var tal2: Array = as_arr(gu_m2.get("unlocked_talents", []))
	assert_eq(tal2.size(), 3, "Qi Refining 2 unlocks all 3 Ch1 specialization tiers")
	assert_true(tal2.has("nd_gu_a3"), "Tier 3 node nd_gu_a3 unlocked")


func case_t1_f08_02_potentials_and_respec() -> void:
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "solid")
	var gu_m: Dictionary = _get_member_dict("gu_changqing")
	assert_eq(int(gu_m.get("free_potential", 0)), 5, "5 free potential points available")
	var base_sheet: Dictionary = _get_member_sheet("gu_changqing").duplicate(true)

	var dew_before: int = CampaignState.get_item_count("item_marrow_dew")
	CampaignState.add_item("item_marrow_dew", 1, true)
	assert_eq(CampaignState.get_item_count("item_marrow_dew"), dew_before + 1, "Added 1 item_marrow_dew")

	assert_true(CampaignState.allocate_potential_point("gu_changqing", "con", 1), "Allocate +1 con")
	var sh_con: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(int(sh_con.get("max_hp", 0)) - int(base_sheet.get("max_hp", 0)), 12, "+1 con -> +12 max_hp")

	assert_true(CampaignState.allocate_potential_point("gu_changqing", "spi", 1), "Allocate +1 spi")
	var sh_spi: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(int(sh_spi.get("max_mp", 0)) - int(sh_con.get("max_mp", 0)), 8, "+1 spi -> +8 max_mp")
	assert_approx(float(sh_spi.get("spell_power", 0.0)) - float(sh_con.get("spell_power", 0.0)), 1.5, 0.05, "+1 spi -> +1.5 spell_power")
	assert_approx(float(sh_spi.get("heal_power", 0.0)) - float(sh_con.get("heal_power", 0.0)), 0.8, 0.05, "+1 spi -> +0.8 heal_power")

	assert_true(CampaignState.allocate_potential_point("gu_changqing", "str", 1), "Allocate +1 str")
	var sh_str: Dictionary = _get_member_sheet("gu_changqing")
	assert_approx(float(sh_str.get("phys_power", 0.0)) - float(sh_spi.get("phys_power", 0.0)), 1.6, 0.05, "+1 str -> +1.6 phys_power")

	assert_true(CampaignState.allocate_potential_point("gu_changqing", "end", 1), "Allocate +1 end")
	var sh_end: Dictionary = _get_member_sheet("gu_changqing")
	assert_approx(float(sh_end.get("defense", 0.0)) - float(sh_str.get("defense", 0.0)), 2.2, 0.05, "+1 end -> +2.2 defense")

	assert_true(CampaignState.allocate_potential_point("gu_changqing", "agi", 1), "Allocate +1 agi")
	var sh_agi: Dictionary = _get_member_sheet("gu_changqing")
	assert_approx(float(sh_agi.get("crit_rating", 0.0)) - float(sh_end.get("crit_rating", 0.0)), 1.2, 0.05, "+1 agi -> +1.2 crit_rating")
	assert_gt(float(sh_agi.get("move_speed_px", 0.0)), float(sh_end.get("move_speed_px", 0.0)), "+1 agi raises move_speed_px")
	assert_eq(int(_get_member_dict("gu_changqing").get("free_potential", -1)), 0, "All 5 potential points spent")

	var did_reset: bool = CampaignState.reset_potential_points("gu_changqing")
	assert_true(did_reset, "reset_potential_points succeeds with item_marrow_dew")
	assert_eq(CampaignState.get_item_count("item_marrow_dew"), dew_before, "Consumed exactly 1 item_marrow_dew")

	var after_m: Dictionary = _get_member_dict("gu_changqing")
	assert_eq(int(after_m.get("free_potential", -1)), 5, "Refunded 100% of 5 potential points")
	var alloc_after: Dictionary = as_dict(after_m.get("allocated_potential", {}))
	for sk: String in ["con", "spi", "str", "end", "agi"]:
		assert_eq(int(alloc_after.get(sk, -1)), 0, "Allocated '%s' reset to 0" % sk)

	var reset_sheet: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(int(reset_sheet.get("max_hp", 0)), int(base_sheet.get("max_hp", 0)), "Post-reset max_hp matches pre-allocation")
	assert_approx(float(reset_sheet.get("phys_power", 0.0)), float(base_sheet.get("phys_power", 0.0)), 0.01, "Post-reset phys_power matches")
	assert_approx(float(reset_sheet.get("crit_rating", 0.0)), float(base_sheet.get("crit_rating", 0.0)), 0.01, "Post-reset crit_rating matches")


func case_t1_f08_03_hyperbolic_ratings_and_ledger() -> void:
	var ks: Array[float] = [20.0, 30.0, 42.0, 75.0]
	for i: int in range(ks.size() - 1):
		var k_lo: float = ks[i]
		var k_hi: float = ks[i + 1]
		assert_gt(StatLedger.convert_crit_rating(40.0, k_lo), StatLedger.convert_crit_rating(40.0, k_hi), "Crit rating diminishes at higher k_realm")
		assert_gt(StatLedger.convert_haste_rating(40.0, k_lo), StatLedger.convert_haste_rating(40.0, k_hi), "Haste rating diminishes at higher k_realm")
		assert_gt(StatLedger.convert_mastery_rating(40.0, k_lo), StatLedger.convert_mastery_rating(40.0, k_hi), "Mastery rating diminishes at higher k_realm")
		assert_gt(StatLedger.convert_versatility_rating(40.0, k_lo), StatLedger.convert_versatility_rating(40.0, k_hi), "Versatility rating diminishes at higher k_realm")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.open_tab("cultivation")
	await step_frames(3)

	var sh: Dictionary = _get_member_sheet("gu_changqing")
	var all_txt: String = _join_visible_label_texts(casket)
	var exp_crit: String = "%.1f%%" % (float(sh.get("crit_pct", 0.05)) * 100.0)
	var exp_haste: String = "%.1f%%" % (float(sh.get("haste_pct", 0.0)) * 100.0)
	var exp_gcd: String = "%.2fs" % float(sh.get("gcd_sec", 1.50))
	var exp_mast: String = "%.1f%%" % (float(sh.get("mastery_pct", 0.0)) * 100.0)
	var exp_mit: String = "%.1f%%" % (float(sh.get("mitigation_pct", 0.0)) * 100.0)

	assert_str_contains(all_txt, exp_crit, "Ledger shows exact post-diminishing crit_pct")
	assert_str_contains(all_txt, exp_haste, "Ledger shows exact post-diminishing haste_pct")
	assert_str_contains(all_txt, exp_gcd, "Ledger shows exact post-haste gcd_sec")
	assert_str_contains(all_txt, exp_mast, "Ledger shows exact post-diminishing mastery_pct")
	assert_str_contains(all_txt, exp_mit, "Ledger shows exact mitigation_pct")


func case_t1_f08_04_flawless_foundation_bonus() -> void:
	var g_flawless: Dictionary = StatLedger.evaluate_breakthrough_grade(true, true, 2, true, false)
	var g_solid: Dictionary = StatLedger.evaluate_breakthrough_grade(true, false, 1, true, false)
	var g_saved: Dictionary = StatLedger.evaluate_breakthrough_grade(true, true, 3, true, true)
	var g_fail: Dictionary = StatLedger.evaluate_breakthrough_grade(true, true, 3, false, false)

	assert_eq(str(g_flawless.get("grade", "")), "flawless", "Pill + charm + bond>=2 + no save -> flawless")
	assert_eq(int(g_flawless.get("lifespan_cost", -1)), 0, "Flawless costs 0 lifespan")
	assert_eq(str(g_flawless.get("title_key", "")), "UI_BREAKTHROUGH_FLAWLESS", "Flawless title_key")
	assert_eq(str(g_solid.get("grade", "")), "solid", "Pill without aux charm -> solid")
	assert_eq(str(g_saved.get("grade", "")), "solid", "Used protector save downgrades flawless -> solid")
	assert_false(bool(g_fail.get("success", true)), "Trial defeat -> breakthrough failed")

	var cdef: Dictionary = DataDB.get_character("gu_changqing")
	var rdef: Dictionary = DataDB.get_realm("qi_refining_2")
	var alloc: Dictionary = {"con": 4, "spi": 4, "str": 4, "end": 4, "agi": 4}
	var sh_solid: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, alloc, "solid", [], DataDB.equip_sets, {}, {}, {}, {}, 0, 0
	)
	var sh_flaw: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, alloc, "flawless", [], DataDB.equip_sets, {}, {}, {}, {}, 0, 0
	)

	var five_s: Dictionary = as_dict(sh_solid.get("five_stats", {}))
	var five_f: Dictionary = as_dict(sh_flaw.get("five_stats", {}))
	for sk: String in ["con", "spi", "str", "end", "agi"]:
		var vs: float = float(five_s.get(sk, 1))
		var vf: float = float(five_f.get(sk, 1))
		assert_gt(vf, vs, "Flawless '%s' > Solid '%s'" % [sk, sk])
		assert_approx(vf / vs, 1.08, 0.045, "Flawless '%s' scales ~1.08x over Solid" % sk)

	assert_gt(int(sh_flaw.get("max_hp", 0)), int(sh_solid.get("max_hp", 0)), "Flawless increases max_hp")
	assert_gt(float(sh_flaw.get("phys_power", 0.0)), float(sh_solid.get("phys_power", 0.0)), "Flawless increases phys_power")
	assert_gt(float(sh_flaw.get("spell_power", 0.0)), float(sh_solid.get("spell_power", 0.0)), "Flawless increases spell_power")


func case_t1_f08_05_r3_ink_meridian_figure() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.open_tab("cultivation")
	var img: Image = await capture_1080p_frame(18)

	var left_ctrls: Array[Control] = _collect_visible_controls_in_x_band(casket, 80.0, 690.0)
	var has_meridian_graphic: bool = false
	for ctrl: Control in left_ctrls:
		if ctrl is TextureRect:
			var tr_node: TextureRect = ctrl as TextureRect
			if tr_node.texture != null and tr_node.size.x >= 160.0 and tr_node.size.y >= 220.0:
				has_meridian_graphic = true
				break
		elif ctrl is NinePatchRect:
			var np_node: NinePatchRect = ctrl as NinePatchRect
			if np_node.texture != null and np_node.size.x >= 160.0 and np_node.size.y >= 220.0:
				has_meridian_graphic = true
				break
		elif ctrl.get_script() != null and not (ctrl is Label) and not (ctrl is Button):
			if ctrl.size.x >= 160.0 and ctrl.size.y >= 220.0 and obj_has_method(ctrl, "_draw"):
				has_meridian_graphic = true
				break

	var jade_acupoint_px: int = 0
	for y: int in range(215, 760, 4):
		for x: int in range(180, 560, 4):
			var c: Color = img.get_pixel(x, y)
			if c.g > 0.40 and c.g > c.r + 0.045 and c.g >= c.b - 0.04:
				jade_acupoint_px += 1

	var left_page_stats: Dictionary = sample_image_roi_stats(img, Rect2i(160, 240, 140, 140))
	record_metric("meridian_graphic_found", has_meridian_graphic)
	record_metric("jade_acupoint_sampled_px", jade_acupoint_px)
	record_metric("left_page_mean_luma", snappedf(float(left_page_stats.get("mean_luma", 0.0)), 0.001))

	assert_true(
		has_meridian_graphic,
		"Polish R3 Tab 1 left page (x<690) must render a classical brush-ink human meridian figure (TextureRect or custom _draw Control >=160x220, not plain Labels)"
	)
	assert_gt(
		float(left_page_stats.get("mean_luma", 0.0)),
		0.50,
		"Polish R3 left meridian page rests on warm aged Xuan paper (mean_luma > 0.50, not dark ebony box)"
	)
	assert_ge(
		jade_acupoint_px,
		24,
		"Polish R3 meridian figure renders glowing celadon-jade acupoints along central axis (master_d)"
	)


func case_t1_f09_01_five_slot_equip_swap() -> void:
	var sh_before: Dictionary = _get_member_sheet("gu_changqing").duplicate(true)
	assert_approx(float(sh_before.get("attack_range_px", 0.0)), 135.0, 0.5, "Starter iron sword attack_range_px == 135")

	CampaignState.add_item("eq_ancient_wood_blade", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)

	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_ancient_wood_blade"), "Equip eq_ancient_wood_blade")
	assert_eq(CampaignState.get_item_count("eq_qinglan_iron_sword"), 1, "Previous weapon eq_qinglan_iron_sword returned to inventory")
	assert_eq(CampaignState.get_item_count("eq_ancient_wood_blade"), 0, "Equipped weapon removed from bag")

	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_poxue"), "Equip eq_pendant_poxue")
	var sh_after: Dictionary = _get_member_sheet("gu_changqing")
	assert_approx(float(sh_after.get("attack_range_px", 0.0)), 260.0, 0.5, "Ancient wood blade raises attack_range_px to 260")
	assert_lt(float(sh_after.get("attack_interval", 9.0)), float(sh_before.get("attack_interval", 0.0)), "Faster weapon lowers attack_interval")
	assert_gt(float(sh_after.get("phys_power", 0.0)), float(sh_before.get("phys_power", 0.0)), "phys_power increased")
	assert_gt(float(sh_after.get("spell_power", 0.0)), float(sh_before.get("spell_power", 0.0)), "spell_power increased")
	assert_gt(float(sh_after.get("mastery_rating", 0.0)), float(sh_before.get("mastery_rating", 0.0)), "mastery_rating increased")
	assert_gt(float(sh_after.get("crit_rating", 0.0)), float(sh_before.get("crit_rating", 0.0)), "crit_rating increased")


func case_t1_f09_02_sect_set_bonuses() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)

	var gu_3pc: Dictionary = _get_member_sheet("gu_changqing")
	var shen_3pc: Dictionary = _get_member_sheet("shen_qinghe")
	var pei_3pc: Dictionary = _get_member_sheet("pei_zhao")

	assert_true(as_arr(gu_3pc.get("active_set_effects", [])).has("synergy_restore_mp_8"), "Gu 3/3 set_qinglan_walker activates synergy_restore_mp_8")
	assert_true(as_arr(shen_3pc.get("active_set_effects", [])).has("overheal_wood_shield_50"), "Shen 3/3 set_yaolu_longevity activates overheal_wood_shield_50")
	assert_true(as_arr(pei_3pc.get("active_set_effects", [])).has("interrupt_ward_buff_20"), "Pei 3/3 set_qingyun_swift activates interrupt_ward_buff_20")

	# Swap Gu's weapon to non-qinglan blade -> drops to 2/3 set_qinglan_walker
	CampaignState.add_item("eq_qingyun_frost_blade", 1, true)
	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_qingyun_frost_blade"), "Swap Gu weapon to break 3pc")
	var gu_2pc: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(int(as_dict(gu_2pc.get("set_counts", {})).get("set_qinglan_walker", 0)), 2, "Gu now at 2/3 set_qinglan_walker")
	assert_false(as_arr(gu_2pc.get("active_set_effects", [])).has("synergy_restore_mp_8"), "3pc effect deactivated at 2/3")

	# Swap Gu's robe to non-qinglan robe -> drops to 1/3 set_qinglan_walker (loses 2pc haste +10 & hp +18)
	var haste_2pc: float = float(gu_2pc.get("haste_rating", 0.0))
	CampaignState.add_item("eq_qingyun_cloud_robe", 1, true)
	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_qingyun_cloud_robe"), "Swap Gu robe to break 2pc")
	var gu_1pc: Dictionary = _get_member_sheet("gu_changqing")
	assert_eq(int(as_dict(gu_1pc.get("set_counts", {})).get("set_qinglan_walker", 0)), 1, "Gu now at 1/3 set_qinglan_walker")
	assert_approx(haste_2pc - float(gu_1pc.get("haste_rating", 0.0)), 10.0, 0.05, "Breaking 2pc set_qinglan_walker removes +10 haste_rating")


func case_t1_f09_03_blue_stunts_and_natal_treasure() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)

	assert_true(CampaignState.equip_item_on_member("shen_qinghe", "eq_pendant_jingqing"), "Shen equips eq_pendant_jingqing")
	assert_true(CampaignState.equip_item_on_member("pei_zhao", "eq_pendant_poxue"), "Pei equips eq_pendant_poxue")

	var shen_stunts: Array = as_arr(_get_member_sheet("shen_qinghe").get("blue_stunt_ids", []))
	var pei_stunts: Array = as_arr(_get_member_sheet("pei_zhao").get("blue_stunt_ids", []))
	assert_eq(shen_stunts, ["stunt_jingqing_jade"], "Shen gains stunt_jingqing_jade (晶清玉露)")
	assert_eq(pei_stunts, ["stunt_poxue_assault"], "Pei gains stunt_poxue_assault (破血狂攻)")

	var sk_jq: Dictionary = DataDB.get_skill("stunt_jingqing_jade")
	var sk_px: Dictionary = DataDB.get_skill("stunt_poxue_assault")
	assert_approx(float(sk_jq.get("attunement_cost", 0.0)), 55.0, 0.1, "晶清玉露 costs 55 attunement Qi")
	assert_approx(float(sk_px.get("attunement_cost", 0.0)), 40.0, 0.1, "破血狂攻 costs 40 attunement Qi")

	var gu_bar: Dictionary = CampaignState.get_member_active_skills("gu_changqing")
	assert_eq(str(gu_bar.get("R", "")), "sk_gu_sword_box_burst", "Gu Natal Treasure 断玉剑匣 maps slot R to sk_gu_sword_box_burst")
	var shen_bar: Dictionary = CampaignState.get_member_active_skills("shen_qinghe")
	assert_eq(str(shen_bar.get("R", "")), "sk_shen_herb_field", "Shen Natal Treasure 青囊药匣 maps slot R to sk_shen_herb_field")
	var pei_bar: Dictionary = CampaignState.get_member_active_skills("pei_zhao")
	assert_eq(str(pei_bar.get("R", "")), "sk_pei_starfall_sword", "Pei Natal Treasure 惊鸿剑穗 maps slot R to sk_pei_starfall_sword")


func case_t1_f09_04_r3_embossed_slots_and_bars() -> void:
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_jingqing")
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")
	CampaignState.allocate_potential_point("gu_changqing", "con", 2)
	CampaignState.allocate_potential_point("gu_changqing", "str", 1)

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.open_tab("cultivation")
	await step_frames(6)

	var mid_ctrls: Array[Control] = _collect_visible_controls_in_x_band(casket, 670.0, 1290.0)
	var icon_rects: Array[Control] = []
	var bar_gauges: int = 0

	for ctrl: Control in mid_ctrls:
		if ctrl is TextureRect:
			var tr_icon: TextureRect = ctrl as TextureRect
			if tr_icon.texture != null and tr_icon.size.x >= 44.0 and tr_icon.size.y >= 44.0 and tr_icon.size.x <= 240.0:
				icon_rects.append(tr_icon)
		elif ctrl is Range and not (ctrl is ScrollBar):
			bar_gauges += 1
		elif ctrl is ColorRect and ctrl.size.x >= 90.0 and ctrl.size.y >= 8.0 and ctrl.size.y <= 36.0:
			bar_gauges += 1
		elif ctrl.get_script() != null and not (ctrl is Label) and not (ctrl is Button):
			if ctrl.size.x >= 120.0 and ctrl.size.y >= 12.0 and ctrl.size.y <= 48.0 and obj_has_method(ctrl, "_draw"):
				bar_gauges += 1

	var top_row_icons: int = 0
	var bot_row_icons: int = 0
	if icon_rects.size() >= 5:
		var icon_ys: Array[float] = []
		for ic: Control in icon_rects:
			icon_ys.append(ic.global_position.y + ic.size.y * 0.5)
		icon_ys.sort()
		var band_anchors: Array[float] = []
		var band_counts: Array[int] = []
		for cy: float in icon_ys:
			var matched_band: int = -1
			for b_idx: int in range(band_anchors.size()):
				if absf(cy - band_anchors[b_idx]) <= 36.0:
					matched_band = b_idx
					break
			if matched_band >= 0:
				band_counts[matched_band] = band_counts[matched_band] + 1
			else:
				band_anchors.append(cy)
				band_counts.append(1)
		var top_band_idx: int = -1
		for b_idx2: int in range(band_counts.size()):
			if band_counts[b_idx2] >= 3:
				top_band_idx = b_idx2
				top_row_icons = band_counts[b_idx2]
				break
		if top_band_idx >= 0:
			for b_idx3: int in range(top_band_idx + 1, band_counts.size()):
				if band_counts[b_idx3] >= 2:
					bot_row_icons = band_counts[b_idx3]
					break

	record_metric("mid_col_icon_slots", icon_rects.size())
	record_metric("top_row_icons", top_row_icons)
	record_metric("bot_row_icons", bot_row_icons)
	record_metric("potential_bar_gauges", bar_gauges)

	assert_ge(
		icon_rects.size(),
		5,
		"Polish R3 Tab 1 middle page must render 5 embossed artifact icon slots with Texture2D icons (not text-only rows)"
	)
	assert_true(
		top_row_icons >= 3 and bot_row_icons >= 2,
		"Polish R3 artifact slots follow master_d 3+2 two-row layout (佩兵/法衣/履腕 top + 灵佩/本命法宝 bottom)"
	)
	assert_ge(
		bar_gauges,
		5,
		"Polish R3 Tab 1 middle page renders 5 bronze-framed potential progress bars alongside [+] buttons (master_d)"
	)


func case_t1_f09_05_r3_sky_blue_stunt_comparison() -> void:
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_jingqing")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.selected_item_id = "eq_pendant_poxue"
	casket.open_tab("cultivation")
	await step_frames(5)

	var target_sky: Color = Color("#8FD4E8")
	var theme_stunt: Color = UIThemeBuilder.COL_BLUE_STUNT
	var theme_matches_sky: bool = (
		absf(theme_stunt.r - target_sky.r) <= 0.08
		and absf(theme_stunt.g - target_sky.g) <= 0.08
		and absf(theme_stunt.b - target_sky.b) <= 0.08
	)

	var right_ctrls: Array[Control] = _collect_visible_controls_in_x_band(casket, 1255.0, 1880.0)
	var right_texts: PackedStringArray = PackedStringArray()
	var sky_blue_label_found: bool = theme_matches_sky
	for ctrl: Control in right_ctrls:
		if ctrl is Label:
			var lbl: Label = ctrl as Label
			right_texts.append(lbl.text)
			var fc: Color = lbl.get_theme_color("font_color", "Label")
			if absf(fc.r - target_sky.r) <= 0.09 and absf(fc.g - target_sky.g) <= 0.09 and absf(fc.b - target_sky.b) <= 0.09:
				sky_blue_label_found = true
		elif ctrl is RichTextLabel:
			right_texts.append((ctrl as RichTextLabel).get_parsed_text())

	var joined_right: String = "\n".join(right_texts)
	var eq_name_jq: String = DataDB.loc("EQ_PENDANT_JINGQING_NAME")
	var eq_name_px: String = DataDB.loc("EQ_PENDANT_POXUE_NAME")
	var has_side_by_side_in_tab1: bool = joined_right.contains(eq_name_jq) and joined_right.contains(eq_name_px)

	record_metric("col_blue_stunt_hex", theme_stunt.to_html(false))
	record_metric("tab1_right_side_by_side", has_side_by_side_in_tab1)

	assert_true(
		sky_blue_label_found,
		"Polish R3 blue-skill comparison highlight must use #8FD4E8 sky-blue (actual COL_BLUE_STUNT=#%s)" % theme_stunt.to_html(false)
	)
	assert_true(
		has_side_by_side_in_tab1,
		"Polish R3 Tab 1 right page lower half must render side-by-side equipped vs compared artifact comparison card (master_d)"
	)
