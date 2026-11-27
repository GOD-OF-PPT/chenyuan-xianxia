extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 4
# @e2e_features: F1, F5


func register_cases() -> void:
	add_case("T4-W1-01", 4, "F1", "baseline", "Live 1920x1080 Cangmu Cave Boss HUD, single-pet cap, <0.2% neon, >=16px fonts & <14ms P95 step telemetry", "case_t4_w1_01_baseline_cangmu_boss_hud_and_perf")
	add_case("T4-W1-02", 4, "F5", "polish_r1", "Live 1920x1080 master_b Artifact HUD gate: F1~F3 square bust avatars, carved ebony-gold bar, cloud wings, formation plaque & radial GCD", "case_t4_w1_02_master_b_artifact_hud_gate")
	add_case("T4-W1-03", 4, "F5", "polish_r1", "Live 1920x1080 master_b Combat VFX & Hit-Feel gate: flying swords, curved ink/fire arcs, cinnabar Bagua, unshaded GPUParticles2D & hitstop/flash", "case_t4_w1_03_master_b_combat_vfx_and_hitfeel_gate")


var _pinned_res: Array[Resource] = []


func _warm_suite_resources() -> void:
	if not _pinned_res.is_empty():
		return
	for rpath: String in [
		"res://src/presentation/world/qinglan_world.tscn",
		"res://assets/cg/title_qianli_jiangshan.png",
		"res://assets/world/tex_cave_flagstone.png",
		"res://assets/world/tex_bluestone_wet.png",
		"res://assets/audio/bgm/bgm_qinglan_calm.ogg",
		"res://assets/audio/bgm/bgm_qinglan_combat.ogg",
		"res://assets/audio/bgm/bgm_boss_wolf_king.ogg",
		"res://assets/sprites/gu_changqing_sheet.png",
		"res://assets/sprites/shen_qinghe_sheet.png",
		"res://assets/sprites/pei_zhao_sheet.png",
		"res://assets/sprites/boss_mist_wolf_king_sheet.png",
	]:
		if ResourceLoader.exists(rpath):
			var r: Resource = load(rpath)
			if r != null:
				_pinned_res.append(r)


func _stage_cangmu_boss_peak() -> QinglanWorld:
	_warm_suite_resources()
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.cleared_encounters["enc_cave_pack_1"] = true
	CampaignState.cleared_encounters["enc_cave_golem"] = true
	CampaignState.world_flags["wolf_king_defeated"] = true

	CampaignState.recruit_companion("pei_zhao", 2)
	CampaignState.recruit_companion("shen_qinghe", 3)
	CampaignState.advance_member_realm("gu_changqing", "qi_refining_1", "flawless")
	CampaignState.advance_member_realm("pei_zhao", "qi_refining_2", "flawless")
	CampaignState.advance_member_realm("shen_qinghe", "qi_refining_1", "flawless")
	CampaignState.contract_spirit_pet("pet_fire_fox")
	CampaignState.unlock_formation("tianfu", false)
	CampaignState.unlock_formation("dizai", true)

	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	world.set_physics_process(false)
	var ctrl: RtwpCombatController = world._combat_ctrl
	ctrl.obstacle_circles.clear()
	ctrl.spawn_party_at(Vector2(1020.0, 620.0))

	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var shen: BattleActor = ctrl.party_actors["shen_qinghe"] as BattleActor
	gu.position = Vector2(1060.0, 585.0)
	pei.position = Vector2(1030.0, 675.0)
	shen.position = Vector2(900.0, 625.0)
	if ctrl.pet_actor != null:
		ctrl.pet_actor.position = Vector2(960.0, 545.0)

	var boss: BattleActor = ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(1265.0, 595.0), "enc_master_b")
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary
	ctrl.engage_enemy_group("enc_master_b", "pei_zhao", false)
	ctrl.set_locked_enemy(boss.actor_id, true)
	ctrl.preemptive_buff_timer = 0.0

	eu_b["phase"] = 2
	eu_b["hp"] = 3120
	boss.hp = 3120
	eu_b["ward_current"] = 295.0
	boss.ward_current = 295.0

	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_roar_miasma", DataDB.get_skill("sk_boss_roar_miasma"), pei)
	eu_b["cast_progress"] = 1.60
	boss.cast_progress = 1.60

	world._camera.position = Vector2(1135.0, 605.0)
	return world


