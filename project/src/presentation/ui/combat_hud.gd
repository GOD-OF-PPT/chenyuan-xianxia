class_name CombatHud
extends Control
## 第三层 1920×1080 魔兽现代团本人体工学 HUD × 乌木错金玉牌器物界面
## 严格对齐 docs/design/21-ui-ux-spec.md 第 3.1 节：
## - 底部居中乌木快捷栏：[1][2][3][4] | [Q][E][R][G] | [5][6] | [蓝字特技] | [Z 阵/宠]，实时显示 1.5s GCD 与五行相生高亮！
## - 左下小队框体（F1~F4）：原生支持 Mouseover（鼠标悬停直接加血驱散）+ 角色职责 AI 一键轮换！
## - 灵宠迷你控制条：[姿态] [Ctrl+1] [Ctrl+2]
## - 顶部居中首领框（4200 气血 + ❖木灵护罡 + 24px 大读条）
## - 右上淡墨小地图与道匣/留卷入口；脱战满 5 秒且气血 >90% 时平滑呼吸半透隐退。

signal open_casket_requested(tab_id: String)
signal open_map_requested()
signal open_save_modal_requested()
signal open_settings_requested()

var combat_ctrl: RtwpCombatController = null

## 顶层子组件引用
var _boss_panel: PanelContainer
var _boss_title_lbl: Label
var _boss_hp_fill: ColorRect
var _boss_hp_lbl: Label
var _boss_ward_fill: ColorRect
var _boss_ward_lbl: Label
var _boss_cast_box: Control
var _boss_cast_fill: ColorRect
var _boss_cast_lbl: Label
var _tracked_boss: BattleActor = null

var _pause_banner: PanelContainer
var _status_buff_lbl: Label

var _party_box: VBoxContainer
var _party_cards: Array[Dictionary] = []

var _bottom_cluster: Control
var _pet_bar: PanelContainer
var _pet_stance_btn: Button
var _pet_sk1_btn: Button
var _pet_sk2_btn: Button

var _quick_drawer: PanelContainer
var _drawer_vbox: VBoxContainer

var _slot_widgets: Dictionary = {} # slot_code -> {btn, icon, key_lbl, cd_lbl, border_panel, skill_id}
var _attunement_wrap: PanelContainer
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


