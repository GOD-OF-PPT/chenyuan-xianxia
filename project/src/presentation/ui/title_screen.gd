extends Control
## 《尘缘问道》标题主画卷界面
## 呈现宋明《千里江山》青绿山水残破天门画卷、奏响《问道凡尘》古琴尺八主题曲，
## 支持三档难度新开局、继续最新存档、23槽道卷读取（含损坏零覆盖保护演示）、4总线器物设置与闸门3视觉母版鉴赏。

var _audio: AudioDirector
var _modals: WorldModals
var _notify: NotificationOverlay
var _selected_diff: String = "cultivation"
var _gallery_modal: ColorRect
var _gallery_tex: TextureRect
var _gallery_lbl: Label
var _gallery_idx: int = 0

const GALLERY_PLATES: Array[Array] = [
	["res://assets/ui/masters/master_a_tingyu_town.png", "样片 A · 听雨镇烟雨街巷（35°斜俯视青瓦药庐与古樟 Y-Sort）"],
	["res://assets/ui/masters/master_b_cangmu_rtwp.png", "样片 B · 苍木古窟无缝 RTwP 团战 HUD（木罡、琥珀金读条与朱砂危招圈）"],
	["res://assets/ui/masters/master_c_temple_stage.png", "样片 C · 破庙立绘演剧台（顾长青与裴照工笔半身立绘对峙）"],
	["res://assets/ui/masters/master_d_dao_casket.png", "样片 D · 万象道匣修行五维与五槽器物面板"],
]


func _ready() -> void:
	theme = UIThemeBuilder.get_global_theme()
	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	if ResourceLoader.exists("res://assets/ui/cursors/cursor_jade_pin.png"):
		Input.set_custom_mouse_cursor(load("res://assets/ui/cursors/cursor_jade_pin.png") as Texture2D, Input.CURSOR_ARROW, Vector2(2.0, 2.0))

	_audio = AudioDirector.new()
	add_child(_audio)
	_audio.play_special_bgm("res://assets/audio/bgm/bgm_title_wendao.ogg", "title")

	_build_visual_backdrop()
	_build_left_calligraphy_menu()
	_build_modals_and_gallery()


func _build_visual_backdrop() -> void:
	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://assets/cg/title_qianli_jiangshan.png"):
		bg_tex.texture = load("res://assets/cg/title_qianli_jiangshan.png") as Texture2D
	add_child(bg_tex)

	# 左侧留白墨晕衬底，确保大字号书法标题与按钮对比度 >= 9:1
	var left_shade: ColorRect = ColorRect.new()
	left_shade.offset_left = 0.0
	left_shade.offset_top = 0.0
	left_shade.offset_right = 760.0
	left_shade.offset_bottom = 1080.0
	left_shade.color = Color(0.08, 0.08, 0.07, 0.66)
	add_child(left_shade)


func _build_left_calligraphy_menu() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.offset_left = 88.0
	panel.offset_top = 110.0
	panel.offset_right = 670.0
	panel.offset_bottom = 965.0
	panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.11, 0.10, 0.09, 0.92), UIThemeBuilder.COL_BRONZE_GOLD, 2, 8))
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)

	var title_lbl: Label = Label.new()
	title_lbl.text = "《尘缘问道》"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 46)
	title_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	vb.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	var ver_str: String = str(ProjectSettings.get_setting("application/config/version", "0.1.5-slice"))
	sub_lbl.text = "%s · v%s" % [tr("GAME_SUBTITLE"), ver_str]
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color("#A9DFC8"))
	vb.add_child(sub_lbl)

	var verse_lbl: Label = Label.new()
	verse_lbl.text = "“天地不仁，以万物为刍狗；仙路既断，我自执剑叩天。”"
	verse_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verse_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verse_lbl.add_theme_font_size_override("font_size", 17)
	verse_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_PAPER)
	vb.add_child(verse_lbl)

	# 难度档位选择行
	var diff_title: Label = Label.new()
	diff_title.text = "◆ 开局问道难度（局内随时可调）："
	diff_title.add_theme_font_size_override("font_size", 17)
	diff_title.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	vb.add_child(diff_title)

	var diff_hb: HBoxContainer = HBoxContainer.new()
	diff_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_hb.add_theme_constant_override("separation", 8)
	vb.add_child(diff_hb)

	var diff_btns: Dictionary = {}
	for dpair: Array in [["ask_heart", "问心(剧情)"], ["cultivation", "修行(标准)"], ["tribulation", "渡劫(苦修)"]]:
		var dk: String = str(dpair[0])
		var db: Button = Button.new()
		db.focus_mode = Control.FOCUS_NONE
		db.text = ("★ " if dk == _selected_diff else "") + str(dpair[1])
		diff_btns[dk] = db
		db.pressed.connect(func() -> void:
			_selected_diff = dk
			for k_var: Variant in diff_btns.keys():
				var k: String = str(k_var)
				var b_ref: Button = diff_btns[k] as Button
				var base_t: String = b_ref.text.trim_prefix("★ ")
				b_ref.text = ("★ " if k == _selected_diff else "") + base_t
		)
		diff_hb.add_child(db)

	var has_save: bool = SaveManager.has_any_valid_save()
	if has_save:
		var cont_btn: Button = _make_main_btn(tr("UI_BTN_CONTINUE"))
		cont_btn.pressed.connect(func() -> void:
			var res: Dictionary = SaveManager.load_latest_valid_save()
			if bool(res.get("ok", false)):
				get_tree().change_scene_to_file("res://src/presentation/world/qinglan_world.tscn")
		)
		vb.add_child(cont_btn)

	var new_btn: Button = _make_main_btn(tr("UI_BTN_NEW_GAME"))
	new_btn.pressed.connect(func() -> void:
		_audio.play_sfx("sfx_ui_seal_stamp", AudioDirector.TIER_A, true)
		CampaignState.start_new_campaign(_selected_diff)
		get_tree().change_scene_to_file("res://src/presentation/world/qinglan_world.tscn")
	)
	vb.add_child(new_btn)

	var load_btn: Button = _make_main_btn(tr("UI_BTN_LOAD_GAME"))
	load_btn.pressed.connect(func() -> void: _modals.open_save_load_modal(false))
	vb.add_child(load_btn)

	var set_btn: Button = _make_main_btn(tr("UI_BTN_SETTINGS"))
	set_btn.pressed.connect(func() -> void: _modals.open_settings_modal())
	vb.add_child(set_btn)

	var gal_btn: Button = _make_main_btn("宋明青绿视觉母版鉴赏（闸门3）")
	gal_btn.pressed.connect(func() -> void: _open_gallery(0))
	vb.add_child(gal_btn)

	if OS.get_name() != "Web":
		var quit_btn: Button = _make_main_btn(tr("UI_BTN_QUIT"))
		quit_btn.pressed.connect(func() -> void: get_tree().quit())
		vb.add_child(quit_btn)

	var footer: Label = Label.new()
	footer.text = "纯正 PC 键鼠原生设计 · WASD 走位 / 右键平砍走位 / Space 战术凝时 / Q 秒断读条"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	footer.add_theme_color_override("font_color", Color("#9E968B"))
	vb.add_child(footer)


