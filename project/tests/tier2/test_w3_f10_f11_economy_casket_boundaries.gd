extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 2
# @e2e_features: F10, F11


func register_cases() -> void:
	add_case("T2-F10-01", 2, "F10", "baseline", "Sell <= floor(Buy * 0.35) cap & 100% EconomyRules.is_recipe_arbitrage_safe (+ tampered counter-proof)", "case_t2_f10_01_sell_cap_and_zero_arbitrage")
	add_case("T2-F10-02", 2, "F10", "baseline", ">=60 Spirit Stone secondary confirmation banner: 0-deduct on click, Cancel preserves stones, Confirm buys & insufficient-funds block", "case_t2_f10_02_secondary_confirm_and_cancel")
	add_case("T2-F10-03", 2, "F10", "baseline", "Burnt-pill 0.34 fire error boundary, rejected beneficial OOC heal & unsellable shop guard", "case_t2_f10_03_burnt_pill_boundary_and_unsellable")
	add_case("T2-F10-04", 2, "F10", "baseline", "Mid-brew close_modal() timer cleanup, MODE_WORLD_COMBAT restoration & zero stray pill production", "case_t2_f10_04_mid_brew_close_cleanup")
	add_case("T2-F10-05", 2, "F10", "baseline", "Sword Box occupied-slot rejection, premature claim (3/2/1) block, non-purifiable guard & 100% reforge refund", "case_t2_f10_05_sword_box_guards_and_reforge")
	add_case("T2-F11-01", 2, "F11", "baseline", "Strict 4-tab casket cap (C/N/B/J only), hidden 灵兽袋 (P) tab & KEY_P no-op guard", "case_t2_f11_01_hidden_pet_tab_and_key_p")
	add_case("T2-F11-02", 2, "F11", "baseline", "Runtime UI text walk across HUD, Casket (4 tabs) & Modals: zero master_d/master_b gibberish or Traditional strings", "case_t2_f11_02_zero_gibberish_runtime_walk")
	add_case("T2-F11-03", 2, "F11", "baseline", "Live scene-tree >=16px font floor across TitleScreen, CombatHud, DaoCasketPanel & all WorldModals", "case_t2_f11_03_runtime_16px_font_floor_all_screens")
	add_case("T2-F11-04", 2, "F11", "polish_r3", "Polish R3 hover_outline.gdshader WITHOUT render_mode unshaded; + clean unhover outline reset", "case_t2_f11_04_r3_hover_shader_shaded_and_unhover")
	add_case("T2-F11-05", 2, "F11", "polish_r3", "Polish R3 NPC/enemy RMB non-ripple guard + Alt highlight auto-reset on MODE_DIALOGUE / MODE_MODAL_MENU", "case_t2_f11_05_r3_npc_enemy_no_ripple_and_alt_reset")


