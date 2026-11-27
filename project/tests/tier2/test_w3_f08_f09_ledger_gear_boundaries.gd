extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 2
# @e2e_features: F8, F9


func register_cases() -> void:
	add_case("T2-F08-01", 2, "F8", "baseline", "45/35/20 3-bucket progression weighting & BUCKET_C_MAX_MULT == 1.28 hard clamp under extreme buffs", "case_t2_f08_01_three_bucket_clamp")
	add_case("T2-F08-02", 2, "F8", "baseline", "Hyperbolic rating caps/floors: 1.00s GCD floor, 0.35s cast floor, 0.30 DR floor & [-20%,+25%] move speed", "case_t2_f08_02_rating_caps_and_floors")
	add_case("T2-F08-03", 2, "F8", "baseline", "Pill-less 'cracked' breakthrough (-20 lifespan, 10 floor, -10% HP) & zero world exploration lifespan drain", "case_t2_f08_03_cracked_foundation_and_zero_drain")
	add_case("T2-F08-04", 2, "F8", "polish_r3", "Polish R3 'cracked' (裂脉强渡) Dao-foundation plaque label & pill-less breakthrough confirmation guard", "case_t2_f08_04_r3_cracked_plaque_and_confirm")
	add_case("T2-F08-05", 2, "F8", "baseline", "Invalid potential allocation rejection, zero-waste Marrow Dew guard & mid-combat spec-switch block", "case_t2_f08_05_potential_and_spec_guards")
	add_case("T2-F09-01", 2, "F9", "polish_r3", "Polish R3 empty pendant slot renders monochrome ink silhouette (0 legacy '（空置）' text-only rows)", "case_t2_f09_01_r3_empty_slot_ink_silhouette")
	add_case("T2-F09-02", 2, "F9", "baseline", "Cross-character Natal Treasure (断玉剑匣/青囊药匣/惊鸿剑穗) secrecy & allowed_characters hard block", "case_t2_f09_02_natal_treasure_secrecy_block")
	add_case("T2-F09-03", 2, "F9", "baseline", "Mid-combat equip block, disabled inventory equip buttons & unowned/consumable equip rejection", "case_t2_f09_03_mid_combat_and_invalid_equip_block")
	add_case("T2-F09-04", 2, "F9", "polish_r3", "Polish R3 signed +/- comparison deltas & #8FD4E8 sky-blue stunt name + description side-by-side card", "case_t2_f09_04_r3_signed_comparison_deltas")
	add_case("T2-F09-05", 2, "F9", "baseline", "Runtime DataDB.equipment & equip_sets FK/locale/icon integrity & shop Natal Treasure sell exclusion", "case_t2_f09_05_equipment_db_and_unsellable_treasures")


func _join_visible_texts(root_node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(root_node):
		out.append(lbl.text)
	return "\n".join(out)


func case_t2_f08_01_three_bucket_clamp() -> void:
	var cdef: Dictionary = DataDB.get_character("gu_changqing")
	var rdef: Dictionary = DataDB.get_realm("qi_refining_2")
	var alloc: Dictionary = {"con": 3, "spi": 2, "str": 3, "end": 1, "agi": 1}
	var full_gear: Array = [
		DataDB.get_equipment("eq_ancient_wood_blade"),
		DataDB.get_equipment("eq_qinglan_rain_robe"),
		DataDB.get_equipment("eq_qinglan_mist_boots"),
		DataDB.get_equipment("eq_pendant_poxue"),
		DataDB.get_equipment("tr_broken_jade_box_1"),
	]
	var fdef: Dictionary = DataDB.get_formation("tianfu")
	var slot_mod: Dictionary = FormationRules.get_slot_modifiers(fdef, 1)
	var elixir_def: Dictionary = DataDB.get_any_item_or_equip("item_juqi_pellet_flawless")

	var sh_std: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, alloc, "flawless", full_gear, DataDB.equip_sets,
		{}, slot_mod, {"damage_mult": 1.05, "damage_taken_mult": 0.95}, elixir_def, 0, 0
	)
	var bbreak: Dictionary = as_dict(sh_std.get("bucket_breakdown", {}))
	var ba_hp: int = int(bbreak.get("bucket_a_hp", 0))
	var bb_hp: int = int(bbreak.get("bucket_b_hp", 0))
	var bc_mult: float = float(bbreak.get("bucket_c_offense_mult", 0.0))

	assert_gt(float(ba_hp), float(bb_hp), "Bucket A (Realm+Potential) HP exceeds Bucket B (5-slot gear+sets) HP per 45:35 ratio")
	assert_gt(float(bb_hp), 60.0, "Bucket B gear+set HP contributes substantial ~35% tier")
	assert_approx(StatLedger.BUCKET_C_MAX_MULT, 1.28, 0.0001, "GDD 1.28 BUCKET_C_MAX_MULT constant")
	assert_le(bc_mult, 1.28, "Standard Bucket C multiplier <= 1.28")

	# Extreme stacked tactical multipliers -> hard clamp at BUCKET_C_MAX_MULT (1.28)
	var sh_extreme: Dictionary = StatLedger.compute_character_sheet(
		cdef,
		rdef,
		alloc,
		"flawless",
		full_gear,
		DataDB.equip_sets,
		{"damage_pct": 0.85, "heal_pct": 0.85},
		{"damage_mult": 2.50, "heal_mult": 2.50},
		{"damage_mult": 1.80, "damage_taken_mult": 0.90},
		{"power_pct": 0.95, "max_hp_pct": 0.20, "defense_pct": 0.20},
		0,
		0
	)
	var bbreak_ext: Dictionary = as_dict(sh_extreme.get("bucket_breakdown", {}))
	var bc_ext: float = float(bbreak_ext.get("bucket_c_offense_mult", 99.0))
	assert_approx(bc_ext, 1.28, 0.0001, "Extreme stacked tactical buffs hard-clamp at BUCKET_C_MAX_MULT == 1.28")