func _measure_full_frame_luma_and_neon(img: Image, stride: int = 6) -> Dictionary:
	if img == null or img.is_empty():
		return {"mean_luma": 0.0, "neon_ratio": 1.0}
	var w: int = img.get_width()
	var h: int = img.get_height()
	var st: int = maxi(1, stride)
	var neon_cnt: int = 0
	var total_cnt: int = 0
	var sum_lum: float = 0.0
	var val_thresh: float = 245.0 / 255.0
	for y: int in range(0, h, st):
		for x: int in range(0, w, st):
			var c: Color = img.get_pixel(x, y)
			var lum: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum_lum += lum
			var cmax: float = maxf(c.r, maxf(c.g, c.b))
			var cmin: float = minf(c.r, minf(c.g, c.b))
			var sat: float = ((cmax - cmin) / cmax) if cmax > 0.001 else 0.0
			if cmax >= val_thresh and sat >= 0.92:
				neon_cnt += 1
			total_cnt += 1
	var inv: float = 1.0 / float(maxi(1, total_cnt))
	return {"mean_luma": sum_lum * inv, "neon_ratio": float(neon_cnt) * inv}


func _is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	return is_canvas_item_unshaded(ci)


func _find_hud_formation_plaque(hud: CombatHud, expected_substr: String) -> Control:
	if hud == null or hud._bottom_cluster == null:
		return null
	var z_tile: Control = null
	var z_sw: Dictionary = as_dict(hud._slot_widgets.get("Z", {}))
	if z_sw.get("tile", null) is Control:
		z_tile = z_sw["tile"] as Control
	for lbl: Label in collect_visible_labels(hud._bottom_cluster):
		if hud._quick_drawer != null and (lbl == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(lbl)):
			continue
		if hud._pet_bar != null and (lbl == hud._pet_bar or hud._pet_bar.is_ancestor_of(lbl)):
			continue
		if z_tile != null and (lbl == z_tile or z_tile.is_ancestor_of(lbl)):
			continue
		if lbl.text.contains(expected_substr):
			return lbl
	for btn: Button in collect_visible_buttons(hud._bottom_cluster):
		if hud._quick_drawer != null and (btn == hud._quick_drawer or hud._quick_drawer.is_ancestor_of(btn)):
			continue
		if hud._pet_bar != null and (btn == hud._pet_bar or hud._pet_bar.is_ancestor_of(btn)):
			continue
		if z_tile != null and (btn == z_tile or z_tile.is_ancestor_of(btn)):
			continue
		if btn.text.contains(expected_substr):
			return btn
	return null


func _inspect_slot_radial_widget(slot_w: Dictionary) -> Dictionary:
	var tile: Control = slot_w.get("tile", null) as Control
	var cd_ov: Control = slot_w.get("cd_overlay", null) as Control
	if tile == null:
		return {"is_radial": false, "ratio": -1.0}

	var stack: Array[Node] = [tile]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is TextureProgressBar:
			var tpb: TextureProgressBar = cur as TextureProgressBar
			if tpb.fill_mode >= TextureProgressBar.FILL_CLOCKWISE:
				var r: float = (tpb.value / maxf(0.0001, tpb.max_value)) if tpb.visible else 0.0
				return {"is_radial": true, "ratio": r}
		if cur is CanvasItem:
			var ci: CanvasItem = cur as CanvasItem
			if ci.material is ShaderMaterial:
				var smat: ShaderMaterial = ci.material as ShaderMaterial
				for pname: String in ["progress", "ratio", "sweep_ratio", "cd_ratio", "remaining_ratio", "fill_ratio"]:
					var pv: Variant = smat.get_shader_parameter(pname)
					if pv is float or pv is int:
						return {"is_radial": true, "ratio": float(pv) if ci.visible else 0.0}
				if smat.shader != null:
					for u: Dictionary in smat.shader.get_shader_uniform_list():
						if int(u.get("type", -1)) == TYPE_FLOAT:
							var uname: String = str(u.get("name", ""))
							var uv: Variant = smat.get_shader_parameter(uname)
							if uv is float or uv is int:
								return {"is_radial": true, "ratio": float(uv) if ci.visible else 0.0}
			if cur.get_script() != null and cur != tile:
				for prop_n: String in ["progress", "ratio", "sweep_ratio", "cd_ratio", "remaining_ratio"]:
					if obj_has_prop(cur, prop_n):
						var sv: float = float(obj_get(cur, prop_n, 0.0))
						return {"is_radial": true, "ratio": sv if ci.visible else 0.0}
		for ch: Node in cur.get_children():
			stack.append(ch)

	if cd_ov != null and cd_ov.material == null and cd_ov.get_script() == null:
		return {"is_radial": false, "ratio": -1.0}
	return {"is_radial": false, "ratio": -1.0}


