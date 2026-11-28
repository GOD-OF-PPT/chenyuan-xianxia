class_name BattleActor
extends Node2D
## 第三层战场实体表现与斜向关键帧动画机（主角小队 / 灵宠 / 明雷妖物 / 雾隐狼王 / 城镇NPC）
## 严格对齐 docs/design/20-art-bible.md 第 4.1 节与 21-ui-ux-spec.md 第 3.1.2 节：
## - 精灵严格锚定两脚中心 FeetOrigin（Y-Sort 深度排序零穿模）
## - 动画推进仅受 combat_delta 驱动（Space 战术凝时下 100% 定格）
## - 头顶智能杀意变色姓名板（青玉稳固 / 琥珀预警 / 朱砂OT）+ 琥珀金/暗红吟唱条 + 6秒五行母印古篆徽章 + Tier 1 宣纸气泡。

var actor_id: String = ""
var faction: String = "party" # party / pet / enemy / npc
var display_name: String = ""
var role_badge: String = ""
var sprite_id: String = "gu_changqing"

var alive: bool = true
var is_boss: bool = false
var is_elite: bool = false
var is_controlled: bool = false
var is_box_selected: bool = false
var is_targeted: bool = false
var is_hovered: bool = false

## 战斗属性与状态镜像（由 RtwpCombatController 实时同步）
var hp: int = 120
var max_hp: int = 120
var mp: int = 60
var max_mp: int = 60
var shield: float = 0.0

var ward_current: float = 0.0
var ward_max: float = 0.0
var ward_element: String = "none"
var stagger_timer: float = 0.0

var mother_seal_element: String = ""
var mother_seal_timer: float = 0.0
var miasma_stacks: int = 0
var lockout_timer: float = 0.0

var is_casting: bool = false
var cast_skill_name: String = ""
var cast_progress: float = 0.0
var cast_duration: float = 1.0
var cast_interruptible: bool = true

var nameplate_threat_state: String = "jade_safe" # jade_safe / amber_warn / cinnabar_ot
var stealth_alpha: float = 1.0
var is_occluded: bool = false
var occlusion_silhouette_alpha: float = 0.0

## 走位与朝向
var facing_dir: Vector2 = Vector2(1.0, 0.5).normalized()
var move_waypoint: Vector2 = Vector2.ZERO
var has_move_waypoint: bool = false
var home_pos: Vector2 = Vector2.ZERO
var patrol_points: Array[Vector2] = []
var patrol_index: int = 0

## 关键帧图集元数据
var _sprite: Sprite2D
var _occlusion_silhouette: Sprite2D
var _overlay_canvas: Node2D
var _sheet_meta: Dictionary = {}
var _cell_w: int = 224
var _cell_h: int = 224
var _foot_y: int = 202
var _head_top_px: int = 156
var _anim_state: String = "idle"
var _anim_timer: float = 0.0
var _one_shot_state: String = ""
var _one_shot_remaining: float = 0.0
var _death_dissolve: float = 0.0
var _visual_root_offset: Vector2 = Vector2.ZERO

## Tier 1 头顶轻量宣纸气泡
var _bark_text: String = ""
var _bark_timer: float = 0.0
var _bark_duration: float = 3.5
var _pulse_clock: float = 0.0

var _seal_textures: Dictionary = {}
var _hit_flash_shader: Shader = null
var _occ_silhouette_shader: Shader = null

var _hit_flash_mat: ShaderMaterial = null
var _hit_flash_timer: float = 0.0
var _hit_flash_duration: float = 0.12
var _hit_flash_peak: float = 0.0
var _flipped_left: bool = false


func _ready() -> void:
	if not SaveManager.settings_changed.is_connected(_on_comfort_settings_changed):
		SaveManager.settings_changed.connect(_on_comfort_settings_changed)


func _on_comfort_settings_changed() -> void:
	if SaveManager.reduced_motion:
		clear_hit_flash()


