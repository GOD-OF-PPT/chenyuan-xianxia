class_name NarrativeStage
extends Control
## 第三层叙事演出舞台（涵盖 Tier 2 宋明工笔半身立绘演剧台 + 雕花乌木手卷 + Tier 3 全屏 4 层视差动态绘卷 CG）
## 严格对齐 docs/design/14-narrative-design.md、21-ui-ux-spec.md 与闸门 3 样片 master_c_temple_stage.png：
## - 开启瞬间隐藏同级 CombatHud，调用 NotifyHub.set_narrative_exclusive(true) 清空残字、挂起 P3 轻签
## - 开启与换行触发 InputRouter 400ms 防连点锁；Space 键与战斗快捷键 100% 物理屏蔽！
## - 仅限 Enter 键或鼠标左键点击对话手卷推进；已读文本支持长按 Ctrl 快进；重打 Boss 自动跳过已读战前对白。

signal dialogue_action_triggered(action: Dictionary)
signal dialogue_finished(dialogue_id: String)

var audio_director: AudioDirector = null

## Tier 3 动态 CG 视差层
var _cg_root: Control
var _cg_layers: Array[TextureRect] = []
var _cg_caption_box: PanelContainer
var _cg_title_lbl: Label
var _cg_caption_lbl: Label
var _cg_active: bool = false
var _cg_standalone_only: bool = false
var _cg_anim_time: float = 0.0

## Tier 2 半身立绘演剧层与雕花乌木手卷层
var _stage_dimmer: ColorRect
var _stage_backdrop: TextureRect
var _stage_rain_canvas: Control
var _left_portrait: TextureRect
var _right_portrait: TextureRect
var _scroll_panel: PanelContainer
var _roller_left: PanelContainer
var _roller_right: PanelContainer
var _speaker_plaque: PanelContainer
var _speaker_lbl: Label
var _body_lbl: Label
var _hint_lbl: Label
var _choices_box: VBoxContainer

var _active_dialogue_id: String = ""
var _active_dialogue: Dictionary = {}
var _line_index: int = 0
var _is_already_read: bool = false
var _ctrl_ff_accum: float = 0.0
var _stage_fx_clock: float = 0.0
var _rain_seeds: Array[Vector3] = []

var _portrait_cache: Dictionary = {}
var _ui_tex_cache: Dictionary = {}
var _suppressed_hud: Control = null


func _ready() -> void:
	UIThemeBuilder.bind_full_rect(self)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	for i: int in range(64):
		var sx: float = fmod(float(i) * 137.5 + 41.0, 1920.0)
		var sy: float = fmod(float(i) * 89.3 + 17.0, 1080.0)
		var slen: float = 34.0 + float(i % 5) * 9.0
		_rain_seeds.append(Vector3(sx, sy, slen))

	_build_stage_dimmer_and_portraits()
	_build_bottom_scroll()
	_build_cg_overlay()

	InputRouter.dialogue_advance_requested.connect(_on_advance_input)


func _exit_tree() -> void:
	_set_sibling_hud_suppressed(false)
	_portrait_cache.clear()
	_ui_tex_cache.clear()
	_cg_layers.clear()


func _load_ui_tex(path: String) -> Texture2D:
	if _ui_tex_cache.has(path):
		return _ui_tex_cache[path] as Texture2D
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_ui_tex_cache[path] = tex
		return tex
	return null


func _set_sibling_hud_suppressed(suppressed: bool) -> void:
	if suppressed:
		if _suppressed_hud == null or not is_instance_valid(_suppressed_hud):
			var p: Node = get_parent()
			if p != null:
				for ch: Node in p.get_children():
					if ch is CombatHud:
						_suppressed_hud = ch as Control
						break
		if _suppressed_hud != null and is_instance_valid(_suppressed_hud):
			_suppressed_hud.call("set_interact_prompt", "")
			_suppressed_hud.visible = false
	else:
		if _suppressed_hud != null and is_instance_valid(_suppressed_hud):
			_suppressed_hud.visible = true
		_suppressed_hud = null