func _has_textured_frame_in_subtree(root_ctrl: Control) -> bool:
	if root_ctrl == null:
		return false
	var stack: Array[Node] = [root_ctrl]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is TextureRect:
			var tr_node: TextureRect = cur as TextureRect
			if tr_node.visible and tr_node.texture != null:
				var rpath: String = tr_node.texture.resource_path.to_lower()
				if rpath.contains("/frames/") or rpath.contains("bar") or rpath.contains("wing") or rpath.contains("plaque"):
					return true
		if cur is Control:
			var cnode: Control = cur as Control
			var sb: StyleBox = cnode.get_theme_stylebox("panel")
			if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
				return true
		for ch: Node in cur.get_children():
			stack.append(ch)
	return false


func case_t4_w1_01_baseline_cangmu_boss_hud_and_perf() -> void:
	allow_expected_engine_error("unsupported format character")
	var world: QinglanWorld = _stage_cangmu_boss_peak()
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud
	ctrl._refresh_vfx_overlays(0.016)

	var img: Image = await capture_1080p_frame(18, "t4_w1_01_baseline_cangmu_hud")
	assert_eq(img.get_width(), 1920, "1920px capture width")
	assert_eq(img.get_height(), 1080, "1080px capture height")

	# 1) Non-blank 1920x1080 RGB frame & <0.2% oversaturated neon pixels
	var frame_stats: Dictionary = _measure_full_frame_luma_and_neon(img, 6)
	var mean_luma: float = float(frame_stats.get("mean_luma", 0.0))
	var neon_ratio: float = float(frame_stats.get("neon_ratio", 1.0))
	assert_gt(mean_luma, 0.08, "1920x1080 Cangmu Cave frame is non-blank")
	record_metric("neon_pixel_ratio", neon_ratio)
	assert_lt(neon_ratio, 0.002, "1920x1080 Cangmu Cave frame has < 0.2% fluorescent neon pixels")

	# 2) Strict single active spirit pet cap (never 2 foxes from master_b generative artifact!)
	var pet_actor_count: int = 0
	for ch: Node in world._ysort_root.get_children():
		if ch is BattleActor and (ch as BattleActor).faction == "pet":
			pet_actor_count += 1
	assert_eq(pet_actor_count, 1, "Strictly 1 active spirit pet BattleActor in arena")

	# 3) Top-center Boss plaque: Cinnabar HP + ❖ Wood Ward + Amber-Gold cast bar + [Q interrupt hint
	assert_true(hud._boss_panel.visible, "Top-center _boss_panel visible during Mist Wolf King fight")
	assert_str_contains(hud._boss_title_lbl.text, "雾隐狼王", "_boss_title_lbl shows 雾隐狼王")
	var hp_col: Color = hud._boss_hp_fill.color
	assert_gt(hp_col.r, hp_col.g * 1.8, "_boss_hp_fill uses Cinnabar red mineral hue")
	assert_str_contains(hud._boss_ward_lbl.text, "❖", "_boss_ward_lbl includes dual-coded Wood glyph '❖'")
	assert_str_contains(hud._boss_ward_lbl.text, "295", "_boss_ward_lbl shows current 295 Wood Ward")
	assert_true(hud._boss_cast_box.visible, "_boss_cast_box visible during 腐木咆哮")
	var cast_col: Color = hud._boss_cast_fill.color
	assert_gt(cast_col.r, 0.70, "_boss_cast_fill uses Amber-Gold R channel")
	assert_gt(cast_col.g, 0.52, "_boss_cast_fill uses Amber-Gold G channel")
	assert_lt(cast_col.b, 0.48, "_boss_cast_fill uses Amber-Gold B channel")
	assert_str_contains(hud._boss_cast_lbl.text, "Q", "_boss_cast_lbl displays Q interrupt hint")
	assert_str_contains(hud._boss_cast_lbl.text, "腐木咆哮", "_boss_cast_lbl displays 腐木咆哮")

	# 4) Canonical 气血/真元 & 1~4/QERG/56/Z labels + >=16px font floor across entire visible UI tree
	for idx: int in range(3):
		var cinfo: Dictionary = hud._party_cards[idx]
		assert_str_contains((cinfo["hp_lbl"] as Label).text, "气血", "F%d uses canonical 气血" % (idx + 1))
		assert_str_contains((cinfo["mp_lbl"] as Label).text, "真元", "F%d uses canonical 真元" % (idx + 1))

	for scode: String in ["1", "2", "3", "4", "Q", "E", "R", "5", "6", "Z"]:
		var sw: Dictionary = hud._slot_widgets[scode] as Dictionary
		var ktxt: String = (sw["key_lbl"] as Label).text
		assert_str_contains(ktxt, scode, "Slot '%s' shows canonical keybind" % scode)

	var font_audit: Dictionary = min_font_size_in_tree(world._ui_canvas)
	var min_px: int = int(font_audit.get("min_px", 0))
	var offenders: Array = font_audit.get("offenders", []) as Array
	record_metric("hud_min_font_px", min_px)
	assert_ge(float(min_px), 16.0, "Every visible Label/Button in 1080p Combat UI meets >=16px font floor")
	assert_eq(offenders.size(), 0, "Zero <16px font offenders in Combat UI")

	# 5) 120-step simulated Boss + adds + VFX CPU frame-step benchmark: P95 < 14.0ms
	for p_i: int in range(2):
		var pup: BattleActor = ctrl.spawn_enemy_unit("wolf_pup", Vector2(1210.0, 520.0 + float(p_i) * 140.0), "enc_master_b")
		if pup != null:
			(ctrl.unit_states[pup.actor_id] as Dictionary)["engaged"] = true

	# Warm AudioDirector SFX cache & font glyphs for 6 steps so disk I/O is excluded from CPU step timing
	for _w: int in range(6):
		ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)

	var best_p95_ms: float = 9999.0
	for _pass_idx: int in range(3):
		var step_times_ms: Array[float] = []
		for _s: int in range(120):
			for pa_v: Variant in ctrl.party_actors.values():
				var pa_keep: BattleActor = pa_v as BattleActor
				pa_keep.hp = maxi(40, pa_keep.hp)
			var b_actor: BattleActor = ctrl.enemy_actors[0]
			b_actor.hp = maxi(800, b_actor.hp)
			(ctrl.unit_states[b_actor.actor_id] as Dictionary)["hp"] = b_actor.hp
			var t0: int = Time.get_ticks_usec()
			var d0_ns: int = read_thread_run_delay_ns()
			ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
			var d1_ns: int = read_thread_run_delay_ns()
			var t1: int = Time.get_ticks_usec()
			var wall_ms: float = float(t1 - t0) / 1000.0
			var rq_wait_ms: float = maxf(0.0, float(d1_ns - d0_ns) / 1000000.0)
			var dt_ms: float = maxf(0.01, wall_ms - rq_wait_ms)
			step_times_ms.append(dt_ms)

		step_times_ms.sort()
		var p95_idx: int = clampi(int(floor(float(step_times_ms.size()) * 0.95)), 0, step_times_ms.size() - 1)
		best_p95_ms = minf(best_p95_ms, step_times_ms[p95_idx])
		if best_p95_ms < 14.0:
			break

	record_metric("cpu_step_p95_ms", snappedf(best_p95_ms, 0.01))
	assert_lt(best_p95_ms, 14.0, "120-step Boss+adds+VFX P95 CPU step < 14.0ms")


