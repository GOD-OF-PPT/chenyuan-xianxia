extends "res://tests/e2e_harness.gd"
# @e2e_mode: headless
# @e2e_tier: 2
# @e2e_features: F7, F15
## Worker 2 Tier 2 Boundary, Negative & Corner-Case Suite for F7 (Narrative Stage) and F15 (Save/Input/Notify/Audio).


func register_cases() -> void:
	add_case("T2-F07-01", 2, "F7", "baseline", "400ms narrative anti-mash lock & 100% Space/combat-key isolation", "case_t2_f07_01_anti_mash_and_space_block")
	add_case("T2-F07-02", 2, "F7", "baseline", "Choice button FOCUS_NONE, Enter/Space non-selection & 400ms choice click lock", "case_t2_f07_02_choice_click_lock")
	add_case("T2-F07-03", 2, "F7", "baseline", "0.8s post-combat floater settle, P1 purge & 1.0s post-dialogue P3 max-2 drain", "case_t2_f07_03_post_combat_settle_and_p3_delay")
	add_case("T2-F07-04", 2, "F7", "baseline", "Wolf King retry auto-skip vs force_replay gallery playback", "case_t2_f07_04_boss_retry_autoskip")
	add_case("T2-F07-05", 2, "F7", "baseline", "Esc non-dismissal during NarrativeStage & scene_epoch stale timer guard", "case_t2_f07_05_esc_and_epoch_guard")
	add_case("T2-F07-06", 2, "F7", "baseline", "Companion bond [1..5] clamping & duplicate Cinnabar Karma Seal idempotency", "case_t2_f07_06_bond_clamp_and_seal_idempotency")
	add_case("T2-F15-01", 2, "F15", "baseline", "SHA-256 tampered & malformed JSON save 100% byte preservation + P0 crisis + .bak recovery", "case_t2_f15_01_corrupt_save_zero_overwrite_and_bak")
	add_case("T2-F15-02", 2, "F15", "baseline", "Sandbox, mid-combat, and puzzle-lock save blocks + disabled Save/Load UI", "case_t2_f15_02_save_lock_states")
	add_case("T2-F15-03", 2, "F15", "baseline", "Esc priority stack closing Casket/Modals/Drawer with zero trapped GUI focus", "case_t2_f15_03_esc_stack_and_focus_release")
	add_case("T2-F15-06", 2, "F15", "baseline", "SaveManager mute_on_unfocus Master bus mute/unmute on window focus notifications", "case_t2_f15_06_mute_on_unfocus")


func _sha256_bytes(buf: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return ctx.finish().hex_encode()


func case_t2_f07_01_anti_mash_and_space_block() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	var ctrl: RtwpCombatController = world._combat_ctrl
	var stage: NarrativeStage = world._narrative
	var gu: BattleActor = ctrl.party_actors["gu_changqing"] as BattleActor
	var start_pos: Vector2 = gu.position

	stage.start_dialogue("dlg_ch01_meet_shen")
	assert_eq(stage._line_index, 0, "Dialogue starts at line 0")

	var mash_keys: Array[Key] = [
		KEY_ENTER,
		KEY_SPACE,
		KEY_W,
		KEY_A,
		KEY_S,
		KEY_D,
		KEY_1,
		KEY_2,
		KEY_3,
		KEY_4,
		KEY_Q,
		KEY_E,
	]
	for step_dt: float in [0.0, 0.15, 0.23]:
		if step_dt > 0.0:
			InputRouter._process(step_dt)
		for _rep: int in range(20):
			for k: Key in mash_keys:
				InputRouter._input(make_key_event(k, true))
			stage._scroll_panel.gui_input.emit(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(400.0, 60.0), true))

	var gu_u: Dictionary = ctrl.unit_states["gu_changqing"] as Dictionary
	assert_eq(stage._line_index, 0, "Zero lines skipped during 0..0.38s anti-mash lock")
	assert_false(ctrl.tactical_paused, "Space during dialogue never toggles Tactical Pause")
	assert_approx(float(gu_u.get("gcd_timer", 0.0)), 0.0, 0.001, "Zero combat skills cast during dialogue")
	assert_eq(gu.position, start_pos, "Player position 100% unchanged during dialogue")

	# Step past 0.40s -> Space / WASD / 1..4 / Q / E STILL advance 0 lines; 1 Enter advances to line 1
	InputRouter._process(0.05) # total 0.43s > 0.40s
	for _rep2: int in range(20):
		for k2: Key in [KEY_SPACE, KEY_W, KEY_A, KEY_S, KEY_D, KEY_1, KEY_2, KEY_3, KEY_4, KEY_Q, KEY_E]:
			InputRouter._input(make_key_event(k2, true))
	assert_eq(stage._line_index, 0, "Space and combat hotkeys advance 0 lines even after 0.43s")

	InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_eq(stage._line_index, 1, "Single KEY_ENTER after 0.43s advances cleanly to line 1")


