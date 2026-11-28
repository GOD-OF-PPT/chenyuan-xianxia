class_name DaoCasketPanel
extends ColorRect
## 第三层唯一功能菜单《万象道匣》（精装第 3 轮 · 摊开式线装旧宣古籍与器物化交互）
## 严格对齐 docs/design/21-ui-ux-spec.md 第 3.2 节与 Gate 3 样片 master_d_dao_casket.png：
## - 外框：雕花乌木如意纹深匣（#1C1815） + 顶部 4 大核心页签（C / N / B / J，未开放 P 灵兽袋彻底隐藏）
## - 书页：摊开式线装旧宣纸古籍（叠页毛边、装订丝线、折页中缝阴影、开卷与翻页动效 + sfx_ui_page_turn）
## - Tab 1【修行·兵甲 (C)】：左页水墨奇经八脉人体图与青玉璧穴位环 + 道基牌匾与破境二次确认；
##   中页 3+2 浮雕双线兵甲器物槽（空槽绘水墨剪影） + 5 条错金铜框五维潜能条；
##   右页细线分栏双曲递减实算详表 + 下半并排装备与 #8FD4E8 天青蓝字特技对比卡。
## - Tab 2/3/5（N/B/J）：双页古籍中缝排布，全树字号 >= 16px，全按钮 FOCUS_NONE 阻断 Space 误触。

signal replay_cg_requested(cg_id: String)
signal casket_closed()

const TEX_OUTER_FRAME: String = "res://assets/ui/frames/casket_ebony_outer_frame.png"
const TEX_TOME_SPREAD: String = "res://assets/ui/frames/casket_xuan_tome_spread.png"
const TEX_PAGE_FLIP_LEAF: String = "res://assets/ui/frames/casket_page_flip_leaf.png"
const TEX_MERIDIAN_FIG: String = "res://assets/ui/frames/casket_meridian_figure.png"
const TEX_SLOT_EMBOSSED: String = "res://assets/ui/frames/casket_slot_embossed.png"
const TEX_SLOT_SELECTED: String = "res://assets/ui/frames/casket_slot_selected.png"
const TEX_POT_BAR_BG: String = "res://assets/ui/frames/casket_potential_bar_bg.png"
const TEX_POT_BAR_FILL: String = "res://assets/ui/frames/casket_potential_bar_fill.png"
const TEX_TAB_ACTIVE: String = "res://assets/ui/frames/casket_tab_active.png"
const TEX_TAB_INACTIVE: String = "res://assets/ui/frames/casket_tab_inactive.png"
const TEX_ACUPOINT_JADE: String = "res://assets/ui/icons/casket_acupoint_jade.png"

var audio_director: AudioDirector = null
var active_tab: String = "cultivation"
var selected_char_id: String = "gu_changqing"
var selected_inv_filter: String = "all"
var selected_item_id: String = ""
var selected_journal_vol: String = "main"
var _selected_equip_slot: String = "pendant"
var _slot_manually_selected: bool = false

var _tab_buttons: Dictionary = {}
var _content_root: MarginContainer
var _tome_rig: Control = null
var _crease_overlay: _TomeCreaseOverlay = null
var _page_flip_veil: ColorRect = null
var _page_flip_leaf: TextureRect = null
var _active_tween: Tween = null
var _prev_focus_owner: Control = null
var _breakthrough_modal: CenterContainer = null
var _tex_cache: Dictionary = {}


class _TomeCreaseOverlay extends Control:
	var is_three_page: bool = true

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 100.0 or h < 100.0:
			return
		var hairline_outer: Color = Color(0.50, 0.40, 0.28, 0.56)
		var hairline_inner: Color = Color(0.62, 0.51, 0.37, 0.38)

		if is_three_page:
			# Tab 1 三折页装订阴影与丝线（local x = 604, 1144 -> global x = 712, 1252）
			_draw_fold_gutter(604.0, h)
			_draw_fold_gutter(1144.0, h)
			# 中页上下雕花细线内框（对齐 master_d_dao_casket.png）
			_draw_filigree_box(Rect2(624.0, 24.0, 500.0, 384.0), hairline_outer, hairline_inner)
			_draw_filigree_box(Rect2(624.0, 420.0, 500.0, 418.0), hairline_outer, hairline_inner)
			# 右页上下面板细线内框
			_draw_filigree_box(Rect2(1164.0, 24.0, 502.0, 368.0), hairline_outer, hairline_inner)
			_draw_filigree_box(Rect2(1164.0, 404.0, 502.0, 434.0), hairline_outer, hairline_inner)
		else:
			# Tabs N / B / J 对开古籍中缝书脊阴影与装订线（local x = 876 -> global x = 984）
			_draw_fold_gutter(876.0, h)
			_draw_filigree_box(Rect2(32.0, 22.0, 824.0, h - 44.0), hairline_outer, hairline_inner)
			_draw_filigree_box(Rect2(896.0, 22.0, 774.0, h - 44.0), hairline_outer, hairline_inner)

	func _draw_fold_gutter(cx: float, h: float) -> void:
		for band_i: int in range(7):
			var hw: float = float(7 - band_i) * 3.0
			var a: float = 0.026 * float(band_i + 1)
			draw_rect(Rect2(cx - hw, 14.0, hw * 2.0, h - 30.0), Color(0.24, 0.19, 0.14, a), true)
		draw_line(Vector2(cx, 14.0), Vector2(cx, h - 16.0), Color(0.32, 0.25, 0.18, 0.58), 1.6)
		draw_line(Vector2(cx + 1.5, 14.0), Vector2(cx + 1.5, h - 16.0), Color(0.92, 0.88, 0.79, 0.42), 1.0)
		for sy: float in [116.0, 312.0, 536.0, 734.0]:
			draw_line(Vector2(cx - 7.0, sy), Vector2(cx + 7.0, sy), Color(0.36, 0.29, 0.21, 0.72), 2.0)

	func _draw_filigree_box(r: Rect2, c_out: Color, c_in: Color) -> void:
		draw_rect(r, c_out, false, 1.5)
		draw_rect(r.grow(-4.0), c_in, false, 1.0)
		var cs: float = 12.0
		for corner: Vector2 in [
			r.position,
			Vector2(r.end.x - cs, r.position.y),
			Vector2(r.position.x, r.end.y - cs),
			Vector2(r.end.x - cs, r.end.y - cs),
		]:
			draw_rect(Rect2(corner + Vector2(2.0, 2.0), Vector2(cs - 4.0, cs - 4.0)), c_out, false, 1.2)


class _MeridianAcupointCanvas extends Control:
	var realm_id: String = "mortal"
	var foundation_grade: String = "solid"
	var meridian_bruise: int = 0
	var fig_offset: Vector2 = Vector2(42.0, 0.0)
	var pulse_clock: float = 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if not SaveManager.reduced_motion:
			pulse_clock += delta
			queue_redraw()

	func _draw() -> void:
		var pulse: float = 0.0 if SaveManager.reduced_motion else (0.5 + 0.5 * sin(pulse_clock * 2.6))
		var ox: float = fig_offset.x
		var oy: float = fig_offset.y
		var cx: float = ox + 224.0

		# 穴位局部坐标（精确映射 460x550 casket_meridian_figure.png 穴位中心，引线圆点与文字严格保持 8px 雅致间距）
		var pts: Array[Dictionary] = [
			{"id": "baihui", "pos": Vector2(cx, oy + 33.0), "r": 13.5, "label": tr("CASKET_ACU_BAIHUI"), "side": -1.0, "lx": ox + 104.0},
			{"id": "niwan", "pos": Vector2(cx, oy + 68.0), "r": 7.5, "label": tr("CASKET_ACU_NIWAN"), "side": 1.0, "lx": ox + 378.0},
			{"id": "shanzhong", "pos": Vector2(cx, oy + 222.0), "r": 16.5, "label": tr("CASKET_ACU_SHANZHONG"), "side": -1.0, "lx": ox + 50.0},
			{"id": "zhongwan", "pos": Vector2(cx, oy + 283.0), "r": 12.5, "label": tr("CASKET_ACU_ZHONGWAN"), "side": 1.0, "lx": ox + 382.0},
			{"id": "qihai", "pos": Vector2(cx, oy + 334.0), "r": 18.0, "label": tr("CASKET_ACU_QIHAI"), "side": -1.0, "lx": ox + 48.0},
			{"id": "dantian", "pos": Vector2(cx, oy + 383.0), "r": 19.5, "label": tr("CASKET_ACU_DANTIAN"), "side": 1.0, "lx": ox + 382.0},
			{"id": "laogong_l", "pos": Vector2(ox + 91.0, oy + 384.0), "r": 11.5, "label": tr("CASKET_ACU_LAOGONG"), "side": -1.0, "lx": ox - 10.0},
			{"id": "laogong_r", "pos": Vector2(ox + 357.0, oy + 384.0), "r": 11.5, "label": "", "side": 1.0, "lx": ox + 392.0},
		]

		# 境界动态周天灵脉流转（炼气一层贯通任督与双掌，炼气二层周天盈满）
		var flow_alpha: float = 0.34 if realm_id == "mortal" else (0.68 if realm_id == "qi_refining_1" else 0.88)
		var jade_line: Color = Color(0.27, 0.62, 0.50, flow_alpha)
		draw_line(Vector2(cx, oy + 116.0), Vector2(cx, oy + 383.0), jade_line, 3.0)
		if realm_id != "mortal":
			for side_f: float in [-1.0, 1.0]:
				var arm_chain: PackedVector2Array = PackedVector2Array([
					Vector2(cx, oy + 222.0),
					Vector2(cx + side_f * 44.0, oy + 154.0),
					Vector2(cx + side_f * 72.0, oy + 174.0),
					Vector2(cx + side_f * 91.0, oy + 254.0),
					Vector2(cx + side_f * 112.0, oy + 329.0),
					Vector2(cx + side_f * 133.0, oy + 384.0),
				])
				draw_polyline(arm_chain, Color(0.29, 0.66, 0.53, flow_alpha * 0.85), 2.4)

		# 青玉璧穴位环与呼吸灵晕（保证 (180..560, 215..760) 采样远超 24 像素，且零荧光色）
		for p_dict: Dictionary in pts:
			var p: Vector2 = p_dict["pos"] as Vector2
			var base_r: float = float(p_dict["r"])
			var aura_r: float = base_r + 3.0 + pulse * 2.8
			draw_circle(p, aura_r, Color(0.30, 0.66, 0.54, 0.24 + 0.10 * pulse))
			draw_arc(p, base_r * 0.78, 0.0, TAU, 28, Color(0.28, 0.63, 0.50, 0.92), maxf(2.4, base_r * 0.34))
			draw_arc(p, base_r * 0.95, 0.0, TAU, 28, Color(0.42, 0.74, 0.62, 0.85), 1.6)
			if foundation_grade == "flawless" and (str(p_dict["id"]) == "baihui" or str(p_dict["id"]) == "dantian"):
				draw_arc(p, base_r + 2.4, 0.0, TAU, 28, Color(0.80, 0.64, 0.34, 0.86), 1.8)
			if foundation_grade == "cracked" or meridian_bruise > 0:
				if str(p_dict["id"]) == "shanzhong" or str(p_dict["id"]) == "qihai":
					draw_line(p + Vector2(-9.0, -7.0), p + Vector2(8.0, 7.0), Color(0.69, 0.23, 0.18, 0.85), 2.0)

			# 古籍引线标注（全部采用 >= 16px NotoSerifCJKsc 简体正字，严禁任何生造伪字）
			var lbl_txt: String = str(p_dict["label"])
			if lbl_txt != "":
				var side_s: float = float(p_dict["side"])
				var lx: float = float(p_dict["lx"])
				var start_x: float = p.x + side_s * (base_r + 4.0)
				var end_x: float = lx + (36.0 if side_s < 0.0 else -6.0)
				var line_col: Color = Color(0.26, 0.21, 0.16, 0.72)
				var dot_col: Color = Color(0.32, 0.25, 0.18, 0.85)
				if str(p_dict["id"]) == "dantian":
					var corridor_x: float = ox + 310.0 # >=29px 避开躯干(323)与右掌(381)墨线
					var bend_y: float = oy + 450.0 # 指尖下方纯白宣纸区
					var dantian_pts: PackedVector2Array = PackedVector2Array([
						Vector2(start_x, p.y),
						Vector2(corridor_x, p.y),
						Vector2(corridor_x, bend_y),
						Vector2(end_x, bend_y),
					])
					draw_polyline(dantian_pts, line_col, 1.2)
					draw_circle(Vector2(end_x, bend_y), 2.0, dot_col)
				else:
					draw_line(Vector2(start_x, p.y), Vector2(end_x, p.y), line_col, 1.2)
					draw_circle(Vector2(end_x, p.y), 2.0, dot_col)