func setup_actor(
	p_actor_id: String,
	p_faction: String,
	p_name: String,
	p_sprite_id: String,
	p_scale_mult: float = 1.0
) -> void:
	actor_id = p_actor_id
	faction = p_faction
	display_name = p_name
	sprite_id = p_sprite_id
	home_pos = position
	_anim_state = "idle"
	_anim_timer = 0.0
	_one_shot_state = ""
	_one_shot_remaining = 0.0
	_visual_root_offset = Vector2.ZERO
	_death_dissolve = 0.0
	_hit_flash_timer = 0.0
	_hit_flash_peak = 0.0
	is_occluded = false
	occlusion_silhouette_alpha = 0.0
	if p_sprite_id == "boss_mist_wolf_king":
		facing_dir = Vector2(-1.0, 0.35).normalized()
	_flipped_left = facing_dir.x < -0.08
	visible = true

	if not SaveManager.settings_changed.is_connected(_on_comfort_settings_changed):
		SaveManager.settings_changed.connect(_on_comfort_settings_changed)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	if _occlusion_silhouette == null:
		_occlusion_silhouette = Sprite2D.new()
		_occlusion_silhouette.name = "OcclusionSilhouette"
		_occlusion_silhouette.centered = false
		_occlusion_silhouette.z_index = 5
		_occlusion_silhouette.visible = false
		_occlusion_silhouette.modulate = Color(1.0, 1.0, 1.0, 0.0)
		if _occ_silhouette_shader == null and ResourceLoader.exists("res://src/presentation/shaders/actor_occlusion_silhouette.gdshader"):
			_occ_silhouette_shader = load("res://src/presentation/shaders/actor_occlusion_silhouette.gdshader") as Shader
		if _occ_silhouette_shader != null:
			var sil_mat: ShaderMaterial = ShaderMaterial.new()
			sil_mat.shader = _occ_silhouette_shader
			_occlusion_silhouette.material = sil_mat
		add_child(_occlusion_silhouette)
	_ensure_hit_flash_material()
	if _overlay_canvas == null:
		_overlay_canvas = Node2D.new()
		_overlay_canvas.z_index = 26
		var ov_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		ov_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_overlay_canvas.material = ov_mat
		_overlay_canvas.draw.connect(_draw_overhead_ui)
		add_child(_overlay_canvas)

	_load_sprite_sheet(p_sprite_id)
	_sprite.scale = Vector2(p_scale_mult, p_scale_mult)
	if _occlusion_silhouette != null:
		_occlusion_silhouette.scale = Vector2(p_scale_mult, p_scale_mult)
	_ensure_seal_icons()
	_apply_current_frame()
	queue_redraw()
	_overlay_canvas.queue_redraw()


