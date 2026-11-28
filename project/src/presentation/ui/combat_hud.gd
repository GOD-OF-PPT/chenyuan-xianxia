class_name CombatHud
extends Control
## 第三层 1920×1080 魔兽现代团本人体工学 HUD × 宋明雕花乌木错金器物界面
## 严格对齐 docs/design/21-ui-ux-spec.md 第 3.1 节与闸门 3 靶心样片 master_b_cangmu_rtwp.png：
## - 底部居中雕花乌木错金快捷栏 + 左右祥云卷草侧翼 + 顶部奇门阵图匾额：[1~4] | [Q E R G] | [5 6] | [特技] | [Z]，金色扇形日晷 GCD/CD 转圈！
## - 左下小队框体（F1→F2→F3 无跳号）：左侧镶金方框工笔半身头像 + 阵位职责徽标 + 朱砂【气血】/青瓷蓝【真元】+ 最多3枚状态图标 + 原生 Mouseover 悬停施法！
## - 灵宠迷你控制条（严守至多 1 只出战灵宠）：[姿态] [Ctrl+1] [Ctrl+2] 实时冷却
## - 顶部居中首领乌木金边匾额（23px 标题 + 朱砂气血 + ❖木灵护罡 + 20px 高对比琥珀金/暗红危招读条）
## - 全组件锁死 >=16px 思源宋体字号下限与 FOCUS_NONE（杜绝 Space 误触任何按钮）。

signal open_casket_requested(tab_id: String)
signal open_map_requested()
signal open_save_modal_requested()
signal open_settings_requested()


class RadialCooldownOverlay extends Control:
	var ratio: float = 0.0
	var is_gcd_sweep: bool = false
	var ready_flash: float = 0.0

	func set_sweep(new_ratio: float, gcd_only: bool) -> void:
		if is_nan(new_ratio) or is_inf(new_ratio):
			new_ratio = 0.0
		var clamped: float = clampf(new_ratio, 0.0, 1.0)
		if absf(clamped - ratio) > 0.002 or is_gcd_sweep != gcd_only:
			var was_active: bool = ratio > 0.02
			ratio = clamped
			is_gcd_sweep = gcd_only
			if was_active and clamped <= 0.005:
				trigger_ready_gleam()
			queue_redraw()

	func trigger_ready_gleam() -> void:
		if SaveManager.reduced_motion:
			ready_flash = 0.0
			return
		ready_flash = 1.0
		queue_redraw()

	func step_gleam(dt: float) -> void:
		if ready_flash > 0.0:
			ready_flash = maxf(0.0, ready_flash - dt * 5.2)
			queue_redraw()

	func _ray_rect_point(center: Vector2, half: Vector2, angle: float) -> Vector2:
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var tx: float = (half.x / absf(dir.x)) if absf(dir.x) > 0.0001 else 9999.0
		var ty: float = (half.y / absf(dir.y)) if absf(dir.y) > 0.0001 else 9999.0
		return center + dir * minf(tx, ty)

	func _draw() -> void:
		var sz: Vector2 = size
		if sz.x <= 2.0 or sz.y <= 2.0:
			return
		var center: Vector2 = sz * 0.5
		var half: Vector2 = sz * 0.5

		if ratio > 0.005:
			# 顺时针日晷扇形扫掠（自 12 点钟 -PI/2 起）
			var lead_ang: float = -PI * 0.5 + (1.0 - ratio) * TAU
			var end_ang: float = -PI * 0.5 + TAU
			var steps: int = maxi(6, int(ceil(ratio * 40.0)))

			var poly: PackedVector2Array = PackedVector2Array([center])
			var rim_pts: PackedVector2Array = PackedVector2Array()
			for i: int in range(steps + 1):
				var a: float = lerpf(lead_ang, end_ang, float(i) / float(steps))
				var pt: Vector2 = _ray_rect_point(center, half, a)
				poly.append(pt)
				rim_pts.append(pt)

			var shade_col: Color = Color(0.13, 0.09, 0.04, 0.56) if is_gcd_sweep else Color(0.07, 0.06, 0.05, 0.72)
			draw_colored_polygon(poly, shade_col)
			var gold_fan_col: Color = Color(0.90, 0.70, 0.28, 0.28 if is_gcd_sweep else 0.17)
			draw_colored_polygon(poly, gold_fan_col)

			if rim_pts.size() >= 2:
				draw_polyline(rim_pts, Color(0.92, 0.76, 0.42, 0.82), 1.8, true)

			var lead_pt: Vector2 = rim_pts[0]
			draw_line(center, lead_pt, Color(0.86, 0.66, 0.28, 0.52), 4.6, true)
			draw_line(center, lead_pt, UIThemeBuilder.COL_GILT_BRIGHT, 2.2, true)
			draw_circle(center, 2.6, UIThemeBuilder.COL_GILT_BRIGHT)

		if ready_flash > 0.01:
			draw_rect(Rect2(Vector2(1.0, 1.0), sz - Vector2(2.0, 2.0)), Color(0.99, 0.89, 0.56, ready_flash * 0.85), false, 2.4)


var combat_ctrl: RtwpCombatController = null

## 顶层首领框组件引用
var _boss_panel: PanelContainer
var _boss_title_lbl: Label
var _boss_hp_fill: ColorRect
var _boss_hp_lbl: Label
var _boss_ward_fill: ColorRect
var _boss_ward_lbl: Label
var _boss_cast_box: PanelContainer
var _boss_cast_sb: StyleBoxFlat
var _boss_cast_fill: ColorRect
var _boss_cast_lbl: Label
var _tracked_boss: BattleActor = null

var _pause_banner: PanelContainer
var _status_buff_lbl: Label

var _party_box: VBoxContainer
var _party_cards: Array[Dictionary] = []

var _bottom_cluster: Control
var _formation_plaque: Button
var _pet_bar: PanelContainer
var _pet_stance_btn: Button
var _pet_sk1_btn: Button
var _pet_sk2_btn: Button

var _quick_drawer: PanelContainer
var _drawer_vbox: VBoxContainer

var _slot_widgets: Dictionary = {}
var _attunement_wrap: PanelContainer
var _attunement_sb: StyleBoxFlat
var _attunement_fill: ColorRect
var _attunement_lbl: Label

var _top_right_zone_lbl: Label
var _stones_lbl: Label
var _minimap_canvas: Control
var _mm_roads: Array[PackedVector2Array] = []
var _mm_buildings: Array[Rect2] = []
var _mm_steles: Array[Vector2] = []
var _mm_portals: Array[Vector2] = []
var _mm_npcs: Array[BattleActor] = []

var _interact_prompt_box: PanelContainer
var _interact_prompt_lbl: Label

var _box_select_rect: Rect2 = Rect2()
var _is_box_selecting: bool = false
var _hud_hovered: bool = false
var _fade_alpha: float = 1.0
var _ui_pulse_clock: float = 0.0

var _tex_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIThemeBuilder.bind_full_rect(self)
	theme = UIThemeBuilder.get_global_theme()

	_build_top_boss_bar()
	_build_top_right_cluster()
	_build_tactical_pause_watermark()
	_build_party_frames()
	_build_bottom_action_bar()
	_build_interact_prompt()

	CampaignState.party_updated.connect(refresh_static_bindings)
	CampaignState.inventory_updated.connect(refresh_static_bindings)
	CampaignState.spirit_stones_changed.connect(func(_v: int) -> void: refresh_static_bindings())
	CampaignState.formation_changed.connect(func(_f: String) -> void: refresh_static_bindings())
	InputRouter.quick_drawer_toggled.connect(toggle_quick_drawer)


func bind_combat_controller(ctrl: RtwpCombatController) -> void:
	if combat_ctrl != ctrl:
		combat_ctrl = ctrl
		combat_ctrl.boss_combat_changed.connect(func(b: BattleActor) -> void:
			_tracked_boss = b
			_boss_panel.visible = (b != null and b.alive)
		)
		combat_ctrl.combat_hud_dirty.connect(refresh_static_bindings)
	refresh_static_bindings()


func set_minimap_zone_geometry(
	roads: Array[PackedVector2Array],
	buildings: Array[Rect2],
	steles: Array[Vector2],
	portals: Array[Vector2],
	npcs: Array[BattleActor]
) -> void:
	_mm_roads = roads
	_mm_buildings = buildings
	_mm_steles = steles
	_mm_portals = portals
	_mm_npcs = npcs
	if _minimap_canvas != null:
		_minimap_canvas.queue_redraw()


func set_box_selection_visual(active: bool, rect: Rect2) -> void:
	_is_box_selecting = active
	_box_select_rect = rect
	queue_redraw()


