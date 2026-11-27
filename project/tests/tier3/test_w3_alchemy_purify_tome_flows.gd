extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 3
# @e2e_features: F8, F9, F10, F11


func register_cases() -> void:
	add_case("T3-W3-01", 3, "F9", "baseline", "Flea-Market Appraisal -> >=60 Confirm -> Bamboo Ambush -> Pouch -> Spy Confrontation -> eq_pendant_jingqing Stunt Equip -> Scratch Save/Load", "case_t3_w3_01_flea_market_spy_save_roundtrip")
	add_case("T3-W3-02", 3, "F10", "baseline", "Failed Brew (item_burnt_pill) -> Sword Box 3-Battle Purification -> Claim item_huichun_powder_flawless -> Cleanse 经脉暗伤 & Combat Slot 5 Off-GCD Heal", "case_t3_w3_02_burnt_brew_purify_combat_pill")
	add_case("T3-W3-03", 3, "F8", "baseline", "洗髓灵露 Potential Respec + eq_pendant_poxue & eq_ancient_wood_blade -> StatLedger Bucket A/B/C -> 破血狂攻 (40 Qi) Combat Execution", "case_t3_w3_03_respec_gear_buckets_poxue_combat")
	add_case("T3-W3-04", 3, "F11", "polish_r3", "Tactical Pause (Space, combat_delta == 0.0) + 900Hz LPF + LMB Box-Select + Live ui_delta Unshaded RMB Jade Water-Ripple", "case_t3_w3_04_r3_pause_lpf_and_unshaded_ripple")
	add_case("T3-W3-05", 3, "F11", "polish_r3", "Reputation Discount Herb Purchase -> Flickering-Flame Cauldron Brew -> Thread-Bound Xuan Tome (C/N/B/J -> Esc) Focus Return", "case_t3_w3_05_r3_discount_brew_tome_tour")


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


func _mean_abs_diff_in_rect(img_a: Image, img_b: Image, rect: Rect2i) -> float:
	if img_a == null or img_b == null or img_a.is_empty() or img_b.is_empty():
		return 0.0
	var x0: int = clampi(rect.position.x, 0, mini(img_a.get_width(), img_b.get_width()))
	var y0: int = clampi(rect.position.y, 0, mini(img_a.get_height(), img_b.get_height()))
	var x1: int = clampi(rect.position.x + rect.size.x, 0, mini(img_a.get_width(), img_b.get_width()))
	var y1: int = clampi(rect.position.y + rect.size.y, 0, mini(img_a.get_height(), img_b.get_height()))
	var total: float = 0.0
	var cnt: int = 0
	for y: int in range(y0, y1, 2):
		for x: int in range(x0, x1, 2):
			var ca: Color = img_a.get_pixel(x, y)
			var cb: Color = img_b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			cnt += 1
	return total / float(maxi(1, cnt))


func _is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	return is_canvas_item_unshaded(ci)