func _load_sprite_sheet(sid: String) -> void:
	var png_path: String = "res://assets/sprites/%s_sheet.png" % sid
	var json_path: String = "res://assets/sprites/%s_sheet.json" % sid
	if ResourceLoader.exists(png_path):
		_sprite.texture = load(png_path) as Texture2D
		if _occlusion_silhouette != null:
			_occlusion_silhouette.texture = _sprite.texture
	if FileAccess.file_exists(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			_sheet_meta = parsed as Dictionary
			_cell_w = int(_sheet_meta.get("cell_w", 224))
			_cell_h = int(_sheet_meta.get("cell_h", 224))
			_foot_y = int(_sheet_meta.get("foot_y", 202))
			_head_top_px = int(_sheet_meta.get("head_top_px", maxi(80, _foot_y - 44)))
	_sprite.region_enabled = true
	_sprite.offset = Vector2(-float(_cell_w) * 0.5, -float(_foot_y))
	if _occlusion_silhouette != null:
		_occlusion_silhouette.region_enabled = true
		_occlusion_silhouette.offset = _sprite.offset


func _ensure_seal_icons() -> void:
	if not _seal_textures.is_empty():
		return
	for elem: String in ["metal", "wood", "water", "fire", "earth"]:
		var p: String = "res://assets/ui/icons/seal_%s.png" % elem
		if ResourceLoader.exists(p):
			_seal_textures[elem] = load(p) as Texture2D


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() > 0.001:
		facing_dir = dir.normalized()


func is_knocked_down() -> bool:
	return (not alive) or (is_boss and stagger_timer > 4.0)


func has_active_attack_or_cast() -> bool:
	if is_casting:
		return true
	return _one_shot_remaining > 0.0 and (
		_one_shot_state == "attack_1"
		or _one_shot_state == "attack_2"
		or _one_shot_state == "cast_release"
	)


func play_action_anim(anim_name: String, duration_sec: float = 0.42) -> void:
	if is_knocked_down():
		return
	_one_shot_state = anim_name
	_one_shot_remaining = duration_sec
	_anim_state = anim_name
	_anim_timer = 0.0
	_apply_current_frame()


func _ensure_hit_flash_material() -> void:
	if _sprite == null:
		return
	if _hit_flash_shader == null and ResourceLoader.exists("res://src/presentation/shaders/actor_hit_flash.gdshader"):
		_hit_flash_shader = load("res://src/presentation/shaders/actor_hit_flash.gdshader") as Shader
	if _hit_flash_mat == null and _hit_flash_shader != null:
		_hit_flash_mat = ShaderMaterial.new()
		_hit_flash_mat.resource_local_to_scene = true
		_hit_flash_mat.shader = _hit_flash_shader
		_sprite.material = _hit_flash_mat
	if _hit_flash_mat != null:
		_hit_flash_mat.set_shader_parameter("hit_flash", 0.0)
		_hit_flash_mat.set_shader_parameter("occlusion_alpha", occlusion_silhouette_alpha)


func set_occlusion_state(p_occluded: bool, delta: float) -> void:
	var eff_occ: bool = p_occluded and alive
	is_occluded = eff_occ
	var target_a: float = 1.0 if eff_occ else 0.0
	occlusion_silhouette_alpha = move_toward(occlusion_silhouette_alpha, target_a, delta * 5.0)
	if _hit_flash_mat != null:
		_hit_flash_mat.set_shader_parameter("occlusion_alpha", occlusion_silhouette_alpha)
	if _occlusion_silhouette != null:
		var vis_sil: bool = alive and (occlusion_silhouette_alpha > 0.02)
		_occlusion_silhouette.visible = vis_sil
		if vis_sil:
			_occlusion_silhouette.modulate = Color(1.0, 1.0, 1.0, occlusion_silhouette_alpha * 0.85 * stealth_alpha)


func clear_hit_flash() -> void:
	_hit_flash_timer = 0.0
	_hit_flash_duration = 0.0
	_hit_flash_peak = 0.0
	if _hit_flash_mat != null:
		_hit_flash_mat.set_shader_parameter("hit_flash", 0.0)


func trigger_hit_flash(duration: float = 0.12, intensity: float = 1.0) -> void:
	if SaveManager.reduced_motion or duration <= 0.0 or intensity <= 0.0:
		clear_hit_flash()
		return
	var dur: float = maxf(0.03, duration)
	var pk: float = clampf(intensity, 0.0, 1.0)
	var cur_val: float = _compute_hit_flash_value()
	if pk >= cur_val or _hit_flash_timer <= 0.0:
		_hit_flash_duration = dur
		_hit_flash_timer = dur
		_hit_flash_peak = pk
	if _hit_flash_mat != null:
		_hit_flash_mat.set_shader_parameter("hit_flash", _compute_hit_flash_value())


func _compute_hit_flash_value() -> float:
	if _hit_flash_timer <= 0.0 or SaveManager.reduced_motion:
		return 0.0
	var ratio: float = clampf(_hit_flash_timer / maxf(0.001, _hit_flash_duration), 0.0, 1.0)
	return clampf(_hit_flash_peak * ratio * ratio, 0.0, 1.0)


func show_world_bark(text: String, duration_sec: float = 3.5) -> void:
	_bark_text = text
	_bark_duration = maxf(1.5, duration_sec)
	_bark_timer = _bark_duration
	queue_redraw()
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func has_active_bark() -> bool:
	return _bark_timer > 0.05 and _bark_text != ""


func clear_world_bark() -> void:
	_bark_timer = 0.0
	_bark_text = ""
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func step_visuals(combat_delta: float, ui_delta: float, is_moving: bool) -> void:
	if _bark_timer > 0.0:
		_bark_timer = maxf(0.0, _bark_timer - ui_delta)
	if SaveManager.reduced_motion:
		_hit_flash_timer = 0.0
	elif _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - ui_delta)
	if _hit_flash_mat != null:
		_hit_flash_mat.set_shader_parameter("hit_flash", _compute_hit_flash_value())

	# 敌方战败倾倒与 1.15s 化瘴归墟消散（即使已脱离战斗亦以 ui_delta 走完消散，彻底清除站街死怪！）
	if not alive and faction == "enemy":
		is_targeted = false
		is_hovered = false
		is_occluded = false
		occlusion_silhouette_alpha = 0.0
		if _hit_flash_mat != null:
			_hit_flash_mat.set_shader_parameter("occlusion_alpha", 0.0)
		if _occlusion_silhouette != null:
			_occlusion_silhouette.visible = false
		_anim_state = "down"
		_anim_timer = 0.35
		_death_dissolve += ui_delta
		if _death_dissolve >= 1.15:
			if visible:
				visible = false
			return
		if _sprite != null:
			var rem_a: float = clampf(1.0 - (_death_dissolve / 1.15), 0.0, 1.0)
			_sprite.modulate = Color(0.54, 0.44, 0.62, rem_a)
			_apply_current_frame()
		queue_redraw()
		if _overlay_canvas != null:
			_overlay_canvas.queue_redraw()
		return

	_death_dissolve = 0.0
	if not visible:
		visible = true
	if not alive:
		if is_occluded or occlusion_silhouette_alpha > 0.0:
			is_occluded = false
			occlusion_silhouette_alpha = 0.0
		if _hit_flash_mat != null:
			_hit_flash_mat.set_shader_parameter("occlusion_alpha", 0.0)
		if _occlusion_silhouette != null and _occlusion_silhouette.visible:
			_occlusion_silhouette.visible = false

	# 关键帧与脉冲计时严格绑定 combat_delta（Space 凝时与顿帧期间 combat_delta == 0，100% 像素级定格！）
	if combat_delta > 0.0:
		_pulse_clock += combat_delta
		var next_state: String = "idle"
		if is_knocked_down():
			next_state = "down"
		elif _one_shot_remaining > 0.0:
			_one_shot_remaining = maxf(0.0, _one_shot_remaining - combat_delta)
			if _one_shot_remaining > 0.0:
				next_state = _one_shot_state
			elif is_casting:
				next_state = "cast_loop"
			elif is_moving:
				next_state = "run"
		elif is_casting:
			next_state = "cast_loop"
		elif is_moving:
			next_state = "run"

		if next_state != _anim_state:
			_anim_state = next_state
			_anim_timer = 0.0
		else:
			_anim_timer += combat_delta

	if _sprite != null:
		var target_alpha: float = stealth_alpha if alive else 0.72
		_sprite.modulate = Color(1.0, 1.0, 1.0, target_alpha)
		_apply_current_frame(combat_delta)

	queue_redraw()
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func _resolve_effective_lookup_key() -> String:
	if is_knocked_down():
		return "down"
	if _one_shot_remaining > 0.0 and _one_shot_state != "":
		return _one_shot_state
	if is_casting and _anim_state != "cast_release":
		return "cast_loop"
	var use_back: bool = facing_dir.y < -0.22
	if _anim_state == "idle":
		return "idle_ne" if use_back else "idle_se"
	if _anim_state == "run":
		return "run_ne" if use_back else "run_se"
	return _anim_state