func _join_visible_texts(root_node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	for lbl: Label in collect_visible_labels(root_node):
		out.append(lbl.text)
	for btn: Button in collect_visible_buttons(root_node):
		out.append(btn.text)
	return "\n".join(out)


func _find_button_containing(root_node: Node, substr: String) -> Button:
	for btn: Button in collect_visible_buttons(root_node):
		if btn.text.contains(substr):
			return btn
	return null


func _count_active_move_ripples(world: QinglanWorld) -> int:
	var count: int = 0
	for vfx_obj: CombatVfxOverlay in [world._ground_vfx, world._sky_vfx]:
		if vfx_obj == null:
			continue
		for pname: String in ["move_ripples", "_move_ripples", "active_ripples", "_ripples"]:
			if obj_has_prop(vfx_obj, pname):
				count += as_arr(obj_get(vfx_obj, pname, [])).size()
		for fx: Dictionary in vfx_obj.transient_fx:
			var fk: String = str(fx.get("kind", ""))
			if fk.contains("ripple") or fk.contains("move") or fk.contains("water"):
				count += 1
		for ch: Node in vfx_obj.get_children():
			if ch is CanvasItem and (ch as CanvasItem).visible and ch.name.to_lower().contains("ripple"):
				count += 1
	return count


func case_t2_f10_01_sell_cap_and_zero_arbitrage() -> void:
	assert_approx(EconomyRules.SELL_RATIO, 0.35, 0.0001, "GDD 0.35 SELL_RATIO constant")
	assert_eq(EconomyRules.SWORD_BOX_PURIFY_BATTLES, 3, "GDD 3 SWORD_BOX_PURIFY_BATTLES constant")
	assert_eq(EconomyRules.compute_sell_price(100, 999), 35, "Explicit sell price > 35% clamped to floor(100 * 0.35) == 35")
	assert_eq(EconomyRules.compute_sell_price(100, -1), 35, "Implicit sell price == floor(100 * 0.35) == 35")
	assert_eq(EconomyRules.compute_sell_price(0, -1), 1, "Zero buy_price floors sell_price at 1")

	var merged: Dictionary = {}
	for k_var: Variant in DataDB.items.keys():
		var k: String = str(k_var)
		merged[k] = DataDB.items[k]
	for ek_var: Variant in DataDB.equipment.keys():
		var ek: String = str(ek_var)
		merged[ek] = DataDB.equipment[ek]

	var checked_sell: int = 0
	for iid_var: Variant in merged.keys():
		var iid: String = str(iid_var)
		var idef: Dictionary = as_dict(merged[iid])
		if bool(idef.get("unsellable", false)):
			continue
		var buy_p: int = int(idef.get("buy_price", 0))
		if buy_p <= 0:
			continue
		var computed_s: int = EconomyRules.compute_sell_price(buy_p, int(idef.get("sell_price", -1)))
		var max_allowed: int = maxi(1, int(floor(float(buy_p) * 0.35)))
		assert_le(float(computed_s), float(max_allowed), "Sell price for '%s' <= floor(buy*0.35)" % iid)
		checked_sell += 1
	assert_ge(checked_sell, 15, "Checked >= 15 sellable items")

	assert_ge(DataDB.recipes.size(), 3, "At least 3 recipes in DataDB")
	for rid_var: Variant in DataDB.recipes.keys():
		var rid: String = str(rid_var)
		var rdef: Dictionary = DataDB.get_recipe(rid)
		assert_true(EconomyRules.is_recipe_arbitrage_safe(rdef, merged), "Recipe '%s' is 100%% arbitrage-safe" % rid)

	# Non-vacuity counter-proof: cheap 2-stone herb -> 500-stone pill MUST be flagged unsafe!
	var fake_defs: Dictionary = {
		"cheap_herb": {"buy_price": 2},
		"gold_pill": {"buy_price": 500, "sell_price": 175},
	}
	var bad_recipe: Dictionary = {
		"output_item_id": "gold_pill",
		"ingredients": [{"item_id": "cheap_herb", "count": 1}],
	}
	assert_false(EconomyRules.is_recipe_arbitrage_safe(bad_recipe, fake_defs), "Counter-proof: profitable buy-brew-sell loop rejected")


func case_t2_f10_02_secondary_confirm_and_cancel() -> void:
	CampaignState.spirit_stones = 100
	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_shop_modal("shop_tingyu_peddler")
	await step_frames(2)

	# Find row for item_stall_sword_shard (60 Spirit Stones >= 60 threshold)
	var shard_name: String = DataDB.loc("ITEM_STALL_SHARD_NAME")
	var shard_buy_btn: Button = null
	var stack: Array[Node] = [modals]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is PanelContainer:
			var pc: PanelContainer = cur as PanelContainer
			if pc.get_parent() is VBoxContainer and _join_visible_texts(pc).contains(shard_name):
				shard_buy_btn = _find_button_containing(pc, "购入")
				if shard_buy_btn != null:
					break
		for ch: Node in cur.get_children():
			stack.append(ch)

	assert_not_null(shard_buy_btn, "Found 购入 button for 60-stone item_stall_sword_shard")
	if shard_buy_btn != null:
		shard_buy_btn.pressed.emit()
	await step_frames(2)

	assert_eq(CampaignState.spirit_stones, 100, "First click on >=60 item deducts 0 Spirit Stones before confirmation")
	assert_eq(CampaignState.get_item_count("item_stall_sword_shard"), 0, "0 shards granted before confirmation")

	var cancel_btn: Button = _find_button_containing(modals, tr("UI_BTN_CANCEL"))
	assert_not_null(cancel_btn, "Secondary confirmation banner shows UI_BTN_CANCEL")
	if cancel_btn != null:
		cancel_btn.pressed.emit()
	await step_frames(2)
	assert_eq(CampaignState.spirit_stones, 100, "Cancel leaves Spirit Stones untouched at 100")
	assert_eq(CampaignState.get_item_count("item_stall_sword_shard"), 0, "Cancel grants 0 shards")

	# Re-open confirm and click Confirm
	modals.open_shop_modal("shop_tingyu_peddler", "item_stall_sword_shard")
	await step_frames(2)
	var confirm_btn: Button = _find_button_containing(modals, tr("UI_BTN_CONFIRM"))
	assert_not_null(confirm_btn, "Secondary confirmation banner shows UI_BTN_CONFIRM")
	if confirm_btn != null:
		confirm_btn.pressed.emit()
	await step_frames(2)

	assert_eq(CampaignState.spirit_stones, 40, "Confirm deducts 60 Spirit Stones (100 -> 40)")
	assert_eq(CampaignState.get_item_count("item_stall_sword_shard"), 1, "Confirm grants 1 item_stall_sword_shard")
	assert_true(bool(CampaignState.world_flags.get("peddler_gem_bought", false)), "peddler_gem_bought flag set")
	assert_false(CampaignState.add_spirit_stones(-999, true), "Over-spend rejected cleanly")
	assert_eq(CampaignState.spirit_stones, 40, "Failed spend preserves exact Spirit Stone balance")


func case_t2_f10_03_burnt_pill_boundary_and_unsellable() -> void:
	var rdef: Dictionary = DataDB.get_recipe("recipe_huichun_powder")
	var at_014: Dictionary = EconomyRules.evaluate_first_brew_fire([0.50, 0.50, 0.50], [0.64, 0.36, 0.64], rdef)
	var at_034: Dictionary = EconomyRules.evaluate_first_brew_fire([0.50, 0.50, 0.50], [0.84, 0.16, 0.84], rdef)
	var over_034: Dictionary = EconomyRules.evaluate_first_brew_fire([0.50, 0.50, 0.50], [0.85, 0.15, 0.85], rdef)

	assert_eq(str(at_014.get("quality", "")), "flawless", "avg_error == 0.14 boundary -> flawless")
	assert_eq(str(at_034.get("quality", "")), "standard", "avg_error == 0.34 boundary -> standard")
	assert_approx(float(at_034.get("potency_mult", 0.0)), 1.00, 0.001, "Standard potency_mult == 1.00")
	assert_eq(str(over_034.get("quality", "")), "burnt", "avg_error == 0.35 (>0.34) -> burnt")
	assert_approx(float(over_034.get("potency_mult", 1.0)), 0.0, 0.001, "Burnt potency_mult == 0.0")
	assert_false(bool(over_034.get("unlock_quick_brew", true)), "Burnt never unlocks quick_brew")
	assert_eq(str(over_034.get("output_item_id", "")), "item_burnt_pill", "Burnt outputs item_burnt_pill")

	# Rejected beneficial OOC heal: burnt pill must NEVER heal HP, restore MP, or grant active_elixir
	var gu_m: Dictionary = as_dict(CampaignState.party_members.get("gu_changqing", {}))
	gu_m["hp"] = 75
	gu_m["mp"] = 20
	CampaignState.active_elixir.clear()
	CampaignState.add_item("item_burnt_pill", 1, true)
	var ooc_res: Dictionary = CampaignState.use_out_of_combat_item("item_burnt_pill")
	var hp_after: int = int(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("hp", 999))
	var mp_after: int = int(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("mp", 999))
	assert_le(float(hp_after), 75.0, "Consuming/attempting item_burnt_pill OOC never grants beneficial HP healing (res=%s)" % str(ooc_res))
	assert_eq(mp_after, 20, "item_burnt_pill never restores MP")
	assert_true(CampaignState.active_elixir.is_empty(), "item_burnt_pill never grants elixir buff")

	# Unsellable guard in shop sell column
	var burnt_def: Dictionary = DataDB.get_any_item_or_equip("item_burnt_pill")
	assert_true(bool(burnt_def.get("unsellable", false)), "item_burnt_pill marked unsellable == true")
	CampaignState.add_item("item_burnt_pill", 1, true)
	CampaignState.add_item("item_marrow_dew", 1, true)
	CampaignState.add_item("item_yaolu_jade_token", 1, true)
	CampaignState.add_item("item_bloodied_pouch", 1, true)

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)

	var shop_txt: String = _join_visible_texts(modals)
	assert_str_not_contains(shop_txt, "%s ×" % DataDB.loc("ITEM_BURNT_PILL_NAME"), "Unsellable 焦黑废丹 excluded from shop sell list")
	assert_str_not_contains(shop_txt, "%s ×" % DataDB.loc("ITEM_MARROW_DEW_NAME"), "Unsellable 洗髓灵露 excluded from shop sell list")
	assert_str_not_contains(shop_txt, "%s ×" % DataDB.loc("ITEM_BLOODIED_POUCH_NAME"), "Storage pouch excluded from shop sell list")
	assert_str_not_contains(shop_txt, "%s ×" % DataDB.loc("ITEM_YAOLU_TOKEN_NAME"), "Quest token excluded from shop sell list")