func case_t3_w3_01_flea_market_spy_save_roundtrip() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.spirit_stones = 135

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	# 1. Open Peddler Stall, hover shard for Sword-Box resonance, and purchase with >=60 secondary confirmation
	world._modals.open_shop_modal("shop_tingyu_peddler")
	await step_frames(2)

	var shard_name: String = DataDB.loc("ITEM_STALL_SHARD_NAME")
	var shard_card: PanelContainer = null
	var shard_buy_btn: Button = null
	var stack: Array[Node] = [world._modals]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is PanelContainer:
			var pc: PanelContainer = cur as PanelContainer
			if pc.get_parent() is VBoxContainer and _join_visible_texts(pc).contains(shard_name):
				var b: Button = _find_button_containing(pc, "购入")
				if b != null:
					shard_card = pc
					shard_buy_btn = b
					break
		for ch: Node in cur.get_children():
			stack.append(ch)

	assert_not_null(shard_card, "Peddler shard card located")
	if shard_card != null:
		shard_card.mouse_entered.emit()
		await step_frames(1)
		assert_str_contains(_join_visible_texts(world._modals), "断玉剑匣", "Hovering shard shows 断玉剑匣 warm resonance")

	if shard_buy_btn != null:
		shard_buy_btn.pressed.emit()
	await step_frames(2)
	assert_eq(CampaignState.spirit_stones, 135, "0 Spirit Stones deducted before secondary confirmation")

	var confirm_btn: Button = _find_button_containing(world._modals, tr("UI_BTN_CONFIRM"))
	assert_not_null(confirm_btn, "Secondary confirm button present")
	if confirm_btn != null:
		confirm_btn.pressed.emit()
	await step_frames(2)
	assert_eq(CampaignState.spirit_stones, 75, "60 Spirit Stones deducted (135 -> 75)")
	assert_eq(CampaignState.get_item_count("item_stall_sword_shard"), 1, "Obtained item_stall_sword_shard")
	assert_true(bool(CampaignState.world_flags.get("peddler_gem_bought", false)), "peddler_gem_bought == true")
	world._modals.close_modal()

	# 2. Walk into bamboo ambush zone in qinglan_pass -> dlg_ch01_rogue_ambush -> enc_rogue_ambush
	world.load_zone("qinglan_pass", "from_town", false)
	await step_frames(3)
	var ctrl_a: BattleActor = world._combat_ctrl.get_controlled_actor()
	if ctrl_a != null:
		ctrl_a.position = Vector2(1120.0, 820.0)
	world._check_dynamic_zone_triggers()
	await step_frames(2)
	assert_true(world._narrative.visible, "Bamboo ambush dialogue dlg_ch01_rogue_ambush triggered")

	while world._narrative.visible and not world._narrative._choices_box.visible:
		InputRouter._process(0.45)
		world._narrative._on_advance_input()
		await step_frames(1)

	assert_true(world._combat_ctrl.in_combat, "Rogue ambush combat engaged")

	# Defeat all engaged enc_rogue_ambush enemies
	for ea: BattleActor in world._combat_ctrl.enemy_actors:
		var eu: Dictionary = as_dict(world._combat_ctrl.unit_states.get(ea.actor_id, {}))
		if str(eu.get("group_id", "")) == "enc_rogue_ambush" and ea.alive:
			world._combat_ctrl._apply_direct_enemy_hp_loss(eu, ea, 9999, "metal", true, "")
	world._combat_ctrl._check_combat_resolution()
	await step_frames(2)

	assert_false(world._combat_ctrl.in_combat, "Ambush cleared")
	assert_true(bool(CampaignState.world_flags.get("rogue_ambush_cleared", false)), "rogue_ambush_cleared == true")
	assert_eq(CampaignState.get_item_count("item_bloodied_pouch"), 1, "Dropped item_bloodied_pouch")

	# 3. Open item_bloodied_pouch
	var stones_pre_pouch: int = CampaignState.spirit_stones
	var pouch_res: Dictionary = CampaignState.use_out_of_combat_item("item_bloodied_pouch")
	assert_true(bool(pouch_res.get("ok", false)), "Opened item_bloodied_pouch")
	assert_eq(CampaignState.spirit_stones, stones_pre_pouch + 110, "+110 Spirit Stones from pouch")
	assert_gt(CampaignState.get_item_count("item_yaolu_jade_token"), 0, "Granted item_yaolu_jade_token")
	assert_true(CampaignState.unlocked_recipes.has("recipe_qingmu_pill"), "Unlocked recipe_qingmu_pill")
	assert_true(CampaignState.unlocked_clues.has("clue_yaolu_spy_token"), "Unlocked clue_yaolu_spy_token")

	# 4. Return to tingyu_town and confront Steward Zhou -> CHOICE_ZHOU_INVESTIGATE
	world.load_zone("tingyu_town", "from_pass", false)
	await step_frames(3)
	var rep_before_zhou: int = int(CampaignState.faction_reputation.get("jishi_pharmacy", 0))
	world._trigger_npc_dialogue("npc_zhou")
	await step_frames(2)
	assert_true(world._narrative.visible, "Confront Zhou dialogue started")

	var safety: int = 0
	while world._narrative.visible and not world._narrative._choices_box.visible and safety < 12:
		safety += 1
		InputRouter._process(0.45)
		world._narrative._on_advance_input()
		await step_frames(1)

	assert_true(world._narrative._choices_box.visible, "Zhou confrontation moral choice presented")
	await step_frames(2)
	InputRouter._process(0.45)
	var mercy_label: String = DataDB.loc("CHOICE_ZHOU_INVESTIGATE")
	var mercy_btn: Button = null
	for ch_c: Node in world._narrative._choices_box.get_children():
		if ch_c is Button and (ch_c as Button).text.contains(mercy_label):
			mercy_btn = ch_c as Button
			break
	assert_not_null(mercy_btn, "Found CHOICE_ZHOU_INVESTIGATE button")
	if mercy_btn != null:
		mercy_btn.pressed.emit()
	await step_frames(2)

	assert_false(world._narrative.visible, "Zhou confrontation finished")
	assert_eq(CampaignState.get_item_count("eq_pendant_jingqing"), 1, "Rewarded eq_pendant_jingqing")
	assert_eq(int(CampaignState.faction_reputation.get("jishi_pharmacy", 0)), rep_before_zhou + 550, "+550 jishi_pharmacy reputation")
	assert_ge(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), 2, "Shen Qinghe bond reached Tier 2")
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "Unlocked dual bond ultimate 青莲引剑")
	assert_true(CampaignState.ink_seals.has("seal_yaolu_justice"), "Stamped cinnabar karma seal seal_yaolu_justice")

	# 5. Equip eq_pendant_jingqing on Shen Qinghe & verify Scratch Save/Load roundtrip
	assert_true(CampaignState.equip_item_on_member("shen_qinghe", "eq_pendant_jingqing"), "Equip eq_pendant_jingqing on Shen")
	var shen_stunts_pre: Array = as_arr(as_dict(as_dict(CampaignState.party_members.get("shen_qinghe", {})).get("sheet", {})).get("blue_stunt_ids", []))
	assert_eq(shen_stunts_pre, ["stunt_jingqing_jade"], "Shen active blue stunt == stunt_jingqing_jade")

	var expected_stones: int = CampaignState.spirit_stones
	var expected_rep: int = int(CampaignState.faction_reputation.get("jishi_pharmacy", 0))
	if not begin_isolated_xdg_save_test():
		return
	var save_res: Dictionary = SaveManager.save_manual_slot(4)
	assert_true(bool(save_res.get("ok", false)), "Scratch manual save slot_04 succeeded")

	CampaignState.start_new_campaign("ask_heart")
	assert_eq(CampaignState.spirit_stones, 135, "Reset campaign wiped state before reload")

	var load_res: Dictionary = SaveManager.load_slot("slot_04", false)
	assert_true(bool(load_res.get("ok", false)), "Reloaded slot_04 from scratch XDG user://saves")
	assert_eq(CampaignState.spirit_stones, expected_stones, "Spirit Stones roundtripped 100%")
	assert_eq(int(CampaignState.faction_reputation.get("jishi_pharmacy", 0)), expected_rep, "Faction reputation roundtripped 100%")
	assert_true(CampaignState.ink_seals.has("seal_yaolu_justice"), "Karma seal roundtripped 100%")
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "Bond ultimate roundtripped 100%")
	var shen_stunts_post: Array = as_arr(as_dict(as_dict(CampaignState.party_members.get("shen_qinghe", {})).get("sheet", {})).get("blue_stunt_ids", []))
	assert_eq(shen_stunts_post, ["stunt_jingqing_jade"], "Equipped blue-stunt pendant roundtripped 100%")

	end_isolated_xdg_save_test()


