extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 3
# @e2e_features: F12, F13, F14


func register_cases() -> void:
	add_case(
		"T3-W4-01",
		3,
		"F12",
		"baseline",
		"Full 3-Zone Seamless Box-Garden Journey: town -> pass fox rescue & vista -> cave barriers/stealth/loop -> stele return",
		"case_t3_w4_01_full_three_zone_seamless_journey"
	)
	add_case(
		"T3-W4-02",
		3,
		"F13",
		"polish_r4",
		"济世药庐 Courtyard Walk -> 55% Occlusion + Actor Ink Silhouette -> Shaded Actor/Props Lit by Cauldron PointLight2D",
		"case_t3_w4_02_courtyard_occlusion_silhouette_and_cauldron_light"
	)
	add_case(
		"T3-W4-03",
		3,
		"F14",
		"polish_r4",
		"Rainy wet_bluestone.gdshader + Warm Cauldron vs Cool Stele PointLight2D (<=8/screen) + reduced_motion Comfort Toggle",
		"case_t3_w4_03_wet_stone_warm_cool_lights_and_reduced_motion"
	)
	add_case(
		"T3-W4-05",
		3,
		"F12",
		"baseline",
		"cangmu_cave Miasma Hazard DoT -> Cleanse & Stele Rest (Scratch Autosave) -> Zone Reload <1.5s & Reachability Invariance",
		"case_t3_w4_05_cave_miasma_stele_autosave_reload_invariance"
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


func _collect_active_point_lights(world: Node) -> Array[PointLight2D]:
	var out: Array[PointLight2D] = []
	for n: Node in world.find_children("*", "PointLight2D", true, false):
		if n is PointLight2D and is_instance_valid(n) and not n.is_queued_for_deletion():
			var pl: PointLight2D = n as PointLight2D
			if pl.enabled and pl.energy > 0.01 and pl.texture != null and pl.is_visible_in_tree():
				out.append(pl)
	return out


func _light_world_rect(pl: PointLight2D) -> Rect2:
	var tw: float = float(pl.texture.get_width()) * pl.texture_scale * absf(pl.global_scale.x)
	var th: float = float(pl.texture.get_height()) * pl.texture_scale * absf(pl.global_scale.y)
	var center: Vector2 = pl.global_position + pl.offset * pl.global_scale
	return Rect2(center - Vector2(tw * 0.5, th * 0.5), Vector2(tw, th))


func _probe_actor_occlusion_silhouette_active(pa: BattleActor, world: QinglanWorld) -> bool:
	for pname: String in [
		"is_occluded",
		"occluded",
		"_is_occluded",
		"occluded_by_canopy",
		"show_occlusion_silhouette",
	]:
		if obj_has_prop(pa, pname) and bool(obj_get(pa, pname, false)):
			return true
	for aname: String in [
		"occlusion_silhouette_alpha",
		"ink_silhouette_alpha",
		"_occlusion_alpha",
		"silhouette_alpha",
	]:
		if obj_has_prop(pa, aname) and float(obj_get(pa, aname, 0.0)) > 0.05:
			return true
	if pa._sprite != null and pa._sprite.material is ShaderMaterial:
		var sm: ShaderMaterial = pa._sprite.material as ShaderMaterial
		for u_name: String in ["silhouette_alpha", "occlusion_alpha", "ink_silhouette", "occluded_mix"]:
			var uval: Variant = sm.get_shader_parameter(u_name)
			if (uval is float or uval is int) and float(uval) > 0.05:
				return true
			if uval is bool and bool(uval):
				return true
	for ch: Node in pa.get_children():
		var low_n: String = str(ch.name).to_lower()
		if (low_n.contains("silhouette") or low_n.contains("occlu")) and ch is CanvasItem:
			var ci: CanvasItem = ch as CanvasItem
			if ci.visible and ci.modulate.a > 0.05:
				return true
	for wch: Node in world.get_children():
		var wlow: String = str(wch.name).to_lower()
		if (wlow.contains("silhouette") or wlow.contains("occlu")) and wch is CanvasItem:
			var wci: CanvasItem = wch as CanvasItem
			if wci.visible and wci.modulate.a > 0.05:
				return true
	return false


func case_t3_w4_01_full_three_zone_seamless_journey() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 3)
	CampaignState.add_item("item_stealth_talisman", 2, true)
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	# 1. Unlock stele_tingyu_gate in tingyu_town, then step into northeast portal -> qinglan_pass
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1955.0, 720.0)
	world._try_interact_nearest()
	assert_true(CampaignState.unlocked_steles.has("stele_tingyu_gate"), "Unlocked stele_tingyu_gate")
	world._modals.close_modal()

	gu.position = Vector2(2310.0, 610.0)
	world._physics_process(1.0 / 60.0)
	await step_frames(2)
	assert_eq(CampaignState.current_zone_id, "qinglan_pass", "Entered qinglan_pass via seamless portal")

	# 2. Rescue injured beast -> contract pet_fire_fox & inspect Golden Core cliff vista
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(560.0, 520.0)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world, "CHOICE_PET_FOX")
	assert_eq(CampaignState.active_pet_id, "pet_fire_fox", "Contracted pet_fire_fox in qinglan_pass")
	assert_not_null(world._combat_ctrl.pet_actor, "pet_actor spawned in qinglan_pass")

	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1385.0, 895.0)
	world._try_interact_nearest()
	assert_true(CampaignState.unlocked_clues.has("clue_golden_core_cliff"), "Unlocked clue_golden_core_cliff")

	# 3. Unlock temple cave portal & transition to cangmu_cave
	CampaignState.world_flags["met_pei_zhao"] = true
	CampaignState.cleared_encounters["enc_temple_wolves"] = true
	world.load_zone("qinglan_pass", "stele_temple_courtyard", false)
	await step_frames(2)
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(2120.0, 625.0)
	world._physics_process(1.0 / 60.0)
	await step_frames(2)
	assert_eq(CampaignState.current_zone_id, "cangmu_cave", "Entered cangmu_cave via seamless portal")
	assert_not_null(world._combat_ctrl.pet_actor, "pet_actor persisted seamlessly into cangmu_cave")

	# 4. Burn Fire vine barrier -> pop stealth talisman -> loot chest_poxue_pendant -> cleanse Water pool -> open north shortcut_gate
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(580.0, 1085.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("vine_wall_burned", false)), "Burned Fire vine barrier")

	for ea: BattleActor in world._combat_ctrl.enemy_actors:
		var eu: Dictionary = world._combat_ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
		if str(eu.get("enemy_def_id", "")) == "wood_golem":
			ea.patrol_points.clear()
			ea.position = Vector2(980.0, 430.0)
	assert_true(world._combat_ctrl.activate_stealth_talisman(), "Activated stealth talisman in cangmu_cave")
	gu.position = Vector2(980.0, 310.0)
	for _s: int in range(20):
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_false(world._combat_ctrl.in_combat, "Stealth bypassed wood_golem at 120px")

	gu.position = Vector2(1125.0, 250.0)
	world._try_interact_nearest()
	assert_eq(CampaignState.get_item_count("eq_pendant_poxue"), 1, "Looted eq_pendant_poxue in stealth branch")

	gu.position = Vector2(1060.0, 1155.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("miasma_pool_cleansed", false)), "Cleansed Water miasma pool")

	gu.position = Vector2(490.0, 820.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("shortcut_gate_opened", false)), "Opened north loop shortcut_gate")

	# 5. Rest at stele_cave_mid & fast travel back to tingyu_town (stele_tingyu_gate)
	gu.position = Vector2(1290.0, 755.0)
	world._try_interact_nearest()
	assert_true(CampaignState.unlocked_steles.has("stele_cave_mid"), "Unlocked stele_cave_mid")

	var teleported: bool = false
	for btn: Button in collect_visible_buttons(world._modals):
		if btn.text.contains("听雨镇") and not btn.disabled:
			btn.pressed.emit()
			teleported = true
			break
	assert_true(teleported, "Clicked stele fast-travel button back to tingyu_town")
	await step_frames(2)

	assert_eq(CampaignState.current_zone_id, "tingyu_town", "Fast-traveled back to tingyu_town")
	assert_lt(
		world._combat_ctrl.get_controlled_actor_pos().distance_to(Vector2(1855.0, 645.0)),
		6.0,
		"Arrived at stele_tingyu_gate spawn coordinates"
	)


