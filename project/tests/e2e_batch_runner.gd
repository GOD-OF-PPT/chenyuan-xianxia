extends SceneTree
## Batched GDScript SceneTree test runner for 《尘缘问道》 E2E suites.
## Supports --mode headless|visual, --list-only, --report-json, --scratch-dir,
## --suites / --suites-file, and --tiers / --features / --targets / --cases filters.

const E2EHarness = preload("res://tests/e2e_harness.gd")


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_run.call_deferred()


func _run() -> void:
	var cfg: Dictionary = _parse_user_args(OS.get_cmdline_user_args())
	var mode: String = str(cfg.get("mode", "headless"))
	var list_only: bool = bool(cfg.get("list_only", false))
	var report_json_path: String = str(cfg.get("report_json", ""))
	var scratch_dir: String = str(cfg.get("scratch_dir", ""))
	var suites: Array[String] = cfg.get("suites", []) as Array[String]
	var suite_modes: Dictionary = cfg.get("suite_modes", {}) as Dictionary
	var tier_filter: Array[int] = cfg.get("tiers", []) as Array[int]
	var feature_filter: Array[String] = cfg.get("features", []) as Array[String]
	var target_filter: Array[String] = cfg.get("targets", []) as Array[String]
	var case_filter: Array[String] = cfg.get("cases", []) as Array[String]

	# Lock 2: Hard verify user:// points inside isolated scratch XDG directory before anything else!
	var user_dir: String = OS.get_user_data_dir()
	if not user_dir.contains("/.gemini/jetski/scratch/") or user_dir.contains("/.local/share/godot"):
		printerr("FATAL_ISOLATION_BREACH: Unsafe OS.get_user_data_dir()=" + user_dir)
		quit(3)
		return

	var formal_saves_dir: String = OS.get_environment("CHENYUAN_FORMAL_SAVES_DIR")
	var pre_formal_snap: Dictionary = _snapshot_formal_saves_dir(formal_saves_dir)

	# Allow 1 frame for Autoload singletons (_ready) to complete initialization
	await process_frame
	if mode == "visual" and not list_only:
		RenderingServer.render_loop_enabled = false
	var cs_node: Node = root.get_node_or_null("CampaignState")
	if cs_node != null:
		cs_node.set("sandbox_mode", true)
	E2EHarness.capture_baseline_autoload_signals_for_tree(self)

	var all_cases: Array[Dictionary] = []
	var suite_errors: Array[Dictionary] = []

	for suite_res_path: String in suites:
		print("@@E2E_SUITE_START@@%s" % suite_res_path)
		if not ResourceLoader.exists(suite_res_path):
			var miss_msg: String = "Suite script does not exist: %s" % suite_res_path
			printerr("@@E2E_SUITE_ERROR@@%s@@%s" % [suite_res_path, miss_msg])
			suite_errors.append({"suite": suite_res_path, "message": miss_msg})
			print("@@E2E_SUITE_END@@%s" % suite_res_path)
			continue

		var scr: GDScript = load(suite_res_path) as GDScript
		if scr == null or not scr.can_instantiate():
			var comp_msg: String = "Failed to compile/load GDScript suite: %s" % suite_res_path
			printerr("@@E2E_SUITE_ERROR@@%s@@%s" % [suite_res_path, comp_msg])
			suite_errors.append({"suite": suite_res_path, "message": comp_msg})
			print("@@E2E_SUITE_END@@%s" % suite_res_path)
			continue

		var inst: Variant = scr.new()
		if not (inst is E2EHarness):
			var ext_msg: String = "Suite '%s' must extend 'res://tests/e2e_harness.gd'" % suite_res_path
			printerr("@@E2E_SUITE_ERROR@@%s@@%s" % [suite_res_path, ext_msg])
			suite_errors.append({"suite": suite_res_path, "message": ext_msg})
			print("@@E2E_SUITE_END@@%s" % suite_res_path)
			continue

		var suite: E2EHarness = inst as E2EHarness
		var declared_mode: String = str(suite_modes.get(suite_res_path, mode))
		suite.tree = self
		suite.suite_path = suite_res_path
		suite.suite_mode = declared_mode
		suite.is_visual_mode = (mode == "visual")
		suite.scratch_dir = scratch_dir
		suite.register_cases()

		if list_only:
			var defs: Array[Dictionary] = suite.get_registered_cases()
			for d: Dictionary in defs:
				all_cases.append(d)
		else:
			var suite_results: Array[Dictionary] = await suite.run_selected_cases(
				tier_filter,
				feature_filter,
				target_filter,
				case_filter
			)
			for r: Dictionary in suite_results:
				all_cases.append(r)

		print("@@E2E_SUITE_END@@%s" % suite_res_path)

	await process_frame
	var post_formal_snap: Dictionary = _snapshot_formal_saves_dir(formal_saves_dir)
	var isolation_errors: Array[String] = _diff_formal_snaps(pre_formal_snap, post_formal_snap)
	var isolation_ok: bool = isolation_errors.is_empty()
	if not isolation_ok:
		for iso_err: String in isolation_errors:
			printerr("FATAL_ISOLATION_BREACH: " + iso_err)

	var report_payload: Dictionary = {
		"mode": mode,
		"list_only": list_only,
		"user_data_dir": user_dir,
		"display_driver": DisplayServer.get_name(),
		"isolation_ok": isolation_ok,
		"isolation_errors": isolation_errors,
		"suite_errors": suite_errors,
		"cases": all_cases,
	}

	if report_json_path != "":
		var out_file: FileAccess = FileAccess.open(report_json_path, FileAccess.WRITE)
		if out_file != null:
			out_file.store_string(JSON.stringify(report_payload, "  "))
			out_file.close()
		else:
			printerr("FATAL_REPORT_WRITE_ERROR: Cannot write report JSON to " + report_json_path)
			E2EHarness.clear_shared_pinned_resources()
			quit(2)
			return

	RenderingServer.render_loop_enabled = true
	E2EHarness.clear_shared_pinned_resources()
	quit(0 if (isolation_ok and suite_errors.is_empty()) else (3 if not isolation_ok else 2))


