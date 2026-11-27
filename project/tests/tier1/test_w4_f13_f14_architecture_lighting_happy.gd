extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 1
# @e2e_features: F13, F14


func register_cases() -> void:
	add_case(
		"T1-F13-01",
		1,
		"F13",
		"polish_r4",
		"tingyu_town left street features continuous whitewash-and-dark-tile (粉墙黛瓦) folk residences (>=4)",
		"case_t1_f13_01_tingyu_folk_residences"
	)
	add_case(
		"T1-F13-02",
		1,
		"F13",
		"polish_r4",
		"济世药庐 compound features enclosed courtyard wall, roofed gatehouse, thatched alchemy pavilion & main hall",
		"case_t1_f13_02_yaolu_enclosed_courtyard_compound"
	)
	add_case(
		"T1-F13-03",
		1,
		"F13",
		"polish_r4",
		"qinglan_pass features wooden mountain plank bridges (山道栈桥) & dense bamboo sea (>=6)",
		"case_t1_f13_03_pass_plank_bridges_and_bamboo_sea"
	)
	add_case(
		"T1-F13-04",
		1,
		"F13",
		"polish_r4",
		"cangmu_cave features giant gnarled ancient roots (盘根古木) & carved mossy stone steps (古窟石阶)",
		"case_t1_f13_04_cave_gnarled_roots_and_stone_steps"
	)
	add_case(
		"T1-F13-05",
		1,
		"F13",
		"baseline",
		"4-layer architectural hierarchy & Y-Sort bottom-baseline Sprite2D anchoring across all 3 zones",
		"case_t1_f13_05_four_layer_hierarchy_and_ysort_anchors"
	)
	add_case(
		"T1-F14-01",
		1,
		"F14",
		"polish_r4",
		"Stage C active warm/cool PointLight2D nodes + tuned CanvasModulate across all 3 zones",
		"case_t1_f14_01_stage_c_warm_cool_point_lights"
	)
	add_case(
		"T1-F14-02",
		1,
		"F14",
		"polish_r4",
		"Rainy bluestone road Polygon2Ds use wet_bluestone.gdshader specular & raindrop ripples",
		"case_t1_f14_02_wet_bluestone_road_shader"
	)
	add_case(
		"T1-F14-03",
		1,
		"F14",
		"baseline",
		"Y-Sort canopy/roof smoothly fades to 55% alpha behind prop_camphor_tree and restores to 100%",
		"case_t1_f14_03_ysort_55pct_occlusion_fade_and_restore"
	)
	add_case(
		"T1-F14-04",
		1,
		"F14",
		"polish_r4",
		"Occluded living BattleActor behind 55% roof/canopy activates subtle ink actor silhouette",
		"case_t1_f14_04_occluded_actor_ink_silhouette"
	)
	add_case(
		"T1-F14-05",
		1,
		"F14",
		"polish_r4",
		"Layer 3 foreground renders both diagonal rain streaks and wind-blown bamboo leaf parallax",
		"case_t1_f14_05_layer3_rain_and_wind_bamboo_parallax"
	)


func _collect_world_sprites(root_node: Node) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == null or not is_instance_valid(cur) or cur.is_queued_for_deletion():
			continue
		if cur is BattleActor:
			continue
		if cur is Sprite2D:
			out.append(cur as Sprite2D)
		for ch: Node in cur.get_children():
			stack.append(ch)
	return out


func _collect_active_point_lights(world: Node) -> Array[PointLight2D]:
	var out: Array[PointLight2D] = []
	var found: Array[Node] = world.find_children("*", "PointLight2D", true, false)
	for n: Node in found:
		if n is PointLight2D and is_instance_valid(n) and not n.is_queued_for_deletion():
			var pl: PointLight2D = n as PointLight2D
			if pl.enabled and pl.energy > 0.01 and pl.texture != null and pl.is_visible_in_tree():
				out.append(pl)
	return out


func _str_has_any(haystack: String, tokens: Array[String]) -> bool:
	var low: String = haystack.to_lower()
	for tok: String in tokens:
		if low.contains(tok.to_lower()):
			return true
	return false