func set_interact_prompt(prompt_text: String, screen_anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
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
		var py: float = clampf(screen_anchor.y - box_h - 14.0, 28.0, maxf(28.0, vp_size.y - 210.0))
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
		_interact_prompt_box.offset_top = 720.0
		_interact_prompt_box.offset_bottom = 760.0


func is_quick_drawer_open() -> bool:
	return _quick_drawer != null and _quick_drawer.visible


func toggle_quick_drawer() -> void:
	_quick_drawer.visible = not _quick_drawer.visible
	if _quick_drawer.visible:
		_rebuild_quick_drawer()


func _build_top_boss_bar() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -310.0
	_boss_panel.offset_right = 310.0
	_boss_panel.offset_top = 14.0
	_boss_panel.offset_bottom = 166.0
	_boss_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.10, 0.09, 0.08, 0.94), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_boss_panel.visible = false
	add_child(_boss_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_boss_panel.add_child(vb)

	_boss_title_lbl = Label.new()
	_boss_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_title_lbl.add_theme_font_size_override("font_size", 22)
	_boss_title_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	vb.add_child(_boss_title_lbl)

	# Boss HP bar
	var hp_bg: Control = _make_bar_row(580.0, 24.0, Color(0.22, 0.10, 0.09, 0.95))
	_boss_hp_fill = hp_bg.get_child(0) as ColorRect
	_boss_hp_fill.color = UIThemeBuilder.COL_CINNABAR_RED
	_boss_hp_lbl = hp_bg.get_child(1) as Label
	vb.add_child(hp_bg)

	# Boss Five-Element Ward bar
	var ward_bg: Control = _make_bar_row(580.0, 22.0, Color(0.09, 0.15, 0.13, 0.95))
	_boss_ward_fill = ward_bg.get_child(0) as ColorRect
	_boss_ward_fill.color = UIThemeBuilder.COL_JADE_GREEN
	_boss_ward_lbl = ward_bg.get_child(1) as Label
	vb.add_child(ward_bg)

	# Boss 24px Large Cast Bar
	_boss_cast_box = _make_bar_row(580.0, 30.0, Color(0.18, 0.14, 0.08, 0.96))
	_boss_cast_fill = _boss_cast_box.get_child(0) as ColorRect
	_boss_cast_lbl = _boss_cast_box.get_child(1) as Label
	_boss_cast_lbl.add_theme_font_size_override("font_size", 20)
	_boss_cast_box.visible = false
	vb.add_child(_boss_cast_box)


func _make_bar_row(w: float, h: float, bg_c: Color) -> Control:
	var bg: ColorRect = ColorRect.new()
	bg.custom_minimum_size = Vector2(w, h)
	bg.color = bg_c

	var fill: ColorRect = ColorRect.new()
	fill.position = Vector2(2.0, 2.0)
	fill.size = Vector2(w - 4.0, h - 4.0)
	bg.add_child(fill)

	var lbl: Label = Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	bg.add_child(lbl)

	return bg


func _build_top_right_cluster() -> void:
	var tr_panel: PanelContainer = PanelContainer.new()
	tr_panel.anchor_left = 1.0
	tr_panel.anchor_right = 1.0
	tr_panel.offset_left = -352.0
	tr_panel.offset_right = -16.0
	tr_panel.offset_top = 14.0
	tr_panel.offset_bottom = 252.0
	tr_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.10, 0.09, 0.90), UIThemeBuilder.COL_BRONZE_DIM, 2, 6))
	add_child(tr_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	tr_panel.add_child(vb)

	_top_right_zone_lbl = Label.new()
	_top_right_zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_right_zone_lbl.add_theme_font_size_override("font_size", 17)
	_top_right_zone_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	vb.add_child(_top_right_zone_lbl)

	# 淡墨圆盘小地图画布
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
	b.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	var sb: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.16, 0.14, 0.12, 0.95), UIThemeBuilder.COL_BRONZE_DIM, 1, 4)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	b.add_theme_stylebox_override("normal", sb)
	return b


func _build_tactical_pause_watermark() -> void:
	_pause_banner = PanelContainer.new()
	_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_banner.anchor_left = 0.5
	_pause_banner.anchor_right = 0.5
	_pause_banner.offset_left = -360.0
	_pause_banner.offset_right = 360.0
	_pause_banner.offset_top = 772.0
	_pause_banner.offset_bottom = 816.0
	_pause_banner.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.08, 0.14, 0.16, 0.92), Color("#8CE0D4"), 2, 6))
	_pause_banner.visible = false
	add_child(_pause_banner)

	var p_lbl: Label = Label.new()
	p_lbl.text = tr("HUD_TACTICAL_PAUSE")
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
	p_lbl.add_theme_color_override("font_color", Color("#B9F2E6"))
	_pause_banner.add_child(p_lbl)

	_status_buff_lbl = Label.new()
	_status_buff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_buff_lbl.anchor_left = 0.5
	_status_buff_lbl.anchor_right = 0.5
	_status_buff_lbl.offset_left = -280.0
	_status_buff_lbl.offset_right = 280.0
	_status_buff_lbl.offset_top = 822.0
	_status_buff_lbl.offset_bottom = 850.0
	_status_buff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_buff_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	_status_buff_lbl.add_theme_color_override("font_color", Color("#98E2C6"))
	add_child(_status_buff_lbl)


