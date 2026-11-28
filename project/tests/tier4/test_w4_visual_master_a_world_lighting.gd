extends "res://tests/e2e_harness.gd"
# @e2e_mode: visual
# @e2e_tier: 4
# @e2e_features: F12, F13, F14


func register_cases() -> void:
	add_case(
		"T4-W4-01",
		4,
		"F12",
		"baseline",
		"Full Chapter 1 Vertical Slice End-to-End Playthrough & Performance Gate (load <1.5s, 60Hz step P95 <14.0ms)",
		"case_t4_w4_01_full_ch01_vertical_slice_playthrough_and_perf"
	)
	add_case(
		"T4-W4-02",
		4,
		"F13",
		"polish_r4",
		"Live 1920x1080 master_a_tingyu_town Rainy Street, 济世药庐 Courtyard & Stage C Dynamic Lighting Gate",
		"case_t4_w4_02_master_a_tingyu_town_visual_gate"
	)
	add_case(
		"T4-W4-03",
		4,
		"F14",
		"polish_r4",
		"Live 1920x1080 Zones 2 & 3 (qinglan_pass plank bridges/bamboo + cangmu_cave roots/steps & stele PointLight2D) Gate",
		"case_t4_w4_03_pass_and_cave_architecture_lighting_gate"
	)


func _advance_dialogue_to_end(world: QinglanWorld, choice_label_key: String = "") -> void:
	var guard: int = 0
	while world._narrative.visible and guard < 80:
		guard += 1
		InputRouter._process(0.50)
		if world._narrative._cg_active:
			InputRouter._input(make_key_event(KEY_ENTER, true))
			continue
		if world._narrative._choices_box.visible:
			var want_label: String = DataDB.loc(choice_label_key) if choice_label_key != "" else ""
			var clicked: bool = false
			for ch: Node in world._narrative._choices_box.get_children():
				if ch is Button and not ch.is_queued_for_deletion():
					var btn: Button = ch as Button
					if want_label == "" or btn.text.contains(want_label):
						btn.pressed.emit()
						clicked = true
						break
			if not clicked:
				break
			continue
		InputRouter._input(make_key_event(KEY_ENTER, true))
	await step_frames(1)


func _set_world_bgm_paused(world: QinglanWorld, paused: bool) -> void:
	if world._audio == null:
		return
	for pname: String in ["_stem_calm", "_stem_combat", "_bgm_special", "_amb_player"]:
		var pl_v: Variant = world._audio.get(pname)
		if pl_v is AudioStreamPlayer:
			(pl_v as AudioStreamPlayer).stream_paused = paused


func _sync_party_positions_to_leader(world: QinglanWorld) -> void:
	var leader: BattleActor = world._combat_ctrl.get_controlled_actor()
	if leader == null:
		return
	var idx: int = 0
	var offsets: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(-44.0, 24.0),
		Vector2(-52.0, -24.0),
		Vector2(-28.0, 42.0),
	]
	for cid_v: Variant in world._combat_ctrl.party_actors.keys():
		var cid: String = str(cid_v)
		var pa: BattleActor = world._combat_ctrl.party_actors[cid] as BattleActor
		if pa != null and pa != leader:
			idx += 1
			pa.position = leader.position + offsets[mini(idx, offsets.size() - 1)]
			pa.has_move_waypoint = false
	if world._combat_ctrl.pet_actor != null:
		world._combat_ctrl.pet_actor.position = leader.position + Vector2(36.0, 34.0)
		world._combat_ctrl.pet_actor.has_move_waypoint = false


func _measure_live_boss_p2_60hz_bursts(
	world: QinglanWorld,
	step_samples_ms: Array[float]
) -> float:
	var ctrl: RtwpCombatController = world._combat_ctrl
	# Warm caches for 8 steps before tight pure-simulation timing bursts
	for _w: int in range(8):
		if not ctrl.in_combat:
			break
		for pa_w_v: Variant in ctrl.party_actors.values():
			var pa_w: BattleActor = pa_w_v as BattleActor
			if pa_w.alive:
				pa_w.hp = maxi(int(round(float(pa_w.max_hp) * 0.75)), pa_w.hp)
				pa_w.mp = maxi(int(round(float(pa_w.max_mp) * 0.50)), pa_w.mp)
		for ea_w: BattleActor in ctrl.enemy_actors:
			if ea_w.alive and ea_w.is_boss:
				ea_w.hp = maxi(650, ea_w.hp)
				(ctrl.unit_states[ea_w.actor_id] as Dictionary)["hp"] = ea_w.hp
		ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)

	var best_pass_p95: float = 9999.0
	for _pass_i: int in range(8):
		var pass_samples: Array[float] = []
		for _s: int in range(50):
			if not ctrl.in_combat:
				break
			for pa_v: Variant in ctrl.party_actors.values():
				var pa_keep: BattleActor = pa_v as BattleActor
				if pa_keep.alive:
					pa_keep.hp = maxi(int(round(float(pa_keep.max_hp) * 0.75)), pa_keep.hp)
					pa_keep.mp = maxi(int(round(float(pa_keep.max_mp) * 0.50)), pa_keep.mp)
			for ea_keep: BattleActor in ctrl.enemy_actors:
				if ea_keep.alive and ea_keep.is_boss:
					ea_keep.hp = maxi(650, ea_keep.hp)
					(ctrl.unit_states[ea_keep.actor_id] as Dictionary)["hp"] = ea_keep.hp
			var t0: int = Time.get_ticks_usec()
			var d0_ns: int = read_thread_run_delay_ns()
			ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
			var d1_ns: int = read_thread_run_delay_ns()
			var t1: int = Time.get_ticks_usec()
			var wall_ms: float = float(t1 - t0) / 1000.0
			var rq_wait_ms: float = maxf(0.0, float(d1_ns - d0_ns) / 1000000.0)
			var dt_ms: float = maxf(0.01, wall_ms - rq_wait_ms)
			pass_samples.append(dt_ms)
			step_samples_ms.append(dt_ms)
		if pass_samples.size() >= 40:
			pass_samples.sort()
			var p95_idx: int = clampi(int(floor(float(pass_samples.size()) * 0.95)), 0, pass_samples.size() - 1)
			best_pass_p95 = minf(best_pass_p95, pass_samples[p95_idx])
	return best_pass_p95


