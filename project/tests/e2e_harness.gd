extends RefCounted
## Shared opaque-box E2E harness base for 《尘缘问道》 (NO class_name — inherited via extends "res://tests/e2e_harness.gd").
## Strictly complies with gdscript/warnings/untyped_declaration=2, unsafe_property_access=1, unsafe_method_access=1.

var tree: SceneTree = null
var suite_path: String = ""
var suite_mode: String = "headless"
var is_visual_mode: bool = false
var scratch_dir: String = ""
var results: Array[Dictionary] = []

var _registered_cases: Array[Dictionary] = []
var _active_case_id: String = ""
var _cur_failures: Array[String] = []
var _cur_metrics: Dictionary = {}
var _spawned_nodes: Array[Node] = []
var _in_scoped_save_test: bool = false

static var _baseline_signals_captured: bool = false
static var _baseline_autoload_signals: Dictionary = {}
static var _suite_pinned_resources: Array[Resource] = []

const AUTOLOAD_NAMES: Array[String] = [
	"DataDB",
	"NotifyHub",
	"InputRouter",
	"CampaignState",
	"SaveManager",
]

const BUILTIN_NODE_SIGNALS: Array[String] = [
	"ready",
	"renamed",
	"tree_entered",
	"tree_exiting",
	"tree_exited",
	"child_entered_tree",
	"child_exiting_tree",
	"child_order_changed",
	"replacing_by",
	"editor_description_changed",
	"script_changed",
	"property_list_changed",
]


func register_cases() -> void:
	pass # Overridden by each project/tests/tier{1..4}/test_*.gd suite


func add_case(
	case_id: String,
	tier: int,
	feature: String,
	target: String,
	title: String,
	method_name: String
) -> void:
	_registered_cases.append({
		"id": case_id.strip_edges(),
		"tier": tier,
		"feature": _normalize_feature(feature),
		"target": target.strip_edges(),
		"title": title.strip_edges(),
		"method": method_name.strip_edges(),
	})


func get_registered_cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in _registered_cases:
		var copy_d: Dictionary = item.duplicate(true)
		copy_d["mode"] = suite_mode
		copy_d["suite"] = _to_repo_rel_suite(suite_path)
		out.append(copy_d)
	return out


func _normalize_feature(raw_feat: String) -> String:
	var tok: String = raw_feat.strip_edges().to_upper()
	if tok.begins_with("F"):
		tok = tok.substr(1)
	if tok.is_valid_int():
		return "F%d" % int(tok)
	return raw_feat.strip_edges().to_upper()


func _to_repo_rel_suite(res_path: String) -> String:
	if res_path.begins_with("res://"):
		return "project/" + res_path.substr(6)
	return res_path


func _case_matches_filters(
	cdef: Dictionary,
	tier_filter: Array[int],
	feature_filter: Array[String],
	target_filter: Array[String],
	case_filter: Array[String]
) -> bool:
	var cid: String = str(cdef.get("id", ""))
	var ctier: int = int(cdef.get("tier", 0))
	var cfeat: String = str(cdef.get("feature", ""))
	var ctarg: String = str(cdef.get("target", ""))
	if not tier_filter.is_empty() and not tier_filter.has(ctier):
		return false
	if not feature_filter.is_empty() and not feature_filter.has(cfeat):
		return false
	if not target_filter.is_empty() and not target_filter.has(ctarg):
		return false
	if not case_filter.is_empty() and not case_filter.has(cid):
		return false
	return true


func run_selected_cases(
	tier_filter: Array[int],
	feature_filter: Array[String],
	target_filter: Array[String],
	case_filter: Array[String]
) -> Array[Dictionary]:
	results.clear()
	capture_baseline_autoload_signals()
	for cdef: Dictionary in _registered_cases:
		if not _case_matches_filters(cdef, tier_filter, feature_filter, target_filter, case_filter):
			continue
		var cid: String = str(cdef.get("id", ""))
		var ctier: int = int(cdef.get("tier", 1))
		var cfeat: String = str(cdef.get("feature", "F1"))
		var ctarg: String = str(cdef.get("target", "baseline"))
		var ctitle: String = str(cdef.get("title", ""))
		var mname: String = str(cdef.get("method", ""))

		_active_case_id = cid
		_cur_failures.clear()
		_cur_metrics.clear()
		reset_sandbox_campaign("cultivation")

		print("@@E2E_CASE_START@@%s" % cid)
		var t0_usec: int = Time.get_ticks_usec()
		var status: String = "PASS"
		var msg: String = ""

		if not has_method(mname):
			status = "ERROR"
			msg = "Suite '%s' is missing test method '%s'" % [suite_path, mname]
		else:
			var cb: Callable = Callable(self, mname)
			await cb.call()
			if not _cur_failures.is_empty():
				status = "FAIL"
				msg = "; ".join(_cur_failures)

		var dur_ms: float = float(Time.get_ticks_usec() - t0_usec) / 1000.0
		cleanup_case_state()
		if tree != null:
			await tree.process_frame
		print("@@E2E_CASE_END@@%s@@%s" % [cid, status])

		results.append({
			"id": cid,
			"tier": ctier,
			"feature": cfeat,
			"target": ctarg,
			"mode": suite_mode,
			"suite": _to_repo_rel_suite(suite_path),
			"title": ctitle,
			"status": status,
			"duration_ms": snappedf(dur_ms, 0.01),
			"message": msg,
			"metrics": _cur_metrics.duplicate(true),
		})
		_active_case_id = ""
	if tree != null:
		await tree.process_frame
	return results