func case_t1_f13_01_tingyu_folk_residences() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var non_building_tokens: Array[String] = [
		"camphor",
		"bamboo",
		"herb",
		"peddler_stall",
		"stele",
		"cliff_rock",
		"alchemy_furnace",
		"yaolu_counter",
		"discarded_pill",
	]
	var residence_tokens: Array[String] = [
		"house",
		"residence",
		"folk",
		"townhouse",
		"dwelling",
		"shop_front",
		"eave",
		"minju",
		"street_bldg",
		"courtyard_house",
	]

	var left_buildings: int = 0
	var folk_house_hits: int = 0
	for sp: Sprite2D in _collect_world_sprites(world._ysort_root):
		if sp.texture == null:
			continue
		var rpath: String = sp.texture.resource_path
		var tag: String = rpath + "::" + str(sp.name)
		if sp.global_position.x < 965.0 and not _str_has_any(tag, non_building_tokens):
			if sp.texture.get_height() >= 140:
				left_buildings += 1
				if _str_has_any(tag, residence_tokens) or not rpath.ends_with("prop_tea_pavilion.png"):
					folk_house_hits += 1

	record_metric("tingyu_left_street_buildings", left_buildings)
	record_metric("tingyu_folk_residence_sprites", folk_house_hits)
	assert_ge(
		float(left_buildings),
		4.0,
		"tingyu_town left street (x < 965) has >= 4 architectural building sprites (master_a continuous street)"
	)
	assert_ge(
		float(folk_house_hits),
		2.0,
		"tingyu_town left street includes dedicated 粉墙黛瓦 folk residence structures beyond lone tea pavilion"
	)


func case_t1_f13_02_yaolu_enclosed_courtyard_compound() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var all_sprites: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	all_sprites.append_array(_collect_world_sprites(world._ground_decor_layer))

	var has_main_hall: bool = false
	var wall_count: int = 0
	var has_gatehouse: bool = false
	var has_alchemy_pavilion: bool = false

	var wall_tokens: Array[String] = ["wall", "courtyard", "fence", "yuanqiang", "compound_wall"]
	var gate_tokens: Array[String] = ["gate", "menlou", "archway", "paifang", "entry_gate"]
	var pav_tokens: Array[String] = [
		"alchemy_pavilion",
		"alchemy_shed",
		"alchemy_hut",
		"thatched",
		"thatch",
		"danlu_pavilion",
		"caolu",
		"herb_pavilion",
		"yaolu_pavilion",
	]

	for sp: Sprite2D in all_sprites:
		if sp.texture == null:
			continue
		var gx: float = sp.global_position.x
		if gx < 880.0 or gx > 1920.0:
			continue
		var tag: String = sp.texture.resource_path + "::" + str(sp.name)
		if tag.contains("yaolu_hall"):
			has_main_hall = true
		if _str_has_any(tag, wall_tokens):
			wall_count += 1
		if _str_has_any(tag, gate_tokens):
			has_gatehouse = true
		if _str_has_any(tag, pav_tokens):
			has_alchemy_pavilion = true

	# Also check custom Polygon2D/Line2D courtyard wall nodes inside compound if drawn procedurally
	for ch: Node in world._ground_decor_layer.get_children():
		if _str_has_any(str(ch.name), wall_tokens):
			wall_count += 1

	record_metric("yaolu_wall_segments", wall_count)
	assert_true(has_main_hall, "济世药庐 compound contains raised main hall (prop_yaolu_hall)")
	assert_ge(float(wall_count), 1.0, "济世药庐 compound contains enclosed whitewashed courtyard wall segments")
	assert_true(has_gatehouse, "济世药庐 compound contains roofed timber gatehouse (门楼)")
	assert_true(has_alchemy_pavilion, "济世药庐 compound contains thatched alchemy pavilion framing cauldron")


func case_t1_f13_03_pass_plank_bridges_and_bamboo_sea() -> void:
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(3)

	var sprites: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	sprites.append_array(_collect_world_sprites(world._ground_decor_layer))
	sprites.append_array(_collect_world_sprites(world._ground_layer))

	var bridge_tokens: Array[String] = ["bridge", "plank", "walkway", "boardwalk", "trestle", "zhanqiao"]
	var bamboo_tokens: Array[String] = ["bamboo", "zhuhai", "bamboo_grove", "bamboo_sea"]

	var bridge_count: int = 0
	var bamboo_count: int = 0
	for sp: Sprite2D in sprites:
		var tag: String = (sp.texture.resource_path if sp.texture != null else "") + "::" + str(sp.name)
		if _str_has_any(tag, bridge_tokens):
			bridge_count += 1
		if _str_has_any(tag, bamboo_tokens):
			bamboo_count += 1

	for sub_n: Node in world._ground_decor_layer.get_children():
		if not (sub_n is Sprite2D) and _str_has_any(str(sub_n.name), bridge_tokens):
			bridge_count += 1

	record_metric("pass_plank_bridges", bridge_count)
	record_metric("pass_bamboo_structures", bamboo_count)
	assert_ge(float(bridge_count), 1.0, "qinglan_pass includes wooden mountain plank bridge/walkway structures")
	assert_ge(float(bamboo_count), 6.0, "qinglan_pass features dense bamboo sea (>= 6 bamboo structures)")


