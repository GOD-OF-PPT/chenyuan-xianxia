class_name NarrativeStage
extends Control
## 第三层叙事演出舞台（涵盖 Tier 2 高清半身立绘演剧台 + Tier 3 全屏 4 层视差动态绘卷 CG）
## 严格对齐 docs/design/14-narrative-design.md 与 21-ui-ux-spec.md：
## - 开启瞬间调用 NotifyHub.set_narrative_exclusive(true) 清空战斗残字、挂起 P3 轻签
## - 开启瞬间触发 InputRouter 400ms 防连点锁；Space 键 100% 屏蔽！
## - 仅限 Enter 键或鼠标左键点击对话卷轴推进；已读文本支持长按 Ctrl 快进；重打 Boss 自动跳过已读战前对白。

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

## Tier 2 半身立绘演剧层
var _stage_dimmer: ColorRect
var _left_portrait: TextureRect
var _right_portrait: TextureRect
var _scroll_panel: PanelContainer
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
var _portrait_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	_build_stage_dimmer_and_portraits()
	_build_cg_overlay()
	_build_bottom_scroll()

	InputRouter.dialogue_advance_requested.connect(_on_advance_input)


func _build_stage_dimmer_and_portraits() -> void:
	_stage_dimmer = ColorRect.new()
	_stage_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_dimmer.color = Color(0.05, 0.05, 0.05, 0.56)
	add_child(_stage_dimmer)

	# 左右 1024x1280 高清工笔半身立绘位
	_left_portrait = TextureRect.new()
	_left_portrait.anchor_top = 1.0
	_left_portrait.anchor_bottom = 1.0
	_left_portrait.offset_left = 70.0
	_left_portrait.offset_right = 710.0
	_left_portrait.offset_top = -860.0
	_left_portrait.offset_bottom = -60.0
	_left_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_portrait)

	_right_portrait = TextureRect.new()
	_right_portrait.anchor_left = 1.0
	_right_portrait.anchor_right = 1.0
	_right_portrait.anchor_top = 1.0
	_right_portrait.anchor_bottom = 1.0
	_right_portrait.offset_left = -710.0
	_right_portrait.offset_right = -70.0
	_right_portrait.offset_top = -860.0
	_right_portrait.offset_bottom = -60.0
	_right_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_portrait)


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
		if ResourceLoader.exists(p):
			tr_node.texture = load(p) as Texture2D
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


func _build_bottom_scroll() -> void:
	_scroll_panel = PanelContainer.new()
	_scroll_panel.anchor_left = 0.5
	_scroll_panel.anchor_right = 0.5
	_scroll_panel.anchor_top = 1.0
	_scroll_panel.anchor_bottom = 1.0
	_scroll_panel.offset_left = -780.0
	_scroll_panel.offset_right = 780.0
	_scroll_panel.offset_top = -275.0
	_scroll_panel.offset_bottom = -28.0
	var xuan_sb: StyleBoxFlat = UIThemeBuilder.make_xuan_paper_box(Color("#5C462C"), 4)
	xuan_sb.content_margin_left = 36.0
	xuan_sb.content_margin_right = 36.0
	xuan_sb.content_margin_top = 28.0
	xuan_sb.content_margin_bottom = 20.0
	_scroll_panel.add_theme_stylebox_override("panel", xuan_sb)
	add_child(_scroll_panel)

	# 顶部错金铭牌
	_speaker_plaque = PanelContainer.new()
	_speaker_plaque.anchor_left = 0.5
	_speaker_plaque.anchor_right = 0.5
	_speaker_plaque.anchor_top = 1.0
	_speaker_plaque.anchor_bottom = 1.0
	_speaker_plaque.offset_left = -740.0
	_speaker_plaque.offset_right = -450.0
	_speaker_plaque.offset_top = -302.0
	_speaker_plaque.offset_bottom = -256.0
	_speaker_plaque.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.12, 0.10, 0.98), UIThemeBuilder.COL_BRONZE_GOLD, 2, 5))
	add_child(_speaker_plaque)

	_speaker_lbl = Label.new()
	_speaker_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speaker_lbl.add_theme_font_size_override("font_size", 22)
	_speaker_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	_speaker_plaque.add_child(_speaker_lbl)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_scroll_panel.add_child(vb)

	_body_lbl = Label.new()
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.custom_minimum_size = Vector2(1460.0, 88.0)
	_body_lbl.add_theme_font_size_override("font_size", 23)
	_body_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	vb.add_child(_body_lbl)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	_choices_box.visible = false
	vb.add_child(_choices_box)

	_hint_lbl = Label.new()
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	_hint_lbl.add_theme_color_override("font_color", Color("#6B5133"))
	vb.add_child(_hint_lbl)

	# 仅允许鼠标左键点击对话栏推进（防呆：400ms 保护锁生效）
	_scroll_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and InputRouter.can_advance_dialogue():
				_on_advance_input()
	)