func _apply_current_frame(step_dt: float = 0.0) -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var rows_dict: Dictionary = _sheet_meta.get("rows", {}) as Dictionary
	var lookup_key: String = _resolve_effective_lookup_key()

	var rinfo: Dictionary = rows_dict.get(lookup_key, {"row": 0, "frames": 4, "fps": 6.0, "loop": true}) as Dictionary
	var row_idx: int = int(rinfo.get("row", 0))
	var start_col: int = int(rinfo.get("start_col", 0))
	var frame_cnt: int = maxi(1, int(rinfo.get("frames", 4)))
	var fps: float = maxf(1.0, float(rinfo.get("fps", 6.0)))
	var loops: bool = bool(rinfo.get("loop", true))

	var raw_frame: int = int(floor(_anim_timer * fps))
	var col_offset: int = (raw_frame % frame_cnt) if loops else mini(frame_cnt - 1, raw_frame)
	var final_col: int = start_col + col_offset

	_sprite.region_rect = Rect2(float(final_col * _cell_w), float(row_idx * _cell_h), float(_cell_w), float(_cell_h))
	# 基础素材默认朝右下（+X）；交战竖向拉扯时启用轻回差防左右频闪，脱战保持即时响应
	var flip: bool = facing_dir.x < -0.08
	if NotifyHub.combat_active:
		flip = (facing_dir.x < 0.05) if _flipped_left else (facing_dir.x < -0.11)
	_flipped_left = flip
	_sprite.flip_h = flip

	var dir_n: Vector2 = facing_dir.normalized() if facing_dir.length_squared() > 0.001 else Vector2(0.894, 0.447)
	var target_root: Vector2 = Vector2.ZERO
	if SaveManager.reduced_motion or not alive or is_knocked_down():
		_visual_root_offset = Vector2.ZERO
	else:
		if lookup_key == "attack_1" or lookup_key == "attack_2":
			var lunge_t: float = sin(clampf(_anim_timer / 0.35, 0.0, 1.0) * PI)
			target_root = dir_n * lunge_t * (12.0 if is_boss else 5.0)
		elif lookup_key == "hit":
			target_root = -dir_n * 3.5
		if step_dt > 0.0:
			_visual_root_offset = _visual_root_offset.move_toward(target_root, step_dt * 84.0)
	_sprite.position = _visual_root_offset
	if _occlusion_silhouette != null:
		_occlusion_silhouette.region_rect = _sprite.region_rect
		_occlusion_silhouette.flip_h = flip
		_occlusion_silhouette.position = _visual_root_offset


func get_hit_rect_local() -> Rect2:
	var sc_x: float = absf(_sprite.scale.x) if _sprite != null else 1.0
	var sc_y: float = absf(_sprite.scale.y) if _sprite != null else 1.0
	var base_w: float = 524.0 if is_boss else maxf(104.0, float(_cell_w) * 0.58)
	var w: float = base_w * sc_x
	var top_h: float = float(_head_top_px) * sc_y + 18.0
	var bot_pad: float = (28.0 if is_boss else 16.0) * sc_y
	return Rect2(_visual_root_offset.x - w * 0.5, _visual_root_offset.y - top_h, w, top_h + bot_pad)


func contains_world_point(world_pt: Vector2) -> bool:
	return get_hit_rect_local().has_point(to_local(world_pt))