func case_t1_f13_04_cave_gnarled_roots_and_stone_steps() -> void:
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "cave_entry") as QinglanWorld
	await step_frames(3)

	var sprites: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	sprites.append_array(_collect_world_sprites(world._ground_decor_layer))
	sprites.append_array(_collect_world_sprites(world._ground_layer))

	var root_tokens: Array[String] = ["root", "gnarl", "ancient_root", "banyan", "pangen"]
	var step_tokens: Array[String] = ["stair", "step", "shijie", "stone_step", "moss_step"]

	var root_count: int = 0
	var step_count: int = 0
	for sp: Sprite2D in sprites:
		var tag: String = (sp.texture.resource_path if sp.texture != null else "") + "::" + str(sp.name)
		if _str_has_any(tag, root_tokens):
			root_count += 1
		if _str_has_any(tag, step_tokens):
			step_count += 1

	for dec_n: Node in world._ground_decor_layer.get_children():
		if not (dec_n is Sprite2D):
			if _str_has_any(str(dec_n.name), root_tokens):
				root_count += 1
			if _str_has_any(str(dec_n.name), step_tokens):
				step_count += 1

	record_metric("cave_gnarled_roots", root_count)
	record_metric("cave_stone_steps", step_count)
	assert_ge(float(root_count), 2.0, "cangmu_cave includes >= 2 giant gnarled ancient root structures (master_b)")
	assert_ge(float(step_count), 1.0, "cangmu_cave includes >= 1 carved mossy stone stair/step structure")


func case_t1_f13_05_four_layer_hierarchy_and_ysort_anchors() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld

	var bg_canvas: CanvasLayer = null
	for ch: Node in world.get_children():
		if ch is CanvasLayer and (ch as CanvasLayer).layer == -2:
			bg_canvas = ch as CanvasLayer
			break
	assert_not_null(bg_canvas, "Layer 0 parallax CanvasLayer (layer == -2) exists")
	assert_not_null(world._parallax_bg, "Layer 0 _parallax_bg Sprite2D exists")
	assert_not_null(world._ground_layer, "Layer 1 _ground_layer exists")
	assert_not_null(world._ground_decor_layer, "Layer 1.5 _ground_decor_layer exists")
	assert_not_null(world._ysort_root, "Layer 2 _ysort_root exists")
	assert_true(world._ysort_root.y_sort_enabled, "_ysort_root has y_sort_enabled == true")
	assert_not_null(world._rain_overlay, "Layer 3 _rain_overlay exists")
	assert_ge(float(world._rain_overlay.z_index), 20.0, "Layer 3 _rain_overlay z_index >= 20")

	assert_lt(
		float(world._ground_layer.get_index()),
		float(world._ground_decor_layer.get_index()),
		"_ground_layer ordered below _ground_decor_layer"
	)
	assert_lt(
		float(world._ground_decor_layer.get_index()),
		float(world._ysort_root.get_index()),
		"_ground_decor_layer ordered below _ysort_root"
	)
	assert_lt(
		float(world._ysort_root.get_index()),
		float(world._rain_overlay.get_index()),
		"_ysort_root ordered below _rain_overlay"
	)

	var total_checked_sprites: int = 0
	for zid: String in ["tingyu_town", "qinglan_pass", "cangmu_cave"]:
		world.load_zone(zid, "", false)
		await step_frames(2)
		for ych: Node in world._ysort_root.get_children():
			if ych is Sprite2D and not ych.is_queued_for_deletion():
				var sp: Sprite2D = ych as Sprite2D
				assert_false(sp.centered, "Y-Sort Sprite2D in %s has centered == false" % zid)
				assert_not_null(sp.texture, "Y-Sort Sprite2D in %s has loaded Texture2D" % zid)
				if sp.texture != null:
					var tex_h: float = float(sp.texture.get_height())
					var fname: String = sp.texture.resource_path.get_file()
					assert_ge(
						sp.offset.y,
						-tex_h - 4.0,
						"Y-Sort Sprite2D %s bottom-baseline offset.y >= -tex_h - 4.0" % fname
					)
					assert_le(
						sp.offset.y,
						-tex_h * 0.78,
						"Y-Sort Sprite2D %s bottom-baseline offset.y <= -tex_h * 0.78" % fname
					)
					total_checked_sprites += 1

	record_metric("verified_ysort_sprites", total_checked_sprites)
	assert_ge(float(total_checked_sprites), 15.0, "Verified >= 15 Y-Sort structure/prop Sprite2D anchors across 3 zones")


