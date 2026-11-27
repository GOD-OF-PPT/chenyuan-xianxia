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

## 走位与朝向
var facing_dir: Vector2 = Vector2(1.0, 0.5).normalized()
var move_waypoint: Vector2 = Vector2.ZERO
var has_move_waypoint: bool = false
var home_pos: Vector2 = Vector2.ZERO
var patrol_points: Array[Vector2] = []
var patrol_index: int = 0

## 关键帧图集元数据
var _sprite: Sprite2D
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

## Tier 1 头顶轻量宣纸气泡
var _bark_text: String = ""
var _bark_timer: float = 0.0
var _bark_duration: float = 3.5
var _pulse_clock: float = 0.0

static var _seal_textures: Dictionary = {}


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
	_death_dissolve = 0.0
	visible = true

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	if _overlay_canvas == null:
		_overlay_canvas = Node2D.new()
		_overlay_canvas.z_index = 6
		_overlay_canvas.draw.connect(_draw_overhead_ui)
		add_child(_overlay_canvas)

	_load_sprite_sheet(p_sprite_id)
	_sprite.scale = Vector2(p_scale_mult, p_scale_mult)
	_ensure_seal_icons()
	_apply_current_frame()
	queue_redraw()
	_overlay_canvas.queue_redraw()


func _load_sprite_sheet(sid: String) -> void:
	var png_path: String = "res://assets/sprites/%s_sheet.png" % sid
	var json_path: String = "res://assets/sprites/%s_sheet.json" % sid
	if ResourceLoader.exists(png_path):
		_sprite.texture = load(png_path) as Texture2D
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


static func _ensure_seal_icons() -> void:
	if not _seal_textures.is_empty():
		return
	for elem: String in ["metal", "wood", "water", "fire", "earth"]:
		var p: String = "res://assets/ui/icons/seal_%s.png" % elem
		if ResourceLoader.exists(p):
			_seal_textures[elem] = load(p) as Texture2D


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() > 0.001:
		facing_dir = dir.normalized()


func play_action_anim(anim_name: String, duration_sec: float = 0.42) -> void:
	_one_shot_state = anim_name
	_one_shot_remaining = duration_sec
	_anim_timer = 0.0
	_apply_current_frame()


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
	_pulse_clock += ui_delta
	if _bark_timer > 0.0:
		_bark_timer = maxf(0.0, _bark_timer - ui_delta)

	# 敌方战败倾倒与 1.15s 化瘴归墟消散（即使已脱离战斗亦以 ui_delta 走完消散，彻底清除站街死怪！）
	if not alive and faction == "enemy":
		is_targeted = false
		is_hovered = false
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

	# 关键帧计时严格绑定 combat_delta（Space 凝时期间 combat_delta == 0，动作完全定格！）
	if combat_delta > 0.0:
		if not alive or (stagger_timer > 0.0 and is_boss and stagger_timer > 4.0):
			_anim_state = "down"
			_anim_timer += combat_delta
		elif _one_shot_remaining > 0.0:
			_one_shot_remaining = maxf(0.0, _one_shot_remaining - combat_delta)
			_anim_state = _one_shot_state
			_anim_timer += combat_delta
		elif is_casting:
			_anim_state = "cast_loop"
			_anim_timer += combat_delta
		elif is_moving:
			_anim_state = "run"
			_anim_timer += combat_delta
		else:
			_anim_state = "idle"
			_anim_timer += combat_delta

	if _sprite != null:
		var target_alpha: float = stealth_alpha if alive else 0.72
		_sprite.modulate = Color(1.0, 1.0, 1.0, target_alpha)
		_apply_current_frame()

	queue_redraw()
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func _apply_current_frame() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var rows_dict: Dictionary = _sheet_meta.get("rows", {}) as Dictionary
	var use_back: bool = facing_dir.y < -0.22
	var lookup_key: String = _anim_state
	if _anim_state == "idle":
		lookup_key = "idle_ne" if use_back else "idle_se"
	elif _anim_state == "run":
		lookup_key = "run_ne" if use_back else "run_se"

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
	# 基础素材默认朝右下（+X）；朝左（facing_dir.x < -0.08）时水平镜像
	var flip: bool = facing_dir.x < -0.08
	_sprite.flip_h = flip


func get_hit_rect_local() -> Rect2:
	var sc: float = _sprite.scale.y if _sprite != null else 1.0
	var h: float = float(_head_top_px) * sc
	var w: float = (76.0 if not is_boss else 190.0) * sc
	return Rect2(-w * 0.5, -h, w, h)


func contains_world_point(world_pt: Vector2) -> bool:
	return get_hit_rect_local().has_point(to_local(world_pt))