func _get_cached_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path] as Texture2D
	if path != "" and ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			_tex_cache[path] = t
			return t
	return null


func _make_tex_stylebox(
	path: String,
	ml: int,
	mt: int,
	mr: int,
	mb: int,
	cl: float,
	ct: float,
	cr: float,
	cb: float,
	fallback_bg: Color,
	fallback_border: Color
) -> StyleBox:
	var tex: Texture2D = _get_cached_tex(path)
	if tex != null:
		var sbt: StyleBoxTexture = StyleBoxTexture.new()
		sbt.texture = tex
		sbt.texture_margin_left = float(ml)
		sbt.texture_margin_top = float(mt)
		sbt.texture_margin_right = float(mr)
		sbt.texture_margin_bottom = float(mb)
		sbt.content_margin_left = cl
		sbt.content_margin_top = ct
		sbt.content_margin_right = cr
		sbt.content_margin_bottom = cb
		return sbt
	var fb: StyleBoxFlat = UIThemeBuilder.make_ebony_box(fallback_bg, fallback_border, 2, 4)
	fb.content_margin_left = cl
	fb.content_margin_top = ct
	fb.content_margin_right = cr
	fb.content_margin_bottom = cb
	return fb


func _ready() -> void:
	UIThemeBuilder.bind_full_rect(self)
	z_index = 20
	color = Color(0.04, 0.03, 0.03, 0.88)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	# 1. 全屏雕花乌木如意纹深匣外框（1920x1080，四角 mean_luma ~0.095 < 0.17）
	var outer_frame: TextureRect = TextureRect.new()
	outer_frame.name = "OuterEbonyFrame"
	outer_frame.position = Vector2.ZERO
	outer_frame.size = Vector2(1920.0, 1080.0)
	outer_frame.custom_minimum_size = Vector2(1920.0, 1080.0)
	outer_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outer_frame.stretch_mode = TextureRect.STRETCH_SCALE
	outer_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_frame.texture = _get_cached_tex(TEX_OUTER_FRAME)
	add_child(outer_frame)

	# 2. 顶部乌木错金页签槽（严格 4 个第一章已开放页签 C / N / B / J，隐藏 P）
	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.name = "TopHeaderBar"
	top_bar.position = Vector2(196.0, 34.0)
	top_bar.size = Vector2(1590.0, 62.0)
	top_bar.custom_minimum_size = Vector2(1590.0, 62.0)
	top_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_bar.add_theme_constant_override("separation", 18)
	add_child(top_bar)

	var tabs_meta: Array[Array] = [
		["cultivation", tr("HUD_TAB_CASKET_1")],
		["specialization", tr("HUD_TAB_CASKET_2")],
		["inventory", tr("HUD_TAB_CASKET_3")],
		["journal", tr("HUD_TAB_CASKET_5")],
	]
	for tpair: Array in tabs_meta:
		var tid: String = str(tpair[0])
		var tlabel: String = str(tpair[1])
		var tbtn: Button = Button.new()
		tbtn.text = tlabel
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.custom_minimum_size = Vector2(256.0, 56.0)
		tbtn.pressed.connect(func() -> void: open_tab(tid))
		top_bar.add_child(tbtn)
		_tab_buttons[tid] = tbtn

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var stones_badge: Label = Label.new()
	stones_badge.name = "StonesBadge"
	stones_badge.add_theme_font_size_override("font_size", UIThemeBuilder.FS_SUBTITLE)
	stones_badge.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	top_bar.add_child(stones_badge)

	var close_btn: Button = Button.new()
	close_btn.text = tr("UI_BTN_CLOSE")
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(170.0, 48.0)
	close_btn.pressed.connect(close_casket)
	top_bar.add_child(close_btn)

	# 3. 摊开式线装旧宣纸古籍书页总成（1704x864，中心轴 852x432 承载开卷/翻页 Tween）
	_tome_rig = Control.new()
	_tome_rig.name = "TomeSpreadRig"
	_tome_rig.position = Vector2(108.0, 146.0)
	_tome_rig.size = Vector2(1704.0, 864.0)
	_tome_rig.custom_minimum_size = Vector2(1704.0, 864.0)
	_tome_rig.pivot_offset = Vector2(852.0, 432.0)
	add_child(_tome_rig)

	var tome_plate: TextureRect = TextureRect.new()
	tome_plate.name = "TomeSpreadPlate"
	tome_plate.position = Vector2.ZERO
	tome_plate.size = Vector2(1704.0, 864.0)
	tome_plate.custom_minimum_size = Vector2(1704.0, 864.0)
	tome_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tome_plate.stretch_mode = TextureRect.STRETCH_SCALE
	tome_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tome_plate.texture = _get_cached_tex(TEX_TOME_SPREAD)
	_tome_rig.add_child(tome_plate)

	_crease_overlay = _TomeCreaseOverlay.new()
	_crease_overlay.name = "TomeCreaseOverlay"
	_crease_overlay.position = Vector2.ZERO
	_crease_overlay.size = Vector2(1704.0, 864.0)
	_crease_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tome_rig.add_child(_crease_overlay)

	_content_root = MarginContainer.new()
	_content_root.position = Vector2.ZERO
	_content_root.size = Vector2(1704.0, 864.0)
	_content_root.custom_minimum_size = Vector2(1704.0, 864.0)
	_content_root.add_theme_constant_override("margin_left", 34)
	_content_root.add_theme_constant_override("margin_right", 34)
	_content_root.add_theme_constant_override("margin_top", 20)
	_content_root.add_theme_constant_override("margin_bottom", 22)
	_tome_rig.add_child(_content_root)

	_page_flip_leaf = TextureRect.new()
	_page_flip_leaf.name = "PageFlipLeaf"
	_page_flip_leaf.position = Vector2(552.0, 4.0)
	_page_flip_leaf.size = Vector2(600.0, 856.0)
	_page_flip_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_flip_leaf.stretch_mode = TextureRect.STRETCH_SCALE
	_page_flip_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_flip_leaf.texture = _get_cached_tex(TEX_PAGE_FLIP_LEAF)
	_page_flip_leaf.visible = false
	_tome_rig.add_child(_page_flip_leaf)

	_page_flip_veil = ColorRect.new()
	_page_flip_veil.name = "PageFlipVeil"
	_page_flip_veil.position = Vector2.ZERO
	_page_flip_veil.size = Vector2(1704.0, 864.0)
	_page_flip_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_flip_veil.color = Color(0.85, 0.80, 0.72, 0.0)
	_tome_rig.add_child(_page_flip_veil)

	# 4. 破境叩关筹备与无丹【裂脉强渡】二次确认模态框
	_breakthrough_modal = CenterContainer.new()
	_breakthrough_modal.name = "BreakthroughConfirmModal"
	UIThemeBuilder.bind_full_rect(_breakthrough_modal)
	_breakthrough_modal.visible = false
	add_child(_breakthrough_modal)


func open_tab(tab_id: String) -> void:
	if visible and active_tab == tab_id:
		close_casket()
		return
	var was_open: bool = visible
	var tab_changed: bool = (active_tab != tab_id)
	if not was_open:
		var vp: Viewport = get_viewport()
		_prev_focus_owner = null
		if vp != null:
			var cur_f: Control = vp.gui_get_focus_owner()
			if cur_f != null and is_instance_valid(cur_f) and not is_ancestor_of(cur_f) and cur_f.focus_mode != Control.FOCUS_NONE:
				_prev_focus_owner = cur_f
			if cur_f != null and is_instance_valid(cur_f):
				cur_f.release_focus()

	active_tab = tab_id
	_slot_manually_selected = false
	if not CampaignState.recruited_order.has(selected_char_id):
		selected_char_id = "gu_changqing"
	if _breakthrough_modal != null:
		_breakthrough_modal.visible = false
	visible = true
	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_page_turn", AudioDirector.TIER_B, true)
	rebuild_current_tab()
	_play_tome_transition(not was_open, tab_changed)


func _play_tome_transition(is_unfold: bool, tab_changed: bool) -> void:
	if _tome_rig == null:
		return
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null

	_tome_rig.pivot_offset = Vector2(852.0, 432.0)
	if SaveManager.reduced_motion or not is_inside_tree() or (not is_unfold and not tab_changed):
		_tome_rig.scale = Vector2.ONE
		_tome_rig.modulate = Color.WHITE
		if _page_flip_veil != null:
			_page_flip_veil.color = Color(0.85, 0.80, 0.72, 0.0)
		if _page_flip_leaf != null:
			_page_flip_leaf.visible = false
		return

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	if is_unfold:
		_tome_rig.scale = Vector2(0.955, 0.978)
		_tome_rig.modulate = Color(1.0, 0.99, 0.96, 0.88)
		_page_flip_veil.color = Color(0.85, 0.80, 0.72, 0.22)
		_page_flip_leaf.visible = false
		_active_tween.tween_property(_tome_rig, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_tome_rig, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_page_flip_veil, "color:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_tome_rig.scale = Vector2(0.985, 1.0)
		_tome_rig.modulate = Color.WHITE
		_page_flip_veil.color = Color(0.86, 0.81, 0.73, 0.24)
		_page_flip_leaf.position = Vector2(880.0, 4.0)
		_page_flip_leaf.modulate = Color(1.0, 1.0, 1.0, 0.52)
		_page_flip_leaf.visible = (_page_flip_leaf.texture != null)
		_active_tween.tween_property(_tome_rig, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_page_flip_veil, "color:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_page_flip_leaf, "position:x", 220.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_active_tween.tween_property(_page_flip_leaf, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tween.chain().tween_callback(func() -> void:
			if _page_flip_leaf != null:
				_page_flip_leaf.visible = false
		)


func close_casket() -> void:
	if not visible:
		return
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null
	if _page_flip_leaf != null:
		_page_flip_leaf.visible = false
	if _page_flip_veil != null:
		_page_flip_veil.color.a = 0.0
	if _tome_rig != null:
		_tome_rig.scale = Vector2.ONE
		_tome_rig.modulate = Color.WHITE
	if _breakthrough_modal != null:
		_breakthrough_modal.visible = false

	visible = false
	var vp: Viewport = get_viewport()
	if vp != null:
		var cur_f: Control = vp.gui_get_focus_owner()
		if cur_f != null and is_instance_valid(cur_f):
			cur_f.release_focus()
		if _prev_focus_owner != null and is_instance_valid(_prev_focus_owner) and _prev_focus_owner.is_visible_in_tree() and _prev_focus_owner.focus_mode != Control.FOCUS_NONE:
			_prev_focus_owner.grab_focus()
	_prev_focus_owner = null

	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_jade_click", AudioDirector.TIER_B, true)
	casket_closed.emit()


func rebuild_current_tab() -> void:
	if not visible:
		return
	CampaignState.recalculate_all_party_stats(false)

	var sb_act: StyleBox = _make_tex_stylebox(
		TEX_TAB_ACTIVE, 12, 10, 12, 14, 14.0, 6.0, 14.0, 10.0,
		Color(0.16, 0.13, 0.09, 0.98), UIThemeBuilder.COL_BRONZE_GOLD
	)
	var sb_idle: StyleBox = _make_tex_stylebox(
		TEX_TAB_INACTIVE, 12, 10, 12, 14, 14.0, 6.0, 14.0, 10.0,
		Color(0.11, 0.09, 0.08, 0.94), UIThemeBuilder.COL_BRONZE_DIM
	)

	for tid_var: Variant in _tab_buttons.keys():
		var tid: String = str(tid_var)
		var b: Button = _tab_buttons[tid] as Button
		var is_cur: bool = (tid == active_tab)
		var st: StyleBox = sb_act if is_cur else sb_idle
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", sb_act)
		b.add_theme_stylebox_override("pressed", sb_act)
		b.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if is_cur else UIThemeBuilder.COL_XUAN_WARM)
		b.add_theme_font_size_override("font_size", 19 if is_cur else 18)

	var sb_lbl: Label = find_child("StonesBadge", true, false) as Label
	if sb_lbl != null:
		sb_lbl.text = "◆ %s：%d  " % [tr("TERM_SPIRIT_STONE"), CampaignState.spirit_stones]

	if _crease_overlay != null:
		_crease_overlay.is_three_page = (active_tab == "cultivation")
		_crease_overlay.queue_redraw()

	for ch: Node in _content_root.get_children():
		ch.queue_free()

	match active_tab:
		"cultivation":
			_build_tab_cultivation()
		"specialization":
			_build_tab_specialization()
		"inventory":
			_build_tab_inventory_and_sword_box()
		"journal":
			_build_tab_journal()


## ==================== 破境筹备与无丹【裂脉强渡】二次确认 ====================
func _next_breakthrough_realm(cur_realm: String) -> String:
	if cur_realm == "mortal":
		return "qi_refining_1"
	elif cur_realm == "qi_refining_1":
		return "qi_refining_2"
	return ""