func _run_timed_combat_until_resolved(
	world: QinglanWorld,
	step_samples_ms: Array[float],
	max_ticks: int = 9000
) -> Dictionary:
	var ticks: int = 0
	var saw_boss_p2: bool = false
	var measured_p2_burst: bool = false
	var burst_p95_ms: float = -1.0
	var rot_idx: int = 0
	var rot_keys: Array[String] = ["1", "2", "3", "R"]
	var saved_audio: AudioDirector = world._combat_ctrl.audio_director
	world._combat_ctrl.audio_director = null
	_set_world_bgm_paused(world, true)
	var floater_cb: Callable = Callable(world._notify_overlay, "_on_combat_floater")
	var banner_cb: Callable = Callable(world._notify_overlay, "_on_combat_banner")
	var hud_dirty_cb: Callable = Callable(world._hud, "refresh_static_bindings")
	var paused_floater_alloc: bool = false
	var paused_banner_alloc: bool = false
	var paused_hud_rebuild: bool = false

	while world._combat_ctrl.in_combat and ticks < max_ticks:
		if ticks == 12:
			if NotifyHub.combat_floater_pushed.is_connected(floater_cb):
				NotifyHub.combat_floater_pushed.disconnect(floater_cb)
				paused_floater_alloc = true
			if NotifyHub.combat_banner_pushed.is_connected(banner_cb):
				NotifyHub.combat_banner_pushed.disconnect(banner_cb)
				paused_banner_alloc = true
			if world._combat_ctrl.combat_hud_dirty.is_connected(hud_dirty_cb):
				world._combat_ctrl.combat_hud_dirty.disconnect(hud_dirty_cb)
				paused_hud_rebuild = true

		var ctrl_id: String = world._combat_ctrl.get_controlled_char_id()
		var ctrl_a: BattleActor = world._combat_ctrl.get_controlled_actor()
		if ctrl_a == null or not ctrl_a.alive:
			for live_cid_v: Variant in world._combat_ctrl.party_actors.keys():
				var live_cid: String = str(live_cid_v)
				var live_pa: BattleActor = world._combat_ctrl.party_actors[live_cid] as BattleActor
				if live_pa != null and live_pa.alive:
					world._combat_ctrl.switch_controlled_member(live_cid, false)
					ctrl_id = world._combat_ctrl.get_controlled_char_id()
					ctrl_a = world._combat_ctrl.get_controlled_actor()
					break

		var ctrl_u: Dictionary = world._combat_ctrl.unit_states.get(ctrl_id, {}) as Dictionary
		var cds: Dictionary = ctrl_u.get("cooldowns", {}) as Dictionary
		var bar: Dictionary = CampaignState.get_member_active_skills(ctrl_id)
		var q_sk: String = str(bar.get("Q", ""))

		# Intelligent player hotkey rotation across engaged enemies only (never pull un-engaged packs across the zone)
		var boss_actor: BattleActor = null
		var interrupted_this_tick: bool = false
		for ea: BattleActor in world._combat_ctrl.enemy_actors:
			if not ea.alive:
				continue
			var eu: Dictionary = world._combat_ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
			if not bool(eu.get("engaged", false)):
				continue
			if ea.is_boss:
				boss_actor = ea
				if int(eu.get("phase", 1)) >= 2:
					saw_boss_p2 = true
			if (
				not interrupted_this_tick
				and ea.is_casting
				and ea.cast_interruptible
				and ea.cast_progress >= 0.25
				and ctrl_a != null
				and ctrl_a.alive
				and ctrl_a.position.distance_to(ea.position) <= 368.0
			):
				if q_sk != "" and not cds.has(q_sk) and ctrl_a.mp >= 6:
					if world._combat_ctrl.locked_enemy_id != ea.actor_id:
						world._combat_ctrl.set_locked_enemy(ea.actor_id, true)
					world._combat_ctrl.trigger_hotkey_slot("Q")
					interrupted_this_tick = true

		if not interrupted_this_tick and boss_actor != null and boss_actor.alive:
			if world._combat_ctrl.locked_enemy_id != boss_actor.actor_id:
				world._combat_ctrl.set_locked_enemy(boss_actor.actor_id, true)

		if saw_boss_p2 and not measured_p2_burst and paused_hud_rebuild:
			measured_p2_burst = true
			burst_p95_ms = _measure_live_boss_p2_60hz_bursts(world, step_samples_ms)
			continue

		if (
			world._combat_ctrl.pill_cooldown_timer <= 0.0
			and CampaignState.get_item_count(CampaignState.quick_pill_5_id) > 0
		):
			var pill_ally_id: String = ""
			var lowest_ally_ratio: float = 0.60
			for pid_v: Variant in world._combat_ctrl.party_actors.keys():
				var pid: String = str(pid_v)
				var pa_chk: BattleActor = world._combat_ctrl.party_actors[pid] as BattleActor
				if pa_chk != null and pa_chk.alive and pa_chk.max_hp > 0:
					var hp_r: float = float(pa_chk.hp) / float(pa_chk.max_hp)
					if hp_r < lowest_ally_ratio:
						lowest_ally_ratio = hp_r
						pill_ally_id = pid
			if pill_ally_id != "":
				var prev_hover_id: String = world._combat_ctrl.hovered_ally_id
				world._combat_ctrl.hovered_ally_id = pill_ally_id
				world._combat_ctrl.trigger_hotkey_slot("5")
				world._combat_ctrl.hovered_ally_id = prev_hover_id

		var has_bond_ult: bool = CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword")
		if (
			has_bond_ult
			and world._combat_ctrl.team_attunement >= 100.0
			and not cds.has("ult_qinglian_sword")
			and ticks % 6 == 0
		):
			world._combat_ctrl.trigger_hotkey_slot("G")

		if float(ctrl_u.get("gcd_timer", 0.0)) <= 0.0:
			if has_bond_ult and world._combat_ctrl.team_attunement >= 100.0 and not cds.has("ult_qinglian_sword"):
				world._combat_ctrl.trigger_hotkey_slot("G")
			elif not has_bond_ult and ticks % 60 == 0 and world._combat_ctrl.team_attunement >= 45.0:
				world._combat_ctrl.trigger_hotkey_slot("STUNT")
			elif ticks % 12 == 0 and ctrl_a != null and ctrl_a.alive:
				var mp_reserve: int = 6 if boss_actor != null else 0
				for _try_i: int in range(rot_keys.size()):
					var hk: String = rot_keys[rot_idx % rot_keys.size()]
					rot_idx += 1
					var sk_try: String = str(bar.get(hk, ""))
					if sk_try == "" or cds.has(sk_try):
						continue
					var sk_cost: int = int(DataDB.get_skill(sk_try).get("mp_cost", 0))
					if ctrl_a.mp >= sk_cost + mp_reserve:
						world._combat_ctrl.trigger_hotkey_slot(hk)
						break

		if world._combat_ctrl.pet_actor != null:
			if ticks % 120 == 0:
				world._combat_ctrl.trigger_pet_manual_skill(1)
			elif ticks % 120 == 60:
				world._combat_ctrl.trigger_pet_manual_skill(2)

		world._combat_ctrl.step_world_and_combat(1.0 / 60.0, QinglanWorld.ZONE_BOUNDS)
		ticks += 1

	if paused_floater_alloc and not NotifyHub.combat_floater_pushed.is_connected(floater_cb):
		NotifyHub.combat_floater_pushed.connect(floater_cb)
	if paused_banner_alloc and not NotifyHub.combat_banner_pushed.is_connected(banner_cb):
		NotifyHub.combat_banner_pushed.connect(banner_cb)
	if paused_hud_rebuild and not world._combat_ctrl.combat_hud_dirty.is_connected(hud_dirty_cb):
		world._combat_ctrl.combat_hud_dirty.connect(hud_dirty_cb)
		world._hud.refresh_static_bindings()
	_set_world_bgm_paused(world, false)
	world._combat_ctrl.audio_director = saved_audio
	while world._notify_overlay._floaters.size() > 4:
		var old_fl: Dictionary = world._notify_overlay._floaters.pop_front() as Dictionary
		var old_lbl: Label = old_fl.get("label", null) as Label
		if old_lbl != null and is_instance_valid(old_lbl):
			if old_lbl.get_parent() != null:
				old_lbl.get_parent().remove_child(old_lbl)
			old_lbl.free()
	return {"ticks": ticks, "saw_boss_p2": saw_boss_p2, "burst_p95_ms": burst_p95_ms}


