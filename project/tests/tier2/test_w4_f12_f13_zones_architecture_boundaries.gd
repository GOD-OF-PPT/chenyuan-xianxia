extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 2
# @e2e_features: F12, F13


func register_cases() -> void:
	add_case(
		"T2-F12-01",
		2,
		"F12",
		"baseline",
		"Boss ignores stealth talisman (-70% aggro bypassed) and mid-combat / 0-stock stealth activation is rejected",
		"case_t2_f12_01_boss_ignores_stealth_and_combat_block"
	)
	add_case(
		"T2-F12-02",
		2,
		"F12",
		"baseline",
		"South-side shortcut_gate and pre-cleanse ancient_remains reject premature interaction",
		"case_t2_f12_02_shortcut_south_and_remains_precleanse_reject"
	)
	add_case(
		"T2-F12-03",
		2,
		"F12",
		"baseline",
		"+2 realm suppression (+35% dmg taken, -15% speed) & Golden Core cliff abyss air-wall block",
		"case_t2_f12_03_realm_suppression_and_cliff_abyss_airwall"
	)
	add_case(
		"T2-F12-04",
		2,
		"F12",
		"baseline",
		"Line-of-Sight rock cover blocks ranged shaman aggro & cone_120 back-approach respects 0.48x inner radius",
		"case_t2_f12_04_los_cover_and_cone120_back_aggro"
	)
	add_case(
		"T2-F12-05",
		2,
		"F12",
		"baseline",
		"Active spirit pet cap is strictly 1 on pet swap and mid-combat zone portal overlap is 100% ignored",
		"case_t2_f12_05_single_pet_cap_and_midcombat_portal_block"
	)
	add_case(
		"T2-F13-01",
		2,
		"F13",
		"baseline",
		"Canonical 济世药庐 plaque/name enforced across world props, modals & zh_CN.csv (0 濟世堂/济世堂)",
		"case_t2_f13_01_canonical_jishi_yaolu_name_guard"
	)
	add_case(
		"T2-F13-02",
		2,
		"F13",
		"baseline",
		"16-ray walkable reachability guard on 100% of _interactables & _npc_actors across all 3 zones",
		"case_t2_f13_02_sixteen_ray_interactable_reachability"
	)
	add_case(
		"T2-F13-03",
		2,
		"F13",
		"baseline",
		"Underground cangmu_cave contains 0 outdoor trees/bamboo sprites and 0 outdoor rain streaks",
		"case_t2_f13_03_cave_zero_outdoor_trees_and_rain"
	)
	add_case(
		"T2-F13-05",
		2,
		"F13",
		"baseline",
		"Full 3-zone cycle (tingyu -> pass -> cave -> tingyu) leaks 0 Y-Sort children, occluders, or obstacles",
		"case_t2_f13_05_zero_zone_cycle_node_or_obstacle_leaks"
	)


func case_t2_f12_01_boss_ignores_stealth_and_combat_block() -> void:
	# Normalize stealth talisman stock to exact 1
	var cur_tal: int = CampaignState.get_item_count("item_stealth_talisman")
	if cur_tal > 1:
		CampaignState.remove_item("item_stealth_talisman", cur_tal - 1)
	elif cur_tal < 1:
		CampaignState.add_item("item_stealth_talisman", 1 - cur_tal, true)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)

	assert_true(world._combat_ctrl.activate_stealth_talisman(), "Activated stealth with 1 talisman")
	assert_eq(CampaignState.get_item_count("item_stealth_talisman"), 0, "Stock reached 0")
	assert_false(world._combat_ctrl.activate_stealth_talisman(), "0-stock stealth activation rejected")

	# Add 1 talisman to verify mid-combat rejection does not consume it
	CampaignState.add_item("item_stealth_talisman", 1, true)
	world._combat_ctrl.stealth_timer = 20.0

	var boss: BattleActor = null
	for ea: BattleActor in world._combat_ctrl.enemy_actors:
		if ea.is_boss:
			boss = ea
			break
	assert_not_null(boss, "boss_mist_wolf_king exists in cangmu_cave")
	if boss == null:
		return

	# Place Gu Changqing at 200px from Boss (inside 245px aggro; would be ignored if -70% stealth applied)
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = boss.position + Vector2(-200.0, 0.0)
	assert_false(
		world._combat_ctrl._is_line_of_sight_blocked(boss.position, gu.position),
		"Clear LoS between Boss and party at 200px"
	)

	world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_true(world._combat_ctrl.in_combat, "Boss ignores stealth talisman and engages party at 200px")
	assert_approx(world._combat_ctrl.stealth_timer, 0.0, 0.001, "Boss engagement immediately clears stealth_timer")

	# Attempt mid-combat stealth activation
	var mid_combat_try: bool = world._combat_ctrl.activate_stealth_talisman()
	assert_false(mid_combat_try, "Mid-combat activate_stealth_talisman() rejected")
	assert_eq(CampaignState.get_item_count("item_stealth_talisman"), 1, "Mid-combat rejection consumed 0 talismans")