func _is_temple_stage_dialogue(dlg_id: String) -> bool:
	if dlg_id == "dlg_ch01_temple_clash" or dlg_id == "dlg_ch01_temple_aftermath":
		return true
	if dlg_id == "dlg_night_talk_1" and CampaignState.current_zone_id == "qinglan_pass":
		return true
	return false


func _build_stage_dimmer_and_portraits() -> void:
	_stage_dimmer = ColorRect.new()
	_stage_dimmer.color = Color(0.05, 0.06, 0.07, 0.64)
	_stage_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage_dimmer)
	UIThemeBuilder.bind_full_rect(_stage_dimmer)

	_stage_backdrop = TextureRect.new()
	_stage_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_stage_backdrop.texture = _load_ui_tex("res://assets/ui/frames/narrative_roller_temple_backdrop.png")
	_stage_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_backdrop.visible = false
	add_child(_stage_backdrop)

	_stage_rain_canvas = Control.new()
	_stage_rain_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_rain_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_rain_canvas.visible = false
	_stage_rain_canvas.draw.connect(_draw_stage_rain_and_lantern_glow)
	add_child(_stage_rain_canvas)

	# 左右 1024x1280 宋明工笔半身立绘位（严格 4:5 等比，下摆自然露出乌木手卷底轴之下）
	_left_portrait = TextureRect.new()
	_left_portrait.anchor_left = 0.0
	_left_portrait.anchor_right = 0.0
	_left_portrait.anchor_top = 1.0
	_left_portrait.anchor_bottom = 1.0
	_left_portrait.offset_left = 18.0
	_left_portrait.offset_right = 898.0
	_left_portrait.offset_top = -1100.0
	_left_portrait.offset_bottom = 0.0
	_left_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_portrait)

	_right_portrait = TextureRect.new()
	_right_portrait.anchor_left = 1.0
	_right_portrait.anchor_right = 1.0
	_right_portrait.anchor_top = 1.0
	_right_portrait.anchor_bottom = 1.0
	_right_portrait.offset_left = -898.0
	_right_portrait.offset_right = -18.0
	_right_portrait.offset_top = -1100.0
	_right_portrait.offset_bottom = 0.0
	_right_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_portrait)


func _draw_stage_rain_and_lantern_glow() -> void:
	if _stage_rain_canvas == null or not _stage_rain_canvas.visible:
		return
	var flicker: float = 0.86 + 0.14 * sin(_stage_fx_clock * 3.1)
	_stage_rain_canvas.draw_circle(Vector2(1096.0, 326.0), 68.0, Color(0.95, 0.68, 0.30, 0.08 * flicker))
	_stage_rain_canvas.draw_circle(Vector2(1410.0, 326.0), 68.0, Color(0.95, 0.68, 0.30, 0.08 * flicker))
	var shift: float = 0.0 if SaveManager.reduced_motion else (_stage_fx_clock * 460.0)
	var r_col: Color = Color(0.76, 0.84, 0.88, 0.16)
	for seed_v: Vector3 in _rain_seeds:
		var rx: float = fposmod(seed_v.x - shift * 0.20, 1920.0)
		var ry: float = fposmod(seed_v.y + shift, 1080.0)
		_stage_rain_canvas.draw_line(Vector2(rx, ry), Vector2(rx - seed_v.z * 0.20, ry + seed_v.z), r_col, 1.15)