func set_interact_prompt(prompt_text: String, screen_anchor: Vector2 = Vector2(-1.0, -1.0), place_below: bool = false) -> void:
	if prompt_text == "":
		_interact_prompt_box.visible = false
		return
	_interact_prompt_lbl.text = "  " + prompt_text + "  "
	_interact_prompt_box.visible = true
	var vp_size: Vector2 = get_viewport_rect().size
	var box_w: float = maxf(230.0, _interact_prompt_box.get_combined_minimum_size().x)
	var box_h: float = 40.0
	if screen_anchor.x >= 0.0 and screen_anchor.y >= 0.0:
		var px: float = clampf(screen_anchor.x - box_w * 0.5, 24.0, maxf(24.0, vp_size.x - box_w - 24.0))
		var raw_py: float = (screen_anchor.y + 10.0) if place_below else (screen_anchor.y - box_h - 14.0)
		var py: float = clampf(raw_py, 28.0, maxf(28.0, vp_size.y - 210.0))
		_interact_prompt_box.anchor_left = 0.0
		_interact_prompt_box.anchor_right = 0.0
		_interact_prompt_box.offset_left = px
		_interact_prompt_box.offset_right = px + box_w
		_interact_prompt_box.offset_top = py
		_interact_prompt_box.offset_bottom = py + box_h
	else:
		_interact_prompt_box.anchor_left = 0.5
		_interact_prompt_box.anchor_right = 0.5
		_interact_prompt_box.offset_left = -box_w * 0.5
		_interact_prompt_box.offset_right = box_w * 0.5
		_interact_prompt_box.offset_top = 728.0
		_interact_prompt_box.offset_bottom = 768.0


func is_quick_drawer_open() -> bool:
	return _quick_drawer != null and _quick_drawer.visible


func toggle_quick_drawer() -> void:
	_quick_drawer.visible = not _quick_drawer.visible
	if _quick_drawer.visible:
		_rebuild_quick_drawer()


## ==================== 1. 顶部居中首领雕花乌木错金匾额 ====================
func _build_top_boss_bar() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -316.0
	_boss_panel.offset_right = 316.0
	_boss_panel.offset_top = 14.0
	_boss_panel.offset_bottom = 192.0
	_boss_panel.add_theme_stylebox_override(
		"panel",
		UIThemeBuilder.make_texture_or_ebony_box(
			"res://assets/ui/frames/hud_boss_plaque_bg.png",
			26, 18, 26, 22,
			UIThemeBuilder.COL_BOSS_EBONY,
			Color("#D6A244"),
			2, 6
		)
	)
	_boss_panel.visible = false
	add_child(_boss_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 5)
	_boss_panel.add_child(vb)

	_boss_title_lbl = Label.new()
	_boss_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_title_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	_boss_title_lbl.add_theme_font_size_override("font_size", 23)
	_boss_title_lbl.add_theme_color_override("font_color", Color("#F2E8D5"))
	_boss_title_lbl.add_theme_constant_override("outline_size", 3)
	_boss_title_lbl.add_theme_color_override("font_outline_color", Color("#0D0B0A"))
	vb.add_child(_boss_title_lbl)

	# 朱砂气血条 (#B03A2E)
	var hp_info: Dictionary = _make_framed_bar_row(580.0, 24.0, Color("#2B1311"), Color("#6E4B3A"), 1, 17, true)
	var hp_wrap: PanelContainer = hp_info["panel"] as PanelContainer
	_boss_hp_fill = hp_info["fill"] as ColorRect
	_boss_hp_fill.color = UIThemeBuilder.COL_HP_VERMILION
	_boss_hp_lbl = hp_info["label"] as Label
	vb.add_child(hp_wrap)

	# ❖木灵护体灵罡条 (#3E7B67)
	var ward_info: Dictionary = _make_framed_bar_row(580.0, 22.0, Color("#13221D"), Color("#4E6B5E"), 1, 16, true)
	var ward_wrap: PanelContainer = ward_info["panel"] as PanelContainer
	_boss_ward_fill = ward_info["fill"] as ColorRect
	_boss_ward_fill.color = UIThemeBuilder.COL_JADE_GREEN
	_boss_ward_lbl = ward_info["label"] as Label
	vb.add_child(ward_wrap)

	# 琥珀金 (#D6A244) 可打断 vs 暗红 (#8E2822) 锁链危招 30px 大读条
	var cast_info: Dictionary = _make_framed_bar_row(580.0, 30.0, Color("#261D10"), Color("#F5D580"), 2, 20, true)
	_boss_cast_box = cast_info["panel"] as PanelContainer
	_boss_cast_sb = cast_info["stylebox"] as StyleBoxFlat
	_boss_cast_fill = cast_info["fill"] as ColorRect
	_boss_cast_lbl = cast_info["label"] as Label
	_boss_cast_lbl.add_theme_color_override("font_color", Color("#FFF8EA"))
	_boss_cast_lbl.add_theme_constant_override("outline_size", 4)
	_boss_cast_lbl.add_theme_color_override("font_outline_color", Color("#16110C"))
	_boss_cast_box.visible = false
	vb.add_child(_boss_cast_box)


func _make_framed_bar_row(
	w: float,
	h: float,
	trough_col: Color,
	border_col: Color,
	border_w: int,
	font_sz: int,
	use_bold: bool
) -> Dictionary:
	var pnl: PanelContainer = PanelContainer.new()
	pnl.custom_minimum_size = Vector2(w, h)
	pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = trough_col
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = float(border_w)
	sb.content_margin_right = float(border_w)
	sb.content_margin_top = float(border_w)
	sb.content_margin_bottom = float(border_w)
	pnl.add_theme_stylebox_override("panel", sb)

	var inner: Control = Control.new()
	inner.custom_minimum_size = Vector2(w - float(border_w * 2), h - float(border_w * 2))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pnl.add_child(inner)

	var fill: ColorRect = ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = Vector2(w - float(border_w * 2), h - float(border_w * 2))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(fill)

	var lbl: Label = Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font() if use_bold else UIThemeBuilder.get_regular_font())
	lbl.add_theme_font_size_override("font_size", maxi(UIThemeBuilder.FS_MIN, font_sz))
	lbl.add_theme_color_override("font_color", Color("#FAF5EC"))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color("#090706"))
	inner.add_child(lbl)

	return {
		"panel": pnl,
		"stylebox": sb,
		"fill": fill,
		"label": lbl,
		"max_fill_w": w - float(border_w * 2),
	}


## ==================== 2. 右上淡墨舆图与功能簇 ====================
func _build_top_right_cluster() -> void:
	var tr_panel: PanelContainer = PanelContainer.new()
	tr_panel.anchor_left = 1.0
	tr_panel.anchor_right = 1.0
	tr_panel.offset_left = -352.0
	tr_panel.offset_right = -16.0
	tr_panel.offset_top = 14.0
	tr_panel.offset_bottom = 252.0
	tr_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.10, 0.09, 0.92), UIThemeBuilder.COL_BRONZE_DIM, 2, 6))
	add_child(tr_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	tr_panel.add_child(vb)

	_top_right_zone_lbl = Label.new()
	_top_right_zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_right_zone_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	_top_right_zone_lbl.add_theme_font_size_override("font_size", 17)
	_top_right_zone_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	vb.add_child(_top_right_zone_lbl)

	_minimap_canvas = Control.new()
	_minimap_canvas.custom_minimum_size = Vector2(316.0, 112.0)
	_minimap_canvas.draw.connect(_draw_minimap)
	vb.add_child(_minimap_canvas)

	_stones_lbl = Label.new()
	_stones_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stones_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	vb.add_child(_stones_lbl)

	var menu_row1: HBoxContainer = HBoxContainer.new()
	menu_row1.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row1.add_theme_constant_override("separation", 6)
	vb.add_child(menu_row1)

	for pair: Array in [["修行(C)", "cultivation"], ["道途(N)", "specialization"], ["剑匣(B)", "inventory"], ["手札(J)", "journal"]]:
		var b: Button = _make_compact_btn(str(pair[0]))
		var tab_key: String = str(pair[1])
		b.pressed.connect(func() -> void: open_casket_requested.emit(tab_key))
		menu_row1.add_child(b)

	var menu_row2: HBoxContainer = HBoxContainer.new()
	menu_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row2.add_theme_constant_override("separation", 10)
	vb.add_child(menu_row2)

	var map_btn: Button = _make_compact_btn("青岚舆图(M)")
	map_btn.pressed.connect(func() -> void: open_map_requested.emit())
	menu_row2.add_child(map_btn)

	var save_btn: Button = _make_compact_btn("留存道卷")
	save_btn.pressed.connect(func() -> void: open_save_modal_requested.emit())
	menu_row2.add_child(save_btn)

	var set_btn: Button = _make_compact_btn("器物设置")
	set_btn.pressed.connect(func() -> void: open_settings_requested.emit())
	menu_row2.add_child(set_btn)


func _make_compact_btn(label_txt: String) -> Button:
	var b: Button = Button.new()
	b.text = label_txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UIThemeBuilder.get_regular_font())
	b.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	var sb_n: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.16, 0.14, 0.12, 0.95), UIThemeBuilder.COL_BRONZE_DIM, 1, 4)
	sb_n.content_margin_left = 7.0
	sb_n.content_margin_right = 7.0
	sb_n.content_margin_top = 3.0
	sb_n.content_margin_bottom = 3.0
	var sb_h: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.22, 0.19, 0.15, 0.98), UIThemeBuilder.COL_BRONZE_GOLD, 1, 4)
	sb_h.content_margin_left = 7.0
	sb_h.content_margin_right = 7.0
	sb_h.content_margin_top = 3.0
	sb_h.content_margin_bottom = 3.0
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("focus", sb_n)
	return b


