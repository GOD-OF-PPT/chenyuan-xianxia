class_name DefeatRecapScroll
extends ColorRect
## 第三层【问道败北复盘卷轴】（严格对齐 docs/design/21-ui-ux-spec.md 第 4.2.1 节）
## 铁律：小队全灭绝不静默跳场景！精确列出最后 5 秒致死伤害链（明示是否漏断金条或未躲红圈），
## 给出针对性破局锦囊，由玩家主动选择【退回最近引灵石碑重整（战利品与地图进度 100% 保全）】或【读取旧卷】。

signal respawn_at_stele_requested()
signal open_load_menu_requested()

var _chain_vbox: VBoxContainer
var _tip_label: Label


func _ready() -> void:
	UIThemeBuilder.bind_full_rect(self)
	color = Color(0.05, 0.04, 0.04, 0.84)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	UIThemeBuilder.bind_full_rect(center)

	var scroll_panel: PanelContainer = PanelContainer.new()
	scroll_panel.custom_minimum_size = Vector2(780.0, 480.0)
	scroll_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_xuan_paper_box(Color("#6E4826"), 3))
	center.add_child(scroll_panel)

	var root_v: VBoxContainer = VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 16)
	scroll_panel.add_child(root_v)

	var header: Label = Label.new()
	header.text = "【问道败北 · 战局复盘卷轴】"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", UIThemeBuilder.FS_HEADER)
	header.add_theme_color_override("font_color", UIThemeBuilder.COL_CINNABAR_RED)
	root_v.add_child(header)

	var sub_title: Label = Label.new()
	sub_title.text = "◆ 致死溯源（最后 5 秒承伤链）："
	sub_title.add_theme_font_size_override("font_size", UIThemeBuilder.FS_SUBTITLE)
	sub_title.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	root_v.add_child(sub_title)

	var chain_card: PanelContainer = PanelContainer.new()
	chain_card.custom_minimum_size = Vector2(720.0, 185.0)
	chain_card.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.16, 0.14, 0.12, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 4))
	root_v.add_child(chain_card)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	chain_card.add_child(margin)

	_chain_vbox = VBoxContainer.new()
	_chain_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(_chain_vbox)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
	_tip_label.add_theme_color_override("font_color", Color("#23483E"))
	root_v.add_child(_tip_label)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	root_v.add_child(btn_row)

	var stele_btn: Button = Button.new()
	stele_btn.text = "退回最近【引灵石碑】重整（保留全部所得与进度）"
	stele_btn.focus_mode = Control.FOCUS_NONE
	stele_btn.pressed.connect(func() -> void:
		visible = false
		InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
		respawn_at_stele_requested.emit()
	)
	btn_row.add_child(stele_btn)

	var load_btn: Button = Button.new()
	load_btn.text = "读取道卷存档"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.pressed.connect(func() -> void:
		visible = false
		open_load_menu_requested.emit()
	)
	btn_row.add_child(load_btn)


func show_recap(recap_data: Dictionary) -> void:
	for ch: Node in _chain_vbox.get_children():
		ch.queue_free()

	var chain: Array = recap_data.get("fatal_chain", []) as Array
	if chain.is_empty():
		var empty_l: Label = Label.new()
		empty_l.text = "· 气血耗竭力战倒地。"
		empty_l.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
		_chain_vbox.add_child(empty_l)
	else:
		for raw_ev: Variant in chain:
			if not (raw_ev is Dictionary):
				continue
			var ev: Dictionary = raw_ev as Dictionary
			var tag: String = ""
			if bool(ev.get("was_interruptible_cast", false)):
				tag = "【琥珀金条·未打断】"
			elif bool(ev.get("was_ground_telegraph", false)):
				tag = "【朱砂危招圈·未走位】"
			var elem_badge: String = UIThemeBuilder.get_element_dual_badge(str(ev.get("element", "none")))
			var row_lbl: Label = Label.new()
			row_lbl.text = "· [%.1fs] %s 施展【%s】%s 对 %s 造成 %d 点 %s 伤害" % [
				float(ev.get("time_sec", 0.0)),
				str(ev.get("source_name", "")),
				str(ev.get("skill_name", "")),
				tag,
				str(ev.get("victim_name", "")),
				int(ev.get("damage", 0)),
				elem_badge,
			]
			row_lbl.add_theme_font_size_override("font_size", 17)
			row_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
			_chain_vbox.add_child(row_lbl)

	var tip_key: String = str(recap_data.get("tip_key", "RECAP_TIP_GENERAL"))
	var tip_param: String = str(recap_data.get("tip_param", ""))
	var raw_tip: String = tr(tip_key)
	_tip_label.text = (raw_tip % tip_param) if (tip_param != "" and raw_tip.contains("%s")) else raw_tip

	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	visible = true