func _build_party_frames() -> void:
	_party_box = VBoxContainer.new()
	_party_box.anchor_top = 1.0
	_party_box.anchor_bottom = 1.0
	_party_box.offset_left = 20.0
	_party_box.offset_right = 324.0
	_party_box.offset_top = -420.0
	_party_box.offset_bottom = -16.0
	_party_box.alignment = BoxContainer.ALIGNMENT_END
	_party_box.add_theme_constant_override("separation", 8)
	add_child(_party_box)

	for i: int in range(4):
		var slot_num: int = i + 1
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(298.0, 90.0)
		card.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.10, 0.09, 0.96), UIThemeBuilder.COL_BRONZE_GOLD, 2, 5))
		_party_box.add_child(card)

		var cvb: VBoxContainer = VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 4)
		card.add_child(cvb)

		var top_hb: HBoxContainer = HBoxContainer.new()
		cvb.add_child(top_hb)

		var name_l: Label = Label.new()
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 17)
		top_hb.add_child(name_l)

		var ai_btn: Button = _make_compact_btn("AI")
		top_hb.add_child(ai_btn)

		var hp_row: Control = _make_bar_row(268.0, 20.0, Color(0.20, 0.10, 0.10, 0.92))
		var hp_fill: ColorRect = hp_row.get_child(0) as ColorRect
		hp_fill.color = Color("#458F68")
		var hp_l: Label = hp_row.get_child(1) as Label
		cvb.add_child(hp_row)

		var mp_row: Control = _make_bar_row(268.0, 18.0, Color(0.09, 0.13, 0.20, 0.92))
		var mp_fill: ColorRect = mp_row.get_child(0) as ColorRect
		mp_fill.color = UIThemeBuilder.COL_WATER_BLUE
		var mp_l: Label = mp_row.get_child(1) as Label
		cvb.add_child(mp_row)

		var card_info: Dictionary = {
			"slot_num": slot_num,
			"char_id": "",
			"card": card,
			"name_lbl": name_l,
			"ai_btn": ai_btn,
			"hp_fill": hp_fill,
			"hp_lbl": hp_l,
			"mp_fill": mp_fill,
			"mp_lbl": mp_l,
		}
		_party_cards.append(card_info)

		# Mouseover 指向悬停侦测 + 左键点击切主控！
		card.mouse_entered.connect(func() -> void:
			_hud_hovered = true
			if combat_ctrl != null:
				combat_ctrl.hovered_ally_id = str(card_info.get("char_id", ""))
		)
		card.mouse_exited.connect(func() -> void:
			_hud_hovered = false
			if combat_ctrl != null and combat_ctrl.hovered_ally_id == str(card_info.get("char_id", "")):
				combat_ctrl.hovered_ally_id = ""
		)
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


func _build_bottom_action_bar() -> void:
	_bottom_cluster = Control.new()
	_bottom_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_cluster.anchor_left = 0.5
	_bottom_cluster.anchor_right = 0.5
	_bottom_cluster.anchor_top = 1.0
	_bottom_cluster.anchor_bottom = 1.0
	_bottom_cluster.offset_left = -495.0
	_bottom_cluster.offset_right = 495.0
	_bottom_cluster.offset_top = -172.0
	_bottom_cluster.offset_bottom = -12.0
	add_child(_bottom_cluster)

	# 左上方迷你灵宠控制条（Ctrl+1 / Ctrl+2）
	_pet_bar = PanelContainer.new()
	_pet_bar.position = Vector2(12.0, 4.0)
	_pet_bar.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 4))
	_pet_bar.visible = false
	_bottom_cluster.add_child(_pet_bar)

	var pet_hb: HBoxContainer = HBoxContainer.new()
	pet_hb.add_theme_constant_override("separation", 8)
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

	# 正上方居中同调气机青莲槽（仅在战斗中或拥有同调气机时展开显示，脱战零气机时干净收纳！）
	_attunement_wrap = PanelContainer.new()
	_attunement_wrap.position = Vector2(310.0, 4.0)
	_attunement_wrap.custom_minimum_size = Vector2(368.0, 34.0)
	_attunement_wrap.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.10, 0.09, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 4))
	_attunement_wrap.visible = false
	_bottom_cluster.add_child(_attunement_wrap)

	var att_bar: Control = _make_bar_row(356.0, 24.0, Color(0.08, 0.14, 0.12, 0.95))
	_attunement_fill = att_bar.get_child(0) as ColorRect
	_attunement_fill.color = UIThemeBuilder.COL_JADE_GREEN
	_attunement_lbl = att_bar.get_child(1) as Label
	_attunement_wrap.add_child(att_bar)

	# 主乌木镶青铜技能栏底座
	var main_bar: PanelContainer = PanelContainer.new()
	main_bar.position = Vector2(8.0, 44.0)
	main_bar.custom_minimum_size = Vector2(974.0, 108.0)
	main_bar.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.09, 0.08, 0.96), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	main_bar.mouse_entered.connect(func() -> void: _hud_hovered = true)
	main_bar.mouse_exited.connect(func() -> void: _hud_hovered = false)
	_bottom_cluster.add_child(main_bar)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	main_bar.add_child(hb)

	var slot_order: Array[String] = ["1", "2", "3", "4", "Q", "E", "R", "G", "5", "6", "STUNT", "Z"]
	for code: String in slot_order:
		var tile: PanelContainer = _create_action_tile(code)
		hb.add_child(tile)

	# Z 键奇门变阵/灵宠小抽屉
	_quick_drawer = PanelContainer.new()
	_quick_drawer.position = Vector2(720.0, -148.0)
	_quick_drawer.custom_minimum_size = Vector2(260.0, 140.0)
	_quick_drawer.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.97), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_quick_drawer.visible = false
	_bottom_cluster.add_child(_quick_drawer)

	_drawer_vbox = VBoxContainer.new()
	_drawer_vbox.add_theme_constant_override("separation", 6)
	_quick_drawer.add_child(_drawer_vbox)