func _build_tactical_pause_watermark() -> void:
	_pause_banner = PanelContainer.new()
	_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_banner.anchor_left = 0.5
	_pause_banner.anchor_right = 0.5
	_pause_banner.offset_left = -360.0
	_pause_banner.offset_right = 360.0
	_pause_banner.offset_top = 644.0
	_pause_banner.offset_bottom = 688.0
	_pause_banner.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.08, 0.14, 0.16, 0.92), Color("#8CE0D4"), 2, 6))
	_pause_banner.visible = false
	add_child(_pause_banner)

	var p_lbl: Label = Label.new()
	p_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_lbl.text = tr("HUD_TACTICAL_PAUSE")
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	p_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
	p_lbl.add_theme_color_override("font_color", Color("#B9F2E6"))
	_pause_banner.add_child(p_lbl)

	_status_buff_lbl = Label.new()
	_status_buff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_buff_lbl.anchor_left = 0.5
	_status_buff_lbl.anchor_right = 0.5
	_status_buff_lbl.offset_left = -280.0
	_status_buff_lbl.offset_right = 280.0
	_status_buff_lbl.offset_top = 694.0
	_status_buff_lbl.offset_bottom = 722.0
	_status_buff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_buff_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	_status_buff_lbl.add_theme_color_override("font_color", Color("#98E2C6"))
	add_child(_status_buff_lbl)


## ==================== 3. 左下小队框体（F1→F2→F3 · 工笔头像 + 气血/真元 + Mouseover） ====================
func _build_party_frames() -> void:
	_party_box = VBoxContainer.new()
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_box.anchor_top = 1.0
	_party_box.anchor_bottom = 1.0
	_party_box.offset_left = 18.0
	_party_box.offset_right = 416.0
	_party_box.offset_top = -386.0
	_party_box.offset_bottom = -16.0
	_party_box.alignment = BoxContainer.ALIGNMENT_END
	_party_box.add_theme_constant_override("separation", 10)
	add_child(_party_box)

	var frame_tex: Texture2D = _load_tex("res://assets/ui/frames/hud_avatar_frame.png")

	for i: int in range(4):
		var slot_num: int = i + 1
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(398.0, 84.0)
		var card_hit_sb: StyleBoxFlat = StyleBoxFlat.new()
		card_hit_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		card_hit_sb.content_margin_left = 0.0
		card_hit_sb.content_margin_right = 0.0
		card_hit_sb.content_margin_top = 0.0
		card_hit_sb.content_margin_bottom = 0.0
		card.add_theme_stylebox_override("panel", card_hit_sb)
		_party_box.add_child(card)

		var row_hb: HBoxContainer = HBoxContainer.new()
		row_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_hb.add_theme_constant_override("separation", 8)
		card.add_child(row_hb)

		# 左侧 78x78 镶金乌木方框工笔半身头像
		var av_wrap: Control = Control.new()
		av_wrap.custom_minimum_size = Vector2(78.0, 78.0)
		av_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_hb.add_child(av_wrap)

		var av_bg: ColorRect = ColorRect.new()
		av_bg.position = Vector2(3.0, 3.0)
		av_bg.size = Vector2(72.0, 72.0)
		av_bg.color = Color("#2C2E24")
		av_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_wrap.add_child(av_bg)

		var av_tex: TextureRect = TextureRect.new()
		av_tex.position = Vector2(3.0, 3.0)
		av_tex.size = Vector2(72.0, 72.0)
		av_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_wrap.add_child(av_tex)

		var av_frame: TextureRect = TextureRect.new()
		av_frame.position = Vector2.ZERO
		av_frame.size = Vector2(78.0, 78.0)
		av_frame.texture = frame_tex
		av_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_frame.stretch_mode = TextureRect.STRETCH_SCALE
		av_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_wrap.add_child(av_frame)

		# 右侧 312px 名牌横幅 + 朱砂气血 + 青瓷蓝真元
		var rvb: VBoxContainer = VBoxContainer.new()
		rvb.custom_minimum_size = Vector2(312.0, 80.0)
		rvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_theme_constant_override("separation", 3)
		row_hb.add_child(rvb)

		var banner_pnl: PanelContainer = PanelContainer.new()
		banner_pnl.custom_minimum_size = Vector2(312.0, 28.0)
		banner_pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var banner_sb: StyleBoxFlat = StyleBoxFlat.new()
		banner_sb.bg_color = Color(0.11, 0.10, 0.09, 0.93)
		banner_sb.border_color = Color("#7D6339")
		banner_sb.set_border_width_all(1)
		banner_sb.set_corner_radius_all(3)
		banner_sb.content_margin_left = 6.0
		banner_sb.content_margin_right = 4.0
		banner_sb.content_margin_top = 1.0
		banner_sb.content_margin_bottom = 1.0
		banner_pnl.add_theme_stylebox_override("panel", banner_sb)
		rvb.add_child(banner_pnl)

		var top_hb: HBoxContainer = HBoxContainer.new()
		top_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_hb.add_theme_constant_override("separation", 4)
		banner_pnl.add_child(top_hb)

		var name_l: Label = Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
		name_l.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
		name_l.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
		top_hb.add_child(name_l)

		var buff_hb: HBoxContainer = HBoxContainer.new()
		buff_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buff_hb.alignment = BoxContainer.ALIGNMENT_END
		buff_hb.add_theme_constant_override("separation", 2)
		top_hb.add_child(buff_hb)

		var buff_badges: Array[Dictionary] = []
		for _b_i: int in range(3):
			var bp: PanelContainer = PanelContainer.new()
			bp.custom_minimum_size = Vector2(20.0, 20.0)
			bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bp.visible = false
			var bsb: StyleBoxFlat = StyleBoxFlat.new()
			bsb.bg_color = Color(0.10, 0.09, 0.08, 0.94)
			bsb.border_color = UIThemeBuilder.COL_BRONZE_GOLD
			bsb.set_border_width_all(1)
			bsb.set_corner_radius_all(2)
			bsb.content_margin_left = 1.0
			bsb.content_margin_right = 1.0
			bsb.content_margin_top = 1.0
			bsb.content_margin_bottom = 1.0
			bp.add_theme_stylebox_override("panel", bsb)
			var b_ico: TextureRect = TextureRect.new()
			b_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			b_ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bp.add_child(b_ico)
			buff_hb.add_child(bp)
			buff_badges.append({"panel": bp, "sb": bsb, "icon": b_ico})

		var ai_btn: Button = _make_compact_btn("AI")
		top_hb.add_child(ai_btn)

		var hp_info_p: Dictionary = _make_framed_bar_row(312.0, 22.0, Color("#261210"), Color("#6A4838"), 1, 16, true)
		var hp_fill: ColorRect = hp_info_p["fill"] as ColorRect
		hp_fill.color = Color("#9E3429")
		var hp_l: Label = hp_info_p["label"] as Label
		rvb.add_child(hp_info_p["panel"] as PanelContainer)

		var mp_info_p: Dictionary = _make_framed_bar_row(312.0, 20.0, Color("#0F1B26"), Color("#3E5A6E"), 1, 16, true)
		var mp_fill: ColorRect = mp_info_p["fill"] as ColorRect
		mp_fill.color = Color("#2F6980")
		var mp_l: Label = mp_info_p["label"] as Label
		rvb.add_child(mp_info_p["panel"] as PanelContainer)

		var card_info: Dictionary = {
			"slot_num": slot_num,
			"formation_slot": slot_num,
			"char_id": "",
			"card": card,
			"avatar_tex": av_tex,
			"avatar_frame": av_frame,
			"banner_sb": banner_sb,
			"name_lbl": name_l,
			"buff_badges": buff_badges,
			"ai_btn": ai_btn,
			"hp_fill": hp_fill,
			"hp_max_w": float(hp_info_p["max_fill_w"]),
			"hp_lbl": hp_l,
			"mp_fill": mp_fill,
			"mp_max_w": float(mp_info_p["max_fill_w"]),
			"mp_lbl": mp_l,
		}
		_party_cards.append(card_info)

		# Hardened Mouseover Cast (card + ai_btn share global_rect guard so hovering AI pill never drops hovered_ally_id!)
		var on_enter: Callable = func() -> void:
			_hud_hovered = true
			if combat_ctrl != null:
				combat_ctrl.hovered_ally_id = str(card_info.get("char_id", ""))
		var on_exit: Callable = func() -> void:
			if is_instance_valid(card) and card.visible and card.get_global_rect().has_point(card.get_global_mouse_position()):
				return
			_hud_hovered = false
			if combat_ctrl != null and combat_ctrl.hovered_ally_id == str(card_info.get("char_id", "")):
				combat_ctrl.hovered_ally_id = ""

		card.mouse_entered.connect(on_enter)
		card.mouse_exited.connect(on_exit)
		ai_btn.mouse_entered.connect(on_enter)
		ai_btn.mouse_exited.connect(on_exit)

		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and combat_ctrl != null:
					combat_ctrl.switch_controlled_party_slot(slot_num, false)
		)
		ai_btn.pressed.connect(func() -> void:
			var cid_a: String = str(card_info.get("char_id", ""))
			if cid_a != "" and CampaignState.party_members.has(cid_a):
				var m: Dictionary = CampaignState.party_members[cid_a] as Dictionary
				var cdef: Dictionary = DataDB.get_character(cid_a)
				var presets: Array = cdef.get("ai_presets", []) as Array
				if not presets.is_empty():
					m["ai_preset_index"] = (int(m.get("ai_preset_index", 0)) + 1) % presets.size()
					refresh_static_bindings()
		)