func get_vfx_origin_world(slot: String = "weapon") -> Vector2:
	var sc: Vector2 = _sprite.scale if _sprite != null else Vector2.ONE
	var sign_x: float = -1.0 if facing_dir.x < -0.08 else 1.0
	var lookup_key: String = _resolve_effective_lookup_key()
	var eff_slot: String = "mouth" if slot == "roar" else slot

	# 1. M2 per-animation-state anchor: {"state_anchors": {"attack_1": {"weapon": [78, -82]}}}
	var state_anchors_raw: Variant = _sheet_meta.get("state_anchors", null)
	if state_anchors_raw is Dictionary:
		var sa_dict: Dictionary = state_anchors_raw as Dictionary
		var st_entry_raw: Variant = sa_dict.get(lookup_key, null)
		if st_entry_raw is Dictionary:
			var st_d: Dictionary = st_entry_raw as Dictionary
			var raw_st: Variant = st_d.get(slot, st_d.get(eff_slot, null))
			var parsed_st: Vector2 = _parse_anchor_offset(raw_st, Vector2.INF)
			if parsed_st.is_finite():
				return global_position + _visual_root_offset + Vector2(parsed_st.x * sign_x * sc.x, parsed_st.y * sc.y)

	# 2. Actor-level anchor in *_sheet.json: {"anchors": {"weapon": [54, -76], "hand": [36, -88]}}
	var anchors_raw: Variant = _sheet_meta.get("anchors", null)
	if anchors_raw is Dictionary:
		var anc_d: Dictionary = anchors_raw as Dictionary
		var raw_a: Variant = anc_d.get(slot, anc_d.get(eff_slot, null))
		var parsed_a: Vector2 = _parse_anchor_offset(raw_a, Vector2.INF)
		if parsed_a.is_finite():
			return global_position + _visual_root_offset + Vector2(parsed_a.x * sign_x * sc.x, parsed_a.y * sc.y)

	# 3. Clean M1 proportional fallbacks relative to FeetOrigin (0, 0)
	var h: float = maxf(64.0, float(_head_top_px))
	var dir_n: Vector2 = facing_dir.normalized() if facing_dir.length_squared() > 0.001 else Vector2(0.894, 0.447)
	var local_off: Vector2 = Vector2.ZERO
	match slot:
		"feet", "ground":
			local_off = Vector2.ZERO
		"chest", "body", "center", "hit":
			local_off = Vector2(0.0, -h * 0.52 * sc.y)
		"head":
			local_off = Vector2(0.0, -h * 0.88 * sc.y)
		"overhead":
			local_off = Vector2(0.0, -h * sc.y - 14.0)
		"hand", "cast":
			local_off = Vector2(sign_x * h * 0.24 * sc.x, -h * 0.56 * sc.y) + dir_n * (8.0 * sc.x)
		"mouth", "roar":
			var reach_m: float = 92.0 if is_boss else 42.0
			local_off = Vector2(dir_n.x * reach_m * sc.x, -h * (0.56 if is_boss else 0.62) * sc.y + dir_n.y * 14.0 * sc.y)
		_:
			var reach_w: float = 78.0 if is_boss else (h * 0.32)
			local_off = Vector2(sign_x * reach_w * sc.x, -h * 0.50 * sc.y) + dir_n * (10.0 * sc.x)
	return global_position + _visual_root_offset + local_off


func _parse_anchor_offset(raw_val: Variant, fallback: Vector2) -> Vector2:
	if raw_val is Array:
		var arr: Array = raw_val as Array
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	elif raw_val is Dictionary:
		var d: Dictionary = raw_val as Dictionary
		if d.has("x") and d.has("y"):
			return Vector2(float(d["x"]), float(d["y"]))
	return fallback


func _draw() -> void:
	# 35° 斜向柔化水墨接地阴影（绘于父节点底层，绝不受 actor_hit_flash.gdshader 闪白污染！）
	var sh_alpha_mult: float = stealth_alpha
	if not alive and faction == "enemy":
		if _death_dissolve >= 1.15:
			return
		sh_alpha_mult = clampf(1.0 - (_death_dissolve / 1.15), 0.0, 1.0)

	var sc_s: float = _sprite.scale.x if _sprite != null else 1.0
	var lookup_s: String = _resolve_effective_lookup_key()
	var sh_rx: float = 34.0
	var sh_ry: float = 14.5
	if is_boss:
		sh_rx = 186.0
		sh_ry = 68.0
	elif sprite_id.begins_with("pet_") or sprite_id == "enemy_rot_wolf" or sprite_id == "enemy_wolf_pup":
		sh_rx = 44.0
		sh_ry = 17.0
	else:
		sh_rx = 42.0 if (lookup_s == "attack_1" or lookup_s == "attack_2" or lookup_s == "down") else 34.0
		sh_ry = sh_rx * 0.42
	sh_rx *= sc_s
	sh_ry *= sc_s

	var sh_center: Vector2 = Vector2(4.0, 2.0) + _visual_root_offset * 0.55
	_draw_filled_ellipse(sh_center, sh_rx * 1.12, sh_ry * 1.12, Color(0.05, 0.05, 0.05, 0.14 * sh_alpha_mult))
	_draw_filled_ellipse(sh_center, sh_rx * 0.86, sh_ry * 0.86, Color(0.05, 0.05, 0.05, 0.18 * sh_alpha_mult))
	_draw_filled_ellipse(sh_center, sh_rx * 0.58, sh_ry * 0.58, Color(0.04, 0.04, 0.04, 0.20 * sh_alpha_mult))

	# 死怪绝不残留锁定红圈！
	if not alive and faction == "enemy":
		return

	var ring_rx: float = 34.0 if not is_boss else 178.0
	var ring_ry: float = 15.0 if not is_boss else 70.0
	if is_controlled:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.35, 0.82, 0.65, 0.88), 3.0)
	elif is_box_selected:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.52, 0.78, 0.92, 0.85), 2.5)
	elif is_targeted and faction == "enemy":
		var pulse: float = 0.78 + 0.22 * sin(_pulse_clock * 6.0)
		_draw_ellipse(Vector2.ZERO, ring_rx + 4.0, ring_ry + 2.0, Color(0.86, 0.28, 0.22, pulse), 3.0)
	elif is_hovered:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.88, 0.74, 0.44, 0.65), 2.0)