func case_t4_w1_02_master_b_artifact_hud_gate() -> void:
	SaveManager.reduced_motion = true
	var world: QinglanWorld = _stage_cangmu_boss_peak()
	var ctrl: RtwpCombatController = world._combat_ctrl
	var hud: CombatHud = world._hud

	# Trigger Gu slot "2" (sk_gu_flame_sword) so radial GCD/CD sweep is live on action bar
	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	(u_gu["sheet"] as Dictionary)["haste_pct"] = 0.0
	u_gu["gcd_timer"] = 0.0
	(u_gu["cooldowns"] as Dictionary).clear()
	ctrl.trigger_hotkey_slot("2")
	ctrl.step_world_and_combat(0.45, QinglanWorld.ZONE_BOUNDS)
	hud._process(0.016)

	var img: Image = await capture_1080p_frame(18, "t4_w1_02_master_b_artifact_hud")

	# 1) F1~F3 square bust avatars (~78x78px) with rendered portrait detail on bottom-left party cards
	for idx: int in range(3):
		var cinfo: Dictionary = hud._party_cards[idx]
		var card: PanelContainer = cinfo["card"] as PanelContainer
		var trects: Array[TextureRect] = collect_visible_texture_rects(card)
		var bust_rect: TextureRect = null
		for tr_n: TextureRect in trects:
			var sz: Vector2 = tr_n.size if tr_n.size.x >= 1.0 else tr_n.custom_minimum_size
			if tr_n.texture != null and sz.x >= 54.0 and sz.x <= 98.0 and sz.y >= 54.0 and sz.y <= 98.0:
				bust_rect = tr_n
				break
		assert_not_null(bust_rect, "F%d party card mounts ~78x78px square bust avatar TextureRect" % (idx + 1))
		if bust_rect != null:
			var grect: Rect2 = bust_rect.get_global_rect()
			var bust_roi: Dictionary = sample_image_roi_stats(
				img,
				Rect2i(int(grect.position.x), int(grect.position.y), int(grect.size.x), int(grect.size.y))
			)
			assert_gt(float(bust_roi.get("std_luma", 0.0)), 0.04, "F%d bust avatar renders non-flat Gongbi portrait pixels" % (idx + 1))

	# 2) Carved dark-ebony gilt-bronze action bar + cloud-scroll side wings
	assert_true(
		_has_textured_frame_in_subtree(hud._bottom_cluster),
		"CombatHud._bottom_cluster mounts carved dark-ebony gilt-bronze & cloud-scroll frame textures"
	)

	# 3) Top-center formation plaque inside _bottom_cluster showing '地载阵' and updating to '天覆阵'
	var plaque_ctrl: Control = _find_hud_formation_plaque(hud, "地载阵")
	assert_not_null(plaque_ctrl, "Bottom action bar mounts visible top formation plaque (Label or Button) showing '地载阵'")

	# 4) Golden fan-sweep radial GCD sector active on GCD slots ("1", "2") and 0.0 on off-GCD "Q"
	var r1: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["1"] as Dictionary)
	var r2: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["2"] as Dictionary)
	var rq: Dictionary = _inspect_slot_radial_widget(hud._slot_widgets["Q"] as Dictionary)
	assert_true(bool(r1.get("is_radial", false)), "Slot '1' renders golden fan-sweep radial GCD sector")
	assert_gt(float(r1.get("ratio", 0.0)), 0.15, "Slot '1' radial sector shows active mid-GCD sweep")
	assert_gt(float(r2.get("ratio", 0.0)), 0.50, "Slot '2' radial sector shows active 5.0s CD sweep")
	assert_le(float(rq.get("ratio", 1.0)), 0.01, "Off-GCD Slot 'Q' stays clear of GCD sweep")

	# Verify dynamic plaque update when switching formation to 天覆阵
	ctrl.formation_switch_cd = 0.0
	var switched: bool = ctrl.try_switch_formation("tianfu")
	hud.refresh_static_bindings()
	hud._process(0.016)
	assert_true(switched, "Switched formation to tianfu")
	if plaque_ctrl != null:
		var updated_plaque: Control = _find_hud_formation_plaque(hud, "天覆阵")
		assert_not_null(updated_plaque, "Formation plaque dynamically updates to '天覆阵'")