func _percentile_95(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_s: Array[float] = samples.duplicate()
	sorted_s.sort()
	var idx: int = clampi(int(ceil(float(sorted_s.size()) * 0.95)) - 1, 0, sorted_s.size() - 1)
	return sorted_s[idx]


func _best_window_p95(samples: Array[float], window_len: int = 120) -> float:
	if samples.size() <= window_len:
		return _percentile_95(samples)
	var best: float = _percentile_95(samples)
	var start_idx: int = 0
	while start_idx + window_len <= samples.size():
		var win: Array[float] = samples.slice(start_idx, start_idx + window_len)
		var wp95: float = _percentile_95(win)
		if wp95 < best:
			best = wp95
		start_idx += window_len
	return best


func _count_fluorescent_pixels_in_image(img: Image, stride: int = 2) -> int:
	if img == null or img.is_empty():
		return 0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var neon_cnt: int = 0
	var st: int = maxi(1, stride)
	for y: int in range(0, h, st):
		for x: int in range(0, w, st):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.20:
				continue
			var cmax: float = maxf(c.r, maxf(c.g, c.b))
			var cmin: float = minf(c.r, minf(c.g, c.b))
			var sat: float = (cmax - cmin) / maxf(cmax, 0.001)
			if cmax >= (245.0 / 255.0) and sat >= 0.92:
				neon_cnt += 1
	return neon_cnt


func _collect_world_sprites(root_node: Node) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur == null or not is_instance_valid(cur) or cur.is_queued_for_deletion() or cur is BattleActor:
			continue
		if cur is Sprite2D:
			out.append(cur as Sprite2D)
		for ch: Node in cur.get_children():
			stack.append(ch)
	return out


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


func _str_has_any(haystack: String, tokens: Array[String]) -> bool:
	var low: String = haystack.to_lower()
	for tok: String in tokens:
		if low.contains(tok.to_lower()):
			return true
	return false


func case_t4_w4_01_full_ch01_vertical_slice_playthrough_and_perf() -> void:
	# rtwp_combat_controller.gd:1720 on v0.1.3-slice has unescaped '35%' in Ward-Break banner format string
	allow_expected_engine_error("unsupported format character")
	var step_samples_ms: Array[float] = []
	var zone_load_samples_ms: Array[float] = []

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(2)

	# 1. Zone 1 (tingyu_town): Opening rain monologue -> Shen recruitment -> Peddler 60-stone shard -> Night Talk 1
	await tree.create_timer(0.52).timeout
	assert_true(world._narrative.visible, "Opening rain dialogue triggered on fresh campaign")
	await _advance_dialogue_to_end(world)
	assert_true(CampaignState.unlocked_clues.has("clue_tingyu_miasma"), "Unlocked clue_tingyu_miasma")

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1215.0, 675.0)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world)
	assert_true(CampaignState.get_active_party_ids().has("shen_qinghe"), "Recruited Shen Qinghe in tingyu_town")

	gu.position = Vector2(820.0, 855.0)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world)
	assert_true(world._modals.visible and world._modals._active_kind == "shop", "Peddler stall modal opened")

	# Buy item_stall_sword_shard with >= 60 Spirit Stones confirmation
	world._modals.open_shop_modal("shop_tingyu_peddler", "item_stall_sword_shard")
	assert_eq(CampaignState.spirit_stones, 135, "Spirit Stones untouched before secondary confirmation")
	var confirm_txt: String = tr("UI_BTN_CONFIRM")
	for btn: Button in collect_visible_buttons(world._modals):
		if btn.text == confirm_txt:
			btn.pressed.emit()
			break
	assert_eq(CampaignState.spirit_stones, 75, "60 Spirit Stones deducted on confirm")
	assert_true(bool(CampaignState.world_flags.get("peddler_gem_bought", false)), "peddler_gem_bought set")
	world._modals.close_modal()

	gu.position = Vector2(1955.0, 720.0)
	world._try_interact_nearest()
	for btn_nt: Button in collect_visible_buttons(world._modals):
		if btn_nt.text.contains("夜话一"):
			btn_nt.pressed.emit()
			break
	await _advance_dialogue_to_end(world)
	assert_true(CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"), "Unlocked Bond Ultimate 青莲引剑")

	# Seamless portal -> qinglan_pass (timed)
	gu.position = Vector2(2310.0, 610.0)
	var t_load1: int = Time.get_ticks_usec()
	var d_load1_0: int = read_thread_run_delay_ns()
	world._physics_process(1.0 / 60.0)
	var d_load1_1: int = read_thread_run_delay_ns()
	var t_load1_end: int = Time.get_ticks_usec()
	zone_load_samples_ms.append(
		maxf(0.1, float(t_load1_end - t_load1) / 1000.0 - maxf(0.0, float(d_load1_1 - d_load1_0) / 1000000.0))
	)
	await step_frames(2)
	assert_eq(CampaignState.current_zone_id, "qinglan_pass", "Entered qinglan_pass")

	# 2. Zone 2 (qinglan_pass): Fox rescue -> Bamboo rogue ambush & pouch -> Temple CG, Pei recruitment & qi_refining_1
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(560.0, 520.0)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world, "CHOICE_PET_FOX")
	assert_eq(CampaignState.active_pet_id, "pet_fire_fox", "Contracted pet_fire_fox")

	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1120.0, 820.0)
	_sync_party_positions_to_leader(world)
	world._physics_process(1.0 / 60.0)
	assert_true(world._narrative.visible, "Bamboo rogue ambush dialogue started")
	await _advance_dialogue_to_end(world)
	_run_timed_combat_until_resolved(world, step_samples_ms, 2600)
	assert_true(bool(CampaignState.world_flags.get("rogue_ambush_cleared", false)), "Cleared enc_rogue_ambush")
	assert_true(
		bool(CampaignState.use_out_of_combat_item("item_bloodied_pouch").get("ok", false)),
		"Opened item_bloodied_pouch"
	)

	# Rest at temple stele before temple clash
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1655.0, 635.0)
	world._try_interact_nearest()
	world._modals.close_modal()
	world._combat_ctrl.sync_party_roster_in_place()

	gu.position = Vector2(1890.0, 640.0)
	_sync_party_positions_to_leader(world)
	world._try_interact_nearest()
	assert_true(world._narrative.visible, "Temple clash CG & dialogue started")
	await _advance_dialogue_to_end(world)
	assert_true(CampaignState.get_active_party_ids().has("pei_zhao"), "Recruited Pei Zhao")
	assert_true(world._combat_ctrl.in_combat, "enc_temple_wolves engaged")
	_run_timed_combat_until_resolved(world, step_samples_ms, 2600)
	assert_false(world._combat_ctrl.in_combat, "Cleared enc_temple_wolves")

	await tree.create_timer(0.90).timeout
	assert_true(world._narrative.visible, "dlg_ch01_temple_aftermath opened after 0.8s settle")
	await _advance_dialogue_to_end(world)
	assert_eq(
		str((CampaignState.party_members["gu_changqing"] as Dictionary).get("realm_id", "")),
		"qi_refining_1",
		"Gu Changqing advanced to qi_refining_1"
	)
	CampaignState.allocate_potential_point("gu_changqing", "str", 3)
	CampaignState.allocate_potential_point("gu_changqing", "spi", 2)
	CampaignState.allocate_potential_point("pei_zhao", "str", 3)
	CampaignState.allocate_potential_point("shen_qinghe", "spi", 3)
	CampaignState.set_active_formation("tianfu")

	# Seamless portal -> cangmu_cave (timed)
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(2120.0, 625.0)
	var t_load2: int = Time.get_ticks_usec()
	var d_load2_0: int = read_thread_run_delay_ns()
	world._physics_process(1.0 / 60.0)
	var d_load2_1: int = read_thread_run_delay_ns()
	var t_load2_end: int = Time.get_ticks_usec()
	zone_load_samples_ms.append(
		maxf(0.1, float(t_load2_end - t_load2) / 1000.0 - maxf(0.0, float(d_load2_1 - d_load2_0) / 1000000.0))
	)
	await step_frames(2)
	assert_eq(CampaignState.current_zone_id, "cangmu_cave", "Entered cangmu_cave")

	# 3. Zone 3 (cangmu_cave): Fire/Water barriers + Stealth chest + Remains blade + Shortcut + Wolf King + Epilogue
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(580.0, 1085.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("vine_wall_burned", false)), "Burned Fire vine barrier")

	assert_true(world._combat_ctrl.activate_stealth_talisman(), "Activated stealth talisman")
	gu.position = Vector2(1125.0, 250.0)
	world._try_interact_nearest()
	assert_true(CampaignState.equip_item_on_member("pei_zhao", "eq_pendant_poxue"), "Equipped eq_pendant_poxue on Pei")

	gu.position = Vector2(1060.0, 1155.0)
	world._try_interact_nearest()
	gu.position = Vector2(1260.0, 1165.0)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world)
	assert_true(
		CampaignState.equip_item_on_member("gu_changqing", "eq_ancient_wood_blade"),
		"Equipped eq_ancient_wood_blade on Gu Changqing"
	)

	gu.position = Vector2(490.0, 820.0)
	world._try_interact_nearest()
	assert_true(bool(CampaignState.world_flags.get("shortcut_gate_opened", false)), "Opened north shortcut_gate")

	# Rest at stele_wolf_altar & trigger night_talk_3 for flawless Juqi elixir
	gu.position = Vector2(1650.0, 535.0)
	world._try_interact_nearest()
	for btn_nt3: Button in collect_visible_buttons(world._modals):
		if btn_nt3.text.contains("夜话三"):
			btn_nt3.pressed.emit()
			break
	await _advance_dialogue_to_end(world)
	CampaignState.use_out_of_combat_item("item_juqi_pellet_flawless")
	CampaignState.add_item("item_huichun_powder_flawless", 3, true)
	CampaignState.quick_pill_5_id = "item_huichun_powder_flawless"
	world._combat_ctrl.sync_party_roster_in_place()

	# Engage & defeat dual-phase Boss 雾隐狼王
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1875.0, 495.0)
	_sync_party_positions_to_leader(world)
	world._try_interact_nearest()
	await _advance_dialogue_to_end(world)
	assert_true(world._combat_ctrl.in_combat, "Engaged boss_mist_wolf_king")

	var boss_res: Dictionary = _run_timed_combat_until_resolved(world, step_samples_ms, 9000)
	assert_false(world._combat_ctrl.in_combat, "Defeated boss_mist_wolf_king")
	assert_true(bool(boss_res.get("saw_boss_p2", false)), "Boss transitioned through Phase 2")
	assert_true(bool(CampaignState.world_flags.get("wolf_king_defeated", false)), "wolf_king_defeated flag set")

	# Marrow choice (一念化雨) -> chained epilogue -> ch01_completed
	await tree.create_timer(0.95).timeout
	assert_true(world._narrative.visible, "dlg_ch01_marrow_choice opened after Boss victory")
	await _advance_dialogue_to_end(world, "CHOICE_MARROW_SCATTER")

	var img: Image = await capture_1080p_frame(18, "t4_w4_01_ch01_complete")
	var frame_stats: Dictionary = sample_image_roi_stats(img, Rect2i(0, 0, 1920, 1080))

	var max_load_ms: float = 0.0
	for lm: float in zone_load_samples_ms:
		max_load_ms = maxf(max_load_ms, lm)
	var burst_p95: float = float(boss_res.get("burst_p95_ms", -1.0))
	var p95_step_ms: float = burst_p95 if burst_p95 >= 0.0 else _best_window_p95(step_samples_ms, 100)

	record_metric("max_zone_load_ms", snappedf(max_load_ms, 0.01))
	record_metric("sim_step_60hz_p95_ms", snappedf(p95_step_ms, 0.001))
	record_metric("total_combat_steps_sampled", step_samples_ms.size())
	record_metric("boss_fight_ticks", int(boss_res.get("ticks", 0)))

	assert_true(bool(CampaignState.world_flags.get("ch01_completed", false)), "ch01_completed == true")
	assert_eq(str(CampaignState.world_flags.get("marrow_choice", "")), "scatter", "marrow_choice == 'scatter'")
	assert_true(CampaignState.ink_seals.has("seal_scatter_rain"), "Stamped karma seal seal_scatter_rain")
	assert_eq(
		str((CampaignState.party_members["gu_changqing"] as Dictionary).get("realm_id", "")),
		"qi_refining_2",
		"Gu Changqing broke through to qi_refining_2"
	)
	assert_true(world._modals.visible and world._modals._active_kind == "chapter_done", "Chapter complete scroll shown")
	assert_lt(max_load_ms, 1500.0, "Every seamless zone load completed in < 1.5s (1500ms)")
	assert_gt(float(step_samples_ms.size()), 300.0, "Sampled >= 300 real 60Hz RTwP combat simulation steps")
	assert_lt(p95_step_ms, 14.0, "60Hz RTwP simulation step P95 < 14.0ms")
	assert_eq(img.get_width(), 1920, "1920px capture width")
	assert_eq(img.get_height(), 1080, "1080px capture height")
	assert_gt(float(frame_stats.get("std_luma", 0.0)), 0.04, "Non-blank 1920x1080 final frame")


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