## ==================== 4. 底部居中雕花乌木错金快捷栏 + 祥云侧翼 + 奇门匾额 ====================
func _build_bottom_action_bar() -> void:
	_bottom_cluster = Control.new()
	_bottom_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_cluster.anchor_left = 0.5
	_bottom_cluster.anchor_right = 0.5
	_bottom_cluster.anchor_top = 1.0
	_bottom_cluster.anchor_bottom = 1.0
	_bottom_cluster.offset_left = -540.0
	_bottom_cluster.offset_right = 540.0
	_bottom_cluster.offset_top = -172.0
	_bottom_cluster.offset_bottom = 0.0
	add_child(_bottom_cluster)

	# 左肩上层迷你灵宠控制条（严守至多 1 只出战灵宠，screen x=436..900, y=882..916，与奇门匾额及 Z 抽屉 100% 零重叠！）
	_pet_bar = PanelContainer.new()
	_pet_bar.position = Vector2(16.0, -26.0)
	var pet_sb: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 4)
	pet_sb.content_margin_left = 4.0
	pet_sb.content_margin_right = 4.0
	pet_sb.content_margin_top = 2.0
	pet_sb.content_margin_bottom = 2.0
	_pet_bar.add_theme_stylebox_override("panel", pet_sb)
	_pet_bar.visible = false
	_bottom_cluster.add_child(_pet_bar)

	var pet_hb: HBoxContainer = HBoxContainer.new()
	pet_hb.add_theme_constant_override("separation", 4)
	_pet_bar.add_child(pet_hb)

	_pet_stance_btn = _make_compact_btn("灵宠:协助")
	_pet_stance_btn.pressed.connect(func() -> void:
		var order: Array[String] = ["assist", "follow", "hold"]
		var cur_i: int = order.find(CampaignState.pet_stance)
		CampaignState.pet_stance = order[(cur_i + 1) % order.size()]
		refresh_static_bindings()
	)
	pet_hb.add_child(_pet_stance_btn)

	_pet_sk1_btn = _make_compact_btn("Ctrl+1")
	_pet_sk1_btn.pressed.connect(func() -> void:
		if combat_ctrl != null:
			combat_ctrl.trigger_pet_manual_skill(1)
	)
	pet_hb.add_child(_pet_sk1_btn)

	_pet_sk2_btn = _make_compact_btn("Ctrl+2")
	_pet_sk2_btn.pressed.connect(func() -> void:
		if combat_ctrl != null:
			combat_ctrl.trigger_pet_manual_skill(2)
	)
	pet_hb.add_child(_pet_sk2_btn)

	# 右肩同调气机青莲槽（screen x=1152..1452, y=930..958）
	var att_info: Dictionary = _make_framed_bar_row(300.0, 28.0, Color(0.08, 0.14, 0.12, 0.95), UIThemeBuilder.COL_BRONZE_DIM, 1, 16, false)
	_attunement_wrap = att_info["panel"] as PanelContainer
	_attunement_sb = att_info["stylebox"] as StyleBoxFlat
	_attunement_fill = att_info["fill"] as ColorRect
	_attunement_fill.color = UIThemeBuilder.COL_JADE_GREEN
	_attunement_lbl = att_info["label"] as Label
	_attunement_wrap.position = Vector2(732.0, 22.0)
	_attunement_wrap.visible = false
	_bottom_cluster.add_child(_attunement_wrap)

	# 主雕花乌木错金底座 + 左右祥云卷草侧翼（全12槽位总宽 <= 980px，居中于 x=470..1450，距左下小队框 >=54px！）
	var bar_center: CenterContainer = CenterContainer.new()
	bar_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_center.position = Vector2(0.0, 54.0)
	bar_center.custom_minimum_size = Vector2(1080.0, 108.0)
	_bottom_cluster.add_child(bar_center)

	var pedestal_hb: HBoxContainer = HBoxContainer.new()
	pedestal_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedestal_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	pedestal_hb.add_theme_constant_override("separation", 0)
	bar_center.add_child(pedestal_hb)

	var wing_l_wrap: Control = Control.new()
	wing_l_wrap.custom_minimum_size = Vector2(106.0, 106.0)
	wing_l_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wing_l_tex: TextureRect = TextureRect.new()
	wing_l_tex.position = Vector2(0.0, 48.0)
	wing_l_tex.size = Vector2(106.0, 56.0)
	wing_l_tex.texture = _load_tex("res://assets/ui/frames/hud_bar_wing_l.png")
	wing_l_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wing_l_tex.stretch_mode = TextureRect.STRETCH_SCALE
	wing_l_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wing_l_wrap.add_child(wing_l_tex)
	pedestal_hb.add_child(wing_l_wrap)

	var main_bar: PanelContainer = PanelContainer.new()
	main_bar.custom_minimum_size = Vector2(0.0, 106.0)
	var main_sb: StyleBox = UIThemeBuilder.make_texture_or_ebony_box(
		"res://assets/ui/frames/hud_action_bar_bg.png",
		16, 12, 16, 10,
		UIThemeBuilder.COL_CARVED_EBONY,
		Color("#C8A055"),
		2, 6
	)
	main_bar.add_theme_stylebox_override("panel", main_sb)
	main_bar.mouse_entered.connect(func() -> void: _hud_hovered = true)
	main_bar.mouse_exited.connect(func() -> void: _hud_hovered = false)
	pedestal_hb.add_child(main_bar)

	var wing_r_wrap: Control = Control.new()
	wing_r_wrap.custom_minimum_size = Vector2(106.0, 106.0)
	wing_r_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wing_r_tex: TextureRect = TextureRect.new()
	wing_r_tex.position = Vector2(0.0, 48.0)
	wing_r_tex.size = Vector2(106.0, 56.0)
	wing_r_tex.texture = _load_tex("res://assets/ui/frames/hud_bar_wing_r.png")
	wing_r_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wing_r_tex.stretch_mode = TextureRect.STRETCH_SCALE
	wing_r_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wing_r_wrap.add_child(wing_r_tex)
	pedestal_hb.add_child(wing_r_wrap)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 3)
	main_bar.add_child(hb)

	var slot_order: Array[String] = ["1", "2", "3", "4", "Q", "E", "R", "G", "5", "6", "STUNT", "Z"]
	for code: String in slot_order:
		if code == "Q" or code == "5" or code == "STUNT":
			hb.add_child(_make_bar_group_divider())
		var tile: PanelContainer = _create_action_tile(code)
		hb.add_child(tile)

	# 顶部正中凸起奇门常驻阵图匾额（对标 master_b `地载阵 · 调息流转`，screen x=814..1106, y=924..962）
	_formation_plaque = Button.new()
	_formation_plaque.focus_mode = Control.FOCUS_NONE
	_formation_plaque.z_index = 2
	_formation_plaque.position = Vector2(394.0, 16.0)
	_formation_plaque.size = Vector2(292.0, 38.0)
	_formation_plaque.custom_minimum_size = Vector2(292.0, 38.0)
	_formation_plaque.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	_formation_plaque.add_theme_font_size_override("font_size", 17)
	_formation_plaque.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
	_formation_plaque.add_theme_color_override("font_hover_color", UIThemeBuilder.COL_GILT_BRIGHT)
	var fp_sb: StyleBox = UIThemeBuilder.make_texture_or_ebony_box(
		"res://assets/ui/frames/hud_formation_plaque.png",
		24, 5, 24, 5,
		Color("#24201B"),
		Color("#C8A055"),
		2, 5
	)
	_formation_plaque.add_theme_stylebox_override("normal", fp_sb)
	_formation_plaque.add_theme_stylebox_override("hover", fp_sb)
	_formation_plaque.add_theme_stylebox_override("pressed", fp_sb)
	_formation_plaque.add_theme_stylebox_override("focus", fp_sb)
	_formation_plaque.pressed.connect(toggle_quick_drawer)
	_bottom_cluster.add_child(_formation_plaque)

	# Z 键奇门变阵小抽屉（screen x=918..1174, y=774..918，避开左肩灵宠条与上方凝时横幅）
	_quick_drawer = PanelContainer.new()
	_quick_drawer.z_index = 4
	_quick_drawer.position = Vector2(498.0, -134.0)
	_quick_drawer.custom_minimum_size = Vector2(256.0, 140.0)
	_quick_drawer.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.97), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_quick_drawer.visible = false
	_bottom_cluster.add_child(_quick_drawer)

	_drawer_vbox = VBoxContainer.new()
	_drawer_vbox.add_theme_constant_override("separation", 6)
	_quick_drawer.add_child(_drawer_vbox)