func _build_bottom_scroll() -> void:
	_scroll_panel = PanelContainer.new()
	_scroll_panel.anchor_left = 0.5
	_scroll_panel.anchor_right = 0.5
	_scroll_panel.anchor_top = 1.0
	_scroll_panel.anchor_bottom = 1.0
	_scroll_panel.offset_left = -866.0
	_scroll_panel.offset_right = 866.0
	_scroll_panel.offset_top = -328.0
	_scroll_panel.offset_bottom = -54.0
	_scroll_panel.focus_mode = Control.FOCUS_NONE

	var scroll_tex: Texture2D = _load_ui_tex("res://assets/ui/frames/narrative_roller_scroll_bg.png")
	if scroll_tex != null:
		var sb_scroll: StyleBoxTexture = StyleBoxTexture.new()
		sb_scroll.texture = scroll_tex
		sb_scroll.texture_margin_left = 48.0
		sb_scroll.texture_margin_right = 48.0
		sb_scroll.texture_margin_top = 44.0
		sb_scroll.texture_margin_bottom = 44.0
		sb_scroll.content_margin_left = 86.0
		sb_scroll.content_margin_right = 86.0
		sb_scroll.content_margin_top = 50.0
		sb_scroll.content_margin_bottom = 32.0
		_scroll_panel.add_theme_stylebox_override("panel", sb_scroll)
	else:
		var xuan_sb: StyleBoxFlat = UIThemeBuilder.make_xuan_paper_box(Color("#5C462C"), 4)
		xuan_sb.content_margin_left = 64.0
		xuan_sb.content_margin_right = 64.0
		xuan_sb.content_margin_top = 42.0
		xuan_sb.content_margin_bottom = 28.0
		_scroll_panel.add_theme_stylebox_override("panel", xuan_sb)
	add_child(_scroll_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_scroll_panel.add_child(vb)

	_body_lbl = Label.new()
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(1540.0, 96.0)
	_body_lbl.add_theme_font_override("font", UIThemeBuilder.get_regular_font())
	_body_lbl.add_theme_font_size_override("font_size", 24)
	_body_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	_body_lbl.add_theme_constant_override("line_spacing", 8)
	vb.add_child(_body_lbl)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	_choices_box.visible = false
	vb.add_child(_choices_box)

	_hint_lbl = Label.new()
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl.add_theme_font_override("font", UIThemeBuilder.get_regular_font())
	_hint_lbl.add_theme_font_size_override("font_size", 17)
	_hint_lbl.add_theme_color_override("font_color", Color("#5B452B"))
	vb.add_child(_hint_lbl)

	# 左右两侧竖向雕花乌木卷轴端头（x: 34..1886，完全落在 20..1900 安全区内！）
	_roller_left = _create_roller_cap_panel("res://assets/ui/frames/narrative_roller_cap_l.png", -926.0, -846.0)
	add_child(_roller_left)
	_roller_right = _create_roller_cap_panel("res://assets/ui/frames/narrative_roller_cap_r.png", 846.0, 926.0)
	add_child(_roller_right)

	# 顶部海棠耳错金乌木说话人铭牌（随左右说话方动态停靠！）
	_speaker_plaque = PanelContainer.new()
	_speaker_plaque.anchor_left = 0.5
	_speaker_plaque.anchor_right = 0.5
	_speaker_plaque.anchor_top = 1.0
	_speaker_plaque.anchor_bottom = 1.0
	_speaker_plaque.offset_left = -798.0
	_speaker_plaque.offset_right = -418.0
	_speaker_plaque.offset_top = -358.0
	_speaker_plaque.offset_bottom = -296.0
	_speaker_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_plaque.focus_mode = Control.FOCUS_NONE

	var plaque_tex: Texture2D = _load_ui_tex("res://assets/ui/frames/narrative_roller_plaque_bg.png")
	if plaque_tex != null:
		var sb_plq: StyleBoxTexture = StyleBoxTexture.new()
		sb_plq.texture = plaque_tex
		sb_plq.texture_margin_left = 44.0
		sb_plq.texture_margin_right = 44.0
		sb_plq.texture_margin_top = 14.0
		sb_plq.texture_margin_bottom = 16.0
		sb_plq.content_margin_left = 28.0
		sb_plq.content_margin_right = 28.0
		sb_plq.content_margin_top = 8.0
		sb_plq.content_margin_bottom = 10.0
		_speaker_plaque.add_theme_stylebox_override("panel", sb_plq)
	else:
		_speaker_plaque.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.12, 0.10, 0.98), UIThemeBuilder.COL_BRONZE_GOLD, 2, 5))
	add_child(_speaker_plaque)

	_speaker_lbl = Label.new()
	_speaker_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speaker_lbl.add_theme_font_override("font", UIThemeBuilder.get_bold_font())
	_speaker_lbl.add_theme_font_size_override("font_size", 22)
	_speaker_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	_speaker_plaque.add_child(_speaker_lbl)

	# 仅允许鼠标左键点击手卷推进（防呆：400ms 保护锁生效，Space 100% 屏蔽）
	_scroll_panel.gui_input.connect(_on_scroll_gui_input)
	_roller_left.gui_input.connect(_on_scroll_gui_input)
	_roller_right.gui_input.connect(_on_scroll_gui_input)