func request_breakthrough(char_id: String = "", force_cracked: bool = false) -> bool:
	var cid: String = char_id if char_id != "" else selected_char_id
	if NotifyHub.combat_active or not CampaignState.party_members.has(cid):
		return false
	var m: Dictionary = CampaignState.party_members[cid] as Dictionary
	var next_r: String = _next_breakthrough_realm(str(m.get("realm_id", "mortal")))
	if next_r == "":
		open_breakthrough_confirm(cid)
		return false
	var pill_cnt: int = CampaignState.get_item_count("item_ningqi_vein_pill")
	if pill_cnt <= 0 and not force_cracked:
		# 无主丹时严禁直接扣寿破境，强制弹出二次确认警示！
		open_breakthrough_confirm(cid)
		return false
	if pill_cnt > 0:
		CampaignState.remove_item("item_ningqi_vein_pill", 1)
		var max_bond: int = maxi(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), int(CampaignState.companion_bonds.get("pei_zhao", 1)))
		var eval_d: Dictionary = StatLedger.evaluate_breakthrough_grade(true, CampaignState.unlocked_formations.size() >= 2, max_bond, true, false)
		CampaignState.advance_member_realm(cid, next_r, str(eval_d.get("grade", "solid")))
	else:
		CampaignState.advance_member_realm(cid, next_r, "cracked")
	if _breakthrough_modal != null:
		_breakthrough_modal.visible = false
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_seal_stamp", AudioDirector.TIER_A, true)
	rebuild_current_tab()
	return true


func open_breakthrough_confirm(char_id: String = "") -> void:
	var cid: String = char_id if char_id != "" else selected_char_id
	if _breakthrough_modal == null or not CampaignState.party_members.has(cid):
		return
	for ch: Node in _breakthrough_modal.get_children():
		ch.queue_free()

	var m: Dictionary = CampaignState.party_members[cid] as Dictionary
	var cur_r: String = str(m.get("realm_id", "mortal"))
	var next_r: String = _next_breakthrough_realm(cur_r)
	var pill_cnt: int = CampaignState.get_item_count("item_ningqi_vein_pill")
	var has_array: bool = CampaignState.unlocked_formations.size() >= 2
	var max_bond: int = maxi(int(CampaignState.companion_bonds.get("shen_qinghe", 1)), int(CampaignState.companion_bonds.get("pei_zhao", 1)))

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(740.0, 390.0)
	var sb_m: StyleBoxFlat = UIThemeBuilder.make_xuan_paper_box(Color("#7A3328") if pill_cnt <= 0 else Color("#6E5233"), 3)
	sb_m.content_margin_left = 26.0
	sb_m.content_margin_right = 26.0
	sb_m.content_margin_top = 20.0
	sb_m.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", sb_m)
	_breakthrough_modal.add_child(card)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	var title_txt: String = tr("CASKET_CONFIRM_CRACKED_TITLE") if pill_cnt <= 0 else "【破境试炼 · 三槽叩关筹备】"
	vb.add_child(_dark_label(title_txt, 22, Color("#8E2822") if pill_cnt <= 0 else Color("#4A331C")))

	var prep_lines: String = (
		"◆ 主丹槽：【凝气护脉丹】×%d（有丹稳固破境；无丹则入裂脉强渡）\n" % pill_cnt
		+ "◆ 辅材阵盘：%s\n" % ("已备奇门阵图共鸣" if has_array else "待参悟地载阵/天覆阵")
		+ "◆ 同道护法：最高羁绊 %d 阶（≥2 阶且零代挡冲成【天道无瑕道基】）" % max_bond
	)
	vb.add_child(_dark_label(prep_lines, 17, UIThemeBuilder.COL_INK_DARK))

	if next_r == "":
		vb.add_child(_dark_label("当前角色已臻第一章境界上限（炼气二层），待东赴青云山门再叩筑基仙关。", 17, Color("#23483E")))
	elif pill_cnt <= 0:
		vb.add_child(_dark_label(tr("CASKET_CONFIRM_CRACKED_BODY"), 17, Color("#8E2822")))
	else:
		var next_name: String = DataDB.loc(str(DataDB.get_realm(next_r).get("name_key", next_r)))
		vb.add_child(_dark_label("行囊已备护脉主丹，可稳妥服丹冲关晋入【%s】！", 17, Color("#1F4E3D")) if next_name == "" else _dark_label("行囊已备护脉主丹，可稳妥服丹冲关晋入【%s】！" % next_name, 17, Color("#1F4E3D")))

	var btn_hb: HBoxContainer = HBoxContainer.new()
	btn_hb.alignment = BoxContainer.ALIGNMENT_END
	btn_hb.add_theme_constant_override("separation", 16)
	vb.add_child(btn_hb)

	var cancel_b: Button = Button.new()
	cancel_b.text = tr("UI_BTN_CANCEL")
	cancel_b.focus_mode = Control.FOCUS_NONE
	cancel_b.pressed.connect(func() -> void: _breakthrough_modal.visible = false)
	btn_hb.add_child(cancel_b)

	if next_r != "":
		var confirm_b: Button = Button.new()
		confirm_b.focus_mode = Control.FOCUS_NONE
		confirm_b.disabled = NotifyHub.combat_active
		if pill_cnt <= 0:
			confirm_b.text = "%s（%s）" % [tr("UI_BTN_CONFIRM"), tr("CASKET_BTN_FORCE_CRACKED")]
			confirm_b.pressed.connect(func() -> void:
				if NotifyHub.combat_active:
					return
				request_breakthrough(cid, true)
			)
		else:
			confirm_b.text = "%s · 服丹破境" % tr("UI_BTN_CONFIRM")
			confirm_b.pressed.connect(func() -> void:
				if NotifyHub.combat_active:
					return
				request_breakthrough(cid, false)
			)
		btn_hb.add_child(confirm_b)

	_breakthrough_modal.visible = true


