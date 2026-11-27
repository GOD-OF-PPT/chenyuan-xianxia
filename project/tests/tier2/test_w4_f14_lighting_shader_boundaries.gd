extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 2
# @e2e_features: F14


func register_cases() -> void:
	add_case(
		"T2-F14-01",
		2,
		"F14",
		"polish_r4",
		"PointLight2D per-screen budget stays strictly within 1 <= visible_lights <= 8 across 5x3 1920x1080 grid",
		"case_t2_f14_01_point_light_per_screen_budget"
	)
	add_case(
		"T2-F14-02",
		2,
		"F14",
		"polish_r4",
		"wet_bluestone.gdshader stays shaded (0 render_mode unshaded) while CombatVfxOverlay stays unshaded",
		"case_t2_f14_02_shaded_road_vs_unshaded_vfx_contract"
	)
	add_case(
		"T2-F14-03",
		2,
		"F14",
		"baseline",
		"SaveManager.reduced_motion freezes rain streaks while preserving 55% Y-Sort canopy occlusion fade",
		"case_t2_f14_03_reduced_motion_rain_freeze_and_occlusion"
	)
	add_case(
		"T2-F14-04",
		2,
		"F14",
		"baseline",
		"Downed ally (alive == false) behind canopy skips occlusion fade and restores roof/tree alpha to 1.0",
		"case_t2_f14_04_downed_ally_skips_occlusion_fade"
	)
	add_case(
		"T2-F14-05",
		2,
		"F14",
		"polish_r4",
		"Live 1920x1080 OpenGL3 cauldron PointLight2D renders warm pixel halo (R > B + 0.04 & Luma > distant + 0.04)",
		"case_t2_f14_05_cauldron_warm_halo_pixel_contrast"
	)


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


func case_t2_f14_01_point_light_per_screen_budget() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld

	var xs: Array[float] = [0.0, 120.0, 240.0, 360.0, 480.0]
	var ys: Array[float] = [0.0, 160.0, 320.0]

	for zid: String in ["tingyu_town", "qinglan_pass", "cangmu_cave"]:
		world.load_zone(zid, "", false)
		await step_frames(3)
		var lights: Array[PointLight2D] = _collect_active_point_lights(world)
		assert_ge(float(lights.size()), 1.0, zid + " has >= 1 active PointLight2D")

		var min_vis: int = 999
		var max_vis: int = 0
		for vx: float in xs:
			for vy: float in ys:
				var vp_rect: Rect2 = Rect2(Vector2(vx, vy), Vector2(1920.0, 1080.0))
				var vis_cnt: int = 0
				for pl: PointLight2D in lights:
					if vp_rect.intersects(_light_world_rect(pl)):
						vis_cnt += 1
				min_vis = mini(min_vis, vis_cnt)
				max_vis = maxi(max_vis, vis_cnt)

		record_metric(zid + "_min_screen_lights", min_vis)
		record_metric(zid + "_max_screen_lights", max_vis)
		assert_ge(float(min_vis), 1.0, zid + " has >= 1 visible PointLight2D in every 1920x1080 viewport")
		assert_le(float(max_vis), 8.0, zid + " enforces <= 8 visible PointLight2D per 1920x1080 viewport")


func _node_or_children_use_unshaded(root_ci: CanvasItem) -> bool:
	if root_ci == null or not is_instance_valid(root_ci):
		return false
	var stack: Array[Node] = [root_ci]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CanvasItem and is_canvas_item_unshaded(cur as CanvasItem):
			return true
		for ch: Node in cur.get_children():
			stack.append(ch)
	return false


func case_t2_f14_02_shaded_road_vs_unshaded_vfx_contract() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var shader_path: String = "res://src/presentation/shaders/wet_bluestone.gdshader"
	assert_true(res_exists(shader_path), "wet_bluestone.gdshader exists")
	if FileAccess.file_exists(shader_path):
		var code: String = FileAccess.get_file_as_string(shader_path)
		assert_str_contains(strip_shader_comments(code), "shader_type canvas_item;", "wet_bluestone.gdshader is a canvas_item shader")
		assert_false(
			shader_code_has_unshaded_render_mode(code),
			"wet_bluestone.gdshader MUST NOT declare render_mode unshaded (roads receive PointLight2D glow)"
		)

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)
	world._sky_vfx.spawn_ring_burst(Vector2(600.0, 680.0), 120.0, UIThemeBuilder.COL_CINNABAR_RED, 0.50)
	await step_frames(1)

	assert_true(
		_node_or_children_use_unshaded(world._ground_vfx),
		"_ground_vfx CombatVfxOverlay renders unshaded so _mood_modulate never dims telegraphs/ripples"
	)
	assert_true(
		_node_or_children_use_unshaded(world._sky_vfx),
		"_sky_vfx CombatVfxOverlay renders unshaded so _mood_modulate never dims sword/element VFX"
	)


