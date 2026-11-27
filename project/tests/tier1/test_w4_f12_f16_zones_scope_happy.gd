extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 1
# @e2e_features: F12, F16


func register_cases() -> void:
	add_case(
		"T1-F12-01",
		1,
		"F12",
		"baseline",
		"Seamless 3-zone transitions (tingyu_town <-> qinglan_pass <-> cangmu_cave), scene_epoch & spawn coords",
		"case_t1_f12_01_seamless_three_zone_transitions"
	)
	add_case(
		"T1-F12-02",
		1,
		"F12",
		"baseline",
		"Stealth talisman (-70% aggro, 20s, 0.52 alpha) bypasses wood_golem for herb/chest and breaks on combat",
		"case_t1_f12_02_stealth_talisman_branch"
	)
	add_case(
		"T1-F12-03",
		1,
		"F12",
		"baseline",
		"cangmu_cave Fire vine barrier, Water miasma pool cleanse, ancient_remains & north shortcut_gate",
		"case_t1_f12_03_cave_barriers_remains_and_shortcut"
	)
	add_case(
		"T1-F12-04",
		1,
		"F12",
		"baseline",
		"Spirit Stele full heal, meridian_bruise clear, Sword Box finish, night_talk_1 bond ult & fast travel",
		"case_t1_f12_04_spirit_stele_rest_talk_and_teleport"
	)
	add_case(
		"T1-F12-05",
		1,
		"F12",
		"baseline",
		"Peddler shard -> bamboo rogue ambush -> bloodied pouch loot & injured beast pet rescue",
		"case_t1_f12_05_rogue_ambush_pouch_and_pet_rescue"
	)
	add_case(
		"T1-F12-06",
		1,
		"F12",
		"baseline",
		"Golden Core cliff vista clue/bark foreshadowing & M hand-drawn Qinglan ink map modal",
		"case_t1_f12_06_cliff_vista_and_ink_map"
	)
	add_case(
		"T1-F16-04",
		1,
		"F16",
		"baseline",
		"Chapter 1 ch01_qinglan 3-zone & 8-core-system runtime scope lock",
		"case_t1_f16_04_ch01_runtime_scope_lock"
	)


func _advance_dialogue_to_end(world: QinglanWorld, choice_label_key: String = "") -> void:
	var guard: int = 0
	while world._narrative.visible and guard < 60:
		guard += 1
		InputRouter._process(0.50)
		if world._narrative._cg_active:
			dispatch_input(make_key_event(KEY_ENTER, true))
			dispatch_input(make_key_event(KEY_ENTER, false))
			await step_frames(1)
			continue
		if world._narrative._choices_box.visible:
			var want_label: String = DataDB.loc(choice_label_key) if choice_label_key != "" else ""
			var clicked: bool = false
			for ch: Node in world._narrative._choices_box.get_children():
				if ch is Button:
					var btn: Button = ch as Button
					if want_label == "" or btn.text.contains(want_label):
						btn.pressed.emit()
						clicked = true
						break
			if not clicked:
				break
			await step_frames(1)
			continue
		dispatch_input(make_key_event(KEY_ENTER, true))
		dispatch_input(make_key_event(KEY_ENTER, false))
		await step_frames(1)


func _run_combat_until_resolved(world: QinglanWorld, max_ticks: int = 2400) -> int:
	var ticks: int = 0
	var hotkeys: Array[String] = ["1", "2", "3", "Q", "R"]
	while world._combat_ctrl.in_combat and ticks < max_ticks:
		if ticks % 24 == 0:
			var rot_i: int = int(float(ticks) / 24.0) % hotkeys.size()
			var hk: String = hotkeys[rot_i]
			world._combat_ctrl.trigger_hotkey_slot(hk)
		if ticks % 90 == 0 and world._combat_ctrl.pet_actor != null:
			world._combat_ctrl.trigger_pet_manual_skill(1)
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
		ticks += 1
	return ticks