## ==================== Tab 1：【修行 · 兵甲】（三折古籍宣纸定稿版） ====================
func _build_tab_cultivation() -> void:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	_content_root.add_child(cols)

	var m: Dictionary = CampaignState.party_members.get(selected_char_id, {}) as Dictionary
	var cdef: Dictionary = DataDB.get_character(selected_char_id)
	var realm_id_s: String = str(m.get("realm_id", "mortal"))
	var rdef: Dictionary = DataDB.get_realm(realm_id_s)
	var sheet: Dictionary = m.get("sheet", {}) as Dictionary
	var foundation_grade: String = str(m.get("dao_foundation_grade", "solid"))
	var bruise_cnt: int = int(m.get("meridian_bruise", 0))

	# ==================== 左页（global x: 142..698, 宽 556px） ====================
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(556.0, 820.0)
	left_col.add_theme_constant_override("separation", 4)
	cols.add_child(left_col)

	# 顶部紧凑同道竹简切换条（高 36px，不遮挡 y>=212 旧宣底纸！）
	var char_row: HBoxContainer = HBoxContainer.new()
	char_row.custom_minimum_size = Vector2(556.0, 36.0)
	char_row.add_theme_constant_override("separation", 8)
	left_col.add_child(char_row)
	for cid: String in CampaignState.recruited_order:
		var cd: Dictionary = DataDB.get_character(cid)
		var cb: Button = _make_xuan_slip_button(
			("★ " if cid == selected_char_id else "") + DataDB.loc(str(cd.get("name_key", cid))),
			cid == selected_char_id
		)
		cb.pressed.connect(func() -> void:
			selected_char_id = cid
			rebuild_current_tab()
		)
		char_row.add_child(cb)

	# 中部：古典工笔水墨奇经八脉人体图 + 青玉璧穴位环 + 竖排《奇经八脉图》题签（高 552px）
	var meridian_stage: Control = Control.new()
	meridian_stage.name = "MeridianStage"
	meridian_stage.custom_minimum_size = Vector2(556.0, 552.0)
	meridian_stage.size = Vector2(556.0, 552.0)
	left_col.add_child(meridian_stage)

	var fig_rect: TextureRect = TextureRect.new()
	fig_rect.name = "MeridianFigureRect"
	fig_rect.position = Vector2(42.0, 2.0)
	fig_rect.size = Vector2(460.0, 550.0)
	fig_rect.custom_minimum_size = Vector2(460.0, 550.0)
	fig_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fig_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fig_rect.texture = _get_cached_tex(TEX_MERIDIAN_FIG)
	meridian_stage.add_child(fig_rect)

	var acu_canvas: _MeridianAcupointCanvas = _MeridianAcupointCanvas.new()
	acu_canvas.position = Vector2.ZERO
	acu_canvas.size = Vector2(556.0, 552.0)
	acu_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	acu_canvas.realm_id = realm_id_s
	acu_canvas.foundation_grade = foundation_grade
	acu_canvas.meridian_bruise = bruise_cnt
	acu_canvas.fig_offset = Vector2(42.0, 2.0)
	meridian_stage.add_child(acu_canvas)

	# 穴位正楷简体批注标签（全部 >= 16px，距页边 >= 28px，与引线圆点严格保持 8px 间距，绝不遮盖 Rect2i(160,240,140,140) 亮宣采样区）
	var callouts: Array[Array] = [
		[tr("CASKET_ACU_BAIHUI"), Vector2(142.0, 22.0)],
		[tr("CASKET_ACU_NIWAN"), Vector2(422.0, 56.0)],
		[tr("CASKET_ACU_SHANZHONG"), Vector2(88.0, 211.0)],
		[tr("CASKET_ACU_ZHONGWAN"), Vector2(426.0, 272.0)],
		[tr("CASKET_ACU_QIHAI"), Vector2(86.0, 323.0)],
		[tr("CASKET_ACU_DANTIAN"), Vector2(426.0, 439.0)],
		[tr("CASKET_ACU_LAOGONG"), Vector2(28.0, 373.0)],
	]
	for co: Array in callouts:
		var cl: Label = Label.new()
		cl.text = str(co[0])
		cl.position = co[1] as Vector2
		cl.add_theme_font_size_override("font_size", 16)
		cl.add_theme_color_override("font_color", Color("#261F19"))
		meridian_stage.add_child(cl)

	# 右上角竖排题签框《奇经八脉图》（对标 master_d 右上题签框，根除 AI 伪字）
	var cartouche: PanelContainer = PanelContainer.new()
	cartouche.position = Vector2(500.0, 22.0)
	cartouche.custom_minimum_size = Vector2(42.0, 148.0)
	var sb_cart: StyleBoxFlat = StyleBoxFlat.new()
	sb_cart.bg_color = Color(0.84, 0.79, 0.70, 0.92)
	sb_cart.border_color = Color("#3F3224")
	sb_cart.set_border_width_all(2)
	sb_cart.content_margin_left = 6.0
	sb_cart.content_margin_right = 6.0
	sb_cart.content_margin_top = 8.0
	sb_cart.content_margin_bottom = 8.0
	cartouche.add_theme_stylebox_override("panel", sb_cart)
	meridian_stage.add_child(cartouche)
	var cart_lbl: Label = Label.new()
	cart_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cart_lbl.text = "奇\n经\n八\n脉\n图"
	cart_lbl.add_theme_font_size_override("font_size", 17)
	cart_lbl.add_theme_color_override("font_color", Color("#241D17"))
	cartouche.add_child(cart_lbl)

	# 左页底部：道基品评宣纸牌匾 + 【破境试炼 · 叩关筹备】入口（y ~ 762..984，复刻 master_d 左下铭牌）
	var plaque_box: PanelContainer = PanelContainer.new()
	plaque_box.custom_minimum_size = Vector2(552.0, 214.0)
	var sb_plaque: StyleBoxFlat = StyleBoxFlat.new()
	sb_plaque.bg_color = Color(0.84, 0.79, 0.70, 0.96)
	sb_plaque.border_color = Color("#8E2822") if foundation_grade == "cracked" else Color("#7A6344")
	sb_plaque.set_border_width_all(2)
	sb_plaque.set_corner_radius_all(3)
	sb_plaque.content_margin_left = 14.0
	sb_plaque.content_margin_right = 14.0
	sb_plaque.content_margin_top = 10.0
	sb_plaque.content_margin_bottom = 10.0
	plaque_box.add_theme_stylebox_override("panel", sb_plaque)
	left_col.add_child(plaque_box)

	var pvb: VBoxContainer = VBoxContainer.new()
	pvb.add_theme_constant_override("separation", 5)
	plaque_box.add_child(pvb)

	var realm_cn: String = DataDB.loc(str(rdef.get("name_key", "")))
	var grade_badge: String = "【地道稳固道基】"
	var grade_col: Color = Color("#2C241D")
	if foundation_grade == "flawless":
		grade_badge = "【天道无瑕】（全五维 +8%）"
		grade_col = Color("#1F4E3D")
	elif foundation_grade == "cracked":
		grade_badge = tr("CASKET_FOUNDATION_CRACKED")
		grade_col = Color("#8E2822")

	pvb.add_child(_dark_label("当前道基：%s · %s" % [realm_cn, grade_badge], 18, grade_col))

	var bruise_note: String = (" · 经脉暗伤 %d 层" % bruise_cnt) if bruise_cnt > 0 else ""
	var sub_line: String = "%s · %s · 寿元上限 %d 载（探索零损耗）%s" % [
		DataDB.loc(str(cdef.get("name_key", ""))),
		DataDB.loc(str(cdef.get("title_key", ""))),
		int(sheet.get("lifespan_max", 80)),
		bruise_note,
	]
	pvb.add_child(_dark_label(sub_line, 16, Color("#8E2822") if bruise_cnt > 0 else Color("#245242")))

	var r_desc_lbl: Label = _dark_label(DataDB.loc(str(rdef.get("desc_key", ""))), 16, Color("#3B3228"))
	r_desc_lbl.max_lines_visible = 2
	r_desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pvb.add_child(r_desc_lbl)

	var bt_row: HBoxContainer = HBoxContainer.new()
	bt_row.alignment = BoxContainer.ALIGNMENT_END
	pvb.add_child(bt_row)

	var bt_btn: Button = _make_bronze_action_button("【%s】" % tr("CASKET_BTN_BREAKTHROUGH"), Vector2(216.0, 34.0))
	bt_btn.disabled = NotifyHub.combat_active
	bt_btn.pressed.connect(func() -> void:
		if NotifyHub.combat_active:
			return
		open_breakthrough_confirm(selected_char_id)
	)
	bt_row.add_child(bt_btn)

	# 折页中缝 1（28px，跨过 global 712 装订折痕）
	var gutter_1: Control = Control.new()
	gutter_1.custom_minimum_size = Vector2(28.0, 10.0)
	cols.add_child(gutter_1)

	# ==================== 中页（global x: 726..1238, 宽 512px, 中心 982） ====================
	var mid_col: VBoxContainer = VBoxContainer.new()
	mid_col.custom_minimum_size = Vector2(512.0, 820.0)
	mid_col.add_theme_constant_override("separation", 8)
	cols.add_child(mid_col)

	# 上半：3+2 浮雕双线兵甲器物槽（高 382px）
	var slots_box: VBoxContainer = VBoxContainer.new()
	slots_box.custom_minimum_size = Vector2(512.0, 382.0)
	slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_box.add_theme_constant_override("separation", 12)
	mid_col.add_child(slots_box)

	var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
	var cand_info: Dictionary = _resolve_comparison_candidate(eq_map)
	var active_cmp_slot: String = str(cand_info.get("slot", _selected_equip_slot))

	var row_top: HBoxContainer = HBoxContainer.new()
	row_top.alignment = BoxContainer.ALIGNMENT_CENTER
	row_top.add_theme_constant_override("separation", 18)
	slots_box.add_child(row_top)
	for sk_top: String in ["weapon", "robe", "boots"]:
		row_top.add_child(_build_embossed_equip_slot(sk_top, str(eq_map.get(sk_top, "")), sk_top == active_cmp_slot))

	var row_bot: HBoxContainer = HBoxContainer.new()
	row_bot.alignment = BoxContainer.ALIGNMENT_CENTER
	row_bot.add_theme_constant_override("separation", 26)
	slots_box.add_child(row_bot)
	for sk_bot: String in ["pendant", "treasure"]:
		row_bot.add_child(_build_embossed_equip_slot(sk_bot, str(eq_map.get(sk_bot, "")), sk_bot == active_cmp_slot))

	# 下半：5 条错金铜框五维潜能条 + [+] / [-] + 【洗髓灵露】重置（高 418px）
	var pot_box: VBoxContainer = VBoxContainer.new()
	pot_box.custom_minimum_size = Vector2(512.0, 418.0)
	pot_box.add_theme_constant_override("separation", 10)
	mid_col.add_child(pot_box)

	var pot_pad: MarginContainer = MarginContainer.new()
	pot_pad.add_theme_constant_override("margin_left", 18)
	pot_pad.add_theme_constant_override("margin_right", 18)
	pot_pad.add_theme_constant_override("margin_top", 10)
	pot_box.add_child(pot_pad)

	var pot_inner: VBoxContainer = VBoxContainer.new()
	pot_inner.add_theme_constant_override("separation", 12)
	pot_pad.add_child(pot_inner)

	var free_pts: int = int(m.get("free_potential", 0))
	var pot_hdr: Label = _dark_label("◆ %s（余 %d 点自由潜能）" % [tr("TERM_FIVE_STATS"), free_pts], 18, Color("#4A331C"))
	pot_inner.add_child(pot_hdr)

	var five_vals: Dictionary = sheet.get("five_stats", {}) as Dictionary
	var alloc_vals: Dictionary = m.get("allocated_potential", {}) as Dictionary
	var dew_cnt: int = CampaignState.get_item_count("item_marrow_dew")
	var total_alloc: int = 0
	for ak_var: Variant in alloc_vals.keys():
		total_alloc += int(alloc_vals[str(ak_var)])

	var sb_bar_bg: StyleBox = _make_tex_stylebox(
		TEX_POT_BAR_BG, 12, 6, 12, 6, 4.0, 3.0, 4.0, 3.0,
		Color("#2A231B"), Color("#7D6339")
	)
	var sb_bar_fill: StyleBox = _make_tex_stylebox(
		TEX_POT_BAR_FILL, 4, 4, 4, 4, 0.0, 0.0, 0.0, 0.0,
		Color("#B89149"), Color("#DFBA70")
	)

	var five_meta: Array[Array] = [
		["con", tr("TERM_STAT_CON"), "+12 气血上限 / 脱战回血"],
		["spi", tr("TERM_STAT_SPI"), "+8 真元 / +1.5 仙术 / +0.8 治疗"],
		["str", tr("TERM_STAT_STR"), "+1.6 兵刃飞剑强度 / 破罡力"],
		["end", tr("TERM_STAT_END"), "+2.2 护甲与五灵抗性"],
		["agi", tr("TERM_STAT_AGI"), "+1.2 暴击等级 / +0.15% 移速"],
	]
	for fmeta: Array in five_meta:
		var fkey: String = str(fmeta[0])
		var fcn: String = str(fmeta[1])
		var ftip: String = str(fmeta[2])
		var cur_v: int = int(five_vals.get(fkey, 6))
		var cur_alloc: int = int(alloc_vals.get(fkey, 0))

		var fhb: HBoxContainer = HBoxContainer.new()
		fhb.alignment = BoxContainer.ALIGNMENT_CENTER
		fhb.add_theme_constant_override("separation", 8)
		fhb.tooltip_text = "%s：%d（已投 +%d）· %s" % [fcn, cur_v, cur_alloc, ftip]
		pot_inner.add_child(fhb)

		var flbl: Label = Label.new()
		flbl.custom_minimum_size = Vector2(96.0, 34.0)
		flbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		flbl.text = "%s  %d" % [fcn, cur_v]
		flbl.add_theme_font_size_override("font_size", 19)
		flbl.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
		fhb.add_child(flbl)

		var pbar: ProgressBar = ProgressBar.new()
		pbar.custom_minimum_size = Vector2(236.0, 24.0)
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pbar.min_value = 0.0
		pbar.max_value = 30.0
		pbar.step = 1.0
		pbar.value = clampf(float(cur_v), 0.0, 30.0)
		pbar.show_percentage = false
		pbar.add_theme_stylebox_override("background", sb_bar_bg)
		pbar.add_theme_stylebox_override("fill", sb_bar_fill)
		fhb.add_child(pbar)

		var plus_b: Button = _make_bronze_action_button("+", Vector2(36.0, 34.0))
		plus_b.tooltip_text = "投入 1 点自由潜能（%s）" % ftip
		plus_b.disabled = free_pts <= 0 or NotifyHub.combat_active
		plus_b.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			if CampaignState.allocate_potential_point(selected_char_id, fkey, 1):
				rebuild_current_tab()
		)
		fhb.add_child(plus_b)

		var minus_b: Button = _make_bronze_action_button("-", Vector2(36.0, 34.0))
		minus_b.tooltip_text = "服用【洗髓灵露】洗髓归元（100% 无损退回全部潜能点）"
		minus_b.disabled = cur_alloc <= 0 or dew_cnt <= 0 or NotifyHub.combat_active
		minus_b.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			if CampaignState.reset_potential_points(selected_char_id):
				rebuild_current_tab()
		)
		fhb.add_child(minus_b)

	var reset_btn: Button = _make_bronze_action_button(
		"服用【洗髓灵露】无损重置五维（存量：%d）" % dew_cnt,
		Vector2(460.0, 38.0)
	)
	reset_btn.disabled = dew_cnt <= 0 or total_alloc <= 0 or NotifyHub.combat_active
	reset_btn.pressed.connect(func() -> void:
		if NotifyHub.combat_active:
			return
		if CampaignState.reset_potential_points(selected_char_id):
			rebuild_current_tab()
	)
	pot_inner.add_child(reset_btn)

	# 折页中缝 2（28px，跨过 global 1252 装订折痕）
	var gutter_2: Control = Control.new()
	gutter_2.custom_minimum_size = Vector2(28.0, 10.0)
	cols.add_child(gutter_2)

	# ==================== 右页（global x: 1266..1778, 宽 512px, 中心 1522） ====================
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(512.0, 820.0)
	right_col.add_theme_constant_override("separation", 8)
	cols.add_child(right_col)

	# 上半：双栏细线分格真实递减生效账本（高 366px，直接落在暖宣底纸上确保 R > B！）
	var ledger_margin: MarginContainer = MarginContainer.new()
	ledger_margin.custom_minimum_size = Vector2(512.0, 366.0)
	ledger_margin.add_theme_constant_override("margin_left", 16)
	ledger_margin.add_theme_constant_override("margin_right", 16)
	ledger_margin.add_theme_constant_override("margin_top", 10)
	right_col.add_child(ledger_margin)

	var ledger_vb: VBoxContainer = VBoxContainer.new()
	ledger_vb.add_theme_constant_override("separation", 6)
	ledger_margin.add_child(ledger_vb)

	ledger_vb.add_child(_dark_label("◆ 最终生效面板（45/35/20 递减实算）", 18, Color("#4A331C")))

	var ledger_pairs: Array[Array] = [
		[
			"气血  %d / %d" % [int(m.get("hp", 120)), int(sheet.get("max_hp", 120))],
			"暴击率  %.1f%%" % (float(sheet.get("crit_pct", 0.05)) * 100.0),
		],
		[
			"真元  %d / %d" % [int(m.get("mp", 60)), int(sheet.get("max_mp", 60))],
			"急速  %.1f%% (%.2fs)" % [float(sheet.get("haste_pct", 0.0)) * 100.0, float(sheet.get("gcd_sec", 1.50))],
		],
		[
			"兵刃强度  %.1f" % float(sheet.get("phys_power", 14.0)),
			"破罡精通  %.1f%%" % (float(sheet.get("mastery_pct", 0.0)) * 100.0),
		],
		[
			"仙术强度  %.1f" % float(sheet.get("spell_power", 14.0)),
			"综合减伤  %.1f%%" % (float(sheet.get("mitigation_pct", 0.15)) * 100.0),
		],
		[
			"治疗强度  %.1f" % float(sheet.get("heal_power", 12.0)),
			"御守减伤  %.1f%%" % (float(sheet.get("vers_pct", 0.0)) * 100.0),
		],
		[
			"护甲抗性  %.0f" % float(sheet.get("defense", 18.0)),
			"移速/杀意  %.0f / ×%.2f" % [float(sheet.get("move_speed_px", 215.0)), float(sheet.get("threat_mult", 1.0))],
		],
	]
	for pair_row: Array in ledger_pairs:
		var rhb: HBoxContainer = HBoxContainer.new()
		rhb.add_theme_constant_override("separation", 14)
		ledger_vb.add_child(rhb)

		var l_cell: Label = Label.new()
		l_cell.custom_minimum_size = Vector2(226.0, 28.0)
		l_cell.text = str(pair_row[0])
		l_cell.add_theme_font_size_override("font_size", 17)
		l_cell.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
		rhb.add_child(l_cell)

		var r_cell: Label = Label.new()
		r_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_cell.text = str(pair_row[1])
		r_cell.add_theme_font_size_override("font_size", 17)
		r_cell.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
		rhb.add_child(r_cell)

		var rule: ColorRect = ColorRect.new()
		rule.custom_minimum_size = Vector2(468.0, 1.0)
		rule.color = Color(0.50, 0.40, 0.28, 0.38)
		ledger_vb.add_child(rule)

	var set_counts: Dictionary = sheet.get("set_counts", {}) as Dictionary
	if not set_counts.is_empty():
		var set_parts: PackedStringArray = PackedStringArray()
		var set_tips: PackedStringArray = PackedStringArray()
		for sid_var: Variant in set_counts.keys():
			var sid: String = str(sid_var)
			var cnt: int = int(set_counts[sid])
			var sdef: Dictionary = DataDB.equip_sets.get(sid, {}) as Dictionary
			set_parts.append("【%s】(%d/3)" % [DataDB.loc(str(sdef.get("name_key", sid))), cnt])
			set_tips.append("【%s】(%d/3)：\n· %s\n· %s" % [
				DataDB.loc(str(sdef.get("name_key", sid))),
				cnt,
				DataDB.loc(str(sdef.get("desc_2pc_key", ""))),
				DataDB.loc(str(sdef.get("desc_3pc_key", ""))),
			])
		var set_lbl: Label = _dark_label("套装共鸣：" + "  ".join(set_parts), 16, Color("#214B3F"))
		set_lbl.tooltip_text = "\n".join(set_tips)
		ledger_vb.add_child(set_lbl)

	# 下半：并排双色底装备与 #8FD4E8 蓝字特技对比卡（复刻 master_d 右下暖宣 vs 冷青石板双栏）
	var cmp_margin: MarginContainer = MarginContainer.new()
	cmp_margin.custom_minimum_size = Vector2(512.0, 434.0)
	cmp_margin.add_theme_constant_override("margin_left", 14)
	cmp_margin.add_theme_constant_override("margin_right", 14)
	cmp_margin.add_theme_constant_override("margin_top", 10)
	cmp_margin.add_theme_constant_override("margin_bottom", 8)
	right_col.add_child(cmp_margin)

	cmp_margin.add_child(_build_side_by_side_comparison_card(selected_char_id, eq_map, cand_info))