func _make_main_btn(txt: String) -> Button:
	var b: Button = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(460.0, 50.0)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _build_modals_and_gallery() -> void:
	_modals = WorldModals.new()
	_modals.audio_director = _audio
	_modals.is_standalone_on_title = true
	_modals.save_loaded_reload_zone.connect(func() -> void:
		get_tree().change_scene_to_file("res://src/presentation/world/qinglan_world.tscn")
	)
	add_child(_modals)

	_gallery_modal = ColorRect.new()
	_gallery_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gallery_modal.color = Color(0.04, 0.04, 0.04, 0.92)
	_gallery_modal.visible = false
	add_child(_gallery_modal)

	_gallery_tex = TextureRect.new()
	_gallery_tex.anchor_left = 0.5
	_gallery_tex.anchor_right = 0.5
	_gallery_tex.anchor_top = 0.5
	_gallery_tex.anchor_bottom = 0.5
	_gallery_tex.offset_left = -800.0
	_gallery_tex.offset_right = 800.0
	_gallery_tex.offset_top = -475.0
	_gallery_tex.offset_bottom = 425.0
	_gallery_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gallery_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gallery_modal.add_child(_gallery_tex)

	var bar: HBoxContainer = HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -640.0
	bar.offset_right = 640.0
	bar.offset_top = -82.0
	bar.offset_bottom = -24.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 18)
	_gallery_modal.add_child(bar)

	var prev_b: Button = Button.new()
	prev_b.text = "◀ 上一幅"
	prev_b.focus_mode = Control.FOCUS_NONE
	prev_b.pressed.connect(func() -> void: _open_gallery((_gallery_idx + GALLERY_PLATES.size() - 1) % GALLERY_PLATES.size()))
	bar.add_child(prev_b)

	_gallery_lbl = Label.new()
	_gallery_lbl.custom_minimum_size = Vector2(720.0, 40.0)
	_gallery_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gallery_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gallery_lbl.add_theme_font_size_override("font_size", 19)
	_gallery_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	bar.add_child(_gallery_lbl)

	var next_b: Button = Button.new()
	next_b.text = "下一幅 ▶"
	next_b.focus_mode = Control.FOCUS_NONE
	next_b.pressed.connect(func() -> void: _open_gallery((_gallery_idx + 1) % GALLERY_PLATES.size()))
	bar.add_child(next_b)

	var close_g: Button = Button.new()
	close_g.text = tr("UI_BTN_CLOSE")
	close_g.focus_mode = Control.FOCUS_NONE
	close_g.pressed.connect(func() -> void: _gallery_modal.visible = false)
	bar.add_child(close_g)

	_notify = NotificationOverlay.new()
	_notify.backup_recovery_chosen.connect(func(slot_id: String) -> void:
		var res: Dictionary = SaveManager.load_slot(slot_id, true)
		if bool(res.get("ok", false)):
			get_tree().change_scene_to_file("res://src/presentation/world/qinglan_world.tscn")
	)
	add_child(_notify)

	InputRouter.escape_pressed.connect(func() -> void:
		if _gallery_modal.visible:
			_gallery_modal.visible = false
		elif _modals.visible:
			_modals.close_modal()
	)


func _open_gallery(idx: int) -> void:
	_gallery_idx = idx
	var entry: Array = GALLERY_PLATES[idx]
	var p: String = str(entry[0])
	if ResourceLoader.exists(p):
		_gallery_tex.texture = load(p) as Texture2D
	_gallery_lbl.text = str(entry[1])
	_gallery_modal.visible = true