func case_t1_f12_01_seamless_three_zone_transitions() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	var epoch_start: int = CampaignState.scene_epoch
	assert_eq(CampaignState.current_zone_id, "tingyu_town", "Starts in tingyu_town")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(360.0, 790.0)),
		6.0,
		"Spawns at tingyu_town south entry coords"
	)

	# 1. Step into northeast town portal Rect2(2265, 505, 130, 210) -> qinglan_pass
	var gu_1: BattleActor = world._combat_ctrl.get_controlled_actor()
	assert_not_null(gu_1, "Controlled party actor exists in tingyu_town")
	gu_1.position = Vector2(2310.0, 610.0)
	world._physics_process(1.0 / 60.0)
	await step_frames(2)

	assert_eq(CampaignState.current_zone_id, "qinglan_pass", "Transitioned tingyu_town -> qinglan_pass")
	assert_eq(CampaignState.scene_epoch, epoch_start + 1, "scene_epoch incremented on 1st portal hop")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(220.0, 960.0)),
		6.0,
		"Placed at qinglan_pass south entry coords"
	)
	assert_eq(world._notify_overlay._floaters.size(), 0, "0 residual combat floaters after zone transition")

	# 2. Unlock temple cave portal and step into Rect2(2060, 565, 150, 130) -> cangmu_cave
	CampaignState.world_flags["met_pei_zhao"] = true
	CampaignState.cleared_encounters["enc_temple_wolves"] = true
	world.load_zone("qinglan_pass", "stele_temple_courtyard", false)
	await step_frames(2)
	assert_eq(CampaignState.scene_epoch, epoch_start + 2, "scene_epoch incremented on temple reload")

	var gu_2: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu_2.position = Vector2(2120.0, 625.0)
	world._physics_process(1.0 / 60.0)
	await step_frames(2)

	assert_eq(CampaignState.current_zone_id, "cangmu_cave", "Transitioned qinglan_pass -> cangmu_cave")
	assert_eq(CampaignState.scene_epoch, epoch_start + 3, "scene_epoch incremented on cave portal hop")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(240.0, 1090.0)),
		6.0,
		"Placed at cangmu_cave entrance coords"
	)

	# 3. Return via cave exit portal Rect2(35, 1005, 130, 170) -> qinglan_pass (from_cave)
	var gu_3: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu_3.position = Vector2(95.0, 1085.0)
	world._physics_process(1.0 / 60.0)
	await step_frames(2)

	assert_eq(CampaignState.current_zone_id, "qinglan_pass", "Returned cangmu_cave -> qinglan_pass")
	assert_eq(CampaignState.scene_epoch, epoch_start + 4, "scene_epoch incremented on return hop")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(1950.0, 645.0)),
		6.0,
		"Placed at exact from_cave spawn coords Vector2(1950, 645)"
	)