func case_t3_w3_02_burnt_brew_purify_combat_pill() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(3)

	# 1. Failed 15s fire brew (>0.34 error) -> produces item_burnt_pill (2 brews -> 2 burnt pills)
	CampaignState.add_item("item_ningqi_herb", 4, true)
	CampaignState.add_item("item_qingmu_leaf", 4, true)
	var burnt_start: int = CampaignState.get_item_count("item_burnt_pill")

	for _attempt: int in range(2):
		world._modals.open_alchemy_furnace("recipe_huichun_powder")
		await step_frames(1)
		var sbtn: Button = _find_button_containing(world._modals, "15秒")
		if sbtn != null:
			sbtn.pressed.emit()
		await step_frames(1)
		world._modals._brew_heat = 0.99
		world._modals._process(5.1)
		world._modals._brew_heat = 0.01
		world._modals._process(5.0)
		world._modals._brew_heat = 0.99
		world._modals._process(5.0)
		await step_frames(1)

	world._modals.close_modal()
	assert_eq(CampaignState.get_item_count("item_burnt_pill"), burnt_start + 2, "2 failed brews yielded 2 item_burnt_pill")
	assert_false(CampaignState.quick_brew_recipes.has("recipe_huichun_powder"), "Failed brew never unlocks quick_brew")

	# 2. Load 1st burnt pill into Sword Box & advance via 3 real combat victories!
	var flaw_start: int = CampaignState.get_item_count("item_huichun_powder_flawless")
	assert_true(CampaignState.start_sword_box_purify("item_burnt_pill"), "Loaded 1st item_burnt_pill into Sword Box")

	for b_idx: int in range(3):
		var grp: String = "e2e_purify_pack_%d" % b_idx
		var ppos: Vector2 = world._combat_ctrl.get_controlled_actor_pos()
		var wolf: BattleActor = world._combat_ctrl.spawn_enemy_unit("rot_wolf", ppos + Vector2(120.0, 0.0), grp)
		world._combat_ctrl.engage_enemy_group(grp, "gu_changqing", false)
		assert_true(world._combat_ctrl.in_combat, "Combat #%d started" % (b_idx + 1))
		var wu: Dictionary = as_dict(world._combat_ctrl.unit_states.get(wolf.actor_id, {}))
		world._combat_ctrl._apply_direct_enemy_hp_loss(wu, wolf, 9999, "fire", true, "")
		world._combat_ctrl._check_combat_resolution()
		await step_frames(1)
		if b_idx < 2:
			assert_false(CampaignState.claim_sword_box_output(), "Premature claim blocked after %d/3 battles" % (b_idx + 1))

	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 0, "3 real combat victories completed Sword Box purification")
	assert_true(CampaignState.claim_sword_box_output(), "Claimed 1st purified item_huichun_powder_flawless")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), flaw_start + 1, "+1 flawless pill claimed")

	# 3. Purify 2nd burnt pill via Spirit Stele rest -> claim 2nd flawless pill
	assert_true(CampaignState.start_sword_box_purify("item_burnt_pill"), "Loaded 2nd item_burnt_pill")
	CampaignState.rest_at_stele("stele_temple_courtyard")
	assert_true(CampaignState.claim_sword_box_output(), "Claimed 2nd purified item_huichun_powder_flawless")
	assert_eq(CampaignState.get_item_count("item_huichun_powder_flawless"), flaw_start + 2, "+2 flawless pills available")

	# 4. Inflict 2 stacks of 经脉暗伤 (-12% max_hp) and cleanse with 1st flawless Huichun Powder
	var gu_m: Dictionary = as_dict(CampaignState.party_members.get("gu_changqing", {}))
	var unbruised_max: int = int(as_dict(gu_m.get("sheet", {})).get("max_hp", 180))
	gu_m["meridian_bruise"] = 2
	CampaignState.recalculate_all_party_stats(false)
	var bruised_max: int = int(as_dict(gu_m.get("sheet", {})).get("max_hp", 180))
	assert_lt(float(bruised_max), float(unbruised_max), "2 stacks of 经脉暗伤 reduces max_hp (-12%)")

	var cleanse_res: Dictionary = CampaignState.use_out_of_combat_item("item_huichun_powder_flawless")
	assert_true(bool(cleanse_res.get("ok", false)), "Consumed 1st flawless Huichun Powder")
	assert_eq(int(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("meridian_bruise", -1)), 0, "经脉暗伤 cleansed to 0")
	assert_eq(int(as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("sheet", {})).get("max_hp", 0)), unbruised_max, "Full max_hp restored after cleansing 经脉暗伤")

	# 5. Bind 2nd flawless Huichun Powder to Slot 5 & fire mid-combat OFF-GCD while gcd_timer == 1.25s!
	CampaignState.quick_pill_5_id = "item_huichun_powder_flawless"
	world._combat_ctrl.sync_party_roster_in_place()
	var ppos2: Vector2 = world._combat_ctrl.get_controlled_actor_pos()
	var wolf2: BattleActor = world._combat_ctrl.spawn_enemy_unit("rot_wolf", ppos2 + Vector2(140.0, 0.0), "e2e_pill_combat")
	assert_not_null(wolf2, "Spawned combat test wolf")
	world._combat_ctrl.engage_enemy_group("e2e_pill_combat", "gu_changqing", false)

	var gu_actor: BattleActor = world._combat_ctrl.get_controlled_actor()
	var gu_u: Dictionary = as_dict(world._combat_ctrl.unit_states.get("gu_changqing", {}))
	gu_actor.hp = 55
	gu_u["gcd_timer"] = 1.25
	world._combat_ctrl.pill_cooldown_timer = 0.0

	world._combat_ctrl.trigger_hotkey_slot("5")
	assert_approx(float(gu_u.get("gcd_timer", 0.0)), 1.25, 0.001, "Slot 5 combat pill executes strictly off-GCD without waiting for or resetting gcd_timer")
	assert_approx(world._combat_ctrl.pill_cooldown_timer, 30.0, 0.05, "30s pill toxicity cooldown started")
	assert_gt(float(gu_actor.hp), 115.0, "Flawless Huichun Powder restored +42% max_hp mid-combat")