func _create_roller_cap_panel(tex_path: String, off_l: float, off_r: float) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 1.0
	pc.anchor_bottom = 1.0
	pc.offset_left = off_l
	pc.offset_right = off_r
	pc.offset_top = -384.0
	pc.offset_bottom = -12.0
	pc.focus_mode = Control.FOCUS_NONE
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var tex: Texture2D = _load_ui_tex(tex_path)
	if tex != null:
		var sb: StyleBoxTexture = StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_top = 64.0
		sb.texture_margin_bottom = 52.0
		pc.add_theme_stylebox_override("panel", sb)
	else:
		pc.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color("#1C1815"), UIThemeBuilder.COL_BRONZE_DIM, 2, 6))
	return pc


func _on_scroll_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and InputRouter.can_advance_dialogue():
			_on_advance_input()


func _set_scroll_chrome_visible(vis: bool) -> void:
	_scroll_panel.visible = vis
	_roller_left.visible = vis
	_roller_right.visible = vis
	_speaker_plaque.visible = vis


func _apply_scroll_geometry(choice_mode: bool, spk_dock_right: bool) -> void:
	if choice_mode:
		_scroll_panel.offset_top = -436.0
		_scroll_panel.offset_bottom = -46.0
		_roller_left.offset_top = -492.0
		_roller_left.offset_bottom = -6.0
		_roller_right.offset_top = -492.0
		_roller_right.offset_bottom = -6.0
		_speaker_plaque.offset_top = -466.0
		_speaker_plaque.offset_bottom = -404.0
	else:
		_scroll_panel.offset_top = -328.0
		_scroll_panel.offset_bottom = -54.0
		_roller_left.offset_top = -384.0
		_roller_left.offset_bottom = -12.0
		_roller_right.offset_top = -384.0
		_roller_right.offset_bottom = -12.0
		_speaker_plaque.offset_top = -358.0
		_speaker_plaque.offset_bottom = -296.0

	if spk_dock_right:
		_speaker_plaque.offset_left = 418.0
		_speaker_plaque.offset_right = 798.0
	else:
		_speaker_plaque.offset_left = -798.0
		_speaker_plaque.offset_right = -418.0