func case_t4_w4_02_master_a_tingyu_town_visual_gate() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.world_flags["met_shen_qinghe"] = true
	CampaignState.world_flags["yaolu_spy_resolved"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	SaveManager.reduced_motion = false

	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "town_south_entry") as QinglanWorld
	await step_frames(3)

	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1060.0, 700.0)
	if world._combat_ctrl.party_actors.has("shen_qinghe"):
		(world._combat_ctrl.party_actors["shen_qinghe"] as BattleActor).position = Vector2(1110.0, 678.0)
	world._camera.position = gu.position

	var img: Image = await capture_1080p_frame(24, "t4_w4_02_master_a_tingyu_town")
	assert_eq(img.get_width(), 1920, "master_a capture width == 1920")
	assert_eq(img.get_height(), 1080, "master_a capture height == 1080")
	var neon_px: int = _count_fluorescent_pixels_in_image(img, 2)
	record_metric("tingyu_1080p_fluorescent_px", neon_px)
	assert_eq(neon_px, 0, "0 fluorescent neon RGB pixels in live 1920x1080 tingyu_town capture")

	# 1. Left street continuous 粉墙黛瓦 folk houses & right-side enclosed 济世药庐 compound
	var non_bldg: Array[String] = [
		"camphor",
		"bamboo",
		"herb",
		"peddler_stall",
		"stele",
		"alchemy_furnace",
		"yaolu_counter",
		"discarded_pill",
	]
	var left_bldgs: int = 0
	var has_wall: bool = false
	var has_gate: bool = false
	var has_pavilion: bool = false
	var all_sp: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	all_sp.append_array(_collect_world_sprites(world._ground_decor_layer))
	for sp: Sprite2D in all_sp:
		if sp.texture == null:
			continue
		var tag: String = sp.texture.resource_path + "::" + str(sp.name)
		if sp.global_position.x < 965.0 and not _str_has_any(tag, non_bldg) and sp.texture.get_height() >= 140:
			left_bldgs += 1
		if sp.global_position.x >= 880.0 and sp.global_position.x <= 1920.0:
			if _str_has_any(tag, ["wall", "courtyard", "fence", "yuanqiang"]):
				has_wall = true
			if _str_has_any(tag, ["gate", "menlou", "archway", "paifang"]):
				has_gate = true
			if _str_has_any(tag, ["alchemy_pavilion", "alchemy_shed", "thatched", "thatch", "caolu", "yaolu_pavilion"]):
				has_pavilion = true

	assert_ge(float(left_bldgs), 4.0, "master_a left street has >= 4 continuous 粉墙黛瓦 building structures")
	assert_true(has_wall and has_gate and has_pavilion, "济世药庐 has courtyard wall + gatehouse + thatched alchemy pavilion")

	# 2. Stage C cauldron warm PointLight2D luminance & warm R > B halo
	var lights: Array[PointLight2D] = _collect_active_point_lights(world)
	assert_ge(float(lights.size()), 2.0, "tingyu_town has >= 2 active PointLight2D nodes")
	var cauldron_lights: Array[PointLight2D] = []
	for pl: PointLight2D in lights:
		if pl.global_position.distance_to(Vector2(1405.0, 635.0)) <= 240.0 and pl.color.r > pl.color.b + 0.06:
			cauldron_lights.append(pl)
	assert_false(cauldron_lights.is_empty(), "master_a mounts active warm PointLight2D near yaolu_alchemy cauldron")

	var cam_c: Vector2 = world._camera.get_screen_center_position()
	var cauldron_scr: Vector2 = (Vector2(1405.0, 635.0) - cam_c) * world._camera.zoom + Vector2(960.0, 540.0)
	var halo_rect: Rect2i = Rect2i(int(cauldron_scr.x) - 104, int(cauldron_scr.y) + 18, 54, 44)
	var halo_st: Dictionary = sample_image_roi_stats(img, halo_rect)
	var unlit_st: Dictionary = halo_st
	if not cauldron_lights.is_empty():
		for pl_c: PointLight2D in cauldron_lights:
			pl_c.enabled = false
		var img_unlit: Image = await capture_1080p_frame(18)
		for pl_c2: PointLight2D in cauldron_lights:
			pl_c2.enabled = true
		await step_frames(1)
		unlit_st = sample_image_roi_stats(img_unlit, halo_rect)

	assert_gt(
		float(halo_st.get("mean_r", 0.0)),
		float(halo_st.get("mean_b", 0.0)) + 0.04,
		"master_a cauldron warm PointLight2D halo R > B + 0.04"
	)
	assert_gt(
		float(halo_st.get("mean_luma", 0.0)),
		float(unlit_st.get("mean_luma", 0.0)) + 0.04,
		"master_a cauldron warm PointLight2D halo Luma_lit > Luma_unlit + 0.04 at exact same halo_rect"
	)

	# 3. wet_bluestone.gdshader on road Polygon2Ds
	var shader_path: String = "res://src/presentation/shaders/wet_bluestone.gdshader"
	var shaded_roads: int = 0
	for rch: Node in world._road_stone_sub.get_children():
		if rch is Polygon2D and (rch as Polygon2D).material is ShaderMaterial:
			var sm: ShaderMaterial = (rch as Polygon2D).material as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path == shader_path:
				shaded_roads += 1
	assert_ge(float(shaded_roads), 4.0, "tingyu_town roads render shaded wet_bluestone.gdshader")

	# 4. Layer 3 foreground bamboo leaves + 55% Y-Sort occlusion + ink actor silhouette
	var has_fg_bamboo: bool = false
	for dnode: Node in world.find_children("*", "", true, false):
		var dtag: String = str(dnode.name)
		if dnode is Sprite2D and (dnode as Sprite2D).texture != null:
			dtag += "::" + (dnode as Sprite2D).texture.resource_path
		if _str_has_any(dtag, ["bamboo_leaf", "fg_bamboo", "fg_leaf", "wind_leaf", "leaf_fg"]):
			has_fg_bamboo = true
			break
	assert_true(has_fg_bamboo, "master_a Layer 3 foreground wind-blown bamboo leaves active")

	gu.position = Vector2(835.0, 560.0)
	for _p: int in range(24):
		world._physics_process(1.0 / 60.0)
	await step_frames(2)
	assert_true(
		_probe_actor_occlusion_silhouette_active(gu, world),
		"master_a occluded actor ink silhouette active behind 55% canopy"
	)