func case_t2_f07_02_choice_click_lock() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var stage: NarrativeStage = world._narrative

	stage.start_dialogue("dlg_ch01_marrow_choice", true)
	InputRouter._process(0.45)
	for _i: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_true(stage._choices_box.visible, "Choices box visible after final line")

	var btns: Array[Button] = collect_visible_buttons(stage._choices_box)
	assert_eq(btns.size(), 2, "Two choice buttons rendered")
	for b: Button in btns:
		assert_eq(b.focus_mode, Control.FOCUS_NONE, "Choice button enforces FOCUS_NONE against blind Enter/Space")

	# Even after lock would expire on lines, Enter / Space / scroll-click must NEVER pick a choice
	InputRouter._process(0.10) # t = 0.10s (< 0.40s choice lock)
	btns[0].pressed.emit()
	assert_eq(str(CampaignState.world_flags.get("marrow_choice", "")), "", "Choice button click at 0.10s blocked by 400ms lock")

	InputRouter._process(0.35) # t = 0.45s (> 0.40s choice lock)
	for _m: int in range(5):
		InputRouter._input(make_key_event(KEY_ENTER, true))
		InputRouter._input(make_key_event(KEY_SPACE, true))
		stage._scroll_panel.gui_input.emit(make_mouse_button_event(MOUSE_BUTTON_LEFT, Vector2(300.0, 50.0), true))
	assert_eq(str(CampaignState.world_flags.get("marrow_choice", "")), "", "Enter, Space, and scroll-click pick 0 choices")

	btns[0].pressed.emit()
	assert_eq(str(CampaignState.world_flags.get("marrow_choice", "")), "absorb", "Explicit button click at 0.45s executes Choice 0")


func case_t2_f07_03_post_combat_settle_and_p3_delay() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	CampaignState.recruit_companion("shen_qinghe", 2)
	CampaignState.recruit_companion("pei_zhao", 2)
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)

	var spawned_slips: Array[Dictionary] = []
	var cb_slip: Callable = func(payload: Dictionary) -> void: spawned_slips.append(payload.duplicate(true))
	NotifyHub.explore_slip_spawned.connect(cb_slip)

	NotifyHub.set_combat_active(true)
	NotifyHub.push_combat_number(Vector2(1700.0, 620.0), 88, false, true, "metal")
	NotifyHub.push_combat_number(Vector2(1720.0, 610.0), 54, false, false, "fire")
	assert_eq(world._notify_overlay._floaters.size(), 2, "2 active P1 damage floaters on screen")

	for s_i: int in range(4):
		NotifyHub.push_explore_slip("战利灵材_%d" % s_i, "数量 +1", "loot")

	# Combat ends and enc_temple_wolves triggers 0.80s post-combat settle timer
	NotifyHub.set_combat_active(false)
	world._combat_ctrl.encounter_cleared.emit("enc_temple_wolves", false)

	await tree.create_timer(0.30).timeout
	assert_false(world._narrative.visible, "At +0.30s (< 0.80s settle), NarrativeStage is not yet open")
	assert_eq(spawned_slips.size(), 0, "Zero P3 slips spawned at +0.30s")

	await tree.create_timer(0.60).timeout # total ~0.90s > 0.80s
	assert_true(world._narrative.visible, "At +0.90s (> 0.80s settle), NarrativeStage opens dlg_ch01_temple_aftermath")
	assert_true(NotifyHub.narrative_exclusive, "NotifyHub.narrative_exclusive active")
	assert_true(world._notify_overlay._floaters.is_empty(), "Active P1 combat floaters 100% purged on dialogue entry")
	assert_eq(spawned_slips.size(), 0, "Zero P3 slips spawned during P2 narrative exclusive")

	# Advance all 3 lines of dlg_ch01_temple_aftermath to close dialogue
	InputRouter._process(0.45)
	for _ln: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(world._narrative.visible, "Dialogue closed")

	await tree.create_timer(0.45).timeout
	assert_eq(spawned_slips.size(), 0, "Zero P3 slips at +0.45s post-close (< 1.0s POST_BUSY_DELAY_SEC)")

	await tree.create_timer(0.68).timeout # total ~1.13s post-close
	assert_eq(spawned_slips.size(), 2, "Exactly MAX_ACTIVE_SLIPS == 2 P3 slips spawned at +1.13s post-close")
	assert_ge(NotifyHub._p3_queue.size(), 2, "Remaining P3 slips stay queued until 3.2s slip duration expires")

	NotifyHub.explore_slip_spawned.disconnect(cb_slip)