func _build_embossed_equip_slot(slot_key: String, eq_id: String, is_selected: bool) -> PanelContainer:
	var edef: Dictionary = DataDB.get_equipment(eq_id)
	var has_stunt: bool = (eq_id != "" and str(edef.get("blue_stunt_id", "")) != "")
	var use_glow: bool = is_selected

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(144.0, 156.0)
	var sbt: StyleBox = _make_tex_stylebox(
		TEX_SLOT_SELECTED if use_glow else TEX_SLOT_EMBOSSED,
		16, 16, 16, 42, 10.0, 14.0, 10.0, 8.0,
		Color("#ACA089"), UIThemeBuilder.COL_BRONZE_GOLD if use_glow else UIThemeBuilder.COL_BRONZE_DIM
	)
	card.add_theme_stylebox_override("panel", sbt)

	var eq_name: String = DataDB.loc(str(edef.get("name_key", ""))) if eq_id != "" else "未佩器物"
	var slot_title: String = tr("CASKET_SLOT_" + slot_key.to_upper())
	card.tooltip_text = "【%s】%s" % [slot_title, eq_name]
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_selected_equip_slot = slot_key
			_slot_manually_selected = true
			if selected_item_id != "":
				var sel_eq: Dictionary = DataDB.get_equipment(selected_item_id)
				if str(sel_eq.get("slot", "")) != slot_key:
					selected_item_id = ""
			rebuild_current_tab()
	)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)

	var icon_wrap: CenterContainer = CenterContainer.new()
	icon_wrap.custom_minimum_size = Vector2(120.0, 96.0)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(icon_wrap)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(74.0, 74.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	if eq_id != "":
		icon_rect.texture = _get_cached_tex(str(edef.get("icon", "")))
		icon_rect.modulate = Color.WHITE
	if icon_rect.texture == null:
		icon_rect.texture = _get_cached_tex("res://assets/ui/icons/slot_silhouette_%s.png" % slot_key)
		icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.86)
	icon_wrap.add_child(icon_rect)

	var slot_lbl: Label = Label.new()
	slot_lbl.custom_minimum_size = Vector2(0.0, 26.0)
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_lbl.text = slot_title
	slot_lbl.add_theme_font_size_override("font_size", 16)
	slot_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT if has_stunt else Color("#EFE6D5"))
	vb.add_child(slot_lbl)

	return card


func _resolve_comparison_candidate(eq_map: Dictionary) -> Dictionary:
	# 0. 若玩家在中页左键手动点选了 3+2 槽位，则严格锁定该槽位展示与同部位备选，绝不被其它部位覆盖！
	if _slot_manually_selected:
		if selected_item_id != "" and DataDB.equipment.has(selected_item_id) and CampaignState.get_item_count(selected_item_id) > 0:
			var mdef: Dictionary = DataDB.get_equipment(selected_item_id)
			if str(mdef.get("slot", "")) == _selected_equip_slot:
				return {"cand_id": selected_item_id, "slot": _selected_equip_slot}
		var slot_cand: String = ""
		for entry_m: Dictionary in CampaignState.inventory:
			var iid_m: String = str(entry_m.get("id", ""))
			if int(entry_m.get("count", 0)) > 0 and DataDB.equipment.has(iid_m):
				var ed_m: Dictionary = DataDB.get_equipment(iid_m)
				if str(ed_m.get("slot", "")) == _selected_equip_slot:
					if str(ed_m.get("blue_stunt_id", "")) != "":
						return {"cand_id": iid_m, "slot": _selected_equip_slot}
					if slot_cand == "":
						slot_cand = iid_m
		return {"cand_id": slot_cand, "slot": _selected_equip_slot}

	# 1. 优先采用外部或行囊已选中的在包装备（如 selected_item_id = "eq_pendant_poxue"）
	if selected_item_id != "" and DataDB.equipment.has(selected_item_id) and CampaignState.get_item_count(selected_item_id) > 0:
		var sdef: Dictionary = DataDB.get_equipment(selected_item_id)
		return {"cand_id": selected_item_id, "slot": str(sdef.get("slot", _selected_equip_slot))}
	# 2. 次选：行囊中与当前选中槽位同部位的备选装备
	for entry: Dictionary in CampaignState.inventory:
		var iid: String = str(entry.get("id", ""))
		if int(entry.get("count", 0)) > 0 and DataDB.equipment.has(iid):
			var ed: Dictionary = DataDB.get_equipment(iid)
			if str(ed.get("slot", "")) == _selected_equip_slot:
				return {"cand_id": iid, "slot": _selected_equip_slot}
	# 3. 再次：行囊中任意一件可对比装备（优先含蓝字特技者）
	var fallback_cand: String = ""
	var fallback_slot: String = _selected_equip_slot
	for entry2: Dictionary in CampaignState.inventory:
		var iid2: String = str(entry2.get("id", ""))
		if int(entry2.get("count", 0)) > 0 and DataDB.equipment.has(iid2):
			var ed2: Dictionary = DataDB.get_equipment(iid2)
			if str(ed2.get("blue_stunt_id", "")) != "":
				return {"cand_id": iid2, "slot": str(ed2.get("slot", "pendant"))}
			if fallback_cand == "":
				fallback_cand = iid2
				fallback_slot = str(ed2.get("slot", _selected_equip_slot))
	if fallback_cand != "":
		return {"cand_id": fallback_cand, "slot": fallback_slot}
	# 4. 行囊无多余装备时，左栏展示当前选中槽位（若空则取 weapon）
	var inspect_slot: String = _selected_equip_slot
	if str(eq_map.get(inspect_slot, "")) == "":
		inspect_slot = "weapon"
	return {"cand_id": "", "slot": inspect_slot}


func _build_side_by_side_comparison_card(char_id: String, eq_map: Dictionary, cand_info: Dictionary) -> HBoxContainer:
	var cmp_slot: String = str(cand_info.get("slot", "pendant"))
	var cand_id: String = str(cand_info.get("cand_id", ""))
	var eq_id: String = str(eq_map.get(cmp_slot, ""))
	var eq_def: Dictionary = DataDB.get_equipment(eq_id)
	var cand_def: Dictionary = DataDB.get_equipment(cand_id)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 10)

	# 左子卡：当前穿戴（暖深旧宣底 #C5B69B，墨字）
	var left_sub: PanelContainer = PanelContainer.new()
	left_sub.custom_minimum_size = Vector2(236.0, 408.0)
	left_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_l: StyleBoxFlat = StyleBoxFlat.new()
	sb_l.bg_color = Color("#C5B69B")
	sb_l.border_color = Color("#856E4E")
	sb_l.set_border_width_all(1)
	sb_l.set_corner_radius_all(3)
	sb_l.content_margin_left = 12.0
	sb_l.content_margin_right = 12.0
	sb_l.content_margin_top = 10.0
	sb_l.content_margin_bottom = 10.0
	left_sub.add_theme_stylebox_override("panel", sb_l)
	hb.add_child(left_sub)

	var lvb: VBoxContainer = VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 6)
	left_sub.add_child(lvb)

	lvb.add_child(_dark_label("%s · %s" % [tr("CASKET_COMPARE_EQUIPPED"), tr("CASKET_SLOT_" + cmp_slot.to_upper())], 16, Color("#584530")))
	var eq_title: String = DataDB.loc(str(eq_def.get("name_key", ""))) if eq_id != "" else "尚无佩器"
	var eq_title_lbl: Label = _dark_label(eq_title, 19, UIThemeBuilder.COL_INK_DARK)
	lvb.add_child(eq_title_lbl)

	var l_div: ColorRect = ColorRect.new()
	l_div.custom_minimum_size = Vector2(180.0, 1.0)
	l_div.color = Color(0.32, 0.25, 0.18, 0.55)
	lvb.add_child(l_div)

	var eq_stats: Dictionary = eq_def.get("stats", {}) as Dictionary
	var stat_labels: Dictionary = _equip_stat_labels()
	if eq_id != "":
		for k_var: Variant in stat_labels.keys():
			var k: String = str(k_var)
			var v: float = float(eq_stats.get(k, 0.0))
			if absf(v) > 0.01:
				lvb.add_child(_dark_label("%s: +%.0f" % [str(stat_labels[k]), v], 16, UIThemeBuilder.COL_INK_DARK))
		var eq_stunt: String = str(eq_def.get("blue_stunt_id", ""))
		if eq_stunt != "":
			var st_d: Dictionary = DataDB.get_skill(eq_stunt)
			var st_badge: PanelContainer = PanelContainer.new()
			var sb_st: StyleBoxFlat = StyleBoxFlat.new()
			sb_st.bg_color = Color("#2C393F")
			sb_st.border_color = Color("#638594")
			sb_st.set_border_width_all(1)
			sb_st.set_corner_radius_all(3)
			sb_st.content_margin_left = 8.0
			sb_st.content_margin_right = 8.0
			sb_st.content_margin_top = 6.0
			sb_st.content_margin_bottom = 6.0
			st_badge.add_theme_stylebox_override("panel", sb_st)
			lvb.add_child(st_badge)
			var st_l: Label = Label.new()
			st_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			st_l.text = "【%s】\n%s" % [
				DataDB.loc(str(st_d.get("name_key", eq_stunt))),
				DataDB.loc(str(st_d.get("desc_key", ""))),
			]
			st_l.add_theme_font_size_override("font_size", 16)
			st_l.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT)
			st_badge.add_child(st_l)
		else:
			var eq_desc_short: Label = _dark_label(DataDB.loc(str(eq_def.get("desc_key", ""))), 16, Color("#3F352B"))
			eq_desc_short.max_lines_visible = 4
			eq_desc_short.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lvb.add_child(eq_desc_short)
	else:
		lvb.add_child(_dark_label("此部位尚未佩戴法器，可在【行囊·剑匣 (B)】或右侧备选中穿戴。", 16, Color("#4D4032")))

	# 右子卡：备选比对（冷青黛石板底 #354147，天青蓝 #8FD4E8 特技高亮，复刻 master_d 右下右卡）
	var right_sub: PanelContainer = PanelContainer.new()
	right_sub.custom_minimum_size = Vector2(236.0, 408.0)
	right_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_r: StyleBoxFlat = StyleBoxFlat.new()
	sb_r.bg_color = Color("#354147")
	sb_r.border_color = Color("#6C8A96")
	sb_r.set_border_width_all(1)
	sb_r.set_corner_radius_all(3)
	sb_r.content_margin_left = 12.0
	sb_r.content_margin_right = 12.0
	sb_r.content_margin_top = 10.0
	sb_r.content_margin_bottom = 10.0
	right_sub.add_theme_stylebox_override("panel", sb_r)
	hb.add_child(right_sub)

	var rvb: VBoxContainer = VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 5)
	right_sub.add_child(rvb)

	rvb.add_child(_dark_label(tr("CASKET_COMPARE_CANDIDATE"), 16, Color("#B9C9CF")))

	if cand_id != "" and not cand_def.is_empty():
		var cand_stunt: String = str(cand_def.get("blue_stunt_id", ""))
		var c_title: Label = Label.new()
		c_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c_title.text = DataDB.loc(str(cand_def.get("name_key", cand_id)))
		c_title.add_theme_font_size_override("font_size", 19)
		c_title.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT if cand_stunt != "" else Color("#EAE4D7"))
		rvb.add_child(c_title)

		var r_div: ColorRect = ColorRect.new()
		r_div.custom_minimum_size = Vector2(180.0, 1.0)
		r_div.color = Color(0.56, 0.78, 0.86, 0.45)
		rvb.add_child(r_div)

		var n_stats: Dictionary = cand_def.get("stats", {}) as Dictionary
		var short_labels: Dictionary = {
			"hp": "气血", "mp": "真元", "phys_power": "兵刃", "spell_power": "仙术",
			"heal_power": "治疗", "defense": "护甲", "crit_rating": "暴击",
			"haste_rating": "急速", "mastery_rating": "破罡", "vers_rating": "御守",
		}
		var delta_entries: Array[Dictionary] = []
		for k2_var: Variant in stat_labels.keys():
			var k2: String = str(k2_var)
			var nv: float = float(n_stats.get(k2, 0.0))
			var cv: float = float(eq_stats.get(k2, 0.0))
			if absf(nv) > 0.01 or absf(cv) > 0.01:
				var diff: float = nv - cv
				var d_str: String = "%s%.0f" % ["+" if diff >= 0.0 else "", diff]
				var line_col: Color = Color("#8AD6B0") if diff > 0.01 else (Color("#E28B7A") if diff < -0.01 else Color("#E4DFD3"))
				delta_entries.append({
					"full_lbl": str(stat_labels[k2]),
					"short_lbl": str(short_labels.get(k2, stat_labels[k2])),
					"nv": nv,
					"d_str": d_str,
					"col": line_col,
				})
		if delta_entries.size() > 4:
			var d_grid: GridContainer = GridContainer.new()
			d_grid.columns = 2
			d_grid.add_theme_constant_override("h_separation", 8)
			d_grid.add_theme_constant_override("v_separation", 3)
			rvb.add_child(d_grid)
			for de: Dictionary in delta_entries:
				var sl_g: Label = Label.new()
				sl_g.text = "%s+%.0f(%s)" % [str(de["short_lbl"]), float(de["nv"]), str(de["d_str"])]
				sl_g.add_theme_font_size_override("font_size", 16)
				sl_g.add_theme_color_override("font_color", de["col"] as Color)
				d_grid.add_child(sl_g)
		else:
			for de2: Dictionary in delta_entries:
				var sl: Label = Label.new()
				sl.text = "%s: +%.0f (%s)" % [str(de2["full_lbl"]), float(de2["nv"]), str(de2["d_str"])]
				sl.add_theme_font_size_override("font_size", 16)
				sl.add_theme_color_override("font_color", de2["col"] as Color)
				rvb.add_child(sl)

		if cand_stunt != "":
			var cst_def: Dictionary = DataDB.get_skill(cand_stunt)
			var cst_lbl: Label = Label.new()
			cst_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cst_lbl.text = "【%s】%s" % [
				DataDB.loc(str(cst_def.get("name_key", cand_stunt))),
				DataDB.loc(str(cst_def.get("desc_key", ""))),
			]
			cst_lbl.add_theme_font_size_override("font_size", 16)
			cst_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT)
			rvb.add_child(cst_lbl)

		var wear_b: Button = Button.new()
		wear_b.text = "穿戴此器物"
		wear_b.focus_mode = Control.FOCUS_NONE
		wear_b.disabled = NotifyHub.combat_active
		wear_b.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			if CampaignState.equip_item_on_member(char_id, cand_id):
				rebuild_current_tab()
		)
		rvb.add_child(wear_b)
	else:
		var empty_cmp: Label = _dark_label("行囊暂无可替换的同阶法器。\n游历山道、药庐或秘藏石匣获宝后，将在此处并排呈列属性增减与【古宝蓝字特技】。", 16, Color("#CFD9DD"))
		rvb.add_child(empty_cmp)

	return hb