func _build_cg_overlay() -> void:
	_cg_root = Control.new()
	_cg_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cg_root.visible = false
	add_child(_cg_root)

	var layer_paths: Array[String] = [
		"res://assets/cg/cg_ch01_layer0_sky.png",
		"res://assets/cg/cg_ch01_layer1_temple.png",
		"res://assets/cg/cg_ch01_layer2_aura.png",
		"res://assets/cg/cg_ch01_layer3_rain_sword.png",
	]
	for p: String in layer_paths:
		var tr_node: TextureRect = TextureRect.new()
		tr_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr_node.texture = _load_ui_tex(p)
		tr_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cg_root.add_child(tr_node)
		_cg_layers.append(tr_node)

	_cg_caption_box = PanelContainer.new()
	_cg_caption_box.anchor_left = 0.5
	_cg_caption_box.anchor_right = 0.5
	_cg_caption_box.anchor_top = 1.0
	_cg_caption_box.anchor_bottom = 1.0
	_cg_caption_box.offset_left = -560.0
	_cg_caption_box.offset_right = 560.0
	_cg_caption_box.offset_top = -175.0
	_cg_caption_box.offset_bottom = -42.0
	_cg_caption_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.09, 0.08, 0.08, 0.88), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_cg_root.add_child(_cg_caption_box)

	var cvb: VBoxContainer = VBoxContainer.new()
	cvb.alignment = BoxContainer.ALIGNMENT_CENTER
	cvb.add_theme_constant_override("separation", 8)
	_cg_caption_box.add_child(cvb)

	_cg_title_lbl = Label.new()
	_cg_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cg_title_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_HEADER)
	_cg_title_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	cvb.add_child(_cg_title_lbl)

	_cg_caption_lbl = Label.new()
	_cg_caption_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cg_caption_lbl.add_theme_font_size_override("font_size", 20)
	cvb.add_child(_cg_caption_lbl)

	_cg_root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and InputRouter.can_advance_dialogue():
				_dismiss_cg_step()
	)


func _process(delta: float) -> void:
	if not visible:
		return

	if _stage_rain_canvas != null and _stage_rain_canvas.visible and not SaveManager.reduced_motion:
		_stage_fx_clock += delta
		_stage_rain_canvas.queue_redraw()

	if _cg_active and not SaveManager.reduced_motion:
		_cg_anim_time += delta
		var wave: float = sin(_cg_anim_time * 1.4)
		if _cg_layers.size() >= 4:
			_cg_layers[1].scale = Vector2(1.02, 1.02)
			_cg_layers[1].position = Vector2(-12.0 + wave * 6.0, -8.0)
			_cg_layers[2].modulate.a = 0.65 + 0.35 * sin(_cg_anim_time * 2.6)
			_cg_layers[3].position = Vector2(wave * -10.0, 0.0)

	# 已读文本支持长按 Ctrl 快进
	if not _cg_active and _is_already_read and not _choices_box.visible and Input.is_key_pressed(KEY_CTRL):
		_ctrl_ff_accum += delta
		if _ctrl_ff_accum >= 0.14:
			_ctrl_ff_accum = 0.0
			_advance_line()


func start_dialogue(dialogue_id: String, force_replay: bool = false) -> void:
	var ddef: Dictionary = DataDB.get_dialogue(dialogue_id)
	if ddef.is_empty():
		return

	var already_read: bool = CampaignState.read_dialogues.has(dialogue_id)
	# 首领战重开自动跳过已读战前重复台词（14-narrative-design.md 第 6 节）
	if already_read and not force_replay and dialogue_id == "dlg_ch01_wolf_king_intro":
		_run_action_list(ddef.get("on_finish_actions", []) as Array)
		dialogue_finished.emit(dialogue_id)
		return

	_active_dialogue_id = dialogue_id
	_active_dialogue = ddef
	_line_index = 0
	_is_already_read = already_read

	_set_sibling_hud_suppressed(true)
	NotifyHub.set_narrative_exclusive(true)
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	visible = true

	var use_temple_bg: bool = _is_temple_stage_dialogue(dialogue_id) and (_stage_backdrop.texture != null)
	_stage_backdrop.visible = use_temple_bg
	_stage_rain_canvas.visible = use_temple_bg
	if use_temple_bg:
		_stage_rain_canvas.queue_redraw()

	var cg_id: String = str(ddef.get("trigger_cg_id", ""))
	if cg_id != "" and (force_replay or not CampaignState.unlocked_cgs.has(cg_id)):
		if not CampaignState.unlocked_cgs.has(cg_id):
			CampaignState.unlocked_cgs.append(cg_id)
		_show_cg_card(cg_id, false)
		return

	_cg_active = false
	_cg_root.visible = false
	_set_scroll_chrome_visible(true)
	_render_current_line()