func _make_bar_group_divider() -> Control:
	var wrap: Control = Control.new()
	wrap.custom_minimum_size = Vector2(6.0, 82.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_r: ColorRect = ColorRect.new()
	line_r.position = Vector2(2.0, 10.0)
	line_r.size = Vector2(2.0, 62.0)
	line_r.color = Color(0.56, 0.44, 0.25, 0.72)
	line_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line_r)
	return wrap


func _create_action_tile(slot_code: String) -> PanelContainer:
	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(56.0, 82.0)
	var sb: StyleBox = UIThemeBuilder.make_texture_or_ebony_box(
		"res://assets/ui/frames/hud_slot_frame.png",
		6, 6, 6, 4,
		Color(0.14, 0.12, 0.11, 0.96),
		UIThemeBuilder.COL_BRONZE_DIM,
		2, 5
	)
	tile.add_theme_stylebox_override("panel", sb)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	tile.add_child(vb)

	var icon_wrap: Control = Control.new()
	icon_wrap.custom_minimum_size = Vector2(44.0, 46.0)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon_wrap)

	var well_bg: ColorRect = ColorRect.new()
	well_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well_bg.color = Color("#141917")
	well_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(well_bg)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(icon_rect)

	var cd_radial: RadialCooldownOverlay = RadialCooldownOverlay.new()
	cd_radial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(cd_radial)

	var glow_rim: Panel = Panel.new()
	glow_rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_sb: StyleBoxFlat = StyleBoxFlat.new()
	rim_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	rim_sb.border_color = UIThemeBuilder.COL_BRONZE_DIM
	rim_sb.set_border_width_all(1)
	rim_sb.set_corner_radius_all(2)
	glow_rim.add_theme_stylebox_override("panel", rim_sb)
	icon_wrap.add_child(glow_rim)

	var cd_lbl: Label = Label.new()
	cd_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	cd_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	cd_lbl.add_theme_color_override("font_color", Color("#FCE49C"))
	cd_lbl.add_theme_constant_override("outline_size", 3)
	cd_lbl.add_theme_color_override("font_outline_color", Color("#120E0B"))
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(cd_lbl)

	var key_lbl: Label = Label.new()
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	key_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	key_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
	key_lbl.add_theme_constant_override("outline_size", 2)
	key_lbl.add_theme_color_override("font_outline_color", Color("#120E0B"))
	key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(key_lbl)

	tile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if slot_code == "Z":
					toggle_quick_drawer()
				elif combat_ctrl != null:
					combat_ctrl.trigger_hotkey_slot(slot_code)
	)

	_slot_widgets[slot_code] = {
		"tile": tile,
		"rim_sb": rim_sb,
		"icon": icon_rect,
		"cd_radial": cd_radial,
		"cd_lbl": cd_lbl,
		"key_lbl": key_lbl,
		"skill_id": "",
	}
	return tile


func _build_interact_prompt() -> void:
	_interact_prompt_box = PanelContainer.new()
	_interact_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_prompt_box.anchor_left = 0.5
	_interact_prompt_box.anchor_right = 0.5
	_interact_prompt_box.offset_left = -240.0
	_interact_prompt_box.offset_right = 240.0
	_interact_prompt_box.offset_top = 728.0
	_interact_prompt_box.offset_bottom = 768.0
	_interact_prompt_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.90), UIThemeBuilder.COL_BRONZE_GOLD, 2, 5))
	_interact_prompt_box.visible = false
	add_child(_interact_prompt_box)

	_interact_prompt_lbl = Label.new()
	_interact_prompt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interact_prompt_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
	_interact_prompt_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
	_interact_prompt_box.add_child(_interact_prompt_lbl)


func _rebuild_quick_drawer() -> void:
	for ch: Node in _drawer_vbox.get_children():
		ch.queue_free()
	var title: Label = Label.new()
	title.text = "奇门常驻阵图（Z）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	_drawer_vbox.add_child(title)

	for fid: String in CampaignState.unlocked_formations:
		var fdef: Dictionary = DataDB.get_formation(fid)
		var fname: String = DataDB.loc(str(fdef.get("name_key", fid)))
		var b: Button = _make_compact_btn(("★ " if fid == CampaignState.active_formation_id else "  ") + fname)
		b.pressed.connect(func() -> void:
			if combat_ctrl != null:
				combat_ctrl.try_switch_formation(fid)
			_quick_drawer.visible = false
			refresh_static_bindings()
		)
		_drawer_vbox.add_child(b)


func _get_formation_plaque_text(fid: String, fname: String) -> String:
	var motto: String = "随心流转"
	match fid:
		"dizai":
			motto = "调息流转"
		"tianfu":
			motto = "剑气凌霄"
		"fengyang":
			motto = "疾风掠影"
		"huyi":
			motto = "破罡裂阵"
		_:
			motto = "随心流转"
	if combat_ctrl != null and combat_ctrl.formation_switch_cd > 0.05:
		return "%s · %s (%.0fs)" % [fname, motto, combat_ctrl.formation_switch_cd]
	return "%s · %s" % [fname, motto]


func refresh_static_bindings() -> void:
	_top_right_zone_lbl.text = tr("ZONE_NAME_" + CampaignState.current_zone_id.to_upper())
	var fid: String = CampaignState.active_formation_id
	var fdef: Dictionary = DataDB.get_formation(fid)
	var fname: String = DataDB.loc(str(fdef.get("name_key", fid)))
	_stones_lbl.text = "◆ %s: %d  |  %s" % [tr("TERM_SPIRIT_STONE"), CampaignState.spirit_stones, fname]
	if _formation_plaque != null:
		_formation_plaque.text = _get_formation_plaque_text(fid, fname)

	if combat_ctrl == null:
		return

	# 1. 更新左下 F1→F2→F3 无跳号连续小队框与工笔头像
	var occupied_slots: Array[int] = combat_ctrl.get_occupied_formation_slots()
	if not occupied_slots.is_empty() and not occupied_slots.has(CampaignState.controlled_slot):
		CampaignState.controlled_slot = occupied_slots[0]
	for card_idx: int in range(4):
		var cinfo: Dictionary = _party_cards[card_idx]
		var card: PanelContainer = cinfo["card"] as PanelContainer
		if card_idx >= occupied_slots.size():
			card.visible = false
			cinfo["char_id"] = ""
			continue

		var f_slot: int = occupied_slots[card_idx]
		var cid: String = CampaignState.formation_slots[f_slot - 1]
		if cid == "" or not combat_ctrl.party_actors.has(cid):
			card.visible = false
			cinfo["char_id"] = ""
			continue

		card.visible = true
		cinfo["char_id"] = cid
		cinfo["formation_slot"] = f_slot

		var cdef: Dictionary = DataDB.get_character(cid)
		var m: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var smod: Dictionary = FormationRules.get_slot_modifiers(fdef, f_slot)
		var cname: String = DataDB.loc(str(cdef.get("name_key", cid)))
		var is_ctrl: bool = (CampaignState.controlled_slot == f_slot)
		var display_f_num: int = card_idx + 1
		var role_str: String = str(smod.get("role_title", ""))
		(cinfo["name_lbl"] as Label).text = "%sF%d %s · %s" % ["▶" if is_ctrl else "", display_f_num, cname, role_str]

		var portrait_id: String = str(cdef.get("portrait_id", cid))
		var av_path: String = "res://assets/ui/icons/avatar_%s.png" % portrait_id
		var av_tex_r: TextureRect = cinfo["avatar_tex"] as TextureRect
		av_tex_r.texture = _load_avatar_or_fallback(av_path, portrait_id)

		var presets: Array = cdef.get("ai_presets", []) as Array
		var pidx: int = int(m.get("ai_preset_index", 0))
		if pidx < presets.size() and presets[pidx] is Dictionary:
			(cinfo["ai_btn"] as Button).text = DataDB.loc(str((presets[pidx] as Dictionary).get("name_key", "AI")))

	# 2. 更新灵宠迷你控制条（严守至多 1 只出战灵宠）
	if CampaignState.active_pet_id != "":
		_pet_bar.visible = true
		var pdef: Dictionary = DataDB.get_pet(CampaignState.active_pet_id)
		var stance_cn: String = "协助" if CampaignState.pet_stance == "assist" else ("跟随" if CampaignState.pet_stance == "follow" else "坚守")
		_pet_stance_btn.text = "%s:%s" % [DataDB.loc(str(pdef.get("name_key", ""))), stance_cn]
		_pet_sk1_btn.text = "Ctrl+1 " + DataDB.loc(str(DataDB.get_skill(str(pdef.get("skill_1", ""))).get("name_key", "")))
		_pet_sk2_btn.text = "Ctrl+2 " + DataDB.loc(str(DataDB.get_skill(str(pdef.get("skill_2", ""))).get("name_key", "")))
	else:
		_pet_bar.visible = false

	# 3. 更新主控角色快捷栏图标与标准键位说明（1~4 | Q E R G | 5 6 | 特技 | Z）
	var ctrl_id: String = combat_ctrl.get_controlled_char_id()
	var bar: Dictionary = CampaignState.get_member_active_skills(ctrl_id)

	for code_var: Variant in _slot_widgets.keys():
		var code: String = str(code_var)
		var w: Dictionary = _slot_widgets[code] as Dictionary
		var tile: PanelContainer = w["tile"] as PanelContainer
		var icon_r: TextureRect = w["icon"] as TextureRect
		var key_l: Label = w["key_lbl"] as Label

		if code == "Z":
			w["skill_id"] = "Z"
			key_l.text = "Z"
			icon_r.texture = _load_tex("res://assets/ui/icons/seal_earth.png")
			tile.tooltip_text = "切换奇门常驻阵图（%s）" % fname
			continue
		elif code == "5" or code == "6":
			var pid: String = CampaignState.quick_pill_5_id if code == "5" else CampaignState.quick_pill_6_id
			var idef: Dictionary = DataDB.get_any_item_or_equip(pid)
			var cnt: int = CampaignState.get_item_count(pid)
			w["skill_id"] = pid
			key_l.text = "%s(%d)" % [code, cnt]
			icon_r.texture = _load_tex(str(idef.get("icon", "res://assets/ui/icons/pill_huichun.png")))
			tile.tooltip_text = "%s\n%s" % [DataDB.loc(str(idef.get("name_key", pid))), DataDB.loc(str(idef.get("desc_key", "")))]
			continue
		elif code == "G":
			var has_g: bool = CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword")
			tile.visible = has_g
			if has_g:
				var gsdef: Dictionary = DataDB.get_skill("ult_qinglian_sword")
				w["skill_id"] = "ult_qinglian_sword"
				key_l.text = "G"
				icon_r.texture = _load_tex(str(gsdef.get("icon", "")))
				tile.tooltip_text = "%s\n%s" % [DataDB.loc(str(gsdef.get("name_key", ""))), DataDB.loc(str(gsdef.get("desc_key", "")))]
			continue
		elif code == "STUNT":
			var stunt_info: Dictionary = combat_ctrl.get_active_blue_stunt_info()
			var stunt_id: String = str(stunt_info.get("skill_id", ""))
			tile.visible = (stunt_id != "")
			if stunt_id != "":
				var st_def: Dictionary = DataDB.get_skill(stunt_id)
				w["skill_id"] = stunt_id
				w["stunt_owner_id"] = str(stunt_info.get("owner_id", ""))
				key_l.text = "特技"
				icon_r.texture = _load_tex(str(st_def.get("icon", "")))
				tile.tooltip_text = "%s\n%s" % [DataDB.loc(str(st_def.get("name_key", ""))), DataDB.loc(str(st_def.get("desc_key", "")))]
			else:
				w["skill_id"] = ""
				w["stunt_owner_id"] = ""
			continue

		var sk_id: String = str(bar.get(code, ""))
		w["skill_id"] = sk_id
		if sk_id == "":
			icon_r.texture = null
			key_l.text = code
			tile.tooltip_text = ""
		else:
			var sdef: Dictionary = DataDB.get_skill(sk_id)
			icon_r.texture = _load_tex(str(sdef.get("icon", "")))
			key_l.text = code
			tile.tooltip_text = "【%s】(%s)\n%s" % [
				DataDB.loc(str(sdef.get("name_key", sk_id))),
				UIThemeBuilder.get_element_dual_badge(str(sdef.get("element", "none"))),
				DataDB.loc(str(sdef.get("desc_key", "")))
			]