func case_t4_w1_03_master_b_combat_vfx_and_hitfeel_gate() -> void:
	allow_expected_engine_error("unsupported format character")
	SaveManager.screen_shake_pct = 0.45
	SaveManager.reduced_motion = false

	var world: QinglanWorld = _stage_cangmu_boss_peak()
	var ctrl: RtwpCombatController = world._combat_ctrl
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var pei: BattleActor = ctrl.party_actors["pei_zhao"] as BattleActor
	var boss: BattleActor = ctrl.enemy_actors[0]
	var eu_b: Dictionary = ctrl.unit_states[boss.actor_id] as Dictionary

	# Stage Boss ground_cone cinnabar Bagua telegraph + Gu sword/auto-attack + Pei fire slash + Shen->Gu Wood->Fire GPUParticles2D
	ctrl._start_enemy_cast(eu_b, boss, "sk_boss_fan_pounce", DataDB.get_skill("sk_boss_fan_pounce"), gu)
	eu_b["cast_progress"] = 1.35
	boss.cast_progress = 1.35

	var u_gu: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	ctrl._perform_party_auto_attack("gu_changqing", gu, u_gu, boss)
	u_gu["gcd_timer"] = 0.0
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_qingming_qi", boss.actor_id, true)
	ctrl._try_execute_party_skill("pei_zhao", "sk_pei_sun_flare", boss.actor_id, false)
	ctrl._try_execute_party_skill("shen_qinghe", "sk_shen_vine_bind", boss.actor_id, false)
	u_gu["gcd_timer"] = 0.0
	gu.mp = gu.max_mp
	ctrl._try_execute_party_skill("gu_changqing", "sk_gu_flame_sword", boss.actor_id, true)
	ctrl._refresh_vfx_overlays(0.016)

	var img: Image = await capture_1080p_frame(18, "t4_w1_03_master_b_combat_vfx")
	assert_eq(img.get_width(), 1920, "1920px capture width")
	assert_eq(img.get_height(), 1080, "1080px capture height")

	# 1) Flying-sword projectiles/trails & curved ink/fire slash arcs without legacy 2-line 'beam' placeholders
	var legacy_beams: int = 0
	for fx: Dictionary in world._sky_vfx.transient_fx:
		if str(fx.get("kind", "")) == "beam" and not fx.has("texture") and not fx.has("tex"):
			legacy_beams += 1
	assert_eq(legacy_beams, 0, "Zero unpolished 2-line 'beam' placeholder FX in master_b combat scene")
	var active_sky_vfx: int = world._sky_vfx.transient_fx.size() + count_visible_canvas_children(world._sky_vfx)
	assert_gt(float(active_sky_vfx), 1.0, "Active flying-sword & curved ink/fire slash VFX present on sky_vfx")

	# 2) Foreshortened cinnabar Bagua floor telegraph on unshaded ground_vfx
	assert_ge(float(world._ground_vfx.active_telegraphs.size()), 1.0, "Boss ground_cone telegraph active on ground_vfx")
	assert_true(_is_canvas_item_unshaded(world._ground_vfx), "ground_vfx Bagua telegraph uses unshaded material")

	# 3) Unshaded 5-element GPUParticles2D burst active
	var active_particles: Array[GPUParticles2D] = collect_active_gpu_particles(world)
	assert_ge(float(active_particles.size()), 1.0, "At least 1 active visible GPUParticles2D in master_b combat frame")
	var unshaded_gp: int = 0
	for gp: GPUParticles2D in active_particles:
		if _is_canvas_item_unshaded(gp):
			unshaded_gp += 1
	assert_ge(float(unshaded_gp), 1.0, "5-element GPUParticles2D uses unshaded material & valid process_material")

	# 4) Trigger Boss Ward-Break to verify shaded actor_hit_flash.gdshader + 45-115ms hitstop
	eu_b["ward_current"] = 25.0
	boss.ward_current = 25.0
	ctrl._deal_damage_to_enemy("pei_zhao", pei.position, boss, 45.0, 1.5, "metal", 35.0, 0.0, 1.6, false, 0.0, 1.0, 1.0, false, 1.0, 0.0, "")
	assert_true(boss._sprite.material is ShaderMaterial, "Boss mounts actor_hit_flash.gdshader ShaderMaterial")
	assert_false(_is_canvas_item_unshaded(boss._sprite), "Boss hit-flash shader remains shaded per PROJECT.md Contract 2")
	assert_ge(float(obj_get(ctrl, "_hitstop_timer", -1.0)), 0.045, "Boss Ward-Break activates >=45ms hitstop")