func case_t2_f07_04_boss_retry_autoskip() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("cangmu_cave", "stele_wolf_altar") as QinglanWorld
	await step_frames(2)
	var stage: NarrativeStage = world._narrative
	var ctrl: RtwpCombatController = world._combat_ctrl

	# First play of dlg_ch01_wolf_king_intro opens stage and marks read_dialogues
	stage.start_dialogue("dlg_ch01_wolf_king_intro", false)
	assert_true(stage.visible, "First Wolf King encounter opens pre-fight dialogue")
	InputRouter._process(0.45)
	for _i: int in range(3):
		InputRouter._input(make_key_event(KEY_ENTER, true))
	assert_false(stage.visible, "Pre-fight dialogue finished")
	assert_true(CampaignState.read_dialogues.has("dlg_ch01_wolf_king_intro"), "Wolf King intro marked read")
	assert_true(ctrl.in_combat, "Boss engaged after intro")

	# Simulate retry: reload cave (resetting in_combat = false) while keeping read_dialogues
	world.load_zone("cangmu_cave", "stele_wolf_altar", false)
	await step_frames(2)
	assert_false(ctrl.in_combat, "Boss disengaged on fresh retry load")

	var finished_ids: Array[String] = []
	stage.dialogue_finished.connect(func(did: String) -> void: finished_ids.append(did))

	stage.start_dialogue("dlg_ch01_wolf_king_intro", false)
	assert_false(stage.visible, "Boss retry (force_replay=false) skips already-read intro UI")
	assert_true(ctrl.in_combat, "Boss retry immediately fires engage_boss_wolf_king")
	assert_true(finished_ids.has("dlg_ch01_wolf_king_intro"), "dialogue_finished emitted on auto-skip")

	# Gallery replay (force_replay=true) MUST open the stage at line 0
	stage.start_dialogue("dlg_ch01_wolf_king_intro", true)
	assert_true(stage.visible, "Gallery replay (force_replay=true) opens NarrativeStage")
	assert_eq(stage._line_index, 0, "Gallery replay starts at _line_index == 0")


func case_t2_f07_05_esc_and_epoch_guard() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("qinglan_pass", "stele_temple_courtyard") as QinglanWorld
	await step_frames(2)

	# Part A: Esc during active NarrativeStage does NOT close dialogue or open settings modal
	world._narrative.start_dialogue("dlg_ch01_meet_shen")
	assert_true(world._narrative.visible, "NarrativeStage open")
	InputRouter._input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_true(world._narrative.visible, "Esc does not abort active Tier 2 NarrativeStage")
	assert_false(world._modals.visible, "Esc does not open settings modal over active NarrativeStage")
	world._narrative.call("_close_stage")

	# Part B: Clear enc_temple_wolves (arming 0.80s timer), immediately zone to tingyu_town (bumping scene_epoch)
	world._combat_ctrl.encounter_cleared.emit("enc_temple_wolves", false)
	world.load_zone("tingyu_town", "stele_tingyu_gate", false)
	await tree.create_timer(0.95).timeout
	assert_false(
		world._narrative.visible,
		"Stale 0.80s enc_temple_wolves timer aborted cleanly after load_zone bumped CampaignState.scene_epoch"
	)