func _create_action_tile(slot_code: String) -> PanelContainer:
	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(72.0, 88.0)
	var sb: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.15, 0.13, 0.12, 0.96), UIThemeBuilder.COL_BRONZE_DIM, 2, 5)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	tile.add_theme_stylebox_override("panel", sb)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	tile.add_child(vb)

	var icon_wrap: Control = Control.new()
	icon_wrap.custom_minimum_size = Vector2(62.0, 56.0)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon_wrap)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(icon_rect)

	var cd_overlay: ColorRect = ColorRect.new()
	cd_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_overlay.color = Color(0.05, 0.05, 0.05, 0.72)
	cd_overlay.visible = false
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(cd_overlay)

	var cd_lbl: Label = Label.new()
	cd_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	cd_lbl.add_theme_color_override("font_color", Color("#FCE49C"))
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(cd_lbl)

	var key_lbl: Label = Label.new()
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	key_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
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
		"stylebox": sb,
		"icon": icon_rect,
		"cd_overlay": cd_overlay,
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
	_interact_prompt_box.offset_top = 720.0
	_interact_prompt_box.offset_bottom = 762.0
	_interact_prompt_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.90), UIThemeBuilder.COL_BRONZE_GOLD, 2, 5))
	_interact_prompt_box.visible = false
	add_child(_interact_prompt_box)

	_interact_prompt_lbl = Label.new()
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