func case_t2_f12_02_shortcut_south_and_remains_precleanse_reject() -> void:
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "cave_entry") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()

	# 1. Approach shortcut_gate (490, 885) from south entrance side (y=960 > 895)
	gu.position = Vector2(490.0, 960.0)
	world._try_interact_nearest()
	assert_false(
		bool(CampaignState.world_flags.get("shortcut_gate_opened", false)),
		"shortcut_gate refuses to open from south entrance side (y > 895)"
	)
	assert_true(gu.has_active_bark(), "Controlled actor barks north-corridor mechanism hint")
	assert_str_contains(gu._bark_text, "北侧", "South shortcut bark explains north-corridor mechanism")

	var blocked_gate: Vector2 = world._combat_ctrl._resolve_move_collision(
		Vector2(490.0, 990.0), Vector2(490.0, 885.0), QinglanWorld.ZONE_BOUNDS
	)
	assert_gt(blocked_gate.distance_to(Vector2(490.0, 885.0)), 40.0, "Shortcut collision obstacle remains active")

	# 2. Approach ancient_remains (1310, 1165) BEFORE miasma_pool_cleansed is true
	assert_false(bool(CampaignState.world_flags.get("miasma_pool_cleansed", false)), "Pool initially uncleansed")
	gu.position = Vector2(1285.0, 1165.0)
	world._try_interact_nearest()
	assert_false(world._narrative.visible, "ancient_remains refuses dialogue before barrier_pool is cleansed")
	assert_false(
		CampaignState.read_dialogues.has("dlg_ch01_ancient_remains"),
		"dlg_ch01_ancient_remains not marked read before cleanse"
	)
	assert_eq(CampaignState.get_item_count("eq_ancient_wood_blade"), 0, "0 blade granted before pool cleanse")
	assert_true(gu.has_active_bark(), "Controlled actor barks pool-cleanse prerequisite")
	assert_str_contains(gu._bark_text, "净化", "Remains bark instructs cleansing miasma pool first")


func case_t2_f12_03_realm_suppression_and_cliff_abyss_airwall() -> void:
	# 1. +2 Realm suppression math (+35% damage taken, -15% move speed)
	var cdef: Dictionary = DataDB.get_character("gu_changqing")
	var rdef: Dictionary = DataDB.get_realm("mortal")
	var sh_0: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, {}, "solid", [], DataDB.equip_sets, {}, {}, {}, {}, 0, 0
	)
	var sh_2: Dictionary = StatLedger.compute_character_sheet(
		cdef, rdef, {}, "solid", [], DataDB.equip_sets, {}, {}, {}, {}, 0, 2
	)
	var dmg_ratio: float = float(sh_2.get("damage_taken_mult", 1.0)) / float(sh_0.get("damage_taken_mult", 1.0))
	var spd_ratio: float = float(sh_2.get("move_speed_px", 1.0)) / float(sh_0.get("move_speed_px", 1.0))
	assert_approx(dmg_ratio, 1.35, 0.01, "+2 realm suppression multiplies damage_taken_mult by 1.35x (+35%)")
	assert_approx(spd_ratio, 0.85, 0.01, "+2 realm suppression multiplies move_speed_px by 0.85x (-15%)")

	# 2. Golden Core cliff abyss air-wall blocks walking to far-pinnacle chest Vector2(1765, 1095)
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	var far_chest_pos: Vector2 = Vector2(1765.0, 1095.0)
	gu.position = Vector2(1385.0, 895.0)
	for _step: int in range(180):
		var step_dir: Vector2 = (far_chest_pos - gu.position).normalized()
		gu.position = world._combat_ctrl._resolve_move_collision(
			gu.position, gu.position + step_dir * 8.0, QinglanWorld.ZONE_BOUNDS
		)

	var final_dist: float = gu.position.distance_to(far_chest_pos)
	record_metric("min_dist_to_far_cliff_chest_px", snappedf(final_dist, 0.1))
	assert_gt(
		final_dist,
		260.0,
		"Golden Core cliff abyss air-wall 100% blocks foot movement from reaching Vector2(1765, 1095)"
	)