func case_t3_w4_02_courtyard_occlusion_silhouette_and_cauldron_light() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.world_flags["met_shen_qinghe"] = true
	CampaignState.world_flags["yaolu_spy_resolved"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	assert_not_null(gu, "Controlled actor exists")

	# 1. Verify actor _sprite stays shaded (0 unshaded override) so cauldron PointLight2D illuminates character
	var sprite_unshaded: bool = is_canvas_item_unshaded(gu._sprite)
	assert_false(sprite_unshaded, "BattleActor._sprite stays shaded (receives Stage C PointLight2D illumination)")

	# 2. Step behind prop_camphor_tree / courtyard gatehouse -> 55% fade + subtle ink actor silhouette
	var camphor_sp: Sprite2D = null
	for occ: Dictionary in world._occluder_sprites:
		var sp: Sprite2D = occ.get("sprite", null) as Sprite2D
		if sp != null and is_instance_valid(sp) and sp.position.distance_to(Vector2(835.0, 595.0)) < 45.0:
			camphor_sp = sp
			break
	assert_not_null(camphor_sp, "Found occluder Sprite2D")

	gu.position = Vector2(835.0, 560.0)
	for _i: int in range(24):
		world._physics_process(1.0 / 60.0)
	await step_frames(2)
	if camphor_sp != null:
		assert_approx(camphor_sp.modulate.a, 0.55, 0.03, "Occluder faded to 0.55 alpha")
	assert_true(
		_probe_actor_occlusion_silhouette_active(gu, world),
		"Occluded BattleActor activates subtle ink actor silhouette behind 55% occluder"
	)

	# 3. Walk into enclosed 济世药庐 courtyard & verify cauldron warm PointLight2D illumination
	var compound_structures: int = 0
	for ch: Node in world._ysort_root.get_children():
		if ch is Sprite2D and not ch.is_queued_for_deletion():
			var sp2: Sprite2D = ch as Sprite2D
			if sp2.position.x >= 880.0 and sp2.position.x <= 1920.0 and sp2.texture != null:
				var rp: String = sp2.texture.resource_path
				if not rp.contains("camphor") and not rp.contains("bamboo") and not rp.contains("discarded"):
					compound_structures += 1
	assert_ge(
		float(compound_structures),
		5.0,
		"济世药庐 compound contains enclosed courtyard/gatehouse/alchemy pavilion structures beyond baseline"
	)

	gu.position = Vector2(1180.0, 680.0)
	world._camera.position = gu.position
	var cauldron_lights: Array[PointLight2D] = []
	for pl: PointLight2D in _collect_active_point_lights(world):
		if pl.global_position.distance_to(Vector2(1405.0, 635.0)) <= 240.0 and pl.color.r > pl.color.b + 0.06:
			cauldron_lights.append(pl)
	assert_false(cauldron_lights.is_empty(), "Active warm PointLight2D mounted near yaolu_alchemy cauldron")

	var img: Image = await capture_1080p_frame(20, "t3_w4_02_courtyard_cauldron")
	var cam_c: Vector2 = world._camera.get_screen_center_position()
	var cauldron_scr: Vector2 = (Vector2(1405.0, 635.0) - cam_c) * world._camera.zoom + Vector2(960.0, 540.0)
	var halo_rect: Rect2i = Rect2i(int(cauldron_scr.x) - 104, int(cauldron_scr.y) + 18, 54, 44)
	var halo_stats: Dictionary = sample_image_roi_stats(img, halo_rect)
	var unlit_stats: Dictionary = halo_stats
	if not cauldron_lights.is_empty():
		for pl_c: PointLight2D in cauldron_lights:
			pl_c.enabled = false
		var img_unlit: Image = await capture_1080p_frame(18)
		for pl_c2: PointLight2D in cauldron_lights:
			pl_c2.enabled = true
		await step_frames(1)
		unlit_stats = sample_image_roi_stats(img_unlit, halo_rect)

	assert_gt(
		float(halo_stats.get("mean_r", 0.0)),
		float(halo_stats.get("mean_b", 0.0)) + 0.04,
		"Courtyard cauldron PointLight2D renders warm amber halo (R > B + 0.04)"
	)
	assert_gt(
		float(halo_stats.get("mean_luma", 0.0)),
		float(unlit_stats.get("mean_luma", 0.0)) + 0.04,
		"Courtyard cauldron PointLight2D raises local luminance above unlit baseline at exact same halo_rect"
	)


func case_t3_w4_03_wet_stone_warm_cool_lights_and_reduced_motion() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	SaveManager.reduced_motion = false
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	# 1. Verify wet_bluestone.gdshader on road Polygon2Ds
	var shader_path: String = "res://src/presentation/shaders/wet_bluestone.gdshader"
	assert_true(res_exists(shader_path), "wet_bluestone.gdshader exists")
	var road_mat_ok: int = 0
	for ch: Node in world._road_stone_sub.get_children():
		if ch is Polygon2D and (ch as Polygon2D).material is ShaderMaterial:
			var sm: ShaderMaterial = (ch as Polygon2D).material as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path == shader_path:
				road_mat_ok += 1
	assert_ge(float(road_mat_ok), 4.0, "tingyu_town bluestone road Polygon2Ds apply wet_bluestone.gdshader")

	# 2. Verify warm cauldron/lantern PointLight2D vs cool jade stele_tingyu_gate PointLight2D & <=8 lights/screen
	var lights: Array[PointLight2D] = _collect_active_point_lights(world)
	var found_warm_cauldron: bool = false
	var found_cool_stele: bool = false
	for pl: PointLight2D in lights:
		if pl.global_position.distance_to(Vector2(1405.0, 635.0)) <= 190.0 and pl.color.r > pl.color.b + 0.06:
			found_warm_cauldron = true
		if pl.global_position.distance_to(Vector2(1955.0, 685.0)) <= 190.0 and (pl.color.g >= pl.color.r or pl.color.b >= pl.color.r):
			found_cool_stele = true
	assert_true(found_warm_cauldron, "Warm amber PointLight2D active on yaolu_alchemy cauldron")
	assert_true(found_cool_stele, "Cool jade/cyan PointLight2D active on stele_tingyu_gate")

	for vx: float in [0.0, 240.0, 480.0]:
		for vy: float in [0.0, 160.0, 320.0]:
			var vp_rect: Rect2 = Rect2(Vector2(vx, vy), Vector2(1920.0, 1080.0))
			var vis_n: int = 0
			for pl2: PointLight2D in lights:
				if vp_rect.intersects(_light_world_rect(pl2)):
					vis_n += 1
			assert_ge(float(vis_n), 1.0, ">= 1 visible PointLight2D in viewport")
			assert_le(float(vis_n), 8.0, "<= 8 visible PointLight2D in viewport")

	# 3. Toggle reduced_motion == true: rain freezes while PointLight2D & 0.55 occlusion remain intact
	SaveManager.reduced_motion = true
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(835.0, 560.0)
	var rain_before: Vector2 = world._rain_streaks[0]
	for _k: int in range(24):
		world._physics_process(1.0 / 60.0)
	assert_eq(world._rain_streaks[0], rain_before, "reduced_motion freezes rain streaks")
	assert_eq(_collect_active_point_lights(world).size(), lights.size(), "PointLight2D nodes stay active under reduced_motion")
	SaveManager.reduced_motion = false


func _count_unobstructed_rays(world: QinglanWorld, target_pos: Vector2, rad: float) -> int:
	var walkable_rect: Rect2 = Rect2(38.0, 54.0, 2324.0, 1312.0)
	var ok_rays: int = 0
	for r_i: int in range(16):
		var ang: float = TAU * float(r_i) / 16.0
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		for frac: float in [0.60, 0.80]:
			var cand: Vector2 = target_pos + dir * (rad * frac)
			if not walkable_rect.has_point(cand) or world._interact_distance_to(cand, target_pos) > rad:
				continue
			var blocked: bool = false
			for obs: Dictionary in world._combat_ctrl.obstacle_circles:
				var c: Vector2 = obs.get("pos", Vector2.ZERO) as Vector2
				var r: float = float(obs.get("radius", 0.0))
				if r > 1.5 and cand.distance_to(c) < r + 2.0:
					blocked = true
					break
			if not blocked:
				ok_rays += 1
				break
	return ok_rays


func case_t3_w4_05_cave_miasma_stele_autosave_reload_invariance() -> void:
	if not begin_isolated_xdg_save_test():
		return

	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.world_flags["vine_wall_burned"] = true
	CampaignState.world_flags["shortcut_gate_opened"] = true
	var gu_m0: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	gu_m0["meridian_bruise"] = 2
	CampaignState.recalculate_all_party_stats(true)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_cave_mid") as QinglanWorld
	CampaignState.sandbox_mode = false # Keep scratch save enabled after spawn_qinglan_world
	await step_frames(2)

	var obs_count_initial: int = world._combat_ctrl.obstacle_circles.size()
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	assert_not_null(gu, "Controlled actor spawned in cangmu_cave")

	# 1. Inflict cangmu_cave miasma hazard & step 2.2s (within 3.0s post-hit window) to verify 2.0s miasma DoT tick
	world._combat_ctrl.out_of_combat_sec = 0.0
	world._combat_ctrl._apply_damage_to_ally(
		"gu_changqing", gu, 12, "瘴林毒巫", "腐毒咒", "wood", true, false, true
	)
	assert_ge(float(gu.miasma_stacks), 1.0, "Miasma stacks applied on Gu Changqing")
	var hp_after_hit: int = gu.hp
	for _t: int in range(132): # 2.20s at 60Hz (< 3.0s OOC delay) -> triggers 2.0s miasma tick
		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
	assert_lt(float(gu.hp), float(hp_after_hit), "2.0s cangmu_cave miasma DoT ticked HP damage")

	# 2. Cleanse miasma via qingmu pill & rest at stele_cave_mid (clears meridian_bruise, heals 100%, writes auto_01.json)
	CampaignState.add_item("item_qingmu_pill", 1, true)
	CampaignState.quick_pill_5_id = "item_qingmu_pill"
	world._combat_ctrl.pill_cooldown_timer = 0.0
	world._combat_ctrl.trigger_hotkey_slot("5")
	assert_eq(gu.miasma_stacks, 0, "item_qingmu_pill cleansed miasma_stacks to 0")

	gu.position = Vector2(1290.0, 755.0)
	world._try_interact_nearest()
	assert_true(world._modals.visible and world._modals._active_kind == "stele", "Opened stele_cave_mid modal")
	world._modals.close_modal()

	var gu_rested: Dictionary = CampaignState.party_members["gu_changqing"] as Dictionary
	var gu_sheet: Dictionary = gu_rested.get("sheet", {}) as Dictionary
	assert_eq(int(gu_rested.get("meridian_bruise", -1)), 0, "Stele rest cleared meridian_bruise to 0")
	assert_eq(int(gu_rested.get("hp", 0)), int(gu_sheet.get("max_hp", -1)), "Stele rest restored 100% HP")
	assert_true(FileAccess.file_exists("user://saves/auto_01.json"), "Stele rest wrote rolling auto_01.json in scratch XDG")

	# 3. Mutate state, load auto_01.json, and measure zone reload < 1.5s (< 1500ms) + obstacle reachability invariance
	var saved_stones: int = CampaignState.spirit_stones
	CampaignState.spirit_stones = 3
	var load_res: Dictionary = SaveManager.load_slot("auto_01", false)
	assert_true(bool(load_res.get("ok", false)), "Loaded rolling auto_01.json cleanly")

	var t0_usec: int = Time.get_ticks_usec()
	var d0_ns: int = read_thread_run_delay_ns()
	world.load_zone(CampaignState.current_zone_id, "", true)
	var d1_ns: int = read_thread_run_delay_ns()
	var t1_usec: int = Time.get_ticks_usec()
	var reload_ms: float = maxf(
		0.1, float(t1_usec - t0_usec) / 1000.0 - maxf(0.0, float(d1_ns - d0_ns) / 1000000.0)
	)
	await step_frames(2)

	record_metric("cave_reload_ms", snappedf(reload_ms, 0.01))
	assert_lt(reload_ms, 1500.0, "cangmu_cave zone reload completed in < 1.5s (1500ms)")
	assert_eq(CampaignState.spirit_stones, saved_stones, "Reloaded auto_01 restored exact Spirit Stones")

	var gu_reloaded: BattleActor = world._combat_ctrl.get_controlled_actor()
	assert_eq(gu_reloaded.miasma_stacks, 0, "Reloaded party actor has 0 miasma_stacks")
	assert_eq(gu_reloaded.hp, gu_reloaded.max_hp, "Reloaded party actor has 100% max_hp")
	assert_eq(world._combat_ctrl.obstacle_circles.size(), obs_count_initial, "Obstacle circle count 100% invariant after reload")

	var unreachable: Array[String] = []
	for inter: Dictionary in world._interactables:
		var rad: float = float(inter.get("radius", 0.0))
		if rad > 1.0:
			var r_cnt: int = _count_unobstructed_rays(world, inter.get("pos", Vector2.ZERO) as Vector2, rad)
			if r_cnt < 2:
				unreachable.append(str(inter.get("id", "")))
	assert_eq(unreachable, [], "100% of cangmu_cave interactables remain walkable-reachable after stele reload")

	end_isolated_xdg_save_test()