func play_standalone_cg(cg_id: String) -> void:
	_set_sibling_hud_suppressed(true)
	NotifyHub.set_narrative_exclusive(true)
	InputRouter.set_mode(InputRouter.MODE_CUTSCENE_CG)
	visible = true
	_stage_backdrop.visible = false
	_stage_rain_canvas.visible = false
	_set_scroll_chrome_visible(false)
	_left_portrait.texture = null
	_right_portrait.texture = null
	_show_cg_card(cg_id, true)


func _show_cg_card(cg_id: String, standalone: bool) -> void:
	_cg_active = true
	_cg_standalone_only = standalone
	_cg_anim_time = 0.0
	var cg_def: Dictionary = DataDB.cg_gallery.get(cg_id, {}) as Dictionary
	_cg_title_lbl.text = DataDB.loc(str(cg_def.get("title_key", "CG_CH01_TEMPLE_TITLE")))
	_cg_caption_lbl.text = DataDB.loc(str(cg_def.get("caption_key", "CG_CH01_TEMPLE_CAPTION"))) + "\n\n【按 Enter 或左键点击继续】"
	_cg_root.visible = true
	_set_scroll_chrome_visible(false)
	InputRouter.trigger_dialogue_lock()


func _dismiss_cg_step() -> void:
	_cg_active = false
	_cg_root.visible = false
	if _cg_standalone_only:
		_close_stage()
		return
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	_set_scroll_chrome_visible(true)
	_render_current_line()


func _on_advance_input() -> void:
	if not visible or not InputRouter.can_advance_dialogue():
		return
	if _cg_active:
		_dismiss_cg_step()
		return
	if _choices_box.visible:
		# 抉择分支阶段必须由玩家主动点选具体道心选项，严禁盲按 Enter 误选！
		return
	InputRouter.trigger_dialogue_lock()
	_advance_line()


func _advance_line() -> void:
	var lines: Array = _active_dialogue.get("lines", []) as Array
	_line_index += 1
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_page_turn", AudioDirector.TIER_B, true)
	if _line_index < lines.size():
		_render_current_line()
		return

	# 台词播完：检查是否有问道抉择项
	var choices: Array = _active_dialogue.get("choices", []) as Array
	if not choices.is_empty():
		_present_choices(choices)
		return

	_finish_current_dialogue()


func _format_speaker_title(spk_key: String) -> String:
	var base_name: String = DataDB.loc(spk_key)
	match spk_key:
		"CHAR_PEI_NAME":
			var p_title: String = DataDB.loc("CHAR_PEI_TITLE").split(" · ")[0].replace("宗", "")
			return "%s · %s" % [base_name, p_title]
		"CHAR_SHEN_NAME":
			var s_title: String = DataDB.loc("CHAR_SHEN_TITLE").split(" · ")[0]
			return "%s · %s" % [base_name, s_title]
		"CHAR_GU_NAME":
			var g_title: String = DataDB.loc("CHAR_GU_TITLE").split(" · ")[0]
			return "%s · %s" % [base_name, g_title]
		"BOSS_WOLF_KING_NAME":
			var b_title: String = DataDB.loc("BOSS_WOLF_KING_TITLE").split(" · ")[0]
			return "%s · %s" % [base_name, b_title]
	return base_name


func _wrap_scroll_lines(raw_text: String, max_chars: int = 34) -> String:
	var clean_t: String = raw_text.replace("\n", "")
	var total_len: int = clean_t.length()
	if total_len <= max_chars:
		return clean_t
	# 优先在靠近中段的中文标点处优雅断为两行（严格 <= 2 行且每行 <= max_chars）
	var puncts: String = "，。？！；：、"
	var best_idx: int = -1
	var target_mid: int = mini(max_chars, int(ceil(float(total_len) * 0.52)))
	var min_idx: int = maxi(8, target_mid - 12)
	if total_len <= max_chars * 2:
		min_idx = maxi(min_idx, total_len - max_chars)
	var max_search: int = mini(total_len - 4, max_chars)
	for i: int in range(maxi(0, min_idx - 1), max_search):
		var split_at: int = i + 1
		if split_at <= max_chars and (total_len > max_chars * 2 or (total_len - split_at) <= max_chars):
			if puncts.contains(clean_t.substr(i, 1)):
				best_idx = split_at
	if best_idx < 0:
		var mid_fb: int = int(ceil(float(total_len) * 0.5))
		if total_len <= max_chars * 2:
			best_idx = clampi(mid_fb, total_len - max_chars, max_chars)
		else:
			best_idx = mini(max_chars, mid_fb)
	return clean_t.substr(0, best_idx) + "\n" + clean_t.substr(best_idx)