func case_t2_f12_04_los_cover_and_cone120_back_aggro() -> void:
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(2)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()

	# 1. LoS cover behind prop_cliff_rock at Vector2(690, 740) -> obstacle circle at (690, 716), r=68
	var shaman: BattleActor = world._combat_ctrl.spawn_enemy_unit(
		"miasma_shaman", Vector2(760.0, 770.0), "enc_los_test"
	)
	assert_not_null(shaman, "Spawned miasma_shaman (aggro 265px)")
	gu.position = Vector2(620.0, 662.0) # dist ~176.8px (< 265px), segment passes directly through (690, 716)
	assert_lt(shaman.position.distance_to(gu.position), 200.0, "Party is within 200px (< 265px aggro) of shaman")
	assert_true(
		world._combat_ctrl._is_line_of_sight_blocked(shaman.position, gu.position),
		"_is_line_of_sight_blocked detects prop_cliff_rock cover"
	)
	for _i: int in range(30):
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_false(world._combat_ctrl.in_combat, "Rock LoS cover prevents miasma_shaman aggro at 177px")

	# Remove shaman for clean cone_120 test
	shaman.alive = false

	# 2. cone_120 rot_wolf facing RIGHT: back-approach at 160px (> 0.48*245=117.6px) does not aggro
	var wolf: BattleActor = world._combat_ctrl.spawn_enemy_unit("rot_wolf", Vector2(400.0, 960.0), "enc_cone_test")
	assert_not_null(wolf, "Spawned cone_120 rot_wolf")
	wolf.set_facing(Vector2.RIGHT)
	gu.position = Vector2(240.0, 960.0) # 160px directly behind wolf
	assert_false(
		world._combat_ctrl._is_line_of_sight_blocked(wolf.position, gu.position),
		"Unobstructed open road behind rot_wolf"
	)
	for _j: int in range(24):
		wolf.set_facing(Vector2.RIGHT)
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_false(world._combat_ctrl.in_combat, "cone_120 back-approach at 160px (> 0.48*aggro) does NOT aggro")

	# Stepping inside 0.48 * 245 = 117.6px proximity behind wolf triggers aggro
	gu.position = Vector2(295.0, 960.0) # 105px behind wolf
	world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_true(world._combat_ctrl.in_combat, "Entering <= 0.48*aggro proximity behind cone_120 wolf triggers aggro")


func case_t2_f12_05_single_pet_cap_and_midcombat_portal_block() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	CampaignState.contract_spirit_pet("pet_fire_fox")
	world._combat_ctrl.sync_pet_actor(Vector2(410.0, 800.0))
	await step_frames(2)
	assert_not_null(world._combat_ctrl.pet_actor, "First pet (pet_fire_fox) spawned")

	CampaignState.contract_spirit_pet("pet_spirit_turtle")
	world._combat_ctrl.sync_pet_actor(Vector2(410.0, 800.0))
	await step_frames(2)

	var pet_nodes_in_ysort: int = 0
	for ch: Node in world._ysort_root.get_children():
		if ch is BattleActor and not ch.is_queued_for_deletion():
			if (ch as BattleActor).faction == "pet":
				pet_nodes_in_ysort += 1

	assert_eq(pet_nodes_in_ysort, 1, "Strictly 1 active spirit pet BattleActor in _ysort_root after pet swap")
	assert_eq(world._combat_ctrl.pet_actor.actor_id, "pet_pet_spirit_turtle", "Active pet swapped to pet_spirit_turtle")
	assert_false(world._combat_ctrl.unit_states.has("pet_pet_fire_fox"), "Old pet state purged from unit_states")

	# Mid-combat portal overlap block (with genuinely engaged living enemy so combat stays active across frames)
	var guard_enemy: BattleActor = world._combat_ctrl.spawn_enemy_unit(
		"rogue_cultivator", Vector2(2210.0, 610.0), "enc_portal_guard"
	)
	assert_not_null(guard_enemy, "Spawned portal guard enemy")
	world._combat_ctrl.engage_enemy_group("enc_portal_guard", "gu_changqing", false)
	assert_true(world._combat_ctrl.in_combat, "Party is genuinely engaged in combat")

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(2310.0, 610.0) # Inside tingyu_town northeast portal Rect2(2265, 505, 130, 210)
	world._physics_process(1.0 / 60.0)
	await step_frames(1)
	assert_true(world._combat_ctrl.in_combat, "Combat remains active")
	assert_eq(CampaignState.current_zone_id, "tingyu_town", "Overlapping zone portal during combat is 100% blocked")