func case_t1_f12_02_stealth_talisman_branch() -> void:
	var base_talisman: int = CampaignState.get_item_count("item_stealth_talisman")
	if base_talisman < 2:
		CampaignState.add_item("item_stealth_talisman", 2 - base_talisman, true)
	var tal_before: int = CampaignState.get_item_count("item_stealth_talisman")

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "cave_entry") as QinglanWorld
	await step_frames(2)

	var golem: BattleActor = null
	for ea: BattleActor in world._combat_ctrl.enemy_actors:
		var eu: Dictionary = world._combat_ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("enemy_def_id", "")) == "wood_golem":
			golem = ea
			assert_approx(float(eu.get("aggro_radius_px", 0.0)), 250.0, 0.5, "wood_golem base aggro is 250px")
			break
	assert_not_null(golem, "wood_golem spawned in cangmu_cave stealth branch")
	golem.patrol_points.clear()
	golem.position = Vector2(980.0, 430.0)
	golem.home_pos = Vector2(980.0, 430.0)

	var activated: bool = world._combat_ctrl.activate_stealth_talisman()
	assert_true(activated, "activate_stealth_talisman() succeeded out of combat")
	assert_eq(CampaignState.get_item_count("item_stealth_talisman"), tal_before - 1, "Consumed 1 stealth talisman")
	assert_approx(world._combat_ctrl.stealth_timer, 20.0, 0.05, "Stealth duration initialized to 20.0s")

	# Stand 120px north of wood_golem (inside 250px normal aggro, outside 250*0.30=75px stealth aggro)
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(980.0, 310.0)
	for _i: int in range(30):
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)

	assert_false(world._combat_ctrl.in_combat, "120px distance does NOT aggro wood_golem under -70% stealth")
	assert_approx(gu.stealth_alpha, 0.52, 0.02, "Party actor stealth_alpha is 0.52 while stealthed")

	# Loot herb_cave_stealth & chest_poxue_pendant without triggering combat
	var flowers_before: int = CampaignState.get_item_count("item_corrupt_flower")
	var stones_before: int = CampaignState.spirit_stones
	gu.position = Vector2(835.0, 245.0)
	world._try_interact_nearest()
	assert_eq(
		CampaignState.get_item_count("item_corrupt_flower"),
		flowers_before + 2,
		"herb_cave_stealth granted item_corrupt_flower x2"
	)

	gu.position = Vector2(1125.0, 250.0)
	world._try_interact_nearest()
	assert_eq(CampaignState.get_item_count("eq_pendant_poxue"), 1, "chest_poxue_pendant granted eq_pendant_poxue")
	assert_eq(CampaignState.spirit_stones, stones_before + 65, "chest_poxue_pendant granted +65 Spirit Stones")

	# Engaging combat immediately breaks stealth
	world._combat_ctrl.engage_enemy_group("enc_cave_golem", "gu_changqing", true)
	world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_true(world._combat_ctrl.in_combat, "Engaged wood_golem")
	assert_approx(world._combat_ctrl.stealth_timer, 0.0, 0.001, "Engaging combat immediately breaks stealth_timer")
	assert_approx(gu.stealth_alpha, 1.0, 0.001, "stealth_alpha immediately restores to 1.0 in combat")


func case_t1_f12_03_cave_barriers_remains_and_shortcut() -> void:
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "cave_entry") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()

	# 1. Fire barrier: burn vine wall at Vector2(640, 1085)
	var blocked_before: Vector2 = world._combat_ctrl._resolve_move_collision(
		Vector2(560.0, 1085.0), Vector2(640.0, 1085.0), QinglanWorld.ZONE_BOUNDS
	)
	assert_gt(blocked_before.distance_to(Vector2(640.0, 1085.0)), 40.0, "Vine barrier blocks passage before burning")

	gu.position = Vector2(580.0, 1085.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("vine_wall_burned", false)), "vine_wall_burned flag set")
	var unblocked_after: Vector2 = world._combat_ctrl._resolve_move_collision(
		Vector2(560.0, 1085.0), Vector2(640.0, 1085.0), QinglanWorld.ZONE_BOUNDS
	)
	assert_lt(unblocked_after.distance_to(Vector2(640.0, 1085.0)), 1.0, "Vine obstacle circle cleared after burning")

	# 2. Water barrier: cleanse miasma pool at Vector2(1120, 1155)
	var dew_before: int = CampaignState.get_item_count("item_marrow_dew")
	gu.position = Vector2(1060.0, 1155.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("miasma_pool_cleansed", false)), "miasma_pool_cleansed flag set")
	assert_eq(CampaignState.get_item_count("item_marrow_dew"), dew_before + 1, "Cleansing pool grants item_marrow_dew")

	var pool_tex_path: String = ""
	for inter: Dictionary in world._interactables:
		if str(inter.get("id", "")) == "barrier_pool":
			var sp: Sprite2D = inter.get("sprite", null) as Sprite2D
			if sp != null and sp.texture != null:
				pool_tex_path = sp.texture.resource_path
	assert_str_contains(pool_tex_path, "prop_miasma_pool_clean.png", "Pool sprite swapped to cleansed texture")

	# 3. Ancient remains at Vector2(1310, 1165) -> dlg_ch01_ancient_remains
	gu.position = Vector2(1260.0, 1165.0)
	world._try_interact_nearest()
	assert_true(world._narrative.visible, "ancient_remains starts dlg_ch01_ancient_remains after pool cleanse")
	await _advance_dialogue_to_end(world)
	assert_ge(CampaignState.get_item_count("eq_ancient_wood_blade"), 1, "ancient_remains grants eq_ancient_wood_blade")
	assert_true(
		CampaignState.unlocked_clues.has("clue_ancient_stele_ch01"),
		"ancient_remains unlocks clue_ancient_stele_ch01"
	)

	# 4. North corridor shortcut_gate at Vector2(490, 885) approached from y=820 (<= 895)
	gu.position = Vector2(490.0, 820.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("shortcut_gate_opened", false)), "shortcut_gate_opened flag set")
	var gate_pass: Vector2 = world._combat_ctrl._resolve_move_collision(
		Vector2(490.0, 820.0), Vector2(490.0, 885.0), QinglanWorld.ZONE_BOUNDS
	)
	assert_lt(gate_pass.distance_to(Vector2(490.0, 885.0)), 1.0, "Shortcut gate obstacle cleared")