func _parse_user_args(args: PackedStringArray) -> Dictionary:
	var mode: String = "headless"
	var list_only: bool = false
	var report_json: String = ""
	var scratch_dir: String = ""
	var suites: Array[String] = []
	var suite_modes: Dictionary = {}
	var tiers: Array[int] = []
	var features: Array[String] = []
	var targets: Array[String] = []
	var cases: Array[String] = []

	var idx: int = 0
	while idx < args.size():
		var flag: String = args[idx]
		if flag == "--list-only":
			list_only = true
			idx += 1
		elif flag == "--mode" and idx + 1 < args.size():
			mode = args[idx + 1].strip_edges()
			idx += 2
		elif flag == "--report-json" and idx + 1 < args.size():
			report_json = args[idx + 1].strip_edges()
			idx += 2
		elif flag == "--scratch-dir" and idx + 1 < args.size():
			scratch_dir = args[idx + 1].strip_edges()
			idx += 2
		elif flag == "--suites" and idx + 1 < args.size():
			for s_tok: String in args[idx + 1].split(",", false):
				var trimmed_s: String = s_tok.strip_edges()
				if trimmed_s != "" and not suites.has(trimmed_s):
					suites.append(trimmed_s)
			idx += 2
		elif flag == "--suites-file" and idx + 1 < args.size():
			var sf_path: String = args[idx + 1].strip_edges()
			if FileAccess.file_exists(sf_path):
				var parsed_sf: Variant = JSON.parse_string(FileAccess.get_file_as_string(sf_path))
				if parsed_sf is Array:
					var sf_arr: Array = parsed_sf as Array
					for entry_v: Variant in sf_arr:
						if entry_v is Dictionary:
							var ed: Dictionary = entry_v as Dictionary
							var sp: String = str(ed.get("res_path", ""))
							var sm: String = str(ed.get("mode", mode))
							if sp != "" and not suites.has(sp):
								suites.append(sp)
								suite_modes[sp] = sm
						else:
							var sp2: String = str(entry_v).strip_edges()
							if sp2 != "" and not suites.has(sp2):
								suites.append(sp2)
			idx += 2
		elif flag == "--tiers" and idx + 1 < args.size():
			for t_tok: String in args[idx + 1].split(",", false):
				var trimmed_t: String = t_tok.strip_edges()
				if trimmed_t.is_valid_int():
					tiers.append(int(trimmed_t))
			idx += 2
		elif flag == "--features" and idx + 1 < args.size():
			for f_tok: String in args[idx + 1].split(",", false):
				var trimmed_f: String = f_tok.strip_edges().to_upper()
				if trimmed_f != "":
					features.append(trimmed_f)
			idx += 2
		elif flag == "--targets" and idx + 1 < args.size():
			for tg_tok: String in args[idx + 1].split(",", false):
				var trimmed_tg: String = tg_tok.strip_edges()
				if trimmed_tg != "":
					targets.append(trimmed_tg)
			idx += 2
		elif flag == "--cases" and idx + 1 < args.size():
			for c_tok: String in args[idx + 1].split(",", false):
				var trimmed_c: String = c_tok.strip_edges()
				if trimmed_c != "":
					cases.append(trimmed_c)
			idx += 2
		else:
			idx += 1

	return {
		"mode": mode,
		"list_only": list_only,
		"report_json": report_json,
		"scratch_dir": scratch_dir,
		"suites": suites,
		"suite_modes": suite_modes,
		"tiers": tiers,
		"features": features,
		"targets": targets,
		"cases": cases,
	}


func _snapshot_formal_saves_dir(dir_path: String) -> Dictionary:
	var snap: Dictionary = {}
	if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
		snap["__exists__"] = false
		return snap
	snap["__exists__"] = true
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return snap
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir():
			var full_p: String = dir_path.path_join(fname)
			snap[fname] = {
				"mtime": FileAccess.get_modified_time(full_p),
				"sha256": FileAccess.get_sha256(full_p),
			}
		fname = da.get_next()
	da.list_dir_end()
	return snap


func _diff_formal_snaps(before: Dictionary, after: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for k_var: Variant in before.keys():
		var k: String = str(k_var)
		if not after.has(k):
			errs.append("Formal save entry disappeared: " + k)
		elif before[k] != after[k]:
			errs.append("Formal save entry modified: " + k)
	for k2_var: Variant in after.keys():
		var k2: String = str(k2_var)
		if not before.has(k2):
			errs.append("Unexpected formal save entry created: " + k2)
	return errs