func case_t2_f13_01_canonical_jishi_yaolu_name_guard() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	var corpus: PackedStringArray = PackedStringArray()
	for inter: Dictionary in world._interactables:
		corpus.append(str(inter.get("title", "")))
	for npc: BattleActor in world._npc_actors:
		corpus.append(npc.display_name)
	for portal: Dictionary in world._zone_portals:
		corpus.append(str(portal.get("label", "")))

	world._modals.open_shop_modal("shop_yaolu_pharmacy")
	for lbl: Label in collect_visible_labels(world._modals):
		corpus.append(lbl.text)
	world._modals.open_alchemy_furnace()
	for lbl2: Label in collect_visible_labels(world._modals):
		corpus.append(lbl2.text)
	world._modals.close_modal()

	if FileAccess.file_exists("res://locales/zh_CN.csv"):
		corpus.append(FileAccess.get_file_as_string("res://locales/zh_CN.csv"))

	var joined: String = "\n".join(corpus)
	assert_str_contains(joined, "济世药庐", "Canonical pharmacy name '济世药庐' is present")
	assert_str_not_contains(joined, "濟世堂", "Zero Traditional mockup artifact '濟世堂'")
	assert_str_not_contains(joined, "济世堂", "Zero uncanonical mockup name '济世堂'")


func _count_unobstructed_approach_rays(
	world: QinglanWorld,
	target_pos: Vector2,
	interact_radius: float
) -> int:
	var walkable_rect: Rect2 = Rect2(38.0, 54.0, 2324.0, 1312.0)
	var valid_rays: int = 0
	for ray_i: int in range(16):
		var ang: float = TAU * float(ray_i) / 16.0
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var ray_ok: bool = false
		for frac: float in [0.58, 0.76, 0.90]:
			var cand: Vector2 = target_pos + dir * (interact_radius * frac)
			if not walkable_rect.has_point(cand):
				continue
			if world._interact_distance_to(cand, target_pos) > interact_radius:
				continue
			var inside_obs: bool = false
			for obs: Dictionary in world._combat_ctrl.obstacle_circles:
				var c: Vector2 = obs.get("pos", Vector2.ZERO) as Vector2
				var r: float = float(obs.get("radius", 0.0))
				if r > 1.5 and cand.distance_to(c) < r + 2.0:
					inside_obs = true
					break
			if not inside_obs:
				ray_ok = true
				break
		if ray_ok:
			valid_rays += 1
	return valid_rays