func case_t2_f08_02_rating_caps_and_floors() -> void:
	var cdef: Dictionary = DataDB.get_character("gu_changqing")
	var rdef: Dictionary = DataDB.get_realm("qi_refining_1")

	var huge_gear: Array = [{
		"slot": "weapon",
		"attack_interval": 0.30,
		"attack_range_px": 40.0,
		"stats": {
			"crit_rating": 100000.0,
			"haste_rating": 100000.0,
			"mastery_rating": 100000.0,
			"vers_rating": 100000.0,
			"defense": 100000.0,
			"move_speed_pct": 2.50,
		},
	}]
	var sh_cap: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, {}, "solid", huge_gear, {},
		{"flat_crit_pct": 0.40, "flat_haste_pct": 0.40},
		{"crit_bonus": 0.25, "haste_bonus": 0.25, "damage_taken_mult": 0.10},
		{}, {}, 0, 0
	)

	assert_approx(StatLedger.MIN_GCD_SEC, 1.00, 0.0001, "GDD 1.00s MIN_GCD_SEC constant")
	assert_approx(StatLedger.BASE_GCD_SEC, 1.50, 0.0001, "GDD 1.50s BASE_GCD_SEC constant")
	assert_approx(StatLedger.MAX_HASTE_PCT, 0.35, 0.0001, "GDD 0.35 MAX_HASTE_PCT constant")
	assert_approx(StatLedger.MIN_DAMAGE_TAKEN_MULT, 0.30, 0.0001, "GDD 0.30 MIN_DAMAGE_TAKEN_MULT constant")
	assert_approx(StatLedger.BASE_CRIT_PCT, 0.05, 0.0001, "GDD 0.05 BASE_CRIT_PCT constant")
	assert_approx(StatLedger.BASE_CRIT_MULT, 1.60, 0.0001, "GDD 1.60 BASE_CRIT_MULT constant")
	assert_approx(StatLedger.MAX_MOVE_SPEED_BONUS_PCT, 0.25, 0.0001, "GDD 0.25 MAX_MOVE_SPEED_BONUS_PCT constant")

	assert_le(float(sh_cap.get("crit_pct", 1.0)), 0.48, "crit_pct hard-capped at <= 0.48")
	assert_le(float(sh_cap.get("haste_pct", 1.0)), 0.35, "haste_pct hard-capped at MAX_HASTE_PCT (0.35)")
	assert_ge(float(sh_cap.get("gcd_sec", 0.0)), 1.00, "gcd_sec floored at MIN_GCD_SEC (1.00s)")
	assert_ge(float(sh_cap.get("attack_interval", 0.0)), 0.65, "attack_interval floored at 0.65s")
	assert_ge(float(sh_cap.get("attack_range_px", 0.0)), 90.0, "attack_range_px floored at 90px")
	assert_ge(float(sh_cap.get("damage_taken_mult", 0.0)), 0.30, "damage_taken_mult floored at 0.30 (<=70% mitigation)")
	assert_le(float(sh_cap.get("mitigation_pct", 1.0)), 0.70, "mitigation_pct <= 0.70")

	var base_mv: float = float(cdef.get("base_move_speed_px", 215.0))
	assert_approx(float(sh_cap.get("move_speed_px", 0.0)), base_mv * 1.25, 0.05, "move_speed_px bonus capped at +25%")

	var neg_gear: Array = [{
		"slot": "boots",
		"stats": {
			"crit_rating": -999.0,
			"haste_rating": -999.0,
			"mastery_rating": -999.0,
			"vers_rating": -999.0,
			"move_speed_pct": -0.95,
		},
	}]
	var sh_neg: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, {}, "solid", neg_gear, {}, {}, {}, {}, {}, 3, 2
	)
	assert_approx(float(sh_neg.get("crit_pct", 0.0)), 0.05, 0.001, "Negative crit_rating floors at BASE_CRIT_PCT (0.05)")
	assert_approx(float(sh_neg.get("haste_pct", -1.0)), 0.0, 0.001, "Negative haste_rating floors at 0.0")
	assert_ge(float(sh_neg.get("move_speed_px", 0.0)), 110.0, "Negative move_speed_pct + suppression floors >= 110.0px/s")
	assert_ge(StatLedger.compute_actual_cast_time(0.40, 0.99), 0.35, "Cast time floored at 0.35s")
	assert_eq(StatLedger.compute_actual_cast_time(0.0, 0.35), 0.0, "Instant cast stays 0.0s")