func case_t2_f10_04_mid_brew_close_cleanup() -> void:
	CampaignState.add_item("item_ningqi_herb", 2, true)
	CampaignState.add_item("item_qingmu_leaf", 2, true)
	var std_before: int = CampaignState.get_item_count("item_huichun_powder")
	var flaw_before: int = CampaignState.get_item_count("item_huichun_powder_flawless")
	var burnt_before: int = CampaignState.get_item_count("item_burnt_pill")

	var modals: WorldModals = WorldModals.new()
	mount_node(modals)
	await step_frames(2)
	modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(2)

	var start_btn: Button = _find_button_containing(modals, "15秒")
	assert_not_null(start_btn, "15s brew button exists")
	if start_btn != null:
		start_btn.pressed.emit()
	await step_frames(1)
	assert_true(modals._brew_running, "Minigame started")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_BREW_MINIGAME, "Mode == MODE_BREW_MINIGAME")

	modals._process(6.0)
	assert_eq(modals._brew_recorded.size(), 1, "Recorded stage 0 at 6.0s")

	modals.close_modal()
	assert_false(modals.visible, "Modal hidden on close_modal()")
	assert_false(modals._brew_running, "_brew_running cleared immediately on close_modal()")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Mode restored to MODE_WORLD_COMBAT")

	# Step 25s after close -> zero stray completion!
	modals._process(25.0)
	await step_frames(2)
	assert_eq(CampaignState.get_item_count("item_huichun_powder"), std_before, "0 standard pills leaked after mid-brew close")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), flaw_before, "0 flawless pills leaked after mid-brew close")
	assert_eq(CampaignState.get_item_count("item_burnt_pill"), burnt_before, "0 burnt pills leaked after mid-brew close")