func _render_current_line() -> void:
	var lines: Array = _active_dialogue.get("lines", []) as Array
	if _line_index < 0 or _line_index >= lines.size():
		return
	var ln: Dictionary = lines[_line_index] as Dictionary
	_choices_box.visible = false
	_body_lbl.visible = true

	var spk_key: String = str(ln.get("speaker_key", ""))
	var lp_id: String = str(ln.get("left_portrait", ""))
	var lp_ex: String = str(ln.get("left_expr", "calm"))
	var rp_id: String = str(ln.get("right_portrait", ""))
	var rp_ex: String = str(ln.get("right_expr", "calm"))

	_left_portrait.texture = _load_portrait(lp_id, lp_ex)
	_right_portrait.texture = _load_portrait(rp_id, rp_ex)

	var spk_is_left: bool = _matches_speaker(spk_key, lp_id)
	var spk_is_right: bool = _matches_speaker(spk_key, rp_id)
	var dock_right: bool = spk_is_right and not spk_is_left

	_apply_scroll_geometry(false, dock_right)
	_speaker_lbl.text = _format_speaker_title(spk_key)
	_body_lbl.text = _wrap_scroll_lines(DataDB.loc(str(ln.get("text_key", ""))), 34)
	_hint_lbl.text = tr("UI_BTN_ENTER_CONTINUE") + ("  |  按住 Ctrl 快进已读" if _is_already_read else "")

	# 当前说话方明亮微抬，聆听方温和保留工笔面部与衣纹层次（对齐 master_c_temple_stage.png）
	var lift_l: float = -8.0 if (spk_is_left and not SaveManager.reduced_motion) else 0.0
	var lift_r: float = -8.0 if (spk_is_right and not SaveManager.reduced_motion) else 0.0
	_left_portrait.offset_top = -1100.0 + lift_l
	_left_portrait.offset_bottom = lift_l
	_right_portrait.offset_top = -1100.0 + lift_r
	_right_portrait.offset_bottom = lift_r

	_left_portrait.modulate = Color.WHITE if (spk_is_left or rp_id == "") else Color(0.86, 0.87, 0.90, 0.98)
	_right_portrait.modulate = Color.WHITE if spk_is_right else Color(0.86, 0.87, 0.90, 0.98)


func _present_choices(choices: Array) -> void:
	for ch: Node in _choices_box.get_children():
		ch.queue_free()
	_choices_box.visible = true
	var spk_right_now: bool = _speaker_plaque.offset_left > 0.0
	_apply_scroll_geometry(true, spk_right_now)
	_hint_lbl.text = "请审慎择定道心去向（仅玩家鼠标左键点击生效）"
	InputRouter.trigger_dialogue_lock()

	for raw_c: Variant in choices:
		if not (raw_c is Dictionary):
			continue
		var cdict: Dictionary = raw_c as Dictionary
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.button_mask = MOUSE_BUTTON_MASK_LEFT
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var title_s: String = DataDB.loc(str(cdict.get("label_key", "")))
		var desc_s: String = DataDB.loc(str(cdict.get("desc_key", "")))
		btn.text = "◆ %s\n   %s" % [title_s, desc_s]
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
		btn.add_theme_color_override("font_hover_color", UIThemeBuilder.COL_BRONZE_GOLD)
		var sb_norm: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color("#231E1A"), UIThemeBuilder.COL_BRONZE_DIM, 2, 4)
		sb_norm.content_margin_left = 18.0
		sb_norm.content_margin_right = 18.0
		sb_norm.content_margin_top = 8.0
		sb_norm.content_margin_bottom = 8.0
		var sb_hov: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color("#332B23"), UIThemeBuilder.COL_BRONZE_GOLD, 2, 4)
		sb_hov.content_margin_left = 18.0
		sb_hov.content_margin_right = 18.0
		sb_hov.content_margin_top = 8.0
		sb_hov.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override("normal", sb_norm)
		btn.add_theme_stylebox_override("hover", sb_hov)
		btn.add_theme_stylebox_override("pressed", sb_hov)

		var acts: Array = cdict.get("actions", []) as Array
		btn.pressed.connect(func() -> void:
			if not InputRouter.can_advance_dialogue():
				return
			if audio_director != null:
				audio_director.play_sfx("sfx_ui_seal_stamp", AudioDirector.TIER_A, true)
			_finish_current_dialogue(acts)
		)
		_choices_box.add_child(btn)