## ==================== Tab 2：【道途 · 奇门】（对开古籍双页布局） ====================
func _build_tab_specialization() -> void:
	var pages: Dictionary = _make_two_page_spread()
	var lv: VBoxContainer = pages["left"] as VBoxContainer
	var rv: VBoxContainer = pages["right"] as VBoxContainer

	var char_row: HBoxContainer = HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	lv.add_child(char_row)
	for cid: String in CampaignState.recruited_order:
		var cd: Dictionary = DataDB.get_character(cid)
		var cb: Button = _make_xuan_slip_button(
			("★ " if cid == selected_char_id else "") + DataDB.loc(str(cd.get("name_key", cid))),
			cid == selected_char_id
		)
		cb.pressed.connect(func() -> void:
			selected_char_id = cid
			rebuild_current_tab()
		)
		char_row.add_child(cb)

	var m: Dictionary = CampaignState.party_members.get(selected_char_id, {}) as Dictionary
	var cdef: Dictionary = DataDB.get_character(selected_char_id)
	var specs: Dictionary = cdef.get("specializations", {}) as Dictionary
	var active_sp: String = str(m.get("active_spec", "spec_a"))
	var unlocked_nodes: Array = m.get("unlocked_talents", []) as Array

	var spec_hb: HBoxContainer = HBoxContainer.new()
	spec_hb.add_theme_constant_override("separation", 14)
	lv.add_child(spec_hb)

	for skey: String in ["spec_a", "spec_b"]:
		var sp_def: Dictionary = specs.get(skey, {}) as Dictionary
		var is_cur: bool = (active_sp == skey)
		var scard: PanelContainer = PanelContainer.new()
		scard.custom_minimum_size = Vector2(384.0, 660.0)
		scard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb_scard: StyleBoxFlat = UIThemeBuilder.make_ebony_box(
			Color(0.14, 0.13, 0.11, 0.96),
			UIThemeBuilder.COL_BRONZE_GOLD if is_cur else UIThemeBuilder.COL_BRONZE_DIM,
			3 if is_cur else 1, 6
		)
		sb_scard.content_margin_left = 14.0
		sb_scard.content_margin_right = 14.0
		sb_scard.content_margin_top = 10.0
		sb_scard.content_margin_bottom = 10.0
		scard.add_theme_stylebox_override("panel", sb_scard)
		spec_hb.add_child(scard)

		var sv: VBoxContainer = VBoxContainer.new()
		sv.add_theme_constant_override("separation", 10)
		scard.add_child(sv)

		var stitle: Label = Label.new()
		stitle.text = "%s【%s】" % ["★ 当前生效 · " if is_cur else "", DataDB.loc(str(sp_def.get("name_key", skey)))]
		stitle.add_theme_font_size_override("font_size", 20)
		stitle.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if is_cur else UIThemeBuilder.COL_XUAN_WARM)
		sv.add_child(stitle)

		var sdesc: Label = Label.new()
		sdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sdesc.text = DataDB.loc(str(sp_def.get("desc_key", "")))
		sdesc.add_theme_font_size_override("font_size", 17)
		sv.add_child(sdesc)

		var sw_btn: Button = Button.new()
		sw_btn.text = "当前修习流派" if is_cur else "脱战一键切换至此专精"
		sw_btn.focus_mode = Control.FOCUS_NONE
		sw_btn.disabled = is_cur or NotifyHub.combat_active
		sw_btn.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			if CampaignState.switch_specialization(selected_char_id, skey):
				rebuild_current_tab()
		)
		sv.add_child(sw_btn)

		var bar_preview: Dictionary = sp_def.get("skill_bar", {}) as Dictionary
		var sk_txt: PackedStringArray = PackedStringArray(["◆ 专属快捷栏剑诀/仙术："])
		for k_slot: String in ["1", "2", "3", "4", "Q", "E"]:
			var skid: String = str(bar_preview.get(k_slot, ""))
			if skid != "":
				sk_txt.append("  [%s] %s" % [k_slot, DataDB.loc(str(DataDB.get_skill(skid).get("name_key", skid)))])
		var sk_lbl: Label = Label.new()
		sk_lbl.text = "\n".join(sk_txt)
		sk_lbl.add_theme_font_size_override("font_size", 16)
		sk_lbl.add_theme_color_override("font_color", Color("#9EE0C4"))
		sv.add_child(sk_lbl)

		for raw_nd: Variant in (sp_def.get("nodes", []) as Array):
			if raw_nd is Dictionary:
				var nd: Dictionary = raw_nd as Dictionary
				var nid: String = str(nd.get("id", ""))
				var lit: bool = is_cur and unlocked_nodes.has(nid)
				var nlbl: Label = Label.new()
				nlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nlbl.text = "%s 第%d层 ·【%s】：%s" % [
					"●" if lit else "○",
					int(nd.get("tier", 1)),
					DataDB.loc(str(nd.get("name_key", ""))),
					DataDB.loc(str(nd.get("desc_key", ""))),
				]
				nlbl.add_theme_font_size_override("font_size", 16)
				nlbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if lit else Color("#A59D92"))
				sv.add_child(nlbl)

	# 右页：奇门常驻光环阵法与 1~4 阵位编排
	rv.add_child(_dark_label("◆ 奇门常驻光环阵法（不绑地面范围，走位完全自由）：", 20, Color("#5A3B1E")))
	for fid: String in ["scatter", "tianfu", "dizai"]:
		var fdef: Dictionary = DataDB.get_formation(fid)
		var is_unlocked: bool = CampaignState.unlocked_formations.has(fid)
		var is_active: bool = (CampaignState.active_formation_id == fid)
		var fbox: PanelContainer = PanelContainer.new()
		var sb_fbox: StyleBoxFlat = UIThemeBuilder.make_ebony_box(
			Color(0.15, 0.13, 0.12, 0.95),
			UIThemeBuilder.COL_BRONZE_GOLD if is_active else UIThemeBuilder.COL_BRONZE_DIM,
			2 if is_active else 1, 5
		)
		sb_fbox.content_margin_left = 14.0
		sb_fbox.content_margin_right = 14.0
		sb_fbox.content_margin_top = 10.0
		sb_fbox.content_margin_bottom = 10.0
		fbox.add_theme_stylebox_override("panel", sb_fbox)
		rv.add_child(fbox)
		var fvb: VBoxContainer = VBoxContainer.new()
		fbox.add_child(fvb)
		var ftop: HBoxContainer = HBoxContainer.new()
		fvb.add_child(ftop)
		var flbl: Label = Label.new()
		flbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flbl.text = "%s【%s】%s" % ["★ " if is_active else "", DataDB.loc(str(fdef.get("name_key", fid))), "" if is_unlocked else "（破庙初阵解锁）"]
		flbl.add_theme_font_size_override("font_size", 19)
		flbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if is_active else UIThemeBuilder.COL_XUAN_WARM)
		ftop.add_child(flbl)

		var fbtn: Button = Button.new()
		fbtn.text = "已布阵" if is_active else "启用此阵"
		fbtn.focus_mode = Control.FOCUS_NONE
		fbtn.disabled = (not is_unlocked) or is_active or NotifyHub.combat_active
		fbtn.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			CampaignState.set_active_formation(fid)
			rebuild_current_tab()
		)
		ftop.add_child(fbtn)

		var fdesc: Label = Label.new()
		fdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fdesc.text = DataDB.loc(str(fdef.get("desc_key", "")))
		fdesc.add_theme_font_size_override("font_size", 16)
		fvb.add_child(fdesc)

	rv.add_child(_dark_label("◆ 四象阵位职责分配（点击【互换】自由调整玄武主坦位）：", 19, Color("#5A3B1E")))
	var cur_fdef: Dictionary = DataDB.get_formation(CampaignState.active_formation_id)
	for s_i: int in range(4):
		var slot_n: int = s_i + 1
		var occ_id: String = CampaignState.formation_slots[s_i]
		var smod: Dictionary = FormationRules.get_slot_modifiers(cur_fdef, slot_n)
		var shb: HBoxContainer = HBoxContainer.new()
		shb.add_theme_constant_override("separation", 10)
		rv.add_child(shb)

		var occ_name: String = DataDB.loc(str(DataDB.get_character(occ_id).get("name_key", ""))) if occ_id != "" else "（待同伴入队）"
		var slbl: Label = _dark_label(
			"%d号【%s】：%s（伤×%.2f / 承伤×%.2f / 杀意×%.2f）" % [
				slot_n, str(smod.get("role_title", "")), occ_name,
				float(smod.get("damage_mult", 1.0)), float(smod.get("damage_taken_mult", 1.0)), float(smod.get("threat_mult", 1.0)),
			],
			16, UIThemeBuilder.COL_INK_DARK
		)
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shb.add_child(slbl)

		if slot_n < 4:
			var swap_b: Button = Button.new()
			swap_b.text = "↕ 互换 %d/%d" % [slot_n, slot_n + 1]
			swap_b.focus_mode = Control.FOCUS_NONE
			swap_b.disabled = NotifyHub.combat_active
			swap_b.pressed.connect(func() -> void:
				if NotifyHub.combat_active:
					return
				CampaignState.swap_formation_slots(slot_n, slot_n + 1)
				rebuild_current_tab()
			)
			shb.add_child(swap_b)