func case_t1_f12_04_spirit_stele_rest_talk_and_teleport() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.contract_spirit_pet("pet_fire_fox")
	CampaignState.pet_hp_ratio = 0.20
	if not CampaignState.unlocked_steles.has("stele_tingyu_gate"):
		CampaignState.unlocked_steles.append("stele_tingyu_gate")

	CampaignState.add_item("item_burnt_pill", 1, true)
	assert_true(CampaignState.start_sword_box_purify("item_burnt_pill"), "Loaded item_burnt_pill into Sword Box")
	assert_eq(int(CampaignState.sword_box_slot.get("battles_remaining", -1)), 3, "Sword Box starts at 3 battles")

	var gu_m: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	gu_m["meridian_bruise"] = 3
	CampaignState.recalculate_all_party_stats(false)
	gu_m["hp"] = 25
	gu_m["mp"] = 5

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_cave_mid") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1290.0, 755.0)
	world._try_interact_nearest()

	assert_true(world._modals.visible, "Stele modal opened")
	assert_eq(world._modals._active_kind, "stele", "Active modal kind is stele")
	assert_true(CampaignState.unlocked_steles.has("stele_cave_mid"), "stele_cave_mid added to unlocked_steles")

	var gu_after: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	var gu_sheet: Dictionary = gu_after.get("sheet", {}) as Dictionary
	assert_eq(int(gu_after.get("meridian_bruise", -1)), 0, "Stele rest cleared meridian_bruise stacks to 0")
	assert_eq(int(gu_after.get("hp", 0)), int(gu_sheet.get("max_hp", -1)), "Stele rest restored full HP")
	assert_eq(int(gu_after.get("mp", 0)), int(gu_sheet.get("max_mp", -1)), "Stele rest restored full MP")
	assert_approx(CampaignState.pet_hp_ratio, 1.0, 0.001, "Stele rest restored pet_hp_ratio to 1.0")
	assert_eq(
		int(CampaignState.sword_box_slot.get("battles_remaining", -1)),
		0,
		"Stele rest completed Sword Box purification (battles_remaining == 0)"
	)

	# Trigger night_talk_1 from stele modal
	var btns_talk: Array[Button] = collect_visible_buttons(world._modals)
	var triggered_talk: bool = false
	for b: Button in btns_talk:
		if b.text.contains("夜话一"):
			b.pressed.emit()
			triggered_talk = true
			break
	assert_true(triggered_talk, "Clicked night_talk_1 button in stele modal")
	assert_true(world._narrative.visible, "dlg_night_talk_1 started")
	await _advance_dialogue_to_end(world)
	assert_ge(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), 2, "Shen Qinghe bond raised to Tier >= 2")
	assert_true(
		CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"),
		"night_talk_1 unlocked Bond Ultimate ult_qinglian_sword"
	)

	# Re-open stele modal and teleport to stele_tingyu_gate
	world._try_interact_nearest()
	var btns_tp: Array[Button] = collect_visible_buttons(world._modals)
	var triggered_tp: bool = false
	for b2: Button in btns_tp:
		if b2.text.contains("听雨镇") and not b2.disabled:
			b2.pressed.emit()
			triggered_tp = true
			break
	assert_true(triggered_tp, "Clicked teleport button for stele_tingyu_gate")
	await step_frames(2)

	assert_eq(CampaignState.current_zone_id, "tingyu_town", "Fast traveled to tingyu_town")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(1855.0, 645.0)),
		6.0,
		"Teleported to exact stele_tingyu_gate coords Vector2(1855, 645)"
	)