func case_t3_w3_03_respec_gear_buckets_poxue_combat() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.unlock_formation("tianfu", true)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_2", "flawless")

	# 1. Allocate 10 points into spi, then respec via 洗髓灵露 into 7 str + 3 agi
	assert_true(CampaignState.allocate_potential_point("gu_changqing", "spi", 10), "Initial +10 spi")
	CampaignState.add_item("item_marrow_dew", 1, true)
	assert_true(CampaignState.reset_potential_points("gu_changqing"), "Respec via item_marrow_dew")
	assert_true(CampaignState.allocate_potential_point("gu_changqing", "str", 7), "Reallocate +7 str")
	assert_true(CampaignState.allocate_potential_point("gu_changqing", "agi", 3), "Reallocate +3 agi")

	# 2. Equip eq_ancient_wood_blade + eq_pendant_poxue & consume item_juqi_pellet_flawless (Bucket C)
	CampaignState.add_item("eq_ancient_wood_blade", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	CampaignState.add_item("item_juqi_pellet_flawless", 1, true)
	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_ancient_wood_blade"), "Equip eq_ancient_wood_blade")
	assert_true(CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_poxue"), "Equip eq_pendant_poxue")
	assert_true(bool(CampaignState.use_out_of_combat_item("item_juqi_pellet_flawless").get("ok", false)), "Consume flawless Juqi elixir")

	var sh: Dictionary = as_dict(as_dict(CampaignState.party_members.get("gu_changqing", {})).get("sheet", {}))
	var bbreak: Dictionary = as_dict(sh.get("bucket_breakdown", {}))
	assert_gt(float(bbreak.get("bucket_a_hp", 0)), float(bbreak.get("bucket_b_hp", 0)), "Bucket A HP > Bucket B HP")
	assert_gt(float(bbreak.get("bucket_c_offense_mult", 1.0)), 1.15, "Bucket C tianfu + flawless Juqi boosts offense > 1.15x")
	assert_le(float(bbreak.get("bucket_c_offense_mult", 9.0)), 1.28, "Bucket C clamped <= 1.28")
	assert_eq(as_arr(sh.get("blue_stunt_ids", [])), ["stunt_poxue_assault"], "Gu active blue stunt == stunt_poxue_assault")

	# 3. Spawn world & execute 破血狂攻 (40 Qi, off-GCD) against armored enemy!
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_cave_mid") as QinglanWorld
	await step_frames(3)

	var banners: Array[String] = []
	var banner_cb: Callable = func(payload: Dictionary) -> void:
		banners.append(str(payload.get("text", "")))
	NotifyHub.combat_banner_pushed.connect(banner_cb)

	var ppos: Vector2 = world._combat_ctrl.get_controlled_actor_pos()
	var golem: BattleActor = world._combat_ctrl.spawn_enemy_unit("wood_golem", ppos + Vector2(150.0, 0.0), "e2e_poxue_test")
	world._combat_ctrl.engage_enemy_group("e2e_poxue_test", "gu_changqing", false)
	world._combat_ctrl.set_locked_enemy(golem.actor_id, false)

	var golem_u: Dictionary = as_dict(world._combat_ctrl.unit_states.get(golem.actor_id, {}))
	golem_u["ward_max"] = 600.0
	golem_u["ward_current"] = 600.0
	golem.ward_max = 600.0
	golem.ward_current = 600.0

	var hp_pre: int = golem.hp
	var ward_pre: float = golem.ward_current
	world._combat_ctrl.team_attunement = 60.0
	var gu_u: Dictionary = as_dict(world._combat_ctrl.unit_states.get("gu_changqing", {}))
	gu_u["gcd_timer"] = 1.10

	world._combat_ctrl.trigger_hotkey_slot("STUNT")
	var cds: Dictionary = as_dict(gu_u.get("cooldowns", {}))
	assert_true(cds.has("stunt_poxue_assault"), "stunt_poxue_assault placed on cooldown after firing")
	assert_lt(world._combat_ctrl.team_attunement, 30.0, "Consumed 40 attunement Qi (+ small gain)")
	assert_lt(float(golem.hp), float(hp_pre), "破血狂攻 dealt direct HP damage to wood_golem")
	assert_lt(golem.ward_current, ward_pre, "破血狂攻 shredded wood_golem Ward")

	var joined_banners: String = "\n".join(banners)
	assert_str_contains(joined_banners, DataDB.loc("STUNT_POXUE_NAME"), "NotifyHub announced 破血狂攻 stunt banner")


func case_t3_w3_04_r3_pause_lpf_and_unshaded_ripple() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)

	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(18)

	var ppos: Vector2 = world._combat_ctrl.get_controlled_actor_pos()
	world._combat_ctrl.spawn_enemy_unit("rot_wolf", ppos + Vector2(220.0, 0.0), "e2e_pause_pack")
	world._combat_ctrl.engage_enemy_group("e2e_pause_pack", "gu_changqing", false)
	assert_true(world._combat_ctrl.in_combat, "Combat active")

	# Press Space -> Tactical Pause + 900Hz LPF on BGM_Bus & Ambient_UI_Bus
	dispatch_input(make_key_event(KEY_SPACE, true))
	await step_frames(2)
	assert_true(world._combat_ctrl.tactical_paused, "Space engages tactical_paused")

	for bus_name: String in ["BGM_Bus", "Ambient_UI_Bus"]:
		var bidx: int = AudioServer.get_bus_index(bus_name)
		assert_ge(float(bidx), 0.0, "Bus '%s' exists" % bus_name)
		if bidx >= 0 and AudioServer.get_bus_effect_count(bidx) > 0:
			assert_true(AudioServer.is_bus_effect_enabled(bidx, 0), "Tactical pause enables LPF on '%s'" % bus_name)
			var eff: AudioEffect = AudioServer.get_bus_effect(bidx, 0)
			if eff is AudioEffectLowPassFilter:
				assert_approx((eff as AudioEffectLowPassFilter).cutoff_hz, 900.0, 1.0, "900Hz LPF cutoff on '%s'" % bus_name)

	world._camera.position_smoothing_enabled = false
	world._camera.position = Vector2(960.0, 860.0)
	world._camera.force_update_scroll()
	await step_frames(2)

	# LMB drag-box across whole screen to select party
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(80.0, 80.0), true))
	dispatch_input(make_mouse_motion_event(Vector2(1840.0, 1000.0)))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(1840.0, 1000.0), false))
	await step_frames(2)
	assert_ge(float(world._combat_ctrl.box_selected_ids.size()), 2.0, "LMB box-selects party during Space pause")

	var gu_actor: BattleActor = world._combat_ctrl.get_controlled_actor()
	var frozen_pos: Vector2 = gu_actor.position
	var frozen_anim_t: float = gu_actor._anim_timer

	# RMB ground click -> spread waypoints + unshaded ui_delta celadon-jade water-ripple
	var dest_world: Vector2 = ppos + Vector2(-95.0, -35.0)
	var dest_scr: Vector2 = world.get_canvas_transform() * dest_world
	Input.warp_mouse(dest_scr)
	dispatch_input(make_mouse_motion_event(dest_scr))
	await step_frames(1)
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, dest_scr, true))
	dispatch_input(make_mouse_button_event(MOUSE_BUTTON_RIGHT, dest_scr, false))

	var img_a: Image = await capture_1080p_subframe(3)
	var img_b: Image = await capture_1080p_subframe(5)

	assert_true(gu_actor.has_move_waypoint, "RMB assigns tactical move_waypoint while paused")
	assert_approx(gu_actor.position.distance_to(frozen_pos), 0.0, 0.01, "Actor position 100% frozen while combat_delta == 0.0")
	assert_approx(gu_actor._anim_timer, frozen_anim_t, 0.001, "Actor sprite _anim_timer 100% frozen while combat_delta == 0.0")

	var vfx_unshaded: bool = _is_canvas_item_unshaded(world._ground_vfx) or _is_canvas_item_unshaded(world._sky_vfx)
	if not vfx_unshaded:
		for ch: Node in world._ground_vfx.get_children():
			if ch is CanvasItem and _is_canvas_item_unshaded(ch as CanvasItem):
				vfx_unshaded = true
				break

	var scr_i: Vector2i = Vector2i(int(round(dest_scr.x)), int(round(dest_scr.y)))
	var ripple_diff: float = _mean_abs_diff_in_rect(img_a, img_b, Rect2i(scr_i.x - 42, scr_i.y - 28, 84, 56))
	assert_true(vfx_unshaded, "Polish R3 RMB water-ripple renders unshaded")
	assert_gt(ripple_diff, 0.004, "Polish R3 RMB water-ripple animates via live ui_delta while combat_delta == 0.0")