func case_t2_f08_03_cracked_foundation_and_zero_drain() -> void:
	var g_cracked: Dictionary = StatLedger.evaluate_breakthrough_grade(false, false, 0, true, false)
	assert_true(bool(g_cracked.get("success", false)), "Pill-less trial victory succeeds as cracked")
	assert_eq(str(g_cracked.get("grade", "")), "cracked", "Grade == 'cracked'")
	assert_eq(int(g_cracked.get("lifespan_cost", 0)), 20, "Cracked breakthrough lifespan_cost == 20")
	assert_eq(str(g_cracked.get("title_key", "")), "UI_BREAKTHROUGH_CRACKED", "Title key UI_BREAKTHROUGH_CRACKED")

	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "solid")
	var hp_solid: int = int(as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("sheet", {})).get("max_hp", 0))

	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "cracked")
	var sh_cracked: Dictionary = as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("sheet", {}))
	var hp_cracked: int = int(sh_cracked.get("max_hp", 0))
	assert_eq(int(sh_cracked.get("lifespan_max", 0)), 100, "Qi Refining 1 cracked reduces lifespan_max 120 -> 100")
	assert_approx(float(hp_cracked) / float(maxi(1, hp_solid)), 0.90, 0.02, "Cracked foundation applies -10% max_hp imprint")

	# Low-lifespan floor check (20 - 20 -> floored at 10)
	var sh_floor: Dictionary = StatLedger.compute_character_sheet(
		DataDB.get_character("gu_changqing"),
		{"k_realm": 20.0, "sub_realm_total_index": 0, "lifespan_max": 20},
		{}, "cracked", [], {}, {}, {}, {}, {}, 0, 0
	)
	assert_eq(int(sh_floor.get("lifespan_max", 0)), 10, "Cracked lifespan_max floors at 10 (never <= 0)")

	# Step 600s of world exploration -> 0 lifespan drain
	var play_before: float = CampaignState.playtime_sec
	for _i: int in range(10):
		CampaignState._process(60.0)
	CampaignState.recalculate_all_party_stats(false)
	var sh_after_explore: Dictionary = as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("sheet", {}))
	assert_approx(CampaignState.playtime_sec - play_before, 600.0, 0.1, "Simulated 600s exploration playtime")
	assert_eq(int(sh_after_explore.get("lifespan_max", 0)), 100, "600s world exploration drains 0 lifespan")