func case_t2_f10_05_sword_box_guards_and_reforge() -> void:
	CampaignState.add_item("item_burnt_pill", 1, true)
	CampaignState.add_item("item_ningqi_herb", 2, true)
	var herb_cnt: int = CampaignState.get_item_count("item_ningqi_herb")

	assert_true(CampaignState.start_sword_box_purify("item_burnt_pill"), "Load burnt pill into Sword Box")
	assert_false(CampaignState.start_sword_box_purify("item_ningqi_herb"), "Occupied Sword Box rejects 2nd item")
	assert_eq(CampaignState.get_item_count("item_ningqi_herb"), herb_cnt, "Rejected 2nd item stays in inventory")

	assert_false(CampaignState.claim_sword_box_output(), "Premature claim blocked at 3 battles remaining")
	CampaignState.advance_sword_box_progress(1)
	assert_false(CampaignState.claim_sword_box_output(), "Premature claim blocked at 2 battles remaining")
	CampaignState.advance_sword_box_progress(1)
	assert_false(CampaignState.claim_sword_box_output(), "Premature claim blocked at 1 battle remaining")
	CampaignState.advance_sword_box_progress(1)
	assert_true(CampaignState.claim_sword_box_output(), "Claim succeeds at 0 battles remaining")
	assert_false(CampaignState.claim_sword_box_output(), "Double-claim on empty slot rejected")

	# Non-purifiable equipment & unowned item rejected
	CampaignState.add_item("eq_qinglan_iron_sword", 1, true)
	assert_false(CampaignState.start_sword_box_purify("eq_qinglan_iron_sword"), "Non-purifiable weapon rejected")
	assert_false(CampaignState.start_sword_box_purify("item_corrupt_flower"), "Unowned item rejected")

	# 100% lossless reforge core & enchant crystal refund
	var refunds: Array[Dictionary] = EconomyRules.compute_reforge_refund({
		"craft_core_item_id": "item_wolf_fang_core",
		"craft_core_count": 2,
		"enchant_crystal_spent": 3,
	})
	assert_eq(refunds.size(), 2, "Reforge refunds both rare core and enchant crystals")
	assert_eq(str(refunds[0].get("item_id", "")), "item_wolf_fang_core", "100% rare monster core ID")
	assert_eq(int(refunds[0].get("count", 0)), 2, "100% rare monster core count")
	assert_eq(str(refunds[1].get("item_id", "")), "item_enchant_crystal", "100% enchant crystal ID")
	assert_eq(int(refunds[1].get("count", 0)), 3, "100% enchant crystal count")