# ==================== Assertions (Non-Aborting Within Case) ====================

func fail_msg(msg: String) -> void:
	_cur_failures.append(msg)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_cur_failures.append(msg)


func assert_false(cond: bool, msg: String) -> void:
	if cond:
		_cur_failures.append(msg)


func assert_not_null(val: Variant, msg: String) -> void:
	if val == null:
		_cur_failures.append("%s [actual=null]" % msg)


func assert_null(val: Variant, msg: String) -> void:
	if val != null:
		_cur_failures.append("%s [expected=null, actual=%s]" % [msg, str(val)])


func assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		_cur_failures.append("%s [expected=%s, actual=%s]" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String) -> void:
	if actual == unexpected:
		_cur_failures.append("%s [unexpected=%s]" % [msg, str(actual)])


func assert_approx(actual: float, expected: float, eps: float, msg: String) -> void:
	if is_nan(actual) or absf(actual - expected) > eps:
		_cur_failures.append("%s [expected=%.4f±%.4f, actual=%.4f]" % [msg, expected, eps, actual])


func assert_gt(actual: float, threshold: float, msg: String) -> void:
	if is_nan(actual) or not (actual > threshold):
		_cur_failures.append("%s [expected > %.4f, actual=%.4f]" % [msg, threshold, actual])


func assert_ge(actual: float, threshold: float, msg: String) -> void:
	if is_nan(actual) or not (actual >= threshold):
		_cur_failures.append("%s [expected >= %.4f, actual=%.4f]" % [msg, threshold, actual])


func assert_lt(actual: float, threshold: float, msg: String) -> void:
	if is_nan(actual) or not (actual < threshold):
		_cur_failures.append("%s [expected < %.4f, actual=%.4f]" % [msg, threshold, actual])


func assert_le(actual: float, threshold: float, msg: String) -> void:
	if is_nan(actual) or not (actual <= threshold):
		_cur_failures.append("%s [expected <= %.4f, actual=%.4f]" % [msg, threshold, actual])


func assert_str_contains(haystack: String, needle: String, msg: String) -> void:
	if not haystack.contains(needle):
		_cur_failures.append("%s [missing '%s' in '%s']" % [msg, needle, haystack])


func assert_str_not_contains(haystack: String, needle: String, msg: String) -> void:
	if haystack.contains(needle):
		_cur_failures.append("%s [unexpected '%s' found in '%s']" % [msg, needle, haystack])


func record_metric(key: String, val: Variant) -> void:
	_cur_metrics[key] = val


func read_thread_run_delay_ns() -> int:
	var f: FileAccess = FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return 0
	var ln: String = f.get_line().strip_edges()
	f.close()
	var parts: PackedStringArray = ln.split(" ", false)
	if parts.size() >= 2 and parts[1].is_valid_int():
		return int(parts[1])
	return 0


func allow_expected_engine_error(pattern: String) -> void:
	print("@@E2E_ALLOW_ERR@@%s@@%s" % [_active_case_id, pattern])


# ==================== Safe Typed Casts & Forward-Compatible Reflection ====================

func as_dict(val: Variant) -> Dictionary:
	if val is Dictionary:
		return val as Dictionary
	return {}


func as_arr(val: Variant) -> Array:
	if val is Array:
		return val as Array
	return []