func case_t2_f07_06_bond_clamp_and_seal_idempotency() -> void:
	CampaignState.add_companion_bond("shen_qinghe", 99)
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 0)), 5, "Companion bond clamps at max Tier 5")

	CampaignState.add_companion_bond("shen_qinghe", -99)
	assert_eq(int(CampaignState.companion_bonds.get("shen_qinghe", 0)), 1, "Companion bond clamps at min Tier 1")

	CampaignState.stamp_ink_seal("seal_scatter_rain", "mortal_mercy")
	CampaignState.stamp_ink_seal("seal_scatter_rain", "mortal_mercy")
	var occurrences: int = 0
	for s: String in CampaignState.ink_seals:
		if s == "seal_scatter_rain":
			occurrences += 1
	assert_eq(occurrences, 1, "Duplicate stamp_ink_seal records seal_scatter_rain once without array duplication")


func case_t2_f15_01_corrupt_save_zero_overwrite_and_bak() -> void:
	if not begin_isolated_xdg_save_test():
		return
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)
	CampaignState.sandbox_mode = false

	# 1. Save slot_02 twice: 200 stones -> .bak, 500 stones -> .json
	CampaignState.spirit_stones = 200
	assert_true(bool(SaveManager.save_manual_slot(2).get("ok", false)), "Initial save slot_02 (200 stones)")
	CampaignState.spirit_stones = 500
	assert_true(bool(SaveManager.save_manual_slot(2).get("ok", false)), "Second save slot_02 (500 stones, .bak=200)")

	# Overwrite slot_02.json with tampered spirit_stones (breaking SHA-256 checksum)
	var slot2_path: String = "user://saves/slot_02.json"
	var raw_valid: String = FileAccess.get_file_as_string(slot2_path)
	var tampered_txt: String = raw_valid.replace("\"spirit_stones\": 500", "\"spirit_stones\": 99999")
	assert_ne(tampered_txt, raw_valid, "Constructed tampered JSON payload")
	var f2: FileAccess = FileAccess.open(slot2_path, FileAccess.WRITE)
	f2.store_string(tampered_txt)
	f2.flush()
	f2.close()

	var tampered_bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(slot2_path)
	var tampered_sha_before: String = _sha256_bytes(tampered_bytes_before)

	var crisis_payloads: Array[Dictionary] = []
	var cb_crisis: Callable = func(p: Dictionary) -> void: crisis_payloads.append(p.duplicate(true))
	NotifyHub.crisis_alert_requested.connect(cb_crisis)

	var load_bad: Dictionary = SaveManager.load_slot("slot_02", false)
	assert_false(bool(load_bad.get("ok", true)), "Tampered slot_02 load rejected")
	assert_eq(str(load_bad.get("error", "")), "corrupted", "Returns error == corrupted")
	assert_true(bool(load_bad.get("has_backup", false)), "Reports has_backup == true")
	assert_eq(crisis_payloads.size(), 1, "Fires P0 crisis_alert_requested immediately")
	assert_true(world._notify_overlay._crisis_modal.visible, "NotificationOverlay._crisis_modal opened")
	assert_true(world._notify_overlay._crisis_bak_btn.visible, "_crisis_bak_btn visible when .bak exists")

	# Verify 100% byte-for-byte preservation of tampered slot_02.json (ZERO silent overwrite/delete)
	var tampered_bytes_after: PackedByteArray = FileAccess.get_file_as_bytes(slot2_path)
	assert_eq(_sha256_bytes(tampered_bytes_after), tampered_sha_before, "Tampered slot_02.json preserved 100% byte-for-byte")

	# Save/Load modal marks slot_02 corrupted and disables overwrite button
	world._modals.open_save_load_modal(true)
	await step_frames(1)
	var insp2: Dictionary = SaveManager.inspect_slot("slot_02", false)
	assert_eq(str(insp2.get("status", "")), "corrupted", "inspect_slot marks slot_02 corrupted")
	world._modals.close_modal()

	# Recover from .bak -> restores spirit_stones == 200 while tampered main file remains untouched
	var rec_res: Dictionary = SaveManager.load_slot("slot_02", true)
	CampaignState.sandbox_mode = false
	assert_true(bool(rec_res.get("ok", false)), "Recovery from slot_02.json.bak succeeded")
	assert_eq(CampaignState.spirit_stones, 200, ".bak recovery restored spirit_stones == 200")
	assert_eq(
		_sha256_bytes(FileAccess.get_file_as_bytes(slot2_path)),
		tampered_sha_before,
		"Main slot_02.json still 100% untouched after .bak load"
	)

	# 2. Truncated non-JSON '{{corrupt' in slot_03.json -> allow expected C++ JSON parse error first!
	var slot3_path: String = "user://saves/slot_03.json"
	var f3: FileAccess = FileAccess.open(slot3_path, FileAccess.WRITE)
	f3.store_string("{{{corrupt_truncated_json")
	f3.flush()
	f3.close()
	var bad3_bytes: PackedByteArray = FileAccess.get_file_as_bytes(slot3_path)
	var bad3_sha: String = _sha256_bytes(bad3_bytes)

	allow_expected_engine_error("Parse JSON failed")
	var load_bad3: Dictionary = SaveManager.load_slot("slot_03", false)
	assert_false(bool(load_bad3.get("ok", true)), "Malformed JSON slot_03 rejected")
	assert_eq(str(load_bad3.get("error", "")), "corrupted", "Malformed JSON returns corrupted")
	assert_false(bool(load_bad3.get("has_backup", true)), "Reports has_backup == false when no .bak exists")
	assert_eq(
		_sha256_bytes(FileAccess.get_file_as_bytes(slot3_path)),
		bad3_sha,
		"Truncated slot_03.json preserved 100% byte-for-byte on disk"
	)

	NotifyHub.crisis_alert_requested.disconnect(cb_crisis)
	end_isolated_xdg_save_test()