func case_t2_f08_04_r3_cracked_plaque_and_confirm() -> void:
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "cracked")
	assert_eq(CampaignState.get_item_count("item_ningqi_vein_pill"), 0, "0 breakthrough pills in inventory")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.open_tab("cultivation")
	await step_frames(4)

	var all_txt: String = _join_visible_texts(casket)
	var shows_cracked_label: bool = (
		all_txt.contains("裂脉")
		or all_txt.contains("有瑕")
		or all_txt.contains(tr("UI_BREAKTHROUGH_CRACKED"))
	)
	var falsely_shows_solid: bool = all_txt.contains("地道稳固道基")

	var has_breakthrough_guard_ui: bool = (
		obj_has_method(casket, "request_breakthrough")
		or obj_has_method(casket, "open_breakthrough_confirm")
	)
	if not has_breakthrough_guard_ui:
		for btn: Button in collect_visible_buttons(casket):
			if btn.text.contains("破境") or btn.text.contains("冲关") or btn.text.contains("突破") or btn.text.contains("渡劫"):
				has_breakthrough_guard_ui = true
				break

	record_metric("shows_cracked_label", shows_cracked_label)
	record_metric("falsely_shows_solid", falsely_shows_solid)
	record_metric("has_breakthrough_guard_ui", has_breakthrough_guard_ui)

	assert_true(
		shows_cracked_label and not falsely_shows_solid,
		"Polish R3 Tab 1 Dao-foundation plaque must label 'cracked' as 裂脉强渡 / 有瑕道基 (-20 寿元), never '地道稳固道基'"
	)
	assert_true(
		has_breakthrough_guard_ui,
		"Polish R3 Tab 1 must expose breakthrough entry with mandatory secondary confirmation before pill-less 裂脉强渡"
	)


func case_t2_f08_05_potential_and_spec_guards() -> void:
	# 0 free_potential -> cannot allocate
	assert_false(CampaignState.allocate_potential_point("gu_changqing", "con", 1), "Rejects allocation when free_potential == 0")

	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "solid")
	assert_false(CampaignState.allocate_potential_point("gu_changqing", "con", 0), "Rejects delta_pts == 0")
	assert_false(CampaignState.allocate_potential_point("gu_changqing", "con", -2), "Rejects negative delta_pts")
	assert_false(CampaignState.allocate_potential_point("gu_changqing", "nonexistent_stat", 1), "Rejects invalid stat key")
	assert_false(CampaignState.allocate_potential_point("unknown_hero", "con", 1), "Rejects unknown character")
	assert_false(CampaignState.allocate_potential_point("gu_changqing", "con", 99), "Rejects delta_pts > free_potential")

	# Reset with 0 Marrow Dew -> false
	CampaignState.allocate_potential_point("gu_changqing", "str", 2)
	while CampaignState.get_item_count("item_marrow_dew") > 0:
		CampaignState.remove_item("item_marrow_dew", 1)
	assert_false(CampaignState.reset_potential_points("gu_changqing"), "Rejects reset without item_marrow_dew")

	# Reset with 1 Marrow Dew -> succeeds once, then second reset with 0 allocated points MUST NOT waste a 2nd Marrow Dew!
	CampaignState.add_item("item_marrow_dew", 2, true)
	assert_true(CampaignState.reset_potential_points("gu_changqing"), "First reset succeeds")
	assert_eq(CampaignState.get_item_count("item_marrow_dew"), 1, "1 item_marrow_dew remaining")
	assert_false(CampaignState.reset_potential_points("gu_changqing"), "Reset rejected when allocated_potential is already all 0")
	assert_eq(CampaignState.get_item_count("item_marrow_dew"), 1, "item_marrow_dew NOT wasted when 0 points allocated")

	# Specialization switching: allowed OOC, blocked mid-combat
	assert_true(CampaignState.switch_specialization("gu_changqing", "spec_b"), "Switch to spec_b out of combat")
	assert_false(CampaignState.switch_specialization("gu_changqing", "spec_invalid"), "Rejects invalid spec key")

	NotifyHub.set_combat_active(true)
	assert_false(CampaignState.switch_specialization("gu_changqing", "spec_a"), "Mid-combat spec switch blocked")
	assert_eq(str(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("active_spec", "")), "spec_b", "Active spec unchanged during combat")
	NotifyHub.set_combat_active(false)