## ==================== Tab 3：【行囊 · 剑匣】（对开古籍双页布局 + 完整蓝字对比） ====================
func _build_tab_inventory_and_sword_box() -> void:
	var pages: Dictionary = _make_two_page_spread()
	var lv: VBoxContainer = pages["left"] as VBoxContainer
	var rv: VBoxContainer = pages["right"] as VBoxContainer

	var filter_hb: HBoxContainer = HBoxContainer.new()
	filter_hb.add_theme_constant_override("separation", 8)
	lv.add_child(filter_hb)
	for fpair: Array in [["all", "全部"], ["equip", "兵甲灵佩"], ["pill", "丹药灵符"], ["mat", "灵材奇物"]]:
		var fk: String = str(fpair[0])
		var fb: Button = _make_xuan_slip_button(
			("★ " if selected_inv_filter == fk else "") + str(fpair[1]),
			selected_inv_filter == fk
		)
		fb.pressed.connect(func() -> void:
			selected_inv_filter = fk
			rebuild_current_tab()
		)
		filter_hb.add_child(fb)

	var sort_b: Button = _make_bronze_action_button("按品阶整理", Vector2(128.0, 36.0))
	sort_b.pressed.connect(func() -> void:
		CampaignState.sort_inventory_by_grade()
		rebuild_current_tab()
	)
	filter_hb.add_child(sort_b)

	var split_hb: HBoxContainer = HBoxContainer.new()
	split_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hb.add_theme_constant_override("separation", 12)
	lv.add_child(split_hb)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360.0, 700.0)
	split_hb.add_child(scroll)

	var list_v: VBoxContainer = VBoxContainer.new()
	list_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_v.add_theme_constant_override("separation", 6)
	scroll.add_child(list_v)

	var filtered_entries: Array[Dictionary] = []
	var visible_inv_ids: Array[String] = []
	for entry: Dictionary in CampaignState.inventory:
		var iid: String = str(entry.get("id", ""))
		var cnt: int = int(entry.get("count", 0))
		if cnt <= 0:
			continue
		var is_eq: bool = DataDB.equipment.has(iid)
		var idef: Dictionary = DataDB.get_any_item_or_equip(iid)
		var cat: String = str(idef.get("category", "equip" if is_eq else "material"))
		if selected_inv_filter == "equip" and not is_eq:
			continue
		if selected_inv_filter == "pill" and not ["instant_pill", "elixir", "talisman", "breakthrough"].has(cat):
			continue
		if selected_inv_filter == "mat" and (is_eq or ["instant_pill", "elixir", "talisman"].has(cat)):
			continue
		filtered_entries.append({
			"id": iid,
			"count": cnt,
			"idef": idef,
		})
		visible_inv_ids.append(iid)

	if visible_inv_ids.is_empty():
		selected_item_id = ""
	elif not visible_inv_ids.has(selected_item_id):
		selected_item_id = visible_inv_ids[0]

	if filtered_entries.is_empty():
		list_v.add_child(_dark_label("此分类下暂无器物或丹材。", 17, Color("#5B5248")))
	else:
		for fentry: Dictionary in filtered_entries:
			var iid: String = str(fentry["id"])
			var cnt: int = int(fentry["count"])
			var idef: Dictionary = fentry["idef"] as Dictionary
			var ibtn: Button = Button.new()
			ibtn.focus_mode = Control.FOCUS_NONE
			ibtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var iname: String = DataDB.loc(str(idef.get("name_key", iid)))
			var purify_tag: String = " [可入剑匣]" if str(idef.get("purify_into_item_id", "")) != "" else ""
			ibtn.text = "%s%s ×%d%s" % ["▶ " if selected_item_id == iid else "", iname, cnt, purify_tag]
			ibtn.pressed.connect(func() -> void:
				selected_item_id = iid
				rebuild_current_tab()
			)
			list_v.add_child(ibtn)

	# 右侧器物详情与 #8FD4E8 蓝字特技对比窗
	var detail_box: PanelContainer = PanelContainer.new()
	detail_box.custom_minimum_size = Vector2(412.0, 700.0)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_detail: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.15, 0.14, 0.13, 0.96), UIThemeBuilder.COL_BRONZE_DIM, 2, 6)
	sb_detail.content_margin_left = 14.0
	sb_detail.content_margin_right = 14.0
	sb_detail.content_margin_top = 10.0
	sb_detail.content_margin_bottom = 10.0
	detail_box.add_theme_stylebox_override("panel", sb_detail)
	split_hb.add_child(detail_box)

	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(detail_scroll)

	var dv: VBoxContainer = VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(dv)

	if selected_item_id != "" and CampaignState.get_item_count(selected_item_id) > 0:
		var sel_def: Dictionary = DataDB.get_any_item_or_equip(selected_item_id)
		var is_sel_eq: bool = DataDB.equipment.has(selected_item_id)
		var has_blue: bool = (str(sel_def.get("blue_stunt_id", "")) != "")
		var dtitle: Label = Label.new()
		dtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dtitle.text = "【%s】" % DataDB.loc(str(sel_def.get("name_key", selected_item_id)))
		dtitle.add_theme_font_size_override("font_size", 21)
		dtitle.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT if has_blue else UIThemeBuilder.COL_BRONZE_GOLD)
		dv.add_child(dtitle)

		var ddesc: Label = Label.new()
		ddesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ddesc.text = DataDB.loc(str(sel_def.get("desc_key", "")))
		ddesc.add_theme_font_size_override("font_size", 17)
		dv.add_child(ddesc)

		if is_sel_eq:
			var slot_s: String = str(sel_def.get("slot", "weapon"))
			var cmp_lbl: Label = Label.new()
			cmp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cmp_lbl.text = _format_equip_comparison(selected_char_id, sel_def, slot_s)
			cmp_lbl.add_theme_font_size_override("font_size", 16)
			cmp_lbl.add_theme_color_override("font_color", Color("#A4DEC4"))
			dv.add_child(cmp_lbl)

			var stunt_id_inv: String = str(sel_def.get("blue_stunt_id", ""))
			if stunt_id_inv != "":
				var st_def_inv: Dictionary = DataDB.get_skill(stunt_id_inv)
				var st_lbl_inv: Label = Label.new()
				st_lbl_inv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				st_lbl_inv.text = "★ 蓝字特技：【%s】\n%s" % [
					DataDB.loc(str(st_def_inv.get("name_key", stunt_id_inv))),
					DataDB.loc(str(st_def_inv.get("desc_key", ""))),
				]
				st_lbl_inv.add_theme_font_size_override("font_size", 16)
				st_lbl_inv.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT)
				dv.add_child(st_lbl_inv)

			for target_cid: String in CampaignState.recruited_order:
				var tname: String = DataDB.loc(str(DataDB.get_character(target_cid).get("name_key", target_cid)))
				var eq_b: Button = Button.new()
				eq_b.text = "由【%s】穿戴此器物" % tname
				eq_b.focus_mode = Control.FOCUS_NONE
				eq_b.disabled = NotifyHub.combat_active
				eq_b.pressed.connect(func() -> void:
					if NotifyHub.combat_active:
						return
					if CampaignState.equip_item_on_member(target_cid, selected_item_id):
						rebuild_current_tab()
				)
				dv.add_child(eq_b)
		else:
			var icat: String = str(sel_def.get("category", ""))
			if ["elixir", "instant_pill", "storage_pouch"].has(icat):
				var use_b: Button = Button.new()
				use_b.text = "开启搜刮【储物袋】" if icat == "storage_pouch" else "立即服用此丹药"
				use_b.focus_mode = Control.FOCUS_NONE
				use_b.disabled = NotifyHub.combat_active
				use_b.pressed.connect(func() -> void:
					if NotifyHub.combat_active:
						return
					CampaignState.use_out_of_combat_item(selected_item_id)
					rebuild_current_tab()
				)
				dv.add_child(use_b)

			if icat == "instant_pill" or icat == "talisman":
				for qslot: String in ["5", "6"]:
					var bind_b: Button = Button.new()
					bind_b.text = "装入快捷丹符槽 [%s]" % qslot
					bind_b.focus_mode = Control.FOCUS_NONE
					bind_b.disabled = NotifyHub.combat_active
					bind_b.pressed.connect(func() -> void:
						if NotifyHub.combat_active:
							return
						if qslot == "5":
							CampaignState.quick_pill_5_id = selected_item_id
						else:
							CampaignState.quick_pill_6_id = selected_item_id
						CampaignState.inventory_updated.emit()
						rebuild_current_tab()
					)
					dv.add_child(bind_b)
			if str(sel_def.get("purify_into_item_id", "")) != "":
				var pur_b: Button = Button.new()
				pur_b.text = "置入【断玉剑匣】蕴灵提纯（历战3场化极品）"
				pur_b.focus_mode = Control.FOCUS_NONE
				pur_b.disabled = (not CampaignState.sword_box_slot.is_empty()) or NotifyHub.combat_active
				pur_b.pressed.connect(func() -> void:
					if NotifyHub.combat_active:
						return
					if CampaignState.start_sword_box_purify(selected_item_id):
						if audio_director != null:
							audio_director.play_sfx("sfx_sword_box_hum", AudioDirector.TIER_A, true)
						rebuild_current_tab()
				)
				dv.add_child(pur_b)
	else:
		var empty_detail: Label = Label.new()
		empty_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_detail.text = "（当前分类暂无可检视之器物或丹材）"
		empty_detail.add_theme_font_size_override("font_size", 17)
		empty_detail.add_theme_color_override("font_color", Color("#B8B0A0"))
		dv.add_child(empty_detail)

	# 右页：【断玉剑匣 · 混元提纯暗格】与丹道图谱
	rv.add_child(_dark_label("◆ 绝密古宝【断玉剑匣 · 混元提纯暗格】：", 21, Color("#23483E")))
	rv.add_child(_dark_label("将焦黑废丹、凡品凝气草、腐骨幽花或地摊蒙尘残铁片放入匣中，每历 3 场斗法（或引灵石碑休整）即可汲取游离混沌气淬炼为无瑕极品！", 16, UIThemeBuilder.COL_INK_DARK))

	var box_panel: PanelContainer = PanelContainer.new()
	box_panel.custom_minimum_size = Vector2(700.0, 185.0)
	var sb_box: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.10, 0.16, 0.14, 0.97), UIThemeBuilder.COL_JADE_GREEN, 2, 6)
	sb_box.content_margin_left = 14.0
	sb_box.content_margin_right = 14.0
	sb_box.content_margin_top = 10.0
	sb_box.content_margin_bottom = 10.0
	box_panel.add_theme_stylebox_override("panel", sb_box)
	rv.add_child(box_panel)

	var bvb: VBoxContainer = VBoxContainer.new()
	bvb.alignment = BoxContainer.ALIGNMENT_CENTER
	bvb.add_theme_constant_override("separation", 10)
	box_panel.add_child(bvb)

	if CampaignState.sword_box_slot.is_empty():
		var empty_l: Label = Label.new()
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_l.text = "【一号蕴灵暗格：空置待纳】\n（可在左页行囊选中【焦黑废丹】或灵材点击置入）"
		empty_l.add_theme_font_size_override("font_size", 18)
		empty_l.add_theme_color_override("font_color", Color("#9EE0C4"))
		bvb.add_child(empty_l)
	else:
		var in_id: String = str(CampaignState.sword_box_slot.get("input_item_id", ""))
		var out_id: String = str(CampaignState.sword_box_slot.get("output_item_id", ""))
		var rem_b: int = int(CampaignState.sword_box_slot.get("battles_remaining", 0))
		var in_name: String = DataDB.loc(str(DataDB.get_any_item_or_equip(in_id).get("name_key", in_id)))
		var out_name: String = DataDB.loc(str(DataDB.get_any_item_or_equip(out_id).get("name_key", out_id)))

		var slot_l: Label = Label.new()
		slot_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_l.text = "正在淬炼：【%s】 ──▶ 【%s】\n%s" % [
			in_name, out_name,
			("已淬炼圆满！可立即开匣取宝" if rem_b <= 0 else ("尚需经历 %d 场真实战斗（或石碑休整）" % rem_b)),
		]
		slot_l.add_theme_font_size_override("font_size", 18)
		slot_l.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if rem_b <= 0 else Color("#B8E6D4"))
		bvb.add_child(slot_l)

		var claim_b: Button = Button.new()
		claim_b.text = "开匣收取提纯至宝"
		claim_b.focus_mode = Control.FOCUS_NONE
		claim_b.disabled = (rem_b > 0) or NotifyHub.combat_active
		claim_b.pressed.connect(func() -> void:
			if NotifyHub.combat_active:
				return
			if CampaignState.claim_sword_box_output():
				if audio_director != null:
					audio_director.play_sfx("sfx_alchemy_success", AudioDirector.TIER_A, true)
				rebuild_current_tab()
		)
		bvb.add_child(claim_b)

	rv.add_child(_dark_label("◆ 已参悟丹道图谱（前往济世药庐青铜丹炉即可开炉控火）：", 20, Color("#5A3B1E")))
	for rid: String in CampaignState.unlocked_recipes:
		var rdef: Dictionary = DataDB.get_recipe(rid)
		var is_qb: bool = CampaignState.quick_brew_recipes.has(rid)
		var ing_parts: PackedStringArray = PackedStringArray()
		for raw_ing: Variant in (rdef.get("ingredients", []) as Array):
			if raw_ing is Dictionary:
				var ing: Dictionary = raw_ing as Dictionary
				var mid: String = str(ing.get("item_id", ""))
				ing_parts.append("%s×%d(存%d)" % [
					DataDB.loc(str(DataDB.get_any_item_or_equip(mid).get("name_key", mid))),
					int(ing.get("count", 1)),
					CampaignState.get_item_count(mid),
				])
		rv.add_child(_dark_label(
			"· 【%s】%s\n   配伍：%s" % [
				DataDB.loc(str(rdef.get("name_key", rid))),
				" ★已解锁一键完美速炼" if is_qb else "（待首炼15s文武控火）",
				" + ".join(ing_parts),
			],
			16, Color("#23483E") if is_qb else UIThemeBuilder.COL_INK_DARK
		))