func _process(delta: float) -> void:
	if combat_ctrl == null:
		return

	if not SaveManager.reduced_motion:
		_ui_pulse_clock += delta

	_pause_banner.visible = combat_ctrl.tactical_paused
	var status_parts: PackedStringArray = PackedStringArray()
	if combat_ctrl.stealth_timer > 0.0:
		status_parts.append("【敛息潜行 %.1fs】" % combat_ctrl.stealth_timer)
	if combat_ctrl.preemptive_buff_timer > 0.0:
		status_parts.append("【先机破袭 %.1fs】" % combat_ctrl.preemptive_buff_timer)
	if not CampaignState.active_elixir.is_empty():
		var el_id: String = str(CampaignState.active_elixir.get("item_id", ""))
		var el_name: String = DataDB.loc(str(DataDB.get_any_item_or_equip(el_id).get("name_key", el_id)))
		status_parts.append("【%s %dm】" % [el_name, int(ceil(float(CampaignState.active_elixir.get("remaining_sec", 0.0)) / 60.0))])
	_status_buff_lbl.text = "   ".join(status_parts)

	var fid_cur: String = CampaignState.active_formation_id
	var fname_cur: String = DataDB.loc(str(DataDB.get_formation(fid_cur).get("name_key", fid_cur)))
	_formation_plaque.text = _get_formation_plaque_text(fid_cur, fname_cur)

	# 1. 实时刷新左下小队框气血/真元、头像高亮与至多 3 枚状态图标
	var all_healthy: bool = true
	for cinfo: Dictionary in _party_cards:
		var cid: String = str(cinfo.get("char_id", ""))
		if cid == "" or not combat_ctrl.party_actors.has(cid):
			continue
		var pa: BattleActor = combat_ctrl.party_actors[cid] as BattleActor
		var pu: Dictionary = combat_ctrl.unit_states.get(cid, {}) as Dictionary
		var pm: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var hp_r: float = clampf(float(pa.hp) / float(maxi(1, pa.max_hp)), 0.0, 1.0)
		var mp_r: float = clampf(float(pa.mp) / float(maxi(1, pa.max_mp)), 0.0, 1.0)
		if hp_r < 0.90:
			all_healthy = false

		(cinfo["hp_fill"] as ColorRect).size.x = float(cinfo["hp_max_w"]) * hp_r
		(cinfo["hp_lbl"] as Label).text = "%s %d/%d%s" % [
			tr("TERM_HP"), pa.hp, pa.max_hp,
			(" (+%d盾)" % int(pa.shield)) if pa.shield >= 1.0 else ""
		]
		(cinfo["mp_fill"] as ColorRect).size.x = float(cinfo["mp_max_w"]) * mp_r
		(cinfo["mp_lbl"] as Label).text = "%s %d/%d%s" % [
			tr("TERM_MP"), pa.mp, pa.max_mp,
			(" [瘴×%d]" % pa.miasma_stacks) if pa.miasma_stacks > 0 else ""
		]

		var av_tex_r: TextureRect = cinfo["avatar_tex"] as TextureRect
		var av_frame_r: TextureRect = cinfo["avatar_frame"] as TextureRect
		var banner_sb: StyleBoxFlat = cinfo["banner_sb"] as StyleBoxFlat
		av_tex_r.modulate = Color.WHITE if pa.alive else Color(0.45, 0.42, 0.40, 0.90)
		var is_mo: bool = (combat_ctrl.hovered_ally_id == cid)
		var is_leader: bool = (int(cinfo.get("formation_slot", 0)) == CampaignState.controlled_slot)
		if is_mo:
			av_frame_r.modulate = Color("#74F0C2")
			banner_sb.border_color = Color("#74F0C2")
		elif is_leader:
			av_frame_r.modulate = Color("#FCE6A4")
			banner_sb.border_color = Color("#D6A85A")
		else:
			av_frame_r.modulate = Color.WHITE
			banner_sb.border_color = Color("#7D6339")

		_refresh_party_buff_badges(cinfo["buff_badges"] as Array[Dictionary], pa, pu, pm)

	# 2. 灵宠 Ctrl+1 / Ctrl+2 实时冷却更新
	if _pet_bar.visible and combat_ctrl.pet_actor != null:
		var pdef_live: Dictionary = DataDB.get_pet(CampaignState.active_pet_id)
		var p_u: Dictionary = combat_ctrl.unit_states.get(combat_ctrl.pet_actor.actor_id, {}) as Dictionary
		var p_cds: Dictionary = p_u.get("cooldowns", {}) as Dictionary
		var sk1_id: String = str(pdef_live.get("skill_1", ""))
		var sk2_id: String = str(pdef_live.get("skill_2", ""))
		var sk1_nm: String = DataDB.loc(str(DataDB.get_skill(sk1_id).get("name_key", "")))
		var sk2_nm: String = DataDB.loc(str(DataDB.get_skill(sk2_id).get("name_key", "")))
		var rem1: float = float(p_cds.get(sk1_id, 0.0))
		var rem2: float = float(p_cds.get(sk2_id, 0.0))
		_pet_sk1_btn.text = ("Ctrl+1 %s(%.0fs)" % [sk1_nm, rem1]) if rem1 > 0.05 else ("Ctrl+1 " + sk1_nm)
		_pet_sk2_btn.text = ("Ctrl+2 %s(%.0fs)" % [sk2_nm, rem2]) if rem2 > 0.05 else ("Ctrl+2 " + sk2_nm)

	# 3. 脱战保持高对比清晰度（最低 0.92）
	var target_alpha: float = 1.0
	if not combat_ctrl.in_combat and combat_ctrl.out_of_combat_sec >= 5.0 and all_healthy and not _hud_hovered and not _quick_drawer.visible:
		target_alpha = 0.92
	_fade_alpha = move_toward(_fade_alpha, target_alpha, delta * 2.2)
	_party_box.modulate.a = _fade_alpha
	_bottom_cluster.modulate.a = _fade_alpha

	# 4. 实时刷新快捷栏金色扇形 GCD/CD 转圈与【五行相生连携】边框高亮
	var ctrl_id: String = combat_ctrl.get_controlled_char_id()
	var cu: Dictionary = combat_ctrl.unit_states.get(ctrl_id, {}) as Dictionary
	var gcd_rem: float = float(cu.get("gcd_timer", 0.0))
	var gcd_tot: float = maxf(0.001, float(cu.get("gcd_total", StatLedger.BASE_GCD_SEC)))
	var cds: Dictionary = cu.get("cooldowns", {}) as Dictionary
	var cd_tots: Dictionary = cu.get("cooldown_totals", {}) as Dictionary

	var locked_ea: BattleActor = null
	for ea: BattleActor in combat_ctrl.enemy_actors:
		if ea.alive and ea.actor_id == combat_ctrl.locked_enemy_id:
			locked_ea = ea
			break
	var seal_elem: String = locked_ea.mother_seal_element if (locked_ea != null and locked_ea.mother_seal_timer > 0.0) else ""

	for code_var: Variant in _slot_widgets.keys():
		var code: String = str(code_var)
		var w: Dictionary = _slot_widgets[code] as Dictionary
		var sk_id: String = str(w.get("skill_id", ""))
		var cd_rad: RadialCooldownOverlay = w["cd_radial"] as RadialCooldownOverlay
		var cd_l: Label = w["cd_lbl"] as Label
		var rim_sb: StyleBoxFlat = w["rim_sb"] as StyleBoxFlat
		cd_rad.step_gleam(delta)

		if code == "5" or code == "6":
			var p_idef: Dictionary = DataDB.get_any_item_or_equip(sk_id)
			var is_talisman: bool = (str(p_idef.get("category", "")) == "talisman")
			var p_rem: float = 0.0 if is_talisman else combat_ctrl.pill_cooldown_timer
			var p_tot: float = maxf(0.001, combat_ctrl.pill_cooldown_total)
			cd_rad.set_sweep((p_rem / p_tot) if p_rem > 0.05 else 0.0, false)
			cd_l.text = ("%.0fs" % p_rem) if p_rem > 0.05 else ""
			rim_sb.border_color = Color("#74E0B8") if (is_talisman and combat_ctrl.stealth_timer > 0.0) else UIThemeBuilder.COL_BRONZE_DIM
			rim_sb.set_border_width_all(2 if (is_talisman and combat_ctrl.stealth_timer > 0.0) else 1)
			continue
		if sk_id == "" or code == "Z":
			cd_rad.set_sweep(0.0, false)
			cd_l.text = ""
			rim_sb.border_color = UIThemeBuilder.COL_BRONZE_DIM
			rim_sb.set_border_width_all(1)
			continue

		var sdef: Dictionary = DataDB.get_skill(sk_id)
		var slot_u: Dictionary = cu
		var slot_cds: Dictionary = cds
		var slot_cd_tots: Dictionary = cd_tots
		var slot_gcd_rem: float = gcd_rem
		var slot_gcd_tot: float = gcd_tot
		if code == "STUNT":
			var live_st: Dictionary = combat_ctrl.get_active_blue_stunt_info()
			var st_owner: String = str(live_st.get("owner_id", str(w.get("stunt_owner_id", ctrl_id))))
			if st_owner != "" and combat_ctrl.unit_states.has(st_owner):
				slot_u = combat_ctrl.unit_states[st_owner] as Dictionary
				slot_cds = slot_u.get("cooldowns", {}) as Dictionary
				slot_cd_tots = slot_u.get("cooldown_totals", {}) as Dictionary
				slot_gcd_rem = float(slot_u.get("gcd_timer", 0.0))
				slot_gcd_tot = maxf(0.001, float(slot_u.get("gcd_total", StatLedger.BASE_GCD_SEC)))

		var sk_cd: float = float(slot_cds.get(sk_id, 0.0))
		var uses_gcd: bool = bool(sdef.get("uses_gcd", true))
		var gcd_part: float = slot_gcd_rem if uses_gcd else 0.0
		var eff_rem: float = maxf(sk_cd, gcd_part)

		var sk_tot: float = maxf(sk_cd, float(slot_cd_tots.get(sk_id, maxf(0.001, float(sdef.get("cooldown_sec", slot_gcd_tot))))))
		var sk_ratio: float = (sk_cd / maxf(0.001, sk_tot)) if sk_cd > 0.001 else 0.0
		var gcd_ratio: float = (gcd_part / maxf(0.001, slot_gcd_tot)) if gcd_part > 0.001 else 0.0
		var sweep_ratio: float = maxf(sk_ratio, gcd_ratio)

		if eff_rem > 0.05 and sweep_ratio > 0.005:
			var is_gcd_only: bool = (gcd_ratio >= sk_ratio and sk_cd <= gcd_part)
			cd_rad.set_sweep(sweep_ratio, is_gcd_only)
			cd_l.text = "%.1fs" % eff_rem
		else:
			cd_rad.set_sweep(0.0, false)
			cd_l.text = ""

		var s_elem: String = str(sdef.get("element", "none"))
		var syn_ready: bool = false
		if seal_elem != "" and RtwpSimStep.ELEMENT_SYNERGY_MAP.has(seal_elem):
			var child_e: String = str((RtwpSimStep.ELEMENT_SYNERGY_MAP[seal_elem] as Dictionary).get("child", ""))
			syn_ready = (child_e == s_elem)

		if code == "G" and combat_ctrl.team_attunement >= 100.0:
			rim_sb.border_color = Color("#74F0C2")
			rim_sb.set_border_width_all(2)
		elif syn_ready and eff_rem <= 0.05:
			rim_sb.border_color = UIThemeBuilder.COL_GILT_BRIGHT
			rim_sb.set_border_width_all(2)
		elif code == "STUNT":
			rim_sb.border_color = Color("#8FD4E8")
			rim_sb.set_border_width_all(2)
		else:
			rim_sb.border_color = UIThemeBuilder.COL_BRONZE_DIM
			rim_sb.set_border_width_all(1)

	# 5. 同调气机槽刷新
	_attunement_wrap.visible = combat_ctrl.in_combat or (combat_ctrl.out_of_combat_sec < 2.5 and combat_ctrl.team_attunement >= 0.5)
	if _attunement_wrap.visible:
		var att_r: float = clampf(combat_ctrl.team_attunement / RtwpSimStep.MAX_ATTUNEMENT, 0.0, 1.0)
		_attunement_fill.size.x = 298.0 * att_r
		var att_suffix: String = ""
		if combat_ctrl.team_attunement >= 100.0:
			_attunement_sb.border_color = Color("#74F0C2")
			if CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword"):
				att_suffix = " 【按 G 合击】"
			else:
				att_suffix = " （夜话领悟）"
		else:
			_attunement_sb.border_color = UIThemeBuilder.COL_BRONZE_DIM
		_attunement_lbl.text = "%s: %d/100%s" % [
			tr("TERM_ATTUNEMENT"),
			int(floor(combat_ctrl.team_attunement)),
			att_suffix
		]

	# 6. 顶部首领大匾额实时刷新
	if _tracked_boss != null and is_instance_valid(_tracked_boss) and _tracked_boss.alive:
		_boss_panel.visible = true
		if _tracked_boss.actor_id.begins_with("boss_mist_wolf_king"):
			_boss_title_lbl.text = "【首领】%s · 道影侵蚀" % _tracked_boss.display_name
		else:
			_boss_title_lbl.text = "【首领】%s" % _tracked_boss.display_name

		var bhp_r: float = clampf(float(_tracked_boss.hp) / float(maxi(1, _tracked_boss.max_hp)), 0.0, 1.0)
		_boss_hp_fill.size.x = 578.0 * bhp_r
		_boss_hp_lbl.text = "%s  %d / %d" % [tr("TERM_HP"), _tracked_boss.hp, _tracked_boss.max_hp]

		if _tracked_boss.stagger_timer > 0.0:
			_boss_ward_fill.size.x = 578.0
			_boss_ward_fill.color = Color("#E8B858")
			_boss_ward_lbl.text = "【气机破绽 · 承伤剧增】剩余 %.1fs" % _tracked_boss.stagger_timer
		else:
			var bw_r: float = clampf(_tracked_boss.ward_current / maxf(1.0, _tracked_boss.ward_max), 0.0, 1.0)
			_boss_ward_fill.size.x = 578.0 * bw_r
			_boss_ward_fill.color = UIThemeBuilder.get_element_color(_tracked_boss.ward_element)
			_boss_ward_lbl.text = "%s %s  %d / %d" % [
				UIThemeBuilder.get_element_dual_badge(_tracked_boss.ward_element),
				tr("TERM_WARD"),
				int(round(_tracked_boss.ward_current)),
				int(round(_tracked_boss.ward_max))
			]

		if _tracked_boss.is_casting and _tracked_boss.cast_duration > 0.0:
			_boss_cast_box.visible = true
			var bc_r: float = clampf(_tracked_boss.cast_progress / _tracked_boss.cast_duration, 0.0, 1.0)
			_boss_cast_fill.size.x = 576.0 * bc_r
			var rem_cast: float = maxf(0.0, _tracked_boss.cast_duration - _tracked_boss.cast_progress)
			if _tracked_boss.cast_interruptible:
				_boss_cast_fill.color = UIThemeBuilder.COL_CAST_AMBER
				_boss_cast_sb.border_color = Color("#F5D580")
				_boss_cast_lbl.text = "吟唱: %s（按 Q 可打断！ %.1fs）" % [_tracked_boss.cast_skill_name, rem_cast]
			else:
				_boss_cast_fill.color = UIThemeBuilder.COL_CAST_LOCKED
				_boss_cast_sb.border_color = Color("#D45A52")
				_boss_cast_lbl.text = "危招: %s（不可打断·速躲圈 %.1fs）" % [_tracked_boss.cast_skill_name, rem_cast]
		else:
			_boss_cast_box.visible = false
	else:
		_boss_panel.visible = false

	_minimap_canvas.queue_redraw()