func case_t2_f09_01_r3_empty_slot_ink_silhouette() -> void:
	var gu_eq: Dictionary = as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("equipped", {}))
	assert_eq(str(gu_eq.get("pendant", "")), "", "Gu starts with empty pendant slot")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.open_tab("cultivation")
	await step_frames(5)

	var all_txt: String = _join_visible_texts(casket)
	var has_legacy_empty_text: bool = all_txt.contains("④ 灵佩：（空置）")

	var slot_visuals: int = 0
	var stack: Array[Node] = [casket]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Control and (cur as Control).is_visible_in_tree():
			var c: Control = cur as Control
			var cx: float = c.global_position.x + c.size.x * 0.5
			if cx >= 670.0 and cx <= 1290.0:
				if c is TextureRect and (c as TextureRect).texture != null and c.size.x >= 44.0 and c.size.y >= 44.0 and c.size.x <= 240.0:
					slot_visuals += 1
				elif c.get_script() != null and not (c is Label) and not (c is Button) and c.size.x >= 56.0 and c.size.y >= 56.0 and c.size.x <= 220.0 and obj_has_method(c, "_draw"):
					slot_visuals += 1
		for ch: Node in cur.get_children():
			stack.append(ch)

	record_metric("has_legacy_empty_text", has_legacy_empty_text)
	record_metric("mid_col_slot_visuals_with_empty", slot_visuals)

	assert_false(has_legacy_empty_text, "Polish R3 replaces legacy '④ 灵佩：（空置）' text row with embossed icon slot")
	assert_ge(slot_visuals, 5, "All 5 embossed artifact slots render visual icons/monochrome ink silhouettes even when pendant is empty")


func case_t2_f09_02_natal_treasure_secrecy_block() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)

	CampaignState.add_item("tr_broken_jade_box_1", 1, true)
	CampaignState.add_item("tr_qingnang_box", 1, true)
	CampaignState.add_item("tr_jinghong_tassel", 1, true)

	assert_false(CampaignState.equip_item_on_member("shen_qinghe", "tr_broken_jade_box_1"), "Shen cannot equip Gu's 断玉剑匣")
	assert_false(CampaignState.equip_item_on_member("pei_zhao", "tr_broken_jade_box_1"), "Pei cannot equip Gu's 断玉剑匣")
	assert_false(CampaignState.equip_item_on_member("gu_changqing", "tr_qingnang_box"), "Gu cannot equip Shen's 青囊药匣")
	assert_false(CampaignState.equip_item_on_member("shen_qinghe", "tr_jinghong_tassel"), "Shen cannot equip Pei's 惊鸿剑穗")

	assert_eq(str(as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("equipped", {})).get("treasure", "")), "tr_broken_jade_box_1", "Gu keeps tr_broken_jade_box_1")
	assert_eq(str(as_dict(as_dict(CampaignState.party_members.get("shen_qinghe", {})).get("equipped", {})).get("treasure", "")), "tr_qingnang_box", "Shen keeps tr_qingnang_box")
	assert_eq(str(as_dict(as_dict(CampaignState.party_members.get("pei_zhao", {})).get("equipped", {})).get("treasure", "")), "tr_jinghong_tassel", "Pei keeps tr_jinghong_tassel")
	assert_eq(CampaignState.get_item_count("tr_broken_jade_box_1"), 1, "Rejected treasure stays untouched in inventory")