func _process(delta: float) -> void:
	if not visible:
		return

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

	NotifyHub.set_narrative_exclusive(true)
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	visible = true

	var cg_id: String = str(ddef.get("trigger_cg_id", ""))
	if cg_id != "" and (force_replay or not CampaignState.unlocked_cgs.has(cg_id)):
		if not CampaignState.unlocked_cgs.has(cg_id):
			CampaignState.unlocked_cgs.append(cg_id)
		_show_cg_card(cg_id, false)
		return

	_cg_active = false
	_cg_root.visible = false
	_scroll_panel.visible = true
	_speaker_plaque.visible = true
	_render_current_line()


func play_standalone_cg(cg_id: String) -> void:
	NotifyHub.set_narrative_exclusive(true)
	InputRouter.set_mode(InputRouter.MODE_CUTSCENE_CG)
	visible = true
	_scroll_panel.visible = false
	_speaker_plaque.visible = false
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
	_scroll_panel.visible = false
	_speaker_plaque.visible = false
	InputRouter.trigger_dialogue_lock()


func _dismiss_cg_step() -> void:
	_cg_active = false
	_cg_root.visible = false
	if _cg_standalone_only:
		_close_stage()
		return
	InputRouter.set_mode(InputRouter.MODE_DIALOGUE)
	_scroll_panel.visible = true
	_speaker_plaque.visible = true
	_render_current_line()


func _on_advance_input() -> void:
	if not visible:
		return
	if _cg_active:
		_dismiss_cg_step()
		return
	if _choices_box.visible:
		# 抉择分支阶段必须由玩家主动点选具体道心选项，严禁盲按 Enter 误选！
		return
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


func _render_current_line() -> void:
	var lines: Array = _active_dialogue.get("lines", []) as Array
	if _line_index < 0 or _line_index >= lines.size():
		return
	var ln: Dictionary = lines[_line_index] as Dictionary
	_choices_box.visible = false
	_body_lbl.visible = true

	var spk_key: String = str(ln.get("speaker_key", ""))
	_speaker_lbl.text = DataDB.loc(spk_key)
	_body_lbl.text = DataDB.loc(str(ln.get("text_key", "")))
	_hint_lbl.text = tr("UI_BTN_ENTER_CONTINUE") + ("  |  按住 Ctrl 快进已读" if _is_already_read else "")

	var lp_id: String = str(ln.get("left_portrait", ""))
	var lp_ex: String = str(ln.get("left_expr", "calm"))
	var rp_id: String = str(ln.get("right_portrait", ""))
	var rp_ex: String = str(ln.get("right_expr", "calm"))

	_left_portrait.texture = _load_portrait(lp_id, lp_ex)
	_right_portrait.texture = _load_portrait(rp_id, rp_ex)

	# 当前说话方高亮微抬，聆听方柔和压暗，呈现经典立绘演剧纵深感
	var spk_is_left: bool = _matches_speaker(spk_key, lp_id)
	var spk_is_right: bool = _matches_speaker(spk_key, rp_id)
	_left_portrait.modulate = Color.WHITE if (spk_is_left or rp_id == "") else Color(0.62, 0.62, 0.65, 0.95)
	_right_portrait.modulate = Color.WHITE if spk_is_right else Color(0.62, 0.62, 0.65, 0.95)


func _present_choices(choices: Array) -> void:
	for ch: Node in _choices_box.get_children():
		ch.queue_free()
	_choices_box.visible = true
	_hint_lbl.text = "请审慎择定道心去向（仅玩家主动点击生效）"
	InputRouter.trigger_dialogue_lock()

	for raw_c: Variant in choices:
		if not (raw_c is Dictionary):
			continue
		var cdict: Dictionary = raw_c as Dictionary
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var title_s: String = DataDB.loc(str(cdict.get("label_key", "")))
		var desc_s: String = DataDB.loc(str(cdict.get("desc_key", "")))
		btn.text = "◆ %s\n   %s" % [title_s, desc_s]
		btn.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
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
	_choices_box.visible = false
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