func case_t1_f12_05_rogue_ambush_pouch_and_pet_rescue() -> void:
	# rtwp_combat_controller.gd:1720 on v0.1.3-slice has unescaped '35%' in Ward-Break banner format string
	allow_expected_engine_error("unsupported format character")
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	# Buy item_stall_sword_shard via peddler modal with >=60 stone confirmation
	world._modals.open_shop_modal("shop_tingyu_peddler", "item_stall_sword_shard")
	var confirm_txt: String = tr("UI_BTN_CONFIRM")
	var bought: bool = false
	for b: Button in collect_visible_buttons(world._modals):
		if b.text == confirm_txt:
			b.pressed.emit()
			bought = true
			break
	assert_true(bought, "Confirmed 60-stone purchase of item_stall_sword_shard")
	assert_true(bool(CampaignState.world_flags.get("peddler_gem_bought", false)), "peddler_gem_bought flag set")
	world._modals.close_modal()

	# Transition to qinglan_pass
	world.load_zone("qinglan_pass", "from_town", false)
	await step_frames(2)

	# 1. Rescue injured beast -> contract pet_fire_fox
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(560.0, 520.0)
	world._try_interact_nearest()
	assert_true(world._narrative.visible, "injured_beast started dlg_ch01_rescue_beast")
	await _advance_dialogue_to_end(world, "CHOICE_PET_FOX")
	assert_eq(CampaignState.active_pet_id, "pet_fire_fox", "Contracted starter pet pet_fire_fox")
	assert_not_null(world._combat_ctrl.pet_actor, "pet_actor spawned in world")

	# 2. Walk near bamboo ambush trigger Vector2(1120, 820)
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1120.0, 820.0)
	world._physics_process(1.0 / 60.0)
	assert_true(world._narrative.visible, "Bamboo rogue ambush dialogue triggered automatically")
	await _advance_dialogue_to_end(world)
	assert_true(world._combat_ctrl.in_combat, "enc_rogue_ambush combat engaged")

	_run_combat_until_resolved(world, 2400)
	assert_false(world._combat_ctrl.in_combat, "Defeated enc_rogue_ambush")
	assert_true(bool(CampaignState.world_flags.get("rogue_ambush_cleared", false)), "rogue_ambush_cleared flag set")
	assert_eq(CampaignState.get_item_count("item_bloodied_pouch"), 1, "Granted item_bloodied_pouch")

	# 3. Open item_bloodied_pouch
	var stones_pre: int = CampaignState.spirit_stones
	var tal_pre: int = CampaignState.get_item_count("item_stealth_talisman")
	var flw_pre: int = CampaignState.get_item_count("item_corrupt_flower")
	var pouch_res: Dictionary = CampaignState.use_out_of_combat_item("item_bloodied_pouch")
	assert_true(bool(pouch_res.get("ok", false)), "Opened item_bloodied_pouch")
	assert_eq(CampaignState.spirit_stones, stones_pre + 110, "Bloodied pouch granted +110 Spirit Stones")
	assert_eq(CampaignState.get_item_count("item_yaolu_jade_token"), 1, "Bloodied pouch granted item_yaolu_jade_token")
	assert_eq(CampaignState.get_item_count("item_stealth_talisman"), tal_pre + 2, "Granted stealth talisman x2")
	assert_eq(CampaignState.get_item_count("item_corrupt_flower"), flw_pre + 2, "Granted corrupt flower x2")
	assert_true(CampaignState.unlocked_recipes.has("recipe_qingmu_pill"), "Unlocked recipe_qingmu_pill")
	assert_true(CampaignState.unlocked_clues.has("clue_yaolu_spy_token"), "Unlocked clue_yaolu_spy_token")