func _finish_current_dialogue(choice_actions: Array = []) -> void:
	var finished_id: String = _active_dialogue_id
	CampaignState.read_dialogues[finished_id] = true
	var base_actions: Array = _active_dialogue.get("on_finish_actions", []) as Array
	var chained_dlg: String = ""

	for raw_a: Variant in base_actions:
		if raw_a is Dictionary:
			var a: Dictionary = raw_a as Dictionary
			if str(a.get("type", "")) == "play_dialogue":
				chained_dlg = str(a.get("id", ""))
			else:
				dialogue_action_triggered.emit(a)

	for raw_ca: Variant in choice_actions:
		if raw_ca is Dictionary:
			var ca: Dictionary = raw_ca as Dictionary
			if str(ca.get("type", "")) == "play_dialogue":
				chained_dlg = str(ca.get("id", ""))
			else:
				dialogue_action_triggered.emit(ca)

	if chained_dlg != "":
		start_dialogue(chained_dlg, false)
		return

	_close_stage()
	dialogue_finished.emit(finished_id)


func _run_action_list(actions: Array) -> void:
	for raw_a: Variant in actions:
		if raw_a is Dictionary:
			dialogue_action_triggered.emit(raw_a as Dictionary)


func _close_stage() -> void:
	visible = false
	_cg_active = false
	_cg_root.visible = false
	_stage_backdrop.visible = false
	_stage_rain_canvas.visible = false
	_choices_box.visible = false
	_set_sibling_hud_suppressed(false)
	NotifyHub.set_narrative_exclusive(false)
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)


func _matches_speaker(speaker_key: String, portrait_id: String) -> bool:
	if portrait_id == "":
		return false
	if speaker_key == "CHAR_GU_NAME" and portrait_id == "gu_changqing":
		return true
	if speaker_key == "CHAR_SHEN_NAME" and portrait_id == "shen_qinghe":
		return true
	if speaker_key == "CHAR_PEI_NAME" and portrait_id == "pei_zhao":
		return true
	if speaker_key == "BOSS_WOLF_KING_NAME" and portrait_id == "mist_wolf_king":
		return true
	if speaker_key == "ENEMY_ROGUE_NAME" and portrait_id == "npc_peddler":
		return true
	if speaker_key.begins_with("NPC_") and portrait_id.begins_with("npc_"):
		return true
	return false


func _load_portrait(pid: String, expr: String) -> Texture2D:
	if pid == "":
		return null
	var p1: String = "res://assets/portraits/%s_%s.png" % [pid, expr]
	var p2: String = "res://assets/portraits/%s_calm.png" % pid
	var target: String = p1 if ResourceLoader.exists(p1) else p2
	if _portrait_cache.has(target):
		return _portrait_cache[target] as Texture2D
	if ResourceLoader.exists(target):
		var tex: Texture2D = load(target) as Texture2D
		_portrait_cache[target] = tex
		return tex
	return null