func refresh_static_bindings() -> void:
	_top_right_zone_lbl.text = tr("ZONE_NAME_" + CampaignState.current_zone_id.to_upper())
	var fdef: Dictionary = DataDB.get_formation(CampaignState.active_formation_id)
	var fname: String = DataDB.loc(str(fdef.get("name_key", CampaignState.active_formation_id)))
	_stones_lbl.text = "◆ %s: %d  |  %s" % [tr("TERM_SPIRIT_STONE"), CampaignState.spirit_stones, fname]

	if combat_ctrl == null:
		return

	# 更新左下 1~4 号阵位小队框
	for i: int in range(4):
		var cinfo: Dictionary = _party_cards[i]
		var cid: String = CampaignState.formation_slots[i]
		var card: PanelContainer = cinfo["card"] as PanelContainer
		if cid == "" or not combat_ctrl.party_actors.has(cid):
			card.visible = false
			cinfo["char_id"] = ""
			continue
		card.visible = true
		cinfo["char_id"] = cid
		var cdef: Dictionary = DataDB.get_character(cid)
		var m: Dictionary = CampaignState.party_members.get(cid, {}) as Dictionary
		var smod: Dictionary = FormationRules.get_slot_modifiers(fdef, i + 1)
		var cname: String = DataDB.loc(str(cdef.get("name_key", cid)))
		var is_ctrl: bool = (CampaignState.controlled_slot == i + 1)
		(cinfo["name_lbl"] as Label).text = "%sF%d %s·%s" % ["▶" if is_ctrl else "", i + 1, cname, str(smod.get("role_title", ""))]
		var presets: Array = cdef.get("ai_presets", []) as Array
		var pidx: int = int(m.get("ai_preset_index", 0))
		if pidx < presets.size() and presets[pidx] is Dictionary:
			(cinfo["ai_btn"] as Button).text = DataDB.loc(str((presets[pidx] as Dictionary).get("name_key", "AI")))

	# 更新灵宠迷你控制条
	if CampaignState.active_pet_id != "":
		_pet_bar.visible = true
		var pdef: Dictionary = DataDB.get_pet(CampaignState.active_pet_id)
		var stance_cn: String = "协助" if CampaignState.pet_stance == "assist" else ("跟随" if CampaignState.pet_stance == "follow" else "坚守")
		_pet_stance_btn.text = "%s:%s" % [DataDB.loc(str(pdef.get("name_key", ""))), stance_cn]
		_pet_sk1_btn.text = "C+1 " + DataDB.loc(str(DataDB.get_skill(str(pdef.get("skill_1", ""))).get("name_key", "")))
		_pet_sk2_btn.text = "C+2 " + DataDB.loc(str(DataDB.get_skill(str(pdef.get("skill_2", ""))).get("name_key", "")))
	else:
		_pet_bar.visible = false

	# 更新主控角色快捷栏图标与说明
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
			key_l.text = "Z·奇门"
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
				key_l.text = "G·合击"
				icon_r.texture = _load_tex(str(gsdef.get("icon", "")))
				tile.tooltip_text = "%s\n%s" % [DataDB.loc(str(gsdef.get("name_key", ""))), DataDB.loc(str(gsdef.get("desc_key", "")))]
			continue
		elif code == "STUNT":
			var stunt_id: String = combat_ctrl.get_active_blue_stunt_id()
			tile.visible = (stunt_id != "")
			if stunt_id != "":
				var st_def: Dictionary = DataDB.get_skill(stunt_id)
				w["skill_id"] = stunt_id
				key_l.text = "特技"
				icon_r.texture = _load_tex(str(st_def.get("icon", "")))
				tile.tooltip_text = "%s\n%s" % [DataDB.loc(str(st_def.get("name_key", ""))), DataDB.loc(str(st_def.get("desc_key", "")))]
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

	# 1. 实时刷新小队框血条/真元条
	var all_healthy: bool = true
	for cinfo: Dictionary in _party_cards:
		var cid: String = str(cinfo.get("char_id", ""))
		if cid == "" or not combat_ctrl.party_actors.has(cid):
			continue
		var pa: BattleActor = combat_ctrl.party_actors[cid] as BattleActor
		var hp_r: float = clampf(float(pa.hp) / float(maxi(1, pa.max_hp)), 0.0, 1.0)
		var mp_r: float = clampf(float(pa.mp) / float(maxi(1, pa.max_mp)), 0.0, 1.0)
		if hp_r < 0.90:
			all_healthy = false
		(cinfo["hp_fill"] as ColorRect).size.x = 264.0 * hp_r
		(cinfo["hp_lbl"] as Label).text = "%s %d/%d%s" % [
			tr("TERM_HP"), pa.hp, pa.max_hp,
			(" (+%d盾)" % int(pa.shield)) if pa.shield >= 1.0 else ""
		]
		(cinfo["mp_fill"] as ColorRect).size.x = 264.0 * mp_r
		(cinfo["mp_lbl"] as Label).text = "%s %d/%d%s" % [
			tr("TERM_MP"), pa.mp, pa.max_mp,
			(" [瘴×%d]" % pa.miasma_stacks) if pa.miasma_stacks > 0 else ""
		]

	# 2. 脱战保持高对比清晰度（最低 0.92，彻底杜绝发灰模糊），悬停或交战时 1.0
	var target_alpha: float = 1.0
	if not combat_ctrl.in_combat and combat_ctrl.out_of_combat_sec >= 5.0 and all_healthy and not _hud_hovered and not _quick_drawer.visible:
		target_alpha = 0.92
	_fade_alpha = move_toward(_fade_alpha, target_alpha, delta * 2.2)
	_party_box.modulate.a = _fade_alpha
	_bottom_cluster.modulate.a = _fade_alpha

	# 3. 实时刷新快捷栏 GCD、技能 CD 与【五行相生连携】高亮金青边框！
	var ctrl_id: String = combat_ctrl.get_controlled_char_id()
	var cu: Dictionary = combat_ctrl.unit_states.get(ctrl_id, {}) as Dictionary
	var gcd_rem: float = float(cu.get("gcd_timer", 0.0))
	var cds: Dictionary = cu.get("cooldowns", {}) as Dictionary
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
		var cd_ov: ColorRect = w["cd_overlay"] as ColorRect
		var cd_l: Label = w["cd_lbl"] as Label
		var sb: StyleBoxFlat = w["stylebox"] as StyleBoxFlat

		if code == "5" or code == "6":
			var p_idef: Dictionary = DataDB.get_any_item_or_equip(sk_id)
			var is_talisman: bool = (str(p_idef.get("category", "")) == "talisman")
			var p_rem: float = 0.0 if is_talisman else combat_ctrl.pill_cooldown_timer
			cd_ov.visible = p_rem > 0.05
			cd_l.text = ("%.0fs" % p_rem) if p_rem > 0.05 else ""
			sb.border_color = Color("#74E0B8") if (is_talisman and combat_ctrl.stealth_timer > 0.0) else UIThemeBuilder.COL_BRONZE_DIM
			continue
		if sk_id == "" or code == "Z":
			cd_ov.visible = false
			cd_l.text = ""
			continue

		var sdef: Dictionary = DataDB.get_skill(sk_id)
		var sk_cd: float = float(cds.get(sk_id, 0.0))
		var eff_rem: float = maxf(sk_cd, gcd_rem if bool(sdef.get("uses_gcd", true)) else 0.0)
		cd_ov.visible = eff_rem > 0.05
		cd_l.text = ("%.1fs" % eff_rem) if eff_rem > 0.05 else ""

		# 五行相生连携或满气机合击闪烁高亮！
		var s_elem: String = str(sdef.get("element", "none"))
		var syn_ready: bool = false
		if seal_elem != "" and RtwpSimStep.ELEMENT_SYNERGY_MAP.has(seal_elem):
			var child_e: String = str((RtwpSimStep.ELEMENT_SYNERGY_MAP[seal_elem] as Dictionary).get("child", ""))
			syn_ready = (child_e == s_elem)
		if code == "G" and combat_ctrl.team_attunement >= 100.0:
			sb.border_color = Color("#74F0C2")
		elif syn_ready and eff_rem <= 0.05:
			sb.border_color = Color("#FCE088")
		elif code == "STUNT":
			sb.border_color = UIThemeBuilder.COL_BLUE_STUNT
		else:
			sb.border_color = UIThemeBuilder.COL_BRONZE_DIM

	# 同调气机槽刷新（脱战且气机为 0 时干净隐藏，入战或积攒气机后展开）
	_attunement_wrap.visible = combat_ctrl.in_combat or combat_ctrl.team_attunement >= 0.5
	if _attunement_wrap.visible:
		var att_r: float = clampf(combat_ctrl.team_attunement / RtwpSimStep.MAX_ATTUNEMENT, 0.0, 1.0)
		_attunement_fill.size.x = 352.0 * att_r
		_attunement_lbl.text = "%s: %d / 100%s" % [
			tr("TERM_ATTUNEMENT"),
			int(floor(combat_ctrl.team_attunement)),
			" 【可按 G 放合击！】" if combat_ctrl.team_attunement >= 100.0 and CampaignState.unlocked_bond_ultimates.has("ult_qinglian_sword") else ""
		]

	# 4. 顶部首领大框刷新
	if _tracked_boss != null and is_instance_valid(_tracked_boss) and _tracked_boss.alive:
		_boss_panel.visible = true
		_boss_title_lbl.text = "【首领】%s" % _tracked_boss.display_name
		var bhp_r: float = clampf(float(_tracked_boss.hp) / float(maxi(1, _tracked_boss.max_hp)), 0.0, 1.0)
		_boss_hp_fill.size.x = 576.0 * bhp_r
		_boss_hp_lbl.text = "%s  %d / %d" % [tr("TERM_HP"), _tracked_boss.hp, _tracked_boss.max_hp]

		if _tracked_boss.stagger_timer > 0.0:
			_boss_ward_fill.size.x = 576.0
			_boss_ward_fill.color = Color("#E8B858")
			_boss_ward_lbl.text = "【气机破绽 · 承伤+35%%】剩余 %.1fs" % _tracked_boss.stagger_timer
		else:
			var bw_r: float = clampf(_tracked_boss.ward_current / maxf(1.0, _tracked_boss.ward_max), 0.0, 1.0)
			_boss_ward_fill.size.x = 576.0 * bw_r
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
			_boss_cast_fill.color = Color("#D6A85A") if _tracked_boss.cast_interruptible else Color("#8E2822")
			_boss_cast_lbl.text = "%s %s (%.1fs)" % [
				"【琥珀金·按Q可断】" if _tracked_boss.cast_interruptible else "【暗红危招·速躲圈】",
				_tracked_boss.cast_skill_name,
				maxf(0.0, _tracked_boss.cast_duration - _tracked_boss.cast_progress)
			]
		else:
			_boss_cast_box.visible = false
	else:
		_boss_panel.visible = false

	_minimap_canvas.queue_redraw()