func case_t2_f15_02_save_lock_states() -> void:
	if not begin_isolated_xdg_save_test():
		return
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)

	# Lock (a): sandbox_mode == true
	CampaignState.sandbox_mode = true
	var chk_sb: Dictionary = SaveManager.can_save_now()
	assert_false(bool(chk_sb.get("ok", true)), "can_save_now false in sandbox_mode")
	assert_eq(str(chk_sb.get("reason_key", "")), "MSG_SAVE_SANDBOX_BLOCKED", "Reason is MSG_SAVE_SANDBOX_BLOCKED")
	assert_false(bool(SaveManager.save_manual_slot(1).get("ok", true)), "save_manual_slot blocked in sandbox")
	assert_false(bool(SaveManager.save_rolling_auto().get("ok", true)), "save_rolling_auto blocked in sandbox")

	# Lock (b): NotifyHub.combat_active == true
	CampaignState.sandbox_mode = false
	NotifyHub.set_combat_active(true)
	var chk_cb: Dictionary = SaveManager.can_save_now()
	assert_false(bool(chk_cb.get("ok", true)), "can_save_now false during combat")
	assert_eq(str(chk_cb.get("reason_key", "")), "MSG_SAVE_COMBAT_BLOCKED", "Reason is MSG_SAVE_COMBAT_BLOCKED")
	assert_false(bool(SaveManager.save_manual_slot(1).get("ok", true)), "save_manual_slot blocked in combat")
	assert_false(bool(SaveManager.save_rolling_auto().get("ok", true)), "save_rolling_auto blocked in combat")

	world._modals.open_save_load_modal(true)
	await step_frames(1)
	var write_btns: int = 0
	for btn: Button in collect_visible_buttons(world._modals):
		if btn.text == "写入此卷":
			write_btns += 1
			assert_true(btn.disabled, "写入此卷 button disabled while in combat")
	assert_gt(float(write_btns), 0.0, "Save modal rendered manual slot write buttons")
	world._modals.close_modal()
	NotifyHub.set_combat_active(false)

	# Lock (c): SaveManager.in_puzzle_lock == true
	SaveManager.in_puzzle_lock = true
	var chk_pz: Dictionary = SaveManager.can_save_now()
	assert_false(bool(chk_pz.get("ok", true)), "can_save_now false during puzzle lock")
	assert_eq(str(chk_pz.get("reason_key", "")), "MSG_SAVE_PUZZLE_BLOCKED", "Reason is MSG_SAVE_PUZZLE_BLOCKED")
	assert_false(bool(SaveManager.save_manual_slot(1).get("ok", true)), "save_manual_slot blocked in puzzle lock")
	SaveManager.in_puzzle_lock = false

	assert_false(FileAccess.file_exists("user://saves/slot_01.json"), "Zero save files written across all 3 lock states")
	assert_false(FileAccess.file_exists("user://saves/auto_01.json"), "Zero auto-save files written across all 3 lock states")
	end_isolated_xdg_save_test()