func obj_has_prop(obj: Object, prop_name: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var plist: Array[Dictionary] = obj.get_property_list()
	for p: Dictionary in plist:
		if str(p.get("name", "")) == prop_name:
			return true
	return false


func obj_get(obj: Object, prop_name: String, default_val: Variant = null) -> Variant:
	if not obj_has_prop(obj, prop_name):
		return default_val
	var val: Variant = obj.get(prop_name)
	return default_val if val == null else val


func obj_set(obj: Object, prop_name: String, val: Variant) -> bool:
	if not obj_has_prop(obj, prop_name):
		return false
	obj.set(prop_name, val)
	return true


func obj_has_method(obj: Object, method_name: String) -> bool:
	return obj != null and is_instance_valid(obj) and obj.has_method(method_name)


func obj_method_arg_count(obj: Object, method_name: String) -> int:
	if not obj_has_method(obj, method_name):
		return -1
	var mlist: Array[Dictionary] = obj.get_method_list()
	for m: Dictionary in mlist:
		if str(m.get("name", "")) == method_name:
			var args: Array = m.get("args", []) as Array
			return args.size()
	return -1


func obj_call(obj: Object, method_name: String, args: Array = []) -> Variant:
	if not obj_has_method(obj, method_name):
		return null
	return obj.callv(method_name, args)


func step_vfx_compat(vfx: Object, combat_delta: float, ui_delta: float) -> bool:
	var argc: int = obj_method_arg_count(vfx, "step_fx")
	if argc >= 2:
		vfx.callv("step_fx", [combat_delta, ui_delta])
		return true
	elif argc == 1:
		vfx.callv("step_fx", [combat_delta])
		return true
	return false


func res_exists(res_path: String) -> bool:
	return ResourceLoader.exists(res_path) or FileAccess.file_exists(res_path)


func load_tex(res_path: String) -> Texture2D:
	if not ResourceLoader.exists(res_path):
		return null
	return load(res_path) as Texture2D


func load_shader(res_path: String) -> Shader:
	if not ResourceLoader.exists(res_path):
		return null
	return load(res_path) as Shader


func load_json_dict(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		return {}
	var raw: String = FileAccess.get_file_as_string(res_path)
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func strip_shader_comments(code: String) -> String:
	if code == "":
		return ""
	var rx: RegEx = RegEx.new()
	rx.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
	return rx.sub(code, "", true)


func shader_code_has_unshaded_render_mode(code: String) -> bool:
	var clean_code: String = strip_shader_comments(code)
	if clean_code == "":
		return false
	var rx_rm: RegEx = RegEx.new()
	rx_rm.compile("\\brender_mode\\b[^;]*\\bunshaded\\b")
	return rx_rm.search(clean_code) != null


func shader_has_unshaded_render_mode(sh: Shader) -> bool:
	if sh == null:
		return false
	return shader_code_has_unshaded_render_mode(sh.code)


func is_canvas_item_unshaded(ci: CanvasItem) -> bool:
	if ci == null or not is_instance_valid(ci):
		return false
	var cur: Node = ci
	while cur != null and cur is CanvasItem:
		var item: CanvasItem = cur as CanvasItem
		var mat: Material = item.material
		if mat is CanvasItemMaterial:
			if (mat as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED:
				return true
		elif mat is ShaderMaterial:
			var sh: Shader = (mat as ShaderMaterial).shader
			if shader_has_unshaded_render_mode(sh):
				return true
		if not item.use_parent_material:
			break
		cur = item.get_parent()
	return false


func collect_active_gpu_particles(root_node: Node) -> Array[GPUParticles2D]:
	var out: Array[GPUParticles2D] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var found_nodes: Array[Node] = root_node.find_children("*", "GPUParticles2D", true, false)
	for p_node: Node in found_nodes:
		var gp: GPUParticles2D = p_node as GPUParticles2D
		if gp != null and is_instance_valid(gp) and gp.visible and gp.process_material != null:
			out.append(gp)
	return out


func count_visible_canvas_children(parent_node: Node) -> int:
	if parent_node == null or not is_instance_valid(parent_node):
		return 0
	var cnt: int = 0
	for ch: Node in parent_node.get_children():
		if ch is CanvasItem and (ch as CanvasItem).visible:
			cnt += 1
	return cnt


func find_alchemy_cauldron_rect(modals: Node) -> Rect2i:
	if modals == null or not is_instance_valid(modals):
		return Rect2i()
	var found: bool = false
	var union_r: Rect2 = Rect2()
	var stack: Array[Node] = [modals]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var cand_r: Rect2 = Rect2()
		var is_cand: bool = false
		if cur is TextureRect:
			var tr_c: TextureRect = cur as TextureRect
			if tr_c.is_visible_in_tree() and tr_c.texture != null and tr_c.size.y >= 110.0:
				cand_r = tr_c.get_global_rect()
				is_cand = true
		elif cur is NinePatchRect:
			var np_c: NinePatchRect = cur as NinePatchRect
			if np_c.is_visible_in_tree() and np_c.texture != null and np_c.size.y >= 110.0:
				cand_r = np_c.get_global_rect()
				is_cand = true
		elif cur is Sprite2D:
			var sp_c: Sprite2D = cur as Sprite2D
			if sp_c.visible and sp_c.is_visible_in_tree() and sp_c.texture != null:
				var sp_sz: Vector2 = sp_c.texture.get_size() * sp_c.global_scale.abs()
				var sp_tl: Vector2 = (
					sp_c.global_position
					- (sp_sz * 0.5 if sp_c.centered else Vector2.ZERO)
					+ sp_c.offset * sp_c.global_scale
				)
				cand_r = Rect2(sp_tl, sp_sz)
				is_cand = true
		elif cur is GPUParticles2D or cur is CPUParticles2D:
			var ci_p: Node2D = cur as Node2D
			if ci_p != null and ci_p.visible and ci_p.is_visible_in_tree():
				cand_r = Rect2(ci_p.global_position - Vector2(140.0, 140.0), Vector2(280.0, 240.0))
				is_cand = true
		elif cur is Control and cur != modals:
			var ctrl_c: Control = cur as Control
			if ctrl_c.is_visible_in_tree() and ctrl_c.size.y >= 110.0 and (
				(cur.get_script() != null and obj_has_method(ctrl_c, "_draw"))
				or ctrl_c.material is ShaderMaterial
			):
				cand_r = ctrl_c.get_global_rect()
				is_cand = true
		if is_cand and cand_r.size.x > 4.0 and cand_r.size.y > 4.0:
			if not found:
				union_r = cand_r
				found = true
			else:
				union_r = union_r.merge(cand_r)
		for ch: Node in cur.get_children():
			stack.append(ch)
	if not found:
		return Rect2i()
	var x0: int = clampi(int(floor(union_r.position.x)), 0, 1920)
	var y0: int = clampi(int(floor(union_r.position.y)), 0, 1080)
	var x1: int = clampi(int(ceil(union_r.end.x)), 0, 1920)
	var y1: int = clampi(int(ceil(union_r.end.y)), 0, 1080)
	if x1 <= x0 or y1 <= y0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


# ==================== Dual-Lock Sandbox Isolation & Autoload Signal Hygiene ====================

static func capture_baseline_autoload_signals_for_tree(tree_ref: SceneTree) -> void:
	if _baseline_signals_captured or tree_ref == null or tree_ref.root == null:
		return
	_baseline_autoload_signals.clear()
	for aname: String in AUTOLOAD_NAMES:
		var singleton: Node = tree_ref.root.get_node_or_null(aname)
		if singleton == null:
			continue
		var sigs: Array[Dictionary] = singleton.get_signal_list()
		for s: Dictionary in sigs:
			var sname: String = str(s.get("name", ""))
			if BUILTIN_NODE_SIGNALS.has(sname):
				continue
			var bkey: String = "%s::%s" % [aname, sname]
			var cbs: Array[Callable] = []
			var conns: Array[Dictionary] = singleton.get_signal_connection_list(sname)
			for c: Dictionary in conns:
				var cb: Callable = c.get("callable", Callable()) as Callable
				if cb.is_valid():
					cbs.append(cb)
			_baseline_autoload_signals[bkey] = cbs
	_baseline_signals_captured = true


func capture_baseline_autoload_signals() -> void:
	capture_baseline_autoload_signals_for_tree(tree)


func purge_autoload_scene_signals() -> void:
	if not _baseline_signals_captured and tree != null:
		capture_baseline_autoload_signals_for_tree(tree)
	if tree == null or tree.root == null:
		return
	for aname: String in AUTOLOAD_NAMES:
		var singleton: Node = tree.root.get_node_or_null(aname)
		if singleton == null:
			continue
		var sigs: Array[Dictionary] = singleton.get_signal_list()
		for s: Dictionary in sigs:
			var sname: String = str(s.get("name", ""))
			if BUILTIN_NODE_SIGNALS.has(sname):
				continue
			var bkey: String = "%s::%s" % [aname, sname]
			var base_cbs: Array = _baseline_autoload_signals.get(bkey, []) as Array
			var conns: Array[Dictionary] = singleton.get_signal_connection_list(sname)
			for c: Dictionary in conns:
				var cb: Callable = c.get("callable", Callable()) as Callable
				var is_baseline: bool = false
				for b_var: Variant in base_cbs:
					var b_cb: Callable = b_var as Callable
					if b_cb == cb:
						is_baseline = true
						break
				if not is_baseline and singleton.is_connected(sname, cb):
					singleton.disconnect(sname, cb)


func get_autoload(autoload_name: String) -> Node:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func reset_sandbox_campaign(difficulty: String = "cultivation") -> void:
	var nh: Node = get_autoload("NotifyHub")
	if nh != null:
		nh.call("set_combat_active", false)
		nh.call("set_narrative_exclusive", false)
		nh.call("clear_all_transient")
		(nh.get("_p3_queue") as Array).clear()
		(nh.get("_active_slip_timers") as Array).clear()
		(nh.get("_aoe_buckets") as Dictionary).clear()
		nh.set("_post_busy_timer", 0.0)
	var ir: Node = get_autoload("InputRouter")
	if ir != null:
		ir.call("reset_default_keybinds")
		ir.call("set_mode", 0) # InputRouter.MODE_WORLD_COMBAT
		ir.set("combat_engaged", false)
		ir.set("alt_held", false)
		ir.set("_dialogue_cooldown_sec", 0.0)
	var sm: Node = get_autoload("SaveManager")
	if sm != null:
		sm.set("in_puzzle_lock", false)
		sm.set("reduced_motion", false)
		sm.set("screen_shake_pct", 0.40)
		sm.set("colorblind_dual_code", true)
		sm.set("master_muted", false)
	var cs: Node = get_autoload("CampaignState")
	if cs != null:
		cs.call("start_new_campaign", difficulty)
		cs.set("sandbox_mode", true) # MANDATORY LOCK 2 right after start_new_campaign()!


func _is_scratch_user_dir_safe() -> bool:
	var udir: String = OS.get_user_data_dir()
	return udir.contains("/.gemini/jetski/scratch/") and not udir.contains("/.local/share/godot")


func _wipe_scratch_user_saves() -> void:
	if not _is_scratch_user_dir_safe():
		return
	var da: DirAccess = DirAccess.open("user://saves")
	if da == null:
		return
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir():
			da.remove(fname)
		fname = da.get_next()
	da.list_dir_end()


func begin_isolated_xdg_save_test() -> bool:
	var udir: String = OS.get_user_data_dir()
	var cs: Node = get_autoload("CampaignState")
	if not _is_scratch_user_dir_safe():
		fail_msg("ISOLATION BREACH: Refusing disk save test outside scratch XDG dir: " + udir)
		if cs != null:
			cs.set("sandbox_mode", true)
		return false
	_wipe_scratch_user_saves()
	var sm: Node = get_autoload("SaveManager")
	if sm != null:
		sm.set("_auto_slot_cursor", 1)
		sm.set("in_puzzle_lock", false)
	var nh: Node = get_autoload("NotifyHub")
	if nh != null:
		nh.call("set_combat_active", false)
	_in_scoped_save_test = true
	if cs != null:
		cs.set("sandbox_mode", false)
	return true


func end_isolated_xdg_save_test() -> void:
	_wipe_scratch_user_saves()
	var cs: Node = get_autoload("CampaignState")
	if cs != null:
		cs.set("sandbox_mode", true)
	_in_scoped_save_test = false


func cleanup_case_state() -> void:
	if _in_scoped_save_test:
		end_isolated_xdg_save_test()
	for i: int in range(_spawned_nodes.size() - 1, -1, -1):
		var n: Node = _spawned_nodes[i]
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_spawned_nodes.clear()
	purge_autoload_scene_signals()
	var cs: Node = get_autoload("CampaignState")
	if cs != null:
		cs.call("bump_scene_epoch")
		cs.set("sandbox_mode", true)
	var nh: Node = get_autoload("NotifyHub")
	if nh != null:
		nh.call("set_combat_active", false)
		nh.call("set_narrative_exclusive", false)
		nh.call("clear_all_transient")
		(nh.get("_p3_queue") as Array).clear()
		(nh.get("_active_slip_timers") as Array).clear()
		(nh.get("_aoe_buckets") as Dictionary).clear()
	var ir: Node = get_autoload("InputRouter")
	if ir != null:
		ir.call("set_mode", 0)
		ir.set("combat_engaged", false)
	for lpf_bus: String in ["BGM_Bus", "Ambient_UI_Bus"]:
		var bidx: int = AudioServer.get_bus_index(lpf_bus)
		if bidx >= 0 and AudioServer.get_bus_effect_count(bidx) > 0:
			AudioServer.set_bus_effect_enabled(bidx, 0, false)


# ==================== Scene Spawning, Frame Stepping & 1080p Visual Capture ====================

func track_node(n: Node) -> Node:
	if n != null and not _spawned_nodes.has(n):
		_spawned_nodes.append(n)
	return n


func mount_node(n: Node, parent: Node = null) -> Node:
	if n == null:
		return null
	var target_parent: Node = parent if parent != null else (tree.root if tree != null else null)
	if target_parent != null and n.get_parent() == null:
		target_parent.add_child(n)
	return track_node(n)


func ensure_suite_world_resources_pinned() -> void:
	if not _suite_pinned_resources.is_empty():
		return
	var core_paths: Array[String] = [
		"res://src/presentation/world/qinglan_world.tscn",
		"res://assets/cg/title_qianli_jiangshan.png",
		"res://assets/cg/cg_ch01_layer0_sky.png",
		"res://assets/cg/cg_ch01_layer1_temple.png",
		"res://assets/cg/cg_ch01_layer2_wolves.png",
		"res://assets/cg/cg_ch01_layer3_fg_blade.png",
		"res://assets/world/tex_moss_earth.png",
		"res://assets/world/tex_cave_flagstone.png",
		"res://assets/world/tex_bluestone_wet.png",
		"res://assets/audio/bgm/bgm_qinglan_calm.ogg",
		"res://assets/audio/bgm/bgm_qinglan_combat.ogg",
		"res://assets/audio/bgm/amb_qinglan_rain.ogg",
		"res://assets/audio/bgm/bgm_boss_wolf_king.ogg",
		"res://assets/sprites/gu_changqing_sheet.png",
		"res://assets/sprites/shen_qinghe_sheet.png",
		"res://assets/sprites/pei_zhao_sheet.png",
		"res://assets/sprites/boss_mist_wolf_king_sheet.png",
		"res://assets/sprites/wolf_pup_sheet.png",
		"res://assets/sprites/rot_wolf_sheet.png",
		"res://assets/sprites/rogue_cultivator_sheet.png",
		"res://assets/sprites/miasma_shaman_sheet.png",
		"res://assets/sprites/wood_golem_sheet.png",
		"res://assets/sprites/pet_fire_fox_sheet.png",
		"res://assets/sprites/pet_spirit_turtle_sheet.png",
	]
	for rpath: String in core_paths:
		if ResourceLoader.exists(rpath):
			var r_obj: Resource = load(rpath)
			if r_obj != null:
				_suite_pinned_resources.append(r_obj)


static func clear_shared_pinned_resources() -> void:
	_suite_pinned_resources.clear()


func spawn_qinglan_world(
	zone_id: String = "tingyu_town",
	spawn_tag: String = "town_south_entry"
) -> Node2D:
	ensure_suite_world_resources_pinned()
	var cs: Node = get_autoload("CampaignState")
	if cs != null:
		cs.set("current_zone_id", zone_id)
		cs.set("current_spawn_tag", spawn_tag)
		cs.set("sandbox_mode", true)
	var packed: PackedScene = load("res://src/presentation/world/qinglan_world.tscn") as PackedScene
	var world: Node2D = packed.instantiate() as Node2D
	tree.root.add_child(world)
	_spawned_nodes.append(world)
	var cam_v: Variant = world.get("_camera")
	if cam_v is Camera2D:
		(cam_v as Camera2D).position_smoothing_enabled = false
	return world


func spawn_title_screen() -> Control:
	var cs: Node = get_autoload("CampaignState")
	if cs != null:
		cs.set("sandbox_mode", true)
	var packed: PackedScene = load("res://src/presentation/ui/title_screen.tscn") as PackedScene
	var title: Control = packed.instantiate() as Control
	tree.root.add_child(title)
	_spawned_nodes.append(title)
	return title


func step_frames(count: int = 1) -> void:
	if tree == null:
		return
	var steps: int = maxi(1, count)
	for _i: int in range(steps):
		await tree.process_frame


func capture_1080p_frame(warmup_frames: int = 18, save_tag: String = "") -> Image:
	if tree == null or tree.root == null:
		fail_msg("capture_1080p_frame called without active SceneTree")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	if DisplayServer.get_name() == "headless":
		fail_msg(
			"capture_1080p_frame requires '# @e2e_mode: visual' (Xvfb + opengl3); DisplayServer is headless"
		)
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)

	tree.root.size = Vector2i(1920, 1080)
	var total_warmup: int = maxi(18, warmup_frames)
	var raster_frames: int = mini(6, total_warmup)
	var sim_warmup_frames: int = maxi(0, total_warmup - raster_frames)

	var prev_render_loop: bool = RenderingServer.render_loop_enabled
	if sim_warmup_frames > 0:
		RenderingServer.render_loop_enabled = false
		for _s: int in range(sim_warmup_frames):
			await tree.process_frame

	RenderingServer.render_loop_enabled = true
	var pulse_layer: CanvasLayer = CanvasLayer.new()
	pulse_layer.layer = 120
	var pulse_dot: ColorRect = ColorRect.new()
	pulse_dot.size = Vector2(1.0, 1.0)
	pulse_dot.position = Vector2(0.0, 1079.0)
	pulse_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_dot.color = Color(0.0, 0.0, 0.0, 0.008)
	pulse_layer.add_child(pulse_dot)
	tree.root.add_child(pulse_layer)

	for i: int in range(raster_frames):
		pulse_dot.color.a = 0.008 if (i % 2 == 0) else 0.012
		await tree.process_frame
	pulse_dot.color.a = 0.010
	pulse_dot.queue_redraw()
	await RenderingServer.frame_post_draw

	var vp_tex: ViewportTexture = tree.root.get_texture()
	var img: Image = vp_tex.get_image()
	if pulse_layer.get_parent() != null:
		pulse_layer.get_parent().remove_child(pulse_layer)
	pulse_layer.free()
	RenderingServer.render_loop_enabled = prev_render_loop

	if save_tag != "" and scratch_dir != "" and img != null:
		var shots_dir: String = scratch_dir.path_join("shots")
		DirAccess.make_dir_recursive_absolute(shots_dir)
		img.save_png(shots_dir.path_join(save_tag + ".png"))
	return img


func capture_1080p_subframe(frames: int = 3) -> Image:
	if tree == null or tree.root == null or DisplayServer.get_name() == "headless":
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	tree.root.size = Vector2i(1920, 1080)
	var prev_render_loop: bool = RenderingServer.render_loop_enabled
	RenderingServer.render_loop_enabled = true
	var pulse_layer: CanvasLayer = CanvasLayer.new()
	pulse_layer.layer = 120
	var pulse_dot: ColorRect = ColorRect.new()
	pulse_dot.size = Vector2(1.0, 1.0)
	pulse_dot.position = Vector2(0.0, 1079.0)
	pulse_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_dot.color = Color(0.0, 0.0, 0.0, 0.008)
	pulse_layer.add_child(pulse_dot)
	tree.root.add_child(pulse_layer)
	for i: int in range(maxi(2, frames)):
		pulse_dot.color.a = 0.008 if (i % 2 == 0) else 0.012
		await tree.process_frame
	pulse_dot.color.a = 0.010
	pulse_dot.queue_redraw()
	await RenderingServer.frame_post_draw
	var img: Image = tree.root.get_texture().get_image()
	if pulse_layer.get_parent() != null:
		pulse_layer.get_parent().remove_child(pulse_layer)
	pulse_layer.free()
	RenderingServer.render_loop_enabled = prev_render_loop
	return img


# ==================== Strictly Typed UI, Input & Pixel ROI Helpers ====================

func _is_node_effectively_visible(n: Node, stop_root: Node = null) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var cur: Node = n
	while cur != null:
		if cur is CanvasItem and not (cur as CanvasItem).visible:
			return false
		if cur is CanvasLayer and not (cur as CanvasLayer).visible:
			return false
		if stop_root != null and cur == stop_root:
			break
		cur = cur.get_parent()
	if n is CanvasItem and (n as CanvasItem).is_inside_tree():
		if not (n as CanvasItem).is_visible_in_tree():
			return false
	return true


func collect_visible_labels(root_node: Node) -> Array[Label]:
	var out: Array[Label] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label and _is_node_effectively_visible(cur, root_node):
			out.append(cur as Label)
		var children: Array[Node] = cur.get_children()
		for i: int in range(children.size() - 1, -1, -1):
			stack.append(children[i])
	return out


func collect_visible_buttons(root_node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Button and _is_node_effectively_visible(cur, root_node):
			out.append(cur as Button)
		var children: Array[Node] = cur.get_children()
		for i: int in range(children.size() - 1, -1, -1):
			stack.append(children[i])
	return out


func collect_texture_rects(root_node: Node, visible_only: bool = false) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	if root_node == null or not is_instance_valid(root_node):
		return out
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is TextureRect:
			if not visible_only or _is_node_effectively_visible(cur, root_node):
				out.append(cur as TextureRect)
		var children: Array[Node] = cur.get_children()
		for i: int in range(children.size() - 1, -1, -1):
			stack.append(children[i])
	return out


func collect_visible_texture_rects(root_node: Node) -> Array[TextureRect]:
	return collect_texture_rects(root_node, true)


func min_font_size_in_tree(root_node: Node) -> Dictionary:
	var min_px: int = 9999
	var max_px: int = 0
	var count: int = 0
	var min_path: String = ""
	var min_text: String = ""
	var offenders: Array[String] = []
	if root_node == null or not is_instance_valid(root_node):
		return {
			"min_px": 0,
			"max_px": 0,
			"count": 0,
			"min_node_path": "",
			"min_text": "",
			"offenders": offenders,
		}

	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if _is_node_effectively_visible(cur, root_node):
			var fsize: int = -1
			var sample_txt: String = ""
			if cur is Label:
				var lbl: Label = cur as Label
				sample_txt = lbl.text.strip_edges()
				if sample_txt != "":
					if lbl.label_settings != null:
						fsize = lbl.label_settings.font_size
					else:
						fsize = lbl.get_theme_font_size("font_size", "Label")
			elif cur is Button:
				var btn: Button = cur as Button
				sample_txt = btn.text.strip_edges()
				if sample_txt != "":
					fsize = btn.get_theme_font_size("font_size", "Button")
			elif cur is RichTextLabel:
				var rtl: RichTextLabel = cur as RichTextLabel
				sample_txt = rtl.get_parsed_text().strip_edges()
				if sample_txt != "":
					fsize = rtl.get_theme_font_size("normal_font_size", "RichTextLabel")
			elif cur is LineEdit:
				var le: LineEdit = cur as LineEdit
				sample_txt = (le.text + le.placeholder_text).strip_edges()
				if sample_txt != "":
					fsize = le.get_theme_font_size("font_size", "LineEdit")

			if fsize > 0:
				count += 1
				if fsize < min_px:
					min_px = fsize
					min_path = str(cur.name)
					min_text = sample_txt
				if fsize > max_px:
					max_px = fsize
				if fsize < 16:
					offenders.append("%s(%dpx:'%s')" % [str(cur.name), fsize, sample_txt.left(24)])

		var children: Array[Node] = cur.get_children()
		for i: int in range(children.size() - 1, -1, -1):
			stack.append(children[i])

	if count == 0:
		min_px = 0
	return {
		"min_px": min_px,
		"max_px": max_px,
		"count": count,
		"min_node_path": min_path,
		"min_text": min_text,
		"offenders": offenders,
	}


func make_key_event(
	keycode: Key,
	pressed: bool = true,
	ctrl: bool = false,
	alt: bool = false
) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.echo = false
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	return ev


func make_mouse_button_event(
	btn: MouseButton,
	pos: Vector2,
	pressed: bool = true
) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = btn
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	return ev


func make_mouse_motion_event(pos: Vector2) -> InputEventMouseMotion:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev


func dispatch_input(ev: InputEvent) -> void:
	if tree != null and tree.root != null and ev != null:
		tree.root.push_input(ev)


func sample_image_roi_stats(img: Image, rect: Rect2i) -> Dictionary:
	if img == null or img.is_empty():
		return {
			"mean_r": 0.0,
			"mean_g": 0.0,
			"mean_b": 0.0,
			"mean_luma": 0.0,
			"max_luma": 0.0,
			"min_luma": 0.0,
			"std_luma": 0.0,
			"non_dark_ratio": 0.0,
			"mean_r_255": 0.0,
			"mean_g_255": 0.0,
			"mean_b_255": 0.0,
			"pixel_count": 0,
		}

	var w: int = img.get_width()
	var h: int = img.get_height()
	var x0: int = clampi(rect.position.x, 0, w)
	var y0: int = clampi(rect.position.y, 0, h)
	var x1: int = clampi(rect.position.x + rect.size.x, 0, w)
	var y1: int = clampi(rect.position.y + rect.size.y, 0, h)

	if x1 <= x0 or y1 <= y0:
		return {
			"mean_r": 0.0,
			"mean_g": 0.0,
			"mean_b": 0.0,
			"mean_luma": 0.0,
			"max_luma": 0.0,
			"min_luma": 0.0,
			"std_luma": 0.0,
			"non_dark_ratio": 0.0,
			"mean_r_255": 0.0,
			"mean_g_255": 0.0,
			"mean_b_255": 0.0,
			"pixel_count": 0,
		}

	var sum_r: float = 0.0
	var sum_g: float = 0.0
	var sum_b: float = 0.0
	var sum_luma: float = 0.0
	var sum_luma_sq: float = 0.0
	var max_luma: float = 0.0
	var min_luma: float = 1.0
	var non_dark_count: int = 0
	var count: int = 0

	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			var c: Color = img.get_pixel(x, y)
			var lum: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum_r += c.r
			sum_g += c.g
			sum_b += c.b
			sum_luma += lum
			sum_luma_sq += lum * lum
			if lum > max_luma:
				max_luma = lum
			if lum < min_luma:
				min_luma = lum
			if lum > 0.12:
				non_dark_count += 1
			count += 1

	var inv_n: float = 1.0 / float(maxi(1, count))
	var mean_r: float = sum_r * inv_n
	var mean_g: float = sum_g * inv_n
	var mean_b: float = sum_b * inv_n
	var mean_luma: float = sum_luma * inv_n
	var variance: float = maxf(0.0, (sum_luma_sq * inv_n) - (mean_luma * mean_luma))

	return {
		"mean_r": mean_r,
		"mean_g": mean_g,
		"mean_b": mean_b,
		"mean_luma": mean_luma,
		"max_luma": max_luma,
		"min_luma": min_luma,
		"std_luma": sqrt(variance),
		"non_dark_ratio": float(non_dark_count) * inv_n,
		"mean_r_255": mean_r * 255.0,
		"mean_g_255": mean_g * 255.0,
		"mean_b_255": mean_b * 255.0,
		"pixel_count": count,
	}


func wcag_contrast_color(col_a: Color, col_b: Color) -> float:
	var lum_a: float = _srgb_rel_lum(col_a)
	var lum_b: float = _srgb_rel_lum(col_b)
	var lighter: float = maxf(lum_a, lum_b)
	var darker: float = minf(lum_a, lum_b)
	return (lighter + 0.05) / (darker + 0.05)


func _srgb_rel_lum(col: Color) -> float:
	var r_lin: float = col.r / 12.92 if col.r <= 0.04045 else pow((col.r + 0.055) / 1.055, 2.4)
	var g_lin: float = col.g / 12.92 if col.g <= 0.04045 else pow((col.g + 0.055) / 1.055, 2.4)
	var b_lin: float = col.b / 12.92 if col.b <= 0.04045 else pow((col.b + 0.055) / 1.055, 2.4)
	return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