func _refresh_party_buff_badges(
	badges: Array[Dictionary],
	pa: BattleActor,
	pu: Dictionary,
	pm: Dictionary
) -> void:
	var active_entries: Array[Dictionary] = []
	if pa.miasma_stacks > 0:
		var pulse_a: float = 1.0 if SaveManager.reduced_motion else (0.72 + 0.28 * sin(_ui_pulse_clock * 7.5))
		active_entries.append({"icon": "res://assets/ui/icons/herb_corrupt.png", "col": Color(0.79, 0.47, 0.87, pulse_a)})
	if int(pm.get("meridian_bruise", 0)) > 0:
		active_entries.append({"icon": "res://assets/ui/icons/pill_burnt.png", "col": Color("#B84332")})
	if pa.shield >= 1.0:
		active_entries.append({"icon": "res://assets/ui/icons/sk_lotus_shield.png", "col": Color("#8CE0D4")})
	if float(pu.get("dr_buff_timer", 0.0)) > 0.0 and active_entries.size() < 3:
		active_entries.append({"icon": "res://assets/ui/icons/sk_taunt_bell.png", "col": Color("#D6A85A")})
	if float(pu.get("hot_timer", 0.0)) > 0.0 and active_entries.size() < 3:
		active_entries.append({"icon": "res://assets/ui/icons/sk_wood_heal.png", "col": Color("#58C496")})
	if float(pu.get("miasma_immune_timer", 0.0)) > 0.0 and active_entries.size() < 3:
		active_entries.append({"icon": "res://assets/ui/icons/pill_qingmu.png", "col": Color("#74E0B8")})

	for idx: int in range(badges.size()):
		var b_dict: Dictionary = badges[idx]
		var bp: PanelContainer = b_dict["panel"] as PanelContainer
		if idx < active_entries.size():
			var ent: Dictionary = active_entries[idx]
			bp.visible = true
			(b_dict["sb"] as StyleBoxFlat).border_color = ent["col"] as Color
			(b_dict["icon"] as TextureRect).texture = _load_tex(str(ent["icon"]))
		else:
			bp.visible = false