func case_t3_w3_05_r3_discount_brew_tome_tour() -> void:
	SaveManager.reduced_motion = false
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.faction_reputation["jishi_pharmacy"] = 1000 # 95折
	CampaignState.spirit_stones = 200

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(3)

	# 1. Buy discounted herb (base 24 -> 95折 == 23)
	world._modals.open_shop_modal("shop_yaolu_pharmacy")
	await step_frames(2)
	var herb_name: String = DataDB.loc("ITEM_NINGQI_HERB_NAME")
	var herb_buy_btn: Button = null
	var stack: Array[Node] = [world._modals]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is PanelContainer:
			var pc: PanelContainer = cur as PanelContainer
			if pc.get_parent() is VBoxContainer and _join_visible_texts(pc).contains("【%s】· 23 灵石" % herb_name):
				herb_buy_btn = _find_button_containing(pc, "购入")
				if herb_buy_btn != null:
					break
		for ch: Node in cur.get_children():
			stack.append(ch)
	assert_not_null(herb_buy_btn, "Yaolu pharmacy offers 95折 (23 灵石) Ningqi Herb at 1000 rep")
	if herb_buy_btn != null:
		herb_buy_btn.pressed.emit()
	await step_frames(2)
	assert_eq(CampaignState.spirit_stones, 177, "Paid discounted 23 Spirit Stones")
	world._modals.close_modal()

	# 2. Brew in flickering-flame cauldron
	CampaignState.add_item("item_ningqi_herb", 2, true)
	CampaignState.add_item("item_qingmu_leaf", 2, true)
	world._modals.open_alchemy_furnace("recipe_huichun_powder")
	await step_frames(2)
	var sbtn: Button = _find_button_containing(world._modals, "15秒")
	if sbtn != null:
		sbtn.pressed.emit()
	await step_frames(2)

	var cauldron_found: bool = false
	var st2: Array[Node] = [world._modals]
	while not st2.is_empty():
		var n2: Node = st2.pop_back()
		if (n2 is TextureRect and (n2 as TextureRect).texture != null and (n2 as Control).size.y >= 110.0) or (n2 is GPUParticles2D) or (n2 is CPUParticles2D):
			cauldron_found = true
			break
		if n2 is Control and n2.get_script() != null and n2 != world._modals and (n2 as Control).size.y >= 110.0 and obj_has_method(n2, "_draw"):
			cauldron_found = true
			break
		for c2: Node in n2.get_children():
			st2.append(c2)

	world._modals.close_modal()

	# 3. Equip blue-stunt pendant & tour Thread-Bound Xuan Tome C -> N -> B -> J -> Esc
	CampaignState.add_item("eq_pendant_jingqing", 1, true)
	CampaignState.add_item("eq_pendant_poxue", 1, true)
	CampaignState.equip_item_on_member("gu_changqing", "eq_pendant_jingqing")
	world._casket.selected_item_id = "eq_pendant_poxue"

	var tweens_pre: int = tree.get_processed_tweens().size()
	dispatch_input(make_key_event(KEY_C, true))
	var tweens_post: int = tree.get_processed_tweens().size()
	await step_frames(4)

	var sky_target: Color = Color("#8FD4E8")
	var sky_ok: bool = (
		absf(UIThemeBuilder.COL_BLUE_STUNT.r - sky_target.r) <= 0.08
		and absf(UIThemeBuilder.COL_BLUE_STUNT.g - sky_target.g) <= 0.08
		and absf(UIThemeBuilder.COL_BLUE_STUNT.b - sky_target.b) <= 0.08
	)
	var icon_cnt: int = collect_visible_texture_rects(world._casket).size()

	dispatch_input(make_key_event(KEY_N, true))
	await step_frames(2)
	assert_eq(world._casket.active_tab, "specialization", "Switched to N")
	dispatch_input(make_key_event(KEY_B, true))
	await step_frames(2)
	assert_eq(world._casket.active_tab, "inventory", "Switched to B")
	dispatch_input(make_key_event(KEY_J, true))
	await step_frames(2)
	assert_eq(world._casket.active_tab, "journal", "Switched to J")

	dispatch_input(make_key_event(KEY_ESCAPE, true))
	await step_frames(2)
	assert_false(world._casket.visible, "Esc closes DaoCasketPanel")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Esc restores MODE_WORLD_COMBAT")
	assert_null(tree.root.gui_get_focus_owner(), "Zero trapped GUI focus after Esc")

	assert_true(cauldron_found, "Polish R3 alchemy furnace includes bronze cauldron + flickering flame visual")
	assert_gt(float(tweens_post), float(tweens_pre), "Polish R3 opening casket spawns unfold Tween")
	assert_ge(float(icon_cnt), 5.0, "Polish R3 Tab 1 renders meridian + 3+2 embossed icon slots")
	assert_true(sky_ok, "Polish R3 stunt highlight color matches #8FD4E8 sky-blue")