func _draw() -> void:
	# 脚底选中/锁定奇门光圈（绘于父节点底层，自然处于角色双脚之下；死怪绝不残留锁定红圈！）
	if not alive and faction == "enemy":
		return

	var ring_rx: float = 34.0 if not is_boss else 84.0
	var ring_ry: float = 15.0 if not is_boss else 36.0
	if is_controlled:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.35, 0.82, 0.65, 0.88), 3.0)
	elif is_box_selected:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.52, 0.78, 0.92, 0.85), 2.5)
	elif is_targeted and faction == "enemy":
		var pulse: float = 0.78 + 0.22 * sin(_pulse_clock * 6.0)
		_draw_ellipse(Vector2.ZERO, ring_rx + 4.0, ring_ry + 2.0, Color(0.86, 0.28, 0.22, pulse), 3.0)
	elif is_hovered:
		_draw_ellipse(Vector2.ZERO, ring_rx, ring_ry, Color(0.88, 0.74, 0.44, 0.65), 2.0)


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
	var head_y: float = -float(_head_top_px) * sc_y - 10.0

	# 1. NPC 简化名牌与气泡
	if faction == "npc":
		if is_hovered or InputRouter.alt_held:
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
		var border_col: Color = UIThemeBuilder.COL_JADE_GREEN
		var border_w: float = 2.0
		if nameplate_threat_state == "amber_warn":
			border_col = Color("#E09A3B")
			border_w = 2.5
		elif nameplate_threat_state == "cinnabar_ot":
			var flash: float = 0.75 + 0.25 * sin(_pulse_clock * 9.0)
			border_col = Color(0.92, 0.26, 0.20, flash)
			border_w = 3.0

		# 名字黑底轻衬 + >=16px 文字，确保在任何亮暗背景下锐利可读
		var name_w: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var name_x: float = -name_w * 0.5
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
	var reg_font: Font = UIThemeBuilder.get_regular_font()
	if reg_font == null:
		reg_font = font
	var fade: float = clampf(minf(_bark_timer / 0.45, (_bark_duration - _bark_timer + 0.15) / 0.25), 0.0, 1.0)
	var max_content_w: float = 264.0
	var single_w: float = reg_font.get_string_size(_bark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var wrap_w: float = minf(max_content_w, maxf(112.0, single_w + 6.0))
	var cjk_brk: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
	var msize: Vector2 = reg_font.get_multiline_string_size(_bark_text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, 16, -1, cjk_brk)
	var box_w: float = wrap_w + 26.0
	var box_h: float = maxf(34.0, msize.y + 18.0)
	var rect: Rect2 = Rect2(-box_w * 0.5, anchor_y - box_h - 8.0, box_w, box_h)

	# 视口左右与顶部安全边界内推（防止靠近屏幕边缘的老樵夫等 NPC 气泡被切掉半截！）
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x > 200.0:
		var scr_origin: Vector2 = get_global_transform_with_canvas().origin
		if scr_origin.x + rect.position.x < 18.0:
			rect.position.x = 18.0 - scr_origin.x
		elif scr_origin.x + rect.end.x > vp_size.x - 18.0:
			rect.position.x = (vp_size.x - 18.0) - scr_origin.x - box_w
		if scr_origin.y + rect.position.y < 16.0:
			rect.position.y = 16.0 - scr_origin.y

	var tail_x: float = clampf(0.0, rect.position.x + 14.0, rect.end.x - 14.0)

	# 宣纸底衬阴影 + 框体 + 指向三角尾标
	_overlay_canvas.draw_rect(Rect2(rect.position + Vector2(2.0, 3.0), rect.size), Color(0.06, 0.05, 0.04, 0.42 * fade), true)
	_overlay_canvas.draw_rect(rect, Color(0.89, 0.85, 0.77, 0.96 * fade), true)
	_overlay_canvas.draw_rect(rect, Color(0.42, 0.32, 0.20, 0.96 * fade), false, 1.8)
	var tail_pts: PackedVector2Array = PackedVector2Array([
		Vector2(tail_x - 7.0, rect.end.y - 1.0),
		Vector2(tail_x + 7.0, rect.end.y - 1.0),
		Vector2(tail_x * 0.4, rect.end.y + 7.0),
	])
	_overlay_canvas.draw_colored_polygon(tail_pts, Color(0.89, 0.85, 0.77, 0.96 * fade))
	_overlay_canvas.draw_multiline_string(
		reg_font,
		Vector2(rect.position.x + 13.0, rect.position.y + 22.0),
		_bark_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap_w,
		16,
		-1,
		Color(0.14, 0.11, 0.09, fade),
		cjk_brk
	)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 28
	for i: int in range(steps + 1):
		var a: float = (TAU * float(i)) / float(steps)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)