func case_t2_f14_03_reduced_motion_rain_freeze_and_occlusion() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	SaveManager.reduced_motion = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	var camphor_sp: Sprite2D = null
	for occ: Dictionary in world._occluder_sprites:
		var sp: Sprite2D = occ.get("sprite", null) as Sprite2D
		if sp != null and is_instance_valid(sp) and sp.position.distance_to(Vector2(835.0, 595.0)) < 45.0:
			camphor_sp = sp
			break
	assert_not_null(camphor_sp, "Found prop_camphor_tree occluder")

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(835.0, 560.0)
	var rain_p0: Vector2 = world._rain_streaks[0]
	for _i: int in range(30):
		world._physics_process(1.0 / 60.0)

	assert_eq(world._rain_streaks[0], rain_p0, "reduced_motion == true freezes rain streak motion")
	if camphor_sp != null:
		assert_approx(
			camphor_sp.modulate.a,
			0.55,
			0.02,
			"reduced_motion == true still preserves 55% Y-Sort canopy occlusion readability"
		)

	SaveManager.reduced_motion = false
	for _j: int in range(5):
		world._physics_process(1.0 / 60.0)
	assert_gt(
		world._rain_streaks[0].distance_to(rain_p0),
		5.0,
		"Restoring reduced_motion == false resumes diagonal rain motion"
	)


func case_t2_f14_04_downed_ally_skips_occlusion_fade() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	var camphor_sp: Sprite2D = null
	for occ: Dictionary in world._occluder_sprites:
		var sp: Sprite2D = occ.get("sprite", null) as Sprite2D
		if sp != null and is_instance_valid(sp) and sp.position.distance_to(Vector2(835.0, 595.0)) < 45.0:
			camphor_sp = sp
			break
	assert_not_null(camphor_sp, "Found prop_camphor_tree occluder")
	if camphor_sp == null:
		return

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.alive = true
	gu.position = Vector2(835.0, 560.0)
	for _i: int in range(24):
		world._update_ysort_occlusion_fade(1.0 / 60.0)
	assert_approx(camphor_sp.modulate.a, 0.55, 0.02, "Living ally behind canopy fades tree to 0.55")

	# Simulate downed ally behind canopy
	gu.alive = false
	for _j: int in range(30):
		world._update_ysort_occlusion_fade(1.0 / 60.0)
	assert_approx(
		camphor_sp.modulate.a,
		1.00,
		0.02,
		"Downed ally (alive == false) is ignored by _update_ysort_occlusion_fade, restoring tree alpha to 1.0"
	)
	gu.alive = true


func case_t2_f14_05_cauldron_warm_halo_pixel_contrast() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.world_flags["met_shen_qinghe"] = true
	CampaignState.world_flags["yaolu_spy_resolved"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	# Position controlled actor at Vector2(1180, 680) so cauldron Vector2(1405, 646) is cleanly in frame
	# and no party/NPC sprite overlaps the cauldron ground halo ROI.
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1180.0, 680.0)
	world._camera.position = gu.position

	var lights: Array[PointLight2D] = _collect_active_point_lights(world)
	var cauldron_lights: Array[PointLight2D] = []
	for pl: PointLight2D in lights:
		if pl.global_position.distance_to(Vector2(1405.0, 635.0)) <= 240.0 and pl.color.r > pl.color.b + 0.06:
			cauldron_lights.append(pl)
	var has_cauldron_warm_light: bool = not cauldron_lights.is_empty()
	assert_true(has_cauldron_warm_light, "Active warm PointLight2D mounted near yaolu_alchemy cauldron")

	var img: Image = await capture_1080p_frame(20, "t2_f14_05_cauldron_halo")
	assert_eq(img.get_width(), 1920, "Captured 1920px frame width")
	assert_eq(img.get_height(), 1080, "Captured 1080px frame height")

	var cam_c: Vector2 = world._camera.get_screen_center_position()
	var cauldron_scr: Vector2 = (Vector2(1405.0, 635.0) - cam_c) * world._camera.zoom + Vector2(960.0, 540.0)
	var halo_rect: Rect2i = Rect2i(int(cauldron_scr.x) - 104, int(cauldron_scr.y) + 18, 54, 44)

	var halo_stats: Dictionary = sample_image_roi_stats(img, halo_rect)
	var unlit_stats: Dictionary = halo_stats
	if has_cauldron_warm_light:
		for pl_c: PointLight2D in cauldron_lights:
			pl_c.enabled = false
		var img_unlit: Image = await capture_1080p_frame(18)
		for pl_c2: PointLight2D in cauldron_lights:
			pl_c2.enabled = true
		await step_frames(1)
		unlit_stats = sample_image_roi_stats(img_unlit, halo_rect)

	var halo_r: float = float(halo_stats.get("mean_r", 0.0))
	var halo_b: float = float(halo_stats.get("mean_b", 0.0))
	var halo_luma: float = float(halo_stats.get("mean_luma", 0.0))
	var unlit_luma: float = float(unlit_stats.get("mean_luma", 0.0))

	record_metric("cauldron_halo_mean_r", snappedf(halo_r, 0.001))
	record_metric("cauldron_halo_mean_b", snappedf(halo_b, 0.001))
	record_metric("cauldron_halo_mean_luma", snappedf(halo_luma, 0.001))
	record_metric("cauldron_unlit_mean_luma", snappedf(unlit_luma, 0.001))

	assert_gt(
		halo_r,
		halo_b + 0.04,
		"Cauldron PointLight2D warm halo satisfies R_halo > B_halo + 0.04 in rendered 1080p frame"
	)
	assert_gt(
		halo_luma,
		unlit_luma + 0.04,
		"Cauldron PointLight2D warm halo satisfies Luma_lit > Luma_unlit + 0.04 at exact same halo_rect"
	)