func _get_current_overhead_top_px() -> float:
	var top_px: float = float(_head_top_px)
	var state_anchors_raw: Variant = _sheet_meta.get("state_anchors", null)
	if state_anchors_raw is Dictionary:
		var sa_dict: Dictionary = state_anchors_raw as Dictionary
		var st_raw: Variant = sa_dict.get(_resolve_effective_lookup_key(), null)
		if st_raw is Dictionary:
			var ov_vec: Vector2 = _parse_anchor_offset((st_raw as Dictionary).get("overhead", null), Vector2.INF)
			if ov_vec.is_finite():
				top_px = maxf(top_px, -ov_vec.y)
	return top_px


func _draw_overhead_ui() -> void:
	if _overlay_canvas == null:
		return

	# 战败妖物化瘴青紫墨烟升腾消散演出
	if not alive and faction == "enemy":
		if _death_dissolve > 0.0 and _death_dissolve < 1.15:
			var prog: float = _death_dissolve / 1.15
			var wisp_a: float = clampf((1.0 - prog) * 0.72, 0.0, 0.72)
			for wi: int in range(6):
				var seed_f: float = float(wi) * 1.37
				var wx: float = sin(seed_f * 2.3 + prog * 4.0) * (24.0 + float(wi) * 6.0)
				var wy: float = -18.0 - prog * (58.0 + float(wi) * 14.0)
				var wr: float = (12.0 + float(wi % 3) * 5.0) * (1.0 - prog * 0.45)
				_overlay_canvas.draw_circle(Vector2(wx, wy), wr, Color(0.26, 0.19, 0.32, wisp_a))
		return

	var font: Font = UIThemeBuilder.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font

	var sc_y: float = _sprite.scale.y if _sprite != null else 1.0
	var top_px_cur: float = _get_current_overhead_top_px()
	var head_y: float = -top_px_cur * sc_y - 10.0

	# 1. NPC 简化名牌与气泡
	if faction == "npc":
		if is_hovered and not InputRouter.alt_held and not Input.is_key_pressed(KEY_ALT) and InputRouter.current_mode == InputRouter.MODE_WORLD_COMBAT:
			var tw_npc: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x + 20.0
			var nrect: Rect2 = Rect2(-tw_npc * 0.5, head_y - 24.0, tw_npc, 24.0)
			_overlay_canvas.draw_rect(nrect, Color(0.11, 0.10, 0.09, 0.88), true)
			_overlay_canvas.draw_rect(nrect, UIThemeBuilder.COL_BRONZE_DIM, false, 1.5)
			_overlay_canvas.draw_string(font, Vector2(-tw_npc * 0.5 + 10.0, head_y - 6.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIThemeBuilder.COL_XUAN_WARM)
		_draw_bark_bubble(font, head_y - 28.0)
		return

	# 2. 战斗头顶姓名板（位于 _overlay_canvas 顶层，绝不被高大精英怪自身头肩遮挡！）
	var bar_w: float = 116.0 if not is_boss else 182.0
	var bar_h: float = 11.0 if not is_boss else 14.0
	var bx: float = -bar_w * 0.5
	var by: float = head_y

	if faction == "enemy":
		var has_cast_line: bool = (is_casting and cast_duration > 0.0) or lockout_timer > 0.0
		var stack_below_by: float = bar_h + (11.0 if ward_max > 0.0 else 0.0) + (20.0 if has_cast_line else 0.0)
		by = -top_px_cur * sc_y - stack_below_by - 8.0
		var seal_extra_w: float = 82.0 if (mother_seal_element != "" and mother_seal_timer > 0.0) else 8.0
		var vp_sz: Vector2 = get_viewport_rect().size
		if vp_sz.x > 200.0:
			var scr_o: Vector2 = get_global_transform_with_canvas().origin
			# 脱战态下若远端未交战敌人处于视口边缘或正被右上角小地图遮蔽（且未被悬停），直接隐去远端浮空名牌，彻底根除血条脱离本体数百像素悬在岩壁上！
			if not NotifyHub.combat_active and not is_hovered:
				if scr_o.x < 68.0 or scr_o.x > vp_sz.x - 68.0 or scr_o.y < 52.0 or scr_o.y > vp_sz.y - 42.0:
					return
				if scr_o.y + by - 26.0 < 268.0 and scr_o.x + bx + bar_w + seal_extra_w > vp_sz.x - 356.0:
					return
			if scr_o.y + by - 25.0 < 16.0:
				by = 16.0 + 25.0 - scr_o.y
			# 避让右上角小地图与菜单簇（横向微调上限 92px，超出则顺滑下沉至小地图底沿下方，绝不横向飞离模型！）
			if scr_o.y + by - 25.0 < 268.0 and scr_o.x + bx + bar_w + seal_extra_w > vp_sz.x - 356.0:
				var cand_bx: float = (vp_sz.x - 356.0) - scr_o.x - bar_w - seal_extra_w
				if cand_bx >= -bar_w * 0.5 - 92.0:
					bx = cand_bx
				else:
					by = 268.0 + 25.0 - scr_o.y
					bx = clampf(bx, 16.0 - scr_o.x, vp_sz.x - 16.0 - bar_w - seal_extra_w - scr_o.x)
			# 避让顶中首领铭牌（Rect2(vp_sz.x*0.5 - 322, 0, 644, 198)）
			var plaque_l: float = vp_sz.x * 0.5 - 322.0
			var plaque_r: float = vp_sz.x * 0.5 + 322.0
			if NotifyHub.combat_active and scr_o.y + by - 25.0 < 198.0:
				if scr_o.x + bx + bar_w + seal_extra_w > plaque_l and scr_o.x + bx - 6.0 < plaque_r:
					if scr_o.x >= vp_sz.x * 0.5 and (plaque_r + 8.0 + bar_w + seal_extra_w) <= vp_sz.x - 356.0:
						bx = plaque_r + 8.0 - scr_o.x
					elif scr_o.x < vp_sz.x * 0.5 and (plaque_l - 8.0 - bar_w - seal_extra_w) >= 16.0:
						bx = plaque_l - 8.0 - bar_w - seal_extra_w - scr_o.x
					else:
						by = 198.0 + 25.0 - scr_o.y

		var border_col: Color = UIThemeBuilder.COL_JADE_GREEN
		var border_w: float = 2.0
		if nameplate_threat_state == "amber_warn":
			border_col = Color("#E09A3B")
			border_w = 2.5
		elif nameplate_threat_state == "cinnabar_ot":
			var flash: float = 0.75 + 0.25 * sin(_pulse_clock * 9.0)
			border_col = Color(0.92, 0.26, 0.20, flash)
			border_w = 3.0

		# 名字黑底轻衬 + >=16px 文字，始终随 bx 居中对齐
		var name_w: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var name_x: float = bx + (bar_w - name_w) * 0.5
		_overlay_canvas.draw_rect(Rect2(name_x - 5.0, by - 23.0, name_w + 10.0, 19.0), Color(0.07, 0.07, 0.06, 0.76), true)
		_overlay_canvas.draw_string(font, Vector2(name_x, by - 7.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIThemeBuilder.COL_XUAN_WARM)

		# 气血条 + 杀意变色外框
		var hp_ratio: float = clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		_overlay_canvas.draw_rect(Rect2(bx - 2.0, by - 2.0, bar_w + 4.0, bar_h + 4.0), Color(0.08, 0.07, 0.07, 0.94), true)
		_overlay_canvas.draw_rect(Rect2(bx, by, bar_w * hp_ratio, bar_h), UIThemeBuilder.COL_CINNABAR_RED, true)
		_overlay_canvas.draw_rect(Rect2(bx - 2.0, by - 2.0, bar_w + 4.0, bar_h + 4.0), border_col, false, border_w)

		# 护体灵罡条（若拥有护罡）
		var next_y: float = by + bar_h + 5.0
		if ward_max > 0.0:
			var w_ratio: float = clampf(ward_current / ward_max, 0.0, 1.0)
			_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w, 7.0), Color(0.10, 0.12, 0.11, 0.90), true)
			if stagger_timer > 0.0:
				_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w, 7.0), Color(0.92, 0.72, 0.32, 0.85), true)
			else:
				_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w * w_ratio, 7.0), UIThemeBuilder.get_element_color(ward_element), true)
			_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w, 7.0), Color(0.45, 0.42, 0.36, 0.8), false, 1.0)
			next_y += 11.0

		# 吟唱读条（琥珀金 = 可打断，暗红锁链 = 不可常规打断）
		if is_casting and cast_duration > 0.0:
			var c_ratio: float = clampf(cast_progress / cast_duration, 0.0, 1.0)
			var c_col: Color = Color("#D6A85A") if cast_interruptible else Color("#8E2822")
			var c_border: Color = Color("#FCE29C") if cast_interruptible else Color("#D45A52")
			_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w, 16.0), Color(0.10, 0.09, 0.08, 0.94), true)
			_overlay_canvas.draw_rect(Rect2(bx + 1.0, next_y + 1.0, (bar_w - 2.0) * c_ratio, 14.0), c_col, true)
			_overlay_canvas.draw_rect(Rect2(bx, next_y, bar_w, 16.0), c_border, false, 1.8)
			var prefix: String = "[Q断] " if cast_interruptible else "[危] "
			_overlay_canvas.draw_string(font, Vector2(bx + 4.0, next_y + 13.0), prefix + cast_skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		elif lockout_timer > 0.0:
			_overlay_canvas.draw_string(font, Vector2(bx, next_y + 13.0), "【破功封脉 %.1fs】" % lockout_timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIThemeBuilder.COL_BRONZE_GOLD)

		# 右侧挂载 6 秒【五行母印】古篆大徽章
		if mother_seal_element != "" and mother_seal_timer > 0.0:
			var seal_pos: Vector2 = Vector2(bx + bar_w + 8.0, by - 10.0)
			var tex: Texture2D = _seal_textures.get(mother_seal_element, null) as Texture2D
			if tex != null:
				_overlay_canvas.draw_texture_rect(tex, Rect2(seal_pos, Vector2(34.0, 34.0)), false)
			else:
				_overlay_canvas.draw_rect(Rect2(seal_pos, Vector2(34.0, 34.0)), UIThemeBuilder.get_element_color(mother_seal_element), true)
			_overlay_canvas.draw_string(font, seal_pos + Vector2(36.0, 23.0), "%.1fs" % mother_seal_timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIThemeBuilder.get_element_color(mother_seal_element))
	else:
		# 我方小队/灵宠头顶精简血条与护盾条（战斗中或受伤时显示）
		if NotifyHub.combat_active or hp < max_hp or is_hovered:
			var ally_ratio: float = clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
			var a_w: float = 78.0
			var a_x: float = -a_w * 0.5
			_overlay_canvas.draw_rect(Rect2(a_x - 1.0, by - 1.0, a_w + 2.0, 9.0), Color(0.08, 0.08, 0.08, 0.88), true)
			_overlay_canvas.draw_rect(Rect2(a_x, by, a_w * ally_ratio, 7.0), Color("#499B6E") if alive else Color("#7A322C"), true)
			if shield > 0.5:
				var sh_ratio: float = clampf(shield / float(maxi(1, max_hp)), 0.0, 1.0)
				_overlay_canvas.draw_rect(Rect2(a_x, by - 4.0, a_w * sh_ratio, 3.0), Color("#8CE0D4"), true)
			if miasma_stacks > 0:
				_overlay_canvas.draw_string(font, Vector2(a_x, by - 6.0), "瘴×%d" % miasma_stacks, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#C978DF"))

	_draw_bark_bubble(font, by - 28.0)


func _draw_bark_bubble(font: Font, anchor_y: float) -> void:
	if _bark_timer <= 0.0 or _bark_text == "" or _overlay_canvas == null:
		return
	var bark_font: Font = font if font != null else UIThemeBuilder.get_regular_font()
	var fade: float = clampf(_bark_timer / 0.35, 0.0, 1.0)
	var max_content_w: float = 272.0
	var single_w: float = bark_font.get_string_size(_bark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var wrap_w: float = minf(max_content_w, maxf(116.0, single_w + 8.0))
	var cjk_brk: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	var msize: Vector2 = bark_font.get_multiline_string_size(_bark_text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, 16, -1, cjk_brk)
	var box_w: float = wrap_w + 26.0
	var box_h: float = maxf(36.0, msize.y + 18.0)
	var rect: Rect2 = Rect2(-box_w * 0.5, anchor_y - box_h - 8.0, box_w, box_h)

	# 视口左右、顶部与右上舆图 HUD 安全边界内推（防止边缘 NPC 气泡切边或撞上右上小地图！）
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x > 200.0:
		var scr_origin: Vector2 = get_global_transform_with_canvas().origin
		if scr_origin.x + rect.position.x < 18.0:
			rect.position.x = 18.0 - scr_origin.x
		elif scr_origin.x + rect.end.x > vp_size.x - 18.0:
			rect.position.x = (vp_size.x - 18.0) - scr_origin.x - box_w
		if scr_origin.y + rect.position.y < 16.0:
			rect.position.y = 16.0 - scr_origin.y
		if scr_origin.y + rect.position.y < 268.0 and scr_origin.x + rect.end.x > vp_size.x - 368.0:
			rect.position.x = (vp_size.x - 368.0) - scr_origin.x - box_w

	var tail_x: float = clampf(0.0, rect.position.x + 14.0, rect.end.x - 14.0)

	# 高对比不透光熟宣底衬 + 深墨阴影 + 双层乌铜描边 + 指向尾角（叠在浅色茅草屋檐上依然清亮锐利！）
	_overlay_canvas.draw_rect(Rect2(rect.position + Vector2(3.0, 4.0), rect.size), Color(0.04, 0.03, 0.03, 0.64 * fade), true)
	_overlay_canvas.draw_rect(rect, Color(0.97, 0.94, 0.87, 0.99 * fade), true)
	_overlay_canvas.draw_rect(rect, Color(0.26, 0.18, 0.11, 1.0 * fade), false, 2.2)
	_overlay_canvas.draw_rect(Rect2(rect.position + Vector2(3.0, 3.0), rect.size - Vector2(6.0, 6.0)), Color(0.68, 0.54, 0.34, 0.62 * fade), false, 1.0)
	var tail_pts: PackedVector2Array = PackedVector2Array([
		Vector2(tail_x - 7.5, rect.end.y - 1.0),
		Vector2(tail_x + 7.5, rect.end.y - 1.0),
		Vector2(tail_x * 0.4, rect.end.y + 8.0),
	])
	_overlay_canvas.draw_colored_polygon(tail_pts, Color(0.97, 0.94, 0.87, 0.99 * fade))
	_overlay_canvas.draw_line(tail_pts[0], tail_pts[2], Color(0.26, 0.18, 0.11, 1.0 * fade), 2.0)
	_overlay_canvas.draw_line(tail_pts[1], tail_pts[2], Color(0.26, 0.18, 0.11, 1.0 * fade), 2.0)
	_overlay_canvas.draw_multiline_string(
		bark_font,
		Vector2(rect.position.x + 13.0, rect.position.y + 22.0),
		_bark_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap_w,
		16,
		-1,
		Color(0.08, 0.06, 0.04, fade),
		cjk_brk
	)


func _draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 24
	for i: int in range(steps):
		var a: float = (TAU * float(i)) / float(steps)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 28
	for i: int in range(steps + 1):
		var a: float = (TAU * float(i)) / float(steps)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)