func _draw_minimap() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _minimap_canvas.size)
	# 宋明青灰绢本水墨底色 + 细暗格经纬
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

	# 1. 道路与庭院石板轮廓
	for rpoly: PackedVector2Array in _mm_roads:
		if rpoly.size() >= 3:
			var scaled_pts: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in rpoly:
				scaled_pts.append(Vector2(pt.x * scale_x, pt.y * scale_y))
			_minimap_canvas.draw_colored_polygon(scaled_pts, Color(0.36, 0.39, 0.37, 0.78))

	# 2. 重点亭台屋宇轮廓
	for brect: Rect2 in _mm_buildings:
		var srect: Rect2 = Rect2(
			Vector2(brect.position.x * scale_x, brect.position.y * scale_y),
			Vector2(maxf(8.0, brect.size.x * scale_x), maxf(6.0, brect.size.y * scale_y))
		)
		_minimap_canvas.draw_rect(srect, Color(0.54, 0.45, 0.34, 0.85), true)
		_minimap_canvas.draw_rect(srect, Color(0.82, 0.68, 0.44, 0.85), false, 1.0)

	# 3. 过图出口路标（错金三角印）
	for p_pt: Vector2 in _mm_portals:
		var mp: Vector2 = Vector2(clampf(p_pt.x * scale_x, 6.0, rect.size.x - 6.0), clampf(p_pt.y * scale_y, 6.0, rect.size.y - 6.0))
		_minimap_canvas.draw_rect(Rect2(mp - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), UIThemeBuilder.COL_BRONZE_GOLD, true)

	# 4. 引灵石碑（青玉菱形）
	for st_pt: Vector2 in _mm_steles:
		var sp: Vector2 = Vector2(st_pt.x * scale_x, st_pt.y * scale_y)
		var d_pts: PackedVector2Array = PackedVector2Array([
			sp + Vector2(0.0, -5.0),
			sp + Vector2(5.0, 0.0),
			sp + Vector2(0.0, 5.0),
			sp + Vector2(-5.0, 0.0),
		])
		_minimap_canvas.draw_colored_polygon(d_pts, Color("#62E0B8"))

	# 5. 友好 NPC（暖琥珀圆点）
	for npc: BattleActor in _mm_npcs:
		if is_instance_valid(npc):
			var np_pt: Vector2 = Vector2(npc.position.x * scale_x, npc.position.y * scale_y)
			_minimap_canvas.draw_circle(np_pt, 3.2, Color("#E8C06E"))

	# 6. 敌群（朱砂红点）
	for ea: BattleActor in combat_ctrl.enemy_actors:
		if is_instance_valid(ea) and ea.alive:
			var ep: Vector2 = Vector2(clampf(ea.position.x * scale_x, 4.0, rect.size.x - 4.0), clampf(ea.position.y * scale_y, 4.0, rect.size.y - 4.0))
			_minimap_canvas.draw_circle(ep, 4.8 if ea.is_boss else 3.2, UIThemeBuilder.COL_CINNABAR_RED)

	# 7. 当前镜头视野淡金框 + 主控角色翠玉主标
	if combat_ctrl.world_camera != null:
		var cam_c: Vector2 = combat_ctrl.world_camera.get_screen_center_position()
		var vp_sz: Vector2 = Vector2(1920.0 * scale_x, 1080.0 * scale_y)
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
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null