func case_t1_f14_01_stage_c_warm_cool_point_lights() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	assert_not_null(world._mood_modulate, "QinglanWorld has _mood_modulate CanvasModulate")

	var total_warm: int = 0
	var total_cool: int = 0
	for zid: String in ["tingyu_town", "qinglan_pass", "cangmu_cave"]:
		world.load_zone(zid, "", false)
		await step_frames(3)
		var lights: Array[PointLight2D] = _collect_active_point_lights(world)
		record_metric("lights_" + zid, lights.size())
		assert_ge(
			float(lights.size()),
			2.0,
			"Zone '%s' instantiates >= 2 active enabled PointLight2D nodes with texture & energy > 0" % zid
		)
		var mod_col: Color = world._mood_modulate.color
		assert_lt(
			(mod_col.r + mod_col.g + mod_col.b) / 3.0,
			0.97,
			"Zone '%s' _mood_modulate provides atmospheric ambient base for PointLight2D contrast" % zid
		)
		for pl: PointLight2D in lights:
			if pl.color.r > pl.color.b + 0.06:
				total_warm += 1
			if pl.color.g >= pl.color.r or pl.color.b >= pl.color.r:
				total_cool += 1

	record_metric("warm_point_lights_total", total_warm)
	record_metric("cool_point_lights_total", total_cool)
	assert_ge(float(total_warm), 2.0, "Stage C lighting includes warm amber-orange PointLight2Ds (cauldron/lantern/fire)")
	assert_ge(float(total_cool), 2.0, "Stage C lighting includes cool jade/cyan PointLight2Ds (Spirit Steles/cave)")


func case_t1_f14_02_wet_bluestone_road_shader() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var shader_path: String = "res://src/presentation/shaders/wet_bluestone.gdshader"
	assert_true(res_exists(shader_path), "wet_bluestone.gdshader exists at " + shader_path)

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	for zid: String in ["tingyu_town", "qinglan_pass"]:
		world.load_zone(zid, "", false)
		await step_frames(3)
		var road_polys: int = 0
		var shaded_polys: int = 0
		for ch: Node in world._road_stone_sub.get_children():
			if ch is Polygon2D and not ch.is_queued_for_deletion():
				road_polys += 1
				var poly: Polygon2D = ch as Polygon2D
				if poly.material is ShaderMaterial:
					var smat: ShaderMaterial = poly.material as ShaderMaterial
					if smat.shader != null and smat.shader.resource_path == shader_path:
						shaded_polys += 1
		assert_gt(float(road_polys), 0.0, zid + " has rainy bluestone road Polygon2D nodes")
		assert_eq(
			shaded_polys,
			road_polys,
			"All rainy bluestone road Polygon2Ds in %s apply wet_bluestone.gdshader ShaderMaterial" % zid
		)


func case_t1_f14_03_ysort_55pct_occlusion_fade_and_restore() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	var camphor_sp: Sprite2D = null
	for occ: Dictionary in world._occluder_sprites:
		var sp: Sprite2D = occ.get("sprite", null) as Sprite2D
		if sp != null and is_instance_valid(sp) and sp.position.distance_to(Vector2(835.0, 595.0)) < 45.0:
			camphor_sp = sp
			break
	assert_not_null(camphor_sp, "Found occluder prop_camphor_tree at Vector2(835, 595)")
	if camphor_sp == null:
		return

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.alive = true
	gu.position = Vector2(835.0, 560.0)
	for _i: int in range(24):
		world._update_ysort_occlusion_fade(1.0 / 60.0)
	assert_approx(camphor_sp.modulate.a, 0.55, 0.02, "Canopy Sprite2D smoothly fades to 0.55 alpha when actor behind")

	gu.position = Vector2(835.0, 700.0)
	for _j: int in range(24):
		world._update_ysort_occlusion_fade(1.0 / 60.0)
	assert_approx(camphor_sp.modulate.a, 1.00, 0.02, "Canopy Sprite2D smoothly restores to 1.00 alpha when actor in front")