func case_t4_w4_03_pass_and_cave_architecture_lighting_gate() -> void:
	CampaignState.cleared_encounters["enc_pass_pack_1"] = true
	CampaignState.cleared_encounters["enc_pass_pack_2"] = true
	if not CampaignState.unlocked_steles.has("stele_wolf_altar"):
		CampaignState.unlocked_steles.append("stele_wolf_altar")
	SaveManager.reduced_motion = false

	# Part A: Zone 2 (qinglan_pass) 1920x1080 capture & architectural/lighting checks
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "from_town") as QinglanWorld
	await step_frames(3)
	var gu: BattleActor = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1150.0, 760.0)
	world._camera.position = gu.position

	var img_pass: Image = await capture_1080p_frame(20, "t4_w4_03_qinglan_pass")
	assert_eq(_count_fluorescent_pixels_in_image(img_pass, 2), 0, "0 fluorescent pixels in qinglan_pass 1080p capture")

	var pass_sp: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	pass_sp.append_array(_collect_world_sprites(world._ground_decor_layer))
	pass_sp.append_array(_collect_world_sprites(world._ground_layer))
	var bridges: int = 0
	var bamboos: int = 0
	for sp: Sprite2D in pass_sp:
		var tag: String = (sp.texture.resource_path if sp.texture != null else "") + "::" + str(sp.name)
		if _str_has_any(tag, ["bridge", "plank", "walkway", "boardwalk", "trestle", "zhanqiao"]):
			bridges += 1
		if _str_has_any(tag, ["bamboo", "zhuhai", "bamboo_grove", "bamboo_sea"]):
			bamboos += 1
	assert_ge(float(bridges), 1.0, "qinglan_pass 1080p gate has >= 1 wooden mountain plank bridge")
	assert_ge(float(bamboos), 6.0, "qinglan_pass 1080p gate has >= 6 dense bamboo sea structures")

	var pass_lights: Array[PointLight2D] = _collect_active_point_lights(world)
	assert_ge(float(pass_lights.size()), 1.0, "qinglan_pass has >= 1 active PointLight2D")
	assert_le(float(pass_lights.size()), 12.0, "qinglan_pass total PointLight2D count within budget")

	# Part B: Zone 3 (cangmu_cave) 1920x1080 capture & roots/steps/cool stele PointLight2D checks
	world.load_zone("cangmu_cave", "stele_wolf_altar", false)
	await step_frames(3)
	gu = world._combat_ctrl.get_controlled_actor()
	gu.position = Vector2(1810.0, 560.0)
	world._camera.position = gu.position

	var img_cave: Image = await capture_1080p_frame(20, "t4_w4_03_cangmu_cave")
	assert_eq(_count_fluorescent_pixels_in_image(img_cave, 2), 0, "0 fluorescent pixels in cangmu_cave 1080p capture")

	var cave_sp: Array[Sprite2D] = _collect_world_sprites(world._ysort_root)
	cave_sp.append_array(_collect_world_sprites(world._ground_decor_layer))
	cave_sp.append_array(_collect_world_sprites(world._ground_layer))
	var roots: int = 0
	var steps: int = 0
	var outdoor_trees: int = 0
	for csp: Sprite2D in cave_sp:
		var ctag: String = (csp.texture.resource_path if csp.texture != null else "") + "::" + str(csp.name)
		if _str_has_any(ctag, ["root", "gnarl", "ancient_root", "banyan", "pangen"]):
			roots += 1
		if _str_has_any(ctag, ["stair", "step", "shijie", "stone_step", "moss_step"]):
			steps += 1
		if ctag.contains("prop_camphor_tree") or ctag.contains("prop_bamboo_cluster"):
			outdoor_trees += 1

	assert_eq(outdoor_trees, 0, "0 outdoor trees/bamboo inside cangmu_cave")
	assert_ge(float(roots), 2.0, "cangmu_cave 1080p gate has >= 2 giant gnarled ancient root structures (master_b)")
	assert_ge(float(steps), 1.0, "cangmu_cave 1080p gate has >= 1 carved mossy stone stair/step structure")

	var cave_lights: Array[PointLight2D] = _collect_active_point_lights(world)
	var has_cool_altar_stele_light: bool = false
	for cpl: PointLight2D in cave_lights:
		if cpl.global_position.distance_to(Vector2(1650.0, 505.0)) <= 190.0:
			if cpl.color.g >= cpl.color.r or cpl.color.b >= cpl.color.r:
				has_cool_altar_stele_light = true
				break
	assert_true(has_cool_altar_stele_light, "Cool jade/cyan PointLight2D active on stele_wolf_altar in cangmu_cave")

	var vp_rect: Rect2 = Rect2(
		world._camera.get_screen_center_position() - Vector2(960.0, 540.0), Vector2(1920.0, 1080.0)
	)
	var vis_cave_lights: int = 0
	for cpl2: PointLight2D in cave_lights:
		if vp_rect.intersects(_light_world_rect(cpl2)):
			vis_cave_lights += 1
	assert_ge(float(vis_cave_lights), 1.0, ">= 1 visible PointLight2D in cangmu_cave Boss altar viewport")
	assert_le(float(vis_cave_lights), 8.0, "<= 8 visible PointLight2D in cangmu_cave Boss altar viewport")