func case_t2_f11_01_hidden_pet_tab_and_key_p() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	assert_eq(world._casket._tab_buttons.size(), 4, "Exactly 4 casket tabs in Ch1 vertical slice")
	for expected_tab: String in ["cultivation", "specialization", "inventory", "journal"]:
		assert_true(world._casket._tab_buttons.has(expected_tab), "Casket has tab '%s'" % expected_tab)
	assert_false(world._casket._tab_buttons.has("pets"), "Unopened Spirit Pet Tome tab omitted")

	dispatch_input(make_key_event(KEY_P, true))
	await step_frames(2)
	assert_false(world._casket.visible, "KEY_P in world mode opens zero panels")
	assert_false(world._modals.visible, "KEY_P opens zero modals")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Mode remains MODE_WORLD_COMBAT")

	world._casket.open_tab("cultivation")
	await step_frames(2)
	var casket_txt: String = _join_visible_texts(world._casket)
	assert_str_not_contains(casket_txt, "灵兽袋", "Zero grey-locked 灵兽袋 tab text in DaoCasketPanel")
	assert_str_not_contains(casket_txt, "(P)", "Zero (P) hotkey label in DaoCasketPanel")

	dispatch_input(make_key_event(KEY_P, true))
	await step_frames(2)
	assert_eq(world._casket.active_tab, "cultivation", "KEY_P inside casket leaves active_tab unchanged")


func case_t2_f11_02_zero_gibberish_runtime_walk() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)

	var hud: CombatHud = CombatHud.new()
	var casket: DaoCasketPanel = DaoCasketPanel.new()
	var modals: WorldModals = WorldModals.new()
	mount_node(hud)
	mount_node(casket)
	mount_node(modals)
	await step_frames(2)

	var forbidden: Array[String] = [
		"丸榲", "百榥", "白恩", "體魄", "靈識", "真氣", "攻擊", "防禦", "Qi 56", "濟世堂", "济世堂"
	]

	var hud_txt: String = _join_visible_texts(hud)
	for tok: String in forbidden:
		assert_str_not_contains(hud_txt, tok, "CombatHud free of mockup token '%s'" % tok)

	for tab_id: String in ["cultivation", "specialization", "inventory", "journal"]:
		if casket.active_tab != tab_id or not casket.visible:
			casket.open_tab(tab_id)
			await step_frames(1)
		var tab_txt: String = _join_visible_texts(casket)
		for tok2: String in forbidden:
			assert_str_not_contains(tab_txt, tok2, "Casket tab '%s' free of mockup token '%s'" % [tab_id, tok2])
	casket.close_casket()

	modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(1)
	var alch_txt: String = _join_visible_texts(modals)
	for tok3: String in forbidden:
		assert_str_not_contains(alch_txt, tok3, "Alchemy modal free of mockup token '%s'" % tok3)

	modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(1)
	var shop_txt: String = _join_visible_texts(modals)
	assert_str_contains(shop_txt, "济世药庐", "Pharmacy modal uses canonical '济世药庐'")
	for tok4: String in forbidden:
		assert_str_not_contains(shop_txt, tok4, "Shop modal free of mockup token '%s'" % tok4)