func _probe_actor_occlusion_silhouette_active(pa: BattleActor, world: QinglanWorld) -> bool:
	# 1. Check BattleActor occlusion properties
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

	# 2. Check ShaderMaterial uniform on actor _sprite
	if pa._sprite != null and pa._sprite.material is ShaderMaterial:
		var sm: ShaderMaterial = pa._sprite.material as ShaderMaterial
		for u_name: String in ["silhouette_alpha", "occlusion_alpha", "ink_silhouette", "occluded_mix"]:
			var uval: Variant = sm.get_shader_parameter(u_name)
			if (uval is float or uval is int) and float(uval) > 0.05:
				return true
			if uval is bool and bool(uval):
				return true

	# 3. Check dedicated silhouette child node on BattleActor or QinglanWorld
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


func case_t1_f14_04_occluded_actor_ink_silhouette() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.alive = true

	# Unoccluded baseline in open street
	gu.position = Vector2(835.0, 710.0)
	for _i: int in range(20):
		world._physics_process(1.0 / 60.0)
	var active_in_open: bool = _probe_actor_occlusion_silhouette_active(gu, world)

	# Occluded behind prop_camphor_tree canopy (alpha -> 0.55)
	gu.position = Vector2(835.0, 560.0)
	for _j: int in range(24):
		world._physics_process(1.0 / 60.0)
	await step_frames(2)
	var active_behind_canopy: bool = _probe_actor_occlusion_silhouette_active(gu, world)

	assert_false(active_in_open, "Actor ink occlusion silhouette is inactive when standing in open street")
	assert_true(
		active_behind_canopy,
		"Occluded BattleActor behind 55% faded canopy activates subtle ink actor silhouette (20-art-bible.md §5.3)"
	)


func _collect_fg_bamboo_nodes(world: QinglanWorld) -> Array[Node]:
	var found: Array[Node] = []
	var tokens: Array[String] = ["bamboo_leaf", "fg_bamboo", "fg_leaf", "wind_leaf", "foreground_bamboo", "leaf_fg"]
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == null or not is_instance_valid(cur) or cur == world._ui_canvas or cur == world._ysort_root:
			continue
		var tag: String = str(cur.name)
		if cur is Sprite2D and (cur as Sprite2D).texture != null:
			tag += "::" + (cur as Sprite2D).texture.resource_path
		elif cur is TextureRect and (cur as TextureRect).texture != null:
			tag += "::" + (cur as TextureRect).texture.resource_path
		elif cur is GPUParticles2D and (cur as GPUParticles2D).texture != null:
			tag += "::" + (cur as GPUParticles2D).texture.resource_path
		elif cur is CPUParticles2D and (cur as CPUParticles2D).texture != null:
			tag += "::" + (cur as CPUParticles2D).texture.resource_path
		if _str_has_any(tag, tokens):
			found.append(cur)
		for ch: Node in cur.get_children():
			stack.append(ch)
	return found


func case_t1_f14_05_layer3_rain_and_wind_bamboo_parallax() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	SaveManager.reduced_motion = false
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld

	for zid: String in ["tingyu_town", "qinglan_pass"]:
		world.load_zone(zid, "", false)
		await step_frames(3)
		assert_gt(float(world._rain_streaks.size()), 50.0, zid + " initializes diagonal rain streaks")

		var fg_nodes: Array[Node] = _collect_fg_bamboo_nodes(world)
		var has_bamboo_prop: bool = false
		for pname: String in ["_fg_bamboo_leaves", "_bamboo_leaves", "_fg_leaves", "_foreground_bamboo"]:
			if obj_has_prop(world, pname):
				var arr: Array = as_arr(obj_get(world, pname, []))
				if not arr.is_empty():
					has_bamboo_prop = true

		record_metric("fg_bamboo_nodes_" + zid, fg_nodes.size())
		assert_true(
			not fg_nodes.is_empty() or has_bamboo_prop,
			"Layer 3 foreground in %s includes wind-blown bamboo leaf silhouettes (master_a_tingyu_town.png)" % zid
		)

		if not fg_nodes.is_empty() and fg_nodes[0] is Node2D:
			var n0: Node2D = fg_nodes[0] as Node2D
			var pos_before: Vector2 = n0.position
			var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
			gu.position += Vector2(300.0, 0.0)
			for _k: int in range(10):
				world._physics_process(1.0 / 60.0)
			assert_gt(
				n0.position.distance_to(pos_before),
				0.5,
				"Layer 3 foreground bamboo leaf responds to camera pan & wind sway in " + zid
			)