func case_t1_f12_06_cliff_vista_and_ink_map() -> void:
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1385.0, 895.0)
	world._try_interact_nearest()

	assert_true(
		CampaignState.unlocked_clues.has("clue_golden_core_cliff"),
		"cliff_chest_vista unlocked clue_golden_core_cliff"
	)
	assert_true(gu.has_active_bark(), "Controlled actor displays Golden Core foreshadowing world bark")
	assert_str_contains(gu._bark_text, "金丹", "Cliff vista bark mentions Golden Core (金丹)")
	assert_str_contains(gu._bark_text, "御剑飞行", "Cliff vista bark mentions sword-flight (御剑飞行)")

	dispatch_input(make_key_event(KEY_M, true))
	dispatch_input(make_key_event(KEY_M, false))
	await step_frames(2)

	assert_true(world._modals.visible, "Pressing M opened Qinglan world map modal")
	assert_eq(world._modals._active_kind, "map", "Modal _active_kind is 'map'")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "InputRouter switched to MODE_MODAL_MENU")

	var map_header_joined: String = ""
	for lbl: Label in collect_visible_labels(world._modals):
		map_header_joined += lbl.text + " "
	assert_str_contains(map_header_joined, "青岚境", "Map header shows 青岚境")
	assert_str_contains(map_header_joined, "无自动寻路", "Map header states zero auto-pathfinding")

	for btn: Button in collect_visible_buttons(world._modals):
		assert_str_not_contains(btn.text, "自动寻路", "Zero auto-pathfinding buttons in ink map modal")


func case_t1_f16_04_ch01_runtime_scope_lock() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	assert_eq(CampaignState.chapter_id, "ch01_qinglan", "Active campaign locked to ch01_qinglan")

	# Playable roster locked to Ch1 trio (no premature Ch2 lu_xuansong)
	var char_keys: Array = DataDB.characters.keys()
	assert_eq(char_keys.size(), 3, "Ch1 DataDB.characters exposes exact 3 playable characters")
	assert_true(DataDB.characters.has("gu_changqing"), "Has gu_changqing")
	assert_true(DataDB.characters.has("shen_qinghe"), "Has shen_qinghe")
	assert_true(DataDB.characters.has("pei_zhao"), "Has pei_zhao")
	assert_false(DataDB.characters.has("lu_xuansong"), "Ch2 companion lu_xuansong not prematurely exposed")

	# DaoCasketPanel locked to exact 4 Ch1 tabs (C/N/B/J; zero E2 Reforge, E4 Dispatch, or P Pet-book tabs)
	world._casket.open_tab("cultivation")
	await step_frames(1)
	assert_eq(world._casket._tab_buttons.size(), 4, "DaoCasketPanel exposes exact 4 Ch1 tabs")
	for tab_id: String in ["cultivation", "specialization", "inventory", "journal"]:
		assert_true(world._casket._tab_buttons.has(tab_id), "DaoCasketPanel has Ch1 tab: " + tab_id)
	for forbidden_tab: String in ["pet", "reforge", "dispatch", "auction"]:
		assert_false(world._casket._tab_buttons.has(forbidden_tab), "No premature extended tab: " + forbidden_tab)
	world._casket.close_casket()

	# All zone portals across all 3 zones remain strictly inside the 3 Ch1 zones
	var allowed_zones: Array[String] = ["tingyu_town", "qinglan_pass", "cangmu_cave"]
	CampaignState.world_flags["met_pei_zhao"] = true
	CampaignState.cleared_encounters["enc_temple_wolves"] = true
	for zid: String in allowed_zones:
		world.load_zone(zid, "", false)
		await step_frames(2)
		assert_gt(world._zone_portals.size(), 0, zid + " has >= 1 seamless zone portal")
		for portal: Dictionary in world._zone_portals:
			var tzone: String = str(portal.get("target_zone", ""))
			assert_true(allowed_zones.has(tzone), "Portal in %s targets allowed Ch1 zone (%s)" % [zid, tzone])

	# Sole currency lock
	assert_true(obj_has_prop(CampaignState, "spirit_stones"), "Sole currency spirit_stones exists")
	for extra_curr: String in ["jade_ingots", "gold_coins", "sect_tokens", "vouchers"]:
		assert_false(obj_has_prop(CampaignState, extra_curr), "Zero secondary currency property: " + extra_curr)