func case_t2_f11_03_runtime_16px_font_floor_all_screens() -> void:
	var title: Control = spawn_title_screen()
	await step_frames(2)
	var t_stats: Dictionary = min_font_size_in_tree(title)
	assert_ge(int(t_stats.get("min_px", 0)), 16, "TitleScreen min font size >= 16px")
	assert_true(as_arr(t_stats.get("offenders", [])).is_empty(), "TitleScreen has 0 <16px offenders")
	if is_instance_valid(title):
		_spawned_nodes.erase(title)
		if title.get_parent() != null:
			title.get_parent().remove_child(title)
		title.free()

	var hud: CombatHud = CombatHud.new()
	var casket: DaoCasketPanel = DaoCasketPanel.new()
	var modals: WorldModals = WorldModals.new()
	mount_node(hud)
	mount_node(casket)
	mount_node(modals)
	await step_frames(2)

	var hud_stats: Dictionary = min_font_size_in_tree(hud)
	assert_ge(int(hud_stats.get("min_px", 0)), 16, "CombatHud min font size >= 16px")
	assert_true(as_arr(hud_stats.get("offenders", [])).is_empty(), "CombatHud has 0 <16px offenders")

	for tab_id: String in ["cultivation", "specialization", "inventory", "journal"]:
		if casket.active_tab != tab_id or not casket.visible:
			casket.open_tab(tab_id)
			await step_frames(1)
		var c_stats: Dictionary = min_font_size_in_tree(casket)
		assert_ge(int(c_stats.get("min_px", 0)), 16, "DaoCasketPanel '%s' >= 16px" % tab_id)
		assert_true(as_arr(c_stats.get("offenders", [])).is_empty(), "DaoCasketPanel '%s' 0 offenders" % tab_id)
	casket.close_casket()

	modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(1)
	assert_true(as_arr(min_font_size_in_tree(modals).get("offenders", [])).is_empty(), "Alchemy modal >=16px")

	modals.open_shop_modal("shop_tingyu_peddler")
	await step_frames(1)
	assert_true(as_arr(min_font_size_in_tree(modals).get("offenders", [])).is_empty(), "Peddler modal >=16px")

	modals.open_world_map_modal()
	await step_frames(1)
	assert_true(as_arr(min_font_size_in_tree(modals).get("offenders", [])).is_empty(), "World map modal >=16px")

	modals.open_settings_modal()
	await step_frames(1)
	assert_true(as_arr(min_font_size_in_tree(modals).get("offenders", [])).is_empty(), "Settings modal >=16px")
	modals.close_modal()