func case_t2_f13_02_sixteen_ray_interactable_reachability() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld

	var total_checked: int = 0
	var blocked_targets: Array[String] = []

	for zid: String in ["tingyu_town", "qinglan_pass", "cangmu_cave"]:
		if zid == "cangmu_cave":
			# First verify barrier_vine & shortcut_gate themselves are reachable before opening
			CampaignState.world_flags.erase("vine_wall_burned")
			CampaignState.world_flags.erase("shortcut_gate_opened")
			world.load_zone(zid, "", false)
			await step_frames(2)
			for pre_inter: Dictionary in world._interactables:
				var pid: String = str(pre_inter.get("id", ""))
				if pid == "barrier_vine" or pid == "shortcut_gate":
					var pr: int = _count_unobstructed_approach_rays(
						world,
						pre_inter.get("pos", Vector2.ZERO) as Vector2,
						float(pre_inter.get("radius", 120.0))
					)
					total_checked += 1
					if pr < 2:
						blocked_targets.append("%s::%s(pre:%d)" % [zid, pid, pr])
			CampaignState.world_flags["vine_wall_burned"] = true
			CampaignState.world_flags["shortcut_gate_opened"] = true

		world.load_zone(zid, "", false)
		await step_frames(2)

		for inter: Dictionary in world._interactables:
			var rad: float = float(inter.get("radius", 0.0))
			if rad <= 1.0:
				continue
			var iid: String = str(inter.get("id", ""))
			var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
			var open_rays: int = _count_unobstructed_approach_rays(world, ipos, rad)
			total_checked += 1
			if open_rays < 2:
				blocked_targets.append("%s::%s(%d)" % [zid, iid, open_rays])

		for npc: BattleActor in world._npc_actors:
			if is_instance_valid(npc):
				var npc_rays: int = _count_unobstructed_approach_rays(world, npc.position, 175.0)
				total_checked += 1
				if npc_rays < 2:
					blocked_targets.append("%s::npc:%s(%d)" % [zid, npc.actor_id, npc_rays])

	record_metric("reachability_targets_checked", total_checked)
	assert_ge(float(total_checked), 18.0, "Checked >= 18 interactables & NPCs across 3 zones")
	assert_eq(
		blocked_targets,
		[],
		"100% of interactables & NPCs across all 3 zones have >= 2 unobstructed walkable approach rays"
	)


func case_t2_f13_03_cave_zero_outdoor_trees_and_rain() -> void:
	SaveManager.reduced_motion = false
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "cave_entry") as QinglanWorld
	await step_frames(2)

	var outdoor_leaks: Array[String] = []
	for layer_node: Node in [world._ysort_root, world._ground_decor_layer]:
		for ch: Node in layer_node.get_children():
			if ch is Sprite2D and not ch.is_queued_for_deletion():
				var sp: Sprite2D = ch as Sprite2D
				if sp.texture != null:
					var rpath: String = sp.texture.resource_path
					if rpath.ends_with("prop_camphor_tree.png") or rpath.ends_with("prop_bamboo_cluster.png"):
						outdoor_leaks.append(rpath)

	assert_eq(outdoor_leaks, [], "Underground cangmu_cave contains 0 outdoor camphor tree or bamboo sprites")

	var streak_0_before: Vector2 = world._rain_streaks[0]
	for _i: int in range(20):
		world._physics_process(1.0 / 60.0)
	assert_eq(
		world._rain_streaks[0],
		streak_0_before,
		"Underground cangmu_cave suppresses outdoor rain streak animation 100%"
	)


func case_t2_f13_05_zero_zone_cycle_node_or_obstacle_leaks() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var ysort_1: int = world._ysort_root.get_child_count()
	var decor_1: int = world._ground_decor_layer.get_child_count()
	var inter_1: int = world._interactables.size()
	var occ_1: int = world._occluder_sprites.size()
	var obs_1: int = world._combat_ctrl.obstacle_circles.size()
	var portal_1: int = world._zone_portals.size()

	world.load_zone("qinglan_pass", "from_town", false)
	await step_frames(3)
	world.load_zone("cangmu_cave", "from_pass", false)
	await step_frames(3)
	world.load_zone("tingyu_town", "town_south_entry", false)
	await step_frames(3)

	assert_eq(world._ysort_root.get_child_count(), ysort_1, "0 leaked _ysort_root children after 3-zone cycle")
	assert_eq(world._ground_decor_layer.get_child_count(), decor_1, "0 leaked _ground_decor_layer children")
	assert_eq(world._interactables.size(), inter_1, "0 leaked _interactables entries")
	assert_eq(world._occluder_sprites.size(), occ_1, "0 leaked _occluder_sprites entries")
	assert_eq(world._combat_ctrl.obstacle_circles.size(), obs_1, "0 compounded obstacle_circles after 3-zone cycle")
	assert_eq(world._zone_portals.size(), portal_1, "0 leaked _zone_portals entries")