func case_t2_f09_03_mid_combat_and_invalid_equip_block() -> void:
	CampaignState.add_item("eq_ancient_wood_blade", 1, true)
	CampaignState.add_item("item_huichun_powder", 2, true)

	NotifyHub.set_combat_active(true)
	assert_false(CampaignState.equip_item_on_member("gu_changqing", "eq_ancient_wood_blade"), "Mid-combat equip_item_on_member blocked")
	assert_eq(CampaignState.get_item_count("eq_ancient_wood_blade"), 1, "Blocked weapon stays in inventory")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.selected_item_id = "eq_ancient_wood_blade"
	casket.open_tab("inventory")
	await step_frames(3)

	var wear_btns: int = 0
	for btn: Button in collect_visible_buttons(casket):
		if btn.text.contains("穿戴"):
			wear_btns += 1
			assert_true(btn.disabled, "Inventory wear button disabled during combat")
	assert_ge(wear_btns, 1, "Found wear button in inventory tab")

	NotifyHub.set_combat_active(false)
	assert_false(CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_poxue"), "Cannot equip unowned equipment (count == 0)")
	assert_false(CampaignState.equip_item_on_member("gu_changqing", "item_huichun_powder"), "Cannot equip non-equipment consumable")


func case_t2_f09_04_r3_signed_comparison_deltas() -> void:
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_jingqing"), "Equip eq_pendant_jingqing (hp:24)")

	var casket: DaoCasketPanel = DaoCasketPanel.new()
	mount_node(casket)
	await step_frames(2)
	casket.selected_item_id = "eq_pendant_poxue"
	casket.open_tab("inventory")
	await step_frames(4)

	var inv_txt: String = _join_visible_texts(casket)
	assert_str_contains(inv_txt, "-4", "Comparing eq_pendant_poxue (hp:20) vs eq_pendant_jingqing (hp:24) shows signed -4 delta")
	assert_str_contains(inv_txt, "+6", "Comparing eq_pendant_poxue (phys:6) vs eq_pendant_jingqing (phys:0) shows signed +6 delta")

	var poxue_desc: String = DataDB.loc("STUNT_POXUE_DESC")
	var target_sky: Color = Color("#8FD4E8")
	var theme_stunt: Color = UIThemeBuilder.COL_BLUE_STUNT
	var sky_ok: bool = (
		absf(theme_stunt.r - target_sky.r) <= 0.08
		and absf(theme_stunt.g - target_sky.g) <= 0.08
		and absf(theme_stunt.b - target_sky.b) <= 0.08
	)
	var shows_stunt_desc: bool = inv_txt.contains(poxue_desc.left(10))

	casket.open_tab("cultivation")
	await step_frames(4)
	var cult_txt: String = _join_visible_texts(casket)
	if cult_txt.contains(poxue_desc.left(10)):
		shows_stunt_desc = true

	record_metric("sky_blue_ok", sky_ok)
	record_metric("shows_stunt_desc", shows_stunt_desc)

	assert_true(sky_ok, "Polish R3 stunt highlight color uses #8FD4E8 sky-blue")
	assert_true(
		shows_stunt_desc,
		"Polish R3 side-by-side comparison card renders localized blue-stunt description ('%s...') without truncation/key leak" % poxue_desc.left(12)
	)


func case_t2_f09_05_equipment_db_and_unsellable_treasures() -> void:
	assert_ge(DataDB.equipment.size(), 15, "DataDB.equipment loaded >= 15 artifacts")
	assert_ge(DataDB.equip_sets.size(), 3, "DataDB.equip_sets loaded >= 3 sets")

	var canonical_slots: Array[String] = ["weapon", "robe", "boots", "pendant", "treasure"]
	assert_eq(StatLedger.EQUIP_SLOTS, canonical_slots, "GDD 5-slot EQUIP_SLOTS contract")
	for eid_var: Variant in DataDB.equipment.keys():
		var eid: String = str(eid_var)
		var edef: Dictionary = DataDB.get_equipment(eid)
		var slot: String = str(edef.get("slot", ""))
		assert_true(canonical_slots.has(slot), "Equipment '%s' has valid slot '%s'" % [eid, slot])

		var nk: String = str(edef.get("name_key", ""))
		var dk: String = str(edef.get("desc_key", ""))
		assert_ne(tr(nk), nk, "Equipment '%s' name_key '%s' localized" % [eid, nk])
		assert_ne(tr(dk), dk, "Equipment '%s' desc_key '%s' localized" % [eid, dk])

		var icon_tex: Texture2D = load_tex(str(edef.get("icon", "")))
		assert_not_null(icon_tex, "Equipment '%s' icon loads as Texture2D" % eid)

		var b_stunt: String = str(edef.get("blue_stunt_id", ""))
		if b_stunt != "":
			assert_false(DataDB.get_skill(b_stunt).is_empty(), "Blue stunt '%s' exists in DataDB.skills" % b_stunt)
		var tr_sk: String = str(edef.get("treasure_skill_id", ""))
		if tr_sk != "":
			assert_false(DataDB.get_skill(tr_sk).is_empty(), "Treasure skill '%s' exists in DataDB.skills" % tr_sk)

	# Verify Natal Treasures in inventory NEVER appear in shop sell rows
	CampaignState.add_item("tr_broken_jade_box_1", 1, true)
	CampaignState.add_item("tr_qingnang_box", 1, true)
	CampaignState.add_item("tr_jinghong_tassel", 1, true)

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)

	var shop_txt: String = _join_visible_texts(modals)
	assert_str_not_contains(shop_txt, DataDB.loc("TR_BROKEN_JADE_BOX_NAME"), "断玉剑匣 never listed for sale in shop")
	assert_str_not_contains(shop_txt, DataDB.loc("TR_QINGNANG_BOX_NAME"), "青囊药匣 never listed for sale in shop")
	assert_str_not_contains(shop_txt, DataDB.loc("TR_JINGHONG_TASSEL_NAME"), "惊鸿剑穗 never listed for sale in shop")