func case_t2_f11_04_r3_hover_shader_shaded_and_unhover() -> void:
	var sh: Shader = load_shader("res://src/presentation/shaders/hover_outline.gdshader")
	assert_not_null(sh, "Polish R3 hover_outline.gdshader loads cleanly")
	if sh != null:
		assert_str_contains(strip_shader_comments(sh.code), "shader_type canvas_item;", "hover_outline.gdshader is canvas_item shader")
		assert_false(shader_has_unshaded_render_mode(sh), "hover_outline.gdshader omits render_mode unshaded; (PROJECT.md:90)")

	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(3)
	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(1380.0, 650.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	var alch_sp: Sprite2D = null
	var alch_pos: Vector2 = Vector2(1405.0, 646.0)
	for inter: Dictionary in world._interactables:
		if str(inter.get("id", "")) == "yaolu_alchemy":
			alch_sp = inter.get("sprite", null) as Sprite2D
			alch_pos = inter.get("pos", alch_pos) as Vector2
			break

	var hover_scr: Vector2 = world.get_canvas_transform() * (alch_pos + Vector2(0.0, -32.0))
	Input.warp_mouse(hover_scr)
	dispatch_input(make_mouse_motion_event(hover_scr))
	await step_frames(4)

	var active_on_hover: bool = (alch_sp != null and alch_sp.material is ShaderMaterial)

	# Move cursor far away to empty top-left sky corner -> outline must reset!
	var away_scr: Vector2 = Vector2(24.0, 24.0)
	Input.warp_mouse(away_scr)
	dispatch_input(make_mouse_motion_event(away_scr))
	await step_frames(5)

	var reset_on_unhover: bool = true
	if alch_sp != null and alch_sp.material is ShaderMaterial:
		var sm: ShaderMaterial = alch_sp.material as ShaderMaterial
		reset_on_unhover = false
		for pname: String in ["outline_intensity", "hover_strength", "intensity", "outline_alpha", "enabled"]:
			var pv: Variant = sm.get_shader_parameter(pname)
			if pv is float and float(pv) <= 0.01:
				reset_on_unhover = true
				break
			if pv is bool and not bool(pv):
				reset_on_unhover = true
				break

	assert_true(active_on_hover, "Hovering yaolu_alchemy activates hover_outline.gdshader ShaderMaterial")
	assert_true(reset_on_unhover, "Unhovering yaolu_alchemy resets outline material/intensity cleanly to 0")


func case_t2_f11_05_r3_npc_enemy_no_ripple_and_alt_reset() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	# 1. Verify Alt highlight auto-resets when entering dialogue or modal mode
	InputRouter.alt_held = true
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	assert_false(InputRouter.alt_held, "Entering MODE_DIALOGUE resets InputRouter.alt_held to false")
	InputRouter.alt_held = true
	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	assert_false(InputRouter.alt_held, "Entering MODE_MODAL_MENU resets InputRouter.alt_held to false")
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)

	# 2. Positive control: RMB on open walkable ground MUST spawn >= 1 move water-ripple
	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(960.0, 700.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	var ripples_0: int = _count_active_move_ripples(world)
	var ground_scr: Vector2 = world.get_canvas_transform() * Vector2(700.0, 810.0)
	Input.warp_mouse(ground_scr)
	dispatch_input(make_mouse_motion_event(ground_scr))
	await step_frames(1)
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, ground_scr, true))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, ground_scr, false))
	await step_frames(2)
	var ripples_ground: int = _count_active_move_ripples(world)
	assert_gt(float(ripples_ground), float(ripples_0), "Positive control: RMB on walkable ground spawns celadon-jade move ripple")

	# 3. Negative guard A: RMB directly on nearby npc_elder starts dialogue WITHOUT adding a move ripple
	var gu_actor: BattleActor = world._combat_ctrl.get_controlled_actor()
	if gu_actor != null:
		gu_actor.position = Vector2(565.0, 760.0) # Within 240px of npc_elder (565, 695)
	var before_npc_ripples: int = _count_active_move_ripples(world)
	var elder_scr: Vector2 = world.get_canvas_transform() * Vector2(565.0, 650.0)
	Input.warp_mouse(elder_scr)
	dispatch_input(make_mouse_motion_event(elder_scr))
	await step_frames(1)
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, elder_scr, true))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, elder_scr, false))
	await step_frames(2)
	assert_true(world._narrative.visible, "RMB on nearby npc_elder opens dialogue")
	assert_le(float(_count_active_move_ripples(world)), float(before_npc_ripples), "RMB on NPC does NOT spawn ground move water-ripple")
	world._narrative.visible = false
	NotifyHub.set_narrative_exclusive(false)
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)

	# 4. Negative guard B: RMB directly on an enemy in qinglan_pass locks target WITHOUT spawning move ripple
	world.load_zone("qinglan_pass", "from_town", false)
	await step_frames(3)
	if not world._combat_ctrl.enemy_actors.is_empty():
		var enemy_a: BattleActor = world._combat_ctrl.enemy_actors[0]
		var ctrl_a: BattleActor = world._combat_ctrl.get_controlled_actor()
		if ctrl_a != null:
			ctrl_a.position = enemy_a.position + Vector2(-150.0, 20.0)
		world._camera.position_smoothing_enabled = false
		world._camera.position = enemy_a.position
		world._camera.force_update_scroll()
		await step_frames(2)

		var before_enemy_ripples: int = _count_active_move_ripples(world)
		var enemy_scr: Vector2 = world.get_canvas_transform() * (enemy_a.position + Vector2(0.0, -48.0))
		Input.warp_mouse(enemy_scr)
		dispatch_input(make_mouse_motion_event(enemy_scr))
		await step_frames(1)
		dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, enemy_scr, true))
		dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, enemy_scr, false))
		await step_frames(2)
		assert_eq(world._combat_ctrl.locked_enemy_id, enemy_a.actor_id, "RMB on enemy locks enemy target")
		assert_le(float(_count_active_move_ripples(world)), float(before_enemy_ripples), "RMB on enemy does NOT spawn ground move water-ripple")