func _equip_stat_labels() -> Dictionary:
	return {
		"hp": "气血",
		"mp": "真元",
		"phys_power": "兵刃强度",
		"spell_power": "仙术强度",
		"heal_power": "治疗强度",
		"defense": "护甲抗性",
		"crit_rating": "暴击等级",
		"haste_rating": "急速等级",
		"mastery_rating": "破罡精通",
		"vers_rating": "御守等级",
	}


func _format_equip_comparison(char_id: String, new_def: Dictionary, slot_s: String) -> String:
	var m: Dictionary = CampaignState.party_members.get(char_id, {}) as Dictionary
	var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
	var cur_id: String = str(eq_map.get(slot_s, ""))
	var cur_def: Dictionary = DataDB.get_equipment(cur_id)
	var cur_name: String = DataDB.loc(str(cur_def.get("name_key", ""))) if cur_id != "" else "无"
	var lines: PackedStringArray = PackedStringArray([
		"【与 %s 当前穿戴（%s）对比】：" % [
			DataDB.loc(str(DataDB.get_character(char_id).get("name_key", char_id))),
			cur_name,
		]
	])
	var n_st: Dictionary = new_def.get("stats", {}) as Dictionary
	var c_st: Dictionary = cur_def.get("stats", {}) as Dictionary
	var labels: Dictionary = _equip_stat_labels()
	for k_var: Variant in labels.keys():
		var k: String = str(k_var)
		var nv: float = float(n_st.get(k, 0.0))
		var cv: float = float(c_st.get(k, 0.0))
		if nv != 0.0 or cv != 0.0:
			var diff: float = nv - cv
			lines.append("  · %s：%.0f (%s%.0f)" % [str(labels[k]), nv, "+" if diff >= 0.0 else "", diff])
	return "\n".join(lines)


## ==================== Tab 5：【问道手札】（对开古籍双页布局） ====================
func _build_tab_journal() -> void:
	var pages: Dictionary = _make_two_page_spread()
	var lv: VBoxContainer = pages["left"] as VBoxContainer
	var rv: VBoxContainer = pages["right"] as VBoxContainer

	var vol_hb: HBoxContainer = HBoxContainer.new()
	vol_hb.add_theme_constant_override("separation", 8)
	lv.add_child(vol_hb)
	for vpair: Array in [["main", "求仙主脉"], ["side", "红尘奇遇"], ["relic", "残碑秘辛"], ["lore", "博物风土"]]:
		var vk: String = str(vpair[0])
		var vb: Button = _make_xuan_slip_button(
			("★ " if selected_journal_vol == vk else "") + str(vpair[1]),
			selected_journal_vol == vk
		)
		vb.pressed.connect(func() -> void:
			selected_journal_vol = vk
			rebuild_current_tab()
		)
		vol_hb.add_child(vb)

	for qid_var: Variant in CampaignState.quest_states.keys():
		var qid: String = str(qid_var)
		var qst: String = str(CampaignState.quest_states[qid])
		if qst == "inactive":
			continue
		var qdef: Dictionary = DataDB.quests.get(qid, {}) as Dictionary
		if str(qdef.get("volume", "main")) != selected_journal_vol:
			continue
		var stages_d: Dictionary = qdef.get("stages", {}) as Dictionary
		var st_txt: String = DataDB.loc(str(stages_d.get(qst, qst)))
		lv.add_child(_dark_label(
			"【%s】\n  笔录：%s" % [DataDB.loc(str(qdef.get("title_key", qid))), st_txt],
			18, Color("#5A3320")
		))

	for clue_id: String in CampaignState.unlocked_clues:
		var cdef: Dictionary = DataDB.journal_entries.get(clue_id, {}) as Dictionary
		if str(cdef.get("volume", "main")) != selected_journal_vol:
			continue
		var entry_lbl: Label = _dark_label(
			"◆ %s\n%s" % [DataDB.loc(str(cdef.get("title_key", clue_id))), DataDB.loc(str(cdef.get("body_key", "")))],
			17, UIThemeBuilder.COL_INK_DARK
		)
		lv.add_child(entry_lbl)

	# 右页：五阶羁绊词牌 + 五大势力声望 + 朱砂因果水墨签 + 前尘绘卷 CG 回看
	rv.add_child(_dark_label("◆ 同道五阶羁绊词牌（二阶解锁 G 键双人羁绊合击）：", 20, Color("#5A3B1E")))
	var shown_bonds: int = 0
	for comp_id: String in ["shen_qinghe", "pei_zhao"]:
		if not CampaignState.recruited_order.has(comp_id):
			continue
		shown_bonds += 1
		var btier: int = clampi(int(CampaignState.companion_bonds.get(comp_id, 1)), 1, 5)
		var cname: String = DataDB.loc(str(DataDB.get_character(comp_id).get("name_key", comp_id)))
		var ult_note: String = "（已开启合击【青莲引剑】）" if comp_id == "shen_qinghe" and btier >= 2 else ""
		rv.add_child(_dark_label("  · %s：%s %s" % [cname, tr(CampaignState.BOND_TIER_KEYS[btier - 1]), ult_note], 18, Color("#23483E")))
	if shown_bonds == 0:
		rv.add_child(_dark_label("  （游历青岚结识同道后录入金兰词牌）", 16, Color("#5B5248")))

	rv.add_child(_dark_label("◆ 九州五大势力声望阶位：", 20, Color("#5A3B1E")))
	for fid_var: Variant in DataDB.factions.keys():
		var fid: String = str(fid_var)
		var fdef: Dictionary = DataDB.factions[fid] as Dictionary
		var pts: int = int(CampaignState.faction_reputation.get(fid, 0))
		var tinfo: Dictionary = EconomyRules.get_reputation_tier_info(pts)
		rv.add_child(_dark_label(
			"  · %s：%s（%d）" % [DataDB.loc(str(fdef.get("name_key", fid))), tr(str(tinfo.get("name_key", "REP_TIER_0"))), pts],
			16, UIThemeBuilder.COL_INK_DARK
		))

	rv.add_child(_dark_label("◆ 道心轨迹 · 朱砂因果水墨签（无功利属性数字，铭刻本心抉择）：", 20, Color("#8E2822")))
	if CampaignState.ink_seals.is_empty():
		rv.add_child(_dark_label("  （尚未落印重大章节因果签）", 16, Color("#5B5248")))
	else:
		for seal_id: String in CampaignState.ink_seals:
			var sdef: Dictionary = DataDB.ink_seals.get(seal_id, {}) as Dictionary
			rv.add_child(_dark_label(
				"  印鉴：%s\n  “%s”" % [DataDB.loc(str(sdef.get("name_key", seal_id))), DataDB.loc(str(sdef.get("poem_key", "")))],
				17, Color("#8E2822")
			))

	rv.add_child(_dark_label("◆ 前尘绘卷（全屏动态 CG 回看）：", 19, Color("#5A3B1E")))
	var cg_btn: Button = _make_bronze_action_button(
		"重温绘卷一：《破庙剑鸣会少年》" if CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple") else "绘卷一：破庙初会解锁后可随时鉴赏",
		Vector2(420.0, 42.0)
	)
	cg_btn.disabled = (not CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple")) or NotifyHub.combat_active
	cg_btn.pressed.connect(func() -> void:
		if NotifyHub.combat_active:
			return
		close_casket()
		replay_cg_requested.emit("cg_ch01_ruined_temple")
	)
	rv.add_child(cg_btn)


## ==================== 宣纸双页与铜器按钮通用构造 ====================
func _make_two_page_spread() -> Dictionary:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	_content_root.add_child(cols)

	var l_scroll: ScrollContainer = ScrollContainer.new()
	l_scroll.custom_minimum_size = Vector2(812.0, 816.0)
	l_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(l_scroll)

	var l_pad: MarginContainer = MarginContainer.new()
	l_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_pad.add_theme_constant_override("margin_left", 14)
	l_pad.add_theme_constant_override("margin_right", 14)
	l_pad.add_theme_constant_override("margin_top", 12)
	l_pad.add_theme_constant_override("margin_bottom", 12)
	l_scroll.add_child(l_pad)

	var lv: VBoxContainer = VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 10)
	l_pad.add_child(lv)

	var spine_spacer: Control = Control.new()
	spine_spacer.custom_minimum_size = Vector2(48.0, 10.0)
	cols.add_child(spine_spacer)

	var r_scroll: ScrollContainer = ScrollContainer.new()
	r_scroll.custom_minimum_size = Vector2(768.0, 816.0)
	r_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(r_scroll)

	var r_pad: MarginContainer = MarginContainer.new()
	r_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_pad.add_theme_constant_override("margin_left", 14)
	r_pad.add_theme_constant_override("margin_right", 14)
	r_pad.add_theme_constant_override("margin_top", 12)
	r_pad.add_theme_constant_override("margin_bottom", 12)
	r_scroll.add_child(r_pad)

	var rv: VBoxContainer = VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 10)
	r_pad.add_child(rv)

	return {"left": lv, "right": rv}


func _make_xuan_slip_button(txt: String, is_selected: bool) -> Button:
	var b: Button = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(118.0, 34.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("#2C231A") if is_selected else Color("#C8B99E")
	sb.border_color = UIThemeBuilder.COL_BRONZE_GOLD if is_selected else Color("#7E6849")
	sb.set_border_width_all(2 if is_selected else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if is_selected else UIThemeBuilder.COL_INK_DARK)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _make_bronze_action_button(txt: String, min_sz: Vector2) -> Button:
	var b: Button = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_sz
	var sb_n: StyleBoxFlat = StyleBoxFlat.new()
	sb_n.bg_color = Color("#74634A")
	sb_n.border_color = Color("#433524")
	sb_n.set_border_width_all(2)
	sb_n.set_corner_radius_all(3)
	sb_n.content_margin_left = 8.0
	sb_n.content_margin_right = 8.0
	sb_n.content_margin_top = 3.0
	sb_n.content_margin_bottom = 3.0

	var sb_h: StyleBoxFlat = sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color("#8D7858")
	sb_h.border_color = UIThemeBuilder.COL_BRONZE_GOLD

	var sb_d: StyleBoxFlat = sb_n.duplicate() as StyleBoxFlat
	sb_d.bg_color = Color(0.56, 0.50, 0.42, 0.55)
	sb_d.border_color = Color(0.38, 0.33, 0.27, 0.50)

	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("disabled", sb_d)
	b.add_theme_color_override("font_color", Color("#201B18"))
	b.add_theme_color_override("font_hover_color", Color("#14100D"))
	b.add_theme_color_override("font_disabled_color", Color(0.26, 0.22, 0.18, 0.60))
	b.add_theme_font_size_override("font_size", 17 if txt.length() <= 2 else 16)
	return b


func _dark_label(txt: String, fsize: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", maxi(UIThemeBuilder.FS_MIN, fsize))
	l.add_theme_color_override("font_color", col)
	return l