func _draw_minimap() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _minimap_canvas.size)
	_minimap_canvas.draw_rect(rect, Color(0.14, 0.17, 0.16, 0.96), true)
	for gx: int in range(1, 4):
		var lx: float = rect.size.x * float(gx) * 0.25
		_minimap_canvas.draw_line(Vector2(lx, 2.0), Vector2(lx, rect.size.y - 2.0), Color(0.24, 0.28, 0.26, 0.32), 1.0)
	_minimap_canvas.draw_line(Vector2(2.0, rect.size.y * 0.5), Vector2(rect.size.x - 2.0, rect.size.y * 0.5), Color(0.24, 0.28, 0.26, 0.32), 1.0)

	if combat_ctrl == null:
		_minimap_canvas.draw_rect(rect, UIThemeBuilder.COL_BRONZE_DIM, false, 1.5)
		return

	var scale_x: float = rect.size.x / 2400.0
	var scale_y: float = rect.size.y / 1400.0

	for rpoly: PackedVector2Array in _mm_roads:
		if rpoly.size() >= 3:
			var scaled_pts: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in rpoly:
				scaled_pts.append(Vector2(clampf(pt.x * scale_x, 1.5, rect.size.x - 1.5), clampf(pt.y * scale_y, 1.5, rect.size.y - 1.5)))
			_minimap_canvas.draw_colored_polygon(scaled_pts, Color(0.36, 0.39, 0.37, 0.78))

	for brect: Rect2 in _mm_buildings:
		var srect: Rect2 = Rect2(
			Vector2(brect.position.x * scale_x, brect.position.y * scale_y),
			Vector2(maxf(8.0, brect.size.x * scale_x), maxf(6.0, brect.size.y * scale_y))
		)
		_minimap_canvas.draw_rect(srect, Color(0.54, 0.45, 0.34, 0.85), true)
		_minimap_canvas.draw_rect(srect, Color(0.82, 0.68, 0.44, 0.85), false, 1.0)

	for p_pt: Vector2 in _mm_portals:
		var mp: Vector2 = Vector2(clampf(p_pt.x * scale_x, 6.0, rect.size.x - 6.0), clampf(p_pt.y * scale_y, 6.0, rect.size.y - 6.0))
		_minimap_canvas.draw_rect(Rect2(mp - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), UIThemeBuilder.COL_BRONZE_GOLD, true)

	for st_pt: Vector2 in _mm_steles:
		var sp: Vector2 = Vector2(st_pt.x * scale_x, st_pt.y * scale_y)
		var d_pts: PackedVector2Array = PackedVector2Array([
			sp + Vector2(0.0, -5.0),
			sp + Vector2(5.0, 0.0),
			sp + Vector2(0.0, 5.0),
			sp + Vector2(-5.0, 0.0),
		])
		_minimap_canvas.draw_colored_polygon(d_pts, Color("#62E0B8"))

	for npc: BattleActor in _mm_npcs:
		if is_instance_valid(npc):
			var np_pt: Vector2 = Vector2(npc.position.x * scale_x, npc.position.y * scale_y)
			_minimap_canvas.draw_circle(np_pt, 3.2, Color("#E8C06E"))

	for ea: BattleActor in combat_ctrl.enemy_actors:
		if is_instance_valid(ea) and ea.alive:
			var ep: Vector2 = Vector2(clampf(ea.position.x * scale_x, 4.0, rect.size.x - 4.0), clampf(ea.position.y * scale_y, 4.0, rect.size.y - 4.0))
			_minimap_canvas.draw_circle(ep, 4.8 if ea.is_boss else 3.2, UIThemeBuilder.COL_CINNABAR_RED)

	if combat_ctrl.world_camera != null:
		var cam_c: Vector2 = combat_ctrl.world_camera.get_screen_center_position()
		var live_vp: Vector2 = get_viewport_rect().size / combat_ctrl.world_camera.zoom
		var vp_sz: Vector2 = Vector2(live_vp.x * scale_x, live_vp.y * scale_y)
		var cam_r: Rect2 = Rect2(Vector2(cam_c.x * scale_x, cam_c.y * scale_y) - vp_sz * 0.5, vp_sz)
		_minimap_canvas.draw_rect(cam_r.intersection(rect), Color(0.84, 0.68, 0.42, 0.34), false, 1.0)

	var ppos: Vector2 = combat_ctrl.get_controlled_actor_pos()
	var pp: Vector2 = Vector2(clampf(ppos.x * scale_x, 5.0, rect.size.x - 5.0), clampf(ppos.y * scale_y, 5.0, rect.size.y - 5.0))
	_minimap_canvas.draw_circle(pp, 5.2, Color(0.10, 0.16, 0.14, 0.95))
	_minimap_canvas.draw_circle(pp, 4.0, Color("#8AF6CC"))
	_minimap_canvas.draw_rect(rect, UIThemeBuilder.COL_BRONZE_GOLD, false, 1.5)


func _draw() -> void:
	if combat_ctrl != null and combat_ctrl.tactical_paused:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.34, 0.36, 0.10), true)
		draw_rect(Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 8.0)), Color(0.55, 0.86, 0.80, 0.55), false, 3.0)
	if _is_box_selecting:
		draw_rect(_box_select_rect, Color(0.46, 0.86, 0.76, 0.18), true)
		draw_rect(_box_select_rect, Color(0.68, 0.94, 0.86, 0.88), false, 2.0)


func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			_tex_cache[path] = t
			return t
	return null


func _load_avatar_or_fallback(av_path: String, portrait_id: String) -> Texture2D:
	var direct: Texture2D = _load_tex(av_path)
	if direct != null:
		return direct
	var fallback_p: String = "res://assets/portraits/%s_calm.png" % portrait_id
	var p_tex: Texture2D = _load_tex(fallback_p)
	if p_tex != null:
		var at: AtlasTexture = AtlasTexture.new()
		at.atlas = p_tex
		at.region = Rect2(256.0, 64.0, 512.0, 512.0)
		return at
	return null