func case_t2_f15_03_esc_stack_and_focus_release() -> void:
	CampaignState.read_dialogues["dlg_ch01_opening_rain"] = true
	var world: QinglanWorld = spawn_qinglan_world("tingyu_town", "stele_tingyu_gate") as QinglanWorld
	await step_frames(2)

	# 1. Open DaoCasketPanel (C) -> Esc closes casket and restores MODE_WORLD_COMBAT
	InputRouter._input(make_key_event(KEY_C, true))
	await step_frames(1)
	assert_true(world._casket.visible, "DaoCasketPanel opened via KEY_C")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_MODAL_MENU, "Mode is MODE_MODAL_MENU")
	InputRouter._input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_false(world._casket.visible, "Esc closes DaoCasketPanel")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Mode restored to MODE_WORLD_COMBAT")

	# 2. Open Settings Modal, grab GUI focus on an HSlider -> Esc closes modal & releases focus cleanly
	world._modals.open_settings_modal()
	await step_frames(1)
	var sliders: Array[Node] = world._modals.find_children("*", "HSlider", true, false)
	assert_gt(float(sliders.size()), 0.0, "Settings modal contains audio/shake HSlider controls")
	if not sliders.is_empty():
		var sl: HSlider = sliders[0] as HSlider
		sl.grab_focus()
		assert_eq(world.get_viewport().gui_get_focus_owner(), sl, "HSlider grabbed GUI focus")

	InputRouter._input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_false(world._modals.visible, "Esc closes Settings modal")
	assert_null(world.get_viewport().gui_get_focus_owner(), "Zero focus trapped on hidden modal HSlider")
	assert_eq(InputRouter.current_mode, InputRouter.MODE_WORLD_COMBAT, "Mode restored to MODE_WORLD_COMBAT")

	# 3. Open CombatHud Z quick drawer -> Esc closes quick drawer without opening settings
	world._hud.toggle_quick_drawer()
	await step_frames(1)
	assert_true(world._hud.is_quick_drawer_open(), "Z quick drawer open")
	InputRouter._input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_false(world._hud.is_quick_drawer_open(), "Esc closes Z quick drawer first")
	assert_false(world._modals.visible, "Closing Z quick drawer does not open Settings modal")

	# 4. Active DefeatRecapScroll -> Esc must NOT prematurely dismiss recap scroll
	world._recap_scroll.show_recap({"fatal_chain": [], "tip_key": "RECAP_TIP_GENERAL", "tip_param": ""})
	await step_frames(1)
	InputRouter._input(make_key_event(KEY_ESCAPE, true))
	await step_frames(1)
	assert_true(world._recap_scroll.visible, "Esc never prematurely dismisses DefeatRecapScroll")


func case_t2_f15_06_mute_on_unfocus() -> void:
	SaveManager.master_muted = false
	SaveManager.mute_on_unfocus = true
	SaveManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_false(AudioServer.is_bus_mute(0), "Master bus unmuted when focused")

	SaveManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(AudioServer.is_bus_mute(0), "Master bus muted on FOCUS_OUT when mute_on_unfocus == true")

	SaveManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_false(AudioServer.is_bus_mute(0), "Master bus unmuted on FOCUS_IN")

	SaveManager.mute_on_unfocus = false
	SaveManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(AudioServer.is_bus_mute(0), "Master bus remains unmuted on FOCUS_OUT when mute_on_unfocus == false")
	SaveManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	SaveManager.mute_on_unfocus = true
